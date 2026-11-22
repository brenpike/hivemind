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

# Design review record: Lair merge lane

This record covers the design review of the Lair's merge lane, issue #631: the [merge-lane design](merge-lane-design.md). Only merge-lane-design.md is stamped. Its stamp's blob is `git rev-parse HEAD:docs/initiatives/autonomous-ready-issue-loop/merge-lane-design.md`, and the stamp is written last, after every other change to this record. The [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md), [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md) and the [solution design](solution-design.md) are reviewed, not stamped.

The review exits only when zero critical or high findings are open and one round raises no new findings. It runs rounds until then; there is no round cap.

Each round runs two passes in parallel. Each pass is a fresh, read-only `hivemind:cerebrate` analysis delegation with "Memory context: none":

- **Pass A:** code truth, governance and ADR conflicts, and existing-path coverage.
- **Pass B:** failure modes, trust and injection, and testability.

New finding IDs take the `M` prefix, then the round, the pass and the finding number: `M1-A2` is round 1, pass A, finding 2.

## Record keys

- `stamps`: one entry, for merge-lane-design.md, with `path` and `blob` keys. Empty until the review passes.
- `verdict`: `pending`, `pass` or `fail`.
- `open_counts`: open findings by severity: `critical`, `high`, `medium` and `low`. It counts every finding this record owns that is still open: the round-3 findings below and every `M` finding.
- `rounds`: the number of rounds run.
- `clean_round`: the round that raised no new findings, or `null`.

## Dispositions

Every finding is open until it gets exactly one disposition:

- **fixed**: the record says where.
- **deferred**: the record names a tracked issue.
- **recorded**: the record says where.
- **rejected**: the record says why.

**Open** is a state, not a disposition. An open finding is counted in `open_counts`, and its disposition column reads `open`.

### Round-3 findings this issue owns

The findings come from round 3 of the [parent review record](review-record.md), which split them out to #631. Each disposition names the section of merge-lane-design.md that answers it. Three findings are owned only in part; the Finding column states the part, and the rest stays with the parent record.

| ID | Severity | Finding | Overlaps | Disposition |
| --- | --- | --- | --- | --- |
| A3-2 | high | The tick runs `merge-approved.sh` outside the watch, dropping ADR-0044's settled-approval precondition, and the failure-mode row maps the script's results wrongly. | B3-5, B3-6 | fixed: merge-lane-design.md, Settle check, Routing table and Failure modes, under ADR-0044 decisions 17, 18 and 20; completed in round 1 by M1-B3, M1-B4, M1-B5, M1-B13 and M1-B16, and in round 2 by M2-A6, M2-A9 and M2-B8 |
| A3-3 | high | The controller has no defined source for the merge settings it reads each tick, so unsetting auto-merge may never stop merges. | B3-7 | fixed: merge-lane-design.md, Merge settings source, Merge environment and Lifecycle "Stage 4: halt and circuit breaker"; completed in round 1 by M1-A2, M1-B10 and M1-B15, and in round 2 by M2-B11 |
| B3-4 | high | Strain result fields (`pr`, `branch`, `head`) are trusted unchecked, and "Lair PR" is undefined. | | fixed: merge-lane-design.md, Lair pull request, Pinned head and Merge-lane step of the tick (late group); completed in round 1 by M1-A6, M1-B1, M1-B2 and M1-B8, and in round 2 by M2-A1, M2-B2, M2-B3 and M2-B5 |
| B3-5 | high | The tick's merge drops ADR-0044's settle period and does not tie the auto tier to the merged head. | A3-2 | fixed: merge-lane-design.md, Settle check, Pinned head and Expected-head argument; completed in round 1 by M1-B4, M1-B5 and M1-B17, and in round 2 by M2-B8 |
| B3-6 | high | The merge-result failure-mode row maps `merge-approved.sh` results wrongly. | A3-2 | fixed: merge-lane-design.md, Routing table and Failure modes |
| B3-7 | high | No defined source for merge settings in the tick. | A3-3 | fixed: merge-lane-design.md, Merge settings source and Merge environment; completed in round 1 by M1-A2, M1-B10 and M1-B15 |
| B3-8 | high | Auto-tier inputs (protected-path list, local-review-skipped evidence, bump type) are undefined or untrusted. | A3-10 | fixed: merge-lane-design.md, Auto-tier script, Git and tool reads and Trust boundaries; completed in round 1 by M1-B1, M1-B11, M1-B12 and M1-B17, and in round 2 by M2-B4, M2-B6, M2-B12 and M2-B14 |
| A3-10 | medium | Auto-tier inputs have no named source, and two can be forged by the strain. | B3-8 | fixed: merge-lane-design.md, Auto-tier script and Trust boundaries; completed in round 1 by M1-B1, M1-B11 and M1-B12, and in round 2 by M2-B4, M2-B6 and M2-B12 |
| A3-8 | medium | Draft-PR and closed-unmerged states have no lifecycle exit. | | fixed: merge-lane-design.md, Exits (Draft, Closed unmerged, Claim withdrawn) and Write order; completed in round 1 by M1-B7 and M1-B8, and in round 2 by M2-B3 and M2-B9 |
| B3-13 | medium | The run outcome to label mapping is incomplete (blocked, complete with no PR, invalid result). | | fixed: merge-lane-design.md, Run outcome to labels; completed in round 2 by M2-A3 |
| B3-14 | medium | Remediation strains leave no GitHub record, their parks have no path, and the halt does not cover them. | | fixed: merge-lane-design.md, Fix-up runs, Markers the merge lane writes, Run outcome to labels and Lifecycle "Stage 4: halt and circuit breaker"; completed in round 1 by M1-A3, M1-B6 and M1-B7, and in round 2 by M2-A4, M2-A5, M2-B2 and M2-B10 |
| A3-13 | low | It is unclear whether `lair:review` goes on the issue or the pull request. | | fixed: merge-lane-design.md, Exits (Batch review: on the issue and the pull request) and State and ownership; completed in round 1 by M1-A5 |
| A3-12 | medium | This scope's part: the no-merge-after-edit and CI-red calls should have been asked, and this scope's calls were not listed for veto. The session-scoped breaker call is not in this scope. | | fixed: merge-lane-design.md, Tier A answers (Q8, Q9) and Decided for you; the veto list completed in round 1 by M1-A14 and the run's calls R1 to R13, and in round 2 by M2-A11 and the run's calls R14 to R21, R21 withdrawing the Tier-A-derived R13 |
| B3-20 | low | This scope's part: the merge-lane tests and their `tools/validate.sh` registration. The overlord prose, injection and halt tests and the halt file path are not in this scope. | | fixed: merge-lane-design.md, Verification strategy; completed in round 1 by M1-A8, M1-A13, M1-B5 and M1-B14, and in round 2 by M2-A8 and M2-B7 |
| A3-11 | medium | This scope's part: the Seam order ADR lists for the slices the merge lane changes. | | fixed: merge-lane-design.md, Seam order; completed in round 1 by M1-A1 and M1-A7, and in round 2 by M2-A7 |

## Round 1, 2026-11-21

Two passes, run in parallel.

- **Pass A reviewer:** a fresh read-only `hivemind:cerebrate` analysis delegation that did not write the design, with "Memory context: none".
- **Pass A angle:** code truth, governance and ADR conflicts, existing-path coverage.
- **Pass B reviewer:** the same kind as pass A.
- **Pass B angle:** failure modes, trust and injection, testability.
- **Reviewed:** merge-lane-design.md at blob `0177e805e2d91d69f12c5d64a62121d4fd8ef944`, with the PRD, ADR-0045, ADR-0044 as amended and solution-design.md as sources.

Result: 0 critical, 3 high (all from pass B), 18 medium (7 from pass A, 11 from pass B) and 11 low (8 from pass A, 3 from pass B). All are new. Each was fixed in merge-lane-design.md, or in ADR-0044's 2026-11-21 amendment where named. Round 2 reverted the fix of M1-B9 for compliance, and its disposition is now recorded (R16). The run's calls on the open choices were R1 to R13; R1 to R12 are listed under Decisions taken, and R13 was withdrawn from the veto list in round 2 (R21).

### Pass A findings

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M1-A1 | medium | The tick is a second merge path, while `decision-autonomy.md` Tier A and its pinned fixture say only the watch merges, and no slice owns the change. | fixed: merge-lane-design.md, Existing-path coverage (The Tier A merge rule), Seam order (#605) and Changes to shared documents, item 5 (R12) |
| M1-A2 | medium | `env -i` drops `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `XDG_CONFIG_HOME` and the D-Bus keyring variables. | fixed: merge-lane-design.md, Merge environment (R6) |
| M1-A3 | medium | A fix-up park was made not answerable and not counted toward the third-park handoff, against ADR-0045 decision 7, while the design claimed no ADR-0045 change. | fixed: merge-lane-design.md, Run outcome to labels, Failure modes (Parked fix-up run) and Decisions (R1) |
| M1-A4 | medium | The review-finding fix-up cap (`fixup-cap`) sets what starts a fix-up run, which ADR-0045 decision 13 and the PRD leave to #610, and the opening's scope statement does not match. | fixed: merge-lane-design.md, opening, Fix-up runs (Seam note for #610) and Failure modes; the cap is dropped (R2) |
| M1-A5 | medium | `lair:review` only on the pull request contradicts the PRD's Labels and Admission criteria, which put it on the issue. | fixed: merge-lane-design.md, Routing table, Exits, Run outcome to labels and State and ownership (R3) |
| M1-A6 | medium | The run-end fields were added to #632's claim marker, whose contract this design does not own. | fixed: merge-lane-design.md, opening, State and ownership and Markers the merge lane writes (Run-end marker) (R8); completed in round 2 by M2-A2 |
| M1-A7 | medium | The Seam order ADR lists are incomplete for #604, #605, #608 and #610. | fixed: merge-lane-design.md, Seam order; completed in round 2 by M2-A7 |
| M1-A8 | low | #605 depends on #608 and later slices (the script directory, the fix-up, halt and breaker cases) but builds first. | fixed: merge-lane-design.md, Merge-lane step of the tick (script directory), Verification strategy (cases added by the slices that build them) and Seam order |
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
| M1-B1 | high | The #630 assumption covers only the settings files and the cache; a strain can write the git common directory, `PATH` directories or the plugin scripts the tick runs, and the residual understates ADR-0045's. | fixed: merge-lane-design.md, Git and tool reads, Assumptions about #630 and Trust boundaries (R4); completed in round 2 by M2-B4, M2-B5 and M2-B14 |
| M1-B2 | high | A strain holds the user's credentials and the nonces, so it can forge markers unless #632's rule stops it, yet the design and the amendment treat recorded heads as unforgeable. | fixed: merge-lane-design.md, Assumptions about #632 and Trust boundaries (The pinned head, Residual: marker forgery); ADR-0044, Amendment 2026-11-21, Consequences (R5) |
| M1-B3 | high | Tick reads have no fail-closed route, and the absence checks fail open on a failed or partial comment read. | fixed: merge-lane-design.md, Merge-lane step of the tick (steps 1, 2 and 10 and the fail-closed rule), Failure modes and Verification strategy; completed in round 2 by M2-B2 |
| M1-B4 | medium | A failed re-snapshot keeps the old `quiet_since`, so the settle check can settle early. | fixed: merge-lane-design.md, Settle check, Failure modes (Failed re-snapshot) and Verification strategy; completed in round 2 by M2-B8 |
| M1-B5 | medium | The poll and tier outputs are caught by catch-alls, so a malformed line can settle or reach the late group. | fixed: merge-lane-design.md, Settle check, Merge-lane step of the tick (step 10) and Verification strategy; `pr-change-detect-poll.sh` routes to the merge-lane suite, and `loop-state.sh` is no longer read after R2 |
| M1-B6 | medium | An in-flight fix-up run is unbounded: no budget, stall or crash route ends it. | fixed: merge-lane-design.md, Fix-up runs, Failure modes (Fix-up run lost in flight, Start marker write failed) and Verification strategy; completed in round 2 by M2-A4 and M2-B2 (R15) |
| M1-B7 | medium | Routes with several writes have no order or retry, and only open pull requests are iterated. | fixed: merge-lane-design.md, Write order, Lair pull request (the lane set), Failure modes and Verification strategy |
| M1-B8 | medium | A pull request stays a Lair pull request after its claim ends, and a closed issue or a removed `lair:claimed` has no route. | fixed: merge-lane-design.md, Lair pull request and Exits (Closed unmerged, Claim withdrawn); completed in round 2 by M2-A1, M2-B3 and M2-B9 |
| M1-B9 | medium | A fix-up run can start for a pull request with a review marker. | recorded: merge-lane-design.md, Fix-up runs (Recorded residual: fix-ups during batch review); the round-1 fix was reverted in round 2 for compliance with ADR-0045 decision 13 and the PRD's Post-PR feedback criterion (M2-A5, R16) |
| M1-B10 | medium | The clean environment does not prove which account `gh` acts as. | fixed: merge-lane-design.md, Merge environment and Merge-lane step of the tick (step 12) (R6) |
| M1-B11 | medium | The protected-path floor misses nested and case-variant `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json` and `.claude` paths. | fixed: merge-lane-design.md, Auto-tier script (the list forms and the floor) and Verification strategy; completed in round 2 by M2-B12 |
| M1-B12 | medium | `.github/lair.json` has no strict schema, so a malformed list can declare no protected paths. | fixed: merge-lane-design.md, Auto-tier script (the schema) and Verification strategy |
| M1-B13 | medium | The CI-red rule waits on the merge script's gate order and settings. | fixed: merge-lane-design.md, Merge-lane step of the tick (step 7) and Fix-up runs (The CI-red rule) (R7); completed in round 2 by M2-A6 (R17) |
| M1-B14 | medium | Verification misses holds, skips, exits, settle results, delivery rows and the existing `args:six` case, and the late-group order test cannot see the settings and cache reads. | fixed: merge-lane-design.md, Verification strategy and Existing-path coverage; completed in round 2 by M2-B7 |
| M1-B15 | low | "Matches Claude Code's order" is false, and other settings sources are not ruled out. | fixed: merge-lane-design.md, Merge settings source |
| M1-B16 | low | A hung child process stalls the tick. | fixed: merge-lane-design.md, Merge-lane step of the tick (child timeout) and Routing table (R10) |
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
| M2-B3 | medium | Once a claim ends, its still-open pull request leaves the lane set, so no tick reads it and the lane rule cannot be judged. | fixed: merge-lane-design.md, Lair pull request (the lane-holder set), State and ownership, Failure modes (Failed lane read), Seam order (#608) and Verification strategy |
| M2-B4 | medium | The git hardening misses replace objects, grafts, alternates, the submodule diff setting and inherited `GIT_*` variables, and the design says its hardening does not rely on the #630 assumption. | fixed: merge-lane-design.md, Git and tool reads, Auto-tier script, Assumptions about #630, Trust boundaries (Residual: a strain that writes the tick's inputs), Failure modes (Changed git repository) and Verification strategy |
| M2-B5 | medium | A fix-up run can build on another account's push and record it as its head, so ADR-0044's unreviewed-push residual returns through fix-up heads. | fixed: merge-lane-design.md, Assumptions about #630 (Leased pushes) and Trust boundaries (The pinned head); ADR-0044, Amendment 2026-11-21, the third Consequences bullet (R18) |
| M2-B6 | medium | This repository's protected-path list is not specified, so a Lair pull request can change the Lair, the merge script, the hooks, the manifest, the validators or the policy pins in the auto tier. | fixed: merge-lane-design.md, Auto-tier script (This repository's list) and Verification strategy (R19) |
| M2-B7 | medium | Tests miss the git and tool hardening rules, settings type failures, killed poll, git and `gh` reads, the `.gitmodules` floor name and malformed `version_files` entries; the hook case is vacuous. | fixed: merge-lane-design.md, Verification strategy |
| M2-B8 | low | The merge-pending flag lives with the seed, so a settle reset clears it and a second merge call can run for a queued head. | fixed: merge-lane-design.md, Settle check (The merge-pending mark), Merge-lane step of the tick (step 8), State and ownership, Routing table, Failure modes and Verification strategy |
| M2-B9 | low | Step 2 reads the pull request before the issue, so a merge that closes the issue can be routed as a claim withdrawal. | fixed: merge-lane-design.md, Merge-lane step of the tick (steps 2 and 15) and Verification strategy |
| M2-B10 | low | A fix-up run that ends after its claim has ended still writes labels, a review marker and a breaker count. | fixed: merge-lane-design.md, Run outcome to labels, Lifecycle "Stage 4: halt and circuit breaker" and Failure modes |
| M2-B11 | low | Once the merge queue holds a pull request, unsetting `HIVEMIND_AUTO_MERGE` or a later review marker does not take it out. | recorded: merge-lane-design.md, Trust boundaries (Residual: a queued merge) and Lifecycle "Stage 4: halt and circuit breaker" (R20) |
| M2-B12 | low | A path with a non-ASCII byte or a segment ending in `.` or a space, the exact path `.github`, or a prefix entry's exact path escapes protected-path matching. | fixed: merge-lane-design.md, Auto-tier script (the list forms and the floor) and Verification strategy |
| M2-B13 | low | One merge call per tick in a fixed order lets a pull request that always waits at the merge call starve the others. | fixed: merge-lane-design.md, Merge-lane step of the tick (lane order), State and ownership and Verification strategy |
| M2-B14 | low | The fixed `PATH` puts `/usr/bin:/bin` before the resolved tool directories, and nothing checks that a tool name resolves to its resolved path. | fixed: merge-lane-design.md, Git and tool reads, Failure modes (Shadowed tool at start) and Verification strategy |
| M2-B15 | low | The same gap as M2-A9's waiting CI-red rule: under a halt, a red pull request has no stated path to the review wait. | fixed: merge-lane-design.md, as for M2-A9 |

## Sources

- The [parent review record](review-record.md), round 3, for the findings above and the split to #631.
- The [PRD](../../prds/autonomous-ready-issue-loop.md).
- [ADR-0045](../../adr/0045-lair-software-factory.md), with its amendment "Lair admission excludes epics and requires a passing readiness check".
- [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md), with its amendment of 2026-11-21, "the Lair controller runs the merge script (issue 631)", decisions 17 to 20.
- The [solution design](solution-design.md).
- Trunk commit `9cb44f94dc430a66a57383f9d26e7d6486d3ea14`, the base the design's Context and code truth section was read from.
- Round 1: merge-lane-design.md at blob `0177e805e2d91d69f12c5d64a62121d4fd8ef944`, read directly by the two passes. The round-1 finding text above is as supplied in the remediation brief.
- Round 2: merge-lane-design.md at blob `6e59293f79881ef118e7b86baaebcf3d8f204be9`, read directly by the two passes. The round-2 finding text above is abridged from the remediation brief.

## Decisions taken (listed for veto)

The calls of the design, each also listed under its Decided for you or Decisions section:

- The review marker is authoritative and final; the Lair never merges a pull request that has one, even if the label is removed.
- Markers go on the claimed issue, never the pull request.
- The review wait is 3600 seconds, the watch's `max_watch_duration` default in `SKILL.md` (recorded in ADR-0029's Findings), measured from the recording run's `ended_at`.
- The routing rows: no checks, conflicts, a blocked merge and a refused merge go to batch review; a script error, malformed output, a killed merge run and `merge-pending` wait, bounded by the review wait; `skipped:bad-setting` is handled like `off`.
- The head check goes first in `merge-approved.sh`, before gate 1.
- The merge call pins only the head, and every input it does not pin is one class of known limit: each merge condition is exactly one of five kinds (pinned, derived from git objects, judged by `merge-approved.sh` on its own read, read by the tick in the late group, and Lair-owned state). The seconds between the late group's reads and the merge call are the merge gap; a finding that names a late-group input changing in that gap is a repeat. It extends ADR-0044 decision 15 by analogy and changes nothing in ADR-0044.
- The late group is the last tick work before the merge call, in this order: the merge settings, the credential login, the trunk tip, the identity, the issue (its state, `lair:claimed` and text) and the settle check, then the merge call and nothing else. The Lair pull request checks are one function, called when a result is recorded and again in the late group, which leaves out the head because the merge call pins it.
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
- The solution-design.md Amendments pointer, the parent record's round-3 dispositions, the CONTEXT.md "Lair Pull Request" term and the `decision-autonomy.md` Tier A merge bullet are recorded under the design's Changes to shared documents, listed for veto and not applied. The PRD Out of Scope bullet and the ADR-0045 status line are recorded there too and not applied, but are not listed for veto: they derive from Tier A answers Q1 and Q3 (R21).
- #605 fixes the Lair's script directory, `plugin/skills/lair/scripts/`; the fix-up, halt and breaker test cases are added by the slices that build them (M1-A8).
- Every tick read fails closed: a failed or incomplete read means no merge and no label change that tick, and only the review wait may still route, from the markers (M1-B3).
- A resetting settle result deletes the seed before the new snapshot, and only exactly one known line with exit 0 counts, for the poll and the auto tier alike (M1-B4, M1-B5).
- A fix-up run is supervised from its markers: the start marker goes first, a failed write launches nothing, the stall window runs from `started_at` and the budget from `claimed_at` (R15), and a lost run with no unprocessed result gets an end marker with outcome `crashed` (M1-B6).
- The write order is marker, then labels, then an applied marker, each write idempotent and finished on later ticks, with no second review marker for a pull request under one claim (M1-B7).
- A Lair pull request needs a live claim, an open issue and `lair:claimed`; a closed issue or a removed `lair:claimed` is the claim-withdrawn exit, and the closed-unmerged exit also writes a review marker (M1-B8).
- The protected-path floor is the root `.github/` directory and the exact path `.github`, any `.claude` path segment, any file named `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.gitmodules` or `.gitattributes` at any depth, and any path with a byte other than printable ASCII or a segment ending in `.` or a space, with ASCII case ignored; the list gains the `**/<name>` form, and a prefix entry also matches its exact path (M1-B11, M2-B12).
- `.github/lair.json` has a strict schema, and `[]` is the only way to declare no entries (M1-B12).
- The tick reads only the two named settings files, and the queue report names the files read (M1-B15).
- The late group rereads the issue's state and `lair:claimed`; a withdrawal it sees makes no merge call and is routed by the next tick's step 2 (M2-A1, M2-B1).
- Step 2 reads the issue before the pull request and routes a merge first (M2-B9).
- A waiting CI-red rule and a merge-pending mark each run only the review wait, then stop (M2-A9, M2-B15).
- Results are kept in the Lair cache until their marker is written; a failed result-check read retries on later ticks, bounded by the issue's budget, and only a check that reads and fails makes a result invalid (M2-B2).
- The lane-holder set, kept by #608, holds every recorded pull request whose claim ended while it is open, and admission fails closed on any failed read of it (M2-B3).
- The Lair's git repository is checked each tick and rebuilt on any change it did not write, and every git call drops the environment's `GIT_*` variables and sets `GIT_NO_REPLACE_OBJECTS=1` and `diff.ignoreSubmodules=none` (M2-B4).
- The merge-pending mark is kept apart from the seed, never cleared by a settle reset, checked at step 8, and cleared only on a `MERGED` or `CLOSED` state read or a new pinned head (M2-B8).
- A fix-up run that ends under an ended claim writes only its end marker (M2-B10).
- The lane order rotates: the pull request whose merge call ran last goes to the end of the next tick's order (M2-B13).
- The tick's `PATH` puts the resolved tool directories first, and the Lair refuses to start when `command -v` of a tool under it differs from its resolved path (M2-B14).

The calls of this run:

- This record reuses the parent record's keys and disposition vocabulary.
- Only merge-lane-design.md is stamped. ADR-0044 is amended by this run but reviewed, not stamped, like the other sources.
- A3-11, A3-12 and B3-20 are owned only in part; their other parts stay open in the parent record.
- Every owned round-3 finding is dispositioned `fixed` by the design as written; the review rounds confirm or reopen each one. Where a round-1 or round-2 finding showed a fix held only in part, the disposition stays `fixed` and names the findings that completed it. Round 2 reverted one round-1 fix, M1-B9, for compliance with ADR-0045 decision 13, and its disposition became `recorded`.
- The seams with #630 and #632 are stated as assumptions in the design, and their files are not created.
- Local review returned a root-cluster finding on the merge-lane tick's unpinned inputs. Root cause: the tick judged its merge conditions on its own reads, in a step list that grew one check per review round, while the merge call pins only the head, and the design never said which inputs the call can cover and which it never can. Class fix: every merge condition is keyed to one of five kinds by who reads it relative to the merge call, the tick's reads run in one late group with only the merge call after it, and the Lair pull request checks are one function used at recording and in the late group. The residual merge gap is recorded once as a class in merge-lane-design.md, Merge-lane step of the tick (Known limit) and Trust boundaries. Linked findings: `6cae4d438fcbd73fb76c1487beac991a3f98ae859ad5079fc9455024a74a23ed`, `b81db886da79ea26f3ece2cccdac1982ba7c77d628fc10391a295e0e7a20a4d2`, `ff9090699d221fd738ca76ed6b8d479146ba249d1eeb623d09eb7003d2ce1b41` and `bf472704b77555a397febc7472498d3c3e9e4d789170f336accca5151bef9024`. ADR-0044 is unchanged by this fix.

The calls on the review rounds' open choices, each dated 2026-11-21 and decided by the run, and each also listed under the design's Decided for you:

- **R1** (M1-A3): a fix-up run's `decision` and `fact` parks are answerable on the issue and count toward the third-park handoff, under ADR-0045 decision 7. #609 handles them as a delivery run's park; the Lair first converts the pull request to a draft, so it belongs to its parked issue and does not hold the lane. The contrary text and the "no ADR-0045 change" claim are corrected.
- **R2** (M1-A4): the review-finding fix-up cap, `fixup-cap`, is dropped. What starts a fix-up run on review findings stays with #610, per ADR-0045 decision 13 and the PRD's Post-PR feedback criterion. The unbounded review loop is a seam note for #610, not a merge-lane rule.
- **R3** (M1-A5): `lair:review` goes on both the issue (PRD Labels and Admission) and the pull request (ADR-0045 decision 12).
- **R4** (M1-B1): the #630 assumption is the property that no strain process can write what the tick reads or runs: the two user settings files, the Lair cache directory, the main checkout's git common directory (config, hooks, refs), the `PATH` directories and the plugin script directory. A worktree strain must write objects and refs, so hooks and config need a carve-out or a per-strain clone, which is #630's choice. The tick hardens itself as well: a Lair-owned bare repository, hooks and system and global config off, a fixed URL, the trunk id from this tick's `ls-remote`, and tools by absolute path. Round 2 added the per-tick repository check, `GIT_NO_REPLACE_OBJECTS=1`, `diff.ignoreSubmodules=none`, the removal of inherited `GIT_*` variables and the start-time `PATH` check (M2-B4, M2-B14), and dropped the claim that this hardening does not rely on the assumption. The residuals are ADR-0045's prompt-injected strain, with its merge-lane consequences listed, and a strain that writes the tick's inputs; the Lair pull request checks are not called a bound against a strain that reports values.
- **R5** (M1-B2): an explicit #632 assumption that a process holding the user's GitHub credentials, the claim nonce and the run nonce cannot produce a marker that passes #632's rule; otherwise marker forgery is a named residual. The design's pinned-head line and ADR-0044's amendment consequence are conditional on it.
- **R6** (M1-A2, M1-B10): the merge script and the settle check run in the Lair's own environment minus every `HIVEMIND_*` key, plus the keys read from the two settings files, so merge settings never come from the environment (Q4). Before every merge call, `gh api user` in that environment must report the Lair's own login; a mismatch is no merge with the reason `credential-mismatch`. The "authenticates as the Lair does" claim is dropped, and a test is added.
- **R7** (M1-B13, M1-A14): the CI-red rule fires from the tick's own rollup read on the pinned head or `MERGE=wait:checks-failed`, whatever the merge settings, the approval and the gate order. Q9's one fix-up run, then batch review, is unchanged. Corrected in round 2 (R17): the settle check's `CI_FAILED` only means not settled.
- **R8** (M1-A6): `pr`, `branch`, `head` and `local_review_head` move out of the claim marker into a run-end marker the merge lane owns. The lane reads `claim_nonce`, `claimed_at` and `body_sha256` from #632's claim marker and assumes only #632's author and nonce rule applies to its own markers too.
- **R9** (M1-B17): at most one merge call per tick, and the trunk tip is re-resolved in the late group, with the auto tier run again when it moved.
- **R10** (M1-B16): every merge-lane child process runs under a 300-second timeout; a killed merge run routes as `MERGE_ERROR`, and the next tick's state read decides whether it merged.
- **R11** (M1-A9): the empty-string merge keys in strain settings are #630's pending ADR-0045 and PRD change (A3-1), not this design's; the design claims only that its own decisions reverse no ADR-0045 decision (narrowed in round 2, M2-A10).
- **R12** (M1-A1): #605 changes the Tier A merge bullet of `plugin/governance/decision-autonomy.md` to name the Lair tick's merge under ADR-0044 decision 17, updates `tests/policy/safety-auto-merge-after-approval.json`, and adds a structural check. The bullet text is recorded under Changes to shared documents and not applied.
- **R14** (M2-A3): the breaker counts only `failed`, `crashed`, `stalled` and `timed-out`, the outcomes ADR-0045 decision 17, the PRD's Stop controls criterion and solution-design.md name. Delivery `blocked`, `no-pr` and `invalid-result`, fix-up `blocked` and invalid results, and any fix-up end under an ended claim neither add to the count nor reset it; a `complete` run end under a live claim resets it. The design's claim about ADR-0045 is corrected to match.
- **R15** (M2-A4): the wall-clock budget is per issue, measured from the claim marker's `claimed_at`, and a fix-up run runs on what is left of it (the PRD's Budgets and recovery criterion, ADR-0045 decision 17). Fix-up outcomes: `complete` with checks passing records the head; `parked` is #609's park; `failed`, `blocked` and an invalid result go to batch review with reason `fixup-failed`; `crashed`, `stalled` and `timed-out` give `lair:failed` and end the claim. With no budget left no fix-up run starts, and the pull request goes to batch review with reason `budget-exhausted`, a tick route and not a run outcome. The stall window runs from the start marker's `started_at`. The round-1 rules for the start marker and the `crashed` end marker stand, but a `crashed` fix-up run now gives `lair:failed`, like `stalled` and `timed-out`, where round 1 sent it to batch review.
- **R16** (M2-A5): a review marker does not stop a fix-up run (ADR-0045 decision 13, the PRD's Post-PR feedback criterion); the round-1 fix of M1-B9 is reverted. The design sets preconditions on #610's trigger only where a binding source allows: a live claim, no run in flight, a fresh head equal to the pinned head, budget left, and no halt or tripped breaker. Fix-up runs pushing while the user reviews is a recorded residual.
- **R17** (M2-A6): the settle check's `CI_FAILED` is not a CI-red signal; CI-red comes from step 7's rollup read on the pinned head and from `MERGE=wait:checks-failed`. A fix-up run starts only when a fresh GitHub read of the pull request's head equals the pinned head. R7's wording is corrected.
- **R18** (M2-B5): every strain push is leased (an assumption about #630): a fix-up run's against its `start_head`, then its own last push, so a push by another process makes the run's next push fail, no head built on it is recorded, and a failed fix-up run goes to batch review with reason `fixup-failed`. ADR-0044's amendment, its third Consequences bullet, and the design's pinned-head trust bullet are conditional on it; without it, ADR-0044's residual "An unreviewed push by another account can merge" applies through fix-up heads.
- **R19** (M2-B6): this repository's `.github/lair.json` must protect `plugin/skills/lair/`, `plugin/skills/github-review-loop/scripts/`, `plugin/hooks/`, `plugin/.claude-plugin/`, `tools/` and `tests/policy/`, a requirement on #605's list, with a test that the committed list holds them.
- **R20** (M2-B11): a pull request GitHub's merge queue already holds is not taken out of it when `HIVEMIND_AUTO_MERGE` is unset or a review marker is written later; no dequeue write is added, and the case is a named residual.
- **R21** (M2-A10, M2-A11): the PRD Out of Scope change (Changes to shared documents, item 6) and the ADR-0045 status-line change (item 7) derive from Tier A answers Q1 and Q3, so each carries an Answer line citing them and neither is listed for veto. R13, the round-1 call that listed item 6 for veto, is withdrawn.

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
