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
#   NAME LOOKUP: the two name functions below look a name up the way git does (gitrevisions),
#   six candidates in this order: <name>, refs/<name>, refs/tags/<name>, refs/heads/<name>,
#   refs/remotes/<name>, refs/remotes/<name>/HEAD. hivemind__set_name_candidates builds this
#   list and is its one copy. A name names a branch by ref identity, never by its text: a
#   candidate, or the end a candidate resolves to, must equal one of the branch's refs. A text
#   suffix is not enough, so team/main, release/feature/x and refs/heads/team/main do not name
#   main or feature/x. Every comparison is exact string equality after an ASCII case fold (see
#   RECORDED RESIDUAL R1 below).
#
#   hivemind_ref_names_branch <name text> <branch>
#     Succeeds when one NAME LOOKUP candidate of <name text> equals refs/heads/<branch>, both
#     ASCII case folded. So only the spellings <branch>, heads/<branch> and refs/heads/<branch>
#     match. Runs no git command, so it cannot see a remote image or a symbolic ref;
#     hivemind_resolve_name_refs does.
#     Returns 0 names the branch, 1 does not, 2 cannot compare (an empty <branch>, or the case
#     fold failed).
#
#   hivemind_resolve_name_refs <name> <branch>
#     Reads every ref <name> names, once, walking the NAME LOOKUP candidates in order. A
#     candidate that `git symbolic-ref --quiet` reads as a symbolic ref names the end of its
#     chain as git prints it, even when that end does not exist yet. A candidate under refs/
#     that is not symbolic names itself when `git show-ref --verify` finds it. Any other
#     candidate names no ref. Two candidates that end at the same ref name one ref. A candidate
#     other than refs/heads/<name> that git cannot read names no ref.
#     With a non-empty <branch>, it first reads `git remote` once and builds the branch refs:
#     refs/heads/<branch>, plus refs/remotes/<remote>/<branch> for each remote git lists. A
#     remote name may contain `/` and is used whole, never split. No remote is assumed: origin
#     counts only when git lists it. Then, for each candidate in lookup order, the walk stops
#     with 1 when the candidate itself (existing or not) equals a branch ref, and next when the
#     end it names (dangling or not) does. Pass an empty <branch> to read the refs with no
#     branch check and no `git remote` read. Callers pass a trunk or base name as <name>.
#     Returns 0 the walk ended, 1 a ref names the branch, 2 cannot read <name> (git cannot read
#     refs/heads/<name>, or prints no end for a symbolic candidate), 3 cannot compare a ref with
#     the branch (`git remote` failed, or a case fold failed). `git remote` is read before the
#     walk. Codes 1, 2 and 3 from the walk come from the first candidate, in lookup order, that
#     raises one. On return 0 it also sets:
#       HIVEMIND_NAME_AMBIGUOUS  true when the refs <name> names that exist are more than one
#                                ref (a dangling end is not counted), else false. Reported
#                                apart from the return code; the caller decides whether to
#                                refuse it.
#       HIVEMIND_NAME_REF        the one existing ref <name> names, or empty when it names no
#                                existing ref or is ambiguous.
#     HIVEMIND_CANDIDATE_END and HIVEMIND_CANDIDATE_EXISTS hold the last candidate read, and
#     HIVEMIND__NAME_CANDIDATES holds the last NAME LOOKUP list built. They are internal to the
#     walk and carry no contract.
#
#   hivemind_branch_is_remote_default <branch>
#     Tells whether <branch> is the default branch of a remote git lists. It reads `git remote`
#     once and builds the same branch refs as hivemind_resolve_name_refs: refs/heads/<branch>,
#     plus refs/remotes/<remote>/<branch> for each listed remote. Then, for each listed remote in
#     `git remote` order, it reads `git symbolic-ref --quiet refs/remotes/<remote>/HEAD` once. A
#     remote name may contain `/` and is used whole, never split. When the end that HEAD ref
#     names (dangling or not) equals a branch ref, both ASCII case folded, <branch> is that
#     remote's default branch. A remote with no HEAD ref, or a HEAD ref that is not symbolic,
#     has no default branch record, so the branch cannot be cleared against it: that gives 4.
#     `git remote set-head <remote> --auto` writes the record. No remote is assumed: with no
#     listed remote, no branch is a default.
#     Returns 0 no listed remote's default branch is <branch>, 1 <branch> is a listed remote's
#     default branch, 2 cannot read a remote HEAD (a git error other than not symbolic or
#     absent, or git prints no end), 3 cannot compare (an empty <branch>, `git remote` failed, or
#     a case fold failed), 4 a listed remote has no default branch record (its HEAD ref is absent
#     or not symbolic). Codes 1, 2, 3 and 4 from the remote reads come from the first remote, in
#     `git remote` order, that raises one.
#
#   HIVEMIND__REMOTE_LISTING and HIVEMIND__BRANCH_REFS hold the last `git remote` listing read
#   and the last branch refs built, for both functions above. They are internal and carry no
#   contract.
#
#   REMOTE IMAGE LAYOUT: the branch refs above assume each remote fetches with git's default
#   layout, refs/remotes/<remote>/*. A remote whose fetch refspec maps its branches elsewhere
#   is not seen as an image of the branch. Deferred:
#   https://github.com/brenpike/hivemind/issues/409#issuecomment-6303470852
#
#   RECORDED RESIDUAL R1 (case fold): both name functions and hivemind_branch_is_remote_default
#     fold ASCII case before they compare.
#     Root cause:  a case-insensitive file system stores refs/heads/Main and refs/heads/main as
#                  one file, so there the two spellings are one branch.
#     Bounded impact: on a case-sensitive file system two case-variant branches (Main and main)
#                  are two refs, and the fold treats them as one. A check then over-refuses: it
#                  blocks Main when trunk is main. It never lets a branch through that it
#                  should refuse, so it fails safe. Inherited from 6.1.0.
#     Rejected remediation:
#                  - keying the fold on core.ignorecase: that setting describes only this
#                    checkout's file system, not the remote host or any other clone.
#     Linked:      PR #421 review comment r4330910585, PR #420 review comment r4328340771.
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

# hivemind__fold_ascii_case <text>
#   Prints <text> with ASCII A-Z folded to a-z. Returns the status of the fold. INTERNAL (double
#   underscore): not a caller entry point.
hivemind__fold_ascii_case() {
  printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z'
}

# hivemind__set_name_candidates <name>
#   Sets HIVEMIND__NAME_CANDIDATES to the NAME LOOKUP list for <name>, in order. INTERNAL (double
#   underscore): not a caller entry point.
hivemind__set_name_candidates() {
  local name_text="$1"
  HIVEMIND__NAME_CANDIDATES=("$name_text" "refs/$name_text" "refs/tags/$name_text" \
    "refs/heads/$name_text" "refs/remotes/$name_text" "refs/remotes/$name_text/HEAD")
}

# hivemind__matches_any_ref <ref> <branch ref>...
#   Returns 0 when <ref> equals one <branch ref> exactly, else 1. INTERNAL (double underscore):
#   not a caller entry point.
hivemind__matches_any_ref() {
  local ref_text="$1"
  local branch_ref
  shift
  for branch_ref in "$@"; do
    [ "$ref_text" != "$branch_ref" ] || return 0
  done
  return 1
}

# hivemind__set_branch_refs <branch>
#   Reads `git remote` once into HIVEMIND__REMOTE_LISTING, as git prints it. Sets
#   HIVEMIND__BRANCH_REFS to refs/heads/<branch> plus refs/remotes/<remote>/<branch> for each
#   listed remote, all ASCII case folded. Returns 3 when `git remote` or a case fold fails, else 0.
#   INTERNAL (double underscore): not a caller entry point.
hivemind__set_branch_refs() {
  local branch_text="$1"
  local remote_folded remote_name branch_folded
  HIVEMIND__REMOTE_LISTING="$(git remote 2>/dev/null)" || return 3
  remote_folded="$(hivemind__fold_ascii_case "$HIVEMIND__REMOTE_LISTING")" || return 3
  branch_folded="$(hivemind__fold_ascii_case "$branch_text")" || return 3
  HIVEMIND__BRANCH_REFS=("refs/heads/$branch_folded")
  while IFS= read -r remote_name; do
    [ -n "$remote_name" ] || continue
    HIVEMIND__BRANCH_REFS+=("refs/remotes/$remote_name/$branch_folded")
  done <<EOF
$remote_folded
EOF
  return 0
}

# hivemind_ref_names_branch <name text> <branch>
#   See API above. INVARIANT: every NAME LOOKUP prefix is lower case ASCII, so the candidates
#   built from the folded name equal the folded candidates.
hivemind_ref_names_branch() {
  local name_text="$1"
  local branch_text="$2"
  local name_folded branch_folded candidate_name
  [ -n "$branch_text" ] || return 2
  name_folded="$(hivemind__fold_ascii_case "$name_text")" || return 2
  branch_folded="$(hivemind__fold_ascii_case "$branch_text")" || return 2
  hivemind__set_name_candidates "$name_folded"
  for candidate_name in "${HIVEMIND__NAME_CANDIDATES[@]}"; do
    if hivemind__matches_any_ref "$candidate_name" "refs/heads/$branch_folded"; then
      return 0
    fi
  done
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
  local candidate_name candidate_folded end_folded existing_end='' candidate_rc
  HIVEMIND_NAME_AMBIGUOUS=false
  HIVEMIND_NAME_REF=''
  if [ -n "$branch_text" ]; then
    hivemind__set_branch_refs "$branch_text" || return 3
  fi
  hivemind__set_name_candidates "$name_text"
  for candidate_name in "${HIVEMIND__NAME_CANDIDATES[@]}"; do
    if [ -n "$branch_text" ]; then
      candidate_folded="$(hivemind__fold_ascii_case "$candidate_name")" || return 3
      if hivemind__matches_any_ref "$candidate_folded" "${HIVEMIND__BRANCH_REFS[@]}"; then
        return 1
      fi
    fi
    candidate_rc=0
    hivemind__read_name_candidate "$candidate_name" "$name_text" || candidate_rc=$?
    [ "$candidate_rc" -eq 0 ] || return 2
    [ -n "$HIVEMIND_CANDIDATE_END" ] || continue
    if [ -n "$branch_text" ]; then
      end_folded="$(hivemind__fold_ascii_case "$HIVEMIND_CANDIDATE_END")" || return 3
      if hivemind__matches_any_ref "$end_folded" "${HIVEMIND__BRANCH_REFS[@]}"; then
        return 1
      fi
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

# hivemind_branch_is_remote_default <branch>
#   See API above.
hivemind_branch_is_remote_default() {
  local branch_text="$1"
  local remote_name head_end end_folded head_rc
  [ -n "$branch_text" ] || return 3
  hivemind__set_branch_refs "$branch_text" || return 3
  while IFS= read -r remote_name; do
    [ -n "$remote_name" ] || continue
    head_rc=0
    head_end="$(git symbolic-ref --quiet "refs/remotes/$remote_name/HEAD" 2>/dev/null)" || head_rc=$?
    case "$head_rc" in
      0) ;;
      1) return 4 ;;
      *) return 2 ;;
    esac
    [ -n "$head_end" ] || return 2
    end_folded="$(hivemind__fold_ascii_case "$head_end")" || return 3
    if hivemind__matches_any_ref "$end_folded" "${HIVEMIND__BRANCH_REFS[@]}"; then
      return 1
    fi
  done <<EOF
$HIVEMIND__REMOTE_LISTING
EOF
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
