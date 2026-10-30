---
name: spawn-brood
description: Dispatches parallel overlord sessions as a brood, spawning N Claude Code instances in separate git worktrees via tmux and writing the brood manifest. Use when spawning a brood or running parallel strains.
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/spawn-brood/scripts/spawn-brood.sh" *)
  - Read(~/.claude/plugins/cache/brenpike/hivemind/**)
  - Edit(.hivemind/spawn-inputs.*.json)
shell: bash
---

# Spawn Brood

Dispatch parallel overlord sessions as a brood. Spawn N Claude Code instances in
separate git worktrees via tmux, inject task descriptions, and write the brood
manifest. The deterministic engine is the committed script
`${CLAUDE_PLUGIN_ROOT}/skills/spawn-brood/scripts/spawn-brood.sh`; this body is a
navigator that builds the inputs file and runs the script once.

Rules: `GIT-01` (no trunk commits).

## Quick Reference

Before:
- [ ] `strains`, `base`, `overlap_risk`, `overlap_details` provided (no `brood_id` — script generates it).
- [ ] `tmux`, `claude`, and `jq` are installed (the script blocks on any missing).
- [ ] `base` resolves to a real commit (the script verifies this once, up front).
- [ ] No tmux session or worktree path collides (the script pre-flights both; names
      are brood-id-namespaced, so concurrent broods on the same checkout are supported).

After:
- [ ] Script printed `brood_id: <id>` on stdout — the coordinator captures the generated
      brood-id for monitoring (hatchery references its own brood-id).
- [ ] Brood manifest written to `.hivemind/broods/<brood-id>/manifest.json` as
      `manifest_version: 4` (JSON integer) — carrying a top-level `hatchery`
      block (`run_id`, `ledger`, `workflow`) and a per-strain `run` block
      (`suggested_id`, `workflow_hint`) alongside the v1 fields. No per-strain
      `branch` field is written; readers treat an absent branch as `MISSING`.
      Parsed exclusively by jq (machine consumer); no YAML back-compat.
- [ ] Each strain has a worktree created DETACHED at the resolved `base` commit
      (no `strain/<brood-id>/<short>` branch is created; the child's own planner
      names and creates its working branch), a detached tmux session
      `<brood-id>-<short>` running `claude --permission-mode auto`, and its
      injected `task.md`. In auto mode the classifier launches the child's workflow
      with no prompt, so the child runs on the script engine. `task.md` emits the
      data-boundary preamble FIRST, THEN a data-only YAML block: `parent.kind`,
      `parent.brood_id`, `strain.id`, `strain.name`, `run.suggested_id`,
      `run.workflow_hint` (a non-binding hint, passed through AS-IS),
      `working_branch.base` and `task.description`. It carries no instructions
      list and no field naming a scratch branch, a ledger path or a trunk-freshness
      override, because the harness relays it to every workflow agent the child runs.
      A pre-launch identity guard runs before each strain's session is started:
      if the strain's `task.md` `strain.id` would not match its `run.suggested_id`,
      the strain is refused (failed-pre-launch) and never spawned. A pre-launch
      facts guard runs too: a strain whose new worktree already holds
      `.hivemind/facts` (a base that tracks it) is refused (failed-pre-launch)
      and its worktree removed, so every facts file spawn or brood-status reads
      was written after launch. The engine
      submits each task during a shared Pass-2 readiness round-robin:
      load-buffer, paste-buffer, settle, then a single Enter, so the submit
      keystroke lands as a submit instead of racing the paste. After all strains
      have been submitted in Pass 2, a separate Pass 3 runs per-strain turn-start
      verification — each strain's verify/resend poll runs on its OWN independent
      deadline (`STARTED_EVIDENCE_TIMEOUT`, default 180 s), decoupled from every
      other strain's readiness budget, so one slow child cannot block another.
      The verifier polls the child worktree for started-evidence: a valid run-ledger
      `state.current` (the confined ledger read) OR a gather-facts output file
      (`.hivemind/facts/facts-*.json`, written by a script-engine child, which keeps
      no run ledger). If no started-evidence is observed it resends Enter
      (idempotent — task text is already buffered, never re-pasted) as a
      periodic nudge within the grace window. On grace exhaustion the outcome
      depends on tmux session liveness: if the session is ALIVE the strain is
      classified `starting` (alive but not yet started) in the manifest; only a
      DEAD session yields `failed` (failed-to-launch). `starting` is a
      non-failed observable rendered by `hivemind:brood-status` as such;
      only `failed` is the error state in brood-status derivation. Verification
      reads on-disk ground truth — capture-pane is not used. Whether a child
      actually started is also observed independently by `hivemind:brood-status`
      from the same two sources (ledger or facts file present => `running`,
      neither => `starting`), not only by spawn-brood.
      After Pass-3 completes and BEFORE manifest emission, a FINAL reconciliation
      sweep re-probes every `starting` strain once: a strain whose tmux session
      died in the Pass-3 tail is reclassified `failed` (contributing to exit 1),
      and a strain that reached started-evidence (ledger or facts file) in the
      tail is promoted to `running` — tightening the spawn exit code to
      end-of-spawn liveness.
- [ ] Remote control: after the manifest is written, on both the exit-0 and
      exit-1 paths, the script runs the `hivemind:enable-brood-remote` engine with
      `--only <short>...` for exactly the strains whose status is `running`, so
      each receives `/rc <short>`. It never triggers an unfiltered fan-out and
      makes no call when no strain is running. Each engine output line is printed
      to stdout prefixed `remote: `. Each `starting` strain gets one
      `remote: skipped: <short> (not started when spawn ended; ask for enable-brood-remote later)`
      line; a `failed` strain gets none. An engine blocker or failure prints a
      `remote:` warning line and never changes the manifest or the exit code.
      Remote control needs a claude.ai login and an accepted one-time
      remote-control confirmation; otherwise the child shows that confirmation
      until the user attaches.
- [ ] `.claude/worktrees/` is excluded from git (the script self-guards).
- [ ] Final action is the Bash script call. Exit 0 = brood spawned successfully
      (all strains `running`, OR all non-running strains are `starting` — a slow
      cold boot is not a failure); exit 1 = pre-flight blocker OR at least one
      strain is genuinely `failed` (dead tmux session, or a pre-launch refusal
      by the identity guard or the facts guard). `starting` strains do NOT contribute to `failed_count`
      and do NOT cause exit 1.

The manifest is a registry/coordination artifact, NOT the source of truth for
child workflow state — that lives in each child's own JSON run ledger. The
`hatchery.ledger` path only POINTS at the hatchery ledger; this skill never
creates a child or hatchery ledger. Full shape and status-derivation rules:
`${CLAUDE_PLUGIN_ROOT}/references/brood-ledger-model.md`.

## Required Inputs

The caller resolves and passes these; the skill does not resolve them.

- `strains`: array of `{name, description}` — one element per cerebrate
  `Strains` plan-artifact entry. Each strain MAY also carry an optional
  `workflow_hint` (a non-binding suggestion for the child's router; defaults to
  `standard-delivery` when omitted). Per-strain `branch` is NOT supplied —
  no strain branch is created.
- `base`: resolved trunk/base branch; each strain worktree is created detached
  at its commit.
- `overlap_risk`: `low | medium | high`.
- `overlap_details`: planner overlap-assessment text.
- `hatchery` (OPTIONAL): `{run_id, workflow}` for the coordinator's own run
  ledger. `run_id` defaults to `<brood_id>-hatchery`; `workflow` defaults to
  `hatchery-dispatch`. These only POINT at the hatchery ledger the coordinator
  owns — the script never creates it.

`brood_id` is NOT supplied — the script generates it internally as
`brood-<uuidv4>` and prints it on stdout.

## Procedure

1. **Build the inputs object** in your reasoning from the Required Inputs.
   Exact shape:

   ```json
   {
     "base": "<resolved trunk/base branch>",
     "overlap_risk": "low | medium | high",
     "overlap_details": "<planner overlap-assessment text>",
     "hatchery": {
       "run_id": "<optional; defaults to <brood_id>-hatchery>",
       "workflow": "<optional; defaults to hatchery-dispatch>"
     },
     "strains": [
       {
         "name": "<strain name>",
         "description": "<task description — may be GitHub-issue-sourced>",
         "workflow_hint": "<optional; defaults to standard-delivery>"
       }
     ]
   }
   ```

   Field rules:
   - `strains` MUST be a non-empty array — a zero-strain array is a blocker.
   - `base`, `overlap_risk`, `overlap_details` are required top-level scalars.
   - Do NOT include `brood_id` — the script generates it internally; any
     caller-supplied value is ignored.
   - Each strain requires `name` and `description`; `workflow_hint` is optional.
     Do NOT include a per-strain `branch` — no strain branch is created; any
     caller-supplied value is ignored.
   - `hatchery` is optional; both its fields default when omitted.
   - `name` is sanitized to `short` (`[a-z0-9-]`) for the worktree path
     (`.claude/worktrees/<brood-id>/<short>`) and tmux session
     (`<brood-id>-<short>`). Two names that sanitize to the same `short` are an
     in-set collision and a blocker.
   - Every value is data. None is interpolated into generated shell command source.

2. **Write the inputs file** via the Write tool to a per-invocation mktemp-unique
   staging path under `.hivemind/` (e.g. `.hivemind/spawn-inputs.<rand>.json`).
   Use the Write tool's `file_path` parameter for that unique path; set `content`
   to the JSON object from step 1. Write performs no shell parsing of the values.
   `spawn-brood.sh` reads the inputs file once into memory and reads each field
   from that copy with `jq` into a shell variable, so no field is interpolated
   into shell or jq program source. That is a transport
   property only: the description is carried on into the child's prompt as
   `task.description`, and the controls that bound that text are the compensating
   controls in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Brood Spawn
   Bypass-Mode Mitigation), not this write. Do NOT use a fixed singleton path —
   concurrent spawns must not clobber each other's staging file.
   If the Write tool is ABSENT from this session, STOP BLOCKED per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern →
   Transport Degradation Is a Hard Stop).

3. **Execute the script** with one Bash call, passing the staging path as `$1`:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/spawn-brood/scripts/spawn-brood.sh" <staging-path>
   ```
   EXECUTE (do not Read) the script — it owns every deterministic step: dependency
   checks, input validation, pre-flight collision/exclude/base checks, brood-id
   generation, per-brood state-dir creation, the inputs snapshot, the record
   write and the staging-file removal, three-pass
   spawn (create+launch, ready-poll+inject, then started-evidence verify),
   manifest emission, the remote-control step, and cleanup.

4. **Capture the generated brood-id** from stdout: on exit 0 the script prints
   `brood_id: <id>` then `manifest: <abs path>`. Capture `brood_id` — the
   coordinator needs it to monitor the brood (hatchery references its own brood-id).
   Exit 1: the script printed a `blocker: <reason>` (and, for partial failures,
   a `manifest: <abs path>` and `brood_id: <id>`) on stderr — surface it and stop.
   On both exits, any `remote:` lines on stdout report the remote-control step.

## Pointers

- EXECUTE (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/spawn-brood/scripts/spawn-brood.sh`.

## Tunables

Environment variables the caller may set before invoking the script to override
defaults. All tunables are fail-closed: a non-numeric or non-positive value is
rejected and the script exits with a blocker.

| Variable | Default | Purpose |
|---|---|---|
| `STARTED_EVIDENCE_TIMEOUT` | `180` (seconds) | Cold-boot grace period for an auto-mode child to write started-evidence: a run-ledger `state.current` or a gather-facts output file. Governs the Pass-3 per-strain verification deadline. Bare-Enter resends are periodic nudges within this window, not a fixed retry cap. A strain still without started-evidence when spawn ends stays `starting` and gets no remote control until the user asks for `hivemind:enable-brood-remote`. |

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own — its steps are tool calls only.
- The Write tool (step 2) is a permitted NON-FINAL tool call — it emits no chat text.
- The procedure ends at the step 3 Bash script call, which hands the routing data back
  to the caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = caller proceeds (all strains running, or all non-running strains are
  `starting`); routing data (`brood_id:`, `manifest:`, and `attach:` lines for
  running AND starting strains) is on stdout. Exit 1 = blocked; the reason is
  on stderr (pre-flight blocker or at least one genuinely `failed` strain).

## Do Not

- do not rely on `claude --worktree` for worktree creation — the script
  creates worktrees explicitly via `git worktree add --detach` at the base commit.
- commit, push, or open a PR.
- modify any product files.
- invent values for `strains`, `base`, `overlap_risk`, or `overlap_details` —
  the script exits 1 with a blocker if any are missing.
- supply `brood_id` or per-strain `branch` in the inputs — the script generates
  the brood-id and creates no strain branch; caller-supplied values are ignored.
- author the inputs file via any transport other than the Write tool — no heredoc, no shell
  redirection, no inline python/node script. A missing Write tool is a hard stop, not a
  workaround; see `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md`
  (Transport Degradation Is a Hard Stop).
- Read or reconstruct the script body — invoke it with the documented argument.
