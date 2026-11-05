---
name: spawn-brood
description: Spawns a brood of parallel overlord sessions in git worktrees via tmux and writes its manifest. Use to run strains.
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/spawn-brood/scripts/spawn-brood.sh" *)
  - Read(~/.claude/plugins/cache/brenpike/hivemind/**)
  - Edit(.hivemind/spawn-inputs.*.json)
shell: bash
---

# Spawn Brood

Dispatch parallel overlord sessions as a brood: N Claude Code instances in separate
git worktrees via tmux, each with its injected task, plus the brood manifest. The
engine is the committed script
`${CLAUDE_PLUGIN_ROOT}/skills/spawn-brood/scripts/spawn-brood.sh`; this body builds
the inputs file and runs the script once.

Rules: `GIT-01` (no trunk commits).

The manifest (`.hivemind/broods/<brood-id>/manifest.json`) is a registry and
coordination artifact, not the source of truth for child workflow state, which lives
in each child's own run ledger. This skill never creates a child or hatchery ledger:
`hatchery.ledger` only points at the hatchery ledger. Manifest shape, task.md
contents, launch and verification passes, and status derivation:
`${CLAUDE_PLUGIN_ROOT}/references/brood-ledger-model.md`.

## Required Inputs

The caller resolves and passes these; the skill does not resolve them.

- `strains`: array of `{name, description}`, one per cerebrate `Strains`
  plan-artifact entry. A strain may also carry an optional `workflow_hint` (a
  non-binding suggestion for the child's router; default `standard-delivery`).
- `base`: resolved trunk/base branch; each strain worktree is created detached at
  its commit.
- `overlap_risk`: `low | medium | high`.
- `overlap_details`: planner overlap-assessment text.
- `hatchery` (optional): `{run_id, workflow}` for the coordinator's own run ledger.
  `run_id` defaults to `<brood_id>-hatchery`; `workflow` defaults to
  `hatchery-dispatch`. They only point at the hatchery ledger the coordinator owns.

`brood_id` and per-strain `branch` are not inputs: the script generates the brood id
(`brood-<uuidv4>`) and prints it on stdout, and creates no strain branch (each child
names and creates its own working branch).

## Procedure

1. **Build the inputs object** in your reasoning from the Required Inputs. Exact
   shape:

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
   - `strains` must be a non-empty array; a zero-strain array is a blocker.
   - `base`, `overlap_risk`, `overlap_details` are required top-level scalars.
   - Each strain requires `name` and `description`; `workflow_hint` is optional.
   - `hatchery` is optional; both its fields default when omitted.
   - Include no `brood_id` and no per-strain `branch`; any caller-supplied value is
     ignored.
   - `name` is sanitized to `short` (`[a-z0-9-]`) for the worktree path
     (`.claude/worktrees/<brood-id>/<short>`) and tmux session
     (`<brood-id>-<short>`). Two names that sanitize to the same `short` are an
     in-set collision and a blocker.
   - Every value is data. None is interpolated into generated shell command source.

2. **Write the inputs file** with the Write tool, per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern):
   `file_path` = a per-invocation mktemp-unique staging path under `.hivemind/` (e.g.
   `.hivemind/spawn-inputs.<rand>.json`), never a fixed singleton path; `content` = the JSON
   object from step 1. The strain description reaches the child's prompt as
   `task.description`; the controls in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md`
   (Brood Spawn Bypass-Mode Mitigation) bound that text, not this Write.
   If the Write call does not succeed, stop blocked per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).

3. **Execute the script** with one Bash call, passing the staging path as `$1`:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/spawn-brood/scripts/spawn-brood.sh" <staging-path>
   ```
   Execute (do not Read) the script. It owns every deterministic step: dependency
   checks (`tmux`, `claude`, `jq`), input validation, pre-flight collision, exclude
   and base checks, brood-id generation, the per-brood state dir, the inputs record
   and staging-file removal, the three-pass spawn (create+launch, ready-poll+inject,
   started-evidence verify), manifest emission, the remote-control step, and cleanup.

4. **Capture the generated brood-id** from stdout: on exit 0 the script prints
   `brood_id: <id>` then `manifest: <abs path>`. Capture `brood_id`: the
   coordinator needs it to monitor the brood (hatchery references its own brood-id).
   Exit 1: the script printed a `blocker: <reason>` (and, for partial failures,
   a `manifest: <abs path>` and `brood_id: <id>`) on stderr; surface it and stop.
   On both exits, `attach:` lines name the live strain sessions and `remote:` lines
   report the remote-control step: the script turns on `/rc <short>` for exactly the
   `running` strains and prints one `remote: skipped:` line per `starting` strain,
   which gets remote control only when the user asks for
   `hivemind:enable-brood-remote`. A remote-control failure never changes the
   manifest or the exit code.

## Pointers

- Execute (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/spawn-brood/scripts/spawn-brood.sh`.

## Tunables

Environment variables the caller may set before invoking the script. Each is
fail-closed: a non-numeric or non-positive value is rejected with a blocker.

| Variable | Default | Purpose |
|---|---|---|
| `STARTED_EVIDENCE_TIMEOUT` | `180` (seconds) | Cold-boot grace period for an auto-mode child to write started-evidence: a run-ledger `state.current` or a gather-facts output file. Governs the Pass-3 per-strain verification deadline. Bare-Enter resends are periodic nudges within this window, not a fixed retry cap. A strain still without started-evidence when spawn ends stays `starting` and gets no remote control until the user asks for `hivemind:enable-brood-remote`. |

## Silence Discipline

Follow `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Silence Discipline). The step 2 Write
is the inputs-file Write; the procedure ends at the step 3 Bash call. Exit 0: all strains are
running, or every non-running strain is `starting` (a slow cold boot is no failure); the
routing data is the `brood_id:` and `manifest:` lines and the `attach:` lines for running and
starting strains. Exit 1: a pre-flight blocker or at least one genuinely `failed` strain (a
dead tmux session, or a pre-launch refusal).

## Do Not

- rely on `claude --worktree` for worktree creation; the script creates worktrees
  with `git worktree add --detach` at the base commit.
- commit, push, or open a PR.
- modify any product files.
- invent values for `strains`, `base`, `overlap_risk`, or `overlap_details`; the
  script exits 1 with a blocker if any are missing.
- supply `brood_id` or per-strain `branch` in the inputs.
- author the inputs file by any transport other than the Write tool; see
  `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
- Read or reconstruct the script body; invoke it with the documented argument.
