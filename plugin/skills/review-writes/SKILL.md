---
name: review-writes
description: Pre-approves push-branch.sh, reply-resolve.sh and react-marker.sh for the rest of the invoking turn and runs no command. Invoke right before the first such call.
user-invocable: false
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/push-branch/scripts/push-branch.sh" *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reply-resolve.sh" *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/react-marker.sh" *)
shell: bash
---

This skill runs no command.

Its allowed-tools pre-approve exactly three scripts, each by its plugin-root path, for the rest of the turn that invokes it:

- `${CLAUDE_PLUGIN_ROOT}/skills/push-branch/scripts/push-branch.sh`
- `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reply-resolve.sh`
- `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/react-marker.sh`

No settings rule is needed for these calls.

Invoke it right before the first such call, after any other skill call. No other skill invocation may come between the grant and the writes.

The caller runs each script in its own documented form. This skill restates none of them.

Deny and ask rules still win. A refused call is the caller's to handle.

This completes this skill's own procedure. The skill then returns control to whatever invoked it; the caller then continues from the point at which it invoked this skill.
