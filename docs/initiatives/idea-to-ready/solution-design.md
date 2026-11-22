# Solution design: Idea to Ready

This is the HOW for [docs/prds/idea-to-ready.md](../../prds/idea-to-ready.md), as merged in #626. It does not reopen the PRD. Epic #614 tracks the slices #615 to #624; #627 is this second by-hand pilot. ADRs: [ADR-0046](../../adr/0046-idea-to-ready-process.md) (the idea-to-ready process) and [ADR-0047](../../adr/0047-abathur-council.md) (the Abathur council). The design review record is [review-record.md](review-record.md) in this folder.

## Context and code truth

Checked against main at commit `49787cc9`; line numbers are at that commit. Each fact below names what exists today; the components say what changes.

- **Pipeline skills exist.** `hivemind:plan-interrogation`, `hivemind:plan-to-prd`, `hivemind:prd-to-issues` and `hivemind:create-handoff` are all implemented. [CONTEXT.md](../../../CONTEXT.md) still calls the last three "planned skill — not yet implemented"; this pull request's glossary edits fix that.
- **plan-interrogation** holds `Read`, `Write` and `Edit`, and is the named writer of `CONTEXT.md` terms and ADRs. It offers an ADR only when a decision is hard to reverse, surprising without context and a real trade-off. Those three are the ADR conditions this design cites.
- **plan-to-prd** writes a nine-section, WHAT-only PRD to `docs/prds/<slug>.md`. One slug names the plan, the handoff, the PRD and the epic.
- **prd-to-issues** is a leaf skill that names no sibling ([ADR-0013](../../adr/0013-decoupled-leaf-pipeline-skills.md)). Its issue body has exactly four sections: Initiative, What to build, Acceptance Criteria, Dependencies. Blockers are only `#123` refs in the Dependencies section; it writes no native blocked-by edge. `subissue-ops.sh ensure-parent --existing-number <n>` already resolves a known issue as the epic, and `find-by-title` makes a rerun create no duplicates. Its hard rules include "No file paths or code snippets".
- **create-handoff** writes `.hivemind/handoffs/<slug>.md`, which is gitignored. It is session state on one machine and can never be stage evidence.
- **triage-backlog** is user-only (`disable-model-invocation: true`), so no model, the guide included, can start it. It rates seven families (readiness, type, effort, moscow, priority, risk, difficulty). `readiness:ready` is a rubric judgment ("plan clear, no open questions") with no check behind it, and `readiness:blocked` means "would be ready but a dependency blocks it". `triage-ops.sh` has five subcommands: `ensure-labels`, `list-issues`, `apply-labels`, `deps-read`, `deps-add`. `list-issues` returns number, title, labels, body and node id, with no parent or sub-issue fields. `deps-add` writes native blocked-by edges behind the confirm gate. `triage-ops.sh` fails closed when a read's `pageInfo.hasNextPage` is true.
- **Triage transport.** triage-backlog passes `apply-labels --targets` as a JSON argument (`plugin/skills/triage-backlog/SKILL.md:231`). Its `allowed-tools` hold no `Edit(.hivemind/` entry.
- **decision-autonomy.md, Review Calls** says who decides a reviewer's question. A call is taken when the recommended option is reversible and not architectural (Promotion Gate clauses 1 and 2). It is asked when irreversible, architectural, at strength none, or when the table cell is `surface`. There is no rule for design decisions.
- **Prose budgets.** Measured as CHECK 18 measures (bytes with CR stripped): `plugin/governance/decision-autonomy.md` is 12165 bytes of a 12173 budget (8 bytes free); `plugin/governance/remediation-doctrine.md` is 19901 of 19906 (5 bytes free); `plugin/governance/security-policy.md` is 24143 of 24145 (2 bytes free); `plugin/agents/synapse.md` is 1716 of 1727 (11 bytes free). `plugin/agents/overlord.md` (39038), `plugin/skills/triage-backlog/SKILL.md` (11952), `plugin/skills/prd-to-issues/SKILL.md` (14566) and `plugin/skills/adaptation-cycle/SKILL.md` (5421) are each exactly at their budget. The budgets live in `tests/policy/prose-byte-budget.json`.
- **Built-script budgets.** Measured at the branch head, whose `plugin/` equals `49787cc9`: literal characters with `countProseCharacters`, exported by `tools/build_workflows.mjs`, against each script's entry in `tests/policy/prose-byte-budget.json`, and length as the string length of the file read as UTF-8 against `MAX_BUILT_SCRIPT_LENGTH`, 191000. `tools/build_workflows.mjs` enforces both.
  - `plugin/workflows/standard-delivery.js`: 41976 characters of string and template literals against its 42100 budget (124 free); 190836 characters long (164 free).
  - `plugin/workflows/analysis-only.js`: 15552 against its 16050 budget (498 free); 64417 characters long (126583 free).
  - `plugin/workflows/pr-feedback-remediation.js`: 38053 against its 38200 budget (147 free); 176060 characters long (14940 free).
- **decision-autonomy-table.json** is version 1, levels `high`, `balanced`, `low` (default `high`), 17 row kinds with cells `auto` or `surface`, and 6 hard stops, `injection_suspect` among them. It has no consult setting.
- **Planner question cells.** The `planner_question` cells are `auto` at `high` and `surface` at `balanced` and `low` (`plugin/references/decision-autonomy-table.json:16`). `decide()` asks `table_surface` before any gate or strength check (`plugin/workflow-src/lib/decide.js:110`).
- **The table projection.** `projectAutonomyTable` in `tools/build_workflows.mjs` keeps only `levels`, `default_level`, `hard_stops` and each row's `kind`, `high`, `balanced` and `low`. `tests/workflow-scripts/build.test.mjs` pins those keys, and `tests/workflow-scripts/data.test.mjs` requires an `auto` or `surface` cell per row per level.
- **decide.js** returns only `ask` or `take`. Its check order is hard_stop, malformed_brief, recommendation_not_an_option, unknown_kind, table_surface, bad_cell, gate_irreversible, gate_architectural, gate_safety, no_recommendation. A weak recommendation is taken ([ADR-0036](../../adr/0036-analysis-only-first-workflow-on-script-engine.md) decision 6). There is no park.
- **Levels.** `resolveLevel` maps an unknown level to `low`, and each workflow resolves the table's default level. The `unattended` level and the park arrive with Lair unattended mode (#607, ADR-0045 decision 6).
- **The closed Ask Set.** `askReasons()` and `listReasons()` are closed lists ([ADR-0037](../../adr/0037-standard-delivery-on-script-engine.md), amendment for issue 549). `pauseDelivery` in `plugin/workflow-src/lib/record.js` refuses an ask whose reason is outside `askReasons()`, pinned by `tests/workflow-scripts/ask-set.test.mjs` and `tests/policy/safety-ask-set.json`.
- **decide() call sites.** `decide()` is called directly in three places: `resolveDecision` in `plugin/workflow-src/lib/plan.js`, `hasDefectQuestion` in `plugin/workflow-src/lib/retry.js` (a planner-question check) and `plugin/workflow-src/analysis-only/main.js`. `plugin/workflow-src/lib/tails.js`, `plugin/workflow-src/standard-delivery/review.js` and pr-feedback-remediation reach it through `resolveDecision`.
- **The planning pass.** `runPlanningPass` (`plugin/workflow-src/lib/plan.js:533`) is async, shared by `plugin/workflow-src/standard-delivery/main.js:490` and `plugin/workflow-src/pr-feedback-remediation/escalation.js:108`. It resolves planner questions through `resolvePlanAsks` (`plan.js:450`), which calls the synchronous `resolveDecision` (`plan.js:393`).
- **Code-built asks.** `buildUndecidedAsk` (`plugin/workflow-src/lib/tails.js:109`) throws when `decide()` takes its brief. The validation fix limit (`plugin/workflow-src/lib/gates.js`), step stops, the version question and the review safety hold use it with code-built briefs.
- **Review calls.** A review call resolves on a copy whose problem, option summaries and why read "Not shown." (`removeReviewerText`, `plugin/workflow-src/standard-delivery/review.js`). A taken call replies with the reviewer's own option (`takeReviewCall`).
- **Injection-suspect is terminal.** `runPassScan` (`plugin/workflow-src/lib/runner.js:302`) ends the run with a terminal stop on an injection-suspect scan (SD-06). ADR-0037 keeps injection-suspect terminal.
- **Strength and gate.** The brief schema says a strength `none` question is asked either way, and the local reviewer gives `none` when only the user holds the fact. `plugin/agents/cerebrate.md` (Questions and Replies) writes the plan assuming every raised recommendation. `decide()` checks the gate before `no_recommendation`, so a weak take or a `no_recommendation` ask has a clean gate and an `auto` cell.
- **Settled answers.** `listAnswerEntries` (`plan.js:516`) puts one settled entry per launch decision, built by `buildAnswerEntry` (`plugin/workflow-src/lib/brief.js`), ahead of `run.answerLog`. The scope, plan, revise and review prompts carry them in an answers block whose data line calls settled only what an entry's settled labels name (SD-60, SD-67, SD-80). A decision never enters `run.answerLog`, its rounds or `resume_args`, whose answers are the replies of `run.answerLog` (`plugin/workflow-src/lib/record.js`).
- **Question keys.** `questionKey` (`plugin/workflow-src/lib/plan.js:367`) keys an ask by kind, scope and the question as rendered, which shows the recommendation's why. `resolveDecision` checks `run.answeredKeys` only for an ask, never a take (`plan.js:393-411`).
- **Replans.** A pass that returns `{replan: {reason}}`, the shape `buildReplyReplan` (`plugin/workflow-src/lib/tails.js:99`) builds for a reply, starts the next pass from the facts step (`runDelivery`, `plugin/workflow-src/standard-delivery/main.js:505`). `keepReplanReview` keeps a review the replan carries. A reply replan is outside `maxReplans()`. ADR-0037 invariant 3 starts every planning pass from fresh facts.
- **Defect questions.** `pauseDelivery` refuses an ask whose reason is outside `askReasons()`. `hasDefectQuestion` (`plugin/workflow-src/lib/retry.js`) sends a planner question back to the planner when `decide()` gives it such a reason, such as `malformed_brief` for a beyond-request option that is not strong with trivial or small effort (SD-81).
- **What a built script carries.** A built script carries only the functions and data constants its code reads, each data constant whole as projected. `AUTONOMY_TABLE` and `BRIEF_SCHEMA` are in all three built scripts, and so is `runnerValuePatterns` (`plugin/workflow-src/lib/facts.js`). The prose measure counts every string literal, data constants included.
- **Schema projection.** `projectSchema` (`tools/build_workflows.mjs:245`) drops every title and description from `BRIEF_SCHEMA` in the built scripts.
- **Parks.** ADR-0045 decision 7 parks a fact only the user holds as its own park.
- **Shown decisions.** `isShownDecision` in `plugin/workflow-src/lib/record.js` shows the routine kinds `plan_acceptance`, `remediation_plan_acceptance` and `gate_rerun` only when they are listed.
- **decision-brief-schema.json** carries `recommendation.strength` of `strong`, `weak` or `none`, and has no dissent or member provenance fields. Its `gate` is the producer's read of the recommended option only. Options carry `reversible`, `beyond_request` and an optional `destructive` list, but no gate of their own.
- **standard-delivery** resolves every question through `decide()` and pauses through `pauseDelivery`; it has no cumulative pause cap. It stops on a dirty tree (`dirty_paths`, `plugin/workflow-src/lib/facts.js`). plan-interrogation and plan-to-prd hold no git grant and leave the files they write uncommitted.
- **`resume_args`** is `{answers, build}` alone (`plugin/workflow-src/lib/args.js`).
- **Draft and closing lines.** The standard-delivery `draft` launch arg is absent, true or false, and absent means false (SD-48, `plugin/workflow-src/standard-delivery/contract.js:54`). The pull request body opens with one `Closes #N` line per `plan.closes` number (`renderClosingLines`, `plugin/workflow-src/lib/pr.js:198`), and each number must be a launch reference (`describeClosesProblem`, `plugin/workflow-src/lib/title.js:173`). `open-plan-pr.sh` leaves a reused pull request's title, body and draft state unchanged (`plugin/skills/open-plan-pr/scripts/open-plan-pr.sh:145`).
- **Docs validation mapping.** `tools/validate.sh` maps `docs/adr/**` to `policy_check` only, and every other `docs/**` path except `docs/skill-authoring.md` to no suite (`tools/validate.sh:429`).
- **Fix and post-PR commits.** `runValidateGate` (`plugin/workflow-src/lib/gates.js:477`) sends a failed validation to a `validation_remediation` decision (`gates.js:497`). `runFixRound` (`gates.js:420`) then commits the files the fix drone reports through `runCommitStep` (`plugin/workflow-src/lib/commit.js:180`). The validate drone's failures are its own text, under the schema description "Each failing command with its failure output." (`gates.js:217`). pr-feedback-remediation runs the same gate loop (PFR-23) and commits each wave through `runPlanWaves` (`plugin/workflow-src/lib/workers.js:234`, PFR-22), as standard-delivery does. `molt.sh` refuses a dirty path outside its file list. The github-reviewer validates per the Validation Procedure, returns blocked on a failure, and commits its own simple fixes with git (`plugin/agents/github-reviewer.md:76`). No code refuses a review record path today.
- **The synapse agent** is the haiku runner that relays one committed script. The name Synapse is taken. The earlier council epic #440 (closed) used it for a bioform.
- **The Synapse Runner Gate** (`plugin/hooks/synapse-gate.sh`; `plugin/governance/security-policy.md`, Synapse Runner Gate) admits five scripts: molt, gather-facts, create-working-branch, bump-type and open-plan-pr. `run-review.sh` is not one. The gate admits a script only at `skills/<name>/scripts/<name>.sh`. Synapse's Write is limited to `.hivemind/molt-inputs-<token>.json` and `.hivemind/pr-inputs-<token>.json`. The Input contract of `plugin/agents/synapse.md` carries `inputs_file` only for a commit or pull request. `runnerValuePatterns` allows `--inputs` only as a molt or pr inputs file. `hivemind_remove_inputs_file` in `plugin/skills/_shared/containment.sh` accepts kinds `molt` and `pr` only. `plugin/skills/_shared/settings-merge.sh` and `.claude/settings.json` seed `Edit(.hivemind/molt-inputs-*.json)` and `Edit(.hivemind/pr-inputs-*.json)`, held equal by `tests/policy/safety-navigator-transport-rules.json`.
- **The tool-neutral review runner** `plugin/skills/adaptation-cycle/scripts/run-review.sh` reads `HIVEMIND_LOCAL_REVIEWER` (the `codex-plugin` preset or a JSON argv list run with no shell). Its prompt is fixed: an adversarial review of a branch diff against `--base`, checked against the findings schema. It cannot carry a decision brief today. The `codex-plugin` preset runs a fixed companion command with no prompt path. Per [ADR-0042](../../adr/0042-tool-neutral-local-review.md) decision 7, Hivemind never names a model.
- **Test homes.** Runner cases live in `tools/test_run_review.sh`; `tests/run-review/` holds only a README. Subissue-ops cases are in `tools/test_subissue_ops.sh` with fixtures in `tests/prd-to-issues/`. Triage-ops cases are in `tools/test_triage_ops.sh` with `tests/triage-backlog/`. Gate cases are in `tools/test_synapse_gate.sh`.
- **Runner test routing.** `tools/validate.sh` routes `test_run_review` by exact paths (`tools/validate.sh:972`). Any other `plugin/skills/_shared/*.sh` routes to `test_shared_libs` (`tools/validate.sh:592`), never to `test_run_review`.
- **Navigator checks.** CHECK 14 and CHECK 16 (`tools/policy_check.sh:2283`, `tools/policy_check.sh:3368`) treat a skill whose `allowed-tools` hold an entry starting `- Edit(.hivemind/` as a discovered navigator. One of its scripts must source `containment.sh` in the direct form. `docs/skill-authoring.md` (Covered Navigators) must list it with its Edit glob, and a skill may carry only its own listed glob.
- **cerebrate** is read-only by its `tools:` list (Read, Glob, Grep, LSP, web and claude-mem search). A delegation line `Memory context:` stops its memory search.
- **The overlord's** Agent allowlist in `plugin/agents/overlord.md` holds general-purpose, hivemind:cerebrate, hivemind:drone, hivemind:changeling, hivemind:local-reviewer and hivemind:github-reviewer. Its Write grant covers only fixed-prefix inputs files under `.hivemind/`.
- **ADR-0045 decision 12** keeps any pull request touching a file in its protected-path list out of the auto tier.
- **ADR-0045 decision 10** sets Lair admission: latest ready label from a user with write permission, title and body unedited since, no open blocked-by dependency. This design cites it only as "ADR-0045 decision 10, as amended by #625": #625 adds the epic exclusion and the readiness check at claim time. This design never stamps ADR-0045.
- **Ready Issue** in `CONTEXT.md` requires no open blocked-by dependency. That rule stays: a slice may carry `readiness:ready` with open blockers, but it is a Ready Issue, and claimable, only once they close.
- **No folder** `docs/initiatives/` exists on main before this pull request.

## Components

### Guide skill

A user-only conductor skill (`disable-model-invocation: true`) that runs in the main session. Given nothing, it lists in-flight initiatives with their derived stage. Given an idea, it starts one. Given an initiative, it reports the stage, the evidence found and the next action, then starts that stage without asking to continue. It is written as stage must-haves with judgment, not a numbered state machine. It invokes the leaf skills by intent, and they stay uncoupled. It never applies `readiness:ready`: at the triage stage it tells the maintainer to run `/hivemind:triage-backlog`, which is user-only.

The guide owns the docs branch (#622):

- Before stage 2 writes any tracked file, it creates `docs/<slug>` from the fetched trunk.
- It commits the stage-2 and stage-3 outputs on that branch through `hivemind:molt` with exact paths: the glossary and ADR edits from `hivemind:plan-interrogation` and the PRD from `hivemind:plan-to-prd`. The tree is then clean before stage 4's standard-delivery run, whose `dirty_paths` stop would otherwise refuse it.
- It launches every standard-delivery run on the docs branch with `draft` true and no launch reference the run could close, so the docs pull request opens as a draft with no Closes line. Stage 4's first run opens it, and later runs reuse it.
- It runs the record verify at the pull request head before `gh pr ready`. A later push to a stamped path returns the pull request to draft.

Docs writing happens in a standard-delivery run on the docs branch, whose steps give a drone exact file scope. The design review runs from the main session between those runs. A standalone idea ends with an issue carrying the spec block, per Standalone spec block format, ready for triage.

### Readiness check

One deterministic shell library, `plugin/skills/_shared/readiness-check.sh`, sourced by each caller's own script entry: a `readiness` subcommand of `triage-ops.sh`, the guide's script and the Lair controller. It reads issues through `gh`. Each caller fetches and passes the remote trunk commit id, never a branch name or local ref. The library rejects a value not matching `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$` before any git call. At that commit it tests existence with `git cat-file -e <commit>:<path>`, reads contents with `git show` and reads blob ids with `git rev-parse`. The Lair passes the commit it spawns the strain from. It checks structure, existence, versions and labels, never quality. It writes nothing.

### Track fact

The track is read, never judged. An issue with a native parent is an initiative slice; any other issue is standalone. The parent must carry `type:epic`, else the slice fails `parent_not_epic`. A standalone issue whose `type:` label is not `bug`, `chore`, `documentation`, `refactor` or `enhancement`, or whose `effort:` label is `l` or `xl`, fails with a promote reason. The type and effort labels are human-confirmed, because triage applies them only after its confirm gate.

### Initiative folder

`docs/initiatives/<slug>/` holds `solution-design.md` and `review-record.md`, with the same slug as `docs/prds/<slug>.md`. The PRD stays in `docs/prds/`. ADRs stay global and numbered in `docs/adr/`.

### Solution design skill

A leaf skill that turns a merged-or-branch PRD into `docs/initiatives/<slug>/solution-design.md` with every section of the solution design template. It applies the design-decision rule and lists each decision with its ADR or the ADR condition it fails. It names no sibling skill. The file itself is written by a drone with exact file scope.

### Design review

A main-session skill that runs fresh read-only cerebrate analysis passes with `Memory context: none`. Round 1 is angles A and B in parallel; a confirming round follows. It records every finding with exactly one disposition. Only its record step, a standard-delivery wave, writes or re-stamps a record, and it rewrites the record after every round. Every commit except a standard-delivery wave refuses a record in code (Review record body). A review fix that stales a passing record fails verify, and goes through the confirming pass before the record step re-stamps, per Re-review and re-stamp. It exits per the design review rounds lifecycle.

### Slice design section

`hivemind:prd-to-issues` adds a fifth body section, `## Design`, to each slice, and reuses the initiative's seed issue as the epic through `ensure-parent --existing-number`. A rerun creates no duplicates, through the existing `find-by-title` preflight.

### Triage readiness gate

Triage runs the readiness check on every issue it would propose as `readiness:ready`. The `readiness` subcommand of `triage-ops.sh` takes an overlay of the labels and blocked-by edges the pending apply would write, as a `--overlay` JSON argument, the transport `apply-labels --targets` uses: family and value pairs from the seven closed families and issue numbers, so it adds no inputs file and no navigator entry. It checks as if they were present. A failing issue never enters the apply set as ready, and its reason codes show in the Notes column. A slice that passes is proposed ready even with open blocked-by links. `readiness:blocked` is kept only for a block with no issue link.

At apply, triage first writes the ratings and, through `deps-add`, the native blocked-by edge for each `#123` ref in a slice's Dependencies section. It then re-runs the check on the live state and applies `readiness:ready` only to issues that still pass. An issue that now fails is dropped from the ready set and named with its reasons.

### Stage derivation and handoff check

A pure function from GitHub and git to a stage and next action, run by the guide's script. Its evidence: the seed issue or epic, the docs branch and its pull request, then trunk, the review record, sub-issues, labels and readiness results. It reads the design's `**Status:** delivered` before record staleness.

- The seed is the one open issue carrying the seed issue marker whose author has write permission.
- Only same-repository pull request heads named `docs/<slug>` or `docs/<slug>-<suffix>` count.
- Fork pull requests, and issues or pull requests by users without write permission, are ignored and named in the report.

Handoff mode passes only when every condition of the PRD's handoff check holds, and reports each slice as claimable now or blocked, with the reason. Per slice it verifies that the latest `readiness:ready` labeled event comes from a user with write permission and that the title and body are unedited since. That is the test of ADR-0045 decision 10, as amended by #625.

### Lair admission

At claim time the Lair controller (#608) runs the readiness check against the trunk commit it will spawn from. It never claims an epic or a failing issue. A failing issue stays unclaimed, with no new label, and is named in the tick's queue report with its reason codes. The queue report shows reason codes encoded as untrusted text. This is ADR-0045 decision 10, as amended by #625; slice #623 implements it.

#623, with the #625 amendment, adds `docs/prds/`, `docs/initiatives/` and `docs/adr/` to the Lair's protected-path list (ADR-0045 decision 12). So a pull request touching them never takes the auto tier.

### Abathur council

Two read-only agents: `abathur` and the council member `overseer` (#618). The caller launches two to four members in all: Overseer members, each with an angle and a model, plus one runner member only when `HIVEMIND_LOCAL_REVIEWER` is a JSON argv list. So a council with a runner member has at most three Overseers. Then it launches Abathur. Each member returns one opinion. Abathur weighs the opinions and returns only an option id among the input's, a strength and a why. The caller composes the council's brief, per Council brief contract. Abathur never picks the members it judges. In standard-delivery, opinions and Abathur's output are injection-scanned per Consult step. In the design stages the conductor classifies each opinion before launching Abathur, and Abathur's output before writing the design, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Injection-Suspect Classification), and asks a suspect one.

In the main session the conductor launches them. #622 adds `hivemind:abathur` and `hivemind:overseer` to the overlord's Agent allowlist; its Write grant is unchanged (D23). For a runner member the main-session guide invokes `hivemind:council-member`, whose own skill grant holds the council script's Bash grant and the `Edit(.hivemind/council-inputs-*.json)` inputs-file entry (#618). The guide's grant holds neither, so the guide is not an inputs-file navigator (#622). In standard-delivery the workflow script launches the Claude members, and synapse runs the runner member's committed script (D22). Every member and Abathur delegation carries `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Delegation Data-Boundary Constraint).

### Mid-delivery consult

Inside standard-delivery the council weighs only planner questions, in `runPlanningPass` before `resolvePlanAsks`. So `decide()`, `resolveDecision` and `resolvePlanAsks` stay synchronous and unchanged. `decide()` gains no consult action and no consult-count input. `askReasons()` and `listReasons()` gain no council reason.

- A question its planner marks `needs_user_fact` true, or leaves unmarked, is never convened.
- A strong council result on the planner's own option is taken, journaled and shown in the pull request decisions.
- A strong result on another option is taken only when the producer's gate read of that option is clean. It is journaled and shown, and the run plans again with it as a settled answer, so the plan that runs is built on it.
- A split comes back with strength `none`. It asks `no_recommendation` with the dissent in an interactive run and parks in an unattended run (#607).
- Never consulted: code-built briefs, every `buildUndecidedAsk` site (the validation fix limit among them), `review_question` and `high_severity_rejection` calls (Review Calls: no second agent judges), hard stops, `table_surface` and every gate trip.

The code lives in `plugin/workflow-src/standard-delivery/council.js`. It reaches `runPlanningPass` as an optional argument that only standard-delivery's `main.js` passes, so pr-feedback-remediation never consults and bundles no `council.js` function.

### Design-decision rule

An extension of Review Calls in `plugin/governance/decision-autonomy.md` for the design stages. A decision is taken when its recommendation is strong, it is inside the PRD's scope and its gate is clean.

A design decision's gate reads Promotion Gate clause 1, irreversible, and clause 3, safety-relevant. The always-ask list replaces clause 2. So a decision inside the PRD's scope that amends no accepted ADR does not trip it.

These are always asked: a change to the PRD's scope or acceptance criteria, an amendment of an accepted ADR, a trust-boundary, credential or merge-path change, and anything irreversible.

A design decision whose brief marks `needs_user_fact` true, or leaves it out, is asked and never sent to the council. An unmarked decision with a weak or absent recommendation goes to the council first:

- A strong result on the producer's option with a clean gate is taken and listed for veto.
- A strong result on another option is taken only after the conductor, as producer, reads that option's clauses 1 and 3 and its always-ask screen and finds them clean. The design is then written with that answer settled, and the decision is listed for veto.
- A split is asked with the council's opinions, per Council brief contract.

The design stages run no `decide()`. Take or ask is the conductor's judgment, checked by review. The review record lists each taken decision with its always-ask screen: an answer to each of the four always-ask items. The confirming pass checks every screen. A taken decision that should have been asked is a finding (#619). The review record lists each council-settled decision with the classification of its opinions and Abathur's output, and the confirming pass checks it (#619).

## State and ownership

No progress state is stored anywhere. Every row below is ground truth in GitHub or git, except the interrogated plan, the consult count and the council answers, which live only in one session or run.

| State | Home | Writer | Readers |
|---|---|---|---|
| Seed issue, later the epic | GitHub issue, identified by the Seed issue marker and a write-permission author | the guide at capture; `hivemind:prd-to-issues` reuses it | stage derivation, readiness check |
| Interrogated plan | live session, `.hivemind/plans/<slug>.md` | `hivemind:plan-interrogation`, `hivemind:create-handoff` | the same session only |
| PRD | `docs/prds/<slug>.md` | `hivemind:plan-to-prd` | design stages, readiness check |
| Solution design | `docs/initiatives/<slug>/solution-design.md` | a drone with exact file scope | design review, slices, readiness check |
| ADRs | `docs/adr/NNNN-<title>.md` | a drone with exact file scope at the design stage; `hivemind:plan-interrogation` during interrogation | readiness check |
| Review record | `docs/initiatives/<slug>/review-record.md` | the design review's record step only; every commit except a standard-delivery wave refuses it (#619) | readiness check, stage derivation, the design review's verify |
| Slices and blocked-by edges | GitHub sub-issues and issue dependencies | `hivemind:prd-to-issues` (sub-issues); triage `deps-add` (edges) | readiness check, handoff check, the Lair |
| Rating labels | GitHub labels | triage only, behind its confirm gate | readiness check |
| `readiness:ready` | GitHub label | a user with write permission, through triage (D29) | the handoff check, the Lair, under ADR-0045 decision 10, as amended by #625 |
| Consult setting | the `council_consult` object of `plugin/references/decision-autonomy-table.json` | #624, by pull request | the Consult step, the conductor |
| Consults used in a run | never stored: a script-local counter in the standard-delivery script, recomputed as a replay passes the same steps, so `resume_args` stays `{answers, build}`; in the design stages, the conductor's count per guide invocation | the Consult step; the conductor for its own count | the Consult step; the conductor for its own count |
| Council answers in a run | never stored: a script-local list in the standard-delivery script, rebuilt as a replay passes the same steps, never in `run.answerLog` or `resume_args`; in the design stages, the design itself | the Consult step; the conductor | `listAnswerEntries`, for every later scope, plan, revise and review prompt; the review record's veto list |

## Contracts and seams

### Readiness check output contract

Output: one JSON line per issue, `{"issue": <number>, "commit": "<evaluated trunk commit id>", "track": "standalone" | "slice", "result": "pass" | "fail", "reasons": [<code>, ...]}`, built with `jq --arg` and `--argjson`, never by splicing text. `reasons` is empty only on a pass.

Exit and failure rules:

- Exit 0 means every issue was evaluated. A missing document is a reason code, never a failure.
- Only an unresolvable commit id or a failed `gh` or `git` process exits non-zero.
- A read is truncated when any `pageInfo.hasNextPage` is true on labels, sub-issues or blockedBy, the rule `triage-ops.sh` already applies. A truncated read exits non-zero.
- Callers discard every line of a run that exits non-zero, and none treats it as a pass.

Reason codes, a closed set:

- Every issue: `issue_closed`, `rating_missing:<family>`, `is_epic`, `is_idea`, `has_subissues`, `no_acceptance_criteria`.
- Standalone: `spec_problem_missing`, `spec_evidence_missing`, `spec_scope_missing`, `open_questions_not_none`, `promote_type`, `promote_effort`.
- Slice: `epic_closed`, `parent_not_epic`, `epic_marker_missing`, `design_block_missing`, `design_link_invalid`, `design_slug_mismatch`, `prd_missing`, `design_missing`, `design_delivered`, `record_missing`, `template_section_missing:<name>`, `template_order`, `heading_duplicate`, `design_section_unfilled:<n>`, `design_open_questions`, `adr_missing:<path>`, `adr_not_accepted:<path>`, `record_malformed`, `record_not_passed`, `record_open`, `record_rounds_exceeded`, `record_stale:<path>`, `record_unstamped:<path>`, `heading_unmatched:<n>`, `heading_ambiguous:<n>`, `dependency_edge_missing:<n>`. `design_block_missing` replaces the earlier `design_section_missing`.

Pass-rule codes, one per clause of the pass rule in Review record front matter:

- `verdict` not `pass` gives `record_not_passed`.
- `clean_round` not `true` gives `record_not_passed`.
- `rounds` below 2 gives `record_not_passed`.
- `rounds` above 3 gives `record_rounds_exceeded`.
- Any open count above 0, at any severity, gives `record_open`.

A front matter off its shape, a blob off its pattern or a stamp path outside the path allowlist gives `record_malformed`.

Placeholders:

- In `design_section_unfilled`, `heading_unmatched` and `heading_ambiguous`, `<n>` is the 1-based index of the `- Heading:` line in the issue's Design block, never its text.
- In `dependency_edge_missing`, `<n>` is the number of a Dependencies `#<n>` ref with no native blocked-by edge.
- `<path>` appears only for a path that passed the path allowlist in Slice design section format.
- `<family>` and `<name>` come from closed lists.

An ADR is accepted when its `**Status:**` line's value starts with `accepted`.

### Document parsing rules

These rules serve issue bodies, the solution design and the record body (#615; #619's verify uses them).

- Headings are ATX lines, `#` to `######` then a space, outside fenced code blocks, which open with three backticks or `~~~`.
- Heading text is trimmed, and any trailing run of `#` is stripped.
- A section's body runs to the next heading of the same or a higher level, so subsections are inside it.
- A section is filled when its body holds a non-blank line that is not a heading.

### Standalone spec block format

A standalone issue body carries these sections: `## Problem`, `## Evidence`, `## Acceptance Criteria`, `## Scope boundary`, `## Open questions`. Each must be non-empty, Acceptance Criteria must hold at least one `- [ ]` or `- [x]` item, and Open questions must read exactly `None`.

### Slice design section format

A slice body holds exactly one `## Design` section, with one item per line:

- `- Solution design: [<path>](<link>)`, exactly one line
- `- Heading: <exact heading text>`, at least one line, one per heading
- `- ADR: [<path>](<link>)`, one line per ADR
- `- Review record: [<path>](<link>)`, exactly one line

Any other count of these sections or lines gives `design_block_missing`.

The slug is the parent epic's seed issue marker slug, never read from the issue. An epic whose body does not open with a valid seed issue marker gives `epic_marker_missing`.

Link rules, the path allowlist:

- A link is a bare path or `https://github.com/<owner>/<repo>/blob/<trunk>/<path>`.
- The Solution design link must resolve to a path of the shape `docs/initiatives/<s>/solution-design.md`, and the Review record link to `docs/initiatives/<s>/review-record.md`, where `<s>` matches `^[a-z0-9]+(-[a-z0-9]+)*$`.
- Each ADR link must resolve to a path matching `^docs/adr/[0-9]{4}-[a-z0-9]+(-[a-z0-9]+)*\.md$`.
- A link failing any shape rule yields `design_link_invalid`.
- A Solution design or Review record link whose `<s>` is not the epic's slug yields `design_slug_mismatch`.
- No git call is made for a failing link.
- The PRD is derived as `docs/prds/<slug>.md` from the epic's slug, never read from the issue.
- The PRD path must match `^docs/prds/[a-z0-9]+(-[a-z0-9]+)*\.md$`, both the path derived from the epic's slug and a PRD stamp path.
- The record must stamp the PRD and the solution design, else `record_unstamped:<path>`.

Each heading must match exactly one heading of the solution design, at any level, as literal text without `#` marks, per Document parsing rules.

### Seed issue marker

The guide writes `<!-- hivemind-initiative: <slug> -->` as the first line of the seed issue body at capture (#622). The marker slug must match `^[a-z0-9]+(-[a-z0-9]+)*$` before any `git` or `gh` use, else the issue is ignored and named (#621). #617 keeps the line when it reuses the seed as the epic, and #615 binds the epic's slices to its slug. Stage derivation (#621) takes as seed only an open issue with that line whose author has write permission. Any other issue carrying it is ignored and named. Two qualifying issues for one slug are ambiguous.

Epics created before the guide gain the seed marker in #615's delivery, which adds it by hand to epics #603 and #614 before the readiness check is first used to label any slice ready. Until then their slices fail `epic_marker_missing`.

### Solution design template

These `## ` sections, in this order: Context and code truth; Components; State and ownership; Contracts and seams; Trust boundaries; Lifecycle; Existing-path coverage; Failure modes; Decisions; Verification strategy; Seam order; Open questions; Amendments. Every heading in the file is unique. Open questions reads exactly `None`. Amendments may read `None yet.`.

The check parses the file per Document parsing rules:

- A missing `## ` section gives `template_section_missing:<name>`.
- Sections out of order give `template_order`.
- A heading text appearing twice gives `heading_duplicate`.
- An Open questions body other than exactly `None` gives `design_open_questions`.

After close-out the file gains `**Status:** delivered` under its title and an `## As-built deltas` section. A design is delivered when the first non-blank line after its `# ` title line is exactly `**Status:** delivered`. A slice whose design is delivered fails `design_delivered`; stage derivation and verify read the status by the same rule.

### Review record front matter

The record starts with this front matter, keys in this order, and the check parses only this fixed shape:

```yaml
---
stamps:
  - path: docs/prds/<slug>.md
    blob: <40 or 64 hex blob id>
  - path: docs/initiatives/<slug>/solution-design.md
    blob: <40 or 64 hex blob id>
verdict: pass | fail
open:
  critical: <n>
  high: <n>
  medium: <n>
  low: <n>
rounds: <n>
clean_round: true | false
---
```

Each `blob` is the output of `git rev-parse HEAD:<path>` on the docs branch when the record is written.

- Each blob matches `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$`.
- Each stamp path passes the path allowlist in Slice design section format, else `record_malformed`.
- Stamps must include the PRD, the solution design and every ADR its own docs pull request adds or edits, never an ADR it only cites.
- The record passes when `verdict` is `pass`, every open count (`critical`, `high`, `medium`, `low`) is 0, `clean_round` is `true` and `rounds` is 2 to 3. Round 1 is always followed by a confirming round. Each clause gives one reason code, per Readiness check output contract.
- `open.<severity>` counts that severity's findings whose disposition is `open`. Any critical or high whose disposition is not `fixed` or `rejected` counts as open.
- A record is authoritative only through a human-reviewed merge (D24). Only the design review's record step writes or re-stamps it. Every commit except a standard-delivery wave refuses `docs/initiatives/*/review-record.md` in code, per Review record body. The github-reviewer commits its own simple fixes with git, outside the workflow scripts: the Validation Procedure it loads forbids a fix that edits a record, and any record edit is authoritative only through the human-reviewed merge.

Staleness rule: the record is stale when any stamped path's `git rev-parse <commit>:<path>` differs from its blob, or the path is missing. A blob id is a content hash, so the merge method does not matter, and any edit to a stamped file makes the record stale until a review of the change re-stamps it.

### Review record body

The body has these sections:

- `## Reviewed documents`.
- `## Rounds`, with one `### Round <n>` per round naming each pass's reviewer agent, model and angle.
- `## Findings`.
- `## Decisions taken, listed for veto`, each with its always-ask screen, and for a council-settled decision the classification of its opinions and Abathur's output.
- `## Decisions asked`, each with the user's answer.

Findings is one Markdown table with the header `| ID | Round | Angle | Severity | Disposition | Note |` and one row per finding:

- ID is unique. Round is the round that disposed the finding.
- Angle is one of `A`, `B`, `confirm` or `review`. `review` marks a finding raised by local review or the post-PR review of the docs pull request.
- Severity is `critical`, `high`, `medium` or `low`.
- Disposition is exactly one of `fixed`, `rejected`, `deferred`, `recorded` or `open`.
- Note holds the summary and, for `rejected`, `deferred` or `recorded`, the reason and destination.

The readiness check never reads the body. The design review skill's `verify` (#619, D28) checks:

- the front matter shape;
- that each stamp equals the blob at the pull request head;
- for each record the pull request adds or edits, that its stamps include every ADR the pull request adds or edits, read from its diff against the merge-base with trunk; every other passing record gets stamp equality only, as on trunk;
- that the Findings table parses, IDs are unique and every row has exactly one disposition from the set;
- that the open counts equal the table under the open rule;
- that `verdict` is `pass` only under the pass rule, so a passing record with any open Findings row fails.

Verify prints one line `record-verify-failed: <record path>` per failing record.

Where verify runs:

- The guide runs it before `gh pr ready`, in any repository.
- In CI, in a repository that wires it, as this one does through `tools/validate.sh`, which #619 maps from `docs/initiatives/`, `docs/prds/` and `docs/adr/`. Every record the pull request adds or edits gets every check above, whether or not its design is delivered. Every other passing record whose design is not delivered gets stamp equality only, as on trunk. A delivered design's unedited record is skipped, because close-out stales it by design.
- A repository with no verify in CI keeps the guide's verify, the readiness check and the commit refusal below. The guide does not pass verify as a validation command, because a plan's validation commands are the planner's reading of the project's documented commands, so no code carries a guide-passed command to the validate step.

A verify failure is never fixed in place (#619):

- The validate step (`plugin/workflow-src/lib/gates.js`, shared with pr-feedback-remediation) reads the failures of a failed validation in code. A trimmed line of `record-verify-failed: ` and a path matching `^docs/initiatives/[a-z0-9]+(-[a-z0-9]+)*/review-record\.md$` stops the run blocked, next action report, naming each such record encoded, before any `validation_remediation` decision, so no fix round runs. The failures description asks for each such line word for word, and the Validation Procedure of `plugin/governance/definitions.md` says the same.
- `runCommitStep` (`plugin/workflow-src/lib/commit.js`) refuses, before any runner call, a commit whose file list holds a path matching `^docs/initiatives/[^/]+/review-record\.md$`, compared case-insensitively, as a terminal stop naming the path encoded. Only a wave commit of a workflow whose `main.js` declares record writes may carry one, and only standard-delivery's does, because the record step is a standard-delivery wave. Which wave writes it is the accepted plan's, and the record is authoritative only through the human-reviewed merge (D24). So no validation fix round, in either workflow, and no pr-feedback-remediation commit carries a record, even when the validate drone leaves verify's line out.
- The guide then starts the re-review path.

### Council brief contract

Input: a planner question in standard-delivery, or a design decision brief, valid against `plugin/references/decision-brief-schema.json`. #618 adds two optional fields and no other:

- `needs_user_fact`, a boolean. Its schema description tells every producer to set it true when the answer needs a fact only the user holds, and false otherwise.
- the bounded `council` object.

Options gain no gate, and existing briefs stay valid. Only a brief whose `needs_user_fact` is false is convened; true or absent never is.

Member output: each member returns `{option_id, strength, why}`, with strength `strong`, `weak` or `none`.

Abathur output: Abathur gets the input brief and the opinions as data. It returns only `{option_id, strength, why}`. `option_id` is one of the input's option ids, and strength is `strong` or `none`. A split is `none`. A `weak` strength, an unknown option id or any other shape means no council result.

Composed output: the caller builds it. It is the input brief unchanged except `recommendation`, `gate` and `council`. Options, option ids, problem, criticality, assumptions and `needs_user_fact` never change.

- Abathur strong on the input's recommended option: the recommendation is that option, strong, with Abathur's why. The gate is the input's.
- Abathur strong on another option: the recommendation is that option, strong, with Abathur's why. The gate is the producer's gate read of that option: in standard-delivery a fresh planner call per Consult step, in the design stages the conductor's read. With no usable gate read, the recommendation is the input's with strength `none`, and the gate is the input's.
- Abathur `none`: the recommendation is the input's with strength `none`, and the gate is the input's.
- `members` has one entry per valid opinion. `id`, `angle` and `model` come from the caller's launch record. `option_id`, `strength` and `why` come from that member's output.
- `dissent` has one entry per member whose `option_id` differs from the composed recommendation's option: `member_id`, `option_id`, `why`.

No member or Abathur text reaches options, problem, criticality, assumptions or gate. A claimed model is ignored. `decide()` resolves every composed brief, so a gate trip asks.

Bounds: `members` holds 2 to 4 items, counting a runner member, and `dissent` at most 4. Each `why` has maxLength 200, is described "Written for the user" and is rendered encoded as untrusted text. `id`, `angle` and `model` have maxLength 64. A result counts only with at least two members whose `model` values differ. #618 extends `tests/workflow-scripts/data.test.mjs` for them.

### Runner member brief mode

The runner member runs only when `HIVEMIND_LOCAL_REVIEWER` is a JSON argv list. The caller launches two to four members in all, so a council with a runner member has at most three Overseers. Unset or the `codex-plugin` preset means no runner member. The council then needs two Claude members on two Claude models. The runner member's `model` value is `runner:` plus the basename of argv[0]. That names the tool, never a model (ADR-0042 decision 7).

It is a sixth script of the Synapse Runner Gate: `plugin/skills/council-member/scripts/council-member.sh`, with `plugin/skills/council-member/SKILL.md`. #618 edits:

- `plugin/hooks/synapse-gate.sh`, `plugin/governance/security-policy.md` (Synapse Runner Gate), `tests/policy/safety-synapse-gate.json` and `tools/test_synapse_gate.sh`;
- `plugin/agents/synapse.md`: its Input contract carries `inputs_file` also for a council opinion;
- `plugin/skills/_shared/containment.sh`: `hivemind_remove_inputs_file` accepts kind `council`, with `tools/test_shared_libs.sh`;
- `plugin/skills/_shared/settings-merge.sh` and `.claude/settings.json`: they seed `Edit(.hivemind/council-inputs-*.json)`, as the molt and pull request inputs-file rules are seeded (asked in design review round 2, answer Q7 A), with `tests/policy/safety-navigator-transport-rules.json` and `tools/test_seed_hive.sh`;
- `plugin/governance/security-policy.md` (Synapse Runner Gate): two residual bullets widen, within answers Q3 A and Q7 A. Cross-script use widens to six scripts, including the run of the configured reviewer tool through `council-member.sh`. The broken-hook seeded-rules bullet widens to the `Edit(.hivemind/council-inputs-*.json)` rule;
- `plugin/skills/council-member/SKILL.md` carries the `Edit(.hivemind/council-inputs-*.json)` entry, so `docs/skill-authoring.md` (Covered Navigators) gains a `hivemind:council-member` line with fixed path `.hivemind/council-inputs-<token>.json` and Edit glob `.hivemind/council-inputs-*.json`. `council-member.sh` sources `containment.sh` in the direct form and reads its inputs file only after `hivemind_assert_inputs_contained`;
- `tools/validate.sh` routes `plugin/skills/_shared/runner-kernel.sh` and `plugin/skills/council-member/scripts/council-member.sh` to `test_run_review`, and `tools/test_run_review.sh` gains the brief-mode cases.

#624 extends the `--inputs` pattern of `runnerValuePatterns` in `plugin/workflow-src/lib/facts.js` to the council inputs file.

Synapse's Write allow gains one fixed inputs file, `.hivemind/council-inputs-<token>.json`. It is the only way the brief reaches the script, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern). The engine reaches the script through synapse. The main-session guide reaches it through `hivemind:council-member`.

Per [docs/engineering-principles.md](../../engineering-principles.md) P9 it shares only the runner's kernel with `run-review.sh`. The kernel is:

- the reviewer-setting read and argv check;
- the no-shell argv run under `timeout -k 5 <deadline>`;
- the before/after work-tree check, where any change blocks and discards the opinion;
- the reply JSON extraction.

The kernel moves to `plugin/skills/_shared/runner-kernel.sh`. Review mode's behavior and output do not change, and `tools/test_run_review.sh` stays green. `run-review.sh` still runs every local review (ADR-0042 decision 9).

### Consult setting

A top-level object `council_consult` in `plugin/references/decision-autonomy-table.json`, beside `rows` and never a row. It holds one value per level, `consult` or `skip`, and an integer `per_run_cap`. `rows` and `hard_stops` are unchanged, so no call site can pass it as a kind. A level's `consult` value has effect only where that level's `planner_question` cell is `auto`: elsewhere `decide()` asks `table_surface` first, so no planner question is convened.

#624 extends `projectAutonomyTable` in `tools/build_workflows.mjs` to project it, and updates `tests/workflow-scripts/build.test.mjs` and `tests/workflow-scripts/data.test.mjs`. All three built scripts carry the projected table, so #624 regenerates each (D20). #624 sets the `unattended` value and lands after #607 adds that level (ADR-0045 decision 6). In the design stages the conductor reads the value at the table's `default_level`. It allows at most `per_run_cap` consults per guide invocation (#622).

### Consult step

Only standard-delivery runs the step. Its code is `plugin/workflow-src/standard-delivery/council.js`, passed to `runPlanningPass` as an optional fifth argument that only standard-delivery's `main.js` passes. `escalation.js` passes none, so pr-feedback-remediation never consults. `decide()`, `resolveDecision` and `resolvePlanAsks` are unchanged.

1. The step runs once per new checked planner result, plan or revise, after any reply round is logged and rescoped and before `resolvePlanAsks`. A shown result restored when a reply settles the plan acceptance is not consulted again.
2. It takes each planner question in order and nothing else. Every case Mid-delivery consult names as never consulted stays out.
3. It reads the question through `resolveDecision`, with kind `planner_question` and the pass scope, on a scratch resolution, as `buildUndecidedAsk` does. So `decide()` gains no call site, and SD-29 holds.
4. It convenes only when all of these hold; otherwise the question stays as it came:
   - the question is not settled: its key, as `questionKey` builds it from kind `planner_question`, the pass scope and the question rendered alone, is not in `run.answeredKeys`;
   - `needs_user_fact` is false;
   - the read is a take of a `weak` recommendation or an ask with reason `no_recommendation`;
   - `council_consult` at the run's level is `consult`;
   - the run's consult count is below `per_run_cap`.

   A settled question resolves as answered, neither convened nor taken, and is left out of the list `resolvePlanAsks` gets.
5. The count rises by one per convened council, whether or not it returns a result.
6. It launches the members in parallel, scans their opinions, launches Abathur and scans its output. A suspect scan ends the run with the terminal stop `runPassScan` returns for a suspect scan (ADR-0037: injection-suspect stays terminal). In an unattended run it is an approval park (ADR-0045 decision 7). The first read never stands. A scan that fails, times out or returns an unusable result gives no council result: the question stays as it came, and the attempt counts toward the cap.
7. It composes per Council brief contract. When Abathur's option is not the planner's recommended option, the gate comes from a gate read: one fresh hivemind:cerebrate call whose prompt holds only the planner question, as data, and that option id, and whose result is the brief schema's gate object.
8. It reads the composed brief through `resolveDecision` on a scratch resolution:
   - A take on another option is listed in `run.taken` through `acceptResolution`, as `resolveTailDecision` (`plugin/workflow-src/lib/tails.js`) does. The council answer joins the run's council answers. `runPlanningPass` returns `{replan}` with a code-built reason, the shape `buildReplyReplan` builds. So the next pass starts from the facts step (ADR-0037 invariant 3), outside `maxReplans()` and bounded by `per_run_cap`, and the first result is never accepted.
   - A reason outside `askReasons()`, such as `malformed_brief` for a beyond-request option, gives no council result.
   - Any other result replaces the question with the composed brief, which `resolvePlanAsks` resolves: a take on the planner's option, or an ask with the dissent that parks in an unattended run (#607). `runPlanningPass` gives that composed ask its raw question's key, so a reply settles the raw question. Within a pass, a raw question raised again reuses its composed brief with no new council.
   - With no council result, the question stays as it came.
9. `listAnswerEntries` gives one settled entry per council answer, after the launch decision entries and before `run.answerLog`, built by `buildAnswerEntry`. Its question names the council and holds the planner's question as rendered; settled is its label; the reply is the council option's shown letter. No member or Abathur text enters it. A council answer never enters `run.answerLog`, its rounds, `resume_args`, `run.headRound` or the resume note. With no council answer, every prompt is byte for byte as before. SD-60, SD-67 and SD-80 add the council entries (#624). A composed ask the user answers enters `run.answerLog` like any shown question, so its council text reaches later prompts only inside that question.
10. Member, scan, Abathur and gate-read prompts are built only from the brief, the option id and the run's fixed values, with labels from the pass and the count, so a resume replays them from cache. The count, the council answers and the composed briefs kept for reuse start empty on each launch and are rebuilt on replay. `resume_args` stays `{answers, build}` (`plugin/workflow-src/lib/args.js`).
11. `askReasons()`, `listReasons()`, the check order, `pauseDelivery`'s guard, SD-29 and SD-82 are unchanged. So ADR-0037 is not amended.

Every take a council causes matches the plan that runs. The planner plans assuming its own recommended option, and after a switch the plan that runs was planned with the answer settled. Whether a planner honors a settled answer is its judgment, for a council answer as for a user's (the `plugin/workflow-src/lib/plan.js` header).

## Trust boundaries

- **External content stays data.** Issue bodies, PRD and design text, review findings, member opinions and Abathur's brief are data per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (External Content Boundary). The readiness check parses fixed shapes and literal heading text and never runs or evaluates content. Links pass the path allowlist before any git call. Reason codes carry line indexes, never issue text. JSON is built with `jq --arg`. The Lair queue report and parks show reason codes encoded as untrusted data, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Trust-Boundary Discipline). Slices: #615, #621, #623, #624.
- **Write permission authorizes the ready label.** The authorization is write permission on the latest `readiness:ready` labeled event, with the title and body unedited since (ADR-0045 decision 10, as amended by #625; D29). The handoff check verifies the same (#621), and the Lair keeps its check (#623). "Maintainer" names a role, and triage's confirm gate is a workflow step, not an authorization boundary. The guide and the Lair never apply the label. Slices: #620, #621, #623.
- **Reviewers are fresh and read-only.** Review passes run on cerebrate, whose tool list holds no Bash, Write or Edit. `Memory context: none` keeps the writing session's memory from steering a reviewer. A pass that errors, times out or returns unparseable output yields no round. Slices: #619.
- **Stamps bind the reviewed content.** The record ships in the same pull request as the design, so it passes the same local review and bot review. Trunk never holds an unreviewed design, and any later edit is detected by blob id. Authority is a human-reviewed merge (D24). Only the design review's record step writes or re-stamps a record. Verify runs before the pull request leaves draft and, where wired, in CI (D28). Every commit except a standard-delivery wave refuses a record in code. #623 keeps docs paths out of the Lair's auto tier. Recorded residual: with `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a bot approval with no human review of the design. It is recorded per the user's decision, on the ground that it is outside the threat model as the maintainer's own opt-in (ADR-0044). It is bounded: where verify runs in CI, it keeps a merged record consistent and current, and in any repository the commit refusal, the guide's verify before ready and the readiness check, which fails every slice of a stale or delivered design, hold (ADR-0046, Residuals). Slices: #615, #619, #622, #623.
- **The council cannot widen authority.** Options, option ids, problem, criticality and assumptions never change. Every gate is a producer read: the input's for the producer's own option, and a fresh gate read for another, so no gate is council-written. `decide()` resolves every composed brief. Abathur writes only an option id among the input's, a strength and a why. A question marked `needs_user_fact` true, or left unmarked, is never convened. Council text reaches a planner prompt only inside a question shown to the user: a composed ask's Abathur why and dissent whys, each scanned before compose, at most 200 characters and rendered encoded as untrusted text, carried in the answers block as data. A council answer entry for a take is code-built and holds none. Member provenance comes from the caller's launch records. The `abathur` and `overseer` tools lists hold no Bash, Write, Edit or agent-launch tool, pinned by a safety fixture under `tests/policy/` (#618). The runner member runs under the kernel's no-shell argv run and before/after check. Opinions are scanned before Abathur, and Abathur's output before compose. A scan that fails gives no council result, so unscanned council text is never used. A suspect one is a terminal stop in standard-delivery and an approval park in an unattended run. In the design stages the conductor classifies each opinion and Abathur's output per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Injection-Suspect Classification) and asks a suspect one (Tier A injection-suspect). Slices: #618, #622, #624.
- **Unattended runs never decide a split.** A split or always-ask call parks with the brief and dissent. Its text is encoded as untrusted data in the park record. Slices: #624, with #607.
- **No new credential and no merge-path change.** Everything runs under the executing user's credentials, and `merge-approved.sh` is untouched. The two trust-boundary changes, a sixth runner-gate script and the overlord's two new agents, were asked (D22, D23). The seeded `Edit(.hivemind/council-inputs-*.json)` rule was asked (D30, answer Q7 A). The record refusal narrows only what a fix commit may carry; `merge-approved.sh` and the merge path are untouched. Slices: #618, #619, #622.

## Lifecycle

### Initiative stages

1. **Capture.** The guide creates the seed issue. Its body links `docs/prds/<slug>.md`, which may not resolve until the docs merge.
2. **Interrogation.** The guide has created the docs branch before interrogation writes tracked files. `hivemind:plan-interrogation` runs in one session. This is the one single-machine window: its plan lives in the session or `.hivemind/`, so another machine sees only the seed issue.
3. **PRD.** `hivemind:plan-to-prd` writes the PRD on the docs branch `docs/<slug>` or `docs/<slug>-<suffix>`. The guide commits the PRD and the interrogation outputs on that branch.
4. **Solution design and ADRs.** Written on the docs branch by drones with exact file scope, in standard-delivery runs the guide launches with `draft` true and no closable launch reference. The first run opens the docs pull request as a draft with no Closes line; later runs reuse it.
5. **Design review.** Per the design review rounds below; the record is written on the docs branch.
6. **Docs pull request.** It has been a draft since stage 4. It leaves draft through `gh pr ready` only after verify passes at its head, and merges to trunk. A later push by the guide that changes a stamped path returns it to draft.
7. **Slicing.** `hivemind:prd-to-issues` reuses the seed issue as the epic and adds each slice's design section.
8. **Triage.** The maintainer runs triage; it gates `readiness:ready` on the readiness check and writes native blocked-by edges.
9. **Handoff check.** It passes only when every slice passes, and names each slice as claimable now or blocked.

Stage derivation picks the latest stage whose evidence exists. Evidence it cannot resolve to one answer, such as two seed issues for one slug or two open docs pull requests, is reported as ambiguous and asked, never guessed.

### Design review rounds

Round 1 is two parallel fresh passes: angle A (code truth, governance and ADR conflicts, existing-path coverage) and angle B (failure modes, trust and injection, testability). Findings are fixed on the docs branch. Each later round is one fresh confirming pass over both angles. A pass that errors, times out or returns output the skill cannot parse yields no round and is re-run. Only a completed pass whose parsed list of new findings is empty makes a clean round. The review exits only when, after dispositions, no finding at any severity is open, and one round is clean: the pass rule of Review record front matter. So a passing review has 2 or 3 rounds. A review that has not converged after round 3 stops and reaches the maintainer as a signal to split the initiative. Every finding gets exactly one disposition: `fixed`, `rejected` with its reason, `deferred` or `recorded`. Critical and high findings are only `fixed` or `rejected`. Mediums follow `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Defer-with-Scope, Recorded Residual).

The record step rewrites the record after every round: `verdict` stays `fail` until exit, and `rounds`, the open counts and the Findings table stay current. A lost session resumes from the record's rounds.

This initiative's own review has one user-approved exception, D31.

### Re-review and re-stamp

- Review fix: a local-review or post-PR fix that changes a stamped document of a passing record after the review exited stales it: verify fails, and where the project's validation runs verify, the validate step stops the run blocked, naming the record (Review record body). The design review then runs one fresh confirming pass over the diff since the stamped blobs. With no new finding the record step re-stamps, and the pass is appended under Rounds as a confirming pass that does not change `rounds` and does not count toward the cap. With a new finding it becomes a re-review.
- Re-review after an amendment: fresh passes run over the diff since the stamped blobs, with rounds counted from 1 for that review. The front matter is replaced, and the body history is appended under a dated heading.

### Close-out

When every slice is done, the solution design gains `**Status:** delivered` and an `## As-built deltas` section in one docs pull request, and is never maintained afterward. The truth then lives in code, ADRs, the glossary and governance.

Close-out edits the stamped design, so its record goes stale by design. Stage derivation reads `**Status:** delivered` first, and a delivered design's record is never re-stamped. Verify skips its unedited record, and its slices fail `design_delivered` (Review record body, Solution design template).

## Existing-path coverage

One row per existing path, with its effect and the slice that makes it. "Unchanged" rows name the slice that relies on them, or none.

| Existing path | Effect | Slice |
|---|---|---|
| `plugin/skills/triage-backlog/SKILL.md`, `plugin/skills/triage-backlog/scripts/triage-ops.sh` | Gains the `readiness` subcommand with the overlay as a `--overlay` JSON argument, as `apply-labels --targets` takes its targets, the apply order (ratings and edges, then the re-check, then `readiness:ready`), reason codes in Notes, `readiness:blocked` narrowed to blocks with no issue link, and `deps-add` edges from Dependencies refs. The confirm gate, `triage:locked` and the per-family mutex are unchanged. | #615, #620 |
| `tools/test_triage_ops.sh`, `tests/triage-backlog/` | Gain the readiness gate, overlay and re-check cases. | #620 |
| `plugin/skills/plan-interrogation/SKILL.md` | Unchanged. The guide commits its outputs on the docs branch. | #622 |
| `plugin/skills/plan-to-prd/SKILL.md` | Unchanged. The guide commits the PRD on the docs branch. | #622 |
| `plugin/skills/molt/SKILL.md` | Unchanged. The guide commits through it with exact paths. | none |
| `plugin/skills/prd-to-issues/SKILL.md`, `plugin/skills/prd-to-issues/scripts/subissue-ops.sh` | Gain the `## Design` section, seed reuse through `ensure-parent --existing-number` with the seed marker line kept, and a carve-out of the "No file paths or code snippets" rule for Design links. Idempotency and the four existing sections are unchanged. | #617 |
| `tools/test_subissue_ops.sh`, `tests/prd-to-issues/` | Gain the Design section and seed reuse cases. | #617 |
| `plugin/skills/create-handoff/SKILL.md` | Unchanged. Its handoff is never stage evidence. | none |
| `plugin/governance/decision-autonomy.md`, Review Calls and Tier A | Gains the design-decision rule and one consult-step sentence. The Tier A line "On the script engine, `decide()` asks only for" is unchanged. Each edit fits the byte budget by cutting. | #616, #624 |
| `plugin/governance/remediation-doctrine.md` | No edit planned; the design review skill cites Defer-with-Scope and Recorded Residual. | none |
| `plugin/references/decision-autonomy-table.json` | Gains the top-level `council_consult` object. Rows and hard stops are unchanged. | #624 |
| `tools/build_workflows.mjs` | `projectAutonomyTable` projects `council_consult`. | #624 |
| `tests/workflow-scripts/build.test.mjs`, `tests/workflow-scripts/data.test.mjs` | Pin the projected keys and the setting's values; check the optional `needs_user_fact` boolean and the bounded council fields written for the user. | #618, #624 |
| `plugin/references/decision-brief-schema.json` | Gains the optional `needs_user_fact` boolean and the bounded `council` object. Options gain no gate, existing briefs stay valid, and every built script regenerates. | #618 |
| `plugin/workflow-src/lib/decide.js`, `tests/workflow-scripts/decide.test.mjs` | Unchanged. | none |
| `plugin/workflow-src/lib/plan.js` | `runPlanningPass` takes an optional consult argument, awaited on each new checked planner result before `resolvePlanAsks`, and returns the consult's `{replan}` on a council switch. `listAnswerEntries` puts one settled entry per council answer after the launch decision entries. `runPlanningPass` also gives each composed ask its raw question's key. `resolveDecision` and `resolvePlanAsks` are unchanged. | #624 |
| `plugin/workflow-src/lib/retry.js`, `plugin/workflow-src/lib/tails.js`, `plugin/workflow-src/lib/record.js` | Unchanged. `hasDefectQuestion` keeps `decide()` alone. Tail asks, `buildUndecidedAsk` and `buildReplyReplan` included, are never consulted, and the consult returns `{replan}` in `buildReplyReplan`'s shape. The `pauseDelivery` guard and `isShownDecision` are unchanged. | #624 |
| `plugin/workflow-src/lib/args.js` | Unchanged; `resume_args` stays `{answers, build}`. | none |
| `tests/policy/safety-ask-set.json`, `tests/workflow-scripts/ask-set.test.mjs` | Unchanged and green. | none |
| `plugin/workflow-src/standard-delivery/` | Gains `council.js` (Consult step, gate read, compose). `main.js` passes the consult and the council settings, and its run state gains the script-local count and council answers. `contract.js` gains the council rows, and SD-60, SD-67 and SD-80 name the council answer entries. SD-29, SD-82 and the pause contract are unchanged. `main.js` declares that its waves may commit a review record, and `contract.js` SD-25 and SD-26 name the record stop and the fix-commit refusal (#619). | #619, #624 |
| `plugin/workflow-src/analysis-only/`, `plugin/workflow-src/pr-feedback-remediation/` | Analysis-only source unchanged. pr-feedback-remediation's `main.js` declares that its waves commit no review record, and `contract.js` PFR-22 and PFR-23 name the refusal and the record stop (#619). `escalation.js` passes no consult argument, so neither workflow consults (#624). | #619, #624 |
| `plugin/hooks/synapse-gate.sh`, `plugin/governance/security-policy.md` (Synapse Runner Gate), `tests/policy/safety-synapse-gate.json`, `tools/test_synapse_gate.sh` | Gain the sixth runner script, `plugin/skills/council-member/scripts/council-member.sh`, and synapse's `.hivemind/council-inputs-<token>.json` Write. Two residual bullets widen: Cross-script use to six scripts, including the configured reviewer tool's run through `council-member.sh`, and the broken-hook seeded-rules bullet to the `Edit(.hivemind/council-inputs-*.json)` rule. | #618 |
| `plugin/agents/synapse.md` | Its Input contract carries `inputs_file` also for a council opinion. Its name is not reused. | #618 |
| `plugin/skills/_shared/containment.sh`, `tools/test_shared_libs.sh` | `hivemind_remove_inputs_file` accepts kind `council`. | #618 |
| `plugin/skills/_shared/settings-merge.sh`, `.claude/settings.json`, `tests/policy/safety-navigator-transport-rules.json`, `tools/test_seed_hive.sh` | Seed `Edit(.hivemind/council-inputs-*.json)` beside the molt and pull request inputs-file rules (asked, answer Q7 A). | #618 |
| `plugin/skills/adaptation-cycle/scripts/run-review.sh`, `tools/test_run_review.sh` | The runner kernel moves to `plugin/skills/_shared/runner-kernel.sh`. Review mode is unchanged and its cases stay green; `tools/test_run_review.sh` gains the council-member brief-mode cases. | #618 |
| `docs/skill-authoring.md`, Covered Navigators | Gains the `hivemind:council-member` line: fixed path `.hivemind/council-inputs-<token>.json`, Edit glob `.hivemind/council-inputs-*.json`, read-guard `hivemind_assert_inputs_contained` in `council-member.sh`, which sources `containment.sh` in the direct form. CHECK 14 and CHECK 16 of `tools/policy_check.sh` read it. The guide and triage-backlog carry no `Edit(.hivemind/` entry, so neither is a navigator. | #618, #620, #622 |
| `plugin/agents/cerebrate.md` | Unchanged. Review passes use it with `Memory context: none`. When to set `needs_user_fact` is the field's schema description, and its answers rule reads a council answer entry by its settled labels. | #618, #624 |
| `plugin/workflow-src/lib/brief.js` | Renders the bounded council fields encoded as untrusted text. `buildAnswerEntry` is unchanged. | #624 |
| `plugin/workflow-src/lib/facts.js` | `runnerValuePatterns` allows `--inputs` as the council inputs file. | #624 |
| `plugin/workflows/standard-delivery.js`, `plugin/workflows/analysis-only.js`, `plugin/workflows/pr-feedback-remediation.js` | Regenerated; their BUILD_IDs change, and each fits D20. | #618, #619, #624 |
| `plugin/agents/overlord.md` | The Agent allowlist gains hivemind:abathur and hivemind:overseer. The Write grant is unchanged. | #622 |
| `CONTEXT.md` | This pull request adds the initiative's terms and fixes the stale "planned" notes. | #627 |
| `docs/adr/0045-lair-software-factory.md` | Not edited here; decision 10 is amended by #625. | #625 |
| `tools/validate.sh` | Maps `docs/initiatives/`, `docs/prds/` and `docs/adr/` to the record verify suite, and registers the readiness check (#615), design review (#619) and stage derivation (#621) suites, and routes `plugin/skills/_shared/runner-kernel.sh` and `plugin/skills/council-member/scripts/council-member.sh` to `test_run_review` (#618). | #615, #618, #619, #621 |
| `plugin/workflow-src/lib/gates.js` | The validate step, shared with pr-feedback-remediation, reads verify's `record-verify-failed:` line from a failed validation in code and stops blocked, naming the record, before any `validation_remediation` decision. Its failures description asks for that line word for word. The fix-round commit refuses a review record. | #619 |
| `plugin/workflow-src/lib/commit.js` | `runCommitStep` refuses a review record path before any runner call, a terminal stop naming it, except in a wave commit of a workflow whose `main.js` declares record writes. | #619 |
| `plugin/governance/definitions.md`, Validation Procedure | Gains the record rule: each `record-verify-failed:` line of failure output is reported word for word, and no fix edits a review record. It fits its budget by cutting (D20). | #619 |
| `plugin/agents/github-reviewer.md` | Unchanged. It loads the Validation Procedure, so the record rule binds its own fix commits. | #619 |
| `tests/workflow-scripts/standard-delivery.test.mjs`, `tests/workflow-scripts/pr-feedback-remediation.test.mjs` | Gain the record stop and commit refusal cases. | #619 |
| `plugin/skills/open-plan-pr/scripts/open-plan-pr.sh` | Unchanged. A reused pull request keeps its draft state, and the `draft` launch arg (SD-48) is unchanged. | #622 |
| Lair controller, not yet built (#608) | The readiness check is its admission step. Its protected-path list gains `docs/prds/`, `docs/initiatives/` and `docs/adr/` under the #625 amendment. | #623 |
| Lair initiative, epic #603 | The PRD's Lair retrofit criterion is covered by #625, the first pilot. #625's acceptance criteria verify it: the record passes with stamps equal to trunk, and every Lair slice passes the readiness checklist by hand. Once #615 and #620 land, triage's readiness gate also checks the Lair slices before any is labeled ready under the new rule. #615's delivery adds the seed marker to epic #603 by hand before the readiness check is first used to label any slice ready; until then its slices fail `epic_marker_missing`. | #625, #615 |

## Failure modes

| Failure | Handling | Slice |
|---|---|---|
| A stamped document is edited after review | The record is stale (`record_stale:<path>`) until a review of the change re-stamps it; every slice fails the check meanwhile. | #615, #619 |
| A merge conflict resolution edits a stamped document | Same as above, seen on trunk; a follow-up docs pull request re-reviews and re-stamps. | #615, #619 |
| A passing record goes stale on a later push | Where verify runs in CI, it fails, and the guide returns the pull request to draft. In any repository the readiness check fails every slice with `record_stale:<path>`. | #619, #622, #615 |
| Another initiative's docs pull request adds an ADR | ADR inclusion is checked only for records the pull request adds or edits, so every other passing record gets stamp equality only. | #619 |
| A fix round or post-PR fix would re-stamp a record to clear verify | Never: every commit except a standard-delivery wave refuses a review record path in code, a terminal stop naming it, and the edit stays uncommitted. The validate step reads verify's `record-verify-failed:` line in code and stops blocked before any `validation_remediation` decision. | #619 |
| A docs-branch run would open a ready pull request or add a Closes line | The guide launches every docs-branch run with `draft` true and no closable launch reference. | #622 |
| A pull request edits a stamped PRD or ADR outside `docs/initiatives/` | Where verify runs in CI, `docs/prds/` and `docs/adr/` map to it, which fails it. A record stale on trunk fails every slice with `record_stale:<path>` until a re-review. | #619, #615 |
| A record claims pass with an open Findings row | Verify fails. | #619 |
| The validate drone leaves verify's line out of its failures | The failure takes the fix path, but no fix commit can carry the record, so verify keeps failing until a review re-stamps it, and the fix limit asks. | #619 |
| A design is marked delivered to escape verify | A record the pull request edits is verified whatever its design's status, and every slice of a delivered design fails `design_delivered`. | #615, #619 |
| A repository wires no verify in CI | The guide's verify before `gh pr ready`, the readiness check and the commit refusal hold; a stale record fails every slice with `record_stale:<path>`. | #615, #619, #622 |
| #625 merges first and changes ADR-0045 | No effect: this design cites only "ADR-0045 decision 10, as amended by #625" and never stamps ADR-0045. | #625 |
| ADR number 0046 or 0047 is taken on main | Checked before the pull request opens and before it leaves draft; the ADR is renumbered and every link updated. | #627 |
| A design review pass errors, times out or returns unparseable output | It gives no round and is re-run. | #619 |
| A session is lost mid-review | The next session resumes from the record's rounds. | #619 |
| Local review or a post-PR fix changes a stamped document | One confirming pass over the diff, then a re-stamp; the pass does not count toward the cap. A new finding makes it a re-review. | #619 |
| The design review does not converge by round 3 | It stops and reaches the maintainer as a signal to split the initiative. | #619 |
| `gh` or `git` fails, or a read is truncated | The check exits non-zero; no caller reads it as a pass, and the Lair leaves the issue unclaimed. | #615, #623 |
| A linked document is missing | A reason code; the run continues to the next issue. | #615 |
| A caller passes a branch name, a local ref or a malformed id | Rejected before any git call. Callers pass the fetched remote commit id, so a stale local ref is never read. | #615, #620, #621, #623 |
| Link or heading text in an issue body is hostile | A link failing the path allowlist gives `design_link_invalid` with no git call. Heading codes carry the line index, never the text. | #615 |
| A named heading matches zero or several headings | `heading_unmatched` or `heading_ambiguous`; the slice fails. | #615 |
| The review record's front matter is off its shape | `record_malformed`; the slice fails. | #615 |
| Design links name another slug, or the epic lacks a seed marker | `design_slug_mismatch` or `epic_marker_missing`; the slice fails. | #615 |
| A Design block has duplicate or missing lines | `design_block_missing`; the slice fails. | #615 |
| A seed marker carries a malformed slug | Ignored and named, with no `git` or `gh` call. | #621 |
| A Dependencies ref has no native blocked-by edge | `dependency_edge_missing:<n>`; triage writes the edge through `deps-add`. | #615, #620 |
| Labels are applied after the check | The overlay checks the pending labels, and the post-apply re-check drops any issue that now fails. | #620 |
| A slice passes with open blockers | It may be labeled ready; the Lair still claims it only when no blocked-by dependency is open. | #620, #623 |
| The issue is edited between the check and the claim | The unedited check of ADR-0045 decision 10, as amended by #625, and the body hash captured at claim time stop it. | #623 |
| A council member fails, times out or returns off schema | Abathur weighs the rest. With too few members on two models, or off-schema Abathur output, there is no council result, and the question is resolved as it came. The attempt counts toward the cap. | #618, #624 |
| Abathur picks an option other than the producer's recommendation | The producer's gate read of that option decides. Clean: the take is journaled and the run plans again with it settled. A trip asks or parks. No usable read gives strength `none`, asked or parked. Options and option ids never change. | #618, #624 |
| A composed brief `decide()` refuses as a defect | No council result; the question is resolved as it came. No ask outside the Ask Set reaches `pauseDelivery`. | #624 |
| A member opinion or Abathur's output is injection-suspect | A terminal stop, as the pass scan gives; an approval park in an unattended run. The first result never stands. In the design stages it is asked. | #618, #622, #624 |
| A member or Abathur scan fails, times out or returns an unusable result | No council result; the question is resolved as it came, and the attempt counts toward the cap. Unscanned council text is never used. | #624 |
| A question needs a fact only the user holds | Marked `needs_user_fact` true, it is never convened and reaches the user as it would with no council. In the design stages the conductor asks it. | #618, #622, #624 |
| A planner question leaves `needs_user_fact` out | Never convened; resolved as it came. | #624 |
| A code-built brief, a `buildUndecidedAsk` site or a review call has no strong recommendation | Never consulted; resolved as today. `buildUndecidedAsk` never throws for it. | #624 |
| A council splits on a weak or unanswered question | It asks `no_recommendation` with the dissent. | #624 |
| A later plan raises a council-settled question again | It breaks the settled-answer rule as it would for a user's answer. It is resolved like any planner question under the cap, and every take is listed for veto. | #624 |
| A user-settled composed ask's raw question is raised again in the same run | Answered by the raw question's key: never convened again and never taken. | #624 |
| A member claims a model or provenance | Ignored; `id`, `angle` and `model` come from the caller's launch record. | #618 |
| `HIVEMIND_LOCAL_REVIEWER` is unset or the `codex-plugin` preset | No runner member; the council needs two Claude members on two Claude models. | #618 |
| The runner member changes the work tree | The before/after check blocks it, and its opinion is discarded. | #618 |
| The per-run cap is reached | No consult; the question is resolved as it came. | #624 |
| A council splits in an unattended run | Strength `none`, so `decide()` at the `unattended` level parks it, with the brief and dissent encoded as untrusted data. | #624 |
| Two guide sessions work on one stage | The later one stops and re-derives the stage. | #621, #622 |
| Stage evidence is ambiguous, such as two open docs pull requests | The guide reports it and asks; it never guesses a stage. | #621, #622 |
| A seed-marked issue comes from a user without write permission, or a fork pull request uses `docs/<slug>` | Ignored and named in the report. | #621 |
| An interrogation session is lost | Only the seed issue survives; the guide reports the interrogation stage and restarts it. | #621, #622 |
| A budgeted file cannot fit its budget by cutting | The slice stops and asks the user with the measured size, the budget and the size needed (D20). | every slice |

## Decisions

Taken decisions are listed for veto in the pull request body and the review record. Asked decisions carry the user's answer.

### D1: Guide is a user-only conductor skill

Taken and listed for veto; set by the PRD. A main-session skill, not a workflow (workflows take no input mid-run) and not an overlord section (it would load in every session). ADR-0046.

### D2: Stage derived only from GitHub and git

Taken and listed for veto; set by the PRD. No progress state or pointer is stored. ADR-0046.

### D3: One deterministic readiness check shared by three callers

Taken and listed for veto; set by the PRD. Triage, the guide's handoff check and Lair admission share one check that judges no quality. Lair admission is ADR-0045 decision 10, as amended by #625. ADR-0046.

### D4: Track read from the native parent and labels

Taken and listed for veto; set by the PRD. The track is a native parent epic plus the human-confirmed type and effort labels. ADR-0046.

### D5: Per-initiative docs folder

Taken and listed for veto; set by the PRD. `docs/initiatives/<slug>/` holds the solution design and review record; the PRD stays at `docs/prds/<slug>.md`. ADR-0046.

### D6: Design review by fresh read-only planner passes

Taken and listed for veto; set by the PRD. Fresh cerebrate passes with `Memory context: none`, angles A and B in parallel, a confirming round, capped at three rounds. Exit is the pass rule of Review record front matter: zero open findings at any severity after dispositions and one round with no new findings, stricter than the PRD's zero open critical or high. ADR-0046.

### D7: Review record front matter with blob stamps

Taken and listed for veto; set by the PRD. The fixed front matter and its staleness rule. ADR-0046.

### D8: Ready label allowed with open blockers

Taken and listed for veto; set by the PRD. A passing slice is ready with open blocked-by links; `readiness:blocked` is kept for blocks with no issue link. Ready Issue keeps its no-open-blocked-by rule. ADR-0046.

### D9: Design-decision always-ask rule

Taken and listed for veto; set by the PRD. Review Calls gains the rule in the design-decision rule component. ADR-0046.

### D10: Delivered design frozen as history

Taken and listed for veto; set by the PRD. Close-out adds the delivered status and as-built deltas, then the file is never maintained. ADR-0046.

### D11: No dedicated different-model design pass in v1

Taken and listed for veto; set by the PRD. ADR-0046 records it as a deferred option. It fails hard to reverse, because the record already names each pass's reviewer, so a pass can be added later with no schema change.

### D12: Abathur council with two callers

Taken and listed for veto; set by the PRD. One decision service called from the design stages and, for planner questions, from standard-delivery (D30). The caller launches two to four members in all, Overseers plus at most one runner member, then Abathur. A council result needs at least two members with different `model` values from the caller's launch record. A runner member joins only when `HIVEMIND_LOCAL_REVIEWER` is a JSON argv list. ADR-0047.

### D13: Consult setting as data with a per-run cap

Taken and listed for veto; set by the PRD. The convening rule is the top-level `council_consult` object in the autonomy table, beside `rows` and never a row, per Consult setting: one value per level and an integer `per_run_cap`. Hard stops, `table_surface` asks and promotion-gate trips are never consulted. Nor are code-built briefs, `buildUndecidedAsk` sites, review calls and questions not marked `needs_user_fact` false (D30). ADR-0047.

### D14: Council member named Overseer

Taken and listed for veto. Synapse is now the runner agent, so the member takes a new name. ADR-0047.

### D15: Drone with exact file scope writes designs and records

Taken and listed for veto. Solution designs, review records and design-stage ADRs are written by a drone with exact file scope; `hivemind:plan-interrogation`'s writer exception is not extended. ADR-0046 (decision 11).

### D16: Process and council get separate ADRs

Taken and listed for veto. ADR-0046 records the process and ADR-0047 the council, so the council can be amended alone. ADR-0047 records it among its considered options.

### D17: Readiness check is a shared library

Taken and listed for veto. `plugin/skills/_shared/readiness-check.sh` is sourced by each caller's own script, so no skill calls another's script. ADR-0046 (decision 3).

### D18: Initial consult setting values

Taken and listed for veto. `consult` at `high` and `unattended`, `skip` at `balanced` and `low`, `per_run_cap` 2. At `balanced` and `low` the `planner_question` cell is `surface`, so `decide()` asks `table_surface` before any consult could convene, and `consult` there would have no effect. #624 sets the `unattended` value after #607 adds that level. Each standard-delivery consult costs at least five agent runs (two members, Abathur, two scans), and a switch adds a gate read and a new pass. No ADR: fails hard to reverse, because the values are table data.

### D19: Native blocked-by edges written at triage

Taken and listed for veto. Triage writes the edge for each Dependencies ref through `deps-add`, behind its confirm gate; `hivemind:prd-to-issues` keeps body refs. ADR-0046 (decision 4).

### D20: Prose budget with no pre-approved raise

Asked, answer Q1 B: no budget raise is pre-approved. A slice fits every budgeted file it edits by cutting, measured as that file's check measures. If it cannot, it stops and asks the user with the measured size, the budget and the size needed. The budgets the slices meet:

- `plugin/governance/decision-autonomy.md`, 12173 bytes (#616, #624).
- `plugin/governance/security-policy.md`, 24145 bytes (#618).
- `plugin/governance/definitions.md`, 7084 bytes (#619).
- `plugin/agents/synapse.md`, 1727 bytes (#618).
- `plugin/agents/overlord.md`, 39038 bytes (#622).
- `plugin/skills/triage-backlog/SKILL.md`, 11952 bytes (#620).
- `plugin/skills/prd-to-issues/SKILL.md`, 14566 bytes (#617).
- `plugin/governance/remediation-doctrine.md`, 19906 bytes (any slice that edits it).
- `plugin/workflows/standard-delivery.js`, 42100 characters of string and template literals (#618, #619, #624).
- `plugin/workflows/analysis-only.js`, 16050 characters of string and template literals (#618, #624).
- `plugin/workflows/pr-feedback-remediation.js`, 38200 characters of string and template literals (#618, #619, #624).

Each built script also stays under the 191000-character `MAX_BUILT_SCRIPT_LENGTH`, and `tools/build_workflows.mjs` enforces both limits. Each regeneration changes that script's `BUILD_ID`. The `needs_user_fact` rule lives in the description of `plugin/references/decision-brief-schema.json`, which has no budget entry of its own. `projectSchema` in `tools/build_workflows.mjs` drops every description from the built scripts, so the rule's text counts in no budget; the new fields' names and validation keywords count in each built script's literal budget. `plugin/agents/cerebrate.md` is not edited.

A new file takes a new budget entry, which needs no raise. This pull request edits nothing under `tests/policy/`. No ADR: fails hard to reverse, because a raise is one user-approved entry in `tests/policy/prose-budget-raises.json`.

### D21: Accepted-ADR amendments recorded in ADR-0047

Asked, answer Q2 A, narrowed by D30. ADR-0047's status line and decisions record three amendments of accepted ADRs:

- ADR-0026 decision 2: for design-stage decisions and planner questions in standard-delivery, a weak or absent recommendation with a clean gate goes to the council before defer-or-record, unless it needs a fact only the user holds.
- ADR-0036 decision 6: a weak planner question in standard-delivery goes to the council before it is taken. The consult runs ahead of an unchanged `decide()`, which stays the only place a decision is resolved.
- ADR-0045 decision 7: a planner question with no recommendation goes to the council before it parks, unless it needs a fact only the user holds.

D30 narrowed this wording within the approval. None of those three ADR files is edited. Taken and listed for veto, with a strong recommendation: ADR-0037 and ADR-0042 decision 9 are not amended, because `decide()` and `run-review.sh` keep their contracts (D22, D25). ADR-0037 keeps injection-suspect terminal, and a council re-plan enters planning through the facts step (invariant 3). ADR-0047.

### D22: Runner member through a sixth runner-gate script

Asked, answer Q3 A. The runner member runs only when `HIVEMIND_LOCAL_REVIEWER` is a JSON argv list, as a sixth script of the Synapse Runner Gate, per Runner member brief mode. Synapse's Write allow gains one fixed inputs file, `.hivemind/council-inputs-<token>.json`, the only way the brief reaches the script. #618 seeds `Edit(.hivemind/council-inputs-*.json)` through `plugin/skills/_shared/settings-merge.sh`, as the molt and pull request inputs-file rules are seeded (asked in design review round 2, answer Q7 A; D30). The script shares only the runner's kernel with `run-review.sh`. ADR-0042 decision 9 is not amended, because `run-review.sh` still runs every local review. ADR-0047.

### D23: Overlord may launch the council agents

Asked, answer Q4 A. #622 adds `hivemind:abathur` and `hivemind:overseer` to the overlord's Agent allowlist, and its Write grant is unchanged. A safety fixture under `tests/policy/` pins both agents' tools lists with no Bash, Write, Edit or agent-launch tool (#618). ADR-0047.

### D24: Review record authority is a human-reviewed merge

Asked, answer Q5 A. A review record is authoritative only through a human-reviewed merge, and only the design review's record step writes or re-stamps it. #623, with the #625 amendment, adds `docs/prds/`, `docs/initiatives/` and `docs/adr/` to the Lair's protected-path list, so a docs pull request never takes the auto tier. Recorded residual: with `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a bot approval with no human review of the design. ADR-0046 (decision 7 and Residuals).

### D25: Consult step with decide unchanged

Taken and listed for veto. The consult runs in `runPlanningPass` before `resolvePlanAsks`, only on planner questions, per Consult step. It reads each question and each composed brief through `resolveDecision` on a scratch resolution. A switch is listed as taken, and the run plans again from the facts step with the answer settled. A defect gives no council result. Any other composed brief goes through `resolvePlanAsks` unchanged. `decide()`, `resolveDecision`, `resolvePlanAsks`, the Ask Set, the list reasons, the check order and `resume_args` are unchanged. ADR-0047.

### D26: Caller composes the council brief

Taken and listed for veto. Abathur writes only an option id among the input's, a strength and a why, per Council brief contract. Member provenance comes from the caller's launch records. Options, option ids, problem, criticality and assumptions never change. Every gate is a producer read: the input's for the producer's own option, and a fresh gate read for another. There is no per-option gate, because Q6 A adds one brief field (D30). Its always-ask screen: it narrows the council's authority, since no gate is council-written, and widens none. ADR-0047.

### D27: Design-stage resolution is judgment checked by review

Taken and listed for veto. The design stages run no `decide()`. Take or ask is the conductor's judgment under the design-decision rule. The review record lists each taken decision with its always-ask screen, and the confirming pass checks every screen (#619). ADR-0046.

### D28: Record verified before ready and on every push

Taken and listed for veto: verify itself. The design review skill's verify checks the front matter, the stamps and the Findings table, per Review record body. A record with `verdict` pass and any open Findings row fails it. The guide runs it before `gh pr ready`. In a repository that wires it into CI, as `tools/validate.sh` does here with `docs/initiatives/`, `docs/prds/` and `docs/adr/` mapped to it, it runs on every push, and every other passing record whose design is not delivered gets stamp equality only. The guide does not pass verify as a validation command, because a plan's validation commands are the planner's reading of the project's documented commands.

Asked after design review round 3, answer Q10 A: record integrity is enforced in code. Verify prints `record-verify-failed: <record path>` per failing record. In CI every record the pull request adds or edits gets every check, ADR inclusion included, whether or not its design is delivered. A delivered design's slices fail `design_delivered`. The validate step reads verify's line in code and stops the run blocked, naming the record, before any `validation_remediation` decision, and every commit except a standard-delivery wave refuses a review record in code. A repository with no verify in CI keeps the guide's verify, the readiness check and the commit refusal. ADR-0046.

### D29: Write permission is the ready label's authority

Taken and listed for veto. The authorization for `readiness:ready` is write permission on its latest labeled event, with the title and body unedited since. The handoff check verifies it (#621), and the Lair keeps its check (#623). "Maintainer" names a role, and triage's confirm gate is not an authorization boundary. ADR-0046 and ADR-0045 decision 10, as amended by #625.

### D30: Council settles unmarked weak or unanswered questions

Asked in design review round 2.

Answer Q6 A. The council weighs every weak or unanswered planner question, and in the design stages every such design decision, that its producer does not mark as needing a fact only the user holds.

- A strong result on the producer's option with a clean gate is taken.
- A strong result on another option is taken only with a clean producer gate read of it, and the run plans again with it as a settled answer.
- A split is asked with each side's reasoning, or parks in an unattended run.
- Planners mark through one brief field, `needs_user_fact`. A question marked true, or left unmarked, is never convened, so it reaches the user as it would with no council.
- Code-built briefs, `buildUndecidedAsk` sites, review calls, hard stops, `table_surface` and gate trips are never consulted.

It narrows the three amendments approved under D21 to planner questions in standard-delivery and design-stage decisions, and adds none.

Answer Q7 A: #618 seeds `Edit(.hivemind/council-inputs-*.json)` through `plugin/skills/_shared/settings-merge.sh` (D22).

Answer Q8 A: the round-2 remediation plan was accepted with the Q6 answer. ADR-0047.

### D31: One-time fourth design review round

Asked after design review round 3, answer Q9 A. Every round-3 finding is fixed, then round 4 runs as one fresh confirming pass over both angles, a one-time exception the user approved for this initiative only. The three-round cap of Design review rounds stays the general rule, and the pass rule and the readiness check are unchanged. Round 4 is added under Rounds as the D31 confirming round and does not change `rounds`, as the review-fix confirming pass of Re-review and re-stamp does not (answer Q11 A). If round 4 raises any new critical or high finding, the council work (#618, #624) splits out into its own initiative. Any other new finding leaves no clean round, so the review stops and reaches the maintainer, as the cap does. The review record names the exception. No ADR: fails hard to reverse, because it is a one-time exception that changes no rule.

## Verification strategy

Each slice runs `bash tools/validate.sh --changed` at its validate state. Per slice:

- **#615:** contract tests over recorded issue fixtures for each track and each reason code. Cases include a document edited after stamping, an epic, a standalone issue that must be promoted, a slice with open blockers that passes, hostile link and heading text, a design link and record of different slugs, an unstamped PRD, a missing blocked-by edge, a truncated read, a missing document versus a `git` failure, a malformed commit id, and template order, duplicate heading and missing-section cases. More cases: `design_slug_mismatch`, `epic_marker_missing`, and Design blocks with zero or two `## Design` sections, Solution design lines or Review record lines, or no Heading line. A delivered design gives `design_delivered`. One case per pass-rule clause with its code: `verdict` fail, `clean_round` false and `rounds` 1 give `record_not_passed`; `rounds` 4 gives `record_rounds_exceeded`; an open medium gives `record_open`. A PRD stamp path passes the allowlist, and a stamp path outside every shape gives `record_malformed`. Test script `tools/test_readiness_check.sh`, fixtures in `tests/readiness-check/`, and a `tools/validate.sh` suite mapped from `plugin/skills/_shared/readiness-check.sh`, `tests/readiness-check/` and the script.
- **#616:** a fixture run on the Lair PRD yields every template section filled; skill authoring checks prove the skill names no sibling.
- **#617:** `tools/test_subissue_ops.sh` with `tests/prd-to-issues/` fixtures: the Design section, seed reuse with the marker line kept, and no duplicate on rerun. A policy fixture under `tests/policy/` pins the Design section and the Design-link carve-out of the "No file paths or code snippets" rule in `plugin/skills/prd-to-issues/SKILL.md`.
- **#618:** `tests/workflow-scripts/data.test.mjs` checks that `needs_user_fact` is an optional boolean, that every existing brief and fixture stays valid, and the council bounds: `members` 2 to 4 counting a runner member, `dissent` at most 4, `why` at most 200, `id`, `angle` and `model` at most 64. Composed-brief tests: a claimed model is ignored, and fewer than two distinct `model` values give no result. `tests/workflow-scripts/decide.test.mjs` stays green. `tools/test_synapse_gate.sh` with `tests/policy/safety-synapse-gate.json` covers `council-member.sh` and its inputs file. `tools/test_shared_libs.sh` covers remove-inputs kind `council`. `tools/test_seed_hive.sh` and `tests/policy/safety-navigator-transport-rules.json` cover the seeded rule. The safety fixture pins both agents' tools lists. `tools/test_run_review.sh` stays green. `tools/validate.sh` routes the kernel and `council-member.sh` to `test_run_review`, and `tools/test_run_review.sh` runs the brief-mode cases. CHECK 14 and CHECK 16 of `tools/policy_check.sh` pass with the `hivemind:council-member` Covered Navigators line. `council-member.sh` sources `containment.sh` in the direct form and reads its inputs file only after `hivemind_assert_inputs_contained`. The two widened residual bullets name the sixth script and the council inputs path.
- **#619:** stamping then verify passes. Each of these fails: an open high, a deferred high, a missing clean round, `rounds` of 1 or 4, an errored pass counted as a round, an unstamped added ADR, and a Findings table that disagrees with the open counts. A resume continues from the record's rounds, a confirming pass flags a taken decision that amends an accepted ADR, and the CI suite fails a stale passing record. More cases: an added ADR fails only the record the pull request edits; a verify failure stops the run with no fix round; a pass with an open medium fails; and CI runs verify on a `docs/prds/` or `docs/adr/` edit. Record-integrity cases: a fix round that reports a review record path is refused before any runner call with a terminal stop naming it, in standard-delivery and pr-feedback-remediation (`tests/workflow-scripts/standard-delivery.test.mjs`, `tests/workflow-scripts/pr-feedback-remediation.test.mjs`); a pr-feedback-remediation wave step whose files hold a record is refused the same way, a case variant of the path included, while a standard-delivery wave commits one; a failed validation whose failures hold a `record-verify-failed:` line stops blocked, naming the record, with no `validation_remediation` decision and no fix round, and a line whose path is outside the record shape is not read; CI verify fails a record the pull request edits whose design is delivered, skips a delivered design's unedited record, and fails an edited failing record whose stamps differ from the head; SD-25, SD-26, PFR-22 and PFR-23 name the stop and the refusal. A confirming pass flags a council-settled design decision whose veto row names no classification. Test script `tools/test_design_review.sh`, fixtures in `tests/design-review/`, and `tools/validate.sh` registrations for the design review suite and the record verify suite.
- **#620:** `tools/test_triage_ops.sh` with `tests/triage-backlog/`: the overlay, a post-apply re-check that drops a now-failing issue, edges written before readiness, a failing issue that never enters the apply set as ready with its reasons shown, a passing slice with open blockers proposed ready, and the existing cases. The overlay is a `--overlay` JSON argument checked as `--targets` is, and CHECK 14 and CHECK 16 pass with no Edit entry in triage-backlog.
- **#621:** recorded fixtures for every stage give the expected stage and next action. Cases: `**Status:** delivered` read before staleness, seed identity, fork and non-write evidence ignored and named, the latest-label check, and two open docs pull requests reported as ambiguous. Handoff mode passes only when every slice passes. A malformed marker slug is ignored and named with no `git` or `gh` call. Test script `tools/test_stage_derivation.sh`, fixtures in `tests/stage-derivation/`, and a `tools/validate.sh` suite.
- **#622:** the skill is user-only. A live smoke takes a throwaway idea to ready slices: it creates the docs branch, commits the stage-2 and stage-3 outputs so the tree is clean, and runs verify before `gh pr ready`. Every docs-branch run launches with `draft` true, and the pull request stays a draft with no Closes line across reused runs, leaving draft only after verify. A design decision marked `needs_user_fact` true is asked with no council. A fresh session resumes at the derived stage. The guide invokes `hivemind:council-member` for a runner member and carries no Edit entry, so CHECK 14 and CHECK 16 pass.
- **#623:** a tick contract test where an epic and a stale design are not claimed and are named in the queue report with encoded reason codes, and a docs pull request never takes the auto tier.
- **#624:** `tests/workflow-scripts/` engine tests:
  - only planner questions are consulted;
  - a question marked `needs_user_fact` true, and one with the field absent, is never convened and resolves as it came; an unmarked weak or `none` question is convened;
  - the validation fix limit's `buildUndecidedAsk` never consults and never throws; `review_question` and `high_severity_rejection` calls and a code-built brief are never consulted;
  - a strong result on the planner's option is taken and shown in the pull request decisions;
  - on a switch the gate comes from a fresh gate-read call whose prompt holds only the planner question and the option id, never from Abathur's output;
  - a clean read lists the composed brief as taken, and the pass returns a replan; the next pass's plan prompt carries the council answer as a settled entry; the plan that runs is that pass's result and never the first; the journaled take names the council's option;
  - a switch whose gate read trips asks with the gate reason and parks unattended; a failed gate read asks `no_recommendation`;
  - a composed brief `decide()` refuses as a defect gives no council result and never reaches `pauseDelivery`;
  - a split asks `no_recommendation` with the dissent, and an unattended split parks;
  - an injection-suspect opinion or Abathur output ends the run with the terminal stop, as SD-06, and the first result never stands;
  - the cap bounds councils and re-plans;
  - replay rebuilds the count and the council answers with `resume_args` `{answers, build}`, and `run.answerLog` and `resume_args` never hold a council answer;
  - with no council answer every prompt is byte for byte as before;
  - the projection includes `council_consult`;
  - analysis-only and pr-feedback-remediation never consult, and their built scripts bundle no `council.js` function or council prompt;
  - a user-settled composed ask whose raw question is raised again in the same run resolves as answered, with no new council and no take;
  - a raw question raised again in the same pass reuses its composed brief with no new council call, rebuilt on replay;
  - a failed, timed-out or unusable scan gives no council result, resolves the question as it came and counts toward the cap;
  - no planner question convenes at `balanced`;
  - after a composed ask is answered, the revise prompt holds each council why only encoded, at most 200 characters, and only inside that question in the answers block;
  - SD-29, SD-82, `tests/workflow-scripts/decide.test.mjs`, `tests/workflow-scripts/ask-set.test.mjs` and `tests/policy/safety-ask-set.json` are unchanged and green.

  One live delivery run resolves a weak planner question through the council.

### Prose budget check

Every slice that edits a file in D20's list measures it as its check measures: bytes with CR stripped for CHECK 18 of `tools/policy_check.sh` against `tests/policy/prose-byte-budget.json`. For `plugin/workflows/standard-delivery.js`, `plugin/workflows/analysis-only.js` and `plugin/workflows/pr-feedback-remediation.js`, `tools/build_workflows.mjs` measures the characters of string and template literals with `countProseCharacters` against the script's entry in the same budget file, and the script's length against `MAX_BUILT_SCRIPT_LENGTH`. It fits by cutting per P25. If it cannot, it stops and asks the user, showing the measured size, the budget and the size needed. A prose budget raise lands only with a user-approved entry in `tests/policy/prose-budget-raises.json`. Governance citations pass `tests/workflow-scripts/governance-section-refs.test.mjs`.

## Seam order

Slices start in this order; a slice waits on its blockers.

Row rule: each row names, by full heading text, the component, contract, state and lifecycle sections its slice builds; Trust boundaries when a trust bullet names the slice; Failure modes, since the budget failure row names every slice; Prose budget check when the slice edits a file in D20's list; and the decisions it carries. Existing-path coverage and Verification strategy name every slice, so no row lists them.

| Slice | Blocked by | Headings it implements |
|---|---|---|
| #615 Readiness check | none | Readiness check; Track fact; Readiness check output contract; Document parsing rules; Standalone spec block format; Slice design section format; Seed issue marker; Solution design template; Review record front matter; Trust boundaries; Failure modes; D3: One deterministic readiness check shared by three callers; D4: Track read from the native parent and labels; D17: Readiness check is a shared library |
| #618 Abathur council | none | Abathur council; Council brief contract; Runner member brief mode; Trust boundaries; Failure modes; Prose budget check; D12: Abathur council with two callers; D14: Council member named Overseer; D20: Prose budget with no pre-approved raise; D22: Runner member through a sixth runner-gate script; D23: Overlord may launch the council agents; D26: Caller composes the council brief; D30: Council settles unmarked weak or unanswered questions |
| #616 Solution design skill and template | #618 | Solution design skill; Initiative folder; Design-decision rule; Solution design template; Failure modes; Prose budget check; D5: Per-initiative docs folder; D9: Design-decision always-ask rule; D15: Drone with exact file scope writes designs and records; D20: Prose budget with no pre-approved raise; D27: Design-stage resolution is judgment checked by review; D30: Council settles unmarked weak or unanswered questions |
| #617 Slice design links and seed epic | none | Slice design section; Slice design section format; Seed issue marker; Failure modes; Prose budget check; D20: Prose budget with no pre-approved raise |
| #619 Design review and record | #615 | Design review; Design review rounds; Re-review and re-stamp; Review record front matter; Review record body; Document parsing rules; State and ownership; Trust boundaries; Failure modes; Prose budget check; D6: Design review by fresh read-only planner passes; D7: Review record front matter with blob stamps; D11: No dedicated different-model design pass in v1; D20: Prose budget with no pre-approved raise; D24: Review record authority is a human-reviewed merge; D27: Design-stage resolution is judgment checked by review; D28: Record verified before ready and on every push |
| #620 Triage readiness gate | #615 | Triage readiness gate; Readiness check output contract; Trust boundaries; Failure modes; Prose budget check; D8: Ready label allowed with open blockers; D19: Native blocked-by edges written at triage; D20: Prose budget with no pre-approved raise; D29: Write permission is the ready label's authority |
| #621 Stage derivation and handoff check | #615, #619 | Stage derivation and handoff check; Initiative stages; Readiness check output contract; Seed issue marker; Trust boundaries; Failure modes; D2: Stage derived only from GitHub and git; D29: Write permission is the ready label's authority |
| #622 Guided initiative command | #616, #617, #618, #619, #620, #621 | Guide skill; Initiative stages; Re-review and re-stamp; Close-out; Standalone spec block format; Seed issue marker; Abathur council; Council brief contract; Consult setting; Design-decision rule; Trust boundaries; Failure modes; Prose budget check; D1: Guide is a user-only conductor skill; D10: Delivered design frozen as history; D20: Prose budget with no pre-approved raise; D23: Overlord may launch the council agents; D27: Design-stage resolution is judgment checked by review; D30: Council settles unmarked weak or unanswered questions |
| #623 Lair admission | #615, #608, #625 | Lair admission; Readiness check output contract; Trust boundaries; Failure modes; D24: Review record authority is a human-reviewed merge; D29: Write permission is the ready label's authority |
| #624 Mid-delivery consult | #618, #607 | Mid-delivery consult; Abathur council; Council brief contract; Runner member brief mode; Consult setting; Consult step; State and ownership; Trust boundaries; Failure modes; Prose budget check; D13: Consult setting as data with a per-run cap; D18: Initial consult setting values; D20: Prose budget with no pre-approved raise; D21: Accepted-ADR amendments recorded in ADR-0047; D22: Runner member through a sixth runner-gate script; D25: Consult step with decide unchanged; D26: Caller composes the council brief; D30: Council settles unmarked weak or unanswered questions |

## Open questions

None

## Amendments

None yet.
