---
name: molt
description: Creates a checkpoint commit for the current approved plan. Use when completing a phase, milestone, version bump, or review-remediation item.
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/molt/scripts/molt.sh" *)
  - Bash(git status *)
  - Bash(git diff *)
  - Bash(git rev-parse *)
  - Bash(git log *)
  - Bash(printf *)
  - Edit(.hivemind/molt-inputs-*.json)
shell: bash
---

## Quick Reference

Rules: `GIT-01` (no trunk commits), `VAL-01` (validation gate)

Before:
- [ ] Current branch is not trunk
- [ ] Git state is not unsafe per Definitions
- [ ] Staged files belong to the completed phase only

After:
- [ ] Commit message uses `<type>(<scope>): <subject>` format
- [ ] No unrelated files included
- [ ] This skill's procedure ended at its own final Bash tool call (exit 0 = succeeded, exit 1 = blocked)

Create a checkpoint commit for the current approved plan.

Follow `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md`.

## Required Inputs

The orchestrator resolves and passes these. The skill does not resolve them on its own.

- `trunk`: resolved trunk branch name (the branch that must not be committed to directly).

## Optional Inputs

The caller may pass these. When one is absent, this skill judges it, as it always has.

- `files`: the exact paths to commit, relative to the top of the work tree. When it is absent, requirement 3 judges the list.
- `commit_type`: the commit type, one of the types in requirement 4. When it is absent, requirement 4 judges the type.
- `breaking`: `true` when the change breaks a public contract, else `false`. When it is absent, it is `true` only when requirement 4 (b) applies.
- `commit_body`: the commit body, per requirement 4 (d).
- `subject`: the commit subject. When it is absent, requirement 4 judges the subject.

When the caller passes both `files` and `subject`, this skill skips requirement 2 and runs no git command of its own: it writes the inputs file from the given values and runs the script.

## Requirements

Every commit runs through `${CLAUDE_PLUGIN_ROOT}/skills/molt/scripts/molt.sh`. The script reads the message and the file list from an inputs file that this skill writes with the Write tool, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern), so no message text or path goes into a shell command. This skill never stages or commits with its own git commands.

**Input gate.** Before any Bash call, validate `trunk` against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline); on failure, exit 1 with `blocker: trunk contains characters outside the safe allowlist`.

1. Confirm current branch is not `trunk` and that git state is not unsafe per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State). The script makes these checks before any change, so this step needs no git command of its own.
2. Review staged and unstaged diff. Skip this requirement when the caller passes both `files` and `subject`.
3. Choose the files to commit. Use `files` when the caller passes it. Otherwise list only the files that belong to the completed phase, milestone, version bump, or review-remediation item. List each path exactly, relative to the top of the work tree. List each deleted path and both sides of a rename. Never list a directory. The script stages exactly the listed paths that are dirty. It refuses when any other path is dirty, so a dirty file that belongs to no item stops the commit.
4. Create a commit message in the form `<type>(<optional scope>): <subject>`, where:
   - `<type>` is one of: `feat`, `fix`, `hotfix`, `refactor`, `docs`, `test`, `chore`, `ci`
   - `<subject>` is 72 characters or fewer
   - include a body only when one of: (a) the change reverts a prior commit, (b) the change includes a `BREAKING CHANGE:` footer, (c) the planner's delegation contains a `Why:` field, OR (d) the orchestrator passes `commit_body` explicitly. Otherwise omit the body.
   - the message must not contain any of the following strings (any case): `Co-Authored-By:`, `Generated with`, `Created with Claude`, `🤖 Generated`, any `Authored-by:` line naming a bot/AI/agent, or any line attributing generated-content authorship
   - use `commit_type` as `<type>` when the caller passes it
   - use `subject` as `<subject>` exactly as given when the caller passes it; the script enforces its rules. When it contains a string the attribution rule above forbids, exit 1 with `blocker: subject contains a forbidden attribution string` and never rewrite it
   - when `breaking` is true, the script adds `!` before the colon. A `BREAKING CHANGE:` footer, or `!:` in the subject, needs `breaking` true; the script refuses it otherwise.

   The script checks the format, the type, the scope and the subject length. The attribution rule above is this skill's own check.

   Then write the inputs file with the Write tool. `file_path` is `.hivemind/molt-inputs-<token>.json`, where `<token>` is a new value for each invocation, made only of letters, digits and `-`, such as a UTC timestamp plus a random part (`20261020T141500Z-a1b2c3`). `content` is one JSON object:

   ```json
   {
     "type": "<type>",
     "scope": "<optional scope>",
     "breaking": false,
     "subject": "<subject>",
     "body": "<optional body>",
     "files": ["<exact path>"]
   }
   ```

   Leave out `scope` and `body` when there is none. The script header lists the rule for each field. If the Write call does not succeed, stop blocked per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern →
   Transport Degradation Is a Hard Stop).
5. **Final Bash tool call.** Run the commit script, where `<allowlist-validated-trunk>` is the value that passed the input gate and `<token>` is the token from requirement 4:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/molt/scripts/molt.sh" --trunk <allowlist-validated-trunk> --inputs .hivemind/molt-inputs-<token>.json
   ```

   The script header defines the field rules, the refusals, staging, the commit, the result checks, and the output; this skill does not restate them. Exit 0: stdout `branch: <branch>` is the routing data, followed by `commit: <full sha>` and `committed: true|false`. `committed: false` means no listed path was dirty, so the script made no commit. Exit 1: blocked; relay the script's stderr: one `outside:` line for each dirty path that is not in the list, as a JSON string, then the `blocker:` line.

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own — its steps are tool calls only.
- The procedure ends at the requirement 5 Bash tool call, which hands the routing data back
  to the caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = orchestrator proceeds. Routing data (if any) is in stdout.
- Exit 1 = blocked. Emit reason: `printf 'blocker: <reason>' >&2; exit 1`
- Never include a `status:` field in any output.

## Do Not

- create a branch
- push
- open a PR
- include unrelated files
- commit on `trunk`
- stage or commit with your own git commands; only the script stages and commits
- paste the message or a path into a Bash command
- use the Write tool for anything other than the `.hivemind/molt-inputs-<token>.json` inputs file
- author the inputs file through any transport other than the Write tool: no heredoc, no shell
  redirection, no inline script. A Write that does not succeed is a hard stop, not a workaround;
  see `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md`
  (Transport Degradation Is a Hard Stop).
