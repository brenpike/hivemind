#!/usr/bin/env bash
#
# Behavioral unit runner for the fix-history classification filter (issue #198, STEP-002).
#
# PURE jq TEST — CI-runnable with ONLY jq present (NO tmux / claude / gh / network). It runs the
# single-source-of-truth classification predicate:
#   plugin/skills/github-review-loop/scripts/fix-history-classify.jq
# over fixed GraphQL-payload fixtures under tests/fix-history/, and asserts the emitted classified
# stream equals an expected set. The filter is a PURE function of stdin + --arg login/--arg filter/
# --arg reviewers, so every case is deterministic and offline.
#
# It also tests the reviewer identity module the filter includes:
#   plugin/skills/github-review-loop/scripts/reviewer-identity.jq
# through truth tables for each of its defs (configured-reviewer parsing, case folding, the
# github-actions rule, the Bot gate on configured logins, the filter modes, review approval, settled
# threads, the retired filter value), and for CLOSURE: no `[bot]` strip literal and no login-only self compare may
# be inlined in a consumer script, no known reviewer product login may appear in the module or a
# consumer, `github-actions` may appear only in the module, and the retired-filter literal may appear
# only on the module's `is_retired_filter` line. The consumers these closure checks read are the
# CLOSURE_TARGETS: fix-history-classify.jq, prefilter.sh, fetch-normalize.sh,
# _shared/fetch-normalize-core.sh, pr-change-detect-poll.sh, react-marker.sh and merge-approved.sh.
#
# Mirrors tools/test_shared_libs.sh's pass/fail counter + per-case assertion + exit-nonzero-on-any-
# fail convention. Read-only: the only writes are scratch files in a disposable tmpdir removed on EXIT.
#
# Usage:
#   ./tools/test_fix_history_classify.sh

set -u

# The suite passes every configured-reviewer value explicitly; an inherited setting must not leak in.
unset HIVEMIND_PR_REVIEWERS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
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

make_scratch_dir WORKDIR "${TMPDIR:-/tmp}/hivemind-fix-history.XXXXXX"
cleanup() { rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# Canonicalize a classified stream into a single deterministic line: slurp the stream into an
# array, sort by the fields that disambiguate every record (databaseId, url, surface,
# classification), and emit compact JSON. Ordering noise across surfaces or thread nodes can never
# flake the comparison. An empty stream canonicalizes to "[]".
canon() {
  jq -s -c 'sort_by((.databaseId // -1), (.url // ""), (.thread_id // ""), .surface, .classification)'
}

# run_case <case> <fixture-basename> <login> <filter> <expected-canonical-json> [reviewers]
# Feed the fixture through the filter with the given args, canonicalize, and exact-match against
# the expected canonical JSON. [reviewers] is the raw configured-reviewer value (default empty).
# `-L "$MODULE_DIR"` resolves the filter's `include "reviewer-identity"`.
# A jq failure (filter error / invalid fixture / unresolved include) fails the case loudly.
run_case() {
  local case_name="$1" fixture="$2" login="$3" filt="$4" expected="$5" reviewers="${6:-}"
  local path="$FIX_DIR/$fixture"
  if [ ! -f "$path" ]; then
    failed "$case_name" "fixture missing: $path"
    return
  fi
  local actual
  if ! actual="$(jq -c -L "$MODULE_DIR" -f "$FILTER" --arg login "$login" --arg filter "$filt" \
      --arg reviewers "$reviewers" < "$path" | canon)"; then
    failed "$case_name" "jq filter failed on fixture $fixture (login=$login filter=$filt reviewers=$reviewers)"
    return
  fi
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "($fixture login=$login filter=$filt reviewers=$reviewers)"
  else
    failed "$case_name" "($fixture login=$login filter=$filt reviewers=$reviewers)
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
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase06comment600","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-600","last_edited_at":null,"classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase06comment601","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-601","last_edited_at":null,"classification":"actionable"}]'

# ── Case 7: review summaries ─────────────────────────────────────────────────────
# CHANGES_REQUESTED/COMMENTED review node with a self EYES reaction (viewerHasReacted:true) →
# handled; non-reacted → actionable; APPROVED and DISMISSED emit NO record.
run_case "case07:review-summary" "case07-review-summary.json" "selfuser" "all" \
  '[{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase07review700","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-700","last_edited_at":null,"classification":"handled"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase07review701","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-701","last_edited_at":null,"classification":"actionable"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase07review702","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-702","last_edited_at":null,"classification":"actionable"}]'

# ── Case 8: a bot-suffixed Bot sharing the self login is NOT self ────────────────
# Self identity is a User-typed author whose RAW login equals --arg login (module `is_self`); the
# `[bot]` strip never applies to it. A Bot-typed `selfuser[bot]` therefore stays a non-self author
# under `all`: it is emitted, its own `Fixed in <SHA>.` body marks IT handled (801), and it
# contributes NO self disposition, so the codex finding before it (800) is a first-time finding on a
# never-disposed thread → actionable. Under the superseded login-only key the stripped `selfuser`
# read as self: 801 became a fix disposition, 800 was absolved, and 801 was dropped.
run_case "case08:bot-suffixed-bot-not-self" "case08-bot-normalization.json" "selfuser" "all" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case08ffffffffffff","id":"PRRC_case08comment800","databaseId":800,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case08ffffffffffff","id":"PRRC_case08comment801","databaseId":801,"url":null,"classification":"handled"}]'

# ── Case 9: reviewer_filter — automated vs all on one payload ─────────────────────
# Same payload, two filters. automated matches ONLY the Bot-typed chatgpt-codex-connector (900): its
# review-thread comment makes it an Automated Reviewer, while the User-typed human reviewer (901) fails
# the Bot gate. all matches any non-self author (900 + 901). No self disposition on the thread → both
# are FIRST-TIME findings on a never-disposed thread → actionable (per case 4).
run_case "case09:reviewer-filter-automated" "case09-reviewer-filter.json" "selfuser" "automated" \
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
  '[{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase11review113","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-111","last_edited_at":null,"classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase11comment111","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-111","last_edited_at":null,"classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase11comment112","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-112","last_edited_at":null,"classification":"actionable"}]'

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

# ── Case 19: filter modes over every reviewer identity class ─────────────────────
# One unresolved thread, no self disposition, so every emitted thread record is a FIRST-TIME
# actionable finding and the assertions isolate WHICH authors each filter mode admits:
#   1900 chatgpt-codex-connector Bot       review-thread author → Automated Reviewer
#   1901 copilot-pull-request-reviewer Bot review-thread author → Automated Reviewer
#   1902 Copilot Bot                       review-thread author (mixed case) → Automated Reviewer
#   1903 claude Bot                        review-thread author → Automated Reviewer
#   1904 claude User                       HUMAN sharing the claude login; the Bot gate excludes it
#   1905 dependabot Bot                    top-level comment only, no review: a status bot, out
#   1906 github-actions Bot                review-thread author, but the generic CI identity: out
#                                          unless configured
#   1907 human-reviewer User               human
#   1908 selfuser User                     self; stripped by every mode
# automated → 1900..1903. automated with github-actions configured → also 1906. all → every non-self
# author (1900..1907). The `<login>` mode stays type-agnostic: `claude` selects both the Bot (1903)
# and the human User (1904).
run_case "case19:automated-review-bots-only" "case19-automated-reviewers.json" "selfuser" "automated" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1900","databaseId":1900,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1901","databaseId":1901,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1902","databaseId":1902,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1903","databaseId":1903,"url":null,"classification":"actionable"}]'
run_case "case19:automated-github-actions-configured" "case19-automated-reviewers.json" "selfuser" "automated" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1900","databaseId":1900,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1901","databaseId":1901,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1902","databaseId":1902,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1903","databaseId":1903,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1906","databaseId":1906,"url":null,"classification":"actionable"}]' \
  "github-actions"
run_case "case19:all-non-self" "case19-automated-reviewers.json" "selfuser" "all" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase19comment1905","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-1905","last_edited_at":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1900","databaseId":1900,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1901","databaseId":1901,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1902","databaseId":1902,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1903","databaseId":1903,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1904","databaseId":1904,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1906","databaseId":1906,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1907","databaseId":1907,"url":null,"classification":"actionable"}]'
run_case "case19:login-type-agnostic" "case19-automated-reviewers.json" "selfuser" "claude" \
  '[{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1903","databaseId":1903,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case19pppppppppppp","id":"PRRC_case19comment1904","databaseId":1904,"url":null,"classification":"actionable"}]'

# ── Case 20: self identity is User type + login, never login alone ───────────────
# The viewer runs as the human User `claude`; the Claude app Bot's bare login is also `claude`.
# Self is ONLY the User-typed `claude` (module `is_self`). Four unresolved threads plus top-level:
#   T1 2000 claude Bot finding → emitted (an Automated Reviewer through its review-thread comment),
#        first-time → actionable. A login-only self key dropped it.
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
#        2041 itself → actionable (an Automated Reviewer's comment); 2043 claude User `Addresses: <2042>` is
#        the self harvest → 2042 handled, 2043 not emitted.
run_case "case20:self-identity-automated" "case20-self-identity-login-collision.json" "claude" "automated" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2040","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2040","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2041","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2041","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2042","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2042","last_edited_at":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq1","id":"PRRC_case20comment2000","databaseId":2000,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2010","databaseId":2010,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2011","databaseId":2011,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2012","databaseId":2012,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq3","id":"PRRC_case20comment2020","databaseId":2020,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq3","id":"PRRC_case20comment2022","databaseId":2022,"url":null,"classification":"followup-after-fix"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq4","id":"PRRC_case20comment2030","databaseId":2030,"url":null,"classification":"actionable"}]'
run_case "case20:self-identity-all" "case20-self-identity-login-collision.json" "claude" "all" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2040","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2040","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2041","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2041","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase20comment2042","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2042","last_edited_at":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq1","id":"PRRC_case20comment2000","databaseId":2000,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2010","databaseId":2010,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2011","databaseId":2011,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq2","id":"PRRC_case20comment2012","databaseId":2012,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq3","id":"PRRC_case20comment2020","databaseId":2020,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq3","id":"PRRC_case20comment2022","databaseId":2022,"url":null,"classification":"followup-after-fix"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq4","id":"PRRC_case20comment2030","databaseId":2030,"url":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case20qqqqqqqqqqq4","id":"PRRC_case20comment2031","databaseId":2031,"url":null,"classification":"handled"}]'

# ── Case 25: our EYES mark handles noise from every reviewer, no reviewer-specific code ──
# Three no-finding notices, each with our EYES mark (viewerHasReacted:true) and a self EYES reaction
# node at 12:00:00Z, none edited after the mark:
#   2500 Codex Bot top-level "no major issues", lastEditedAt null (never edited). Codex is an
#        Automated Reviewer through its THUMBS_UP on the PR object.
#   2501 status Bot, top-level only, edited at 11:59:59Z (one second before the mark).
#   2502 Copilot Bot COMMENTED review "generated no comments", edited at 11:30:00Z.
# all → all three handled. automated → the Automated Reviewers 2500 and 2502 handled; 2501 has no
# review and no THUMBS_UP, so the filter does not emit it.
run_case "case25:noise-marked-bots-all" "case25-noise-marked-bots.json" "selfuser" "all" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase25comment2500","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2500","last_edited_at":null,"classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase25comment2501","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2501","last_edited_at":"2026-11-10T11:59:59Z","classification":"handled"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase25review2502","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-2502","last_edited_at":"2026-11-10T11:30:00Z","classification":"handled"}]'
run_case "case25:noise-marked-bots-automated" "case25-noise-marked-bots.json" "selfuser" "automated" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase25comment2500","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2500","last_edited_at":null,"classification":"handled"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase25review2502","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-2502","last_edited_at":"2026-11-10T11:30:00Z","classification":"handled"}]'

# ── Case 26: a mark stops counting once the node is edited at or after it ────────
# Every node is by a human User and carries an EYES group with viewerHasReacted:true unless stated;
# the self EYES reaction node is at 12:00:00Z unless stated. Each must be actionable except 2608 and
# 2609:
#   2600 edited 12:05:00Z, after the mark.
#   2601 edited 12:00:00Z, the same second as the mark (strict compare).
#   2602 edited 12:05:00Z; only ANOTHER user's EYES (12:10:00Z) is newer than the edit.
#   2603 no lastEditedAt key at all.
#   2604 lastEditedAt `2026-11-10T11:00:00.000Z`: earlier as a string, but not the second-precision
#        format, so it is rejected.
#   2605 edited 11:00:00Z; the only self reaction time `2026-11-10T12:00:00+00:00` is malformed and
#        ignored, so there is no mark time.
#   2606 COMMENTED review edited 12:05:00Z, after the mark.
#   2607 lastEditedAt null and a self reaction node, but viewerHasReacted:false.
#   2608 edited 11:59:59Z, before the mark → handled.
#   2609 COMMENTED review edited 11:59:59Z, before the mark → handled.
#   2610 edited 12:05:00Z; the newer EYES (12:10:00Z) is by a Bot sharing the self login, not self.
#   2611 edited 11:00:00Z with `reactions` a string: the gate is total and reads not handled.
#   2612 lastEditedAt a number: not a time string → not handled.
run_case "case26:marked-then-edited" "case26-marked-then-edited.json" "selfuser" "all" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2600","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2600","last_edited_at":"2026-11-10T12:05:00Z","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2601","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2601","last_edited_at":"2026-11-10T12:00:00Z","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2602","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2602","last_edited_at":"2026-11-10T12:05:00Z","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2603","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2603","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2604","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2604","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2605","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2605","last_edited_at":"2026-11-10T11:00:00Z","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2607","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2607","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2608","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2608","last_edited_at":"2026-11-10T11:59:59Z","classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2610","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2610","last_edited_at":"2026-11-10T12:05:00Z","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2611","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2611","last_edited_at":"2026-11-10T11:00:00Z","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase26comment2612","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2612","last_edited_at":null,"classification":"actionable"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase26review2606","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-2606","last_edited_at":"2026-11-10T12:05:00Z","classification":"actionable"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase26review2609","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-2609","last_edited_at":"2026-11-10T11:59:59Z","classification":"handled"}]'

# ── Case 26b: the read version is carried as last_edited_at ──────────────────────
# A toplevel/review record carries the node's lastEditedAt as fetched: 2600 (edited 12:05:00Z)
# carries that time, 2607 (never edited, lastEditedAt null) carries null.
read_version_expected='[{"id":"IC_kwDOcase26comment2600","last_edited_at":"2026-11-10T12:05:00Z"},{"id":"IC_kwDOcase26comment2607","last_edited_at":null}]'
if read_version_actual="$(jq -c -L "$MODULE_DIR" -f "$FILTER" --arg login selfuser --arg filter all \
    --arg reviewers "" < "$FIX_DIR/case26-marked-then-edited.json" \
    | jq -s -c '[.[] | select(.id == "IC_kwDOcase26comment2600" or .id == "IC_kwDOcase26comment2607")
                 | {id, last_edited_at}] | sort_by(.id)')"; then
  if [ "$read_version_actual" = "$read_version_expected" ]; then
    pass "case26b:read-version-carried" "(edited node carries its time, never-edited node null)"
  else
    failed "case26b:read-version-carried" "
    expected: $read_version_expected
    actual:   $read_version_actual"
  fi
else
  failed "case26b:read-version-carried" "jq filter failed on fixture case26-marked-then-edited.json"
fi

# ── Case 27: reviewer parity — no product gets its own rule ──────────────────────
# Three reviewer Bots of different product shapes (chatgpt-codex-connector, base 2700;
# copilot-pull-request-reviewer, base 2710; a generic acme-review-bot, base 2720) each leave the same
# items at the same offsets from their base:
#   +0 thread finding, +1 self `Fixed in <SHA>.`, +2 follow-up → +0 handled, +2 followup-after-fix.
#   +3 unmarked top-level finding → actionable. +5 top-level notice with our unedited EYES → handled.
#   +4 unmarked COMMENTED review → actionable. +6 APPROVED review → no record.
# automated and all give the same stream, and the parity check asserts the three per-bot projections
# (offset, surface, classification) are identical.
CASE27_EXPECTED='[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase27comment2703","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2703","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase27comment2705","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2705","last_edited_at":null,"classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase27comment2713","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2713","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase27comment2715","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2715","last_edited_at":null,"classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase27comment2723","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2723","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase27comment2725","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2725","last_edited_at":null,"classification":"handled"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase27review2704","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-2704","last_edited_at":null,"classification":"actionable"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase27review2714","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-2714","last_edited_at":null,"classification":"actionable"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase27review2724","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-2724","last_edited_at":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case27rrrrrrrrrrr1","id":"PRRC_case27comment2700","databaseId":2700,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case27rrrrrrrrrrr1","id":"PRRC_case27comment2702","databaseId":2702,"url":null,"classification":"followup-after-fix"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case27rrrrrrrrrrr2","id":"PRRC_case27comment2710","databaseId":2710,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case27rrrrrrrrrrr2","id":"PRRC_case27comment2712","databaseId":2712,"url":null,"classification":"followup-after-fix"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case27rrrrrrrrrrr3","id":"PRRC_case27comment2720","databaseId":2720,"url":null,"classification":"handled"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case27rrrrrrrrrrr3","id":"PRRC_case27comment2722","databaseId":2722,"url":null,"classification":"followup-after-fix"}]'
run_case "case27:reviewer-parity-automated" "case27-reviewer-parity.json" "selfuser" "automated" "$CASE27_EXPECTED"
run_case "case27:reviewer-parity-all" "case27-reviewer-parity.json" "selfuser" "all" "$CASE27_EXPECTED"
if parity_groups="$(printf '%s' "$CASE27_EXPECTED" | jq -c '
    map((.databaseId // (.url | sub("^.*[-#]"; "") | tonumber)) as $n
        | {bot: (($n - 2700) / 10 | floor), row: [($n % 10), .surface, .classification]})
    | group_by(.bot) | map(map(.row) | sort) | unique | length')" && [ "$parity_groups" = "1" ]; then
  pass "case27:per-bot-projection-identical" "three reviewer shapes classify identically"
else
  failed "case27:per-bot-projection-identical" "per-bot projections differ (distinct groups: ${parity_groups:-error})"
fi

# ── Case 28: what makes a Bot an Automated Reviewer ──────────────────────────────
# Evidence rows are review authors, review-thread comment authors, per-author latest review authors
# and THUMBS_UP reactors on the PR object; HIVEMIND_PR_REVIEWERS adds to them.
#   2800 coverage-bot Bot, top-level only: a status bot with no review and no THUMBS_UP → out.
#   2801 thumbs-bot Bot, admitted by its THUMBS_UP on the PR object alone → actionable.
#   2802 github-actions Bot COMMENTED review (also in latestReviews) → out unless configured.
#   2803 plain-bot Bot, top-level only → out unless configured.
#   2804 review-bot Bot review-thread finding → actionable.
#   2805 plain-bot User (a human holding the configured login) → out even when configured.
#   2806 eyes-bot Bot whose only PR reaction is EYES, never evidence → out.
#   2807 latest-bot Bot, evidenced by its latestReviews entry alone → actionable.
# The THUMBS_UP group also holds a User reactor (human-fan), which the Bot gate drops.
# Configured `PLAIN-bot[bot], github-actions` (mixed case, suffix, comma and space) adds 2802 and 2803
# without removing the evidence bots 2801, 2804 and 2807.
run_case "case28:evidence-default" "case28-reviewer-evidence.json" "selfuser" "automated" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase28comment2801","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2801","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase28comment2807","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2807","last_edited_at":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case28ssssssssssss","id":"PRRC_case28comment2804","databaseId":2804,"url":null,"classification":"actionable"}]'
run_case "case28:evidence-configured" "case28-reviewer-evidence.json" "selfuser" "automated" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase28comment2801","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2801","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase28comment2803","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2803","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase28comment2807","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2807","last_edited_at":null,"classification":"actionable"},{"surface":"review","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"PRR_kwDOcase28review2802","databaseId":null,"url":"https://github.com/o/r/pull/1#pullrequestreview-2802","last_edited_at":null,"classification":"actionable"},{"surface":"thread","thread_resolved":false,"thread_overflow":false,"thread_id":"PRRT_case28ssssssssssss","id":"PRRC_case28comment2804","databaseId":2804,"url":null,"classification":"actionable"}]' \
  "PLAIN-bot[bot], github-actions"

# ── Case 29: retired Codex summary markers carry no meaning ──────────────────────
# Codex is an Automated Reviewer through its THUMBS_UP. Each top-level comment starts with the old
# summary marker and carries an old state comment; the filter reads neither:
#   2900 completed, no findings, no mark → actionable.
#   2901 running → actionable.
#   2902 completed, no findings, our unedited EYES mark → handled by the one handled-marker rule.
#   2903 same, edited after the mark → actionable.
#   2904 a human copying the markers → actionable under all; not emitted under automated.
run_case "case29:summary-markers-inert-automated" "case29-summary-markers-inert.json" "selfuser" "automated" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase29comment2900","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2900","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase29comment2901","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2901","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase29comment2902","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2902","last_edited_at":null,"classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase29comment2903","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2903","last_edited_at":"2026-11-10T12:05:00Z","classification":"actionable"}]'
run_case "case29:summary-markers-inert-all" "case29-summary-markers-inert.json" "selfuser" "all" \
  '[{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase29comment2900","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2900","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase29comment2901","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2901","last_edited_at":null,"classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase29comment2902","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2902","last_edited_at":null,"classification":"handled"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase29comment2903","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2903","last_edited_at":"2026-11-10T12:05:00Z","classification":"actionable"},{"surface":"toplevel","thread_resolved":false,"thread_overflow":false,"thread_id":null,"id":"IC_kwDOcase29comment2904","databaseId":null,"url":"https://github.com/o/r/pull/1#issuecomment-2904","last_edited_at":null,"classification":"actionable"}]'

# ── Identity module truth tables ─────────────────────────────────────────────────
# Each row evaluates one module call with the module included and exact-matches the JSON it must
# return.

# identity_row <case> <expected-json> <jq-call-over-the-module>
identity_row() {
  local case_name="$1" expected="$2" call="$3" actual
  if ! actual="$(jq -n -c -L "$MODULE_DIR" "include \"reviewer-identity\"; $call")"; then
    failed "$case_name" "jq failed evaluating: $call"
    return
  fi
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "$call -> $actual"
  else
    failed "$case_name" "$call -> $actual (expected $expected)"
  fi
}

# `is_bot`: typed `Bot`, OR a raw login ending in the reserved `[bot]` suffix (the REST reactions
# endpoint types a bot reactor `User`). A suffix that is not at the end (the tab-forged login) and a
# bare login without a `Bot` type are NOT bots.
identity_row "is-bot:suffix-user-typed" 'true' 'is_bot("review-bot[bot]"; "User")'
identity_row "is-bot:suffix-null-typed" 'true' 'is_bot("review-bot[bot]"; null)'
identity_row "is-bot:bare-bot-typed" 'true' 'is_bot("review-bot"; "Bot")'
identity_row "is-bot:bare-user-typed" 'false' 'is_bot("claude"; "User")'
identity_row "is-bot:bare-null-typed" 'false' 'is_bot("claude"; null)'
identity_row "is-bot:tab-forged-suffix" 'false' 'is_bot("review-bot[bot]\tBot"; "User")'
identity_row "is-bot:null-login-null-type" 'false' 'is_bot(null; null)'

# `configured_reviewers`: split on commas and whitespace, empties dropped, one `[bot]` stripped,
# lowercased.
identity_row "configured:comma-space-mix" '["a","b","c","d"]' 'configured_reviewers("a, b  c[bot],,D[bot]")'
identity_row "configured:tab-newline" '["a","b"]' 'configured_reviewers("\ta\nb\n")'
identity_row "configured:empty" '[]' 'configured_reviewers("")'
identity_row "configured:separators-only" '[]' 'configured_reviewers(" , ,\t")'
identity_row "configured:null" '[]' 'configured_reviewers(null)'
identity_row "configured:bare-suffix-dropped" '[]' 'configured_reviewers("[bot]")'
identity_row "configured:one-suffix-stripped" '["x[bot]"]' 'configured_reviewers("x[bot][bot]")'
identity_row "configured:uppercase-folded" '["review-bot"]' 'configured_reviewers("Review-Bot[bot]")'

# `automated_reviewer_set`: Bot evidence rows plus configured logins, lowercased, deduplicated,
# github-actions only when configured.
identity_row "set:bot-rows-only" '["a","c"]' \
  'automated_reviewer_set([{login:"A",type:"Bot"},{login:"b",type:"User"},{login:"c[bot]",type:"User"}]; "")'
identity_row "set:case-dedupe" '["a"]' \
  'automated_reviewer_set([{login:"A",type:"Bot"},{login:"a[bot]",type:null}]; "A[bot]")'
identity_row "set:github-actions-evidence-dropped" '["a"]' \
  'automated_reviewer_set([{login:"github-actions",type:"Bot"},{login:"a",type:"Bot"}]; "")'
identity_row "set:github-actions-configured" '["a","github-actions"]' \
  'automated_reviewer_set([{login:"github-actions",type:"Bot"},{login:"a",type:"Bot"}]; "GitHub-Actions[bot]")'
identity_row "set:configured-adds-never-narrows" '["a","b"]' \
  'automated_reviewer_set([{login:"a",type:"Bot"}]; "b")'
identity_row "set:malformed-rows-ignored" '["a"]' \
  'automated_reviewer_set([null,5,"x",{login:null,type:"Bot"},{login:7,type:"Bot"},{type:"Bot"},{login:"a",type:"Bot"}]; "")'
identity_row "set:null-evidence" '["b"]' 'automated_reviewer_set(null; "b")'

# `is_automated_reviewer`: a Bot account whose folded login is in the set.
identity_row "automated:bot-in-set" 'true' 'is_automated_reviewer("review-bot"; "Bot"; ["review-bot"])'
identity_row "automated:case-folded" 'true' 'is_automated_reviewer("Review-Bot"; "Bot"; ["review-bot"])'
identity_row "automated:suffix-user-typed" 'true' 'is_automated_reviewer("review-bot[bot]"; "User"; ["review-bot"])'
identity_row "automated:user-same-login" 'false' 'is_automated_reviewer("review-bot"; "User"; ["review-bot"])'
identity_row "automated:bare-null-typed" 'false' 'is_automated_reviewer("review-bot"; null; ["review-bot"])'
identity_row "automated:bot-not-in-set" 'false' 'is_automated_reviewer("other-bot"; "Bot"; ["review-bot"])'
identity_row "automated:null-login" 'false' 'is_automated_reviewer(null; "Bot"; ["review-bot"])'

# Bot gate on configured logins: configuring a login never admits a human User holding it.
identity_row "filter:configured-bot-admitted" 'true' \
  'reviewer_matches_filter("plain-bot"; "Bot"; "selfuser"; "automated"; automated_reviewer_set([]; "plain-bot"))'
identity_row "filter:configured-login-user-refused" 'false' \
  'reviewer_matches_filter("plain-bot"; "User"; "selfuser"; "automated"; automated_reviewer_set([]; "plain-bot"))'
identity_row "filter:configured-github-actions-admitted" 'true' \
  'reviewer_matches_filter("github-actions[bot]"; "Bot"; "selfuser"; "automated"; automated_reviewer_set([]; "github-actions"))'
identity_row "filter:github-actions-unconfigured-refused" 'false' \
  'reviewer_matches_filter("github-actions"; "Bot"; "selfuser"; "automated"; automated_reviewer_set([{login:"github-actions",type:"Bot"}]; ""))'

# `reviewer_matches_filter` modes.
identity_row "filter:automated-suffix-user-typed" 'true' \
  'reviewer_matches_filter("claude[bot]"; "User"; "selfuser"; "automated"; ["claude"])'
identity_row "filter:automated-bare-user-typed" 'false' \
  'reviewer_matches_filter("claude"; "User"; "selfuser"; "automated"; ["claude"])'
identity_row "filter:all-human" 'true' 'reviewer_matches_filter("someone"; "User"; "selfuser"; "all"; [])'
identity_row "filter:all-self-refused" 'false' 'reviewer_matches_filter("selfuser"; "User"; "selfuser"; "all"; [])'
identity_row "filter:login-exact" 'true' 'reviewer_matches_filter("review-bot[bot]"; "Bot"; "selfuser"; "review-bot"; [])'
identity_row "filter:login-case-sensitive" 'false' 'reviewer_matches_filter("Review-Bot"; "Bot"; "selfuser"; "review-bot"; [])'
identity_row "filter:login-type-agnostic" 'true' 'reviewer_matches_filter("someone"; "User"; "selfuser"; "someone"; [])'
identity_row "filter:keyword-shadows-login" 'false' 'reviewer_matches_filter("automated"; "User"; "selfuser"; "automated"; [])'
identity_row "filter:retired-value-matches-nothing" 'false' \
  'reviewer_matches_filter("chatgpt-codex-connector"; "Bot"; "selfuser"; "codex-only"; ["chatgpt-codex-connector"])'

# `is_review_approval`: APPROVED, or COMMENTED with zero inline comments; null or missing is not.
identity_row "approval:approved" 'true' 'is_review_approval("APPROVED"; 0)'
identity_row "approval:approved-with-inline" 'true' 'is_review_approval("APPROVED"; 3)'
identity_row "approval:commented-no-inline" 'true' 'is_review_approval("COMMENTED"; 0)'
identity_row "approval:commented-with-inline" 'false' 'is_review_approval("COMMENTED"; 2)'
identity_row "approval:commented-null-inline" 'false' 'is_review_approval("COMMENTED"; null)'
identity_row "approval:changes-requested" 'false' 'is_review_approval("CHANGES_REQUESTED"; 0)'
identity_row "approval:dismissed" 'false' 'is_review_approval("DISMISSED"; 0)'
identity_row "approval:null-state" 'false' 'is_review_approval(null; 0)'

# `is_settled_thread`: resolved exactly true, or the last comment is a User-typed self comment.
identity_row "settled:resolved" 'true' 'is_settled_thread(true; "review-bot[bot]"; "Bot"; "selfuser")'
identity_row "settled:unresolved-self-last" 'true' 'is_settled_thread(false; "selfuser"; "User"; "selfuser")'
identity_row "settled:unresolved-bot-last" 'false' 'is_settled_thread(false; "review-bot[bot]"; "Bot"; "selfuser")'
identity_row "settled:unresolved-bot-typed-self-login" 'false' 'is_settled_thread(false; "selfuser"; "Bot"; "selfuser")'
identity_row "settled:unresolved-untyped-last" 'false' 'is_settled_thread(false; "selfuser"; null; "selfuser")'
identity_row "settled:null-resolved" 'false' 'is_settled_thread(null; "review-bot[bot]"; "Bot"; "selfuser")'
identity_row "settled:empty-self" 'false' 'is_settled_thread(false; ""; "User"; "")'

# `has_settled_evidence`: every latest review of every author is APPROVED, COMMENTED or DISMISSED,
# and an in-scope Bot has an APPROVED or COMMENTED latest review or a THUMBS_UP.
identity_row "evidence:bot-approved" 'true' \
  'has_settled_evidence([{state:"APPROVED",login:"review-bot",type:"Bot"}]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:bot-commented" 'true' \
  'has_settled_evidence([{state:"COMMENTED",login:"review-bot[bot]",type:"User"}]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:bot-changes-requested" 'false' \
  'has_settled_evidence([{state:"CHANGES_REQUESTED",login:"review-bot",type:"Bot"}]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:human-changes-requested-blocks" 'false' \
  'has_settled_evidence([{state:"APPROVED",login:"review-bot",type:"Bot"},{state:"CHANGES_REQUESTED",login:"someone",type:"User"}]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:null-author-changes-requested-blocks" 'false' \
  'has_settled_evidence([{state:"APPROVED",login:"review-bot",type:"Bot"},{state:"CHANGES_REQUESTED",login:null,type:null}]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:pending-blocks" 'false' \
  'has_settled_evidence([{state:"APPROVED",login:"review-bot",type:"Bot"},{state:"PENDING",login:"someone",type:"User"}]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:null-state-blocks" 'false' \
  'has_settled_evidence([{state:"APPROVED",login:"review-bot",type:"Bot"},{state:null,login:"someone",type:"User"}]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:missing-state-blocks" 'false' \
  'has_settled_evidence([{state:"APPROVED",login:"review-bot",type:"Bot"},{login:"someone",type:"User"}]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:unknown-state-blocks" 'false' \
  'has_settled_evidence([{state:"APPROVED",login:"review-bot",type:"Bot"},{state:"SOMETHING_NEW",login:"someone",type:"User"}]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:non-object-row-blocks" 'false' \
  'has_settled_evidence([{state:"APPROVED",login:"review-bot",type:"Bot"},null]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:dismissed-alone" 'false' \
  'has_settled_evidence([{state:"DISMISSED",login:"review-bot",type:"Bot"}]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:dismissed-plus-bot-thumbs" 'true' \
  'has_settled_evidence([{state:"DISMISSED",login:"review-bot",type:"Bot"}]; [{login:"review-bot[bot]",type:"User"}]; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:thumbs-only-bot" 'true' \
  'has_settled_evidence([]; [{login:"review-bot[bot]",type:"User"}]; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:empty-inputs" 'false' 'has_settled_evidence([]; []; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:null-inputs" 'false' 'has_settled_evidence(null; null; "selfuser"; "automated"; ["review-bot"])'
identity_row "evidence:human-only-review" 'false' \
  'has_settled_evidence([{state:"APPROVED",login:"someone",type:"User"}]; []; "selfuser"; "all"; ["review-bot"])'
identity_row "evidence:human-only-thumbs" 'false' \
  'has_settled_evidence([]; [{login:"someone",type:"User"}]; "selfuser"; "all"; ["review-bot"])'
identity_row "evidence:self-user-review" 'false' \
  'has_settled_evidence([{state:"APPROVED",login:"selfuser",type:"User"}]; []; "selfuser"; "all"; ["selfuser"])'
identity_row "evidence:login-filter-other-bot" 'false' \
  'has_settled_evidence([{state:"APPROVED",login:"review-bot",type:"Bot"}]; [{login:"review-bot[bot]",type:"User"}]; "selfuser"; "other-bot"; ["review-bot","other-bot"])'
identity_row "evidence:login-filter-named-bot" 'true' \
  'has_settled_evidence([{state:"APPROVED",login:"review-bot[bot]",type:"Bot"}]; []; "selfuser"; "review-bot"; ["review-bot","other-bot"])'

# `is_retired_filter`: only the exact retired value.
identity_row "retired:codex-only" 'true' 'is_retired_filter("codex-only")'
identity_row "retired:case-sensitive" 'false' 'is_retired_filter("Codex-Only")'
identity_row "retired:automated" 'false' 'is_retired_filter("automated")'
identity_row "retired:all" 'false' 'is_retired_filter("all")'
identity_row "retired:null" 'false' 'is_retired_filter(null)'

# ── CLOSURE: no inlined `[bot]` strip literal in a consumer ──────────────────────
# The `[bot]` strip literal must live ONLY in reviewer-identity.jq. A consumer that inlines it is a
# second source of truth the module cannot govern.
#
# Matching choice: ERE `\[bot\\*\]` — matches `[bot]` with zero or more backslashes before the
# closing bracket, so it catches the bare `[bot]` text AND both the jq-escaped `\\[bot\\]` and
# single-escaped `\[bot\]` regex spellings. Prose mentioning the suffix in these files also trips it;
# that is intentional, as the module header is the one place the identity semantics are described.
# The matcher is proven to bite against a scratch canary carrying each forbidden construct, and
# proven not to over-match the legitimate constructs these files contain today.
CLOSURE_TARGETS=(
  "$MODULE_DIR/fix-history-classify.jq"
  "$MODULE_DIR/prefilter.sh"
  "$MODULE_DIR/fetch-normalize.sh"
  "$REPO_ROOT/plugin/skills/_shared/fetch-normalize-core.sh"
  "$MODULE_DIR/pr-change-detect-poll.sh"
  "$MODULE_DIR/react-marker.sh"
  "$MODULE_DIR/merge-approved.sh"
)
BOT_STRIP_ERE='\[bot\\*\]'

# print_closure_hits <file>
# Print every hit of the `[bot]` strip literal in <file>, one per line, as `bot-strip:<lineno>:<text>`.
print_closure_hits() {
  grep -nE -- "$BOT_STRIP_ERE" "$1" | sed 's/^/bot-strip:/'
  return 0
}

CANARY_HIT="$WORKDIR/closure-canary-hit.jq"
printf '%s\n' 'sub("\\[bot\\]$"; "")' 'test("\[bot\]$")' '# strips the [bot] suffix' > "$CANARY_HIT"
canary_lines="$(wc -l < "$CANARY_HIT" | tr -d ' ')"
canary_hit_lines="$(print_closure_hits "$CANARY_HIT" | cut -d: -f2 | sort -un | wc -l | tr -d ' ')"
if [ "$canary_hit_lines" = "$canary_lines" ]; then
  pass "closure:canary-bites" "every one of $canary_lines forbidden canary lines detected"
else
  failed "closure:canary-bites" "detected $canary_hit_lines of $canary_lines forbidden canary lines"
fi

CANARY_CLEAN="$WORKDIR/closure-canary-clean.sh"
printf '%s\n' '# ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/prefilter.sh' \
  'REVIEWER_FILTER="automated"' 'include "reviewer-identity";' > "$CANARY_CLEAN"
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
    pass "closure:$closure_rel" "no inlined [bot] strip literal"
  else
    failed "closure:$closure_rel" "inlined identity literal(s):
$closure_hits"
  fi
done

# ── CLOSURE: no login-only self compare in a consumer ────────────────────────────
# Self identity is the module's `is_self` (User type + raw login). A consumer that compares an
# author login straight against the `$login` (SELF_LOGIN) --arg — `select($a == $login)`,
# `strip_bot(.author.login) != $login` — re-derives self on login alone, so a Bot sharing the
# viewer's bare login reads as self. Any `==` / `!=` with `$login` as either operand is a hit; the
# word bound after `$login` keeps a longer variable name (`$login_x`) out. `$login` passed as an
# argument (`--arg login`, `is_self(...; $login)`, the matches_filter wrapper) is not a compare.
# RESIDUAL: rebinding the --arg to another variable (`$login as $me | ... == $me`) evades this
# matcher; the behavioural cases (8, 20) are the guard for that shape. merge-approved.sh binds self as
# `--arg self`, not `--arg login`, so this matcher reads no self compare there; its merge cases in
# tools/test_merge_approved.sh (`threads:unresolved-bot-with-self-login-last`) are the guard there.
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
  'def matches_filter($a; $t): reviewer_matches_filter($a; $t; $login; $filter; $reviewer_set);' > "$SELF_CANARY_CLEAN"
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

# ── CLOSURE: no reviewer product, CI or retired-filter literal outside its home ───
# The Automated Reviewer set is derived from PR evidence, so no reviewer product login may be named
# in the module or a consumer; the logins below are TEST DATA held only here. `github-actions` is the
# module's CI-identity exclusion and may appear only in the module. The retired filter value is
# named only by the module's `is_retired_filter` line; consumers call that def, never the literal.
# Matching choice: case-insensitive (GitHub logins are case-insensitive). Product logins match as
# whole words (`grep -w`), so a hyphenated login inside prose (`claude-mem`) still hits while an
# identifier such as `CLAUDE_PLUGIN_ROOT` does not. `codex` and `github-actions` match as plain
# substrings, so `codex_only` or `chatgpt-codex-connector` cannot slip past a word bound. Prose
# mentioning any of these in a target trips it; that is intentional.
REVIEWER_PRODUCT_LOGIN_ERE='chatgpt-codex-connector|copilot-pull-request-reviewer|copilot|claude|coderabbitai|gemini-code-assist|sourcery-ai|greptile-apps|qodo-merge-pro'
CI_IDENTITY_ERE='github-actions'
RETIRED_LITERAL_ERE='codex'
RETIRED_HOME_ERE='^[0-9]+:def is_retired_filter\('
LITERAL_TARGETS=("$IDENTITY_MODULE" "${CLOSURE_TARGETS[@]}")

# print_literal_hits <grep-mode-flags> <ere> <file>
# Print every case-insensitive hit of <ere> in <file> as `<lineno>:<text>`, one per line. Exits 0 on
# hits or no hits and non-zero only when grep itself fails (exit 2), so a read error is never a pass.
print_literal_hits() {
  local grep_status
  grep -ni"$1"E -- "$2" "$3"
  grep_status=$?
  [ "$grep_status" -le 1 ]
}

# print_retired_hits <file>
# Print every retired-literal hit in <file> as `<lineno>:<text>`; in the module, the one home line
# (`def is_retired_filter(`) is exempt. Non-zero only when the underlying grep fails.
print_retired_hits() {
  local retired_hits
  retired_hits="$(print_literal_hits '' "$RETIRED_LITERAL_ERE" "$1")" || return 1
  if [ "$1" = "$IDENTITY_MODULE" ]; then
    printf '%s\n' "$retired_hits" | grep -vE -- "$RETIRED_HOME_ERE" | grep -v '^$'
  else
    printf '%s\n' "$retired_hits" | grep -v '^$'
  fi
  return 0
}

# assert_canary_hits <case> <expected-hit-count> <hits> <grep-status>
# Pass when the canary grep succeeded and produced exactly <expected-hit-count> distinct hit lines.
assert_canary_hits() {
  local hit_lines
  if [ "$4" -ne 0 ]; then
    failed "$1" "canary grep failed"
    return 0
  fi
  hit_lines="$(printf '%s\n' "$3" | grep -v '^$' | cut -d: -f1 | sort -un | wc -l | tr -d ' ')"
  if [ "$hit_lines" = "$2" ]; then
    pass "$1" "detected exactly $2 canary hit lines"
  else
    failed "$1" "detected $hit_lines canary hit lines, expected $2:
$3"
  fi
}

LITERAL_CANARY_HIT="$WORKDIR/literal-canary-hit.sh"
printf '%s\n' 'select(.login == "chatgpt-codex-connector")' '["Copilot", "copilot-pull-request-reviewer[bot]"]' \
  '# reviews from claude-mem or CodeRabbitAI' 'def x: "gemini-code-assist[bot]";' > "$LITERAL_CANARY_HIT"
literal_canary_hits="$(print_literal_hits 'w' "$REVIEWER_PRODUCT_LOGIN_ERE" "$LITERAL_CANARY_HIT")"
assert_canary_hits "product-login:canary-bites" 4 "$literal_canary_hits" "$?"

LITERAL_CANARY_CLEAN="$WORKDIR/literal-canary-clean.sh"
printf '%s\n' '# ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/prefilter.sh' \
  'automated_reviewer_set(.; $reviewers)' 'REVIEWER_FILTER="automated"' 'include "reviewer-identity";' \
  > "$LITERAL_CANARY_CLEAN"
literal_canary_hits="$(print_literal_hits 'w' "$REVIEWER_PRODUCT_LOGIN_ERE" "$LITERAL_CANARY_CLEAN")"
assert_canary_hits "product-login:canary-no-overmatch" 0 "$literal_canary_hits" "$?"

CI_CANARY_HIT="$WORKDIR/ci-canary-hit.sh"
printf '%s\n' 'select(. != "github-actions")' '["GitHub-Actions[bot]"]' > "$CI_CANARY_HIT"
ci_canary_hits="$(print_literal_hits '' "$CI_IDENTITY_ERE" "$CI_CANARY_HIT")"
assert_canary_hits "ci-identity:canary-bites" 2 "$ci_canary_hits" "$?"

CI_CANARY_CLEAN="$WORKDIR/ci-canary-clean.sh"
printf '%s\n' '# .github/workflows/policy-check.yml' 'github_actions_run=1' > "$CI_CANARY_CLEAN"
ci_canary_hits="$(print_literal_hits '' "$CI_IDENTITY_ERE" "$CI_CANARY_CLEAN")"
assert_canary_hits "ci-identity:canary-no-overmatch" 0 "$ci_canary_hits" "$?"

RETIRED_CANARY="$WORKDIR/retired-canary.sh"
printf '%s\n' 'def is_retired_filter($filter): $filter == "codex-only";' '[ "$f" = codex_only ] && exit' \
  '# Codex reviews' > "$RETIRED_CANARY"
retired_canary_hits="$(print_retired_hits "$RETIRED_CANARY")"
assert_canary_hits "retired-literal:consumer-canary-bites" 3 "$retired_canary_hits" "$?"

RETIRED_MODULE_CANARY="$WORKDIR/reviewer-identity.jq"
printf '%s\n' 'def is_retired_filter($filter): $filter == "codex-only";' \
  'def is_filter_ok($filter): $filter != "codex-only";' > "$RETIRED_MODULE_CANARY"
retired_canary_hits="$(IDENTITY_MODULE="$RETIRED_MODULE_CANARY" print_retired_hits "$RETIRED_MODULE_CANARY")"
assert_canary_hits "retired-literal:module-canary-bites-off-home-line" 1 "$retired_canary_hits" "$?"
case "$retired_canary_hits" in
  2:*) pass "retired-literal:module-canary-home-line-exempt" "only the off-home line is reported" ;;
  *) failed "retired-literal:module-canary-home-line-exempt" "unexpected module canary hits: $retired_canary_hits" ;;
esac

for literal_target in "${LITERAL_TARGETS[@]}"; do
  literal_rel="${literal_target#"$REPO_ROOT"/}"
  if [ ! -f "$literal_target" ]; then
    failed "literal-closure:$literal_rel" "closure target missing"
    continue
  fi
  if ! product_hits="$(print_literal_hits 'w' "$REVIEWER_PRODUCT_LOGIN_ERE" "$literal_target")"; then
    failed "product-login:$literal_rel" "grep failed"
  elif [ -z "$product_hits" ]; then
    pass "product-login:$literal_rel" "no reviewer product login"
  else
    failed "product-login:$literal_rel" "reviewer product login(s); derive reviewers from PR evidence:
$product_hits"
  fi
  if ! retired_hits="$(print_retired_hits "$literal_target")"; then
    failed "retired-literal:$literal_rel" "grep failed"
  elif [ -z "$retired_hits" ]; then
    pass "retired-literal:$literal_rel" "no retired-filter literal outside the module's is_retired_filter line"
  else
    failed "retired-literal:$literal_rel" "retired-filter literal(s); call is_retired_filter:
$retired_hits"
  fi
  [ "$literal_target" != "$IDENTITY_MODULE" ] || continue
  if ! ci_hits="$(print_literal_hits '' "$CI_IDENTITY_ERE" "$literal_target")"; then
    failed "ci-identity:$literal_rel" "grep failed"
  elif [ -z "$ci_hits" ]; then
    pass "ci-identity:$literal_rel" "no github-actions literal outside the module"
  else
    failed "ci-identity:$literal_rel" "github-actions literal(s); the module owns the CI identity rule:
$ci_hits"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────────
echo
echo "fix-history-classify: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
