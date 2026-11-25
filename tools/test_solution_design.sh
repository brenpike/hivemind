#!/usr/bin/env bash
#
# Offline suite for the hivemind:solution-design skill:
#   plugin/skills/solution-design/SKILL.md
#
# OFFLINE bash/jq TEST — needs only bash and jq (NO gh / network / auth / CI / Codex / Fable /
# claude-mem). It sources the readiness check library, plugin/skills/_shared/readiness-check.sh,
# read-only, and runs the library's own jq definitions (hivemind_readiness_jq_defs) over the
# recorded fixture run, tests/solution-design/lair-fixture-run.md: rc_design_codes reads the
# framed document (a prefix line, the document's bytes, then the status line) exactly as the
# library frames it. It also checks that the `## ` sections of the fenced template in SKILL.md
# equal the library's rc_template_sections, in order.
#
# Every check also runs on a mutated scratch copy built to break it, proving the check fails.
# tests/solution-design/README.md lists the cases. Mirrors tools/test_stage_derivation.sh's
# pass/fail counter, exit 1 on any failure, exit 2 on set-up failure and scratch dir removed on
# EXIT. Read-only: the only writes are in the scratch dir.
#
# Usage:
#   ./tools/test_solution_design.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
RC_LIB="$REPO_ROOT/plugin/skills/_shared/readiness-check.sh"
SKILL="$REPO_ROOT/plugin/skills/solution-design/SKILL.md"
FIXTURE="$REPO_ROOT/tests/solution-design/lair-fixture-run.md"

for required_file in "$RC_LIB" "$SKILL" "$FIXTURE"; do
  [ -f "$required_file" ] || { echo "FAIL: file under test missing: $required_file" >&2; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this suite" >&2; exit 2; }

# shellcheck source=../plugin/skills/_shared/readiness-check.sh
. "$RC_LIB" || { echo "FAIL: cannot source $RC_LIB" >&2; exit 2; }
JQ_DEFS="$(hivemind_readiness_jq_defs)" || { echo "FAIL: hivemind_readiness_jq_defs failed" >&2; exit 2; }

make_scratch_dir TMPDIR_TEST
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
setup_fail() { echo "FAIL: set-up: $1" >&2; exit 2; }

# The headings prefix asks rc_design_codes to apply design_section_unfilled to every template
# section except Open questions (which reads None) and Amendments (empty until one is made).
HEADINGS_PREFIX="$(jq -cn "$JQ_DEFS"'
  {documents: {headings: [rc_template_sections | to_entries[]
    | select(.value[1] != "Open questions" and .value[1] != "Amendments")
    | {index: .key, text: .value[1]}]}}')" || setup_fail "cannot build the headings prefix"

DECISION_FAULTS_JQ='
  rc_lines | rc_parse | rc_section(2; "Decisions") as $decisions
  | if $decisions == null then "no Decisions section"
    else [$decisions[] | select(.level == 3 and (.title | test("\\AD[0-9]+: "))) | .title] as $titles
    | if ($titles | length) == 0 then "no ### D<n>: decision"
      else $titles[] as $title
      | [$decisions | rc_section(3; $title) | .[] | select(.fenced | not) | .text]
      | select(any(.[]; test("ADR-[0-9]{4}") or test("No ADR: fails [^ \t]")) | not)
      | "no ADR line: " + $title end end'

TEMPLATE_JQ='
  rc_lines as $lines
  | ([range(0; $lines | length) | select($lines[.] == "## Solution design template")] | .[0])
    as $section
  | (if $section == null then null
     else [range($section; $lines | length) | select($lines[.] | test("\\A```markdown[ \t]*\\z"))]
       | .[0] end) as $open
  | (if $open == null then null
     else [range($open + 1; $lines | length) | select($lines[.] == "```")] | .[0] end) as $close
  | if $close == null then "no fenced template"
    else [$lines[$open + 1:$close][] | capture("\\A## (?<t>.*)\\z").t] as $found
    | [rc_template_sections[] | .[1]] as $expected
    | if $found == $expected then empty
      else "template sections " + ($found | tojson) + " differ from " + ($expected | tojson) end
    end'

# design_codes <design-file> <codes-file>: writes rc_design_codes of the framed document.
design_codes() {
  local design="$1" codes="$2"
  [ -r "$design" ] || return 2
  {
    printf '%s\n' "$HEADINGS_PREFIX"
    cat "$design"
    printf '\n%s' 0
  } | jq -Rsr "$JQ_DEFS"'rc_doc_eval(rc_design_codes)' >"$codes"
}

# open_reads_none <design-file>: 0 when ## Open questions reads exactly None by rc_reads_none.
open_reads_none() {
  [ "$(jq -Rsr "$JQ_DEFS"'rc_lines | rc_parse | rc_section(2; "Open questions") | rc_reads_none' \
    <"$1")" = true ]
}

# decision_faults <design-file>: prints one line per decision fault; none when every decision holds.
decision_faults() {
  jq -Rsr "$JQ_DEFS$DECISION_FAULTS_JQ" <"$1"
}

# design_check <check> <design-file> <codes-file>: 0 when the design passes <check>, else 1.
design_check() {
  local check="$1" design="$2" codes="$3" faults=""
  case "$check" in
    section-present) ! grep -q '^template_section_missing:' "$codes" ;;
    section-order) ! grep -qx template_order "$codes" ;;
    heading-unique) ! grep -qx heading_duplicate "$codes" ;;
    open-questions-code) ! grep -qx design_open_questions "$codes" ;;
    open-questions-none) open_reads_none "$design" ;;
    not-delivered) ! grep -qx design_delivered "$codes" ;;
    section-filled) ! grep -qE '^(design_section_unfilled|heading_unmatched|heading_ambiguous):' "$codes" ;;
    decision-adr)
      faults="$(decision_faults "$design")" || return 1
      [ -z "$faults" ]
      ;;
    *) setup_fail "unknown check $check" ;;
  esac
}

ALL_CHECKS=(section-present section-order heading-unique open-questions-code open-questions-none
  not-delivered section-filled decision-adr)

test_fixture() {
  local codes="$TMPDIR_TEST/fixture.codes" check
  design_codes "$FIXTURE" "$codes" || setup_fail "rc_design_codes failed on the fixture"
  for check in "${ALL_CHECKS[@]}"; do
    if design_check "$check" "$FIXTURE" "$codes"; then
      pass "fixture:$check" "lair-fixture-run.md passes"
    else
      failed "fixture:$check" "lair-fixture-run.md fails: $(tr '\n' ' ' <"$codes")$(decision_faults "$FIXTURE")"
    fi
  done
  if [ -s "$codes" ]; then
    failed "fixture:no-codes" "rc_design_codes printed: $(tr '\n' ' ' <"$codes")"
  else
    pass "fixture:no-codes" "rc_design_codes prints no code"
  fi
}

# mutate <name> <awk-program>: writes the fixture through <awk-program> to the scratch copy
# $TMPDIR_TEST/<name>.md; a set-up failure when the copy equals the fixture.
mutate() {
  local name="$1" program="$2" copy="$TMPDIR_TEST/$1.md"
  awk "$program" "$FIXTURE" >"$copy" || setup_fail "mutation $name"
  cmp -s "$FIXTURE" "$copy" && setup_fail "mutation $name changed nothing"
}

# expect_fault <name> <check>...: each named check fails on the mutated copy <name>.md.
expect_fault() {
  local name="$1" copy="$TMPDIR_TEST/$1.md" codes="$TMPDIR_TEST/$1.codes" check
  shift
  design_codes "$copy" "$codes" || setup_fail "rc_design_codes failed on mutation $name"
  for check in "$@"; do
    if design_check "$check" "$copy" "$codes"; then
      failed "mutation:$name:$check" "the check passed a copy built to break it"
    else
      pass "mutation:$name:$check" "the check fails"
    fi
  done
}

test_mutations() {
  mutate section-dropped '
    $0 == "## Seam order" { skip = 1; next }
    skip && /^## / { skip = 0 }
    !skip'
  expect_fault section-dropped section-present
  mutate sections-swapped '
    $0 == "## Components" { print "## Lifecycle"; next }
    $0 == "## Lifecycle" { print "## Components"; next }
    { print }'
  expect_fault sections-swapped section-order
  mutate heading-duplicate '
    /^### D1: / { first = $0 }
    /^### D2: / { print first; next }
    { print }'
  expect_fault heading-duplicate heading-unique
  mutate open-question '
    $0 == "## Open questions" { open = 1 }
    open && $0 == "None" { print "- Which tick runs first?"; open = 0; next }
    { print }'
  expect_fault open-question open-questions-code open-questions-none
  mutate delivered '
    { print }
    NR == 1 { print ""; print "**Status:** delivered" }'
  expect_fault delivered not-delivered
  mutate section-unfilled '
    $0 == "## Verification strategy" { print; print ""; skip = 1; next }
    skip && /^#/ { skip = 0 }
    !skip'
  expect_fault section-unfilled section-filled
  mutate decision-no-adr '
    /^### D10: / { d10 = 1; print; next }
    d10 && /^#/ { d10 = 0 }
    d10 { sub(/ ?No ADR: fails [^.]*\./, "") }
    { print }'
  expect_fault decision-no-adr decision-adr
}

test_template() {
  local mismatch copy="$TMPDIR_TEST/skill-swapped.md"
  mismatch="$(jq -Rsr "$JQ_DEFS$TEMPLATE_JQ" <"$SKILL")" || setup_fail "template read failed"
  if [ -z "$mismatch" ]; then
    pass "template:sections" "SKILL.md template sections equal rc_template_sections, in order"
  else
    failed "template:sections" "$mismatch"
  fi
  awk '$0 == "## Components" { print "## Lifecycle"; next }
    $0 == "## Lifecycle" { print "## Components"; next }
    { print }' "$SKILL" >"$copy" || setup_fail "template mutation"
  cmp -s "$SKILL" "$copy" && setup_fail "template mutation changed nothing"
  mismatch="$(jq -Rsr "$JQ_DEFS$TEMPLATE_JQ" <"$copy")" || setup_fail "template read failed"
  if [ -n "$mismatch" ]; then
    pass "mutation:template-swapped:sections" "the check fails"
  else
    failed "mutation:template-swapped:sections" "the check passed a template built to break it"
  fi
}

test_fixture
test_mutations
test_template

# ── Summary ───────────────────────────────────────────────────────────────────────
echo
echo "solution-design: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
