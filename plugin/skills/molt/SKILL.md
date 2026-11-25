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
- `attribution`: this session's harness commit trailers, such as `Co-Authored-By:` and `Claude-Session:`, verbatim. Absent: none; this skill never judges or writes them.

When the caller passes both `files` and `subject`, skip requirement 2 and run no git command of your own: write the files from the given values and run the script.

## Requirements

Every commit runs through `${CLAUDE_PLUGIN_ROOT}/skills/molt/scripts/molt.sh`. It reads the message and the file list from files this skill writes with the Write tool, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern), so no message text or path enters a shell command.

**Input gate.** Before any Bash call, validate `trunk` against the identifier gate in `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Shell Identifier Discipline); on failure, exit 1 with `blocker: trunk contains characters outside the safe allowlist`.

1. Confirm current branch is not `trunk` and git state is not unsafe per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State). The script makes both checks, so this step runs no git command.
2. Review the staged and unstaged diff, unless the caller passed both `files` and `subject`.
3. Choose the files to commit: `files` when given; otherwise only the files of the completed phase, milestone, version bump or review-remediation item. List each path exactly, relative to the top of the work tree, including each deleted path and both sides of a rename; never a directory. The script refuses when any other path is dirty.
4. Write the message as `<type>(<optional scope>): <subject>`, where:
   - `<type>` is one of: `feat`, `fix`, `hotfix`, `refactor`, `docs`, `test`, `chore`, `ci`; it is `commit_type` when the caller passes it
   - `<subject>` is 72 characters or fewer; it is `subject` exactly as given when the caller passes it, and the script enforces its rules
   - include a body only when (a) the change reverts a prior commit, (b) the change includes a `BREAKING CHANGE:` footer, (c) the planner's delegation contains a `Why:` field, or (d) the orchestrator passes `commit_body` explicitly; otherwise omit it
   - the message holds no attribution string (any case), such as `Co-Authored-By:`, `Generated with`, `Created with Claude` or `🤖 Generated`, except `attribution`, last after one blank line, as git trailers; on a given `subject` with one, exit 1 with `blocker: subject contains a forbidden attribution string`, never rewriting it
   - when `breaking` is true, the script adds `!` before the colon; a `BREAKING CHANGE:` footer or `!:` in the subject needs `breaking` true.

   Then, with the Write tool and a `<token>` new for each invocation, at most 58 letters, digits and `-`, write each `content` to its `file_path`: the raw subject to `.hivemind/molt-inputs-<token>-subj.json`; the files, one path per line, to `.hivemind/molt-inputs-<token>-files.json`; only with a body or `attribution`, the raw body then `attribution`, each if any, to `.hivemind/molt-inputs-<token>-body.json`; then one JSON object to `.hivemind/molt-inputs-<token>.json`:

   ```json
   { "type": "<type>", "scope": "<optional scope>", "breaking": false }
   ```

   Leave out `scope` when there is none; the script header gives each rule. If a Write call does not succeed, stop blocked per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
5. **Final Bash tool call.** Run the commit script, where `<allowlist-validated-trunk>` is the value that passed the input gate and `<token>` is the token from requirement 4:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/molt/scripts/molt.sh" --trunk <allowlist-validated-trunk> --inputs .hivemind/molt-inputs-<token>.json --subject-file .hivemind/molt-inputs-<token>-subj.json --files-file .hivemind/molt-inputs-<token>-files.json [--body-file .hivemind/molt-inputs-<token>-body.json]
   ```

   Pass `--body-file` only with a body or `attribution`. Exit 0: stdout `branch: <branch>` is the routing data, then `commit: <full sha>` and `committed: true|false`; `committed: false` means no listed path was dirty. Exit 1: blocked; relay the script's stderr, `outside:` lines then the `blocker:` line.

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
- use the Write tool for anything other than the `.hivemind/molt-inputs-<token>.json` inputs file and its `-subj.json`, `-files.json` and `-body.json` files
- author any of them by any transport other than the Write tool; see
  `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
