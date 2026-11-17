#!/usr/bin/env bash
#
# Behavioral unit runner for the thin PR change-detection poll (issue #324).
#
# OFFLINE bash TEST — CI-runnable with ONLY bash + jq present (NO tmux / gh / network). It drives:
#   plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh
# through a PATH-shim fake `gh` that serves canned fixture bytes from tests/change-detect-poll/.
# The REAL `jq` runs the script's REAL filters over those bytes, so the snapshot derivation under
# test is the production one — only the transport, the watch-deadline clock and the interval
# sleep are faked (a PATH-shim fake `date` and fake `sleep`, see "PATH-shim fake date" and
# "PATH-shim fake sleep" below).
#
# Mirrors tools/test_react_marker.sh's pass/fail counter + per-case assertion + exit-nonzero-on-any
# -fail convention, extended with a THIRD counter (SKIP) for the cases that exercise the seeded
# baseline contract that does not exist yet on main. Read-only: the only writes are scratch state
# under a disposable tmpdir removed on EXIT.
#
# WHAT THIS PROVES (the bite): pr-change-detect-poll.sh treats its FIRST successful poll as the
# baseline — it emits nothing and records everything already present as seen. The skill arms the
# Monitor only AFTER cycle 0 finishes dispatching (SKILL.md Lifecycle steps 2-3), so the whole
# cycle-0 duration is a BLIND WINDOW: feedback posted inside it missed cycle 0's fetch AND is
# counted as pre-existing by the poll, so it never produces a CHANGED event.
#
# THE SEED PROBE: the fix adds a `--snapshot` mode emitting a `BASELINE=<arm kind + one field per
# diffed scalar>` token captured BEFORE cycle 0, passed back as a REQUIRED 8th positional arg to
# poll mode. The suite PROBES the script under test for `--snapshot` support rather than assuming
# it:
#   - ABSENT  → cases run against the legacy 7-arg form; the seed-contract cases SKIP visibly.
#   - PRESENT → the seed is captured at the pre-cycle-0 state and passed as arg 8; the
#               seed-contract cases RUN.
# Post-merge the probe doubles as a regression guard: if seed support ever disappears, the
# bite-proof case goes red again instead of silently passing.
#
# HARNESS-ASSUMED SEED CONTRACT (asserted, not guessed silently): snapshot mode is invoked as
#   pr-change-detect-poll.sh --snapshot <initial|re-arm> <OWNER> <REPO> <PR> <MAX_WATCH>
#     <INTERVAL> <FILTER> <SELF>
# and emits one `BASELINE=<value>` line; the BARE <value> (no `BASELINE=` label) is arg 8 of poll
# mode. Snapshot failure emits `SNAPSHOT_ERROR` and exits 1.
#
# THE STATE-MODEL CONTRACT this suite holds (the second bite, PR #361):
#   - COMPLETE SERIALIZATION. The seed serializes EVERY scalar the poll diffs. `seed:complete-
#     serialization` is STRUCTURAL, not per-scalar: it reads the script's own `SNAPSHOT_FIELDS`
#     declaration and the set of `cur_<name>` assignments and asserts they are the same set, so a
#     future author who adds a diffed scalar without declaring it goes red. Per-scalar assertions
#     are exactly what let the omitted approval bool through twice.
#   - EXPLICIT ARM KIND. Whether an approval predating the arm surfaces is answered by the seed's
#     ARM KIND, not by which fields the token carries: `initial` surfaces it (#324 blind window),
#     `re-arm` suppresses it (a stale approval must never short-circuit later pushback).
#
# THE REVIEWER-IDENTITY CONTRACT (ADR-0043): every login / filter / approval decision is the
# shared `reviewer-identity.jq` module's, and no reviewer product is named in code. Each capture
# derives ONE Automated Reviewer set from the PR evidence it read (snapshot review authors,
# `latestReviews` authors, 👍 reactors; Bot accounts only, `github-actions` only when listed) plus
# HIVEMIND_PR_REVIEWERS. The poll's approval scalar is true when an Automated Reviewer in scope of
# the active filter left a 👍 on the PR, or its latest review, as GitHub's per-author
# `latestReviews` reports it, is APPROVED or COMMENTED with zero inline review comments; it
# surfaces as `REVIEWER_APPROVED`. A Bot account is the module's `is_bot`: typed `Bot`, OR a raw
# login ending in the reserved `[bot]` suffix — the REST reactions endpoint types a bot reactor
# `User`, so a bot 👍 arrives User-typed with a `[bot]`-suffixed login, and the committed bot
# reaction fixtures carry exactly that shape. The approval is read from `latestReviews`, never
# rebuilt from the bounded `reviews` history window, by an exhaustive paginated walk in its own
# query: `first: 100` is the page size, not a bound, and a walk that fails on any page fails the
# capture. The fake gh models gh's GraphQL pagination contract, so a walk that stops at page 1 or
# judges a partial walk goes red. Reactions and latest-review rows travel as one JSON object per
# row, so a login carrying a delimiter byte cannot forge the account type. An empty filter slot
# defaults to `automated`; the retired filter value is rejected in every mode before any gh call.
# The suite unsets HIVEMIND_PR_REVIEWERS at the top, and a case that needs it sets it on its own
# call only.
#
# THE GRAPHQL RESPONSE CONTRACT (#393): gh exits 0 on several GraphQL error envelopes, so an
# exit-0 response is usable only when the shared plugin/skills/_shared/graphql-response.sh check
# accepts it. A snapshot body carrying a top-level `errors` value, or a `latestReviews` walk with
# such a value on ANY page, fails the capture (SNAPSHOT_ERROR / POLL_ERROR) and never yields a
# baseline, a delta, or an approval verdict. A snapshot body that has lost part of the
# review-activity skeleton (a null pullRequest, a null or absent connection or `nodes` list, a null
# thread, or a thread whose `comments` connection is lost) fails the capture the same way through
# the shared plugin/skills/_shared/review-surface-shape.sh check, while a genuinely empty PR (every
# `nodes` list `[]`) still yields a valid baseline.
#
# THE PROCESS-LIFETIME CONTRACT: `CHANGED` and `CI_FAILED` are the only markers after which the
# poll keeps running. `REVIEWER_APPROVED` and every terminal marker are the last line the process
# prints, so an approval co-firing with a delta never trails a later `CHANGED` or `CI_FAILED` from
# an orphaned poll.
#
# THE CI ROUTE CONTRACT (#400): a RISE in FAILED_CHECKS against the previous snapshot or the seed
# prints `CI_FAILED`, never `CHANGED`, so the skill dispatches the reviewer without the prefilter.
# A drop, or red CI that stays red at the same count, never prints `CI_FAILED`: a drop and any
# other delta print `CHANGED`. One marker per iteration, in the order STATE=MERGED, STATE=CLOSED,
# REVIEWER_APPROVED, CI_FAILED, CHANGED. A seed whose failed_checks field is not all digits fails
# closed before any gh call.
#
# THE QUIET-EXIT CHECK CONTRACT: a return that would end the watch clean, or keep watching with no
# poll running, first runs
#   pr-change-detect-poll.sh --check <OWNER> <REPO> <PR> <MAX_WATCH> <INTERVAL> <FILTER> <SELF>
#     <SEED>
# against the pending seed. It takes ONE capture through the poll's own query path, decides through
# the poll's own `iteration_marker`, and prints exactly one line (`STATE=MERGED`, `STATE=CLOSED`,
# `REVIEWER_APPROVED`, `CI_FAILED`, `CHANGED`, or `UNCHANGED`), exit 0, so its line equals the line a poll armed
# with the same seed prints first over the same state, with that poll's `WATCH_TIMEOUT` read as
# `UNCHANGED`. A missing or malformed seed is `CHECK_ERROR`, exit 1, before any gh call; a failed
# capture is `CHECK_ERROR`, exit 1, never retried.
#
# THE WATCH-LIFETIME CONTRACT: no poll sleep outruns the watch window. Every sleep, the
# failed-capture retry included, goes through the poll's one helper, sleep_to_next_poll, which
# sleeps the smaller of the poll interval and the seconds left to the deadline, or not at all when
# none is left, so the loop top prints `WATCH_TIMEOUT` on time for every accepted interval and
# window, including a re-arm whose window is smaller than the interval. The executable lines of the
# poll hold exactly one `sleep` command, inside that helper, so a second raw sleep goes red.
#
# THE CHECKED-NUMBER CONTRACT: every number the poll reads from outside itself (an argument, the
# seed, a gh capture, the clock) is read through one of two helpers, and every other number it does
# arithmetic or a numeric test on is a script-internal integer computed only from literals and
# checked numbers. read_decimal is the only bounded-decimal check (1 to 18 digits) and
# the only base-10 coercion; read_clock holds the only `date` command and routes its reading
# through read_decimal. A failed or bad clock reading, at any of the three clock reads (arm time,
# the loop-top deadline check, sleep_to_next_poll), is POLL_ERROR, exit 1, and a 19-digit PR number
# is POLL_ERROR before any gh call. `--snapshot` and `--check` never read the clock. No scan of the
# poll's text decides whether a number is checked: Bash evaluates a number in many syntax forms, so
# a list of them cannot be complete. The rule is held by running the poll with hostile and
# zero-padded readings at every source the contract names (the PR number, window and interval
# arguments, the seed's failed_checks field, a capture's check count, the clock). A hostile reading
# that arithmetic would run creates a canary file when any form evaluates it before its check, and
# a zero-padded reading changes the output when any use skips the base-10 coercion. A new source of
# numbers is a new row of that grid. One structural case remains: the executable lines hold exactly
# one `date` command, inside read_clock.
#
# Usage:
#   ./tools/test_change_detect_poll.sh

set -u
# INVARIANT: an inherited HIVEMIND_PR_REVIEWERS would widen every case's Automated Reviewer set.
unset HIVEMIND_PR_REVIEWERS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
POLL="$REPO_ROOT/plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh"
FIXTURES="$REPO_ROOT/tests/change-detect-poll"

[ -f "$POLL" ] || { echo "FAIL: script under test missing: $POLL" >&2; exit 2; }
[ -d "$FIXTURES" ] || { echo "FAIL: fixture dir missing: $FIXTURES" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required by the script under test" >&2; exit 2; }

TMPDIR_TEST="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skipped() { echo "SKIP [$1] $2"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

# Poll args held fixed across cases. MAX_WATCH=3 / INTERVAL=1 yields EXACTLY three polls then
# WATCH_TIMEOUT: the fake `date` advances the deadline clock one virtual second per snapshot
# query, so the window counts polls, not wall-clock seconds, and a case passes or fails the same
# way under any CPU load.
OWNER="hive-org"
REPO_NAME="hive-repo"
PR_NUMBER="4242"
MAX_WATCH=3
POLL_INTERVAL=1
REVIEWER_FILTER="automated"
RETIRED_FILTER="codex-only"
SELF_LOGIN="hive-author"
# Bot login shapes the identity cases share: one per real-world naming pattern plus a generic one
# and the CI identity. GraphQL reports each as a Bot-typed bare login; REST adds `[bot]` and types
# the reactor `User`.
CODEX_SHAPED_BOT="chatgpt-codex-connector"
COPILOT_SHAPED_BOT="copilot-pull-request-reviewer"
GENERIC_BOT="acme-review-helper"
CI_BOT="github-actions"
STATUS_BOT="coverage-reporter"

PRE="$FIXTURES/graphql-pre-cycle0.json"
BLIND="$FIXTURES/graphql-blind-window.json"
MALFORMED="$FIXTURES/graphql-malformed.json"
REACT_NONE="$FIXTURES/reactions-none.json"
REACT_CODEX="$FIXTURES/reactions-codex.json"
REACT_HUMAN="$FIXTURES/reactions-human.json"
REACT_FORGED="$FIXTURES/reactions-forged.json"
REACT_CODEX_EYES="$FIXTURES/reactions-codex-eyes.json"

# ── PATH-shim fake gh ───────────────────────────────────────────────────────────────
# Serves a per-call fixture from a state dir: <kind>.seq lists one fixture path per line and
# <kind>.n is the call counter; call N serves line N, clamping to the last line so a steady
# state can be served indefinitely. The literal entry `FAIL` makes the call exit non-zero
# (a gh transport failure). Every entry is a raw API response: `graphql` responses are raw
# GraphQL JSON piped into the script's real jq filter, and reactions entries are raw REST pages.
# When the call carries `--jq`, the stub applies the script's OWN `--jq` expression to each
# served page with the real jq (`-r`, matching gh printing string results raw), so the
# production transport expression runs; a jq error on any page exits non-zero, and a call
# without `--jq` serves the raw bytes. Only the reactions read carries `--jq`: the snapshot query
# and the `latestReviews` walk carry none, so both are served raw — a `.pages` walk as every
# page's JSON object concatenated, exactly the stream the script hands to the shared
# graphql-response.sh check before projecting any row itself.
#
# Call kinds: `reactions` (the REST reactions path), `latestreviews` (a `graphql` call carrying
# `--paginate`, the paginated per-author latest-reviews walk), and `graphql` (the snapshot query).
# With no `latestreviews.seq`, a `latestreviews` call MIRRORS the `graphql.seq` entry at its OWN
# counter, so every committed state fixture (each carries a `latestReviews` connection) serves both
# calls. Caveat: the two counters advance independently, so a sequence whose `graphql` call fails
# mid-sequence (a `FAIL` or malformed entry before a good one) desynchronises the mirror; such a
# case sets its own `latestreviews.seq`.
#
# A sequence entry ending `.pages` is a paginated walk: a file listing one page path per line,
# served in order as one paginated call. A `FAIL` line exits non-zero after printing the earlier
# pages (a later page failing mid-walk). Pages after the first are served ONLY when the
# whitespace-normalized query declares `$endCursor: String`, passes `after: $endCursor`, and
# selects `pageInfo { hasNextPage endCursor }`; otherwise only page 1 is served, as real gh
# returns a single page for a query it cannot walk.
STUB_BIN="$TMPDIR_TEST/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -u
set -o pipefail
kind=""
jq_expr=""
query_text=""
want_jq=0
saw_graphql=0
saw_paginate=0
for arg in "$@"; do
  if [ "$want_jq" -eq 1 ]; then
    jq_expr="$arg"
    want_jq=0
    continue
  fi
  case "$arg" in
    graphql) saw_graphql=1 ;;
    repos/*/reactions) kind="reactions" ;;
    --paginate) saw_paginate=1 ;;
    --jq) want_jq=1 ;;
    query=*) query_text="${arg#query=}" ;;
  esac
done
if [ -z "$kind" ] && [ "$saw_graphql" -eq 1 ]; then
  kind="graphql"
  [ "$saw_paginate" -eq 0 ] || kind="latestreviews"
fi
[ -n "$kind" ] || { echo "fake gh: unrecognized call: $*" >&2; exit 1; }
[ -n "${FAKE_GH_STATE_DIR:-}" ] || { echo "fake gh: FAKE_GH_STATE_DIR unset" >&2; exit 1; }
seq_file="$FAKE_GH_STATE_DIR/$kind.seq"
n_file="$FAKE_GH_STATE_DIR/$kind.n"
if [ "$kind" = "latestreviews" ] && [ ! -f "$seq_file" ]; then
  seq_file="$FAKE_GH_STATE_DIR/graphql.seq"
fi
[ -f "$seq_file" ] || { echo "fake gh: no sequence for $kind" >&2; exit 1; }
n=$(cat "$n_file" 2>/dev/null || printf '0')
n=$((n + 1))
printf '%s' "$n" > "$n_file"
total=$(wc -l < "$seq_file")
[ "$n" -le "$total" ] || n="$total"
entry=$(sed -n "${n}p" "$seq_file")
[ "$entry" != "FAIL" ] || exit 1

# serve_page <path>: one page of the response.
# INVARIANT: gh stdout never carries CR; a core.autocrlf checkout of a fixture would otherwise
# carry CR into the bytes the script parses.
serve_page() {
  if [ -n "$jq_expr" ]; then
    tr -d '\r' < "$1" | jq -r "$jq_expr"
  else
    tr -d '\r' < "$1"
  fi
}

# query_walks_pages: 0 when the whitespace-normalized query carries the full GraphQL cursor
# contract gh --paginate needs to request a page after the first.
query_walks_pages() {
  local norm_query
  norm_query=$(printf '%s' "$query_text" | tr -s '[:space:]' ' ')
  case "$norm_query" in *'$endCursor: String'*) ;; *) return 1 ;; esac
  case "$norm_query" in *'after: $endCursor'*) ;; *) return 1 ;; esac
  case "$norm_query" in *'pageInfo { hasNextPage endCursor }'*) ;; *) return 1 ;; esac
  return 0
}

case "$entry" in
  *.pages) ;;
  *) serve_page "$entry" || exit 1; exit 0 ;;
esac
page_number=0
while IFS= read -r page || [ -n "$page" ]; do
  page="${page%$'\r'}"
  [ -n "$page" ] || continue
  page_number=$((page_number + 1))
  if [ "$page_number" -gt 1 ]; then
    [ "$saw_paginate" -eq 1 ] && query_walks_pages || exit 0
  fi
  [ "$page" != "FAIL" ] || exit 1
  serve_page "$page" || exit 1
done < "$entry"
exit 0
STUB
chmod +x "$STUB_BIN/gh"

# ── PATH-shim fake date ─────────────────────────────────────────────────────────────
# The poll's watch window is a wall-clock deadline: `date +%s` once at arm time, then again
# before every poll. Under CPU contention (validate.sh runs suites in parallel) the stubbed
# captures can overrun a 3 s real window before the poll that carries a case's delta, so a case
# expecting CHANGED or REVIEWER_APPROVED on poll 2 saw WATCH_TIMEOUT instead. Widening the window
# is no fix: CHANGED does not end the process, so every CHANGED case would idle the whole wider
# window out. The fake clock reads a fixed epoch plus the fake gh's snapshot-query counter
# (`graphql.n`): every poll iteration issues exactly one snapshot query, so the deadline check
# before poll N reads epoch + N-1 and MAX_WATCH counts polls. The real deadline arithmetic
# still runs; only the clock's source is faked. Any other `date` call exits non-zero so a new use
# of the clock cannot silently read the virtual one.
#
# The fake counts its calls in the state dir's `date.n`, which new_state zeroes, so a case reads
# how many clock reads a run made. When the state dir carries `date.seq`, call N serves line N:
# the literal `FAIL` exits non-zero with no output, the literal `CLOCK` reads the virtual clock,
# and any other line, an empty one included, is printed as the reading. Calls past the list, and
# every call in a state with no `date.seq`, read the virtual clock unchanged. When the state dir
# carries the flag file `date.padded` (new_state leaves it absent), every virtual-clock reading, a
# `CLOCK` entry or a call past the list, is printed left-padded with zeros to 18 digits.
cat > "$STUB_BIN/date" <<'STUB'
#!/usr/bin/env bash
set -u
[ "$#" -eq 1 ] && [ "$1" = "+%s" ] || { echo "fake date: unsupported call: $*" >&2; exit 1; }
[ -n "${FAKE_GH_STATE_DIR:-}" ] || { echo "fake date: FAKE_GH_STATE_DIR unset" >&2; exit 1; }
call_number=$(cat "$FAKE_GH_STATE_DIR/date.n") || exit 1
call_number=$((call_number + 1))
printf '%s' "$call_number" > "$FAKE_GH_STATE_DIR/date.n" || exit 1
seq_file="$FAKE_GH_STATE_DIR/date.seq"
reading="CLOCK"
if [ -f "$seq_file" ] && [ "$call_number" -le "$(wc -l < "$seq_file")" ]; then
  reading=$(sed -n "${call_number}p" "$seq_file")
fi
[ "$reading" != "FAIL" ] || exit 1
if [ "$reading" = "CLOCK" ]; then
  capture_count=$(cat "$FAKE_GH_STATE_DIR/graphql.n") || exit 1
  reading="$((1700000000 + capture_count))"
  [ ! -f "$FAKE_GH_STATE_DIR/date.padded" ] || reading="$(printf '%018d' "$reading")"
fi
printf '%s\n' "$reading"
STUB
chmod +x "$STUB_BIN/date"

# ── PATH-shim fake sleep ────────────────────────────────────────────────────────────
# The interval sleep between polls is wall time only: the fake clock above already advances the
# deadline per snapshot query, so a real `sleep` adds no coverage and costs about one second per
# poll across every case. The fake returns at once and appends its argument to the state dir's
# `sleep.calls`, one line per call, so a case that needs the interval count reads it from there
# (sleep_call_count) and a case that needs each duration reads the file itself. Any call that is not one integer argument exits non-zero so a new use of
# `sleep` cannot silently pass through.
cat > "$STUB_BIN/sleep" <<'STUB'
#!/usr/bin/env bash
set -u
[ "$#" -eq 1 ] || { echo "fake sleep: unsupported call: $*" >&2; exit 1; }
case "$1" in ''|*[!0-9]*) echo "fake sleep: unsupported call: $*" >&2; exit 1 ;; esac
[ -n "${FAKE_GH_STATE_DIR:-}" ] || { echo "fake sleep: FAKE_GH_STATE_DIR unset" >&2; exit 1; }
printf '%s\n' "$1" >> "$FAKE_GH_STATE_DIR/sleep.calls" || exit 1
STUB
chmod +x "$STUB_BIN/sleep"

# new_state <name>: fresh fake-gh state dir with zeroed call counters.
new_state() {
  local dir="$TMPDIR_TEST/state-$1"
  mkdir -p "$dir"
  printf '0' > "$dir/graphql.n"
  printf '0' > "$dir/latestreviews.n"
  printf '0' > "$dir/reactions.n"
  printf '0' > "$dir/date.n"
  rm -f "$dir/date.padded"
  : > "$dir/sleep.calls"
  printf '%s' "$dir"
}

# set_seq <state_dir> <graphql|latestreviews|reactions|date> <entry>...: the per-call fixture (or
# clock reading) sequence.
set_seq() {
  local dir="$1" kind="$2"
  shift 2
  printf '%s\n' "$@" > "$dir/$kind.seq"
}

# derive_fixture <name> <base_fixture> <jq_program>: a variant of a committed fixture, so a
# single realistic base covers several scalar-delta classes without one fixture file per class.
derive_fixture() {
  local out="$TMPDIR_TEST/$1.json"
  jq "$3" "$2" > "$out" || return 1
  printf '%s' "$out"
}

# review_page <name> <first_user> <user_count> <has_next> [last_state] [last_inline]: one raw
# `latestReviews` GraphQL page holding <user_count> distinct User-typed COMMENTED authors (zero
# inline comments each) numbered from <first_user>, followed, when <last_state> is given, by a
# Bot-typed $COPILOT_SHAPED_BOT review in that state carrying <last_inline> inline comments
# (default 0).
review_page() {
  local out="$TMPDIR_TEST/$1.json"
  jq -n --argjson first "$2" --argjson count "$3" --argjson next "$4" --arg last "${5:-}" \
    --argjson inline "${6:-0}" --arg bot "$COPILOT_SHAPED_BOT" '
    {data: {repository: {pullRequest: {latestReviews: {
      pageInfo: {hasNextPage: $next, endCursor: (if $next then "cursor-\($first + $count)" else null end)},
      nodes: ([range($first; $first + $count)
                | {state: "COMMENTED", author: {login: "octo-user-\(.)", __typename: "User"},
                   comments: {totalCount: 0}}]
              + (if $last == "" then []
                 else [{state: $last, author: {login: $bot, __typename: "Bot"},
                        comments: {totalCount: $inline}}]
                 end))}}}}}' > "$out" || return 1
  printf '%s' "$out"
}

# review_pages <name> <page>...: a `.pages` sequence entry listing one page path (or `FAIL`) per
# line, served by the fake gh as one paginated walk.
review_pages() {
  local out="$TMPDIR_TEST/$1.pages"
  shift
  printf '%s\n' "$@" > "$out"
  printf '%s' "$out"
}

# review_walk <name> <page_count> <last_state> [last_inline]: a `.pages` walk whose every page but
# the last holds 100 distinct User-typed COMMENTED authors (hasNextPage true) and whose last page
# holds only the $COPILOT_SHAPED_BOT review in <last_state> with <last_inline> inline comments
# (hasNextPage false).
review_walk() {
  local name="$1" page_count="$2" last_state="$3" last_inline="${4:-0}" page_index page
  local -a walk_pages=()
  for ((page_index = 1; page_index < page_count; page_index++)); do
    page="$(review_page "$name-$page_index" $(((page_index - 1) * 100)) 100 true)" || return 1
    walk_pages+=("$page")
  done
  page="$(review_page "$name-$page_count" $(((page_count - 1) * 100)) 0 false "$last_state" \
    "$last_inline")" || return 1
  walk_pages+=("$page")
  review_pages "$name" "${walk_pages[@]}"
}

# run_poll <state_dir> <arg>...: the script under test with the fake gh on PATH. Only stdout is
# captured — every marker goes to stdout, and stderr carries the no-`timeout`-on-PATH warning
# that would otherwise pollute the exact-output assertions.
run_poll() {
  local dir="$1"
  shift
  PATH="$STUB_BIN:$PATH" FAKE_GH_STATE_DIR="$dir" bash "$POLL" "$@" 2>/dev/null
}

# arm_poll <state_dir> [seed] [filter]: poll mode with the standard 7 args, appending <seed> as
# the required 8th arg when non-empty (empty seed = legacy form on the unfixed script). <filter>
# defaults to $REVIEWER_FILTER when OMITTED; an explicit empty string is passed through as an
# empty filter slot.
arm_poll() {
  local dir="$1" seed="${2:-}" filter="${3-$REVIEWER_FILTER}"
  if [ -n "$seed" ]; then
    run_poll "$dir" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" "$POLL_INTERVAL" \
      "$filter" "$SELF_LOGIN" "$seed"
  else
    run_poll "$dir" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" "$POLL_INTERVAL" \
      "$filter" "$SELF_LOGIN"
  fi
}

# run_check <state_dir> [seed] [filter]: --check mode with the standard 7 args, appending <seed>
# as the 8th arg when non-empty (empty seed = the arg omitted). <filter> follows arm_poll's
# omitted-vs-empty rule.
run_check() {
  local dir="$1" seed="${2:-}" filter="${3-$REVIEWER_FILTER}"
  if [ -n "$seed" ]; then
    run_poll "$dir" --check "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" "$POLL_INTERVAL" \
      "$filter" "$SELF_LOGIN" "$seed"
  else
    run_poll "$dir" --check "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" "$POLL_INTERVAL" \
      "$filter" "$SELF_LOGIN"
  fi
}

# gh_call_counts <state_dir>: the fake gh's call counters as `<graphql> <latestreviews>
# <reactions>`; one capture is `1 1 1`.
gh_call_counts() {
  printf '%s %s %s' "$(cat "$1/graphql.n")" "$(cat "$1/latestreviews.n")" "$(cat "$1/reactions.n")"
}

# sleep_call_count <state_dir>: the number of interval sleeps the fake `sleep` recorded.
sleep_call_count() {
  wc -l < "$1/sleep.calls" | tr -d ' '
}

# snapshot_raw <state_name> <arm_kind> <graphql_entry> <reactions_entry> [filter]: snapshot mode
# over a fresh fake-gh state, returning the RAW stdout (BASELINE= line included). <filter> follows
# arm_poll's omitted-vs-empty rule.
snapshot_raw() {
  local st filter="${5-$REVIEWER_FILTER}"
  st="$(new_state "$1")"
  set_seq "$st" graphql "$3"
  set_seq "$st" reactions "$4"
  run_poll "$st" --snapshot "$2" "$OWNER" "$REPO_NAME" "$PR_NUMBER" \
    "$MAX_WATCH" "$POLL_INTERVAL" "$filter" "$SELF_LOGIN"
}

# capture_seed <state_name> <arm_kind> <graphql_entry> <reactions_entry> [filter]: the BARE seed
# token the skill would strip out of that BASELINE= line and pass as arg 8.
capture_seed() {
  snapshot_raw "$@" | sed -n 's/^BASELINE=//p' | head -1
}

# identity_author_json <type>: a `$SELF_LOGIN`-login author object typed <type>, or carrying no
# `__typename` at all when <type> is `none`.
identity_author_json() {
  if [ "$1" = "none" ]; then
    printf '{"login":"%s"}' "$SELF_LOGIN"
  else
    printf '{"login":"%s","__typename":"%s"}' "$SELF_LOGIN" "$1"
  fi
}

# identity_outcome_matches <type> <poll_output>: a User-typed SELF_LOGIN author is self and must
# idle to WATCH_TIMEOUT; a Bot-typed or untyped one is never self and must fire CHANGED.
identity_outcome_matches() {
  case "$1" in
    User) [ "$2" = "WATCH_TIMEOUT" ] ;;
    *) printf '%s\n' "$2" | grep -qx 'CHANGED' ;;
  esac
}

# bot_thumbs_up <name> <bare_login>: a raw REST reactions page holding one +1 from
# `<bare_login>[bot]` in the REST bot-reactor shape (User-typed), derived from reactions-codex.json.
bot_thumbs_up() {
  derive_fixture "$1" "$REACT_CODEX" ".[0].user.login = \"$2[bot]\""
}

# bot_review_state <name> <login> <state> <comments_json>: the pre-cycle-0 state plus one Bot-typed
# <login> review (databaseId 3011002) in `reviews` and, replacing any entry of that author, its
# `latestReviews` entry in <state>. <comments_json> is the entry's `comments` value; `absent`
# omits the key.
bot_review_state() {
  local comments_program=".comments = $4"
  [ "$4" != "absent" ] || comments_program="."
  derive_fixture "$1" "$PRE" "
    .data.repository.pullRequest.reviews.totalCount = 2
    | .data.repository.pullRequest.reviews.nodes += [{\"databaseId\":3011002,\"state\":\"$3\",\"author\":{\"login\":\"$2\",\"__typename\":\"Bot\"}}]
    | .data.repository.pullRequest.latestReviews.nodes |= (map(select(.author.login != \"$2\"))
        + [{\"state\":\"$3\",\"author\":{\"login\":\"$2\",\"__typename\":\"Bot\"}} | $comments_program])"
}

# seeded_poll_output <state_name> <graphql_entry> <reactions_entry> [filter]: the output of a poll
# armed with an `initial` seed captured over the pre-cycle-0 state with no reaction, serving
# <graphql_entry> and <reactions_entry> to every poll. <filter> follows arm_poll's
# omitted-vs-empty rule; an HIVEMIND_PR_REVIEWERS set on the call reaches both runs.
seeded_poll_output() {
  local seed st filter="${4-$REVIEWER_FILTER}"
  seed="$(capture_seed "$1-seed" initial "$PRE" "$REACT_NONE" "$filter")"
  st="$(new_state "$1")"
  set_seq "$st" graphql "$2"
  set_seq "$st" reactions "$3"
  arm_poll "$st" "$seed" "$filter"
}

# capture_fails_closed <state_name> <graphql_entry> <latestreviews_entry> <seed> <filter>: 0 when
# the capture fails CLOSED in BOTH modes — snapshot mode prints exactly SNAPSHOT_ERROR and exits
# non-zero, and a poll armed with <seed> prints exactly POLL_ERROR and exits non-zero (so it never
# emits a delta or an approval marker first). An empty <latestreviews_entry> leaves the walk
# mirroring <graphql_entry>. On failure it prints the observed outcome and returns 1.
capture_fails_closed() {
  local name="$1" graphql_entry="$2" walk_entry="$3" seed="$4" filter="$5" st out status
  st="$(new_state "$name-snapshot")"
  set_seq "$st" graphql "$graphql_entry"
  [ -z "$walk_entry" ] || set_seq "$st" latestreviews "$walk_entry"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(run_poll "$st" --snapshot initial "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" \
    "$POLL_INTERVAL" "$filter" "$SELF_LOGIN")"
  status=$?
  if [ "$status" -eq 0 ] || [ "$out" != "SNAPSHOT_ERROR" ]; then
    printf 'snapshot status=%s out=%s' "$status" "$(printf '%s' "$out" | tr '\n' ';')"
    return 1
  fi

  st="$(new_state "$name-poll")"
  set_seq "$st" graphql "$graphql_entry"
  [ -z "$walk_entry" ] || set_seq "$st" latestreviews "$walk_entry"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(arm_poll "$st" "$seed" "$filter")"
  status=$?
  if [ "$status" -eq 0 ] || [ "$out" != "POLL_ERROR" ]; then
    printf 'poll status=%s out=%s' "$status" "$(printf '%s' "$out" | tr '\n' ';')"
    return 1
  fi
  return 0
}

# ── Seed probe ──────────────────────────────────────────────────────────────────────
# Source-level probe for `--snapshot` support. A behavioral probe cannot discriminate: on the
# unfixed script `--snapshot` is simply read as OWNER and the run dies with the same POLL_ERROR
# a genuine input error produces.
SEED_SUPPORTED=0
grep -qF -- '--snapshot' "$POLL" && SEED_SUPPORTED=1

SEED=""
SEED_RAW=""
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  SEED_RAW="$(snapshot_raw seed initial "$PRE" "$REACT_NONE")"
  SEED="$(printf '%s\n' "$SEED_RAW" | sed -n 's/^BASELINE=//p' | head -1)"
fi
SKIP_REASON="script under test has no --snapshot seed support (pre-fix baseline contract)"

# ── Declared-vs-computed snapshot state (source-derived) ─────────────────────────────
# declared_fields: the script's own `SNAPSHOT_FIELDS=( ... )` block — the single declaration the
# serializer, parser, seed regex and diff are all built from.
declared_fields() {
  sed -n '/^SNAPSHOT_FIELDS=(/,/^)/p' "$POLL" \
    | sed -e '1d' -e '$d' -e 's/[[:space:]]//g' \
    | grep -v '^$'
}
# computed_fields: every scalar compute_snapshot actually fills, read off the literal `cur_<name>=`
# assignments in executable (non-comment) lines.
computed_fields() {
  grep -vE '^[[:space:]]*#' "$POLL" \
    | grep -oE '\bcur_[a-z0-9_]+=' \
    | sed -e 's/^cur_//' -e 's/=$//' \
    | sort -u
}
DECLARED_FIELD_COUNT=0
[ "$SEED_SUPPORTED" -eq 0 ] || DECLARED_FIELD_COUNT="$(declared_fields | grep -c .)"

# ── 1. blind-window feedback surfaces (THE BITE-PROOF) ──────────────────────────────
# A Codex review + review-thread comment lands AFTER the pre-cycle-0 state and BEFORE the Monitor
# is armed. The poll therefore only ever observes the post-comment state. It MUST still wake the
# reviewer. On the unfixed script the first poll self-baselines on that state and no CHANGED is
# ever emitted — the finding is lost for the life of the watch.
st="$(new_state blind)"
set_seq "$st" graphql "$BLIND"
set_seq "$st" reactions "$REACT_NONE"
out="$(arm_poll "$st" "$SEED")"
if printf '%s\n' "$out" | grep -qx 'CHANGED'; then
  pass "blind-window:comment-surfaces" "feedback posted inside the cycle-0 blind window fired CHANGED"
else
  failed "blind-window:comment-surfaces" "no CHANGED for feedback posted inside the cycle-0 blind window (seed=$([ -n "$SEED" ] && echo present || echo absent)) out=$(printf '%s' "$out" | tr '\n' ';')"
fi

# ── 2. seeded no-delta stays silent ─────────────────────────────────────────────────
# The pre-cycle-0 state served unchanged for every poll: no marker at all until the watch window
# closes. Guards the fix against the opposite failure — a seed that fires CHANGED on every poll.
st="$(new_state nodelta)"
set_seq "$st" graphql "$PRE"
set_seq "$st" reactions "$REACT_NONE"
out="$(arm_poll "$st" "$SEED")"
if [ "$out" = "WATCH_TIMEOUT" ]; then
  pass "nodelta:silent-to-timeout" "no marker before WATCH_TIMEOUT"
else
  failed "nodelta:silent-to-timeout" "expected only WATCH_TIMEOUT, got=$(printf '%s' "$out" | tr '\n' ';')"
fi

# ── 3a. scalar delta: max non-self issue-comment id ──────────────────────────────────
# A new Codex issue comment moves LATEST_NONSELF_ISSUE_COMMENT_ID (NONE -> 2411003) and
# COMMENTS_TOTAL. Sequence is pre-cycle-0 then the delta, so both arms see the delta as a real
# poll-to-poll change.
delta_comment="$(derive_fixture delta-comment "$PRE" \
  '.data.repository.pullRequest.comments.totalCount = 3
   | .data.repository.pullRequest.comments.nodes += [{"databaseId":2411003,"author":{"login":"chatgpt-codex-connector","__typename":"Bot"}}]')"
st="$(new_state deltacomment)"
set_seq "$st" graphql "$PRE" "$delta_comment"
set_seq "$st" reactions "$REACT_NONE"
out="$(arm_poll "$st" "$SEED")"
changed_count="$(printf '%s\n' "$out" | grep -cx 'CHANGED')"
if [ "$changed_count" -ge 1 ]; then
  pass "delta:comment-id" "new non-self issue comment fired CHANGED"
else
  failed "delta:comment-id" "expected CHANGED, got=$(printf '%s' "$out" | tr '\n' ';')"
fi

# ── 3b. scalar delta: totalCount tripwire alone ──────────────────────────────────────
# A self-authored comment is DELETED: COMMENTS_TOTAL drops 2 -> 1 while every id token is
# unchanged (both comment nodes are self-authored, so the token stays NONE). Isolates the
# totalCount tripwire from the id tokens.
delta_total="$(derive_fixture delta-total "$PRE" \
  'del(.data.repository.pullRequest.comments.nodes[1])
   | .data.repository.pullRequest.comments.totalCount = 1')"
st="$(new_state deltatotal)"
set_seq "$st" graphql "$PRE" "$delta_total"
set_seq "$st" reactions "$REACT_NONE"
out="$(arm_poll "$st" "$SEED")"
changed_count="$(printf '%s\n' "$out" | grep -cx 'CHANGED')"
if [ "$changed_count" -ge 1 ]; then
  pass "delta:totals-only" "COMMENTS_TOTAL change alone fired CHANGED"
else
  failed "delta:totals-only" "expected CHANGED, got=$(printf '%s' "$out" | tr '\n' ';')"
fi

# ── 3c. scalar delta: FAILED_CHECKS ─────────────────────────────────────────────────
# CI regresses with no review activity at all: one rollup check run moves SUCCESS -> FAILURE, so
# FAILED_CHECKS goes 0 -> 1. A rise is its own marker, CI_FAILED, which the skill dispatches to the
# reviewer without the prefilter (#400); the prefilter judges only the review surfaces and would
# skip a wake whose only change is the failed-check count. The rise prints CI_FAILED and no CHANGED,
# the steady red poll after it prints nothing, and CI_FAILED keeps the poll running to
# WATCH_TIMEOUT.
delta_checks="$(derive_fixture delta-checks "$PRE" \
  '.data.repository.pullRequest.statusCheckRollup.contexts.checkRunCountsByState =
     [{"state":"SUCCESS","count":2},{"state":"FAILURE","count":1}]')"
st="$(new_state deltachecks)"
set_seq "$st" graphql "$PRE" "$delta_checks"
set_seq "$st" reactions "$REACT_NONE"
out="$(arm_poll "$st" "$SEED")"
if [ "$out" = "$(printf 'CI_FAILED\nWATCH_TIMEOUT')" ]; then
  pass "delta:failed-checks" "FAILED_CHECKS 0->1 fired CI_FAILED, no CHANGED, polled on to WATCH_TIMEOUT"
else
  failed "delta:failed-checks" "expected exactly CI_FAILED;WATCH_TIMEOUT, got=$(printf '%s' "$out" | tr '\n' ';')"
fi

# ── 4. Codex 👍 present at the first poll emits REVIEWER_APPROVED ────────────────────
# The reaction (a `chatgpt-codex-connector[bot]` +1 in a raw REST page, typed `User` as the REST
# endpoint reports a bot reactor) is
# present for every poll while the pre-cycle-0 seed state carried none. Legacy arm: the baseline
# poll's pre-existing-approval special case fires. Seeded arm: false -> true against the seed
# fires. Either way the FIRST emitted marker is REVIEWER_APPROVED — an approval that lands in the
# blind window must not idle the loop to WATCH_TIMEOUT.
st="$(new_state codex)"
set_seq "$st" graphql "$PRE"
set_seq "$st" reactions "$REACT_CODEX"
out="$(arm_poll "$st" "$SEED")"
first_line="$(printf '%s\n' "$out" | head -1)"
if [ "$first_line" = "REVIEWER_APPROVED" ]; then
  pass "approval:thumbs-up-on-first-poll" "REVIEWER_APPROVED emitted on the first poll"
else
  failed "approval:thumbs-up-on-first-poll" "expected REVIEWER_APPROVED first, got=$(printf '%s' "$out" | tr '\n' ';')"
fi

# ── 5. missing seed argument fails CLOSED ───────────────────────────────────────────
# Once the seed is a REQUIRED 8th positional arg, the legacy 7-arg invocation must not silently
# fall back to self-baselining — that is exactly the defect. POLL_ERROR, exit 1.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  st="$(new_state noseed)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(arm_poll "$st")"
  status=$?
  if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'POLL_ERROR'; then
    pass "seed:missing-arg" "7-arg form -> POLL_ERROR exit=$status"
  else
    failed "seed:missing-arg" "status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
  fi
else
  skipped "seed:missing-arg" "$SKIP_REASON"
fi

# ── 6. malformed seed fails CLOSED ──────────────────────────────────────────────────
# A seed that is not a well-formed emitted token must be rejected outright rather than parsed into
# partially-empty previous scalars (which would fire a spurious CHANGED on the first poll).
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  st="$(new_state badseed)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(arm_poll "$st" "not-a-baseline-token")"
  status=$?
  if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'POLL_ERROR'; then
    pass "seed:malformed" "malformed seed -> POLL_ERROR exit=$status"
  else
    failed "seed:malformed" "status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
  fi
else
  skipped "seed:malformed" "$SKIP_REASON"
fi

# ── 7. --snapshot emits a well-formed BASELINE line ─────────────────────────────────
# One `BASELINE=` line carrying the arm kind plus exactly one field per declared snapshot scalar,
# and nothing else to parse. The expected width is DERIVED from the script's own declaration, so
# the count assertion and SEED_FORMAT_RE cannot drift apart from the field list.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  field_count=0
  [ -z "$SEED" ] || field_count="$(printf '%s' "$SEED" | awk -F'|' '{print NF}')"
  baseline_lines="$(printf '%s\n' "$SEED_RAW" | grep -c '^BASELINE=')"
  expected_width=$((DECLARED_FIELD_COUNT + 1))
  seed_kind="$(printf '%s' "$SEED" | cut -d'|' -f1)"
  if [ "$baseline_lines" -eq 1 ] && [ "$field_count" -eq "$expected_width" ] \
    && [ "$seed_kind" = "initial" ]; then
    pass "snapshot:baseline-well-formed" "one BASELINE= line, arm kind + $DECLARED_FIELD_COUNT scalars"
  else
    failed "snapshot:baseline-well-formed" "baseline_lines=$baseline_lines fields=$field_count expected=$expected_width kind=$seed_kind raw=$(printf '%s' "$SEED_RAW" | tr '\n' ';')"
  fi
else
  skipped "snapshot:baseline-well-formed" "$SKIP_REASON"
fi

# ── 8. --snapshot on a gh failure fails CLOSED ──────────────────────────────────────
# A seed that cannot be captured must be loud: SNAPSHOT_ERROR + exit 1, never an empty token the
# caller would pass on as a valid baseline.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  out="$(snapshot_raw snapfail initial FAIL FAIL)"
  status=$?
  if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'SNAPSHOT_ERROR'; then
    pass "snapshot:gh-failure" "gh failure -> SNAPSHOT_ERROR exit=$status"
  else
    failed "snapshot:gh-failure" "status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
  fi
else
  skipped "snapshot:gh-failure" "$SKIP_REASON"
fi

# ── 9. input validation still holds ─────────────────────────────────────────────────
# A non-integer PR number is rejected before any gh binding or deadline arithmetic: POLL_ERROR,
# exit 1, regardless of the seed contract.
st="$(new_state badpr)"
set_seq "$st" graphql "$PRE"
set_seq "$st" reactions "$REACT_NONE"
if [ -n "$SEED" ]; then
  out="$(run_poll "$st" "$OWNER" "$REPO_NAME" "12a" "$MAX_WATCH" "$POLL_INTERVAL" \
    "$REVIEWER_FILTER" "$SELF_LOGIN" "$SEED")"
else
  out="$(run_poll "$st" "$OWNER" "$REPO_NAME" "12a" "$MAX_WATCH" "$POLL_INTERVAL" \
    "$REVIEWER_FILTER" "$SELF_LOGIN")"
fi
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'POLL_ERROR'; then
  pass "validation:bad-pr-number" "non-integer PR number -> POLL_ERROR exit=$status"
else
  failed "validation:bad-pr-number" "status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
fi

# A 19-digit watch window or poll interval would wrap Bash's 64-bit arithmetic, so each is
# rejected before any gh call: POLL_ERROR, exit 1, zero gh calls.
oversized_ok=1
oversized_detail=""
for oversized_arg in watch interval; do
  st="$(new_state "oversized-$oversized_arg")"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  oversized_watch="$MAX_WATCH"
  oversized_interval="$POLL_INTERVAL"
  if [ "$oversized_arg" = "watch" ]; then
    oversized_watch="1234567890123456789"
  else
    oversized_interval="1234567890123456789"
  fi
  out="$(run_poll "$st" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$oversized_watch" "$oversized_interval" \
    "$REVIEWER_FILTER" "$SELF_LOGIN" "$SEED")"
  status=$?
  calls="$(gh_call_counts "$st")"
  if [ "$out" != "POLL_ERROR" ] || [ "$status" -ne 1 ] || [ "$calls" != "0 0 0" ]; then
    oversized_ok=0
    oversized_detail="$oversized_detail $oversized_arg: status=$status calls=$calls out=$(printf '%s' "$out" | tr '\n' ';')"
  fi
done
if [ -z "$SEED" ]; then
  skipped "validation:oversized-seconds" "no seed captured"
elif [ "$oversized_ok" -eq 1 ]; then
  pass "validation:oversized-seconds" "19-digit watch window or poll interval -> POLL_ERROR, exit 1, zero gh calls"
else
  failed "validation:oversized-seconds" "$oversized_detail"
fi

# ── 10. repeated unusable query response fails CLOSED ───────────────────────────────
# A GraphQL error response (null pullRequest) makes the snapshot pipeline fail; two consecutive
# failures are terminal POLL_ERROR, exit 1 — the retry-once path is unchanged by the seed.
st="$(new_state malformedresp)"
set_seq "$st" graphql "$MALFORMED"
set_seq "$st" reactions "$REACT_NONE"
out="$(arm_poll "$st" "$SEED")"
status=$?
if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qx 'POLL_ERROR'; then
  pass "response:malformed-twice" "two unusable responses -> POLL_ERROR exit=$status"
else
  failed "response:malformed-twice" "status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
fi

# ── 11. the seed is a COMPLETE serialization (STRUCTURAL) ───────────────────────────
# THE SECOND BITE-PROOF (PR #361). The original defect was not "the token is missing the Codex
# bool" but "the token may omit a scalar the poll diffs at all" — a per-scalar assertion would
# have caught neither instance. This case is structural: the set of scalars compute_snapshot
# fills must EQUAL the declared SNAPSHOT_FIELDS set the serializer/parser/diff iterate. A future
# author who adds a diffed scalar without declaring it — the exact shape that shipped twice —
# goes red here.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  declared_list="$(declared_fields | sort -u)"
  computed_list="$(computed_fields)"
  if [ "$declared_list" = "$computed_list" ] && [ "$DECLARED_FIELD_COUNT" -gt 0 ]; then
    pass "seed:complete-serialization" "$DECLARED_FIELD_COUNT declared scalars == $DECLARED_FIELD_COUNT computed scalars"
  else
    failed "seed:complete-serialization" "declared=[$(printf '%s' "$declared_list" | tr '\n' ' ')] computed=[$(printf '%s' "$computed_list" | tr '\n' ' ')]"
  fi
else
  skipped "seed:complete-serialization" "$SKIP_REASON"
fi

# ── 12. a stale 👍 does NOT re-fire on a productive re-arm (THE REPORTED DEFECT) ─────
# A productive remediation cycle re-arms with the PENDING seed captured before its dispatch, and
# the Codex 👍 was ALREADY present at that capture. The re-armed poll must not re-announce it:
# a re-fired REVIEWER_APPROVED runs a confirmation pass right after the reviewer fixed and pushed,
# finds nothing actionable, and ends the watch as terminal `clean` — the early exit this PR's
# idle window exists to prevent.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  rearm_seed="$(capture_seed rearmseed re-arm "$PRE" "$REACT_CODEX")"
  st="$(new_state rearmstale)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_CODEX"
  out="$(arm_poll "$st" "$rearm_seed")"
  if [ "$out" = "WATCH_TIMEOUT" ]; then
    pass "approval:stale-not-refired-on-rearm" "👍 predating the re-arm stayed silent"
  else
    failed "approval:stale-not-refired-on-rearm" "expected only WATCH_TIMEOUT, got=$(printf '%s' "$out" | tr '\n' ';') seed=$rearm_seed"
  fi
else
  skipped "approval:stale-not-refired-on-rearm" "$SKIP_REASON"
fi

# ── 13. the INITIAL arm still surfaces a 👍 present at seed capture ──────────────────
# The mirror of case 12, and the behavior that must NOT regress: on an `initial` arm the watch has
# never observed the approval edge, so a 👍 already present when the watch started must still fire
# (#324 blind window — it must not idle to WATCH_TIMEOUT). Same PR state and same reactions as
# case 12; ONLY the seed's arm kind differs, which is what proves the kind — not the field set —
# decides the question.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  initial_seed="$(capture_seed initseedcodex initial "$PRE" "$REACT_CODEX")"
  st="$(new_state initialstale)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_CODEX"
  out="$(arm_poll "$st" "$initial_seed")"
  first_line="$(printf '%s\n' "$out" | head -1)"
  if [ "$first_line" = "REVIEWER_APPROVED" ]; then
    pass "approval:initial-arm-surfaces-pre-existing" "pre-existing 👍 still fires on an initial arm"
  else
    failed "approval:initial-arm-surfaces-pre-existing" "expected REVIEWER_APPROVED first, got=$(printf '%s' "$out" | tr '\n' ';') seed=$initial_seed"
  fi
else
  skipped "approval:initial-arm-surfaces-pre-existing" "$SKIP_REASON"
fi

# ── 14. a GENUINELY new 👍 still fires on a re-arm ───────────────────────────────────
# Guards case 12 against over-correction: `re-arm` suppresses only an approval the seed already
# recorded. An approval that lands AFTER the pending capture is real feedback and must wake the
# confirmation pass.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  fresh_seed="$(capture_seed rearmfresh re-arm "$PRE" "$REACT_NONE")"
  st="$(new_state rearmfreshpoll)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE" "$REACT_CODEX"
  out="$(arm_poll "$st" "$fresh_seed")"
  if printf '%s\n' "$out" | grep -qx 'REVIEWER_APPROVED'; then
    pass "approval:new-fires-on-rearm" "👍 arriving after the pending capture fired"
  else
    failed "approval:new-fires-on-rearm" "expected REVIEWER_APPROVED, got=$(printf '%s' "$out" | tr '\n' ';') seed=$fresh_seed"
  fi
else
  skipped "approval:new-fires-on-rearm" "$SKIP_REASON"
fi

# ── 15. the arm kind is REQUIRED and closed-set ──────────────────────────────────────
# `--snapshot` with no kind, or an unrecognised one, must be SNAPSHOT_ERROR rather than a token
# whose semantics are guessed downstream; a poll seed carrying an unknown kind must be POLL_ERROR.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  arm_kind_ok=1
  arm_kind_detail=""

  out="$(snapshot_raw armkindbogus bogus "$PRE" "$REACT_NONE")"
  status=$?
  if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -qx 'SNAPSHOT_ERROR'; then
    arm_kind_ok=0
    arm_kind_detail="unknown-kind status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  st="$(new_state armkindmissing)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(run_poll "$st" --snapshot "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" \
    "$POLL_INTERVAL" "$REVIEWER_FILTER" "$SELF_LOGIN")"
  status=$?
  if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -qx 'SNAPSHOT_ERROR'; then
    arm_kind_ok=0
    arm_kind_detail="$arm_kind_detail missing-kind status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  st="$(new_state armkindseed)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(arm_poll "$st" "bogus|${SEED#*|}")"
  status=$?
  if [ "$status" -eq 0 ] || ! printf '%s\n' "$out" | grep -qx 'POLL_ERROR'; then
    arm_kind_ok=0
    arm_kind_detail="$arm_kind_detail seed-kind status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  if [ "$arm_kind_ok" -eq 1 ]; then
    pass "seed:arm-kind-closed-set" "missing / unknown arm kind fails closed in both modes"
  else
    failed "seed:arm-kind-closed-set" "$arm_kind_detail"
  fi
else
  skipped "seed:arm-kind-closed-set" "$SKIP_REASON"
fi

# ── 16. a human 👍 NEVER approves ────────────────────────────────────────────────────
# reactions-human.json carries a User-typed +1 whose login IS a bare bot login, plus a User-typed
# `claude` +1. Neither login carries the reserved `[bot]` suffix, so neither is a Bot account per
# the module's `is_bot`, and neither may approve under `automated` OR `all` — `all` admits every
# login to the filter, which isolates the Automated Reviewer Bot-account gate as the only thing
# standing between a human 👍 and a terminal `clean`. The third arm lists both logins in
# HIVEMIND_PR_REVIEWERS: a configured login held by a User account still never approves.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  human_ok=1
  human_detail=""
  for human_arm in "automated|" "all|" "automated|$CODEX_SHAPED_BOT, claude"; do
    IFS='|' read -r human_filter human_reviewers <<EOF
$human_arm
EOF
    human_name="$human_filter-$([ -n "$human_reviewers" ] && echo listed || echo unlisted)"
    human_seed="$(HIVEMIND_PR_REVIEWERS="$human_reviewers" \
      capture_seed "humanseed-$human_name" initial "$PRE" "$REACT_NONE" "$human_filter")"
    st="$(new_state "humanpoll-$human_name")"
    set_seq "$st" graphql "$PRE"
    set_seq "$st" reactions "$REACT_HUMAN"
    out="$(HIVEMIND_PR_REVIEWERS="$human_reviewers" arm_poll "$st" "$human_seed" "$human_filter")"
    if [ "$out" != "WATCH_TIMEOUT" ]; then
      human_ok=0
      human_detail="$human_detail arm=$human_name got=$(printf '%s' "$out" | tr '\n' ';') seed=$human_seed"
    fi
  done
  if [ "$human_ok" -eq 1 ]; then
    pass "approval:human-thumbs-up-never-approves" "human 👍 stayed silent under automated and all, and with its logins listed in HIVEMIND_PR_REVIEWERS"
  else
    failed "approval:human-thumbs-up-never-approves" "$human_detail"
  fi
else
  skipped "approval:human-thumbs-up-never-approves" "$SKIP_REASON"
fi

# ── 17. an APPROVED review fires under `automated` and its own `<login>`, NOT another's ─
# A `latestReviews` entry in state APPROVED for the Bot-typed $COPILOT_SHAPED_BOT is the approval
# signal, no reaction involved. The derived fixture adds that review to BOTH the `reviews` history
# and `latestReviews`, as GitHub reports a fresh approval. Under `automated`, and under `<login>`
# mode naming that bot, it is in scope, so the first marker is REVIEWER_APPROVED. Under `<login>`
# mode naming a different reviewer it is out of scope: the review still moves REVIEWS_TOTAL
# (CHANGED) but must never approve.
COPILOT_APPROVED="$(derive_fixture copilot-approved "$PRE" \
  ".data.repository.pullRequest.reviews.totalCount = 2
   | .data.repository.pullRequest.reviews.nodes += [{\"databaseId\":3011002,\"state\":\"APPROVED\",\"author\":{\"login\":\"$COPILOT_SHAPED_BOT\",\"__typename\":\"Bot\"}}]
   | .data.repository.pullRequest.latestReviews.nodes += [{\"state\":\"APPROVED\",\"author\":{\"login\":\"$COPILOT_SHAPED_BOT\",\"__typename\":\"Bot\"},\"comments\":{\"totalCount\":0}}]")"
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  scope_ok=1
  scope_detail=""
  for scope_row in "automated|REVIEWER_APPROVED" "$COPILOT_SHAPED_BOT|REVIEWER_APPROVED" \
    "$CODEX_SHAPED_BOT|CHANGED"; do
    IFS='|' read -r scope_filter scope_expected <<EOF
$scope_row
EOF
    scope_seed="$(capture_seed "scopeseed-$scope_filter" initial "$PRE" "$REACT_NONE" "$scope_filter")"
    st="$(new_state "scope-$scope_filter")"
    set_seq "$st" graphql "$PRE" "$COPILOT_APPROVED"
    set_seq "$st" reactions "$REACT_NONE"
    out="$(arm_poll "$st" "$scope_seed" "$scope_filter")"
    if [ "$scope_expected" = "REVIEWER_APPROVED" ]; then
      [ "$(printf '%s\n' "$out" | head -1)" = "REVIEWER_APPROVED" ] || scope_ok=0
    elif printf '%s\n' "$out" | grep -qx 'REVIEWER_APPROVED' \
      || ! printf '%s\n' "$out" | grep -qx 'CHANGED'; then
      scope_ok=0
    fi
    scope_detail="$scope_detail filter=$scope_filter expected=$scope_expected got=$(printf '%s' "$out" | tr '\n' ';')"
  done
  if [ "$scope_ok" -eq 1 ]; then
    pass "approval:review-scoped-by-filter" "APPROVED fired under automated and its own <login>, only CHANGED under another reviewer's <login>"
  else
    failed "approval:review-scoped-by-filter" "$scope_detail"
  fi
else
  skipped "approval:review-scoped-by-filter" "$SKIP_REASON"
fi

# ── 18. an EMPTY filter slot behaves as `automated` ──────────────────────────────────
# Over one mixed state — a Bot COMMENTED review with inline comments, a Bot APPROVED review, and a
# later User-typed human review — `automated`, `<login>` mode naming the COMMENTED bot, and `all`
# each yield a DIFFERENT seed token (filtered review id and approval both move). The empty-slot
# token must equal the `automated` one, and the discrimination check proves the comparison could
# have failed. Behaviorally, an empty-slot arm then fires REVIEWER_APPROVED on the APPROVED review
# exactly as `automated` does.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  mixed_reviews="$(derive_fixture mixed-reviews "$COPILOT_APPROVED" \
    '.data.repository.pullRequest.reviews.totalCount = 3
     | .data.repository.pullRequest.reviews.nodes += [{"databaseId":3011003,"state":"COMMENTED","author":{"login":"octo-human","__typename":"User"}}]
     | .data.repository.pullRequest.latestReviews.nodes += [{"state":"COMMENTED","author":{"login":"octo-human","__typename":"User"},"comments":{"totalCount":0}}]')"
  empty_token="$(capture_seed mixed-empty initial "$mixed_reviews" "$REACT_NONE" "")"
  automated_token="$(capture_seed mixed-automated initial "$mixed_reviews" "$REACT_NONE" automated)"
  login_token="$(capture_seed mixed-login initial "$mixed_reviews" "$REACT_NONE" "$CODEX_SHAPED_BOT")"
  all_token="$(capture_seed mixed-all initial "$mixed_reviews" "$REACT_NONE" all)"

  empty_seed="$(capture_seed emptyseed initial "$PRE" "$REACT_NONE" "")"
  st="$(new_state emptyfilterpoll)"
  set_seq "$st" graphql "$PRE" "$COPILOT_APPROVED"
  set_seq "$st" reactions "$REACT_NONE"
  empty_out="$(arm_poll "$st" "$empty_seed" "")"

  if [ -n "$empty_token" ] && [ "$empty_token" = "$automated_token" ] \
    && [ "$automated_token" != "$login_token" ] && [ "$automated_token" != "$all_token" ] \
    && [ "$(printf '%s\n' "$empty_out" | head -1)" = "REVIEWER_APPROVED" ]; then
    pass "filter:empty-slot-is-automated" "empty-slot seed == automated seed (!= <login>, != all); empty-slot arm fired REVIEWER_APPROVED"
  else
    failed "filter:empty-slot-is-automated" "empty=$empty_token automated=$automated_token login=$login_token all=$all_token poll=$(printf '%s' "$empty_out" | tr '\n' ';')"
  fi
else
  skipped "filter:empty-slot-is-automated" "$SKIP_REASON"
fi

# ── 19. a SUPERSEDED APPROVED review never approves ─────────────────────────────────
# Review approval is current state, not history: each reviewer is judged by its LATEST review,
# which is the state GitHub reports in its `latestReviews` entry. An APPROVED followed by a later
# CHANGES_REQUESTED, COMMENTED with inline comments, or DISMISSED review from the same bot
# (appended to `reviews`, and the `latestReviews` entry taking that later state) must not fire
# REVIEWER_APPROVED under `automated`, even on an `initial` arm (which surfaces any approval present
# when the watch starts). The later review still moves the filtered review id, so CHANGED fires.
# The reverse order (COMMENTED, then a later APPROVED) is the discrimination check: it must still
# fire, which proves the assertion could pass.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  stale_ok=1
  stale_detail=""
  for later_state in CHANGES_REQUESTED COMMENTED DISMISSED; do
    stale_fixture="$(derive_fixture "copilot-stale-$later_state" "$COPILOT_APPROVED" \
      ".data.repository.pullRequest.reviews.totalCount = 3
       | .data.repository.pullRequest.reviews.nodes += [{\"databaseId\":3011009,\"state\":\"$later_state\",\"author\":{\"login\":\"$COPILOT_SHAPED_BOT\",\"__typename\":\"Bot\"}}]
       | .data.repository.pullRequest.latestReviews.nodes |= map(if .author.login == \"$COPILOT_SHAPED_BOT\" then .state = \"$later_state\" | .comments = {\"totalCount\":2} else . end)")"
    stale_seed="$(capture_seed "copilotstaleseed-$later_state" initial "$PRE" "$REACT_NONE" automated)"
    st="$(new_state "copilot-stale-$later_state")"
    set_seq "$st" graphql "$PRE" "$stale_fixture"
    set_seq "$st" reactions "$REACT_NONE"
    out="$(arm_poll "$st" "$stale_seed" automated)"
    if printf '%s\n' "$out" | grep -qx 'REVIEWER_APPROVED' \
      || ! printf '%s\n' "$out" | grep -qx 'CHANGED'; then
      stale_ok=0
      stale_detail="$stale_detail later=$later_state got=$(printf '%s' "$out" | tr '\n' ';')"
    fi
  done

  reapproved="$(derive_fixture copilot-reapproved "$PRE" \
    ".data.repository.pullRequest.reviews.totalCount = 3
     | .data.repository.pullRequest.reviews.nodes += [
         {\"databaseId\":3011002,\"state\":\"COMMENTED\",\"author\":{\"login\":\"$COPILOT_SHAPED_BOT\",\"__typename\":\"Bot\"}},
         {\"databaseId\":3011009,\"state\":\"APPROVED\",\"author\":{\"login\":\"$COPILOT_SHAPED_BOT\",\"__typename\":\"Bot\"}}]
     | .data.repository.pullRequest.latestReviews.nodes += [{\"state\":\"APPROVED\",\"author\":{\"login\":\"$COPILOT_SHAPED_BOT\",\"__typename\":\"Bot\"},\"comments\":{\"totalCount\":0}}]")"
  reapproved_seed="$(capture_seed copilotreapprovedseed initial "$PRE" "$REACT_NONE" automated)"
  st="$(new_state copilot-reapproved)"
  set_seq "$st" graphql "$PRE" "$reapproved"
  set_seq "$st" reactions "$REACT_NONE"
  reapproved_out="$(arm_poll "$st" "$reapproved_seed" automated)"
  if [ "$(printf '%s\n' "$reapproved_out" | head -1)" != "REVIEWER_APPROVED" ]; then
    stale_ok=0
    stale_detail="$stale_detail reapproved got=$(printf '%s' "$reapproved_out" | tr '\n' ';')"
  fi

  if [ "$stale_ok" -eq 1 ]; then
    pass "approval:superseded-review-never-approves" "stale APPROVED stayed silent after CHANGES_REQUESTED/COMMENTED with inline/DISMISSED; a latest APPROVED still fired"
  else
    failed "approval:superseded-review-never-approves" "$stale_detail"
  fi
else
  skipped "approval:superseded-review-never-approves" "$SKIP_REASON"
fi
# ── 20. the issue-comment self filter keys on account type, not login alone ─────────
# comments.nodes[1] is swapped for a higher-id comment whose login IS SELF_LOGIN, COMMENTS_TOTAL
# unchanged, so only LATEST_NONSELF_ISSUE_COMMENT_ID can fire. Bot-typed: `is_self` is User-gated,
# so it is not self and the token moves NONE -> 2411003 (CHANGED); a login-only compare drops it
# as self-echo and idles to WATCH_TIMEOUT. User-typed: genuinely self, silent (self-echo
# suppression intact). Untyped: a null type is never self, so CHANGED (fail toward wake).
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  ident_comment_ok=1
  ident_comment_detail=""
  ident_comment_seed="$(capture_seed identcommentseed initial "$PRE" "$REACT_NONE")"
  for swap_type in Bot User none; do
    swap_fixture="$(derive_fixture "ident-comment-$swap_type" "$PRE" \
      ".data.repository.pullRequest.comments.nodes[1] = {\"databaseId\":2411003,\"author\":$(identity_author_json "$swap_type")}")"
    st="$(new_state "ident-comment-$swap_type")"
    set_seq "$st" graphql "$PRE" "$swap_fixture"
    set_seq "$st" reactions "$REACT_NONE"
    out="$(arm_poll "$st" "$ident_comment_seed")"
    if ! identity_outcome_matches "$swap_type" "$out"; then
      ident_comment_ok=0
      ident_comment_detail="$ident_comment_detail type=$swap_type got=$(printf '%s' "$out" | tr '\n' ';')"
    fi
  done
  if [ "$ident_comment_ok" -eq 1 ]; then
    pass "identity:comment-self-keys-on-type" "SELF_LOGIN comment: Bot/untyped fired CHANGED, User stayed silent"
  else
    failed "identity:comment-self-keys-on-type" "$ident_comment_detail seed=$ident_comment_seed"
  fi
else
  skipped "identity:comment-self-keys-on-type" "$SKIP_REASON"
fi

# ── 21. the review-thread self filter keys on account type, not login alone ──────────
# Base: the one thread's last comment is a User-typed SELF_LOGIN reply (self, token NONE). The
# variant replaces it with a higher-id SELF_LOGIN reply, REVIEW_THREADS_TOTAL unchanged, so only
# LATEST_NONSELF_THREAD_COMMENT_ID can fire. Same expectations per type as case 20.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  ident_thread_ok=1
  ident_thread_detail=""
  thread_self_base="$(derive_fixture ident-thread-base "$PRE" \
    ".data.repository.pullRequest.reviewThreads.nodes[0].comments.nodes = [{\"databaseId\":4011001,\"author\":$(identity_author_json User)}]")"
  ident_thread_seed="$(capture_seed identthreadseed initial "$thread_self_base" "$REACT_NONE")"
  for swap_type in Bot User none; do
    swap_fixture="$(derive_fixture "ident-thread-$swap_type" "$thread_self_base" \
      ".data.repository.pullRequest.reviewThreads.nodes[0].comments.nodes = [{\"databaseId\":4011002,\"author\":$(identity_author_json "$swap_type")}]")"
    st="$(new_state "ident-thread-$swap_type")"
    set_seq "$st" graphql "$thread_self_base" "$swap_fixture"
    set_seq "$st" reactions "$REACT_NONE"
    out="$(arm_poll "$st" "$ident_thread_seed")"
    if ! identity_outcome_matches "$swap_type" "$out"; then
      ident_thread_ok=0
      ident_thread_detail="$ident_thread_detail type=$swap_type got=$(printf '%s' "$out" | tr '\n' ';')"
    fi
  done
  if [ "$ident_thread_ok" -eq 1 ]; then
    pass "identity:thread-self-keys-on-type" "SELF_LOGIN thread reply: Bot/untyped fired CHANGED, User stayed silent"
  else
    failed "identity:thread-self-keys-on-type" "$ident_thread_detail seed=$ident_thread_seed"
  fi
else
  skipped "identity:thread-self-keys-on-type" "$SKIP_REASON"
fi

# ── 22. an approval outside the `reviews` history window still approves ─────────────
# The poll reads only the last 50 `reviews`; a busy PR pushes a reviewer's latest review out of
# that window. `REVIEWS_TOTAL` is 120 and no Copilot review sits in the window, but GitHub's
# `latestReviews` still reports the Copilot APPROVED. The approval comes from `latestReviews`, so
# the FIRST marker under `automated` is REVIEWER_APPROVED; an approval rebuilt from the window
# misses it and the watch idles toward WATCH_TIMEOUT.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  overflow_fixture="$(derive_fixture review-window-overflow "$PRE" \
    '.data.repository.pullRequest.reviews.totalCount = 120
     | .data.repository.pullRequest.latestReviews.nodes += [{"state":"APPROVED","author":{"login":"copilot-pull-request-reviewer","__typename":"Bot"}}]')"
  overflow_seed="$(capture_seed overflowseed initial "$PRE" "$REACT_NONE" automated)"
  st="$(new_state review-window-overflow)"
  set_seq "$st" graphql "$overflow_fixture"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(arm_poll "$st" "$overflow_seed" automated)"
  if [ "$(printf '%s\n' "$out" | head -1)" = "REVIEWER_APPROVED" ]; then
    pass "approval:review-window-overflow-still-approves" "latestReviews APPROVED outside the 50-review window fired REVIEWER_APPROVED first"
  else
    failed "approval:review-window-overflow-still-approves" "expected REVIEWER_APPROVED first, got=$(printf '%s' "$out" | tr '\n' ';') seed=$overflow_seed"
  fi
else
  skipped "approval:review-window-overflow-still-approves" "$SKIP_REASON"
fi

# ── 23. approval is GitHub's latest review, not the poll's reading of history ─────────
# The `reviews` window ends in a Copilot APPROVED, but `latestReviews` carries no Copilot entry.
# The poll never rebuilds the latest review from history, so no REVIEWER_APPROVED fires; the new
# review still moves the filtered review id and `REVIEWS_TOTAL`, so CHANGED fires.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  history_only_fixture="$(derive_fixture latest-review-not-history "$PRE" \
    '.data.repository.pullRequest.reviews.totalCount = 2
     | .data.repository.pullRequest.reviews.nodes += [{"databaseId":3011002,"state":"APPROVED","author":{"login":"copilot-pull-request-reviewer","__typename":"Bot"}}]')"
  history_only_seed="$(capture_seed historyonlyseed initial "$PRE" "$REACT_NONE" automated)"
  st="$(new_state latest-review-not-history)"
  set_seq "$st" graphql "$PRE" "$history_only_fixture"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(arm_poll "$st" "$history_only_seed" automated)"
  if ! printf '%s\n' "$out" | grep -qx 'REVIEWER_APPROVED' \
    && printf '%s\n' "$out" | grep -qx 'CHANGED'; then
    pass "approval:latest-review-not-history" "history-only Copilot APPROVED fired CHANGED, never REVIEWER_APPROVED"
  else
    failed "approval:latest-review-not-history" "expected CHANGED without REVIEWER_APPROVED, got=$(printf '%s' "$out" | tr '\n' ';') seed=$history_only_seed"
  fi
else
  skipped "approval:latest-review-not-history" "$SKIP_REASON"
fi

# ── 24. a User-typed APPROVED review NEVER approves ──────────────────────────────────
# A User-typed account whose login IS a Copilot-shaped bot login submits an APPROVED review that
# is its latest. Under `all` every login passes the filter, which isolates the Automated Reviewer
# Bot-type gate as the only thing standing between that human review and a terminal `clean`. The
# review moves `REVIEWS_TOTAL`, so CHANGED fires.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  user_review_fixture="$(derive_fixture user-typed-review "$PRE" \
    '.data.repository.pullRequest.reviews.totalCount = 2
     | .data.repository.pullRequest.reviews.nodes += [{"databaseId":3011002,"state":"APPROVED","author":{"login":"copilot-pull-request-reviewer","__typename":"User"}}]
     | .data.repository.pullRequest.latestReviews.nodes += [{"state":"APPROVED","author":{"login":"copilot-pull-request-reviewer","__typename":"User"}}]')"
  user_review_seed="$(capture_seed userreviewseed initial "$PRE" "$REACT_NONE" all)"
  st="$(new_state user-typed-review)"
  set_seq "$st" graphql "$PRE" "$user_review_fixture"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(arm_poll "$st" "$user_review_seed" all)"
  if ! printf '%s\n' "$out" | grep -qx 'REVIEWER_APPROVED' \
    && printf '%s\n' "$out" | grep -qx 'CHANGED'; then
    pass "approval:user-typed-review-never-approves" "User-typed APPROVED latest review under all fired CHANGED, never REVIEWER_APPROVED"
  else
    failed "approval:user-typed-review-never-approves" "expected CHANGED without REVIEWER_APPROVED, got=$(printf '%s' "$out" | tr '\n' ';') seed=$user_review_seed"
  fi
else
  skipped "approval:user-typed-review-never-approves" "$SKIP_REASON"
fi

# ── 25. a reaction login cannot forge the account type ───────────────────────────────
# reactions-forged.json carries one User-typed +1 whose login is a `[bot]`-suffixed bot login
# followed by a TAB and `Bot`. A transport that joins login and type with a delimiter and splits
# them again reads that row as a Bot-typed approval. The transport carries each row as a JSON
# object, so the login stays one value and the type stays User; the login ends in `Bot`, not the
# reserved `[bot]` suffix, so it is no Bot account per `is_bot`: no approval under `automated` OR
# `all`.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  forged_ok=1
  forged_detail=""
  for forged_filter in automated all; do
    forged_seed="$(capture_seed "forgedseed-$forged_filter" initial "$PRE" "$REACT_NONE" "$forged_filter")"
    st="$(new_state "forgedpoll-$forged_filter")"
    set_seq "$st" graphql "$PRE"
    set_seq "$st" reactions "$REACT_FORGED"
    out="$(arm_poll "$st" "$forged_seed" "$forged_filter")"
    if [ "$out" != "WATCH_TIMEOUT" ]; then
      forged_ok=0
      forged_detail="$forged_detail filter=$forged_filter got=$(printf '%s' "$out" | tr '\n' ';') seed=$forged_seed"
    fi
  done
  if [ "$forged_ok" -eq 1 ]; then
    pass "approval:reaction-login-cannot-forge-type" "delimiter-forged login stayed silent under automated and all"
  else
    failed "approval:reaction-login-cannot-forge-type" "$forged_detail"
  fi
else
  skipped "approval:reaction-login-cannot-forge-type" "$SKIP_REASON"
fi

# ── 26. a non-+1 reaction from a bot NEVER approves ──────────────────────────────
# reactions-codex-eyes.json carries one bot `eyes` reaction in the REST shape (User-typed,
# `[bot]`-suffixed login, so a Bot account per `is_bot`). Only a +1 is a reaction approval signal,
# and an `eyes` reactor is no Automated Reviewer evidence, so the poll idles to WATCH_TIMEOUT.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  st="$(new_state codex-eyes)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_CODEX_EYES"
  out="$(arm_poll "$st" "$SEED")"
  if [ "$out" = "WATCH_TIMEOUT" ]; then
    pass "approval:eyes-reaction-never-approves" "bot eyes reaction stayed silent"
  else
    failed "approval:eyes-reaction-never-approves" "expected only WATCH_TIMEOUT, got=$(printf '%s' "$out" | tr '\n' ';')"
  fi
else
  skipped "approval:eyes-reaction-never-approves" "$SKIP_REASON"
fi

# ── 27. the approval read walks EVERY latestReviews page ─────────────────────────────
# A Bot-typed APPROVED sits on the LAST page of a 2-page and a 3-page `latestReviews` walk, behind
# 100 / 200 distinct User-typed COMMENTED authors. The snapshot query's own `latestReviews` holds
# exactly page 1, so a read bounded to one 100-author page finds no approval and idles to
# WATCH_TIMEOUT. The approval read is an exhaustive paginated walk, so the FIRST marker under
# `automated` is REVIEWER_APPROVED. Discrimination: the same walks ending in a COMMENTED review
# with 3 inline comments idle to WATCH_TIMEOUT, which proves the assertion could pass.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  walk_ok=1
  walk_detail=""
  walk_head="$(review_page walk-head 0 100 true)"
  walk_main="$(derive_fixture walk-main "$PRE" \
    ".data.repository.pullRequest.latestReviews.nodes = $(jq -c '.data.repository.pullRequest.latestReviews.nodes' "$walk_head")")"
  walk_seed="$(capture_seed walkseed initial "$PRE" "$REACT_NONE" automated)"
  for walk_page_count in 2 3; do
    for walk_last_state in APPROVED COMMENTED; do
      walk_entry="$(review_walk "walk-$walk_page_count-$walk_last_state" "$walk_page_count" \
        "$walk_last_state" 3)"
      st="$(new_state "walk-$walk_page_count-$walk_last_state")"
      set_seq "$st" graphql "$walk_main"
      set_seq "$st" latestreviews "$walk_entry"
      set_seq "$st" reactions "$REACT_NONE"
      out="$(arm_poll "$st" "$walk_seed" automated)"
      if [ "$walk_last_state" = "APPROVED" ]; then
        [ "$(printf '%s\n' "$out" | head -1)" = "REVIEWER_APPROVED" ] || walk_ok=0
      else
        [ "$out" = "WATCH_TIMEOUT" ] || walk_ok=0
      fi
      walk_detail="$walk_detail pages=$walk_page_count last=$walk_last_state got=$(printf '%s' "$out" | tr '\n' ';')"
    done
  done
  if [ "$walk_ok" -eq 1 ]; then
    pass "approval:latest-reviews-every-page-read" "last-page APPROVED fired REVIEWER_APPROVED first on 2- and 3-page walks; last-page COMMENTED with inline stayed silent"
  else
    failed "approval:latest-reviews-every-page-read" "$walk_detail seed=$walk_seed"
  fi
else
  skipped "approval:latest-reviews-every-page-read" "$SKIP_REASON"
fi

# ── 28. a PARTIAL latestReviews walk fails the capture CLOSED ────────────────────────
# Page 1 reports hasNextPage true and the next page fails. An approval judged from the pages read
# so far would be a verdict over a partial fetch, so the capture fails instead: SNAPSHOT_ERROR,
# exit 1, in snapshot mode, and POLL_ERROR, exit 1, in poll mode (two consecutive failures).
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  partial_ok=1
  partial_detail=""
  partial_head="$(review_page partial-head 0 100 true)"
  partial_entry="$(review_pages partial-walk "$partial_head" FAIL)"

  st="$(new_state partial-snapshot)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" latestreviews "$partial_entry"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(run_poll "$st" --snapshot initial "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" \
    "$POLL_INTERVAL" "$REVIEWER_FILTER" "$SELF_LOGIN")"
  status=$?
  if [ "$status" -eq 0 ] || [ "$out" != "SNAPSHOT_ERROR" ]; then
    partial_ok=0
    partial_detail="snapshot status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  st="$(new_state partial-poll)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" latestreviews "$partial_entry"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(arm_poll "$st" "$SEED")"
  status=$?
  if [ "$status" -eq 0 ] || [ "$out" != "POLL_ERROR" ]; then
    partial_ok=0
    partial_detail="$partial_detail poll status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  if [ "$partial_ok" -eq 1 ]; then
    pass "approval:latest-reviews-partial-walk-fails-closed" "failed later page -> SNAPSHOT_ERROR / POLL_ERROR, exit 1"
  else
    failed "approval:latest-reviews-partial-walk-fails-closed" "$partial_detail"
  fi
else
  skipped "approval:latest-reviews-partial-walk-fails-closed" "$SKIP_REASON"
fi

# ── 29. the REST-typed bot 👍 approves under every filter that admits it ─────────────
# The REST reactions endpoint reports a bot reactor as `user.type` `User` with the
# `[bot]`-suffixed login (reactions-codex.json is that verbatim shape). The module's `is_bot`
# admits it by the reserved suffix, so under `automated` AND `<login>` mode naming that bot the
# FIRST marker is REVIEWER_APPROVED. A gate on the account type alone rejects that row and idles to
# WATCH_TIMEOUT. The variant re-typing the same row `Bot` must approve too, so the suffix arm
# widens the type arm rather than replacing it.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  rest_ok=1
  rest_detail=""
  react_codex_bot_typed="$(derive_fixture reactions-codex-bot-typed "$REACT_CODEX" '.[].user.type = "Bot"')"
  for rest_reactions in "$REACT_CODEX" "$react_codex_bot_typed"; do
    for rest_filter in automated "$CODEX_SHAPED_BOT"; do
      rest_name="restpoll-$(basename "$rest_reactions" .json)-$rest_filter"
      rest_seed="$(capture_seed "$rest_name-seed" initial "$PRE" "$REACT_NONE" "$rest_filter")"
      st="$(new_state "$rest_name")"
      set_seq "$st" graphql "$PRE"
      set_seq "$st" reactions "$rest_reactions"
      out="$(arm_poll "$st" "$rest_seed" "$rest_filter")"
      if [ "$(printf '%s\n' "$out" | head -1)" != "REVIEWER_APPROVED" ]; then
        rest_ok=0
        rest_detail="$rest_detail reactions=$(basename "$rest_reactions") filter=$rest_filter got=$(printf '%s' "$out" | tr '\n' ';') seed=$rest_seed"
      fi
    done
  done
  if [ "$rest_ok" -eq 1 ]; then
    pass "approval:rest-user-typed-bot-thumbs-up-approves" "User-typed and Bot-typed bot 👍 fired REVIEWER_APPROVED first under automated and <login>"
  else
    failed "approval:rest-user-typed-bot-thumbs-up-approves" "$rest_detail"
  fi
else
  skipped "approval:rest-user-typed-bot-thumbs-up-approves" "$SKIP_REASON"
fi

# ── 30. a snapshot body carrying a GraphQL `errors` value fails the capture CLOSED ────
# gh exits 0 on several GraphQL error envelopes, and the fake gh serves each of these exit 0. The
# pre-cycle-0 state keeps its full `data` and gains a top-level `errors` value: an array holding a
# message object, an array holding an EMPTY object, and a bare object. The `data` alone would
# yield a valid baseline and a silent poll; the shared graphql-response.sh check rejects every
# variant, so snapshot mode is SNAPSHOT_ERROR and poll mode is POLL_ERROR, both exit 1.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  errors_ok=1
  errors_detail=""
  errors_index=0
  for errors_value in '[{"message":"x"}]' '[{}]' '{}'; do
    errors_index=$((errors_index + 1))
    errors_fixture="$(derive_fixture "snapshot-errors-$errors_index" "$PRE" ".errors = $errors_value")"
    if ! errors_outcome="$(capture_fails_closed "snapshot-errors-$errors_index" "$errors_fixture" "" \
      "$SEED" "$REVIEWER_FILTER")"; then
      errors_ok=0
      errors_detail="$errors_detail errors=$errors_value $errors_outcome"
    fi
  done
  if [ "$errors_ok" -eq 1 ]; then
    pass "response:snapshot-graphql-errors-fail-closed" "errors [{message}], [{}] and {} -> SNAPSHOT_ERROR / POLL_ERROR, exit 1"
  else
    failed "response:snapshot-graphql-errors-fail-closed" "$errors_detail"
  fi
else
  skipped "response:snapshot-graphql-errors-fail-closed" "$SKIP_REASON"
fi

# ── 31. a latestReviews walk with a GraphQL `errors` value on ANY page fails CLOSED ───
# A 2-page walk ends in an APPROVED review from the Bot-typed reviewer that `review_page`
# emits, served exit 0; on its own (case 27) that walk fires REVIEWER_APPROVED
# first under `automated`. Here one page also carries a
# top-level `errors` value — page 2 (the page holding the approval) in one variant, page 1 in the
# other. The shared graphql-response.sh pages check rejects the whole stream, so snapshot mode is
# SNAPSHOT_ERROR and poll mode is POLL_ERROR, both exit 1, and no approval is ever judged from an
# errored walk.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  walk_errors_ok=1
  walk_errors_detail=""
  walk_errors_seed="$(capture_seed walkerrorsseed initial "$PRE" "$REACT_NONE" automated)"
  clean_head="$(review_page walk-errors-head 0 100 true)"
  clean_tail="$(review_page walk-errors-tail 100 0 false APPROVED)"
  errored_head="$(derive_fixture walk-errors-head-errored "$clean_head" '.errors = [{"message":"x"}]')"
  errored_tail="$(derive_fixture walk-errors-tail-errored "$clean_tail" '.errors = [{"message":"x"}]')"
  for errored_page in 2 1; do
    if [ "$errored_page" -eq 2 ]; then
      walk_errors_entry="$(review_pages walk-errors-page-2 "$clean_head" "$errored_tail")"
    else
      walk_errors_entry="$(review_pages walk-errors-page-1 "$errored_head" "$clean_tail")"
    fi
    if ! walk_errors_outcome="$(capture_fails_closed "walk-errors-page-$errored_page" "$PRE" \
      "$walk_errors_entry" "$walk_errors_seed" automated)"; then
      walk_errors_ok=0
      walk_errors_detail="$walk_errors_detail errored_page=$errored_page $walk_errors_outcome"
    fi
  done
  if [ "$walk_errors_ok" -eq 1 ]; then
    pass "approval:latest-reviews-graphql-errors-fail-closed" "errors on page 2 or page 1 of an APPROVED walk -> SNAPSHOT_ERROR / POLL_ERROR, exit 1, never REVIEWER_APPROVED"
  else
    failed "approval:latest-reviews-graphql-errors-fail-closed" "$walk_errors_detail seed=$walk_errors_seed"
  fi
else
  skipped "approval:latest-reviews-graphql-errors-fail-closed" "$SKIP_REASON"
fi

# ── 32. a snapshot body that lost part of the review-activity skeleton fails CLOSED ────
# Each variant derives from the pre-cycle-0 state with NO `errors` value, so the shared
# graphql-response.sh check accepts it. The first three are the hollow per-thread bodies the
# snapshot projection reads as "no thread comment" (its optional iteration skips them) and would
# idle the poll past real feedback: a thread whose `comments.nodes` is null, a thread with its
# `comments` connection deleted, and a null thread element. The last two are locks a projection
# error already fails today: a null `reviews` connection and a null `pullRequest`. The shared
# review-surface-shape.sh check rejects every variant, so snapshot mode is SNAPSHOT_ERROR and poll
# mode is POLL_ERROR, both exit 1.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  hollow_ok=1
  hollow_detail=""
  hollow_index=0
  for hollow_program in \
    '.data.repository.pullRequest.reviewThreads.nodes[0].comments.nodes = null' \
    '.data.repository.pullRequest.reviewThreads.nodes[0] |= del(.comments)' \
    '.data.repository.pullRequest.reviewThreads.nodes[0] = null' \
    '.data.repository.pullRequest.reviews = null' \
    '.data.repository.pullRequest = null'; do
    hollow_index=$((hollow_index + 1))
    hollow_fixture="$(derive_fixture "snapshot-hollow-$hollow_index" "$PRE" "$hollow_program")"
    if ! hollow_outcome="$(capture_fails_closed "snapshot-hollow-$hollow_index" "$hollow_fixture" "" \
      "$SEED" "$REVIEWER_FILTER")"; then
      hollow_ok=0
      hollow_detail="$hollow_detail program=[$hollow_program] $hollow_outcome"
    fi
  done
  if [ "$hollow_ok" -eq 1 ]; then
    pass "response:snapshot-hollow-surface-fail-closed" "null thread comments.nodes, deleted thread comments, null thread, null reviews, null pullRequest -> SNAPSHOT_ERROR / POLL_ERROR, exit 1"
  else
    failed "response:snapshot-hollow-surface-fail-closed" "$hollow_detail"
  fi
else
  skipped "response:snapshot-hollow-surface-fail-closed" "$SKIP_REASON"
fi

# ── 33. a genuinely empty review surface still yields a valid baseline ────────────────
# Discrimination for case 32: `nodes: []` is a clean PR, not a hollow one. Every connection empty
# (totals 0), and a variant whose one thread holds an empty `comments.nodes`, each capture exactly
# the expected BASELINE= line, exit 0, and a poll armed with that seed over the same state idles
# silently to WATCH_TIMEOUT.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  empty_ok=1
  empty_detail=""
  empty_all="$(derive_fixture surface-empty-all "$PRE" \
    '.data.repository.pullRequest |= (.comments = {"totalCount":0,"nodes":[]}
      | .reviews = {"totalCount":0,"nodes":[]}
      | .reviewThreads = {"totalCount":0,"nodes":[]})')"
  empty_thread="$(derive_fixture surface-empty-thread "$empty_all" \
    '.data.repository.pullRequest.reviewThreads = {"totalCount":1,"nodes":[{"comments":{"nodes":[]}}]}')"
  for empty_case in "all|$empty_all|initial|OPEN|NONE|NONE|NONE|0|0|0|0|false" \
    "thread|$empty_thread|initial|OPEN|NONE|NONE|NONE|0|0|1|0|false"; do
    empty_name="${empty_case%%|*}"
    empty_rest="${empty_case#*|}"
    empty_fixture="${empty_rest%%|*}"
    empty_expected="${empty_rest#*|}"
    empty_raw="$(snapshot_raw "surface-empty-$empty_name" initial "$empty_fixture" "$REACT_NONE")"
    empty_status=$?
    if [ "$empty_status" -ne 0 ] || [ "$empty_raw" != "BASELINE=$empty_expected" ]; then
      empty_ok=0
      empty_detail="$empty_detail $empty_name: snapshot status=$empty_status out=$(printf '%s' "$empty_raw" | tr '\n' ';')"
      continue
    fi
    st="$(new_state "surface-empty-$empty_name-poll")"
    set_seq "$st" graphql "$empty_fixture"
    set_seq "$st" reactions "$REACT_NONE"
    out="$(arm_poll "$st" "$empty_expected")"
    if [ "$out" != "WATCH_TIMEOUT" ]; then
      empty_ok=0
      empty_detail="$empty_detail $empty_name: poll out=$(printf '%s' "$out" | tr '\n' ';')"
    fi
  done
  if [ "$empty_ok" -eq 1 ]; then
    pass "response:empty-surface-valid-baseline" "all-empty connections and an empty-comment thread -> exact BASELINE=, exit 0; seeded poll silent to WATCH_TIMEOUT"
  else
    failed "response:empty-surface-valid-baseline" "$empty_detail"
  fi
else
  skipped "response:empty-surface-valid-baseline" "$SKIP_REASON"
fi

# ── 34. REVIEWER_APPROVED is the last line the poll process prints ────────────────────
# The approval marker ends the process (exit 0): the skill's confirmation pass is a full fix pass
# and any return that keeps watching arms a fresh poll, so a poll left running past the marker is
# an orphan. (i) a lone approval edge prints exactly `REVIEWER_APPROVED`, exit 0, and the fake gh
# sees no snapshot query after it; (ii) an approval co-firing with a comment delta still prints
# exactly `REVIEWER_APPROVED` with no trailing marker; (iii) discrimination: the same comment delta
# WITHOUT an approval prints `CHANGED` and keeps polling to `WATCH_TIMEOUT`, so only the approval
# edge ends the process. (i) runs under a watch window long enough for several polls after the
# marker, so the snapshot-query count and the recorded interval-sleep count, not just stdout,
# catch a poll that outlives it; a passing run exits at the marker and never waits that window out.
LIFETIME_MAX_WATCH=8
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  lifetime_ok=1
  lifetime_detail=""

  st="$(new_state lifetime-lone)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE" "$REACT_CODEX"
  out="$(run_poll "$st" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$LIFETIME_MAX_WATCH" "$POLL_INTERVAL" \
    "$REVIEWER_FILTER" "$SELF_LOGIN" "$SEED")"
  status=$?
  graphql_calls="$(cat "$st/graphql.n")"
  sleep_calls="$(sleep_call_count "$st")"
  if [ "$out" != "REVIEWER_APPROVED" ] || [ "$status" -ne 0 ] || [ "$graphql_calls" != "2" ] \
    || [ "$sleep_calls" != "1" ]; then
    lifetime_ok=0
    lifetime_detail="$lifetime_detail lone: status=$status graphql_calls=$graphql_calls sleep_calls=$sleep_calls out=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  st="$(new_state lifetime-cofire)"
  set_seq "$st" graphql "$PRE" "$delta_comment"
  set_seq "$st" reactions "$REACT_NONE" "$REACT_CODEX"
  out="$(arm_poll "$st" "$SEED")"
  status=$?
  if [ "$out" != "REVIEWER_APPROVED" ] || [ "$status" -ne 0 ]; then
    lifetime_ok=0
    lifetime_detail="$lifetime_detail co-fire: status=$status out=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  st="$(new_state lifetime-changed)"
  set_seq "$st" graphql "$PRE" "$delta_comment"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(arm_poll "$st" "$SEED")"
  last_line="$(printf '%s\n' "$out" | tail -1)"
  if ! printf '%s\n' "$out" | grep -qx 'CHANGED' || [ "$last_line" != "WATCH_TIMEOUT" ]; then
    lifetime_ok=0
    lifetime_detail="$lifetime_detail changed: out=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  if [ "$lifetime_ok" -eq 1 ]; then
    pass "approval:marker-ends-poll-process" "REVIEWER_APPROVED alone or co-fired is the last line, exit 0, no later poll; CHANGED keeps polling to WATCH_TIMEOUT"
  else
    failed "approval:marker-ends-poll-process" "$lifetime_detail"
  fi
else
  skipped "approval:marker-ends-poll-process" "$SKIP_REASON"
fi

# ── 35. the QUIET-EXIT CHECK judges the pending seed exactly as the poll would ─────────
# The approval marker ends the poll, so after a confirmation pass no poll is running. Activity
# that landed after the pending seed is caught only by the --check the skill runs before the watch
# goes quiet. Gated on SEED_SUPPORTED with no probe of its own: a script without --check reads the
# flag as OWNER and prints POLL_ERROR, so every case goes red.
#   (a) THE BITE: a `re-arm` seed captured over the pre-cycle-0 state with the Codex 👍, then a new
#       Codex issue comment: exactly CHANGED, exit 0, one capture.
#   (b) the same seed over the unchanged state: exactly UNCHANGED, exit 0, one capture.
#   (c) parity: over each delta class, a derived MERGED and CLOSED state, an approval rise, and no
#       delta, the check's line equals the expected marker AND the first line of a poll armed with
#       the same seed over the same state (its WATCH_TIMEOUT read as UNCHANGED); exit 0, one capture.
#       A failed-check rise is CI_FAILED, and a drop against a red re-arm seed is CHANGED.
#   (d) fail-closed: a failed snapshot query (no retry), a missing seed, and a malformed seed (no gh
#       call) each print exactly CHECK_ERROR, exit 1.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  check_seed="$(capture_seed checkseed re-arm "$PRE" "$REACT_CODEX")"

  st="$(new_state check-delta)"
  set_seq "$st" graphql "$delta_comment"
  set_seq "$st" reactions "$REACT_CODEX"
  out="$(run_check "$st" "$check_seed")"
  status=$?
  calls="$(gh_call_counts "$st")"
  if [ "$out" = "CHANGED" ] && [ "$status" -eq 0 ] && [ "$calls" = "1 1 1" ]; then
    pass "check:delta-after-pending-seed-detected" "comment after the pending re-arm seed -> CHANGED, exit 0, one capture"
  else
    failed "check:delta-after-pending-seed-detected" "expected exactly CHANGED exit 0 calls=1 1 1, got status=$status calls=$calls out=$(printf '%s' "$out" | tr '\n' ';') seed=$check_seed"
  fi

  st="$(new_state check-nodelta)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_CODEX"
  out="$(run_check "$st" "$check_seed")"
  status=$?
  calls="$(gh_call_counts "$st")"
  if [ "$out" = "UNCHANGED" ] && [ "$status" -eq 0 ] && [ "$calls" = "1 1 1" ]; then
    pass "check:no-delta-unchanged" "state unchanged since the pending seed -> UNCHANGED, exit 0, one capture"
  else
    failed "check:no-delta-unchanged" "expected exactly UNCHANGED exit 0 calls=1 1 1, got status=$status calls=$calls out=$(printf '%s' "$out" | tr '\n' ';') seed=$check_seed"
  fi

  parity_ok=1
  parity_detail=""
  parity_seed="$(capture_seed checkparityseed re-arm "$PRE" "$REACT_NONE")"
  parity_red_seed="$(capture_seed checkparityredseed re-arm "$delta_checks" "$REACT_NONE")"
  state_merged="$(derive_fixture state-merged "$PRE" '.data.repository.pullRequest.state = "MERGED"')"
  state_closed="$(derive_fixture state-closed "$PRE" '.data.repository.pullRequest.state = "CLOSED"')"
  # INVARIANT: the seed is the LAST row field: it carries `|` itself, and `read` hands the last
  # name the remainder of the line.
  for parity_row in "totals|$delta_total|$REACT_NONE|CHANGED|$parity_seed" \
    "checks|$delta_checks|$REACT_NONE|CI_FAILED|$parity_seed" \
    "checks-drop|$PRE|$REACT_NONE|CHANGED|$parity_red_seed" \
    "merged|$state_merged|$REACT_NONE|STATE=MERGED|$parity_seed" \
    "closed|$state_closed|$REACT_NONE|STATE=CLOSED|$parity_seed" \
    "approval|$PRE|$REACT_CODEX|REVIEWER_APPROVED|$parity_seed" \
    "nodelta|$PRE|$REACT_NONE|UNCHANGED|$parity_seed"; do
    IFS='|' read -r parity_name parity_graphql parity_reactions parity_expected parity_row_seed <<EOF
$parity_row
EOF
    st="$(new_state "check-parity-$parity_name")"
    set_seq "$st" graphql "$parity_graphql"
    set_seq "$st" reactions "$parity_reactions"
    check_out="$(run_check "$st" "$parity_row_seed")"
    status=$?
    calls="$(gh_call_counts "$st")"

    st="$(new_state "check-parity-$parity_name-poll")"
    set_seq "$st" graphql "$parity_graphql"
    set_seq "$st" reactions "$parity_reactions"
    poll_first="$(arm_poll "$st" "$parity_row_seed" | head -1)"
    [ "$poll_first" != "WATCH_TIMEOUT" ] || poll_first="UNCHANGED"

    if [ "$check_out" != "$poll_first" ] || [ "$check_out" != "$parity_expected" ] \
      || [ "$status" -ne 0 ] || [ "$calls" != "1 1 1" ]; then
      parity_ok=0
      parity_detail="$parity_detail $parity_name: expected=$parity_expected check=$(printf '%s' "$check_out" | tr '\n' ';') poll_first=$poll_first status=$status calls=$calls seed=$parity_row_seed"
    fi
  done
  if [ "$parity_ok" -eq 1 ]; then
    pass "check:parity-with-poll-first-iteration" "totals, checks rise (CI_FAILED), checks drop (CHANGED), merged, closed, approval rise, no delta: check line == poll first line == expected, exit 0, one capture"
  else
    failed "check:parity-with-poll-first-iteration" "$parity_detail"
  fi

  check_fail_ok=1
  check_fail_detail=""
  # INVARIANT: the seed is the LAST row field: it carries `|` itself, and `read` hands the last
  # name the remainder of the line.
  for check_fail_row in "ghfail|FAIL|1 0 0|$check_seed" \
    "missing-seed|$PRE|0 0 0|" \
    "malformed-seed|$PRE|0 0 0|not-a-baseline-token"; do
    IFS='|' read -r check_fail_name check_fail_graphql check_fail_calls check_fail_seed <<EOF
$check_fail_row
EOF
    st="$(new_state "check-fail-$check_fail_name")"
    set_seq "$st" graphql "$check_fail_graphql"
    set_seq "$st" reactions "$REACT_NONE"
    out="$(run_check "$st" "$check_fail_seed")"
    status=$?
    calls="$(gh_call_counts "$st")"
    if [ "$out" != "CHECK_ERROR" ] || [ "$status" -ne 1 ] || [ "$calls" != "$check_fail_calls" ]; then
      check_fail_ok=0
      check_fail_detail="$check_fail_detail $check_fail_name: status=$status calls=$calls expected_calls=$check_fail_calls out=$(printf '%s' "$out" | tr '\n' ';')"
    fi
  done
  if [ "$check_fail_ok" -eq 1 ]; then
    pass "check:fails-closed" "gh failure (one call, no retry), missing seed and malformed seed (no gh call) -> CHECK_ERROR, exit 1"
  else
    failed "check:fails-closed" "$check_fail_detail"
  fi
else
  for check_case_id in check:delta-after-pending-seed-detected check:no-delta-unchanged \
    check:parity-with-poll-first-iteration check:fails-closed; do
    skipped "$check_case_id" "$SKIP_REASON"
  done
fi

# ── 36. the retired filter value is rejected in every mode before any gh call ──────────
# The module's `is_retired_filter` names one former filter value. Snapshot, check and poll mode
# each print exactly their error marker (SNAPSHOT_ERROR / CHECK_ERROR / POLL_ERROR), exit 1, and
# the fake gh sees no call at all (`0 0 0`): the rejection is an input gate, not a capture failure.
retired_ok=1
retired_detail=""
for retired_mode in snapshot check poll; do
  st="$(new_state "retired-$retired_mode")"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  case "$retired_mode" in
    snapshot)
      retired_expected="SNAPSHOT_ERROR"
      out="$(run_poll "$st" --snapshot initial "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" \
        "$POLL_INTERVAL" "$RETIRED_FILTER" "$SELF_LOGIN")"
      ;;
    check)
      retired_expected="CHECK_ERROR"
      out="$(run_check "$st" "$SEED" "$RETIRED_FILTER")"
      ;;
    poll)
      retired_expected="POLL_ERROR"
      out="$(arm_poll "$st" "$SEED" "$RETIRED_FILTER")"
      ;;
  esac
  status=$?
  calls="$(gh_call_counts "$st")"
  if [ "$out" != "$retired_expected" ] || [ "$status" -ne 1 ] || [ "$calls" != "0 0 0" ]; then
    retired_ok=0
    retired_detail="$retired_detail $retired_mode: status=$status calls=$calls out=$(printf '%s' "$out" | tr '\n' ';')"
  fi
done
if [ "$retired_ok" -eq 1 ]; then
  pass "filter:retired-value-rejected" "retired filter -> SNAPSHOT_ERROR / CHECK_ERROR / POLL_ERROR, exit 1, zero gh calls"
else
  failed "filter:retired-value-rejected" "$retired_detail"
fi

# ── 37. every bot shape approves identically through every approval signal ──────────────
# No reviewer product is named in code, so a Codex-shaped, a Copilot-shaped and a generic bot login
# must behave the same. For each: a REST-shaped 👍 (User-typed `[bot]` login) on the pre-cycle-0
# state, an APPROVED latest review, and a COMMENTED latest review with zero inline comments each
# fire REVIEWER_APPROVED first under `automated` with no HIVEMIND_PR_REVIEWERS: the 👍 or the
# review is itself the evidence that makes the bot an Automated Reviewer.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  shape_ok=1
  shape_detail=""
  for shape_login in "$CODEX_SHAPED_BOT" "$COPILOT_SHAPED_BOT" "$GENERIC_BOT"; do
    shape_thumbs="$(bot_thumbs_up "shape-thumbs-$shape_login" "$shape_login")"
    shape_approved="$(bot_review_state "shape-approved-$shape_login" "$shape_login" APPROVED '{"totalCount":0}')"
    shape_commented="$(bot_review_state "shape-commented-$shape_login" "$shape_login" COMMENTED '{"totalCount":0}')"
    for shape_signal in "thumbs|$PRE|$shape_thumbs" "approved|$shape_approved|$REACT_NONE" \
      "commented-no-inline|$shape_commented|$REACT_NONE"; do
      IFS='|' read -r shape_name shape_graphql shape_reactions <<EOF
$shape_signal
EOF
      out="$(seeded_poll_output "shape-$shape_login-$shape_name" "$shape_graphql" "$shape_reactions")"
      if [ "$(printf '%s\n' "$out" | head -1)" != "REVIEWER_APPROVED" ]; then
        shape_ok=0
        shape_detail="$shape_detail login=$shape_login signal=$shape_name got=$(printf '%s' "$out" | tr '\n' ';')"
      fi
    done
  done
  if [ "$shape_ok" -eq 1 ]; then
    pass "approval:every-bot-shape-approves-identically" "Codex-shaped, Copilot-shaped and generic bots: 👍, APPROVED and COMMENTED with 0 inline each fired REVIEWER_APPROVED first"
  else
    failed "approval:every-bot-shape-approves-identically" "$shape_detail"
  fi
else
  skipped "approval:every-bot-shape-approves-identically" "$SKIP_REASON"
fi

# ── 38. a COMMENTED review with inline comments, or an unknown inline count, never approves ─
# A COMMENTED latest review approves only with exactly zero inline review comments. A count above
# zero, a `comments` key that is absent, a null `comments`, and a null `totalCount` are each no
# approval under `automated` OR `all`; the new review still moves REVIEWS_TOTAL, so CHANGED fires.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  inline_ok=1
  inline_detail=""
  inline_index=0
  for inline_comments in '{"totalCount":2}' absent null '{"totalCount":null}'; do
    inline_index=$((inline_index + 1))
    inline_fixture="$(bot_review_state "inline-$inline_index" "$GENERIC_BOT" COMMENTED "$inline_comments")"
    for inline_filter in automated all; do
      out="$(seeded_poll_output "inline-$inline_index-$inline_filter" "$inline_fixture" "$REACT_NONE" "$inline_filter")"
      if printf '%s\n' "$out" | grep -qx 'REVIEWER_APPROVED' \
        || ! printf '%s\n' "$out" | grep -qx 'CHANGED'; then
        inline_ok=0
        inline_detail="$inline_detail comments=$inline_comments filter=$inline_filter got=$(printf '%s' "$out" | tr '\n' ';')"
      fi
    done
  done
  if [ "$inline_ok" -eq 1 ]; then
    pass "approval:commented-with-inline-or-unknown-never-approves" "COMMENTED with 2 inline, absent, null comments or null totalCount fired CHANGED, never REVIEWER_APPROVED"
  else
    failed "approval:commented-with-inline-or-unknown-never-approves" "$inline_detail"
  fi
else
  skipped "approval:commented-with-inline-or-unknown-never-approves" "$SKIP_REASON"
fi

# ── 39. the CI identity approves only when listed in HIVEMIND_PR_REVIEWERS ──────────────
# `github-actions` is dropped from the evidence-derived set. Unlisted, its REST-shaped 👍 idles to
# WATCH_TIMEOUT and its APPROVED latest review fires only CHANGED, under `automated` AND `all`.
# Listed (with the `[bot]` suffix in one arm, bare among comma- and space-separated logins in the
# other), each fires REVIEWER_APPROVED first. A listed value shaped like jq program text is data,
# never code: it neither errors the capture nor admits the unlisted CI identity.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  ci_ok=1
  ci_detail=""
  ci_thumbs="$(bot_thumbs_up ci-thumbs "$CI_BOT")"
  ci_approved="$(bot_review_state ci-approved "$CI_BOT" APPROVED '{"totalCount":0}')"
  for ci_row in "unlisted-thumbs-automated||automated|$PRE|$ci_thumbs|WATCH_TIMEOUT" \
    "unlisted-thumbs-all||all|$PRE|$ci_thumbs|WATCH_TIMEOUT" \
    "unlisted-review-automated||automated|$ci_approved|$REACT_NONE|CHANGED" \
    "unlisted-review-all||all|$ci_approved|$REACT_NONE|CHANGED" \
    "program-text-review|\") or true or (\"|automated|$ci_approved|$REACT_NONE|CHANGED" \
    "listed-thumbs|$CI_BOT[bot]|automated|$PRE|$ci_thumbs|REVIEWER_APPROVED" \
    "listed-review|$GENERIC_BOT, $CI_BOT other-bot|automated|$ci_approved|$REACT_NONE|REVIEWER_APPROVED"; do
    IFS='|' read -r ci_name ci_reviewers ci_filter ci_graphql ci_reactions ci_expected <<EOF
$ci_row
EOF
    out="$(HIVEMIND_PR_REVIEWERS="$ci_reviewers" \
      seeded_poll_output "ci-$ci_name" "$ci_graphql" "$ci_reactions" "$ci_filter")"
    case "$ci_expected" in
      WATCH_TIMEOUT) [ "$out" = "WATCH_TIMEOUT" ] || ci_ok=0 ;;
      CHANGED)
        if printf '%s\n' "$out" | grep -qx 'REVIEWER_APPROVED' \
          || ! printf '%s\n' "$out" | grep -qx 'CHANGED'; then
          ci_ok=0
        fi
        ;;
      REVIEWER_APPROVED) [ "$(printf '%s\n' "$out" | head -1)" = "REVIEWER_APPROVED" ] || ci_ok=0 ;;
    esac
    ci_detail="$ci_detail $ci_name: expected=$ci_expected got=$(printf '%s' "$out" | tr '\n' ';')"
  done
  if [ "$ci_ok" -eq 1 ]; then
    pass "approval:ci-identity-only-when-listed" "unlisted CI 👍 / APPROVED never approved under automated or all; listed CI fired REVIEWER_APPROVED; program-text value stayed data"
  else
    failed "approval:ci-identity-only-when-listed" "$ci_detail"
  fi
else
  skipped "approval:ci-identity-only-when-listed" "$SKIP_REASON"
fi

# ── 40. a status bot's comment wakes the reviewer but never approves ───────────────────
# A Bot that only posts a plain PR comment (coverage, deploy preview) submits no review and leaves
# no 👍, so it is no Automated Reviewer. Its new issue comment moves
# LATEST_NONSELF_ISSUE_COMMENT_ID and COMMENTS_TOTAL, so CHANGED fires; REVIEWER_APPROVED never
# does, under `automated` OR `all`.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  status_ok=1
  status_detail=""
  status_comment="$(derive_fixture status-bot-comment "$PRE" \
    ".data.repository.pullRequest.comments.totalCount = 3
     | .data.repository.pullRequest.comments.nodes += [{\"databaseId\":2411003,\"author\":{\"login\":\"$STATUS_BOT\",\"__typename\":\"Bot\"}}]")"
  for status_filter in automated all; do
    out="$(seeded_poll_output "status-bot-$status_filter" "$status_comment" "$REACT_NONE" "$status_filter")"
    if printf '%s\n' "$out" | grep -qx 'REVIEWER_APPROVED' \
      || ! printf '%s\n' "$out" | grep -qx 'CHANGED'; then
      status_ok=0
      status_detail="$status_detail filter=$status_filter got=$(printf '%s' "$out" | tr '\n' ';')"
    fi
  done
  if [ "$status_ok" -eq 1 ]; then
    pass "approval:status-bot-comment-changes-never-approves" "status bot comment fired CHANGED, never REVIEWER_APPROVED, under automated and all"
  else
    failed "approval:status-bot-comment-changes-never-approves" "$status_detail"
  fi
else
  skipped "approval:status-bot-comment-changes-never-approves" "$SKIP_REASON"
fi

# ── 41. the CI route: a FAILED_CHECKS rise is CI_FAILED, a drop or steady red is CHANGED ──
# The prefilter judges only the review surfaces, so a wake whose only change is the failed-check
# count would be PREFILTER_SKIP, and the running poll has already moved its baseline (#400). A rise
# therefore prints its own marker, CI_FAILED, which the skill dispatches without the prefilter;
# a drop and every other delta stay CHANGED, so a steady red run never re-dispatches. Red seeds are
# captured over the derived red state; no committed fixture changes.
#   (a) a red seed over the green state (a drop) prints CHANGED, never CI_FAILED.
#   (b) a red seed over the same red count plus a new non-self comment prints CHANGED only.
#   (c) a rise and a comment delta in one iteration print CI_FAILED, never CHANGED.
#   (d) a running poll served 0, 1, 1, 2 failed checks prints CI_FAILED once per rise and nothing
#       on the steady iteration.
#   (e) an approval edge co-firing with a rise prints REVIEWER_APPROVED only and ends the process.
#   (f) a seed whose failed_checks field is not all digits, or is 19 digits (past the 18-digit
#       bound that keeps Bash's 64-bit arithmetic from wrapping), is POLL_ERROR / CHECK_ERROR,
#       exit 1, with zero gh calls.

# seed_with_failed_checks <value>: the shared seed with its failed_checks field set to <value>.
seed_with_failed_checks() {
  local field_pos
  field_pos=$(($(declared_fields | grep -nx 'failed_checks' | cut -d: -f1) + 1))
  printf '%s' "$SEED" | awk -F'|' -v OFS='|' -v pos="$field_pos" -v value="$1" '{$pos = value; print}'
}

# ci_route_poll <state_name> <seed> <max_watch> <graphql_entry>...: a poll armed with <seed> under
# a <max_watch>-poll window, serving the graphql entries in order and no reaction to every poll.
ci_route_poll() {
  local st seed="$2" max_watch="$3"
  st="$(new_state "$1")"
  shift 3
  set_seq "$st" graphql "$@"
  set_seq "$st" reactions "$REACT_NONE"
  run_poll "$st" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$max_watch" "$POLL_INTERVAL" \
    "$REVIEWER_FILTER" "$SELF_LOGIN" "$seed"
}

if [ "$SEED_SUPPORTED" -eq 1 ]; then
  ci_red_seed="$(capture_seed ci-red-seed re-arm "$delta_checks" "$REACT_NONE")"
  ci_red_comment="$(derive_fixture ci-red-comment "$delta_checks" \
    '.data.repository.pullRequest.comments.totalCount = 3
     | .data.repository.pullRequest.comments.nodes += [{"databaseId":2411003,"author":{"login":"chatgpt-codex-connector","__typename":"Bot"}}]')"
  ci_checks_two="$(derive_fixture ci-checks-two "$PRE" \
    '.data.repository.pullRequest.statusCheckRollup.contexts.checkRunCountsByState =
       [{"state":"SUCCESS","count":1},{"state":"FAILURE","count":2}]')"
  ci_changed_then_timeout="$(printf 'CHANGED\nWATCH_TIMEOUT')"
  ci_failed_then_timeout="$(printf 'CI_FAILED\nWATCH_TIMEOUT')"

  out="$(ci_route_poll ci-drop "$ci_red_seed" "$MAX_WATCH" "$PRE")"
  if [ "$out" = "$ci_changed_then_timeout" ]; then
    pass "ci:drop-fires-changed" "red seed over green state fired CHANGED, never CI_FAILED"
  else
    failed "ci:drop-fires-changed" "expected exactly CHANGED;WATCH_TIMEOUT, got=$(printf '%s' "$out" | tr '\n' ';') seed=$ci_red_seed"
  fi

  out="$(ci_route_poll ci-steady-red-comment "$ci_red_seed" "$MAX_WATCH" "$ci_red_comment")"
  if [ "$out" = "$ci_changed_then_timeout" ]; then
    pass "ci:steady-red-with-comment-fires-changed" "same red count plus a new comment fired CHANGED only"
  else
    failed "ci:steady-red-with-comment-fires-changed" "expected exactly CHANGED;WATCH_TIMEOUT, got=$(printf '%s' "$out" | tr '\n' ';') seed=$ci_red_seed"
  fi

  out="$(ci_route_poll ci-rise-comment "$SEED" "$MAX_WATCH" "$PRE" "$ci_red_comment")"
  if [ "$out" = "$ci_failed_then_timeout" ]; then
    pass "ci:rise-with-comment-fires-ci-failed" "rise plus comment delta in one iteration fired CI_FAILED, never CHANGED"
  else
    failed "ci:rise-with-comment-fires-ci-failed" "expected exactly CI_FAILED;WATCH_TIMEOUT, got=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  out="$(ci_route_poll ci-each-rise "$SEED" 4 "$PRE" "$delta_checks" "$delta_checks" "$ci_checks_two")"
  if [ "$out" = "$(printf 'CI_FAILED\nCI_FAILED\nWATCH_TIMEOUT')" ]; then
    pass "ci:each-rise-fires-once" "failed checks 0, 1, 1, 2 fired CI_FAILED on each rise and nothing on the steady poll"
  else
    failed "ci:each-rise-fires-once" "expected exactly CI_FAILED;CI_FAILED;WATCH_TIMEOUT, got=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  st="$(new_state ci-approval-cofire)"
  set_seq "$st" graphql "$PRE" "$delta_checks"
  set_seq "$st" reactions "$REACT_NONE" "$REACT_CODEX"
  out="$(run_poll "$st" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$LIFETIME_MAX_WATCH" "$POLL_INTERVAL" \
    "$REVIEWER_FILTER" "$SELF_LOGIN" "$SEED")"
  status=$?
  graphql_calls="$(cat "$st/graphql.n")"
  if [ "$out" = "REVIEWER_APPROVED" ] && [ "$status" -eq 0 ] && [ "$graphql_calls" = "2" ]; then
    pass "ci:approval-cofire-wins" "approval co-firing with a rise printed REVIEWER_APPROVED only, exit 0, no later poll"
  else
    failed "ci:approval-cofire-wins" "expected exactly REVIEWER_APPROVED exit 0 graphql_calls=2, got status=$status graphql_calls=$graphql_calls out=$(printf '%s' "$out" | tr '\n' ';')"
  fi

  ci_seed_ok=1
  ci_seed_detail=""
  for ci_bad_value in 1a -1 1234567890123456789; do
    ci_bad_seed="$(seed_with_failed_checks "$ci_bad_value")"
    for ci_seed_mode in poll check; do
      st="$(new_state "ci-bad-seed-$ci_bad_value-$ci_seed_mode")"
      set_seq "$st" graphql "$PRE"
      set_seq "$st" reactions "$REACT_NONE"
      if [ "$ci_seed_mode" = "poll" ]; then
        ci_seed_expected="POLL_ERROR"
        out="$(arm_poll "$st" "$ci_bad_seed")"
      else
        ci_seed_expected="CHECK_ERROR"
        out="$(run_check "$st" "$ci_bad_seed")"
      fi
      status=$?
      calls="$(gh_call_counts "$st")"
      if [ "$out" != "$ci_seed_expected" ] || [ "$status" -ne 1 ] || [ "$calls" != "0 0 0" ]; then
        ci_seed_ok=0
        ci_seed_detail="$ci_seed_detail $ci_seed_mode/$ci_bad_value: status=$status calls=$calls out=$(printf '%s' "$out" | tr '\n' ';') seed=$ci_bad_seed"
      fi
    done
  done
  if [ "$ci_seed_ok" -eq 1 ]; then
    pass "ci:seed-non-digit-failed-checks-fails-closed" "non-digit or oversized failed_checks seed field -> POLL_ERROR / CHECK_ERROR, exit 1, zero gh calls"
  else
    failed "ci:seed-non-digit-failed-checks-fails-closed" "$ci_seed_detail"
  fi
else
  for ci_case_id in ci:drop-fires-changed ci:steady-red-with-comment-fires-changed \
    ci:rise-with-comment-fires-ci-failed ci:each-rise-fires-once ci:approval-cofire-wins \
    ci:seed-non-digit-failed-checks-fails-closed; do
    skipped "$ci_case_id" "$SKIP_REASON"
  done
fi

# ── 42. the watch window bounds every poll sleep ─────────────────────────────────────
# A sleep is the smaller of the poll interval and the seconds left to the deadline, so no sleep
# outruns the window and WATCH_TIMEOUT is never late. A re-arm whose window is smaller than the
# interval is a legitimate input (SKILL.md Window deadline), not a rejected one. The fake clock
# reads epoch plus the snapshot-query count and the fake sleep records each argument, so the
# recorded sleeps are exact.
#   (a) a steady state under a 5-poll window with interval 3600, and again with the 18-digit
#       interval, prints exactly WATCH_TIMEOUT and sleeps 4, 3, 2, 1: each sleep is the time left.
#       Interval 2 sleeps 2, 2, 2, 1: an interval below the time left passes through unchanged.
#   (b) a failed first capture then the steady state, interval 3600, sleeps 4 first and prints
#       exactly WATCH_TIMEOUT, not POLL_ERROR.
#   (c) STRUCTURAL: the executable, non-comment lines of the poll hold exactly one `sleep` command,
#       inside sleep_to_next_poll, so a second raw sleep goes red.
WINDOW_MAX_WATCH=5

# window_poll <state_dir> <interval>: a poll armed with the shared seed under the 5-poll window.
window_poll() {
  run_poll "$1" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$WINDOW_MAX_WATCH" "$2" \
    "$REVIEWER_FILTER" "$SELF_LOGIN" "$SEED"
}

# recorded_sleeps <state_dir>: every argument the fake `sleep` recorded, comma-joined in order.
recorded_sleeps() {
  paste -sd, "$1/sleep.calls"
}

# poll_sleep_commands: `<line>:<in_helper>` for each `sleep` command on an executable,
# non-comment line of the poll, <in_helper> 1 inside sleep_to_next_poll and 0 elsewhere.
poll_sleep_commands() {
  awk '
    /^sleep_to_next_poll\(\) \{/ { in_helper = 1 }
    /^[[:space:]]*#/ { next }
    /(^|[^[:alnum:]_-])sleep([[:space:]]|$)/ { print NR ":" in_helper + 0 }
    in_helper && /^\}/ { in_helper = 0 }
  ' "$POLL"
}

if [ "$SEED_SUPPORTED" -eq 1 ]; then
  window_ok=1
  window_detail=""
  for window_case in 3600:4,3,2,1 999999999999999999:4,3,2,1 2:2,2,2,1; do
    window_interval="${window_case%%:*}"
    window_expected="${window_case#*:}"
    st="$(new_state "window-$window_interval")"
    set_seq "$st" graphql "$PRE"
    set_seq "$st" reactions "$REACT_NONE"
    out="$(window_poll "$st" "$window_interval")"
    status=$?
    window_sleeps="$(recorded_sleeps "$st")"
    if [ "$out" != "WATCH_TIMEOUT" ] || [ "$status" -ne 0 ] \
      || [ "$window_sleeps" != "$window_expected" ]; then
      window_ok=0
      window_detail="$window_detail interval=$window_interval: status=$status sleeps=$window_sleeps expected=$window_expected out=$(printf '%s' "$out" | tr '\n' ';')"
    fi
  done
  if [ "$window_ok" -eq 1 ]; then
    pass "watch:sleep-never-outruns-window" "interval 3600 or 18 digits sleeps 4,3,2,1 to WATCH_TIMEOUT; interval 2 sleeps 2,2,2,1"
  else
    failed "watch:sleep-never-outruns-window" "$window_detail"
  fi

  st="$(new_state window-failed-capture)"
  set_seq "$st" graphql FAIL "$PRE"
  set_seq "$st" latestreviews "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(window_poll "$st" 3600)"
  status=$?
  window_first_sleep="$(head -1 "$st/sleep.calls")"
  if [ "$out" = "WATCH_TIMEOUT" ] && [ "$status" -eq 0 ] && [ "$window_first_sleep" = "4" ]; then
    pass "watch:failed-capture-sleep-clamped" "failed first capture slept 4, not 3600, then idled to WATCH_TIMEOUT"
  else
    failed "watch:failed-capture-sleep-clamped" "expected WATCH_TIMEOUT exit 0 first sleep 4, got status=$status first_sleep=$window_first_sleep sleeps=$(recorded_sleeps "$st") out=$(printf '%s' "$out" | tr '\n' ';')"
  fi
else
  skipped "watch:sleep-never-outruns-window" "$SKIP_REASON"
  skipped "watch:failed-capture-sleep-clamped" "$SKIP_REASON"
fi

sleep_commands="$(poll_sleep_commands)"
if [ "$(printf '%s\n' "$sleep_commands" | grep -c .)" = "1" ] \
  && printf '%s\n' "$sleep_commands" | grep -qx '[0-9]*:1'; then
  pass "watch:one-sleep-primitive" "the poll's only sleep command is inside sleep_to_next_poll"
else
  failed "watch:one-sleep-primitive" "expected exactly one sleep command, inside sleep_to_next_poll, got line:in_helper=[$(printf '%s' "$sleep_commands" | tr '\n' ' ')]"
fi

# ── 43. every number is read through one checked source ──────────────────────────────
# The poll checks each number where it is read, never where it is used: read_decimal is the only
# bounded-decimal check and base-10 coercion, and read_clock holds the only `date` command. No scan
# of the poll's text decides whether a number is checked: Bash evaluates a number in many syntax
# forms (arithmetic expansion, `(( ))`, `let`, `declare -i`, `[[ -eq ]]`, subscripts, substring
# offsets), so a list of them cannot be complete. The rule is held by running the poll with
# hostile and zero-padded readings at every source the contract names: the PR number, window and
# interval arguments, the seed's failed_checks field, a capture's check count and the clock. A new
# source of numbers is a new row. ARITH_PAYLOAD is a reading that arithmetic evaluation runs: it
# creates ARITH_CANARY, so any syntax form that evaluates a reading before its check leaves the
# canary behind. Its base name is BASH_VERSINFO, an array every Bash sets, because the poll runs
# under `set -u` and an unset base name would abort the evaluation before the subscript runs. A zero-padded reading changes the output when any use skips the base-10 coercion.
# The fake `date` serves `date.seq`, counts its calls in `date.n`, and pads with `date.padded`.
#   (a) each bad reading (FAIL, empty, abc, -1, 19 digits, ARITH_PAYLOAD) served on clock read N,
#       N = 1 to 4, over the steady pre-cycle-0 state armed with the shared seed, prints exactly
#       POLL_ERROR, exit 1, after exactly N clock reads. Reads 1 to 4 are arm time, the first loop
#       top, the first sleep_to_next_poll and the second loop top. On N = 1 the fake gh sees zero
#       calls.
#   (b) with every clock read failing, --snapshot prints its BASELINE= line and --check with the
#       shared seed prints UNCHANGED, each exit 0 with zero clock reads.
#   (c) a 19-digit PR number is POLL_ERROR, exit 1, with zero gh calls.
#   (d) STRUCTURAL: the executable, non-comment lines of the poll hold exactly one `date` command,
#       inside read_clock.
#   (e) ARITH_PAYLOAD, abc, -1 and empty, each served as the PR number, the window and the
#       interval of a seeded poll over the steady state, print exactly POLL_ERROR, exit 1, zero gh
#       calls. ARITH_PAYLOAD served as the seed's failed_checks field, through an exported variable
#       whose name is the field value (the seed shape allows only [A-Za-z0-9_-], and arithmetic on
#       a name runs its value), is POLL_ERROR in poll mode and CHECK_ERROR in --check mode, exit
#       1, zero gh calls. ARITH_CANARY does not exist after every row, (a) included, ran.
#   (f) a seeded poll over the steady state with window 12 and interval 9 prints exactly
#       WATCH_TIMEOUT, exit 0, and sleeps 9,9,9,8,7,6,5,4,3,2,1. The same poll with the PR number,
#       window and interval zero-padded (004242, 0012, 0009), the seed's failed_checks field
#       padded (000) and every clock reading padded gives identical output, status and sleeps.
#   (g) a capture whose checkRunCountsByState holds a FAILURE count of -1, or of 19 digits, is
#       SNAPSHOT_ERROR in snapshot mode and POLL_ERROR in poll mode.
ARITH_CANARY="$TMPDIR_TEST/arith-canary"
ARITH_PAYLOAD="BASH_VERSINFO[\$(touch $(printf '%q' "$ARITH_CANARY"))]"
CLOCK_BAD_READINGS=(FAIL "" abc -1 9999999999999999999 "$ARITH_PAYLOAD")
CLOCK_BAD_READ_COUNT=4

# clock_poll_outcome <state_name> <bad_reading> <read_number>: a poll armed with the shared seed
# over the steady pre-cycle-0 state, its clock reads 1 to <read_number> - 1 serving the virtual
# clock and read <read_number> serving <bad_reading>, as `<status>:<date_calls>:<gh_calls>:<out>`.
clock_poll_outcome() {
  local st out status read_index
  local -a clock_entries=()
  st="$(new_state "$1")"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  for ((read_index = 1; read_index < $3; read_index++)); do
    clock_entries+=(CLOCK)
  done
  clock_entries+=("$2")
  set_seq "$st" date "${clock_entries[@]}"
  out="$(arm_poll "$st" "$SEED")"
  status=$?
  printf '%s:%s:%s:%s' "$status" "$(cat "$st/date.n")" "$(gh_call_counts "$st")" \
    "$(printf '%s' "$out" | tr '\n' ';')"
}

# poll_date_commands: `<line>:<in_helper>` for each `date` command on an executable, non-comment
# line of the poll, <in_helper> 1 inside read_clock and 0 elsewhere.
poll_date_commands() {
  awk '
    /^read_clock\(\) \{/ { in_helper = 1 }
    /^[[:space:]]*#/ { next }
    /(^|[^[:alnum:]_-])date([[:space:]]|$)/ { print NR ":" in_helper + 0 }
    in_helper && /^\}/ { in_helper = 0 }
  ' "$POLL"
}

if [ "$SEED_SUPPORTED" -eq 1 ]; then
  clock_ok=1
  clock_detail=""
  for clock_bad_index in "${!CLOCK_BAD_READINGS[@]}"; do
    clock_bad_value="${CLOCK_BAD_READINGS[$clock_bad_index]}"
    for ((clock_read = 1; clock_read <= CLOCK_BAD_READ_COUNT; clock_read++)); do
      clock_outcome="$(clock_poll_outcome "clock-bad-$clock_bad_index-$clock_read" \
        "$clock_bad_value" "$clock_read")"
      clock_expected="1:$clock_read:$(cut -d: -f3 <<<"$clock_outcome"):POLL_ERROR"
      [ "$clock_read" -ne 1 ] || clock_expected="1:1:0 0 0:POLL_ERROR"
      if [ "$clock_outcome" != "$clock_expected" ]; then
        clock_ok=0
        clock_detail="$clock_detail reading=[$clock_bad_value] read=$clock_read: status:date_calls:gh_calls:out=$clock_outcome"
      fi
    done
  done
  if [ "$clock_ok" -eq 1 ]; then
    pass "clock:bad-reading-fails-closed" "a failed, empty, non-digit, negative or 19-digit reading on clock read 1 to 4 -> POLL_ERROR, exit 1, after exactly that many reads"
  else
    failed "clock:bad-reading-fails-closed" "$clock_detail"
  fi

  st="$(new_state clock-snapshot)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  set_seq "$st" date FAIL
  snapshot_out="$(run_poll "$st" --snapshot initial "$OWNER" "$REPO_NAME" "$PR_NUMBER" \
    "$MAX_WATCH" "$POLL_INTERVAL" "$REVIEWER_FILTER" "$SELF_LOGIN")"
  snapshot_status=$?
  snapshot_date_calls="$(cat "$st/date.n")"
  st="$(new_state clock-check)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  set_seq "$st" date FAIL
  check_out="$(run_check "$st" "$SEED")"
  check_status=$?
  check_date_calls="$(cat "$st/date.n")"
  if [ "$(printf '%s\n' "$snapshot_out" | grep -c .)" = "1" ] \
    && printf '%s\n' "$snapshot_out" | grep -q '^BASELINE=.' && [ "$snapshot_status" -eq 0 ] \
    && [ "$snapshot_date_calls" = "0" ] && [ "$check_out" = "UNCHANGED" ] \
    && [ "$check_status" -eq 0 ] && [ "$check_date_calls" = "0" ]; then
    pass "clock:snapshot-and-check-never-read-clock" "--snapshot printed BASELINE= and --check printed UNCHANGED, each exit 0 with zero clock reads"
  else
    failed "clock:snapshot-and-check-never-read-clock" "snapshot: status=$snapshot_status date_calls=$snapshot_date_calls out=$(printf '%s' "$snapshot_out" | tr '\n' ';') check: status=$check_status date_calls=$check_date_calls out=$(printf '%s' "$check_out" | tr '\n' ';')"
  fi

  st="$(new_state oversized-pr)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  out="$(run_poll "$st" "$OWNER" "$REPO_NAME" "1234567890123456789" "$MAX_WATCH" "$POLL_INTERVAL" \
    "$REVIEWER_FILTER" "$SELF_LOGIN" "$SEED")"
  status=$?
  calls="$(gh_call_counts "$st")"
  if [ "$out" = "POLL_ERROR" ] && [ "$status" -eq 1 ] && [ "$calls" = "0 0 0" ]; then
    pass "validation:oversized-pr-number" "19-digit PR number -> POLL_ERROR, exit 1, zero gh calls"
  else
    failed "validation:oversized-pr-number" "status=$status calls=$calls out=$(printf '%s' "$out" | tr '\n' ';')"
  fi
else
  skipped "clock:bad-reading-fails-closed" "$SKIP_REASON"
  skipped "clock:snapshot-and-check-never-read-clock" "$SKIP_REASON"
  skipped "validation:oversized-pr-number" "$SKIP_REASON"
fi

date_commands="$(poll_date_commands)"
if [ "$(printf '%s\n' "$date_commands" | grep -c .)" = "1" ] \
  && printf '%s\n' "$date_commands" | grep -qx '[0-9]*:1'; then
  pass "numbers:one-clock-read" "the poll's only date command is inside read_clock"
else
  failed "numbers:one-clock-read" "expected exactly one date command, inside read_clock, got line:in_helper=[$(printf '%s' "$date_commands" | tr '\n' ' ')]"
fi

# number_source_outcome <state_name> <pr_number> <max_watch> <interval> <seed> <padded>: a poll
# armed with <seed> over the steady pre-cycle-0 state, every clock reading zero-padded when
# <padded> is 1, as `<status>:<gh_calls>:<sleeps>:<out>`.
number_source_outcome() {
  local st out status
  st="$(new_state "$1")"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  [ "$6" -eq 0 ] || : > "$st/date.padded"
  out="$(run_poll "$st" "$OWNER" "$REPO_NAME" "$2" "$3" "$4" "$REVIEWER_FILTER" "$SELF_LOGIN" "$5")"
  status=$?
  printf '%s:%s:%s:%s' "$status" "$(gh_call_counts "$st")" "$(recorded_sleeps "$st")" \
    "$(printf '%s' "$out" | tr '\n' ';')"
}

# hostile_seed_outcome <state_name> <mode> <seed>: <mode> `poll` or `check` armed with <seed> over
# the steady pre-cycle-0 state, as `<status>:<gh_calls>:<out>`.
hostile_seed_outcome() {
  local st out status
  st="$(new_state "$1")"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_NONE"
  if [ "$2" = "poll" ]; then
    out="$(arm_poll "$st" "$3")"
  else
    out="$(run_check "$st" "$3")"
  fi
  status=$?
  printf '%s:%s:%s' "$status" "$(gh_call_counts "$st")" "$(printf '%s' "$out" | tr '\n' ';')"
}

if [ "$SEED_SUPPORTED" -eq 1 ]; then
  hostile_ok=1
  hostile_detail=""
  hostile_index=0
  for hostile_value in "$ARITH_PAYLOAD" abc -1 ""; do
    hostile_index=$((hostile_index + 1))
    for hostile_slot in pr window interval; do
      hostile_pr="$PR_NUMBER"
      hostile_window="$MAX_WATCH"
      hostile_interval="$POLL_INTERVAL"
      case "$hostile_slot" in
        pr) hostile_pr="$hostile_value" ;;
        window) hostile_window="$hostile_value" ;;
        interval) hostile_interval="$hostile_value" ;;
      esac
      hostile_outcome="$(number_source_outcome "hostile-$hostile_index-$hostile_slot" \
        "$hostile_pr" "$hostile_window" "$hostile_interval" "$SEED" 0)"
      if [ "$hostile_outcome" != "1:0 0 0::POLL_ERROR" ]; then
        hostile_ok=0
        hostile_detail="$hostile_detail $hostile_slot=[$hostile_value]: status:gh_calls:sleeps:out=$hostile_outcome"
      fi
    done
  done
  export hostile_failed_checks="$ARITH_PAYLOAD"
  hostile_seed="$(seed_with_failed_checks hostile_failed_checks)"
  for hostile_mode in poll check; do
    hostile_expected="1:0 0 0:POLL_ERROR"
    [ "$hostile_mode" = "poll" ] || hostile_expected="1:0 0 0:CHECK_ERROR"
    hostile_outcome="$(hostile_seed_outcome "hostile-seed-$hostile_mode" "$hostile_mode" \
      "$hostile_seed")"
    if [ "$hostile_outcome" != "$hostile_expected" ]; then
      hostile_ok=0
      hostile_detail="$hostile_detail seed/$hostile_mode: status:gh_calls:out=$hostile_outcome seed=$hostile_seed"
    fi
  done
  unset hostile_failed_checks
  if [ -e "$ARITH_CANARY" ]; then
    hostile_ok=0
    hostile_detail="$hostile_detail canary created: a reading was evaluated before its check"
  fi
  if [ "$hostile_ok" -eq 1 ]; then
    pass "numbers:no-source-evaluated-before-check" "a hostile, non-digit, negative or empty PR number, window, interval, seed failed_checks or clock reading fails closed with zero gh calls, and no reading is evaluated before its check"
  else
    failed "numbers:no-source-evaluated-before-check" "$hostile_detail"
  fi

  padded_expected="0:9,9,9,8,7,6,5,4,3,2,1:WATCH_TIMEOUT"
  plain_outcome="$(number_source_outcome padded-plain "$PR_NUMBER" 12 9 "$SEED" 0)"
  padded_outcome="$(number_source_outcome padded-zeros "00$PR_NUMBER" 0012 0009 \
    "$(seed_with_failed_checks 000)" 1)"
  if [ "$(cut -d: -f1,3- <<<"$plain_outcome")" = "$padded_expected" ] \
    && [ "$padded_outcome" = "$plain_outcome" ]; then
    pass "numbers:leading-zero-readings-behave-as-decimal" "zero-padded PR number, window, interval, seed failed_checks and clock readings give the unpadded poll's WATCH_TIMEOUT, exit 0 and sleeps 9,9,9,8,7,6,5,4,3,2,1"
  else
    failed "numbers:leading-zero-readings-behave-as-decimal" "expected status:sleeps:out=$padded_expected for both, got plain status:gh_calls:sleeps:out=$plain_outcome padded=$padded_outcome"
  fi

  count_ok=1
  count_detail=""
  for count_value in -1 1234567890123456789; do
    count_fixture="$(derive_fixture "bad-count$count_value" "$PRE" \
      ".data.repository.pullRequest.statusCheckRollup.contexts.checkRunCountsByState =
         [{\"state\":\"SUCCESS\",\"count\":1},{\"state\":\"FAILURE\",\"count\":$count_value}]")"
    if ! count_outcome="$(capture_fails_closed "bad-count$count_value" "$count_fixture" "" \
      "$SEED" "$REVIEWER_FILTER")"; then
      count_ok=0
      count_detail="$count_detail count=$count_value $count_outcome"
    fi
  done
  if [ "$count_ok" -eq 1 ]; then
    pass "numbers:bad-capture-count-fails-closed" "a FAILURE check count of -1 or 19 digits -> SNAPSHOT_ERROR / POLL_ERROR, exit 1"
  else
    failed "numbers:bad-capture-count-fails-closed" "$count_detail"
  fi
else
  skipped "numbers:no-source-evaluated-before-check" "$SKIP_REASON"
  skipped "numbers:leading-zero-readings-behave-as-decimal" "$SKIP_REASON"
  skipped "numbers:bad-capture-count-fails-closed" "$SKIP_REASON"
fi

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "change-detect-poll: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
