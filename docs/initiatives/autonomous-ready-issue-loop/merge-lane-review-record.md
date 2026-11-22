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

# Design review record: Lair merge lane

This record covers the design review of the Lair's merge lane, issue #631: the [merge-lane design](merge-lane-design.md). Only merge-lane-design.md is stamped. Its stamp's blob is `git rev-parse HEAD:docs/initiatives/autonomous-ready-issue-loop/merge-lane-design.md`, and the stamp is written last, after every other change to this record. The [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md), [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md) and the [solution design](solution-design.md) are reviewed, not stamped.

The review exits only when zero critical or high findings are open and one round raises no new findings. It runs at most 3 rounds.

Each round runs two passes in parallel. Each pass is a fresh, read-only `hivemind:cerebrate` analysis delegation with "Memory context: none":

- **Pass A:** code truth, governance and ADR conflicts, and existing-path coverage.
- **Pass B:** failure modes, trust and injection, and testability.

New finding IDs take the `M` prefix, then the round, the pass and the finding number: `M1-A2` is round 1, pass A, finding 2. No round has run yet.

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
| A3-2 | high | The tick runs `merge-approved.sh` outside the watch, dropping ADR-0044's settled-approval precondition, and the failure-mode row maps the script's results wrongly. | B3-5, B3-6 | fixed: merge-lane-design.md, Settle check, Routing table and Failure modes, under ADR-0044 decisions 17, 18 and 20 |
| A3-3 | high | The controller has no defined source for the merge settings it reads each tick, so unsetting auto-merge may never stop merges. | B3-7 | fixed: merge-lane-design.md, Merge settings source and Lifecycle "Stage 4: halt and circuit breaker" |
| B3-4 | high | Strain result fields (`pr`, `branch`, `head`) are trusted unchecked, and "Lair PR" is undefined. | | fixed: merge-lane-design.md, Lair pull request and Pinned head |
| B3-5 | high | The tick's merge drops ADR-0044's settle period and does not tie the auto tier to the merged head. | A3-2 | fixed: merge-lane-design.md, Settle check, Pinned head and Expected-head argument |
| B3-6 | high | The merge-result failure-mode row maps `merge-approved.sh` results wrongly. | A3-2 | fixed: merge-lane-design.md, Routing table and Failure modes |
| B3-7 | high | No defined source for merge settings in the tick. | A3-3 | fixed: merge-lane-design.md, Merge settings source |
| B3-8 | high | Auto-tier inputs (protected-path list, local-review-skipped evidence, bump type) are undefined or untrusted. | A3-10 | fixed: merge-lane-design.md, Auto-tier script and Trust boundaries |
| A3-10 | medium | Auto-tier inputs have no named source, and two can be forged by the strain. | B3-8 | fixed: merge-lane-design.md, Auto-tier script and Trust boundaries |
| A3-8 | medium | Draft-PR and closed-unmerged states have no lifecycle exit. | | fixed: merge-lane-design.md, Exits (Draft, Closed unmerged) |
| B3-13 | medium | The run outcome to label mapping is incomplete (blocked, complete with no PR, invalid result). | | fixed: merge-lane-design.md, Run outcome to labels |
| B3-14 | medium | Remediation strains leave no GitHub record, their parks have no path, and the halt does not cover them. | | fixed: merge-lane-design.md, Fix-up runs, Markers the merge lane writes, Run outcome to labels and Lifecycle "Stage 4: halt and circuit breaker" |
| A3-13 | low | It is unclear whether `lair:review` goes on the issue or the pull request. | | fixed: merge-lane-design.md, Exits (Batch review: on the pull request, never the issue) and State and ownership |
| A3-12 | medium | This scope's part: the no-merge-after-edit and CI-red calls should have been asked, and this scope's calls were not listed for veto. The session-scoped breaker call is not in this scope. | | fixed: merge-lane-design.md, Tier A answers (Q8, Q9) and Decided for you |
| B3-20 | low | This scope's part: the merge-lane tests and their `tools/validate.sh` registration. The overlord prose, injection and halt tests and the halt file path are not in this scope. | | fixed: merge-lane-design.md, Verification strategy |
| A3-11 | medium | This scope's part: the Seam order ADR lists for the slices the merge lane changes. | | fixed: merge-lane-design.md, Seam order |

## Sources

- The [parent review record](review-record.md), round 3, for the findings above and the split to #631.
- The [PRD](../../prds/autonomous-ready-issue-loop.md).
- [ADR-0045](../../adr/0045-lair-software-factory.md), with its amendment "Lair admission excludes epics and requires a passing readiness check".
- [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md), with its amendment of 2026-11-21, "the Lair controller runs the merge script (issue 631)", decisions 17 to 20.
- The [solution design](solution-design.md).
- Trunk commit `9cb44f94dc430a66a57383f9d26e7d6486d3ea14`, the base the design's Context and code truth section was read from.

## Decisions taken (listed for veto)

The calls of the design, each also listed under its Decided for you or Decisions section:

- The review marker is authoritative and final; the Lair never merges a pull request that has one, even if the label is removed.
- Markers go on the claimed issue, never the pull request.
- The review wait is 3600 seconds, the watch's `max_watch_duration` default, measured from the recording run's `ended_at`.
- The routing rows: no checks, conflicts, a blocked merge and a refused merge go to batch review; a script error, malformed output and `merge-pending` wait, bounded by the review wait; `skipped:bad-setting` is handled like `off`.
- `merge-pending` makes no second merge call for the same head while the cache marks it.
- The head check goes first in `merge-approved.sh`, before gate 1.
- `HIVEMIND_PR_REVIEWERS` comes from the same two user settings files as the merge keys, and the reviewer filter is `automated`.
- The clean environment holds `PATH`, `HOME`, the `gh` auth variables when set, and the three merge keys.
- The settle snapshots use the `re-arm` arm kind and are keyed by pull request and pinned head.
- The trunk file is `.github/lair.json`, with `protected_paths` (exact paths or directory prefixes, no globs) and `version_files`; a missing or unparseable file sends every pull request to batch review.
- The protected-path floor is `.github/`, `.claude/`, `CLAUDE.md`, `.mcp.json`, `.gitmodules` and `.gitattributes`.
- A major bump is a rise in the major component of any declared version file; a missing, unparseable or lower value goes to batch review.
- A fix-up head counts as reviewed only when the claim's local-review head is not null.
- A fix-up head is recorded only when the previous recorded head is its ancestor.
- The outcome mapping: `blocked`, `no-pr` and an invalid result give `lair:failed` and count toward the breaker; a pull request closed unmerged gives `lair:handoff` and does not count.
- A complete run's draft pull request goes to batch review with reason `draft` and does not hold the lane.
- A fix-up park goes to batch review; it is not answerable, not a `readiness:needs-decision` move, and not counted toward the third-park handoff.
- The review-finding fix-up cap is the `loop-state.sh floor` value per pull request.
- The test layout and suite names under Verification strategy.
- No ADR-0045 change is needed; the design fills in ADR-0045 decisions 12, 13 and 17 and reverses none of them.
- The solution-design.md Amendments pointer, the parent record's round-3 dispositions and the CONTEXT.md "Lair Pull Request" term are recorded under the design's Changes to shared documents and not applied.

The calls of this run:

- This record reuses the parent record's keys and disposition vocabulary.
- Only merge-lane-design.md is stamped. ADR-0044 is amended by this run but reviewed, not stamped, like the other sources.
- A3-11, A3-12 and B3-20 are owned only in part; their other parts stay open in the parent record.
- Every owned round-3 finding is dispositioned `fixed` by the design as written; the review rounds confirm or reopen each one.
- The seams with #630 and #632 are stated as assumptions in the design, and their files are not created.

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
