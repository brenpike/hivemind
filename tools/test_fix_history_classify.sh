#!/usr/bin/env bash
#
# Behavioral unit runner for the fix-history classification filter (issue #198, STEP-002).
#
# PURE jq TEST — CI-runnable with ONLY jq present (NO tmux / claude / gh / network). It runs the
# single-source-of-truth classification predicate:
#   plugin/skills/github-review-loop/scripts/fix-history-classify.jq
# over fixed GraphQL-payload fixtures under tests/fix-history/, and asserts the emitted classified
# stream equals an expected set. The filter is a PURE function of stdin + --arg login/--arg filter,
# so every case is deterministic and offline.
#
# Mirrors tools/test_shared_libs.sh's pass/fail counter + per-case assertion + exit-nonzero-on-any-
# fail convention. Read-only: the only writes are scratch files in a disposable tmpdir removed on EXIT.
#
# Usage:
#   ./tools/test_fix_history_classify.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
FILTER="$REPO_ROOT/plugin/skills/github-review-loop/scripts/fix-history-classify.jq"
FIX_DIR="$REPO_ROOT/tests/fix-history"

[ -f "$FILTER" ] || { echo "FAIL: filter under test missing: $FILTER" >&2; exit 2; }
[ -d "$FIX_DIR" ] || { echo "FAIL: fixture dir missing: $FIX_DIR" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this suite" >&2; exit 2; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-fix-history.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# Canonicalize a classified stream into a single deterministic line: slurp the stream into an
# array, sort by the fields that disambiguate every record (databaseId, url, surface,
# classification), and emit compact JSON. Ordering noise across surfaces or thread nodes can never
# flake the comparison. An empty stream canonicalizes to "[]".
canon() {
  jq -s -c 'sort_by((.databaseId // -1), (.url // ""), (.thread_id // ""), .surface, .classification)'
}

# run_case <case> <fixture-basename> <login> <filter> <expected-canonical-json>
# Feed the fixture through the filter with the given args, canonicalize, and exact-match against
# the expected canonical JSON. A jq failure (filter error / invalid fixture) fails the case loudly.
run_case() {
  local case_name="$1" fixture="$2" login="$3" filt="$4" expected="$5"
  local path="$FIX_DIR/$fixture"
  if [ ! -f "$path" ]; then
    failed "$case_name" "fixture missing: $path"
    return
  fi
  local actual
  if ! actual="$(jq -cf "$FILTER" --arg login "$login" --arg filter "$filt" < "$path" | canon)"; then
    failed "$case_name" "jq filter failed on fixture $fixture (login=$login filter=$filt)"
    return
  fi
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "($fixture login=$login filter=$filt)"
  else
    failed "$case_name" "($fixture login=$login filter=$filt)
    expected: $expected
    actual:   $actual"
  fi
}

# ── Case 1: handled-by-marker ────────────────────────────────────────────────────
# Non-self thread comment whose OWN body carries `Fixed in <40hex>.` → handled. No self fix-reply
# exists in the thread (latest_self_fix_id sentinel 0), so the marker branch is isolated.
run_case "case01:handled-by-marker" "case01-handled-by-marker.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case01aaaaaaaaaaaa","id":"PRRC_case01comment100","databaseId":100,"url":null,"classification":"handled"}]'

# ── Case 2: handled-by-id-ordering ───────────────────────────────────────────────
# Non-self comment (id 200) with no marker; a later self `Fixed in <SHA>.` reply (id 201) sets
# latest_self_fix_id=201. 200 <= 201 → handled via the id-ordering branch. The self reply is not
# emitted as a candidate.
run_case "case02:handled-by-id-ordering" "case02-handled-by-id-ordering.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case02bbbbbbbbbbbb","id":"PRRC_case02comment200","databaseId":200,"url":null,"classification":"handled"}]'

# ── Case 3: followup-after-fix ───────────────────────────────────────────────────
# Thread with a self fix-reply (id 301). Comment 300 predates it (<= 301 → handled); comment 302
# post-dates it (> 301, no marker → followup-after-fix). Exercises both branches in one thread.
run_case "case03:followup-after-fix" "case03-followup-after-fix.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case03cccccccccccc","id":"PRRC_case03comment300","databaseId":300,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case03cccccccccccc","id":"PRRC_case03comment302","databaseId":302,"url":null,"classification":"followup-after-fix"}]'

# ── Case 4: no-self-fix thread ───────────────────────────────────────────────────
# Non-self comment, NO self fix-reply in the thread → latest_self_fix_id sentinel 0. A real
# databaseId (400) has no marker. Because no self fix-reply exists (latest_self_fix_id == 0), this
# is a FIRST-TIME finding on a never-fixed thread → actionable. It is NOT followup-after-fix:
# followup-after-fix requires a prior self fix-reply (latest_self_fix_id > 0) to post-date.
run_case "case04:no-self-fix-thread" "case04-no-self-fix-thread.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case04dddddddddddd","id":"PRRC_case04comment400","databaseId":400,"url":null,"classification":"actionable"}]'

# ── Case 5: thread-overflow ──────────────────────────────────────────────────────
# comments.totalCount (50) > fetched nodes length (1) → thread_overflow=true forces classification
# actionable filter-blind, EVEN for a comment whose body carries a fix marker. Because the thread is
# unresolved AND overflowed it ALSO emits the per-thread overflow SENTINEL (databaseId:null), so the
# stream is BOTH the per-comment record (500) AND the sentinel — both actionable, both project to
# DISPATCH/candidate. canon sorts the null-databaseId sentinel (// -1) before 500.
run_case "case05:thread-overflow" "case05-thread-overflow.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":true,"thread_id":"PRRT_case05eeeeeeeeeeee","id":null,"databaseId":null,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":true,"thread_id":"PRRT_case05eeeeeeeeeeee","id":"PRRC_case05comment500","databaseId":500,"url":null,"classification":"actionable"}]'

# ── Case 6: top-level EYES-reacted / not ────────────────────────────────────────
# A non-thread toplevel comment node with a self EYES reaction (viewerHasReacted:true) → handled;
# a node whose EYES reaction has viewerHasReacted:false (or carries no EYES reaction) → actionable.
run_case "case06:toplevel-addressed" "case06-toplevel-addressed.json" "selfuser" "all" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase06comment600","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-600","classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase06comment601","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-601","classification":"actionable"}]'

# ── Case 7: review summaries ─────────────────────────────────────────────────────
# CHANGES_REQUESTED/COMMENTED review node with a self EYES reaction (viewerHasReacted:true) →
# handled; non-reacted → actionable; APPROVED and DISMISSED emit NO record.
run_case "case07:review-summary" "case07-review-summary.json" "selfuser" "all" \
  '[{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase07review700","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-700","classification":"handled"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase07review701","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-701","classification":"actionable"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase07review702","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-702","classification":"actionable"}]'

# ── Case 8: [bot] normalization ──────────────────────────────────────────────────
# A self author login carrying a trailing `[bot]` suffix (selfuser[bot]) normalizes to selfuser →
# treated as self, so its `Fixed in <SHA>.` sets latest_self_fix_id and it is NOT emitted. The
# non-self comment (id 800 <= 801) → handled. Exactly one record.
run_case "case08:bot-normalization" "case08-bot-normalization.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case08ffffffffffff","id":"PRRC_case08comment800","databaseId":800,"url":null,"classification":"handled"}]'

# ── Case 9: reviewer_filter — codex-only vs all on one payload ────────────────────
# Same payload, two filters. codex-only matches ONLY chatgpt-codex-connector (900). all matches any
# non-self author (900 + the human reviewer 901). No self fix-reply (latest_self_fix_id sentinel 0)
# → both are FIRST-TIME findings on a never-fixed thread → actionable (per case 4).
run_case "case09:reviewer-filter-codex-only" "case09-reviewer-filter.json" "selfuser" "codex-only" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case09gggggggggggg","id":"PRRC_case09comment900","databaseId":900,"url":null,"classification":"actionable"}]'
run_case "case09:reviewer-filter-all" "case09-reviewer-filter.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case09gggggggggggg","id":"PRRC_case09comment900","databaseId":900,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case09gggggggggggg","id":"PRRC_case09comment901","databaseId":901,"url":null,"classification":"actionable"}]'

# ── Case 10: thread-overflow, ZERO visible matching comment ──────────────────────
# An UNRESOLVED thread with comments.totalCount (50) > visible nodes whose ONLY visible node is
# SELF-authored (selfuser) → matches_filter strips it, so the per-comment loop emits NOTHING. The
# older unaddressed finding sits OUTSIDE the fetched page. Without the per-thread sentinel this
# thread would emit ZERO records and silently lose the overflow actionable signal. The filter must
# emit EXACTLY the thread-level overflow sentinel (databaseId:null, classification:actionable) and
# no spurious record — preserving main's unconditional-ACTIONABLE fail-open for oversized threads.
run_case "case10:thread-overflow-no-visible-match" "case10-thread-overflow-no-visible-match.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":true,"thread_id":"PRRT_case10hhhhhhhhhhhh","id":null,"databaseId":null,"url":null,"classification":"actionable"}]'

# ── Case 11: legacy `Addresses:` handled marker WITHOUT an EYES reaction ─────────
# Backward-compat: a PR processed by the PRE-reaction workflow carries a durable
# self-authored `Addresses: <url>` top-level comment but NO EYES reaction on the
# addressed nodes (the EYES marker did not yet exist). The legacy harvest must keep
# classifying those nodes handled so restart/upgrade does not re-dispatch already-
# fixed non-thread feedback. The non-self toplevel comment whose url is harvested
# (issuecomment-111), with empty reactionGroups → handled via the legacy fallback;
# the unaddressed toplevel (issuecomment-112) → actionable; the review summary whose
# url is harvested, also with no EYES → handled via the legacy fallback. The self
# `Addresses:` comment is not emitted.
run_case "case11:legacy-addresses-no-eyes" "case11-legacy-addresses-no-eyes.json" "selfuser" "all" \
  '[{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase11review113","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-111","classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase11comment111","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-111","classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase11comment112","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-112","classification":"actionable"}]'

# ── Case 12: self defer reply as a durable handled marker ────────────────────────
# One unresolved thread, NO self fix-reply (latest_self_fix_id sentinel 0), one self DEFER reply
# whose body STARTS with the machine sentinel `<!-- hivemind-defer-v1 -->` (id 1201) →
# latest_self_defer_id=1201. The sentinel is the whole machine record; the `Deferred to <home>.`
# prose that follows it is display text the filter never reads. Three assertions in one thread:
#   1200 non-self, BEFORE the defer reply (1200 <= 1201) → handled. This is the durability
#        guarantee: the deferred finding stays handled even if the thread's resolve mutation failed,
#        so the loop cannot re-raise it and post a duplicate defer reply.
#   1202 non-self, AFTER the defer reply (1202 > 1201) → actionable, NOT followup-after-fix: a
#        deferral is not a fix, so a post-defer re-raise on a defer-ONLY thread is not cycling
#        evidence (followup-after-fix requires latest_self_fix_id > 0).
#   1203 non-self whose OWN body carries the defer PROSE `Deferred to https://x/1.` but NOT the
#        sentinel → actionable (PROSE-IS-NOT-A-MARKER guard). It sits AFTER the self defer reply
#        precisely so the id-ordering handled arm cannot absolve it; the only thing that could turn
#        it handled is its own body. If prose matching ever returned to the body tests, 1203 alone
#        would flip to handled while 1202 stayed actionable — making that regression directly
#        observable. The self-only forgery guard (a reviewer body carrying the sentinel at byte 0)
#        is asserted by case 13.
# The self defer reply (1201) is stripped by matches_filter and emits no record.
run_case "case12:deferred-marker" "case12-deferred-marker.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case12iiiiiiiiiiii","id":"PRRC_case12comment1200","databaseId":1200,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case12iiiiiiiiiiii","id":"PRRC_case12comment1202","databaseId":1202,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case12iiiiiiiiiiii","id":"PRRC_case12comment1203","databaseId":1203,"url":null,"classification":"actionable"}]'

# ── Case 13: defer PROSE / QUOTED sentinel is NOT a defer marker ─────────────────
# Regression lock for the pre-sentinel prose match: only the EXACT constant
# `<!-- hivemind-defer-v1 -->` at BYTE 0 of a SELF-authored body sets latest_self_defer_id. One
# unresolved thread, NO self fix-reply, and THREE bodies that each look like a deferral but are not:
#   1301 SELF, plain prose `Deferred to <url>. Tracked separately.` with NO sentinel. Under the old
#        prose match this alone would set latest_self_defer_id=1301.
#   1302 SELF, a Markdown QUOTE of a real defer reply: the `> ` prefix pushes the sentinel off byte
#        0, so `startswith` rejects it. A `contains`-style read would accept it and set
#        latest_self_defer_id=1302.
#   1303 NON-SELF, sentinel at BYTE 0 (FORGERY GUARD): the sentinel is read ONLY off the
#        self-authored arm, so a reviewer cannot mint handled status by pasting the constant.
# Because latest_self_defer_id stays at its sentinel 0, the original reviewer finding 1300 is a
# FIRST-TIME finding on a never-handled thread → actionable, and the forged 1303 → actionable. The
# two SELF comments are stripped by matches_filter and emit no record. Either regression (prose
# fallback, or a non-anchored/non-self-scoped sentinel read) flips 1300 to handled and fails here.
run_case "case13:defer-prose-not-marker" "case13-defer-prose-not-marker.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case13jjjjjjjjjjjj","id":"PRRC_case13comment1300","databaseId":1300,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case13jjjjjjjjjjjj","id":"PRRC_case13comment1303","databaseId":1303,"url":null,"classification":"actionable"}]'

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "fix-history-classify: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
