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

# Design review record: Lair claim integrity

This record covers the design review of the [claim-integrity design](claim-integrity-design.md) for issue #632, split from epic #603 after the round-3 review in the epic's [review record](review-record.md).

- **Stamped:** only `claim-integrity-design.md`. Its stamp's blob is `git rev-parse HEAD:docs/initiatives/autonomous-ready-issue-loop/claim-integrity-design.md`. The stamp is written last, after the clean round. Any later edit to the design needs a new round and a new stamp, inside the cap.
- **Reviewed, not stamped:** the [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md) and the [solution design](solution-design.md).
- **Exit:** the review exits only when zero critical or high findings are open and one round raises no new findings. It is capped at 3 rounds.
- **Passes:** each round runs two fresh read-only `hivemind:cerebrate` analysis passes in parallel, each with "Memory context: none".
  - Pass A covers code truth, governance and ADR conflicts, and existing-path coverage.
  - Pass B covers failure modes, trust and injection, and testability.
- **Finding IDs:** new finding IDs take the prefix `C`, then the round, then the pass and the finding's number in that pass. `C1-A2` is round 1, pass A, finding 2.

Each later review round adds its own section after Inherited findings.

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

## Inherited findings

These are the round-3 findings of the epic's [review record](review-record.md) that this issue owns. Each disposition names the section of the [claim-integrity design](claim-integrity-design.md) that answers it. None is open, so `open_counts` is zero.

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| B3-1 | high | The pre-spawn injection scan has no executor. | fixed: [Scanner session](claim-integrity-design.md#scanner-session) |
| B3-3 | high | Marker comments have no author rule, so anyone can forge breaker, budget, park and sweep inputs. | fixed: [Marker signer and verifier](claim-integrity-design.md#marker-signer-and-verifier) |
| B3-10 | medium | A claim is several writes, and the partial states and the sweep are undefined. | fixed: [Claim sequence](claim-integrity-design.md#claim-sequence) |
| B3-11 | medium | The single-instance lock scope is not stated. | fixed: [Single-instance lock](claim-integrity-design.md#single-instance-lock) |
| B3-16 | medium | The readiness check needs one snapshot, an error state and a cost limit. | fixed: [Readiness snapshot](claim-integrity-design.md#readiness-snapshot) |
| A3-12, breaker part | medium | The session-scoped circuit breaker was a design call that should have been asked. | fixed: [Decisions](claim-integrity-design.md#decisions) |
| B3-18 | low | The `body_sha256` form is undefined (CRLF, null body). | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) |
| B3-19 | low | The queue report prints issue-derived text raw and gives no cause. | fixed: [Queue report](claim-integrity-design.md#queue-report) |
| B3-20, owned parts | low | The injection and halt tests, the halt file path, and their registration in `tools/validate.sh`. | fixed: [Verification strategy](claim-integrity-design.md#verification-strategy) |
| B3-22 | low | The readiness check reads document paths named in the issue body (seam with #615). | recorded: [Assumptions about #615](claim-integrity-design.md#assumptions-about-615) |
| A3-17 | low | A parked issue loses its `lair:*` label, so triage no longer skips it. | fixed: [Lifecycle](claim-integrity-design.md#lifecycle) |

A3-11 (incomplete Seam order ADR lists) is met for this scope by the design's [Seam order](claim-integrity-design.md#seam-order), which names the ADRs of each slice this design changes. It is not counted here.

The other parts of A3-12 (no-merge after edit, the CI-red rule) and of B3-20 (overlord prose) are not owned by this issue and are not counted here.

## Sources

- The round-3 findings of the epic's [review record](review-record.md).
- The [claim-integrity design](claim-integrity-design.md) on this branch.
- The user's answers to this run's three Tier A questions, given on 2026-11-21.

## Decisions taken (listed for veto)

- This record reuses the epic review record's keys and disposition vocabulary.
- Only the claim-integrity design is stamped; the PRD, ADR-0045 and the solution design are reviewed, not stamped.
- New finding IDs take the prefix `C`, so they never collide with the epic's `A3-` and `B3-` IDs.
- B3-22 is `recorded`, not `fixed`: the design answers it as an assumption about #615, which owns the readiness check.
- A3-11 is noted as met for this scope, not given a disposition.
- The design's decisions other than the three Tier A answers, each listed in its [Decisions](claim-integrity-design.md#decisions):
  - HMAC-SHA256 with one local key per repository, and a `kid` in every marker.
  - The state root lives outside every checkout and worktree.
  - Every marker reader fails toward stopping, and an invalid or missing marker halts the Lair.
  - Markers are append-only; the outcome is a separate outcome marker, not an edit of the claim marker.
  - Claim write order: claim marker, then labels, then spawn. Run end: outcome marker, then labels.
  - A claim that stopped partway always moves forward to `crashed`, never back to ready and never retried.
  - The sweep covers only Lair issues: a `lair:*` label or a counting claim marker.
  - The lock covers one repository for one account on one machine, through `flock`.
  - One snapshot per candidate, a Lair-side `check-error` state, and at most 5 checks of 60 seconds each per tick.
  - The scan verdict is a token file; only the exact clean token passes, malformed is suspect, and missing is an error.
  - Three consecutive scan errors halt the Lair.
  - The `body_sha256` form: a hash of the title and body hashes, with no normalization.
  - The queue report prints only fixed keys and validated tokens, with a stage and reason codes per failure.
  - A parked issue keeps `lair:claimed`.
  - Only `failed`, `crashed` and `timed-out` outcomes count toward the breaker; a park is skipped, and any other outcome ends a streak.
  - The halt file's path and cause codes.
- The proposed `solution-design.md` Amendments pointer, under the design's Changes to shared documents. It is not applied in this pull request.

## Decisions asked

The user answered three Tier A questions on 2026-11-21 and took the recommended option each time.

- **The pre-spawn injection scan's executor and ADR-0045 decision 10.** Answer, 2026-11-21: the scan runs in a locked-down scanner session, and ADR-0045 decision 10 stays unchanged.
- **Marker authentication.** Answer, 2026-11-21: markers are signed with a key no Lair-started session can read, and count only when unedited and written by the Lair's login. Forgery after a containment escape is a proposed ADR-0045 residual, under the design's Changes to shared documents.
- **The circuit-breaker scope.** Answer, 2026-11-21: the breaker counts the runs that ended in the current Lair session. A trip writes the halt file with its cause, so only the user deleting that file re-arms the Lair.
