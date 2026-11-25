# Decision Autonomy

A term defined here binds every rule that uses it.

## Decision Tiers

Each decision is Tier A, always surfaced, or Tier B, auto-decided and journaled only while the promotion gate is clean.

### Tier A — Always Surface

Tier A is the closed Ask Set. The overlord never auto-decides:

- the safety rails of `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` (Destructive Fix Gate, Git Safety, Injection Scanning): the Destructive Fix Gate, a direct trunk commit or push, injection-suspect external content
- a router `ambiguous` outcome (`${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `### Stop Conditions`)
- brood strain approval, the injection gate before parallel strains dispatch
- a tool call failed after retry exhaustion (`${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Tool-Error Recovery`)
- a genuine fact-needed blocker: a fact only the user holds
- every merge recommendation; the human merges, except the review watch's opt-in merge after a reviewer approval, per `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/SKILL.md`
- a question with no recommendation
- the whole gate-trips column of **The Autonomy 2x2**

On the script engine, `decide()` asks only for `hard_stop`, `table_surface`, `gate_irreversible`, `gate_architectural`, `gate_safety` and `no_recommendation`.

### Tier B — Auto-Decide and Journal

- planner-escalation routing
- the Creep-Stagnation / diminishing-returns advisory early-exit decision
- a validation failure: remediate autonomously; surface only if unresolved
- a version-bump type inferable from the compatibility impact; a non-inferable one is Tier A
- root-cluster zoom-out routing, per the remediation-plan rule in **Promotion Gate**
- a remediation-approach choice where the overlord holds a confident recommendation
- the list set: an option beyond the request recommended strong at trivial or small effort, and a plan file outside the request's limits. Each is taken, journaled and listed for veto before merge; branch work is undone by declining the PR.

## The Autonomy 2x2

| | gate clean | gate trips |
|---|---|---|
| **strong recommendation** | do it now (auto), journal `did-now` | surface |
| **weak / no recommendation** | auto defer or record with full scope (`deferred` or `recorded`) | surface |

- Strong with a clean gate is done now, never deferred or recorded.

## Promotion Gate

The gate trips, forcing a surface, when the recommended action is any of:

1. **Irreversible**: causes data loss, rewrites history, or mutates a published or released artifact.
2. **Architectural blast radius**: changes a public contract, alters governance-doc semantics, or crosses a cross-module boundary.
3. **Safety-relevant**: touches any Destructive Fix category 1-10 per `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` (Destructive Fix Gate).

Otherwise it is clean. A review call reads clauses 1 and 2 only (**Review Calls**).

**Remediation-plan rule.** Routing a reviewer's or escalation's read-only signal to cerebrate for a remediation plan is clean-gate, auto-taken (**Tier B**), except the forced zoom-out per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry). Accepting the returned plan is asked of the user only when its `remediation_gate` (`${CLAUDE_PLUGIN_ROOT}/references/plan-schema.json`) marks any of:

- the gate trips on accepting it, by any clause, as `remediation_gate.promotion_gate` records;
- it adds more surface than it removes, per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Surface-Growth Escalation);
- it repeats a fix that did not close its class (`remediation_gate.repeats_surface`).

Any other plan is auto-taken: on Instinct the overlord runs it; on the script engine the `remediation_plan_acceptance` row of `${CLAUDE_PLUGIN_ROOT}/references/decision-autonomy-table.json` resolves it. **Tier A** safety rails hold for every step of an auto-taken plan.

With any flag set on Instinct, the overlord surfaces the plan before running it.

### Review Calls

Only this rule says who decides a reviewer's question. The local reviewer writes its `user-input-required` or `high-severity-rejection` call (options, a recommendation with honest strength, its read of Promotion Gate clauses 1 and 2 on the recommended option) but never decides it. Recording a new threat model a reviewer raises is a review call.

The run takes a call when the overlord agrees with the recommendation and the recommended option is reversible and not architectural. On the script engine, agreement is the `review_question` and `high_severity_rejection` rows of `${CLAUDE_PLUGIN_ROOT}/references/decision-autonomy-table.json` via `decide()`; no second agent judges. Clause 3 is not read: a safety-relevant call both agree on is taken when reversible and not architectural, even a pick that keeps or records a safety finding unfixed. A call whose pick applies a fix in a Destructive Fix Gate category is asked, never taken (**Tier A**); a gate hold after a taken call asks that call again.

A taken call returns to the reviewer as its answer, recorded at its source per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Recorded Decisions and Repeat Findings), naming the run as decider, and is listed for veto as in **Tier B**.

Asked of the user: an irreversible call; an architectural call; a call whose recommendation has strength none; every call at an autonomy level whose table cell for its row is `surface`. **Tier A** hard stops still apply, and the overlord asks only what `${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `### Stop Conditions` surfaces.

**Design-decision rule.** In the design stages, a decision with a strong recommendation is taken and listed for veto, in the review record and on the docs pull request, whatever it touches: PRD scope or acceptance criteria, an accepted-ADR amendment, or a trust-boundary, credential or merge-path change. Of design decisions only two kinds are asked: a weak or absent recommendation, asked, never deferred (brenpike/hivemind#638 may change that only by its own ADR), and an action irreversible now, outside the unmerged pull request. The asks other rules set are unchanged. The gate reads **Promotion Gate** clause 1 only, applied to the action taken now. The design stages run no `decide()`; take or ask is judgment, checked by review.

## Disposition Vocabulary

Each Tier-B decision resolves to exactly one of:

- **`did-now`**: strong recommendation, clean gate; the overlord did the work.
- **`deferred`**: no strong recommendation, clean gate; the finding's full scope went to a tracked follow-up, not acted on now. Only a tracked follow-up makes a disposition `deferred`; a residual in the repository's durable design record is `recorded`, never `deferred` (`${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Defer-with-Scope)).
- **`recorded`**: adjudicated, deliberately not actioned, reasoning written in the repository next to its code (the durable design record, or a code comment where a full record is disproportionate): root cause, bounded impact, and the ground with its citation. No tracker entry. Admissible only on a ground named in `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Recorded Residual); a behavior's origin is never one. Its scope requirement equals `deferred`'s; only the destination differs.
- **`surfaced`**: the gate tripped, or the decision was genuine ambiguity-with-risk; it went to the user. A Tier-A decision is always `surfaced`.

## Decision Journal

A run's decision journal is the list of the decisions it took for the user, one line each: the problem, the option chosen and its summary. A run that opens a pull request, or pushes to one through `hivemind:open-plan-pr`, lists them on that pull request, under "Decided for you" in the body of one it opens and in a comment on one it reuses, and the same lines in its final message or final report. Any other run, such as a read-only analysis or a brood dispatch, lists its decisions in its final message or final report and keeps no decision journal. Accepting a plan or a remediation plan, and rerunning a gate after a later commit, are not listed, except a plan acceptance that changes a file outside the request's limits. A workflow script writes the list in code; on Instinct the overlord writes it. No local copy exists.

## Recurrence Interplay

Auto-take never disables proactive same-surface recurrence tracking. Contained remediation fixes flow under the 2x2 as `did-now` work; a forced zoom-out's plan is accepted or surfaced per the remediation-plan rule in **Promotion Gate**. Recurrence mechanics and the `recurrence_origin` marker: `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry, Cross-Iteration Same-Surface Recurrence, Proactive Zoom-Out Marker).
