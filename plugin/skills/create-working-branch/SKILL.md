---
name: create-working-branch
description: Creates or confirms the compliant working branch for the current approved plan. Use when starting implementation on an approved plan and the working branch needs to be created or verified.
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/create-working-branch/scripts/create-working-branch.sh *)
  - Bash(printf *)
shell: bash
---

## Quick Reference

Rules: `GIT-01` (no trunk commits), `GIT-02` (required git preflight)

Before:
- [ ] Orchestrator provided `base`, `working_branch`, `classification`, and `trunk`
- [ ] Orchestrator confirmed trunk freshness, user acknowledged stale trunk, a caller that decided a stale trunk passed a bare `stale`, or orchestrator recorded trunk-freshness: skipped
- [ ] `base` branch exists locally or can be fetched
- [ ] No uncommitted changes that make switching unsafe
- [ ] `working_branch` name follows branch taxonomy

After:
- [ ] Current branch is `working_branch`
- [ ] Current branch is not `trunk`
- [ ] Branch created from or confirmed on `base`
- [ ] This skill's procedure ended at its own final Bash tool call (exit 0 = succeeded, exit 1 = blocked)

Create or confirm the working branch for the current approved plan.

Follow `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md`.

## Required Inputs

The orchestrator resolves and passes these. The skill does not resolve them on its own.

- `base`: base branch the working branch is created from (typically the resolved trunk; may differ for stacked work).
- `working_branch`: requested working branch name (must follow branch taxonomy and naming rules).
- `classification`: work classification (`feature|bugfix|hotfix|refactor|chore|docs|test|ci`).
- `trunk-freshness`: resolved trunk freshness state from the orchestrator's preflight check per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (Trunk Freshness). One of: `fresh`, `stale (N behind)`, `stale (diverged — local N ahead)`, `stale (diverged — local M ahead, N behind)`, `stale`, or `skipped`. A bare `stale` comes from a caller that decided a stale trunk, such as the script engine's `trunk_stale` decision. Absent = skill exits 1 with blocker.
- `trunk`: the resolved trunk branch. The script refuses a `working_branch` equal to it.

## Requirements

Every branch create or switch runs through `${CLAUDE_PLUGIN_ROOT}/skills/create-working-branch/scripts/create-working-branch.sh`, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline).

**Input gate.** Before any Bash call, validate `base` and `working_branch` against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline); on failure, exit 1 with `blocker: base or working_branch contains characters outside the safe allowlist`.

Validate `trunk` against the same gate; on failure, exit 1 with `blocker: trunk contains characters outside the safe allowlist`.

1. Map the `trunk-freshness` session fact passed by the orchestrator per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (Trunk Freshness) to the script value:
   - `trunk-freshness: fresh` maps to `fresh`.
   - `trunk-freshness: stale (...)`, in any of the forms listed in Required Inputs, maps to `stale` (user already acknowledged at preflight).
   - `trunk-freshness: stale`, bare, maps to `stale` (the caller already decided a stale trunk).
   - `trunk-freshness: skipped` maps to `skipped`.
   - Absent: emit `printf 'blocker: trunk-freshness session fact not provided by orchestrator' >&2; exit 1`.
2. Confirm `working_branch` follows the branch taxonomy and naming rules in `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (Branch Taxonomy, Branch Naming), and that `classification` is one of the values in Required Inputs. On failure, exit 1 with blocker.
3. **Final Bash tool call.** Run the branch script, where each `<allowlist-validated-...>` placeholder is the value that passed the input gate or the checks in steps 1 and 2:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/create-working-branch/scripts/create-working-branch.sh --base <allowlist-validated-base> --branch <allowlist-validated-working-branch> --classification <allowlist-validated-classification> --trunk-freshness <allowlist-validated-trunk-freshness> --trunk <allowlist-validated-trunk>
   ```

   The script header defines the tree refusals, the refusal of a `working_branch` equal to `trunk`, base resolution, branch creation and switching, upstream handling, and output; this skill does not restate them. Exit 0: stdout `branch: <working_branch>` is the routing data, followed by `commit:`, `created:`, and, for stale or skipped trunk freshness, a `warning:` line. Exit 1: blocked; relay the script's `blocker:` line from stderr.

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own; its steps are tool calls only.
  The trunk-freshness warning is the script's `warning:` stdout line.
- The procedure ends at the requirement 3 Bash tool call, which hands the routing data back
  to the caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = orchestrator proceeds. Routing data (`branch`, `commit`, `created`, and any `warning`) is in stdout.
- Exit 1 = blocked. Emit reason: `printf 'blocker: <reason>' >&2; exit 1`
- Never include a `status:` field in any output.

## Do Not

- create or modify product files
- commit
- push
- open a PR
- continue when branch state is unsafe or indeterminate
- invent values for `base`, `working_branch`, or `classification` — exit 1 with blocker if any are missing
- invent a value for `trunk`; exit 1 with blocker if it is missing
