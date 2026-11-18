#!/usr/bin/env bash
#
# Behavioral unit runner for the triage MECHANISM substrate (triage-backlog skill, STEP-002).
#
# OFFLINE jq/bash TEST — CI-runnable with ONLY jq + bash present (NO gh / network / auth). It
# drives the pure transform core of:
#   plugin/skills/triage-backlog/scripts/triage-ops.sh
# via its documented offline seam (TRIAGE_OPS_OFFLINE=1 + the injection flags
# --current-labels-file / --response-file / --targets), feeds canned fixtures from
# tests/triage-backlog/, and asserts the emitted JSON equals a golden fixture under
# tests/triage-backlog/expected/. Each transform (triage_palette, compute_mutex_delta,
# build_deps_add_payload, surface_dep_response, normalize_deps_read, list-issues identity) is a
# PURE function of its injected input, so every case is deterministic and offline.
#
# Comparison is canonicalized (object keys sorted via -S, arrays deep-sorted) so jq key/element
# ordering can never flake the match. The palette shape cases assert structural invariants
# (family/value counts = 36 labels, every color a 6-hex string) rather than a frozen golden, so a
# deliberate color re-shade does not falsely fail while a count drift still does.
#
# Mirrors tools/test_fetch_normalize.sh's pass/fail counter + per-case assertion + helper-fn +
# exit-nonzero-on-any-fail + scratch-tmpdir-on-trap conventions. Read-only: the only writes are
# scratch files in a disposable tmpdir removed on EXIT.
#
# Usage:
#   ./tools/test_triage_ops.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
OPS="$REPO_ROOT/plugin/skills/triage-backlog/scripts/triage-ops.sh"
TB_DIR="$REPO_ROOT/tests/triage-backlog"
EXPECTED_DIR="$TB_DIR/expected"

[ -f "$OPS" ] || { echo "FAIL: script under test missing: $OPS" >&2; exit 2; }
[ -d "$TB_DIR" ] || { echo "FAIL: triage-backlog fixture dir missing: $TB_DIR" >&2; exit 2; }
[ -d "$EXPECTED_DIR" ] || { echo "FAIL: expected-output dir missing: $EXPECTED_DIR" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this suite" >&2; exit 2; }

make_scratch_dir TMPDIR_TEST
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# canon: deep-canonicalize one JSON value into a single deterministic line. Sort object keys (-S)
# and recursively sort every array, so neither key order nor array element order can flake an
# exact-match comparison. (The script already `unique`s its delta arrays, but deep-sorting here
# makes the test robust to any future ordering change in the transform.)
canon() {
  jq -S -c '
    def deepsort:
      if type == "array" then map(deepsort) | sort
      elif type == "object" then map_values(deepsort)
      else . end;
    deepsort'
}

# run_case <case> <expected-fixture-abspath> -- <ops-arg...>
# Invoke triage-ops.sh under the OFFLINE seam with the given args, canonicalize stdout, and
# exact-match against the canonicalized expected fixture. A nonzero exit, empty, or mismatched
# output fails the case loudly.
run_case() {
  local case_name="$1" expected_fix="$2"; shift 2
  [ "$1" = "--" ] && shift
  if [ ! -f "$expected_fix" ]; then failed "$case_name" "expected fixture missing: $expected_fix"; return; fi

  local expected actual
  if ! expected="$(canon < "$expected_fix")"; then
    failed "$case_name" "could not canonicalize expected fixture $expected_fix"
    return
  fi
  if ! actual="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" "$@" 2>/dev/null | canon)"; then
    failed "$case_name" "triage-ops failed (args: $*)"
    return
  fi
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "($(basename "$expected_fix"))"
  else
    failed "$case_name" "(args: $*)
    expected: $expected
    actual:   $actual"
  fi
}

# run_exit0_case <case> -- <ops-arg...>
# Like run_case but ONLY asserts the script exited 0 (no pipe masking status). Used to lock the
# cycle-rejection-must-not-crash invariant: a GraphQL cycle response surfaces a warning record AND
# exits 0 so a batch keeps going. Captures status WITHOUT a pipe.
run_exit0_case() {
  local case_name="$1"; shift
  [ "$1" = "--" ] && shift
  local out status
  out="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" "$@" 2>/dev/null)"
  status=$?
  if [ "$status" -eq 0 ]; then
    pass "$case_name" "exit=0 (args: $*)"
  else
    failed "$case_name" "expected exit 0, got $status (args: $*; stdout: $out)"
  fi
}

# run_exit1_case <case> -- <ops-arg...>
# Asserts the script exited NONZERO (fail-closed). Used to lock the deps-add
# fail-closed invariant: a non-cycle GraphQL error, an empty/non-JSON transport
# error, or a malformed-success response MUST surface as nonzero so the caller
# never proceeds as if a dependency edge were written. Captures status WITHOUT a
# pipe so the exit code is the script's own, not jq's.
run_exit1_case() {
  local case_name="$1"; shift
  [ "$1" = "--" ] && shift
  local out status
  out="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" "$@" 2>/dev/null)"
  status=$?
  if [ "$status" -ne 0 ]; then
    pass "$case_name" "exit=$status (args: $*)"
  else
    failed "$case_name" "expected nonzero exit, got 0 (args: $*; stdout: $out)"
  fi
}

# ── Palette shape + idempotence ───────────────────────────────────────────────────
# ensure-labels offline emits the baked palette JSON. Assert the family/value census (36 labels:
# readiness 9, type 8, effort 5, moscow 4, priority/risk/difficulty 3 each, control 1) so a label
# add/drop is caught, and assert every color is a 6-hex string so a malformed color is caught.
PALETTE="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" ensure-labels 2>/dev/null)"

assert_jq() {
  local case_name="$1" filter="$2"
  if printf '%s' "$PALETTE" | jq -e "$filter" >/dev/null 2>&1; then
    pass "$case_name" "$filter"
  else
    failed "$case_name" "palette assertion failed: $filter"
  fi
}

assert_jq "palette:total-36"        'length == 36'
assert_jq "palette:readiness-9"     '[.[] | select(.family=="readiness")] | length == 9'
assert_jq "palette:type-8"          '[.[] | select(.family=="type")] | length == 8'
assert_jq "palette:effort-5"        '[.[] | select(.family=="effort")] | length == 5'
assert_jq "palette:moscow-4"        '[.[] | select(.family=="moscow")] | length == 4'
assert_jq "palette:priority-3"      '[.[] | select(.family=="priority")] | length == 3'
assert_jq "palette:risk-3"          '[.[] | select(.family=="risk")] | length == 3'
assert_jq "palette:difficulty-3"    '[.[] | select(.family=="difficulty")] | length == 3'
assert_jq "palette:control-1"       '[.[] | select(.family=="control")] | length == 1'
assert_jq "palette:color-hex6"      'all(.[]; .color | test("^[0-9a-fA-F]{6}$"))'
# Control label triage:locked is the single human-only unmanaged label — it must exist (ensured)
# but be marked managed:false so the mutex reconcile can never select it.
assert_jq "palette:locked-unmanaged" 'any(.[]; .name=="triage:locked" and .managed==false)'
# Idempotence/determinism: a second offline emit is byte-identical to the first (no nondeterminism).
PALETTE2="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" ensure-labels 2>/dev/null)"
if [ "$(printf '%s' "$PALETTE" | canon)" = "$(printf '%s' "$PALETTE2" | canon)" ]; then
  pass "palette:idempotent-emit" "two emits identical"
else
  failed "palette:idempotent-emit" "two ensure-labels emits diverged"
fi

# ── Per-family mutex delta (remove-all-then-set) ──────────────────────────────────
# A conflicting duplicate (priority:low + priority:medium) with target priority:high: the delta
# REMOVES both stale priority values and ADDS priority:high. Foreign labels (initiative:foo,
# triage:locked) are present in the current set but MUST NOT appear in remove.
run_case "mutex:priority-conflict" "$EXPECTED_DIR/delta-priority-conflict.json" -- \
  apply-labels 7 --targets '{"priority":"high"}' \
  --current-labels-file "$TB_DIR/current-priority-conflict.json"

# ── Idempotent no-op ──────────────────────────────────────────────────────────────
# Current value already equals the target (priority:high): the family contributes NO remove and NO
# add — low-churn stability (already-correct value is not removed-and-re-added).
run_case "mutex:noop-already-correct" "$EXPECTED_DIR/delta-priority-noop.json" -- \
  apply-labels 7 --targets '{"priority":"high"}' \
  --current-labels-file "$TB_DIR/current-priority-noop.json"

# ── Multi-family + foreign-label safety ───────────────────────────────────────────
# Three target families at once; current set carries stale values, an already-correct value
# (readiness:ready), and foreign labels (initiative:alpha, wontfix, custom:thing, triage:locked).
# Golden delta proves: stale priority/type removed, new values added, readiness:ready is a no-op,
# and NO foreign label is in remove.
run_case "mutex:multi-foreign" "$EXPECTED_DIR/delta-multi-foreign.json" -- \
  apply-labels 12 --targets '{"priority":"high","type":"bug","readiness":"ready"}' \
  --current-labels-file "$TB_DIR/current-multi-foreign.json"

# Direct foreign-safety assertion: NO non-family / initiative / triage:locked label may ever be in
# the remove set, across the multi-family delta. Locks the foreign-label + triage:locked invariants
# independently of the golden file.
FOREIGN_DELTA="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" apply-labels 12 \
  --targets '{"priority":"high","type":"bug","readiness":"ready"}' \
  --current-labels-file "$TB_DIR/current-multi-foreign.json" 2>/dev/null)"
if printf '%s' "$FOREIGN_DELTA" | jq -e '
    .remove as $r
    | ([ "initiative:alpha", "wontfix", "custom:thing", "triage:locked" ]
       | all(. as $f | ($r | index($f)) == null))' >/dev/null 2>&1; then
  pass "mutex:foreign-never-removed" "no foreign/locked label in remove set"
else
  failed "mutex:foreign-never-removed" "a foreign or triage:locked label leaked into remove (delta: $FOREIGN_DELTA)"
fi

# ── Foreign label sharing a MANAGED family prefix is never removed ────────────────
# Regression for the palette-bounded remove set: a non-palette label that shares a
# managed family prefix (priority:customer under target priority:high, and
# type:legal-hold) must NOT be scheduled for removal. Only the palette-managed
# stale value (priority:low) is removed. Removing on prefix alone would clobber
# human/project labels — the contract says foreign labels are invisible.
run_case "mutex:foreign-prefix-not-removed" "$EXPECTED_DIR/delta-priority-foreign-prefix.json" -- \
  apply-labels 9 --targets '{"priority":"high"}' \
  --current-labels-file "$TB_DIR/current-priority-foreign-prefix.json"

# ── apply-labels: live path rejects --current-labels-file (security regression) ──
# STEP-R001 fix: a LIVE (non-offline) invocation supplying --current-labels-file MUST
# be rejected fail-closed (exit 2) BEFORE any gh call — the flag is a test seam only.
# Supplying it live would let a caller spoof the label set and bypass triage:locked.
# No TRIAGE_OPS_OFFLINE — this runs in live mode. The die fires before require_gh,
# so no gh dependency and the result is deterministic.
LIVE_STATUS=0
bash "$OPS" apply-labels 9 \
  --current-labels-file "$TB_DIR/current-priority-foreign-prefix.json" \
  --targets '{"priority":"high"}' >/dev/null 2>&1 || LIVE_STATUS=$?
if [ "$LIVE_STATUS" -ne 0 ]; then
  pass "apply-labels:live-current-labels-file-rejected" "exit=$LIVE_STATUS (expected nonzero)"
else
  failed "apply-labels:live-current-labels-file-rejected" "expected nonzero exit, got 0 (live path must reject --current-labels-file)"
fi

# ── list-issues: live path rejects --response-file (security regression) ──────
# STEP-S001 shared guard: a LIVE (non-offline) invocation supplying --response-file
# MUST be rejected fail-closed (exit 2) BEFORE any gh call — the flag is a test seam
# only. No TRIAGE_OPS_OFFLINE — runs in live mode; die fires before require_gh.
LIVE_STATUS=0
bash "$OPS" list-issues \
  --response-file "$TB_DIR/list-issues-response.json" >/dev/null 2>&1 || LIVE_STATUS=$?
if [ "$LIVE_STATUS" -ne 0 ]; then
  pass "list-issues:live-response-file-rejected" "exit=$LIVE_STATUS (expected nonzero)"
else
  failed "list-issues:live-response-file-rejected" "expected nonzero exit, got 0 (live path must reject --response-file)"
fi

# ── deps-read: live path rejects --response-file (security regression) ────────
# STEP-S001 shared guard: a LIVE invocation supplying --response-file MUST be
# rejected fail-closed (exit 2) BEFORE any gh call.
LIVE_STATUS=0
bash "$OPS" deps-read 5 \
  --response-file "$TB_DIR/deps-read-response.json" >/dev/null 2>&1 || LIVE_STATUS=$?
if [ "$LIVE_STATUS" -ne 0 ]; then
  pass "deps-read:live-response-file-rejected" "exit=$LIVE_STATUS (expected nonzero)"
else
  failed "deps-read:live-response-file-rejected" "expected nonzero exit, got 0 (live path must reject --response-file)"
fi

# ── deps-add: live path rejects --response-file (security regression) ─────────
# STEP-S001 shared guard: a LIVE invocation supplying --response-file MUST be
# rejected fail-closed (exit 2) BEFORE the live addBlockedBy mutation.
LIVE_STATUS=0
bash "$OPS" deps-add --issue-id I_a --blocked-by-id I_b \
  --response-file "$TB_DIR/deps-add-cycle-response.json" >/dev/null 2>&1 || LIVE_STATUS=$?
if [ "$LIVE_STATUS" -ne 0 ]; then
  pass "deps-add:live-response-file-rejected" "exit=$LIVE_STATUS (expected nonzero)"
else
  failed "deps-add:live-response-file-rejected" "expected nonzero exit, got 0 (live path must reject --response-file)"
fi

# ── deps-add GraphQL payload shape ────────────────────────────────────────────────
# Offline deps-add WITHOUT --response-file builds the GraphQL variables payload. Assert the exact
# variable keys (issueId, blockingIssueId) with node ids passed through as DATA.
run_case "deps-add:payload-shape" "$EXPECTED_DIR/deps-add-payload.json" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb

# Direct key-set assertion: the payload has EXACTLY {issueId, blockingIssueId} — no extra/missing
# variable keys (a drift in the mutation variable contract is caught).
PAYLOAD="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" deps-add --issue-id I_aaa --blocked-by-id I_bbb 2>/dev/null)"
if printf '%s' "$PAYLOAD" | jq -e '(keys | sort) == ["blockingIssueId","issueId"]' >/dev/null 2>&1; then
  pass "deps-add:payload-key-set" "keys == issueId + blockingIssueId"
else
  failed "deps-add:payload-key-set" "unexpected payload key set (payload: $PAYLOAD)"
fi

# ── Cycle-rejection surfacing (must not crash) ────────────────────────────────────
# A canned GraphQL cycle-rejection response via --response-file surfaces a structured WARNING record
# (status warning, kind cycle-rejected) AND the script exits 0 — a rejected dependency never crashes
# the batch.
run_case "deps-add:cycle-surface" "$EXPECTED_DIR/deps-add-cycle.json" -- \
  deps-add --response-file "$TB_DIR/deps-add-cycle-response.json"
run_exit0_case "deps-add:cycle-exit0" -- \
  deps-add --response-file "$TB_DIR/deps-add-cycle-response.json"

# ── deps-add FAIL-CLOSED on non-cycle / transport / malformed responses ───────────
# A non-cycle GraphQL error (auth/permission), an empty/non-JSON transport error, and
# a malformed-success body each MUST surface as a NONZERO exit so the caller never
# treats a failed dependency write as handled. Only the cycle rejection above is the
# recoverable exit-0 warning.
run_exit1_case "deps-add:noncycle-error-exit1" -- \
  deps-add --response-file "$TB_DIR/deps-add-noncycle-error-response.json"
run_exit1_case "deps-add:empty-transport-exit1" -- \
  deps-add --response-file "$TB_DIR/deps-add-empty-response.json"
run_exit1_case "deps-add:malformed-success-exit1" -- \
  deps-add --response-file "$TB_DIR/deps-add-malformed-success-response.json"
# Mixed `.errors` array: a cycle error FIRST and a non-cycle (auth/permission)
# error SECOND MUST fail closed — recoverability is decided over the WHOLE array,
# not just .errors[0], so a first-error-only check can no longer mask the failed
# write behind a benign cycle.
run_exit1_case "deps-add:mixed-cycle-noncycle-exit1" -- \
  deps-add --response-file "$TB_DIR/deps-add-mixed-error-response.json"

# ── deps-read normalize + list-issues identity ────────────────────────────────────
# A canned blockedBy GraphQL response normalizes into the stable deps-read schema.
run_case "deps-read:normalize" "$EXPECTED_DIR/deps-read-normalized.json" -- \
  deps-read 5 --response-file "$TB_DIR/deps-read-response.json"

# ── deps-read FAIL-CLOSED on GraphQL error / null-issue responses ──────────────────
# A blockedBy read has NO recoverable failure variant: a 200-with-`.errors`
# body (auth/rate-limit/schema) and a null `.data.repository.issue` each MUST surface
# as a NONZERO exit so the caller never demotes a failed read into an empty "no
# blockers" dependency set and makes triage decisions from corrupted state.
run_exit1_case "deps-read:graphql-error-exit1" -- \
  deps-read 5 --response-file "$TB_DIR/deps-read-graphql-error-response.json"
run_exit1_case "deps-read:null-issue-exit1" -- \
  deps-read 5 --response-file "$TB_DIR/deps-read-null-issue-response.json"
# Field-completeness gate: a 200 body that satisfies the outer shape (issue
# present, nodes is an array) but carries null issue id and null blocker
# id/number/title MUST fail closed — null identifiers would normalize into a
# record that cannot be matched for later deps-add/removal.
run_exit1_case "deps-read:null-fields-exit1" -- \
  deps-read 5 --response-file "$TB_DIR/deps-read-null-fields-response.json"
# Pagination fail-close: the query requests only the first 50 blockers, so a
# response whose blockedBy connection reports `pageInfo.hasNextPage == true` has
# unfetched blockers. Emitting it would normalize as if those blockers do not
# exist (driving bogus re-triage removals / re-adds), so a continued page MUST
# fail closed rather than surface a partial blocker set.
run_exit1_case "deps-read:paginated-exit1" -- \
  deps-read 5 --response-file "$TB_DIR/deps-read-paginated-response.json"

# list-issues offline re-emits the injected response verbatim (identity pass-through).
run_case "list-issues:identity" "$EXPECTED_DIR/list-issues-identity.json" -- \
  list-issues --response-file "$TB_DIR/list-issues-response.json"

# ── list-issues: cap-hit fail-closed ──────────────────────────────────────────────
# STEP-L001: the cap check runs uniformly in BOTH offline and live paths. When the
# injected fixture has EXACTLY --limit rows the subcommand MUST fail closed (nonzero)
# — the cap may have silently truncated the backlog.
# list-issues-response.json has 2 rows; --limit 2 triggers the cap check.
LIST_RESPONSE_TMP="$TMPDIR_TEST/list-response-tmp.json"
cp "$TB_DIR/list-issues-response.json" "$LIST_RESPONSE_TMP"

LIST_STATUS=0
TRIAGE_OPS_OFFLINE=1 bash "$OPS" list-issues \
  --limit 2 --response-file "$LIST_RESPONSE_TMP" >/dev/null 2>&1 || LIST_STATUS=$?
if [ "$LIST_STATUS" -ne 0 ]; then
  pass "list-issues:cap-hit-fail-closed" "exit=$LIST_STATUS (2 rows, --limit 2 triggers cap)"
else
  failed "list-issues:cap-hit-fail-closed" "expected nonzero exit when row_count == limit, got 0"
fi

# ── list-issues: under-cap passthrough ────────────────────────────────────────────
# Fewer rows than --limit: row_count (2) -lt limit (3) → exit 0 passthrough.
LIST_STATUS=0
TRIAGE_OPS_OFFLINE=1 bash "$OPS" list-issues \
  --limit 3 --response-file "$LIST_RESPONSE_TMP" >/dev/null 2>&1 || LIST_STATUS=$?
if [ "$LIST_STATUS" -eq 0 ]; then
  pass "list-issues:under-cap-ok" "exit=0 (2 rows, --limit 3 is under cap)"
else
  failed "list-issues:under-cap-ok" "expected exit 0 when row_count < limit, got $LIST_STATUS"
fi

# ── deps-add: offline locked labels → skipped-locked record, exit 0, no payload ──
# STEP-L001 lock gate: --issue-labels-file with triage:locked present → emits
# {"id":<issue_id>,"status":"skipped-locked"}, exit 0, and NO {issueId,...} payload.
LOCKED_FILE="$TMPDIR_TEST/labels-locked.json"
cp "$TB_DIR/labels-locked.json" "$LOCKED_FILE"

run_case "deps-add:offline-locked-skipped" "$EXPECTED_DIR/deps-add-skipped-locked.json" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb --issue-labels-file "$LOCKED_FILE"

# Lock exit-0 invariant: a locked issue emits the record AND exits 0 (same as apply-labels
# skipped-locked — the batch must keep going, the skip is not an error).
run_exit0_case "deps-add:offline-locked-exit0" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb --issue-labels-file "$LOCKED_FILE"

# No payload emitted when locked: stdout must NOT contain the {issueId,...} payload line.
LOCKED_OUT="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" deps-add \
  --issue-id I_aaa --blocked-by-id I_bbb --issue-labels-file "$LOCKED_FILE" 2>/dev/null)"
if printf '%s' "$LOCKED_OUT" | jq -e 'has("issueId") | not' >/dev/null 2>&1; then
  pass "deps-add:offline-locked-no-payload" "no {issueId} payload emitted when locked"
else
  failed "deps-add:offline-locked-no-payload" "locked path emitted a payload (stdout: $LOCKED_OUT)"
fi

# ── deps-add: offline unlocked labels → payload emitted ───────────────────────────
# STEP-L001: gate only fires on locked sets. An unlocked --issue-labels-file must
# let the flow reach build_deps_add_payload and emit the {issueId,blockingIssueId} line.
UNLOCKED_FILE="$TMPDIR_TEST/labels-unlocked.json"
cp "$TB_DIR/labels-unlocked.json" "$UNLOCKED_FILE"

run_case "deps-add:offline-unlocked-proceeds" "$EXPECTED_DIR/deps-add-payload.json" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb --issue-labels-file "$UNLOCKED_FILE"

# ── deps-add: live path rejects --issue-labels-file (security regression) ─────────
# STEP-L001: in the LIVE path, --issue-labels-file is a test seam and MUST be rejected
# fail-closed (exit 2) BEFORE any gh call — it could spoof the label set and bypass
# triage:locked on the addBlockedBy mutation path.
LIVE_STATUS=0
bash "$OPS" deps-add \
  --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-file "$TB_DIR/labels-locked.json" >/dev/null 2>&1 || LIVE_STATUS=$?
if [ "$LIVE_STATUS" -ne 0 ]; then
  pass "deps-add:live-issue-labels-file-rejected" "exit=$LIVE_STATUS (expected nonzero)"
else
  failed "deps-add:live-issue-labels-file-rejected" "expected nonzero exit, got 0 (live path must reject --issue-labels-file)"
fi

# ── deps-add: lock-read FAIL-CLOSED via --issue-labels-response (N004) ───────────
# The --issue-labels-response seam injects the RAW node(id:) labels GraphQL response
# and routes it through validate_response_shape (the shared kernel). Every malformed
# or error body MUST fail closed: nonzero exit AND no {issueId,...} payload on stdout.
# This proves the kernel guard is closed at the lock-read site in deps-add.

# Case 1: .errors envelope → kernel rejects, nonzero exit, no payload.
LABELS_RESP_ERR_TMP="$TMPDIR_TEST/labels-raw-errors.json"
cp "$TB_DIR/labels-raw-errors.json" "$LABELS_RESP_ERR_TMP"

run_exit1_case "deps-add:lock-read-errors-exit1" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_ERR_TMP"

LOCK_ERR_OUT="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" deps-add \
  --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_ERR_TMP" 2>/dev/null)" || true
if printf '%s' "$LOCK_ERR_OUT" | grep -qF '"issueId"'; then
  failed "deps-add:lock-read-errors-no-payload" "errors body emitted a payload (stdout: $LOCK_ERR_OUT)"
else
  pass "deps-add:lock-read-errors-no-payload" "no {issueId} payload on .errors response"
fi

# Case 2: null .data.node → kernel rejects (malformed-read), nonzero exit, no payload.
LABELS_RESP_NULL_TMP="$TMPDIR_TEST/labels-raw-null-data.json"
cp "$TB_DIR/labels-raw-null-data.json" "$LABELS_RESP_NULL_TMP"

run_exit1_case "deps-add:lock-read-null-node-exit1" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_NULL_TMP"

LOCK_NULL_OUT="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" deps-add \
  --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_NULL_TMP" 2>/dev/null)" || true
if printf '%s' "$LOCK_NULL_OUT" | grep -qF '"issueId"'; then
  failed "deps-add:lock-read-null-node-no-payload" "null-node body emitted a payload (stdout: $LOCK_NULL_OUT)"
else
  pass "deps-add:lock-read-null-node-no-payload" "no {issueId} payload on null-node response"
fi

# Case 3: null label name element → kernel elem_pred fails, nonzero exit, no payload.
LABELS_RESP_NULLELEM_TMP="$TMPDIR_TEST/labels-raw-null-elem.json"
cp "$TB_DIR/labels-raw-null-elem.json" "$LABELS_RESP_NULLELEM_TMP"

run_exit1_case "deps-add:lock-read-null-elem-exit1" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_NULLELEM_TMP"

LOCK_NULLELEM_OUT="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" deps-add \
  --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_NULLELEM_TMP" 2>/dev/null)" || true
if printf '%s' "$LOCK_NULLELEM_OUT" | grep -qF '"issueId"'; then
  failed "deps-add:lock-read-null-elem-no-payload" "null-elem body emitted a payload (stdout: $LOCK_NULLELEM_OUT)"
else
  pass "deps-add:lock-read-null-elem-no-payload" "no {issueId} payload on null-elem response"
fi

# Case 4: continued page (hasNextPage==true) → root_pred fails, nonzero exit, no payload.
# The page-1 nodes do NOT contain triage:locked, proving fail-closed on the pagination
# signal itself rather than on a visible lock.
LABELS_RESP_PAGINATED_TMP="$TMPDIR_TEST/labels-raw-paginated.json"
cp "$TB_DIR/labels-raw-paginated.json" "$LABELS_RESP_PAGINATED_TMP"

run_exit1_case "deps-add:lock-read-paginated-failclosed" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_PAGINATED_TMP"

LOCK_PAGINATED_OUT="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" deps-add \
  --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_PAGINATED_TMP" 2>/dev/null)" || true
if printf '%s' "$LOCK_PAGINATED_OUT" | grep -qF '"issueId"'; then
  failed "deps-add:lock-read-paginated-no-payload" "paginated body emitted a payload (stdout: $LOCK_PAGINATED_OUT)"
else
  pass "deps-add:lock-read-paginated-no-payload" "no {issueId} payload on continued-page response"
fi

# ── deps-add: lock-read CLEAN via --issue-labels-response (N004) ─────────────────
# Proves the kernel passes clean bodies through to the lock gate correctly.

# Case 4: clean raw body WITH triage:locked → skipped-locked record, exit 0, no payload.
LABELS_RESP_LOCKED_TMP="$TMPDIR_TEST/labels-raw-locked.json"
cp "$TB_DIR/labels-raw-locked.json" "$LABELS_RESP_LOCKED_TMP"

run_case "deps-add:lock-read-locked-skipped" "$EXPECTED_DIR/deps-add-skipped-locked.json" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_LOCKED_TMP"

run_exit0_case "deps-add:lock-read-locked-exit0" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_LOCKED_TMP"

LOCK_LOCKED_OUT="$(TRIAGE_OPS_OFFLINE=1 bash "$OPS" deps-add \
  --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_LOCKED_TMP" 2>/dev/null)"
if printf '%s' "$LOCK_LOCKED_OUT" | grep -qF '"issueId"'; then
  failed "deps-add:lock-read-locked-no-payload" "locked raw response emitted a payload (stdout: $LOCK_LOCKED_OUT)"
else
  pass "deps-add:lock-read-locked-no-payload" "no {issueId} payload when raw response carries triage:locked"
fi

# Case 5: clean raw body WITHOUT triage:locked → proceeds to {issueId,blockingIssueId} payload.
LABELS_RESP_UNLOCKED_TMP="$TMPDIR_TEST/labels-raw-unlocked.json"
cp "$TB_DIR/labels-raw-unlocked.json" "$LABELS_RESP_UNLOCKED_TMP"

run_case "deps-add:lock-read-unlocked-payload" "$EXPECTED_DIR/deps-add-payload.json" -- \
  deps-add --issue-id I_aaa --blocked-by-id I_bbb \
  --issue-labels-response "$LABELS_RESP_UNLOCKED_TMP"

# ── list-issues: FAIL-CLOSED on error-envelope and null-element row (N004) ───────
# The shared kernel validates produced rows before the cap check and before emitting
# the backlog. Neither an error envelope nor a row with null identifiers may be
# passed through as the backlog.

# Case 6: error envelope body → .errors present, kernel fails closed, nonzero exit.
LIST_ERR_TMP="$TMPDIR_TEST/list-issues-error-response.json"
cp "$TB_DIR/list-issues-error-response.json" "$LIST_ERR_TMP"

LIST_STATUS=0
TRIAGE_OPS_OFFLINE=1 bash "$OPS" list-issues \
  --limit 500 --response-file "$LIST_ERR_TMP" >/dev/null 2>&1 || LIST_STATUS=$?
if [ "$LIST_STATUS" -ne 0 ]; then
  pass "list-issues:error-envelope-fail-closed" "exit=$LIST_STATUS (error envelope rejected by kernel)"
else
  failed "list-issues:error-envelope-fail-closed" "expected nonzero exit on error envelope, got 0"
fi

# Case 7: null-element row (null number field) → elem_pred fails, kernel rejects, nonzero exit.
LIST_NULLELEM_TMP="$TMPDIR_TEST/list-issues-null-elem-response.json"
cp "$TB_DIR/list-issues-null-elem-response.json" "$LIST_NULLELEM_TMP"

LIST_STATUS=0
TRIAGE_OPS_OFFLINE=1 bash "$OPS" list-issues \
  --limit 500 --response-file "$LIST_NULLELEM_TMP" >/dev/null 2>&1 || LIST_STATUS=$?
if [ "$LIST_STATUS" -ne 0 ]; then
  pass "list-issues:null-elem-row-fail-closed" "exit=$LIST_STATUS (null-number row rejected by kernel)"
else
  failed "list-issues:null-elem-row-fail-closed" "expected nonzero exit on null-elem row, got 0"
fi

# ── deps-read: owner/repo shape guard — fail-closed on malformed NWO token ───────
# STEP-001 guard: after `gh repo view --json nameWithOwner` returns, the kernel-projected
# token must match ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ or die exit 1.  We exercise the
# LIVE path (no TRIAGE_OPS_OFFLINE) with a PATH-shadowed gh stub that answers
# `repo view --json nameWithOwner` with a synthetic {"nameWithOwner":"<TOKEN>"}.
# The stub is parameterized via STUB_NWO so one script covers all cases.
# The stub need not handle `gh api graphql` — the guard die()s before that call.
#
# Positive happy-path: the existing offline deps-read:normalize case locks the well-formed
# path.  If a clean live positive assertion is desired it would require a full graphql stub;
# instead we omit it and note that coverage above is sufficient.

STUBBIN_DIR="$TMPDIR_TEST/stubbin"
mkdir -p "$STUBBIN_DIR"
cat > "$STUBBIN_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
# Minimal gh stub: answers `repo view --json nameWithOwner` only.
# If `api graphql` is reached, the malformed token slipped PAST the shape guard.
# The caller invokes `gh api graphql ... 2>/dev/null`, so a stderr marker would be
# swallowed — drop a SENTINEL FILE next to this stub (a path it derives from $0,
# unaffected by the caller's stderr redirection) so the test can observe whether
# the split was ever reached. This makes the guard-before-split property load-bearing
# rather than vacuous.
if [ "${1:-}" = "api" ] && [ "${2:-}" = "graphql" ]; then
  printf 'reached gh api graphql — shape guard did NOT fire before the split\n' \
    > "$(dirname "$0")/STUB_REACHED_GRAPHQL"
  exit 1
fi
for arg in "$@"; do
  case "$arg" in
    nameWithOwner)
      printf '{"nameWithOwner":"%s"}\n' "${STUB_NWO:-ownerrepo}"
      exit 0
      ;;
  esac
done
exit 1
STUB_EOF
chmod +x "$STUBBIN_DIR/gh"

# Case 1: no slash — token "ownerrepo" must fire the guard (exit nonzero).
# Also verify the guard message appears on stderr so we know the RIGHT guard fired.
NWO_NOSTUB_STDERR="$TMPDIR_TEST/nostub-stderr.txt"
NWO_NOSTUB_STATUS=0
STUB_NWO="ownerrepo" PATH="$STUBBIN_DIR:$PATH" \
  bash "$OPS" deps-read 5 >"$TMPDIR_TEST/nostub-out.txt" 2>"$NWO_NOSTUB_STDERR" \
  || NWO_NOSTUB_STATUS=$?
if [ "$NWO_NOSTUB_STATUS" -ne 0 ]; then
  pass "deps-read:malformed-no-slash-failclosed" "exit=$NWO_NOSTUB_STATUS (token: ownerrepo)"
else
  failed "deps-read:malformed-no-slash-failclosed" "expected nonzero exit, got 0 (token: ownerrepo)"
fi
# Confirm the guard message is present — failure here means a DIFFERENT guard fired.
if grep -qF "is not a valid 'owner/repo' token" "$NWO_NOSTUB_STDERR"; then
  pass "deps-read:malformed-no-slash-guard-message" "guard message found in stderr"
else
  failed "deps-read:malformed-no-slash-guard-message" \
    "guard message absent from stderr (stderr: $(cat "$NWO_NOSTUB_STDERR"))"
fi

# Case 2: extra slash — token "owner/repo/extra" must fire the guard (exit nonzero).
# Pre-fix, owner/repo/extra would split (owner=owner, repo=repo/extra) and REACH
# gh api graphql; the stub now marks that path loudly, so this case proves the
# shape guard fires BEFORE the split rather than passing vacuously on the stub's
# generic exit 1. Assert: nonzero exit + guard message present + GraphQL NOT reached.
NWO_EXTRA_STDERR="$TMPDIR_TEST/extra-stderr.txt"
NWO_EXTRA_STATUS=0
rm -f "$STUBBIN_DIR/STUB_REACHED_GRAPHQL"  # clear any stale sentinel before the run
STUB_NWO="owner/repo/extra" PATH="$STUBBIN_DIR:$PATH" \
  bash "$OPS" deps-read 5 >"$TMPDIR_TEST/extra-out.txt" 2>"$NWO_EXTRA_STDERR" \
  || NWO_EXTRA_STATUS=$?
if [ "$NWO_EXTRA_STATUS" -ne 0 ]; then
  pass "deps-read:malformed-extra-slash-failclosed" "exit=$NWO_EXTRA_STATUS (token: owner/repo/extra)"
else
  failed "deps-read:malformed-extra-slash-failclosed" "expected nonzero exit, got 0 (token: owner/repo/extra)"
fi
# Confirm the SHAPE guard fired (not some other failure) — same guard message as case 1.
if grep -qF "is not a valid 'owner/repo' token" "$NWO_EXTRA_STDERR"; then
  pass "deps-read:malformed-extra-slash-guard-message" "guard message found in stderr"
else
  failed "deps-read:malformed-extra-slash-guard-message" \
    "guard message absent from stderr (stderr: $(cat "$NWO_EXTRA_STDERR"))"
fi
# Confirm the split was NEVER reached: the stub's sentinel file must be ABSENT.
# This is the property the guard exists to enforce — fail-closed BEFORE the split.
# (The caller's `gh api graphql ... 2>/dev/null` swallows stderr, so the stub
# signals via a sentinel file that the redirection cannot suppress.)
if [ -e "$STUBBIN_DIR/STUB_REACHED_GRAPHQL" ]; then
  failed "deps-read:malformed-extra-slash-guard-before-split" \
    "owner/repo split reached gh api graphql — guard did NOT fire before the split"
else
  pass "deps-read:malformed-extra-slash-guard-before-split" "graphql not reached; guard fired before split"
fi

# ── Summary ───────────────────────────────────────────────────────────────────────
echo
echo "triage-ops: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
