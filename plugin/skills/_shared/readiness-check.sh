# shellcheck shell=bash
#
# readiness-check.sh — shared readiness check library (ADR-0046 decision 3): the one
# implementation of the Document existence test, the seed issue marker parse and the review
# record front matter parse, plus the closed set of readiness reason codes. Its callers are
# triage's readiness subcommand, the guide's handoff script, Lair admission, the slicing script
# and verify's record check; each sources it from its own script entry.
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute path
# derived from its OWN script_dir (`. "$plugin_root/skills/_shared/readiness-check.sh"`).
# It defines functions only; it runs no top-level statements, sources no other file and changes
# no caller state beyond defining the functions below. Sourcing it twice is harmless.
# `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately
# OMITS the P18 shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced
# file mutates the SOURCING shell's option state, so installing those here would corrupt
# every caller's shell; the floor is therefore the documented exception, not the full
# `set -euo pipefail`. This file carries no top-level `set` at all (pure function
# definitions); each caller owns its own `set -u` and error routing. Allowlisted under
# CHECK13 as a P18 documented exception.
#
# SINGLE RESPONSIBILITY: decide structure, existence and versions of initiative documents and
# issue text, never their quality. It writes nothing: no file, no scratch path. Input reaches jq
# only on stdin, never in argv or program text. Every git call is
# `git --no-replace-objects --literal-pathspecs ...` and resolves no ref and makes no network
# call; a commit argument must be a full lowercase object id before any git call. The functions
# behave the same under a caller's `set -euo pipefail` or `set -u` alone.
#
# FAILURE CONTRACT: a failure prints exactly one stderr line `readiness-check-error: <token>`
# and returns non-zero; the library never exits and never echoes its input. Tokens: usage,
# commit-malformed, commit-unresolvable, snapshot-malformed, truncated, gh-failed, git-failed.
# A checking call prints its result to stdout only when it returns 0.
#
# PUBLIC API:
#   hivemind_readiness_commit_ok <commit>
#       0 when <commit> is 40 or 64 lowercase hex, else 1. No git call.
#   hivemind_readiness_codes
#       Prints the closed reason-code set, one base code per line, in the order of the solution
#       design's Readiness check output contract. A parameterized code ends with `:`.
#   hivemind_readiness_path_kind <path>
#       Path allowlist: prints the kind (prd, solution-design, review-record, prototype-index,
#       prototype-notes, adr) and returns 0 when <path> matches one allowlisted shape, else 1.
#       The stamp allowlist is all six kinds.
#   hivemind_doc_entry <commit> <path>
#       Document existence test: prints the blob id and returns 0 only when the commit's tree
#       holds exactly one entry at exactly <path>, of type blob and mode 100644 or 100755.
#       Returns 1 when missing (a malformed path is missing, with no git call). Returns 2 on
#       commit-malformed (no git call), commit-unresolvable or git-failed.
#   hivemind_doc_read <commit> <path>
#       Streams the document's bytes, read only by the blob id the existence test printed.
#       Returns 1 when missing, 2 on failure; a caller discards stdout on any non-zero return.
#   hivemind_seed_marker_slug  (issue body on stdin)
#       Prints the slug and returns 0 when the body's first line, one ending CR removed, is
#       exactly `<!-- hivemind-initiative: <slug> -->`; else returns 1 with no output.
#   hivemind_record_front_matter  (review record on stdin)
#       Parses the fixed front matter shape and prints one compact JSON object
#       {"stamps":[{"path","blob"}...],"verdict","open":{"critical","high","medium","low"},
#       "rounds","clean_round"} and returns 0; any other shape returns 1 with no output. The
#       zero-stamp form is the line `stamps: []`; a bare `stamps:` needs at least one stamp.

# _hivemind_rc_error <token>: prints the one failure line to stderr.
_hivemind_rc_error() {
  printf 'readiness-check-error: %s\n' "$1" >&2
}

# _hivemind_rc_jq_defs: prints the constant jq definitions shared by the jq programs below.
_hivemind_rc_jq_defs() {
  printf '%s\n' '
def rc_slug: "[a-z0-9]+(-[a-z0-9]+)*";
def rc_path_kind:
  if test("\\Adocs/prds/" + rc_slug + "\\.md\\z") then "prd"
  elif test("\\Adocs/initiatives/" + rc_slug + "/solution-design\\.md\\z") then "solution-design"
  elif test("\\Adocs/initiatives/" + rc_slug + "/review-record\\.md\\z") then "review-record"
  elif test("\\Adocs/initiatives/" + rc_slug + "/prototype/index\\.html\\z") then "prototype-index"
  elif test("\\Adocs/initiatives/" + rc_slug + "/prototype/notes\\.md\\z") then "prototype-notes"
  elif test("\\Adocs/adr/[0-9]{4}-" + rc_slug + "\\.md\\z") then "adr"
  else null end;
def rc_count($line; $key):
  $line | capture("\\A" + $key + ": (?<v>0|[1-9][0-9]*)\\z") | .v | tonumber;
'
}

# hivemind_readiness_commit_ok <commit>: 0 for 40 or 64 lowercase hex, else 1. No git call.
hivemind_readiness_commit_ok() {
  if [ "$#" -ne 1 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local commit="${1-}"
  if [[ "$commit" =~ ^[0123456789abcdef]{40}$ ]] || [[ "$commit" =~ ^[0123456789abcdef]{64}$ ]]; then
    return 0
  fi
  return 1
}

# hivemind_readiness_codes: prints the closed reason-code set, one base code per line.
hivemind_readiness_codes() {
  if [ "$#" -ne 0 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  printf '%s\n' \
    issue_closed 'rating_missing:' is_epic is_idea has_subissues no_acceptance_criteria \
    spec_problem_missing spec_evidence_missing spec_scope_missing open_questions_not_none \
    promote_type promote_effort \
    epic_closed parent_not_epic epic_marker_missing design_block_missing design_link_invalid \
    design_slug_mismatch prd_missing prd_ui_invalid design_missing design_delivered \
    prototype_missing record_missing 'template_section_missing:' template_order \
    heading_duplicate 'design_section_unfilled:' design_open_questions 'adr_missing:' \
    'adr_not_accepted:' record_malformed record_not_passed record_open record_rounds_exceeded \
    'record_stale:' 'record_unstamped:' 'heading_unmatched:' 'heading_ambiguous:' \
    'dependency_edge_missing:'
}

# hivemind_readiness_path_kind <path>: prints the allowlisted kind of <path> (0), else 1.
hivemind_readiness_path_kind() {
  if [ "$#" -ne 1 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local path="${1-}" kind="" program
  program="$(_hivemind_rc_jq_defs)"'
rc_path_kind // empty'
  if ! kind="$(printf '%s' "$path" | jq -Rsr "$program" 2>/dev/null)"; then
    return 1
  fi
  if [ -z "$kind" ]; then
    return 1
  fi
  printf '%s\n' "$kind"
}

# _hivemind_rc_path_shape_ok <path>: 0 when <path> is relative, holds no empty, `.` or `..`
# segment and no control character; else 1.
_hivemind_rc_path_shape_ok() {
  local path="$1"
  if [ -z "$path" ]; then
    return 1
  fi
  case "$path" in
    /* | */ | *//*) return 1 ;;
    . | .. | ./* | ../* | */. | */.. | */./* | */../*) return 1 ;;
    *[$'\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037\177']*) return 1 ;;
  esac
  return 0
}

# _hivemind_rc_ls_tree_verdict <path> <commit-length>: reads `git ls-tree -z` records then one
# trailer record holding git's exit status from stdin, and prints one verdict line:
# `ok <oid>`, `missing`, `unresolvable` or `failed`.
_hivemind_rc_ls_tree_verdict() {
  local want_path="$1" commit_len="$2" record="" previous="" have_previous=0 count=0
  local meta="" entry_path="" mode="" type="" oid="" found_oid="" mismatch=0
  while IFS= read -r -d '' record; do
    if [ "$have_previous" -eq 1 ]; then
      count=$((count + 1))
      meta="${previous%%$'\t'*}"
      entry_path="${previous#*$'\t'}"
      mode="${meta%% *}"
      type="${meta#* }"
      oid="${type#* }"
      type="${type%% *}"
      if [ "${#oid}" -ne "$commit_len" ]; then
        mismatch=1
      fi
      if [ "$entry_path" == "$want_path" ] && [ "$type" = blob ] \
        && { [ "$mode" = 100644 ] || [ "$mode" = 100755 ]; }; then
        found_oid="$oid"
      fi
    fi
    previous="$record"
    have_previous=1
  done
  if [ "$have_previous" -eq 0 ] || [ "$previous" != 0 ]; then
    printf 'failed\n'
  elif [ "$mismatch" -eq 1 ]; then
    printf 'unresolvable\n'
  elif [ "$count" -eq 1 ] && [ -n "$found_oid" ] && hivemind_readiness_commit_ok "$found_oid"; then
    printf 'ok %s\n' "$found_oid"
  else
    printf 'missing\n'
  fi
}

# hivemind_doc_entry <commit> <path>: the Document existence test (see PUBLIC API).
hivemind_doc_entry() {
  if [ "$#" -ne 2 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local commit="${1-}" path="${2-}" verdict="" git_rc=0
  if ! hivemind_readiness_commit_ok "$commit"; then
    _hivemind_rc_error commit-malformed
    return 2
  fi
  if ! _hivemind_rc_path_shape_ok "$path"; then
    return 1
  fi
  verdict="$(
    {
      git --no-replace-objects --literal-pathspecs ls-tree --full-tree -z "$commit" -- "$path" \
        2>/dev/null || git_rc=$?
      printf '%s\0' "$git_rc"
    } | _hivemind_rc_ls_tree_verdict "$path" "${#commit}"
  )" || verdict=failed
  case "$verdict" in
    'ok '*)
      printf '%s\n' "${verdict#ok }"
      return 0
      ;;
    missing)
      return 1
      ;;
    unresolvable)
      _hivemind_rc_error commit-unresolvable
      return 2
      ;;
  esac
  _hivemind_rc_error git-failed
  return 2
}

# hivemind_doc_read <commit> <path>: streams the document's bytes by its blob id (see PUBLIC API).
hivemind_doc_read() {
  if [ "$#" -ne 2 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local oid="" entry_rc=0
  oid="$(hivemind_doc_entry "$1" "$2")" || entry_rc=$?
  if [ "$entry_rc" -ne 0 ]; then
    return "$entry_rc"
  fi
  if git --no-replace-objects --literal-pathspecs cat-file blob "$oid" 2>/dev/null; then
    return 0
  fi
  _hivemind_rc_error git-failed
  return 2
}

# hivemind_seed_marker_slug: issue body on stdin; prints the seed marker slug (see PUBLIC API).
hivemind_seed_marker_slug() {
  if [ "$#" -ne 0 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local slug="" program
  program="$(_hivemind_rc_jq_defs)"'
[inputs] | select(length > 0) | .[0] | sub("\r\\z"; "")
| capture("\\A<!-- hivemind-initiative: (?<slug>" + rc_slug + ") -->\\z") | .slug'
  if ! slug="$(jq -nRr "$program" 2>/dev/null)"; then
    return 1
  fi
  if [ -z "$slug" ]; then
    return 1
  fi
  printf '%s\n' "$slug"
}

# hivemind_record_front_matter: review record on stdin; prints its front matter as compact JSON
# (see PUBLIC API).
hivemind_record_front_matter() {
  if [ "$#" -ne 0 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local parsed="" program
  program="$(_hivemind_rc_jq_defs)"'
[inputs | sub("\r\\z"; "")] as $lines
| [range(1; $lines | length) | select($lines[.] == "---")] as $closers
| select(($lines | length) > 0 and $lines[0] == "---" and ($closers | length) > 0)
| $lines[1:$closers[0]] as $fm
| ($fm | length) as $fm_len
| select($fm_len >= 9)
| $fm[1:$fm_len - 8] as $pairs
| $fm[$fm_len - 8:] as $tail
| select(($fm[0] == "stamps:" and ($pairs | length) > 0)
    or ($fm[0] == "stamps: []" and ($pairs | length) == 0))
| select(($pairs | length) % 2 == 0)
| [range(0; $pairs | length; 2) as $i
    | {path: ($pairs[$i] | capture("\\A  - path: (?<v>.*)\\z") | .v),
       blob: ($pairs[$i + 1] | capture("\\A    blob: (?<v>[0-9a-f]{40}|[0-9a-f]{64})\\z") | .v)}]
  as $stamps
| select(($stamps | length) * 2 == ($pairs | length))
| select(all($stamps[]; .path | rc_path_kind != null))
| select(($stamps | map(.path) | unique | length) == ($stamps | length))
| select($tail[1] == "open:")
| {stamps: $stamps,
   verdict: ($tail[0] | capture("\\Averdict: (?<v>pass|fail)\\z") | .v),
   open: {critical: rc_count($tail[2]; "  critical"),
          high: rc_count($tail[3]; "  high"),
          medium: rc_count($tail[4]; "  medium"),
          low: rc_count($tail[5]; "  low")},
   rounds: rc_count($tail[6]; "rounds"),
   clean_round: ($tail[7] | capture("\\Aclean_round: (?<v>true|false)\\z") | .v == "true")}'
  if ! parsed="$(jq -nRc "$program" 2>/dev/null)"; then
    return 1
  fi
  if [ -z "$parsed" ]; then
    return 1
  fi
  printf '%s\n' "$parsed"
}
