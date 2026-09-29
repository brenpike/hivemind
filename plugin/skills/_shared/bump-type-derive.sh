# shellcheck shell=bash
#
# bump-type-derive.sh — single-source PURE Bump Type Determination arithmetic (hivemind:bump-type).
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: the thin entrypoint
# (`skills/bump-type/scripts/bump-type.sh`) sources it by a path derived from its OWN script_dir.
# It defines functions only; it runs no top-level statements beyond `set -u` and changes no caller
# state beyond defining the functions below. `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file carries `set -u`
# ONLY and deliberately OMITS the rest of the P18 shell-safety floor — `set -e`, `set -o pipefail`,
# and any EXIT trap. A sourced file mutates the SOURCING shell's option state, so installing those
# here would corrupt every caller's shell; the floor is therefore the documented exception, not the
# full `set -euo pipefail`. `set -u` alone is safe to inherit. Allowlisted under CHECK13 as a P18
# documented exception.
#
# SINGLE RESPONSIBILITY: be the SINGLE SOURCE of the Bump Type Determination arithmetic — the
# revert pre-pass predicates, the per-commit row mapping, the dominant-row precedence, and the
# verdict projection. versioning.md `## Bump Type Determination` keeps the row table and the
# caller's two judgments and delegates this arithmetic to the engine without restating it.
# EVERYTHING here is PURE string/arithmetic mapping: inputs in, words out on stdout, status via
# return code. There is NO git/file I/O and no `exit`; the IMPURE git reads, argument gating, and
# record framing live in the entrypoint.
#
# UNTRUSTED-DATA POSTURE: commit subjects/bodies are attacker-influenceable DATA. Every match below
# is a bash `[[ $text =~ $re ]]` whose pattern lives in an UNQUOTED shell variable (bash 3.2 treats
# a quoted right operand as a literal string) and whose commit text is ONLY the left operand.
# Commit text is never eval'd, never spliced into shell/jq/awk program source, never used as a
# printf format, and never echoed back: every function emits only fixed vocabulary words or a
# value that already passed a strict hex regex (the reverted-original SHA).
#
# PORTABILITY: bash 3.2 compatible (macOS /bin/bash): no associative arrays, no mapfile, no
# namerefs, no ${var,,}; POSIX `[[:space:]]` in place of `\s`.
#
# ROW VOCABULARY: MAJOR | MINOR | PATCH | NO_BUMP for a mapped commit, UNMAPPED otherwise.
# DOMINANT VOCABULARY: MAJOR | MINOR | PATCH | NO_BUMP | NONE (matches no row) | MULTI (matches
# more than one row).
#
# RESIDUALS (deliberate engine behaviour, preserved from the former governance prose; documented,
# not fixed here):
#   A1  Row step 1 is a literal CONTAINS test for `!:` anywhere in the subject — not anchored to the
#       type token. A subject such as `docs: note that foo!: bar` or `Revert "feat!: x"` maps to
#       MAJOR (over-bump). Over-bump is the fail-safe direction (it escalates, never hides a break).
#   A2  A reverted-original SHA prefix matching MORE THAN ONE in-range commit is ambiguous and is
#       treated as unmatched: nothing is dropped and the revert maps by row step 3.
#   A3  Revert drops are a UNION over a single pass: a commit is dropped at most once even when
#       several reverts target it, and a revert-of-a-revert drops all three commits (the chain is
#       not re-applied).
#   A4  Type tokens are case-exact: `Feat:` / `FIX:` are unmapped.
#   A6  Merge commits are read like any other commit; `Merge branch ...` is typically unmapped.
#   A8  A subject with no `(` and no `:` has no leading token and is unmapped.
#   A marker body line is matched per line with `$` at end-of-line, so a CR-terminated line
#   (`...abc1234.\r`) does not match and the revert is kept (literal, no normalization).

set -u

# ── hivemind_bump_is_revert ───────────────────────────────────────────────────────
# hivemind_bump_is_revert <subject>
#   -> return 0 iff <subject> matches `^Revert "(.+)"$` (git default) or
#      `^revert(\([^)]*\))?:[[:space:]]*(.+)$` (Conventional Commits); 1 otherwise. Emits nothing.
hivemind_bump_is_revert() {
  local subject="$1"
  local re_git_revert='^Revert "(.+)"$'
  local re_cc_revert='^revert(\([^)]*\))?:[[:space:]]*(.+)$'
  if [[ $subject =~ $re_git_revert ]]; then
    return 0
  fi
  if [[ $subject =~ $re_cc_revert ]]; then
    return 0
  fi
  return 1
}

# ── hivemind_bump_extract_revert_target ───────────────────────────────────────────
# hivemind_bump_extract_revert_target <body>
#   -> prints the reverted-original SHA captured from the FIRST body line matching
#      `^This reverts commit ([0-9a-f]{7,40})\.?$` and returns 0; prints nothing and returns 1 when
#      no line matches. The printed value is hex-only by construction of the capture group.
hivemind_bump_extract_revert_target() {
  local remaining_text="$1"
  local newline=$'\n'
  local re_marker='^This reverts commit ([0-9a-f]{7,40})\.?$'
  local body_line
  while :; do
    body_line="${remaining_text%%"$newline"*}"
    if [[ $body_line =~ $re_marker ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
    case "$remaining_text" in
      *"$newline"*) remaining_text="${remaining_text#*"$newline"}" ;;
      *) return 1 ;;
    esac
  done
}

# ── hivemind_bump_resolve_revert_index ────────────────────────────────────────────
# hivemind_bump_resolve_revert_index <target_sha> <sha_0> [<sha_1> ...]
#   -> prints the 0-based position of the ONE in-range SHA that equals <target_sha> or starts with
#      it, and returns 0. Returns 1 (prints nothing) when zero in-range SHAs match OR when more
#      than one matches (A2: an ambiguous prefix is treated as unmatched).
hivemind_bump_resolve_revert_index() {
  local target_sha="$1"
  shift
  local match_count=0
  local match_index=-1
  local position=0
  local candidate_sha
  for candidate_sha in "$@"; do
    case "$candidate_sha" in
      "$target_sha"*)
        match_count=$((match_count + 1))
        match_index=$position
        ;;
    esac
    position=$((position + 1))
  done
  if [ "$match_count" -ne 1 ]; then
    return 1
  fi
  printf '%s\n' "$match_index"
  return 0
}

# ── hivemind_bump_map_row ─────────────────────────────────────────────────────────
# hivemind_bump_map_row <subject> <body>
#   -> prints the commit's row: MAJOR | MINOR | PATCH | NO_BUMP | UNMAPPED. Always returns 0.
#   1. subject contains `!:` anywhere (A1)                                  -> MAJOR
#   2. any line of subject or body starts `BREAKING CHANGE:`/`BREAKING-CHANGE:` -> MAJOR
#   3. leading token before the first `(` or `:` of the subject (A4 case-exact, A8 none -> UNMAPPED):
#        feat -> MINOR; fix | bugfix | hotfix | refactor -> PATCH;
#        chore | docs | test | ci -> NO_BUMP; anything else -> UNMAPPED.
hivemind_bump_map_row() {
  local subject="$1"
  local body="$2"
  local newline=$'\n'
  local re_bang_colon='!:'
  local re_breaking="${newline}BREAKING[ -]CHANGE:"
  local re_leading_token='^([^(:]*)[(:]'
  local framed_text="${newline}${subject}${newline}${body}"
  if [[ $subject =~ $re_bang_colon ]]; then
    printf '%s\n' 'MAJOR'
    return 0
  fi
  if [[ $framed_text =~ $re_breaking ]]; then
    printf '%s\n' 'MAJOR'
    return 0
  fi
  if ! [[ $subject =~ $re_leading_token ]]; then
    printf '%s\n' 'UNMAPPED'
    return 0
  fi
  case "${BASH_REMATCH[1]}" in
    feat) printf '%s\n' 'MINOR' ;;
    fix|bugfix|hotfix|refactor) printf '%s\n' 'PATCH' ;;
    chore|docs|test|ci) printf '%s\n' 'NO_BUMP' ;;
    *) printf '%s\n' 'UNMAPPED' ;;
  esac
  return 0
}

# ── hivemind_bump_select_dominant_row ─────────────────────────────────────────────
# hivemind_bump_select_dominant_row <bump_trigger:yes|no> <major> <minor> <patch> <no_bump>
#   -> prints `<DOMINANT> <rule>` where rule is the 1-based precedence rule that fired
#      (first match wins). Always returns 0.
#   1. no mapped commits                                   -> NONE
#   2. any MAJOR                                           -> MAJOR
#   3. bump_trigger yes AND (minor + patch) >= 1           -> MINOR if minor >= 1 else PATCH
#   4. exactly one mapped commit                           -> that commit's row
#   5. two or more non-MAJOR rows tie for the highest count -> MULTI
#   6. otherwise                                           -> the strictly-highest row
hivemind_bump_select_dominant_row() {
  local bump_trigger="$1"
  local major_count="$2"
  local minor_count="$3"
  local patch_count="$4"
  local no_bump_count="$5"
  local mapped_total=$((major_count + minor_count + patch_count + no_bump_count))
  if [ "$mapped_total" -eq 0 ]; then
    printf '%s\n' 'NONE 1'
    return 0
  fi
  if [ "$major_count" -gt 0 ]; then
    printf '%s\n' 'MAJOR 2'
    return 0
  fi
  if [ "$bump_trigger" = 'yes' ] && [ $((minor_count + patch_count)) -gt 0 ]; then
    if [ "$minor_count" -gt 0 ]; then
      printf '%s\n' 'MINOR 3'
    else
      printf '%s\n' 'PATCH 3'
    fi
    return 0
  fi
  local rule_number=6
  if [ "$mapped_total" -eq 1 ]; then
    rule_number=4
  fi
  local highest_count="$minor_count"
  local highest_row='MINOR'
  if [ "$patch_count" -gt "$highest_count" ]; then
    highest_count="$patch_count"
    highest_row='PATCH'
  fi
  if [ "$no_bump_count" -gt "$highest_count" ]; then
    highest_count="$no_bump_count"
    highest_row='NO_BUMP'
  fi
  local tied_rows=0
  [ "$minor_count" -eq "$highest_count" ] && tied_rows=$((tied_rows + 1))
  [ "$patch_count" -eq "$highest_count" ] && tied_rows=$((tied_rows + 1))
  [ "$no_bump_count" -eq "$highest_count" ] && tied_rows=$((tied_rows + 1))
  if [ "$rule_number" -eq 6 ] && [ "$tied_rows" -ge 2 ]; then
    printf '%s\n' 'MULTI 5'
    return 0
  fi
  printf '%s %s\n' "$highest_row" "$rule_number"
  return 0
}

# ── hivemind_bump_derive_verdict ──────────────────────────────────────────────────
# hivemind_bump_derive_verdict <dominant_row> <bump_trigger:yes|no> <no_bump_match:yes|no>
#   -> prints `<verdict> <bump_type>`. Always returns 0.
#   MAJOR | MINOR | PATCH -> bump_required <major|minor|patch> iff bump_trigger yes, else ask_user none.
#   NO_BUMP               -> no_bump none iff no_bump_match yes AND bump_trigger no, else ask_user none.
#   NONE | MULTI | other  -> ask_user none.
hivemind_bump_derive_verdict() {
  local dominant_row="$1"
  local bump_trigger="$2"
  local no_bump_match="$3"
  case "$dominant_row" in
    MAJOR|MINOR|PATCH)
      if [ "$bump_trigger" = 'yes' ]; then
        case "$dominant_row" in
          MAJOR) printf '%s\n' 'bump_required major' ;;
          MINOR) printf '%s\n' 'bump_required minor' ;;
          PATCH) printf '%s\n' 'bump_required patch' ;;
        esac
      else
        printf '%s\n' 'ask_user none'
      fi
      ;;
    NO_BUMP)
      if [ "$no_bump_match" = 'yes' ] && [ "$bump_trigger" = 'no' ]; then
        printf '%s\n' 'no_bump none'
      else
        printf '%s\n' 'ask_user none'
      fi
      ;;
    *) printf '%s\n' 'ask_user none' ;;
  esac
  return 0
}
