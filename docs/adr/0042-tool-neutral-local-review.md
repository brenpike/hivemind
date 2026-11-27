# Local review is tool-neutral

**Status:** accepted, 2026-11-16

## Context

Local pre-PR review was hard-wired to Codex. `hivemind:adaptation-cycle` found the `codex-plugin-cc` companion script and ran its `adversarial-review` command. The overlord set `local_review: false` when the Codex plugin was not installed.

Some users cannot use Codex. At work, one user has only GitHub Copilot. That user had to override the review by hand in every request ("do a local adversarial review using copilot CLI instead"). The agent then made up a prompt and an output format each time, and nothing checked the result.

The decisions below come from a plan-interrogation session with the user on 2026-11-16. https://github.com/brenpike/hivemind/issues/581 records them.

## Decision

1. **Hivemind owns the review.** The plugin ships one adversarial-review prompt and one findings JSON schema. The `codex-plugin` preset still calls the Codex plugin's own command.
2. **One setting picks the reviewer.** `HIVEMIND_LOCAL_REVIEWER`, set in the settings `env` block, holds a preset name (`codex-plugin`) or a JSON argv list. If one element is exactly `"{prompt}"`, the whole prompt replaces it as one argv element. Otherwise the prompt goes on stdin. No shell runs the command. When the setting is unset, the `codex-plugin` preset runs if the Codex plugin is installed; else local review is skipped. Examples: `["codex","exec","--sandbox","read-only","-"]` and `["copilot","-p","{prompt}","-s","--no-ask-user","--deny-tool=write","--deny-tool=shell"]`.
3. **Change input by size.** A diff of about 64 KB or less goes inline in the prompt. This stays under the 128 KB Linux limit for one argument. A larger diff goes to a file under `.hivemind/`, and the prompt points at it. Every finding must cite a file the branch changes. A finding on any other file is dropped and counted (Implementation decisions, item 2).
4. **Prompt and schema come from the Codex plugin.** They are copied from `prompts/adversarial-review.md` and `schemas/review-output.schema.json` (Apache-2.0, Copyright 2026 OpenAI) and adapted. The copies carry the license attribution and mark the changes. The prompt states that the review is read-only.
5. **Output parsing is strict.** The parser accepts bare JSON, or JSON inside one ```` ```json ```` fence with nothing else around it. Any other output is blocked as an unexpected output shape.
6. **Cannot run means skip; bad output means blocked.** The review cannot run when the setting is unset and Codex is not installed (`no-reviewer`), the setting is invalid (`bad-setting`), the tool is missing (`tool-missing`), the tool fails, for example the user is not signed in or the tool crashes (`tool-failed`), or the review's time limit passes (Implementation decisions, item 4), which is `timed-out`. Then local review is skipped, and the PR opens with a warning in the PR body and in the final report. A review that ran but returned bad output is blocked. A tool failure that states a retry time, and a permission refusal of the script call, are not skips (Implementation decisions, items 1 and 7).
7. **`HIVEMIND_LOCAL_REVIEW_MODEL` is retired.** Hivemind never names a model. Each tool uses its own default or its own config.
8. **The overlord always requests local review,** unless the request skips it. The review skill decides whether the review can run. Codex mentions leave the overlord and the workflows.
9. **One plugin script runs every reviewer.** `run-review.sh` is granted through the skill's `allowed-tools` with a `${CLAUDE_PLUGIN_ROOT}` path. The hand-written `Bash(node /path/to/.claude/plugins/cache/openai-codex/codex/*)` rule and its docs are removed.
10. **Before and after check.** The script records `git status` and HEAD before the review. Any change after the review is blocked as "reviewer modified the working tree". The change is never reverted automatically. The check guards only files a commit could carry: HEAD, tracked files and untracked files that are not ignored. It does not see ignored files, such as `.claude/settings.local.json` or `.hivemind/`, or paths outside the repo. Those rely on the review tool's own sandbox. User decision, 2026-11-16: a finding that asks the check to cover them repeats this decision.

## Implementation decisions (2026-11-16)

These were settled while the change was built. Each names who decided it.

1. **A tool failure with a retry time keeps the bounded wait.** The failure states when the tool is back, for example a usage or rate limit with a retry time. The review then ends blocked with `retry_minutes`. The run waits, within its existing bounds, and reviews again. User decision.
2. **Inside the diff means a changed file.** A finding is inside the diff when it cites any line of a file the branch changes. The path is the new-side path. Findings on unchanged files are dropped and counted. This replaces the reading that a finding must sit within 3 lines of a hunk. User decision.
3. **The `codex-plugin` preset uses `--json`.** Its `.result` is checked against the same schema as every other tool. Run decision.
4. **`run-review.sh` derives the review's time limit from the call budget.** The budget is 570 seconds: the Bash tool's 600-second cap less 30 seconds. The limit is the budget less the seconds the script has already spent, less twice the before-snapshot time and the 5-second kill grace. When under 60 seconds are left, the review ends `timed-out` without running. The reviewer runs only under `timeout` or `gtimeout`. With neither, the review ends `tool-missing` before any other work, so it never runs unguarded. An after-check that overruns its reserve ends the call at the Bash cap, and the skill blocks with `review timed out`: it ends blocked, never passed. This replaces the fixed 590-second timeout. The user decided the direction and the run decided the numbers, 2026-11-16, local review findings 1f00e281 and 1312c326.
5. **The devcontainer stops seeding the Codex node grant.** The grant is dead now that `run-review.sh` runs every reviewer. Run decision.
6. **A skip holds for the rest of the run.** Later gate reruns do not retry local review. Run decision.
7. **A permission refusal is blocked, not skipped.** When the permission system refuses the `run-review.sh` call, local review ends blocked. So a broken grant is noticed. User decision.
8. **A finding id frames its fields.** `finding_id` is the SHA-256 digest of the JSON array text `[file, line_start, line_end, title]`. Before, the fields were run together, so lines 1-123 and lines 11-23 of one file with the same title got the same id. Every id now differs from the ids earlier versions gave. Nothing is keyed on an id across runs (ADR-0038 decision 4). User decision on the direction, 2026-11-16, local review finding 6cda4fe1.
9. **Review tool excerpts are shown unredacted (recorded residual).** The `tool-failed` skip's `stderr_excerpt` is the trimmed stderr, or the trimmed stdout when stderr is blank, cut to its last 300 code points with `...` in front when cut. The `unexpected output shape` blocker's `raw_excerpt` is the trimmed stdout cut to its first 200 code points. Neither is redacted. Ground: outside the threat model, as the review tool is the command the operator configured. Bounded impact: each excerpt is capped, JSON-encoded and shown only in the local session, and the local reviewer reports in its own words, never copying review tool text (`plugin/agents/local-reviewer.md`, Output Contract). User decision, 2026-11-16, local review finding fa3c6d4a. A finding that asks to redact or drop these excerpts repeats this decision.
10. **Cleanup never deletes recursively.** `run-review.sh` removes only the files it wrote in its work folder, each by name from one list, then the folder itself when it is empty, and its large-diff file. It sets a path for cleanup only after `mktemp` exited 0 and checks confirmed the result: the folder is a real, empty directory, the diff file is an empty regular file, and neither is a symlink. Otherwise the run is blocked and the path is left in place. So cleanup never deletes a path the run did not create. User decision, 2026-11-16, local review finding 8957ae52.

Skip reasons are exactly `no-reviewer`, `bad-setting`, `tool-missing`, `tool-failed` and `timed-out`.

## Considered Options

| Option | Rejected because |
|---|---|
| Send the prompt on stdin only | Copilot ignores piped input when `-p` is given. The `{prompt}` slot covers tools like it |
| Always put the diff in a file | A tool could skip reading the file and review nothing. Small diffs go inline so the tool sees them |
| Retry once on bad output | A retry doubles the cost of a review. Bad output is blocked instead |
| Keep a model setting | Every model update would need a config change. Each tool already has its own default and config |
| An allow rule per tool | Each rule needs a hardcoded path to the tool. One plugin script with a `${CLAUDE_PLUGIN_ROOT}` grant covers every tool |

## Consequences

- **Breaking change: 9.0.0.** `HIVEMIND_LOCAL_REVIEW_MODEL` is removed. This supersedes the model override in ADR-0022 supporting decision (a). The rest of ADR-0022 stands.
- **Auto mode approves the script, not the command.** The permission grant covers `run-review.sh`. The command the setting names runs inside it without its own approval. The user accepted this trade-off.
- **A skipped review is visible.** The PR body and the final report both carry the skip warning.
- **Out of scope: the post-PR watch.** The GitHub review watch is not changed here. https://github.com/brenpike/hivemind/issues/576 tracks it.

Links: https://github.com/brenpike/hivemind/issues/581, https://github.com/brenpike/hivemind/issues/576, https://github.com/brenpike/hivemind/issues/409, `docs/adr/0022-local-review-parity-with-post-pr-review.md`.

## Amendment 2026-11-25: tolerant output parsing, skip after a blocked exit, per-branch fix ledger (issue 673)

Issue 673 found that real review tools wrap their JSON in prose or fences, and that a skip after a blocked exit still forced a draft PR. Four decisions follow. Decision 5 is amended. Decision 6 stands.

1. **Output parsing is tolerant, still schema-checked.** This amends decision 5. For a generic run, `run-review.sh` accepts a trimmed reply that is any one of:
   - one JSON object;
   - exactly one fenced block, opened by ```` ```json ```` or a plain ```` ``` ```` and a line break and closed by ```` ``` ````, with one object inside;
   - one object from the first `{` to the last `}`, with no `{`, `}`, `[` or `]` outside it.

   For the `codex-plugin` preset, when `.result` is not an object and `.rawOutput` is a string, the same rule applies to `.rawOutput`. Every other reply stays `unexpected output shape`. The schema check stays.
2. **Retry stays rejected.** A shape failure is not retried. The Considered Options row "Retry once on bad output" stands.
3. **A skip after a blocked exit is local review that did not run.** When the user replies to a `blocked` exit by skipping local review, `plugin/governance/workflow.md` (PR Requirements) treats it as local review that did not run. It neither holds nor blocks the PR, so it no longer forces a draft. The PR body and the final report name the skip and its reason. The overlord's Instinct delivery gate points at that clause. On the workflow script, the blocked-review question for a blocked exit with no retry time offers the skip as option B ("skip local review for this run"). A reply of the letter B drops local review for the rest of the run, named `skipped (user-reply)` in the PR body and the final report. Option A, or a reply in the user's own words, reruns local review. The skip after a blocked exit so holds on both delivery paths.
4. **The fix ledger is one flat file per branch.** The path is `.hivemind/review-loop/<working_branch>.yaml`, with each `/` in the branch name written `~`. Git forbids `~` in branch names, so no two branches share a file. One flat folder keeps the existing `Edit(.hivemind/review-loop/*)` and `mkdir -p .hivemind/review-loop` permission rules covering it. A nested path was rejected because `*` matches one path segment only. The engine passes `fixLedgerPath(plan.branch)`. This supersedes the fixed path `.hivemind/review-loop/fix-ledger.yaml` named in ADR-0037 and ADR-0041. Those records are left as they are. The old file is no longer read or written.

User decision, 2026-11-25: decisions 1 to 4.

Links: https://github.com/brenpike/hivemind/issues/673.

## Amendment 2026-11-26: whole diff in every prompt, too-large skip, preset through the companion task command (issue 684)

Issue 684 found a local review that passed without reading the whole diff. In a delivery on 2026-11-25, the review read about 760 of 1237 diff lines and gave the verdict `approve`. An input over 64 KB went to a file, and the tool read that file its own way. The `codex-plugin` preset (companion 1.0.6) inlines a diff only up to 2 files and 256 KiB. Past that, Codex collects the diff itself. Nothing checked coverage. Three decisions follow. Decisions 1, 3 and 6 and Implementation decisions, item 3, are amended.

1. **Every prompt holds the whole review input.** This amends decision 3. The review input is the commit log, the diff stat and the full diff. There is no file mode, and the script writes only its own work files, in a private folder under `${TMPDIR:-/tmp}`. The limit is on the review input, measured before the prompt is built. It is 65536 bytes when the prompt fills a `{prompt}` argv element, for the same per-argument reason as before: the fixed template and schema add about 7 KiB, so the prompt stays well under the 128 KiB limit for one argument, and an argv too long to run ends `skipped: tool-missing`. It is 262144 bytes on stdin and for the `codex-plugin` preset. That matches the companion's own inline cap. The large-diff file in Implementation decisions, item 10, goes with the file mode.
2. **Too large means skip.** This amends decision 6. A review input over its limit ends `skipped: too-large`, before any snapshot or run. Skip reasons are exactly `no-reviewer`, `bad-setting`, `tool-missing`, `tool-failed`, `timed-out` and `too-large`. This supersedes the list under Implementation decisions. The fallback follows `docs/engineering-principles.md` P26: local review did not run, and the PR body and the final report name the skip with its reason. The `skipped:` and `blocker:` output shapes stay, so `hivemind:design-review` needs no change. Two blockers go: cannot prepare the review diff file, and cannot remove it.
3. **The preset runs the companion's `task` command.** This amends decision 1 and Implementation decisions, item 3. The preset still runs the Codex plugin's own command. It runs `task`, in its read-only sandbox by default, with Hivemind's prompt on stdin and `--json`. Its `.rawOutput` goes through the shape rules of the 2026-11-25 amendment, decision 1, and is checked against the same schema. `.result` is no longer read. Trade-off: Codex's `outputSchema` enforcement is lost. Tolerant parsing covers it.

These options were rejected:

| Option | Rejected because |
|---|---|
| Echo a coverage token from the last line of the prompt | It proves the end was read, not the middle. It needs a schema change, and the preset cannot carry it |
| Split the diff over several reviewer runs | It does not fit the 570-second call budget. It loses context across files |
| Keep the file mode with an instruction to read it all | The issue 684 run shows the instruction does not bind |
| Keep the preset on `adversarial-review` and record coverage unchecked | It leaves the default reviewer, the likely path of the issue 684 run, unfixed |
| Skip the preset whenever the companion would collect the diff itself | It mirrors companion internals and skips nearly every real branch |

Recorded residual: a tool that truncates or compacts its own prompt is outside what the script can see. The impact is bounded. 256 KiB is about 70,000 to 85,000 tokens, well under the context windows of current reviewers.

Threat-model residual: the reviewer's output has no byte cap. `run-review.sh` writes the reviewer's stdout and stderr to temporary files, and only the call's 570-second budget, with its process-group kill, bounds them. The reviewer is a command the operator set up. It runs with the user's own rights, so it could fill the disk without the script. Trunk has the same code. Run decision, 2026-11-26, under `plugin/governance/decision-autonomy.md` (`### Review Calls`), listed for veto on the PR.

Threat-model residual: `TMPDIR` is operator environment. `run-review.sh` makes its work folder under `${TMPDIR:-/tmp}` and does not refuse a `TMPDIR` inside the work tree under review. The impact is bounded. The files are local and private, and they are removed at exit. When they are not ignored, the before/after check blocks the run as `reviewer modified the working tree`, so the run fails closed and never passes falsely. This is outside the threat model: `TMPDIR` is operator environment, like the reviewer command. User decision, 2026-11-26, local review finding d3b592ef, listed on the PR.

Threat-model residual: the base ref is resolved at each read. `run-review.sh` checks once that the base names a commit and pins HEAD to one SHA, but it resolves the base name again at each of the four branch-diff reads (the changed-path list, the log, the stat and the diff). The impact is bounded. It needs a concurrent ref move on the base in the reviewed checkout, such as a commit, fetch or pull, during the seconds of collection. The reviewer then sees a mismatched input. It cannot make a failing review pass or write the work tree, and the before/after check still holds the work tree. This is outside the threat model: a concurrent git move of the base or HEAD during a review is operator activity, like `TMPDIR` and the reviewer command. User decision, 2026-11-26, rejecting the local review root cluster (findings ed9fc7a5, 0e8c0119, 12ceae9c, 6a5820f4), listed on the PR.

User decision, 2026-11-26: decision 3. Run decisions under the request's delegation, listed for veto on the PR: decisions 1 and 2 and the rejected options.

Links: https://github.com/brenpike/hivemind/issues/684.
