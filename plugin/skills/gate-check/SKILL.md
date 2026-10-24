---
name: gate-check
description: Finds the next gate the pull request still needs on the standard-delivery state machine, reading the run ledger, HEAD and the gate contract, and emitting the gate_check outcome. Use when a run reaches the gate_check state.
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/gate-check/scripts/gate-check.sh *)
  - Read(~/.claude/plugins/cache/brenpike/hivemind/**)
shell: bash
---

# Gate Check

Find the next gate the pull request still needs on the standard-delivery state machine. The
rule this skill applies lives in `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (PR
Requirements). The deterministic engine is the committed, READ-ONLY script
`${CLAUDE_PLUGIN_ROOT}/skills/gate-check/scripts/gate-check.sh`; this body is a thin navigator
that runs the script once and hands back its routing. The engine mutates NOTHING.

## Required Inputs

The caller resolves and passes this; the skill does not invent it.

- `run_id`: the run identifier (from `init-run-ledger`). It is the ONLY caller identity. The
  engine DERIVES the ledger from it, `<git-root>/.hivemind/runs/<run_id>/state.json`, and
  routes the read through the shared containment guard. The caller passes NO path.

## How the outcome is derived

The engine reads the gate contract beside it,
`${CLAUDE_PLUGIN_ROOT}/skills/gate-check/scripts/gate-contract.json`: the gates in order
(version bump, validation, local review), the transitions that hold each gate, the transition
that skips local review, and the rerun bound. It reads the run ledger (schema:
`${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`) for the current plan epoch only, takes
each gate's held commit from the top-level `head` of its latest holding event, and compares it
with HEAD. It refuses a working tree with any uncommitted or untracked path.

## Procedure

1. **Execute the script** with one Bash call, passing the run_id:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/gate-check/scripts/gate-check.sh <run_id>
   ```
   EXECUTE (do not Read) the script. It reads the ledger, HEAD and the working tree, and
   writes nothing.

2. **Interpret the result.** Exit 0: the script printed YAML routing lines on stdout:
   ```yaml
   outcome: version_due|validation_due|review_due|all_held|rerun_limit
   head: <full object id of HEAD>
   reruns: <N>
   max_reruns: <N>
   ```
   The caller records `outcome` as the `gate_check` state result. On `all_held`, the caller
   passes `head` as `expect_commit` to `hivemind:open-plan-pr`. Exit 1: the script printed
   `blocker: <reason>` on stderr; the caller records `blocked` as the state result.

## Pointers

- EXECUTE (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/gate-check/scripts/gate-check.sh`.
- Gate rule: `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (PR Requirements).
- Ledger schema: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own — its steps are tool calls only.
- The only action is the Bash script call (step 1); the engine performs no writes.
- The procedure ends at the step 1 Bash script call, which hands the routing data back
  to the caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = caller records the returned `outcome`; routing data is on stdout.
  Exit 1 = blocked; the reason is on stderr and nothing was mutated.

## Do Not

- guess, override or re-derive the outcome — record the one the script printed.
- mutate the ledger, the working tree or any file — this engine is read-only.
- commit or push.
- Read or reconstruct the script body — invoke it with the documented `run_id`.
