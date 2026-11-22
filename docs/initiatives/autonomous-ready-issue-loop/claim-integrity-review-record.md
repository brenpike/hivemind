---
stamps: []
verdict: pending
open_counts:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 1
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

These are the round-3 findings of the epic's [review record](review-record.md) that this issue owns. Each disposition names the section of the [claim-integrity design](claim-integrity-design.md) that answers it. None is open, so `open_counts` is zero. Round 1's pass B found B3-20 and A3-17 not yet closed; the round-1 fixes close both, as their rows say.

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| B3-1 | high | The pre-spawn injection scan has no executor. | fixed: [Scanner session](claim-integrity-design.md#scanner-session) and [Contracts and seams](claim-integrity-design.md#contracts-and-seams) |
| B3-3 | high | Marker comments have no author rule, so anyone can forge breaker, budget, park and sweep inputs. | fixed: [Marker signer and verifier](claim-integrity-design.md#marker-signer-and-verifier) and [Design invariants](claim-integrity-design.md#design-invariants) |
| B3-10 | medium | A claim is several writes, and the partial states and the sweep are undefined. | fixed: [Claim sequence](claim-integrity-design.md#claim-sequence) and [Design invariants](claim-integrity-design.md#design-invariants) |
| B3-11 | medium | The single-instance lock scope is not stated. | fixed: [Single-instance lock](claim-integrity-design.md#single-instance-lock), [Lair state root](claim-integrity-design.md#lair-state-root) and [Design invariants](claim-integrity-design.md#design-invariants) |
| B3-16 | medium | The readiness check needs one snapshot, an error state and a cost limit. | fixed: [Readiness snapshot](claim-integrity-design.md#readiness-snapshot) |
| A3-12, breaker part | medium | The session-scoped circuit breaker was a design call that should have been asked. | fixed: [Decisions](claim-integrity-design.md#decisions) |
| B3-18 | low | The `body_sha256` form is undefined (CRLF, null body). | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) |
| B3-19 | low | The queue report prints issue-derived text raw and gives no cause. | fixed: [Queue report](claim-integrity-design.md#queue-report) |
| B3-20, owned parts | low | The injection and halt tests, the halt file path, and their registration in `tools/validate.sh`. | fixed: [Verification strategy](claim-integrity-design.md#verification-strategy), which names the injection suite `tools/test_lair_text.sh` and registers all four suites (round 1, C1-B26) |
| B3-22 | low | The readiness check reads document paths named in the issue body (seam with #615). | recorded: [Assumptions about #615](claim-integrity-design.md#assumptions-about-615) |
| A3-17 | low | A parked issue loses its `lair:*` label, so triage no longer skips it. | fixed: [Lifecycle](claim-integrity-design.md#lifecycle), with the solution design's Lifecycle line "with `lair:claimed` removed" superseded in the design's opening list and the proposed Amendments pointer (round 1, C1-A1) |

A3-11 (incomplete Seam order ADR lists) is met for this scope by the design's [Seam order](claim-integrity-design.md#seam-order), which names the ADRs of each slice this design changes. It is not counted here.

The other parts of A3-12 (no-merge after edit, the CI-red rule) and of B3-20 (overlord prose) are not owned by this issue and are not counted here.

## Round 1, 2026-11-21

Two passes, run in parallel, each a fresh read-only `hivemind:cerebrate` analysis delegation with "Memory context: none". Pass A covered code truth, governance and ADR conflicts, and existing-path coverage; pass B covered failure modes, trust and injection, and testability. They reviewed the design at blob `d7a124adb26c5e90553ec1686727bd6da5b738cf`.

Result: 0 critical, 5 high, 22 medium and 18 low, 45 findings in all. Every finding has a disposition: 43 fixed and 2 recorded, so none is open. Two findings needed the user: C1-A5 and C1-A6 with C1-B6, answered on 2026-11-21 under Decisions asked. The rest follow the decisions taken for the user, listed for veto below. The round raised new findings, so it is not clean, and the design gets a new round before any stamp.

Pass B's owned round-3 status: B3-1, B3-3, B3-10, B3-11, B3-16, B3-18, B3-19 and the breaker part of A3-12 closed, and B3-22 recorded. B3-20 and A3-17 were not closed; the fixes for C1-B26 and C1-A1 close them, as Inherited findings says.

Section links below go to the [claim-integrity design](claim-integrity-design.md).

### Pass A findings

| ID | Severity | Finding | Overlaps | Disposition |
| --- | --- | --- | --- | --- |
| C1-A1 | high | The supersede list misses five solution-design lines: the park label move, the outcome in the claim marker, the start-up sweep, and the Crash and Stall rows. | C1-B9 | fixed: the design's opening list and [Changes to shared documents](claim-integrity-design.md#changes-to-shared-documents) |
| C1-A2 | high | `stalled` does not count toward the breaker, against the solution design and the PRD. | C1-B8 | fixed: [Lifecycle](claim-integrity-design.md#lifecycle), [Assumptions about #631](claim-integrity-design.md#assumptions-about-631), [Decisions](claim-integrity-design.md#decisions) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-A3 | high | The scanner starts like a strain in auto mode, and allow-only settings do not deny everything else. | C1-B1 | fixed: [Scanner session](claim-integrity-design.md#scanner-session), [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Scanner launch, Scanner session settings), [Assumptions about #604](claim-integrity-design.md#assumptions-about-604) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-A4 | medium | A `Write(path)` rule never matches; only `Edit(path)` governs writes. | C1-B1 | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Scanner session settings) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-A5 | high | The key is out of reach only of Lair-started sessions; other sessions of the same user can read it. | | fixed: [Trust boundaries](claim-integrity-design.md#trust-boundaries), [Existing-path coverage](claim-integrity-design.md#existing-path-coverage) and [Changes to shared documents](claim-integrity-design.md#changes-to-shared-documents), per the user's answer under Decisions asked |
| C1-A6 | medium | The key, the session marker ids and the ended-run list cannot be rebuilt from GitHub, against ADR-0045 decision 2. | C1-B6 | fixed: [State and ownership](claim-integrity-design.md#state-and-ownership), [Lifecycle](claim-integrity-design.md#lifecycle) and [Changes to shared documents](claim-integrity-design.md#changes-to-shared-documents), per the user's answer under Decisions asked |
| C1-A7 | medium | The lane read and the live-strain read are not claim inputs and are not re-taken. | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Snapshot, tick guards) and [Lifecycle](claim-integrity-design.md#lifecycle) (claim step 5) |
| C1-A8 | medium | The orphan rule says "no Lair pull request"; the PRD says "no pull request". | | fixed: [Design invariants](claim-integrity-design.md#design-invariants) (Claim state) and the decision 17 amendment under [Changes to shared documents](claim-integrity-design.md#changes-to-shared-documents) |
| C1-A9 | medium | A handed-off issue moved to `readiness:implementation` by hand is swept as an orphan each tick. | | fixed: [Design invariants](claim-integrity-design.md#design-invariants) (Claim state), the decision 17 amendment and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-A10 | medium | #605 needs the verifier and read library, which #608 builds after it. | | fixed: [Seam order](claim-integrity-design.md#seam-order) and [Design invariants](claim-integrity-design.md#design-invariants) (Unavailable reads): #605 builds them |
| C1-A11 | medium | Seam order lacks a #610 row and some ADRs for #605 and #608. | | fixed: [Seam order](claim-integrity-design.md#seam-order) |
| C1-A12 | medium | Strains start through brood tooling, which pastes issue text into the pane. | | recorded: [Assumptions about #630](claim-integrity-design.md#assumptions-about-630) (Task text by file), cited by [Design invariants](claim-integrity-design.md#design-invariants) (Lair-written text) |
| C1-A13 | medium | The HMAC primitive is unnamed, `openssl -hmac` takes the key on argv, and macOS has no `flock`. | C1-B25 | fixed: [Marker signer and verifier](claim-integrity-design.md#marker-signer-and-verifier), [Context and code truth](claim-integrity-design.md#context-and-code-truth) and [Lifecycle](claim-integrity-design.md#lifecycle) (Start steps 1 and 9) |
| C1-A14 | low | Wording: `reply-resolve.sh` also writes a marker, `--settings` is conditional, and both sentinels start with `<!-- `. | | fixed: [Context and code truth](claim-integrity-design.md#context-and-code-truth) and [Existing-path coverage](claim-integrity-design.md#existing-path-coverage) |
| C1-A15 | medium | Decision 17's session and worktree sweep has no owner, and scanner leftovers are not removed. | C1-B20 | fixed: [Assumptions about #630](claim-integrity-design.md#assumptions-about-630) (Orphaned strain sessions and worktrees) and [Lifecycle](claim-integrity-design.md#lifecycle) (Start step 7) |
| C1-A16 | low | The proposed residual edits the original Residuals section, "counting" is undefined in ADR terms, and the per-tick clause goes beyond the user's answer. | | fixed: [Changes to shared documents](claim-integrity-design.md#changes-to-shared-documents) |
| C1-A17 | low | "On a park" should be "on an answerable park"; approval and third parks take #631's mapping. | | fixed: [Lifecycle](claim-integrity-design.md#lifecycle) |
| C1-A18 | low | The Lair's halt write is not an exclusive create. | C1-B16 | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Halt file) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-A19 | low | Start omits the repository node-id read, the session id, and creating `scan/` and `cache/`. | C1-B14 | fixed: [Lifecycle](claim-integrity-design.md#lifecycle) (Start) |

### Pass B findings

| ID | Severity | Finding | Overlaps | Disposition |
| --- | --- | --- | --- | --- |
| C1-B1 | high | The scanner is not locked down in auto mode. | C1-A3 | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Scanner launch, Scanner session settings), [Assumptions about #604](claim-integrity-design.md#assumptions-about-604) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B2 | medium | Plugin hooks such as claude-mem's capture could store injected text. | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Scanner launch, Scanner session settings), [Assumptions about #630](claim-integrity-design.md#assumptions-about-630) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B3 | medium | The default tmux server is a channel between sessions. | | fixed: [Lair state root](claim-integrity-design.md#lair-state-root), [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Scanner launch), [Assumptions about #630](claim-integrity-design.md#assumptions-about-630) (Tmux reach) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B4 | medium | The lock and `cache/` are within a session's reach. | | fixed: [Lair state root](claim-integrity-design.md#lair-state-root), [Design invariants](claim-integrity-design.md#design-invariants) (Lock scope) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B5 | medium | A half-written key is possible. | | fixed: [Marker signer and verifier](claim-integrity-design.md#marker-signer-and-verifier) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B6 | medium | Key loss has no bounded recovery. | C1-A6 | fixed: [Lifecycle](claim-integrity-design.md#lifecycle) (Start step 8, key reset), [Failure modes](claim-integrity-design.md#failure-modes) and [Changes to shared documents](claim-integrity-design.md#changes-to-shared-documents) |
| C1-B7 | medium | Stop controls fail open: the breaker runs only after an outcome marker, a halt write can fail, and the budget skips on an unavailable read. | | fixed: [Lifecycle](claim-integrity-design.md#lifecycle) (tick, budget, halt and breaker) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B8 | medium | `stalled` and `blocked` end a streak. | C1-A2 | fixed: [Lifecycle](claim-integrity-design.md#lifecycle) and [Decisions](claim-integrity-design.md#decisions); the solution design's Stall row is superseded |
| C1-B9 | medium | The supersede list misses six solution-design lines, the restart re-arm sentence included. | C1-A1 | fixed: the design's opening list and [Changes to shared documents](claim-integrity-design.md#changes-to-shared-documents) |
| C1-B10 | medium | Any commenter can block a claim forever. | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Snapshot), [Lifecycle](claim-integrity-design.md#lifecycle) (claim steps 5 and 8) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B11 | medium | More than one page of comments makes an issue unreadable forever. | | fixed: [Design invariants](claim-integrity-design.md#design-invariants) (Unavailable reads), [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Snapshot), [Lifecycle](claim-integrity-design.md#lifecycle), [Failure modes](claim-integrity-design.md#failure-modes) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B12 | medium | The park slot can break out of its fence. | | fixed: [Design invariants](claim-integrity-design.md#design-invariants) (Lair-written text) and [Verification strategy](claim-integrity-design.md#verification-strategy) (`tools/test_lair_text.sh`) |
| C1-B13 | medium | The lock scope depends on `XDG_STATE_HOME`. | | fixed: [Lair state root](claim-integrity-design.md#lair-state-root) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B14 | low | Start omits the repository node-id read. | C1-A19 | fixed: [Lifecycle](claim-integrity-design.md#lifecycle) (Start step 2) |
| C1-B15 | low | The handoff marker's nonce clause cannot be checked from GitHub. | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Counting rule) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B16 | low | No recovery rule per halt cause, and the halt-write semantics are unset. | C1-A18 | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Halt file) and [Lifecycle](claim-integrity-design.md#lifecycle) |
| C1-B17 | low | The verdict token is brittle. | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Verdict file) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B18 | low | The scan id format is undefined. | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Marker payload) |
| C1-B19 | low | The `input.txt` wording and the JSON extraction are loose. | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (`body_sha256`, Scan input) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B20 | low | Orphaned scanner sessions and scan directories are never removed. | C1-A15 | fixed: [Lifecycle](claim-integrity-design.md#lifecycle) (Start step 7) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B21 | low | The result file is not bound to its strain. | | recorded: [Assumptions about #630](claim-integrity-design.md#assumptions-about-630) (Result file per strain), [Assumptions about #631](claim-integrity-design.md#assumptions-about-631) (Result field checks) and [Trust boundaries](claim-integrity-design.md#trust-boundaries) (The strain result) |
| C1-B22 | low | The breaker's attribution of sweep crashes is undefined. | | fixed: [Lifecycle](claim-integrity-design.md#lifecycle), [Decisions](claim-integrity-design.md#decisions) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B23 | low | A `check-error` can starve the queue. | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Readiness-check call at claim) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B24 | low | A `lastEditedAt` that ties with the label event is undefined. | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (Unedited since the admitting event) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B25 | low | The signing tool is unnamed. | C1-A13 | fixed: [Marker signer and verifier](claim-integrity-design.md#marker-signer-and-verifier) and [Verification strategy](claim-integrity-design.md#verification-strategy) |
| C1-B26 | low | Testability gaps: no named injection suite and its registration, and missing cases. | | fixed: [Verification strategy](claim-integrity-design.md#verification-strategy). The asked marker-missing-id case is replaced by deleted-marker cases, since the cache of marker ids it tested is dropped under the user's rebuildable-state answer. |

## Sources

- The round-3 findings of the epic's [review record](review-record.md).
- The [claim-integrity design](claim-integrity-design.md) on this branch.
- The user's answers to this run's four Tier A questions before round 1, and to two more after it, all given on 2026-11-21.
- The pre-PR local review of this branch, whose root-cluster finding, design-invariant drift, the [Design invariants](claim-integrity-design.md#design-invariants) subsection answers. It found the orphan rule stated differently by the reconciler and the proposed decision 17 amendment, a lock scope that did not match its claims, and park marker text that broke the untrusted-text rule.
- A second root-cluster finding of the same local review: each site listed its path's preconditions instead of deriving them from the inputs it depends on. The claim's re-read before the claim marker missed admission inputs, and an unreadable state root still reconciled and reported. The claim's re-take of every claim input under [Lifecycle](claim-integrity-design.md#lifecycle) answers the re-read. The first answer to the rest, a table of inputs per controller path, was replaced after the third finding below; invariant Unavailable reads in [Design invariants](claim-integrity-design.md#design-invariants) now answers it.
- A third root-cluster finding of the same local review: the table of inputs per controller path, the earlier fix, again omitted reads and writes its paths make: the permission read, the pull request and session lookups, result files, park answers, the merge lane, report state, handoff writes and the key creation of a first start. The user chose to change approach. Invariant Unavailable reads in [Design invariants](claim-integrity-design.md#design-invariants) answers it with no list per path: a guard's reads are the reads its own definition names. The content defects the table hid are answered by Start under [Lifecycle](claim-integrity-design.md#lifecycle), the verifier's results under [Contracts and seams](claim-integrity-design.md#contracts-and-seams), and the scanner launch as an action in the claim sequence under [Lifecycle](claim-integrity-design.md#lifecycle).
- The round-1 reports of passes A and B, and the Claude Code permission-mode and CLI documentation read on 2026-11-21 for the scanner launch.

## Decisions taken (listed for veto)

- This record reuses the epic review record's keys and disposition vocabulary.
- Only the claim-integrity design is stamped; the PRD, ADR-0045 and the solution design are reviewed, not stamped.
- New finding IDs take the prefix `C`, so they never collide with the epic's `A3-` and `B3-` IDs.
- B3-22 is `recorded`, not `fixed`: the design answers it as an assumption about #615, which owns the readiness check.
- A3-11 is noted as met for this scope, not given a disposition.
- C1-A12 and C1-B21 are `recorded`, not `fixed`: the design answers each as an assumption about #630 or #631, which own the strain launch and the result file.
- Round 1 decisions taken for the user:
  - A `stalled` outcome counts toward the breaker, as the solution design's Lifecycle and Stall row say. A `blocked` outcome is skipped: it neither counts nor ends a streak. `parked` is skipped too, and only `complete` ends a streak.
  - The orphan rule's "no pull request" means any pull request linked to the issue, open or merged, by any author, as the PRD says. The PRD is not changed.
  - The per-tick reconcile rests on ADR-0045 decision 2's per-tick reconcile. The proposed decision 17 amendment keeps only the Lair-issue scope the user approved.
  - Proposed ADR text goes in dated amendment sections, never into the original Residuals section, and "counting" is defined in ADR terms.
  - The scanner runs in `dontAsk` permission mode, not auto, with explicit deny rules (`Bash`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, `Task`, `Agent`, `mcp__*`), `Edit(//<abs state root>/scan/<scan-id>/verdict)` as the only write rule, an empty start folder outside every repository, only the hivemind plugin, no hooks, and a private tmux socket under `control/`.
  - The lock and `cache/` move under `control/`, and each tick checks that the lock path still names the locked file. Start anchors the state root to the password-database home and ignores `XDG_STATE_HOME` and `HOME`.
  - The key is written atomically: a temporary file, flushed, then linked without replacing. Every read checks a regular file, the owner, mode 0600 and exactly 32 bytes, and Start checks the state root and `control/` with `lstat`. HMAC-SHA256 is built from the SHA-256 tool with key bytes only on pipes, never on a command line or in an environment, and Start checks it against an RFC 4231 vector. Linux and macOS are supported, with `flock` installed on macOS.
  - A candidate under another `kid` is foreign: it never counts and never halts. This lets a key reset need no stored list of retired keys; a replaced key or a second Lair is still caught by the `lair:claimed` rule.
  - The user's key reset is a start with `--retire-kid <kid>` for each old key the refusal named. The retired id is not stored.
  - The session id, the runs this session launched and ended, their claim and end times, the failed-check fingerprints, the re-take abort counts and a halt that could not be written live only in memory. The cache of marker comment ids and of spawned and ended nonces is dropped, so `marker-missing` comes only from the `lair:claimed` rule.
  - The breaker reads the outcome markers of runs this session launched, every tick, and counts an unavailable read as undecided, so no claim follows. A claim an earlier session made, ended `crashed` by this session's reconciler, is not counted.
  - A halt the Lair cannot write holds in memory and is retried each tick, until an entry exists.
  - The budget clock starts at the claim time held in memory, or at the claim marker's `at` for an earlier session's live strain, and an unavailable read never pauses it.
  - The re-take compares only the claim-relevant fields, the Lair-login marker candidates among the comments, and the tick guards: the halt, the breaker, the lane read and the live-strain read. `updatedAt` and other comments are not read. The trunk commit is pinned at the snapshot, and the strain starts there. After 3 ended attempts an issue is skipped for the rest of the session and reported with stage `retake`.
  - Every connection is paged to its end, up to 10 pages of 100 nodes. Past that a candidate is reported with `too-large`, and a Lair issue halts the Lair with cause `too-large`.
  - The halt file is written only by exclusive create. Each cause names the user's action before deleting it, and a non-regular entry halts as `user` without being opened.
  - The park slot holds only Unicode categories L, M, N, P and S, the space and LF, inside a backtick fence one longer than its longest backtick run.
  - The verdict file starts as a `pending` placeholder line the scanner edits, accepted with or without one trailing LF, and read only when two reads 2 seconds apart agree.
  - Readiness checks start after the last issue checked the tick before, so an erroring issue cannot starve the queue.
  - The read library, the marker format and the verifier are built by #605, the first slice that reads a marker. The solution design's build order stands.
  - The injection and queue-report tests live in `tools/test_lair_text.sh`, registered in all five `tools/validate.sh` places with the other three suites.
- The design's other decisions, each listed in its [Decisions](claim-integrity-design.md#decisions):
  - Markers are append-only; the outcome is a separate outcome marker, not an edit of the claim marker.
  - Claim write order: claim marker, then labels, then spawn. Run end: outcome marker, then labels.
  - A claim that stopped partway always moves forward to `crashed`, never back to ready and never retried.
  - Claim state is derived once, in invariant Claim state, and labels follow counting markers under invariant Markers and labels. The reconciler moves labels forward only, and skips repair when a `readiness:ready` labeled event is newer than the latest counting outcome or handoff marker, since that event is the user's re-admission.
  - One lock scope, invariant Lock scope: one repository, one user account and one machine, through `flock` on `control/lock`, taken before any write other than creating the state root, `control/` and the lock file. The lock descriptor is never inherited.
  - Invariant Unavailable reads: every controller read returns a value or `unavailable`. A guard that uses an unavailable read does not fire, and neither does its negation. A guard's reads are the reads its own definition names; no list of inputs per path exists. Availability is never stored, and every controller read goes through one recording library.
  - Start runs once, in a fixed order, each step with its own failure code, and refuses start when any step fails.
  - The verifier returns `counts`, `foreign`, `invalid` or `unavailable`, and only `invalid` or a complete read with no counting marker fails toward stopping.
  - One snapshot per candidate, a Lair-side `check-error` state, and at most 5 checks of 60 seconds each per tick.
  - Launching the scanner session is an action, not a read: a scan directory that cannot be created or a scanner session that cannot start is a scan error.
  - Three consecutive scan errors halt the Lair.
  - The `body_sha256` form: a hash of the title and body hashes, with no normalization.
  - Invariant Lair-written text: every string the Lair writes is a fixed template, a validated token or the one bounded slot. The queue report has no slot and gives a stage and reason codes per failure.
  - An answerable park keeps `lair:claimed`; an `approval` or third park takes #631's mapping.
  - The halt file's path and cause codes, with `state-root` a report-only cause code never written to the file.
- The proposed ADR-0045 decision 17 amendment's wording, re-derived from invariant Claim state, under the design's Changes to shared documents. It also covers a claim that stopped before its label writes, which decision 17 already names an orphaned claim. It is not applied in this pull request.
- The proposed `CONTEXT.md` change to the **Lair** term, under the design's Changes to shared documents. It is not applied in this pull request.
- The proposed `solution-design.md` Amendments pointer, under the design's Changes to shared documents. It is not applied in this pull request.

## Decisions asked

The user answered four Tier A questions on 2026-11-21 before round 1. For the first three the user took the recommended option; for the fourth the user chose option A.

- **The pre-spawn injection scan's executor and ADR-0045 decision 10.** Answer, 2026-11-21: the scan runs in a locked-down scanner session, and ADR-0045 decision 10 stays unchanged.
- **Marker authentication.** Answer, 2026-11-21: markers are signed with a key, and count only when unedited and written by the Lair's login. The key is out of reach of the sessions the Lair starts. Forgery by a session that can read the key is a proposed ADR-0045 residual, under the design's Changes to shared documents; after round 1 the user's answer below widened it to every same-user session the Lair does not start.
- **The circuit-breaker scope.** Answer, 2026-11-21: the breaker counts the runs that ended in the current Lair session. A trip writes the halt file with its cause, so only the user deleting that file re-arms the Lair.
- **The sweep scope and the proposed ADR-0045 decision 17 amendment.** Answer A, 2026-11-21: the sweep covers only Lair issues, as invariant Claim state of the design defines them, through a proposed amendment to ADR-0045 decision 17 under the design's Changes to shared documents. The amendment's wording is decided for the user and listed for veto under Decisions taken.

After round 1 the user answered two more Tier A questions on 2026-11-21.

- **Key reach (C1-A5).** Question: "Your answer 'sign markers with a key no session can read' is only true for sessions the Lair starts. Your other Claude sessions run as the same OS user and could read the key file. Lock the key in a separate OS user account (sudo setup on every machine), or keep it a file only your account can read and record the risk in ADR-0045?" Reply, 2026-11-21: "This is a plugin that needs to be installed on many different machines". Taken as: no separate OS account. The key stays a file only the user's account can read, mode 0600 under `control/`, and the proposed residual, in a dated ADR-0045 amendment, covers every same-user session the Lair does not start.
- **A key the Lair cannot rebuild (C1-A6, C1-B6).** Question: "If the key file is lost, the Lair can't rebuild it from GitHub. Is it OK to add that one exception to ADR-0045 decision 2 (local files are a cache it can rebuild)? If the key goes missing while markers exist, the Lair refuses to start and says how to reset it." Reply, 2026-11-21: "Sure but I don't even understand what the point is". Taken as yes. The design proposes the decision 2 amendment and makes every other local item rebuildable, a control input or transient.
