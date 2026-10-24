#!/usr/bin/env bash
#
# Behavioral test harness for the CONCURRENT run_suites() in tools/validate.sh
# (issue: validate-suite-speedup, Codex F3 remediation, R-STEP-001).
#
# run_suites() backgrounds each selected suite (`&` + bounded pid pool + wait),
# collects each suite's exit status from a per-job scratch rc file, applies an
# `echo 1` fail-safe when an rc file is missing, computes the aggregate exit
# code, and REPLAYS every suite's report in canonical ALL_SUITES order rather
# than completion order. That surface had NO committed behavioral test — it is
# the highest false-green risk in the dispatcher (a dropped non-zero rc or a
# completion-ordered replay would silently green the merge gate).
#
# This harness exercises the REAL inline run_suites() unmodified. It does NOT
# extract or edit run_suites' production logic. Mechanism (ii): source a copy of
# validate.sh with its source-time `main "$@"` line removed (a sourcing guard —
# the production file is never edited), then override only the INJECTION POINTS:
#   - ALL_SUITES         : the canonical-order array run_suites replays against
#   - run_suite()        : the per-suite executor (stubbed to produce deterministic
#                          pass/fail + sleep-skewed completion order, writing nothing
#                          into the repo tree)
#   - nproc              : pinned for deterministic concurrency (N>1 and N=1 paths)
# Overriding these leaves run_suites' concurrency, wait-based rc collection,
# missing-rc fallback, aggregate-rc, and canonical replay running unmodified.
#
# Assertions target the OBSERVABLE CONTRACT — aggregate exit code + replayed
# report order on stdout — NOT scratch-file internals (out.$i/rc.$i naming), so
# benign refactors of the scratch layout do not break this harness.
#
# CI-runnable with bash only — no jq, no tmux, no network.
#
# Usage:
#   bash tools/test_validate_suites.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
VALIDATE_SH="$SCRIPT_DIR/validate.sh"

[ -f "$VALIDATE_SH" ] || { printf 'FAIL: script under test missing: %s\n' "$VALIDATE_SH" >&2; exit 2; }

# wait -n (bash 5+) is used by run_suites' bounded pid pool. SKIP loudly on older bash
# rather than produce a misleading green.
if ! (wait -n) 2>/dev/null; then
  case "${BASH_VERSINFO[0]:-0}" in
    [5-9]|[1-9][0-9]) : ;;  # bash 5+ — wait -n returns nonzero only because no jobs exist
    *)
      printf 'SKIP: run_suites concurrency requires bash 5+ (wait -n); have %s\n' "${BASH_VERSION:-unknown}" >&2
      exit 0
      ;;
  esac
fi

PASS_COUNT=0
FAIL_COUNT=0
pass()   { printf 'PASS [%s] %s\n' "$1" "$2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { printf 'FAIL [%s] %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# All scratch lives under one mktemp -d; EXIT-trap cleanup leaves the repo tree untouched.
HARNESS_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/test-validate-suites.XXXXXX")"
cleanup_harness() { [ -n "${HARNESS_SCRATCH:-}" ] && rm -rf -- "$HARNESS_SCRATCH"; }
trap cleanup_harness EXIT

# A copy of validate.sh with the final source-time `main "$@"` line removed, so sourcing
# it loads run_suites + helpers + ALL_SUITES WITHOUT executing the dispatcher. The exact
# line is asserted unique below before stripping (a sourcing guard, not a production edit).
VALIDATE_NOMAIN="$HARNESS_SCRATCH/validate-nomain.sh"

main_lines="$(grep -c '^main "\$@"$' "$VALIDATE_SH" || true)"
if [ "$main_lines" != "1" ]; then
  printf 'FAIL: expected exactly one source-time `main "$@"` line in validate.sh, found %s — harness guard assumption broken\n' "$main_lines" >&2
  exit 2
fi
grep -v '^main "\$@"$' "$VALIDATE_SH" >"$VALIDATE_NOMAIN"

# ---------------------------------------------------------------------------
# run_suites is invoked in a SUBSHELL per scenario so each scenario gets a fresh
# sourced copy with its own ALL_SUITES / run_suite / nproc overrides, and so the
# EXIT-trap that run_suites installs (cleanup_suites_scratch) fires in isolation
# and never collides across scenarios. The subshell prints the run_suites stdout
# and, on its LAST line, the aggregate rc as "RUN_SUITES_RC=<n>".
#
# Stub-suite tokens encode behavior so run_suite (overridden) can produce a
# deterministic pass/fail and sleep-skewed completion order:
#   STUB:<name>:<rc>:<sleep>   -> sleep <sleep>, emit a marker, return <rc>
#   STUB:<name>:vanish:<sleep> -> sleep <sleep>, then KILL its own job subshell
#                                 BEFORE run_one_suite writes rc.<i>, exercising
#                                 the real missing-rc `echo 1` fail-safe.
# ---------------------------------------------------------------------------
# run_scenario <pinned_nproc> <stub_token> [stub_token ...]
# Echoes the full run_suites stdout plus a trailing RUN_SUITES_RC=<rc> line.
run_scenario() {
  local pinned_nproc="$1"; shift
  local -a stubs=("$@")
  (
    # shellcheck disable=SC1090
    source "$VALIDATE_NOMAIN"
    # The sourced copy re-runs `set -euo pipefail` (validate.sh line 21), so relax `errexit`
    # AFTER sourcing: this harness drives run_suites through failing/vanishing stubs and asserts
    # on its return value, which `set -e` would otherwise convert into a subshell abort.
    set +e

    # INJECTION: canonical order = the order of the stub tokens as passed. run_suites
    # replays in ALL_SUITES order, so this array defines the expected replay order.
    ALL_SUITES=("${stubs[@]}")

    # INJECTION: deterministic per-suite executor. Parses the STUB token, applies the
    # encoded sleep to skew completion order, and returns the encoded rc — or kills its
    # own subshell to force a missing rc file. Writes nothing into the repo tree;
    # run_one_suite redirects this function's stdout to its scratch out file.
    run_suite() {
      local token="$1"
      local name rc_field sleep_field
      name="$(printf '%s' "$token" | cut -d: -f2)"
      rc_field="$(printf '%s' "$token" | cut -d: -f3)"
      sleep_field="$(printf '%s' "$token" | cut -d: -f4)"
      [ -n "$sleep_field" ] && sleep "$sleep_field"
      if [ "$rc_field" = "vanish" ]; then
        # Terminate THIS backgrounded job subshell before run_one_suite records rc.<i>.
        # The absent rc file must drive run_suites' `echo 1` fail-safe (treat as FAILURE).
        kill -s KILL "$BASHPID"
      fi
      printf 'STUB-MARKER name=%s rc=%s\n' "$name" "$rc_field"
      return "$rc_field"
    }

    # INJECTION: pin nproc for deterministic concurrency width (N>1 and N=1 paths).
    nproc() { printf '%s\n' "$pinned_nproc"; }

    # Merge stderr into stdout: run_suites emits per-suite `--- [s] FAIL ---` lines on
    # STDERR (validate.sh), and the harness asserts on those FAIL markers, so they must land
    # in the captured string. Parsers (rc_of / replay_order) are line-anchored, so interleave
    # is safe.
    run_suites "${ALL_SUITES[@]}" 2>&1
    rc=$?
    printf 'RUN_SUITES_RC=%s\n' "$rc"
  )
}

# Extract the trailing aggregate rc from a run_scenario capture.
rc_of() { printf '%s\n' "$1" | sed -n 's/^RUN_SUITES_RC=//p' | tail -n1; }

# Echo the canonical replay order: the suite name of each "=== running [STUB:name:...] ==="
# block, in the order it appears in the captured stdout.
replay_order() {
  printf '%s\n' "$1" \
    | sed -n 's/^=== validate.sh: running \[STUB:\([^:]*\):.*\] ===$/\1/p'
}

# ============================================================================
# SECTION A: AGGREGATE-RC
#   (a1) all stubs pass            -> rc 0
#   (a2) >=1 stub fails            -> rc nonzero, after waiting on every suite
#   (a3) a vanished/missing rc file is treated as FAILURE (echo 1 fail-safe)
# ============================================================================

# (a1) All pass, N>1 concurrency.
out_a1="$(run_scenario 4 \
  "STUB:alpha:0:0" "STUB:bravo:0:0" "STUB:charlie:0:0")"
rc_a1="$(rc_of "$out_a1")"
if [ "$rc_a1" = "0" ]; then
  pass "aggregate:all-pass-rc0" "rc=$rc_a1"
else
  failed "aggregate:all-pass-rc0" "expected rc 0, got '$rc_a1'"
fi

# (a1) Every passing suite must report PASS (no lost suites, full signal).
if grep -q -- '--- \[STUB:alpha:0:0\] PASS ---' <<<"$out_a1" \
   && grep -q -- '--- \[STUB:bravo:0:0\] PASS ---' <<<"$out_a1" \
   && grep -q -- '--- \[STUB:charlie:0:0\] PASS ---' <<<"$out_a1"; then
  pass "aggregate:all-pass-replayed" "all three PASS lines present"
else
  failed "aggregate:all-pass-replayed" "missing a PASS line: $out_a1"
fi

# (a2) One stub fails (rc=2) among passers -> aggregate nonzero, that suite FAILs,
#      and ALL other suites still report (no early abort).
out_a2="$(run_scenario 4 \
  "STUB:alpha:0:0" "STUB:bravo:2:0" "STUB:charlie:0:0")"
rc_a2="$(rc_of "$out_a2")"
if [ -n "$rc_a2" ] && [ "$rc_a2" != "0" ]; then
  pass "aggregate:one-fail-rc-nonzero" "rc=$rc_a2"
else
  failed "aggregate:one-fail-rc-nonzero" "expected nonzero rc, got '$rc_a2'"
fi
if grep -q -- '--- \[STUB:bravo:2:0\] FAIL ---' <<<"$out_a2" \
   && grep -q -- '--- \[STUB:alpha:0:0\] PASS ---' <<<"$out_a2" \
   && grep -q -- '--- \[STUB:charlie:0:0\] PASS ---' <<<"$out_a2"; then
  pass "aggregate:one-fail-full-signal" "failing suite FAILs, others still PASS"
else
  failed "aggregate:one-fail-full-signal" "expected bravo FAIL + alpha/charlie PASS: $out_a2"
fi

# (a3) A vanished job (rc file never written) must be treated as FAILURE via the
#      `echo 1` fail-safe: aggregate nonzero AND that suite reported FAIL, even though
#      every OTHER suite passed.
out_a3="$(run_scenario 4 \
  "STUB:alpha:0:0" "STUB:gone:vanish:0" "STUB:charlie:0:0")"
rc_a3="$(rc_of "$out_a3")"
if [ -n "$rc_a3" ] && [ "$rc_a3" != "0" ]; then
  pass "missing-rc:fail-safe-rc-nonzero" "rc=$rc_a3"
else
  failed "missing-rc:fail-safe-rc-nonzero" "expected nonzero rc from missing rc file, got '$rc_a3'"
fi
if grep -q -- '--- \[STUB:gone:vanish:0\] FAIL ---' <<<"$out_a3"; then
  pass "missing-rc:fail-safe-suite-fail" "vanished suite reported FAIL"
else
  failed "missing-rc:fail-safe-suite-fail" "vanished suite did NOT report FAIL: $out_a3"
fi

# ============================================================================
# SECTION B: CANONICAL-ORDER REPLAY
#   Completion order is deliberately scrambled vs ALL_SUITES order via sleep skew:
#   a FAST-FAILING stub placed LATE in canonical order finishes FIRST, and a
#   SLOW-PASSING stub placed EARLY finishes LAST. The replayed report blocks and
#   PASS/FAIL lines must appear in canonical ALL_SUITES order, NOT completion order.
# ============================================================================

# Canonical order: early (slow pass), middle (medium), late (fast fail).
# Completion order: late finishes first (0s), middle second (~0.2s), early last (~0.4s).
out_b="$(run_scenario 4 \
  "STUB:early:0:0.4" "STUB:middle:0:0.2" "STUB:late:3:0")"
order_b="$(replay_order "$out_b")"
expected_b="$(printf 'early\nmiddle\nlate\n')"
if [ "$order_b" = "$expected_b" ]; then
  pass "replay:canonical-not-completion" "replay order: $(printf '%s' "$order_b" | tr '\n' ' ')"
else
  failed "replay:canonical-not-completion" \
    "expected canonical [early middle late], got [$(printf '%s' "$order_b" | tr '\n' ' ')] — completion-ordered replay?"
fi

# The late, fast-failing suite must still surface its FAIL (aggregate nonzero), proving
# completion-first did not drop the late suite's rc.
rc_b="$(rc_of "$out_b")"
if [ -n "$rc_b" ] && [ "$rc_b" != "0" ] \
   && grep -q -- '--- \[STUB:late:3:0\] FAIL ---' <<<"$out_b"; then
  pass "replay:late-failer-not-lost" "rc=$rc_b, late FAIL present"
else
  failed "replay:late-failer-not-lost" "late fast-failer's FAIL/rc lost: rc='$rc_b' out=$out_b"
fi

# ============================================================================
# SECTION C: N=1 SERIAL PATH (cap pinned to 1) — bounded pool degenerates to one
#   job at a time; aggregate-rc and canonical replay must still hold.
# ============================================================================

out_c="$(run_scenario 1 \
  "STUB:one:0:0" "STUB:two:5:0" "STUB:three:0:0")"
rc_c="$(rc_of "$out_c")"
order_c="$(replay_order "$out_c")"
expected_c="$(printf 'one\ntwo\nthree\n')"
if [ -n "$rc_c" ] && [ "$rc_c" != "0" ] && [ "$order_c" = "$expected_c" ]; then
  pass "n1:serial-aggregate-and-order" "rc=$rc_c order=[$(printf '%s' "$order_c" | tr '\n' ' ')]"
else
  failed "n1:serial-aggregate-and-order" \
    "expected nonzero rc + canonical [one two three]; rc='$rc_c' order=[$(printf '%s' "$order_c" | tr '\n' ' ')]"
fi

# N=1 all-pass -> rc 0.
out_c2="$(run_scenario 1 "STUB:solo:0:0")"
rc_c2="$(rc_of "$out_c2")"
if [ "$rc_c2" = "0" ]; then
  pass "n1:single-suite-pass-rc0" "rc=$rc_c2"
else
  failed "n1:single-suite-pass-rc0" "expected rc 0, got '$rc_c2'"
fi

# ============================================================================
# Summary
# ============================================================================
printf '\nvalidate-suites: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
