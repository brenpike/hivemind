#!/usr/bin/env bash
#
# Behavioral unit runner for the fetch + normalize candidate-set builder (issue #203, STEP-002).
#
# OFFLINE jq/bash TEST — CI-runnable with ONLY jq + bash present (NO tmux / gh / network). It
# drives the pure normalization core of:
#   plugin/skills/github-review-loop/scripts/fetch-normalize.sh
# via its documented test seam (--payload-file / --ci-payload-file, both bypassing the live
# `gh api graphql` / `gh pr checks` fetches), feeds canned fixtures, and asserts the emitted
# normalized JSON array equals an expected set. The normalize core is a PURE function of the
# injected payload(s) + --arg login/filter, so every case is deterministic and offline.
#
# Review-path fixtures are reused from tests/fix-history/ (verified by STEP-001 to conform to
# fetch-normalize.sh's GraphQL input contract). CI-path, connection-tripwire, and empty/malformed
# fixtures are authored under tests/fetch-normalize/. Each case pairs an input fixture with an
# expected normalized output fixture under tests/fetch-normalize/expected/, compared after
# canonicalization (object keys + array elements sorted) so jq key-ordering can never flake it.
#
# Mirrors tools/test_fix_history_classify.sh's pass/fail counter + per-case assertion +
# exit-nonzero-on-any-fail convention. Read-only: the only writes are scratch files in a
# disposable tmpdir removed on EXIT.
#
# Usage:
#   ./tools/test_fetch_normalize.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SKILLS_DIR="$REPO_ROOT/plugin/skills"
NORMALIZE="$SKILLS_DIR/github-review-loop/scripts/fetch-normalize.sh"
FIX_HISTORY_DIR="$REPO_ROOT/tests/fix-history"
FN_DIR="$REPO_ROOT/tests/fetch-normalize"
EXPECTED_DIR="$FN_DIR/expected"

[ -f "$NORMALIZE" ] || { echo "FAIL: script under test missing: $NORMALIZE" >&2; exit 2; }
[ -d "$FIX_HISTORY_DIR" ] || { echo "FAIL: fix-history fixture dir missing: $FIX_HISTORY_DIR" >&2; exit 2; }
[ -d "$FN_DIR" ] || { echo "FAIL: fetch-normalize fixture dir missing: $FN_DIR" >&2; exit 2; }
[ -d "$EXPECTED_DIR" ] || { echo "FAIL: expected-output dir missing: $EXPECTED_DIR" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this suite" >&2; exit 2; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-fetch-normalize.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# Canonicalize a normalized candidate array into a single deterministic line: sort the array by
# the union of fields that disambiguate both record families (review records and ci-check-failure
# records) and sort object keys (-S). Ordering noise across families or surfaces can never flake
# the comparison. An empty array canonicalizes to "[]".
canon() {
  jq -S -c 'sort_by((.databaseId // -1), (.url // ""), (.thread_id // ""), (.name // ""), (.surface // ""), (.classification // ""), (.item_source // ""))'
}

# run_case <case> <review-fixture-abspath> <ci-fixture-abspath|-> <reviewer-filter> <expected-fixture-abspath>
# Feed the review fixture (and optional CI fixture) through the normalize core under the OFFLINE
# test seam, canonicalize stdout, and exact-match against the canonicalized expected fixture.
# OWNER/REPO/PR_NUMBER are left empty (not required under --payload-file); SELF_LOGIN is fixed to
# "selfuser" to match the reused fix-history fixtures. A nonzero exit or empty/mismatched output
# fails the case loudly.
run_case() {
  local case_name="$1" review_fix="$2" ci_fix="$3" filt="$4" expected_fix="$5"
  if [ ! -f "$review_fix" ]; then failed "$case_name" "review fixture missing: $review_fix"; return; fi
  if [ ! -f "$expected_fix" ]; then failed "$case_name" "expected fixture missing: $expected_fix"; return; fi

  local -a ci_args=()
  if [ "$ci_fix" != "-" ]; then
    if [ ! -f "$ci_fix" ]; then failed "$case_name" "ci fixture missing: $ci_fix"; return; fi
    ci_args=(--ci-payload-file "$ci_fix")
  fi

  local expected actual
  if ! expected="$(canon < "$expected_fix")"; then
    failed "$case_name" "could not canonicalize expected fixture $expected_fix"
    return
  fi
  # The normalize core fails non-zero ONLY on a live-fetch path; under --payload-file it always
  # exits 0 (fail-open). A nonzero here is a real regression — surface it.
  if ! actual="$(bash "$NORMALIZE" --payload-file "$review_fix" "${ci_args[@]}" -- "" "" "" "$filt" selfuser 2>/dev/null | canon)"; then
    failed "$case_name" "normalize core failed on $review_fix (ci=$ci_fix filter=$filt)"
    return
  fi
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "($(basename "$review_fix") ci=$(basename "$ci_fix") filter=$filt)"
  else
    failed "$case_name" "($(basename "$review_fix") ci=$(basename "$ci_fix") filter=$filt)
    expected: $expected
    actual:   $actual"
  fi
}

# stderr_contains <case> <review-fixture> <needle> <present|absent>
# Run the normalize core capturing ONLY stderr, and assert the needle is present or absent. Used to
# verify the connection-tripwire OVERFLOW diagnostic fires on a >50 totalCount and stays silent
# otherwise (the diagnostic is the consumer's fail-open signal; stdout candidates are unaffected).
stderr_contains() {
  local case_name="$1" review_fix="$2" needle="$3" mode="$4"
  if [ ! -f "$review_fix" ]; then failed "$case_name" "review fixture missing: $review_fix"; return; fi
  local err
  err="$(bash "$NORMALIZE" --payload-file "$review_fix" -- "" "" "" all selfuser 2>&1 1>/dev/null)"
  case "$mode" in
    present)
      if printf '%s' "$err" | grep -q "$needle"; then
        pass "$case_name" "stderr contains '$needle'"
      else
        failed "$case_name" "stderr MISSING '$needle' (got: $err)"
      fi ;;
    absent)
      if printf '%s' "$err" | grep -q "$needle"; then
        failed "$case_name" "stderr UNEXPECTEDLY contains '$needle' (got: $err)"
      else
        pass "$case_name" "stderr free of '$needle'"
      fi ;;
    *) failed "$case_name" "bad stderr_contains mode: $mode" ;;
  esac
}

# stderr_exact <case> <review-fixture> <expected-full-stderr-line>
# Like stderr_contains but EXACT-MATCHES the full stderr line, not a substring needle. The OVERFLOW
# diagnostic IS the consumer's fail-open signal and its exact counter payload (reviewThreads/comments/
# reviews) is a behavior-preservation requirement: a bare "OVERFLOW" needle would still pass if a
# refactor dropped/garbled the counter values or weakened the wording. This locks the whole line.
stderr_exact() {
  local case_name="$1" review_fix="$2" expected="$3"
  if [ ! -f "$review_fix" ]; then failed "$case_name" "review fixture missing: $review_fix"; return; fi
  local err
  err="$(bash "$NORMALIZE" --payload-file "$review_fix" -- "" "" "" all selfuser 2>&1 1>/dev/null)"
  if [ "$err" = "$expected" ]; then
    pass "$case_name" "stderr exact-matches full diagnostic line"
  else
    failed "$case_name" "stderr diagnostic mismatch
    expected: $expected
    actual:   $err"
  fi
}

# union_order <case> <review-fixture> <ci-fixture> <expected-item_source-json>
# Assert the RAW (un-canonicalized) item_source sequence of the normalized array. run_case
# canonicalizes via `canon` (sort_by), which by design erases element order — so it can NOT catch a
# regression that REVERSES the union (ci records emitted before review records). The contract is
# explicit: review-surface records FIRST, then ci-check-failure records. This locks that order through
# the full entrypoint seam, complementing run_case (which still guards the canonical value).
union_order() {
  local case_name="$1" review_fix="$2" ci_fix="$3" expected="$4"
  if [ ! -f "$review_fix" ]; then failed "$case_name" "review fixture missing: $review_fix"; return; fi
  if [ ! -f "$ci_fix" ]; then failed "$case_name" "ci fixture missing: $ci_fix"; return; fi
  local actual
  actual="$(bash "$NORMALIZE" --payload-file "$review_fix" --ci-payload-file "$ci_fix" -- "" "" "" all selfuser 2>/dev/null \
    | jq -c '[.[].item_source]')"
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "RAW union item_source order is $expected"
  else
    failed "$case_name" "union order mismatch
    expected: $expected
    actual:   $actual"
  fi
}

# run_fail_case <case> <expected-reason> <arg...>
# Run the normalize core with the given raw args, capturing stdout + exit code WITHOUT a pipe (so
# the script's own exit status is observed, not a downstream filter's). Assert the script exited
# NON-ZERO and that stdout carries the single `FETCHNORM_ERROR=<expected-reason>` line. This is the
# fail-CLOSED asserter: it locks the RS-001 structural guarantee that a live-fetch / input error
# surfaces as exit 1 + a FETCHNORM_ERROR marker rather than being silently swallowed (the original
# #203 bug). Distinct from run_case, which treats any non-zero exit as a regression.
run_fail_case() {
  local case_name="$1" expected_reason="$2"; shift 2
  local out status
  out="$(bash "$NORMALIZE" "$@" 2>/dev/null)"
  status=$?
  if [ "$status" -eq 0 ]; then
    failed "$case_name" "expected NON-ZERO exit, got 0 (stdout: $out)"
    return
  fi
  if printf '%s\n' "$out" | grep -q "^FETCHNORM_ERROR=$expected_reason$"; then
    pass "$case_name" "exit=$status FETCHNORM_ERROR=$expected_reason"
  else
    failed "$case_name" "exit=$status but stdout missing 'FETCHNORM_ERROR=$expected_reason' (got: $out)"
  fi
}

# run_failopen_case <case> <review-fixture-abspath> <ci-fixture-abspath|-> <expected-fixture-abspath>
# Like run_case, but ALSO asserts the script exited 0 explicitly (run_case pipes stdout into canon,
# so the script's own exit status is masked by canon's). This locks the PRESERVED fail-OPEN
# guarantee: a malformed / empty / non-array injected payload yields the expected (usually empty)
# candidate set AND exit 0 — never an error. Captures stdout + status WITHOUT a pipe, then
# canonicalizes the captured buffer.
run_failopen_case() {
  local case_name="$1" review_fix="$2" ci_fix="$3" expected_fix="$4"
  if [ ! -f "$review_fix" ]; then failed "$case_name" "review fixture missing: $review_fix"; return; fi
  if [ ! -f "$expected_fix" ]; then failed "$case_name" "expected fixture missing: $expected_fix"; return; fi

  local -a ci_args=()
  if [ "$ci_fix" != "-" ]; then
    if [ ! -f "$ci_fix" ]; then failed "$case_name" "ci fixture missing: $ci_fix"; return; fi
    ci_args=(--ci-payload-file "$ci_fix")
  fi

  local raw status expected actual
  raw="$(bash "$NORMALIZE" --payload-file "$review_fix" "${ci_args[@]}" -- "" "" "" all selfuser 2>/dev/null)"
  status=$?
  if [ "$status" -ne 0 ]; then
    failed "$case_name" "expected exit 0 (fail-open), got $status (stdout: $raw)"
    return
  fi
  if ! expected="$(canon < "$expected_fix")"; then
    failed "$case_name" "could not canonicalize expected fixture $expected_fix"
    return
  fi
  actual="$(printf '%s' "$raw" | canon)"
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "(exit=0 $(basename "$review_fix") ci=$(basename "$ci_fix"))"
  else
    failed "$case_name" "($(basename "$review_fix") ci=$(basename "$ci_fix"))
    expected: $expected
    actual:   $actual"
  fi
}

# ── Review surfaces ───────────────────────────────────────────────────────────────
# thread surface, handled classification: a thread comment carrying a `Fixed in <sha>.` marker
# normalizes to one review record, item_source review, classification handled.
run_case "review:thread-handled" \
  "$FIX_HISTORY_DIR/case01-handled-by-marker.json" - all \
  "$EXPECTED_DIR/review-thread-handled.json"

# thread surface, handled + followup-after-fix in one thread: a comment predating the self
# fix-reply -> handled; a comment post-dating it -> followup-after-fix. Exercises both branches.
run_case "review:thread-followup-after-fix" \
  "$FIX_HISTORY_DIR/case03-followup-after-fix.json" - all \
  "$EXPECTED_DIR/review-thread-followup.json"

# toplevel surface: an addressed (self `Addresses:` url) top-level comment -> handled; the
# unaddressed one -> actionable.
run_case "review:toplevel" \
  "$FIX_HISTORY_DIR/case06-toplevel-addressed.json" - all \
  "$EXPECTED_DIR/review-toplevel.json"

# review surface: CHANGES_REQUESTED/COMMENTED summaries -> actionable; an addressed
# CHANGES_REQUESTED -> handled; APPROVED/DISMISSED emit nothing.
run_case "review:summary" \
  "$FIX_HISTORY_DIR/case07-review-summary.json" - all \
  "$EXPECTED_DIR/review-summary.json"

# ── Thread-overflow sentinel pass-through ─────────────────────────────────────────
# An overflowed unresolved thread emits BOTH the per-comment record AND the thread-overflow
# SENTINEL (id:null, databaseId:null, thread_id non-null). The sentinel passes through with only
# item_source added — never collapsed or reinterpreted.
run_case "overflow-sentinel:passthrough" \
  "$FIX_HISTORY_DIR/case05-thread-overflow.json" - all \
  "$EXPECTED_DIR/review-thread-overflow.json"

# Overflowed thread whose only visible node is self-authored: the per-comment loop emits nothing,
# so the stream is EXACTLY the thread-overflow sentinel (id:null, databaseId:null, thread_id
# non-null) — the overflow actionable signal is never silently lost.
run_case "overflow-sentinel:no-visible-match" \
  "$FIX_HISTORY_DIR/case10-thread-overflow-no-visible-match.json" - all \
  "$EXPECTED_DIR/review-overflow-no-visible.json"

# ── Connection-tripwire / >50-node fail-open (one per axis) ───────────────────────
# Each axis (reviewThreads / comments / reviews) with totalCount 51 must (a) preserve the in-page
# candidate on stdout and (b) emit the OVERFLOW diagnostic on stderr so the consumer fails open.
run_case "tripwire:threads-stdout" \
  "$FN_DIR/overflow-threads.json" - all \
  "$EXPECTED_DIR/overflow-threads.json"
stderr_contains "tripwire:threads-stderr" "$FN_DIR/overflow-threads.json" "OVERFLOW" present
# Full diagnostic-text lock: assert the WHOLE stderr line incl. the exact counter payload
# (reviewThreads=51 comments=0 reviews=0), not just the bare "OVERFLOW" needle above.
stderr_exact "tripwire:threads-stderr-full" "$FN_DIR/overflow-threads.json" \
  'github-review-loop: OVERFLOW one or more connection totalCounts exceed 50 (reviewThreads=51 comments=0 reviews=0); in-page classification is untrustworthy on the overflowed axis — the consumer must fail open (DISPATCH) per its >50 tripwire.'

run_case "tripwire:comments-stdout" \
  "$FN_DIR/overflow-comments.json" - all \
  "$EXPECTED_DIR/overflow-comments.json"
stderr_contains "tripwire:comments-stderr" "$FN_DIR/overflow-comments.json" "OVERFLOW" present

run_case "tripwire:reviews-stdout" \
  "$FN_DIR/overflow-reviews.json" - all \
  "$EXPECTED_DIR/overflow-reviews.json"
stderr_contains "tripwire:reviews-stderr" "$FN_DIR/overflow-reviews.json" "OVERFLOW" present

# Control: a payload with all totalCounts <= 50 emits NO OVERFLOW diagnostic.
stderr_contains "tripwire:no-overflow-control" "$FIX_HISTORY_DIR/case01-handled-by-marker.json" "OVERFLOW" absent

# Read-only-FS regression (iter-4): the overflow tripwire must NOT depend on a
# writable TMPDIR. The original here-doc-fed `while read` loop required bash to
# create a here-doc temp file; on a read-only filesystem that create fails, the
# loop never runs, the counters stay 0, and a real >50 overflow is silently lost
# (exit 0). This case points TMPDIR at an unwritable, non-existent path so any
# temp-file creation would fail, then asserts the OVERFLOW diagnostic STILL fires
# — locking the temp-file-free (command-substitution) overflow read.
stderr_contains_unwritable_tmp() {
  local case_name="$1" review_fix="$2" needle="$3"
  if [ ! -f "$review_fix" ]; then failed "$case_name" "review fixture missing: $review_fix"; return; fi
  local err
  err="$(TMPDIR=/nonexistent-readonly-tmpdir-$$/cannot-create \
    bash "$NORMALIZE" --payload-file "$review_fix" -- "" "" "" all selfuser 2>&1 1>/dev/null)"
  if printf '%s' "$err" | grep -q "$needle"; then
    pass "$case_name" "stderr contains '$needle' with unwritable TMPDIR"
  else
    failed "$case_name" "stderr MISSING '$needle' with unwritable TMPDIR (got: $err)"
  fi
}
stderr_contains_unwritable_tmp "tripwire:threads-stderr-readonly-tmp" \
  "$FN_DIR/overflow-threads.json" "OVERFLOW"

# ── CI-check candidate injection ──────────────────────────────────────────────────
# An empty review payload + a `gh pr checks --json bucket,name,description,link,state,workflow`
# array yields ONLY the bucket==fail checks as ci-check-failure records (id ALWAYS null);
# pass/pending checks are dropped.
run_case "ci:injection-only" \
  "$FN_DIR/empty-review.json" "$FN_DIR/ci-checks.json" all \
  "$EXPECTED_DIR/ci-only.json"

# Union: review records AND ci-check-failure records coexist in the one normalized array.
run_case "ci:union-with-review" \
  "$FIX_HISTORY_DIR/case01-handled-by-marker.json" "$FN_DIR/ci-checks.json" all \
  "$EXPECTED_DIR/review-plus-ci.json"
# ORDER-SENSITIVE union lock: run_case above canonicalizes (sort_by), erasing element order. Assert
# the RAW item_source sequence so a reversed union (ci-before-review) is caught — review records FIRST.
union_order "ci:union-order-review-then-ci" \
  "$FIX_HISTORY_DIR/case01-handled-by-marker.json" "$FN_DIR/ci-checks.json" \
  '["review","ci-check-failure","ci-check-failure"]'

# ── Empty / malformed payload CONTENT -> [] + explicit exit 0 (PRESERVED fail-open) ─
# RS-001 hardened the LIVE-fetch / input-error path to fail CLOSED, but the malformed/empty injected
# CONTENT path MUST stay fail-OPEN. run_failopen_case asserts BOTH the empty array AND exit 0
# explicitly (run_case's pipe to canon masks the script's own exit status). This locks the
# behavior-preserving boundary: bad payload CONTENT is "nothing classified", never an error.
run_failopen_case "empty:no-records" \
  "$FN_DIR/empty-review.json" - \
  "$EXPECTED_DIR/empty.json"

run_failopen_case "malformed:fail-open" \
  "$FN_DIR/malformed.json" - \
  "$EXPECTED_DIR/empty-malformed.json"

# A non-array CI payload fed through the OFFLINE --ci-payload-file seam fails OPEN: the ci_records
# jq projects `if type=="array" then .[] else empty end`, so a non-array CI payload contributes ZERO
# CI candidates and the script exits 0. (The ci-checks-failed REJECTION lives ONLY in the LIVE
# fetch_ci_payload path, which --ci-payload-file bypasses — see report limitation note.)
run_failopen_case "ci:non-array-fail-open" \
  "$FN_DIR/empty-review.json" "$FN_DIR/ci-non-array.json" \
  "$EXPECTED_DIR/empty.json"

# ── Fail-CLOSED cluster lock (RS-001 structural fix regression guard) ──────────────
# Each case drives a live-fetch / input error through the OFFLINE seam and asserts the net observable
# RS-001 guarantees: exit NON-ZERO + a single `FETCHNORM_ERROR=<reason>` line on stdout. Before
# RS-001 these were silently swallowed (the original #203 bug); these cases ensure that can never
# regress.

# Nonexistent --payload-file: the clearest reproduction of the original bug now failing correctly.
# A path that does not exist trips read_payload_source's regular-file guard. No fixture needed.
run_fail_case "fail-closed:payload-file-not-found" "payload-file-not-found" \
  --payload-file "$FN_DIR/__does-not-exist__.json" -- "" "" "" all selfuser

# Empty inline --payload-file= : rejected as an input error, NOT silently re-routed to live GraphQL.
run_fail_case "fail-closed:empty-inline-payload-file" "missing-value-for-payload-file" \
  --payload-file= -- "" "" "" all selfuser

# Empty inline --ci-payload-file= : same input-error rejection on the CI seam.
run_fail_case "fail-closed:empty-inline-ci-payload-file" "missing-value-for-ci-payload-file" \
  --payload-file "$FN_DIR/empty-review.json" --ci-payload-file= -- "" "" "" all selfuser

# ── Live-response gate (RS2-001) — driven OFFLINE via the FETCHNORM_LIVE_* seam ────
# DISTINCT from --payload-file (which BYPASSES the live path + gate). These cases set the
# FETCHNORM_LIVE_GRAPHQL_FILE/STATUS and/or FETCHNORM_LIVE_CI_FILE/STATUS env vars for a SINGLE
# invocation (via `env VAR=...`, so nothing leaks into sibling cases), feeding a raw live response
# + simulated gh exit status THROUGH validate_live_response exactly as a real fetch would. No real
# gh / network is touched. The live helpers require OWNER/REPO/PR positionals are present for the
# non-seam branch, but the seam SHORT-CIRCUITS that — we still pass placeholder "o r 5" positionals
# so the offline run never hits the OWNER guard ordering (the seam is checked first).

# run_live_fail_case <case> <expected-reason> <env-assignment...> -- <arg...>
# Run the normalize core with the FETCHNORM_LIVE_* env vars set ONLY for this invocation and assert
# the fail-CLOSED contract: NON-ZERO exit + a single `FETCHNORM_ERROR=<reason>` line on stdout. The
# `--` separates the leading `VAR=value` env assignments from the script's positional/flag args.
# This locks the RS2-001 live-response gate: an exit-0 operational failure (errors array / null
# pullRequest / empty body) or a non-allowlisted CI exit must surface as an error, never zero
# candidates.
run_live_fail_case() {
  local case_name="$1" expected_reason="$2"; shift 2
  local -a env_assign=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do env_assign+=("$1"); shift; done
  shift  # drop the "--"
  # STEP-001 gate: the live seam activates ONLY when FETCHNORM_TEST_MODE=1 is ALSO
  # set alongside the FETCHNORM_LIVE_*_FILE var. Inject it once here so every
  # live-seam case routes through validate_live_response instead of going live.
  env_assign+=("FETCHNORM_TEST_MODE=1")
  local out status
  out="$(env "${env_assign[@]}" bash "$NORMALIZE" "$@" 2>/dev/null)"
  status=$?
  if [ "$status" -eq 0 ]; then
    failed "$case_name" "expected NON-ZERO exit, got 0 (stdout: $out)"
    return
  fi
  if printf '%s\n' "$out" | grep -q "^FETCHNORM_ERROR=$expected_reason$"; then
    pass "$case_name" "exit=$status FETCHNORM_ERROR=$expected_reason"
  else
    failed "$case_name" "exit=$status but stdout missing 'FETCHNORM_ERROR=$expected_reason' (got: $out)"
  fi
}

# run_live_failopen_case <case> <expected-fixture-abspath> <env-assignment...> -- <arg...>
# Run with the FETCHNORM_LIVE_* env vars set ONLY for this invocation and assert the fail-OPEN
# guarantee: exit 0 + the canonicalized candidate array equals the expected fixture. Proves the gate
# does NOT over-reject a valid-but-empty live response, that a passing/failing CI exit yields the
# right candidate set, and (via the no-env variant) that injected content bypasses the gate. Captures
# stdout + status WITHOUT a pipe, then canonicalizes the buffer (mirrors run_failopen_case).
run_live_failopen_case() {
  local case_name="$1" expected_fix="$2"; shift 2
  local -a env_assign=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do env_assign+=("$1"); shift; done
  shift  # drop the "--"
  # STEP-001 gate: the live seam activates ONLY when FETCHNORM_TEST_MODE=1 is ALSO
  # set alongside the FETCHNORM_LIVE_*_FILE var. Inject it once here so every
  # live-seam case routes through validate_live_response instead of going live.
  env_assign+=("FETCHNORM_TEST_MODE=1")
  if [ ! -f "$expected_fix" ]; then failed "$case_name" "expected fixture missing: $expected_fix"; return; fi
  local raw status expected actual
  raw="$(env "${env_assign[@]}" bash "$NORMALIZE" "$@" 2>/dev/null)"
  status=$?
  if [ "$status" -ne 0 ]; then
    failed "$case_name" "expected exit 0 (fail-open), got $status (stdout: $raw)"
    return
  fi
  if ! expected="$(canon < "$expected_fix")"; then
    failed "$case_name" "could not canonicalize expected fixture $expected_fix"
    return
  fi
  actual="$(printf '%s' "$raw" | canon)"
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "(exit=0 $(basename "$expected_fix"))"
  else
    failed "$case_name" "($case_name)
    expected: $expected
    actual:   $actual"
  fi
}

# Fail-CLOSED via the GraphQL live seam (FETCHNORM_LIVE_GRAPHQL_FILE/STATUS). Each pairs a passing CI
# seam ([] @ status 0) so the live CI fetch is also short-circuited offline — the GraphQL gate is the
# subject under test and must fire before CI is even consulted.
# 1. non-empty .errors at status 0 -> graphql-errors.
run_live_fail_case "live-closed:graphql-errors" "graphql-errors" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-errors.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 2. null/absent .data.repository.pullRequest at status 0 -> graphql-null-pullrequest.
run_live_fail_case "live-closed:graphql-null-pullrequest" "graphql-null-pullrequest" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-null-pr.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 3. empty/whitespace body at status 0 -> graphql-empty-body.
run_live_fail_case "live-closed:graphql-empty-body" "graphql-empty-body" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-empty.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 4. EDGE: .errors populated AND a present pullRequest at status 0 -> graphql-errors (errors overrides
#    presence — the operational-failure signal wins).
run_live_fail_case "live-closed:graphql-errors-override-presence" "graphql-errors" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-errors-with-pr.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# Connection-shape gate (#322). Each fixture carries a NON-NULL pullRequest and NO .errors, so it
# clears the three earlier checks and isolates the connection-shape assertion. Before this gate a
# response that parsed but had LOST its connection nodes normalized to an empty candidate set —
# indistinguishable from a genuinely clean PR, which lost a real finding in production.
# 4b. a REQUESTED top-level connection key ABSENT entirely -> graphql-missing-connection.
run_live_fail_case "live-closed:graphql-absent-connection" "graphql-missing-connection" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-absent-connection.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 4c. a present connection whose `nodes` is NULL -> graphql-missing-connection (has() would accept
#     this shape; the `type == "array"` assertion is strictly stronger).
run_live_fail_case "live-closed:graphql-null-nodes" "graphql-missing-connection" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-null-nodes.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 4d. FIELD-REPORT REPRODUCTION: top-level connections all intact, but an UNRESOLVED reviewThreads
#     node's NESTED `comments` key is ABSENT -> graphql-missing-connection. This is the exact shape
#     that lost a real finding; the nested per-thread clause is what catches it.
run_live_fail_case "live-closed:graphql-absent-thread-comments" "graphql-missing-connection" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-absent-thread-comments.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# Shared envelope validator (#393, _shared/graphql-response.sh). gh exits 0 for these error
# envelopes, so each must fail closed on content. The two errors fixtures carry a VALID empty
# pullRequest, so only the envelope check can reject them.
# 4e. `.errors` array whose element has no `message` -> graphql-errors.
run_live_fail_case "live-closed:graphql-errors-no-message" "graphql-errors" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-errors-no-message.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 4f. `.errors` is an OBJECT, not an array -> graphql-errors. The prior array-length check read an
#     empty object as length 0 and passed it through to [].
run_live_fail_case "live-closed:graphql-errors-object" "graphql-errors" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-errors-object.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 4g. non-JSON body at status 0 -> graphql-malformed.
run_live_fail_case "live-closed:graphql-malformed" "graphql-malformed" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-malformed.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 4h. `.data` null with no `.errors` -> graphql-missing-data.
run_live_fail_case "live-closed:graphql-null-data" "graphql-missing-data" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-null-data.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser

# Fail-CLOSED via the CI live seam (FETCHNORM_LIVE_CI_FILE/STATUS). Each pairs a VALID empty GraphQL
# seam (present pullRequest, zero connections @ status 0) so the GraphQL gate passes and the CI gate
# is the subject under test.
# 5. valid JSON array but STATUS=4 (auth) -> ci-operational-failure (the F5 shape-only-trust bug edge:
#    a non-allowlisted exit fails closed EVEN WITH a valid array body).
run_live_fail_case "live-closed:ci-auth4-with-array" "ci-operational-failure" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-valid-empty.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-array.json" "FETCHNORM_LIVE_CI_STATUS=4" \
  -- o r 5 all selfuser
# 6. STATUS=2 (cancelled) with [] -> ci-operational-failure (non-allowlisted exit, even with an empty
#    array body).
run_live_fail_case "live-closed:ci-cancelled2-with-empty" "ci-operational-failure" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-valid-empty.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=2" \
  -- o r 5 all selfuser
# 7. STATUS=8 (pending — allowlisted) with a NON-array body -> ci-not-array (an allowlisted failing/
#    pending exit must still carry the JSON array).
run_live_fail_case "live-closed:ci-pending8-non-array" "ci-not-array" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-valid-empty.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-non-array.json" "FETCHNORM_LIVE_CI_STATUS=8" \
  -- o r 5 all selfuser
# 7b. STATUS=0 (success — allowlisted) with a NON-array body -> ci-not-array (uniform parse: ALL
#     allowlisted statuses 0/1/8 must carry a JSON array; a non-array at exit 0 fails closed).
run_live_fail_case "live-closed:ci-status0-non-array" "ci-not-array" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-valid-empty.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-non-array.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 8. seam file unreadable -> live-seam-file-not-found (an explicitly-set seam path that does not exist
#    is an input error, distinct from the fail-open empty path).
run_live_fail_case "live-closed:seam-file-not-found" "live-seam-file-not-found" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/__live-seam-missing__.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  -- o r 5 all selfuser

# Fail-OPEN guards (exit 0). Prove the gate does NOT over-reject valid responses.
# 9. valid live GraphQL, present pullRequest, ZERO connections @ status 0 -> [] exit 0 (paired with a
#    passing CI seam so the whole live path is offline). Gate must accept valid-but-empty.
run_live_failopen_case "live-open:graphql-valid-empty" \
  "$EXPECTED_DIR/live-graphql-valid-empty.json" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-valid-empty.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 10. CI STATUS=0 with [] -> zero CI candidates, exit 0.
run_live_failopen_case "live-open:ci-empty-status0" \
  "$EXPECTED_DIR/live-ci-empty.json" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-valid-empty.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 11. CI STATUS=1 (failing — allowlisted) with a real array of failing check objects -> emits the CI
#     candidate(s), exit 0 (the genuine failing-CI path stays intact through the gate).
run_live_failopen_case "live-open:ci-failing-status1" \
  "$EXPECTED_DIR/live-ci-failing.json" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-valid-empty.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-array.json" "FETCHNORM_LIVE_CI_STATUS=1" \
  -- o r 5 all selfuser
# Connection-shape gate must NOT over-reject (#322). Both shapes below are legitimate live responses.
# 11b. every requested connection PRESENT but EMPTY (`nodes: []`, including `reviewThreads.nodes: []`,
#      on which the nested per-thread clause is vacuously true) -> [] exit 0. A genuinely clean PR
#      still passes.
run_live_failopen_case "live-open:graphql-connections-present-empty" \
  "$EXPECTED_DIR/live-graphql-valid-empty.json" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FN_DIR/live-graphql-valid-empty.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser
# 11c. every requested connection PRESENT and POPULATED — incl. a reviewThreads node with a real
#      nested `comments` connection -> the thread candidate survives the gate, exit 0.
run_live_failopen_case "live-open:graphql-connections-populated" \
  "$EXPECTED_DIR/review-thread-handled.json" \
  "FETCHNORM_LIVE_GRAPHQL_FILE=$FIX_HISTORY_DIR/case01-handled-by-marker.json" "FETCHNORM_LIVE_GRAPHQL_STATUS=0" \
  "FETCHNORM_LIVE_CI_FILE=$FN_DIR/live-ci-empty.json" "FETCHNORM_LIVE_CI_STATUS=0" \
  -- o r 5 all selfuser

# ── Live-vs-injected divergence lock (the critical boundary assertion) ──────────────
# 12. A --payload-file fixture whose body carries a non-empty .errors array, with NO live seam env
#     vars set, STILL yields [] exit 0: injected content is TRUSTED and bypasses validate_live_response
#     entirely. The SAME body shape, were it a LIVE response, would fail closed as graphql-errors
#     (case 1) — this proves the deliberate live=validated / injected=trusted divergence. No env vars,
#     so it runs through run_failopen_case's existing --payload-file path.
run_failopen_case "injected-bypass:errors-array-trusted" \
  "$FN_DIR/injected-graphql-with-errors.json" - \
  "$EXPECTED_DIR/injected-errors-bypass.json"

# ── Fail-closed gate lock: LIVE_*_FILE WITHOUT TEST_MODE does NOT divert ───────────
# STEP-001 made the live seam require BOTH FETCHNORM_TEST_MODE=1 AND the
# FETCHNORM_LIVE_*_FILE var. A stray *_FILE ALONE must no longer divert — the fetch
# goes LIVE. We point the GraphQL seam file at the SAME errors fixture case 1 uses
# (which, were the seam active, would fail closed as graphql-errors), but DELIBERATELY
# OMIT FETCHNORM_TEST_MODE and supply NO OWNER/REPO/PR positionals. With the seam
# inactive the code falls through to the live path and trips the OWNER guard FIRST —
# so the reason is `missing-owner`, NOT `graphql-errors`. That the fixture's
# graphql-errors signal is NEVER produced proves the seam file was never read.
nodivert_out="$(FETCHNORM_LIVE_GRAPHQL_FILE="$FN_DIR/live-graphql-errors.json" \
  bash "$NORMALIZE" -- "" "" "" all selfuser 2>/dev/null)"
nodivert_status=$?
if [ "$nodivert_status" -ne 0 ] \
   && printf '%s\n' "$nodivert_out" | grep -q '^FETCHNORM_ERROR=missing-owner$' \
   && ! printf '%s\n' "$nodivert_out" | grep -q '^FETCHNORM_ERROR=graphql-errors$'; then
  pass "fail-closed:live-file-without-testmode-no-divert" \
    "LIVE_GRAPHQL_FILE alone did NOT divert (missing-owner from live path, fixture unread)"
else
  failed "fail-closed:live-file-without-testmode-no-divert" \
    "seam diverted WITHOUT TEST_MODE — status=$nodivert_status out=$nodivert_out"
fi

# ── reviewer_filter scoping ───────────────────────────────────────────────────────
# case09: codex-only matches ONLY the Bot-typed chatgpt-codex-connector (900). all matches any
# non-self author (900 + the User-typed human reviewer 901). An empty filter slot defaults to
# automated, which on case09 admits only the Bot-typed codex record (900).
run_case "filter:codex-only" \
  "$FIX_HISTORY_DIR/case09-reviewer-filter.json" - codex-only \
  "$EXPECTED_DIR/review-filter-codex-only.json"
run_case "filter:all" \
  "$FIX_HISTORY_DIR/case09-reviewer-filter.json" - all \
  "$EXPECTED_DIR/review-filter-all.json"
run_case "filter:default-is-automated" \
  "$FIX_HISTORY_DIR/case09-reviewer-filter.json" - "" \
  "$EXPECTED_DIR/review-filter-default.json"
# case19 carries one author per identity class (registry Bots incl. both Copilot spellings, a human
# User named claude, non-registry Bots dependabot/github-actions, a human, and self). automated
# admits ONLY the four registry Bot records (1900..1903). The empty-slot run on the same payload
# DISCRIMINATES the default: under a codex-only default it would emit 1900 alone.
run_case "filter:automated" \
  "$FIX_HISTORY_DIR/case19-automated-reviewers.json" - automated \
  "$EXPECTED_DIR/review-filter-automated.json"
run_case "filter:default-is-automated-discriminating" \
  "$FIX_HISTORY_DIR/case19-automated-reviewers.json" - "" \
  "$EXPECTED_DIR/review-filter-automated.json"

# ── Identity-module bootstrap fail-closed (missing / unparseable) ─────────────────
# The classifier `include`s reviewer-identity.jq. fetch-normalize.sh checks the module is present
# and compile-probes the classifier BEFORE sourcing the core; without these checks the core's
# fail-open-on-content stderr swallow would turn a broken include into a silent `[]`. Each case runs
# a COPY of the skills tree (fetch-normalize.sh self-locates via BASH_SOURCE, so the copy resolves
# its own siblings), mutates the copied module, and asserts exit 1 + stdout EXACTLY the single
# `FETCHNORM_ERROR=<reason>` line. A pristine-copy control proves the copy itself is faithful.

# copy_skills_tree <dest-dir>
# Copy the two skill dirs fetch-normalize.sh resolves at runtime (its own scripts dir and
# ../../_shared) into <dest-dir>/skills/, preserving the relative layout.
copy_skills_tree() {
  local dest="$1"
  mkdir -p "$dest/skills/github-review-loop" || return 1
  cp -R "$SKILLS_DIR/github-review-loop/scripts" "$dest/skills/github-review-loop/" || return 1
  cp -R "$SKILLS_DIR/_shared" "$dest/skills/" || return 1
}

# remove_identity_module <scripts-dir> — delete the copied module.
remove_identity_module() { rm -f "$1/reviewer-identity.jq"; }

# corrupt_identity_module <scripts-dir> — overwrite the copied module with a syntax error.
corrupt_identity_module() { printf '%s\n' 'def automated_reviewers: [' > "$1/reviewer-identity.jq"; }

# keep_identity_module <scripts-dir> — leave the copy untouched (control).
keep_identity_module() { :; }

# run_tree_case <case> <mutator-fn> <expected-exit> <expected-stdout>
# Copy the skills tree into a fresh scratch dir, apply <mutator-fn> to the copied scripts dir, run
# the COPIED fetch-normalize.sh over case09 with the automated filter, and exact-match exit + stdout.
# A success (expected exit 0) stdout is canonicalized first, so pass a canonicalized expected value.
run_tree_case() {
  local case_name="$1" mutator="$2" expected_status="$3" expected_out="$4"
  local tree="$WORKDIR/$case_name"
  tree="${tree//:/_}"
  if ! copy_skills_tree "$tree"; then failed "$case_name" "could not copy skills tree to $tree"; return; fi
  local copied_scripts="$tree/skills/github-review-loop/scripts"
  if ! "$mutator" "$copied_scripts"; then failed "$case_name" "mutator $mutator failed"; return; fi
  local out status
  out="$(bash "$copied_scripts/fetch-normalize.sh" --payload-file "$FIX_HISTORY_DIR/case09-reviewer-filter.json" \
    -- "" "" "" automated selfuser 2>/dev/null)"
  status=$?
  if [ "$expected_status" -eq 0 ] && [ "$status" -eq 0 ]; then
    out="$(printf '%s' "$out" | canon)"
  fi
  if [ "$status" -eq "$expected_status" ] && [ "$out" = "$expected_out" ]; then
    pass "$case_name" "exit=$status stdout=$out"
  else
    failed "$case_name" "expected exit=$expected_status stdout=$expected_out
    actual:   exit=$status stdout=$out"
  fi
}

run_tree_case "bootstrap:pristine-copy-control" keep_identity_module 0 \
  "$(canon < "$EXPECTED_DIR/review-filter-default.json")"
run_tree_case "fail-closed:missing-identity-module" remove_identity_module 1 \
  "FETCHNORM_ERROR=missing-identity-module"
run_tree_case "fail-closed:unparseable-filter" corrupt_identity_module 1 \
  "FETCHNORM_ERROR=unparseable-filter"

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "fetch-normalize: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
