---
stamps: []
verdict: pending
open_counts:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 0
clean_round: null
---

# Design review record: Lair strain launch and containment

This record covers the design review of issue #630, the strain launch and containment part of the Lair, epic #603. Only the [strain launch design](strain-launch-design.md) is stamped. Its stamp's blob is `git rev-parse HEAD:docs/initiatives/autonomous-ready-issue-loop/strain-launch-design.md`, and the stamp is written last. The [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md) and the parent [solution design](solution-design.md) are reviewed, not stamped.

The review exits only when zero critical or high findings are open and one round raises no new findings. It runs at most 3 rounds.

Each round is two parallel, fresh, read-only `hivemind:cerebrate` analysis delegations. Neither wrote the design, and each runs with "Memory context: none".

- **Pass A angle:** code truth, governance and ADR conflicts, and existing-path coverage.
- **Pass B angle:** failure modes, trust and injection, and testability.

New finding IDs take the form `L<round>-<pass><n>`, such as `L1-A2`. Any edit to the design after a stamp needs a review round of the change and a new stamp, within the cap.

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

**Open** is a state, not a disposition. An open finding is counted in `open_counts`, and its disposition column reads `open`. `open_counts` counts every finding still without a disposition, the round 3 findings below and every finding a round of this review raises.

### Round 3 findings owned by #630

The round 3 findings come from the parent [review record](review-record.md). #630 owns the findings below. Each disposition names the section of the strain launch design that answers it.

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| A3-1 | high | Lair-written settings do not keep merge keys out of strains. | fixed: Components > Strain launch and settings, and Contracts and seams > Strain settings and Strain environment |
| A3-4 | high | There is no contract for the strain's launch inputs or for carrying parked, branch, head and decisions out of the run result. | fixed: Components > Launch inputs, and Contracts and seams > Launch file and Strain result |
| A3-5 | high | Re-claim and remediation contradict the detached spawn and the brood-child fresh-branch rule. | fixed: Components > Start points |
| A3-6 | high | Governance the strain overlord loads still tells it to ask, and no slice owns the edits. | fixed: Components > Unattended governance edits |
| A3-7 | high | The facts step re-reads referenced issues and outsider comments live. | fixed: Components > Launch inputs ("Facts come only from the captured issue text") |
| B3-2 | high | The strain's model derives launch inputs from the issue text, and the facts step re-reads GitHub live. | fixed: Components > Launch inputs |
| B3-9 | high | Deny rules cannot deliver "a strain cannot merge, change labels or edit the issue". | recorded: Trust boundaries > Strain containment, as the named residual "a prompt-injected strain holds the user's rights", with the reworded claims in Decisions > Changes to shared documents, changes 1 and 2 |
| B3-17 | high | Env values leak into strains both ways, and the marker's source cannot be told. | fixed: Components > Strain launch and settings, and Contracts and seams > Strain environment and Marker check |
| B3-15 | medium | Re-claim from the pushed branch has four gaps: moved head, superseded design, unanswered park, decision size limit. | fixed: Components > Start points |
| A3-9 | medium | Stall and agent-call budget rules rely on signals nothing produces, and the agent-call cap has no owner. | fixed: Components > Strain result and liveness ("Run activity") and Launch inputs ("Agent-call cap") |
| B3-12 | medium | Session end waits for "branch pushed", and run activity is undefined. | fixed: Lifecycle, steps 4 and 5, and Components > Strain result and liveness ("Run activity") |
| A3-14 | low | Remote control on strains is not covered under Trust boundaries. | fixed: Trust boundaries |
| A3-15 | low | The state table omits spawn-brood's files. | fixed: State and ownership |
| B3-21 | low | The decision digest is only as complete as the strain's report. | fixed: Components > Strain result and liveness ("The overlord's call writes the result") |
| B3-20, overlord-prose tests | low | The verification strategy has no overlord prose tests. | fixed: Verification strategy ("Overlord prose tests") |
| B3-20, `tools/validate.sh` registration | low | The verification strategy does not register new tests in `tools/validate.sh`. | fixed: Verification strategy ("Registration in `tools/validate.sh`") |

The other parts of B3-20, the injection and halt tests and the halt file path, are not owned by #630 and stay in the parent review record.

A3-11 is not owned by #630. The design's Seam order meets it for this scope: each slice this design changes names its ADRs.

## Sources

- The parent [review record](review-record.md): the round 3 findings, their severities and the three-way split.
- Issue #630: the findings it owns and its acceptance criteria.
- The [strain launch design](strain-launch-design.md): the sections each disposition names.

## Decisions taken (listed for veto)

- B3-17 is held to the high bar. The round 3 table of the parent review record rates it medium, and #630 lists it with its highs.
- B3-9 is recorded, not fixed: the risk stays as a named residual, with the claims reworded per the user's answers below.
- B3-20 is split into the two parts #630 owns, each with its own disposition.
- Each owned finding is dispositioned before round 1, so `open_counts` starts at zero. Round 1 checks each disposition.
- This record keeps the parent record's keys and disposition vocabulary.

## Decisions asked

The user was asked three always-ask (Tier A) questions and answered each with option A on 2026-11-21:

- Reword ADR-0045 decision 4 to what the settings deliver.
- Reword PRD line 64 to what the settings deliver, with an injected strain as a named residual.
- Reword ADR-0045 decision 3 to name the start points for a first claim, a re-claim and a remediation.

The design's section Decisions > Changes to shared documents holds each rewording as exact proposed text. A later integration issue applies them. None is applied in this pull request.
