---
name: molt
description: Creates a checkpoint commit for the current approved plan. Use when completing a phase, milestone, bump or review fix.
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

Create a checkpoint commit for the current approved plan, per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (Commit Messages).

## Required Inputs

The orchestrator resolves and passes these; the skill never resolves them itself.

- `trunk`: the resolved trunk branch, which must never be committed to directly.

## Optional Inputs

When one is absent, this skill judges it.

- `files`: the exact paths to commit, relative to the top of the work tree. Absent: requirement 3 judges the list.
- `commit_type`: one of the types in requirement 4. Absent: requirement 4 judges the type.
- `breaking`: `true` when the change breaks a public contract, else `false`. Absent: `true` only when requirement 4 (b) applies.
- `commit_body`: the commit body, per requirement 4 (d).
- `subject`: the commit subject. Absent: requirement 4 judges it.

When the caller passes both `files` and `subject`, skip requirement 2 and run no git command of your own: write the inputs file from the given values and run the script.

## Requirements

Every commit runs through `${CLAUDE_PLUGIN_ROOT}/skills/molt/scripts/molt.sh`. It reads the message and the file list from an inputs file this skill writes with the Write tool, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern), so no message text or path enters a shell command.

**Input gate.** Before any Bash call, validate `trunk` against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline); on failure, exit 1 with `blocker: trunk contains characters outside the safe allowlist`.

1. Confirm current branch is not `trunk` and git state is not unsafe per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State). The script makes both checks before any change, so this step runs no git command.
2. Review the staged and unstaged diff, unless the caller passed both `files` and `subject`.
3. Choose the files to commit: `files` when given; otherwise only the files of the completed phase, milestone, version bump or review-remediation item. List each path exactly, relative to the top of the work tree, including each deleted path and both sides of a rename; never a directory. The script stages exactly the listed dirty paths and refuses when any other path is dirty, so a dirty file of no item stops the commit.
4. Write the message as `<type>(<optional scope>): <subject>`, where:
   - `<type>` is one of: `feat`, `fix`, `hotfix`, `refactor`, `docs`, `test`, `chore`, `ci`; it is `commit_type` when the caller passes it
   - `<subject>` is 72 characters or fewer; it is `subject` exactly as given when the caller passes it, and the script enforces its rules
   - include a body only when (a) the change reverts a prior commit, (b) the change includes a `BREAKING CHANGE:` footer, (c) the planner's delegation contains a `Why:` field, or (d) the orchestrator passes `commit_body` explicitly; otherwise omit it
   - the message must not contain any of the following strings (any case): `Co-Authored-By:`, `Generated with`, `Created with Claude`, `🤖 Generated`, any `Authored-by:` line naming a bot/AI/agent, or any line attributing generated-content authorship. This check is this skill's own: when a given `subject` contains such a string, exit 1 with `blocker: subject contains a forbidden attribution string` and never rewrite it
   - when `breaking` is true, the script adds `!` before the colon. A `BREAKING CHANGE:` footer, or `!:` in the subject, needs `breaking` true; the script refuses it otherwise.

   The script checks the format, the type, the scope and the subject length.

   Then write the inputs file with the Write tool. `file_path` is `.hivemind/molt-inputs-<token>.json`, where `<token>` is new for each invocation, made only of letters, digits and `-`, such as a UTC timestamp plus a random part (`20261020T141500Z-a1b2c3`). `content` is one JSON object:

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

   Leave out `scope` and `body` when there is none; the script header gives each field's rule. If the Write call does not succeed, stop blocked per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
5. **Final Bash tool call.** Run the commit script, where `<allowlist-validated-trunk>` is the value that passed the input gate and `<token>` is the token from requirement 4:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/molt/scripts/molt.sh" --trunk <allowlist-validated-trunk> --inputs .hivemind/molt-inputs-<token>.json
   ```

   The script header defines the field rules, refusals, staging, commit, result checks and output. Exit 0: stdout `branch: <branch>` is the routing data, then `commit: <full sha>` and `committed: true|false`; `committed: false` means no listed path was dirty, so the script made no commit. Exit 1: blocked; relay the script's stderr: one `outside:` line for each dirty path not in the list, as a JSON string, then the `blocker:` line.

## Silence Discipline

Follow `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Silence Discipline). The procedure
ends at the requirement 5 Bash call. Emit a blocker as
`printf 'blocker: <reason>' >&2; exit 1`. Never include a `status:` field in any output.

## Do Not

- create a branch, push, or open a PR
- include unrelated files
- commit on `trunk`
- stage or commit with your own git commands; only the script stages and commits
- paste the message or a path into a Bash command
- use the Write tool for anything other than the `.hivemind/molt-inputs-<token>.json` inputs file
- author the inputs file by any transport other than the Write tool; see
  `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
