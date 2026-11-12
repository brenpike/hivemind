# Local review fixes a whole class in the round, and keeps its history across a replan

**Status:** accepted, 2026-11-11

## Context

Local review spent rounds and planner calls on narrow patches when one fix for the underlying pattern would have closed the whole class. https://github.com/brenpike/hivemind/issues/563 records the pattern and its cost.

- **#559 and #562.** A finding was fixed narrowly. The same construct failed on another axis in the next round, the zoom-out tripped at iteration 2, a full replan ran, and the replan produced another narrow patch. On #562 this cost about 2.8M subagent tokens across 54 agents, with one replan.

The issue found three causes:

- **A class fix was wired only to a replan.** Clustering keys on the fix framing, and the only route to a class fix was the `root-cluster-suspected` exit. So even a class fix of one file cost a full replan.
- **The fix-ledger history was lost at a replan.** The engine set `run.ledger` only on the blocked rerun (`stop_rerun` in `plugin/workflow-src/standard-delivery/review.js`). The review run after a replan started a new ledger, and its recurrence checks started blind.
- **Local review rerouted a bounded tail to a replan.** Step 9 of `plugin/agents/local-reviewer.md` sent diminishing returns on a young surface to `root-cluster-suspected`, which turned a bounded tail into a replan.

This ADR records the decisions. It does not restate the rules. `plugin/governance/remediation-doctrine.md` and `plugin/agents/local-reviewer.md` hold the rule text, and the sections named below are its home. The decisions amend ADR-0038 decision 3, ADR-0025 and ADR-0037, so they get their own record, and each of those ADRs carries a dated note that points here.

## Decision

1. **In-round class fix.** Local review may fix a whole class in the current round when the fix stays within its 2-file bar, changes no architecture or contract, and passes the Closed-by-Construction Acceptance Test. Otherwise it returns `root-cluster-suspected`, as before. Local review judges this itself. There is no script trigger and no record of fixed surfaces: ADR-0038 decision 3 stands on both points (the user's choice on local review finding 65415fd0). A later finding on a construct the ledger already shows class-fixed returns `root-cluster-suspected` to the planner, never a second in-round fix. This amends ADR-0038 decision 3, which before sent every class fix through a replan. Text: the doctrine's `## Root-Cluster`, and step 6 of The Loop in `plugin/agents/local-reviewer.md`.
2. **The fix-ledger history survives a review replan.** The replan route hands the reviewer's own returned `ledger_path` to the next review run as `resume_from_ledger`, once, as the blocked rerun already did. Only the iterations after the ledger's last `root-cluster-suspected` or `planner-escalation` exit count toward `max_iterations`, so the count restarts after a replan. The earlier iterations stay as history for the break-fix, recurrence and class-fix checks. This amends ADR-0025: GitHub stays the recurrence ledger of the GitHub loop, and no new local recurrence file is added. The fix ledger the local reviewer already writes carries the history. Text: `routeLocalReview` and `buildReviewPrompt` in `plugin/workflow-src/standard-delivery/review.js`, rows SD-36 and SD-39, and steps 1 and 2 of The Loop.
3. **Local review step 9 drops the young-surface reroute.** A `diminishing-returns` verdict that passes the two-round gate is honored on any surface. The doctrine's `## Post-Fix Young-Tail Reroute Synthesis` stays for the GitHub reviewer, which still reroutes a young recurring tail. Text: step 9 of The Loop, and that doctrine section, now worded for the GitHub reviewer only.
4. **Riders.** First-finding triage question 2 also asks which other failure axes the same construct has, each cited as `file:line_start..line_end`. After a class fix, step 3a names that construct first in the next round's focus, in the reviewer's own words. Text: the doctrine's `## First-Finding Triage`, and step 3a of The Loop.
5. **Iteration policy.** A local review run has at most 6 rounds (`max_iterations` 6). There is no round cap per pull request. A pull request gets at most one review replan (`maxReviewReplans()` 1); a review that would send the run back to planning a second time opens the pull request as a draft instead (row SD-83). With the recurrence escalation of decision 1, these are the bounds. This replaces ADR-0037's limit of 10. Text: the Input Contract and step 1 of `plugin/agents/local-reviewer.md`, `maxReviewIterations()` and `maxReviewReplans()` in `plugin/workflow-src/standard-delivery/main.js`, and rows SD-32, SD-39 and SD-83.
6. **Planner model.** A planning pass that plans from a review block runs on Sonnet. When a checked Sonnet result flags `remediation_gate.promotion_gate.architectural`, the pass resends that call once on Opus, and every later call of the pass stays on Opus. The rule is one shared function. It covers standard-delivery review replans (row SD-85) and the escalation plans of the draft pr-feedback-remediation workflow (row PFR-28), whose escalation passes always carry a review block. Text: `callPassPlanner` in `plugin/workflow-src/lib/checks.js`, `runPlanningPass` in `plugin/workflow-src/lib/plan.js`, and `plannerCallOptions` in `plugin/workflow-src/lib/runner.js`.

### Measures

The issue sets these measures for the change. This ADR adds no code that counts them; they are read from run records and pull request history.

- Re-emission rate, a finding on a construct already fixed in this pull request: under 20%.
- At most 1 review replan per pull request.
- Codex calls per pull request, reported next to the count of distinct root classes.
- Findings caused by prose trims made to fit a byte budget: 0.

## Text homes

Each file this decision changed, and what changed in it:

- `plugin/governance/remediation-doctrine.md`: `## Root-Cluster` (the in-round class fix and the escalation on a construct already class-fixed), `## First-Finding Triage` question 2 (the other failure axes), and `## Post-Fix Young-Tail Reroute Synthesis` (worded for the GitHub reviewer only).
- `plugin/agents/local-reviewer.md`: the load line drops the reroute section; the Input Contract and step 1 set `max_iterations` 6 and count only the iterations after the last replan exit; step 2 reads that count; step 3a names a class-fixed construct first; step 6 applies the class fix; step 9 drops the young-surface reroute.
- `plugin/workflow-src/standard-delivery/review.js`: `routeLocalReview` sets `run.ledger` on the replan route; `requestReviewReplan` counts review replans and opens a draft at the limit.
- `plugin/workflow-src/standard-delivery/main.js`: `maxReviewIterations()` returns 6, `maxReviewReplans()` returns 1, and `createRunState` adds `reviewReplans`.
- `plugin/workflow-src/lib/checks.js`, `plugin/workflow-src/lib/plan.js` and `plugin/workflow-src/lib/runner.js`: the planner model rule of decision 6.
- `plugin/workflow-src/standard-delivery/contract.js`: rows SD-32, SD-36, SD-39, SD-57, SD-83 and SD-84, and the new SD-85, each tested in `tests/workflow-scripts/standard-delivery.test.mjs`. The generated `plugin/workflows/standard-delivery.js` follows.
- `plugin/workflow-src/pr-feedback-remediation/contract.js`: the new row PFR-28, tested in `tests/workflow-scripts/pr-feedback-remediation.test.mjs`.
- Policy fixtures: `tests/policy/safety-first-finding-triage.json` pins the new triage question, and `tests/policy/safety-post-fix-young-tail-reroute.json` no longer names the local reviewer as a consumer.
- `README.md`: the local reviewer row names `max_iterations` 6.

## Considered Options

| Option | Rejected because |
|---|---|
| A script trigger for the class fix, keyed on a count or on a fixed-surface record | ADR-0038 decision 3 keeps the zoom-out a judgment with no code trigger, by the user's choice on local review finding 65415fd0. A record of fixed surfaces is a second record beside git and GitHub (ADR-0037 decision 2), which the user already turned down |
| Keep the class fix on the replan route only | The cost on #559 and #562: a class fix of one file cost a full replan, and the replan produced another narrow patch |
| A local recurrence file that outlives the review run | ADR-0025 decision 2 turned it down. The fix ledger the reviewer already writes holds the history, and the engine only hands its path on |
| Carry the iteration count across a replan | The run after a replan would start near its limit, so the remediation the replan planned would get few rounds or none |
| Keep the young-surface reroute in local review | It turned a bounded tail into a replan. Decision 1 now handles a recurring class inside the round, and the GitHub reviewer, which has no in-round class fix, keeps the reroute |
| A round cap per pull request | Rounds are already bounded per run (6) and replans per pull request (1); a third cap adds a stop with no class it closes |
| Plan every review replan on Opus | Most review remediation plans change no architecture. The flag the planner already sets picks the plans that need Opus |
| Plan every review replan on Sonnet | A plan that changes architecture needs the stronger planner |
| A model rule in each workflow, so pr-feedback-remediation plans its escalations on Opus alone | Two copies of one rule drift. Its escalation passes carry a review block like a standard-delivery review replan, so the one shared rule fits both |

## Consequences and residuals

- **The class fix is local review's judgment.** No code decides that a class fix fits the 2-file bar, changes no contract or closes its class. This is bounded: the Closed-by-Construction Acceptance Test must pass, the fix is reviewed again in the next round with its construct named first in the focus, and a later finding on that construct returns `root-cluster-suspected` to the planner.
- **The planner model is the planner's judgment.** Sonnet sets the `architectural` flag that moves the pass to Opus. A Sonnet plan that changes architecture without the flag stays on Sonnet. Bounded impact: the same flag is the plan's promotion gate, which asks the user about an architectural remediation plan, so a missed flag is a miss that gate already bears, and gate flags were the planner's judgment before this change (ADR-0037 decision 3). The plan's steps are reviewed by the next local review run, and every pull request is in front of the user before merge.
- **The draft remediation workflow plans Sonnet-first.** Once pr-feedback-remediation goes live, its escalation plans start on Sonnet under decision 6.
- **A second review replan opens a draft.** A pull request that needs more than one review replan opens as a draft that names the review exit and the limit. The user decides there.
- **No new state, stop kind or record.** The ledger already existed; the engine hands its path on. The draft at the replan limit uses the existing loop-cap path.

Links: https://github.com/brenpike/hivemind/issues/563, https://github.com/brenpike/hivemind/issues/559, https://github.com/brenpike/hivemind/issues/562, `docs/adr/0025-young-surface-recurrence-and-github-as-ledger.md`, `docs/adr/0037-standard-delivery-on-script-engine.md`, `docs/adr/0038-root-cause-at-the-first-finding.md`, `docs/adr/0040-post-pr-flow-on-script-engine.md`.
