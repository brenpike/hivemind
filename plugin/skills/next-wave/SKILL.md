---
name: next-wave
description: Computes the ready wave of independent plan steps for the intra-run parallel-wave implement loop, reading the run ledger and emitting the step ids to dispatch this iteration. Use when computing the next wave or ready-set of plan steps.
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/next-wave/scripts/next-wave.sh *)
  - Read
shell: bash
---

# Next Wave

Compute the next dispatchable WAVE of independent plan steps for the intra-run
parallel-wave implement loop. The wave is the maximal, plan-order, file-disjoint subset of
the READY steps — the steps whose dependencies are already done and whose file scopes do
not collide — so the overlord session can fan them out concurrently, and the wave runs serially
when the plan graph forces it. The deterministic engine is the committed,
READ-ONLY script `${CLAUDE_PLUGIN_ROOT}/skills/next-wave/scripts/next-wave.sh`; this body is
a thin navigator that runs the script once and interprets its routing. The engine mutates
NOTHING — it reads the ledger, derives the wave, and prints a routing decision.

## Required Inputs

The caller resolves and passes this; the skill does not invent it.

- `run_id`: the run identifier (from `init-run-ledger`). It is the ONLY caller identity. The
  engine DERIVES the ledger from it — `<git-root>/.hivemind/runs/<run_id>/state.json` — and
  routes the read through the shared containment guard. The caller passes NO ledger PATH, so a
  caller can never point the engine at an arbitrary file.

## How the wave is derived

The engine reads the run ledger (schema: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`)
and computes:

- **DONE SET** — the union of every `events[].outputs.completed_steps[]` (a flat list of
  step-id strings). Done-ness lives in the EVENT log, never in `plan.steps[].status` (which
  stays planner-emitted `pending`) — the engine does not read that status field. Done-ness is
  scoped to the CURRENT plan epoch (`.plan.epoch`): a `completed_steps` credit recorded under
  a PRIOR plan generation never satisfies the current plan, so positional STEP-NNN ids may be
  safely reused across replans without a prior generation's credit skipping the new step.
- **READY** — steps NOT in done whose `depends_on` is a subset of done.
- **WAVE** — the greedy, plan-order, maximal subset of READY that is pairwise disjoint under
  EXACT string match over each step's CANONICAL declared file-scope paths. A path is
  comparable only if it is relative, `/`-splits into non-empty components, no component is
  `.` or `..`, no component carries a glob metacharacter (`*`, `?`, `[`), and the path has no
  leading/trailing slash and no `//`. A step whose scope is missing, empty, non-array, or
  contains any path that fails this grammar is classified CONFLICTS-WITH-ALL and runs ALONE
  (serial), never fanned out — this is FAIL-CLOSED and conservative-safe: run-alone is always
  correct and never strands a step. Filesystem-level aliasing (symlinks, case-insensitive
  filesystems) is a documented residual outside this grammar, deferred to a tracked issue
  rather than guarded against here.

A single ready step yields a wave of one (serial behavior); `all_done` is true only when the
done set covers every step.

## Procedure

1. **Execute the script** with one Bash call, passing the run_id:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/next-wave/scripts/next-wave.sh <run_id>
   ```
   EXECUTE (do not Read) the script — it owns the deterministic read -> derive -> emit and the
   ledger containment/coherence guards. It reads the ledger and writes nothing.

2. **Interpret the result.** Exit 0: the script printed YAML routing lines on stdout —
   ```yaml
   all_done: true|false
   wave: [STEP-00X, STEP-00Y]
   remaining: <N>
   ```
   Dispatch exactly the step ids in `wave` this iteration; when `all_done: true` the wave is
   `[]` and every step is done. Exit 1: the script printed `blocker: <reason>` on stderr and
   read-only-failed (empty/cyclic/invalid plan, a step `id` or `depends_on` entry that fails the
   safe-id charset — a reader-side belt over pre-existing seeded/resume ledgers — missing/invalid
   ledger, or a containment rejection) — surface it and stop.

## Pointers

- EXECUTE (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/next-wave/scripts/next-wave.sh`.
- Ledger schema: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own — its steps are tool calls only.
- The only action is the Bash script call (step 1); the engine performs no writes.
- The procedure ends at the step 1 Bash script call, which hands the routing data back
  to the caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = caller dispatches the returned `wave`; routing data is on stdout.
  Exit 1 = blocked; the reason is on stderr and nothing was mutated.

## Do Not

- supply or guess the done set, ready set, or wave — the script derives them directly from
  the ledger's event log and plan graph.
- read `plan.steps[].status` to infer done-ness — done-ness lives in
  `events[].outputs.completed_steps[]`.
- dispatch any step id not present in the returned `wave`.
- mutate the ledger or any file — this engine is read-only.
- commit, push, or open a PR.
- Read or reconstruct the script body — invoke it with the documented `run_id`.
