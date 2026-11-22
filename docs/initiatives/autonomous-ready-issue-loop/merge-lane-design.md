# Solution design: Lair merge lane

This is the solution design for the Lair's merge lane, issue #631, a sub-issue of epic #603. It links the [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md), [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md) and the [solution design](solution-design.md) rather than restating them. It cites them as "ADR-0045 decision N" and "ADR-0044 decision N"; decisions 17 to 20 are those of ADR-0044's 2026-11-21 amendment. Its design review is recorded in the [merge-lane review record](merge-lane-review-record.md). For the merge lane, this design supersedes these parts of solution-design.md:

- the Component "Merge lane and auto tier";
- the GitHub-record, park and halt side of the Component "Post-PR remediation strains", and the start of a fix-up run for failed checks (the CI-red rule); what starts a fix-up run on review findings stays there, with #610, and this design sets preconditions on that trigger only where a binding source allows (Fix-up runs);
- the Contract "Auto-tier script result";
- the Contract "Strain result", extended by the field `local_review_head` (Assumptions about #630);
- every place that records a run end in the claim marker: in the Contract "Claim marker comment", its last sentence, "At run end the Lair adds `outcome` and `ended_at`."; the run-end update in the State and ownership row "Claim marker comment"; stage 1's "The Lair records the outcome in the claim marker"; and the claim-marker part of the Decision "The outcome recorded in the claim marker, and the circuit-breaker count scoped to the Lair session", whose session-scoped count stands. A run end goes into the run-end marker or the fix-up end marker (Markers the merge lane writes);
- the outcome list of the Component "Decision digest and circuit breaker", "failed, crashed or timed-out", which gains `stalled` from solution-design.md's own Stall row (Lifecycle, stage 4);
- the merge-settings part of the Trust boundaries channel list ("the halt file and the merge settings on the user's own machine");
- in Lifecycle: the `lair:handoff`, `lair:failed` and `lair:review` label bullets, for the run ends and exits this design names; stage 1's merge step; stage 3 whole; stage 4's merge stop; and the draft, closed-unmerged and claim-withdrawn exits, which solution-design.md does not have;
- the Failure modes rows "Crash", "Merge refused", "CI red" and "Issue edited after claim", and, for the merge lane only, the row "GitHub API failure or rate limit";
- the Decisions "Merges only through `merge-approved.sh` and its gates", "A red CI result gets one remediation strain, then `lair:review`" and "An issue edited after claim is not merged and goes to `lair:review`".

Every other part of solution-design.md stands.

## Context and code truth

The merge lane builds on this code, as it stands on trunk:

- `plugin/skills/github-review-loop/scripts/merge-approved.sh` takes exactly five arguments: owner, repo, pull request number, reviewer filter and self login. Any other count is `MERGE_ERROR=bad-arguments`. It reads `HIVEMIND_AUTO_MERGE`, `HIVEMIND_AUTO_MERGE_ADMIN` and `HIVEMIND_PR_REVIEWERS` from its environment. It prints exactly one line, a `MERGE=` line with exit 0 or a `MERGE_ERROR=` line with exit 1, and nothing on stderr.
- The script reads the PR once, then runs gates 1 to 7 in order: not open, draft, no settled evidence (`has_settled_evidence`), an open thread (`is_settled_thread`), no check rollup, pending (`PENDING` or `EXPECTED`), failed (`FAILURE` or `ERROR`). Only then does it call `gh pr merge` with `--match-head-commit` set to the head of that read. A read past its page is `MERGE_ERROR=read-incomplete`.
- That one read is `PR_QUERY` (lines 247 to 282). It holds the pull request's state, draft flag, head, merge state, check rollup, reviews, reactions and review threads. It holds no base, repository, author or branch name, so the script judges none of them. `--match-head-commit` pins only the head.
- `MERGE=wait:head-moved` already exists. Today it prints only after a refused plain merge, when the re-read shows a different head. The script has no way to be told which head the caller expects.
- A merge call that exits 0 is followed by a confirm read. `MERGE=merged` and `MERGE=merged-admin` print only when that read shows `MERGED`, else `MERGE=wait:merge-pending` (ADR-0044 decision 16). A failed confirm read is a `MERGE_ERROR=` line, though the merge call ran. No read of the script holds the pull request's merge-queue state.
- The script bounds each of its reads with `timeout` when present. Its header says merge calls are never wrapped, so a merge is never cut off.
- `tools/test_merge_approved.sh` runs the script against a PATH-shim `gh` that serves canned GraphQL bodies and logs every call. After the cases it checks five properties over every case, among them that every merge call carries `--match-head-commit` equal to the head of the read before it. Its case `args:six` passes a sixth argument, `extra`, and expects `MERGE_ERROR=bad-arguments`.
- `plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh` has three modes. `--snapshot <arm-kind>` prints one `BASELINE=<seed>` line, or `SNAPSHOT_ERROR`. `--check` compares one capture against a seed and prints one of `UNCHANGED`, `CHANGED`, `CI_FAILED`, `REVIEWER_APPROVED`, `STATE=MERGED`, `STATE=CLOSED` or `CHECK_ERROR`. It never sleeps, never reads the deadline and never prints `REVIEWER_SETTLED`. Only poll mode judges a settled approval, with `SETTLE_SECONDS=600` on its loop-top clock. Both one-shot modes still validate the window and interval arguments as integers.
- The seed carries its arm kind. Under an `initial` seed an approval already present fires `REVIEWER_APPROVED`. Under a `re-arm` seed the approval edge counts as observed and does not fire again.
- `plugin/skills/github-review-loop/scripts/reviewer-identity.jq` holds `has_settled_evidence` and `is_settled_thread`. They are the only settled-evidence and settled-thread verdicts. The poll and the merge script both call them (ADR-0044 decision 14).
- The merge rule in `plugin/skills/github-review-loop/SKILL.md` runs `merge-approved.sh` with five arguments, once, only after an approval return whose QUIET-EXIT CHECK reports `UNCHANGED`, and routes its line for the watch alone. The skill's `allowed-tools` grant is `Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/merge-approved.sh" *)`. Its `max_watch_duration` default is `3600` seconds, recorded in ADR-0029's Findings.
- `plugin/governance/decision-autonomy.md` Tier A holds the bullet "every merge recommendation; the human merges, except the review watch's opt-in merge after a reviewer approval, per `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/SKILL.md`". `tests/policy/safety-auto-merge-after-approval.json` pins that bullet and the watch's merge rule. Its residual (4) says no presence pin can find a new merge path; that needs a structural check.
- The standard-delivery local review gate (ADR-0037, ADR-0042) is in `plugin/workflow-src/standard-delivery/gates.js` and `review.js`. `configuredGateIds` requires local review only when the launch's `local_review` is true and no review returned `skipped` (SD-31, SD-86). A skipped review still opens a ready pull request, with a warning line (SD-86). A loop cap opens a draft whose local review did not hold (SD-83). The run's result names the pull request and its `head_ref_oid` (SD-47). The run state knows whether the gate held; nothing writes that outside the run today.
- `pr-feedback-remediation` runs validation as its one gate and no local review (`plugin/workflow-src/pr-feedback-remediation/tail.js` `gateIds()`, contract row PFR-23).
- Both workflows push through `open-plan-pr`, which pushes through `plugin/skills/push-branch/scripts/push-branch.sh` (ADR-0037, Workflow outline step 8 and decision 5; ADR-0040 decision 2). That script makes a plain fast-forward push to an explicit refspec. Only in upstream mode, on a non-fast-forward rejection, does it retry once with `--force-with-lease`, whose expected value is the remote-tracking ref. Its header records the decision: capturing the expected object id early was rejected. No push today names an expected remote head taken from the run.
- `tools/validate.sh` registers each behavioural suite in four places: a `SUITE_*` constant, the `ALL_SUITES` and `KNOWN_SUITES` lists, a path-to-suite rule in `map_path`, and a probe path in the `self_test` map. `test_merge_approved.sh` is registered in all four. `map_path` routes `pr-change-detect-poll.sh` to four suites: `test_change_detect_poll.sh` by its own rule, `test_shared_libs.sh` by the rule for every review-loop script, `test_script_bootstrap.sh` by the rule for every `plugin/**/*.sh`, and the policy suite by the rule for every `plugin/` file. `.github/**` routes to the full suite.
- `tools/test_script_bootstrap.sh` checks ADR-0020's fail-closed bootstrap forms (amendment 2026-09-29). Its closure check fails until each new self-locating `plugin/**/*.sh` is enrolled in its bootstrap table.
- No Lair script exists on trunk. Nothing under `plugin/` reads a merge setting from a settings file; every reader takes it from the environment.

## Components

### Merge-lane step of the tick

Built by #605, called by #608's tick under the single-instance lock. #605 fixes the Lair's script directory, `plugin/skills/lair/scripts/`, and #608 builds the tick there.

Each tick the step works the lane set (Lair pull request, under Contracts and seams) in the lane order: by pull request number, starting after the pull request whose merge call ran last, so that one moves to the end. The cache keeps that pull request; with none kept, the order starts at the lowest number. #608's tick handles run ends (Result recording) before it calls the step. For each pull request in the lane set, the step runs these checks in order and stops at the first that routes:

1. **Markers.** The step reads every page of the claimed issue's comments and keeps the markers that pass #632's rule. A failed or incomplete read means nothing more for this pull request this tick. For a pull request whose claim has a terminal outcome, the step stops here.
2. **State.** The step reads the claimed issue (state and labels), then the pull request (state, draft flag, head, labels, merge-queue state and the head's check rollup), in that order, so that a merge which closes the issue is seen as a merge. It routes in this order: merged goes to the merged exit; closed goes to the closed-unmerged exit; an issue that is closed, or that no longer carries `lair:claimed`, goes to the claim-withdrawn exit (Lifecycle).
3. **Held by review.** A review marker exists for this pull request under this claim, or step 2's read shows `lair:review` on the issue or on the pull request. The step skips it. The Lair never merges a pull request with a review marker again. The label only adds a hold: removing it never releases a pull request that has a review marker.
4. **Fix-up in flight.** A fix-up run on this pull request has a start marker and no end marker. The step skips it, because the run will move the head. The run's budget, stall and crash handling are under Fix-up runs.
5. **Draft.** The pull request is a draft. The step routes it to the draft exit.
6. **Pinned head.** The pinned head (Contracts and seams) must equal GitHub's head on step 2's read. Otherwise the pull request goes to batch review with reason `unrecorded-head`. This step compares only the head.
7. **CI red.** The check rollup on step 2's read, which step 6 tied to the pinned head, is `FAILURE` or `ERROR`. The step applies the CI-red rule (Fix-up runs). It reads no merge setting, and neither the approval nor the gate order plays a part. When the rule routes the pull request or starts a fix-up run, the step stops; when it waits, the step runs step 9 and then stops for this pull request.
8. **Merge queue.** Step 2's read shows the pull request in GitHub's merge queue. No merge call runs for it. The step runs step 9 and then stops for this pull request. Step 14 reads the queue state again.
9. **Review wait.** When 3600 seconds have passed since the `ended_at` of the run that recorded the pinned head, the pull request goes to batch review with reason `review-wait-elapsed`.
10. **Auto tier.** The step resolves the trunk commit and fetches it and the pinned head (Git and tool reads), then runs the auto-tier script on them. Only exactly one `TIER=auto` line with exit 0 goes on to the late group. Exactly one `TIER=review:<code>[,<code>...]` line with exit 0, each code one of the five under Auto-tier script, sends the pull request to batch review with those codes. Any other output or exit status, a killed script or a failed fetch is `TIER_ERROR`: no merge this tick.

When either read of step 2 fails or is incomplete, the step runs only steps 3, 4 and 9, on the markers and the clock alone, and then stops. Any other failed or incomplete read, in steps 2 to 10 or in the late group, means no merge and no label change for this pull request this tick. The queue report names each failed read. A read that GitHub answers as not found or moved is named as needing the user (Failure modes, Issue not found).

Steps 11 to 16 are the late group. They are the last tick work before the merge call, in this order, and nothing but step 17 follows them:

11. **Merge settings.** The step reads the two user settings files (Merge settings source). A file that does not parse, or a value of the wrong type, means no merge this tick.
12. **Credential login.** The step runs `gh api user` in the merge environment (Merge environment). A login other than the Lair's own, or a failed read, means no merge this tick; the queue report names `credential-mismatch` or the failed read. No label changes.
13. **Trunk tip.** The step resolves the trunk commit again. When it differs from step 10's, the step fetches the new commit and runs the auto tier again on it, routed as step 10 routes.
14. **Identity.** The step reads the pull request once more and reruns the Lair pull request checks (Contracts and seams) on that read, every check other than the head: same repository, not a fork, trunk base, the Lair's own login as author, and the recorded branch. A base retargeted away from the trunk, or any other mismatch, sends the pull request to batch review with reason `identity-changed`. On the same read, a pull request in GitHub's merge queue, or one that carries `lair:review`, means no merge call this tick.
15. **Issue.** The step reads the claimed issue once: its state, labels, title and body. An issue that is closed, that no longer carries `lair:claimed`, or that carries `lair:review`, means no merge call this tick; the next tick's step 2 routes the pull request, a merge first. Otherwise the step recomputes `body_sha256` of the title and body and compares it with the claim marker's. A difference sends the pull request to batch review with reason `issue-edited` (Q8). The check runs before every merge attempt.
16. **Settle check.** See below. Not settled means no merge this tick.
17. **Merge.** The step runs `merge-approved.sh` with six arguments in the merge environment and routes its one line by the routing table under Contracts and seams.

The tick makes at most one merge call per tick. Once step 17 has run for one pull request, whatever its line, the step skips steps 11 to 17 for every other pull request that tick; steps 1 to 10 still run for them. The lane order puts that pull request last on the next tick, so a pull request that waits at the merge call on every tick never starves the others.

Every child process of the step except `merge-approved.sh` runs under a timeout of 300 seconds: `git`, `gh`, the auto-tier script and the poll script. A killed process counts as a failed read, and a killed auto-tier script as `TIER_ERROR`. `merge-approved.sh` runs with no timeout, as its header requires: it bounds each of its own reads, and its merge call is never cut off. A merge call that hangs holds the tick until it returns. When a merge call ran but its line was lost or was a `MERGE_ERROR=` line, the next tick's state read and merge-queue read show whether it merged or queued.

A check whose input can change after the tick reads it belongs in the late group. Steps 2, 3, 5 and 8 read the pull request's state, draft flag, labels and merge-queue state and the issue's state and labels only to route exits or to skip: `merge-approved.sh` judges the pull request's state and draft flag again on its own read, step 14 reads the pull request's labels and merge-queue state again, and step 15 reads the issue's state, `lair:claimed` and `lair:review` again. Step 7's rollup read can only start the CI-red rule, never a merge.

**Known limit: the merge gap.** Decided by the run under `plugin/governance/decision-autonomy.md` (Review Calls), on a local-review finding, 2026-11-21. The merge call pins one input, the head. Every merge condition is exactly one of five kinds, each with its control:

- **Pinned.** The head: every merge call carries `--match-head-commit` with the pinned head (ADR-0044 decision 19).
- **Derived from git objects.** The auto tier: it reads only commits, which do not change, at the pinned head and the trunk commit the late group resolved.
- **Judged by `merge-approved.sh` on its own read.** State, draft, approval, threads, checks and conflicts. The gap between that read and the merge call is ADR-0044 decision 15.
- **Read by the tick in the late group.** The merge settings; the credential login; the trunk tip; the Lair pull request checks, the base included; the pull request's merge-queue state and `lair:review` label; the issue's state, its `lair:claimed` and `lair:review` labels and its text; the settle snapshot.
- **Lair-owned state.** The markers, which count only under #632's rule, and the settle cache and the Lair's git repository, which only the Lair writes (an assumption about #630), under the single-instance lock.

The late-group kind can change in the seconds between its read and the merge call. No check closes that. GitHub offers no merge call that pins those inputs. Moving a check into `merge-approved.sh`, as expected base, author or branch arguments, a settle digest or the issue hash, only narrows the window and adds script surface, and the issue and the settle snapshot stay outside what the merge call pins. A finding that names a late-group input changing in that gap contests this decision and is a repeat. A finding that shows a merge condition fitting no kind, or a tick read placed after the late group, is new.

Under parallel strains (#612) the step runs the same way for each pull request, with at most one merge call per tick.

### Settle check

Built by #605. It equals ADR-0044 decision 1 (decision 18, Q2). It uses `pr-change-detect-poll.sh` unchanged, in the merge environment, under the child timeout. A result counts only when the output is exactly one line of the form named below and the exit status is 0; anything else is treated as the error case of its mode.

- When the cache has no entry for this pull request and pinned head, the step takes a snapshot with `--snapshot re-arm`. It saves the seed with the pinned head and `quiet_since` set to now only from exactly one `BASELINE=` line with a non-empty value and exit 0. `SNAPSHOT_ERROR`, any other output, a non-zero exit or a timeout saves nothing. Either way the check is not settled this tick. The arm kind is `re-arm` so that an approval already present does not fire `REVIEWER_APPROVED` on every tick.
- Otherwise it runs `--check` against the saved seed:
  - `UNCHANGED` with now minus `quiet_since` at least 600 seconds: settled.
  - `UNCHANGED` with fewer: not settled.
  - `CHANGED`, `CI_FAILED` or `REVIEWER_APPROVED`: the step first deletes the cache entry, then takes a new snapshot as for a missing entry. A failed snapshot leaves no entry, so the next tick starts a new quiet period and no older seed is used. Not settled. `CI_FAILED` starts nothing else: the CI-red rule reads the rollup at step 7.
  - `STATE=MERGED` or `STATE=CLOSED`: not settled; the next tick's state read routes the pull request.
  - `CHECK_ERROR`, any other output, more than one line, a non-zero exit or a timeout: not settled, and the cache entry is kept.
- The window and interval arguments are `3600` and `60`. The one-shot modes validate them and use neither. The reviewer filter is `automated`.

The approval and thread parts of decision 1 are not judged here. `merge-approved.sh` judges them on its own read through `has_settled_evidence` and `is_settled_thread`, with a read past its page failing closed. A lost or unreadable seed only delays a merge: the next tick takes a new snapshot, and the quiet period starts again.

### Auto-tier script

Built by #605 as one script, `plugin/skills/lair/scripts/auto-tier.sh`. It has no model in it and reads only git objects in the git directory the tick passes, and the tick's arguments: that directory, the trunk commit, the pinned head, the local-review head and the fix-up heads. It runs every git call with the settings under Git and tool reads. It and the merge-lane step use ADR-0020's fail-closed bootstrap forms (amendment 2026-09-29). The ADR-0044 gates are left to `merge-approved.sh`. Its conditions (Q5, Q6):

- **Protected paths.** The changed paths are `git diff --name-only --no-renames -z` from the merge base to the pinned head, so a rename lists both sides. The protected-path list is read from the trunk commit, never from the pull request head. It is `.github/lair.json`, key `protected_paths`. An entry has one of three forms, and there are no globs:
  - an exact path;
  - a directory prefix ending in `/`, which matches every path under it and also the exact path without the `/`;
  - a file name written `**/<name>`, which matches that name at any depth. It is the only form that holds `*`.
- **The floor.** A fixed floor in the script applies whatever the list says, and no list entry removes it: the `.github/` directory at the root, and the exact path `.github`; any path with a segment named `.claude`; any file named `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.gitmodules` or `.gitattributes`, at any depth; and any path that holds a byte other than printable ASCII, or a segment that ends in `.` or a space. The list file itself sits under the floor. Every comparison, for the floor and the list, ignores ASCII case.
- **Bump.** The version files are named in the same trunk file, key `version_files`. The script reads each value at the merge base and at the pinned head as `MAJOR.MINOR.PATCH`. A rise in `MAJOR` is a major bump. A file or value that is missing, unparseable or lower at the head is unreadable.
- **Release-train mode.** Under #606's release-train mode a pull request adds a change fragment and changes no version file, so the version-file diff cannot show its bump. In that mode, unless a bump input exists that the pull request cannot change, the script fails closed with `version-unreadable`, and every pull request goes to batch review. #606, which builds the mode, makes the script detect it, and enables the auto tier in it only by supplying such an input. Q5's input is unchanged.
- **Local review.** The tick passes the claim's recorded local-review head and the heads the Lair's fix-up runs recorded since that claim. The condition holds when the pinned head equals the local-review head, or the local-review head is not null and the pinned head is a fix-up head.

`.github/lair.json` has a strict schema. It is a JSON object with exactly two keys, both required arrays:

- `protected_paths`: each entry a non-empty string in one of the three forms, with no leading `/`, no empty, `.` or `..` segment other than a prefix's trailing `/`, and no `*` outside the `**/` form.
- `version_files`: each entry an object with exactly two keys, `path`, an exact path in the same form, and `key`, a non-empty string naming a top-level key of that file.

A missing or unparseable file, or a top-level value that is not such an object, gives `protected-list-unreadable` and `version-unreadable`. A `protected_paths` value that is missing, not an array, or holds any malformed entry gives `protected-list-unreadable`. The same for `version_files` gives `version-unreadable`. An empty array, `[]`, is the only way to declare no entries. So no pull request merges until a well-formed file exists.

**This repository's list.** #605's pull request adds this repository's `.github/lair.json`. Its `protected_paths` is derived from what decides a merge: every file the merge, poll, auto-tier and tick scripts run or source, plus the producers of the local-review evidence. So it must hold at least these ten entries:

- `plugin/skills/lair/`, the Lair's scripts;
- `plugin/skills/github-review-loop/scripts/`, the merge and poll scripts and `reviewer-identity.jq`;
- `plugin/skills/_shared/`, the libraries those scripts source;
- `plugin/hooks/`;
- `plugin/.claude-plugin/`, the plugin manifest;
- `.claude-plugin/`, the marketplace manifest, whose `source` names the plugin root;
- `plugin/workflow-src/` and `plugin/workflows/`, the standard-delivery gate sources and the generated workflow scripts that run the local-review gate;
- `tools/`, the validators;
- `tests/policy/`, the policy pins.

When #630's result script, which writes `local_review_head`, lies outside these, #604 adds its path. Because `plugin/.claude-plugin/plugin.json` holds the version, every pull request that bumps it goes to batch review here. A test checks that the committed list holds the ten entries.

The script prints one line:

- `TIER=auto`, exit 0;
- `TIER=review:<code>[,<code>...]`, exit 0, with every failing code, in this order: `protected-list-unreadable`, `protected-path`, `version-unreadable`, `major-bump`, `local-review-missing`;
- `TIER_ERROR=<reason>`, exit 1, for bad arguments, an unusable git directory, a commit that is not present, or no merge base.

### Fix-up runs

A fix-up run is an unattended `pr-feedback-remediation` run on the pull request (ADR-0040 decision 2, ADR-0045 decision 13). What starts a fix-up run on review findings is #610's rule (ADR-0045 decision 13, the PRD's Post-PR feedback criterion). This design sets preconditions on that trigger only where a binding source allows, and fixes what the merge lane needs from every fix-up run (Q9, Q10):

- **Start preconditions.** A fix-up run starts, from either trigger, only when all of these hold:
  - the pull request is a Lair pull request, so its claim is live (Q7);
  - no fix-up run on it is in flight (the PRD's Post-PR feedback criterion: exactly one remediation run);
  - the issue's wall-clock budget has time left (the PRD's Budgets and recovery criterion, ADR-0045 decision 17);
  - neither the halt file nor the circuit breaker holds (Q10).

  A review marker does not stop a fix-up run (ADR-0045 decision 13). With no budget left, no run starts and the pull request goes to batch review with reason `budget-exhausted`, a tick route and not a run outcome. Under the halt or the breaker the pull request waits, and runs already started finish. The run starts at the pinned head, whatever GitHub's head is. When the branch has moved past the pinned head, the run's first leased push fails (Assumptions about #630), so it records no head and ends at `fixup-failed`.
- **Markers.** Each run has a start marker and an end marker on the claimed issue, with the fields under Contracts and seams. The Lair writes the start marker before it launches the run, and launches nothing when that write reports a failure; the trigger is tried again next tick. A start marker that landed although its write reported a failure ends `not-launched` (below).
- **Budget, stall and crash.** The wall-clock budget is per issue, #608's value, measured from the claim marker's `claimed_at`, so a fix-up run runs on what is left of it. A run still going when the budget passes ends with outcome `timed-out`. The stall window, #608's value, is measured from the start marker's `started_at`; a run past it ends with outcome `stalled`. A tick or the start-up sweep can find a start marker with no end marker, no live session and no unprocessed result (Result recording). It then writes the end marker with outcome `crashed` when the run's worktree exists, and `not-launched` when it does not. The worktree is the launch evidence: the launch creates it first, after the start marker, and the Lair removes it only after the run's end marker is written. A `not-launched` end writes no label, does not end the claim and leaves the breaker unchanged; the trigger can start a new run on a later tick, within the issue's budget.
- The run-end handling is under Lifecycle.

**The CI-red rule.** It fires from the first of two signals: step 7's rollup read on the pinned head, or `MERGE=wait:checks-failed`. The settle check's `CI_FAILED` only means not settled. The rule does not depend on the merge settings, the approval or the gate order. A held pull request never reaches step 7, so the rule does not fire for it. When it fires, the first of these that applies routes the pull request:

1. A `fixup-checks` start marker is already recorded for this pull request under this claim, other than one whose run ended `not-launched`: batch review with reason `checks-failed`.
2. The issue's budget has no time left: batch review with reason `budget-exhausted`.
3. Every other start precondition holds: one fix-up run for failed checks starts.
4. Otherwise the pull request waits, and the review wait (step 9) bounds the wait.

Q9's rule is unchanged: one fix-up run for failed checks, then batch review.

**Recorded residual: fix-ups during batch review.** A pull request with a review marker can still get fix-up runs on review findings, by #610's trigger (ADR-0045 decision 13, the PRD's Post-PR feedback criterion), so a fix-up run can push while the user reviews it. The Lair still never merges it, because the review marker is final. Stopping those runs would depart from ADR-0045 decision 13, so the residual is recorded, not fixed.

**Seam note for #610.** The merge lane does not bound fix-up runs on review findings. Each fix-up run records a new head, and the review wait restarts from its `ended_at`. A reviewer that raises a new finding after every run keeps the pull request cycling until the issue's budget runs out. Bounding it further is #610's, in its trigger, not a merge-lane rule.

## State and ownership

GitHub stays authoritative (ADR-0045 decision 2). This table adds the merge lane's state to solution-design.md's table:

| State | Writer | Readers | Authoritative |
| --- | --- | --- | --- |
| Run-end marker on the claimed issue | Lair, after checking the result against GitHub | Lair, user | yes |
| Fix-up start and end markers on the claimed issue | Lair | Lair, user | yes |
| Review marker on the claimed issue | Lair | Lair, user | yes; the `lair:review` labels only show it |
| Exit marker on the claimed issue | Lair | Lair, user | yes |
| `lair:review` label on the issue and the pull request | Lair, user | user; admission (PRD Admission); the merge-lane step, as a hold | no; the review marker is. The label only adds a hold |
| Merge-queue state of the pull request | GitHub | Lair, in step 2 and the late group | yes |
| Protected-path list and version files, `.github/lair.json` at the trunk commit | user, through a reviewed pull request | auto-tier script | yes, at that commit |
| Merge settings in `.claude/settings.local.json` and `~/.claude/settings.json` | user | Lair, each tick | no; a control input |
| Settle cache: seed, pinned head and `quiet_since`, per pull request | Lair | Lair | no; losing it only delays a merge |
| Run result file in the run's worktree, kept with the worktree until the run's run-end or fix-up end marker is written | the run, through #630's result script | Lair | no; the end marker is |
| Lane order: the pull request whose merge call ran last | Lair | Lair | no; losing it starts the order at the lowest number |
| Lane-holder set: every pull request a run-end marker names, until merged | Lair (#608) | admission | no; rebuilt from the markers, and admission claims nothing until it is |
| Lair git repository: a bare repository in the Lair's cache directory | Lair | auto-tier script | no; checked each tick and rebuilt by fetching |

The pinned head, the local-review proof and the CI fix-up count are all recomputed from markers each tick, never kept only in the cache.

## Contracts and seams

Fields and seams only. Each slice builds the code.

### Lair pull request

The Lair records a pull request in the run-end marker of the claimed issue (Q7). It records one only from a `complete` delivery result, and only after these hold on a fresh GitHub read:

- the result's `pr` exists in the same repository, not a fork;
- its base is the trunk;
- its author is the Lair's own login;
- its head branch equals the result's `branch`;
- its head commit equals the result's `head`. When GitHub's head is a strict ancestor of the result's head, tested in the Lair's git repository after fetching both (Git and tool reads), GitHub has not yet caught up with the run's last push. That counts as a read not yet complete, not as a failed check.

A check that reads GitHub and fails makes the result invalid (Lifecycle). These checks are one function, called by the step that records a result and again by the merge-lane step's late group (step 14), which leaves out the head because the merge call pins it, so there is no second list.

**Result recording.** A run's result file stays in the run's worktree. The Lair removes neither the file nor the worktree until the run's run-end or fix-up end marker is written (#608), so the file is the one copy the Lair needs, and a Lair restart loses nothing. A result file with no end marker yet is an unprocessed result. A read during the result checks that fails or is incomplete, a stale GitHub head included, leaves the result unprocessed, and a later tick checks it again. A result still unchecked when the issue's wall-clock budget passes ends the run with outcome `timed-out`. Only a check that reads and fails makes a result invalid. No run with an unprocessed result is ended as crashed, by a tick or by the start-up sweep. The start-up sweep first processes every unprocessed result as a tick does, so the claims it marks failed under ADR-0045 decision 17 are those with no run end; a result whose checks cannot be read yet is left to a later tick, within the issue's budget.

A recorded pull request is a Lair pull request while all of these hold: its claim has no terminal outcome, the claimed issue is open, and the issue carries `lair:claimed`. A claim's terminal outcome is a run-end marker whose outcome is not `complete`, a fix-up end marker whose outcome is `parked`, `crashed`, `stalled` or `timed-out`, or an exit marker. The Lair merges only a Lair pull request. It never merges or labels a pull request it did not record, and it holds the lane for one only as the lane-holder set says.

The lane set, which the merge-lane step works each tick, is every pull request recorded under a claim with no terminal outcome, open or not.

The lane-holder set is every pull request that a run-end marker names, under any claim, whether the Lair recorded it or only the run's result named it, until GitHub shows it merged. #608 keeps it in the Lair cache, adds each pull request a marker names when it writes that marker, and rebuilds the set from GitHub markers when the cache is lost. A fix-up run works only on a pull request a run-end marker recorded, so it adds none. A closed one stays in the set, so a reopened one holds the lane again. Each tick, before admission, the tick reads the state and draft flag of each pull request in it. A merged one leaves the set.

A pull request in the lane-holder set that is open and not a draft holds the lane until it is merged or closed, whether or not it is a Lair pull request (ADR-0045 decision 12). A failed or incomplete read of any pull request in the set, or a set not yet rebuilt, means no claim this tick: admission fails closed. The queue report names each pull request that holds the lane.

**Recorded residual: a pull request no result names.** A delivery run can open a pull request and then crash, stall or time out before a result names it. No marker names that pull request, so it does not hold the lane, and admission can claim the next issue while it is open. The Lair never merges or labels it, because it is unrecorded. The user's remedy is to merge or close it.

### Pinned head

The pinned head is the last `head` a Lair run recorded for the pull request: the delivery run's, in its run-end marker, or the latest fix-up run's, in its end marker, by `ended_at`, since the claim. A fix-up run's head is recorded only when the previous recorded head is its ancestor. The tick passes the pinned head as `merge-approved.sh`'s sixth argument. The auto tier, the settle cache key and the merge all use that one commit.

### Expected-head argument

Decision 19 (Q3). `merge-approved.sh` takes an optional sixth argument, `EXPECTED_HEAD`:

- It must be 40 or 64 lowercase hex characters, else `MERGE_ERROR=bad-expected-head`, checked with the other arguments before any `gh` call. Seven or more arguments stay `MERGE_ERROR=bad-arguments`.
- Right after the first read, before gate 1, a head that differs prints `MERGE=wait:head-moved` and makes no merge call. The check goes first so that a moved head never yields a gate line, such as `wait:checks-failed`, about a commit no Lair run recorded.
- The gated head is the expected head, so every merge call, `--admin` included, carries `--match-head-commit` with it. The refused-merge re-read compares against it as it does today.
- With five arguments nothing changes.

### Merge settings source

Decision 17 (Q4). Each tick the step reads the `env` object of exactly two files:

1. `.claude/settings.local.json` at the root of the Lair's checkout, which is the main checkout;
2. `~/.claude/settings.json`.

For each of `HIVEMIND_AUTO_MERGE`, `HIVEMIND_AUTO_MERGE_ADMIN` and `HIVEMIND_PR_REVIEWERS`, a key present in file 1, even empty, wins; otherwise file 2's value is used; otherwise the key is unset.

- An absent file counts as empty.
- A file that does not parse as JSON, an `env` that is not an object, or one of the three values that is not a string, `null` included, means no merge this tick. The queue report names the file.
- The tick reads no other settings source. The committed `.claude/settings.json`, `CLAUDE_CONFIG_DIR`, managed settings and every other settings file never reach it, and the merge keys are never taken from the Lair's own environment. The queue report names the files read and whether each was present.

### Merge environment

The step runs the merge script, the poll script and the `gh api user` call in the Lair's own environment, minus every `HIVEMIND_*` key, plus each of the three keys above that the settings files set. So the `gh` authentication the Lair runs under reaches `gh` unchanged, whether it comes from `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `GH_HOST`, `GH_CONFIG_DIR`, `XDG_CONFIG_HOME` or the D-Bus session variables the keyring needs, and no merge key comes from the environment (Q4). `PATH` is the tick's fixed `PATH` (Git and tool reads).

The environment alone does not prove the account. Step 12 checks, in this same environment, that `gh api user` reports the Lair's own login, read once when the Lair starts (#608), before every merge call. The merge script gets that login as its fifth argument.

### Git and tool reads

- When the Lair starts, #608 resolves `bash`, `git`, `gh`, `jq` and `timeout` to absolute paths, and the tick calls them by those paths. The tick's `PATH`, and its children's, is the directories of those paths, in that order with repeats dropped, followed by `/usr/bin:/bin`. At start, under that `PATH`, `command -v` of each of the five must print its resolved path; otherwise the Lair refuses to start. Every other tool the scripts call resolves through that `PATH`.
- The tick's git reads run in a bare repository the Lair owns in its cache directory, never in the main checkout's git directory, so no config, hook or ref of the main checkout is read. The Lair creates it with a config the Lair writes. Each tick, before any git read, the tick checks that the repository's config is exactly what the Lair wrote and that it has no `refs/replace/` ref, no `info/grafts` file and no `objects/info/alternates` file. On any difference, or when the repository is lost, the tick deletes it and creates it again by fetching.
- At start, the Lair also refuses to start when `$HOME/.jq` exists, which `jq` would load into every filter, or when `gh config get http_unix_socket`, globally or for the repository's host, prints a value, which would send every `gh` call through that socket. Both are start checks only; a later write is the residual "A strain that writes the tick's inputs" (Trust boundaries).
- Every git call, the auto-tier script's included, runs with every `GIT_*` variable of the Lair's environment removed, then sets `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_NO_REPLACE_OBJECTS=1`, names the git directory explicitly, and passes `-c core.hooksPath=/dev/null` and `-c diff.ignoreSubmodules=none`. It fetches from the repository's URL fixed at Lair start, never a named remote. Its credentials come only from `gh auth git-credential`, named by absolute path on the command line.
- The trunk commit is the id that `git ls-remote` returns for the trunk branch from that URL in this tick. The tick fetches that id and the pull request's `refs/pull/<n>/head`, then checks that both the trunk commit and the pinned head are present. No local ref, `FETCH_HEAD` included, names either commit.

### Routing table

Decision 20. The tick routes the script's output as follows. The skill's routing in `SKILL.md` stays bound to the watch. Batch review means the `lair:review` label on the issue and on the pull request, then a review marker with the reason code (Write order).

| Output | Route |
| --- | --- |
| `MERGE=off` | No merge. The pull request stays open and holds the lane. |
| `MERGE=skipped:bad-setting` | No merge. The queue report names the setting. Handled like `off`. |
| `MERGE=skipped:not-open` | No change. The next tick's state read routes the pull request. |
| `MERGE=skipped:draft` | The draft exit. |
| `MERGE=skipped:no-approval` | Wait; the review wait bounds it. |
| `MERGE=skipped:open-threads` | Wait; #610's trigger may start a fix-up run. |
| `MERGE=skipped:no-checks` | Batch review, reason `no-checks` (ADR-0044 decision 6). |
| `MERGE=wait:checks-pending` | Wait. |
| `MERGE=wait:checks-failed` | The CI-red rule, which step 7 also applies. |
| `MERGE=merged` | The merged exit. |
| `MERGE=merged-admin` | The merged exit; the digest notes the `--admin` merge. |
| `MERGE=wait:head-moved` | No merge. The next tick's pinned-head check routes the pull request. |
| `MERGE=skipped:conflicts` | Batch review, reason `conflicts`. |
| `MERGE=skipped:blocked` | Batch review, reason `merge-blocked`. |
| `MERGE=skipped:refused` | Batch review, reason `merge-refused`. |
| `MERGE=wait:merge-pending` | No merge. While GitHub's merge queue holds the pull request, step 8 and step 14 make no merge call for it. The next tick's state read routes it once merged, and the review wait bounds it. |
| `MERGE_ERROR=<reason>` with exit 1 | No change. Retried next tick; the queue report names the reason; the review wait bounds it. When a merge call ran before the error, the next tick's state read and merge-queue read show whether it merged or queued. |
| A non-zero exit with any other output | Treated as `MERGE_ERROR`. |
| No line, more than one line, or a line not in this table | Treated as `MERGE_ERROR`. |

### Write order

A route that makes more than one write makes its label changes and pull request changes first, then its markers, and the marker that ends the route last: the run-end, fix-up end or exit marker, or for a batch review the review marker. Every write is idempotent: adding a label already present, removing one already absent, or converting a draft to a draft changes nothing. A route first looks for each of its markers under this claim and never writes a second one; a route that would write a review marker writes none when the pull request already has one under this claim. A failed write leaves the rest for the next tick.

A route whose last marker is missing is not finished, and no record of it is kept. A later tick computes the route again from the same inputs and repeats its writes:

- a run end, from the result file, which stays until its end marker is written, or from the session, the worktree and the clock;
- an exit, from GitHub's state of the pull request and the issue. When that state has changed, the route it now gives runs instead: a closed pull request reopened after its issue lost `lair:claimed` goes to the claim-withdrawn exit and is never merged;
- a batch review stopped before its review marker leaves the `lair:review` label, which already holds the pull request (step 3), so no merge follows. The user releases a label-only hold by removing the label.

### Markers the merge lane writes

Each marker is a machine-readable comment on the claimed issue, under #632's author and nonce rule (Assumptions about #632). From #632's claim marker the merge lane reads `claim_nonce`, `claimed_at` and `body_sha256`, and it writes nothing to it.

- **Run-end marker.** Written when a delivery run ends: `claim_nonce`, `outcome` (`complete`, `parked`, `blocked`, `failed`, `no-pr`, `invalid-result`, `crashed`, `stalled` or `timed-out`) and `ended_at`. When the result names a pull request and passes the schema check, it holds `pr`, which puts the pull request in the lane-holder set. Only for a `complete` result that passed the Lair pull request checks does it also hold `branch`, `head` and `local_review_head`, and only such a marker records the pull request. A parked run's draft is named, not recorded; it belongs to the park (#609, ADR-0045 decision 12). #608's start-up sweep and #611's breaker read `outcome` here.
- **Fix-up start marker.** `kind` (`fixup-checks` or `fixup-review`), `run_nonce`, `claim_nonce`, `pr`, `start_head`, `started_at`.
- **Fix-up end marker.** `run_nonce`, `claim_nonce`, `outcome` (`complete`, `parked`, `blocked`, `failed`, `crashed`, `stalled`, `timed-out`, `invalid-result` or `not-launched`), `ended_at`, and `head` when recorded, or the park record when parked.
- **Review marker.** `claim_nonce`, `pr`, `head`, `reasons` (codes only, no issue or pull request text), `at`.
- **Exit marker.** `claim_nonce`, `pr`, `exit` (`merged`, `pr-closed` or `claim-withdrawn`), `at`.

### Assumptions about #630

- **A strain writes nothing outside its worktree and the shared object and ref store.** No strain process writes any file outside its own worktree, except objects and refs in the main checkout's git common directory, which a worktree strain made by `git worktree add` and launched in tmux (ADR-0017 decisions 1 and 2) must write. So no strain writes what the tick reads or runs, among them: the two user settings files; the Lair's cache directory, with its git repository, settle cache and lane-holder set; another run's worktree and result file; the main checkout's git config and hooks; the directories on the tick's `PATH`; the plugin's script directory; `gh`'s config directory; and `$HOME/.jq`. How #630 keeps a strain to this, a carve-out or a per-strain clone, is #630's. Where this does not hold, the residual "A strain that writes the tick's inputs" applies (Trust boundaries).
- **No merge key takes effect in a strain.** ADR-0045 decision 4 has the strain settings carry no `HIVEMIND_AUTO_MERGE*` key. Since Claude Code 2.1.211 a worktree session also reads the main checkout's `.claude/settings.local.json` (ADR-0010, amendment 2026-10-31), and an omitted key overrides nothing inherited (A3-1). How #630 keeps a strain from inheriting the keys, for example with empty-string keys, and any ADR-0045 or PRD change that needs, are #630's.
- **Leased pushes.** Every push of a strain run, a fast-forward included, names the remote head it expects, never taken from a remote-tracking ref: a fix-up run's first push expects its `start_head`, a delivery run's first push expects the branch head the run started from, or no branch, and every later push expects the run's own last push. A push by any other process to the branch then makes the run's next push fail, so no head built on that push passes the result checks and is recorded; a fix-up run then ends without a recorded head, as Run outcome to labels routes it, at `fixup-failed`. This reverses, for strains only, the decision `push-branch.sh` records (Context and code truth): a plain fast-forward push, a lease only on a non-fast-forward retry and only from the remote-tracking ref, and early capture of the expected head rejected. #630 must add a strain-only leased mode to `push-branch.sh` and `open-plan-pr`, used only by strain runs; the interactive push path stays unchanged. Where this does not hold, see The pinned head under Trust boundaries.
- The result schema carries `local_review_head`: a commit, or null when local review was not configured, was skipped, or did not hold. #630's fixed result script writes it from the run's own state, never from a value the model passes. This extends solution-design.md's Contract "Strain result".
- A fix-up run starts on the pull request's branch at the pinned head, pushes to that branch only, and writes the same result schema, with `local_review_head` null.
- A finished strain run holds no live process or credential that can edit its pull request.

### Assumptions about #632

- **Markers.** #632 defines the author and nonce rule that makes a marker comment count. The rule covers every marker kind this design adds. The merge lane reads no marker that fails it.
- **Unforgeable markers.** A process that holds the user's GitHub credentials, the claim nonce and the run nonce cannot produce a marker that passes #632's rule. A strain holds all three. If #632 does not provide this, marker forgery is a named residual (Trust boundaries).
- **Claim marker fields.** The claim marker carries `claim_nonce`, `claimed_at` and `body_sha256`. #632 fixes the `body_sha256` form, including line-ending and null-body handling, as one function. The merge lane's issue-edit check calls that function and has no form of its own.
- **Controls.** #632 fixes the halt file path, the lock and the injection scan. The merge lane reads the halt file through #632's reader and runs only under the lock. It gives no GitHub text to a model, so it adds no injection-scan call.

### Fields the merge lane needs at run end

From each delivery result: `outcome`, `pr`, `branch`, `head`, `local_review_head`. From each fix-up result: `outcome`, `pr`, `branch`, `head`, `park`. The run-end and fix-up end markers carry them once the Lair has checked them.

## Trust boundaries

This section replaces the merge-settings part of solution-design.md's channel list. Merge settings are a channel only through the user's own files on the Lair's machine: `.claude/settings.local.json` at the main checkout and `~/.claude/settings.json`. Unsetting `HIVEMIND_AUTO_MERGE` there stops merges from the next tick (ADR-0045 decision 17), except a merge GitHub's merge queue already holds (Residual: a queued merge).

- **The committed settings.** A pull request, a Lair one included, can change the committed `.claude/settings.json`, so the tick never reads it.
- **The Lair's environment.** None of its `HIVEMIND_*` keys reaches the merge or settle scripts; the merge keys come only from the two files. Its `gh` authentication does reach them, and step 12 checks the login it yields before every merge call. No `GIT_*` variable of it reaches a git call.
- **The strain.** It writes nothing outside its worktree and the shared object and ref store (an assumption about #630). The tick's git reads use a Lair-owned repository it checks each tick, with hooks, system and global config and replace objects off, and a fixed URL; they take the trunk commit id from this tick's `ls-remote`; the tick calls tools by absolute path under a `PATH` checked at start; and the start checks refuse a `$HOME/.jq` and a `gh` `http_unix_socket`. These narrow what a strain could plant; they do not replace the assumption.
- **The auto-tier inputs.** None of them comes from the pull request head:
  - the protected-path list is read at the trunk commit, and the floor is in the script;
  - the bump is computed from version-file values, not from commit messages, plan fields or labels;
  - the local-review proof is a head the Lair recorded from a result that passed its checks.
- **The pinned head.** A head no Lair run recorded never merges a Lair pull request, while two assumptions hold: #632's unforgeable markers, and #630's leased pushes. Without leased pushes, a fix-up run can build on a push by another account and record the result as its head, and ADR-0044's residual "An unreviewed push by another account can merge" then applies through fix-up heads.
- **The recorded identity.** The late group reruns the Lair pull request checks on a fresh read before every merge call. These checks bound which pull request the lane acts on. They do not bound a strain that reports false values about its own run: the strain pushed the head and opened the pull request it reports.
- **Residual: under-declared bump.** The bump check sees the version a pull request declares, not its real compatibility impact. A breaking change shipped with a minor bump passes it. The protected-path list is the control for compatibility surfaces.
- **Residual: a prompt-injected strain holds the user's rights** (ADR-0045 Residuals). Containment is #630's strain settings, not a separate identity. While a strain runs, for the merge lane this means:
  - it can merge its own pull request, or any other, outside the lane and the auto tier;
  - it can push to its branch after its result is recorded; the pinned head then differs, so the lane routes `unrecorded-head` and never merges that push;
  - it can report a false `local_review_head` if it subverts #630's fixed result script, and the auto tier then accepts an unreviewed head;
  - it can add or remove labels, `lair:review` and `lair:claimed` included; an added label only adds a hold, a removed `lair:review` never releases a pull request with a review marker, and a removed `lair:claimed` only stops merges;
  - it can post marker comments, which count only under #632's rule (Residual: marker forgery), and delete the Lair's own marker comments, a review marker included.

  The merge lane bounds none of these. Ground: ADR-0045 accepts this residual. Bounded impact: a merge is reverted (ADR-0045 decision 14).
- **Residual: a strain that writes the tick's inputs.** If #630's write assumption does not hold, a strain can write:
  - the two user settings files, turning merges or `--admin` on or changing the reviewers;
  - the settle cache, where a forged `quiet_since` settles at once;
  - another run's result file, though a forged result still has to pass the result checks against GitHub;
  - the lane-holder set, where a removed entry lets admission claim while that pull request holds the lane;
  - the Lair's git repository, where the per-tick check catches a changed config, a replace ref, grafts and alternates only at the moment it runs;
  - a directory on the tick's `PATH`, where a planted tool runs with the user's rights at the next tick;
  - the plugin's script directory, where a replaced merge, poll or auto-tier script decides the merge;
  - `gh`'s config directory, where an `http_unix_socket` set after start sends every `gh` call, the credential check included, through a socket the strain controls;
  - `$HOME/.jq`, where definitions written after start load into every `jq` filter the scripts run.

  The merge lane bounds none of these beyond its own hardening. Ground: ADR-0045's prompt-injected strain residual. Bounded impact: a merge is reverted (ADR-0045 decision 14).
- **Residual: marker forgery.** If #632's rule does not stop a process that holds the user's credentials and the nonces, a forged run-end or fix-up end marker can pin any head and record any local-review head, a forged exit marker can end a claim, and a forged last marker of a route ends the route before its writes are made. The pinned head and the local-review proof then hold only as far as the forger allows.
- **Residual: the merge gap.** A late-group input can change in the seconds before the merge call (Known limit, Merge-lane step of the tick). The lane trusts repository writers and the user's machine, who can already merge, push or change the settings with no gap to time. The issue's author was admitted on the text as it stood, and an edit inside the gap equals an edit one second after the merge, which no check sees. A strain is not trusted: no strain run on the pull request is in flight when the late group runs, and what a strain can do with the user's rights is the residual above. Ground: outside the recorded threat model. Bounded impact: a merge is reverted (ADR-0045 decision 14).
- **Residual: a queued merge.** Once `merge-approved.sh` has queued a pull request in GitHub's merge queue (`MERGE=wait:merge-pending`), unsetting `HIVEMIND_AUTO_MERGE`, a later review marker, a halt or a claim withdrawal does not take it out of the queue, and it can still merge. The Lair adds no dequeue write. Bounded impact: a merge is reverted (ADR-0045 decision 14).
- **Residual: the Lair acts as the user's own login.** The Lair's own login, passed to `merge-approved.sh` as the self login, is the user's. So `is_settled_thread` counts a thread that ends in the user's own comment as settled, and the user's review comments never block a merge. GitHub lets no author review their own pull request, so the user cannot request changes on a Lair pull request either. The user's working holds are: convert the pull request to a draft; close it; remove `lair:claimed` from the issue; edit the issue's title or body; add `lair:review` to the issue or the pull request; or unset `HIVEMIND_AUTO_MERGE`. Each stops the merge from the next late group, except a merge already queued (Residual: a queued merge). Bounded impact: a merge is reverted (ADR-0045 decision 14).
- **Residual: the interactive watch.** A user who runs the interactive watch on a Lair pull request merges under ADR-0044 unchanged, outside the auto tier.

## Lifecycle

### Run outcome to labels

This table covers each run end the merge lane depends on, and replaces stage 1's merge step. A park from a delivery run stays with #609. Every route follows the Write order. In the Breaker column, "counts" adds one to the consecutive count, "resets" sets it to zero, and "neither" leaves it as it is.

| Run end | Issue | Pull request | Breaker |
| --- | --- | --- | --- |
| Delivery `complete`, result checks pass, PR not a draft | stays `readiness:implementation` and `lair:claimed` | recorded; enters the merge lane and holds it | resets |
| Delivery `complete`, result checks pass, PR a draft | `lair:review` added | recorded; batch review, reason `draft`; does not hold the lane | resets |
| Delivery `complete` with `pr` null | `lair:failed`, outcome `no-pr` | none | neither |
| Delivery `blocked` | `lair:failed`, outcome `blocked` | left as it is, unrecorded; while open and not a draft, a pull request the result names holds the lane (lane-holder set) | neither |
| Delivery `failed` | `lair:failed` | left as it is, unrecorded; while open and not a draft, a pull request the result names holds the lane (lane-holder set) | counts |
| Delivery `crashed`, `stalled` or `timed-out` | `lair:failed`, the outcome in the run-end marker | left as it is, unrecorded; while open and not a draft, a pull request the result names holds the lane (lane-holder set) | counts |
| Delivery invalid result: the schema check fails, or a Lair pull request check reads and fails | `lair:failed`, outcome `invalid-result` | left as it is, unrecorded, never merged; while open and not a draft, a pull request the result names holds the lane (lane-holder set) | neither |
| Delivery `parked` | #609's park | #609's park | neither |
| Fix-up `complete`, result checks pass | unchanged | new recorded head | resets |
| Fix-up `parked`, a `decision` or `fact` park | #609's park: answerable on the issue, `readiness:needs-decision`, `lair:claimed` removed; counts toward the third-park handoff | converted to a draft; the claim ends | neither |
| Fix-up `parked`, an `approval` park or a third park | #609's park: `lair:handoff`; the issue leaves the factory | converted to a draft; the claim ends | neither |
| Fix-up `failed` | `lair:review` added | batch review, reason `fixup-failed` | counts |
| Fix-up `blocked`, or an invalid result | `lair:review` added | batch review, reason `fixup-failed` | neither |
| Fix-up `crashed`, `stalled` or `timed-out` | `lair:failed`; the claim ends | not merged by the Lair; while open and not a draft it holds the lane (lane-holder set) | counts |
| Fix-up `not-launched`: a start marker with no session, no result and no worktree | unchanged | unchanged; the trigger can start a new run | neither |
| Any fix-up end under a claim that already has a terminal outcome | unchanged | unchanged | neither |

The `not-launched` row and the last row write only the fix-up end marker: no label, no review marker, no draft conversion. The fix-up result checks are the Lair pull request checks against the pull request it ran on, plus the ancestor check under Contracts and seams. A fix-up park is a park of the claim under ADR-0045 decision 7, handled by #609 as a delivery run's park is. Its writes are the draft conversion, then #609's park writes, then the fix-up end marker with the park record, last (Write order). The draft conversion makes the pull request belong to its parked issue, so it does not hold the lane (ADR-0045 decision 12), as a parked delivery run's draft does. A re-claim continues on the pushed branch (ADR-0045 decision 11). A fix-up run's `crashed`, `stalled` and `timed-out` ends give `lair:failed`, as a delivery run's do, and as solution-design.md's Stall and Budget overrun rows and the PRD's Budgets and recovery criterion give for any run.

### Exits

- **Merged.** GitHub shows the pull request `MERGED`, seen by the script's confirm read or a later tick's state read. The issue moves to `readiness:done`, and `lair:claimed` and `lair:review` are removed; then the exit marker `merged` is written. The lane is freed.
- **Draft.** A Lair pull request that is a draft goes to batch review with reason `draft`. A draft does not hold the lane (ADR-0045 decision 12). The issue keeps its other labels until the user merges or closes the pull request, which ends at the merged or closed-unmerged exit.
- **Closed unmerged.** GitHub shows the pull request `CLOSED`. The issue gets `lair:handoff`, `lair:claimed` and `lair:review` are removed, and its readiness label is left as it is. Then a review marker with reason `pr-closed` is written, so the Lair never merges the pull request if it is reopened, then the exit marker `pr-closed`. It leaves the factory. The exit does not count toward the breaker. The lane is freed. The pull request stays in the lane-holder set, so a reopened one holds the lane again.
- **Claim withdrawn.** Step 2 sees the issue closed, or without `lair:claimed`, while the pull request is open. `lair:review` goes on the issue and the pull request, then a review marker with reason `issue-closed` or `claim-removed` is written, then the exit marker `claim-withdrawn`. The claim ends, and the Lair never merges the pull request. A non-draft one holds the lane until the user merges or closes it (lane-holder set). The exit does not count toward the breaker. When step 15 sees the withdrawal first, it makes no merge call, and the next tick's step 2 routes it.
- **Batch review.** `lair:review` goes on the issue and on the pull request, then the review marker is written. The issue's label keeps it out of admission (PRD Admission). The Lair never merges that pull request again. A non-draft one still holds the lane (ADR-0045 decision 12) until the user merges it, which ends at the merged exit, or closes it, which ends at the closed-unmerged exit.

### Stage 3: post-PR fix-up

This replaces solution-design.md's stage 3 whole. A trigger starts one fix-up run on the pull request: review findings by #610's rule, or the CI-red rule, when the start preconditions under Fix-up runs hold. The Lair writes the start marker, then launches the run. The run pushes to the same branch and ends with a result, or the Lair finds it crashed, stalled or over budget. The Lair reads the result from the run's worktree, checks it and makes the route's writes, the end marker last, recording the new head or routing as the table above says. On a later tick the merge-lane step evaluates the pull request again from step 1, with a new settle snapshot for the new head.

### Stage 4: halt and circuit breaker

This replaces solution-design.md's stage 4 merge stop (Q10). The halt file and a tripped circuit breaker stop new claims and new fix-up runs. Runs in flight, delivery and fix-up alike, finish, and their results are handled; budget, stall and crash handling still apply. Merges continue. Unsetting `HIVEMIND_AUTO_MERGE` in the user's settings files stops merges from the next tick (ADR-0045 decision 17), except a merge already queued (Residual: a queued merge). Under a halt, a pull request whose checks fail waits. When the review wait elapses it goes to batch review.

The breaker counts only `failed`, `crashed`, `stalled` and `timed-out`, from run-end and fix-up end markers. ADR-0045 decision 17 and the PRD's Stop controls criterion name `failed`, `crashed` and `timed-out`; `stalled` rests on solution-design.md's Stall row, which counts a stall toward the breaker, and replaces the shorter list in its Component "Decision digest and circuit breaker". A `complete` run end under a live claim resets the count. Every other run end and route, `blocked`, `no-pr`, `invalid-result`, `not-launched`, a park, an exit, a review wait, `budget-exhausted` or any fix-up end under an ended claim, neither adds to the count nor resets it.

## Existing-path coverage

- **The watch.** Its five-argument call of `merge-approved.sh`, its routing in `SKILL.md`, its settle period in poll mode and its grant are unchanged. The five-argument test cases in `tools/test_merge_approved.sh` stay as they are. The six-argument case `args:six`, whose sixth argument `extra` is malformed, now expects `MERGE_ERROR=bad-expected-head` (decision 19).
- **The Tier A merge rule.** `plugin/governance/decision-autonomy.md` keeps every merge recommendation with the human, except the review watch's merge. The Lair tick's merge is a second merge path. #605 changes that Tier A bullet to name it under ADR-0044 decision 17 (Changes to shared documents, item 5). #605 also updates `tests/policy/safety-auto-merge-after-approval.json` to pin the new bullet text and the merge-lane step's call of `merge-approved.sh`, and adds a structural check to the policy suite. In every file under `plugin/` other than `merge-approved.sh`, it flags `gh pr merge`, a REST merge path matching `pulls/[^ ]*/merge`, `mergePullRequest`, `enqueuePullRequest`, and `--auto` on a line that also holds `merge`; and only the watch's merge rule and the merge-lane step call `merge-approved.sh`.
- **The poll script.** `pr-change-detect-poll.sh` is not changed. The tick uses its existing `--snapshot` and `--check` modes.
- **`reviewer-identity.jq`.** Not changed. The merge script still calls it for the approval and thread gates.
- **Interactive auto-merge.** Unchanged. With `HIVEMIND_AUTO_MERGE` set in the committed settings, the interactive watch still merges as ADR-0044 states. That setting never reaches the tick.
- **Interactive pushes.** `push-branch.sh` and `open-plan-pr` keep their interactive push path and its recorded lease decision unchanged. The strain-only leased mode is #630's (Assumptions about #630).
- **Standard-delivery and pr-feedback-remediation.** Their gates are unchanged. The local-review head is read from the run's own state by #630's result script; neither workflow gains a gate.
- **Non-Lair pull requests.** The tick never merges or labels them. It reads one only when a run-end marker names it, to hold the lane (lane-holder set).

## Failure modes

These rows replace "Crash", "Merge refused", "CI red" and "Issue edited after claim" in solution-design.md, replace "GitHub API failure or rate limit" for the merge lane, and add the merge lane's own. The other rows there stand.

| Failure | Detection | Resulting state |
| --- | --- | --- |
| Crash | A strain session has exited with no result file. | Delivery: `lair:failed`; the outcome `crashed` goes into the run-end marker. Fix-up: see Fix-up run lost in flight. Counts toward the breaker. |
| Merge refused | `MERGE=skipped:conflicts`, `skipped:blocked` or `skipped:refused`. | Batch review with that reason; the pull request holds the lane until the user acts. |
| CI red | The tick's rollup read on the pinned head shows `FAILURE` or `ERROR`, or the script prints `MERGE=wait:checks-failed`. The settle check's `CI_FAILED` is not a CI-red signal. | With a CI fix-up already recorded under this claim: batch review, reason `checks-failed`. With no budget left: batch review, reason `budget-exhausted`. Otherwise one fix-up run for failed checks when every start precondition holds, else the pull request waits and the review wait bounds it. The merge settings play no part. |
| Issue edited after claim | `body_sha256` of the current title and body differs from the claim marker's, checked by step 15 before every merge attempt. | No merge. Batch review, reason `issue-edited`. The strain kept its captured text. |
| Failed or incomplete tick read | A GitHub read that fails or does not read every page; a failed `ls-remote` or fetch; a read killed by the child timeout. This replaces "GitHub API failure or rate limit" for the merge lane. | No merge and no label change for that pull request this tick. When a read of step 2 fails, only the review wait may route, from the markers. The queue report names the read. The next tick retries. |
| Issue not found | GitHub answers a read of the claimed issue as not found or moved: the issue was deleted or transferred, or the credential lost access to it. | No merge and no label change. From the first such answer, every tick's queue report names the issue and its pull request as needing the user. The pull request's own state read still frees the lane once it is merged or closed (lane-holder set). The user's remedy: merge or close the pull request, or restore the issue or the access. |
| Failed result-check read | A read during the result checks fails or is incomplete, or GitHub's head is a strict ancestor of the result's head. | The result stays unprocessed in the run's worktree, and a later tick checks it again. A result still unchecked when the issue's budget passes ends the run `timed-out`. |
| Failed lane read | A read of a pull request in the lane-holder set fails or is incomplete, or the set is not yet rebuilt. | No claim this tick. |
| Malformed settings file | A user settings file does not parse, or its `env` is not an object, or a merge value is not a string, `null` included. | No merge this tick. The queue report names the file. No label changes. |
| Credential mismatch | `gh api user` in the merge environment reports a login other than the Lair's own, or fails. | No merge this tick. The queue report names `credential-mismatch` or the failed read. No label changes. The review wait bounds it. |
| Shadowed tool at start | Under the tick's fixed `PATH`, `command -v` of `bash`, `git`, `gh`, `jq` or `timeout` differs from its resolved path. | The Lair refuses to start. |
| Unsafe tool config at start | `$HOME/.jq` exists, or `gh config get http_unix_socket` prints a value, globally or for the repository's host. | The Lair refuses to start. |
| Changed git repository | The Lair's bare repository has a config the Lair did not write, a `refs/replace/` ref, `info/grafts` or `objects/info/alternates`. | The tick deletes the repository and creates it again by fetching, before any git read. |
| Merge-script error | `MERGE_ERROR=`, a non-zero exit, no line or an unknown line. `merge-approved.sh` runs under no child timeout. | No change. Retried next tick; when a merge call ran first, the next tick's state read and merge-queue read show whether it merged or queued. The review wait bounds the retries. |
| Unrecorded or moved head | GitHub's head differs from the pinned head, or the script prints `MERGE=wait:head-moved`. | No merge. With no fix-up run in flight: batch review, reason `unrecorded-head`. |
| Changed identity | The late group's fresh pull request read shows a base that is not the trunk, or a repository, author or branch that no longer matches the Lair pull request checks. | No merge. Batch review, reason `identity-changed`. |
| Trunk moved in the late group | Step 13's `ls-remote` returns a different trunk commit than step 10's. | The auto tier runs again on the new commit and routes as step 10. |
| Late-group input changed in the merge gap | None: the change lands between the late group's read and the merge call. | The pull request merges. A revert is the veto (ADR-0045 decision 14). See the Known limit under Merge-lane step of the tick. |
| Invalid result | The schema check fails, or a Lair pull request check or the ancestor check reads and fails. | Delivery: `lair:failed`, outcome `invalid-result`, the pull request unrecorded. Fix-up: batch review, reason `fixup-failed`. Neither counts toward the breaker. |
| Failed fix-up run | The fix-up end marker's outcome is `failed`, `blocked` or `invalid-result`. | Batch review, reason `fixup-failed`. Only `failed` counts toward the breaker. Under an ended claim, see Fix-up end under an ended claim. |
| Fix-up run lost in flight | A start marker with no end marker, no live session and no unprocessed result, whose run's worktree exists, seen by a tick or the start-up sweep; the stall window passed since its `started_at`; or the issue's budget passed since the claim marker's `claimed_at`. | The Lair writes the end marker with outcome `crashed`, `stalled` or `timed-out`. The issue gets `lair:failed` and the claim ends; the pull request is not merged by the Lair and, while open and not a draft, holds the lane. Counts toward the breaker. Under an ended claim, see Fix-up end under an ended claim. |
| No budget for a fix-up run | A trigger would start a fix-up run, and the issue's budget has no time left. | No run starts. Batch review, reason `budget-exhausted`. Not a run outcome: the breaker is unchanged. |
| Fix-up end under an ended claim | A fix-up run ends after its claim reached a terminal outcome. | Only the fix-up end marker is written: no label, no review marker, no breaker change. |
| Parked fix-up run | The fix-up end marker's outcome is `parked`. | The pull request is converted to a draft and the claim ends. #609 handles the park: a `decision` or `fact` park is answerable on the issue; an `approval` park or a third park hands it off. Does not count toward the breaker. |
| Start marker write failed | The write of a fix-up start marker reports a failure. | No run is launched. The trigger is tried again next tick. A marker that landed anyway ends `not-launched`. |
| Fix-up run not launched | A start marker with no end marker, no live session, no unprocessed result and no worktree: a write that landed though it reported a failure, or a Lair stop between the marker and the launch. | The Lair writes the end marker with outcome `not-launched`: no label, the claim stays live, the breaker is unchanged. The trigger can start a new run on a later tick, within the issue's budget; a `not-launched` `fixup-checks` run does not use up the CI fix-up. |
| Interrupted route | A route stopped after some of its writes, before its last marker. | A later tick computes the route again from the same inputs and repeats its idempotent writes; no marker is written twice. A batch review stopped before its review marker is held by its `lair:review` label. |
| Review label without a review marker | `lair:review` on the issue or the pull request, put there by the user or by an interrupted batch review. | No merge while it is there (steps 3, 14 and 15). Removing it releases the pull request only when no review marker exists. |
| Claim withdrawn | The issue is closed, or has lost `lair:claimed`, while the pull request is open. | No merge. The claim-withdrawn exit, routed by step 2. Does not count toward the breaker. |
| Lost settle cache | No seed, or one for another head. | A new `re-arm` snapshot. The quiet period starts again. The merge is delayed by at least 600 seconds, never taken early. |
| Queued merge | Step 2's read or the late group's read shows the pull request in GitHub's merge queue, after `MERGE=wait:merge-pending` or after a merge call whose line was lost or was a `MERGE_ERROR=` line. | No merge call while it is queued. The next tick's state read routes it once merged; the review wait bounds it. See Residual: a queued merge. |
| Failed re-snapshot | `--check` prints a resetting marker, and the new snapshot fails. | The seed was deleted first, so no older seed remains. The next tick starts a new quiet period. |
| Malformed poll output | Not exactly one known line with exit 0. | Not settled. A failed `--snapshot` saves nothing; a failed `--check` keeps the seed. |
| Pull request closed unmerged | GitHub shows `CLOSED`. | Issue `lair:handoff`, then a review marker, reason `pr-closed`; not counted toward the breaker. The lane is freed; a reopened pull request holds it again (lane-holder set). |
| Elapsed review wait | 3600 seconds since the `ended_at` of the run that recorded the pinned head, with no merge. | Batch review, reason `review-wait-elapsed`. |
| Auto-tier script error | `TIER_ERROR=`, a non-zero exit, a killed run, or any output other than exactly one `TIER=auto` line or one `TIER=review:` line of known codes. | No merge this tick. The review wait bounds it. |

## Decisions

A decision that is not ADR-worthy names the [P20](../../engineering-principles.md) condition it fails.

- **The tick runs `merge-approved.sh`.** ADR-0044 decisions 17 and 20.
- **The tick's settle check equals decision 1.** ADR-0044 decision 18.
- **The expected-head argument.** ADR-0044 decision 19, amending decisions 4 and 9.
- **The tick routes its own result by this design's table.** ADR-0044 decision 20, amending decision 10.
- **Merge settings come only from the user's two settings files.** ADR-0044 decision 17. ADR-0045 decision 12's "re-reading `HIVEMIND_AUTO_MERGE` and `HIVEMIND_AUTO_MERGE_ADMIN` every tick" holds as written.
- **The auto-tier inputs.** ADR-0045 decision 12. The input sources are not ADR-worthy: each fails P20's hard-to-reverse condition.
- **A Lair pull request is one the Lair recorded after checking it, while its claim is live.** ADR-0045 decision 12. The Lair rechecks it in the late group with the same function. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The merge call pins only the head, and every other tick-read input is one class of known limit.** Decided by the run under `plugin/governance/decision-autonomy.md` (Review Calls), on a local-review root-cluster finding, 2026-11-21. Not ADR-worthy: fails P20's hard-to-reverse condition. It extends ADR-0044 decision 15 by analogy, from the script's own read to the tick's late group, and changes nothing in ADR-0044. See the Known limit under Merge-lane step of the tick.
- **No merge after an issue edit.** Extends ADR-0045 decision 10. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The CI-red rule: one fix-up run for failed checks, then batch review.** Extends ADR-0045 decision 13. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **A fix-up run's parks follow ADR-0045 decision 7.** ADR-0045 decision 7 as written: `decision` and `fact` parks are answerable on the issue, and a third park hands it off.
- **A review marker does not stop a fix-up run.** ADR-0045 decision 13 and the PRD's Post-PR feedback criterion as written.
- **The wall-clock budget is per issue, and fix-up runs run on what is left of it.** ADR-0045 decision 17 and the PRD's Budgets and recovery criterion as written.
- **The breaker counts only `failed`, `crashed`, `stalled` and `timed-out`.** ADR-0045 decision 17 and the PRD's Stop controls criterion as written for `failed`, `crashed` and `timed-out`. `stalled` rests on solution-design.md's Stall row, which counts a stall toward the breaker, over the shorter outcome list of its Component "Decision digest and circuit breaker".
- **The halt and breaker stop claims and fix-up runs; merges continue.** Tier A answer Q10, 2026-11-21. ADR-0045 decision 17 says only that the halt stops new claims and that unsetting auto-merge stops merges; that fix-up dispatch stops too, and that merges go on under a halt or a tripped breaker, is the user's Q10 answer.

The merge lane's own decisions reverse no ADR-0045 decision. Decision 12 already names the script, the per-tick settings read and the auto-tier conditions; decision 13 already starts fix-up runs on review findings, a held pull request's included, and the start preconditions turn none away beyond a live claim (Q7), one run at a time and the per-issue budget (the PRD) and the halt and breaker (Q10), with no precondition on GitHub's head; decision 7 already types every park, a fix-up run's included; decision 17's breaker outcomes are kept as written, with `stalled` from solution-design.md's Stall row, and so is its per-issue budget. Two points go past ADR-0045's text and rest on the user's Tier A answers of 2026-11-21, not on ADR-0045 alone: the halt and the breaker stop fix-up dispatch while merges continue (Q10); and the tick's merge path amends ADR-0044 (Q1, Q3), so ADR-0045's status line "Keeps ADR-0044's merge rules." and the PRD's Out of Scope bullet on those rules change (Changes to shared documents, items 6 and 7). The strain settings' merge keys are #630's pending ADR-0045 and PRD question (A3-1), not this design's.

### Tier A answers

The user answered A to each question on 2026-11-21:

- **Q1.** Amend ADR-0044 decisions 2 and 10 so the Lair's tick may run `merge-approved.sh`. Applied as ADR-0044 decisions 17 and 20.
- **Q2.** A settle check equal to ADR-0044 decision 1: the watch's change check against a saved snapshot each tick, 600 quiet seconds, and a lost cache only delays a merge. Applied as decision 18 and the Settle check component.
- **Q3.** An optional sixth expected-head argument; a different head prints `MERGE=wait:head-moved` with no merge call. Applied as decision 19.
- **Q4.** Merge settings only from the user's `.claude/settings.local.json`, then `~/.claude/settings.json`, with a PRD Credentials note. Applied under Contracts and seams, with the note under Changes to shared documents.
- **Q5.** Protected paths from a trunk list plus a fixed floor; the bump from the version-file diff. Applied in the Auto-tier script component.
- **Q6.** Local-review proof is the delivery run's recorded head plus heads the Lair's own fix-up runs recorded. Applied in the Auto-tier script component.
- **Q7.** Only a pull request the Lair recorded on the claimed issue after checking it against GitHub may merge. Applied under Contracts and seams.
- **Q8.** No merge after an issue edit; the pull request goes to batch review. Applied as step 15 of the merge-lane step.
- **Q9.** One fix-up run for failed checks, then batch review. Applied as the CI-red rule.
- **Q10.** The halt and the breaker stop claims and fix-up dispatch; merges continue; unsetting auto-merge stops merges. Applied in Fix-up runs and Lifecycle stage 4.

### Decided for you

Each of these is listed for veto. None is ADR-worthy: each fails P20's hard-to-reverse condition, as a script constant, a marker field or a routing row that a later change can alter.

- **The review marker is authoritative and final.** The Lair never merges a pull request that has one, even if the label is removed. A `lair:review` label only adds a hold (R27).
- **Markers go on the claimed issue, never the pull request.** One place to read, under one marker rule.
- **The review wait is 3600 seconds**, the watch's `max_watch_duration` default in `SKILL.md` (recorded in ADR-0029's Findings), measured from the recording run's `ended_at`, so it survives a lost cache.
- **The routing rows.** No checks, conflicts, a blocked merge and a refused merge go to batch review. A script error, malformed output and `merge-pending` wait, bounded by the review wait. `skipped:bad-setting` is handled like `off`.
- **The late group and its order.** The late group is the last tick work, in this order: the merge settings, the credential login, the trunk tip, the identity (with the merge-queue state and `lair:review` on the pull request), the issue (its state, `lair:claimed`, `lair:review` and text) and the settle check, then the merge call and nothing else. The seconds between its reads and that call are the merge gap (Known limit, Merge-lane step of the tick).
- **No expected base, author or branch arguments for `merge-approved.sh`.** Rejected: GitHub offers no merge call that pins those inputs, so the arguments would only narrow the merge gap and add script surface, and the issue and the settle snapshot would still stay outside what the merge call pins (Known limit, Merge-lane step of the tick).
- **The head check goes first** in `merge-approved.sh`, before gate 1, so a moved head never yields another gate line.
- **`HIVEMIND_PR_REVIEWERS` comes from the same two user files** as the merge keys (ADR-0043 decision 2), and the reviewer filter is `automated`.
- **The settle snapshots use the `re-arm` arm kind** and are keyed by pull request and pinned head.
- **The trunk file is `.github/lair.json`.** It holds `protected_paths` and `version_files` under a strict schema. A missing, unparseable or malformed file sends every pull request to batch review. This repository's list holds at least the entries R19 names; any more are proposed in #605's pull request.
- **A major bump is a rise in the major component** of any declared version file. A missing, unparseable or lower value goes to batch review.
- **A fix-up head counts as reviewed only when the claim's local-review head is not null**, so a fix-up run cannot launder a skipped local review.
- **A fix-up head is recorded only when the previous recorded head is its ancestor.**
- **The delivery outcome mapping.** `blocked`, `no-pr` and an invalid result give `lair:failed`, as `failed`, `crashed`, `stalled` and `timed-out` do. A pull request closed unmerged gives `lair:handoff`. Extends ADR-0045 decision 16. The breaker side is R14.
- **A complete run's draft pull request goes to batch review with reason `draft`** and does not hold the lane.
- **The test layout and suite names** under Verification strategy.
- **#605 fixes the Lair's script directory**, `plugin/skills/lair/scripts/`, because it builds first; the fix-up, halt, breaker, start-check, result recording, delivery run end, lane-holder and admission test cases are added to `tools/test_lair_merge_lane.sh` by the slices that build them. Decided by the run, 2026-11-21, on M1-A8; round 3 moved the #608 cases under #608 (M3-A6).
- **Every tick read fails closed.** A read that fails or does not read every page means no merge and no label change that tick; only the review wait may still route, from the markers. Decided by the run, 2026-11-21, on M1-B3.
- **A resetting settle result deletes the seed before the new snapshot**, and only exactly one known line with exit 0 counts, for the poll and the auto tier alike. Decided by the run, 2026-11-21, on M1-B4 and M1-B5.
- **A fix-up run is supervised from its markers.** The start marker goes first and a failed write launches nothing; the stall window runs from `started_at` and the budget from `claimed_at` (R15); a lost run with no unprocessed result gets an end marker with outcome `crashed`, or `not-launched` when it has no worktree (R28). Decided by the run, 2026-11-21, on M1-B6.
- **Every multi-write route has a fixed write order**, each write idempotent and finished on later ticks, with no second review marker for a pull request under one claim. Decided by the run, 2026-11-21, on M1-B7. The order itself is R29's: round 3 replaced the marker-first order and its applied marker.
- **A Lair pull request needs a live claim, an open issue and `lair:claimed`.** A closed issue or a removed `lair:claimed` is the claim-withdrawn exit, and the closed-unmerged exit also writes a review marker. Decided by the run, 2026-11-21, on M1-B8.
- **The protected-path floor** is the root `.github/` directory and the exact path `.github`, any `.claude` path segment, any file named `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.gitmodules` or `.gitattributes` at any depth, and any path with a byte other than printable ASCII or a segment ending in `.` or a space, with ASCII case ignored; the list gains the `**/<name>` file-name form, and a prefix entry also matches its exact path. Decided by the run, 2026-11-21, on M1-B11 and M2-B12.
- **The strict `.github/lair.json` schema**, with `[]` the only way to declare no entries. Decided by the run, 2026-11-21, on M1-B12.
- **The tick reads only the two named settings files**, and the queue report names the files read. Decided by the run, 2026-11-21, on M1-B15.
- **The late group rereads the issue's state and `lair:claimed`.** A withdrawal that step 15 sees makes no merge call and is routed by the next tick's step 2, so a merge that closed the issue is never routed as a withdrawal. Decided by the run, 2026-11-21, on M2-A1.
- **Step 2 reads the issue before the pull request and routes a merge first.** Decided by the run, 2026-11-21, on M2-B9.
- **A waiting CI-red rule and a queued pull request each run only the review wait, then stop.** Decided by the run, 2026-11-21, on M2-A9; the queued case is R22's.
- **Results stay in the run's worktree until their marker is written** (R22). A failed result-check read retries on later ticks, bounded by the issue's budget, and only a check that reads and fails makes a result invalid. Decided by the run, 2026-11-21, on M2-B2.
- **The lane-holder set**, kept by #608, holds every pull request a run-end marker names (R23), closed ones included until merged (R30), and admission fails closed on any failed read of it. Decided by the run, 2026-11-21, on M2-B3.
- **The Lair's git repository is checked each tick and rebuilt on any change it did not write**, and every git call drops the environment's `GIT_*` variables and sets `GIT_NO_REPLACE_OBJECTS=1` and `diff.ignoreSubmodules=none`. Decided by the run, 2026-11-21, on M2-B4.
- **A queued pull request makes no further merge call.** Decided by the run, 2026-11-21, on M2-B8. Round 3 replaced the merge-pending mark that held it with GitHub's own merge-queue state (R22).
- **A fix-up run that ends under an ended claim writes only its end marker.** Decided by the run, 2026-11-21, on M2-B10.
- **The lane order rotates**: the pull request whose merge call ran last goes to the end of the next tick's order. Decided by the run, 2026-11-21, on M2-B13.
- **The tick's `PATH` puts the resolved tool directories first**, and the Lair refuses to start when `command -v` of a tool under it differs from its resolved path. Decided by the run, 2026-11-21, on M2-B14.
- **R1: a fix-up run's `decision` and `fact` parks are answerable on the issue and count toward the third-park handoff** (ADR-0045 decision 7). #609 handles them as a delivery run's park; the Lair first converts the pull request to a draft, so it belongs to its parked issue and does not hold the lane. Decided by the run, 2026-11-21, on M1-A3.
- **R2: no cap on fix-up runs for review findings.** What starts them stays with #610 (ADR-0045 decision 13, the PRD's Post-PR feedback criterion); the unbounded review loop is a seam note for #610. Decided by the run, 2026-11-21, on M1-A4.
- **R3: `lair:review` goes on both the issue (PRD Labels and Admission) and the pull request (ADR-0045 decision 12).** Decided by the run, 2026-11-21, on M1-A5.
- **R4: no strain process can write what the tick reads or runs** (an assumption about #630), and the tick hardens its own git and tool calls: a Lair-owned bare repository, hooks and system and global config off, a fixed URL, the trunk id from this tick's `ls-remote`, and tools by absolute path, with the round-2 additions on M2-B4 and M2-B14. The residuals are ADR-0045's prompt-injected strain, with its merge-lane consequences listed, and a strain that writes the tick's inputs. Round 3 restates the assumption as a property and adds the start checks (R26). Decided by the run, 2026-11-21, on M1-B1.
- **R5: markers are assumed unforgeable by a process that holds the user's credentials and the nonces** (an assumption about #632); otherwise marker forgery is a named residual. Decided by the run, 2026-11-21, on M1-B2.
- **R6: the merge environment is the Lair's own minus every `HIVEMIND_*` key, plus the keys read from the two settings files**, and a `gh api user` login check runs in it before every merge call. Decided by the run, 2026-11-21, on M1-A2 and M1-B10.
- **R7: the CI-red rule fires from the tick's own rollup read on the pinned head or `MERGE=wait:checks-failed`**, whichever comes first, whatever the merge settings, the approval and the gate order. The settle check's `CI_FAILED` only means not settled (R17). Decided by the run, 2026-11-21, on M1-B13 and M1-A14.
- **R8: a run-end marker the merge lane owns holds `pr`, `branch`, `head` and `local_review_head`**, separate from #632's claim marker, of which the lane reads only `claim_nonce`, `claimed_at` and `body_sha256`. Decided by the run, 2026-11-21, on M1-A6.
- **R9: at most one merge call per tick, and the trunk tip is a late-group input**, with the auto tier run again when it moved. Decided by the run, 2026-11-21, on M1-B17.
- **R10: every merge-lane child process runs under a 300-second timeout**, `merge-approved.sh` excepted since round 3 (R25); a killed read counts as a failed read. Decided by the run, 2026-11-21, on M1-B16.
- **R11: the empty-string merge keys in strain settings are #630's pending ADR-0045 and PRD question (A3-1)**, not this design's; this design claims only that its own decisions reverse no ADR-0045 decision (Decisions). Decided by the run, 2026-11-21, on M1-A9.
- **R14: the breaker counts only `failed`, `crashed`, `stalled` and `timed-out`**, the outcomes ADR-0045 decision 17 and the PRD's Stop controls criterion name, with `stalled` from solution-design.md's Stall row. Delivery `blocked`, `no-pr` and `invalid-result`, and fix-up `blocked` and invalid results, neither add to the count nor reset it, nor does any fix-up end under an ended claim; a `complete` run end under a live claim resets it. Decided by the run, 2026-11-21, on M2-A3.
- **R15: the wall-clock budget is per issue, measured from the claim marker's `claimed_at`, and a fix-up run runs on what is left of it** (the PRD's Budgets and recovery criterion, ADR-0045 decision 17). The fix-up outcome mapping: `complete` with checks passing records the head; `parked` is #609's park; `failed`, `blocked` and an invalid result go to batch review with reason `fixup-failed`; `crashed`, `stalled` and `timed-out` give `lair:failed` and end the claim. With no budget left no fix-up run starts, and the pull request goes to batch review with reason `budget-exhausted`, a tick route and not a run outcome. The stall window runs from the start marker's `started_at`. The round-1 rules for the start marker and the `crashed` end marker stand, but a `crashed` fix-up run now gives `lair:failed`, like `stalled` and `timed-out`, where round 1 sent it to batch review. Decided by the run, 2026-11-21, on M2-A4.
- **R16: a review marker does not stop a fix-up run** (ADR-0045 decision 13, the PRD's Post-PR feedback criterion); the round-1 rule on M1-B9 is reverted. The design sets preconditions on #610's trigger only where a binding source allows: a live claim, no run in flight, budget left, and no halt or tripped breaker. Round 3 dropped the round-2 precondition that GitHub's head equal the pinned head (M3-A1): a fix-up run starts at the pinned head, and a moved branch fails its leased first push. Fix-up runs pushing while the user reviews is a recorded residual (Fix-up runs). Decided by the run, 2026-11-21, on M2-A5.
- **R17: the settle check's `CI_FAILED` is not a CI-red signal**; CI-red comes from step 7's rollup read on the pinned head and from `MERGE=wait:checks-failed`. Its round-2 start precondition, a fresh GitHub head equal to the pinned head, is dropped in round 3 (M3-A1, R16). Decided by the run, 2026-11-21, on M2-A6.
- **R18: every strain push uses a lease** (an assumption about #630): a fix-up run's against its `start_head`, then its own last push, so a push by another process makes the run's next push fail, no head built on it is recorded, and a failed fix-up run goes to batch review with reason `fixup-failed`. ADR-0044's amendment and the pinned-head trust bullet are conditional on it; without it, ADR-0044's residual "An unreviewed push by another account can merge" applies through fix-up heads. #630 adds it as a strain-only mode of `push-branch.sh` and `open-plan-pr`, reversing their recorded lease decision for strains only, and the interactive push path is unchanged (M3-A4). Decided by the run, 2026-11-21, on M2-B5.
- **R19: this repository's `.github/lair.json` must protect `plugin/skills/lair/`, `plugin/skills/github-review-loop/scripts/`, `plugin/skills/_shared/`, `plugin/hooks/`, `plugin/.claude-plugin/`, `.claude-plugin/`, `plugin/workflow-src/`, `plugin/workflows/`, `tools/` and `tests/policy/`**, a requirement on #605's list derived from what the merge, poll, auto-tier and tick scripts run or source and from the local-review evidence producers, with a test that the committed list holds them. Decided by the run, 2026-11-21, on M2-B6; round 3 added `plugin/skills/_shared/`, `.claude-plugin/`, `plugin/workflow-src/` and `plugin/workflows/` (M3-A5, M3-B4).
- **R20: a pull request GitHub's merge queue already holds is not taken out of it** when `HIVEMIND_AUTO_MERGE` is unset or a review marker is written later; no dequeue write is added, and the case is a named residual (Trust boundaries). Decided by the run, 2026-11-21, on M2-B11.
- **R21: the PRD Out of Scope change and the ADR-0045 status-line change derive from Tier A answers Q1 and Q3** (Changes to shared documents, items 6 and 7), so neither is listed for veto, and the round-1 call R13 is withdrawn from this list. Decided by the run, 2026-11-21, on M2-A10 and M2-A11.
- **R22: GitHub's merge-queue state replaces the merge-pending mark, and the result file replaces the result cache.** Step 2 and the late group read the pull request's merge-queue state; a queued pull request gets no merge call. The Lair removes no run's worktree or result file until that run's end marker is written, so no Lair-only copy of a result exists. Decided by the run, 2026-11-21, on M3-A2 and M3-B1.
- **R23: every pull request a run-end marker names holds the lane while open and not a draft, recorded or not.** The run-end marker holds `pr` for every result that names one and passes the schema check; only a checked `complete` result records it. A pull request no result names is a recorded residual. Decided by the run, 2026-11-21, on M3-A3.
- **R24: under #606's release-train mode the auto tier fails closed with `version-unreadable`** until #606 supplies a bump input the pull request cannot change; Q5's input is unchanged. Decided by the run, 2026-11-21, on M3-A7.
- **R25: `merge-approved.sh` runs under no child timeout**, as its header requires; its own reads are bounded, its merge call is never cut off, and the merge-queue read covers a merge call whose line was lost. Decided by the run, 2026-11-21, on M3-A8.
- **R26: the #630 write assumption is a property: a strain writes nothing outside its worktree and the shared object and ref store.** The Lair refuses to start when `$HOME/.jq` exists or `gh` has an `http_unix_socket` set; a later write of either is named in the residual. Decided by the run, 2026-11-21, on M3-B2.
- **R27: a `lair:review` label on the issue or the pull request is an extra hold**, read at steps 3, 14 and 15. It only adds holds and fails closed; the review marker stays authoritative for release. The Lair acting as the user's own login, so that the user's own review comments never block a merge, is a named residual with the user's working holds listed. Decided by the run, 2026-11-21, on M3-B3.
- **R28: a fix-up start marker with no live session, no result and no worktree ends `not-launched`**, which writes no label, does not end the claim, leaves the breaker unchanged and does not use up the CI fix-up; the worktree is the launch evidence. Decided by the run, 2026-11-21, on M3-B5.
- **R29: a route writes its labels and pull request changes first and its markers last**, so the marker that ends the route marks it done, and a later tick that finds it missing computes the route again from the same inputs. The applied marker and the walk over unfinished sequences are removed. Decided by the run, 2026-11-21, on M3-B6.
- **R30: a closed pull request stays in the lane-holder set until GitHub shows it merged**, so a reopened one holds the lane again. Decided by the run, 2026-11-21, on M3-B11.
- **R31: a claimed-issue read that GitHub answers as not found or moved is named in the queue report as needing the user from the first such answer**, with no clock and no new cache; the pull request's own state read still frees the lane. Decided by the run, 2026-11-21, on M3-B12.

### Changes to shared documents

None of these is applied in this pull request.

1. **PRD Credentials bullet.** Target: [docs/prds/autonomous-ready-issue-loop.md](../../prds/autonomous-ready-issue-loop.md), Implementation Decisions, the bullet that begins "**Credentials.**". Replace its second sentence, "Merges follow the user's existing merge settings, the admin bypass included, read fresh each tick.", with: "Merges follow the user's own merge settings, read fresh each tick from `.claude/settings.local.json` and then `~/.claude/settings.json`, never from the committed settings, the admin bypass included." Answer: Tier A, Q4, approved 2026-11-21.
2. **Amendments pointer.** Target: [solution-design.md](solution-design.md), section Amendments, a new paragraph after its last line: "2026-11-21: For the merge lane, [merge-lane-design.md](merge-lane-design.md) supersedes the parts its opening paragraph names: the Merge lane and auto tier component; the GitHub-record, park and halt side of Post-PR remediation strains and the start of a fix-up run for failed checks; the Auto-tier script result contract; the Strain result contract, which gains `local_review_head`; every run-end record in the claim marker, that is, the run-end sentence of the Claim marker comment contract, the run-end update of the Claim marker comment row under State and ownership, stage 1's recording of the outcome in the claim marker, and the claim-marker part of the Decision on the outcome and the session-scoped breaker; the outcome list of the Decision digest and circuit breaker component, which gains `stalled` from the Stall row; the merge-settings channel; the Lifecycle label bullets for `lair:handoff`, `lair:failed` and `lair:review`, stage 1's merge step, stage 3 whole and stage 4's merge stop, and it adds the draft, closed-unmerged and claim-withdrawn exits; the Failure modes rows Crash, Merge refused, CI red and Issue edited after claim, and the row GitHub API failure or rate limit for the merge lane; and three Decisions. ADR-0044's amendment of the same date lets the Lair's tick run `merge-approved.sh`." Answer: decided for you, listed for veto.
3. **Round-3 dispositions.** Target: [review-record.md](review-record.md), the Disposition column of the Round 3 tables, and the `open_counts` front matter recomputed to match. Each `open` cell below becomes the text given, the same text the [merge-lane review record](merge-lane-review-record.md) holds for that finding:
   - A3-2: "fixed: merge-lane-design.md, Settle check, Routing table and Failure modes, under ADR-0044 decisions 17, 18 and 20; completed in round 1 by M1-B3, M1-B4, M1-B5, M1-B13 and M1-B16, in round 2 by M2-A6, M2-A9 and M2-B8, and in round 3 by M3-A2 and M3-B1".
   - A3-3: "fixed: merge-lane-design.md, Merge settings source, Merge environment and Lifecycle "Stage 4: halt and circuit breaker"; completed in round 1 by M1-A2, M1-B10 and M1-B15, and in round 2 by M2-B11".
   - B3-4: "fixed: merge-lane-design.md, Lair pull request, Pinned head and Merge-lane step of the tick (late group); completed in round 1 by M1-A6, M1-B1, M1-B2 and M1-B8, in round 2 by M2-A1, M2-B2, M2-B3 and M2-B5, and in round 3 by M3-B2".
   - B3-5: "fixed: merge-lane-design.md, Settle check, Pinned head and Expected-head argument; completed in round 1 by M1-B4, M1-B5 and M1-B17, in round 2 by M2-B8, and in round 3 by M3-A2 and M3-B1".
   - B3-6: "fixed: merge-lane-design.md, Routing table and Failure modes".
   - B3-7: "fixed: merge-lane-design.md, Merge settings source and Merge environment; completed in round 1 by M1-A2, M1-B10 and M1-B15".
   - B3-8: "fixed: merge-lane-design.md, Auto-tier script, Git and tool reads and Trust boundaries; completed in round 1 by M1-B1, M1-B11, M1-B12 and M1-B17, in round 2 by M2-B4, M2-B6, M2-B12 and M2-B14, and in round 3 by M3-A5, M3-B2 and M3-B4".
   - A3-10: "fixed: merge-lane-design.md, Auto-tier script and Trust boundaries; completed in round 1 by M1-B1, M1-B11 and M1-B12, in round 2 by M2-B4, M2-B6 and M2-B12, and in round 3 by M3-A5, M3-B2 and M3-B4".
   - A3-8: "fixed: merge-lane-design.md, Exits (Draft, Closed unmerged, Claim withdrawn) and Write order; completed in round 1 by M1-B7 and M1-B8, and in round 2 by M2-B3 and M2-B9".
   - B3-13: "fixed: merge-lane-design.md, Run outcome to labels; completed in round 2 by M2-A3".
   - B3-14: "fixed: merge-lane-design.md, Fix-up runs, Markers the merge lane writes, Run outcome to labels and Lifecycle "Stage 4: halt and circuit breaker"; completed in round 1 by M1-A3, M1-B6 and M1-B7, in round 2 by M2-A4, M2-A5, M2-B2 and M2-B10, and in round 3 by M3-B5".
   - A3-13: "fixed: merge-lane-design.md, Exits (Batch review: on the issue and the pull request) and State and ownership; completed in round 1 by M1-A5".

   The parent record assigned A3-2, A3-3, A3-10, B3-4, B3-5, B3-6, B3-7 and B3-8 to #631. The issue's brief, the strain's task text, assigned it A3-8, B3-13, B3-14 and A3-13 in full, and its own part of A3-11, A3-12 and B3-20. A3-11, A3-12 and B3-20 stay open there: the merge-lane review record dispositions only this issue's part of each, and their other parts stay with the parent record. Answer: decided for you, listed for veto.
4. **Lair pull request term.** Target: [CONTEXT.md](../../../CONTEXT.md), section Language, a new entry after the **Lair** entry, in the glossary's three-line form:

   ```text
   **Lair Pull Request**:
   A pull request the **Lair** recorded on its claimed issue after checking a strain's complete result against GitHub: same repository, trunk base, the Lair's own login as author, and the result's branch and head. It stays one while its claim is live and the issue is open and carries `lair:claimed`. Only a Lair Pull Request can be merged by the Lair.
   _Avoid_: strain PR, factory PR
   ```

   Answer: decided for you, listed for veto.
5. **Tier A merge bullet.** Target: `plugin/governance/decision-autonomy.md`, Tier A, the bullet "every merge recommendation; the human merges, except the review watch's opt-in merge after a reviewer approval, per `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/SKILL.md`". Replace it with: "every merge recommendation; the human merges, except the review watch's opt-in merge after a reviewer approval, per `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/SKILL.md`, and the Lair tick's merge of a Lair pull request in the auto tier under ADR-0044 decision 17". Built by #605 with the fixture update and the structural check under Existing-path coverage, within the file's byte budget. Basis: ADR-0044 decision 17. Answer: Tier A, Q1, approved 2026-11-21.
6. **PRD Out of Scope bullet.** Target: [docs/prds/autonomous-ready-issue-loop.md](../../prds/autonomous-ready-issue-loop.md), Out of Scope, the bullet "**Changing the ADR-0044 merge rules** beyond the auto-tier precondition, and changing the repository's ruleset." Replace it with: "**Changing the ADR-0044 merge rules** beyond the auto-tier precondition and the Lair tick's merge path of ADR-0044's 2026-11-21 amendment (decisions 17 to 20), and changing the repository's ruleset." Basis: Q1 lets the tick run `merge-approved.sh`, and Q3 adds the expected-head argument. Answer: Tier A, Q1 and Q3, approved 2026-11-21.
7. **ADR-0045 status line.** Target: [ADR-0045](../../adr/0045-lair-software-factory.md), the Status line, its last sentence, "Keeps ADR-0044's merge rules." Replace it with: "Keeps ADR-0044's merge rules, as ADR-0044's amendment of 2026-11-21 (decisions 17 to 20) extends them to the Lair's tick." Basis: Q1 lets the tick run `merge-approved.sh`, and Q3 adds the expected-head argument. Answer: Tier A, Q1 and Q3, approved 2026-11-21.

## Verification strategy

The tests follow the PRD's [Testing Decisions](../../prds/autonomous-ready-issue-loop.md#testing-decisions) "Merge tests" and controller-tick tests. All run offline against recorded GitHub states, with no live GitHub.

- **Expected-head cases in `tools/test_merge_approved.sh`:**
  - a sixth argument equal to the head merges, with `--match-head-commit` equal to it;
  - a different head prints `MERGE=wait:head-moved` with one read and no merge call, even when the read's rollup is failed;
  - a malformed sixth argument prints `MERGE_ERROR=bad-expected-head` with no `gh` call; the existing case `args:six`, whose sixth argument is `extra`, is rewritten to expect this;
  - seven arguments print `MERGE_ERROR=bad-arguments`;
  - a refused plain merge whose re-read head differs prints `MERGE=wait:head-moved`.

  One more property is checked over every case: with a sixth argument, every merge call's `--match-head-commit` equals it. The five-argument cases are unchanged.
- **Auto-tier test runner, `tools/test_auto_tier.sh`, with fixtures in `tests/auto-tier/`:**
  - The runner builds scratch git repositories, and each case asserts the one output line.
  - Protected paths: a floor path; a trunk-list path; a list entry added on the pull request head, which is ignored; a rename into a protected directory; a rename out of a protected path, which only `--no-renames` lists by its old side; and a copy into a protected directory. Each asserts `protected-path`.
  - The floor by name and case: `docs/CLAUDE.md`, `a/CLAUDE.local.md`, `sub/.mcp.json`, `y/.gitmodules`, `x/.gitattributes`, `a/.claude/b`, `.Claude/x`, `claude.md`, `.GitHub/workflows/x.yml` and the exact path `.github`.
  - The odd-path floor: a path with a non-ASCII byte, a path with a control byte, a segment ending in `.`, and a segment ending in a space.
  - The list forms: an exact path, a directory prefix, the prefix's exact path without the `/`, and a `**/<name>` entry, each also matched with other case.
  - Trunk file: missing; unparseable; not an object; an extra top-level key; each key missing; each key not an array; a malformed `protected_paths` entry (empty, leading `/`, a `..` segment, a stray `*`); a `version_files` entry with a missing or extra key, a malformed `path` or an empty `key`; and `[]` for both, which is accepted.
  - This repository's committed `.github/lair.json` holds each of the ten entries R19 names.
  - Bump: major, minor, and an unreadable or lower version.
  - Local review: the delivery's local-review head; a fix-up head; a fix-up head with a null local-review head; an unrecorded head.
  - Several reasons at once, in their fixed order.
  - Errors: no merge base, a commit that is not present, an unusable git directory, and bad arguments.
  - Git settings: a `refs/replace/` ref in the git directory that swaps the pinned head's tree does not change the result, and neither does a `GIT_*` variable such as `GIT_OBJECT_DIRECTORY` or `GIT_CONFIG_PARAMETERS` in the caller's environment.
- **Merge-lane tick tests, `tools/test_lair_merge_lane.sh`, with fixtures in `tests/lair-merge-lane/`:**
  - A PATH-shim `gh` and `git` serve recorded GitHub states and log the argv and environment of every call, and fake merge, poll and auto-tier scripts record theirs. The tick's settings-file reader, credential read, cache reader and #632's marker rule are called through names the test replaces, so the fake-call log records them.
  - Git hardening: a property checked over every case, that every logged git call has no inherited `GIT_*` variable, sets `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_NO_REPLACE_OBJECTS=1`, names the git directory, passes `-c core.hooksPath=/dev/null` and `-c diff.ignoreSubmodules=none`, fetches from the fixed URL and names no local ref for the trunk or head. For each rule, a negative case feeds the property a log with that rule broken, and the property must fail.
  - Git repository check: a config entry the Lair did not write, a `refs/replace/` ref, an `info/grafts` file and an `objects/info/alternates` file in the bare repository each make the tick rebuild it before any git read.
  - Routing: every row of the routing table, plus a check that the table names every `MERGE=` line listed in `merge-approved.sh`'s output contract. The fake-call log shows `merge-approved.sh` called with no timeout wrapper. A `MERGE_ERROR` after a merge call, followed by a next-tick state read of `MERGED`, gives the merged exit.
  - Merge settings: the local file winning; the user file used alone; an empty local value overriding the user's; committed settings ignored; a key in the Lair's environment ignored; `CLAUDE_CONFIG_DIR` set and ignored; an unparseable file, an `env` that is not an object, and a merge value that is a number or `null` each meaning no merge; the queue report naming the files read.
  - Merge environment: no `HIVEMIND_*` key from the Lair's environment reaches the fake scripts; `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `XDG_CONFIG_HOME` and a keyring variable pass through; a credential login that differs, or a failed credential read, makes no merge call and names the reason.
  - Settle check: a check that the tick names every `--check` and `--snapshot` output line of the poll script's contract; the first sighting; `UNCHANGED` under 600 seconds and at 600 seconds, on an injected clock; each resetting marker; `CI_FAILED` then `SNAPSHOT_ERROR`, after which an `UNCHANGED` against the old seed is not settled; `CI_FAILED` starting no fix-up run; `SNAPSHOT_ERROR` on a first sighting; a malformed `BASELINE=` line; `STATE=MERGED` and `STATE=CLOSED` from `--check`; `CHECK_ERROR`; `UNCHANGED` with a second line or a non-zero exit; a lost cache.
  - Auto tier: `TIER=auto`; `TIER=review:` with known codes; an unknown code; two lines; `TIER=auto` with a non-zero exit; `TIER_ERROR`; a run killed by the timeout.
  - Child timeout: a poll run, a git read and a `gh` read each killed by the 300-second timeout count as a failed read, with no merge call and no label change.
  - Merge queue: a pull request in the merge queue on step 2's read gets no merge call and runs only the review wait; one that enters the queue after step 2 is seen by step 14, with no merge call; a failed confirm read after a queued merge call (`MERGE_ERROR`), followed by a tick whose read shows the pull request queued, makes no merge call; `MERGE=wait:merge-pending` followed by a queued read makes no merge call on the next tick.
  - Fail-closed reads: a review marker on the second comment page still holds the pull request; an incomplete comment read does nothing; a failed pull request read or issue read in step 2 runs only the review wait; a failed identity read, late issue read, `ls-remote` or fetch makes no merge call and no label change.
  - Step 2 order: a merged pull request whose issue the merge closed gives the merged exit, not the claim-withdrawn exit.
  - Pinned head: equal, moved, unrecorded, and a fix-up head that is not a descendant.
  - Lair pull request checks: the five failing cases, a fork, a wrong base, another author, a branch mismatch and a head mismatch, each run through both paths. The recording path gives an invalid result. The late group gives `identity-changed` and no merge call.
  - Lair pull request state: a closed issue and a removed `lair:claimed` each give the claim-withdrawn exit and no merge; a withdrawal that lands after step 2 is seen by step 15, which makes no merge call, and the next tick gives the claim-withdrawn exit; a claim with a terminal outcome is never merged.
  - Holds and skips: a review marker with the `lair:review` label removed still gives no merge; a `lair:review` label on the issue or on the pull request with no review marker gives no merge, and one added after step 2 is seen by step 14 or 15; a fix-up run in flight is skipped.
  - Marker rule: for each marker kind the lane reads, the claim, run-end, fix-up start, fix-up end, review and exit markers, a copy that fails #632's rule, called through a name the test replaces, is ignored. Among them, a non-conforming run-end marker and a non-conforming fix-up end marker naming another `head` or `local_review_head` change neither the pinned head nor the local-review proof.
  - Issue not found: a claimed-issue read answered as not found names the issue and its pull request in the queue report as needing the user, with no merge and no label change.
  - Late group: one property checked over every case that reaches the merge call. The fake-call log shows the late-group reads in order, the settings files, the credential read, the `ls-remote`, the pull request, the issue and the settle check, with only the merge script call after the last, so a tick read added after the group fails the test. A trunk that moved in the late group reruns the auto tier.
  - One merge per tick: with two pull requests ready, the tick makes one merge call.
  - Lane order: with two pull requests ready and the first returning `MERGE=wait:checks-pending` on every tick, the second gets the merge call on the next tick.
  - Exits: the merged exit from a state read, not only from the script's confirm read; the draft and closed-unmerged exits, the latter not counting toward the breaker; the review wait; issue edit before merge.
  - Write order: a tick stopped after each write of each lane route, before its last marker; the next tick computes the route again, repeats its writes and writes each marker once; a batch review stopped before its review marker stays held by its label; a second batch review route writes no second review marker.
  - A pull request whose body holds a "Decided for you" list still merges.
  - Cases added by the slices that build them.
    - #608: the halt stopping fix-up runs while merges continue. The start checks: a shadowing tool earlier on the fixed `PATH`, a `$HOME/.jq` and a `gh` `http_unix_socket` each make the Lair refuse to start. Result recording: a result whose worktree is kept is not ended as crashed by a tick or the start-up sweep; a failed or incomplete read during the result checks leaves the result unprocessed and the next tick records it; GitHub's head a strict ancestor of the result's head right after a push leaves the result unprocessed, and the next tick records it once the head catches up; a check that reads and fails gives an invalid result; a result still unchecked when the budget passes ends the run `timed-out`. Delivery run ends: `no-pr`, `blocked`, `failed`, `crashed`, `stalled`, `timed-out` and the draft delivery, each also stopped after each write before its run-end marker, so the next tick finishes it from the kept result file. Lane-holder set and admission: a recorded pull request whose claim ended by withdrawal or by a fix-up `timed-out`, while open and not a draft, blocks admission; so does an open non-draft pull request named by a `blocked`, `failed` or `invalid-result` run end, and a parked run's draft once the user marks it ready; a closed recorded pull request that is reopened blocks admission again; one leaves the set only when merged; a failed read of it, or a lost set not yet rebuilt, means no claim; the queue report names it.
    - #610: the CI-red rule from each of its two signals with merge settings off; a second red result; under a halt, a red rollup that waits and, once the review wait has elapsed, goes to batch review with reason `review-wait-elapsed` with no auto-tier run; a fix-up run starting for a pull request with a review marker; a review-finding fix-up run starting when GitHub's head differs from the pinned head; a failed start-marker write launching nothing; a start marker that lands though its write reported a failure ending `not-launched`, with no label, the claim live, the breaker unchanged and the CI fix-up not used up; a lost run's `crashed` end marker; the budget measured from `claimed_at` and the stall window from `started_at`; a fix-up `timed-out` giving `lair:failed`; no budget left giving `budget-exhausted`; fix-up park routes, each stopped before its end marker and finished by the next tick; each fix-up run outcome; a stale GitHub head after a fix-up push; a fix-up end under an ended claim writing only the end marker.
    - #611: the breaker counting `failed`, `crashed`, `stalled` and `timed-out`, resetting on `complete` under a live claim, and neither counting nor resetting on `blocked`, `no-pr`, `invalid-result`, `not-launched`, a park, an exit, `budget-exhausted` or a fix-up end under an ended claim.
    - #606: under the release-train mode, with no bump input the pull request cannot change, `TIER=review:version-unreadable`.
- **No merge by a strain, and leased pushes,** are tested in the strain contract suite that #630 designs and #604 builds: a push by another process during a run makes the run's next push fail, and the interactive push path's cases are unchanged.
- **Structural merge-path check, in the policy suite:** one negative case each for `gh pr merge`, a `pulls/<n>/merge` REST path, `mergePullRequest`, `enqueuePullRequest` and `--auto` on a merge line, placed in a file under `plugin/` other than `merge-approved.sh`, each of which the check must flag; and a call of `merge-approved.sh` from a third place.
- **Registration in `tools/validate.sh`, for each new suite:**
  - a constant: `SUITE_TEST_AUTO_TIER='test_auto_tier.sh'` and `SUITE_TEST_LAIR_MERGE_LANE='test_lair_merge_lane.sh'`;
  - an entry in `ALL_SUITES` and in `KNOWN_SUITES`;
  - a `map_path` rule routing the script, its test and its fixture directory to the suite; `plugin/skills/lair/**` and every `plugin/skills/_shared/` library the Lair scripts, the merge script or the poll script source route to both new suites; the merge-lane rule also routes `merge-approved.sh` and `pr-change-detect-poll.sh`, whose output contracts that test reads; `.github/lair.json` already routes to the full suite;
  - a `self_test` probe: `tests/auto-tier/README.md` and `tests/lair-merge-lane/README.md`.

  `tools/test_validate_suites.sh` runs with the new entries. Both `auto-tier.sh` and the merge-lane step script are also enrolled in the bootstrap table of `tools/test_script_bootstrap.sh`, whose closure check fails until they are; `map_path` already routes every `plugin/**/*.sh` to that suite. A closure check in the merge-lane suite fails when a Lair script, the merge script or the poll script sources a `plugin/skills/_shared/` library that `map_path` does not route to both new suites.

## Seam order

The design changes these slices. The ADRs each one touches were confirmed by reading them. #607 is unchanged.

| Slice | Change | ADRs |
| --- | --- | --- |
| #604 | Strain settings keep any merge key from taking effect in a strain, as #630 chooses, and keep a strain from writing anything outside its worktree and the shared object and ref store; every strain push is leased, through a strain-only mode of `push-branch.sh` and `open-plan-pr` that leaves the interactive push path unchanged; the result gains `local_review_head`; the path of #630's result script joins `.github/lair.json` when it lies outside the listed entries. | ADR-0045 decisions 4 and 5; ADR-0044 decision 17; ADR-0017 decisions 1 and 2; ADR-0010, amendment 2026-10-31; ADR-0037, decision 5 and Workflow outline step 8; ADR-0040 decision 2; ADR-0042 |
| #605 | The Lair's script directory; the merge-lane step with its lane order, late group, fail-closed reads, child timeout with `merge-approved.sh` exempt, one merge per tick, merge-queue reads, `lair:review` label holds, merge environment and credential check, and git and tool hardening with the per-tick repository check; the settle check; the auto-tier script, its schema, its release-train fail-closed rule and this repository's list; the expected-head argument; the routing table; the merge settings source; the write order for the lane's routes; the Tier A merge bullet in `decision-autonomy.md`, the `safety-auto-merge-after-approval.json` update and the structural check; and their tests, other than those listed under #608, #610, #611 and #606. | ADR-0044 decisions 1, 4, 6, 9, 10, 14, 15, 16 and 17 to 20; ADR-0045 decisions 2, 10, 12, 13, 14, 16 and 17; ADR-0043 decision 2; ADR-0042; ADR-0029, Findings; ADR-0026; ADR-0020, amendment 2026-09-29 |
| #606 | Under the release-train mode the auto tier fails closed with `version-unreadable` until #606 supplies a bump input the pull request cannot change; #606 makes the auto-tier script detect the mode and adds its test case. | ADR-0045 decisions 12 and 15 |
| #608 | The tick handles run ends, then calls the merge-lane step under the lock, and reads the halt file before fix-up dispatch. It reads each result from the run's worktree and removes no run's worktree or result file until its end marker is written; it writes the run-end marker, with `pr` for every result that names one, every delivery outcome and the outcome mapping, labels first and the marker last, retrying failed result-check reads and a stale GitHub head. It keeps the lane-holder set, closed pull requests included until merged, and fails admission closed on it. At start it reads the Lair's own login, resolves the tools under the fixed `PATH`, and refuses to start on a `$HOME/.jq` or a `gh` `http_unix_socket`. Its start-up sweep ends lost runs only when no unprocessed result exists. It owns the per-issue budget and the stall window. It adds the halt, start-check, result recording, delivery run end, lane-holder and admission test cases. | ADR-0045 decisions 2, 5, 12, 16 and 17; ADR-0044 decision 17 |
| #609 | Park counting and answer handling include fix-up parks, whose pull request the Lair has converted to a draft. | ADR-0045 decisions 7, 11, 12 and 16 |
| #610 | Fix-up runs gain start and end markers; the start preconditions (a live claim, no run in flight, budget left, no halt or tripped breaker); the `not-launched` end, with the worktree as launch evidence; the CI-red rule from its two signals; the per-issue budget and the stall window from `started_at`; the `budget-exhausted` route; the fix-up outcome mapping and park route, the end marker last; and end-marker-only handling under an ended claim. Its trigger owns the bound on review-finding runs. It adds the fix-up test cases. | ADR-0045 decisions 2, 5, 7, 12, 13, 16 and 17; ADR-0040 decision 2 |
| #611 | The breaker reads outcomes from the run-end and fix-up end markers and counts only `failed`, `crashed`, `stalled` and `timed-out`; a `complete` end under a live claim resets it, and every other outcome and route, `not-launched` included, and any fix-up end under an ended claim, neither counts nor resets; the digest notes `--admin` merges. It adds the breaker test cases. | ADR-0045 decisions 14 and 17 |
| #612 | Each parallel pull request keeps its own pinned head, settle cache and auto-tier run against the current trunk, with one merge call per tick in the rotating lane order. | ADR-0045 decisions 12 and 15; ADR-0044 decision 19 |

## Open questions

None

## Amendments

This design was written with ADR-0044's amendment of 2026-11-21 (decisions 17 to 20) and the user's Tier A answers of the same date. Later changes to this design are appended here as dated entries.

2026-11-21: Design review round 1 returned 32 findings, M1-A1 to M1-A15 and M1-B1 to M1-B17. Each is fixed in this design or in ADR-0044's amendment of the same date, as the [merge-lane review record](merge-lane-review-record.md) lists under Round 1, and the run's calls R1 to R13 were listed under Decided for you.

2026-11-21: Design review round 2 returned 26 findings, M2-A1 to M2-A11 and M2-B1 to M2-B15. Each is fixed or recorded in this design or in ADR-0044's amendment of the same date, as the merge-lane review record lists under Round 2. The run's calls R14 to R21 are under Decided for you. R16 reverts the round-1 rule that a review marker stops a fix-up run, and R21 withdraws R13 from the veto list, because the PRD change it named derives from the Tier A answers Q1 and Q3.

2026-11-21: Design review round 3 returned 24 findings, M3-A1 to M3-A11 and M3-B1 to M3-B13. Each is fixed or recorded in this design, as the merge-lane review record lists under Round 3. The run's calls R22 to R31 are under Decided for you. Round 3 removed parts rather than adding them where it could: the merge-pending mark (GitHub's merge-queue state replaces it), the result cache (the kept result file replaces it), the applied marker and the walk over unfinished writes (the route's last marker replaces them), and the fix-up start precondition on GitHub's head. R12 is withdrawn from the veto list, because the Tier A bullet change it named derives from Tier A answer Q1 (Changes to shared documents, item 5).
