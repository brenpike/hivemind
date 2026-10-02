#!/usr/bin/env bash
#
# Behavioral unit runner for the non-thread EYES reaction marker (issue #265).
#
# OFFLINE bash TEST — CI-runnable with ONLY bash present (NO tmux / gh / network). It drives:
#   plugin/skills/github-review-loop/scripts/react-marker.sh
# via its documented CAPTURE seam (REACTMARKER_TEST_MODE=1 + REACTMARKER_CAPTURE_FILE, which records
# each reaction to a file INSTEAD of issuing it against gh) plus the REACTMARKER_REACT_STATUS
# exit-status seam (to simulate a failed live mutation). Every case asserts the captured reaction log
# (line format: REACT node=<NODE_ID> content=EYES) and the script's own exit status / REACTMARKER_ERROR
# reason token, so each case is deterministic and offline.
#
# The live-path cases (#393) leave the capture seam unset and put a stub `gh` first on PATH that prints
# a canned GraphQL response body. They lock the single definition of live success — gh exit 0, the
# shared response check passing, AND .data.addReaction.reaction.content == EYES — and assert every
# other response (error envelopes, already-reacted wording, a null payload, a different content, a
# non-zero exit) is REACTMARKER_ERROR=react-failed.
#
# Mirrors tools/test_reply_resolve.sh's pass/fail counter + per-case assertion + exit-nonzero-on-any
# -fail convention. Read-only: the only writes are scratch capture files in a disposable tmpdir
# removed on EXIT.
#
# Production-shaped node ids are used deliberately (IC_... for toplevel IssueComment, PRR_... for a
# review PullRequestReview) — NOT fake placeholder ids — so validation-order bugs cannot hide behind
# a non-production shape.
#
# Usage:
#   ./tools/test_react_marker.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REACT_MARKER="$REPO_ROOT/plugin/skills/github-review-loop/scripts/react-marker.sh"

[ -f "$REACT_MARKER" ] || { echo "FAIL: script under test missing: $REACT_MARKER" >&2; exit 2; }

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

# Real production-shaped reviewer node ids. IC_ = toplevel IssueComment; PRR_ = review PullRequestReview.
TOPLEVEL_NODE="IC_kwDOABCDEF4AbCdEf"
REVIEW_NODE="PRR_kwDOABCDEF4AbCdEf"

# ── toplevel surface reacts with EYES over a real IC_ node ──────────────────────────
# A toplevel IssueComment is Reactable: exactly ONE capture line `REACT node=IC_... content=EYES`,
# exit 0.
cap="$(fresh_capture toplevel)"
out="$(REACTMARKER_TEST_MODE=1 REACTMARKER_CAPTURE_FILE="$cap" \
  bash "$REACT_MARKER" "$TOPLEVEL_NODE" toplevel "https://github.com/o/r/pull/5#issuecomment-1" 2>&1)"
status=$?
line_count="$(grep -c '^REACT ' "$cap")"
if [ "$status" -eq 0 ] && [ "$line_count" -eq 1 ] \
   && grep -qx "REACT node=$TOPLEVEL_NODE content=EYES" "$cap"; then
  pass "toplevel:react-eyes" "one REACT line for IC_ node, content=EYES, exit 0"
else
  failed "toplevel:react-eyes" "status=$status line_count=$line_count cap=$(cat "$cap") out=$out"
fi

# ── review surface reacts with EYES over a real PRR_ node ───────────────────────────
# A review PullRequestReview is also Reactable: exactly ONE capture line
# `REACT node=PRR_... content=EYES`, exit 0.
cap="$(fresh_capture review)"
out="$(REACTMARKER_TEST_MODE=1 REACTMARKER_CAPTURE_FILE="$cap" \
  bash "$REACT_MARKER" "$REVIEW_NODE" review "https://github.com/o/r/pull/5#pullrequestreview-9" 2>&1)"
status=$?
line_count="$(grep -c '^REACT ' "$cap")"
if [ "$status" -eq 0 ] && [ "$line_count" -eq 1 ] \
   && grep -qx "REACT node=$REVIEW_NODE content=EYES" "$cap"; then
  pass "review:react-eyes" "one REACT line for PRR_ node, content=EYES, exit 0"
else
  failed "review:react-eyes" "status=$status line_count=$line_count cap=$(cat "$cap") out=$out"
fi

# ── thread surface is a SILENT NO-OP (#265) ─────────────────────────────────────────
# Threads converge via reply-resolve.sh's resolveReviewThread; react-marker NEVER reacts to a thread
# node: ZERO capture lines, zero stdout, exit 0. (NODE_ID is supplied to prove the no-op is
# surface-driven, not input-driven.)
cap="$(fresh_capture thread)"
out="$(REACTMARKER_TEST_MODE=1 REACTMARKER_CAPTURE_FILE="$cap" \
  bash "$REACT_MARKER" "$TOPLEVEL_NODE" thread "https://github.com/o/r/pull/5#discussion_r1" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && [ ! -s "$cap" ] && [ -z "$out" ]; then
  pass "thread:silent-no-op" "no reaction captured, zero stdout, exit 0"
else
  failed "thread:silent-no-op" "status=$status cap=$(cat "$cap") out=$out"
fi

# ── unmapped surface fails CLOSED (no reaction issued) ──────────────────────────────
# An unknown surface (e.g. `bogus`) is not in the surface->delivery map: REACTMARKER_ERROR=
# unmapped-surface, exit non-zero, and NO reaction captured (dispatch never falls back to react).
cap="$(fresh_capture badsurface)"
out="$(REACTMARKER_TEST_MODE=1 REACTMARKER_CAPTURE_FILE="$cap" \
  bash "$REACT_MARKER" "$TOPLEVEL_NODE" bogus "" 2>&1)"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'REACTMARKER_ERROR=unmapped-surface' \
   && [ ! -s "$cap" ]; then
  pass "badsurface:unmapped-surface" "exit=$status REACTMARKER_ERROR=unmapped-surface, no reaction"
else
  failed "badsurface:unmapped-surface" "status=$status out=$out cap=$(cat "$cap")"
fi

# ── missing node id on a mutating surface fails CLOSED ──────────────────────────────
# An empty NODE_ID ($1) on a mutating surface (toplevel) trips the surface-scoped required-input
# guard: REACTMARKER_ERROR=missing-node-id, exit non-zero, no reaction captured.
cap="$(fresh_capture missingnode)"
out="$(REACTMARKER_TEST_MODE=1 REACTMARKER_CAPTURE_FILE="$cap" \
  bash "$REACT_MARKER" "" toplevel "https://github.com/o/r/pull/5#issuecomment-1" 2>&1)"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'REACTMARKER_ERROR=missing-node-id' \
   && [ ! -s "$cap" ]; then
  pass "missingnode:missing-node-id" "exit=$status REACTMARKER_ERROR=missing-node-id, no reaction"
else
  failed "missingnode:missing-node-id" "status=$status out=$out cap=$(cat "$cap")"
fi

# ── react mutation failure is a HARD failure ────────────────────────────────────────
# A failed REACT (simulated via REACTMARKER_REACT_STATUS=1 under the capture seam, which returns that
# status from run_reaction) routes through react_marker_fail: REACTMARKER_ERROR=react-failed, exit
# non-zero. The capture line is still written (the seam appends BEFORE returning the forced status),
# so the failure is on the mutation result, not the dispatch.
cap="$(fresh_capture reactfail)"
out="$(REACTMARKER_TEST_MODE=1 REACTMARKER_CAPTURE_FILE="$cap" REACTMARKER_REACT_STATUS=1 \
  bash "$REACT_MARKER" "$TOPLEVEL_NODE" toplevel "https://github.com/o/r/pull/5#issuecomment-1" 2>&1)"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'REACTMARKER_ERROR=react-failed'; then
  pass "reactfail:react-failed" "exit=$status REACTMARKER_ERROR=react-failed"
else
  failed "reactfail:react-failed" "status=$status out=$out cap=$(cat "$cap")"
fi

# ── Fail-closed gate lock: CAPTURE_FILE WITHOUT TEST_MODE does NOT divert ────────────
# The capture seam requires BOTH REACTMARKER_TEST_MODE=1 AND REACTMARKER_CAPTURE_FILE. A stray
# CAPTURE_FILE ALONE must NOT divert — the mutation goes LIVE to gh. We assert the gate's observable
# contract: with TEST_MODE absent the capture file is NEVER written (the seam stayed inactive and the
# code fell through to the live path). NOTE: TEST_MODE is deliberately UNSET here.
#
# OFFLINE INVARIANT: with TEST_MODE unset, run_reaction falls through to the LIVE `gh api graphql`
# path. Without a stub that would invoke the REAL gh CLI when present (network call / 45s timeout)
# despite this suite being offline. We prepend a stub `gh` to PATH that records it was reached
# (proving the code went live) and exits non-zero, so no real CLI runs. Asserting the stub was
# reached AND the capture file stayed empty locks BOTH halves of the contract: the seam did NOT
# divert (cap empty) and the live path WAS taken (stub reached).
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
PATH="$gh_stub_dir:$PATH" REACTMARKER_CAPTURE_FILE="$cap" \
  bash "$REACT_MARKER" "$TOPLEVEL_NODE" toplevel "https://github.com/o/r/pull/5#issuecomment-1" >/dev/null 2>&1
if [ ! -s "$cap" ] && [ -f "$gh_stub_marker" ]; then
  pass "failclosed:capture-without-testmode-no-divert" "CAPTURE_FILE alone did NOT divert (cap empty); live gh path reached (stub invoked)"
else
  failed "failclosed:capture-without-testmode-no-divert" "diverted or live-path-not-reached — cap=$(cat "$cap") stub_reached=$([ -f "$gh_stub_marker" ] && echo yes || echo no)"
fi

# ── Capture-append failure is a HARD failure, NOT a false success (#265 regression) ──
# When the seam is ACTIVE (TEST_MODE=1 + CAPTURE_FILE) but the capture path is UNWRITABLE, the append
# fails. With set -e deliberately omitted (P18 floor), an UNGUARDED append would be silently ignored
# and run_reaction would still return the default-0 simulated status — reporting marker SUCCESS while
# NOTHING was captured and the live gh mutation was bypassed. The `|| return 1` guard converts that
# into react-failed. Assert: exit non-zero, REACTMARKER_ERROR=react-failed, and the live gh path is
# NOT reached (a stub gh on PATH must stay un-invoked — the seam stayed engaged and hard-failed on
# the append, never falling through to live). REACTMARKER_REACT_STATUS is left at its default 0 so
# the ONLY failure source under test is the append itself.
#
# The write must fail INDEPENDENT of permissions: `chmod 000` does not stop root (the validation
# suite runs as root in the container), so a permission-based unwritable dir would let the append
# SUCCEED and silently invert this assertion. Instead point the capture file under a NONEXISTENT
# parent — the `>>` redirect then fails with ENOENT for every user, root included.
bad_cap="$TMPDIR_TEST/nonexistent-parent-dir/cap.log"
gh_stub_dir2="$TMPDIR_TEST/capfail-stubbin"
gh_stub_marker2="$TMPDIR_TEST/capfail-gh-reached"
mkdir -p "$gh_stub_dir2"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'printf reached > %q\n' "$gh_stub_marker2"
  printf '%s\n' 'exit 0'
} > "$gh_stub_dir2/gh"
chmod +x "$gh_stub_dir2/gh"
out="$(PATH="$gh_stub_dir2:$PATH" REACTMARKER_TEST_MODE=1 REACTMARKER_CAPTURE_FILE="$bad_cap" \
  bash "$REACT_MARKER" "$TOPLEVEL_NODE" toplevel "https://github.com/o/r/pull/5#issuecomment-1" 2>&1)"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'REACTMARKER_ERROR=react-failed' \
   && [ ! -f "$gh_stub_marker2" ]; then
  pass "capfail:append-failure-hard-fails" "unwritable capture -> exit=$status REACTMARKER_ERROR=react-failed, live gh NOT reached"
else
  failed "capfail:append-failure-hard-fails" "status=$status out=$out gh_reached=$([ -f "$gh_stub_marker2" ] && echo yes || echo no)"
fi

# ── LIVE path: positive proof is the ONLY definition of success (#393) ──────────
# These cases drive the LIVE run_reaction body (TEST_MODE and CAPTURE_FILE UNSET) against a PATH-shim
# `gh` that prints a canned response body on stdout and exits with a chosen status. Success requires
# ALL of: gh exit 0, the shared response check accepting the envelope, AND
# .data.addReaction.reaction.content equal to the requested EYES. Nothing text-matches a response, so a
# body whose error message mentions an existing reaction is react-failed like any other error. Each
# case asserts the shim was reached, so a case can never pass without the live path.

# make_live_gh_shim <name> <exit status> <body>: write a stub gh under the tmpdir that records it was
# reached, prints <body> on stdout, writes an unrelated line on stderr, and exits <exit status>.
# Prints the stub's bin dir.
make_live_gh_shim() {
  local shim_dir="$TMPDIR_TEST/$1-stubbin"
  local body_file="$TMPDIR_TEST/$1-body.json"
  mkdir -p "$shim_dir"
  printf '%s' "$3" > "$body_file"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'printf reached > %q\n' "$TMPDIR_TEST/$1-gh-reached"
    printf 'cat %q\n' "$body_file"
    printf '%s\n' 'echo "gh: stub stderr line" >&2'
    printf 'exit %d\n' "$2"
  } > "$shim_dir/gh"
  chmod +x "$shim_dir/gh"
  printf '%s' "$shim_dir"
}

# run_live_case <name> <exit status> <body>: run react-marker over a toplevel node on the live path
# against the shim. Sets live_status, live_stdout, live_stderr, live_reached (yes|no).
run_live_case() {
  local shim_dir
  shim_dir="$(make_live_gh_shim "$1" "$2" "$3")"
  PATH="$shim_dir:$PATH" env -u REACTMARKER_TEST_MODE -u REACTMARKER_CAPTURE_FILE \
    bash "$REACT_MARKER" "$TOPLEVEL_NODE" toplevel "https://github.com/o/r/pull/5#issuecomment-1" \
    > "$TMPDIR_TEST/$1.stdout" 2> "$TMPDIR_TEST/$1.stderr"
  live_status=$?
  live_stdout="$(cat "$TMPDIR_TEST/$1.stdout")"
  live_stderr="$(cat "$TMPDIR_TEST/$1.stderr")"
  if [ -f "$TMPDIR_TEST/$1-gh-reached" ]; then live_reached=yes; else live_reached=no; fi
}

# assert_live_react_failed <name> <label>: the live case exited 1 with exactly the react-failed
# token on stderr and the shim reached.
assert_live_react_failed() {
  if [ "$live_status" -eq 1 ] && [ "$live_reached" = yes ] \
     && printf '%s\n' "$live_stderr" | grep -qx 'REACTMARKER_ERROR=react-failed'; then
    pass "$1" "$2"
  else
    failed "$1" "status=$live_status reached=$live_reached stdout=$live_stdout stderr=$live_stderr"
  fi
}

# assert_live_success <name> <label>: the live case exited 0, silent on stdout, no error token on
# stderr, and the shim reached.
assert_live_success() {
  if [ "$live_status" -eq 0 ] && [ "$live_reached" = yes ] && [ -z "$live_stdout" ] \
     && ! printf '%s\n' "$live_stderr" | grep -q 'REACTMARKER_ERROR='; then
    pass "$1" "$2"
  else
    failed "$1" "status=$live_status reached=$live_reached stdout=$live_stdout stderr=$live_stderr"
  fi
}

# exit 0 + a top-level errors array carrying a message -> NOT success: react-failed.
run_live_case live-errors-message 0 \
  '{"data":{"addReaction":null},"errors":[{"type":"FORBIDDEN","message":"Resource not accessible by integration"}]}'
assert_live_react_failed "live:exit0-errors-message" "exit 0 + errors[{message}] -> exit 1 REACTMARKER_ERROR=react-failed"

# exit 0 + errors [{}] (no message: gh does not turn this into a non-zero exit) -> react-failed.
run_live_case live-errors-empty-object 0 '{"data":{"addReaction":null},"errors":[{}]}'
assert_live_react_failed "live:exit0-errors-empty-object" "exit 0 + errors[{}] -> exit 1 REACTMARKER_ERROR=react-failed"

# exit 0 + a clean success envelope naming the requested content -> success, silent on stdout.
run_live_case live-clean 0 '{"data":{"addReaction":{"reaction":{"content":"EYES"}}}}'
assert_live_success "live:exit0-clean" "exit 0 + clean data envelope with reaction.content EYES -> exit 0, empty stdout"

# exit 0 + errors array naming an already-present reaction -> react-failed (no text-match success path).
run_live_case live-errors-already 0 \
  '{"data":{"addReaction":null},"errors":[{"message":"Viewer has already reacted with this content"}]}'
assert_live_react_failed "live:exit0-errors-already-reacted-fails" "exit 0 + already-reacted errors -> exit 1 REACTMARKER_ERROR=react-failed"

# exit 1 + already-reacted body on stdout -> react-failed: a non-zero gh exit is never success.
run_live_case live-exit1-already 1 \
  '{"data":{"addReaction":null},"errors":[{"message":"Viewer has already reacted with this content"}]}'
assert_live_react_failed "live:exit1-already-reacted-fails" "exit 1 + already-reacted body on stdout -> exit 1 REACTMARKER_ERROR=react-failed"

# exit 0 + an errors OBJECT whose message names an existing reaction, next to an EYES payload ->
# react-failed: the envelope check rejects any non-null, non-empty errors value.
run_live_case live-errors-object-already 0 \
  '{"data":{"addReaction":{"reaction":{"content":"EYES"}}},"errors":{"message":"Viewer has already reacted with this content"}}'
assert_live_react_failed "live:exit0-errors-object-already-reacted" "exit 0 + errors{message} beside EYES payload -> exit 1 REACTMARKER_ERROR=react-failed"

# exit 0 + clean envelope with a null addReaction payload -> react-failed: no positive proof.
run_live_case live-null-payload 0 '{"data":{"addReaction":null}}'
assert_live_react_failed "live:exit0-null-payload" "exit 0 + data.addReaction null -> exit 1 REACTMARKER_ERROR=react-failed"

# exit 0 + clean envelope naming a different reaction content -> react-failed.
run_live_case live-wrong-content 0 '{"data":{"addReaction":{"reaction":{"content":"HEART"}}}}'
assert_live_react_failed "live:exit0-wrong-content" "exit 0 + reaction.content HEART -> exit 1 REACTMARKER_ERROR=react-failed"

# exit 1 + a clean EYES payload on stdout -> react-failed: the gh exit status is checked first.
run_live_case live-exit1-clean 1 '{"data":{"addReaction":{"reaction":{"content":"EYES"}}}}'
assert_live_react_failed "live:exit1-clean-payload" "exit 1 + clean EYES payload -> exit 1 REACTMARKER_ERROR=react-failed"

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "react-marker: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
