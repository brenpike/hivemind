#!/usr/bin/env bash
#
# Behavior test runner for the READ-ONLY ready-wave engine
# (plugin/skills/next-wave/scripts/next-wave.sh).
#
# The engine takes a BARE run_id positional (never a ledger path), DERIVES the ledger as
# <git-root>/.hivemind/runs/<run_id>/state.json, reads it, and PRINTS a routing decision:
#     all_done: true|false
#     wave: [STEP-00X, STEP-00Y]     # step ids to dispatch this iteration; [] when all_done
#     remaining: <N>                 # count of not-done steps
# It mutates NOTHING (pure read -> derive -> emit). On a validation failure it prints
# `blocker: <reason>` on stderr and exits 1 with nothing on stdout.
#
# ISOLATION (mirrors tools/test_engine.sh's ledger-root pattern): the REAL committed engine is
# run unmodified — it self-locates its own plugin_root (BASH_SOURCE + pwd -P => the real
# plugin/) and sources the real shared containment / ledger-engine-io helpers. Only the LEDGER
# ROOT is faked: each case stages its fixture under a THROWAWAY `git init` checkout so the
# engine's `git rev-parse --show-toplevel` derives the ledger inside that disposable root and
# never touches THIS repo. No FAKEPLUGIN self-location root is needed here (unlike test_engine.sh)
# because next-wave reads NO packaged workflow definition — only the ledger.
#
# Fixtures (tests/next-wave/*.json) are synthetic run-ledger state.json payloads, each crafted to
# exercise one behavior. The harness copies a fixture into the derived ledger path, forcing
# .run.id == run_id for the engine's coherence check (mirroring test_engine.sh's stage helper),
# and optionally overriding .events to simulate wave-advance stages via the DONE-SET derivation
# (union of events[].outputs.completed_steps). Overriding .events in the STAGED copy is a
# harness-side jq mutation (like test_engine.sh forcing .run.id/.run.workflow); it adds NO new
# fixture file — the six tracked fixtures stay the six source payloads.
#
# Assertions:
#   linear   — A->B->C strictly chained: waves of exactly 1 each (today-equivalent serial degrade),
#              and advancement after an event marks STEP-001 done.
#   diamond  — A, then B and C (disjoint) both depend on A, then D depends on B and C. Proves the
#              full lifecycle across simulated stages: wave1=[A], wave2=[B,C] fan-out (with A
#              excluded because a completed_steps event marks it done), wave3=[D] join (done-set
#              UNION across TWO events), wave4=[] all_done. This is the DONE-SET-driven-by-events
#              proof: done-ness comes from events[].outputs.completed_steps, never plan.steps.status.
#   overlap  — two steps with satisfied deps SHARING a file serialize to a wave of 1.
#   glob     — a ready step whose files[] carries a glob metachar is conflicts-with-all: runs ALONE
#              even though a disjoint ready step is available.
#   alias    — a ready step whose files[] carries a `.`/`..` path component (the previously
#              fail-open alias forms) is conflicts-with-all: runs ALONE even though its own alias
#              form and a disjoint ready step are both available.
#   missing  — a ready step with an absent or empty files[] is conflicts-with-all: runs ALONE even
#              though a disjoint ready step is available (under-declared scope can't fan out).
#   cycle    — a dependency cycle is a blocker: exit 1, stderr blocker, ledger byte-unchanged.
#   empty    — empty plan.steps is a blocker: exit 1, stderr blocker, ledger byte-unchanged.
#   epoch    — cross-generation collision closed: after a replan into epoch 2, a prior-epoch
#              (plan_epoch=1) completed_steps credit for the REUSED positional id STEP-001 is
#              IGNORED (1 != current 2), so STEP-001 is re-dispatched this generation; and a
#              SAME-epoch (plan_epoch=2) credit for STEP-001 DOES count, excluding it from the wave.
#              Proves next-wave's done-set is scoped to the current plan.epoch.
#   bad-id   — a plan.steps entry whose .id fails the SAFE_ID_RE charset (a stray `]`) is a
#              blocker: exit 1, stderr blocker, ledger byte-unchanged. Proves the READER-SIDE
#              charset belt (a pre-existing seeded/resume ledger predating the write-boundary
#              guards) stops a malformed id BEFORE it can reach the `wave: [...]` routing emit.
#   line-feed — the safe-id check covers the WHOLE string (issue #424): a step id or depends_on
#              entry ending in a line feed is a blocker, a run_id with an embedded or trailing
#              line feed is refused before any ledger read, and an unsafe duplicate or unknown
#              dependency id (a line feed, or 5000 bytes ending in `]`) gets the safe-id blocker,
#              which runs before the duplicate-id / unknown-dep checks; a safe duplicate or unknown
#              id still gets its own blocker, the id JSON-encoded.
#   shape    — the POSITIVE SHAPE-VALIDATION GATE that runs before checks (a)-(f): a non-object
#              plan.steps entry, a non-array depends_on, a non-array plan.steps, and a
#              missing/non-string .id are each a clean blocker (exit 1, stderr blocker, empty
#              stdout, ledger byte-unchanged) rather than an uncaught raw-jq crash. A further
#              assert_wave case proves the DONE-SET read is type-projected: a malformed
#              (non-object) .events[] element is SKIPPED, not crashed, while a valid
#              completed_steps event alongside it still credits normally.
#
# Every success case ALSO asserts the staged ledger is BYTE-UNCHANGED after the engine runs
# (sha256 before == after) — the engine is read-only.
#
# Prints PASS/FAIL per assertion. Exits non-zero if ANY assertion FAILs.
#
# Usage:
#   ./tools/test_next_wave.sh

set -euo pipefail

# ── Path setup ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENGINE="$REPO_ROOT/plugin/skills/next-wave/scripts/next-wave.sh"
FIXTURES_DIR="$REPO_ROOT/tests/next-wave"

LEDGER_LINEAR="$FIXTURES_DIR/ledger-linear.json"
LEDGER_DIAMOND="$FIXTURES_DIR/ledger-diamond.json"
LEDGER_OVERLAP="$FIXTURES_DIR/ledger-overlap.json"
LEDGER_GLOB="$FIXTURES_DIR/ledger-glob-scope.json"
LEDGER_ALIAS="$FIXTURES_DIR/ledger-alias-scope.json"
LEDGER_MISSING="$FIXTURES_DIR/ledger-missing-scope.json"
LEDGER_CYCLE="$FIXTURES_DIR/ledger-cycle.json"
LEDGER_EMPTY="$FIXTURES_DIR/ledger-empty-steps.json"
LEDGER_REPLAN_EPOCH="$FIXTURES_DIR/ledger-replan-epoch.json"

# ── Dependency / fixture preflight ──────────────────────────────────────────

for dep in jq sha256sum git; do
    command -v "$dep" >/dev/null 2>&1 \
        || { echo "FAIL: required dependency '$dep' is not installed" >&2; exit 2; }
done

for required in "$ENGINE" \
    "$LEDGER_LINEAR" "$LEDGER_DIAMOND" "$LEDGER_OVERLAP" "$LEDGER_GLOB" \
    "$LEDGER_ALIAS" "$LEDGER_MISSING" \
    "$LEDGER_CYCLE" "$LEDGER_EMPTY" "$LEDGER_REPLAN_EPOCH"; do
    [[ -f "$required" ]] \
        || { echo "FAIL: required input missing: $required" >&2; exit 2; }
done

# ── Disposable workdir ──────────────────────────────────────────────────────

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-next-wave-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ── Per-case helpers ─────────────────────────────────────────────────────────

# new_gitroot <name> -> prints the path to a fresh throwaway git checkout under $WORKDIR. The
# engine self-locates into the real plugin/ while `git rev-parse --show-toplevel` (run with
# cd "$gitroot") resolves THIS disposable checkout, so the derived ledger never touches the repo.
new_gitroot() {
    local root="$WORKDIR/$1"
    mkdir -p "$root"
    git -C "$root" init -q
    printf '%s' "$root"
}

# stage_ledger <gitroot> <run_id> <fixture> [events_json]
# Places <fixture> at <gitroot>/.hivemind/runs/<run-id>/state.json with .run.id forced to
# <run-id> (coherence). When [events_json] is supplied it is bound via --argjson and overrides
# .events (simulating completed-step stages for the DONE-SET derivation). Prints the ledger path.
stage_ledger() {
    local gitroot="$1" run_id="$2" fixture="$3" events_json="${4:-}"
    local dir="$gitroot/.hivemind/runs/$run_id"
    mkdir -p "$dir"
    local ledger="$dir/state.json"
    if [[ -n "$events_json" ]]; then
        jq --arg id "$run_id" --argjson ev "$events_json" \
            '.run.id = $id | .events = $ev' \
            "$fixture" > "$ledger"
    else
        jq --arg id "$run_id" '.run.id = $id' "$fixture" > "$ledger"
    fi
    printf '%s' "$ledger"
}

# run_engine <gitroot> <run_id> <out-var> <err-file> -> sets <out-var> to stdout, writes stderr to
# <err-file>, returns the engine's exit code (never trips errexit — called via `|| rc=$?`).
# shellcheck disable=SC2034
run_engine() {
    local gitroot="$1" run_id="$2" __outvar="$3" errfile="$4"
    local __out rc=0
    __out="$(cd "$gitroot" && bash "$ENGINE" "$run_id" 2>"$errfile")" || rc=$?
    printf -v "$__outvar" '%s' "$__out"
    return "$rc"
}

# assert_wave <name> <gitroot> <run_id> <ledger> <exp_all_done> <exp_wave> <exp_remaining>
# Runs the engine, asserts exit 0, the three YAML routing lines match, and the ledger is
# byte-unchanged (read-only proof).
assert_wave() {
    local name="$1" gitroot="$2" run_id="$3" ledger="$4"
    local exp_all_done="$5" exp_wave="$6" exp_remaining="$7"
    local before after out rc=0
    before="$(sha256sum "$ledger" | awk '{print $1}')"
    local errfile="$gitroot/$run_id.err"

    run_engine "$gitroot" "$run_id" out "$errfile" || rc=$?

    after="$(sha256sum "$ledger" | awk '{print $1}')"
    if [[ "$rc" -ne 0 ]]; then
        failed "$name" "engine exited $rc (expected 0); stderr=$(tr '\n' '|' < "$errfile" 2>/dev/null)"
        return
    fi
    if [[ "$before" != "$after" ]]; then
        failed "$name" "engine mutated the ledger (sha256 changed) — must be read-only"
        return
    fi
    local got_all_done got_wave got_remaining
    got_all_done="$(printf '%s\n' "$out" | sed -n 's/^all_done: //p')"
    got_wave="$(printf '%s\n' "$out" | sed -n 's/^wave: //p')"
    got_remaining="$(printf '%s\n' "$out" | sed -n 's/^remaining: //p')"
    if [[ "$got_all_done" == "$exp_all_done" && "$got_wave" == "$exp_wave" && "$got_remaining" == "$exp_remaining" ]]; then
        pass "$name" "all_done=$got_all_done wave=$got_wave remaining=$got_remaining (ledger byte-unchanged)"
    else
        failed "$name" "expected all_done=$exp_all_done/wave=$exp_wave/remaining=$exp_remaining, got all_done=$got_all_done/wave=$got_wave/remaining=$got_remaining"
    fi
}

# assert_blocker <name> <gitroot> <run_id> <ledger>
# Runs the engine, asserts exit 1, stdout EMPTY, a `blocker:` line on stderr, and the ledger
# byte-unchanged (read-only proof).
assert_blocker() {
    local name="$1" gitroot="$2" run_id="$3" ledger="$4"
    local before after out rc=0
    before="$(sha256sum "$ledger" | awk '{print $1}')"
    local errfile="$gitroot/$run_id.err"

    run_engine "$gitroot" "$run_id" out "$errfile" || rc=$?

    after="$(sha256sum "$ledger" | awk '{print $1}')"
    local has_blocker="no"
    grep -q '^blocker: ' "$errfile" 2>/dev/null && has_blocker="yes"
    if [[ "$rc" -eq 1 && -z "$out" && "$has_blocker" == "yes" && "$before" == "$after" ]]; then
        pass "$name" "exit 1, blocker on stderr, stdout empty, ledger byte-unchanged"
    else
        failed "$name" "expected exit1/empty-stdout/blocker/unchanged; rc=$rc stdout='$out' blocker=$has_blocker changed=$([[ "$before" != "$after" ]] && echo yes || echo no)"
    fi
}

# assert_blocker_text <name> <gitroot> <run_id> <expected_stderr>
# Runs the engine, asserts exit 1, stdout EMPTY, and stderr EXACTLY <expected_stderr> plus one
# final newline, so a value the blocker names cannot add or split a line unnoticed.
assert_blocker_text() {
    local name="$1" gitroot="$2" run_id="$3" expected="$4"
    local out rc=0 got
    local errfile="$WORKDIR/$name.err"

    run_engine "$gitroot" "$run_id" out "$errfile" || rc=$?

    got="$(cat "$errfile"; printf x)"
    got="${got%x}"
    if [[ "$rc" -eq 1 && -z "$out" && "$got" == "$expected"$'\n' ]]; then
        pass "$name" "exit 1, stdout empty, stderr matches the expected blocker"
    else
        failed "$name" "expected exit1/empty-stdout/stderr=$(printf '%q' "$expected"$'\n'); rc=$rc stdout='$out' stderr=$(printf '%q' "$got")"
    fi
}

# ── linear: A->B->C strictly chained; waves of exactly 1 + advancement ───────

test_linear() {
    local gitroot run_id ledger
    gitroot="$(new_gitroot linear)"
    run_id="nw-linear"

    # Stage 0: no completed steps. Only STEP-001 is ready (B needs A, C needs B).
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_LINEAR")"
    assert_wave "linear:wave1" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-001]" "3"

    # Stage 1: STEP-001 done (via an event's completed_steps). Now only STEP-002 is ready.
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_LINEAR" \
        '[{"state":"implement_step","outputs":{"completed_steps":["STEP-001"]}}]')"
    assert_wave "linear:wave2-advance" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-002]" "2"
}

# ── diamond: fan-out / join lifecycle, done-set driven by events ─────────────

test_diamond() {
    local gitroot run_id ledger
    gitroot="$(new_gitroot diamond)"
    run_id="nw-diamond"

    # Stage 0: nothing done. Only STEP-001 ready.
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_DIAMOND")"
    assert_wave "diamond:wave1" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-001]" "4"

    # Stage 1: STEP-001 done -> STEP-002 and STEP-003 fan out (disjoint files). STEP-001 is
    # EXCLUDED because the completed_steps event marks it done (done-set from events, not status).
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_DIAMOND" \
        '[{"state":"implement_step","outputs":{"completed_steps":["STEP-001"]}}]')"
    assert_wave "diamond:wave2-fanout" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-002, STEP-003]" "3"

    # Stage 2: done-set is the UNION across TWO events ([STEP-001] then [STEP-002, STEP-003]).
    # STEP-004 (join) becomes ready once both its deps are in the union.
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_DIAMOND" \
        '[{"state":"implement_step","outputs":{"completed_steps":["STEP-001"]}},{"state":"implement_step","outputs":{"completed_steps":["STEP-002","STEP-003"]}}]')"
    assert_wave "diamond:wave3-join-union" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-004]" "1"

    # Stage 3: all four done across three events -> all_done, empty wave.
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_DIAMOND" \
        '[{"state":"implement_step","outputs":{"completed_steps":["STEP-001"]}},{"state":"implement_step","outputs":{"completed_steps":["STEP-002","STEP-003"]}},{"state":"implement_step","outputs":{"completed_steps":["STEP-004"]}}]')"
    assert_wave "diamond:all-done" "$gitroot" "$run_id" "$ledger" \
        "true" "[]" "0"
}

# ── overlap: two ready steps sharing a file serialize to a wave of 1 ─────────

test_overlap() {
    local gitroot run_id ledger
    gitroot="$(new_gitroot overlap)"
    run_id="nw-overlap"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_OVERLAP")"
    # Both ready (no deps), but they share src/shared.txt: plan-order greedy admits STEP-001 and
    # excludes STEP-002. remaining stays 2 (neither is done).
    assert_wave "overlap:serialize" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-001]" "2"
}

# ── glob: conflicts-with-all step runs ALONE ─────────────────────────────────

test_glob() {
    local gitroot run_id ledger
    gitroot="$(new_gitroot glob)"
    run_id="nw-glob"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_GLOB")"
    # STEP-001 declares a glob metachar (src/*.js) => conflicts-with-all => it locks the wave to
    # itself even though STEP-002 (docs/readme.md) is ready and file-disjoint.
    assert_wave "glob:runs-alone" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-001]" "2"
}

# ── alias: conflicts-with-all step with a `.`/`..` path component runs ALONE ─

test_alias_scope() {
    local gitroot run_id ledger
    gitroot="$(new_gitroot alias)"
    run_id="nw-alias"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_ALIAS")"
    # STEP-001 declares a `.` path component (src/./foo.ts) => conflicts-with-all => it locks the
    # wave to itself even though its alias STEP-002 (src/../src/foo.ts) and the disjoint STEP-003
    # (docs/readme.md) are both ready. Proves alias forms can't co-schedule.
    assert_wave "alias:runs-alone" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-001]" "3"
}

# ── missing: conflicts-with-all step with absent/empty files[] runs ALONE ────

test_missing_scope() {
    local gitroot run_id ledger
    gitroot="$(new_gitroot missing)"
    run_id="nw-missing"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_MISSING")"
    # STEP-001 has no files key at all => conflicts-with-all => it locks the wave to itself even
    # though STEP-002 (empty files[]) and STEP-003 (docs/readme.md) are both ready. Proves
    # under-declared scope cannot fan out unprotected.
    assert_wave "missing:runs-alone" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-001]" "3"
}

# ── cycle: dependency cycle is a blocker ─────────────────────────────────────

test_cycle() {
    local gitroot run_id ledger
    gitroot="$(new_gitroot cycle)"
    run_id="nw-cycle"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_CYCLE")"
    assert_blocker "cycle:blocker-exit1" "$gitroot" "$run_id" "$ledger"
}

# ── empty: empty plan.steps is a blocker ─────────────────────────────────────

test_empty() {
    local gitroot run_id ledger
    gitroot="$(new_gitroot empty)"
    run_id="nw-empty"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_EMPTY")"
    assert_blocker "empty:blocker-exit1" "$gitroot" "$run_id" "$ledger"
}

# ── epoch: cross-generation done-set scoping (replan collision closed) ───────

test_replan_epoch() {
    local gitroot run_id ledger
    gitroot="$(new_gitroot replan-epoch)"
    run_id="nw-replan-epoch"

    # Cross-epoch: the fixture carries .plan.epoch=2, two current-generation steps REUSING
    # positional ids STEP-001/STEP-002 (disjoint files, no deps, pending), and one EPOCH-1 event
    # (plan_epoch=1) crediting STEP-001 (plus a stale STEP-009 not in the current plan). Staged
    # with the fixture's OWN events (no override), the prior-generation credit is SCOPED OUT
    # (1 != 2), so STEP-001 is NOT done: both steps fan out. Proves the reused id from a prior
    # epoch does not collide with the current generation.
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_REPLAN_EPOCH")"
    assert_wave "epoch:prior-credit-ignored" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-001, STEP-002]" "2"

    # Same-epoch: override .events with a CURRENT-epoch (plan_epoch=2) credit for STEP-001. Now
    # 2 == 2, so STEP-001 IS done and excluded; only STEP-002 remains ready. Proves same-epoch
    # credits still count — the scoping ignores stale epochs, not the current one.
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_REPLAN_EPOCH" \
        '[{"state":"implement_step","plan_epoch":2,"outputs":{"completed_steps":["STEP-001"]}}]')"
    assert_wave "epoch:same-credit-counts" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-002]" "1"
}

# ── bad-id: a plan.steps entry with a SAFE_ID_RE-violating .id is a blocker ──

test_bad_step_id() {
    local name="bad-id:blocker-exit1"
    local gitroot run_id ledger tmp
    gitroot="$(new_gitroot bad-step-id)"
    run_id="nw-bad-step-id"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_LINEAR")"
    # Corrupt STEP-001's id to carry a `]` byte outside [A-Za-z0-9._-] — simulates a pre-existing
    # seeded/resume ledger predating the write-boundary guards (record-state-result /
    # init-run-ledger reject this at write time, so this shape can only arise from a ledger
    # written before those guards existed). In-place jq mutation of the staged copy: mirrors
    # tools/test_engine.sh's tmp/seed re-point pattern rather than adding a new fixture file for a
    # one-field corruption.
    tmp="$ledger.seed"
    jq '.plan.steps[0].id = "STEP-001]"' "$ledger" > "$tmp" && mv "$tmp" "$ledger"
    assert_blocker "$name" "$gitroot" "$run_id" "$ledger"
}

# ── line-feed: the safe-id check covers the WHOLE string (issue #424) ────────
# jq's Oniguruma `$` also matches before one final line feed, and grep is line-based, so the old
# `^[A-Za-z0-9._-]+$` checks accepted "STEP-001<LF>" (jq) and "ok<LF>../x" (grep).

test_trailing_lf_step_id() {
    local gitroot run_id ledger tmp
    gitroot="$(new_gitroot trailing-lf-step-id)"
    run_id="nw-trailing-lf-step-id"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_LINEAR")"
    tmp="$ledger.seed"
    jq '.plan.steps[0].id = "STEP-001\n" | .plan.steps[1].depends_on = ["STEP-001\n"]' "$ledger" > "$tmp" && mv "$tmp" "$ledger"
    assert_blocker "line-feed:trailing-lf-step-id" "$gitroot" "$run_id" "$ledger"
    assert_blocker_text "line-feed:trailing-lf-step-id-text" "$gitroot" "$run_id" \
        'blocker: plan step id or depends_on entry fails the safe-id charset: "STEP-001\n"'
}

test_trailing_lf_depends_on() {
    local gitroot run_id ledger tmp
    gitroot="$(new_gitroot trailing-lf-depends-on)"
    run_id="nw-trailing-lf-depends-on"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_LINEAR")"
    # Both STEP-001 and "STEP-001<LF>" exist, so the dependency is known and the cycle check
    # passes: only the safe-id check can refuse the trailing line feed.
    tmp="$ledger.seed"
    jq '.plan.steps += [{"id": "STEP-001\n", "files": ["src/lf.ts"]}] | .plan.steps[1].depends_on = ["STEP-001\n"]' "$ledger" > "$tmp" && mv "$tmp" "$ledger"
    assert_blocker_text "line-feed:trailing-lf-depends-on" "$gitroot" "$run_id" \
        'blocker: plan step id or depends_on entry fails the safe-id charset: "STEP-001\n"'
}

test_embedded_lf_run_id() {
    local gitroot
    gitroot="$(new_gitroot embedded-lf-run-id)"
    assert_blocker_text "line-feed:embedded-lf-run-id" "$gitroot" $'ok\n../x' \
        $'blocker: run_id is not a safe path component: ok\n../x'
    assert_blocker_text "line-feed:trailing-lf-run-id" "$gitroot" $'nw-ok\n' \
        $'blocker: run_id is not a safe path component: nw-ok\n'
}

# stage_mutated_ledger <label> <run-id> <jq-filter> -> stages LEDGER_LINEAR under a new gitroot,
# applies <jq-filter> to it, and prints the gitroot.
stage_mutated_ledger() {
    local gitroot ledger tmp
    gitroot="$(new_gitroot "$1")"
    ledger="$(stage_ledger "$gitroot" "$2" "$LEDGER_LINEAR")"
    tmp="$ledger.seed"
    jq "$3" "$ledger" > "$tmp" && mv "$tmp" "$ledger"
    printf '%s' "$gitroot"
}

test_unsafe_duplicate_and_unknown_id_get_charset_blocker() {
    local gitroot oversized
    oversized="$(printf 'S%.0s' $(seq 1 5000))]"
    gitroot="$(stage_mutated_ledger encoded-dup-id nw-encoded-dup-id \
        '.plan.steps[0].id = "A\nforged: x" | .plan.steps[1].id = "A\nforged: x"')"
    assert_blocker_text "line-feed:unsafe-duplicate-id-charset" "$gitroot" nw-encoded-dup-id \
        'blocker: plan step id or depends_on entry fails the safe-id charset: "A\nforged: x"'

    gitroot="$(stage_mutated_ledger encoded-unknown-dep nw-encoded-unknown-dep \
        '.plan.steps[1].depends_on = ["Z\nforged: x"]')"
    assert_blocker_text "line-feed:unsafe-unknown-dep-charset" "$gitroot" nw-encoded-unknown-dep \
        'blocker: plan step id or depends_on entry fails the safe-id charset: "Z\nforged: x"'

    gitroot="$(stage_mutated_ledger oversized-dup-id nw-oversized-dup-id \
        ".plan.steps[0].id = \"$oversized\" | .plan.steps[1].id = \"$oversized\"")"
    assert_blocker_text "line-feed:oversized-unsafe-duplicate-id-charset" "$gitroot" nw-oversized-dup-id \
        "blocker: plan step id or depends_on entry fails the safe-id charset: \"$oversized\""

    gitroot="$(stage_mutated_ledger oversized-unknown-dep nw-oversized-unknown-dep \
        ".plan.steps[1].depends_on = [\"$oversized\"]")"
    assert_blocker_text "line-feed:oversized-unsafe-unknown-dep-charset" "$gitroot" nw-oversized-unknown-dep \
        "blocker: plan step id or depends_on entry fails the safe-id charset: \"$oversized\""
}

test_safe_duplicate_and_unknown_id_encoded() {
    local gitroot
    gitroot="$(stage_mutated_ledger safe-dup-id nw-safe-dup-id '.plan.steps[1].id = .plan.steps[0].id')"
    assert_blocker_text "line-feed:safe-duplicate-id-encoded" "$gitroot" nw-safe-dup-id \
        "blocker: duplicate plan step id: $(jq -c '.plan.steps[0].id' "$LEDGER_LINEAR")"

    gitroot="$(stage_mutated_ledger safe-unknown-dep nw-safe-unknown-dep '.plan.steps[1].depends_on = ["STEP-099"]')"
    assert_blocker_text "line-feed:safe-unknown-dep-encoded" "$gitroot" nw-safe-unknown-dep \
        'blocker: depends_on references unknown step id: "STEP-099"'
}

# ── shape: the positive shape-validation gate rejects malformed plan shapes ──

test_shape_non_object_step() {
    local name="shape:non-object-step"
    local gitroot run_id ledger tmp
    gitroot="$(new_gitroot shape-non-object-step)"
    run_id="nw-shape-non-object-step"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_LINEAR")"
    # Corrupt STEP-001 itself into a non-object (an array) — formerly crashed raw jq at the
    # `.id` index; the shape gate now catches it as a clean blocker BEFORE (a)-(f) ever runs.
    tmp="$ledger.seed"
    jq '.plan.steps[0] = ["x"]' "$ledger" > "$tmp" && mv "$tmp" "$ledger"
    assert_blocker "$name" "$gitroot" "$run_id" "$ledger"
}

test_shape_non_array_depends_on() {
    local name="shape:non-array-depends_on"
    local gitroot run_id ledger tmp
    gitroot="$(new_gitroot shape-non-array-depends-on)"
    run_id="nw-shape-non-array-depends-on"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_LINEAR")"
    # Corrupt STEP-002's depends_on into a non-array string — formerly crashed raw jq on
    # iterate; the shape gate now catches it as a clean blocker.
    tmp="$ledger.seed"
    jq '.plan.steps[1].depends_on = "BAD]"' "$ledger" > "$tmp" && mv "$tmp" "$ledger"
    assert_blocker "$name" "$gitroot" "$run_id" "$ledger"
}

test_shape_non_array_steps() {
    local name="shape:non-array-plan-steps"
    local gitroot run_id ledger tmp
    gitroot="$(new_gitroot shape-non-array-steps)"
    run_id="nw-shape-non-array-steps"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_LINEAR")"
    # Corrupt .plan.steps into a non-array string — formerly PASSED the old (a) non-empty check
    # via `"BAD" // [] | length` (== 3) then crashed at the `.id` index; the shape gate now
    # catches it FIRST, before any later map/iteration ever touches it.
    tmp="$ledger.seed"
    jq '.plan.steps = "BAD"' "$ledger" > "$tmp" && mv "$tmp" "$ledger"
    assert_blocker "$name" "$gitroot" "$run_id" "$ledger"
}

test_shape_non_string_id() {
    local name="shape:non-string-id"
    local gitroot run_id ledger tmp
    gitroot="$(new_gitroot shape-non-string-id)"
    run_id="nw-shape-non-string-id"
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_LINEAR")"
    # Corrupt STEP-001's id into a number — the shape gate rejects a missing-or-non-string id
    # before it ever reaches the SAFE_ID_RE charset check.
    tmp="$ledger.seed"
    jq '.plan.steps[0].id = 123' "$ledger" > "$tmp" && mv "$tmp" "$ledger"
    assert_blocker "$name" "$gitroot" "$run_id" "$ledger"
}

# ── shape: done-set read is type-projected — a malformed event element is skipped, not crashed ──

test_shape_tolerant_malformed_event() {
    local gitroot run_id ledger
    gitroot="$(new_gitroot shape-tolerant-event)"
    run_id="nw-shape-tolerant-event"
    # .events carries a NON-OBJECT element ("junk") alongside a valid completed_steps event
    # crediting STEP-001. Mirrors linear:wave2-advance's staging exactly (LEDGER_LINEAR has no
    # .plan.epoch, so cur=0; the event carries no plan_epoch, so it also defaults to 0 and the
    # credit applies at the ledger's current epoch). The engine must skip "junk" via the
    # `objects` type-projection rather than crash, while the valid event still counts.
    ledger="$(stage_ledger "$gitroot" "$run_id" "$LEDGER_LINEAR" \
        '["junk", {"state":"implement_step","outputs":{"completed_steps":["STEP-001"]}}]')"
    assert_wave "shape:tolerant-malformed-event" "$gitroot" "$run_id" "$ledger" \
        "false" "[STEP-002]" "2"
}

# ── Run all cases ────────────────────────────────────────────────────────────

test_linear
test_diamond
test_overlap
test_glob
test_alias_scope
test_missing_scope
test_cycle
test_empty
test_replan_epoch
test_bad_step_id
test_trailing_lf_step_id
test_trailing_lf_depends_on
test_embedded_lf_run_id
test_unsafe_duplicate_and_unknown_id_get_charset_blocker
test_safe_duplicate_and_unknown_id_encoded
test_shape_non_object_step
test_shape_non_array_depends_on
test_shape_non_array_steps
test_shape_non_string_id
test_shape_tolerant_malformed_event

echo
echo "next-wave engine tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
