# Decision Autonomy

A term defined here binds every rule that uses it.

## Decision Tiers

Each decision is Tier A, always surfaced to the user, or Tier B, auto-decided and journaled only while the promotion gate is clean.

### Tier A — Always Surface

Tier A is the closed Ask Set. The overlord never auto-decides:

- the safety rails of `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` (Destructive Fix Gate, Git Safety, Injection Scanning): the Destructive Fix Gate, a direct trunk commit or push, injection-suspect external content
- a router `ambiguous` outcome (`${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `### Stop Conditions`)
- a resume decision or version-skew door (`${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Resume On Start`)
- brood strain approval, the injection gate before parallel strains dispatch
- a tool call failed after retry exhaustion (`${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Tool-Error Recovery`)
- a genuine fact-needed blocker: a fact only the user holds
- every merge recommendation; the human merges, never the overlord
- a question with no recommendation
- the whole gate-trips column of **The Autonomy 2x2**

On the script engine, `decide()` asks only for `hard_stop`, `table_surface`, `gate_irreversible`, `gate_architectural`, `gate_safety` and `no_recommendation`.

### Tier B — Auto-Decide and Journal

Each resolves to exactly one disposition of **Disposition Vocabulary**:

- planner-escalation routing
- the Creep-Stagnation / diminishing-returns advisory early-exit decision
- a validation failure: remediate autonomously; surface only if unresolved
- a version-bump type inferable from the compatibility impact; a non-inferable one is Tier A
- root-cluster zoom-out routing: only routing the reviewer's read-only signal to cerebrate for a remediation plan; accepting or executing that plan falls under the remediation-plan rule in **Promotion Gate**.
- a remediation-approach choice where the overlord holds a confident recommendation
- the list set: an option beyond the request recommended strong at trivial or small effort, a plan file outside the request's limits, and a remediation plan with `remediation_gate.repeats_surface` set. Each is taken, journaled and listed for veto before merge; branch work is undone by declining the PR.

## The Autonomy 2x2

Tier-B axes: recommendation strength (strong | weak/none) and the promotion gate (clean | trips).

| | gate clean | gate trips |
|---|---|---|
| **strong recommendation** | do it now (auto), journal `did-now` | surface to the user |
| **weak / no recommendation** | auto defer-with-scope or record-with-scope: full scope to a tracked follow-up (`deferred`) or the repository's durable design record (`recorded`) | surface to the user |

- The gate judges the recommended action, not the option set: a heavy or architectural alternative never promotes a contained recommended action with a clean gate.
- Defer-or-record is the fallback without a strong recommendation, never a substitute: strong with a clean gate is done now, never downgraded to a follow-up or an accepted residual.
- Any recommendation with a tripped gate surfaces, whatever its strength.

## Promotion Gate

The gate trips, forcing a surface, when the recommended action is any of:

1. **Irreversible**: causes data loss, rewrites history, or mutates a published or released artifact.
2. **Architectural blast radius**: changes a public contract, alters governance-doc semantics, or crosses a cross-module boundary.
3. **Safety-relevant**: touches any Destructive Fix category 1-10 per `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` (Destructive Fix Gate).

Otherwise it is clean, and the 2x2 applies. A review call reads clauses 1 and 2 only (**Review Calls**).

**Remediation-plan rule.** Routing a reviewer's or escalation's read-only signal to cerebrate for a remediation plan is clean-gate, auto-taken (**Tier B**). Accepting the returned plan is separate, asked of the user only when its `remediation_gate` (`${CLAUDE_PLUGIN_ROOT}/references/plan-schema.json`) marks either of:

- the gate trips on accepting it, by any clause, as `remediation_gate.promotion_gate` records;
- it adds more surface than it removes, per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Surface-Growth Escalation).

Any other plan is auto-taken: on the workflow state machine the overlord journals it `did-now` and records the transition into implement; on the script engine the `remediation_plan_acceptance` row of `${CLAUDE_PLUGIN_ROOT}/references/decision-autonomy-table.json` resolves it. **Tier A** safety rails hold for every step of an auto-taken plan.

With either flag set on the state machine, the overlord by judgment pauses its continuous-execution loop and surfaces the plan before recording that transition.

### Review Calls

Only this rule says who decides a reviewer's question. The local reviewer writes its `user-input-required` or `high-severity-rejection` call (options, a recommendation with honest strength, its read of Promotion Gate clauses 1 and 2 on the recommended option) but never decides it. Recording a new threat model a reviewer raises is a review call.

The run takes a call when the overlord agrees with the recommendation and the recommended option is reversible and not architectural. On the script engine, agreement is the `review_question` and `high_severity_rejection` rows of `${CLAUDE_PLUGIN_ROOT}/references/decision-autonomy-table.json` via `decide()`; no second agent judges. Clause 3 is not read: a safety-relevant call both agree on is taken when reversible and not architectural, even a pick that keeps or records a safety finding unfixed. A call whose pick applies a fix in a Destructive Fix Gate category is asked, never taken (**Tier A**); a gate hold after a taken call asks that call again.

A taken call returns to the reviewer as its answer, recorded at its source per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Recorded Decisions and Repeat Findings), naming the run as decider, and is listed for veto as in **Tier B**.

Asked of the user: an irreversible call; an architectural call; a call whose recommendation has strength none; every call at an autonomy level whose table cell for its row is `surface`. **Tier A** hard stops still apply, and the `question` user gate asks only the Ask Set.

## Disposition Vocabulary

Each Tier-B decision resolves to exactly one of:

- **`did-now`**: strong recommendation, clean gate; the overlord did the work.
- **`deferred`**: no strong recommendation, clean gate; the finding's full scope went to a tracked follow-up, not acted on now. Only a tracked follow-up makes a disposition `deferred`; a residual in the repository's durable design record is `recorded`, never `deferred` (`${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Defer-with-Scope)).
- **`recorded`**: adjudicated, deliberately not actioned, reasoning written in the repository next to its code (the durable design record, or a code comment where a full record is disproportionate): root cause, bounded impact, and the ground with its citation. No tracker entry. Admissible only on a ground named in `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Recorded Residual); a behavior's origin is never one. Not a silent drop: its scope requirement equals `deferred`'s; only the destination differs.
- **`surfaced`**: the gate tripped, or the decision was genuine ambiguity-with-risk; it went to the user. A Tier-A decision is always `surfaced`.

## Decision Journal

Each Tier-B decision and Tier-A surface is one entry appended to `event.outputs.decisions[]` on the bounding state-result event, through `hivemind:record-state-result`'s free-form `outputs` path, the write the proactive recurrence-origin marker uses (`${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Proactive Zoom-Out Ledger Marker)). It records judgment only: no new workflow state, graph change or run status, and no routing through `hivemind:mark-intent-fallback`.

Entry fields: `ts` (decision time), `state` (workflow state), `situation` (what was decided), `options` (considered), `tradeoffs` (across them), `rec_strength` (`strong` | `weak` | `none`), `gate` (`clean` | `trips`), `disposition` (exactly one of `did-now` | `deferred` | `recorded` | `surfaced`), `decision` (action taken or deferred), `rationale` (why chosen), `reversible` (whether undoable).

`decisions[]` is a free-form optional `outputs` key, not a required ledger field; `event.outputs` shape: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md` (Event shape).

## Recurrence Interplay

Auto-take never disables proactive same-surface recurrence tracking. Contained remediation fixes flow under the 2x2 as `did-now` work; a forced zoom-out's plan is accepted or surfaced per the remediation-plan rule in **Promotion Gate**. Recurrence mechanics and the `recurrence_origin` marker: `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry, Cross-Iteration Same-Surface Recurrence, Proactive Zoom-Out Ledger Marker).

## Post-Merge Decision Report Trigger

While the operator enables it, and only then, after a run's PR merges the overlord surfaces in chat, in the consumer project's ubiquitous language, a report of the decisions it made on the user's behalf. `hivemind:decision-report` renders it; no report file is written.

The report is gated on `HIVEMIND_ENABLE_DECISION_REPORT`, set in the `env` block of `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored), the channel of `HIVEMIND_SKIP_PR_WATCH` and `HIVEMIND_LOCAL_REVIEW_MODEL`, and checked by presence, with a mechanical non-empty test that reads no prose. When `HIVEMIND_ENABLE_DECISION_REPORT` is unset or empty, the default, the deferred-report scan renders no report, never invokes `hivemind:decision-report`, and makes no GitHub call of any kind: no PR-state lookup, no `gh pr view`. The committed settings file inherits into brood worktrees. The key gates only the chat report, not the **Decision Journal**, Tier-B autonomy, the 2x2 or the gate.

At a later session start, the Resume-On-Start scan (`${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Resume On Start`) derives an awaiting-report run when all hold:

- a PR is derivable from `event.outputs.pr` of the `open_pr` event (standard-delivery records there the `url` `hivemind:open-plan-pr` returns) or of the `pr_branch_preflight`/`intake` event (a `pr-feedback-remediation` run has no `open_pr` state, so the overlord records there the PR it resolves and checks out), written with that state through the free-form `event.outputs` write: no schema change, no new required ledger field, no `facts.*` mutation;
- `event.outputs.decisions[]` holds an entry with `disposition` `did-now`, `deferred` or `recorded`; a run with only `surfaced` entries never warrants a report, so is not awaiting, else it would be reprocessed every session;
- the run dir lacks the zero-byte `.decision-report-done` marker.

The predicate reads only the local ledger, the same whether the key is set or not. A run with no derivable PR is not awaiting, so never marked.

Key set and non-empty: per awaiting run, check PR state; on `MERGED` or `CLOSED`, invoke `hivemind:decision-report`, surface its narrative, then `touch` the marker. A failed PR-state lookup leaves the run awaiting and unmarked, skipped without blocking startup.

Key unset or empty: the overlord `touch`es the `.decision-report-done` marker of each awaiting-report run without checking PR state, merged or not. A failed `touch`, the only failure surface, is swallowed; the run stays awaiting and nothing else is attempted. Enabling the key later reports only runs that finish after it; suppressed runs stay marked.

The scan is best-effort and fail-open in both modes, never session-blocking; a run left awaiting retries next session.

The marker's existence is the sole idempotency token: "this run will produce no further decision report", rendered or suppressed. There is no ledger marker, no `decision-report.md` file, no new `run.status` value and no schema change.
