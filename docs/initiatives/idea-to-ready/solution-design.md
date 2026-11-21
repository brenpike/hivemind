# Solution design: Idea to Ready

This is the HOW for [docs/prds/idea-to-ready.md](../../prds/idea-to-ready.md), as merged in #626. It does not reopen the PRD. Epic #614 tracks the slices #615 to #624; #627 is this second by-hand pilot. ADRs: [ADR-0046](../../adr/0046-idea-to-ready-process.md) (the idea-to-ready process) and [ADR-0047](../../adr/0047-abathur-council.md) (the Abathur council). The design review record is [review-record.md](review-record.md) in this folder.

## Context and code truth

Checked against main at commit `49787cc9`. Each fact below names what exists today; the components say what changes.

- **Pipeline skills exist.** `hivemind:plan-interrogation`, `hivemind:plan-to-prd`, `hivemind:prd-to-issues` and `hivemind:create-handoff` are all implemented. [CONTEXT.md](../../../CONTEXT.md) still calls the last three "planned skill — not yet implemented"; this pull request's glossary edits fix that.
- **plan-interrogation** holds `Read`, `Write` and `Edit`, and is the named writer of `CONTEXT.md` terms and ADRs. It offers an ADR only when a decision is hard to reverse, surprising without context and a real trade-off. Those three are the ADR conditions this design cites.
- **plan-to-prd** writes a nine-section, WHAT-only PRD to `docs/prds/<slug>.md`. One slug names the plan, the handoff, the PRD and the epic.
- **prd-to-issues** is a leaf skill that names no sibling ([ADR-0013](../../adr/0013-decoupled-leaf-pipeline-skills.md)). Its issue body has exactly four sections: Initiative, What to build, Acceptance Criteria, Dependencies. Blockers are only `#123` refs in the Dependencies section; it writes no native blocked-by edge. `subissue-ops.sh ensure-parent --existing-number <n>` already resolves a known issue as the epic, and `find-by-title` makes a rerun create no duplicates.
- **create-handoff** writes `.hivemind/handoffs/<slug>.md`, which is gitignored. It is session state on one machine and can never be stage evidence.
- **triage-backlog** is user-only (`disable-model-invocation: true`), so no model, the guide included, can start it. It rates seven families (readiness, type, effort, moscow, priority, risk, difficulty). `readiness:ready` is a rubric judgment ("plan clear, no open questions") with no check behind it, and `readiness:blocked` means "would be ready but a dependency blocks it". `triage-ops.sh` has five subcommands: `ensure-labels`, `list-issues`, `apply-labels`, `deps-read`, `deps-add`. `list-issues` returns number, title, labels, body and node id, with no parent or sub-issue fields. `deps-add` writes native blocked-by edges behind the confirm gate.
- **decision-autonomy.md, Review Calls** says who decides a reviewer's question. A call is taken when the recommended option is reversible and not architectural (Promotion Gate clauses 1 and 2). It is asked when irreversible, architectural, at strength none, or when the table cell is `surface`. There is no rule for design decisions.
- **Prose budgets.** Measured as CHECK 18 measures (bytes with CR stripped): `plugin/governance/decision-autonomy.md` is 12165 bytes of a 12173 budget (8 bytes free); `plugin/governance/remediation-doctrine.md` is 19901 of 19906 (5 bytes free).
- **decision-autonomy-table.json** is version 1, levels `high`, `balanced`, `low` (default `high`), 17 row kinds with cells `auto` or `surface`, and 6 hard stops. It has no consult row.
- **decide.js** returns only `ask` or `take`. Its check order is hard_stop, malformed_brief, recommendation_not_an_option, unknown_kind, table_surface, bad_cell, gate_irreversible, gate_architectural, gate_safety, no_recommendation. A weak recommendation is taken ([ADR-0036](../../adr/0036-analysis-only-first-workflow-on-script-engine.md) decision 6). There is no park; it arrives with Lair unattended mode (#607).
- **decision-brief-schema.json** carries `recommendation.strength` of `strong`, `weak` or `none`, and has no dissent or member provenance fields.
- **standard-delivery** resolves every question through `decide()` and pauses through `pauseDelivery`; it has no cumulative pause cap.
- **The synapse agent** is the haiku runner that relays one committed script. The name Synapse is taken. The earlier council epic #440 (closed) used it for a bioform.
- **The tool-neutral review runner** `plugin/skills/adaptation-cycle/scripts/run-review.sh` reads `HIVEMIND_LOCAL_REVIEWER` (the `codex-plugin` preset or a JSON argv list run with no shell). Its prompt is fixed: an adversarial review of a branch diff against `--base`, checked against the findings schema. It cannot carry a decision brief today.
- **cerebrate** is read-only by its `tools:` list (Read, Glob, Grep, LSP, web and claude-mem search). A delegation line `Memory context:` stops its memory search.
- **The overlord's Write grant** covers only fixed-prefix inputs files under `.hivemind/`.
- **ADR-0045 decision 10** sets Lair admission: latest ready label from a user with write permission, title and body unedited since, no open blocked-by dependency. This design cites it only as "ADR-0045 decision 10, as amended by #625": #625 adds the epic exclusion and the readiness check at claim time. This design never stamps ADR-0045.
- **Ready Issue** in `CONTEXT.md` requires no open blocked-by dependency. That rule stays: a slice may carry `readiness:ready` with open blockers, but it is a Ready Issue, and claimable, only once they close.
- **No folder** `docs/initiatives/` exists on main before this pull request.

## Components

### Guide skill

A user-only conductor skill (`disable-model-invocation: true`) that runs in the main session. Given nothing, it lists in-flight initiatives with their derived stage. Given an idea, it starts one. Given an initiative, it reports the stage, the evidence found and the next action, then starts that stage without asking to continue. It is written as stage must-haves with judgment, not a numbered state machine. It invokes the leaf skills by intent, and they stay uncoupled. It never applies `readiness:ready`: at the triage stage it tells the maintainer to run `/hivemind:triage-backlog`, which is user-only. Docs writing happens in a standard-delivery run on the docs branch, whose steps give a drone exact file scope. The design review runs from the main session between those runs. A standalone idea ends with an issue carrying the spec block, ready for triage.

### Readiness check

One deterministic shell library, `plugin/skills/_shared/readiness-check.sh`, sourced by each caller's own script entry: a `readiness` subcommand of `triage-ops.sh`, the guide's script and the Lair controller. It reads issues through `gh` and documents through `git show <trunk-ref>:<path>` and `git rev-parse <trunk-ref>:<path>`, where the caller passes the trunk ref. The Lair passes the fetched trunk commit it spawns the strain from. It checks structure, existence, versions and labels, never quality. It writes nothing.

### Track fact

The track is read, never judged. An issue with a native parent is an initiative slice; any other issue is standalone. The parent must carry `type:epic`, else the slice fails `parent_not_epic`. A standalone issue whose `type:` label is not `bug`, `chore`, `documentation`, `refactor` or `enhancement`, or whose `effort:` label is `l` or `xl`, fails with a promote reason. The type and effort labels are human-confirmed, because triage applies them only after its confirm gate.

### Initiative folder

`docs/initiatives/<slug>/` holds `solution-design.md` and `review-record.md`, with the same slug as `docs/prds/<slug>.md`. The PRD stays in `docs/prds/`. ADRs stay global and numbered in `docs/adr/`.

### Solution design skill

A leaf skill that turns a merged-or-branch PRD into `docs/initiatives/<slug>/solution-design.md` with every section of the solution design template. It applies the design-decision rule and lists each decision with its ADR or the ADR condition it fails. It names no sibling skill. The file itself is written by a drone with exact file scope.

### Design review

A main-session skill that runs fresh read-only cerebrate analysis passes with `Memory context: none`. Round 1 is angles A and B in parallel; a confirming round follows. It records every finding with exactly one disposition and writes, through a drone, the review record. It exits per the design review rounds lifecycle.

### Slice design section

`hivemind:prd-to-issues` adds a fifth body section, `## Design`, to each slice, and reuses the initiative's seed issue as the epic through `ensure-parent --existing-number`. A rerun creates no duplicates, through the existing `find-by-title` preflight.

### Triage readiness gate

Triage runs the readiness check on every issue it would propose as `readiness:ready`. A failing issue never enters the apply set as ready, and its reason codes show in the Notes column. A slice that passes is proposed ready even with open blocked-by links. `readiness:blocked` is kept only for a block with no issue link. Triage writes the native blocked-by edge for each `#123` ref in a slice's Dependencies section through `deps-add`.

### Stage derivation and handoff check

A pure function from GitHub and git to a stage and next action, run by the guide's script. Its evidence: the seed issue or epic, the docs branch and its pull request, then trunk, the review record, sub-issues, labels and readiness results. Handoff mode passes only when every condition of the PRD's handoff check holds, and reports each slice as claimable now or blocked, with the reason.

### Lair admission

At claim time the Lair controller (#608) runs the readiness check against the trunk commit it will spawn from. It never claims an epic or a failing issue. A failing issue stays unclaimed, with no new label, and is named in the tick's queue report with its reason codes. This is ADR-0045 decision 10, as amended by #625; slice #623 implements it.

### Abathur council

Two read-only agents: `abathur` and the council member `overseer` (#618). The caller launches two to four Overseer members, each with an angle and a model, then Abathur. Each member returns one opinion. Abathur weighs the opinions and returns only a recommendation. The caller composes the council's brief, per the council brief contract. Abathur never picks the members it judges.

In the main session the conductor launches them. #622 adds `hivemind:abathur` and `hivemind:overseer` to the overlord's Agent allowlist; its Write grant is unchanged (D23). In standard-delivery the workflow script launches the Claude members, and synapse runs the runner member's committed script (D22). Every member and Abathur delegation carries `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Delegation Data-Boundary Constraint).

### Mid-delivery consult

Inside standard-delivery, the consult step runs before the script acts on a `decide()` result. `decide()` is unchanged. It gains no third action and no `consults_used` input. There is no `council_split` ask reason and no `council` list reason. A strong council result with a clean gate is taken, journaled and shown in the pull request decisions. A split comes back with strength `none`, so it asks `no_recommendation`. In an interactive run the ask carries the dissent. In an unattended run it parks (#607).

### Design-decision rule

An extension of Review Calls in `plugin/governance/decision-autonomy.md` for the design stages. A decision is taken when its recommendation is strong, it is inside the PRD's scope and its gate is clean.

A design decision's gate reads Promotion Gate clause 1, irreversible, and clause 3, safety-relevant. The always-ask list replaces clause 2. So a decision inside the PRD's scope that amends no accepted ADR does not trip it.

These are always asked: a change to the PRD's scope or acceptance criteria, an amendment of an accepted ADR, a trust-boundary, credential or merge-path change, and anything irreversible. A weak or absent recommendation goes to the council first, and a split is asked.

The design stages run no `decide()`. Take or ask is the conductor's judgment, checked by review. The review record lists each taken decision with its always-ask screen: an answer to each of the four always-ask items. The confirming pass checks every screen. A taken decision that should have been asked is a finding (#619).

## State and ownership

No progress state is stored anywhere. Every row below is ground truth in GitHub or git.

| State | Home | Writer | Readers |
|---|---|---|---|
| Seed issue, later the epic | GitHub issue | the guide at capture; `hivemind:prd-to-issues` reuses it | stage derivation, readiness check |
| Interrogated plan | live session, `.hivemind/plans/<slug>.md` | `hivemind:plan-interrogation`, `hivemind:create-handoff` | the same session only |
| PRD | `docs/prds/<slug>.md` | `hivemind:plan-to-prd` | design stages, readiness check |
| Solution design | `docs/initiatives/<slug>/solution-design.md` | a drone with exact file scope | design review, slices, readiness check |
| ADRs | `docs/adr/NNNN-<title>.md` | a drone with exact file scope at the design stage; `hivemind:plan-interrogation` during interrogation | readiness check |
| Review record | `docs/initiatives/<slug>/review-record.md` | a drone with exact file scope | readiness check, stage derivation |
| Slices and blocked-by edges | GitHub sub-issues and issue dependencies | `hivemind:prd-to-issues` (sub-issues); triage `deps-add` (edges) | readiness check, handoff check, the Lair |
| Rating labels | GitHub labels | triage only, behind its confirm gate | readiness check |
| `readiness:ready` | GitHub label | the maintainer, through triage | the Lair, under ADR-0045 decision 10 as amended by #625 |
| Consult row and cap | `plugin/references/decision-autonomy-table.json` | a delivery slice, by pull request | `decide()`, the conductor |
| Consults used in a run | standard-delivery run state, carried in `resume_args` | the workflow script | `decide()` |

## Contracts and seams

### Readiness check output contract

One JSON line per issue: `{"issue": <number>, "track": "standalone" | "slice", "result": "pass" | "fail", "reasons": [<code>, ...]}`. `reasons` is empty only on a pass. Exit 0 means every issue was evaluated. A `gh` or `git` failure, or a truncated read, exits non-zero with a diagnostic, and no caller treats it as a pass.

Reason codes, a closed set:

- Every issue: `issue_closed`, `rating_missing:<family>`, `is_epic`, `is_idea`, `has_subissues`, `no_acceptance_criteria`.
- Standalone: `spec_problem_missing`, `spec_evidence_missing`, `spec_scope_missing`, `open_questions_not_none`, `promote_type`, `promote_effort`.
- Slice: `epic_closed`, `parent_not_epic`, `design_section_missing`, `prd_missing`, `design_missing`, `record_missing`, `design_section_unfilled:<heading>`, `design_open_questions`, `adr_missing:<path>`, `adr_not_accepted:<path>`, `record_malformed`, `record_not_passed`, `record_open_blocking`, `record_rounds_exceeded`, `record_stale:<path>`, `heading_unmatched:<text>`, `heading_ambiguous:<text>`.

An ADR is accepted when its `**Status:**` line's value starts with `accepted`. A design section is filled when its body has non-blank text other than a heading.

### Standalone spec block format

A standalone issue body carries these sections: `## Problem`, `## Evidence`, `## Acceptance Criteria`, `## Scope boundary`, `## Open questions`. Each must be non-empty, Acceptance Criteria must hold at least one `- [ ]` or `- [x]` item, and Open questions must read exactly `None`.

### Slice design section format

A slice body's `## Design` section holds one item per line:

- `- Solution design: [<path>](<link>)`
- `- Heading: <exact heading text>`, one line per heading
- `- ADR: [<path>](<link>)`, one line per ADR
- `- Review record: [<path>](<link>)`

The check reads the repository path from each link, either a bare path or the part after `/blob/<trunk>/`. Each heading must match exactly one heading of the solution design, at any level, as literal text without `#` marks.

### Solution design template

These `## ` sections, in this order: Context and code truth; Components; State and ownership; Contracts and seams; Trust boundaries; Lifecycle; Existing-path coverage; Failure modes; Decisions; Verification strategy; Seam order; Open questions; Amendments. Every heading in the file is unique. Open questions reads exactly `None`. Amendments may read `None yet.`. After close-out the file gains `**Status:** delivered` under its title and an `## As-built deltas` section.

### Review record front matter

The record starts with this front matter, keys in this order, and the check parses only this fixed shape:

```yaml
---
stamps:
  - path: docs/prds/<slug>.md
    blob: <40-hex blob id>
  - path: docs/initiatives/<slug>/solution-design.md
    blob: <40-hex blob id>
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

Each `blob` is the output of `git rev-parse HEAD:<path>` on the docs branch when the record is written. Stamps must include the PRD and the solution design and may add ADRs. The record passes when `verdict` is `pass`, `critical` and `high` are 0, `clean_round` is `true` and `rounds` is 1 to 3.

Staleness rule: the record is stale when any stamped path's `git rev-parse <trunk-ref>:<path>` differs from its blob, or the path is missing. A blob id is a content hash, so the merge method does not matter, and any edit to a stamped file makes the record stale until a review of the change re-stamps it.

The record body, read by people only: reviewed documents, each round's passes with reviewer agent, angle and model, every finding with its severity, angle, summary and one disposition, the decisions taken (listed for veto) and the decisions asked with the user's answer.

### Council brief contract

Input: a decision brief valid against `plugin/references/decision-brief-schema.json`. #618 adds an optional per-option `gate` object with `irreversible`, `architectural` and `safety`. It is the producer's read of that option. Existing briefs stay valid.

Member output: each member returns `{option_id, strength, why}`, with strength `strong`, `weak` or `none`.

Abathur output: Abathur gets the input brief and the opinions as data. It returns only `{option_id, strength, why}`, with strength `strong` or `none`. A split is `none`. A `weak` strength, an `option_id` not among the input's option ids, or any other shape means no council result.

Composed output: the caller composes the output brief. It is the input brief unchanged except `recommendation`, which is Abathur's, plus the optional `council` object:

- `members` has one entry per member that returned a valid opinion. `id`, `angle` and `model` come from the caller's own launch record. `option_id`, `strength` and `why` come from that member's own output.
- `dissent` has one entry per member whose `option_id` differs from the council's: `member_id`, `option_id`, `why`.

No text a member or Abathur writes reaches the gate, options, problem or criticality. A claimed model is ignored. When the council's `option_id` differs from the input's recommended option, the caller sets the composed `gate` from that option's own `gate`. When that option carries none, the caller sets strength `none`, so the call asks.

Schema bounds: `members` holds 2 to 4 items and `dissent` at most 3. Each `why` has maxLength 200 and is described "Written for the user". `id`, `angle` and `model` have maxLength 64. The engine shows only bounded fields written for the user; #618 extends `tests/workflow-scripts/data.test.mjs` for them. A result counts only with at least two members whose `model` values differ.

### Runner member brief mode

The runner member runs only when `HIVEMIND_LOCAL_REVIEWER` is a JSON argv list. Unset or the `codex-plugin` preset means no runner member. The council then needs two Claude members on two Claude models. The runner member's `model` value is `runner:` plus the basename of argv[0]. That names the tool, never a model (ADR-0042 decision 7).

It is a sixth script of the Synapse Runner Gate. #618 edits `plugin/hooks/synapse-gate.sh`, `plugin/governance/security-policy.md` (Synapse Runner Gate), `tests/policy/safety-synapse-gate.json` and `tools/test_synapse_gate.sh`. Synapse's Write allow gains one fixed inputs file, `.hivemind/council-inputs-<token>.json`. It is the only way the brief reaches the script, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern). The engine reaches the script through synapse. The main-session guide reaches it through its own skill grant.

Per [docs/engineering-principles.md](../../engineering-principles.md) P9 it shares only the runner's kernel with `run-review.sh`. The kernel is:

- the reviewer-setting read and argv check;
- the no-shell argv run under `timeout -k 5 <deadline>`;
- the before/after work-tree check, where any change blocks and discards the opinion;
- the reply JSON extraction.

The kernel moves to `plugin/skills/_shared/`. Review mode's behavior and output do not change, and `tools/test_run_review.sh` stays green. `run-review.sh` still runs every local review (ADR-0042 decision 9).

### Consult setting

A top-level object `council_consult` in `plugin/references/decision-autonomy-table.json`, beside `rows` and never a row. It holds one value per level, `consult` or `skip`, and an integer `per_run_cap`. `rows` and `hard_stops` are unchanged, so no call site can pass it as a kind.

#624 extends `projectAutonomyTable` in `tools/build_workflows.mjs` to project it, and updates `tests/workflow-scripts/build.test.mjs` and `tests/workflow-scripts/data.test.mjs`. #624 sets the `unattended` value and lands after #607 adds that level (ADR-0045 decision 6). In the design stages the conductor reads the value at the table's `default_level`. It allows at most `per_run_cap` consults per guide invocation (#622).

### Consult step

Only standard-delivery runs the step. analysis-only and pr-feedback-remediation carry no council settings, so their call sites resolve through `decide()` alone. The `decide()` call sites in `plugin/workflow-src/lib/` run the step only when the run carries council settings (#624).

1. Call `decide()` on the input brief with the call site's kind, level and listed.
2. Convene the council only when all of these hold:
   - the result is a take of a `weak` recommendation or an ask with reason `no_recommendation`;
   - the kind is not `plan_acceptance`, `remediation_plan_acceptance` or `gate_rerun`, the routine kinds the record shows only when listed;
   - `council_consult` at the run's level is `consult`;
   - the run's consult count is below `per_run_cap`.

   Otherwise the first result stands. So a hard stop, a malformed brief, `table_surface`, `bad_cell` and every gate trip never reach the council.
3. The count rises by one per convened council, whether or not it returns a result.
4. With no council result, the first result stands.
5. With a council result, call `decide()` on the composed brief with the same kind, level and listed. That result stands.
6. `askReasons()`, `listReasons()`, the check order and `pauseDelivery`'s guard are unchanged. So ADR-0037's closed Ask Set is not amended.
7. The count is a script-local counter. It starts at 0 on each launch and is rebuilt as a replay passes the same steps. `resume_args` stays `{answers, build}` (`plugin/workflow-src/lib/args.js`).

## Trust boundaries

- **External content stays data.** Issue bodies, PRD and design text, review findings, member opinions and Abathur's brief are data per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (External Content Boundary). The readiness check parses fixed shapes and literal heading text and never runs or evaluates content.
- **The ready label stays the maintainer's.** Only the maintainer applies `readiness:ready`, through triage's confirm gate. The guide and the Lair never apply it. The Lair keeps its write-permission and unedited-since checks of ADR-0045 decision 10, as amended by #625.
- **Reviewers are fresh and read-only.** Review passes run on cerebrate, whose tool list holds no Bash, Write or Edit. `Memory context: none` keeps the writing session's memory from steering a reviewer.
- **Stamps bind the reviewed content.** The record ships in the same pull request as the design, so it passes the same local review and bot review. Trunk never holds an unreviewed design, and any later edit is detected by blob id.
- **The council cannot widen authority.** `decide()` resolves a caller-composed brief. Abathur writes only a recommendation. Member provenance comes from the caller's launch records. A switched option is gated by its own producer-written gate, or the call asks. The `abathur` and `overseer` tools lists hold no Bash, Write, Edit or agent-launch tool, pinned by a safety fixture under `tests/policy/` (#618). The runner member runs under the kernel's no-shell argv run and before/after check. Member opinions and Abathur's output are injection-scanned. A suspect one ends the consult with no council result and stops at the `injection_suspect` hard stop. That stop is asked in an interactive run and is an approval park in an unattended run (ADR-0045 decision 7) (#618, #624).
- **Unattended runs never decide a split.** A split or always-ask call parks with the brief and dissent. Its text is encoded as untrusted data in the park record (#624, with #607).
- **No new credential and no merge-path change.** Everything runs under the executing user's credentials, and `merge-approved.sh` is untouched. The two trust-boundary changes, a sixth runner-gate script and the overlord's two new agents, were asked (D22, D23).

## Lifecycle

### Initiative stages

1. **Capture.** The guide creates the seed issue. Its body links `docs/prds/<slug>.md`, which may not resolve until the docs merge.
2. **Interrogation.** `hivemind:plan-interrogation` in one session. This is the one single-machine window: its plan lives in the session or `.hivemind/`, so another machine sees only the seed issue.
3. **PRD.** `hivemind:plan-to-prd` writes the PRD on the docs branch `docs/<slug>` or `docs/<slug>-<suffix>`.
4. **Solution design and ADRs.** Written on the docs branch by drones with exact file scope.
5. **Design review.** Per the design review rounds below; the record is written on the docs branch.
6. **Docs pull request.** It opens as a draft with no closing keyword, leaves draft only when the record passes and its stamps equal the documents at the pull request head, and merges to trunk.
7. **Slicing.** `hivemind:prd-to-issues` reuses the seed issue as the epic and adds each slice's design section.
8. **Triage.** The maintainer runs triage; it gates `readiness:ready` on the readiness check and writes native blocked-by edges.
9. **Handoff check.** It passes only when every slice passes, and names each slice as claimable now or blocked.

Stage derivation picks the latest stage whose evidence exists. Evidence it cannot resolve to one answer, such as two seed issues for one slug or two open docs pull requests, is reported as ambiguous and asked, never guessed.

### Design review rounds

Round 1 is two parallel fresh passes: angle A (code truth, governance and ADR conflicts, existing-path coverage) and angle B (failure modes, trust and injection, testability). Findings are fixed on the docs branch. Each later round is one fresh confirming pass over both angles. The review exits only with zero open critical or high findings and one round with no new findings. A review that has not converged after round 3 stops and reaches the maintainer as a signal to split the initiative. Every finding gets exactly one disposition: `fixed`, `rejected` with its reason, `deferred` or `recorded`. Critical and high findings are only `fixed` or `rejected`. Mediums follow `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Defer-with-Scope, Recorded Residual).

### Close-out

When every slice is done, the solution design gains `**Status:** delivered` and an `## As-built deltas` section in one docs pull request, and is never maintained afterward. The truth then lives in code, ADRs, the glossary and governance.

## Existing-path coverage

| Existing path | Effect | Slice |
|---|---|---|
| `plugin/skills/triage-backlog/SKILL.md`, `scripts/triage-ops.sh` | Gains the readiness gate, a `readiness` subcommand and reason codes in Notes; `readiness:blocked` narrows to blocks with no issue link; `deps-add` writes native edges from Dependencies refs. The confirm gate, `triage:locked` and the per-family mutex are unchanged. | #615, #620 |
| `plugin/skills/plan-interrogation/SKILL.md` | Unchanged. The guide invokes it; it stays the glossary and ADR writer during interrogation only. | none |
| `plugin/skills/plan-to-prd/SKILL.md` | Unchanged. The PRD stays at `docs/prds/<slug>.md`. | none |
| `plugin/skills/prd-to-issues/SKILL.md`, `scripts/subissue-ops.sh` | The body gains `## Design` as a fifth section; the seed issue is passed as `--existing-number`. Idempotency and the four existing sections are unchanged. | #617 |
| `plugin/skills/create-handoff/SKILL.md` | Unchanged. Its handoff is never stage evidence. | none |
| `plugin/governance/decision-autonomy.md`, Review Calls and Tier A | Gains the design-decision rule, the consult step and `council_split` in the engine's ask line. Each edit fits the byte budget by cutting. | #616, #624 |
| `plugin/governance/remediation-doctrine.md` | No edit planned; the design review skill cites Defer-with-Scope and Recorded Residual. A slice that must edit it follows the same budget rule. | none |
| `plugin/references/decision-autonomy-table.json` | Gains the `council_consult` row; every existing row and hard stop is unchanged. | #624 |
| `plugin/references/decision-brief-schema.json` | Gains the optional `council` object; existing briefs stay valid. | #618 |
| `plugin/workflow-src/lib/decide.js` | Gains the `consult` action, the `council_split` ask reason and the `council` list reason. With `consults_used` absent, every existing outcome is unchanged. | #624 |
| `plugin/workflow-src/standard-delivery/` | Passes `consults_used` and convenes the council on `consult`. The pause contract is unchanged. | #624 |
| `plugin/workflow-src/analysis-only/`, `pr-feedback-remediation/` | Unchanged; they pass no `consults_used`, so they never consult. | none |
| `plugin/agents/synapse.md` | Unchanged; in delivery it runs the non-Claude member's runner command. Its name is not reused. | none |
| `plugin/skills/adaptation-cycle/scripts/run-review.sh` | Review mode unchanged; the council's brief mode shares its reviewer setting and argv kernel. | #618 |
| `plugin/agents/cerebrate.md` | Unchanged; review passes use it with `Memory context: none`. | none |
| `plugin/agents/overlord.md` | Unchanged; its Write grant stays limited to `.hivemind/` inputs files. | none |
| `CONTEXT.md` | This pull request adds the initiative's terms and fixes the stale "planned" notes. | #627 |
| `docs/adr/0045-lair-software-factory.md` | Not edited here; decision 10 is amended by #625. | #625 |
| Lair controller | Not yet built (#608); the readiness check is its admission step. | #623 |

## Failure modes

| Failure | Handling |
|---|---|
| A stamped document is edited after review | The record is stale (`record_stale:<path>`) until a review of the change re-stamps it; every slice fails the check meanwhile. |
| A merge conflict resolution edits a stamped document | Same as above, seen on trunk; a follow-up docs pull request re-reviews and re-stamps. |
| #625 merges first and changes ADR-0045 | No effect: this design cites ADR-0045 decision 10 by number and never stamps ADR-0045. |
| ADR number 0046 or 0047 is taken on main | Checked before the pull request opens and before it leaves draft; the ADR is renumbered and every link updated. |
| The design review does not converge by round 3 | It stops and reaches the maintainer as a signal to split the initiative. |
| `gh` or `git` fails, or a read is truncated | The check exits non-zero; no caller reads it as a pass, and the Lair leaves the issue unclaimed. |
| A named heading matches zero or several headings | `heading_unmatched` or `heading_ambiguous`; the slice fails. |
| The review record's front matter is off its shape | `record_malformed`; the slice fails. |
| A slice passes with open blockers | It may be labeled ready; the Lair still claims it only when no blocked-by dependency is open. |
| The issue is edited between the check and the claim | ADR-0045 decision 10's unedited check and the body hash captured at claim time stop it. |
| A council member fails, times out or returns off schema | Abathur weighs the rest; with fewer than two members, or off-schema Abathur output, there is no council result and the pre-consult outcome applies (ask, or park when unattended). The attempt counts toward the cap. |
| The per-run cap is reached | No consult; `decide()` resolves as it does today. |
| Stage evidence is ambiguous | The guide reports it and asks; it never guesses a stage. |
| An interrogation session is lost | Only the seed issue survives; the guide reports the interrogation stage and restarts it. |
| A governance edit cannot fit its byte budget by cutting | The slice stops and asks the user with measured bytes. |

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

Taken and listed for veto; set by the PRD. Fresh cerebrate passes with `Memory context: none`, angles A and B in parallel, a confirming round, exit at zero open critical or high and one round with no new findings, capped at three rounds. ADR-0046.

### D7: Review record front matter with blob stamps

Taken and listed for veto; set by the PRD. The fixed front matter and its staleness rule. ADR-0046.

### D8: Ready label allowed with open blockers

Taken and listed for veto; set by the PRD. A passing slice is ready with open blocked-by links; `readiness:blocked` is kept for blocks with no issue link. Ready Issue keeps its no-open-blocked-by rule. ADR-0046.

### D9: Design-decision always-ask rule

Taken and listed for veto; set by the PRD. Review Calls gains the rule in the design-decision rule component. ADR-0046.

### D10: Delivered design frozen as history

Taken and listed for veto; set by the PRD. Close-out adds the delivered status and as-built deltas, then the file is never maintained. ADR-0046.

### D11: No dedicated different-model design pass in v1

Taken and listed for veto; set by the PRD. No ADR: fails hard to reverse, because the record already names each pass's reviewer, so a pass can be added later with no schema change.

### D12: Abathur council with two callers

Taken and listed for veto; set by the PRD. One decision service called from the design stages and from standard-delivery; the caller launches the members, then Abathur; at least two members on at least two models, one of which may run through the tool-neutral runner. ADR-0047.

### D13: Consult row as data with a per-run cap

Taken and listed for veto; set by the PRD. The convening rule is the `council_consult` row; hard stops and promotion-gate trips are never consulted. ADR-0047.

### D14: Council member named Overseer

Taken and listed for veto. Synapse is now the runner agent, so the member takes a new name. ADR-0047.

### D15: Drone with exact file scope writes designs and records

Taken and listed for veto. Solution designs, review records and design-stage ADRs are written by a drone with exact file scope; `hivemind:plan-interrogation`'s writer exception is not extended. No ADR: fails hard to reverse, because changing the writer is one prose edit.

### D16: Process and council get separate ADRs

Taken and listed for veto. ADR-0046 records the process and ADR-0047 the council, so the council can be amended alone. No ADR: fails hard to reverse.

### D17: Readiness check is a shared library

Taken and listed for veto. `plugin/skills/_shared/readiness-check.sh` is sourced by each caller's own script, so no skill calls another's script. No ADR: fails hard to reverse.

### D18: Initial consult row values

Taken and listed for veto. `consult` at `high` and `balanced`, `skip` at `low`, `per_run_cap` 2. A run at `low` asked to be asked; each consult costs at least three agent runs. No ADR: fails hard to reverse, because the values are table data.

### D19: Native blocked-by edges written at triage

Taken and listed for veto. Triage writes the edge for each Dependencies ref through `deps-add`, behind its confirm gate; `hivemind:prd-to-issues` keeps body refs. No ADR: fails hard to reverse.

### D20: Prose budget with no pre-approved raise

Asked. The user's answer: no raise is pre-approved. Each later slice that edits `decision-autonomy.md` or `remediation-doctrine.md` fits its byte budget by cutting. If it cannot, it asks the user with measured bytes. This pull request edits nothing under `tests/policy/`. No ADR: fails hard to reverse.

### D21: Accepted-ADR amendments recorded in ADR-0047

Asked. The user's answer: approved. ADR-0047's status line and decisions record the amendments of ADR-0026 decision 2 (a weak or absent recommendation with a clean gate goes to the council before defer-or-record), ADR-0036 decision 6 (`decide()` gains the consult action, so a weak recommendation is consulted before it is taken) and ADR-0045 decision 7 (a choice with no recommendation goes to the council before it parks). None of those three ADR files is edited. ADR-0047.

## Verification strategy

Each slice runs `bash tools/validate.sh --changed` at its validate state. Per slice:

- **#615:** contract tests over recorded issue fixtures for each track and each reason code, including a document edited after stamping, an epic, a standalone issue that must be promoted and a slice with open blockers that passes.
- **#616:** a fixture run on the Lair PRD yields every template section filled; skill authoring checks prove the skill names no sibling.
- **#617:** `tests/prd-to-issues/` fixtures for the design section and for seed-issue reuse with no duplicate on rerun.
- **#618:** schema contract tests for the brief in and out, member provenance, a council of two Claude members on two models, and a council with one member through the runner; the review runner's existing `tests/run-review/` cases stay green.
- **#619:** stamping then verifying passes; an open high finding, a missing clean round or a fourth round fails.
- **#620:** `tests/triage-backlog/` cases: a failing issue never enters the apply set as ready and its reasons show; a passing slice with open blockers is proposed ready.
- **#621:** recorded fixtures for every stage give the expected stage and next action; handoff mode passes only when every slice passes.
- **#622:** the skill is user-only; a live smoke takes a throwaway idea to ready slices, and a fresh session resumes at the derived stage.
- **#623:** a tick contract test where an epic and a stale design are not claimed and are named in the queue report.
- **#624:** `tests/workflow-scripts/` engine tests where consult turns into take, ask or park by session type; the per-run cap holds; hard stops and gate trips are never consulted; existing `decide()` cases stay unchanged; one live delivery run resolves a weak-recommendation question through the council.

### Prose budget check

Every slice that edits a governance doc (#616 and #624 edit `decision-autonomy.md`; any slice that edits `remediation-doctrine.md`) measures the file as CHECK 18 does, bytes with CR stripped, and passes CHECK 18 of `tools/policy_check.sh` within the budget in `tests/policy/prose-byte-budget.json`. It fits by cutting per P25. If it cannot, it stops and asks the user, showing the measured bytes, the budget and the bytes needed. A raise lands only with a user-approved entry in `tests/policy/prose-budget-raises.json`. Governance citations pass `tests/workflow-scripts/governance-section-refs.test.mjs`.

## Seam order

Slices start in this order; a slice waits on its blockers.

| Slice | Blocked by | Headings it implements |
|---|---|---|
| #615 Readiness check | none | Readiness check; Track fact; Readiness check output contract; Standalone spec block format; Slice design section format; Review record front matter; D3: One deterministic readiness check shared by three callers; D4: Track read from the native parent and labels; D17: Readiness check is a shared library |
| #616 Solution design skill and template | none | Solution design skill; Initiative folder; Design-decision rule; Solution design template; D5: Per-initiative docs folder; D9: Design-decision always-ask rule; D15: Drone with exact file scope writes designs and records; D20: Prose budget with no pre-approved raise |
| #617 Slice design links and seed epic | none | Slice design section; Slice design section format |
| #618 Abathur council | none | Abathur council; Council brief contract; D12: Abathur council with two callers; D14: Council member named Overseer |
| #619 Design review and record | #615 | Design review; Design review rounds; Review record front matter; D6: Design review by fresh read-only planner passes; D7: Review record front matter with blob stamps; D11: No dedicated different-model design pass in v1 |
| #620 Triage readiness gate | #615 | Triage readiness gate; D8: Ready label allowed with open blockers; D19: Native blocked-by edges written at triage |
| #621 Stage derivation and handoff check | #615, #619 | Stage derivation and handoff check; Initiative stages; D2: Stage derived only from GitHub and git |
| #622 Guided initiative command | #616, #617, #619, #620, #621 | Guide skill; Close-out; D1: Guide is a user-only conductor skill; D10: Delivered design frozen as history |
| #623 Lair admission | #615, #608 | Lair admission |
| #624 Mid-delivery consult | #618, #607 | Mid-delivery consult; Consult setting; D13: Consult row as data with a per-run cap; D18: Initial consult row values; D20: Prose budget with no pre-approved raise; D21: Accepted-ADR amendments recorded in ADR-0047 |

## Open questions

None

## Amendments

None yet.
