---
name: merge-write
description: Pre-approves merge-approved.sh for the rest of the invoking turn and runs no command. Invoke right before that call.
user-invocable: false
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/merge-approved.sh" *)
shell: bash
---

This skill runs no command.

Its allowed-tools pre-approve exactly one script, by its plugin-root path, for the rest of the turn that invokes it:

- `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/merge-approved.sh`

No settings rule is needed for this call.

Invoke it right before that call, after any other skill call. No other skill invocation may come between the grant and the call.

The caller runs the script in its documented form. This skill restates none of it.

Deny and ask rules and managed-only rules still win. A refused call is the caller's to handle.

This completes this skill's own procedure. The skill then returns control to whatever invoked it; the caller then continues from the point at which it invoked this skill.
