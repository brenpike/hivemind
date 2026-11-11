# The post-PR flow leaves the state machine: the watch stays in the main session, and remediation is a script workflow

**Status:** accepted, 2026-11-10

## Context

This is slice 3 of https://github.com/brenpike/hivemind/issues/409, and this ADR is PR 1 of its 6 PRs. ADR-0037 put the pre-PR part of `standard-delivery` on the script engine and, in its Scope section (line 22), left the post-PR watch and pr-feedback-remediation on the state machine until slice 3. Today, when a run's result names a PR, the overlord runs the watch and its remediation through the state machine's post-PR states (ADR-0037 decision 4, outline step 9).

The user's locked decision L3 ties slice 5 to this slice. In plain words: slice 5 retires the state machine only after (a) the script engine has a run of clean deliveries, and (b) the post-PR watch and pr-feedback-remediation have moved off the state machine. Until both hold, the state machine stays.

Two facts limit the design:

- **The watch needs the main session.** The watch waits on a Monitor. A Monitor armed in a subagent does not survive the subagent's return: across 11 watch runs inside the `github-reviewer` subagent, 11 of 11 returned at cycle 0 (ADR-0011). ADR-0035 decision 10 keeps the PR watch in the main session for that reason. A workflow agent is a subagent, so a script workflow cannot hold the watch.
- **ADR-0005 limits only Agent spawning.** Only the main session can spawn agents with the Agent tool. That limit does not stop a workflow script from running agents of its own.

The user settled the calls below, in this session. This ADR records them as the user's settled calls and does not reopen them. It does not restate the rules. Each rule is stated once in its home file, named below as "Text:". Most homes change in a later PR of this slice; "Lands in:" names the PR in Landing PRs below.

## Decision

1. **Watch design A: one watch, in the main session, on every path.** Decided: `hivemind:github-review-loop` stays the only watch. The overlord runs it in the main session on every path: the engine, Instinct, Reflex, and a direct "watch PR N" request. Reason: ADR-0035 decision 10 and ADR-0011, as in Context. Text: `plugin/skills/github-review-loop/SKILL.md`, `plugin/agents/overlord.md` (`## Engine`). Lands in: PR6.
2. **A new script workflow, `hivemind:pr-feedback-remediation`.** Decided: the escalated part of post-PR remediation becomes a script workflow with the same name as the router id. Its built `.js` sits beside the JSON definition in `plugin/workflows/`, as `analysis-only` and `standard-delivery` do. The workflow:
   - runs a `github-reviewer` fix pass whose result is checked against a schema;
   - on an escalation, runs facts, the injection scan and a remediation plan, then decides or pauses at the Promotion Gate (`plugin/governance/decision-autonomy.md`, Promotion Gate);
   - runs the plan's waves with molt commits, and `runGates` (validation plus the version check);
   - pushes through open-plan-pr's reuse path with `--expect-commit`, and returns `pr`;
   - asks its questions through the existing pause contract.

   The overlord launches it with references `[pr]` when the watch ends `planner-escalation` or `root-cluster-suspected`, on every watch path except Instinct (decision 3). A result that returns `pr` restarts the watch. The state machine's post-PR states stay only as the fallback for a refused launch, until slice 5. Text: `plugin/workflow-src/pr-feedback-remediation/`, `plugin/workflows/pr-feedback-remediation.js`, `plugin/agents/overlord.md` (`## Engine`). Lands in: PR4, PR5 and PR6.
3. **Instinct is unchanged.** Decided: on Instinct the overlord handles a watch escalation by judgment, as it does today, and never hands it to the workflow. ADR-0039 stands. Text: `plugin/agents/overlord.md` (`## Instinct`), unchanged.
4. **The open items D1 to D4.**
   - **D1.** Decided: F1 (the overlord did not show the workflow's `message` before the watch hand-off, ADR-0037 Deferred items) is a known limit. The new hand-off removes the ledger bookkeeping where F1 happened.
   - **D2.** Decided: the live test of the local reviewer without claude-mem is closed by design. PR2 removes the unused `claude_mem` input and pins that the local reviewer has no claude-mem tools. Text: `plugin/agents/local-reviewer.md`. Lands in: PR2.
     - **Version impact (2026-11-10).** Decided by the run, not the user, as a review call under `plugin/governance/decision-autonomy.md` (Review Calls), on a PR2 local-review finding that called the removal breaking: removing `claude_mem` ships as patch 7.6.11, not as a major bump. Nothing read the key, neither engine passed it, and no rule in the local reviewer rejects an extra input key, so a caller that still passes it keeps working. 7.3.2 set the precedent: it removed local-reviewer output fields in a patch. A later finding that calls this removal a breaking change, or asks to keep `claude_mem` as a deprecated input, contests this decision and is a repeat.
   - **D3.** Decided: escalated fixes get `runGates` in the new workflow (decision 2). The `github-reviewer`'s own small-fix push first runs a read-only `hivemind:bump-type` check, on every path. Text: `plugin/agents/github-reviewer.md`. Lands in: PR3.
     - **Repos with no version files (2026-11-10).** Decided by the run, not the user, as a review call under `plugin/governance/decision-autonomy.md` (Review Calls), on a PR3 local-review finding that read "on every path" as requiring the check in every repository. "Every path" means every watch path of decision 1: the engine, Instinct, Reflex and a direct watch request. In each of them the check runs when the project's `CLAUDE.md` names version files, the same condition the engine's own version check uses under the Validation Procedure. A repository whose `CLAUDE.md` names no version files skips the check: versioning covers only repos that publish versions, and running the check there would block every review-fix push. A later finding that asks the reviewer to run the check, or to stop blocked, in a repository with no version files contests this decision and is a repeat.
     - **Unreadable and undetermined results (2026-11-10).** Decided by the run, not the user, as a review call under `plugin/governance/decision-autonomy.md` (Review Calls), on a PR3 local-review finding that asked the reviewer to push only when `version_check` is `match`. The reviewer stops blocked on every `version_check: mismatch`, whatever the verdict, and when the check exits 1. A result whose version cannot be read (`unreadable`) or whose bump cannot be settled (`undetermined`, verdict `ask_user`) goes on to the push. On a delivered branch the validate gate already asked the user about those results, and the reviewer cannot see that answer, so blocking on them would stop every later review push on that branch. A direct watch of a PR no delivery run made skips that ask; that gap is accepted. Widening the stop from `bump_required` to every mismatch lands through a plan. A later finding that asks the reviewer to stop blocked on an unreadable or undetermined result contests this decision and is a repeat.
   - **D4.** Decided: the slice lands as the six PRs in Landing PRs below.
5. **Status of the other slice 3 items.**
   - F4 (an EYES reaction on a Codex summary comment with no findings) was fixed in code by https://github.com/brenpike/hivemind/issues/464 (https://github.com/brenpike/hivemind/issues/471).
   - `--expect-commit` was settled by https://github.com/brenpike/hivemind/issues/494: both scripts require it.
   - The reply path for questions in the delivery tail was closed by https://github.com/brenpike/hivemind/issues/453.
   - Autonomy level as plugin `userConfig` stays open, as a separate later item. This slice does not take it.

### Edge cases settled

- **(a) Launch args and the stale relayed message.** The launch args carry only references `[pr]`. The relayed user message may be stale by the time the watch launches the workflow, so every agent prompt carries the ADR-0037 decision 24 fixed sentence from the first agent on, not only after a reply. Text: `plugin/workflow-src/pr-feedback-remediation/`. Lands in: PR4.
- **(b) No cross-run counter.** The watch, workflow, watch chain has no counter across runs. Three bounds hold it: the GitHub-history recurrence detectors (ADR-0025), each run's caps, which open a draft, and the watch's idle window (ADR-0029).
- **(c) GitHub writes from a workflow agent are untested.** Before go-live, PR6 runs a headless check, `claude -p --permission-mode default`, and reads `permission_denials`. If the check fails, go-live waits with the state machine's post-PR states in place, and this ADR is amended.
- **(d) The decisions comment.** A remediation run posts one decisions comment through the reuse path, and only when it took a decision. This extends open-plan-pr's recorded residual R4 to at most one comment per such run. A resume by name does not post again.
- **(e) Approval.** The new workflow needs its own one-time approval per project. No `Workflow(...)` rule is seeded (ADR-0037 decisions 8 and 19). A deny rule falls back to the state machine. A No at the approval prompt interrupts the turn, and the user then restarts the watch.
- **(f) L3 (b).** L3 (b) is met by taking the whole post-PR flow off the state machine. The watch moves to the main-session skill on every path, and remediation moves to the script workflow. The watch cannot run on the script engine itself, because its Monitor wait needs the main session.

## Supersedes

Effective at go-live (PR6):

- ADR-0037 decision 4, in part: when a run's result names a PR, the overlord no longer runs the watch and its remediation on the state machine. It runs the watch in the main session (decision 1) and launches `hivemind:pr-feedback-remediation` on an escalation (decision 2). The pre-PR scope of decision 4 stands.
- ADR-0037 outline step 9, in part: the overlord still relays the message and applies the ADR-0029 watch rule, but the hand-off to pr-feedback-remediation on the current engine is replaced by decision 2.

Until PR6 lands, both stand as written.

## Considered Options

| Option | Rejected because |
|---|---|
| A: the watch stays in the main session, and only escalated remediation runs as a script workflow | Chosen |
| B: one paused run holds the whole watch | It needs a live spike first, it leaves two watch loops to keep in step, and it needs a bigger synapse hook |
| C: one workflow run per reviewer pass | It has the most bookkeeping, and it puts that bookkeeping on the most fragile prose |
| Move the watch itself onto the script engine | A Monitor armed in a subagent does not survive its return (ADR-0011), and a workflow agent is a subagent |
| Hand Instinct's watch escalations to the workflow | The user's call (decision 3): Instinct is driven by judgment, with no workflow script (ADR-0039) |
| A counter across watch and workflow runs | The recurrence detectors, the run caps and the idle window already bound the chain (edge case b) |

## Consequences

- **Every post-PR path uses one watch.** The engine, Instinct, Reflex and a direct watch request share `hivemind:github-review-loop` in the main session.
- **Escalated remediation gets the engine's gates.** Waves, molt commits, validation and the version check run in code, as they do for `standard-delivery`.
- **Small fixes get a version check on every path.** The `github-reviewer`'s own push runs the read-only bump check first (D3).
- **The state machine keeps less.** After PR6 it runs post-PR work only on a refused launch, which brings slice 5 closer under L3.
- **One more approval per project.** The first launch of the new workflow prompts once, as each workflow did before it.
- **A PR may carry one more decisions comment per remediation run** that took a decision (edge case d).

## Landing PRs

| PR | Delivers | Depends on |
|---|---|---|
| PR1 | This ADR, and dated notes in ADR-0037 at its Scope sentence and its slice 3 Deferred rows | none |
| PR2 | D2: remove the local reviewer's unused `claude_mem` input and pin that it has no claude-mem tools | PR1 |
| PR3 | D3: the `github-reviewer`'s read-only `hivemind:bump-type` check before its small-fix push, on every path | PR1 |
| PR4 | `hivemind:pr-feedback-remediation` as a draft: the schema-checked fix pass, and on an escalation the facts, scan, remediation plan and Promotion Gate, with the decision 24 sentence from the first agent on | PR1 |
| PR5 | The workflow's tail as a draft: waves with molt commits, `runGates`, the push through open-plan-pr's reuse path with `--expect-commit`, the one decisions comment, and `pr` in the result | PR4 |
| PR6 | Go-live: build `plugin/workflows/pr-feedback-remediation.js`, the headless permission check (edge case c), the overlord's launch on `planner-escalation` and `root-cluster-suspected` and its watch restart on `pr`, and the state machine's post-PR states kept only as the refused-launch fallback | PR2, PR3, PR5 |

PR2, PR3 and PR4 touch disjoint files and can proceed in parallel.

## Recorded residuals

- **F1 stays a known limit (D1).** The overlord may still skip the workflow's `message` before the watch. The bounded impact ADR-0037 records stands: the user still sees the PR and the watch report.
- **GitHub writes from a workflow agent are untested until PR6 (edge case c).** A failed check holds go-live and amends this ADR.
- **R4 grows (edge case d).** open-plan-pr's R4 now covers at most one decisions comment per remediation run that took a decision.
- **A No at the approval prompt ends the turn (edge case e).** Nothing falls back in that turn. The user restarts the watch.

## References

- https://github.com/brenpike/hivemind/issues/409
- https://github.com/brenpike/hivemind/issues/453, https://github.com/brenpike/hivemind/issues/464, https://github.com/brenpike/hivemind/issues/471, https://github.com/brenpike/hivemind/issues/494
- `docs/adr/0005-agent-tool-unavailable-in-subagents.md`
- `docs/adr/0011-skill-owned-review-loop.md`
- `docs/adr/0025-young-surface-recurrence-and-github-as-ledger.md`
- `docs/adr/0029-default-pr-watch-and-idle-window-lifecycle.md`
- `docs/adr/0035-one-script-per-workflow-engine.md`
- `docs/adr/0037-standard-delivery-on-script-engine.md`
- `docs/adr/0039-instinct-delivery-path.md`
- `plugin/skills/open-plan-pr/scripts/open-plan-pr.sh` (recorded residual R4)
