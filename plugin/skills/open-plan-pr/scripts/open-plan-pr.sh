#!/usr/bin/env bash
#
# open-plan-pr: THIN executable entrypoint (ADR-0020) that places the working branch on its
# remote and opens its pull request, or reuses the open one, in ONE process. It reads the inputs
# file once, refuses before any change, pushes through push-branch.sh as a child process, then
# reuses or creates the PR and verifies it against the values it checked. A change is a push, a
# write to a branch ref, HEAD, the index, the work tree or git config, a PR created on GitHub, or
# a comment posted on a PR.
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
#   comment   optional. Text with a character other than space, newline and tab, and no control
#             character other than newline and tab. It is posted only on a reused PR (REUSE).
# No other field is allowed. The title reaches gh as one `--title=<value>` argument from a quoted
# shell variable, and the body and the comment as files in the private work folder
# (`--body-file=<path>`), so none of them is ever part of shell source or an argument's text. The
# rule that the PR content carries no attribution string is the caller's judgment (the
# open-plan-pr SKILL.md), not checked here.
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
#                than a JSON array of PR objects, each with a headRepository that is null or an
#                object with a string id (`cannot look up the open PRs for head`).
# push-branch.sh then makes its own refusals before its push: the current branch, the base, the
# expected commit, and the upstream. Its stderr is relayed, and its `blocker:` line ends the run.
#
# PUSH: one child call, `bash <plugin root>/skills/push-branch/scripts/push-branch.sh --head <head>
# --base <base> --report-remote yes [--remote <remote>] --on-reject warn --no-upstream origin
# [--expect-commit <sha>]`. Its stdout must be exactly `branch: <head>`, then `commit: <full
# object id>` (equal to --expect-commit when given), then one of two endings. When a push ran:
# `remote: <name>`, then at most `warning: <rejected warning>`. When the push was deferred:
# `warning: <deferred warning>` and no remote line. The remote name must pass the identifier gate
# and equal --remote when given. The two warnings are push-branch.sh's fixed texts. Anything else
# stops the run with `the push script printed unexpected output`. The `commit:` value is the
# pushed commit: every later check compares against it, never against a re-read of local state,
# per ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Shell Identifier Discipline).
#
# HEAD REPOSITORY: the GitHub node id of the repository the push landed in. It is known only when
# the push did not warn, `git remote get-url --push --all <reported remote>` prints exactly one
# URL, that URL starts with `https://` and has no `@`, or starts with `ssh://` or `git@`, and
# `gh repo view --json id -- <url>` exits 0. A value with no URL prefix is never passed, because
# gh reads it as OWNER/REPO. When gh exits 0 but prints anything other than one object whose id
# is a string of [A-Za-z0-9_=+/-] characters, the run stops with `cannot read the GitHub
# repository of the push remote`. Every other miss leaves the id unknown (see R3).
#
# REUSE: only when the head repository id is known. After the push, `gh pr list` is read again.
# An open PR whose headRefName is head, whose baseRefName is base, whose headRepository id is the
# head repository id, and whose headRefOid is the pushed commit is reused: `created: false`, and
# its title, body, and draft state are left unchanged. A PR from another head repository, such as
# a fork, or with a null headRepository (a deleted fork), is never reused and never causes a
# re-read. When an open PR has the head, base and head repository but another head SHA, the list
# is read again, up to 5 reads in all, HIVEMIND_OPEN_PLAN_PR_REREAD_DELAY seconds apart (default
# 2), because GitHub updates a PR's head SHA a moment after a push. When no read finds a PR on the
# pushed commit, or the id is unknown, CREATE runs. More than one open PR carrying the pushed
# commit stops the run.
#   When the inputs carry comment, the script then posts it on the reused PR: `gh pr comment <n>
# --body-file=<private file>`, where <n> is the number at the end of the reused PR URL and passes
# the identifier gate. The comment text never reaches gh as an argument. gh's stderr is relayed,
# and a failed post stops the run with `the PR comment could not be posted`. Each run that reuses
# a PR posts its own comment, by design: a rerun that reuses the PR posts the comment again
# (see R4). CREATE never posts the comment.
#
# CREATE: when no open PR carries the pushed commit, `gh pr create --base <base> --title=<title>
# --body-file=<private file> [--draft]`. It never passes `--head` (see R1). Its stdout must be one
# line, a PR URL that passes the identifier gate (^https://[A-Za-z0-9._/-]+$) and ends in
# `/pull/<n>`. gh's stderr is relayed.
#
# VERIFY: `gh pr view <n> --json headRefName,headRefOid,headRepository`. headRepository must be
# null or an object with a string id. headRefName must equal head, then headRefOid must equal the
# pushed commit, then, when the head repository id is known, headRepository must be non-null with
# that id (`PR head repository does not match the push remote`). A mismatch is a blocker, never a
# retry.
#
# OUTPUT on success (exit 0), on stdout in ONE write:
#   url: <PR url>
#   head_ref_oid: <pushed commit>
#   created: true|false
#   commented: true|false
#                       only when the inputs carry comment: true when the comment was posted on
#                       a reused PR, false when the PR was created
#   warning: <text>     only when the push warned (push-branch.sh's warning), or when the push
#                       did not warn and the head repository id is unknown (`gh cannot read the
#                       push remote as a GitHub repository; the PR head repository was not
#                       checked`)
# Without comment in the inputs, there is no `commented:` line and the output is as above.
# EXIT CONTRACT:
#   0  routing lines on stdout
#   1  NOTHING on stdout. stderr carries any relayed push-branch.sh or gh stderr, then
#      `blocker: <fixed reason>` as the LAST line. Blocker text never echoes a caller-supplied,
#      repository, or GitHub value. A blocker after PUSH means the branch may be on its remote;
#      HEAD REPOSITORY, REUSE and VERIFY above name the blockers this script adds after the push.
#      After `the PR comment could not be posted`, the reused PR is open on the pushed commit and
#      the comment may be missing from it.
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
#                headRefName, headRefOid and, when it is known, headRepository id against the
#                gated head input, push-branch.sh's `commit:` line, and the id of the repository
#                the push landed in, never against a re-read of local state, so a drifted head or
#                a head in another repository is blocked, not accepted. Drift needs HEAD to change
#                in the run owner's worktree between the push and the create call, and only
#                repo-owned hooks or the operator act in the run owner's worktree. The worst
#                result is a visible, closable PR.
#   Rejected remediations:
#                - passing `--head <owner>:<branch>`: it names the head by owner login, not by
#                  repository. gh does not support an organization owner there, and one
#                  organization can hold several forks with one branch name (cli/cli#10093). It
#                  fails Closed-by-Construction: it adds the owner to a text key instead of
#                  binding the repository.
#                - passing `--head <branch>`: exact only when the push repository is the base
#                  repository gh pr create uses, and gh offers no way to read that base (gh repo
#                  view ignores GH_REPO, which gh pr create honors).
#                - creating the PR with the GraphQL createPullRequest mutation and a
#                  headRepositoryId through gh api: it binds the head by id, but it replaces gh
#                  pr create with a hand-built mutation and changes every create pin and test,
#                  for a case VERIFY now blocks.
#                - running the push and the PR creation in one process: this script now runs
#                  both, but gh still resolves its own head unless `--head` is passed, so the
#                  shared process binds nothing. The push stays in push-branch.sh, called as a
#                  child, so the push kernel stays apart from PR authoring, and the free-text
#                  title and body reach this script through the inputs file, never as arguments.
#   Linkage:     review findings f781f8c8, 87f850de, a3c042d0, bd3204af, 08991c85, and
#                09ca6d9d, with b0f99069 as lineage; review thread r4331751745.
#
# RECORDED RESIDUAL R2 (https-only PR URL gate): REUSE and CREATE above accept a PR URL only
# when it passes the identifier gate (^https://[A-Za-z0-9._/-]+$) and ends in `/pull/<n>`. A
# GitHub host that gh reports with `http://` or with a port (`host:8443`) fails that gate.
#   Root cause:  this script gates the whole PR URL with the https-only, no-port PR URL pattern
#                from ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Shell Identifier
#                Discipline).
#   Inherited:   no. On main, open-plan-pr checked only the trailing PR number, so a stop after
#                the create call on such hosts is new with this script.
#   Bounded impact: github.com is not affected. Such hosts are already unsupported across the
#                plugin: the github-reviewer `pr` input uses the same gate, so the review loop
#                would stop there anyway. The run stops loudly after the create call, and a
#                rerun stops in REUSE. The extra PR is visible and can be closed.
#   Rejected remediations:
#                - widening the policy gate to allow `http://` or a port: that changes the
#                  security contract and loosens input checking for every consumer.
#   Linkage:     review thread r4331321536.
#
# RECORDED RESIDUAL R3 (head repository not checked when its id is unknown): when HEAD
# REPOSITORY above leaves the id unknown, REUSE is skipped and VERIFY checks only headRefName and
# headRefOid, so the head repository of the created PR is not checked.
#   Root cause:  the id is read from the push URL with gh, and gh cannot read every URL git can
#                push to.
#   Inherited:   yes. On main, open-plan-pr checked only the head branch name and commit, never
#                the head repository.
#   Bounded impact: it applies only to a push remote whose URL is an ssh host alias, a local
#                path, or a non-GitHub host, to a gh failure, or to a push that did not land
#                (rejected or deferred). Nothing is reused in that case, so a PR from another
#                repository is never taken as this one. When the push landed, the output carries
#                a warning that the head repository was not checked. The check made is the same
#                as on main.
#   Rejected remediations:
#                - translating ssh host aliases by hand: that means parsing ssh config, which gh
#                  and git own, and it would still miss other URL forms.
#                - stopping when the id is unknown: it adds stops, compared with main, for
#                  remotes that work today.
#   Linkage:     review thread r4331751745.
#
# RECORDED RESIDUAL R4 (one decisions comment per reusing run): REUSE above posts the comment
# input on a reused PR in every run that reuses it, so the PR can carry the comment more than
# once.
#   Root cause:  each run that reuses an open PR posts its own decisions comment. A new run after
#                an ADR-0037 decision 2 restart reuses the PR and posts again. A resume by name
#                gets the runner result from cache (ADR-0037 decision 8), so it does not post
#                again.
#   Inherited:   no. The comment input is new with this script; on main, open-plan-pr had no
#                comment input and posted nothing on a reused PR.
#   Bounded impact: at most one redundant comment, and one notification, per new run. No wrong
#                state, no data loss, no security effect. The PR, its branch and the pushed commit
#                are unchanged.
#   Rejected remediations:
#                - a dedup marker in the comment text: anyone who can comment can forge one, and a
#                  forged marker would suppress the run's decision record that ADR-0037 decision 3
#                  requires.
#                - comparing the comment text with the existing comments: it needs a paginated
#                  read of external comment bodies plus an author check, and it changes the
#                  `commented` contract.
#                - an idempotency key: GitHub offers none for comments.
#   Linkage:     local review finding 2a8f6742.
#
# NOT CHECKED: repo hooks, local refs, git config, gh config and auth, and the operator are
# trusted under ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Shell Identifier
# Discipline). gh picks the repository for every call from the git remotes and its own config;
# this script never names it. The lookup, the push, and the create call are not atomic: a PR
# opened by someone else between them makes the create call fail, and the run stops after the
# push. A run that stops after the push leaves the branch on its remote; a rerun pushes again,
# which changes nothing, and then reuses or creates the PR. REUSE keys on the head repository
# id, so an open PR from another repository, such as a fork with the same branch name and the
# same commit, is never reused. The push URL behind that id is read again from git config after
# the push, and git config is trusted. When `.hivemind/` is not ignored, the
# inputs file itself is an untracked file and the run stops there. The private work folder
# (mktemp -d under TMPDIR) holds the inputs copy, the body file, the comment file, and the gh
# and push-branch.sh output, and is removed by the EXIT trap.
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
comment_file="$work_dir/comment.md"
comment_err_file="$work_dir/comment.err"
view_file="$work_dir/view.json"
repo_file="$work_dir/repo.json"

# ── Inputs ──────────────────────────────────────────────────────────────────

[ -f "$INPUTS_FILE" ] || blocker "inputs file not found"
hivemind_assert_inputs_contained "$work_tree_top" "$INPUTS_FILE" >/dev/null 2>&1 || blocker "inputs file resolves outside the checkout"
jq -c -s 'if length == 1 then .[0] else error("not one JSON value") end' "$INPUTS_FILE" >"$inputs_copy" 2>/dev/null \
  || blocker "inputs file is not valid JSON"

# The field rules from the header, in order. Prints the fixed reason of the first rule the
# inputs break, or an empty line when every rule holds.
validate_program='
def known_keys: ["title", "body", "draft", "comment"];
def is_one_line: explode | all(.[]; . >= 32 and . != 127);
def is_text_block: explode | all(.[]; . == 9 or . == 10 or (. >= 32 and . != 127));
if type != "object" then "inputs must be a JSON object"
elif (keys - known_keys | length) > 0 then "inputs have a field other than title, body, draft and comment"
elif (.title | type) != "string" then "title must be one line of text"
elif (.title | is_one_line | not) or (.title | test("[^ ]") | not) then "title must be one line of text"
elif (.body | type) != "string" then "body must be text with no control characters other than newline and tab"
elif (.body | is_text_block | not) then "body must be text with no control characters other than newline and tab"
elif has("draft") and (.draft | type) != "boolean" then "draft must be true or false"
elif has("comment") and (.comment | type) != "string" then "comment must be non-blank text with no control characters other than newline and tab"
elif has("comment") and ((.comment | is_text_block | not) or (.comment | test("[^ \t\n]") | not)) then "comment must be non-blank text with no control characters other than newline and tab"
else "" end
'
inputs_reason="$(jq -r "$validate_program" "$inputs_copy" 2>/dev/null)" || blocker "cannot read the inputs file"
[ -z "$inputs_reason" ] || blocker "$inputs_reason"

title_text="$(jq -r '.title' "$inputs_copy" 2>/dev/null)" || blocker "cannot read the inputs file"
draft_value="$(jq -r '.draft == true' "$inputs_copy" 2>/dev/null)" || blocker "cannot read the inputs file"
jq -j '.body' "$inputs_copy" >"$body_file" 2>/dev/null || blocker "cannot read the inputs file"
comment_given="$(jq -r 'has("comment")' "$inputs_copy" 2>/dev/null)" || blocker "cannot read the inputs file"
if [ "$comment_given" = true ]; then
  jq -j '.comment' "$inputs_copy" >"$comment_file" 2>/dev/null || blocker "cannot read the inputs file"
fi
commented_value=false

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

# Reads the open PR list in the list file. Fails unless it is an array of PR objects, each with a
# headRepository that is null or an object with a string id. Prints `<PRs with head, base and the
# head repository id> <of those, PRs on the pushed commit> <url of the one such PR, or ->`.
list_program='
def has_head_repository: .headRepository == null
  or ((.headRepository | type) == "object" and (.headRepository.id | type) == "string");
if type != "array" then error("not an array")
elif (all(.[]; type == "object"
    and (.number | type) == "number"
    and (.url | type) == "string"
    and (.headRefName | type) == "string"
    and (.headRefOid | type) == "string"
    and (.baseRefName | type) == "string"
    and has_head_repository) | not) then error("not PR objects")
else
  [.[] | select(.headRefName == $head and .baseRefName == $base
    and .headRepository != null and .headRepository.id == $repo)] as $named
  | [$named[] | select(.headRefOid == $commit)] as $carrying
  | "\($named | length) \($carrying | length) \(if ($carrying | length) == 1 then $carrying[0].url else "-" end)"
end
'

# read_open_prs <pushed commit or empty> <head repository id or empty>
#   Runs `gh pr list` for open PRs with head and base and sets named_count, carrying_count, and
#   carrying_url from list_program. Returns 1 when gh fails or its output is not a PR list.
named_count=0
carrying_count=0
carrying_url=''
read_open_prs() {
  local commit_text="$1"
  local repo_id_text="$2"
  local summary_line
  gh pr list --head "$head_name" --base "$base_name" --state open --limit 100 \
    --json number,url,headRefName,headRefOid,baseRefName,headRepository </dev/null >"$list_file" 2>/dev/null || return 1
  summary_line="$(jq -r --arg head "$head_name" --arg base "$base_name" --arg commit "$commit_text" \
    --arg repo "$repo_id_text" "$list_program" "$list_file" 2>/dev/null)" || return 1
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

read_open_prs '' '' || blocker "cannot look up the open PRs for head"

# ── Push ────────────────────────────────────────────────────────────────────

push_args=(--head "$head_name" --base "$base_name" --report-remote yes)
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
#   Sets pushed_commit, pushed_remote, and push_warning from push-branch.sh's stdout, or blocks
#   when it is not exactly the lines the header names. Runs in the main shell so blocker exits it.
pushed_commit=''
pushed_remote=''
remote_line_seen=false
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
          'remote: '*)
            pushed_remote="${push_line#remote: }"
            remote_line_seen=true
            ;;
          "warning: $deferred_warning") push_warning="$deferred_warning" ;;
          *) blocker "$unexpected_reason" ;;
        esac
        ;;
      4)
        [ "$remote_line_seen" = true ] || blocker "$unexpected_reason"
        [ "$push_line" = "warning: $reject_warning" ] || blocker "$unexpected_reason"
        push_warning="$reject_warning"
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
  [ "$line_index" -ge 3 ] || blocker "$unexpected_reason"
  if [ "$remote_line_seen" = true ]; then
    hivemind_assert_identifier "$pushed_remote" || blocker "$unexpected_reason"
    if [ "$remote_seen" = true ]; then
      [ "$pushed_remote" = "$remote_name" ] || blocker "$unexpected_reason"
    fi
  fi
}
parse_push_output

# ── Head repository ─────────────────────────────────────────────────────────

# read_push_repository_id
#   Sets push_repo_id to the GitHub node id of the repository the push landed in, read from the
#   push URL of the reported remote. Leaves it empty when the id is unknown. Blocks when gh reads
#   the URL but prints anything other than one object with a safe string id. Runs in the main
#   shell so blocker exits it.
push_repo_id=''
read_push_repository_id() {
  local push_url_text repo_id_text
  local repo_reason='cannot read the GitHub repository of the push remote'
  [ -z "$push_warning" ] || return 0
  push_url_text="$(git remote get-url --push --all "$pushed_remote" 2>/dev/null)" || return 0
  case "$push_url_text" in
    ''|*$'\n'*) return 0 ;;
  esac
  case "$push_url_text" in
    https://*@*) return 0 ;;
    https://*|ssh://*|git@*) ;;
    *) return 0 ;;
  esac
  gh repo view --json id -- "$push_url_text" </dev/null >"$repo_file" 2>/dev/null || return 0
  repo_id_text="$(jq -r -s 'if length == 1 and (.[0] | type) == "object" and (.[0].id | type) == "string"
    and (.[0].id | test("\\A[A-Za-z0-9_=+/-]+\\z")) then .[0].id else error("not a repository id") end' \
    "$repo_file" 2>/dev/null)" || blocker "$repo_reason"
  push_repo_id="$repo_id_text"
}
read_push_repository_id
if [ -z "$push_repo_id" ] && [ -z "$push_warning" ]; then
  push_warning='gh cannot read the push remote as a GitHub repository; the PR head repository was not checked'
fi

# is_pr_url <value>
#   Succeeds when <value> passes the PR URL identifier gate and ends in /pull/<n>.
is_pr_url() {
  local url_text="$1"
  local url_pattern='^https://[A-Za-z0-9._/-]+/pull/[0-9]+$'
  [[ "$url_text" =~ $url_pattern ]]
}

# ── Reuse ───────────────────────────────────────────────────────────────────

carrying_count=0
carrying_url=''
if [ -n "$push_repo_id" ]; then
  read_count=0
  while :; do
    read_count=$((read_count + 1))
    read_open_prs "$pushed_commit" "$push_repo_id" || blocker "the open PRs could not be read after the push"
    [ "$carrying_count" -le 1 ] || blocker "more than one open PR carries the pushed commit"
    [ "$carrying_count" -eq 0 ] || break
    [ "$named_count" -gt 0 ] || break
    [ "$read_count" -lt "$reread_limit" ] || break
    sleep "$reread_delay"
  done
fi

if [ "$carrying_count" -eq 1 ]; then
  is_pr_url "$carrying_url" || blocker "PR URL contains characters outside the safe allowlist"
  pr_url="$carrying_url"
  created_value=false
  if [ "$comment_given" = true ]; then
    comment_number="${pr_url##*/}"
    hivemind_assert_identifier "$comment_number" || blocker "PR number contains characters outside the safe allowlist"
    comment_rc=0
    gh pr comment "$comment_number" --body-file="$comment_file" </dev/null >/dev/null 2>"$comment_err_file" || comment_rc=$?
    [ ! -s "$comment_err_file" ] || cat -- "$comment_err_file" >&2
    [ "$comment_rc" -eq 0 ] || blocker "the PR comment could not be posted"
    commented_value=true
  fi
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
  gh pr view "$pr_number" --json headRefName,headRefOid,headRepository </dev/null >"$view_file" 2>/dev/null \
    || blocker "could not read the PR head branch or head SHA"
  view_shape="$(jq -r 'if type == "object" and (.headRefName | type) == "string" and (.headRefOid | type) == "string"
    and (.headRepository == null or ((.headRepository | type) == "object" and (.headRepository.id | type) == "string"))
    then "ok" else "bad" end' "$view_file" 2>/dev/null)" \
    || blocker "could not read the PR head branch or head SHA"
  [ "$view_shape" = ok ] || blocker "could not read the PR head branch or head SHA"
  head_match="$(jq -r --arg head "$head_name" '.headRefName == $head' "$view_file" 2>/dev/null)" \
    || blocker "could not read the PR head branch or head SHA"
  [ "$head_match" = true ] || blocker "PR head branch does not match head"
  oid_match="$(jq -r --arg commit "$pushed_commit" '.headRefOid == $commit' "$view_file" 2>/dev/null)" \
    || blocker "could not read the PR head branch or head SHA"
  [ "$oid_match" = true ] || blocker "PR head SHA does not match the pushed commit"
  if [ -n "$push_repo_id" ]; then
    repo_match="$(jq -r --arg repo "$push_repo_id" '.headRepository != null and .headRepository.id == $repo' "$view_file" 2>/dev/null)" \
      || blocker "could not read the PR head branch or head SHA"
    [ "$repo_match" = true ] || blocker "PR head repository does not match the push remote"
  fi
  created_value=true
fi

# The warning line carries push-branch.sh's warning or the HEAD REPOSITORY warning. The
# commented line appears only when the inputs carry comment.
if [ "$comment_given" = true ]; then
  if [ -n "$push_warning" ]; then
    printf 'url: %s\nhead_ref_oid: %s\ncreated: %s\ncommented: %s\nwarning: %s\n' "$pr_url" "$pushed_commit" "$created_value" "$commented_value" "$push_warning"
  else
    printf 'url: %s\nhead_ref_oid: %s\ncreated: %s\ncommented: %s\n' "$pr_url" "$pushed_commit" "$created_value" "$commented_value"
  fi
else
  if [ -n "$push_warning" ]; then
    printf 'url: %s\nhead_ref_oid: %s\ncreated: %s\nwarning: %s\n' "$pr_url" "$pushed_commit" "$created_value" "$push_warning"
  else
    printf 'url: %s\nhead_ref_oid: %s\ncreated: %s\n' "$pr_url" "$pushed_commit" "$created_value"
  fi
fi
