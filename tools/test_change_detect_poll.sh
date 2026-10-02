#!/usr/bin/env bash
#
# Behavioral unit runner for the thin PR change-detection poll (issue #324).
#
# OFFLINE bash TEST — CI-runnable with ONLY bash + jq present (NO tmux / gh / network). It drives:
#   plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh
# through a PATH-shim fake `gh` that serves canned fixture bytes from tests/change-detect-poll/.
# The REAL `jq` runs the script's REAL filters over those bytes, so the snapshot derivation under
# test is the production one — only the transport is faked.
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
# THE REVIEWER-IDENTITY CONTRACT (ADR-0033): every login / filter / approver decision is the
# shared `reviewer-identity.jq` registry's. The poll's approval scalar is true on EITHER a 👍 from
# a Bot-typed `pr-reaction-thumbs-up` registry member (Codex) OR a Bot-typed `review-approved`
# member (Copilot) whose latest review, as GitHub's per-author `latestReviews` reports it, is
# APPROVED, both scoped by the active filter, and surfaces as `REVIEWER_APPROVED`. The approval is
# read from `latestReviews`, never rebuilt from the bounded `reviews` history window. Reactions
# travel as one JSON object per +1 row, so a login carrying a delimiter byte cannot forge the
# account type. An empty filter slot defaults to `automated`.
#
# Usage:
#   ./tools/test_change_detect_poll.sh

set -u

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

# Poll args held fixed across cases. MAX_WATCH=3 / INTERVAL=1 yields three polls then
# WATCH_TIMEOUT, so every case terminates in ~3s and the whole suite stays well under a minute.
OWNER="hive-org"
REPO_NAME="hive-repo"
PR_NUMBER="4242"
MAX_WATCH=3
POLL_INTERVAL=1
REVIEWER_FILTER="codex-only"
SELF_LOGIN="hive-author"

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
# When the call carries `--jq`, the stub applies the script's OWN `--jq` expression to the entry
# with the real jq (`-r`, matching gh printing string results raw), so the production transport
# expression runs; a call without `--jq` serves the raw bytes.
STUB_BIN="$TMPDIR_TEST/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -u
kind=""
jq_expr=""
want_jq=0
for arg in "$@"; do
  if [ "$want_jq" -eq 1 ]; then
    jq_expr="$arg"
    want_jq=0
    continue
  fi
  case "$arg" in
    graphql) kind="graphql" ;;
    repos/*/reactions) kind="reactions" ;;
    --jq) want_jq=1 ;;
  esac
done
[ -n "$kind" ] || { echo "fake gh: unrecognized call: $*" >&2; exit 1; }
[ -n "${FAKE_GH_STATE_DIR:-}" ] || { echo "fake gh: FAKE_GH_STATE_DIR unset" >&2; exit 1; }
seq_file="$FAKE_GH_STATE_DIR/$kind.seq"
n_file="$FAKE_GH_STATE_DIR/$kind.n"
[ -f "$seq_file" ] || { echo "fake gh: no sequence for $kind" >&2; exit 1; }
n=$(cat "$n_file" 2>/dev/null || printf '0')
n=$((n + 1))
printf '%s' "$n" > "$n_file"
total=$(wc -l < "$seq_file")
[ "$n" -le "$total" ] || n="$total"
entry=$(sed -n "${n}p" "$seq_file")
[ "$entry" != "FAIL" ] || exit 1
# INVARIANT: gh stdout never carries CR; a core.autocrlf checkout of a fixture would otherwise
# carry CR into the bytes the script parses.
if [ -n "$jq_expr" ]; then
  tr -d '\r' < "$entry" | jq -r "$jq_expr"
else
  tr -d '\r' < "$entry"
fi
STUB
chmod +x "$STUB_BIN/gh"

# new_state <name>: fresh fake-gh state dir with zeroed call counters.
new_state() {
  local dir="$TMPDIR_TEST/state-$1"
  mkdir -p "$dir"
  printf '0' > "$dir/graphql.n"
  printf '0' > "$dir/reactions.n"
  printf '%s' "$dir"
}

# set_seq <state_dir> <graphql|reactions> <entry>...: the per-call fixture sequence.
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
# FAILED_CHECKS goes 0 -> 1. Keeps github-reviewer step 3 (failed-CI fix candidates) wired to a
# wake signal.
delta_checks="$(derive_fixture delta-checks "$PRE" \
  '.data.repository.pullRequest.statusCheckRollup.contexts.checkRunCountsByState =
     [{"state":"SUCCESS","count":2},{"state":"FAILURE","count":1}]')"
st="$(new_state deltachecks)"
set_seq "$st" graphql "$PRE" "$delta_checks"
set_seq "$st" reactions "$REACT_NONE"
out="$(arm_poll "$st" "$SEED")"
changed_count="$(printf '%s\n' "$out" | grep -cx 'CHANGED')"
if [ "$changed_count" -ge 1 ]; then
  pass "delta:failed-checks" "FAILED_CHECKS 0->1 fired CHANGED"
else
  failed "delta:failed-checks" "expected CHANGED, got=$(printf '%s' "$out" | tr '\n' ';')"
fi

# ── 4. Codex 👍 present at the first poll emits REVIEWER_APPROVED ────────────────────
# The reaction (a Bot-typed `chatgpt-codex-connector[bot]` +1 in a raw REST page) is
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

# ── 16. a User-typed 👍 NEVER approves ───────────────────────────────────────────────
# reactions-human.json carries a User-typed +1 whose login IS the Codex registry login, plus a
# User-typed `claude` +1. The registry's approver test is Bot-type gated, so neither may approve
# under `codex-only` OR under `all` — `all` admits every login to the filter, which isolates the
# approver type gate as the only thing standing between a human 👍 and a terminal `clean`.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  human_ok=1
  human_detail=""
  for human_filter in codex-only all; do
    human_seed="$(capture_seed "humanseed-$human_filter" initial "$PRE" "$REACT_NONE" "$human_filter")"
    st="$(new_state "humanpoll-$human_filter")"
    set_seq "$st" graphql "$PRE"
    set_seq "$st" reactions "$REACT_HUMAN"
    out="$(arm_poll "$st" "$human_seed" "$human_filter")"
    if [ "$out" != "WATCH_TIMEOUT" ]; then
      human_ok=0
      human_detail="$human_detail filter=$human_filter got=$(printf '%s' "$out" | tr '\n' ';') seed=$human_seed"
    fi
  done
  if [ "$human_ok" -eq 1 ]; then
    pass "approval:user-thumbs-up-never-approves" "User-typed 👍 stayed silent under codex-only and all"
  else
    failed "approval:user-thumbs-up-never-approves" "$human_detail"
  fi
else
  skipped "approval:user-thumbs-up-never-approves" "$SKIP_REASON"
fi

# ── 17. a Copilot APPROVED review fires under `automated`, NOT under `codex-only` ─────
# Copilot's registry approval kind is `review-approved`: a `latestReviews` entry in state APPROVED
# for the Bot-typed `copilot-pull-request-reviewer` is the approval signal, no reaction involved.
# The derived fixture adds that review to BOTH the `reviews` history and `latestReviews`, as GitHub
# reports a fresh approval. Under `automated`
# Copilot is in scope, so the first marker is REVIEWER_APPROVED. Under `codex-only` it is out of
# scope: the review still moves REVIEWS_TOTAL (CHANGED) but must never approve.
COPILOT_APPROVED="$(derive_fixture copilot-approved "$PRE" \
  '.data.repository.pullRequest.reviews.totalCount = 2
   | .data.repository.pullRequest.reviews.nodes += [{"databaseId":3011002,"state":"APPROVED","author":{"login":"copilot-pull-request-reviewer","__typename":"Bot"}}]
   | .data.repository.pullRequest.latestReviews.nodes += [{"state":"APPROVED","author":{"login":"copilot-pull-request-reviewer","__typename":"Bot"}}]')"
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  automated_seed="$(capture_seed copilotseed-automated initial "$PRE" "$REACT_NONE" automated)"
  st="$(new_state copilot-automated)"
  set_seq "$st" graphql "$PRE" "$COPILOT_APPROVED"
  set_seq "$st" reactions "$REACT_NONE"
  automated_out="$(arm_poll "$st" "$automated_seed" automated)"

  st="$(new_state copilot-codexonly)"
  set_seq "$st" graphql "$PRE" "$COPILOT_APPROVED"
  set_seq "$st" reactions "$REACT_NONE"
  codexonly_out="$(arm_poll "$st" "$SEED" codex-only)"

  if [ "$(printf '%s\n' "$automated_out" | head -1)" = "REVIEWER_APPROVED" ] \
    && ! printf '%s\n' "$codexonly_out" | grep -qx 'REVIEWER_APPROVED' \
    && printf '%s\n' "$codexonly_out" | grep -qx 'CHANGED'; then
    pass "approval:copilot-review-scoped-by-filter" "Copilot APPROVED fired under automated, only CHANGED under codex-only"
  else
    failed "approval:copilot-review-scoped-by-filter" "automated=$(printf '%s' "$automated_out" | tr '\n' ';') codex-only=$(printf '%s' "$codexonly_out" | tr '\n' ';')"
  fi
else
  skipped "approval:copilot-review-scoped-by-filter" "$SKIP_REASON"
fi

# ── 18. an EMPTY filter slot behaves as `automated` ──────────────────────────────────
# Over one mixed state — a Codex COMMENTED review, a Copilot APPROVED review, and a later
# User-typed human review — `automated`, `codex-only` and `all` each yield a DIFFERENT seed token
# (filtered review id and approval both move). The empty-slot token must equal the `automated`
# one, and the discrimination check proves the comparison could have failed. Behaviorally, an
# empty-slot arm then fires REVIEWER_APPROVED on the Copilot approval exactly as `automated` does.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  mixed_reviews="$(derive_fixture mixed-reviews "$COPILOT_APPROVED" \
    '.data.repository.pullRequest.reviews.totalCount = 3
     | .data.repository.pullRequest.reviews.nodes += [{"databaseId":3011003,"state":"COMMENTED","author":{"login":"octo-human","__typename":"User"}}]
     | .data.repository.pullRequest.latestReviews.nodes += [{"state":"COMMENTED","author":{"login":"octo-human","__typename":"User"}}]')"
  empty_token="$(capture_seed mixed-empty initial "$mixed_reviews" "$REACT_NONE" "")"
  automated_token="$(capture_seed mixed-automated initial "$mixed_reviews" "$REACT_NONE" automated)"
  codexonly_token="$(capture_seed mixed-codexonly initial "$mixed_reviews" "$REACT_NONE" codex-only)"
  all_token="$(capture_seed mixed-all initial "$mixed_reviews" "$REACT_NONE" all)"

  empty_seed="$(capture_seed emptyseed initial "$PRE" "$REACT_NONE" "")"
  st="$(new_state emptyfilterpoll)"
  set_seq "$st" graphql "$PRE" "$COPILOT_APPROVED"
  set_seq "$st" reactions "$REACT_NONE"
  empty_out="$(arm_poll "$st" "$empty_seed" "")"

  if [ -n "$empty_token" ] && [ "$empty_token" = "$automated_token" ] \
    && [ "$automated_token" != "$codexonly_token" ] && [ "$automated_token" != "$all_token" ] \
    && [ "$(printf '%s\n' "$empty_out" | head -1)" = "REVIEWER_APPROVED" ]; then
    pass "filter:empty-slot-is-automated" "empty-slot seed == automated seed (!= codex-only, != all); empty-slot arm fired REVIEWER_APPROVED"
  else
    failed "filter:empty-slot-is-automated" "empty=$empty_token automated=$automated_token codex-only=$codexonly_token all=$all_token poll=$(printf '%s' "$empty_out" | tr '\n' ';')"
  fi
else
  skipped "filter:empty-slot-is-automated" "$SKIP_REASON"
fi

# ── 19. a SUPERSEDED Copilot APPROVED review never approves ─────────────────────────
# Review approval is current state, not history: each approver is judged by its LATEST review,
# which is the state GitHub reports in its `latestReviews` entry. A Copilot APPROVED followed by a
# later Copilot CHANGES_REQUESTED, COMMENTED, or DISMISSED review (appended to `reviews`, and the
# `latestReviews` entry taking that later state) must not fire REVIEWER_APPROVED under
# `automated`, even on an `initial` arm (which surfaces any approval present when the watch
# starts). The later review still moves the filtered review id, so CHANGED fires. The reverse
# order (COMMENTED, then a later APPROVED) is the discrimination check: it must still fire, which
# proves the assertion could pass.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  stale_ok=1
  stale_detail=""
  for later_state in CHANGES_REQUESTED COMMENTED DISMISSED; do
    stale_fixture="$(derive_fixture "copilot-stale-$later_state" "$COPILOT_APPROVED" \
      ".data.repository.pullRequest.reviews.totalCount = 3
       | .data.repository.pullRequest.reviews.nodes += [{\"databaseId\":3011009,\"state\":\"$later_state\",\"author\":{\"login\":\"copilot-pull-request-reviewer\",\"__typename\":\"Bot\"}}]
       | .data.repository.pullRequest.latestReviews.nodes |= map(if .author.login == \"copilot-pull-request-reviewer\" then .state = \"$later_state\" else . end)")"
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
    '.data.repository.pullRequest.reviews.totalCount = 3
     | .data.repository.pullRequest.reviews.nodes += [
         {"databaseId":3011002,"state":"COMMENTED","author":{"login":"copilot-pull-request-reviewer","__typename":"Bot"}},
         {"databaseId":3011009,"state":"APPROVED","author":{"login":"copilot-pull-request-reviewer","__typename":"Bot"}}]
     | .data.repository.pullRequest.latestReviews.nodes += [{"state":"APPROVED","author":{"login":"copilot-pull-request-reviewer","__typename":"Bot"}}]')"
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
    pass "approval:superseded-review-never-approves" "stale Copilot APPROVED stayed silent after CHANGES_REQUESTED/COMMENTED/DISMISSED; a latest APPROVED still fired"
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
# The poll reads only the last 50 `reviews`; a busy PR pushes an approver's latest review out of
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
# A User-typed account whose login IS the Copilot registry login submits an APPROVED review that
# is its latest. Under `all` every login passes the filter, which isolates the approver's Bot-type
# gate as the only thing standing between that human review and a terminal `clean`. The review
# moves `REVIEWS_TOTAL`, so CHANGED fires.
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
# reactions-forged.json carries one User-typed +1 whose login is the Codex bot login followed by a
# TAB and `Bot`. A transport that joins login and type with a delimiter and splits them again
# reads that row as a Bot-typed Codex approval. The transport carries each row as a JSON object,
# so the login stays one value and the type stays User: no approval under `codex-only` OR `all`.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  forged_ok=1
  forged_detail=""
  for forged_filter in codex-only all; do
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
    pass "approval:reaction-login-cannot-forge-type" "delimiter-forged login stayed silent under codex-only and all"
  else
    failed "approval:reaction-login-cannot-forge-type" "$forged_detail"
  fi
else
  skipped "approval:reaction-login-cannot-forge-type" "$SKIP_REASON"
fi

# ── 26. a non-+1 reaction from the approver NEVER approves ───────────────────────────
# reactions-codex-eyes.json carries one Bot-typed Codex `eyes` reaction. Only a +1 is the Codex
# approval signal, so the poll idles to WATCH_TIMEOUT.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  st="$(new_state codex-eyes)"
  set_seq "$st" graphql "$PRE"
  set_seq "$st" reactions "$REACT_CODEX_EYES"
  out="$(arm_poll "$st" "$SEED")"
  if [ "$out" = "WATCH_TIMEOUT" ]; then
    pass "approval:eyes-reaction-never-approves" "Bot-typed Codex eyes reaction stayed silent"
  else
    failed "approval:eyes-reaction-never-approves" "expected only WATCH_TIMEOUT, got=$(printf '%s' "$out" | tr '\n' ';')"
  fi
else
  skipped "approval:eyes-reaction-never-approves" "$SKIP_REASON"
fi

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "change-detect-poll: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
