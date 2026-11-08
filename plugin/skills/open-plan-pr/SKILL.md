---
name: open-plan-pr
description: Opens the PR for a completed approved plan after final verification. Use once validation and versioning gates pass.
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

Open a pull request for the completed approved plan, per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (PR Requirements) and `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md` (Bump Trigger, Bump Execution).

## Required Inputs

The orchestrator resolves and passes these; the skill never resolves them itself.

- `base`: resolved trunk branch (PR target).
- `head`: working branch (current branch).
- `push_remote`: optional explicit remote name. Omit unless the user named one.
- `expect_commit`: the full SHA of the commit the PR must carry, the commit every gate held for. The script stops before the push when HEAD is another commit.

## Optional Inputs

Step 5 writes each given value verbatim, `body` as the body file and each other value as its inputs-file field.

- `title`, `body`: the PR title and body.
- `comment`: text for the open PR the script reuses. The script posts it only on a reused PR; a created PR gets no comment.
- `draft`: `true` or `false`, the caller's choice of a draft PR, in place of judging whether the user asked for one.

The caller passes as `expect_commit` the commit on which it checked validation, version metadata and local review, so steps 3 and 4 take the caller's check on that commit.

## Requirements

Every push and every PR open runs through `${CLAUDE_PLUGIN_ROOT}/skills/open-plan-pr/scripts/open-plan-pr.sh`. It reads the PR title from an inputs file and the body from a body file, both written by this skill with the Write tool, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern), so no title or body text enters a shell command.

**Input gate.** Before any Bash call, validate `head`, `base` and, when provided, `push_remote` against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline); on failure, exit 1 with `blocker: head, base or push_remote contains characters outside the safe allowlist`, which echoes no value. Validate `expect_commit` as a commit SHA against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline) before any Bash call; on failure, exit 1 with `blocker: expected commit is not a full object id`, which echoes no value.

1. Confirm current branch matches `head` and is not `base`. The step 6 script checks this in the same process as the push; no separate Bash call compares them. On mismatch or trunk match, the script exits 1 with `blocker: current branch does not match head or equals base`, which echoes neither value.
2. Confirm no unexpected unstaged changes; the script refuses a dirty tree before any change.
3. Confirm validation outcome per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Validation Procedure) is one of: every declared command passed, or `Not run (no validation commands defined)`. Exit 1 with blocker if the procedure returned the Worker Report — Blocked (`stage: validation`) or any declared command failed.
4. Confirm required version/release metadata is included or not required, and that the local review gate held, local review did not run, or the PR is a loop-cap draft, per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (PR Requirements).
5. Write the PR title and body, or take `title` and `body` when given. The title is one line; the body holds the summary, validation notes, version/release notes and unresolved issues. The title, the body and a given `comment` must not contain a string the `## Do Not` list forbids; that check is this skill's own. A given value is never changed: when one carries such a string, exit 1 with `blocker: PR text carries a string the Do Not list forbids`, which echoes no value.

   Then write two files with the Write tool, where `<token>` is new for each invocation, made only of letters, digits and `-`, such as a UTC timestamp plus a random part (`20261020T141500Z-a1b2c3`). First the body file: `file_path` is `.hivemind/pr-inputs-<token>-body.json` and `content` is the body as raw Markdown. Then the inputs file: `file_path` is `.hivemind/pr-inputs-<token>.json` and `content` is one JSON object:

   ```json
   {
     "title": "<title>",
     "draft": false
   }
   ```

   Write a given `draft` as the `draft` field; otherwise set `draft` to `true` only when the user asked for a draft PR, and leave it out when they did not. Add a `"comment": "<comment>"` field only when `comment` is given. The script header gives each field's rule. If either Write call does not succeed, stop blocked per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
6. **Final Bash tool call.** Run the PR script, where each `<allowlist-validated-...>` placeholder is the input value that passed its gate above and `<token>` is the token from step 5. Pass `--remote` only when `push_remote` is provided:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/open-plan-pr/scripts/open-plan-pr.sh" --head <allowlist-validated-head> --base <allowlist-validated-base> [--remote <allowlist-validated-remote>] --expect-commit <allowlist-validated-commit> --inputs .hivemind/pr-inputs-<token>.json --body-file .hivemind/pr-inputs-<token>-body.json
   ```

   Every push runs through the push-branch script, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline). The script header defines the refusals, push, open-PR reuse, create call, PR check and output.
   - exit 0: stdout `url: <url>` and `head_ref_oid: <sha>` are the routing data, then `created: true|false`, then `commented: true|false` only when the inputs carry `comment`, then a `warning:` line when the push warned or the head repository was not checked; record it as a warning. `created: false` means the script reused the open PR from the push remote's repository on the pushed commit and left its title and body unchanged. `commented: true` means the script posted the comment on that reused PR; each run that reuses a PR posts its own comment.
   - exit 1: blocked; relay the script's stderr, whose last line is the `blocker:` line.

## Silence Discipline

Follow `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Silence Discipline). The procedure
ends at the step 6 Bash call. Emit a blocker as `printf 'blocker: <reason>' >&2; exit 1`. Never
include a `status:` field in any output.

## Do Not

- open PR for a partial plan unless the user explicitly requested a draft PR or the planner's `Delivery: Shape` field equals `multi-plan`
- open PR if the Validation procedure returned the Worker Report — Blocked (`stage: validation`) or any declared validation command failed
- open PR if required version/release metadata is missing per `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md` (Bump Trigger, Bump Execution)
- open a ready-for-review PR when local review ran on the branch and did not hold the local review gate per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (PR Requirements)
- continue past step 6 with an unverified push state
- invent missing validation
- include any of the following strings (any case) in commit messages or PR content: `Co-Authored-By:`, `Generated with`, `Created with Claude`, `🤖 Generated`, any `Authored-by:` line naming a bot/AI/agent, or any line attributing generated-content authorship
- push, open a PR, or read a PR with your own commands; only the script does
- paste the title, the body, or the comment into a Bash command
- use the Write tool for anything other than the `.hivemind/pr-inputs-<token>-body.json` body file and the `.hivemind/pr-inputs-<token>.json` inputs file
- author either file by any transport other than the Write tool; see
  `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
