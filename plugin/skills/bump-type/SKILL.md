---
name: bump-type
description: Derives the dominant Bump Type Determination row and bump verdict for the working-branch commits since the base, emitting a routing decision the caller acts on. Use when deciding whether a version bump is required and which bump type applies.
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/bump-type/scripts/bump-type.sh *)
  - Read
shell: bash
---

# Bump Type

Derive the version-bump verdict for the commits on the working branch since it diverged from
the base. This skill backs the `version_bump_decision` workflow state owned by
`hivemind:overlord`. The deterministic engine is the committed, READ-ONLY script
`${CLAUDE_PLUGIN_ROOT}/skills/bump-type/scripts/bump-type.sh`; this body is a thin navigator
that runs the script once and interprets its routing. The engine mutates NOTHING — it reads
the commit range, derives the verdict, and prints a routing decision.

## Division of labor

The engine owns ALL the mechanical arithmetic of
`${CLAUDE_PLUGIN_ROOT}/governance/versioning.md` (Bump Type Determination): the revert
pre-pass, the per-commit row mapping, and the dominant-row precedence. The engine alone is the
single source for that arithmetic; versioning.md keeps the row table and the two judgment
definitions; this skill does not restate them.

The caller keeps ONLY two judgments, both defined in
`${CLAUDE_PLUGIN_ROOT}/governance/versioning.md` (Bump Trigger):

- whether the change satisfies any Bump Trigger bullet — passed as `--bump-trigger yes|no`.
- whether the change matches one or more bullets of the "No bump is required by default"
  list — passed as `--no-bump-match yes|no`.

## Required Inputs

The caller resolves and passes these; the skill does not invent them.

- `base`: the resolved base branch per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md`
  (Framework Defaults). Passed as a plain ref name; revision-suffix syntax is rejected.
- `bump_trigger`: `yes` or `no` — the Bump Trigger judgment above.
- `no_bump_match`: `yes` or `no` — the "No bump is required by default" judgment above.

## Procedure

1. **Execute the script** with one Bash call:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/bump-type/scripts/bump-type.sh <base> --bump-trigger <yes|no> --no-bump-match <yes|no>
   ```
   EXECUTE (do not Read) the script — it owns the deterministic read -> derive -> emit and the
   argument and commit-framing guards. It reads the commit range and writes nothing.

2. **Interpret the result.** Exit 0: the script printed YAML routing lines on stdout —
   ```yaml
   dominant_row: MAJOR|MINOR|PATCH|NO_BUMP|NONE|MULTI
   verdict: bump_required|no_bump|ask_user
   bump_type: major|minor|patch|none
   rule_applied: <1-6>
   counts:
     major: <N>
     minor: <N>
     patch: <N>
     no_bump: <N>
   mapped_commits: <N>
   dropped_reverts: <N>
   ```
   Route on `verdict`:
   - `bump_required` — a version bump is required; `bump_type` names the increment to assign.
   - `no_bump` — no version bump is required.
   - `ask_user` — the change matches more than one row, matches no row, or matches a row whose
     impact condition is unsatisfied. The caller surfaces the bump decision to the user before
     delegating any version edit.

   `rule_applied`, `counts`, `mapped_commits`, and `dropped_reverts` are evidence for the
   caller's report, not additional routing inputs.

   Exit 1: the script printed `blocker: <reason>` on stderr and nothing on stdout (for
   example: an invalid or unresolvable base, a missing, repeated, or invalid flag, no git
   checkout, a missing shared library, a failed commit read, or a commit-framing violation) —
   surface it and stop.

## Pointers

- EXECUTE (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/bump-type/scripts/bump-type.sh`.
- Rules the engine encodes: `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md`
  (Bump Type Determination).

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own — its steps are tool calls only.
- The only action is the Bash script call (step 1); the engine performs no writes.
- The procedure ends at the step 1 Bash script call, which hands the routing data back
  to the caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = caller routes on the returned `verdict`; routing data is on stdout.
  Exit 1 = blocked; the reason is on stderr and nothing was mutated.

## Do Not

- hand-compute the revert pre-pass, row mapping, or dominant row — the script derives them
  from the commit range.
- pass a judgment the caller has not made — each flag is required and takes only `yes` or `no`.
- assign a bump type when `verdict` is `ask_user` — surface the decision to the user first.
- edit any version artifact — this skill only derives the verdict.
- mutate any file — this engine is read-only.
- commit, push, or open a PR.
- Read or reconstruct the script body — invoke it with the documented arguments.
