#!/usr/bin/env bash
#
# Thin PR change-detection poll for the github-review-loop skill.
#
# Predefined, exact statement: the skill arms this in the MAIN-SESSION Monitor
# every run and never reconstructs it. It runs as a BACKGROUND Monitor command,
# so the `while` loop + `sleep` between iterations is legal (foreground sleep is
# harness-blocked; this is not foreground).
#
# Contract:
#   - Each iteration computes a CHEAP SCALAR snapshot via ONE non-paginated
#     GraphQL query (PR state; author-aware latest-id tokens for issue comments,
#     filtered reviews, and review-thread comments (filtered by reviewer-filter
#     and self identity); totalCount tripwires for the three connections capped at
#     50; a CI `FAILED_CHECKS` scalar that counts only checks in a failed/
#     errored state, so CI regressions wake the reviewer even when no new review
#     comment was posted) plus ONE automated-reviewer APPROVAL bool (a
#     `review-approved` reviewer whose LATEST review is APPROVED, read from
#     GitHub's per-author `latestReviews` and never rebuilt from review history,
#     OR a 👍 reaction on the PR from a `pr-reaction-thumbs-up` reviewer; both
#     scoped by the active reviewer filter). Both approval reads are EXHAUSTIVE
#     paginated walks (`latestReviews` in its own paginated GraphQL query, the
#     reactions over paginated REST): the `latestReviews` `first: 100` is a
#     page size, not a bound, and a walk that fails on any page fails the
#     capture rather than judging approval from a partial fetch. No bodies —
#     the poll only answers "did anything change?" and "is the PR terminal?".
#   - Every reviewer IDENTITY decision (self identity, login normalization,
#     filter scope, approver membership) is delegated to the sibling jq module
#     `reviewer-identity.jq` (ADR-0033), loaded by `jq -L "$SCRIPT_DIR"`. This
#     script carries no login literal, login compare, or suffix-strip regex of
#     its own; a missing module is a terminal error before the first gh call.
#   - It DIFFS the scalar snapshot in bash against the previous iteration and
#     emits a single minimal marker line ONLY on a real delta or a terminal
#     state. The reviewer re-fetches ALL feedback bodies and does the full
#     classification on wake; the poll never interprets.
#   - A no-change iteration emits NOTHING (silent) → Monitor feeds nothing back
#     → the model is never woken → zero model tokens during idle.
#   - It reads each gh command's stdout directly via command substitution. There
#     is NO functional pipe (`tail -f | grep`, etc.) feeding Monitor.
#   - No /tmp. No stop-file. Monitor is stopped natively by the skill.
#
# Accepted trade-off (coarse author-aware tokens, not full fingerprints): the
# poll tracks a single max databaseId per author-filtered stream rather than a
# per-node identity set. Consequences:
#   - Self-only flurries between polls (own `Fixed in <SHA>` replies, own
#     pushes) do not bump any token — by design, eliminates self-echo CHANGED
#     storms.
#   - Non-self activity older than 50 nodes behind a self-flurry surfaces on
#     the next non-self event or next non-`CHANGED` terminal marker; thin-poll
#     never interprets — reviewer re-fetches all on wake.
#   - `reviewThreads(first: 50)` is bounded — actionable threads past page 1
#     surface on the NEXT CHANGED.
#   - `*_TOTAL` scalars are tripwires for >50-node activity: when actionable
#     feedback appears past page 1 of any connection (comments, reviews, or
#     review threads), the corresponding totalCount changes and fires CHANGED
#     even though no id token bumped. This re-introduces ONE self-induced
#     noise vector — our own `Fixed in <SHA>` reply bumps COMMENTS_TOTAL.
#     That noise is absorbed downstream by `prefilter.sh` returning
#     `PREFILTER_SKIP` for the self-handled-only case. Net effect: huge-PR
#     coverage without losing the self-echo suppression.
#   - A silent thread resolve→reopen with no new comment does not bump a token
#     and so does not fire on that exact poll. Such a cycle surfaces on the
#     NEXT activity or the next reviewer wake — the reviewer re-fetches ALL
#     state on every wake. The cost is "caught a cycle late," never
#     "missed forever."
#   - The CI failure signal `FAILED_CHECKS` counts only `statusCheckRollup`
#     contexts in a failed/errored state (FAILURE, ERROR, TIMED_OUT,
#     CANCELLED, ACTION_REQUIRED for check runs; FAILURE, ERROR for legacy
#     statuses). PENDING / QUEUED / IN_PROGRESS / NEUTRAL / SUCCESS /
#     STARTUP_FAILURE are NOT counted. The count is derived from
#     `checkRunCountsByState` and `statusContextCountsByState` — both are
#     aggregate scalars that sum across ALL rollup contexts independent of
#     paging, so a failed check past page 1 still bumps `FAILED_CHECKS`.
#     This keeps `github-reviewer` step 3 (failed CI checks added as fix
#     candidates via `gh pr checks`) wired to a wake signal: when a reviewer
#     push lands and CI subsequently fails without any new review comment,
#     FAILED_CHECKS changes and fires CHANGED so the reviewer can remediate.
#     SUCCESS→PENDING / PENDING→SUCCESS transitions do not wake (they are
#     not actionable feedback). The signal is also a recovery beacon: when
#     failures clear, the count drops back to zero and fires CHANGED once,
#     surfacing the recovery via a reviewer wake that will return clean.
#
# Modes:
#   --snapshot <arm-kind>
#                ONE-SHOT baseline capture (`initial` | `re-arm`). Computes the
#                SAME scalar snapshot the poll diffs through the SAME query path
#                and emits one BASELINE= line stamped with that arm kind.
#   (no flag)    POLL. Watches the PR, diffing the first iteration against the
#                seed token and every later iteration against its predecessor.
#
# Why the seed exists (issue #324): the skill arms the Monitor only AFTER cycle 0
# finishes dispatching, so the whole cycle-0 duration is a BLIND WINDOW of
# unbounded length. A poll that self-baselined on its own first successful
# iteration counted everything posted inside that window as pre-existing and
# never fired CHANGED, losing that feedback for the life of the watch. Seeding
# the previous-snapshot scalars from a token captured BEFORE cycle 0 makes the
# first poll a REAL diff against pre-cycle-0 state, so blind-window feedback
# surfaces on the very first iteration.
#
# Markers emitted (one token-cheap line each):
#   CHANGED          a non-terminal delta in the scalar snapshot (wake reviewer)
#   STATE=MERGED     PR merged (terminal)
#   STATE=CLOSED     PR closed unmerged (terminal)
#   REVIEWER_APPROVED
#                    the in-scope automated-reviewer approval crossed into
#                    "present" against the seeded approval state. Whether an
#                    approval that PREDATES this arm counts as new is decided by
#                    the seed's ARM KIND, never by which fields the token carries
#                    (see ARM-KIND SEMANTICS below; skill confirms via reviewer
#                    before any terminal)
#   WATCH_TIMEOUT    max_watch_duration elapsed (terminal)
#   POLL_ERROR       repeated query failure, or a missing/malformed seed
#                    (terminal; skill returns blocked)
#   BASELINE=<seed>  --snapshot mode only: the seed token poll mode requires as
#                    its 8th argument (arm kind + every diffed scalar)
#   SNAPSHOT_ERROR   --snapshot mode only: the seed could not be captured
#                    (terminal; skill returns blocked)
#
# Positional arguments supplied by the skill when arming Monitor (all required;
# the skill/overlord layer resolves defaults and passes concrete values).
# --snapshot mode takes the flag, then the ARM KIND, then the same $1-$7:
#   $1  OWNER                   base-repo owner
#   $2  REPO                    base-repo name
#   $3  PR_NUMBER               integer PR number
#   $4  MAX_WATCH_SECONDS       integer seconds before WATCH_TIMEOUT
#   $5  POLL_INTERVAL_SECONDS   integer seconds between polls
#   $6  REVIEWER_FILTER         "automated" | "codex-only" | "all" | "<login>"
#                               (default "automated" when empty; modes are
#                               defined by reviewer-identity.jq)
#   $7  SELF_LOGIN              viewer login used to exclude self-authored
#                               activity from delta tokens (required)
#   $8  BASELINE_SEED           poll mode only: the BARE value of the BASELINE=
#                               line emitted by --snapshot (label stripped) —
#                               the arm kind followed by EVERY scalar the poll
#                               diffs. REQUIRED, never optional: an optional
#                               seed would let a caller silently regress to the
#                               self-baselining blind window, so a missing,
#                               malformed, or incomplete value is POLL_ERROR
#                               before the first poll.
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: compute_snapshot returns
# non-zero in the normal retry/backoff flow guarded by `if !`, pipefail is scoped per-pipeline
# inside subshells, and failures route through poll_fail() with explicit exit codes — a global
# `set -e` would abort the poll loop on the first transient gh hiccup.

set -u

# Mode dispatch. The sentinel cannot collide with a real OWNER: GitHub logins are
# alphanumeric-with-hyphens and may not BEGIN with a hyphen, so no owner can ever
# be the literal `--snapshot`.
MODE="poll"
ARM_KIND=""
if [ "${1:-}" = "--snapshot" ]; then
  MODE="snapshot"
  shift
  ARM_KIND="${1:-}"
  [ "$#" -eq 0 ] || shift
fi

OWNER="${1:-}"
REPO="${2:-}"
PR_NUMBER="${3:-}"
MAX_WATCH_SECONDS="${4:-}"
POLL_INTERVAL_SECONDS="${5:-}"
REVIEWER_FILTER="${6:-}"
SELF_LOGIN="${7:-}"
BASELINE_SEED="${8:-}"

# INVARIANT: SNAPSHOT_FIELDS is the SINGLE declaration of the poll's diffed
# state. compute_snapshot writes one `cur_<field>` per entry; the seed
# serializer, the seed parser, the seed-format regex, the completeness
# assertion, the CHANGED diff, and the end-of-iteration advance are ALL derived
# by iterating THIS list. There is no second place to add a scalar, so "the seed
# omits a scalar the poll diffs" is unrepresentable rather than merely fixed for
# one field: a scalar absent from this list is never diffed, and a scalar
# present in it is always serialized.
SNAPSHOT_FIELDS=(
  state
  nonself_comment_id
  filtered_review_id
  nonself_thread_id
  comments_total
  reviews_total
  threads_total
  failed_checks
  approval
)
# The approval edge is the ONE field that raises its own marker
# (REVIEWER_APPROVED) instead of folding into CHANGED, so the generic diff skips
# it by name. It is still serialized like every other field.
APPROVAL_FIELD="approval"

# An arm declares its KIND, and the kind travels inside the seed token rather
# than alongside it: carrying a seed forward (arm-expiry re-arm) therefore
# carries its kind forward with no caller bookkeeping.
ARM_KIND_ALTERNATION='initial|re-arm'
ARM_KIND_RE="^(${ARM_KIND_ALTERNATION})"'$'
# Seed shape: the arm kind followed by exactly one field per SNAPSHOT_FIELDS
# entry. The repeat count is DERIVED from the declaration, so adding a field
# retightens this regex automatically.
SEED_FORMAT_RE="^(${ARM_KIND_ALTERNATION})([|][A-Za-z0-9_-]+){${#SNAPSHOT_FIELDS[@]}}"'$'

# Validate inputs before any arithmetic or gh binding. Empty OWNER/REPO or a
# non-integer numeric arg would otherwise abort under set -u or corrupt the
# GraphQL Int binding / the $(( )) deadline math. Emits the terminal error
# marker of the mode this run was invoked in, then exits non-zero; every
# validation and capture failure routes through here. An optional reason
# argument is accepted and deliberately NOT emitted: the contracted stdout is the
# bare marker alone, and nothing is written to stderr.
poll_fail() {
  if [ "$MODE" = "snapshot" ]; then
    echo "SNAPSHOT_ERROR"
  else
    echo "POLL_ERROR"
  fi
  exit 1
}

# Resolve the sibling identity module RELATIVE to this script's own location
# (ADR-0020 C1): the poll runs as a direct sibling of reviewer-identity.jq, and
# every snapshot jq program loads it by search path. The shared GraphQL response
# check (plugin/skills/_shared/graphql-response.sh, two levels up) and the shared
# review-surface shape check (plugin/skills/_shared/review-surface-shape.sh) are
# sourced the same way; each defines functions only.
SCRIPT_DIR="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || poll_fail "cannot-self-locate"
[ -f "$SCRIPT_DIR/reviewer-identity.jq" ] || poll_fail "missing-identity-module"
[ -f "$SCRIPT_DIR/../../_shared/graphql-response.sh" ] || poll_fail "missing-graphql-check"
# shellcheck source=../../_shared/graphql-response.sh
. "$SCRIPT_DIR/../../_shared/graphql-response.sh" || poll_fail "unparseable-graphql-check"
[ -f "$SCRIPT_DIR/../../_shared/review-surface-shape.sh" ] || poll_fail "missing-review-surface-check"
# shellcheck source=../../_shared/review-surface-shape.sh
. "$SCRIPT_DIR/../../_shared/review-surface-shape.sh" || poll_fail "unparseable-review-surface-check"

# reset_snapshot_vars: clear every `cur_<field>` before a capture, so an
# indirect read of any declared field is always defined under `set -u`.
reset_snapshot_vars() {
  local field
  for field in "${SNAPSHOT_FIELDS[@]}"; do
    printf -v "cur_$field" '%s' ''
  done
}

# assert_snapshot_complete: every declared field must have been filled by
# compute_snapshot. A field declared but never computed is a loud failure here
# rather than an empty token field the caller would pass on as a valid baseline.
assert_snapshot_complete() {
  local field ref
  for field in "${SNAPSHOT_FIELDS[@]}"; do
    ref="cur_$field"
    [ -n "${!ref}" ] || return 1
  done
  return 0
}

# serialize_snapshot: the seed token — the arm kind followed by EVERY declared
# field in declaration order. Iterating the declaration is what makes an omitted
# scalar unrepresentable.
serialize_snapshot() {
  local kind="$1" field ref out
  out="$kind"
  for field in "${SNAPSHOT_FIELDS[@]}"; do
    ref="cur_$field"
    out="$out|${!ref}"
  done
  printf 'BASELINE=%s\n' "$out"
}

# load_seed: parse a seed token into ARM_KIND plus one `prev_<field>` per
# declared field, in the same order serialize_snapshot emitted them. Returns
# non-zero when the field count disagrees with the declaration or any field is
# empty — a partially-parsed seed would leave a prev_ scalar empty and fire a
# spurious CHANGED on the first poll.
load_seed() {
  local token="$1" field i
  local -a parts
  IFS='|' read -r -a parts <<EOF
$token
EOF
  [ "${#parts[@]}" -eq "$((${#SNAPSHOT_FIELDS[@]} + 1))" ] || return 1
  ARM_KIND="${parts[0]}"
  i=1
  for field in "${SNAPSHOT_FIELDS[@]}"; do
    [ -n "${parts[$i]}" ] || return 1
    printf -v "prev_$field" '%s' "${parts[$i]}"
    i=$((i + 1))
  done
  return 0
}

# snapshot_changed: 0 when any non-approval declared field differs from the
# previous snapshot. Derived from the declaration, so a newly declared scalar is
# diffed automatically and an undeclared one cannot be diffed at all.
snapshot_changed() {
  local field latest_ref earlier_ref
  for field in "${SNAPSHOT_FIELDS[@]}"; do
    [ "$field" != "$APPROVAL_FIELD" ] || continue
    latest_ref="cur_$field"
    earlier_ref="prev_$field"
    [ "${!latest_ref}" = "${!earlier_ref}" ] || return 0
  done
  return 1
}

# advance_snapshot: this iteration's scalars become the next iteration's
# previous, for every declared field including the approval edge.
advance_snapshot() {
  local field ref
  for field in "${SNAPSHOT_FIELDS[@]}"; do
    ref="cur_$field"
    printf -v "prev_$field" '%s' "${!ref}"
  done
}

[ -n "$OWNER" ] || poll_fail
[ -n "$REPO" ] || poll_fail
case "$PR_NUMBER" in ''|*[!0-9]*) poll_fail ;; esac
case "$MAX_WATCH_SECONDS" in ''|*[!0-9]*) poll_fail ;; esac
case "$POLL_INTERVAL_SECONDS" in ''|*[!0-9]*) poll_fail ;; esac
# Base-10-coerce before any arithmetic / numeric comparison. The digit-only case
# guards above guarantee decimal digits, but bash reads a leading-zero value as
# octal in $(( )) and [ -ge ] — 08/09 error under set -u, 060 mis-scales to 48s.
MAX_WATCH_SECONDS=$((10#$MAX_WATCH_SECONDS))
POLL_INTERVAL_SECONDS=$((10#$POLL_INTERVAL_SECONDS))
# Reject a zero (or otherwise non-positive) poll interval: `sleep 0` would make
# the loop re-poll immediately and hammer gh api until timeout, risking rate
# limits. Require at least one second between polls before entering the loop.
[ "$POLL_INTERVAL_SECONDS" -ge 1 ] || poll_fail
# SELF_LOGIN is required: without it, the jq filter cannot exclude self-authored
# activity and self-echo CHANGED storms return. REVIEWER_FILTER defaults to
# automated when empty; any non-empty string is accepted (a non-keyword value is
# the legacy login form).
[ -n "$SELF_LOGIN" ] || poll_fail
[ -n "$REVIEWER_FILTER" ] || REVIEWER_FILTER="automated"
# Snapshot mode must be told which kind of arm it is seeding; an absent or
# unknown kind is SNAPSHOT_ERROR rather than a token whose semantics are guessed
# downstream.
if [ "$MODE" = "snapshot" ]; then
  [[ "$ARM_KIND" =~ $ARM_KIND_RE ]] || poll_fail
fi
# The baseline seed is REQUIRED in poll mode and is validated STRICTLY, before
# the first poll or sleep: a partially-parsed seed would leave some prev_ scalar
# empty and fire a spurious CHANGED, and an absent one would re-open the #324
# blind window. Two layers, both derived from SNAPSHOT_FIELDS: the shape regex,
# then load_seed's field-count and non-empty checks.
if [ "$MODE" = "poll" ]; then
  [[ "$BASELINE_SEED" =~ $SEED_FORMAT_RE ]] || poll_fail
  load_seed "$BASELINE_SEED" || poll_fail
fi

# Timeout wrapper for gh API calls.
# Normal gh graphql/reactions completes in 1-5s; 45s is generous against
# transient slowness yet bounds a true hang far below Monitor's
# max_watch_duration, so two consecutive timeouts surface POLL_ERROR well
# inside any watch window.
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
  echo "github-review-loop: WARNING neither 'timeout' nor 'gtimeout' found on PATH; gh API calls in the change-detection poll are running UNGUARDED and a hung call can stall this poll until max_watch_duration. Install GNU coreutils (provides 'timeout'; 'gtimeout' on Homebrew) to restore the timeout guard." >&2
fi

deadline=$(($(date +%s) + MAX_WATCH_SECONDS))
fail_count=0

# compute_snapshot: fills the global scalar variables from ONE non-paginated
# GraphQL query (PR state + last 50 issue-comment databaseIds + last 50 review
# databaseIds with state and author + last 50 reviewThreads with their last
# comment databaseId and author + the totalCount of the comments, reviews, and
# reviewThreads connections + the `statusCheckRollup` contexts so a
# `FAILED_CHECKS` scalar can be derived) plus two exhaustive paginated approval
# reads — every per-author latest review (`latestReviews`, its own paginated
# GraphQL query) and every REST reaction — folded into ONE in-scope approval
# bool (an approver's LATEST review APPROVED, OR PR 👍, each from its registry
# approver kind). The `latestReviews` `first: 100` is a page size, not a
# bound; a walk that fails on any page fails the capture.
# Returns 0 on success, non-zero on failure of the query, either approval walk,
# or any identity jq evaluation, on a GraphQL response (the snapshot body or
# any `latestReviews` page) that the shared graphql-response.sh check rejects —
# gh exits 0 on several error envelopes, so its exit status alone is not success —
# and on a snapshot body the shared review-surface-shape.sh check rejects (a lost
# connection or per-thread `comments` would otherwise project as no activity).
# Each id token is a single max-databaseId across the author-filtered stream —
# self-only flurries (own replies, own pushes) do not bump any token,
# eliminating self-echo CHANGED storms. "Self" is the module's `is_self` over
# each node's login AND `__typename` (both selected for that reason): only a
# User-typed SELF_LOGIN author is self, so a Bot sharing the login, or a node
# with no type, still bumps its token (fail toward wake). The totalCount scalars
# are tripwires for activity past the 50-node page boundary: when it bumps the
# totalCount but not the id token, CHANGED still fires and the reviewer
# re-fetches all on wake. `FAILED_CHECKS` is the count of `statusCheckRollup`
# contexts in a failed/errored state (FAILURE / ERROR / TIMED_OUT / CANCELLED /
# ACTION_REQUIRED for CheckRun; FAILURE / ERROR for legacy StatusContext);
# changes here fire CHANGED so `github-reviewer` step 3 (failed-CI fix
# candidates) is wired to a wake signal independent of review activity. The
# reviewer does the full body-level classification on wake (thin poll, no
# interpretation). Writes diagnostic stderr to /dev/null (never /tmp).
compute_snapshot() {
  local snapshot_body raw line review_pages review_rows review_approved reaction_rows thumbs_approved

  # gh exits 0 on several GraphQL error envelopes, so its exit status alone never
  # proves a usable response: the body is captured first and must pass the shared
  # hivemind_graphql_response_check, then the shared
  # hivemind_review_surface_shape_check, before any field is projected from it.
  # The shape check rejects a hollow body (a null pullRequest, a null or absent
  # comments / reviews / reviewThreads connection or `nodes` list, a null thread,
  # or a thread whose `comments` connection or `nodes` list is lost) that the
  # projection below would otherwise read as no activity: a silently missed wake.
  # A rejected body fails the capture; each check's token is discarded because
  # the contracted stdout is the bare marker alone.
  snapshot_body=$("${GH_TIMEOUT[@]}" gh api graphql \
    -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUMBER" \
    -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      state
      comments(last: 50) {
        totalCount
        nodes { databaseId author { login __typename } }
      }
      reviews(last: 50) {
        totalCount
        nodes { databaseId state author { login __typename } }
      }
      reviewThreads(first: 50) {
        totalCount
        nodes {
          comments(last: 1) {
            nodes { databaseId author { login __typename } }
          }
        }
      }
      statusCheckRollup {
        contexts(first: 0) {
          checkRunCountsByState { state count }
          statusContextCountsByState { state count }
        }
      }
    }
  }
}' 2>/dev/null) || return 1
  hivemind_graphql_response_check "$snapshot_body" >/dev/null || return 1
  hivemind_review_surface_shape_check "$snapshot_body" >/dev/null || return 1

  raw=$( ( set -o pipefail; printf '%s' "$snapshot_body" \
    | jq -r -L "$SCRIPT_DIR" --arg login "$SELF_LOGIN" --arg filter "$REVIEWER_FILTER" '
    include "reviewer-identity";
    .data.repository.pullRequest as $pr |
    ($pr.comments.nodes
      | map(select(is_self(.author.login; .author.__typename; $login) | not))
      | map(.databaseId)
      | (if length == 0 then "NONE" else max | tostring end)) as $nonself_comment |
    ($pr.reviews.nodes
      | map(select(.state as $s | ["CHANGES_REQUESTED","COMMENTED","APPROVED","DISMISSED"] | index($s)))
      | map(select(reviewer_matches_filter(.author.login; .author.__typename; $login; $filter)))
      | map(.databaseId)
      | (if length == 0 then "NONE" else max | tostring end)) as $filtered_review |
    ($pr.reviewThreads.nodes
      | map(.comments.nodes[]?)
      | map(select(is_self(.author.login; .author.__typename; $login) | not))
      | map(.databaseId)
      | (if length == 0 then "NONE" else max | tostring end)) as $nonself_thread |
    # FAILED_CHECKS: sum rollup state-count buckets for failed/errored
    # terminal states across ALL contexts (independent of paging). Using
    # `checkRunCountsByState` and `statusContextCountsByState` avoids the
    # first-100-contexts blind spot the previous `contexts(first: 100)`
    # walk had: a failed check past page 1 still bumps FAILED_CHECKS, so
    # `github-reviewer` step 3 (failed CI checks added as fix candidates)
    # stays wired even on PRs with many checks. CheckRun states reported
    # here are the post-completion conclusions surfaced via CheckRunState
    # (FAILURE / TIMED_OUT / CANCELLED / ACTION_REQUIRED — the first four
    # treated as failures; STARTUP_FAILURE is excluded as infrastructure
    # noise). StatusContext state buckets are FAILURE / ERROR. Anything
    # else — PENDING / QUEUED / IN_PROGRESS / NEUTRAL / SUCCESS / SKIPPED
    # / STARTUP_FAILURE / STALE — is NOT counted. A null rollup means no
    # checks have run yet; count 0.
    # RECORDED RESIDUAL (linked finding a303b3ee): the `// []` and `// 0`
    # defaults below are the correct reading, not a degradation. In the
    # published schema pullRequest.statusCheckRollup is NULLABLE (null = no
    # checks yet) and both CountsByState fields are NULLABLE lists of
    # non-null buckets, so a null at either position arrives WITHOUT an
    # `errors` entry and means no failed checks. `contexts` and each bucket
    # `state` and `count` are non-null, so a lost one arrives only with an
    # `errors` entry, which the envelope check rejects before this program
    # runs. A string, number, boolean, or array where the rollup object
    # belongs raises a jq error and fails the capture. Inherited: these
    # reads are byte-identical to main. Obvious remediation considered and
    # rejected on the merits: a gate that rejects a null rollup or a null
    # bucket list would fail the capture on every PR with no checks.
    # Residual window: an absent field, a `false` or an object where a
    # bucket list belongs, or a null bucket, shapes only a server violating
    # its own schema can send. The query-derived shape check that would
    # close that window is tracked in issue #328.
    (
      ((($pr.statusCheckRollup.contexts.checkRunCountsByState // [])
        | map(select(.state == "FAILURE" or .state == "TIMED_OUT" or .state == "CANCELLED" or .state == "ACTION_REQUIRED"))
        | map(.count) | add) // 0)
      +
      ((($pr.statusCheckRollup.contexts.statusContextCountsByState // [])
        | map(select(.state == "FAILURE" or .state == "ERROR"))
        | map(.count) | add) // 0)
    ) as $failed_checks |
    "STATE=" + $pr.state,
    "LATEST_NONSELF_ISSUE_COMMENT_ID=" + $nonself_comment,
    "LATEST_FILTERED_REVIEW_ID=" + $filtered_review,
    "LATEST_NONSELF_THREAD_COMMENT_ID=" + $nonself_thread,
    "COMMENTS_TOTAL=" + ($pr.comments.totalCount | tostring),
    "REVIEWS_TOTAL=" + ($pr.reviews.totalCount | tostring),
    "THREADS_TOTAL=" + ($pr.reviewThreads.totalCount | tostring),
    "FAILED_CHECKS=" + ($failed_checks | tostring)
  ' \
  ) ) || return 1

  # Parse the labeled scalar lines. Read the captured string directly — no pipe
  # into Monitor.
  while IFS= read -r line; do
    case "$line" in
      STATE=*) cur_state="${line#STATE=}" ;;
      LATEST_NONSELF_ISSUE_COMMENT_ID=*) cur_nonself_comment_id="${line#LATEST_NONSELF_ISSUE_COMMENT_ID=}" ;;
      LATEST_FILTERED_REVIEW_ID=*) cur_filtered_review_id="${line#LATEST_FILTERED_REVIEW_ID=}" ;;
      LATEST_NONSELF_THREAD_COMMENT_ID=*) cur_nonself_thread_id="${line#LATEST_NONSELF_THREAD_COMMENT_ID=}" ;;
      COMMENTS_TOTAL=*) cur_comments_total="${line#COMMENTS_TOTAL=}" ;;
      REVIEWS_TOTAL=*) cur_reviews_total="${line#REVIEWS_TOTAL=}" ;;
      THREADS_TOTAL=*) cur_threads_total="${line#THREADS_TOTAL=}" ;;
      FAILED_CHECKS=*) cur_failed_checks="${line#FAILED_CHECKS=}" ;;
    esac
  done <<EOF
$raw
EOF

  # Review approval is CURRENT state read from GitHub, never rebuilt from review
  # history: `latestReviews` holds the latest submitted review of each author, so
  # a later COMMENTED, CHANGES_REQUESTED, or DISMISSED review from the same
  # approver supersedes an earlier APPROVED. The read is an EXHAUSTIVE paginated
  # walk in its own query (gh follows only one paginated connection per query):
  # `first: 100` is the page size, not a bound, so an approver past any number of
  # other authors is still read. The walk carries NO --jq: under --paginate gh
  # runs --jq once per page and cannot load a module, so no envelope check could
  # run inside it. The raw page stream (every page's JSON object concatenated) is
  # captured whole and must pass the shared hivemind_graphql_pages_check, which
  # rejects the stream when ANY page carries a GraphQL error envelope. Only then
  # does a local jq (no -s, so it reads each concatenated page in turn) project
  # one compact row `{state, login, type}` per entry across every page; the
  # identity decision then runs locally over every row at once. A failed later
  # page, a rejected page, or a null connection (a jq iteration error) fails the
  # capture, so no approval verdict is ever drawn from a partial or errored
  # walk. A walk whose pages hold no entries slurps to `[]` (no approval).
  review_pages=$("${GH_TIMEOUT[@]}" gh api graphql --paginate \
    -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUMBER" \
    -f query='
query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      latestReviews(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes { state author { login __typename } }
      }
    }
  }
}' \
    2>/dev/null) || return 1
  hivemind_graphql_pages_check "$review_pages" >/dev/null || return 1
  review_rows=$(printf '%s' "$review_pages" \
    | jq -c '.data.repository.pullRequest.latestReviews.nodes[] | {state, login: .author.login, type: .author.__typename}' \
    2>/dev/null) || return 1
  review_approved=$(printf '%s' "$review_rows" \
    | jq -s -r -L "$SCRIPT_DIR" --arg login "$SELF_LOGIN" --arg filter "$REVIEWER_FILTER" '
      include "reviewer-identity";
      any(.[];
          .state == "APPROVED"
          and reviewer_is_approver(.login; .type; "review-approved")
          and reviewer_matches_filter(.login; .type; $login; $filter))
    ' 2>/dev/null) || return 1

  # PR 👍 via the paginated REST reactions endpoint. The gh --jq filter is pure
  # TRANSPORT: it emits one JSON object `{login, type}` per +1 reaction and
  # makes NO identity decision (gh may apply --jq per page, so rows concatenate
  # across pages). Each row is `tojson`-encoded because gh prints a string
  # result raw and uncolored, one per line; the local jq parses the rows back
  # as JSON values, so no login byte can be read as a field boundary. The
  # identity decision runs locally over all rows at once, through the module,
  # so the 100-node GraphQL blind spot and the per-page slurp pitfall are both
  # avoided. Empty input slurps to `[]` (no approval); a row that is not JSON
  # is a jq error and fails the capture.
  reaction_rows=$("${GH_TIMEOUT[@]}" gh api --paginate "repos/$OWNER/$REPO/issues/$PR_NUMBER/reactions" \
    --jq '.[] | select(.content == "+1") | {login: .user.login, type: .user.type} | tojson' \
    2>/dev/null) || return 1
  thumbs_approved=$(printf '%s' "$reaction_rows" \
    | jq -s -r -L "$SCRIPT_DIR" --arg login "$SELF_LOGIN" --arg filter "$REVIEWER_FILTER" '
      include "reviewer-identity";
      any(.[];
          reviewer_is_approver(.login; .type; "pr-reaction-thumbs-up")
          and reviewer_matches_filter(.login; .type; $login; $filter))
    ' 2>/dev/null) || return 1

  case "$review_approved" in true|false) ;; *) return 1 ;; esac
  case "$thumbs_approved" in true|false) ;; *) return 1 ;; esac
  if [ "$review_approved" = "true" ] || [ "$thumbs_approved" = "true" ]; then
    cur_approval="true"
  else
    cur_approval="false"
  fi

  # A well-formed snapshot always carries a non-empty PR state.
  [ -n "${cur_state:-}" ] || return 1
  return 0
}

# --snapshot: one-shot baseline capture, emitted as a single pipe-separated
# token stamped with the arm kind it seeds. It is a COMPLETE serialization —
# every scalar the poll diffs, the approval bool included — so no field the diff
# reads can be absent from the token. A seed that cannot be captured, or that
# leaves any declared field empty, is loud (SNAPSHOT_ERROR, exit 1) rather than
# a partial token the caller would pass on as a valid baseline.
if [ "$MODE" = "snapshot" ]; then
  reset_snapshot_vars
  compute_snapshot || poll_fail
  assert_snapshot_complete || poll_fail
  serialize_snapshot "$ARM_KIND"
  exit 0
fi

# Previous-snapshot scalars, seeded from the --snapshot token captured BEFORE
# cycle 0 so the FIRST poll is a real diff rather than a self-baselining no-op
# (#324). load_seed already filled every prev_<field> from the token above.
#
# ARM-KIND SEMANTICS. The seed carries the approval bool like every other
# scalar, so "does an approval that predates this arm surface?" is answered
# ONCE, by the arm's KIND, instead of per-scalar by which fields the token
# happens to carry:
#   initial — this watch has never observed the approval edge. Treat it as
#             UNOBSERVED: an approval already present when the watch started
#             fires REVIEWER_APPROVED on the first poll, so an approval that
#             landed in the #324 blind window cannot idle the loop to
#             WATCH_TIMEOUT (D14).
#   re-arm  — the seed was captured immediately before a reviewer pass that
#             consumed this exact state. The approval edge IS observed, so the
#             serialized bool stands and a stale approval predating that pass
#             never re-fires to short-circuit later pushback.
if [ "$ARM_KIND" = "initial" ]; then
  printf -v "prev_$APPROVAL_FIELD" '%s' ''
fi

while true; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "WATCH_TIMEOUT"
    exit 0
  fi

  reset_snapshot_vars

  # A declared field left unfilled is treated as a failed capture in BOTH modes:
  # diffing an empty scalar would fire a spurious CHANGED instead of failing.
  if ! compute_snapshot || ! assert_snapshot_complete; then
    fail_count=$((fail_count + 1))
    if [ "$fail_count" -ge 2 ]; then
      echo "POLL_ERROR"
      exit 1
    fi
    sleep "$POLL_INTERVAL_SECONDS"
    continue
  fi
  fail_count=0

  # Terminal PR state takes precedence over any other delta.
  if [ "$cur_state" = "MERGED" ]; then
    echo "STATE=MERGED"
    exit 0
  fi
  if [ "$cur_state" = "CLOSED" ]; then
    echo "STATE=CLOSED"
    exit 0
  fi

  # An in-scope approval newly present is its own marker (the skill runs a
  # confirmation pass rather than treating it as a generic CHANGED delta). What
  # counts as "newly" on the FIRST iteration is set by ARM-KIND SEMANTICS above —
  # terminal clean ONLY if nothing actionable remains (D14).
  if [ "$cur_approval" = "true" ] && [ "$prev_approval" != "true" ]; then
    echo "REVIEWER_APPROVED"
  elif snapshot_changed; then
    echo "CHANGED"
  fi
  # No-change iteration: emit nothing.

  advance_snapshot

  sleep "$POLL_INTERVAL_SECONDS"
done
