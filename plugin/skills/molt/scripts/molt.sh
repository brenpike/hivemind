#!/usr/bin/env bash
#
# molt: THIN executable entrypoint (ADR-0020) that makes one checkpoint commit of exactly the
# listed files in ONE process. It reads the inputs file once, reads the branch, trunk's refs and
# the tree state, refuses before any change, then stages the dirty listed paths, commits them
# with a message built by jq, and verifies the result with the values it checked. A change is a
# write to a branch ref, HEAD, the index, the work tree or git config. It never pushes.
#
# INPUT (`--flag value` form only; each flag exactly once; unknown, duplicate, or missing flags
# give the fixed usage blocker):
#   --trunk <branch>    REQUIRED. Resolved trunk branch name. It may be absent locally.
#   --inputs <path>     REQUIRED. The inputs file, a JSON object the caller wrote with the Write
#                       tool (`.hivemind/molt-inputs-<token>.json`). A relative path is resolved
#                       from the folder the script was started in, before the script moves to
#                       the top of the work tree.
# trunk passes hivemind_assert_identifier (_shared/allowlist.sh: non-empty, no leading `-`, no
# `..`, charset ^[A-Za-z0-9._/-]+$) before any git command runs (`trunk contains characters
# outside the safe allowlist`). The script then runs plain git from the top of the work tree
# (`git rev-parse --show-toplevel`), never `git -C` (ADR-0037 decision 25).
#
# INPUTS FILE (read once, with jq, into a private copy; no field enters shell or jq program
# source, per ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md, Inert Inputs-File Navigator
# Pattern). Fields, checked in this order, first failure wins:
#   type      REQUIRED. feat|fix|hotfix|refactor|docs|test|chore|ci.
#   scope     optional. A string that passes hivemind_assert_identifier.
#   breaking  optional. true or false. true adds `!` before the colon of the subject line.
#   subject   REQUIRED. One line of text with a non-space character and no control character,
#             at most 72 characters (Unicode code points).
#   body      optional. Text with no control character other than newline and tab. A body of
#             only spaces, tabs and newlines is the same as no body.
#   files     REQUIRED. An array of exact paths relative to the top of the work tree. Each entry
#             is a non-empty string with no control character, no leading `/`, and no empty,
#             `.`, `..` or `.git` (any case) path component. An entry that names a directory in
#             the work tree (not a symlink) is refused. The array may be empty.
# No other field is allowed. When breaking is not true, a subject that contains `!:` or a body
# line that starts with `BREAKING CHANGE:` or `BREAKING-CHANGE:` is refused, so the marker
# bump-type reads always agrees with `breaking`. The message is
#   <type>[(<scope>)][!]: <subject>
# followed by a blank line and the body when there is one. The rule that the message carries no
# attribution string is the caller's judgment (the molt SKILL.md), not checked here.
#
# REFUSALS (fixed blockers, checked in this order, before any change; ADR-0037 invariant 1):
#   inputs       the inputs file is missing (`inputs file not found`), resolves outside the
#                checkout through a symlinked leaf or folder (`inputs file resolves outside the
#                checkout`, checked before the first read), is not exactly one valid JSON value
#                (`inputs file is not valid JSON`), or breaks a field rule above (one fixed
#                reason per rule).
#   in progress  a merge (MERGE_HEAD), rebase (rebase-merge, rebase-apply, REBASE_HEAD),
#                cherry-pick (CHERRY_PICK_HEAD), revert (REVERT_HEAD), cherry-pick or revert
#                sequence (sequencer), or bisect (BISECT_START, BISECT_LOG), each looked up with
#                `git rev-parse --git-path` so a linked worktree reads its own state.
#   unmerged     `git ls-files -u` reports any path.
#   detached     HEAD is not a symbolic ref to refs/heads/<branch> (`HEAD is detached`).
#   unborn       the current branch has no commit yet.
#   branch name  the current branch fails hivemind_assert_identifier.
#   trunk        trunk names the current branch: as text, ignoring ASCII case, it is the branch
#                or ends with `/` followed by it, or a ref trunk names (git's six-rule lookup
#                order, symbolic refs followed to their end) does (`the current branch is
#                trunk`). When git cannot read refs/heads/<trunk>, or prints no end for a
#                symbolic candidate, the run stops with `cannot read trunk`. A trunk that names
#                more than one existing ref does not stop the run, and neither does a trunk that
#                names no ref.
#   outside      `git status --porcelain=v1 -z --untracked-files=all --no-renames` reports a
#                dirty path that is not in files. Each such path is printed to stderr as an
#                `outside: <JSON string>` line, in status order, then the blocker `the working
#                tree has dirty paths outside files`. Ignored files are not reported, so they
#                are allowed. A rename is reported as its two sides, so both must be listed.
#
# ACTION:
#   nothing listed is dirty   no change; prints the current HEAD with `committed: false`.
#   otherwise                 `git add -A` of each dirty listed path whose work tree side
#                             differs from the index (literal pathspecs through
#                             GIT_LITERAL_PATHSPECS=1, so `*`, `:` and a leading `-` are plain
#                             bytes); a path already fully staged is left as it is. When the
#                             index then equals HEAD, it prints `committed: false`. Else
#                             `git commit --cleanup=whitespace -F -` with the message piped from
#                             jq, then the checks below.
#   After a commit: HEAD must still be refs/heads/<branch>, HEAD must be a new commit whose one
#   parent is the old HEAD, every path the new commit changes, read from the commit itself with
#   `git diff-tree`, must be in files (`the commit has a path outside files`, as when a
#   pre-commit hook staged another file), and no listed path may be dirty (`a listed path is
#   still dirty after the commit`, as when a pre-commit hook rewrote a file without staging it).
#   After a change, the only blockers are failed git actions and these result checks; none of
#   them refuses the request.
#
# OUTPUT on success (exit 0), on stdout in ONE write:
#   branch: <b>
#   commit: <full sha of HEAD>
#   committed: true|false
# EXIT CONTRACT:
#   0  routing lines on stdout
#   1  NOTHING on stdout. stderr carries zero or more `outside: <JSON string>` lines (only for
#      the outside refusal), then `blocker: <fixed reason>` as the LAST line. Every git call
#      discards git's own stderr. Blocker text never echoes a caller- or repository-supplied
#      value; an outside line carries a repository path only as a JSON string.
#
# NOT CHECKED: repo hooks, local refs, git config, and the operator are trusted under
# ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Shell Identifier Discipline). A commit-msg
# hook can rewrite the message, and a post-commit hook can change files or refs; the result
# checks catch a moved HEAD, a committed path outside files and a dirty listed path, and anything
# else is a recorded residual. The status read and the commit are not atomic: a hook or another
# process that stages an unlisted path between them has it committed, and the result check then
# stops the run with that commit in place; one that edits a listed path has the edit staged. A
# failed commit leaves the listed paths staged; a rerun stages them again and changes nothing
# else.
# jq decodes status paths as UTF-8, so a path with bytes that are not UTF-8 shows with
# replacement characters on its outside line and can never be listed. A listed path that is an
# untracked ignored file is not dirty, so it is not committed. A submodule path is a directory,
# so it cannot be listed, and its changes are dirty paths outside files. When `.hivemind/` is not
# ignored, the inputs file itself is a dirty path outside files and the run stops there. The
# trunk lookup order is mirrored from git, not asked of git, and git 2.25 shows only the end of
# a symbolic-ref chain, with the same residuals as create-working-branch.sh. The private work
# folder (mktemp -d under TMPDIR) holds the inputs copy, the status listing and the commit's path
# listing, and is removed by the EXIT trap.
#
# Conventions (ADR-0020 thin entrypoint): `set -euo pipefail`, an EXIT trap ending in a
# guaranteed-zero `:`, self-location via `cd && pwd -P`, NO `realpath`/`readlink`; bash 3.2
# compatible (no mapfile / associative arrays / ${var,,}). The identifier gate comes from
# _shared/allowlist.sh, the inputs read-guard from _shared/containment.sh, and the name rule,
# the in-progress and unmerged checks and the trunk ref walk from _shared/git-refusals.sh; this
# script maps their results to its own blockers.

set -euo pipefail
trap ':' EXIT

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# layout plugin/skills/molt/scripts/ => ../../_shared is the shared-library dir.
# cd && pwd -P is portable (no realpath/readlink). NO ${CLAUDE_PLUGIN_ROOT} inside an engine
# script. SOURCE-OR-DIE: a missing/unparseable library fails closed before any git command.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
shared_dir="$(CDPATH= cd -- "$script_dir/../../_shared" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve skills/_shared from the script directory; refusing to proceed"
[ -f "$shared_dir/allowlist.sh" ] || blocker "required shared library missing: skills/_shared/allowlist.sh; refusing to proceed"
. "$shared_dir/allowlist.sh" || blocker "failed to source skills/_shared/allowlist.sh (unparseable); refusing to proceed"
[ -f "$shared_dir/containment.sh" ] || blocker "required shared library missing: skills/_shared/containment.sh; refusing to proceed"
. "$shared_dir/containment.sh" || blocker "failed to source skills/_shared/containment.sh (unparseable); refusing to proceed"
[ -f "$shared_dir/git-refusals.sh" ] || blocker "required shared library missing: skills/_shared/git-refusals.sh; refusing to proceed"
. "$shared_dir/git-refusals.sh" || blocker "failed to source skills/_shared/git-refusals.sh (unparseable); refusing to proceed"

export LC_ALL=C
export GIT_TERMINAL_PROMPT=0

usage_reason='invalid arguments; usage: molt.sh --trunk <branch> --inputs <path>'

trunk_name=''
trunk_seen=false
inputs_arg=''
inputs_seen=false
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || blocker "$usage_reason"
  case "$1" in
    --trunk)
      [ "$trunk_seen" = false ] || blocker "$usage_reason"
      trunk_name="$2"
      trunk_seen=true
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

[ "$trunk_seen" = true ] && [ "$inputs_seen" = true ] || blocker "$usage_reason"
[ -n "$inputs_arg" ] || blocker "$usage_reason"
hivemind_assert_identifier "$trunk_name" || blocker "trunk contains characters outside the safe allowlist"

case "$inputs_arg" in
  /*) INPUTS_FILE="$inputs_arg" ;;
  *) INPUTS_FILE="$PWD/$inputs_arg" ;;
esac

command -v git >/dev/null 2>&1 || blocker "git not found on PATH"
command -v jq >/dev/null 2>&1 || blocker "jq not found on PATH"
inside_work_tree="$(git rev-parse --is-inside-work-tree 2>/dev/null)" || blocker "not inside a git checkout"
[ "$inside_work_tree" = true ] || blocker "not inside a git checkout"
work_tree_top="$(git rev-parse --show-toplevel 2>/dev/null)" || blocker "cannot read the top of the work tree"
[ -n "$work_tree_top" ] || blocker "cannot read the top of the work tree"
CDPATH= cd -- "$work_tree_top" 2>/dev/null || blocker "cannot read the top of the work tree"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-molt.XXXXXX" 2>/dev/null)" || blocker "cannot create a private work folder"
# remove_work_dir
#   Removes the private work folder. Runs from the EXIT trap.
remove_work_dir() {
  rm -rf -- "$work_dir" 2>/dev/null
  return 0
}
trap 'remove_work_dir; :' EXIT
inputs_copy="$work_dir/inputs.json"
status_file="$work_dir/status.z"
commit_paths_file="$work_dir/commit-paths.z"

# ── Inputs ──────────────────────────────────────────────────────────────────

[ -f "$INPUTS_FILE" ] || blocker "inputs file not found"
hivemind_assert_inputs_contained "$work_tree_top" "$INPUTS_FILE" >/dev/null 2>&1 || blocker "inputs file resolves outside the checkout"
jq -c -s 'if length == 1 then .[0] else error("not one JSON value") end' "$INPUTS_FILE" >"$inputs_copy" 2>/dev/null \
  || blocker "inputs file is not valid JSON"

# The field rules from the header, in order. Prints the fixed reason of the first rule the
# inputs break, or an empty line when every rule holds.
validate_program='
def type_names: ["feat", "fix", "hotfix", "refactor", "docs", "test", "chore", "ci"];
def known_keys: ["type", "scope", "breaking", "subject", "body", "files"];
def is_one_line: explode | all(.[]; . >= 32 and . != 127);
def is_text_block: explode | all(.[]; . == 9 or . == 10 or (. >= 32 and . != 127));
def is_exact_path:
  type == "string" and length > 0 and is_one_line and (startswith("/") | not)
  and (split("/") | all(.[]; . != "" and . != "." and . != ".." and ascii_downcase != ".git"));
def has_breaking_marker:
  (.subject | contains("!:"))
  or (("\n" + (.body // "")) | test("\nBREAKING[ -]CHANGE:"));
if type != "object" then "inputs must be a JSON object"
elif (keys - known_keys | length) > 0 then "inputs have a field other than type, scope, breaking, subject, body and files"
elif (.type | type) != "string" then "type must be one of feat fix hotfix refactor docs test chore ci"
elif (.type as $type_name | any(type_names[]; . == $type_name) | not) then "type must be one of feat fix hotfix refactor docs test chore ci"
elif has("scope") and ((.scope | type) != "string" or .scope == "" or (.scope | is_one_line | not)) then "scope contains characters outside the safe allowlist"
elif has("breaking") and (.breaking | type) != "boolean" then "breaking must be true or false"
elif (.subject | type) != "string" then "subject must be one line of text"
elif (.subject | is_one_line | not) or (.subject | test("[^ ]") | not) then "subject must be one line of text"
elif (.subject | length) > 72 then "subject must be 72 characters or fewer"
elif has("body") and (.body | type) != "string" then "body must be text with no control characters other than newline and tab"
elif has("body") and (.body | is_text_block | not) then "body must be text with no control characters other than newline and tab"
elif .breaking != true and has_breaking_marker then "the subject or body has a breaking change marker but breaking is not true"
elif (.files | type) != "array" then "files must be an array of exact paths relative to the top of the work tree"
elif (.files | all(.[]; is_exact_path) | not) then "files must be an array of exact paths relative to the top of the work tree"
else "" end
'
inputs_reason="$(jq -r "$validate_program" "$inputs_copy" 2>/dev/null)" || blocker "cannot read the inputs file"
[ -z "$inputs_reason" ] || blocker "$inputs_reason"

scope_value="$(jq -r '.scope // ""' "$inputs_copy" 2>/dev/null)" || blocker "cannot read the inputs file"
if [ -n "$scope_value" ]; then
  hivemind_assert_identifier "$scope_value" || blocker "scope contains characters outside the safe allowlist"
fi

# Every listed path is one line (the field rules), so a newline-separated listing is exact.
listed_paths="$(jq -r '.files[]' "$inputs_copy" 2>/dev/null)" || blocker "cannot read the inputs file"
while IFS= read -r listed_path; do
  [ -n "$listed_path" ] || continue
  if [ -d "./$listed_path" ] && [ ! -L "./$listed_path" ]; then
    blocker "a files entry names a directory"
  fi
done <<EOF
$listed_paths
EOF

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

# refuse_trunk_branch
#   Blocks when trunk names the current branch, as text or through a ref trunk names, and when
#   git cannot read trunk. A trunk that names more than one existing ref passes. Runs in the main
#   shell so blocker exits it.
refuse_trunk_branch() {
  local name_rc=0 trunk_rc=0
  hivemind_ref_names_branch "$trunk_name" "$branch_name" || name_rc=$?
  case "$name_rc" in
    0) blocker "the current branch is trunk" ;;
    1) ;;
    *) blocker "cannot compare the current branch with trunk" ;;
  esac
  hivemind_resolve_name_refs "$trunk_name" "$branch_name" || trunk_rc=$?
  case "$trunk_rc" in
    0) ;;
    1) blocker "the current branch is trunk" ;;
    3) blocker "cannot compare the current branch with trunk" ;;
    *) blocker "cannot read trunk" ;;
  esac
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

# read_status_listing
#   Writes the NUL-separated porcelain v1 status, untracked files listed one by one and renames
#   split into their two sides, to the private status file. Runs in the main shell so blocker
#   exits it.
read_status_listing() {
  GIT_OPTIONAL_LOCKS=0 git status --porcelain=v1 -z --untracked-files=all --no-renames >"$status_file" 2>/dev/null \
    || blocker "cannot read the working tree status"
}

# Status entries from the private status file, each `{code, path, listed}`, where listed is
# true when the path is an entry of files.
entries_program='
($status_text | split("\u0000") | map(select(length > 3))) as $raw_entries
| (.files | map({key: ., value: true}) | from_entries) as $listed_set
| [$raw_entries[] | {code: .[0:2], path: .[3:]} | .listed = ($listed_set[.path] == true)]
'

refuse_operation_in_progress
refuse_unmerged_paths

head_ref_rc=0
head_ref="$(git symbolic-ref --quiet HEAD 2>/dev/null)" || head_ref_rc=$?
case "$head_ref_rc" in
  0) ;;
  1) blocker "HEAD is detached" ;;
  *) blocker "cannot read the current branch" ;;
esac
case "$head_ref" in
  refs/heads/?*) branch_name="${head_ref#refs/heads/}" ;;
  *) blocker "HEAD is detached" ;;
esac
old_head="$(git rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null)" || blocker "the current branch has no commit"
is_full_object_id "$old_head" || blocker "the current branch has no commit"
hivemind_assert_identifier "$branch_name" || blocker "the current branch name contains characters outside the safe allowlist"
refuse_trunk_branch

# ── Dirty paths ─────────────────────────────────────────────────────────────

read_status_listing
outside_lines="$(jq -r --rawfile status_text "$status_file" "$entries_program"' | .[] | select(.listed | not) | "outside: " + (.path | tojson)' "$inputs_copy" 2>/dev/null)" \
  || blocker "cannot read the working tree status"
if [ -n "$outside_lines" ]; then
  printf '%s\n' "$outside_lines" >&2
  blocker "the working tree has dirty paths outside files"
fi

listed_dirty_count="$(jq -r --rawfile status_text "$status_file" "$entries_program"' | map(select(.listed)) | length' "$inputs_copy" 2>/dev/null)" \
  || blocker "cannot read the working tree status"

if [ "$listed_dirty_count" = 0 ]; then
  printf 'branch: %s\ncommit: %s\ncommitted: %s\n' "$branch_name" "$old_head" false
  exit 0
fi

# ── Stage and commit ────────────────────────────────────────────────────────

# Listed paths are one line each (the field rules), so this newline-separated listing is exact.
add_listing="$(jq -r --rawfile status_text "$status_file" "$entries_program"' | .[] | select(.listed and (.code == "??" or .code[1:2] != " ")) | .path' "$inputs_copy" 2>/dev/null)" \
  || blocker "cannot read the working tree status"
add_paths=()
while IFS= read -r add_path; do
  [ -n "$add_path" ] || continue
  add_paths+=("$add_path")
done <<EOF
$add_listing
EOF
if [ "${#add_paths[@]}" -gt 0 ]; then
  GIT_LITERAL_PATHSPECS=1 git add -A -- "${add_paths[@]}" >/dev/null 2>&1 || blocker "could not stage the listed paths"
fi

staged_rc=0
git diff --cached --quiet --no-ext-diff >/dev/null 2>&1 || staged_rc=$?
case "$staged_rc" in
  0)
    printf 'branch: %s\ncommit: %s\ncommitted: %s\n' "$branch_name" "$old_head" false
    exit 0
    ;;
  1) ;;
  *) blocker "cannot read the index" ;;
esac

message_program='
.type
+ (if (.scope // "") != "" then "(" + .scope + ")" else "" end)
+ (if .breaking == true then "!" else "" end)
+ ": " + .subject
+ (if ((.body // "") | test("[^ \t\n]")) then "\n\n" + .body else "" end)
+ "\n"
'
jq -j "$message_program" "$inputs_copy" 2>/dev/null | git commit --quiet --cleanup=whitespace -F - >/dev/null 2>&1 \
  || blocker "the commit failed"

# ── Result checks ───────────────────────────────────────────────────────────

final_ref="$(git symbolic-ref --quiet HEAD 2>/dev/null)" || blocker "HEAD is not on the branch after the commit"
[ "$final_ref" = "refs/heads/$branch_name" ] || blocker "HEAD is not on the branch after the commit"
new_head="$(git rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null)" || blocker "HEAD does not resolve to a commit after the commit"
is_full_object_id "$new_head" || blocker "HEAD does not resolve to a commit after the commit"
[ "$new_head" != "$old_head" ] || blocker "the commit did not make a new commit"
parent_line="$(git rev-list --parents --max-count=1 "$new_head" 2>/dev/null)" || blocker "cannot read the new commit"
[ "$parent_line" = "$new_head $old_head" ] || blocker "the parent of the new commit is not the old HEAD"

# The paths the new commit changes, NUL-separated, read from the commit and not from the status
# taken before it, so a path a hook or another process staged after the status read is seen.
git diff-tree -r -z --no-renames --name-only "$old_head" "$new_head" >"$commit_paths_file" 2>/dev/null \
  || blocker "cannot read the new commit"
unlisted_count="$(jq -r --rawfile commit_text "$commit_paths_file" '
(.files | map({key: ., value: true}) | from_entries) as $listed_set
| [$commit_text | split("\u0000")[] | select(length > 0) | select($listed_set[.] != true)] | length
' "$inputs_copy" 2>/dev/null)" || blocker "cannot read the new commit"
[ "$unlisted_count" = 0 ] || blocker "the commit has a path outside files"

read_status_listing
remaining_count="$(jq -r --rawfile status_text "$status_file" "$entries_program"' | map(select(.listed)) | length' "$inputs_copy" 2>/dev/null)" \
  || blocker "cannot read the working tree status"
[ "$remaining_count" = 0 ] || blocker "a listed path is still dirty after the commit"

printf 'branch: %s\ncommit: %s\ncommitted: %s\n' "$branch_name" "$new_head" true
