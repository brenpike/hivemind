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
# THE SEED PROBE: the planned fix adds a `--snapshot` mode emitting a `BASELINE=<8 pipe-separated
# fields>` token captured BEFORE cycle 0, passed back as a REQUIRED 8th positional arg to poll mode.
# The suite PROBES the script under test for `--snapshot` support rather than assuming it:
#   - ABSENT  → cases run against the legacy 7-arg form; the seed-contract cases SKIP visibly.
#   - PRESENT → the seed is captured at the pre-cycle-0 state and passed as arg 8; the
#               seed-contract cases RUN.
# Post-merge the probe doubles as a regression guard: if seed support ever disappears, the
# bite-proof case goes red again instead of silently passing.
#
# HARNESS-ASSUMED SEED CONTRACT (asserted, not guessed silently): snapshot mode is invoked as
#   pr-change-detect-poll.sh --snapshot <OWNER> <REPO> <PR> <MAX_WATCH> <INTERVAL> <FILTER> <SELF>
# and emits one `BASELINE=<value>` line; the BARE <value> (no `BASELINE=` label) is arg 8 of poll
# mode. Snapshot failure emits `SNAPSHOT_ERROR` and exits 1.
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
REACT_NONE="$FIXTURES/reactions-none.txt"
REACT_CODEX="$FIXTURES/reactions-codex.txt"

# ── PATH-shim fake gh ───────────────────────────────────────────────────────────────
# Serves a per-call fixture from a state dir: <kind>.seq lists one fixture path per line and
# <kind>.n is the call counter; call N serves line N, clamping to the last line so a steady
# state can be served indefinitely. The literal entry `FAIL` makes the call exit non-zero
# (a gh transport failure). `graphql` responses are raw GraphQL JSON piped into the script's
# real jq filter; the reactions entry is the post-`--jq` stdout gh itself would emit.
STUB_BIN="$TMPDIR_TEST/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -u
kind=""
for arg in "$@"; do
  case "$arg" in
    graphql) kind="graphql"; break ;;
    repos/*/reactions) kind="reactions"; break ;;
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
cat "$entry"
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

# arm_poll <state_dir> [seed]: poll mode with the standard 7 args, appending <seed> as the
# required 8th arg when non-empty (empty seed = legacy form on the unfixed script).
arm_poll() {
  local dir="$1" seed="${2:-}"
  if [ -n "$seed" ]; then
    run_poll "$dir" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" "$POLL_INTERVAL" \
      "$REVIEWER_FILTER" "$SELF_LOGIN" "$seed"
  else
    run_poll "$dir" "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" "$POLL_INTERVAL" \
      "$REVIEWER_FILTER" "$SELF_LOGIN"
  fi
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
  seed_state="$(new_state seed)"
  set_seq "$seed_state" graphql "$PRE"
  set_seq "$seed_state" reactions "$REACT_NONE"
  SEED_RAW="$(run_poll "$seed_state" --snapshot "$OWNER" "$REPO_NAME" "$PR_NUMBER" \
    "$MAX_WATCH" "$POLL_INTERVAL" "$REVIEWER_FILTER" "$SELF_LOGIN")"
  SEED="$(printf '%s\n' "$SEED_RAW" | sed -n 's/^BASELINE=//p' | head -1)"
fi
SKIP_REASON="script under test has no --snapshot seed support (pre-fix baseline contract)"

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
   | .data.repository.pullRequest.comments.nodes += [{"databaseId":2411003,"author":{"login":"chatgpt-codex-connector"}}]')"
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

# ── 4. Codex 👍 present at the first poll emits CODEX_APPROVED ───────────────────────
# The reaction is present for every poll while the pre-cycle-0 seed state carried none. Legacy
# arm: the baseline poll's pre-existing-approval special case fires. Seeded arm: false -> true
# against the seed fires. Either way the FIRST emitted marker is CODEX_APPROVED — an approval
# that lands in the blind window must not idle the loop to WATCH_TIMEOUT.
st="$(new_state codex)"
set_seq "$st" graphql "$PRE"
set_seq "$st" reactions "$REACT_CODEX"
out="$(arm_poll "$st" "$SEED")"
first_line="$(printf '%s\n' "$out" | head -1)"
if [ "$first_line" = "CODEX_APPROVED" ]; then
  pass "codex:approved-on-first-poll" "CODEX_APPROVED emitted on the first poll"
else
  failed "codex:approved-on-first-poll" "expected CODEX_APPROVED first, got=$(printf '%s' "$out" | tr '\n' ';')"
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
# A seed that is not the emitted 8-field token must be rejected outright rather than parsed into
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
# One `BASELINE=` line carrying exactly 8 pipe-separated fields — the eight scalars the poll
# diffs (state, three id tokens, three totals, failed checks) plus nothing else to parse.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  field_count=0
  [ -z "$SEED" ] || field_count="$(printf '%s' "$SEED" | awk -F'|' '{print NF}')"
  baseline_lines="$(printf '%s\n' "$SEED_RAW" | grep -c '^BASELINE=')"
  if [ "$baseline_lines" -eq 1 ] && [ "$field_count" -eq 8 ]; then
    pass "snapshot:baseline-well-formed" "one BASELINE= line, 8 pipe-separated fields"
  else
    failed "snapshot:baseline-well-formed" "baseline_lines=$baseline_lines fields=$field_count raw=$(printf '%s' "$SEED_RAW" | tr '\n' ';')"
  fi
else
  skipped "snapshot:baseline-well-formed" "$SKIP_REASON"
fi

# ── 8. --snapshot on a gh failure fails CLOSED ──────────────────────────────────────
# A seed that cannot be captured must be loud: SNAPSHOT_ERROR + exit 1, never an empty token the
# caller would pass on as a valid baseline.
if [ "$SEED_SUPPORTED" -eq 1 ]; then
  st="$(new_state snapfail)"
  set_seq "$st" graphql FAIL
  set_seq "$st" reactions FAIL
  out="$(run_poll "$st" --snapshot "$OWNER" "$REPO_NAME" "$PR_NUMBER" "$MAX_WATCH" \
    "$POLL_INTERVAL" "$REVIEWER_FILTER" "$SELF_LOGIN")"
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

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "change-detect-poll: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
