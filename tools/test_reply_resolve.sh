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
# The LIVE run_mutation path is covered too (issue #393): with every REPLYRESOLVE_* test env var unset,
# a PATH-shim `gh` tells the REPLY call from the RESOLVE call by its `query=` text and answers each with
# a canned response body and exit status, recording every call in a call log. A live mutation succeeds
# only when gh exits 0 AND the shared validator hivemind_graphql_response_check accepts the body.
#
# Every live write is bound to the current PR first (reply-resolve.sh §4 PR BINDING). Each live-path
# case therefore runs from a scratch git repo under the tmpdir (branch bugfix/fixture-branch, a fake
# https GitHub origin), never from this checkout, whose branch and remotes vary (CI checks out PRs at
# detached HEAD). The same shim answers `gh repo view` and the binding query; the binding cases assert
# each refusal and lookup failure exits 1 with its token and sends no reply or resolve.
#
# Mirrors tools/test_fetch_normalize.sh's pass/fail counter + per-case assertion + exit-nonzero-on-any
# -fail convention. Read-only: the only writes are scratch capture files and scratch git repos in a
# disposable tmpdir removed on EXIT.
#
# Usage:
#   ./tools/test_reply_resolve.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPLY_RESOLVE="$REPO_ROOT/plugin/skills/github-review-loop/scripts/reply-resolve.sh"

[ -f "$REPLY_RESOLVE" ] || { echo "FAIL: script under test missing: $REPLY_RESOLVE" >&2; exit 2; }

make_scratch_dir TMPDIR_TEST
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

# ── Live-path fixtures: scratch git repos + gh shim (PR binding, reply-resolve.sh §4) ──
# Git runs with GIT_DIR / GIT_WORK_TREE / XDG_CONFIG_HOME unset, HOME pointed at a scratch dir and the
# system config off, so no user or system git config (an insteadOf rewrite included) reaches a case.
GIT_ISOLATION_HOME="$TMPDIR_TEST/step001b-home"
mkdir -p "$GIT_ISOLATION_HOME"
FIXTURE_BRANCH="bugfix/fixture-branch"
FIXTURE_ORIGIN_URL="https://github.com/fixture-owner/fixture-repo.git"
FIXTURE_REPO_ID="R_fixtureRepo1"
LIVE_REPO_VIEW_CLEAN="{\"id\":\"$FIXTURE_REPO_ID\"}"
LIVE_REPLY_CLEAN='{"data":{"addPullRequestReviewThreadReply":{"comment":{"id":"PRRC_l1","url":"https://github.com/o/r/pull/5#discussion_r1"}}}}'
LIVE_RESOLVE_CLEAN='{"data":{"resolveReviewThread":{"thread":{"id":"PRRT_l1","isResolved":true}}}}'

# run_isolated_git <arg>...: run git under the isolation environment above.
run_isolated_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u XDG_CONFIG_HOME HOME="$GIT_ISOLATION_HOME" GIT_CONFIG_NOSYSTEM=1 git "$@"
}

# make_scratch_repo <name> <origin url, empty for none> [second push url]: create a scratch repo whose
# HEAD is $FIXTURE_BRANCH with one empty commit, and print its path. A second push url gives origin two
# push URLs.
make_scratch_repo() {
  local repo_dir="$TMPDIR_TEST/step001b-repo-$1"
  run_isolated_git init -q "$repo_dir" \
    && run_isolated_git -C "$repo_dir" symbolic-ref HEAD "refs/heads/$FIXTURE_BRANCH" \
    && run_isolated_git -C "$repo_dir" -c commit.gpgsign=false -c user.name=fixture \
      -c user.email=fixture@example.invalid commit -q --allow-empty -m fixture \
    || return 1
  if [ -n "$2" ]; then
    run_isolated_git -C "$repo_dir" remote add origin "$2" || return 1
  fi
  if [ -n "${3:-}" ]; then
    run_isolated_git -C "$repo_dir" remote set-url --add --push origin "$2" \
      && run_isolated_git -C "$repo_dir" remote set-url --add --push origin "$3" \
      || return 1
  fi
  printf '%s' "$repo_dir"
}

FIXTURE_REPO="$(make_scratch_repo main "$FIXTURE_ORIGIN_URL")" \
  || { echo "FAIL: cannot create the scratch git repo fixture" >&2; exit 2; }

# pr_thread_binding <state> <headRefName> <headRepository json>: print a binding-query response body
# for a PullRequestReviewThread node.
pr_thread_binding() {
  printf '{"data":{"node":{"__typename":"PullRequestReviewThread","pullRequest":{"state":"%s","headRefName":"%s","headRepository":%s}}}}' \
    "$1" "$2" "$3"
}
LIVE_BINDING_MATCH="$(pr_thread_binding OPEN "$FIXTURE_BRANCH" "{\"id\":\"$FIXTURE_REPO_ID\"}")"

# make_live_gh_shim <name> <repo-view status> <repo-view body> <binding status> <binding body>
#   <reply status> <reply body> <resolve status> <resolve body>: write a stub gh under the tmpdir that
# answers `gh repo view`, the binding query (`node(id:`), the reply and the resolve, each with its own
# canned stdout body and exit status, writes an unrelated stderr line, and appends the call kind to
# <name>-calls.log. The repo-view and binding argv are saved NUL-separated to <name>-<kind>.args.
# Prints the stub's bin dir.
make_live_gh_shim() {
  local shim_name="$1"
  local shim_dir="$TMPDIR_TEST/$shim_name-stubbin"
  mkdir -p "$shim_dir"
  printf '%s' "$3" > "$TMPDIR_TEST/$shim_name-repo-view-body.json"
  printf '%s' "$5" > "$TMPDIR_TEST/$shim_name-binding-body.json"
  printf '%s' "$7" > "$TMPDIR_TEST/$shim_name-reply-body.json"
  printf '%s' "$9" > "$TMPDIR_TEST/$shim_name-resolve-body.json"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'call_kind=unknown'
    printf '%s\n' 'if [ "${1:-}" = repo ] && [ "${2:-}" = view ]; then call_kind=repo-view; fi'
    printf '%s\n' 'for call_arg in "$@"; do'
    printf '%s\n' '  case "$call_arg" in'
    printf '%s\n' '    query=*addPullRequestReviewThreadReply*) call_kind=reply ;;'
    printf '%s\n' '    query=*resolveReviewThread*) call_kind=resolve ;;'
    printf '%s\n' '    query=*"node(id:"*) call_kind=binding ;;'
    printf '%s\n' '  esac'
    printf '%s\n' 'done'
    printf 'printf "%%s\\n" "$call_kind" >> %q\n' "$TMPDIR_TEST/$shim_name-calls.log"
    printf 'printf "%%s\\0" "$@" > %q-"$call_kind".args\n' "$TMPDIR_TEST/$shim_name"
    printf '%s\n' 'echo "gh: stub stderr line" >&2'
    printf '%s\n' 'case "$call_kind" in'
    printf '  repo-view) cat %q; exit %d ;;\n' "$TMPDIR_TEST/$shim_name-repo-view-body.json" "$2"
    printf '  binding) cat %q; exit %d ;;\n' "$TMPDIR_TEST/$shim_name-binding-body.json" "$4"
    printf '  reply) cat %q; exit %d ;;\n' "$TMPDIR_TEST/$shim_name-reply-body.json" "$6"
    printf '  resolve) cat %q; exit %d ;;\n' "$TMPDIR_TEST/$shim_name-resolve-body.json" "$8"
    printf '%s\n' 'esac'
    printf '%s\n' 'exit 97'
  } > "$shim_dir/gh"
  chmod +x "$shim_dir/gh"
  printf '%s' "$shim_dir"
}

# run_reply_resolve_in_repo <repo dir> <shim dir> <capture file, empty for none> <script arg>...: run
# reply-resolve.sh from <repo dir> with the shim first on PATH, the git isolation environment, and
# REPLYRESOLVE_TEST_MODE / _REPLY_STATUS / _RESOLVE_STATUS unset. REPLYRESOLVE_CAPTURE_FILE is unset
# too unless a capture file is given.
run_reply_resolve_in_repo() {
  local repo_dir="$1" shim_dir="$2" capture_file="$3"
  shift 3
  local capture_env=(-u REPLYRESOLVE_CAPTURE_FILE)
  [ -z "$capture_file" ] || capture_env=("REPLYRESOLVE_CAPTURE_FILE=$capture_file")
  (cd "$repo_dir" && env -u REPLYRESOLVE_TEST_MODE -u REPLYRESOLVE_REPLY_STATUS -u REPLYRESOLVE_RESOLVE_STATUS \
    -u GIT_DIR -u GIT_WORK_TREE -u XDG_CONFIG_HOME "${capture_env[@]}" \
    PATH="$shim_dir:$PATH" HOME="$GIT_ISOLATION_HOME" GIT_CONFIG_NOSYSTEM=1 \
    bash "$REPLY_RESOLVE" "$@")
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
# OFFLINE INVARIANT: with TEST_MODE unset and otherwise-valid inputs, the script takes
# the LIVE path: the PR binding (reply-resolve.sh §4), then `gh api graphql` mutations.
# Without a stub that would invoke the REAL gh CLI when present (network call / 45s
# timeout) despite this suite being offline. The case runs from the scratch repo with
# the shim gh answering a matching binding, so the live reply and resolve are reached.
# Asserting the shim saw the binding, reply and resolve AND the capture file stayed
# empty locks BOTH halves of the contract: the seam did NOT divert (cap empty) and the
# live path WAS taken (mutations sent to the shim).
cap="$(fresh_capture nodivert)"
nodivert_shim="$(make_live_gh_shim nodivert 0 "$LIVE_REPO_VIEW_CLEAN" 0 "$LIVE_BINDING_MATCH" \
  0 "$LIVE_REPLY_CLEAN" 0 "$LIVE_RESOLVE_CLEAN")"
run_reply_resolve_in_repo "$FIXTURE_REPO" "$nodivert_shim" "$cap" \
  --resolve-eligible -- PRRT_iii xyz789 "No test mode" thread "" >/dev/null 2>&1
nodivert_calls="$(tr '\n' ',' 2>/dev/null < "$TMPDIR_TEST/nodivert-calls.log")"
if [ ! -s "$cap" ] && [ "$nodivert_calls" = "repo-view,binding,reply,resolve," ]; then
  pass "failclosed:capture-without-testmode-no-divert" "CAPTURE_FILE alone did NOT divert (cap empty); live binding, reply and resolve reached the shim"
else
  failed "failclosed:capture-without-testmode-no-divert" "diverted or live-path-not-reached — cap=$(cat "$cap") calls=$nodivert_calls"
fi

# ── Capture mode makes no git call: a run from a non-git directory still captures ──
# The PR binding is skipped while the capture seam is engaged (reply-resolve.sh §5), so a capture-mode
# run needs no git repository and reaches no gh. GIT_CEILING_DIRECTORIES stops git discovery at the
# tmpdir, so the directory is non-git whatever lies above it.
nongit_dir="$TMPDIR_TEST/step001b-nongit"
mkdir -p "$nongit_dir"
cap="$(fresh_capture nongit)"
nongit_shim="$(make_live_gh_shim nongit 0 "$LIVE_REPO_VIEW_CLEAN" 0 "$LIVE_BINDING_MATCH" \
  0 "$LIVE_REPLY_CLEAN" 0 "$LIVE_RESOLVE_CLEAN")"
out="$(cd "$nongit_dir" && env -u GIT_DIR -u GIT_WORK_TREE GIT_CEILING_DIRECTORIES="$TMPDIR_TEST" \
  PATH="$nongit_shim:$PATH" REPLYRESOLVE_TEST_MODE=1 REPLYRESOLVE_CAPTURE_FILE="$cap" \
  bash "$REPLY_RESOLVE" --resolve-eligible -- PRRT_ng abc123 "Non-git capture" thread "" 2>&1)"
status=$?
expected_nongit_cap="$(printf 'REPLY thread=PRRT_ng body=Fixed in abc123. Non-git capture.\nRESOLVE thread=PRRT_ng')"
if [ "$status" -eq 0 ] && [ -z "$out" ] && [ "$(cat "$cap")" = "$expected_nongit_cap" ] \
   && [ ! -e "$TMPDIR_TEST/nongit-calls.log" ]; then
  pass "capture:non-git-dir-captures" "capture mode from a non-git dir captured reply then resolve, no gh call, exit 0"
else
  failed "capture:non-git-dir-captures" "status=$status out=$out cap=$(cat "$cap") calls=$(cat "$TMPDIR_TEST/nongit-calls.log" 2>/dev/null)"
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

# ── LIVE path: shared GraphQL response check over both mutations (#393) ───────────
# These cases drive the LIVE run_mutation body (every REPLYRESOLVE_* test env var UNSET) from the
# scratch repo against the PATH-shim `gh` (make_live_gh_shim above). The shim classifies each call
# (repo view, binding query, reply, resolve), appends the kind to a call log, prints that kind's canned
# body on stdout, writes an unrelated line on stderr, and exits with that kind's status. gh exits 0 on
# several GraphQL error envelopes, so success must require BOTH exit 0 AND the shared response check
# passing. The call log proves which mutations went live and in what order, so no case can pass
# without reaching the live path.

# run_bound_case <name> <repo dir> <repo-view status> <repo-view body> <binding status> <binding body>
#   <reply status> <reply body> <resolve status> <resolve body>: run reply-resolve over a
# resolve-eligible thread candidate (PRRT_l1) from <repo dir> on the live path against a fresh shim.
# Sets live_status, live_stdout, live_stderr, live_all_calls (every gh call kind, comma-joined) and
# live_calls (the reply / resolve mutation kinds only, one per line; empty when none was sent).
run_bound_case() {
  local case_name="$1" repo_dir="$2" shim_dir
  shift 2
  shim_dir="$(make_live_gh_shim "$case_name" "$@")"
  run_reply_resolve_in_repo "$repo_dir" "$shim_dir" "" --resolve-eligible -- PRRT_l1 abc123 "Live fix" thread "" \
    > "$TMPDIR_TEST/$case_name.stdout" 2> "$TMPDIR_TEST/$case_name.stderr"
  live_status=$?
  live_stdout="$(cat "$TMPDIR_TEST/$case_name.stdout")"
  live_stderr="$(cat "$TMPDIR_TEST/$case_name.stderr")"
  live_all_calls="$(tr '\n' ',' 2>/dev/null < "$TMPDIR_TEST/$case_name-calls.log")"
  live_calls="$(grep -E '^(reply|resolve)$' "$TMPDIR_TEST/$case_name-calls.log" 2>/dev/null)"
}

# run_live_case <name> <reply status> <reply body> <resolve status> <resolve body>: run_bound_case
# from the fixture repo with a matching PR binding, so the case exercises the mutations alone.
run_live_case() {
  run_bound_case "$1" "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" 0 "$LIVE_BINDING_MATCH" "$2" "$3" "$4" "$5"
}

# assert_live_reply_failed <name> <label>: the live case exited 1 with exactly the reply-failed token
# on stdout, and the call log shows the reply went live and NO resolve was sent.
assert_live_reply_failed() {
  if [ "$live_status" -eq 1 ] && [ "$live_stdout" = "REPLYRESOLVE_ERROR=reply-failed" ] \
     && [ "$live_calls" = "reply" ]; then
    pass "$1" "$2"
  else
    failed "$1" "status=$live_status stdout=$live_stdout calls=$(printf '%s' "$live_calls" | tr '\n' ',') stderr=$live_stderr"
  fi
}

# assert_live_resolve_failed <name> <label>: the live case exited 0 silent on stdout, the call log
# shows the reply then the resolve went live, and stderr carries REPLYRESOLVE_RESOLVE_FAILED.
assert_live_resolve_failed() {
  if [ "$live_status" -eq 0 ] && [ -z "$live_stdout" ] && [ "$live_calls" = "$(printf 'reply\nresolve')" ] \
     && printf '%s\n' "$live_stderr" | grep -q 'REPLYRESOLVE_RESOLVE_FAILED'; then
    pass "$1" "$2"
  else
    failed "$1" "status=$live_status stdout=$live_stdout calls=$(printf '%s' "$live_calls" | tr '\n' ',') stderr=$live_stderr"
  fi
}

# exit 0 + a top-level errors array carrying a message on the REPLY -> reply-failed, no resolve sent.
run_live_case live-reply-errors-message 0 \
  '{"data":{"addPullRequestReviewThreadReply":null},"errors":[{"type":"FORBIDDEN","message":"Resource not accessible by integration"}]}' \
  0 "$LIVE_RESOLVE_CLEAN"
assert_live_reply_failed "live:reply-exit0-errors-message" "reply exit 0 + errors[{message}] -> exit 1 reply-failed, no resolve sent"

# exit 0 + errors [{}] on the REPLY (no message: gh does not turn this into a non-zero exit).
run_live_case live-reply-errors-empty-object 0 '{"data":{"addPullRequestReviewThreadReply":null},"errors":[{}]}' \
  0 "$LIVE_RESOLVE_CLEAN"
assert_live_reply_failed "live:reply-exit0-errors-empty-object" "reply exit 0 + errors[{}] -> exit 1 reply-failed, no resolve sent"

# non-zero gh exit on the REPLY -> reply-failed, no resolve sent (the exit status still decides first).
run_live_case live-reply-nonzero 1 "$LIVE_REPLY_CLEAN" 0 "$LIVE_RESOLVE_CLEAN"
assert_live_reply_failed "live:reply-nonzero-exit" "reply exit 1 -> exit 1 reply-failed, no resolve sent"

# clean REPLY + exit 0 RESOLVE carrying errors -> REPLYRESOLVE_RESOLVE_FAILED, still exit 0.
run_live_case live-resolve-errors 0 "$LIVE_REPLY_CLEAN" \
  0 '{"data":{"resolveReviewThread":null},"errors":[{"type":"FORBIDDEN","message":"Resource not accessible by integration"}]}'
assert_live_resolve_failed "live:resolve-exit0-errors-non-blocking" "resolve exit 0 + errors -> RESOLVE_FAILED on stderr, exit 0, reply then resolve"

# ── LIVE path: positive proof of the requested object (reply-resolve.sh §4 RESPONSE CHECK) ──
# A clean envelope is not success: exit 0 with no `errors` and an object `data` still proves nothing
# when the mutation payload is null. A REPLY must carry a non-empty comment id; a RESOLVE must report
# the thread isResolved true.

# exit 0 + clean envelope + null reply payload -> reply-failed, no resolve sent.
run_live_case live-reply-null-payload 0 '{"data":{"addPullRequestReviewThreadReply":null}}' \
  0 "$LIVE_RESOLVE_CLEAN"
assert_live_reply_failed "live:reply-exit0-null-payload" "reply exit 0 + null payload -> exit 1 reply-failed, no resolve sent"

# exit 0 + clean envelope + null comment -> reply-failed, no resolve sent.
run_live_case live-reply-comment-null 0 '{"data":{"addPullRequestReviewThreadReply":{"comment":null}}}' \
  0 "$LIVE_RESOLVE_CLEAN"
assert_live_reply_failed "live:reply-exit0-comment-null" "reply exit 0 + comment null -> exit 1 reply-failed, no resolve sent"

# exit 0 + clean envelope + empty-string comment id -> reply-failed (the id must be NON-EMPTY).
run_live_case live-reply-comment-id-empty 0 '{"data":{"addPullRequestReviewThreadReply":{"comment":{"id":"","url":""}}}}' \
  0 "$LIVE_RESOLVE_CLEAN"
assert_live_reply_failed "live:reply-exit0-comment-id-empty" "reply exit 0 + empty comment id -> exit 1 reply-failed, no resolve sent"

# clean REPLY + exit 0 RESOLVE reporting isResolved false -> RESOLVE_FAILED, still exit 0.
run_live_case live-resolve-not-resolved 0 "$LIVE_REPLY_CLEAN" \
  0 '{"data":{"resolveReviewThread":{"thread":{"id":"PRRT_l1","isResolved":false}}}}'
assert_live_resolve_failed "live:resolve-exit0-not-resolved" "resolve exit 0 + isResolved false -> RESOLVE_FAILED on stderr, exit 0, reply then resolve"

# clean REPLY + exit 0 RESOLVE with a null payload -> RESOLVE_FAILED, still exit 0.
run_live_case live-resolve-null-payload 0 "$LIVE_REPLY_CLEAN" 0 '{"data":{"resolveReviewThread":null}}'
assert_live_resolve_failed "live:resolve-exit0-null-payload" "resolve exit 0 + null payload -> RESOLVE_FAILED on stderr, exit 0, reply then resolve"

# clean REPLY + clean RESOLVE -> exit 0, silent on stdout, no RESOLVE_FAILED, reply then resolve.
run_live_case live-both-clean 0 "$LIVE_REPLY_CLEAN" 0 "$LIVE_RESOLVE_CLEAN"
if [ "$live_status" -eq 0 ] && [ -z "$live_stdout" ] && [ "$live_calls" = "$(printf 'reply\nresolve')" ] \
   && ! printf '%s\n' "$live_stderr" | grep -q 'REPLYRESOLVE_RESOLVE_FAILED'; then
  pass "live:both-clean" "clean reply + clean resolve -> exit 0, empty stdout, no RESOLVE_FAILED, reply then resolve"
else
  failed "live:both-clean" "status=$live_status stdout=$live_stdout calls=$(printf '%s' "$live_calls" | tr '\n' ',') stderr=$live_stderr"
fi

# The binding lookups the both-clean case sent: `gh repo view` read the origin push URL, and the binding
# query carried the thread id ONLY as the threadId variable, never spliced into the query text.
both_clean_repo_view_args="$(tr '\0' ' ' 2>/dev/null < "$TMPDIR_TEST/live-both-clean-repo-view.args")"
both_clean_binding_args="$(tr '\0' '\n' 2>/dev/null < "$TMPDIR_TEST/live-both-clean-binding.args")"
if [ "$live_all_calls" = "repo-view,binding,reply,resolve," ] \
   && [ "$both_clean_repo_view_args" = "repo view --json id -- $FIXTURE_ORIGIN_URL " ] \
   && printf '%s\n' "$both_clean_binding_args" | grep -qx 'threadId=PRRT_l1' \
   && [ "$(printf '%s\n' "$both_clean_binding_args" | grep -c 'PRRT_l1')" -eq 1 ]; then
  pass "binding:lookups-before-mutations" "repo view then binding query before reply and resolve; origin URL passed; thread id only as a variable"
else
  failed "binding:lookups-before-mutations" "calls=$live_all_calls repo_view_args=$both_clean_repo_view_args binding_args=$both_clean_binding_args"
fi

# ── LIVE path: PR binding (reply-resolve.sh §4 PR BINDING) ────────────────────────
# Each case runs from a scratch repo on bugfix/fixture-branch with clean reply and resolve bodies, so
# only the binding decides. A failure must exit 1 with its exact token on stdout and send NO reply or
# resolve; the full call log shows how far the binding got.

# run_binding_case <name> <repo dir> <repo-view status> <repo-view body> <binding status> <binding body>
run_binding_case() {
  run_bound_case "$1" "$2" "$3" "$4" "$5" "$6" 0 "$LIVE_REPLY_CLEAN" 0 "$LIVE_RESOLVE_CLEAN"
}

# assert_binding_fail <name> <token> <expected gh calls, comma-joined> <label>: the binding case exited
# 1 with exactly REPLYRESOLVE_ERROR=<token> on stdout, sent no reply or resolve, and made exactly the
# expected gh calls.
assert_binding_fail() {
  if [ "$live_status" -eq 1 ] && [ "$live_stdout" = "REPLYRESOLVE_ERROR=$2" ] && [ -z "$live_calls" ] \
     && [ "$live_all_calls" = "$3" ]; then
    pass "$1" "$4"
  else
    failed "$1" "status=$live_status stdout=$live_stdout calls=$live_all_calls stderr=$live_stderr"
  fi
}

# pr-binding-refused: the lookup succeeded but the thread is not on the current branch's open PR.
run_binding_case binding-other-pr "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" \
  0 "$(pr_thread_binding OPEN feature/other-branch "{\"id\":\"$FIXTURE_REPO_ID\"}")"
assert_binding_fail "binding:refused-other-pr-same-repo" pr-binding-refused "repo-view,binding," \
  "thread on another PR of the same repo -> exit 1 pr-binding-refused, no reply or resolve"

run_binding_case binding-other-repo "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" \
  0 "$(pr_thread_binding OPEN "$FIXTURE_BRANCH" '{"id":"R_forkRepo9"}')"
assert_binding_fail "binding:refused-same-branch-other-repo" pr-binding-refused "repo-view,binding," \
  "PR head has the same branch name in another repo -> exit 1 pr-binding-refused, no reply or resolve"

run_binding_case binding-closed "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" \
  0 "$(pr_thread_binding CLOSED "$FIXTURE_BRANCH" "{\"id\":\"$FIXTURE_REPO_ID\"}")"
assert_binding_fail "binding:refused-closed-pr" pr-binding-refused "repo-view,binding," \
  "CLOSED PR -> exit 1 pr-binding-refused, no reply or resolve"

run_binding_case binding-merged "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" \
  0 "$(pr_thread_binding MERGED "$FIXTURE_BRANCH" "{\"id\":\"$FIXTURE_REPO_ID\"}")"
assert_binding_fail "binding:refused-merged-pr" pr-binding-refused "repo-view,binding," \
  "MERGED PR -> exit 1 pr-binding-refused, no reply or resolve"

run_binding_case binding-issue-comment "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" \
  0 '{"data":{"node":{"__typename":"IssueComment"}}}'
assert_binding_fail "binding:refused-issue-comment-node" pr-binding-refused "repo-view,binding," \
  "IssueComment node -> exit 1 pr-binding-refused, no reply or resolve"

run_binding_case binding-null-node "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" 0 '{"data":{"node":null}}'
assert_binding_fail "binding:refused-null-node" pr-binding-refused "repo-view,binding," \
  "null node -> exit 1 pr-binding-refused, no reply or resolve"

run_binding_case binding-null-head-repo "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" \
  0 "$(pr_thread_binding OPEN "$FIXTURE_BRANCH" null)"
assert_binding_fail "binding:refused-null-head-repository" pr-binding-refused "repo-view,binding," \
  "null headRepository -> exit 1 pr-binding-refused, no reply or resolve"

# pr-binding-lookup-failed: the branch is known but the origin repository or the thread cannot be read.
run_binding_case binding-query-nonzero "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" 1 "$LIVE_BINDING_MATCH"
assert_binding_fail "binding:lookup-failed-query-nonzero-exit" pr-binding-lookup-failed "repo-view,binding," \
  "binding query exit 1 -> exit 1 pr-binding-lookup-failed, no reply or resolve"

run_binding_case binding-not-found "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" \
  0 '{"data":{"node":null},"errors":[{"type":"NOT_FOUND","path":["node"],"message":"Could not resolve to a node with the global id of '"'"'PRRT_l1'"'"'"}]}'
assert_binding_fail "binding:lookup-failed-exit0-not-found" pr-binding-lookup-failed "repo-view,binding," \
  "binding query exit 0 + NOT_FOUND errors -> exit 1 pr-binding-lookup-failed, no reply or resolve"

run_binding_case binding-non-json "$FIXTURE_REPO" 0 "$LIVE_REPO_VIEW_CLEAN" 0 'not json at all'
assert_binding_fail "binding:lookup-failed-non-json-body" pr-binding-lookup-failed "repo-view,binding," \
  "binding query non-JSON body -> exit 1 pr-binding-lookup-failed, no reply or resolve"

run_binding_case binding-repo-view-fails "$FIXTURE_REPO" 1 "$LIVE_REPO_VIEW_CLEAN" 0 "$LIVE_BINDING_MATCH"
assert_binding_fail "binding:lookup-failed-repo-view-fails" pr-binding-lookup-failed "repo-view," \
  "gh repo view exit 1 -> exit 1 pr-binding-lookup-failed, no binding query, no reply or resolve"

run_binding_case binding-repo-view-bad-id "$FIXTURE_REPO" 0 '{"id":"R bad id"}' 0 "$LIVE_BINDING_MATCH"
assert_binding_fail "binding:lookup-failed-repo-view-bad-id" pr-binding-lookup-failed "repo-view," \
  "gh repo view id outside the charset -> exit 1 pr-binding-lookup-failed, no reply or resolve"

no_origin_repo="$(make_scratch_repo no-origin "")" \
  || { echo "FAIL: cannot create the no-origin scratch repo" >&2; exit 2; }
run_binding_case binding-no-origin "$no_origin_repo" 0 "$LIVE_REPO_VIEW_CLEAN" 0 "$LIVE_BINDING_MATCH"
assert_binding_fail "binding:lookup-failed-no-origin" pr-binding-lookup-failed "" \
  "no origin remote -> exit 1 pr-binding-lookup-failed, gh never reached"

at_url_repo="$(make_scratch_repo at-url "https://x-access-token:fixture@github.com/fixture-owner/fixture-repo.git")" \
  || { echo "FAIL: cannot create the at-url scratch repo" >&2; exit 2; }
run_binding_case binding-at-url "$at_url_repo" 0 "$LIVE_REPO_VIEW_CLEAN" 0 "$LIVE_BINDING_MATCH"
assert_binding_fail "binding:lookup-failed-https-url-with-at" pr-binding-lookup-failed "" \
  "https origin URL holding @ -> exit 1 pr-binding-lookup-failed, gh never reached"

two_push_repo="$(make_scratch_repo two-push "$FIXTURE_ORIGIN_URL" "https://github.com/fixture-owner/fixture-mirror.git")" \
  || { echo "FAIL: cannot create the two-push scratch repo" >&2; exit 2; }
run_binding_case binding-two-push "$two_push_repo" 0 "$LIVE_REPO_VIEW_CLEAN" 0 "$LIVE_BINDING_MATCH"
assert_binding_fail "binding:lookup-failed-two-push-urls" pr-binding-lookup-failed "" \
  "two push URLs on origin -> exit 1 pr-binding-lookup-failed, gh never reached"

# pr-binding-no-branch: a detached HEAD has no branch to bind to, so gh is never reached.
detached_repo="$(make_scratch_repo detached "$FIXTURE_ORIGIN_URL")" \
  && run_isolated_git -C "$detached_repo" checkout -q --detach \
  || { echo "FAIL: cannot create the detached scratch repo" >&2; exit 2; }
run_binding_case binding-detached "$detached_repo" 0 "$LIVE_REPO_VIEW_CLEAN" 0 "$LIVE_BINDING_MATCH"
assert_binding_fail "binding:no-branch-detached-head" pr-binding-no-branch "" \
  "detached HEAD -> exit 1 pr-binding-no-branch, gh never reached"

# An ssh-form origin passes the URL gate: the binding matches and the reply and resolve go live.
ssh_repo="$(make_scratch_repo ssh-origin "git@github.com:fixture-owner/fixture-repo.git")" \
  || { echo "FAIL: cannot create the ssh-origin scratch repo" >&2; exit 2; }
run_binding_case binding-ssh-origin "$ssh_repo" 0 "$LIVE_REPO_VIEW_CLEAN" 0 "$LIVE_BINDING_MATCH"
if [ "$live_status" -eq 0 ] && [ -z "$live_stdout" ] && [ "$live_all_calls" = "repo-view,binding,reply,resolve," ]; then
  pass "binding:ssh-origin-bound" "git@ origin + matching binding -> reply and resolve sent, exit 0"
else
  failed "binding:ssh-origin-bound" "status=$live_status stdout=$live_stdout calls=$live_all_calls stderr=$live_stderr"
fi

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "reply-resolve: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
