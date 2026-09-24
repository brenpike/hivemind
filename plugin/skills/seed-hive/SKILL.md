---
name: seed-hive
description: Applies required .claude/settings.json keys to make the overlord the session default agent and gitignores .hivemind/ and .claude/worktrees/. Use when adopting the plugin in a new project or repairing plugin setup.
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/seed-hive/scripts/seed-hive.sh *)
  - Bash(git rev-parse *)   # navigator resolves the project root (git rev-parse --show-toplevel) before calling detect/apply — Procedure step 1
  - Read
  - Write   # inert inputs-file only: authors per-invocation-unique path .hivemind/seed-inputs-<token>.json; see security-policy.md "Inert Inputs-File Navigator Pattern" + ADR-0017/0020
  - Skill   # hivemind:creep-spread orchestration step — a skill cannot be invoked from bash (P5)
shell: bash
---

# Setup Project

Apply the hivemind plugin's required project settings to `.claude/settings.json` so the
session default agent becomes `hivemind:overlord`, gitignore the runtime dirs, and bootstrap
project context. The deterministic engine is the committed two-phase script
`${CLAUDE_PLUGIN_ROOT}/skills/seed-hive/scripts/seed-hive.sh`; this body is a navigator that
OWNS the judgment — companion detection reasoning, interactive confirmation, and conflict
approval — then authors a single resolved-values inputs file and runs the script once. The
script performs NO judgment: given resolved `yes`/`no` inputs it is purely deterministic.

This skill is the user-invoked alternative to manually editing `.claude/settings.json` per
the README. It is not auto-invoked by the plugin; the user must explicitly request it.

Rules: ADR-0020 (engine is the committed two-phase script; the navigator resolves every
tri-state input before calling apply). The mechanism moved to four sourced `_shared` libs and
the entrypoint, each carrying its own P2 contract header:

- settings-merge.sh — the `.claude/settings.json` required-key merge, the frozen
  `permissions.allow` template (single-source DATA), and the `agent`-conflict detector.
- file-guard.sh — the append-if-absent kernel for the `.gitignore`, `.envrc`, caveman-hook,
  and `## Validation` text guards (idempotency mechanics live here).
- claude-mem-path.sh — the never-clobber, malformed-safe `CLAUDE_CODE_PATH` provisioning into
  claude-mem's OWN `~/.claude-mem/settings.json`.
- test-detect.sh — the root-level ecosystem signal→command projector that feeds the
  `## Validation` section guard.

This body references those by intent; it does NOT re-narrate their mechanics.

## Quick Reference

Before:
- [ ] Project root resolved via `git rev-parse --show-toplevel`
- [ ] `.claude/settings.json` read or default `{}` established
- [ ] No conflicting `agent` value exists (or user approved override)
- [ ] `.gitignore` read or default absence noted
- [ ] Companions detected (`caveman@caveman`, `claude-mem@thedotmack`, `codex@openai-codex`) via the `detect` phase for any input left at `detect`
- [ ] Companions confirmed/overridden by user (or auto-enabled in headless mode) for any input left at `detect`
- [ ] If `claude_mem` resolves to `yes`: `~/.claude-mem/settings.json` existence checked and (if present) read

After:
- [ ] Required keys applied to `.claude/settings.json`
- [ ] Existing keys preserved
- [ ] Output uses lowercase snake_case field names
- [ ] `.hivemind/` and `.claude/worktrees/` entries ensured in `.gitignore`
- [ ] If `caveman` resolves to `yes`: `.envrc` contains `CAVEMAN_DEFAULT_MODE=ultra`, `pluginConfigs` for caveman applied, SubagentStart hook configured
- [ ] If `claude_mem` resolves to `yes` and `~/.claude-mem/settings.json` present with empty/missing `CLAUDE_CODE_PATH`: key set to dynamically-resolved `claude` path (only that key), and user told to restart the worker
- [ ] `hivemind:creep-spread` invoked
- [ ] Test command detected and recorded under `## Validation` in repo-root `CLAUDE.md` if absent (or `already documented` / `none detected`)

## When to Use

- new project adopting the plugin
- existing project missing the `agent` default
- repairing settings after manual edits broke routing
- after a plugin upgrade that ships new `permissions.allow` template rules — the template
  merges into `.claude/settings.json` ONLY when this skill RUNS, and a plugin upgrade never
  re-merges a consumer's settings, so an already-seeded project receives nothing until this
  skill is re-run. The merge is idempotent append-if-absent, so re-running is always safe and
  preserves existing entries.

Do not use this skill to change unrelated settings or to write keys not listed in the
engine's merge contract.

## Required Inputs

None. The navigator resolves the project root via `git rev-parse --show-toplevel` and passes
it to the engine. Stop blocked if not a git repository or path resolution fails.

## Optional Inputs

These are tri-state knobs the navigator RESOLVES to a final `yes`/`no` before calling apply:

- `caveman`: `yes`|`no`|`detect` (default `detect`) — enable `caveman@caveman`, configure
  `pluginConfigs`, set up `.envrc`, and install the SubagentStart hook for caveman ultra mode.
  When omitted (`detect`), the navigator runs detection + confirmation (below); an explicit
  `yes`/`no` skips both and is honored verbatim.
- `claude_mem`: `yes`|`no`|`detect` (default `detect`) — enable `claude-mem@thedotmack` and
  provision its `CLAUDE_CODE_PATH`. Same tri-state resolution as `caveman`.
- `codex`: `yes`|`no`|`detect` (default `detect`) — enable `codex@openai-codex`. Same
  tri-state resolution.
- `seed_allowlist`: `yes`|`no` (default `yes`) — merge a recommended least-privilege
  `permissions.allow` template into `.claude/settings.json`. NOT detected and NOT interactive
  — an explicit flag only, threaded into apply verbatim. The template DATA and its
  union/append-if-absent merge semantics live in settings-merge.sh.

## Companion Detection (judgment)

For each companion input left at `detect` (`caveman@caveman`, `claude-mem@thedotmack`,
`codex@openai-codex`), run the engine's `detect` phase to obtain the FACTS, then REASON about
them. An explicit `yes`/`no` input needs no detection for that companion.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/seed-hive/scripts/seed-hive.sh detect <project_root>
```

`detect` is READ-ONLY (it mutates nothing) and emits one JSON object on stdout:

```json
{
  "companions": {
    "caveman@caveman":       { "detected": "installed"|"absent", "source": "manifest"|"cache"|"none" },
    "claude-mem@thedotmack": { "detected": "...", "source": "..." },
    "codex@openai-codex":    { "detected": "...", "source": "..." }
  }
}
```

The engine owns the resolution mechanics (manifest authoritative via `jq` → cache-dir
fallback → none, honoring `$HOME`); the navigator consumes the `detected`/`source` facts to
build its confirmation prompt and to populate the Output `companions:` block. Carry each
companion's `detected` and `source` forward into the inputs file you author for apply.

## Interactive Confirmation (judgment)

After Companion Detection, resolve each `detect` companion to a final `yes`/`no`:

- **Explicit input (`yes`/`no`).** Resolves to that value verbatim. No detection, no prompt.
  Record `via: explicit-input`.
- **Omitted input (`detect`) — interactive.** Present ONE consolidated in-conversation
  confirmation message listing every detected companion's status and recommended default
  (recommended `yes` if `detected: installed`, recommended `no` if `detected: absent`). This
  is the model PAUSING to ask the user in the conversation — NOT a Bash `read`. Read the
  user's reply and resolve each companion to its confirmed or overridden value. Record
  `via: prompt-confirmed` when the user accepts the recommended default, `via: prompt-overridden`
  when the user chooses the opposite.
- **Omitted input (`detect`) — headless fallback.** When the skill is invoked where no user
  turn is available (no interactive conversation), do NOT hang on the prompt. Auto-enable
  detected companions (`detected: installed` → resolved `yes`), skip absent ones
  (`detected: absent` → resolved `no`), and record `via: auto-detect-no-prompt`.

The resolved `yes`/`no` value — never the raw `detect` input — is what you thread into the
inputs file. The engine writes nothing for a companion resolved `no`.

## Conflict Resolution (judgment)

The engine never overwrites a different existing `agent` value: when `.claude/settings.json`
already holds a DIFFERENT, non-empty `agent` (a real string with non-whitespace content, or a
non-string value such as a number, bool, object, or array), apply returns `status: blocked`,
writes the conflict into the Output `conflicts:` block, and writes NOTHING to any file. An
existing `agent` that is missing, `null`, an empty string `""`, or a whitespace-only string
normalizes to ABSENT — the engine classifies it `added` and writes the target value as a
normal write, not a conflict. The navigator OWNS the recovery for real conflicts — surface the
conflict to the user and obtain EXPLICIT approval to overwrite. On explicit user approval, the
navigator re-runs apply with `agent_conflict_approved: "yes"` authored into the inputs file;
the engine then classifies the agent as `overwritten`, returns `status: ok`, and produces
normal `complete`/`updated` Output. Without approval the skill stays blocked and no file is
changed. There is no silent-overwrite path; the navigator is the ONLY route that may proceed
past a conflict, and only with the user's go-ahead. On `malformed` settings (unparseable
existing file) the engine fails closed regardless of `agent_conflict_approved` — approval
authorizes an agent overwrite, never clobbering a malformed file.

## Inputs JSON (apply)

Once every tri-state is resolved, author ONE inputs file (via the Write tool) at the
PER-INVOCATION-UNIQUE gitignored path `.hivemind/seed-inputs-<token>.json` carrying the
RESOLVED values and the detection facts, and pass that path to the `apply` phase. Every value
crosses the transport as data only — the engine reads each field with `jq` into a shell
variable and never interpolates it into shell or jq program source. What the engine does with
a field after that read is the field's own contract. Shape (authoritative: the entrypoint
header):

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

`caveman` / `claude_mem` / `codex` carry the RESOLVED `yes`/`no` (detect+confirm already
done); `seed_allowlist` is the explicit flag (default `yes`). `agent_conflict_approved` is
OPTIONAL, default `"no"`; the navigator sets it `"yes"` ONLY when re-running apply after the
user EXPLICITLY approved overwriting a conflicting existing `agent` value; absent or any other
value leaves the conflict blocked and the file unchanged; it NEVER authorizes clobbering a
malformed settings file. The `companions` block echoes the detection facts you gathered —
`detected`/`source` from `detect`, `via` from the confirmation resolution — verbatim into the
Output `companions:` block; an absent `detected`/`source` field (explicit `yes`/`no` skips
detection) is reported `not-checked`.

## Procedure

1. Resolve project root via `git rev-parse --show-toplevel`. Stop blocked if not a git
   repository or path resolution fails.
2. **Detect.** Run the `detect` phase for the facts. Skip per-companion when its input is an
   explicit `yes`/`no`.
3. **Resolve confirmation (judgment).** Apply Interactive Confirmation to resolve `caveman`,
   `claude_mem`, and `codex` to final `yes`/`no` (interactive prompt, headless fallback, or
   explicit-input verbatim).
4. **Author the inputs file** via the Write tool at `.hivemind/seed-inputs-<token>.json`, with
   the resolved values and detection facts matching the Inputs JSON shape above. GENERATE an
   invocation-unique `<token>` for the filename (a UTC timestamp plus a random component, such
   as `20260601T014132Z-a1b2c3`) so two concurrent same-checkout sessions author DISTINCT inputs
   files and cannot clobber each other's payload between the Write and the script exec.
   `.hivemind/` is gitignored. Write performs no shell parsing, and the engine reads each
   field with `jq` into a shell variable, so no value is interpolated into shell or jq program
   source. A FIRST-EVER install still prompts once for this write, because the permission
   allow rule
   covering `.hivemind/seed-inputs-*.json` is itself seeded by this very skill; that is an
   accepted bootstrap ordering, not a defect — the rule lands for repair re-runs and every
   later seeded project.
   If the Write tool is ABSENT from this session, STOP BLOCKED per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern →
   Transport Degradation Is a Hard Stop).
5. **Apply.** Run the `apply` phase once:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/seed-hive/scripts/seed-hive.sh apply .hivemind/seed-inputs-<token>.json
   ```
   EXECUTE (do not Read) the script. It composes the four libs to merge settings, guard the
   `.gitignore`/`.envrc`/hook/`## Validation` files, provision claude-mem's `CLAUDE_CODE_PATH`,
   detect the test command, and emit the EXACT `## Output` block below. apply exits 0 even when
   it reports `status: blocked` — the conflict is a REPORTED outcome, not a script error.
6. **Conflict gate (judgment).** If apply reported `status: blocked` on an `agent` conflict,
   follow Conflict Resolution: surface it, obtain explicit user approval, then re-author the
   inputs file at a fresh `<token>` path with `"agent_conflict_approved": "yes"` and re-run apply. On `malformed`
   settings (unparseable existing file) the engine fails closed — surface and stop; do not
   overwrite regardless of `agent_conflict_approved`.
7. **Invoke `hivemind:creep-spread`** to analyze the project and generate a populated
   `CONTEXT.md` (or `CONTEXT-MAP.md` for multi-context repos). A skill cannot be invoked from
   bash (P5), so this is the navigator's own orchestration step; the engine emits the
   `context_bootstrap: creep-spread: invoked` Output line as a constant on the assumption you
   run it here. creep-spread has its own skip guard for existing files.
8. **Assemble + present the Output.** The engine's emitted block IS the Output schema below;
   present it, reflecting the creep-spread invocation and (if reached) the conflict-approval
   recovery.

## Pointers

- EXECUTE (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/seed-hive/scripts/seed-hive.sh`.
- Mechanism libs (referenced by intent, not re-narrated):
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/settings-merge.sh`,
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/file-guard.sh`,
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/claude-mem-path.sh`,
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/test-detect.sh`.

## Do Not

- write any settings key outside the engine's merge contract (the required keys, plus
  `hooks.SubagentStart` when `caveman` resolves to `yes`, and `permissions.allow` ONLY when
  `seed_allowlist` = `yes`) — the engine owns the contract; do not hand-edit settings.
- modify project files outside the engine's surface (`.claude/settings.json`, `.gitignore`,
  `.envrc`, `.claude/hooks/`, repo-root `CLAUDE.md` create-or-append-if-absent) and files
  created or modified by `hivemind:creep-spread`.
- install, scaffold, or invent a test harness; run the detected test command; or overwrite,
  reorder, or replace an existing documented test/validation command in repo-root `CLAUDE.md`
  — the engine detects and records append-if-absent only; a `## Validation` section counts as
  already-documented only when it carries a real command body (a fenced block under the
  heading); a heading-only stub with no body is treated as absent and the detected command is
  appended; a `## Validation` section that contains prose but no command body has the command
  APPENDED after the existing prose — existing prose is preserved, never replaced or dropped.
- modify `~/.claude-mem/settings.json` beyond the single `CLAUDE_CODE_PATH` key the engine
  provisions (and only when `claude_mem` resolves to `yes`, the file exists, the key is
  empty/missing, and a `claude` binary resolves); never overwrite an existing present value
  (a non-empty string, a non-string such as a boolean/null/number/object/array, or any other
  non-absent form — all are reported `already set` and left untouched), and never touch any
  other key.
- remove or disable an existing `enabledPlugins` companion entry — detection only ever adds;
  an entry already present is preserved and reported `already present` even if detection missed it.
- clobber or crash on a wrong-typed existing container at a required object-typed key
  (`enabledPlugins`, `pluginConfigs`, `hooks`, `permissions`) or the `permissions.allow` array
  — a present value that is not the expected object or array type is treated as the canonical
  absent/needs-seed shape and seeded add-if-absent; it is never clobbered and never causes a
  crash, mirroring the never-clobber posture documented for the top-level malformed settings
  object in Conflict Resolution above.
- overwrite a conflicting `agent` value without EXPLICIT user approval — the engine reports
  blocked, and the navigator may proceed only after the user approves.
- author the inputs file via any transport other than the Write tool — no heredoc, no shell
  redirection, no inline python/node script. A missing Write tool is a hard stop, not a
  workaround; see `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md`
  (Transport Degradation Is a Hard Stop).
- proceed if the project root cannot be resolved.
- commit, push, or otherwise touch git state.
- Read or reconstruct the engine body — invoke it with the documented phase + argument.

## Output

The `apply` phase emits this block verbatim; the navigator presents it. The schema and field
values are the acceptance contract. When the `follow_up:` block carries the restart line (a fresh
`set` of CLAUDE_CODE_PATH), the navigator MUST surface it to the user so they restart the
claude-mem worker — until they do, the worker may drop observations.

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
# `via: explicit-input` is reported whenever detection was skipped for that companion (an explicit
# `yes`/`no` input, so no `detect`/confirm ran); the other `via` tokens reflect a detected companion's resolution path.
- caveman@caveman: detected: installed | absent | not-checked, source: manifest | cache | none | not-checked, resolved: yes | no, via: explicit-input | prompt-confirmed | prompt-overridden | auto-detect-no-prompt
- claude-mem@thedotmack: detected: installed | absent | not-checked, source: manifest | cache | none | not-checked, resolved: yes | no, via: explicit-input | prompt-confirmed | prompt-overridden | auto-detect-no-prompt
- codex@openai-codex: detected: installed | absent | not-checked, source: manifest | cache | none | not-checked, resolved: yes | no, via: explicit-input | prompt-confirmed | prompt-overridden | auto-detect-no-prompt

claude_mem_path:
- ~/.claude-mem/settings.json CLAUDE_CODE_PATH: set | already set | skipped (claude-mem not installed) | skipped (claude binary not found) | skipped (malformed json) | skipped (claude_mem not enabled)

follow_up:
- Restart claude-mem (or its background worker) so the new CLAUDE_CODE_PATH takes effect; until then it may drop observations. | None
# the restart line is emitted ONLY when claude_mem_path resolves to `set` (a fresh write); `None` for `already set` / any `skipped (...)` / claude_mem not enabled. The navigator MUST surface this line to the user.

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
# one line per template rule when seed_allowlist = yes (the default); `not requested` when seed_allowlist = no

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

Use the Worker Report — Blocked schema from `${CLAUDE_PLUGIN_ROOT}/governance/report-format.md` for blocked states.
