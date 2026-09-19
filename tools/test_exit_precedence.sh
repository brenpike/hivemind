#!/usr/bin/env bash
#
# Behavioral unit runner for the exit_reason precedence ladder (issue #204, STEP-003).
#
# Tests plugin/skills/github-review-loop/scripts/exit-precedence.sh against the
# 15-rank ladder defined in that script's header. CI-runnable with bash only — no
# jq, no tmux, no network. Pure subprocess invocation of the script under test.
#
# Mirrors tools/test_fix_history_classify.sh: pass/fail counters, per-case
# assertion helper, exit-nonzero-on-any-fail.
#
# Usage:
#   bash tools/test_exit_precedence.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SCRIPT="$REPO_ROOT/plugin/skills/github-review-loop/scripts/exit-precedence.sh"

[ -f "$SCRIPT" ] || { printf 'FAIL: script under test missing: %s\n' "$SCRIPT" >&2; exit 2; }

PASS_COUNT=0
FAIL_COUNT=0
pass()   { printf 'PASS [%s] %s\n' "$1" "$2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { printf 'FAIL [%s] %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---------------------------------------------------------------------------
# assert_args <case_name> <expected_stdout> <token> [token ...]
# Invoke via positional arguments; assert stdout and exit 0.
# ---------------------------------------------------------------------------
assert_args() {
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
    pass "$case_name" "(args) got: $actual"
  else
    failed "$case_name" "(args) expected='$expected' actual='$actual'"
  fi
}

# ---------------------------------------------------------------------------
# assert_stdin <case_name> <expected_stdout> <stdin_string>
# Invoke via stdin; assert stdout and exit 0.
# ---------------------------------------------------------------------------
assert_stdin() {
  local case_name="$1" expected="$2" input="$3"
  local actual exit_code
  actual="$(printf '%s' "$input" | bash "$SCRIPT" 2>/dev/null)"
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    failed "$case_name" "expected exit 0, got $exit_code (stdin: '$input')"
    return
  fi
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "(stdin) got: $actual"
  else
    failed "$case_name" "(stdin) expected='$expected' actual='$actual'"
  fi
}

# ---------------------------------------------------------------------------
# assert_nonzero_args <case_name> <token> [token ...]
# Invoke via positional arguments; assert exit nonzero.
# ---------------------------------------------------------------------------
assert_nonzero_args() {
  local case_name="$1"
  shift 1
  local exit_code
  bash "$SCRIPT" "$@" >/dev/null 2>/dev/null
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    pass "$case_name" "(args nonzero) exit=$exit_code"
  else
    failed "$case_name" "(args nonzero) expected nonzero exit, got 0"
  fi
}

# ---------------------------------------------------------------------------
# assert_nonzero_stderr_args <case_name> <token> [token ...]
# Invoke via positional arguments; assert exit nonzero AND stderr non-empty.
# ---------------------------------------------------------------------------
assert_nonzero_stderr_args() {
  local case_name="$1"
  shift 1
  local stderr_out exit_code
  stderr_out="$(bash "$SCRIPT" "$@" 2>&1 >/dev/null)"
  exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    failed "$case_name" "expected nonzero exit, got 0"
    return
  fi
  if [ -n "$stderr_out" ]; then
    pass "$case_name" "exit=$exit_code stderr non-empty"
  else
    failed "$case_name" "exit=$exit_code but stderr was empty"
  fi
}

# ============================================================================
# SECTION 1: Empty input — both forms
# ============================================================================

# No args, no stdin (redirect from /dev/null to avoid terminal check in CI)
actual_empty="$(bash "$SCRIPT" </dev/null 2>/dev/null)"
exit_empty=$?
if [ "$exit_empty" -eq 0 ] && [ "$actual_empty" = "clean" ]; then
  pass "empty:no-args-no-stdin" "got clean, exit 0"
else
  failed "empty:no-args-no-stdin" "exit=$exit_empty stdout='$actual_empty'"
fi

# Empty stdin explicitly
assert_stdin "empty:empty-stdin" "clean" ""

# Whitespace-only stdin
assert_stdin "empty:whitespace-stdin" "clean" "   "

# ============================================================================
# SECTION 2: Single-token passthrough (args and stdin)
# ============================================================================

assert_args  "single:injection-suspect-args"       "injection-suspect"       "injection-suspect"
assert_args  "single:high-severity-rejection-args" "high-severity-rejection" "high-severity-rejection"
assert_args  "single:clean-args"                   "clean"                   "clean"
assert_args  "single:blocked-args"                 "blocked"                 "blocked"
assert_stdin "single:merge-advised-stdin"          "merge-advised"           "merge-advised"
assert_stdin "single:max-cycles-reached-stdin"     "max-cycles-reached"      "max-cycles-reached"
assert_args  "single:watch-window-elapsed-args"    "watch-window-elapsed"    "watch-window-elapsed"

# ============================================================================
# SECTION 3: Adjacent ladder pairs — each should return the higher (14 pairs)
# Ranks: 1  2  3  4  5  6  7  8  9  10  11  12  13  14  15
# 10=pr-merged 11=pr-closed 12=max-iterations 13=max-cycles
# 14=watch-window-elapsed 15=clean
# ============================================================================

# Pair 1/2: injection-suspect beats high-severity-rejection
assert_args "adj:rank1-beats-2-args"   "injection-suspect"      "injection-suspect"      "high-severity-rejection"
assert_stdin "adj:rank1-beats-2-stdin" "injection-suspect"      "injection-suspect high-severity-rejection"

# Pair 2/3
assert_args "adj:rank2-beats-3-args"   "high-severity-rejection" "high-severity-rejection" "user-input-required"
assert_stdin "adj:rank2-beats-3-stdin" "high-severity-rejection" "user-input-required high-severity-rejection"

# Pair 3/4
assert_args "adj:rank3-beats-4-args"   "user-input-required" "user-input-required" "planner-escalation"
assert_stdin "adj:rank3-beats-4-stdin" "user-input-required" "planner-escalation user-input-required"

# Pair 4/5
assert_args "adj:rank4-beats-5-args"   "planner-escalation" "planner-escalation" "break-fix-break"
assert_stdin "adj:rank4-beats-5-stdin" "planner-escalation" "break-fix-break planner-escalation"

# Pair 5/6: break-fix-break beats blocked (alias tier adjacency)
assert_args "adj:rank5-beats-6-args"   "break-fix-break" "break-fix-break" "blocked"
assert_stdin "adj:rank5-beats-6-stdin" "break-fix-break" "blocked break-fix-break"

# Pair 6/7
assert_args "adj:rank6-beats-7-args"   "blocked" "blocked" "root-cluster-suspected"
assert_stdin "adj:rank6-beats-7-stdin" "blocked" "root-cluster-suspected blocked"

# Pair 7/8
assert_args "adj:rank7-beats-8-args"   "root-cluster-suspected" "root-cluster-suspected" "diminishing-returns"
assert_stdin "adj:rank7-beats-8-stdin" "root-cluster-suspected" "diminishing-returns root-cluster-suspected"

# Pair 8/9
assert_args "adj:rank8-beats-9-args"   "diminishing-returns" "diminishing-returns" "merge-advised"
assert_stdin "adj:rank8-beats-9-stdin" "diminishing-returns" "merge-advised diminishing-returns"

# Pair 9/10: merge-advised beats pr-merged
assert_args "adj:rank9-beats-10-args"   "merge-advised" "merge-advised" "pr-merged"
assert_stdin "adj:rank9-beats-10-stdin" "merge-advised" "pr-merged merge-advised"

# Pair 10/11: pr-merged beats pr-closed (merge is the success terminal)
assert_args "adj:rank10-beats-11-args"   "pr-merged" "pr-merged" "pr-closed"
assert_stdin "adj:rank10-beats-11-stdin" "pr-merged" "pr-closed pr-merged"

# Pair 11/12: pr-closed beats max-iterations-reached (PR-state terminal dominates budget ceiling)
assert_args "adj:rank11-beats-12-args"   "pr-closed" "pr-closed" "max-iterations-reached"
assert_stdin "adj:rank11-beats-12-stdin" "pr-closed" "max-iterations-reached pr-closed"

# Pair 12/13
assert_args "adj:rank12-beats-13-args"   "max-iterations-reached" "max-iterations-reached" "max-cycles-reached"
assert_stdin "adj:rank12-beats-13-stdin" "max-iterations-reached" "max-cycles-reached max-iterations-reached"

# Pair 13/14: max-cycles-reached beats watch-window-elapsed (a real cycle ceiling
# is the more informative report than a quiet idle window elapsing)
assert_args "adj:rank13-beats-14-args"   "max-cycles-reached" "max-cycles-reached" "watch-window-elapsed"
assert_stdin "adj:rank13-beats-14-stdin" "max-cycles-reached" "watch-window-elapsed max-cycles-reached"

# Pair 14/15: watch-window-elapsed beats clean (more specific than "nothing fired")
assert_args "adj:rank14-beats-15-args"   "watch-window-elapsed" "watch-window-elapsed" "clean"
assert_stdin "adj:rank14-beats-15-stdin" "watch-window-elapsed" "clean watch-window-elapsed"

# Transitive: max-cycles-reached still beats the clean floor across the new rank
assert_args "adj:rank13-beats-15-args"   "max-cycles-reached" "max-cycles-reached" "clean"
assert_stdin "adj:rank13-beats-15-stdin" "max-cycles-reached" "clean max-cycles-reached"

# ============================================================================
# SECTION 4: Non-adjacent multi-token inputs spanning tiers
# ============================================================================

# rank1 beats rank7 and rank12
assert_args "nonadj:rank1-beats-7-12" "injection-suspect" \
  "root-cluster-suspected" "injection-suspect" "clean"

# rank3 beats rank8 and rank11
assert_args "nonadj:rank3-beats-8-11" "user-input-required" \
  "diminishing-returns" "max-cycles-reached" "user-input-required"

# rank4 beats rank9 and rank10
assert_stdin "nonadj:rank4-beats-9-10-stdin" "planner-escalation" \
  "merge-advised max-iterations-reached planner-escalation"

# rank6 beats rank9 and rank12
assert_args "nonadj:rank6-beats-9-12" "blocked" \
  "merge-advised" "clean" "blocked"

# rank7 beats rank13 and rank12
assert_stdin "nonadj:rank7-beats-12-13-stdin" "root-cluster-suspected" \
  "max-iterations-reached root-cluster-suspected max-cycles-reached"

# ============================================================================
# SECTION 4b: PR-state terminals (pr-merged rank 10, pr-closed rank 11) — these
# are the github-review-loop STATE=MERGED / STATE=CLOSED guard tokens. Before
# this they were absent from the ladder and hit the unknown-token reject path
# whenever surfaced alongside another guard (e.g. max-cycles-reached). Assert
# they are now VALID tokens: pass through as singletons, dominate the budget
# ceilings, and lose to genuine escalations above them.
# ============================================================================

# Singleton passthrough — must NOT be rejected as unknown.
assert_args  "prstate:pr-merged-single-args"  "pr-merged" "pr-merged"
assert_args  "prstate:pr-closed-single-args"  "pr-closed" "pr-closed"
assert_stdin "prstate:pr-merged-single-stdin" "pr-merged" "pr-merged"
assert_stdin "prstate:pr-closed-single-stdin" "pr-closed" "pr-closed"

# The exact regression the finding describes: MERGED/CLOSED alongside another
# guard must produce a terminal, not exit 1.
assert_args  "prstate:pr-merged-beats-max-cycles" "pr-merged" "pr-merged" "max-cycles-reached"
assert_stdin "prstate:pr-closed-beats-max-cycles" "pr-closed" "max-cycles-reached pr-closed"
assert_args  "prstate:pr-merged-beats-max-iters"  "pr-merged" "max-iterations-reached" "pr-merged"

# PR-state terminals lose to genuine escalations above them.
assert_args  "prstate:injection-beats-pr-merged"  "injection-suspect" "pr-merged" "injection-suspect"
assert_stdin "prstate:blocked-beats-pr-closed"    "blocked" "pr-closed blocked"
assert_args  "prstate:merge-advised-beats-pr-merged" "merge-advised" "pr-merged" "merge-advised"

# ============================================================================
# SECTION 5: All 15 tokens at once → injection-suspect
# ============================================================================

assert_args "all15:args" "injection-suspect" \
  "injection-suspect" "high-severity-rejection" "user-input-required" \
  "planner-escalation" "break-fix-break" "blocked" \
  "root-cluster-suspected" "diminishing-returns" "merge-advised" \
  "pr-merged" "pr-closed" \
  "max-iterations-reached" "max-cycles-reached" "watch-window-elapsed" "clean"

assert_stdin "all15:stdin" "injection-suspect" \
  "injection-suspect high-severity-rejection user-input-required planner-escalation break-fix-break blocked root-cluster-suspected diminishing-returns merge-advised pr-merged pr-closed max-iterations-reached max-cycles-reached watch-window-elapsed clean"

# ============================================================================
# SECTION 6: Alias tier — break-fix-break (5) vs blocked (6) vs root-cluster (7)
# ============================================================================

# break-fix-break beats blocked
assert_args "alias:bfb-beats-blocked-args"   "break-fix-break" "break-fix-break" "blocked"
assert_stdin "alias:bfb-beats-blocked-stdin" "break-fix-break" "blocked break-fix-break"

# blocked beats root-cluster-suspected
assert_args "alias:blocked-beats-rcs-args"   "blocked" "blocked" "root-cluster-suspected"
assert_stdin "alias:blocked-beats-rcs-stdin" "blocked" "root-cluster-suspected blocked"

# break-fix-break beats root-cluster-suspected (transitive)
assert_args "alias:bfb-beats-rcs-args"   "break-fix-break" "break-fix-break" "root-cluster-suspected"
assert_stdin "alias:bfb-beats-rcs-stdin" "break-fix-break" "root-cluster-suspected break-fix-break"

# All three together → break-fix-break
assert_args "alias:all-three-args"   "break-fix-break" "break-fix-break" "blocked" "root-cluster-suspected"
assert_stdin "alias:all-three-stdin" "break-fix-break" "root-cluster-suspected blocked break-fix-break"

# ============================================================================
# SECTION 7: Bare clean floor
# ============================================================================

assert_args  "floor:clean-alone-args"   "clean" "clean"
assert_stdin "floor:clean-alone-stdin"  "clean" "clean"

# clean loses to every other token; verify against the highest-rank token
assert_args  "floor:clean-loses-to-max-cycles" "max-cycles-reached" "clean" "max-cycles-reached"
assert_stdin "floor:clean-loses-to-max-iter"   "max-iterations-reached" "max-iterations-reached
clean"
# clean also loses to the rank immediately above it
assert_args  "floor:clean-loses-to-watch-window" "watch-window-elapsed" "clean" "watch-window-elapsed"

# ============================================================================
# SECTION 8: Unknown / garbage tokens → nonzero exit + stderr non-empty
# ============================================================================

assert_nonzero_stderr_args "unknown:garbage-string-args"       "notarealtoken"
# A single positional argv is exactly ONE token (no word-splitting). An empty
# string argv is a single empty token and must REJECT LOUDLY, not silently drop
# to the empty-input clean floor.
assert_nonzero_stderr_args "unknown:empty-string-token-args"   ""
# A single argv carrying internal whitespace (e.g. "blocked clean") is ONE
# malformed token, not two valid tokens — it must reject, never split to "blocked".
assert_nonzero_stderr_args "unknown:whitespace-in-single-argv" "blocked clean"
# A single argv carrying a glob character must reject as one unknown token, never
# glob-expand against the working directory.
assert_nonzero_stderr_args "unknown:glob-char-in-single-argv"  "blocked *"
assert_nonzero_stderr_args "unknown:partial-token-args"        "injection"
assert_nonzero_stderr_args "unknown:mixed-valid-invalid-args"  "clean" "notarealtoken"

# Unknown via stdin
actual_unk_exit=0
bash "$SCRIPT" <<<"garbage-token" >/dev/null 2>/dev/null || actual_unk_exit=$?
if [ "$actual_unk_exit" -ne 0 ]; then
  pass "unknown:garbage-stdin" "exit=$actual_unk_exit"
else
  failed "unknown:garbage-stdin" "expected nonzero exit, got 0"
fi

# ============================================================================
# SECTION 9: Multiline stdin (newline-delimited tokens)
# ============================================================================

assert_stdin "multiline:two-tokens-newline" "user-input-required" \
  "merge-advised
user-input-required"

assert_stdin "multiline:all-ranks-newline" "injection-suspect" \
  "clean
watch-window-elapsed
max-cycles-reached
max-iterations-reached
pr-closed
pr-merged
merge-advised
diminishing-returns
root-cluster-suspected
blocked
break-fix-break
planner-escalation
user-input-required
high-severity-rejection
injection-suspect"

# ============================================================================
# Summary
# ============================================================================
printf '\nexit-precedence: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
