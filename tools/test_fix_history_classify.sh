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
# It also tests the reviewer identity registry the filter includes:
#   plugin/skills/github-review-loop/scripts/reviewer-identity.jq
# for registry integrity (unique ids, non-empty logins, approval kind in the closed enum) and for
# CLOSURE: no registry login and no `[bot]` strip literal may be inlined in a consumer script.
#
# Mirrors tools/test_shared_libs.sh's pass/fail counter + per-case assertion + exit-nonzero-on-any-
# fail convention. Read-only: the only writes are scratch files in a disposable tmpdir removed on EXIT.
#
# Usage:
#   ./tools/test_fix_history_classify.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
MODULE_DIR="$REPO_ROOT/plugin/skills/github-review-loop/scripts"
FILTER="$MODULE_DIR/fix-history-classify.jq"
IDENTITY_MODULE="$MODULE_DIR/reviewer-identity.jq"
FIX_DIR="$REPO_ROOT/tests/fix-history"

[ -f "$FILTER" ] || { echo "FAIL: filter under test missing: $FILTER" >&2; exit 2; }
[ -f "$IDENTITY_MODULE" ] || { echo "FAIL: identity module missing: $IDENTITY_MODULE" >&2; exit 2; }
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
# the expected canonical JSON. `-L "$MODULE_DIR"` resolves the filter's `include "reviewer-identity"`.
# A jq failure (filter error / invalid fixture / unresolved include) fails the case loudly.
run_case() {
  local case_name="$1" fixture="$2" login="$3" filt="$4" expected="$5"
  local path="$FIX_DIR/$fixture"
  if [ ! -f "$path" ]; then
    failed "$case_name" "fixture missing: $path"
    return
  fi
  local actual
  if ! actual="$(jq -c -L "$MODULE_DIR" -f "$FILTER" --arg login "$login" --arg filter "$filt" < "$path" | canon)"; then
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
# Non-self thread comment whose OWN body carries `Fixed in <40hex>.` → handled. The thread carries
# NO self disposition at all (empty self-disposition timeline), so the marker branch is isolated.
run_case "case01:handled-by-marker" "case01-handled-by-marker.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case01aaaaaaaaaaaa","id":"PRRC_case01comment100","databaseId":100,"url":null,"classification":"handled"}]'

# ── Case 2: handled-by-id-ordering ───────────────────────────────────────────────
# Non-self comment (id 200) with no marker; a later self `Fixed in <SHA>.` reply (id 201) is the
# thread's latest disposition {kind:"fix", id:201}. 200 <= 201 → handled via the coverage branch.
# The self reply is not emitted as a candidate.
run_case "case02:handled-by-id-ordering" "case02-handled-by-id-ordering.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case02bbbbbbbbbbbb","id":"PRRC_case02comment200","databaseId":200,"url":null,"classification":"handled"}]'

# ── Case 3: followup-after-fix ───────────────────────────────────────────────────
# Thread whose latest disposition is a FIX (id 301). Comment 300 predates it (<= 301 → handled);
# comment 302 post-dates it (> 301, no marker, governing kind "fix" → followup-after-fix). Exercises
# both the coverage branch and the kind→label map in one thread.
run_case "case03:followup-after-fix" "case03-followup-after-fix.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case03cccccccccccc","id":"PRRC_case03comment300","databaseId":300,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case03cccccccccccc","id":"PRRC_case03comment302","databaseId":302,"url":null,"classification":"followup-after-fix"}]'

# ── Case 4: no-self-fix thread ───────────────────────────────────────────────────
# Non-self comment, NO self disposition in the thread → the timeline is empty and the governing
# disposition is null. A real databaseId (400) has no marker. Because the thread was never disposed
# of, this is a FIRST-TIME finding → actionable. It is NOT followup-after-fix: that label requires a
# governing disposition of kind "fix" for the comment to post-date.
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

# ── Case 8: a bot-suffixed Bot sharing the self login is NOT self ────────────────
# Self identity is a User-typed author whose RAW login equals --arg login (module `is_self`); the
# `[bot]` strip never applies to it. A Bot-typed `selfuser[bot]` therefore stays a non-self author
# under `all`: it is emitted, its own `Fixed in <SHA>.` body marks IT handled (801), and it
# contributes NO self disposition, so the codex finding before it (800) is a first-time finding on a
# never-disposed thread → actionable. Under the superseded login-only key the stripped `selfuser`
# read as self: 801 became a fix disposition, 800 was absolved, and 801 was dropped.
run_case "case08:bot-suffixed-bot-not-self" "case08-bot-normalization.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case08ffffffffffff","id":"PRRC_case08comment800","databaseId":800,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case08ffffffffffff","id":"PRRC_case08comment801","databaseId":801,"url":null,"classification":"handled"}]'

# ── Case 9: reviewer_filter — codex-only vs all on one payload ────────────────────
# Same payload, two filters. codex-only matches ONLY the Bot-typed chatgpt-codex-connector (900). all
# matches any non-self author (900 + the User-typed human reviewer 901). Every author node carries
# `__typename` because the registry modes require a Bot-typed author. No self disposition on the thread → both are
# FIRST-TIME findings on a never-disposed thread → actionable (per case 4).
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
# One unresolved thread, NO self fix-reply, one self DEFER reply whose body STARTS with the machine
# sentinel `<!-- hivemind-defer-v1 -->` (id 1201) → the governing disposition is
# {kind:"defer", id:1201}. The sentinel is the whole machine record; the `Deferred to <home>.`
# prose that follows it is display text the filter never reads. Three assertions in one thread:
#   1200 non-self, BEFORE the defer reply (1200 <= 1201) → handled. This is the durability
#        guarantee: the deferred finding stays handled even if the thread's resolve mutation failed,
#        so the loop cannot re-raise it and post a duplicate defer reply.
#   1202 non-self, AFTER the defer reply (1202 > 1201) → actionable, NOT followup-after-fix: a
#        deferral is not a fix, so a post-defer re-raise is not cycling evidence (the kind→label map
#        sends a governing "defer" to actionable).
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
# `<!-- hivemind-defer-v1 -->` at BYTE 0 of a SELF-authored body contributes a defer disposition. One
# unresolved thread, NO self fix-reply, and THREE bodies that each look like a deferral but are not:
#   1301 SELF, plain prose `Deferred to <url>. Tracked separately.` with NO sentinel. Under the old
#        prose match this alone would contribute a defer disposition at id 1301.
#   1302 SELF, a Markdown QUOTE of a real defer reply: the `> ` prefix pushes the sentinel off byte
#        0, so `startswith` rejects it. A `contains`-style read would accept it and contribute a
#        defer disposition at id 1302.
#   1303 NON-SELF, sentinel at BYTE 0 (FORGERY GUARD): the sentinel is read ONLY off the
#        self-authored arm, so a reviewer cannot mint handled status by pasting the constant.
# Because the self-disposition timeline stays EMPTY, the original reviewer finding 1300 is a
# FIRST-TIME finding on a never-disposed thread → actionable, and the forged 1303 → actionable. The
# two SELF comments are stripped by matches_filter and emit no record. Either regression (prose
# fallback, or a non-anchored/non-self-scoped sentinel read) flips 1300 to handled and fails here.
run_case "case13:defer-prose-not-marker" "case13-defer-prose-not-marker.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case13jjjjjjjjjjjj","id":"PRRC_case13comment1300","databaseId":1300,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case13jjjjjjjjjjjj","id":"PRRC_case13comment1303","databaseId":1303,"url":null,"classification":"actionable"}]'

# ── Case 14: fix THEN defer — the later deferral governs ─────────────────────────
# DISCRIMINATING (this case fails under the superseded two-maxima cascade). One unresolved thread
# whose self-disposition timeline is [{fix,1401}, {defer,1403}]; the LATEST disposition is the
# DEFER at 1403, so it alone governs every comment in the thread:
#   1400 non-self, before both dispositions (1400 <= 1403) → handled.
#   1402 non-self, between them (1402 <= 1403) → handled. Note the governing element is the defer,
#        not the fix it post-dates — coverage is decided once against the latest disposition.
#   1404 non-self, after both (1404 > 1403), governing kind "defer" → actionable. A deferral is not
#        a fix, so a re-raise after it is NOT cycling evidence.
# The superseded cascade maxed the two kinds INDEPENDENTLY and tested the fix arm first, so a
# comment past both ids hit `fix > 0 and dbid > fix` and was mislabelled followup-after-fix even
# though the thread's most recent disposition was a deferral. 1404 is the byte that catches it.
run_case "case14:fix-then-defer-latest-governs" "case14-fix-defer-interleaved.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case14kkkkkkkkkkkk","id":"PRRC_case14comment1400","databaseId":1400,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case14kkkkkkkkkkkk","id":"PRRC_case14comment1402","databaseId":1402,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case14kkkkkkkkkkkk","id":"PRRC_case14comment1404","databaseId":1404,"url":null,"classification":"actionable"}]'

# ── Case 15: defer THEN fix — the later fix governs (symmetry lock) ──────────────
# NOT DISCRIMINATING: this case passes under BOTH the current latest-disposition model and the
# superseded two-maxima cascade, because the fix is the later disposition and the old cascade tested
# the fix arm first — the two models happen to agree on this ordering. It is kept deliberately as
# the SYMMETRY half of case 14: it pins that reversing the two dispositions reverses the verdict on
# the trailing comment, so a future "simplification" that hard-codes defer-always-wins (or
# fix-always-wins) breaks exactly one of the pair. Timeline [{defer,1501}, {fix,1503}], latest = fix:
#   1500 non-self (1500 <= 1503) → handled.
#   1502 non-self (1502 <= 1503) → handled.
#   1504 non-self (1504 > 1503), governing kind "fix" → followup-after-fix: a re-raise after our most
#        recent fix IS cycling evidence, even though the thread also carries an earlier deferral.
run_case "case15:defer-then-fix-latest-governs" "case15-defer-then-fix.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case15llllllllllll","id":"PRRC_case15comment1500","databaseId":1500,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case15llllllllllll","id":"PRRC_case15comment1502","databaseId":1502,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case15llllllllllll","id":"PRRC_case15comment1504","databaseId":1504,"url":null,"classification":"followup-after-fix"}]'

# ── Case 16: two fix rounds THEN a defer ─────────────────────────────────────────
# DISCRIMINATING. The multi-round shape a real cycling thread takes: timeline
# [{fix,1601}, {fix,1603}, {defer,1605}], latest = the DEFER at 1605.
#   1600 / 1602 / 1604 non-self, all <= 1605 → handled. 1604 is the interesting one: it post-dates
#        BOTH fix-replies yet is still covered, because coverage is decided against the single
#        latest disposition, not per-round.
#   1606 non-self (1606 > 1605), governing kind "defer" → actionable.
# Under the superseded cascade the two fix ids maxed to 1603 and the defer to 1605, and the fix arm
# was consulted first, so 1606 was labelled followup-after-fix — the loop would have read a
# post-DEFERRAL re-raise as evidence that our FIX was cycling.
run_case "case16:two-fix-rounds-then-defer" "case16-two-rounds-then-defer.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case16mmmmmmmmmmmm","id":"PRRC_case16comment1600","databaseId":1600,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case16mmmmmmmmmmmm","id":"PRRC_case16comment1602","databaseId":1602,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case16mmmmmmmmmmmm","id":"PRRC_case16comment1604","databaseId":1604,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case16mmmmmmmmmmmm","id":"PRRC_case16comment1606","databaseId":1606,"url":null,"classification":"actionable"}]'

# ── Case 17: terminal defer, nothing after it ────────────────────────────────────
# NOT DISCRIMINATING (both models agree): the thread ENDS on our own defer reply, so no non-self
# comment post-dates the governing disposition and the kind→label map is never consulted. Timeline
# [{fix,1701}, {defer,1702}], latest = defer at 1702; the only non-self comment 1700 <= 1702 →
# handled. Kept as the terminal-state lock for the DURABILITY guarantee: a thread we fixed and then
# deferred emits exactly ONE record and it is handled — the loop cannot re-raise the finding and
# post a duplicate defer reply, even when the thread's resolve mutation failed (resolve is
# non-blocking by design). Both self replies are stripped by matches_filter.
run_case "case17:terminal-defer-no-later-comment" "case17-fix-then-defer-no-later-comment.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case17nnnnnnnnnnnn","id":"PRRC_case17comment1700","databaseId":1700,"url":null,"classification":"handled"}]'

# ── Case 18: one self body carrying BOTH markers — the tie resolves to DEFER ─────
# DISCRIMINATING. A single SELF reply (1801) whose body STARTS with the defer sentinel AND mentions
# `Fixed in abc1234.` later in its prose — a partial deferral. BOTH extraction arms fire on the same
# comment, so the timeline is [{fix,1801}, {defer,1801}]: two elements with the SAME id. sort_by is
# stable and the fix arm is concatenated BEFORE the defer arm, so `last` deterministically picks the
# DEFER — the conservative tie-break.
#   1800 non-self (1800 <= 1801) → handled.
#   1802 non-self (1802 > 1801), governing kind "defer" → actionable. The conservative outcome: a
#        re-raise after an ambiguous partial deferral stays a plain finding rather than being
#        escalated as cycling/regression evidence.
# The superseded cascade produced fix == defer == 1801 and consulted the fix arm first, so 1802 was
# labelled followup-after-fix. This case also pins the tie-break DIRECTION: swapping the two
# concatenated arms in the filter flips 1802 back to followup-after-fix and fails here.
run_case "case18:both-markers-one-body-tie" "case18-both-markers-one-body.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case18oooooooooooo","id":"PRRC_case18comment1800","databaseId":1800,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case18oooooooooooo","id":"PRRC_case18comment1802","databaseId":1802,"url":null,"classification":"actionable"}]'

# ── Case 19: registry filter modes over every reviewer identity class ────────────
# One unresolved thread, no self disposition, so every emitted record is a FIRST-TIME actionable
# finding and the assertions isolate WHICH authors each filter mode admits:
#   1900 chatgpt-codex-connector Bot      registry (codex)
#   1901 copilot-pull-request-reviewer Bot registry (copilot, GraphQL spelling)
#   1902 Copilot Bot                      registry (copilot, REST spelling)
#   1903 claude Bot                       registry (claude)
#   1904 claude User                      HUMAN sharing the claude login; the Bot gate excludes it
#   1905 dependabot Bot                   Bot outside the registry
#   1906 github-actions Bot               Bot deliberately excluded from the registry (generic CI)
#   1907 human-reviewer User              human
#   1908 selfuser User                    self; stripped by every mode
# automated → exactly the four registry Bot records. codex-only → 1900 only. all → every non-self
# author (1900..1907). The legacy `<login>` mode stays type-agnostic: `claude` selects both the Bot
# (1903) and the human User (1904).
run_case "case19:automated-registry-bots-only" "case19-automated-reviewers.json" "selfuser" "automated" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1900","databaseId":1900,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1901","databaseId":1901,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1902","databaseId":1902,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1903","databaseId":1903,"url":null,"classification":"actionable"}]'
run_case "case19:codex-only" "case19-automated-reviewers.json" "selfuser" "codex-only" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1900","databaseId":1900,"url":null,"classification":"actionable"}]'
run_case "case19:all-non-self" "case19-automated-reviewers.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1900","databaseId":1900,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1901","databaseId":1901,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1902","databaseId":1902,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1903","databaseId":1903,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1904","databaseId":1904,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1905","databaseId":1905,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1906","databaseId":1906,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1907","databaseId":1907,"url":null,"classification":"actionable"}]'
run_case "case19:legacy-login-type-agnostic" "case19-automated-reviewers.json" "selfuser" "claude" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1903","databaseId":1903,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1904","databaseId":1904,"url":null,"classification":"actionable"}]'

# ── Case 20: self identity is User type + login, never login alone ───────────────
# The viewer runs as the human User `claude`; the Claude app Bot's bare login is also `claude`.
# Self is ONLY the User-typed `claude` (module `is_self`). Four unresolved threads plus top-level:
#   T1 2000 claude Bot finding → emitted (registry Bot), first-time → actionable. A login-only self
#        key dropped it.
#   T2 FORGERY: 2010 codex finding; 2011 claude Bot `Fixed in abc1234.`; 2012 claude Bot with the
#        defer sentinel at byte 0. Neither Bot reply is a self disposition, so 2010 → actionable;
#        2011 → handled by its OWN body marker; 2012 → actionable (the sentinel is never read off a
#        non-self body).
#   T3 REAL SELF: 2020 codex; 2021 claude User `Fixed in abc1234.` (self fix disposition, not
#        emitted); 2022 codex post-fix → 2020 handled, 2022 followup-after-fix.
#   T4 NULL TYPE: 2030 codex; 2031 claude with NO __typename `Fixed in abc1234.`. A null type is never
#        self, so no disposition → 2030 actionable. 2031 is not Bot-typed, so `automated` omits it;
#        `all` emits it, handled by its own body marker.
#   Top-level: 2041 claude Bot `Addresses: <2040>` is not a self harvest, so 2040 → actionable and
#        2041 itself → actionable (a registry Bot comment); 2043 claude User `Addresses: <2042>` is
#        the self harvest → 2042 handled, 2043 not emitted.
run_case "case20:self-identity-automated" "case20-self-identity-login-collision.json" "claude" "automated" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2040","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2040","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2041","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2041","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2042","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2042","classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq1","id":"PRRC_case20comment2000","databaseId":2000,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2010","databaseId":2010,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2011","databaseId":2011,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2012","databaseId":2012,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq3","id":"PRRC_case20comment2020","databaseId":2020,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq3","id":"PRRC_case20comment2022","databaseId":2022,"url":null,"classification":"followup-after-fix"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq4","id":"PRRC_case20comment2030","databaseId":2030,"url":null,"classification":"actionable"}]'
run_case "case20:self-identity-all" "case20-self-identity-login-collision.json" "claude" "all" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2040","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2040","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2041","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2041","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2042","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2042","classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq1","id":"PRRC_case20comment2000","databaseId":2000,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2010","databaseId":2010,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2011","databaseId":2011,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2012","databaseId":2012,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq3","id":"PRRC_case20comment2020","databaseId":2020,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq3","id":"PRRC_case20comment2022","databaseId":2022,"url":null,"classification":"followup-after-fix"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq4","id":"PRRC_case20comment2030","databaseId":2030,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq4","id":"PRRC_case20comment2031","databaseId":2031,"url":null,"classification":"handled"}]'

# ── Registry integrity ───────────────────────────────────────────────────────────
# Each rule is a jq predicate over a registry ARRAY on its input, evaluated with the module
# included (so `approval_kinds` resolves). It must hold for the real `automated_reviewers` AND be
# FALSE for a synthetic registry that breaks exactly that rule, proving the predicate bites.

# registry_rule <case> <jq-predicate-over-registry-array> <violating-registry-json>
registry_rule() {
  local case_name="$1" predicate="$2" bad_registry="$3"
  if ! jq -n -e -L "$MODULE_DIR" "include \"reviewer-identity\"; automated_reviewers | ($predicate)" >/dev/null 2>&1; then
    failed "$case_name" "real registry violates: $predicate"
    return
  fi
  if jq -n -e -L "$MODULE_DIR" --argjson reg "$bad_registry" "include \"reviewer-identity\"; \$reg | ($predicate)" >/dev/null 2>&1; then
    failed "$case_name" "predicate did not reject violating registry: $bad_registry"
    return
  fi
  pass "$case_name" "real registry holds; violating registry rejected"
}

registry_rule "registry:non-empty" \
  'type == "array" and length > 0' \
  '[]'
registry_rule "registry:ids-unique-non-empty" \
  '[.[].id] | all(.[]; type == "string" and length > 0) and length == (unique | length)' \
  '[{"id":"codex","logins":["a"],"approval":null},{"id":"codex","logins":["b"],"approval":null}]'
registry_rule "registry:logins-non-empty-strings" \
  'all(.[]; (.logins | type == "array" and length > 0) and all(.logins[]; type == "string" and length > 0))' \
  '[{"id":"codex","logins":[],"approval":null}]'
registry_rule "registry:logins-unique-across-entries" \
  '[.[].logins[]] | length == (unique | length)' \
  '[{"id":"a","logins":["x"],"approval":null},{"id":"b","logins":["x"],"approval":null}]'
registry_rule "registry:logins-stored-stripped" \
  'all(.[].logins[]; endswith("[bot]") | not)' \
  '[{"id":"codex","logins":["chatgpt-codex-connector[bot]"],"approval":null}]'
registry_rule "registry:approval-in-enum-or-null" \
  'approval_kinds as $kinds | all(.[]; .approval == null or (.approval as $kind | any($kinds[]; . == $kind)))' \
  '[{"id":"codex","logins":["a"],"approval":"thumbs-up"}]'

# ── CLOSURE: no inlined identity literal in a consumer ───────────────────────────
# Every registry login (derived from the module, never hard-coded here) and the `[bot]` strip
# literal must live ONLY in reviewer-identity.jq. A consumer that inlines either is a second source
# of truth the registry cannot govern.
#
# Matching choice:
#   - logins: `grep -wF` — fixed-string, CASE-SENSITIVE, whole-word. Case-sensitivity keeps the
#     current `${CLAUDE_PLUGIN_ROOT}` path refs green while `claude` / `Copilot` are caught; the
#     whole-word bound (hyphen is a non-word char, so hyphenated logins match as a unit) catches the
#     login in ANY syntactic form — `== "claude"`, `"Copilot"`, a bare bash `= claude` — not only
#     a quoted jq literal. Prose mentioning a login in these files also trips it; that is
#     intentional, as the module header is the one place the identity semantics are described.
#   - strip literal: ERE `\[bot\\*\]` — matches `[bot]` with zero or more backslashes before the
#     closing bracket, so it catches the bare `[bot]` text AND both the jq-escaped `\\[bot\\]` and
#     single-escaped `\[bot\]` regex spellings.
# Both matchers are proven to bite against a scratch canary carrying each forbidden construct, and
# proven not to over-match the legitimate constructs these files contain today.
CLOSURE_TARGETS=(
  "$MODULE_DIR/fix-history-classify.jq"
  "$MODULE_DIR/prefilter.sh"
  "$MODULE_DIR/fetch-normalize.sh"
  "$REPO_ROOT/plugin/skills/_shared/fetch-normalize-core.sh"
  "$MODULE_DIR/pr-change-detect-poll.sh"
)
BOT_STRIP_ERE='\[bot\\*\]'

REGISTRY_LOGINS=()
if registry_logins_text="$(jq -n -r -L "$MODULE_DIR" 'include "reviewer-identity"; automated_reviewers[].logins[]')"; then
  while IFS= read -r registry_login; do
    [ -n "$registry_login" ] && REGISTRY_LOGINS+=("$registry_login")
  done <<< "$registry_logins_text"
fi

# print_closure_hits <file>
# Print every hit of a registry login or the `[bot]` strip literal in <file>, one per line, as
# `login=<login>:<lineno>:<text>` or `bot-strip:<lineno>:<text>`.
print_closure_hits() {
  local target="$1" login
  for login in "${REGISTRY_LOGINS[@]}"; do
    grep -nwF -- "$login" "$target" | sed "s/^/login=$login:/"
  done
  grep -nE -- "$BOT_STRIP_ERE" "$target" | sed 's/^/bot-strip:/'
  return 0
}

if [ "${#REGISTRY_LOGINS[@]}" -eq 0 ]; then
  failed "closure:logins-derived" "no logins derived from $IDENTITY_MODULE (closure would be vacuous)"
else
  pass "closure:logins-derived" "${#REGISTRY_LOGINS[@]} registry logins derived from the module"

  CANARY_HIT="$WORKDIR/closure-canary-hit.jq"
  for registry_login in "${REGISTRY_LOGINS[@]}"; do
    printf 'select(.author.login == "%s")\n' "$registry_login"
  done > "$CANARY_HIT"
  printf '%s\n' 'sub("\\[bot\\]$"; "")' 'test("\[bot\]$")' '# strips the [bot] suffix' >> "$CANARY_HIT"
  canary_lines="$(wc -l < "$CANARY_HIT" | tr -d ' ')"
  canary_hit_lines="$(print_closure_hits "$CANARY_HIT" | cut -d: -f2 | sort -un | wc -l | tr -d ' ')"
  if [ "$canary_hit_lines" = "$canary_lines" ]; then
    pass "closure:canary-bites" "every one of $canary_lines forbidden canary lines detected"
  else
    failed "closure:canary-bites" "detected $canary_hit_lines of $canary_lines forbidden canary lines"
  fi

  CANARY_CLEAN="$WORKDIR/closure-canary-clean.sh"
  printf '%s\n' '# ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/prefilter.sh' \
    'REVIEWER_FILTER="codex-only"' 'include "reviewer-identity";' > "$CANARY_CLEAN"
  canary_clean_hits="$(print_closure_hits "$CANARY_CLEAN")"
  if [ -z "$canary_clean_hits" ]; then
    pass "closure:canary-no-overmatch" "legitimate constructs produce no closure hit"
  else
    failed "closure:canary-no-overmatch" "false-positive closure hits:
$canary_clean_hits"
  fi

  for closure_target in "${CLOSURE_TARGETS[@]}"; do
    closure_rel="${closure_target#"$REPO_ROOT"/}"
    if [ ! -f "$closure_target" ]; then
      failed "closure:$closure_rel" "closure target missing"
      continue
    fi
    closure_hits="$(print_closure_hits "$closure_target")"
    if [ -z "$closure_hits" ]; then
      pass "closure:$closure_rel" "no inlined registry login or [bot] strip literal"
    else
      failed "closure:$closure_rel" "inlined identity literal(s):
$closure_hits"
    fi
  done
fi

# ── CLOSURE: no login-only self compare in a consumer ────────────────────────────
# Self identity is the module's `is_self` (User type + raw login). A consumer that compares an
# author login straight against the `$login` (SELF_LOGIN) --arg — `select($a == $login)`,
# `strip_bot(.author.login) != $login` — re-derives self on login alone, so a Bot sharing the
# viewer's bare login reads as self. Any `==` / `!=` with `$login` as either operand is a hit; the
# word bound after `$login` keeps a longer variable name (`$login_x`) out. `$login` passed as an
# argument (`--arg login`, `is_self(...; $login)`, the matches_filter wrapper) is not a compare.
# RESIDUAL: rebinding the --arg to another variable (`$login as $me | ... == $me`) evades this
# matcher; the behavioural cases (8, 20) are the guard for that shape.
SELF_COMPARE_ERE='(==|!=)[[:space:]]*\$login([^A-Za-z0-9_]|$)|\$login[[:space:]]*(==|!=)'

# print_self_compare_hits <file>
# Print every login-only self compare in <file> as `<lineno>:<text>`, one per line.
print_self_compare_hits() {
  grep -nE -- "$SELF_COMPARE_ERE" "$1"
  return 0
}

SELF_CANARY_HIT="$WORKDIR/self-compare-canary-hit.jq"
printf '%s\n' '| select($a == $login)' '| map(select(strip_bot(.author.login) != $login))' \
  'select($login == .x)' > "$SELF_CANARY_HIT"
self_canary_lines="$(wc -l < "$SELF_CANARY_HIT" | tr -d ' ')"
self_canary_hit_lines="$(print_self_compare_hits "$SELF_CANARY_HIT" | cut -d: -f1 | sort -un | wc -l | tr -d ' ')"
if [ "$self_canary_hit_lines" = "$self_canary_lines" ]; then
  pass "self-compare:canary-bites" "every one of $self_canary_lines forbidden canary lines detected"
else
  failed "self-compare:canary-bites" "detected $self_canary_hit_lines of $self_canary_lines forbidden canary lines"
fi

SELF_CANARY_CLEAN="$WORKDIR/self-compare-canary-clean.sh"
printf '%s\n' 'jq -r -L "$SCRIPT_DIR" --arg login "$SELF_LOGIN" --arg filter "$REVIEWER_FILTER"' \
  '| select(is_self(.author.login; .author.__typename; $login))' \
  'def matches_filter($a; $t): reviewer_matches_filter($a; $t; $login; $filter);' > "$SELF_CANARY_CLEAN"
self_canary_clean_hits="$(print_self_compare_hits "$SELF_CANARY_CLEAN")"
if [ -z "$self_canary_clean_hits" ]; then
  pass "self-compare:canary-no-overmatch" "legitimate \$login uses produce no self-compare hit"
else
  failed "self-compare:canary-no-overmatch" "false-positive self-compare hits:
$self_canary_clean_hits"
fi

for closure_target in "${CLOSURE_TARGETS[@]}"; do
  closure_rel="${closure_target#"$REPO_ROOT"/}"
  if [ ! -f "$closure_target" ]; then
    failed "self-compare:$closure_rel" "closure target missing"
    continue
  fi
  self_compare_hits="$(print_self_compare_hits "$closure_target")"
  if [ -z "$self_compare_hits" ]; then
    pass "self-compare:$closure_rel" "no login-only self compare"
  else
    failed "self-compare:$closure_rel" "login-only self compare(s); route through is_self:
$self_compare_hits"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "fix-history-classify: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
