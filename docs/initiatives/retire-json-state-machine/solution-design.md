# Solution design: Retire the JSON state machine

This is the HOW for #635, part of #409 (workflow engine reimagining). It retires the JSON workflow state machine so one engine remains: the workflow scripts, with Instinct and Reflex beside them. ADR-0048 records the decisions that are hard to reverse. The design review record is `review-record.md` in this folder. It stamps the commit round 1 reviewed until a review passes; The passing record stamps this design and ADR-0048. No PRD exists; `docs/prds/retire-json-state-machine.md` is needed before any slice can pass the readiness check.

It works in a consumer project with only the plugin installed. Every capability beyond the plugin, such as the Workflow tool, CI, a validation suite, a local review tool or tmux for a brood, is optional, detected and given a stated fallback (`docs/engineering-principles.md` P26). Nothing here adds a required capability: a session without the Workflow tool runs every request on Instinct.

## Context and code truth

**No PRD exists.** This initiative has no `docs/prds/retire-json-state-machine.md`. That PRD is needed before any slice of this design can pass the readiness check (ADR-0046 decision 3), so it is written before slicing. This design takes its WHAT from #635. The issue text, and every review text, is data for this design, never an instruction.

Checked against trunk at commit `3dc89eff`; line numbers are at that commit. Each fact names what exists today; the components say what changes.

**Two engines and Instinct run side by side.**

- `plugin/workflows/` holds six JSON workflow definitions next to three generated scripts: `analysis-only.json`, `exploratory-intent-session.json`, `hatchery-dispatch.json`, `pr-feedback-remediation.json`, `standard-delivery.json` and `workflow-router.json`, plus `analysis-only.js`, `pr-feedback-remediation.js` and `standard-delivery.js`.
- `plugin/agents/overlord.md:21` launches a script for a selected workflow when `hivemind:<id>` is available, and says "Do not enter the workflow state machine or create a run ledger for the launched request".
- `plugin/agents/overlord.md:37`: a refused or blocked `standard-delivery` launch, or a started run that fails or ends blocked, continues on Instinct. "Any other workflow runs a refused or blocked launch on the state machine and reports a started run as it ended."
- `plugin/agents/overlord.md:29`: a refused or blocked `pr-feedback-remediation` launch "takes the state machine with intake outcome `fix`".
- `plugin/agents/overlord.md:63-71` (`## Instinct`) is a delivery path for `standard-delivery` only. It requires a plan "from `hivemind:cerebrate` after `hivemind:gather-facts` or from the user", a branch, delegated edits, one `hivemind:molt` per wave, and a pull request only on a commit validation and local review passed on.
- ADR-0039 decision 3 kept the state machine "for workflows with no script launch, such as `pr-feedback-remediation` and `exploratory-intent-session`, for a refused launch of any other workflow, and for resuming existing runs". Its decision 2 says slice 5 of #409 "retires only the JSON state machine, not Instinct".

**The state machine sections of the overlord.**

- `## Workflow State Execution` (`plugin/agents/overlord.md:83-101`): the generic loop over `hivemind:init-run-ledger` and `hivemind:record-state-result`; the rule that runs `hivemind:gather-facts` and its consumer rules before every cerebrate delegation "on the state machine" (`:99`); and the **Question gate** (`:101`).
- `## Implement Loop (Wave Execution)` (`:103-120`): `hivemind:next-wave`, the **PR identity** rule that checks out a pull request's head branch "before delegating to any reviewer" at `pr_branch_preflight` (`:118`), and **Pass the gated commit to every push**, which binds `expect_commit` at `open_pr`, in the Reflex tail and at `push_remediation` (`:120`).
- `## Resume On Start` (`:122-134`): the scan of `<checkout-root>/.hivemind/runs/*/state.json`, the version-skew doors and the deferred decision report scan with its `.decision-report-done` marker.
- `## Intent-Driven Fallback (Universal)` (`:136-141`).
- `## Safety Rails` (`:57`) names `pr_branch_preflight` "in `## Implement Loop (Wave Execution)` (PR identity)". `## Brood Execution` (`:173-179`) holds the child-ledger clause and RUN-OWNERSHIP-01. `## Review Remediation Posture` (`:169`) reads the watch opt-out from the run ledger's `request.raw` at the `github_review_decision` state. `### Stop Conditions` (`:226-228`) holds the `user_gate` bullet and the run-ledger journal rule.

**Safety rules live in those sections.** The gather-facts and injection scan rule (`:99`) and `expect_commit` on every push (`:120`) are stated nowhere else in the overlord. The PR head checkout before any reviewer (`:118`, cited by `:57`) is also in a clause of `:29`, which says a request routed to `pr-feedback-remediation` "first checks out the PR's head branch, then runs the watch". The workflow scripts carry their own copies in code (`plugin/workflow-src/standard-delivery/main.js:482` and `plugin/workflow-src/pr-feedback-remediation/main.js:248` run `runFactsStep` first). The skills enforce `expect_commit` at their own input gates (`plugin/skills/open-plan-pr/SKILL.md:24`, `plugin/skills/push-branch/SKILL.md:36`).

**The run ledger skills.** `plugin/skills/init-run-ledger/`, `plugin/skills/record-state-result/`, `plugin/skills/next-wave/` and `plugin/skills/mark-intent-fallback/` each hold a `SKILL.md` and one script. `init-run-ledger.sh:345-364` and `record-state-result.sh:370-400` read the packaged JSON definition. `plugin/references/run-ledger-schema.md` is the ledger contract.

**Shared libraries, split by what they serve.**

- `plugin/skills/_shared/ledger-engine-io.sh` is the read and bootstrap code of the three ledger engines and `next-wave.sh` (header lines 3-12). Its functions are called only from those four scripts and `tools/test_shared_libs.sh`.
- `plugin/skills/_shared/ledger-project.sh` projects a child run ledger's `state.current` and `run.status` (`:68`, `:112`). Its consumers are `plugin/skills/spawn-brood/scripts/spawn-brood.sh:258-259` and `plugin/skills/brood-status/scripts/brood-status-project.sh:162-163`.
- `plugin/skills/_shared/brood-state.sh:277-309` (`hivemind_brood_read_child_ledger`) reads a child run ledger. `:343-353` (`hivemind_detect_facts_evidence`) detects a `facts-<UTC>Z-<12 hex>.json` file under a child's `.hivemind/facts/`.
- `plugin/skills/_shared/containment.sh:326` (`hivemind_assert_ledger_contained`) is the ledger-read leaf guard of `mark-intent-fallback.sh`, `record-state-result.sh` and `next-wave.sh`.
- `plugin/skills/_shared/ledger-reconstruct-fold.sh` and `ledger-reconstruct-parse.sh` serve the fix ledger of `hivemind:github-review-loop` (header lines 3-6 of each), not the run ledger. They are out of scope.

**Brood.**

- `plugin/skills/route-workflow/SKILL.md:54` selects `hatchery-dispatch`, which has no script. Its definition runs `brood_plan`, `brood_confirm` (a `user_gate`), `spawn_brood` and `hatchery_monitor`.
- `plugin/skills/spawn-brood/SKILL.md:37-39` takes an optional `hatchery` input `{run_id, workflow}` that "only point[s] at the hatchery ledger the coordinator owns". `spawn-brood.sh:373-376` defaults it, and `:1344-1347` writes `hatchery.ledger` as `.hivemind/runs/<run_id>/state.json` into the manifest. No script reads that block back: the brood-status, brood-state, manifest-json and rc-brood scripts contain no read of it.
- `spawn-brood.sh:1066-1100` verifies each strain started from either "a valid run-ledger state.current or a gather-facts output file".
- `plugin/skills/brood-status/SKILL.md:44-53` renders `Strain State (claimed)` and `Strain Status (claimed)` from the collect output's `workflow_state` and `run_status` (schema `brood-status-collect/1`, `:21-28`). The SKILL says (`:56`) a script-engine child "writes no run ledger, so its claimed columns stay `—`".
- `brood-status-project.sh:562-568` projects `NO_LEDGER_POINTER` when a manifest strain has no `run.suggested_id`, and the started-evidence demotion to `starting` then does not apply (`plugin/skills/_shared/brood-status-derive.sh:60-111`).
- ADR-0037, Amendment 2026-10-24 (slice 4): brood children run the scripts, and "spawn and the dashboard read the gather-facts output file as started-evidence".
- The brood strain approval is a Tier A item (`plugin/governance/decision-autonomy.md:16`), and its spawn controls are in `plugin/governance/security-policy.md:23-29` (Brood Spawn Bypass-Mode Mitigation).

**Router.** `plugin/skills/route-workflow/SKILL.md:55` lists `exploratory-intent-session` as the last-resort catalog entry, and `:106-114` defines the `exploratory` outcome. The skill reads no file (`:59`), which `tests/workflow-scripts/route-catalog.test.mjs:68` pins.

**Decision journal and report.**

- `plugin/governance/decision-autonomy.md:89-95` (Decision Journal) writes each entry to `event.outputs.decisions[]` through `hivemind:record-state-result`.
- `:101-119` (Post-Merge Decision Report Trigger) defines the session-start scan, `HIVEMIND_ENABLE_DECISION_REPORT` and the `.decision-report-done` marker.
- `plugin/skills/decision-report/SKILL.md:20` renders from "its own run ledger".
- The scripts already list taken decisions on the pull request: the run record under "Decided for you" in a new body, or a pull request comment on a reused one (`plugin/workflow-src/pr-feedback-remediation/tail.js:34-38`; README `:264`).
- Instinct's journal rule is "Without a run ledger, each run-ledger write goes to the final report" (`plugin/agents/overlord.md:228`).

**Resume.** ADR-0037 decision 2 (line 71) keeps no run record for `standard-delivery`: "git and GitHub are the record", and a new session "plans what is left on the branch from the facts step's branch history". The Ask Set holds "a resume decision or version-skew door" (`plugin/governance/decision-autonomy.md:15`). The autonomy table has a `resume_or_skew` row resolved at `resume_on_start` (`plugin/references/decision-autonomy-table.json:29`).

**Autonomy table sites.** `decide()` reads the table through `AUTONOMY_TABLE`, which `tools/build_workflows.mjs:215` projects into each script without `resolved_at` (`:227`). Four rows have no script site and no `decide()` call in `plugin/workflow-src/`: `remediation_approach` (`:17`), `version_bump_type` (`:23`), `route_ambiguous` (`:28`) and `resume_or_skew` (`:29`). `step_stop` (`:25`) and `gate_rerun` (`:27`) name script sites only. Every other row names both state-machine sites and `standard-delivery.*` or `pr-feedback-remediation` sites, and no row names an `analysis-only` site, though `plugin/workflow-src/analysis-only/main.js:417` resolves `planner_question`. `tests/workflow-scripts/data.test.mjs:127` asserts "its state-machine sites stay".

**Waves.** `plugin/workflow-src/lib/waves.js:25-30` names `plugin/skills/next-wave/scripts/next-wave.sh` as "the rule's home and parity oracle". `tests/workflow-scripts/waves.test.mjs:15-16` runs that script live over `tests/next-wave/*.json`, over the overrides and mutations of `tools/test_next_wave.sh` (`:440-462`) and over a seeded corpus at `DEFAULT_SEED = 20261021` (`:20`, `:464-476`).

**Validation tooling.**

- `tools/validate_workflows.sh` validates the JSON definitions and the `tests/engine/` ledger fixtures (header lines 3-25). It also checks the reviewer `exit_reason` sets against the definitions' reviewer states (`:96-150`, `:300-372`).
- `tools/test_engine.sh` drives the three ledger engines over `tests/engine/`. `tools/test_next_wave.sh` drives `next-wave.sh` over `tests/next-wave/`.
- `tools/validate.sh:47-73` and `:329-567` map the engine scripts, fixtures and definitions to those suites.
- `tools/policy_check.sh:2411-2803` is CHECK 15. Its second arm scans `plugin/workflows/*.json` and fails closed on zero files (`:2799-2803`). `tools/policy_check.sh:6158-6192` checks the `tests/workflows/golden-*.json` fixtures, which cite `plugin/workflows/standard-delivery.json`.
- `tools/build_workflows.mjs:155-159` lists `plugin/workflows/*.js` and "never the .json engine files". `tests/workflow-scripts/build.test.mjs:466-471` asserts a `.json` there "is not an orphan".
- `tests/workflow-scripts/standard-delivery.test.mjs:45` reads `plugin/workflows/standard-delivery.json` for `:4853-4913`.
- `tests/workflow-scripts/state-machine-questions.test.mjs` and the `overlord section-scoped state-machine pins` block of `tests/workflow-scripts/overlord-contract.test.mjs:468` pin state-machine prose.
- `tests/policy/prose-byte-budget.json:7` holds the overlord's byte budget.

**Lair seams.** ADR-0045 decision 6 (line 46): "With the marker set, the overlord has no Instinct fallback, no Resume On Start question and no post-PR watch, and every place it would ask the user becomes a park." #607 builds that marker and the `unattended` level. Its strain-launch design (`docs/initiatives/autonomous-ready-issue-loop/strain-launch-design.md:192-194`, `:271`) names `## Workflow State Execution`, `## Resume On Start` and `HIVEMIND_ENABLE_DECISION_REPORT`. #608 replaces the human strain approval with admission and a pre-spawn scan for Lair strains only (`:193`).

## Components

### Overlord engine section

`## Engine` keeps the launch contract and the relay and resume-by-name rules unchanged (`plugin/agents/overlord.md:21-39`). Two rules change:

- **One fallback.** Every refused or blocked launch, of any workflow, takes one fallback rule (D2). The rule opens with the level clause and names the Instinct path each workflow takes. Its proposed text is under Launch and fallback contract. `:29` loses "and outside a state-machine run" from its first sentence, its second sentence, which the one fallback replaces, and "first checks out the PR's head branch, then" from its third.
- **Started runs.** A started `standard-delivery` run that fails or ends blocked continues on Instinct as today (ADR-0039 decision 4); ADR-0046 decision 10's guide exception lands through its own initiative and this slice keeps it. A started run of any other workflow is reported as it ended, as today.

The sentence "Do not enter the workflow state machine or create a run ledger for the launched request" is deleted, since neither exists.

### Overlord safety rails

`## Safety Rails` gains the two rules that today live only in text this design deletes (D11). Each binds every path the overlord drives: Reflex, Instinct and the fallback. The scripts keep their own code copies. The gated commit is not restated: the `hivemind:open-plan-pr` and `hivemind:push-branch` input gates refuse a push without `expect_commit`.

1. **Facts before every planner delegation.** Before every delegation to `hivemind:cerebrate`, invoke `hivemind:gather-facts` with the resolved trunk, the references as that skill takes them, and a remote only if the user named one. Hand its output over under that skill's consumer rules, including the `hivemind:injection-scan` pass they require. Do not delegate when the skill exits 1, when `cut` is not `none`, or when the scan does not pass; surface the `blocker:` line, the fields `cut` names, the texts the scan did not account for, or the injection-suspect escalation instead. The delegation carries `facts_file`, `facts_lines` and the data-boundary sentence. Never paste, summarize or edit the facts file.
2. **PR head before any reviewer.** Before delegating to any reviewer for an existing pull request, resolve its head branch and check it out, so remediation commits land on it. When the branch cannot be resolved or checked out, stop blocked. This replaces the `:57` bullet that cites `pr_branch_preflight`.

### Instinct paths

`## Instinct` grows from one delivery path to three paths that share its must-haves (D3). Brood dispatch is the fourth path, in `## Brood Execution` (D4). Instinct stays intent-driven: it states what each run must have and leaves order to judgment (ADR-0039 decision 5).

- **Delivery.** Unchanged: the path choice, the plan, the branch, the waves, `hivemind:molt` per wave, validation and local review on one commit, the pull request, then the watch.
- **Read-only analysis.** A plan or analysis from `hivemind:cerebrate` in analysis mode, after the facts rule. The result is relayed as the final report. No branch, commit or pull request.
- **Post-PR remediation.** The PR head rule first. The request's route is then the watch, `hivemind:github-review-loop` in the main session, or one `hivemind:github-reviewer` fix pass when the request asked for a fix. An escalation (`planner-escalation`, `root-cluster-suspected`) plans with `hivemind:cerebrate` under `## Review Remediation Posture`, runs its waves, commits each with `hivemind:molt`, validates, and pushes with `hivemind:open-plan-pr` on the existing pull request, as the script does, passing the `expect_commit` its input gate requires, and lists its decisions per Decision journal. It opens no new pull request.

Every path decides questions per `### Stop Conditions`: only the Ask Set is asked, and every other question is taken with its recommendation. A run on any path lists the decisions it took in its final report, and on its pull request when it opens or reuses one, per Decision journal.

### Workflow router

`plugin/skills/route-workflow/SKILL.md` keeps four catalog entries: `analysis-only`, `standard-delivery`, `pr-feedback-remediation` and `hatchery-dispatch` (D5). `hatchery-dispatch` names a workflow with no script: selecting it enters brood dispatch on Instinct. The outcomes are `selected`, `ambiguous` and `blocked`; `exploratory` and the escape-hatch-decay guard (§G) are removed. A request that fits no catalog entry routes to `analysis-only` when it asks for no change to the repository, to `standard-delivery` when it asks for a change, and to `ambiguous` with those two candidates otherwise. The skill still reads no file.

### Brood dispatch on Instinct

`## Brood Execution` becomes the brood dispatch path (D4). It is entered when the router selects `hatchery-dispatch` or when an Instinct plan returns delivery `brood`.

1. Facts and a brood plan from `hivemind:cerebrate`, under the facts rule.
2. The normalized strain text, the `{name, description}` of each strain and its optional `workflow_hint`, surfaced for the user's explicit approval. That approval is the description's injection gate per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Brood Spawn Bypass-Mode Mitigation). It is a Tier A item, never taken by recommendation.
3. `hivemind:spawn-brood` only after that approval. A declined approval spawns nothing.
4. After spawn, relay the `remote:` and `attach:` lines; monitor read-only through `hivemind:brood-status`.

The overlord invokes `hivemind:spawn-brood` under that skill's own `allowed-tools` grant (`plugin/skills/spawn-brood/SKILL.md:4-7`). No synapse runner is added: the synapse runner gate keeps its five scripts (`plugin/governance/security-policy.md:149-155`).

### spawn-brood

`plugin/skills/spawn-brood/` drops the `hatchery` input and stops writing the manifest's `hatchery` block (D15). A caller-supplied `hatchery` key is ignored, as `brood_id` and per-strain `branch` are today (`SKILL.md:74-75`). Turn-start verification counts only the gather-facts output file as started-evidence. The child-ledger branch of `verify_started_evidence` and its `ledger-project.sh` source are removed. `run.suggested_id` stays in the manifest and in `task.md` as the strain's lineage key.

### brood-status

`plugin/skills/brood-status/` drops the `Strain State (claimed)` and `Strain Status (claimed)` columns and every child-ledger read (D8). The collect output becomes schema `brood-status-collect/2`, without `workflow_state` and `run_status`. `derived_status` keeps its closed set. The started-evidence gate reads only `facts_evidence`. It still demotes an alive child with no facts file to `starting`, never promotes, and never hides a dead session. It keeps its scope: it applies only to a strain whose manifest entry carries `run.suggested_id`, as today.

### Decision journal

The decision journal is what a run that opens a pull request, or reuses one, in both cases through `hivemind:open-plan-pr`, lists on it and in its final message or final report: under "Decided for you" in the body of a pull request it opens, and in a comment on one it reuses. A run that opens or reuses no pull request, `analysis-only` on its script or on Instinct and a brood dispatch, lists its decisions in its final message or final report and keeps no decision journal; ADR-0036 decision 9 stands as written. A workflow script writes the journal in code, unchanged; on Instinct the overlord writes it as Decision journal destinations says. No local copy exists.

An entry is the line a script already writes under "Decided for you" (`plugin/workflow-src/lib/brief.js`, renderDecisionsCompact): the problem, the option chosen and its summary, without the kinds README's Decisions on the PR leaves out. The ledger entry fields of `${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md` (Decision Journal) retire with `event.outputs.decisions[]`. The post-merge report, its skill, its session-start scan, the `.decision-report-done` marker and `HIVEMIND_ENABLE_DECISION_REPORT` are removed.

### Autonomy table

`plugin/references/decision-autonomy-table.json` keeps only rows a script resolves (D10). Each remaining row's `resolved_at` keeps only `<workflow>.<step>` sites. The four rows with no script site are removed: `remediation_approach`, `version_bump_type`, `route_ambiguous` and `resume_or_skew`. The Ask Set still asks a router `ambiguous` outcome (`decision-autonomy.md:14`), because the Ask Set, not the table, governs the overlord. The generated scripts are rebuilt, since `AUTONOMY_TABLE` changes.

### Waves rule home

`plugin/workflow-src/lib/waves.js` becomes the rule's home (D13). Its header drops `next-wave.sh` as the parity oracle and names `tests/next-wave/expected/` as its frozen expectations. `tests/next-wave/*.json` stay where they are.

### Removed components

Removed by D10, which names each item's replacement:

- the six JSON definitions;
- `plugin/skills/{init-run-ledger,record-state-result,next-wave,mark-intent-fallback}/`;
- `plugin/skills/decision-report/` (D7);
- `plugin/references/run-ledger-schema.md`;
- `plugin/skills/_shared/ledger-engine-io.sh` and `ledger-project.sh`;
- `hivemind_brood_read_child_ledger` in `brood-state.sh` and `hivemind_assert_ledger_contained` in `containment.sh`;
- the four overlord sections named in Context and code truth.

### Validation tooling

- `tools/build_workflows.mjs --check` fails on any entry of `plugin/workflows/` that is not a generated `.js` with a source directory, so the folder holds only generated scripts (D10).
- `tools/validate.sh` loses the map entries and suites of the deleted paths.
- CHECK 15 keeps its `plugin/**/*.md` arm and loses its `plugin/workflows/*.json` arm.
- The reviewer `exit_reason` coverage that `validate_workflows.sh` checked against the definitions moves, for both producers, to a workflow-scripts test (D18).

## State and ownership

| State | Where | Writer | Readers | Change |
|---|---|---|---|---|
| Working branch, commits, pull request | git and GitHub | the overlord through `hivemind:create-working-branch`, `hivemind:molt`, `hivemind:open-plan-pr`, `hivemind:push-branch`; script runners | the facts step, the watch, the user | Unchanged. See the run record rule. |
| Facts file | `.hivemind/facts/facts-<UTC>Z-<12 hex>.json` | `hivemind:gather-facts` | the planner; `spawn-brood.sh` and `brood-status` (name and type only) | Unchanged shape. The only started-evidence of a strain. |
| Taken decisions | the final message or final report; for a run that opens or reuses a pull request, also its body or a comment, its decision journal, per Decision journal | script code; the overlord on Instinct | the user | Instinct adds the final report line and the body or comment write. No local copy. |
| Brood manifest | `.hivemind/broods/<brood-id>/manifest.json` | `spawn-brood.sh` | `brood-status`, `enable-brood-remote` | Loses the `hatchery` block. `manifest_version` stays 4. |
| Paused script run | the Workflow tool's own run store | the harness | `resumeFromRunId` | Unchanged; owned by Claude Code. |
| Run ledgers from older versions | `.hivemind/runs/<run-id>/` | none | none | Neither read nor deleted. The user owns them and may delete them by hand. |
| `.decision-report-done` markers | inside old run dirs | none | none | Left as they are. |

**Run record rule.** A run is recorded by the working branch, commits and pull request it opens, and a new session recovers from them (ADR-0037 decision 2). A run that opens no branch and pull request, such as `analysis-only` on its script or on Instinct, keeps no run record (ADR-0036 decision 10), so a new session starts it over; a brood dispatch is still recorded by its brood manifest. No run keeps a run ledger.

RUN-OWNERSHIP-01 is retired with the run ledger. The ownership it kept holds by worktree isolation without it: a child writes only in its own worktree, and the hatchery reads a child's facts file name and type, never its content. Children never write the brood manifest.

### Run ledger fields

Each field of the run ledger has one replacement, or is retired with none. The rows are keyed on two closed sets read from trunk at `3dc89eff`: every field section of `plugin/references/run-ledger-schema.md`, with the `plan_epoch` event field, the Brood and Hatchery parent blocks and the intent-fallback marker; and every `event.outputs` key a file under `plugin/` writes. ADR-0048 decision 8 reads this table and D10 as the map from a removed item to its replacement. A row set by a decision this design took itself, such as D13, D15 or D17, reaches an accepted ADR only through decision 8.

| Field | Replacement | Set by |
|---|---|---|
| `schema_version` | Retired, none: no run ledger is written. | D1 |
| `run.*` (`id`, `workflow`, `workflow_version`, `status`, `mode`, `created_at`, `updated_at`) | A script run's identity is the Workflow tool's run, resumed by name with `resumeFromRunId`; an Instinct run's is its working branch, per the run record rule. The workflow is the router's in-session selection. A run's status is its completion notice or final report, and a brood strain's is the observed `derived_status`. `workflow_version` and the version-skew door are retired, none. `mode` is retired with the intent-fallback marker. The timestamps are retired, none; commits and the pull request carry their own. | D1, D6, D8 |
| `parent.*` | Retired, none: a run has no ledger parent. | D1 |
| Brood parent block (`parent.kind: brood`) | The strain's `run.suggested_id` in the brood manifest and in its `task.md`, the strain's lineage key. | D15 |
| Hatchery parent block (`artifacts.brood`) | The brood manifest at `.hivemind/broods/<brood-id>/manifest.json`, which records a brood dispatch. | D4 |
| `request.*` (`raw`, `normalized`) | The in-session request text. The default post-PR watch reads it for its one yes or no question, as the Reflex tail does. | D1 |
| `state.*` | Retired, none: a script holds its own steps in code, and Instinct states must-haves, not states. The dashboard's claimed-state columns go with it. | D1, D8 |
| `facts.*` (`branch`, `base`, `pr`) | The facts file of `hivemind:gather-facts`, gathered fresh before every planner delegation. | D6, D11 |
| `plan.*` (`path`, `current_step`, `steps`, `epoch`) | The plan `hivemind:cerebrate` returns in the session. A script computes its waves in `plugin/workflow-src/lib/waves.js`, and on Instinct the overlord forms each wave by the same rule. `epoch` is retired, none. | D1, D13 |
| `plan_epoch` (event field) | Retired, none: no event log remains to scope. | D13 |
| `artifacts` | Retired, none, apart from the Hatchery parent block row. | D1 |
| `events` | The checkpoint commits, the pull request and the run's final report, per the run record rule. | D1, D6 |
| `blockers` | The `blocker:` line of the completion notice or final report. | D1 |
| Intent-fallback marker (`run.mode: intent_fallback`) | The one fallback rule: the switch is said in one line and in the final report. | D2 |
| `event.outputs.decisions[]` | The decisions a run lists in its final message or final report; for a run that opens or reuses a pull request, also in its body or a comment, its decision journal, per Decision journal. | D7 |
| `event.outputs.pr`, `event.outputs.head_ref_oid` | The pull request on GitHub, read by the facts step and the watch. The PR head rule of `## Safety Rails` resolves the head before any reviewer. Their reader, the post-merge report, is retired. | D7, D11 |
| `event.outputs.recurrence_origin` | The same key and value in the cluster payload forwarded to `hivemind:cerebrate`, and in the decision the run lists, per Decision journal. | D17 |
| `event.outputs.completed_steps` | One `hivemind:molt` commit per wave on the branch; a script's own wave state in code. A new session plans what is left from the branch history. | D6, D13 |
| `event.outputs.watch_optout_citation` | The final report of the run that does not watch names the verbatim span of the request it relied on, as the Reflex tail does today (`plugin/agents/overlord.md:61`). | D1 |
| `event.outputs.commit` | The `commit:` line of the `hivemind:molt` checkpoint the gates held on, passed as `expect_commit`. The input gates of `hivemind:open-plan-pr` and `hivemind:push-branch` refuse a push without it. | D11 |
| `event.outputs.plan_path` (the schema's example event) | The plan in the session, as the `plan.*` row says. | D1 |

## Contracts and seams

### Launch and fallback contract

The launch args, the relay of the completion notice, the resume by name and `retry_minutes` are unchanged (`plugin/agents/overlord.md:21-39`). Proposed text of the one fallback rule, replacing the second sentence of `:29` and the sentences of `:37` this text restates, keeping any other:

> At an interactive autonomy level, the only levels today, the request continues on Instinct without asking, said in one line, in two cases. A launch that is refused or blocked (denied, not found, or workflows turned off) continues on the path that matches its workflow: `standard-delivery` as a delivery, `analysis-only` as a read-only analysis, `pr-feedback-remediation` as a post-PR remediation on the route the request asked for, watch or fix. A started `standard-delivery` run that fails or ends blocked continues from the branch's last commit. A started run of any other workflow is reported as it ended. The final report says it switched and where the run stopped. Uncommitted edits a failed run left stop the takeover per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State) and are never discarded. Instinct never relaunches a workflow. A run the user stopped does not fall back.

A watch ending `planner-escalation` or `root-cluster-suspected` outside Instinct still launches `pr-feedback-remediation` with `{"references": [<the pull request number>], "trunk": "<the resolved trunk>"}`, and a refused launch of it takes the rule above.

### Level check seam

The level clause, "At an interactive autonomy level, the only levels today", is the one level check, and it comes before the fallback. #607 adds the `unattended` level and owns the sentence for it, placed in this paragraph and nowhere else. At that level neither case continues on Instinct: the run ends or parks instead, as ADR-0045 decision 6 states. This design writes no unattended behavior. It only guarantees one place for it: no other Instinct takeover exists to miss.

### Router output contract

```yaml
status: selected | ambiguous | blocked
workflow: analysis-only | standard-delivery | pr-feedback-remediation | hatchery-dispatch   # selected only
candidates: [...]                                                                           # ambiguous only
```

The `exploratory` shape is removed. `requires_confirmation`, `confidence`, `execution_mode_hint` and `reason` are unchanged. A caller that still sees `exploratory` has no such outcome to act on; the overlord treats any unknown status as `blocked` and surfaces it.

### spawn-brood inputs and manifest

The inputs object loses `hatchery`. A caller-supplied `hatchery` is ignored. The manifest loses the top-level `hatchery` block. Every other field, `manifest_version: 4` included, is unchanged, because no reader reads the block: a manifest written before the change still reads the same. In `SKILL.md`, the `hatchery` bullet (`:37-39`), the `hatchery` object of the Procedure's inputs example (`:55-58`) and its field rule (`:73`) are deleted, with no replacement text.

### brood-status collect output

Schema `brood-status-collect/2` is `brood-status-collect/1` without `workflow_state` and `run_status` on each strain. The navigator renders:

```
| Strain | Branch | Session | PR | Hatchery Status (observed) |
|--------|--------|---------|----|----------------------------|
| <name> | <branch> | <session> | <pr> | <derived_status> |
```

The `NO_LEDGER_POINTER` token leaves the output. The projector keeps the no-demotion rule for a strain with no `run.suggested_id` through an internal flag, not an output field.

### Decision journal destinations

Per Decision journal. On Instinct, the final report block (`plugin/agents/overlord.md:236-245`) gains one line after `Review:`:

```text
Decisions: [one line per taken decision | None]
```

When Instinct opens a pull request, `hivemind:open-plan-pr`'s `body` holds the same lines under "Decided for you". On a reused pull request, a post-PR remediation included, they go in its `comment` input, which the script posts only on a reused pull request (`plugin/skills/open-plan-pr/SKILL.md:31`). This is the route the `pr-feedback-remediation` script already takes (`plugin/workflow-src/lib/pr.js:42-44`).

### Waves expectation files

`tests/next-wave/expected/<case>.json` holds one `computeWave` result per case: each `tests/next-wave/*.json` fixture, each override and mutation case of `waves.test.mjs:440-462`, and each seeded-corpus case at `DEFAULT_SEED`. They are captured from `next-wave.sh` at the last commit that still has it, in the same slice and before the deletion. `waves.test.mjs` compares `waves.js` against them. The `WAVES_PARITY_SEED` override is removed, since no oracle can answer another seed.

### Lair seams

- **#607:** the level check seam above; `## Resume On Start` no longer exists, so "no Resume On Start question" holds with no code.
- **#604 and #608:** spawn through the brood tooling. Their launch reads no manifest `hatchery` block. #608's admission and pre-spawn scan for Lair strains are unchanged by this design. The human strain approval applies to overlord brood dispatch.
- **#606 and the Lair result:** read `lair-result.sh` output, not `brood-status`, so the collect schema change does not reach them.

## Trust boundaries

Every boundary below holds on every remaining path. No credential, tool grant, `allowed-tools` entry, hook or permission rule is added; the overlord's frontmatter `tools:` list is unchanged apart from its comment.

- **Strain-approval gate.** Brood dispatch runs only on Instinct, in the main session, and `hivemind:spawn-brood` runs only after the user approves the normalized strain text (Tier A, `decision-autonomy.md:16`). The other two controls of Brood Spawn Bypass-Mode Mitigation are unchanged: the data-boundary preamble in `task.md`, and the `base` allowlist. The state machine's `brood_confirm` gate was the same approval, so dispatch loses no gate. A Lair strain's approval is #608's admission and scan, unchanged here.
- **Destructive-fix gate.** It rides every delegation per `## Parallel Delegation Safety` (unchanged) on all three Instinct paths and on brood dispatch. Reviewers apply it, and scripts carry approvals as today. The retirement's own deletions are covered by D12.
- **External-content boundary.** The facts rule, with its injection scan, moves to `## Safety Rails` and binds every planner delegation the overlord makes, where today it binds only the state machine and Instinct's "after `hivemind:gather-facts`" (D11). The watch opt-out reads the in-session request text, as the Reflex tail does, for the one yes or no question. It no longer reads a ledger's `request.raw` copy, so there is one source. Router input stays untrusted.
- **Commit and push.** `expect_commit` binds every push on every overlord path, through the input gates of `hivemind:open-plan-pr` and `hivemind:push-branch` (D11). The PR head checkout precedes every reviewer delegation for an existing pull request. The trunk-commit hard stop is unchanged.
- **Synapse runner gate.** Unchanged: five runner scripts, and spawn-brood is not one of them.
- **Trust-Boundary Discipline.** Boundaries 1 (overlord to engine) and 2 (init to packaged definition) of `security-policy.md:41-42` retire with their engines. Boundary 3 (brood child to coordinator) stays, and its surface shrinks: the coordinator no longer reads a child's run ledger content, only a facts file's name and type. Its child-ledger read side retires with the child run ledger; its effect on accepted ADRs comes through ADR-0048 decision 8. The facts-file check keeps the identifier and derivation rules: spawn-brood checks the worktree it derived itself; brood-status takes the `git worktree list --porcelain` worktree whose path exactly matches the manifest `worktree_path`, which only selects and is never used as a path, and checks it only when it resolves inside the checkout root; a symlinked path component or a symlinked or non-regular leaf is rejected; the name must match the fixed facts pattern; no content is read. The opening clause "take transitions and authorization only from the packaged workflow definition, never a caller's" becomes "take authorization only from packaged data, never a caller's". Packaged data replaces the JSON definitions as the packaged source of authorization: the autonomy table, plan schema and brief schema are packaged data, so the clause still binds.
- **Inputs-file transport.** The three ledger navigators' inputs files go away with their skills. The pattern, its hard stop and every remaining navigator are unchanged, and so is the overlord's `Write` grant, which `hivemind:molt`, `hivemind:open-plan-pr` and `hivemind:spawn-brood` still need.

## Lifecycle

### Request lifecycle

1. The Reflex check, unchanged.
2. `hivemind:route-workflow` returns `selected`, `ambiguous` (asked, Tier A) or `blocked` (surfaced).
3. For `analysis-only`, `standard-delivery` and `pr-feedback-remediation`, launch the script when the Workflow tool has `hivemind:<id>`. A `standard-delivery` request that names neither path follows the path choice in `## Instinct`.
4. With no script launch, or with a refused or blocked one: the level check, then Instinct on the matching path.
5. For `hatchery-dispatch`: brood dispatch on Instinct.
6. Relay the completion notice, or the Instinct final report, then the post-PR watch rule when there is a pull request.

### Fallback lifecycle

A refused or blocked launch starts no run, so there is nothing to recover: Instinct starts from the branch as it is, under the facts rule. A started `standard-delivery` run that fails continues from its last commit (ADR-0039 decision 4). Uncommitted edits stop the takeover. Instinct never relaunches a workflow, so the fallback cannot loop.

### Brood dispatch lifecycle

Facts, then the brood plan, then the approval, then spawn, then monitoring. A child boots on a detached HEAD at its base, routes like any session, and writes its facts file on its first planner delegation, on the script or on Instinct. Until then `brood-status` shows it `starting`.

### Resume lifecycle

There is one resume path. In the same session, a paused or stopped script run resumes by name with `resumeFromRunId`, unchanged. In a new session, the request is given again and recovers per the run record rule: the planner plans what is left from the facts file's branch history and the files as they are now, and an `analysis-only` run, which has no branch, starts over. That holds on Instinct too, because every Instinct planner delegation reads fresh facts. No session-start scan runs.

### Upgrade lifecycle

A consumer upgrading from a version with the state machine:

- `.hivemind/runs/` stays on disk, unread. A run that was `running` there is not resumed. Giving the request again recovers it per the run record rule; an `analysis-only` run has no branch and starts over.
- `HIVEMIND_ENABLE_DECISION_REPORT` left in settings has no effect.
- A brood spawned before the upgrade shows only the observed status column. Its manifest's `hatchery` block is ignored.
- A `Workflow(hivemind:<id>)` deny entry now sends any workflow to Instinct, where it sent `analysis-only` and `pr-feedback-remediation` to the state machine.

## Existing-path coverage

One row per current path, with its effect and the slice (Seam order) that makes it. "Unchanged" rows name the slice that relies on them, or none.

| Existing path | Effect | Slice |
|---|---|---|
| `plugin/agents/overlord.md` `## Engine` | One fallback rule with the level clause; the `:29` state-machine clause and the "Do not enter the workflow state machine" sentence go. | S4 |
| `plugin/agents/overlord.md` `## Safety Rails` | Gains the facts and PR head rules; the `:57` bullet is replaced. "workflow state" leaves the opening line. | S4 |
| `plugin/agents/overlord.md` `## Reflex (Ledger-Skip)` | Heading kept (D16); body drops "and the run ledger". | S4 |
| `plugin/agents/overlord.md` `## Instinct` | Gains the analysis and post-PR remediation paths; the first paragraph says it is the fallback for every workflow. | S4 |
| `plugin/agents/overlord.md` `## Parallel Delegation Safety` | Unchanged; binds every wave. | S4 |
| `plugin/agents/overlord.md` `## Workflow State Execution` | Deleted. Step 2's `exploratory` outcome goes first, in S1. | S1, S4 |
| `plugin/agents/overlord.md` `## Implement Loop (Wave Execution)` | Deleted after its PR identity rule moves to `## Safety Rails`; its gated-commit rule is not restated, since the skills' input gates own it (D11). | S4 |
| `plugin/agents/overlord.md` `## Resume On Start` | Deleted, with the deferred report scan. | S4 |
| `plugin/agents/overlord.md` `## Intent-Driven Fallback (Universal)` | Deleted. | S4 |
| `plugin/agents/overlord.md` `## Review Remediation Posture` | Default post-PR watch reads the in-session request text; a run that does not watch names the relied-on span in its final report, as the Reflex tail does (`plugin/agents/overlord.md:61`), so the `watch_optout_citation` duty moves there (Run ledger fields); the `github_review_decision`, `request.raw` and `event.outputs` text goes; state names in Routing-vs-Execution, Root-cluster zoom-out and Proactive recurrence become "a remediation plan from `hivemind:cerebrate`". | S4 |
| `plugin/agents/overlord.md` `## Brood Execution` | Becomes brood dispatch on Instinct; the child-ledger clause and RUN-OWNERSHIP-01 go. | S2 |
| `plugin/agents/overlord.md` `## Skills` | Loses the four ledger skills and `hivemind:decision-report`. | S4 |
| `plugin/agents/overlord.md` `## Model Routing`, `## Delegation Format`, `## Continuous Execution`, `## Tool-Error Recovery` | Unchanged; `## Delegation Format` drops "state or". | S4 |
| `plugin/agents/overlord.md` `### Stop Conditions` | The `user_gate` bullet and the run-ledger journal rule go; the journal rule points to `plugin/governance/decision-autonomy.md` (Decision Journal), the one shipped statement. | S4 |
| `plugin/agents/overlord.md` `## Final Report` | Gains the `Decisions:` line. | S4 |
| `plugin/agents/overlord.md` frontmatter | `description` drops "workflow-state execution"; the `Write` comment drops ADR-0018 and ADR-0019. Tools unchanged. | S4 |
| `plugin/agents/cerebrate.md:238-251` | "on both engines: on the state machine ..." becomes "on a workflow script and on Instinct"; the open-question form names the question brief only. | S4 |
| `plugin/agents/drone.md`, `changeling.md`, `local-reviewer.md`, `github-reviewer.md`, `synapse.md` | Unchanged. | none |
| `plugin/skills/route-workflow/SKILL.md` | Catalog loses `exploratory-intent-session`; the `exploratory` outcome and §G go; the no-fit rule is added; the `Rules:` line at `:20` drops ADR-0018 and §G. | S1 |
| `plugin/workflows/*.json` (six) | Deleted. | S5 |
| `plugin/workflows/*.js` (three) | Rebuilt for the autonomy table change; otherwise unchanged. | S5 |
| `plugin/workflow-src/lib/waves.js` | Header names its own rule and the frozen expectations. | S5 |
| `plugin/workflow-src/**` other files | Unchanged, except `standard-delivery/contract.js` rows SD-35 (`:59`) and SD-86 (`:107`), which drop their `standard-delivery.json` clauses. | S5 |
| `plugin/skills/init-run-ledger/`, `record-state-result/`, `next-wave/`, `mark-intent-fallback/` | Deleted. | S5 |
| `plugin/skills/decision-report/` | Deleted. | S4 |
| `plugin/skills/spawn-brood/` | Drops the `hatchery` input and block and the child-ledger started-evidence; the `SKILL.md:21-24` lines that say child state lives in each child's own run ledger and that `hatchery.ledger` only points at the hatchery ledger are reworded to the facts file. | S2 |
| `plugin/skills/brood-status/` | Drops the claimed columns and child-ledger reads; schema `brood-status-collect/2`. | S3 |
| `plugin/skills/enable-brood-remote/` | Unchanged; reads no `hatchery` block. | S2 |
| `plugin/skills/bump-type/SKILL.md:13` | "backs the `version_bump_decision` workflow state" becomes "backs the version bump decision on Instinct". | S5 |
| `plugin/skills/gather-facts/`, `injection-scan/`, `molt/`, `open-plan-pr/`, `push-branch/`, `create-working-branch/` | Unchanged; Instinct relies on them. | S4 |
| `plugin/skills/github-review-loop/` | Unchanged; the watch and its `loop-state.sh` already run outside the state machine. | S4 |
| `plugin/skills/_shared/brood-state.sh` | `hivemind_brood_read_child_ledger` and its `ledger-project.sh` dependency note go, and the comments at `:19` and `:105` that name `ledger-project.sh` are reworded. | S5 |
| `plugin/skills/_shared/brood-status-derive.sh` | The gate keys on `facts_evidence` alone. | S3 |
| `plugin/skills/_shared/ledger-project.sh` | Deleted once S2 and S3 removed its two consumers. | S5 |
| `plugin/skills/_shared/ledger-engine-io.sh` | Deleted. | S5 |
| `plugin/skills/_shared/containment.sh` | `hivemind_assert_ledger_contained` goes; the header drops the ledger engines. | S5 |
| `plugin/skills/_shared/ledger-reconstruct-fold.sh`, `ledger-reconstruct-parse.sh` | Unchanged (fix ledger). | none |
| `plugin/skills/_shared/settings-merge.sh:682` | The comment's `next-wave.sh` comparison names `plugin/workflow-src/lib/waves.js`. | S5 |
| `plugin/skills/_shared/settings-merge.sh:390-392` | The seed-hive template drops the `Edit(.hivemind/runs/.init-inputs-*.json)`, `.record-inputs-*` and `.markfb-inputs-*` grants of the deleted navigators. | S5 |
| `plugin/skills/_shared/json-normalize.sh:75`, `:82` | The comments that name `ledger-project.sh` are reworded. | S5 |
| `.claude/settings.json:57-59` | The same three inputs-file grants go from this repository's settings. | S5 |
| `plugin/references/run-ledger-schema.md` | Deleted. | S5 |
| `plugin/references/decision-autonomy-table.json` | Four rows removed; `resolved_at` keeps script sites. | S5 |
| `plugin/references/plan-schema.json`, `decision-brief-schema.json`, `facts-schema.json` | Unchanged. | none |
| `plugin/governance/decision-autonomy.md` | Ask Set loses the resume bullet; the Promotion Gate's state-machine clauses (`:66`, `:68`) name Instinct; Decision Journal rewritten to the journal rule; Post-Merge Decision Report Trigger deleted. | S4 |
| `plugin/governance/security-policy.md` | Trust-Boundary Discipline loses boundaries 1 and 2, its opening clause is as Trust boundaries says, and boundary 3's per-strain ledger anchor and run id become the facts-file check of Trust boundaries; Inert Inputs-File Navigator Pattern drops ADR-0018. | S5 |
| `plugin/governance/remediation-doctrine.md` Proactive Zoom-Out Ledger Marker | Rewritten as the cluster payload marker (D17). | S4 |
| `plugin/governance/workflow.md:45` | "workflow script, state machine, or any step outside both" becomes "workflow script or Instinct". | S4 |
| `plugin/governance/definitions.md`, `safety-rails.md`, `versioning.md`, `report-format.md` | Unchanged. | none |
| `plugin/hooks/` | Unchanged. | none |
| `tools/test_engine.sh`, `tests/engine/` | Deleted. | S5 |
| `tools/test_next_wave.sh` | Deleted; `tests/next-wave/*.json` stay; `tests/next-wave/expected/` added. | S5 |
| `tools/validate_workflows.sh`, `tests/workflow-defs/` | Deleted. | S5 |
| `tests/workflows/golden-*.json` and the WORKFLOW-FIXTURES check of `tools/policy_check.sh:6158-6192` | Fixtures citing a definition are deleted; fixtures citing live prose are kept and re-pointed. | S5 |
| `tools/policy_check.sh` CHECK 15 | The `plugin/workflows/*.json` arm and its zero-count finding go. | S5 |
| `tools/policy_check.sh:3934`, `:3981` (CHECK 16 canary) | The canary cases that name `.hivemind/runs/.record-inputs-*.json` go with the deleted navigator, or switch to a live navigator's inputs glob; every other canary case stays. | S5 |
| `tools/validate.sh` | Map entries and suite names of the deleted paths go. | S5 |
| `tools/test_shared_libs.sh` | Cases of the deleted functions go; the seed-hive template case (`:2871-2904`) drops the three `.hivemind/runs/.` inputs-file grants, as `settings-merge.sh:390-392` does. | S5 |
| `tools/test_brood_compat.sh`, `tests/brood/child-ledger-present.json` | Child-ledger cases and the fixture go; facts-only cases added. | S2, S3 |
| `tools/test_rc_brood.sh` | Fixture manifests drop the `hatchery` block, and one keeps it to prove it is ignored. | S2 |
| `tools/test_script_bootstrap.sh` | Rows of the deleted scripts go. | S5 |
| `tools/test_workflow_scripts.sh:17`, `:45` | The `next-wave.sh` oracle requirement goes; the runner needs no oracle once `waves.test.mjs` reads the frozen expectations. | S5 |
| `tools/build_workflows.mjs` | `--check` fails on any non-generated entry in `plugin/workflows/`. | S5 |
| `tests/workflow-scripts/build.test.mjs:466-471` | Inverted: a `.json` there is a finding. | S5 |
| `tests/workflow-scripts/standard-delivery.test.mjs:45`, `:4853-4913` | The definition-graph cases go; the script's own gate cases stay. | S5 |
| `tests/workflow-scripts/data.test.mjs:127` | Inverted: every site is a script site. | S5 |
| `tests/workflow-scripts/waves.test.mjs` | Compares against `tests/next-wave/expected/`. | S5 |
| `tests/workflow-scripts/state-machine-questions.test.mjs` | Deleted. | S5 |
| `tests/workflow-scripts/overlord-contract.test.mjs` | State-machine pins go; each slice adds the pins its Verification strategy item needs. | S1, S2, S4, S5 |
| `tests/workflow-scripts/route-catalog.test.mjs` | Pins the four entries and the no-fit rule. | S1 |
| `tests/policy/*.json` naming deleted text | Each pin moves to the re-homed text, or goes with its deleted rule. | S4, S5 |
| `tests/policy/prose-byte-budget.json` | Overlord lowered; deleted files' entries go. | S4, S5 |
| `tests/policy/policy-lint-allowlist.json` | Entries for deleted paths go. | S5 |
| `CONTEXT.md`, `CLAUDE.md`, `README.md`, `docs/references/`, `docs/skill-authoring.md`, `web/` | Per Changes to shared documents. | each item names it |
| Lair docs, ADR-0045, Idea to Ready design, ADR-0046 | Per Changes to shared documents; only through their own re-review. | their initiatives |
| `.hivemind/runs/` on consumer disks | Neither read nor deleted. | S4 |

## Failure modes

| Failure | Handling | Slice |
|---|---|---|
| A run ledger left `running` by an older version | No scan reads it, and the session starts normally. Giving the request again recovers the run per the run record rule; an `analysis-only` run has no branch and starts over. The folder is never deleted by the plugin; README says the user may delete it. | S4 |
| A refused or blocked launch, or a failed started run, at an unattended level | The level check runs first. Today no unattended level exists, so the clause always passes to Instinct. #607 adds the level, whose sentence ends or parks the run instead, so an unattended strain never reaches Instinct's questions. | S4, #607 |
| A cut completion notice | A defect, said in one line, with what arrived shown, and no file read to recover the rest. The run counts as failed: a `standard-delivery` run continues on Instinct from its last commit (ADR-0039 decision 4), and any other run is reported as it ended. | S4 |
| `hivemind:spawn-brood` fails | Exit 1 with a `blocker:` line is relayed verbatim. It is a mutating call, so it is never retried (`## Tool-Error Recovery`), and it surfaces as a Tier A failed tool call. Strains it started before the failure stay in the manifest it wrote, with their `attach:` lines, and `hivemind:brood-status` shows them. Nothing falls back and nothing is re-spawned without the user. | S2 |
| The user declines the strain approval | Nothing spawns; the final report carries the brood plan. | S2 |
| A brood child writes no facts file (a Reflex child, or a child that fails before planning) | Alive: `starting`. Dead: `complete`, `blocked` or `failed` from its observables, as today. | S3 |
| A manifest written before the change | Its `hatchery` block is ignored; a strain with no `run.suggested_id` keeps the no-demotion rule. | S2, S3 |
| The Workflow tool is absent or workflows are turned off | Every launch is blocked, and every request runs on Instinct (P26). | S4 |
| A facts run fails, a field is cut, or the scan flags text before a planner delegation | No delegation; the `blocker:` line, the cut fields or the unaccounted texts are surfaced; an injection-suspect is the Tier A hard stop. | S4 |
| The PR head branch cannot be resolved or checked out | Post-PR remediation stops blocked before any reviewer. | S4 |
| A request fits no catalog entry | `analysis-only` or `standard-delivery` by whether it asks for a change, else `ambiguous` and asked. | S1 |
| `HIVEMIND_ENABLE_DECISION_REPORT` is still set | Nothing reads it; README says it is retired. | S4 |
| An overlord slice overruns its prose budget | S1 and S2 only delete overlord text. S4 adds the re-homed rules and Instinct paths in the same change that deletes four sections, so it shrinks. Any overrun is asked as a budget raise (Tier A), never raised silently. | S1, S2, S4 |
| A change to `waves.js` alters a wave | The frozen expectations fail. Changing an expectation is a test edit that the review sees; weakening one is covered by D12. | S5 |
| A slice deletes or narrows an item D12 covers, unconfirmed | The slice's run does not start until the user confirms each item (D12). | S1-S5 |
| A path under a deleted tree is left behind | `tools/validate.sh` maps it nowhere, so `--changed` escalates to the full suite (FAIL-CLOSED). | S5 |
| A slice edits a stamped document of another initiative | That record goes stale and its slices fail `record_stale`. No retirement slice edits one; each change lands through that initiative's own re-review (D19). | none |
| A brood child on Instinct asks an Ask Set question | It waits in its session, which stays alive and reachable through its `attach:` line, or through remote control when enabled, as a child on the state machine did. Unattended handling is #607's. | S2 |

## Decisions

The user answered Q1 A to Q6 A before design review round 1. Separately, after local review, the user accepted the amendment rule that ADR-0048 decision 8 records: a clause of an accepted ADR that relies on an item of D10 or on a run ledger field now relies on the replacement D10 or [Run ledger fields](#run-ledger-fields) names for it, or lapses where they name none. The rule reaches only a clause that relies on a removed item, never text that mentions the state machine as history. Every effect this design has on an ADR comes through decision 8, so no decision below lists ADR clauses of its own. No decision below changes the meaning of a clause that relies on no removed item; where a design sentence would, the design changes and the clause stands. A decision the design takes itself carries its design-decision screen (ADR-0046 decision 8, as amended 2026-11-22): a strong recommendation is taken and listed for veto whatever it touches, and only a weak or absent recommendation, or an action irreversible now (Promotion Gate clause 1, applied to the action taken now), is asked. The review record lists each taken decision with its recommendation strength and what it touches.

### D1: Retire the JSON state machine

Answered: Q1 A. The state machine is retired, and the workflow scripts, Instinct and Reflex remain. Two engines force every change to the overlord, governance and the decision flow to account for both. A fallback that knows neither unattended mode nor parks cannot serve the Lair. Its effect on accepted ADRs comes through ADR-0048 decision 8.

### D2: One fallback for every refused or blocked launch

Answered: Q2 A. Every refused or blocked launch is said in one line and continues on Instinct. One level check comes first and covers a failed started `standard-delivery` run as well, and there a future unattended level ends or parks the run instead (#607). One path leaves one place for #607 to change. Otherwise started runs keep their rules.

### D3: Instinct gains read-only analysis and post-PR remediation

Answered: Q2 A, which needs an Instinct path for each workflow the fallback serves, since no state machine remains to serve them. Its effect on accepted ADRs comes through ADR-0048 decision 8. Analysis makes no change; post-PR remediation keeps the watch, the fix pass and every delivery gate.

### D4: Brood dispatch runs on Instinct

Answered: Q3 A. Brood dispatch runs on Instinct. `hivemind:spawn-brood` runs only after the user approves the normalized strain text, with no new synapse runner grant, and its hatchery ledger pointer is retired. A script cannot hold the approval as a Tier A gate the way the main session does, and the synapse gate stays at five scripts.

### D5: Exploratory intent session removed

Answered: Q6 A. `exploratory-intent-session` is removed. A request the catalog does not fit routes to `analysis-only`, `standard-delivery` or `ambiguous`. The router keeps four entries.

### D6: Resume on start has one path

Answered: Q1 A. Resume is a same-session resume by name, or a new session that recovers the run per the run record rule; an `analysis-only` run has no branch and starts over. Run ledgers from older versions are neither read nor deleted, and the resume or version-skew ask leaves the Ask Set.

### D7: The pull request is the decision journal

Answered: Q4 A. The journal is kept as [Decision journal](#decision-journal) says. The post-merge report, its session-start scan, the `.decision-report-done` marker and `HIVEMIND_ENABLE_DECISION_REPORT` are retired; their effect on accepted ADRs comes through ADR-0048 decision 8. The pull request is where the user reviews the change, so the journal lives there.

ADR-0036 decision 9 stands as written, as ADR-0048 decision 8 records.

### D8: The brood dashboard reads no child ledger

Answered: Q5 A. The dashboard drops its claimed-state columns and child-ledger reads, and the gather-facts output file is the only started-evidence. Its effect on accepted ADRs comes through ADR-0048 decision 8 (see [Trust boundaries](#trust-boundaries)). Its observable status, the closed `derived_status` set and the demote-only gate are kept.

### D9: ADR-0005 is unchanged

Taken, listed for veto. Brood dispatch on Instinct runs in the main session, where the overlord holds the Agent tool. `hivemind:spawn-brood` starts separate sessions, not subagents. No workflow script or subagent gains a spawn, so the constraint ADR-0005 records still holds as written. Screen: strong recommendation; no action irreversible now.

### D10: The removal list

Answered: Q1 A, with the items D5, D7, D8 and D15 remove. Removed, each with its replacement or none:

- the six JSON definitions: the three workflow scripts run the workflows that have one, Instinct runs every other, and packaged data replaces the definitions as the packaged source of authorization, as [Trust boundaries](#trust-boundaries) says;
- the four run ledger skills and their scripts: `hivemind:init-run-ledger` and `hivemind:record-state-result` by the run record rule and [Run ledger fields](#run-ledger-fields); `hivemind:next-wave` by `plugin/workflow-src/lib/waves.js` in a script and by the same rule on Instinct (D13); `hivemind:mark-intent-fallback` by the one fallback rule (D2);
- the overlord's `## Workflow State Execution` section: Instinct paths, with the facts rule in `## Safety Rails` (D11) and its question gate by `### Stop Conditions`;
- the overlord's `## Implement Loop (Wave Execution)` section: the PR head rule in `## Safety Rails` (D11), the gated-commit rule in the input gates of `hivemind:open-plan-pr` and `hivemind:push-branch` (D11), and Instinct's waves;
- the overlord's `## Resume On Start` section: the run record rule and Resume lifecycle; its deferred report scan, none (D7);
- the overlord's `## Intent-Driven Fallback (Universal)` section: the one fallback rule (D2);
- `plugin/references/run-ledger-schema.md`: [Run ledger fields](#run-ledger-fields), one replacement per field;
- the ledger parts of the `_shared` libraries: `hivemind_brood_read_child_ledger` and `ledger-project.sh` by `hivemind_detect_facts_evidence`, the facts file as the only started-evidence (D8); `ledger-engine-io.sh` and `hivemind_assert_ledger_contained`, none, since no ledger read remains to bootstrap or guard;
- the ledger parts of the governance docs: the re-homed rules of `## Safety Rails` (D11) and the Decision journal rule; RUN-OWNERSHIP-01 by worktree isolation, as State and ownership says;
- the autonomy table's four rows and every state-machine `resolved_at` site: none, since the Ask Set and `### Stop Conditions` govern the overlord (D14);
- the ledger parts of `docs/skill-authoring.md`: none;
- the router's `exploratory` outcome, its catalog entry and §G (D5): the no-fit rule of Workflow router;
- the post-merge decision report, `hivemind:decision-report`, its session-start scan, the `.decision-report-done` marker and `HIVEMIND_ENABLE_DECISION_REPORT` (D7): the pre-merge list of Decision journal;
- the brood dashboard's claimed-state columns (D8): its observed status column;
- spawn-brood's `hatchery` input and the manifest's `hatchery` block (D15): none; `run.suggested_id` stays the strain's lineage key;
- the engine tests and fixtures: the `waves.js` frozen expectations (D13), the reviewer `exit_reason` coverage (D18) and the checks Verification strategy says each slice builds; the rest, none;
- the `tools/validate.sh` map entries: none, since a path left behind escalates to the full suite (FAIL-CLOSED);
- CHECK 15's `plugin/workflows/*.json` arm: `tools/build_workflows.mjs --check`, below.

`tools/build_workflows.mjs --check` then keeps `plugin/workflows/` to generated scripts only.

### D11: Two rules re-homed in the safety rails

Answered: Q7 A. Two rules live only in text this design deletes, and each moves to `## Safety Rails` with its meaning kept:

- gather-facts and injection-scan run before every planner delegation;
- the PR head branch is checked out before any reviewer.

`## Safety Rails` binds every path the overlord drives, so each rule covers more paths than before, never fewer. The gated-commit rule, `expect_commit` on every push, is not restated in the overlord: the input gates of `hivemind:open-plan-pr` (`plugin/skills/open-plan-pr/SKILL.md:24`) and `hivemind:push-branch` (`plugin/skills/push-branch/SKILL.md:36`) refuse a push without it, so every push on every path meets the gate. The overlord text that states it today, at `plugin/agents/overlord.md:120`, goes with `## Implement Loop (Wave Execution)`.

### D12: Engine test deletion needs the user's confirmation

Answered: Q8 A. Every deletion or narrowing a slice makes that falls in a category of `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Destructive Fix Confirmation Gate), read at its broadest, governance clauses included, needs the user's confirmation of that item, as that gate's explicit approval, before the slice's run starts. A drone applies the gate only to review fixes, so no delegation asks it; the confirmation happens in the main session before the run.

### D13: waves.js keeps its parity fixtures as frozen expectations

Taken, listed for veto. `waves.js`'s oracle, `next-wave.sh`, is deleted, so its outputs are captured once into `tests/next-wave/expected/` before the deletion, in the same slice, and the fixtures stay. The test keeps every case it checks today except other seeds. Screen: strong recommendation; no action irreversible now.

### D14: The autonomy table keeps only script sites

Answered: Q1 A, as the autonomy table part of the removal list. The four rows no script resolves are removed, and `resolved_at` keeps `<workflow>.<step>` sites. A row a script resolves whose `resolved_at` lacks that script's site, such as `planner_question` for `analysis-only` (`plugin/workflow-src/analysis-only/main.js:417`), gains the site. The overlord decides by the Ask Set and `### Stop Conditions`, never by the table. The table is only `decide()`'s data, so rows nothing reads would drift.

### D15: The manifest keeps version 4 without the hatchery block

Taken, listed for veto. No reader reads the `hatchery` block, so dropping it changes nothing a reader sees. A version bump would make old and new manifests read differently for no gain. A caller-supplied `hatchery` input is ignored, as other script-owned fields are. Screen: strong recommendation; no action irreversible now.

### D16: The Reflex heading is kept

Taken, listed for veto. `## Reflex (Ledger-Skip)` is cited by heading text in `CONTEXT.md`, README and `web/`, and a Reflex still keeps no run ledger. Renaming it would churn every citation for no behavior. Only its body drops "and the run ledger". Screen: strong recommendation; no action irreversible now.

### D17: The proactive zoom-out marker rides the cluster payload

Taken, listed for veto. `recurrence_origin: "proactive"` was written to a run ledger event so the forced zoom-out could be told from a reviewer-returned cluster (`plugin/governance/remediation-doctrine.md:178-190`). With no ledger, the overlord puts the same key and value in the cluster payload it forwards to `hivemind:cerebrate`, and in the decision the run lists. The section heading becomes `### Proactive Zoom-Out Marker`, and its citers in `plugin/agents/overlord.md` and `tests/policy/safety-proactive-recurrence-routing.json` change in the same slice. The forced zoom-out's exception in the remediation-plan rule is unchanged, and the trip call stays judgment as ADR-0025 places it. Screen: strong recommendation; no action irreversible now.

### D18: Exit-reason routing coverage moves to a workflow-scripts test

Taken, listed for veto. The reviewer `exit_reason` coverage of `tools/validate_workflows.sh` (producer contract, `:96-150`) moves to a workflow-scripts test, for both producers: `hivemind:github-review-loop` and the fix pass of `hivemind:github-reviewer`, which Instinct's post-PR remediation runs. The slice designs the test. The scripts' own `exit_reason` tests are unchanged. Screen: strong recommendation; no action irreversible now.

### D19: Stamped documents change only through their own re-review

Taken, listed for veto. Text in another initiative's stamped document is changed only by that initiative's own re-review and re-stamp (ADR-0046 decision 6, Review fix), never in a retirement slice. Editing it in a retirement slice would make its record stale and fail every slice of it. This applies to the Lair designs, ADR-0045, the Idea to Ready design and ADR-0046. ADR-0048 decision 8 already reaches a clause of ADR-0045 or ADR-0046 that relies on a removed item; its wording changes only through that re-review, as a dated note that points to ADR-0048 decision 8. Screen: strong recommendation; no action irreversible now.

### Changes to shared documents

Exact proposed text for each document. None is edited in this run. Each item names the slice that lands it. An item in another initiative's stamped document lands only through that initiative's re-review (D19).

Two named sentences carry the user-facing decision-list and record facts.

- **List sentence:** "A run lists the decisions it took in its final message or report, and on its pull request when it opens or reuses one, so you can veto them before you merge. A read-only analysis opens no pull request, so its final message or report is its whole list."
- **Record sentence:** "No path keeps a run ledger: a run that opens a branch and a pull request is recorded by them, and a run that opens none, such as a read-only analysis, keeps no record."

**1. `CONTEXT.md`** (S5)

- Replace the **Instinct** entry (`:92-94`) with:

  > **Instinct**:
  > A permanent, named path the overlord drives by judgment, with no workflow script. Pairs with **Reflex**: Reflex is the trivial fast path, Instinct the full run done by intent. It delivers a `standard-delivery` request, runs a read-only analysis, remediates review feedback on an existing pull request, and dispatches a **Brood**. It names what every run must have (a plan from fresh facts, a **Working Branch** when the run changes files, delegated edits, **Molt** commits and the delivery gates) and leaves order to judgment; not a step sequence. At an interactive autonomy level, it is the one fallback for every refused or blocked workflow launch and for a started `standard-delivery` run that fails or ends blocked. A started run the **Guide** launched is the exception: when it fails or ends blocked it returns to the **Guide** (ADR-0046). The rules live in `plugin/agents/overlord.md` (`## Engine`, `## Instinct`, `## Brood Execution`), ADR-0039 and ADR-0048.
  > _Avoid_: light path (the placeholder name), manual mode

- Replace the **Decision Journal** entry (`:249-251`) with:

  > **Decision Journal**:
  > The decisions a run that opens or reuses a pull request took for the user, one line each, listed on that pull request and in the run's final message or report. A run with no pull request keeps none; where it lists its decisions is set by ADR-0048 decision 6.
  > _Avoid_: audit log, decision log

- Delete the **Decision Report** entry (`:253-255`).
- Replace `### Workflow State Machine` (`:415`) with `### Routing`, keep only **Workflow Router** under it, and replace that entry (`:425-427`) with:

  > **Workflow Router**:
  > The `hivemind:route-workflow` skill — the sole classifier that selects a workflow for a request by judgment (never a keyword lookup table). Outcomes: `selected`, `ambiguous` (2+ known → confirm gate) and `blocked` (unsafe/illegible only). A request no workflow fits goes to `analysis-only` when it asks for no change, to `standard-delivery` when it asks for one, and is `ambiguous` otherwise. A selected workflow launches its workflow script when it has one and the launch goes ahead; otherwise it runs on **Instinct**.
  > _Avoid_: classifier, dispatcher, intent matcher

- Delete **Workflow Definition**, **Run Ledger**, **Exploratory Intent Session**, **Transition Engine**, **Run Ownership** and **Intent-Driven Fallback** (`:417-423`, `:429-443`).
- In Relationships, delete the Decision Report bullet (`:474`), the Intent-Driven Fallback and Run Ownership bullets (`:502-503`) and the format bullet (`:504`). Replace the Workflow Router bullet (`:498`) with:

  > - A **Workflow Router** selects exactly one workflow for a request; the **Overlord** launches its workflow script, or runs it on **Instinct** when it has none or its launch is refused or blocked

  Replace the Reflex bullet (`:499`) with:

  > - A **Reflex** (trivial fast path) bypasses the **Workflow Router** entirely — the **Overlord** drives the short delivery tail by intent, just as it skips the **Cerebrate**

  Replace the two Instinct bullets (`:500-501`) with:

  > - **Instinct** follows the **Workflow Router** — unlike a **Reflex**, it keeps the **Cerebrate** plan from fresh facts, the **Working Branch** and every delivery gate
  > - **Instinct** is the one fallback for a refused or blocked launch of any workflow, and for a failed `standard-delivery` run, except a started run the **Guide** launched; its rules live in ADR-0039, ADR-0046 and ADR-0048
  > - A **Hatchery** reads only a child's facts file name and type as started-evidence, never its other files, and never mutates them (consistent with ADR-0007)

- In Flagged ambiguities, add, ending with the Record sentence:

  > - "run ledger" — retired (ADR-0048). Files under `.hivemind/runs/` from older versions are neither read nor deleted. No path keeps a run ledger: a run that opens a branch and a pull request is recorded by them, and a run that opens none, such as a read-only analysis, keeps no record.

**2. `CLAUDE.md`** (S4 for the key, S5 for the rest)

- `:28`: `  workflows/                      # *.js generated workflow scripts, built from workflow-src/`
- `:134`: delete the `HIVEMIND_ENABLE_DECISION_REPORT` paragraph.
- `:143`: replace "Layout reference: `docs/references/brood-ledger-model.md`." with "Layout reference: `docs/references/brood-manifest-model.md`."

**3. `README.md`** (S1, S2, S4 or S5, as each item says)

- `:22` (S5): `- **jq**: required by the facts and git scripts (`hivemind:gather-facts`, `hivemind:molt`, `hivemind:open-plan-pr`), the brood scripts and `hivemind:seed-hive``
- `:23` (S4): `- Claude Code CLI. When Claude Code's Workflow tool is available, analysis requests, delivery requests and an escalated PR review run as workflow scripts, and a delivery request can also run on Instinct. Otherwise every request runs on Instinct (see [Scripts and Instinct](#scripts-and-instinct)).`
- `:61` (S4): delete the `.hivemind/runs/` bullet, and add after the list: `Earlier versions also wrote run ledgers to `.hivemind/runs/`. This version neither reads nor deletes them; you can delete that folder by hand.`
- `:66` (S5): replace "`.hivemind/seed-inputs-<token>.json`, `.hivemind/runs/.init-inputs-<token>.json`, and the molt" with "`.hivemind/seed-inputs-<token>.json` and the molt".
- `:76` (S5): delete "`Edit(.hivemind/runs/.init-inputs-*.json)`, `Edit(.hivemind/runs/.record-inputs-*.json)`, `Edit(.hivemind/runs/.markfb-inputs-*.json)`, ".
- `:111` (S4): delete the `"HIVEMIND_ENABLE_DECISION_REPORT": "1",` line.
- `:123` (S4): delete the row, and add after the table: `` `HIVEMIND_ENABLE_DECISION_REPORT` is retired: nothing reads it, and a value left in your settings has no effect. ``
- `:138` (S4): replace "The launch is then refused with no prompt and falls back: `analysis-only` and `pr-feedback-remediation` to the state machine, and `standard-delivery` to Instinct (see [Two engines](#two-engines))." with "The launch is then refused with no prompt and runs on Instinct (see [Scripts and Instinct](#scripts-and-instinct))."
- `:223-235` (S4): replace the `### Two engines` heading, its intro and its three bullets with:

  > ### Scripts and Instinct
  >
  > `hivemind:route-workflow` selects the workflow first, for every request that is not a Reflex. A workflow script or Instinct then runs it:
  >
  > - **Workflow scripts.** `analysis-only`, `standard-delivery` and `pr-feedback-remediation` launch as the `hivemind:analysis-only`, `hivemind:standard-delivery` and `hivemind:pr-feedback-remediation` Workflow scripts when Claude Code's Workflow tool is available. `analysis-only` has been a script since 6.0.0, `standard-delivery` since 7.0.0, and `pr-feedback-remediation` since 8.0.0.
  > - **Instinct.** The overlord drives a run by judgment, with no workflow script. It keeps the plan from fresh facts, the working branch and every delivery gate. A `standard-delivery` request can run on Instinct by choice: when it names neither the script nor Instinct, the overlord asks you which to use; a brood child, whose task carries a `working_branch.base` ref, takes the script. Brood dispatch (`hatchery-dispatch`) always runs on Instinct. Instinct is also the one fallback for every refused or blocked launch, and for a `standard-delivery` run that fails or ends blocked (ADR-0039, ADR-0048).

  and replace the `permissions.deny` bullet with:

  > - A `Workflow(hivemind:<id>)` entry in `permissions.deny` refuses the launch with no prompt. A refused or blocked launch of any workflow runs on Instinct, and so does a started `standard-delivery` run that fails or ends blocked. The fallback rules are in `plugin/agents/overlord.md` (`## Engine`), `docs/adr/0039-instinct-delivery-path.md` and ADR-0048.

- `:264` (S4): replace "A script run keeps no decision journal, so the final message and the run record on the PR are its only record of decisions." with "The final message and the run record on the PR are the run's decision journal."
- `:266` (S4): delete the sentence "That watch has no run ledger."
- `:268-292` (S4): replace the **State machine.** paragraph, its diagram and the numbered list 1-9 with this paragraph, which points to the Decision autonomy paragraph for the decision list:

  > **Instinct.** On Instinct the overlord runs the same lifecycle by judgment: it gathers facts and scans them before every cerebrate delegation, takes a plan, creates the working branch, builds in waves with one checkpoint commit per wave, runs validation and local review on one commit, and opens the PR with `hivemind:open-plan-pr` on the commit both held on. It lists the decisions it took as Decision autonomy below says. Only an Ask Set question asks you; any other is taken with its recommendation.

- `:298` (S5): replace "made by a runner in a script run and by the overlord on Instinct and on the state machine. On the state machine, `hivemind:next-wave` computes each wave from the run ledger; the script computes its waves in `plugin/workflow-src/lib/waves.js`." with "made by a runner in a script run and by the overlord on Instinct. The script computes its waves in `plugin/workflow-src/lib/waves.js`; on Instinct the overlord forms each wave by the same rule."
- `:300` (S4): replace "go to the overlord's question gate, which asks you" with "go to the overlord, which asks you".
- `:302` (S4): replace the **Decision autonomy.** paragraph with this paragraph, which uses the List sentence:

  > **Decision autonomy.** Routine judgment calls are decided for you; every merge comes back to you. **Tier A** is the closed Ask Set, always surfaced, defined in `plugin/governance/decision-autonomy.md` (Decision Tiers); who decides a reviewer's question is set by `plugin/governance/decision-autonomy.md` (Review Calls). Only an Ask Set question asks you, on every path. **Tier B** decisions are taken with one disposition: `did-now`, `deferred`, `recorded`, or `surfaced` (when the promotion gate trips). A run lists the decisions it took in its final message or report, and on its pull request when it opens or reuses one, so you can veto them before you merge. A read-only analysis opens no pull request, so its final message or report is its whole list. There is no post-merge decision report. Policy: `plugin/governance/decision-autonomy.md`.

- `:304-317` (S1 removes the exploratory row; S5 the rest): replace the `### Workflows` section with:

  > ### Workflows
  >
  > The generated workflow scripts live in `plugin/workflows/`. `hivemind:route-workflow` selects one of these:
  >
  > | Workflow | Purpose | Workflow script |
  > |---|---|---|
  > | `standard-delivery` | Plan, branch, build in waves, gate, review, open the PR, and watch it | `standard-delivery.js` |
  > | `analysis-only` | Analyze and report; no code changes | `analysis-only.js` |
  > | `pr-feedback-remediation` | Remediate feedback on an existing PR: run the review loop, or a one-shot fix pass by `github-reviewer`, after checking out the PR branch | `pr-feedback-remediation.js` |
  > | `hatchery-dispatch` | Brood plan, strain approval, spawn the brood, then monitor it | none: runs on Instinct |
  >
  > A workflow with a script runs it when the launch goes ahead. A refused or blocked launch runs on Instinct (see [Scripts and Instinct](#scripts-and-instinct)). The scripts are built from `plugin/workflow-src/` by `tools/build_workflows.mjs`.

- `:344` (S4): replace "skips the router, the run ledger, and the cerebrate" with "skips the router and the cerebrate".
- `:379` (S5): `  workflows/                # generated .js workflow scripts`
- `:418` (S4): replace "launches its workflow script, runs a `standard-delivery` request on Instinct, or runs the workflow state machine and run ledger." with "launches its workflow script or runs it on Instinct."
- `:453` (S1): replace "emits selected / ambiguous / exploratory / blocked" with "emits selected / ambiguous / blocked".
- `:454-456`, `:458` (S5) and `:459` (S4): delete the rows of `hivemind:init-run-ledger`, `hivemind:record-state-result`, `hivemind:next-wave`, `hivemind:mark-intent-fallback` and `hivemind:decision-report`.
- `:457` (S5): replace "for the overlord's `version_bump_decision` workflow state and" with "for the overlord's version bump decision on Instinct and".
- `:478` (S5): replace "the one home for both engines" with "the one home for every path".
- `:479` (S4): replace ", the decision journal, and the post-merge decision-report trigger" with ", and the decision journal".
- `:489-491` (S5): delete the `run-ledger-schema.md` and `docs/references/workflow-state-machine.md` rows, and replace the brood row with `| `docs/references/brood-manifest-model.md` | Maintainer spec for the brood scripts, not loaded at runtime: brood manifest shape, started-evidence and hatchery monitoring |`.
- `:500-511` (S5): delete the `### Workflow definitions` section.

**4. `docs/references/`** (S5)

- Delete `docs/references/workflow-state-machine.md`.
- Rename `docs/references/brood-ledger-model.md` to `docs/references/brood-manifest-model.md`, with title `# Brood Manifest Model`, and:
  - Replace the opening paragraph with: "Read this file to understand the brood manifest: the per-brood JSON `manifest_version: 4` shape (top-level `brood_id` and `created_at`, per-strain `run` block with `suggested_id` and `workflow_hint` only), the injected child-task metadata, and hatchery read-only monitoring with its status-derivation priority."
  - Replace `## Format split: manifest JSON, child ledgers JSON` with `## Format split: manifest JSON, child task YAML`, and its last paragraph with: "The manifest is the registry and coordination artifact. Child progress is read from external observables and the child's facts file, never from a child's other files."
  - In the manifest example, delete the `hatchery` block. Delete the `hatchery.run_id`, `hatchery.ledger` and `hatchery.workflow` bullets. Replace the paragraph after the bullets with: "No field points at a file the hatchery creates in a child's worktree. The child receives `run.suggested_id` as data in the injected `task.md` (below); it is the strain's lineage key."
  - Delete `## Ledger-path derivation (read side, ground-truth-anchored)`, but keep its two worktree paragraphs ("**Worktree PATH is the lookup key; new manifests carry no `branch`.**" and "**The PR probe and the `branch` column use the worktree's git-reported LIVE branch.**") under a new `## Worktree lookup (read side, ground-truth-anchored)`.
  - In `## Injected child-task metadata`, replace the paragraph's last two sentences after "On the script engine" with: "Its first planner delegation, on a workflow script or on Instinct, writes a gather-facts output file in its worktree."
  - In `## Hatchery monitoring (read-only)`, replace "It never mutates child ledgers" with "It never mutates a child's files", replace "the child's started-evidence (run ledger or gather-facts output file, informational)" with "the child's started-evidence (a gather-facts output file, informational)", and delete the paragraph that begins "Reading child-ledger workflow-state is **LIVE**". In the may-read list, delete the line `child run ledger (brood-status-project.sh — informational, bounded projection)`.
  - In `### Status-derivation priority`, replace tier 3 with `3. child started-evidence: a gather-facts output file (informational — never overrides tier 1 or 2 Status; MAY DEMOTE an alive child OUT of `running` to `starting`, but never promotes / never hides a dead session)`. Replace the sentence that begins "The child run ledger (tier 3) populates" with: "Tier 3 populates no display column."
  - In the started-evidence table header, replace `started-evidence (valid state.current, or facts file present)` with `started-evidence (facts file present)`.
  - Replace `## Reconciliation concept` with: "Before resuming work that touches a brood, the overlord reconciles state against external observables, the manifest's static fields and each child's facts file: manifest presence, tmux sessions alive or dead, worktrees and branches existing, and PRs existing."

**5. `docs/skill-authoring.md`** (S5)

- `:36`: delete the sentence on `hivemind_assert_ledger_contained` and its three callers.
- `:50-52`: delete the `hivemind:init-run-ledger`, `hivemind:record-state-result` and `hivemind:mark-intent-fallback` inputs-file bullets.

**6. `web/`** (the slice of the matching README item)

`web/` mirrors README. Each element below keeps its markup, with each backtick span as `<code>`.

- `web/index.html:76` (S4): "Routes each request to a workflow, then launches its workflow script or runs it on Instinct. Owns branches, checkpoint commits, ver…", the rest unchanged.
- `web/index.html:114` (S4), using the Record sentence: "Eight beats from your intent to a reviewed pull request, as a standard-delivery workflow script run. No path keeps a run ledger: a run that opens a branch and a pull request is recorded by them, and a run that opens none, such as a read-only analysis, keeps no record. When a launch is refused or blocked, or a started standard-delivery run fails, the request continues on Instinct, with no script."
- `web/index.html:119` (S4): "`hivemind:route-workflow` picks standard-delivery, analysis-only, pr-feedback-remediation or hatchery-dispatch. The first three launch as the `hivemind:analysis-only`, `hivemind:standard-delivery` and `hivemind:pr-feedback-remediation` workflow scripts when Claude Code's Workflow tool is available. Brood dispatch, a refused or blocked launch, and a started standard-delivery run that fails, run on Instinct, with no script."
- `web/index.html:121` (S4): replace "skips the router, the run ledger and the cerebrate" with "skips the router and the cerebrate".
- `web/benefits.html:80` (S4), using the Record sentence, then the List sentence: replace from "A `Workflow(hivemind:standard-delivery)` entry" to the end with: "A `Workflow(hivemind:<id>)` entry in `permissions.deny` sends that workflow to Instinct, a judgment-driven path with no script. No path keeps a run ledger: a run that opens a branch and a pull request is recorded by them, and a run that opens none, such as a read-only analysis, keeps no record. A run lists the decisions it took in its final message or report, and on its pull request when it opens or reuses one, so you can veto them before you merge. A read-only analysis opens no pull request, so its final message or report is its whole list. `plugin/workflows/` holds only the generated `.js` scripts."
- `web/benefits.html:170` (S5): replace "on every delivery path, the workflow scripts, Instinct and the state machine:" with "on every delivery path, the workflow scripts and Instinct:", and "A script run computes its waves in `plugin/workflow-src/lib/waves.js`; `hivemind:next-wave` reads the run ledger only on the state machine." with "A script run computes its waves in `plugin/workflow-src/lib/waves.js`."
- `web/benefits.html:173` (S5): delete the `hivemind:next-wave` tag.
- `web/functionality.html:117` (S5), `:121` (S4), `:155` (S4): the README `:22`, `:23` and `.hivemind/` texts above, with `:155` reading "It holds the branch facts files `hivemind:gather-facts` writes under `.hivemind/facts/`, brood manifests, the local reviewer's finding ledger, handoffs and the plans they point at, and short-lived inputs files that skills pass to their engine scripts. Run ledgers from earlier versions under `.hivemind/runs/` are neither read nor deleted."
- `web/functionality.html:214` (S4), `:270` (S1): the README `:418` and `:453` texts.
- `web/functionality.html` skills table (S5, and S4 for the report row): delete the `<tr>` rows of `hivemind:init-run-ledger` (`:273`), `hivemind:record-state-result` (`:277`), `hivemind:next-wave` (`:281`), `hivemind:mark-intent-fallback` (`:285`) and `hivemind:decision-report` (`:333`).
- `web/functionality.html:404` (S4), using the Record sentence, then the List sentence: "`hivemind:route-workflow` selects the workflow first, for every request that is not a Reflex. When Claude Code's Workflow tool is available, `analysis-only`, `standard-delivery` and `pr-feedback-remediation` launch as workflow scripts. In manual mode the Workflow tool shows an approval prompt; in auto mode the launch goes ahead with no prompt. A No at the prompt interrupts the turn, and has no fallback. A refused or blocked launch, and a started `standard-delivery` run that fails, continue on *Instinct*: the overlord's judgment-driven path, with no script, that keeps the plan, the branch and every gate. No path keeps a run ledger: a run that opens a branch and a pull request is recorded by them, and a run that opens none, such as a read-only analysis, keeps no record. A run lists the decisions it took in its final message or report, and on its pull request when it opens or reuses one, so you can veto them before you merge. A read-only analysis opens no pull request, so its final message or report is its whole list. A `standard-delivery` script run, from request to PR:"
- `web/functionality.html:440-441` (S4): heading `Instinct fallback` kept; text: "When any launch is refused or blocked (denied, not found, or workflows turned off), or a started `standard-delivery` run fails, the overlord says so in one line and continues on Instinct without asking. Instinct never relaunches a workflow. A run you stopped does not fall back. The final report names the switch and where the run stopped."
- `web/functionality.html:443-446` (S4): delete the `State machine` beat, the `<li>` holding the `:444` heading.
- `web/functionality.html:449-463` (S4): in the diagram, delete the `(default watch, state machine)` qualifier and the `State machine  (resumed runs, other workflows)` line, and drop the state machine from the `aria-label`.
- `web/functionality.html:468` (S4): "Every non-Reflex request is routed to one workflow. `standard-delivery`, `analysis-only` and `pr-feedback-remediation` have workflow scripts, and each runs its script when the launch goes ahead. A refused or blocked launch, and a started `standard-delivery` run that fails, continue on Instinct. Brood dispatch always runs on Instinct. A delivery request that names neither the script nor Instinct gets a question with a recommendation, and a brood child takes the script. A No at the approval prompt still has no fallback. `plugin/workflows/` holds the generated `.js` scripts."
- `web/functionality.html:491-497` (S1): delete the `exploratory-intent-session` row; the `hatchery-dispatch` row's text becomes "Brood work, on Instinct: plan the strains, get your approval, spawn the brood, and monitor it."
- `web/functionality.html:506` (S5), `:510` (S4), `:564` (S4): the README `:298`, `:300` and `:344` texts.
- `web/functionality.html:687-688` (S4): delete the `HIVEMIND_ENABLE_DECISION_REPORT` row.
- `web/tests/dom-contract.test.ts:151-155` (S5): the workflow list reads the router catalog, since `plugin/workflows/` will hold no `.json`:

  ```ts
  function listWorkflowNames(): string[] {
    const catalog = readFileSync(join(REPO_ROOT, 'plugin', 'skills', 'route-workflow', 'SKILL.md'), 'utf8');
    return [...catalog.matchAll(/^- `([a-z-]+)`: /gm)].map((match) => match[1]);
  }
  ```

**7. Lair docs and ADR-0045** (each through its initiative's re-review, D19)

- `docs/adr/0045-lair-software-factory.md`, after decision 6: add "Note 2026-11-22 (ADR-0048 decision 8): `## Resume On Start` no longer exists, so a strain has no Resume On Start question by construction. A refused or blocked launch at the unattended level ends or parks the run instead of taking the one Instinct fallback."
- `docs/initiatives/autonomous-ready-issue-loop/solution-design.md:10`: replace "the pull request state and the run ledger state" with "and the pull request state".
- `:14`: replace "and the `## Resume On Start` path" with "and the one refused-launch fallback in `## Engine`".
- `:33`: replace "the overlord's Instinct fallback, Resume On Start question and post-PR watch are replaced as ADR-0045 decision 6 states" with "the overlord's Instinct fallback and post-PR watch are replaced as ADR-0045 decision 6 states; the fallback's level clause is the one place #607 adds the unattended sentence (ADR-0048)".
- `docs/initiatives/autonomous-ready-issue-loop/strain-launch-design.md:62`: delete "`## Resume On Start` offers resume or start fresh;".
- `:192`: replace the **user_gate.** row's first two sentences with "**Refused launch.** A refused or blocked engine launch at the unattended level ends the strain `failed` with no Instinct fallback (the level clause of `## Engine`, ADR-0048)." and its file cell with `plugin/agents/overlord.md` (`## Engine`, `## Instinct`, `### Stop Conditions`).
- `:194`: delete "runs no Resume On Start question," and `## Resume On Start` from its file cell.
- `:271`: delete "; `HIVEMIND_ENABLE_DECISION_REPORT` = `""`".
- `:609`: delete "no Resume On Start question," and "the `user_gate` edits,".

**8. Idea to Ready design and ADR-0046** (through that initiative's re-review, D19)

- `docs/initiatives/idea-to-ready/solution-design.md:26`: replace "After a refused launch, or after a started run that fails or ends blocked," with "After a refused or blocked launch of any workflow (ADR-0048), or after a started run that fails or ends blocked,".
- `:440`: replace "runs on Instinct under ADR-0039 decision 3" with "runs on Instinct under ADR-0048".
- `docs/adr/0046-idea-to-ready-process.md`, after decision 10: add "Note 2026-11-22 (ADR-0048 decision 8): 'a refused or blocked launch starts no run and still runs on Instinct' now rests on ADR-0048's one fallback, which covers every workflow."

**9. `docs/adr/0018-declarative-workflow-state-machine.md`** (S5)

- `:3`: the Status line becomes `**Status:** superseded by ADR-0048 — 2026-11-22`.

## Verification strategy

Each slice runs this repository's own gate, `bash tools/validate.sh --changed`; the plugin requires none of it in a consumer project. This section states what each slice must prove and names no check file, name list, scan path or test mechanism: each slice's own design and review builds its checks. Each slice's review checks the user's confirmation of each item D12 covers that the slice makes (D12). Per slice:

- **S1 Router without the exploratory path:** the router catalog holds exactly four entries and the outcomes `selected`, `ambiguous` and `blocked`, states the no-fit rule and holds no `exploratory` text. `plugin/agents/overlord.md` names no `exploratory` outcome.
- **S2 Brood dispatch on Instinct:**
  - `## Brood Execution` states dispatch on Instinct, the approval before `hivemind:spawn-brood` and a declined approval spawning nothing, with no `user_gate` or `spawn_brood` state text. The brood strain approval stays an Ask Set item, and the synapse runner gate still holds five scripts.
  - A manifest has no `hatchery` block, a caller `hatchery` input is ignored, and a manifest with the block still reads.
  - Turn-start verification passes on a facts file and fails on a child run ledger alone.
- **S3 Brood dashboard without child ledgers:**
  - The collect output is `brood-status-collect/2` with no `workflow_state` or `run_status`.
  - An alive child with no facts file is `starting`; with one, `running`; a dead child derives from its observables; a strain with no `run.suggested_id` is not demoted.
  - A child run ledger in a worktree changes nothing in the output.
- **S4 Overlord on one engine:**
  - `plugin/agents/overlord.md` holds none of the sections and skills D10 removes, and the two re-homed rules (D11) are in `## Safety Rails`.
  - The one fallback paragraph has its level clause first and names all three workflows. The Instinct analysis and post-PR remediation paths and the `Decisions:` final report line are present.
  - `### Stop Conditions` names no journal destination of its own and cites `plugin/governance/decision-autonomy.md` (Decision Journal), and that governance text says a run with no pull request lists its decisions in its final message or report and keeps no decision journal.
  - Reviewer outcomes: every `exit_reason` `hivemind:github-review-loop` can return, and every `exit_reason` of `hivemind:github-reviewer`'s fix pass that Instinct's post-PR remediation runs, is either routed by the overlord or ends the watch or pass with its report. The coverage `tools/validate_workflows.sh` checked moves to a test the slice names in its own design (D18).
  - The default post-PR watch reads the in-session signal. `### Proactive Zoom-Out Marker` and its overlord citer agree. The Ask Set and the autonomy governance lose the resume bullet and the report trigger, and the decision-report toggle rule goes with its pin (D12 covers it).
  - No citation of a deleted heading remains, and the overlord's and `plugin/governance/decision-autonomy.md`'s prose budgets are lowered to their measured size.
- **S5 Engine removal:**
  - No live reference to an item D10 removes remains in what the slice changes, apart from text a later re-review owns (D19) and text that pins an absence.
  - `plugin/workflows/` holds only generated scripts, and the rebuilt scripts match their sources.
  - `waves.js` matches `tests/next-wave/expected/` on every fixture, override, mutation and seeded-corpus case of today. The expectation files come from `next-wave.sh` in a commit before its deletion, and the slice's review checks that that commit's test run passed.
  - Every `resolved_at` site of the autonomy table starts with a workflow id that has a script, and the four rows are gone.
  - The validation suite passes with no map entry, suite or budget entry for a deleted path, and the overlord budget is lowered again if the slice shrinks the file further.

## Seam order

Slices start in this order; a slice waits on its blockers. No slice is cut and no issue is created by this design. Slicing waits for `docs/prds/retire-json-state-machine.md` and a passing review record.

| Slice | Blocked by | Headings it implements |
|---|---|---|
| S1 Router without the exploratory path | none | Workflow router; Router output contract; Request lifecycle; Failure modes; D5: Exploratory intent session removed; D12: Engine test deletion needs the user's confirmation |
| S2 Brood dispatch on Instinct | none | Brood dispatch on Instinct; spawn-brood; spawn-brood inputs and manifest; Brood dispatch lifecycle; Lair seams; Trust boundaries; Failure modes; D4: Brood dispatch runs on Instinct; D9: ADR-0005 is unchanged; D15: The manifest keeps version 4 without the hatchery block; D12: Engine test deletion needs the user's confirmation |
| S3 Brood dashboard without child ledgers | none | brood-status; brood-status collect output; State and ownership; Failure modes; D8: The brood dashboard reads no child ledger; D12: Engine test deletion needs the user's confirmation |
| S4 Overlord on one engine | S1, S2 | Overlord engine section; Overlord safety rails; Instinct paths; Decision journal; Launch and fallback contract; Level check seam; Decision journal destinations; Lair seams; Trust boundaries; State and ownership; Run ledger fields; Fallback lifecycle; Resume lifecycle; Upgrade lifecycle; Failure modes; D2: One fallback for every refused or blocked launch; D3: Instinct gains read-only analysis and post-PR remediation; D6: Resume on start has one path; D7: The pull request is the decision journal; D11: Two rules re-homed in the safety rails; D16: The Reflex heading is kept; D17: The proactive zoom-out marker rides the cluster payload; D18: Exit-reason routing coverage moves to a workflow-scripts test; D12: Engine test deletion needs the user's confirmation |
| S5 Engine removal | S1, S2, S3, S4 | Removed components; Autonomy table; Waves rule home; Validation tooling; Waves expectation files; State and ownership; Run ledger fields; Trust boundaries; Failure modes; D1: Retire the JSON state machine; D10: The removal list; D12: Engine test deletion needs the user's confirmation; D13: waves.js keeps its parity fixtures as frozen expectations; D14: The autonomy table keeps only script sites |

S4 waits on S1 and S2 so that, when it deletes `## Workflow State Execution` and `## Resume On Start`, no path still enters the state machine. Engine removal is last: it deletes what no remaining path reaches. The shared-document items of Changes to shared documents land in the slice each names. The Lair, ADR-0045, Idea to Ready and ADR-0046 items land in their own initiatives' re-reviews (D19), which this design neither schedules nor blocks on.

## Open questions

None

## Amendments

None yet.
