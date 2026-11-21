# Settled approval and opt-in auto-merge in the post-PR watch

**Status:** accepted, 2026-11-20. Amends ADR-0026 (the consequence "the merge action always stays with the human"). Extends ADR-0043 decision 5.

## Context

The post-PR watch (`hivemind:github-review-loop`) ends clean on a Reviewer Approval (ADR-0043 decision 5). An in-scope Automated Reviewer's latest review is `APPROVED`, or is `COMMENTED` with no inline comments, or the bot left a 👍 on the PR. That covers a Copilot review with no inline comments, whatever its text says.

One case is not covered. A bot leaves inline threads. HIVEMIND fixes and resolves them. The bot never reviews again. No approval ever fires, so the watch idles until `watch-window-elapsed`. The user then has to see that the PR is done and merge it by hand.

The user asked for two things: an approval that fires in this case, and an opt-in merge at the end of a clean watch. The decisions below come from a plan-interrogation session with the user on 2026-11-20.

## Decision

### The user's decisions

1. **Settled approval.** The change-detect poll gets a clock-based marker, `REVIEWER_SETTLED`. It fires when all of these hold:
   - No marker has printed for a fixed settle period, `SETTLE_SECONDS` (600, about 10 minutes), since the arm or the last `CHANGED` or `CI_FAILED`.
   - An in-scope Automated Reviewer has reviewed or 👍'd the PR, and no latest review of any author is a standing request for changes (decision 14).
   - Every review thread is resolved or ends in HIVEMIND's own reply, and the thread read is complete.

   It reads no review text. The skill handles `REVIEWER_SETTLED` exactly like `REVIEWER_APPROVED`: a confirmation pass, the QUIET-EXIT CHECK, then `approval-clean`. The seed shape and the clock reads are unchanged.
2. **A fixed script merges, with no AI judgment.** The script is `merge-approved.sh`, inside the watch. The skill runs it once after an `approval-clean` end. The overlord makes no merge decision; the script's checks are the whole rule.
3. **`--admin` sits behind a second setting.** `HIVEMIND_AUTO_MERGE_ADMIN` allows it. The script uses `--admin` only when the plain merge is refused, the setting is set, and its own check saw every check pass.
4. **Merge only after approval with every check green.** The PR must be approved and the head commit's check rollup must be `SUCCESS`, CI included. The merge call uses `--match-head-commit`, so a push after the check cannot be merged unchecked.

### The run's own calls

5. **Pending CI keeps the watch running.** Pending or failed checks never merge and never end the watch. A CI failure still gets fixed, and the merge is tried again at the next settled approval.
6. **No checks means no merge.** A head commit with no check rollup is not green.
7. **Any open thread blocks the merge.** A thread that is not resolved and does not end in HIVEMIND's reply stops the script.
8. **The setting value names the method.** `HIVEMIND_AUTO_MERGE` is `merge`, `squash` or `rebase`. Unset or empty means off. Any other value is refused, and nothing merges.
9. **The script rechecks approval itself.** It does not trust the skill's end reason. It checks again that the PR is open and not a draft, that an in-scope bot reviewed or 👍'd and no latest review of any author is a standing request for changes (decision 14), that every thread is settled, and that the rollup is `SUCCESS`.
10. **The skill routes the script's one line.** The skill runs the script only after an approval return whose QUIET-EXIT CHECK reports `UNCHANGED`. No other end runs it, `merge-advised` included. `MERGE=off` ends `clean`, as before. `MERGE=merged` or `MERGE=merged-admin` ends `pr-merged`, through `loop-state.sh token-map STATE=MERGED`, with the line under `Issues` (decision 16 says when the script prints them). `MERGE=skipped:*`, `MERGE_ERROR=`, a non-zero exit or a refused call ends `clean`, with the line under `Issues` and a `Next action` that tells the human to merge.
11. **A wait keeps watching in the current window.** `MERGE=wait:*` ends nothing. The skill arms the poll again with the pending seed for the time left in the current idle window. That arm opens no new window and captures no seed, so a PR whose CI never turns green ends at `watch-window-elapsed`.
12. **An empty `HIVEMIND_AUTO_MERGE_ADMIN` is off.** The setting is checked by presence, like the other `HIVEMIND_*` presence settings, and an empty value counts as unset. Only a non-empty value allows `--admin`.

### Recorded review decisions

13. **A fresh blocked or behind read is the refusal signal for `--admin`.** Decided by the run under `plugin/governance/decision-autonomy.md` (Review Calls), on a local-review finding, 2026-11-20. After a failed plain merge the script does not read the error output and does not prove why the merge failed: a network, login or CLI error counts the same as a branch-protection refusal. The `--admin` retry runs only when a fresh read shows the same head, GitHub's merge state `BLOCKED` or `BEHIND`, and every gate passing again. GitHub then reports that a plain merge would be refused anyway, so the admin merge happens under the conditions decision 3 allows. Parsing the tool's error text was rejected as fragile text matching. A finding that only says the first failure may not have been a branch-protection refusal contests this decision and is a repeat.
14. **Approval is the review state, not author presence.** Decided by the run under `plugin/governance/decision-autonomy.md` (Review Calls), on a local-review finding, 2026-11-20. The finding: the merge gate and the poll's settle evidence counted a bot's presence among the latest reviews as approval, so a bot review that requests changes, or a human or null-author one, could merge. One shared module def, `has_settled_evidence` in `reviewer-identity.jq`, is now the only settled-evidence verdict, and the settle check and the merge script's approval gate both call it. Every latest review of any author, null-author rows included, must be in the allowlist `APPROVED`, `COMMENTED` or `DISMISSED`; `CHANGES_REQUESTED`, `PENDING`, a missing state or an unknown state blocks. Approval then needs an in-scope bot whose latest review is `APPROVED` or `COMMENTED`, or an in-scope bot's 👍. A human's `CHANGES_REQUESTED` therefore also blocks the merge, failing closed. A blocked merge prints `MERGE=skipped:no-approval`, as before; no setting, output line or marker is added. `REVIEWER_APPROVED` is unchanged (ADR-0043 decision 5): it can still fire on one bot's approval while another author's latest review requests changes, but that only ends the watch, and the merge script now refuses the merge.
15. **A review state change in the seconds before the merge call is a known limit.** Decided by the run under `plugin/governance/decision-autonomy.md` (Review Calls), on a local-review finding, 2026-11-20. The merge script reads reviews, threads, draft state and checks, then calls `gh pr merge`. A review that requests changes, or a reopened thread, landing between that last read and the merge call, plain or `--admin`, is not seen. `--match-head-commit` pins only the head commit; GitHub offers no merge call that also pins review or thread state, so no client-side check can close the gap, and the window is a few seconds. The code is kept as it is. Requiring GitHub's branch protection for the plain merge was rejected: it adds a protection read, does not cover the `--admin` retry decision 3 allows, and only narrows the plain path. A finding that only says review or thread state can change between the script's last read and its merge call contests this decision and is a repeat.
16. **A merge is what GitHub shows, not the merge call's exit status.** Decided by the user on a GitHub review finding (https://github.com/brenpike/hivemind/pull/602#discussion_r4650841549), 2026-11-21. In a merge-queue repo `gh pr merge` exiting 0 only queues the PR; it is not merged yet. After every merge call that exits 0, plain or `--admin`, the script re-reads the PR. It prints `MERGE=merged` or `MERGE=merged-admin` only when the state is `MERGED`, and `MERGE=wait:merge-pending` otherwise. Decision 11 routes that line, so the watch keeps running and the poll's `STATE=MERGED` ends it at `pr-merged`. A failed confirm read prints `MERGE_ERROR=`. A finding that asks to end the watch on the merge call's exit status contests this decision and is a repeat.

## Considered options

- **Read review text for a settled verdict**, such as Copilot's "Approval Recommended". Rejected: product wording in code and text matching on external content, as ADR-0043 rejected.
- **Ask the reviewer for a new review after the fixes.** Rejected: ADR-0043 decision 7, the loop never requests a review.
- **A long settle period, or one set per repo.** Rejected: the user chose a short fixed period. A setting adds surface for a value nobody has asked to tune.
- **The overlord judges whether to merge.** Rejected: the user chose no AI judgment. A fixed script is the same every run and can be tested.
- **`--admin` under the same setting as the merge.** Rejected: bypassing branch protection is a bigger grant than merging, so the user put it behind its own setting.
- **Merge while CI is pending, or with GitHub's own auto-merge.** Rejected: the user chose to merge only when every check is green, and the watch must stay up to fix a CI failure.
- **One on/off setting plus a separate method setting.** Rejected: one value that names the method is enough.
- **Read every latest review as approval evidence, whatever its state.** Rejected: a review that requests changes, or a human or null-author review, would count as approval and could merge. Decision 14 keys approval on the review state instead.
- **Drop the script's merged result and let the poll end every merge.** Rejected: the poll checks its deadline before it reads the PR, so a merge that lands late would end at `watch-window-elapsed`, and the `--admin` note would be lost.
- **Record that auto-merge does not support merge queues.** Rejected: queue repos would keep the false `pr-merged` end, and decision 16 handles them.

## Consequences

- With `HIVEMIND_AUTO_MERGE` unset, nothing merges. The merge stays with the human, as before.
- With it set, ADR-0026's consequence "the merge action always stays with the human" no longer holds for that repo. The overlord still never decides a merge, and a merge recommendation outside the watch stays Tier-A. Only the fixed script merges, and only after a clean watch.
- With `HIVEMIND_SKIP_PR_WATCH` set (ADR-0029), no watch runs, so nothing merges.
- A watch that ends any way other than `approval-clean` merges nothing.

### Residuals

- **A slow bot re-review can be cut off.** A bot that starts a new review more than 10 minutes after the last fix can find the PR already merged. Its findings then need a new PR.
- **An unreviewed push by another account can merge.** If another account pushes to the branch, the push can merge once its checks are green and approval fires again. No bot needs to have reviewed that push.
- **A stray bot 👍 can now lead to a merge.** Under ADR-0043 a bot's 👍 makes it an Automated Reviewer. With the setting on, that 👍 can lead to a merge when no thread is open and every check is green. Before this ADR it could only end the watch.
- **Auto mode can refuse the merge call.** The permission system may refuse `gh pr merge` in auto mode. The script then reports the refusal and the PR stays open for the human.
- **Committed settings turn auto-merge on in brood worktrees.** `HIVEMIND_AUTO_MERGE` set in the committed `.claude/settings.json` is inherited by every brood worktree, so every strain's PR can merge. Set it in `.claude/settings.local.json` to keep it to one checkout.
- **A merge queue can outlast the idle window.** A queue slower than the time left in the idle window ends the watch at `watch-window-elapsed` while the PR is still queued. A queue that drops the PR leaves it open for the human.

References: `plugin/skills/github-review-loop/SKILL.md`, `plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh`, `plugin/skills/github-review-loop/scripts/merge-approved.sh`, `plugin/governance/decision-autonomy.md`; amends ADR-0026; extends ADR-0043.
