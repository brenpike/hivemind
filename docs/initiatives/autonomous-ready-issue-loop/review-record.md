---
stamps: []
verdict: fail
open:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 1
clean_round: false
---

# Design review record: Lair — Software Factory

The first review, rounds 1 to 3, did not converge. After round 3 the user split the initiative into three part designs: #630 strain launch, #631 merge lane and #632 claim integrity. #633 integrates them into this design. The integration review, rounds 1 to 3 of 2026-11-22, also reached the 3-round cap without converging, on strain containment, and the user split containment into its own part design, #646, Lair design: strain containment (Decisions asked, Round 3 questions). This review restarts at round 1, a fresh re-review under ADR-0046 decision 6, Re-review after an amendment: the front matter is reset (`verdict`, `rounds`, the open counts and `clean_round`), the stamps are kept, and both earlier reviews' rounds and findings are kept under History below.

## Reviewed documents

- [PRD: Lair — Software Factory](../../prds/autonomous-ready-issue-loop.md)
- [Solution design: Lair — Software Factory](solution-design.md)
- [ADR-0045](../../adr/0045-lair-software-factory.md): the Lair software factory

Stamps follow ADR-0046 decision 7, Blob stamps. This re-review kept the first review's stamps under ADR-0046 decision 6, Re-review after an amendment, and they were empty; a record written with `verdict` `fail` keeps its stamps, so they stayed empty through the integration review and stay empty as this review restarts. The record that sets `verdict` `pass` stamps these three documents at the commit its clean pass reviewed, ADR-0045 among them because this pull request edits it.

The mechanism of strain containment is designed and reviewed in #646. This review reads the solution design's Seams between the part designs, item 6, as the requirement and its pointer to #646.

The three part designs, [strain launch](strain-launch-design.md), the [merge lane](merge-lane-design.md) and [claim integrity](claim-integrity-design.md), are read as the text they supersede in the solution design. They are not stamped: the stamp path rule admits no other file of this folder than the solution design and this record. That is bounded: each part design is frozen, and a change to one lands only with a dated Amendments entry in the solution design, which is stamped, so the change stales this record (solution design, opening paragraphs). An edit made with no such entry is a residual (Residuals).

Review rule:

- Rounds count from 1. Round 1 covers the whole documents, because no record of this design has passed.
- Each round is one fresh, read-only `hivemind:cerebrate` pass with `Memory context: none`, covering every angle. When a local review tool is configured, the round adds one pass of that tool. When none is configured, the record says that pass was skipped.
- A round never runs two passes of one model.
- The cap is 3 rounds.

## Rounds

### Round 1

- **Date:** 2026-11-22.
- **Reviewed commit:** `7ac4387dff0d7e46d07650e20abc55b532aa55be`.
- **Scope:** the whole PRD, solution design and ADR-0045, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`, covering every angle. Model: `claude-opus-5-5`. It raised 11 findings, R1-1 to R1-11: 0 critical, 0 high, 4 medium and 7 low.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. The tool returned 0 findings in the diff. It dropped 1 item outside the diff, the merge lane's breaker list under Lifecycle "Stage 4: halt and circuit breaker", which Seams between the part designs, item 4, already replaces by its explicit override. The pass's reviewer agent added one note, C1-1, low.
- **Result:** 0 critical, 0 high, 4 medium and 8 low, all new. The user approved R1-2 option A, R1-8 and R1-3 with "Go" on 2026-11-22 (Decisions asked, Restarted round 1 questions); the other findings take the recommended fix, each listed for veto. Every finding is disposed below, so none is open. The round raised new findings, so it is not clean, and a confirming round follows.

## Findings

| ID | Round | Angle | Severity | Disposition | Note |
| --- | --- | --- | --- | --- | --- |
| R1-1 | 1 | B | medium | fixed | The Crash and Stall rows and the Lifecycle run-end bullet sent a pull request to `lair:review` by strain launch's rows alone, against Seams items 2 and 9. Fixed: solution design, Failure modes, the Crash and Stall rows, a delivery run's route narrowed by Seams item 9 and a remediation run under the merge lane's "Fix-up run lost in flight" with the claim end stopping every merge (Seams item 2); Lifecycle, the "every run end and exit" bullet names Seams items 2 and 9. |
| R1-2 | 1 | A | medium | fixed | The decision digest had no State and ownership row, and as a local item GitHub cannot give again it conflicted with ADR-0045 decision 2 and its 2026-11-21 amendment. Fixed per the user's approval of option A: solution design, State and ownership, the digest row at `control/digest/<session-id>.txt` and the intro sentence; Component "Decision digest and circuit breaker", the Decisions bullet, the Verification strategy case and #611's ADRs cell; [ADR-0045](../../adr/0045-lair-software-factory.md), the amendment of 2026-11-22, "the decision digest is a local item GitHub cannot give again"; `CONTEXT.md`, the **Lair** entry. The digest sits under `control/`, so #646's containment requirement covers it. |
| R1-3 | 1 | A | medium | fixed | The release-train decisions ADR-0045 decision 15 keeps for the user were deferred to #606 with no issue to settle them before #606 is built. Fixed per the user's approval: #647, Lair design: release-train decisions, filed as a part of epic #603; solution design, Seam order states that #647 natively blocks #606, and its pending issue edits add that link; Component "Release-train versioning mode" and the release-train Decisions bullet follow. |
| R1-4 | 1 | A | medium | fixed | Nothing said how #646's design joins this design or freezes. Fixed: solution design, the opening paragraphs and Seams item 6, #646's design joins as a fourth part design through a dated Amendments entry once its own review passes, linked from item 6 and added to the Part designs column of #604, #608 and #612, then frozen; this record's Residuals scope names it. |
| R1-5 | 1 | A | low | fixed | Existing-path coverage and Component "Unattended autonomy level" said a missing marker means today's behavior, though a launch file with no marker fails closed. Fixed: solution design, both places, citing strain launch, Contracts and seams, "Marker check". |
| R1-6 | 1 | B | low | fixed | The Budget overrun row recorded an agent-call cap end as `timed-out`. Fixed: solution design, Failure modes, Budget overrun, the wall-clock budget gives `timed-out` and the agent-call cap the run's own `failed` result with cause `agent_budget`, recorded as `failed`. |
| R1-7 | 1 | A | low | fixed | Seams item 1 did not map strain launch's remediation `claim_nonce` onto claim integrity's payload. Fixed: solution design, Seams item 1, that `claim_nonce` is `run`, and the marker's `nonce` is that of the claim whose run-end marker recorded the pull request. |
| R1-8 | 1 | A | low | fixed | The PRD Post-PR feedback criterion said "exactly one remediation run" on review findings only, against the merge lane's CI-red rule (Tier A Q9), its halt rule (Tier A Q10) and the one remediation per pull request of strain launch's round-5 answer A. Fixed per the user's approval: the PRD, Acceptance Criteria, Post-PR feedback. |
| R1-9 | 1 | B | low | fixed | Trust boundaries and the Labels row omitted review comments as a channel and the user's label holds. Fixed: solution design, Trust boundaries, the channel bullet; State and ownership, the Labels row, the user may add `lair:review` or remove `lair:claimed` as a hold, the holds the merge lane's Trust boundaries name. |
| R1-10 | 1 | A | low | fixed | The glossary's **Strain** entry tied every strain to a brood-plan, and its **Park** entry did not name the third park's handoff (ADR-0045 decision 7). Fixed: `CONTEXT.md`, the **Strain** and **Park** entries. |
| R1-11 | 1 | A | low | fixed | The restarted review's IDs collided with the integration review's in this record and the solution design. Fixed: this record, History's Integration round headings, the Integration review note on IDs, the lead-ins of the integration rounds' calls under Decisions taken and the Decisions asked texts; solution design, the integration review citations in Seams item 6, Decisions and Amendments. |
| C1-1 | 1 | review | low | fixed | Seams item 4 did not name the merge lane's Failure modes rows "Invalid result" and "Failed fix-up run", whose breaker clauses it replaces for invalid results. Fixed: solution design, Seams item 4. |

## Decisions taken, listed for veto

Each decision has its always-ask screen: an answer to each of the four always-ask items of ADR-0046 decision 8. "no" means the decision does not do that.

Listed again for veto, from the part designs:

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- |
| Merge lane, Changes to shared documents, item 2: the Amendments pointer paragraph in the solution design | no | no | no: it points to the merge lane's governing text and changes no rule | no |
| Merge lane, item 3: the round-3 dispositions, applied under History. Its `open_counts` recompute is replaced by the ADR-0046 decision 7 open counts, reset to 0 | no | no | no | no |
| Merge lane, item 4: the **Lair Pull Request** entry in `CONTEXT.md` | no | no | no: it names the merge lane's existing rule, which rests on Tier A answer Q1 and ADR-0044 decision 17 | no |
| Claim integrity: the wording of the ADR-0045 amendment of 2026-11-21, the orphan rule covers only Lair issues | no | no: the amendment was asked and answered A on 2026-11-21; only its wording, which follows invariant Claim state, was decided | no | no |
| Claim integrity: the sentence for the **Lair** entry in `CONTEXT.md` | no | no: it cites the asked amendment of 2026-11-21 to decision 2 | no: it names the key exception the user approved | no |
| Claim integrity: its Amendments paragraph in the solution design | no | no | no | no |

This run's calls:

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- |
| Seams between the part designs, item 1: markers are append-only, signed and posted on the claimed issue; the merge lane's run-end and fix-up end markers and strain launch's outcome write are outcome markers; the dispatch marker is the fix-up start marker | no | no: it implements ADR-0045 decision 2 and its 2026-11-21 amendment | no: claim integrity's signing and counting rules are unchanged | no |
| Item 2: one remediation strain per pull request decides what starts a remediation, and the merge lane's R2 no longer applies | no | no | no: the merge lane's CI-red rule (Q9) and merge gates stand; the one-strain rule is the user's answer A of 2026-11-22 at strain launch's design review round 5 | no |
| Item 3: a remediation run's wall-clock budget is timed from its own launch | no | no | no | no |
| Item 4: one set of counted and skipped breaker outcomes. The counted set is asked (Decisions asked); the skipped outcomes, the streak end and the session scope are this call | no | no | no | no |
| Item 5: one tick order, with the remediation step before the merge lane, per the user's answer A of 2026-11-22 at strain launch's design review round 7 | no | no | no | no |
| Item 7: the orphan rule and the start-up sweep follow claim integrity, with strain launch's deferred-write exemption and the merge lane's worktree removal after the end marker | no | no: it follows the asked ADR-0045 amendment of 2026-11-21 on orphans | no | no |
| The integration entry under the solution design's Amendments covers strain launch, which has no approved Amendments text | no | no | no | no |
| The Part designs column of Seam order | no | no | no | no |
| The line "Part designs this slice implements: ..." added to the bodies of #604 to #612, every other byte kept | no | no | no | no: the body edit is reversible |
| A3-18 disposed `recorded` in ADR-0046 | no | no | no | no |
| B3-9 disposed `fixed` by removing the claim it attacks, through strain launch's changes 1, 2 and 9 | no | no: the reworded ADR-0045 text is strain launch's approved changes 1 and 9 | no: the reworded claims were approved by the user, option A, 2026-11-21 | no |

The parent design's own calls, listed for veto under A3-12:

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- |
| Triage leaves `lair:*` issues alone, built in #608 | no | no | no | no |
| The release-train decisions are deferred with full scope to #606, so #606 and #612 are not ready until a dated Amendments entry settles them | no | no | no | no |
| #608's admission needs the readiness check from #615, recorded in Seam order and left for the maintainer to link | no | no | no | no |

Integration round 1's calls, each in the solution design:

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- |
| R1-4, Seams item 1: the kinds `fixup-start`, `review` and `exit`, the field mapping onto claim integrity's payload, the extra outcome values, and the merge lane's start-marker `kind` not carried | no | no | no: claim integrity's signing and counting rules are unchanged | no |
| R1-6, Seams item 9: strain launch's `lair:review` route of a delivery run that did not complete applies only to a pull request that passes the Lair pull request checks other than the head | no | no | no: it narrows which pull request a route labels; no merge rule changes | no |
| R1-7, Seams item 10: a remediation run's answerable park keeps `lair:claimed`, and the claim still ends at its end marker | no | no | no | no |
| R1-8, Seams items 2 and 3: a landed start marker spends the one remediation; a `not-launched` end goes to `lair:review`; the CI-red rule never starts a second run; the issue's budget no longer gates a remediation; a due dispatch under a halt does not block the review wait | no | no | no: no merge gate changes; each reading sends more pull requests to batch review, never fewer | no |
| R1-9, Seams item 11: a valid result whose reads cannot be made yet is never ended `timed-out`, narrowed by R2-2 to transient reads | no | no | no | no |
| R1-10, Seams item 4: the live-claim qualifier, a remediation run end under an ended claim neither counts nor ends a streak, and an invalid result is `invalid-result`, never `crashed`; by R2-4 it counts toward the breaker as a failure | no | yes, since round 3: C3-1 added the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results", asked and answered A under Decisions asked, Round 3 questions, Q1 | no | no |
| R1-11, Seams item 12: the merged exit closes the issue before its exit marker | no | no | no | no: a closed issue can be reopened |
| R1-13: run end copies each run's decisions into the session digest before clean-up, trusted by its outcome marker | no | no | no | no |
| R1-14, Contract "Park record": the engine builds the park key from the stop's identity | no | no | no | no |
| R1-15, Trust boundaries: the reworded lead and the two channels from Bots, CI check descriptions and any commenter | no: the PRD's user story is unchanged | no | no: it names channels strain launch's Decisions already decided and changes no boundary | no |
| R1-16, Decisions: #607 records ADR-0045 decision 6's narrowing of ADR-0039 decisions 3 and 4 and decision 8's narrowing of ADR-0026 decision 3 in ADR amendments | no | no: accepted ADR-0045 decisions 6 and 8 already decide both narrowings; #607 records them, as strain launch assigns it ADR-0037's | no | no |
| R1-23, Seams item 13: claim integrity's idle signal takes strain launch's activity rule | no | no | no | no |
| R1-27, Seams item 2: one term, remediation run | no | no | no | no |
| R1-18, Seam order: #608 builds the readiness-check call at claim and #605 the docs floor, so #623 builds neither again and keeps its acceptance tests | no: no PRD scope moves; #623's text in ADR-0046 and the idea-to-ready design is left to that epic | no | no | no |
| R1-17, Seam order: #606 after #605, with its native link and Dependencies ref | no | no | no | no |
| Answer 1A on macOS: no ADR-0045 amendment is added, because the `sandbox-exec` profile denies `control/` and the tmux sockets but does not hide the Lair's processes, so the 2026-11-22 residual on process reach still holds as written | no | no: the accepted residual stands unchanged | no | no |
| R1-29: the PRD Labels criterion names `lair:handoff`, `lair:failed` and `lair:review`; `lair:claimed` stays outside it | no: wording only; the criterion keeps its meaning | no | no | no |
| R1-28: the **Lair** and **Park** entries in `CONTEXT.md` | no | no | no | no |

Integration round 2's calls, each the reviewer's recommended fix, taken under the user's direction "Take recs" of 2026-11-22 (Decisions asked):

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- |
| C2-1, Seams item 6: #604's sandbox denies each strain every other Lair worktree and strain folder, on Linux and macOS, with #608's sibling probe cases; #612 runs strains at once only under it. Superseded on 2026-11-22 by the split into #646 (Decisions asked, Round 3 questions, Q1): Seams item 6 no longer claims it | no | no | yes: it narrows a strain's reach; asked through the user's direction "Take recs" | no |
| R2-1, Seams item 6: on Linux the sandbox hides every tmux socket of the user and every user-level service socket that runs a command outside it; the probe `sandbox` runs exactly #604's probe cases. Superseded on 2026-11-22 by the split into #646 (Decisions asked, Round 3 questions, Q1): Seams item 6 no longer claims it | no | no: macOS stays under the accepted ADR-0045 amendments of 2026-11-22 on process reach and of 2026-11-21 on forged markers | yes: it narrows a strain's reach, reading answer 1A; asked through the user's direction "Take recs" | no |
| R2-2, Seams item 11: only a transient read defers a result; a result head the remote does not hold, or a GitHub head still behind it once the budget has passed, ends the run `invalid-result` | no | no | no: no merge rule changes; such a run ends and is never merged | no |
| R2-3, Seams item 2: the merge lane's rows govern a `parked`, `crashed`, `stalled` or `timed-out` remediation end, whose claim end meets strain launch's `lair:review` requirement; a `not-launched` end makes a batch review with reason `fixup-not-launched` | no | no | no: a `not-launched` pull request goes to batch review, never to a merge | no |
| R2-4, Seams item 4: `invalid-result` counts toward the breaker as a failure; `blocked` stays skipped | no | yes, since round 3: C3-1 added the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results", asked and answered A under Decisions asked, Round 3 questions, Q1 | no | no |
| R2-5, Contract "Park record": the key from the stop's whole identity | no | no | no | no |
| R2-6: each Seams item names its building slices, and the heading joins the slices' Component heading(s) cells and the #604 and #608 acceptance-criteria edits | no | no | no | no: the issue edits keep every other byte |
| R2-7: #623's docs-path part is built by #605, recorded on #623, and the ADR-0046 and idea-to-ready text is left to that initiative's own amendment | no: no PRD scope moves | no: ADR-0046 is not edited here | no | no |
| R2-8, Component "Merge lane and auto tier": the docs entries of the floor match at the repository root, ignoring ASCII case | no | no | no: it applies the floor's own root and case rule to answer 2A's entries | no |
| R2-9: the PRD Labels sentence names which issue gets each `lair:*` label | no: wording only; the criterion keeps its meaning | no | no | no |
| R2-10: Seam order exempts #605 after #604 from the native-link rule | no | no | no | no |
| R2-11, Seams item 6: the merge lane's result checks bound a result's `pr`, `branch` and `head` only | no | no | no: it names what the existing result checks bound | no |
| R2-12: the overlord records the input-mode requirement in a comment on #615 | no | no | no | no |
| R2-13: this record's Residuals names the part-design edit with no Amendments entry | no | no | no | no |
| R2-14: Rounds names each pass's model by its id | no | no | no | no |

Integration round 3's calls, each the reviewer's recommended fix, taken under the user's reply "Take recs" of 2026-11-22 (Decisions asked, Round 3 questions):

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- |
| Seams item 6 goes back to the approved texts and points to #646; the merge lane's cache stays under `control/`, covered by the containment of `control/`; strain launch's residuals stand as written; the merge lane's residual "A strain that writes the tick's inputs" applies where its write assumption does not hold | no: the containment mechanism moves to #646, a part design of the same epic | no: it cites the accepted ADR-0045 amendments of 2026-11-21 on forged markers and of 2026-11-22 on process reach unchanged | no: it removes claims and restores the approved residual texts; answer A to Q1 | no |
| Seam order: #646 comes before #604, #608 and #612, each natively blocked by it with no `## Dependencies` ref, and the issue edits add those links | no | no | no | no: a link can be removed |
| R3-5, Contract "Park record": the key is `park-` and the first 16 hex characters of the SHA-256 of the canonical JSON array of the stop's identity fields; for a stop that is not a step stop it is distinct per `decide()` site, an answer binding to the park marker it follows | no | no: it implements ADR-0045 decisions 6 and 11 | no | no |
| R3-9, Seams item 4: the merge lane's Breaker column is replaced for invalid results | no | no: it follows the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results" | no | no |
| R3-10, Seams item 11: a result head still absent after a fetch that completes ends the run `invalid-result`; a failed fetch is transient until the run's budget has passed, then `invalid-result` | no | no | no: such a run ends and is never merged | no |
| R3-7: the round-2 Amendments entry names the residual's narrowing as the fields of a strain's own result | no | no | no | no |
| R3-8: the Residuals bound is the reviewer of the part-design pull request, with D24's recorded residual for auto-merge | no | no | no | no |
| R3-11: the PRD Labels criterion pairs each `lair:*` label with its issue | no: wording only; the criterion keeps its meaning | no | no | no |
| The integration review is kept inside the existing `## History: 2026-11-22` section, under headings named "Integration review", so every heading stays unique | no | no | no | no |
| The containment rows R1-1, R1-2, R1-5, R1-12, R2-1 and C2-1 keep their dispositions with a note naming the split, since History keeps the rows and a high is only `fixed` or `rejected` | no | no | no | no |

Restarted round 1's calls, each the recommended fix of a finding not asked of the user; R1-2, R1-3 and R1-8 were asked (Decisions asked, Restarted round 1 questions):

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- |
| R1-1, Failure modes Crash and Stall rows and the Lifecycle run-end bullet: a delivery run's `lair:review` route is narrowed by Seams item 9, and a remediation run follows the merge lane's "Fix-up run lost in flight", its claim end stopping every merge (Seams item 2) | no | no | no: it names the routes Seams items 2 and 9 already set; no merge gate changes | no |
| R1-4, the opening paragraphs and Seams item 6: #646's design joins as a fourth part design through a dated Amendments entry once its own review passes, then frozen | no: #646 is already a part design of the same epic | no | no | no |
| R1-5, Component "Unattended autonomy level" and Existing-path coverage: a launch file with no marker fails closed | no | no | no: it names strain launch's existing "Marker check" | no |
| R1-6, Failure modes Budget overrun: the agent-call cap ends the run with its own `failed` result, cause `agent_budget`, never `timed-out` | no | no | no | no |
| R1-7, Seams item 1: strain launch's remediation `claim_nonce` is `run`, and the marker's `nonce` is the claim's whose run-end marker recorded the pull request | no | no | no: claim integrity's signing and counting rules are unchanged | no |
| R1-9, Trust boundaries and the Labels row: review comments reach a remediation strain through the author filter, scanned before use; the user may add `lair:review` or remove `lair:claimed` as a hold | no | no | no: it names channels and holds strain launch and the merge lane already decided | no |
| R1-10, `CONTEXT.md`: the **Strain** entry names the Lair strain outside any brood-plan, and the **Park** entry the third park's handoff | no | no | no | no |
| R1-11: the integration review's IDs and rounds are cited as "integration"; History's round headings read "Integration round" | no | no | no | no |
| C1-1, Seams item 4: the breaker clauses of the merge lane's Failure modes rows "Invalid result" and "Failed fix-up run" are replaced for invalid results | no | no: it follows the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results" | no | no |
| R1-2 follow-on: the **Lair** entry in `CONTEXT.md` names the decision digest beside the key | no | no: it cites the asked ADR-0045 amendment of 2026-11-22 to decision 2 | no | no |

## Decisions asked

- **Restarted round 1 questions.** Tier A, asked after this restarted review's round 1. The user answered "Go" on 2026-11-22.
  - The question: "Approve these three changes? (1) R1-2, option A: widen ADR-0045's 2026-11-21 amendment to decision 2 with a dated amendment that names the decision digest file beside the marker key as a local item GitHub cannot give again. (2) R1-8: change the PRD's Post-PR feedback criterion to 'Review findings or a red CI result on an open Lair pull request start at most one remediation run for it, and none while the Lair is halted.' (3) R1-3: open the issue 'Lair design: release-train decisions' as a native blocker on #606, to settle the fragment format, release cadence and release trigger."
  - Answer: "Go". Applied: the ADR-0045 amendment of 2026-11-22, "the decision digest is a local item GitHub cannot give again", with the digest row under the solution design's State and ownership; the PRD's Post-PR feedback criterion; and #647, filed on 2026-11-22, with the solution design's Seam order and issue edits naming its native link on #606.

- **Round 1 questions.** Tier A, asked after this design's integration review round 1. The user answered "1A 2A 3A" on 2026-11-22.
  - Q1 (R1-1, R1-2, R1-5, R1-12), containment. Answer A: #604 builds per-platform containment. On Linux, the strain sandbox that hides the Lair's processes also hides `control/` and every tmux socket, and the Lair's own window runs on its own tmux server no strain can reach. On macOS, a `sandbox-exec` profile denies `control/` and the Lair's tmux sockets. A #608 preflight probe `sandbox` makes the Lair claim nothing when containment cannot be confirmed, stopping with `strain_env_preflight`, probe `sandbox`. The merge lane's cache moves under `control/`. Strain launch's "tmux global environment" residual does not apply under containment. #604's probe cases, on each supported platform: from inside a strain, `tmux -S <socket> list-sessions` and `new-window` fail for each Lair socket, and Bash cannot read `control/marker.key`, append to `control/halt` or delete it.
  - Q2 (R1-18), docs pull requests and the auto tier. Answer A: `docs/prds/`, `docs/initiatives/` and `docs/adr/` go into the auto-tier script's built-in floor, built by #605, so ADR-0046's "A docs pull request never takes the Lair's auto tier (#623)" holds in every consumer project. #623's overlap with #608, the readiness-check call at claim, is recorded in Seam order with who builds it.
  - Q3 (R1-17, R1-20, R1-22), issue-body edits. Answer A: the edits are made after the clean round, before the pull request leaves draft: #604's stale acceptance criteria; #606's Dependencies gaining #605, with the native link; and the `## Design` blocks of #604 to #612. The solution design's Seam order states this obligation. The overlord makes these edits; they are still to be made.

- **Round 2 direction.** The user directed "Take recs" on 2026-11-22: each integration round 2 finding takes its reviewer's recommended fix, and each such call is listed under Decisions taken, listed for veto. This answers the always-ask screens of C2-1 and R2-1, which narrow a strain's reach.

- **Round 3 questions.** Tier A, asked after this design's integration review round 3, which reached the 3-round cap. The user replied "Take recs" on 2026-11-22, taking the recommended option of each.
  - Q1 (R3-1 to R3-4, R3-6 and C3-1), "How should the review proceed?" Options: A, "split strain containment into its own part design under a new issue with its own review; item 6 goes back to what the three part designs approved and points at the new design; fix the other round-3 findings here, naming invalid results in the PRD and ADR-0045; restart this PR's review at round 1 with current rounds moved to History" (recommended); B, "drop cross-strain isolation claims, keep strain launch's residual"; C, "raise the cap, run round 4". Answer A: #646, Lair design: strain containment, is filed and blocks #604, #608 and #612; the PRD Stop controls criterion and the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results", name `invalid-result`; this review restarts at round 1.
  - Q2, "Record round 3 and push the branch now, keeping the PR as a draft?" Answer: yes.

- **Key containment.** Answered A by the user on 2026-11-22. Both approved ADR-0045 residual texts stand unchanged. #604 keeps every Lair strain and remediation strain out of the `control/` folder of the Lair's state root and, on Linux, runs each in a sandbox with its own process namespace. Strain launch's statement that a strain can read any file the user can read holds outside that folder. The solution design states it under Seams between the part designs, item 6.
- **Stalled outcomes.** Answered A by the user on 2026-11-22. The PRD's Stop controls criterion counts stalled outcomes: "Three consecutive failed, crashed, stalled or timed-out outcomes halt the Lair with a stated cause. Parks and review waits do not count." This matches the ADR-0045 amendment of 2026-11-22, more causes stop the Lair.
- **Tier A answers the applied entries carry:**
  - Merge lane, item 1, the PRD Credentials bullet: Tier A, Q4, approved 2026-11-21.
  - Merge lane, item 6, the PRD Out of Scope bullet: Tier A, Q1 and Q3, approved 2026-11-21.
  - Merge lane, item 7, the ADR-0045 Status line: Tier A, Q1 and Q3, approved 2026-11-21.
  - Strain launch, changes 1 to 10: option A each. Changes 1 to 3 were accepted at design, changes 4 and 5 at its local review and changes 6 to 9 at its design review round 1, each on 2026-11-21; change 10 at its design review round 2, on 2026-11-22.
  - Claim integrity, ADR-0045 amendment of 2026-11-21, the marker key is the one local file the Lair cannot rebuild: the user's reply of 2026-11-21, "Sure but I don't even understand what the point is", taken as yes.
  - Claim integrity, ADR-0045 amendment of 2026-11-21, sessions running as the user can forge Lair markers: signed markers with a residual, chosen by the user on 2026-11-21, with no separate operating-system account.
  - Claim integrity, ADR-0045 amendment of 2026-11-21, the orphan rule covers only Lair issues: answer A, 2026-11-21.
  - Claim integrity, ADR-0045 amendment of 2026-11-22, the Lair's strains can read its key where no sandbox hides its processes: Tier A, answer A, 2026-11-22.
  - Claim integrity, ADR-0045 amendment of 2026-11-22, more causes stop the Lair: Tier A, answered yes on 2026-11-22.
- **Merge lane, item 5, is not applied.** The Tier A merge bullet in `plugin/governance/decision-autonomy.md` (Tier A, Q1, approved 2026-11-21) is built by #605, with its fixture update and structural check.

## Residuals

- **A part-design edit with no Amendments entry stales no stamp.**
  - Scope: an edit to [strain launch](strain-launch-design.md), the [merge lane](merge-lane-design.md), [claim integrity](claim-integrity-design.md), or #646's design once it joins as a fourth part design (solution design, opening paragraphs), that lands with no dated entry under the solution design's Amendments.
  - Ground: the stamp path allowlist (idea-to-ready design, Contracts and seams, "Slice design section format") admits no other file of this folder than the solution design and this record, so no part design can be stamped.
  - Bounded impact: a docs pull request never takes the Lair's auto tier (solution design, Component "Merge lane and auto tier"). The bound is the reviewer of the part-design pull request, when there is one, who sees the edit in its diff; a pull request that edits only a part design leaves this record unchanged. With `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a Bot approval with no human review, the residual the idea-to-ready design records under D24.
  - Recorded: here, and under Reviewed documents.

## History: 2026-11-22

This section keeps two earlier reviews of this design: the first review, from here to its decisions asked, and then the integration review, under Integration review below.

The first review of this design, kept as it stood after round 3. Its front matter then held `verdict` `fail`, `open_counts` of 0 critical, 16 high, 13 medium and 11 low, `rounds` 3 and `clean_round` `null`. On 2026-11-22, under #633, every round-3 finding took a disposition from the part design reviews and this integration, so none is open.

### First review scope

This record covered the design review of the Lair: the [PRD](../../prds/autonomous-ready-issue-loop.md), the [solution design](solution-design.md) and [ADR-0045](../../adr/0045-lair-software-factory.md). Only the PRD and the solution design were stamped; each stamp's blob was `git rev-parse HEAD:<path>` for that file. ADR-0045 was reviewed but not stamped. The review exited only when zero critical or high findings were open and one round raised no new findings. It was capped at 3 rounds.

### First review record keys

- `stamps`: one entry per stamped document, with `path` and `blob` keys. Empty until the review passes.
- `verdict`: `pending`, `pass` or `fail`.
- `open_counts`: open findings by severity: `critical`, `high`, `medium` and `low`.
- `rounds`: the number of rounds run.
- `clean_round`: the round that raised no new findings, or `null`.

### First review dispositions

Every finding is open until it gets exactly one disposition:

- **fixed**: the record says where.
- **deferred**: the record names a tracked issue.
- **recorded**: the record says where.
- **rejected**: the record says why.

**Open** is a state, not a disposition. An open finding was counted in `open_counts`, and its disposition column read `open`.

### Round 1, 2026-11-21

One pass.

- **Reviewer:** a `hivemind:cerebrate` planner pass (per PR #613).
- **Model:** Fable 5.2.
- **Angle:** adversarial interrogation of the first Lair draft.

Every finding is fixed: folded into ADR-0045 and the PRD by PR #613 and answered by the named ADR-0045 decision.

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| C1 | critical | Brood-status could not see a run end or a park. | fixed: ADR-0045 decision 5 |
| C2 | critical | Unattended mode covered only `decide()`. | fixed: ADR-0045 decision 6 |
| C3 | critical | Issue text reached the strain with no trust anchor: the label actor was unchecked, and the body was editable after the label. | fixed: ADR-0045 decision 10 |
| H1 | high | The park round-trip criteria were false, and there was no park cap. | fixed: ADR-0045 decisions 11 and 7 |
| H2 | high | The plan-again stop had no cause identity. | fixed: ADR-0045 decision 6 |
| H3 | high | The serial merge lane was contradicted, and a draft pull request could deadlock it. | fixed: ADR-0045 decision 12 |
| H4 | high | Strains copied the coordinator's `settings.local.json`, so `--admin` persisted. | fixed: ADR-0045 decision 4 |
| H5 | high | Unattended mode had no channel and no enforcement. | fixed: ADR-0045 decisions 6 and 4 |
| H6 | high | There was no liveness check, reaping or crash recovery. | fixed: ADR-0045 decisions 5 and 17 |
| M1 | medium | Release train. | fixed: ADR-0045 decision 15 |
| M2 | medium | Label-meaning collision. | fixed: ADR-0045 decision 16 |
| M3 | medium | Stateless design versus counters. | fixed: ADR-0045 decisions 2, 7 and 17, with counts recomputed from GitHub markers |
| M4 | medium | Tooling gaps. | fixed: ADR-0045 decisions 3 and 5. The unverified `Stop` hook and tmux exit stay the ADR-0045 residual that #604 resolves. |

### Round 2, 2026-11-21

One pass.

- **Reviewer:** a `hivemind:cerebrate` planner pass (per PR #613).
- **Model:** claude-fable-5-2.
- **Angle:** gap analysis and solution over the same draft.

Its solutions were adopted as ADR-0045 decisions by PR #613. Its findings are recorded as folded into PR #613, each naming the answering decision. The Context section of ADR-0045 names four findings from the two adversarial reviews together. It does not split them by pass.

| Finding | Disposition |
| --- | --- |
| Park answers were an injection path. | recorded: folded into PR #613, answered by ADR-0045 decision 11 |
| The merge controls did not reach strains. | recorded: folded into PR #613, answered by ADR-0045 decisions 4, 12 and 17 |

### Round 3, 2026-11-21

Two passes, run in parallel. No further round: the review was capped at 3 rounds.

- **Pass A reviewer:** a fresh read-only `hivemind:cerebrate` analysis delegation that did not write the design, with "Memory context: none".
- **Pass A model:** Opus 5.5 (claude-opus-5-5).
- **Pass A angle:** code truth, governance and ADR conflicts, existing-path coverage.
- **Pass B reviewer and model:** the same kind and model as pass A.
- **Pass B angle:** failure modes, trust and injection, testability.
- **Reviewed:** the PRD, ADR-0045 as amended, and the solution design.

Checks that passed (pass A):

- The 13 sections are present, in order.
- Headings are unique.
- Open questions reads None.
- Each decision names its ADR or the condition it fails.
- Links go only to main or this PR.
- The PRD Admission criterion and admission testing decision match the amendment.

Result: 0 critical, 16 high (7 from pass A, 9 from pass B), 13 medium and 11 low. All were new and all were open at the end of round 3. The review did not converge by round 3, so per the review rule it went to the user as a signal to split the initiative.

Deduplicated, the 16 highs are 11 distinct issues: merge keys reach strains (A3-1, B3-17); merge lane bypasses ADR-0044 (A3-2, B3-5, B3-6); merge settings source (A3-3, B3-7); launch inputs from issue text (A3-4, A3-7, B3-2); re-claim and remediation branch (A3-5); governance asks (A3-6); injection-scan executor (B3-1); forgeable markers (B3-3); unchecked strain result (B3-4); auto-tier inputs (B3-8, A3-10); deny-rule containment (B3-9).

The dispositions below were set on 2026-11-22. A finding a part design owns takes that part's review record disposition, citing the record. The merge lane's findings take the text of its Changes to shared documents, item 3, word for word.

#### Pass A findings

| ID | Severity | Finding | Overlaps | Disposition |
| --- | --- | --- | --- | --- |
| A3-1 | high | Lair-written settings do not keep merge keys out of strains: worktree sessions read the main checkout's `settings.local.json` since Claude Code 2.1.211 per ADR-0010, an omitted key overrides nothing inherited, and the file is not named. | B3-17 | fixed: Components > Strain launch and settings, and Contracts and seams > Strain settings and Strain environment, for the user, project and local scopes; a managed merge key stays the named residual "managed settings" under Trust boundaries > Strain containment (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-2 | high | The tick runs `merge-approved.sh` outside the watch, dropping ADR-0044's settled-approval precondition, and the failure-mode row maps the script's results wrongly. | B3-5, B3-6 | fixed: merge-lane-design.md, Settle check, Routing table and Failure modes, under ADR-0044 decisions 17, 18 and 20; completed in round 1 by M1-B3, M1-B4, M1-B5, M1-B13 and M1-B16, in round 2 by M2-A6, M2-A9 and M2-B8, and in round 3 by M3-A2 and M3-B1 |
| A3-3 | high | The controller has no defined source for the merge settings it reads each tick, so unsetting auto-merge may never stop merges. | B3-7 | fixed: merge-lane-design.md, Merge settings source, Merge environment and Lifecycle "Stage 4: halt and circuit breaker"; completed in round 1 by M1-A2, M1-B10 and M1-B15, and in round 2 by M2-B11 |
| A3-4 | high | There is no contract for the strain overlord's launch inputs (level, decisions, draft) or for carrying parked, branch, head and decisions out of the run result. | B3-2 | fixed: Components > Launch inputs, and Contracts and seams > Launch file and Strain result (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-5 | high | Re-claim on the pushed branch and remediation on the PR branch contradict spawn-brood (detached at base) and the brood-child fresh-branch rule. | | fixed: Components > Start points, where the remote compares the pre-image at the write: Lair mode of `push-branch.sh` pushes with a lease pinned to the pre-image the Lair captured, after an ancestry check, and the engine maps its fixed blocker line to `start_moved`; and the Failure modes rows "Start moved", "Moved head before a re-claim launch" and "Moved head before a remediation launch" (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-6 | high | Governance the strain overlord loads (Tier A, user_gate, pre-spawn approval) still tells it to ask, and no slice owns the edits. | | fixed: Components > Unattended governance edits (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-7 | high | The facts step re-reads referenced issues and outsider comments live. | B3-2 | fixed: Components > Launch inputs ("Facts come only from the captured issue text") (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-8 | medium | Draft-PR and closed-unmerged states have no lifecycle exit. | | fixed: merge-lane-design.md, Exits (Draft, Closed unmerged, Claim withdrawn) and Write order; completed in round 1 by M1-B7 and M1-B8, and in round 2 by M2-B3 and M2-B9 |
| A3-9 | medium | Stall and agent-call budget rules rely on signals nothing produces, and the agent-call cap has no owner. | | fixed: Components > Launch inputs ("Agent-call cap": the cap keeps back the record call) and Strain result and liveness ("The engine writes its own record" at every verified end), so `agent_budget` reaches the result (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-10 | medium | Auto-tier inputs have no named source, and two can be forged by the strain. | B3-8 | fixed: merge-lane-design.md, Auto-tier script and Trust boundaries; completed in round 1 by M1-B1, M1-B11 and M1-B12, in round 2 by M2-B4, M2-B6 and M2-B12, in round 3 by M3-A5, M3-B2 and M3-B4, and in round 4 by M4-C4 and M4-C5 |
| A3-11 | medium | The Seam order ADR lists are incomplete (ADR-0010, 0017, 0029, 0037, 0042, 0044). | | fixed: [solution-design.md](solution-design.md), Seam order, where each ADRs cell is the union of the design's row and the part designs' rows for that slice |
| A3-12 | medium | Design calls were taken but not listed for veto, and three (no-merge after edit, CI-red rule, session-scoped breaker) should have been asked. | | fixed: the [merge lane review record](merge-lane-review-record.md) and the [claim integrity review record](claim-integrity-review-record.md) for the three named calls, plus this record's Decisions taken, listed for veto, for the parent design's own calls |
| A3-13 | low | It is unclear whether `lair:review` goes on the issue or the PR. | | fixed: merge-lane-design.md, Exits (Batch review: on the issue and the pull request) and State and ownership; completed in round 1 by M1-A5 |
| A3-14 | low | Remote control (`/rc`) on strains is not covered under Trust boundaries. | | fixed: Trust boundaries (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-15 | low | The state table omits spawn-brood's files. | | fixed: State and ownership (the spawn record row, written by `spawn-brood.sh` before the session starts) and Components > Strain launch and settings (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| A3-16 | low | The intra-epic build order has no native blocked-by links stated. | | fixed: [solution-design.md](solution-design.md), Seam order, which states each edge of the build order as one native blocked-by link and who writes it |
| A3-17 | low | A parked issue loses its `lair:*` label, so triage no longer skips it. | | fixed: [Lifecycle](claim-integrity-design.md#lifecycle), with the solution design's Lifecycle line "with `lair:claimed` removed" superseded in the design's opening list and the proposed Amendments pointer (round 1, C1-A1) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| A3-18 | low | The #606 amendment will stale the record and block every Lair slice until re-review. | | recorded: `docs/adr/0046-idea-to-ready-process.md`, decision 6, Re-review after an amendment, and decision 7, Staleness: an amendment stales the record until a re-review re-stamps it |

#### Pass B findings

| ID | Severity | Finding | Overlaps | Disposition |
| --- | --- | --- | --- | --- |
| B3-1 | high | The pre-spawn injection scan has no executor: it needs a model, the controller has none, and headless `claude -p` is rejected. | | fixed: [Scanner session](claim-integrity-design.md#scanner-session) and [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-2 | high | The strain's model derives launch inputs from the issue text, and the facts step re-reads GitHub live. | A3-4, A3-7 | fixed: Components > Launch inputs (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| B3-3 | high | Marker comments have no author rule, so anyone can forge breaker, budget, park and sweep inputs. | | fixed: [Marker signer and verifier](claim-integrity-design.md#marker-signer-and-verifier) and [Design invariants](claim-integrity-design.md#design-invariants) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-4 | high | Strain result fields (pr, branch, head) are trusted unchecked, and "Lair PR" is undefined. | | fixed: merge-lane-design.md, Lair pull request, Pinned head and Merge-lane step of the tick (late group); completed in round 1 by M1-A6, M1-B1, M1-B2 and M1-B8, in round 2 by M2-A1, M2-B2, M2-B3 and M2-B5, and in round 3 by M3-B2 |
| B3-5 | high | The tick's merge drops ADR-0044's settle period and does not tie the auto tier to the merged head. | A3-2 | fixed: merge-lane-design.md, Settle check, Pinned head and Expected-head argument; completed in round 1 by M1-B4, M1-B5 and M1-B17, in round 2 by M2-B8, and in round 3 by M3-A2 and M3-B1 |
| B3-6 | high | The merge-result failure-mode row maps `merge-approved.sh` results wrongly. | A3-2 | fixed: merge-lane-design.md, Routing table and Failure modes |
| B3-7 | high | No defined source for merge settings in the tick. | A3-3 | fixed: merge-lane-design.md, Merge settings source and Merge environment; completed in round 1 by M1-A2, M1-B10 and M1-B15 |
| B3-8 | high | Auto-tier inputs (protected-path list, local-review-skipped evidence, bump type) are undefined or untrusted. | A3-10 | fixed: merge-lane-design.md, Auto-tier script, Git and tool reads and Trust boundaries; completed in round 1 by M1-B1, M1-B11, M1-B12 and M1-B17, in round 2 by M2-B4, M2-B6, M2-B12 and M2-B14, in round 3 by M3-A5, M3-B2 and M3-B4, and in round 4 by M4-C4 and M4-C5 |
| B3-9 | high | Deny rules cannot deliver "a strain cannot merge, change labels or edit the issue" (`gh api`, `curl`, `bash -c`, committed allows), so an injected strain could admit or answer other issues. | | fixed: the claim it attacks is removed by [strain launch](strain-launch-design.md)'s changes 1, 2 and 9 (Decisions, Changes to shared documents), applied in this pull request to ADR-0045 decision 4, the PRD's Merges bullet and ADR-0045's Residuals: deny rules are a barrier against a strain's mistake, not full containment, and a prompt-injected strain stays a named residual. The strain launch review record's `recorded` disposition is not kept, because a recorded high counts as open under ADR-0046 decision 7. #604's acceptance criterion "A strain cannot merge a pull request, change labels or edit the issue" still states the removed claim; its edit is pending overlord action after the clean round, before the pull request leaves draft (solution design, Seam order; R1-22) |
| B3-10 | medium | A claim is several writes, and the partial states and the sweep are undefined. | | fixed: [Claim sequence](claim-integrity-design.md#claim-sequence) and [Design invariants](claim-integrity-design.md#design-invariants) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-11 | medium | The single-instance lock scope is not stated. | | fixed: [Single-instance lock](claim-integrity-design.md#single-instance-lock), [Lair state root](claim-integrity-design.md#lair-state-root) and [Design invariants](claim-integrity-design.md#design-invariants) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-12 | medium | Session end waits for "branch pushed", which can block forever, and run activity is undefined. | | fixed: the opening list of replaced parent parts now holds the Lifecycle stage 1 sentence; Lifecycle steps 4 and 5 and Strain result and liveness ("Run activity") stand (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| B3-13 | medium | The run outcome to label mapping is incomplete (blocked, complete with no PR, invalid result). | | fixed: merge-lane-design.md, Run outcome to labels; completed in round 2 by M2-A3 |
| B3-14 | medium | Remediation strains leave no GitHub record, their parks have no path, and the halt does not cover them. | | fixed: merge-lane-design.md, Fix-up runs, Markers the merge lane writes, Run outcome to labels and Lifecycle "Stage 4: halt and circuit breaker"; completed in round 1 by M1-A3, M1-B6 and M1-B7, in round 2 by M2-A4, M2-A5, M2-B2 and M2-B10, and in round 3 by M3-B5 |
| B3-15 | medium | Re-claim from the pushed branch has four gaps: moved head, superseded design, unanswered park, decision size limit. | | fixed: Components > Start points (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| B3-16 | medium | The readiness check needs one snapshot, an error state and a cost limit (time-of-check to time-of-use between reads). | | fixed: [Readiness snapshot](claim-integrity-design.md#readiness-snapshot) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-17 | medium | Env values leak into strains both ways, and the marker's source cannot be told. | A3-1 | fixed: Components > Strain launch and settings, and Contracts and seams > Strain environment and Marker check, against a stray or copied marker; a prompt-injected strain that rewrites the Lair's records stays the named residual under Trust boundaries > Strain containment (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| B3-18 | low | The `body_sha256` form is undefined (CRLF, null body). | | fixed: [Contracts and seams](claim-integrity-design.md#contracts-and-seams) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-19 | low | The queue report prints issue-derived text raw and gives no cause. | | fixed: [Queue report](claim-integrity-design.md#queue-report) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |
| B3-20 | low | Verification strategy gaps: test registration in `tools/validate.sh`, overlord prose, injection and halt tests, the halt file path. | | fixed across the three part records: the overlord prose tests and the `tools/validate.sh` registration in the [strain launch review record](strain-launch-review-record.md), the injection and halt tests, the halt file path and their registration in the [claim integrity review record](claim-integrity-review-record.md), and the merge lane's own part in the [merge lane review record](merge-lane-review-record.md) |
| B3-21 | low | The decision digest is only as complete as the strain's report. | | fixed: Components > Strain result and liveness (the engine record at every verified end, with the record call kept back from the cap) and Contracts and seams > Strain result (`decisions` null, shown as unknown, when no record exists) (in [strain-launch-design.md](strain-launch-design.md), per the [strain launch review record](strain-launch-review-record.md), Round 3 findings owned by #630) |
| B3-22 | low | The readiness check reads document paths named in the issue body (seam with #615). | | recorded: [Assumptions about #615](claim-integrity-design.md#assumptions-about-615) (per the [claim integrity review record](claim-integrity-review-record.md), Inherited findings) |

### First review sources

- claude-mem observation #43827 (pass 1).
- claude-mem observations #43828, #43844, #43845 and #43846 (pass 2).
- The Context section of [ADR-0045](../../adr/0045-lair-software-factory.md).
- Round 3: the PRD, ADR-0045 as amended and the solution design, read directly by the two passes.
- The claude-mem observations above could not be read in the session that wrote round 3, because claude-mem was unavailable. The round 1 and 2 finding text and pass metadata are as supplied in the task brief and were not re-checked against them. Every round 1 decision citation was checked against the ADR-0045 text and holds.

### First review decisions taken

Listed for veto in the first review:

- The PRD's Admission criterion and its admission testing decision are aligned with the ADR-0045 amendment.
- The release-train decisions are deferred with their full scope to #606, so #606 and #612 are not ready yet.
- #608's admission depends on the readiness check from #615. This is recorded in the design's Seam order and left for the maintainer to link.
- This record's keys and disposition vocabulary.
- Rounds 1 and 2 are recorded from the listed findings and ADR-0045.

### First review decisions asked

The ADR-0045 admission amendment was asked of and settled by the user before this work. Its three rules:

- Epics are never claimed.
- An issue is claimed only when the readiness check passes at claim time.
- A failing issue stays unclaimed, is named in the queue report, and gets no new label.

The idea-to-ready work is referred to as #614 and #615; the readiness check comes from #615.

Round 3 did not converge under the 3-round cap. The user was asked to choose: split the initiative, fix and run a fourth round, record and merge, or other. The user chose to split.

- The record stayed at verdict `fail`.
- The user accepted a three-way split on 2026-11-21. Each part was filed as a native sub-issue of #603, to get its own solution design and design review:
  - #630 Lair design: strain launch and containment (A3-1, A3-4, A3-5, A3-6, A3-7, B3-2, B3-9, B3-17).
  - #631 Lair design: merge lane (A3-2, A3-3, A3-10, B3-4, B3-5, B3-6, B3-7, B3-8).
  - #632 Lair design: claim integrity (B3-1, B3-3).
- PR #628 was merged.

### Integration review

The review of the integrated design under #633, rounds 1 to 3 of 2026-11-22, kept as it stood after round 3. Its front matter then held `verdict` `fail`, every open count 0, `rounds` 3 and `clean_round` `false`. Round 3 reached the 3-round cap without converging on strain containment, and the user split containment into its own part design, #646, Lair design: strain containment (Decisions asked, Round 3 questions). The containment rows R1-1, R1-2, R1-5, R1-12, R2-1 and C2-1 keep their dispositions, each with a note naming the split: R3-1 is fixed by removing the claims they added from this design, and #646 designs the mechanism. The integration review's finding IDs are cited as "integration R1-n"; the restarted review's IDs start again at R1-1.

### Integration review rounds

#### Integration round 1

- **Date:** 2026-11-22.
- **Reviewed commit:** `9d5438ea2d82d379bedf134c3a13a595f946a7be`.
- **Scope:** the whole PRD, solution design and ADR-0045, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`, covering every angle. Model: `claude-opus-5-5`. It raised 31 findings, R1-1 to R1-31.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It raised 1 finding, C1-1, high, a duplicate of R1-3.
- **Result:** 5 high, 18 medium and 9 low, all new. The user answered the three questions under Decisions asked "1A 2A 3A". Every finding is disposed below, so none is open. The round raised new findings, so it is not clean, and a confirming round follows.

#### Integration round 2

- **Date:** 2026-11-22.
- **Reviewed commit:** `1495f726d708fa35ba94a456edc3450edd8cea18`.
- **Scope:** a confirming round: the change since `9d5438ea` and round 1's fixes, in the PRD, the solution design, ADR-0045 and `CONTEXT.md`, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`. Model: `claude-opus-5-5`. It raised 14 findings, R2-1 to R2-14.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It raised 1 finding, C2-1, high.
- **Result:** 2 high, 5 medium and 8 low, all new. The planner pass confirmed four of round 1's decisions listed for veto as valid: no ADR-0045 amendment for macOS, because the `sandbox-exec` profile denies `control/` and the tmux sockets but does not hide the Lair's processes, so the 2026-11-22 macOS process-reach residual holds as written; the merge lane's start-marker kind (`fixup-checks` or `fixup-review`) is not carried; a `not-launched` remediation end routes the pull request to `lair:review`, and the one remediation is spent once its start marker lands (its writes since set by R2-3); and the record keeps `stamps: []` until it passes (ADR-0046 decision 6 and decision 7). The user directed "Take recs" on 2026-11-22, so each finding takes its reviewer's recommended fix (Decisions asked). Every finding is disposed below, so none is open, and no high is deferred. The round raised new findings, so it is not clean, and round 3, the last under the cap, follows.

#### Integration round 3

- **Date:** 2026-11-22.
- **Reviewed commit:** `4d9cc08beb4b60f09141925af7de8e1ab04db8e4`.
- **Scope:** a confirming round: the change since `1495f726` and round 2's fixes, in the PRD, the solution design, ADR-0045 and `CONTEXT.md`, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`. Model: `claude-opus-5-5`. It raised 11 findings, R3-1 to R3-11: 1 high, 4 medium and 6 low.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, an angle review. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It raised 1 finding, C3-1, high.
- **Result:** 2 high, 4 medium and 6 low, all new. The planner pass found C2-1 not closed and R2-1 only partly closed: containment that denies named targets leaves writable the shared files other processes later run or load as config. The round is not clean, and the 3-round cap is reached. The user replied "Take recs" on 2026-11-22 to the two questions under Decisions asked, Round 3 questions: strain containment is split into #646, the other findings are fixed here, and this review restarts at round 1. Every finding is disposed below, so none is open, and no high is deferred.

### Integration review findings

| ID | Round | Angle | Severity | Disposition | Note |
| --- | --- | --- | --- | --- | --- |
| R1-1 | 1 | B | high | fixed | Seams item 6 gave containment no tmux reach, so a strain on the default tmux server could run `tmux new-window` or `run-shell` outside its sandbox. Fixed per answer 1A: solution design, Seams between the part designs, item 6, hides every tmux socket of the Lair, with the Lair's window on a server of its own, and Verification strategy adds the tmux probe cases. Round 2 (R2-1) widened it on Linux to every tmux socket of the user and every user-level service socket that runs a command outside the sandbox. Round 3 split (R3-1): solution design, Seams item 6, now states the requirement and points to #646, which designs the mechanism. |
| R1-2 | 1 | B | high | fixed | The containment of `control/` had no building slice and no test, and macOS was unaddressed. Fixed per answer 1A: solution design, Seams item 6 (#604 builds it on Linux and macOS), with the containment probe cases under Verification strategy. Round 3 split (R3-1): solution design, Seams item 6, now states the requirement and points to #646, which designs the mechanism. |
| R1-3 | 1 | B | high | fixed | Lifecycle stage 1's "outcome marker, then the labels" inverted the merge lane's Write order. Fixed: solution design, Seams item 8, Run-end write order, for every multi-write route, with the result file kept until the last marker and `gh pr ready` before the run-end mapping; Lifecycle stages 1, 2 and 3; the Failure modes row "A route stopped before its last marker"; and the write-boundary tests under Verification strategy. Claim integrity's order is superseded there. |
| R1-4 | 1 | A | high | fixed | Seams item 1 named markers claim integrity's payload has no kind for. Fixed: solution design, Seams item 1, adds the kinds `fixup-start`, `review` and `exit`, each carrying a counting claim marker's nonce, the field mapping and the outcome values `no-pr`, `invalid-result` and `not-launched`. |
| R1-5 | 1 | B | medium | fixed | No check stopped the Lair where containment was missing. Fixed per answer 1A: solution design, Seams item 6, the preflight probe `sandbox`, and the Failure modes row "Strain containment cannot be confirmed". Round 3 split (R3-1): the probe `sandbox` stays, and #646 designs its cases. |
| R1-6 | 1 | B | medium | fixed | Strain launch's `lair:review` route of a delivery that did not complete could label a pull request the Lair never recorded. Fixed: solution design, Seams item 9, only a pull request that passes the Lair pull request checks other than the head. |
| R1-7 | 1 | A | medium | fixed | The merge lane removed `lair:claimed` on a remediation run's answerable park, against claim integrity. Fixed: solution design, Seams item 10. |
| R1-8 | 1 | A | medium | fixed | Items 2 and 3 left the budget precondition, the `not-launched` retry, the CI-red rule and the halt's effect on the review wait unreconciled with one remediation per pull request. Fixed: solution design, Seams items 2 and 3. |
| R1-9 | 1 | B | medium | fixed | The merge lane ended an unchecked valid result `timed-out`, against strain launch's deferred write. Fixed: solution design, Seams item 11, with the merge lane's rule and its #608 test superseded and the replacing case under Verification strategy. |
| R1-10 | 1 | B | medium | fixed | Item 4 lost the live-claim qualifier, the ended-claim rule and the outcome of an invalid result. Fixed: solution design, Seams item 4, and the Failure modes row "Invalid result". |
| R1-11 | 1 | A | medium | fixed | The merged exit did not close the issue that strain launch requires closed. Fixed: solution design, Seams item 12, and the Lifecycle `readiness:done` bullet. |
| R1-12 | 1 | B | medium | fixed | The merge lane's cache sat where a strain could write it, and the result-file assumption had no bound. Fixed per answer 1A: solution design, Seams item 6, the cache under `control/`, and the result file under strain launch's residual bounded by the merge lane's result checks. Round 2 (C2-1) replaced that result-file text: item 6 now denies each strain every other strain's files, so claim integrity's assumption "Result file per strain" is met. Round 3 split (R3-1): the cache stays under `control/`, covered by the containment of `control/`; the result-file part is #646's, with strain launch's residual as written until then. |
| R1-13 | 1 | B | medium | fixed | A run's decisions could be lost at clean-up, and their trust was unstated. Fixed: solution design, Component "Decision digest and circuit breaker". |
| R1-14 | 1 | B | medium | fixed | The park key had no builder, so a re-claim could not keep it stable. Fixed: solution design, Contract "Park record", the key built by the engine from the stop's identity, and the #607 and #609 test under Verification strategy. |
| R1-15 | 1 | B | medium | fixed | Trust boundaries said only a user with write permission steers the Lair, though Bots, CI descriptions and any commenter reach it. Fixed: solution design, Trust boundaries, its reworded lead and two more channels. The PRD's user story is unchanged; the call is listed for veto. |
| R1-16 | 1 | A | medium | fixed | ADR-0045 decisions 6 and 8 narrow ADR-0039 decisions 3 and 4 and ADR-0026 decision 3 with no slice to record it. Fixed: solution design, Decisions, the unattended-level bullet assigns #607. ADR-0045's Status line is unchanged. |
| R1-17 | 1 | A | medium | fixed | Seam order claimed no link blocks #604, #605 and #606. Fixed: solution design, Seam order, states the native links read from GitHub and #606's edge on #605. Pending overlord action per answer 3A: add `#605` to #606's Dependencies and the native link. |
| R1-18 | 1 | A | medium | fixed | A consumer project's own protected-path list could let a docs pull request take the auto tier. Fixed per answer 2A: solution design, Component "Merge lane and auto tier", the docs directories in the floor built by #605, and Seam order, #623's overlap with #608 and #605. |
| R1-19 | 1 | A | medium | deferred | The readiness check's input mode, the snapshot and trunk commit passed by the Lair with no GitHub read of its own, is a requirement on #615, stated under the solution design's Seam order, cross-epic seams. Deferred to #615, which builds the check. The overlord records it in a comment on #615 (solution design, Seam order, issue edits; R2-12). |
| R1-20 | 1 | A | medium | fixed | The slices carried no `## Design` block for the readiness check. Fixed: solution design, Seam order, states each block's form. Pending overlord action per answer 3A: write the block into #604 to #612 after the clean round, before the pull request leaves draft. |
| R1-21 | 1 | A | medium | fixed | A part design could change with no stamp staling. Fixed: solution design, opening paragraphs, each part design frozen and changed only through a dated Amendments entry, and this record's Reviewed documents. |
| R1-22 | 1 | A | medium | fixed | B3-9's Note did not name #604's stale acceptance criterion. Fixed: B3-9's Note under History. Pending overlord action per answer 3A: the #604 acceptance-criteria edit stated in the solution design's Seam order. |
| R1-23 | 1 | B | low | fixed | Claim integrity's and strain launch's fallbacks for a `Stop` hook that does not fire disagreed. Fixed: solution design, Seams item 13, and the Stall and `Stop` hook rows of Failure modes. |
| R1-24 | 1 | A | low | fixed | The admission sentence said a Dependencies ref is not read, though the readiness check reads it. Fixed: solution design, Component "Controller tick and admission", and the matching Decisions bullet. |
| R1-25 | 1 | A | low | fixed | Two Decisions bullets named no P20 condition, and the containment bullet cited no amendment. Fixed: solution design, Decisions. |
| R1-26 | 1 | B | low | fixed | Existing-path coverage and Verification strategy did not point to the part designs, and crash and stall tests had no one home. Fixed: solution design, both sections, with `tools/test_lair_tick.sh` as that home. |
| R1-27 | 1 | A | low | fixed | One run had two names. Fixed: solution design, Seams item 2, declares remediation run, used throughout. |
| R1-28 | 1 | A | low | fixed | The glossary's Lair entry omitted the remediation strain, and its Park entry pushed with no commits. Fixed: `CONTEXT.md`, the **Lair** and **Park** entries. |
| R1-29 | 1 | A | low | fixed | The PRD Labels criterion called the labels markers. Fixed: the PRD, Acceptance Criteria, Labels, wording only. It names `lair:handoff`, `lair:failed` and `lair:review`; `lair:claimed` (ADR-0045 decision 16) stays outside the criterion. |
| R1-30 | 1 | A | low | rejected | The finding contested the review rule "A round never runs two passes of one model". The rule stays: the two passes run different models from different vendors, the planner pass `claude-opus-5-5` through `hivemind:cerebrate` and the tool pass the tool's own default (ADR-0042 decision 7) through the `codex-plugin` preset. This record now names each pass's reviewer and model under Rounds. |
| R1-31 | 1 | A | low | recorded | The part designs' Assumptions about #630 still say the strain settings carry no merge key. Recorded: ADR-0045 decision 4 as amended, the merge keys set empty, governs, in [solution-design.md](solution-design.md), Contract "Lair-written settings". |
| C1-1 | 1 | review | high | fixed | Lifecycle stage 1 recorded the outcome marker before the labels, against the merge lane's Write order. A duplicate of R1-3, fixed by the same change: solution design, Seams item 8. |
| R2-1 | 2 | confirm | high | fixed | Seams item 6 narrowed answer 1A to the Lair's tmux sockets, so a strain could make another tmux server or a user service run a command outside its sandbox. Fixed: solution design, Seams item 6, on Linux hides every tmux socket of the user and every user-level service socket that runs a command outside the sandbox, the user service manager's bus included, and the probe `sandbox` runs exactly #604's probe cases at each start; Verification strategy adds the `tmux run-shell` and `systemd-run --user` cases. macOS stays under the ADR-0045 amendment of 2026-11-22 on process reach. Round 3 split (R3-1): solution design, Seams item 6, now states the requirement and points to #646, which designs the mechanism. |
| R2-2 | 2 | confirm | medium | fixed | Seams item 11 kept every result whose reads could not be made from timing out, a missing or lagging head included, so such a run could stay deferred without end. Fixed: solution design, Seams item 11 covers only transient reads; a result head the remote does not hold, or a GitHub head still a strict ancestor of it once the budget has passed, ends the run `invalid-result`; the queue report names each deferred result with its age. The Invalid result and Budget overrun rows, the Decisions bullet and the `tools/test_lair_tick.sh` cases under Verification strategy follow. |
| R2-3 | 2 | confirm | medium | fixed | Seams item 2 sent every remediation end other than `complete` to `lair:review`, against the merge lane's rows it keeps. Fixed: solution design, Seams item 2, the merge lane's rows govern a `parked`, `crashed`, `stalled` or `timed-out` remediation end, whose claim end meets strain launch's `lair:review` requirement, and a `not-launched` end makes a batch review with reason `fixup-not-launched`, the end marker last; Verification strategy adds its write-boundary case. Listed for veto. |
| R2-4 | 2 | confirm | medium | fixed | Seams item 4 skipped `invalid-result`, so repeated invalid results never tripped the breaker. Fixed: solution design, Seams item 4 counts it as a failure, a failed outcome for the PRD's Stop controls rule, and keeps `blocked` skipped; the Failure modes row "Invalid result", the breaker Decisions bullet and the R1-10 row under Decisions taken follow. Round 3 (C3-1): the PRD Stop controls criterion and the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results", now name `invalid-result`. |
| R2-5 | 2 | confirm | medium | fixed | The park key held only the stop kind and, for a step stop, the step and cause code, so two distinct stops could share a key. Fixed: solution design, Contract "Park record", the key from the stop's whole identity, with a hash of the sorted paths and, for a non-step stop, the `decide()` site id; Verification strategy adds the distinct-key test for #607 and #609. |
| R2-6 | 2 | confirm | medium | fixed | The Seams items named no building slice, and no slice's Component heading(s) cell led to them. Fixed: solution design, each Seams item names its building slices, `Seams between the part designs` joins the cells of #604, #605 and #608 to #612, and Seam order's issue edits add the containment and its probe cases to #604's and #608's acceptance criteria. |
| R2-7 | 2 | confirm | low | deferred | ADR-0046 decision 7 and the idea-to-ready design assign the docs paths of the Lair's protected list to #623, while this design builds them in #605's floor. The solution design's Seam order now states it: ADR-0046's docs pull request rule holds through #605's floor, and #623's docs pull request acceptance test runs against #605's auto-tier script. Deferred to #623: the overlord records on #623 that its docs-path part is built by #605, and the ADR-0046 and idea-to-ready text is corrected through that initiative's own amendment and re-review. |
| R2-8 | 2 | confirm | low | fixed | The docs entries of the auto-tier floor had no stated match rule. Fixed: solution design, Component "Merge lane and auto tier", at the repository root, compared ignoring ASCII case, as the rest of the floor, with #605's cases under Verification strategy. |
| R2-9 | 2 | confirm | low | fixed | The PRD Labels sentence read as giving every issue a `lair:*` label. Fixed: the PRD, Acceptance Criteria, Labels, names which issue gets each. |
| R2-10 | 2 | confirm | low | fixed | Seam order called every edge of the build order a native link, though #605 after #604 is build order only. Fixed: solution design, Seam order, exempts that edge. |
| R2-11 | 2 | confirm | low | fixed | Seams item 6 bounded every result field by the merge lane's result checks. Fixed: solution design, Seams item 6, those checks bound `pr`, `branch` and `head`; a strain's own outcome, park record and decisions stay under strain launch's residual. |
| R2-12 | 2 | confirm | low | fixed | The input-mode requirement on #615 was recorded only in this design. Fixed: solution design, Seam order's issue edits add the overlord's comment on #615, linking claim integrity's "Assumptions about #615" and noting it needs an amendment of the idea-to-ready design. R1-19 stays deferred to #615. |
| R2-13 | 2 | confirm | low | fixed | A part-design edit with no Amendments entry stales no stamp, and no residual named it. Fixed: this record's Residuals. |
| R2-14 | 2 | confirm | low | fixed | The record named the models loosely. Fixed: Rounds names `claude-opus-5-5` for each planner pass and the tool's own default (ADR-0042 decision 7) for each local review tool pass, and R1-30's Note matches. |
| C2-1 | 2 | review | high | fixed | Containment let one strain read and write another strain's result, liveness and launch files, so a prompt-injected strain could park or fail another claim, hide its stall, spend its remediation or inject decisions once #612 runs strains at once. Fixed: solution design, Seams item 6, #604's sandbox on Linux and macOS denies each strain every other Lair worktree and strain folder, so claim integrity's assumption "Result file per strain" is met; #608's probe `sandbox` and Verification strategy add the sibling cases, with a delivery and a remediation strain running at once; #612 runs strains at once only under it. Round 3 found it not closed (R3-1). Fixed by the split: the claim is removed from Seams item 6, and #646 designs the isolation between strains. |
| R3-1 | 3 | confirm | high | fixed | C2-1 was not closed and R2-1's property was false: containment denied named targets and left writable every shared file another process later runs or loads as config, such as the git common directory's `config` and `hooks/` and the main checkout's `.claude/settings.local.json`, and on macOS a process outside the profile reaches every sibling file. Fixed by the split, per answer A to Q1 after round 3: the over-claiming text is removed from this design (solution design, Seams between the part designs, item 6, reverted to the approved texts), and the containment mechanism is designed in #646. |
| R3-2 | 3 | confirm | medium | deferred | The Linux socket hiding cannot be enumerated: abstract Unix sockets such as X11's and system sockets the user's groups open, such as `/run/docker.sock`, escape hiding by path, with no probe case. Deferred to #646, which designs the sandbox and its probe cases. |
| R3-3 | 3 | confirm | medium | deferred | Hiding the session bus hides the Secret Service keyring, where `gh` and git's libsecret helper keep the token on desktop Linux, so every strain loses GitHub auth with no stated cause or fallback. Deferred to #646, which states the keyring impact and its fallback. |
| R3-4 | 3 | confirm | medium | deferred | The per-start probe's targets and launch order were unspecified, so it could delete a kept result or the user's halt file, and could pass for siblings that exist at launch only. Deferred to #646, which designs the probe `sandbox` on scratch targets under fresh nonces. |
| R3-5 | 3 | confirm | medium | fixed | The park key's fields hold characters its pattern forbids and could exceed 64 characters, and one `decide()` site could raise distinct stops. Fixed: solution design, Contract "Park record", the key `park-` and the first 16 hex characters of the SHA-256 of the canonical JSON array of the identity fields, distinct per `decide()` site for a stop that is not a step stop, an answer binding to the park marker it follows (ADR-0045 decision 11); Verification strategy adds the `step_stop` pattern test. |
| R3-6 | 3 | confirm | low | deferred | The macOS reach was cited to the 2026-11-22 amendment on process reach only, though an escape from the profile is the 2026-11-21 amendment on forged markers. Item 6 and the R2-1 row under Decisions taken now cite both; the other containment citations are deferred to #646. |
| R3-7 | 3 | confirm | low | fixed | The round-2 Amendments entry overstated the residual's narrowing. Fixed: solution design, Amendments, the round-2 entry reads "keeps, of a strain's own result, its outcome, park record and decisions". |
| R3-8 | 3 | confirm | low | fixed | The R2-13 residual's bound misstated D24. Fixed: this record's Residuals, the bound is the reviewer of the part-design pull request when there is one, with D24's recorded residual for the `HIVEMIND_AUTO_MERGE` and `merge-approved.sh` case. |
| R3-9 | 3 | confirm | low | fixed | The merge lane's Breaker column still read "neither" for invalid results. Fixed: solution design, Seams item 4, names that column as replaced for invalid results. |
| R3-10 | 3 | confirm | low | fixed | Item 11's missing-head signal was unreachable, since a failed fetch is transient. Fixed: solution design, Seams item 11, a result head still absent after a fetch that completes ends the run `invalid-result`, and a failed fetch is transient until the run's budget has passed, then `invalid-result`; the Invalid result row, the Decisions bullet and the `tools/test_lair_tick.sh` cases follow. |
| R3-11 | 3 | confirm | low | fixed | The PRD Labels pairing was implicit. Fixed: the PRD, Acceptance Criteria, Labels, "A handed-off issue gets `lair:handoff`, a failed one `lair:failed`, and one sent to batch review `lair:review`." |
| C3-1 | 3 | review | high | fixed | `invalid-result` counted toward the breaker only by a reading the PRD's and ADR-0045's outcome lists did not support. Fixed per answer A to Q1 after round 3: the PRD Stop controls criterion names `invalid-result`, and the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results", adds it to decision 17; solution design, Seams item 4, and R2-4's Note cite both. |
