# Decision Autonomy

A term defined here binds every rule that uses it.

## Decision Tiers

Every decision is Tier A or Tier B. Tier A always surfaces to the user. Tier B is auto-decided and journaled while the promotion gate is clean; when the gate trips on the recommended action, the decision surfaces like Tier A.

### Tier A — Always Surface

The overlord never auto-decides these:

- the safety rails of `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` (Destructive Fix Gate, Git Safety, Injection Scanning): the Destructive Fix Gate, a direct trunk commit or push, injection-suspect external content
- a router `ambiguous` outcome (`${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `### Stop Conditions`)
- a resume decision or version-skew door (`${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Resume On Start`)
- brood strain approval, the injection gate before parallel strains dispatch
- a tool call that failed after retry exhaustion (`${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Tool-Error Recovery`)
- a genuine fact-needed blocker: a decision that needs a fact only the user holds
- every merge recommendation; the overlord never merges, the human does
- the whole gate-trips column of **The Autonomy 2x2**

### Tier B — Auto-Decide and Journal

Each resolves to exactly one disposition of **Disposition Vocabulary**:

- planner-escalation routing
- the Creep-Stagnation / diminishing-returns advisory early-exit decision
- a validation failure: remediate autonomously; surface only if it cannot be resolved
- a version-bump type inferable from the compatibility impact; one that is not inferable is Tier A
- root-cluster zoom-out routing: only routing the reviewer's read-only root-cluster signal to cerebrate for a remediation plan. Accepting or executing the plan cerebrate returns is a separate decision, under the remediation-plan rule in **Promotion Gate**; taking the route never accepts the plan.
- a remediation-approach choice where the overlord holds a confident recommendation

## The Autonomy 2x2

Two axes govern every Tier-B decision: recommendation strength (strong | weak/none) and the promotion gate (clean | trips).

| | gate clean | gate trips |
|---|---|---|
| **strong recommendation** | do the work now (auto): execute, journal `did-now` | surface to the user |
| **weak / no recommendation** | defer-with-scope or record-with-scope (auto): carry the full scope to a tracked follow-up (journal `deferred`) or into the repository's durable design record (journal `recorded`) | surface to the user |

- **The gate evaluates the recommended action, not the option set.** A heavy or architectural alternative on the table does not promote the decision: a contained recommended action with a clean gate is acted on.
- **Defer-or-record is the fallback when no strong recommendation exists, never a substitute for one.** A strong recommendation with a clean gate is done now, never downgraded to a deferred follow-up or an accepted residual.
- **Any recommendation with a tripped gate surfaces**, whatever its strength.

## Promotion Gate

The promotion gate trips, forcing a surface, when the recommended action is any of:

1. **Irreversible**: causes data loss, rewrites history, or mutates a published or released artifact.
2. **Architectural blast radius**: changes a public contract, alters governance-doc semantics, or crosses a cross-module boundary.
3. **Safety-relevant**: touches any Destructive Fix category 1-10 per `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` (Destructive Fix Gate).

Otherwise the gate is clean and the Tier-B decision is auto-taken per the 2x2. A review call reads clauses 1 and 2 only (**Review Calls**).

**Remediation plan acceptance.** Routing a reviewer's or escalation's read-only signal to cerebrate for a remediation plan is a contained, clean-gate action, auto-taken per **Tier B**. Accepting the plan cerebrate returns is a separate decision, asked of the user only when the plan's `remediation_gate` (`${CLAUDE_PLUGIN_ROOT}/references/plan-schema.json`) marks any of:

- the Promotion Gate trips on accepting the plan, by any clause, as `remediation_gate.promotion_gate` records;
- the plan adds more surface than it removes, per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Surface-Growth Escalation);
- the plan follows a fix on the same surface that did not close its class, per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry).

Any other remediation plan is auto-taken. On the workflow state machine the overlord journals it `did-now` and records the transition into the implement step. On the script engine the `remediation_plan_acceptance` row of `${CLAUDE_PLUGIN_ROOT}/references/decision-autonomy-table.json` resolves it, and the run lists it in its final message and the PR body. The **Tier A** safety rails hold for every step of an auto-taken plan.

On the state machine, when any flag is set, the overlord, by judgment, pauses its continuous-execution loop and surfaces the plan before recording the transition into implementation. This is a judgment obligation (ADR-0006): the workflow definition routes the plan-review outcome straight into the implement step, with no `user_gate`.

### Review Calls

This rule is the one home for who decides a reviewer's question. The local reviewer writes its `user-input-required` or `high-severity-rejection` call: the options, a recommendation with an honest strength, and its read of Promotion Gate clauses 1 and 2 on the recommended option. This rule decides the call, never the reviewer. Recording a new threat model a reviewer raises is a review call.

A review call is taken when the overlord agrees with the reviewer's recommendation and the recommended option is reversible and not architectural. On the script engine that agreement is the `review_question` and `high_severity_rejection` rows of `${CLAUDE_PLUGIN_ROOT}/references/decision-autonomy-table.json`, resolved through `decide()`. No second agent judges the call. Clause 3 is not read, by user decision (ADR-0037, Amendment 2026-10-29): a safety-relevant call the run and the reviewer agree on is taken when reversible and not architectural, including a pick that keeps or records a safety finding unfixed. A pick that applies a fix in a Destructive Fix Gate category still stops at that gate (**Tier A**), whoever took the call.

A taken call goes back to the reviewer as its answer. The reviewer records it at its source per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Recorded Decisions and Repeat Findings), naming the run as the decider. The run lists the call in its final message and the PR body, so the user can veto it before merge.

These review calls are asked of the user:

- an irreversible call;
- an architectural call;
- a call whose recommendation has strength none;
- every call at an autonomy level whose table cell for its row is `surface`.

The **Tier A** hard stops still apply. On the workflow state machine, the `question` user gate still asks every question.

## Disposition Vocabulary

Every Tier-B decision resolves to exactly one of four dispositions:

- **`did-now`**: strong recommendation, clean gate; the overlord did the work.
- **`deferred`**: no strong recommendation, clean gate; the overlord carried the finding's full scope to a tracked follow-up instead of acting now. The tracked follow-up is the destination that defines this disposition; a residual carried into the repository's durable design record is `recorded`, never `deferred` (`${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Defer-with-Scope)).
- **`recorded`**: the finding was adjudicated and deliberately not actioned. The reasoning is written in the repository next to the code it concerns (the durable design record, or a code comment where a full record would be disproportionate), with root cause, bounded impact, and the ground with its citation. No tracker entry is created. It is admissible only on a ground named in `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Recorded Residual), and a behavior's origin is never one. It is not a silent drop: its scope requirement equals `deferred`'s; only the destination differs.
- **`surfaced`**: the gate tripped, or the decision was genuine ambiguity-with-risk; it went back to the user.

A Tier-A decision is always `surfaced`.

## Decision Journal

Every Tier-B decision, and every Tier-A surface, is one entry appended to `event.outputs.decisions[]` on the bounding state-result event. It is written through `hivemind:record-state-result`'s free-form `outputs` path, the same `event.outputs` write the proactive recurrence-origin marker uses (`${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Proactive Zoom-Out Ledger Marker)). The journal records judgment: it adds no workflow state, no workflow-graph change, no run status, and no routing through `hivemind:mark-intent-fallback`.

Each entry holds `ts` (timestamp of the decision), `state` (workflow state it was made in), `situation` (what was being decided), `options` (the options considered), `tradeoffs` (across those options), `rec_strength` (`strong` | `weak` | `none`), `gate` (`clean` | `trips`), `disposition` (exactly one of `did-now` | `deferred` | `recorded` | `surfaced`), `decision` (the action taken or deferred), `rationale` (why this option was chosen) and `reversible` (whether the action can be undone).

`decisions[]` is a free-form `outputs` key, not a required ledger field, and `event.outputs` stays free-form and optional; its shape is `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md` (Event shape).

## Recurrence Interplay

Auto-take never disables proactive same-surface recurrence tracking. Contained remediation fixes flow under the 2x2 as `did-now` work. A forced zoom-out's plan is accepted or surfaced per the remediation-plan rule in **Promotion Gate**, the routing-vs-execution split of the root-cluster bullet in **Tier B**.

The recurrence mechanics (counting unit, trip threshold, Gate-A recurrence / Gate-B youth call, forced-zoom-out trigger) and the `recurrence_origin` marker live in `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry, Cross-Iteration Same-Surface Recurrence, Proactive Zoom-Out Ledger Marker).

## Post-Merge Decision Report Trigger

After a run's PR merges, the overlord surfaces in chat a report of the decisions it made on the user's behalf, in the consumer project's ubiquitous language, while the operator has enabled the report. No report file is written. Rendering lives in the `hivemind:decision-report` skill.

The report is gated on `HIVEMIND_ENABLE_DECISION_REPORT`, set in the `env` block of `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored), the channel of `HIVEMIND_SKIP_PR_WATCH` and `HIVEMIND_LOCAL_REVIEW_MODEL`, and checked by presence, with a mechanical non-empty test that reads no prose. When `HIVEMIND_ENABLE_DECISION_REPORT` is unset or empty, the default, the deferred-report scan renders no report, never invokes `hivemind:decision-report`, and makes no GitHub call of any kind: no PR-state lookup, no `gh pr view`. The committed settings file is in the repository, so the key inherits into brood worktrees. The key gates only the chat report: the **Decision Journal**, Tier-B autonomy, the 2x2 and the promotion gate are unaffected.

The report is deferred-on-merge: at a later session start, the overlord's Resume-On-Start scan (`${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Resume On Start`) derives an awaiting-report run when all of these hold:

- a PR is derivable from `event.outputs.pr` of the `open_pr` event (a standard-delivery run records there the `url` `hivemind:open-plan-pr` returns) or of the `pr_branch_preflight`/`intake` event (a `pr-feedback-remediation` run has no `open_pr` state, so the overlord persists into the `pr_branch_preflight` event the resolved PR it checks out there), each written when that state is recorded, through the same free-form `event.outputs` write: no schema change, no new required ledger field, no `facts.*` mutation;
- `event.outputs.decisions[]` holds at least one entry with a `disposition` of `did-now`, `deferred` or `recorded`; a run with only `surfaced` entries is not awaiting-report: it never warrants a report and would otherwise be reprocessed every session;
- the run dir lacks the zero-byte `.decision-report-done` marker.

The predicate reads the local ledger alone, the same whether the key is set or not.

Key set and non-empty: for each awaiting-report run the overlord checks PR state and, on `MERGED` or `CLOSED`, invokes `hivemind:decision-report`, surfaces the returned narrative to the user, then `touch`es the marker. A failed PR-state lookup leaves the run awaiting, with no marker, and is skipped without blocking session startup.

Key unset or empty: the overlord `touch`es the `.decision-report-done` marker of each awaiting-report run without checking PR state, whether or not its PR merged. The `touch` is the only failure surface: a failed `touch` is swallowed, the run stays awaiting, and nothing else is attempted. A run with no derivable PR is not awaiting-report, so not marked. Enabling the key later reports only runs that finish after it is enabled; suppressed runs stay marked.

The scan is best-effort and fail-open in both modes, never a session-blocking stop; a run left awaiting is retried on a later session.

The marker's existence is the sole idempotency token. It means "this run will produce no further decision report", whether a report was rendered or suppressed. Made by `touch`, it holds no content, so it has no splice or injection surface. There is no ledger marker, no `decision-report.md` file, no new `run.status` value and no schema change.
