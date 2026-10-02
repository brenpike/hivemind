#!/usr/bin/env bash
#
# Behavioral unit runner for the github-review-loop CHANGED-event prefilter (issue #393).
#
# OFFLINE bash TEST — CI-runnable with ONLY bash + jq present (NO gh / network). It drives:
#   plugin/skills/github-review-loop/scripts/prefilter.sh
# through a PATH-shim fake `gh` that prints one canned response body (CR stripped) and exits with
# a configured status. The REAL `jq` runs the script's REAL shared validator and classifier over
# those bytes, so only the transport is faked.
#
# Inputs reuse the tests/fix-history/* fixtures, which are raw GraphQL response bodies of the
# prefilter query shape (`.data.repository.pullRequest.{reviewThreads,comments,reviews}`). Error
# envelopes are DERIVED from them inside a disposable tmpdir; the committed fixtures are never
# edited.
#
# WHAT THIS PROVES (the bite): gh exits 0 on several GraphQL error envelopes. Before the shared
# validator, a body carrying top-level `errors` next to a usable `data` classified normally and
# could yield PREFILTER_SKIP, silently swallowing a failed fetch. Each error case asserts the
# fail-open `PREFILTER_ERROR=graphql-<token>` line and a non-zero exit instead.
#
# The shape cases prove the second bite: an error-free but hollow body (null repository or
# pullRequest, an absent or null connection or `nodes` list) read as an empty page and yielded
# PREFILTER_SKIP. Each now asserts `PREFILTER_ERROR=graphql-null-pullrequest` or
# `PREFILTER_ERROR=graphql-missing-connection` from the shared review-surface shape check, while
# a genuinely empty page (every `nodes` [] and totalCount 0) still skips, and an `errors` entry
# next to a null pullRequest stays `graphql-errors` because the envelope check runs first.
#
# Mirrors tools/test_change_detect_poll.sh's pass/fail counter + per-case assertion +
# exit-nonzero-on-any-fail convention. Read-only: the only writes are scratch files under a
# disposable tmpdir removed on EXIT.
#
# Usage:
#   ./tools/test_prefilter.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PREFILTER="$REPO_ROOT/plugin/skills/github-review-loop/scripts/prefilter.sh"
FIXTURES="$REPO_ROOT/tests/fix-history"

[ -f "$PREFILTER" ] || { echo "FAIL: script under test missing: $PREFILTER" >&2; exit 2; }
[ -d "$FIXTURES" ] || { echo "FAIL: fixture dir missing: $FIXTURES" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required by the script under test" >&2; exit 2; }

TMPDIR_TEST="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Prefilter args held fixed across cases: OWNER REPO PR_NUMBER REVIEWER_FILTER SELF_LOGIN. The
# filter/self pair matches the fix-history suite's run of the same fixtures.
OWNER="o"
REPO_NAME="r"
PR_NUMBER="5"
REVIEWER_FILTER="all"
SELF_LOGIN="selfuser"

CASE01="$FIXTURES/case01-handled-by-marker.json"
CASE04="$FIXTURES/case04-no-self-fix-thread.json"
[ -f "$CASE01" ] || { echo "FAIL: fixture missing: $CASE01" >&2; exit 2; }
[ -f "$CASE04" ] || { echo "FAIL: fixture missing: $CASE04" >&2; exit 2; }

# ── PATH-shim fake gh ───────────────────────────────────────────────────────────────
# Prints the file named by FAKE_GH_BODY (CR stripped) and exits with FAKE_GH_EXIT.
# INVARIANT: gh stdout never carries CR; a core.autocrlf checkout of a fixture would otherwise
# carry CR into the bytes the script parses.
STUB_BIN="$TMPDIR_TEST/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -u
[ -n "${FAKE_GH_BODY:-}" ] || { echo "fake gh: FAKE_GH_BODY unset" >&2; exit 1; }
tr -d '\r' < "$FAKE_GH_BODY"
exit "${FAKE_GH_EXIT:-0}"
STUB
chmod +x "$STUB_BIN/gh"

# derive_body <name> <jq program> <source fixture>: write <source> transformed by <program> to a
# scratch file and print its path.
derive_body() {
  local body_path="$TMPDIR_TEST/$1.json"
  tr -d '\r' < "$3" | jq "$2" > "$body_path" || { echo "FAIL: cannot derive $1" >&2; exit 2; }
  printf '%s\n' "$body_path"
}

# write_body <name> <bytes>: write <bytes> verbatim to a scratch file and print its path.
write_body() {
  local body_path="$TMPDIR_TEST/$1.body"
  printf '%s' "$2" > "$body_path"
  printf '%s\n' "$body_path"
}

# run_case <name> <body file> <gh exit> <expected stdout> <expected rc>
run_case() {
  local case_name="$1" body_path="$2" gh_exit="$3" want_out="$4" want_rc="$5"
  local got_out got_rc
  got_out="$(PATH="$STUB_BIN:$PATH" FAKE_GH_BODY="$body_path" FAKE_GH_EXIT="$gh_exit" \
    bash "$PREFILTER" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$REVIEWER_FILTER" "$SELF_LOGIN" 2>/dev/null)"
  got_rc=$?
  if [ "$got_out" = "$want_out" ] && [ "$got_rc" -eq "$want_rc" ]; then
    pass "$case_name" "stdout=$got_out rc=$got_rc"
  else
    failed "$case_name" "want stdout=$want_out rc=$want_rc; got stdout=$(printf '%s' "$got_out" | tr '\n' ';') rc=$got_rc"
  fi
}

ERRORS_MESSAGE="$(derive_body case01-errors-message '. + {errors: [{message: "Something went wrong"}]}' "$CASE01")" || exit 2
ERRORS_EMPTY_OBJECT="$(derive_body case01-errors-empty-object '. + {errors: [{}]}' "$CASE01")" || exit 2
BLANK_BODY="$(write_body blank $'  \n\t\n')"
NON_JSON="$(write_body non-json 'this is not json')"
NULL_DATA="$(write_body null-data '{"data":null}')"

run_case "classify:handled-marker-skips" "$CASE01" 0 "PREFILTER_SKIP" 0
run_case "classify:no-self-fix-dispatches" "$CASE04" 0 "PREFILTER_DISPATCH" 0
run_case "graphql:errors-with-message" "$ERRORS_MESSAGE" 0 "PREFILTER_ERROR=graphql-errors" 1
run_case "graphql:errors-empty-object" "$ERRORS_EMPTY_OBJECT" 0 "PREFILTER_ERROR=graphql-errors" 1
run_case "graphql:blank-body" "$BLANK_BODY" 0 "PREFILTER_ERROR=graphql-empty-body" 1
run_case "graphql:non-json" "$NON_JSON" 0 "PREFILTER_ERROR=graphql-malformed" 1
run_case "graphql:null-data" "$NULL_DATA" 0 "PREFILTER_ERROR=graphql-missing-data" 1
run_case "graphql:gh-nonzero-exit" "$CASE01" 1 "PREFILTER_ERROR=graphql-failed" 1

# ── Hollow-body shape cases ──────────────────────────────────────────────────────
NULL_PULLREQUEST="$(derive_body shape-null-pullrequest '.data.repository.pullRequest = null' "$CASE01")" || exit 2
NULL_REPOSITORY="$(derive_body shape-null-repository '.data.repository = null' "$CASE01")" || exit 2
ABSENT_REVIEWS="$(derive_body shape-absent-reviews 'del(.data.repository.pullRequest.reviews)' "$CASE01")" || exit 2
NULL_COMMENTS_NODES="$(derive_body shape-null-comments-nodes '.data.repository.pullRequest.comments.nodes = null' "$CASE01")" || exit 2
NULL_THREAD_COMMENTS_NODES="$(derive_body shape-null-thread-comments-nodes \
  '.data.repository.pullRequest.reviewThreads.nodes[0].comments.nodes = null' "$CASE01")" || exit 2
VALID_EMPTY="$(derive_body shape-valid-empty \
  '.data.repository.pullRequest |= with_entries(.value = {totalCount: 0, nodes: []})' "$CASE01")" || exit 2
ERRORS_OVER_NULL_PR="$(derive_body shape-errors-over-null-pr \
  '.data.repository.pullRequest = null | . + {errors: [{type: "NOT_FOUND", message: "Could not resolve to a PullRequest with the number of 5."}]}' \
  "$CASE01")" || exit 2

run_case "shape:null-pullrequest" "$NULL_PULLREQUEST" 0 "PREFILTER_ERROR=graphql-null-pullrequest" 1
run_case "shape:null-repository" "$NULL_REPOSITORY" 0 "PREFILTER_ERROR=graphql-null-pullrequest" 1
run_case "shape:absent-reviews" "$ABSENT_REVIEWS" 0 "PREFILTER_ERROR=graphql-missing-connection" 1
run_case "shape:null-comments-nodes" "$NULL_COMMENTS_NODES" 0 "PREFILTER_ERROR=graphql-missing-connection" 1
run_case "shape:null-thread-comments-nodes" "$NULL_THREAD_COMMENTS_NODES" 0 "PREFILTER_ERROR=graphql-missing-connection" 1
run_case "shape:valid-empty-skips" "$VALID_EMPTY" 0 "PREFILTER_SKIP" 0
run_case "shape:errors-over-null-pr" "$ERRORS_OVER_NULL_PR" 0 "PREFILTER_ERROR=graphql-errors" 1

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "prefilter: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
