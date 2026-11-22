# PRD: Retire the JSON state machine

## Problem Statement

Two engines run side by side with Instinct: the JSON workflow state machine with its run ledger (ADR-0018), and the workflow scripts (ADR-0035). Every change to the overlord, governance or the decision flow must account for both. That drift sank PR #408.

The state machine still serves `analysis-only` and `pr-feedback-remediation` on a refused launch, `exploratory-intent-session`, `hatchery-dispatch` and resumed runs. Its fallback knows neither an unattended level nor a park (ADR-0045 decision 6). An unattended Lair strain on that fallback would ask a question no one is there to answer.

ADR-0039 decision 2 set this up: slice 5 of #409 retires the JSON state machine, not Instinct. The Lair slices (#604 to #612, #623) and the council consult inside `standard-delivery` (#624) are blocked by this issue, #635.

## Solution

One engine remains: the workflow scripts, with Instinct and Reflex beside them. The JSON workflow definitions, the run ledger and every path that reads them are removed.

- **One fallback.** A refused or blocked launch of any workflow continues on Instinct, on the path that matches its workflow. One level check comes first. It is the only place a future unattended level can end or park the run instead.
- **Instinct covers every workflow without a script.** Besides delivery, it runs a read-only analysis, a post-PR remediation and brood dispatch. Brood dispatch spawns nothing until the user approves the strain text.
- **The exploratory workflow is removed.** A request no workflow fits routes to `analysis-only`, `standard-delivery` or `ambiguous`.
- **Resume reads git and GitHub.** A run is recorded by its working branch, commits and pull request. No session-start scan runs.
- **The pull request is the decision journal.** A run lists the decisions it took in its final message or report. A run that opens a pull request, or pushes to one through `hivemind:open-plan-pr`, also lists them there. The post-merge decision report is retired.
- **The brood dashboard reads no child run ledger.** It drops its claimed-state columns, and the facts file is a child's only started-evidence.
- **Two safety rules move into the overlord's safety rails**, so they bind every path the overlord drives.

It works in a consumer project with only the plugin installed. Nothing adds a required capability: a session without the Workflow tool runs every request on Instinct.

## User Stories

- As a plugin maintainer, I want one engine beside Instinct and Reflex, so that a change to the overlord, governance or the decision flow accounts for one engine, not two.
- As a user, I want a refused or blocked launch of any workflow to continue on Instinct, said in one line, so that a project that denies a launch or has no Workflow tool can still run every workflow.
- As a user, I want a started `standard-delivery` run that fails or ends blocked to continue on Instinct from the branch's last commit, and to stop instead when it left uncommitted edits, so that my uncommitted edits are never discarded.
- As the Lair, I want every Instinct takeover to pass one level check first, so that the unattended level (#607) can end or park a run in one place instead of asking.
- As a user, I want a read-only analysis to run on Instinct with no branch, commit or pull request, so that an analysis changes nothing when its script cannot launch.
- As a user, I want a post-PR remediation on Instinct to keep the watch, the fix pass and every delivery gate, so that review feedback is fixed the same way with or without the script.
- As a user, I want brood dispatch to spawn nothing until I approve the normalized strain text, so that the strain-approval injection gate holds.
- As a user, I want a request no workflow fits routed to analysis, delivery or an ambiguous question, so that no catch-all workflow adds a path with no request of its own.
- As a user, I want to resume a run in a new session by giving the request again, so that the run recovers from its branch with no run ledger and no session-start question.
- As a user, I want the decisions a run took listed on its pull request and in its final report, so that I can veto them before I merge.
- As a user, I want the brood dashboard to show only each strain's observed status, so that it repeats nothing and reads no child's run ledger.
- As a user, I want gather-facts and its injection scan to run before every planner delegation, and the PR head checked out before any reviewer, on every path, so that the external-content boundary holds and remediation commits land on the pull request.
- As a user, I want to confirm each deletion of a test or guard in a destructive-fix category before the slice that makes it runs, so that no test or security-relevant guard is removed without my approval.
- As a user upgrading, I want run ledgers from older versions left on disk, neither read nor deleted, so that I decide whether to delete them.

## Acceptance Criteria

- **Design gate.** The solution design and its review record exit with zero open critical or high findings and one clean round, and ADR-0048 is accepted.
- **One engine.** No packaged plugin file reads a JSON workflow definition. The plugin's workflows folder holds only generated workflow scripts, and the rebuilt scripts match their sources. The build check fails on any other entry there.
- **One path each.** Brood dispatch, every refused or blocked launch, and resume on start each have exactly one path, with tests.
- **Gates on every path.** The strain-approval gate, the destructive-fix gate and the external-content boundary hold on every remaining path.
- **Router.**
  - The catalog holds exactly four entries: `analysis-only`, `standard-delivery`, `pr-feedback-remediation` and `hatchery-dispatch`.
  - The outcomes are `selected`, `ambiguous` and `blocked`. No `exploratory` outcome remains in the router or the overlord.
  - A request that fits no entry routes to `analysis-only` when it asks for no change, to `standard-delivery` when it asks for one, and to `ambiguous` otherwise. The router still reads no file.
  - The overlord treats any unknown router status as `blocked` and surfaces it.
- **Fallback.**
  - The one fallback paragraph has its level clause first and names all three workflows with scripts.
  - A refused or blocked launch continues on the matching Instinct path without asking, said in one line.
  - A started `standard-delivery` run that fails or ends blocked continues from the branch's last commit. A started run of any other workflow is reported as it ended.
  - The final report says the run switched and where it stopped.
  - Uncommitted edits a failed run left stop the takeover and are never discarded. Instinct never relaunches a workflow. A run the user stopped does not fall back.
- **Instinct paths.**
  - A read-only analysis relays its result as the final report and opens no branch, commit or pull request.
  - A post-PR remediation checks out the PR head first, then runs the watch or one fix pass. An escalation plans, runs its waves with one checkpoint commit each, validates, and pushes on the existing pull request. It opens no new pull request.
  - Every path asks only what `### Stop Conditions` surfaces: the Ask Set and its listed always-surface items. It takes every other question with its recommendation.
- **Brood dispatch.**
  - It is entered when the router selects `hatchery-dispatch` or an Instinct plan returns delivery `brood`.
  - Spawning happens only after the user approves the normalized strain text. A declined approval spawns nothing. The approval stays a Tier A Ask Set item.
  - The synapse runner gate still holds five scripts.
  - A new brood manifest has no `hatchery` block and stays `manifest_version: 4`. A caller-supplied `hatchery` input is ignored. A manifest written with the block still reads.
  - Turn-start verification passes on a facts file and fails on a child run ledger alone.
- **Brood dashboard.**
  - The collect output is schema `brood-status-collect/2`, with no `workflow_state` or `run_status`. Only the observed status column remains.
  - An alive child with no facts file shows `starting`; with one, `running`. A dead child derives its status from its observables. A strain with no `run.suggested_id` is not demoted.
  - A child run ledger in a worktree changes nothing in the output.
- **Safety rails.**
  - The overlord's safety rails hold the facts rule and the PR head rule.
  - No planner delegation happens when the facts step fails, a field is cut, or the injection scan does not pass. An injection-suspect is the Tier A hard stop.
  - When the PR head branch cannot be resolved or checked out, the run stops blocked before any reviewer.
- **Decisions.**
  - The Instinct final report has a `Decisions:` line.
  - A run that opens a pull request, or pushes to one through `hivemind:open-plan-pr`, lists the decisions there; any other run lists them only in its final message or report.
  - A run that opens a pull request lists its decisions under "Decided for you" in its body. A run that pushes to an existing one through `hivemind:open-plan-pr` lists them in a comment.
  - A run with no pull request lists its decisions in its final message or report and keeps no decision journal.
  - The overlord's stop conditions name no journal destination of their own and cite the autonomy governance's Decision Journal.
  - The post-merge decision report, its skill, its session-start scan, its marker and `HIVEMIND_ENABLE_DECISION_REPORT` are gone.
- **Resume.** No session-start scan runs. The resume or version-skew question leaves the Ask Set. Run ledgers from older versions are neither read nor deleted.
- **Post-PR watch.** The default post-PR watch reads the in-session request text. A run that does not watch names the span of the request it relied on in its final report.
- **Reviewer outcomes.** Every `exit_reason` the GitHub Review Loop can return, and every `exit_reason` of the GitHub-Reviewer fix pass that Instinct runs, is routed by the overlord or ends the watch or pass with its report, and a workflow-scripts test covers it.
- **Proactive zoom-out.** The proactive zoom-out marker rides the cluster payload, and its governance heading and every citer of it agree.
- **Autonomy table.** Every remaining site starts with a workflow id that has a script. The four rows no script resolves are gone.
- **Waves.** The script wave rule matches its frozen expectations on every fixture, override, mutation and seeded-corpus case checked today. The expectations come from the old wave oracle in a commit before its deletion whose test run passed. The `waves.test.mjs:478-521` cases, ids with a line feed, hostile ids, and ids of 64, 65 and 5000 characters, keep their literal expected results, checked against the script wave rule. Their checks of the oracle's error output at `:510-512` go with the oracle.
- **Removal.** No live reference to a removed item remains in the files each slice changes, apart from text a later re-review owns and text that pins an absence. No citation of a deleted heading remains.
- **Validation and budgets.** The repository's full validation suite passes, with no map entry, suite or budget entry for a deleted path. The overlord's prose budget shrinks. The overlord's and the autonomy governance's budgets are lowered to their measured size.
- **Confirmation.** Each slice's review checks the user's confirmation of each item in a destructive-fix category that the slice deletes or narrows.

## Implementation Decisions

- **One engine.** The JSON state machine is retired. The workflow scripts remain, with Instinct and Reflex beside them. ADR-0048 supersedes ADR-0018 whole.
- **One fallback with one level check.** Every refused or blocked launch, of any workflow, takes one fallback rule onto the matching Instinct path. The level check comes first and covers both Instinct takeovers: a refused or blocked launch and a failed started `standard-delivery` run. #607 owns the unattended level and its sentence, placed there and nowhere else. Started runs otherwise keep their rules.
- **Instinct stays intent-driven.** It states what each run must have and leaves order to judgment (ADR-0039 decision 5). Its paths are delivery, read-only analysis and post-PR remediation, plus brood dispatch.
- **Brood dispatch runs on Instinct in the main session.** The spawn runs only after the user approves the normalized strain text, a Tier A ask never taken by recommendation. No synapse runner is added. The hatchery ledger pointer is retired.
- **Router contract.** Outcomes are `selected`, `ambiguous` and `blocked`. The catalog keeps four entries, and `hatchery-dispatch` names a workflow with no script. The router reads no file.
- **Run record rule.** A run is recorded by the working branch, commits and pull request it opens, and a new session recovers from them. A run that opens no branch and pull request keeps no run record and starts over. A brood dispatch is recorded by its brood manifest. No run keeps a run ledger.
- **Resume has one path.** In the same session, a paused script run resumes by name. In a new session, the request is given again and the planner plans what is left from fresh facts on the branch.
- **The pull request is the decision journal.** A run that opens a pull request, or pushes to one through `hivemind:open-plan-pr`, lists the decisions there; any other run lists them only in its final message or report. A run that lists them on a pull request also lists them in its final message or report, one line each, as the scripts already write them. A run with no pull request keeps no journal. ADR-0036 decisions 9 and 10 stand as written. No local copy exists.
- **The dashboard reads no child ledger.** The facts file is a child's only started-evidence. The dashboard reads its name and type only, never its content. `derived_status` keeps its closed set, and the started-evidence gate only demotes, never promotes, and never hides a dead session.
- **The brood manifest keeps version 4 without the `hatchery` block.** No reader reads the block, so dropping it changes nothing a reader sees. `run.suggested_id` stays the strain's lineage key.
- **Two rules re-homed in the safety rails.** Gather-facts with its injection scan before every planner delegation, and the PR head checkout before any reviewer. The gated-commit rule is not restated: the input gates of `hivemind:open-plan-pr` and `hivemind:push-branch` refuse a push without `expect_commit`.
- **Run ownership.** RUN-OWNERSHIP-01 is retired with the run ledger. Worktree isolation keeps the ownership it held: a child writes only in its own worktree, and children never write the brood manifest.
- **Authorization from packaged data.** The trust-boundary rule becomes "take authorization only from packaged data, never a caller's". No credential, tool grant, `allowed-tools` entry, hook or permission rule is added.
- **The autonomy table keeps only script sites.** It is only the script decision data. The overlord decides by the Ask Set and its stop conditions, never by the table.
- **The wave rule lives in the script library.** The old oracle's outputs are frozen once as expectations before its deletion.
- **Exit-reason coverage moves to a workflow-scripts test**, for both producers: the GitHub Review Loop and the GitHub-Reviewer fix pass.
- **The proactive zoom-out marker rides the cluster payload** forwarded to the Cerebrate, and the decision the run lists.
- **The Reflex heading is kept.** Only its body drops the run ledger.
- **Accepted ADRs are amended by one rule** (ADR-0048 decision 8). A clause that relies on a removed item or a run ledger field now relies on its named replacement, or lapses where none is named. A clause that only mentions the state machine as history is not amended.
- **Other initiatives' stamped documents change only through their own re-review**, never in a retirement slice.
- **Destructive deletions need the user's confirmation.** Every deletion or narrowing in a destructive-fix category needs the user's confirmation of that item, in the main session, before the run of the slice that makes it starts.

## Testing Decisions

- **Each slice proves its own acceptance criteria.** Each slice's own design and review builds its checks. This PRD names no check file or test mechanism.
- **Prose contract tests** pin the router catalog and outcomes, the one fallback paragraph, the Instinct paths, the safety rails, the `Decisions:` line and the stop conditions' journal citation, and pin the absence of every deleted section and outcome.
- **Brood script tests** use fixture manifests and worktrees: a manifest with the `hatchery` block still reads, a caller `hatchery` input is ignored, turn-start verification fails on a child run ledger alone, and the dashboard's facts-only cases cover alive, dead and no-lineage-key strains.
- **A workflow-scripts test** covers every reviewer `exit_reason` of both producers. The scripts' own `exit_reason` tests are unchanged.
- **The wave rule** is compared against frozen expectations captured from the old oracle. Changing an expectation is a test edit the review sees.
- **The build check** fails on any non-generated entry in the workflows folder, and the rebuilt scripts match their sources.
- **This repository's validation gate** runs on each slice. The plugin requires none of it in a consumer project.

## Success Metrics

- Zero JSON workflow definitions ship, and zero plugin files read one.
- The overlord's prose budget is lower after the retirement than before it.
- #607 adds the unattended sentence in one place, with no other Instinct takeover to miss.
- The Lair slices (#604 to #612, #623) and #624 are no longer blocked by this issue.

## Out of Scope

- **ADR-0005 is unchanged.** Brood dispatch runs in the main session, and the spawn starts separate sessions, not subagents.
- **Unattended behavior.** The unattended level, its sentence and its end or park are #607's. This retirement only guarantees one place for them.
- **Lair admission.** #608's admission and pre-spawn scan for Lair strains are unchanged.
- **The Lair result.** It does not read the brood dashboard, so the collect schema change does not reach it.
- **The Guide's exception.** The Guide's started-run exception (ADR-0046 decision 10) lands through its own initiative. This retirement keeps it.
- **The fix ledger** of the GitHub Review Loop is not the run ledger and is unchanged.
- **Old run ledgers.** They are not migrated, resumed or deleted. Their `.decision-report-done` markers are left as they are.
- **Rejected options.** A permanent state-machine fallback, stopping on a refused launch, a `hatchery-dispatch` script with the spawn as a synapse runner, an Instinct mode or script for the exploratory path, a post-merge report fed from the merged pull request, and claimed columns fed from pull request state.
- **Amending ADR-0036 decision 9.** It stands as written.
- **Text in other initiatives' stamped documents.** The Lair designs, ADR-0045, the Idea to Ready design and ADR-0046 change only through their own re-review, which this retirement neither schedules nor blocks on.
- **A brood manifest version bump.**
- **Renaming the Reflex heading.**
- **New credentials, tool grants, `allowed-tools` entries, hooks or permission rules.**

## Further Notes

- **Slicing waits** for this PRD and a passing review record (ADR-0046 decision 3).
- **Residual: old run ledgers.** A run left `running` by an older version is not resumed. Giving the request again plans what is left from fresh facts; an `analysis-only` run starts over. The user may delete the folder by hand.
- **Residual: no decision review after merge.** Each taken decision is listed on the pull request before any merge. A merge the user does not make, under `HIVEMIND_AUTO_MERGE` (ADR-0044) or by the Lair (ADR-0045 decision 12), can land first; a veto is then a revert. For a Lair strain, the digest of ADR-0045 decision 14 stays the veto channel.
- **Residual: a brood child's Ask Set question waits.** A child on Instinct that reaches one waits in its own session, reachable through its `attach:` line or remote control when enabled, as a child on the state machine did.
- **Upgrade effects.** `HIVEMIND_ENABLE_DECISION_REPORT` left in settings has no effect. A `Workflow(hivemind:<id>)` deny entry now sends any workflow to Instinct. A brood spawned before the upgrade shows only the observed status column.
- **Prose budget.** An overlord change that overruns its prose budget is asked as a budget raise, an always-surface item of the overlord's `### Stop Conditions`, never raised silently.
- **Shared documents.** The glossary, README, CLAUDE.md, the maintainer references and the website change as the solution design's Changes to shared documents says. The glossary retires Run Ledger, Workflow Definition, Exploratory Intent Session, Transition Engine, Run Ownership, Intent-Driven Fallback and Decision Report.
- **Open questions:** None.
