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
#     errored state; a RISE in it against the previous snapshot or seed raises
#     its own `CI_FAILED` marker, so a CI regression wakes the reviewer directly
#     even when no new review comment was posted) plus ONE Reviewer Approval
#     bool (an Automated
#     Reviewer whose LATEST review is APPROVED, or COMMENTED with zero inline
#     review comments, read from GitHub's per-author `latestReviews` and never
#     rebuilt from review history, OR a 👍 reaction on the PR from an Automated
#     Reviewer; both scoped by the active reviewer filter). Both approval reads
#     are EXHAUSTIVE paginated walks (`latestReviews` in its own paginated
#     GraphQL query, the reactions over paginated REST): the `latestReviews`
#     `first: 100` is a page size, not a bound, and a walk that fails on any
#     page fails the capture rather than judging approval from a partial
#     fetch. No bodies — the poll only answers "did anything change?" and "is
#     the PR terminal?".
#   - Every reviewer IDENTITY decision (self identity, login normalization,
#     the Automated Reviewer set, filter scope, approval state, the retired
#     filter value) is delegated to the sibling jq module `reviewer-identity.jq`
#     (ADR-0043), loaded by `jq -L "$SCRIPT_DIR"`. This script carries no login
#     literal, login compare, or suffix-strip regex of its own; a missing module
#     is a terminal error before the first gh call. Each capture derives ONE
#     Automated Reviewer set from the PR evidence it fetched (snapshot review
#     authors, `latestReviews` authors, 👍 reactors) plus the optional
#     HIVEMIND_PR_REVIEWERS value, passed to jq as data and never as program
#     text, and every identity program of that capture uses that one set.
#   - It DIFFS the scalar snapshot in bash against the previous iteration and
#     emits a single minimal marker line ONLY on a real delta or a terminal
#     state. The reviewer re-fetches ALL feedback bodies and does the full
#     classification on wake; the poll never interprets.
#   - A no-change iteration emits NOTHING (silent) → Monitor feeds nothing back
#     → the model is never woken → zero model tokens during idle.
#   - It reads each gh command's stdout directly via command substitution. There
#     is NO functional pipe (`tail -f | grep`, etc.) feeding Monitor.
#   - No /tmp. No stop-file. Every terminal marker and `REVIEWER_APPROVED` end
#     the process themselves; `CHANGED` and `CI_FAILED` keep it running (the
#     CONTINUING_MARKERS declaration); the skill natively stops only an arm that
#     is still running.
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
#     This keeps the reviewer's ci-check-failure fix candidates (failed CI
#     checks read via `gh pr checks`) wired to a wake signal of their own.
#     RISE RULE: when `cur_failed_checks` is greater than the previous
#     snapshot's (or the seed's) count, compared as base-10 integers, the poll
#     prints `CI_FAILED`, which the skill dispatches to the reviewer directly,
#     never through `prefilter.sh` (it judges only the review surfaces, so a
#     wake whose only change is the failed-check count would be skipped and
#     the failure lost once the poll advances its baseline). A DROP is not a
#     rise: it fires `CHANGED`, which the prefilter judges on the review
#     surfaces like any other delta, and red CI that stays red at the same
#     count raises nothing, so a steady red run never re-dispatches.
#     SUCCESS→PENDING / PENDING→SUCCESS transitions do not wake (they are
#     not actionable feedback).
#   - A re-failure that keeps the SAME failed count across a push landing
#     between two polls (one check goes green, another goes red) raises no
#     marker: the scalar never moved. Inherited from main. It is picked up on
#     the next rise or on any other reviewer wake, since the reviewer reads
#     every failed check on each wake.
#   - An expired arm re-armed from an older seed diffs against that seed, so
#     it can re-fire `CI_FAILED` once while CI stays red for a failure a
#     reviewer pass already saw. Bounded by the skill's cycle and
#     same-finding guards; red CI stays visible on the PR, and agents never
#     merge.
#
# Modes:
#   --snapshot <arm-kind>
#                ONE-SHOT baseline capture (`initial` | `re-arm`). Computes the
#                SAME scalar snapshot the poll diffs through the SAME query path
#                and emits one BASELINE= line stamped with that arm kind.
#   --check      ONE-SHOT compare for the skill's QUIET-EXIT CHECK. Takes the
#                same $1-$8 as poll mode (seed required), computes ONE snapshot
#                through the SAME query path, runs the poll's own marker decision
#                once against the seed, and prints that marker (CI_FAILED
#                included) or UNCHANGED. No sleep, no deadline, no baseline line.
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
#   CHANGED          a non-terminal delta in the scalar snapshot (wake reviewer
#                    through the prefilter), a FAILED_CHECKS drop included
#   CI_FAILED        FAILED_CHECKS rose against the previous snapshot or seed
#                    (non-terminal; the skill dispatches the reviewer directly,
#                    without the prefilter)
#   STATE=MERGED     PR merged (terminal)
#   STATE=CLOSED     PR closed unmerged (terminal)
#   REVIEWER_APPROVED
#                    the in-scope automated-reviewer approval crossed into
#                    "present" against the seeded approval state. Whether an
#                    approval that PREDATES this arm counts as new is decided by
#                    the seed's ARM KIND, never by which fields the token carries
#                    (see ARM-KIND SEMANTICS below). ENDS THIS PROCESS (exit 0)
#                    but is NOT a loop terminal: the skill confirms via the
#                    reviewer before any terminal
#   WATCH_TIMEOUT    max_watch_duration elapsed (terminal); no sleep passes
#                    the deadline, so it is never late by more than one capture
#   POLL_ERROR       repeated query failure, a missing/malformed seed, a
#                    retired reviewer filter value, or an unreadable clock
#                    (terminal; skill returns blocked)
#   BASELINE=<seed>  --snapshot mode only: the seed token poll mode requires as
#                    its 8th argument (arm kind + every diffed scalar)
#   SNAPSHOT_ERROR   --snapshot mode only: the seed could not be captured, or
#                    the reviewer filter value is retired (terminal; skill
#                    returns blocked)
#   UNCHANGED        --check mode only: the snapshot raised no marker against
#                    the seed
#   CHECK_ERROR      --check mode only: a missing/malformed seed, a retired
#                    reviewer filter value, or a failed capture (terminal)
#
# Marker precedence within one iteration: STATE=MERGED, STATE=CLOSED,
# REVIEWER_APPROVED, CI_FAILED, then CHANGED; exactly one is printed. The
# approval goes before CI_FAILED because its confirmation pass is a full fix
# pass that also picks up failed checks.
#
# Process lifetime: `CHANGED` and `CI_FAILED` are the ONLY markers after which
# the poll keeps running, declared once in CONTINUING_MARKERS. Every other
# marker is the last line the process prints. --check prints exactly one line
# and exits.
#
# Positional arguments supplied by the skill when arming Monitor (all required;
# the skill/overlord layer resolves defaults and passes concrete values).
# --snapshot mode takes the flag, then the ARM KIND, then the same $1-$7.
# --check mode takes the flag, then the same $1-$8:
#   $1  OWNER                   base-repo owner
#   $2  REPO                    base-repo name
#   $3  PR_NUMBER               integer PR number
#   $4  MAX_WATCH_SECONDS       integer seconds before WATCH_TIMEOUT
#   $5  POLL_INTERVAL_SECONDS   integer seconds between polls; a sleep never
#                               passes the deadline, so the last one before
#                               WATCH_TIMEOUT is cut to the seconds left
#   $6  REVIEWER_FILTER         "automated" | "all" | "<login>"
#                               (default "automated" when empty; modes are
#                               defined by reviewer-identity.jq). A value the
#                               module's `is_retired_filter` names is the
#                               mode's error marker, exit 1, before any gh
#                               call; select one reviewer with `<login>`.
#
# Environment:
#   HIVEMIND_PR_REVIEWERS       optional; more Bot logins for the Automated
#                               Reviewer set (comma- or whitespace-separated).
#                               It only adds to the evidence-derived set.
#   $7  SELF_LOGIN              viewer login used to exclude self-authored
#                               activity from delta tokens (required)
#   $8  BASELINE_SEED           poll and --check modes: the BARE value of the
#                               BASELINE= line emitted by --snapshot (label
#                               stripped) — the arm kind followed by EVERY
#                               scalar the poll diffs. REQUIRED, never optional:
#                               an optional seed would let a caller silently
#                               regress to the self-baselining blind window, so
#                               a missing, malformed, or incomplete value, or a
#                               failed_checks field that read_decimal rejects,
#                               is POLL_ERROR (CHECK_ERROR in --check mode)
#                               before any gh call.
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: compute_snapshot returns
# non-zero in the normal retry/backoff flow guarded by `if !`, pipefail is scoped per-pipeline
# inside subshells, and failures route through poll_fail() with explicit exit codes — a global
# `set -e` would abort the poll loop on the first transient gh hiccup.

set -u

# Mode dispatch. The sentinels cannot collide with a real OWNER: GitHub logins
# are alphanumeric-with-hyphens and may not BEGIN with a hyphen, so no owner can
# ever be the literal `--snapshot` or `--check`.
MODE="poll"
ARM_KIND=""
if [ "${1:-}" = "--snapshot" ]; then
  MODE="snapshot"
  shift
  ARM_KIND="${1:-}"
  [ "$#" -eq 0 ] || shift
elif [ "${1:-}" = "--check" ]; then
  MODE="check"
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
# INVARIANT: CONTINUING_MARKERS is the SINGLE declaration of the markers after
# which the poll keeps running; the main loop asks marker_continues, and every
# other marker ends the process.
CONTINUING_MARKERS=(
  CHANGED
  CI_FAILED
)

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
  elif [ "$MODE" = "check" ]; then
    echo "CHECK_ERROR"
  else
    echo "POLL_ERROR"
  fi
  exit 1
}

# read_decimal <name> <value>: when the value is 1 to 18 decimal digits, assign
# its base-10 value to the variable <name> and return 0; otherwise return 1 and
# assign nothing. It declares no locals, so no target name can collide with one.
# INVARIANT: read_decimal is the script's only bounded-decimal check and its
# only base-10 coercion, and every number the script does arithmetic or a
# numeric test on is read through it or read_clock, never checked at its use
# site. Bash arithmetic is signed 64-bit and wraps silently; 18 digits stay
# below 2^63 with room for the epoch the deadline adds, so no accepted value can
# wrap. The base-10 coercion keeps a leading zero from reading as octal (08/09
# error under set -u, 060 mis-scales to 48), and a normalized value also
# compares equal as text to a capture of the same count.
read_decimal() {
  [[ "${2:-}" =~ ^[0-9]{1,18}$ ]] || return 1
  printf -v "$1" '%s' "$((10#$2))"
}

# read_clock <name>: hold the script's only date command. Assigns the epoch
# seconds to the variable <name> through read_decimal; a non-zero date exit or a
# reading read_decimal rejects is poll_fail. Always called in the main shell,
# never inside $( ), so poll_fail ends the poll rather than a subshell. Its one
# local is clock_reading, which no caller uses as a target name.
read_clock() {
  local clock_reading
  clock_reading="$(date +%s)" || poll_fail
  read_decimal "$1" "$clock_reading" || poll_fail
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

# failed_checks_rose: 0 when the current FAILED_CHECKS count is greater than the
# previous one. Both counts were read through read_decimal, the seed's before any
# gh call and the capture's inside compute_snapshot, so both are base-10 values
# and the compare needs no coercion of its own.
failed_checks_rose() {
  [ "$cur_failed_checks" -gt "$prev_failed_checks" ]
}

# marker_continues: 0 when the poll keeps running after printing the given
# marker, i.e. it is listed in CONTINUING_MARKERS.
marker_continues() {
  local marker="$1" continuing
  for continuing in "${CONTINUING_MARKERS[@]}"; do
    [ "$marker" != "$continuing" ] || return 0
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

# iteration_marker: the ONE marker decision over the current snapshot against
# the previous one. Echoes STATE=MERGED or STATE=CLOSED (terminal PR state takes
# precedence over any other delta), REVIEWER_APPROVED (an in-scope approval
# newly present), CI_FAILED (FAILED_CHECKS rose), CHANGED (any other
# non-approval declared field differs, a FAILED_CHECKS drop included), or
# nothing.
# INVARIANT: the poll loop and --check both decide through this function, so the
# QUIET-EXIT CHECK can never judge a seed differently from the poll it stands in for.
iteration_marker() {
  if [ "$cur_state" = "MERGED" ]; then
    echo "STATE=MERGED"
  elif [ "$cur_state" = "CLOSED" ]; then
    echo "STATE=CLOSED"
  elif [ "$cur_approval" = "true" ] && [ "$prev_approval" != "true" ]; then
    echo "REVIEWER_APPROVED"
  elif failed_checks_rose; then
    echo "CI_FAILED"
  elif snapshot_changed; then
    echo "CHANGED"
  fi
}

[ -n "$OWNER" ] || poll_fail
[ -n "$REPO" ] || poll_fail
# The numeric args are read through read_decimal, the one source of checked
# base-10 numbers, before any gh binding, arithmetic or numeric comparison.
read_decimal PR_NUMBER "$PR_NUMBER" || poll_fail
read_decimal MAX_WATCH_SECONDS "$MAX_WATCH_SECONDS" || poll_fail
read_decimal POLL_INTERVAL_SECONDS "$POLL_INTERVAL_SECONDS" || poll_fail
# Reject a zero (or otherwise non-positive) poll interval: `sleep 0` would make
# the loop re-poll immediately and hammer gh api until timeout, risking rate
# limits. Require at least one second between polls before entering the loop.
[ "$POLL_INTERVAL_SECONDS" -ge 1 ] || poll_fail
# SELF_LOGIN is required: without it, the jq filter cannot exclude self-authored
# activity and self-echo CHANGED storms return. REVIEWER_FILTER defaults to
# automated when empty; any other non-empty string is accepted (a non-keyword
# value is the login form) except the retired value the module names, which is
# rejected here, before any gh call, in every mode. The verdict must be exactly
# `false` to proceed, so a failed jq evaluation also fails closed.
[ -n "$SELF_LOGIN" ] || poll_fail
[ -n "$REVIEWER_FILTER" ] || REVIEWER_FILTER="automated"
retired_filter=$(jq -n -r -L "$SCRIPT_DIR" --arg filter "$REVIEWER_FILTER" '
  include "reviewer-identity";
  is_retired_filter($filter)
' 2>/dev/null) || poll_fail
[ "$retired_filter" = "false" ] || poll_fail
# Snapshot mode must be told which kind of arm it is seeding; an absent or
# unknown kind is SNAPSHOT_ERROR rather than a token whose semantics are guessed
# downstream.
if [ "$MODE" = "snapshot" ]; then
  [[ "$ARM_KIND" =~ $ARM_KIND_RE ]] || poll_fail
fi
# The baseline seed is REQUIRED in poll and --check modes and is validated
# STRICTLY, before any gh call or sleep: a partially-parsed seed would leave some
# prev_ scalar empty and fire a spurious CHANGED, and an absent one would re-open
# the #324 blind window. Two layers, both derived from SNAPSHOT_FIELDS: the shape
# regex, then load_seed's field-count and non-empty checks. The failed_checks
# field is then read through read_decimal, since failed_checks_rose compares it
# as a number.
if [ "$MODE" = "poll" ] || [ "$MODE" = "check" ]; then
  [[ "$BASELINE_SEED" =~ $SEED_FORMAT_RE ]] || poll_fail
  load_seed "$BASELINE_SEED" || poll_fail
  read_decimal prev_failed_checks "$prev_failed_checks" || poll_fail
fi

# Timeout wrapper for gh API calls.
# Normal gh graphql/reactions completes in 1-5s; 45s is generous against
# transient slowness yet bounds a true hang. The bound is 45s per gh call, not
# derived from the time left: a capture runs several gh calls, so a window
# shorter than one capture can end that late, past the deadline.
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

fail_count=0

# compute_snapshot: fills the global scalar variables from ONE non-paginated
# GraphQL query (PR state + last 50 issue-comment databaseIds + last 50 review
# databaseIds with state and author + last 50 reviewThreads with their last
# comment databaseId and author + the totalCount of the comments, reviews, and
# reviewThreads connections + the `statusCheckRollup` contexts so a
# `FAILED_CHECKS` scalar can be derived) plus two exhaustive paginated approval
# reads — every per-author latest review (`latestReviews`, its own paginated
# GraphQL query) and every REST reaction — folded into ONE in-scope approval
# bool (an Automated Reviewer's LATEST review passing `is_review_approval`, OR
# its PR 👍). The `latestReviews` `first: 100` is a page size, not a bound; a
# walk that fails on any page fails the capture. The three gh calls run first;
# the Automated Reviewer set is then derived once from their evidence, and the
# snapshot projection and both approval programs all judge identity over it.
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
# ACTION_REQUIRED for CheckRun; FAILURE / ERROR for legacy StatusContext); a
# rise here fires CI_FAILED, dispatched to the reviewer without the prefilter,
# so the reviewer's ci-check-failure fix candidates are wired to a wake signal
# independent of review activity, and a drop fires CHANGED. The count is read
# through read_decimal, and a count it rejects fails the capture. The
# reviewer does the full body-level classification on wake (thin poll, no
# interpretation). Writes diagnostic stderr to /dev/null (never /tmp).
compute_snapshot() {
  local snapshot_body raw line review_pages review_rows reaction_rows snapshot_review_rows reviewer_set review_approved thumbs_approved

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

  # Review approval is CURRENT state read from GitHub, never rebuilt from review
  # history: `latestReviews` holds the latest submitted review of each author, so
  # a later CHANGES_REQUESTED or DISMISSED review, or a COMMENTED review with
  # inline comments, from the same reviewer supersedes an earlier approval. The
  # read is an EXHAUSTIVE paginated walk in its own query (gh follows only one
  # paginated connection per query): `first: 100` is the page size, not a bound,
  # so a reviewer past any number of other authors is still read. The walk
  # carries NO --jq: under --paginate gh runs --jq once per page and cannot load
  # a module, so no envelope check could run inside it. The raw page stream
  # (every page's JSON object concatenated) is captured whole and must pass the
  # shared hivemind_graphql_pages_check, which rejects the stream when ANY page
  # carries a GraphQL error envelope. Only then does a local jq (no -s, so it
  # reads each concatenated page in turn) project one compact row
  # `{state, login, type, comments}` per entry across every page, `comments`
  # being the entry's inline review comment count; the identity decision then
  # runs locally over every row at once. A failed later page, a rejected page,
  # or a null connection (a jq iteration error) fails the capture, so no
  # approval verdict is ever drawn from a partial or errored walk. A walk whose
  # pages hold no entries slurps to `[]` (no approval).
  review_pages=$("${GH_TIMEOUT[@]}" gh api graphql --paginate \
    -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUMBER" \
    -f query='
query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      latestReviews(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes { state author { login __typename } comments { totalCount } }
      }
    }
  }
}' \
    2>/dev/null) || return 1
  hivemind_graphql_pages_check "$review_pages" >/dev/null || return 1
  review_rows=$(printf '%s' "$review_pages" \
    | jq -c '.data.repository.pullRequest.latestReviews.nodes[] | {state, login: .author.login, type: .author.__typename, comments: .comments.totalCount}' \
    2>/dev/null) || return 1

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

  # The Automated Reviewer set of THIS capture, derived once by the module's
  # `automated_reviewer_set` from the evidence the three reads returned: the
  # snapshot's review authors, every `latestReviews` author, and every 👍
  # reactor (only `{login, type}` is read from each row). HIVEMIND_PR_REVIEWERS
  # reaches jq as `--arg` data, never as program text, and only adds to the set.
  # The set is a compact JSON array handed to every identity program below, so
  # the filtered review token and both approval reads judge the same set. A jq
  # failure here, or a set that is not valid JSON, fails the capture.
  snapshot_review_rows=$(printf '%s' "$snapshot_body" \
    | jq -c '.data.repository.pullRequest.reviews.nodes[] | {login: .author.login, type: .author.__typename}' \
    2>/dev/null) || return 1
  reviewer_set=$(printf '%s\n%s\n%s\n' "$snapshot_review_rows" "$review_rows" "$reaction_rows" \
    | jq -s -c -L "$SCRIPT_DIR" --arg reviewers "${HIVEMIND_PR_REVIEWERS-}" '
      include "reviewer-identity";
      automated_reviewer_set(.; $reviewers)
    ' 2>/dev/null) || return 1

  raw=$( ( set -o pipefail; printf '%s' "$snapshot_body" \
    | jq -r -L "$SCRIPT_DIR" --arg login "$SELF_LOGIN" --arg filter "$REVIEWER_FILTER" \
      --argjson set "$reviewer_set" '
    include "reviewer-identity";
    .data.repository.pullRequest as $pr |
    ($pr.comments.nodes
      | map(select(is_self(.author.login; .author.__typename; $login) | not))
      | map(.databaseId)
      | (if length == 0 then "NONE" else max | tostring end)) as $nonself_comment |
    ($pr.reviews.nodes
      | map(select(.state as $s | ["CHANGES_REQUESTED","COMMENTED","APPROVED","DISMISSED"] | index($s)))
      | map(select(reviewer_matches_filter(.author.login; .author.__typename; $login; $filter; $set)))
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
    # the ci-check-failure fix candidates of the reviewer (failed CI
    # checks) stay wired even on PRs with many checks. CheckRun states reported
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

  # Approval: a `latestReviews` row whose state passes `is_review_approval`, or a
  # 👍 row, from an author that is an Automated Reviewer of this capture's set
  # AND matches the active filter. A missing or null inline count is never an
  # approval.
  review_approved=$(printf '%s' "$review_rows" \
    | jq -s -r -L "$SCRIPT_DIR" --arg login "$SELF_LOGIN" --arg filter "$REVIEWER_FILTER" \
      --argjson set "$reviewer_set" '
      include "reviewer-identity";
      any(.[];
          is_review_approval(.state; .comments)
          and is_automated_reviewer(.login; .type; $set)
          and reviewer_matches_filter(.login; .type; $login; $filter; $set))
    ' 2>/dev/null) || return 1
  thumbs_approved=$(printf '%s' "$reaction_rows" \
    | jq -s -r -L "$SCRIPT_DIR" --arg login "$SELF_LOGIN" --arg filter "$REVIEWER_FILTER" \
      --argjson set "$reviewer_set" '
      include "reviewer-identity";
      any(.[];
          is_automated_reviewer(.login; .type; $set)
          and reviewer_matches_filter(.login; .type; $login; $filter; $set))
    ' 2>/dev/null) || return 1

  case "$review_approved" in true|false) ;; *) return 1 ;; esac
  case "$thumbs_approved" in true|false) ;; *) return 1 ;; esac
  if [ "$review_approved" = "true" ] || [ "$thumbs_approved" = "true" ]; then
    cur_approval="true"
  else
    cur_approval="false"
  fi
  # A well-formed snapshot always carries a non-empty PR state and a
  # failed-check count read_decimal accepts.
  [ -n "${cur_state:-}" ] || return 1
  read_decimal cur_failed_checks "${cur_failed_checks:-}" || return 1
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

# --check: ONE-SHOT compare for the skill's QUIET-EXIT CHECK. One capture, the
# poll's own marker decision against the seed, one line out. A failed or
# incomplete capture is CHECK_ERROR (exit 1); it is never retried, never sleeps,
# never reads the deadline, and never advances or re-emits a seed.
# RECORDED RESIDUAL (linked local-review finding 91655d29, iter2,
# approval-exit lifecycle): activity between this check and the skill's
# terminal report is unseen. Root cause: any watcher must stop at a terminal,
# so a gap always exists after the last look; the same gap is WATCH_TIMEOUT's
# final sleep interval and an expired arm's last interval, inherited from
# main. Bounded impact: seconds or one poll interval, on a PR the loop no
# longer owns; agents never merge, and the activity stays on the PR for the
# human who merges. Obvious remediation considered and rejected on the merits:
# keeping a poll alive past the terminal needs a Monitor running after the
# loop returns (forbidden; nothing would consume its events) or TaskStop (the
# dependency the self-exit removed).
if [ "$MODE" = "check" ]; then
  reset_snapshot_vars
  compute_snapshot || poll_fail
  assert_snapshot_complete || poll_fail
  check_marker="$(iteration_marker)"
  echo "${check_marker:-UNCHANGED}"
  exit 0
fi

# sleep_to_next_poll: hold the only sleep in this script. Reads the clock once
# through read_clock and sleeps the smaller of POLL_INTERVAL_SECONDS and the
# seconds left to the deadline; with none left it returns without sleeping, so
# the loop top emits WATCH_TIMEOUT. An unreadable clock is POLL_ERROR.
# INVARIANT: no poll sleep passes the deadline, for every accepted interval and
# window, including a re-arm whose window is smaller than the interval.
sleep_to_next_poll() {
  local now_seconds seconds_left nap_seconds
  read_clock now_seconds
  seconds_left=$((deadline - now_seconds))
  [ "$seconds_left" -gt 0 ] || return 0
  nap_seconds="$POLL_INTERVAL_SECONDS"
  [ "$seconds_left" -lt "$nap_seconds" ] && nap_seconds="$seconds_left"
  sleep "$nap_seconds"
}

read_clock arm_seconds
deadline=$((arm_seconds + MAX_WATCH_SECONDS))

while true; do
  read_clock clock_seconds
  if [ "$clock_seconds" -ge "$deadline" ]; then
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
    sleep_to_next_poll
    continue
  fi
  fail_count=0

  # An in-scope approval newly present is its own marker (the skill runs a
  # confirmation pass rather than treating it as a generic CHANGED delta). What
  # counts as "newly" on the FIRST iteration is set by ARM-KIND SEMANTICS above —
  # terminal clean ONLY if nothing actionable remains (D14). A FAILED_CHECKS
  # rise is CI_FAILED, which the skill dispatches without the prefilter; any
  # other non-approval delta, a drop included, is CHANGED. Only the markers in
  # CONTINUING_MARKERS (CHANGED, CI_FAILED) keep the poll running; every other
  # marker ends the process here. Exiting on REVIEWER_APPROVED is safe because
  # every exit from the confirmation pass diffs the pending seed before the watch
  # goes quiet. A productive return arms a fresh poll from it; a return that would
  # end clean or keep watching with no poll running runs --check against it first
  # (SKILL.md step 6, QUIET-EXIT CHECK).
  iteration_marker_line="$(iteration_marker)"
  if [ -n "$iteration_marker_line" ]; then
    echo "$iteration_marker_line"
    marker_continues "$iteration_marker_line" || exit 0
  fi
  # No-change iteration: emit nothing.

  advance_snapshot

  sleep_to_next_poll
done
