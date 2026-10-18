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

- `high` is the default when the key is unset or empty. The overlord takes recommendations.
- `balanced` is exactly the 5.0.3 posture. It is the migration path for an operator who wants the old behavior back.
- `low` asks before every judgment call.

The value is checked against a POSITIVE ALLOWLIST of those three strings, not by presence. An invalid value resolves to `low` with a one-line warning. A typo therefore fails toward more oversight, never less.

ADR-0030's verb-in-name presence trap does not apply here. That trap exists because a presence check reads `=off` as "present", which means "enable". `HIVEMIND_AUTONOMY` is never presence-checked. Its value is the signal, and any value outside the allowlist lands on the most cautious level. The key can be a bare noun because the check is not a presence check.

### 2. Surface rules are a data table, and hard stops have no cells

Whether a decision surfaces is defined in `plugin/references/decision-autonomy-table.json`, indexed by decision kind × autonomy level, and each cell is `surface` or `auto`. Only a literal `auto` grants autonomy. Any other cell content, or a missing cell, means surface.

The hard stops have NO cells: `destructive_fix_gate`, `trunk_commit_push`, `injection_suspect`, `merge_recommendation`, and `brood_strain_approval`. No level can make them `auto`, because there is no cell to set. Their protection is structural, not something each level has to remember to repeat.

### 3. The decision brief is data, and its rendering contract lives in governance

Surfaced decisions follow `plugin/references/decision-brief-schema.json`, a JSON Schema limited to the structured-output subset. The rules for rendering a brief live in `plugin/governance/decision-autonomy.md` (`## Decision Brief`). The schema fixes what a brief must carry. Governance fixes how it reads to the user.

Assumed constraints appear in the brief as OVERRULABLE. A constraint the agent assumed is labeled as an assumption the user can strike, never presented as a given. This is the direct answer to "Who made the public API constraint?".

### 4. Agents read the table directly, with no lookup script

Agents read the table as prose-loaded data and apply it by judgment. No jq lookup script sits in front of it.

A script would be thrown away at the planned Workflow-tool migration. It would also guard the wrong step. The errors that actually occur are choosing the decision kind, judging whether the promotion gate trips, and judging recommendation strength. All three remain judgment with or without a script. A mechanical lookup over a judged key does not make the key more correct.

**Revisit trigger.** This choice is reopened if decision-journal entries show disposition `surfaced` where the table cell at the recorded level was `auto`. That pattern is the observable sign that agents are misreading the table, as opposed to misjudging the kind or the gate.

### 5. Cerebrate resolves auto-cell questions itself, the overlord backstops, and the workflow graph does not change

When a question the cerebrate would raise falls in an `auto` cell at the active level, the cerebrate takes its own recommendation and journals it. It does not emit `open_questions`. As a backstop, if an `open_questions` outcome reaches the overlord anyway and the question falls in an `auto` cell, the overlord re-delegates to the cerebrate once, telling it to resolve the question.

The workflow graph does NOT change. `open_questions` still maps to `blocked`. What changes is how often the cerebrate reaches that outcome. As a result there is no workflow version bump and no version skew for in-flight ledgers. A run started under 5.0.3 resumes against an identical graph.

### 6. `remediation_plan_acceptance` surfaces at every level

Accepting a remediation plan stays `surface` at every level, including `high`. A remediation plan is architectural by construction: it exists because review escalated past a patch to a change of approach. ADR-0026 already treated accepting such a plan as tripping the promotion gate by judgment. This record makes that unconditional in the table.

### 7. Reviewers produce briefs and never answer questions

`local-reviewer` and `github-reviewer` may produce decision briefs. They never answer the questions those briefs raise, at any level. Answering a human reviewer on GitHub speaks for the user in a public, attributed channel, and no autonomy level grants that authority.

### 8. The schema file is named `decision-brief-schema.json`, not `decision-brief.schema.json`

The CHECK8 bare-path regex in `tools/policy_check.sh` matches a filename stem of `[A-Za-z0-9_-]+` followed directly by `.(md|sh|json)`. The stem class excludes `.`, so a reference to `references/decision-brief.schema.json` never matches: the stem stops at `decision-brief`, and what follows is `.schema`, not one of the three suffixes. A bare reference to a `.schema.json` file would pass CHECK8 unflagged. The single-extension name keeps every reference to the schema under the bare-path gate.

### 9. MAJOR bump to 6.0.0

The default behavior changes. An operator who sets nothing moves from the 5.0.3 posture to `high`, and decisions that used to surface are now taken. Under `plugin/governance/versioning.md` a change to default behavior is MAJOR, following the precedent of 3.0.0, 4.0.0, and 5.0.0. `balanced` is provided precisely so that an operator who wants the old behavior can get it back with one key.

### 10. Both data files are engine-agnostic by intent

`decision-autonomy-table.json` and `decision-brief-schema.json` are written to be reused as-is when the executor moves to the Claude Code Workflow tool. The schema passes straight to `agent(..., {schema})` as a structured-output contract, and the table becomes a lookup the workflow script performs. Neither file encodes anything specific to the current prose-driven executor.

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
| Allowlisted `HIVEMIND_AUTONOMY` (`high` default, invalid → `low`), table with no cells for hard stops, schema-backed briefs, no graph change (CHOSEN) | — |

## Consequences

- **The default posture is `high`.** An operator who sets nothing gets the overlord taking recommendations on every kind whose `high` cell is `auto`. The rubber-stamp round trips this record targets go away, and each auto-taken decision is still journaled.
- **`balanced` restores 5.0.3 exactly.** An operator who wants the previous posture sets one key. It inherits into brood worktrees through the committed settings file.
- **Hard stops cannot be relaxed by data.** Destructive-fix gate, trunk commit/push, injection-suspect content, merge recommendations, and brood strain approval have no cell at any level. The overlord still never merges.
- **Surfaced decisions have a fixed shape.** Every surfaced decision is a brief validated by the schema. Assumed constraints appear as overrulable, so a constraint the user never set can be struck instead of silently narrowing the options.
- **The workflow graph and its version are unchanged.** `open_questions` still maps to `blocked`. In-flight ledgers resume without skew, and `hivemind:mark-intent-fallback` is not involved.
- **ADR-0026 Decision 1 is amended, not deleted.** Tier membership now lives in the table. The Autonomy 2x2, the promotion gate, the disposition vocabulary, and the journal entry shape stand as ADR-0026 and its amendments leave them. ADR-0026 stays unedited as historical record.
- **The override channel now carries four keys.** `HIVEMIND_LOCAL_REVIEW_MODEL`, `HIVEMIND_SKIP_PR_WATCH`, `HIVEMIND_ENABLE_DECISION_REPORT`, and `HIVEMIND_AUTONOMY` share one `env`-block convention, one settings-file pair, and one brood-inheritance property. `HIVEMIND_AUTONOMY` is the only one checked against a value allowlist rather than by presence or charset.
- **Table misreads are observable.** The revisit trigger in Decision 4 is checked against existing journal data. No new instrumentation is needed to know when the prose-read approach has stopped working.
- **The plugin version moves to 6.0.0.** The default behavior change is MAJOR.

References: `plugin/governance/decision-autonomy.md` (`## Decision Brief`), `plugin/references/decision-autonomy-table.json`, `plugin/references/decision-brief-schema.json`, `plugin/governance/versioning.md`, `plugin/workflows/standard-delivery.json`, `plugin/workflows/pr-feedback-remediation.json`, `plugin/workflows/analysis-only.json`, `CLAUDE.md`; amends ADR-0026 Decision 1; follows the operator-override precedent of ADR-0022, ADR-0029, and ADR-0030.
