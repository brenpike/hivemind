# Root-cause remediation doctrine: shared detection skill + governance vocabulary

**Status:** accepted — 2026-06-04

## Context

Both review loops — the post-PR `hivemind:github-reviewer` and the pre-PR `local-reviewer` — were patching review findings one at a time. On a hardened security surface this is whack-a-mole: a per-finding patch fixes the observed byte and the next reviewer pass surfaces the next sibling of the same class. Two anti-churn detectors already existed (Mutation Decay and Creep Stagnation, both defined in CONTEXT.md), but they lived as prose inside `local-reviewer` only, so the GitHub side could not see them, and neither encoded the missing signal: a *cluster* of findings that share one root cause and should trigger a zoom-out to a structural fix rather than N narrow patches.

Issues #163 and #177 asked for a single doctrine that both loops reason from with one vocabulary — covering when to cluster, when to stop-and-merge a converged bounded tail, and how severity participates — without re-litigating it in two places or proliferating workflow state.

The hard constraint is the prose architecture: there is no shared function to call. Logic is either re-stated in each agent body or single-sourced as a loadable artifact. The decisions below are the ones that are load-bearing and expensive to reverse.

## Decision

1. **Detection is a shared SKILL; vocabulary/policy is a governance DOC — a deliberate split.** The cluster / break-fix / diminishing-returns / stop-and-merge DETECTION ALGORITHM lives in one classifier-style skill, `hivemind:detect-remediation-signals` (modeled on `route-workflow`), invoked by BOTH reviewers with one invocation and one return contract. The VOCABULARY and POLICY live in `plugin/governance/remediation-doctrine.md`, loaded by both reviewers plus the overlord and cerebrate. That governance doc is the authoritative runtime home and single source for the binding vocabulary and operational policy — this ADR records the decision; the governance doc operationalizes and executes it (P20). Rationale: single-source the algorithm — the strongest possible de-dup in this architecture is one invocation + return contract, not two prose copies that each agent must re-interpret — while keeping always-on policy as loadable governance. **Mutation Decay and Creep Stagnation were EXTRACTED out of `local-reviewer` into the skill**, both to de-dup and to cross-pollinate them to the GitHub side, which never had them.

2. **`root-cluster-suspected` is a new exit_reason that REUSES the existing remediation-plan states.** A reviewer that detects a root-cluster returns the `root-cluster-suspected` exit_reason; the overlord routes it through the existing `review_remediation_plan` / `review_remediation_plan_postpr` states (which already route to cerebrate for a structural fix). No new zoom-out state is added. Rationale: a distinct exit_reason gives observability and engine-enforced contract — the signal is visible in the ledger and report and is validated like any other outcome — without adding a state to the machine.

3. **Severity is a sensitivity MODIFIER, not a standalone gate.** There is no standalone P0/P1 zoom-out gate; severity instead lowers the cluster-recurrence threshold on a just-touched / same-framing surface. The exact threshold mechanics are operationalized in `plugin/governance/remediation-doctrine.md` ("Severity as Sensitivity Modifier") as the authoritative home. Rationale: whack-a-mole is a RECURRENCE signal, not a severity signal. A lone high-severity finding is the review WORKING, not a reason to cluster; gating every P0/P1 over-escalates, costs a structural detour on single findings, and desensitizes the loop to the badge. A cross-cutting single fix already routes via planner-escalation.

4. **`merge_advised` is an ADVISORY terminal; agents never merge.** When the stop-and-merge preconditions hold — their authoritative statement lives in `plugin/governance/remediation-doctrine.md` ("Stop-and-Merge") — the loop surfaces a recommendation — the reason is carried as an `advisory_reason` + `recommendation_text` PAYLOAD, not as a routing decision — and the human merges. It is a DISTINCT terminal, not folded into `complete` or `review_exhausted`, for honest observability: a converged bounded tail is a success, and labeling it either as "merged" or as "exhausted" would misreport it. This terminal is github-review-loop-only.

The six PR #172 case studies ship as few-shot exemplars in the skill's `references/`, not as a `tests/` schema-conformance harness. The requirement that "case studies back the doctrine" is satisfied by exemplars-plus-dogfood — behavioral proof is the dogfood, not a CI fixture — a deliberate decision, not an omission.

## Considered Options

| Option | Rejected because |
|---|---|
| Put the WHOLE doctrine including the algorithm in a governance doc both agents load (no skill) | A loaded doc still makes each agent re-state and re-interpret the algorithm in its own body; a skill with one invocation + return contract is the closest this prose architecture gets to a shared function — the strongest de-dup available |
| Overload planner-escalation with a cluster payload (no new exit_reason) | Loses observability and engine enforcement — the cluster signal would be invisible in the ledger/report and unvalidated as an outcome |
| Add a dedicated new zoom-out state | Unnecessary state proliferation; the existing `review_remediation_plan` / `review_remediation_plan_postpr` states already route to cerebrate for a structural fix |
| Gate ALL P0/P1 (or only P0) findings to zoom-out | Over-generalizes a recurrence signal into a severity signal; a lone high-sev finding is the review working. Gating every high-sev finding forces a structural detour on single findings, costs more, and dilutes the cluster signal |
| Fold stop-and-merge into the `complete` terminal | Implies the branch is already merged — misleading; agents never merge |
| Fold stop-and-merge into `review_exhausted` | Labels a converged bounded-tail SUCCESS as an exhaustion FAILURE — dishonest observability |
| Ship the 6 PR #172 case studies as a `tests/` schema-conformance harness | Case studies are behavioral exemplars; their proof is dogfood, not schema conformance. Few-shot exemplars in the skill's `references/` carry the behavioral signal without a CI fixture that asserts nothing about behavior |

## Consequences

- **One detection algorithm, one return contract, invoked by both loops** — the `hivemind:detect-remediation-signals` skill is the single source; the GitHub side gains Mutation Decay and Creep Stagnation it never had, and neither agent re-states the algorithm.
- **The cluster signal is observable and engine-enforced** — `root-cluster-suspected` appears in the ledger and report and is validated as an outcome, while reusing existing states keeps the state machine flat.
- **Severity tunes, never gates** — high-severity findings lower the cluster threshold to N=2 on a just-touched surface but never force a zoom-out on their own; the loop stays sensitive to recurrence, not to the badge.
- **A converged bounded tail terminates honestly** — `merge_advised` reports success as success, the human merges, and a hardened-surface tail is no longer mislabeled as exhaustion or silently treated as merged.
- **Doctrine is dogfooded, not fixture-tested** — the six PR #172 exemplars in the skill's `references/` are the behavioral proof; correctness is demonstrated by the loop's own runs.
- **Binding vocabulary and policy are single-sourced in governance** — `plugin/governance/remediation-doctrine.md` is the authoritative runtime home for the binding vocabulary and the operational rule mechanics (threshold tuning, stop-and-merge preconditions); this ADR records the decisions and rationale, the governance doc executes them (P20). The pointer is one-way ADR→governance.

Reference: issues #163 and #177.

## Amendment — 2026-09-18 (an unfixed finding routes by DESTINATION; the tracker is no longer the mandated home)

Decision 4 and the Consequences above name "a tracked issue" as the structural home for any finding left unfixed — defer-with-scope was, in practice, read as file-an-issue-with-scope. That reading is superseded: **a finding left unfixed now routes by DESTINATION, chosen from what the finding IS.** A finding that is WORK someone should do routes to a tracked issue, preferring an EXISTING tracked home; a finding that is a DECISION — the behavior is inherited rather than introduced, its impact is bounded and understood, and the obvious remediation was considered and rejected on the merits — is written into the repository next to the code it concerns as a recorded residual, and opens no tracker entry. The explicit default ordering is: prefer an existing tracked home, prefer recording over filing, and treat a NEW issue as the last resort.

The discriminating test is what the record ASSERTS: an issue asserts that SOMEONE WILL ACT; a recorded residual asserts that WE DECIDED, AND HERE IS WHY. The scope obligation is unchanged and identical across both destinations — full root-cause scope, linked threads, and a bounded-impact note. Only the destination varies. A record that omits scope remains a silent drop and remains forbidden.

**Rejected alternative: file every unfixed finding as a tracked issue.** This was the operative reading of the original Decision, and its consequence was observed rather than predicted. The tracker fills with review spillover: opened issues outpace closed ones, and the backlog stops functioning as a signal because a genuine user-reported defect becomes indistinguishable from reviewer noise sitting beside it. Filing a decision as an issue is additionally a category error — it inflates the backlog with work nobody intends to do and buries the reasoning away from the code it concerns, which is exactly where the next reader needs it. Recording the decision adjacent to the behavior keeps the backlog a list of intended work and puts the rationale where it is found.

Recording is not one-way: a recorded residual whose reasoning is later invalidated — the impact turns out to be unbounded, or the behavior turns out to have been introduced by the change after all — is promoted to a filed issue carrying the same scope.

The NORMATIVE home for this routing — the conjunctive conditions, the destination-by-role rule, the code-comment floor, and the promotion path — is `plugin/governance/remediation-doctrine.md` (`## Defer-with-Scope`, `### Recorded Residual`). This amendment records the decision and its rationale; the governance doc executes it, and this amendment does not restate its mechanics. The pointer stays one-way ADR→governance.

No new ADR is created for this decision: these existing ADRs are its correct homes, and ADR ordinals collide across parallel worktrees.

This amendment is APPEND-ONLY. The original Context, Decision, Considered Options, and Consequences above stand as written. Status remains accepted.
