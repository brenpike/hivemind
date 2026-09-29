#!/usr/bin/env bash
#
# Behavioral unit runner for the reply + resolve mutation-sequence builder (issue #205).
#
# OFFLINE bash TEST — CI-runnable with ONLY bash present (NO tmux / gh / network). It drives:
#   plugin/skills/github-review-loop/scripts/reply-resolve.sh
# via its documented CAPTURE seam (REPLYRESOLVE_CAPTURE_FILE, which records each mutation to a file
# INSTEAD of issuing it against gh) plus the REPLYRESOLVE_REPLY_STATUS / REPLYRESOLVE_RESOLVE_STATUS
# exit-status seams (to simulate a failed reply / failed resolve). Every case asserts the captured
# mutation log and the script's own exit status, so each case is deterministic and offline.
#
# Both reply modes are covered: the FIX body (`Fixed in <SHA>. <summary>.`) and the sanctioned DEFER
# body selected by `--defer <TRACKED_HOME>`
# (`<!-- hivemind-defer-v1 --> Deferred to <TRACKED_HOME>. <SUMMARY>.`, issue #384), including the
# DEFER-only reason tokens (conflicting-reply-mode / missing-tracked-home / invalid-tracked-home)
# and the SENTINEL invariant (reply-resolve.sh §4): the machine record of a deferral is the exact
# constant `<!-- hivemind-defer-v1 -->` at BYTE 0 of a ONE-LINE body, asserted here as a byte-exact
# prefix comparison against that constant — never as a prose pattern.
#
# Mirrors tools/test_fetch_normalize.sh's pass/fail counter + per-case assertion + exit-nonzero-on-any
# -fail convention. Read-only: the only writes are scratch capture files in a disposable tmpdir
# removed on EXIT.
#
# Usage:
#   ./tools/test_reply_resolve.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPLY_RESOLVE="$REPO_ROOT/plugin/skills/github-review-loop/scripts/reply-resolve.sh"

[ -f "$REPLY_RESOLVE" ] || { echo "FAIL: script under test missing: $REPLY_RESOLVE" >&2; exit 2; }

TMPDIR_TEST="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# fresh_capture <name>: return a path to a fresh, empty capture file under the tmpdir.
fresh_capture() {
  local f="$TMPDIR_TEST/$1.log"
  : > "$f"
  printf '%s' "$f"
}

# ── reply-then-resolve happy path (ordering) ───────────────────────────────────────
# A thread surface, resolve-eligible: the REPLY line must precede the RESOLVE line, and both target
# the thread id. Exit 0.
cap="$(fresh_capture happy)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --resolve-eligible -- PRRT_aaa abc123 "Fixed the null deref" thread "" 2>&1)"
status=$?
reply_line="$(grep -n '^REPLY ' "$cap" | head -n1 | cut -d: -f1)"
resolve_line="$(grep -n '^RESOLVE ' "$cap" | head -n1 | cut -d: -f1)"
if [ "$status" -eq 0 ] && [ -n "$reply_line" ] && [ -n "$resolve_line" ] && [ "$reply_line" -lt "$resolve_line" ]; then
  pass "happy:reply-before-resolve" "REPLY(line $reply_line) precedes RESOLVE(line $resolve_line), exit 0"
else
  failed "happy:reply-before-resolve" "status=$status reply_line=$reply_line resolve_line=$resolve_line cap=$(cat "$cap") out=$out"
fi
# Reply body format for a thread surface: "Fixed in <SHA>. <summary>." with NO Addresses line.
if grep -q '^REPLY thread=PRRT_aaa body=Fixed in abc123\. Fixed the null deref\.$' "$cap"; then
  pass "happy:reply-body-thread" "thread reply body exact"
else
  failed "happy:reply-body-thread" "body mismatch: $(grep '^REPLY' "$cap")"
fi

# ── resolve-skip when an unaddressed non-self comment remains ───────────────────────
# The caller signals "not all addressed" by OMITTING --resolve-eligible. The reply is still posted;
# NO resolve is issued. Exit 0.
cap="$(fresh_capture unaddressed)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" -- PRRT_bbb def456 "Partial fix" thread "" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && grep -q '^REPLY ' "$cap" && ! grep -q '^RESOLVE ' "$cap"; then
  pass "skip:unaddressed-no-resolve" "reply posted, NO resolve, exit 0"
else
  failed "skip:unaddressed-no-resolve" "status=$status cap=$(cat "$cap") out=$out"
fi

# ── question-needs-user-input is NEVER resolved ─────────────────────────────────────
# Even with --resolve-eligible, the --question-needs-user-input marker hard-blocks resolve. The reply
# is still posted. Exit 0.
cap="$(fresh_capture question)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --resolve-eligible --question-needs-user-input -- \
  PRRT_ccc ghi789 "Replied but awaiting answer" thread "" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && grep -q '^REPLY ' "$cap" && ! grep -q '^RESOLVE ' "$cap"; then
  pass "question:never-resolved" "reply posted, NO resolve despite eligible, exit 0"
else
  failed "question:never-resolved" "status=$status cap=$(cat "$cap") out=$out"
fi

# ── resolve-failure is non-blocking ────────────────────────────────────────────────
# A failed RESOLVE (simulated via REPLYRESOLVE_RESOLVE_STATUS=1) logs the REPLYRESOLVE_RESOLVE_FAILED
# diagnostic to stderr but the script STILL exits 0 — the reply landed and the candidate succeeded.
cap="$(fresh_capture resolvefail)"
err="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" REPLYRESOLVE_RESOLVE_STATUS=1 \
  bash "$REPLY_RESOLVE" --resolve-eligible -- PRRT_ddd jkl012 "Fix applied" thread "" 2>&1 1>/dev/null)"
status=$?
if [ "$status" -eq 0 ] && grep -q '^REPLY ' "$cap" && grep -q '^RESOLVE ' "$cap" \
   && printf '%s' "$err" | grep -q "REPLYRESOLVE_RESOLVE_FAILED"; then
  pass "resolvefail:non-blocking" "resolve attempted + failed, diagnostic on stderr, exit 0"
else
  failed "resolvefail:non-blocking" "status=$status cap=$(cat "$cap") err=$err"
fi

# ── reply-failure is a HARD failure (no resolve attempted) ──────────────────────────
# A failed REPLY (simulated via REPLYRESOLVE_REPLY_STATUS=1) exits 1 with REPLYRESOLVE_ERROR=reply
# -failed and NEVER issues a resolve (reply-before-resolve invariant: no orphaned resolve).
cap="$(fresh_capture replyfail)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" REPLYRESOLVE_REPLY_STATUS=1 \
  bash "$REPLY_RESOLVE" --resolve-eligible -- PRRT_eee mno345 "Attempted fix" thread "" 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -q '^REPLYRESOLVE_ERROR=reply-failed$' \
   && ! grep -q '^RESOLVE ' "$cap"; then
  pass "replyfail:hard-fail-no-resolve" "exit=$status REPLYRESOLVE_ERROR=reply-failed, no resolve"
else
  failed "replyfail:hard-fail-no-resolve" "status=$status out=$out cap=$(cat "$cap")"
fi

# ── toplevel surface is a SILENT NO-OP (#218) ──────────────────────────────────────
# A toplevel surface has no review-thread node, so NOTHING is delivered: no REPLY, no RESOLVE,
# zero stdout, empty capture file, exit 0. (Even with --resolve-eligible and a candidate url.)
cap="$(fresh_capture toplevel)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --resolve-eligible -- PRRT_fff pqr678 "Addressed in code" toplevel "https://github.com/o/r/pull/5#issuecomment-1" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && [ ! -s "$cap" ] && [ -z "$out" ]; then
  pass "toplevel:silent-no-op" "no mutation captured, zero stdout, exit 0"
else
  failed "toplevel:silent-no-op" "status=$status cap=$(cat "$cap") out=$out"
fi

# ── review surface is a SILENT NO-OP (#218) ─────────────────────────────────────────
# Identical to toplevel: no REPLY, no RESOLVE, empty capture file, exit 0.
cap="$(fresh_capture reviewsurface)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" -- PRRT_ggg stu901 "Summary addressed" review "https://github.com/o/r/pull/5#pullrequestreview-9" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && [ ! -s "$cap" ] && [ -z "$out" ]; then
  pass "review:silent-no-op" "no mutation captured, zero stdout, exit 0"
else
  failed "review:silent-no-op" "status=$status cap=$(cat "$cap") out=$out"
fi

# ── toplevel surface PRODUCTION SHAPE: empty thread id is a SILENT NO-OP (#218) ─────
# The normalizer emits thread_id: null for non-thread surfaces (fetch-normalize.sh §2), so a
# REAL fixed toplevel candidate reaches reply-resolve.sh with an EMPTY THREAD_ID positional.
# The required-input guards are surface-scoped (inside the thread) branch), so an empty thread
# id must NOT trip missing-thread-id — it must silently no-op: empty capture, zero stdout, exit 0.
cap="$(fresh_capture toplevel_empty_tid)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --resolve-eligible -- "" pqr678 "Addressed in code" toplevel "https://github.com/o/r/pull/5#issuecomment-1" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && [ ! -s "$cap" ] && [ -z "$out" ]; then
  pass "toplevel:empty-tid-silent-no-op" "empty thread id no-ops (no missing-thread-id), zero stdout, exit 0"
else
  failed "toplevel:empty-tid-silent-no-op" "status=$status cap=$(cat "$cap") out=$out"
fi

# ── review surface PRODUCTION SHAPE: empty thread id is a SILENT NO-OP (#218) ────────
# Identical to the toplevel production-shape case: an empty thread id on the review surface must
# silently no-op (empty capture, zero stdout, exit 0), NOT fail with missing-thread-id.
cap="$(fresh_capture review_empty_tid)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" -- "" stu901 "Summary addressed" review "https://github.com/o/r/pull/5#pullrequestreview-9" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && [ ! -s "$cap" ] && [ -z "$out" ]; then
  pass "review:empty-tid-silent-no-op" "empty thread id no-ops (no missing-thread-id), zero stdout, exit 0"
else
  failed "review:empty-tid-silent-no-op" "status=$status cap=$(cat "$cap") out=$out"
fi

# ── thread surface STILL requires a thread id (guard relocated, not removed) ─────────
# The missing-thread-id guard moved INTO the thread) branch — it must still fire for a thread
# surface with an empty thread id: REPLYRESOLVE_ERROR=missing-thread-id, exit non-zero, no mutation.
cap="$(fresh_capture thread_empty_tid)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --resolve-eligible -- "" abc123 "Fix applied" thread "" 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -q '^REPLYRESOLVE_ERROR=missing-thread-id$' \
   && [ ! -s "$cap" ]; then
  pass "thread:empty-tid-missing-thread-id" "thread surface still fails closed on empty thread id, no mutation"
else
  failed "thread:empty-tid-missing-thread-id" "status=$status out=$out cap=$(cat "$cap")"
fi

# ── unmapped surface fails CLOSED (no mutation issued) ──────────────────────────────
# An unknown surface (e.g. `bogus`) is not in the surface->delivery map: REPLYRESOLVE_ERROR=
# unmapped-surface, exit non-zero, and NO mutation captured (dispatch never falls back to thread).
cap="$(fresh_capture badsurface)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" -- PRRT_hhh vwx234 "Bad surface" bogus "" 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -q '^REPLYRESOLVE_ERROR=unmapped-surface$' \
   && [ ! -s "$cap" ]; then
  pass "badsurface:unmapped-surface" "exit=$status REPLYRESOLVE_ERROR=unmapped-surface, no mutation"
else
  failed "badsurface:unmapped-surface" "status=$status out=$out cap=$(cat "$cap")"
fi

# ── Fail-closed gate lock: CAPTURE_FILE WITHOUT TEST_MODE does NOT divert ──────────
# STEP-001 made the capture seam require BOTH REPLYRESOLVE_TEST_MODE=1 AND
# REPLYRESOLVE_CAPTURE_FILE. A stray CAPTURE_FILE ALONE must no longer divert — the
# mutation goes LIVE to gh. We assert the gate's observable contract: with TEST_MODE
# absent the capture file is NEVER written (the seam stayed inactive and the code
# fell through to the live path). NOTE: TEST_MODE is deliberately UNSET here — the
# whole point of the case.
#
# OFFLINE INVARIANT: with TEST_MODE unset and otherwise-valid inputs, run_mutation
# falls through to the LIVE `gh api graphql` path. Without a stub that would invoke
# the REAL gh CLI when present (network call / 45s timeout) despite this suite being
# offline. We prepend a stub `gh` to PATH that records it was reached (proving the
# code went live) and exits non-zero, so no real CLI runs. Asserting the stub was
# reached AND the capture file stayed empty locks BOTH halves of the contract:
# the seam did NOT divert (cap empty) and the live path WAS taken (stub reached).
cap="$(fresh_capture nodivert)"
gh_stub_dir="$TMPDIR_TEST/nodivert-stubbin"
gh_stub_marker="$TMPDIR_TEST/nodivert-gh-reached"
mkdir -p "$gh_stub_dir"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'printf reached > %q\n' "$gh_stub_marker"
  printf '%s\n' 'exit 1'
} > "$gh_stub_dir/gh"
chmod +x "$gh_stub_dir/gh"
PATH="$gh_stub_dir:$PATH" REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --resolve-eligible -- PRRT_iii xyz789 "No test mode" thread "" >/dev/null 2>&1
if [ ! -s "$cap" ] && [ -f "$gh_stub_marker" ]; then
  pass "failclosed:capture-without-testmode-no-divert" "CAPTURE_FILE alone did NOT divert (cap empty); live gh path reached (stub invoked)"
else
  failed "failclosed:capture-without-testmode-no-divert" "diverted or live-path-not-reached — cap=$(cat "$cap") stub_reached=$([ -f "$gh_stub_marker" ] && echo yes || echo no)"
fi

# ── FIX mode STILL requires a fix SHA (regression lock for the DEFER split) ─────────
# reply-resolve.sh §3 fixes the thread-surface validation order; step 5 (missing-fix-sha) fires in
# FIX mode ONLY. With --defer ABSENT an empty FIX_SHA must still fail closed, so the DEFER branch
# cannot have loosened the FIX path: REPLYRESOLVE_ERROR=missing-fix-sha, exit non-zero, no mutation.
cap="$(fresh_capture fix_empty_sha)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --resolve-eligible -- PRRT_jjj "" "Fix applied" thread "" 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -q '^REPLYRESOLVE_ERROR=missing-fix-sha$' \
   && [ ! -s "$cap" ]; then
  pass "fix:empty-sha-missing-fix-sha" "FIX mode still fails closed on empty fix SHA, no mutation"
else
  failed "fix:empty-sha-missing-fix-sha" "status=$status out=$out cap=$(cat "$cap")"
fi

# ══ DEFER reply mode (--defer <TRACKED_HOME>, issue #384) ═══════════════════════════
# The sanctioned second reply body:
# "<!-- hivemind-defer-v1 --> Deferred to <TRACKED_HOME>. <SUMMARY>." (reply-resolve.sh §3).
# Same capture seam, same exit-status seams, no new env var.

# The machine sentinel, pinned here as a byte-exact CONSTANT (reply-resolve.sh §4). Every DEFER
# assertion below compares against this literal — no regex, no wildcard, no prose match — so a
# reworded body still passes while a body that loses the sentinel (or moves it off byte 0) fails.
DEFER_SENTINEL='<!-- hivemind-defer-v1 -->'
DEFER_ISSUE_HOME="https://github.com/brenpike/hivemind/issues/384"
DEFER_RESIDUAL_HOME="docs/adr/0031-checked-discovery-policy.md"

# assert_hard_fail <case-name> <reason-token> <script-arg>...: run reply-resolve.sh with a fresh
# capture file and assert it fails closed — REPLYRESOLVE_ERROR=<reason-token> on stdout, non-zero
# exit, and NOTHING written to the capture seam. Shared by the DEFER mode/value guards, which differ
# only in argv and reason token.
assert_hard_fail() {
  local name="$1" token="$2"
  shift 2
  local cap out status
  cap="$(fresh_capture "${name//:/-}")"
  out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
    bash "$REPLY_RESOLVE" "$@" 2>/dev/null)"
  status=$?
  if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -q "^REPLYRESOLVE_ERROR=$token\$" \
     && [ ! -s "$cap" ]; then
    pass "$name" "exit=$status REPLYRESOLVE_ERROR=$token, no mutation captured"
  else
    failed "$name" "status=$status out=$out cap=$(cat "$cap")"
  fi
}

# assert_silent_no_op <case-name> <script-arg>...: run reply-resolve.sh with a fresh capture file and
# assert the silent-no-op contract — exit 0, ZERO stdout/stderr, empty capture. Shared by the
# toplevel/review DEFER cases, which differ only in argv.
assert_silent_no_op() {
  local name="$1"
  shift
  local cap out status
  cap="$(fresh_capture "${name//:/-}")"
  out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
    bash "$REPLY_RESOLVE" "$@" 2>&1)"
  status=$?
  if [ "$status" -eq 0 ] && [ ! -s "$cap" ] && [ -z "$out" ]; then
    pass "$name" "no mutation captured, zero stdout, exit 0"
  else
    failed "$name" "status=$status cap=$(cat "$cap") out=$out"
  fi
}

# ── DEFER happy path: reply-then-resolve ordering, exact body, sentinel at byte 0 ───
# A deferred thread resolves on the SAME --resolve-eligible predicate as a fixed one (§3(b)), so the
# REPLY line must precede the RESOLVE line. FIX_SHA is EMPTY — required to be, under --defer.
cap="$(fresh_capture defer_happy)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --defer "$DEFER_ISSUE_HOME" --resolve-eligible -- \
  PRRT_d1 "" "Tracked for the next cycle" thread "" 2>&1)"
status=$?
reply_line="$(grep -n '^REPLY ' "$cap" | head -n1 | cut -d: -f1)"
resolve_line="$(grep -n '^RESOLVE ' "$cap" | head -n1 | cut -d: -f1)"
if [ "$status" -eq 0 ] && [ -n "$reply_line" ] && [ -n "$resolve_line" ] && [ "$reply_line" -lt "$resolve_line" ]; then
  pass "defer:reply-before-resolve" "REPLY(line $reply_line) precedes RESOLVE(line $resolve_line), exit 0"
else
  failed "defer:reply-before-resolve" "status=$status reply_line=$reply_line resolve_line=$resolve_line cap=$(cat "$cap") out=$out"
fi
# Exact DEFER body (§4, one of EXACTLY TWO sanctioned bodies): sentinel-first, no `Fixed in`, no
# `Addresses:` line.
expected_defer_reply="REPLY thread=PRRT_d1 body=$DEFER_SENTINEL Deferred to $DEFER_ISSUE_HOME. Tracked for the next cycle."
actual_defer_reply="$(grep '^REPLY ' "$cap" | head -n1)"
actual_defer_body="${actual_defer_reply#*body=}"
if [ "$actual_defer_reply" = "$expected_defer_reply" ] && ! grep -q 'Fixed in' "$cap" \
   && ! grep -q 'Addresses:' "$cap"; then
  pass "defer:reply-body-exact" "DEFER reply body exact, no 'Fixed in', no 'Addresses:'"
else
  failed "defer:reply-body-exact" "expected=$expected_defer_reply actual=$actual_defer_reply cap=$(cat "$cap")"
fi
# SENTINEL AT BYTE 0 (§4): the classifier recognises a deferral by a CONSTANT COMPARISON on the
# body's leading bytes (jq `startswith`), so the emitted body must START WITH the exact sentinel
# constant. Asserted as a byte-exact prefix match against $DEFER_SENTINEL — deliberately NOT a
# regex over the prose that follows, because prose is not the machine record. A body whose sentinel
# is missing, altered, or preceded by anything (e.g. a Markdown quote marker) fails here.
if [[ "$actual_defer_body" == "$DEFER_SENTINEL"* ]]; then
  pass "defer:body-starts-with-sentinel" "body starts with the exact sentinel constant"
else
  failed "defer:body-starts-with-sentinel" "sentinel not at byte 0 of body: $actual_defer_body"
fi
# ONE-LINE BODY (§4/§5): the capture seam writes ONE line per mutation, so an embedded newline in
# the body would split the machine record from its prose across capture lines. Assert the happy-path
# capture holds EXACTLY ONE REPLY line and NO line that is neither a REPLY nor a RESOLVE record —
# i.e. no stray continuation line leaked out of the body.
defer_reply_lines="$(grep -c '^REPLY ' "$cap")"
defer_stray_lines="$(grep -cvE '^(REPLY|RESOLVE) ' "$cap")"
if [ "$defer_reply_lines" -eq 1 ] && [ "$defer_stray_lines" -eq 0 ]; then
  pass "defer:body-single-line" "exactly 1 REPLY line, 0 stray continuation lines"
else
  failed "defer:body-single-line" "reply_lines=$defer_reply_lines stray_lines=$defer_stray_lines cap=$(cat "$cap")"
fi

# ── DEFER to a RECORDED RESIDUAL home (not a tracked issue) ─────────────────────────
# TRACKED_HOME is a ROLE, not a destination type (§1): a repo-relative residual location is as valid
# as an issue url, and is interpolated verbatim into the body.
cap="$(fresh_capture defer_residual)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --defer "$DEFER_RESIDUAL_HOME" --resolve-eligible -- \
  PRRT_d2 "" "Recorded as residual" thread "" 2>&1)"
status=$?
expected_residual_reply="REPLY thread=PRRT_d2 body=$DEFER_SENTINEL Deferred to $DEFER_RESIDUAL_HOME. Recorded as residual."
if [ "$status" -eq 0 ] && [ "$(grep '^REPLY ' "$cap" | head -n1)" = "$expected_residual_reply" ]; then
  pass "defer:recorded-residual-home" "residual location named in body verbatim, exit 0"
else
  failed "defer:recorded-residual-home" "status=$status cap=$(cat "$cap") out=$out"
fi

# ── DEFER without --resolve-eligible: reply only ────────────────────────────────────
# The resolve predicate is unchanged by reply mode — omitting --resolve-eligible still means NO
# resolve, reply posted, exit 0.
cap="$(fresh_capture defer_unaddressed)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --defer "$DEFER_ISSUE_HOME" -- PRRT_d3 "" "Deferred, siblings open" thread "" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && grep -q '^REPLY ' "$cap" && ! grep -q '^RESOLVE ' "$cap"; then
  pass "defer:no-eligible-no-resolve" "deferral reply posted, NO resolve, exit 0"
else
  failed "defer:no-eligible-no-resolve" "status=$status cap=$(cat "$cap") out=$out"
fi

# ── DEFER + question-needs-user-input is NEVER resolved ─────────────────────────────
# The hard NEVER-resolve marker outranks --resolve-eligible in BOTH reply modes (§4).
cap="$(fresh_capture defer_question)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --defer "$DEFER_ISSUE_HOME" --resolve-eligible --question-needs-user-input -- \
  PRRT_d4 "" "Deferred pending an answer" thread "" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && grep -q '^REPLY ' "$cap" && ! grep -q '^RESOLVE ' "$cap"; then
  pass "defer:question-never-resolved" "deferral reply posted, NO resolve despite eligible, exit 0"
else
  failed "defer:question-never-resolved" "status=$status cap=$(cat "$cap") out=$out"
fi

# ── DEFER on the non-thread surfaces stays a SILENT NO-OP (surface-scoped guards) ────
# toplevel/review deliver nothing in BOTH reply modes — including when --defer carries an absent or
# malformed value, because TRACKED_HOME is a thread-surface input and no guard for it runs here (§3).
assert_silent_no_op "defer:toplevel-silent-no-op" \
  --defer "$DEFER_ISSUE_HOME" --resolve-eligible -- PRRT_d5 "" "Deferred" toplevel \
  "https://github.com/o/r/pull/5#issuecomment-1"
assert_silent_no_op "defer:review-silent-no-op" \
  --defer "$DEFER_ISSUE_HOME" -- PRRT_d6 "" "Deferred" review \
  "https://github.com/o/r/pull/5#pullrequestreview-9"
assert_silent_no_op "defer:toplevel-malformed-home-silent-no-op" \
  --defer "has space" --resolve-eligible -- PRRT_d7 "" "Deferred" toplevel ""

# ── DEFER does NOT loosen the surface->delivery map ─────────────────────────────────
assert_hard_fail "defer:unmapped-surface" unmapped-surface \
  --defer "$DEFER_ISSUE_HOME" -- PRRT_d8 "" "Deferred" bogus ""

# ── THREAD-SURFACE VALIDATION ORDER (§3) under --defer ──────────────────────────────
# 1. missing-thread-id still wins first, in DEFER mode too.
assert_hard_fail "defer:empty-tid-missing-thread-id" missing-thread-id \
  --defer "$DEFER_ISSUE_HOME" --resolve-eligible -- "" "" "Deferred" thread ""
# 2. conflicting-reply-mode: a non-empty FIX_SHA alongside --defer claims two dispositions at once,
#    and is judged BEFORE the TRACKED_HOME value guards.
assert_hard_fail "defer:fix-sha-conflicting-reply-mode" conflicting-reply-mode \
  --defer "$DEFER_ISSUE_HOME" --resolve-eligible -- PRRT_d9 abc123 "Deferred" thread ""
# 3. missing-tracked-home: an EMPTY value, and `--defer` as the LAST arg (space form only — it has no
#    value to consume, so TRACKED_HOME stays empty).
assert_hard_fail "defer:empty-home-missing-tracked-home" missing-tracked-home \
  --defer "" --resolve-eligible -- PRRT_d10 "" "Deferred" thread ""
assert_hard_fail "defer:no-value-missing-tracked-home" missing-tracked-home \
  PRRT_d11 "" "Deferred" thread "" --defer
# 4. invalid-tracked-home: whitespace-bearing (space or tab) or `-`-leading values. NOT marker-
#    load-bearing (the sentinel is written unconditionally, §2) — a `-`-leading value catches a
#    SWALLOWED FLAG, and a whitespace-free token keeps the home a citable one-token reference.
assert_hard_fail "defer:space-home-invalid-tracked-home" invalid-tracked-home \
  --defer "has space" --resolve-eligible -- PRRT_d12 "" "Deferred" thread ""
assert_hard_fail "defer:tab-home-invalid-tracked-home" invalid-tracked-home \
  --defer "$(printf 'has\ttab')" --resolve-eligible -- PRRT_d13 "" "Deferred" thread ""
assert_hard_fail "defer:dash-home-invalid-tracked-home" invalid-tracked-home \
  --defer -oops --resolve-eligible -- PRRT_d14 "" "Deferred" thread ""
# 6. missing-summary fires in BOTH modes — the summary is interpolated into either body.
assert_hard_fail "defer:empty-summary-missing-summary" missing-summary \
  --defer "$DEFER_ISSUE_HOME" --resolve-eligible -- PRRT_d15 "" "" thread ""

# ── DEFER reply failure is a HARD failure (no resolve attempted) ────────────────────
# REPLY BEFORE RESOLVE holds identically for a DEFER reply: a failed reply must never leave an
# orphaned resolve.
cap="$(fresh_capture defer_replyfail)"
out="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" REPLYRESOLVE_REPLY_STATUS=1 \
  bash "$REPLY_RESOLVE" --defer "$DEFER_ISSUE_HOME" --resolve-eligible -- \
  PRRT_d16 "" "Deferred" thread "" 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -q '^REPLYRESOLVE_ERROR=reply-failed$' \
   && ! grep -q '^RESOLVE ' "$cap"; then
  pass "defer:replyfail-hard-fail-no-resolve" "exit=$status REPLYRESOLVE_ERROR=reply-failed, no resolve"
else
  failed "defer:replyfail-hard-fail-no-resolve" "status=$status out=$out cap=$(cat "$cap")"
fi

# ── DEFER resolve failure stays NON-BLOCKING ────────────────────────────────────────
# A failed resolve after a deferral reply logs REPLYRESOLVE_RESOLVE_FAILED to stderr and the script
# STILL exits 0 — identical posture to the FIX path.
cap="$(fresh_capture defer_resolvefail)"
err="$(REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" REPLYRESOLVE_RESOLVE_STATUS=1 \
  bash "$REPLY_RESOLVE" --defer "$DEFER_ISSUE_HOME" --resolve-eligible -- \
  PRRT_d17 "" "Deferred" thread "" 2>&1 1>/dev/null)"
status=$?
if [ "$status" -eq 0 ] && grep -q '^REPLY ' "$cap" && grep -q '^RESOLVE ' "$cap" \
   && printf '%s' "$err" | grep -q "REPLYRESOLVE_RESOLVE_FAILED"; then
  pass "defer:resolvefail-non-blocking" "resolve attempted + failed, diagnostic on stderr, exit 0"
else
  failed "defer:resolvefail-non-blocking" "status=$status cap=$(cat "$cap") err=$err"
fi

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "reply-resolve: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
