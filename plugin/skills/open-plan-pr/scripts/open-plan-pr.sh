#!/usr/bin/env bash
#
# open-plan-pr: THIN executable entrypoint (ADR-0020) that places the working branch on its
# remote and opens its pull request, or reuses the open one, in ONE process. It reads the inputs
# file once, refuses before any change, pushes through push-branch.sh as a child process, then
# reuses or creates the PR and verifies it against the values it checked. A change is a push, a
# write to a branch ref, HEAD, the index, the work tree or git config, or a PR created on GitHub.
#
# INPUT (`--flag value` form only; each flag at most once; unknown, duplicate, or missing flags
# give the fixed usage blocker):
#   --head <branch>          REQUIRED. Expected current branch.
#   --base <branch>          REQUIRED. Trunk, the PR target.
#   --remote <name>          OPTIONAL. Explicit push remote, passed on to push-branch.sh.
#   --expect-commit <sha>    OPTIONAL. The commit HEAD must be, passed on to push-branch.sh, which
#                            checks it in the same process as the push (ADR-0037 invariant 2).
#   --inputs <path>          REQUIRED. The inputs file, a JSON object the caller wrote with the
#                            Write tool (`.hivemind/pr-inputs-<token>.json`). A relative path is
#                            resolved from the folder the script was started in, before the
#                            script moves to the top of the work tree.
# head, base, and remote pass hivemind_assert_identifier (_shared/allowlist.sh: non-empty, no
# leading `-`, no `..`, charset ^[A-Za-z0-9._/-]+$) before any git or gh command runs (`head,
# base or push_remote contains characters outside the safe allowlist`). Then an expect-commit
# value that is not a full 40- or 64-digit lowercase hex object id stops with `expected commit is
# not a full object id`. The script then runs plain git from the top of the work tree (`git
# rev-parse --show-toplevel`), never `git -C` (ADR-0037 decision 25).
#
# INPUTS FILE (read once, with jq, into a private copy; no field enters shell or jq program
# source, per ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md, Inert Inputs-File Navigator
# Pattern). Fields, checked in this order, first failure wins:
#   title     REQUIRED. One line of text with a non-space character and no control character.
#   body      REQUIRED. Text with no control character other than newline and tab. It may be
#             empty.
#   draft     optional. true or false. true opens the PR as a draft. A reused PR is not changed.
# No other field is allowed. The title reaches gh as one `--title=<value>` argument from a quoted
# shell variable, and the body as a file in the private work folder (`--body-file=<path>`), so
# neither is ever part of shell source. The rule that the PR content carries no attribution
# string is the caller's judgment (the open-plan-pr SKILL.md), not checked here.
#
# REFUSALS (fixed blockers, checked in this order, before any change; ADR-0037 invariant 1):
#   delay        HIVEMIND_OPEN_PLAN_PR_REREAD_DELAY, when set, is not a whole number of seconds.
#   tools        git, jq, or gh is not on PATH (`gh not found on PATH`).
#   checkout     not inside a git work tree.
#   inputs       the inputs file is missing (`inputs file not found`), resolves outside the
#                checkout through a symlinked leaf or folder (`inputs file resolves outside the
#                checkout`, checked before the first read), is not exactly one valid JSON value
#                (`inputs file is not valid JSON`), or breaks a field rule above (one fixed
#                reason per rule).
#   in progress  a merge, rebase, cherry-pick, revert, cherry-pick or revert sequence, or bisect,
#                each looked up with `git rev-parse --git-path` so a linked worktree reads its own
#                state (_shared/git-refusals.sh).
#   unmerged     `git ls-files -u` reports any path.
#   dirty        the index has staged changes, the work tree has unstaged changes, or the work
#                tree has untracked files. Ignored files are allowed.
#   push script  skills/push-branch/scripts/push-branch.sh is missing.
#   lookup       `gh pr list` for open PRs with this head and base fails, or prints anything other
#                than a JSON array of PR objects (`cannot look up the open PRs for head`).
# push-branch.sh then makes its own refusals before its push: the current branch, the base, the
# expected commit, and the upstream. Its stderr is relayed, and its `blocker:` line ends the run.
#
# PUSH: one child call, `bash <plugin root>/skills/push-branch/scripts/push-branch.sh --head <head>
# --base <base> [--remote <remote>] --on-reject warn --no-upstream origin [--expect-commit <sha>]`.
# Its stdout must be exactly `branch: <head>`, then `commit: <full object id>` (equal to
# --expect-commit when given), then at most one `warning:` line with one of push-branch.sh's two
# fixed warnings. Anything else stops the run with `the push script printed unexpected output`.
# The `commit:` value is the pushed commit: every later check compares against it, never against
# a re-read of local state, per ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Shell
# Identifier Discipline).
#
# REUSE: after the push, `gh pr list` is read again. An open PR whose headRefName is head, whose
# baseRefName is base, and whose headRefOid is the pushed commit is reused: `created: false`, and
# its title, body, and draft state are left unchanged. When an open PR has the head and base but
# another head SHA, the list is read again, up to 5 reads in all, HIVEMIND_OPEN_PLAN_PR_REREAD_DELAY
# seconds apart (default 2), because GitHub updates a PR's head SHA a moment after a push. When
# no read finds a PR on the pushed commit, CREATE runs. More than one open PR carrying the pushed
# commit stops the run.
#
# CREATE: when no open PR carries the pushed commit, `gh pr create --base <base> --title=<title>
# --body-file=<private file> [--draft]`. It never passes `--head` (see R1). Its stdout must be one
# line, a PR URL that passes the identifier gate (^https://[A-Za-z0-9._/-]+$) and ends in
# `/pull/<n>`. gh's stderr is relayed.
#
# VERIFY: `gh pr view <n> --json headRefName,headRefOid`. headRefName must equal head and
# headRefOid must equal the pushed commit; a mismatch is a blocker, never a retry.
#
# OUTPUT on success (exit 0), on stdout in ONE write:
#   url: <PR url>
#   head_ref_oid: <pushed commit>
#   created: true|false
#   warning: <push-branch.sh warning>     only when the push warned
# EXIT CONTRACT:
#   0  routing lines on stdout
#   1  NOTHING on stdout. stderr carries any relayed push-branch.sh or gh stderr, then
#      `blocker: <fixed reason>` as the LAST line. Blocker text never echoes a caller-supplied,
#      repository, or GitHub value. A blocker after PUSH means the branch may be on its remote.
#
# RECORDED RESIDUAL R1 (implicit head of the PR creation): CREATE above runs `gh pr create`
# without `--head`, so gh resolves the PR head from the current branch in its own process, after
# the push-branch.sh child has exited. No check made by this script or by push-branch.sh binds
# that resolution.
#   Root cause:  the PR head is implicit, and gh resolves it in a different process.
#   Inherited:   on main, the PR creation already relied on an earlier step's branch check. This
#                is not a new exposure introduced by routing pushes through push-branch.sh or by
#                moving PR creation into this script.
#   Bounded impact: non-interactive gh never pushes, prompts, or forks; it aborts when the branch
#                is not on a remote at the local commit. VERIFY above compares GitHub's
#                headRefName and headRefOid against the gated head input and push-branch.sh's
#                `commit:` line, never against a re-read of local state, so a drifted head is
#                blocked, not accepted. Drift needs HEAD to change in the run owner's worktree
#                between the push and the create call, and only repo-owned hooks or the operator
#                act in the run owner's worktree. The worst result is a visible, closable PR.
#   Rejected remediations:
#                - passing `--head <branch>`: gh then uses the base repository unless given
#                  `<owner>:<branch>`, and deriving the owner means hand-parsing a remote URL,
#                  which breaks fork and triangular remotes.
#                - running the push and the PR creation in one process: this script now runs
#                  both, but gh still resolves its own head unless `--head` is passed, so the
#                  shared process binds nothing. The push stays in push-branch.sh, called as a
#                  child, so the push kernel stays apart from PR authoring, and the free-text
#                  title and body reach this script through the inputs file, never as arguments.
#   Linkage:     review findings f781f8c8, 87f850de, a3c042d0, and bd3204af, with b0f99069 as
#                lineage.
#
# NOT CHECKED: repo hooks, local refs, git config, gh config and auth, and the operator are
# trusted under ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Shell Identifier
# Discipline). gh picks the repository for every call from the git remotes and its own config;
# this script never names it. The lookup, the push, and the create call are not atomic: a PR
# opened by someone else between them makes the create call fail, and the run stops after the
# push. A run that stops after the push leaves the branch on its remote; a rerun pushes again,
# which changes nothing, and then reuses or creates the PR. An open PR on a fork with the same
# branch name has another head SHA, so it is never reused. When `.hivemind/` is not ignored, the
# inputs file itself is an untracked file and the run stops there. The private work folder
# (mktemp -d under TMPDIR) holds the inputs copy, the body file, and the gh and push-branch.sh
# output, and is removed by the EXIT trap.
#
# Conventions (ADR-0020 thin entrypoint): `set -euo pipefail`, an EXIT trap ending in a
# guaranteed-zero `:`, self-location via `cd && pwd -P`, NO `realpath`/`readlink`; bash 3.2
# compatible (no mapfile / associative arrays / ${var,,}). The identifier gate comes from
# _shared/allowlist.sh, the inputs read-guard from _shared/containment.sh, and the in-progress,
# unmerged and dirty checks from _shared/git-refusals.sh; this script maps their results to its
# own blockers.

set -euo pipefail
trap ':' EXIT

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# layout plugin/skills/open-plan-pr/scripts/ => ../../.. is the plugin root.
# cd && pwd -P is portable (no realpath/readlink). NO ${CLAUDE_PLUGIN_ROOT} inside an engine
# script. SOURCE-OR-DIE: a missing/unparseable library fails closed before any git command.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve the plugin root from the script directory; refusing to proceed"
[ -f "$plugin_root/skills/_shared/allowlist.sh" ] || blocker "required shared library missing: skills/_shared/allowlist.sh; refusing to proceed"
. "$plugin_root/skills/_shared/allowlist.sh" || blocker "failed to source skills/_shared/allowlist.sh (unparseable); refusing to proceed"
[ -f "$plugin_root/skills/_shared/containment.sh" ] || blocker "required shared library missing: skills/_shared/containment.sh; refusing to proceed"
. "$plugin_root/skills/_shared/containment.sh" || blocker "failed to source skills/_shared/containment.sh (unparseable); refusing to proceed"
[ -f "$plugin_root/skills/_shared/git-refusals.sh" ] || blocker "required shared library missing: skills/_shared/git-refusals.sh; refusing to proceed"
. "$plugin_root/skills/_shared/git-refusals.sh" || blocker "failed to source skills/_shared/git-refusals.sh (unparseable); refusing to proceed"
push_script="$plugin_root/skills/push-branch/scripts/push-branch.sh"

export LC_ALL=C
export GIT_TERMINAL_PROMPT=0
export GH_PROMPT_DISABLED=1

usage_reason='invalid arguments; usage: open-plan-pr.sh --head <branch> --base <branch> [--remote <name>] [--expect-commit <sha>] --inputs <path>'
reject_warning='push was rejected; the branch is not on its remote'
deferred_warning='no upstream and no origin remote; push deferred'
reread_limit=5

head_name=''
head_seen=false
base_name=''
base_seen=false
remote_name=''
remote_seen=false
expect_commit=''
expect_commit_seen=false
inputs_arg=''
inputs_seen=false
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || blocker "$usage_reason"
  case "$1" in
    --head)
      [ "$head_seen" = false ] || blocker "$usage_reason"
      head_name="$2"
      head_seen=true
      ;;
    --base)
      [ "$base_seen" = false ] || blocker "$usage_reason"
      base_name="$2"
      base_seen=true
      ;;
    --remote)
      [ "$remote_seen" = false ] || blocker "$usage_reason"
      remote_name="$2"
      remote_seen=true
      ;;
    --expect-commit)
      [ "$expect_commit_seen" = false ] || blocker "$usage_reason"
      expect_commit="$2"
      expect_commit_seen=true
      ;;
    --inputs)
      [ "$inputs_seen" = false ] || blocker "$usage_reason"
      inputs_arg="$2"
      inputs_seen=true
      ;;
    *)
      blocker "$usage_reason"
      ;;
  esac
  shift 2
done

[ "$head_seen" = true ] && [ "$base_seen" = true ] && [ "$inputs_seen" = true ] || blocker "$usage_reason"
[ -n "$inputs_arg" ] || blocker "$usage_reason"

identifier_reason='head, base or push_remote contains characters outside the safe allowlist'
hivemind_assert_identifier "$head_name" || blocker "$identifier_reason"
hivemind_assert_identifier "$base_name" || blocker "$identifier_reason"
if [ "$remote_seen" = true ]; then
  hivemind_assert_identifier "$remote_name" || blocker "$identifier_reason"
fi

# is_full_object_id <value>
#   Succeeds when <value> is a full 40- or 64-digit lowercase hex object id.
is_full_object_id() {
  local object_id="$1"
  case "$object_id" in
    ''|*[!0-9a-f]*) return 1 ;;
  esac
  [ "${#object_id}" -eq 40 ] || [ "${#object_id}" -eq 64 ]
}

if [ "$expect_commit_seen" = true ]; then
  is_full_object_id "$expect_commit" || blocker "expected commit is not a full object id"
fi

reread_delay="${HIVEMIND_OPEN_PLAN_PR_REREAD_DELAY:-2}"
case "$reread_delay" in
  ''|*[!0-9]*) blocker "HIVEMIND_OPEN_PLAN_PR_REREAD_DELAY must be a whole number of seconds" ;;
esac

case "$inputs_arg" in
  /*) INPUTS_FILE="$inputs_arg" ;;
  *) INPUTS_FILE="$PWD/$inputs_arg" ;;
esac

command -v git >/dev/null 2>&1 || blocker "git not found on PATH"
command -v jq >/dev/null 2>&1 || blocker "jq not found on PATH"
command -v gh >/dev/null 2>&1 || blocker "gh not found on PATH"
inside_work_tree="$(git rev-parse --is-inside-work-tree 2>/dev/null)" || blocker "not inside a git checkout"
[ "$inside_work_tree" = true ] || blocker "not inside a git checkout"
work_tree_top="$(git rev-parse --show-toplevel 2>/dev/null)" || blocker "cannot read the top of the work tree"
[ -n "$work_tree_top" ] || blocker "cannot read the top of the work tree"
CDPATH= cd -- "$work_tree_top" 2>/dev/null || blocker "cannot read the top of the work tree"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-open-plan-pr.XXXXXX" 2>/dev/null)" || blocker "cannot create a private work folder"
# remove_work_dir
#   Removes the private work folder. Runs from the EXIT trap.
remove_work_dir() {
  rm -rf -- "$work_dir" 2>/dev/null
  return 0
}
trap 'remove_work_dir; :' EXIT
inputs_copy="$work_dir/inputs.json"
body_file="$work_dir/body.md"
list_file="$work_dir/list.json"
push_err_file="$work_dir/push.err"
create_err_file="$work_dir/create.err"
view_file="$work_dir/view.json"

# ── Inputs ──────────────────────────────────────────────────────────────────

[ -f "$INPUTS_FILE" ] || blocker "inputs file not found"
hivemind_assert_inputs_contained "$work_tree_top" "$INPUTS_FILE" >/dev/null 2>&1 || blocker "inputs file resolves outside the checkout"
jq -c -s 'if length == 1 then .[0] else error("not one JSON value") end' "$INPUTS_FILE" >"$inputs_copy" 2>/dev/null \
  || blocker "inputs file is not valid JSON"

# The field rules from the header, in order. Prints the fixed reason of the first rule the
# inputs break, or an empty line when every rule holds.
validate_program='
def known_keys: ["title", "body", "draft"];
def is_one_line: explode | all(.[]; . >= 32 and . != 127);
def is_text_block: explode | all(.[]; . == 9 or . == 10 or (. >= 32 and . != 127));
if type != "object" then "inputs must be a JSON object"
elif (keys - known_keys | length) > 0 then "inputs have a field other than title, body and draft"
elif (.title | type) != "string" then "title must be one line of text"
elif (.title | is_one_line | not) or (.title | test("[^ ]") | not) then "title must be one line of text"
elif (.body | type) != "string" then "body must be text with no control characters other than newline and tab"
elif (.body | is_text_block | not) then "body must be text with no control characters other than newline and tab"
elif has("draft") and (.draft | type) != "boolean" then "draft must be true or false"
else "" end
'
inputs_reason="$(jq -r "$validate_program" "$inputs_copy" 2>/dev/null)" || blocker "cannot read the inputs file"
[ -z "$inputs_reason" ] || blocker "$inputs_reason"

title_text="$(jq -r '.title' "$inputs_copy" 2>/dev/null)" || blocker "cannot read the inputs file"
draft_value="$(jq -r '.draft == true' "$inputs_copy" 2>/dev/null)" || blocker "cannot read the inputs file"
jq -j '.body' "$inputs_copy" >"$body_file" 2>/dev/null || blocker "cannot read the inputs file"

# ── Git state ───────────────────────────────────────────────────────────────

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
#   Blocks when the index has staged changes, the work tree has unstaged changes, or the work
#   tree has untracked files. Runs in the main shell so blocker exits it.
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

refuse_operation_in_progress
refuse_unmerged_paths
refuse_dirty_tree
[ -f "$push_script" ] || blocker "required script missing: skills/push-branch/scripts/push-branch.sh; refusing to proceed"

# ── Open PR lookup ──────────────────────────────────────────────────────────

# Reads the open PR list in the list file. Fails unless it is an array of PR objects. Prints
# `<PRs with head and base> <of those, PRs on the pushed commit> <url of the one such PR, or ->`.
list_program='
if type != "array" then error("not an array")
elif (all(.[]; type == "object"
    and (.number | type) == "number"
    and (.url | type) == "string"
    and (.headRefName | type) == "string"
    and (.headRefOid | type) == "string"
    and (.baseRefName | type) == "string") | not) then error("not PR objects")
else
  [.[] | select(.headRefName == $head and .baseRefName == $base)] as $named
  | [$named[] | select(.headRefOid == $commit)] as $carrying
  | "\($named | length) \($carrying | length) \(if ($carrying | length) == 1 then $carrying[0].url else "-" end)"
end
'

# read_open_prs <pushed commit or empty>
#   Runs `gh pr list` for open PRs with head and base and sets named_count, carrying_count, and
#   carrying_url from list_program. Returns 1 when gh fails or its output is not a PR list.
named_count=0
carrying_count=0
carrying_url=''
read_open_prs() {
  local commit_text="$1"
  local summary_line
  gh pr list --head "$head_name" --base "$base_name" --state open --limit 100 \
    --json number,url,headRefName,headRefOid,baseRefName </dev/null >"$list_file" 2>/dev/null || return 1
  summary_line="$(jq -r --arg head "$head_name" --arg base "$base_name" --arg commit "$commit_text" \
    "$list_program" "$list_file" 2>/dev/null)" || return 1
  case "$summary_line" in
    *' '*' '*) ;;
    *) return 1 ;;
  esac
  named_count="${summary_line%% *}"
  summary_line="${summary_line#* }"
  carrying_count="${summary_line%% *}"
  carrying_url="${summary_line#* }"
  return 0
}

read_open_prs '' || blocker "cannot look up the open PRs for head"

# ── Push ────────────────────────────────────────────────────────────────────

push_args=(--head "$head_name" --base "$base_name")
if [ "$remote_seen" = true ]; then
  push_args+=(--remote "$remote_name")
fi
push_args+=(--on-reject warn --no-upstream origin)
if [ "$expect_commit_seen" = true ]; then
  push_args+=(--expect-commit "$expect_commit")
fi

push_rc=0
push_output="$(bash "$push_script" "${push_args[@]}" 2>"$push_err_file")" || push_rc=$?
push_err_last=''
if [ -s "$push_err_file" ]; then
  cat -- "$push_err_file" >&2
  push_err_last="$(tail -n 1 -- "$push_err_file")"
fi
if [ "$push_rc" -ne 0 ]; then
  case "$push_rc:$push_err_last" in
    '1:blocker: '?*) exit 1 ;;
  esac
  blocker "the push script failed"
fi

# parse_push_output
#   Sets pushed_commit and push_warning from push-branch.sh's stdout, or blocks when it is not
#   exactly the lines the header names. Runs in the main shell so blocker exits it.
pushed_commit=''
push_warning=''
parse_push_output() {
  local unexpected_reason='the push script printed unexpected output'
  local line_index=0 push_line
  while IFS= read -r push_line; do
    line_index=$((line_index + 1))
    case "$line_index" in
      1) [ "$push_line" = "branch: $head_name" ] || blocker "$unexpected_reason" ;;
      2)
        case "$push_line" in
          'commit: '*) pushed_commit="${push_line#commit: }" ;;
          *) blocker "$unexpected_reason" ;;
        esac
        ;;
      3)
        case "$push_line" in
          "warning: $reject_warning"|"warning: $deferred_warning") push_warning="${push_line#warning: }" ;;
          *) blocker "$unexpected_reason" ;;
        esac
        ;;
      *) blocker "$unexpected_reason" ;;
    esac
  done <<EOF
$push_output
EOF
  [ "$line_index" -ge 2 ] || blocker "$unexpected_reason"
  is_full_object_id "$pushed_commit" || blocker "$unexpected_reason"
  if [ "$expect_commit_seen" = true ]; then
    [ "$pushed_commit" = "$expect_commit" ] || blocker "$unexpected_reason"
  fi
}
parse_push_output

# is_pr_url <value>
#   Succeeds when <value> passes the PR URL identifier gate and ends in /pull/<n>.
is_pr_url() {
  local url_text="$1"
  local url_pattern='^https://[A-Za-z0-9._/-]+/pull/[0-9]+$'
  [[ "$url_text" =~ $url_pattern ]]
}

# ── Reuse ───────────────────────────────────────────────────────────────────

read_count=0
while :; do
  read_count=$((read_count + 1))
  read_open_prs "$pushed_commit" || blocker "the open PRs could not be read after the push"
  [ "$carrying_count" -le 1 ] || blocker "more than one open PR carries the pushed commit"
  [ "$carrying_count" -eq 0 ] || break
  [ "$named_count" -gt 0 ] || break
  [ "$read_count" -lt "$reread_limit" ] || break
  sleep "$reread_delay"
done

if [ "$carrying_count" -eq 1 ]; then
  is_pr_url "$carrying_url" || blocker "PR URL contains characters outside the safe allowlist"
  pr_url="$carrying_url"
  created_value=false
else
  # ── Create ────────────────────────────────────────────────────────────────
  create_rc=0
  if [ "$draft_value" = true ]; then
    create_output="$(gh pr create --base "$base_name" --title="$title_text" --body-file="$body_file" --draft </dev/null 2>"$create_err_file")" || create_rc=$?
  else
    create_output="$(gh pr create --base "$base_name" --title="$title_text" --body-file="$body_file" </dev/null 2>"$create_err_file")" || create_rc=$?
  fi
  [ ! -s "$create_err_file" ] || cat -- "$create_err_file" >&2
  [ "$create_rc" -eq 0 ] || blocker "the PR could not be created"
  is_pr_url "$create_output" || blocker "PR URL contains characters outside the safe allowlist"
  pr_url="$create_output"
  pr_number="${pr_url##*/}"
  hivemind_assert_identifier "$pr_number" || blocker "PR number contains characters outside the safe allowlist"

  # ── Verify ────────────────────────────────────────────────────────────────
  gh pr view "$pr_number" --json headRefName,headRefOid </dev/null >"$view_file" 2>/dev/null \
    || blocker "could not read the PR head branch or head SHA"
  view_shape="$(jq -r 'if type == "object" and (.headRefName | type) == "string" and (.headRefOid | type) == "string" then "ok" else "bad" end' "$view_file" 2>/dev/null)" \
    || blocker "could not read the PR head branch or head SHA"
  [ "$view_shape" = ok ] || blocker "could not read the PR head branch or head SHA"
  head_match="$(jq -r --arg head "$head_name" '.headRefName == $head' "$view_file" 2>/dev/null)" \
    || blocker "could not read the PR head branch or head SHA"
  [ "$head_match" = true ] || blocker "PR head branch does not match head"
  oid_match="$(jq -r --arg commit "$pushed_commit" '.headRefOid == $commit' "$view_file" 2>/dev/null)" \
    || blocker "could not read the PR head branch or head SHA"
  [ "$oid_match" = true ] || blocker "PR head SHA does not match the pushed commit"
  created_value=true
fi

if [ -n "$push_warning" ]; then
  printf 'url: %s\nhead_ref_oid: %s\ncreated: %s\nwarning: %s\n' "$pr_url" "$pushed_commit" "$created_value" "$push_warning"
else
  printf 'url: %s\nhead_ref_oid: %s\ncreated: %s\n' "$pr_url" "$pushed_commit" "$created_value"
fi
