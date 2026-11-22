---
stamps:
  - path: docs/prds/idea-to-ready.md
    blob: a8d9fd9fb30ee65a19d5a11c1902178bd77f5899
  - path: docs/initiatives/idea-to-ready/solution-design.md
    blob: 6d7ada4576c641e116268d9ad0f8eb9f54c05e52
  - path: docs/adr/0046-idea-to-ready-process.md
    blob: 3e3a5c191758ce1425a5627c108c3c57429be290
verdict: fail
open:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 3
clean_round: false
---

# Design review record: Idea to Ready

The first review, rounds 1 to 4, did not converge. After round 4 the user split the council out into its own initiative, #638 (answers Q12 A and Q14 B), and approved the narrowing of ADR-0037 decision 16 (answer Q13 A).

For a fresh re-review under Re-review and re-stamp of the solution design, the front matter was reset (`verdict`, `rounds`, the open counts and `clean_round`) and the stamps kept. The re-review starts at round 1 and covers the whole documents, because no record of this initiative has passed. The first review's Rounds and Findings are kept under History below.

The stamps are the blobs at commit `92c9981f905531d8f4ba20040baf0cab2b855916`, the pull request head round 1 reviewed, read with `git rev-parse <commit>:<path>`, and equal those of commit `6fe5e03342397d06be7f722878ccc4e8fd755184`. Under the stamp rule of Review record front matter, a record with `verdict` `fail` keeps its stamps, and only the passing record re-stamps, to the commit its clean pass reviewed. Any later edit to a stamped file makes this record stale until a review of the change re-stamps it. The pull request stays a draft until the re-review passes. The design review skill's verify does not exist yet (#619), so this record is checked by hand.

## Reviewed documents

- [PRD: Idea to Ready](../../prds/idea-to-ready.md)
- [Solution design: Idea to Ready](solution-design.md)
- [ADR-0046](../../adr/0046-idea-to-ready-process.md): the idea-to-ready process

The council ADR drafted in this pull request was withdrawn to #638. The [glossary](../../../CONTEXT.md) edits were reviewed but are not stamped.

## Rounds

From round 2, by the user's instruction after round 1:

- Each round runs one `hivemind:cerebrate` pass covering both angles, A (code truth, governance and ADR conflicts, existing-path coverage) and B (failure modes, trust and injection, testability), delegated with effort high. Two parallel passes no longer run.
- When the design touches trust, credentials or the merge path and a local review tool is configured (`HIVEMIND_LOCAL_REVIEWER`, or the `codex-plugin` default when the Codex plugin is installed), one more pass runs through that tool via `run-review.sh`. When none is configured, that pass is skipped and the skip is recorded in this record.
- The confirming round reviews only the diff since the previous round and the fixes to open findings, with effort medium.

#640, #641 and #643, merged from main after round 2, set this procedure in the PRD, so the PRD and this note now agree. The PRD names no effort level.

This design touches trust and the merge path. `HIVEMIND_LOCAL_REVIEWER` is unset and the Codex plugin is installed, so the `codex-plugin` default runs the extra pass.

### Round 1

Two parallel passes. Each was fresh and read-only, ran with `Memory context: none`, and neither reviewer wrote the design. Both reviewed commit `92c9981f905531d8f4ba20040baf0cab2b855916`.

- Angle A: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Code truth, governance and ADR conflicts, existing-path coverage.
- Angle B: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Failure modes, trust and injection, testability.

The round raised 15 findings, RR1A1 to RR1A6 and RR1B1 to RR1B9. RR1B1 is high. After the round the user answered Q18 A and Q19 A and accepted the remediation plan (Q20 A). Round 2, a confirming round, follows.

### Round 2

The confirming round. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), effort medium. One fresh, read-only pass with `Memory context: none`, covering both angles, A and B, over the change since round 1 and the fixes to its findings. It reviewed commit `20169518422a183c3735c5ca3ccd61ddc507a9f6`.
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh` against base `92c9981f905531d8f4ba20040baf0cab2b855916`. The tool names no model (ADR-0042 decision 7). Its verdict was needs-attention, with one high finding.

The cerebrate pass confirmed all 15 round-1 findings fixed. The round raised 4 new findings, RR2-C1 (high, from the tool pass), RR2-1, RR2-2 and RR2-3, so it is not clean.

After the round the branch merged main at `5881e389`, bringing in #628, #640, #641, #642 and #643. #642 added principle P26, which drove a consumer-portability sweep of the design: CI, `tools/validate.sh`, the Codex plugin and Fable are each optional, with a stated fallback. The user answered the merge check question (Q21 A) and accepted the remediation plan (Q22 A).

Round 3, the confirming round and the last under the three-round cap, follows. It reviews the diff since `20169518`, which includes the merge of main, and the fixes to round 2's findings.

### Round 3

The confirming round and the last under the three-round cap. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), effort medium. One fresh, read-only pass with `Memory context: none`, covering every angle, over the change since round 2's reviewed commit `20169518422a183c3735c5ca3ccd61ddc507a9f6`, which includes the merge of main, and the fixes to round 2's findings. It reviewed commit `5d2cf651544c4a7c5105d0a3cdcf98ddb91f5650`.
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh` against base `20169518422a183c3735c5ca3ccd61ddc507a9f6`. The tool names no model (ADR-0042 decision 7). Its verdict was needs-attention, with one high finding.

The cerebrate pass confirmed all four round-2 findings fixed: RR2-C1, RR2-1, RR2-2 and RR2-3. The round raised 5 new findings, RR3-C1 (high, from the tool pass) and RR3-1 to RR3-4. RR3-1 is a duplicate of RR3-C1. So the round is not clean, and the review has not converged under the three-round cap.

After the round the user answered Q23 A: fix every round-3 finding, broaden the ADR-0044 narrowing in the merge check of D28, and run round 4 of the re-review as a one-time confirming round (D34). The user also answered Q24 A: the round-3 remediation plan is accepted, with `merge-approved.sh` fetching the head and base from origin with git, and merge mode refusing a stamp path the base changed after the merge-base.

Round 4, the D34 confirming round, follows. It reviews the diff since `5d2cf651` and the fixes to round 3's findings, covering every angle with the local review tool pass. It does not change `rounds`, as D31's round 4 did not (answer Q11 A). If it raises any new critical or high finding, the merge enforcement moves out to #619's own design, and the design narrows its claim to the guide's draft rule and the readiness check.

### Round 4

The D34 confirming round. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), effort medium. One fresh, read-only pass with `Memory context: none`, covering every angle, over the change since round 3's reviewed commit `5d2cf651544c4a7c5105d0a3cdcf98ddb91f5650` and the fixes to round 3's findings. It reviewed commit `94156faf9286efac684a5e468efd129f39688996`.
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh` against base `5d2cf651544c4a7c5105d0a3cdcf98ddb91f5650`. The tool names no model (ADR-0042 decision 7). Its verdict was needs-attention, with one high finding.

The cerebrate pass confirmed all five round-3 findings fixed: RR3-C1 and RR3-1 to RR3-4. The round raised 4 new findings, RR4-C1 (high, from the tool pass) and RR4-1 to RR4-3, so it is not clean. It does not change `rounds` (answer Q11 A).

After the round the user answered Q25 A: as D34 set, merge-time enforcement on the plugin's merge paths leaves this design and is #619's own design question, with RR4-C1 and RR4-1 to RR4-3 as its input, superseding the merge-check parts of Q21 A, Q23 A and Q24 A. The guarantee narrows to the guide's draft rule and the readiness check (D28). The user also judged the remaining findings to be diminishing returns and directed that the design review check for diminishing returns after every round and raise it unprompted (D35).

A final confirming round over the narrowing change follows. It reviews the diff since `94156faf` and does not change `rounds`. If it is clean, the record step re-stamps to the commit that round reviewed and sets `verdict` `pass` and `clean_round` `true`.

Diminishing-returns advisory: raised by the maintainer after round 4 (before D35 existed); signals: recurrence on the merge-check surface across rounds 2 to 4, severity trending to edge cases bounded by the readiness check; answer Q25 A (narrow and move merge-time enforcement to #619).

## Findings

| ID | Round | Angle | Severity | Disposition | Note |
|---|---|---|---|---|---|
| RR1A1 | 1 | A | medium | fixed | D9 replaced the Promotion Gate's architectural clause with no recorded amendment. ADR-0046 records narrowing ADR-0026 decision 3 for design-stage decisions only, and D9 and D32 cite it (asked in re-review round 1, answer Q18 A). |
| RR1A2 | 1 | A | medium | fixed | A guide-launched run that failed or ended blocked would continue on Instinct. It returns to the guide, which re-derives the stage, told by the request's marker line. This narrows ADR-0039 decision 4 for guide-launched runs (asked in re-review round 1, answer Q19 A; D33). |
| RR1A3 | 1 | A | medium | fixed | The record-commit residual listed exactly four routes, but more exist. Its scope is every commit route outside `runCommitStep` (Residuals, Trust boundaries, D28, Context and code truth; within answer Q15 A). |
| RR1A4 | 1 | A | low | fixed | Existing-path coverage lacked rows for the budget file, the README skills table, `workers.js`, `facts.js`, `pr.js`, `title.js`, `overlord.md` `## Engine`, `merge-approved.sh` and the PRD. They are added. |
| RR1A5 | 1 | A | low | fixed | Seam order lacked headings for #619, #621 and #622. They are added. |
| RR1A6 | 1 | A | low | fixed | #616 and #619 planned no consumer-assertion fixture (P3). Verification strategy plans one each, and the `safety-review-calls.json` pins survive #616's cut. |
| RR1B1 | 1 | B | high | fixed | Stamps recorded the head when the record was written, not the content the clean pass reviewed. Each stamp is now the blob at the pull request head commit the guide recorded before the pass, a clean round raises no new finding and finds no earlier finding unfixed, and verify's stamp equality at the head fails any change after the clean pass (Review record front matter, Design review rounds). |
| RR1B2 | 1 | B | medium | fixed | The re-stamp rules contradicted each other. One stamp rule: the first record stamps the commit round 1 reviewed, a fail record keeps its stamps, only the passing record re-stamps, and a reset keeps the stamps. |
| RR1B3 | 1 | B | medium | fixed | The post-apply re-check failed never-triaged issues on `rating_missing:readiness`. Its overlay holds exactly `readiness:ready` (Triage readiness gate). |
| RR1B4 | 1 | B | medium | fixed | Review findings reached a writing drone through an unscanned request. Guide runs take a fixed request, review text arrives only through the docs pull request number as a scanned launch reference, and pass findings only in a data block (Guide skill, Trust boundaries). |
| RR1B5 | 1 | B | medium | fixed | Duplicate of RR1A2, fixed by the same change. |
| RR1B6 | 1 | B | low | fixed | CRLF bodies broke parsing. The ending carriage return of every line is removed first (Document parsing rules). |
| RR1B7 | 1 | B | low | fixed | #621's paged reads had no truncation rule. Any `pageInfo.hasNextPage` fails with no stage (Stage derivation and handoff check). |
| RR1B8 | 1 | B | low | fixed | Verify did not check destinations. A deferred Note needs a `#<n>` issue reference and a recorded Note a repository path (Review record body). |
| RR1B9 | 1 | B | low | fixed | The end condition "asked until #638 ships" could not be evaluated. A weak or absent recommendation is asked, and #638 may change that only by its own ADR (ADR-0046, Design-decision rule, D32, PRD Further Notes). |
| RR2-C1 | 2 | review | high | fixed | Local review tool pass, finding_id `2b482094fd606613bd5ffb179042cd21786865347cf098217baa4555ff2d33f2`: design review findings entered a guide run's request in a data block, outside the pass scan (SD-06), so quoted hostile text or a fence could reach the run's instruction channel. The data block is removed, and no review text enters the request. The guide posts each round's findings as comments on the docs pull request, the run's one launch reference, so gather-facts carries them under the pass scan (Guide skill, Trust boundaries, ADR-0046 decision 10). |
| RR2-1 | 2 | confirm | medium | fixed | The keep-stamps rule conflicted with ADR inclusion: a failing record stamped before an ADR was added could not include it. Stamp equality and ADR inclusion are checked only on a record whose verdict is pass, which re-stamps at its clean pass and includes every added or edited ADR (Review record front matter, Review record body, D28, ADR-0046 decision 7). |
| RR2-2 | 2 | confirm | medium | fixed | The guide request's layout was unfixed, and the overlord's reading of the Docs pull request line was ambiguous. Line 1 is the marker, line 2 is exactly `Docs pull request: #<n>` or `Docs pull request: none`, and the overlord reads references only from line 2. No issue number becomes a launch reference, and a reused pull request's body never gains a Closes line (Guide skill, D33). |
| RR2-3 | 2 | confirm | low | fixed | A recorded Note's repository path and a deferred Note's issue reference were undefined. A repository path is a link target read from the record's folder or a code span read from the repository root, naming a file present at the pull request head; `#<n>` is checked by shape only, with no gh call (Review record body). |
| RR3-C1 | 3 | review | high | fixed | Local review tool pass, finding_id `5ed27523bb1f947af88dc5e43b544cee991e387104aaf616a15a9cf447499048`: merge mode examined only the records the pull request adds or edits and checked only verdict and open counts, so a push that edits a stamped document without editing the record, or a record with stale stamps under unchanged pass metadata, could merge content no pass reviewed. Merge mode now applies a record for every changed PRD, solution design, ADR and record and runs every check, stamp equality, base drift and the pass rule included, at the head a merge path would merge, refusing a changed initiative folder with no record, and the overclaims are scoped (Review record body, Trust boundaries, Failure modes, D28, ADR-0046 decision 7). Merge mode later left this design (answer Q25 A). |
| RR3-1 | 3 | confirm | medium | fixed | Duplicate of RR3-C1, fixed by the same change. |
| RR3-2 | 3 | confirm | medium | fixed | `merge-approved.sh` is gh-only, with no git call and one stdout line per run, so merge mode had no head or base objects. #619 fetches the pull request head and base branch from origin, runs merge mode at the gated head, captures its lines, and prints `MERGE=skipped:record-blocked` or `MERGE=skipped:record-unread`, never merging a pull request whose changed paths it cannot read (Context and code truth, Review record body, Existing-path coverage, Verification strategy). Merge mode later left this design (answer Q25 A). |
| RR3-3 | 3 | confirm | medium | fixed | Review record body said every other passing record gets stamp equality only, missing the delivered exclusion. Every other passing record whose design is not delivered gets stamp equality only, and a delivered design's unedited record is skipped. |
| RR3-4 | 3 | confirm | low | fixed | The glossary said a record stamps every ADR its docs pull request adds or edits, but a failing record keeps its stamps. A passing record stamps them (CONTEXT.md, Review Record entry and its relationship line). |
| RR4-C1 | 4 | review | high | fixed | Local review tool pass, finding_id `0fccd1412859526f6b3282d70ae7b88348cb36ba2e94178c4b5e74407a231090`: the merge check had a base-branch race: `--match-head-commit` pins only the head, so GitHub can merge onto a base newer than the one merge mode checked. Fixed by removal: merge-time enforcement on the plugin's merge paths left this design (answer Q25 A; D28, ADR-0046 decision 7), and this finding is input to #619's own design of it. |
| RR4-1 | 4 | confirm | medium | deferred | `merge-approved.sh` fetched from `origin`, which nothing tied to the `<OWNER> <REPO>` it merges in, so a fork or foreign base could be checked in place of the real one. Deferred to #619, which now owns merge-time enforcement on the plugin's merge paths (answer Q25 A); this finding is its input. |
| RR4-2 | 4 | confirm | low | deferred | Merge mode's exit-code contract was ambiguous for its callers. Deferred to #619, which now owns merge-time enforcement on the plugin's merge paths (answer Q25 A); this finding is its input. |
| RR4-3 | 4 | confirm | low | deferred | A pull request that marks a design delivered skipped the merge check, because merge mode skipped a delivered design's unedited record. Deferred to #619, which now owns merge-time enforcement on the plugin's merge paths (answer Q25 A); this finding is its input. Every slice of a delivered design fails `design_delivered`. |

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
| D10: Delivered design frozen as history | no | no | no | no |
| D11: A second model only when configured | no | no | no | no |
| D15: Drone with exact file scope writes designs and records | no | no | no | no |
| D17: Readiness check is a shared library | no | no | no | no |
| D19: Native blocked-by edges written at triage | no | no | no | no |
| D27: Design-stage resolution is judgment checked by review | no | no | no | no |
| D28: Record verified before ready | no | no | no | no |
| D29: Write permission is the ready label's authority | no | Restates ADR-0045 decision 10, as amended by #625. | no | no |
| A16: the PRD's Lair retrofit criterion covered by #625 | No. The criterion stands, and #625's acceptance criteria verify it. | no | no | no |
| Local-review severities: d224e40e medium, 820000d7 medium, 0c9bd346 high | no | no | no | No. All three are fixed, so the open counts do not depend on the severities. |
| Round-0 placeholder record, now replaced by this record | no | no | no | No. This record replaces it. |
| R2B2: ADR inclusion checked only for records the pull request adds or edits and whose verdict is pass (RR2-1) | no | no | no | no |
| R2B3: a verify failure stops the run, and fix rounds never edit a record | no | No. ADR-0026 Tier B surfaces a validation failure remediation cannot resolve. | Narrows: a fix can no longer re-stamp a record. | no |
| R2B4: every docs-branch run launches as a draft with no closable launch reference | no | no | no | no |
| R2B5: where a repository wires verify in its own CI, which is optional, it maps `docs/prds/` and `docs/adr/` to verify beside `docs/initiatives/`; this repository does through its own `tools/validate.sh` as an example | no | no | no | no |
| R2B6: the design slug is derived from the parent epic's seed marker; #615's delivery adds the marker by hand to epics #603 and #614 | No. This pull request edits no epic. | no | no | no |
| R2B8 and R2B9: exact Design block line counts, and the seed marker slug checked before any `git` or `gh` call | no | no | no | no |
| R2B10: every open count is 0 at pass, stricter than the PRD's exit rule of zero open critical or high | No. It matches the PRD's rule that a record with any open finding cannot merge (#641). | no | no | no |
| R2B11: named test scripts, fixture folders and this repository's own `tools/validate.sh` suites, an example of optional verify wiring | no | no | no | no |
| R2A8: #623 blocked by #625 | no | no | no | no |
| D20's list covers `standard-delivery.js` and `pr-feedback-remediation.js` | no | no | no | no |
| In every repository the fallbacks are the guide's verify before ready, the readiness check and the fix-round commit refusal; verify in a repository's own CI is optional, never required (P26, Q21 A), and D28, ADR-0046 decision 7 and the auto-merge residual state that | no | no | No change: it states where the existing bound holds. | no |
| The guide does not pass verify as a validation command | no | no | no | no |
| The guide's verdict-fail-first step removed | no | no | no | no |
| The github-reviewer's own fix commits are bound by a Validation Procedure rule and D24 | no | no | No change: its commit path is unchanged, a record edit is authoritative only through the human-reviewed merge (D24, answer Q5 A), and its git commits fall inside the recorded residual Record commits outside the fix-round commit step. | no |
| R3B8: the triage overlay is a `--overlay` JSON argument | no | no | Narrows: triage carries no inputs-file Edit entry. | no |
| R3A7: the PRD path shape in the allowlist | no | no | no | no |
| R3B9: one reason code per pass-rule clause, and `record_open_blocking` renamed `record_open` | no | no | no | no |
| Duplicates merged: R3B6 with R3A7 | no | no | no | no |
| Verify checks stamp equality and ADR inclusion only for a record whose `verdict` is `pass` (RR2-1) | no | no | No change: a failing record fails the pass rule and the readiness check either way. | no |
| Each round's fixes and its record rewrite land in one standard-delivery run, the record wave last | no | no | no | no |
| The run that writes `verdict` `pass` carries only the record wave and launches with `local_review` false | no | no | No change: the documents it stamps passed local review in earlier runs, and the merge stays human-reviewed (D24). | no |
| A review fix after the review exits follows the order of Re-review and re-stamp | no | no | no | no |
| The guide returns a docs pull request that is not a draft to draft with `gh pr ready --undo` before it launches a run on it | no | no | Narrows: a pull request a run may change is a draft. | no |
| The record body's Residuals and History sections are optional, and verify reads neither | no | no | no | no |
| The PRD's design-decisions criterion matches its user story: a call with no strong recommendation is asked (overlord) | Within the approved council removal (D32, answers Q12 A and Q14 B). | no | no | no |
| Every other finding fixed as recommended | no | no | The trust-boundary and merge-path fixes were asked (D24, D28). | no |
| RR1B1 and RR1B2: stamps name blobs at the commit a pass reviewed, under one stamp rule | no | no | Narrows: a stamp names only content a pass read. | no |
| A clean round raises no new finding and finds no earlier finding unfixed | no | no | no | no |
| RR1B3: the post-apply re-check's overlay holds exactly `readiness:ready` | no | no | no | no |
| RR1B4 and RR2-C1: guide runs take the fixed request layout; review text, findings included, reaches a run only as the docs pull request's body and comments under the pass scan | no | no | Narrows: no review text enters a run's request. | no |
| D33's mechanism: the marker line `hivemind-guide-run: <slug>`, not a new launch arg | no | Within the ADR-0039 decision 4 narrowing asked in re-review round 1, answer Q19 A. | no | no |
| A refused or blocked guide launch starts no run and still runs on Instinct under ADR-0039 decision 3 | no | No. ADR-0039 decision 3 is unchanged. | No change: its commits stay inside the recorded residual Record commits outside the fix-round commit step. | no |
| RR1B6: line-ending carriage returns are removed before parsing | no | no | no | no |
| RR1B7: stage derivation fails on any truncated paged read | no | no | no | no |
| RR1B8: verify checks deferred and recorded Notes | no | no | no | no |
| RR1B9: a weak or absent design decision is asked with no end condition; #638 may change it only by its own ADR | Within the approved council removal (D32, answers Q12 A and Q14 B): the PRD's Further Notes say the same. | Within the ADR-0026 decision 2 amendment asked under D32, answer Q16 A: its end becomes an ADR of #638. | no | no |
| RR1A3: the record-commit residual covers every commit route outside `runCommitStep` | no | no | No change: it restates the residual of answer Q15 A by its rule, not by a count. | no |
| RR1A4, RR1A5 and RR1A6: coverage rows, Seam order headings and consumer-assertion fixtures | no | no | no | no |
| The glossary's Instinct and Review Record entries reflect D33 and the stamp rule | no | no | no | no |
| RR2-2: line 2 of a guide request is `Docs pull request: #<n>` or `Docs pull request: none`, and references come only from line 2 | no | Within the ADR-0039 decision 4 narrowing asked in re-review round 1, answer Q19 A. | Narrows: no other number reaches references. | no |
| The guide posts each round's findings as docs pull request comments with `gh pr comment` | no | no | No change: the executing user's credentials, on the pull request the guide already writes. | no |
| RR2-3: a recorded Note's repository path, and a deferred Note's `#<n>` checked by shape with no gh call | no | no | no | no |
| D11: the local review tool pass runs through `hivemind:adaptation-cycle`, and `HIVEMIND_DESIGN_REVIEW_MODEL` falls back to cerebrate's own model | no | no | no | no |
| The Findings Angle column: A or B for a round-1 finding's angle group, confirm for a confirming pass, review for the local review tool, local review or post-PR review | no | no | no | no |
| One pass per round covering every angle, confirming rounds over the change and fixes only, and findings landing before the next round, set by the PRD (#640, #641, #643) | no | no | no | no |
| Verify is one shared library, `plugin/skills/_shared/record-verify.sh`, sourced by each caller's own script | no | no | no | no |
| The P26 sweep (#642): CI, `tools/validate.sh`, the Codex plugin and Fable are each optional, with a stated fallback | No. #642 set P26 on main. | no | No change: the guide's verify before ready, the readiness check and the fix-round commit refusal hold in every repository. | no |
| RR3-3 and RR3-4: the delivered-design exclusion in Review record body, and the glossary's passing-record ADR stamps | no | no | no | no |

Moved to #638 with the council, so no longer listed here: D12, D13, D14, D16, D18 and D18's `skip` at `balanced`, D25, D26, the A1 redesign, ADR-0042 decision 9 not amended, A15, R2A3, the switched-option gate, the `needs_user_fact` absent rule, the council switch re-plan, script-local council answers, the composed-brief defect, the `dissent` bound, `council.js`, the merges of A5 with B12, A6 with B13, R2A1 with R2B1, R2A4 with B15, R2B7 with A2, R3A8 with R3B1 and R3B8 with R3A2, R3B1, R3B2, R3B3, R3A2, R3A3, R3A4 and R3B7.

The commit refusal, the code-read verify stop, verify on every record the pull request adds or edits (in a repository's own CI where it wires verify there, optional per Q21 A) and `design_delivered` were asked (Q10 A), and the round-4 count was asked (Q11 A). After round 4 the council split (Q12 A, Q14 B), the narrowing of ADR-0037 decision 16 (Q13 A), the commit refusal's scope (Q15 A), the ADR-0026 decision 2 amendment (Q16 A) and the remediation plan (Q17 A) were asked. In re-review round 1 the narrowing of ADR-0026 decision 3 (Q18 A, D9), the return of a guide-launched run to the guide (Q19 A, D33) and the remediation plan (Q20 A) were asked. In re-review round 2 the plugin-only merge check with the narrowing of ADR-0044's merge conditions (Q21 A, D28) and the remediation plan (Q22 A) were asked. After re-review round 3 the broadened merge check (Q23 A, D28), its git fetch and base-drift details (Q24 A, D28) and the one-time fourth re-review round (Q23 A, D34) were asked. After re-review round 4 the move of merge-time enforcement out to #619 (Q25 A, D28, D34) and the diminishing-returns check (D35, the user's directive) were asked, and the taken rows for merge mode's details left with it. So none of them has a taken row.

## Decisions asked

- D9, design-decision always-ask rule. Asked in re-review round 1. The user's answer: Q18 A: ADR-0046 records narrowing ADR-0026 decision 3 for design-stage decisions only; the always-ask list replaces the Promotion Gate's architectural clause (clause 2). D9 and D32 cite it.
- D20, prose budget with no pre-approved raise. The user's answer: Q1 B, no budget raise is pre-approved.
- D24, review record authority is a human-reviewed merge. The user's answer: Q5 A, take the recommendation.
- D28, record integrity enforced in code. The user's answers:
  - Q10 A, asked after design review round 3: every commit except a standard-delivery wave refuses a review record, the validate step reads verify's `record-verify-failed: <record path>` line in code and stops the run blocked before any fix decision, verify runs on every record the pull request adds or edits (in a repository's own CI where it wires verify there, optional per Q21 A), and a delivered design's slices fail `design_delivered`.
  - Q15 A, asked after design review round 4, narrows Q10 A: the commit refusal covers `runCommitStep` only. Every commit route outside it carries no refusal, a recorded residual (Residuals).
  - Q13 A, asked after design review round 4: the validate step's record stop narrows ADR-0037 decision 16.
  - Q21 A, asked in re-review round 2: the merge check needs only the plugin, with no CI merge gate. The guide keeps the docs pull request a draft until verify passes at its head and the record passes the pass rule. Verify's merge mode fails a record the pull request adds or edits whose verdict is not pass or whose open counts are not all 0. `merge-approved.sh` and the Lair's merge (#623) run it and refuse a docs pull request it fails, which narrows ADR-0044's merge conditions by one refusal. A human who marks the pull request ready and merges it is a recorded residual bounded by D24 (Residuals). Verify in a repository's own CI is optional. Its merge-check part is superseded by Q25 A.
  - Q23 A and Q24 A, asked after re-review round 3: merge mode checks, at the head a merge path would merge, every record that a changed PRD, solution design, ADR or record applies, with every check and the pass rule. `merge-approved.sh` fetches the head and base from origin with git and refuses a pull request whose changed paths or commits it cannot read, and merge mode refuses a stamp path the base changed after the merge-base. This broadens the ADR-0044 narrowing of Q21 A. Superseded by Q25 A.
  - Q25 A, asked after re-review round 4: supersedes the merge-check parts of Q21 A, Q23 A and Q24 A. Merge-time enforcement on the plugin's merge paths leaves this design and is #619's own design question, with RR4-C1 and RR4-1 to RR4-3 as its input. The guide keeps the docs pull request a draft until verify passes at its head and the record passes, and neither GitHub nor `merge-approved.sh` merges a draft, which meets the PRD's rule that such a record cannot merge (#641). A human who marks the pull request ready and merges it, or a push after it is ready that `merge-approved.sh` then merges, is a recorded residual (Residuals).
- D31, one-time fourth design review round. Asked after design review round 3. Spent: round 4 raised new high findings, so the council split out (D32). The user's answers:
  - Q9 A: fix all round-3 findings, then run round 4 as a one-time confirming round; if it raises any new critical or high finding, the council work (#618, #624) splits out into its own initiative.
  - Q11 A: round 4 is recorded under Rounds as the D31 confirming round, and `rounds` stays 3.
- D32, council split into its own initiative. Asked after design review round 4. The user's answers:
  - Q12 A and Q14 B: the council, slices #618 and #624 and the decisions listed under Moved to #638 with the council go to #638, and the PRD loses its council requirements.
  - Q16 A: until #638 ships, a design decision with a weak or absent recommendation is asked, recorded as an amendment of ADR-0026 decision 2 for design-stage decisions. Re-worded in re-review round 1 (RR1B9): #638 may change it only by its own ADR.
  - Q17 A: the round-4 remediation plan is accepted.
- D33, guide-launched runs return to the guide. Asked in re-review round 1. The user's answer: Q19 A: a run the guide launched that fails or ends blocked returns to the guide, which re-derives the stage, with no Instinct takeover. This narrows ADR-0039 decision 4 for guide-launched runs, recorded in ADR-0046; #622 edits `plugin/agents/overlord.md` (`## Engine`) within D20.
- D34, one-time fourth re-review round. Asked after re-review round 3. The user's answer: Q23 A: fix all four round-3 findings, then run round 4 of the re-review as a one-time confirming round, recorded like D31: it does not change `rounds`; if it raises any new critical or high finding, the merge enforcement moves out to #619's own design, and the design narrows its claim to the guide's draft rule and the readiness check. Q25 A, asked after re-review round 4: round 4 raised a new high finding, RR4-C1, so the merge enforcement moved out to #619 (D28), and one final confirming round over that change follows and does not change `rounds`.
- D35, diminishing-returns check after every round. The user's directive after re-review round 4: "We should factor diminishing returns identification into our design review....I shouldn't have to ask specifically if we're at diminishing returns." After every round the review checks its findings for recurrence on an already-fixed surface, a downward severity trend while fixes add surface, and edge cases an existing safeguard bounds, and raises the advisory to the maintainer unprompted.
- Round-2 remediation plan. Asked in re-review round 2. The user's answer: Q22 A, the plan is accepted. Review findings reach a guide run only as docs pull request comments under the pass scan, the guide request has a fixed layout (RR2-C1, RR2-2; D33), stamp equality and ADR inclusion are checked only on a passing record (RR2-1; D28), and the Note shapes are defined (RR2-3).
- Round-3 remediation plan. Asked after re-review round 3. The user's answer: Q24 A, the plan is accepted.

## Moved to #638 with the council

These asked decisions are no longer decisions of this design. Their numbers are not reused.

- D21, accepted-ADR amendments recorded in ADR-0047. The user's answer: Q2 A, the amendments of ADR-0026, ADR-0036 and ADR-0045 are recorded in ADR-0047 only.
- D22, runner member through a sixth runner-gate script. The user's answer: Q3 A, take the recommendation.
- D23, overlord may launch the council agents. The user's answer: Q4 A, take the recommendation.
- D30, council settles unmarked weak or unanswered questions. Asked in design review round 2. The user's answers:
  - Q6 A: the council weighs every weak or unanswered planner question not marked as needing a fact only the user holds. A strong result with a clean gate is taken. A switch plans again with the answer settled. A split is asked with each side's reasoning. Planners mark through one brief field, `needs_user_fact`.
  - Q7 A: #618 seeds `Edit(.hivemind/council-inputs-*.json)` through `settings-merge.sh`.
  - Q8 A: the round-2 remediation plan is accepted with the Q6 answer.

## Residuals

Auto-merge of a docs pull request, from finding B5:

- Scope: with `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a bot approval and green checks with no human review of the design.
- Ground: the user's decision of 2026-11-21 (answer Q5). It is outside the threat model as the maintainer's own opt-in under [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md).
- Bounded impact: in any repository, `merge-approved.sh` never merges a draft, and the guide keeps the pull request a draft until verify passes at its head and the record passes (ADR-0046 decision 7). The fix-round commit refusal holds, the readiness check fails every slice of a stale, failing or delivered record, and #623 closes the Lair path. Where a repository adds verify to its own CI, verify there also keeps a merged record consistent and current. A wrong design is caught only by a later review.
- Recorded in [ADR-0046](../../adr/0046-idea-to-ready-process.md), Residuals.

Record commits outside the fix-round commit step, from findings R4A1, R4B1 and RR1A3:

- Scope: every commit route outside `runCommitStep` can carry a review record path with no code refusal, such as Instinct, chosen or as the fallback after a refused launch or a failed or blocked run the guide did not launch, the Reflex tail's molt checkpoint, the state-machine implement loop's molt checkpoints, the local reviewer's molt fix commits on every path, the github-reviewer's git commits and the guide's own molt commits. A run the guide launched does not fall back to Instinct (answer Q19 A).
- Ground: unclosable on this engine, because a model that writes a molt inputs file or runs git can carry any path. The user decided so (asked after design review round 4, answer Q15 A).
- Bounded impact: the guide's verify before ready, the readiness check failing every slice of a stale record, and verify in the repository's own CI where it adds it. A re-stamp without review reaches trunk only through a human-reviewed merge (D24) or under the auto-merge residual.
- Recorded in [ADR-0046](../../adr/0046-idea-to-ready-process.md), Residuals.

Human merge of a record that does not pass, from re-review rounds 2 and 4:

- Scope: a human with write permission who deliberately marks the docs pull request ready and merges it can merge a record with an open finding or a failed verdict, unless the repository adds its own merge block. A push after the pull request is ready can likewise leave its record stale or failing when a human, or `merge-approved.sh` under `HIVEMIND_AUTO_MERGE`, merges it.
- Ground: HIVEMIND requires no consumer CI, so it has no merge gate a human cannot pass (`docs/engineering-principles.md` P26). The user decided so (asked in re-review round 2, answer Q21 A). After re-review round 4 the user moved merge-time enforcement on the plugin's merge paths to #619's own design question (answer Q25 A).
- Bounded impact: the merge is a human-reviewed merge (D24) or the maintainer's auto-merge opt-in. The guide keeps the pull request a draft until the record passes, and the readiness check fails every slice of a stale record or one that does not pass the pass rule, so no slice of it is labeled ready or claimed. A repository may add verify to its own CI as an optional capability.
- Recorded in [ADR-0046](../../adr/0046-idea-to-ready-process.md), Residuals.

## History: 2026-11-22

### Rounds

#### Round 1

Two parallel passes. Each was fresh and read-only, ran with `Memory context: none`, and neither reviewer wrote the design.

- Angle A: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Code truth, governance and ADR conflicts, existing-path coverage.
- Angle B: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Failure modes, trust and injection, testability.

#### Round 2

The confirming round. It ran as one pass per angle. Each pass was fresh and read-only, ran with `Memory context: none`, and neither reviewer wrote the design.

- Angle A: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Code truth, governance and ADR conflicts, existing-path coverage.
- Angle B: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Failure modes, trust and injection, testability.

Angle A confirmed every round-1 finding fixed except A2, A13 and A14, which were partly or not fixed. Angle B confirmed every round-1 finding fixed except B15. Those four rows are reopened with Round 2. The round raised 21 new findings, R2A1 to R2A10 and R2B1 to R2B11.

#### Round 3

The confirming round. It ran as one pass per angle. Each pass was fresh and read-only, ran with `Memory context: none`, and neither reviewer wrote the design.

- Angle A: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Code truth, governance and ADR conflicts, existing-path coverage.
- Angle B: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Failure modes, trust and injection, testability.

Angle A confirmed every round-1 and round-2 finding fixed. It judged R2B3 fixed but found that its fix introduced R3A1. Angle B confirmed every round-1 and round-2 finding fixed except R2B3: the rule was written but not enforced, the validate step's failures were free text, and the fix round had no file scope. So R2B3 is reopened with Round 3. The round raised 17 new findings, R3A1 to R3A8 and R3B1 to R3B9.

#### Round 4

The D31 confirming round. It ran as one pass per angle. Each pass was fresh and read-only, ran with `Memory context: none`, and neither reviewer wrote the design. The first attempt of each pass was cut off by a usage limit, yielded no round and was re-run fresh.

- Angle A: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Code truth, governance and ADR conflicts, existing-path coverage.
- Angle B: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Failure modes, trust and injection, testability.

Both angles confirmed every round-1 to round-3 finding fixed. The round raised 9 new findings, R4A1 to R4A5 and R4B1 to R4B4. R4A1 is high, so the council split out into its own initiative, #638 (D32). Round 4 did not change `rounds` (answer Q11 A).

### Findings

Local review reported no severity for d224e40e, 820000d7 and 0c9bd346. The severities below are assigned to match the finding each one shares a fix with: B18, B9 and B5.

| ID | Round | Angle | Severity | Disposition | Note |
|---|---|---|---|---|---|
| A1 | 1 | A | high | fixed | The consult is a step ahead of an unchanged `decide()`. No `council_split` ask reason and no `council` list reason. The Ask Set is unchanged (D25). |
| A2 | 2 | A | high | fixed | Reopened in round 2: the sixth runner-gate script also needed `plugin/agents/synapse.md`, `runnerValuePatterns` in `plugin/workflow-src/lib/facts.js`, the `containment.sh` remove-inputs kind `council`, the Edit rule seeded through `settings-merge.sh` (asked, Q7 A) and the script path `plugin/skills/council-member/scripts/council-member.sh`. Coverage and D20 list them (D22). R2B7 is its duplicate. |
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
| A13 | 2 | A | medium | fixed | Reopened in round 2: the trust bullets lacked their slices. Every trust bullet now names its slices, and every Seam order row a bullet names carries Trust boundaries, #620 included. |
| A14 | 2 | A | medium | fixed | Reopened in round 2: D20 lacked two built scripts. D20 and coverage add `analysis-only.js` and `pr-feedback-remediation.js`, regenerated by #618, #619 and #624, plus `synapse.md`. |
| A15 | 1 | A | medium | fixed | The ADR-0026 decision 2 amendment is narrowed to the design stages and standard-delivery. |
| A16 | 1 | A | medium | fixed | A coverage row assigns the Lair retrofit to #625 and says how it is verified. |
| A17 | 1 | A | medium | fixed | A review fix gets one confirming pass, not counted toward the cap. |
| A18 | 1 | A | low | fixed | D15 and D17 cite ADR-0046. |
| A19 | 1 | A | low | fixed | The glossary entries are qualified and reworded. |
| A20 | 1 | A | low | fixed | Verification names `tools/test_run_review.sh`, `tools/test_subissue_ops.sh` and the prd-to-issues carve-out. |
| B1 | 1 | B | critical | fixed | The caller composes the brief, provenance comes from launch records, and a switched option is gated by its own gate or asks (D26). Round 2 removed the per-option gate: a switched option's gate is the producer's fresh gate read, and the run plans again with the council's answer settled (D26, D30). |
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
| B15 | 2 | B | medium | fixed | Reopened in round 2: the consult step had no injection-suspect branch. Opinions are scanned before Abathur and Abathur's output before compose. A suspect one ends the run with the pass scan's terminal stop, and #624 tests it (Consult step). Closed by the R2B1 structural fix. R2A4 is its duplicate. |
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
| R2A1 | 2 | A | high | fixed | A consult on the validation fix limit's ask would throw in `buildUndecidedAsk`. Duplicate of R2B1, fixed by the same change: the consult covers only planner questions in the planning pass, and `buildUndecidedAsk` sites, code-built briefs and review calls are never consulted (D25, D30). |
| R2A2 | 2 | A | high | fixed | `resolveDecision` is synchronous but convening is async. Closed by the R2B1 structural fix: the consult runs in the async `runPlanningPass` before `resolvePlanAsks`, and `resolveDecision` is unchanged (Consult step, D25). |
| R2A3 | 2 | A | medium | fixed | The runner member counts inside the 2 to 4 members, and `members` holds at most 4 items (Abathur council, Council brief contract, D12). |
| R2A4 | 2 | A | medium | fixed | The consult had no injection-suspect branch, and ADR-0037 keeps it terminal. Duplicate of B15, fixed by the same change. |
| R2A5 | 2 | A | medium | fixed | Seam order had heading gaps. It now uses full exact heading texts and states its row rule. |
| R2A6 | 2 | A | low | fixed | "Gains no third action" was false once #607 adds the park. Context and code truth says `decide()` has no park until #607 adds it. |
| R2A7 | 2 | A | low | fixed | The glossary's Council entry now says Abathur returns a recommendation, the caller keeps the dissent, and a council has 2 to 4 members. |
| R2A8 | 2 | A | low | fixed | #623 was not blocked by #625. Seam order now lists #625 among #623's blockers. |
| R2A9 | 2 | A | low | fixed | The always-ask screens of D9, D12 and D13 read "no" for ADR amendment. This record's screens now read "Within D21's approved amendment, narrowed by D30." |
| R2A10 | 2 | A | low | fixed | The glossary's Initiative Track definition was garbled. It is rewritten. |
| R2B1 | 2 | B | high | fixed | The convening rule admitted sites that cannot act on a council result: the validation fix limit, review calls, a planner take with a different option and facts only the user holds. One structural fix, a forced zoom-out on the mid-delivery consult surface: only unmarked planner questions are consulted, in the async planning pass; every gate is a producer read; a switch plans again; an injection-suspect result is terminal (Consult step, D25, D26, D30). It also closes R2A1, R2A2, R2A4 and B15. |
| R2B2 | 2 | B | high | fixed | An ADR-inclusion check on every record would break other initiatives' docs pull requests. Verify checks ADR inclusion only for records the pull request adds or edits; every other passing record gets stamp equality only (Review record body, D28). |
| R2B3 | 3 | B | high | fixed | Reopened in round 3: angle B found the stop still rested on the validate report and on prose. Closed by the record-integrity zoom-out: every commit except a standard-delivery wave refuses a review record in code, and the validate step reads verify's fixed line in code and stops blocked before any fix decision (Review record front matter, Review record body, D28). |
| R2B4 | 2 | B | high | fixed | Docs-branch runs defaulted to a ready pull request and could add Closes lines. The guide launches every docs-branch run with `draft` true and no closable launch reference (Guide skill, Initiative stages, Failure modes). |
| R2B5 | 2 | B | medium | fixed | CI mapped only `docs/initiatives/` to verify. #619 maps `docs/initiatives/`, `docs/prds/` and `docs/adr/` (Review record body, D28). |
| R2B6 | 2 | B | medium | fixed | The design slug was not bound to the parent epic. It is the epic's seed marker slug, else `epic_marker_missing` (Slice design section format, Seed issue marker). |
| R2B7 | 2 | B | medium | fixed | The `synapse.md` edit and its budget were missing. Duplicate of A2, fixed by the same change; D20 lists `plugin/agents/synapse.md` at 1727 bytes. |
| R2B8 | 2 | B | low | fixed | Design block line counts were unspecified. Each line occurs exactly once, else `design_block_missing` (Slice design section format, Failure modes). |
| R2B9 | 2 | B | low | fixed | The seed marker slug was not checked before `git` or `gh` use. It must match its pattern first, else the issue is ignored and named (Seed issue marker). |
| R2B10 | 2 | B | low | fixed | The pass rule allowed open medium and low rows. A passing record needs every open count at 0 (Review record front matter, D6). |
| R2B11 | 2 | B | low | fixed | No named test homes or `tools/validate.sh` suite registrations. Verification strategy names the test scripts, fixture folders and suites for #615, #619 and #621. |
| R3A1 | 3 | A | medium | fixed | The validate step stopped "blocked" on a verify failure, against SD-25, SD-26 and the Validation Procedure, and no signal told verify failures apart. Closed by the record-integrity zoom-out: verify prints `record-verify-failed: <record path>`, and the validate step reads it in code (Review record body, D28). |
| R3A2 | 3 | A | medium | fixed | Skills with an `Edit(.hivemind/...)` entry are discovered navigators, and council-member, the guide and the triage overlay were not covered. `hivemind:council-member` is the one council navigator, the guide invokes it, and the triage overlay is a `--overlay` JSON argument (Abathur council, Triage readiness gate, Existing-path coverage). |
| R3A3 | 3 | A | low | fixed | The runner kernel in `_shared` routed only to `test_shared_libs`, and the `council-member.sh` suite was unnamed. `tools/validate.sh` routes `plugin/skills/_shared/runner-kernel.sh` and `council-member.sh` to `test_run_review` (Runner member brief mode). |
| R3A4 | 3 | A | low | fixed | D20 counted `needs_user_fact` description bytes in the built scripts, but `projectSchema` drops descriptions. D20 now says the built scripts drop schema descriptions. |
| R3A5 | 3 | A | low | fixed | `consult` at `balanced` had no effect, because the `planner_question` cell there is `surface`. D18 sets `skip` at `balanced`. |
| R3A6 | 3 | A | low | fixed | ADR-0046 decision 7's Verify bullet lacked the delivered qualifier. Superseded by the record-integrity zoom-out: CI verify runs on every record the pull request adds or edits, whatever its design's status. |
| R3A7 | 3 | A | low | fixed | The path allowlist lacked a PRD shape. The PRD path shape joins the allowlist (Slice design section format). |
| R3A8 | 3 | A | low | fixed | Duplicate of R3B1, fixed by the same change. |
| R3B1 | 3 | B | medium | fixed | A user-settled composed ask raised again raw in the same pass was convened again. A composed ask carries its raw question's key, a settled raw question resolves as answered, and within one pass a raw question raised again reuses its composed brief (Consult step). |
| R3B2 | 3 | B | medium | fixed | "No member or Abathur text reaches a planner prompt" was false for asked composed briefs. Council text reaches a planner prompt only inside a question shown to the user: scanned, at most 200 characters each, encoded (Trust boundaries). |
| R3B3 | 3 | B | medium | fixed | A failed or unusable opinion or Abathur scan had no stated behavior, and the design-stage scan was unnamed. A failed scan gives no council result. In the design stages the conductor classifies opinions and Abathur's output, and the review record and the confirming pass check it (Abathur council, Consult step, Design-decision rule). |
| R3B4 | 3 | B | medium | fixed | Delivered designs were exempt from CI verify, and readiness never read delivered status. Closed by the record-integrity zoom-out: CI verify runs on every edited record, and a delivered design's slices fail `design_delivered` (Review record body, Readiness check output contract). |
| R3B5 | 3 | B | medium | fixed | The verify-in-CI guarantees held only in repositories that wire it. Closed by the record-integrity zoom-out: they are scoped to those repositories, and every repository keeps the guide's verify, the readiness check and the commit refusal (Review record body, D28). |
| R3B6 | 3 | B | low | fixed | Duplicate of R3A7, fixed by the same change. |
| R3B7 | 3 | B | low | fixed | Two Synapse Runner Gate residual bullets needed widening. #618 widens Cross-script use to six scripts and the broken-hook seeded-rules bullet to the council inputs rule (Runner member brief mode). |
| R3B8 | 3 | B | low | fixed | The triage overlay's inputs-file transport was unspecified. Duplicate in part of R3A2, fixed by the same change. |
| R3B9 | 3 | B | low | fixed | The pass-rule clauses lacked one reason code each. Each clause has one reason code, and `record_open_blocking` is renamed `record_open` (Readiness check output contract). |
| R4A1 | 4 | A | high | fixed | The claim that every commit except a standard-delivery wave refuses a record was false: four commit routes run outside `runCommitStep`. Scoped to `runCommitStep`; the other routes are a recorded residual (answer Q15 A, Residuals). |
| R4B1 | 4 | B | high | fixed | Duplicate of R4A1, fixed by the same change. |
| R4A2 | 4 | A | medium | fixed | Fixed in commit `05a6fbaf`; its taken decisions are listed for veto. |
| R4A3 | 4 | A | medium | fixed | The validate step's record stop conflicted with ADR-0037 decision 16. The stop now narrows that decision (answer Q13 A). |
| R4A4 | 4 | A | medium | deferred | Council-only: an unattended consult never convenes. Moved to #638 with the council, no impact here. |
| R4B2 | 4 | B | medium | deferred | Duplicate of R4A4, moved to #638 with it. |
| R4A5 | 4 | A | low | fixed | Fixed in commit `05a6fbaf`; its taken decisions are listed for veto. |
| R4B3 | 4 | B | low | fixed | Fixed in commit `05a6fbaf`; its taken decisions are listed for veto. |
| R4B4 | 4 | B | low | deferred | Council-only: the design-stage classification check. Moved to #638 with the council. |
