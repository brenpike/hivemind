---
name: open-plan-pr
description: Opens a pull request for a successfully completed approved plan after final verification. Use when validation and versioning gates have passed and the plan is ready for PR.
allowed-tools:
  - Bash(git status *)
  - Bash(git branch *)
  - Bash(git log *)
  - Bash(git diff *)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/push-branch/scripts/push-branch.sh *)
  - Bash(gh pr create *)
  - Bash(gh pr view *)
  - Bash(printf *)
shell: bash
---

## Quick Reference

Rules: `GIT-01` (no trunk commits), `VAL-01` (validation gate), `VAL-02` (PR only after validation)

Before:
- [ ] Current branch matches `head` and is not `base`
- [ ] Validation passed or "Not run (no validation commands defined)"
- [ ] Required version/release metadata included or not required
- [ ] No unexpected unstaged changes

After:
- [ ] PR head branch and SHA match `head` and the step 6 `commit:` line
- [ ] PR created with `--base` targeting resolved trunk
- [ ] This skill's procedure ended at its own final Bash tool call (exit 0 = succeeded, exit 1 = blocked)

Open a pull request for the completed approved plan.

Follow `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` and `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md`.

## Required Inputs

The orchestrator resolves and passes these. The skill does not resolve them on its own.

- `base`: resolved trunk branch (PR target).
- `head`: working branch (current branch).
- `push_remote`: optional explicit remote name. Omit unless the user named one.

## Requirements

**Input gate.** Before any Bash call, validate `head`, `base` and, when provided, `push_remote` against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline); on failure, exit 1 with `blocker: head, base or push_remote contains characters outside the safe allowlist`, which echoes no value.

1. Confirm current branch matches `head` and is not `base`. The step 6 script makes this check in the same process as the push, so the check and the push act on one reading of the branch; no separate Bash call compares them here. On mismatch or trunk match, the script exits 1 with `blocker: current branch does not match head or equals base`, which echoes neither value.
2. Confirm no unexpected unstaged changes.
3. Confirm validation outcome per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Validation Procedure) is one of: every declared command passed, OR `Not run (no validation commands defined)`. Exit 1 with blocker if the procedure returned the Worker Report — Blocked (`stage: validation`) or any declared command failed.
4. Confirm required version/release metadata is included or not required.
5. The commit the PR must carry is the step 6 script's `commit:` line: the object id the script pushed, or on a warning path the one it would have pushed. No Bash call reads HEAD for it, before or after the push, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline).
6. Place the working branch on its remote in ONE Bash call to the push-branch script, where `<allowlist-validated-head>`, `<allowlist-validated-base>` and `<allowlist-validated-remote>` are the `head`, `base` and `push_remote` values that passed the input gate. Pass `--remote` only when `push_remote` is provided:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/push-branch/scripts/push-branch.sh --head <allowlist-validated-head> --base <allowlist-validated-base> [--remote <allowlist-validated-remote>] --on-reject warn --no-upstream origin
   ```
   Every push runs through the push-branch script, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline).
   - exit 1: blocked. The script's `blocker:` line on stderr is the reason.
   - exit 0 with a `warning:` line: record it as a warning and continue to step 7. Non-interactive `gh pr create` neither pushes nor prompts: it proceeds only when it finds the branch on a remote at the local commit, and otherwise stops.
   - exit 0 without a `warning:` line: the branch is on its remote; continue to step 7.
7. Run `gh pr create --base <allowlist-validated-base> ...`, where `<allowlist-validated-base>` is the `base` value that passed the input gate, with title, summary, validation notes, version/release notes, and unresolved issues. Do not pass `--head`. Without `--head`, `gh` finds the head repository, including a fork, from the remote whose tracking ref matches the pushed commit, while `--head <branch>` names the base repository unless given `<owner>:<branch>`, which cannot be derived without parsing a remote URL. `gh` resolves the head itself, so step 8 checks the PR it created. See recorded residual R1 in `${CLAUDE_PLUGIN_ROOT}/skills/push-branch/scripts/push-branch.sh`.
8. **Final Bash tool call.** Verify the PR's head branch and head SHA against `head` and the step 6 commit. Take the PR number from the trailing `/pull/<n>` segment of the step 7 URL and validate it against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline) before the Bash call; on failure, exit 1 with `blocker: PR number contains characters outside the safe allowlist`. Take the commit from the step 6 `commit:` line and validate it as a commit SHA against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline) before the Bash call; on failure, exit 1 with `blocker: pushed commit is not a full commit SHA`. Then run ONE Bash call, where `<allowlist-validated-pr-number>` is that validated PR number, `<allowlist-validated-head>` is the `head` value that passed the input gate, and `<allowlist-validated-commit>` is that validated commit:

   ```bash
   n="$(gh pr view <allowlist-validated-pr-number> --json headRefName --jq '.headRefName')"
   p="$(gh pr view <allowlist-validated-pr-number> --json headRefOid --jq '.headRefOid')"
   u="$(gh pr view <allowlist-validated-pr-number> --json url --jq '.url')"
   [ -n "$n" ] && [ -n "$p" ] && [ -n "$u" ] || { printf 'blocker: could not read the PR head branch, head SHA, or URL' >&2; exit 1; }
   [ "$n" = '<allowlist-validated-head>' ] || { printf 'blocker: PR head branch does not match head' >&2; exit 1; }
   [ "$p" = '<allowlist-validated-commit>' ] || { printf 'blocker: PR head SHA mismatch, expected %s got %s' '<allowlist-validated-commit>' "$p" >&2; exit 1; }
   printf 'url: %s\nhead_ref_oid: %s\n' "$u" "$p"
   ```

   On success (head branch matches `head` and head SHA matches the step 6 commit), the YAML output (`url` + `head_ref_oid`) is the routing data. Exits 1 with the blocker in stderr when the PR head branch, head SHA, or URL cannot be read (`blocker: could not read the PR head branch, head SHA, or URL`), when the head branch does not match `head` (`blocker: PR head branch does not match head`), or when the head SHA does not match the step 6 commit (`blocker: PR head SHA mismatch, ...`).

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own — its steps are tool calls only.
- The procedure ends at the step 8 Bash tool call, which hands the routing data back to the
  caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = orchestrator proceeds. Routing data (if any) is in stdout.
- Exit 1 = blocked. Emit reason: `printf 'blocker: <reason>' >&2; exit 1`
- Never include a `status:` field in any output.

## Do Not

- open PR for a partial plan unless one of: the user explicitly requested a draft PR, OR the planner's `Delivery: Shape` field equals `multi-plan`
- open PR if the Validation procedure returned the Worker Report — Blocked (`stage: validation`) or any declared validation command failed. `Validated: Not run (no validation commands defined)` is a valid terminal state per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Validation Procedure) and does not block PR opening.
- open PR if required version/release metadata is missing per `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md`
- continue past step 6 with an unverified push state
- invent missing validation
- include any of the following strings (any case) in commit messages or PR content: `Co-Authored-By:`, `Generated with`, `Created with Claude`, `🤖 Generated`, any `Authored-by:` line naming a bot/AI/agent, or any line attributing generated-content authorship
