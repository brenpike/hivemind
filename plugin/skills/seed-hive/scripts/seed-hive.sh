#!/usr/bin/env bash
#
# seed-hive — deterministic two-phase entrypoint for the hivemind:seed-hive skill.
#
# THIS SCRIPT IS THE THIN ENTRYPOINT (ADR-0020). It carries the REAL P18 shell-safety
# floor (`set -euo pipefail` + a guaranteed-zero EXIT trap) and COMPOSES the four sourced
# `_shared` libraries, performing NO judgment of its own: it runs no interactive prompt,
# invokes no skill, and makes no detect/headless decision. Those stay in the NAVIGATOR
# (the SKILL.md body / STEP-006): the navigator resolves every tri-state input to a final
# yes/no, then threads the resolved values into this script's APPLY phase. Given those
# inputs the script is PURELY DETERMINISTIC.
#
# TWO PHASES (selected by the first positional argument):
#
#   seed-hive.sh detect <project_root>
#       READ-ONLY companion classifier (SKILL.md Companion Detection). For each companion
#       (caveman@caveman, claude-mem@thedotmack, codex@openai-codex) it determines install
#       state from the installed-plugins manifest via jq → cache-dir fallback → none, and
#       emits ONE JSON object on stdout the navigator consumes to build its confirmation
#       prompt / headless resolution. Mutates NOTHING. Shape:
#         {
#           "companions": {
#             "caveman@caveman":       { "detected": "installed"|"absent",
#                                        "source": "manifest"|"cache"|"none" },
#             "claude-mem@thedotmack": { ... },
#             "codex@openai-codex":    { ... }
#           }
#         }
#       <project_root> is accepted for symmetry with apply (the detection sources are in the
#       user's HOME, not the project); it is validated as a real directory and otherwise
#       unused. The manifest path and cache root honor $HOME (so the navigator's test
#       harness can point them at a tmp HOME via the environment).
#
#   seed-hive.sh apply <inputs.json>
#       DETERMINISTIC mutator. Reads ONE JSON inputs file (authored by the navigator via the
#       Write tool) carrying every RESOLVED value, then composes the four libs to perform the
#       seed and emits the EXACT SKILL.md `## Output` block. The inputs file is the ONLY value
#       on the command line; every field is read with jq into inert shell variables (never
#       interpolated into program source). Inputs JSON shape (authoritative: SKILL.md):
#         {
#           "project_root":   "<required> absolute repo root (the navigator resolves it via
#                              git rev-parse --show-toplevel before calling)",
#           "agent_target":   "<optional> the required agent value; default hivemind:overlord",
#           "caveman":        "yes"|"no",   // RESOLVED (navigator already ran detect+confirm)
#           "claude_mem":     "yes"|"no",   // RESOLVED
#           "codex":          "yes"|"no",   // RESOLVED
#           "seed_allowlist": "yes"|"no",   // default yes
#           "agent_conflict_approved": "yes"|"no", // OPTIONAL, default "no". The navigator sets
#                              "yes" ONLY when re-running apply after the user explicitly approved
#                              overwriting a CONFLICTING existing `agent` value. Threaded as the
#                              7th positional arg into hivemind_settings_merge: "yes" authorizes
#                              the overwrite (merge returns ok → normal complete/updated Output);
#                              any other value / absent → conflict stays blocked. Inert when no
#                              agent conflict exists. NEVER authorizes clobbering a malformed file.
#           // companion detection FACTS (detected/source/via) the navigator gathered, echoed
#           // verbatim into the Output `companions:` block. Optional; absent detected/source
#           // (explicit yes/no skips detection) → reported not-checked.
#           "companions": {
#             "caveman@caveman":       { "detected": "...", "source": "...", "via": "..." },
#             "claude-mem@thedotmack": { ... },
#             "codex@openai-codex":    { ... }
#           }
#         }
#
# COMPOSITION (how the four libs are orchestrated in apply):
#   - settings.json: read current (or `{}`), call hivemind_settings_merge, then BRANCH on its
#     IN-BAND `status`:
#       * "conflict"  → the `agent` key already holds a DIFFERENT value. The entrypoint does
#                       NOT overwrite (SKILL.md Merge Rules: needs explicit user approval); it
#                       emits `status: blocked` with the conflict in the Output `conflicts:`
#                       block, writes NOTHING.
#       * "malformed" → the existing settings file is a non-empty unparseable blob. Fail closed:
#                       `status: blocked`, write NOTHING, file byte-unchanged.
#       * "ok"        → write the merged `.settings` back atomically (temp + mv).
#   - file-guards (file-guard.sh): `.gitignore` entries (.hivemind/, .claude/worktrees/) via
#     hivemind_append_if_absent; `.envrc` (caveman=yes) via hivemind_append_env_if_absent; the
#     caveman hook scaffold (caveman=yes) via hivemind_scaffold_hook_file.
#   - claude-mem CLAUDE_CODE_PATH (claude-mem-path.sh, claude_mem=yes) via
#     hivemind_claude_mem_provision_path against $HOME/.claude-mem/settings.json.
#   - test-command detection + `## Validation` append (test-detect.sh) via
#     hivemind_record_validation. test-detect.sh DELEGATES its section append to file-guard.sh's
#     hivemind_guard_validation_section, so file-guard.sh MUST be sourced BEFORE test-detect.sh.
#   - The Output `context_bootstrap: creep-spread: invoked` line is emitted as a CONSTANT — the
#     entrypoint does NOT invoke the skill (that is the navigator's job per SKILL.md step 13);
#     the navigator runs creep-spread around this APPLY call.
#
# STATUS RESOLUTION (SKILL.md Output `status: complete | partial | blocked`):
#   - blocked  → settings-merge returned conflict OR malformed (no settings write happened).
#   - partial  → settings written, but a sub-step degraded into a non-fatal skip that the
#                Output records in `issues:` (e.g. claude_mem_path malformed json). Reserved
#                for the documented degraded outcomes; the common clean seed is complete.
#   - complete → settings written and no degraded `issues:` accrued.
#
# EXIT CONTRACT:
#   0  detect emitted facts, OR apply emitted the Output block (INCLUDING the blocked Output —
#      a settings conflict is a REPORTED outcome, not a script error). The Output `status:`
#      field, not the exit code, carries complete/partial/blocked.
#   2  usage error (unknown/missing phase, missing/invalid argument, jq absent).
#
# P18 FLOOR: this entrypoint carries the FULL `set -euo pipefail` floor (it is an executable
# script, not a sourced library — the sourced libs each document their own CHECK13 floor
# exception). The libs run no top-level `set`, so sourcing them does not perturb this floor.
# INVARIANT: the EXIT trap ends with a guaranteed-zero `:` so a failing trap body can never
# clobber the script's intended exit code.

set -euo pipefail
trap ':' EXIT

fail() { printf 'seed-hive: %s\n' "$1" >&2; exit 2; }

# ── Script self-location (portable; independent of ${CLAUDE_PLUGIN_ROOT} and the caller) ──
# Resolve the plugin root from THIS script's OWN location, never a caller value. `cd && pwd -P`
# is portable (no GNU-only readlink -f); BASH_SOURCE is set under `#!/usr/bin/env bash`. Layout:
# plugin/skills/seed-hive/scripts/ => 3 dirs up is the plugin root (verified against the tree).
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || fail "cannot self-locate the script directory; refusing to proceed"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || fail "cannot resolve the plugin root from the script directory; refusing to proceed"
shared_dir="$plugin_root/skills/_shared"

# Source the five sourced libs by self-located absolute path. SOURCE-OR-DIE: a missing or
# unparseable shared library fails closed BEFORE any consumer logic — the entrypoint owns no
# merge/guard logic of its own, so proceeding without them would silently disarm every guard.
# containment.sh is DEFINITION-ONLY (pure function definitions, no top-level statement, no jq
# dependency), so sourcing it here neither perturbs the P18 floor nor adds a hard dependency the
# jq-less `detect` phase would trip over; it supplies phase_apply's inputs READ-guard only.
# KEEP THIS SOURCE DIRECT AND LITERAL — do NOT fold it back into the loop below: the policy
# linter enrolls a script into guard-before-read enforcement by matching the literal
# `. <path>/containment.sh` form, and an indirect loop-variable source silently opts this
# engine out of that enforcement.
[ -f "$shared_dir/containment.sh" ] || fail "required shared library missing: skills/_shared/containment.sh; refusing to proceed"
# shellcheck source=/dev/null
. "$shared_dir/containment.sh" || fail "failed to source skills/_shared/containment.sh (unparseable); refusing to proceed"

# ORDER: file-guard.sh BEFORE test-detect.sh — test-detect.sh's hivemind_record_validation
# DELEGATES its `## Validation` append to file-guard.sh's hivemind_guard_validation_section, so
# that function must be defined first (the test harness sources in the same order).
for lib in settings-merge.sh claude-mem-path.sh file-guard.sh test-detect.sh; do
  [ -f "$shared_dir/$lib" ] || fail "required shared library missing: skills/_shared/$lib; refusing to proceed"
  # shellcheck source=/dev/null
  . "$shared_dir/$lib" || fail "failed to source skills/_shared/$lib (unparseable); refusing to proceed"
done

# ── Companion detection (READ-ONLY) ────────────────────────────────────────────
# NO global jq gate: the read-only `detect` phase MUST run on a jq-less machine (SKILL.md
# Companion Detection: "treat jq-unavailable like an unparseable manifest; never crash"). The
# jq REQUIREMENT is scoped to `phase_apply` (which genuinely needs jq for the settings merge
# and Output render); detect degrades to the cache-dir probe and emits its facts via printf.
# The three companion plugin@marketplace keys, in the canonical Output order.
SEED_COMPANIONS=("caveman@caveman" "claude-mem@thedotmack" "codex@openai-codex")

# hivemind_seed_detect_one <plugin@marketplace>
# Classify ONE companion's install state (SKILL.md Companion Detection), READ-ONLY. Emits two
# space-separated words on stdout: "<detected> <source>" where detected is installed|absent and
# source is manifest|cache|none. Resolution order:
#   1. Manifest authoritative: when jq is available AND ~/.claude/plugins/installed_plugins.json
#      is readable valid JSON, a top-level .plugins["<key>"] entry → installed/manifest; absent
#      key → absent/manifest (the manifest is authoritative even if a cache dir happens to exist).
#   2. Cache fallback: jq absent, OR manifest absent/unparseable → check
#      ~/.claude/plugins/cache/<mkt>/<plugin>/. Directory present → installed/cache.
#   3. Neither: (jq absent OR manifest unparseable) AND no cache dir → absent/none.
# jq-UNAVAILABLE is treated EXACTLY like an unparseable manifest (SKILL.md Companion Detection):
# the manifest probe is skipped entirely and resolution degrades to the cache-dir branch; this
# function NEVER crashes and NEVER clobbers. $HOME is honored so a test harness can point
# detection at a tmp HOME.
hivemind_seed_detect_one() {
  local key="$1"
  local manifest="$HOME/.claude/plugins/installed_plugins.json"
  local plugin="${key%@*}"
  local marketplace="${key#*@}"
  local cache_dir="$HOME/.claude/plugins/cache/$marketplace/$plugin"

  # Manifest authoritative ONLY when jq is available AND the file is readable + valid JSON object.
  # When jq is ABSENT this whole branch is skipped (jq-unavailable == unparseable manifest), so
  # detection degrades to the cache-dir probe below — never a crash.
  if command -v jq >/dev/null 2>&1 \
     && [ -f "$manifest" ] && hivemind_jq_is_single_object_file "$manifest"; then
    if jq -e --arg k "$key" '(.plugins // {}) | has($k)' "$manifest" >/dev/null 2>&1; then
      printf '%s %s\n' "installed" "manifest"
    else
      printf '%s %s\n' "absent" "manifest"
    fi
    return 0
  fi

  # Cache fallback (manifest absent/unparseable).
  if [ -d "$cache_dir" ]; then
    printf '%s %s\n' "installed" "cache"
  else
    printf '%s %s\n' "absent" "none"
  fi
}

# phase_detect <project_root>
# Emit the companion-detection facts JSON the navigator consumes. READ-ONLY, and DELIBERATELY
# jq-FREE: detect MUST run to completion on a fully jq-less machine (FINDING 2). The output is a
# small FIXED-SHAPE structure — keys are the fixed literals in SEED_COMPANIONS, values are fixed
# enums (detected: installed|absent; source: manifest|cache|none) produced by
# hivemind_seed_detect_one. Because every emitted byte is a controlled literal (never an
# untrusted interpolation), the object is assembled with printf — no jq, no injection surface.
phase_detect() {
  local project_root="${1:-}"
  [ -n "$project_root" ] || fail "detect requires a project root argument"
  [ -d "$project_root" ] || fail "detect project root is not a directory: $project_root"

  # printf-assemble the SAME shape jq used to emit:
  #   { "companions": { "<key>": { "detected": "...", "source": "..." }, ... } }
  # `detected`/`source` are constrained to fixed enums by hivemind_seed_detect_one, and each
  # <key> is a fixed literal from SEED_COMPANIONS — no value here is attacker-controlled, so
  # direct embedding is safe and jq is not required to build (or escape) the document.
  local key fields detected source idx last
  last=$(( ${#SEED_COMPANIONS[@]} - 1 ))
  printf '{\n'
  printf '  "companions": {\n'
  for idx in "${!SEED_COMPANIONS[@]}"; do
    key="${SEED_COMPANIONS[$idx]}"
    fields="$(hivemind_seed_detect_one "$key")"
    detected="${fields%% *}"
    source="${fields##* }"
    printf '    "%s": { "detected": "%s", "source": "%s" }' "$key" "$detected" "$source"
    if [ "$idx" -lt "$last" ]; then printf ','; fi
    printf '\n'
  done
  printf '  }\n'
  printf '}\n'
}

# ── APPLY phase ─────────────────────────────────────────────────────────────────
# phase_apply <inputs.json>
# Compose the four libs to perform the deterministic seed and emit the SKILL.md `## Output`
# block. The inputs file is the ONLY command-line value; every field is read with jq into inert
# variables below — never interpolated into program source.
phase_apply() {
  # jq is REQUIRED for apply (the settings merge and every Output render run through jq). detect
  # degrades without jq; apply genuinely cannot — fail closed here rather than mid-merge.
  command -v jq >/dev/null 2>&1 \
    || fail "jq is required to merge settings and render the apply Output but is not installed"

  local INPUTS_FILE="${1:-}"
  [ -n "$INPUTS_FILE" ] || fail "apply requires an inputs JSON file argument"
  [ -f "$INPUTS_FILE" ] || fail "apply inputs file does not exist: $INPUTS_FILE"

  # ── Defense-in-depth inputs READ-guard (shared helper) ───────────────────────
  # Refuse to READ the inputs file when its canonical path escapes the checkout (e.g. via a
  # symlinked ancestor or a symlinked leaf) — converting a silent external read into a hard
  # blocker. ORDERING IS LOAD-BEARING: this runs BEFORE hivemind_jq_is_single_object_file,
  # because that helper performs the FIRST jq open of the file and a jq open of an
  # attacker-supplied external path is itself a JSON-validity read oracle. The helper never
  # exits; map its non-zero return onto this script's own fail() blocker idiom.
  #
  # ANCHOR: the checkout root is resolved from the PROCESS CWD via
  # `git rev-parse --show-toplevel` — NOT from the inputs file's `project_root`, which is not
  # readable until AFTER this guard runs, by design (the guard exists to decide whether reading
  # that file is safe at all). The not-in-a-repo PRECONDITION is the NAVIGATOR's gate, not this
  # engine's: see the skill body's Procedure step 1 ("Stop blocked if not a git repository").
  # On an EMPTY root the shared canonicalizer resolves to the process CWD rather than failing
  # closed — a property of the shared helper, common to the sibling call sites, tracked at #295.
  hivemind_assert_inputs_contained "$(git rev-parse --show-toplevel 2>/dev/null)" "$INPUTS_FILE" >/dev/null \
    || fail "refusing to read the inputs file: $INPUTS_FILE resolves outside the checkout"

  hivemind_jq_is_single_object_file "$INPUTS_FILE" \
    || fail "apply inputs file is not a valid JSON object: $INPUTS_FILE"

  # Parse every field into inert variables.
  local project_root agent_target caveman claude_mem codex seed_allowlist agent_conflict_approved
  project_root="$(jq -r '.project_root // ""' "$INPUTS_FILE")"
  agent_target="$(jq -r '.agent_target // "hivemind:overlord"' "$INPUTS_FILE")"
  caveman="$(jq -r '.caveman // "no"' "$INPUTS_FILE")"
  claude_mem="$(jq -r '.claude_mem // "no"' "$INPUTS_FILE")"
  codex="$(jq -r '.codex // "no"' "$INPUTS_FILE")"
  seed_allowlist="$(jq -r '.seed_allowlist // "yes"' "$INPUTS_FILE")"
  # OPTIONAL inert input: when the navigator re-runs apply after the user approved an agent
  # overwrite, it sets this to "yes". Read inertly via jq (never spliced into program source);
  # default "no" preserves the never-overwrite-on-conflict behavior for every existing caller.
  agent_conflict_approved="$(jq -r '.agent_conflict_approved // "no"' "$INPUTS_FILE")"

  [ -n "$project_root" ] || fail "apply inputs file is missing required project_root"
  [ -d "$project_root" ] || fail "apply project_root is not a directory: $project_root"

  # The companions facts block (detected/source/via) the navigator threaded in. Echoed verbatim
  # into the Output companions: block; absent detected/source → reported not-checked. Read once as
  # compact JSON.
  local companions_json
  if jq -e 'has("companions") and (.companions | type == "object")' "$INPUTS_FILE" >/dev/null 2>&1; then
    companions_json="$(jq -c '.companions' "$INPUTS_FILE")"
  else
    companions_json='{}'
  fi

  # Accumulators for the degraded-outcome → partial/issues classification.
  local -a issues=()

  # ── settings.json merge (settings-merge.sh) ──────────────────────────────────
  local settings_dir="$project_root/.claude"
  local settings_file="$settings_dir/settings.json"
  mkdir -p "$settings_dir"

  local current_settings=""
  # An EMPTY existing settings.json (zero-byte OR whitespace-only) is treated the SAME as an absent
  # file: current_settings stays "" and hivemind_settings_merge seeds {} defaults. The on-path single-
  # object gate returns non-zero for empty content, so without this special-case an empty file would be
  # misclassified malformed→blocked even though an absent file seeds fine. Emptiness is probed at the
  # BYTE level (-s for zero-byte, grep for any non-whitespace byte) — never via $(cat) capture, which
  # strips NUL/trailing newlines and would mask a torn file as empty.
  # NON-EMPTY content (any non-whitespace byte, including a NUL-bearing file) still runs the on-path
  # gate below — Class A: bash $(cat ...) silently strips NUL bytes (and trailing newlines), so a
  # NUL-bearing or torn on-disk settings.json would pass the in-variable single-object check and get
  # clobbered while apply reports complete. Validate the file ON ITS PATH before the lossy read — same
  # root as the ledger-project.sh hivemind_path_has_nul-before-$(cat) NUL precedent.
  if [ -f "$settings_file" ] && [ -s "$settings_file" ] && grep -q '[^[:space:]]' "$settings_file"; then
    if ! hivemind_jq_is_single_object_file "$settings_file"; then
      emit_blocked_output "$project_root" "malformed" "" "$companions_json"
      return 0
    fi
    current_settings="$(cat "$settings_file")"
  fi

  local merge_out merge_status
  merge_out="$(hivemind_settings_merge "$current_settings" "$agent_target" \
    "$caveman" "$claude_mem" "$codex" "$seed_allowlist" "$agent_conflict_approved")"
  merge_status="$(printf '%s' "$merge_out" | jq -r '.status')"

  # BRANCH on the in-band merge status. conflict/malformed → blocked Output, write NOTHING.
  if [ "$merge_status" = "conflict" ] || [ "$merge_status" = "malformed" ]; then
    emit_blocked_output "$project_root" "$merge_status" "$merge_out" "$companions_json"
    return 0
  fi

  # status == ok → render the merged settings to a temp file, then classify the write as
  # created (file was absent), unchanged (existing file is byte-identical to the merge result —
  # the idempotent re-run case), or updated (existing file differs). Only install when the bytes
  # actually change so a re-seed reports `unchanged` and leaves mtime untouched.
  local file_existed="false"
  [ -f "$settings_file" ] && file_existed="true"
  local tmp_settings
  tmp_settings="$(mktemp "$settings_dir/.settings.json.XXXXXX")" \
    || fail "failed to create temp settings file under $settings_dir"
  printf '%s' "$merge_out" | jq '.settings' >"$tmp_settings" \
    || { rm -f "$tmp_settings"; fail "failed to render merged settings JSON"; }
  local target_result
  if [ "$file_existed" = "false" ]; then
    target_result="created"
    mv -f "$tmp_settings" "$settings_file" \
      || { rm -f "$tmp_settings"; fail "failed to install merged settings at $settings_file"; }
  elif cmp -s "$tmp_settings" "$settings_file"; then
    target_result="unchanged"
    rm -f "$tmp_settings"
  else
    target_result="updated"
    mv -f "$tmp_settings" "$settings_file" \
      || { rm -f "$tmp_settings"; fail "failed to install merged settings at $settings_file"; }
  fi

  # ── .gitignore guards (file-guard.sh kernel, one call per entry) ──────────────
  local gitignore_existed="false"
  [ -f "$project_root/.gitignore" ] && gitignore_existed="true"
  local gi_hivemind gi_worktrees
  gi_hivemind="$(hivemind_append_if_absent "$project_root/.gitignore" ".hivemind/")"
  gi_worktrees="$(hivemind_append_if_absent "$project_root/.gitignore" ".claude/worktrees/")"
  local gitignore_result
  if [ "$gitignore_existed" = "false" ]; then
    gitignore_result="created"
  elif [ "$gi_hivemind" = "added" ] || [ "$gi_worktrees" = "added" ]; then
    gitignore_result="updated"
  else
    gitignore_result="already present"
  fi

  # ── .envrc + caveman hook scaffold (file-guard.sh, caveman=yes only) ──────────
  local envrc_result hook_file_result
  if [ "$caveman" = "yes" ]; then
    local envrc_existed="false"
    [ -f "$project_root/.envrc" ] && envrc_existed="true"
    local envrc_guard
    envrc_guard="$(hivemind_append_env_if_absent "$project_root/.envrc" "export CAVEMAN_DEFAULT_MODE=ultra")"
    if [ "$envrc_existed" = "false" ]; then
      envrc_result="created"
    elif [ "$envrc_guard" = "added" ]; then
      envrc_result="updated"
    else
      envrc_result="already present"
    fi
    hook_file_result="$(hivemind_scaffold_hook_file "$project_root/.claude/hooks/caveman-ultra-subagent.sh")"
  else
    envrc_result="skipped (caveman not enabled)"
    hook_file_result="skipped (caveman not enabled)"
  fi

  # hooks.SubagentStart settings classification comes from the merge report (settings-merge.sh
  # owns the settings wiring). resolved no → skipped Output token.
  local hook_settings_class hook_settings_result
  hook_settings_class="$(printf '%s' "$merge_out" | jq -r '.keys["hooks.SubagentStart"]')"
  case "$hook_settings_class" in
    "resolved no") hook_settings_result="skipped (caveman not enabled)" ;;
    *)             hook_settings_result="$hook_settings_class" ;;
  esac

  # ── claude-mem CLAUDE_CODE_PATH (claude-mem-path.sh, claude_mem=yes only) ──────
  local claude_mem_path_result
  if [ "$claude_mem" = "yes" ]; then
    claude_mem_path_result="$(hivemind_claude_mem_provision_path "$HOME/.claude-mem/settings.json")"
    case "$claude_mem_path_result" in
      "skipped (malformed json)") issues+=("claude_mem_path: skipped (malformed json)") ;;
    esac
  else
    claude_mem_path_result="skipped (claude_mem not enabled)"
  fi

  # ── test-command detection + ## Validation append (test-detect.sh) ────────────
  # hivemind_record_validation DELEGATES to file-guard.sh's section guard (sourced above).
  local validation_status test_command_line
  validation_status="$(hivemind_record_validation "$project_root" "$project_root/CLAUDE.md")"
  case "$validation_status" in
    "none detected (recommend manual)")
      test_command_line="none detected (recommend manual)" ;;
    "already documented")
      test_command_line="already documented" ;;
    "added")
      # Recorded — report the detected command(s) inline, joined with a literal `, ` between
      # adjacent commands. Element boundary is the NEWLINE (one command per detector line);
      # embedded spaces within a single command (e.g. `go test ./...`) are preserved.
      local recorded
      recorded="$(hivemind_detect_test_commands "$project_root" | awk 'NR>1{printf ", "}{printf "%s",$0}')"
      test_command_line="recorded $recorded" ;;
    *)
      test_command_line="$validation_status" ;;
  esac

  # ── status resolution ────────────────────────────────────────────────────────
  local overall_status
  if [ "${#issues[@]}" -gt 0 ]; then
    overall_status="partial"
  else
    overall_status="complete"
  fi

  emit_complete_output \
    "$overall_status" "$project_root" "$target_result" "$gitignore_result" \
    "$envrc_result" "$hook_file_result" "$hook_settings_result" \
    "$companions_json" "$claude_mem_path_result" "$merge_out" \
    "$seed_allowlist" "$test_command_line" \
    "$caveman" "$claude_mem" "$codex"
}

# ── Output emitters ─────────────────────────────────────────────────────────────
# emit_companions_block <companions_json> <caveman_resolved> <claude_mem_resolved> <codex_resolved>
# Render the Output companions: lines from the threaded facts. The `resolved` yes/no value is NOT
# carried inside the companions facts block — the inputs schema keeps it at the TOP LEVEL caveman /
# claude_mem / codex fields, not inside each companion object — so it is supplied here from the
# three resolved top-level flags the caller already parsed, positional in SEED_COMPANIONS order
# (caveman, claude-mem, codex). detected/source/via still come from the threaded facts; a missing
# detected/source field (explicit yes/no skips detection) → "not-checked"; missing via →
# "explicit-input" (detection skipped because the input was explicit yes/no). resolved defaults to
# "no" — the caller always supplies all three flags (jq default "no"), so this default is latent.
emit_companions_block() {
  local companions_json="$1"
  # Resolved yes/no flags, positional in SEED_COMPANIONS order (caveman, claude-mem, codex).
  # Defaults to "no" (documented value) — caller always supplies these; default is latent hardening.
  local -a resolved_flags=("${2:-no}" "${3:-no}" "${4:-no}")
  local key fields detected source via resolved idx
  printf 'companions:\n'
  for idx in "${!SEED_COMPANIONS[@]}"; do
    key="${SEED_COMPANIONS[$idx]}"
    fields="$(jq -r --arg k "$key" '
      (.[$k] // {}) as $c
      | [($c.detected // "not-checked"), ($c.source // "not-checked"), ($c.via // "explicit-input")] | @tsv
    ' <<<"$companions_json")"
    IFS=$'\t' read -r detected source via <<<"$fields"
    resolved="${resolved_flags[$idx]}"
    printf -- '- %s: detected: %s, source: %s, resolved: %s, via: %s\n' \
      "$key" "$detected" "$source" "$resolved" "$via"
  done
}

# emit_permissions_block <merge_out> <seed_allowlist>
# Render the Output permissions_allow: lines from the merge report.
emit_permissions_block() {
  local merge_out="$1" seed_allowlist="$2"
  printf 'permissions_allow:\n'
  if [ "$seed_allowlist" = "yes" ]; then
    printf '%s' "$merge_out" \
      | jq -r '.permissions_allow[] | "- \(.rule): \(.result)"'
  else
    printf -- '- not requested\n'
  fi
}

# emit_keys_block <merge_out>
# Render the Output keys_applied: lines from the merge report.
emit_keys_block() {
  local merge_out="$1"
  printf 'keys_applied:\n'
  printf '%s' "$merge_out" | jq -r '
    .keys as $k
    | "- enabledPlugins[\"hivemind@brenpike\"]: \($k["enabledPlugins.hivemind@brenpike"])",
      "- agent: \($k.agent)",
      "- enabledPlugins[\"caveman@caveman\"]: \($k["enabledPlugins.caveman@caveman"])",
      "- enabledPlugins[\"claude-mem@thedotmack\"]: \($k["enabledPlugins.claude-mem@thedotmack"])",
      "- enabledPlugins[\"codex@openai-codex\"]: \($k["enabledPlugins.codex@openai-codex"])",
      "- pluginConfigs[\"caveman@caveman\"]: \($k["pluginConfigs.caveman@caveman"])"
  '
}

# emit_complete_output <status> <project_root> <target_result> <gitignore_result> \
#   <envrc_result> <hook_file_result> <hook_settings_result> <companions_json> \
#   <claude_mem_path_result> <merge_out> <seed_allowlist> <test_command_line> \
#   <caveman_resolved> <claude_mem_resolved> <codex_resolved>
# Emit the full SKILL.md `## Output` block for the complete/partial (settings-written) path. The
# three trailing resolved yes/no flags feed the companions: block's `resolved` column — that value
# lives at the inputs TOP LEVEL, not inside the companions facts, so it is threaded through here.
emit_complete_output() {
  local status="$1" project_root="$2" target_result="$3" gitignore_result="$4"
  local envrc_result="$5" hook_file_result="$6" hook_settings_result="$7"
  local companions_json="$8" claude_mem_path_result="$9" merge_out="${10}"
  local seed_allowlist="${11}" test_command_line="${12}"
  local caveman_resolved="${13}" claude_mem_resolved="${14}" codex_resolved="${15}"

  printf 'status: %s\n\n' "$status"
  printf 'project_root:\n- %s\n\n' "$project_root"
  printf 'target_file:\n- .claude/settings.json: %s\n\n' "$target_result"
  printf 'gitignore:\n- .gitignore: %s\n\n' "$gitignore_result"
  printf 'envrc:\n- .envrc: %s\n\n' "$envrc_result"
  printf 'hooks:\n'
  printf -- '- .claude/hooks/caveman-ultra-subagent.sh: %s\n' "$hook_file_result"
  printf -- '- hooks.SubagentStart in settings.json: %s\n\n' "$hook_settings_result"
  emit_companions_block "$companions_json" \
    "$caveman_resolved" "$claude_mem_resolved" "$codex_resolved"
  printf '\n'
  printf 'claude_mem_path:\n'
  printf -- '- ~/.claude-mem/settings.json CLAUDE_CODE_PATH: %s\n\n' "$claude_mem_path_result"
  # Restart follow-up: emitted ONLY on a FRESH set of CLAUDE_CODE_PATH. The claude-mem background
  # worker does not reload the new path until restart, so until then it may drop observations.
  # NOT emitted for `already set` / any `skipped (...)` — those write nothing and need no restart.
  printf 'follow_up:\n'
  if [ "$claude_mem_path_result" = "set" ]; then
    printf -- '- Restart claude-mem (or its background worker) so the new CLAUDE_CODE_PATH takes effect; until then it may drop observations.\n\n'
  else
    printf -- '- None\n\n'
  fi
  emit_keys_block "$merge_out"
  printf '\n'
  emit_permissions_block "$merge_out" "$seed_allowlist"
  printf '\n'
  printf 'context_bootstrap:\n- creep-spread: invoked\n\n'
  printf 'test_command:\n- repo-root CLAUDE.md ## Validation: %s\n\n' "$test_command_line"
  printf 'conflicts:\n- None\n\n'
  if [ "$status" = "partial" ]; then
    printf 'issues:\n'
    local issue
    for issue in "${issues[@]}"; do
      printf -- '- %s\n' "$issue"
    done
  else
    printf 'issues:\n- None\n'
  fi
}

# emit_blocked_output <project_root> <merge_status> <merge_out> <companions_json>
# Emit the BLOCKED terminal when settings-merge returned conflict/malformed. No settings were
# written (the merge left the file byte-unchanged). This conforms to the canonical Worker Report
# — Blocked schema (${CLAUDE_PLUGIN_ROOT}/governance/report-format.md, referenced by SKILL.md
# ## Output: "Use the Worker Report — Blocked schema ... for blocked states"): every emitted
# field is a schema-valid token. It carries the agent-conflict cause via a `conflicts:` /
# `existing vs required` line so the navigator can present the conflict to the user, then re-run
# apply with agent_conflict_approved="yes". The out-of-schema `## Output` tokens the prior
# version emitted (`unchanged`, `not invoked`, `not recorded`, `unchanged (settings not
# written)`) are GONE — none are members of any schema enum. The conflict and malformed branches
# remain distinct via the blocker reason. companions_json is accepted for signature symmetry
# with the complete emitter; the blocked report carries no companions block.
emit_blocked_output() {
  local project_root="$1" merge_status="$2" merge_out="$3" companions_json="$4"

  printf 'status: blocked\n'
  printf 'stage: implementation\n'
  if [ "$merge_status" = "conflict" ]; then
    printf 'blocker: .claude/settings.json already sets a different agent; overwrite needs explicit user approval\n'
  else
    printf 'blocker: .claude/settings.json is not valid JSON; refusing to overwrite without user approval\n'
  fi
  printf 'retry: not attempted\n'
  printf 'impact: settings not written; no project files mutated (settings.json byte-unchanged)\n'
  printf 'project_root:\n- %s\n' "$project_root"
  if [ "$merge_status" = "conflict" ]; then
    printf 'conflicts:\n'
    printf '%s' "$merge_out" | jq -r '
      .agent_conflict as $c
      | "- agent: \($c.existing) vs \($c.required)"'
    printf 'next: present the agent conflict to the user; on approval, re-run apply with agent_conflict_approved="yes"\n'
  else
    printf 'conflicts:\n- None\n'
    printf 'next: ask the user to repair or remove the malformed .claude/settings.json, then re-run apply\n'
  fi
}

# ── Phase dispatch ──────────────────────────────────────────────────────────────
main() {
  local phase="${1:-}"
  case "$phase" in
    detect) shift; phase_detect "${1:-}" ;;
    apply)  shift; phase_apply "${1:-}" ;;
    ""|-h|--help) fail "usage: seed-hive.sh detect <project_root> | apply <inputs.json>" ;;
    *)      fail "unknown phase '$phase'; expected detect|apply" ;;
  esac
}

main "$@"
