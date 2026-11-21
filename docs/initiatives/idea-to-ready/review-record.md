---
stamps:
  - path: docs/prds/idea-to-ready.md
    blob: 87696cdd88a93ab24c9a08010d43e791e0b49d19
  - path: docs/initiatives/idea-to-ready/solution-design.md
    blob: 6c13c1bae864d65829bf5b35089f5be0f4545894
  - path: docs/adr/0046-idea-to-ready-process.md
    blob: 8e0ddc8aa2cfbc4f43ab74bb1a2318d50e488413
  - path: docs/adr/0047-abathur-council.md
    blob: b85ccf3e79f205b7a752c5d83982d7991e099131
verdict: fail
open:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 1
clean_round: false
---

# Design review record: Idea to Ready

Round 1 ran, and every finding is fixed on the docs branch. The record fails the pass rule on three counts: `verdict` is `fail`, `rounds` is 1 and `clean_round` is `false`.

A confirming round follows: round 2, one fresh pass over both angles. The pull request stays a draft until this record passes and its stamps equal the documents at the pull request head.

The stamps are the blobs of commit `1c8528aa18f902ade57dc7dc1433355c10839490`, read with `git rev-parse HEAD:<path>`. Any later edit to a stamped file makes this record stale until a review of the change re-stamps it. The design review skill's verify does not exist yet (#619), so this record is checked by hand.

## Reviewed documents

- [PRD: Idea to Ready](../../prds/idea-to-ready.md)
- [Solution design: Idea to Ready](solution-design.md)
- [ADR-0046](../../adr/0046-idea-to-ready-process.md): the idea-to-ready process
- [ADR-0047](../../adr/0047-abathur-council.md): the Abathur council

The [glossary](../../../CONTEXT.md) edits were reviewed but are not stamped.

## Rounds

### Round 1

Two parallel passes. Each was fresh and read-only, ran with `Memory context: none`, and neither reviewer wrote the design.

- Angle A: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Code truth, governance and ADR conflicts, existing-path coverage.
- Angle B: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Failure modes, trust and injection, testability.

## Findings

Local review reported no severity for d224e40e, 820000d7 and 0c9bd346. The severities below are assigned to match the finding each one shares a fix with: B18, B9 and B5.

| ID | Round | Angle | Severity | Disposition | Note |
|---|---|---|---|---|---|
| A1 | 1 | A | high | fixed | The consult is a step ahead of an unchanged `decide()`. No `council_split` ask reason and no `council` list reason. The Ask Set is unchanged (D25). |
| A2 | 1 | A | high | fixed | The runner member runs through a sixth runner-gate script. Coverage lists the hook, `security-policy.md` and the gate fixture (D22, answer Q3). |
| A3 | 1 | A | high | fixed | #622 adds both council agents to the overlord's Agent allowlist (D23, answer Q4). |
| A4 | 1 | A | high | fixed | The consult setting is a top-level `council_consult` object projected by `projectAutonomyTable`. The table rows are unchanged. |
| A5 | 1 | A | medium | fixed | The consult count is script-local and rebuilt on replay. `resume_args` is unchanged. |
| A6 | 1 | A | medium | fixed | The `unattended` value is set when #607 adds that level (D18). |
| A7 | 1 | A | medium | fixed | The runner identity names the tool. Only a JSON argv list runs a runner member. |
| A8 | 1 | A | high | fixed | The guide (#622) creates the docs branch, commits the stage-2 and stage-3 outputs through `hivemind:molt` and moves the pull request out of draft. |
| A9 | 1 | A | medium | fixed | Design decisions read Promotion Gate clauses 1 and 3. The always-ask list replaces clause 2 (D27). |
| A10 | 1 | A | medium | fixed | Triage overlay plus a post-apply re-check (#620). |
| A11 | 1 | A | medium | fixed | Coverage names the lib call sites, `pauseDelivery`, `safety-ask-set.json` and `ask-set.test.mjs`. The other workflows pass no council settings. |
| A12 | 1 | A | medium | fixed | Council fields are bounded. `data.test.mjs` checks the bounds under #618. |
| A13 | 1 | A | medium | fixed | #622 is blocked by #618 and owns the design-stage caller, Standalone spec block format and Consult setting. #620, #621 and #623 own the output contract. Failure rows and trust bullets name their slices. |
| A14 | 1 | A | medium | fixed | D20 covers every budgeted file a slice edits. |
| A15 | 1 | A | medium | fixed | The ADR-0026 decision 2 amendment is narrowed to the design stages and standard-delivery. |
| A16 | 1 | A | medium | fixed | A coverage row assigns the Lair retrofit to #625 and says how it is verified. |
| A17 | 1 | A | medium | fixed | A review fix gets one confirming pass, not counted toward the cap. |
| A18 | 1 | A | low | fixed | D15 and D17 cite ADR-0046. |
| A19 | 1 | A | low | fixed | The glossary entries are qualified and reworded. |
| A20 | 1 | A | low | fixed | Verification names `tools/test_run_review.sh`, `tools/test_subissue_ops.sh` and the prd-to-issues carve-out. |
| B1 | 1 | B | critical | fixed | The caller composes the brief, provenance comes from launch records, and a switched option is gated by its own gate or asks (D26). |
| B2 | 1 | B | high | fixed | A pass that errors yields no round. |
| B3 | 1 | B | high | fixed | Slug binding, `design_link_invalid` and `record_unstamped`. |
| B4 | 1 | B | high | fixed | `dependency_edge_missing`. Edges are written before the re-check. |
| B5 | 1 | B | high | fixed | Authority is a human-reviewed merge, only the drone step writes the record, and #623 protects docs paths (D24, answer Q5). The auto-merge exposure stays as a residual, recorded under Residuals. |
| B6 | 1 | B | medium | fixed | Path allowlist before any git call, line-index reason codes, `jq --arg` and encoded reports. |
| B7 | 1 | B | medium | fixed | Existence rule and truncation rule. Callers discard a failed run. |
| B8 | 1 | B | medium | fixed | Callers pass a fetched commit id, checked as 40 or 64 hex. The output names the commit. |
| B9 | 1 | B | medium | fixed | `rounds` is 2 to 3 in a passing record, and the open rule defines the counts. |
| B10 | 1 | B | medium | fixed | The record is rewritten every round. A lost session resumes from `rounds`. |
| B11 | 1 | B | medium | fixed | Verify runs before ready and in CI (D28). |
| B12 | 1 | B | medium | fixed | Duplicate of A5, fixed by the same change. |
| B13 | 1 | B | medium | fixed | Duplicate of A6, fixed by the same change. #624 tests that an unattended split parks. |
| B14 | 1 | B | medium | fixed | The runner kernel is named. Both council agents are pinned read-only. |
| B15 | 1 | B | medium | fixed | Delegations carry the Data-Boundary Constraint. A suspect opinion stops at the `injection_suspect` hard stop. |
| B16 | 1 | B | medium | fixed | Design-stage resolution is judgment, checked through always-ask screens (D27). |
| B17 | 1 | B | medium | fixed | Document parsing rules and template codes. `design_block_missing`. |
| B18 | 1 | B | medium | fixed | Stamps include every ADR the docs pull request adds or edits. This record stamps ADR-0046 and ADR-0047. |
| B19 | 1 | B | medium | fixed | Re-review rules. `**Status:** delivered` is read first. |
| B20 | 1 | B | medium | fixed | Seed marker and a write-permission author. Only same-repository pull request heads count. |
| B21 | 1 | B | low | fixed | The latest-label check (D29). |
| B22 | 1 | B | low | fixed | A concurrency failure row. |
| B23 | 1 | B | low | fixed | Blob ids are 40 or 64 hex. |
| d224e40e | 1 | review | medium | fixed | Raised by local review before round 1. Same fix as B18. |
| 820000d7 | 1 | review | medium | fixed | Raised by local review before round 1. The Review record body table and verify make dispositions checkable (D28). |
| 0c9bd346 | 1 | review | high | fixed | Raised by local review before round 1. Write permission on the labeled event is the authority, and "maintainer" names a role (D29). |

## Decisions taken, listed for veto

Each decision has its always-ask screen: an answer to each of the four always-ask items. "no" means the decision does not do that.

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
|---|---|---|---|---|
| D1: Guide is a user-only conductor skill | no | no | no | no |
| D2: Stage derived only from GitHub and git | no | no | no | no |
| D3: One deterministic readiness check shared by three callers | no | no | no | no |
| D4: Track read from the native parent and labels | no | no | no | no |
| D5: Per-initiative docs folder | no | no | no | no |
| D6: Design review by fresh read-only planner passes | no | no | no | no |
| D7: Review record front matter with blob stamps | no | no | no | no |
| D8: Ready label allowed with open blockers | no | no | no | no |
| D9: Design-decision always-ask rule | no | no | no | no |
| D10: Delivered design frozen as history | no | no | no | no |
| D11: No dedicated different-model design pass in v1 | no | no | no | no |
| D12: Abathur council with two callers | no | no | no | no |
| D13: Consult setting as data with a per-run cap | no | no | no | no |
| D14: Council member named Overseer | no | no | no | no |
| D15: Drone with exact file scope writes designs and records | no | no | no | no |
| D16: Process and council get separate ADRs | no | no | no | no |
| D17: Readiness check is a shared library | no | no | no | no |
| D18: Initial consult setting values | no | no | no | no |
| D19: Native blocked-by edges written at triage | no | no | no | no |
| D25: Consult step with decide unchanged | no | Within D21's approved amendment of ADR-0036 decision 6. ADR-0037 is not amended. | no | no |
| D26: Caller composes the council brief | no | no | Narrows the council's authority in this unmerged design and widens none. | no |
| D27: Design-stage resolution is judgment checked by review | no | no | no | no |
| D28: Record verified before ready and on every push | no | no | no | no |
| D29: Write permission is the ready label's authority | no | Restates ADR-0045 decision 10, as amended by #625. | no | no |
| A1 redesign: the consult wraps an unchanged `decide()` (D25) | no | No. ADR-0037's closed Ask Set, list reasons and check order are unchanged. | no | no |
| ADR-0042 decision 9 is not amended | no | No. `run-review.sh` still runs every local review; the runner member is a separate gate script. | The sixth runner-gate script was asked (D22); this decision adds no change. | no |
| A15: the ADR-0026 decision 2 amendment narrowed to the design stages and standard-delivery | no | Narrows the amendment approved under D21 and adds none. | no | no |
| A16: the PRD's Lair retrofit criterion covered by #625 | No. The criterion stands, and #625's acceptance criteria verify it. | no | no | no |
| Local-review severities: d224e40e medium, 820000d7 medium, 0c9bd346 high | no | no | no | No. All three are fixed, so the open counts do not depend on the severities. |
| Round-0 placeholder record, now replaced by this record | no | no | no | No. This record replaces it. |
| Duplicates merged: A5 with B12, A6 with B13 | no | no | no | no |
| Every other finding fixed as recommended | no | no | The trust-boundary and merge-path fixes were asked (D22, D23, D24). | no |

## Decisions asked

- D20, prose budget with no pre-approved raise. The user's answer: Q1 B, no budget raise is pre-approved.
- D21, accepted-ADR amendments recorded in ADR-0047. The user's answer: Q2 A, the amendments of ADR-0026, ADR-0036 and ADR-0045 are recorded in ADR-0047 only.
- D22, runner member through a sixth runner-gate script. The user's answer: Q3 A, take the recommendation.
- D23, overlord may launch the council agents. The user's answer: Q4 A, take the recommendation.
- D24, review record authority is a human-reviewed merge. The user's answer: Q5 A, take the recommendation.

## Residuals

Auto-merge of a docs pull request, from finding B5:

- Scope: with `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a bot approval and green checks with no human review of the design.
- Ground: the user's decision of 2026-11-21 (answer Q5). It is outside the threat model as the maintainer's own opt-in under [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md).
- Bounded impact: verify in CI keeps a merged record consistent and current, and #623 closes the Lair path. A wrong design is caught only by a later review.
- Recorded in [ADR-0046](../../adr/0046-idea-to-ready-process.md), Residuals.
