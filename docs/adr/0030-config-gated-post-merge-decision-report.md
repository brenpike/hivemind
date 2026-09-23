# The post-merge decision report is opt-in behind a presence-checked env key

**Status:** accepted — 2026-09-23

## Context

ADR-0026 (Decision 5, as widened by its 2026-09-18 amendment) makes the post-merge decision report UNCONDITIONAL: every run that journaled at least one `did-now`, `deferred`, or `recorded` decision produces a chat report on the next session start after its PR reaches `MERGED` or `CLOSED`. That rule was the structural mitigation for the autonomy shift — oversight moved from synchronous confirmation to asynchronous recounting, and the report was the thing being recounted.

In practice the operator does not want the recounting delivered unsolicited. A session that opens to do new work is greeted instead by a narrative of decisions taken during a previous, already-merged run. The report is long by construction — situation, options, trade-offs, decision, why, per decision, in the consumer project's domain language — and it arrives at the moment the operator's attention is on something else. Delivered that way it reads as noise rather than oversight.

The audit trail itself is not the problem and is not in question. The decision journal (`event.outputs.decisions[]`) is written regardless, persists in the ledger, and is readable on demand. What ADR-0026 assumed is that the journal needs a PUSH channel to be useful. That assumption is what this record revises: the journal is the audit trail, and the chat report is one presentation of it that an operator may or may not want automatically delivered.

This record AMENDS ADR-0026's always-report rule. ADR-0026 is a historical record and is deliberately left unedited; where the two disagree on whether the report fires, this record governs.

## Findings

- **The report is the only unsolicited push in the resume path.** Everything else the Resume-On-Start scan does is either silent or answers a question the operator asked. The deferred-report scan is the one branch that produces unrequested chat output, and it produces the longest output of any branch.
- **The scan's only external dependency is the PR-state check.** Deriving the awaiting-report set is entirely local: read the run dirs, read the persisted PR event output, read the journal, check for the marker. The GitHub call exists solely to answer "has this PR merged or closed yet?" — which is only needed because a report is about to be rendered.
- **This repository already has an operator-override channel with two occupants.** `HIVEMIND_LOCAL_REVIEW_MODEL` (ADR-0022) and `HIVEMIND_SKIP_PR_WATCH` (ADR-0029, Decision 1) are both set in the `env` block of `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored, per-account). Because the committed settings file is in-repo, keys set there INHERIT into brood worktrees — the case where no human is present in the session at all.
- **`.decision-report-done` is a zero-byte presence marker, not a status record.** ADR-0026 Decision 5 makes its EXISTENCE the sole idempotency signal. Nothing reads its contents, and no ledger field, `run.status` value, or content file mirrors it. That gives the marker room to carry a slightly wider meaning without any schema consequence.

## Decision

### 1. The report becomes opt-in, off by default

The post-merge decision report fires only when `HIVEMIND_ENABLE_DECISION_REPORT` is set. Unset or empty — the default for every consumer that does nothing — means no report.

The justification is that the journal already provides the audit trail ADR-0026 was protecting. Turning the report off removes a delivery channel, not the record. An operator who wants the recounting sets one key; an operator who does not gets a quiet session start, and the decisions taken on their behalf remain fully reconstructable from the ledger.

Tier-B autonomy is UNTOUCHED. The tier membership lists, the Autonomy 2x2, the promotion gate, the disposition vocabulary, and the journal entry shape are all exactly as ADR-0026 and its amendments leave them. Journaling is unconditional and does not consult the key. This record gates ONE thing: whether the chat report is rendered.

### 2. The channel is a presence-checked env key on the existing operator-override path

`HIVEMIND_ENABLE_DECISION_REPORT` is set in the `env` block of `.claude/settings.json` or `.claude/settings.local.json` — the same channel as `HIVEMIND_SKIP_PR_WATCH` and `HIVEMIND_LOCAL_REVIEW_MODEL`, and it inherits into brood worktrees for the same reason.

It is checked by PRESENCE, with a simple non-empty test. No value parsing, no truthiness vocabulary, no enumerated accepted strings. This matches `HIVEMIND_SKIP_PR_WATCH` exactly, and it is the property that makes the check mechanical rather than interpretive: a key is present or it is not, and there is no third reading.

### 3. The key is named `HIVEMIND_ENABLE_DECISION_REPORT`, not `HIVEMIND_DECISION_REPORT`

A presence-only check on a bare-noun key is a trap. An operator who writes `HIVEMIND_DECISION_REPORT=off` — or `false`, or `0`, or `no` — is stating an intent to DISABLE, and a presence check reads that as ENABLE. The key would then do the opposite of what its own value says, and the failure is silent.

Putting the verb in the name closes that gap: `HIVEMIND_ENABLE_DECISION_REPORT=<anything>` reads as "enable the decision report" for every value an operator could plausibly write, including the confused ones. The name and the check agree. This is the same construction `HIVEMIND_SKIP_PR_WATCH` uses — a verb in the key, presence as the signal.

### 4. While off, the scan still runs locally and still leaves the marker

With the key unset, the deferred-report scan renders NOTHING, never invokes `hivemind:decision-report`, and makes NO GitHub call of any kind. It nevertheless still derives the awaiting-report set from local ledger reads using the SAME predicate as the on path — a derivable PR event output, a journal holding at least one `did-now` / `deferred` / `recorded` entry, and no `.decision-report-done` marker — and unconditionally `touch`es the zero-byte marker for each awaiting run. No PR-state check is performed, because the marker is being written regardless of what that check would return.

The reason is backlog containment. If the off path left no marker, every run completed while the report was off would stay awaiting-report indefinitely, and the first session after an operator enables the key would deliver a flood of reports for work merged weeks earlier — the exact unsolicited-noise failure this record exists to fix, concentrated into one session. Marking as we go means enabling the key produces reports for runs that finish AFTERWARD, which is what "turn the report on" should mean.

The same mechanism discharges the existing backlog: the first session after this change lands, with the toggle off, marks every currently-awaiting run done and produces no output. The upgrade is quiet by construction.

**The marker's meaning widens.** `.decision-report-done` now asserts "this run will produce no further decision report" — whether because the report was rendered or because it was suppressed while the feature was off. It remains zero-byte, remains the SOLE idempotency token, and carries no ledger field, no schema change, and no `run.status` value. Nothing reads its contents, so the widened meaning costs nothing structurally.

**Fail-open behavior is unchanged.** The scan never blocks a session start. On the off path the only failure surface is the `touch` itself; a failed `touch` leaves the run awaiting-report, which is the pre-existing state and self-corrects on the next scan.

### 5. Recorded residual: a still-open PR can be marked done while the report is off

The off-path `touch` is unconditional, so a run whose PR is still OPEN gets marked done. If the operator enables the key before that PR merges, the run will never report — its marker already says otherwise.

This is ACCEPTED, and recorded per the **Recorded Residual** clause of `plugin/governance/remediation-doctrine.md`.

- **Root cause.** The off path deliberately makes no GitHub call, so it cannot distinguish an open PR from a merged one. Marking unconditionally is the only option consistent with that constraint.
- **Bounded impact.** The loss is one chat rendering for runs that straddle the moment the operator flips the key on. The run's decision journal is untouched and stays readable in the ledger — the audit trail survives in full, only the push delivery is missed, and only for the straddling window.
- **Obvious remediation considered and rejected.** Gate the off-path `touch` on the PR being terminal. That reintroduces a per-run GitHub call on the off path, which is precisely the cost the off path exists to avoid: an operator who has turned the feature OFF would still pay a network round trip per awaiting run at every session start, forever, to preserve a report they have declined to receive. Paying a standing cost on the disabled path to protect an edge of the enabled path is the wrong trade.

### 6. The `hivemind:decision-report` skill needs no change

The skill owns RENDERING mechanics — how a journal becomes narrative in the consumer project's domain language. It does not own FIRING POLICY, which is single-sourced in `plugin/governance/decision-autonomy.md` (`## Post-Merge Decision Report Trigger`). Gating happens at the caller, before invocation. A skill that is never invoked needs no knowledge of why.

Keeping the gate out of the skill also preserves the skill's usefulness as a manual tool: an operator running it directly against a run gets the report, regardless of the key.

## Considered Options

| Option | Rejected because |
|---|---|
| An opt-OUT key (`HIVEMIND_SKIP_DECISION_REPORT`), report on by default | Leaves the default noisy, which is the entire complaint. An operator who has never heard of the key still gets unsolicited reports, and the many-consumer default is the case that matters |
| A bare-noun key `HIVEMIND_DECISION_REPORT` with a presence check | `=off` / `=false` / `=0` would ENABLE the report — the key would contradict its own value, silently. Either the name gets a verb or the check must parse values, and parsing values abandons the presence-check simplicity shared with `HIVEMIND_SKIP_PR_WATCH` |
| Parse the key's value (`true`/`false`/`1`/`0`) instead of checking presence | Invents a truthiness vocabulary this repo does not otherwise have, and every accepted-string list is a fixture waiting to be extended by the next value someone types. Presence is total over all inputs |
| While off, leave no marker | The awaiting-report set grows unbounded, and enabling the key floods one session with reports for long-merged work — the same unsolicited-noise failure, concentrated. It also leaves no way to land this change quietly, since the existing backlog would sit primed |
| While off, check PR state before marking | Reintroduces a per-run GitHub call on the path whose defining property is making none. A standing network cost on the disabled path, paid to protect a straddling-window edge of the enabled path |
| Delete the report feature outright | Loses real value for operators who DO want the asynchronous recounting, and discards the ADR-0026 mitigation entirely rather than making it elective. The objection was to unsolicited delivery, not to the report |
| Presence-checked `HIVEMIND_ENABLE_DECISION_REPORT`, off by default, unconditional off-path marker (CHOSEN) | — |

## Consequences

- **The default session start is quiet.** No consumer sees a decision report unless an operator sets the key. The first session after this change lands discharges the existing awaiting backlog silently.
- **The off path makes zero GitHub calls.** The deferred-report scan becomes purely local reads plus a `touch` per awaiting run. Session start gets cheaper for every consumer running the default.
- **The audit trail is unchanged.** Journaling is unconditional; `event.outputs.decisions[]` is written exactly as before. Oversight moves from pushed to pulled, not from present to absent.
- **Tier-A and Tier-B behavior are untouched.** No tier membership, gate, disposition, or journal field changes. ALL merge recommendations remain Tier-A and always surfaced.
- **ADR-0026's always-report rule is amended, not deleted.** The AWAITING-REPORT predicate survives verbatim and still governs which runs the scan considers; what changes is what happens to an awaiting run when the key is absent. ADR-0026 stays unedited as historical record.
- **The override channel now carries three keys.** `HIVEMIND_LOCAL_REVIEW_MODEL`, `HIVEMIND_SKIP_PR_WATCH`, and `HIVEMIND_ENABLE_DECISION_REPORT` share one `env`-block convention, one settings-file pair, and one brood-inheritance property.
- **Enabling the key mid-life reports forward only.** Runs marked while off stay marked. An operator enabling the report gets it for runs that complete afterward, and the straddling-window residual in Decision 5 applies to runs whose PRs were open at the moment of the flip.

References: `plugin/governance/decision-autonomy.md` (`## Post-Merge Decision Report Trigger`), `plugin/governance/remediation-doctrine.md` (`### Recorded Residual`), `plugin/agents/overlord.md`, `plugin/skills/decision-report/`, `CLAUDE.md`; amends ADR-0026 Decision 5; follows the operator-override precedent of ADR-0022 and ADR-0029.
