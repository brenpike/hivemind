#!/usr/bin/env bash
#
# design-review.sh — engine entrypoint for the hivemind:design-review skill (ADR-0046 decision 6).
# It reads facts the skill needs between review rounds: the record verify result, the stamp blobs
# of the reviewed commit, the round state of a record, the change to the design documents between
# two commits, whether the checkout is clean at the reviewed commit, and the configured reviewer
# model. It makes no judgment of review quality and
# writes nothing: no file, no scratch path, no git write.
#
# Usage:
#   design-review.sh verify --head <commit> --base <commit>
#   design-review.sh stamps --commit <commit> <path>...
#   design-review.sh round --commit <commit> --slug <slug>
#   design-review.sh diff --from <commit> --to <commit> [--names]
#   design-review.sh head --commit <commit>
#   design-review.sh model
#
# Every flag is given once, as `--flag value`; `--names` takes no value. A <commit> is a full
# lowercase object id, 40 or 64 hex, checked before any git call. Every document is read at a
# commit through the readiness check library's Document existence test (hivemind_doc_entry,
# hivemind_doc_read), or for diff as a git diff between two commits, never from the working tree.
# Text reaches jq only on stdin.
#
# OUTPUT CONTRACT
#   verify   Runs hivemind_record_verify <head> <base> (record-verify.sh, pull request mode) and
#            relays its stdout lines, its stderr token and its exit status 0, 1 or 2 unchanged.
#   stamps   Each <path> must pass hivemind_readiness_path_kind (the stamp allowlist) before any
#            git call. Prints one line per path, in argument order: `<path> <blob>` when the path
#            passes the Document existence test at <commit>, else `<path> missing`; a missing path
#            is never stamped. Exit 0.
#   round    <slug> must match ^[a-z0-9]+(-[a-z0-9]+)*$ before any git call. Prints, in order:
#              ui=yes|no|invalid|missing   the first non-blank line after the title of
#                                          docs/prds/<slug>.md at <commit>: exactly
#                                          `**UI:** yes` or `**UI:** no`, any other line or none
#                                          is invalid, and missing when the PRD fails the
#                                          Document existence test
#              record=missing|malformed|present
#                                          docs/initiatives/<slug>/review-record.md at <commit>;
#                                          malformed when its front matter fails the fixed shape
#            then, only when present, `verdict=<pass|fail>`, `rounds=<n>` and `open=<sum of the
#            four open counts>`, then exactly one of, first match wins:
#              stop=passed         the record meets the pass rule: verdict pass, every open count
#                                  0, clean_round true, rounds 2 to 3
#              stop=cap-reached    rounds 3 or more and not passing, open findings or not: no
#                                  fourth round runs, the split-the-initiative signal for the
#                                  maintainer
#              stop=open-findings  rounds below 3 and an open count is above 0
#              next=<n>            the next round to run: 1 when the record is missing, else
#                                  rounds + 1
#            A malformed record prints no line after `record=malformed`. Exit 0.
#   diff     Reads only the paths under docs/prds/, docs/initiatives/ and docs/adr/, as literal
#            pathspecs rooted at the working tree top level, from <from> to <to>, with no rename
#            detection, external diff, textconv, color or diff.relative. Without --names, prints the unified diff of those paths,
#            paths quoted as core.quotePath quotes them. With --names, prints one
#            `<A|M|D|T> <path>` line per changed path, sorted by path, each control character of
#            a path shown as `?`; any other status fails git-failed. No change prints nothing.
#            Output is buffered, so a failure prints none of it. Exit 0.
#   head     Prints `head=ok` and exits 0 only when `git status --porcelain`, untracked files
#            included, is empty and HEAD is <commit>. Else prints `head=dirty` (checked first) or
#            `head=moved` and exits 1.
#   model    Prints `model=<value>` when HIVEMIND_DESIGN_REVIEW_MODEL is set and matches
#            ^[A-Za-z0-9][A-Za-z0-9._:\[\]-]{0,63}$; `model=default` when it is unset or empty;
#            `model=default` then `setting=invalid` when it does not match. A malformed value is
#            never printed. Exit 0.
#
# FAILURE CONTRACT: except for verify's relayed result, a failure leaves stdout empty, prints
# exactly one stderr line `design-review-error: <token>` and exits 2. Tokens:
#   cannot-self-locate, cannot-resolve-shared-dir       bootstrap
#   missing-readiness-check, unparseable-readiness-check
#   missing-record-verify, unparseable-record-verify    a shared library is missing or unparseable
#   usage            unknown subcommand or flag, a repeated flag, a missing value or path, a stamp
#                    path off the allowlist, or a malformed slug
#   jq-missing       jq is not on PATH (verify, stamps, round)
#   commit-malformed a <commit> is not 40 or 64 lowercase hex
#   commit-unresolvable  a <commit> names no commit object (stamps, round, diff)
#   git-failed       a git call or a document read failed
#
# P18 floor: `set -euo pipefail` before the first statement. Self-location (C1), the shared
# directory (C2) and source-or-die of each shared library (C4) follow ADR-0020's canonical forms;
# tools/test_script_bootstrap.sh pins them.

set -euo pipefail

design_review_fail() { printf 'design-review-error: %s\n' "$1" >&2; exit 2; }

script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || design_review_fail "cannot-self-locate"
shared_dir="$(CDPATH= cd -- "$script_dir/../../_shared" 2>/dev/null && pwd -P 2>/dev/null)" || design_review_fail "cannot-resolve-shared-dir"
[ -f "$shared_dir/readiness-check.sh" ] || design_review_fail "missing-readiness-check"
# shellcheck source=../../_shared/readiness-check.sh
. "$shared_dir/readiness-check.sh" || design_review_fail "unparseable-readiness-check"
[ -f "$shared_dir/record-verify.sh" ] || design_review_fail "missing-record-verify"
# shellcheck source=../../_shared/record-verify.sh
. "$shared_dir/record-verify.sh" || design_review_fail "unparseable-record-verify"

# require_flag_value <seen> <remaining-arg-count>: fails usage when the flag was already given or
# has no value after it.
require_flag_value() {
  if [ "$1" -ne 0 ] || [ "$2" -lt 2 ]; then
    design_review_fail usage
  fi
}

# require_jq: fails jq-missing when jq is not on PATH.
require_jq() {
  command -v jq >/dev/null 2>&1 || design_review_fail jq-missing
}

# require_commit <commit>: fails commit-malformed unless <commit> is 40 or 64 lowercase hex.
require_commit() {
  hivemind_readiness_commit_ok "$1" 2>/dev/null || design_review_fail commit-malformed
}

# require_resolved_commit <commit>: fails commit-unresolvable unless <commit> names a commit object.
require_resolved_commit() {
  local object_type=""
  object_type="$(git --no-replace-objects --literal-pathspecs cat-file -t "$1" </dev/null 2>/dev/null)" \
    || object_type=""
  [ "$object_type" = commit ] || design_review_fail commit-unresolvable
}

# design_review_jq_defs: prints the constant jq definitions of round; they need
# hivemind_readiness_jq_defs before them. Each filter runs under rc_doc_eval.
design_review_jq_defs() {
  printf '%s\n' '
def dr_ui:
  .texts | rc_parse | rc_after_title
  | if . == "**UI:** yes" then "yes" elif . == "**UI:** no" then "no" else "invalid" end;
def dr_round:
  [.texts | rc_front_matter] as $front
  | if ($front | length) == 0 then "record=malformed"
    else $front[0] as $fm
    | ([$fm.open[]] | add) as $open
    | ($fm.verdict == "pass" and $open == 0 and $fm.clean_round
       and $fm.rounds >= 2 and $fm.rounds <= 3) as $passing
    | "record=present", "verdict=" + $fm.verdict, "rounds=" + ($fm.rounds | tostring),
      "open=" + ($open | tostring),
      (if $passing then "stop=passed"
       elif $fm.rounds >= 3 then "stop=cap-reached"
       elif $open > 0 then "stop=open-findings"
       else "next=" + ($fm.rounds + 1 | tostring) end)
    end;
'
}

# read_doc_filter <commit> <path> <filter>: streams the line <path>, the bytes of the document at
# <path> and its hivemind_doc_read status into one jq program running rc_doc_eval(<filter>), and
# prints its output: `missing` for a missing document, else the filter's lines. Returns 2 on a
# failure.
read_doc_filter() {
  local commit="$1" path="$2" read_rc=0 output="" program
  program="$(hivemind_readiness_jq_defs)$(design_review_jq_defs)rc_doc_eval($3)"
  if ! output="$(
    {
      printf '%s\n' "$path"
      hivemind_doc_read "$commit" "$path" 2>/dev/null || read_rc=$?
      printf '\n%s' "$read_rc"
    } | jq -Rsr "$program" 2>/dev/null
  )"; then
    return 2
  fi
  if [ "$output" = failed ]; then
    return 2
  fi
  printf '%s\n' "$output"
}

# run_verify <arg>...: the verify subcommand.
run_verify() {
  local head="" base="" have_head=0 have_base=0 verify_rc=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --head) require_flag_value "$have_head" "$#"; head="$2"; have_head=1; shift 2 ;;
      --base) require_flag_value "$have_base" "$#"; base="$2"; have_base=1; shift 2 ;;
      *) design_review_fail usage ;;
    esac
  done
  if [ "$have_head" -eq 0 ] || [ "$have_base" -eq 0 ]; then
    design_review_fail usage
  fi
  require_jq
  hivemind_record_verify "$head" "$base" || verify_rc=$?
  exit "$verify_rc"
}

# run_stamps <arg>...: the stamps subcommand.
run_stamps() {
  local commit="" have_commit=0 path="" oid="" entry_rc=0 lines=""
  local -a paths=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --commit) require_flag_value "$have_commit" "$#"; commit="$2"; have_commit=1; shift 2 ;;
      --*) design_review_fail usage ;;
      *) paths+=("$1"); shift ;;
    esac
  done
  if [ "$have_commit" -eq 0 ] || [ "${#paths[@]}" -eq 0 ]; then
    design_review_fail usage
  fi
  require_jq
  for path in "${paths[@]}"; do
    hivemind_readiness_path_kind "$path" >/dev/null 2>&1 || design_review_fail usage
  done
  require_commit "$commit"
  require_resolved_commit "$commit"
  for path in "${paths[@]}"; do
    entry_rc=0
    oid="$(hivemind_doc_entry "$commit" "$path" 2>/dev/null)" || entry_rc=$?
    case "$entry_rc" in
      0) lines+="$path $oid"$'\n' ;;
      1) lines+="$path missing"$'\n' ;;
      *) design_review_fail git-failed ;;
    esac
  done
  printf '%s' "$lines"
}

# run_round <arg>...: the round subcommand.
run_round() {
  local commit="" slug="" have_commit=0 have_slug=0 ui="" record=""
  local slug_chars='abcdefghijklmnopqrstuvwxyz0123456789'
  local slug_pattern="^[${slug_chars}]+(-[${slug_chars}]+)*\$"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --commit) require_flag_value "$have_commit" "$#"; commit="$2"; have_commit=1; shift 2 ;;
      --slug) require_flag_value "$have_slug" "$#"; slug="$2"; have_slug=1; shift 2 ;;
      *) design_review_fail usage ;;
    esac
  done
  if [ "$have_commit" -eq 0 ] || [ "$have_slug" -eq 0 ] || ! [[ "$slug" =~ $slug_pattern ]]; then
    design_review_fail usage
  fi
  require_jq
  require_commit "$commit"
  require_resolved_commit "$commit"
  ui="$(read_doc_filter "$commit" "docs/prds/$slug.md" dr_ui)" || design_review_fail git-failed
  record="$(read_doc_filter "$commit" "docs/initiatives/$slug/review-record.md" dr_round)" \
    || design_review_fail git-failed
  if [ "$record" = missing ]; then
    record=$'record=missing\nnext=1'
  fi
  printf 'ui=%s\n%s\n' "$ui" "$record"
}

# git_design_diff <top> <from> <to> <diff-option>...: runs one git diff from <from> to <to> over
# the design document trees, from the working tree top level <top> so the pathspecs are
# repository-rooted, and prints its output; returns git's status.
git_design_diff() {
  git -C "$1" --no-replace-objects --literal-pathspecs -c diff.relative=false \
    -c core.quotePath=true diff --no-renames --no-ext-diff --no-textconv --no-color "${@:4}" \
    "$2" "$3" -- docs/prds/ docs/initiatives/ docs/adr/ </dev/null 2>/dev/null
}

# name_status_lines: reads NUL-terminated `<status>` and `<path>` record pairs, then one trailer
# record holding git's exit status, from stdin; prints `ok` then one `<status> <path>` line per
# pair, each control character of a path shown as `?`, or prints `failed` when git failed, the
# trailer is missing, a pair is incomplete or a status is not A, M, D or T.
name_status_lines() {
  local record="" lines="" index=0 count=0
  local -a records=()
  while IFS= read -r -d '' record; do
    records+=("$record")
  done
  count="${#records[@]}"
  if [ "$count" -eq 0 ] || [ "${records[count - 1]}" != 0 ] || [ $(((count - 1) % 2)) -ne 0 ]; then
    printf 'failed\n'
    return 0
  fi
  for ((index = 0; index < count - 1; index += 2)); do
    case "${records[index]}" in
      A | M | D | T) lines+="${records[index]} ${records[index + 1]//[[:cntrl:]]/?}"$'\n' ;;
      *) printf 'failed\n'; return 0 ;;
    esac
  done
  printf 'ok\n%s' "$lines"
}

# run_diff <arg>...: the diff subcommand.
run_diff() {
  local from="" to="" have_from=0 have_to=0 names=0 git_rc=0 top="" output=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --from) require_flag_value "$have_from" "$#"; from="$2"; have_from=1; shift 2 ;;
      --to) require_flag_value "$have_to" "$#"; to="$2"; have_to=1; shift 2 ;;
      --names) [ "$names" -eq 0 ] || design_review_fail usage; names=1; shift ;;
      *) design_review_fail usage ;;
    esac
  done
  if [ "$have_from" -eq 0 ] || [ "$have_to" -eq 0 ]; then
    design_review_fail usage
  fi
  require_commit "$from"
  require_commit "$to"
  require_resolved_commit "$from"
  require_resolved_commit "$to"
  top="$(git --no-replace-objects rev-parse --show-toplevel </dev/null 2>/dev/null)" \
    || design_review_fail git-failed
  [ -n "$top" ] || design_review_fail git-failed
  if [ "$names" -eq 0 ]; then
    output="$(git_design_diff "$top" "$from" "$to" && printf '.')" || design_review_fail git-failed
    printf '%s' "${output%.}"
    return 0
  fi
  output="$(
    {
      git_design_diff "$top" "$from" "$to" --name-status -z || git_rc=$?
      printf '%s\0' "$git_rc"
    } | name_status_lines
  )" || design_review_fail git-failed
  if [ "${output%%$'\n'*}" != ok ]; then
    design_review_fail git-failed
  fi
  if [ "$output" = ok ]; then
    return 0
  fi
  output="$(printf '%s\n' "${output#ok$'\n'}" | LC_ALL=C sort -t ' ' -k2 && printf '.')" \
    || design_review_fail git-failed
  printf '%s' "${output%.}"
}

# run_head <arg>...: the head subcommand.
run_head() {
  local commit="" have_commit=0 status="" current=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --commit) require_flag_value "$have_commit" "$#"; commit="$2"; have_commit=1; shift 2 ;;
      *) design_review_fail usage ;;
    esac
  done
  if [ "$have_commit" -eq 0 ]; then
    design_review_fail usage
  fi
  require_commit "$commit"
  status="$(git --no-optional-locks --no-replace-objects status --porcelain --untracked-files=all \
    </dev/null 2>/dev/null)" || design_review_fail git-failed
  if [ -n "$status" ]; then
    printf 'head=dirty\n'
    exit 1
  fi
  current="$(git --no-replace-objects rev-parse --verify --quiet HEAD </dev/null 2>/dev/null)" \
    || current=""
  if [ "$current" != "$commit" ]; then
    printf 'head=moved\n'
    exit 1
  fi
  printf 'head=ok\n'
}

# run_model <arg>...: the model subcommand.
run_model() {
  local value="${HIVEMIND_DESIGN_REVIEW_MODEL-}"
  local first_chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
  local model_pattern="^[${first_chars}][]${first_chars}._:[-]{0,63}\$"
  if [ "$#" -ne 0 ]; then
    design_review_fail usage
  fi
  if [ -z "$value" ]; then
    printf 'model=default\n'
  elif [[ "$value" =~ $model_pattern ]]; then
    printf 'model=%s\n' "$value"
  else
    printf 'model=default\nsetting=invalid\n'
  fi
}

if [ "$#" -eq 0 ]; then
  design_review_fail usage
fi
subcommand="$1"
shift
case "$subcommand" in
  verify) run_verify "$@" ;;
  stamps) run_stamps "$@" ;;
  round) run_round "$@" ;;
  diff) run_diff "$@" ;;
  head) run_head "$@" ;;
  model) run_model "$@" ;;
  *) design_review_fail usage ;;
esac
