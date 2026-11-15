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
# The live-path cases (#393) leave the capture seam unset, run from a scratch git repo under the tmpdir
# (branch bugfix/fixture-branch, a fake https GitHub origin) and put a stub `gh` first on PATH that
# answers `gh repo view`, the PR binding lookup and the addReaction mutation with canned bodies. They
# lock the single definition of live success — gh exit 0, the shared response check passing, AND
# .data.addReaction.reaction.content == EYES — and assert every other response (error envelopes,
# already-reacted wording, a null payload, a different content, a non-zero exit) is
# REACTMARKER_ERROR=react-failed. The PR binding cases assert a node outside the current open PR is
# pr-binding-refused, a failed lookup is pr-binding-lookup-failed, and a detached HEAD is
# pr-binding-no-branch, each with no reaction sent.
#
# The noise-mode cases (#568) pass --noise <reviewer_filter> and assert the binding node's author
# decides: a Bot account inside the filter is marked; a human, a Bot outside the filter or a null
# author is noise-author-refused with no mutation sent. They also cover missing-value-for-noise,
# missing-identity-module, the capture seam skipping the author check, and fix mode marking a
# human-authored node. The re-mark refresh cases assert a viewer EYES already on the node is removed
# (removeReaction) before addReaction, and that a removal lacking positive proof is react-failed with
# addReaction never sent. Cases that must not reach gh put a failing gh stub first on PATH.
#
# Mirrors tools/test_reply_resolve.sh's pass/fail counter + per-case assertion + exit-nonzero-on-any
# -fail convention. Read-only: the only writes are scratch capture files, scratch repos and shim
# files in a disposable tmpdir removed on EXIT.
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


# ── Live-path fixtures: scratch git repo + gh shim ──────────────────────────────────
# Every live-path case runs from a scratch git repo under the tmpdir, never from the hivemind checkout
# (CI checks PRs out at a detached HEAD, so the checkout's own branch and remotes are unusable). Git
# runs with GIT_DIR and GIT_WORK_TREE unset, HOME and XDG_CONFIG_HOME pointed at an empty scratch home
# and GIT_CONFIG_NOSYSTEM=1, so no user or system config (url rewrites included) reaches the binding.
#
# The gh shim tells apart its four calls: `gh repo view` (the origin repository id), the binding
# `gh api graphql` lookup, the removeReaction mutation of the re-mark refresh (part unreact, a query=
# argument naming removeReaction) and the addReaction mutation (part react, a query= argument naming
# addReaction). Each call appends its part name to calls.log (the call order), records a
# <part>-reached marker and its arguments under the case dir named by FIXTURE_GH_CASE_DIR, prints
# <part>.body on stdout, writes an unrelated line on stderr and exits <part>.status. live_reached
# means the addReaction MUTATION was reached.
FIXTURE_BRANCH="bugfix/fixture-branch"
FIXTURE_ORIGIN_URL="https://github.com/fixture-owner/fixture-repo.git"
FIXTURE_REPO_ID="R_kgDOFixture1"
FIXTURE_HOME="$TMPDIR_TEST/home"
mkdir -p "$FIXTURE_HOME/.config"

# fixture_git <args...>: run git with the scratch home and no system config, GIT_DIR/GIT_WORK_TREE unset.
fixture_git() {
  env -u GIT_DIR -u GIT_WORK_TREE HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_HOME/.config" \
    GIT_CONFIG_NOSYSTEM=1 git "$@"
}

# make_fixture_repo <name>: init a scratch repo on branch bugfix/fixture-branch with no remote. Prints
# its path.
make_fixture_repo() {
  local repo_dir="$TMPDIR_TEST/repo-$1"
  fixture_git init -q "$repo_dir" >/dev/null 2>&1
  fixture_git -C "$repo_dir" symbolic-ref HEAD "refs/heads/$FIXTURE_BRANCH"
  printf '%s' "$repo_dir"
}

BOUND_REPO="$(make_fixture_repo bound)"
fixture_git -C "$BOUND_REPO" remote add origin "$FIXTURE_ORIGIN_URL"

NO_ORIGIN_REPO="$(make_fixture_repo no-origin)"

AT_ORIGIN_REPO="$(make_fixture_repo at-origin)"
fixture_git -C "$AT_ORIGIN_REPO" remote add origin "https://token@github.com/fixture-owner/fixture-repo.git"

TWO_PUSH_REPO="$(make_fixture_repo two-push)"
fixture_git -C "$TWO_PUSH_REPO" remote add origin "$FIXTURE_ORIGIN_URL"
fixture_git -C "$TWO_PUSH_REPO" remote set-url --add --push origin "$FIXTURE_ORIGIN_URL"
fixture_git -C "$TWO_PUSH_REPO" remote set-url --add --push origin "https://github.com/fixture-owner/other-repo.git"

DETACHED_REPO="$(make_fixture_repo detached)"
fixture_git -C "$DETACHED_REPO" remote add origin "$FIXTURE_ORIGIN_URL"
fixture_git -C "$DETACHED_REPO" -c user.name=fixture -c user.email=fixture@example.invalid \
  -c commit.gpgsign=false commit -q --allow-empty -m fixture
fixture_git -C "$DETACHED_REPO" checkout -q --detach

NON_GIT_DIR="$TMPDIR_TEST/non-git"
mkdir -p "$NON_GIT_DIR"

GH_SHIM_DIR="$TMPDIR_TEST/gh-shim-bin"
mkdir -p "$GH_SHIM_DIR"
cat > "$GH_SHIM_DIR/gh" <<'SHIM'
#!/usr/bin/env bash
case_dir="$FIXTURE_GH_CASE_DIR"
if [ "${1:-}" = repo ] && [ "${2:-}" = view ]; then
  part=repo
elif [ "${1:-}" = api ] && [ "${2:-}" = graphql ]; then
  part=binding
  for arg in "$@"; do
    case "$arg" in
      query=*addReaction*) part=react ;;
      query=*removeReaction*) part=unreact ;;
    esac
  done
else
  printf '%s\n' "$*" > "$case_dir/unexpected-reached"
  exit 99
fi
printf '%s\n' "$part" >> "$case_dir/calls.log"
printf reached > "$case_dir/$part-reached"
printf '%s\n' "$@" > "$case_dir/$part.args"
cat "$case_dir/$part.body"
echo "gh: stub stderr line" >&2
exit "$(cat "$case_dir/$part.status")"
SHIM
chmod +x "$GH_SHIM_DIR/gh"

GIT_SHIM_DIR="$TMPDIR_TEST/git-shim-bin"
mkdir -p "$GIT_SHIM_DIR"
cat > "$GIT_SHIM_DIR/git" <<'SHIM'
#!/usr/bin/env bash
printf reached > "$FIXTURE_GH_CASE_DIR/git-reached"
exit 99
SHIM
chmod +x "$GIT_SHIM_DIR/git"

# A failing gh stub for cases that must never reach gh: it records gh-reached and exits 97.
FAIL_GH_SHIM_DIR="$TMPDIR_TEST/fail-gh-shim-bin"
mkdir -p "$FAIL_GH_SHIM_DIR"
cat > "$FAIL_GH_SHIM_DIR/gh" <<'SHIM'
#!/usr/bin/env bash
printf reached > "$FIXTURE_GH_CASE_DIR/gh-reached"
exit 97
SHIM
chmod +x "$FAIL_GH_SHIM_DIR/gh"

# Author and reaction-group JSON for the binding node. Bot names appear only in these fixtures.
CODEX_BOT_AUTHOR='{"login":"chatgpt-codex-connector","__typename":"Bot"}'
COPILOT_BOT_AUTHOR='{"login":"copilot-pull-request-reviewer","__typename":"Bot"}'
OTHER_BOT_AUTHOR='{"login":"fixture-lint-app","__typename":"Bot"}'
HUMAN_AUTHOR='{"login":"fixture-human","__typename":"User"}'
VIEWER_EYES_GROUPS='[{"content":"THUMBS_UP","viewerHasReacted":false},{"content":"EYES","viewerHasReacted":true}]'
OTHER_EYES_GROUPS='[{"content":"EYES","viewerHasReacted":false}]'

# bound_node_body <typename> [author json] [reactionGroups json]: a binding response whose node is
# <typename> on the OPEN fixture PR, authored by <author json> (default the Codex Bot) and carrying
# <reactionGroups json> (default []).
bound_node_body() {
  printf '{"data":{"node":{"__typename":"%s","pullRequest":{"state":"OPEN","headRefName":"%s","headRepository":{"id":"%s"}},"author":%s,"reactionGroups":%s}}}' \
    "$1" "$FIXTURE_BRANCH" "$FIXTURE_REPO_ID" "${2:-$CODEX_BOT_AUTHOR}" "${3:-[]}"
}

# set_gh_part <part> <exit status> <body>: set one shim response (repo | binding | unreact | react)
# for the current case dir.
set_gh_part() {
  printf '%s' "$3" > "$case_dir/$1.body"
  printf '%s' "$2" > "$case_dir/$1.status"
}

# new_gh_case <name> <surface>: create a fresh case dir whose repo view and binding match the fixture
# repo for <surface> (toplevel IssueComment, review PullRequestReview) and whose reaction is a clean
# EYES success; a removal, when reached, proves no viewer EYES remains. Sets case_dir.
new_gh_case() {
  local node_type="IssueComment"
  [ "$2" = review ] && node_type="PullRequestReview"
  case_dir="$TMPDIR_TEST/case-$1"
  mkdir -p "$case_dir"
  set_gh_part repo 0 "{\"id\":\"$FIXTURE_REPO_ID\"}"
  set_gh_part binding 0 "$(bound_node_body "$node_type")"
  set_gh_part unreact 0 '{"data":{"removeReaction":{"reactionGroups":[{"content":"EYES","viewerHasReacted":false}]}}}'
  set_gh_part react 0 '{"data":{"addReaction":{"reaction":{"content":"EYES"}}}}'
}

# reached_flag <part>: print yes when the shim recorded <part>-reached in the current case dir, else no.
reached_flag() {
  if [ -f "$case_dir/$1-reached" ]; then printf yes; else printf no; fi
}

# call_order: print the shim's recorded call order for the current case dir on one line.
call_order() {
  if [ -f "$case_dir/calls.log" ]; then tr '\n' ' ' < "$case_dir/calls.log"; fi
}

# MARKER_FLAGS: flags run_bound_case passes before the positionals (empty = fix mode).
MARKER_FLAGS=()

# run_bound_case <repo dir> <node id> <surface> [env assignments...]: run react-marker on the live path
# from <repo dir> against the gh shim of the current case dir, with MARKER_FLAGS before the
# positionals. Sets live_status, live_stdout, live_stderr, live_reached (the mutation), repo_reached,
# binding_reached, unreact_reached.
run_bound_case() {
  local repo_dir="$1" node_id="$2" surface="$3"
  shift 3
  (
    cd "$repo_dir" || exit 98
    env -u GIT_DIR -u GIT_WORK_TREE -u REACTMARKER_TEST_MODE -u REACTMARKER_CAPTURE_FILE \
      HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_HOME/.config" GIT_CONFIG_NOSYSTEM=1 \
      PATH="$GH_SHIM_DIR:$PATH" FIXTURE_GH_CASE_DIR="$case_dir" "$@" \
      bash "$REACT_MARKER" ${MARKER_FLAGS[@]+"${MARKER_FLAGS[@]}"} "$node_id" "$surface" \
      "https://github.com/fixture-owner/fixture-repo/pull/5"
  ) > "$case_dir/run.stdout" 2> "$case_dir/run.stderr"
  live_status=$?
  live_stdout="$(cat "$case_dir/run.stdout")"
  live_stderr="$(cat "$case_dir/run.stderr")"
  live_reached="$(reached_flag react)"
  repo_reached="$(reached_flag repo)"
  binding_reached="$(reached_flag binding)"
  unreact_reached="$(reached_flag unreact)"
}

# ── Fail-closed gate lock: CAPTURE_FILE WITHOUT TEST_MODE does NOT divert ────────────
# The capture seam requires BOTH REACTMARKER_TEST_MODE=1 AND REACTMARKER_CAPTURE_FILE. A stray
# CAPTURE_FILE ALONE must NOT divert — the mutation goes LIVE to gh. We assert the gate's observable
# contract: with TEST_MODE absent the capture file is NEVER written (the seam stayed inactive and the
# code fell through to the live path). NOTE: TEST_MODE is deliberately UNSET here.
#
# OFFLINE INVARIANT: with TEST_MODE unset, the script takes the LIVE path: the PR binding, then
# `gh api graphql`. It runs from the bound scratch repo against the gh shim, whose binding matches and
# whose mutation exits non-zero, so no real CLI runs. Asserting the mutation was reached AND the
# capture file stayed empty locks BOTH halves of the contract: the seam did NOT divert (cap empty) and
# the live path WAS taken (mutation reached).
cap="$(fresh_capture nodivert)"
new_gh_case nodivert toplevel
set_gh_part react 1 ''
run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel REACTMARKER_CAPTURE_FILE="$cap"
if [ ! -s "$cap" ] && [ "$live_reached" = yes ]; then
  pass "failclosed:capture-without-testmode-no-divert" "CAPTURE_FILE alone did NOT divert (cap empty); live mutation reached"
else
  failed "failclosed:capture-without-testmode-no-divert" "diverted or live-path-not-reached — cap=$(cat "$cap") mutation_reached=$live_reached stderr=$live_stderr"
fi

# ── Capture-append failure is a HARD failure, NOT a false success (#265 regression) ──
# When the seam is ACTIVE (TEST_MODE=1 + CAPTURE_FILE) but the capture path is UNWRITABLE, the append
# fails. With set -e deliberately omitted (P18 floor), an UNGUARDED append would be silently ignored
# and run_reaction would still return the default-0 simulated status — reporting marker SUCCESS while
# NOTHING was captured and the live gh mutation was bypassed. The `|| return 1` guard converts that
# into react-failed. Assert: exit non-zero, REACTMARKER_ERROR=react-failed, and gh is NEVER reached
# (the active seam skips the PR binding and hard-fails on the append, never falling through to live).
# REACTMARKER_REACT_STATUS is left at its default 0 so the ONLY failure source under test is the
# append itself.
#
# The write must fail INDEPENDENT of permissions: `chmod 000` does not stop root (the validation
# suite runs as root in the container), so a permission-based unwritable dir would let the append
# SUCCEED and silently invert this assertion. Instead point the capture file under a NONEXISTENT
# parent — the `>>` redirect then fails with ENOENT for every user, root included.
bad_cap="$TMPDIR_TEST/nonexistent-parent-dir/cap.log"
new_gh_case capfail toplevel
out="$(PATH="$GH_SHIM_DIR:$PATH" FIXTURE_GH_CASE_DIR="$case_dir" REACTMARKER_TEST_MODE=1 \
  REACTMARKER_CAPTURE_FILE="$bad_cap" \
  bash "$REACT_MARKER" "$TOPLEVEL_NODE" toplevel "https://github.com/o/r/pull/5#issuecomment-1" 2>&1)"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'REACTMARKER_ERROR=react-failed' \
   && [ "$(reached_flag repo)" = no ] && [ "$(reached_flag binding)" = no ] \
   && [ "$(reached_flag react)" = no ]; then
  pass "capfail:append-failure-hard-fails" "unwritable capture -> exit=$status REACTMARKER_ERROR=react-failed, gh NOT reached"
else
  failed "capfail:append-failure-hard-fails" "status=$status out=$out repo=$(reached_flag repo) binding=$(reached_flag binding) react=$(reached_flag react)"
fi

# ── LIVE path: positive proof is the ONLY definition of success (#393) ──────────
# These cases drive the LIVE run_reaction body (TEST_MODE and CAPTURE_FILE UNSET) from the bound
# scratch repo against the gh shim, with a binding that matches the fixture PR. The mutation prints a
# canned response body on stdout and exits with a chosen status. Success requires ALL of: gh exit 0,
# the shared response check accepting the envelope, AND .data.addReaction.reaction.content equal to
# the requested EYES. Nothing text-matches a response, so a body whose error message mentions an
# existing reaction is react-failed like any other error. Each case asserts the mutation was reached,
# so a case can never pass without the live path.

# run_live_case <name> <exit status> <body>: run react-marker over a bound toplevel node on the live
# path, the mutation answering <body> with <exit status>.
run_live_case() {
  new_gh_case "$1" toplevel
  set_gh_part react "$2" "$3"
  run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel
}

# assert_live_react_failed <name> <label>: the live case exited 1 with exactly the react-failed
# token on stderr and the mutation reached.
assert_live_react_failed() {
  if [ "$live_status" -eq 1 ] && [ "$live_reached" = yes ] \
     && printf '%s\n' "$live_stderr" | grep -qx 'REACTMARKER_ERROR=react-failed'; then
    pass "$1" "$2"
  else
    failed "$1" "status=$live_status reached=$live_reached stdout=$live_stdout stderr=$live_stderr"
  fi
}

# assert_live_success <name> <label>: the live case exited 0, silent on stdout, no error token on
# stderr, and the mutation reached.
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

# The binding lookup passes the node id as a variable argument, never inside the query text.
if [ -f "$case_dir/binding.args" ] && grep -qx "id=$TOPLEVEL_NODE" "$case_dir/binding.args" \
   && grep -qF 'node(id: $id)' "$case_dir/binding.args" \
   && ! grep -vx "id=$TOPLEVEL_NODE" "$case_dir/binding.args" | grep -qF "$TOPLEVEL_NODE"; then
  pass "live:binding-node-id-is-variable" "binding query passes id=<node> as a variable, query text never holds it"
else
  failed "live:binding-node-id-is-variable" "args=$(cat "$case_dir/binding.args" 2>/dev/null)"
fi

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

# A review candidate bound to a PullRequestReview on the fixture PR reacts like a toplevel one.
new_gh_case live-review-clean review
run_bound_case "$BOUND_REPO" "$REVIEW_NODE" review
assert_live_success "live:review-bound-clean" "review node bound to the open fixture PR -> exit 0, empty stdout"

# ── PR BINDING: no live reaction outside the current PR ─────────────────────────────
# Each case runs the live path with a clean EYES mutation answer, so only the binding can stop the
# reaction. Every failure asserts exit 1, exactly its token on stderr, and the mutation NOT reached.

# assert_binding_token <name> <token> <label>: the case exited 1 with exactly REACTMARKER_ERROR=<token>
# on stderr and the mutation not reached.
assert_binding_token() {
  if [ "$live_status" -eq 1 ] && [ "$live_reached" = no ] \
     && [ "$live_stderr" = "REACTMARKER_ERROR=$2" ]; then
    pass "$1" "$3"
  else
    failed "$1" "status=$live_status mutation_reached=$live_reached stdout=$live_stdout stderr=$live_stderr"
  fi
}

# run_refused_case <name> <surface> <binding body>: run a bound live case whose binding answers
# <binding body> with exit 0, from the bound repo, over the surface's node id.
run_refused_case() {
  local node_id="$TOPLEVEL_NODE"
  [ "$2" = review ] && node_id="$REVIEW_NODE"
  new_gh_case "$1" "$2"
  set_gh_part binding 0 "$3"
  run_bound_case "$BOUND_REPO" "$node_id" "$2"
}

run_refused_case refused-other-pr toplevel \
  "{\"data\":{\"node\":{\"__typename\":\"IssueComment\",\"pullRequest\":{\"state\":\"OPEN\",\"headRefName\":\"feature/other-branch\",\"headRepository\":{\"id\":\"$FIXTURE_REPO_ID\"}}}}}"
assert_binding_token "binding:refused-other-pr" pr-binding-refused "node on another PR (other head branch) -> pr-binding-refused"

run_refused_case refused-same-branch-other-repo toplevel \
  "{\"data\":{\"node\":{\"__typename\":\"IssueComment\",\"pullRequest\":{\"state\":\"OPEN\",\"headRefName\":\"$FIXTURE_BRANCH\",\"headRepository\":{\"id\":\"R_kgDOForkRepo9\"}}}}}"
assert_binding_token "binding:refused-same-branch-other-repo" pr-binding-refused "PR head has the same branch name in another repo -> pr-binding-refused"

run_refused_case refused-closed toplevel \
  "{\"data\":{\"node\":{\"__typename\":\"IssueComment\",\"pullRequest\":{\"state\":\"CLOSED\",\"headRefName\":\"$FIXTURE_BRANCH\",\"headRepository\":{\"id\":\"$FIXTURE_REPO_ID\"}}}}}"
assert_binding_token "binding:refused-closed-pr" pr-binding-refused "CLOSED PR -> pr-binding-refused"

run_refused_case refused-merged toplevel \
  "{\"data\":{\"node\":{\"__typename\":\"IssueComment\",\"pullRequest\":{\"state\":\"MERGED\",\"headRefName\":\"$FIXTURE_BRANCH\",\"headRepository\":{\"id\":\"$FIXTURE_REPO_ID\"}}}}}"
assert_binding_token "binding:refused-merged-pr" pr-binding-refused "MERGED PR -> pr-binding-refused"

run_refused_case refused-toplevel-is-review toplevel "$(bound_node_body PullRequestReview)"
assert_binding_token "binding:refused-toplevel-node-is-review" pr-binding-refused "toplevel candidate whose node is a PullRequestReview -> pr-binding-refused"

run_refused_case refused-review-is-comment review "$(bound_node_body IssueComment)"
assert_binding_token "binding:refused-review-node-is-comment" pr-binding-refused "review candidate whose node is an IssueComment -> pr-binding-refused"

run_refused_case refused-null-pr toplevel '{"data":{"node":{"__typename":"IssueComment","pullRequest":null}}}'
assert_binding_token "binding:refused-null-pull-request" pr-binding-refused "IssueComment with null pullRequest -> pr-binding-refused"

run_refused_case refused-null-node toplevel '{"data":{"node":null}}'
assert_binding_token "binding:refused-null-node" pr-binding-refused "null node -> pr-binding-refused"

run_refused_case refused-null-head-repo toplevel \
  "{\"data\":{\"node\":{\"__typename\":\"IssueComment\",\"pullRequest\":{\"state\":\"OPEN\",\"headRefName\":\"$FIXTURE_BRANCH\",\"headRepository\":null}}}}"
assert_binding_token "binding:refused-null-head-repository" pr-binding-refused "null headRepository -> pr-binding-refused"

# Lookup failures: the binding query, the repo view, or the origin push URL.
new_gh_case lookup-binding-exit1 toplevel
set_gh_part binding 1 "$(bound_node_body IssueComment)"
run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel
assert_binding_token "binding:lookup-binding-nonzero-exit" pr-binding-lookup-failed "non-zero gh exit on the binding query -> pr-binding-lookup-failed"

new_gh_case lookup-not-found toplevel
set_gh_part binding 0 \
  '{"data":{"node":null},"errors":[{"type":"NOT_FOUND","path":["node"],"message":"Could not resolve to a node with the global id of '"'"'IC_kwDOABCDEF4AbCdEf'"'"'"}]}'
run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel
assert_binding_token "binding:lookup-not-found-envelope" pr-binding-lookup-failed "exit-0 NOT_FOUND errors envelope -> pr-binding-lookup-failed"

new_gh_case lookup-non-json toplevel
set_gh_part binding 0 'not json at all'
run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel
assert_binding_token "binding:lookup-non-json-body" pr-binding-lookup-failed "non-JSON binding body -> pr-binding-lookup-failed"

new_gh_case lookup-repo-view-fails toplevel
set_gh_part repo 1 ''
run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel
assert_binding_token "binding:lookup-repo-view-fails" pr-binding-lookup-failed "failed gh repo view -> pr-binding-lookup-failed"

new_gh_case lookup-no-origin toplevel
run_bound_case "$NO_ORIGIN_REPO" "$TOPLEVEL_NODE" toplevel
assert_binding_token "binding:lookup-no-origin" pr-binding-lookup-failed "no origin remote -> pr-binding-lookup-failed"

new_gh_case lookup-at-origin toplevel
run_bound_case "$AT_ORIGIN_REPO" "$TOPLEVEL_NODE" toplevel
assert_binding_token "binding:lookup-https-origin-with-at" pr-binding-lookup-failed "https origin URL holding @ -> pr-binding-lookup-failed"

new_gh_case lookup-two-push toplevel
run_bound_case "$TWO_PUSH_REPO" "$TOPLEVEL_NODE" toplevel
assert_binding_token "binding:lookup-two-push-urls" pr-binding-lookup-failed "two origin push URLs -> pr-binding-lookup-failed"

# A detached HEAD has no branch to bind: pr-binding-no-branch before any gh call.
new_gh_case no-branch-detached toplevel
run_bound_case "$DETACHED_REPO" "$TOPLEVEL_NODE" toplevel
if [ "$repo_reached" = no ] && [ "$binding_reached" = no ] && [ ! -f "$case_dir/unexpected-reached" ]; then
  assert_binding_token "binding:no-branch-detached-head" pr-binding-no-branch "detached HEAD -> pr-binding-no-branch, gh never reached"
else
  failed "binding:no-branch-detached-head" "gh reached: repo=$repo_reached binding=$binding_reached stderr=$live_stderr"
fi

# ── NOISE MODE (#568): --noise <reviewer_filter> marks only an automated author's node ──
# Each case runs the live path from the bound repo with a binding whose node is on the fixture PR, so
# only the noise author check decides. The check reads only author.login and author.__typename
# through reviewer-identity.jq: is_bot and reviewer_matches_filter with an empty self login.

# run_noise_case <name> <filter> <surface> <author json>: a bound live case in noise mode with
# <filter> as the --noise value, the binding node authored by <author json>.
run_noise_case() {
  local node_id="$TOPLEVEL_NODE" node_type="IssueComment"
  if [ "$3" = review ]; then node_id="$REVIEW_NODE"; node_type="PullRequestReview"; fi
  new_gh_case "$1" "$3"
  set_gh_part binding 0 "$(bound_node_body "$node_type" "$4")"
  MARKER_FLAGS=(--noise "$2")
  run_bound_case "$BOUND_REPO" "$node_id" "$3"
  MARKER_FLAGS=()
}

# assert_noise_refused <name> <label>: exit 1, exactly noise-author-refused on stderr, the binding
# reached and neither mutation sent.
assert_noise_refused() {
  if [ "$live_status" -eq 1 ] && [ "$binding_reached" = yes ] && [ "$live_reached" = no ] \
     && [ "$unreact_reached" = no ] && [ "$live_stderr" = "REACTMARKER_ERROR=noise-author-refused" ]; then
    pass "$1" "$2"
  else
    failed "$1" "status=$live_status binding=$binding_reached unreact=$unreact_reached react=$live_reached stderr=$live_stderr"
  fi
}

run_noise_case noise-codex-automated "" toplevel "$CODEX_BOT_AUTHOR"
assert_live_success "noise:accepted-codex-bot-comment-automated" "Codex Bot IssueComment, empty filter (automated) -> exit 0, reaction sent"

run_noise_case noise-copilot-review-automated automated review "$COPILOT_BOT_AUTHOR"
assert_live_success "noise:accepted-copilot-bot-review-automated" "Copilot Bot review, filter automated -> exit 0, reaction sent"

run_noise_case noise-other-bot-all all toplevel "$OTHER_BOT_AUTHOR"
assert_live_success "noise:accepted-non-registry-bot-all" "non-registry Bot, filter all -> exit 0, reaction sent"

run_noise_case noise-human-all all toplevel "$HUMAN_AUTHOR"
assert_noise_refused "noise:refused-human-all" "human author, filter all -> exit 1 noise-author-refused, no mutation"

run_noise_case noise-human-own-login fixture-human toplevel "$HUMAN_AUTHOR"
assert_noise_refused "noise:refused-human-own-login-filter" "human author, filter naming that login -> exit 1 noise-author-refused, no mutation"

run_noise_case noise-other-bot-automated automated toplevel "$OTHER_BOT_AUTHOR"
assert_noise_refused "noise:refused-non-registry-bot-automated" "non-registry Bot, filter automated -> exit 1 noise-author-refused, no mutation"

run_noise_case noise-copilot-codex-only codex-only review "$COPILOT_BOT_AUTHOR"
assert_noise_refused "noise:refused-copilot-codex-only" "Copilot Bot, filter codex-only -> exit 1 noise-author-refused, no mutation"

run_noise_case noise-null-author automated toplevel null
assert_noise_refused "noise:refused-null-author" "null author -> exit 1 noise-author-refused, no mutation"

# A binding refusal still wins over the author check: a Codex Bot node on another PR is
# pr-binding-refused, never marked.
new_gh_case noise-other-pr toplevel
set_gh_part binding 0 \
  "{\"data\":{\"node\":{\"__typename\":\"IssueComment\",\"pullRequest\":{\"state\":\"OPEN\",\"headRefName\":\"feature/other-branch\",\"headRepository\":{\"id\":\"$FIXTURE_REPO_ID\"}},\"author\":$CODEX_BOT_AUTHOR,\"reactionGroups\":[]}}}"
MARKER_FLAGS=(--noise automated)
run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel
MARKER_FLAGS=()
assert_binding_token "noise:binding-refusal-precedes-author-check" pr-binding-refused "Codex Bot node on another PR in noise mode -> pr-binding-refused"

# --noise as the last argument has no value: missing-value-for-noise before any git or gh call.
new_gh_case noise-missing-value toplevel
(
  cd "$BOUND_REPO" || exit 98
  env -u GIT_DIR -u GIT_WORK_TREE -u REACTMARKER_TEST_MODE -u REACTMARKER_CAPTURE_FILE \
    PATH="$FAIL_GH_SHIM_DIR:$PATH" FIXTURE_GH_CASE_DIR="$case_dir" \
    bash "$REACT_MARKER" "$TOPLEVEL_NODE" toplevel "https://github.com/fixture-owner/fixture-repo/pull/5" --noise
) > "$case_dir/run.stdout" 2> "$case_dir/run.stderr"
status=$?
if [ "$status" -eq 1 ] && [ "$(cat "$case_dir/run.stderr")" = "REACTMARKER_ERROR=missing-value-for-noise" ] \
   && [ "$(reached_flag gh)" = no ]; then
  pass "noise:missing-value" "--noise with no value -> exit 1 missing-value-for-noise, gh never reached"
else
  failed "noise:missing-value" "status=$status stderr=$(cat "$case_dir/run.stderr") gh=$(reached_flag gh)"
fi

# Under the capture seam noise mode skips the binding and the author check and captures the
# reaction like fix mode.
cap="$(fresh_capture noise-capture)"
new_gh_case noise-capture toplevel
out="$(PATH="$FAIL_GH_SHIM_DIR:$PATH" FIXTURE_GH_CASE_DIR="$case_dir" REACTMARKER_TEST_MODE=1 \
  REACTMARKER_CAPTURE_FILE="$cap" \
  bash "$REACT_MARKER" --noise automated "$TOPLEVEL_NODE" toplevel "https://github.com/o/r/pull/5#issuecomment-1" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && [ -z "$out" ] && [ "$(grep -c '^REACT ' "$cap")" -eq 1 ] \
   && grep -qx "REACT node=$TOPLEVEL_NODE content=EYES" "$cap" && [ "$(reached_flag gh)" = no ]; then
  pass "noise:capture-seam-skips-author-check" "capture seam in noise mode -> one REACT line, exit 0, gh never reached"
else
  failed "noise:capture-seam-skips-author-check" "status=$status out=$out cap=$(cat "$cap") gh=$(reached_flag gh)"
fi

# The thread surface stays a silent no-op in noise mode.
cap="$(fresh_capture noise-thread)"
out="$(REACTMARKER_TEST_MODE=1 REACTMARKER_CAPTURE_FILE="$cap" \
  bash "$REACT_MARKER" --noise automated "$TOPLEVEL_NODE" thread "https://github.com/o/r/pull/5#discussion_r1" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && [ ! -s "$cap" ] && [ -z "$out" ]; then
  pass "noise:thread-silent-no-op" "thread surface in noise mode -> no reaction, zero output, exit 0"
else
  failed "noise:thread-silent-no-op" "status=$status cap=$(cat "$cap") out=$out"
fi

# A copy of the script whose directory lacks reviewer-identity.jq: noise mode fails with
# missing-identity-module before any gh call; fix mode never needs the module.
NO_IDENTITY_ROOT="$TMPDIR_TEST/no-identity-plugin"
mkdir -p "$NO_IDENTITY_ROOT/skills/github-review-loop/scripts" "$NO_IDENTITY_ROOT/skills/_shared"
cp "$REACT_MARKER" "$NO_IDENTITY_ROOT/skills/github-review-loop/scripts/react-marker.sh"
cp "$REPO_ROOT/plugin/skills/_shared/graphql-response.sh" "$NO_IDENTITY_ROOT/skills/_shared/graphql-response.sh"
NO_IDENTITY_MARKER="$NO_IDENTITY_ROOT/skills/github-review-loop/scripts/react-marker.sh"

new_gh_case noise-no-identity toplevel
(
  cd "$BOUND_REPO" || exit 98
  env -u GIT_DIR -u GIT_WORK_TREE -u REACTMARKER_TEST_MODE -u REACTMARKER_CAPTURE_FILE \
    PATH="$FAIL_GH_SHIM_DIR:$PATH" FIXTURE_GH_CASE_DIR="$case_dir" \
    bash "$NO_IDENTITY_MARKER" --noise automated "$TOPLEVEL_NODE" toplevel "https://github.com/fixture-owner/fixture-repo/pull/5"
) > "$case_dir/run.stdout" 2> "$case_dir/run.stderr"
status=$?
if [ "$status" -eq 1 ] && [ "$(cat "$case_dir/run.stderr")" = "REACTMARKER_ERROR=missing-identity-module" ] \
   && [ "$(reached_flag gh)" = no ]; then
  pass "noise:missing-identity-module" "noise mode without reviewer-identity.jq -> exit 1 missing-identity-module, gh never reached"
else
  failed "noise:missing-identity-module" "status=$status stderr=$(cat "$case_dir/run.stderr") gh=$(reached_flag gh)"
fi

cap="$(fresh_capture fix-no-identity)"
out="$(PATH="$FAIL_GH_SHIM_DIR:$PATH" FIXTURE_GH_CASE_DIR="$case_dir" REACTMARKER_TEST_MODE=1 \
  REACTMARKER_CAPTURE_FILE="$cap" \
  bash "$NO_IDENTITY_MARKER" "$TOPLEVEL_NODE" toplevel "https://github.com/o/r/pull/5#issuecomment-1" 2>&1)"
status=$?
if [ "$status" -eq 0 ] && grep -qx "REACT node=$TOPLEVEL_NODE content=EYES" "$cap"; then
  pass "fix:no-identity-module-needed" "fix mode without reviewer-identity.jq -> exit 0, reaction captured"
else
  failed "fix:no-identity-module-needed" "status=$status out=$out cap=$(cat "$cap")"
fi

# Fix mode makes no author check: a human-authored node bound to the fixture PR is still marked.
new_gh_case fix-human-author toplevel
set_gh_part binding 0 "$(bound_node_body IssueComment "$HUMAN_AUTHOR")"
run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel
assert_live_success "fix:human-author-still-reacts" "fix mode over a human-authored node -> exit 0, reaction sent"

# ── RE-MARK REFRESH (#568): a viewer EYES already present is removed before the new mark ──
# assert_remark_order <name> <label>: exit 0, silent stdout, no error token, and the shim saw
# repo view, binding, removeReaction, addReaction in that order.
assert_remark_order() {
  local order
  order="$(call_order)"
  if [ "$live_status" -eq 0 ] && [ -z "$live_stdout" ] && [ "$order" = "repo binding unreact react " ] \
     && ! printf '%s\n' "$live_stderr" | grep -q 'REACTMARKER_ERROR='; then
    pass "$1" "$2"
  else
    failed "$1" "status=$live_status order=$order stdout=$live_stdout stderr=$live_stderr"
  fi
}

new_gh_case remark-fix toplevel
set_gh_part binding 0 "$(bound_node_body IssueComment "$HUMAN_AUTHOR" "$VIEWER_EYES_GROUPS")"
run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel
assert_remark_order "remark:fix-unreact-before-react" "fix mode, viewer EYES present -> removeReaction then addReaction, exit 0"

if [ -f "$case_dir/unreact.args" ] && grep -qx "id=$TOPLEVEL_NODE" "$case_dir/unreact.args" \
   && grep -qF 'removeReaction(input: { subjectId: $id, content: EYES })' "$case_dir/unreact.args" \
   && ! grep -vx "id=$TOPLEVEL_NODE" "$case_dir/unreact.args" | grep -qF "$TOPLEVEL_NODE"; then
  pass "remark:unreact-node-id-is-variable" "removeReaction passes id=<node> as a variable, query text never holds it"
else
  failed "remark:unreact-node-id-is-variable" "args=$(cat "$case_dir/unreact.args" 2>/dev/null)"
fi

new_gh_case remark-noise review
set_gh_part binding 0 "$(bound_node_body PullRequestReview "$COPILOT_BOT_AUTHOR" "$VIEWER_EYES_GROUPS")"
MARKER_FLAGS=(--noise automated)
run_bound_case "$BOUND_REPO" "$REVIEW_NODE" review
MARKER_FLAGS=()
assert_remark_order "remark:noise-unreact-before-react" "noise mode, viewer EYES present -> removeReaction then addReaction, exit 0"

# An EYES group the viewer did not add needs no removal: only addReaction is sent.
new_gh_case remark-other-eyes toplevel
set_gh_part binding 0 "$(bound_node_body IssueComment "$CODEX_BOT_AUTHOR" "$OTHER_EYES_GROUPS")"
run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel
if [ "$live_status" -eq 0 ] && [ "$(call_order)" = "repo binding react " ]; then
  pass "remark:other-eyes-no-unreact" "EYES group with viewerHasReacted false -> no removeReaction, exit 0"
else
  failed "remark:other-eyes-no-unreact" "status=$live_status order=$(call_order) stderr=$live_stderr"
fi

# run_remark_failure <name> <exit status> <body>: a bound fix-mode case whose binding shows the
# viewer's EYES and whose removeReaction answers <body> with <exit status>.
run_remark_failure() {
  new_gh_case "$1" toplevel
  set_gh_part binding 0 "$(bound_node_body IssueComment "$CODEX_BOT_AUTHOR" "$VIEWER_EYES_GROUPS")"
  set_gh_part unreact "$2" "$3"
  run_bound_case "$BOUND_REPO" "$TOPLEVEL_NODE" toplevel
}

# assert_remark_failed <name> <label>: exit 1, exactly react-failed on stderr, the removal reached and
# addReaction never sent.
assert_remark_failed() {
  if [ "$live_status" -eq 1 ] && [ "$unreact_reached" = yes ] && [ "$live_reached" = no ] \
     && [ "$live_stderr" = "REACTMARKER_ERROR=react-failed" ]; then
    pass "$1" "$2"
  else
    failed "$1" "status=$live_status unreact=$unreact_reached react=$live_reached stderr=$live_stderr"
  fi
}

run_remark_failure remark-fail-exit1 1 \
  '{"data":{"removeReaction":{"reactionGroups":[{"content":"EYES","viewerHasReacted":false}]}}}'
assert_remark_failed "remark:removal-gh-nonzero" "removeReaction gh exit 1 -> exit 1 react-failed, addReaction not sent"

run_remark_failure remark-fail-errors 0 \
  '{"data":{"removeReaction":null},"errors":[{"type":"FORBIDDEN","message":"Resource not accessible by integration"}]}'
assert_remark_failed "remark:removal-errors-envelope" "removeReaction exit 0 + errors envelope -> exit 1 react-failed, addReaction not sent"

run_remark_failure remark-fail-still-eyes 0 \
  '{"data":{"removeReaction":{"reactionGroups":[{"content":"EYES","viewerHasReacted":true}]}}}'
assert_remark_failed "remark:removal-eyes-still-reacted" "removeReaction payload still shows viewer EYES -> exit 1 react-failed, addReaction not sent"

run_remark_failure remark-fail-null-groups 0 '{"data":{"removeReaction":{"reactionGroups":null}}}'
assert_remark_failed "remark:removal-null-reaction-groups" "removeReaction payload with null reactionGroups -> exit 1 react-failed, addReaction not sent"

# ── thread surface from a non-git directory stays a silent no-op ─────────────────────
# The thread surface never runs the binding: from a directory outside any repository, with shim git
# and gh first on PATH, it exits 0 silently and neither git nor gh is reached.
new_gh_case thread-non-git toplevel
(
  cd "$NON_GIT_DIR" || exit 98
  env -u GIT_DIR -u GIT_WORK_TREE -u REACTMARKER_TEST_MODE -u REACTMARKER_CAPTURE_FILE \
    PATH="$GIT_SHIM_DIR:$GH_SHIM_DIR:$PATH" FIXTURE_GH_CASE_DIR="$case_dir" \
    bash "$REACT_MARKER" "$TOPLEVEL_NODE" thread "https://github.com/o/r/pull/5#discussion_r1"
) > "$case_dir/run.out" 2>&1
status=$?
if [ "$status" -eq 0 ] && [ ! -s "$case_dir/run.out" ] && [ "$(reached_flag git)" = no ] \
   && [ "$(reached_flag repo)" = no ] && [ "$(reached_flag binding)" = no ] \
   && [ "$(reached_flag react)" = no ] && [ ! -f "$case_dir/unexpected-reached" ]; then
  pass "thread:non-git-silent-no-op" "thread surface outside a repo -> exit 0, no output, no git or gh call"
else
  failed "thread:non-git-silent-no-op" "status=$status out=$(cat "$case_dir/run.out") git=$(reached_flag git)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "react-marker: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
