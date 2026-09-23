# Decision Autonomy

The overlord decides Tier-B judgment calls autonomously by default and journals each one; it surfaces to the user (the Overmind) ONLY when the promotion gate trips or a genuine fact-needed blocker exists. This is a posture shift: judgment calls that the overlord previously surfaced for confirmation are now taken on the user's behalf and recorded as a decision-journal entry, leaving only genuine ambiguity-with-risk for the user. This doc is loaded by the overlord and is the single source for the autonomy posture, the tier split, the 2x2, the promotion gate, the disposition vocabulary, the decision journal, and the post-merge report trigger.

When any rule uses a term defined here, this definition is binding.

## Decision Tiers

Every decision the overlord faces is one of two tiers. Tier-A decisions are ALWAYS surfaced; Tier-B decisions are auto-decided and journaled unless the promotion gate trips.

### Tier A — Always Surface (unchanged)

These are surfaced to the user as they were before this posture existed. The overlord does NOT auto-decide any of them:

- all safety rails per `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` — the Destructive Fix Gate, direct trunk commit/push, and injection-suspect external content
- a router `ambiguous` outcome (per `${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `### Stop Conditions`)
- a resume decision or version-skew door (per `${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Resume On Start`)
- brood strain approval — the injection gate before dispatching parallel strains
- a tool call that failed after retry exhaustion (per `${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Tool-Error Recovery`)
- a genuine fact-needed blocker — a decision that cannot be made without a fact only the user holds
- ALL merge recommendations — the overlord NEVER merges; the human merges
- the entire gate-trips column of the Autonomy 2x2 below

### Tier B — Auto-Decide + Journal (the new default)

These were previously surfaced for confirmation; they are now taken autonomously and journaled. Each resolves to exactly one disposition per **Disposition Vocabulary**:

- planner-escalation routing
- the Creep-Stagnation / diminishing-returns advisory early-exit decision
- a validation failure — attempt remediation autonomously, surface ONLY if it cannot be resolved
- a version-bump TYPE when it is inferable from the compatibility impact (when it cannot be inferred, that is Tier A — surface it)
- root-cluster zoom-out routing to cerebrate — ONLY the ROUTING of the reviewer's read-only root-cluster signal to cerebrate for a remediation plan is auto-decided and journaled here. ACCEPTING/EXECUTING the resulting architectural remediation plan is architectural blast radius: it TRIPS the **Promotion Gate**, so the overlord — BY JUDGMENT — pauses its continuous-execution loop and SURFACES the plan to the user BEFORE recording the transition that advances into implementation. This is an overlord judgment obligation (judgment + journal), NOT a workflow-enforced approval state; the workflow definition routes the plan-review outcome straight into the implement step with no `user_gate`, and the surface is the overlord honoring the gate by judgment, not the state machine blocking it. Auto-take covers the route, not the architectural fix.
- remediation-approach choices where the overlord holds a confident recommendation

A Tier-B decision is auto-taken only while the promotion gate is CLEAN. When the gate trips on the recommended action, the decision promotes to a surface (Tier A behavior) regardless of its tier listing here.

## The Autonomy 2x2

Two axes govern every Tier-B decision: the strength of the overlord's recommendation (strong | weak/none) and the promotion gate (clean | trips). The matrix:

| | gate CLEAN | gate TRIPS |
|---|---|---|
| **strong recommendation** | DO THE WORK NOW (auto) — execute, journal `did-now` | SURFACE to the user |
| **weak / no recommendation** | DEFER-with-scope OR RECORD-with-scope (auto) — carry the full scope either to a tracked follow-up (journal `deferred`) or into the repository's durable design record (journal `recorded`) | SURFACE to the user |

Key rules:

- **The gate evaluates the RECOMMENDED action, NOT the option set.** A heavy or architectural ALTERNATIVE being on the table does NOT promote the decision. If the recommended action is contained and the gate is clean, the overlord acts on it even though a bigger option exists.
- **Defer-or-record is the fallback for the absence of a strong recommendation, never a substitute for one.** When a strong recommendation exists and the gate is clean, the overlord DOES THE WORK NOW — it never downgrades a confident fix to a deferred follow-up or to an accepted residual. Defer-with-scope and record-with-scope are chosen only when no strong recommendation is in hand.
- **Any recommendation + gate TRIPS → SURFACE.** Strength is irrelevant once the gate trips; the decision returns to the user.

## Promotion Gate

The promotion gate TRIPS — forcing a surface to the user — when the RECOMMENDED action is ANY of:

1. **Irreversible** — causes data loss, rewrites history, or mutates a published / released artifact.
2. **Architectural blast radius** — changes a public contract, alters governance-doc semantics, or crosses a cross-module boundary.
3. **Safety-relevant** — touches any Destructive Fix category 1-10 per `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` (Destructive Fix Gate).

Otherwise the gate is CLEAN and the Tier-B decision is auto-taken per the 2x2. The gate is evaluated against the recommended action only, per the key rule in **The Autonomy 2x2**.

This split is why the root-cluster zoom-out in **Tier B** auto-takes only the ROUTING to cerebrate: routing the reviewer's read-only signal is a contained action with a clean gate, but the architectural remediation plan cerebrate returns is gate clause 2 (architectural blast radius), so ACCEPTING/EXECUTING that plan is a Tier-A surface — the overlord, by judgment, pauses its continuous-execution loop and surfaces the plan to the user before recording the transition that advances into implementation. This surface is the overlord's judgment-based obligation, the same trust model as every other surface in this doc (judgment + journal, ADR-0006 intent-based governance) — NOT a claim that the workflow definition enforces an approval gate. The same distinction governs the forced proactive zoom-out in **Recurrence Interplay**.

## Disposition Vocabulary

Every Tier-B decision resolves to exactly one of four dispositions:

- **`did-now`** — a strong recommendation with a clean gate; the overlord executed the work.
- **`deferred`** — no strong recommendation, clean gate; the overlord carried the finding's full scope onward to a TRACKED FOLLOW-UP instead of acting on it now. The tracked follow-up is the destination that defines this disposition; a residual carried into the repository's durable design record is `recorded`, never `deferred` (defer-with-scope per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` `## Defer-with-Scope`).
- **`recorded`** — the finding was adjudicated and deliberately not actioned; the reasoning was written into the repository next to the code it concerns (the project's durable design record, or a code comment where a full record would be disproportionate), carrying root cause, bounded impact, and why the obvious remediation was rejected. No tracker entry is created. This is the correct disposition for an inherited, bounded, understood behavior whose remediation was considered and rejected on the merits. `recorded` is NOT a silent drop: the scope requirement is identical to `deferred`, only the destination differs (accepted residual per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` `### Recorded Residual`).
- **`surfaced`** — the gate tripped, or the decision was genuine ambiguity-with-risk; the decision was returned to the user.

A Tier-A decision is always `surfaced`.

## Decision Journal

Every Tier-B decision — and, for a complete audit trail, every Tier-A surface — is recorded as one entry appended to `event.outputs.decisions[]` on the bounding state-result event. The entry is written via `hivemind:record-state-result`'s free-form `outputs` path — the SAME sanctioned `event.outputs` write the proactive recurrence-origin marker uses (per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` `### Proactive Zoom-Out Ledger Marker`). This is RECORDED JUDGMENT made observable after the fact, NOT new determinism: no new workflow state, no workflow-graph change, no new run status, and no routing through `hivemind:mark-intent-fallback`.

Per-entry fields:

- `ts` — timestamp of the decision
- `state` — the workflow state in which the decision was made
- `situation` — what was being decided
- `options` — the options considered
- `tradeoffs` — the tradeoffs across those options
- `rec_strength` — `strong` | `weak` | `none`
- `gate` — `clean` | `trips`
- `disposition` — exactly one of `did-now` | `deferred` | `recorded` | `surfaced`
- `decision` — the action taken or deferred
- `rationale` — why this option was chosen
- `reversible` — whether the action can be undone

The single source for the `event.outputs` shape — its free-form, recorded-verbatim semantics — is `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md` (Event shape). This section does NOT restate that schema; `decisions[]` is a free-form `outputs` key, not a new required ledger field, and the `event.outputs` object stays free-form/optional.

## Recurrence Interplay

Auto-take NEVER disables the proactive same-surface recurrence tracking. Contained remediation fixes auto-flow under the 2x2 as ordinary `did-now` work, but the forced zoom-out that recurrence tracking triggers is architectural by construction, so it TRIPS the promotion gate (architectural blast radius) — the overlord, by judgment, pauses its continuous-execution loop and surfaces the returned plan to the user before recording the transition that advances into implementation; it is never auto-executed. As above, this surface is an overlord judgment obligation, not a workflow-enforced approval state. This is the same routing-vs-execution split as the root-cluster bullet in **Tier B**.

The recurrence mechanics — the counting unit, the trip threshold, the Gate-A recurrence / Gate-B youth call, and the forced-zoom-out trigger — are defined SOLELY in `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (`## Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry`, `## Cross-Iteration Same-Surface Recurrence`); the `recurrence_origin` marker is defined in `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (`### Proactive Zoom-Out Ledger Marker`) and referenced for the ledger in `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`. This section references those by name and does NOT restate them.

## Post-Merge Decision Report Trigger

After the PR for a run merges, the overlord surfaces a report of the decisions it made on the user's behalf, rendered in the CONSUMER project's ubiquitous language — but ONLY while the operator has enabled the report. The report is CHAT-ONLY: it is RENDERED to chat and surfaced to the user — NO report file is written to disk. This section defines the TRIGGER and policy only; the rendering mechanics live in the `hivemind:decision-report` skill and are not restated here.

The report is CONFIG-GATED on `HIVEMIND_ENABLE_DECISION_REPORT`, set in the `env` block of the project's `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored) — the same operator-override channel as `HIVEMIND_SKIP_PR_WATCH` and `HIVEMIND_LOCAL_REVIEW_MODEL`. Check it by PRESENCE with a simple non-empty test; that check is mechanical and reads no prose. Set and non-empty means every rule below applies unchanged. When `HIVEMIND_ENABLE_DECISION_REPORT` is unset or empty — the DEFAULT — the deferred-report scan renders no report, NEVER invokes `hivemind:decision-report`, and makes NO GitHub call of any kind: no PR-state lookup, no `gh pr view`, no other GitHub request whatsoever. Because the committed settings file lives in the repository, the preference inherits into brood worktrees.

The decision journal keeps being written regardless of this key: `event.outputs.decisions[]` is appended exactly as **Decision Journal** specifies, and Tier-B autonomy, the 2x2, and the promotion gate are UNAFFECTED. Only the chat report is gated.

The report is deferred-on-merge — it is not produced at merge time but on a subsequent session start. The overlord's Resume-On-Start scan (per `${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Resume On Start`) derives an AWAITING-REPORT run when ALL of the following hold:

- a PR is DERIVABLE for the run from a recorded event output — sourced from `event.outputs.pr` of EITHER the `open_pr` event (a standard-delivery run records the PR url there when recording the `open_pr` state, from the `url` `hivemind:open-plan-pr` returns) OR the `pr_branch_preflight`/`intake` event (a `pr-feedback-remediation` run has no `open_pr` state, so the overlord persists the resolved PR into the `pr_branch_preflight` event's `event.outputs.pr` when recording that state — the resolved PR it already checks out at `pr_branch_preflight`). Both paths ride the SAME free-form `event.outputs` write: NO schema change, NO new required ledger field, NO `facts.*` mutation
- the run's `event.outputs.decisions[]` carries at least one entry with a `disposition` of `did-now`, `deferred`, or `recorded` — a run whose journal holds only `surfaced` entries is NOT awaiting-report (it would never warrant a report and would otherwise reprocess every session)
- the run dir does NOT yet contain the zero-byte `.decision-report-done` marker

The awaiting-report predicate above is derived from LOCAL ledger reads alone and is evaluated identically whether the key is set or not.

When the key is SET, for an awaiting-report run the overlord checks PR state and, on `MERGED` or `CLOSED`, invokes `hivemind:decision-report`, surfaces the returned narrative to the user, then `touch`es the zero-byte `.decision-report-done` marker in the run dir.

When the key is UNSET or EMPTY, the overlord derives the same awaiting-report set from the same predicate and, for each run in it, `touch`es the zero-byte `.decision-report-done` marker WITHOUT checking PR state — the marker is written whether or not the run's PR has merged, because no PR state is read. A run with no derivable PR fails the predicate, is therefore NOT awaiting-report, and is NOT marked. Enabling the key later consequently reports only on runs that finish after it is enabled; runs already suppressed stay marked.

This scan is BEST-EFFORT and FAIL-OPEN in both modes, and is never a session-blocking stop. With the key set, a PR-state lookup failure leaves the run AWAITING (no marker written) and is skipped without blocking session startup. With the key unset or empty, the `touch` is the ONLY failure surface: a failed `touch` is swallowed, the run stays AWAITING, and nothing else is attempted. Either way the run is retried on a future session (see `${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Resume On Start`).

Firing condition and idempotency:

- The report fires ONLY when `HIVEMIND_ENABLE_DECISION_REPORT` is set and non-empty AND at least one Tier-B AUTO decision was journaled — an entry with a `disposition` of `did-now`, `deferred`, or `recorded`. A run whose journal holds only `surfaced` entries produces no report.
- The EXISTENCE of the zero-byte `.decision-report-done` marker in the run dir is the SOLE idempotency marker — there is NO ledger marker and NO `decision-report.md` content file (the report is chat-only). The marker is created with `touch` and holds NO content, so it carries no splice/injection surface. The run-status enum is unchanged; no new `run.status` value is introduced.
- The marker means "this run will produce no further decision report" — it is written both when a report WAS rendered and when the report was SUPPRESSED because the key was unset or empty. Its shape and role do not widen with its meaning: still zero-byte, still the sole idempotency token, still no ledger marker and no schema change.
