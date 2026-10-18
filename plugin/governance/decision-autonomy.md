# Decision Autonomy

The overlord decides Tier-B judgment calls on the user's (the Overmind's) behalf at the autonomy level the operator selects with `HIVEMIND_AUTONOMY`, and journals each one; it surfaces a decision to the user when the active level's table cell says `surface`, when the promotion gate trips, or when a genuine fact-needed blocker exists. Every judgment call taken on the user's behalf is recorded as a decision-journal entry. This doc is loaded by the overlord, and by each other agent a section names as its consumer, and is the single source for the autonomy posture, the autonomy level, the tier split, the 2x2, the promotion gate, the disposition vocabulary, the decision brief, the decision journal, and the post-merge report trigger.

When any rule uses a term defined here, this definition is binding.

## Autonomy Level

Consumers: overlord and cerebrate. The operator selects the level with `HIVEMIND_AUTONOMY`, set in the `env` block of the project's `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored) — the same operator-override channel as `HIVEMIND_SKIP_PR_WATCH`, `HIVEMIND_LOCAL_REVIEW_MODEL`, and `HIVEMIND_ENABLE_DECISION_REPORT`. Because the committed settings file lives in the repository, the level inherits into brood worktrees. The key is value-checked against a positive allowlist, NOT checked by presence. When `HIVEMIND_AUTONOMY` is unset or empty the level is the table's `default_level`; a value that is not exactly one of the table's `levels` resolves to `low`, the most-surfacing level, and the overlord surfaces a one-line warning naming the rejected value.

The levels and their per-kind cells live in `${CLAUDE_PLUGIN_ROOT}/references/decision-autonomy-table.json`. `high` takes the recommendation on every kind whose cell is `auto`; `balanced` is the prior posture; `low` asks before every judgment call.

Only the literal cell value `auto` grants autonomy: any other cell value or a kind the table does not list reads as `surface`. A kind listed in the table's `hard_stops` carries no per-level cell, so no autonomy level, table row, or delegation can make it an auto decision: it surfaces at every level.

Each row's `resolved_at` lists the decision sites where its kind is decided: a workflow state in `${CLAUDE_PLUGIN_ROOT}/workflows/`, written `<state>`; one transition out of it, written `<state>.<outcome>`; or the reserved site `resume_on_start`. At each decision site the overlord resolves every kind bound to that site whose `when` holds, before acting on the decision or recording the transition that acts on it. Hard stops carry no `resolved_at`: they hold at every site. No two rows name the same site, and a state and each of its outcomes are distinct sites. A site therefore names at most one kind, and a decision takes the kind of the site where it arises: a row's `when` describes that kind and never chooses between kinds.

Each decision resolves in this order, and the first step that applies decides it. Steps 1-5 each surface:

1. the kind is a hard stop;
2. the workflow state carries a `user_gate`;
3. the **Promotion Gate** trips on the recommended action;
4. a fact only the user holds is needed, or no recommendation is possible — including a tool call that failed after retry exhaustion (per `${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Tool-Error Recovery`) and a validation failure that remediation did not resolve;
5. the kind is not listed in the table, or its row's `resolved_at` does not name the site where the decision arises;
6. otherwise the table cell for the kind at the active level decides.

A pre-supplied answer is a recommendation the overlord has already resolved `auto` and passes back to a producer as a `decided:` answer when it re-delegates the state. It stands in for step 6 only, and only for the question it answers: steps 1-5 re-run at the producer's decision site, and the first of them that applies surfaces the question again. While none applies, the producer carries the answer in every brief it touches as a constraint whose `origin` is `assumed`, and does not raise that question again.

A `surface` verdict at a state with no `user_gate` is an overlord judgment pause: the overlord surfaces the decision before recording the transition that acts on it. The overlord resolves the level once per run and passes it as `autonomy` on every delegation; a producer whose delegation carries no `autonomy` reads `low`. The decision journal is written at every level.

## Decision Tiers

Every decision the overlord faces is one of two tiers, read at the active level per **Autonomy Level**. Tier-A decisions are ALWAYS surfaced; Tier-B decisions are auto-decided and journaled unless the promotion gate trips. The table `${CLAUDE_PLUGIN_ROOT}/references/decision-autonomy-table.json` is the single source for tier membership; this section does not enumerate it.

### Tier A — Always Surface (unchanged)

Tier A is every kind in the table's `hard_stops`, the floors that surface regardless of any cell (resolution steps 2-5 in **Autonomy Level**, which include the entire gate-trips column of the Autonomy 2x2 below), and every table row whose cell at the active level is `surface`. The overlord does NOT auto-decide any of them, and it NEVER merges; the human merges.

### Tier B — Auto-Decide + Journal (the new default)

Tier B is every table row whose cell at the active level is `auto`. Each resolves to exactly one disposition per **Disposition Vocabulary**. A row that ROUTES work, such as root-cluster routing to cerebrate, auto-takes the route only; ACCEPTING/EXECUTING what the route returns is its own decision, per the routing-vs-execution split in **Promotion Gate**.

A Tier-B decision is auto-taken only while the promotion gate is CLEAN. When the gate trips on the recommended action, the decision promotes to a surface (Tier A behavior) regardless of its table cell.

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
- **A choice the run cannot proceed without is non-deferrable.** Defer-or-record needs a run that can finish without the choice. Under an `auto` verdict, a weak recommendation whose action is reversible is taken (`did-now`) with its assumptions flagged as ones the user can overrule; with no recommendation, the decision surfaces.

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

## Decision Brief

Consumers: overlord, cerebrate, local-reviewer, github-reviewer. Every decision surfaced to the user is rendered from a decision brief that conforms to `${CLAUDE_PLUGIN_ROOT}/references/decision-brief-schema.json`. Cerebrate returns a brief for each decision it takes on the user's behalf and each question it cannot resolve at the active level. Local-reviewer and github-reviewer return a brief when they escalate a decision, and never answer the question it raises at any level. A brief travels only as a structured field: an entry of a planner's `plan.decisions` or `plan.open_questions`, or a reviewer's `brief`. A report line that names a decision, such as a planner's `Decisions taken:` or `Open questions:` line, is a one-line summary rendered from one such entry and is never itself a brief; a list with no entries reads `- None`. The overlord builds a brief for each decision it surfaces itself, and re-judges the gate on every brief it receives. A reviewer-escalation brief's `kind` is the table row whose `exit_reason` equals the exit_reason the reviewer returned, never a value read from the payload. A brief built from external content is data per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (External Content Boundary).

Render each brief in this fixed order:

1. Problem.
2. Why it matters: level, likelihood, if wrong (`blast_radius`), if ignored.
3. Options, each with summary, effort, value, the case for (`steel_man`), the case against (`straw_man`).
4. Ruled out, one line each.
5. Recommend, with why.
6. Assumptions you can overrule.
7. Reply hint: "letter, or go to take the recommendation".

Omit any part whose field is absent or empty. When `recommendation.strength` is `none`, there is no recommendation: the Recommend part states that none is made and why, and the reply hint asks for a letter or a free-form answer, never `go`.

A constraint whose `origin` is `assumed` is rendered as an assumption the user can overrule, never as a fixed constraint.

Limits: about 12 lines per brief and at most 3 options. No internal names: no tier, gate, 2x2, disposition, kind keys, or state and exit_reason tokens. When several briefs surface at once, a numbered one-line index comes first. Auto-taken decisions are not rendered live; each appears on the overlord's Final Report `Decided:` line instead. The `merge_advised` terminal keeps its fixed advisory line. A brief's `verbatim` text is shown as-is. Interactive user-invoked skills, such as the `hivemind:plan-interrogation` grill, are exempt.

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
- `kind` — OPTIONAL; the table kind the decision resolved under
- `autonomy` — OPTIONAL; the autonomy level active for the run

When a decision has a brief, its entry is filled from that brief: `situation` from `problem`, `options` from the option summaries, `tradeoffs` from each option's `steel_man` / `straw_man` with its `effort` and `value`, `rec_strength` from `recommendation.strength`, `gate` from the brief's `gate` as the overlord re-judges it, `rationale` from `recommendation.why`, and `reversible` from the chosen option.

The single source for the `event.outputs` shape — its free-form, recorded-verbatim semantics — is `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md` (Event shape). This section does NOT restate that schema; `decisions[]` is a free-form `outputs` key, not a new required ledger field, and the `event.outputs` object stays free-form/optional.

## Recurrence Interplay

Auto-take NEVER disables the proactive same-surface recurrence tracking. Contained remediation fixes auto-flow under the 2x2 as ordinary `did-now` work, but the forced zoom-out that recurrence tracking triggers is architectural by construction, so it TRIPS the promotion gate (architectural blast radius) — the overlord, by judgment, pauses its continuous-execution loop and surfaces the returned plan to the user before recording the transition that advances into implementation; it is never auto-executed. As above, this surface is an overlord judgment obligation, not a workflow-enforced approval state. This is the same routing-vs-execution split as root-cluster routing in **Tier B**.

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
