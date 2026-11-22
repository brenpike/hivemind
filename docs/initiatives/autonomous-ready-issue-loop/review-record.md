---
stamps: []
verdict: fail
open:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 0
clean_round: false
---

# Design review record: Lair — Software Factory

The first review, rounds 1 to 3, did not converge. After round 3 the user split the initiative into three part designs: #630 strain launch, #631 merge lane and #632 claim integrity. #633 integrates them into this design. For a fresh re-review under ADR-0046 decision 6, Re-review after an amendment, the front matter is reset (`verdict`, `rounds`, the open counts and `clean_round`), the stamps are kept, and the first review's rounds and findings are kept under History below.

## Reviewed documents

- [PRD: Lair — Software Factory](../../prds/autonomous-ready-issue-loop.md)
- [Solution design: Lair — Software Factory](solution-design.md)
- [ADR-0045](../../adr/0045-lair-software-factory.md): the Lair software factory

Stamps follow ADR-0046 decision 7, Blob stamps. The record written after round 1 stamps these three documents at the commit round 1 reviewed. The record that sets `verdict` `pass` re-stamps them at the commit its clean pass reviewed.

The three part designs, [strain launch](strain-launch-design.md), the [merge lane](merge-lane-design.md) and [claim integrity](claim-integrity-design.md), are read as the text they supersede in the solution design.

Review rule:

- Rounds count from 1. Round 1 covers the whole documents, because no record of this design has passed.
- Each round is one fresh, read-only `hivemind:cerebrate` pass with `Memory context: none`, covering every angle. When a local review tool is configured, the round adds one pass of that tool. When none is configured, the record says that pass was skipped.
- A round never runs two passes of one model.
- The cap is 3 rounds.

## Rounds

None yet.

## Findings

| ID | Round | Angle | Severity | Disposition | Note |
| --- | --- | --- | --- | --- | --- |

## Decisions taken, listed for veto

Each decision has its always-ask screen: an answer to each of the four always-ask items of ADR-0046 decision 8. "no" means the decision does not do that.

Listed again for veto, from the part designs:

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- |
| Merge lane, Changes to shared documents, item 2: the Amendments pointer paragraph in the solution design | no | no | no: it points to the merge lane's governing text and changes no rule | no |
| Merge lane, item 3: the round-3 dispositions, applied under History. Its `open_counts` recompute is replaced by the ADR-0046 decision 7 open counts, reset to 0 | no | no | no | no |
| Merge lane, item 4: the **Lair Pull Request** entry in `CONTEXT.md` | no | no | no: it names the merge lane's existing rule, which rests on Tier A answer Q1 and ADR-0044 decision 17 | no |
| Claim integrity: the wording of the ADR-0045 amendment of 2026-11-21, the orphan rule covers only Lair issues | no | no: the amendment was asked and answered A on 2026-11-21; only its wording, which follows invariant Claim state, was decided | no | no |
| Claim integrity: the sentence for the **Lair** entry in `CONTEXT.md` | no | no: it cites the asked amendment of 2026-11-21 to decision 2 | no: it names the key exception the user approved | no |
| Claim integrity: its Amendments paragraph in the solution design | no | no | no | no |

This run's calls:

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- |
| Seams between the part designs, item 1: markers are append-only, signed and posted on the claimed issue; the merge lane's run-end and fix-up end markers and strain launch's outcome write are outcome markers; the dispatch marker is the fix-up start marker | no | no: it implements ADR-0045 decision 2 and its 2026-11-21 amendment | no: claim integrity's signing and counting rules are unchanged | no |
| Item 2: one remediation strain per pull request decides what starts a remediation, and the merge lane's R2 no longer applies | no | no | no: the merge lane's CI-red rule (Q9) and merge gates stand; the one-strain rule is the user's answer A of 2026-11-22 at strain launch's design review round 5 | no |
| Item 3: a remediation run's wall-clock budget is timed from its own launch | no | no | no | no |
| Item 4: one set of counted and skipped breaker outcomes. The counted set is asked (Decisions asked); the skipped outcomes, the streak end and the session scope are this call | no | no | no | no |
| Item 5: one tick order, with the remediation step before the merge lane, per the user's answer A of 2026-11-22 at strain launch's design review round 7 | no | no | no | no |
| Item 7: the orphan rule and the start-up sweep follow claim integrity, with strain launch's deferred-write exemption and the merge lane's worktree removal after the end marker | no | no: it follows the asked ADR-0045 amendment of 2026-11-21 on orphans | no | no |
| The integration entry under the solution design's Amendments covers strain launch, which has no approved Amendments text | no | no | no | no |
| The Part designs column of Seam order | no | no | no | no |
| The line "Part designs this slice implements: ..." added to the bodies of #604 to #612, every other byte kept | no | no | no | no: the body edit is reversible |
| A3-18 disposed `recorded` in ADR-0046 | no | no | no | no |
| B3-9 disposed `fixed` by removing the claim it attacks, through strain launch's changes 1, 2 and 9 | no | no: the reworded ADR-0045 text is strain launch's approved changes 1 and 9 | no: the reworded claims were approved by the user, option A, 2026-11-21 | no |

The parent design's own calls, listed for veto under A3-12:

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- |
| Triage leaves `lair:*` issues alone, built in #608 | no | no | no | no |
| The release-train decisions are deferred with full scope to #606, so #606 and #612 are not ready until a dated Amendments entry settles them | no | no | no | no |
| #608's admission needs the readiness check from #615, recorded in Seam order and left for the maintainer to link | no | no | no | no |

## Decisions asked

- **Key containment.** Answered A by the user on 2026-11-22. Both approved ADR-0045 residual texts stand unchanged. #604 keeps every Lair strain and remediation strain out of the `control/` folder of the Lair's state root and, on Linux, runs each in a sandbox with its own process namespace. Strain launch's statement that a strain can read any file the user can read holds outside that folder. The solution design states it under Seams between the part designs, item 6.
- **Stalled outcomes.** Answered A by the user on 2026-11-22. The PRD's Stop controls criterion counts stalled outcomes: "Three consecutive failed, crashed, stalled or timed-out outcomes halt the Lair with a stated cause. Parks and review waits do not count." This matches the ADR-0045 amendment of 2026-11-22, more causes stop the Lair.
- **Tier A answers the applied entries carry:**
  - Merge lane, item 1, the PRD Credentials bullet: Tier A, Q4, approved 2026-11-21.
  - Merge lane, item 6, the PRD Out of Scope bullet: Tier A, Q1 and Q3, approved 2026-11-21.
  - Merge lane, item 7, the ADR-0045 Status line: Tier A, Q1 and Q3, approved 2026-11-21.
  - Strain launch, changes 1 to 10: option A each. Changes 1 to 3 were accepted at design, changes 4 and 5 at its local review and changes 6 to 9 at its design review round 1, each on 2026-11-21; change 10 at its design review round 2, on 2026-11-22.
  - Claim integrity, ADR-0045 amendment of 2026-11-21, the marker key is the one local file the Lair cannot rebuild: the user's reply of 2026-11-21, "Sure but I don't even understand what the point is", taken as yes.
  - Claim integrity, ADR-0045 amendment of 2026-11-21, sessions running as the user can forge Lair markers: signed markers with a residual, chosen by the user on 2026-11-21, with no separate operating-system account.
  - Claim integrity, ADR-0045 amendment of 2026-11-21, the orphan rule covers only Lair issues: answer A, 2026-11-21.
  - Claim integrity, ADR-0045 amendment of 2026-11-22, the Lair's strains can read its key where no sandbox hides its processes: Tier A, answer A, 2026-11-22.
  - Claim integrity, ADR-0045 amendment of 2026-11-22, more causes stop the Lair: Tier A, answered yes on 2026-11-22.
- **Merge lane, item 5, is not applied.** The Tier A merge bullet in `plugin/governance/decision-autonomy.md` (Tier A, Q1, approved 2026-11-21) is built by #605, with its fixture update and structural check.

## History: 2026-11-22

The first review of this design, kept as it stood after round 3. Its front matter then held `verdict` `fail`, `open_counts` of 0 critical, 16 high, 13 medium and 11 low, `rounds` 3 and `clean_round` `null`. On 2026-11-22, under #633, every round-3 finding took a disposition from the part design reviews and this integration, so none is open.

### First review scope

This record covered the design review of the Lair: the [PRD](../../prds/autonomous-ready-issue-loop.md), the [solution design](solution-design.md) and [ADR-0045](../../adr/0045-lair-software-factory.md). Only the PRD and the solution design were stamped; each stamp's blob was `git rev-parse HEAD:<path>` for that file. ADR-0045 was reviewed but not stamped. The review exited only when zero critical or high findings were open and one round raised no new findings. It was capped at 3 rounds.

### First review record keys

- `stamps`: one entry per stamped document, with `path` and `blob` keys. Empty until the review passes.
- `verdict`: `pending`, `pass` or `fail`.
- `open_counts`: open findings by severity: `critical`, `high`, `medium` and `low`.
- `rounds`: the number of rounds run.
- `clean_round`: the round that raised no new findings, or `null`.

### First review dispositions

Every finding is open until it gets exactly one disposition:

- **fixed**: the record says where.
- **deferred**: the record names a tracked issue.
- **recorded**: the record says where.
- **rejected**: the record says why.

**Open** is a state, not a disposition. An open finding was counted in `open_counts`, and its disposition column read `open`.

### Round 1, 2026-11-21

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

### Round 2, 2026-11-21

One pass.

- **Reviewer:** a `hivemind:cerebrate` planner pass (per PR #613).
- **Model:** claude-fable-5-2.
- **Angle:** gap analysis and solution over the same draft.

Its solutions were adopted as ADR-0045 decisions by PR #613. Its findings are recorded as folded into PR #613, each naming the answering decision. The Context section of ADR-0045 names four findings from the two adversarial reviews together. It does not split them by pass.

| Finding | Disposition |
| --- | --- |
| Park answers were an injection path. | recorded: folded into PR #613, answered by ADR-0045 decision 11 |
| The merge controls did not reach strains. | recorded: folded into PR #613, answered by ADR-0045 decisions 4, 12 and 17 |

### Round 3, 2026-11-21

Two passes, run in parallel. No further round: the review was capped at 3 rounds.

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

Result: 0 critical, 16 high (7 from pass A, 9 from pass B), 13 medium and 11 low. All were new and all were open at the end of round 3. The review did not converge by round 3, so per the review rule it went to the user as a signal to split the initiative.

Deduplicated, the 16 highs are 11 distinct issues: merge keys reach strains (A3-1, B3-17); merge lane bypasses ADR-0044 (A3-2, B3-5, B3-6); merge settings source (A3-3, B3-7); launch inputs from issue text (A3-4, A3-7, B3-2); re-claim and remediation branch (A3-5); governance asks (A3-6); injection-scan executor (B3-1); forgeable markers (B3-3); unchecked strain result (B3-4); auto-tier inputs (B3-8, A3-10); deny-rule containment (B3-9).

The dispositions below were set on 2026-11-22. A finding a part design owns takes that part's review record disposition, citing the record. The merge lane's findings take the text of its Changes to shared documents, item 3, word for word.

#### Pass A findings

| ID | Severity | Finding | Overlaps | Disposition |
| --- | --- | --- | --- | --- |
| A3-1 | high | Lair-written settings do not keep merge keys out of strains: worktree sessions read the main checkout's `settings.local.json` since Claude Code 2.1.211 per ADR-0010, an omitted key overrides nothing inherited, and the file is not named. | B3-17 | fixed: Components > Strain launch and settings, and Contracts and seams > Strain settings and Strain environment, for the user, project and local scopes; a managed merge key stays the named residual "managed settings" under Trust boundaries > Strain containment (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-2 | high | The tick runs `merge-approved.sh` outside the watch, dropping ADR-0044's settled-approval precondition, and the failure-mode row maps the script's results wrongly. | B3-5, B3-6 | fixed: merge-lane-design.md, Settle check, Routing table and Failure modes, under ADR-0044 decisions 17, 18 and 20; completed in round 1 by M1-B3, M1-B4, M1-B5, M1-B13 and M1-B16, in round 2 by M2-A6, M2-A9 and M2-B8, and in round 3 by M3-A2 and M3-B1 |
| A3-3 | high | The controller has no defined source for the merge settings it reads each tick, so unsetting auto-merge may never stop merges. | B3-7 | fixed: merge-lane-design.md, Merge settings source, Merge environment and Lifecycle "Stage 4: halt and circuit breaker"; completed in round 1 by M1-A2, M1-B10 and M1-B15, and in round 2 by M2-B11 |
| A3-4 | high | There is no contract for the strain overlord's launch inputs (level, decisions, draft) or for carrying parked, branch, head and decisions out of the run result. | B3-2 | fixed: Components > Launch inputs, and Contracts and seams > Launch file and Strain result (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-5 | high | Re-claim on the pushed branch and remediation on the PR branch contradict spawn-brood (detached at base) and the brood-child fresh-branch rule. | | fixed: Components > Start points, where the remote compares the pre-image at the write: Lair mode of `push-branch.sh` pushes with a lease pinned to the pre-image the Lair captured, after an ancestry check, and the engine maps its fixed blocker line to `start_moved`; and the Failure modes rows "Start moved", "Moved head before a re-claim launch" and "Moved head before a remediation launch" (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-6 | high | Governance the strain overlord loads (Tier A, user_gate, pre-spawn approval) still tells it to ask, and no slice owns the edits. | | fixed: Components > Unattended governance edits (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-7 | high | The facts step re-reads referenced issues and outsider comments live. | B3-2 | fixed: Components > Launch inputs ("Facts come only from the captured issue text") (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-8 | medium | Draft-PR and closed-unmerged states have no lifecycle exit. | | fixed: merge-lane-design.md, Exits (Draft, Closed unmerged, Claim withdrawn) and Write order; completed in round 1 by M1-B7 and M1-B8, and in round 2 by M2-B3 and M2-B9 |
| A3-9 | medium | Stall and agent-call budget rules rely on signals nothing produces, and the agent-call cap has no owner. | | fixed: Components > Launch inputs ("Agent-call cap": the cap keeps back the record call) and Strain result and liveness ("The engine writes its own record" at every verified end), so `agent_budget` reaches the result (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-10 | medium | Auto-tier inputs have no named source, and two can be forged by the strain. | B3-8 | fixed: merge-lane-design.md, Auto-tier script and Trust boundaries; completed in round 1 by M1-B1, M1-B11 and M1-B12, in round 2 by M2-B4, M2-B6 and M2-B12, in round 3 by M3-A5, M3-B2 and M3-B4, and in round 4 by M4-C4 and M4-C5 |
| A3-11 | medium | The Seam order ADR lists are incomplete (ADR-0010, 0017, 0029, 0037, 0042, 0044). | | fixed: [solution-design.md](solution-design.md), Seam order, where each ADRs cell is the union of the design's row and the part designs' rows for that slice |
| A3-12 | medium | Design calls were taken but not listed for veto, and three (no-merge after edit, CI-red rule, session-scoped breaker) should have been asked. | | fixed: the [merge lane review record](merge-lane-review-record.md) and the [claim integrity review record](claim-integrity-review-record.md) for the three named calls, plus this record's Decisions taken, listed for veto, for the parent design's own calls |
| A3-13 | low | It is unclear whether `lair:review` goes on the issue or the PR. | | fixed: merge-lane-design.md, Exits (Batch review: on the issue and the pull request) and State and ownership; completed in round 1 by M1-A5 |
| A3-14 | low | Remote control (`/rc`) on strains is not covered under Trust boundaries. | | fixed: Trust boundaries (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-15 | low | The state table omits spawn-brood's files. | | fixed: State and ownership (the spawn record row, written by `spawn-brood.sh` before the session starts) and Components > Strain launch and settings (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-16 | low | The intra-epic build order has no native blocked-by links stated. | | fixed: [solution-design.md](solution-design.md), Seam order, which states each edge of the build order as one native blocked-by link and who writes it |
| A3-17 | low | A parked issue loses its `lair:*` label, so triage no longer skips it. | | fixed: [Lifecycle](claim-integrity-design.md#lifecycle), with the solution design's Lifecycle line "with `lair:claimed` removed" superseded in the design's opening list and the proposed Amendments pointer (round 1, C1-A1) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| A3-18 | low | The #606 amendment will stale the record and block every Lair slice until re-review. | | recorded: `docs/adr/0046-idea-to-ready-process.md`, decision 6, Re-review after an amendment, and decision 7, Staleness: an amendment stales the record until a re-review re-stamps it |

#### Pass B findings

| ID | Severity | Finding | Overlaps | Disposition |
| --- | --- | --- | --- | --- |
| B3-1 | high | The pre-spawn injection scan has no executor: it needs a model, the controller has none, and headless `claude -p` is rejected. | | fixed: [Scanner session](claim-integrity-design.md#scanner-session) and [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-2 | high | The strain's model derives launch inputs from the issue text, and the facts step re-reads GitHub live. | A3-4, A3-7 | fixed: Components > Launch inputs (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| B3-3 | high | Marker comments have no author rule, so anyone can forge breaker, budget, park and sweep inputs. | | fixed: [Marker signer and verifier](claim-integrity-design.md#marker-signer-and-verifier) and [Design invariants](claim-integrity-design.md#design-invariants) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-4 | high | Strain result fields (pr, branch, head) are trusted unchecked, and "Lair PR" is undefined. | | fixed: merge-lane-design.md, Lair pull request, Pinned head and Merge-lane step of the tick (late group); completed in round 1 by M1-A6, M1-B1, M1-B2 and M1-B8, in round 2 by M2-A1, M2-B2, M2-B3 and M2-B5, and in round 3 by M3-B2 |
| B3-5 | high | The tick's merge drops ADR-0044's settle period and does not tie the auto tier to the merged head. | A3-2 | fixed: merge-lane-design.md, Settle check, Pinned head and Expected-head argument; completed in round 1 by M1-B4, M1-B5 and M1-B17, in round 2 by M2-B8, and in round 3 by M3-A2 and M3-B1 |
| B3-6 | high | The merge-result failure-mode row maps `merge-approved.sh` results wrongly. | A3-2 | fixed: merge-lane-design.md, Routing table and Failure modes |
| B3-7 | high | No defined source for merge settings in the tick. | A3-3 | fixed: merge-lane-design.md, Merge settings source and Merge environment; completed in round 1 by M1-A2, M1-B10 and M1-B15 |
| B3-8 | high | Auto-tier inputs (protected-path list, local-review-skipped evidence, bump type) are undefined or untrusted. | A3-10 | fixed: merge-lane-design.md, Auto-tier script, Git and tool reads and Trust boundaries; completed in round 1 by M1-B1, M1-B11, M1-B12 and M1-B17, in round 2 by M2-B4, M2-B6, M2-B12 and M2-B14, in round 3 by M3-A5, M3-B2 and M3-B4, and in round 4 by M4-C4 and M4-C5 |
| B3-9 | high | Deny rules cannot deliver "a strain cannot merge, change labels or edit the issue" (`gh api`, `curl`, `bash -c`, committed allows), so an injected strain could admit or answer other issues. | | fixed: the claim it attacks is removed by [strain launch](strain-launch-design.md)'s changes 1, 2 and 9 (Decisions, Changes to shared documents), applied in this pull request to ADR-0045 decision 4, the PRD's Merges bullet and ADR-0045's Residuals: deny rules are a barrier against a strain's mistake, not full containment, and a prompt-injected strain stays a named residual. The strain launch review record's `recorded` disposition is not kept, because a recorded high counts as open under ADR-0046 decision 7 |
| B3-10 | medium | A claim is several writes, and the partial states and the sweep are undefined. | | fixed: [Claim sequence](claim-integrity-design.md#claim-sequence) and [Design invariants](claim-integrity-design.md#design-invariants) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-11 | medium | The single-instance lock scope is not stated. | | fixed: [Single-instance lock](claim-integrity-design.md#single-instance-lock), [Lair state root](claim-integrity-design.md#lair-state-root) and [Design invariants](claim-integrity-design.md#design-invariants) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-12 | medium | Session end waits for "branch pushed", which can block forever, and run activity is undefined. | | fixed: the opening list of replaced parent parts now holds the Lifecycle stage 1 sentence; Lifecycle steps 4 and 5 and Strain result and liveness ("Run activity") stand (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| B3-13 | medium | The run outcome to label mapping is incomplete (blocked, complete with no PR, invalid result). | | fixed: merge-lane-design.md, Run outcome to labels; completed in round 2 by M2-A3 |
| B3-14 | medium | Remediation strains leave no GitHub record, their parks have no path, and the halt does not cover them. | | fixed: merge-lane-design.md, Fix-up runs, Markers the merge lane writes, Run outcome to labels and Lifecycle "Stage 4: halt and circuit breaker"; completed in round 1 by M1-A3, M1-B6 and M1-B7, in round 2 by M2-A4, M2-A5, M2-B2 and M2-B10, and in round 3 by M3-B5 |
| B3-15 | medium | Re-claim from the pushed branch has four gaps: moved head, superseded design, unanswered park, decision size limit. | | fixed: Components > Start points (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| B3-16 | medium | The readiness check needs one snapshot, an error state and a cost limit (time-of-check to time-of-use between reads). | | fixed: [Readiness snapshot](claim-integrity-design.md#readiness-snapshot) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-17 | medium | Env values leak into strains both ways, and the marker's source cannot be told. | A3-1 | fixed: Components > Strain launch and settings, and Contracts and seams > Strain environment and Marker check, against a stray or copied marker; a prompt-injected strain that rewrites the Lair's records stays the named residual under Trust boundaries > Strain containment (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| B3-18 | low | The `body_sha256` form is undefined (CRLF, null body). | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-19 | low | The queue report prints issue-derived text raw and gives no cause. | | fixed: [Queue report](claim-integrity-design.md#queue-report) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-20 | low | Verification strategy gaps: test registration in `tools/validate.sh`, overlord prose, injection and halt tests, the halt file path. | | fixed across the three part records: the overlord prose tests and the `tools/validate.sh` registration in the [strain launch review record](strain-launch-review-record.md), the injection and halt tests, the halt file path and their registration in the [claim integrity review record](claim-integrity-review-record.md), and the merge lane's own part in the [merge lane review record](merge-lane-review-record.md) |
| B3-21 | low | The decision digest is only as complete as the strain's report. | | fixed: Components > Strain result and liveness (the engine record at every verified end, with the record call kept back from the cap) and Contracts and seams > Strain result (`decisions` null, shown as unknown, when no record exists) (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| B3-22 | low | The readiness check reads document paths named in the issue body (seam with #615). | | recorded: [Assumptions about #615](claim-integrity-design.md#assumptions-about-615) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |

### First review sources

- claude-mem observation #43827 (pass 1).
- claude-mem observations #43828, #43844, #43845 and #43846 (pass 2).
- The Context section of [ADR-0045](../../adr/0045-lair-software-factory.md).
- Round 3: the PRD, ADR-0045 as amended and the solution design, read directly by the two passes.
- The claude-mem observations above could not be read in the session that wrote round 3, because claude-mem was unavailable. The round 1 and 2 finding text and pass metadata are as supplied in the task brief and were not re-checked against them. Every round 1 decision citation was checked against the ADR-0045 text and holds.

### First review decisions taken

Listed for veto in the first review:

- The PRD's Admission criterion and its admission testing decision are aligned with the ADR-0045 amendment.
- The release-train decisions are deferred with their full scope to #606, so #606 and #612 are not ready yet.
- #608's admission depends on the readiness check from #615. This is recorded in the design's Seam order and left for the maintainer to link.
- This record's keys and disposition vocabulary.
- Rounds 1 and 2 are recorded from the listed findings and ADR-0045.

### First review decisions asked

The ADR-0045 admission amendment was asked of and settled by the user before this work. Its three rules:

- Epics are never claimed.
- An issue is claimed only when the readiness check passes at claim time.
- A failing issue stays unclaimed, is named in the queue report, and gets no new label.

The idea-to-ready work is referred to as #614 and #615; the readiness check comes from #615.

Round 3 did not converge under the 3-round cap. The user was asked to choose: split the initiative, fix and run a fourth round, record and merge, or other. The user chose to split.

- The record stayed at verdict `fail`.
- The user accepted a three-way split on 2026-11-21. Each part was filed as a native sub-issue of #603, to get its own solution design and design review:
  - #630 Lair design: strain launch and containment (A3-1, A3-4, A3-5, A3-6, A3-7, B3-2, B3-9, B3-17).
  - #631 Lair design: merge lane (A3-2, A3-3, A3-10, B3-4, B3-5, B3-6, B3-7, B3-8).
  - #632 Lair design: claim integrity (B3-1, B3-3).
- PR #628 was merged.
