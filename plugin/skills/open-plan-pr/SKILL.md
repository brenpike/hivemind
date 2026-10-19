---
name: open-plan-pr
description: Opens a pull request for a successfully completed approved plan after final verification. Use when validation and versioning gates have passed and the plan is ready for PR.
allowed-tools:
  - Bash(git status *)
  - Bash(git branch *)
  - Bash(git log *)
  - Bash(git diff *)
  - Bash(git rev-parse *)
  - Bash(git config --get *)
  - Bash(git push *)
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
- [ ] PR head SHA matches local HEAD
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

1. Confirm current branch matches `head` and is not `base`.
2. Confirm no unexpected unstaged changes.
3. Confirm validation outcome per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Validation Procedure) is one of: every declared command passed, OR `Not run (no validation commands defined)`. Exit 1 with blocker if the procedure returned the Worker Report — Blocked (`stage: validation`) or any declared command failed.
4. Confirm required version/release metadata is included or not required.
5. Capture local HEAD SHA: `git rev-parse HEAD`.
6. Place the working branch on a remote that `gh pr create` can target:
   - if `push_remote` is provided: `git push -u <push_remote> <head>`. On failure, exit 1 with blocker.
   - else if upstream tracking is set: first confirm the upstream is the branch's own name, then run `git push`. An upstream under any other name, such as trunk, would make this push or the force-with-lease retry below target that branch. Capture the branch and its upstream ref OUT-OF-BAND in the same Bash call and reference them only as `"$var"`, the same technique as `hivemind:push-branch` requirement 4:
     ```bash
     b="$(git rev-parse --abbrev-ref HEAD)"
     ref="$(git config --get "branch.$b.merge")"
     [ "$ref" = "refs/heads/$b" ] || { printf 'blocker: upstream does not match the working branch' >&2; exit 1; }
     git push
     ```
     Step 1 confirmed `head` is not `base`, so with the upstream at `refs/heads/<head>` neither the push nor the retry below can target trunk.
     - on success: continue with that remote.
     - on **non-fast-forward** failure: retry once with a refspec-scoped force-with-lease against the tracked upstream ref. Read remote and upstream ref via git plumbing (string-splitting on `/` is unsafe — branch names like `feature/foo` and rare remote names with `/` make any single-slash split incorrect):
       - `<remote>` = `git config --get branch.<head>.remote`
       - `<upstream_ref>` = `git config --get branch.<head>.merge` (yields `refs/heads/<upstream_branch>`)
       - `<upstream_branch>` = `<upstream_ref>` with the `refs/heads/` prefix stripped
       Run `git push --force-with-lease <remote> HEAD:<upstream_branch>`. The explicit `HEAD:<upstream_branch>` refspec targets the actual tracked branch — not the same-named branch on the remote, which may differ when the local branch tracks a renamed upstream (`push.default=upstream` or explicit branch mapping). Force-with-lease without a value uses the remote-tracking ref as expected, so it succeeds only when the remote tip matches what the local clone last fetched, which covers intentional history rewrites (rebase, amend) without overwriting concurrent pushes.
       - on FWL success: continue.
       - on FWL failure: exit 1 with blocker. Remote has commits the local clone has not seen.
     - on **auth / read-only / protected branch / hook-policy** failure: record warning and continue. `gh pr create` may route to a fork or alternate remote. Treat as auth/read-only/protected/hook-policy when stderr contains any of: `Permission denied`, `remote: Permission`, `protected branch`, `403`, `401`, `[remote rejected]`, `remote rejected`, `pre-receive hook`, `update hook`, `push declined`. Treat as non-fast-forward only when stderr contains `non-fast-forward` OR `(fetch first)`. Bare `rejected` is not a non-fast-forward marker on its own (`[remote rejected]` is server-side and is not resolved by force-with-lease).
   - else (no upstream, no `push_remote`): when `git config --get remote.origin.url` succeeds, run `b="$(git rev-parse --abbrev-ref HEAD)"; git push -u origin "HEAD:$b"` so the first push sets the branch's own upstream. The branch is derived OUT-OF-BAND as HEAD (confirmed `== head` in step 1), so no branch bytes are pasted into command text. On failure, record a warning and continue to step 7.
     - when `git config --get remote.origin.url` fails (no `origin` remote): defer to `gh pr create` in step 7. It prompts for push target and can fork the base repo.
7. Run `gh pr create --base <base> ...` with title, summary, validation notes, version/release notes, and unresolved issues. Do not pass `--head` — `--head` makes `gh` skip its push/fork fallback, which defeats step 6's fork-based and unpushed-branch handling. `gh pr create` uses the current branch as head by default; confirm step 1 already verified current branch matches the intended `head`.
8. **Final Bash tool call.** Verify PR head SHA matches local HEAD using allowed command patterns. Each Bash call is independent — substitute literal captured values from prior steps (not shell variables).

   First, capture the remote PR head SHA:

   ```bash
   gh pr view <pr> --json headRefOid --jq '.headRefOid'
   ```

   Where `<pr>` is the PR number or URL from step 7. The output is the remote head SHA. Compare it with the local SHA captured in step 5. If they differ, exit with blocker (substitute the literal SHA values):

   ```bash
   printf 'blocker: PR head SHA mismatch — expected %s got %s' "<local_sha>" "<pr_sha>" >&2; exit 1
   ```

   If they match, emit YAML routing data as the final Bash tool call (substitute the literal SHA):

   ```bash
   printf 'url: %s\nhead_ref_oid: %s\n' "$(gh pr view <pr> --json url --jq '.url')" "<pr_sha>"
   ```

   On success (SHA matches), the YAML output (`url` + `head_ref_oid`) is the routing data. On mismatch, exits 1 with blocker in stderr.

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
