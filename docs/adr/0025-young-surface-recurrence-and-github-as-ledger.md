# Young-surface recurrence as a hard gate; GitHub as the recurrence ledger

**Status:** accepted — 2026-06-09

## Context

ADR-0023 established `plugin/governance/remediation-doctrine.md` as the authoritative runtime home for root-cluster detection vocabulary and policy. That doctrine introduced **Cross-Iteration Same-Surface Recurrence** as a second clustering axis — orthogonal to the within-pass fix-framing axis — but left two load-bearing architectural choices implicit: (1) whether surface age should be a hard gate or a soft heuristic on the cross-iteration escalation path, and (2) where the per-surface recurrence counter should live.

Issue #273 extended the doctrine to operationalize both choices. The decisions below are the ones that are hard-to-reverse, surprising-without-context, and carry a genuine trade-off; the normative mechanics — thresholds, acceptance-test wording, reconstruction formula — live exclusively in `plugin/governance/remediation-doctrine.md` as the authoritative runtime home (P20). This ADR records the decisions and rationale; the governance doc executes them. The pointer is one-way ADR → governance.

## Decision

1. **Youth is a HARD GATE (AND'd requirement) on cross-iteration recurrence escalation, not a soft heuristic.** A surface qualifies for the cross-iteration zoom-out path only when it was introduced or heavily modified in the same PR or initiative. A surface that does not satisfy this gate — mature or legacy code — routes instead to the bounded-tail merge-advisory path regardless of how many times it re-emits findings. The authoritative runtime statement of both paths lives in `plugin/governance/remediation-doctrine.md` ("Cross-Iteration Same-Surface Recurrence" and "Bounded-Tail vs Recurring-Class Disambiguation").

2. **GitHub is the recurrence ledger; there is NO persisted local recurrence file.** The per-surface non-closing-structural-fix counter is reconstructed each loop from GitHub ground truth. The reconstruction formula and counter persistence semantics live in `plugin/governance/remediation-doctrine.md` ("Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry") as the authoritative home.

## Considered Options

### Decision 1 — surface age as gate vs. alternatives

| Option | Rejected because |
|---|---|
| Apply cross-iteration recurrence escalation to ALL surfaces regardless of age | Stable, heavily-tested legacy code naturally accumulates bounded tails of residual findings as a hardened surface converges; conflating that with a young design smell produces spurious zoom-outs on mature code and dilutes the signal. The escalation would fire on surfaces the team has no intent to redesign in this initiative |
| Use severity alone as the escalation trigger (no age gate) | Severity is already a sensitivity MODIFIER on the cluster threshold N, not a standalone gate (ADR-0023, Decision 3). Repeating severity as a cross-iteration escalation gate would over-escalate lone high-severity findings on mature surfaces — the same failure mode ADR-0023 rejected — and would miss young-surface design smells at lower severity where the recurrence IS the signal |
| Treat age as a soft heuristic (weighted factor, not a hard AND) | A soft heuristic introduces reviewer-to-reviewer variation: one pass escalates, the next defers, the overlord receives inconsistent signals across iterations. A hard AND'd gate produces a deterministic routing decision from a single judgment call (is this surface young?) rather than a continuous score. The loss of nuance is accepted deliberately in exchange for consistency |

### Decision 2 — GitHub as ledger vs. persisted local file

| Option | Rejected because |
|---|---|
| Persist a local `.hivemind` recurrence ledger file updated each loop | Introduces a local state artifact the github-reviewer already chose not to use: that reviewer reconstructs its fix-ledger from ground truth on each pass rather than persisting one (per ADR-0023 and `plugin/governance/remediation-doctrine.md`). A local recurrence file duplicates that responsibility with a second persistence surface, creates drift risk when the file and GitHub diverge (e.g. manual thread resolution, force-push, branch rebase), requires ownership and concurrency discipline (ADR-0016/P16), and couples the overlord's recurrence state to the local filesystem rather than the single source of truth the loop already relies on |

## Consequences

- **Youth as a hard gate produces deterministic routing.** The classification is a binary judgment (young vs. mature), not a continuous score. This is a deliberate precision trade-off: the discriminator is itself a judgment over a lossy source — "was this surface introduced or heavily modified here" — but that single judgment is cheaper to apply consistently than a weighted heuristic is to calibrate across reviewers and iterations.
- **Mature surfaces are protected from spurious zoom-outs.** Legacy surfaces that were not touched in this initiative but absorb reviewer findings continue to route to the bounded-tail merge-advisory path, exactly as before the cross-iteration axis existed. Gate B of the recurrence rule is the discriminator; the two paths are disjoint by construction.
- **GitHub ground truth is the single source of recurrence state.** The reconstruction approach is consistent with how the github-reviewer already reasons about its fix-ledger. No local state artifact is introduced; no ownership, concurrency, or staleness burden is accepted. The accepted cost is reconstruction work each loop and dependence on GitHub thread and commit fidelity — if a structural-fix thread is force-resolved without a commit, the counter under-counts.
- **The runtime mechanics are single-sourced in governance.** Threshold values, acceptance-test wording, reconstruction formula, and zoom-out routing asymmetry live in `plugin/governance/remediation-doctrine.md` as the authoritative home. This ADR records the decisions; it does not restate the mechanics (P1, P20).
- **This ADR extends the ADR-0023 lineage.** The remediation doctrine, its detection skill, and the governance vocabulary were established by ADR-0023. The decisions here deepen that lineage by committing two previously implicit architectural choices.

Reference: issue #273.

## Amendment — 2026-10-24 (zoom-out at the first non-closing fix, ADR-0038)

`docs/adr/0038-root-cause-at-the-first-finding.md` moves both trip points earlier. `plugin/governance/remediation-doctrine.md` governs the mechanics.

- **The forced zoom-out moves to the first fix.** The overlord forces the approach-level zoom-out after one non-closing structural fix on a surface, not after two. The counter still persists across structural fixes, and the first non-closing fix after any accepted structural fix is the trip point. On the script engine the trigger is a local review that sends the run back to planning after a remediation pass already ran.
- **The cross-iteration axis trips at N=2.** Gate A now holds at two distinct iterations with a fix between them, and the axis has no N=3 default. Sharing a data-access, query, parse or serialization primitive is now part of the cluster's same-framing rationale, not a separate threshold.

Decisions 1 and 2 stand: youth is still a hard gate, and GitHub is still the recurrence ledger. Status remains accepted.
