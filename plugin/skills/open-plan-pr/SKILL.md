---
name: open-plan-pr
description: Opens a pull request for a successfully completed approved plan after final verification. Use when validation and versioning gates have passed and the plan is ready for PR.
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/open-plan-pr/scripts/open-plan-pr.sh" *)
  - Bash(git status *)
  - Bash(git branch *)
  - Bash(git log *)
  - Bash(git diff *)
  - Bash(printf *)
  - Edit(.hivemind/pr-inputs-*.json)
shell: bash
---

## Quick Reference

Rules: `GIT-01` (no trunk commits), `VAL-01` (validation gate), `VAL-02` (PR only after validation)

Before:
- [ ] Current branch matches `head` and is not `base`
- [ ] Validation passed or "Not run (no validation commands defined)"
- [ ] Required version/release metadata included or not required
- [ ] Local review gate held, or local review did not run, per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (PR Requirements)
- [ ] No unexpected unstaged changes

After:
- [ ] The script checked the PR head repository, branch and SHA against the push remote's repository, `head` and the commit it pushed
- [ ] PR created or reused with `base` (resolved trunk) as its target
- [ ] This skill's procedure ended at its own final Bash tool call (exit 0 = succeeded, exit 1 = blocked)

Open a pull request for the completed approved plan.

Follow `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` and `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md`.

## Required Inputs

The orchestrator resolves and passes these. The skill does not resolve them on its own.

- `base`: resolved trunk branch (PR target).
- `head`: working branch (current branch).
- `push_remote`: optional explicit remote name. Omit unless the user named one.

## Optional Inputs

The caller may pass these. When one is absent, the script works as it does without it.

- `expect_commit`: the full SHA of the commit the PR must carry, such as the commit every gate held for. The script stops before the push when HEAD is another commit. When it is absent, the script pushes the commit HEAD is on.
- `title`: the PR title. When it is given, step 5 writes it verbatim as the `title` field.
- `body`: the PR body. When it is given, step 5 writes it verbatim as the `body` field.
- `comment`: text for the open PR the script reuses. When it is given, step 5 writes it verbatim as the `comment` field. The script posts it only on a reused PR; a created PR gets no comment.
- `draft`: `true` or `false`, the caller's choice of a draft PR. When it is given, step 5 writes it as the `draft` field, in place of judging whether the user asked for a draft PR.

When `expect_commit` is given, the caller has already checked validation, version metadata and local review on that commit, so steps 3 and 4 and the local review gate take the caller's check.

## Requirements

Every push and every PR open runs through `${CLAUDE_PLUGIN_ROOT}/skills/open-plan-pr/scripts/open-plan-pr.sh`. The script reads the PR title and body from an inputs file that this skill writes with the Write tool, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern), so no title or body text goes into a shell command. This skill never pushes, opens a PR, or reads a PR with its own commands.

**Input gate.** Before any Bash call, validate `head`, `base` and, when provided, `push_remote` against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline); on failure, exit 1 with `blocker: head, base or push_remote contains characters outside the safe allowlist`, which echoes no value.

When `expect_commit` is provided, validate it as a commit SHA against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline) before any Bash call; on failure, exit 1 with `blocker: expected commit is not a full object id`, which echoes no value.

1. Confirm current branch matches `head` and is not `base`. The step 6 script makes this check in the same process as the push, so the check and the push act on one reading of the branch; no separate Bash call compares them here. On mismatch or trunk match, the script exits 1 with `blocker: current branch does not match head or equals base`, which echoes neither value.
2. Confirm no unexpected unstaged changes. The script refuses a dirty tree before any change.
3. Confirm validation outcome per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Validation Procedure) is one of: every declared command passed, OR `Not run (no validation commands defined)`. Exit 1 with blocker if the procedure returned the Worker Report — Blocked (`stage: validation`) or any declared command failed.
4. Confirm required version/release metadata is included or not required.
5. Write the PR title and body, or take `title` and `body` when given. The title is one line. The body holds the summary, validation notes, version/release notes, and unresolved issues. Neither the title, the body, nor a given `comment` may contain a string the `## Do Not` list forbids; that check is this skill's own. A given value is never changed, so when one carries such a string, exit 1 with `blocker: PR text carries a string the Do Not list forbids`, which echoes no value.

   Then write the inputs file with the Write tool. `file_path` is `.hivemind/pr-inputs-<token>.json`, where `<token>` is a new value for each invocation, made only of letters, digits and `-`, such as a UTC timestamp plus a random part (`20261020T141500Z-a1b2c3`). `content` is one JSON object:

   ```json
   {
     "title": "<title>",
     "body": "<body>",
     "draft": false
   }
   ```

   When `draft` is given, write it as the `draft` field. Otherwise set `draft` to `true` only when the user asked for a draft PR, and leave it out when they did not. Add a `"comment": "<comment>"` field only when `comment` is given. The script header lists the rule for each field. If the Write call does not succeed, stop blocked per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern →
   Transport Degradation Is a Hard Stop).
6. **Final Bash tool call.** Run the PR script, where each `<allowlist-validated-...>` placeholder is the input value that passed its gate above and `<token>` is the token from step 5. Pass `--remote` only when `push_remote` is provided, and `--expect-commit` only when `expect_commit` is provided:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/open-plan-pr/scripts/open-plan-pr.sh" --head <allowlist-validated-head> --base <allowlist-validated-base> [--remote <allowlist-validated-remote>] [--expect-commit <allowlist-validated-commit>] --inputs .hivemind/pr-inputs-<token>.json
   ```

   The script pushes through the push-branch script, as a child process, before it opens or reuses the PR. Every push runs through the push-branch script, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline). The script header defines the refusals, the push, the reuse of an open PR, the create call, the PR check, and the output; this skill does not restate them. The script never passes `--head` to `gh pr create`; see recorded residuals R1 and R3 in `${CLAUDE_PLUGIN_ROOT}/skills/open-plan-pr/scripts/open-plan-pr.sh`.
   - exit 0: stdout `url: <url>` and `head_ref_oid: <sha>` are the routing data, followed by `created: true|false`, then `commented: true|false` only when the inputs carry `comment`, and, when the push warned, a `warning:` line. `created: false` means the script reused the open PR from the push remote's repository on the pushed commit and left its title and body unchanged. `commented: true` means the script posted the comment on that reused PR; each run that reuses a PR posts its own comment. The `warning:` line appears when the push warned or the head repository was not checked. Record a `warning:` line as a warning.
   - exit 1: blocked; relay the script's stderr. The `blocker:` line is last.

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own — its steps are tool calls only.
- The procedure ends at the step 6 Bash tool call, which hands the routing data back to the
  caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = orchestrator proceeds. Routing data (if any) is in stdout.
- Exit 1 = blocked. Emit reason: `printf 'blocker: <reason>' >&2; exit 1`
- Never include a `status:` field in any output.

## Do Not

- open PR for a partial plan unless one of: the user explicitly requested a draft PR, OR the planner's `Delivery: Shape` field equals `multi-plan`
- open PR if the Validation procedure returned the Worker Report — Blocked (`stage: validation`) or any declared validation command failed. `Validated: Not run (no validation commands defined)` is a valid terminal state per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Validation Procedure) and does not block PR opening.
- open PR if required version/release metadata is missing per `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md`
- open PR when local review ran on the branch and did not hold the local review gate per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (PR Requirements)
- continue past step 6 with an unverified push state
- invent missing validation
- include any of the following strings (any case) in commit messages or PR content: `Co-Authored-By:`, `Generated with`, `Created with Claude`, `🤖 Generated`, any `Authored-by:` line naming a bot/AI/agent, or any line attributing generated-content authorship
- push, open a PR, or read a PR with your own commands; only the script does
- paste the title, the body, or the comment into a Bash command
- use the Write tool for anything other than the `.hivemind/pr-inputs-<token>.json` inputs file
- author the inputs file through any transport other than the Write tool: no heredoc, no shell
  redirection, no inline script. A Write that does not succeed is a hard stop, not a workaround;
  see `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md`
  (Transport Degradation Is a Hard Stop).
