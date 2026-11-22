# Solution design: Lair — Software Factory

This is the solution design for the Lair, epic #603. It covers the HOW that the slices share. It links the [PRD](../../prds/autonomous-ready-issue-loop.md) and [ADR-0045](../../adr/0045-lair-software-factory.md) rather than restating them, cites them as "ADR-0045 decision N", and adds only what they lack. The design review is recorded in the [review record](review-record.md).

Three part designs govern parts of this design: [strain launch](strain-launch-design.md) (#630), the [merge lane](merge-lane-design.md) (#631) and [claim integrity](claim-integrity-design.md) (#632). Each part this design hands to one of them is a link to the part design and section that govern it. Where several part designs govern one place, the text names the aspect each one governs. Seams between the part designs, under Contracts and seams, states how they fit where they disagree. Each part design is frozen: a change to one lands only with a dated entry under Amendments here, which edits this stamped design and so stales the review record.

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
- crash and stall detection: [claim integrity](claim-integrity-design.md), Design invariants (Claim state) and Lifecycle (the run checks), with the idle signal of Seams between the part designs, item 13;
- when the Lair removes a run's worktree: never before the run's outcome marker is written, per the [merge lane](merge-lane-design.md), Contracts and seams "Lair pull request" (Result recording) and Decided for you (R37), with strain launch's Lifecycle step 5 after it.

### Unattended autonomy level

Built by #607. It adds the `unattended` level to the autonomy table and the park action to `decide()`. The level is selected only by `HIVEMIND_LAIR_STRAIN` (ADR-0045 decision 6). The governance and agent edits that replace the overlord's Instinct fallback, Resume On Start question and post-PR watch for a verified strain are under [strain launch](strain-launch-design.md), Components "Unattended governance edits". Park types follow ADR-0045 decision 7, and the architectural gate follows ADR-0045 decision 8. With the marker absent, the levels and actions are today's.

### Controller tick and admission

Built by #608. The controller is a deterministic script in a tmux window (ADR-0045 decision 2). #608 covers:

- the tick loop, in the one tick order under Seams between the part designs, item 5;
- the single-instance lock, the claim, the readiness-check call, the injection scan, labels and marker comments, the halt file, the wall-clock budget, the start-up sweep and the queue report, which [claim integrity](claim-integrity-design.md) governs: its Components and Lifecycle;
- the change to `triage-ops.sh` so that triage leaves `lair:*` issues alone (ADR-0045 decision 16).

The no-open-blocker condition of admission reads native blocked-by links only (ADR-0045 decisions 2 and 10). The readiness check reads `## Dependencies` refs only to require their edges.

### Merge lane and auto tier

Built by #605. The [merge lane](merge-lane-design.md) governs it: Components "Merge-lane step of the tick", "Settle check" and "Auto-tier script", and Contracts and seams "Lair pull request", which holds the lane rule.

Per the user's answer 2A of 2026-11-22, the auto-tier script's fixed floor (merge lane, Components "Auto-tier script", "The floor") also holds the directories `docs/prds/`, `docs/initiatives/` and `docs/adr/`, built by #605. So ADR-0046's rule that a docs pull request never takes the Lair's auto tier holds in every consumer project, whatever its `.github/lair.json` lists.

### Park answer round trip

Built by #609. A park writes the park marker comment. Its form and signature follow [claim integrity](claim-integrity-design.md), Contracts and seams ("Marker comment", "Counting rule"), and its label moves follow claim integrity's Lifecycle (run end), for a remediation run's park too, in the write order of Seams between the part designs, items 8 and 10. An answer counts only as ADR-0045 decision 11 states, against a counting park marker. Relabeling `readiness:ready` re-admits the issue. The Lair alone builds the settled decisions from the answers ([strain launch](strain-launch-design.md), Contracts and seams, "Settled decisions"), and the re-claimed run continues on the pushed branch (strain launch, Start points). A third park, or an `approval` park, hands the issue off (ADR-0045 decision 7).

### Post-PR remediation strains

Built by #610. The tick polls each open Lair pull request. What starts a remediation is Seams between the part designs, item 2. Each aspect has its own governing part:

- the dispatch, the launch, the settings, the author filter and the result contract: [strain launch](strain-launch-design.md), Components "Remediation strain launch";
- the markers, the park route, the halt and the outcome mapping of each remediation run, which the merge lane calls a fix-up run: the [merge lane](merge-lane-design.md), Components "Fix-up runs" and Lifecycle "Run outcome to labels", under Seams between the part designs, items 2, 3 and 10.

### Decision digest and circuit breaker

Built by #611. Each Lair session produces a digest of every decision taken for the user, with its issue and pull request (ADR-0045 decision 14). Run end copies each run's `decisions` from its result file into the session's digest before clean-up removes the file. Each run's entry takes its trust from the run's outcome marker: it is listed as `unverified` when that marker does not count ([claim integrity](claim-integrity-design.md), Contracts and seams, "Reader failure direction"). The circuit breaker follows [claim integrity](claim-integrity-design.md), Components "Halt file and circuit breaker" and its Lifecycle rules for the halt and the breaker, with the outcomes it counts and skips under Seams between the part designs, item 4.

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
- [strain launch](strain-launch-design.md): the strain record, the launch file, the settings fragment and strain settings, the result file, the liveness files, the worktree and its local branch ref, and the remediation dispatch marker, which is a remediation run's start marker (Seams between the part designs, item 1);
- the [merge lane](merge-lane-design.md): its run-end, fix-up start, fix-up end, review and exit markers, the run-end and fix-up end markers being outcome markers (Seams between the part designs, item 1), the `lair:review` label, the merge settings, and the settle cache, the lane order, the lane-holder set and the Lair git repository, which are kept under `control/` (Seams between the part designs, item 6).

## Contracts and seams

Fields and seams only. Each slice builds the code.

- **Strain result.** [Strain launch](strain-launch-design.md), Contracts and seams, "Strain result", extended by `local_review_head` ([merge lane](merge-lane-design.md), "Assumptions about #630").
- **Lair-written settings.** Strain launch, Contracts and seams, "Strain settings" and "Strain environment".
  - ADR-0045 decision 4 as amended, which sets the merge keys to empty values, governs over the part designs' older Assumptions about #630 that the strain settings carry no merge key: the merge lane's "No merge key takes effect in a strain" and claim integrity's "Strain settings and environment".
- **Claim marker comment.** [Claim integrity](claim-integrity-design.md), Contracts and seams, "Marker comment", "Marker payload, every kind" and "Counting rule". A run end goes into an outcome marker (Seams between the part designs, item 1).
- **Park marker comment.** Claim integrity, Contracts and seams, "Marker comment" and "Marker payload, every kind", with its question block under Design invariants (Lair-written text).
- **Park record.** `key`, `type` (`decision`, `fact` or `approval`), `question`, `options`, `recommendation`, `branch`, `pr` (a draft pull request or null).
  - The engine builds the `key` from the stop's identity, never from model text: the stop kind, and for a step stop the step and the cause code (ADR-0045 decision 6).
  - The `key` matches `^[a-z0-9][a-z0-9-]{0,63}$` (claim integrity, Design invariants, Lair-written text).
  - So the same stop on a re-claim of the same issue gives the same key, whatever the question's wording.
- **Answer form.** `/lair answer <key> <option or text>`. `<key>` names an open park on that issue. A `decision` answer names one option. A `fact` answer is free text.
- **Settled decisions.** Strain launch, Contracts and seams, "Settled decisions".
- **Auto-tier script result.** The merge lane, Components "Auto-tier script".
- **Readiness-check call at claim.** Claim integrity, Contracts and seams, "Readiness-check call at claim".
- **Queue report.** Claim integrity, Contracts and seams, "Queue report".

### Seams between the part designs

Where the part designs disagree, these rules decide. Each names its source.

1. **Markers.** Every Lair marker is append-only and signed, and is posted on the claimed issue ([claim integrity](claim-integrity-design.md), Contracts and seams, "Marker comment" and "Counting rule"; Decisions, "Markers are append-only"). Their payload is claim integrity's (Contracts and seams, "Marker payload, every kind"), with these additions:
   - Three more kinds: `fixup-start`, a remediation run's start marker, which is also strain launch's remediation dispatch marker, with `run` the remediation run's id; `review`, the merge lane's review marker; and `exit`, its exit marker. Each carries the nonce of a counting claim marker on the same issue, as an `outcome` or `park` marker does under the counting rule.
   - The [merge lane](merge-lane-design.md)'s run-end and fix-up end markers ("Markers the merge lane writes") are `outcome` markers. They carry the fields the merge lane names for that end, and `outcome` also takes the values `no-pr`, `invalid-result` and `not-launched`.
   - The merge lane's field names map onto claim integrity's: `claim_nonce` is `nonce`, `run_nonce` is `run`, and `claimed_at`, `started_at` and `dispatched_at` are `at`. The merge lane's start-marker `kind`, `fixup-checks` or `fixup-review`, is not carried, since under item 2 no rule reads which trigger started the run.

   [Strain launch](strain-launch-design.md)'s single write of the outcome, `ended_at`, the baseline and, after a remediation, the end head ("Assumptions about #632") is one appended outcome marker, never an edit of the claim marker. Strain launch's remediation dispatch marker is posted on the issue. Claim-time fields, such as `design_stamps`, go in the claim marker.
2. **What starts a remediation.** This design calls a remediation strain's run a remediation run, as the PRD and strain launch do. The merge lane's fix-up run names the same run, and its fix-up start and end markers are the remediation run's start and end markers. One remediation strain per pull request, the user's 2026-11-22 answer in strain launch (Components "Remediation strain launch"; Decisions), decides what starts a remediation, from review feedback or a red CI result. The merge lane's fix-up runs are those runs. They keep their start and end markers, their park route and their outcome mapping (merge lane, Components "Fix-up runs" and Lifecycle "Run outcome to labels"). A pull request whose one remediation has started gets no second, whatever starts it:
   - The one remediation is spent once its start marker lands. A dispatch whose start-marker write did not land wrote nothing, and a later tick may dispatch, since strain launch dispatches only when the pull request has no dispatch marker. A start marker that landed with no launch ends `not-launched`, and the pull request goes to `lair:review`, as for every remediation end other than `complete` (strain launch, Components "Start points", "Handling by start kind"). The merge lane's new run after a `not-launched` end no longer applies.
   - The CI-red rule (Q9) never starts a second run. Its step 1 holds for any remediation start marker under the claim, whichever trigger wrote it, and its step 3 starts a run only when the pull request has no start marker.
   - The merge lane's start precondition that the issue's budget has time left, and its `budget-exhausted` route, no longer apply to a remediation run (item 3).
   - Under the halt or a tripped breaker a due dispatch starts no run (merge lane, Lifecycle "Stage 4: halt and circuit breaker"). It does not block the merge lane's step 9: the review wait still sends the pull request to batch review with reason `review-wait-elapsed`.

   The merge lane's R2, no cap on fix-up runs, no longer applies.
3. **A remediation run's budget.** A remediation run's wall-clock budget is timed from its own launch (claim integrity, Lifecycle, the budget check; Decisions). This replaces the merge lane's timing of a fix-up run from the claim marker's `claimed_at`, with its start precondition on the issue's budget and its `budget-exhausted` route.
4. **The circuit breaker.** The breaker:
   - counts `failed`, `crashed`, `stalled` and `timed-out` outcomes, as the PRD's Stop controls criterion and the [ADR-0045](../../adr/0045-lair-software-factory.md) amendment of 2026-11-22 both state;
   - also counts, as a failure, a run this session ended whose outcome marker does not count, a refinement neither the PRD nor ADR-0045 states, decided in claim integrity (Decisions, the breaker and its window, C3-2);
   - skips `parked`, `blocked`, `no-pr`, `invalid-result` and `not-launched` outcomes, which neither count nor end a streak;
   - takes an invalid result as the outcome `invalid-result`, skipped, never as a crash, so strain launch's Failure modes row "Invalid result", "Treated as a crash.", no longer applies;
   - ends a streak on a `complete` outcome of a run end under a live claim, the merge lane's qualifier ("Stage 4: halt and circuit breaker");
   - neither counts nor ends a streak on a remediation run end under a claim that already has a terminal outcome;
   - covers only runs this Lair session launched.

   This one set replaces the merge lane's ("Stage 4: halt and circuit breaker") and claim integrity's (Lifecycle, the breaker) separate lists. The rest of the breaker follows claim integrity.
5. **One tick order.** Run end and the run checks, then the remediation step (strain launch, Components "Remediation strain launch", "Tick order"), then the merge lane (merge lane, Components "Merge-lane step of the tick"), then claims. In claim integrity's tick (Lifecycle), steps 1 and 2 still come first, the remediation step and the merge lane run in step 3 after the run checks, with park answers after the merge lane, and claims are step 4.
6. **Containment of the key, the halt file and the Lair's tmux servers.** Per the user's answer A of 2026-11-22 to the key-containment question and answer 1A of 2026-11-22 at this design's review round 1, #604 builds the containment of every Lair strain and remediation strain, per platform, and the Lair starts none without it. The Lair's tmux sockets are those of every tmux server it starts or uses: the server of its own window, the scanner's server on `control/scan.sock` and the server its strains run on.
   - On Linux, the sandbox with its own process namespace that hides the Lair's processes also hides the `control/` folder of the Lair's state root ([claim integrity](claim-integrity-design.md), Components "Lair state root") and every tmux socket of the Lair. The Lair's own window runs on a tmux server of its own, which no strain can reach (claim integrity, "Assumptions about #630", Tmux reach).
   - On macOS, a `sandbox-exec` profile denies each strain `control/` and the Lair's tmux sockets. The profile does not hide the Lair's processes, so the ADR-0045 amendment of 2026-11-22 on process reach still applies there.
   - #608's environment preflight (strain launch, Components "Strain launch and settings") gains the probe `sandbox`, which checks the containment from inside a session launched as a strain is. When it cannot confirm the containment, on any platform, the Lair claims nothing and stops with cause `strain_env_preflight`, probe `sandbox`.
   - The merge lane's cache, that is the settle cache, the lane order, the lane-holder set and the Lair git repository, moves under `control/`, so no strain can write it. #605 names its folder there; `control/cache/` still holds only the queue report.
   - Under this containment, strain launch's named residual "the tmux global environment" (Trust boundaries) does not apply: no strain reaches a tmux server of the Lair.
   - Claim integrity's assumption "Result file per strain" is not met by this containment. A strain that writes another run's result file falls under strain launch's named residual "a prompt-injected strain holds the user's rights", bounded by the merge lane's result checks (Contracts and seams, "Lair pull request").

   Claim integrity's "Assumptions about #630" and the ADR-0045 amendments of 2026-11-21 on forged markers and of 2026-11-22 on process reach require this containment. Strain launch's statement that a strain can read any file the user can read (Contracts and seams, "Strain environment"; Trust boundaries) holds outside `control/` and the Lair's tmux sockets.
7. **Orphans and the start-up sweep.** The orphan rule and the start-up sweep follow claim integrity (Design invariants, Claim state; Components "Reconciler and start-up sweep"; Lifecycle). A strain whose kept worktree holds a valid result file whose outcome is unwritten is exempt: the sweep keeps it (strain launch, Components "Remediation strain launch", "A deferred write is not a budget overrun or an orphan"). The Lair removes a run's worktree only after that run's outcome marker is written (merge lane, Decided for you, R37), and then as strain launch's Lifecycle step 5 states.
8. **Run-end write order.** Every route that makes more than one write takes the merge lane's Write order (Contracts and seams, "Write order"): a run end, a remediation run end, an exit, a park and a batch review. Its label changes and pull request changes come first, then its markers, and the marker that ends the route last.
   - A run's result file stays in its kept worktree until that last marker lands, so a later tick computes the route again from it and repeats the writes, each idempotent (strain launch, Lifecycle step 5). A run check with no result file computes its route again from the session, the worktree and the clock.
   - Strain launch's `gh pr ready` after a `complete` re-claim result whose pull request is a draft (Components "Start points") is a pull request change made before the run-end mapping reads the draft flag. When it fails, the pull request goes to `lair:review`, as strain launch states.
   - Claim integrity's order at run end and in the run checks (Lifecycle), the outcome marker first and then the labels, no longer applies. Each write still re-reads its guards under claim integrity's invariant Write guards, and the run checks end the session after the outcome marker.
9. **The pull request of a delivery run that did not complete.** Strain launch routes to `lair:review` the pull request of a delivery run that ended `blocked`, `failed`, `crashed`, `stalled`, `timed-out` or with an invalid result (Contracts and seams, "Assumptions about #631"; Failure modes). That route applies only to a pull request that passes the merge lane's Lair pull request checks other than the head: the same repository, not a fork; the trunk base; the Lair's own login as author; and the claim's branch. The Lair leaves any other pull request alone, as the merge lane's "Recorded residual: a pull request no result names" states.
10. **Labels of a remediation run's park.** Claim integrity's rule that an answerable park keeps `lair:claimed` (Lifecycle, run end) applies to a remediation run's park too. The merge lane's removal of `lair:claimed` in its fix-up park rows (Lifecycle "Run outcome to labels") no longer applies. The claim still ends, through the remediation run's end marker with outcome `parked`, a terminal outcome (merge lane, Contracts and seams, "Lair pull request").
11. **A valid result is never timed out.** A valid result file whose result checks or end reads cannot be read yet is never ended `timed-out`. A later tick checks it again, and only that retry writes its outcome (strain launch, Components "Remediation strain launch", "A deferred write is not a budget overrun or an orphan"). The merge lane's rule that a result still unchecked when the budget passes ends the run `timed-out` (Contracts and seams, "Lair pull request", Result recording), and its #608 test of that rule, no longer apply.
12. **The merged exit closes the issue.** The merge lane's merged exit (Lifecycle "Exits") also closes the issue, as strain launch's "Assumptions about #631" require, since the pull request names no issue to close. The close is a write made before the exit marker, under item 8.
13. **The idle signal.** Claim integrity's idle signal ("Assumptions about #630", Idle signal) takes both of strain launch's stall rules (Failure modes "Stall"), the activity rule included: a session alive with no result whose last activity is more than 30 minutes old gives the idle signal. So when the `Stop` hook does not fire, the stall check still ends the run `stalled`; only when the activity hooks do not fire either does the budget check end it `timed-out`. Claim integrity's statement that with no `Stop` hook no idle signal comes no longer applies.

## Trust boundaries

A user with write permission steers the Lair through these channels:

- the `readiness:ready` label on an unedited issue, as admission (ADR-0045 decision 10 and its 2026-11-21 amendment);
- `/lair answer` comments, as park answers (ADR-0045 decision 11);
- the halt file on the user's own machine (ADR-0045 decision 17);
- the merge settings, only through the user's own settings files on the Lair's machine, as the [merge lane](merge-lane-design.md)'s Trust boundaries state (ADR-0045 decision 12);
- remote control on a Lair strain, as [strain launch](strain-launch-design.md)'s Trust boundaries state;
- the batch review of `lair:review` pull requests, and the decision digest as the veto channel (ADR-0045 decisions 12 and 14).

Two more channels reach the Lair from others:

- in-scope reviewer Bots (ADR-0043) and CI check descriptions reach a remediation strain's fix pass, through strain launch's author filter (Components "Remediation strain launch"), scanned before use;
- any commenter, a user without write permission included, can spend a pull request's one remediation strain or send it to `lair:review`, because the seed counts every author but the Lair's login; no comment text reaches a strain this way (strain launch, Components "Remediation strain launch", "The cost").

Strain containment follows strain launch, Trust boundaries, "Strain containment", with the containment of the key, the halt file and the Lair's tmux servers under Seams between the part designs, item 6. The markers, the key, the scanner session and the halt file follow [claim integrity](claim-integrity-design.md), Trust boundaries. The remaining risks are the [ADR-0045 residuals](../../adr/0045-lair-software-factory.md#residuals) and the residuals its amendments add.

## Lifecycle

Issue labels move as ADR-0045 decision 16 states:

- `readiness:ready` to `readiness:implementation` with `lair:claimed` at claim;
- to `readiness:done` when GitHub shows the pull request merged, and the issue is closed (Seams between the part designs, item 12);
- to `readiness:needs-decision` on an answerable park, keeping `lair:claimed` ([claim integrity](claim-integrity-design.md), Lifecycle, run end), a remediation run's park included (Seams between the part designs, item 10);
- `lair:handoff`, `lair:failed` and `lair:review` as each part design maps them:
  - every run end and exit: the [merge lane](merge-lane-design.md), Lifecycle "Run outcome to labels" and "Exits";
  - a suspect scan and an orphan: claim integrity, Lifecycle (claim sequence step 4) and Design invariants (Claim state);
  - a refused start or push, by start kind: [strain launch](strain-launch-design.md), Components "Start points", "Handling by start kind".

A run moves through these stages:

1. **Claim, spawn, run, result, labels, merge.** The tick admits an issue, writes the claim marker and labels, and spawns the strain (claim integrity, Lifecycle, claim sequence). The strain runs standard-delivery unattended and writes its result. The Lair records the run end: its label and pull request changes first, then the outcome marker last (the merge lane, Lifecycle "Run outcome to labels"; Seams between the part designs, items 1 and 8). It ends the session and cleans up as strain launch's Lifecycle steps 4 and 5 state, under Seams between the part designs, item 7. The merge lane then works the pull request (the merge lane, Components "Merge-lane step of the tick").
2. **Park, answer, re-admit, continue.** A parked result becomes its label moves, then the park marker, then the outcome marker last (Seams between the part designs, item 8). The user answers and relabels `readiness:ready`. Admission runs again, the readiness check included. The new strain starts on the pushed branch with the answers as settled decisions.
3. **Post-PR remediation.** A Lair pull request gets at most one remediation run, under Seams between the part designs, item 2. Its dispatch and launch follow strain launch, Components "Remediation strain launch", and its markers and route follow the merge lane, Lifecycle "Stage 3: post-PR fix-up", under Seams between the part designs, items 8 and 10.
4. **Halt and circuit breaker.** The halt file and the breaker follow claim integrity, Lifecycle, with the outcomes of Seams between the part designs, item 4. Their effect on remediation runs and merges follows the merge lane, Lifecycle "Stage 4: halt and circuit breaker".
5. **Start-up sweep.** The start-up sweep and the removal of orphaned sessions and worktrees follow Seams between the part designs, item 7.

## Existing-path coverage

- Interactive standard-delivery is unchanged when the `HIVEMIND_LAIR_STRAIN` marker is absent.
- Non-Lair brood strains keep today's behavior. That includes the settings copy noted in PR #613, which this design neither covers nor changes.
- Triage, the review watch and interactive auto-merge are unchanged, except that triage leaves `lair:*` issues alone.
- Each part design's Existing-path coverage section adds the paths its part touches: [strain launch](strain-launch-design.md), the [merge lane](merge-lane-design.md) and [claim integrity](claim-integrity-design.md).

## Failure modes

| Failure | Detection | Resulting state |
| --- | --- | --- |
| Crash | The session side: [strain launch](strain-launch-design.md), Failure modes "Crash". The claim side: [claim integrity](claim-integrity-design.md), Failure modes "Crash, or claim stopped partway". | The outcome `crashed` in an outcome marker (claim integrity). Labels by the [merge lane](merge-lane-design.md), Lifecycle "Run outcome to labels", and for a remediation run its Failure modes "Fix-up run lost in flight". The pull request's `lair:review` route by strain launch's "Crash" row. Counts toward the breaker (Seams between the part designs, item 4). |
| Stall | The stall rules: strain launch, Failure modes "Stall". The idle signal the Lair acts on: claim integrity, Failure modes "Stall", which takes both stall rules (Seams between the part designs, item 13). | The outcome `stalled` in an outcome marker (claim integrity), labels by the merge lane's "Run outcome to labels", and the pull request route by strain launch's "Stall" row. Counts toward the breaker. |
| The `Stop` hook does not fire while a workflow runs in the background | Found while building #604. | The activity rule still gives the idle signal, so the stall check ends the run `stalled`. Only when the activity hooks do not fire either does the budget check end it `timed-out` (Seams between the part designs, item 13). |
| `/exit` sent through tmux does not end a session | Strain launch, Failure modes, the row of that name. | The Lair kills the session, then cleans up under Seams between the part designs, item 7. |
| GitHub API failure or rate limit | Claim integrity, Failure modes "GitHub read failure or rate limit"; for the merge lane, its Failure modes "Failed or incomplete tick read"; for the remediation step, strain launch's Failure modes "Snapshot or pull request read fails on a tick". | As each of those rows states. |
| Lock already held | Claim integrity, Failure modes "Lock already held". | As that row states. |
| Merge refused | The merge lane, Failure modes "Merge refused". | As that row states. |
| CI red | The merge lane, Failure modes "CI red", and strain launch, Failure modes "CI red". | Under Seams between the part designs, item 2: the pull request's one remediation, whose dispatch timing follows strain launch's row and whose routes follow the merge lane's CI-red rule (Components "Fix-up runs"), which never starts a second run. |
| Invalid result | The merge lane's result checks: the schema check fails, or a Lair pull request check reads and fails (Lifecycle "Run outcome to labels"). | The outcome `invalid-result` in an outcome marker, with the merge lane's labels. The breaker skips it (Seams between the part designs, item 4). |
| Issue edited after claim | The merge lane, Failure modes "Issue edited after claim". | As that row states. |
| Edited answer, or an answer from a user without write access | The comment's edit history, or the user's permission. | The answer is ignored and never reaches a strain. The issue stays in `readiness:needs-decision`. |
| Third park | The issue's park marker count reaches 3. | `lair:handoff`; the issue leaves the factory. |
| Budget overrun | The wall-clock budget clock: claim integrity, Lifecycle (the budget check), with a remediation run timed from its own launch (Seams between the part designs, item 3). The agent-call cap and the deferred-write exemption: strain launch, Failure modes "Budget overrun". | The outcome `timed-out` in an outcome marker (claim integrity), labels by the merge lane's "Run outcome to labels", or a park when a parked result was written first. Counts toward the breaker. A valid result whose reads cannot be made yet is never timed out (Seams between the part designs, item 11). |
| Orphaned claim | Claim integrity, Failure modes "Orphaned claim", with strain launch's Failure modes "Start-up sweep while an outcome write is deferred". | Under Seams between the part designs, item 7. |
| Stale design, or an epic | Claim integrity, Failure modes "Stale design, or an epic". | As that row states. |
| Strain containment cannot be confirmed | #608's environment preflight probe `sandbox`, on any platform (Seams between the part designs, item 6). | The Lair claims nothing and stops with cause `strain_env_preflight`, probe `sandbox`. |
| A route stopped before its last marker | A run end, remediation run end, exit, park or batch review whose last marker is missing. | A later tick computes the route again from the kept result file, or from the session, the worktree and the clock, and repeats its writes (Seams between the part designs, item 8). |

## Decisions

A decision that is not ADR-worthy names the [P20](../../engineering-principles.md) condition it fails.

- **Admission by the readiness check, never an epic.** ADR-0045's 2026-11-21 amendment.
- **Triage leaves `lair:*` issues alone, built in #608.** ADR-0045 decision 16. Placing it in #608 is not ADR-worthy: it fails P20's hard-to-reverse condition.
- **The no-open-blocker condition reads native blocked-by links only; the readiness check reads `## Dependencies` refs only to require their edges.** ADR-0045 decisions 2 and 10; ADR-0046 decision 4.
- **Lair strains through the brood tooling, owned by the Lair.** ADR-0045 decision 3, amending ADR-0007.
- **Admission replaces brood strain approval for Lair strains.** ADR-0045 decision 10, amending ADR-0026.
- **The `unattended` level and park action.** ADR-0045 decision 6, amending ADR-0036 decision 8. For a verified Lair strain, decision 6 also narrows ADR-0039 decisions 3 and 4, the Instinct fallback, and decision 8 narrows ADR-0026 decision 3, the promotion gate. #607 records both narrowings in ADR amendments, as it records ADR-0037's ([strain launch](strain-launch-design.md), Decisions).
- **Merges only through `merge-approved.sh` and its gates.** The [merge lane](merge-lane-design.md)'s Decisions govern it, under ADR-0044 decisions 17 to 20.
- **The exit fallback.** Not ADR-worthy: fails P20's hard-to-reverse condition. It covers an unverified item in the ADR-0045 residuals. Its rule is [strain launch](strain-launch-design.md)'s Failure modes row on `/exit`. The stall fallback is [claim integrity](claim-integrity-design.md)'s idle signal, in its Decisions, with strain launch's activity rule (Seams between the part designs, item 13).
- **The queue report contents.** Claim integrity's Decisions govern them.
- **The outcome in an outcome marker, and the circuit breaker scoped to the Lair session.** Claim integrity's Decisions govern both, under Seams between the part designs, items 1 and 4.
- **A red CI result.** The merge lane's Decisions govern the CI-red rule, under Seams between the part designs, item 2.
- **An issue edited after claim is not merged and goes to `lair:review`.** The merge lane's Decisions govern it.
- **The release-train decisions are deferred with full scope to #606.** ADR-0045 decision 15. These are the fragment format, the release cadence, and who triggers the release pull request. #606 and #612 are therefore not ready until a dated entry under Amendments settles them.
- **Markers are append-only, signed and posted on the claimed issue; the merge lane's run-end and fix-up end markers and strain launch's outcome write are outcome markers; the dispatch marker is the remediation run's start marker; the kinds `fixup-start`, `review` and `exit` and the field mapping join claim integrity's payload; claim-time fields go in the claim marker.** Seams between the part designs, item 1. Implements ADR-0045 decision 2. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **One remediation strain per pull request decides what starts a remediation; the merge lane's fix-up runs are those runs, and its R2 no longer applies.** Seams between the part designs, item 2. The user's answer A of 2026-11-22 at strain launch's design review round 5. Its readings here, that a landed start marker spends the one remediation, that the CI-red rule never starts a second run, that the issue's budget no longer gates a remediation, and that a due dispatch under a halt does not block the review wait, are not ADR-worthy: each fails P20's hard-to-reverse condition.
- **A remediation run's wall-clock budget is timed from its own launch.** Seams between the part designs, item 3. Claim integrity's decision, listed for veto there. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **One set of counted and skipped breaker outcomes.** Seams between the part designs, item 4. The counted outcomes are the PRD's Stop controls criterion and the ADR-0045 amendment of 2026-11-22, which rest on the user's answers of 2026-11-22: yes after claim integrity's design review round 2, and A to the stalled-outcome question. The skipped outcomes, the streak end and the session scope are not ADR-worthy: each fails P20's hard-to-reverse condition.
- **One tick order, with the remediation step before the merge lane.** Seams between the part designs, item 5. The user's answer A of 2026-11-22 at strain launch's design review round 7. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **#604 contains every Lair strain and remediation strain per platform: out of `control/` and every tmux socket of the Lair, on Linux in a sandbox with its own process namespace and on macOS by a `sandbox-exec` profile; #608's probe `sandbox` stops the Lair when the containment cannot be confirmed; the merge lane's cache moves under `control/`.** Seams between the part designs, item 6. The user's answer A of 2026-11-22 to the key-containment question and answer 1A of 2026-11-22 at this design's review round 1. Implements the ADR-0045 amendments of 2026-11-21 on forged markers and of 2026-11-22 on process reach.
- **The orphan rule and the start-up sweep follow claim integrity, with strain launch's deferred-write exemption and the merge lane's worktree removal after the end marker.** Seams between the part designs, item 7. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Every multi-write route takes the merge lane's write order, the route-ending marker last, with `gh pr ready` before the run-end mapping reads the draft flag.** Seams between the part designs, item 8. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Strain launch's `lair:review` route of a delivery run that did not complete applies only to a pull request that passes the Lair pull request checks other than the head.** Seams between the part designs, item 9. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **A remediation run's answerable park keeps `lair:claimed`, and the claim still ends at its end marker.** Seams between the part designs, item 10. ADR-0045 decision 16. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **A valid result whose reads cannot be made yet is never timed out.** Seams between the part designs, item 11. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The merged exit closes the issue before its exit marker.** Seams between the part designs, item 12. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Claim integrity's idle signal takes strain launch's activity rule.** Seams between the part designs, item 13. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **One term, remediation run, for the merge lane's fix-up run.** Seams between the part designs, item 2. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The auto-tier floor holds `docs/prds/`, `docs/initiatives/` and `docs/adr/`, built by #605.** Component "Merge lane and auto tier". The user's answer 2A of 2026-11-22. Implements ADR-0046's rule that a docs pull request never takes the Lair's auto tier.
- **The engine builds the park key from the stop's identity.** Contract "Park record". Implements ADR-0045 decision 6. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Bots, CI check descriptions and any commenter's activity are named as channels that reach the Lair.** Trust boundaries. Names what strain launch's Decisions already decided; the PRD's user stories are unchanged. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **A run's decisions reach the digest from its result file before clean-up, trusted by its outcome marker.** Component "Decision digest and circuit breaker". Implements ADR-0045 decision 14. Not ADR-worthy: fails P20's hard-to-reverse condition.

## Verification strategy

The tests are the PRD's [Testing Decisions](../../prds/autonomous-ready-issue-loop.md#testing-decisions). This section adds only where each test lives:

- Engine tests, for the unattended level, the park action and the settled-decisions launch input, go in `tests/workflow-scripts/`.
- Shell-script tests are `tools/test_*.sh` scripts, such as `tools/test_merge_approved.sh` for the merge lane. New ones cover the strain launch and settings, the result schema, crash and stall detection, the auto-tier script, the park round trip and the controller tick.
- Controller tests use recorded GitHub states, with no live GitHub.
- The live smoke run is by hand, on a throwaway issue in this repository.
- Each part design's Verification strategy section names its own cases and suites: [strain launch](strain-launch-design.md), the [merge lane](merge-lane-design.md) and [claim integrity](claim-integrity-design.md). The cases below add to them.
- The crash and stall detection tests have one home, `tools/test_lair_tick.sh`, as strain launch names it. Claim integrity's and the merge lane's crash and stall cases land there, the activity rule of Seams between the part designs, item 13, included.
- Write-boundary tests, for every multi-write route of Seams between the part designs, item 8: a tick stopped after each write of the route, before its last marker, after which the next tick computes the route again, repeats its writes and writes each marker once, with the result file kept until the last marker lands. The run end, remediation run end and park cases go in `tools/test_lair_tick.sh`, and the exit and batch review cases in `tools/test_lair_merge_lane.sh`. A case for `gh pr ready` after a `complete` re-claim checks that the run-end mapping reads the pull request ready.
- Containment probe cases, in #604's live probe, on each supported platform, Linux and macOS: from inside a strain, `tmux -S <socket> list-sessions` and `tmux -S <socket> new-window` fail for each tmux socket of the Lair; a Bash call cannot read `control/marker.key`, append to `control/halt` or delete it. #608's preflight case: when the probe `sandbox` cannot confirm the containment, the Lair claims nothing and stops with cause `strain_env_preflight`, probe `sandbox`.
- #607's engine tests and #609's park round-trip test: the same stop on a re-claim of the same issue gives the same park key, and a key that fails its pattern is never posted.
- The merge lane's #608 case that a result still unchecked when the budget passes ends the run `timed-out` is replaced by its opposite: such a result is never ended `timed-out` (Seams between the part designs, item 11). The merge lane's #610 cases for the budget measured from `claimed_at`, `budget-exhausted` and a new run after `not-launched` are replaced by the cases of items 2 and 3.
- The merged exit closes the issue before the exit marker is written (Seams between the part designs, item 12), in `tools/test_lair_merge_lane.sh`.

## Seam order

The build order is:

1. #604;
2. then #607 and #605;
3. then #608, and #606 after #605, since #606 makes the auto-tier script detect its mode (merge lane, Components "Auto-tier script");
4. then #609, #610 and #611;
5. with #606 before #612.

Each edge of that order is one native blocked-by link, matching one `#N` ref in the blocked slice's `## Dependencies` section:

- #607 is blocked by #604.
- #606 is blocked by #605.
- #608 is blocked by #604, #605 and #607.
- #609, #610 and #611 are each blocked by #608.
- #612 is blocked by #606 and #608.

As read from GitHub on 2026-11-22, every link of that list exists except #606's on #605, and #606's `## Dependencies` section reads None. Every slice from #604 to #612 is also natively blocked by #625 (closed), #633 and #635, and #610 also by #580; none of these is a Dependencies ref. #605's place after #604 is build order only. Triage writes each link at apply, before it applies `readiness:ready` (ADR-0046 decision 4); otherwise the maintainer adds it. A slice with a Dependencies ref whose link is missing fails the readiness check with `dependency_edge_missing:<n>`.

Issue edits, per the user's answer 3A of 2026-11-22: the overlord makes them after this design's clean review round, before the docs pull request leaves draft. Each is a body edit that keeps every other byte:

- #606 gains `#605` in its `## Dependencies` section and the native blocked-by link on #605.
- #604's acceptance criteria are brought in line with the design: the merge keys set empty, deny rules as a barrier against a strain's mistake rather than full containment (B3-9), and the worktree removed after the outcome marker, never waiting on a push.
- Each slice from #604 to #612 gains one `## Design` block before triage labels it ready, in the form of the idea-to-ready design's Contracts and seams, "Slice design section format": one Solution design link; one `- Heading:` line per entry of its Component heading(s) cell; one `- ADR:` line per ADR in its ADRs cell; and one Review record link. The part designs stay named only on the slice's Initiative line.

Cross-epic seams with #614:

- #608's admission needs the readiness check from #615. It is recorded here. The maintainer adds the native blocked-by link.
- The Lair calls the readiness check with the claim's snapshot and trunk commit, and the check reads no GitHub itself (claim integrity, Contracts and seams, "Readiness-check call at claim"; "Assumptions about #615"). That input mode is a requirement on #615.
- #623 overlaps #608 and #605. #608 builds the readiness-check call at claim, and #605 builds the docs directories of the auto-tier floor (Component "Merge lane and auto tier"). #623, blocked by #608 and #615, builds neither again: its acceptance tests run against #608's call with #615's check.

| Slice | Component heading(s) | Part designs | ADRs |
| --- | --- | --- | --- |
| #604 | Strain launch and settings; Strain result and liveness | [strain launch](strain-launch-design.md); [merge lane](merge-lane-design.md); [claim integrity](claim-integrity-design.md) | ADR-0045 decisions 3, 4, 5 and 10, its 2026-11-21 amendment on forged markers and its 2026-11-22 amendment on process reach; ADR-0007; ADR-0010; ADR-0017; ADR-0019; ADR-0020; ADR-0021; ADR-0027; ADR-0028; ADR-0029; ADR-0030; ADR-0037; ADR-0040; ADR-0042; ADR-0044 |
| #605 | Merge lane and auto tier | [merge lane](merge-lane-design.md); [claim integrity](claim-integrity-design.md) | ADR-0045 decisions 2, 10, 12, 13, 14, 16 and 17 and its 2026-11-21 amendment to decision 2; ADR-0020, amendment 2026-09-29; ADR-0026; ADR-0029, Findings; ADR-0032; ADR-0042; ADR-0043 decision 2; ADR-0044; ADR-0046 |
| #606 | Release-train versioning mode | [merge lane](merge-lane-design.md) | ADR-0045 decisions 12 and 15 |
| #607 | Unattended autonomy level | [strain launch](strain-launch-design.md) | ADR-0045 decisions 5, 6, 7, 8 and 17; ADR-0026; ADR-0029; ADR-0030; ADR-0036; ADR-0037; ADR-0039; ADR-0040 |
| #608 | Controller tick and admission | [strain launch](strain-launch-design.md); [merge lane](merge-lane-design.md); [claim integrity](claim-integrity-design.md) | ADR-0045 decisions 2, 3, 4, 5, 10, 11, 12, 16 and 17 and every amendment of 2026-11-21 and 2026-11-22; ADR-0007; ADR-0010; ADR-0017; ADR-0019; ADR-0026; ADR-0032; ADR-0044 decision 17 |
| #609 | Park answer round trip | [strain launch](strain-launch-design.md); [merge lane](merge-lane-design.md); [claim integrity](claim-integrity-design.md) | ADR-0045 decisions 3, 7, 11, 12 and 16 and its 2026-11-21 amendment to decision 2; ADR-0017; ADR-0037 |
| #610 | Post-PR remediation strains | [strain launch](strain-launch-design.md); [merge lane](merge-lane-design.md); [claim integrity](claim-integrity-design.md) | ADR-0045 decisions 2, 3, 4, 5, 7, 11, 12, 13, 16 and 17 and its 2026-11-21 amendment to decision 2; ADR-0017; ADR-0023; ADR-0032; ADR-0040; ADR-0043 |
| #611 | Decision digest and circuit breaker | [strain launch](strain-launch-design.md); [merge lane](merge-lane-design.md); [claim integrity](claim-integrity-design.md) | ADR-0045 decisions 14 and 17, its 2026-11-21 amendment to decision 2, and its 2026-11-21 and 2026-11-22 amendments to decision 17; ADR-0026; ADR-0030 |
| #612 | Parallel strains | [merge lane](merge-lane-design.md); [claim integrity](claim-integrity-design.md) | ADR-0045 decisions 12 and 15; ADR-0007; ADR-0044 decisions 3, 12, 13, 17 and 19 |

Each ADRs cell is the union of this design's row and the part designs' rows for that slice. A part design's proposed ADR-0045 amendment is cited by the dated amendment that applied it.

## Open questions

None

## Amendments

This design was written with the ADR-0045 amendment of 2026-11-21, which excludes epics from admission and requires a passing readiness check at claim time. Later changes to this design are appended here as dated entries.

2026-11-21: For the merge lane, [merge-lane-design.md](merge-lane-design.md) supersedes the parts its opening paragraph names: the Merge lane and auto tier component; the GitHub-record, park and halt side of Post-PR remediation strains and the start of a fix-up run for failed checks; the Auto-tier script result contract; the Strain result contract, which gains `local_review_head`; every run-end record in the claim marker, that is, the run-end sentence of the Claim marker comment contract, the run-end update of the Claim marker comment row under State and ownership, stage 1's recording of the outcome in the claim marker, and the claim-marker part of the Decision on the outcome and the session-scoped breaker; the outcome list of the Decision digest and circuit breaker component, which gains `stalled` from the Stall row; the merge-settings channel; the Lifecycle label bullets for `lair:handoff`, `lair:failed` and `lair:review`, stage 1's merge step, stage 3 whole and stage 4's merge stop, and it adds the draft, closed-unmerged and claim-withdrawn exits; every removal of a run's worktree before that run's end marker is written, that is, in the Strain result and liveness component, stage 1, stage 5's orphan removal and the Failure modes row on `/exit` sent through tmux, each of which stands once the end marker is written; the Failure modes rows Crash, Merge refused, CI red and Issue edited after claim, and the row GitHub API failure or rate limit for the merge lane; and three Decisions. ADR-0044's amendment of the same date lets the Lair's tick run `merge-approved.sh`.

**2026-11-21, claim integrity.** The claim-integrity design, `claim-integrity-design.md` in this folder, supersedes, for its scope, these parts of this design: in Controller tick and admission, the claim, the readiness-check call, the injection scan, labels and marker comments, the halt switch, the wall-clock budget, the start-up sweep, the lock and the queue report; in Strain result and liveness, the sentence that crash and stall detection follow ADR-0045 decision 5; the marker side of Park answer round trip, and of Decision digest and circuit breaker with its sentence that a restart by the user re-arms the Lair; the Contracts Claim marker comment, Park marker comment, Readiness-check call at claim and Queue report; the claim-marker, park-marker, halt-file, single-instance-lock and local-cache rows of State and ownership; in Lifecycle, the removal of `lair:claimed` on an answerable park, the outcome recorded in the claim marker, and the start-up sweep of stage 5; the Crash, Stall, GitHub API failure, Lock already held, Orphaned claim and Stale design rows of Failure modes, its row on the `Stop` hook not firing while a workflow runs in the background, and the wall-clock part of its Budget overrun row; and the Decisions on the queue report contents, the outcome in the claim marker and the circuit-breaker scope, and the stall part of the decision on the stall and exit fallbacks.

**2026-11-22, integration.** This entry integrates the three part designs, under #633. [Strain launch](strain-launch-design.md), #630, has no approved Amendments text for this design. For its scope it supersedes the parts its opening list names: the Components "Strain launch and settings" and "Strain result and liveness"; the governance side of "Unattended autonomy level" and the launch side of "Post-PR remediation strains"; the Contracts "Strain result", "Lair-written settings" and "Settled decisions"; the strain-containment paragraph of Trust boundaries; the strain-settings, result-file and idle-marker rows of State and ownership; the sentence of Lifecycle stage 1 that ends the session and removes the worktree after the push; the order of the merge lane and the remediation dispatch in the tick; the deferred-write case of the start-up sweep and of the Orphaned claim row; and the Crash, Stall, `Stop` hook, `/exit`, Budget overrun and CI red rows of Failure modes. Each part superseded by any of the three part designs is now a link to the part design that governs it. Seams between the part designs, under Contracts and seams, reconciles the places where they disagree: the markers (item 1); what starts a remediation, where the merge lane's R2 no longer applies (item 2); a remediation run's budget (item 3); one set of breaker outcomes (item 4); one tick order (item 5); the containment of the key and the halt file (item 6), which applies the user's answer A of 2026-11-22 to the key-containment question, so #604 keeps every Lair strain and remediation strain out of the `control/` folder of the Lair's state root and, on Linux, runs each in a sandbox with its own process namespace; and orphans and the start-up sweep (item 7). Seam order now states each edge of the build order as the native blocked-by link it needs and who writes it, fixing review finding A3-16. It gains a Part designs column, and each ADRs cell is now the union of this design's row and the part designs' rows, fixing A3-11. These approved shared-document changes are applied: in ADR-0045, the merge lane's item 7, strain launch's changes 1, 3, 5 and 9, and claim integrity's five dated amendments; in the PRD, strain launch's changes 2, 4, 6, 7, 8 and 10, the merge lane's items 1 and 6, and the Stop controls criterion, which now counts stalled outcomes per the user's answer A of 2026-11-22; in CONTEXT.md, the merge lane's item 4 and claim integrity's sentence for the Lair entry. The merge lane's item 5, the Tier A merge bullet in `plugin/governance/decision-autonomy.md`, is not applied here: it is left to #605, which builds it.

**2026-11-22, design review round 1.** This entry applies the fixes of this design's review round 1, findings R1-1 to R1-31 and C1-1 in the [review record](review-record.md), with the user's answers 1A, 2A and 3A of 2026-11-22. Each part design is now frozen, changed only through a dated entry here. Seams between the part designs gains: the marker kinds `fixup-start`, `review` and `exit`, the field mapping and the extra outcome values (item 1); the term remediation run and the readings of the one remediation per pull request, with the merge lane's budget precondition and `budget-exhausted` route dropped (items 2 and 3); the live-claim qualifier and the `invalid-result` outcome for the breaker (item 4); per-platform containment of `control/` and the Lair's tmux sockets, the preflight probe `sandbox` and the merge lane's cache under `control/`, per answer 1A (item 6); and items 8 to 13, the run-end write order, the pull request route of a delivery run that did not complete, the labels of a remediation run's park, the valid result that is never timed out, the merged exit that closes the issue, and the idle signal with strain launch's activity rule. The auto-tier floor holds the docs directories, per answer 2A. The Park record's key is built by the engine. Trust boundaries name the channels that reach the Lair from others. Lifecycle stages 1 to 3 follow the write order. Failure modes gain the rows Invalid result, Strain containment cannot be confirmed and A route stopped before its last marker. Decisions name the narrowings #607 records and the P20 condition of each new call. Verification strategy names the part designs' sections, one home for crash and stall tests, the write-boundary and containment probe cases, and the merge-lane cases replaced. Seam order states the native links read from GitHub, #606's link on #605, the issue edits left to the overlord per answer 3A, and the cross-epic seams with #615 and #623. In the PRD the Labels criterion names the three `lair:*` labels, with its meaning unchanged, and in `CONTEXT.md` the Lair entry names the remediation strain and the Park entry pushes its branch only when it has commits.
