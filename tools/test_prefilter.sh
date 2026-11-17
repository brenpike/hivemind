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
# The reviewer cases prove the Automated Reviewer set is derived from the PR's own evidence
# (ADR-0043): Codex-shaped, Copilot-shaped and generic review bots get the same SKIP/DISPATCH, a
# status bot that only posts a top-level comment stays out under `automated`, a login named in
# HIVEMIND_PR_REVIEWERS admits that Bot but never a User holding the same login, and the retired
# filter value fails before any gh call.
#
# Usage:
#   ./tools/test_prefilter.sh

set -u
unset HIVEMIND_PR_REVIEWERS

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
CASE25="$FIXTURES/case25-noise-marked-bots.json"
CASE26="$FIXTURES/case26-marked-then-edited.json"
CASE27="$FIXTURES/case27-reviewer-parity.json"
CASE28="$FIXTURES/case28-reviewer-evidence.json"
for fixture_path in "$CASE01" "$CASE04" "$CASE25" "$CASE26" "$CASE27" "$CASE28"; do
  [ -f "$fixture_path" ] || { echo "FAIL: fixture missing: $fixture_path" >&2; exit 2; }
done

# ── PATH-shim fake gh ───────────────────────────────────────────────────────────────
# Prints the file named by FAKE_GH_BODY (CR stripped) and exits with FAKE_GH_EXIT. Each call
# appends one line to FAKE_GH_CALLS so a case can prove gh was never reached.
# INVARIANT: gh stdout never carries CR; a core.autocrlf checkout of a fixture would otherwise
# carry CR into the bytes the script parses.
STUB_BIN="$TMPDIR_TEST/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -u
[ -z "${FAKE_GH_CALLS:-}" ] || echo "gh $*" >> "$FAKE_GH_CALLS"
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

GH_CALLS="$TMPDIR_TEST/gh-calls"

# run_case <name> <body file> <gh exit> <expected stdout> <expected rc> [reviewer filter]
#          [HIVEMIND_PR_REVIEWERS value]
# The reviewer filter defaults to REVIEWER_FILTER. HIVEMIND_PR_REVIEWERS stays unset unless the
# seventh argument is given. GH_CALLS is reset before each run.
run_case() {
  local case_name="$1" body_path="$2" gh_exit="$3" want_out="$4" want_rc="$5"
  local reviewer_filter="${6:-$REVIEWER_FILTER}"
  local got_out got_rc
  rm -f "$GH_CALLS"
  got_out="$( [ "$#" -lt 7 ] || export HIVEMIND_PR_REVIEWERS="$7"
    PATH="$STUB_BIN:$PATH" FAKE_GH_BODY="$body_path" FAKE_GH_EXIT="$gh_exit" FAKE_GH_CALLS="$GH_CALLS" \
    bash "$PREFILTER" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$reviewer_filter" "$SELF_LOGIN" 2>/dev/null)"
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

# ── EYES mark cases ──────────────────────────────────────────────────────────────
# Each single-node body keeps one top-level comment or review from case25/case26 and empties the
# other connection, so the node alone decides SKIP or DISPATCH. Each bot node runs under a
# reviewer filter that keeps it in scope.
# single_comment_program <comment id>: print a jq program that keeps only that top-level comment.
single_comment_program() {
  printf '%s' ".data.repository.pullRequest |= (.comments.nodes |= map(select(.id == \"$1\")) | .comments.totalCount = (.comments.nodes | length) | .reviews = {totalCount: 0, nodes: []})"
}
# single_review_program <review id>: print a jq program that keeps only that review.
single_review_program() {
  printf '%s' ".data.repository.pullRequest |= (.reviews.nodes |= map(select(.id == \"$1\")) | .reviews.totalCount = (.reviews.nodes | length) | .comments = {totalCount: 0, nodes: []})"
}

CODEX_MARKED="$(derive_body s568-2-codex-marked \
  "$(single_comment_program IC_kwDOcase25comment2500)" "$CASE25")" || exit 2
GENERIC_BOT_MARKED="$(derive_body s568-2-generic-bot-marked \
  "$(single_comment_program IC_kwDOcase25comment2501)" "$CASE25")" || exit 2
COPILOT_MARKED="$(derive_body s568-2-copilot-marked \
  "$(single_review_program PRR_kwDOcase25review2502)" "$CASE25")" || exit 2
EDITED_AFTER_MARK="$(derive_body s568-2-edited-after-mark \
  "$(single_comment_program IC_kwDOcase26comment2600)" "$CASE26")" || exit 2
EDITED_BEFORE_MARK="$(derive_body s568-2-edited-before-mark \
  "$(single_comment_program IC_kwDOcase26comment2608)" "$CASE26")" || exit 2

run_case "eyes:codex-noise-marked-skips" "$CODEX_MARKED" 0 "PREFILTER_SKIP" 0 "automated"
run_case "eyes:copilot-noise-marked-skips" "$COPILOT_MARKED" 0 "PREFILTER_SKIP" 0 "automated"
run_case "eyes:generic-bot-noise-marked-skips" "$GENERIC_BOT_MARKED" 0 "PREFILTER_SKIP" 0 "all"
run_case "eyes:case25-noise-marked-bots-skips" "$CASE25" 0 "PREFILTER_SKIP" 0 "all"
run_case "eyes:edited-after-mark-dispatches" "$EDITED_AFTER_MARK" 0 "PREFILTER_DISPATCH" 0 "all"
run_case "eyes:edited-before-mark-skips" "$EDITED_BEFORE_MARK" 0 "PREFILTER_SKIP" 0 "all"

# ── Reviewer parity cases ────────────────────────────────────────────────────────
# case27 holds one review thread and one finding/notice comment pair per bot: Codex-shaped
# (chatgpt-codex-connector), Copilot-shaped (copilot-pull-request-reviewer) and a generic bot
# (acme-review-bot). Each slice keeps one bot's thread, so its thread comments are the only
# evidence that admits the bot to the Automated Reviewer set, and every bot must get the same
# decision under `automated`.
# parity_program <thread id> <thread comments kept> <top-level comment id or "">: print a jq
# program that keeps that thread cut to its first comments, that top-level comment only, and no
# review.
parity_program() {
  printf '%s' ".data.repository.pullRequest |= (.reviewThreads.nodes |= map(select(.id == \"$1\") | .comments.nodes |= .[0:$2] | .comments.totalCount = (.comments.nodes | length)) | .reviewThreads.totalCount = (.reviewThreads.nodes | length) | .comments.nodes |= map(select(.id == \"$3\")) | .comments.totalCount = (.comments.nodes | length) | .reviews = {totalCount: 0, nodes: []})"
}

# run_parity_cases <label> <thread id> <unmarked finding comment id> <marked notice comment id>
run_parity_cases() {
  local label="$1" thread_id="$2" finding_id="$3" notice_id="$4" body_path
  body_path="$(derive_body "parity-$label-followup" "$(parity_program "$thread_id" 3 "")" "$CASE27")" || exit 2
  run_case "parity:$label-thread-followup-dispatches" "$body_path" 0 "PREFILTER_DISPATCH" 0 "automated"
  body_path="$(derive_body "parity-$label-fixed" "$(parity_program "$thread_id" 2 "")" "$CASE27")" || exit 2
  run_case "parity:$label-thread-fixed-skips" "$body_path" 0 "PREFILTER_SKIP" 0 "automated"
  body_path="$(derive_body "parity-$label-finding" "$(parity_program "$thread_id" 2 "$finding_id")" "$CASE27")" || exit 2
  run_case "parity:$label-toplevel-finding-dispatches" "$body_path" 0 "PREFILTER_DISPATCH" 0 "automated"
  body_path="$(derive_body "parity-$label-notice" "$(parity_program "$thread_id" 2 "$notice_id")" "$CASE27")" || exit 2
  run_case "parity:$label-toplevel-marked-skips" "$body_path" 0 "PREFILTER_SKIP" 0 "automated"
}

run_parity_cases codex-shaped PRRT_case27rrrrrrrrrrr1 IC_kwDOcase27comment2703 IC_kwDOcase27comment2705
run_parity_cases copilot-shaped PRRT_case27rrrrrrrrrrr2 IC_kwDOcase27comment2713 IC_kwDOcase27comment2715
run_parity_cases generic-bot PRRT_case27rrrrrrrrrrr3 IC_kwDOcase27comment2723 IC_kwDOcase27comment2725

# ── Reviewer evidence cases ──────────────────────────────────────────────────────
# case28 keeps its PR-level evidence (latestReviews, the THUMBS_UP reactors) in every slice;
# each slice keeps one unmarked top-level comment and no review or thread.
# evidence_program <comment id>: print a jq program that keeps only that top-level comment.
evidence_program() {
  printf '%s' ".data.repository.pullRequest |= (.comments.nodes |= map(select(.id == \"$1\")) | .comments.totalCount = (.comments.nodes | length) | .reviews = {totalCount: 0, nodes: []} | .reviewThreads = {totalCount: 0, nodes: []})"
}

STATUS_BOT="$(derive_body evidence-status-bot "$(evidence_program IC_kwDOcase28comment2800)" "$CASE28")" || exit 2
THUMBS_BOT="$(derive_body evidence-thumbs-bot "$(evidence_program IC_kwDOcase28comment2801)" "$CASE28")" || exit 2
LATEST_BOT="$(derive_body evidence-latest-bot "$(evidence_program IC_kwDOcase28comment2807)" "$CASE28")" || exit 2
CONFIGURED_BOT="$(derive_body evidence-configured-bot "$(evidence_program IC_kwDOcase28comment2803)" "$CASE28")" || exit 2
CONFIGURED_HUMAN="$(derive_body evidence-configured-human "$(evidence_program IC_kwDOcase28comment2805)" "$CASE28")" || exit 2

run_case "evidence:status-bot-toplevel-only-skips-automated" "$STATUS_BOT" 0 "PREFILTER_SKIP" 0 "automated"
run_case "evidence:status-bot-toplevel-only-dispatches-all" "$STATUS_BOT" 0 "PREFILTER_DISPATCH" 0 "all"
run_case "evidence:thumbs-up-reactor-dispatches" "$THUMBS_BOT" 0 "PREFILTER_DISPATCH" 0 "automated"
run_case "evidence:latest-review-author-dispatches" "$LATEST_BOT" 0 "PREFILTER_DISPATCH" 0 "automated"
run_case "configured:unlisted-bot-skips" "$CONFIGURED_BOT" 0 "PREFILTER_SKIP" 0 "automated"
run_case "configured:listed-bot-dispatches" "$CONFIGURED_BOT" 0 "PREFILTER_DISPATCH" 0 "automated" "plain-bot"
run_case "configured:listed-bot-suffix-dispatches" "$CONFIGURED_BOT" 0 "PREFILTER_DISPATCH" 0 "automated" "other-bot, plain-bot[bot]"
run_case "configured:listed-login-human-skips" "$CONFIGURED_HUMAN" 0 "PREFILTER_SKIP" 0 "automated" "plain-bot"

# ── Retired filter case ──────────────────────────────────────────────────────────
run_case "filter:retired-rejected" "$CASE04" 0 "PREFILTER_ERROR=retired-filter" 1 "codex-only"
if [ -e "$GH_CALLS" ]; then
  failed "filter:retired-no-gh-call" "gh was called: $(tr '\n' ';' < "$GH_CALLS")"
else
  pass "filter:retired-no-gh-call" "no gh call recorded"
fi
run_case "filter:gh-call-recorded-control" "$CASE04" 0 "PREFILTER_DISPATCH" 0
if [ -s "$GH_CALLS" ]; then
  pass "filter:gh-call-recorded" "gh call recorded"
else
  failed "filter:gh-call-recorded" "fake gh recorded no call; the no-gh-call check is vacuous"
fi

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "prefilter: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
