# shellcheck shell=bash
#
# git-refusals.sh: shared read-only checks a git script makes before it changes anything. A
# change is a write to a branch ref, HEAD, the index, the work tree or git config. Each check
# reads git state and reports it; the caller decides what to refuse and owns the blocker text.
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute path derived
# from its OWN script_dir (`. "$shared_dir/git-refusals.sh"`). It defines functions only. It runs
# no top-level statements and never exits. Its functions use only locals and set only the
# HIVEMIND_* result globals named below. `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately OMITS the P18
# shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced file mutates the
# SOURCING shell's option state, so installing those here would corrupt every caller's shell; the
# floor is therefore the documented exception, not the full `set -euo pipefail`. This file
# carries no top-level `set` at all (pure function definitions); each caller owns its own
# `set -u` and error routing. Allowlisted under CHECK13 as a P18 documented exception.
#
# Every function handles each git failure itself and reports it in its return code, so it works
# the same whether or not errexit is in force (a call in an `||` or `if` list turns errexit off
# inside the function). Plain `git` from the current folder, never `git -C` (ADR-0037 decision
# 25). bash 3.2 compatible (no mapfile, associative arrays or ${var,,}). Every git call discards
# git's own stderr. A git identifier read from the repository (a ref end) is captured into a
# variable and used only as "$var", per ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md
# (Shell Identifier Discipline). The caller gates every name it passes in (for example with
# hivemind_assert_identifier from _shared/allowlist.sh) before it calls any function here.
#
# API
#
#   hivemind_ref_names_branch <ref text> <branch>
#     Succeeds when <ref text>, ignoring ASCII case, is <branch> or ends with `/` followed by
#     <branch>. Case is ignored because a case-insensitive file system stores refs/heads/Main and
#     refs/heads/main as one file. The `/` rule holds because every git qualifier of a branch
#     (refs/heads/, heads/, <remote>/, refs/remotes/<remote>/) is a leading path in front of the
#     branch name. Runs no git command.
#     Returns 0 names the branch, 1 does not, 2 cannot compare (an empty <branch>, or the case
#     fold failed).
#
#   hivemind_resolve_name_refs <name> <branch>
#     Reads every ref <name> names, once, with git's own lookup order for a name (gitrevisions),
#     six rules: <name>, refs/<name>, refs/tags/<name>, refs/heads/<name>, refs/remotes/<name>,
#     refs/remotes/<name>/HEAD. A candidate that `git symbolic-ref --quiet` reads as a symbolic
#     ref names the end of its chain as git prints it, even when that end does not exist yet. A
#     candidate under refs/ that is not symbolic names itself when `git show-ref --verify` finds
#     it. Any other candidate names no ref. Two candidates that end at the same ref name one ref.
#     A candidate other than refs/heads/<name> that git cannot read names no ref.
#     With a non-empty <branch>, the walk stops at the first candidate whose ref names the branch
#     (hivemind_ref_names_branch), dangling or not. Pass an empty <branch> to read the refs with
#     no branch check. Callers pass a trunk or base name as <name>.
#     Returns 0 the walk ended, 1 a ref names the branch, 2 cannot read <name> (git cannot read
#     refs/heads/<name>, or prints no end for a symbolic candidate), 3 cannot compare a ref with
#     the branch. Codes 1, 2 and 3 come from the first candidate, in lookup order, that raises
#     one. On return 0 it also sets:
#       HIVEMIND_NAME_AMBIGUOUS  true when the refs <name> names that exist are more than one
#                                ref (a dangling end is not counted), else false. Reported
#                                apart from the return code; the caller decides whether to
#                                refuse it.
#       HIVEMIND_NAME_REF        the one existing ref <name> names, or empty when it names no
#                                existing ref or is ambiguous.
#     HIVEMIND_CANDIDATE_END and HIVEMIND_CANDIDATE_EXISTS hold the last candidate read. They
#     are internal to the walk and carry no contract.
#
#   hivemind_find_operation_in_progress
#     Looks up, in this order, each with `git rev-parse --git-path` so a linked worktree reads
#     its own state, and stops at the first that exists:
#       MERGE_HEAD          a merge is in progress
#       rebase-merge        a rebase is in progress
#       rebase-apply        a rebase is in progress
#       REBASE_HEAD         a rebase is in progress
#       CHERRY_PICK_HEAD    a cherry-pick is in progress
#       REVERT_HEAD         a revert is in progress
#       sequencer           a cherry-pick or revert sequence is in progress
#       BISECT_START        a bisect is in progress
#       BISECT_LOG          a bisect is in progress
#     Returns 0 none, 1 one is in progress, 2 cannot read the repository state. Sets
#     HIVEMIND_OPERATION_REASON to the fixed reason on the right above when it returns 1, else
#     to empty.
#
#   hivemind_check_unmerged_paths
#     Reads `git ls-files -u`. Returns 0 no unmerged path, 1 the index has unmerged paths, 2
#     cannot read the index.
#
#   hivemind_read_dirty_kinds
#     Reads `git status --porcelain=v1 --untracked-files=normal` once, with
#     GIT_OPTIONAL_LOCKS=0. Ignored files are not reported. Sets HIVEMIND_DIRTY_STAGED,
#     HIVEMIND_DIRTY_UNSTAGED and HIVEMIND_DIRTY_UNTRACKED to true or false: a staged, an
#     unstaged, or an untracked path is reported. Returns 0 clean, 1 at least one kind is true,
#     2 cannot read the working tree status (all three are then false).

# hivemind_ref_names_branch <ref text> <branch>
#   See API above.
hivemind_ref_names_branch() {
  local ref_text="$1"
  local branch_text="$2"
  local ref_folded branch_folded
  [ -n "$branch_text" ] || return 2
  ref_folded="$(printf '%s' "$ref_text" | LC_ALL=C tr 'A-Z' 'a-z')" || return 2
  branch_folded="$(printf '%s' "$branch_text" | LC_ALL=C tr 'A-Z' 'a-z')" || return 2
  case "$ref_folded" in
    "$branch_folded"|*/"$branch_folded") return 0 ;;
  esac
  return 1
}

# hivemind__read_name_candidate <candidate> <name>
#   Sets HIVEMIND_CANDIDATE_END to the ref <candidate> names, or to empty when it names none, and
#   HIVEMIND_CANDIDATE_EXISTS to true when that ref exists. Returns 2 when git prints no end for a
#   symbolic candidate, or when git cannot read <candidate> and it is refs/heads/<name>. Returns 0
#   otherwise. INTERNAL (double underscore): not a caller entry point.
hivemind__read_name_candidate() {
  local candidate_name="$1"
  local name_text="$2"
  local symbolic_rc=0 verify_rc=0
  HIVEMIND_CANDIDATE_EXISTS=false
  HIVEMIND_CANDIDATE_END="$(git symbolic-ref --quiet "$candidate_name" 2>/dev/null)" || symbolic_rc=$?
  case "$symbolic_rc" in
    0)
      [ -n "$HIVEMIND_CANDIDATE_END" ] || return 2
      git show-ref --verify --quiet "$HIVEMIND_CANDIDATE_END" >/dev/null 2>&1 || verify_rc=$?
      [ "$verify_rc" -ne 0 ] || HIVEMIND_CANDIDATE_EXISTS=true
      return 0
      ;;
    1) HIVEMIND_CANDIDATE_END='' ;;
    *)
      HIVEMIND_CANDIDATE_END=''
      [ "$candidate_name" != "refs/heads/$name_text" ] || return 2
      return 0
      ;;
  esac
  case "$candidate_name" in
    refs/*) ;;
    *) return 0 ;;
  esac
  git show-ref --verify --quiet "$candidate_name" >/dev/null 2>&1 || verify_rc=$?
  case "$verify_rc" in
    0)
      HIVEMIND_CANDIDATE_END="$candidate_name"
      HIVEMIND_CANDIDATE_EXISTS=true
      ;;
    1) ;;
    *) [ "$candidate_name" != "refs/heads/$name_text" ] || return 2 ;;
  esac
  return 0
}

# hivemind_resolve_name_refs <name> <branch>
#   See API above.
hivemind_resolve_name_refs() {
  local name_text="$1"
  local branch_text="$2"
  local candidate_name existing_end='' candidate_rc match_rc
  HIVEMIND_NAME_AMBIGUOUS=false
  HIVEMIND_NAME_REF=''
  for candidate_name in "$name_text" "refs/$name_text" "refs/tags/$name_text" \
    "refs/heads/$name_text" "refs/remotes/$name_text" "refs/remotes/$name_text/HEAD"; do
    candidate_rc=0
    hivemind__read_name_candidate "$candidate_name" "$name_text" || candidate_rc=$?
    [ "$candidate_rc" -eq 0 ] || return 2
    [ -n "$HIVEMIND_CANDIDATE_END" ] || continue
    if [ -n "$branch_text" ]; then
      match_rc=0
      hivemind_ref_names_branch "$HIVEMIND_CANDIDATE_END" "$branch_text" || match_rc=$?
      case "$match_rc" in
        0) return 1 ;;
        1) ;;
        *) return 3 ;;
      esac
    fi
    [ "$HIVEMIND_CANDIDATE_EXISTS" = true ] || continue
    if [ -n "$existing_end" ] && [ "$existing_end" != "$HIVEMIND_CANDIDATE_END" ]; then
      HIVEMIND_NAME_AMBIGUOUS=true
    fi
    existing_end="$HIVEMIND_CANDIDATE_END"
  done
  [ "$HIVEMIND_NAME_AMBIGUOUS" = true ] || HIVEMIND_NAME_REF="$existing_end"
  return 0
}

# hivemind__check_git_path <git-path name> <reason>
#   Returns 1 and sets HIVEMIND_OPERATION_REASON to <reason> when `git rev-parse --git-path
#   <name>` names an existing file or directory. Returns 2 when git cannot give the path, else 0.
#   INTERNAL (double underscore): not a caller entry point.
hivemind__check_git_path() {
  local git_path_name="$1"
  local operation_reason="$2"
  local resolved_path
  resolved_path="$(git rev-parse --git-path "$git_path_name" 2>/dev/null)" || return 2
  [ -n "$resolved_path" ] || return 2
  if [ -e "$resolved_path" ]; then
    HIVEMIND_OPERATION_REASON="$operation_reason"
    return 1
  fi
  return 0
}

# hivemind_find_operation_in_progress
#   See API above.
hivemind_find_operation_in_progress() {
  HIVEMIND_OPERATION_REASON=''
  hivemind__check_git_path MERGE_HEAD "a merge is in progress" || return $?
  hivemind__check_git_path rebase-merge "a rebase is in progress" || return $?
  hivemind__check_git_path rebase-apply "a rebase is in progress" || return $?
  hivemind__check_git_path REBASE_HEAD "a rebase is in progress" || return $?
  hivemind__check_git_path CHERRY_PICK_HEAD "a cherry-pick is in progress" || return $?
  hivemind__check_git_path REVERT_HEAD "a revert is in progress" || return $?
  hivemind__check_git_path sequencer "a cherry-pick or revert sequence is in progress" || return $?
  hivemind__check_git_path BISECT_START "a bisect is in progress" || return $?
  hivemind__check_git_path BISECT_LOG "a bisect is in progress" || return $?
  return 0
}

# hivemind_check_unmerged_paths
#   See API above.
hivemind_check_unmerged_paths() {
  local unmerged_listing
  unmerged_listing="$(git ls-files -u 2>/dev/null)" || return 2
  [ -z "$unmerged_listing" ] || return 1
  return 0
}

# hivemind_read_dirty_kinds
#   See API above. Each status line starts with the two-letter XY code.
hivemind_read_dirty_kinds() {
  local status_output status_line status_code
  HIVEMIND_DIRTY_STAGED=false
  HIVEMIND_DIRTY_UNSTAGED=false
  HIVEMIND_DIRTY_UNTRACKED=false
  status_output="$(GIT_OPTIONAL_LOCKS=0 git status --porcelain=v1 --untracked-files=normal 2>/dev/null)" || return 2
  while IFS= read -r status_line; do
    [ -n "$status_line" ] || continue
    status_code="${status_line:0:2}"
    if [ "$status_code" = '??' ]; then
      HIVEMIND_DIRTY_UNTRACKED=true
      continue
    fi
    [ "${status_code:0:1}" = ' ' ] || HIVEMIND_DIRTY_STAGED=true
    [ "${status_code:1:1}" = ' ' ] || HIVEMIND_DIRTY_UNSTAGED=true
  done <<EOF
$status_output
EOF
  if [ "$HIVEMIND_DIRTY_STAGED" = true ] || [ "$HIVEMIND_DIRTY_UNSTAGED" = true ] \
    || [ "$HIVEMIND_DIRTY_UNTRACKED" = true ]; then
    return 1
  fi
  return 0
}
