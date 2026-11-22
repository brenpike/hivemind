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
| A3-1 | high | Lair-written settings do not keep merge keys out of strains. | fixed: Components > Strain launch and settings, and Contracts and seams > Strain settings and Strain environment, for the user, project and local scopes; a managed merge key stays the named residual "managed settings" under Trust boundaries > Strain containment |
| A3-4 | high | There is no contract for the strain's launch inputs or for carrying parked, branch, head and decisions out of the run result. | fixed: Components > Launch inputs, and Contracts and seams > Launch file and Strain result |
| A3-5 | high | Re-claim and remediation contradict the detached spawn and the brood-child fresh-branch rule. | fixed: Components > Start points, where the remote compares the pre-image at the write: Lair mode of `push-branch.sh` pushes with a lease pinned to the pre-image the Lair captured, after an ancestry check, and the engine maps its fixed blocker line to `start_moved`; and the Failure modes rows "Start moved", "Moved head before a re-claim launch" and "Moved head before a remediation launch" |
| A3-6 | high | Governance the strain overlord loads still tells it to ask, and no slice owns the edits. | fixed: Components > Unattended governance edits |
| A3-7 | high | The facts step re-reads referenced issues and outsider comments live. | fixed: Components > Launch inputs ("Facts come only from the captured issue text") |
| B3-2 | high | The strain's model derives launch inputs from the issue text, and the facts step re-reads GitHub live. | fixed: Components > Launch inputs |
| B3-9 | high | Deny rules cannot deliver "a strain cannot merge, change labels or edit the issue". | recorded: Trust boundaries > Strain containment, as the named residual "a prompt-injected strain holds the user's rights", with the reworded claims in Decisions > Changes to shared documents, changes 1 and 2 |
| B3-17 | high | Env values leak into strains both ways, and the marker's source cannot be told. | fixed: Components > Strain launch and settings, and Contracts and seams > Strain environment and Marker check, against a stray or copied marker; a prompt-injected strain that rewrites the Lair's records stays the named residual under Trust boundaries > Strain containment |
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
- The local review root-cluster report on the design's start-point paragraph: local review iterations 1, 3 and 4 each found a branch move that fell after a start check, and a fourth finding showed that a plain push accepts a move the strain absorbed, such as a move it fetched and merged during the run.

## Decisions taken (listed for veto)

- B3-17 is held to the high bar. The round 3 table of the parent review record rates it medium, and #630 lists it with its highs.
- B3-9 is recorded, not fixed: the risk stays as a named residual, with the claims reworded per the user's answers below.
- B3-20 is split into the two parts #630 owns, each with its own disposition.
- Each owned finding is dispositioned before round 1, so `open_counts` starts at zero. Round 1 checks each disposition.
- This record keeps the parent record's keys and disposition vocabulary.
- The start-move class is fixed by changing the push's key from fast-forward acceptance to the remote branch's pre-image, the commit the run started from, which the remote compares at the write. The overlord's head recheck after the switch is removed (Components > Start points).
- Lair mode of `push-branch.sh` pushes with a lease pinned to the start commit, `--force-with-lease=refs/heads/<b>:<pre-image>`, with an empty value on a first claim, after an ancestry check so the push never rewrites the branch. This reverses the design's earlier wording that a strain's push is never forced. Taken under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal): a strong recommendation with a clean gate, and reversible.
- A refused first-claim push goes to `lair:failed`, counted toward the circuit breaker (Failure modes, row "Start moved").
- No deny rule on force flags is added: the workflow's lease is pinned to a value the Lair captured, and a push a strain runs by hand stays inside the named residual (Trust boundaries > Strain containment).
- No mid-run poll of the remote branch is designed: only the pinned-lease push sees a move made during the run. The wasted run time of a strain whose branch moved mid-run is a recorded residual in Components > Start points. The run took option A of Q1, a strong recommendation.

## Decisions asked

The user was asked four always-ask (Tier A) questions and answered each with option A on 2026-11-21:

- Reword ADR-0045 decision 4 to what the settings deliver.
- Reword PRD line 64 to what the settings deliver, with an injected strain as a named residual.
- Reword ADR-0045 decision 3 to name the start points for a first claim, a re-claim and a remediation.
- Local review finding f26808d3 on the remediation author filter: keep the in-scope Bot exception as trusted. Changes 4 and 5 of the design propose the matching PRD line 62 and ADR-0045 decision 11 wording.

On 2026-11-21 the user chose "change approach" when local review reported the root cluster on the design's start-point construct: the push is keyed on the remote branch's pre-image instead of another patch to the fast-forward rule.

The design's section Decisions > Changes to shared documents holds each rewording as exact proposed text. A later integration issue applies them. None is applied in this pull request.
