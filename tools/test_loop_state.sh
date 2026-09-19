#!/usr/bin/env bash
#
# Behavioral unit runner for the github-review-loop's deterministic loop
# bookkeeping kernel (issue #207, STEP-002).
#
# Tests plugin/skills/github-review-loop/scripts/loop-state.sh against its four
# subcommands (cycle-decision, token-map, floor, resolve-precedence) and the
# loud-reject contract. CI-runnable with bash only — no jq, no tmux, no network.
# Pure subprocess invocation of the script under test.
#
# Mirrors tools/test_exit_precedence.sh: pass/fail counters, per-case assertion
# helpers, exit-nonzero-on-any-fail. The resolve-precedence cases derive their
# expected winner from the sibling exit-precedence.sh directly (comparison
# assertion) rather than re-listing the ladder here.
#
# Usage:
#   bash tools/test_loop_state.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SCRIPT="$REPO_ROOT/plugin/skills/github-review-loop/scripts/loop-state.sh"
SIBLING="$REPO_ROOT/plugin/skills/github-review-loop/scripts/exit-precedence.sh"

[ -f "$SCRIPT" ]  || { printf 'FAIL: script under test missing: %s\n' "$SCRIPT" >&2; exit 2; }
[ -f "$SIBLING" ] || { printf 'FAIL: sibling kernel missing: %s\n' "$SIBLING" >&2; exit 2; }

PASS_COUNT=0
FAIL_COUNT=0
pass()   { printf 'PASS [%s] %s\n' "$1" "$2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { printf 'FAIL [%s] %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---------------------------------------------------------------------------
# assert_stdout <case_name> <expected_stdout> <arg> [arg ...]
# Invoke the script under test via positional args; assert full stdout and exit 0.
# ---------------------------------------------------------------------------
assert_stdout() {
  local case_name="$1" expected="$2"
  shift 2
  local actual exit_code
  actual="$(bash "$SCRIPT" "$@" 2>/dev/null)"
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    failed "$case_name" "expected exit 0, got $exit_code (args: $*)"
    return
  fi
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "got: $(printf '%s' "$actual" | tr '\n' '|')"
  else
    failed "$case_name" "expected='$(printf '%s' "$expected" | tr '\n' '|')' actual='$(printf '%s' "$actual" | tr '\n' '|')'"
  fi
}

# ---------------------------------------------------------------------------
# assert_nonzero_stderr <case_name> <arg> [arg ...]
# Invoke via positional args; assert exit nonzero AND stderr non-empty.
# ---------------------------------------------------------------------------
assert_nonzero_stderr() {
  local case_name="$1"
  shift 1
  local stderr_out exit_code
  stderr_out="$(bash "$SCRIPT" "$@" 2>&1 >/dev/null)"
  exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    failed "$case_name" "expected nonzero exit, got 0 (args: $*)"
    return
  fi
  if [ -n "$stderr_out" ]; then
    pass "$case_name" "exit=$exit_code stderr non-empty"
  else
    failed "$case_name" "exit=$exit_code but stderr was empty"
  fi
}

# ---------------------------------------------------------------------------
# assert_matches_sibling <case_name> <token> [token ...]
# Feed identical tokens to resolve-precedence (script under test) AND to the
# sibling exit-precedence.sh directly; assert identical winning stdout + exit 0.
# Expected winner is DERIVED from the sibling, never hardcoded.
# ---------------------------------------------------------------------------
assert_matches_sibling() {
  local case_name="$1"
  shift 1
  local via_loop loop_exit via_sibling sibling_exit
  via_loop="$(bash "$SCRIPT" resolve-precedence "$@" 2>/dev/null)"
  loop_exit=$?
  via_sibling="$(bash "$SIBLING" "$@" 2>/dev/null)"
  sibling_exit=$?
  if [ "$loop_exit" -ne 0 ]; then
    failed "$case_name" "resolve-precedence expected exit 0, got $loop_exit (tokens: $*)"
    return
  fi
  if [ "$sibling_exit" -ne 0 ]; then
    failed "$case_name" "sibling reference exited $sibling_exit — bad test input (tokens: $*)"
    return
  fi
  if [ "$via_loop" = "$via_sibling" ]; then
    pass "$case_name" "winner='$via_loop' matches sibling"
  else
    failed "$case_name" "resolve-precedence='$via_loop' != sibling='$via_sibling' (tokens: $*)"
  fi
}

# ---------------------------------------------------------------------------
# assert_default_composes <case_name>
# COMPOSITION assertion, not a unit assertion. SKILL.md's Inputs table publishes
# `$(loop-state.sh floor)` AS THE VALUE of max_remediation_cycles, so this takes
# the value exactly that way and hands it straight to cycle-decision's
# <max_cycles> argv with NO strip and NO reformat step. A unit test of `floor`
# alone cannot see a `KEY=` label creep back into the output — only this
# composition can, because cycle-decision's require_uint rejects a labelled value
# and the loop would die before the watch could arm.
# ---------------------------------------------------------------------------
assert_default_composes() {
  local case_name="$1"
  local composed exit_code
  composed="$(bash "$SCRIPT" cycle-decision 0 "$DOCUMENTED_DEFAULT_MAX_CYCLES" 1 clean 2>&1)"
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    failed "$case_name" "cycle-decision rejected the documented default '$DOCUMENTED_DEFAULT_MAX_CYCLES' (exit $exit_code): $(printf '%s' "$composed" | tr '\n' '|')"
    return
  fi
  case "$composed" in
    NEXT_COUNT=*EXIT_REASON=*)
      pass "$case_name" "documented default '$DOCUMENTED_DEFAULT_MAX_CYCLES' accepted as <max_cycles>" ;;
    *)
      failed "$case_name" "unexpected cycle-decision output for default '$DOCUMENTED_DEFAULT_MAX_CYCLES': $(printf '%s' "$composed" | tr '\n' '|')" ;;
  esac
}

# ============================================================================
# SECTION 1: cycle-decision — increment ONLY on findings_resolved >= 1
# ============================================================================

# clean below ceiling, resolved=2 → count 0 increments to 1, EXIT_REASON=none.
assert_stdout "cycle:increment-on-resolved" \
  "$(printf 'NEXT_COUNT=1\nEXIT_REASON=none')" \
  cycle-decision 0 6 2 clean

# clean below ceiling, resolved=1 (boundary) → increments.
assert_stdout "cycle:increment-on-resolved-one" \
  "$(printf 'NEXT_COUNT=3\nEXIT_REASON=none')" \
  cycle-decision 2 6 1 clean

# Non-actionable wake: findings_resolved=0 → NO increment, count unchanged, none.
assert_stdout "cycle:no-increment-on-zero-resolved" \
  "$(printf 'NEXT_COUNT=0\nEXIT_REASON=none')" \
  cycle-decision 0 6 0 clean

# Non-actionable wake mid-loop: count stays put.
assert_stdout "cycle:no-increment-preserves-count" \
  "$(printf 'NEXT_COUNT=2\nEXIT_REASON=none')" \
  cycle-decision 2 6 0 clean

# ============================================================================
# SECTION 2: cycle-decision — ceiling fires max-cycles-reached
# ============================================================================

# next_count reaching max_cycles → max-cycles-reached (count 5 -> 6 == max 6).
assert_stdout "ceiling:next-reaches-max" \
  "$(printf 'NEXT_COUNT=6\nEXIT_REASON=max-cycles-reached')" \
  cycle-decision 5 6 1 clean

# next_count EXCEEDS max (current already at max, increments past) → still fires.
assert_stdout "ceiling:next-exceeds-max" \
  "$(printf 'NEXT_COUNT=7\nEXIT_REASON=max-cycles-reached')" \
  cycle-decision 6 6 5 clean

# At ceiling but NO increment (resolved=0) → count stays below max, keep watching.
assert_stdout "ceiling:no-increment-stays-below" \
  "$(printf 'NEXT_COUNT=5\nEXIT_REASON=none')" \
  cycle-decision 5 6 0 clean

# One resolved finding lands exactly ON the ceiling → terminal.
# P1 repro lock: arm-gate must NOT arm when EXIT_REASON != none.
# RETARGETED, NOT DROPPED: this lock originally ran `0 1 1 clean` (cycle-0 against
# max=1). Under the declared max_remediation_cycles floor a cycle-0 `clean` can no
# longer reach the ceiling in a single step, so that exact scenario is unreachable
# BY CONSTRUCTION — max_cycles below the floor is now rejected outright. The
# arm-gate behavior it guarded is preserved here at the floor's own boundary, and
# the cycle-0 side of that gate remains covered by SECTION 3's cycle-0 escalation
# cases (terminal:planner-escalation-resolved-increments and
# terminal:planner-escalation-zero-resolved-held).
assert_stdout "ceiling:cycle0-max1-resolved-terminal" \
  "$(printf 'NEXT_COUNT=6\nEXIT_REASON=max-cycles-reached')" \
  cycle-decision 5 6 1 clean

# cycle-0, max at the floor, one finding resolved → NEXT_COUNT=1 below ceiling →
# keep watching. Positive side of the arm-gate: EXIT_REASON=none → skill arms the
# Monitor.
assert_stdout "ceiling:cycle0-max3-resolved-headroom" \
  "$(printf 'NEXT_COUNT=1\nEXIT_REASON=none')" \
  cycle-decision 0 6 1 clean

# ============================================================================
# SECTION 3: cycle-decision — terminal reviewer tokens
#
# Two terminal classes (loop-state.sh encoded decision 4c):
#   - root-cluster-suspected / merge-advised: NOT remediation cycles — NEVER
#     increment, even with findings_resolved >= 1.
#   - escalation terminals (planner-escalation / blocked / injection-suspect /
#     high-severity-rejection / user-input-required): hard-stop but DO count a
#     completed remediation round — increment IFF findings_resolved >= 1. The
#     terminal exit_reason still wins (NOT converted to max-cycles-reached).
# ============================================================================

# --- no-increment terminals (root-cluster / merge-advised) ------------------

# root-cluster-suspected: terminal, NEXT_COUNT unchanged, even with resolved>=1.
assert_stdout "terminal:root-cluster-suspected" \
  "$(printf 'NEXT_COUNT=1\nEXIT_REASON=root-cluster-suspected')" \
  cycle-decision 1 6 3 root-cluster-suspected

# merge-advised: terminal, NEXT_COUNT unchanged, even with resolved>=1.
assert_stdout "terminal:merge-advised" \
  "$(printf 'NEXT_COUNT=2\nEXIT_REASON=merge-advised')" \
  cycle-decision 2 6 4 merge-advised

# --- escalation terminals: increment WHEN findings_resolved >= 1 ------------

# planner-escalation with resolved>=1: mixed fix+escalate pass IS a cycle → +1.
assert_stdout "terminal:planner-escalation-resolved-increments" \
  "$(printf 'NEXT_COUNT=1\nEXIT_REASON=planner-escalation')" \
  cycle-decision 0 6 1 planner-escalation

# blocked with resolved>=1: increments.
assert_stdout "terminal:blocked-resolved-increments" \
  "$(printf 'NEXT_COUNT=2\nEXIT_REASON=blocked')" \
  cycle-decision 1 6 2 blocked

# injection-suspect with resolved>=1: increments.
assert_stdout "terminal:injection-suspect-resolved-increments" \
  "$(printf 'NEXT_COUNT=4\nEXIT_REASON=injection-suspect')" \
  cycle-decision 3 6 1 injection-suspect

# high-severity-rejection with resolved>=1: increments.
assert_stdout "terminal:high-severity-rejection-resolved-increments" \
  "$(printf 'NEXT_COUNT=1\nEXIT_REASON=high-severity-rejection')" \
  cycle-decision 0 6 9 high-severity-rejection

# user-input-required with resolved>=1: increments.
assert_stdout "terminal:user-input-required-resolved-increments" \
  "$(printf 'NEXT_COUNT=3\nEXIT_REASON=user-input-required')" \
  cycle-decision 2 6 1 user-input-required

# --- escalation terminals: NO increment when findings_resolved == 0 --------

# planner-escalation with resolved==0: pure escalation, no completed round → held.
assert_stdout "terminal:planner-escalation-zero-resolved-held" \
  "$(printf 'NEXT_COUNT=0\nEXIT_REASON=planner-escalation')" \
  cycle-decision 0 6 0 planner-escalation

# blocked with resolved==0: held.
assert_stdout "terminal:blocked-zero-resolved-held" \
  "$(printf 'NEXT_COUNT=1\nEXIT_REASON=blocked')" \
  cycle-decision 1 6 0 blocked

# Escalation terminal increment does NOT convert to max-cycles-reached even when
# it reaches the ceiling — the escalation exit_reason wins. current_count is
# retargeted to 5 alongside max_cycles so the increment still LANDS ON the ceiling;
# a bare max_cycles retarget would leave headroom and stop exercising the property.
assert_stdout "terminal:escalation-increment-at-ceiling-keeps-reason" \
  "$(printf 'NEXT_COUNT=6\nEXIT_REASON=planner-escalation')" \
  cycle-decision 5 6 1 planner-escalation

# ============================================================================
# SECTION 4: cycle-decision — same-finding-repeat → max-cycles-reached, no incr
# ============================================================================

assert_stdout "oscillation:same-finding-repeat" \
  "$(printf 'NEXT_COUNT=2\nEXIT_REASON=max-cycles-reached')" \
  cycle-decision 2 6 3 same-finding-repeat

# same-finding-repeat at count 0 → still no increment.
assert_stdout "oscillation:same-finding-repeat-zero" \
  "$(printf 'NEXT_COUNT=0\nEXIT_REASON=max-cycles-reached')" \
  cycle-decision 0 6 0 same-finding-repeat

# ============================================================================
# SECTION 4b: cycle-decision — approval-clean → TERMINAL clean, no increment
#
# The CODEX_APPROVED confirmation pass found nothing actionable. Unlike a plain
# `clean` (keep watching → EXIT_REASON=none), approval-clean is the successful
# approval terminal and MUST emit EXIT_REASON=clean. No increment (a confirmation
# pass that finds nothing is not a remediation round).
# ============================================================================

# approval-clean mid-loop: TERMINAL clean, count held, regardless of headroom.
assert_stdout "approval-clean:terminal-clean" \
  "$(printf 'NEXT_COUNT=2\nEXIT_REASON=clean')" \
  cycle-decision 2 6 0 approval-clean

# approval-clean at count 0: still terminal clean, count held.
assert_stdout "approval-clean:terminal-clean-zero" \
  "$(printf 'NEXT_COUNT=0\nEXIT_REASON=clean')" \
  cycle-decision 0 6 0 approval-clean

# Contrast: plain `clean` with resolved==0 keeps watching (EXIT_REASON=none),
# proving approval-clean is a DISTINCT terminal mapping (already asserted in
# SECTION 1 cycle:no-increment-on-zero-resolved; restated for adjacency).
assert_stdout "approval-clean:plain-clean-keeps-watching" \
  "$(printf 'NEXT_COUNT=0\nEXIT_REASON=none')" \
  cycle-decision 0 6 0 clean

# ============================================================================
# SECTION 4c: floor — the DECLARED max_remediation_cycles floor is the ENFORCED
# floor. loop-state.sh is the sole source of the number; `floor` is how callers
# and prose read it without restating it.
# ============================================================================

# `floor` is a VALUE-PUBLISHING command: a BARE integer, no `KEY=` routing label,
# because its output is substituted where the literal used to sit.
assert_stdout "floor:emits-constant" "6" floor

# The documented default, taken EXACTLY the way SKILL.md's Inputs table publishes
# it: the command's stdout IS the value of max_remediation_cycles.
DOCUMENTED_DEFAULT_MAX_CYCLES="$(bash "$SCRIPT" floor 2>/dev/null)"

# The composition the unit case above cannot see: documented default -> argv.
assert_default_composes "floor:documented-default-composes"

# The other direction, DERIVED from the published value rather than a re-listed
# literal: one below what `floor` publishes must be rejected by cycle-decision.
# This ties `floor`'s output to the guard actually enforced, so a `floor` that
# published some OTHER number than the guard compares against cannot stay green.
assert_nonzero_stderr "floor:one-below-published-rejected" \
  cycle-decision 0 "$((DOCUMENTED_DEFAULT_MAX_CYCLES - 1))" 1 clean

# ============================================================================
# SECTION 5: token-map — each loop signal → its exit_reason
# ============================================================================

assert_stdout "tokenmap:state-merged"   "EXIT_REASON=pr-merged"          token-map STATE=MERGED
assert_stdout "tokenmap:state-closed"   "EXIT_REASON=pr-closed"          token-map STATE=CLOSED
assert_stdout "tokenmap:watch-timeout"  "EXIT_REASON=watch-window-elapsed" token-map WATCH_TIMEOUT
assert_stdout "tokenmap:poll-error"     "EXIT_REASON=blocked"            token-map POLL_ERROR

# ============================================================================
# SECTION 6: resolve-precedence — winner MUST match sibling exit-precedence.sh
# (expected derived from the sibling directly; never a re-listed ladder here)
# ============================================================================

assert_matches_sibling "precedence:single-token"        blocked
assert_matches_sibling "precedence:reviewer-vs-guard"   merge-advised max-cycles-reached
assert_matches_sibling "precedence:prstate-vs-cycle"    pr-merged max-cycles-reached
assert_matches_sibling "precedence:escalation-vs-prstate" injection-suspect pr-closed
assert_matches_sibling "precedence:terminal-vs-clean"   clean root-cluster-suspected
assert_matches_sibling "precedence:three-tokens"        blocked pr-merged max-cycles-reached
assert_matches_sibling "precedence:guard-pair"          pr-closed blocked

# ============================================================================
# SECTION 7: clean below ceiling → none (keep watching)
# ============================================================================

# Already covered in SECTION 1; an explicit large-headroom case for clarity.
assert_stdout "clean:keep-watching" \
  "$(printf 'NEXT_COUNT=1\nEXIT_REASON=none')" \
  cycle-decision 0 10 1 clean

# ============================================================================
# SECTION 8: Loud rejection — unknown/garbage/bad-argc → nonzero exit + stderr
# ============================================================================

# No subcommand at all.
assert_nonzero_stderr "reject:no-subcommand"

# Unknown subcommand.
assert_nonzero_stderr "reject:unknown-subcommand"       frobnicate

# cycle-decision: wrong arg count (too few).
assert_nonzero_stderr "reject:cycle-too-few-args"       cycle-decision 0 5 clean

# cycle-decision: wrong arg count (too many).
assert_nonzero_stderr "reject:cycle-too-many-args"      cycle-decision 0 5 1 clean extra

# cycle-decision: non-integer current_count.
assert_nonzero_stderr "reject:cycle-bad-current"        cycle-decision abc 5 1 clean

# cycle-decision: non-integer findings_resolved.
assert_nonzero_stderr "reject:cycle-bad-resolved"       cycle-decision 0 5 x clean

# cycle-decision: max_cycles=0 — subsumed by the floor guard, still rejects.
assert_nonzero_stderr "reject:cycle-zero-max"           cycle-decision 0 0 1 clean

# cycle-decision: max_cycles below the declared floor (a legal positive integer
# under the old `>= 1` guard) → rejected. The declared floor IS the enforced floor.
assert_nonzero_stderr "reject:cycle-below-floor"        cycle-decision 0 5 1 clean

# cycle-decision: negative number (sign char rejected by require_uint).
assert_nonzero_stderr "reject:cycle-negative"           cycle-decision -1 5 1 clean

# cycle-decision: unknown reviewer_exit_reason that is neither terminal nor clean.
# max_cycles retargeted to the floor so the rejection is attributable to the token
# rather than being masked by the floor guard firing first.
assert_nonzero_stderr "reject:cycle-unknown-reason"     cycle-decision 0 6 1 notarealtoken

# token-map: unknown signal.
assert_nonzero_stderr "reject:tokenmap-unknown-signal"  token-map STATE=PENDING

# token-map: wrong arg count.
assert_nonzero_stderr "reject:tokenmap-no-arg"          token-map

# floor: takes no args — a surplus arg is a caller bug, rejected loudly.
assert_nonzero_stderr "reject:floor-surplus-arg"        floor 6

# resolve-precedence: no tokens.
assert_nonzero_stderr "reject:resolve-no-tokens"        resolve-precedence

# resolve-precedence: unknown token forwarded to sibling rejects loudly.
assert_nonzero_stderr "reject:resolve-unknown-token"    resolve-precedence notarealtoken

# ============================================================================
# Summary
# ============================================================================
printf '\nloop-state: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
