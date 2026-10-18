---
name: create-working-branch
description: Creates or confirms the compliant working branch for the current approved plan. Use when starting implementation on an approved plan and the working branch needs to be created or verified.
allowed-tools:
  - Bash(git status *)
  - Bash(git branch *)
  - Bash(git rev-parse *)
  - Bash(git checkout *)
  - Bash(git switch *)
  - Bash(git fetch *)
  - Bash(printf *)
shell: bash
---

## Quick Reference

Rules: `GIT-01` (no trunk commits), `GIT-02` (required git preflight)

Before:
- [ ] Orchestrator provided `base`, `working_branch`, and `classification`
- [ ] Orchestrator confirmed trunk freshness, user acknowledged stale trunk, or orchestrator recorded trunk-freshness: skipped
- [ ] `base` branch exists locally or can be fetched
- [ ] No uncommitted changes that make switching unsafe
- [ ] `working_branch` name follows branch taxonomy

After:
- [ ] Current branch is `working_branch`
- [ ] Branch created from or confirmed on `base`
- [ ] This skill's procedure ended at its own final Bash tool call (exit 0 = succeeded, exit 1 = blocked)

Create or confirm the working branch for the current approved plan.

Follow `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md`.

## Required Inputs

The orchestrator resolves and passes these. The skill does not resolve them on its own.

- `base`: base branch the working branch is created from (typically the resolved trunk; may differ for stacked work).
- `working_branch`: requested working branch name (must follow branch taxonomy and naming rules).
- `classification`: work classification (`feature|bugfix|hotfix|refactor|chore|docs|test|ci`).
- `trunk-freshness`: resolved trunk freshness state from the orchestrator's preflight check per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (Trunk Freshness). One of: `fresh`, `stale (N behind)`, `stale (diverged — local N ahead)`, `stale (diverged — local M ahead, N behind)`, or `skipped`. Absent = skill exits 1 with blocker.

## Requirements

1. Confirm current branch.
2. Confirm `base` exists locally or fetch it.
3. Check the `trunk-freshness` session fact passed by the orchestrator per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (Trunk Freshness).
   - `trunk-freshness: fresh` — proceed normally, no warning.
   - `trunk-freshness: stale (N behind)` — emit a warning that trunk is stale but proceed (user already acknowledged at preflight).
   - `trunk-freshness: stale (diverged — local N ahead)` — emit a warning that local trunk has unpushed commits but proceed (user already acknowledged at preflight).
   - `trunk-freshness: stale (diverged — local M ahead, N behind)` — emit a warning that local trunk has diverged from origin but proceed (user already acknowledged at preflight).
   - `trunk-freshness: skipped` — proceed with a note that freshness was intentionally skipped.
   - Absent — emit `printf 'blocker: trunk-freshness session fact not provided by orchestrator' >&2; exit 1`.
4. Confirm `working_branch` follows the branch taxonomy and naming rules.
5. Confirm there are no unexpected unstaged/uncommitted changes that make switching unsafe.
6. Create or switch to `working_branch` from `base` conditionally: if `working_branch` does NOT yet exist, create it from `base` via `git switch --no-track -c <working_branch> <base>`; if `working_branch` ALREADY exists (resume/retry, or the current worktree is already on it), switch to it without `-c` via `git switch <working_branch>` (do NOT pass `-c` or `<base>` — passing `-c` to an existing branch fails). Either form repoints the CURRENT worktree HEAD onto `working_branch` even when invoked while booted on a NON-trunk scratch ref (e.g. a brood child booted on `strain/<brood-id>/<short>`); the skill creates and removes NO worktrees (worktree ownership stays with `hivemind:spawn-brood`). Suppress command output (`>/dev/null 2>&1`).
   After `git switch <working_branch>`, if an upstream is set and its name is not `<remote>/<working_branch>`, run `git branch --unset-upstream`. A branch that tracks trunk lets a plain `git push` or a force-with-lease retry against the tracked upstream target trunk. Capture the branch, its upstream remote, and its upstream ref OUT-OF-BAND into shell variables in the same Bash call and reference them only as `"$var"`, the same technique as `hivemind:push-branch` requirement 4; never paste an upstream or branch value into command text:
   ```bash
   b="$(git rev-parse --abbrev-ref HEAD)"
   rem="$(git branch --list "$b" --format='%(upstream:remotename)')"
   up="$(git branch --list "$b" --format='%(upstream)')"
   if [ -n "$up" ] && [ "$up" != "refs/remotes/$rem/$b" ]; then git branch --unset-upstream >/dev/null 2>&1 || { printf 'blocker: could not unset upstream that does not match the working branch' >&2; exit 1; }; fi
   ```
7. After the `git switch` or `git checkout` command in step 6 succeeds, suppress its output (`>/dev/null 2>&1`) and emit explicit YAML as the final Bash tool call: `printf 'branch: %s\n' "$working_branch"`. This YAML line is the routing data. If any prerequisite check fails (missing inputs, unsafe state, bad branch name), emit blocker to stderr and exit 1.

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own, apart from the requirement 3
  trunk-freshness warning — its remaining steps are tool calls only.
- The procedure ends at the requirement 7 Bash tool call, which hands the routing data back
  to the caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = orchestrator proceeds. Routing data (if any) is in stdout.
- Exit 1 = blocked. Emit reason: `printf 'blocker: <reason>' >&2; exit 1`
- Never include a `status:` field in any output.

## Do Not

- create or modify product files
- commit
- push
- open a PR
- continue when branch state is unsafe or indeterminate
- invent values for `base`, `working_branch`, or `classification` — exit 1 with blocker if any are missing
