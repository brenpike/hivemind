# Solution design: Lair — Software Factory

This is the solution design for the Lair, epic #603. It covers the HOW that the slices share. It links the [PRD](../../prds/autonomous-ready-issue-loop.md) and [ADR-0045](../../adr/0045-lair-software-factory.md) rather than restating them, cites them as "ADR-0045 decision N", and adds only what they lack. The design review is recorded in the [review record](review-record.md).

Three part designs govern parts of this design: [strain launch](strain-launch-design.md) (#630), the [merge lane](merge-lane-design.md) (#631) and [claim integrity](claim-integrity-design.md) (#632). Each part this design hands to one of them is a link to the part design and section that govern it. Where several part designs govern one place, the text names the aspect each one governs. Seams between the part designs, under Contracts and seams, states how they fit where they disagree.

## Context and code truth

The Lair builds on this code, as it stands on trunk:

- `plugin/skills/spawn-brood/scripts/spawn-brood.sh` starts each strain as a detached tmux session running `claude` in auto mode in its own worktree. It copies the coordinator's `.claude/settings.local.json` into every strain worktree. What its per-brood settings file holds is in [strain launch](strain-launch-design.md), Context and code truth, "Correction to the parent design".
- `plugin/skills/brood-status/scripts/brood-status-collect.sh` reports, per strain, whether the tmux session is alive, the pull request state and the run ledger state. It reads no run result, so for the Lair it gives liveness only: it cannot tell a run end, a park or a stall apart.
- `plugin/skills/github-review-loop/scripts/merge-approved.sh` is the only merge path. It reads `HIVEMIND_AUTO_MERGE` (the merge method) and `HIVEMIND_AUTO_MERGE_ADMIN` (by presence) each time it runs. Its tests are `tools/test_merge_approved.sh`.
- `plugin/workflow-src/lib/decide.js`, with `plugin/references/decision-autonomy-table.json`, has the levels `high`, `balanced` and `low`. An unknown level resolves to `low`. Its only actions are `take` and `ask`. There is no `unattended` level and no park action.
- `plugin/hooks/hooks.json` holds `PreToolUse` hooks only. There is no `Stop` hook.
- `plugin/agents/overlord.md` holds the `## Instinct` path, which asks the user which delivery path to take, and the `## Resume On Start` path. It also holds the default post-PR watch under `## Review Remediation Posture`.
- `plugin/skills/triage-backlog/scripts/triage-ops.sh` defines the `readiness:*` labels and `type:epic`. It defines no `lair:*` family.
- `plugin/skills/prd-to-issues/scripts/subissue-ops.sh` creates the epic and attaches slices as native sub-issues through the GraphQL `addSubIssue` mutation. It creates no native blocked-by link: `plugin/skills/prd-to-issues/SKILL.md` writes blocked-by as `#N` refs in a slice's `## Dependencies` section.
- The standard-delivery launch in `plugin/workflow-src/standard-delivery/main.js` already takes settled decisions and a draft flag. `decisions` is a list of 1 to 10 non-blank strings of at most 2000 code points each, held as `run.decisions`. `draft` is a boolean that defaults to false.
- No readiness check exists yet. It is built under #615.
- Nothing under `plugin/` reads `HIVEMIND_LAIR_STRAIN` or uses a `lair:*` label.

## Components

### Strain launch and settings

Built by #604. [Strain launch](strain-launch-design.md) governs it: Components "Strain launch and settings", "Launch inputs" and "Start points".

### Strain result and liveness

Built by #604. Each aspect has its own governing part:

- the result and the liveness files: [strain launch](strain-launch-design.md), Components "Strain result and liveness";
- crash and stall detection: [claim integrity](claim-integrity-design.md), Design invariants (Claim state) and Lifecycle (the run checks);
- when the Lair removes a run's worktree: never before the run's outcome marker is written, per the [merge lane](merge-lane-design.md), Contracts and seams "Lair pull request" (Result recording) and Decided for you (R37), with strain launch's Lifecycle step 5 after it.

### Unattended autonomy level

Built by #607. It adds the `unattended` level to the autonomy table and the park action to `decide()`. The level is selected only by `HIVEMIND_LAIR_STRAIN` (ADR-0045 decision 6). The governance and agent edits that replace the overlord's Instinct fallback, Resume On Start question and post-PR watch for a verified strain are under [strain launch](strain-launch-design.md), Components "Unattended governance edits". Park types follow ADR-0045 decision 7, and the architectural gate follows ADR-0045 decision 8. With the marker absent, the levels and actions are today's.

### Controller tick and admission

Built by #608. The controller is a deterministic script in a tmux window (ADR-0045 decision 2). #608 covers:

- the tick loop, in the one tick order under Seams between the part designs, item 5;
- the single-instance lock, the claim, the readiness-check call, the injection scan, labels and marker comments, the halt file, the wall-clock budget, the start-up sweep and the queue report, which [claim integrity](claim-integrity-design.md) governs: its Components and Lifecycle;
- the change to `triage-ops.sh` so that triage leaves `lair:*` issues alone (ADR-0045 decision 16).

Admission reads native blocked-by links only (ADR-0045 decisions 2 and 10). A `#N` ref in a `## Dependencies` section is not read.

### Merge lane and auto tier

Built by #605. The [merge lane](merge-lane-design.md) governs it: Components "Merge-lane step of the tick", "Settle check" and "Auto-tier script", and Contracts and seams "Lair pull request", which holds the lane rule.

### Park answer round trip

Built by #609. A park writes the park marker comment. Its form and signature follow [claim integrity](claim-integrity-design.md), Contracts and seams ("Marker comment", "Counting rule"), and its label moves follow claim integrity's Lifecycle (run end). An answer counts only as ADR-0045 decision 11 states, against a counting park marker. Relabeling `readiness:ready` re-admits the issue. The Lair alone builds the settled decisions from the answers ([strain launch](strain-launch-design.md), Contracts and seams, "Settled decisions"), and the re-claimed run continues on the pushed branch (strain launch, Start points). A third park, or an `approval` park, hands the issue off (ADR-0045 decision 7).

### Post-PR remediation strains

Built by #610. The tick polls each open Lair pull request. What starts a remediation is Seams between the part designs, item 2. Each aspect has its own governing part:

- the dispatch, the launch, the settings, the author filter and the result contract: [strain launch](strain-launch-design.md), Components "Remediation strain launch";
- the markers, the park route, the halt and the outcome mapping of each remediation run, a fix-up run: the [merge lane](merge-lane-design.md), Components "Fix-up runs" and Lifecycle "Run outcome to labels".

### Decision digest and circuit breaker

Built by #611. Each Lair session produces a digest of every decision taken for the user, with its issue and pull request (ADR-0045 decision 14). The circuit breaker follows [claim integrity](claim-integrity-design.md), Components "Halt file and circuit breaker" and its Lifecycle rules for the halt and the breaker, with the outcomes it counts and skips under Seams between the part designs, item 4.

### Release-train versioning mode

Built by #606. It is the opt-in mode of ADR-0045 decision 15: each pull request adds a change fragment, and a script-built release pull request applies the highest bump. Its open choices are deferred to #606, as recorded under Decisions.

### Parallel strains

Built by #612, after #606. More than one strain runs at once. Parallel Lair pull requests merge in sequence, each up to date with trunk and green on its merged head, per the PRD's Parallelism criterion.

## State and ownership

GitHub alone is authoritative (ADR-0045 decision 2). Every local file is a cache, a control input or a hand-off from a strain, except the marker key, the one local item the Lair cannot rebuild from GitHub ([claim integrity](claim-integrity-design.md), State and ownership).

| State | Writer | Readers | Authoritative |
| --- | --- | --- | --- |
| Labels | The user through triage writes `readiness:ready` and `type:*`. The Lair writes the other `readiness:*` moves and every `lair:*` label. | Lair, triage, user | yes |
| Answer comments | User with write permission | Lair only | yes, when the answer rule admits them |
| Captured issue text and its hash | Lair, at claim; the hash also goes into the claim marker | Strain, as its request; Lair | no; the hash in the claim marker is |

The part designs govern every other row, each in its State and ownership section:

- [claim integrity](claim-integrity-design.md): the claim, outcome, park and handoff marker comments, the `lair:claimed` label, the marker key, the halt file, the lock, the scanner files, the queue report and the session records, which replace the local cache;
- [strain launch](strain-launch-design.md): the strain record, the launch file, the settings fragment and strain settings, the result file, the liveness files, the worktree and its local branch ref, and the remediation dispatch marker, which is a fix-up start marker (Seams between the part designs, item 1);
- the [merge lane](merge-lane-design.md): its run-end, fix-up, review and exit markers, the run-end and fix-up end markers being outcome markers (Seams between the part designs, item 1), the `lair:review` label, the merge settings, the settle cache, the lane order, the lane-holder set and the Lair git repository.

## Contracts and seams

Fields and seams only. Each slice builds the code.

- **Strain result.** [Strain launch](strain-launch-design.md), Contracts and seams, "Strain result", extended by `local_review_head` ([merge lane](merge-lane-design.md), "Assumptions about #630").
- **Lair-written settings.** Strain launch, Contracts and seams, "Strain settings" and "Strain environment".
- **Claim marker comment.** [Claim integrity](claim-integrity-design.md), Contracts and seams, "Marker comment", "Marker payload, every kind" and "Counting rule". A run end goes into an outcome marker (Seams between the part designs, item 1).
- **Park marker comment.** Claim integrity, Contracts and seams, "Marker comment" and "Marker payload, every kind", with its question block under Design invariants (Lair-written text).
- **Park record.** `key`, `type` (`decision`, `fact` or `approval`), `question`, `options`, `recommendation`, `branch`, `pr` (a draft pull request or null). The `key` is stable: the same question on the same issue keeps the same key across runs, whatever its wording.
- **Answer form.** `/lair answer <key> <option or text>`. `<key>` names an open park on that issue. A `decision` answer names one option. A `fact` answer is free text.
- **Settled decisions.** Strain launch, Contracts and seams, "Settled decisions".
- **Auto-tier script result.** The merge lane, Components "Auto-tier script".
- **Readiness-check call at claim.** Claim integrity, Contracts and seams, "Readiness-check call at claim".
- **Queue report.** Claim integrity, Contracts and seams, "Queue report".

### Seams between the part designs

Where the part designs disagree, these rules decide. Each names its source.

1. **Markers.** Every Lair marker is append-only and signed, and is posted on the claimed issue ([claim integrity](claim-integrity-design.md), Contracts and seams, "Marker comment" and "Counting rule"; Decisions, "Markers are append-only"). The [merge lane](merge-lane-design.md)'s run-end and fix-up end markers ("Markers the merge lane writes") are claim integrity's outcome markers, and carry the fields the merge lane names for that end. [Strain launch](strain-launch-design.md)'s single write of the outcome, `ended_at`, the baseline and, after a remediation, the end head ("Assumptions about #632") is one appended outcome marker, never an edit of the claim marker. Strain launch's remediation dispatch marker is the merge lane's fix-up start marker, on the issue. Claim-time fields, such as `design_stamps`, go in the claim marker.
2. **What starts a remediation.** One remediation strain per pull request, the user's 2026-11-22 answer in strain launch (Components "Remediation strain launch"; Decisions), decides what starts a remediation, from review feedback or a red CI result. The merge lane's fix-up runs are those runs. They keep their fix-up start and end markers, their CI-red rule (Q9), their park route and their outcome mapping (merge lane, Components "Fix-up runs" and Lifecycle "Run outcome to labels"). A pull request whose one remediation has started gets no second, whatever starts it. The merge lane's R2, no cap on fix-up runs, no longer applies.
3. **A remediation run's budget.** A remediation run's wall-clock budget is timed from its own launch (claim integrity, Lifecycle, the budget check; Decisions). This replaces the merge lane's timing of a fix-up run from the claim marker's `claimed_at`.
4. **The circuit breaker.** As the PRD's Stop controls criterion and the [ADR-0045](../../adr/0045-lair-software-factory.md) amendment of 2026-11-22 both state, the breaker:
   - counts `failed`, `crashed`, `stalled` and `timed-out` outcomes, and any run whose outcome marker does not count;
   - skips `parked`, `blocked`, `no-pr`, `invalid-result` and `not-launched` outcomes, which neither count nor end a streak;
   - ends a streak on a `complete` outcome;
   - covers only runs this Lair session launched.

   This one set replaces the merge lane's ("Stage 4: halt and circuit breaker") and claim integrity's (Lifecycle, the breaker) separate lists. The rest of the breaker follows claim integrity.
5. **One tick order.** Run end and the run checks, then the remediation step (strain launch, Components "Remediation strain launch", "Tick order"), then the merge lane (merge lane, Components "Merge-lane step of the tick"), then claims. In claim integrity's tick (Lifecycle), steps 1 and 2 still come first, the remediation step and the merge lane run in step 3 after the run checks, with park answers after the merge lane, and claims are step 4.
6. **Containment of the key and the halt file.** Per the user's answer A of 2026-11-22 to the key-containment question, #604 keeps every Lair strain and remediation strain out of the `control/` folder of the Lair's state root ([claim integrity](claim-integrity-design.md), Components "Lair state root"). On Linux it runs each one in a sandbox with its own process namespace. Claim integrity's "Assumptions about #630" and the ADR-0045 amendment of 2026-11-22 require both. Strain launch's statement that a strain can read any file the user can read (Contracts and seams, "Strain environment"; Trust boundaries) holds outside that folder.
7. **Orphans and the start-up sweep.** The orphan rule and the start-up sweep follow claim integrity (Design invariants, Claim state; Components "Reconciler and start-up sweep"; Lifecycle). A strain whose kept worktree holds a valid result file whose outcome is unwritten is exempt: the sweep keeps it (strain launch, Components "Remediation strain launch", "A deferred write is not a budget overrun or an orphan"). The Lair removes a run's worktree only after that run's outcome marker is written (merge lane, Decided for you, R37), and then as strain launch's Lifecycle step 5 states.

## Trust boundaries

Only a user with write permission steers the Lair, through these channels:

- the `readiness:ready` label on an unedited issue, as admission (ADR-0045 decision 10 and its 2026-11-21 amendment);
- `/lair answer` comments, as park answers (ADR-0045 decision 11);
- the halt file on the user's own machine (ADR-0045 decision 17);
- the merge settings, only through the user's own settings files on the Lair's machine, as the [merge lane](merge-lane-design.md)'s Trust boundaries state (ADR-0045 decision 12);
- remote control on a Lair strain, as [strain launch](strain-launch-design.md)'s Trust boundaries state;
- the batch review of `lair:review` pull requests, and the decision digest as the veto channel (ADR-0045 decisions 12 and 14).

Strain containment follows strain launch, Trust boundaries, "Strain containment", with the containment of the key and the halt file under Seams between the part designs, item 6. The markers, the key, the scanner session and the halt file follow [claim integrity](claim-integrity-design.md), Trust boundaries. The remaining risks are the [ADR-0045 residuals](../../adr/0045-lair-software-factory.md#residuals) and the residuals its amendments add.

## Lifecycle

Issue labels move as ADR-0045 decision 16 states:

- `readiness:ready` to `readiness:implementation` with `lair:claimed` at claim;
- to `readiness:done` when GitHub shows the pull request merged;
- to `readiness:needs-decision` on an answerable park, keeping `lair:claimed` ([claim integrity](claim-integrity-design.md), Lifecycle, run end);
- `lair:handoff`, `lair:failed` and `lair:review` as each part design maps them:
  - every run end and exit: the [merge lane](merge-lane-design.md), Lifecycle "Run outcome to labels" and "Exits";
  - a suspect scan and an orphan: claim integrity, Lifecycle (claim sequence step 4) and Design invariants (Claim state);
  - a refused start or push, by start kind: [strain launch](strain-launch-design.md), Components "Start points", "Handling by start kind".

A run moves through these stages:

1. **Claim, spawn, run, result, labels, merge.** The tick admits an issue, writes the claim marker and labels, and spawns the strain (claim integrity, Lifecycle, claim sequence). The strain runs standard-delivery unattended and writes its result. The Lair records the run end in an outcome marker, then the labels (the merge lane, Lifecycle "Run outcome to labels"; Seams between the part designs, item 1). It ends the session and cleans up as strain launch's Lifecycle steps 4 and 5 state, under Seams between the part designs, item 7. The merge lane then works the pull request (the merge lane, Components "Merge-lane step of the tick").
2. **Park, answer, re-admit, continue.** A parked result becomes a park marker and a label move. The user answers and relabels `readiness:ready`. Admission runs again, the readiness check included. The new strain starts on the pushed branch with the answers as settled decisions.
3. **Post-PR remediation.** A Lair pull request gets at most one remediation run, under Seams between the part designs, item 2. Its dispatch and launch follow strain launch, Components "Remediation strain launch", and its markers and route follow the merge lane, Lifecycle "Stage 3: post-PR fix-up".
4. **Halt and circuit breaker.** The halt file and the breaker follow claim integrity, Lifecycle, with the outcomes of Seams between the part designs, item 4. Their effect on fix-up runs and merges follows the merge lane, Lifecycle "Stage 4: halt and circuit breaker".
5. **Start-up sweep.** The start-up sweep and the removal of orphaned sessions and worktrees follow Seams between the part designs, item 7.

## Existing-path coverage

- Interactive standard-delivery is unchanged when the `HIVEMIND_LAIR_STRAIN` marker is absent.
- Non-Lair brood strains keep today's behavior. That includes the settings copy noted in PR #613, which this design neither covers nor changes.
- Triage, the review watch and interactive auto-merge are unchanged, except that triage leaves `lair:*` issues alone.

## Failure modes

| Failure | Detection | Resulting state |
| --- | --- | --- |
| Crash | The session side: [strain launch](strain-launch-design.md), Failure modes "Crash". The claim side: [claim integrity](claim-integrity-design.md), Failure modes "Crash, or claim stopped partway". | The outcome `crashed` in an outcome marker (claim integrity). Labels by the [merge lane](merge-lane-design.md), Lifecycle "Run outcome to labels", and for a fix-up run its Failure modes "Fix-up run lost in flight". The pull request's `lair:review` route by strain launch's "Crash" row. Counts toward the breaker (Seams between the part designs, item 4). |
| Stall | The stall rules: strain launch, Failure modes "Stall". The idle signal the Lair acts on: claim integrity, Failure modes "Stall". | The outcome `stalled` in an outcome marker (claim integrity), labels by the merge lane's "Run outcome to labels", and the pull request route by strain launch's "Stall" row. Counts toward the breaker. |
| The `Stop` hook does not fire while a workflow runs in the background | Found while building #604. | The fallback stall rules: strain launch's row of that name. A run with no idle signal is ended `timed-out` by the budget check: claim integrity, Failure modes "Stall". |
| `/exit` sent through tmux does not end a session | Strain launch, Failure modes, the row of that name. | The Lair kills the session, then cleans up under Seams between the part designs, item 7. |
| GitHub API failure or rate limit | Claim integrity, Failure modes "GitHub read failure or rate limit"; for the merge lane, its Failure modes "Failed or incomplete tick read"; for the remediation step, strain launch's Failure modes "Snapshot or pull request read fails on a tick". | As each of those rows states. |
| Lock already held | Claim integrity, Failure modes "Lock already held". | As that row states. |
| Merge refused | The merge lane, Failure modes "Merge refused". | As that row states. |
| CI red | The merge lane, Failure modes "CI red", and strain launch, Failure modes "CI red". | Under Seams between the part designs, item 2: the pull request's one remediation, whose dispatch timing follows strain launch's row and whose routes follow the merge lane's CI-red rule (Components "Fix-up runs"). |
| Issue edited after claim | The merge lane, Failure modes "Issue edited after claim". | As that row states. |
| Edited answer, or an answer from a user without write access | The comment's edit history, or the user's permission. | The answer is ignored and never reaches a strain. The issue stays in `readiness:needs-decision`. |
| Third park | The issue's park marker count reaches 3. | `lair:handoff`; the issue leaves the factory. |
| Budget overrun | The wall-clock budget clock: claim integrity, Lifecycle (the budget check), with a remediation run timed from its own launch (Seams between the part designs, item 3). The agent-call cap and the deferred-write exemption: strain launch, Failure modes "Budget overrun". | The outcome `timed-out` in an outcome marker (claim integrity), labels by the merge lane's "Run outcome to labels", or a park when a parked result was written first. Counts toward the breaker. |
| Orphaned claim | Claim integrity, Failure modes "Orphaned claim", with strain launch's Failure modes "Start-up sweep while an outcome write is deferred". | Under Seams between the part designs, item 7. |
| Stale design, or an epic | Claim integrity, Failure modes "Stale design, or an epic". | As that row states. |

## Decisions

A decision that is not ADR-worthy names the [P20](../../engineering-principles.md) condition it fails.

- **Admission by the readiness check, never an epic.** ADR-0045's 2026-11-21 amendment.
- **Triage leaves `lair:*` issues alone, built in #608.** ADR-0045 decision 16. Placing it in #608 is not ADR-worthy: it fails P20's hard-to-reverse condition.
- **Admission reads native blocked-by links only.** ADR-0045 decisions 2 and 10.
- **Lair strains through the brood tooling, owned by the Lair.** ADR-0045 decision 3, amending ADR-0007.
- **Admission replaces brood strain approval for Lair strains.** ADR-0045 decision 10, amending ADR-0026.
- **The `unattended` level and park action.** ADR-0045 decision 6, amending ADR-0036 decision 8.
- **Merges only through `merge-approved.sh` and its gates.** The [merge lane](merge-lane-design.md)'s Decisions govern it, under ADR-0044 decisions 17 to 20.
- **The exit fallback.** Not ADR-worthy: fails P20's hard-to-reverse condition. It covers an unverified item in the ADR-0045 residuals. Its rule is [strain launch](strain-launch-design.md)'s Failure modes row on `/exit`. The stall fallback is [claim integrity](claim-integrity-design.md)'s, in its Decisions.
- **The queue report contents.** Claim integrity's Decisions govern them.
- **The outcome in an outcome marker, and the circuit breaker scoped to the Lair session.** Claim integrity's Decisions govern both, under Seams between the part designs, items 1 and 4.
- **A red CI result.** The merge lane's Decisions govern the CI-red rule, under Seams between the part designs, item 2.
- **An issue edited after claim is not merged and goes to `lair:review`.** The merge lane's Decisions govern it.
- **The release-train decisions are deferred with full scope to #606.** ADR-0045 decision 15. These are the fragment format, the release cadence, and who triggers the release pull request. #606 and #612 are therefore not ready until a dated entry under Amendments settles them.
- **Markers are append-only, signed and posted on the claimed issue; the merge lane's run-end and fix-up end markers and strain launch's outcome write are outcome markers; the dispatch marker is the fix-up start marker; claim-time fields go in the claim marker.** Seams between the part designs, item 1. Implements ADR-0045 decision 2. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **One remediation strain per pull request decides what starts a remediation; the merge lane's fix-up runs are those runs, and its R2 no longer applies.** Seams between the part designs, item 2. The user's answer A of 2026-11-22 at strain launch's design review round 5.
- **A remediation run's wall-clock budget is timed from its own launch.** Seams between the part designs, item 3. Claim integrity's decision, listed for veto there. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **One set of counted and skipped breaker outcomes.** Seams between the part designs, item 4. The counted outcomes are the PRD's Stop controls criterion and the ADR-0045 amendment of 2026-11-22, which rest on the user's answers of 2026-11-22: yes after claim integrity's design review round 2, and A to the stalled-outcome question. The skipped outcomes, the streak end and the session scope are not ADR-worthy: each fails P20's hard-to-reverse condition.
- **One tick order, with the remediation step before the merge lane.** Seams between the part designs, item 5. The user's answer A of 2026-11-22 at strain launch's design review round 7.
- **#604 keeps every Lair strain and remediation strain out of `control/`, and on Linux runs each in a sandbox with its own process namespace.** Seams between the part designs, item 6. The user's answer A of 2026-11-22 to the key-containment question.
- **The orphan rule and the start-up sweep follow claim integrity, with strain launch's deferred-write exemption and the merge lane's worktree removal after the end marker.** Seams between the part designs, item 7. Not ADR-worthy: fails P20's hard-to-reverse condition.

## Verification strategy

The tests are the PRD's [Testing Decisions](../../prds/autonomous-ready-issue-loop.md#testing-decisions). This section adds only where each test lives:

- Engine tests, for the unattended level, the park action and the settled-decisions launch input, go in `tests/workflow-scripts/`.
- Shell-script tests are `tools/test_*.sh` scripts, such as `tools/test_merge_approved.sh` for the merge lane. New ones cover the strain launch and settings, the result schema, crash and stall detection, the auto-tier script, the park round trip and the controller tick.
- Controller tests use recorded GitHub states, with no live GitHub.
- The live smoke run is by hand, on a throwaway issue in this repository.

## Seam order

The build order is:

1. #604;
2. then #607 and #605;
3. then #608;
4. then #609, #610 and #611;
5. with #606 before #612.

Cross-epic seam: #608's admission needs the readiness check from #615. It is recorded here. The maintainer adds the native blocked-by link.

| Slice | Component heading(s) | ADRs |
| --- | --- | --- |
| #604 | Strain launch and settings; Strain result and liveness | ADR-0045 decisions 3, 4 and 5; ADR-0007 |
| #605 | Merge lane and auto tier | ADR-0045 decision 12; ADR-0044 |
| #606 | Release-train versioning mode | ADR-0045 decision 15 |
| #607 | Unattended autonomy level | ADR-0045 decisions 6, 7 and 8; ADR-0026; ADR-0036 |
| #608 | Controller tick and admission | ADR-0045 decisions 2, 10, 16 and 17 and the 2026-11-21 amendment; ADR-0007; ADR-0026 |
| #609 | Park answer round trip | ADR-0045 decisions 7, 11 and 16 |
| #610 | Post-PR remediation strains | ADR-0045 decision 13 |
| #611 | Decision digest and circuit breaker | ADR-0045 decisions 14 and 17 |
| #612 | Parallel strains | ADR-0045 decisions 12 and 15; ADR-0007 |

## Open questions

None

## Amendments

This design was written with the ADR-0045 amendment of 2026-11-21, which excludes epics from admission and requires a passing readiness check at claim time. Later changes to this design are appended here as dated entries.
