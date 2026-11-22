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
rounds: 0
clean_round: false
---

# Design review record: Idea to Ready

The first review, rounds 1 to 4, did not converge. After round 4 the user split the council out into its own initiative, #638 (answers Q12 A and Q14 B), and approved the narrowing of ADR-0037 decision 16 (answer Q13 A).

The front matter is replaced for a fresh re-review under Re-review and re-stamp of the solution design. It starts at round 1 and covers the whole documents, because no record of this initiative has passed. The first review's Rounds and Findings are kept under History below.

The stamps are the blobs of commit `6fe5e03342397d06be7f722878ccc4e8fd755184`, read with `git rev-parse HEAD:<path>`. Any later edit to a stamped file makes this record stale until a review of the change re-stamps it. The pull request stays a draft until the re-review passes. The design review skill's verify does not exist yet (#619), so this record is checked by hand.

## Reviewed documents

- [PRD: Idea to Ready](../../prds/idea-to-ready.md)
- [Solution design: Idea to Ready](solution-design.md)
- [ADR-0046](../../adr/0046-idea-to-ready-process.md): the idea-to-ready process

The council ADR drafted in this pull request was withdrawn to #638. The [glossary](../../../CONTEXT.md) edits were reviewed but are not stamped.

## Rounds

None yet.

## Findings

| ID | Round | Angle | Severity | Disposition | Note |
|---|---|---|---|---|---|

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
| D9: Design-decision always-ask rule | no | Within the ADR-0026 decision 2 amendment asked under D32, answer Q16 A. | no | no |
| D10: Delivered design frozen as history | no | no | no | no |
| D11: No dedicated different-model design pass in v1 | no | no | no | no |
| D15: Drone with exact file scope writes designs and records | no | no | no | no |
| D17: Readiness check is a shared library | no | no | no | no |
| D19: Native blocked-by edges written at triage | no | no | no | no |
| D27: Design-stage resolution is judgment checked by review | no | no | no | no |
| D28: Record verified before ready and on every push | no | no | no | no |
| D29: Write permission is the ready label's authority | no | Restates ADR-0045 decision 10, as amended by #625. | no | no |
| A16: the PRD's Lair retrofit criterion covered by #625 | No. The criterion stands, and #625's acceptance criteria verify it. | no | no | no |
| Local-review severities: d224e40e medium, 820000d7 medium, 0c9bd346 high | no | no | no | No. All three are fixed, so the open counts do not depend on the severities. |
| Round-0 placeholder record, now replaced by this record | no | no | no | No. This record replaces it. |
| R2B2: ADR inclusion checked only for records the pull request adds or edits | no | no | no | no |
| R2B3: a verify failure stops the run, and fix rounds never edit a record | no | No. ADR-0026 Tier B surfaces a validation failure remediation cannot resolve. | Narrows: a fix can no longer re-stamp a record. | no |
| R2B4: every docs-branch run launches as a draft with no closable launch reference | no | no | no | no |
| R2B5: CI maps `docs/prds/` and `docs/adr/` to verify, beside `docs/initiatives/` | no | no | no | no |
| R2B6: the design slug is derived from the parent epic's seed marker; #615's delivery adds the marker by hand to epics #603 and #614 | No. This pull request edits no epic. | no | no | no |
| R2B8 and R2B9: exact Design block line counts, and the seed marker slug checked before any `git` or `gh` call | no | no | no | no |
| R2B10: every open count is 0 at pass, stricter than the PRD's exit rule of zero open critical or high | No. A medium or low may still be deferred or recorded, which is a disposition, not open, so the PRD's one-disposition rule leaves no open finding at exit. | no | no | no |
| R2B11: named test scripts, fixture folders and `tools/validate.sh` suites | no | no | no | no |
| R2A8: #623 blocked by #625 | no | no | no | no |
| D20's list covers `standard-delivery.js` and `pr-feedback-remediation.js` | no | no | no | no |
| Consumer repositories rely on the guide's verify, the readiness check and the fix-round commit refusal; D28, ADR-0046 decision 7 and the auto-merge residual are scoped to repositories that wire verify in CI | no | no | No change: it states where the existing bound holds. | no |
| The guide does not pass verify as a validation command | no | no | no | no |
| The guide's verdict-fail-first step removed | no | no | no | no |
| The github-reviewer's own fix commits are bound by a Validation Procedure rule and D24 | no | no | No change: its commit path is unchanged, a record edit is authoritative only through the human-reviewed merge (D24, answer Q5 A), and its git commits fall inside the recorded residual Record commits outside the fix-round commit step. | no |
| R3B8: the triage overlay is a `--overlay` JSON argument | no | no | Narrows: triage carries no inputs-file Edit entry. | no |
| R3A7: the PRD path shape in the allowlist | no | no | no | no |
| R3B9: one reason code per pass-rule clause, and `record_open_blocking` renamed `record_open` | no | no | no | no |
| Duplicates merged: R3B6 with R3A7 | no | no | no | no |
| Verify checks stamp equality only for a record whose `verdict` is `pass` | no | no | No change: a failing record fails the pass rule and the readiness check either way. | no |
| Each round's fixes and its record rewrite land in one standard-delivery run, the record wave last | no | no | no | no |
| The run that writes `verdict` `pass` carries only the record wave and launches with `local_review` false | no | no | No change: the documents it stamps passed local review in earlier runs, and the merge stays human-reviewed (D24). | no |
| A review fix after the review exits follows the order of Re-review and re-stamp | no | no | no | no |
| The guide returns a docs pull request that is not a draft to draft with `gh pr ready --undo` before it launches a run on it | no | no | Narrows: a pull request a run may change is a draft. | no |
| The record body's Residuals and History sections are optional, and verify reads neither | no | no | no | no |
| The PRD's design-decisions criterion matches its user story: a call with no strong recommendation is asked (overlord) | Within the approved council removal (D32, answers Q12 A and Q14 B). | no | no | no |
| Every other finding fixed as recommended | no | no | The trust-boundary and merge-path fixes were asked (D24, D28). | no |

Moved to #638 with the council, so no longer listed here: D12, D13, D14, D16, D18 and D18's `skip` at `balanced`, D25, D26, the A1 redesign, ADR-0042 decision 9 not amended, A15, R2A3, the switched-option gate, the `needs_user_fact` absent rule, the council switch re-plan, script-local council answers, the composed-brief defect, the `dissent` bound, `council.js`, the merges of A5 with B12, A6 with B13, R2A1 with R2B1, R2A4 with B15, R2B7 with A2, R3A8 with R3B1 and R3B8 with R3A2, R3B1, R3B2, R3B3, R3A2, R3A3, R3A4 and R3B7.

The commit refusal, the code-read verify stop, CI verify on every record the pull request adds or edits and `design_delivered` were asked (Q10 A), and the round-4 count was asked (Q11 A). After round 4 the council split (Q12 A, Q14 B), the narrowing of ADR-0037 decision 16 (Q13 A), the commit refusal's scope (Q15 A), the ADR-0026 decision 2 amendment (Q16 A) and the remediation plan (Q17 A) were asked. So none of them has a taken row.

## Decisions asked

- D20, prose budget with no pre-approved raise. The user's answer: Q1 B, no budget raise is pre-approved.
- D24, review record authority is a human-reviewed merge. The user's answer: Q5 A, take the recommendation.
- D28, record integrity enforced in code. The user's answers:
  - Q10 A, asked after design review round 3: every commit except a standard-delivery wave refuses a review record, the validate step reads verify's `record-verify-failed: <record path>` line in code and stops the run blocked before any fix decision, CI verify runs on every record the pull request adds or edits, and a delivered design's slices fail `design_delivered`.
  - Q15 A, asked after design review round 4, narrows Q10 A: the commit refusal covers `runCommitStep` only. The overlord's Instinct fallback, the local reviewer's and the guide's molt commits and the github-reviewer's git commits carry no refusal, a recorded residual.
  - Q13 A, asked after design review round 4: the validate step's record stop narrows ADR-0037 decision 16.
- D31, one-time fourth design review round. Asked after design review round 3. Spent: round 4 raised new high findings, so the council split out (D32). The user's answers:
  - Q9 A: fix all round-3 findings, then run round 4 as a one-time confirming round; if it raises any new critical or high finding, the council work (#618, #624) splits out into its own initiative.
  - Q11 A: round 4 is recorded under Rounds as the D31 confirming round, and `rounds` stays 3.
- D32, council split into its own initiative. Asked after design review round 4. The user's answers:
  - Q12 A and Q14 B: the council, slices #618 and #624 and the decisions listed under Moved to #638 with the council go to #638, and the PRD loses its council requirements.
  - Q16 A: until #638 ships, a design decision with a weak or absent recommendation is asked, recorded as an amendment of ADR-0026 decision 2 for design-stage decisions.
  - Q17 A: the round-4 remediation plan is accepted.

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
- Bounded impact: in a repository that wires verify in CI, verify keeps a merged record consistent and current. In any repository, the fix-round commit refusal holds, the guide runs verify before ready, the readiness check fails every slice of a stale or delivered design, and #623 closes the Lair path. A wrong design is caught only by a later review.
- Recorded in [ADR-0046](../../adr/0046-idea-to-ready-process.md), Residuals.

Record commits outside the fix-round commit step, from findings R4A1 and R4B1:

- Scope: four commit routes can carry a review record path with no code refusal: the overlord's Instinct fallback after a blocked run, the local reviewer's own molt fix commits, the github-reviewer's git commits and the guide's own molt commits.
- Ground: unclosable on this engine, because a model that writes a molt inputs file or runs git can carry any path. The user decided so (asked after design review round 4, answer Q15 A).
- Bounded impact: verify in CI where wired, the guide's verify before ready, and the readiness check failing every slice of a stale record. A re-stamp without review reaches trunk only through a human-reviewed merge (D24) or under the auto-merge residual.
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
