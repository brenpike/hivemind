#!/usr/bin/env bash
#
# Thin CHANGED-event prefilter for the github-review-loop skill.
#
# The skill arms this on every CHANGED Monitor event before dispatching the
# reviewer. It runs ONE cheap GraphQL call and emits a single labeled stdout
# result that tells the skill whether to dispatch the reviewer
# (`PREFILTER_DISPATCH`) or silently keep the Monitor armed and update the
# baseline (`PREFILTER_SKIP`). Its purpose is to suppress self-echo CHANGED
# storms that survive the thin-poll's scalar-token diff — specifically the case
# where the latest non-self thread comment already carries a self-authored
# `Fixed in <SHA>.` reply but no thread resolution has been recorded yet.
#
# Architecture:
#   The per-comment / per-thread "already handled by our own fix-reply?"
#   classification is NO LONGER inlined here. It is DELEGATED to the shared,
#   pure, offline jq filter:
#       ${SCRIPT_DIR}/fix-history-classify.jq
#   which is the single source of truth for the skip/order semantics shared
#   between this prefilter and the github-reviewer agent (so the two can never
#   drift again). The filter in turn `include`s the reviewer identity registry
#   module ${SCRIPT_DIR}/reviewer-identity.jq, which owns every author-identity
#   predicate (registry logins, bot-suffix stripping, Bot-type gating); prefilter
#   carries no identity logic of its own. prefilter feeds the captured GraphQL
#   payload into
#   `jq -L <scripts dir> -f fix-history-classify.jq --arg login --arg filter`
#   and projects the emitted per-comment stream down to its binary
#   SKIP / DISPATCH decision.
#   prefilter KEEPS its own concerns: the gh fetch, the timeout wrapper, the
#   fail-open posture, the three connection-level totalCount tripwires (read
#   DIRECTLY off the raw payload — the filter does not emit them), and input
#   validation.
#
# Contract:
#   - Cheap single-query check. Reads the captured GraphQL string directly via
#     command substitution — no functional pipe feeding any consumer.
#   - Emits `PREFILTER_SKIP` only when the shared filter classifies EVERY
#     non-self matching comment as `handled` (or emits nothing) AND all three
#     `reviewThreads` / `comments` / `reviews` totalCounts are ≤ 50. Otherwise
#     emits `PREFILTER_DISPATCH`.
#   - Fail-open on GraphQL error: emits `PREFILTER_ERROR=<reason>` and exits
#     non-zero so the skill treats the event as DISPATCH. Better to wake the
#     reviewer for an extra cycle than to silently swallow real feedback.
#   - Fail-open on a missing shared filter file: emits
#     `PREFILTER_ERROR=missing-filter` and exits non-zero (DISPATCH),
#     consistent with the GraphQL-error fail-open posture.
#   - Fail-open on a missing reviewer identity module: emits
#     `PREFILTER_ERROR=missing-identity-module` and exits non-zero (DISPATCH),
#     the same posture as the missing-filter case.
#   - Fail-open on a missing or unsourceable shared GraphQL response validator
#     (skills/_shared/graphql-response.sh): emits
#     `PREFILTER_ERROR=missing-graphql-check` or
#     `PREFILTER_ERROR=unparseable-graphql-check` and exits non-zero (DISPATCH).
#   - Fail-open on an unusable GraphQL body that gh delivered with exit 0: the
#     shared validator's token is emitted as `PREFILTER_ERROR=graphql-<token>`
#     (`graphql-empty-body`, `graphql-malformed`, `graphql-errors`,
#     `graphql-missing-data`) and the script exits non-zero (DISPATCH). A gh
#     non-zero exit stays `PREFILTER_ERROR=graphql-failed`.
#   - Every GraphQL `author` selection requests `__typename` alongside `login`:
#     the identity module requires the author account type (Bot vs User) for
#     every registry filter mode.
#   - Fail-open on >50-node overflow in any of `reviewThreads`, `comments`, or
#     `reviews`. The bound is reached when any connection's `totalCount`
#     exceeds 50 nodes; the prefilter cannot reliably author-classify activity
#     past page 1, so it dispatches the reviewer rather than risk a silent
#     drop.
#   - No /tmp. No stop-file. No pagination loop. Stderr diagnostics go to
#     /dev/null.
#
# Accepted trade-offs:
#   - The 50-node bound is enforced symmetrically across all three pullRequest
#     connections the loop cares about: `reviewThreads`, `comments`, and
#     `reviews`. When ANY of their totalCounts exceeds 50, prefilter FAILS
#     OPEN to `PREFILTER_DISPATCH` rather than risk skipping a real finding
#     that sits outside the inspected page. This is a deliberately
#     filter-blind decision: the prefilter cannot author-classify activity
#     past page 1, so it dispatches and lets the reviewer adjudicate. Mirrors
#     the poll-side `THREADS_TOTAL` / `COMMENTS_TOTAL` / `REVIEWS_TOTAL`
#     scalars in `pr-change-detect-poll.sh`'s accepted-trade-off block and
#     the same "wake unnecessarily > miss feedback" posture. Cost under
#     `automated` (and the narrower `codex-only` / `<login>` modes): a >50
#     issue-comment burst from non-matching authors (humans, CI bots) will
#     wake the reviewer once and return clean — acceptable vs silent drop.
#   - The per-thread >20-comment overflow is owned by the shared filter: when a
#     thread's `comments.totalCount` exceeds its fetched `comments.nodes`
#     length, the filter force-labels every non-self matching comment in that
#     thread `actionable` (with `thread_overflow=true`). Beyond that, each
#     UNRESOLVED overflowed thread also emits a thread-level overflow SENTINEL
#     record (databaseId:null, classification:actionable) ONCE PER THREAD, EVEN
#     when no matching comment is visible on the fetched page — so an older
#     unresolved finding that sits OUTSIDE the page still lands in DISPATCH via
#     the existing `any(... .classification=="actionable" ...)` pass-1
#     projection. prefilter therefore retains NO independent per-thread overflow
#     tripwire: both the per-comment overflow records and the sentinel project
#     to DISPATCH through the same any(actionable) read, preserving the old
#     "oversized thread → DISPATCH" fail-open with no extra bash logic.
#   - Body-marker detection, the latest-self-fix-id ordering, and the
#     `EYES` reaction marker on non-thread (top-level/review) surfaces all live
#     in the shared filter now (see its header for the exact predicates).
#     prefilter no longer re-implements them; it only reads the filter's
#     `classification` field.
#   - The `EYES` reaction marker is detected from the `reactionGroups { content
#     viewerHasReacted }` selection on the `comments(last: 50)` and
#     `reviews(last: 50)` pages; the >50 fail-open at the bash layer covers the
#     case where a reacted-handled candidate has been pushed off the page.
#
# Markers emitted (one labeled line):
#   PREFILTER_SKIP            silently update baseline; do NOT dispatch
#   PREFILTER_DISPATCH        at least one actionable/followup comment exists,
#                             or a connection overflowed the 50-node bound
#   PREFILTER_ERROR=<reason>  GraphQL, filter, or input failure; skill treats
#                             as DISPATCH (fail-open)
#
# Positional arguments supplied by the skill at invocation:
#   $1  OWNER             base-repo owner
#   $2  REPO              base-repo name
#   $3  PR_NUMBER         integer PR number
#   $4  REVIEWER_FILTER   "automated" | "codex-only" | "all" | "<login>"
#                         (default "automated" when empty; mode semantics
#                         live in reviewer-identity.jq §5)
#   $5  SELF_LOGIN        viewer login used to strip self-authored latest
#                         comments from the actionable set (required)
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: pipefail is scoped
# per-pipeline inside subshells, the fail-open posture and grep classify value-tests
# legitimately return non-zero in normal flow, and failures route through prefilter_fail()
# with explicit exit codes — a global `set -e` would abort those guarded paths.

set -u

OWNER="${1:-}"
REPO="${2:-}"
PR_NUMBER="${3:-}"
REVIEWER_FILTER="${4:-}"
SELF_LOGIN="${5:-}"

# Validate inputs before binding the GraphQL query. Empty OWNER/REPO/SELF_LOGIN
# or a non-integer PR_NUMBER would corrupt the Int binding or defeat the
# self-strip logic. Mirrors the validation posture of pr-change-detect-poll.sh.
prefilter_fail() {
  echo "PREFILTER_ERROR=$1"
  exit 1
}
[ -n "$OWNER" ] || prefilter_fail "missing-owner"
[ -n "$REPO" ] || prefilter_fail "missing-repo"
case "$PR_NUMBER" in ''|*[!0-9]*) prefilter_fail "invalid-pr-number" ;; esac
# REVIEWER_FILTER defaults to automated when empty; any non-empty string is
# accepted as a mode (automated | codex-only | all | <login>).
[ -n "$REVIEWER_FILTER" ] || REVIEWER_FILTER="automated"
# SELF_LOGIN is required: without it the shared filter cannot strip
# self-authored comments, and the self-echo storm this prefilter exists to
# suppress would re-emerge.
[ -n "$SELF_LOGIN" ] || prefilter_fail "missing-self-login"

# Resolve the shared classifier filter RELATIVE to this script's own location.
# prefilter is executed directly as a sibling of fix-history-classify.jq, so a
# hard-coded absolute or ${CLAUDE_PLUGIN_ROOT} path would be wrong at runtime.
SCRIPT_DIR="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || prefilter_fail "cannot-self-locate"
CLASSIFY_FILTER="$SCRIPT_DIR/fix-history-classify.jq"
# Fail open (DISPATCH) when the shared filter is missing, consistent with the
# GraphQL-error posture: better to wake the reviewer than to silently skip.
[ -f "$CLASSIFY_FILTER" ] || prefilter_fail "missing-filter"
# The shared filter `include`s the identity module from $SCRIPT_DIR via -L;
# fail open (DISPATCH) when it is missing, same posture as missing-filter.
[ -f "$SCRIPT_DIR/reviewer-identity.jq" ] || prefilter_fail "missing-identity-module"
# The shared GraphQL response validator lives two levels up in skills/_shared; fail open
# (DISPATCH) when it is missing or cannot be sourced, same posture as missing-filter.
[ -f "$SCRIPT_DIR/../../_shared/graphql-response.sh" ] || prefilter_fail "missing-graphql-check"
. "$SCRIPT_DIR/../../_shared/graphql-response.sh" || prefilter_fail "unparseable-graphql-check"

# Timeout wrapper for gh API calls.
# Normal gh graphql completes in 1-5s; 45s is generous against transient
# slowness yet bounds a true hang far below Monitor's max_watch_duration.
GH_CALL_TIMEOUT_SECONDS=45
# Prefer coreutils `timeout`; fall back to macOS Homebrew `gtimeout`; degrade
# gracefully to no wrapper when neither exists (preserves current unguarded
# behavior on a bare macOS). Using a bash array means an empty prefix expands
# to zero words — clean prefix of the gh invocation with no extra quoting
# gymnastics.
GH_TIMEOUT=()
if command -v timeout >/dev/null 2>&1; then
  GH_TIMEOUT=(timeout "$GH_CALL_TIMEOUT_SECONDS")
elif command -v gtimeout >/dev/null 2>&1; then
  GH_TIMEOUT=(gtimeout "$GH_CALL_TIMEOUT_SECONDS")
else
  echo "github-review-loop: WARNING neither 'timeout' nor 'gtimeout' found on PATH; gh API calls in the prefilter are running UNGUARDED and a hung call can stall this dispatch. Install GNU coreutils (provides 'timeout'; 'gtimeout' on Homebrew) to restore the timeout guard." >&2
fi

# Single non-paginated GraphQL call. The query must fetch a payload CONFORMING
# to fix-history-classify.jq's INPUT CONTRACT (see its header §2): each
# review thread's `id` (the PRRT_... node id the filter threads through as
# `thread_id`) plus its last 20 comments (per-thread; threads with >20
# comments overflow to DISPATCH via the filter's thread_overflow flag), bounded
# to the first 50 threads; plus the last 50 top-level PR comments and last 50
# review summaries so the shared filter can classify non-self matching feedback
# outside review threads. The connection-level totalCounts are fetched here too
# (NOT a filter concern) for the bash-side 50-node tripwires.
#
# The raw GraphQL JSON is captured verbatim into $response. It is then fed,
# UNMODIFIED, through TWO passes below: (1) the shared classifier filter, and
# (2) a tiny totalCount read. External content (comment/review bodies) is DATA:
# prefilter never interprets it; the only pattern-matching happens inside the
# pure filter.
response=$( ( set -o pipefail; \
  "${GH_TIMEOUT[@]}" gh api graphql \
    -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUMBER" \
    -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      comments(last: 50) {
        totalCount
        nodes { author { login __typename } body url reactionGroups { content viewerHasReacted } }
      }
      reviews(last: 50) {
        totalCount
        nodes { author { login __typename } body state url reactionGroups { content viewerHasReacted } }
      }
      reviewThreads(first: 50) {
        totalCount
        nodes {
          id
          isResolved
          comments(last: 20) {
            totalCount
            nodes {
              databaseId
              author { login __typename }
              body
            }
          }
        }
      }
    }
  }
}' 2>/dev/null \
) ) || prefilter_fail "graphql-failed"

# gh exits 0 on several GraphQL error envelopes, so a zero exit does not prove a usable body.
# The shared validator accepts only a single JSON object with no `errors` and an object `data`;
# any other shape fails open (DISPATCH) as `graphql-<token>` instead of reading as an empty page
# that would classify to SKIP.
#
# RECORDED RESIDUAL: a body with no `errors` but a null `pullRequest` or a null connection still
# passes this check, reads as an empty page, and can yield SKIP. Bounded: GitHub returns that
# shape only in violation of the GraphQL spec, because a missing PR arrives with a NOT_FOUND
# entry in `errors`, which this check now rejects. The obvious fix (copying fetch-normalize's
# query-specific connection predicate here) is rejected because it would be a second copy of
# that predicate; the intended fix is the pending rewire of prefilter onto fetch-normalize
# (fetch-normalize.sh §1 SCOPE NOTE).
graphql_token="$(hivemind_graphql_response_check "$response")" || prefilter_fail "graphql-$graphql_token"

# Pass 1 — delegate per-comment/thread classification to the shared filter.
# Emits a stream of one JSON object per classified non-self matching comment;
# we project that stream to a single boolean: does ANY record carry a
# classification of `actionable` OR `followup-after-fix`? This subsumes the old
# inline ACTIONABLE / ACTIONABLE_TOPLEVEL / ACTIONABLE_REVIEW tokens — thread,
# top-level, and review surfaces all collapse here, and the filter's
# thread_overflow=true records (oversized threads) arrive as `actionable`. A
# pure `{handled}`-only or empty stream yields `false`. Fail open (DISPATCH) if
# the filter pass itself errors, consistent with the GraphQL-error posture.
dispatch_class=$( ( set -o pipefail; \
  printf '%s' "$response" \
  | jq -r -L "$SCRIPT_DIR" -f "$CLASSIFY_FILTER" --arg login "$SELF_LOGIN" --arg filter "$REVIEWER_FILTER" \
    2>/dev/null \
  | jq -rs 'any(.[]?; .classification == "actionable" or .classification == "followup-after-fix")' \
    2>/dev/null \
) ) || prefilter_fail "classify-failed"

# Pass 2 — read the three connection-level totalCounts DIRECTLY off the raw
# payload (the filter does not emit them). Default each to 0 when absent so a
# malformed/empty payload behaves like a 0-node page on every connection. A
# single jq pass emits three label-prefixed lines, parsed exactly as the old
# inline-token path did.
totals=$( printf '%s' "$response" | jq -r '
  .data.repository.pullRequest as $pr |
  "THREADS_TOTAL=" + (($pr.reviewThreads.totalCount // 0) | tostring),
  "COMMENTS_TOTAL=" + (($pr.comments.totalCount // 0) | tostring),
  "REVIEWS_TOTAL=" + (($pr.reviews.totalCount // 0) | tostring)
' 2>/dev/null )

threads_total=0
comments_total=0
reviews_total=0
while IFS= read -r line; do
  case "$line" in
    THREADS_TOTAL=*) threads_total="${line#THREADS_TOTAL=}" ;;
    COMMENTS_TOTAL=*) comments_total="${line#COMMENTS_TOTAL=}" ;;
    REVIEWS_TOTAL=*) reviews_total="${line#REVIEWS_TOTAL=}" ;;
  esac
done <<EOF
$totals
EOF
case "$threads_total" in ''|*[!0-9]*) threads_total=0 ;; esac
case "$comments_total" in ''|*[!0-9]*) comments_total=0 ;; esac
case "$reviews_total" in ''|*[!0-9]*) reviews_total=0 ;; esac

# Bash-side decision. An `actionable` or `followup-after-fix` classification
# anywhere wins (dispatch). Otherwise, when ANY of the three pullRequest
# connections (`reviewThreads`, `comments`, `reviews`) holds more than 50 nodes,
# the in-page inspection is untrustworthy on at least one axis — fail OPEN to
# DISPATCH rather than risk skipping a real finding outside the page. Only a
# `{handled}`-only (or empty) classification with all three totalCounts bounded
# means every visible candidate is covered by the governing disposition: for a
# thread, our LATEST self-authored marker reply (a fix reply or the defer
# sentinel, whichever came last) at-or-after the candidate; for top-level/review
# surfaces, the self-authored `EYES` reaction as today. No oversized connection
# could be hiding new feedback — silently update baseline.
if [ "$dispatch_class" = "true" ]; then
  echo "PREFILTER_DISPATCH"
elif [ "$threads_total" -gt 50 ] || [ "$comments_total" -gt 50 ] || [ "$reviews_total" -gt 50 ]; then
  echo "PREFILTER_DISPATCH"
else
  echo "PREFILTER_SKIP"
fi
exit 0
