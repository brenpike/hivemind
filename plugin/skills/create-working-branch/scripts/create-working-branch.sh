#!/usr/bin/env bash
#
# create-working-branch: THIN executable entrypoint (ADR-0020) that creates or confirms the
# working branch in ONE process. It reads the tree state, trunk's ref, the current branch, the
# base commit, and the branch's upstream once, refuses before any change, then switches HEAD onto
# the branch and verifies the result with the values it checked. A change is a write to a branch
# ref, HEAD, the index, the work tree or git config.
#
# INPUT (`--flag value` form only; each flag exactly once; unknown, duplicate, or missing flags
# and invalid enum values all give the fixed usage blocker):
#   --base <branch>              REQUIRED. Branch the working branch is created from.
#   --branch <branch>            REQUIRED. Working branch name. Must differ from base and from
#                                trunk.
#   --classification <kind>      REQUIRED. feature|bugfix|hotfix|refactor|chore|docs|test|ci.
#                                Checked as an enum only; the taxonomy and naming check is the
#                                caller's, made before the call.
#   --trunk-freshness <state>    REQUIRED. fresh|stale|skipped. stale and skipped add a warning.
#   --trunk <branch>             REQUIRED. Resolved trunk branch name. It may be absent locally;
#                                when it names refs that exist, they must be one ref.
# base, branch and trunk pass hivemind_assert_identifier (_shared/allowlist.sh: non-empty, no
# leading `-`, no `..`, charset ^[A-Za-z0-9._/-]+$) before any git command runs, base and branch
# first (`base or working_branch contains characters outside the safe allowlist`), then trunk
# (`trunk contains characters outside the safe allowlist`). Then, still before any git command,
# a branch equal to base stops with `working_branch equals base`, and a trunk that names the
# branch stops with `working_branch equals trunk`. A name or ref names the branch by ref identity,
# not by its text: see the NAME LOOKUP paragraph in _shared/git-refusals.sh. Without a git
# command, that is the spellings <branch>, heads/<branch> and refs/heads/<branch>. A remote
# spelling such as origin/<branch> is caught later, by the trunk ref check. A name that only
# ends with `/<branch>`, such as team/<branch>, is another branch. Case is ignored because a
# case-insensitive file system stores refs/heads/Main and refs/heads/main as one file. A git
# identifier read from the repository (the branch upstream, and each ref end read for trunk) is
# captured into a shell variable and used only as "$var", per
# ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Shell Identifier Discipline).
#
# WHY (trunk): the script, not the caller's taxonomy check, holds the stop on a working branch
# that is trunk, so no caller can switch HEAD onto trunk through it. A run that starts on trunk
# still moves off it, because only the target branch is compared with trunk. The stop keys on
# the refs trunk names, not on the caller's spelling: the same branch has many spellings, and
# git turns each one into the same ref. The stop compares refs as well as names: a commit on HEAD
# updates the ref at the end of HEAD's symbolic-ref chain, so a symbolic refs/heads/<branch> that
# points at trunk would carry commits onto trunk under another name. The alias refusal below
# makes the ref HEAD's commits update the branch's own ref. The trunk refusal covers every ref
# trunk names, symbolic or not, dangling or not. Trunk is read once, before any change, so a
# chain whose end is the branch the run would create stops before the run creates it.
#
# REFUSALS (fixed blockers, checked in this order, before any change; ADR-0037 invariant 1).
# A change is a write to a branch ref, HEAD, the index, the work tree or git config:
#   in progress  a merge (MERGE_HEAD), rebase (rebase-merge, rebase-apply, REBASE_HEAD),
#                cherry-pick (CHERRY_PICK_HEAD), revert (REVERT_HEAD), cherry-pick or revert
#                sequence (sequencer), or bisect (BISECT_START, BISECT_LOG), each looked up with
#                `git rev-parse --git-path` so a linked worktree reads its own state.
#   unmerged     `git ls-files -u` reports any path.
#   dirty        `git status --porcelain=v1 --untracked-files=normal` reports a staged, unstaged,
#                or untracked path. Ignored files are allowed. The run never commits, stashes, or
#                discards an edit it did not make, so a dirty tree stops here.
#   alias        refs/heads/<branch> is a symbolic ref, dangling or not (`working_branch is a
#                symbolic ref`), read with `git symbolic-ref --quiet`. A branch name git cannot
#                read as a branch ref stops with `cannot read working_branch`.
#   trunk        a ref trunk names (see TRUNK REF below) is the branch's own ref or its image on
#                a remote that `git remote` lists (`working_branch equals trunk`). Every ref
#                trunk names is checked for this first. Then, when the refs
#                trunk names that exist are more than one ref, the run stops with `cannot read
#                trunk`; a dangling end is not counted for this. When git cannot read
#                refs/heads/<trunk>, or prints no end for a symbolic candidate, the run also
#                stops with `cannot read trunk`. A trunk that names no ref passes.
#   worktree     the branch is checked out in another worktree.
#   base         the base does not resolve to a commit (see BASE below).
#
# BASE is resolved once, in order: refs/heads/<base>, then <base>^{commit}, then, when
# remote.origin.url is set, `git fetch origin +refs/heads/<base>:refs/remotes/origin/<base>`
# followed by refs/remotes/origin/<base>. The resolved full object id is the start point; the
# base name is never resolved again.
#
# TRUNK REF is read once, after the alias refusal and before the current branch is read, with
# git's own lookup order for a name (gitrevisions), six rules: <trunk>, refs/<trunk>,
# refs/tags/<trunk>, refs/heads/<trunk>, refs/remotes/<trunk>, refs/remotes/<trunk>/HEAD. A
# candidate that `git symbolic-ref --quiet` reads as a symbolic ref names the end of its chain as
# git prints it, even when that end does not exist yet. A candidate under refs/ that is not
# symbolic names itself when `git show-ref --verify` finds it. Any other candidate names no ref.
# Two candidates that end at the same ref name one ref. Trunk is never read again.
#
# ORDER NOTE: a trunk spelled as a remote, such as origin/<branch>, now stops at this trunk ref
# check, not at the earlier no-git name check. It still stops before any change. Only the order
# of blockers on an input with more than one fault changes. No blocker text changes.
#
# ACTION:
#   already on the branch   no switch (created false). The upstream rule below still applies.
#   branch exists           `git switch --no-guess <branch>` (created false), then the upstream
#                           rule below.
#   branch is new           `git switch --no-track -c <branch> <base commit>` (created true),
#                           then HEAD must be the base commit.
#   UPSTREAM RULE: an existing branch keeps its upstream only when branch.<b>.remote passes the
#   identifier gate and is not `.` and branch.<b>.merge is refs/heads/<b>, that is, when the
#   upstream is <remote>/<branch>. Any other upstream, including a half-set one, is removed by
#   unsetting both keys.
#   Afterwards HEAD must be refs/heads/<branch> and resolve to a commit. After a change, the only
#   blockers are failed git actions and these result checks; none of them refuses the request.
#   Only the current worktree's HEAD moves, also from a detached HEAD or a non-trunk scratch
#   branch such as a brood child's boot branch. No worktree is created or removed; worktree
#   ownership stays with spawn-brood.
#
# WHY (no-track and unset-upstream): a working branch that tracks trunk lets a plain `git push`,
# or a force-with-lease retry against the tracked upstream, target trunk. Creating the branch
# from a remote-tracking base such as origin/main would make it track trunk under
# branch.autoSetupMerge, so creation always passes --no-track and starts from the object id. An
# existing branch may already track trunk from an earlier run or a manual checkout, so its
# upstream is removed unless it names the branch itself. The first push then records the
# branch's own upstream (push-branch.sh).
#
# OUTPUT on success (exit 0), on stdout in ONE write:
#   branch: <b>
#   commit: <full sha of HEAD>
#   created: true|false
#   warning: <fixed text>        only for --trunk-freshness stale or skipped
# EXIT CONTRACT:
#   0  routing lines on stdout
#   1  `blocker: <fixed reason>` as the ONLY stderr line, NOTHING on stdout. Every git call
#      discards git's own stderr, so no git message (whose wording varies by git version and
#      load) precedes or follows it. Blocker text never echoes a caller- or repository-supplied
#      value.
#
# NOT CHECKED: a post-checkout hook or the operator can change HEAD, the index, or files after
# the switch. Repo hooks, local refs, git config, and the operator are trusted under
# ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Shell Identifier Discipline); the final
# HEAD check catches a moved HEAD, and anything else is a recorded residual. Trunk is read once,
# before any change, and never again, so a name read through HEAD, such as HEAD itself, is checked
# against the branch HEAD was on before the run; after the run it names the working branch. git
# 2.25 shows only the end of a symbolic-ref chain, so a link in the chain, such as one through
# HEAD, cannot be seen. A trunk name that names no candidate ref names no ref, object names
# included; nothing ties it to the branch. The six-rule lookup order
# is mirrored from git, not asked of git, so a lookup rule a future git adds is missed. A
# candidate other than refs/heads/<trunk> that git cannot read, such as a corrupt ref or a chain
# deeper than git follows, names no ref. The base fetch, part of the base refusal and the last
# refusal, writes refs/remotes/origin/<base>, FETCH_HEAD and objects before its result is checked.
# Those are not changes in this sense, and a rerun gives the same result. The `working_branch
# equals base` stop compares the names as given, so a base that spells the branch another way,
# such as refs/heads/<branch>, passes it, and the run switches onto the branch the caller named;
# later commits then land on that branch, which is also the base. The impact is bounded: the
# caller named that branch, and the trunk stop, which keys on every ref trunk names, still keeps
# trunk off. Comparing the base's canonical ref would add a stop, and the stops here are not to
# grow, so this is a recorded residual.
#
# Conventions (ADR-0020 thin entrypoint): `set -euo pipefail`, an EXIT trap ending in a
# guaranteed-zero `:`, self-location via `cd && pwd -P`, NO `realpath`/`readlink`; bash 3.2
# compatible (no mapfile / associative arrays / ${var,,}). Plain `git` from the current folder,
# never `git -C` (ADR-0037 decision 25). The name rule, the in-progress, unmerged and dirty
# checks, and the TRUNK REF walk come from _shared/git-refusals.sh; this script maps their
# results to its own blockers.

set -euo pipefail
trap ':' EXIT

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# layout plugin/skills/create-working-branch/scripts/ => ../../_shared is the shared-library dir.
# cd && pwd -P is portable (no realpath/readlink). NO ${CLAUDE_PLUGIN_ROOT} inside an engine
# script. SOURCE-OR-DIE: a missing/unparseable library fails closed before any git command.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
shared_dir="$(CDPATH= cd -- "$script_dir/../../_shared" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve skills/_shared from the script directory; refusing to proceed"
[ -f "$shared_dir/allowlist.sh" ] || blocker "required shared library missing: skills/_shared/allowlist.sh; refusing to proceed"
. "$shared_dir/allowlist.sh" || blocker "failed to source skills/_shared/allowlist.sh (unparseable); refusing to proceed"
[ -f "$shared_dir/git-refusals.sh" ] || blocker "required shared library missing: skills/_shared/git-refusals.sh; refusing to proceed"
. "$shared_dir/git-refusals.sh" || blocker "failed to source skills/_shared/git-refusals.sh (unparseable); refusing to proceed"

export LC_ALL=C
export GIT_TERMINAL_PROMPT=0

usage_reason='invalid arguments; usage: create-working-branch.sh --base <branch> --branch <branch> --classification feature|bugfix|hotfix|refactor|chore|docs|test|ci --trunk-freshness fresh|stale|skipped --trunk <branch>'

base_name=''
base_seen=false
branch_name=''
branch_seen=false
classification=''
classification_seen=false
trunk_freshness=''
trunk_freshness_seen=false
trunk_name=''
trunk_seen=false
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || blocker "$usage_reason"
  case "$1" in
    --base)
      [ "$base_seen" = false ] || blocker "$usage_reason"
      base_name="$2"
      base_seen=true
      ;;
    --branch)
      [ "$branch_seen" = false ] || blocker "$usage_reason"
      branch_name="$2"
      branch_seen=true
      ;;
    --classification)
      [ "$classification_seen" = false ] || blocker "$usage_reason"
      classification="$2"
      classification_seen=true
      ;;
    --trunk-freshness)
      [ "$trunk_freshness_seen" = false ] || blocker "$usage_reason"
      trunk_freshness="$2"
      trunk_freshness_seen=true
      ;;
    --trunk)
      [ "$trunk_seen" = false ] || blocker "$usage_reason"
      trunk_name="$2"
      trunk_seen=true
      ;;
    *)
      blocker "$usage_reason"
      ;;
  esac
  shift 2
done

[ "$base_seen" = true ] && [ "$branch_seen" = true ] || blocker "$usage_reason"
[ "$classification_seen" = true ] && [ "$trunk_freshness_seen" = true ] || blocker "$usage_reason"
[ "$trunk_seen" = true ] || blocker "$usage_reason"
case "$classification" in
  feature|bugfix|hotfix|refactor|chore|docs|test|ci) ;;
  *) blocker "$usage_reason" ;;
esac
warning_text=''
case "$trunk_freshness" in
  fresh) ;;
  stale) warning_text='trunk is stale or diverged from origin; proceeding as acknowledged at preflight' ;;
  skipped) warning_text='trunk freshness check was skipped' ;;
  *) blocker "$usage_reason" ;;
esac

identifier_reason='base or working_branch contains characters outside the safe allowlist'
hivemind_assert_identifier "$base_name" || blocker "$identifier_reason"
hivemind_assert_identifier "$branch_name" || blocker "$identifier_reason"
hivemind_assert_identifier "$trunk_name" || blocker "trunk contains characters outside the safe allowlist"
[ "$branch_name" != "$base_name" ] || blocker "working_branch equals base"
trunk_match_rc=0
hivemind_ref_names_branch "$trunk_name" "$branch_name" || trunk_match_rc=$?
case "$trunk_match_rc" in
  0) blocker "working_branch equals trunk" ;;
  1) ;;
  *) blocker "cannot compare working_branch with trunk" ;;
esac

# read_config_value <key>
#   Sets config_value to the value of <key> (empty when the key is unset). Any git config failure
#   other than "key not found" (exit 1) is a blocker. Runs in the main shell so blocker exits it.
config_value=''
read_config_value() {
  local config_key="$1"
  local config_rc=0
  config_value="$(git config --get "$config_key" 2>/dev/null)" || config_rc=$?
  case "$config_rc" in
    0) ;;
    1) config_value='' ;;
    *) blocker "cannot read git config" ;;
  esac
}

# unset_config_key <key>
#   Removes every value of <key> from the repository git config. "Key not set" (exit 5) is not a
#   failure; any other failure is a blocker. Runs in the main shell so blocker exits it.
unset_config_key() {
  local config_key="$1"
  local unset_rc=0
  git config --unset-all "$config_key" 2>/dev/null || unset_rc=$?
  case "$unset_rc" in
    0|5) ;;
    *) blocker "could not unset an upstream that does not match the working branch" ;;
  esac
}

# refuse_operation_in_progress
#   Blocks when hivemind_find_operation_in_progress finds a merge, rebase, cherry-pick, revert,
#   sequence or bisect, with its fixed reason. Runs in the main shell so blocker exits it.
refuse_operation_in_progress() {
  local operation_rc=0
  hivemind_find_operation_in_progress || operation_rc=$?
  case "$operation_rc" in
    0) ;;
    1) blocker "$HIVEMIND_OPERATION_REASON" ;;
    *) blocker "cannot read the repository state" ;;
  esac
}

# refuse_unmerged_paths
#   Blocks when the index has unmerged paths. Runs in the main shell so blocker exits it.
refuse_unmerged_paths() {
  local unmerged_rc=0
  hivemind_check_unmerged_paths || unmerged_rc=$?
  case "$unmerged_rc" in
    0) ;;
    1) blocker "the index has unmerged paths" ;;
    *) blocker "cannot read the index" ;;
  esac
}

# refuse_dirty_tree
#   Blocks when `git status` reports a staged, unstaged, or untracked path, checked in that
#   order. Ignored files are not reported and are allowed. Runs in the main shell so blocker
#   exits it.
refuse_dirty_tree() {
  local dirty_rc=0
  hivemind_read_dirty_kinds || dirty_rc=$?
  case "$dirty_rc" in
    0|1) ;;
    *) blocker "cannot read the working tree status" ;;
  esac
  [ "$HIVEMIND_DIRTY_STAGED" = false ] || blocker "the index has staged changes"
  [ "$HIVEMIND_DIRTY_UNSTAGED" = false ] || blocker "the working tree has unstaged changes"
  [ "$HIVEMIND_DIRTY_UNTRACKED" = false ] || blocker "the working tree has untracked files"
}

# refuse_symbolic_branch
#   Blocks when refs/heads/<branch> is a symbolic ref. `git symbolic-ref --quiet` exits 0 for a
#   symbolic ref, dangling or not, and 1 for a ref that is not symbolic or does not exist. Runs in
#   the main shell so blocker exits it.
refuse_symbolic_branch() {
  local alias_rc=0
  git symbolic-ref --quiet "refs/heads/$branch_name" >/dev/null 2>&1 || alias_rc=$?
  case "$alias_rc" in
    0) blocker "working_branch is a symbolic ref" ;;
    1) ;;
    *) blocker "cannot read working_branch" ;;
  esac
}

# refuse_trunk_ref
#   Reads every ref trunk names, once, with hivemind_resolve_name_refs. Blocks when any of them
#   names the branch, when git cannot read trunk, then when the ones that exist are more than one
#   ref. Runs in the main shell so blocker exits it.
refuse_trunk_ref() {
  local trunk_rc=0
  hivemind_resolve_name_refs "$trunk_name" "$branch_name" || trunk_rc=$?
  case "$trunk_rc" in
    0) ;;
    1) blocker "working_branch equals trunk" ;;
    3) blocker "cannot compare working_branch with trunk" ;;
    *) blocker "cannot read trunk" ;;
  esac
  [ "$HIVEMIND_NAME_AMBIGUOUS" = false ] || blocker "cannot read trunk"
}

# resolve_commit <revision>
#   Sets resolved_commit to the full object id <revision> names as a commit, or to empty when it
#   names none.
resolved_commit=''
resolve_commit() {
  local revision_name="$1"
  resolved_commit="$(git rev-parse --verify --quiet "$revision_name^{commit}" 2>/dev/null)" || resolved_commit=''
}

# is_full_object_id <value>
#   Succeeds when <value> is a full 40- or 64-digit lowercase hex object id.
is_full_object_id() {
  local object_id="$1"
  case "$object_id" in
    ''|*[!0-9a-f]*) return 1 ;;
  esac
  [ "${#object_id}" -eq 40 ] || [ "${#object_id}" -eq 64 ]
}

# checked_out_elsewhere
#   Succeeds when `git worktree list --porcelain` shows the branch checked out in a worktree.
#   Called only when the current worktree is not on the branch, so any match is another worktree.
checked_out_elsewhere() {
  local worktree_listing worktree_line
  worktree_listing="$(git worktree list --porcelain 2>/dev/null)" || blocker "cannot list worktrees"
  while IFS= read -r worktree_line; do
    [ "$worktree_line" != "branch refs/heads/$branch_name" ] || return 0
  done <<EOF
$worktree_listing
EOF
  return 1
}

# apply_upstream_rule
#   Keeps the branch upstream only when it is <remote>/<branch>; otherwise unsets both keys.
apply_upstream_rule() {
  local upstream_remote upstream_merge
  read_config_value "branch.$branch_name.remote"
  upstream_remote="$config_value"
  read_config_value "branch.$branch_name.merge"
  upstream_merge="$config_value"
  [ -n "$upstream_remote" ] || [ -n "$upstream_merge" ] || return 0
  if [ "$upstream_merge" = "refs/heads/$branch_name" ] && [ "$upstream_remote" != '.' ] \
    && hivemind_assert_identifier "$upstream_remote"; then
    return 0
  fi
  unset_config_key "branch.$branch_name.remote"
  unset_config_key "branch.$branch_name.merge"
}

command -v git >/dev/null 2>&1 || blocker "git not found on PATH"
inside_work_tree="$(git rev-parse --is-inside-work-tree 2>/dev/null)" || blocker "not inside a git checkout"
[ "$inside_work_tree" = true ] || blocker "not inside a git checkout"

refuse_operation_in_progress
refuse_unmerged_paths
refuse_dirty_tree
refuse_symbolic_branch
refuse_trunk_ref

head_ref_rc=0
head_ref="$(git symbolic-ref --quiet HEAD 2>/dev/null)" || head_ref_rc=$?
case "$head_ref_rc" in
  0) ;;
  1) head_ref='' ;;
  *) blocker "cannot read the current branch" ;;
esac

already_on_branch=false
[ "$head_ref" != "refs/heads/$branch_name" ] || already_on_branch=true
if [ "$already_on_branch" = false ] && checked_out_elsewhere; then
  blocker "working_branch is checked out in another worktree"
fi

base_reason='base does not resolve to a commit locally or on origin'
resolve_commit "refs/heads/$base_name"
if [ -z "$resolved_commit" ]; then
  resolve_commit "$base_name"
fi
if [ -z "$resolved_commit" ]; then
  read_config_value "remote.origin.url"
  [ -n "$config_value" ] || blocker "$base_reason"
  git fetch --quiet --no-tags origin "+refs/heads/$base_name:refs/remotes/origin/$base_name" </dev/null >/dev/null 2>&1 || blocker "$base_reason"
  resolve_commit "refs/remotes/origin/$base_name"
fi
base_commit="$resolved_commit"
is_full_object_id "$base_commit" || blocker "$base_reason"

resolve_commit "refs/heads/$branch_name"
branch_created=false
if [ "$already_on_branch" = true ]; then
  apply_upstream_rule
elif [ -n "$resolved_commit" ]; then
  git switch --quiet --no-guess "$branch_name" >/dev/null 2>&1 || blocker "could not switch to working_branch"
  apply_upstream_rule
else
  git switch --quiet --no-track -c "$branch_name" "$base_commit" >/dev/null 2>&1 || blocker "could not create working_branch from base"
  branch_created=true
fi

final_ref="$(git symbolic-ref --quiet HEAD 2>/dev/null)" || blocker "HEAD is not on working_branch after the switch"
[ "$final_ref" = "refs/heads/$branch_name" ] || blocker "HEAD is not on working_branch after the switch"
resolve_commit HEAD
head_commit="$resolved_commit"
is_full_object_id "$head_commit" || blocker "HEAD does not resolve to a commit"
if [ "$branch_created" = true ] && [ "$head_commit" != "$base_commit" ]; then
  blocker "new working_branch is not at the base commit"
fi

if [ -n "$warning_text" ]; then
  printf 'branch: %s\ncommit: %s\ncreated: %s\nwarning: %s\n' "$branch_name" "$head_commit" "$branch_created" "$warning_text"
else
  printf 'branch: %s\ncommit: %s\ncreated: %s\n' "$branch_name" "$head_commit" "$branch_created"
fi
