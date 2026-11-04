---
name: push-branch
description: Pushes the current working branch to its remote without opening a PR. Use when pushing review-remediation commits.
allowed-tools:
  - Bash(git status *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/push-branch/scripts/push-branch.sh" *)
  - Bash(printf *)
  - Read(~/.claude/plugins/cache/brenpike/hivemind/**)
shell: bash
---

## Quick Reference

Rules: `GIT-01` (no trunk commits/push)

Before:
- [ ] `head`, `base`, `expect_commit`, and `push_remote` (when given) pass the input gate
- [ ] Git state not unsafe per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State)

After:
- [ ] Working branch is on its remote — push SUCCEEDED, or the skill returned `blocked` (exit 1)
- [ ] This skill's procedure ended at its own final Bash tool call (exit 0 = pushed/routing emitted, exit 1 = blocked)

Push the current working branch to its remote. This skill does NOT create a pull request — its sole job is to place remediation commits on the remote so an in-flight review loop can resume against the updated branch.

Contract: **the push succeeds or the skill returns `blocked`.** There is no warn-and-continue path. In the post-PR `push_remediation` flow a failed push means the review loop would resume against the UNCHANGED remote and could repeat the same finding forever (no `gh pr create` fallback exists here, unlike `hivemind:open-plan-pr`). Any push failure — auth, read-only, protected branch, hook policy, `[remote rejected]`, a non-fast-forward that force-with-lease cannot resolve, or no remote to push to — is therefore a terminal `blocked` (exit 1), never a warning.

Follow `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` whole.

## Required Inputs

The orchestrator resolves and passes these. The skill does not resolve them on its own.

- `base`: resolved trunk branch — used only as a guard (current branch must not equal it).
- `head`: working branch (current branch).
- `expect_commit`: the full SHA of the commit to push. That is the commit the caller's gates held for, or, when no gate runs after the caller's last commit, the commit the caller just made (the `commit:` line of that commit's output). The script stops before the push when HEAD is another commit.
- `push_remote`: optional explicit remote name. Omit unless the user named one.

## Requirements

Every push runs through `${CLAUDE_PLUGIN_ROOT}/skills/push-branch/scripts/push-branch.sh`, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline).

**Input gate.** Before any Bash call, validate `head`, `base`, and, when provided, `push_remote` against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline); on failure, exit 1 with `blocker: head, base, or push_remote contains characters outside the safe allowlist`. Validate `expect_commit` as a commit SHA against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline) before any Bash call; on failure, exit 1 with `blocker: expected commit is not a full object id`, which echoes no value.

1. Confirm git state is not unsafe per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State). On unsafe state, exit 1 with blocker.
2. **Final Bash tool call.** Run the push script, where each `<allowlist-validated-...>` placeholder is the input value that passed the input gate. Pass `--remote` only when `push_remote` is provided:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/push-branch/scripts/push-branch.sh" --head <allowlist-validated-head> --base <allowlist-validated-base> [--remote <allowlist-validated-remote>] --on-reject block --no-upstream block --expect-commit <allowlist-validated-commit>
   ```

   The script header defines the branch checks, push modes, force-with-lease retry, failure classification, and output; this skill does not restate them. Exit 0: stdout `branch` + `commit` are the routing data. Exit 1: blocked; relay the script's `blocker:` line from stderr.

## Silence Discipline

Follow `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Silence Discipline). The procedure
ends at the requirement 2 Bash call. Emit a blocker as
`printf 'blocker: <reason>' >&2; exit 1`. Never include a `status:` field in any output.

## Do Not

- create a pull request — this skill pushes only; PR creation belongs to `hivemind:open-plan-pr`.
- push the trunk branch (`base`) under any circumstance.
- push outside the push script, or continue past step 2 when the script exits 1.
- include any of the following strings (any case) in commit messages or output: `Co-Authored-By:`, `Generated with`, `Created with Claude`, `🤖 Generated`, any `Authored-by:` line naming a bot/AI/agent, or any line attributing generated-content authorship.
