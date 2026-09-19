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
#     and self-login); totalCount tripwires for the three connections capped at
#     50; a CI `FAILED_CHECKS` scalar that counts only checks in a failed/
#     errored state, so CI regressions wake the reviewer even when no new review
#     comment was posted) plus a Codex 👍 PRESENT bool (via paginated REST
#     reactions). No bodies, no cursor walks — the poll only answers "did
#     anything change?" and "is the PR terminal?".
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
#   --snapshot   ONE-SHOT baseline capture. Computes the SAME scalar snapshot
#                through the SAME query path a poll iteration uses, emits one
#                BASELINE= line, and exits. The skill captures this BEFORE
#                cycle 0 starts dispatching.
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
#   CODEX_APPROVED   Codex 👍 newly present, including one already present when
#                    the watch started: the seed carries NO Codex bool, so a
#                    pre-existing 👍 surfaces through the ordinary false->true
#                    diff on the first poll (skill confirms via reviewer;
#                    terminal clean only if nothing actionable remains)
#   WATCH_TIMEOUT    max_watch_duration elapsed (terminal)
#   POLL_ERROR       repeated query failure, or a missing/malformed seed
#                    (terminal; skill returns blocked)
#   BASELINE=<seed>  --snapshot mode only: the seed token poll mode requires as
#                    its 8th argument
#   SNAPSHOT_ERROR   --snapshot mode only: the seed could not be captured
#                    (terminal; skill returns blocked)
#
# Positional arguments supplied by the skill when arming Monitor (all required;
# the skill/overlord layer resolves defaults and passes concrete values).
# --snapshot mode takes the flag FIRST followed by the same $1-$7:
#   $1  OWNER                   base-repo owner
#   $2  REPO                    base-repo name
#   $3  PR_NUMBER               integer PR number
#   $4  MAX_WATCH_SECONDS       integer seconds before WATCH_TIMEOUT
#   $5  POLL_INTERVAL_SECONDS   integer seconds between polls
#   $6  REVIEWER_FILTER         "codex-only" | "all" | "<login>"
#                               (default "codex-only" when empty)
#   $7  SELF_LOGIN              viewer login used to exclude self-authored
#                               activity from delta tokens (required)
#   $8  BASELINE_SEED           poll mode only: the BARE value of the BASELINE=
#                               line emitted by --snapshot (label stripped) —
#                               8 pipe-separated fields carrying the 8 scalars
#                               the poll diffs. REQUIRED, never optional: an
#                               optional seed would let a caller silently
#                               regress to the self-baselining blind window, so
#                               a missing or malformed value is POLL_ERROR
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
if [ "${1:-}" = "--snapshot" ]; then
  MODE="snapshot"
  shift
fi

OWNER="${1:-}"
REPO="${2:-}"
PR_NUMBER="${3:-}"
MAX_WATCH_SECONDS="${4:-}"
POLL_INTERVAL_SECONDS="${5:-}"
REVIEWER_FILTER="${6:-}"
SELF_LOGIN="${7:-}"
BASELINE_SEED="${8:-}"

# Validate inputs before any arithmetic or gh binding. Empty OWNER/REPO or a
# non-integer numeric arg would otherwise abort under set -u or corrupt the
# GraphQL Int binding / the $(( )) deadline math. Emits the terminal error
# marker of the mode this run was invoked in, then exits non-zero; every
# validation and capture failure routes through here.
poll_fail() {
  if [ "$MODE" = "snapshot" ]; then
    echo "SNAPSHOT_ERROR"
  else
    echo "POLL_ERROR"
  fi
  exit 1
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
# codex-only when empty; any non-empty string is accepted as a login form.
[ -n "$SELF_LOGIN" ] || poll_fail
[ -n "$REVIEWER_FILTER" ] || REVIEWER_FILTER="codex-only"
# The baseline seed is REQUIRED in poll mode and is validated STRICTLY, before
# the first poll or sleep: a partially-parsed seed would leave some prev_ scalar
# empty and fire a spurious CHANGED, and an absent one would re-open the #324
# blind window. Shape: exactly 8 non-empty fields over the charset --snapshot
# emits — the PR state enum, NONE-or-digits id tokens, and digit counts.
SEED_FORMAT_RE='^[A-Z0-9]+([|][A-Z0-9]+){7}$'
if [ "$MODE" = "poll" ]; then
  [[ "$BASELINE_SEED" =~ $SEED_FORMAT_RE ]] || poll_fail
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
# comment databaseId and author + the totalCount of each of those three
# connections + the `statusCheckRollup` contexts so a `FAILED_CHECKS` scalar
# can be derived) plus a paginated REST reactions read for the Codex 👍 bool.
# Returns 0 on success, non-zero on failure of the query or the reactions call.
# Each id token is a single max-databaseId across the author-filtered stream —
# self-only flurries (own replies, own pushes) do not bump any token,
# eliminating self-echo CHANGED storms. The totalCount scalars are tripwires
# for activity past the 50-node page boundary: when it bumps the totalCount but
# not the id token, CHANGED still fires and the reviewer re-fetches all on
# wake. `FAILED_CHECKS` is the count of `statusCheckRollup` contexts in a
# failed/errored state (FAILURE / ERROR / TIMED_OUT / CANCELLED /
# ACTION_REQUIRED for CheckRun; FAILURE / ERROR for legacy StatusContext);
# changes here fire CHANGED so `github-reviewer` step 3 (failed-CI fix
# candidates) is wired to a wake signal independent of review activity. The
# reviewer does the full body-level classification on wake (thin poll, no
# interpretation). Writes diagnostic stderr to /dev/null (never /tmp).
compute_snapshot() {
  local raw line

  raw=$( ( set -o pipefail; \
    "${GH_TIMEOUT[@]}" gh api graphql \
      -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUMBER" \
      -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      state
      comments(last: 50) {
        totalCount
        nodes { databaseId author { login } }
      }
      reviews(last: 50) {
        totalCount
        nodes { databaseId state author { login } }
      }
      reviewThreads(first: 50) {
        totalCount
        nodes {
          comments(last: 1) {
            nodes { databaseId author { login } }
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
}' 2>/dev/null \
    | jq -r --arg login "$SELF_LOGIN" --arg filter "$REVIEWER_FILTER" '
    .data.repository.pullRequest as $pr |
    ($pr.comments.nodes
      | map(select((.author.login // "" | sub("\\[bot\\]$"; "")) != $login))
      | map(.databaseId)
      | (if length == 0 then "NONE" else max | tostring end)) as $nonself_comment |
    ($pr.reviews.nodes
      | map(select(.state as $s | ["CHANGES_REQUESTED","COMMENTED","APPROVED","DISMISSED"] | index($s)))
      | map(select(
          (.author.login // "" | sub("\\[bot\\]$"; "")) as $a |
          if $filter == "codex-only" then $a == "chatgpt-codex-connector"
          elif $filter == "all" then $a != $login
          else $a == $filter
          end))
      | map(.databaseId)
      | (if length == 0 then "NONE" else max | tostring end)) as $filtered_review |
    ($pr.reviewThreads.nodes
      | map(.comments.nodes[]?)
      | map(select((.author.login // "" | sub("\\[bot\\]$"; "")) != $login))
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

  # Codex 👍 via the paginated REST reactions endpoint. The --jq filter emits the
  # matching login ONCE per Codex +1 reaction and nothing otherwise; gh may apply
  # --jq per page, so aggregate to a bool in bash (non-empty output = present).
  # This avoids a 100-node GraphQL blind spot and the per-page slurp pitfall.
  local codex_logins
  codex_logins=$("${GH_TIMEOUT[@]}" gh api --paginate "repos/$OWNER/$REPO/issues/$PR_NUMBER/reactions" \
    --jq '.[] | select(.content == "+1") | ((.user.login // "") | sub("\\[bot\\]$"; "")) | select(. == "chatgpt-codex-connector")' \
    2>/dev/null) || return 1
  if [ -n "$codex_logins" ]; then
    cur_codex="true"
  else
    cur_codex="false"
  fi

  # A well-formed snapshot always carries a non-empty PR state.
  [ -n "${cur_state:-}" ] || return 1
  return 0
}

# --snapshot: one-shot baseline capture, emitted as a single pipe-separated
# token. It carries the 8 scalars the poll diffs and NOT the Codex 👍 bool —
# leaving prev_codex empty in poll mode is what keeps a pre-existing approval
# surfacing through the ordinary false->true diff. A seed that cannot be
# captured is loud (SNAPSHOT_ERROR, exit 1) rather than an empty token the
# caller would pass on as a valid baseline.
if [ "$MODE" = "snapshot" ]; then
  cur_state=""; cur_nonself_comment_id=""; cur_filtered_review_id=""
  cur_nonself_thread_id=""; cur_codex=""
  cur_comments_total=""; cur_reviews_total=""; cur_threads_total=""
  cur_failed_checks=""

  compute_snapshot || poll_fail

  printf 'BASELINE=%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$cur_state" "$cur_nonself_comment_id" "$cur_filtered_review_id" \
    "$cur_nonself_thread_id" "$cur_comments_total" "$cur_reviews_total" \
    "$cur_threads_total" "$cur_failed_checks"
  exit 0
fi

# Previous-snapshot scalars, seeded from the --snapshot token captured BEFORE
# cycle 0 so the FIRST poll is a real diff rather than a self-baselining no-op
# (#324). The field order matches the printf above. prev_codex is deliberately
# left EMPTY: the seed carries no Codex bool, so a 👍 already present when the
# watch starts still fires CODEX_APPROVED via the normal false->true diff on the
# first poll (D14) instead of needing a baseline special case.
IFS='|' read -r prev_state prev_nonself_comment_id prev_filtered_review_id \
  prev_nonself_thread_id prev_comments_total prev_reviews_total \
  prev_threads_total prev_failed_checks <<EOF
$BASELINE_SEED
EOF
prev_codex=""

while true; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "WATCH_TIMEOUT"
    exit 0
  fi

  cur_state=""; cur_nonself_comment_id=""; cur_filtered_review_id=""
  cur_nonself_thread_id=""; cur_codex=""
  cur_comments_total=""; cur_reviews_total=""; cur_threads_total=""
  cur_failed_checks=""

  if ! compute_snapshot; then
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

  # Codex 👍 newly present is its own marker (the skill runs a confirmation pass
  # rather than treating it as a generic CHANGED delta). On the first iteration
  # prev_codex is empty, so an approval already present when the watch started
  # fires here too — terminal clean ONLY if nothing actionable remains (D14).
  if [ "$cur_codex" = "true" ] && [ "$prev_codex" != "true" ]; then
    echo "CODEX_APPROVED"
  elif [ "$cur_state" != "$prev_state" ] \
    || [ "$cur_nonself_comment_id" != "$prev_nonself_comment_id" ] \
    || [ "$cur_filtered_review_id" != "$prev_filtered_review_id" ] \
    || [ "$cur_nonself_thread_id" != "$prev_nonself_thread_id" ] \
    || [ "$cur_comments_total" != "$prev_comments_total" ] \
    || [ "$cur_reviews_total" != "$prev_reviews_total" ] \
    || [ "$cur_threads_total" != "$prev_threads_total" ] \
    || [ "$cur_failed_checks" != "$prev_failed_checks" ]; then
    echo "CHANGED"
  fi
  # No-change iteration: emit nothing.

  prev_state="$cur_state"
  prev_nonself_comment_id="$cur_nonself_comment_id"
  prev_filtered_review_id="$cur_filtered_review_id"
  prev_nonself_thread_id="$cur_nonself_thread_id"
  prev_comments_total="$cur_comments_total"
  prev_reviews_total="$cur_reviews_total"
  prev_threads_total="$cur_threads_total"
  prev_failed_checks="$cur_failed_checks"
  prev_codex="$cur_codex"

  sleep "$POLL_INTERVAL_SECONDS"
done
