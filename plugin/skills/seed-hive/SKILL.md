---
name: seed-hive
description: Sets the overlord as default agent in .claude/settings.json and gitignores hivemind state. Use to adopt or repair setup.
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/seed-hive/scripts/seed-hive.sh" *)
  - Bash(git rev-parse *)   # navigator resolves the project root (git rev-parse --show-toplevel) before calling detect/apply — Procedure step 1
  - Read(~/.claude/plugins/cache/brenpike/hivemind/**)
  - Edit(.hivemind/seed-inputs-*.json)
  - Skill   # hivemind:creep-spread orchestration step — a skill cannot be invoked from bash (P5)
shell: bash
disable-model-invocation: true
---

# Setup Project

Apply the plugin's required project settings to `.claude/settings.json` so the
session default agent becomes `hivemind:overlord`, gitignore the runtime dirs, and
bootstrap project context. The engine is the two-phase script
`${CLAUDE_PLUGIN_ROOT}/skills/seed-hive/scripts/seed-hive.sh`, which is deterministic
on resolved `yes`/`no` inputs and makes no judgment. This body owns the judgment
(companion detection reasoning, interactive confirmation, conflict approval), then
authors one resolved-values inputs file and runs apply once (ADR-0020).

This skill runs only when the user explicitly requests it, as the alternative to
editing `.claude/settings.json` by hand per the README.

## When to Use

- new project adopting the plugin
- existing project missing the `agent` default
- repairing settings after manual edits broke routing
- after a plugin upgrade that ships new `permissions.allow` template rules: the
  template merges into `.claude/settings.json` only when this skill runs, and an
  upgrade never re-merges a consumer's settings, so an already-seeded project gets
  nothing until this skill is re-run. Re-running is always safe: the merge is
  idempotent append-if-absent and preserves existing entries.

Do not use this skill to change unrelated settings or to write keys outside the
engine's merge contract.

## Required Inputs

None. The navigator resolves the project root via `git rev-parse --show-toplevel` and
passes it to the engine.

## Optional Inputs

Tri-state knobs the navigator resolves to a final `yes`/`no` before calling apply:

- `caveman`: `yes`|`no`|`detect` (default `detect`): enable `caveman@caveman`,
  configure `pluginConfigs`, set up `.envrc`, and install the SubagentStart hook for
  caveman ultra mode.
- `claude_mem`: `yes`|`no`|`detect` (default `detect`): enable `claude-mem@thedotmack`
  and provision its `CLAUDE_CODE_PATH`.
- `codex`: `yes`|`no`|`detect` (default `detect`): enable `codex@openai-codex`.
- `seed_allowlist`: `yes`|`no` (default `yes`): merge the recommended least-privilege
  `permissions.allow` template (data and merge rules in settings-merge.sh). An explicit
  flag only, never detected or prompted, threaded into apply verbatim.

`detect` runs detection and confirmation (below); an explicit `yes`/`no` skips both
and is honored verbatim.

## Companion Detection (judgment)

For each companion input left at `detect`, run the read-only `detect` phase for the
facts, then reason about them:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/seed-hive/scripts/seed-hive.sh" detect <project_root>
```

It emits one JSON object on stdout:

```json
{
  "companions": {
    "caveman@caveman":       { "detected": "installed"|"absent", "source": "manifest"|"cache"|"none" },
    "claude-mem@thedotmack": { "detected": "...", "source": "..." },
    "codex@openai-codex":    { "detected": "...", "source": "..." }
  }
}
```

Use the `detected`/`source` facts to build the confirmation prompt, and carry them
forward into the inputs file for the Output `companions:` block.

## Interactive Confirmation (judgment)

Resolve each companion to a final `yes`/`no`:

- **Explicit input (`yes`/`no`).** That value verbatim; no detection, no prompt.
  Record `via: explicit-input`.
- **Omitted input (`detect`), interactive.** Present one consolidated
  in-conversation confirmation listing every detected companion's status and
  recommended default (`yes` if `detected: installed`, `no` if `detected: absent`).
  This is the model pausing to ask the user in the conversation, not a Bash `read`.
  Resolve each companion from the user's reply. Record `via: prompt-confirmed` when
  the user accepts the recommended default, `via: prompt-overridden` when the user
  chooses the opposite.
- **Omitted input (`detect`), headless fallback.** Where no user turn is available,
  do not hang on the prompt: resolve `detected: installed` to `yes` and
  `detected: absent` to `no`, and record `via: auto-detect-no-prompt`.

Thread the resolved `yes`/`no`, never the raw `detect`, into the inputs file. The
engine writes nothing for a companion resolved `no`.

## Conflict Resolution (judgment)

The engine never overwrites a different existing `agent` value. When
`.claude/settings.json` already holds a different, non-empty `agent` (a string with
non-whitespace content, or a non-string such as a number, bool, object, or array),
apply returns `status: blocked`, writes the conflict into the Output `conflicts:`
block, and writes nothing to any file. A missing, `null`, `""`, or whitespace-only
`agent` is absent: the engine classifies it `added` and writes the target value.

On a real conflict, surface it to the user and obtain explicit approval to
overwrite. Only then re-run apply with `agent_conflict_approved: "yes"`; the engine
classifies the agent `overwritten`, returns `status: ok`, and emits normal
`complete`/`updated` Output. Without approval the skill stays blocked and no file
changes. The navigator is the only route past a conflict. On `malformed` settings
(an unparseable existing file) the engine fails closed whatever
`agent_conflict_approved` says: approval authorizes an agent overwrite, never
clobbering a malformed file.

## Inputs JSON (apply)

Once every tri-state is resolved, author one inputs file (step 4) carrying the
resolved values and the detection facts, and pass its path to `apply`. Shape
(authoritative: the entrypoint header):

```json
{
  "project_root":   "<required> absolute repo root (resolve via git rev-parse --show-toplevel)",
  "agent_target":   "<optional> required agent value; default hivemind:overlord",
  "caveman":        "yes | no",
  "claude_mem":     "yes | no",
  "codex":          "yes | no",
  "seed_allowlist": "yes | no",
  "agent_conflict_approved": "yes | no",
  "companions": {
    "caveman@caveman":       { "detected": "...", "source": "...", "via": "..." },
    "claude-mem@thedotmack": { "detected": "...", "source": "...", "via": "..." },
    "codex@openai-codex":    { "detected": "...", "source": "...", "via": "..." }
  }
}
```

`agent_conflict_approved` is optional, default `"no"`; set it `"yes"` only per
Conflict Resolution. Any other value leaves the conflict blocked. The `companions` block carries `detected`/`source` from `detect`
and `via` from confirmation verbatim into the Output `companions:` block; an absent
`detected`/`source` (an explicit `yes`/`no` skips detection) is reported
`not-checked`.

## Procedure

1. Resolve the project root via `git rev-parse --show-toplevel`. Stop blocked if it
   is not a git repository or the path does not resolve.
2. **Detect.** Run the `detect` phase, skipping each companion whose input is an
   explicit `yes`/`no`.
3. **Resolve confirmation (judgment).** Resolve `caveman`, `claude_mem`, and `codex`
   per Interactive Confirmation.
4. **Author the inputs file** with the Write tool, per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern), at
   `.hivemind/seed-inputs-<token>.json`, where `<token>` is new for each invocation (a
   UTC timestamp plus a random part, such as `20260601T014132Z-a1b2c3`), in the Inputs
   JSON shape.
   If the Write call does not succeed, stop blocked per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
5. **Apply.** Execute (do not Read) the `apply` phase once:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/seed-hive/scripts/seed-hive.sh" apply .hivemind/seed-inputs-<token>.json
   ```
   It merges settings, guards the `.gitignore`/`.envrc`/hook/`## Validation` files,
   provisions claude-mem's `CLAUDE_CODE_PATH`, detects the test command, and emits the
   exact `## Output` block. It exits 0 even when it reports `status: blocked`: a
   conflict is a reported outcome, not a script error.
6. **Conflict gate (judgment).** On a `status: blocked` agent conflict, follow
   Conflict Resolution: on explicit user approval, re-author the inputs file at a
   fresh `<token>` path with `"agent_conflict_approved": "yes"` and re-run apply. On
   `malformed` settings, surface and stop; do not overwrite.
7. **Invoke `hivemind:creep-spread`** to generate a populated `CONTEXT.md` (or
   `CONTEXT-MAP.md` for multi-context repos). A skill cannot be invoked from bash
   (P5), so this step is the navigator's; the engine emits the
   `context_bootstrap: creep-spread: invoked` line on the assumption it runs here.
   creep-spread skips existing files itself.
8. **Present the Output.** Present the engine's emitted block, reflecting the
   creep-spread invocation and any conflict-approval recovery.

## Pointers

- Execute (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/seed-hive/scripts/seed-hive.sh`.
- Mechanism libs, each with its own contract header:
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/settings-merge.sh`,
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/file-guard.sh`,
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/claude-mem-path.sh`,
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/test-detect.sh`.

## Do Not

- write any settings key outside the engine's merge contract (the required keys,
  `hooks.SubagentStart` when `caveman` resolves to `yes`, and `permissions.allow`
  only when `seed_allowlist` = `yes`), or hand-edit settings.
- modify project files outside the engine's surface (`.claude/settings.json`,
  `.gitignore`, `.envrc`, `.claude/hooks/`, repo-root `CLAUDE.md`
  create-or-append-if-absent) and the files `hivemind:creep-spread` creates or
  modifies.
- install, scaffold, or invent a test harness; run the detected test command; or
  overwrite, reorder, or replace an existing documented test/validation command in
  repo-root `CLAUDE.md`. The engine only appends: a `## Validation` section counts
  as documented only when it carries a fenced command block; a heading-only stub counts as absent and
  gets the command; a section with prose but no command block gets the command
  appended after its prose, which is never replaced or dropped.
- modify `~/.claude-mem/settings.json` beyond the single `CLAUDE_CODE_PATH` key the
  engine provisions, only when `claude_mem` resolves to `yes`, the file exists, the
  key is empty/missing, and a `claude` binary resolves. Never overwrite a present
  value (a non-empty string, or any non-string such as a boolean, null, number,
  object, or array: all are reported `already set`), and never touch another key.
- remove or disable an existing `enabledPlugins` companion entry: detection only
  adds, and a present entry is kept and reported `already present` even if detection
  missed it.
- clobber or crash on a wrong-typed existing value at a required object-typed key
  (`enabledPlugins`, `pluginConfigs`, `hooks`, `permissions`) or the
  `permissions.allow` array: it is treated as absent and seeded add-if-absent.
- overwrite a conflicting `agent` value without explicit user approval.
- author the inputs file by any transport other than the Write tool; see
  `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
- proceed if the project root cannot be resolved.
- commit, push, or otherwise touch git state.
- Read or reconstruct the engine body; invoke it with the documented phase and
  argument.

## Output

The `apply` phase emits this block, less its `#` comment lines; the navigator
presents it. The schema and field values are the acceptance contract. When
`follow_up:` carries the restart line (emitted only on a fresh `set` of
`CLAUDE_CODE_PATH`), the navigator must surface it so the user restarts the
claude-mem worker, which may drop observations until then.

```text
status: complete | partial | blocked

project_root:
- [absolute path]

target_file:
- .claude/settings.json: created | updated | unchanged

gitignore:
- .gitignore: created | updated | already present

envrc:
- .envrc: created | updated | already present | skipped (caveman not enabled)

hooks:
- .claude/hooks/caveman-ultra-subagent.sh: created | already present | skipped (caveman not enabled)
- hooks.SubagentStart in settings.json: added | already present | skipped (caveman not enabled)

companions:
- caveman@caveman: detected: installed | absent | not-checked, source: manifest | cache | none | not-checked, resolved: yes | no, via: explicit-input | prompt-confirmed | prompt-overridden | auto-detect-no-prompt
- claude-mem@thedotmack: detected: installed | absent | not-checked, source: manifest | cache | none | not-checked, resolved: yes | no, via: explicit-input | prompt-confirmed | prompt-overridden | auto-detect-no-prompt
- codex@openai-codex: detected: installed | absent | not-checked, source: manifest | cache | none | not-checked, resolved: yes | no, via: explicit-input | prompt-confirmed | prompt-overridden | auto-detect-no-prompt

claude_mem_path:
- ~/.claude-mem/settings.json CLAUDE_CODE_PATH: set | already set | skipped (claude-mem not installed) | skipped (claude binary not found) | skipped (malformed json) | skipped (claude_mem not enabled)

follow_up:
- Restart claude-mem (or its background worker) so the new CLAUDE_CODE_PATH takes effect; until then it may drop observations. | None

keys_applied:
- enabledPlugins["hivemind@brenpike"]: added | already present
- agent: added | already present | unchanged | overwritten
- enabledPlugins["caveman@caveman"]: added | already present | resolved no
- enabledPlugins["claude-mem@thedotmack"]: added | already present | resolved no
- enabledPlugins["codex@openai-codex"]: added | already present | resolved no
- pluginConfigs["caveman@caveman"]: added | already present | resolved no

permissions_allow:
- [rule string]: added | already present
- not requested
# one line per template rule when seed_allowlist = yes; `not requested` when no

context_bootstrap:
- creep-spread: invoked

test_command:
- repo-root CLAUDE.md ## Validation: recorded <commands> | already documented | none detected (recommend manual)

conflicts:
- [key]: existing value vs required value
- None

issues:
- [issue]
- None
```

Use the Worker Report — Blocked schema from `${CLAUDE_PLUGIN_ROOT}/governance/report-format.md` (Worker Report — Blocked) for blocked states.
