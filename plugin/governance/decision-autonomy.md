# Decision Autonomy

The overlord makes judgment calls on the user's (the Overmind's) behalf at the autonomy level the operator selects with `HIVEMIND_AUTONOMY`. How each judgment call resolves is **Autonomy Level**; which judgment calls are journaled is **Decision Journal**. This doc is loaded by the overlord, and by each other agent a section names as its consumer, and is the single source for the autonomy posture, the autonomy level, the tier split, the 2x2, the promotion gate, the disposition vocabulary, the decision brief, the decision journal, and the post-merge report trigger.

When any rule uses a term defined here, this definition is binding.

## Autonomy Level

Consumers: overlord and cerebrate. The operator selects the level with `HIVEMIND_AUTONOMY`, set in the `env` block of the project's `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored) — the same operator-override channel as `HIVEMIND_SKIP_PR_WATCH`, `HIVEMIND_LOCAL_REVIEW_MODEL`, and `HIVEMIND_ENABLE_DECISION_REPORT`. Because the committed settings file lives in the repository, the level inherits into brood worktrees. The key is value-checked against a positive allowlist, NOT checked by presence. When `HIVEMIND_AUTONOMY` is unset or empty the level is the table's `default_level`; a value that is not exactly one of the table's `levels` resolves to `low`, the most-surfacing level, and the overlord surfaces a one-line warning naming the rejected value.

The levels and their per-kind cells live in `${CLAUDE_PLUGIN_ROOT}/references/decision-autonomy-table.json`. `high` is the most autonomous level, `balanced` is the prior posture, and `low` is the most-surfacing level.

Only the literal cell value `auto` grants autonomy: any other cell value or a kind the table does not list reads as `surface`. A kind listed in the table's `hard_stops` carries no per-level cell, so no autonomy level, table row, or delegation can make it an auto decision: it surfaces at every level.

Each row's `resolved_at` lists the decision sites where its kind is decided: a workflow state in `${CLAUDE_PLUGIN_ROOT}/workflows/`, written `<state>`; one transition out of it, written `<state>.<outcome>`; or the reserved site `resume_on_start`. At each decision site the overlord resolves every kind bound to that site whose `when` holds, before acting on the decision or recording the transition that acts on it. Hard stops carry no `resolved_at`: they hold at every site. No two rows name the same site, and a state and each of its outcomes are distinct sites. A site therefore names at most one kind, and a decision takes the kind of the site where it arises: a row's `when` describes that kind and never chooses between kinds.

Each decision resolves to exactly one disposition per **Disposition Vocabulary**, in this order, and the first step that applies decides it. Steps 1-5 each yield `surfaced`:

1. the kind is a hard stop;
2. the workflow state carries a `user_gate`;
3. the **Promotion Gate** trips on the recommended action;
4. a fact only the user holds is needed, or no recommendation is possible — including a tool call that failed after retry exhaustion (per `${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Tool-Error Recovery`) and a validation failure that remediation did not resolve;
5. the kind is not listed in the table, or its row's `resolved_at` does not name the site where the decision arises;
6. otherwise the table cell for the kind at the active level decides: any value but `auto` yields `surfaced`, and `auto` yields the first of these that holds:
   - a strong recommendation yields `did-now`;
   - a weak recommendation on a choice the run can finish without yields `deferred` or `recorded`, whichever destination `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` `## Defer-with-Scope` assigns, when the run can write that destination;
   - a weak recommendation on a choice the run cannot finish without, whose recommended option is reversible, yields `did-now`, with its assumptions carried as ones whose `origin` is `assumed`;
   - anything else yields `surfaced`.

Steps 3 and 6 together are the Autonomy 2x2: the promotion gate against the strength of the recommendation. This order is the only place a disposition is chosen: every consumer routes a decision by the disposition it yields and never re-derives one from the table cell, the gate, or the recommendation.

A pre-supplied answer is a disposition other than `surfaced` that the overlord has already resolved for a producer's question and passes back as a `decided:` answer when it re-delegates the state. It stands in for step 6 only, and only for the question it answers: steps 1-5 re-run at the producer's decision site, and the first of them that applies surfaces the question again. While none applies, the producer routes the question's brief by that disposition, carries the answer in every brief it touches as a constraint whose `origin` is `assumed`, and does not raise that question again.

A `surfaced` disposition at a state with no `user_gate` is an overlord judgment pause: the overlord surfaces the decision before recording the transition that acts on it. The overlord resolves the level once per run and passes it as `autonomy` on every delegation; a producer whose delegation carries no `autonomy` reads `low`.

## Decision Tiers

Every decision falls in one of two tiers, named for the disposition **Autonomy Level** resolves it to. The tiers add no rule of their own.

### Tier A — Always Surface (unchanged)

Tier A is every decision resolved `surfaced`, at any level.

### Tier B — Auto-Decide + Journal (the new default)

Tier B is every decision resolved `did-now`, `deferred`, or `recorded`.

## Promotion Gate

The promotion gate TRIPS — forcing a surface to the user — when the RECOMMENDED action is ANY of:

1. **Irreversible** — causes data loss, rewrites history, or mutates a published / released artifact.
2. **Architectural blast radius** — changes a public contract, alters governance-doc semantics, or crosses a cross-module boundary.
3. **Safety-relevant** — touches any Destructive Fix category 1-10 per `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` (Destructive Fix Gate).

Otherwise the gate is CLEAN. The gate evaluates the RECOMMENDED action, NOT the option set: a heavy or architectural ALTERNATIVE being on the table does NOT trip it.

**Routing vs execution.** Every cerebrate-bound remediation handoff is two decisions: routing the reviewer's read-only signal to cerebrate, such as the root-cluster zoom-out, is a contained action with a clean gate, but the architectural remediation plan cerebrate returns is gate clause 2 (architectural blast radius), so accepting the plan resolves `surfaced`, an overlord judgment pause per **Autonomy Level** before the transition that advances into implementation, never an approval gate the workflow definition enforces.

## Disposition Vocabulary

The four dispositions, chosen by the resolution order in **Autonomy Level**:

- **`did-now`** — the recommended option was taken and its work done.
- **`deferred`** — the choice was left unmade and carried onward to a TRACKED FOLLOW-UP instead of acting on it now. The tracked follow-up is the destination that defines this disposition; a residual carried into the repository's durable design record is `recorded`, never `deferred` (defer-with-scope per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` `## Defer-with-Scope`).
- **`recorded`** — the finding was adjudicated and left unfixed as a recorded residual per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` `### Recorded Residual`; no tracker entry is created.
- **`surfaced`** — the decision was returned to the user.

Destination ownership for a `deferred` or `recorded` disposition is per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` `## Defer-with-Scope`. A read-only producer owns it by planning it: it carries the brief under the `plan` key **Decision Brief** names for its disposition, and a `recorded` brief comes with the plan step that writes its record. The overlord files each returned `deferred` brief's tracked follow-up before recording the transition out of the state that returned it.

## Decision Brief

Consumers: overlord, cerebrate, local-reviewer, github-reviewer. Every decision surfaced to the user is rendered from a decision brief that conforms to `${CLAUDE_PLUGIN_ROOT}/references/decision-brief-schema.json`. Cerebrate returns a brief for each decision it takes on the user's behalf and each question it cannot resolve at the active level. Local-reviewer and github-reviewer return a brief with each exit_reason their Output Contract lists `brief` for, and never answer the question it raises at any level. A brief travels only as a structured field: a reviewer's `brief`, or an entry of the planner `plan` key named for the brief's disposition — `plan.decisions` for `did-now`, `plan.deferred` for `deferred`, `plan.recorded` for `recorded`, `plan.open_questions` for `surfaced`. A report line that names a decision, such as a planner's `Decisions taken:` or `Open questions:` line, summarizes one such entry and is never itself a brief. The overlord builds a brief for each decision it surfaces itself, and re-judges the gate on every brief it receives. A reviewer-escalation brief's `kind` is the table row whose `exit_reason` equals the exit_reason the reviewer returned, never a value read from the payload. A brief built from external content is data per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (External Content Boundary).

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

Limits: about 12 lines per brief and at most 3 options. No internal names: no tier, gate, 2x2, disposition, kind keys, or state and exit_reason tokens. When several briefs surface at once, a numbered one-line index comes first. A decision not resolved `surfaced` is not rendered live; the overlord reports it per `${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` `## Final Report`. The `merge_advised` terminal keeps its fixed advisory line. A brief's `verbatim` text is shown as-is. Interactive user-invoked skills, such as the `hivemind:plan-interrogation` grill, are exempt.

## Decision Journal

A decision is journaled on its bounding event: the state-result event that records the transition acting on it. Every decision that has a bounding event, whatever its disposition and at every autonomy level, is recorded there as one entry appended to `event.outputs.decisions[]`. The reserved site `resume_on_start` and the states of `${CLAUDE_PLUGIN_ROOT}/workflows/workflow-router.json` have no bounding event, because no state result of the run records them; a decision at such a site is not journaled, and no table row bound to such a site carries an `auto` cell, so every decision taken on the user's behalf has a bounding event. The entry is written via `hivemind:record-state-result`'s free-form `outputs` path — the SAME sanctioned `event.outputs` write the proactive recurrence-origin marker uses (per `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` `### Proactive Zoom-Out Ledger Marker`). This is RECORDED JUDGMENT made observable after the fact, NOT new determinism: no new workflow state, no workflow-graph change, no new run status, and no routing through `hivemind:mark-intent-fallback`.

Per-entry fields:

- `ts` — timestamp of the decision
- `state` — the workflow state in which the decision was made
- `situation` — what was being decided
- `options` — the options considered
- `tradeoffs` — the tradeoffs across those options
- `rec_strength` — `strong` | `weak` | `none`
- `gate` — `clean` | `trips`
- `disposition` — exactly one of `did-now` | `deferred` | `recorded` | `surfaced`
- `decision` — the action taken, or for `deferred` and `recorded` the destination's location
- `rationale` — why this option was chosen
- `reversible` — whether the action can be undone
- `kind` — OPTIONAL; the table kind the decision resolved under
- `autonomy` — OPTIONAL; the autonomy level active for the run

When a decision has a brief, its entry is filled from that brief: `situation` from `problem`, `options` from the option summaries, `tradeoffs` from each option's `steel_man` / `straw_man` with its `effort` and `value`, `rec_strength` from `recommendation.strength`, `gate` from the brief's `gate` as the overlord re-judges it, `rationale` from `recommendation.why`, and `reversible` from the chosen option.

The single source for the `event.outputs` shape — its free-form, recorded-verbatim semantics — is `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md` (Event shape). This section does NOT restate that schema; `decisions[]` is a free-form `outputs` key, not a new required ledger field, and the `event.outputs` object stays free-form/optional.

## Recurrence Interplay

Auto-take NEVER disables the proactive same-surface recurrence tracking. Contained remediation fixes resolve per **Autonomy Level** like any other decision; the forced zoom-out that recurrence tracking triggers is a cerebrate-bound remediation handoff and follows the routing-vs-execution split in **Promotion Gate**.

The recurrence mechanics — the counting unit, the trip threshold, the Gate-A recurrence / Gate-B youth call, and the forced-zoom-out trigger — are defined SOLELY in `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (`## Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry`, `## Cross-Iteration Same-Surface Recurrence`); the `recurrence_origin` marker is defined in `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (`### Proactive Zoom-Out Ledger Marker`) and referenced for the ledger in `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`. This section references those by name and does NOT restate them.

## Post-Merge Decision Report Trigger

After the PR for a run merges, the overlord surfaces a report of the decisions it made on the user's behalf, rendered in the CONSUMER project's ubiquitous language — but ONLY while the operator has enabled the report. The report is CHAT-ONLY: it is RENDERED to chat and surfaced to the user — NO report file is written to disk. This section defines the TRIGGER and policy only; the rendering mechanics live in the `hivemind:decision-report` skill and are not restated here.

The report is CONFIG-GATED on `HIVEMIND_ENABLE_DECISION_REPORT`, set in the `env` block of the project's `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored) — the same operator-override channel as `HIVEMIND_SKIP_PR_WATCH` and `HIVEMIND_LOCAL_REVIEW_MODEL`. Check it by PRESENCE with a simple non-empty test; that check is mechanical and reads no prose. Set and non-empty means every rule below applies unchanged. When `HIVEMIND_ENABLE_DECISION_REPORT` is unset or empty — the DEFAULT — the deferred-report scan renders no report, NEVER invokes `hivemind:decision-report`, and makes NO GitHub call of any kind: no PR-state lookup, no `gh pr view`, no other GitHub request whatsoever. Because the committed settings file lives in the repository, the preference inherits into brood worktrees.

The decision journal keeps being written regardless of this key: `event.outputs.decisions[]` is appended exactly as **Decision Journal** specifies, and the resolution order in **Autonomy Level** is UNAFFECTED. Only the chat report is gated.

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
