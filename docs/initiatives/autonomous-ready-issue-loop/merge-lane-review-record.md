---
stamps: []
verdict: pending
open_counts:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 6
clean_round: null
---

# Design review record: Lair merge lane

This record covers the design review of the Lair's merge lane, issue #631: the [merge-lane design](merge-lane-design.md). Only merge-lane-design.md is stamped. Its stamp's blob is `git rev-parse HEAD:docs/initiatives/autonomous-ready-issue-loop/merge-lane-design.md`, and the stamp is written last, after every other change to this record. The [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md), [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md) and the [solution design](solution-design.md) are reviewed, not stamped.

The review exits only when zero critical or high findings are open and one round raises no new findings. It runs rounds until then; there is no round cap.

Rounds 1 to 3 each ran two passes in parallel. Each pass was a fresh, read-only `hivemind:cerebrate` analysis delegation with "Memory context: none":

- **Pass A:** code truth, governance and ADR conflicts, and existing-path coverage.
- **Pass B:** failure modes, trust and injection, and testability.

From round 4 on, the rounds run as Review procedure says.

New finding IDs take the `M` prefix, then the round, the pass and the finding number: `M1-A2` is round 1, pass A, finding 2.

## Record keys

- `stamps`: one entry, for merge-lane-design.md, with `path` and `blob` keys. Empty until the review passes.
- `verdict`: `pending`, `pass` or `fail`.
- `open_counts`: open findings by severity: `critical`, `high`, `medium` and `low`. It counts every finding this record owns that is still open: the round-3 findings below and every `M` finding.
- `rounds`: the number of rounds run.
- `clean_round`: the round that raised no new findings, or `null`.

## Review procedure

The user set this procedure on 2026-11-21 (Decisions asked). From round 4 on, each round runs one `hivemind:cerebrate` pass covering both angles: code truth, governance and ADR conflicts, and existing-path coverage; and failure modes, trust and injection, and testability. It is delegated with effort high, and no passes run in parallel. Because this design touches trust, credentials and the merge path, each round also runs one pass through the configured local review tool, through `run-review.sh`: here the `codex-plugin` default, since `HIVEMIND_LOCAL_REVIEWER` is unset and Codex is installed. When no tool is configured, that pass is skipped and the skip is recorded. The confirming round reviews only the diff since the previous round and the fixes to open findings, with effort medium.

There is no round cap; the parent record's 3-round cap does not apply here (the user, 2026-11-21). Round 4 and later IDs take `M<round>-C<n>` for the cerebrate pass and `M<round>-L<n>` for the local-tool pass: `M4-C1` and `M4-L1` in round 4.

## Dispositions

Every finding is open until it gets exactly one disposition:

- **fixed**: the record says where.
- **deferred**: the record names a tracked issue.
- **recorded**: the record says where.
- **rejected**: the record says why.

**Open** is a state, not a disposition. An open finding is counted in `open_counts`, and its disposition column reads `open`.

### Round-3 findings this issue owns

The findings come from round 3 of the [parent review record](review-record.md). The parent record assigned A3-2, A3-3, A3-10, B3-4, B3-5, B3-6, B3-7 and B3-8 to #631. The other seven were assigned to #631 by the strain's task text, the issue's brief: A3-8, B3-13, B3-14 and A3-13 in full, and this issue's part of A3-11, A3-12 and B3-20. Each disposition names the section of merge-lane-design.md that answers it. Three findings are owned only in part; the Finding column states the part, and the rest stays with the parent record.

| ID | Severity | Finding | Overlaps | Disposition |
| --- | --- | --- | --- | --- |
| A3-2 | high | The tick runs `merge-approved.sh` outside the watch, dropping ADR-0044's settled-approval precondition, and the failure-mode row maps the script's results wrongly. | B3-5, B3-6 | fixed: merge-lane-design.md, Settle check, Routing table and Failure modes, under ADR-0044 decisions 17, 18 and 20; completed in round 1 by M1-B3, M1-B4, M1-B5, M1-B13 and M1-B16, in round 2 by M2-A6, M2-A9 and M2-B8, and in round 3 by M3-A2 and M3-B1 |
| A3-3 | high | The controller has no defined source for the merge settings it reads each tick, so unsetting auto-merge may never stop merges. | B3-7 | fixed: merge-lane-design.md, Merge settings source, Merge environment and Lifecycle "Stage 4: halt and circuit breaker"; completed in round 1 by M1-A2, M1-B10 and M1-B15, and in round 2 by M2-B11 |
| B3-4 | high | Strain result fields (`pr`, `branch`, `head`) are trusted unchecked, and "Lair PR" is undefined. | | fixed: merge-lane-design.md, Lair pull request, Pinned head and Merge-lane step of the tick (late group); completed in round 1 by M1-A6, M1-B1, M1-B2 and M1-B8, in round 2 by M2-A1, M2-B2, M2-B3 and M2-B5, and in round 3 by M3-B2 |
| B3-5 | high | The tick's merge drops ADR-0044's settle period and does not tie the auto tier to the merged head. | A3-2 | fixed: merge-lane-design.md, Settle check, Pinned head and Expected-head argument; completed in round 1 by M1-B4, M1-B5 and M1-B17, in round 2 by M2-B8, and in round 3 by M3-A2 and M3-B1 |
| B3-6 | high | The merge-result failure-mode row maps `merge-approved.sh` results wrongly. | A3-2 | fixed: merge-lane-design.md, Routing table and Failure modes |
| B3-7 | high | No defined source for merge settings in the tick. | A3-3 | fixed: merge-lane-design.md, Merge settings source and Merge environment; completed in round 1 by M1-A2, M1-B10 and M1-B15 |
| B3-8 | high | Auto-tier inputs (protected-path list, local-review-skipped evidence, bump type) are undefined or untrusted. | A3-10 | fixed: merge-lane-design.md, Auto-tier script, Git and tool reads and Trust boundaries; completed in round 1 by M1-B1, M1-B11, M1-B12 and M1-B17, in round 2 by M2-B4, M2-B6, M2-B12 and M2-B14, in round 3 by M3-A5, M3-B2 and M3-B4, and in round 4 by M4-C4 and M4-C5 |
| A3-10 | medium | Auto-tier inputs have no named source, and two can be forged by the strain. | B3-8 | fixed: merge-lane-design.md, Auto-tier script and Trust boundaries; completed in round 1 by M1-B1, M1-B11 and M1-B12, in round 2 by M2-B4, M2-B6 and M2-B12, in round 3 by M3-A5, M3-B2 and M3-B4, and in round 4 by M4-C4 and M4-C5 |
| A3-8 | medium | Draft-PR and closed-unmerged states have no lifecycle exit. | | fixed: merge-lane-design.md, Exits (Draft, Closed unmerged, Claim withdrawn) and Write order; completed in round 1 by M1-B7 and M1-B8, and in round 2 by M2-B3 and M2-B9 |
| B3-13 | medium | The run outcome to label mapping is incomplete (blocked, complete with no PR, invalid result). | | fixed: merge-lane-design.md, Run outcome to labels; completed in round 2 by M2-A3 |
| B3-14 | medium | Remediation strains leave no GitHub record, their parks have no path, and the halt does not cover them. | | fixed: merge-lane-design.md, Fix-up runs, Markers the merge lane writes, Run outcome to labels and Lifecycle "Stage 4: halt and circuit breaker"; completed in round 1 by M1-A3, M1-B6 and M1-B7, in round 2 by M2-A4, M2-A5, M2-B2 and M2-B10, and in round 3 by M3-B5 |
| A3-13 | low | It is unclear whether `lair:review` goes on the issue or the pull request. | | fixed: merge-lane-design.md, Exits (Batch review: on the issue and the pull request) and State and ownership; completed in round 1 by M1-A5 |
| A3-12 | medium | This scope's part: the no-merge-after-edit and CI-red calls should have been asked, and this scope's calls were not listed for veto. The session-scoped breaker call is not in this scope. | | fixed: merge-lane-design.md, Tier A answers (Q8, Q9) and Decided for you; the veto list completed in round 1 by M1-A14 and the run's calls R1 to R13, and in round 2 by M2-A11 and the run's calls R14 to R21, R21 withdrawing the Tier-A-derived R13 |
| B3-20 | low | This scope's part: the merge-lane tests and their `tools/validate.sh` registration. The overlord prose, injection and halt tests and the halt file path are not in this scope. | | fixed: merge-lane-design.md, Verification strategy; completed in round 1 by M1-A8, M1-A13, M1-B5 and M1-B14, in round 2 by M2-A8 and M2-B7, and in round 3 by M3-A6 |
| A3-11 | medium | This scope's part: the Seam order ADR lists for the slices the merge lane changes. | | fixed: merge-lane-design.md, Seam order; completed in round 1 by M1-A1 and M1-A7, and in round 2 by M2-A7 |

## Round 1, 2026-11-21

Two passes, run in parallel.

- **Pass A reviewer:** a fresh read-only `hivemind:cerebrate` analysis delegation that did not write the design, with "Memory context: none".
- **Pass A angle:** code truth, governance and ADR conflicts, existing-path coverage.
- **Pass B reviewer:** the same kind as pass A.
- **Pass B angle:** failure modes, trust and injection, testability.
- **Reviewed:** merge-lane-design.md at blob `0177e805e2d91d69f12c5d64a62121d4fd8ef944`, with the PRD, ADR-0045, ADR-0044 as amended and solution-design.md as sources.

Result: 0 critical, 3 high (all from pass B), 18 medium (7 from pass A, 11 from pass B) and 11 low (8 from pass A, 3 from pass B). All are new. Each was fixed in merge-lane-design.md, or in ADR-0044's 2026-11-21 amendment where named. Round 2 reverted the fix of M1-B9 for compliance, and its disposition is now recorded (R16). The run's calls on the open choices were R1 to R13; R1 to R11 are listed under Decisions taken. R13 was withdrawn from the veto list in round 2 (R21), and R12 in round 3 (M3-A9), each because the change it named derives from a Tier A answer.

### Pass A findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M1-A1 | medium | The tick is a second merge path, while `decision-autonomy.md` Tier A and its pinned fixture say only the watch merges, and no slice owns the change. | fixed: merge-lane-design.md, Existing-path coverage (The Tier A merge rule), Seam order (#605) and Changes to shared documents, item 5 (R12, withdrawn from the veto list in round 3 by M3-A9) |
| M1-A2 | medium | `env -i` drops `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `XDG_CONFIG_HOME` and the D-Bus keyring variables. | fixed: merge-lane-design.md, Merge environment (R6) |
| M1-A3 | medium | A fix-up park was made not answerable and not counted toward the third-park handoff, against ADR-0045 decision 7, while the design claimed no ADR-0045 change. | fixed: merge-lane-design.md, Run outcome to labels, Failure modes (Parked fix-up run) and Decisions (R1) |
| M1-A4 | medium | The review-finding fix-up cap (`fixup-cap`) sets what starts a fix-up run, which ADR-0045 decision 13 and the PRD leave to #610, and the opening's scope statement does not match. | fixed: merge-lane-design.md, opening, Fix-up runs (Seam note for #610) and Failure modes; the cap is dropped (R2) |
| M1-A5 | medium | `lair:review` only on the pull request contradicts the PRD's Labels and Admission criteria, which put it on the issue. | fixed: merge-lane-design.md, Routing table, Exits, Run outcome to labels and State and ownership (R3) |
| M1-A6 | medium | The run-end fields were added to #632's claim marker, whose contract this design does not own. | fixed: merge-lane-design.md, opening, State and ownership and Markers the merge lane writes (Run-end marker) (R8); completed in round 2 by M2-A2 |
| M1-A7 | medium | The Seam order ADR lists are incomplete for #604, #605, #608 and #610. | fixed: merge-lane-design.md, Seam order; completed in round 2 by M2-A7 |
| M1-A8 | low | #605 depends on #608 and later slices (the script directory, the fix-up, halt and breaker cases) but builds first. | fixed: merge-lane-design.md, Merge-lane step of the tick (script directory), Verification strategy (cases added by the slices that build them) and Seam order; completed in round 3 by M3-A6 |
| M1-A9 | low | The empty-string merge keys in strain settings change ADR-0045 decision 4, so "No ADR-0045 change is needed" is too broad. | fixed: merge-lane-design.md, Assumptions about #630 and Decisions (R11); completed in round 2 by M2-A10 |
| M1-A10 | low | The amendment says the one-line output contract is unchanged, while decision 19 adds `bad-expected-head` and a new `wait:head-moved` trigger. | fixed: ADR-0044, Amendment 2026-11-21, the paragraph of unchanged items |
| M1-A11 | low | Wrong citations: the 3600-second wait under ADR-0029 decision 3, and "ADR-0044 decision 17, amending decisions 2 and 10". | fixed: merge-lane-design.md, Context and code truth, Decisions and Decided for you |
| M1-A12 | low | The opening does not name the Lifecycle label bullets or the claim marker contract as superseded, and the Amendments pointer text misstates stage 3 and the exits. | fixed: merge-lane-design.md, opening and Changes to shared documents, item 2; completed in round 2 by M2-A2 |
| M1-A13 | low | Verification has no case for a pull request body with a "Decided for you" list, and no owner for the no-merge-by-strain test. | fixed: merge-lane-design.md, Verification strategy |
| M1-A14 | low | The CI-red rule fires only from the merge script's line, so it depends on the merge settings, and its trigger point is not listed for veto. | fixed: merge-lane-design.md, Fix-up runs (The CI-red rule) and Decided for you (R7); completed in round 2 by M2-A6 (R17) |
| M1-A15 | low | The PRD Out of Scope bullet "Changing the ADR-0044 merge rules beyond the auto-tier precondition" conflicts with the amendment, and no change to it is recorded. | fixed: merge-lane-design.md, Changes to shared documents, item 6; completed in round 2 by M2-A11, which withdrew R13 from the veto list as derived from Tier A answers Q1 and Q3 (R21) |

### Pass B findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M1-B1 | high | The #630 assumption covers only the settings files and the cache; a strain can write the git common directory, `PATH` directories or the plugin scripts the tick runs, and the residual understates ADR-0045's. | fixed: merge-lane-design.md, Git and tool reads, Assumptions about #630 and Trust boundaries (R4); completed in round 2 by M2-B4, M2-B5 and M2-B14, and in round 3 by M3-B2 |
| M1-B2 | high | A strain holds the user's credentials and the nonces, so it can forge markers unless #632's rule stops it, yet the design and the amendment treat recorded heads as unforgeable. | fixed: merge-lane-design.md, Assumptions about #632 and Trust boundaries (The pinned head, Residual: marker forgery); ADR-0044, Amendment 2026-11-21, Consequences (R5) |
| M1-B3 | high | Tick reads have no fail-closed route, and the absence checks fail open on a failed or partial comment read. | fixed: merge-lane-design.md, Merge-lane step of the tick (steps 1, 2 and 10 and the fail-closed rule), Failure modes and Verification strategy; completed in round 2 by M2-B2 |
| M1-B4 | medium | A failed re-snapshot keeps the old `quiet_since`, so the settle check can settle early. | fixed: merge-lane-design.md, Settle check, Failure modes (Failed re-snapshot) and Verification strategy; completed in round 2 by M2-B8 |
| M1-B5 | medium | The poll and tier outputs are caught by catch-alls, so a malformed line can settle or reach the late group. | fixed: merge-lane-design.md, Settle check, Merge-lane step of the tick (step 10) and Verification strategy; `pr-change-detect-poll.sh` routes to the merge-lane suite, and `loop-state.sh` is no longer read after R2 |
| M1-B6 | medium | An in-flight fix-up run is unbounded: no budget, stall or crash route ends it. | fixed: merge-lane-design.md, Fix-up runs, Failure modes (Fix-up run lost in flight, Start marker write failed) and Verification strategy; completed in round 2 by M2-A4 and M2-B2 (R15), and in round 3 by M3-B5 |
| M1-B7 | medium | Routes with several writes have no order or retry, and only open pull requests are iterated. | fixed: merge-lane-design.md, Write order, Lair pull request (the lane set), Failure modes and Verification strategy |
| M1-B8 | medium | A pull request stays a Lair pull request after its claim ends, and a closed issue or a removed `lair:claimed` has no route. | fixed: merge-lane-design.md, Lair pull request and Exits (Closed unmerged, Claim withdrawn); completed in round 2 by M2-A1, M2-B3 and M2-B9 |
| M1-B9 | medium | A fix-up run can start for a pull request with a review marker. | recorded: merge-lane-design.md, Fix-up runs (Recorded residual: fix-ups during batch review); the round-1 fix was reverted in round 2 for compliance with ADR-0045 decision 13 and the PRD's Post-PR feedback criterion (M2-A5, R16) |
| M1-B10 | medium | The clean environment does not prove which account `gh` acts as. | fixed: merge-lane-design.md, Merge environment and Merge-lane step of the tick (step 12) (R6); completed in round 4 by M4-L2, which binds the check to the repository's host (R33) |
| M1-B11 | medium | The protected-path floor misses nested and case-variant `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json` and `.claude` paths. | fixed: merge-lane-design.md, Auto-tier script (the list forms and the floor) and Verification strategy; completed in round 2 by M2-B12, and in round 4 by M4-C5 |
| M1-B12 | medium | `.github/lair.json` has no strict schema, so a malformed list can declare no protected paths. | fixed: merge-lane-design.md, Auto-tier script (the schema) and Verification strategy |
| M1-B13 | medium | The CI-red rule waits on the merge script's gate order and settings. | fixed: merge-lane-design.md, Merge-lane step of the tick (step 7) and Fix-up runs (The CI-red rule) (R7); completed in round 2 by M2-A6 (R17) |
| M1-B14 | medium | Verification misses holds, skips, exits, settle results, delivery rows and the existing `args:six` case, and the late-group order test cannot see the settings and cache reads. | fixed: merge-lane-design.md, Verification strategy and Existing-path coverage; completed in round 2 by M2-B7 |
| M1-B15 | low | "Matches Claude Code's order" is false, and other settings sources are not ruled out. | fixed: merge-lane-design.md, Merge settings source |
| M1-B16 | low | A hung child process stalls the tick. | fixed: merge-lane-design.md, Merge-lane step of the tick (child timeout) and Routing table (R10); round 3 exempted `merge-approved.sh` (M3-A8, R25), and round 4 bounds it again (M4-L1, R32) |
| M1-B17 | low | Several merges in one tick each use a stale trunk, and the trunk tip is not a late-group input. | fixed: merge-lane-design.md, Merge-lane step of the tick (one merge per tick, step 13) and Known limit (R9); completed in round 2 by M2-B13 |

## Round 2, 2026-11-21

Two passes, run in parallel.

- **Pass A reviewer:** a fresh read-only `hivemind:cerebrate` analysis delegation that did not write the design, with "Memory context: none".
- **Pass A angle:** code truth, governance and ADR conflicts, existing-path coverage.
- **Pass B reviewer:** the same kind as pass A.
- **Pass B angle:** failure modes, trust and injection, testability.
- **Reviewed:** merge-lane-design.md at blob `6e59293f79881ef118e7b86baaebcf3d8f204be9`, with the PRD, ADR-0045, ADR-0044 as amended and solution-design.md as sources.

Result: 0 critical, 0 high, 13 medium (6 from pass A, 7 from pass B) and 13 low (5 from pass A, 8 from pass B); 26 in all. All are new; M2-B1 repeats M2-A1, and M2-B15 repeats part of M2-A9. Each is fixed or recorded in merge-lane-design.md, or in ADR-0044's 2026-11-21 amendment where named. The run's calls R14 to R21 are listed under Decisions taken.

### Pass A findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M2-A1 | medium | The issue's state and `lair:claimed` are read only at step 2, so a claim withdrawal that lands after step 2 can still be merged. | fixed: merge-lane-design.md, Merge-lane step of the tick (step 15 and the Known limit's late-group kind), Exits (Claim withdrawn) and Verification strategy |
| M2-A2 | medium | The opening's superseded list misses solution-design.md parts the design contradicts: stage 1's outcome in the claim marker, the Crash row, the claim-marker Decision, the GitHub API failure row and the Strain result contract; the Amendments pointer text does not match the opening. | fixed: merge-lane-design.md, opening, Markers the merge lane writes (Run-end marker), Run outcome to labels, Failure modes (Crash, Failed or incomplete tick read) and Changes to shared documents, item 2 |
| M2-A3 | medium | The breaker counts `blocked`, `no-pr` and invalid results, beyond the outcomes ADR-0045 decision 17 and the PRD's Stop controls criterion name. | fixed: merge-lane-design.md, Run outcome to labels, Lifecycle "Stage 4: halt and circuit breaker", Failure modes, Decisions and Seam order (#611) (R14) |
| M2-A4 | medium | A fix-up run's budget runs from its own start, against the PRD's per-issue budget, and an over-budget fix-up run goes to batch review instead of `lair:failed`. | fixed: merge-lane-design.md, Fix-up runs, Lair pull request (terminal outcome), Run outcome to labels, Failure modes and Decided for you (R15) |
| M2-A5 | medium | The round-1 rule that a review marker stops a fix-up run departs from ADR-0045 decision 13 and the PRD's Post-PR feedback criterion. | fixed: merge-lane-design.md, Fix-up runs (start preconditions; Recorded residual: fix-ups during batch review), Decisions and Decided for you (R16) |
| M2-A6 | medium | The settle check's `CI_FAILED` counts as a CI-red signal, though it is not tied to the pinned head, and R7 states it so; a fix-up run can start on a head that moved. | fixed: merge-lane-design.md, Settle check, Fix-up runs (start preconditions, The CI-red rule), Routing table, Failure modes (CI red) and Decided for you (R7, R17) |
| M2-A7 | low | The Seam order ADR lists miss ADR-0017 decisions 1 and 2 for #604, ADR-0045 decisions 5, 12 and 16 for #610, and ADR-0045 decision 2 for #605. | fixed: merge-lane-design.md, Seam order, with each row checked against the design's citations; Context and code truth and Assumptions about #630 now cite ADR-0037, ADR-0042 and ADR-0017 |
| M2-A8 | low | Context and code truth says `map_path` routes `pr-change-detect-poll.sh` only to its own suite, but it also reaches `test_shared_libs`, `test_script_bootstrap` and the policy suite; the new scripts have no bootstrap enrolment. | fixed: merge-lane-design.md, Context and code truth and Verification strategy (Registration) |
| M2-A9 | low | A waiting CI-red rule falls through to the auto tier with no stated flow, and the merge-pending hold has no step of its own. | fixed: merge-lane-design.md, Merge-lane step of the tick (steps 7 and 8), Fix-up runs (The CI-red rule) and Verification strategy |
| M2-A10 | low | The halt and breaker stopping fix-up runs while merges continue is cited to ADR-0045 decision 17 as written, but rests on Q10; the "no ADR-0045 change" claim is too broad; ADR-0045's status line "Keeps ADR-0044's merge rules" is not addressed. | fixed: merge-lane-design.md, Decisions and Changes to shared documents, item 7 (R21) |
| M2-A11 | low | Changes item 6 is derived from Tier A answers Q1 and Q3 but is listed for veto as R13, and item 3's texts differ from this record's dispositions. | fixed: merge-lane-design.md, Changes to shared documents, items 3 and 6, and Decided for you (R21) |

### Pass B findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M2-B1 | medium | The same gap as M2-A1: a withdrawal after step 2 is not rechecked before the merge call. | fixed: merge-lane-design.md, as for M2-A1 |
| M2-B2 | medium | A result lost between its read and its marker, or a transient read failure during the result checks, turns a good run into a crash or an invalid result. | fixed: merge-lane-design.md, Lair pull request (Result recording), Fix-up runs, State and ownership, Failure modes (Crash, Failed result-check read) and Verification strategy |
| M2-B3 | medium | Once a claim ends, its still-open pull request leaves the lane set, so no tick reads it and the lane rule cannot be judged. | fixed: merge-lane-design.md, Lair pull request (the lane-holder set), State and ownership, Failure modes (Failed lane read), Seam order (#608) and Verification strategy; completed in round 4 by M4-C8 |
| M2-B4 | medium | The git hardening misses replace objects, grafts, alternates, the submodule diff setting and inherited `GIT_*` variables, and the design says its hardening does not rely on the #630 assumption. | fixed: merge-lane-design.md, Git and tool reads, Auto-tier script, Assumptions about #630, Trust boundaries (Residual: a strain that writes the tick's inputs), Failure modes (Changed git repository) and Verification strategy |
| M2-B5 | medium | A fix-up run can build on another account's push and record it as its head, so ADR-0044's unreviewed-push residual returns through fix-up heads. | fixed: merge-lane-design.md, Assumptions about #630 (Leased pushes) and Trust boundaries (The pinned head); ADR-0044, Amendment 2026-11-21, the third Consequences bullet (R18) |
| M2-B6 | medium | This repository's protected-path list is not specified, so a Lair pull request can change the Lair, the merge script, the hooks, the manifest, the validators or the policy pins in the auto tier. | fixed: merge-lane-design.md, Auto-tier script (This repository's list) and Verification strategy (R19); completed in round 3 by M3-A5 and M3-B4, and in round 4 by M4-C4 |
| M2-B7 | medium | Tests miss the git and tool hardening rules, settings type failures, killed poll, git and `gh` reads, the `.gitmodules` floor name and malformed `version_files` entries; the hook case is vacuous. | fixed: merge-lane-design.md, Verification strategy |
| M2-B8 | low | The merge-pending flag lives with the seed, so a settle reset clears it and a second merge call can run for a queued head. | fixed: merge-lane-design.md, Merge-lane step of the tick (step 8), State and ownership, Routing table, Failure modes and Verification strategy; completed in round 3 by M3-A2 and M3-B1, which replaced the merge-pending mark with GitHub's merge-queue state |
| M2-B9 | low | Step 2 reads the pull request before the issue, so a merge that closes the issue can be routed as a claim withdrawal. | fixed: merge-lane-design.md, Merge-lane step of the tick (steps 2 and 15) and Verification strategy |
| M2-B10 | low | A fix-up run that ends after its claim has ended still writes labels, a review marker and a breaker count. | fixed: merge-lane-design.md, Run outcome to labels, Lifecycle "Stage 4: halt and circuit breaker" and Failure modes |
| M2-B11 | low | Once the merge queue holds a pull request, unsetting `HIVEMIND_AUTO_MERGE` or a later review marker does not take it out. | recorded: merge-lane-design.md, Trust boundaries (Residual: a queued or armed merge) and Lifecycle "Stage 4: halt and circuit breaker" (R20); completed in round 4 by M4-C1, which makes no merge call in a repository that requires a merge queue (R34) |
| M2-B12 | low | A path with a non-ASCII byte or a segment ending in `.` or a space, the exact path `.github`, or a prefix entry's exact path escapes protected-path matching. | fixed: merge-lane-design.md, Auto-tier script (the list forms and the floor) and Verification strategy |
| M2-B13 | low | One merge call per tick in a fixed order lets a pull request that always waits at the merge call starve the others. | fixed: merge-lane-design.md, Merge-lane step of the tick (lane order), State and ownership and Verification strategy |
| M2-B14 | low | The fixed `PATH` puts `/usr/bin:/bin` before the resolved tool directories, and nothing checks that a tool name resolves to its resolved path. | fixed: merge-lane-design.md, Git and tool reads, Failure modes (Shadowed tool at start) and Verification strategy |
| M2-B15 | low | The same gap as M2-A9's waiting CI-red rule: under a halt, a red pull request has no stated path to the review wait. | fixed: merge-lane-design.md, as for M2-A9 |

## Round 3, 2026-11-21

Two passes, run in parallel, the last round run that way (Review procedure).

- **Pass A reviewer:** a fresh read-only `hivemind:cerebrate` analysis delegation that did not write the design, with "Memory context: none".
- **Pass A angle:** code truth, governance and ADR conflicts, existing-path coverage.
- **Pass B reviewer:** the same kind as pass A.
- **Pass B angle:** failure modes, trust and injection, testability.
- **Reviewed:** merge-lane-design.md at blob `b8ea94d76b82b10feed989844c2153153df50803`, with the PRD, ADR-0045, ADR-0044 as amended and solution-design.md as sources.

Result: 0 critical, 0 high, 12 medium (5 pass A, 7 pass B), 12 low (6 pass A, 6 pass B); 24 in all. All are new; M3-B4 repeats M3-A5, and M3-B1 is closed by M3-A2's fix. Round 3 showed five earlier fixes held only in part: M1-A8 (completed by M3-A6), M1-B1 (M3-B2), M1-B6 (M3-B5), M2-B6 (M3-A5, M3-B4) and M2-B8 (M3-A2, M3-B1). Where a fix could remove a part, it did: the merge-pending mark, the result cache, the applied marker with its walk over unfinished writes, and the fix-up start precondition on GitHub's head are gone. The run's calls R22 to R31 are listed under Decisions taken.

### Pass A findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M3-A1 | medium | The fix-up start precondition that a fresh GitHub head equal the pinned head blocks review-finding fix-ups, against ADR-0045 decision 13 and the PRD's Post-PR feedback criterion. | fixed: merge-lane-design.md, Fix-up runs (start preconditions), Decisions (closing paragraph), Decided for you (R16, R17), Seam order (#610) and Verification strategy; the precondition is dropped, the run starts at the pinned head, and a moved branch fails its leased first push |
| M3-A2 | medium | The merge-pending mark and the result cache are Lair-only state that cannot be rebuilt from GitHub, against ADR-0045 decision 2. | fixed: merge-lane-design.md, Merge-lane step of the tick (steps 2, 8 and 14), Lair pull request (Result recording), State and ownership, Routing table, Failure modes (Queued merge) and Verification strategy; both parts are removed, GitHub's merge-queue state and the kept result file replace them (R22) |
| M3-A3 | medium | An open non-draft pull request named by a blocked, failed or invalid result is in neither lane set, so admission claims the next issue, narrowing ADR-0045 decision 12. | fixed: merge-lane-design.md, Lair pull request (the lane-holder set; Recorded residual: a pull request no result names), Markers the merge lane writes (Run-end marker), Run outcome to labels and Verification strategy (#608) (R23) |
| M3-A4 | medium | The leased-push assumption reverses `push-branch.sh`'s recorded decision (plain fast-forward push; lease only on a non-fast-forward retry from the remote-tracking ref; early capture rejected) without naming it. | fixed: merge-lane-design.md, Context and code truth, Assumptions about #630 (Leased pushes), Existing-path coverage (Interactive pushes), Decided for you (R18) and Seam order (#604, with ADR-0040 decision 2 and ADR-0037 decision 5 and Workflow outline step 8) |
| M3-A5 | medium | The protected list misses `plugin/skills/_shared/` and the root `.claude-plugin/`. | fixed: merge-lane-design.md, Auto-tier script (This repository's list), Decided for you (R19) and Verification strategy; the list is derived from what the merge, poll, auto-tier and tick scripts run or source and the local-review evidence producers; completed in round 4 by M4-C4 |
| M3-A6 | low | The #608-built cases (lane-holder and admission, result recording, delivery run ends) sit in #605's main test list. | fixed: merge-lane-design.md, Verification strategy (Cases added by the slices that build them, #608) and Seam order (#605, #608) |
| M3-A7 | low | The #606 row replaces Q5's bump input with change fragments, unasked. | fixed: merge-lane-design.md, Auto-tier script (Release-train mode), Seam order (#606) and Verification strategy; Q5's input stands, and the auto tier fails closed in that mode until #606 supplies an input the pull request cannot change (R24) |
| M3-A8 | low | The 300-second child timeout wraps `merge-approved.sh`, against its header "merge calls are never wrapped". | fixed: merge-lane-design.md, Context and code truth, Merge-lane step of the tick (child timeout), Routing table, Failure modes (Merge-script error) and Verification strategy (R25); superseded in round 4 by M4-L1, which bounds `merge-approved.sh` again for the Lair only (R32) |
| M3-A9 | low | Changes item 5 derives from Tier A answer Q1 but is listed for veto. | fixed: merge-lane-design.md, Changes to shared documents, item 5, now "Answer: Tier A, Q1, approved 2026-11-21", and Decided for you, where R12 is withdrawn; this record's Decisions taken |
| M3-A10 | low | This record says the parent record split all its round-3 findings out to #631, but the parent assigned only eight. | fixed: this record, Round-3 findings this issue owns, and merge-lane-design.md, Changes to shared documents, item 3 |
| M3-A11 | low | The breaker counts `stalled`, but solution-design.md's Component "Decision digest and circuit breaker" lists only failed, crashed and timed-out, and the opening does not supersede it. | fixed: merge-lane-design.md, opening, Lifecycle "Stage 4: halt and circuit breaker", Decisions (the breaker bullet and closing paragraph), Decided for you (R14) and Changes to shared documents, item 2 |

### Pass B findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M3-B1 | medium | A queued pull request whose merge-pending mark was never set, after a failed confirm read or a killed merge run, can get a second merge call. | fixed: as for M3-A2; merge-lane-design.md, Verification strategy (Merge queue) |
| M3-B2 | medium | `gh`'s config directory (`http_unix_socket`) and `$HOME/.jq` are missing from the strain-write list. | fixed: merge-lane-design.md, Assumptions about #630 (the write property), Git and tool reads (start checks), Trust boundaries, Failure modes (Unsafe tool config at start) and Verification strategy (#608) (R26) |
| M3-B3 | medium | The Lair runs as the user's login, so the user's own review comments count as settled and never block a merge. | recorded: merge-lane-design.md, Trust boundaries (Residual: the Lair acts as the user's own login), with the user's working holds listed; a `lair:review` label is now an extra hold at steps 3, 14 and 15 (R27) |
| M3-B4 | medium | The protected list misses `plugin/skills/_shared/` and the root `.claude-plugin/`. | fixed: as for M3-A5; completed in round 4 by M4-C4 |
| M3-B5 | medium | A start marker that lands although its write reported a failure, or a Lair stop before launch, is counted as a crash. | fixed: merge-lane-design.md, Fix-up runs, Markers the merge lane writes, Run outcome to labels, Lifecycle "Stage 4: halt and circuit breaker", Failure modes (Fix-up run not launched) and Verification strategy (#610); the run's worktree is the launch evidence (R28) |
| M3-B6 | medium | Unfinished write sequences for delivery ends with no recorded pull request are never finished, because the finisher walks only lane pull requests. | fixed: merge-lane-design.md, Write order, Exits, Run outcome to labels, Failure modes (Interrupted route) and Verification strategy; labels go first and the route's last marker marks it done, so the applied marker and the walk are removed (R29) |
| M3-B7 | medium | No test shows that a non-conforming marker, wrong author or nonce, is ignored. | fixed: merge-lane-design.md, Verification strategy (Marker rule) |
| M3-B8 | low | The rename case passes even without `--no-renames`. | fixed: merge-lane-design.md, Verification strategy (Protected paths: a rename out of a protected path and a copy into a protected directory) |
| M3-B9 | low | `map_path` does not route `plugin/skills/lair/**` or the `_shared` libraries the scripts source to both new suites. | fixed: merge-lane-design.md, Verification strategy (Registration, with a closure check) |
| M3-B10 | low | The structural check flags only `gh pr merge`, not the REST and GraphQL merge paths or `--auto`. | fixed: merge-lane-design.md, Existing-path coverage (The Tier A merge rule) and Verification strategy (Structural merge-path check); completed in round 4 by M4-C6 |
| M3-B11 | low | A closed recorded pull request that is reopened holds no lane. | fixed: merge-lane-design.md, Lair pull request (the lane-holder set), Exits (Closed unmerged), Failure modes and Verification strategy (#608) (R30) |
| M3-B12 | low | A permanent read failure, an issue deleted or transferred, has no bound and no user-facing report. | fixed: merge-lane-design.md, Merge-lane step of the tick and Failure modes (Issue not found) and Verification strategy (R31) |
| M3-B13 | low | A stale `headRefOid` right after a push makes a good result invalid. | fixed: merge-lane-design.md, Lair pull request (the head check), Failure modes (Failed result-check read) and Verification strategy (#608, #610) |

## Round 4, 2026-11-21 to 2026-11-22

The first round run as Review procedure says: one cerebrate pass and one local-tool pass.

- **Cerebrate pass reviewer:** a fresh read-only `hivemind:cerebrate` analysis delegation that did not write the design, with effort high and "Memory context: none".
- **Cerebrate pass angle:** both angles: code truth, governance and ADR conflicts, and existing-path coverage; and failure modes, trust and injection, and testability. The first attempt stopped on a usage limit before it returned findings, and was rerun as a fresh delegation; only the rerun's findings are recorded.
- **Local-tool pass:** the configured local review tool through `run-review.sh --base main`, here the `codex-plugin` default, since `HIVEMIND_LOCAL_REVIEWER` is unset and Codex is installed. Verdict: needs-attention.
- **Reviewed:** merge-lane-design.md at blob `2732101db8f51a6e311614db8a244d26db91c03c`, with the PRD, ADR-0045, ADR-0044 as amended and solution-design.md as sources.

Result: 0 critical, 3 high (2 local-tool, 1 cerebrate), 4 medium, 4 low; 11 in all. All are new. M4-L1 reverses round 3's call on M3-A8 (R25), which had itself reversed round 1's timeout on M1-B16; it is new because it names a cost round 3 did not weigh, that a hung merge call holds the single-instance lock. Round 4 showed eight earlier fixes held only in part: M1-B10 (completed by M4-L2), M1-B11 (M4-C5), M2-B3 (M4-C8), M2-B6, M3-A5 and M3-B4 (M4-C4), M2-B11 (M4-C1) and M3-B10 (M4-C6); and it superseded M3-A8's fix (M4-L1). Where a fix could remove a part, it did: the `merge-approved.sh` timeout exemption, the per-pull-request reads of the lane-holder set and the set's merged exit are gone. Round 4 moved the fix-up in-flight check ahead of the state read, so the steps the earlier rows name as 2, 3 and 4 are now steps 3, 4 and 2. The run's calls R32 to R39 are listed under Decisions taken.

### Local-tool pass findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M4-L1 | high | `merge-approved.sh` runs with no timeout under the single-instance lock, so a hung `gh pr merge` stops the whole controller and no next tick recovers. | fixed: merge-lane-design.md, Merge-lane step of the tick (child timeout), Routing table, Failure modes (Merge-script error, Queued or armed merge), Verification strategy (Routing, Child timeout), Decided for you (R10, R25, R32) and Seam order (#605); the tick bounds the script with its 300-second child timeout, overriding the script header for the Lair only; completed in round 5 by M5-L1 and M5-C4 |
| M4-L2 | high | The credential check verifies only the `gh api user` login, not the GitHub host, so `GH_HOST`, an enterprise token or `gh` config could send the reads and the merge to another host where the same login exists. | fixed: merge-lane-design.md, Merge environment (The host binding), Merge-lane step of the tick (step 12), Trust boundaries (The Lair's environment), Failure modes (Credential mismatch, Unreadable repository host at start), Verification strategy (Host binding, #608 start checks), Decided for you (R6, R33) and Seam order (#605, #608); completed in round 5 by M5-C4 |

### Cerebrate pass findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M4-C1 | high | In a repository that requires a merge queue, `gh pr merge` without `--admin` arms an auto-merge request instead of merging; an armed, unqueued request is invisible to the merge-queue read and survives pushes, holds, a halt and an unset `HIVEMIND_AUTO_MERGE`, so GitHub can later merge a head the Lair never recorded. | fixed: merge-lane-design.md, Merge-lane step of the tick (steps 3, 8 and 14, Merge queues and auto-merge requests, Known limit), State and ownership, Routing table (`MERGE=wait:merge-pending`), Trust boundaries (The pinned head; Residual: a queued or armed merge), Failure modes (Queued or armed merge, Merge queue required), Decisions (closing paragraph), Verification strategy (Merge queue) and Decided for you (R20, R34); ADR-0044, Amendment 2026-11-21, a fourth Consequences bullet. An auto-merge request armed by someone else is a recorded residual; completed in round 5 by M5-C1 and M5-C5 |
| M4-C2 | medium | A fix-up park whose end-marker write fails has already removed `lair:claimed`, so the same tick's merge-lane step routes the claim-withdrawn exit; the park loses answerability, and a lost run's breaker count is lost the same way. | fixed: merge-lane-design.md, Merge-lane step of the tick (step 2, the fix-up in-flight check moved ahead of the state read, and the fail-closed rule), Verification strategy (Holds and skips) and Decided for you (R35) |
| M4-C3 | medium | The review-marker lookup is scoped to the claim, so a re-claimed issue records the same pull request under a new claim with no review marker and can merge it; a fix-up park on a held pull request leaves `lair:review` on the issue, blocking re-admission. | fixed: merge-lane-design.md, Merge-lane step of the tick (step 4), Write order, Run outcome to labels (the fix-up park rows and paragraph), Failure modes (Parked fix-up run), Verification strategy (Holds and skips, #610), Decided for you (R36) and Seam order (#610); completed in round 5 by M5-C2 and M5-C3 |
| M4-C4 | medium | The protected list misses the local-review producers and the leased-push producers. | fixed: merge-lane-design.md, Auto-tier script (This repository's list: `plugin/agents/local-reviewer.md`, `plugin/skills/adaptation-cycle/`, `plugin/skills/push-branch/` and `plugin/skills/open-plan-pr/` added, and the leased-push producers named in the derivation), Verification strategy and Decided for you (R19) |
| M4-C5 | medium | The protected-path floor misses Codex's instruction files. | fixed: merge-lane-design.md, Auto-tier script (the floor: any `.codex` segment and any file named `AGENTS.md` or `AGENTS.override.md`), Verification strategy (The floor by name and case) and Decided for you (The protected-path floor) |
| M4-C6 | low | The structural merge-path check does not flag `enablePullRequestAutoMerge`. | fixed: merge-lane-design.md, Existing-path coverage (The Tier A merge rule) and Verification strategy (Structural merge-path check, with a negative case) |
| M4-C7 | low | solution-design.md's stage 5 orphaned-worktree removal and the "`/exit` sent through tmux" Failure-modes row remove a worktree that this design keeps until its end marker is written. | fixed: merge-lane-design.md, opening, Changes to shared documents (item 2), Decided for you (R37) and Verification strategy (#608); the Strain result and liveness component's and stage 1's removals are named with them, each superseded until the run's end marker is written |
| M4-C8 | low | The lane-holder set's rebuild scope is undefined, a label-based scope being user-changeable, and its per-tick reads grow without bound. | fixed: merge-lane-design.md, Lair pull request (the lane-holder set), State and ownership, Failure modes (Failed lane read, Issue not found), Existing-path coverage (Non-Lair pull requests), Verification strategy (#608), Decided for you (the lane-holder set, R30, R31, R38) and Seam order (#608); completed in round 5 by M5-C7 |
| M4-C9 | low | The PRD's Parallelism criterion, each pull request up to date with trunk and green on its merged head, binds #612, and an `--admin` merge of a `BEHIND` pull request breaks it. | fixed: merge-lane-design.md, Seam order (#612, a precondition), Merge-lane step of the tick (the parallel-mode pointer) and Decided for you (R39); completed in round 5 by M5-C6, which drops the rule on `--admin` merges of a `BEHIND` pull request |

## Round 5, 2026-11-22

The confirming round, run as Review procedure says: it reviews only the diff since round 4's fixes and the fixes to open findings, with effort medium.

- **Cerebrate pass reviewer:** a fresh read-only `hivemind:cerebrate` analysis delegation that did not write the design, with effort medium and "Memory context: none".
- **Cerebrate pass angle:** both angles, on the diff `a697d1a8..29ae7759`.
- **Local-tool pass:** the configured local review tool through `run-review.sh --base a697d1a8`, here the `codex-plugin` default, since `HIVEMIND_LOCAL_REVIEWER` is unset and Codex is installed. Verdict: needs-attention.
- **Reviewed:** merge-lane-design.md at blob `d7db0d94be0adb1ecec728b81fe9414fd2d6c88e`, base `a697d1a8`, with the PRD, ADR-0045, ADR-0044 as amended and solution-design.md as sources.

Result: 0 critical, 1 high (local tool), 3 medium, 5 low; 9 in all. All are new. Round 5 showed six round-4 fixes held only in part: M4-L1 (completed by M5-L1 and M5-C4), M4-L2 (M5-C4), M4-C1 (M5-C1, M5-C5), M4-C3 (M5-C2, M5-C3), M4-C8 (M5-C7) and M4-C9 (M5-C6). Where a fix could narrow a claim, it did: the claim that the Lair never queues or arms, decision 16 in the ADR-0044 bullet, and round 4's rule of no `--admin` merge of a `BEHIND` pull request are gone. R32, R33, R34 and R39 are amended in place, and the run's calls R40 to R43 are listed under Decisions taken.

### Local-tool pass findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M5-L1 | high | The 300-second timeout is not a hard bound: plain `timeout` sends TERM and can wait forever on a script or `gh pr merge` child that ignores it. | fixed: merge-lane-design.md, Merge-lane step of the tick (child timeout: a session of its own, `timeout --kill-after=10 300`, a session kill after it, output from a file), Git and tool reads (the session tools resolved at start), Failure modes (Merge-script error, Shadowed tool at start), Verification strategy (Routing, Child timeout: a TERM-ignoring merge child and descendant), Seam order (#605) and Decided for you (R32, amended in place); completed in round 6 by M6-C4, which states the bound as requirements and acceptance tests on #605 and drops the tool example |

### Cerebrate pass findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M5-C1 | medium | ADR-0044's fourth amendment Consequences bullet, Trust boundaries "The pinned head" and R34 say the tick never queues or arms, against the design's own residual for a queue required in the merge gap; and decision 16 still binds the tick. | fixed: ADR-0044, Amendment 2026-11-21, the fourth Consequences bullet, with decision 16 dropped from its watch-only clause; merge-lane-design.md, Merge queues and auto-merge requests, Trust boundaries (The pinned head) and Decided for you (R34, amended in place) |
| M5-C2 | medium | A fix-up park that removes the issue's `lair:review` releases a user's issue-only hold. | fixed: merge-lane-design.md, Run outcome to labels (the fix-up park rows and paragraph: `lair:review` on the pull request first, when the issue carries it), Failure modes (Parked fix-up run), Verification strategy (#610), Seam order (#610) and Decided for you (R40); completed in round 6 by M6-C2, which drops the move to the pull request and keeps the issue's `lair:review` unless the pull request has a review marker |
| M5-C3 | medium | A re-claim that records a pull request held by an earlier claim's review marker is skipped at step 4 forever, with no `lair:review` shown. | fixed: merge-lane-design.md, Merge-lane step of the tick (step 4: a label-only batch review, no second marker), Verification strategy (Holds and skips), Seam order (#605) and Decided for you (R41) |
| M5-C4 | low | The merge script calls `gh pr merge --repo`, not `gh api`; and "until a later tick's late group reads the pull request as not merged" misstates which steps read what. | fixed: merge-lane-design.md, Merge environment (The host binding) and Merge-lane step of the tick (child timeout), and Decided for you (R32, R33, amended in place) |
| M5-C5 | low | The source of "the trunk branch requires a merge queue" is unnamed, and a read that misses rulesets or classic protection fails open. | fixed: merge-lane-design.md, Merge queues and auto-merge requests (one read covering both, chosen and verified by #605; a read that cannot decide is a failed read), Failure modes (Merge queue required), Verification strategy (Merge queue fixtures), Seam order (#605) and Decided for you (R42). This run could not verify a GraphQL field that covers both, so the requirement is stated, not the field; completed in round 6 by M6-C1, which moves the requirement read out of step 3 to steps 8 and 14 |
| M5-C6 | low | R39's "no `--admin` merge of a `BEHIND` pull request in parallel mode" conflicts with ADR-0044 decision 13, and decision 17 if the setting is withheld. | fixed: merge-lane-design.md, Seam order (#612, with ADR-0044 decision 17 added) and Decided for you (R39, amended in place); any such mechanism is an ADR-0044 amendment #612 must ask the user, and this design decides neither |
| M5-C7 | low | The lane-holder rebuild is unbounded, and a failed rebuild blocks admission forever. | fixed: merge-lane-design.md, Lair pull request (the rebuild resumable across ticks from a saved `since` cursor, named in the queue report in progress or stuck), Verification strategy (#608), Seam order (#608) and Decided for you (R43); completed in round 6 by M6-L1 and M6-C3, which replace the cursor algorithm with requirements and acceptance tests on #608 |
| M5-C8 | low | The Round 4 summary says "seven earlier fixes" but lists eight. | fixed: this record, Round 4, now "eight" |

## Round 6, 2026-11-22

A confirming round, run as Review procedure says: it reviews only the diff since round 5's fixes and the fixes to open findings, with effort medium.

- **Cerebrate pass reviewer:** a fresh read-only `hivemind:cerebrate` analysis delegation that did not write the design, with effort medium and "Memory context: none".
- **Cerebrate pass angle:** both angles, on the diff `29ae7759..5aae298d`.
- **Local-tool pass:** the configured local review tool through `run-review.sh --base 29ae7759`, here the `codex-plugin` default, since `HIVEMIND_LOCAL_REVIEWER` is unset and Codex is installed. Verdict: needs-attention.
- **Reviewed:** merge-lane-design.md at blob `487bc63e15058377453646843a24f192885ee3c2`, base `29ae7759`, with the PRD, ADR-0045, ADR-0044 as amended and solution-design.md as sources.

Result: 0 critical, 1 high (local tool), 1 medium, 3 low; 5 in all. All are new. Round 6 showed four round-5 fixes held only in part: M5-L1 (completed by M6-C4), M5-C2 (M6-C2), M5-C5 (M6-C1) and M5-C7 (M6-L1, M6-C3). R32, R40, R42 and R43 are amended in place, and R34 and R36 are corrected to match. No new call is added.

**Change of approach.** The high findings of rounds 5 and 6, M5-L1 and M6-L1, were each a bug in mechanism detail the round before had added: process-session tooling, then a pagination cursor algorithm. That detail is build-level and owned by the slices. So round 6 replaces each prescribed mechanism with requirements and acceptance tests the owning slice must meet: bounded, guaranteed progress, fail closed. The child timeout's requirements are #605's to meet and the lane-holder rebuild's #608's; each slice picks its own tools or paging scheme. This design no longer names a mechanism for either.

### Local-tool pass findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M6-L1 | high | The rebuild cursor, `updated_at` alone with an inclusive `since` and dedupe by id, loops forever when more than a page of comments share one timestamp. | fixed: merge-lane-design.md, Lair pull request (the rebuild: requirements on #608, which chooses and verifies the paging scheme), Verification strategy (#608: more than a full page sharing one `updated_at` with a run-end marker beyond the first page; an edit and a deletion during a multi-page read; a resume after a failed page), Seam order (#608) and Decided for you (R43, amended in place) |

### Cerebrate pass findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M6-C1 | medium | The merge-queue requirement read sits in step 3, so a failed or undecidable requirement read blocks the merged, closed-unmerged and claim-withdrawn exits and can send a merged pull request to batch review. | fixed: merge-lane-design.md, Merge-lane step of the tick (step 3 routes its exits from the issue and pull request reads alone; step 8 reads the requirement, and a failed or undecidable read means no merge call this tick, with only the review wait after it; the fail-closed rule), State and ownership, Failure modes (Failed or incomplete tick read, Merge queue required), Verification strategy (Merge queue: a requirement read failing while the pull request is merged gives the merged exit), Seam order (#605) and Decided for you (R34, corrected; R42, amended in place) |
| M6-C2 | low | R40 says a user's issue-only hold survives a park, but the park still removes the issue's `lair:review`, releasing the admission hold. | fixed: merge-lane-design.md, Run outcome to labels (the fix-up park rows and paragraph: the issue's `lair:review` removed only when the pull request has a review marker, under any claim; otherwise kept until the user removes it, PRD Admission), Failure modes (Parked fix-up run), Verification strategy (#610), Seam order (#610) and Decided for you (R36, corrected; R40, amended in place) |
| M6-C3 | low | Within a tick, offset or Link paging can skip a comment edited or deleted during the read. | fixed: as for M6-L1; the requirement that no comment is missed because of an edit or deletion during the read, with its acceptance test |
| M6-C4 | low | `setsid` without `--wait` forks and returns, so the tick would kill the session mid-merge. | fixed: merge-lane-design.md, Merge-lane step of the tick (child timeout: requirements on #605, which picks the tools; the tool example removed), Git and tool reads, Failure modes (Shadowed tool at start), Verification strategy (Routing, Child timeout: the real code returns a normal merge child's `MERGE=` line; a TERM-ignoring child and a descendant in a group of its own are gone within the bound; no signal before the timeout expires), Seam order (#605) and Decided for you (R32, amended in place) |

## Sources

- The [parent review record](review-record.md), round 3, for the findings above and the eight it assigned to #631; the issue's brief for the other seven.
- The [PRD](../../prds/autonomous-ready-issue-loop.md).
- [ADR-0045](../../adr/0045-lair-software-factory.md), with its amendment "Lair admission excludes epics and requires a passing readiness check".
- [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md), with its amendment of 2026-11-21, "the Lair controller runs the merge script (issue 631)", decisions 17 to 20.
- The [solution design](solution-design.md).
- Trunk commit `9cb44f94dc430a66a57383f9d26e7d6486d3ea14`, the base the design's Context and code truth section was read from.
- Round 1: merge-lane-design.md at blob `0177e805e2d91d69f12c5d64a62121d4fd8ef944`, read directly by the two passes. The round-1 finding text above is as supplied in the remediation brief.
- Round 2: merge-lane-design.md at blob `6e59293f79881ef118e7b86baaebcf3d8f204be9`, read directly by the two passes. The round-2 finding text above is abridged from the remediation brief.
- Round 3: merge-lane-design.md at blob `b8ea94d76b82b10feed989844c2153153df50803`, read directly by the two passes. The round-3 finding text above is abridged from the remediation brief.
- Round 4: merge-lane-design.md at blob `2732101db8f51a6e311614db8a244d26db91c03c`, read directly by the cerebrate pass, and by the local-tool pass through `run-review.sh --base main`. The round-4 finding text above is abridged from the remediation brief.
- Round 5: merge-lane-design.md at blob `d7db0d94be0adb1ecec728b81fe9414fd2d6c88e`, the diff `a697d1a8..29ae7759` read by the cerebrate pass, and the local-tool pass through `run-review.sh --base a697d1a8`. The round-5 finding text above is abridged from the remediation brief.
- Round 6: merge-lane-design.md at blob `487bc63e15058377453646843a24f192885ee3c2`, the diff `29ae7759..5aae298d` read by the cerebrate pass, and the local-tool pass through `run-review.sh --base 29ae7759`. The round-6 finding text above is abridged from the remediation brief.

## Decisions taken (listed for veto)

The calls of the design, each also listed under its Decided for you or Decisions section:

- The review marker is authoritative and final; the Lair never merges a pull request that has one, even if the label is removed. A `lair:review` label only adds a hold (R27).
- Markers go on the claimed issue, never the pull request.
- The review wait is 3600 seconds, the watch's `max_watch_duration` default in `SKILL.md` (recorded in ADR-0029's Findings), measured from the recording run's `ended_at`.
- The routing rows: no checks, conflicts, a blocked merge and a refused merge go to batch review; a script error, malformed output and `merge-pending` wait, bounded by the review wait; `skipped:bad-setting` is handled like `off`.
- The head check goes first in `merge-approved.sh`, before gate 1.
- The merge call pins only the head, and every input it does not pin is one class of known limit: each merge condition is exactly one of five kinds (pinned, derived from git objects, judged by `merge-approved.sh` on its own read, read by the tick in the late group, and Lair-owned state). The seconds between the late group's reads and the merge call are the merge gap; a finding that names a late-group input changing in that gap is a repeat. It extends ADR-0044 decision 15 by analogy and changes nothing in ADR-0044.
- The late group is the last tick work before the merge call, in this order: the merge settings, the credential login on the repository's host, the trunk tip, the identity (with the trunk branch's merge-queue requirement, and the merge-queue state, auto-merge request and `lair:review` of the pull request), the issue (its state, `lair:claimed`, `lair:review` and text) and the settle check, then the merge call and nothing else. The Lair pull request checks are one function, called when a result is recorded and again in the late group, which leaves out the head because the merge call pins it.
- No expected base, author or branch arguments for `merge-approved.sh`. Rejected: GitHub offers no merge call that pins those inputs, so the arguments would only narrow the merge gap, add script surface and amend ADR-0044 decision 19 beyond what the user approved.
- `HIVEMIND_PR_REVIEWERS` comes from the same two user settings files as the merge keys, and the reviewer filter is `automated`.
- The settle snapshots use the `re-arm` arm kind and are keyed by pull request and pinned head.
- The trunk file is `.github/lair.json`, with `protected_paths` and `version_files` under a strict schema; a missing, unparseable or malformed file sends every pull request to batch review. This repository's list holds at least the entries R19 names.
- A major bump is a rise in the major component of any declared version file; a missing, unparseable or lower value goes to batch review.
- A fix-up head counts as reviewed only when the claim's local-review head is not null.
- A fix-up head is recorded only when the previous recorded head is its ancestor.
- The delivery outcome mapping: `blocked`, `no-pr` and an invalid result give `lair:failed`, as `failed`, `crashed`, `stalled` and `timed-out` do; a pull request closed unmerged gives `lair:handoff`. The breaker side is R14.
- A complete run's draft pull request goes to batch review with reason `draft` and does not hold the lane.
- The test layout and suite names under Verification strategy.
- The merge lane's own decisions reverse no ADR-0045 decision; the design fills in ADR-0045 decisions 7, 12, 13 and 17. The halt and breaker stopping fix-up dispatch while merges continue rests on Tier A answer Q10, and the tick's merge path on Q1 and Q3. The strain settings' merge keys are #630's pending ADR-0045 and PRD question (A3-1).
- The solution-design.md Amendments pointer, the parent record's round-3 dispositions and the CONTEXT.md "Lair Pull Request" term are recorded under the design's Changes to shared documents, listed for veto and not applied. The PRD Out of Scope bullet, the ADR-0045 status line and the `decision-autonomy.md` Tier A merge bullet are recorded there too and not applied, but are not listed for veto: they derive from Tier A answers Q1 and Q3 (R21, M3-A9).
- #605 fixes the Lair's script directory, `plugin/skills/lair/scripts/`; the fix-up, halt, breaker, start-check, result recording, delivery run end, lane-holder and admission test cases are added by the slices that build them (M1-A8, M3-A6).
- Every tick read fails closed: a failed or incomplete read means no merge and no label change that tick, and only the review wait may still route, from the markers (M1-B3).
- A resetting settle result deletes the seed before the new snapshot, and only exactly one known line with exit 0 counts, for the poll and the auto tier alike (M1-B4, M1-B5).
- A fix-up run is supervised from its markers: the start marker goes first, a failed write launches nothing, the stall window runs from `started_at` and the budget from `claimed_at` (R15), and a lost run with no unprocessed result gets an end marker with outcome `crashed`, or `not-launched` when it has no worktree (M1-B6, R28).
- Every multi-write route has a fixed write order, each write idempotent and finished on later ticks, with no second review marker for a pull request, under any claim since round 4 (M1-B7, R36). The order itself is R29's.
- A Lair pull request needs a live claim, an open issue and `lair:claimed`; a closed issue or a removed `lair:claimed` is the claim-withdrawn exit, and the closed-unmerged exit also writes a review marker (M1-B8).
- The protected-path floor is the root `.github/` directory and the exact path `.github`, any `.claude` or `.codex` path segment, any file named `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `AGENTS.override.md`, `.mcp.json`, `.gitmodules` or `.gitattributes` at any depth, and any path with a byte other than printable ASCII or a segment ending in `.` or a space, with ASCII case ignored; the list gains the `**/<name>` form, and a prefix entry also matches its exact path (M1-B11, M2-B12, M4-C5).
- `.github/lair.json` has a strict schema, and `[]` is the only way to declare no entries (M1-B12).
- The tick reads only the two named settings files, and the queue report names the files read (M1-B15).
- The late group rereads the issue's state and `lair:claimed`; a withdrawal it sees makes no merge call and is routed by the next tick's step 3 (M2-A1, M2-B1).
- Step 3 reads the issue before the pull request and routes a merge first (M2-B9).
- A waiting CI-red rule and a queued pull request each run only the review wait, then stop (M2-A9, M2-B15, R22).
- Results stay in the run's worktree until their marker is written (R22); a failed result-check read retries on later ticks, bounded by the issue's budget, and only a check that reads and fails makes a result invalid (M2-B2).
- The lane-holder set, kept by #608, holds every pull request a run-end marker names (R23), closed and merged ones included (R30, R38), and admission fails closed on a failed read (M2-B3).
- The Lair's git repository is checked each tick and rebuilt on any change it did not write, and every git call drops the environment's `GIT_*` variables and sets `GIT_NO_REPLACE_OBJECTS=1` and `diff.ignoreSubmodules=none` (M2-B4).
- A queued pull request makes no further merge call (M2-B8). Round 3 replaced the merge-pending mark with GitHub's merge-queue state (R22), and round 4 adds an armed auto-merge request (R34).
- A fix-up run that ends under an ended claim writes only its end marker (M2-B10).
- The lane order rotates: the pull request whose merge call ran last goes to the end of the next tick's order (M2-B13).
- The tick's `PATH` puts the resolved tool directories first, and the Lair refuses to start when `command -v` of a tool under it differs from its resolved path (M2-B14).

The calls of this run:

- This record reuses the parent record's keys and disposition vocabulary.
- Only merge-lane-design.md is stamped. ADR-0044 is amended by this run but reviewed, not stamped, like the other sources.
- A3-11, A3-12 and B3-20 are owned only in part; their other parts stay open in the parent record.
- Every owned round-3 finding is dispositioned `fixed` by the design as written; the review rounds confirm or reopen each one. Where a later round's finding showed a fix held only in part, the disposition stays `fixed` and names the findings that completed it. Round 2 reverted one round-1 fix, M1-B9, for compliance with ADR-0045 decision 13, and its disposition became `recorded`.
- The seams with #630 and #632 are stated as assumptions in the design, and their files are not created.
- Local review returned a root-cluster finding on the merge-lane tick's unpinned inputs. Root cause: the tick judged its merge conditions on its own reads, in a step list that grew one check per review round, while the merge call pins only the head, and the design never said which inputs the call can cover and which it never can. Class fix: every merge condition is keyed to one of five kinds by who reads it relative to the merge call, the tick's reads run in one late group with only the merge call after it, and the Lair pull request checks are one function used at recording and in the late group. The residual merge gap is recorded once as a class in merge-lane-design.md, Merge-lane step of the tick (Known limit) and Trust boundaries. Linked findings: `6cae4d438fcbd73fb76c1487beac991a3f98ae859ad5079fc9455024a74a23ed`, `b81db886da79ea26f3ece2cccdac1982ba7c77d628fc10391a295e0e7a20a4d2`, `ff9090699d221fd738ca76ed6b8d479146ba249d1eeb623d09eb7003d2ce1b41` and `bf472704b77555a397febc7472498d3c3e9e4d789170f336accca5151bef9024`. ADR-0044 is unchanged by this fix.

The calls on the review rounds' open choices, each decided by the run and dated 2026-11-21, or 2026-11-22 for R32 to R43, and each also listed under the design's Decided for you. R12 and R13 were withdrawn from this list because the changes they named derive from Tier A answers (R21, M3-A9):

- **R1** (M1-A3): a fix-up run's `decision` and `fact` parks are answerable on the issue and count toward the third-park handoff, under ADR-0045 decision 7. #609 handles them as a delivery run's park; the Lair first converts the pull request to a draft, so it belongs to its parked issue and does not hold the lane. The contrary text and the "no ADR-0045 change" claim are corrected.
- **R2** (M1-A4): the review-finding fix-up cap, `fixup-cap`, is dropped. What starts a fix-up run on review findings stays with #610, per ADR-0045 decision 13 and the PRD's Post-PR feedback criterion. The unbounded review loop is a seam note for #610, not a merge-lane rule.
- **R3** (M1-A5): `lair:review` goes on both the issue (PRD Labels and Admission) and the pull request (ADR-0045 decision 12).
- **R4** (M1-B1): the #630 assumption is the property that no strain process can write what the tick reads or runs: the two user settings files, the Lair cache directory, the main checkout's git common directory (config, hooks, refs), the `PATH` directories and the plugin script directory. A worktree strain must write objects and refs, so hooks and config need a carve-out or a per-strain clone, which is #630's choice. The tick hardens itself as well: a Lair-owned bare repository, hooks and system and global config off, a fixed URL, the trunk id from this tick's `ls-remote`, and tools by absolute path. Round 2 added the per-tick repository check, `GIT_NO_REPLACE_OBJECTS=1`, `diff.ignoreSubmodules=none`, the removal of inherited `GIT_*` variables and the start-time `PATH` check (M2-B4, M2-B14), and dropped the claim that this hardening does not rely on the assumption. The residuals are ADR-0045's prompt-injected strain, with its merge-lane consequences listed, and a strain that writes the tick's inputs; the Lair pull request checks are not called a bound against a strain that reports values. Round 3 restates the assumption as a property, a strain writes nothing outside its worktree and the shared object and ref store, and adds the `$HOME/.jq` and `http_unix_socket` start checks (R26).
- **R5** (M1-B2): an explicit #632 assumption that a process holding the user's GitHub credentials, the claim nonce and the run nonce cannot produce a marker that passes #632's rule; otherwise marker forgery is a named residual. The design's pinned-head line and ADR-0044's amendment consequence are conditional on it.
- **R6** (M1-A2, M1-B10): the merge script and the settle check run in the Lair's own environment minus every `HIVEMIND_*` key, plus the keys read from the two settings files, so merge settings never come from the environment (Q4). Before every merge call, `gh api user` in that environment must report the Lair's own login; a mismatch is no merge with the reason `credential-mismatch`. The "authenticates as the Lair does" claim is dropped, and a test is added. Round 4 binds the environment and the check to the repository's host (R33).
- **R7** (M1-B13, M1-A14): the CI-red rule fires from the tick's own rollup read on the pinned head or `MERGE=wait:checks-failed`, whatever the merge settings, the approval and the gate order. Q9's one fix-up run, then batch review, is unchanged. Corrected in round 2 (R17): the settle check's `CI_FAILED` only means not settled.
- **R8** (M1-A6): `pr`, `branch`, `head` and `local_review_head` move out of the claim marker into a run-end marker the merge lane owns. The lane reads `claim_nonce`, `claimed_at` and `body_sha256` from #632's claim marker and assumes only #632's author and nonce rule applies to its own markers too.
- **R9** (M1-B17): at most one merge call per tick, and the trunk tip is re-resolved in the late group, with the auto tier run again when it moved.
- **R10** (M1-B16): every merge-lane child process runs under a 300-second timeout, a killed read counting as a failed read. Round 3 exempted `merge-approved.sh` (R25), and round 4 bounds it again (R32).
- **R11** (M1-A9): the empty-string merge keys in strain settings are #630's pending ADR-0045 and PRD change (A3-1), not this design's; the design claims only that its own decisions reverse no ADR-0045 decision (narrowed in round 2, M2-A10).
- **R14** (M2-A3): the breaker counts only `failed`, `crashed`, `stalled` and `timed-out`, the outcomes ADR-0045 decision 17 and the PRD's Stop controls criterion name, with `stalled` from solution-design.md's Stall row (M3-A11). Delivery `blocked`, `no-pr` and `invalid-result`, fix-up `blocked` and invalid results, and any fix-up end under an ended claim neither add to the count nor reset it; a `complete` run end under a live claim resets it. The design's claim about ADR-0045 is corrected to match.
- **R15** (M2-A4): the wall-clock budget is per issue, measured from the claim marker's `claimed_at`, and a fix-up run runs on what is left of it (the PRD's Budgets and recovery criterion, ADR-0045 decision 17). Fix-up outcomes: `complete` with checks passing records the head; `parked` is #609's park; `failed`, `blocked` and an invalid result go to batch review with reason `fixup-failed`; `crashed`, `stalled` and `timed-out` give `lair:failed` and end the claim. With no budget left no fix-up run starts, and the pull request goes to batch review with reason `budget-exhausted`, a tick route and not a run outcome. The stall window runs from the start marker's `started_at`. The round-1 rules for the start marker and the `crashed` end marker stand, but a `crashed` fix-up run now gives `lair:failed`, like `stalled` and `timed-out`, where round 1 sent it to batch review.
- **R16** (M2-A5): a review marker does not stop a fix-up run (ADR-0045 decision 13, the PRD's Post-PR feedback criterion); the round-1 fix of M1-B9 is reverted. The design sets preconditions on #610's trigger only where a binding source allows: a live claim, no run in flight, budget left, and no halt or tripped breaker. Round 3 dropped the precondition that a fresh GitHub head equal the pinned head (M3-A1): the run starts at the pinned head, and a moved branch fails its leased first push. Fix-up runs pushing while the user reviews is a recorded residual.
- **R17** (M2-A6): the settle check's `CI_FAILED` is not a CI-red signal; CI-red comes from step 7's rollup read on the pinned head and from `MERGE=wait:checks-failed`. R7's wording is corrected. Its start precondition on a fresh GitHub head is dropped in round 3 (M3-A1, R16).
- **R18** (M2-B5): every strain push is leased (an assumption about #630): a fix-up run's against its `start_head`, then its own last push, so a push by another process makes the run's next push fail, no head built on it is recorded, and a failed fix-up run goes to batch review with reason `fixup-failed`. ADR-0044's amendment, its third Consequences bullet, and the design's pinned-head trust bullet are conditional on it; without it, ADR-0044's residual "An unreviewed push by another account can merge" applies through fix-up heads. #630 adds it as a strain-only mode of `push-branch.sh` and `open-plan-pr`, reversing their recorded lease decision for strains only; the interactive push path is unchanged (M3-A4).
- **R19** (M2-B6): this repository's `.github/lair.json` must protect `plugin/skills/lair/`, `plugin/skills/github-review-loop/scripts/`, `plugin/skills/_shared/`, `plugin/hooks/`, `plugin/.claude-plugin/`, `.claude-plugin/`, `plugin/workflow-src/`, `plugin/workflows/`, `plugin/agents/local-reviewer.md`, `plugin/skills/adaptation-cycle/`, `plugin/skills/push-branch/`, `plugin/skills/open-plan-pr/`, `tools/` and `tests/policy/`, a requirement on #605's list derived from what the merge, poll, auto-tier and tick scripts run or source and the producers of the local-review evidence and the leased pushes, with a test that the committed list holds them. Round 3 added `plugin/skills/_shared/`, `.claude-plugin/`, `plugin/workflow-src/` and `plugin/workflows/` (M3-A5, M3-B4), and round 4 added `plugin/agents/local-reviewer.md`, `plugin/skills/adaptation-cycle/`, `plugin/skills/push-branch/` and `plugin/skills/open-plan-pr/` (M4-C4).
- **R20** (M2-B11): a pull request GitHub's merge queue already holds is not taken out of it when `HIVEMIND_AUTO_MERGE` is unset or a review marker is written later; no dequeue write is added, and the case is a named residual. Round 4 extends the residual to an armed auto-merge request and makes no merge call in a repository that requires a merge queue (R34).
- **R21** (M2-A10, M2-A11): the PRD Out of Scope change (Changes to shared documents, item 6) and the ADR-0045 status-line change (item 7) derive from Tier A answers Q1 and Q3, so each carries an Answer line citing them and neither is listed for veto. R13, the round-1 call that listed item 6 for veto, is withdrawn.
- **R22** (M3-A2, M3-B1): GitHub's merge-queue state replaces the merge-pending mark, and the kept result file replaces the result cache. Step 3 and the late group read the pull request's merge-queue state, and a queued pull request gets no merge call. The Lair removes no run's worktree or result file until that run's end marker is written.
- **R23** (M3-A3): every pull request a run-end marker names holds the lane while open and not a draft, recorded or not. The run-end marker holds `pr` for every result that names one and passes the schema check; only a checked `complete` result records it. A pull request no result names is a recorded residual.
- **R24** (M3-A7): under #606's release-train mode the auto tier fails closed with `version-unreadable` until #606 supplies a bump input the pull request cannot change. Q5's input is unchanged, and the #606 seam no longer replaces it.
- **R25** (M3-A8): `merge-approved.sh` runs under no child timeout, as its header requires; its own reads are bounded, its merge call is never cut off, and the merge-queue read covers a merge call whose line was lost. Superseded in round 4 by R32 (M4-L1).
- **R26** (M3-B2): the #630 write assumption is a property: a strain writes nothing outside its worktree and the shared object and ref store. The Lair refuses to start when `$HOME/.jq` exists or `gh` has an `http_unix_socket` set; a later write of either is named in the residual.
- **R27** (M3-B3): a `lair:review` label on the issue or the pull request is an extra hold, read at steps 4, 14 and 15. It only adds holds and fails closed; the review marker stays authoritative for release. The Lair acting as the user's own login is a named residual, with the user's working holds listed.
- **R28** (M3-B5): a fix-up start marker with no live session, no result and no worktree ends `not-launched`, which writes no label, does not end the claim, leaves the breaker unchanged and does not use up the CI fix-up. The run's worktree is the launch evidence.
- **R29** (M3-B6): a route writes its labels and pull request changes first and its markers last, so the marker that ends the route marks it done, and a later tick that finds it missing computes the route again from the same inputs. The applied marker and the walk over unfinished sequences are removed.
- **R30** (M3-B11): a closed pull request stays in the lane-holder set until GitHub shows it merged, so a reopened one holds the lane again. Round 4 keeps merged ones too (R38).
- **R31** (M3-B12): a claimed-issue read that GitHub answers as not found or moved is named in the queue report as needing the user from the first such answer, with no clock and no new cache; the open pull request read still frees the lane.
- **R32** (M4-L1): `merge-approved.sh` runs under the tick's 300-second child timeout. For the Lair only, this overrides the script header's "merge calls are never wrapped", because a hung merge call would hold the single-instance lock and stop the whole controller. A killed run routes as `MERGE_ERROR`; the next tick's state read routes a merge, and no merge call runs again until step 3 reads the pull request open and step 14 reads it not queued and with no auto-merge request; the script's gate 1 judges the state again. 300 seconds covers the script's own reads, at most three of 45 seconds. The watch's call is unchanged. It supersedes R25. Amended in place in round 5 (M5-L1, M5-C4): the bound is hard, so the child and every descendant end within 310 seconds. Amended in place in round 6 (M6-C4): the bound is stated as requirements on #605, which picks the tools: each child in a session and process group of its own; the tick waits for the child's own exit status; at 300 seconds TERM to the whole session, and after a 10-second grace KILL to every process left in it; the output read only after the child exits. Acceptance tests: a normal merge child through the real code returns its `MERGE=` line; a TERM-ignoring child and a descendant in a group of its own are gone within the bound; no signal comes before the timeout expires. Round 5's tool example is dropped, because one of its tools returned before the child ended.
- **R33** (M4-L2): the merge environment is bound to the repository's host, read from the repository URL the Lair fixes at start. It sets `GH_HOST` to that host, whatever the Lair's environment held, and drops `GH_ENTERPRISE_TOKEN` and `GITHUB_ENTERPRISE_TOKEN` when the host is `github.com`; every `gh` call of the step runs in it. The login check runs `gh api user --hostname <host>`. The poll script calls `gh api`, and the merge script `gh api graphql` and `gh pr merge --repo <owner>/<repo>`; none passes a host, so each resolves to `GH_HOST` (corrected in place in round 5, M5-C4). A mismatch is `credential-mismatch`, no merge. A URL whose host cannot be read stops the Lair at start.
- **R34** (M4-C1): the Lair makes no merge call in a repository whose trunk branch requires a merge queue, and sends its pull requests to batch review with reason `merge-queue-required`; it also makes none while a pull request is queued or has an auto-merge request, read at steps 3 and 14. Chosen as the simplest fail-closed option: the Lair's own call then queues a merge or arms a request only when the trunk branch starts requiring a merge queue in the merge gap (corrected in place in round 5, M5-C1). An auto-merge request armed by someone else, the user included, is outside the Lair and a named residual. ADR-0044's amendment gains a Consequences bullet saying so.
- **R35** (M4-C2): the fix-up in-flight check runs at step 2, on step 1's markers alone, before the state read, so a fix-up route whose end marker is missing is never routed as a claim withdrawal. Steps 2 to 4 of earlier rounds are now steps 3, 4 and 2.
- **R36** (M4-C3): a review marker holds its pull request under any claim of the issue, and a route writes no second review marker for it under any claim. A fix-up park removes `lair:review` from the issue; a held pull request keeps its label and review marker. Round 6 removes the issue's label only when the pull request has a review marker (R40).
- **R37** (M4-C7): solution-design.md's worktree removals in the Strain result and liveness component, stage 1, stage 5's orphan sweep and the `/exit` Failure modes row are superseded until the run's end marker is written, and stand after it.
- **R38** (M4-C8): the lane-holder set is rebuilt from one paginated read of the repository-wide issue-comment list, keeping run-end markers that pass #632's rule, with no label and no search. Each tick, one paginated read of the open pull requests is intersected with the set; closed and merged pull requests stay in it and cost no read.
- **R39** (M4-C9): #612's parallel mode must meet the PRD's Parallelism criterion before it is on, each pull request up to date with trunk and green on its merged head, with no merge queue (R34). That is a #612 precondition; how #612 meets it is #612's. Reworded in place in round 5 (M5-C6): round 4's rule of no `--admin` merge of a `BEHIND` pull request is dropped; any mechanism that changes the `--admin` retry (ADR-0044 decisions 3 and 13) or withholds `HIVEMIND_AUTO_MERGE_ADMIN` (decision 17) is an ADR-0044 amendment #612 must ask the user as a Tier A question, and this design decides neither.
- **R40** (M5-C2): a fix-up park removes the issue's `lair:review` only when the pull request has a review marker, under any claim; the pull request then keeps its marker and label. With no review marker, the issue's label is the user's own hold or that of an interrupted batch review, and the park keeps it: the answered issue stays out of admission (PRD Admission) until the user removes it, which is the user's call. Amended in place in round 6 (M6-C2): round 5's move of the label to the pull request is dropped, because the park still removed the issue's label, which is the hold admission reads.
- **R41** (M5-C3): when step 4's hold comes from a review marker of an earlier claim and step 3's read shows the issue or the pull request without `lair:review`, the step runs a label-only batch review, adding `lair:review` to both, with no second review marker.
- **R42** (M5-C5): the trunk branch's merge-queue requirement comes from one read that covers both rulesets and classic branch protection, chosen and verified by #605; a read that cannot decide is a failed read, so no merge call follows. Amended in place in round 6 (M6-C1): the requirement is read at step 8, where the merge is decided, and again at step 14, never among step 3's exit-routing reads, so a failed or undecidable requirement read stops only this tick's merge call, never the merged, closed-unmerged or claim-withdrawn exit.
- **R43** (M5-C7): the lane-holder rebuild is resumable across ticks. #608 chooses and verifies the paging scheme, to requirements: resumable across ticks from a saved position; progress on every successful page, a run of equal `updated_at` values longer than a page included; no comment missed because of an edit or deletion during the read; a failed page read changing nothing saved. The queue report names a rebuild in progress or stuck, and admission claims nothing until it ends. Acceptance tests: more than a full page sharing one `updated_at` with a run-end marker beyond the first page; an edit and a deletion during a multi-page read; a resume after a failed page. Amended in place in round 6 (M6-L1, M6-C3): round 5's cursor algorithm is dropped, because a run of equal timestamps longer than a page made it loop, and offset paging could skip a comment on an edit or deletion.

## Decisions asked

The user answered A to each of the ten Tier A questions on 2026-11-21:

| Question | Answer | Date |
| --- | --- | --- |
| Q1. Amend ADR-0044 decisions 2 and 10 so the Lair controller may run `merge-approved.sh`. | A | 2026-11-21 |
| Q2. A settle check equal to ADR-0044 decision 1, using the watch's change check against a saved snapshot each tick. | A | 2026-11-21 |
| Q3. An optional sixth expected-head argument; a differing head prints `MERGE=wait:head-moved` with no merge call. | A | 2026-11-21 |
| Q4. Merge settings come only from the user's `.claude/settings.local.json`, then `~/.claude/settings.json`, with a PRD Credentials note recorded. | A | 2026-11-21 |
| Q5. Protected paths come from a trunk list plus a fixed floor; the bump comes from the version-file diff. | A | 2026-11-21 |
| Q6. Local-review proof is the delivery run's recorded head plus heads the Lair's own fix-up runs recorded. | A | 2026-11-21 |
| Q7. Only a pull request the Lair recorded on the claimed issue after checking it against GitHub may merge. | A | 2026-11-21 |
| Q8. No merge after an issue edit; the pull request goes to batch review. | A | 2026-11-21 |
| Q9. One fix-up run for failed checks, then batch review. | A | 2026-11-21 |
| Q10. Halt and breaker stop claims and fix-up dispatch; merges continue; unsetting auto-merge stops merges. | A | 2026-11-21 |

The user also set the review procedure on 2026-11-21. These are the user's instructions, not run decisions:

| Instruction | Date |
| --- | --- |
| From round 4 on, each round runs one `hivemind:cerebrate` pass covering both angles (code truth, governance and ADR conflicts, existing-path coverage; failure modes, trust and injection, testability), delegated with effort high; no parallel passes. Because this design touches trust, credentials and the merge path, each round also runs one pass through the configured local review tool via `run-review.sh` (here the `codex-plugin` default: `HIVEMIND_LOCAL_REVIEWER` unset, Codex installed); if none is configured, the pass is skipped and the skip recorded. The confirming round reviews only the diff since the previous round and the fixes to open findings, with effort medium. | 2026-11-21 |
| There is no round cap; the parent record's 3-round cap does not apply. | 2026-11-21 |
