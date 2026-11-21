---
stamps: []
verdict: pending
open_counts:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 2
clean_round: null
---

# Design review record: Lair — Software Factory

This record covers the design review of the Lair: the [PRD](../../prds/autonomous-ready-issue-loop.md), the [solution design](solution-design.md) and [ADR-0045](../../adr/0045-lair-software-factory.md). Only the PRD and the solution design are stamped; each stamp's blob is `git rev-parse HEAD:<path>` for that file. ADR-0045 is reviewed but not stamped. The review exits only when zero critical or high findings are open and one round raises no new findings. It is capped at 3 rounds.

## Record keys

- `stamps`: one entry per stamped document, with `path` and `blob` keys. Empty until the review passes.
- `verdict`: `pending`, `pass` or `fail`.
- `open_counts`: open findings by severity: `critical`, `high`, `medium` and `low`.
- `rounds`: the number of rounds run.
- `clean_round`: the round that raised no new findings, or `null`.

## Dispositions

Every finding has exactly one disposition:

- **fixed**: the record says where.
- **deferred**: the record names a tracked issue.
- **recorded**: the record says where.
- **rejected**: the record says why.

## Round 1, 2026-11-21

One pass.

- **Reviewer:** a `hivemind:cerebrate` planner pass (per PR #613).
- **Model:** Fable 5.2.
- **Angle:** adversarial interrogation of the first Lair draft.

Every finding is fixed: folded into ADR-0045 and the PRD by PR #613 and answered by the named ADR-0045 decision.

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| C1 | critical | Brood-status could not see a run end or a park. | fixed: ADR-0045 decision 5 |
| C2 | critical | Unattended mode covered only `decide()`. | fixed: ADR-0045 decision 6 |
| C3 | critical | Issue text reached the strain with no trust anchor: the label actor was unchecked, and the body was editable after the label. | fixed: ADR-0045 decision 10 |
| H1 | high | The park round-trip criteria were false, and there was no park cap. | fixed: ADR-0045 decisions 11 and 7 |
| H2 | high | The plan-again stop had no cause identity. | fixed: ADR-0045 decision 6 |
| H3 | high | The serial merge lane was contradicted, and a draft pull request could deadlock it. | fixed: ADR-0045 decision 12 |
| H4 | high | Strains copied the coordinator's `settings.local.json`, so `--admin` persisted. | fixed: ADR-0045 decision 4 |
| H5 | high | Unattended mode had no channel and no enforcement. | fixed: ADR-0045 decisions 6 and 4 |
| H6 | high | There was no liveness check, reaping or crash recovery. | fixed: ADR-0045 decisions 5 and 17 |
| M1 | medium | Release train. | fixed: ADR-0045 decision 15 |
| M2 | medium | Label-meaning collision. | fixed: ADR-0045 decision 16 |
| M3 | medium | Stateless design versus counters. | fixed: ADR-0045 decisions 2, 7 and 17, with counts recomputed from GitHub markers |
| M4 | medium | Tooling gaps. | fixed: ADR-0045 decisions 3 and 5. The unverified `Stop` hook and tmux exit stay the ADR-0045 residual that #604 resolves. |

## Round 2, 2026-11-21

One pass.

- **Reviewer:** a `hivemind:cerebrate` planner pass (per PR #613).
- **Model:** claude-fable-5-2.
- **Angle:** gap analysis and solution over the same draft.

Its solutions were adopted as ADR-0045 decisions by PR #613. Its findings are recorded as folded into PR #613, each naming the answering decision, as the Context section of ADR-0045 states them.

| Finding | Disposition |
| --- | --- |
| Park answers were an injection path. | recorded: folded into PR #613, answered by ADR-0045 decision 11 |
| The merge controls did not reach strains. | recorded: folded into PR #613, answered by ADR-0045 decisions 4 and 12 |

## Sources

- claude-mem observation #43827 (pass 1).
- claude-mem observations #43828, #43844, #43845 and #43846 (pass 2).
- The Context section of [ADR-0045](../../adr/0045-lair-software-factory.md).

## Decisions taken (listed for veto)

- The PRD's Admission criterion and its admission testing decision are aligned with the ADR-0045 amendment.
- The release-train decisions are deferred with their full scope to #606, so #606 and #612 are not ready yet.
- #608's admission depends on the readiness check from #615. This is recorded in the design's Seam order and left for the maintainer to link.
- This record's keys and disposition vocabulary.
- Rounds 1 and 2 are recorded from the listed findings and ADR-0045.

## Decisions asked

The ADR-0045 admission amendment was asked of and settled by the user before this work. Its three rules:

- Epics are never claimed.
- An issue is claimed only when the readiness check passes at claim time.
- A failing issue stays unclaimed, is named in the queue report, and gets no new label.

The idea-to-ready work is referred to as #614 and #615; the readiness check comes from #615.
