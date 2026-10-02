#!/usr/bin/env bash
#
# Shared-library unit runner for the brood-status read-side projection (issue #161).
#
# PURE UNIT TESTS — CI-runnable with ONLY jq present (NO tmux / claude / gh). Exercises the
# three sourced libraries the brood-status-project.sh entrypoint composes:
#   - plugin/skills/_shared/allowlist.sh      (identifier / path / presentation)
#   - plugin/skills/_shared/manifest-json.sh  (hivemind_manifest_strain_names / _field)
#   - plugin/skills/_shared/ledger-project.sh (hivemind_project_run_status / _state_current)
#
# Each lib is SOURCED (these are sourced fragments, not executables) and its functions called
# directly. Mirrors tools/test_brood_compat.sh's pass/fail counter + exit-nonzero-on-failure
# convention. Read-only: the only writes are small inline JSON fixtures in a disposable tmpdir
# removed on EXIT.
#
# Usage:
#   ./tools/test_shared_libs.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SHARED_DIR="$REPO_ROOT/plugin/skills/_shared"
FIX_DIR="$REPO_ROOT/tests/brood"
LEDGER_PRESENT="$FIX_DIR/child-ledger-present.json"

CLASSIFY_FILTER="$REPO_ROOT/plugin/skills/github-review-loop/scripts/fix-history-classify.jq"
FN_REVIEW_HANDLED="$REPO_ROOT/tests/fix-history/case01-handled-by-marker.json"
FN_EXPECTED_REVIEW="$REPO_ROOT/tests/fetch-normalize/expected/review-thread-handled.json"
FN_CI_CHECKS="$REPO_ROOT/tests/fetch-normalize/ci-checks.json"
FN_EXPECTED_CI="$REPO_ROOT/tests/fetch-normalize/expected/ci-only.json"
FN_OVERFLOW_THREADS="$REPO_ROOT/tests/fetch-normalize/overflow-threads.json"
FN_MALFORMED="$REPO_ROOT/tests/fetch-normalize/malformed.json"

for required in "$LEDGER_PRESENT" \
                "$SHARED_DIR/allowlist.sh" "$SHARED_DIR/manifest-json.sh" "$SHARED_DIR/ledger-project.sh" \
                "$SHARED_DIR/brood-status-derive.sh" "$SHARED_DIR/containment.sh" \
                "$SHARED_DIR/ledger-reconstruct-parse.sh" "$SHARED_DIR/ledger-reconstruct-fold.sh" \
                "$SHARED_DIR/fetch-normalize-core.sh" "$SHARED_DIR/ledger-engine-io.sh" \
                "$SHARED_DIR/json-normalize.sh" \
                "$SHARED_DIR/settings-merge.sh" "$SHARED_DIR/claude-mem-path.sh" \
                "$SHARED_DIR/file-guard.sh" "$SHARED_DIR/test-detect.sh" \
                "$SHARED_DIR/graphql-response.sh" \
                "$CLASSIFY_FILTER" \
                "$FN_REVIEW_HANDLED" "$FN_EXPECTED_REVIEW" "$FN_CI_CHECKS" "$FN_EXPECTED_CI" \
                "$FN_OVERFLOW_THREADS" "$FN_MALFORMED"; do
  [ -f "$required" ] || { echo "FAIL: required fixture/lib missing: $required" >&2; exit 2; }
done

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this suite" >&2; exit 2; }

# Source the libs under test.
# shellcheck source=/dev/null
. "$SHARED_DIR/allowlist.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/manifest-json.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/ledger-project.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/brood-status-derive.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/containment.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/ledger-reconstruct-parse.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/ledger-reconstruct-fold.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/fetch-normalize-core.sh"
# ledger-engine-io.sh ORCHESTRATES the containment.sh helpers at call time and does NOT source
# them itself — containment.sh is sourced above (L58), satisfying the dependency contract before
# this source line.
# shellcheck source=/dev/null
. "$SHARED_DIR/ledger-engine-io.sh"
# json-normalize.sh supplies the canon_obj/canon_arr container-shape def text that settings-merge.sh
# splices into its jq program; settings-merge.sh SOURCE-OR-DIE-sources it transitively, but the
# harness lists every lib under test explicitly (presence checked in the required-libs preamble), so
# this explicit source line keeps the listing complete and re-sourcing is idempotent (pure echo fn).
# shellcheck source=/dev/null
. "$SHARED_DIR/json-normalize.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/settings-merge.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/claude-mem-path.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/file-guard.sh"
# test-detect.sh DELEGATES the `## Validation` append to file-guard.sh's
# hivemind_guard_validation_section; file-guard.sh is sourced above (L77), satisfying that
# dependency before this source line.
# shellcheck source=/dev/null
. "$SHARED_DIR/test-detect.sh"
# shellcheck source=/dev/null
. "$SHARED_DIR/graphql-response.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Disposable tmpdir for inline JSON ledger fixtures and side-effect probes.
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-shared-libs.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# assert_eq <case> <expected> <actual> [msg]
assert_eq() {
  local case_name="$1" expected="$2" actual="$3" msg="${4:-}"
  if [ "$expected" = "$actual" ]; then
    pass "$case_name" "${msg:+$msg }(== '$expected')"
  else
    failed "$case_name" "${msg:+$msg }expected '$expected', got '$actual'"
  fi
}

# ── Section 1: allowlist.sh — three value classes sharing one security floor ─────
echo '=== allowlist.sh: identifier / path / presentation ==='

# Side-effect probe: any payload referencing PWN_MARKER must NOT touch it (proves the
# validators never eval/expand command substitution). Cleared once, asserted once at the end.
PWN_MARKER="$WORKDIR/pwn-marker"
rm -f "$PWN_MARKER"

# ── Class 1: identifier (strictest, ^[A-Za-z0-9._/-]+$). ──
for v in "feat/x" "brood-auth" "/abs/path-1.json" "a.b_c" "2026-05-30T22-10-00Z--api"; do
  if hivemind_assert_identifier "$v"; then
    pass "id:accept" "accepted identifier '$v'"
  else
    failed "id:accept" "rejected an identifier that should be safe: '$v'"
  fi
done
# identifier REJECTS space and the path-class inert bytes (those belong to the wider classes).
for v in "" "-rf" "a..b" "x\$(touch $PWN_MARKER)" "\`touch $PWN_MARKER\`" "a b" "a;b" "a#b" "a=b" "a~b" "a!b"; do
  if hivemind_assert_identifier "$v"; then
    failed "id:reject" "accepted a value identifier must reject: '$v'"
  else
    pass "id:reject" "rejected non-identifier '$v'"
  fi
done

# ── Class 2: path (identifier charset PLUS space and inert bytes # = ~ !). ──
# Space-bearing ACCEPTS (the Codex #172 P1 case): a real checkout root with a space.
for v in "/home/me/hive review/wt" "/repo/.claude/worktrees/api" "/home/me/hive#review/wt" "/a/b=c~d!e/wt" "feat/x"; do
  if hivemind_assert_path "$v"; then
    pass "path:accept" "accepted path '$v'"
  else
    failed "path:accept" "rejected a path that should be safe: '$v'"
  fi
done
# path is FLOOR-ONLY (#177/#168 doctrine): the shared floor IS the complete boundary. It STILL
# rejects exactly the floor bytes — command-sub ($/backtick), '..', leading '-', framing bytes
# (TAB/LF/CR), and empty — because those are the only bytes that could break the quoted-data uses
# (`cd "$dir"`, jq --arg, pwd -P). Nothing else is enumerated.
tab=$'\t'; nl=$'\n'; cr=$'\r'; vt=$'\v'; ff=$'\f'
for v in "" "-rf" "/a/../b" "x\$(touch $PWN_MARKER)" "\`touch $PWN_MARKER\`" "a${tab}b" "a${nl}b" "a${cr}b"; do
  if hivemind_assert_path "$v"; then
    failed "path:reject" "accepted a value the path floor must reject: '$v'"
  else
    pass "path:reject" "rejected unsafe path '$v'"
  fi
done
# FLOOR-ONLY CONSEQUENCE (#177 doctrine, locked under #168): bytes that are NOT in the floor are
# ACCEPTED as inert quoted path data — including shell-structural bytes like `; | > & ( )` and the
# non-framing C0 controls VT (\v) / FF (\f). These can never break a command word because a path is
# only ever used as quoted data, never re-parsed; enumerating them was the #177 false-reject
# treadmill. This block LOCKS that they pass (a future re-add of a per-byte charset rule to the path
# class would regress here). Markdown-cell safety for `|` is the render-boundary encoder's job, not
# this class's. (Framing bytes TAB/LF/CR are still floor-rejected above — only the NON-framing
# controls VT/FF pass.)
for v in "a;b" 'a|b' 'a>b' 'a&b' '/a/(b)/wt' "a${vt}b" "a${ff}b"; do
  if hivemind_assert_path "$v"; then
    pass "path:floor-only-inert-accept" "floor-only path accepts inert non-floor byte: '$v'"
  else
    failed "path:floor-only-inert-accept" "floor-only path wrongly rejected inert non-floor byte '$v' (per-byte charset re-added?)"
  fi
done

# ── Class 2b: path-selector (BASE-FLOOR-ONLY — PERMITS `..`; #270 worktree_path selector). ──
# The selector value-class gates brood-status' manifest worktree_path, which is EXACT-MATCHED
# against git's trusted worktree-path set and NEVER traversed. It drops ONLY the `..` reject vs
# the path class (so a legitimate worktree under a `..`-bearing dir name is located instead of
# false-rejected), while STILL rejecting empty, leading-dash, command-sub, and framing bytes.
# ACCEPT: a `..`-bearing value passes (this is the whole point of the class).
for v in "/tmp/hm..repo/wt" "/a/../b" "a..b" "/repo/.claude/worktrees/api" "feat/x"; do
  if hivemind_assert_path_selector "$v"; then
    pass "selector:accept" "path-selector accepted '$v' (permits '..')"
  else
    failed "selector:accept" "path-selector wrongly rejected a value it must permit: '$v'"
  fi
done
# REJECT: the base floor still fires — empty, leading-dash, command-sub ($/backtick), framing.
for v in "" "-rf" "x\$(touch $PWN_MARKER)" "\`touch $PWN_MARKER\`" "a${tab}b" "a${nl}b" "a${cr}b"; do
  if hivemind_assert_path_selector "$v"; then
    failed "selector:reject" "path-selector accepted a value the base floor must reject: '$v'"
  else
    pass "selector:reject" "path-selector rejected base-floor value '$v'"
  fi
done
# DRIFT REGRESSION GUARD: dropping `..` for the SELECTOR class must NOT loosen `..` for the
# path or identifier classes — their values reach cd/--arg/pwd -P/command tokens and keep the
# full floor. A `..`-bearing value MUST still be REJECTED by both.
for v in "/tmp/hm..repo/wt" "/a/../b" "a..b"; do
  if hivemind_assert_path "$v"; then
    failed "selector:path-still-rejects-dotdot" "hivemind_assert_path wrongly accepted a '..' value (full floor relaxed?): '$v'"
  else
    pass "selector:path-still-rejects-dotdot" "hivemind_assert_path still rejects '..' value '$v'"
  fi
  if hivemind_assert_identifier "$v"; then
    failed "selector:id-still-rejects-dotdot" "hivemind_assert_identifier wrongly accepted a '..' value (full floor relaxed?): '$v'"
  else
    pass "selector:id-still-rejects-dotdot" "hivemind_assert_identifier still rejects '..' value '$v'"
  fi
done

# ── Class 3: presentation (positive allowlist; display-only name). ──
# Space-bearing display name ACCEPTS — this is what lets `api worker` render not MALFORMED.
# The permitted set is: A-Za-z0-9 space . _ - / ( ) : , + @ # = ~ !
# `|` is NOT in the permitted set (Markdown table-cell injector — excluded by construction,
# no explicit carve-out required). `;` is also not permitted (shell-structural, not needed).
#
# PRODUCER CONTRACT: these ACCEPT cases are ALSO the spawn-brood.sh strain-name launch gate.
# spawn-brood.sh calls hivemind_assert_presentation at the name-validation point and hard-
# blocks (exit 1, no child launched) on any name outside this class. Producer and consumer
# share this single validator — the tests below document both roles simultaneously.
for v in "api worker" "api" "api-slice" "api/v2" "feature (2)" "a.b_c" "a#b" "a (worker)" "a/b-c.d_e"; do
  if hivemind_assert_presentation "$v"; then
    pass "pres:accept" "accepted presentation value '$v'"
  else
    failed "pres:accept" "rejected a presentation value that should render: '$v'"
  fi
done
# PRODUCER CONTRACT: these REJECT cases are ALSO names that spawn-brood.sh must never launch.
# Each entry proves a class of invalid strain name is hard-blocked at the producer before any
# child session is created — `api & web`, `a;b`, `a|b`, and non-ASCII names all fall here.
# presentation enforces the shared floor (command-sub, '..', leading '-', framing) AND rejects
# bytes not in the positive allowlist — each entry below proves a treadmill byte is closed BY
# CONSTRUCTION (the byte is simply absent from the allowlist), not by a specific carve-out.
esc=$'\033'; del=$'\177'; bidi=$'\xe2\x80\xae'
for v in \
  "" "-x" "a..b" \
  "x\$(touch $PWN_MARKER)" "\`touch $PWN_MARKER\`" \
  "a${tab}b" "a${nl}b" "a${cr}b" \
  "a${esc}b" "a${vt}b" "a${ff}b" "a${del}b" \
  "a${bidi}b" \
  'a|b' 'a<b' 'a>b' 'a;b' 'a&b' "api & web"; do
  if hivemind_assert_presentation "$v"; then
    failed "pres:reject" "accepted a value the presentation allowlist must reject: '$v'"
  else
    pass "pres:reject" "rejected non-allowlist presentation value '$v'"
  fi
done

# No payload across ANY class created the marker (proves no command substitution ran).
if [ -e "$PWN_MARKER" ]; then
  failed "allow:no-side-effect" "a command-sub payload created the side-effect marker $PWN_MARKER"
else
  pass "allow:no-side-effect" "no command-sub payload created a side-effect file"
fi

# ── Section 2: manifest-json.sh ─────────────────────────────────────────────────
echo ''
echo '=== manifest-json.sh: hivemind_manifest_strain_names / hivemind_manifest_field ==='
#
# JSON manifests are built inline in WORKDIR so this section is self-contained (the shared
# JSON manifest fixtures under tests/brood/ are owned by STEP-004). Each fixture mirrors the
# shape spawn-brood.sh's jq emitter writes (manifest_version 3): a top-level object with a
# `strains` array; each strain carries name/worktree_path/branch/tmux_session/status and a
# nested `run` object.

# v3 manifest with a single "api" strain carrying a full run block.
MANIFEST_V3="$WORKDIR/manifest-v3.json"
jq -n '{
  manifest_version: 3,
  brood_id: "2026-05-30T22-10-00Z",
  strains: [
    {
      name: "api",
      description: "Implement the API slice.",
      worktree_path: "/repo/.claude/worktrees/api",
      branch: "feature/api-slice",
      tmux_session: "brood-api",
      status: "running",
      pr: null, merged: false, rebased_after: [],
      run: {
        suggested_id: "2026-05-30T22-10-00Z--api",
        suggested_ledger: "/repo/.claude/worktrees/api/.hivemind/runs/2026-05-30T22-10-00Z--api/state.json",
        workflow_hint: "standard-delivery"
      }
    }
  ],
  merge_order: []
}' > "$MANIFEST_V3"

assert_eq "manifest:v3-names" "api" \
  "$(hivemind_manifest_strain_names "$MANIFEST_V3")" "v3 strain names"
assert_eq "manifest:v3-worktree" "/repo/.claude/worktrees/api" \
  "$(hivemind_manifest_field "$MANIFEST_V3" "api" "worktree_path")" "v3 worktree_path"
assert_eq "manifest:v3-branch" "feature/api-slice" \
  "$(hivemind_manifest_field "$MANIFEST_V3" "api" "branch")" "v3 branch"
assert_eq "manifest:v3-tmux" "brood-api" \
  "$(hivemind_manifest_field "$MANIFEST_V3" "api" "tmux_session")" "v3 tmux_session"
assert_eq "manifest:v3-status" "running" \
  "$(hivemind_manifest_field "$MANIFEST_V3" "api" "status")" "v3 status"
assert_eq "manifest:v3-suggested-id" "2026-05-30T22-10-00Z--api" \
  "$(hivemind_manifest_field "$MANIFEST_V3" "api" "run.suggested_id")" "v3 run.suggested_id"
assert_eq "manifest:v3-suggested-ledger" "/repo/.claude/worktrees/api/.hivemind/runs/2026-05-30T22-10-00Z--api/state.json" \
  "$(hivemind_manifest_field "$MANIFEST_V3" "api" "run.suggested_ledger")" "v3 run.suggested_ledger"
assert_eq "manifest:v3-workflow-hint" "standard-delivery" \
  "$(hivemind_manifest_field "$MANIFEST_V3" "api" "workflow_hint")" "v3 workflow_hint"

# run.* prefix parity: bare field name resolves the same as the run.-prefixed name.
assert_eq "manifest:v3-suggested-ledger-bare" "/repo/.claude/worktrees/api/.hivemind/runs/2026-05-30T22-10-00Z--api/state.json" \
  "$(hivemind_manifest_field "$MANIFEST_V3" "api" "suggested_ledger")" "v3 suggested_ledger (bare name)"

# A v1-shape manifest (no run block): static fields extract, run.* fields are empty.
MANIFEST_NORUN="$WORKDIR/manifest-norun.json"
jq -n '{
  manifest_version: 3,
  strains: [
    { name: "api", worktree_path: "/repo/.claude/worktrees/api",
      branch: "feature/api-slice", tmux_session: "brood-api", status: "running" }
  ]
}' > "$MANIFEST_NORUN"
assert_eq "manifest:norun-names" "api" \
  "$(hivemind_manifest_strain_names "$MANIFEST_NORUN")" "no-run strain names"
assert_eq "manifest:norun-branch" "feature/api-slice" \
  "$(hivemind_manifest_field "$MANIFEST_NORUN" "api" "branch")" "no-run branch"
assert_eq "manifest:norun-suggested-ledger-empty" "" \
  "$(hivemind_manifest_field "$MANIFEST_NORUN" "api" "run.suggested_ledger")" "no run block → empty"

# Absent strain → empty.
assert_eq "manifest:absent-strain" "" \
  "$(hivemind_manifest_field "$MANIFEST_V3" "nope" "branch")" "absent strain yields empty"

# Absent / unparseable manifest → empty, never an error (caller treats as no fields).
assert_eq "manifest:absent-file-names" "" \
  "$(hivemind_manifest_strain_names "$WORKDIR/does-not-exist.json")" "absent manifest → no names"
TORN_MANIFEST="$WORKDIR/torn-manifest.json"
printf '{"strains":[{"name":"api"\n' > "$TORN_MANIFEST"
assert_eq "manifest:torn-names" "" \
  "$(hivemind_manifest_strain_names "$TORN_MANIFEST")" "torn manifest → no names"
assert_eq "manifest:torn-field" "" \
  "$(hivemind_manifest_field "$TORN_MANIFEST" "api" "branch")" "torn manifest → empty field"

# ── Hostile-content containment (the WHOLE POINT of the JSON flip) ───────────────
# A strain `description` string carries untrusted issue-sourced free text. The text embeds
# counterfeit `status: failed`, a `worktree_path:` line, and a command-substitution payload.
# Because the manifest is JSON parsed by jq, the description is JUST A STRING VALUE — jq can
# never re-parse its bytes as sibling keys. The genuine fields MUST be returned unchanged and
# no command substitution can run. This is the injection class that the YAML reader had to
# defend against with block-scalar-aware awk, now DEAD BY CONSTRUCTION.
MANIFEST_HOSTILE="$WORKDIR/manifest-hostile.json"
HOSTILE_DESC='Implement the API slice.
status: failed
worktree_path: /attacker/escape
$(touch '"$PWN_MARKER"')
- name: injected-strain'
jq -n --arg d "$HOSTILE_DESC" '{
  manifest_version: 3,
  strains: [
    {
      name: "api",
      description: $d,
      worktree_path: "/repo/.claude/worktrees/api",
      branch: "feature/api-slice",
      tmux_session: "brood-api",
      status: "running",
      run: { suggested_ledger: "/repo/.claude/worktrees/api/.hivemind/runs/2026-05-30T22-10-00Z--api/state.json" }
    }
  ]
}' > "$MANIFEST_HOSTILE"

# The hostile description's injected `- name:` line is NOT a second strain.
assert_eq "manifest:hostile-names" "api" \
  "$(hivemind_manifest_strain_names "$MANIFEST_HOSTILE")" "injected name in description string is not a strain"
# Genuine status wins over the counterfeit "status: failed" inside the description string.
assert_eq "manifest:hostile-status" "running" \
  "$(hivemind_manifest_field "$MANIFEST_HOSTILE" "api" "status")" "counterfeit status in description is inert"
assert_eq "manifest:hostile-worktree" "/repo/.claude/worktrees/api" \
  "$(hivemind_manifest_field "$MANIFEST_HOSTILE" "api" "worktree_path")" "counterfeit worktree_path in description is inert"
assert_eq "manifest:hostile-branch" "feature/api-slice" \
  "$(hivemind_manifest_field "$MANIFEST_HOSTILE" "api" "branch")" "genuine branch returned"
assert_eq "manifest:hostile-ledger" "/repo/.claude/worktrees/api/.hivemind/runs/2026-05-30T22-10-00Z--api/state.json" \
  "$(hivemind_manifest_field "$MANIFEST_HOSTILE" "api" "run.suggested_ledger")" "genuine run.suggested_ledger returned"
# The command-substitution payload in the description never ran (re-uses the Section 1 marker).
if [ -e "$PWN_MARKER" ]; then
  failed "manifest:hostile-no-side-effect" "description command-sub payload created $PWN_MARKER"
else
  pass "manifest:hostile-no-side-effect" "description command-sub payload did not execute"
fi

# ── Single-snapshot content helpers: shape validation + index extraction ─────────
# hivemind_manifest_validate_shape folds the old `jq empty` syntax probe into a shape check:
# `.strains` must EXIST as an ARRAY with every element an OBJECT. The content-snapshot helpers
# (count_snapshot / field_at) operate on the in-memory snapshot the engine reads ONCE.

# A valid full manifest passes shape validation.
V3_CONTENT="$(cat "$MANIFEST_V3")"
if hivemind_manifest_validate_shape "$V3_CONTENT"; then
  pass "shape:v3-valid" "full v3 manifest passes shape validation"
else
  failed "shape:v3-valid" "full v3 manifest rejected by shape validation"
fi
# A valid EMPTY manifest ({"strains":[]}) passes (all() over an empty array is true) — legit
# empty brood, NOT unreadable.
if hivemind_manifest_validate_shape '{"strains":[]}'; then
  pass "shape:empty-valid" "valid empty manifest passes shape validation"
else
  failed "shape:empty-valid" "valid empty manifest wrongly rejected by shape validation"
fi
# Wrong-shape / invalid manifests must FAIL shape validation: missing .strains, null .strains,
# non-array .strains, non-object element, and syntactically-invalid JSON (folds the old jq empty).
for bad in '{}' '{"strains":null}' '{"strains":"x"}' '{"strains":[1]}' '{"strains":[{"name":"a"}'; do
  if hivemind_manifest_validate_shape "$bad"; then
    failed "shape:reject" "wrong-shape/invalid manifest wrongly passed shape validation: $bad"
  else
    pass "shape:reject" "wrong-shape/invalid manifest rejected: $bad"
  fi
done
# An object element MISSING `name` still passes shape (it is an object) — per-strain field
# degradation is the contract, not a whole-manifest structural failure.
if hivemind_manifest_validate_shape '{"strains":[{}]}'; then
  pass "shape:object-no-name" "object element missing name passes shape (per-strain degradation, not structural)"
else
  failed "shape:object-no-name" "object element missing name wrongly rejected by shape validation"
fi

# Strain count from the in-memory snapshot.
assert_eq "snapshot:v3-count" "1" \
  "$(hivemind_manifest_strain_count_snapshot "$V3_CONTENT")" "v3 strain count from snapshot"
assert_eq "snapshot:empty-count" "0" \
  "$(hivemind_manifest_strain_count_snapshot '{"strains":[]}')" "empty manifest strain count from snapshot"

# Index-based field extraction against the snapshot resolves the same values as the path-based
# pair, selecting by position rather than by name.
assert_eq "snapshot:v3-field-branch" "feature/api-slice" \
  "$(hivemind_manifest_field_at "$V3_CONTENT" 0 "branch")" "field_at branch at index 0"
assert_eq "snapshot:v3-field-worktree" "/repo/.claude/worktrees/api" \
  "$(hivemind_manifest_field_at "$V3_CONTENT" 0 "worktree_path")" "field_at worktree_path at index 0"
assert_eq "snapshot:v3-field-ledger" "/repo/.claude/worktrees/api/.hivemind/runs/2026-05-30T22-10-00Z--api/state.json" \
  "$(hivemind_manifest_field_at "$V3_CONTENT" 0 "run.suggested_ledger")" "field_at run.suggested_ledger at index 0"
# An object element missing `name`/run fields → field_at yields empty (// empty), never an error.
assert_eq "snapshot:objnoname-field" "" \
  "$(hivemind_manifest_field_at '{"strains":[{}]}' 0 "branch")" "field_at on fieldless object → empty"

# ── Section 3: ledger-project.sh ────────────────────────────────────────────────
echo ''
echo '=== ledger-project.sh: hivemind_project_run_status / hivemind_project_state_current ==='

# Valid fixture: status=running, state.current=implement_step.
assert_eq "ledger:valid-status" "running" \
  "$(hivemind_project_run_status "$LEDGER_PRESENT")" "valid run.status from fixture"
assert_eq "ledger:valid-state" "implement_step" \
  "$(hivemind_project_state_current "$LEDGER_PRESENT")" "valid state.current from fixture"

# status outside the enum → MALFORMED.
bad_status="$WORKDIR/bad-status.json"
printf '{"run":{"status":"frobnicate"},"state":{"current":"plan"}}\n' > "$bad_status"
assert_eq "ledger:status-out-of-enum" "MALFORMED" \
  "$(hivemind_project_run_status "$bad_status")" "status outside enum"
# ...but the state.current on the SAME file is good → per-scalar independence.
assert_eq "ledger:independence-state-good" "plan" \
  "$(hivemind_project_state_current "$bad_status")" "good state.current despite bad status (independence)"

# state.current with uppercase / space / metachars → MALFORMED; run.status good → independence.
for bad_state in "Implement_Step" "implement step" "x\$(touch /tmp/should-not-run)"; do
  bad_state_file="$WORKDIR/bad-state.json"
  jq -n --arg s "$bad_state" '{run:{status:"running"},state:{current:$s}}' > "$bad_state_file"
  assert_eq "ledger:state-malformed" "MALFORMED" \
    "$(hivemind_project_state_current "$bad_state_file")" "malformed state '$bad_state'"
  assert_eq "ledger:independence-status-good" "running" \
    "$(hivemind_project_run_status "$bad_state_file")" "good run.status despite bad state (independence)"
done

# state.current > 64 chars → MALFORMED (even though all-lowercase a-z0-9_).
long_state="$WORKDIR/long-state.json"
long_val="$(printf 'a%.0s' $(seq 1 65))"   # 65 lowercase 'a' chars
jq -n --arg s "$long_val" '{run:{status:"complete"},state:{current:$s}}' > "$long_state"
assert_eq "ledger:state-too-long" "MALFORMED" \
  "$(hivemind_project_state_current "$long_state")" "state.current 65 chars (>64 cap)"
# Exactly 64 chars must PASS (boundary).
ok_state="$WORKDIR/ok-state.json"
ok_val="$(printf 'a%.0s' $(seq 1 64))"
jq -n --arg s "$ok_val" '{run:{status:"complete"},state:{current:$s}}' > "$ok_state"
assert_eq "ledger:state-64-ok" "$ok_val" \
  "$(hivemind_project_state_current "$ok_state")" "state.current exactly 64 chars passes"

# Absent file → MISSING for both scalars.
assert_eq "ledger:absent-file-status" "MISSING" \
  "$(hivemind_project_run_status "$WORKDIR/does-not-exist.json")" "absent file run.status"
assert_eq "ledger:absent-file-state" "MISSING" \
  "$(hivemind_project_state_current "$WORKDIR/does-not-exist.json")" "absent file state.current"

# Present-but-UNREADABLE file → MALFORMED for both scalars (distinct from the absent-file
# MISSING case above). The wrapper passes its leading [ -f ] guard, then `cat` FAILS; the
# post-failure [ -e ] re-test confirms presence → MALFORMED, never MISSING. mode 000 does
# not restrict root, so guard the assertions.
if [ "$(id -u)" -ne 0 ]; then
  unreadable="$WORKDIR/unreadable.json"
  printf '{"run":{"status":"running"},"state":{"current":"plan"}}\n' > "$unreadable"
  chmod 000 "$unreadable"
  assert_eq "ledger:unreadable-status" "MALFORMED" \
    "$(hivemind_project_run_status "$unreadable")" "present-but-unreadable run.status → MALFORMED"
  assert_eq "ledger:unreadable-state" "MALFORMED" \
    "$(hivemind_project_state_current "$unreadable")" "present-but-unreadable state.current → MALFORMED"
  chmod 644 "$unreadable" 2>/dev/null || true
fi

# Field present in a parseable file but empty/absent → MISSING (distinct from MALFORMED).
empty_fields="$WORKDIR/empty-fields.json"
printf '{"run":{},"state":{}}\n' > "$empty_fields"
assert_eq "ledger:empty-status" "MISSING" \
  "$(hivemind_project_run_status "$empty_fields")" "absent run.status field → MISSING"
assert_eq "ledger:empty-state" "MISSING" \
  "$(hivemind_project_state_current "$empty_fields")" "absent state.current field → MISSING"

# Unparseable / torn JSON → MALFORMED for both scalars.
torn="$WORKDIR/torn.json"
printf '{"run":{"status":"run\n' > "$torn"   # truncated mid-object
assert_eq "ledger:torn-status" "MALFORMED" \
  "$(hivemind_project_run_status "$torn")" "torn JSON run.status"
assert_eq "ledger:torn-state" "MALFORMED" \
  "$(hivemind_project_state_current "$torn")" "torn JSON state.current"

# Each enum value round-trips.
for st in running complete blocked cancelled; do
  enum_file="$WORKDIR/enum-$st.json"
  printf '{"run":{"status":"%s"},"state":{"current":"plan"}}\n' "$st" > "$enum_file"
  assert_eq "ledger:enum-$st" "$st" \
    "$(hivemind_project_run_status "$enum_file")" "enum value $st"
done

# ── Section 3b: hivemind_read_confined_state_current — two-line confined read ────
echo ''
echo '=== ledger-project.sh: hivemind_read_confined_state_current (two-line confined read) ==='
#
# AUTHORITATIVE regression tests for the shared confined read primitive. This function is the
# SINGLE source of the 6-layer hardened confined read consumed by both spawn-brood and
# brood-status-project.sh. Each case builds a real temp worktree + ledger under WORKDIR and
# asserts the two-line output (line1=state.current, line2=run.status).
#
# Parse helper — safe under set -u: reads exactly two lines from the function's stdout.
# Usage: { IFS= read -r rcc_s; IFS= read -r rcc_r; } < <(hivemind_read_confined_state_current ...)
# then assert_eq on $rcc_s / $rcc_r.

# 3b-1: valid ledger — both scalars present and well-formed.
rcc1_wt="$WORKDIR/rcc1/checkout"
rcc1_run_id="2026-01-01T00-00-00Z--test"
rcc1_rel=".hivemind/runs/$rcc1_run_id/state.json"
mkdir -p "$rcc1_wt/.hivemind/runs/$rcc1_run_id"
printf '{"state":{"current":"implement_step"},"run":{"status":"running"}}\n' \
  > "$rcc1_wt/$rcc1_rel"
{ IFS= read -r rcc_s; IFS= read -r rcc_r; } \
  < <(hivemind_read_confined_state_current "$rcc1_wt" "$rcc1_rel")
assert_eq "rcc:valid-state"  "implement_step" "$rcc_s" "valid ledger: line1 = state.current"
assert_eq "rcc:valid-status" "running"        "$rcc_r" "valid ledger: line2 = run.status"

# 3b-2: absent leaf — no state.json written yet → MISSING / MISSING.
rcc2_wt="$WORKDIR/rcc2/checkout"
rcc2_run_id="2026-01-01T00-00-00Z--test"
rcc2_rel=".hivemind/runs/$rcc2_run_id/state.json"
mkdir -p "$rcc2_wt/.hivemind/runs/$rcc2_run_id"
# Do NOT create the leaf — child has not yet written its ledger.
{ IFS= read -r rcc_s; IFS= read -r rcc_r; } \
  < <(hivemind_read_confined_state_current "$rcc2_wt" "$rcc2_rel")
assert_eq "rcc:absent-state"  "MISSING" "$rcc_s" "absent leaf: line1 = MISSING"
assert_eq "rcc:absent-status" "MISSING" "$rcc_r" "absent leaf: line2 = MISSING"

# 3b-3: symlinked leaf — state.json is a symlink → MALFORMED / MALFORMED.
# hivemind_assert_file_contained fires [ -L ] on the leaf; any symlink leaf is rejected
# before the read (LAYER 1).
rcc3_wt="$WORKDIR/rcc3/checkout"
rcc3_ext="$WORKDIR/rcc3/external"
rcc3_run_id="2026-01-01T00-00-00Z--test"
rcc3_rel=".hivemind/runs/$rcc3_run_id/state.json"
mkdir -p "$rcc3_wt/.hivemind/runs/$rcc3_run_id" "$rcc3_ext"
printf '{"state":{"current":"implement_step"},"run":{"status":"running"}}\n' \
  > "$rcc3_ext/real-state.json"
ln -s "$rcc3_ext/real-state.json" "$rcc3_wt/$rcc3_rel"
{ IFS= read -r rcc_s; IFS= read -r rcc_r; } \
  < <(hivemind_read_confined_state_current "$rcc3_wt" "$rcc3_rel" 2>/dev/null)
assert_eq "rcc:symlink-leaf-state"  "MALFORMED" "$rcc_s" "symlinked leaf: line1 = MALFORMED"
assert_eq "rcc:symlink-leaf-status" "MALFORMED" "$rcc_r" "symlinked leaf: line2 = MALFORMED"

# 3b-4: NUL-bearing ledger — file exists, otherwise valid JSON, but contains a literal NUL byte.
# hivemind_path_has_nul fires at LAYER 4, before the $(...) read strips the NUL → MALFORMED.
rcc4_wt="$WORKDIR/rcc4/checkout"
rcc4_run_id="2026-01-01T00-00-00Z--test"
rcc4_rel=".hivemind/runs/$rcc4_run_id/state.json"
mkdir -p "$rcc4_wt/.hivemind/runs/$rcc4_run_id"
printf '{"state":{"current":"implement_step"},"run":{"status":"running"}}\000' \
  > "$rcc4_wt/$rcc4_rel"
{ IFS= read -r rcc_s; IFS= read -r rcc_r; } \
  < <(hivemind_read_confined_state_current "$rcc4_wt" "$rcc4_rel")
assert_eq "rcc:nul-ledger-state"  "MALFORMED" "$rcc_s" "NUL-bearing ledger: line1 = MALFORMED"
assert_eq "rcc:nul-ledger-status" "MALFORMED" "$rcc_r" "NUL-bearing ledger: line2 = MALFORMED"

# 3b-5: ancestor-symlink escape — a directory component of the ledger chain is a symlink that
# resolves outside the worktree. hivemind_assert_file_contained walks every existing ancestor
# and rejects on the first symlinked component (LAYER 1), so both scalars are MALFORMED.
# NOTE: faithfully constructing a post-read ITEM-4 ancestor-swap race in a unit test is
# impractical (it requires a concurrent writer between LAYER 1 and the cat). This case instead
# asserts the LAYER 1 pre-read ancestor-symlink containment-reject path, which is the structural
# defence (the ITEM-4 post-read check bounds the residual window that LAYER 1 cannot close).
rcc5_wt="$WORKDIR/rcc5/checkout"
rcc5_ext="$WORKDIR/rcc5/external"
rcc5_run_id="2026-01-01T00-00-00Z--test"
rcc5_rel=".hivemind/runs/$rcc5_run_id/state.json"
mkdir -p "$rcc5_wt" "$rcc5_ext/runs/$rcc5_run_id"
# .hivemind itself is a symlink to the external dir — every ancestor walk hits it and rejects.
ln -s "$rcc5_ext" "$rcc5_wt/.hivemind"
printf '{"state":{"current":"implement_step"},"run":{"status":"running"}}\n' \
  > "$rcc5_wt/$rcc5_rel"
{ IFS= read -r rcc_s; IFS= read -r rcc_r; } \
  < <(hivemind_read_confined_state_current "$rcc5_wt" "$rcc5_rel" 2>/dev/null)
assert_eq "rcc:ancestor-escape-state"  "MALFORMED" "$rcc_s" "ancestor symlink escape: line1 = MALFORMED"
assert_eq "rcc:ancestor-escape-status" "MALFORMED" "$rcc_r" "ancestor symlink escape: line2 = MALFORMED"

# 3b-6: present-but-unreadable leaf → MALFORMED / MALFORMED.
# Technique: place a DIRECTORY at the state.json path (not chmod 000, which is bypassed by
# root). `cat -- <dir>` fails (Is a directory), [ -e ] confirms presence → MALFORMED.
# This is root-safe: no filesystem permission required; a directory is never a regular file.
rcc6_wt="$WORKDIR/rcc6/checkout"
rcc6_run_id="2026-01-01T00-00-00Z--test"
rcc6_rel=".hivemind/runs/$rcc6_run_id/state.json"
# mkdir -p creates the full chain INCLUDING the leaf, making state.json itself a directory.
mkdir -p "$rcc6_wt/$rcc6_rel"
{ IFS= read -r rcc_s; IFS= read -r rcc_r; } \
  < <(hivemind_read_confined_state_current "$rcc6_wt" "$rcc6_rel" 2>/dev/null)
assert_eq "rcc:dir-leaf-state"  "MALFORMED" "$rcc_s" "dir-typed leaf (present-but-unreadable): line1 = MALFORMED"
assert_eq "rcc:dir-leaf-status" "MALFORMED" "$rcc_r" "dir-typed leaf (present-but-unreadable): line2 = MALFORMED"

# ── Section 4: NUL / control-byte rejection + single-document discipline (Codex #172) ──
echo ''
echo '=== NUL + control-byte + single-document (Codex #172 root cluster) ==='
#
# ROOT (documented at each fix site): bash command substitution `$(...)` SILENTLY STRIPS NUL
# bytes, so a value validated AFTER a `$(...)` round-trip differs from what jq produced. Defended
# at TWO layers: (1) FILE-LEVEL — reject any manifest/ledger file containing a LITERAL NUL byte
# before it is read into a shell var (hivemind_path_has_nul); (2) SCALAR-LEVEL — every jq field
# projection whose output bash consumes rejects a value containing ANY C0 control byte INSIDE jq
# (so a JSON ` ` escape jq -r would decode to a real NUL is caught while the bytes are intact).
# Plus: jq accepts a STREAM of documents, so shape validation now requires EXACTLY ONE document.

# ── 4a. hivemind_path_has_nul: byte-accurate literal-NUL detection ──
nul_file="$WORKDIR/has-nul.bin"
printf '{"run":{"status":"running"}}\000\n' > "$nul_file"   # literal NUL embedded via \000
clean_file="$WORKDIR/no-nul.json"
printf '{"run":{"status":"running"}}\n' > "$clean_file"
if hivemind_path_has_nul "$nul_file"; then
  pass "nul:detect-present" "hivemind_path_has_nul detects a literal NUL byte"
else
  failed "nul:detect-present" "hivemind_path_has_nul missed a literal NUL byte"
fi
if hivemind_path_has_nul "$clean_file"; then
  failed "nul:detect-absent" "hivemind_path_has_nul false-positived on a clean file"
else
  pass "nul:detect-absent" "hivemind_path_has_nul reports no NUL on a clean file"
fi

# ── 4b. Ledger wrapper: a ledger file with a LITERAL NUL → MALFORMED (both scalars) ──
# The on-disk JSON is otherwise valid; the trailing literal NUL would be stripped by the `$(...)`
# read, so the file-level guard must reject it as MALFORMED before any read.
nul_ledger="$WORKDIR/nul-ledger.json"
printf '{"run":{"status":"running"},"state":{"current":"plan"}}\000' > "$nul_ledger"
assert_eq "ledger:literal-nul-status" "MALFORMED" \
  "$(hivemind_project_run_status "$nul_ledger")" "literal-NUL ledger run.status → MALFORMED"
assert_eq "ledger:literal-nul-state" "MALFORMED" \
  "$(hivemind_project_state_current "$nul_ledger")" "literal-NUL ledger state.current → MALFORMED"

# ── 4c. Scalar-level: a JSON ` ` ESCAPE (valid JSON) → field projects EMPTY, not stripped ──
# The FILE has no literal NUL (the escape is 6 ASCII bytes \u0000), so the file-level check misses
# it; the in-jq control-byte gate must reject it so bash never receives a NUL-stripped value. The
# branch value `feature/api\u0000-slice` must NOT project as the trusted-looking `feature/api-slice`.
nulesc_content="$(printf '%s' '{"strains":[{"name":"api","branch":"feature/api\u0000-slice","worktree_path":"/repo/wt","status":"running"}]}')"
assert_eq "scalar:nul-escape-branch-empty" "" \
  "$(hivemind_manifest_field_at "$nulesc_content" 0 "branch")" "JSON \\u0000 escape in branch → field_at empty (NOT control-stripped)"
# A clean branch on the same shape still projects.
clean_content="$(printf '%s' '{"strains":[{"name":"api","branch":"feature/api-slice","worktree_path":"/repo/wt","status":"running"}]}')"
assert_eq "scalar:clean-branch-projects" "feature/api-slice" \
  "$(hivemind_manifest_field_at "$clean_content" 0 "branch")" "clean branch still projects via field_at"
# A mid-range control escape (TAB, \u0009) is also rejected — proves the whole C0 range, not just NUL.
tabesc_content="$(printf '%s' '{"strains":[{"name":"api","branch":"feat\u0009x","worktree_path":"/repo/wt","status":"running"}]}')"
assert_eq "scalar:tab-escape-branch-empty" "" \
  "$(hivemind_manifest_field_at "$tabesc_content" 0 "branch")" "JSON \\u0009 (TAB) escape in branch → field_at empty"
# A scalar NUL escape in a ledger state.current → MALFORMED (the in-jq charset gate sees it intact).
nulesc_state="$(printf '%s' '{"run":{"status":"running"},"state":{"current":"impl\u0000ement"}}')"
assert_eq "scalar:nul-escape-state-malformed" "MALFORMED" \
  "$(hivemind_project_state_current_content "$nulesc_state")" "JSON \\u0000 escape in state.current → MALFORMED"

# ── 4d. Single-document discipline: a multi-document file FAILS shape validation ──
# jq accepts a STREAM of concatenated JSON documents; shape validation must require EXACTLY ONE.
# Two valid manifest objects concatenated → length>1 → rejected (would otherwise project as empty).
multidoc="$(printf '%s\n%s\n' '{"strains":[{"name":"api"}]}' '{"strains":[{"name":"web"}]}')"
if hivemind_manifest_validate_shape "$multidoc"; then
  failed "multidoc:reject" "two concatenated manifest documents wrongly passed shape validation"
else
  pass "multidoc:reject" "two concatenated manifest documents rejected by shape validation (single-document required)"
fi
# A single valid document still passes (regression guard for the slurp predicate).
if hivemind_manifest_validate_shape "$V3_CONTENT"; then
  pass "multidoc:single-ok" "single valid manifest document still passes shape validation after slurp"
else
  failed "multidoc:single-ok" "slurp predicate wrongly rejected a single valid manifest document"
fi
# count + field_at over the single document remain correct under the slurp (regression).
assert_eq "multidoc:single-count" "1" \
  "$(hivemind_manifest_strain_count_snapshot "$V3_CONTENT")" "slurp count over single document"
assert_eq "multidoc:single-field" "feature/api-slice" \
  "$(hivemind_manifest_field_at "$V3_CONTENT" 0 "branch")" "slurp field_at over single document"

# ── Section 5: #168 brood-namespacing + #178 hardening contract regressions ──────
echo ''
echo '=== #168/#178: floor-only path class + content projectors + field_at exit-code contract ==='

# ── 5a. path class is FLOOR-ONLY (#177/#168): formerly-rejected inert bytes now PASS ──
# allowlist.sh hivemind_assert_path is the FLOOR-ONLY class: any byte that survives the shared
# security floor is accepted as quoted path data. The bytes `+ @ , %` were rejected by the OLD
# per-byte charset enumeration (the #177 whack-a-mole treadmill); under floor-only they must now
# PASS. This is the doctrine guard — a future re-add of per-byte charset rules to the path class
# would fail these.
for v in "/a/b+c/wt" "/a/b@c/wt" "/a/b,c/wt" "/a/b%c/wt" "/home/me/a+b@c,d%e/wt"; do
  if hivemind_assert_path "$v"; then
    pass "path:floor-only-accept" "floor-only path accepts formerly-rejected inert byte: '$v'"
  else
    failed "path:floor-only-accept" "floor-only path wrongly rejected inert-byte path '$v' (per-byte charset re-added?)"
  fi
done
# The floor itself is NEVER relaxed by floor-only: command-sub ($/backtick), '..', leading '-',
# framing bytes (TAB/LF/CR), and empty must STILL reject under the path class.
ptab=$'\t'; pnl=$'\n'; pcr=$'\r'
for v in "" "-x" "/a/../b" "a\$b" "a\`b" "a${ptab}b" "a${pnl}b" "a${pcr}b"; do
  if hivemind_assert_path "$v"; then
    failed "path:floor-still-rejects" "floor-only path accepted a value the floor must reject: '$v'"
  else
    pass "path:floor-still-rejects" "floor still rejects under path class: '$v'"
  fi
done
# identifier remains STRICT: the same inert bytes the path class now accepts are STILL rejected by
# the identifier class (no floor-only loosening of the strict class).
for v in "a+b" "a@b" "a,b" "a%b"; do
  if hivemind_assert_identifier "$v"; then
    failed "id:still-strict" "identifier wrongly accepted an inert byte (must stay strict): '$v'"
  else
    pass "id:still-strict" "identifier stays strict; rejects inert byte: '$v'"
  fi
done
# presentation STILL rejects the Markdown-cell delimiter `|` by construction (not in the
# positive allowlist; render-boundary owns the escape).
if hivemind_assert_presentation 'api|web'; then
  failed "pres:pipe-rejected" "presentation wrongly accepted '|' (Markdown-cell injector)"
else
  pass "pres:pipe-rejected" "presentation rejects '|' by construction"
fi

# ── 5b. #178 F1: content projectors require EXACTLY ONE document ──────────────────
# The _content projectors SLURP and require length==1. TWO concatenated valid ledger objects →
# MALFORMED (both run.status + state.current), because the embedded newline of a two-document
# emission would corrupt the one-line STRAIN frame. Single valid → value. Empty → MISSING.
two_ledgers="$(printf '%s\n%s\n' \
  '{"run":{"status":"running"},"state":{"current":"plan"}}' \
  '{"run":{"status":"complete"},"state":{"current":"review"}}')"
assert_eq "f1:multidoc-run-status" "MALFORMED" \
  "$(hivemind_project_run_status_content "$two_ledgers")" "two concatenated ledger docs → run.status MALFORMED"
assert_eq "f1:multidoc-state-current" "MALFORMED" \
  "$(hivemind_project_state_current_content "$two_ledgers")" "two concatenated ledger docs → state.current MALFORMED"
# A SINGLE valid document still projects its scalars (regression guard for the slurp predicate).
one_ledger='{"run":{"status":"blocked"},"state":{"current":"implement_step"}}'
assert_eq "f1:single-run-status" "blocked" \
  "$(hivemind_project_run_status_content "$one_ledger")" "single ledger doc → run.status value"
assert_eq "f1:single-state-current" "implement_step" \
  "$(hivemind_project_state_current_content "$one_ledger")" "single ledger doc → state.current value"
# Empty content → MISSING (nothing to report), for both scalars.
assert_eq "f1:empty-run-status" "MISSING" \
  "$(hivemind_project_run_status_content "")" "empty content → run.status MISSING"
assert_eq "f1:empty-state-current" "MISSING" \
  "$(hivemind_project_state_current_content "")" "empty content → state.current MISSING"

# ── 5c. #178 F3: non-string manifest scalars → field_at exit 2 (MALFORMED), NOT coerced ──
# Every supported manifest field is a STRING in a well-formed manifest. A present NON-STRING scalar
# (branch:123, tmux_session:true, status:123) is a tamper indicator: hivemind_manifest_field_at must
# exit 2 (the caller renders MALFORMED) and emit NOTHING — never coerce 123→"123" / true→"true".
# We assert the EXIT CODE explicitly (the contract is out-of-band) AND that stdout is empty.
nonstring_branch='{"strains":[{"name":"api","branch":123,"tmux_session":"brood-api","status":"running"}]}'
out="$(hivemind_manifest_field_at "$nonstring_branch" 0 "branch")"; rc=$?
assert_eq "f3:branch-number-rc" "2" "$rc" "branch:123 → field_at exit 2 (MALFORMED, not coerced)"
assert_eq "f3:branch-number-empty" "" "$out" "branch:123 → field_at emits nothing (no coercion to \"123\")"
nonstring_tmux='{"strains":[{"name":"api","branch":"strain/brood-x/api","tmux_session":true,"status":"running"}]}'
out="$(hivemind_manifest_field_at "$nonstring_tmux" 0 "tmux_session")"; rc=$?
assert_eq "f3:tmux-bool-rc" "2" "$rc" "tmux_session:true → field_at exit 2 (MALFORMED, not coerced)"
assert_eq "f3:tmux-bool-empty" "" "$out" "tmux_session:true → field_at emits nothing (no coercion to \"true\")"
nonstring_status='{"strains":[{"name":"api","branch":"strain/brood-x/api","tmux_session":"brood-api","status":123}]}'
out="$(hivemind_manifest_field_at "$nonstring_status" 0 "status")"; rc=$?
assert_eq "f3:status-number-rc" "2" "$rc" "status:123 → field_at exit 2 (MALFORMED, not coerced)"
assert_eq "f3:status-number-empty" "" "$out" "status:123 → field_at emits nothing (no coercion)"

# ── 5d. #178 F2: field_at exit-code contract — present/absent/rejected are DISTINCT ──
# The exit-code contract: 0 = present+valid (value on stdout), 1 = ABSENT (→MISSING),
# 2 = present-but-INVALID (→MALFORMED). A REJECTED value (control byte / multi-document) is exit 2
# and must NEVER be collapsed into the absent exit 1. We assert the exit codes EXPLICITLY.
# Present + valid → exit 0, value on stdout.
valid_field='{"strains":[{"name":"api","branch":"strain/brood-x/api","tmux_session":"brood-api","status":"running"}]}'
out="$(hivemind_manifest_field_at "$valid_field" 0 "branch")"; rc=$?
assert_eq "f2:present-valid-rc" "0" "$rc" "present+valid branch → field_at exit 0"
assert_eq "f2:present-valid-value" "strain/brood-x/api" "$out" "present+valid branch → value on stdout"
# ABSENT field (key missing) → exit 1 (MISSING), nothing on stdout.
absent_field='{"strains":[{"name":"api","tmux_session":"brood-api","status":"running"}]}'
out="$(hivemind_manifest_field_at "$absent_field" 0 "branch")"; rc=$?
assert_eq "f2:absent-rc" "1" "$rc" "absent branch key → field_at exit 1 (MISSING)"
assert_eq "f2:absent-empty" "" "$out" "absent branch key → nothing on stdout"
# Explicit JSON null → exit 1 (MISSING).
null_field='{"strains":[{"name":"api","branch":null,"tmux_session":"brood-api","status":"running"}]}'
out="$(hivemind_manifest_field_at "$null_field" 0 "branch")"; rc=$?
assert_eq "f2:null-rc" "1" "$rc" "branch:null → field_at exit 1 (MISSING)"
# Empty string → exit 1 (MISSING) per the contract (absent-or-empty).
emptystr_field='{"strains":[{"name":"api","branch":"","tmux_session":"brood-api","status":"running"}]}'
out="$(hivemind_manifest_field_at "$emptystr_field" 0 "branch")"; rc=$?
assert_eq "f2:emptystr-rc" "1" "$rc" "branch:\"\" → field_at exit 1 (MISSING)"
# REJECTED: a JSON control-byte ESCAPE (valid JSON; the FILE bytes hold the literal 6-char
# ASCII escape \\u0000, no real NUL) -> exit 2. jq -r would decode \\u0000 to a real NUL that
# $(...) would strip; the in-jq [[:cntrl:]] gate rejects it INSIDE jq while the bytes are intact.
# This rejected value is exit 2 -- NEVER collapsed into the absent exit 1. printf %b is NOT used:
# the \\u in the double-quoted format emits a literal backslash+u so jq receives the JSON escape
# and decodes it at projection time.
ctrl_field="$(printf '{"strains":[{"name":"api","branch":"strain/brood-x\\u0000api","tmux_session":"brood-api","status":"running"}]}')"
out="$(hivemind_manifest_field_at "$ctrl_field" 0 "branch")"; rc=$?
assert_eq "f2:control-escape-rc" "2" "$rc" "branch with u0000 control escape -> field_at exit 2 (REJECTED, not MISSING)"
assert_eq "f2:control-escape-empty" "" "$out" "control-escape branch -> nothing on stdout (never the NUL-stripped token)"
# REJECTED: a multi-document snapshot (length != 1) → exit 2 (not exit 1).
multidoc_field="$(printf '%s\n%s\n' \
  '{"strains":[{"name":"api","branch":"strain/brood-x/api","tmux_session":"brood-api","status":"running"}]}' \
  '{"strains":[{"name":"web","branch":"strain/brood-x/web","tmux_session":"brood-web","status":"running"}]}')"
out="$(hivemind_manifest_field_at "$multidoc_field" 0 "branch")"; rc=$?
assert_eq "f2:multidoc-rc" "2" "$rc" "multi-document snapshot → field_at exit 2 (REJECTED, not MISSING)"
# REGRESSION: rejected (exit 2) is distinct from absent (exit 1) — assert they differ on the same field.
if [ "$rc" -ne 1 ]; then
  pass "f2:rejected-not-collapsed" "a rejected value's exit code (2) is never the absent exit code (1)"
else
  failed "f2:rejected-not-collapsed" "a rejected value collapsed into the absent exit code (1)"
fi

# ── Section 6: brood-status-derive.sh — pure status derivation + aggregation (#186) ─
echo ''
echo '=== brood-status-derive.sh: status derivation, bucket classification, aggregation (#186) ==='
#
# PURE determinism coverage for the collection loop's derivation. This is the PRIMARY test of the
# rule table ported out of SKILL.md steps 2..5 — it runs with no tmux/gh/git, exercising every
# row of the failed-precedence + tmux x PR table, the bucket classifier, and both aggregators.

# ── 6a. hivemind_derive_strain_status — the FULL rule table ──
# SIGNATURE (issue #213, 6-arity): <manifest_status> <session_alive> <pr_state> <pr_number>
#   <state_current> <run_status>. The last two are tier-3 child-ledger started-evidence tokens; an
# alive session derives `running` ONLY with a present, non-MISSING/non-MALFORMED state.current,
# otherwise it demotes to the transient `starting` status. The dead/failed rows ignore them.
STARTED="implement_step"   # a present, non-sentinel state.current = ground-truth started evidence.

# failed-precedence (manifest_status=failed beats tmux): alive vs dead. Ledger tokens are ignored
# under failed-precedence (use MISSING to prove they cannot resurrect a failed strain to starting).
assert_eq "derive:failed-alive" "failed (injection failed; session alive for debug)" \
  "$(hivemind_derive_strain_status failed 1 none "" MISSING MISSING)" "failed + alive -> injection-failed debug"
assert_eq "derive:failed-dead" "failed (session ended, no PR)" \
  "$(hivemind_derive_strain_status failed 0 none "" MISSING MISSING)" "failed + dead -> session ended"
# failed-precedence holds even when a PR is open (manifest failed wins over the table).
assert_eq "derive:failed-alive-pr-open" "failed (injection failed; session alive for debug)" \
  "$(hivemind_derive_strain_status failed 1 open 7 MISSING MISSING)" "failed + alive ignores PR state"

# tmux x PR observable table (manifest_status NOT failed; use the literal status spawn-brood writes).
# Alive rows carry started-evidence (STARTED) so they derive `running` (not the demoted `starting`).
assert_eq "derive:alive-none" "running" \
  "$(hivemind_derive_strain_status running 1 none "" "$STARTED" running)" "alive + started + none -> running"
assert_eq "derive:alive-open" "running (PR #42 open)" \
  "$(hivemind_derive_strain_status running 1 open 42 "$STARTED" running)" "alive + started + open -> running (PR #N open)"
assert_eq "derive:dead-merged" "complete" \
  "$(hivemind_derive_strain_status running 0 merged 13 "$STARTED" complete)" "dead + merged -> complete"
assert_eq "derive:dead-open" "blocked (session ended, PR #99 still open)" \
  "$(hivemind_derive_strain_status running 0 open 99 "$STARTED" running)" "dead + open -> blocked"
assert_eq "derive:dead-none" "failed (session ended, no PR)" \
  "$(hivemind_derive_strain_status running 0 none "" "$STARTED" running)" "dead + none -> failed"

# unknown-PR handling: gh failed. Treated like none for derivation (the cell shows unknown via the
# renderer; status derives from tmux + best-known PR). alive+unknown -> running; dead+unknown -> failed.
assert_eq "derive:alive-unknown" "running" \
  "$(hivemind_derive_strain_status running 1 unknown "" "$STARTED" running)" "alive + started + unknown PR -> running (unknown ~ none)"
assert_eq "derive:dead-unknown" "failed (session ended, no PR)" \
  "$(hivemind_derive_strain_status running 0 unknown "" "$STARTED" running)" "dead + unknown PR -> failed (unknown ~ none)"

# ── 6a-bis. started-evidence gate (issue #213): alive session demotes to `starting` without it ──
STARTING="starting (session alive, workflow not yet started)"
# alive + started-evidence-present -> running (the positive control; mirrors derive:alive-none).
assert_eq "derive:alive-started-running" "running" \
  "$(hivemind_derive_strain_status running 1 none "" "$STARTED" running)" "alive + present state.current -> running"
# alive + MISSING state.current (child pasted but never submitted; no ledger) -> starting, NOT running.
assert_eq "derive:alive-missing-starting" "$STARTING" \
  "$(hivemind_derive_strain_status running 1 none "" MISSING MISSING)" "alive + MISSING state.current -> starting (not running)"
# alive + MALFORMED state.current (fail-closed) -> starting, NOT running.
assert_eq "derive:alive-malformed-starting" "$STARTING" \
  "$(hivemind_derive_strain_status running 1 none "" MALFORMED MISSING)" "alive + MALFORMED state.current -> starting (fail-closed, not running)"
# alive + empty state.current -> starting (defensive: empty is treated as no started-evidence).
assert_eq "derive:alive-empty-starting" "$STARTING" \
  "$(hivemind_derive_strain_status running 1 none "" "" "")" "alive + empty state.current -> starting"
# The started-evidence gate does NOT promote a DEAD session: dead+merged stays complete even with no
# state.current (the gate only DEMOTES alive sessions; it never touches the dead branch).
assert_eq "derive:dead-merged-no-evidence" "complete" \
  "$(hivemind_derive_strain_status running 0 merged 13 MISSING MISSING)" "dead + merged + MISSING -> complete (gate never touches dead branch)"
# alive + started-evidence + open PR -> running (PR #N open), NOT starting (evidence present).
assert_eq "derive:alive-started-open" "running (PR #7 open)" \
  "$(hivemind_derive_strain_status running 1 open 7 "$STARTED" running)" "alive + started + open -> running (PR #N open)"

# ── legacy no-pointer fall-through: NO_LEDGER_POINTER bypasses the started-evidence gate ──
# A legacy manifest has no run.suggested_id, so the projector emits NO_LEDGER_POINTER for
# state.current. Started-evidence is structurally unavailable, so the gate must NOT apply: an alive
# legacy strain keeps its observable status. This is the regression assertion.
assert_eq "derive:alive-nopointer-running" "running" \
  "$(hivemind_derive_strain_status running 1 none "" NO_LEDGER_POINTER MISSING)" "alive + NO_LEDGER_POINTER + no PR -> running (legacy fall-through, NOT starting)"
# alive legacy strain + open PR -> running (PR #N open) (gate still bypassed; observable status kept).
assert_eq "derive:alive-nopointer-open" "running (PR #7 open)" \
  "$(hivemind_derive_strain_status running 1 open 7 NO_LEDGER_POINTER MISSING)" "alive + NO_LEDGER_POINTER + open PR -> running (PR #N open)"
# dead legacy strain (session never resurrected) -> failed terminal; NO_LEDGER_POINTER never touches the dead branch.
assert_eq "derive:dead-nopointer-failed" "failed (session ended, no PR)" \
  "$(hivemind_derive_strain_status running 0 none "" NO_LEDGER_POINTER MISSING)" "dead + NO_LEDGER_POINTER + no PR -> failed (session ended, no PR)"

# ── 6b. hivemind_classify_status_bucket — every derived status maps to a bucket ──
assert_eq "bucket:complete" "complete" \
  "$(hivemind_classify_status_bucket "complete")" "complete -> complete bucket"
assert_eq "bucket:running" "running" \
  "$(hivemind_classify_status_bucket "running")" "running -> running bucket"
assert_eq "bucket:running-pr" "running" \
  "$(hivemind_classify_status_bucket "running (PR #42 open)")" "running (PR #N open) -> running bucket"
assert_eq "bucket:blocked" "blocked_failed" \
  "$(hivemind_classify_status_bucket "blocked (session ended, PR #99 still open)")" "blocked -> blocked_failed"
assert_eq "bucket:failed" "blocked_failed" \
  "$(hivemind_classify_status_bucket "failed (session ended, no PR)")" "failed -> blocked_failed"
assert_eq "bucket:failed-debug" "blocked_failed" \
  "$(hivemind_classify_status_bucket "failed (injection failed; session alive for debug)")" "failed-debug -> blocked_failed"
# issue #213: the new `starting` status buckets OUT of running and is NOT complete -> blocked_failed,
# so the three-bucket summary keeps summing to total.
assert_eq "bucket:starting" "blocked_failed" \
  "$(hivemind_classify_status_bucket "starting (session alive, workflow not yet started)")" "starting -> blocked_failed (out of running, not complete)"
# Conservative default: an unexpected string counts against completion, never silently dropped.
assert_eq "bucket:unexpected" "blocked_failed" \
  "$(hivemind_classify_status_bucket "weird")" "unexpected status -> blocked_failed (conservative)"

# ── 6c. hivemind_aggregate_brood_summary — per-brood {complete,running,blocked_failed,total} ──
# Zero strains (empty brood) -> all zero.
assert_eq "brood-agg:empty" "0 0 0 0" \
  "$(hivemind_aggregate_brood_summary)" "no buckets -> 0 0 0 0"
# Mixed: 2 complete, 1 running, 2 blocked_failed -> total 5.
assert_eq "brood-agg:mixed" "2 1 2 5" \
  "$(hivemind_aggregate_brood_summary complete running complete blocked_failed blocked_failed)" "mixed buckets"
# All complete.
assert_eq "brood-agg:all-complete" "3 0 0 3" \
  "$(hivemind_aggregate_brood_summary complete complete complete)" "all complete"
# An unrecognized bucket token counts into blocked_failed (never dropped from total).
assert_eq "brood-agg:unknown-bucket" "1 0 1 2" \
  "$(hivemind_aggregate_brood_summary complete bogus)" "unknown bucket -> blocked_failed, still counted"
# issue #213: a `starting` strain (classified blocked_failed) is counted in total, so the summary
# still sums (1 complete + 1 running + 2 blocked_failed = 4). Proves no strain is dropped.
assert_eq "brood-agg:with-starting" "1 1 2 4" \
  "$(hivemind_aggregate_brood_summary complete running blocked_failed blocked_failed)" "starting bucketed blocked_failed -> summary sums to total"

# ── 6d. hivemind_aggregate_global — {total_broods,unreadable,complete,total_strains} ──
# Records are "<is_unreadable>:<complete>:<total>".
# Zero broods (No broods found) -> all zero.
assert_eq "global-agg:empty" "0 0 0 0" \
  "$(hivemind_aggregate_global)" "no records -> 0 0 0 0"
# Single ok brood: 2 of 3 complete.
assert_eq "global-agg:single" "1 0 2 3" \
  "$(hivemind_aggregate_global "0:2:3")" "single brood 2/3 complete"
# Multiple broods + one unreadable: 3 broods, 1 unreadable, complete 2+1, strains 3+2 (unreadable=0/0).
assert_eq "global-agg:multi-with-unreadable" "3 1 3 5" \
  "$(hivemind_aggregate_global "0:2:3" "0:1:2" "1:0:0")" "3 broods (1 unreadable); 3 of 5 complete"
# All unreadable -> total_broods counts them, unreadable counts them, zero strains/complete.
assert_eq "global-agg:all-unreadable" "2 2 0 0" \
  "$(hivemind_aggregate_global "1:0:0" "1:0:0")" "two unreadable broods -> 2 broods, 2 unreadable, 0/0"

# ── Section 7: containment.sh ───────────────────────────────────────────────────
echo ''
echo '=== containment.sh: hivemind_assert_contained / _file_contained / _inputs_contained ==='
#
# PURE BASH — no jq/tmux/claude/git required. Every fixture is a real-disk dir/symlink tree
# built under WORKDIR and cleaned up by the existing EXIT trap. Each case gets its OWN
# per-case subdir so fixtures never leak between cases.

# ── 7a. hivemind_assert_contained — dir-chain depth-completeness ─────────────────

# Helper: compute the canonical path for a directory that exists on disk.
# Usage: canon_dir <dir>
canon_dir() { cd "$1" 2>/dev/null && pwd -P; }

# 7a-1: nonexistent leaf chain inside a real checkout → accept.
c7a1="$WORKDIR/c7a1/checkout"
mkdir -p "$c7a1"
c7a1_root="$(canon_dir "$c7a1")"
run_id_7a1="2026-01-01T00-00-00Z--run1"
c7a1_out="$(hivemind_assert_contained "$c7a1" ".hivemind/runs/$run_id_7a1")"
c7a1_rc=$?
assert_eq "c7a:nonexistent-leaf-rc" "0" "$c7a1_rc" "nonexistent leaf chain → return 0"
assert_eq "c7a:nonexistent-leaf-root" "$c7a1_root" "$c7a1_out" "nonexistent leaf chain → echoes canonical root"

# 7a-2: partial ancestors exist (mkdir .hivemind/runs), leaf absent → accept.
c7a2="$WORKDIR/c7a2/checkout"
mkdir -p "$c7a2/.hivemind/runs"
c7a2_root="$(canon_dir "$c7a2")"
c7a2_out="$(hivemind_assert_contained "$c7a2" ".hivemind/runs/run-leaf-absent")"
c7a2_rc=$?
assert_eq "c7a:partial-ancestors-rc" "0" "$c7a2_rc" "partial ancestors real, leaf absent → return 0"
assert_eq "c7a:partial-ancestors-root" "$c7a2_root" "$c7a2_out" "partial ancestors real → echoes canonical root"

# 7a-3: leaf-depth symlink — .hivemind/runs is real, leaf is a symlink to external dir → reject.
c7a3="$WORKDIR/c7a3/checkout"
c7a3_ext="$WORKDIR/c7a3/external"
mkdir -p "$c7a3/.hivemind/runs" "$c7a3_ext"
ln -s "$c7a3_ext" "$c7a3/.hivemind/runs/symlinked-run"
c7a3_out="$(hivemind_assert_contained "$c7a3" ".hivemind/runs/symlinked-run" 2>/dev/null)"
c7a3_rc=$?
if [ "$c7a3_rc" -ne 0 ]; then
  pass "c7a:leaf-symlink-reject" "symlinked leaf → non-zero return"
else
  failed "c7a:leaf-symlink-reject" "symlinked leaf must reject; got return 0"
fi

# 7a-4: ancestor-depth symlink — .hivemind itself is a symlink to external dir → reject.
c7a4="$WORKDIR/c7a4/checkout"
c7a4_ext="$WORKDIR/c7a4/external"
mkdir -p "$c7a4" "$c7a4_ext"
ln -s "$c7a4_ext" "$c7a4/.hivemind"
c7a4_out="$(hivemind_assert_contained "$c7a4" ".hivemind/runs/any-run" 2>/dev/null)"
c7a4_rc=$?
if [ "$c7a4_rc" -ne 0 ]; then
  pass "c7a:ancestor-symlink-reject" "symlinked ancestor .hivemind → non-zero return"
else
  failed "c7a:ancestor-symlink-reject" "symlinked ancestor .hivemind must reject; got return 0"
fi

# 7a-5: deepest-existing prefix resolves outside root via symlinked component → reject.
# .hivemind/runs is real but symlinked TO the external dir, so canonicalization of that
# prefix yields a path outside the checkout.
c7a5="$WORKDIR/c7a5/checkout"
c7a5_ext="$WORKDIR/c7a5/external"
mkdir -p "$c7a5/.hivemind" "$c7a5_ext"
ln -s "$c7a5_ext" "$c7a5/.hivemind/runs"
c7a5_out="$(hivemind_assert_contained "$c7a5" ".hivemind/runs/some-run" 2>/dev/null)"
c7a5_rc=$?
if [ "$c7a5_rc" -ne 0 ]; then
  pass "c7a:outside-prefix-reject" "prefix resolves outside checkout → non-zero return"
else
  failed "c7a:outside-prefix-reject" "prefix outside checkout must reject; got return 0"
fi

# 7a-6: sibling-prefix .hivemind-evil is a real dir and must be independently contained
# (trailing-slash guard prevents .hivemind-evil from prefix-matching .hivemind).
c7a6="$WORKDIR/c7a6/checkout"
mkdir -p "$c7a6/.hivemind-evil"
c7a6_root="$(canon_dir "$c7a6")"
c7a6_out="$(hivemind_assert_contained "$c7a6" ".hivemind-evil/data")"
c7a6_rc=$?
assert_eq "c7a:sibling-prefix-rc" "0" "$c7a6_rc" "sibling-prefix .hivemind-evil real dir → accept"
assert_eq "c7a:sibling-prefix-root" "$c7a6_root" "$c7a6_out" "sibling-prefix → echoes canonical root"
# Also confirm that a SYMLINKED .hivemind-evil rejects independently (no bleed from .hivemind).
c7a6_ext="$WORKDIR/c7a6/external"
mkdir -p "$c7a6_ext"
ln -s "$c7a6_ext" "$c7a6/.hivemind-evil-link"
c7a6b_out="$(hivemind_assert_contained "$c7a6" ".hivemind-evil-link/data" 2>/dev/null)"
c7a6b_rc=$?
if [ "$c7a6b_rc" -ne 0 ]; then
  pass "c7a:sibling-symlinked-reject" "symlinked sibling .hivemind-evil-link → non-zero return"
else
  failed "c7a:sibling-symlinked-reject" "symlinked sibling must reject independently; got return 0"
fi

# 7a-7: un-canonicalizable root (raw_repo_root does not exist) → non-zero, empty stdout.
c7a7_out="$(hivemind_assert_contained "$WORKDIR/c7a7/does-not-exist" ".hivemind/runs/x" 2>/dev/null)"
c7a7_rc=$?
if [ "$c7a7_rc" -ne 0 ]; then
  pass "c7a:bad-root-rc" "non-existent root → non-zero return"
else
  failed "c7a:bad-root-rc" "non-existent root must reject; got return 0"
fi
assert_eq "c7a:bad-root-empty-stdout" "" "$c7a7_out" "non-existent root → empty stdout"

# ── 7b. hivemind_assert_file_contained — regular-or-absent leaf ──────────────────

# 7b-1: non-existent leaf, parent dirs real → accept.
c7b1="$WORKDIR/c7b1/checkout"
mkdir -p "$c7b1/.hivemind/brood"
c7b1_root="$(canon_dir "$c7b1")"
c7b1_out="$(hivemind_assert_file_contained "$c7b1" ".hivemind/brood/task.md")"
c7b1_rc=$?
assert_eq "c7b:nonexistent-leaf-rc" "0" "$c7b1_rc" "file: non-existent leaf → return 0"
assert_eq "c7b:nonexistent-leaf-root" "$c7b1_root" "$c7b1_out" "file: non-existent leaf → canonical root"

# 7b-2: regular-file leaf exists → accept.
c7b2="$WORKDIR/c7b2/checkout"
mkdir -p "$c7b2/.hivemind/brood"
: > "$c7b2/.hivemind/brood/task.md"
c7b2_root="$(canon_dir "$c7b2")"
c7b2_out="$(hivemind_assert_file_contained "$c7b2" ".hivemind/brood/task.md")"
c7b2_rc=$?
assert_eq "c7b:regular-file-rc" "0" "$c7b2_rc" "file: regular-file leaf → return 0"
assert_eq "c7b:regular-file-root" "$c7b2_root" "$c7b2_out" "file: regular-file leaf → canonical root"

# 7b-3: single-component leaf (bare filename at checkout root, nonexistent) → accept.
c7b3="$WORKDIR/c7b3/checkout"
mkdir -p "$c7b3"
c7b3_root="$(canon_dir "$c7b3")"
c7b3_out="$(hivemind_assert_file_contained "$c7b3" "task.md")"
c7b3_rc=$?
assert_eq "c7b:single-component-rc" "0" "$c7b3_rc" "file: single-component nonexistent leaf → return 0"
assert_eq "c7b:single-component-root" "$c7b3_root" "$c7b3_out" "file: single-component → canonical root"

# 7b-4: symlink leaf pointing at a non-existent target (dangling) → reject.
c7b4="$WORKDIR/c7b4/checkout"
mkdir -p "$c7b4/.hivemind/brood"
ln -s "$WORKDIR/c7b4/nowhere" "$c7b4/.hivemind/brood/task.md"
c7b4_out="$(hivemind_assert_file_contained "$c7b4" ".hivemind/brood/task.md" 2>/dev/null)"
c7b4_rc=$?
if [ "$c7b4_rc" -ne 0 ]; then
  pass "c7b:dangling-symlink-reject" "file: dangling symlink leaf → non-zero return"
else
  failed "c7b:dangling-symlink-reject" "file: dangling symlink leaf must reject; got return 0"
fi

# 7b-5: directory leaf — leaf path is a directory → reject.
c7b5="$WORKDIR/c7b5/checkout"
mkdir -p "$c7b5/.claude/settings.local.json"
c7b5_out="$(hivemind_assert_file_contained "$c7b5" ".claude/settings.local.json" 2>/dev/null)"
c7b5_rc=$?
if [ "$c7b5_rc" -ne 0 ]; then
  pass "c7b:directory-leaf-reject" "file: directory leaf → non-zero return"
else
  failed "c7b:directory-leaf-reject" "file: directory leaf must reject; got return 0"
fi

# 7b-6: FIFO leaf — gated on mkfifo availability (skip if absent).
c7b6="$WORKDIR/c7b6/checkout"
mkdir -p "$c7b6/.hivemind/brood"
if command -v mkfifo >/dev/null 2>&1; then
  mkfifo "$c7b6/.hivemind/brood/task.md"
  c7b6_out="$(hivemind_assert_file_contained "$c7b6" ".hivemind/brood/task.md" 2>/dev/null)"
  c7b6_rc=$?
  if [ "$c7b6_rc" -ne 0 ]; then
    pass "c7b:fifo-leaf-reject" "file: FIFO leaf → non-zero return"
  else
    failed "c7b:fifo-leaf-reject" "file: FIFO leaf must reject; got return 0"
  fi
else
  pass "c7b:fifo-leaf-reject" "file: FIFO leaf test skipped (mkfifo absent)"
fi

# 7b-7: symlinked-parent chain — .hivemind symlinked, leaf .hivemind/brood/task.md → reject.
c7b7="$WORKDIR/c7b7/checkout"
c7b7_ext="$WORKDIR/c7b7/external"
mkdir -p "$c7b7" "$c7b7_ext/brood"
ln -s "$c7b7_ext" "$c7b7/.hivemind"
c7b7_out="$(hivemind_assert_file_contained "$c7b7" ".hivemind/brood/task.md" 2>/dev/null)"
c7b7_rc=$?
if [ "$c7b7_rc" -ne 0 ]; then
  pass "c7b:symlinked-parent-reject" "file: symlinked parent .hivemind → non-zero return"
else
  failed "c7b:symlinked-parent-reject" "file: symlinked parent chain must reject; got return 0"
fi

# ── 7c. hivemind_assert_inputs_contained — symlinked-ancestor read-guard ─────────

# 7c-1: inputs file at a real path inside the checkout → accept.
c7c1="$WORKDIR/c7c1/checkout"
mkdir -p "$c7c1/.hivemind"
c7c1_root="$(canon_dir "$c7c1")"
c7c1_inputs="$c7c1/.hivemind/spawn-inputs.json"
: > "$c7c1_inputs"
c7c1_out="$(hivemind_assert_inputs_contained "$c7c1" "$c7c1_inputs")"
c7c1_rc=$?
assert_eq "c7c:real-inputs-rc" "0" "$c7c1_rc" "inputs: real path inside checkout → return 0"
assert_eq "c7c:real-inputs-root" "$c7c1_root" "$c7c1_out" "inputs: real path → canonical root"

# 7c-2: inputs file whose canonical dir escapes via a symlinked ancestor → reject.
c7c2="$WORKDIR/c7c2/checkout"
c7c2_ext="$WORKDIR/c7c2/external"
mkdir -p "$c7c2" "$c7c2_ext"
ln -s "$c7c2_ext" "$c7c2/link"
c7c2_inputs="$c7c2/link/spawn-inputs.json"
: > "$c7c2_inputs"
c7c2_out="$(hivemind_assert_inputs_contained "$c7c2" "$c7c2_inputs" 2>/dev/null)"
c7c2_rc=$?
if [ "$c7c2_rc" -ne 0 ]; then
  pass "c7c:symlinked-ancestor-reject" "inputs: symlinked ancestor → non-zero return"
else
  failed "c7c:symlinked-ancestor-reject" "inputs: symlinked ancestor must reject; got return 0"
fi

# 7c-3: un-canonicalizable root → non-zero, empty stdout.
c7c3_fake_root="$WORKDIR/c7c3/does-not-exist"
c7c3_inputs="$WORKDIR/c7c3/some-file.json"
mkdir -p "$WORKDIR/c7c3"
: > "$c7c3_inputs"
c7c3_out="$(hivemind_assert_inputs_contained "$c7c3_fake_root" "$c7c3_inputs" 2>/dev/null)"
c7c3_rc=$?
if [ "$c7c3_rc" -ne 0 ]; then
  pass "c7c:bad-root-rc" "inputs: non-existent root → non-zero return"
else
  failed "c7c:bad-root-rc" "inputs: non-existent root must reject; got return 0"
fi
assert_eq "c7c:bad-root-empty-stdout" "" "$c7c3_out" "inputs: non-existent root → empty stdout"

# 7c-4: sibling-named external dir must not prefix-match the checkout root (trailing-slash guard).
# The external dir shares a prefix with the checkout root (e.g. /tmp/X/checkout-evil vs /tmp/X/checkout)
# but is distinct. An inputs file there must be rejected.
c7c4_base="$WORKDIR/c7c4"
c7c4_root="$c7c4_base/checkout"
c7c4_evil="$c7c4_base/checkout-evil"
mkdir -p "$c7c4_root" "$c7c4_evil"
c7c4_inputs="$c7c4_evil/spawn-inputs.json"
: > "$c7c4_inputs"
c7c4_out="$(hivemind_assert_inputs_contained "$c7c4_root" "$c7c4_inputs" 2>/dev/null)"
c7c4_rc=$?
if [ "$c7c4_rc" -ne 0 ]; then
  pass "c7c:sibling-no-prefix-match" "inputs: sibling-named external dir must not prefix-match → non-zero return"
else
  failed "c7c:sibling-no-prefix-match" "inputs: sibling-named dir prefix-matched checkout root (trailing-slash guard broken)"
fi

# 7c-5: inputs-file LEAF is a symlink to an external target → reject (leaf read oracle closed).
# The leaf itself is a symlink ([ -L ] fires), even though every dir component is contained.
c7c5="$WORKDIR/c7c5/checkout"
c7c5_ext="$WORKDIR/c7c5/external"
mkdir -p "$c7c5/.hivemind" "$c7c5_ext"
: > "$c7c5_ext/secret.json"
c7c5_inputs="$c7c5/.hivemind/spawn-inputs.json"
ln -s "$c7c5_ext/secret.json" "$c7c5_inputs"
c7c5_out="$(hivemind_assert_inputs_contained "$c7c5" "$c7c5_inputs" 2>/dev/null)"
c7c5_rc=$?
if [ "$c7c5_rc" -ne 0 ]; then
  pass "c7c:symlinked-leaf-reject" "inputs: symlinked leaf → non-zero return"
else
  failed "c7c:symlinked-leaf-reject" "inputs: symlinked leaf must reject; got return 0"
fi
assert_eq "c7c:symlinked-leaf-empty-stdout" "" "$c7c5_out" "inputs: symlinked leaf → empty stdout"

# 7c-6: inputs-file LEAF is a DANGLING symlink (target does not exist) → still reject.
# Proves [ -L ] fires regardless of target existence.
c7c6="$WORKDIR/c7c6/checkout"
c7c6_ext="$WORKDIR/c7c6/external"
mkdir -p "$c7c6/.hivemind" "$c7c6_ext"
c7c6_inputs="$c7c6/.hivemind/spawn-inputs.json"
ln -s "$c7c6_ext/missing.json" "$c7c6_inputs"
c7c6_out="$(hivemind_assert_inputs_contained "$c7c6" "$c7c6_inputs" 2>/dev/null)"
c7c6_rc=$?
if [ "$c7c6_rc" -ne 0 ]; then
  pass "c7c:dangling-symlinked-leaf-reject" "inputs: dangling symlinked leaf → non-zero return"
else
  failed "c7c:dangling-symlinked-leaf-reject" "inputs: dangling symlinked leaf must reject; got return 0"
fi
assert_eq "c7c:dangling-symlinked-leaf-empty-stdout" "" "$c7c6_out" "inputs: dangling symlinked leaf → empty stdout"

# ── 7d. hivemind_assert_ledger_contained — symlinked-ledger-leaf read-guard ──────
# 7d-1: real regular-file ledger inside the checkout .hivemind/runs/<id>/ → accept.
c7d1="$WORKDIR/c7d1/checkout"
mkdir -p "$c7d1/.hivemind/runs/run-1"
c7d1_root="$(canon_dir "$c7d1")"
c7d1_ledger="$c7d1/.hivemind/runs/run-1/state.json"
: > "$c7d1_ledger"
c7d1_out="$(hivemind_assert_ledger_contained "$c7d1" "$c7d1_ledger")"
c7d1_rc=$?
assert_eq "c7d:real-ledger-rc" "0" "$c7d1_rc" "ledger: real regular-file ledger inside checkout → return 0"
assert_eq "c7d:real-ledger-root" "$c7d1_root" "$c7d1_out" "ledger: real ledger → canonical root"

# 7d-2: ledger LEAF is a symlink to an external target → reject (leaf read oracle closed).
# Every dir component is contained; only the leaf symlink ([ -L ] fires) escapes.
c7d2="$WORKDIR/c7d2/checkout"
c7d2_ext="$WORKDIR/c7d2/external"
mkdir -p "$c7d2/.hivemind/runs/run-1" "$c7d2_ext"
: > "$c7d2_ext/secret.json"
c7d2_ledger="$c7d2/.hivemind/runs/run-1/state.json"
ln -s "$c7d2_ext/secret.json" "$c7d2_ledger"
c7d2_out="$(hivemind_assert_ledger_contained "$c7d2" "$c7d2_ledger" 2>/dev/null)"
c7d2_rc=$?
if [ "$c7d2_rc" -ne 0 ]; then
  pass "c7d:symlinked-leaf-reject" "ledger: symlinked leaf → non-zero return"
else
  failed "c7d:symlinked-leaf-reject" "ledger: symlinked leaf must reject; got return 0"
fi
assert_eq "c7d:symlinked-leaf-empty-stdout" "" "$c7d2_out" "ledger: symlinked leaf → empty stdout"

# 7d-3: ledger LEAF is a DANGLING symlink (target does not exist) → still reject.
# Proves [ -L ] fires regardless of target existence.
c7d3="$WORKDIR/c7d3/checkout"
c7d3_ext="$WORKDIR/c7d3/external"
mkdir -p "$c7d3/.hivemind/runs/run-1" "$c7d3_ext"
c7d3_ledger="$c7d3/.hivemind/runs/run-1/state.json"
ln -s "$c7d3_ext/missing.json" "$c7d3_ledger"
c7d3_out="$(hivemind_assert_ledger_contained "$c7d3" "$c7d3_ledger" 2>/dev/null)"
c7d3_rc=$?
if [ "$c7d3_rc" -ne 0 ]; then
  pass "c7d:dangling-symlinked-leaf-reject" "ledger: dangling symlinked leaf → non-zero return"
else
  failed "c7d:dangling-symlinked-leaf-reject" "ledger: dangling symlinked leaf must reject; got return 0"
fi
assert_eq "c7d:dangling-symlinked-leaf-empty-stdout" "" "$c7d3_out" "ledger: dangling symlinked leaf → empty stdout"

# 7d-4: ledger ANCESTOR is a symlink resolving outside the checkout → reject.
# The runs/<id> dir is reached through a symlinked .hivemind that escapes the root.
c7d4="$WORKDIR/c7d4/checkout"
c7d4_ext="$WORKDIR/c7d4/external"
mkdir -p "$c7d4" "$c7d4_ext/runs/run-1"
ln -s "$c7d4_ext" "$c7d4/.hivemind"
c7d4_ledger="$c7d4/.hivemind/runs/run-1/state.json"
: > "$c7d4_ledger"
c7d4_out="$(hivemind_assert_ledger_contained "$c7d4" "$c7d4_ledger" 2>/dev/null)"
c7d4_rc=$?
if [ "$c7d4_rc" -ne 0 ]; then
  pass "c7d:symlinked-ancestor-reject" "ledger: symlinked ancestor escaping root → non-zero return"
else
  failed "c7d:symlinked-ancestor-reject" "ledger: symlinked ancestor must reject; got return 0"
fi

# ── Section 8: ledger-reconstruct-parse.sh — git_log_to_findings (PURE parse) ────
echo ''
echo '=== ledger-reconstruct-parse.sh: git_log_to_findings (git-log fix-surface parse) ==='
#
# DIRECT unit coverage for the lifted PURE git-log parse stage. git_log_to_findings reads the
# machine-channel git-log payload on STDIN and emits a JSON ARRAY of fix-surface findings (one per
# commit/file/hunk). It reads the caller-shell globals US (0x1e record start) / RS (0x1f field sep)
# the entrypoint defines BEFORE sourcing — so this section SETS them first, mirroring the entrypoint
# variable contract verbatim. Ground-truth inputs/outputs reuse the entrypoint oracle's canned
# git-log fixtures (tests/ledger-reconstruct/) so these unit assertions agree with the 49-case
# behavioral suite. Payloads are streamed from disposable WORKDIR files (US/RS/NUL bytes built via
# printf) so NUL delimiters survive the read.
US=$'\x1e'; RS=$'\x1f'; BASE=origin/main

# 8a: qualifying remediation commit — one commit, two files (auth/db), one hunk each → two findings
# with FACTUAL `status: "fixed"`, correct id/file/line arithmetic. The subject carries the literal
# `address review feedback` phrase, so the prior-fix qualification gate ADMITS it.
parse_one="$WORKDIR/parse-one-commit.txt"
printf '%sCOMMIT%saaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa%sfix(auth): address review feedback\x00\n' "$US" "$RS" "$RS" > "$parse_one"
printf ':100644 100644 000aaaa 111aaaa M\x00src/auth.py\x00:100644 100644 000bbbb 111bbbb M\x00src/db.py\x00\x00' >> "$parse_one"
printf 'diff --git a/src/auth.py b/src/auth.py\n@@ -10,3 +10,4 @@\n+x\n' >> "$parse_one"
printf 'diff --git a/src/db.py b/src/db.py\n@@ -5 +5,2 @@\n+y\n' >> "$parse_one"
parse_one_out="$(git_log_to_findings < "$parse_one")"
assert_eq "parse:qualify-count" "2" \
  "$(printf '%s' "$parse_one_out" | jq -c 'length')" "qualifying remediation commit → 2 findings (one per file/hunk)"
assert_eq "parse:qualify-auth-id" "fix:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:src/auth.py:10" \
  "$(printf '%s' "$parse_one_out" | jq -r '.[0].id')" "auth finding id"
assert_eq "parse:qualify-auth-status" "fixed" \
  "$(printf '%s' "$parse_one_out" | jq -r '.[0].status')" "auth finding status is FACTUAL fixed"
assert_eq "parse:qualify-auth-title" "fix(auth): address review feedback" \
  "$(printf '%s' "$parse_one_out" | jq -r '.[0].title')" "auth finding title = subject"
assert_eq "parse:qualify-db-file" "src/db.py" \
  "$(printf '%s' "$parse_one_out" | jq -r '.[1].file')" "db finding file (machine channel)"

# 8b: @@ hunk line arithmetic — new-side `+c,d` → line_start=c, line_end=c+d-1; a bare `+c` (no
# count) → d defaults to 1 → line_end==line_start. auth `@@ -10,3 +10,4 @@` → 10..13;
# db `@@ -5 +5,2 @@` → 5..6.
assert_eq "parse:hunk-auth-start" "10" \
  "$(printf '%s' "$parse_one_out" | jq -r '.[0].line_start')" "auth @@ +10,4 → line_start 10"
assert_eq "parse:hunk-auth-end" "13" \
  "$(printf '%s' "$parse_one_out" | jq -r '.[0].line_end')" "auth @@ +10,4 → line_end 13 (10+4-1)"
assert_eq "parse:hunk-db-start" "5" \
  "$(printf '%s' "$parse_one_out" | jq -r '.[1].line_start')" "db @@ +5,2 → line_start 5"
assert_eq "parse:hunk-db-end" "6" \
  "$(printf '%s' "$parse_one_out" | jq -r '.[1].line_end')" "db @@ +5,2 → line_end 6 (5+2-1)"

# 8c: prior-fix qualification gate — a NON-qualifying subject (ordinary `fix(parser):` dev bug-fix
# with NO `address review feedback` phrase) emits ZERO findings. The gate keys ONLY on the literal
# review-loop phrase, never on the bare conventional type.
parse_nonqual="$WORKDIR/parse-nonqual.txt"
printf '%sCOMMIT%sc3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3%sfix(parser): correct off-by-one\x00\n' "$US" "$RS" "$RS" > "$parse_nonqual"
printf ':100644 100644 000p1 111p2 M\x00src/parser.py\x00\x00' >> "$parse_nonqual"
printf 'diff --git a/src/parser.py b/src/parser.py\n@@ -5,3 +5,3 @@\n+z\n' >> "$parse_nonqual"
assert_eq "parse:gate-reject-nonqualifying" "[]" \
  "$(git_log_to_findings < "$parse_nonqual")" "non-remediation fix subject → gate rejects → []"

# 8d: C0-control-byte-in-subject escaping — subject carries 0x08 backspace, a double-quote, and a
# backslash. jq owns ALL string emission, so the C0 byte is escaped (→ \b) and the finding is
# NON-empty (old hand-rolled-JSON code collapsed to [] on a C0 byte). Title must round-trip escaped.
parse_c0="$WORKDIR/parse-c0.txt"
printf '%sCOMMIT%sdddddddddddddddddddddddddddddddddddddddd%sfix(x): address review feedback Fix\x08"bad\\path"\x00\n' "$US" "$RS" "$RS" > "$parse_c0"
printf ':100644 100644 000fix1 111fix1 M\x00src/fix.py\x00\x00' >> "$parse_c0"
printf 'diff --git a/src/fix.py b/src/fix.py\n@@ -1 +1,3 @@\n+a\n' >> "$parse_c0"
parse_c0_out="$(git_log_to_findings < "$parse_c0")"
assert_eq "parse:c0-count" "1" \
  "$(printf '%s' "$parse_c0_out" | jq -c 'length')" "C0-byte subject → finding NON-empty (jq escapes the byte)"
assert_eq "parse:c0-title-escaped" '"fix(x): address review feedback Fix\b\"bad\\path\""' \
  "$(printf '%s' "$parse_c0_out" | jq -c '.[0].title')" "C0 0x08 escaped to \\b; quote/backslash escaped (jq -c form)"

# 8e: ` b/`-bearing path + rename destination — entry (1) modifies a file whose path contains the
# literal " b/" substring (old in-band ` b/` splitting would have corrupted it); entry (2) is a
# rename (R100, two NUL-delimited paths) — the parser must take the DESTINATION (last path).
parse_tricky="$WORKDIR/parse-tricky.txt"
printf '%sCOMMIT%seeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee%sfix(paths): address review feedback\x00\n' "$US" "$RS" "$RS" > "$parse_tricky"
printf ':100644 100644 000fbb1 111fbb1 M\x00foo b/bar.txt\x00:100644 100644 000old1 111new1 R100\x00old name.txt\x00new dir/new name.txt\x00\x00' >> "$parse_tricky"
printf 'diff --git a/placeholder b/placeholder\n@@ -5 +5,2 @@\n+e\n' >> "$parse_tricky"
printf 'diff --git a/old name.txt b/new dir/new name.txt\n@@ -1 +1,4 @@\n+r\n' >> "$parse_tricky"
parse_tricky_out="$(git_log_to_findings < "$parse_tricky")"
assert_eq "parse:space-b-path" "foo b/bar.txt" \
  "$(printf '%s' "$parse_tricky_out" | jq -r '.[0].file')" "' b/'-bearing path is FULL, not split"
assert_eq "parse:rename-destination" "new dir/new name.txt" \
  "$(printf '%s' "$parse_tricky_out" | jq -r '.[1].file')" "rename → DESTINATION path (last NUL token)"

# 8f: malformed input → `[]` fail-open coercion. A payload with no \x1eCOMMIT\x1f record marker is
# garbage; git_log_to_findings yields `[]` (INJECTED FAIL-OPEN), never an error.
parse_malformed="$WORKDIR/parse-malformed.txt"
printf 'this is not a valid git log payload\nno commit headers here\n@@not-a-real-hunk\n' > "$parse_malformed"
assert_eq "parse:malformed-fail-open" "[]" \
  "$(git_log_to_findings < "$parse_malformed")" "malformed payload (no COMMIT marker) → [] fail-open"

# ── Section 9: ledger-reconstruct-fold.sh — fold / gate / wrap (PURE) ────────────
echo ''
echo '=== ledger-reconstruct-fold.sh: normalized_to_findings / normalized_live_parse_gate / reconstruct_ledger ==='
#
# DIRECT unit coverage for the lifted fold/gate/wrap stage. These functions read the caller-shell
# global BASE (reconstruct_ledger only) — set verbatim per the entrypoint contract. US/RS were set
# in Section 8 above; BASE is (re)asserted here so this section stands on its own.
US=$'\x1e'; RS=$'\x1f'; BASE=origin/main

# 9a: normalized_to_findings — per-surface status derivation. Reuses the entrypoint oracle's
# normalized-threads payload (4 review records + 1 ci-check-failure). Folding rules:
#   thread(resolved=true) → status fixed, thread_resolved true;
#   thread(resolved=false) → status open (thread_resolved // null → null);
#   toplevel(handled) → status fixed FROM classification (non-thread cannot be GitHub-resolved);
#   review(actionable) → status open FROM classification;
#   ci-check-failure → SKIPPED (item_source != "review").
NORM_THREADS='[
  {"id":"PRRT_thread001resolved","thread_id":"PRRT_thread001resolved","item_source":"review","classification":"handled","thread_resolved":true,"surface":"thread"},
  {"id":"PRRT_thread002open","thread_id":"PRRT_thread002open","item_source":"review","classification":"actionable","thread_resolved":false,"surface":"thread"},
  {"id":"IC_toplevel001handled","thread_id":null,"item_source":"review","classification":"handled","thread_resolved":false,"surface":"toplevel"},
  {"id":"PRR_review001actionable","thread_id":null,"item_source":"review","classification":"actionable","thread_resolved":false,"surface":"review"},
  {"id":null,"item_source":"ci-check-failure","name":"policy-check","state":"FAILURE"}
]'
fold_out="$(normalized_to_findings "$NORM_THREADS")"
assert_eq "fold:review-only-count" "4" \
  "$(printf '%s' "$fold_out" | jq -c 'length')" "4 review records fold; ci-check-failure skipped"
assert_eq "fold:thread-resolved-status" "fixed" \
  "$(printf '%s' "$fold_out" | jq -r '.[] | select(.id=="PRRT_thread001resolved") | .status')" "resolved thread → status fixed"
assert_eq "fold:thread-resolved-flag" "true" \
  "$(printf '%s' "$fold_out" | jq -c '.[] | select(.id=="PRRT_thread001resolved") | .thread_resolved')" "resolved thread → thread_resolved true"
assert_eq "fold:thread-unresolved-status" "open" \
  "$(printf '%s' "$fold_out" | jq -r '.[] | select(.id=="PRRT_thread002open") | .status')" "unresolved thread → status open"
assert_eq "fold:toplevel-handled-status" "fixed" \
  "$(printf '%s' "$fold_out" | jq -r '.[] | select(.id=="IC_toplevel001handled") | .status')" "toplevel(handled) → status fixed from classification"
assert_eq "fold:toplevel-thread-resolved-null" "null" \
  "$(printf '%s' "$fold_out" | jq -c '.[] | select(.id=="IC_toplevel001handled") | .thread_resolved')" "toplevel → thread_resolved null (non-thread)"
assert_eq "fold:review-actionable-status" "open" \
  "$(printf '%s' "$fold_out" | jq -r '.[] | select(.id=="PRR_review001actionable") | .status')" "review(actionable) → status open from classification"
# Non-array / unparseable payload → [] fail-open coercion (INJECTED path).
assert_eq "fold:non-array-coerce" "[]" \
  "$(normalized_to_findings '{"not":"an array"}')" "non-array payload → [] fail-open coercion"

# 9b: normalized_live_parse_gate — LIVE FAIL-CLOSED return codes.
#   empty payload (zero bytes) → 0 (legitimate "no thread findings");
#   non-empty parseable JSON array → 0;
#   non-array / garbage → non-zero AND emits LEDGERRECON_ERROR=normalized-parse-failed on stderr.
normalized_live_parse_gate ""; gate_empty_rc=$?
assert_eq "gate:empty-rc0" "0" "$gate_empty_rc" "empty live payload → exit 0 (no thread findings)"
normalized_live_parse_gate '[{"id":"x"}]'; gate_array_rc=$?
assert_eq "gate:array-rc0" "0" "$gate_array_rc" "non-empty JSON array → exit 0"
gate_garbage_err="$(normalized_live_parse_gate 'this is not json' 2>&1 >/dev/null)"; gate_garbage_rc=$?
if [ "$gate_garbage_rc" -ne 0 ]; then
  pass "gate:garbage-rc-nonzero" "garbage payload → non-zero exit (fail closed)"
else
  failed "gate:garbage-rc-nonzero" "garbage payload must fail closed; got exit 0"
fi
if printf '%s' "$gate_garbage_err" | grep -qF "LEDGERRECON_ERROR=normalized-parse-failed"; then
  pass "gate:garbage-marker" "garbage payload emits LEDGERRECON_ERROR=normalized-parse-failed"
else
  failed "gate:garbage-marker" "expected normalized-parse-failed marker; got: $gate_garbage_err"
fi
# A non-empty, parseable, but NON-array JSON value (object) also fails closed with the marker.
gate_obj_err="$(normalized_live_parse_gate '{"a":1}' 2>&1 >/dev/null)"; gate_obj_rc=$?
if [ "$gate_obj_rc" -ne 0 ]; then
  pass "gate:object-rc-nonzero" "non-array JSON object → non-zero exit (fail closed)"
else
  failed "gate:object-rc-nonzero" "non-array JSON object must fail closed; got exit 0"
fi
if printf '%s' "$gate_obj_err" | grep -qF "LEDGERRECON_ERROR=normalized-parse-failed"; then
  pass "gate:object-marker" "non-array object emits LEDGERRECON_ERROR=normalized-parse-failed"
else
  failed "gate:object-marker" "expected normalized-parse-failed marker for object; got: $gate_obj_err"
fi

# 9c: reconstruct_ledger — top-level fix-ledger JSON shape. Wraps the two finding families
# (git + thread) into one iteration. BASE flows into both top-level `base` and the iteration's
# `review_base_ref`. Findings array is the concatenation ($git_findings + $thread_findings).
recon_out="$(reconstruct_ledger '[{"id":"g1"}]' '[{"id":"t1"}]')"
assert_eq "recon:base" "origin/main" \
  "$(printf '%s' "$recon_out" | jq -r '.base')" "BASE flows into top-level base"
assert_eq "recon:max-iterations" "10" \
  "$(printf '%s' "$recon_out" | jq -r '.max_iterations')" "max_iterations is 10"
assert_eq "recon:iteration-count" "1" \
  "$(printf '%s' "$recon_out" | jq -c '.iterations | length')" "exactly one iteration"
assert_eq "recon:iteration-number" "1" \
  "$(printf '%s' "$recon_out" | jq -r '.iterations[0].iteration')" "iteration number is 1"
assert_eq "recon:verdict" "needs-attention" \
  "$(printf '%s' "$recon_out" | jq -r '.iterations[0].verdict')" "iteration verdict needs-attention"
assert_eq "recon:review-base-ref" "origin/main" \
  "$(printf '%s' "$recon_out" | jq -r '.iterations[0].review_base_ref')" "BASE flows into review_base_ref"
assert_eq "recon:findings-merge" "g1 t1" \
  "$(printf '%s' "$recon_out" | jq -r '[.iterations[0].findings[].id] | join(" ")')" "git + thread findings concatenated"
# Empty families → valid ledger with empty findings (the fail-open shape).
recon_empty="$(reconstruct_ledger '[]' '[]')"
assert_eq "recon:empty-findings" "0" \
  "$(printf '%s' "$recon_empty" | jq -c '.iterations[0].findings | length')" "empty families → empty findings (fail-open shape)"

# ── Section 10: fetch-normalize-core.sh — normalize core + overflow tripwire (PURE) ─
echo ''
echo '=== fetch-normalize-core.sh: build_normalized_candidate_set / emit_overflow_tripwire (#245) ==='
#
# DIRECT determinism coverage for the lifted PURE normalize core. build_normalized_candidate_set
# takes EXPLICIT parameters (no caller globals) and emits the SINGLE compact normalized candidate
# array on stdout; emit_overflow_tripwire reads the three connection totalCounts off the raw payload
# and fires the >50 OVERFLOW diagnostic on stderr. Ground-truth inputs/outputs reuse the entrypoint
# oracle's canned fixtures (tests/fix-history/, tests/fetch-normalize/) so these unit assertions
# agree with the behavioral suite. SELF_LOGIN is "selfuser" to match the reused fix-history fixtures.
# Canonicalization mirrors the behavioral suite's `canon` VERBATIM: `jq -S` recursive key-sort PLUS
# a stable array sort_by the same key tuple, so element ORDER never makes a comparison brittle.
fn_canon() { jq -S -c 'sort_by((.databaseId // -1), (.url // ""), (.thread_id // ""), (.name // ""), (.surface // ""), (.classification // ""), (.item_source // ""))' 2>/dev/null; }

# 10a: review-surface-only union — the case01 review payload (handled by self fix-reply marker)
# with NO ci payload folds to exactly the expected single review record (item_source: "review").
fn_review_out="$(build_normalized_candidate_set \
  "$(cat "$FN_REVIEW_HANDLED")" "" "selfuser" "all" "$CLASSIFY_FILTER" | fn_canon)"
fn_review_exp="$(fn_canon < "$FN_EXPECTED_REVIEW")"
assert_eq "fncore:review-only-union" "$fn_review_exp" "$fn_review_out" \
  "build_normalized_candidate_set: review-only payload → expected normalized review record"

# 10b: ci-only union — an empty graphql payload with the ci-checks fixture folds to exactly the two
# bucket==fail records (item_source: "ci-check-failure", id:null), the pass/pending checks dropped.
fn_ci_out="$(build_normalized_candidate_set \
  "" "$(cat "$FN_CI_CHECKS")" "selfuser" "all" "$CLASSIFY_FILTER" | fn_canon)"
fn_ci_exp="$(fn_canon < "$FN_EXPECTED_CI")"
assert_eq "fncore:ci-only-union" "$fn_ci_exp" "$fn_ci_out" \
  "build_normalized_candidate_set: ci-only payload → two bucket==fail records, id:null"

# 10c: review + ci union — both families present → the concatenation of the review record family and
# the ci-check-failure record family (review records first, then ci records). The expected union is
# the jq -s concatenation of the two expected fixtures, canonicalized identically.
fn_union_out="$(build_normalized_candidate_set \
  "$(cat "$FN_REVIEW_HANDLED")" "$(cat "$FN_CI_CHECKS")" "selfuser" "all" "$CLASSIFY_FILTER" | fn_canon)"
fn_union_exp="$(jq -s 'add' "$FN_EXPECTED_REVIEW" "$FN_EXPECTED_CI" | fn_canon)"
assert_eq "fncore:review-plus-ci-union" "$fn_union_exp" "$fn_union_out" \
  "build_normalized_candidate_set: review + ci → concatenated review-then-ci candidate set"

# 10c-bis: ORDER-SENSITIVE union contract. fn_canon (above) sort_by-canonicalizes, which by design
# erases element order so cross-family ordering noise never flakes the value comparison — but that
# also means 10c can NOT catch a regression that REVERSES the union (ci records emitted before review
# records). The behavior-preservation contract is explicit: review-surface records are emitted FIRST,
# then ci-check-failure records (the `printf '%s\n%s\n' "$review_records" "$ci_records"` order). Assert
# the RAW (un-sorted) item_source sequence to lock that order. This complements 10c, it does not
# replace it.
fn_union_order="$(build_normalized_candidate_set \
  "$(cat "$FN_REVIEW_HANDLED")" "$(cat "$FN_CI_CHECKS")" "selfuser" "all" "$CLASSIFY_FILTER" \
  | jq -c '[.[].item_source]')"
assert_eq "fncore:union-order-review-then-ci" '["review","ci-check-failure","ci-check-failure"]' "$fn_union_order" \
  "build_normalized_candidate_set: RAW union emits review record(s) BEFORE ci-check-failure records"

# 10d: fail-OPEN on a malformed injected graphql payload → [] (NOT an error). The normalize core
# never errors on a bad injected payload; the slurp canonicalizes the empty record streams to [].
fn_malformed_out="$(build_normalized_candidate_set \
  "$(cat "$FN_MALFORMED")" "" "selfuser" "all" "$CLASSIFY_FILTER")"
assert_eq "fncore:malformed-fail-open" "[]" "$fn_malformed_out" \
  "build_normalized_candidate_set: malformed graphql payload → [] fail-open"

# 10e: fail-OPEN on an empty graphql payload AND empty ci payload → [] (both families empty).
fn_empty_out="$(build_normalized_candidate_set "" "" "selfuser" "all" "$CLASSIFY_FILTER")"
assert_eq "fncore:empty-fail-open" "[]" "$fn_empty_out" \
  "build_normalized_candidate_set: empty graphql + empty ci → [] fail-open"

# 10f: emit_overflow_tripwire FIRES on a >50 connection totalCount. The overflow-threads fixture
# carries a reviewThreads.totalCount of 51, so the >50 OVERFLOW stderr diagnostic must appear.
fn_overflow_err="$(emit_overflow_tripwire "$(cat "$FN_OVERFLOW_THREADS")" 2>&1 1>/dev/null)"
if printf '%s' "$fn_overflow_err" | grep -qF "OVERFLOW"; then
  pass "fncore:overflow-fires" "emit_overflow_tripwire emits >50 OVERFLOW diagnostic past threshold"
else
  failed "fncore:overflow-fires" "expected >50 OVERFLOW diagnostic; got: $fn_overflow_err"
fi

# 10f-bis: FULL overflow diagnostic-TEXT contract. 10f only greps for the bare "OVERFLOW" needle, so a
# regression that dropped/garbled the three counter values (reviewThreads/comments/reviews) or weakened
# the diagnostic wording would still pass. The diagnostic IS the consumer's fail-open signal and its
# exact counter payload is a behavior-preservation requirement, so assert the full line. The
# overflow-threads fixture carries reviewThreads.totalCount=51 (comments=0 reviews=0). Exact-match the
# whole stderr line (printf-captured, no needle grep).
fn_overflow_exp='github-review-loop: OVERFLOW one or more connection totalCounts exceed 50 (reviewThreads=51 comments=0 reviews=0); in-page classification is untrustworthy on the overflowed axis — the consumer must fail open (DISPATCH) per its >50 tripwire.'
assert_eq "fncore:overflow-full-diagnostic" "$fn_overflow_exp" "$fn_overflow_err" \
  "emit_overflow_tripwire: full >50 diagnostic line incl. exact counter payload (reviewThreads=51 comments=0 reviews=0)"

# 10g: emit_overflow_tripwire STAYS SILENT below the threshold. The case01 review fixture has small
# connection counts (no axis exceeds 50), so NO OVERFLOW diagnostic must be emitted (control).
fn_nooverflow_err="$(emit_overflow_tripwire "$(cat "$FN_REVIEW_HANDLED")" 2>&1 1>/dev/null)"
if printf '%s' "$fn_nooverflow_err" | grep -qF "OVERFLOW"; then
  failed "fncore:overflow-silent" "emit_overflow_tripwire wrongly fired OVERFLOW below threshold: $fn_nooverflow_err"
else
  pass "fncore:overflow-silent" "emit_overflow_tripwire stays silent below the >50 threshold"
fi

# 10h: emit_overflow_tripwire on a malformed/empty payload behaves like a 0-node page (counts default
# to 0) → NO OVERFLOW diagnostic (the overflow read fails OPEN to 0, never erroring).
fn_overflow_malformed_err="$(emit_overflow_tripwire "" 2>&1 1>/dev/null)"
if printf '%s' "$fn_overflow_malformed_err" | grep -qF "OVERFLOW"; then
  failed "fncore:overflow-empty-silent" "emit_overflow_tripwire wrongly fired on an empty payload: $fn_overflow_malformed_err"
else
  pass "fncore:overflow-empty-silent" "emit_overflow_tripwire treats empty payload as 0-node page (no OVERFLOW)"
fi

# ── Section 11: ledger-engine-io.sh — inputs-file bootstrap + ledger-open machinery ─
echo ''
echo '=== ledger-engine-io.sh: hivemind_read_inputs_file / hivemind_open_ledger ==='
#
# DIRECT unit coverage for the two shared engine-IO functions lifted VERBATIM from the three
# ledger engines (init-run-ledger, record-state-result, mark-intent-fallback). Both functions
# ORCHESTRATE the containment.sh helpers (sourced above) and NEVER exit — each returns non-zero
# with a stderr message on failure. hivemind_read_inputs_file's read-guard resolves the checkout
# via `git rev-parse --show-toplevel` INTERNALLY, so its contained-file ACCEPT case stages a real
# inputs file UNDER the live repo root (cleaned up explicitly — the EXIT trap only removes the
# /tmp WORKDIR). hivemind_open_ledger takes an EXPLICIT <repo_root>, so its fixtures live in
# WORKDIR. Each containment-reject case is staged with a REAL on-disk symlink (mirroring the
# Section 7 / engine-oracle symlink-escape staging).

# ── 11a. hivemind_read_inputs_file — arg / existence / read-guard / JSON-validity ──
# 11a-1: missing/empty arg → non-zero + the engine's exact missing-argument blocker.
rif_missing_err="$(hivemind_read_inputs_file "" "run-ledger" 2>&1 >/dev/null)"; rif_missing_rc=$?
if [ "$rif_missing_rc" -ne 0 ]; then
  pass "engineio:rif-missing-rc" "empty inputs-file arg → non-zero return"
else
  failed "engineio:rif-missing-rc" "empty inputs-file arg must return non-zero; got 0"
fi
# NEW CONTRACT (R-STEP-001/002): hivemind_read_inputs_file emits NO stderr of its OWN — it
# signals the missing-arg branch via return code 2, and the ENGINE owns the blocker text. Assert
# the EXACT return code AND that the function's own stderr (captured above as $rif_missing_err,
# which is 2>&1 with stdout discarded — i.e. fd2 only) is EMPTY, proving no self-emission.
assert_eq "engineio:rif-missing-rc-code" "2" "$rif_missing_rc" \
  "missing-arg branch returns the distinct code 2 (engine maps it to its blocker)"
assert_eq "engineio:rif-missing-no-self-stderr" "" "$rif_missing_err" \
  "missing-arg branch emits NO stderr of its own (engine owns the blocker line)"

# 11a-2: non-existent file → non-zero + the engine's exact does-not-exist blocker.
rif_absent="$WORKDIR/engineio-absent-inputs.json"   # never created
rif_absent_err="$(hivemind_read_inputs_file "$rif_absent" "record-state-result" 2>&1 >/dev/null)"; rif_absent_rc=$?
if [ "$rif_absent_rc" -ne 0 ]; then
  pass "engineio:rif-absent-rc" "non-existent inputs file → non-zero return"
else
  failed "engineio:rif-absent-rc" "non-existent inputs file must return non-zero; got 0"
fi
# NEW CONTRACT: the does-not-exist branch signals via return code 3 and emits NO own stderr.
assert_eq "engineio:rif-absent-rc-code" "3" "$rif_absent_rc" \
  "non-existent-file branch returns the distinct code 3 (engine maps it to its blocker)"
assert_eq "engineio:rif-absent-no-self-stderr" "" "$rif_absent_err" \
  "non-existent-file branch emits NO stderr of its own (engine owns the blocker line)"

# 11a-3: present-but-invalid JSON → non-zero + the engine's exact not-valid-JSON blocker. The file
# MUST live inside the repo so it passes the read-guard and reaches the jq validity probe (an
# external path would be rejected by the read-guard first, masking the JSON-validity branch).
ENGINEIO_SCRATCH="$REPO_ROOT/.hivemind-engineio-test.$$"
mkdir -p "$ENGINEIO_SCRATCH"
engineio_scratch_cleanup() { rm -rf "$ENGINEIO_SCRATCH"; return 0; }
trap 'cleanup; engineio_scratch_cleanup' EXIT
rif_badjson="$ENGINEIO_SCRATCH/bad-inputs.json"
printf '{"this is": not valid json\n' > "$rif_badjson"
rif_badjson_err="$(hivemind_read_inputs_file "$rif_badjson" "mark-intent-fallback" 2>&1 >/dev/null)"; rif_badjson_rc=$?
if [ "$rif_badjson_rc" -ne 0 ]; then
  pass "engineio:rif-badjson-rc" "invalid-JSON inputs file → non-zero return"
else
  failed "engineio:rif-badjson-rc" "invalid-JSON inputs file must return non-zero; got 0"
fi
# NEW CONTRACT: the invalid-JSON branch signals via return code 5 and emits NO own stderr — the
# internal `jq -e` probe runs with `2>&1` suppressed, so no jq diagnostic leaks to fd2 either.
assert_eq "engineio:rif-badjson-rc-code" "5" "$rif_badjson_rc" \
  "invalid-JSON branch returns the distinct code 5 (engine maps it to its blocker)"
assert_eq "engineio:rif-badjson-no-self-stderr" "" "$rif_badjson_err" \
  "invalid-JSON branch emits NO stderr of its own (jq diagnostic suppressed; engine owns the blocker)"

# 11a-4: valid, contained JSON inputs file → returns 0 (read-guard passes, jq validity passes).
rif_good="$ENGINEIO_SCRATCH/good-inputs.json"
printf '{"run":{"id":"2026-01-01T00-00-00Z--ok"}}\n' > "$rif_good"
hivemind_read_inputs_file "$rif_good" "run-ledger"; rif_good_rc=$?
assert_eq "engineio:rif-valid-rc" "0" "$rif_good_rc" "valid contained JSON inputs file → return 0"

# 11a-5: symlinked-ANCESTOR inputs path → rejected by the read-guard (mirrors the engine oracle).
# A directory component of the inputs path is a REAL symlink resolving outside the repo; the
# hivemind_assert_inputs_contained read-guard inside hivemind_read_inputs_file rejects BEFORE the
# jq validity probe. The leaf target is valid JSON, proving the rejection is the read-guard, not jq.
rif_link_dir="$ENGINEIO_SCRATCH/linkdir"
ln -s "$WORKDIR" "$rif_link_dir"   # symlinked ancestor escaping the repo into /tmp WORKDIR
printf '{"run":{"id":"x"}}\n' > "$WORKDIR/engineio-symlinked-inputs.json"
rif_link_inputs="$rif_link_dir/engineio-symlinked-inputs.json"
rif_link_err="$(hivemind_read_inputs_file "$rif_link_inputs" "run-ledger" 2>&1 >/dev/null)"; rif_link_rc=$?
if [ "$rif_link_rc" -ne 0 ]; then
  pass "engineio:rif-symlink-ancestor-reject" "symlinked-ancestor inputs path → read-guard rejects (non-zero)"
else
  failed "engineio:rif-symlink-ancestor-reject" "symlinked-ancestor inputs path must be rejected by the read-guard; got 0"
fi
# NEW CONTRACT: the containment reject is signalled by the DISTINCT code 4, and — unlike the other
# branches — the INNER helper hivemind_assert_inputs_contained emits its OWN raw UNPREFIXED detail
# line to fd2 (uncaptured passthrough); hivemind_read_inputs_file adds NO line of its own. The
# engine maps code 4 to its blocker, so the detail line that reaches fd2 here is the inner helper's,
# NOT a self-emitted message. Assert the exact code AND that the inner-helper detail line is present
# on fd2 (captured above as $rif_link_err). The detail for an ancestor-escape is the helper's
# "resolves outside the checkout" line (containment.sh), distinct from the engine's blocker text.
assert_eq "engineio:rif-symlink-ancestor-rc-code" "4" "$rif_link_rc" \
  "containment-reject branch returns the distinct code 4 (engine maps it to its blocker)"
case "$rif_link_err" in
  *"resolves outside the checkout"*)
    pass "engineio:rif-symlink-ancestor-inner-detail-on-fd2" \
      "inner-helper detail line reached fd2 as passthrough (uncaptured), proving read_inputs_file added none" ;;
  *)
    failed "engineio:rif-symlink-ancestor-inner-detail-on-fd2" \
      "expected inner-helper detail line on fd2 containing 'resolves outside the checkout'; got: $rif_link_err" ;;
esac

# ── 11b. hivemind_open_ledger — derive / contain / read / coherence / canonical confirm ──
# These take an EXPLICIT <repo_root>, so every fixture is a self-contained fake checkout in WORKDIR.

# 11b-1: missing ledger file — the run dir exists but state.json was never written → non-zero.
ol1_root="$WORKDIR/ol1/checkout"
ol1_run_id="2026-01-01T00-00-00Z--ol1"
mkdir -p "$ol1_root/.hivemind/runs/$ol1_run_id"
# Do NOT create state.json.
ol1_err="$(hivemind_open_ledger "$ol1_root" "$ol1_run_id" 2>&1 >/dev/null)"; ol1_rc=$?
if [ "$ol1_rc" -ne 0 ]; then
  pass "engineio:ol-missing-ledger-rc" "missing ledger file → non-zero return"
else
  failed "engineio:ol-missing-ledger-rc" "missing ledger file must return non-zero; got 0"
fi

# 11b-2: coherence mismatch — ledger .run.id differs from the passed run_id → non-zero.
ol2_root="$WORKDIR/ol2/checkout"
ol2_run_id="2026-01-01T00-00-00Z--ol2"
mkdir -p "$ol2_root/.hivemind/runs/$ol2_run_id"
printf '{"run":{"id":"2026-01-01T00-00-00Z--DIFFERENT"},"state":{"current":"plan"}}\n' \
  > "$ol2_root/.hivemind/runs/$ol2_run_id/state.json"
ol2_err="$(hivemind_open_ledger "$ol2_root" "$ol2_run_id" 2>&1 >/dev/null)"; ol2_rc=$?
if [ "$ol2_rc" -ne 0 ]; then
  pass "engineio:ol-coherence-mismatch-rc" "ledger .run.id != run_id → non-zero return"
else
  failed "engineio:ol-coherence-mismatch-rc" "coherence mismatch must return non-zero; got 0"
fi

# 11b-3: valid ledger — coherent .run.id, contained leaf → returns 0 with EMPTY stdout (new
# contract: the lib no longer echoes the canonical ledger path / run dir; the consumer derives
# them). We assert (a) rc == 0, (b) no stdout, and (c) that the consumer-side derivation
# reproduces the exact canonical path the lib previously emitted (locks derive-in-consumer).
ol3_root="$WORKDIR/ol3/checkout"
ol3_run_id="2026-01-01T00-00-00Z--ol3"
mkdir -p "$ol3_root/.hivemind/runs/$ol3_run_id"
printf '{"run":{"id":"%s"},"state":{"current":"implement_step"}}\n' "$ol3_run_id" \
  > "$ol3_root/.hivemind/runs/$ol3_run_id/state.json"
ol3_out="$(hivemind_open_ledger "$ol3_root" "$ol3_run_id")"; ol3_rc=$?
assert_eq "engineio:ol-valid-rc" "0" "$ol3_rc" "valid coherent ledger → return 0"
if [ -z "$ol3_out" ]; then
  pass "engineio:ol-valid-empty-stdout" "valid ledger → empty stdout (no canonical lines emitted)"
else
  failed "engineio:ol-valid-empty-stdout" \
    "valid ledger must emit empty stdout; got: $ol3_out"
fi
# Consumer-side derivation must reproduce the canonical path the lib previously returned.
# Canonical expectation: cd && pwd -P the on-disk run dir (handles a symlinked /tmp prefix on macOS).
ol3_canon_dir="$(cd "$ol3_root/.hivemind/runs/$ol3_run_id" && pwd -P)"
ol3_derived_dir="$(cd "$ol3_root/.hivemind/runs/$ol3_run_id" && pwd -P)"
ol3_derived_ledger="$ol3_derived_dir/state.json"
assert_eq "engineio:ol-valid-derived-dir" "$ol3_canon_dir" "$ol3_derived_dir" \
  "consumer derivation reproduces canonical run dir"
assert_eq "engineio:ol-valid-derived-ledger" "$ol3_canon_dir/state.json" "$ol3_derived_ledger" \
  "consumer derivation reproduces canonical ledger path ending /state.json"

# 11b-4: containment reject staged with a REAL symlink — the state.json LEAF is a symlink to an
# external (out-of-checkout) target. hivemind_assert_ledger_contained [ -L ]-rejects the leaf
# BEFORE any read → non-zero, and the on-disk ledger is never followed.
ol4_root="$WORKDIR/ol4/checkout"
ol4_ext="$WORKDIR/ol4/external"
ol4_run_id="2026-01-01T00-00-00Z--ol4"
mkdir -p "$ol4_root/.hivemind/runs/$ol4_run_id" "$ol4_ext"
printf '{"run":{"id":"%s"},"state":{"current":"plan"}}\n' "$ol4_run_id" \
  > "$ol4_ext/secret-state.json"
ln -s "$ol4_ext/secret-state.json" "$ol4_root/.hivemind/runs/$ol4_run_id/state.json"
ol4_err="$(hivemind_open_ledger "$ol4_root" "$ol4_run_id" 2>&1 >/dev/null)"; ol4_rc=$?
if [ "$ol4_rc" -ne 0 ]; then
  pass "engineio:ol-symlinked-leaf-reject" "symlinked state.json leaf → containment reject (non-zero)"
else
  failed "engineio:ol-symlinked-leaf-reject" "symlinked state.json leaf must be rejected; got 0"
fi

# ── Section 12: settings-merge.sh ───────────────────────────────────────────────
echo ''
echo '=== settings-merge.sh: frozen template + required-key merge core ==='
#
# AUTHORITATIVE regression tests for the seed-hive `.claude/settings.json` merge core. The
# merge function takes the settings JSON as a STRING and emits the OUTPUT CONTRACT JSON object;
# it performs NO file I/O. Each case feeds an inline settings string and asserts the emitted
# classification, the merged settings, and the conflict/idempotency/union invariants from
# seed-hive/SKILL.md step 6 + Merge Rules.

# 12a. Frozen template is the SINGLE DATA source (P1): `hivemind_settings_permissions_template`
# is the sole place the 25 rules live, so this case locks its literal content/order self-contained
# — no SKILL.md mirror. The lib emits LF; trailing whitespace is stripped for a clean compare.
SM_LIB_TEMPLATE="$WORKDIR/lib-template.txt"
hivemind_settings_permissions_template | sed 's/[[:space:]]*$//' > "$SM_LIB_TEMPLATE"
assert_eq "settings:template-rule-count" "25" \
  "$(wc -l < "$SM_LIB_TEMPLATE" | tr -d ' ')" "frozen template has 25 rules"
read -r -d '' SM_EXPECTED_TEMPLATE <<'TEMPLATE'
Bash(echo *)
Bash(printf *)
Bash(cat *)
Bash(grep *)
Bash(jq *)
Bash(head *)
Bash(tail *)
Bash(ls *)
Bash(wc *)
Bash(sort *)
Bash(uniq *)
Bash(git ls-files *)
Bash(git ls-tree *)
Bash(git grep *)
Bash(git tag)
Bash(git tag -l*)
Bash(git tag --list*)
Bash(git stash list)
Bash(git stash show *)
Edit(.hivemind/review-loop/*)
Edit(.hivemind/runs/.init-inputs-*.json)
Edit(.hivemind/runs/.record-inputs-*.json)
Edit(.hivemind/runs/.markfb-inputs-*.json)
Edit(.hivemind/spawn-inputs.*.json)
Edit(.hivemind/seed-inputs-*.json)
TEMPLATE
assert_eq "settings:template-content-order" "$SM_EXPECTED_TEMPLATE" \
  "$(cat "$SM_LIB_TEMPLATE")" "frozen template emits the expected 25 rules in order"

# ── caveman SubagentStart hook identity constants under test (issue #352) ──
# The three commands below are the ONLY three this merge has ever authored, and they are NOT
# interchangeable — each names a distinct engine execution branch:
# SM_HOOK_LEGACY — the bare relative SHELL-form command released at 2.40.10. Migratable.
# SM_HOOK_QUOTED — the double-quoted anchored SHELL-form command added on this branch at the
#                  unreleased 2.40.11. The `"` characters around ${CLAUDE_PROJECT_DIR} are PART
#                  of the command STRING; under the shell branch the harness performs NO
#                  substitution and the shell's own expansion is what resolved it. Migratable.
# SM_HOOK_CANON  — the canonical EXEC-form command written today, UNQUOTED. Under exec form the
#                  substituted string reaches execve verbatim, so surrounding `"` would become
#                  literal path characters and break the spawn. Paired ALWAYS with `args: []`,
#                  which is what SELECTS the exec branch (the engine tests whether `args` is
#                  DEFINED, not its length) — so every command assertion below is accompanied by
#                  an `args` assertion, or it does not prove exec form was wired.
# Neither shell-form constant is an identity SUBSTRING: identity is exact equality on an
# exec-form entry, never containment. All three are single-quoted so the shell never expands the
# brace form, and all are passed into jq filters via --arg (never spliced into filter text) so
# the shell and jq agree on the exact bytes under assertion.
SM_HOOK_LEGACY='.claude/hooks/caveman-ultra-subagent.sh'
SM_HOOK_QUOTED='"${CLAUDE_PROJECT_DIR}"/.claude/hooks/caveman-ultra-subagent.sh'
SM_HOOK_CANON='${CLAUDE_PROJECT_DIR}/.claude/hooks/caveman-ultra-subagent.sh'

# Merge helper: run the merge and capture the JSON result for jq assertions.
# Usage: sm_result="$(hivemind_settings_merge "$settings" "$agent" caveman mem codex allow)"
# then: assert_eq <case> <expected> "$(printf '%s' "$sm_result" | jq -r '<filter>')" <msg>

# 12b. Merge from {} (absent-file case): every required key `added`, agent set, full template.
sm_from_empty="$(hivemind_settings_merge '' 'hivemind:overlord' 'no' 'no' 'no' 'yes')"
assert_eq "settings:empty-status" "ok" \
  "$(printf '%s' "$sm_from_empty" | jq -r '.status')" "empty input → ok"
assert_eq "settings:empty-agent-class" "added" \
  "$(printf '%s' "$sm_from_empty" | jq -r '.keys.agent')" "agent added from {}"
assert_eq "settings:empty-agent-value" "hivemind:overlord" \
  "$(printf '%s' "$sm_from_empty" | jq -r '.settings.agent')" "agent value written"
assert_eq "settings:empty-hive-class" "added" \
  "$(printf '%s' "$sm_from_empty" | jq -r '.keys["enabledPlugins.hivemind@brenpike"]')" "hivemind enabledPlugin added"
assert_eq "settings:empty-hive-value" "true" \
  "$(printf '%s' "$sm_from_empty" | jq -r '.settings.enabledPlugins["hivemind@brenpike"]')" "hivemind enabledPlugin = true"
# 12b: absent permissions.allow → created in template ORDER (first rule = Bash(echo *)).
assert_eq "settings:empty-allow-count" "25" \
  "$(printf '%s' "$sm_from_empty" | jq -r '.settings.permissions.allow | length')" "absent allow → 25 template rules created"
assert_eq "settings:empty-allow-first" "Bash(echo *)" \
  "$(printf '%s' "$sm_from_empty" | jq -r '.settings.permissions.allow[0]')" "created allow is in template order (first rule)"
assert_eq "settings:empty-allow-last" "Edit(.hivemind/seed-inputs-*.json)" \
  "$(printf '%s' "$sm_from_empty" | jq -r '.settings.permissions.allow[-1]')" "created allow is in template order (last rule)"
assert_eq "settings:empty-allow-report-count" "25" \
  "$(printf '%s' "$sm_from_empty" | jq -r '.permissions_allow | length')" "permissions_allow reports one entry per template rule"
assert_eq "settings:empty-allow-all-added" "added" \
  "$(printf '%s' "$sm_from_empty" | jq -r '[.permissions_allow[].result] | unique | .[0]')" "every template rule reported added from {}"

# 12c. companion toggles: yes writes the keys; no classifies `resolved no` and writes nothing.
sm_companions="$(hivemind_settings_merge '' 'hivemind:overlord' 'yes' 'yes' 'yes' 'no')"
assert_eq "settings:cave-on-class" "added" \
  "$(printf '%s' "$sm_companions" | jq -r '.keys["enabledPlugins.caveman@caveman"]')" "caveman=yes → added"
assert_eq "settings:cave-on-value" "true" \
  "$(printf '%s' "$sm_companions" | jq -r '.settings.enabledPlugins["caveman@caveman"]')" "caveman enabledPlugin = true"
assert_eq "settings:cave-pcfg-level" "ultra" \
  "$(printf '%s' "$sm_companions" | jq -r '.settings.pluginConfigs["caveman@caveman"].options.defaultLevel')" "caveman pluginConfig defaultLevel = ultra"
assert_eq "settings:cave-hook-cmd" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_companions" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].command')" "SubagentStart hook command wired (project-root ANCHORED, UNQUOTED exec form)"
assert_eq "settings:cave-hook-type" "command" \
  "$(printf '%s' "$sm_companions" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].type')" "SubagentStart hook type = command"
assert_eq "settings:cave-hook-args" "[]" \
  "$(printf '%s' "$sm_companions" | jq -c '.settings.hooks.SubagentStart[0].hooks[0].args')" "args:[] present — this is what SELECTS the exec branch"
assert_eq "settings:mem-on-value" "true" \
  "$(printf '%s' "$sm_companions" | jq -r '.settings.enabledPlugins["claude-mem@thedotmack"]')" "claude_mem=yes → enabledPlugin true"
assert_eq "settings:codex-on-value" "true" \
  "$(printf '%s' "$sm_companions" | jq -r '.settings.enabledPlugins["codex@openai-codex"]')" "codex=yes → enabledPlugin true"
# All companions off → classified `resolved no`, NONE written.
sm_no_companions="$(hivemind_settings_merge '' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:cave-off-class" "resolved no" \
  "$(printf '%s' "$sm_no_companions" | jq -r '.keys["enabledPlugins.caveman@caveman"]')" "caveman=no → resolved no"
assert_eq "settings:cave-off-absent" "null" \
  "$(printf '%s' "$sm_no_companions" | jq -r '.settings.enabledPlugins["caveman@caveman"] // "null"')" "caveman=no → key not written"
assert_eq "settings:cave-pcfg-off-absent" "null" \
  "$(printf '%s' "$sm_no_companions" | jq -r '.settings.pluginConfigs // "null"')" "caveman=no → no pluginConfigs"
assert_eq "settings:cave-hook-off-absent" "null" \
  "$(printf '%s' "$sm_no_companions" | jq -r '.settings.hooks // "null"')" "caveman=no → no hooks"

# 12c-bis. caveman hook APPENDS to an existing UNRELATED SubagentStart array (add-if-absent on the
# SPECIFIC command, not on the presence of the SubagentStart key). The existing entry is preserved,
# the caveman entry appended, classified `added`; and a re-merge is idempotent (no duplicate).
sm_pre_hook='{"hooks":{"SubagentStart":[{"hooks":[{"type":"command","command":".claude/hooks/other.sh"}]}]}}'
sm_existing_hook="$(hivemind_settings_merge "$sm_pre_hook" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-existing-class" "added" \
  "$(printf '%s' "$sm_existing_hook" | jq -r '.keys["hooks.SubagentStart"]')" "caveman hook absent from existing SubagentStart → added"
assert_eq "settings:cave-hook-existing-count" "2" \
  "$(printf '%s' "$sm_existing_hook" | jq -r '.settings.hooks.SubagentStart | length')" "existing SubagentStart entry preserved + caveman appended"
assert_eq "settings:cave-hook-existing-preserved" ".claude/hooks/other.sh" \
  "$(printf '%s' "$sm_existing_hook" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].command')" "existing unrelated hook command preserved at index 0"
assert_eq "settings:cave-hook-existing-appended" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_existing_hook" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].command')" "canonical anchored caveman hook appended at index 1"
assert_eq "settings:cave-hook-existing-appended-args" "[]" \
  "$(printf '%s' "$sm_existing_hook" | jq -c '.settings.hooks.SubagentStart[1].hooks[0].args')" "appended entry carries args:[] (exec form)"
sm_existing_hook_settings="$(printf '%s' "$sm_existing_hook" | jq -c '.settings')"
sm_existing_hook_twice="$(hivemind_settings_merge "$sm_existing_hook_settings" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-existing-idem-class" "already present" \
  "$(printf '%s' "$sm_existing_hook_twice" | jq -r '.keys["hooks.SubagentStart"]')" "re-merge with caveman hook wired → already present"
assert_eq "settings:cave-hook-existing-idem-count" "2" \
  "$(printf '%s' "$sm_existing_hook_twice" | jq -r '.settings.hooks.SubagentStart | length')" "re-merge does not duplicate the caveman hook"

# 12c-bis2. caveman hook PRESENT-PREDICATE TYPE-CHECK (Codex P1 @ settings-merge.sh:411): an existing
# SubagentStart entry whose `.command` MATCHES the caveman hook but whose `.type` is missing/wrong is an
# INVALID hook. It matches NEITHER the classification predicate NOR the migrate pass (both are gated on
# `.type == "command"`), so a wrong-typed entry carrying the LEGACY command classifies `added`, is LEFT
# IN PLACE UNMIGRATED, and the canonical anchored {type:"command", command} entry is APPENDED beside it.
# Non-vacuous: the prior command-only predicate matched the wrong-typed entry → `already present`,
# appended nothing (length stays 1, no canonical-typed entry); and the pre-#352 append wrote the BARE
# command, so the class, the count, the anchored-entry, and the left-in-place assertions all fail.
# The canonical-present probe below requires `.args` to be an ARRAY, so a shell-form append would
# not satisfy it either.
sm_pre_wrongtype='{"hooks":{"SubagentStart":[{"hooks":[{"type":"foo","command":".claude/hooks/caveman-ultra-subagent.sh"}]}]}}'
sm_wrongtype="$(hivemind_settings_merge "$sm_pre_wrongtype" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-wrongtype-class" "added" \
  "$(printf '%s' "$sm_wrongtype" | jq -r '.keys["hooks.SubagentStart"]')" "legacy command but .type wrong → invalid hook → added"
assert_eq "settings:cave-hook-wrongtype-count" "2" \
  "$(printf '%s' "$sm_wrongtype" | jq -r '.settings.hooks.SubagentStart | length')" "wrong-typed entry left in place + canonical entry appended"
assert_eq "settings:cave-hook-wrongtype-canonical-present" "true" \
  "$(printf '%s' "$sm_wrongtype" | jq -r --arg c "$SM_HOOK_CANON" '[.settings.hooks.SubagentStart[].hooks[] | select(.type == "command" and .args == [] and .command == $c)] | length > 0')" "a {type:\"command\", ANCHORED caveman command, args:[]} exec-form entry now exists"
assert_eq "settings:cave-hook-wrongtype-left-in-place" "foo|$SM_HOOK_LEGACY|null" \
  "$(printf '%s' "$sm_wrongtype" | jq -r '.settings.hooks.SubagentStart[0].hooks[0] | "\(.type)|\(.command)|\(.args)"')" "wrong-typed entry NOT migrated (migrate pass is .type-gated) and left byte-identical — no args key grown"

# 12c-bis3. HOOK COMMAND ANCHORING (issue #352) — the STRUCTURAL IDENTITY contract. Identity is
# EXACT VALUE EQUALITY on an EXEC-FORM entry — `.type == "command"` AND `.args == []` AND
# `.command == SM_HOOK_CANON` — never substring containment, and never a TYPE test standing in for
# a value (see (d1): a type-tested `args` admitted unexecutable `[null]`/`[1]` entries as ours).
# Precedence, per `.hooks[]` element:
#   1. exec-form canonical entry (command == CANON, args == []) → already present, untouched
#   2. shell-form entry (NO `args` key) whose STRING `.command` is a MEMBER of the frozen
#      authored list {LEGACY bare, QUOTED anchored}          → added, MIGRATED IN PLACE to exec form
#   3. any other command — including one that merely CONTAINS the script path → NOT identity,
#      left BYTE-UNTOUCHED, and the canonical entry is APPENDED beside it
#   4. entry whose .type != "command"                        → ignored by both passes (12c-bis2)
#   5. no identity match anywhere                            → added, canonical APPENDED
# There is NO new report token: a rewrite reports `added`, sharing the token with the append case.
# The report token is DERIVED from the mutation (post-build vs canon-normalized pre-state), so it
# cannot disagree with what was written.

# (a) MIGRATION, LEGACY BARE-RELATIVE: a legacy bare command is rewritten IN PLACE to EXEC form —
# no duplicate, no append. Sibling keys on the hook entry and SubagentStart array ORDER both
# survive (only `.command` and `.args` are assigned).
# Non-vacuous: pre-#352 the predicate matched the legacy command EXACTLY, so the class was
# `already present` and the command was never rewritten — the class and command assertions fail.
sm_pre_legacy='{"hooks":{"SubagentStart":[{"hooks":[{"type":"command","command":".claude/hooks/other.sh"}]},{"hooks":[{"type":"command","command":".claude/hooks/caveman-ultra-subagent.sh","timeout":30}]}]}}'
sm_legacy="$(hivemind_settings_merge "$sm_pre_legacy" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-migrate-class" "added" \
  "$(printf '%s' "$sm_legacy" | jq -r '.keys["hooks.SubagentStart"]')" "legacy bare command → corrected in place → added"
assert_eq "settings:cave-hook-migrate-count" "2" \
  "$(printf '%s' "$sm_legacy" | jq -r '.settings.hooks.SubagentStart | length')" "migration rewrites in place — no duplicate appended"
assert_eq "settings:cave-hook-migrate-cmd" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_legacy" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].command')" "legacy command rewritten to the UNQUOTED exec-form command"
assert_eq "settings:cave-hook-migrate-args" "[]" \
  "$(printf '%s' "$sm_legacy" | jq -c '.settings.hooks.SubagentStart[1].hooks[0].args')" "migration sets args:[] — a rewritten command without it stays on the shell branch"
assert_eq "settings:cave-hook-migrate-sibling-key" "30" \
  "$(printf '%s' "$sm_legacy" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].timeout')" "sibling key on the migrated hook entry preserved"
assert_eq "settings:cave-hook-migrate-order" ".claude/hooks/other.sh" \
  "$(printf '%s' "$sm_legacy" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].command')" "SubagentStart array order preserved (unrelated entry still at index 0)"

# (b) MIGRATION IDEMPOTENCY: re-merging the migrated output classifies `already present`, adds
# nothing, and is byte-stable. Non-vacuous on the command assertion: pre-#352 the (unmigrated)
# re-merge output still carried the bare command.
sm_legacy_settings="$(printf '%s' "$sm_legacy" | jq -c '.settings')"
sm_legacy_twice="$(hivemind_settings_merge "$sm_legacy_settings" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-migrate-idem-class" "already present" \
  "$(printf '%s' "$sm_legacy_twice" | jq -r '.keys["hooks.SubagentStart"]')" "re-merge of migrated settings → already present"
assert_eq "settings:cave-hook-migrate-idem-count" "2" \
  "$(printf '%s' "$sm_legacy_twice" | jq -r '.settings.hooks.SubagentStart | length')" "re-merge of migrated settings adds nothing"
assert_eq "settings:cave-hook-migrate-idem-cmd" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_legacy_twice" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].command')" "migrated command stays anchored across re-merge"
assert_eq "settings:cave-hook-migrate-idem-args" "[]" \
  "$(printf '%s' "$sm_legacy_twice" | jq -c '.settings.hooks.SubagentStart[1].hooks[0].args')" "migrated entry keeps args:[] across re-merge"
assert_eq "settings:cave-hook-migrate-idem-bytes" "$(printf '%s' "$sm_legacy" | jq -cS '.settings')" \
  "$(printf '%s' "$sm_legacy_twice" | jq -cS '.settings')" "migrated settings are byte-stable under re-merge"

# (b2) MIGRATION, QUOTED-ANCHORED SHELL FORM (the unreleased 2.40.11 shape): the OTHER member of
# the frozen authored list. It carries no `args` key, so it is on the SHELL branch where the
# harness never substitutes ${CLAUDE_PROJECT_DIR} — only the shell's own expansion made it work.
# It migrates IN PLACE to the UNQUOTED exec form (the `"` characters must GO, or they reach execve
# as literal path bytes), reports `added`, and appends NOTHING.
# Non-vacuous: under the previous substring-identity implementation this entry CONTAINED the
# script path, so it classified `already present` and was left carrying the quoted shell command —
# the class, command, and args assertions all fail there.
sm_pre_quoted='{"hooks":{"SubagentStart":[{"hooks":[{"type":"command","command":"\"${CLAUDE_PROJECT_DIR}\"/.claude/hooks/caveman-ultra-subagent.sh"}]}]}}'
sm_quoted="$(hivemind_settings_merge "$sm_pre_quoted" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-quoted-class" "added" \
  "$(printf '%s' "$sm_quoted" | jq -r '.keys["hooks.SubagentStart"]')" "quoted shell-form command → corrected in place → added"
assert_eq "settings:cave-hook-quoted-count" "1" \
  "$(printf '%s' "$sm_quoted" | jq -r '.settings.hooks.SubagentStart | length')" "quoted form migrates in place — nothing appended"
assert_eq "settings:cave-hook-quoted-cmd" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_quoted" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].command')" "quoted command rewritten to the UNQUOTED exec-form command"
assert_eq "settings:cave-hook-quoted-args" "[]" \
  "$(printf '%s' "$sm_quoted" | jq -c '.settings.hooks.SubagentStart[0].hooks[0].args')" "migrated quoted entry now carries args:[]"
assert_eq "settings:cave-hook-quoted-no-quoted-left" "0" \
  "$(printf '%s' "$sm_quoted" | jq -r --arg q "$SM_HOOK_QUOTED" '[.settings.hooks.SubagentStart[].hooks[] | select(.command == $q)] | length')" "no quoted shell-form command survives the migration"
sm_quoted_settings="$(printf '%s' "$sm_quoted" | jq -c '.settings')"
sm_quoted_twice="$(hivemind_settings_merge "$sm_quoted_settings" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-quoted-idem-class" "already present" \
  "$(printf '%s' "$sm_quoted_twice" | jq -r '.keys["hooks.SubagentStart"]')" "re-merge of the migrated quoted entry → already present"
assert_eq "settings:cave-hook-quoted-idem-count" "1" \
  "$(printf '%s' "$sm_quoted_twice" | jq -r '.settings.hooks.SubagentStart | length')" "re-merge of the migrated quoted entry adds nothing"

# (c) ALREADY EXEC FORM: the canonical entry is recognised by EXACT equality, untouched, never
# duplicated, and the whole hooks block is byte-stable.
# Non-vacuous: the previous implementation's canonical entry was the QUOTED shell form, so this
# exec-form pre-state did not match its exact-equality arm; and its append wrote a shell-form
# entry, so the byte-stability assertion fails there.
sm_pre_canon='{"hooks":{"SubagentStart":[{"hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/caveman-ultra-subagent.sh","args":[]}]}]}}'
sm_canon_idem="$(hivemind_settings_merge "$sm_pre_canon" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-canon-idem-class" "already present" \
  "$(printf '%s' "$sm_canon_idem" | jq -r '.keys["hooks.SubagentStart"]')" "canonical exec-form entry re-merged → already present"
assert_eq "settings:cave-hook-canon-idem-count" "1" \
  "$(printf '%s' "$sm_canon_idem" | jq -r '.settings.hooks.SubagentStart | length')" "re-merge of canonical entry does not duplicate"
assert_eq "settings:cave-hook-canon-idem-bytes" "$(printf '%s' "$sm_pre_canon" | jq -cS '.hooks')" \
  "$(printf '%s' "$sm_canon_idem" | jq -cS '.settings.hooks')" "already-canonical hooks block is byte-stable (no-op)"

# (d) USER-CUSTOM WRAPPER — EXPECTATIONS DELIBERATELY INVERTED AT #352. This is a CONTRACT CHANGE,
# not a test that "should still pass". A command that merely CONTAINS the script path (here,
# invoked through `bash`) is NOT hivemind wiring: it is not a member of the frozen authored list,
# so it is never rewritten, AND it is not exec-form canonical, so it NO LONGER SUPPRESSES the
# append. Such a project gains ONE additional entry, ONCE.
# THE DELIBERATE TRADE, with its failure direction: suppression-by-heuristic failed as "the hook is
# SILENTLY NEVER WIRED" — an invisible, permanent loss of the behaviour the seed exists to install.
# Exact identity fails in the OPPOSITE direction: "the context hook FIRES TWICE" — visible,
# harmless for a context-injection hook, bounded at one extra entry, and idempotent thereafter (the
# second merge below is what pins the bound). The visible bounded failure is the one to prefer.
# Non-vacuous: under the previous substring-identity implementation this entry suppressed the
# append → `already present`, length 1 — both the class and the count assertions fail there.
sm_pre_custom='{"hooks":{"SubagentStart":[{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PROJECT_DIR}\"/.claude/hooks/caveman-ultra-subagent.sh"}]}]}}'
sm_custom="$(hivemind_settings_merge "$sm_pre_custom" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-custom-class" "added" \
  "$(printf '%s' "$sm_custom" | jq -r '.keys["hooks.SubagentStart"]')" "user-custom wrapper is NOT identity → canonical entry added beside it"
assert_eq "settings:cave-hook-custom-count" "2" \
  "$(printf '%s' "$sm_custom" | jq -r '.settings.hooks.SubagentStart | length')" "wrapper no longer suppresses the append (the accepted deliberate drop)"
assert_eq "settings:cave-hook-custom-untouched" 'bash "${CLAUDE_PROJECT_DIR}"/.claude/hooks/caveman-ultra-subagent.sh' \
  "$(printf '%s' "$sm_custom" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].command')" "user-custom command left byte-untouched at index 0 (neither migrated nor replaced)"
assert_eq "settings:cave-hook-custom-no-args-grown" "null" \
  "$(printf '%s' "$sm_custom" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].args')" "user-custom entry gains no args key — the merge never rewrites what it did not author"
assert_eq "settings:cave-hook-custom-appended" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_custom" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].command')" "canonical exec-form entry appended at index 1"
assert_eq "settings:cave-hook-custom-appended-args" "[]" \
  "$(printf '%s' "$sm_custom" | jq -c '.settings.hooks.SubagentStart[1].hooks[0].args')" "appended entry beside the wrapper carries args:[]"
# The bound: ONE extra entry, ONCE. A second merge is a no-op, so the trade never compounds.
sm_custom_settings="$(printf '%s' "$sm_custom" | jq -c '.settings')"
sm_custom_twice="$(hivemind_settings_merge "$sm_custom_settings" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-custom-idem-class" "already present" \
  "$(printf '%s' "$sm_custom_twice" | jq -r '.keys["hooks.SubagentStart"]')" "re-merge beside the wrapper → already present (append is one-time)"
assert_eq "settings:cave-hook-custom-idem-count" "2" \
  "$(printf '%s' "$sm_custom_twice" | jq -r '.settings.hooks.SubagentStart | length')" "re-merge appends nothing further — the extra entry is bounded at one"

# (d1) CLOSED LOOSELY-JUDGED-FIELD CLASS — identity is EXACT VALUE equality on `args`, not a TYPE
# test. Under the earlier `(.args | type) == "array"` conjunct, an entry carrying the canonical
# command with ANY array `args` counted as ours. That admitted `args: [null]` and `args: [1]`,
# which the verified schema (`args: z.array(z.string()).optional()`, ADR-0028) cannot execute: the
# merge reported `already present`, left the unexecutable entry in place, and SUPPRESSED the valid
# canonical append — the same silently-never-wired failure the substring class produced, reached
# through a different loosely-judged field.
# `args == []` is the emitted canonical value, so no field of the identity key is judged by type
# and there is no remaining "acceptable shape" set for a later pass to enumerate one value at a
# time. A well-formed but NON-EMPTY `args` is covered here on purpose: it is user-authored
# variation, not our entry, and takes the SAME accepted deliberate drop as the (d) wrapper — left
# byte-untouched, one extra entry, once, hook fires twice rather than never.
# Non-vacuous: under the type-test conjunct all three of these classified `already present` with
# count 1, so every class and count assertion below fails there.
sm_argsvar_i=0
for sm_argsvar_args in '[null]' '[1]' '["--x"]'
do
  sm_argsvar_i=$((sm_argsvar_i + 1))
  sm_pre_argsvar="$(jq -nc --arg c "$SM_HOOK_CANON" --argjson a "$sm_argsvar_args" '{hooks:{SubagentStart:[{hooks:[{type:"command",command:$c,args:$a}]}]}}')"
  sm_argsvar="$(hivemind_settings_merge "$sm_pre_argsvar" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
  assert_eq "settings:cave-hook-argsvar-$sm_argsvar_i-class" "added" \
    "$(printf '%s' "$sm_argsvar" | jq -r '.keys["hooks.SubagentStart"]')" "canonical command with args $sm_argsvar_args is NOT identity → added"
  assert_eq "settings:cave-hook-argsvar-$sm_argsvar_i-count" "2" \
    "$(printf '%s' "$sm_argsvar" | jq -r '.settings.hooks.SubagentStart | length')" "args $sm_argsvar_args no longer suppresses the canonical append"
  assert_eq "settings:cave-hook-argsvar-$sm_argsvar_i-untouched" "$sm_argsvar_args" \
    "$(printf '%s' "$sm_argsvar" | jq -c '.settings.hooks.SubagentStart[0].hooks[0].args')" "pre-existing args $sm_argsvar_args left byte-untouched (never rewritten)"
  assert_eq "settings:cave-hook-argsvar-$sm_argsvar_i-appended" "$SM_HOOK_CANON" \
    "$(printf '%s' "$sm_argsvar" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].command')" "canonical exec-form entry appended beside args $sm_argsvar_args"
  assert_eq "settings:cave-hook-argsvar-$sm_argsvar_i-appended-args" "[]" \
    "$(printf '%s' "$sm_argsvar" | jq -c '.settings.hooks.SubagentStart[1].hooks[0].args')" "appended entry beside args $sm_argsvar_args carries the canonical args:[]"
  # The bound: ONE extra entry, ONCE — the canonical entry now present suppresses every re-merge.
  sm_argsvar_twice="$(hivemind_settings_merge "$(printf '%s' "$sm_argsvar" | jq -c '.settings')" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
  assert_eq "settings:cave-hook-argsvar-$sm_argsvar_i-idem-class" "already present" \
    "$(printf '%s' "$sm_argsvar_twice" | jq -r '.keys["hooks.SubagentStart"]')" "re-merge beside args $sm_argsvar_args → already present"
  assert_eq "settings:cave-hook-argsvar-$sm_argsvar_i-idem-count" "2" \
    "$(printf '%s' "$sm_argsvar_twice" | jq -r '.settings.hooks.SubagentStart | length')" "re-merge appends nothing further — bounded at one extra entry"
done

# (d2) CLOSED SUBSTRING FALSE-POSITIVE CLASS — the three shapes the reviewer REPRODUCED. Under the
# previous substring-identity implementation each of these CONTAINED the script path, so each
# classified `already present` and SUPPRESSED the append: the project's hook was NEVER WIRED, and
# the report said it already was. Each must now report `added` with the canonical exec-form entry
# appended, and each pre-state entry left byte-untouched.
# Non-vacuous by construction: every one of these asserts class `added` and count 2, and the old
# implementation produced `already present` and count 1 for all three.
sm_falsepos_i=0
for sm_falsepos_cmd in \
  'echo .claude/hooks/caveman-ultra-subagent.sh' \
  '/some/other/project/.claude/hooks/caveman-ultra-subagent.sh' \
  'true # .claude/hooks/caveman-ultra-subagent.sh'
do
  sm_falsepos_i=$((sm_falsepos_i + 1))
  sm_pre_falsepos="$(jq -nc --arg c "$sm_falsepos_cmd" '{hooks:{SubagentStart:[{hooks:[{type:"command",command:$c}]}]}}')"
  sm_falsepos="$(hivemind_settings_merge "$sm_pre_falsepos" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
  assert_eq "settings:cave-hook-falsepos-$sm_falsepos_i-class" "added" \
    "$(printf '%s' "$sm_falsepos" | jq -r '.keys["hooks.SubagentStart"]')" "substring-only match [$sm_falsepos_cmd] is NOT identity → added"
  assert_eq "settings:cave-hook-falsepos-$sm_falsepos_i-count" "2" \
    "$(printf '%s' "$sm_falsepos" | jq -r '.settings.hooks.SubagentStart | length')" "substring-only match [$sm_falsepos_cmd] no longer suppresses the append"
  assert_eq "settings:cave-hook-falsepos-$sm_falsepos_i-untouched" "$sm_falsepos_cmd" \
    "$(printf '%s' "$sm_falsepos" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].command')" "substring-only match [$sm_falsepos_cmd] left byte-untouched"
  assert_eq "settings:cave-hook-falsepos-$sm_falsepos_i-appended" "$SM_HOOK_CANON" \
    "$(printf '%s' "$sm_falsepos" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].command')" "canonical exec-form entry appended beside [$sm_falsepos_cmd]"
  assert_eq "settings:cave-hook-falsepos-$sm_falsepos_i-args" "[]" \
    "$(printf '%s' "$sm_falsepos" | jq -c '.settings.hooks.SubagentStart[1].hooks[0].args')" "appended entry beside [$sm_falsepos_cmd] carries args:[]"
done

# (e) SIBLING PRESERVATION: a SubagentStart element carrying a `matcher` key and a SECOND unrelated
# hook alongside the legacy caveman entry. ONLY the caveman entry's `.command`/`.args` are assigned;
# the matcher, the unrelated hook, and the intra-array order all survive. Non-vacuous: pre-#352 the
# caveman command was never rewritten, so the exec-form command and args assertions fail.
sm_pre_siblings='{"hooks":{"SubagentStart":[{"matcher":"*","hooks":[{"type":"command","command":".claude/hooks/other.sh"},{"type":"command","command":".claude/hooks/caveman-ultra-subagent.sh"}]}]}}'
sm_siblings="$(hivemind_settings_merge "$sm_pre_siblings" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-siblings-class" "added" \
  "$(printf '%s' "$sm_siblings" | jq -r '.keys["hooks.SubagentStart"]')" "legacy entry beside siblings → corrected in place → added"
assert_eq "settings:cave-hook-siblings-count" "1" \
  "$(printf '%s' "$sm_siblings" | jq -r '.settings.hooks.SubagentStart | length')" "no SubagentStart element appended"
assert_eq "settings:cave-hook-siblings-matcher" "*" \
  "$(printf '%s' "$sm_siblings" | jq -r '.settings.hooks.SubagentStart[0].matcher')" "matcher key on the wrapping element preserved"
assert_eq "settings:cave-hook-siblings-hooks-count" "2" \
  "$(printf '%s' "$sm_siblings" | jq -r '.settings.hooks.SubagentStart[0].hooks | length')" "intra-element hooks array length unchanged"
assert_eq "settings:cave-hook-siblings-unrelated" ".claude/hooks/other.sh" \
  "$(printf '%s' "$sm_siblings" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].command')" "unrelated sibling hook untouched and still at index 0"
assert_eq "settings:cave-hook-siblings-unrelated-no-args" "null" \
  "$(printf '%s' "$sm_siblings" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].args')" "unrelated sibling hook gains no args key"
assert_eq "settings:cave-hook-siblings-migrated" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_siblings" | jq -r '.settings.hooks.SubagentStart[0].hooks[1].command')" "only the caveman command rewritten, order preserved"
assert_eq "settings:cave-hook-siblings-migrated-args" "[]" \
  "$(printf '%s' "$sm_siblings" | jq -c '.settings.hooks.SubagentStart[0].hooks[1].args')" "only the caveman entry gains args:[]"

# (f) TWO LEGACY ENTRIES: both are rewritten to canonical exec form and nothing is appended.
# DELIBERATE ACCEPTED BEHAVIOR, pinned here: pre-existing duplicates are NOT deduped, because this
# merge never REMOVES an entry the user authored (PRESERVE-EXISTING beats dedupe). The only
# consequence is the hook firing twice, which is harmless for a context-injection hook.
# Non-vacuous: pre-#352 neither entry was rewritten, so both exec-form assertions fail.
sm_pre_dup_legacy='{"hooks":{"SubagentStart":[{"hooks":[{"type":"command","command":".claude/hooks/caveman-ultra-subagent.sh"}]},{"hooks":[{"type":"command","command":".claude/hooks/caveman-ultra-subagent.sh"}]}]}}'
sm_dup_legacy="$(hivemind_settings_merge "$sm_pre_dup_legacy" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-dup-legacy-class" "added" \
  "$(printf '%s' "$sm_dup_legacy" | jq -r '.keys["hooks.SubagentStart"]')" "two legacy entries → corrected in place → added"
assert_eq "settings:cave-hook-dup-legacy-count" "2" \
  "$(printf '%s' "$sm_dup_legacy" | jq -r '.settings.hooks.SubagentStart | length')" "no append, and no dedupe (accepted: merge never removes a user entry)"
assert_eq "settings:cave-hook-dup-legacy-both-migrated" "2" \
  "$(printf '%s' "$sm_dup_legacy" | jq -r --arg c "$SM_HOOK_CANON" '[.settings.hooks.SubagentStart[].hooks[] | select(.type == "command" and .args == [] and .command == $c)] | length')" "BOTH legacy entries rewritten to the canonical exec form"
assert_eq "settings:cave-hook-dup-legacy-no-bare-left" "0" \
  "$(printf '%s' "$sm_dup_legacy" | jq -r --arg l "$SM_HOOK_LEGACY" '[.settings.hooks.SubagentStart[].hooks[] | select(.command == $l)] | length')" "no bare legacy command survives the migration"

# (g) RISK-001 — MIXED pre-state carrying BOTH an exec-form canonical entry AND a legacy bare
# entry. The canonical entry alone must NOT short-circuit the report into `already present` while
# the legacy entry silently stays on the shell branch: the token is derived from the MUTATION, and
# the migrate pass DID mutate, so the answer is `added`. The legacy entry is migrated, and the
# already-present canonical entry suppresses any append — so no duplicate is created.
# Non-vacuous: an implementation whose report came from an independent "is a canonical entry
# present?" predicate answers `already present` here — the exact regression this case exists to
# catch — and the previous substring-identity implementation did precisely that.
sm_pre_mixed='{"hooks":{"SubagentStart":[{"hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/caveman-ultra-subagent.sh","args":[]}]},{"hooks":[{"type":"command","command":".claude/hooks/caveman-ultra-subagent.sh"}]}]}}'
sm_mixed="$(hivemind_settings_merge "$sm_pre_mixed" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-mixed-class" "added" \
  "$(printf '%s' "$sm_mixed" | jq -r '.keys["hooks.SubagentStart"]')" "canonical PLUS legacy → the legacy migration IS a mutation → added (never already present)"
assert_eq "settings:cave-hook-mixed-count" "2" \
  "$(printf '%s' "$sm_mixed" | jq -r '.settings.hooks.SubagentStart | length')" "the present canonical entry suppresses the append — no duplicate"
assert_eq "settings:cave-hook-mixed-both-canonical" "2" \
  "$(printf '%s' "$sm_mixed" | jq -r --arg c "$SM_HOOK_CANON" '[.settings.hooks.SubagentStart[].hooks[] | select(.type == "command" and .args == [] and .command == $c)] | length')" "the legacy entry IS migrated — both entries are now exec form"
assert_eq "settings:cave-hook-mixed-no-bare-left" "0" \
  "$(printf '%s' "$sm_mixed" | jq -r --arg l "$SM_HOOK_LEGACY" '[.settings.hooks.SubagentStart[].hooks[] | select(.command == $l)] | length')" "no bare legacy command survives beside the canonical entry"
sm_mixed_settings="$(printf '%s' "$sm_mixed" | jq -c '.settings')"
sm_mixed_twice="$(hivemind_settings_merge "$sm_mixed_settings" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-mixed-idem-class" "already present" \
  "$(printf '%s' "$sm_mixed_twice" | jq -r '.keys["hooks.SubagentStart"]')" "re-merge of the repaired mixed state → already present"
assert_eq "settings:cave-hook-mixed-idem-count" "2" \
  "$(printf '%s' "$sm_mixed_twice" | jq -r '.settings.hooks.SubagentStart | length')" "re-merge of the repaired mixed state adds nothing"

# (h) ELEMENT-POSITION TOTALITY (issue #355) — this is an EXHAUSTION, not a list of handled shapes.
# READ THIS BEFORE ADDING A ROW: the sweep below is not a growable collection of "shapes we've seen
# in the wild". jq's type domain is CLOSED — every JSON value is exactly one of null / boolean /
# number / string / array / object, and there is no seventh type — so enumerating every one of those
# types at a given element position EXHAUSTS that position. There is no untested value left to add,
# and a future review comment naming one more malformed element (`"hooks":{"SubagentStart":[3.14]}`,
# `[""]`, `[false]`, …) is ALREADY covered by the type it inhabits. Do not append a row for it.
#   THE TWO POSITIONS ARE ALSO EXHAUSTIVE, at the CURRENT nesting depth. The caveman SubagentStart
# build reads untyped elements at exactly two positions: `SubagentStart[]` (the wrapping element) and
# `SubagentStart[].hooks[]` (the hook entry). Types × positions = the whole element-access surface,
# which is what makes the contract "every element access is total" a CHECKED claim here rather than
# an assertion of faith.
#   WHAT WOULD ACTUALLY INVALIDATE THIS: not a new VALUE — a new POSITION. If the merge ever grows a
# THIRD nesting level of untyped element access, this sweep stops being exhaustive, because the
# position axis gained a point. The correct response then is a new sweep DIMENSION (that position ×
# the same closed type domain), NOT one more row bolted onto this one. Same for a second hook event
# name read the same way.
#   The eight values below are the six jq types, with array and object each sampled EMPTY and
# NON-EMPTY, because empty containers are the values most likely to slip through a truthiness- or
# length-based guard while a non-empty one is caught (or vice versa).
#   NON-VACUITY, MEASURED (not assumed) — the pre-STEP-001 library was extracted and every pre-state
# below run through it. 10 of the 16 sweep rows abort the jq program outright pre-fix (rc=5, EMPTY
# output, so `.status` reads as the empty string and every assertion here fails): boolean, number,
# string, empty array and non-empty array, at BOTH positions. The remaining 6 rows — null, {} and
# {"a":1} at both positions — were ALREADY total before the fix, because jq permits field access on
# null and on any object, and their pre/post outputs are byte-identical. Those 6 are deliberately
# KEPT: they are the closure rows that prove the totality change did not regress the type-domain
# points that already worked, and dropping them would break the exhaustion argument above, which is
# the whole value of this block. Both named reproducers and the mixed case below are in the
# aborting-pre-fix set.

# (h1) The two reproducers from issue #355, pinned BY NAME so the issue's exact shapes stay locked
# independently of the sweep's own sampling of the string type.
sm_pre_355_outer='{"hooks":{"SubagentStart":["x"]}}'
sm_355_outer="$(hivemind_settings_merge "$sm_pre_355_outer" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-355-repro-outer-status" "ok" \
  "$(printf '%s' "$sm_355_outer" | jq -r '.status')" "#355 reproducer 1 (bare string in SubagentStart[]) merges instead of aborting jq"
assert_eq "settings:cave-hook-355-repro-outer-class" "added" \
  "$(printf '%s' "$sm_355_outer" | jq -r '.keys["hooks.SubagentStart"]')" "#355 reproducer 1 → added (the non-conforming element is never counted present)"
assert_eq "settings:cave-hook-355-repro-outer-preserved" '"x"' \
  "$(printf '%s' "$sm_355_outer" | jq -cS '.settings.hooks.SubagentStart[0]')" "#355 reproducer 1 leaves \"x\" byte-identical at its original index"
assert_eq "settings:cave-hook-355-repro-outer-appended" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_355_outer" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].command')" "#355 reproducer 1 appends the canonical exec-form entry beside \"x\""
assert_eq "settings:cave-hook-355-repro-outer-args" "[]" \
  "$(printf '%s' "$sm_355_outer" | jq -c '.settings.hooks.SubagentStart[1].hooks[0].args')" "#355 reproducer 1 appended entry carries args:[] (exec form)"

sm_pre_355_inner='{"hooks":{"SubagentStart":[{"hooks":["x"]}]}}'
sm_355_inner="$(hivemind_settings_merge "$sm_pre_355_inner" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-355-repro-inner-status" "ok" \
  "$(printf '%s' "$sm_355_inner" | jq -r '.status')" "#355 reproducer 2 (bare string in SubagentStart[].hooks[]) merges instead of aborting jq"
assert_eq "settings:cave-hook-355-repro-inner-class" "added" \
  "$(printf '%s' "$sm_355_inner" | jq -r '.keys["hooks.SubagentStart"]')" "#355 reproducer 2 → added"
assert_eq "settings:cave-hook-355-repro-inner-preserved" '"x"' \
  "$(printf '%s' "$sm_355_inner" | jq -cS '.settings.hooks.SubagentStart[0].hooks[0]')" "#355 reproducer 2 leaves the inner \"x\" byte-identical inside its OWN .hooks array"
assert_eq "settings:cave-hook-355-repro-inner-appended" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_355_inner" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].command')" "#355 reproducer 2 appends the canonical entry as a NEW SubagentStart element"
assert_eq "settings:cave-hook-355-repro-inner-args" "[]" \
  "$(printf '%s' "$sm_355_inner" | jq -c '.settings.hooks.SubagentStart[1].hooks[0].args')" "#355 reproducer 2 appended entry carries args:[] (exec form)"

# (h2) THE SWEEP: closed jq type domain × both element positions. Per row: the merge completes
# (rc 0, status ok), classifies `added`, leaves the non-conforming element byte-identical at its
# original index, appends the canonical exec-form entry with args:[], and a RE-MERGE of that output
# settles to `already present` with no second append (totality must not cost idempotency).
# The pre-state is built with jq --argjson and the expected preserved bytes are re-emitted by jq
# from the SAME value text, so the comparison is on canonical serialization of one source value.
for sm_elem_pos in outer inner; do
  sm_elem_i=0
  for sm_elem_val in 'null' 'true' '1' '"s"' '[]' '["x"]' '{}' '{"a":1}'; do
    sm_elem_i=$((sm_elem_i + 1))
    if [ "$sm_elem_pos" = "outer" ]; then
      sm_elem_pre="$(jq -nc --argjson v "$sm_elem_val" '{hooks:{SubagentStart:[$v]}}')"
      sm_elem_path='.settings.hooks.SubagentStart[0]'
    else
      sm_elem_pre="$(jq -nc --argjson v "$sm_elem_val" '{hooks:{SubagentStart:[{hooks:[$v]}]}}')"
      sm_elem_path='.settings.hooks.SubagentStart[0].hooks[0]'
    fi
    # Case names are indexed (not derived from the value text) because two distinct sweep values
    # would otherwise slug to the same name; the value itself rides in every assertion message.
    sm_elem_case="settings:cave-hook-elem-$sm_elem_pos-$sm_elem_i"
    sm_elem_res="$(hivemind_settings_merge "$sm_elem_pre" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
    sm_elem_rc=$?
    assert_eq "$sm_elem_case-rc" "0" "$sm_elem_rc" \
      "[$sm_elem_pos element $sm_elem_val] merge exits 0 (pre-#355 the untyped access aborted jq at rc=5)"
    assert_eq "$sm_elem_case-status" "ok" \
      "$(printf '%s' "$sm_elem_res" | jq -r '.status')" "[$sm_elem_pos element $sm_elem_val] status ok"
    assert_eq "$sm_elem_case-class" "added" \
      "$(printf '%s' "$sm_elem_res" | jq -r '.keys["hooks.SubagentStart"]')" "[$sm_elem_pos element $sm_elem_val] never counted present → added"
    assert_eq "$sm_elem_case-preserved" "$(jq -ncS --argjson v "$sm_elem_val" '$v')" \
      "$(printf '%s' "$sm_elem_res" | jq -cS "$sm_elem_path")" "[$sm_elem_pos element $sm_elem_val] preserved byte-identical at its original index"
    assert_eq "$sm_elem_case-appended" "$SM_HOOK_CANON" \
      "$(printf '%s' "$sm_elem_res" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].command')" "[$sm_elem_pos element $sm_elem_val] canonical exec-form entry appended"
    assert_eq "$sm_elem_case-appended-args" "[]" \
      "$(printf '%s' "$sm_elem_res" | jq -c '.settings.hooks.SubagentStart[1].hooks[0].args')" "[$sm_elem_pos element $sm_elem_val] appended entry carries args:[]"
    sm_elem_twice="$(hivemind_settings_merge "$(printf '%s' "$sm_elem_res" | jq -c '.settings')" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
    assert_eq "$sm_elem_case-idem-class" "already present" \
      "$(printf '%s' "$sm_elem_twice" | jq -r '.keys["hooks.SubagentStart"]')" "[$sm_elem_pos element $sm_elem_val] re-merge → already present"
    assert_eq "$sm_elem_case-idem-count" "2" \
      "$(printf '%s' "$sm_elem_twice" | jq -r '.settings.hooks.SubagentStart | length')" "[$sm_elem_pos element $sm_elem_val] re-merge appends nothing further"
  done
done

# (h3) MIXED, at BOTH levels at once: a scalar sits beside a MIGRATABLE legacy entry at the outer
# position ("junk") and at the inner position (7 and "z"). Totality must not become inertness — the
# scalars are skipped, but the legacy entry beside them is still migrated IN PLACE to exec form, the
# `matcher`/`timeout` siblings survive, intra-array ORDER survives, and the successful migration
# suppresses the append (length stays 2 / inner length stays 3). Non-vacuous: this whole pre-state
# aborts the pre-STEP-001 library at rc=5.
sm_pre_elem_mixed='{"hooks":{"SubagentStart":["junk",{"matcher":"m","timeout":30,"hooks":[7,{"type":"command","command":".claude/hooks/caveman-ultra-subagent.sh"},"z"]}]}}'
sm_elem_mixed="$(hivemind_settings_merge "$sm_pre_elem_mixed" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-hook-elem-mixed-status" "ok" \
  "$(printf '%s' "$sm_elem_mixed" | jq -r '.status')" "scalars at BOTH element levels beside a legacy entry → merge completes"
assert_eq "settings:cave-hook-elem-mixed-class" "added" \
  "$(printf '%s' "$sm_elem_mixed" | jq -r '.keys["hooks.SubagentStart"]')" "the in-place migration IS a mutation → added"
assert_eq "settings:cave-hook-elem-mixed-count" "2" \
  "$(printf '%s' "$sm_elem_mixed" | jq -r '.settings.hooks.SubagentStart | length')" "migration fired → append suppressed → no third element"
assert_eq "settings:cave-hook-elem-mixed-outer-scalar" '"junk"' \
  "$(printf '%s' "$sm_elem_mixed" | jq -cS '.settings.hooks.SubagentStart[0]')" "outer scalar sibling preserved byte-identical at index 0"
assert_eq "settings:cave-hook-elem-mixed-matcher" "m" \
  "$(printf '%s' "$sm_elem_mixed" | jq -r '.settings.hooks.SubagentStart[1].matcher')" "matcher on the migrated element preserved"
assert_eq "settings:cave-hook-elem-mixed-timeout" "30" \
  "$(printf '%s' "$sm_elem_mixed" | jq -r '.settings.hooks.SubagentStart[1].timeout')" "unrelated sibling key (timeout) preserved"
assert_eq "settings:cave-hook-elem-mixed-hooks-count" "3" \
  "$(printf '%s' "$sm_elem_mixed" | jq -r '.settings.hooks.SubagentStart[1].hooks | length')" "inner hooks array length unchanged (nothing dropped, nothing inserted)"
assert_eq "settings:cave-hook-elem-mixed-inner-scalar-0" "7" \
  "$(printf '%s' "$sm_elem_mixed" | jq -cS '.settings.hooks.SubagentStart[1].hooks[0]')" "inner scalar 7 preserved byte-identical, still at index 0"
assert_eq "settings:cave-hook-elem-mixed-migrated" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_elem_mixed" | jq -r '.settings.hooks.SubagentStart[1].hooks[1].command')" "migration still fires PAST a scalar sibling, in place at index 1"
assert_eq "settings:cave-hook-elem-mixed-migrated-args" "[]" \
  "$(printf '%s' "$sm_elem_mixed" | jq -c '.settings.hooks.SubagentStart[1].hooks[1].args')" "migrated entry gains args:[] (exec form)"
assert_eq "settings:cave-hook-elem-mixed-inner-scalar-2" '"z"' \
  "$(printf '%s' "$sm_elem_mixed" | jq -cS '.settings.hooks.SubagentStart[1].hooks[2]')" "inner scalar \"z\" preserved byte-identical AFTER the migrated entry (order survives)"
assert_eq "settings:cave-hook-elem-mixed-no-bare-left" "0" \
  "$(printf '%s' "$sm_elem_mixed" | jq -r --arg l "$SM_HOOK_LEGACY" '[.settings.hooks.SubagentStart[] | select(type == "object") | .hooks[]? | select(type == "object" and .command == $l)] | length')" "no bare legacy command survives beside the scalars"

# 12c-ter. caveman pluginConfigs NESTED-LEAF merge: the contract value is
# pluginConfigs["caveman@caveman"].options.defaultLevel == "ultra", NOT the mere presence of the
# parent "caveman@caveman" key. A parent config object present WITHOUT (or with a non-"ultra")
# defaultLevel is NOT configured for ultra mode — the leaf must be set/corrected while preserving
# every sibling key in the config object and in .options.
# (a) parent present, options present, defaultLevel MISSING → set "ultra", preserve sibling option.
sm_pcfg_no_level='{"pluginConfigs":{"caveman@caveman":{"options":{"someOther":1}}}}'
sm_pcfg_set="$(hivemind_settings_merge "$sm_pcfg_no_level" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-pcfg-leaf-missing-class" "added" \
  "$(printf '%s' "$sm_pcfg_set" | jq -r '.keys["pluginConfigs.caveman@caveman"]')" "parent present, defaultLevel missing → corrected (added)"
assert_eq "settings:cave-pcfg-leaf-missing-set" "ultra" \
  "$(printf '%s' "$sm_pcfg_set" | jq -r '.settings.pluginConfigs["caveman@caveman"].options.defaultLevel')" "missing defaultLevel set to ultra"
assert_eq "settings:cave-pcfg-leaf-missing-sibling" "1" \
  "$(printf '%s' "$sm_pcfg_set" | jq -r '.settings.pluginConfigs["caveman@caveman"].options.someOther')" "sibling option key preserved when leaf set"
# (b) parent present, defaultLevel = "lite" (WRONG value) → corrected to "ultra", sibling preserved.
sm_pcfg_lite='{"pluginConfigs":{"caveman@caveman":{"options":{"defaultLevel":"lite","keepMe":true}}}}'
sm_pcfg_corrected="$(hivemind_settings_merge "$sm_pcfg_lite" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-pcfg-leaf-wrong-class" "added" \
  "$(printf '%s' "$sm_pcfg_corrected" | jq -r '.keys["pluginConfigs.caveman@caveman"]')" "defaultLevel != ultra → corrected (added)"
assert_eq "settings:cave-pcfg-leaf-wrong-set" "ultra" \
  "$(printf '%s' "$sm_pcfg_corrected" | jq -r '.settings.pluginConfigs["caveman@caveman"].options.defaultLevel')" "wrong defaultLevel corrected to ultra"
assert_eq "settings:cave-pcfg-leaf-wrong-sibling" "true" \
  "$(printf '%s' "$sm_pcfg_corrected" | jq -r '.settings.pluginConfigs["caveman@caveman"].options.keepMe')" "sibling option key preserved when leaf corrected"
# (c) parent present, defaultLevel ALREADY "ultra" + sibling config key → no-op, already present,
# BYTE-STABLE, sibling config key (outside .options) preserved.
sm_pcfg_ultra='{"pluginConfigs":{"caveman@caveman":{"options":{"defaultLevel":"ultra"},"extra":true}}}'
sm_pcfg_noop="$(hivemind_settings_merge "$sm_pcfg_ultra" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-pcfg-leaf-ultra-class" "already present" \
  "$(printf '%s' "$sm_pcfg_noop" | jq -r '.keys["pluginConfigs.caveman@caveman"]')" "defaultLevel already ultra → already present"
assert_eq "settings:cave-pcfg-leaf-ultra-extra" "true" \
  "$(printf '%s' "$sm_pcfg_noop" | jq -r '.settings.pluginConfigs["caveman@caveman"].extra')" "sibling config key (outside .options) preserved"
assert_eq "settings:cave-pcfg-leaf-ultra-bytestable" \
  "$(printf '%s' '{"caveman@caveman":{"options":{"defaultLevel":"ultra"},"extra":true}}' | jq -cS .)" \
  "$(printf '%s' "$sm_pcfg_noop" | jq -cS '.settings.pluginConfigs')" "already-ultra pluginConfigs is byte-stable (no-op)"
# (d) parent key ABSENT → full add of {options:{defaultLevel:"ultra"}} (regression of original behavior).
sm_pcfg_absent="$(hivemind_settings_merge '{"pluginConfigs":{"other@plugin":{}}}' 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-pcfg-leaf-absent-class" "added" \
  "$(printf '%s' "$sm_pcfg_absent" | jq -r '.keys["pluginConfigs.caveman@caveman"]')" "parent absent → added"
assert_eq "settings:cave-pcfg-leaf-absent-set" "ultra" \
  "$(printf '%s' "$sm_pcfg_absent" | jq -r '.settings.pluginConfigs["caveman@caveman"].options.defaultLevel')" "parent absent → full add with ultra"
assert_eq "settings:cave-pcfg-leaf-absent-sibling" "0" \
  "$(printf '%s' "$sm_pcfg_absent" | jq -r '.settings.pluginConfigs["other@plugin"] | length')" "unrelated sibling pluginConfig preserved"
# (e) parent config WRONG-TYPED (a string) → canon_obj → {} → ultra set, no crash (RR4 shape-norm).
sm_pcfg_wrongcfg="$(hivemind_settings_merge '{"pluginConfigs":{"caveman@caveman":"oops"}}' 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-pcfg-leaf-wrongcfg-status" "ok" \
  "$(printf '%s' "$sm_pcfg_wrongcfg" | jq -r '.status')" "wrong-typed caveman config (string) → canonical {} → status ok (no jq abort)"
assert_eq "settings:cave-pcfg-leaf-wrongcfg-class" "added" \
  "$(printf '%s' "$sm_pcfg_wrongcfg" | jq -r '.keys["pluginConfigs.caveman@caveman"]')" "wrong-typed caveman config → added"
assert_eq "settings:cave-pcfg-leaf-wrongcfg-set" "ultra" \
  "$(printf '%s' "$sm_pcfg_wrongcfg" | jq -r '.settings.pluginConfigs["caveman@caveman"].options.defaultLevel')" "wrong-typed config → canonical {} then ultra set"
# (f) parent present, .options WRONG-TYPED (an array) → canon_obj → {} → ultra set, no crash.
sm_pcfg_wrongopt="$(hivemind_settings_merge '{"pluginConfigs":{"caveman@caveman":{"options":["x"]}}}' 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:cave-pcfg-leaf-wrongopt-status" "ok" \
  "$(printf '%s' "$sm_pcfg_wrongopt" | jq -r '.status')" "wrong-typed .options (array) → canonical {} → status ok (no jq abort)"
assert_eq "settings:cave-pcfg-leaf-wrongopt-set" "ultra" \
  "$(printf '%s' "$sm_pcfg_wrongopt" | jq -r '.settings.pluginConfigs["caveman@caveman"].options.defaultLevel')" "wrong-typed .options → canonical {} then ultra set"

# 12d. IDEMPOTENT re-merge of an already-seeded object = no-op, BYTE-STABLE settings.
sm_once="$(hivemind_settings_merge '' 'hivemind:overlord' 'yes' 'yes' 'yes' 'yes')"
sm_once_settings="$(printf '%s' "$sm_once" | jq -cS '.settings')"
sm_twice="$(hivemind_settings_merge "$(printf '%s' "$sm_once" | jq -c '.settings')" 'hivemind:overlord' 'yes' 'yes' 'yes' 'yes')"
sm_twice_settings="$(printf '%s' "$sm_twice" | jq -cS '.settings')"
assert_eq "settings:idempotent-byte-stable" "$sm_once_settings" "$sm_twice_settings" \
  "re-merge of seeded object is byte-stable (no-op)"
assert_eq "settings:idempotent-all-present" "already present" \
  "$(printf '%s' "$sm_twice" | jq -r '[.keys | to_entries[] | .value] | unique | .[0]')" "re-merge → every key already present"
assert_eq "settings:idempotent-allow-present" "already present" \
  "$(printf '%s' "$sm_twice" | jq -r '[.permissions_allow[].result] | unique | .[0]')" "re-merge → every template rule already present"
assert_eq "settings:idempotent-status" "ok" \
  "$(printf '%s' "$sm_twice" | jq -r '.status')" "re-merge status ok"

# 12e. agent CONFLICT detection: a DIFFERENT existing agent → status conflict, value preserved.
sm_conflict="$(hivemind_settings_merge '{"agent":"other:agent"}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:conflict-status" "conflict" \
  "$(printf '%s' "$sm_conflict" | jq -r '.status')" "different existing agent → status conflict"
assert_eq "settings:conflict-agent-class" "conflict" \
  "$(printf '%s' "$sm_conflict" | jq -r '.keys.agent')" "agent classified conflict"
assert_eq "settings:conflict-existing" "other:agent" \
  "$(printf '%s' "$sm_conflict" | jq -r '.agent_conflict.existing')" "conflict reports existing value"
assert_eq "settings:conflict-required" "hivemind:overlord" \
  "$(printf '%s' "$sm_conflict" | jq -r '.agent_conflict.required')" "conflict reports required value"
# CRITICAL: the existing agent is NOT overwritten on conflict (byte-preserved for user approval).
assert_eq "settings:conflict-not-overwritten" "other:agent" \
  "$(printf '%s' "$sm_conflict" | jq -r '.settings.agent')" "conflicting agent left unchanged (never silently overwritten)"
# An agent already EQUAL to the target is NOT a conflict (already present, no conflict block).
sm_same_agent="$(hivemind_settings_merge '{"agent":"hivemind:overlord"}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:same-agent-status" "ok" \
  "$(printf '%s' "$sm_same_agent" | jq -r '.status')" "agent already equal → ok, not conflict"
assert_eq "settings:same-agent-class" "already present" \
  "$(printf '%s' "$sm_same_agent" | jq -r '.keys.agent')" "agent already equal → already present"
assert_eq "settings:same-agent-no-conflict" "null" \
  "$(printf '%s' "$sm_same_agent" | jq -r '.agent_conflict // "null"')" "agent already equal → no conflict block"

# 12e-empty. ROOT-CLUSTER EDGE (RR3-STEP-005): an existing `agent` that is an EMPTY string ("") or
# WHITESPACE-ONLY ("  ") normalizes to ABSENT — it is NOT a real conflicting value. Classified
# `added` (NOT conflict), `.settings.agent` written to the target, status `ok`, NO conflict block.
# Non-vacuous: if the value-state normalization reverted (any present string treated as a real
# value), "" / "  " would land in the conflict branch → status conflict + class conflict, and every
# assertion below would flip.
sm_empty_agent="$(hivemind_settings_merge '{"agent":""}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:empty-agent-status" "ok" \
  "$(printf '%s' "$sm_empty_agent" | jq -r '.status')" "empty-string agent → status ok (not conflict)"
assert_eq "settings:empty-agent-class-added" "added" \
  "$(printf '%s' "$sm_empty_agent" | jq -r '.keys.agent')" "empty-string agent normalizes to ABSENT → added"
assert_eq "settings:empty-agent-value-written" "hivemind:overlord" \
  "$(printf '%s' "$sm_empty_agent" | jq -r '.settings.agent')" "empty-string agent → target written"
assert_eq "settings:empty-agent-no-conflict" "null" \
  "$(printf '%s' "$sm_empty_agent" | jq -r '.agent_conflict // "null"')" "empty-string agent → no conflict block"
sm_ws_agent="$(hivemind_settings_merge '{"agent":"  "}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:ws-agent-class-added" "added" \
  "$(printf '%s' "$sm_ws_agent" | jq -r '.keys.agent')" "whitespace-only agent normalizes to ABSENT → added"
assert_eq "settings:ws-agent-value-written" "hivemind:overlord" \
  "$(printf '%s' "$sm_ws_agent" | jq -r '.settings.agent')" "whitespace-only agent → target written"
assert_eq "settings:ws-agent-status" "ok" \
  "$(printf '%s' "$sm_ws_agent" | jq -r '.status')" "whitespace-only agent → status ok (not conflict)"

# 12e-approve. APPROVAL OVERWRITE (7th arg "yes"): a DIFFERENT existing agent WITH explicit
# approval → status ok, agent OVERWRITTEN to the target, classified `overwritten`, NO conflict
# block. This locks the restored base-prose contract: overwrite is permitted ONLY WITH approval.
# Non-vacuous: if RR-001 dropped the approval gate, the merge would still return conflict (no
# overwrite) and these four assertions would all fail.
sm_approved="$(hivemind_settings_merge '{"agent":"other:agent"}' 'hivemind:overlord' 'no' 'no' 'no' 'no' 'yes')"
assert_eq "settings:approve-status" "ok" \
  "$(printf '%s' "$sm_approved" | jq -r '.status')" "different existing agent + approval → status ok"
assert_eq "settings:approve-agent-class" "overwritten" \
  "$(printf '%s' "$sm_approved" | jq -r '.keys.agent')" "approved conflict → agent classified overwritten"
assert_eq "settings:approve-agent-value" "hivemind:overlord" \
  "$(printf '%s' "$sm_approved" | jq -r '.settings.agent')" "approved conflict → agent overwritten to target"
assert_eq "settings:approve-no-conflict" "null" \
  "$(printf '%s' "$sm_approved" | jq -r '.agent_conflict // "null"')" "approved conflict → no conflict block"

# 12e-noapprove. NO-APPROVAL BYTE-PRESERVE GUARD (never-silently-overwrite): the SAME conflict
# with approval "no" → status conflict, existing agent byte-unchanged, conflict block populated.
# This is the regression guard that an absent/explicit-"no" approval NEVER overwrites. Non-vacuous:
# if the never-overwrite invariant were inverted, .settings.agent would become the target here.
sm_noapprove="$(hivemind_settings_merge '{"agent":"other:agent"}' 'hivemind:overlord' 'no' 'no' 'no' 'no' 'no')"
assert_eq "settings:noapprove-status" "conflict" \
  "$(printf '%s' "$sm_noapprove" | jq -r '.status')" "different existing agent + approval no → status conflict"
assert_eq "settings:noapprove-agent-preserved" "other:agent" \
  "$(printf '%s' "$sm_noapprove" | jq -r '.settings.agent')" "approval no → existing agent byte-unchanged"
assert_eq "settings:noapprove-conflict-existing" "other:agent" \
  "$(printf '%s' "$sm_noapprove" | jq -r '.agent_conflict.existing')" "approval no → conflict block populated"

# 12e-malformed-approve. MALFORMED-BEFORE-APPROVAL (fail closed): a NON-EMPTY unparseable settings
# blob WITH approval "yes" still returns status malformed — approval authorizes an agent overwrite,
# it NEVER clobbers a torn file. Non-vacuous: if the malformed check were evaluated after (or
# skipped under) the approval gate, this would not report malformed.
sm_malformed_approve="$(hivemind_settings_merge 'torn { not json' 'hivemind:overlord' 'no' 'no' 'no' 'yes' 'yes')"
assert_eq "settings:malformed-approve-status" "malformed" \
  "$(printf '%s' "$sm_malformed_approve" | jq -r '.status')" "malformed input + approval → still malformed (fail closed)"
assert_eq "settings:malformed-approve-settings-null" "null" \
  "$(printf '%s' "$sm_malformed_approve" | jq -r '.settings // "null"')" "malformed + approval → settings not echoed (torn file not clobbered)"

# 12f. permissions.allow UNION preserves existing ORDER, appends only ABSENT rules.
# Existing: a custom rule + one template rule (Bash(jq *)). Union must keep both in place, then
# append the 24 absent template rules; Bash(jq *) reported already present, Bash(echo *) added.
sm_union="$(hivemind_settings_merge '{"permissions":{"allow":["Bash(custom *)","Bash(jq *)"]}}' 'hivemind:overlord' 'no' 'no' 'no' 'yes')"
assert_eq "settings:union-first" "Bash(custom *)" \
  "$(printf '%s' "$sm_union" | jq -r '.settings.permissions.allow[0]')" "union preserves existing first entry order"
assert_eq "settings:union-second" "Bash(jq *)" \
  "$(printf '%s' "$sm_union" | jq -r '.settings.permissions.allow[1]')" "union preserves existing second entry order"
assert_eq "settings:union-total" "26" \
  "$(printf '%s' "$sm_union" | jq -r '.settings.permissions.allow | length')" "union = 2 existing + 24 absent template rules"
assert_eq "settings:union-existing-present" "already present" \
  "$(printf '%s' "$sm_union" | jq -r '.permissions_allow[] | select(.rule=="Bash(jq *)") | .result')" "template rule already in array → already present"
assert_eq "settings:union-absent-added" "added" \
  "$(printf '%s' "$sm_union" | jq -r '.permissions_allow[] | select(.rule=="Bash(echo *)") | .result')" "absent template rule → added"
# A user's custom (non-template) rule is NEVER removed or duplicated by the union.
assert_eq "settings:union-custom-kept" "1" \
  "$(printf '%s' "$sm_union" | jq -r '[.settings.permissions.allow[] | select(. == "Bash(custom *)")] | length')" "user custom rule kept exactly once"

# 12g. permissions present WITHOUT allow → allow added, sibling permissions keys preserved.
sm_sibling="$(hivemind_settings_merge '{"permissions":{"deny":["Bash(rm *)"]}}' 'hivemind:overlord' 'no' 'no' 'no' 'yes')"
assert_eq "settings:sibling-deny-kept" "Bash(rm *)" \
  "$(printf '%s' "$sm_sibling" | jq -r '.settings.permissions.deny[0]')" "sibling permissions.deny preserved"
assert_eq "settings:sibling-allow-created" "25" \
  "$(printf '%s' "$sm_sibling" | jq -r '.settings.permissions.allow | length')" "permissions without allow → allow created with 25 rules"

# 12h. seed_allowlist=no → permissions.allow left UNTOUCHED, permissions_allow report empty.
sm_no_allow="$(hivemind_settings_merge '{"permissions":{"allow":["Bash(x *)"]}}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:noallow-untouched-len" "1" \
  "$(printf '%s' "$sm_no_allow" | jq -r '.settings.permissions.allow | length')" "seed_allowlist=no → existing allow untouched"
assert_eq "settings:noallow-untouched-val" "Bash(x *)" \
  "$(printf '%s' "$sm_no_allow" | jq -r '.settings.permissions.allow[0]')" "seed_allowlist=no → existing allow value unchanged"
assert_eq "settings:noallow-report-empty" "0" \
  "$(printf '%s' "$sm_no_allow" | jq -r '.permissions_allow | length')" "seed_allowlist=no → empty permissions_allow report"

# 12i. PRESERVE-EXISTING: an unrelated pre-existing key the user had is kept untouched.
sm_preserve="$(hivemind_settings_merge '{"theme":"dark","model":"opus"}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:preserve-theme" "dark" \
  "$(printf '%s' "$sm_preserve" | jq -r '.settings.theme')" "unrelated existing key (theme) preserved"
assert_eq "settings:preserve-model" "opus" \
  "$(printf '%s' "$sm_preserve" | jq -r '.settings.model')" "unrelated existing key (model) preserved"
# A pre-existing companion entry is preserved + reported already present even when its toggle is no
# (SKILL.md: detection only ever adds; an entry already present is preserved and `already present`).
sm_pre_companion="$(hivemind_settings_merge '{"enabledPlugins":{"caveman@caveman":true}}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:preserve-companion-kept" "true" \
  "$(printf '%s' "$sm_pre_companion" | jq -r '.settings.enabledPlugins["caveman@caveman"]')" "pre-existing companion entry preserved even when toggle is no"

# 12i-bis. VALUE-EQUALITY classification matrix (SWEEP-STEP-004, Pattern-2). The enabledPlugins
# classification is VALUE-NOT-PRESENCE: a key reports `already present` IFF its existing value
# already EQUALS the canonical target (== true). A key present-but-false / null / wrong-typed is
# NOT already present — it must be classified `added` AND the build must CORRECT it to true. This
# parametrized matrix locks one case PER enabledPlugins key so a revert of `enabled_true` back to
# a presence-only `has()` predicate (which would report `already present` for a present-but-false
# key, leaving the wrong value in place) trips a per-key assertion.
#
# Driver: $1 case-slug, $2 settings-json, $3 caveman, $4 claude_mem, $5 codex, $6 plugin-key,
#         $7 expected-class, $8 expected-built-value ("true" | "null" | "skip"). Runs the merge
#         and asserts BOTH the classification token AND the built .enabledPlugins[key] value, so
#         every case is NON-VACUOUS on the value-equality fix (presence-only revert flips class
#         from `added`→`already present` AND, for false/null inputs, the build still corrects the
#         value to true — the class assertion is what fails on revert).
sm_value_case() {
  local slug="$1" json="$2" cav="$3" mem="$4" cdx="$5" key="$6" want_class="$7" want_val="$8"
  local res
  res="$(hivemind_settings_merge "$json" 'hivemind:overlord' "$cav" "$mem" "$cdx" 'no')"
  assert_eq "settings:value-$slug-class" "$want_class" \
    "$(printf '%s' "$res" | jq -r --arg k "$key" '.keys["enabledPlugins." + $k]')" \
    "$slug: enabledPlugins.$key classified $want_class"
  if [ "$want_val" != "skip" ]; then
    # NOTE: jq `//` treats `false` as empty, so a literal `// "null"` fallback would mis-render a
    # preserved `false` as "null". Branch on has() to render absent vs. the exact stored value.
    assert_eq "settings:value-$slug-built" "$want_val" \
      "$(printf '%s' "$res" | jq -r --arg k "$key" '.settings.enabledPlugins | if has($k) then .[$k] else "null" end')" \
      "$slug: built enabledPlugins.$key == $want_val"
  fi
}

# (i) hivemind key present == false → added (NOT already present), corrected to true.
sm_value_case "hive-false" '{"enabledPlugins":{"hivemind@brenpike":false}}' \
  'no' 'no' 'no' 'hivemind@brenpike' 'added' 'true'
# (ii) hivemind key present == null → added, corrected to true.
sm_value_case "hive-null" '{"enabledPlugins":{"hivemind@brenpike":null}}' \
  'no' 'no' 'no' 'hivemind@brenpike' 'added' 'true'
# (iii) resolved-yes caveman present == false → added, corrected to true.
sm_value_case "cave-false" '{"enabledPlugins":{"caveman@caveman":false}}' \
  'yes' 'no' 'no' 'caveman@caveman' 'added' 'true'
# (iv) resolved-yes claude-mem present == false → added, corrected to true.
sm_value_case "mem-false" '{"enabledPlugins":{"claude-mem@thedotmack":false}}' \
  'no' 'yes' 'no' 'claude-mem@thedotmack' 'added' 'true'
# (v) resolved-yes codex present == false → added, corrected to true.
sm_value_case "codex-false" '{"enabledPlugins":{"codex@openai-codex":false}}' \
  'no' 'no' 'yes' 'codex@openai-codex' 'added' 'true'
# REGRESSION GUARD (a): each key present == true → already present (behavior preserved).
sm_value_case "hive-true" '{"enabledPlugins":{"hivemind@brenpike":true}}' \
  'no' 'no' 'no' 'hivemind@brenpike' 'already present' 'true'
sm_value_case "cave-true" '{"enabledPlugins":{"caveman@caveman":true}}' \
  'yes' 'no' 'no' 'caveman@caveman' 'already present' 'true'
sm_value_case "mem-true" '{"enabledPlugins":{"claude-mem@thedotmack":true}}' \
  'no' 'yes' 'no' 'claude-mem@thedotmack' 'already present' 'true'
sm_value_case "codex-true" '{"enabledPlugins":{"codex@openai-codex":true}}' \
  'no' 'no' 'yes' 'codex@openai-codex' 'already present' 'true'
# REGRESSION GUARD (b): absent key → added (presence-absent still classifies added).
sm_value_case "hive-absent" '{"enabledPlugins":{}}' \
  'no' 'no' 'no' 'hivemind@brenpike' 'added' 'true'
# REGRESSION GUARD (c): companion key present == false but toggle NOT resolved-yes → `resolved no`
# (the `resolved no` short-circuit runs BEFORE the value test, so no spurious `added`, and the
# key is left untouched — the build never writes a companion whose toggle is no).
sm_value_case "cave-false-noresolve" '{"enabledPlugins":{"caveman@caveman":false}}' \
  'no' 'no' 'no' 'caveman@caveman' 'resolved no' 'false'

# 12j. MALFORMED non-empty input → status malformed, settings null, NO merge (fail-closed).
# An EMPTY string is the absent-file case (treated as {}), NOT malformed.
sm_malformed="$(hivemind_settings_merge 'not json{' 'hivemind:overlord' 'no' 'no' 'no' 'yes')"
assert_eq "settings:malformed-status" "malformed" \
  "$(printf '%s' "$sm_malformed" | jq -r '.status')" "unparseable non-empty input → status malformed"
assert_eq "settings:malformed-settings-null" "null" \
  "$(printf '%s' "$sm_malformed" | jq -r '.settings // "null"')" "malformed input → settings not echoed (null)"
# Valid JSON that is NOT an object (a bare array) is likewise malformed (a settings file is an object).
sm_array="$(hivemind_settings_merge '[1,2,3]' 'hivemind:overlord' 'no' 'no' 'no' 'yes')"
assert_eq "settings:nonobject-malformed" "malformed" \
  "$(printf '%s' "$sm_array" | jq -r '.status')" "non-object JSON (array) → status malformed"
# Empty string is NOT malformed — it is the absent-file {} case.
sm_empty_ok="$(hivemind_settings_merge '' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:empty-not-malformed" "ok" \
  "$(printf '%s' "$sm_empty_ok" | jq -r '.status')" "empty input is absent-file case, not malformed"

# 12k. INERT BINDING: a settings value crafted to look like a jq-program fragment or a
# command-substitution payload is treated as plain data (passed via --argjson), never executed.
rm -f "$PWN_MARKER"
sm_inert="$(hivemind_settings_merge "{\"agent\":\"\$(touch $PWN_MARKER)\"}" 'hivemind:overlord' 'no' 'no' 'no' 'no')"
# The crafted agent string is a DIFFERENT value than the target → conflict, value preserved verbatim.
assert_eq "settings:inert-status" "conflict" \
  "$(printf '%s' "$sm_inert" | jq -r '.status')" "crafted agent value is inert data → conflict, not executed"
if [ -e "$PWN_MARKER" ]; then
  failed "settings:inert-no-side-effect" "a settings value triggered command substitution: $PWN_MARKER created"
else
  pass "settings:inert-no-side-effect" "no settings value triggered command substitution"
fi

# 12l. WRONG-TYPED CONTAINER NORMALIZATION (RR4-STEP-005): every container-typed key whose existing
# value is the WRONG SHAPE (a non-object at an object-typed key, a non-array at permissions.allow) is
# the canonical absent/needs-seed state — it collapses to {} / [] via canon_obj/canon_arr (from
# json-normalize.sh) BEFORE any predicate runs, so the required seed is add-if-absent over the empty
# and the merge returns status `ok` with the required keys seeded. NON-VACUOUS for EVERY case: pre-RR4
# the wrong-typed container made jq's has()/index()/iteration abort (jq rc=5 → empty merge output →
# empty `.status`), so each `status == ok` + seeded-key assertion fails on a revert of the
# normalization. No REAL value is clobbered: a wrong-typed container holds no contract-type entries to
# preserve.

# enabledPlugins as a STRING → canon_obj → {} → hivemind required entry seeded; status ok.
sm_ep_string="$(hivemind_settings_merge '{"enabledPlugins":"oops"}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:wrongtype-ep-string-status" "ok" \
  "$(printf '%s' "$sm_ep_string" | jq -r '.status')" "enabledPlugins as string → canonical {} → status ok (no jq abort)"
assert_eq "settings:wrongtype-ep-string-class" "added" \
  "$(printf '%s' "$sm_ep_string" | jq -r '.keys["enabledPlugins.hivemind@brenpike"]')" "wrong-typed enabledPlugins → hivemind seeded as added"
assert_eq "settings:wrongtype-ep-string-value" "true" \
  "$(printf '%s' "$sm_ep_string" | jq -r '.settings.enabledPlugins["hivemind@brenpike"]')" "required hivemind enabledPlugin written over canonical empty"

# enabledPlugins as an ARRAY → canon_obj → {} → required entry seeded; status ok.
sm_ep_array="$(hivemind_settings_merge '{"enabledPlugins":["x"]}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:wrongtype-ep-array-status" "ok" \
  "$(printf '%s' "$sm_ep_array" | jq -r '.status')" "enabledPlugins as array → canonical {} → status ok (no jq abort)"
assert_eq "settings:wrongtype-ep-array-value" "true" \
  "$(printf '%s' "$sm_ep_array" | jq -r '.settings.enabledPlugins["hivemind@brenpike"]')" "wrong-typed (array) enabledPlugins → hivemind seeded true"

# pluginConfigs WRONG-TYPED (array) with caveman=yes → canon_obj → {} → caveman pluginConfig seeded.
sm_pcfg_array="$(hivemind_settings_merge '{"pluginConfigs":["x"]}' 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:wrongtype-pcfg-status" "ok" \
  "$(printf '%s' "$sm_pcfg_array" | jq -r '.status')" "pluginConfigs as array → canonical {} → status ok (no jq abort)"
assert_eq "settings:wrongtype-pcfg-class" "added" \
  "$(printf '%s' "$sm_pcfg_array" | jq -r '.keys["pluginConfigs.caveman@caveman"]')" "wrong-typed pluginConfigs → caveman pluginConfig added"
assert_eq "settings:wrongtype-pcfg-value" "ultra" \
  "$(printf '%s' "$sm_pcfg_array" | jq -r '.settings.pluginConfigs["caveman@caveman"].options.defaultLevel')" "caveman defaultLevel seeded over canonical empty"

# hooks WRONG-TYPED (string) with caveman=yes → canon_obj → {} → SubagentStart hook seeded.
sm_hooks_string="$(hivemind_settings_merge '{"hooks":"oops"}' 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
assert_eq "settings:wrongtype-hooks-status" "ok" \
  "$(printf '%s' "$sm_hooks_string" | jq -r '.status')" "hooks as string → canonical {} → status ok (no jq abort)"
assert_eq "settings:wrongtype-hooks-class" "added" \
  "$(printf '%s' "$sm_hooks_string" | jq -r '.keys["hooks.SubagentStart"]')" "wrong-typed hooks → SubagentStart hook added"
assert_eq "settings:wrongtype-hooks-cmd" "$SM_HOOK_CANON" \
  "$(printf '%s' "$sm_hooks_string" | jq -r '.settings.hooks.SubagentStart[0].hooks[0].command')" "anchored caveman hook command seeded over canonical empty"
assert_eq "settings:wrongtype-hooks-args" "[]" \
  "$(printf '%s' "$sm_hooks_string" | jq -c '.settings.hooks.SubagentStart[0].hooks[0].args')" "seeded entry over canonical empty is exec form (args:[])"

# permissions WRONG-TYPED (array) with seed_allowlist=yes → canon_obj → {} → permissions.allow seeded.
sm_perm_array="$(hivemind_settings_merge '{"permissions":["x"]}' 'hivemind:overlord' 'no' 'no' 'no' 'yes')"
assert_eq "settings:wrongtype-perm-status" "ok" \
  "$(printf '%s' "$sm_perm_array" | jq -r '.status')" "permissions as array → canonical {} → status ok (no jq abort)"
assert_eq "settings:wrongtype-perm-allow-count" "25" \
  "$(printf '%s' "$sm_perm_array" | jq -r '.settings.permissions.allow | length')" "wrong-typed permissions → allow seeded with 25 template rules"

# permissions.allow WRONG-TYPED (string) with seed_allowlist=yes → canon_arr → [] → template appended.
sm_allow_string="$(hivemind_settings_merge '{"permissions":{"allow":"oops"}}' 'hivemind:overlord' 'no' 'no' 'no' 'yes')"
assert_eq "settings:wrongtype-allow-status" "ok" \
  "$(printf '%s' "$sm_allow_string" | jq -r '.status')" "permissions.allow as string → canonical [] → status ok (no jq abort)"
assert_eq "settings:wrongtype-allow-count" "25" \
  "$(printf '%s' "$sm_allow_string" | jq -r '.settings.permissions.allow | length')" "wrong-typed permissions.allow → [] then 25 template rules appended"
assert_eq "settings:wrongtype-allow-report-count" "25" \
  "$(printf '%s' "$sm_allow_string" | jq -r '.permissions_allow | length')" "every template rule reported over the canonical empty allow"

# 12m. MULTI-DOCUMENT STREAM (JSON-stream sweep, STEP-005): a settings input that is a STREAM of TWO
# concatenated top-level objects (`{"a":1}{"b":2}`) is NOT a single settings object — it takes the
# fail-closed malformed path via hivemind_jq_is_single_object_stdin (json-normalize.sh), exactly like
# the unparseable-blob and non-object cases (12j). NON-VACUOUS: the OLD bare `jq -e 'type=="object"'`
# precheck STREAMED both documents and exited 0 on the LAST one, so the merge fell through to the
# `--argjson settings` build which then CRASHED on the two-document operand. If the single-doc gate
# reverts to `type=="object"` (which accepts streams), this case loses status `malformed`, `.settings`
# is no longer null, and the function's stdout is no longer a clean single parseable JSON object.
sm_stream="$(hivemind_settings_merge '{"a":1}{"b":2}' 'hivemind:overlord' 'no' 'no' 'no' 'yes')"
assert_eq "settings:stream-status" "malformed" \
  "$(printf '%s' "$sm_stream" | jq -r '.status')" "two-object stream → status malformed (single-document gate)"
assert_eq "settings:stream-settings-null" "null" \
  "$(printf '%s' "$sm_stream" | jq -r '.settings // "null"')" "stream input → settings not echoed (torn-stream not merged)"
# The crash is GONE: the function's stdout is the malformed-REPORT object — EXACTLY ONE parseable JSON
# object (no jq usage text / no multi-document crash output). `jq -s 'length'` over the stdout proves
# it is a single document; a pre-gate crash would leave non-JSON error bytes here and fail the slurp.
assert_eq "settings:stream-stdout-single-object" "1" \
  "$(printf '%s' "$sm_stream" | jq -s 'length' 2>/dev/null)" "stream input → stdout is exactly one parseable JSON object (crash gone)"
# A genuine SINGLE object on the SAME merge still merges normally (regression: gate does not over-reject).
sm_single_obj="$(hivemind_settings_merge '{"theme":"dark"}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:stream-single-regression-status" "ok" \
  "$(printf '%s' "$sm_single_obj" | jq -r '.status')" "single object still merges → ok (gate does not over-reject)"
assert_eq "settings:stream-single-regression-theme" "dark" \
  "$(printf '%s' "$sm_single_obj" | jq -r '.settings.theme')" "single object preserved key (normal merge)"
# A single ARRAY `[1]` is subsumed by the SAME gate (length==1 but NOT type==object) → malformed.
sm_single_array="$(hivemind_settings_merge '[1]' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
assert_eq "settings:stream-single-array-malformed" "malformed" \
  "$(printf '%s' "$sm_single_array" | jq -r '.status')" "single array [1] → malformed (single-document gate subsumes non-object)"

# ── Section 13: claude-mem-path.sh — dynamic binary resolution + never-clobber single-key write ─
echo ''
echo '=== claude-mem-path.sh: CLAUDE_CODE_PATH dynamic resolution + conditional single-key write ==='
#
# AUTHORITATIVE regression tests for the seed-hive claude-mem `CLAUDE_CODE_PATH` provisioning core
# (SKILL.md step 11). The provision function reads claude-mem's OWN config, decides under
# never-clobber + malformed-safe semantics, and writes ONLY that one key. Every case is HERMETIC:
# it runs against a tmp HOME + tmp candidate bin dirs inside $WORKDIR and NEVER reads or writes the
# developer's real `~/.claude-mem` or `~/.local/bin`. Each case builds its own fixture HOME so the
# resolution + write are isolated.

# HERMETIC PATH: step 11e candidate (1) is `command -v claude`, which honors the ambient PATH —
# a developer with a real `claude` on PATH would otherwise shadow every fixture's home-dir
# fallback and make resolution non-hermetic. Build a CLEAN PATH that keeps the system bins
# (so `mktemp`/`mv`/`jq` still work) but DROPS any directory that actually contains an executable
# `claude`, so `command -v claude` resolves to nothing and the per-fixture `home_dir` fallbacks
# (candidates 2/3) govern. Every Section 13 case runs under this CLEAN PATH.
CM_CLEAN_PATH=""
IFS=':' read -r -a cm_path_dirs <<< "$PATH"
for cm_dir in "${cm_path_dirs[@]}"; do
  [ -n "$cm_dir" ] || continue
  [ -x "$cm_dir/claude" ] && continue   # drop any dir holding a real claude binary
  CM_CLEAN_PATH="${CM_CLEAN_PATH:+$CM_CLEAN_PATH:}$cm_dir"
done

# cm_setup_home <subdir> — create a hermetic tmp HOME under $WORKDIR and a fake executable
# `claude` at ~/.local/bin/claude inside it (so binary resolution succeeds without touching the
# real filesystem). Echoes the HOME path; the claude-mem settings file is NOT created here (each
# case stages its own target so it can exercise the missing/malformed/present permutations).
cm_setup_home() {
  local home_dir="$WORKDIR/$1"
  mkdir -p "$home_dir/.local/bin" "$home_dir/.claude-mem"
  printf '#!/usr/bin/env bash\necho claude-stub\n' > "$home_dir/.local/bin/claude"
  chmod +x "$home_dir/.local/bin/claude"
  printf '%s\n' "$home_dir"
}

# 13a. Missing target file → skipped (claude-mem not installed); nothing created.
cm_home_missing="$(cm_setup_home cm-missing)"
rm -f "$cm_home_missing/.claude-mem/settings.json"
cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$cm_home_missing/.claude-mem/settings.json" "$cm_home_missing")"
assert_eq "claude-mem:missing-status" "skipped (claude-mem not installed)" "$cm_status" \
  "absent settings file → not installed"
if [ -e "$cm_home_missing/.claude-mem/settings.json" ]; then
  failed "claude-mem:missing-no-create" "provision created the settings file when it should not have"
else
  pass "claude-mem:missing-no-create" "missing settings file is NOT created"
fi

# 13b. Empty/missing CLAUDE_CODE_PATH (key absent) → set, value = resolved binary path.
cm_home_set="$(cm_setup_home cm-set)"
cm_file_set="$cm_home_set/.claude-mem/settings.json"
printf '{\n  "logLevel": "info",\n  "CLAUDE_CODE_PATH": ""\n}\n' > "$cm_file_set"
cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$cm_file_set" "$cm_home_set")"
assert_eq "claude-mem:empty-status" "set" "$cm_status" "empty CLAUDE_CODE_PATH → set"
assert_eq "claude-mem:empty-value" "$cm_home_set/.local/bin/claude" \
  "$(jq -r '.CLAUDE_CODE_PATH' "$cm_file_set")" "CLAUDE_CODE_PATH set to resolved binary path"
# Every OTHER key is byte-preserved after the write.
assert_eq "claude-mem:empty-other-key" "info" \
  "$(jq -r '.logLevel' "$cm_file_set")" "sibling key (logLevel) preserved after a write"

# Key entirely ABSENT (not just empty) → also set.
cm_home_absent="$(cm_setup_home cm-absent)"
cm_file_absent="$cm_home_absent/.claude-mem/settings.json"
printf '{\n  "logLevel": "debug"\n}\n' > "$cm_file_absent"
cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$cm_file_absent" "$cm_home_absent")"
assert_eq "claude-mem:absent-key-status" "set" "$cm_status" "absent CLAUDE_CODE_PATH key → set"
assert_eq "claude-mem:absent-key-value" "$cm_home_absent/.local/bin/claude" \
  "$(jq -r '.CLAUDE_CODE_PATH' "$cm_file_absent")" "absent key gets the resolved binary path"
assert_eq "claude-mem:absent-key-other" "debug" \
  "$(jq -r '.logLevel' "$cm_file_absent")" "sibling key preserved when key was absent"

# 13c. Non-empty CLAUDE_CODE_PATH → already set; NOTHING written, value preserved.
cm_home_present="$(cm_setup_home cm-present)"
cm_file_present="$cm_home_present/.claude-mem/settings.json"
printf '{\n  "CLAUDE_CODE_PATH": "/user/provided/claude",\n  "logLevel": "warn"\n}\n' > "$cm_file_present"
cm_before="$(cat "$cm_file_present")"
cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$cm_file_present" "$cm_home_present")"
assert_eq "claude-mem:present-status" "already set" "$cm_status" "non-empty CLAUDE_CODE_PATH → already set"
assert_eq "claude-mem:present-value" "/user/provided/claude" \
  "$(jq -r '.CLAUDE_CODE_PATH' "$cm_file_present")" "user-provided value never overwritten"
cm_after="$(cat "$cm_file_present")"
assert_eq "claude-mem:present-bytes" "$cm_before" "$cm_after" "already-set file is byte-unchanged (no write)"

# 13c-nonstring. ROOT-CLUSTER EDGE (RR3-STEP-005): a PRESENT NON-STRING `CLAUDE_CODE_PATH`
# (boolean/number/object/array) is PRESENT-MALFORMED — a user-provided value that must NEVER be
# clobbered → `already set`, file BYTE-UNCHANGED. Asserted for each non-string JSON shape.
# Non-vacuous: if the predicate normalized non-strings to ABSENT (e.g. an `== ""`-only test that
# mis-handled type), each of these would resolve+write → status `set` and the file bytes would
# change, flipping both assertions per shape.
# Each shape carries an explicit slug (the `{}`/`[]` JSON literals strip to nothing under a
# charset filter, so name them rather than risk duplicate/empty case ids).
for cm_ns_pair in 'false:bool' '42:number' '{}:object' '[]:array'; do
  cm_ns="${cm_ns_pair%%:*}"
  cm_ns_slug="${cm_ns_pair##*:}"
  cm_home_ns="$(cm_setup_home "cm-nonstring-$cm_ns_slug")"
  cm_file_ns="$cm_home_ns/.claude-mem/settings.json"
  printf '{\n  "CLAUDE_CODE_PATH": %s,\n  "logLevel": "info"\n}\n' "$cm_ns" > "$cm_file_ns"
  cm_before="$(cat "$cm_file_ns")"
  cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$cm_file_ns" "$cm_home_ns")"
  assert_eq "claude-mem:nonstring-$cm_ns_slug-status" "already set" "$cm_status" \
    "present non-string CLAUDE_CODE_PATH ($cm_ns) → already set (never clobbered)"
  assert_eq "claude-mem:nonstring-$cm_ns_slug-bytes" "$cm_before" "$(cat "$cm_file_ns")" \
    "present non-string ($cm_ns) → file byte-unchanged"
done

# 13c-null. PRESENT-NULL EDGE (RR3-STEP-005): an explicitly-present JSON `null` is a user-provided
# value → PRESENT-MALFORMED → `already set`, file byte-unchanged (NOT treated as ABSENT). Non-vacuous:
# if present-null were normalized to ABSENT, the binary would resolve and the key be overwritten →
# status `set`, bytes changed.
cm_home_null="$(cm_setup_home cm-null)"
cm_file_null="$cm_home_null/.claude-mem/settings.json"
printf '{\n  "CLAUDE_CODE_PATH": null,\n  "logLevel": "info"\n}\n' > "$cm_file_null"
cm_before="$(cat "$cm_file_null")"
cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$cm_file_null" "$cm_home_null")"
assert_eq "claude-mem:present-null-status" "already set" "$cm_status" "present null CLAUDE_CODE_PATH → already set (skip, not absent)"
assert_eq "claude-mem:present-null-bytes" "$cm_before" "$(cat "$cm_file_null")" "present null → file byte-unchanged"

# 13d. Malformed JSON target → skipped (malformed json); no write, file byte-unchanged.
cm_home_bad="$(cm_setup_home cm-bad)"
cm_file_bad="$cm_home_bad/.claude-mem/settings.json"
printf 'not json{ CLAUDE_CODE_PATH' > "$cm_file_bad"
cm_before="$(cat "$cm_file_bad")"
cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$cm_file_bad" "$cm_home_bad")"
assert_eq "claude-mem:malformed-status" "skipped (malformed json)" "$cm_status" "unparseable target → malformed skip"
cm_after="$(cat "$cm_file_bad")"
assert_eq "claude-mem:malformed-bytes" "$cm_before" "$cm_after" "malformed file is byte-unchanged (never clobbered)"

# 13e. No claude binary resolvable → skipped (claude binary not found); empty key untouched.
# Hermetic: a tmp HOME with NO ~/.local/bin/claude and NO ~/.claude/local/claude, run under the
# CLEAN PATH (no real `claude`), so all three resolution candidates fail without reading the
# developer's filesystem.
cm_home_nobin="$WORKDIR/cm-nobin"
mkdir -p "$cm_home_nobin/.claude-mem"
cm_file_nobin="$cm_home_nobin/.claude-mem/settings.json"
printf '{\n  "CLAUDE_CODE_PATH": "",\n  "logLevel": "info"\n}\n' > "$cm_file_nobin"
cm_before="$(cat "$cm_file_nobin")"
cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$cm_file_nobin" "$cm_home_nobin")"
assert_eq "claude-mem:nobin-status" "skipped (claude binary not found)" "$cm_status" \
  "no resolvable binary → not found skip"
cm_after="$(cat "$cm_file_nobin")"
assert_eq "claude-mem:nobin-bytes" "$cm_before" "$cm_after" "no-binary case writes NOTHING (file unchanged)"

# 13f. Resolution order: when ~/.local/bin/claude is absent, the ~/.claude/local/claude fallback
# is used (proves the EXACT fallback list + order from SKILL.md step 11e).
cm_home_fallback="$WORKDIR/cm-fallback"
mkdir -p "$cm_home_fallback/.claude/local" "$cm_home_fallback/.claude-mem"
printf '#!/usr/bin/env bash\necho stub\n' > "$cm_home_fallback/.claude/local/claude"
chmod +x "$cm_home_fallback/.claude/local/claude"
cm_file_fallback="$cm_home_fallback/.claude-mem/settings.json"
printf '{\n  "CLAUDE_CODE_PATH": ""\n}\n' > "$cm_file_fallback"
cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$cm_file_fallback" "$cm_home_fallback")"
assert_eq "claude-mem:fallback-status" "set" "$cm_status" "second fallback resolves → set"
assert_eq "claude-mem:fallback-value" "$cm_home_fallback/.claude/local/claude" \
  "$(jq -r '.CLAUDE_CODE_PATH' "$cm_file_fallback")" "~/.claude/local/claude fallback used when ~/.local/bin absent"

# 13g. MULTI-DOCUMENT STREAM (JSON-stream sweep, STEP-005): a `~/.claude-mem/settings.json` that is a
# STREAM of TWO concatenated top-level objects (`{"a":1}{"b":2}`) is NOT a single settings object. The
# provision function gates on hivemind_jq_is_single_object_file (json-normalize.sh, file form) BEFORE
# any resolve/write, so a stream → `skipped (malformed json)` with the file BYTE-UNCHANGED — the same
# never-clobber contract as the unparseable-blob case (13d). A resolvable claude binary IS present
# (cm_setup_home stages ~/.local/bin/claude), so the skip is attributable SOLELY to the stream gate,
# not to a missing binary. NON-VACUOUS: the OLD bare `jq -e type=="object"` precheck STREAMED both
# documents and exited 0 on the LAST one → resolve+single-key-write would run and the per-object write
# would clobber/duplicate the file. If the single-doc gate reverts to `type=="object"` (accepts
# streams), status flips to `set` and the byte-compare below fails (the file is rewritten).
cm_home_stream="$(cm_setup_home cm-stream)"
cm_file_stream="$cm_home_stream/.claude-mem/settings.json"
printf '{"a":1}{"b":2}' > "$cm_file_stream"
cm_before="$(cat "$cm_file_stream")"
cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$cm_file_stream" "$cm_home_stream")"
assert_eq "claude-mem:stream-status" "skipped (malformed json)" "$cm_status" \
  "two-object stream target → malformed skip (single-document gate, binary present)"
assert_eq "claude-mem:stream-bytes" "$cm_before" "$(cat "$cm_file_stream")" \
  "stream target is byte-unchanged (never clobbered by a per-object write)"

# 13h. RELATIVE-PATH-COMPONENT REJECT (Class B): with a relative PATH component (`PATH=bin:$PATH`),
# `command -v claude` returns a CWD-relative path (`bin/claude`) that passes -x/-f. Persisted as
# CLAUDE_CODE_PATH it would break worker resolution from another CWD. The candidate-(1) guard now
# ADDITIONALLY requires an ABSOLUTE leading `/`, so the relative hit is REJECTED and resolution
# falls through to the absolute `$home_dir/.local/bin/claude` fallback. The RETURNED path MUST be
# absolute. NON-VACUOUS: pre-fix `command -v claude` returned the relative `bin/claude` verbatim →
# the leading-`/` assertion FAILS pre-fix and PASSES post-fix.
# CWD is restored so the per-case `cd` does not leak into later cases.
cm_home_relpath="$(cm_setup_home cm-relpath)"   # stages an absolute $home/.local/bin/claude fallback
cm_relpath_cwd="$WORKDIR/cm-relpath-cwd"
mkdir -p "$cm_relpath_cwd/bin"
printf '#!/usr/bin/env bash\necho rel-stub\n' > "$cm_relpath_cwd/bin/claude"
chmod +x "$cm_relpath_cwd/bin/claude"
cm_relpath_oldpwd="$PWD"
cd "$cm_relpath_cwd"
cm_relpath_result="$(PATH="bin:$CM_CLEAN_PATH" hivemind_claude_mem_resolve_binary "$cm_home_relpath")"
cd "$cm_relpath_oldpwd"
case "$cm_relpath_result" in
  /*) pass "claude-mem:relpath-absolute" "relative PATH hit rejected; absolute fallback returned ($cm_relpath_result)" ;;
  *)  failed "claude-mem:relpath-absolute" "expected an absolute path; got relative '$cm_relpath_result'" ;;
esac
assert_eq "claude-mem:relpath-value" "$cm_home_relpath/.local/bin/claude" "$cm_relpath_result" \
  "resolution falls through to the absolute home-dir fallback"

# 13h-neg. Negative control: a relative-only `bin/claude` on PATH with NO absolute fallback (a tmp
# HOME containing neither ~/.local/bin/claude nor ~/.claude/local/claude) → resolution returns 1.
cm_home_relonly="$WORKDIR/cm-relonly"
mkdir -p "$cm_home_relonly"   # no .local/bin/claude, no .claude/local/claude
cm_relonly_cwd="$WORKDIR/cm-relonly-cwd"
mkdir -p "$cm_relonly_cwd/bin"
printf '#!/usr/bin/env bash\necho rel-stub\n' > "$cm_relonly_cwd/bin/claude"
chmod +x "$cm_relonly_cwd/bin/claude"
cm_relonly_oldpwd="$PWD"
cd "$cm_relonly_cwd"
if PATH="bin:$CM_CLEAN_PATH" hivemind_claude_mem_resolve_binary "$cm_home_relonly" >/dev/null 2>&1; then
  cd "$cm_relonly_oldpwd"
  failed "claude-mem:relonly-rc" "relative-only PATH with no absolute fallback should return 1"
else
  cd "$cm_relonly_oldpwd"
  pass "claude-mem:relonly-rc" "relative-only PATH + no absolute fallback → return 1 (relative rejected)"
fi

# ── Section 14: file-guard.sh — append-if-absent kernel + comment-aware/section/hook variants ──
echo ''
echo '=== file-guard.sh: append-if-absent kernel + .envrc / ## Validation / hook-scaffold variants ==='
#
# AUTHORITATIVE regression tests for the seed-hive plain-text file-guard family (SKILL.md steps
# 8, 9, 10, and the step-14 `## Validation` guard). Every case is HERMETIC: it builds its own
# fixture file under $WORKDIR and asserts the in-band status word, the idempotency/byte-stability
# invariants, and the EXACT entries/semantics/wording from seed-hive/SKILL.md.

# 14a. .gitignore two-entry kernel idempotency (SKILL.md step 8): each entry independent; re-run
# is a no-op `already present`; the entry is never duplicated.
fg_gitignore="$WORKDIR/fg-gitignore"
rm -f "$fg_gitignore"
fg_s1="$(hivemind_append_if_absent "$fg_gitignore" ".hivemind/")"
fg_s2="$(hivemind_append_if_absent "$fg_gitignore" ".claude/worktrees/")"
assert_eq "file-guard:gitignore-first-added" "added" "$fg_s1" ".hivemind/ appended to fresh file → added"
assert_eq "file-guard:gitignore-second-added" "added" "$fg_s2" ".claude/worktrees/ appended → added"
assert_eq "file-guard:gitignore-both-lines" ".hivemind/
.claude/worktrees/" "$(cat "$fg_gitignore")" "both entries present, each on its own line"
# Re-run both entries → already present, no-op, byte-stable.
fg_before="$(cat "$fg_gitignore")"
fg_r1="$(hivemind_append_if_absent "$fg_gitignore" ".hivemind/")"
fg_r2="$(hivemind_append_if_absent "$fg_gitignore" ".claude/worktrees/")"
assert_eq "file-guard:gitignore-rerun-first" "already present" "$fg_r1" ".hivemind/ re-run → already present"
assert_eq "file-guard:gitignore-rerun-second" "already present" "$fg_r2" ".claude/worktrees/ re-run → already present"
assert_eq "file-guard:gitignore-rerun-bytes" "$fg_before" "$(cat "$fg_gitignore")" "re-run is byte-stable (no duplicate lines)"
# Entry never duplicated: exactly one occurrence of each.
assert_eq "file-guard:gitignore-no-dup-hive" "1" \
  "$(grep -c '^\.hivemind/$' "$fg_gitignore")" ".hivemind/ appears exactly once"

# 14b. Entry independence: a file that already has ONE entry gets only the MISSING one appended.
fg_partial="$WORKDIR/fg-partial-gitignore"
printf '.hivemind/\n' > "$fg_partial"
fg_p1="$(hivemind_append_if_absent "$fg_partial" ".hivemind/")"
fg_p2="$(hivemind_append_if_absent "$fg_partial" ".claude/worktrees/")"
assert_eq "file-guard:partial-present" "already present" "$fg_p1" "pre-existing .hivemind/ → already present"
assert_eq "file-guard:partial-added" "added" "$fg_p2" "absent .claude/worktrees/ → added"
assert_eq "file-guard:partial-result" ".hivemind/
.claude/worktrees/" "$(cat "$fg_partial")" "only the missing entry appended"

# 14c. Trailing-newline guard (SKILL.md step 8b): a file with NO trailing newline gets a blank
# line inserted before the append so the entry lands on its own line, never glued on.
fg_nonl="$WORKDIR/fg-no-trailing-nl"
printf 'existing-line-no-newline' > "$fg_nonl"   # deliberately NO trailing \n
fg_n1="$(hivemind_append_if_absent "$fg_nonl" ".hivemind/")"
assert_eq "file-guard:nonl-added" "added" "$fg_n1" "entry appended to newline-less file → added"
assert_eq "file-guard:nonl-standalone" "existing-line-no-newline
.hivemind/" "$(cat "$fg_nonl")" "entry lands on its own line (blank-line/newline guard fired)"

# 14d. .envrc active-vs-commented discrimination (SKILL.md step 9b/c). A COMMENTED line does NOT
# count as present → the entry is still appended.
fg_env_commented="$WORKDIR/fg-envrc-commented"
printf '# export CAVEMAN_DEFAULT_MODE=ultra\n' > "$fg_env_commented"
fg_ec="$(hivemind_append_env_if_absent "$fg_env_commented" "export CAVEMAN_DEFAULT_MODE=ultra")"
assert_eq "file-guard:env-commented-added" "added" "$fg_ec" "commented line is NOT active → entry appended"
assert_eq "file-guard:env-commented-result" "# export CAVEMAN_DEFAULT_MODE=ultra
export CAVEMAN_DEFAULT_MODE=ultra" "$(cat "$fg_env_commented")" "active entry appended below the comment"
# An ACTIVE matching line → already present, no-op.
fg_env_active="$WORKDIR/fg-envrc-active"
printf 'export CAVEMAN_DEFAULT_MODE=ultra\n' > "$fg_env_active"
fg_ea="$(hivemind_append_env_if_absent "$fg_env_active" "export CAVEMAN_DEFAULT_MODE=ultra")"
assert_eq "file-guard:env-active-present" "already present" "$fg_ea" "active matching line → already present"
# Quote tolerance (SKILL.md step 9b: "with or without quotes around ultra"): a double-quoted and a
# single-quoted active value both count as present → no duplicate append.
fg_env_dq="$WORKDIR/fg-envrc-dq"
printf 'export CAVEMAN_DEFAULT_MODE="ultra"\n' > "$fg_env_dq"
fg_edq="$(hivemind_append_env_if_absent "$fg_env_dq" "export CAVEMAN_DEFAULT_MODE=ultra")"
assert_eq "file-guard:env-dquote-present" "already present" "$fg_edq" "double-quoted value tolerated → already present"
fg_env_sq="$WORKDIR/fg-envrc-sq"
printf "export CAVEMAN_DEFAULT_MODE='ultra'\n" > "$fg_env_sq"
fg_esq="$(hivemind_append_env_if_absent "$fg_env_sq" "export CAVEMAN_DEFAULT_MODE=ultra")"
assert_eq "file-guard:env-squote-present" "already present" "$fg_esq" "single-quoted value tolerated → already present"
# Whitespace-padded active line (trimmed match) → already present.
fg_env_pad="$WORKDIR/fg-envrc-pad"
printf '   export CAVEMAN_DEFAULT_MODE=ultra   \n' > "$fg_env_pad"
fg_epad="$(hivemind_append_env_if_absent "$fg_env_pad" "export CAVEMAN_DEFAULT_MODE=ultra")"
assert_eq "file-guard:env-padded-present" "already present" "$fg_epad" "whitespace-padded active line trimmed-matches → already present"
# .envrc created from absent → entry is the sole line.
fg_env_new="$WORKDIR/fg-envrc-new"
rm -f "$fg_env_new"
fg_en="$(hivemind_append_env_if_absent "$fg_env_new" "export CAVEMAN_DEFAULT_MODE=ultra")"
assert_eq "file-guard:env-new-added" "added" "$fg_en" "absent .envrc → entry added"
assert_eq "file-guard:env-new-content" "export CAVEMAN_DEFAULT_MODE=ultra" "$(cat "$fg_env_new")" "created .envrc holds only the entry"

# 14e. Idempotent re-run of ALL guards is byte-stable (no-op).
fg_env_idem="$WORKDIR/fg-envrc-idem"
printf 'export CAVEMAN_DEFAULT_MODE=ultra\n' > "$fg_env_idem"
fg_env_idem_before="$(cat "$fg_env_idem")"
hivemind_append_env_if_absent "$fg_env_idem" "export CAVEMAN_DEFAULT_MODE=ultra" >/dev/null
assert_eq "file-guard:env-idem-bytes" "$fg_env_idem_before" "$(cat "$fg_env_idem")" "envrc guard re-run is byte-stable"

# 14f. Hook scaffold (SKILL.md step 10a-c): create-if-absent (`created` + executable bit) vs
# `already present` (content untouched).
fg_hook="$WORKDIR/fg-hooks/caveman-ultra-subagent.sh"
rm -rf "$WORKDIR/fg-hooks"
fg_hc="$(hivemind_scaffold_hook_file "$fg_hook")"
assert_eq "file-guard:hook-created" "created" "$fg_hc" "absent hook file → created"
if [ -x "$fg_hook" ]; then
  pass "file-guard:hook-executable" "scaffolded hook file has the executable bit set"
else
  failed "file-guard:hook-executable" "scaffolded hook file is NOT executable"
fi
# Content byte-matches the SINGLE DATA source.
assert_eq "file-guard:hook-content-matches" "$(hivemind_caveman_hook_content)" "$(cat "$fg_hook")" \
  "scaffolded hook content equals the single DATA source"
# Existing hook → already present, content untouched.
fg_hook_marker="$(cat "$fg_hook")"
fg_hc2="$(hivemind_scaffold_hook_file "$fg_hook")"
assert_eq "file-guard:hook-already-present" "already present" "$fg_hc2" "existing hook file → already present"
assert_eq "file-guard:hook-content-untouched" "$fg_hook_marker" "$(cat "$fg_hook")" "existing hook content left untouched"

# 14g. CLAUDE.md `## Validation` section-append (SKILL.md step 14c/d/e): absent → added; present →
# already documented, existing prose untouched.
FG_VALIDATION_BODY="## Validation

\`\`\`bash
go test ./...
\`\`\`"
# Absent CLAUDE.md → section created.
fg_claude_new="$WORKDIR/fg-claude-new.md"
rm -f "$fg_claude_new"
fg_vn="$(hivemind_guard_validation_section "$fg_claude_new" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-new-added" "added" "$fg_vn" "absent CLAUDE.md → ## Validation added"
assert_eq "file-guard:validation-new-content" "$FG_VALIDATION_BODY" "$(cat "$fg_claude_new")" "created CLAUDE.md holds the section body"
# CLAUDE.md WITHOUT a ## Validation section → section appended after existing prose (untouched).
fg_claude_append="$WORKDIR/fg-claude-append.md"
printf '# Project\n\nSome existing prose.\n' > "$fg_claude_append"
fg_va="$(hivemind_guard_validation_section "$fg_claude_append" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-append-added" "added" "$fg_va" "CLAUDE.md lacking ## Validation → added"
assert_eq "file-guard:validation-append-prose-kept" "Some existing prose." \
  "$(grep -F 'Some existing prose.' "$fg_claude_append")" "existing prose preserved on append"
assert_eq "file-guard:validation-append-has-section" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_append")" "## Validation section appended exactly once"
# CLAUDE.md that ALREADY documents ## Validation → already documented, byte-unchanged.
fg_claude_present="$WORKDIR/fg-claude-present.md"
printf '# Project\n\n## Validation\n\n```bash\nmake test\n```\n' > "$fg_claude_present"
fg_present_before="$(cat "$fg_claude_present")"
fg_vp="$(hivemind_guard_validation_section "$fg_claude_present" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-present-documented" "already documented" "$fg_vp" "existing ## Validation → already documented"
assert_eq "file-guard:validation-present-bytes" "$fg_present_before" "$(cat "$fg_claude_present")" "existing ## Validation prose left byte-unchanged"

# 14g-prose. PROSE-PRESERVATION DATA-LOSS LOCK (RR4-STEP-005): a `## Validation` heading carrying
# REAL PROSE but NO fenced command body is PRESENT-NO-COMMAND → `added`, and the existing prose line
# is byte-PRESERVED (APPENDED-UNDER, never REPLACED) while the assembled fenced ```bash block is
# inserted beneath it. Result: EXACTLY ONE `## Validation` heading and the fenced block now present.
# Non-vacuous: the prior RR3 implementation REPLACED the stub range in place, which would DROP this
# prose line (grep -F would return empty) — this case fails on any revert to the replace-in-place
# code, locking the data-loss fix.
fg_claude_prose="$WORKDIR/fg-claude-prose.md"
printf '## Validation\n\nRun the tests manually before pushing.\n' > "$fg_claude_prose"
fg_vpr="$(hivemind_guard_validation_section "$fg_claude_prose" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-prose-added" "added" "$fg_vpr" "prose-only ## Validation → ABSENT body → added"
assert_eq "file-guard:validation-prose-kept" "Run the tests manually before pushing." \
  "$(grep -F 'Run the tests manually before pushing.' "$fg_claude_prose")" "existing prose byte-PRESERVED (append-under, not replace)"
assert_eq "file-guard:validation-prose-one-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_prose")" "exactly ONE ## Validation heading after the append"
assert_eq "file-guard:validation-prose-has-body" "1" \
  "$(grep -c "$(printf '^\140\140\140bash$')" "$fg_claude_prose")" "fenced bash command block now present under the prose"

# 14g-stub. ROOT-CLUSTER EDGE (RR3-STEP-005): a HEADING-ONLY `## Validation` (the heading line
# present but NO fenced command body beneath it) normalizes to ABSENT under the BODY-presence
# predicate → `added`, the heading-only stub is APPENDED-UNDER (prose-preserving — its existing
# blank/comment lines are kept verbatim, never replaced) with the assembled command body, the result
# carries the fenced ```bash block, has EXACTLY ONE `## Validation` heading, and every SIBLING section
# is byte-preserved. Non-vacuous: if the predicate reverted to bare-heading presence, the stub would
# be mis-reported `already documented`, the file would stay byte-unchanged (no fenced block, the
# `go test ./...` body never written) and every assertion below would fail.
fg_claude_stub="$WORKDIR/fg-claude-stub.md"
printf '# Project\n\n## Setup\n\nRun the installer.\n\n## Validation\n\n## License\n\nMIT.\n' > "$fg_claude_stub"
fg_vs="$(hivemind_guard_validation_section "$fg_claude_stub" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-stub-added" "added" "$fg_vs" "heading-only ## Validation stub → ABSENT → added"
# Fence pattern built via printf (octal 140 = backtick) so the literal backticks never enter the
# shell tokenizer inside a command substitution.
fg_fence_re="$(printf '^\140\140\140bash$')"
assert_eq "file-guard:validation-stub-has-body" "1" \
  "$(grep -c "$fg_fence_re" "$fg_claude_stub")" "command body (fenced bash block) written into the stub section"
assert_eq "file-guard:validation-stub-cmd" "go test ./..." \
  "$(grep -F 'go test ./...' "$fg_claude_stub")" "assembled command landed in the section"
assert_eq "file-guard:validation-stub-one-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_stub")" "exactly ONE ## Validation heading (stub appended-under, prose-preserving, not duplicated)"
# Sibling sections are byte-preserved (only the stub's own range was rewritten).
assert_eq "file-guard:validation-stub-sibling-setup" "Run the installer." \
  "$(grep -F 'Run the installer.' "$fg_claude_stub")" "preceding ## Setup sibling byte-preserved"
assert_eq "file-guard:validation-stub-sibling-license" "MIT." \
  "$(grep -F 'MIT.' "$fg_claude_stub")" "following ## License sibling byte-preserved"
assert_eq "file-guard:validation-stub-license-heading" "1" \
  "$(grep -c '^## License$' "$fg_claude_stub")" "following ## License heading byte-preserved"

# 14g-bodyregress. REGRESSION GUARD (RR3-STEP-005): a `## Validation` heading WITH a real fenced
# command body is PRESENT-CANONICAL → still `already documented`, file byte-unchanged. This is the
# inverse-edge guard ensuring the body-presence predicate did not over-correct into always-append.
# Non-vacuous: if the predicate dropped the body check (treating every heading as absent), this
# would return `added` and rewrite the file, breaking both assertions.
fg_claude_body="$WORKDIR/fg-claude-body.md"
printf '# Project\n\n## Validation\n\n```bash\nmake check\n```\n\n## Notes\n\nkeep.\n' > "$fg_claude_body"
fg_body_before="$(cat "$fg_claude_body")"
fg_vb="$(hivemind_guard_validation_section "$fg_claude_body" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-body-documented" "already documented" "$fg_vb" "heading WITH fenced body → already documented"
assert_eq "file-guard:validation-body-bytes" "$fg_body_before" "$(cat "$fg_claude_body")" "heading-with-body file byte-unchanged"

# 14g-nested. NESTED-HEADING BOUND LOCK (PR #297 P2): a `## Validation` section whose fenced command
# body lives under a `### Subsection` (level-3 child) is PRESENT-WITH-COMMAND → `already documented`,
# byte-unchanged, NO duplicate block appended. The section-end scan must bound the `##` section only
# at a LEVEL <= 2 heading — the `### CI` child is PART OF the section, so its fenced block is in range
# and sets has_body. Non-vacuous: under the prior any-`#`-level bound, the `### CI` heading ENDED the
# section before the fence, mis-classifying it PRESENT-NO-COMMAND → a DUPLICATE fenced block appended
# (fence count would jump to 2) and the verdict would be `added`, failing every assertion below.
fg_claude_nested="$WORKDIR/fg-claude-nested.md"
printf '# Project\n\n## Validation\n\n### CI\n\n```bash\nnpm test\n```\n' > "$fg_claude_nested"
fg_nested_before="$(cat "$fg_claude_nested")"
fg_vnest="$(hivemind_guard_validation_section "$fg_claude_nested" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-nested-documented" "already documented" "$fg_vnest" "fenced body under ### child → already documented"
assert_eq "file-guard:validation-nested-bytes" "$fg_nested_before" "$(cat "$fg_claude_nested")" "nested-command file byte-unchanged (no duplicate)"
assert_eq "file-guard:validation-nested-one-fence" "1" \
  "$(grep -c "$(printf '^\140\140\140bash$')" "$fg_claude_nested")" "exactly ONE fenced bash block (no duplicate appended)"
assert_eq "file-guard:validation-nested-subheading" "1" \
  "$(grep -c '^### CI$' "$fg_claude_nested")" "nested ### CI subsection preserved as part of the section"

# 14g-sibling. EXACT-NAME MATCH LOCK (PR #297 P1): a CLAUDE.md that has a SIBLING heading whose text
# merely STARTS WITH `Validation` (`## Validation Details`) but NO exact `## Validation` heading must
# classify ABSENT → the real `## Validation` section is CREATED and the sibling section + its content
# is left BYTE-PRESERVED, so BOTH headings now exist. Non-vacuous: under the prior loose prefix match
# (`'## Validation '*`), `## Validation Details` was mistaken for the `## Validation` heading → the
# command would be recorded UNDER the sibling (or reported `already documented`) and no real
# `## Validation` heading would ever be created — every assertion below would fail.
fg_claude_sibling="$WORKDIR/fg-claude-sibling.md"
printf '# Project\n\n## Validation Details\n\nSee the wiki for the full checklist.\n' > "$fg_claude_sibling"
fg_sib_res="$(hivemind_guard_validation_section "$fg_claude_sibling" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-sibling-added" "added" "$fg_sib_res" "sibling ## Validation Details, no exact ## Validation → ABSENT → added"
assert_eq "file-guard:validation-sibling-real-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_sibling")" "the real ## Validation heading was created exactly once"
assert_eq "file-guard:validation-sibling-preserved-heading" "1" \
  "$(grep -c '^## Validation Details$' "$fg_claude_sibling")" "the ## Validation Details sibling heading preserved"
assert_eq "file-guard:validation-sibling-preserved-prose" "1" \
  "$(grep -c '^See the wiki for the full checklist\.$' "$fg_claude_sibling")" "sibling section prose preserved byte-for-byte"
assert_eq "file-guard:validation-sibling-fence" "1" \
  "$(grep -c "$(printf '^\140\140\140bash$')" "$fg_claude_sibling")" "real ## Validation section carries the fenced command body"

# 14g-trailing. ATX-LEGAL TRAILING MATCH LOCK (PR #297 P1): an exact `## Validation` heading bearing
# trailing whitespace and ATX closing `#`s (`## Validation ##  `) with a fenced command body must
# still be RECOGNIZED as the `## Validation` heading → `already documented`, byte-unchanged. Non-
# vacuous: an over-strict exact match (equality against the literal `## Validation` only) would treat
# the trailing-`#` heading as absent → a DUPLICATE section appended and verdict `added`, failing here.
fg_claude_trailing="$WORKDIR/fg-claude-trailing.md"
printf '# Project\n\n## Validation ##  \n\n```bash\nmake test\n```\n' > "$fg_claude_trailing"
fg_trail_before="$(cat "$fg_claude_trailing")"
fg_trail_res="$(hivemind_guard_validation_section "$fg_claude_trailing" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-trailing-documented" "already documented" "$fg_trail_res" "## Validation ## (ATX closing hashes) with command → already documented"
assert_eq "file-guard:validation-trailing-bytes" "$fg_trail_before" "$(cat "$fg_claude_trailing")" "trailing-hash heading file byte-unchanged"

# 14g-validationx. NO-SUFFIX-MATCH LOCK (PR #297 P1): a heading whose text is `ValidationX` (a single
# trailing char, no space) is NOT the `## Validation` heading → ABSENT → the real `## Validation`
# section is created and `## ValidationX` is preserved. Non-vacuous: a substring/prefix match would
# treat `## ValidationX` as the target → no real `## Validation` ever created.
fg_claude_vx="$WORKDIR/fg-claude-validationx.md"
printf '# Project\n\n## ValidationX\n\nnot the section.\n' > "$fg_claude_vx"
fg_vx_res="$(hivemind_guard_validation_section "$fg_claude_vx" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-vx-added" "added" "$fg_vx_res" "## ValidationX → not the ## Validation heading → ABSENT → added"
assert_eq "file-guard:validation-vx-real-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_vx")" "real ## Validation heading created"
assert_eq "file-guard:validation-vx-preserved" "1" \
  "$(grep -c '^## ValidationX$' "$fg_claude_vx")" "## ValidationX sibling preserved"

# 14g-wsmarker. ATX MARKER-WHITESPACE NORMALIZATION LOCK (PR #297 P2): a valid level-2 heading whose
# `##` marker is followed by EXTRA whitespace (multiple spaces, or a tab) must still be recognized as
# the `## Validation` heading. The prior fix stripped only a single literal `## ` (one space), so
# `##   Validation` / `##\tValidation` left leading whitespace on the heading text → the exact
# compare to `Validation` FAILED → the section was MISSED and a DUPLICATE `## Validation` block was
# appended even when a command was already documented. Each case below is NON-VACUOUS: it FAILS
# against the single-space-strip code (verdict `added` + a duplicate heading) and passes only with
# the strip-ALL-leading-whitespace parse.
#
# (a) `##   Validation` (3 spaces) WITH a fenced command → already documented, byte-unchanged.
fg_claude_msp="$WORKDIR/fg-claude-multispace.md"
printf '# Project\n\n##   Validation\n\n```bash\nnpm test\n```\n' > "$fg_claude_msp"
fg_msp_before="$(cat "$fg_claude_msp")"
fg_msp_res="$(hivemind_guard_validation_section "$fg_claude_msp" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-multispace-documented" "already documented" "$fg_msp_res" "##   Validation (multi-space marker) with command → already documented"
assert_eq "file-guard:validation-multispace-bytes" "$fg_msp_before" "$(cat "$fg_claude_msp")" "multi-space-marker heading file byte-unchanged"
assert_eq "file-guard:validation-multispace-no-dup" "0" \
  "$(grep -c '^## Validation$' "$fg_claude_msp")" "no canonical '## Validation' duplicate appended beside the multi-space heading"

# (b) `##\tValidation` (TAB after the marker) WITH a fenced command → already documented, byte-unchanged.
fg_claude_tab="$WORKDIR/fg-claude-tabmarker.md"
printf '# Project\n\n##\tValidation\n\n```bash\nnpm test\n```\n' > "$fg_claude_tab"
fg_tab_before="$(cat "$fg_claude_tab")"
fg_tab_res="$(hivemind_guard_validation_section "$fg_claude_tab" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-tab-documented" "already documented" "$fg_tab_res" "##<tab>Validation (tab marker) with command → already documented"
assert_eq "file-guard:validation-tab-bytes" "$fg_tab_before" "$(cat "$fg_claude_tab")" "tab-marker heading file byte-unchanged"

# (c) `##   Validation` with PROSE but NO command → recognized as the section (not a duplicate) →
# prose-preserving append, EXACTLY ONE level-2 Validation heading after the append.
fg_claude_msp_prose="$WORKDIR/fg-claude-multispace-prose.md"
printf '##   Validation\n\nRun the tests manually before pushing.\n' > "$fg_claude_msp_prose"
fg_msp_prose_res="$(hivemind_guard_validation_section "$fg_claude_msp_prose" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-multispace-prose-added" "added" "$fg_msp_prose_res" "prose-only ##   Validation → ABSENT body → added (recognized, not duplicated)"
assert_eq "file-guard:validation-multispace-prose-kept" "Run the tests manually before pushing." \
  "$(grep -F 'Run the tests manually before pushing.' "$fg_claude_msp_prose")" "multi-space-marker prose preserved on append"
assert_eq "file-guard:validation-multispace-prose-no-dup" "0" \
  "$(grep -c '^## Validation$' "$fg_claude_msp_prose")" "no canonical '## Validation' duplicate appended beside the multi-space prose heading"
assert_eq "file-guard:validation-multispace-prose-one-heading" "1" \
  "$(grep -cE '^##[[:space:]]+Validation$' "$fg_claude_msp_prose")" "exactly ONE level-2 Validation heading after the prose-preserving append"

# (d) NO-SPACE REGRESSION GUARD: `##Validation` (no whitespace after the marker) is NOT an ATX
# heading → NOT the `## Validation` heading → ABSENT → the real `## Validation` section is created
# and `##Validation` is preserved. Non-vacuous: a marker-strip that did not require whitespace would
# treat `##Validation` as the target → no real `## Validation` ever created.
fg_claude_nospace="$WORKDIR/fg-claude-nospace.md"
printf '# Project\n\n##Validation\n\nnot a heading.\n' > "$fg_claude_nospace"
fg_nospace_res="$(hivemind_guard_validation_section "$fg_claude_nospace" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-nospace-added" "added" "$fg_nospace_res" "##Validation (no space, not ATX) → ABSENT → added"
assert_eq "file-guard:validation-nospace-real-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_nospace")" "real ## Validation heading created beside ##Validation"
assert_eq "file-guard:validation-nospace-preserved" "1" \
  "$(grep -c '^##Validation$' "$fg_claude_nospace")" "##Validation non-heading line preserved"

# 14g-indent. COMMONMARK LEADING-INDENT LOCK (PR #297 ATX-completion): the consolidated
# `_hivemind_atx_heading` parser now applies the CommonMark leading-indent rule to BOTH the
# exact-name match and the level-based section bound. 0-3 leading spaces still make a heading; 4+
# leading spaces are an indented code block, NOT a heading. Each case is NON-VACUOUS against the
# prior column-0-anchored parse, which treated `  ## Validation` as NOT-a-heading (would have
# duplicated) and treated `    ## Validation` as a heading (would have mis-recognized the indented
# code-block line).
#
# (a) `  ## Validation` (2 leading spaces) WITH a fenced command → recognized as the heading →
# already documented, byte-unchanged, NO duplicate `## Validation` appended. Under the prior
# column-0 parse the indented heading was missed → a duplicate canonical block would be appended.
fg_claude_indent2="$WORKDIR/fg-claude-indent2.md"
printf '# Project\n\n  ## Validation\n\n```bash\nnpm test\n```\n' > "$fg_claude_indent2"
fg_indent2_before="$(cat "$fg_claude_indent2")"
fg_indent2_res="$(hivemind_guard_validation_section "$fg_claude_indent2" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-indent2-documented" "already documented" "$fg_indent2_res" "  ## Validation (2-space indent) with command → already documented"
assert_eq "file-guard:validation-indent2-bytes" "$fg_indent2_before" "$(cat "$fg_claude_indent2")" "2-space-indent heading file byte-unchanged"
assert_eq "file-guard:validation-indent2-no-dup" "0" \
  "$(grep -c '^## Validation$' "$fg_claude_indent2")" "no column-0 '## Validation' duplicate appended beside the 2-space-indent heading"

# (b) `    ## Validation` (4 leading spaces) is an indented CODE BLOCK, NOT a heading → ABSENT → the
# real (column-0) `## Validation` section is CREATED and the 4-space-indented line is preserved
# verbatim. Non-vacuous: under the prior column-0-only parse (no indent rule), or a parse that
# allowed 4+ indent, the indented line would be mis-recognized as the heading → no real `## Validation`
# ever created and the assertions below would fail.
fg_claude_indent4="$WORKDIR/fg-claude-indent4.md"
printf '# Project\n\n    ## Validation\n\nnot a heading (indented code block).\n' > "$fg_claude_indent4"
fg_indent4_res="$(hivemind_guard_validation_section "$fg_claude_indent4" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-indent4-added" "added" "$fg_indent4_res" "    ## Validation (4-space indent, code block) → not a heading → ABSENT → added"
assert_eq "file-guard:validation-indent4-real-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_indent4")" "real column-0 ## Validation heading created"
assert_eq "file-guard:validation-indent4-preserved" "1" \
  "$(grep -c '^    ## Validation$' "$fg_claude_indent4")" "4-space-indented non-heading line preserved verbatim"
assert_eq "file-guard:validation-indent4-fence" "1" \
  "$(grep -c "$(printf '^\140\140\140bash$')" "$fg_claude_indent4")" "created section carries the fenced command body"

# 14g-tabsibling. TAB-MARKED SIBLING BOUND LOCK (PR #297 ATX-completion): a `## Validation` section
# (with a fenced command body) is followed by a SIBLING heading whose `##` marker is followed by a
# TAB (`##\tOther`). The section bound (`_hivemind_is_section_heading` → consolidated parser) is now
# tab-aware, so `##\tOther` is correctly LEVEL 2 → it ENDS the `## Validation` section AFTER the
# fenced block, leaving the command in range → already documented, byte-unchanged, no duplicate.
# Non-vacuous: under the SPACE-ONLY `_hivemind_heading_level`, `##\tOther` parsed as level 0 (not a
# heading) → it did NOT bound the section, so the section ran past it; the fence is still in range in
# THIS layout so the verdict would still be `already documented`, but the tab sibling was being
# SWALLOWED into the Validation section's range. To make the swallow OBSERVABLE, place the fenced
# command AFTER the tab sibling: under the space-only parse `##\tOther` does not bound the section,
# the post-sibling fence is (wrongly) counted in-range → already documented; under the tab-aware
# parse `##\tOther` ENDS the section BEFORE that fence → PRESENT-NO-COMMAND → `added`. The verdicts
# DIVERGE, so this case fails on any revert to the space-only level parse.
fg_claude_tabsib="$WORKDIR/fg-claude-tabsibling.md"
printf '# Project\n\n## Validation\n\n##\tOther\n\n```bash\nnpm test\n```\n' > "$fg_claude_tabsib"
fg_tabsib_res="$(hivemind_guard_validation_section "$fg_claude_tabsib" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-tabsibling-added" "added" "$fg_tabsib_res" "##<tab>Other sibling bounds the section (tab-aware level) → Validation has no in-range command → added"
assert_eq "file-guard:validation-tabsibling-one-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_tabsib")" "exactly ONE ## Validation heading (sibling not swallowed; body inserted under Validation)"
# The tab sibling is preserved verbatim and was NOT absorbed into / rewritten by the Validation range.
assert_eq "file-guard:validation-tabsibling-preserved" "1" \
  "$(grep -cP '^##\tOther$' "$fg_claude_tabsib")" "##<tab>Other sibling heading preserved verbatim"

# 14g-crlf. CRLF RECOGNITION LOCK (PR #297 ATX-completion): a CLAUDE.md with CRLF line endings whose
# `## Validation\r\n` heading carries a fenced command body must be RECOGNIZED (the parser strips the
# trailing `\r` before comparing) → already documented, byte-unchanged, NO duplicate appended. Non-
# vacuous: without the `\r` strip the heading text would be `Validation\r` ≠ `Validation` → the
# section is missed → a duplicate canonical `## Validation` block appended and verdict `added`.
fg_claude_crlf="$WORKDIR/fg-claude-crlf.md"
printf '# Project\r\n\r\n## Validation\r\n\r\n```bash\r\nnpm test\r\n```\r\n' > "$fg_claude_crlf"
fg_crlf_before="$(cat "$fg_claude_crlf")"
fg_crlf_res="$(hivemind_guard_validation_section "$fg_claude_crlf" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-crlf-documented" "already documented" "$fg_crlf_res" "CRLF ## Validation\\r with command → recognized → already documented"
assert_eq "file-guard:validation-crlf-bytes" "$fg_crlf_before" "$(cat "$fg_claude_crlf")" "CRLF file byte-unchanged (no duplicate)"
# Exactly one Validation heading — the CRLF heading carries a trailing \r, so match it tolerantly.
assert_eq "file-guard:validation-crlf-one-heading" "1" \
  "$(grep -cE '^## Validation'$'\r''?$' "$fg_claude_crlf")" "exactly ONE ## Validation heading (CRLF, no duplicate appended)"

# 14g-closinghash. §4.3 CLOSING-SEQUENCE MATRIX (PR #297 ATX approach-level zoom-out): the
# general-ATX-text-extraction edge class is ELIMINATED; heading detection is now normalize-and-equate
# against the skill's own canonical `## Validation` heading. The reduction strips a closing `#` run
# ONLY when it is preceded by whitespace (a true CommonMark §4.3 closing sequence); a `#` run GLUED to
# the heading text with no preceding whitespace is PART OF the text. Therefore `## Validation#` and
# `## Validation##` (no space) reduce to text `Validation#`/`Validation##` ≠ `Validation` → NOT the
# heading → ABSENT → the real `## Validation` section is created. `## Validation #` /
# `## Validation ###` (space before the run) STAY recognized as the existing section. This matrix
# locks the canonical-equate primitive against any revert to the prior unconditional closing-hash trim.
#
# (a) `## Validation#` (closing hash, NO preceding space) + fenced body → text `Validation#` ≠
# `Validation` → ABSENT → `added`, real `## Validation` section created. LOAD-BEARING: pre-fix the
# unconditional trim reduced this to `Validation` → wrongly `already documented`.
fg_claude_ch1="$WORKDIR/fg-claude-closinghash1.md"
printf '# Project\n\n## Validation#\n\n```bash\nnpm test\n```\n' > "$fg_claude_ch1"
fg_ch1_res="$(hivemind_guard_validation_section "$fg_claude_ch1" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-closinghash-nospace-added" "added" "$fg_ch1_res" "## Validation# (glued closing hash, no space) → text Validation# → ABSENT → added"
assert_eq "file-guard:validation-closinghash-nospace-real-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_ch1")" "real ## Validation heading created beside ## Validation#"
assert_eq "file-guard:validation-closinghash-nospace-preserved" "1" \
  "$(grep -c '^## Validation#$' "$fg_claude_ch1")" "## Validation# (text-bearing closing hash) preserved verbatim"

# (b) `## Validation##` (double closing hash, NO preceding space) + body → text `Validation##` →
# ABSENT → `added`. LOAD-BEARING: pre-fix the unconditional trim reduced this to `Validation`.
fg_claude_ch2="$WORKDIR/fg-claude-closinghash2.md"
printf '# Project\n\n## Validation##\n\n```bash\nnpm test\n```\n' > "$fg_claude_ch2"
fg_ch2_res="$(hivemind_guard_validation_section "$fg_claude_ch2" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-closinghash-double-added" "added" "$fg_ch2_res" "## Validation## (glued double closing hash, no space) → text Validation## → ABSENT → added"
assert_eq "file-guard:validation-closinghash-double-real-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_ch2")" "real ## Validation heading created beside ## Validation##"
assert_eq "file-guard:validation-closinghash-double-preserved" "1" \
  "$(grep -c '^## Validation##$' "$fg_claude_ch2")" "## Validation## (text-bearing double closing hash) preserved verbatim"

# (c) `## Validation #` (single closing hash WITH a preceding space) + body → true §4.3 closing
# sequence → text `Validation` → recognized → `already documented`, byte-unchanged.
fg_claude_ch3="$WORKDIR/fg-claude-closinghash3.md"
printf '# Project\n\n## Validation #\n\n```bash\nmake test\n```\n' > "$fg_claude_ch3"
fg_ch3_before="$(cat "$fg_claude_ch3")"
fg_ch3_res="$(hivemind_guard_validation_section "$fg_claude_ch3" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-closinghash-space-documented" "already documented" "$fg_ch3_res" "## Validation # (space before closing hash, §4.3 closing seq) with command → already documented"
assert_eq "file-guard:validation-closinghash-space-bytes" "$fg_ch3_before" "$(cat "$fg_claude_ch3")" "## Validation # heading file byte-unchanged"

# (d) `## Validation ###` (closing-hash RUN WITH a preceding space) + body → §4.3 closing sequence →
# text `Validation` → recognized → `already documented`, byte-unchanged.
fg_claude_ch4="$WORKDIR/fg-claude-closinghash4.md"
printf '# Project\n\n## Validation ###\n\n```bash\nmake test\n```\n' > "$fg_claude_ch4"
fg_ch4_before="$(cat "$fg_claude_ch4")"
fg_ch4_res="$(hivemind_guard_validation_section "$fg_claude_ch4" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-closinghash-run-documented" "already documented" "$fg_ch4_res" "## Validation ### (space before closing-hash run) with command → already documented"
assert_eq "file-guard:validation-closinghash-run-bytes" "$fg_ch4_before" "$(cat "$fg_claude_ch4")" "## Validation ### heading file byte-unchanged"

# (e) SIBLING `## Other#` (glued closing hash on a SIBLING) still bounds the `## Validation` section:
# it is a LEVEL-2 heading (text `Other#`), so it ENDS the Validation section AFTER the fenced block,
# leaving the command in range → already documented, byte-unchanged, sibling preserved. Regression
# guard that the level path is UNCHANGED by the text-extraction fix (closing-hash glue does not
# demote a sibling out of level-2 heading status).
fg_claude_ch5="$WORKDIR/fg-claude-closinghash-sibling.md"
printf '# Project\n\n## Validation\n\n```bash\nmake test\n```\n\n## Other#\n\nbody.\n' > "$fg_claude_ch5"
fg_ch5_before="$(cat "$fg_claude_ch5")"
fg_ch5_res="$(hivemind_guard_validation_section "$fg_claude_ch5" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-closinghash-sibling-documented" "already documented" "$fg_ch5_res" "## Other# sibling (level-2, glued closing hash) bounds the section; in-range command → already documented"
assert_eq "file-guard:validation-closinghash-sibling-bytes" "$fg_ch5_before" "$(cat "$fg_claude_ch5")" "## Other# sibling-bound file byte-unchanged (no duplicate)"
assert_eq "file-guard:validation-closinghash-sibling-preserved" "1" \
  "$(grep -c '^## Other#$' "$fg_claude_ch5")" "## Other# sibling heading preserved verbatim (still a level-2 bound)"

# (f) `####### Validation` (7 `#`s) is NOT an ATX heading → ABSENT → real `## Validation` created.
# Regression guard for the level path (7+ marker reject) under the new reduction.
fg_claude_ch6="$WORKDIR/fg-claude-closinghash-seven.md"
printf '# Project\n\n####### Validation\n\nnot a heading.\n' > "$fg_claude_ch6"
fg_ch6_res="$(hivemind_guard_validation_section "$fg_claude_ch6" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-sevenhash-added" "added" "$fg_ch6_res" "####### Validation (7 hashes, not ATX) → ABSENT → added"
assert_eq "file-guard:validation-sevenhash-real-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_ch6")" "real ## Validation heading created beside the 7-hash line"

# (g) `##5 Validation` (no space after the marker run) is NOT an ATX heading → ABSENT → real
# `## Validation` created. Regression guard for the after-marker-whitespace requirement.
fg_claude_ch7="$WORKDIR/fg-claude-closinghash-nomarkerws.md"
printf '# Project\n\n##5 Validation\n\nnot a heading.\n' > "$fg_claude_ch7"
fg_ch7_res="$(hivemind_guard_validation_section "$fg_claude_ch7" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-nomarkerws-added" "added" "$fg_ch7_res" "##5 Validation (no space after marker) → not ATX → ABSENT → added"
assert_eq "file-guard:validation-nomarkerws-real-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_ch7")" "real ## Validation heading created beside ##5 Validation"

# (h) `## Validation` indented 4 spaces is an indented code block, NOT a heading → ABSENT → real
# column-0 `## Validation` created. Regression guard for the 4+-indent reject.
fg_claude_ch8="$WORKDIR/fg-claude-closinghash-indent4.md"
printf '# Project\n\n    ## Validation\n\nnot a heading (indented).\n' > "$fg_claude_ch8"
fg_ch8_res="$(hivemind_guard_validation_section "$fg_claude_ch8" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-ch-indent4-added" "added" "$fg_ch8_res" "    ## Validation (4-space indent) → not a heading → ABSENT → added"
assert_eq "file-guard:validation-ch-indent4-real-heading" "1" \
  "$(grep -c '^## Validation$' "$fg_claude_ch8")" "real column-0 ## Validation heading created"

# (i) `##\tValidation` (TAB after the marker) WITH a fenced command → reduces to the canonical
# `Validation` → recognized → already documented, byte-unchanged. Regression guard for tab-after-marker.
fg_claude_ch9="$WORKDIR/fg-claude-closinghash-tabmarker.md"
printf '# Project\n\n##\tValidation\n\n```bash\nmake test\n```\n' > "$fg_claude_ch9"
fg_ch9_before="$(cat "$fg_claude_ch9")"
fg_ch9_res="$(hivemind_guard_validation_section "$fg_claude_ch9" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-ch-tabmarker-documented" "already documented" "$fg_ch9_res" "##<tab>Validation (tab marker) with command → reduces to Validation → already documented"
assert_eq "file-guard:validation-ch-tabmarker-bytes" "$fg_ch9_before" "$(cat "$fg_claude_ch9")" "##<tab>Validation heading file byte-unchanged"

# (j) CRLF `## Validation\r` WITH a fenced command → the `\r` is stripped before the equate →
# reduces to `Validation` → recognized → already documented, byte-unchanged. Regression guard for CRLF.
fg_claude_ch10="$WORKDIR/fg-claude-closinghash-crlf.md"
printf '# Project\r\n\r\n## Validation\r\n\r\n```bash\r\nmake test\r\n```\r\n' > "$fg_claude_ch10"
fg_ch10_before="$(cat "$fg_claude_ch10")"
fg_ch10_res="$(hivemind_guard_validation_section "$fg_claude_ch10" "$FG_VALIDATION_BODY")"
assert_eq "file-guard:validation-ch-crlf-documented" "already documented" "$fg_ch10_res" "CRLF ## Validation\\r with command → \\r stripped before equate → already documented"
assert_eq "file-guard:validation-ch-crlf-bytes" "$fg_ch10_before" "$(cat "$fg_claude_ch10")" "CRLF ## Validation file byte-unchanged"

# 14h. INERT: a hostile entry value crafted as a command-substitution payload is written as plain
# text, never executed (proves the text guards never eval/source the entry).
rm -f "$PWN_MARKER"
fg_inert="$WORKDIR/fg-inert-gitignore"
rm -f "$fg_inert"
hivemind_append_if_absent "$fg_inert" "\$(touch $PWN_MARKER)" >/dev/null
if [ -e "$PWN_MARKER" ]; then
  failed "file-guard:inert-no-side-effect" "an entry value triggered command substitution: $PWN_MARKER created"
else
  pass "file-guard:inert-no-side-effect" "no entry value triggered command substitution"
fi

# ── Section 15: test-detect.sh — ecosystem signal→command projector + ## Validation recorder ──
echo '=== test-detect.sh: ecosystem detection + JS sub-signal ordering + ## Validation recorder ==='
#
# AUTHORITATIVE regression tests for the seed-hive step-14 test-command detector (SKILL.md step
# 14a/b/c/d/f). Every case is HERMETIC: it builds its own tmp PROJECT dir under $WORKDIR holding
# only the signal files under test, then asserts the EXACT ecosystem→command mapping, the JS
# sub-signal ordering, the runner-agnostic `npm init` placeholder rejection, non-string
# scripts.test fall-through, monorepo multi-match (root signals only), and the file-guard
# delegation for the `## Validation` append.

# Helper: build a fresh empty project dir and echo its path.
td_new_project() {
  local p
  p="$(mktemp -d "$WORKDIR/td-proj.XXXXXX")"
  printf '%s' "$p"
}

# 15a. Each ecosystem emits its correct command (one focused project per ecosystem).
# JS curated scripts.test → npm test.
td_js="$(td_new_project)"
printf '{"scripts":{"test":"jest --runInBand"}}\n' > "$td_js/package.json"
assert_eq "test-detect:js-curated" "npm test" "$(hivemind_detect_test_commands "$td_js")" "curated scripts.test → npm test"

# Python pytest (pyproject.toml with a pytest dependency signal) → pytest.
td_py="$(td_new_project)"
printf '[project]\ndependencies = ["pytest"]\n' > "$td_py/pyproject.toml"
assert_eq "test-detect:python" "pytest" "$(hivemind_detect_test_commands "$td_py")" "pyproject pytest signal → pytest"

# Python pytest NESTED test file (tests/unit/test_api.py, no direct-child test file) → pytest.
# NON-VACUITY: the old shallow ls-glob misses tests/unit/test_api.py so this case FAILS against
# the unfixed code (emitting nothing) and PASSES only with the recursive find fix.
td_py_nested="$(td_new_project)"
printf '[tool.pytest.ini_options]\n' > "$td_py_nested/pyproject.toml"
mkdir -p "$td_py_nested/tests/unit"
printf '# unit test\n' > "$td_py_nested/tests/unit/test_api.py"
assert_eq "test-detect:python-nested-test-file" "pytest" \
  "$(hivemind_detect_test_commands "$td_py_nested")" \
  "pyproject.toml [tool.pytest] + nested tests/unit/test_api.py → pytest"

# Python pytest DIRECT-CHILD regression: tests/test_foo.py still detected after the recursive fix.
td_py_direct="$(td_new_project)"
printf '[tool.pytest.ini_options]\n' > "$td_py_direct/pyproject.toml"
mkdir -p "$td_py_direct/tests"
printf '# test\n' > "$td_py_direct/tests/test_foo.py"
assert_eq "test-detect:python-direct-test-file" "pytest" \
  "$(hivemind_detect_test_commands "$td_py_direct")" \
  "direct-child tests/test_foo.py still detected (recursive find includes depth-1)"

# Python pytest NO-SIGNAL regression: pyproject.toml without a pytest signal AND no test files → no pytest.
td_py_nosig="$(td_new_project)"
printf '[project]\nname = "myapp"\n' > "$td_py_nosig/pyproject.toml"
mkdir -p "$td_py_nosig/tests"
printf '# helper\n' > "$td_py_nosig/tests/helpers.py"
assert_eq "test-detect:python-no-signal" "" \
  "$(hivemind_detect_test_commands "$td_py_nosig")" \
  "pyproject without pytest signal and no test_*.py/*_test.py → no pytest command"

# Go → go test ./...
td_go="$(td_new_project)"
printf 'module example.com/x\n\ngo 1.22\n' > "$td_go/go.mod"
assert_eq "test-detect:go" "go test ./..." "$(hivemind_detect_test_commands "$td_go")" "go.mod → go test ./..."

# Rust → cargo test.
td_rs="$(td_new_project)"
printf '[package]\nname = "x"\n' > "$td_rs/Cargo.toml"
assert_eq "test-detect:rust" "cargo test" "$(hivemind_detect_test_commands "$td_rs")" "Cargo.toml → cargo test"

# .NET csproj referencing Microsoft.NET.Test.Sdk → dotnet test.
td_net="$(td_new_project)"
printf '<Project><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" /></ItemGroup></Project>\n' > "$td_net/app.csproj"
assert_eq "test-detect:dotnet" "dotnet test" "$(hivemind_detect_test_commands "$td_net")" "csproj with Test.Sdk → dotnet test"
# .NET csproj WITHOUT the Test.Sdk reference → no signal (file existence alone insufficient).
td_net_bare="$(td_new_project)"
printf '<Project></Project>\n' > "$td_net_bare/app.csproj"
assert_eq "test-detect:dotnet-no-sdk" "" "$(hivemind_detect_test_commands "$td_net_bare")" "csproj without Test.Sdk → no command"

# Elixir → mix test.
td_ex="$(td_new_project)"
printf 'defmodule X.MixProject do\nend\n' > "$td_ex/mix.exs"
assert_eq "test-detect:elixir" "mix test" "$(hivemind_detect_test_commands "$td_ex")" "mix.exs → mix test"

# Ruby Gemfile with rspec → bundle exec rspec.
td_rb="$(td_new_project)"
printf 'gem "rspec"\n' > "$td_rb/Gemfile"
assert_eq "test-detect:ruby" "bundle exec rspec" "$(hivemind_detect_test_commands "$td_rb")" "Gemfile rspec signal → bundle exec rspec"

# Ruby rspec NESTED spec file (spec/unit/foo_spec.rb, no direct-child spec file) → bundle exec rspec.
# NON-VACUITY: the old shallow ls-glob misses spec/unit/foo_spec.rb so this case FAILS against
# the unfixed code and PASSES only with the recursive find fix.
td_rb_nested="$(td_new_project)"
mkdir -p "$td_rb_nested/spec/unit"
printf '# unit spec\n' > "$td_rb_nested/spec/unit/foo_spec.rb"
assert_eq "test-detect:ruby-nested-spec-file" "bundle exec rspec" \
  "$(hivemind_detect_test_commands "$td_rb_nested")" \
  "nested spec/unit/foo_spec.rb with no Gemfile rspec → bundle exec rspec"

# Ruby rspec DIRECT-CHILD regression: spec/bar_spec.rb still detected after the recursive fix.
td_rb_direct="$(td_new_project)"
mkdir -p "$td_rb_direct/spec"
printf '# spec\n' > "$td_rb_direct/spec/bar_spec.rb"
assert_eq "test-detect:ruby-direct-spec-file" "bundle exec rspec" \
  "$(hivemind_detect_test_commands "$td_rb_direct")" \
  "direct-child spec/bar_spec.rb still detected (recursive find includes depth-1)"

# Make TARGET-vs-ASSIGNMENT-vs-RECIPE grammar matrix. The matcher classifies each line by make's
# rule grammar; every assertion below carries a non-vacuity note tied to the pre-fix OPEN regex
# `^[ ]*test[[:space:]]*:` (which matched `test` + optional space + ANY colon, so it false-positived
# on `:=`/`::=` assignment lines) or to a behavior that must be PRESERVED.
# (1) column-0 real target → make test [preserved].
td_mk="$(td_new_project)"
printf 'test:\n\tgo test ./...\n' > "$td_mk/Makefile"
assert_eq "test-detect:make" "make test" "$(hivemind_detect_test_commands "$td_mk")" "column-0 test: target → make test [preserved]"
# (2) space-leading target → make test [Fix-1 guard: column-0-anchored regex would miss this].
td_mk_sp="$(td_new_project)"
printf ' test:\n\t@echo run\n' > "$td_mk_sp/Makefile"
assert_eq "test-detect:make-space-target" "make test" "$(hivemind_detect_test_commands "$td_mk_sp")" "space-indented test: target → make test [Fix-1 guard]"
# (3) double-colon rule target → make test [non-vacuity: a naive reject-any-second-char-after-colon
# would wrongly drop this VALID target].
td_mk_dc="$(td_new_project)"
printf 'test::\n\t@echo dc\n' > "$td_mk_dc/Makefile"
assert_eq "test-detect:make-double-colon" "make test" "$(hivemind_detect_test_commands "$td_mk_dc")" "double-colon test:: rule → make test [non-vacuity: valid target, second char is a colon]"
# (4) THE Codex P2: `test :=` recursive assignment, no real target → empty [pre-fix the regex
# matched the `:` of `:=` → false positive; rejected post-fix by the assignment-operator grammar].
td_mk_assign="$(td_new_project)"
printf 'test := foo\nbuild:\n\tgo build ./...\n' > "$td_mk_assign/Makefile"
assert_eq "test-detect:make-assign-colon-eq" "" "$(hivemind_detect_test_commands "$td_mk_assign")" "test := assignment, no target → empty [Codex P2: pre-fix matched the : of :=]"
# (5) `test ::=` POSIX simple assignment → empty [pre-fix regex matched the first `:` of `::=` →
# false positive; rejected post-fix].
td_mk_assign2="$(td_new_project)"
printf 'test ::= foo\nbuild:\n\tgo build ./...\n' > "$td_mk_assign2/Makefile"
assert_eq "test-detect:make-assign-dcolon-eq" "" "$(hivemind_detect_test_commands "$td_mk_assign2")" "test ::= assignment → empty [pre-fix matched first : of ::=]"
# (6) `test ?=` conditional assignment → empty [grammar class lock: rejected by the assignment-operator
# branch, never reached the pre-fix regex's colon at all but locks the class].
td_mk_q="$(td_new_project)"
printf 'test ?= foo\nbuild:\n\tgo build ./...\n' > "$td_mk_q/Makefile"
assert_eq "test-detect:make-assign-qeq" "" "$(hivemind_detect_test_commands "$td_mk_q")" "test ?= assignment → empty [grammar class lock]"
# (7) `test +=` append assignment → empty [grammar class lock].
td_mk_plus="$(td_new_project)"
printf 'test += foo\nbuild:\n\tgo build ./...\n' > "$td_mk_plus/Makefile"
assert_eq "test-detect:make-assign-pluseq" "" "$(hivemind_detect_test_commands "$td_mk_plus")" "test += assignment → empty [grammar class lock]"
# (8) `test !=` shell assignment → empty [grammar class lock].
td_mk_bang="$(td_new_project)"
printf 'test != echo foo\nbuild:\n\tgo build ./...\n' > "$td_mk_bang/Makefile"
assert_eq "test-detect:make-assign-bangeq" "" "$(hivemind_detect_test_commands "$td_mk_bang")" "test != shell-assignment → empty [grammar class lock]"
# (9) `.PHONY: test` with NO `test:` recipe → empty [non-vacuity: locks the decision that a phony
# DECLARATION with no recipe is not a runnable `make test`; first token is `.PHONY`, not `test`].
td_mk_phony="$(td_new_project)"
printf '.PHONY: test\nbuild:\n\tgo build ./...\n' > "$td_mk_phony/Makefile"
assert_eq "test-detect:make-phony-only" "" "$(hivemind_detect_test_commands "$td_mk_phony")" ".PHONY: test with no test: recipe → empty [first token is .PHONY, not test]"
# (10) `.PHONY: test` PLUS a real `test:` recipe elsewhere → make test [the real target line matches
# independently of the phony declaration].
td_mk_phony2="$(td_new_project)"
printf '.PHONY: test\ntest:\n\tgo test ./...\n' > "$td_mk_phony2/Makefile"
assert_eq "test-detect:make-phony-plus-target" "make test" "$(hivemind_detect_test_commands "$td_mk_phony2")" ".PHONY: test plus real test: recipe → make test [real target matches independently]"
# (11) TAB-indented `test:` recipe line under another target → empty [regresses if the leading class
# is loosened to `[[:space:]]*`; locks the literal-space invariant — a TAB-led line is a recipe].
td_mk_tab="$(td_new_project)"
printf 'build:\n\ttest: not-a-target\n' > "$td_mk_tab/Makefile"
assert_eq "test-detect:make-tab-recipe" "" "$(hivemind_detect_test_commands "$td_mk_tab")" "TAB-indented test: recipe line → empty [locks literal-space leading invariant]"
# (12) `testing:` near-miss → empty [token-boundary guard: first token is `testing`, not `test`].
td_mk_near="$(td_new_project)"
printf 'testing:\n\t@echo x\n' > "$td_mk_near/Makefile"
assert_eq "test-detect:make-near-miss" "" "$(hivemind_detect_test_commands "$td_mk_near")" "testing: near-miss → empty [token-boundary guard]"
# (13) `test: VAR=x` target-specific variable line → make test [non-vacuity: a matcher rejecting ANY
# `=` after the colon would wrongly drop this REAL target — distinguishes the assignment OPERATOR
# (`:=`/`::=`/`?=`/`+=`/`!=`) from any plain `=` appearing in the recipe/prereqs].
td_mk_tsv="$(td_new_project)"
printf 'test: VAR=x\n\tgo test ./...\n' > "$td_mk_tsv/Makefile"
assert_eq "test-detect:make-target-specific-var" "make test" "$(hivemind_detect_test_commands "$td_mk_tsv")" "test: VAR=x target-specific variable → make test [non-vacuity: any-= reject would drop a real target]"
# Makefile WITHOUT any test: target → no signal [preserved].
td_mk_bare="$(td_new_project)"
printf 'build:\n\tgo build ./...\n' > "$td_mk_bare/Makefile"
assert_eq "test-detect:make-no-target" "" "$(hivemind_detect_test_commands "$td_mk_bare")" "Makefile lacking test: target → no command [preserved]"

# 15b. JS sub-signal ordering: a curated scripts.test WINS over a parallel vitest/jest dependency
# (the fallback is NOT taken when sub-signal 1 matches).
td_js_order="$(td_new_project)"
printf '{"scripts":{"test":"vitest run --coverage"},"devDependencies":{"vitest":"^1.0.0","jest":"^29.0.0"}}\n' > "$td_js_order/package.json"
assert_eq "test-detect:js-curated-wins" "npm test" "$(hivemind_detect_test_commands "$td_js_order")" "curated scripts.test wins over vitest/jest deps"
# vitest fallback fires only when scripts.test is unmatched.
td_js_vitest="$(td_new_project)"
printf '{"devDependencies":{"vitest":"^1.0.0"}}\n' > "$td_js_vitest/package.json"
assert_eq "test-detect:js-vitest-fallback" "npx vitest run" "$(hivemind_detect_test_commands "$td_js_vitest")" "no scripts.test, vitest dep → npx vitest run"
# jest fallback fires only when scripts.test AND vitest are both unmatched.
td_js_jest="$(td_new_project)"
printf '{"devDependencies":{"jest":"^29.0.0"}}\n' > "$td_js_jest/package.json"
assert_eq "test-detect:js-jest-fallback" "npx jest" "$(hivemind_detect_test_commands "$td_js_jest")" "no scripts.test/vitest, jest dep → npx jest"
# vitest precedes jest when BOTH deps present and scripts.test is unmatched.
td_js_both="$(td_new_project)"
printf '{"devDependencies":{"vitest":"^1.0.0","jest":"^29.0.0"}}\n' > "$td_js_both/package.json"
assert_eq "test-detect:js-vitest-over-jest" "npx vitest run" "$(hivemind_detect_test_commands "$td_js_both")" "vitest precedes jest fallback"

# 15c. `npm init` placeholder (`Error: no test specified`) → UNMATCHED, falls through to the
# fallbacks. Runner-AGNOSTIC: prove the substring rejection with EACH of the npm/yarn/pnpm init
# default prefixes; none of them is ever emitted as `npm test`.
for td_init_prefix in 'echo "Error: no test specified" && exit 1' \
                      'echo \"Error: no test specified\" && exit 1'; do
  td_init="$(td_new_project)"
  jq -n --arg t "$td_init_prefix" '{scripts:{test:$t},devDependencies:{vitest:"^1.0.0"}}' > "$td_init/package.json"
  assert_eq "test-detect:placeholder-fallthrough" "npx vitest run" "$(hivemind_detect_test_commands "$td_init")" \
    "init placeholder scripts.test rejected → falls through to vitest (not npm test)"
done
# Placeholder with NO fallback present → JS contributes nothing (no-signal path).
td_init_only="$(td_new_project)"
jq -n '{scripts:{test:"echo \"Error: no test specified\" && exit 1"}}' > "$td_init_only/package.json"
assert_eq "test-detect:placeholder-only" "" "$(hivemind_detect_test_commands "$td_init_only")" \
  "init placeholder with no vitest/jest fallback → no command emitted"
# Case-insensitivity of the substring guard.
td_init_case="$(td_new_project)"
jq -n '{scripts:{test:"echo \"ERROR: NO TEST SPECIFIED\" && exit 1"},devDependencies:{jest:"^29.0.0"}}' > "$td_init_case/package.json"
assert_eq "test-detect:placeholder-case-insensitive" "npx jest" "$(hivemind_detect_test_commands "$td_init_case")" \
  "uppercase placeholder still rejected (case-insensitive) → jest fallback"

# 15d. Non-string scripts.test (object / number) → UNMATCHED, falls through to fallbacks.
td_nonstr_obj="$(td_new_project)"
printf '{"scripts":{"test":{"cmd":"x"}},"devDependencies":{"vitest":"^1.0.0"}}\n' > "$td_nonstr_obj/package.json"
assert_eq "test-detect:nonstring-object" "npx vitest run" "$(hivemind_detect_test_commands "$td_nonstr_obj")" \
  "object scripts.test unmatched → vitest fallback"
td_nonstr_num="$(td_new_project)"
printf '{"scripts":{"test":42},"devDependencies":{"jest":"^29.0.0"}}\n' > "$td_nonstr_num/package.json"
assert_eq "test-detect:nonstring-number" "npx jest" "$(hivemind_detect_test_commands "$td_nonstr_num")" \
  "numeric scripts.test unmatched → jest fallback"
# Non-string scripts.test with NO fallback → JS contributes nothing.
td_nonstr_only="$(td_new_project)"
printf '{"scripts":{"test":["a","b"]}}\n' > "$td_nonstr_only/package.json"
assert_eq "test-detect:nonstring-only" "" "$(hivemind_detect_test_commands "$td_nonstr_only")" \
  "array scripts.test, no fallback → no command"

# 15e. Monorepo multi-match: root package.json (curated) + go.mod → BOTH commands, in canonical
# order, NEVER combined. A NESTED package.json is ignored (root signals only).
td_mono="$(td_new_project)"
printf '{"scripts":{"test":"npm run jest"}}\n' > "$td_mono/package.json"
printf 'module example.com/x\n\ngo 1.22\n' > "$td_mono/go.mod"
mkdir -p "$td_mono/packages/nested"
printf '{"scripts":{"test":"echo nested"}}\n' > "$td_mono/packages/nested/package.json"
assert_eq "test-detect:monorepo-both" "npm test
go test ./..." "$(hivemind_detect_test_commands "$td_mono")" \
  "root package.json + go.mod → both commands, JS before Go, never combined, nested ignored"

# 15f. No-signal project → detector emits nothing; recorder reports recommend-manual and writes
# NOTHING (nothing fabricated).
td_empty="$(td_new_project)"
printf '# Just docs\n' > "$td_empty/README.md"
assert_eq "test-detect:no-signal-detect" "" "$(hivemind_detect_test_commands "$td_empty")" "no signal → empty detector output"
td_empty_claude="$td_empty/CLAUDE.md"
rm -f "$td_empty_claude"
td_rec_none="$(hivemind_record_validation "$td_empty" "$td_empty_claude")"
assert_eq "test-detect:no-signal-recorder" "none detected (recommend manual)" "$td_rec_none" "no signal → recommend manual"
if [ -e "$td_empty_claude" ]; then
  failed "test-detect:no-signal-no-write" "recorder fabricated a CLAUDE.md on the no-signal path"
else
  pass "test-detect:no-signal-no-write" "no-signal recorder wrote nothing (no fabrication)"
fi

# 15g. Recorder DELEGATES the `## Validation` append to file-guard.sh: absent CLAUDE.md → `added`
# with a fenced block per command; existing `## Validation` → `already documented`, prose
# byte-untouched.
td_rec="$(td_new_project)"
printf 'module example.com/x\n\ngo 1.22\n' > "$td_rec/go.mod"
td_rec_claude="$td_rec/CLAUDE.md"
rm -f "$td_rec_claude"
td_rec_added="$(hivemind_record_validation "$td_rec" "$td_rec_claude")"
assert_eq "test-detect:recorder-added" "added" "$td_rec_added" "absent CLAUDE.md, go signal → added (delegated to file-guard)"
assert_eq "test-detect:recorder-section" "1" "$(grep -c '^## Validation$' "$td_rec_claude")" "## Validation heading written once"
assert_eq "test-detect:recorder-command" "1" "$(grep -cF 'go test ./...' "$td_rec_claude")" "detected command in the fenced block"
# Already-documented project → already documented, existing prose untouched (file-guard delegation).
td_doc="$(td_new_project)"
printf 'module example.com/x\n\ngo 1.22\n' > "$td_doc/go.mod"
td_doc_claude="$td_doc/CLAUDE.md"
printf '# Project\n\n## Validation\n\n```bash\nmake test\n```\n' > "$td_doc_claude"
td_doc_before="$(cat "$td_doc_claude")"
td_doc_res="$(hivemind_record_validation "$td_doc" "$td_doc_claude")"
assert_eq "test-detect:recorder-already-documented" "already documented" "$td_doc_res" "existing ## Validation → already documented"
assert_eq "test-detect:recorder-prose-untouched" "$td_doc_before" "$(cat "$td_doc_claude")" "existing ## Validation prose left byte-unchanged"

# 15h. Monorepo recorder: multiple commands → one fenced block PER command, both present.
td_mono_rec="$(td_new_project)"
printf '{"scripts":{"test":"npm run x"}}\n' > "$td_mono_rec/package.json"
printf 'module example.com/x\n\ngo 1.22\n' > "$td_mono_rec/go.mod"
td_mono_claude="$td_mono_rec/CLAUDE.md"
rm -f "$td_mono_claude"
hivemind_record_validation "$td_mono_rec" "$td_mono_claude" >/dev/null
assert_eq "test-detect:monorepo-recorder-js" "1" "$(grep -cF 'npm test' "$td_mono_claude")" "npm test fenced block present"
assert_eq "test-detect:monorepo-recorder-go" "1" "$(grep -cF 'go test ./...' "$td_mono_claude")" "go test ./... fenced block present"

# ── Section 16: root-cluster class-locking matrix (RR3-STEP-005) ────────────────────
echo ''
echo '=== root-cluster class-locking matrix: seed-hive merge-predicate-gap regression lock ==='
#
# CLASS LOCK for the seed-hive MERGE-PREDICATE-GAP cluster (PR #297). The site fixes that closed the
# cluster each replaced a presence-only predicate with a VALUE-STATE NORMALIZATION (or its approach-
# level extension). Clauses (1)-(3) are the RR3 closure; (4)-(5) are the RR4 approach-level closure:
#   (1) file-guard `## Validation`  — bare-heading presence → BODY presence (heading-only stub is ABSENT)
#   (2) settings-merge `agent`      — any-present-string → empty/whitespace normalizes to ABSENT
#   (3) claude-mem CLAUDE_CODE_PATH — present-non-empty-string → present-non-string/null is NEVER clobbered
#   (4) file-guard `## Validation`  — PRESENT-NO-COMMAND is APPENDED-UNDER (prose byte-preserved, not replaced)
#   (5) settings-merge containers   — wrong-typed container → canon_obj/canon_arr empty → merge stays `ok` (no jq abort)
#   (6) settings-merge enabledPlugins — present-but-false value-equality → classified `added` AND corrected to `true`
#   (7) BOTH settings-merge + claude-mem — multi-document JSON STREAM rejected via the shared json-normalize.sh
#       single-document gate (settings-merge → `malformed`; claude-mem → `skipped (malformed json)`, byte-unchanged)
#   (8) settings-merge hook ELEMENTS — every jq type at both element positions → merge stays `ok`, element
#       preserved, canonical entry appended. This is the ELEMENT-POSITION extension of clause (5): (5) locks a
#       wrong-typed CONTAINER collapsing to its canonical empty, (8) locks a wrong-typed ELEMENT reading as its
#       canonical empty object — the same normalization law applied at the other kind of position, which is why
#       it belongs on THIS matrix rather than a parallel one.
# This single test asserts ALL EIGHT together as the NAMED root-cluster lock so a future single-SITE
# regression (reverting just one predicate / one approach-level fix / either single-document gate) trips
# it. It is NON-VACUOUS: each clause below fails independently if its corresponding site fix reverts, so
# no one site can silently regress while the others hold.
mx_fail=0

# Matrix clause (1): heading-only `## Validation` → command appended (file-guard body-presence).
# Reverts-as: a bare-heading predicate would report `already documented` and write no fenced block.
mx_claude="$WORKDIR/mx-claude.md"
printf '# Project\n\n## Validation\n' > "$mx_claude"
mx_v="$(hivemind_guard_validation_section "$mx_claude" "$FG_VALIDATION_BODY")"
[ "$mx_v" = "added" ] || { mx_fail=1; echo "  matrix-1 FAIL: heading-only stub status=$mx_v (want added)"; }
grep -q "$(printf '^\140\140\140bash$')" "$mx_claude" || { mx_fail=1; echo "  matrix-1 FAIL: command body not appended into stub"; }

# Matrix clause (2): `agent:""` → `added` not conflict (settings-merge value-state normalization).
# Reverts-as: an any-present-string predicate would classify "" as a real value → conflict.
mx_sm="$(hivemind_settings_merge '{"agent":""}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
mx_sm_class="$(printf '%s' "$mx_sm" | jq -r '.keys.agent')"
mx_sm_status="$(printf '%s' "$mx_sm" | jq -r '.status')"
[ "$mx_sm_class" = "added" ] || { mx_fail=1; echo "  matrix-2 FAIL: empty agent class=$mx_sm_class (want added)"; }
[ "$mx_sm_status" = "ok" ] || { mx_fail=1; echo "  matrix-2 FAIL: empty agent status=$mx_sm_status (want ok)"; }

# Matrix clause (3): present non-string CLAUDE_CODE_PATH → skipped-not-clobbered (claude-mem never-clobber).
# Reverts-as: a normalize-non-string-to-absent predicate would resolve+write → status `set`, bytes change.
mx_home="$(cm_setup_home mx-claude-mem)"
mx_cm_file="$mx_home/.claude-mem/settings.json"
printf '{\n  "CLAUDE_CODE_PATH": false,\n  "logLevel": "info"\n}\n' > "$mx_cm_file"
mx_cm_before="$(cat "$mx_cm_file")"
mx_cm_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$mx_cm_file" "$mx_home")"
[ "$mx_cm_status" = "already set" ] || { mx_fail=1; echo "  matrix-3 FAIL: non-string status=$mx_cm_status (want already set)"; }
[ "$mx_cm_before" = "$(cat "$mx_cm_file")" ] || { mx_fail=1; echo "  matrix-3 FAIL: non-string file was clobbered"; }

# Matrix clause (4) [RR4]: PROSE-PRESERVATION — a prose-only `## Validation` is APPENDED-UNDER, the
# prose byte-PRESERVED while the command body is inserted (file-guard append-under, not replace).
# Reverts-as: the RR3 replace-in-place code would DROP the prose line (grep -F empty).
mx_prose="$WORKDIR/mx-prose.md"
printf '## Validation\n\nRun the tests manually before pushing.\n' > "$mx_prose"
mx_pv="$(hivemind_guard_validation_section "$mx_prose" "$FG_VALIDATION_BODY")"
[ "$mx_pv" = "added" ] || { mx_fail=1; echo "  matrix-4 FAIL: prose-only stub status=$mx_pv (want added)"; }
[ "$(grep -cF 'Run the tests manually before pushing.' "$mx_prose")" = "1" ] || { mx_fail=1; echo "  matrix-4 FAIL: existing prose dropped (data loss)"; }

# Matrix clause (5) [RR4]: WRONG-TYPED-CONTAINER-NO-CRASH — a wrong-typed container (enabledPlugins as
# a string) collapses to its canonical empty via canon_obj BEFORE any predicate runs, so the merge
# returns status `ok` and seeds the required key (settings-merge shape-normalization at one chokepoint).
# Reverts-as: without canon_obj/canon_arr the wrong-typed container aborts jq (rc=5) → empty `.status`.
mx_wt="$(hivemind_settings_merge '{"enabledPlugins":"oops"}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
mx_wt_status="$(printf '%s' "$mx_wt" | jq -r '.status')"
mx_wt_value="$(printf '%s' "$mx_wt" | jq -r '.settings.enabledPlugins["hivemind@brenpike"]')"
[ "$mx_wt_status" = "ok" ] || { mx_fail=1; echo "  matrix-5 FAIL: wrong-typed container status=$mx_wt_status (want ok)"; }
[ "$mx_wt_value" = "true" ] || { mx_fail=1; echo "  matrix-5 FAIL: required key not seeded over canonical empty (value=$mx_wt_value)"; }

# Matrix clause (6) [SWEEP-STEP-004]: VALUE-EQUALITY — enabledPlugins["hivemind@brenpike"] present
# but == false is classified `added` (NOT `already present`) AND the build CORRECTS it to true. This
# is the value-not-presence predicate (enabled_true), not has()-presence.
# Reverts-as: a presence-only has() predicate would report `already present` and leave the value false.
mx_ve="$(hivemind_settings_merge '{"enabledPlugins":{"hivemind@brenpike":false}}' 'hivemind:overlord' 'no' 'no' 'no' 'no')"
mx_ve_class="$(printf '%s' "$mx_ve" | jq -r '.keys["enabledPlugins.hivemind@brenpike"]')"
mx_ve_value="$(printf '%s' "$mx_ve" | jq -r '.settings.enabledPlugins["hivemind@brenpike"]')"
[ "$mx_ve_class" = "added" ] || { mx_fail=1; echo "  matrix-6 FAIL: present-false enabledPlugin class=$mx_ve_class (want added)"; }
[ "$mx_ve_value" = "true" ] || { mx_fail=1; echo "  matrix-6 FAIL: present-false enabledPlugin not corrected (value=$mx_ve_value, want true)"; }

# Matrix clause (7) [JSON-stream sweep, STEP-005]: MULTI-DOCUMENT-STREAM REJECTION across BOTH sites
# sharing the json-normalize.sh single-document primitive. A STREAM of two concatenated top-level
# objects (`{"a":1}{"b":2}`) is NOT a single object, so BOTH precheck sites must take their fail-closed
# path together: settings-merge → status `malformed` (settings null); claude-mem → `skipped (malformed
# json)` with the target file BYTE-UNCHANGED (binary present, so the skip is the stream gate, not a
# missing binary). Reverts-as: a `type=="object"` precheck on EITHER site STREAMS both docs and exits 0
# on the last → settings-merge crashes its `--argjson` build (status no longer `malformed`) and
# claude-mem resolves+writes (status `set`, bytes change). Reverting EITHER single-doc gate trips this
# one matrix case.
mx_sm_stream="$(hivemind_settings_merge '{"a":1}{"b":2}' 'hivemind:overlord' 'no' 'no' 'no' 'yes')"
mx_sm_stream_status="$(printf '%s' "$mx_sm_stream" | jq -r '.status')"
[ "$mx_sm_stream_status" = "malformed" ] || { mx_fail=1; echo "  matrix-7 FAIL: settings-merge stream status=$mx_sm_stream_status (want malformed)"; }
mx_stream_home="$(cm_setup_home mx-claude-mem-stream)"
mx_stream_file="$mx_stream_home/.claude-mem/settings.json"
printf '{"a":1}{"b":2}' > "$mx_stream_file"
mx_stream_before="$(cat "$mx_stream_file")"
mx_stream_status="$(PATH="$CM_CLEAN_PATH" hivemind_claude_mem_provision_path "$mx_stream_file" "$mx_stream_home")"
[ "$mx_stream_status" = "skipped (malformed json)" ] || { mx_fail=1; echo "  matrix-7 FAIL: claude-mem stream status=$mx_stream_status (want skipped malformed json)"; }
[ "$mx_stream_before" = "$(cat "$mx_stream_file")" ] || { mx_fail=1; echo "  matrix-7 FAIL: claude-mem stream file was clobbered"; }

# Matrix clause (8) [#355 STEP-002]: ELEMENT-POSITION TOTALITY — the element-position extension of clause
# (5). Clause (5) proves a wrong-typed CONTAINER key collapses to its canonical empty before any predicate
# runs; this clause proves the SAME law reaches ELEMENT positions, where a non-conforming element reads as
# the canonical empty object (canon_elem) and is therefore never migrated, never counted present, and always
# preserved. Swept across jq's CLOSED type domain at BOTH element positions the merge reads — `SubagentStart[]`
# and `SubagentStart[].hooks[]` — so the lock covers the whole element-access surface, not sampled shapes.
# Reverts-as: dropping canon_elem from any one element access aborts the jq program on a non-object element
# (rc=5) → `.status` reads empty, the element vanishes with the output, and no canonical entry is appended.
for mx_elem_pos in outer inner; do
  for mx_elem_val in 'null' 'true' '1' '"s"' '[]' '["x"]' '{}' '{"a":1}'; do
    if [ "$mx_elem_pos" = "outer" ]; then
      mx_elem_pre="$(jq -nc --argjson v "$mx_elem_val" '{hooks:{SubagentStart:[$v]}}')"
      mx_elem_path='.settings.hooks.SubagentStart[0]'
    else
      mx_elem_pre="$(jq -nc --argjson v "$mx_elem_val" '{hooks:{SubagentStart:[{hooks:[$v]}]}}')"
      mx_elem_path='.settings.hooks.SubagentStart[0].hooks[0]'
    fi
    mx_elem_res="$(hivemind_settings_merge "$mx_elem_pre" 'hivemind:overlord' 'yes' 'no' 'no' 'no')"
    mx_elem_status="$(printf '%s' "$mx_elem_res" | jq -r '.status')"
    [ "$mx_elem_status" = "ok" ] || { mx_fail=1; echo "  matrix-8 FAIL: $mx_elem_pos element $mx_elem_val status=$mx_elem_status (want ok)"; }
    [ "$(printf '%s' "$mx_elem_res" | jq -cS "$mx_elem_path")" = "$(jq -ncS --argjson v "$mx_elem_val" '$v')" ] || { mx_fail=1; echo "  matrix-8 FAIL: $mx_elem_pos element $mx_elem_val not preserved byte-identical"; }
    [ "$(printf '%s' "$mx_elem_res" | jq -r '.settings.hooks.SubagentStart[1].hooks[0].command')" = "$SM_HOOK_CANON" ] || { mx_fail=1; echo "  matrix-8 FAIL: canonical entry not appended past $mx_elem_pos element $mx_elem_val"; }
  done
done

if [ "$mx_fail" -eq 0 ]; then
  pass "matrix:root-cluster-class-lock" "all eight merge-predicate-gap site fixes hold (heading-only append + agent:\"\"→added + non-string CLAUDE_CODE_PATH never clobbered + prose-preservation append-under + wrong-typed-container normalizes to ok + present-false enabledPlugin value-equality corrected to true + multi-doc-stream rejected by both settings-merge[malformed] and claude-mem[skipped malformed, byte-unchanged] + every jq type at both hook ELEMENT positions stays ok with the element preserved and the canonical entry appended)"
else
  failed "matrix:root-cluster-class-lock" "a seed-hive merge-predicate-gap site fix regressed (see matrix-N FAIL lines above)"
fi

# ── Section 17: graphql-response.sh — fail-closed GraphQL envelope validator (#393) ──
echo ''
echo '=== graphql-response.sh: hivemind_graphql_response_check / hivemind_graphql_pages_check (#393) ==='
#
# Every case asserts the full (return code, stdout) pair: success is `rc=0 out=` (prints nothing),
# failure is `rc=1 out=<token>` with exactly one token. Token precedence under test:
# empty-body > malformed > errors > missing-data.

# gr_probe <fn> <body>: run one validator and render its outcome as `rc=<n> out=<stdout>`.
gr_probe() {
  local probe_fn="$1" probe_body="$2" probe_out probe_rc
  probe_out="$("$probe_fn" "$probe_body")"
  probe_rc=$?
  printf 'rc=%s out=%s' "$probe_rc" "$probe_out"
}

# gr_case <case> <fn> <body> <expected-outcome>
gr_case() {
  assert_eq "$1" "$4" "$(gr_probe "$2" "$3")" "$2"
}

# 17a: single-body mode.
gr_case "gqlresp:single-clean"              hivemind_graphql_response_check '{"data":{"viewer":{"login":"x"}}}' 'rc=0 out='
gr_case "gqlresp:single-errors-empty-array" hivemind_graphql_response_check '{"errors":[],"data":{}}'           'rc=0 out='
gr_case "gqlresp:single-errors-null"        hivemind_graphql_response_check '{"errors":null,"data":{}}'         'rc=0 out='
gr_case "gqlresp:single-empty-string"       hivemind_graphql_response_check ''                                  'rc=1 out=empty-body'
gr_case "gqlresp:single-blank-crlf"         hivemind_graphql_response_check $'  \r\n'                           'rc=1 out=empty-body'
gr_case "gqlresp:single-not-json"           hivemind_graphql_response_check 'not json'                          'rc=1 out=malformed'
gr_case "gqlresp:single-array-value"        hivemind_graphql_response_check '[1]'                               'rc=1 out=malformed'
gr_case "gqlresp:single-two-values"         hivemind_graphql_response_check '{"a":1}{"b":2}'                    'rc=1 out=malformed'
gr_case "gqlresp:single-errors-message"     hivemind_graphql_response_check '{"errors":[{"message":"Could not resolve to a PullRequest"}],"data":{}}' 'rc=1 out=errors'
gr_case "gqlresp:single-errors-empty-obj"   hivemind_graphql_response_check '{"errors":[{}],"data":{}}'         'rc=1 out=errors'
gr_case "gqlresp:single-errors-object"      hivemind_graphql_response_check '{"errors":{},"data":{}}'           'rc=1 out=errors'
gr_case "gqlresp:single-errors-string"      hivemind_graphql_response_check '{"errors":"boom","data":{}}'       'rc=1 out=errors'
gr_case "gqlresp:single-errors-false"       hivemind_graphql_response_check '{"errors":false,"data":{}}'        'rc=1 out=errors'
gr_case "gqlresp:single-errors-zero"        hivemind_graphql_response_check '{"errors":0,"data":{}}'            'rc=1 out=errors'
gr_case "gqlresp:single-errors-null-elem"   hivemind_graphql_response_check '{"errors":[null],"data":{}}'       'rc=1 out=errors'
gr_case "gqlresp:single-data-null"          hivemind_graphql_response_check '{"data":null}'                     'rc=1 out=missing-data'
gr_case "gqlresp:single-data-absent"        hivemind_graphql_response_check '{}'                                'rc=1 out=missing-data'
gr_case "gqlresp:single-data-array"         hivemind_graphql_response_check '{"data":[]}'                       'rc=1 out=missing-data'
gr_case "gqlresp:single-errors-over-data"   hivemind_graphql_response_check '{"errors":[{"message":"x"}],"data":null}' 'rc=1 out=errors'

# 17b: paginated stream mode (pages concatenated with no separator, as `gh api graphql --paginate`
# prints them without --jq / --slurp).
gr_case "gqlresp:pages-two-clean"           hivemind_graphql_pages_check '{"data":{"n":1}}{"data":{"n":2}}'    'rc=0 out='
gr_case "gqlresp:pages-clean-then-errors"   hivemind_graphql_pages_check '{"data":{"n":1}}{"errors":[{"message":"x"}],"data":{"n":2}}' 'rc=1 out=errors'
gr_case "gqlresp:pages-errors-then-clean"   hivemind_graphql_pages_check '{"errors":[{"message":"x"}],"data":{"n":1}}{"data":{"n":2}}' 'rc=1 out=errors'
gr_case "gqlresp:pages-clean-then-array"    hivemind_graphql_pages_check '{"data":{"n":1}}[1]'                 'rc=1 out=malformed'
gr_case "gqlresp:pages-empty"               hivemind_graphql_pages_check ''                                    'rc=1 out=empty-body'
gr_case "gqlresp:pages-one-clean"           hivemind_graphql_pages_check '{"data":{"n":1}}'                    'rc=0 out='
gr_case "gqlresp:pages-clean-then-data-null" hivemind_graphql_pages_check '{"data":{"n":1}}{"data":null}'      'rc=1 out=missing-data'
gr_case "gqlresp:pages-truncated"           hivemind_graphql_pages_check '{"data":{"n":1}}{"data":{"n"'        'rc=1 out=malformed'

# 17c: purity. A sourced validator must `return`, never `exit`: the subshell reaches its trailing
# printf only when the failing call returned control.
gr_subshell_out="$( (hivemind_graphql_response_check 'not json' >/dev/null; printf 'returned:%s' "$?") )"
assert_eq "gqlresp:purity-return-not-exit" "returned:1" "$gr_subshell_out" \
  "failing hivemind_graphql_response_check returns 1 to its caller instead of exiting"
gr_pages_subshell_out="$( (hivemind_graphql_pages_check '' >/dev/null; printf 'returned:%s' "$?") )"
assert_eq "gqlresp:purity-pages-return-not-exit" "returned:1" "$gr_pages_subshell_out" \
  "failing hivemind_graphql_pages_check returns 1 to its caller instead of exiting"

# Success prints nothing on either stream; failure prints only its one token (jq diagnostics stay off
# the caller's stderr).
assert_eq "gqlresp:purity-success-silent" "" "$(hivemind_graphql_response_check '{"data":{}}' 2>&1)" \
  "successful single check writes nothing to stdout or stderr"
assert_eq "gqlresp:purity-pages-success-silent" "" "$(hivemind_graphql_pages_check '{"data":{}}{"data":{}}' 2>&1)" \
  "successful pages check writes nothing to stdout or stderr"
assert_eq "gqlresp:purity-failure-one-token" "malformed" "$(hivemind_graphql_response_check '{"data":' 2>&1)" \
  "failing check writes exactly its token and no jq diagnostic"

# Caller variables that share the validator's internal local names are left untouched.
check_mode="caller-mode"
response_body="caller-body"
check_token="caller-token"
envelope_program="caller-program"
hivemind_graphql_response_check '{"errors":[{}],"data":{}}' >/dev/null
hivemind_graphql_pages_check '{"data":{}}{"data":{}}' >/dev/null
assert_eq "gqlresp:purity-caller-vars-unchanged" "caller-mode|caller-body|caller-token|caller-program" \
  "$check_mode|$response_body|$check_token|$envelope_program" \
  "validator locals do not leak into or overwrite the caller's variables"
unset check_mode response_body check_token envelope_program

# ── Section 18: review-loop GraphQL check closure (#393) ────────────────────────
echo ''
echo '=== review-loop GraphQL check closure: every `gh api graphql` script uses graphql-response.sh (#393) ==='
#
# A review-loop script is DISCOVERED when a non-comment line contains `gh api graphql`. Every
# discovered script must (a) source a path ending in `_shared/graphql-response.sh"` on a non-comment
# line and (b) call hivemind_graphql_response_check or hivemind_graphql_pages_check on a non-comment
# line. The same predicate runs over the canaries (18b) and the real glob (18c), so the canaries prove
# the real check flags an unchecked script and ignores a comment-only mention.
#
# RESIDUAL: this closure is file-level only. It proves each discovered script sources the lib and
# calls a validator somewhere, not that every `gh api graphql` call site in that script routes its
# body through the validator; per-call-site correctness is covered by the consumer behavior suites.

# gqlclosure_classify_file <path>: print one verdict for a script: `undiscovered`, `checked`,
# `missing-source`, `missing-call`, `missing-source+missing-call`, or `unreadable` (returns 1).
gqlclosure_classify_file() {
  local script_path="$1" code_lines grep_rc verdict_parts=""
  code_lines="$(grep -v '^[[:space:]]*#' "$script_path" 2>/dev/null)"
  grep_rc=$?
  if [ "$grep_rc" -gt 1 ]; then
    printf 'unreadable'
    return 1
  fi
  if ! grep -q 'gh api graphql' <<<"$code_lines"; then
    printf 'undiscovered'
    return 0
  fi
  grep -Eq '^[[:space:]]*(\.|source)[[:space:]]+"[^"]*_shared/graphql-response\.sh"' <<<"$code_lines" \
    || verdict_parts="missing-source"
  grep -Eq 'hivemind_graphql_(response|pages)_check([^A-Za-z0-9_]|$)' <<<"$code_lines" \
    || verdict_parts="${verdict_parts:+$verdict_parts+}missing-call"
  printf '%s' "${verdict_parts:-checked}"
}

# gqlclosure_scan_scripts <path>...: print `<basename> <verdict>` per discovered script, one per line.
gqlclosure_scan_scripts() {
  local script_path script_verdict
  for script_path in "$@"; do
    [ -f "$script_path" ] || { printf '%s unreadable\n' "${script_path##*/}"; continue; }
    script_verdict="$(gqlclosure_classify_file "$script_path")"
    [ "$script_verdict" = "undiscovered" ] && continue
    printf '%s %s\n' "${script_path##*/}" "$script_verdict"
  done
}

# 18a: canary fixtures.
gqlclosure_canary_dir="$WORKDIR/gqlclosure-canaries"
mkdir -p "$gqlclosure_canary_dir"
cat > "$gqlclosure_canary_dir/a-checked.sh" <<'EOF'
#!/usr/bin/env bash
. "$SCRIPT_DIR/../../_shared/graphql-response.sh" || exit 1
body="$(gh api graphql -f query=q)"
hivemind_graphql_response_check "$body" >/dev/null || exit 1
EOF
cat > "$gqlclosure_canary_dir/b-unchecked.sh" <<'EOF'
#!/usr/bin/env bash
body="$(gh api graphql -f query=q)"
printf '%s\n' "$body"
EOF
cat > "$gqlclosure_canary_dir/c-comment-only.sh" <<'EOF'
#!/usr/bin/env bash
# This script never runs `gh api graphql`; it only mentions it here.
  # gh api graphql --paginate (indented comment mention)
gh api repos/o/r/pulls
EOF
cat > "$gqlclosure_canary_dir/d-source-only.sh" <<'EOF'
#!/usr/bin/env bash
source "$SCRIPT_DIR/../../_shared/graphql-response.sh"
gh api graphql -f query=q
EOF
cat > "$gqlclosure_canary_dir/e-call-only.sh" <<'EOF'
#!/usr/bin/env bash
[ -f "$SCRIPT_DIR/../../_shared/graphql-response.sh" ] || exit 1
pages="$(gh api graphql --paginate -f query=q)"
hivemind_graphql_pages_check "$pages" >/dev/null || exit 1
EOF
cat > "$gqlclosure_canary_dir/f-checked-in-comments-only.sh" <<'EOF'
#!/usr/bin/env bash
# . "$SCRIPT_DIR/../../_shared/graphql-response.sh"
body="$(gh api graphql -f query=q)"
  # hivemind_graphql_response_check "$body"
EOF

# 18b: the predicate over the canaries. A checked script is clean, an unchecked script is flagged
# (each missing half independently), and a comment-only mention is not discovered. A `[ -f ]` probe
# of the lib path is not a source line, and source/call text inside comments satisfies nothing.
assert_eq "gqlclosure:canary-checked" "checked" \
  "$(gqlclosure_classify_file "$gqlclosure_canary_dir/a-checked.sh")"
assert_eq "gqlclosure:canary-unchecked" "missing-source+missing-call" \
  "$(gqlclosure_classify_file "$gqlclosure_canary_dir/b-unchecked.sh")"
assert_eq "gqlclosure:canary-comment-only-undiscovered" "undiscovered" \
  "$(gqlclosure_classify_file "$gqlclosure_canary_dir/c-comment-only.sh")"
assert_eq "gqlclosure:canary-source-only" "missing-call" \
  "$(gqlclosure_classify_file "$gqlclosure_canary_dir/d-source-only.sh")"
assert_eq "gqlclosure:canary-file-probe-is-not-source" "missing-source" \
  "$(gqlclosure_classify_file "$gqlclosure_canary_dir/e-call-only.sh")"
assert_eq "gqlclosure:canary-comment-source-and-call" "missing-source+missing-call" \
  "$(gqlclosure_classify_file "$gqlclosure_canary_dir/f-checked-in-comments-only.sh")"
assert_eq "gqlclosure:canary-unreadable" "unreadable rc=1" \
  "$(gqlclosure_classify_file "$gqlclosure_canary_dir/absent.sh"; printf ' rc=%s' "$?")"
assert_eq "gqlclosure:canary-scan" \
  "a-checked.sh checked|b-unchecked.sh missing-source+missing-call|d-source-only.sh missing-call|e-call-only.sh missing-source|f-checked-in-comments-only.sh missing-source+missing-call" \
  "$(gqlclosure_scan_scripts "$gqlclosure_canary_dir"/*.sh | paste -sd '|' -)" \
  "scan lists every discovered canary with its verdict and skips the comment-only one"

# 18c: the same scan over the real review-loop scripts.
gqlclosure_report="$(gqlclosure_scan_scripts "$REPO_ROOT"/plugin/skills/github-review-loop/scripts/*.sh)"
gqlclosure_discovered="$(cut -d' ' -f1 <<<"$gqlclosure_report" | paste -sd ' ' -)"
echo "INFO [gqlclosure:real-discovered] $gqlclosure_discovered"
if [ -n "$gqlclosure_report" ]; then
  pass "gqlclosure:real-non-vacuous" "discovered set is non-empty"
else
  failed "gqlclosure:real-non-vacuous" "no review-loop script discovered calling gh api graphql (glob or predicate broke)"
fi
for gqlclosure_expected in fetch-normalize.sh pr-change-detect-poll.sh prefilter.sh react-marker.sh reply-resolve.sh; do
  if grep -q "^$gqlclosure_expected " <<<"$gqlclosure_report"; then
    pass "gqlclosure:real-discovers-$gqlclosure_expected" "discovered as a gh api graphql caller"
  else
    failed "gqlclosure:real-discovers-$gqlclosure_expected" "not discovered (actual set: '$gqlclosure_discovered')"
  fi
done
gqlclosure_violations="$(grep -v ' checked$' <<<"$gqlclosure_report" | paste -sd '|' -)"
assert_eq "gqlclosure:real-all-checked" "" "$gqlclosure_violations" \
  "every discovered review-loop script sources graphql-response.sh and calls a validator"
unset gqlclosure_canary_dir gqlclosure_report gqlclosure_discovered gqlclosure_expected gqlclosure_violations

# ── Summary ─────────────────────────────────────────────────────────────────────
echo ''
echo '=== Summary ==='
echo "Shared-lib unit tests: $PASS_COUNT passed, $FAIL_COUNT failed."
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
