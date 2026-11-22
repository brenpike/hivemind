# Solution design: Lair merge lane

This is the solution design for the Lair's merge lane, issue #631, a sub-issue of epic #603. It links the [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md), [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md) and the [solution design](solution-design.md) rather than restating them. It cites them as "ADR-0045 decision N" and "ADR-0044 decision N"; decisions 17 to 20 are those of ADR-0044's 2026-11-21 amendment. Its design review is recorded in the [merge-lane review record](merge-lane-review-record.md). For the merge lane, this design supersedes these parts of solution-design.md:

- the Component "Merge lane and auto tier";
- the GitHub-record, park and halt side of the Component "Post-PR remediation strains" (what starts a fix-up run stays there);
- the Contract "Auto-tier script result";
- the merge-settings part of the Trust boundaries channel list ("the halt file and the merge settings on the user's own machine");
- in Lifecycle: stage 1's merge step, stage 3, stage 4's merge stop, and the draft and closed-unmerged exits, which solution-design.md does not have;
- the Failure modes rows "Merge refused", "CI red" and "Issue edited after claim";
- the Decisions "Merges only through `merge-approved.sh` and its gates", "A red CI result gets one remediation strain, then `lair:review`" and "An issue edited after claim is not merged and goes to `lair:review`".

Every other part of solution-design.md stands.

## Context and code truth

The merge lane builds on this code, as it stands on trunk:

- `plugin/skills/github-review-loop/scripts/merge-approved.sh` takes exactly five arguments: owner, repo, pull request number, reviewer filter and self login. Any other count is `MERGE_ERROR=bad-arguments`. It reads `HIVEMIND_AUTO_MERGE`, `HIVEMIND_AUTO_MERGE_ADMIN` and `HIVEMIND_PR_REVIEWERS` from its environment. It prints exactly one line, a `MERGE=` line with exit 0 or a `MERGE_ERROR=` line with exit 1, and nothing on stderr.
- The script reads the PR once, then runs gates 1 to 7 in order: not open, draft, no settled evidence (`has_settled_evidence`), an open thread (`is_settled_thread`), no check rollup, pending, failed. Only then does it call `gh pr merge` with `--match-head-commit` set to the head of that read. A read past its page is `MERGE_ERROR=read-incomplete`.
- `MERGE=wait:head-moved` already exists. Today it prints only after a refused plain merge, when the re-read shows a different head. The script has no way to be told which head the caller expects.
- A merge call that exits 0 is followed by a confirm read. `MERGE=merged` and `MERGE=merged-admin` print only when that read shows `MERGED`, else `MERGE=wait:merge-pending` (ADR-0044 decision 16).
- `tools/test_merge_approved.sh` runs the script against a PATH-shim `gh` that serves canned GraphQL bodies and logs every call. After the cases it checks five properties over every case, among them that every merge call carries `--match-head-commit` equal to the head of the read before it.
- `plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh` has three modes. `--snapshot <arm-kind>` prints one `BASELINE=<seed>` line. `--check` compares one capture against a seed and prints one of `UNCHANGED`, `CHANGED`, `CI_FAILED`, `REVIEWER_APPROVED`, `STATE=MERGED`, `STATE=CLOSED` or `CHECK_ERROR`. It never sleeps, never reads the deadline and never prints `REVIEWER_SETTLED`. Only poll mode judges a settled approval, with `SETTLE_SECONDS=600` on its loop-top clock. Both one-shot modes still validate the window and interval arguments as integers.
- The seed carries its arm kind. Under an `initial` seed an approval already present fires `REVIEWER_APPROVED`. Under a `re-arm` seed the approval edge counts as observed and does not fire again.
- `plugin/skills/github-review-loop/scripts/reviewer-identity.jq` holds `has_settled_evidence` and `is_settled_thread`. They are the only settled-evidence and settled-thread verdicts. The poll and the merge script both call them (ADR-0044 decision 14).
- The merge rule in `plugin/skills/github-review-loop/SKILL.md` runs `merge-approved.sh` with five arguments, once, only after an approval return whose QUIET-EXIT CHECK reports `UNCHANGED`, and routes its line for the watch alone. The skill's `allowed-tools` grant is `Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/merge-approved.sh" *)`.
- The standard-delivery local review gate is in `plugin/workflow-src/standard-delivery/gates.js` and `review.js`. `configuredGateIds` requires local review only when the launch's `local_review` is true and no review returned `skipped` (SD-31, SD-86). A skipped review still opens a ready pull request, with a warning line (SD-86). A loop cap opens a draft whose local review did not hold (SD-83). The run's result names the pull request and its `head_ref_oid` (SD-47). The run state knows whether the gate held; nothing writes that outside the run today.
- `pr-feedback-remediation` runs validation as its one gate and no local review (`plugin/workflow-src/pr-feedback-remediation/tail.js` `gateIds()`, contract row PFR-23).
- `tools/validate.sh` registers each behavioural suite in four places: a `SUITE_*` constant, the `ALL_SUITES` and `KNOWN_SUITES` lists, a path-to-suite rule in `map_path`, and a probe path in the `self_test` map. `test_merge_approved.sh` is registered in all four.
- No Lair script exists on trunk. Nothing under `plugin/` reads a merge setting from a settings file; every reader takes it from the environment.

## Components

### Merge-lane step of the tick

Built by #605, called by #608's tick under the single-instance lock. Each tick, for each open Lair pull request (defined under Contracts and seams), the step runs these checks in order and stops at the first that routes:

1. **State.** The step reads the pull request. Merged goes to the merged exit; closed goes to the closed-unmerged exit (Lifecycle).
2. **Held by review.** A review marker exists for this pull request (Contracts and seams). The Lair never merges it again; the step skips it.
3. **Fix-up in flight.** A fix-up run on this pull request has a start marker and no end. The step skips it, because the run will move the head.
4. **Draft.** The pull request is a draft. The step routes it to the draft exit.
5. **Pinned head.** The pinned head is the head the Lair last recorded for this pull request. It must equal GitHub's head. Otherwise the pull request goes to batch review with reason `unrecorded-head`.
6. **Review wait.** When 3600 seconds have passed since the `ended_at` of the run that recorded the pinned head, the pull request goes to batch review with reason `review-wait-elapsed`.
7. **Auto tier.** The auto-tier script runs on the pinned head. A `review` result sends the pull request to batch review with its reason codes. A script error means no merge this tick.
8. **Merge settings.** The step reads the two user settings files. A file that does not parse means no merge this tick.
9. **Issue edit.** The step recomputes `body_sha256` of the claimed issue's title and body and compares it with the latest claim marker's. A difference sends the pull request to batch review with reason `issue-edited` (Q8). The check runs before every merge attempt.
10. **Settle check.** See below. Not settled means no merge this tick.
11. **Merge.** The step runs `merge-approved.sh` with six arguments in a clean environment and routes its one line by the routing table under Contracts and seams.

Steps 9 and 10 run last, with no other step between them and the merge, so the gap between their reads and the merge call is a few seconds.

**Known limit.** Decided by the run under `plugin/governance/decision-autonomy.md` (Review Calls), on a local-review finding, 2026-11-21. An issue edit or a change the settle check would see, landing between step 9's or step 10's read and the merge call, is not seen. `merge-approved.sh` rechecks the approval and threads on its own read, but it never reads the issue, and the expected-head argument pins only the head: GitHub offers no merge call that also pins issue text or the settle snapshot, so no client-side check can close the gap. This is the same kind of limit as ADR-0044 decision 15. Passing a settle digest and the issue hash into `merge-approved.sh` was rejected: it adds script surface, and a gap inside the script remains. A finding that only says the issue or the settle state can change between steps 9 and 10 and the merge call contests this decision and is a repeat.

Under parallel strains (#612) the step runs the same way for each pull request.

### Settle check

Built by #605. It equals ADR-0044 decision 1 (decision 18, Q2). It uses `pr-change-detect-poll.sh` unchanged, in the same clean environment as the merge:

- When the cache has no snapshot for this pull request and pinned head, the step takes one with `--snapshot re-arm`, saves the seed with the pinned head and `quiet_since` set to now, and stops for this tick. The arm kind is `re-arm` so that an approval already present does not fire `REVIEWER_APPROVED` on every tick.
- Otherwise it runs `--check` against the saved seed:
  - `UNCHANGED` with now minus `quiet_since` at least 600 seconds: settled.
  - `UNCHANGED` with fewer: not settled.
  - `CHANGED`, `CI_FAILED` or `REVIEWER_APPROVED`: the step takes a new `re-arm` snapshot, saves it with `quiet_since` set to now, and is not settled.
  - `STATE=MERGED` or `STATE=CLOSED`: not settled; the next tick's state read routes the pull request.
  - `CHECK_ERROR`, `SNAPSHOT_ERROR` or a non-zero exit: not settled, and the cache entry is kept.
- The window and interval arguments are `3600` and `60`. The one-shot modes validate them and use neither. The reviewer filter is `automated`.

The approval and thread parts of decision 1 are not judged here. `merge-approved.sh` judges them on its own read through `has_settled_evidence` and `is_settled_thread`, with a read past its page failing closed. A lost or unreadable cache only delays a merge: the next tick takes a new snapshot, and the quiet period starts again.

### Auto-tier script

Built by #605 as one script, proposed as `plugin/skills/lair/scripts/auto-tier.sh` (#608 fixes the Lair's script directory). It has no model in it and reads only git objects and the arguments the tick passes. It and the merge-lane step use ADR-0020's fail-closed bootstrap forms (amendment 2026-09-29). The ADR-0044 gates are left to `merge-approved.sh`. Its conditions (Q5, Q6):

- **Protected paths.** The changed paths are `git diff --name-only --no-renames -z` from the merge base to the pinned head, so a rename lists both sides. The protected-path list is read from the trunk commit the tick fetched, never from the pull request head. It is `.github/lair.json`, key `protected_paths`. Each entry is an exact path, or a directory prefix ending in `/`; there are no globs. A fixed floor in the script applies whatever the list says, and no list entry removes it: `.github/`, `.claude/`, `CLAUDE.md`, `.mcp.json`, `.gitmodules` and `.gitattributes`. The list file itself sits under the floor.
- **Bump.** The version files are named in the same trunk file, key `version_files`, each as a JSON file path and a top-level key. The script reads each value at the merge base and at the pinned head as `MAJOR.MINOR.PATCH`. A rise in `MAJOR` is a major bump. A value that is missing, unparseable or lower at the head is unreadable.
- **Local review.** The tick passes the latest claim's recorded local-review head and the heads the Lair's fix-up runs recorded since that claim. The condition holds when the pinned head equals the local-review head, or the local-review head is not null and the pinned head is a fix-up head.

The script prints one line:

- `TIER=auto`, exit 0;
- `TIER=review:<code>[,<code>...]`, exit 0, with every failing code, in this order: `protected-list-unreadable`, `protected-path`, `version-unreadable`, `major-bump`, `local-review-missing`;
- `TIER_ERROR=<reason>`, exit 1, for bad arguments, a commit that is not present, or no merge base.

A missing or unparseable `.github/lair.json` gives `protected-list-unreadable`, so no pull request merges until the file exists.

### Fix-up runs

A fix-up run is an unattended `pr-feedback-remediation` run on the pull request (ADR-0040 decision 2, ADR-0045 decision 13). The trigger for a review-finding fix-up run stays with #610. This design fixes what the merge lane needs from every fix-up run (Q9, Q10):

- Each run has a start marker and an end marker on the claimed issue, with the fields under Contracts and seams.
- A fix-up run for failed checks starts only on `MERGE=wait:checks-failed`, at most once per pull request. A second red result goes to batch review (the CI-red rule under Decisions).
- Review-finding fix-up runs on one pull request are capped at the value `loop-state.sh floor` prints, the watch's `max_remediation_cycles` floor. When the cap is reached, the next trigger sends the pull request to batch review with reason `fixup-cap`.
- No fix-up run starts while the halt file or the circuit breaker holds. Runs already started finish.
- The run-end handling is under Lifecycle.

## State and ownership

GitHub stays authoritative (ADR-0045 decision 2). This table adds the merge lane's state to solution-design.md's table:

| State | Writer | Readers | Authoritative |
| --- | --- | --- | --- |
| Recorded run end in the claim marker: `pr`, `branch`, `head`, `local_review_head`, `outcome`, `ended_at` | Lair, after checking the result against GitHub | Lair | yes |
| Fix-up start and end markers on the claimed issue | Lair | Lair, user | yes |
| Review marker on the claimed issue | Lair | Lair, user | yes; the `lair:review` label on the pull request only shows it |
| `lair:review` label on the pull request | Lair | user | no; the review marker is |
| Protected-path list and version files, `.github/lair.json` at the fetched trunk commit | user, through a reviewed pull request | auto-tier script | yes, at that commit |
| Merge settings in `.claude/settings.local.json` and `~/.claude/settings.json` | user | Lair, each tick | no; a control input |
| Settle cache: seed, pinned head, `quiet_since`, merge-pending flag, per pull request | Lair | Lair | no; losing it only delays a merge |

The pinned head, the local-review proof, the fix-up count and the CI fix-up count are all recomputed from markers each tick, never kept only in the cache.

## Contracts and seams

Fields and seams only. Each slice builds the code.

### Lair pull request

A pull request is a Lair pull request only when the Lair recorded it in the run-end fields of the claimed issue's latest claim marker (Q7). The Lair records it only from a `complete` delivery result, and only after these hold on a fresh GitHub read:

- the result's `pr` exists in the same repository, not a fork;
- its base is the trunk;
- its author is the Lair's own login;
- its head branch equals the result's `branch`;
- its head commit equals the result's `head`.

Any failure makes the result invalid (Lifecycle). The Lair never merges, labels or holds the lane for a pull request it did not record.

### Pinned head

The pinned head is the last `head` a Lair run recorded for the pull request: the delivery run's, or the latest fix-up run's, by `ended_at`, since the latest claim. A fix-up run's head is recorded only when the previous recorded head is its ancestor. The tick passes the pinned head as `merge-approved.sh`'s sixth argument. The auto tier, the settle cache key and the merge all use that one commit.

### Expected-head argument

Decision 19 (Q3). `merge-approved.sh` takes an optional sixth argument, `EXPECTED_HEAD`:

- It must be 40 or 64 lowercase hex characters, else `MERGE_ERROR=bad-expected-head`, checked with the other arguments before any `gh` call. Seven or more arguments stay `MERGE_ERROR=bad-arguments`.
- Right after the first read, before gate 1, a head that differs prints `MERGE=wait:head-moved` and makes no merge call. The check goes first so that a moved head never yields a gate line, such as `wait:checks-failed`, about a commit no Lair run recorded.
- The gated head is the expected head, so every merge call, `--admin` included, carries `--match-head-commit` with it. The refused-merge re-read compares against it as it does today.
- With five arguments nothing changes.

### Merge settings source

Decision 17 (Q4). Each tick the step reads the `env` object of two files:

1. `.claude/settings.local.json` at the root of the Lair's checkout, which is the main checkout;
2. `~/.claude/settings.json`.

For each of `HIVEMIND_AUTO_MERGE`, `HIVEMIND_AUTO_MERGE_ADMIN` and `HIVEMIND_PR_REVIEWERS`, a key present in file 1, even empty, wins; otherwise file 2's value is used; otherwise the key is unset. This matches Claude Code's order of local over user settings.

- An absent file counts as empty.
- A file that does not parse as JSON, an `env` that is not an object, or one of the three values that is not a string means no merge this tick. The queue report names the file.
- The committed `.claude/settings.json` is never read, and the merge keys are never taken from the Lair's own environment.

The step runs `merge-approved.sh` and the settle check through `env -i` with only:

- `PATH` and `HOME`;
- `GH_TOKEN`, `GH_HOST` and `GH_CONFIG_DIR` when the Lair's own environment sets them, so `gh` authenticates as the Lair does;
- the three keys above, each only when set.

### Routing table

Decision 20. The tick routes the script's output as follows. The skill's routing in `SKILL.md` stays bound to the watch. Batch review means a review marker, the `lair:review` label on the pull request, and the reason code.

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
| `MERGE=wait:checks-failed` | The CI-red rule. |
| `MERGE=merged` | The merged exit. |
| `MERGE=merged-admin` | The merged exit; the digest notes the `--admin` merge. |
| `MERGE=wait:head-moved` | No merge. The next tick's pinned-head check routes the pull request. |
| `MERGE=skipped:conflicts` | Batch review, reason `conflicts`. |
| `MERGE=skipped:blocked` | Batch review, reason `merge-blocked`. |
| `MERGE=skipped:refused` | Batch review, reason `merge-refused`. |
| `MERGE=wait:merge-pending` | The cache marks the head merge-pending. No merge call runs for that head while the mark stands. The next tick's state read routes the pull request, and the review wait bounds it. |
| `MERGE_ERROR=<reason>` with exit 1 | No change. Retried next tick; the queue report names the reason; the review wait bounds it. |
| A non-zero exit with any other output | Treated as `MERGE_ERROR`. |
| No line, more than one line, or a line not in this table | Treated as `MERGE_ERROR`. |

### Markers the merge lane writes

Each marker is a machine-readable comment on the claimed issue, under #632's author and nonce rule:

- **Claim marker, run-end fields.** Besides `outcome` and `ended_at` (solution-design.md): `pr`, `branch`, `head` and `local_review_head`, written only for a `complete` result that passed the Lair pull request checks. A parked run's draft is not recorded here; it belongs to the park (#609, ADR-0045 decision 12).
- **Fix-up start marker.** `kind` (`fixup-checks` or `fixup-review`), `run_nonce`, the `claim_nonce` of the claim it belongs to, `pr`, `start_head`, `started_at`.
- **Fix-up end marker.** `run_nonce`, `outcome`, `ended_at`, and `head` when recorded, or the park record when parked.
- **Review marker.** `pr`, `head`, `reasons` (codes only, no issue or pull request text), `at`.

### Assumptions about #630

- Strain settings set `HIVEMIND_AUTO_MERGE` and `HIVEMIND_AUTO_MERGE_ADMIN` to the empty string. Omitting them is not enough: since Claude Code 2.1.211 a worktree session reads the main checkout's `.claude/settings.local.json` (ADR-0010, amendment 2026-10-31), and an omitted key overrides nothing inherited.
- Deny rules in the strain settings cover reads and writes of the two files the Lair reads merge settings from, and writes to the Lair's cache directory.
- The result schema carries `local_review_head`: a commit, or null when local review was not configured, was skipped, or did not hold. #630's fixed result script writes it from the run's own state, never from a value the model passes.
- A fix-up run starts on the pull request's branch at the pinned head, pushes to that branch only, and writes the same result schema, with `local_review_head` null.

### Assumptions about #632

- **Markers.** #632 defines the author and nonce rule that makes a marker comment count. The merge lane reads no marker that fails that rule.
- **Claim marker fields.** The claim marker carries `claim_nonce`, `claimed_at` and `body_sha256`. #632 fixes the `body_sha256` form, including line-ending and null-body handling, as one function. The merge lane's issue-edit check calls that function and has no form of its own.
- **Controls.** #632 fixes the halt file path, the lock and the injection scan. The merge lane reads the halt file through #632's reader and runs only under the lock. It gives no GitHub text to a model, so it adds no injection-scan call.

### Fields the merge lane needs at run end

From each delivery result: `outcome`, `pr`, `branch`, `head`, `local_review_head`. From each fix-up result: `outcome`, `pr`, `branch`, `head`, `park`. The claim and fix-up markers above carry them once the Lair has checked them.

## Trust boundaries

This section replaces the merge-settings part of solution-design.md's channel list. Merge settings are a channel only through the user's own files on the Lair's machine: `.claude/settings.local.json` at the main checkout and `~/.claude/settings.json`. Unsetting `HIVEMIND_AUTO_MERGE` there stops merges from the next tick (ADR-0045 decision 17).

- **The committed settings.** A pull request, a Lair one included, can change the committed `.claude/settings.json`, so the tick never reads it.
- **The strain.** It cannot write either user file (an assumption about #630). It cannot reach the tick's environment, because the tick runs the merge in a clean environment.
- **The auto-tier inputs.** None of them comes from the pull request head:
  - the protected-path list is read at the trunk commit, and the floor is in the script;
  - the bump is computed from version-file values, not from commit messages, plan fields or labels;
  - the local-review proof is a head the Lair recorded from a checked result.
- **The pinned head.** A head no Lair run recorded never merges a Lair pull request.
- **Residual: under-declared bump.** The bump check sees the version a pull request declares, not its real compatibility impact. A breaking change shipped with a minor bump passes it. The protected-path list is the control for compatibility surfaces.
- **Residual: a compromised strain.** It can still report a false local-review head if it subverts #630's fixed result script. The head must still pass the Lair pull request checks.
- **Residual: the interactive watch.** A user who runs the interactive watch on a Lair pull request merges under ADR-0044 unchanged, outside the auto tier.

## Lifecycle

### Run outcome to labels

This table covers each run end the merge lane depends on, and replaces stage 1's merge step. Crash, stall and budget outcomes stay as in solution-design.md. A park from a delivery run stays with #609.

| Run end | Issue | Pull request | Breaker |
| --- | --- | --- | --- |
| Delivery `complete`, result checks pass, PR not a draft | stays `readiness:implementation` and `lair:claimed` | recorded; enters the merge lane and holds it | resets the count |
| Delivery `complete`, result checks pass, PR a draft | unchanged | recorded; batch review, reason `draft`; does not hold the lane | resets the count |
| Delivery `complete` with `pr` null | `lair:failed`, outcome `no-pr` | none | counts |
| Delivery `blocked` | `lair:failed`, outcome `blocked` | left as it is, unrecorded | counts |
| Delivery `failed` | `lair:failed` | left as it is, unrecorded | counts |
| Invalid result: the schema check fails, or a Lair pull request check fails | `lair:failed`, outcome `invalid-result` | left as it is, unrecorded, never merged | counts |
| Fix-up `complete`, result checks pass | unchanged | new recorded head | resets the count |
| Fix-up `parked` | unchanged | batch review, reason `fixup-parked` | does not count |
| Fix-up `failed`, `blocked`, crashed or timed out | unchanged | batch review, reason `fixup-failed` | counts |
| Fix-up invalid result | unchanged | batch review, reason `fixup-failed` | counts |

The fix-up result checks are the Lair pull request checks against the pull request it ran on, plus the ancestor check under Contracts and seams. A fix-up park is not answerable on the issue, does not move the issue to `readiness:needs-decision`, and does not count toward the third-park handoff. Its park record is kept in the end marker for the user's batch review.

### Exits

- **Merged.** GitHub shows the pull request `MERGED`, seen by the script's confirm read or a later tick's state read. The issue moves to `readiness:done` and `lair:claimed` is removed. The lane is freed.
- **Draft.** A Lair pull request that is a draft goes to batch review with reason `draft`. A draft does not hold the lane (ADR-0045 decision 12). The issue keeps its labels until the user merges or closes the pull request.
- **Closed unmerged.** The issue gets `lair:handoff`, `lair:claimed` is removed, and its readiness label is left as it is. It leaves the factory. The outcome `pr-closed` goes into the claim marker and does not count toward the breaker. The lane is freed.
- **Batch review.** The review marker is written and `lair:review` goes on the pull request, never the issue. The Lair never merges that pull request again. A non-draft one still holds the lane (ADR-0045 decision 12) until the user merges it, which ends at the merged exit, or closes it, which ends at the closed-unmerged exit.

### Stage 3: post-PR fix-up

This replaces solution-design.md's stage 3. A trigger starts one fix-up run on the pull request: review findings by #610's rule within the cap, or the CI-red rule. The Lair writes the start marker. The run pushes to the same branch and ends with a result. The Lair checks the result and writes the end marker, recording the new head or routing as the table above says. On a later tick the merge-lane step evaluates the pull request again from step 1, with a new settle snapshot for the new head.

### Stage 4: halt and circuit breaker

This replaces solution-design.md's stage 4 merge stop (Q10). The halt file and a tripped circuit breaker stop new claims and new fix-up runs. Runs in flight, delivery and fix-up alike, finish, and their results are handled. Merges continue. Unsetting `HIVEMIND_AUTO_MERGE` in the user's settings files stops merges from the next tick (ADR-0045 decision 17). Under a halt, a pull request whose checks fail waits. When the review wait elapses it goes to batch review.

## Existing-path coverage

- **The watch.** Its five-argument call of `merge-approved.sh`, its routing in `SKILL.md`, its settle period in poll mode and its grant are unchanged. The five-argument test cases in `tools/test_merge_approved.sh` stay as they are.
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
| CI red | `MERGE=wait:checks-failed` on the pinned head. | First time: one fix-up run for failed checks, unless halted, in which case the pull request waits. With a CI fix-up already recorded: batch review, reason `checks-failed`. |
| Issue edited after claim | `body_sha256` of the current title and body differs from the latest claim marker's, checked before every merge attempt. | No merge. Batch review, reason `issue-edited`. The strain kept its captured text. |
| Malformed settings file | A user settings file does not parse, or its `env` or a merge value has the wrong type. | No merge this tick. The queue report names the file. No label changes. |
| Merge-script error | `MERGE_ERROR=`, a non-zero exit, no line, or an unknown line. | No change. Retried next tick. The review wait bounds the retries. |
| Unrecorded or moved head | GitHub's head differs from the pinned head, or the script prints `MERGE=wait:head-moved`. | No merge. With no fix-up run in flight: batch review, reason `unrecorded-head`. |
| Invalid result | The schema check fails, or a Lair pull request check or the ancestor check fails. | Delivery: `lair:failed`, outcome `invalid-result`, the pull request unrecorded. Fix-up: batch review, reason `fixup-failed`. Both count toward the breaker. |
| Failed or parked fix-up run | The fix-up end marker's outcome. | Batch review, reason `fixup-failed` or `fixup-parked`. A failure counts toward the breaker; a park does not. |
| Lost settle cache | No cache entry, or one for another head. | A new `re-arm` snapshot. The quiet period starts again. The merge is delayed by at least 600 seconds, never taken early. A lost merge-pending mark can let one more merge call run for a queued head, with the same `--match-head-commit`. |
| Pull request closed unmerged | GitHub shows `CLOSED`. | Issue `lair:handoff`, outcome `pr-closed`, not counted toward the breaker. The lane is freed. |
| Elapsed review wait | 3600 seconds since the `ended_at` of the run that recorded the pinned head, with no merge. | Batch review, reason `review-wait-elapsed`. |
| Auto-tier script error | `TIER_ERROR=` or a non-zero exit. | No merge this tick. The review wait bounds it. |
| Review-finding fix-up cap reached | The count of `fixup-review` start markers for the pull request equals the cap when #610's trigger fires. | Batch review, reason `fixup-cap`. |

## Decisions

A decision that is not ADR-worthy names the [P20](../../engineering-principles.md) condition it fails.

- **The tick runs `merge-approved.sh`.** ADR-0044 decision 17, amending decisions 2 and 10.
- **The tick's settle check equals decision 1.** ADR-0044 decision 18.
- **The expected-head argument.** ADR-0044 decision 19, amending decisions 4 and 9.
- **The tick routes its own result by this design's table.** ADR-0044 decision 20, amending decision 10.
- **Merge settings come only from the user's two settings files.** ADR-0044 decision 17. ADR-0045 decision 12's "re-reading `HIVEMIND_AUTO_MERGE` and `HIVEMIND_AUTO_MERGE_ADMIN` every tick" holds as written.
- **The auto-tier inputs.** ADR-0045 decision 12. The input sources are not ADR-worthy: each fails P20's hard-to-reverse condition.
- **A Lair pull request is one the Lair recorded after checking it.** ADR-0045 decision 12. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **No merge after an issue edit.** Extends ADR-0045 decision 10. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The CI-red rule: one fix-up run for failed checks, then batch review.** Extends ADR-0045 decision 13. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The halt and breaker stop claims and fix-up runs; merges continue.** ADR-0045 decision 17 as written: the halt stops new claims, and unsetting auto-merge stops merges.

No ADR-0045 change is needed. Decision 12 already names the script, the per-tick settings read and the auto-tier conditions; decision 13 already starts fix-up runs; decision 17 already separates the halt from the merge stop. This design fills in how; it reverses none of them.

### Tier A answers

The user answered A to each question on 2026-11-21:

- **Q1.** Amend ADR-0044 decisions 2 and 10 so the Lair's tick may run `merge-approved.sh`. Applied as ADR-0044 decisions 17 and 20.
- **Q2.** A settle check equal to ADR-0044 decision 1: the watch's change check against a saved snapshot each tick, 600 quiet seconds, and a lost cache only delays a merge. Applied as decision 18 and the Settle check component.
- **Q3.** An optional sixth expected-head argument; a different head prints `MERGE=wait:head-moved` with no merge call. Applied as decision 19.
- **Q4.** Merge settings only from the user's `.claude/settings.local.json`, then `~/.claude/settings.json`, with a PRD Credentials note. Applied under Contracts and seams, with the note under Changes to shared documents.
- **Q5.** Protected paths from a trunk list plus a fixed floor; the bump from the version-file diff. Applied in the Auto-tier script component.
- **Q6.** Local-review proof is the delivery run's recorded head plus heads the Lair's own fix-up runs recorded. Applied in the Auto-tier script component.
- **Q7.** Only a pull request the Lair recorded on the claimed issue after checking it against GitHub may merge. Applied under Contracts and seams.
- **Q8.** No merge after an issue edit; the pull request goes to batch review. Applied as step 9 of the merge-lane step.
- **Q9.** One fix-up run for failed checks, then batch review. Applied as the CI-red rule.
- **Q10.** The halt and the breaker stop claims and fix-up dispatch; merges continue; unsetting auto-merge stops merges. Applied in Lifecycle stage 4.

### Decided for you

Each of these is listed for veto. None is ADR-worthy: each fails P20's hard-to-reverse condition, as a script constant, a marker field or a routing row that a later change can alter.

- **The review marker is authoritative and final.** The Lair never merges a pull request that has one, even if the label is removed.
- **Markers go on the claimed issue, never the pull request.** One place to read, under one marker rule.
- **The review wait is 3600 seconds**, the watch's `max_watch_duration` default (ADR-0029 decision 3), measured from the recording run's `ended_at`, so it survives a lost cache.
- **The routing rows.** No checks, conflicts, a blocked merge and a refused merge go to batch review. A script error, malformed output and `merge-pending` wait, bounded by the review wait. `skipped:bad-setting` is handled like `off`.
- **`merge-pending` makes no second merge call** for the same head while the cache marks it.
- **The issue-edit and settle checks run last**, just before the merge call, and the few seconds left between their reads and that call are a known limit (Merge-lane step of the tick), decided by the run on a local-review finding.
- **The head check goes first** in `merge-approved.sh`, before gate 1, so a moved head never yields another gate line.
- **`HIVEMIND_PR_REVIEWERS` comes from the same two user files** as the merge keys (ADR-0043 decision 2), and the reviewer filter is `automated`.
- **The clean environment** holds `PATH`, `HOME`, the `gh` auth variables when set, and the three keys.
- **The settle snapshots use the `re-arm` arm kind** and are keyed by pull request and pinned head.
- **The trunk file is `.github/lair.json`.** It holds `protected_paths` (exact paths or directory prefixes, no globs) and `version_files`. A missing or unparseable file sends every pull request to batch review. The list contents for this repository are proposed in #605's pull request.
- **The protected-path floor** is `.github/`, `.claude/`, `CLAUDE.md`, `.mcp.json`, `.gitmodules` and `.gitattributes`.
- **A major bump is a rise in the major component** of any declared version file. A missing, unparseable or lower value goes to batch review.
- **A fix-up head counts as reviewed only when the claim's local-review head is not null**, so a fix-up run cannot launder a skipped local review.
- **A fix-up head is recorded only when the previous recorded head is its ancestor.**
- **The outcome mapping.** `blocked`, `no-pr` and an invalid result give `lair:failed` and count toward the breaker. A pull request closed unmerged gives `lair:handoff` and does not count. Extends ADR-0045 decisions 16 and 17.
- **A complete run's draft pull request goes to batch review with reason `draft`** and does not hold the lane.
- **A fix-up park goes to batch review.** It is not answerable, not a `readiness:needs-decision` move, and not counted toward the third-park handoff.
- **The review-finding fix-up cap is the `loop-state.sh floor` value** per pull request.
- **The test layout and suite names** under Verification strategy.

### Changes to shared documents

None of these is applied in this pull request.

1. **PRD Credentials bullet.** Target: [docs/prds/autonomous-ready-issue-loop.md](../../prds/autonomous-ready-issue-loop.md), Implementation Decisions, the bullet that begins "**Credentials.**". Replace its second sentence, "Merges follow the user's existing merge settings, the admin bypass included, read fresh each tick.", with: "Merges follow the user's own merge settings, read fresh each tick from `.claude/settings.local.json` and then `~/.claude/settings.json`, never from the committed settings, the admin bypass included." Answer: Tier A, Q4, approved 2026-11-21.
2. **Amendments pointer.** Target: [solution-design.md](solution-design.md), section Amendments, a new paragraph after its last line: "2026-11-21: For the merge lane, [merge-lane-design.md](merge-lane-design.md) supersedes the parts its opening paragraph names: the Merge lane and auto tier component, the GitHub-record, park and halt side of Post-PR remediation strains, the Auto-tier script result contract, the merge-settings channel, the merge steps of Lifecycle stages 1, 3 and 4, three Failure modes rows and three Decisions. ADR-0044's amendment of the same date lets the Lair's tick run `merge-approved.sh`." Answer: decided for you, listed for veto.
3. **Round-3 dispositions.** Target: [review-record.md](review-record.md), the Disposition column of the Round 3 tables, and the `open_counts` front matter recomputed to match. Each `open` cell below becomes the text given:
   - A3-2, B3-5 and B3-6: "fixed: merge-lane-design.md, Settle check, Pinned head and Routing table".
   - A3-3 and B3-7: "fixed: merge-lane-design.md, Merge settings source".
   - A3-10 and B3-8: "fixed: merge-lane-design.md, Auto-tier script".
   - B3-4: "fixed: merge-lane-design.md, Lair pull request".
   - A3-8: "fixed: merge-lane-design.md, Exits".
   - A3-13: "fixed: merge-lane-design.md, Exits (`lair:review` on the pull request)".
   - B3-13: "fixed: merge-lane-design.md, Run outcome to labels".
   - B3-14: "fixed: merge-lane-design.md, Fix-up runs and Lifecycle stage 4".

   A3-12 stays open: two of its three calls were asked as Q8 and Q9, and the session-scoped breaker is not in this scope. Answer: decided for you, listed for veto.
4. **Lair pull request term.** Target: [CONTEXT.md](../../../CONTEXT.md), section Language, a new entry after the **Lair** entry, in the glossary's three-line form:

   ```text
   **Lair Pull Request**:
   A pull request the **Lair** recorded on its claimed issue after checking a strain's complete result against GitHub: same repository, trunk base, the Lair's own login as author, and the result's branch and head. Only a Lair Pull Request can hold the Lair's merge lane or be merged by the Lair.
   _Avoid_: strain PR, factory PR
   ```

   Answer: decided for you, listed for veto.

## Verification strategy

The tests follow the PRD's [Testing Decisions](../../prds/autonomous-ready-issue-loop.md#testing-decisions) "Merge tests" and controller-tick tests. All run offline against recorded GitHub states, with no live GitHub.

- **Expected-head cases in `tools/test_merge_approved.sh`:**
  - a sixth argument equal to the head merges, with `--match-head-commit` equal to it;
  - a different head prints `MERGE=wait:head-moved` with one read and no merge call, even when the read's rollup is failed;
  - a malformed sixth argument prints `MERGE_ERROR=bad-expected-head` with no `gh` call;
  - seven arguments print `MERGE_ERROR=bad-arguments`;
  - a refused plain merge whose re-read head differs prints `MERGE=wait:head-moved`.

  One more property is checked over every case: with a sixth argument, every merge call's `--match-head-commit` equals it. The five-argument cases are unchanged.
- **Auto-tier test runner, `tools/test_auto_tier.sh`, with fixtures in `tests/auto-tier/`:**
  - The runner builds scratch git repositories, and each case asserts the one output line.
  - Protected paths: a floor path; a trunk-list path; a list entry added on the pull request head, which is ignored; a rename into a protected directory.
  - Trunk file: missing, or unparseable.
  - Bump: major, minor, and an unreadable or lower version.
  - Local review: the delivery's local-review head; a fix-up head; a fix-up head with a null local-review head; an unrecorded head.
  - Several reasons at once, in their fixed order.
  - Errors: no merge base, a commit that is not present, and bad arguments.
- **Merge-lane tick tests, `tools/test_lair_merge_lane.sh`, with fixtures in `tests/lair-merge-lane/`:**
  - A PATH-shim `gh` serves recorded GitHub states, and fake merge and poll scripts record their argv and environment.
  - Routing: every row of the routing table, plus a check that the table names every `MERGE=` line listed in `merge-approved.sh`'s output contract.
  - Merge settings: the local file winning; the user file used alone; an empty local value overriding the user's; committed settings ignored; a key in the Lair's environment ignored; an unparseable file meaning no merge; the clean environment holding only the allowed names.
  - Settle check: the first sighting; `UNCHANGED` under 600 seconds and at 600 seconds, on an injected clock; each resetting marker; a lost cache; `CHECK_ERROR`.
  - Pinned head: equal, moved, unrecorded, and a fix-up head that is not a descendant.
  - Lair pull request checks: a fork, a wrong base, another author, a branch mismatch and a head mismatch.
  - Issue edit before merge, the draft and closed-unmerged exits, and the review wait.
  - Fix-up runs: the CI-red rule; the review-finding cap; fix-up run outcomes and the breaker count; the halt and the breaker stopping fix-up runs while merges continue.
- **Registration in `tools/validate.sh`, for each new suite:**
  - a constant: `SUITE_TEST_AUTO_TIER='test_auto_tier.sh'` and `SUITE_TEST_LAIR_MERGE_LANE='test_lair_merge_lane.sh'`;
  - an entry in `ALL_SUITES` and in `KNOWN_SUITES`;
  - a `map_path` rule routing the script, its test and its fixture directory to the suite; the merge-lane rule also routes `merge-approved.sh`, whose output contract that test reads;
  - a `self_test` probe: `tests/auto-tier/README.md` and `tests/lair-merge-lane/README.md`.

  `tools/test_validate_suites.sh` runs with the new entries.

## Seam order

The design changes these slices. The ADRs each one touches were confirmed by reading them. #607 is unchanged.

| Slice | Change | ADRs |
| --- | --- | --- |
| #604 | Strain settings set the merge keys to empty strings and deny access to the two user settings files and the Lair's cache; the result gains `local_review_head`. | ADR-0045 decisions 4 and 5; ADR-0044 decision 17; ADR-0010, amendment 2026-10-31 |
| #605 | The merge-lane step, the settle check, the auto-tier script, the expected-head argument, the routing table, the merge settings source and their tests. | ADR-0044 decisions 1, 4, 6, 9, 10, 14, 16 and 17 to 20; ADR-0045 decision 12; ADR-0043 decision 2; ADR-0029 decision 3; ADR-0020, amendment 2026-09-29 |
| #606 | Under the release-train mode, the auto tier's bump input must come from the change fragments; #606 defines it. | ADR-0045 decisions 12 and 15 |
| #608 | The tick calls the merge-lane step under the lock, reads the halt file before fix-up dispatch, and writes the run-end fields and the outcome mapping. | ADR-0045 decisions 2, 12, 16 and 17; ADR-0044 decision 17 |
| #609 | Park counting and answer handling ignore fix-up parks. | ADR-0045 decisions 7 and 11 |
| #610 | Fix-up runs gain start and end markers, the CI-red rule, the review-finding cap, the park route and the halt rule. | ADR-0045 decisions 13 and 17; ADR-0040 decision 2 |
| #611 | The breaker counts fix-up failures, `blocked`, `no-pr` and invalid results, and not `pr-closed`; the digest notes `--admin` merges. | ADR-0045 decisions 14 and 17 |
| #612 | Each parallel pull request keeps its own pinned head, settle cache and auto-tier run against the current trunk. | ADR-0045 decisions 12 and 15; ADR-0044 decision 19 |

## Open questions

None

## Amendments

This design was written with ADR-0044's amendment of 2026-11-21 (decisions 17 to 20) and the user's Tier A answers of the same date. Later changes to this design are appended here as dated entries.
