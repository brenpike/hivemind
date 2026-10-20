#!/usr/bin/env bash
#
# Integration runner for the seed-hive entrypoint (issue #247, STEP-005).
#
# Drives plugin/skills/seed-hive/scripts/seed-hive.sh end-to-end against DISPOSABLE tmp project
# roots, with a tmp HOME so companion detection + claude-mem provisioning are hermetic (the
# developer's real ~/.claude / ~/.claude-mem are never read or written). CI-runnable with ONLY
# jq + git present (no tmux / claude / gh): a fake `claude` binary is scaffolded in the tmp HOME
# for the claude-mem path case. SKIPs cleanly when jq or git is missing.
#
# Mirrors tools/test_brood_compat.sh / test_shared_libs.sh conventions: pass/fail counters,
# exit-nonzero-on-failure, all writes inside a disposable tmpdir removed on EXIT.
#
# LOCKED INVARIANTS:
#   1. clean seed (all companions no, allowlist yes) → the FULL Output block verbatim.
#   2. idempotent FULL re-run → all items already present/already documented, settings
#      byte-stable, status complete, target_file unchanged.
#   3. settings-merge agent conflict → status blocked, no overwrite.
#   4. all-companions-no path → correct reduced Output (caveman/claude_mem/codex skipped).
#   5. detect phase reports companion facts (manifest installed/absent, cache fallback, none).
#   6. headless-resolved inputs (inputs file fully specifies yes/no) drive a complete seed.
#   7. caveman SubagentStart hook entry is EXEC (argv) FORM — an UNQUOTED anchored `command`
#      (`${CLAUDE_PROJECT_DIR}/<hook_rel>`) plus `args: []`, the key that selects exec form —
#      and PROVABLY resolves to the scaffolded hook file (drift guard). Both authored SHELL-form
#      pre-states (the legacy bare-relative command and the unreleased quoted-anchored one)
#      migrate IN PLACE to exec form — reported `added`, exactly one entry, canonical command,
#      byte-stable on re-run.
#   8. apply EXITS 0 and emits the Output block even on a NON-CONFORMING SubagentStart pre-state
#      (a bare string element) — the documented SKILL.md contract that a status is a REPORTED
#      outcome, never a script error; the non-conforming element is preserved and the canonical
#      entry appended beside it.
#
# Usage:
#   ./tools/test_seed_hive.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ENTRYPOINT="$REPO_ROOT/plugin/skills/seed-hive/scripts/seed-hive.sh"

[ -f "$ENTRYPOINT" ] || { echo "FAIL: entrypoint missing: $ENTRYPOINT" >&2; exit 2; }

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq is required to run this suite"  >&2; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git is required to run this suite" >&2; exit 0; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

assert_eq() {
  local case_name="$1" expected="$2" actual="$3" msg="${4:-}"
  if [ "$expected" = "$actual" ]; then
    pass "$case_name" "${msg:+$msg }(== '$expected')"
  else
    failed "$case_name" "${msg:+$msg }expected '$expected', got '$actual'"
  fi
}

# assert_contains <case> <needle> <haystack> [msg]
assert_contains() {
  local case_name="$1" needle="$2" haystack="$3" msg="${4:-}"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    pass "$case_name" "${msg:+$msg }(contains '$needle')"
  else
    failed "$case_name" "${msg:+$msg }missing '$needle'"
  fi
}

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-seed-hive.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# new_project <name> — create a disposable git project root with its own tmp HOME under it.
# Echoes the project root path. Sets HOME/PATH per-case via the returned root's fakehome.
new_project() {
  local name="$1"
  local root="$WORKDIR/$name"
  mkdir -p "$root/fakehome"
  ( cd "$root" && git init -q . )
  printf '%s\n' "$root"
}

# run_apply <root> <inputs_json_string> — run the apply phase with HOME pinned to <root>/fakehome.
# Echoes combined stdout.
# cwd is pinned to <root> because apply's inputs-containment guard resolves the checkout via
# `git rev-parse --show-toplevel` from the CURRENT directory; without the cd the guard would compare
# the tmp inputs path against the runner's own checkout and refuse to read it.
run_apply() {
  local root="$1" inputs="$2"
  printf '%s' "$inputs" > "$root/inputs.json"
  ( cd "$root" && HOME="$root/fakehome" bash "$ENTRYPOINT" apply "$root/inputs.json" )
}

# run_detect <root> — run the detect phase with HOME pinned to <root>/fakehome.
run_detect() {
  local root="$1"
  HOME="$root/fakehome" bash "$ENTRYPOINT" detect "$root"
}

# ── Case 1: clean seed — full Output block verbatim ─────────────────────────────
echo '=== Case 1: clean seed (all companions no, allowlist yes) — full Output verbatim ==='
ROOT="$(new_project clean)"
INPUTS="$(jq -nc --arg r "$ROOT" '{
  project_root: $r, agent_target: "hivemind:overlord",
  caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "yes",
  companions: {
    "caveman@caveman":       {detected:"absent", source:"none", resolved:"no", via:"explicit-input"},
    "claude-mem@thedotmack": {detected:"absent", source:"none", resolved:"no", via:"explicit-input"},
    "codex@openai-codex":    {detected:"absent", source:"none", resolved:"no", via:"explicit-input"}
  }
}')"
OUT="$(run_apply "$ROOT" "$INPUTS")"
RC=$?
assert_eq "clean:exit" "0" "$RC" "apply exit code"
assert_contains "clean:status"      "status: complete" "$OUT"
assert_contains "clean:project"     "project_root:" "$OUT"
assert_contains "clean:target"      "- .claude/settings.json: created" "$OUT"
assert_contains "clean:gitignore"   "- .gitignore: created" "$OUT"
assert_contains "clean:envrc"       "- .envrc: skipped (caveman not enabled)" "$OUT"
assert_contains "clean:hookfile"    "- .claude/hooks/caveman-ultra-subagent.sh: skipped (caveman not enabled)" "$OUT"
assert_contains "clean:hookwire"    "- hooks.SubagentStart in settings.json: skipped (caveman not enabled)" "$OUT"
assert_contains "clean:companion"   "- caveman@caveman: detected: absent, source: none, resolved: no, via: explicit-input" "$OUT"
assert_contains "clean:memskip"     "- ~/.claude-mem/settings.json CLAUDE_CODE_PATH: skipped (claude_mem not enabled)" "$OUT"
assert_contains "clean:keyhive"     '- enabledPlugins["hivemind@brenpike"]: added' "$OUT"
assert_contains "clean:keyagent"    "- agent: added" "$OUT"
assert_contains "clean:keycave"     '- enabledPlugins["caveman@caveman"]: resolved no' "$OUT"
assert_contains "clean:keypcfg"     '- pluginConfigs["caveman@caveman"]: resolved no' "$OUT"
assert_contains "clean:allow1"      "- Bash(echo *): added" "$OUT"
assert_contains "clean:allowseed"   "- Edit(.hivemind/seed-inputs-*.json): added" "$OUT"
assert_contains "clean:allowmolt"   "- Edit(.hivemind/molt-inputs-*.json): added" "$OUT"
assert_contains "clean:allowlast"   "- Edit(.hivemind/pr-inputs-*.json): added" "$OUT"
assert_contains "clean:context"     "- creep-spread: invoked" "$OUT"
assert_contains "clean:testcmd"     "- repo-root CLAUDE.md ## Validation: none detected (recommend manual)" "$OUT"
assert_contains "clean:conflicts"   "conflicts:" "$OUT"
assert_contains "clean:noconflict"  "- None" "$OUT"
# settings.json actually written + parseable, agent + hivemind key present.
assert_eq "clean:settings.agent" "hivemind:overlord" \
  "$(jq -r '.agent' "$ROOT/.claude/settings.json" 2>/dev/null)" "settings agent"
assert_eq "clean:settings.hive" "true" \
  "$(jq -r '.enabledPlugins["hivemind@brenpike"]' "$ROOT/.claude/settings.json" 2>/dev/null)" "settings hive key"

# ── Case 2: idempotent full re-run — byte-stable, all already present ────────────
echo '=== Case 2: idempotent full re-run — byte-stable, already present, status complete ==='
SETTINGS_BEFORE="$(cat "$ROOT/.claude/settings.json")"
OUT2="$(run_apply "$ROOT" "$INPUTS")"
assert_eq "idem:exit" "0" "$?" "re-run exit code"
assert_contains "idem:status"     "status: complete" "$OUT2"
assert_contains "idem:target"     "- .claude/settings.json: unchanged" "$OUT2"
assert_contains "idem:gitignore"  "- .gitignore: already present" "$OUT2"
assert_contains "idem:keyhive"    '- enabledPlugins["hivemind@brenpike"]: already present' "$OUT2"
assert_contains "idem:keyagent"   "- agent: already present" "$OUT2"
assert_contains "idem:allow"      "- Bash(echo *): already present" "$OUT2"
assert_eq "idem:byte-stable" "$SETTINGS_BEFORE" "$(cat "$ROOT/.claude/settings.json")" "settings byte-stable across re-run"

# ── Case 3: settings-merge agent conflict → blocked, no overwrite ────────────────
echo '=== Case 3: agent conflict — status blocked, no overwrite ==='
ROOT3="$(new_project conflict)"
mkdir -p "$ROOT3/.claude"
printf '{"agent":"someone:else"}\n' > "$ROOT3/.claude/settings.json"
BEFORE3="$(cat "$ROOT3/.claude/settings.json")"
INPUTS3="$(jq -nc --arg r "$ROOT3" '{
  project_root: $r, caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT3="$(run_apply "$ROOT3" "$INPUTS3")"
assert_eq "conflict:exit" "0" "$?" "blocked is exit 0 (reported outcome)"
assert_contains "conflict:status"   "status: blocked" "$OUT3"
# RR-STEP-002 rewrote the blocked terminal to the Worker Report — Blocked schema: the old
# `## Output` `target_file:` `- .claude/settings.json: unchanged` line is GONE. Key the
# "no settings write" assertion on the schema-valid blocker/impact fields instead. Non-vacuous:
# if the blocked emitter regressed to the old `## Output` shape, these fields would be absent.
assert_contains "conflict:blocker"  "blocker: .claude/settings.json already sets a different agent; overwrite needs explicit user approval" "$OUT3"
assert_contains "conflict:impact"   "impact: settings not written; no project files mutated (settings.json byte-unchanged)" "$OUT3"
assert_contains "conflict:conflict" "- agent: someone:else vs hivemind:overlord" "$OUT3"
assert_eq "conflict:no-overwrite" "$BEFORE3" "$(cat "$ROOT3/.claude/settings.json")" "settings byte-unchanged on conflict"
# (iii) BLOCKED-OUTPUT SCHEMA CONFORMANCE: the blocked Output carries ONLY schema-valid fields and
# NONE of the out-of-schema `## Output` tokens the prior emitter produced. Non-vacuous: each token
# below was emitted by the pre-RR-002 blocked path; their absence proves the rewrite landed.
assert_contains "conflict:schema-status" "status: blocked" "$OUT3"
assert_contains "conflict:schema-stage"  "stage: implementation" "$OUT3"
assert_contains "conflict:schema-retry"  "retry: not attempted" "$OUT3"
for forbidden in "not invoked" "not recorded" "unchanged (settings not written)" ": unchanged"; do
  if printf '%s' "$OUT3" | grep -qF -- "$forbidden"; then
    failed "conflict:no-offschema" "blocked Output still emits out-of-schema token '$forbidden'"
  else
    pass "conflict:no-offschema" "blocked Output free of out-of-schema token '$forbidden'"
  fi
done

# ── Case 3c: agent conflict + approval → overwrite, complete, agent = target ──────
echo '=== Case 3c: agent conflict + agent_conflict_approved=yes — overwrite, complete ==='
ROOT3C="$(new_project approved)"
mkdir -p "$ROOT3C/.claude"
printf '{"agent":"someone:else"}\n' > "$ROOT3C/.claude/settings.json"
INPUTS3C="$(jq -nc --arg r "$ROOT3C" '{
  project_root: $r, caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "yes",
  agent_conflict_approved: "yes" }')"
OUT3C="$(run_apply "$ROOT3C" "$INPUTS3C")"
assert_eq "approve:exit" "0" "$?" "approved overwrite exit"
# Non-vacuous: without the entrypoint threading agent_conflict_approved into the merge, this would
# stay blocked (status blocked) and the written agent would remain someone:else.
assert_contains "approve:status"  "status: complete" "$OUT3C"
assert_contains "approve:target"  "- .claude/settings.json: updated" "$OUT3C"
# Finding-1 (PR #297): the approved-overwrite path classifies the agent `overwritten`, which flows
# through emit_keys_block into keys_applied. Assert that schema-valid token appears in the Output.
# Non-vacuous: pre-fix the `## Output` agent enum lacked `overwritten`, so this legitimate token
# was out-of-schema; the merge already emits it (settings-merge.sh agent classifier).
assert_contains "approve:key-overwritten" "- agent: overwritten" "$OUT3C"
assert_eq "approve:settings.agent" "hivemind:overlord" \
  "$(jq -r '.agent' "$ROOT3C/.claude/settings.json" 2>/dev/null)" "approved conflict overwrites agent to target"

# ── Case 3b: malformed existing settings → blocked, byte-unchanged ───────────────
echo '=== Case 3b: malformed existing settings — blocked, byte-unchanged ==='
ROOT3B="$(new_project malformed)"
mkdir -p "$ROOT3B/.claude"
printf 'this is { not json\n' > "$ROOT3B/.claude/settings.json"
BEFORE3B="$(cat "$ROOT3B/.claude/settings.json")"
INPUTS3B="$(jq -nc --arg r "$ROOT3B" '{ project_root: $r, caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT3B="$(run_apply "$ROOT3B" "$INPUTS3B")"
assert_contains "malformed:status" "status: blocked" "$OUT3B"
assert_eq "malformed:byte-unchanged" "$BEFORE3B" "$(cat "$ROOT3B/.claude/settings.json")" "malformed file untouched"

# ── Case 3n: NUL-bearing existing settings → blocked, byte-unchanged (Class A) ────
# A literal NUL inside otherwise-valid JSON. bash $(cat ...) silently strips the NUL, so the
# pre-fix in-variable single-object check passed and the file got clobbered to a stripped 14-byte
# `{"agent":null}` while apply reported complete. The on-disk validate routes to blocked instead.
# NOTE: $(cat) strips NUL, so the fixture is preserved as a byte-exact reference copy and the
# untouched assertion uses cmp (not a $()-captured string) and wc -c (must NOT be the 14-byte
# stripped form). Both assertions FAIL pre-fix (status complete + clobbered), PASS post-fix.
echo '=== Case 3n: NUL-bearing existing settings — blocked, byte-unchanged ==='
ROOT3N="$(new_project nul)"
mkdir -p "$ROOT3N/.claude"
printf '{"agent":null\000}' > "$ROOT3N/.claude/settings.json"
cp "$ROOT3N/.claude/settings.json" "$ROOT3N/settings.fixture"
BYTES3N_BEFORE="$(wc -c < "$ROOT3N/.claude/settings.json")"
INPUTS3N="$(jq -nc --arg r "$ROOT3N" '{ project_root: $r, caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT3N="$(run_apply "$ROOT3N" "$INPUTS3N")"
# (a) STRUCTURED status field reports the blocked/malformed path (not a banner substring).
assert_contains "nul:status"  "status: blocked" "$OUT3N"
assert_contains "nul:blocker" "blocker: .claude/settings.json is not valid JSON; refusing to overwrite without user approval" "$OUT3N"
# (b) settings.json is BYTE-UNCHANGED vs the original NUL-bearing fixture (not clobbered to the
# 14-byte stripped `{"agent":null}` form).
if cmp -s "$ROOT3N/settings.fixture" "$ROOT3N/.claude/settings.json"; then
  pass "nul:byte-unchanged" "NUL-bearing settings.json byte-exact vs fixture"
else
  failed "nul:byte-unchanged" "NUL-bearing settings.json was mutated (expected byte-exact fixture)"
fi
assert_eq "nul:byte-count" "$BYTES3N_BEFORE" "$(wc -c < "$ROOT3N/.claude/settings.json")" "settings.json byte-count unchanged"

# ── Case 3e: EMPTY existing settings (zero-byte) → seed defaults, status complete ─
# Regression guard (PR #297, e0e75ab): the on-path single-object gate returns NON-ZERO for a
# zero-byte file, so pre-fix an empty existing settings.json was misclassified malformed→blocked
# even though an ABSENT file seeds fine and the merge core treats empty as `{}`. The empty==absent
# special-case routes zero-byte content to current_settings="" → seed defaults. Non-vacuous: pre-fix
# the gate fired emit_blocked_output malformed → status blocked, flipping these assertions.
echo '=== Case 3e: EMPTY (zero-byte) existing settings — seed defaults, status complete ==='
ROOT3E="$(new_project empty-zero)"
mkdir -p "$ROOT3E/.claude"
: > "$ROOT3E/.claude/settings.json"
INPUTS3E="$(jq -nc --arg r "$ROOT3E" '{ project_root: $r, agent_target: "hivemind:overlord", caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT3E="$(run_apply "$ROOT3E" "$INPUTS3E")"
assert_eq "empty-zero:exit" "0" "$?" "zero-byte seed exit"
assert_contains "empty-zero:status" "status: complete" "$OUT3E"
assert_eq "empty-zero:settings.agent" "hivemind:overlord" \
  "$(jq -r '.agent' "$ROOT3E/.claude/settings.json" 2>/dev/null)" "seeded agent"
assert_eq "empty-zero:settings.hive" "true" \
  "$(jq -r '.enabledPlugins["hivemind@brenpike"]' "$ROOT3E/.claude/settings.json" 2>/dev/null)" "seeded hive key"

# ── Case 3w: WHITESPACE-ONLY existing settings → seed defaults, status complete ───
# Same empty==absent special-case as Case 3e, exercising the byte-level non-whitespace probe (not
# just -s): a file with only spaces/newlines/tabs has no non-whitespace byte → empty branch → seed.
echo '=== Case 3w: WHITESPACE-ONLY existing settings — seed defaults, status complete ==='
ROOT3W="$(new_project empty-ws)"
mkdir -p "$ROOT3W/.claude"
printf '  \n\t\n' > "$ROOT3W/.claude/settings.json"
INPUTS3W="$(jq -nc --arg r "$ROOT3W" '{ project_root: $r, agent_target: "hivemind:overlord", caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT3W="$(run_apply "$ROOT3W" "$INPUTS3W")"
assert_eq "empty-ws:exit" "0" "$?" "whitespace-only seed exit"
assert_contains "empty-ws:status" "status: complete" "$OUT3W"
assert_eq "empty-ws:settings.agent" "hivemind:overlord" \
  "$(jq -r '.agent' "$ROOT3W/.claude/settings.json" 2>/dev/null)" "seeded agent"
assert_eq "empty-ws:settings.hive" "true" \
  "$(jq -r '.enabledPlugins["hivemind@brenpike"]' "$ROOT3W/.claude/settings.json" 2>/dev/null)" "seeded hive key"

# ── Case 3g: GUARD — non-empty malformed/multi-doc still blocked (validation NOT loosened) ─
# Proves the empty==absent special-case did NOT loosen non-empty validation: any non-whitespace byte
# reaches the on-path single-object gate, which blocks malformed `{`, multi-doc `{}{}`, and NUL.
echo '=== Case 3g: GUARD non-empty malformed `{` — still blocked ==='
ROOT3G="$(new_project guard-brace)"
mkdir -p "$ROOT3G/.claude"
printf '{' > "$ROOT3G/.claude/settings.json"
BEFORE3G="$(cat "$ROOT3G/.claude/settings.json")"
INPUTS3G="$(jq -nc --arg r "$ROOT3G" '{ project_root: $r, caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT3G="$(run_apply "$ROOT3G" "$INPUTS3G")"
assert_contains "guard-brace:status" "status: blocked" "$OUT3G"
assert_eq "guard-brace:byte-unchanged" "$BEFORE3G" "$(cat "$ROOT3G/.claude/settings.json")" "malformed brace untouched"

echo '=== Case 3g: GUARD multi-doc `{}{}` — still blocked ==='
ROOT3GM="$(new_project guard-multidoc)"
mkdir -p "$ROOT3GM/.claude"
printf '{}{}' > "$ROOT3GM/.claude/settings.json"
BEFORE3GM="$(cat "$ROOT3GM/.claude/settings.json")"
INPUTS3GM="$(jq -nc --arg r "$ROOT3GM" '{ project_root: $r, caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT3GM="$(run_apply "$ROOT3GM" "$INPUTS3GM")"
assert_contains "guard-multidoc:status" "status: blocked" "$OUT3GM"
assert_eq "guard-multidoc:byte-unchanged" "$BEFORE3GM" "$(cat "$ROOT3GM/.claude/settings.json")" "multi-doc untouched"

echo '=== Case 3g: GUARD NUL-bearing — still blocked, byte-unchanged ==='
ROOT3GN="$(new_project guard-nul)"
mkdir -p "$ROOT3GN/.claude"
printf '{\000}' > "$ROOT3GN/.claude/settings.json"
cp "$ROOT3GN/.claude/settings.json" "$ROOT3GN/settings.fixture"
INPUTS3GN="$(jq -nc --arg r "$ROOT3GN" '{ project_root: $r, caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT3GN="$(run_apply "$ROOT3GN" "$INPUTS3GN")"
assert_contains "guard-nul:status" "status: blocked" "$OUT3GN"
if cmp -s "$ROOT3GN/settings.fixture" "$ROOT3GN/.claude/settings.json"; then
  pass "guard-nul:byte-unchanged" "NUL-bearing settings.json byte-exact vs fixture"
else
  failed "guard-nul:byte-unchanged" "NUL-bearing settings.json was mutated (expected byte-exact fixture)"
fi

# ── caveman SubagentStart hook identity constants (shared by Cases 4 / 4m / 4q) ───
# Mirrors the single-literal bindings in plugin/skills/_shared/settings-merge.sh: the relative
# script path, the TWO authored SHELL-form commands earlier seeds wrote (both migration inputs),
# and the canonical EXEC-FORM command written today. COMMAND_CANONICAL is UNQUOTED because under
# exec form the substituted string reaches execve verbatim — a surrounding `"` would become a
# literal path byte. The double quotes in COMMAND_QUOTED_ANCHORED are part of that older COMMAND
# STRING (they quoted the expansion for the shell branch), not JSON syntax.
# Every constant below is SINGLE-QUOTED at the placeholder so ${CLAUDE_PROJECT_DIR} is never
# shell-expanded by this runner.
HOOK_REL=".claude/hooks/caveman-ultra-subagent.sh"
HOOK_PLACEHOLDER='${CLAUDE_PROJECT_DIR}'
COMMAND_LEGACY="$HOOK_REL"
COMMAND_QUOTED_ANCHORED="\"$HOOK_PLACEHOLDER\"/$HOOK_REL"
COMMAND_CANONICAL="$HOOK_PLACEHOLDER/$HOOK_REL"

# ── Case 4: all-companions-no reduced Output (already covered by Case 1) + caveman yes ──
echo '=== Case 4: caveman=yes seed — envrc + hook + pluginConfigs written ==='
ROOT4="$(new_project caveman)"
INPUTS4="$(jq -nc --arg r "$ROOT4" '{
  project_root: $r, caveman: "yes", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT4="$(run_apply "$ROOT4" "$INPUTS4")"
assert_eq "caveman:exit" "0" "$?" "caveman seed exit"
assert_contains "caveman:status"   "status: complete" "$OUT4"
assert_contains "caveman:envrc"    "- .envrc: created" "$OUT4"
assert_contains "caveman:hookfile" "- .claude/hooks/caveman-ultra-subagent.sh: created" "$OUT4"
assert_contains "caveman:hookwire" "- hooks.SubagentStart in settings.json: added" "$OUT4"
assert_contains "caveman:keypcfg"  '- pluginConfigs["caveman@caveman"]: added' "$OUT4"
# `resolved` is sourced from the TOP-LEVEL caveman/claude_mem/codex flags, NOT from the companions
# facts (which here are absent). With caveman=yes top-level, the caveman companion reports
# `resolved: yes` and the off companions `resolved: no` — even though no `companions` block was
# supplied. Guards the regression where `resolved` keyed off the (absent) companions.resolved field
# and always printed `resolved: unknown`.
# Absent companion facts (explicit-input skips detection) → the emitter's `($c.via // "explicit-input")`
# default reports `via: explicit-input` (NOT the out-of-schema `via: unknown`); see SKILL.md `## Output`.
assert_contains "caveman:resolved-yes" "- caveman@caveman: detected: not-checked, source: not-checked, resolved: yes, via: explicit-input" "$OUT4"
assert_contains "caveman:resolved-no"  "- claude-mem@thedotmack: detected: not-checked, source: not-checked, resolved: no, via: explicit-input" "$OUT4"
# Finding-2 (PR #297): absent companion facts (explicit-input skips detection) report the
# schema-valid `not-checked` token for detected/source — NEVER the out-of-schema `unknown`.
# Non-vacuous: pre-fix this path emitted `detected: unknown, source: unknown` (not in the Output enum).
for offschema in "detected: unknown" "source: unknown"; do
  if printf '%s' "$OUT4" | grep -qF -- "$offschema"; then
    failed "caveman:companions-no-unknown" "companions block emits out-of-schema token '$offschema'"
  else
    pass "caveman:companions-no-unknown" "companions block free of out-of-schema token '$offschema'"
  fi
done
# Focused `via` regression (mirrors the detected/source guard above): caveman=yes with NO companions
# facts block exercises the explicit-input skip path. The `via:` column MUST report `explicit-input`
# (the emitter's `($c.via // "explicit-input")` default) and MUST NOT leak the out-of-schema `via: unknown`.
# Non-vacuous: pre-fix this path printed `via: unknown` for every companion when no facts were threaded.
assert_contains "caveman:via-explicit-input" "via: explicit-input" "$OUT4"
if printf '%s' "$OUT4" | grep -qF -- "via: unknown"; then
  failed "caveman:via-no-unknown" "companions block emits out-of-schema token 'via: unknown'"
else
  pass "caveman:via-no-unknown" "companions block free of out-of-schema token 'via: unknown'"
fi
assert_eq "caveman:envrc-content" "export CAVEMAN_DEFAULT_MODE=ultra" "$(cat "$ROOT4/.envrc")" ".envrc content"
[ -x "$ROOT4/.claude/hooks/caveman-ultra-subagent.sh" ] \
  && pass "caveman:hook-exec" "hook file is executable" \
  || failed "caveman:hook-exec" "hook file not executable"
# (a) The WIRED entry is EXEC (argv) form (issue #352): an UNQUOTED anchored command plus an
# `args` array. A relative hook command resolves against the subagent's cwd, so it silently no-ops
# outside the repo root; and without `args` the engine takes the SHELL branch, where the harness
# does NOT substitute ${CLAUDE_PROJECT_DIR} per element. `args: []` is what selects exec form.
CAVE_CMD4="$(jq -r '.hooks.SubagentStart[0].hooks[0].command' "$ROOT4/.claude/settings.json" 2>/dev/null)"
assert_eq "caveman:hook-command" "$COMMAND_CANONICAL" "$CAVE_CMD4" "wired SubagentStart command is the anchored exec-form command"
assert_eq "caveman:hook-args" "[]" \
  "$(jq -c '.hooks.SubagentStart[0].hooks[0].args' "$ROOT4/.claude/settings.json" 2>/dev/null)" "wired SubagentStart entry carries args: [] (selects exec form)"
# (b) DRIFT GUARD — close the path/command drift class MECHANICALLY rather than by matching two
# hand-written literals: substitute this project root for the ${CLAUDE_PROJECT_DIR} placeholder and
# require the resulting real filesystem path to EXIST and be EXECUTABLE. That proves the wired
# command points at the file the scaffold actually created. (No quote-stripping step: the exec-form
# command carries no quotes — under execve a `"` would be a literal path byte.) Non-vacuous: rename
# the hook script on ONE side only (scaffold path in seed-hive.sh, or $hook_rel in
# settings-merge.sh) and this resolves to a nonexistent path → FAIL here, instead of shipping a
# settings.json wired to a script that is not there.
CAVE_HOOK_PATH4="${CAVE_CMD4/"$HOOK_PLACEHOLDER"/$ROOT4}"
if [ -x "$CAVE_HOOK_PATH4" ]; then
  pass "caveman:hook-command-resolves" "wired command resolves to the scaffolded executable hook ('$CAVE_HOOK_PATH4')"
else
  failed "caveman:hook-command-resolves" "wired command resolves to '$CAVE_HOOK_PATH4', which is not an existing executable file"
fi

# ── Case 4m: LEGACY relative hook entry migrates IN PLACE through the entrypoint ──
# A project seeded by an EARLIER plugin version carries the bare relative SHELL-form command (no
# `args` key). Re-seeding with caveman=yes must REWRITE that entry in place to the EXEC-FORM
# command + `args: []` — reported with the EXISTING `added` token (STEP-001 introduced no new
# report token) — and must NEVER append a second entry beside it. Non-vacuous: pre-fix the merge
# keyed hook presence on any command containing the script path, so the legacy entry classified
# `already present` and the unanchored shell-form command stayed wired; a naive append-on-mismatch
# instead yields two entries and flips the duplicate assertions.
echo '=== Case 4m: legacy relative hook entry — migrated in place, no duplicate ==='
ROOT4M="$(new_project caveman-legacy)"
mkdir -p "$ROOT4M/.claude"
jq -nc --arg cmd "$COMMAND_LEGACY" \
  '{hooks:{SubagentStart:[{hooks:[{type:"command",command:$cmd}]}]}}' > "$ROOT4M/.claude/settings.json"
INPUTS4M="$(jq -nc --arg r "$ROOT4M" '{
  project_root: $r, caveman: "yes", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT4M="$(run_apply "$ROOT4M" "$INPUTS4M")"
assert_eq "cavemigrate:exit" "0" "$?" "legacy-migration seed exit"
assert_contains "cavemigrate:status"   "status: complete" "$OUT4M"
assert_contains "cavemigrate:hookwire" "- hooks.SubagentStart in settings.json: added" "$OUT4M"
assert_eq "cavemigrate:no-duplicate" "1" \
  "$(jq -r '.hooks.SubagentStart | length' "$ROOT4M/.claude/settings.json" 2>/dev/null)" "SubagentStart holds exactly one entry"
assert_eq "cavemigrate:single-command" "1" \
  "$(jq -r --arg rel "$HOOK_REL" '[.hooks.SubagentStart[].hooks[] | select((.command | type) == "string" and (.command | contains($rel)))] | length' \
     "$ROOT4M/.claude/settings.json" 2>/dev/null)" "exactly one command wired to the hook script"
assert_eq "cavemigrate:command" "$COMMAND_CANONICAL" \
  "$(jq -r '.hooks.SubagentStart[0].hooks[0].command' "$ROOT4M/.claude/settings.json" 2>/dev/null)" "legacy command rewritten in place to the exec-form command"
assert_eq "cavemigrate:args" "[]" \
  "$(jq -c '.hooks.SubagentStart[0].hooks[0].args' "$ROOT4M/.claude/settings.json" 2>/dev/null)" "migrated entry gained args: [] (selects exec form)"
# Re-run: the migrated entry is already canonical → `already present`, settings byte-stable.
SETTINGS4M_BEFORE="$(cat "$ROOT4M/.claude/settings.json")"
OUT4M2="$(run_apply "$ROOT4M" "$INPUTS4M")"
assert_contains "cavemigrate:rerun-status"   "status: complete" "$OUT4M2"
assert_contains "cavemigrate:rerun-hookwire" "- hooks.SubagentStart in settings.json: already present" "$OUT4M2"
assert_eq "cavemigrate:rerun-byte-stable" "$SETTINGS4M_BEFORE" \
  "$(cat "$ROOT4M/.claude/settings.json")" "settings byte-stable across migration re-run"

# ── Case 4q: UNRELEASED quoted-anchored hook entry migrates IN PLACE ──────────────
# The second authored SHELL-form pre-state: `"${CLAUDE_PROJECT_DIR}"/<hook_rel>` with NO `args` key,
# written by an unreleased intermediate revision. It is anchored but still shell-form, so the engine
# takes the shell branch and never substitutes the placeholder per element. Re-seeding must rewrite
# it IN PLACE to the UNQUOTED exec-form command + `args: []`, with no duplicate entry appended.
# Non-vacuous: if the merge's authored-command list carried only the bare-relative literal, this
# entry would fail canonical identity, get NO migration, and be APPENDED beside — flipping the
# duplicate and command assertions below.
echo '=== Case 4q: unreleased quoted-anchored hook entry — migrated in place, no duplicate ==='
ROOT4Q="$(new_project caveman-quoted)"
mkdir -p "$ROOT4Q/.claude"
jq -nc --arg cmd "$COMMAND_QUOTED_ANCHORED" \
  '{hooks:{SubagentStart:[{hooks:[{type:"command",command:$cmd}]}]}}' > "$ROOT4Q/.claude/settings.json"
INPUTS4Q="$(jq -nc --arg r "$ROOT4Q" '{
  project_root: $r, caveman: "yes", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT4Q="$(run_apply "$ROOT4Q" "$INPUTS4Q")"
assert_eq "cavequoted:exit" "0" "$?" "quoted-anchored migration seed exit"
assert_contains "cavequoted:status"   "status: complete" "$OUT4Q"
assert_contains "cavequoted:hookwire" "- hooks.SubagentStart in settings.json: added" "$OUT4Q"
assert_eq "cavequoted:no-duplicate" "1" \
  "$(jq -r '.hooks.SubagentStart | length' "$ROOT4Q/.claude/settings.json" 2>/dev/null)" "SubagentStart holds exactly one entry"
assert_eq "cavequoted:single-command" "1" \
  "$(jq -r --arg rel "$HOOK_REL" '[.hooks.SubagentStart[].hooks[] | select((.command | type) == "string" and (.command | contains($rel)))] | length' \
     "$ROOT4Q/.claude/settings.json" 2>/dev/null)" "exactly one command wired to the hook script"
assert_eq "cavequoted:command" "$COMMAND_CANONICAL" \
  "$(jq -r '.hooks.SubagentStart[0].hooks[0].command' "$ROOT4Q/.claude/settings.json" 2>/dev/null)" "quoted-anchored command rewritten in place to the unquoted exec-form command"
assert_eq "cavequoted:args" "[]" \
  "$(jq -c '.hooks.SubagentStart[0].hooks[0].args' "$ROOT4Q/.claude/settings.json" 2>/dev/null)" "migrated entry gained args: [] (selects exec form)"
# Re-run: the migrated entry is already canonical → `already present`, settings byte-stable.
SETTINGS4Q_BEFORE="$(cat "$ROOT4Q/.claude/settings.json")"
OUT4Q2="$(run_apply "$ROOT4Q" "$INPUTS4Q")"
assert_contains "cavequoted:rerun-hookwire" "- hooks.SubagentStart in settings.json: already present" "$OUT4Q2"
assert_eq "cavequoted:rerun-byte-stable" "$SETTINGS4Q_BEFORE" \
  "$(cat "$ROOT4Q/.claude/settings.json")" "settings byte-stable across quoted-anchored migration re-run"

# ── Case 4s: NON-CONFORMING SubagentStart element — apply still exits 0 with an Output block ──
# End-to-end pin of the documented apply contract (SKILL.md `## Output`: apply exits 0 even when it
# reports a status — the outcome is REPORTED, never a script error) against a hostile-shaped
# pre-state: a bare STRING sitting directly in `.hooks.SubagentStart[]`. STEP-001's `canon_elem`
# makes every element access in the caveman SubagentStart block TOTAL, so the non-conforming element
# is never migrated, never counted present, and always PRESERVED, while the canonical exec-form
# entry is appended beside it.
# Non-vacuous (verified empirically against a pre-STEP-001 copy of settings-merge.sh): the untotal
# element access aborted the jq program, whose exit 5 propagated through the entrypoint's
# `set -euo pipefail` and killed the script BEFORE the write block — apply exited 5 with raw jq
# stderr and NO Output block at all, flipping every assertion below.
# The apply emitter writes the CONTENTS of the SKILL.md `## Output` block (the heading itself is
# markdown structure in SKILL.md, not emitted text), so Output-block presence is keyed on its
# structural section labels, matching the Case 1 / Case 3 idiom.
echo '=== Case 4s: non-conforming SubagentStart element — exit 0, Output block, element preserved ==='
ROOT4S="$(new_project caveman-nonconforming)"
mkdir -p "$ROOT4S/.claude"
printf '%s' '{"hooks":{"SubagentStart":["x"]}}' > "$ROOT4S/.claude/settings.json"
INPUTS4S="$(jq -nc --arg r "$ROOT4S" '{
  project_root: $r, caveman: "yes", claude_mem: "no", codex: "no", seed_allowlist: "yes" }')"
OUT4S="$(run_apply "$ROOT4S" "$INPUTS4S")"
RC4S=$?
assert_eq "cavescalar:exit" "0" "$RC4S" "non-conforming element is a reported outcome, not a script error"
assert_contains "cavescalar:status"      "status: complete" "$OUT4S"
assert_contains "cavescalar:out-project" "project_root:" "$OUT4S"
assert_contains "cavescalar:out-target"  "target_file:" "$OUT4S"
assert_contains "cavescalar:out-keys"    "keys_applied:" "$OUT4S"
assert_contains "cavescalar:hookwire"    "- hooks.SubagentStart in settings.json: added" "$OUT4S"
# The non-conforming element is PRESERVED verbatim at its original position.
assert_eq "cavescalar:preserved" "x" \
  "$(jq -r '.hooks.SubagentStart[0]' "$ROOT4S/.claude/settings.json" 2>/dev/null)" "non-conforming element preserved at SubagentStart[0]"
assert_eq "cavescalar:appended" "2" \
  "$(jq -r '.hooks.SubagentStart | length' "$ROOT4S/.claude/settings.json" 2>/dev/null)" "canonical entry appended beside the preserved element"
assert_eq "cavescalar:single-command" "1" \
  "$(jq -r --arg rel "$HOOK_REL" '[.hooks.SubagentStart[] | select(type == "object") | .hooks[]? | select((.command | type) == "string" and (.command | contains($rel)))] | length' \
     "$ROOT4S/.claude/settings.json" 2>/dev/null)" "exactly one command wired to the hook script"
assert_eq "cavescalar:command" "$COMMAND_CANONICAL" \
  "$(jq -r '.hooks.SubagentStart[1].hooks[0].command' "$ROOT4S/.claude/settings.json" 2>/dev/null)" "appended entry carries the exec-form command"
assert_eq "cavescalar:args" "[]" \
  "$(jq -c '.hooks.SubagentStart[1].hooks[0].args' "$ROOT4S/.claude/settings.json" 2>/dev/null)" "appended entry carries args: [] (selects exec form)"

# ── Case 5: detect phase — manifest installed/absent, cache fallback, none ───────
echo '=== Case 5: detect phase reports companion facts ==='
ROOT5="$(new_project detect)"
# 5a: no manifest, no cache → all absent/none.
OUT5A="$(run_detect "$ROOT5")"
assert_eq "detect:none-caveman" "absent" "$(printf '%s' "$OUT5A" | jq -r '.companions["caveman@caveman"].detected')"
assert_eq "detect:none-source"  "none"   "$(printf '%s' "$OUT5A" | jq -r '.companions["caveman@caveman"].source')"
# 5b: manifest with caveman installed → caveman installed/manifest, others absent/manifest.
mkdir -p "$ROOT5/fakehome/.claude/plugins"
printf '{"plugins":{"caveman@caveman":[{"x":1}]}}\n' > "$ROOT5/fakehome/.claude/plugins/installed_plugins.json"
OUT5B="$(run_detect "$ROOT5")"
assert_eq "detect:mf-caveman-det" "installed" "$(printf '%s' "$OUT5B" | jq -r '.companions["caveman@caveman"].detected')"
assert_eq "detect:mf-caveman-src" "manifest"  "$(printf '%s' "$OUT5B" | jq -r '.companions["caveman@caveman"].source')"
assert_eq "detect:mf-codex-det"   "absent"    "$(printf '%s' "$OUT5B" | jq -r '.companions["codex@openai-codex"].detected')"
assert_eq "detect:mf-codex-src"   "manifest"  "$(printf '%s' "$OUT5B" | jq -r '.companions["codex@openai-codex"].source')"
# 5c: no manifest, codex cache dir present → codex installed/cache.
rm -f "$ROOT5/fakehome/.claude/plugins/installed_plugins.json"
mkdir -p "$ROOT5/fakehome/.claude/plugins/cache/openai-codex/codex"
OUT5C="$(run_detect "$ROOT5")"
assert_eq "detect:cache-codex-det" "installed" "$(printf '%s' "$OUT5C" | jq -r '.companions["codex@openai-codex"].detected')"
assert_eq "detect:cache-codex-src" "cache"     "$(printf '%s' "$OUT5C" | jq -r '.companions["codex@openai-codex"].source')"
# 5d: jq-ABSENT detect must NOT hard-fail — it degrades to the cache-dir probe and emits parseable
# facts (printf-assembled, valid JSON). Build a hermetic jq-LESS PATH that still has every other
# CLI the entrypoint needs: a tmp bin dir of symlinks to each command currently on PATH EXCEPT jq.
# (Stripping whole PATH dirs is wrong on systems where jq shares a dir with coreutils/bash — it
# would also hide dirname/mkdir/bash and break the script for the wrong reason.) A companion cache
# dir is present so the degraded probe classifies it `cache`. The ASSERTION re-enables jq (ambient
# PATH) to parse the emitted JSON. Non-vacuous: if detect re-acquired a hard jq gate (FINDING 2
# regression), the jq-less run would exit 2 with empty stdout and every assertion below would fail.
JQLESS_BIN="$WORKDIR/jqless-bin"
mkdir -p "$JQLESS_BIN"
IFS=':' read -r -a sh_path_dirs <<< "$PATH"
for sh_dir in "${sh_path_dirs[@]}"; do
  # Skip Windows mounts under WSL (/mnt/*): each stat/symlink across the DrvFs 9p mount is
  # ~10000x slower than a native dir, and those thousands of Windows .exe entries are never
  # CLIs the bash entrypoint invokes. The jq-less guarantee is unaffected — the omission set is
  # still {jq}, and every real POSIX/git CLI the entrypoint needs lives in native PATH dirs. On
  # non-WSL hosts there are no /mnt/* PATH dirs, so this is a no-op (identical farm contents).
  case "$sh_dir" in /mnt/*) continue ;; esac
  [ -d "$sh_dir" ] || continue
  for tool in "$sh_dir"/*; do
    [ -x "$tool" ] || continue
    base="$(basename "$tool")"
    [ "$base" = "jq" ] && continue            # the ONLY omission: jq is unavailable
    [ -e "$JQLESS_BIN/$base" ] && continue     # first dir on PATH wins (mirror real lookup)
    ln -s "$tool" "$JQLESS_BIN/$base"
  done
done
ROOT5D="$(new_project detect-jqless)"
mkdir -p "$ROOT5D/fakehome/.claude/plugins/cache/caveman/caveman"
# Run detect with jq UNAVAILABLE; capture stdout + exit code.
OUT5D="$(PATH="$JQLESS_BIN" HOME="$ROOT5D/fakehome" bash "$ENTRYPOINT" detect "$ROOT5D")"
RC5D=$?
assert_eq "detect:jqless-exit" "0" "$RC5D" "jq-absent detect exits 0 (degrades, not hard-fail)"
# Emitted bytes are parseable JSON (parse with jq, now back on the ambient PATH).
assert_eq "detect:jqless-parseable" "installed" \
  "$(printf '%s' "$OUT5D" | jq -r '.companions["caveman@caveman"].detected' 2>/dev/null)" "jq-absent detect emits parseable facts"
assert_eq "detect:jqless-cache-src" "cache" \
  "$(printf '%s' "$OUT5D" | jq -r '.companions["caveman@caveman"].source' 2>/dev/null)" "jq-absent detect classifies companion via cache fallback"

# ── Case 6: headless-resolved inputs drive a complete seed (claude_mem yes path) ─
echo '=== Case 6: headless-resolved inputs (claude_mem yes, allowlist no) → complete seed ==='
ROOT6="$(new_project headless)"
# claude-mem own config with an EMPTY CLAUDE_CODE_PATH + a fake claude binary on PATH.
mkdir -p "$ROOT6/fakehome/.claude-mem" "$ROOT6/fakehome/bin"
printf '{"other":"keep","CLAUDE_CODE_PATH":""}\n' > "$ROOT6/fakehome/.claude-mem/settings.json"
printf '#!/bin/sh\n' > "$ROOT6/fakehome/bin/claude"; chmod +x "$ROOT6/fakehome/bin/claude"
# a detectable test command (go.mod) so test_command: records.
printf 'module x\n' > "$ROOT6/go.mod"
INPUTS6="$(jq -nc --arg r "$ROOT6" '{
  project_root: $r, caveman: "no", claude_mem: "yes", codex: "no", seed_allowlist: "no" }')"
OUT6="$(PATH="$ROOT6/fakehome/bin:$PATH" run_apply "$ROOT6" "$INPUTS6")"
assert_eq "headless:exit" "0" "$?" "headless seed exit"
assert_contains "headless:status"   "status: complete" "$OUT6"
assert_contains "headless:memset"   "- ~/.claude-mem/settings.json CLAUDE_CODE_PATH: set" "$OUT6"
# Fresh set → restart follow-up note surfaced (behavior-restoring: base-prose step 11g notice).
assert_contains "headless:restart-note" \
  "- Restart claude-mem (or its background worker) so the new CLAUDE_CODE_PATH takes effect" "$OUT6"
assert_contains "headless:allow-no" "- not requested" "$OUT6"
assert_contains "headless:testcmd"  "- repo-root CLAUDE.md ## Validation: recorded go test ./..." "$OUT6"
assert_eq "headless:mem-preserved" "keep" \
  "$(jq -r '.other' "$ROOT6/fakehome/.claude-mem/settings.json")" "claude-mem sibling key preserved"
assert_eq "headless:mem-set" "$ROOT6/fakehome/bin/claude" \
  "$(jq -r '.CLAUDE_CODE_PATH' "$ROOT6/fakehome/.claude-mem/settings.json")" "CLAUDE_CODE_PATH set to resolved binary"
# allowlist no → no permissions.allow written.
assert_eq "headless:no-allowlist" "null" \
  "$(jq -r '.permissions.allow // "null"' "$ROOT6/.claude/settings.json")" "permissions.allow absent when seed_allowlist=no"

# ── Case 7: claude_mem yes but CLAUDE_CODE_PATH ALREADY set → NO restart note ─────
echo '=== Case 7: claude_mem yes, CLAUDE_CODE_PATH already set → already set + no restart note ==='
ROOT7="$(new_project memalready)"
mkdir -p "$ROOT7/fakehome/.claude-mem" "$ROOT7/fakehome/bin"
# A non-empty CLAUDE_CODE_PATH → provision writes nothing, reports `already set`.
printf '{"other":"keep","CLAUDE_CODE_PATH":"/preexisting/claude"}\n' > "$ROOT7/fakehome/.claude-mem/settings.json"
printf '#!/bin/sh\n' > "$ROOT7/fakehome/bin/claude"; chmod +x "$ROOT7/fakehome/bin/claude"
INPUTS7="$(jq -nc --arg r "$ROOT7" '{
  project_root: $r, caveman: "no", claude_mem: "yes", codex: "no", seed_allowlist: "no" }')"
OUT7="$(PATH="$ROOT7/fakehome/bin:$PATH" run_apply "$ROOT7" "$INPUTS7")"
assert_contains "memalready:status"   "status: complete" "$OUT7"
assert_contains "memalready:alreadyset" "- ~/.claude-mem/settings.json CLAUDE_CODE_PATH: already set" "$OUT7"
assert_contains "memalready:followup-none" "follow_up:
- None" "$OUT7"
# Restart note must NOT appear when nothing was freshly set.
if printf '%s' "$OUT7" | grep -qF -- "Restart claude-mem"; then
  failed "memalready:no-restart-note" "restart note leaked on already-set path"
else
  pass "memalready:no-restart-note" "(no restart note on already-set path)"
fi
# Pre-existing value untouched.
assert_eq "memalready:preserved" "/preexisting/claude" \
  "$(jq -r '.CLAUDE_CODE_PATH' "$ROOT7/fakehome/.claude-mem/settings.json")" "existing CLAUDE_CODE_PATH preserved"

# ── Case 7m: apply with a MULTI-DOC inputs stream → exit 2, usage fail, NO mutation ──
# The JSON multi-document (stream) sweep routed apply's inputs precheck through the single-object
# primitive (hivemind_jq_is_single_object_file). Two concatenated objects are a STREAM, not one
# object, so the precheck rejects it BEFORE any field read or file mutation.
# Non-vacuous: a revert to the per-doc `type=="object"` precheck would ACCEPT the stream; the
# jq -r field reads would then concatenate both docs' project_root into a multi-line value (no
# clean exit-2 fail, and the seed would proceed) → every assertion below flips.
echo '=== Case 7m: apply MULTI-DOC inputs stream — exit 2, usage fail, no mutation ==='
ROOT7M="$(new_project apply-multidoc)"
# TWO concatenated JSON objects (a stream). One names a different project_root than the other.
printf '{"project_root":"/x"}{"project_root":"%s"}' "$ROOT7M" > "$ROOT7M/inputs.json"
set +e
OUT7M="$( cd "$ROOT7M" && HOME="$ROOT7M/fakehome" bash "$ENTRYPOINT" apply "$ROOT7M/inputs.json" 2>&1 )"
RC7M=$?
set -u
assert_eq "apply-multidoc:exit" "2" "$RC7M" "multi-doc inputs stream fails with exit 2"
assert_contains "apply-multidoc:failmsg" "apply inputs file is not a valid JSON object" "$OUT7M"
# No silent field corruption: the run never reached the seed/render path.
if printf '%s' "$OUT7M" | grep -qF -- "status: complete"; then
  failed "apply-multidoc:no-complete" "multi-doc inputs stream wrongly emitted 'status: complete'"
else
  pass "apply-multidoc:no-complete" "(multi-doc stream did not emit status: complete)"
fi
# No settings.json written under the project root (the rejected run mutated nothing).
[ -e "$ROOT7M/.claude/settings.json" ] \
  && failed "apply-multidoc:no-write" "multi-doc stream wrote .claude/settings.json (expected no mutation)" \
  || pass "apply-multidoc:no-write" "(no .claude/settings.json written for rejected multi-doc stream)"

# ── Case 7n: detect with a MULTI-DOC manifest → cache-fallback, NO per-object manifest hit ──
# The same sweep routed detect's manifest precheck through hivemind_jq_is_single_object_file: a
# torn `installed_plugins.json` stream is treated EXACTLY like an unparseable manifest, so the
# manifest branch is skipped and resolution degrades to the cache-dir probe.
# Non-vacuous: a revert would `jq -e ... has($k)` per-document and mis-classify caveman as
# installed/manifest off the first doc (which makes it look installed) → the assertions flip.
echo '=== Case 7n: detect MULTI-DOC manifest — cache fallback, no per-object manifest mis-classify ==='
ROOT7N="$(new_project detect-multidoc)"
mkdir -p "$ROOT7N/fakehome/.claude/plugins"
# TWO concatenated manifest objects: the first would make caveman look installed; the second empty.
printf '{"plugins":{"caveman@caveman":[{"x":1}]}}{"plugins":{}}' \
  > "$ROOT7N/fakehome/.claude/plugins/installed_plugins.json"
OUT7N="$(run_detect "$ROOT7N")"
RC7N=$?
assert_eq "detect-multidoc:exit" "0" "$RC7N" "torn manifest detect still exits 0 (degrades, not hard-fail)"
# The torn stream must NOT classify caveman from the manifest. No cache dir is staged → cache
# fallback resolves to absent/none. Critically: source is NEVER `manifest` off the torn stream.
assert_eq "detect-multidoc:caveman-det" "absent" \
  "$(printf '%s' "$OUT7N" | jq -r '.companions["caveman@caveman"].detected' 2>/dev/null)" "torn-stream caveman not installed"
assert_eq "detect-multidoc:caveman-src" "none" \
  "$(printf '%s' "$OUT7N" | jq -r '.companions["caveman@caveman"].source' 2>/dev/null)" "torn-stream caveman resolved via cache fallback, not manifest"
CAVE_SRC7N="$(printf '%s' "$OUT7N" | jq -r '.companions["caveman@caveman"].source' 2>/dev/null)"
if [ "$CAVE_SRC7N" = "manifest" ]; then
  failed "detect-multidoc:no-manifest-misclassify" "torn manifest stream mis-classified caveman as source: manifest"
else
  pass "detect-multidoc:no-manifest-misclassify" "(torn manifest stream did not report caveman source: manifest)"
fi

# ── Case 8: Pattern-1 schema-enumeration — apply Output emits NO companion token out of enum ──
# Closes the merge-predicate-gap class at the SCHEMA boundary: parse the SKILL.md `## Output`
# companions enum for each field (via / detected / source / resolved), then across representative
# apply Outputs assert every `companions:` line's emitted value for that field is INSIDE the parsed
# enum. A future out-of-schema companion token (e.g. a new `via: unknown`) trips this immediately.
echo '=== Case 8: schema-enumeration — apply companions tokens stay within the SKILL.md ## Output enum ==='
SKILL_MD="$REPO_ROOT/plugin/skills/seed-hive/SKILL.md"
assert_eq "schema:skill-present" "0" "$([ -f "$SKILL_MD" ] && echo 0 || echo 1)" "SKILL.md present"

# enum_tokens <field> — extract the alternation tokens for one companions field from the fenced
# `## Output` block. Anchors on the `## Output` heading, the fenced ```text region, and a companion
# `- <name>: ... <field>: <a> | <b> | ...` line (robust to the trailing fields after it). Echoes one
# token per line.
enum_tokens() {
  local field="$1"
  awk -v field="$field" '
    /^## Output/      { in_out = 1; next }
    in_out && /^```text/ { in_fence = 1; next }
    in_out && in_fence && /^```/ { in_fence = 0; in_out = 0; next }
    in_fence && /^- (caveman@caveman|claude-mem@thedotmack|codex@openai-codex):/ {
      # isolate "<field>: <enum...>" up to the next ", <nextfield>:" or end of line.
      line = $0
      idx = index(line, field ": ")
      if (idx == 0) next
      rest = substr(line, idx + length(field) + 2)
      # cut at the first ", " that begins a following "<word>:" field label.
      if (match(rest, /, [a-z_]+: /)) rest = substr(rest, 1, RSTART - 1)
      n = split(rest, parts, / \| /)
      for (i = 1; i <= n; i++) { gsub(/^[ \t]+|[ \t]+$/, "", parts[i]); if (parts[i] != "") print parts[i] }
      exit
    }
  ' "$SKILL_MD" | sort -u
}

# assert_enum_coverage <case> <field> <output> — every value emitted on a companions line for <field>
# in <output> must be a member of the parsed SKILL.md enum for <field>.
assert_enum_coverage() {
  local case_name="$1" field="$2" output="$3"
  local enum emitted tok
  enum="$(enum_tokens "$field")"
  if [ -z "$enum" ]; then
    failed "$case_name" "could not parse '$field' enum from SKILL.md ## Output (parser anchor broke)"
    return
  fi
  # Pull each emitted value for this field from every companions `- <name>: ...` line.
  emitted="$(printf '%s\n' "$output" \
    | grep -E '^- (caveman@caveman|claude-mem@thedotmack|codex@openai-codex):' \
    | sed -nE "s/.*[, ]${field}: ([a-z-]+).*/\1/p" | sort -u)"
  if [ -z "$emitted" ]; then
    failed "$case_name" "no '$field' values emitted on any companions line (expected at least one)"
    return
  fi
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    if printf '%s\n' "$enum" | grep -qx -- "$tok"; then
      pass "$case_name" "'$field: $tok' is in the SKILL.md ## Output enum"
    else
      failed "$case_name" "'$field: $tok' is OUTSIDE the SKILL.md ## Output enum [$(printf '%s' "$enum" | tr '\n' '/')]"
    fi
  done <<< "$emitted"
}

# Representative apply Outputs: clean seed (Case 1, explicit-input/none), caveman=yes with absent
# companion facts (Case 4, the explicit-input skip path → not-checked + explicit-input), headless
# (Case 6, claude_mem=yes). Each must keep every companions token within its parsed enum.
for field in via detected source resolved; do
  assert_enum_coverage "schema:clean:$field"    "$field" "$OUT"
  assert_enum_coverage "schema:caveman:$field"  "$field" "$OUT4"
  assert_enum_coverage "schema:headless:$field" "$field" "$OUT6"
done

# ── Case 9: recorded-join — ≥3 detected commands joined by a TRUE `, ` between EVERY pair ─
# Non-vacuity: pre-fix the `recorded` branch used `paste -sd ', ' -`, whose `-d` CYCLES the two
# delimiter chars rather than using `, ` as one literal separator, yielding
#   `npm test,go test ./..., cargo test`  (comma-NO-space at pair 1).
# ≥3 commands are required to expose the cyclic alternation (2 commands only reveals a single
# missing space). Canonical emission order is derived from test-detect.sh §hivemind_detect_test_commands
# (JS=1, Go=3, Rust=4) → npm test, go test ./..., cargo test.
echo '=== Case 9: recorded-join — ≥3 commands joined by literal ", " between every pair ==='
ROOT9="$(new_project recordjoin)"
# JS (curated scripts.test → npm test) + Go (go.mod) + Rust (Cargo.toml): three root signals.
printf '{"scripts":{"test":"jest"}}\n' > "$ROOT9/package.json"
printf 'module x\n'                    > "$ROOT9/go.mod"
printf '[package]\nname = "x"\n'        > "$ROOT9/Cargo.toml"
INPUTS9="$(jq -nc --arg r "$ROOT9" '{
  project_root: $r, caveman: "no", claude_mem: "no", codex: "no", seed_allowlist: "no" }')"
OUT9="$(run_apply "$ROOT9" "$INPUTS9")"
assert_contains "recordjoin:exact" \
  "- repo-root CLAUDE.md ## Validation: recorded npm test, go test ./..., cargo test" "$OUT9"
# Recurrence guard: the pre-fix cyclic substring (comma-no-space at pair 1) must be ABSENT.
if printf '%s' "$OUT9" | grep -qF -- "npm test,go test"; then
  failed "recordjoin:no-cyclic" "comma-no-space join leaked (pre-fix paste -sd cyclic delimiter)"
else
  pass "recordjoin:no-cyclic" "(no comma-no-space pair; literal ', ' separator confirmed)"
fi

# ── Tally ───────────────────────────────────────────────────────────────────────
echo
echo "test_seed_hive: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
