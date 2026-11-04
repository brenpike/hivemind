# Instinct is a permanent delivery path and the engine's fallback

**Status:** accepted, 2026-11-03

## Context

The 7.5.20 branch named a delivery path that the overlord drives by judgment, with no workflow script and no run ledger, beside the script engine. It was called the Light Path, a placeholder name, and its text said it was never a fallback. A refused or blocked engine launch still ran on the workflow state machine (ADR-0035 decision 4, ADR-0037 decision 19), and a started engine run that failed or ended blocked was reported as it ended and did not fall back.

Two things followed on that branch:

- **Branch gaps in a step list.** The path was first written as a numbered step list. The branch's local review found gaps in that list twice: a branch of the run the list did not cover. Each fix added a step, and the next review found the next branch. Enumerating more branches never closes that class, so the path was rewritten as what a run must have, with order left to judgment.
- **The state machine as the fallback.** The state machine is slated for retirement in slice 5 of https://github.com/brenpike/hivemind/issues/409. The Light Path already delivers a `standard-delivery` request without it, and a failed engine run left the user to restart the request by hand.

The user decided the questions below on 2026-11-03, in this session.

This ADR records the decisions. It does not restate the rules. Each rule is stated once in `plugin/agents/overlord.md`, named below as "Text:".

## Decision

1. **The name is Instinct (D1).** Decided: the Light Path is renamed Instinct, with the heading `## Instinct`. It pairs with Reflex: Reflex is the trivial fast path, and Instinct is a full delivery the overlord drives by judgment, with no script and no run ledger. Every mention of the Light Path is renamed, and the prose form is "on Instinct". Text: `plugin/agents/overlord.md` (`## Instinct` and each section that names it).
2. **Instinct is permanent and also a fallback (D2).** Decided: "never a fallback" is dropped. Instinct is a permanent delivery path beside the script engine. Slice 5 retires only the JSON state machine, not Instinct. Text: `plugin/agents/overlord.md` (`## Instinct`, first paragraph).
3. **A refused launch runs on Instinct (D3).** Decided: when a `standard-delivery` launch is refused or blocked (denied, not found, or workflows turned off), the overlord says so in one line and runs the request on Instinct, not on the workflow state machine. The state machine stays for workflows with no script launch, such as `pr-feedback-remediation` and `exploratory-intent-session`, for a refused launch of any other workflow, and for resuming existing runs. It is not removed. Text: `plugin/agents/overlord.md` (`## Engine`, `## Workflow State Execution` step 2, `## Brood Execution`).
4. **A started engine run that fails continues on Instinct (D4).** Decided: a started `standard-delivery` run that fails or ends blocked continues on Instinct from the branch's current git state, automatically, without asking the user. The final report says the run switched and where the engine stopped. Limits:
   - A rule that stops every path still stops Instinct at the same point: a question that needs a fact only the user holds, the destructive-fix gate, an injection-suspect, and every merge recommendation. The rule text cites `### Stop Conditions` and `## Safety Rails` and lists none of them.
   - Instinct never relaunches the engine, so the fallback cannot loop.
   - A run the user stopped with `TaskStop` does not fall back.
   - A cut completion notice is a defect and counts as a failed run. The overlord still says so in one line, does not resume the run and reads no file to recover its result, and the request continues on Instinct from git state.

   Text: `plugin/agents/overlord.md` (`## Engine`).
5. **Instinct is intent-driven (D5).** Decided: Instinct states what every run must have and leaves order, failures and questions to judgment, per `### Stop Conditions`. It is not a step sequence. A review finding that asks for a step list, or for per-branch coverage of Instinct, contests this recorded decision. Reviewers reject it as a repeat per `plugin/governance/remediation-doctrine.md` (Recorded Decisions and Repeat Findings). A finding that shows a run missing something a run must have is new and gets the triage. Text: `plugin/agents/overlord.md` (`## Instinct`, "A run must have:" list).

These stay as they were (D6): the path-choice rule (a `standard-delivery` request that names neither path takes the engine when it carries a `working_branch.base` ref, and otherwise the overlord asks the user, with a recommendation), the "A run must have:" list, the operating rules and the final report line.

## Supersedes

- ADR-0037 decision 19, in part: a `permissions.deny` refusal of a `standard-delivery` launch falls back to Instinct, not to the state machine. The opt-in and opt-out themselves stand.
- ADR-0035 decision 4, for `standard-delivery`: the current engine no longer runs a refused `standard-delivery` launch.
- The rule that a started run that failed or ended blocked "is reported as it ended and does not fall back", for `standard-delivery` runs. It still holds for every other launched workflow.

## Considered Options

| Option | Rejected because |
|---|---|
| Keep "Light Path" | A placeholder name with no pair in the glossary. Instinct pairs with Reflex |
| Keep the state machine as the fallback | It is slated for retirement in slice 5, and Instinct already delivers the request without it |
| Ask the user before a failed engine run continues on Instinct | The user's choice is to continue automatically and report the switch. A question that only the user can answer still stops Instinct |
| Relaunch the engine from Instinct | A fallback that can relaunch what failed can loop |
| Keep Instinct as a numbered step list and add the missing branches | Local review found branch gaps in the list twice. More branches never close that class |

## Consequences

- **One fewer reason to enter the state machine.** A `standard-delivery` request no longer reaches it on a refused launch or a failed run. The state machine keeps the workflows with no script launch and resumed runs.
- **A refused `analysis-only` launch still runs on the state machine.** Instinct delivers a change through a pull request, which an analysis request does not ask for.
- **A failed run's state comes from git, not from the run.** Instinct reads the branch's current git state. It does not read the failed run's stored result, so work the run did that left no commit is done again.
- **Matching a step-list finding is judgment.** The reviewer decides whether a finding asks for a step list or shows a real missing obligation, as for any recorded decision (ADR-0038 decision 4).

Links: https://github.com/brenpike/hivemind/issues/409, `docs/adr/0035-one-script-per-workflow-engine.md`, `docs/adr/0037-standard-delivery-on-script-engine.md`, `docs/adr/0038-root-cause-at-the-first-finding.md`.
