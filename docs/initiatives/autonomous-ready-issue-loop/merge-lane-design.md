# Solution design: Lair merge lane

This is the solution design for the Lair's merge lane, issue #631, a sub-issue of epic #603. It links the [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md), [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md) and the [solution design](solution-design.md) rather than restating them. It cites them as "ADR-0045 decision N" and "ADR-0044 decision N"; decisions 17 to 20 are those of ADR-0044's 2026-11-21 amendment. Its design review is recorded in the [merge-lane review record](merge-lane-review-record.md). For the merge lane, this design supersedes these parts of solution-design.md:

- the Component "Merge lane and auto tier";
- the GitHub-record, park and halt side of the Component "Post-PR remediation strains", and the start of a fix-up run for failed checks (the CI-red rule); what starts a fix-up run on review findings stays there, with #610;
- the Contract "Auto-tier script result";
- in the Contract "Claim marker comment", its last sentence, "At run end the Lair adds `outcome` and `ended_at`.", and the matching run-end update in the State and ownership row "Claim marker comment": a run end goes into the run-end marker (Markers the merge lane writes);
- the merge-settings part of the Trust boundaries channel list ("the halt file and the merge settings on the user's own machine");
- in Lifecycle: the `lair:handoff`, `lair:failed` and `lair:review` label bullets, for the run ends and exits this design names; stage 1's merge step; stage 3 whole; stage 4's merge stop; and the draft, closed-unmerged and claim-withdrawn exits, which solution-design.md does not have;
- the Failure modes rows "Merge refused", "CI red" and "Issue edited after claim";
- the Decisions "Merges only through `merge-approved.sh` and its gates", "A red CI result gets one remediation strain, then `lair:review`" and "An issue edited after claim is not merged and goes to `lair:review`".

Every other part of solution-design.md stands.

## Context and code truth

The merge lane builds on this code, as it stands on trunk:

- `plugin/skills/github-review-loop/scripts/merge-approved.sh` takes exactly five arguments: owner, repo, pull request number, reviewer filter and self login. Any other count is `MERGE_ERROR=bad-arguments`. It reads `HIVEMIND_AUTO_MERGE`, `HIVEMIND_AUTO_MERGE_ADMIN` and `HIVEMIND_PR_REVIEWERS` from its environment. It prints exactly one line, a `MERGE=` line with exit 0 or a `MERGE_ERROR=` line with exit 1, and nothing on stderr.
- The script reads the PR once, then runs gates 1 to 7 in order: not open, draft, no settled evidence (`has_settled_evidence`), an open thread (`is_settled_thread`), no check rollup, pending (`PENDING` or `EXPECTED`), failed (`FAILURE` or `ERROR`). Only then does it call `gh pr merge` with `--match-head-commit` set to the head of that read. A read past its page is `MERGE_ERROR=read-incomplete`.
- That one read is `PR_QUERY` (lines 247 to 282). It holds the pull request's state, draft flag, head, merge state, check rollup, reviews, reactions and review threads. It holds no base, repository, author or branch name, so the script judges none of them. `--match-head-commit` pins only the head.
- `MERGE=wait:head-moved` already exists. Today it prints only after a refused plain merge, when the re-read shows a different head. The script has no way to be told which head the caller expects.
- A merge call that exits 0 is followed by a confirm read. `MERGE=merged` and `MERGE=merged-admin` print only when that read shows `MERGED`, else `MERGE=wait:merge-pending` (ADR-0044 decision 16).
- `tools/test_merge_approved.sh` runs the script against a PATH-shim `gh` that serves canned GraphQL bodies and logs every call. After the cases it checks five properties over every case, among them that every merge call carries `--match-head-commit` equal to the head of the read before it. Its case `args:six` passes a sixth argument, `extra`, and expects `MERGE_ERROR=bad-arguments`.
- `plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh` has three modes. `--snapshot <arm-kind>` prints one `BASELINE=<seed>` line, or `SNAPSHOT_ERROR`. `--check` compares one capture against a seed and prints one of `UNCHANGED`, `CHANGED`, `CI_FAILED`, `REVIEWER_APPROVED`, `STATE=MERGED`, `STATE=CLOSED` or `CHECK_ERROR`. It never sleeps, never reads the deadline and never prints `REVIEWER_SETTLED`. Only poll mode judges a settled approval, with `SETTLE_SECONDS=600` on its loop-top clock. Both one-shot modes still validate the window and interval arguments as integers.
- The seed carries its arm kind. Under an `initial` seed an approval already present fires `REVIEWER_APPROVED`. Under a `re-arm` seed the approval edge counts as observed and does not fire again.
- `plugin/skills/github-review-loop/scripts/reviewer-identity.jq` holds `has_settled_evidence` and `is_settled_thread`. They are the only settled-evidence and settled-thread verdicts. The poll and the merge script both call them (ADR-0044 decision 14).
- The merge rule in `plugin/skills/github-review-loop/SKILL.md` runs `merge-approved.sh` with five arguments, once, only after an approval return whose QUIET-EXIT CHECK reports `UNCHANGED`, and routes its line for the watch alone. The skill's `allowed-tools` grant is `Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/merge-approved.sh" *)`. Its `max_watch_duration` default is `3600` seconds, recorded in ADR-0029's Findings.
- `plugin/governance/decision-autonomy.md` Tier A holds the bullet "every merge recommendation; the human merges, except the review watch's opt-in merge after a reviewer approval, per `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/SKILL.md`". `tests/policy/safety-auto-merge-after-approval.json` pins that bullet and the watch's merge rule. Its residual (4) says no presence pin can find a new merge path; that needs a structural check.
- The standard-delivery local review gate is in `plugin/workflow-src/standard-delivery/gates.js` and `review.js`. `configuredGateIds` requires local review only when the launch's `local_review` is true and no review returned `skipped` (SD-31, SD-86). A skipped review still opens a ready pull request, with a warning line (SD-86). A loop cap opens a draft whose local review did not hold (SD-83). The run's result names the pull request and its `head_ref_oid` (SD-47). The run state knows whether the gate held; nothing writes that outside the run today.
- `pr-feedback-remediation` runs validation as its one gate and no local review (`plugin/workflow-src/pr-feedback-remediation/tail.js` `gateIds()`, contract row PFR-23).
- `tools/validate.sh` registers each behavioural suite in four places: a `SUITE_*` constant, the `ALL_SUITES` and `KNOWN_SUITES` lists, a path-to-suite rule in `map_path`, and a probe path in the `self_test` map. `test_merge_approved.sh` is registered in all four. `map_path` routes `pr-change-detect-poll.sh` to `test_change_detect_poll.sh` only.
- No Lair script exists on trunk. Nothing under `plugin/` reads a merge setting from a settings file; every reader takes it from the environment.

## Components

### Merge-lane step of the tick

Built by #605, called by #608's tick under the single-instance lock. #605 fixes the Lair's script directory, `plugin/skills/lair/scripts/`, and #608 builds the tick there.

Each tick the step works the lane set (Lair pull request, under Contracts and seams). For each pull request in it, the step runs these checks in order and stops at the first that routes:

1. **Markers.** The step reads every page of the claimed issue's comments and keeps the markers that pass #632's rule. A failed or incomplete read means nothing more for this pull request this tick. The step then finishes any write sequence an earlier tick left unfinished (Write order). For a pull request whose claim has a terminal outcome, the step stops here.
2. **State.** The step reads the pull request (state, draft flag, head and the head's check rollup) and the claimed issue (state and labels). Merged goes to the merged exit; closed goes to the closed-unmerged exit. An issue that is closed, or that no longer carries `lair:claimed`, goes to the claim-withdrawn exit (Lifecycle).
3. **Held by review.** A review marker exists for this pull request under this claim. The Lair never merges it again; the step skips it. The `lair:review` label is not read.
4. **Fix-up in flight.** A fix-up run on this pull request has a start marker and no end marker. The step skips it, because the run will move the head. The run's budget, stall and crash handling are under Fix-up runs.
5. **Draft.** The pull request is a draft. The step routes it to the draft exit.
6. **Pinned head.** The pinned head (Contracts and seams) must equal GitHub's head on step 2's read. Otherwise the pull request goes to batch review with reason `unrecorded-head`. This step compares only the head.
7. **CI red.** The check rollup on step 2's read is `FAILURE` or `ERROR`. The step applies the CI-red rule (Fix-up runs). It reads no merge setting, and neither the approval nor the gate order plays a part.
8. **Review wait.** When 3600 seconds have passed since the `ended_at` of the run that recorded the pinned head, the pull request goes to batch review with reason `review-wait-elapsed`.
9. **Auto tier.** The step resolves the trunk commit and fetches it and the pinned head (Git and tool reads), then runs the auto-tier script on them. Only exactly one `TIER=auto` line with exit 0 goes on to the late group. Exactly one `TIER=review:<code>[,<code>...]` line with exit 0, each code one of the five under Auto-tier script, sends the pull request to batch review with those codes. Any other output or exit status, a killed script or a failed fetch is `TIER_ERROR`: no merge this tick.

When step 2's read fails or is incomplete, the step runs only steps 3, 4 and 8, which need only the markers and the clock, and then stops. Any other failed or incomplete read, in steps 2 to 9 or in the late group, means no merge and no label change for this pull request this tick.

Steps 10 to 15 are the late group. They are the last tick work before the merge call, in this order, and nothing but step 16 follows them:

10. **Merge settings.** The step reads the two user settings files (Merge settings source). A file that does not parse means no merge this tick.
11. **Credential login.** The step runs `gh api user` in the merge environment (Merge environment). A login other than the Lair's own, or a failed read, means no merge this tick; the queue report names `credential-mismatch` or the failed read. No label changes.
12. **Trunk tip.** The step resolves the trunk commit again. When it differs from step 9's, the step fetches the new commit and runs the auto tier again on it, routed as step 9 routes.
13. **Identity.** The step reads the pull request once more and reruns the Lair pull request checks (Contracts and seams) on that read, every check other than the head: same repository, not a fork, trunk base, the Lair's own login as author, and the recorded branch. A base retargeted away from the trunk, or any other mismatch, sends the pull request to batch review with reason `identity-changed`.
14. **Issue edit.** The step recomputes `body_sha256` of the claimed issue's title and body and compares it with the claim marker's. A difference sends the pull request to batch review with reason `issue-edited` (Q8). The check runs before every merge attempt.
15. **Settle check.** See below. Not settled means no merge this tick.
16. **Merge.** The step runs `merge-approved.sh` with six arguments in the merge environment and routes its one line by the routing table under Contracts and seams.

The tick makes at most one merge call per tick. Once step 16 has run for one pull request, whatever its line, the step skips steps 10 to 16 for every other pull request that tick; steps 1 to 9 still run for them.

Every child process of the step runs under a timeout of 300 seconds: `git`, `gh`, the auto-tier script, the poll script and the merge script. A killed process counts as a failed read, a killed auto-tier script as `TIER_ERROR`, and a killed merge run as `MERGE_ERROR`. The next tick's state read shows whether a killed merge run merged.

A check whose input can change after the tick reads it belongs in the late group. Steps 2 and 5 read state and draft only to route exits; `merge-approved.sh` judges both again on its own read. Step 7's rollup read can only start the CI-red rule, never a merge.

**Known limit: the merge gap.** Decided by the run under `plugin/governance/decision-autonomy.md` (Review Calls), on a local-review finding, 2026-11-21. The merge call pins one input, the head. Every merge condition is exactly one of five kinds, each with its control:

- **Pinned.** The head: every merge call carries `--match-head-commit` with the pinned head (ADR-0044 decision 19).
- **Derived from git objects.** The auto tier: it reads only commits, which do not change, at the pinned head and the trunk commit the late group resolved.
- **Judged by `merge-approved.sh` on its own read.** State, draft, approval, threads, checks and conflicts. The gap between that read and the merge call is ADR-0044 decision 15.
- **Read by the tick in the late group.** The merge settings; the credential login; the trunk tip; the Lair pull request checks, the base included; the issue text; the settle snapshot.
- **Lair-owned state.** The markers, which count only under #632's rule, and the settle cache and the Lair's git repository, which only the Lair writes, under the single-instance lock.

The late-group kind can change in the seconds between its read and the merge call. No check closes that. GitHub offers no merge call that pins those inputs. Moving a check into `merge-approved.sh`, as expected base, author or branch arguments, a settle digest or the issue hash, only narrows the window and adds script surface, and the issue text and the settle snapshot stay outside what the merge call pins. A finding that names a late-group input changing in that gap contests this decision and is a repeat. A finding that shows a merge condition fitting no kind, or a tick read placed after the late group, is new.

Under parallel strains (#612) the step runs the same way for each pull request, with at most one merge call per tick.

### Settle check

Built by #605. It equals ADR-0044 decision 1 (decision 18, Q2). It uses `pr-change-detect-poll.sh` unchanged, in the merge environment, under the child timeout. A result counts only when the output is exactly one line of the form named below and the exit status is 0; anything else is treated as the error case of its mode.

- When the cache has no entry for this pull request and pinned head, the step takes a snapshot with `--snapshot re-arm`. It saves the seed with the pinned head and `quiet_since` set to now only from exactly one `BASELINE=` line with a non-empty value and exit 0. `SNAPSHOT_ERROR`, any other output, a non-zero exit or a timeout saves nothing. Either way the check is not settled this tick. The arm kind is `re-arm` so that an approval already present does not fire `REVIEWER_APPROVED` on every tick.
- Otherwise it runs `--check` against the saved seed:
  - `UNCHANGED` with now minus `quiet_since` at least 600 seconds: settled.
  - `UNCHANGED` with fewer: not settled.
  - `CHANGED`, `CI_FAILED` or `REVIEWER_APPROVED`: the step first deletes the cache entry, then takes a new snapshot as for a missing entry. A failed snapshot leaves no entry, so the next tick starts a new quiet period and no older seed is used. Not settled. `CI_FAILED` also applies the CI-red rule.
  - `STATE=MERGED` or `STATE=CLOSED`: not settled; the next tick's state read routes the pull request.
  - `CHECK_ERROR`, any other output, more than one line, a non-zero exit or a timeout: not settled, and the cache entry is kept.
- The window and interval arguments are `3600` and `60`. The one-shot modes validate them and use neither. The reviewer filter is `automated`.

The approval and thread parts of decision 1 are not judged here. `merge-approved.sh` judges them on its own read through `has_settled_evidence` and `is_settled_thread`, with a read past its page failing closed. A lost or unreadable cache only delays a merge: the next tick takes a new snapshot, and the quiet period starts again.

### Auto-tier script

Built by #605 as one script, `plugin/skills/lair/scripts/auto-tier.sh`. It has no model in it and reads only git objects in the git directory the tick passes, and the tick's arguments: that directory, the trunk commit, the pinned head, the local-review head and the fix-up heads. It and the merge-lane step use ADR-0020's fail-closed bootstrap forms (amendment 2026-09-29). The ADR-0044 gates are left to `merge-approved.sh`. Its conditions (Q5, Q6):

- **Protected paths.** The changed paths are `git diff --name-only --no-renames -z` from the merge base to the pinned head, so a rename lists both sides. The protected-path list is read from the trunk commit, never from the pull request head. It is `.github/lair.json`, key `protected_paths`. An entry has one of three forms, and there are no globs:
  - an exact path;
  - a directory prefix ending in `/`;
  - a file name written `**/<name>`, which matches that name at any depth. It is the only form that holds `*`.
- **The floor.** A fixed floor in the script applies whatever the list says, and no list entry removes it: the `.github/` directory at the root; any path with a segment named `.claude`; and any file named `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.gitmodules` or `.gitattributes`, at any depth. The list file itself sits under the floor. Every comparison, for the floor and the list, ignores ASCII case.
- **Bump.** The version files are named in the same trunk file, key `version_files`. The script reads each value at the merge base and at the pinned head as `MAJOR.MINOR.PATCH`. A rise in `MAJOR` is a major bump. A file or value that is missing, unparseable or lower at the head is unreadable.
- **Local review.** The tick passes the claim's recorded local-review head and the heads the Lair's fix-up runs recorded since that claim. The condition holds when the pinned head equals the local-review head, or the local-review head is not null and the pinned head is a fix-up head.

`.github/lair.json` has a strict schema. It is a JSON object with exactly two keys, both required arrays:

- `protected_paths`: each entry a non-empty string in one of the three forms, with no leading `/`, no empty, `.` or `..` segment other than a prefix's trailing `/`, and no `*` outside the `**/` form.
- `version_files`: each entry an object with exactly two keys, `path`, an exact path in the same form, and `key`, a non-empty string naming a top-level key of that file.

A missing or unparseable file, or a top-level value that is not such an object, gives `protected-list-unreadable` and `version-unreadable`. A `protected_paths` value that is missing, not an array, or holds any malformed entry gives `protected-list-unreadable`. The same for `version_files` gives `version-unreadable`. An empty array, `[]`, is the only way to declare no entries. So no pull request merges until a well-formed file exists.

The script prints one line:

- `TIER=auto`, exit 0;
- `TIER=review:<code>[,<code>...]`, exit 0, with every failing code, in this order: `protected-list-unreadable`, `protected-path`, `version-unreadable`, `major-bump`, `local-review-missing`;
- `TIER_ERROR=<reason>`, exit 1, for bad arguments, an unusable git directory, a commit that is not present, or no merge base.

### Fix-up runs

A fix-up run is an unattended `pr-feedback-remediation` run on the pull request (ADR-0040 decision 2, ADR-0045 decision 13). What starts a fix-up run on review findings is #610's rule (ADR-0045 decision 13, the PRD's Post-PR feedback criterion). This design fixes what the merge lane needs from every fix-up run (Q9, Q10):

- Each run has a start marker and an end marker on the claimed issue, with the fields under Contracts and seams. The Lair writes the start marker before it launches the run, and launches nothing when that write fails; the trigger is tried again next tick.
- No fix-up run starts for a pull request that is not a Lair pull request, that has a review marker, or that already has a fix-up run in flight. #610's trigger obeys this rule.
- No fix-up run starts while the halt file or the circuit breaker holds. Runs already started finish.
- Each run's wall-clock budget and stall window, #608's values, are measured from its start marker's `started_at`. A tick or the start-up sweep that finds a start marker with no end marker and no live session writes the end marker with outcome `crashed`. A run over its budget ends with outcome `timed-out`, and a stalled run with outcome `stalled`.
- The run-end handling is under Lifecycle.

**The CI-red rule.** It fires from the first of three signals: step 7's rollup read on the pinned head, the settle check's `CI_FAILED`, or `MERGE=wait:checks-failed`. It does not depend on the merge settings, the approval or the gate order. With no `fixup-checks` start marker for this pull request under this claim, it starts one fix-up run for failed checks, unless the halt file, the breaker or a review marker stops it; then the pull request waits, and the review wait bounds it. With one already recorded, the pull request goes to batch review with reason `checks-failed`. Q9's rule is unchanged: one fix-up run for failed checks, then batch review.

**Seam note for #610.** The merge lane does not bound fix-up runs on review findings. Each fix-up run records a new head, and the review wait restarts from its `ended_at`. A reviewer that raises a new finding after every run keeps the pull request cycling with no end. Bounding that is #610's, in its trigger, not a merge-lane rule.

## State and ownership

GitHub stays authoritative (ADR-0045 decision 2). This table adds the merge lane's state to solution-design.md's table:

| State | Writer | Readers | Authoritative |
| --- | --- | --- | --- |
| Run-end marker on the claimed issue | Lair, after checking the result against GitHub | Lair, user | yes |
| Fix-up start and end markers on the claimed issue | Lair | Lair, user | yes |
| Review marker on the claimed issue | Lair | Lair, user | yes; the `lair:review` labels only show it |
| Exit and applied markers on the claimed issue | Lair | Lair, user | yes |
| `lair:review` label on the issue and the pull request | Lair | user; admission (PRD Admission) | no; the review marker is |
| Protected-path list and version files, `.github/lair.json` at the trunk commit | user, through a reviewed pull request | auto-tier script | yes, at that commit |
| Merge settings in `.claude/settings.local.json` and `~/.claude/settings.json` | user | Lair, each tick | no; a control input |
| Settle cache: seed, pinned head, `quiet_since`, merge-pending flag, per pull request | Lair | Lair | no; losing it only delays a merge |
| Lair git repository: a bare repository in the Lair's cache directory | Lair | auto-tier script | no; rebuilt by fetching |

The pinned head, the local-review proof and the CI fix-up count are all recomputed from markers each tick, never kept only in the cache.

## Contracts and seams

Fields and seams only. Each slice builds the code.

### Lair pull request

The Lair records a pull request in the run-end marker of the claimed issue (Q7). It records one only from a `complete` delivery result, and only after these hold on a fresh GitHub read:

- the result's `pr` exists in the same repository, not a fork;
- its base is the trunk;
- its author is the Lair's own login;
- its head branch equals the result's `branch`;
- its head commit equals the result's `head`.

Any failure makes the result invalid (Lifecycle). These checks are one function, called by the step that records a result and again by the merge-lane step's late group, which leaves out the head because the merge call pins it, so there is no second list.

A recorded pull request is a Lair pull request while all of these hold: its claim has no terminal outcome, the claimed issue is open, and the issue carries `lair:claimed`. A claim's terminal outcome is a run-end marker whose outcome is not `complete`, a fix-up end marker whose outcome is `parked`, or an exit marker. The Lair merges only a Lair pull request, and never merges, labels or holds the lane for a pull request it did not record.

The lane set, which the merge-lane step works each tick, is every pull request recorded under a claim with no terminal outcome, open or not, plus every recorded pull request whose claimed issue has a marker with unfinished writes. A recorded pull request that is open and not a draft holds the lane until it is merged or closed, whether or not it is still a Lair pull request (ADR-0045 decision 12).

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
- A file that does not parse as JSON, an `env` that is not an object, or one of the three values that is not a string means no merge this tick. The queue report names the file.
- The tick reads no other settings source. The committed `.claude/settings.json`, `CLAUDE_CONFIG_DIR`, managed settings and every other settings file never reach it, and the merge keys are never taken from the Lair's own environment. The queue report names the files read and whether each was present.

### Merge environment

The step runs the merge script, the poll script and the `gh api user` call in the Lair's own environment, minus every `HIVEMIND_*` key, plus each of the three keys above that the settings files set. So the `gh` authentication the Lair runs under reaches `gh` unchanged, whether it comes from `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `GH_HOST`, `GH_CONFIG_DIR`, `XDG_CONFIG_HOME` or the D-Bus session variables the keyring needs, and no merge key comes from the environment (Q4). `PATH` is the tick's fixed `PATH` (Git and tool reads).

The environment alone does not prove the account. Step 11 checks, in this same environment, that `gh api user` reports the Lair's own login, read once when the Lair starts (#608), before every merge call. The merge script gets that login as its fifth argument.

### Git and tool reads

- The tick resolves `bash`, `git`, `gh` and `jq` to absolute paths once, when the Lair starts, and calls them by those paths. It sets its own `PATH`, and its children's, to a fixed system list, `/usr/bin:/bin`, followed by the directories of those four paths.
- The tick's git reads run in a bare repository the Lair owns in its cache directory, never in the main checkout's git directory, so no config, hook or ref of the main checkout is read. The Lair creates it at start and rebuilds it by fetching when it is lost.
- Every git call sets `GIT_CONFIG_NOSYSTEM=1` and `GIT_CONFIG_GLOBAL=/dev/null` and passes `-c core.hooksPath=/dev/null`. It fetches from the repository's URL fixed at Lair start, never a named remote. Its credentials come only from `gh auth git-credential`, named by absolute path on the command line.
- The trunk commit is the id that `git ls-remote` returns for the trunk branch from that URL in this tick. The tick fetches that id and the pull request's `refs/pull/<n>/head`, then checks that both the trunk commit and the pinned head are present. No local ref, `FETCH_HEAD` included, names either commit.

### Routing table

Decision 20. The tick routes the script's output as follows. The skill's routing in `SKILL.md` stays bound to the watch. Batch review means a review marker, then the `lair:review` label on the issue and on the pull request, with the reason code (Write order).

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
| `MERGE=wait:checks-failed` | The CI-red rule, which step 7 and the settle check also apply. |
| `MERGE=merged` | The merged exit. |
| `MERGE=merged-admin` | The merged exit; the digest notes the `--admin` merge. |
| `MERGE=wait:head-moved` | No merge. The next tick's pinned-head check routes the pull request. |
| `MERGE=skipped:conflicts` | Batch review, reason `conflicts`. |
| `MERGE=skipped:blocked` | Batch review, reason `merge-blocked`. |
| `MERGE=skipped:refused` | Batch review, reason `merge-refused`. |
| `MERGE=wait:merge-pending` | The cache marks the head merge-pending. No merge call runs for that head while the mark stands. The next tick's state read routes the pull request, and the review wait bounds it. |
| `MERGE_ERROR=<reason>` with exit 1 | No change. Retried next tick; the queue report names the reason; the review wait bounds it. |
| A non-zero exit with any other output, or a run killed by the child timeout | Treated as `MERGE_ERROR`. The next tick's state read shows whether it merged. |
| No line, more than one line, or a line not in this table | Treated as `MERGE_ERROR`. |

### Write order

A route that makes more than one write makes them in this order: its markers first, then each label change or pull request change, then one applied marker naming the comment ids of the route's markers. Every write is idempotent: adding a label already present, removing one already absent, or converting a draft to a draft changes nothing. A route first looks for its markers under this claim and never writes a second one. A route that makes only one write, such as a fix-up start marker or the run-end marker of a recorded non-draft pull request, writes no applied marker. A marker of a multi-write route with no applied marker is finished by step 1 of each later tick, until the applied marker is written. A failed write leaves the rest for the next tick.

### Markers the merge lane writes

Each marker is a machine-readable comment on the claimed issue, under #632's author and nonce rule (Assumptions about #632). From #632's claim marker the merge lane reads `claim_nonce`, `claimed_at` and `body_sha256`, and it writes nothing to it.

- **Run-end marker.** Written when a delivery run ends: `claim_nonce`, `outcome` and `ended_at`. For a `complete` result that passed the Lair pull request checks it also holds `pr`, `branch`, `head` and `local_review_head`. A parked run's draft is not recorded here; it belongs to the park (#609, ADR-0045 decision 12). #608's start-up sweep and #611's breaker read `outcome` here.
- **Fix-up start marker.** `kind` (`fixup-checks` or `fixup-review`), `run_nonce`, `claim_nonce`, `pr`, `start_head`, `started_at`.
- **Fix-up end marker.** `run_nonce`, `claim_nonce`, `outcome` (`complete`, `parked`, `blocked`, `failed`, `crashed`, `stalled`, `timed-out` or `invalid-result`), `ended_at`, and `head` when recorded, or the park record when parked.
- **Review marker.** `claim_nonce`, `pr`, `head`, `reasons` (codes only, no issue or pull request text), `at`.
- **Exit marker.** `claim_nonce`, `pr`, `exit` (`merged`, `pr-closed` or `claim-withdrawn`), `at`.
- **Applied marker.** `applies`, the comment ids of the markers whose writes it completes, and `at`.

### Assumptions about #630

- **No strain can write what the tick reads or runs.** No strain process can write: the two user settings files; the Lair's cache directory, its git repository included; the main checkout's git common directory, its config, hooks and refs; the directories on the tick's `PATH`; or the plugin's script directory. A worktree strain must write objects and refs to the shared common directory, so the hooks and config need a carve-out or a per-strain clone. That choice is #630's. The tick's own hardening (Git and tool reads) does not rely on this assumption.
- **No merge key takes effect in a strain.** ADR-0045 decision 4 has the strain settings carry no `HIVEMIND_AUTO_MERGE*` key. Since Claude Code 2.1.211 a worktree session also reads the main checkout's `.claude/settings.local.json` (ADR-0010, amendment 2026-10-31), and an omitted key overrides nothing inherited (A3-1). How #630 keeps a strain from inheriting the keys, for example with empty-string keys, and any ADR-0045 or PRD change that needs, are #630's.
- The result schema carries `local_review_head`: a commit, or null when local review was not configured, was skipped, or did not hold. #630's fixed result script writes it from the run's own state, never from a value the model passes.
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

This section replaces the merge-settings part of solution-design.md's channel list. Merge settings are a channel only through the user's own files on the Lair's machine: `.claude/settings.local.json` at the main checkout and `~/.claude/settings.json`. Unsetting `HIVEMIND_AUTO_MERGE` there stops merges from the next tick (ADR-0045 decision 17).

- **The committed settings.** A pull request, a Lair one included, can change the committed `.claude/settings.json`, so the tick never reads it.
- **The Lair's environment.** None of its `HIVEMIND_*` keys reaches the merge or settle scripts; the merge keys come only from the two files. Its `gh` authentication does reach them, and step 11 checks the login it yields before every merge call.
- **The strain.** It cannot write what the tick reads or runs (an assumption about #630). Apart from that assumption, the tick's git reads use a Lair-owned repository with hooks and system and global config off and a fixed URL, take the trunk commit id from this tick's `ls-remote`, and call tools by absolute path.
- **The auto-tier inputs.** None of them comes from the pull request head:
  - the protected-path list is read at the trunk commit, and the floor is in the script;
  - the bump is computed from version-file values, not from commit messages, plan fields or labels;
  - the local-review proof is a head the Lair recorded from a result that passed its checks.
- **The pinned head.** Under the #632 assumption, a head no Lair run recorded never merges a Lair pull request.
- **The recorded identity.** The late group reruns the Lair pull request checks on a fresh read before every merge call. These checks bound which pull request the lane acts on. They do not bound a strain that reports false values about its own run: the strain pushed the head and opened the pull request it reports.
- **Residual: under-declared bump.** The bump check sees the version a pull request declares, not its real compatibility impact. A breaking change shipped with a minor bump passes it. The protected-path list is the control for compatibility surfaces.
- **Residual: a prompt-injected strain holds the user's rights** (ADR-0045 Residuals). Containment is #630's strain settings, not a separate identity. While a strain runs, for the merge lane this means:
  - it can merge its own pull request, or any other, outside the lane and the auto tier;
  - it can push to its branch after its result is recorded; the pinned head then differs, so the lane routes `unrecorded-head` and never merges that push;
  - it can report a false `local_review_head` if it subverts #630's fixed result script, and the auto tier then accepts an unreviewed head;
  - it can add or remove labels, `lair:review` and `lair:claimed` included; the review marker, not the label, holds a pull request, and a removed `lair:claimed` only stops merges;
  - it can post marker comments, which count only under #632's rule (Residual: marker forgery), and delete the Lair's own marker comments, a review marker included;
  - if #630's assumption fails, it can write the settings files the tick reads.

  The merge lane bounds none of these. Ground: ADR-0045 accepts this residual. Bounded impact: a merge is reverted (ADR-0045 decision 14).
- **Residual: marker forgery.** If #632's rule does not stop a process that holds the user's credentials and the nonces, a forged run-end or fix-up end marker can pin any head and record any local-review head, and a forged exit or applied marker can end a claim or skip its writes. The pinned head and the local-review proof then hold only as far as the forger allows.
- **Residual: the merge gap.** A late-group input can change in the seconds before the merge call (Known limit, Merge-lane step of the tick). The lane trusts repository writers and the user's machine, who can already merge, push or change the settings with no gap to time. The issue's author was admitted on the text as it stood, and an edit inside the gap equals an edit one second after the merge, which no check sees. A strain is not trusted: no strain run on the pull request is in flight when the late group runs, and what a strain can do with the user's rights is the residual above. Ground: outside the recorded threat model. Bounded impact: a merge is reverted (ADR-0045 decision 14).
- **Residual: the interactive watch.** A user who runs the interactive watch on a Lair pull request merges under ADR-0044 unchanged, outside the auto tier.

## Lifecycle

### Run outcome to labels

This table covers each run end the merge lane depends on, and replaces stage 1's merge step. Crash, stall and budget outcomes of a delivery run stay as in solution-design.md. A park from a delivery run stays with #609. Every route follows the Write order.

| Run end | Issue | Pull request | Breaker |
| --- | --- | --- | --- |
| Delivery `complete`, result checks pass, PR not a draft | stays `readiness:implementation` and `lair:claimed` | recorded; enters the merge lane and holds it | resets the count |
| Delivery `complete`, result checks pass, PR a draft | `lair:review` added | recorded; batch review, reason `draft`; does not hold the lane | resets the count |
| Delivery `complete` with `pr` null | `lair:failed`, outcome `no-pr` | none | counts |
| Delivery `blocked` | `lair:failed`, outcome `blocked` | left as it is, unrecorded | counts |
| Delivery `failed` | `lair:failed` | left as it is, unrecorded | counts |
| Invalid result: the schema check fails, or a Lair pull request check fails | `lair:failed`, outcome `invalid-result` | left as it is, unrecorded, never merged | counts |
| Fix-up `complete`, result checks pass | unchanged | new recorded head | resets the count |
| Fix-up `parked`, a `decision` or `fact` park | #609's park: answerable on the issue, `readiness:needs-decision`, `lair:claimed` removed; counts toward the third-park handoff | converted to a draft; the claim ends; does not hold the lane | does not count |
| Fix-up `parked`, an `approval` park or a third park | #609's park: `lair:handoff`; the issue leaves the factory | converted to a draft; the claim ends | does not count |
| Fix-up `failed`, `blocked`, `crashed`, `stalled` or `timed-out` | `lair:review` added | batch review, reason `fixup-failed` | counts |
| Fix-up invalid result | `lair:review` added | batch review, reason `fixup-failed` | counts |

The fix-up result checks are the Lair pull request checks against the pull request it ran on, plus the ancestor check under Contracts and seams. A fix-up park is a park of the claim under ADR-0045 decision 7, handled by #609 as a delivery run's park is. Its writes are the fix-up end marker with the park record, then the draft conversion, then #609's park writes, then the applied marker. The draft conversion makes the pull request belong to its parked issue, so it does not hold the lane (ADR-0045 decision 12), as a parked delivery run's draft does. A re-claim continues on the pushed branch (ADR-0045 decision 11).

### Exits

- **Merged.** GitHub shows the pull request `MERGED`, seen by the script's confirm read or a later tick's state read. The exit marker `merged` is written. Then the issue moves to `readiness:done`, and `lair:claimed` and `lair:review` are removed. The lane is freed.
- **Draft.** A Lair pull request that is a draft goes to batch review with reason `draft`. A draft does not hold the lane (ADR-0045 decision 12). The issue keeps its other labels until the user merges or closes the pull request, which ends at the merged or closed-unmerged exit.
- **Closed unmerged.** GitHub shows the pull request `CLOSED`. A review marker with reason `pr-closed` is written, so the Lair never merges the pull request if it is reopened, then the exit marker `pr-closed`. Then the issue gets `lair:handoff`, `lair:claimed` and `lair:review` are removed, and its readiness label is left as it is. It leaves the factory. The exit does not count toward the breaker. The lane is freed.
- **Claim withdrawn.** The issue is closed, or no longer carries `lair:claimed`, while the pull request is open. A review marker with reason `issue-closed` or `claim-removed` is written, then the exit marker `claim-withdrawn`, then `lair:review` goes on the issue and the pull request. The claim ends, and the Lair never merges the pull request. A non-draft one holds the lane until the user merges or closes it. The exit does not count toward the breaker.
- **Batch review.** The review marker is written, then `lair:review` goes on the issue and on the pull request. The issue's label keeps it out of admission (PRD Admission). The Lair never merges that pull request again. A non-draft one still holds the lane (ADR-0045 decision 12) until the user merges it, which ends at the merged exit, or closes it, which ends at the closed-unmerged exit.

### Stage 3: post-PR fix-up

This replaces solution-design.md's stage 3 whole. A trigger starts one fix-up run on the pull request: review findings by #610's rule, or the CI-red rule, within the rules under Fix-up runs. The Lair writes the start marker, then launches the run. The run pushes to the same branch and ends with a result, or the Lair finds it crashed, stalled or over budget. The Lair checks the result and writes the end marker, recording the new head or routing as the table above says. On a later tick the merge-lane step evaluates the pull request again from step 1, with a new settle snapshot for the new head.

### Stage 4: halt and circuit breaker

This replaces solution-design.md's stage 4 merge stop (Q10). The halt file and a tripped circuit breaker stop new claims and new fix-up runs. Runs in flight, delivery and fix-up alike, finish, and their results are handled; budget, stall and crash handling still apply. Merges continue. Unsetting `HIVEMIND_AUTO_MERGE` in the user's settings files stops merges from the next tick (ADR-0045 decision 17). Under a halt, a pull request whose checks fail waits. When the review wait elapses it goes to batch review.

## Existing-path coverage

- **The watch.** Its five-argument call of `merge-approved.sh`, its routing in `SKILL.md`, its settle period in poll mode and its grant are unchanged. The five-argument test cases in `tools/test_merge_approved.sh` stay as they are. The six-argument case `args:six`, whose sixth argument `extra` is malformed, now expects `MERGE_ERROR=bad-expected-head` (decision 19).
- **The Tier A merge rule.** `plugin/governance/decision-autonomy.md` keeps every merge recommendation with the human, except the review watch's merge. The Lair tick's merge is a second merge path. #605 changes that Tier A bullet to name it under ADR-0044 decision 17 (Changes to shared documents, item 5). #605 also updates `tests/policy/safety-auto-merge-after-approval.json` to pin the new bullet text and the merge-lane step's call of `merge-approved.sh`, and adds a structural check to the policy suite: `gh pr merge` appears only in `merge-approved.sh`, and only the watch's merge rule and the merge-lane step call that script.
- **The poll script.** `pr-change-detect-poll.sh` is not changed. The tick uses its existing `--snapshot` and `--check` modes.
- **`reviewer-identity.jq`.** Not changed. The merge script still calls it for the approval and thread gates.
- **Interactive auto-merge.** Unchanged. With `HIVEMIND_AUTO_MERGE` set in the committed settings, the interactive watch still merges as ADR-0044 states. That setting never reaches the tick.
- **Standard-delivery and pr-feedback-remediation.** Their gates are unchanged. The local-review head is read from the run's own state by #630's result script; neither workflow gains a gate.
- **Non-Lair pull requests.** The tick never considers them, so they are untouched.

## Failure modes

These rows replace "Merge refused", "CI red" and "Issue edited after claim" in solution-design.md and add the merge lane's own. The other rows there stand.

| Failure | Detection | Resulting state |
| --- | --- | --- |
| Merge refused | `MERGE=skipped:conflicts`, `skipped:blocked` or `skipped:refused`. | Batch review with that reason; the pull request holds the lane until the user acts. |
| CI red | The tick's rollup read on the pinned head shows `FAILURE` or `ERROR`, the settle check prints `CI_FAILED`, or the script prints `MERGE=wait:checks-failed`. | First time under this claim: one fix-up run for failed checks, unless the halt, the breaker or a review marker stops it, in which case the pull request waits. With a CI fix-up already recorded: batch review, reason `checks-failed`. The merge settings play no part. |
| Issue edited after claim | `body_sha256` of the current title and body differs from the claim marker's, checked before every merge attempt. | No merge. Batch review, reason `issue-edited`. The strain kept its captured text. |
| Failed or incomplete tick read | A GitHub read that fails or does not read every page; a failed `ls-remote` or fetch; a read killed by the child timeout. | No merge and no label change for that pull request this tick. When step 2's read fails, only the review wait may route, from the markers. The next tick retries. |
| Malformed settings file | A user settings file does not parse, or its `env` or a merge value has the wrong type. | No merge this tick. The queue report names the file. No label changes. |
| Credential mismatch | `gh api user` in the merge environment reports a login other than the Lair's own, or fails. | No merge this tick. The queue report names `credential-mismatch` or the failed read. No label changes. The review wait bounds it. |
| Merge-script error | `MERGE_ERROR=`, a non-zero exit, no line, an unknown line, or a run killed by the child timeout. | No change. Retried next tick; the next tick's state read shows whether a killed run merged. The review wait bounds the retries. |
| Unrecorded or moved head | GitHub's head differs from the pinned head, or the script prints `MERGE=wait:head-moved`. | No merge. With no fix-up run in flight: batch review, reason `unrecorded-head`. |
| Changed identity | The late group's fresh pull request read shows a base that is not the trunk, or a repository, author or branch that no longer matches the Lair pull request checks. | No merge. Batch review, reason `identity-changed`. |
| Trunk moved in the late group | Step 12's `ls-remote` returns a different trunk commit than step 9's. | The auto tier runs again on the new commit and routes as step 9. |
| Late-group input changed in the merge gap | None: the change lands between the late group's read and the merge call. | The pull request merges. A revert is the veto (ADR-0045 decision 14). See the Known limit under Merge-lane step of the tick. |
| Invalid result | The schema check fails, or a Lair pull request check or the ancestor check fails. | Delivery: `lair:failed`, outcome `invalid-result`, the pull request unrecorded. Fix-up: batch review, reason `fixup-failed`. Both count toward the breaker. |
| Failed fix-up run | The fix-up end marker's outcome is `failed`, `blocked`, `crashed`, `stalled`, `timed-out` or `invalid-result`. | Batch review, reason `fixup-failed`. Counts toward the breaker. |
| Fix-up run lost in flight | A start marker with no end marker and no live session, seen by a tick or the start-up sweep; or the stall window or the wall-clock budget passed since its `started_at`. | The Lair writes the end marker with outcome `crashed`, `stalled` or `timed-out`. Batch review, reason `fixup-failed`. Counts toward the breaker. |
| Parked fix-up run | The fix-up end marker's outcome is `parked`. | The pull request is converted to a draft and the claim ends. #609 handles the park: a `decision` or `fact` park is answerable on the issue; an `approval` park or a third park hands it off. Does not count toward the breaker. |
| Start marker write failed | The write of a fix-up start marker fails. | No run is launched. The trigger is tried again next tick. |
| Unfinished write sequence | A marker of a multi-write route with no applied marker. | Step 1 of the next tick finishes its writes, then writes the applied marker. No marker is written twice. |
| Claim withdrawn | The issue is closed, or has lost `lair:claimed`, while the pull request is open. | No merge. The claim-withdrawn exit. Does not count toward the breaker. |
| Lost settle cache | No cache entry, or one for another head. | A new `re-arm` snapshot. The quiet period starts again. The merge is delayed by at least 600 seconds, never taken early. A lost merge-pending mark can let one more merge call run for a queued head, with the same `--match-head-commit`. |
| Failed re-snapshot | `--check` prints a resetting marker, and the new snapshot fails. | The entry was deleted first, so no older seed remains. The next tick starts a new quiet period. |
| Malformed poll output | Not exactly one known line with exit 0. | Not settled. A failed `--snapshot` saves nothing; a failed `--check` keeps the entry. |
| Pull request closed unmerged | GitHub shows `CLOSED`. | A review marker, reason `pr-closed`; issue `lair:handoff`, not counted toward the breaker. The lane is freed. |
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
- **The halt and breaker stop claims and fix-up runs; merges continue.** ADR-0045 decision 17 as written: the halt stops new claims, and unsetting auto-merge stops merges.

The merge lane's own decisions need no ADR-0045 change. Decision 12 already names the script, the per-tick settings read and the auto-tier conditions; decision 13 already starts fix-up runs; decision 7 already types every park, a fix-up run's included; decision 17 already separates the halt from the merge stop. This design fills in how; it reverses none of them. The strain settings' merge keys are #630's pending ADR-0045 and PRD question (A3-1), not this design's.

### Tier A answers

The user answered A to each question on 2026-11-21:

- **Q1.** Amend ADR-0044 decisions 2 and 10 so the Lair's tick may run `merge-approved.sh`. Applied as ADR-0044 decisions 17 and 20.
- **Q2.** A settle check equal to ADR-0044 decision 1: the watch's change check against a saved snapshot each tick, 600 quiet seconds, and a lost cache only delays a merge. Applied as decision 18 and the Settle check component.
- **Q3.** An optional sixth expected-head argument; a different head prints `MERGE=wait:head-moved` with no merge call. Applied as decision 19.
- **Q4.** Merge settings only from the user's `.claude/settings.local.json`, then `~/.claude/settings.json`, with a PRD Credentials note. Applied under Contracts and seams, with the note under Changes to shared documents.
- **Q5.** Protected paths from a trunk list plus a fixed floor; the bump from the version-file diff. Applied in the Auto-tier script component.
- **Q6.** Local-review proof is the delivery run's recorded head plus heads the Lair's own fix-up runs recorded. Applied in the Auto-tier script component.
- **Q7.** Only a pull request the Lair recorded on the claimed issue after checking it against GitHub may merge. Applied under Contracts and seams.
- **Q8.** No merge after an issue edit; the pull request goes to batch review. Applied as step 14 of the merge-lane step.
- **Q9.** One fix-up run for failed checks, then batch review. Applied as the CI-red rule.
- **Q10.** The halt and the breaker stop claims and fix-up dispatch; merges continue; unsetting auto-merge stops merges. Applied in Lifecycle stage 4.

### Decided for you

Each of these is listed for veto. None is ADR-worthy: each fails P20's hard-to-reverse condition, as a script constant, a marker field or a routing row that a later change can alter.

- **The review marker is authoritative and final.** The Lair never merges a pull request that has one, even if the label is removed.
- **Markers go on the claimed issue, never the pull request.** One place to read, under one marker rule.
- **The review wait is 3600 seconds**, the watch's `max_watch_duration` default in `SKILL.md` (recorded in ADR-0029's Findings), measured from the recording run's `ended_at`, so it survives a lost cache.
- **The routing rows.** No checks, conflicts, a blocked merge and a refused merge go to batch review. A script error, malformed output, a killed merge run and `merge-pending` wait, bounded by the review wait. `skipped:bad-setting` is handled like `off`.
- **`merge-pending` makes no second merge call** for the same head while the cache marks it.
- **The late group and its order.** The late group is the last tick work, in this order: the merge settings, the credential login, the trunk tip, the identity, the issue edit and the settle check, then the merge call and nothing else. The seconds between its reads and that call are the merge gap (Known limit, Merge-lane step of the tick).
- **No expected base, author or branch arguments for `merge-approved.sh`.** Rejected: GitHub offers no merge call that pins those inputs, so the arguments would only narrow the merge gap and add script surface, and the issue text and the settle snapshot would still stay outside what the merge call pins (Known limit, Merge-lane step of the tick).
- **The head check goes first** in `merge-approved.sh`, before gate 1, so a moved head never yields another gate line.
- **`HIVEMIND_PR_REVIEWERS` comes from the same two user files** as the merge keys (ADR-0043 decision 2), and the reviewer filter is `automated`.
- **The settle snapshots use the `re-arm` arm kind** and are keyed by pull request and pinned head.
- **The trunk file is `.github/lair.json`.** It holds `protected_paths` and `version_files` under a strict schema. A missing, unparseable or malformed file sends every pull request to batch review. The list contents for this repository are proposed in #605's pull request.
- **A major bump is a rise in the major component** of any declared version file. A missing, unparseable or lower value goes to batch review.
- **A fix-up head counts as reviewed only when the claim's local-review head is not null**, so a fix-up run cannot launder a skipped local review.
- **A fix-up head is recorded only when the previous recorded head is its ancestor.**
- **The outcome mapping.** `blocked`, `no-pr` and an invalid result give `lair:failed` and count toward the breaker. A pull request closed unmerged gives `lair:handoff` and does not count. Extends ADR-0045 decisions 16 and 17.
- **A complete run's draft pull request goes to batch review with reason `draft`** and does not hold the lane.
- **The test layout and suite names** under Verification strategy.
- **#605 fixes the Lair's script directory**, `plugin/skills/lair/scripts/`, because it builds first; the fix-up, halt and breaker test cases are added to `tools/test_lair_merge_lane.sh` by the slices that build them. Decided by the run, 2026-11-21, on M1-A8.
- **Every tick read fails closed.** A read that fails or does not read every page means no merge and no label change that tick; only the review wait may still route, from the markers. Decided by the run, 2026-11-21, on M1-B3.
- **A resetting settle result deletes the cache entry before the new snapshot**, and only exactly one known line with exit 0 counts, for the poll and the auto tier alike. Decided by the run, 2026-11-21, on M1-B4 and M1-B5.
- **A fix-up run is supervised from its start marker.** The start marker goes first and a failed write launches nothing; the budget and stall window run from `started_at`; a lost run gets an end marker with outcome `crashed`. Decided by the run, 2026-11-21, on M1-B6.
- **The write order: marker, then labels, then an applied marker**, each write idempotent and finished on later ticks. Decided by the run, 2026-11-21, on M1-B7.
- **A Lair pull request needs a live claim, an open issue and `lair:claimed`.** A closed issue or a removed `lair:claimed` is the claim-withdrawn exit, and the closed-unmerged exit also writes a review marker. Decided by the run, 2026-11-21, on M1-B8.
- **No fix-up run starts for a pull request with a review marker.** Decided by the run, 2026-11-21, on M1-B9.
- **The protected-path floor** is the root `.github/` directory, any `.claude` path segment, and any file named `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.gitmodules` or `.gitattributes`, at any depth, with ASCII case ignored; the list gains the `**/<name>` file-name form. Decided by the run, 2026-11-21, on M1-B11.
- **The strict `.github/lair.json` schema**, with `[]` the only way to declare no entries. Decided by the run, 2026-11-21, on M1-B12.
- **The tick reads only the two named settings files**, and the queue report names the files read. Decided by the run, 2026-11-21, on M1-B15.
- **R1: a fix-up run's `decision` and `fact` parks are answerable on the issue and count toward the third-park handoff** (ADR-0045 decision 7). #609 handles them as a delivery run's park; the Lair first converts the pull request to a draft, so it belongs to its parked issue and does not hold the lane. Decided by the run, 2026-11-21, on M1-A3.
- **R2: no cap on fix-up runs for review findings.** What starts them stays with #610 (ADR-0045 decision 13, the PRD's Post-PR feedback criterion); the unbounded review loop is a seam note for #610. Decided by the run, 2026-11-21, on M1-A4.
- **R3: `lair:review` goes on both the issue (PRD Labels and Admission) and the pull request (ADR-0045 decision 12).** Decided by the run, 2026-11-21, on M1-A5.
- **R4: no strain process can write what the tick reads or runs** (an assumption about #630), and the tick hardens its own git and tool calls: a Lair-owned bare repository, hooks and system and global config off, a fixed URL, the trunk id from this tick's `ls-remote`, and tools by absolute path. The residual is ADR-0045's prompt-injected strain, with its merge-lane consequences listed. Decided by the run, 2026-11-21, on M1-B1.
- **R5: markers are assumed unforgeable by a process that holds the user's credentials and the nonces** (an assumption about #632); otherwise marker forgery is a named residual. Decided by the run, 2026-11-21, on M1-B2.
- **R6: the merge environment is the Lair's own minus every `HIVEMIND_*` key, plus the keys read from the two settings files**, and a `gh api user` login check runs in it before every merge call. Decided by the run, 2026-11-21, on M1-A2 and M1-B10.
- **R7: the CI-red rule fires from the tick's own rollup read on the pinned head, the settle check's `CI_FAILED` or `MERGE=wait:checks-failed`**, whichever comes first, whatever the merge settings, the approval and the gate order. Decided by the run, 2026-11-21, on M1-B13 and M1-A14.
- **R8: a run-end marker the merge lane owns holds `pr`, `branch`, `head` and `local_review_head`**, separate from #632's claim marker, of which the lane reads only `claim_nonce`, `claimed_at` and `body_sha256`. Decided by the run, 2026-11-21, on M1-A6.
- **R9: at most one merge call per tick, and the trunk tip is a late-group input**, with the auto tier run again when it moved. Decided by the run, 2026-11-21, on M1-B17.
- **R10: every merge-lane child process runs under a 300-second timeout**; a killed merge run routes as `MERGE_ERROR`, and the next tick's state read shows whether it merged. Decided by the run, 2026-11-21, on M1-B16.
- **R11: the empty-string merge keys in strain settings are #630's pending ADR-0045 and PRD question (A3-1)**, and "no ADR-0045 change" covers only the merge lane's own decisions. Decided by the run, 2026-11-21, on M1-A9.
- **R12: #605 changes the Tier A merge bullet of `plugin/governance/decision-autonomy.md`** to name the Lair tick's merge under ADR-0044 decision 17, updates `tests/policy/safety-auto-merge-after-approval.json` and adds a structural check. Decided by the run, 2026-11-21, on M1-A1.
- **R13: the PRD's Out of Scope bullet on the ADR-0044 merge rules names the Lair tick's merge path**, a PRD change the user's Q1 and Q3 answers already approved (Changes to shared documents, item 6). Decided by the run, 2026-11-21, on M1-A15.

### Changes to shared documents

None of these is applied in this pull request.

1. **PRD Credentials bullet.** Target: [docs/prds/autonomous-ready-issue-loop.md](../../prds/autonomous-ready-issue-loop.md), Implementation Decisions, the bullet that begins "**Credentials.**". Replace its second sentence, "Merges follow the user's existing merge settings, the admin bypass included, read fresh each tick.", with: "Merges follow the user's own merge settings, read fresh each tick from `.claude/settings.local.json` and then `~/.claude/settings.json`, never from the committed settings, the admin bypass included." Answer: Tier A, Q4, approved 2026-11-21.
2. **Amendments pointer.** Target: [solution-design.md](solution-design.md), section Amendments, a new paragraph after its last line: "2026-11-21: For the merge lane, [merge-lane-design.md](merge-lane-design.md) supersedes the parts its opening paragraph names: the Merge lane and auto tier component; the GitHub-record, park and halt side of Post-PR remediation strains and the start of a fix-up run for failed checks; the Auto-tier script result contract; the run-end sentence of the Claim marker comment contract; the merge-settings channel; the Lifecycle label bullets for `lair:handoff`, `lair:failed` and `lair:review`, stage 1's merge step, stage 3 whole and stage 4's merge stop, and it adds the draft, closed-unmerged and claim-withdrawn exits; three Failure modes rows; and three Decisions. ADR-0044's amendment of the same date lets the Lair's tick run `merge-approved.sh`." Answer: decided for you, listed for veto.
3. **Round-3 dispositions.** Target: [review-record.md](review-record.md), the Disposition column of the Round 3 tables, and the `open_counts` front matter recomputed to match. Each `open` cell below becomes the text given:
   - A3-2, B3-5 and B3-6: "fixed: merge-lane-design.md, Settle check, Pinned head and Routing table".
   - A3-3 and B3-7: "fixed: merge-lane-design.md, Merge settings source and Merge environment".
   - A3-10 and B3-8: "fixed: merge-lane-design.md, Auto-tier script".
   - B3-4: "fixed: merge-lane-design.md, Lair pull request".
   - A3-8: "fixed: merge-lane-design.md, Exits".
   - A3-13: "fixed: merge-lane-design.md, Exits (`lair:review` on the issue and the pull request)".
   - B3-13: "fixed: merge-lane-design.md, Run outcome to labels".
   - B3-14: "fixed: merge-lane-design.md, Fix-up runs and Lifecycle stage 4".

   A3-12 stays open: two of its three calls were asked as Q8 and Q9, and the session-scoped breaker is not in this scope. Answer: decided for you, listed for veto.
4. **Lair pull request term.** Target: [CONTEXT.md](../../../CONTEXT.md), section Language, a new entry after the **Lair** entry, in the glossary's three-line form:

   ```text
   **Lair Pull Request**:
   A pull request the **Lair** recorded on its claimed issue after checking a strain's complete result against GitHub: same repository, trunk base, the Lair's own login as author, and the result's branch and head. It stays one while its claim is live and the issue is open and carries `lair:claimed`. Only a Lair Pull Request can be merged by the Lair.
   _Avoid_: strain PR, factory PR
   ```

   Answer: decided for you, listed for veto.
5. **Tier A merge bullet.** Target: `plugin/governance/decision-autonomy.md`, Tier A, the bullet "every merge recommendation; the human merges, except the review watch's opt-in merge after a reviewer approval, per `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/SKILL.md`". Replace it with: "every merge recommendation; the human merges, except the review watch's opt-in merge after a reviewer approval, per `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/SKILL.md`, and the Lair tick's merge of a Lair pull request in the auto tier under ADR-0044 decision 17". Built by #605 with the fixture update and the structural check under Existing-path coverage, within the file's byte budget. Basis: ADR-0044 decision 17 and Tier A answer Q1, 2026-11-21. Answer: decided for you, listed for veto.
6. **PRD Out of Scope bullet.** Target: [docs/prds/autonomous-ready-issue-loop.md](../../prds/autonomous-ready-issue-loop.md), Out of Scope, the bullet "**Changing the ADR-0044 merge rules** beyond the auto-tier precondition, and changing the repository's ruleset." Replace it with: "**Changing the ADR-0044 merge rules** beyond the auto-tier precondition and the Lair tick's merge path of ADR-0044's 2026-11-21 amendment (decisions 17 to 20), and changing the repository's ruleset." Basis: this is a PRD change the user's Tier A answers Q1 and Q3 of 2026-11-21 already approved: Q1 lets the tick run `merge-approved.sh`, and Q3 adds the expected-head argument.

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
  - Protected paths: a floor path; a trunk-list path; a list entry added on the pull request head, which is ignored; a rename into a protected directory.
  - The floor by name and case: `docs/CLAUDE.md`, `a/CLAUDE.local.md`, `sub/.mcp.json`, `x/.gitattributes`, `a/.claude/b`, `.Claude/x`, `claude.md` and `.GitHub/workflows/x.yml`.
  - The list forms: an exact path, a directory prefix and a `**/<name>` entry, each also matched with other case.
  - Trunk file: missing; unparseable; not an object; an extra top-level key; each key missing; each key not an array; a malformed `protected_paths` entry (empty, leading `/`, a `..` segment, a stray `*`); a `version_files` entry with a missing or extra key; and `[]` for both, which is accepted.
  - Bump: major, minor, and an unreadable or lower version.
  - Local review: the delivery's local-review head; a fix-up head; a fix-up head with a null local-review head; an unrecorded head.
  - Several reasons at once, in their fixed order.
  - Errors: no merge base, a commit that is not present, an unusable git directory, and bad arguments.
  - A hook installed in the git directory does not run.
- **Merge-lane tick tests, `tools/test_lair_merge_lane.sh`, with fixtures in `tests/lair-merge-lane/`:**
  - A PATH-shim `gh` and `git` serve recorded GitHub states, and fake merge, poll and auto-tier scripts record their argv and environment. The tick's settings-file reader, credential read and cache reader are called through names the test replaces, so the fake-call log records them.
  - Routing: every row of the routing table, plus a check that the table names every `MERGE=` line listed in `merge-approved.sh`'s output contract. A merge run killed by the timeout routes as `MERGE_ERROR`, and a next-tick state read of `MERGED` gives the merged exit.
  - Merge settings: the local file winning; the user file used alone; an empty local value overriding the user's; committed settings ignored; a key in the Lair's environment ignored; `CLAUDE_CONFIG_DIR` set and ignored; an unparseable file meaning no merge; the queue report naming the files read.
  - Merge environment: no `HIVEMIND_*` key from the Lair's environment reaches the fake scripts; `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `XDG_CONFIG_HOME` and a keyring variable pass through; a credential login that differs, or a failed credential read, makes no merge call and names the reason.
  - Settle check: a check that the tick names every `--check` and `--snapshot` output line of the poll script's contract; the first sighting; `UNCHANGED` under 600 seconds and at 600 seconds, on an injected clock; each resetting marker; `CI_FAILED` then `SNAPSHOT_ERROR`, after which an `UNCHANGED` against the old seed is not settled; `SNAPSHOT_ERROR` on a first sighting; a malformed `BASELINE=` line; `STATE=MERGED` and `STATE=CLOSED` from `--check`; `CHECK_ERROR`; `UNCHANGED` with a second line or a non-zero exit; a lost cache.
  - Auto tier: `TIER=auto`; `TIER=review:` with known codes; an unknown code; two lines; `TIER=auto` with a non-zero exit; `TIER_ERROR`; a run killed by the timeout.
  - Fail-closed reads: a review marker on the second comment page still holds the pull request; an incomplete comment read does nothing; a failed pull request read runs only the review wait; a failed issue read, identity read, `ls-remote` or fetch makes no merge call and no label change.
  - Pinned head: equal, moved, unrecorded, and a fix-up head that is not a descendant.
  - Lair pull request checks: the five failing cases, a fork, a wrong base, another author, a branch mismatch and a head mismatch, each run through both paths. The recording path gives an invalid result. The late group gives `identity-changed` and no merge call.
  - Lair pull request state: a closed issue and a removed `lair:claimed` each give the claim-withdrawn exit and no merge; a claim with a terminal outcome is never merged.
  - Holds and skips: a review marker with the `lair:review` label removed still gives no merge; a fix-up run in flight is skipped; `merge-pending` on one tick means no merge call for that head on the next.
  - Late group: one property checked over every case that reaches the merge call. The fake-call log shows the late-group reads in order, the settings files, the credential read, the `ls-remote`, the pull request, the issue and the settle check, with only the merge script call after the last, so a tick read added after the group fails the test. A trunk that moved in the late group reruns the auto tier.
  - One merge per tick: with two pull requests ready, the tick makes one merge call.
  - Exits: the merged exit from a state read, not only from the script's confirm read; the draft and closed-unmerged exits; the review wait; issue edit before merge.
  - Write order: a tick stopped after each write of each route; the next tick finishes the writes and writes no second marker.
  - Delivery run ends: `no-pr`, `blocked`, the draft delivery, and `pr-closed`, which does not count toward the breaker.
  - A pull request whose body holds a "Decided for you" list still merges.
  - Cases added by the slices that build them: the CI-red rule from each of its three signals with merge settings off, a second red result, and a halt; no fix-up run for a pull request with a review marker; a failed start-marker write launching nothing; a lost run's `crashed` end marker; a budget measured from `started_at`; fix-up park routes; fix-up run outcomes and the breaker count (#610). The halt stopping fix-up runs while merges continue (#608). The breaker counts (#611).
- **No merge by a strain** is tested in the strain contract suite that #630 designs and #604 builds.
- **Registration in `tools/validate.sh`, for each new suite:**
  - a constant: `SUITE_TEST_AUTO_TIER='test_auto_tier.sh'` and `SUITE_TEST_LAIR_MERGE_LANE='test_lair_merge_lane.sh'`;
  - an entry in `ALL_SUITES` and in `KNOWN_SUITES`;
  - a `map_path` rule routing the script, its test and its fixture directory to the suite; the merge-lane rule also routes `merge-approved.sh` and `pr-change-detect-poll.sh`, whose output contracts that test reads;
  - a `self_test` probe: `tests/auto-tier/README.md` and `tests/lair-merge-lane/README.md`.

  `tools/test_validate_suites.sh` runs with the new entries.

## Seam order

The design changes these slices. The ADRs each one touches were confirmed by reading them. #607 is unchanged.

| Slice | Change | ADRs |
| --- | --- | --- |
| #604 | Strain settings keep any merge key from taking effect in a strain, as #630 chooses, and keep strains from writing what the tick reads or runs; the result gains `local_review_head`. | ADR-0045 decisions 4 and 5; ADR-0044 decision 17; ADR-0010, amendment 2026-10-31; ADR-0037; ADR-0042 |
| #605 | The Lair's script directory; the merge-lane step with its late group, fail-closed reads, child timeout, one merge per tick, merge environment and credential check, and git and tool hardening; the settle check; the auto-tier script and its schema; the expected-head argument; the routing table; the merge settings source; the write order; the Tier A merge bullet in `decision-autonomy.md`, the `safety-auto-merge-after-approval.json` update and the structural check; and their tests. | ADR-0044 decisions 1, 4, 6, 9, 10, 14, 15, 16 and 17 to 20; ADR-0045 decisions 10, 12, 16 and 17; ADR-0043 decision 2; ADR-0042; ADR-0029, Findings; ADR-0026; ADR-0020, amendment 2026-09-29 |
| #606 | Under the release-train mode, the auto tier's bump input must come from the change fragments; #606 defines it. | ADR-0045 decisions 12 and 15 |
| #608 | The tick calls the merge-lane step under the lock and reads the halt file before fix-up dispatch. It writes the run-end marker and the outcome mapping, reads the Lair's own login at start, and its start-up sweep ends lost fix-up runs. It adds the halt test cases. | ADR-0045 decisions 2, 5, 12, 16 and 17; ADR-0044 decision 17 |
| #609 | Park counting and answer handling include fix-up parks, whose pull request the Lair has converted to a draft. | ADR-0045 decisions 7, 11, 12 and 16 |
| #610 | Fix-up runs gain start and end markers, the CI-red rule, supervision from `started_at`, the park route, the halt rule and no start for a pull request with a review marker. Its trigger owns the bound on review-finding runs. It adds the fix-up test cases. | ADR-0045 decisions 7, 13 and 17; ADR-0040 decision 2 |
| #611 | The breaker reads outcomes from the run-end and fix-up end markers, counts fix-up failures, `blocked`, `no-pr` and invalid results, and not `pr-closed` or claim withdrawal; the digest notes `--admin` merges. It adds the breaker test cases. | ADR-0045 decisions 14 and 17 |
| #612 | Each parallel pull request keeps its own pinned head, settle cache and auto-tier run against the current trunk, with one merge call per tick. | ADR-0045 decisions 12 and 15; ADR-0044 decision 19 |

## Open questions

None

## Amendments

This design was written with ADR-0044's amendment of 2026-11-21 (decisions 17 to 20) and the user's Tier A answers of the same date. Later changes to this design are appended here as dated entries.

2026-11-21: Design review round 1 returned 32 findings, M1-A1 to M1-A15 and M1-B1 to M1-B17. Each is fixed in this design or in ADR-0044's amendment of the same date, as the [merge-lane review record](merge-lane-review-record.md) lists under Round 1, and the run's calls R1 to R13 are under Decided for you.
