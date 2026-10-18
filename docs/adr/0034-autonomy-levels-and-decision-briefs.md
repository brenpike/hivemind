# Autonomy levels behind an allowlisted env key, with decisions surfaced as structured briefs

**Status:** accepted — 2026-10-18

## Context

ADR-0026 shifted the overlord's default posture toward taking judgment calls on the user's behalf and journaling them. It did that by enumerating two fixed tiers in governance prose: Tier-A always surfaces, Tier-B auto-decides unless the promotion gate trips. There is one posture for every operator, and the tier lists can only change by rewriting governance prose.

An analysis of 49 sessions, 483 user prompts, and 661 run ledgers shows the posture still interrupts far more than the operator wants, and that the interrupts it does make are poorly framed:

- **Most interrupts are rubber stamps.** About 37% of user prompts are pure approval tokens: "Take recs" 53 times, "Go" / "Yes" 48 times, and a bare option pick 28 times. In each case the user accepted the recommendation already on the table. The interrupt did no oversight work; it only cost a round trip.
- **Surfaced decisions are hard to read.** There are 21 complaints about framing, for example "Layman's terms", "insane wall of text", and "you always tell me WHAT ... but never why". The user gets a dump of the situation, not a decision they can make.
- **The user has to ask for the counter-case.** There are 8 explicit requests for a steel-man or straw-man of the options. The user had to ask for the strongest case against the recommendation because the surfaced text did not give it.
- **Agents invent constraints and treat them as binding.** "Who made the public API constraint? It wasn't me." A planner assumed a constraint the user never set, then ruled out options because of it, and the user could not tell which constraints were theirs.

The root cause of the volume is structural, not a matter of prose. In `standard-delivery`, `pr-feedback-remediation`, and `analysis-only`, a cerebrate `open_questions` outcome maps to the `blocked` terminal (as it also does in `hatchery-dispatch`). Every planner question therefore ends the run. The user answers "Take recs", and a new run starts to do what the planner already recommended. Tuning the tier prose cannot fix this, because the question never reaches the tier logic. The workflow graph ends the run first.

This record AMENDS ADR-0026 Decision 1. Tier membership no longer lives in enumerated governance lists; it lives in a data table indexed by autonomy level. ADR-0026 is a historical record and is deliberately left unedited. Where the two disagree on which decisions surface, this record governs. The normative mechanics live in `plugin/governance/decision-autonomy.md`, `plugin/references/decision-autonomy-table.json`, and `plugin/references/decision-brief-schema.json`. This record states the decisions and why they were made, and does not restate the normative text. The pointer is one-way, ADR to governance.

## Findings

- **The rubber-stamp share is the measurable target.** If the user accepts about 37% of prompts verbatim, those decisions already had a recommendation the user trusted. A posture that takes recommendations by default removes those round trips without removing any decision the user actually changed.
- **The planner question is the main source of rubber stamps.** `open_questions` → `blocked` makes every cerebrate question a run-ending event. The pure-approval reply that follows is the user re-authorizing the planner's own recommendation.
- **Framing complaints and counter-case requests share one cause.** Surfaced decisions have no fixed shape. Whether a recommendation, its reasoning, the strongest alternative, and the assumptions behind it appear at all depends on the prose each agent happens to write. Requiring a fixed shape addresses both complaints at once.
- **An invented constraint can only be overruled once it is visible.** A constraint the planner assumed but never labeled reads exactly like one the user set. The user can only overrule it if the brief marks it as assumed.
- **The operator-override channel already holds three keys.** `HIVEMIND_LOCAL_REVIEW_MODEL` (ADR-0022), `HIVEMIND_SKIP_PR_WATCH` (ADR-0029), and `HIVEMIND_ENABLE_DECISION_REPORT` (ADR-0030) are all set in the `env` block of `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored, per-account), and all inherit into brood worktrees.
- **The executor is expected to move to the Claude Code Workflow tool.** Anything built as a shell lookup around today's prose-driven executor would be thrown away at that migration. Data files would not be: a JSON table and a JSON Schema are consumed as-is.

## Decision

### 1. `HIVEMIND_AUTONOMY` selects one of three levels, checked against a positive allowlist

The operator sets `HIVEMIND_AUTONOMY` in the `env` block of `.claude/settings.json` or `.claude/settings.local.json`. This is the same channel as `HIVEMIND_SKIP_PR_WATCH`, `HIVEMIND_LOCAL_REVIEW_MODEL`, and `HIVEMIND_ENABLE_DECISION_REPORT`, and the key inherits into brood worktrees for the same reason they do. There are three levels:

- `high` is the default when the key is unset or empty. The overlord decides the most judgment calls itself.
- `balanced` is exactly the 5.0.3 posture. It is the migration path for an operator who wants the old behavior back.
- `low` asks before every judgment call.

The value is checked against a POSITIVE ALLOWLIST of those three strings, not by presence. An invalid value resolves to `low` with a one-line warning. A typo therefore fails toward more oversight, never less.

ADR-0030's verb-in-name presence trap does not apply here. That trap exists because a presence check reads `=off` as "present", which means "enable". `HIVEMIND_AUTONOMY` is never presence-checked. Its value is the signal, and any value outside the allowlist lands on the most cautious level. The key can be a bare noun because the check is not a presence check.

### 2. Surface rules are a data table, and hard stops have no cells

Decided: whether a decision surfaces is data, `plugin/references/decision-autonomy-table.json`, indexed by decision kind × autonomy level, with one `surface` or `auto` cell each; text: `plugin/governance/decision-autonomy.md` (Autonomy Level).

Decided: the table's `hard_stops` have NO cells; text: `plugin/governance/decision-autonomy.md` (Autonomy Level). With no cell to set, their protection is structural, not something each level has to remember to repeat.

### 3. The decision brief is data, and its rendering contract lives in governance

Surfaced decisions follow `plugin/references/decision-brief-schema.json`, a JSON Schema limited to the structured-output subset. The rules for rendering a brief live in `plugin/governance/decision-autonomy.md` (`## Decision Brief`). The schema fixes what a brief must carry. Governance fixes how it reads to the user.

Decided: assumed constraints appear in the brief as overrulable, the direct answer to "Who made the public API constraint?"; text: `plugin/governance/decision-autonomy.md` (Decision Brief).

Decided: a brief travels only as a structured field, never as a prose line, so the schema applies to the field (Decision 12); text: `plugin/governance/decision-autonomy.md` (Decision Brief), with the planner report lines in the cerebrate report templates (`plugin/agents/cerebrate.md` (Output)). Reference: PR #408 review thread https://github.com/brenpike/hivemind/pull/408#discussion_r4305754238.

**Recorded residual.** This is a decision, not open work, recorded here per `plugin/governance/remediation-doctrine.md` (Recorded Residual).

- **Residual.** The schema does not enforce the three-option limit (`maxItems`) or cross-field constraints, such as `recommendation.option_id` naming a supplied option. Their home: `plugin/governance/decision-autonomy.md` (Decision Brief).
- **Linked findings.** Local review finding 6f1dd3cf; PR #408 review thread https://github.com/brenpike/hivemind/pull/408#discussion_r4305713681.
- **Root cause.** The structured-output JSON Schema subset accepts `minItems` of 0 or 1 only, with no other array bounds and no cross-field constraints. A schema carrying `maxItems` would not be usable as-is as a structured-output contract (Decision 10).
- **Inherited.** The limit belongs to the structured-output subset, not to this change.
- **Bounded impact.** A fourth option only makes a brief longer, and the rendering limit in `plugin/governance/decision-autonomy.md` (Decision Brief) bounds what the user sees. A recommendation that names no supplied option is judged a step-4 case of the resolution order in `plugin/governance/decision-autonomy.md` (Autonomy Level).
- **Rejected on the merits.** Adding `maxItems: 3` would break the schema's use as-is as a structured-output contract. Keeping a second, stricter copy of the schema only for validation would be a hand-kept copy that drifts.
- **Promotion condition.** If the structured-output subset gains `maxItems`, add the bound and a schema test.

### 4. Agents read the table directly, with no lookup script

Agents read the table as prose-loaded data and apply it by judgment. No jq lookup script sits in front of it.

A script would be thrown away at the planned Workflow-tool migration. It would also guard the wrong step. The errors that actually occur are choosing the decision kind, judging whether the promotion gate trips, and judging recommendation strength. All three remain judgment with or without a script. A mechanical lookup over a judged key does not make the key more correct.

**Revisit trigger.** This choice is reopened if decision-journal entries show disposition `surfaced` where the table cell at the recorded level was `auto`. That pattern is the observable sign that agents are misreading the table, as opposed to misjudging the kind or the gate.

### 5. Cerebrate resolves auto-cell questions itself, the overlord backstops, and the workflow graph does not change

Decided: the cerebrate routes each brief by the disposition the resolution order gives it, so a question that resolves to anything but `surfaced` does not emit `open_questions`, and the overlord backstops it by re-judging every returned brief. Text: `plugin/agents/cerebrate.md` (Decisions and Open Questions), `plugin/agents/overlord.md` (Open-question backstop), and, for the meaning of a re-delegated `decided:` answer, `plugin/governance/decision-autonomy.md` (Autonomy Level).

The workflow graph does NOT change. `open_questions` still maps to `blocked`. What changes is how often the cerebrate reaches that outcome. As a result there is no workflow version bump and no version skew for in-flight ledgers. A run started under 5.0.3 resumes against an identical graph.

### 6. `remediation_plan_acceptance` surfaces at every level

Accepting a remediation plan stays `surface` at every level, including `high`. A remediation plan is architectural by construction: it exists because review escalated past a patch to a change of approach. ADR-0026 already treated accepting such a plan as tripping the promotion gate by judgment. This record makes that unconditional in the table.

### 7. Reviewers produce briefs and never answer questions

Decided: `local-reviewer` and `github-reviewer` may produce decision briefs and never answer the questions those briefs raise, at any level; text: `plugin/governance/decision-autonomy.md` (Decision Brief), with the exit_reasons that carry `brief` in each reviewer's Output Contract (`plugin/agents/local-reviewer.md`, `plugin/agents/github-reviewer.md`). Why: answering a human reviewer on GitHub speaks for the user in a public, attributed channel, and no autonomy level grants that authority.

### 8. The schema file is named `decision-brief-schema.json`, not `decision-brief.schema.json`

The CHECK8 bare-path regex in `tools/policy_check.sh` matches a filename stem of `[A-Za-z0-9_-]+` followed directly by `.(md|sh|json)`. The stem class excludes `.`, so a reference to `references/decision-brief.schema.json` never matches: the stem stops at `decision-brief`, and what follows is `.schema`, not one of the three suffixes. A bare reference to a `.schema.json` file would pass CHECK8 unflagged. The single-extension name keeps every reference to the schema under the bare-path gate.

### 9. MAJOR bump to 6.0.0

The default behavior changes. An operator who sets nothing moves from the 5.0.3 posture to `high`, and decisions that used to surface are now taken. Under `plugin/governance/versioning.md` a change to default behavior is MAJOR, following the precedent of 3.0.0, 4.0.0, and 5.0.0. `balanced` is provided precisely so that an operator who wants the old behavior can get it back with one key.

### 10. Both data files are engine-agnostic by intent

`decision-autonomy-table.json` and `decision-brief-schema.json` are written to be reused as-is when the executor moves to the Claude Code Workflow tool. The schema passes straight to `agent(..., {schema})` as a structured-output contract, and the table becomes a lookup the workflow script performs. Neither file encodes anything specific to the current prose-driven executor.

### 11. Each row binds its kind to its decision sites, checked against the workflow graph

Two local-review findings had the same shape: consumer prose (overlord, cerebrate) drifted from the canonical resolution order in `plugin/governance/decision-autonomy.md` (Autonomy Level) at per-site wording. Each patch restated the order at one more site, and the next review found the next restatement. The root cause was that nothing said where a kind is decided, so every consumer re-derived it.

Decided: each table row carries `resolved_at`, a non-empty array of decision sites, and hard stops carry none; site forms and binding text: `plugin/governance/decision-autonomy.md` (Autonomy Level).

Decided: consumers carry one pointer rule instead of per-site prose, and a decision raised at a site its row does not name fails closed. Text: `plugin/agents/overlord.md` (Decision sites) and step 5 of the resolution order in `plugin/governance/decision-autonomy.md` (Autonomy Level).

`tools/validate_workflows.sh` (`validate_autonomy_bindings`) checks the binding at CI time against the union of states and per-state transition keys across `plugin/workflows/*.json`. It rejects an unbound row (R1), a dangling site (R2), a reserved site that carries an outcome (R3), a dangling outcome (R4), a hard stop that carries `resolved_at` (R5), and an unbound planner advance: a cerebrate planning-state outcome that is neither a terminal nor a `user_gate` target and that no row names exactly as `<state>.<outcome>` (R6). `--self-test` proves each rule rejects a broken fixture under `tests/workflow-defs/autonomy-broken/`, with the real table as the positive control.

R7 rejects a decision site named by more than one row. Decided: a site names at most one kind; text: `plugin/governance/decision-autonomy.md` (Autonomy Level). Two rows, `plan_open_question` and `option_choice`, shared the same sites with the same cells, so they are now one row, `planner_question`, at `plan`, `brood_plan`, and `analyze`. `remediation_approach` is the only planner kind at the two remediation planning states, `review_remediation_plan` and `review_remediation_plan_postpr`. This keeps 5.0.3's auto remediation approach at `balanced`, and no oversight is lost because plan acceptance surfaces at every level (Decision 6). The table stays keyed by row. R7 only constrains the bindings, so no second copy of the table exists. Reference: PR #408 review thread https://github.com/brenpike/hivemind/pull/408#discussion_r4305754237.

This is not the runtime lookup script Decision 4 rejects. It runs once in CI over static data, it never sees a live decision, and it does not decide any verdict. Agents still read the table directly and apply it by judgment at runtime.

**Recorded residual.** This is a decision, not open work, recorded here per `plugin/governance/remediation-doctrine.md` (Recorded Residual).

- **Residual.** R1-R7 prove that sites exist, that planner advances are bound, and that each site names at most one kind. They do not prove that a row's kind is the decision actually made at that site. R6 covers cerebrate planning states only, so another decision site can still go unbound without failing validation. Whether a row's `when` applies to a given decision also stays judgment.
- **Linked findings.** Local review finding 1f40bf21 (iteration 3); PR #408 review thread https://github.com/brenpike/hivemind/pull/408#discussion_r4305754237.
- **Root cause.** Which kind is decided at a site is judgment (Decision 4), and the table is its only source. No check can derive the right kind from the workflow graph.
- **Inherited.** Before this change no kind was bound to any site. The bindings narrow that gap and introduce none of it.
- **Bounded impact.** A misbinding needs a reviewed table edit. A decision whose row does not name its site surfaces (resolution step 5). Remediation-plan acceptance surfaces at every level through the promotion gate's architectural clause. Worst case: a skipped plan-acceptance prompt at `low`, and only if the overlord also fails to recognize the decision, on a working branch before a human-merged PR. That is reversible.
- **Rejected on the merits.** An expected kind-to-site map in the validator would be a second hand-kept copy of the table. A site-keyed table, or a `decides` key on workflow states, either leaves the site naming an unverifiable kind or is the graph change already rejected. An inverse rule over every transition fails because most transitions are not decisions, and it would force invented rows or a validator-held exemption list.
- **Promotion condition.** If a misbinding is ever observed to lose a surface, file an issue.

### 12. The resolution order yields the disposition, and consumers route by it

Three PR #408 review threads had one shape: https://github.com/brenpike/hivemind/pull/408#discussion_r4305713684, https://github.com/brenpike/hivemind/pull/408#discussion_r4305838038, and https://github.com/brenpike/hivemind/pull/408#discussion_r4305913044. The last step of the resolution order in `plugin/governance/decision-autonomy.md` (Autonomy Level) returned a bare `auto` or `surface` verdict. What `auto` meant depended on the Autonomy 2x2, the strength of the recommendation against the promotion gate, plus whether the run could finish without the choice and whether the option was reversible. That rule lived in its own section and was restated again in the tier and disposition sections. Consumers read `auto` as "take the recommendation" and dropped the other branches, so the cerebrate and the overlord would act on a weak recommendation the run could have deferred or recorded. The root cause was that a verdict is not a disposition, and every consumer re-derived the disposition from the verdict.

Decided: the resolution order yields the disposition itself, with the 2x2 folded into its step 6, and is the only place a disposition is chosen; text: `plugin/governance/decision-autonomy.md` (Autonomy Level). The tiers are named for the disposition and add no rule of their own, and the separate 2x2 section is gone.

Decided: briefs travel under four planner `plan` keys, one per disposition (text: `plugin/governance/decision-autonomy.md` (Decision Brief)), and the actor that resolves a `deferred` or `recorded` disposition owns its destination (text: `plugin/governance/decision-autonomy.md` (Disposition Vocabulary)). A `decided:` answer now carries a disposition, not a recommendation (text: `plugin/governance/decision-autonomy.md` (Autonomy Level)).

The 2x2 had a "no recommendation" row. It is removed because no decision can reach it: step 4 already surfaces a decision for which no recommendation is possible.

`tests/policy/safety-autonomy-disposition-single-source.json` pins the single-source sentence, the step-6 branch consumers dropped, the plan-key mapping, and the consumer pointers, and its `set_check` requires zero occurrences of the restatement literals in the named consumer files. The pin is a tripwire for the restatements already seen, not the fix. The fix is the single resolution order.

**Recorded residual.** This is a decision, not open work, recorded here per `plugin/governance/remediation-doctrine.md` (Recorded Residual).

- **Residual.** The `set_check` matches fixed, case-sensitive, line-scoped literals. A consumer that re-derives a disposition in fresh words, or wraps a literal across a line break, passes. The human-facing docs (`README.md`, `CLAUDE.md`, `CONTEXT.md`, `web/functionality.html`) are outside its file list, so a restatement there is invisible.
- **Linked findings.** PR #408 review threads https://github.com/brenpike/hivemind/pull/408#discussion_r4305713684, https://github.com/brenpike/hivemind/pull/408#discussion_r4305838038, and https://github.com/brenpike/hivemind/pull/408#discussion_r4305913044.
- **Root cause.** No fixture can assert body-prose absence beyond fixed literals; `absent` is scoped to YAML frontmatter. Whether prose re-derives a disposition is meaning, and a pin claims only word-sequence presence.
- **Inherited.** The limit belongs to the pin mechanism (`tests/policy/README.md`, rules 1 and 7), not to this change.
- **Bounded impact.** A paraphrased restatement needs a reviewed edit to an agent or governance file. The human docs describe the levels to people and are not loaded by agents at runtime, so a restatement there cannot change a disposition.
- **Rejected on the merits.** A semantic check would have to parse prose for meaning. Adding the human docs to the file list would forbid them from describing the behavior in plain words, which is their job.
- **Promotion condition.** If a paraphrased restatement is ever observed to change a disposition, add a structural check in `tools/policy_check.sh`.

### 13. Rules live once; consumers point

Three PR #408 review threads had the Decision 12 shape again, in short or paraphrased form: https://github.com/brenpike/hivemind/pull/408#discussion_r4305913044, https://github.com/brenpike/hivemind/pull/408#discussion_r4307045423, and https://github.com/brenpike/hivemind/pull/408#discussion_r4307096301. Consumer text restated a canonical rule, and the restatement drifted from its home. One of them exposed a gap in the home itself: the Decision Journal recorded every decision on its bounding state-result event, but some decision sites have no such event. `classify.ambiguous` runs in `workflow-router` before `hivemind:init-run-ledger` creates the ledger, and `resume_on_start` is outside any state result.

Decided: the Decision Journal is keyed on the bounding event, so a decision at a site with no bounding event is not journaled; text: `plugin/governance/decision-autonomy.md` (Decision Journal). `tools/validate_workflows.sh` rule R8 rejects an `auto` cell on any table row bound to such a site, so no decision the journal cannot record is taken on the user's behalf.

Decided: every consumer of a rule, in agents, skills, governance, and the human docs, carries only a pointer to the rule's home; the pointer form is defined in `docs/engineering-principles.md` (P22). The cerebrate carries a scoping rule for plans that change a rule; text: `plugin/agents/cerebrate.md`.

Decided: `tests/policy/safety-decision-journal-single-source.json` pins the journal rule as a sibling of `tests/policy/safety-autonomy-disposition-single-source.json` rather than an extension of it, because its `set_check` may include the canonical file, which the disposition fixture's consumer-only file list excludes.

Considered options:

- A generic near-verbatim restatement detector. Rejected: it would have caught none of the three findings, all short or paraphrased; n-gram matching false-positives on pointer paths; and a line-keyed baseline churns on every edit.
- Carry-forward journaling, writing a pre-ledger decision onto the first ledger event. Rejected: it is undefined for a start-fresh resume, and it adds a rule.
- A pre-ledger journal store. Rejected: it is new schema surface.
- Extending the disposition fixture. Rejected in favor of a sibling fixture that may include the canonical file.

**Recorded residual R1.** This is a decision, not open work, recorded here per `plugin/governance/remediation-doctrine.md` (Recorded Residual).

- **Residual.** A paraphrased restatement cannot be detected mechanically.
- **Linked findings.** PR #408 review threads https://github.com/brenpike/hivemind/pull/408#discussion_r4305913044, https://github.com/brenpike/hivemind/pull/408#discussion_r4307045423, and https://github.com/brenpike/hivemind/pull/408#discussion_r4307096301.
- **Root cause.** Pins claim word presence only (`tests/policy/README.md`).
- **Bounded impact.** A paraphrase needs a reviewed edit, and reviewed edits plus Codex review catch it.
- **Rejected on the merits.** Semantic prose checks would have to parse prose for meaning.
- **Promotion condition.** A repeat restatement finding after this sweep promotes this residual to a structural check.

## Considered Options

| Option | Rejected because |
|---|---|
| Keep ADR-0026's fixed two-tier posture and tune the tier prose | Does not reach the root cause. `open_questions` → `blocked` ends the run before any tier logic runs, so planner questions keep producing rubber-stamp round trips however the tiers are worded |
| Change the workflow graph so `open_questions` routes back into planning instead of `blocked` | Requires a workflow version bump and creates version skew for every in-flight ledger. The same effect comes from the cerebrate not emitting auto-cell questions, which leaves the graph unchanged |
| Presence-checked opt-in key (`HIVEMIND_ENABLE_HIGH_AUTONOMY`) with the old posture as default | A presence check can express only two states, and three are needed. It would also keep the noisy default that the 37% rubber-stamp share argues against |
| Invalid `HIVEMIND_AUTONOMY` value resolves to the default (`high`) | A typo would silently grant the most autonomy. Falling to `low` with a warning makes a misconfiguration cost extra prompts instead of oversight |
| Keep tier membership as enumerated governance prose per level | Three levels × every decision kind means three parallel prose lists that drift apart. A table puts each kind × level judgment in exactly one cell |
| Give hard stops a `surface` cell at every level | A cell can be edited, so one bad table edit could make a hard stop `auto`. Having no cell makes that impossible by construction |
| jq lookup script in front of the table | Would be thrown away at the Workflow-tool migration, and it checks the one step that is not error-prone. Kind, gate, and recommendation strength stay judgment either way |
| `remediation_plan_acceptance` `auto` at `high`, with the promotion gate narrowed to blast radius beyond the requested scope | Narrowing the gate changes it for EVERY decision kind, not just this one, to buy autonomy on a decision that is architectural by construction |
| Let reviewers answer questions at `high` | Answering a human reviewer on GitHub speaks for the user publicly. That authority is not something a local autonomy setting can grant |
| Name the schema `decision-brief.schema.json` | The CHECK8 stem class excludes `.`, so a bare reference to a double-extension file is never matched and passes unflagged |
| MINOR bump, on the grounds that `balanced` preserves the old behavior | Preserving the old behavior requires the operator to act. The default changes for everyone who does nothing, and that is the MAJOR case |
| Restate the resolution order in per-site prose at each consumer | This is the failure being fixed. Two review findings of one class showed that per-site wording drifts from the canonical order, and each restatement is one more place to drift |
| A single overlord rule with no per-row binding | The rule would still need to say which kinds apply at which state, so the mapping returns as prose. Nothing could check it against the workflow graph, and a kind raised at an unexpected state would resolve by guesswork instead of failing closed |
| A `decides` key on workflow states | Changes the workflow definition and so needs a workflow version bump, creating version skew for in-flight ledgers. It also puts the decision-kind vocabulary into the WHO/WHAT-only graph (ADR-0018) |
| Let a `decided:` answer bind the planner unconditionally | It ranks a consumer input ahead of the hard stops, user gates, and the promotion gate, and puts the answer's meaning in consumer prose, where it drifts from the canonical order |
| Merge only the two overlapping planner rows, or narrow their `when` predicates | Fixes the observed pair only. `remediation_approach` already overlapped both at the remediation planning states, and the next row added to a shared site would overlap again |
| Rank overlapping kinds by precedence | Keeps two kinds per site and adds a second ordering to keep in step with the table |
| Keep the `auto`/`surface` verdict and restate the branches per consumer | This is the failure Decision 12 fixes. Consumers read `auto` as "take the recommendation" and dropped the defer, record, and surface branches, and each restatement is one more copy to drift |
| Add a `disposition` field to the brief schema | A second, unverified copy of the disposition that the overlord re-judges anyway. The plan keys already carry the disposition with no schema change |
| A generic near-verbatim restatement detector (Decision 13) | Would have caught none of the three findings, all short or paraphrased; n-gram matching false-positives on pointer paths; a line-keyed baseline churns on every edit |
| Carry a pre-ledger decision forward to the first ledger event (Decision 13) | Undefined for a start-fresh resume, and adds a rule |
| A pre-ledger journal store (Decision 13) | New schema surface |
| Extend the disposition fixture to the journal rule (Decision 13) | A sibling fixture may include the canonical file in its `set_check`; the disposition fixture's file list is consumers only |
| Allowlisted `HIVEMIND_AUTONOMY` (`high` default, invalid → `low`), table with no cells for hard stops, schema-backed briefs, no graph change (CHOSEN) | — |

## Consequences

- **The default posture is `high`.** An operator who sets nothing gets the overlord deciding every kind whose `high` cell is `auto`, by the disposition the resolution order yields. The rubber-stamp round trips this record targets go away, and journaling follows `plugin/governance/decision-autonomy.md` (Decision Journal).
- **`balanced` restores 5.0.3 exactly.** An operator who wants the previous posture sets one key. It inherits into brood worktrees through the committed settings file.
- **Hard stops cannot be relaxed by data.** The table's `hard_stops` have no cell at any level. The overlord still never merges.
- **Surfaced decisions have a fixed shape.** Every surfaced decision is a brief conforming to the schema. Assumed constraints appear as overrulable (`plugin/governance/decision-autonomy.md` (Decision Brief)), so a constraint the user never set can be struck instead of silently narrowing the options.
- **The workflow graph and its version are unchanged.** `open_questions` still maps to `blocked`. In-flight ledgers resume without skew, and `hivemind:mark-intent-fallback` is not involved.
- **ADR-0026 Decision 1 is amended, not deleted.** Tier membership now lives in the table. The Autonomy 2x2, the promotion gate, the disposition vocabulary, and the journal entry shape stand as ADR-0026 and its amendments leave them. ADR-0026 stays unedited as historical record; the 2x2 now lives inside the resolution order (Decision 12).
- **The override channel now carries four keys.** `HIVEMIND_LOCAL_REVIEW_MODEL`, `HIVEMIND_SKIP_PR_WATCH`, `HIVEMIND_ENABLE_DECISION_REPORT`, and `HIVEMIND_AUTONOMY` share one `env`-block convention, one settings-file pair, and one brood-inheritance property. `HIVEMIND_AUTONOMY` is the only one checked against a value allowlist rather than by presence or charset.
- **Table misreads are observable.** The revisit trigger in Decision 4 is checked against existing journal data. No new instrumentation is needed to know when the prose-read approach has stopped working.
- **A decision raised outside its row's decision sites surfaces.** A new decision point needs a table row whose `resolved_at` names the decision site where it arises (step 5 of the resolution order in `plugin/governance/decision-autonomy.md` (Autonomy Level)). A row with no `resolved_at`, a dangling site or outcome, a bound hard stop, or a site named by two rows fails `tools/validate_workflows.sh`. Binding correctness and `when` applicability remain judgment.
- **The plugin version moves to 6.0.0.** The default behavior change is MAJOR.

References: `plugin/governance/decision-autonomy.md` (`## Decision Brief`), `plugin/references/decision-autonomy-table.json`, `plugin/references/decision-brief-schema.json`, `tools/validate_workflows.sh`, `plugin/governance/versioning.md`, `plugin/workflows/standard-delivery.json`, `plugin/workflows/pr-feedback-remediation.json`, `plugin/workflows/analysis-only.json`, `CLAUDE.md`; amends ADR-0026 Decision 1; follows the operator-override precedent of ADR-0022, ADR-0029, and ADR-0030.
