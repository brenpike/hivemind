---
stamps: []
verdict: fail
open_counts:
  critical: 0
  high: 16
  medium: 13
  low: 11
rounds: 3
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

Every finding is open until it gets exactly one disposition:

- **fixed**: the record says where.
- **deferred**: the record names a tracked issue.
- **recorded**: the record says where.
- **rejected**: the record says why.

**Open** is a state, not a disposition. An open finding is counted in `open_counts`, and its disposition column reads `open`.

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

Its solutions were adopted as ADR-0045 decisions by PR #613. Its findings are recorded as folded into PR #613, each naming the answering decision. The Context section of ADR-0045 names four findings from the two adversarial reviews together. It does not split them by pass.

| Finding | Disposition |
| --- | --- |
| Park answers were an injection path. | recorded: folded into PR #613, answered by ADR-0045 decision 11 |
| The merge controls did not reach strains. | recorded: folded into PR #613, answered by ADR-0045 decisions 4, 12 and 17 |

## Round 3, 2026-11-21

Two passes, run in parallel. No further round: the review is capped at 3 rounds.

- **Pass A reviewer:** a fresh read-only `hivemind:cerebrate` analysis delegation that did not write the design, with "Memory context: none".
- **Pass A model:** Opus 5.5 (claude-opus-5-5).
- **Pass A angle:** code truth, governance and ADR conflicts, existing-path coverage.
- **Pass B reviewer and model:** the same kind and model as pass A.
- **Pass B angle:** failure modes, trust and injection, testability.
- **Reviewed:** the PRD, ADR-0045 as amended, and the solution design.

Checks that passed (pass A):

- The 13 sections are present, in order.
- Headings are unique.
- Open questions reads None.
- Each decision names its ADR or the condition it fails.
- Links go only to main or this PR.
- The PRD Admission criterion and admission testing decision match the amendment.

Result: 0 critical, 16 high (7 from pass A, 9 from pass B), 13 medium and 11 low. All are new and all are open. The review did not converge by round 3, so per the review rule it went to the user as a signal to split the initiative.

Deduplicated, the 16 highs are 11 distinct issues: merge keys reach strains (A3-1, B3-17); merge lane bypasses ADR-0044 (A3-2, B3-5, B3-6); merge settings source (A3-3, B3-7); launch inputs from issue text (A3-4, A3-7, B3-2); re-claim and remediation branch (A3-5); governance asks (A3-6); injection-scan executor (B3-1); forgeable markers (B3-3); unchecked strain result (B3-4); auto-tier inputs (B3-8, A3-10); deny-rule containment (B3-9).

### Pass A findings

| ID | Severity | Finding | Overlaps | Disposition |
| --- | --- | --- | --- | --- |
| A3-1 | high | Lair-written settings do not keep merge keys out of strains: worktree sessions read the main checkout's `settings.local.json` since Claude Code 2.1.211 per ADR-0010, an omitted key overrides nothing inherited, and the file is not named. | B3-17 | open |
| A3-2 | high | The tick runs `merge-approved.sh` outside the watch, dropping ADR-0044's settled-approval precondition, and the failure-mode row maps the script's results wrongly. | B3-5, B3-6 | open |
| A3-3 | high | The controller has no defined source for the merge settings it reads each tick, so unsetting auto-merge may never stop merges. | B3-7 | open |
| A3-4 | high | There is no contract for the strain overlord's launch inputs (level, decisions, draft) or for carrying parked, branch, head and decisions out of the run result. | B3-2 | open |
| A3-5 | high | Re-claim on the pushed branch and remediation on the PR branch contradict spawn-brood (detached at base) and the brood-child fresh-branch rule. | | open |
| A3-6 | high | Governance the strain overlord loads (Tier A, user_gate, pre-spawn approval) still tells it to ask, and no slice owns the edits. | | open |
| A3-7 | high | The facts step re-reads referenced issues and outsider comments live. | B3-2 | open |
| A3-8 | medium | Draft-PR and closed-unmerged states have no lifecycle exit. | | open |
| A3-9 | medium | Stall and agent-call budget rules rely on signals nothing produces, and the agent-call cap has no owner. | | open |
| A3-10 | medium | Auto-tier inputs have no named source, and two can be forged by the strain. | B3-8 | open |
| A3-11 | medium | The Seam order ADR lists are incomplete (ADR-0010, 0017, 0029, 0037, 0042, 0044). | | open |
| A3-12 | medium | Design calls were taken but not listed for veto, and three (no-merge after edit, CI-red rule, session-scoped breaker) should have been asked. | | open |
| A3-13 | low | It is unclear whether `lair:review` goes on the issue or the PR. | | open |
| A3-14 | low | Remote control (`/rc`) on strains is not covered under Trust boundaries. | | open |
| A3-15 | low | The state table omits spawn-brood's files. | | open |
| A3-16 | low | The intra-epic build order has no native blocked-by links stated. | | open |
| A3-17 | low | A parked issue loses its `lair:*` label, so triage no longer skips it. | | open |
| A3-18 | low | The #606 amendment will stale the record and block every Lair slice until re-review. | | open |

### Pass B findings

| ID | Severity | Finding | Overlaps | Disposition |
| --- | --- | --- | --- | --- |
| B3-1 | high | The pre-spawn injection scan has no executor: it needs a model, the controller has none, and headless `claude -p` is rejected. | | open |
| B3-2 | high | The strain's model derives launch inputs from the issue text, and the facts step re-reads GitHub live. | A3-4, A3-7 | open |
| B3-3 | high | Marker comments have no author rule, so anyone can forge breaker, budget, park and sweep inputs. | | open |
| B3-4 | high | Strain result fields (pr, branch, head) are trusted unchecked, and "Lair PR" is undefined. | | open |
| B3-5 | high | The tick's merge drops ADR-0044's settle period and does not tie the auto tier to the merged head. | A3-2 | open |
| B3-6 | high | The merge-result failure-mode row maps `merge-approved.sh` results wrongly. | A3-2 | open |
| B3-7 | high | No defined source for merge settings in the tick. | A3-3 | open |
| B3-8 | high | Auto-tier inputs (protected-path list, local-review-skipped evidence, bump type) are undefined or untrusted. | A3-10 | open |
| B3-9 | high | Deny rules cannot deliver "a strain cannot merge, change labels or edit the issue" (`gh api`, `curl`, `bash -c`, committed allows), so an injected strain could admit or answer other issues. | | open |
| B3-10 | medium | A claim is several writes, and the partial states and the sweep are undefined. | | open |
| B3-11 | medium | The single-instance lock scope is not stated. | | open |
| B3-12 | medium | Session end waits for "branch pushed", which can block forever, and run activity is undefined. | | open |
| B3-13 | medium | The run outcome to label mapping is incomplete (blocked, complete with no PR, invalid result). | | open |
| B3-14 | medium | Remediation strains leave no GitHub record, their parks have no path, and the halt does not cover them. | | open |
| B3-15 | medium | Re-claim from the pushed branch has four gaps: moved head, superseded design, unanswered park, decision size limit. | | open |
| B3-16 | medium | The readiness check needs one snapshot, an error state and a cost limit (time-of-check to time-of-use between reads). | | open |
| B3-17 | medium | Env values leak into strains both ways, and the marker's source cannot be told. | A3-1 | open |
| B3-18 | low | The `body_sha256` form is undefined (CRLF, null body). | | open |
| B3-19 | low | The queue report prints issue-derived text raw and gives no cause. | | open |
| B3-20 | low | Verification strategy gaps: test registration in `tools/validate.sh`, overlord prose, injection and halt tests, the halt file path. | | open |
| B3-21 | low | The decision digest is only as complete as the strain's report. | | open |
| B3-22 | low | The readiness check reads document paths named in the issue body (seam with #615). | | open |

## Sources

- claude-mem observation #43827 (pass 1).
- claude-mem observations #43828, #43844, #43845 and #43846 (pass 2).
- The Context section of [ADR-0045](../../adr/0045-lair-software-factory.md).
- Round 3: the PRD, ADR-0045 as amended and the solution design, read directly by the two passes.
- The claude-mem observations above could not be read in the session that wrote round 3, because claude-mem was unavailable. The round 1 and 2 finding text and pass metadata are as supplied in the task brief and were not re-checked against them. Every round 1 decision citation was checked against the ADR-0045 text and holds.

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

Round 3 did not converge under the 3-round cap. The user was asked to choose: split the initiative, fix and run a fourth round, record and merge, or other. The user chose to split.

- The record stays at verdict `fail`.
- PR #628 stays a draft and is not merged until a re-reviewed design passes.
- A proposed split, for the user to decide, groups the open highs into three parts:
  - Strain launch and containment: A3-1, A3-4, A3-5, A3-6, A3-7, B3-2, B3-9, B3-17.
  - Merge lane: A3-2, A3-3, A3-10, B3-4, B3-5, B3-6, B3-7, B3-8.
  - Claim integrity: B3-1, B3-3.
