---
stamps:
  - path: docs/prds/autonomous-ready-issue-loop.md
    blob: aa2e7c942a5160b954182f58f5770d0e9d8e8e89
  - path: docs/initiatives/autonomous-ready-issue-loop/solution-design.md
    blob: 2b8a7b6b58a953f657ba8ecef5c5a142b36cc7f9
  - path: docs/adr/0045-lair-software-factory.md
    blob: e1730da467123263e1e173c3404abae3c5b81861
verdict: fail
open:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 2
clean_round: false
---

# Design review record: Lair — Software Factory

The first review, rounds 1 to 3, did not converge. After round 3 the user split the initiative into three part designs: #630 strain launch, #631 merge lane and #632 claim integrity. #633 integrates them into this design. The integration review, rounds 1 to 3 of 2026-11-22, also reached the 3-round cap without converging, on strain containment, and the user split containment into its own part design, #646, Lair design: strain containment (Decisions asked, Round 3 questions). The restarted review, rounds 1 to 3 of 2026-11-22, reached the cap too, recurring on the decision digest, and the user narrowed the digest to a requirement whose design moves to #611 (Decisions asked, Restarted round 3 advisory). The second restarted review, rounds 1 to 3 of 2026-11-22, reached the cap with only 2 low findings in its round 3, both fixed, and under the user's standing rule its strong recommendation to restart was taken (Decisions taken, listed for veto, Second restart round 3's calls). The third restarted review restarted at round 1, a fresh re-review under ADR-0046 decision 6, Re-review after an amendment, with the earlier reviews' rounds and findings kept under History: 2026-11-22. It passed at round 3 on 2026-11-22, a clean round at reviewed commit `66c4858d38cae6b287c2816dadc17b0afc457047`, with no finding open at any severity. PR #668 (issue #636) then added ADR-0045's "Amendment 2026-11-24", which stales the ADR-0045 stamp. PR #672 (issue #646) then added a dated Amendments entry of 2026-11-24 to the solution design, joining the strain containment part design, and the PRD gained its `**UI:** no` line; both stale their stamps. This re-review restarts at round 1 under ADR-0046 decision 6, Re-review after an amendment: the front matter is reset (`verdict`, `rounds`, the open counts and `clean_round`), the stamps are kept, and the passed review's rounds and findings are kept under History: 2026-11-24. The first re-review reached the 3-round cap at round 3 on 2026-11-25, with no design finding in its round 3, and restarted at round 1 under the user's standing rule (Decisions taken, listed for veto, First re-review round 3's calls), its rounds and findings kept under History: 2026-11-25.

## Reviewed documents

- [PRD: Lair — Software Factory](../../prds/autonomous-ready-issue-loop.md)
- [Solution design: Lair — Software Factory](solution-design.md)
- [ADR-0045](../../adr/0045-lair-software-factory.md): the Lair software factory

Stamps follow ADR-0046 decision 7, Blob stamps. The first review's stamps were empty; a record written with `verdict` `fail` keeps its stamps, so they stayed empty through the integration review, the restarted review and the second restarted review, and through the third restarted review's rounds 1 and 2. The third restarted review's record set `verdict` `pass`, so it stamped these three documents at `66c4858d38cae6b287c2816dadc17b0afc457047`, the commit its clean round 3 reviewed, ADR-0045 among them because its pull request edited it. While the verdict is `fail`, this record keeps the third restarted review's stamps, the blobs at `66c4858d` (ADR-0046 decision 7, Blob stamps). The record that sets `verdict` `pass` re-stamps the PRD, the solution design and ADR-0045 at the commit its clean round reviewed.

The mechanism of strain containment is designed and reviewed in #646. The solution design's Amendments entry of 2026-11-24, from PR #672, now joins that part design, [strain containment](strain-containment-design.md), and edits Seams between the part designs, item 6, and the #604, #608 and #612 rows. This review reads the containment part design like the other part designs, as the text it supersedes. Its part review closed `verdict` `fail` with no stamp, and the maintainer joined it anyway (answer B, `strain-containment-review-record.md`, Decisions asked, D4). A finding on the join itself repeats that recorded decision.

The four part designs, [strain launch](strain-launch-design.md), the [merge lane](merge-lane-design.md), [claim integrity](claim-integrity-design.md) and [strain containment](strain-containment-design.md), are read as the text they supersede in the solution design. They are not stamped: the stamp path rule admits no other file of this folder than the solution design and this record. That is bounded: each part design is frozen, and a change to one lands only with a dated Amendments entry in the solution design, which is stamped, so the change stales this record (solution design, opening paragraphs). An edit made with no such entry is a residual (Residuals).

Review rule:

- Rounds count from 1. A record of this design has passed, so round 1 covers the change since `66c4858d38cae6b287c2816dadc17b0afc457047` in the three stamped documents, which is now: (a) #668's ADR-0045 amendment, "Amendment 2026-11-24"; (b) the solution design's Amendments entries "2026-11-24, strain containment", which joins the strain containment part design (`strain-containment-design.md`, issue #646) and edits Seams item 6 and the #604, #608 and #612 rows, "2026-11-24, Lair re-review round 1" and "2026-11-25, Lair re-review round 2"; (c) the PRD's `**UI:** no` line. Each is checked against the PRD and the solution design. The part designs, `strain-containment-design.md` included, are read as the text they supersede.
- Each later round is a confirming round over the change since the previous round's reviewed commit and that round's fixes.
- Each round is one fresh, read-only `hivemind:cerebrate` pass with `Memory context: none`, covering every angle. The amendment touches ADR-0045 decision 8's architectural gate, so each round adds one pass of the configured local review tool. When none is configured, the record says that pass was skipped.
- A round never runs two passes of one model.
- The cap is 3 rounds. A review that has not converged by then stops and goes to the maintainer.

## Rounds

### Round 1

- **Date:** 2026-11-25.
- **Reviewed commit:** `2a8a1e9f453592b3066c2a85d50bbe201d8fc8a1`, merge-base `eb40ed9804b7ad92498ed42a8478b8edd3311e82`.
- **Scope:** the Review rule's round-1 scope, the change since `66c4858d`: #668's ADR-0045 amendment, "Amendment 2026-11-24"; #672's solution design Amendments entries "2026-11-24, strain containment", "2026-11-24, Lair re-review round 1" and "2026-11-25, Lair re-review round 2"; the PRD's `**UI:**` line. Each is checked against the whole PRD and solution design, with the part designs read as the text they supersede.
- **Pass 1, planner pass:** reviewer `hivemind:cerebrate`, on cerebrate's own model (`model=default`), a fresh read-only pass with `Memory context: none`. It raised 7 findings, R1-1 to R1-7: 0 critical, 0 high, 4 medium and 3 low.
- **Pass 2, local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, on the tool's own default model (ADR-0042 decision 7), base the merge-base. It raised 1 finding, R1-T1, high.
- **Result:** not clean. Every finding is disposed below, so none is open: R1-1 to R1-7 are fixed, and R1-T1 is rejected as a repeat of the maintainer's answer 1 (Decisions asked, Round 2 diminishing-returns advisory (2026-11-25)). The fixes are in the solution design's Amendments entry "2026-11-25, restarted Lair re-review round 1".
- **Diminishing-returns check:** no signal fired on recurrence. The findings are on the containment join's seams, a surface no earlier round of this restarted review fixed; the first re-review's surfaces (the checkout requirement, #607) drew only R1-6 (low) and R1-T1 (a rejected repeat). Trend: this is round 1, so none. The standing rule applies: the strong recommended fixes are taken (Decisions asked, Standing rule clarification).

### Round 2

- **Date:** 2026-11-25.
- **Reviewed commit:** `5b9986b564bbb4448dbb3272b1053b42c13de041`, previous commit `2a8a1e9f453592b3066c2a85d50bbe201d8fc8a1`.
- **Scope:** a confirming round over the change since the previous round's reviewed commit and round 1's fixes, the solution design's Amendments entry "2026-11-25, restarted Lair re-review round 1".
- **Pass 1, planner pass:** reviewer `hivemind:cerebrate`, on cerebrate's own model (`model=default`), a fresh read-only pass with `Memory context: none`. It covered the diff and round 1's fixes and found every round-1 row closed (`unfixed: none`). It raised 4 findings, R2-1 to R2-4: 0 critical, 0 high, 0 medium and 4 low.
- **Pass 2, local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, on the tool's own default model (ADR-0042 decision 7), base the previous commit. It raised 1 finding, R2-T1, high, a repeat.
- **Result:** not clean. Every finding is disposed below, so none is open: R2-1 to R2-4 are fixed and R2-T1 is rejected as a repeat of first re-review R3-T1, rejected and recorded (Decisions taken, listed for veto, First re-review round 3's calls). The fixes are in the solution design's Amendments entry "2026-11-25, restarted Lair re-review round 2", except R2-4, which is fixed in this record.
- `Diminishing-returns advisory:` Signal 1, recurrence: R1-1's proxy guard drew R2-1 and R2-2, and R1-4's Seam order edits drew R2-3. Signal 2, trend: severity fell from 4 medium and 3 low in round 1 to 4 low in round 2. Signal 3: R2-2's macOS case is already bounded by the round-1 entry's "on Linux". The maintainer's standing rule applies: a strong recommendation is taken (Decisions asked, Standing rule clarification). The conductor's recommendation, strong: keep going to round 3.

## Findings

| ID | Round | Angle | Severity | Disposition | Note |
| --- | --- | --- | --- | --- | --- |
| R1-1 | 1 | B | medium | fixed | Strain containment's per-tick forwarder and proxy checks had no place in the tick order and no claim or remediation guard. Fixed: Seams item 5 places them; the proxy-up read is a re-taken tick guard and gates remediation; `claims: blocked proxy-down`; #608 tick cases. |
| R1-2 | 1 | A | medium | fixed | #608 and strain containment's "Linux egress" (#604) both claimed the proxy. Fixed: #604 builds the proxy, relay and forwarder; #608 starts, stops and checks them. |
| R1-3 | 1 | B | medium | fixed | A strain-written branch name, checked only by `git check-ref-format`, reached the rescue command the user runs. Fixed: read via the head-check helper; identifier gate and 255-byte cap; a fixed rescue text otherwise; #608 case. |
| R1-4 | 1 | A | medium | fixed | #615 has landed (`readiness-check.sh`, snapshot mode), but Context and code truth said no check exists, and the Snapshot rule bound only #615. Fixed: code truth updated; the rule covers any change adding a GitHub field the check reads. |
| R1-5 | 1 | A | low | fixed | The "Lair-written settings" contract missed strain containment's overrides. Fixed. |
| R1-6 | 1 | A | low | fixed | #607's ADR-0026 amendment would record a narrowing not applied. Fixed: it states no gate is waived until the signal's entry lands. |
| R1-7 | 1 | B | low | fixed | No case pinned the Lair's own tmux calls to `-L default`. Fixed: #608 case. |
| R1-T1 | 1 | review | high | rejected | Local review finding `25044206254f97df512158b9acb5faf15f0477c15b774052e79974d09708f213`, "The checkout-isolation guard cannot be implemented from the stated requirement". Reason: it repeats the maintainer's answer 1 (Decisions asked, Round 2 diminishing-returns advisory (2026-11-25)), which narrowed the claim to a requirement and deferred the mechanism to #608. #608's design lands as a dated Amendments entry that stales this record before build. The finding's added cases (object alternates, shared object dirs, restart and adoption, tests) were added to #608's scope: https://github.com/brenpike/hivemind/issues/608#issuecomment-7162789441. |
| R2-1 | 2 | confirm | low | fixed | A proxy found down at claim integrity's step-5 re-take was a step-5 end: `claims: ok`, counted toward the 3-end lockout. Fixed: it ends the attempt with no write and no count; `claims: blocked proxy-down` prints from the next tick's step 4; #608 case aligned; override named. |
| R2-2 | 2 | confirm | low | fixed | The proxy-up guard, the remediation gate and the #608 case were not scoped to Linux, so macOS would never claim. Fixed: scoped to Linux. |
| R2-3 | 2 | confirm | low | fixed | Seam order still said ADR-0046 decision 7 and idea-to-ready "Lair admission" await #623's correction, and quoted decision 3's old text, though ADR-0046's amendment of 2026-11-22 had already corrected both. Fixed: stated as corrected; the quote and the #623 comment were updated. |
| R2-4 | 2 | confirm | low | fixed | Round 1's Scope line under-reported its coverage. Fixed in this record. |
| R2-T1 | 2 | review | high | rejected | Local review finding `9fef7bb571d9c25a4023fb823da0f6d91101e23c4956d947b559481f02e0a641`, "The fixes have not received the required confirming clean review". Reason: it repeats first re-review R3-T1, rejected and recorded (Decisions taken, listed for veto, First re-review round 3's calls). Round 2 is that confirming round, at the commit carrying round 1's fixes. |

## Decisions taken, listed for veto

The tables from the part designs' decisions to integration round 3's calls give each decision its always-ask screen: an answer to each of the four always-ask items of ADR-0046 decision 8 as it stood before its amendment of 2026-11-22. "no" means the decision does not do that. Their screen's columns name what each decision touches, and their Recommendation strength column gives its strength: `strong`, or `asked: "Take recs"` where the decision took the reviewer's recommended fix at the user's direction its lead-in names (Decisions asked). Each table meets the amended decision 8's rule that every taken decision gives its recommendation strength and what it touches. The restarted rounds', second restart rounds' and third restart rounds' tables give each decision its recommendation strength and what it touches (scope, ADR amendment, trust, credential, merge path), as the amended decision 8 requires (Decisions asked, Design-decision rule update); "none" means it touches none of them. The IDs in the restarted rounds' tables are the restarted review's, cited elsewhere as "restarted R1-n" (History, Restarted review). The IDs in the second restart rounds' tables are the second restarted review's, cited elsewhere as "second restart R1-n" (History, Second restarted review). The IDs in the third restart rounds' tables are the third restarted review's, cited elsewhere as "third restart R1-n" (History, Third restarted review). The IDs in the first re-review rounds' tables are the first re-review's, cited elsewhere as "first re-review R1-n" (History, First re-review). This re-review's own IDs are those of Findings above.

Listed again for veto, from the part designs:

| Decision | Recommendation strength | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- | --- |
| Merge lane, Changes to shared documents, item 2: the Amendments pointer paragraph in the solution design | strong | no | no | no: it points to the merge lane's governing text and changes no rule | no |
| Merge lane, item 3: the round-3 dispositions, applied under History. Its `open_counts` recompute is replaced by the ADR-0046 decision 7 open counts, reset to 0 | strong | no | no | no | no |
| Merge lane, item 4: the **Lair Pull Request** entry in `CONTEXT.md` | strong | no | no | no: it names the merge lane's existing rule, which rests on Tier A answer Q1 and ADR-0044 decision 17 | no |
| Claim integrity: the wording of the ADR-0045 amendment of 2026-11-21, the orphan rule covers only Lair issues | strong | no | no: the amendment was asked and answered A on 2026-11-21; only its wording, which follows invariant Claim state, was decided | no | no |
| Claim integrity: the sentence for the **Lair** entry in `CONTEXT.md` | strong | no | no: it cites the asked amendment of 2026-11-21 to decision 2 | no: it names the key exception the user approved | no |
| Claim integrity: its Amendments paragraph in the solution design | strong | no | no | no | no |

This run's calls:

| Decision | Recommendation strength | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- | --- |
| Seams between the part designs, item 1: markers are append-only, signed and posted on the claimed issue; the merge lane's run-end and fix-up end markers and strain launch's outcome write are outcome markers; the dispatch marker is the fix-up start marker | strong | no | no: it implements ADR-0045 decision 2 and its 2026-11-21 amendment | no: claim integrity's signing and counting rules are unchanged | no |
| Item 2: one remediation strain per pull request decides what starts a remediation, and the merge lane's R2 no longer applies | strong | no | no | no: the merge lane's CI-red rule (Q9) and merge gates stand; the one-strain rule is the user's answer A of 2026-11-22 at strain launch's design review round 5 | no |
| Item 3: a remediation run's wall-clock budget is timed from its own launch | strong | no | no | no | no |
| Item 4: one set of counted and skipped breaker outcomes. The counted set is asked (Decisions asked); the skipped outcomes, the streak end and the session scope are this call | strong | no | no | no | no |
| Item 5: one tick order, with the remediation step before the merge lane, per the user's answer A of 2026-11-22 at strain launch's design review round 7 | strong | no | no | no | no |
| Item 7: the orphan rule and the start-up sweep follow claim integrity, with strain launch's deferred-write exemption and the merge lane's worktree removal after the end marker | strong | no | no: it follows the asked ADR-0045 amendment of 2026-11-21 on orphans | no | no |
| The integration entry under the solution design's Amendments covers strain launch, which has no approved Amendments text | strong | no | no | no | no |
| The Part designs column of Seam order | strong | no | no | no | no |
| The line "Part designs this slice implements: ..." added to the bodies of #604 to #612, every other byte kept | strong | no | no | no | no: the body edit is reversible |
| A3-18 disposed `recorded` in ADR-0046 | strong | no | no | no | no |
| B3-9 disposed `fixed` by removing the claim it attacks, through strain launch's changes 1, 2 and 9 | strong | no | no: the reworded ADR-0045 text is strain launch's approved changes 1 and 9 | no: the reworded claims were approved by the user, option A, 2026-11-21 | no |

The parent design's own calls, listed for veto under A3-12:

| Decision | Recommendation strength | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- | --- |
| Triage leaves `lair:*` issues alone, built in #608 | strong | no | no | no | no |
| The release-train decisions are deferred with full scope to #606, so #606 and #612 are not ready until a dated Amendments entry settles them. Superseded on 2026-11-22 by #647 (Decisions asked, Restarted round 1 questions) | strong | no | no | no | no |
| #608's admission needs the readiness check from #615, recorded in Seam order and left for the maintainer to link | strong | no | no | no | no |

Integration round 1's calls, each in the solution design:

| Decision | Recommendation strength | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- | --- |
| R1-4, Seams item 1: the kinds `fixup-start`, `review` and `exit`, the field mapping onto claim integrity's payload, the extra outcome values, and the merge lane's start-marker `kind` not carried | strong | no | no | no: claim integrity's signing and counting rules are unchanged | no |
| R1-6, Seams item 9: strain launch's `lair:review` route of a delivery run that did not complete applies only to a pull request that passes the Lair pull request checks other than the head | strong | no | no | no: it narrows which pull request a route labels; no merge rule changes | no |
| R1-7, Seams item 10: a remediation run's answerable park keeps `lair:claimed`, and the claim still ends at its end marker | strong | no | no | no | no |
| R1-8, Seams items 2 and 3: a landed start marker spends the one remediation; a `not-launched` end goes to `lair:review`; the CI-red rule never starts a second run; the issue's budget no longer gates a remediation; a due dispatch under a halt does not block the review wait | strong | no | no | no: no merge gate changes; each reading sends more pull requests to batch review, never fewer | no |
| R1-9, Seams item 11: a valid result whose reads cannot be made yet is never ended `timed-out`, narrowed by R2-2 to transient reads | strong | no | no | no | no |
| R1-10, Seams item 4: the live-claim qualifier, a remediation run end under an ended claim neither counts nor ends a streak, and an invalid result is `invalid-result`, never `crashed`; by R2-4 it counts toward the breaker as a failure | strong | no | yes, since integration round 3: integration C3-1 added the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results", asked and answered A under Decisions asked, Round 3 questions, Q1 | no | no |
| R1-11, Seams item 12: the merged exit closes the issue before its exit marker | strong | no | no | no | no: a closed issue can be reopened |
| R1-13: run end copies each run's decisions into the session digest before clean-up, trusted by its outcome marker | strong | no | no | no | no |
| R1-14, Contract "Park record": the engine builds the park key from the stop's identity | strong | no | no | no | no |
| R1-15, Trust boundaries: the reworded lead and the two channels from Bots, CI check descriptions and any commenter | strong | no: the PRD's user story is unchanged | no | no: it names channels strain launch's Decisions already decided and changes no boundary | no |
| R1-16, Decisions: #607 records ADR-0045 decision 6's narrowing of ADR-0039 decisions 3 and 4 and decision 8's narrowing of ADR-0026 decision 3 in ADR amendments | strong | no | no: accepted ADR-0045 decisions 6 and 8 already decide both narrowings; #607 records them, as strain launch assigns it ADR-0037's | no | no |
| R1-23, Seams item 13: claim integrity's idle signal takes strain launch's activity rule | strong | no | no | no | no |
| R1-27, Seams item 2: one term, remediation run | strong | no | no | no | no |
| R1-18, Seam order: #608 builds the readiness-check call at claim and #605 the docs floor, so #623 builds neither again and keeps its acceptance tests | strong | no: no PRD scope moves; #623's text in ADR-0046 and the idea-to-ready design is left to that epic | no | no | no |
| R1-17, Seam order: #606 after #605, with its native link and Dependencies ref | strong | no | no | no | no |
| Answer 1A on macOS: no ADR-0045 amendment is added, because the `sandbox-exec` profile denies `control/` and the tmux sockets but does not hide the Lair's processes, so the 2026-11-22 residual on process reach still holds as written | strong | no | no: the accepted residual stands unchanged | no | no |
| R1-29: the PRD Labels criterion names `lair:handoff`, `lair:failed` and `lair:review`; `lair:claimed` stays outside it | strong | no: wording only; the criterion keeps its meaning | no | no | no |
| R1-28: the **Lair** and **Park** entries in `CONTEXT.md` | strong | no | no | no | no |

Integration round 2's calls, each the reviewer's recommended fix, taken under the user's direction "Take recs" of 2026-11-22 (Decisions asked):

| Decision | Recommendation strength | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- | --- |
| C2-1, Seams item 6: #604's sandbox denies each strain every other Lair worktree and strain folder, on Linux and macOS, with #608's sibling probe cases; #612 runs strains at once only under it. Superseded on 2026-11-22 by the split into #646 (Decisions asked, Round 3 questions, Q1): Seams item 6 no longer claims it | asked: "Take recs" | no | no | yes: it narrows a strain's reach; asked through the user's direction "Take recs" | no |
| R2-1, Seams item 6: on Linux the sandbox hides every tmux socket of the user and every user-level service socket that runs a command outside it; the probe `sandbox` runs exactly #604's probe cases. Superseded on 2026-11-22 by the split into #646 (Decisions asked, Round 3 questions, Q1): Seams item 6 no longer claims it | asked: "Take recs" | no | no: macOS stays under the accepted ADR-0045 amendments of 2026-11-22 on process reach and of 2026-11-21 on forged markers | yes: it narrows a strain's reach, reading answer 1A; asked through the user's direction "Take recs" | no |
| R2-2, Seams item 11: only a transient read defers a result; a result head the remote does not hold, or a GitHub head still behind it once the budget has passed, ends the run `invalid-result` | asked: "Take recs" | no | no | no: no merge rule changes; such a run ends and is never merged | no |
| R2-3, Seams item 2: the merge lane's rows govern a `parked`, `crashed`, `stalled` or `timed-out` remediation end, whose claim end meets strain launch's `lair:review` requirement; a `not-launched` end makes a batch review with reason `fixup-not-launched` | asked: "Take recs" | no | no | no: a `not-launched` pull request goes to batch review, never to a merge | no |
| R2-4, Seams item 4: `invalid-result` counts toward the breaker as a failure; `blocked` stays skipped | asked: "Take recs" | no | yes, since integration round 3: integration C3-1 added the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results", asked and answered A under Decisions asked, Round 3 questions, Q1 | no | no |
| R2-5, Contract "Park record": the key from the stop's whole identity | asked: "Take recs" | no | no | no | no |
| R2-6: each Seams item names its building slices, and the heading joins the slices' Component heading(s) cells and the #604 and #608 acceptance-criteria edits | asked: "Take recs" | no | no | no | no: the issue edits keep every other byte |
| R2-7: #623's docs-path part is built by #605, recorded on #623, and the ADR-0046 and idea-to-ready text is left to that initiative's own amendment | asked: "Take recs" | no: no PRD scope moves | no: ADR-0046 is not edited here | no | no |
| R2-8, Component "Merge lane and auto tier": the docs entries of the floor match at the repository root, ignoring ASCII case | asked: "Take recs" | no | no | no: it applies the floor's own root and case rule to answer 2A's entries | no |
| R2-9: the PRD Labels sentence names which issue gets each `lair:*` label | asked: "Take recs" | no: wording only; the criterion keeps its meaning | no | no | no |
| R2-10: Seam order exempts #605 after #604 from the native-link rule | asked: "Take recs" | no | no | no | no |
| R2-11, Seams item 6: the merge lane's result checks bound a result's `pr`, `branch` and `head` only | asked: "Take recs" | no | no | no: it names what the existing result checks bound | no |
| R2-12: the overlord records the input-mode requirement in a comment on #615 | asked: "Take recs" | no | no | no | no |
| R2-13: this record's Residuals names the part-design edit with no Amendments entry | asked: "Take recs" | no | no | no | no |
| R2-14: Rounds names each pass's model by its id | asked: "Take recs" | no | no | no | no |

Integration round 3's calls, each the reviewer's recommended fix, taken under the user's reply "Take recs" of 2026-11-22 (Decisions asked, Round 3 questions):

| Decision | Recommendation strength | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
| --- | --- | --- | --- | --- | --- |
| Seams item 6 goes back to the approved texts and points to #646; the merge lane's cache stays under `control/`, covered by the containment of `control/`; strain launch's residuals stand as written; the merge lane's residual "A strain that writes the tick's inputs" applies where its write assumption does not hold | asked: "Take recs" | no: the containment mechanism moves to #646, a part design of the same epic | no: it cites the accepted ADR-0045 amendments of 2026-11-21 on forged markers and of 2026-11-22 on process reach unchanged | no: it removes claims and restores the approved residual texts; answer A to Q1 | no |
| Seam order: #646 comes before #604, #608 and #612, each natively blocked by it with no `## Dependencies` ref, and the issue edits add those links | asked: "Take recs" | no | no | no | no: a link can be removed |
| R3-5, Contract "Park record": the key is `park-` and the first 16 hex characters of the SHA-256 of the canonical JSON array of the stop's identity fields; for a stop that is not a step stop it is distinct per `decide()` site, an answer binding to the park marker it follows | asked: "Take recs" | no | no: it implements ADR-0045 decisions 6 and 11 | no | no |
| R3-9, Seams item 4: the merge lane's Breaker column is replaced for invalid results | asked: "Take recs" | no | no: it follows the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results" | no | no |
| R3-10, Seams item 11: a result head still absent after a fetch that completes ends the run `invalid-result`; a failed fetch is transient until the run's budget has passed, then `invalid-result` | asked: "Take recs" | no | no | no: such a run ends and is never merged | no |
| R3-7: the round-2 Amendments entry names the residual's narrowing as the fields of a strain's own result | asked: "Take recs" | no | no | no | no |
| R3-8: the Residuals bound is the reviewer of the part-design pull request, with D24's recorded residual for auto-merge | asked: "Take recs" | no | no | no | no |
| R3-11: the PRD Labels criterion pairs each `lair:*` label with its issue | asked: "Take recs" | no: wording only; the criterion keeps its meaning | no | no | no |
| The integration review is kept inside the existing `## History: 2026-11-22` section, under headings named "Integration review", so every heading stays unique | asked: "Take recs" | no | no | no | no |
| The containment rows R1-1, R1-2, R1-5, R1-12, R2-1 and C2-1 keep their dispositions with a note naming the split, since History keeps the rows and a high is only `fixed` or `rejected` | asked: "Take recs" | no | no | no | no |

Restarted round 1's calls, each the recommended fix of a finding not asked of the user; R1-2, R1-3 and R1-8 were asked (Decisions asked, Restarted round 1 questions):

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| R1-1, Failure modes Crash and Stall rows and the Lifecycle run-end bullet: a delivery run's `lair:review` route is narrowed by Seams item 9, and a remediation run follows the merge lane's "Fix-up run lost in flight", its claim end stopping every merge (Seams item 2) | strong | merge path: it names existing routes; no merge gate changes |
| R1-4, the opening paragraphs and Seams item 6: #646's design joins as a fourth part design through a dated Amendments entry once its own review passes, then frozen | strong | none: #646 is already a part design of the same epic |
| R1-5, Component "Unattended autonomy level" and Existing-path coverage: a launch file with no marker fails closed | strong | none: it names strain launch's existing "Marker check" |
| R1-6, Failure modes Budget overrun: the agent-call cap ends the run with its own `failed` result, cause `agent_budget`, never `timed-out` | strong | none |
| R1-7, Seams item 1: strain launch's remediation `claim_nonce` is `run`, and the marker's `nonce` is the claim's whose run-end marker recorded the pull request | strong | none: claim integrity's signing and counting rules are unchanged |
| R1-9, Trust boundaries and the Labels row: review comments reach a remediation strain through the author filter, scanned before use; the user may add `lair:review` or remove `lair:claimed` as a hold | strong | trust, merge path: it names existing channels and holds; no boundary or gate changes |
| R1-10, `CONTEXT.md`: the **Strain** entry names the Lair strain outside any brood-plan, and the **Park** entry the third park's handoff | strong | none |
| R1-11: the integration review's IDs and rounds are cited as "integration"; History's round headings read "Integration round" | strong | none |
| C1-1, Seams item 4: the breaker clauses of the merge lane's Failure modes rows "Invalid result" and "Failed fix-up run" are replaced for invalid results | strong | none: it follows the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results" |
| R1-2 follow-on: the **Lair** entry in `CONTEXT.md` names the decision digest beside the key | strong | none: it cites the asked ADR-0045 amendment of 2026-11-22 to decision 2 |

Restarted round 2's calls, each the recommended fix of a finding, taken under ADR-0046 decision 8 as amended on 2026-11-22; none was asked. The first three rows list for veto the digest calls that round 1's R1-2 fix made beyond the amendment the user approved:

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| R1-2's fix: the decision digest sits under `control/` in the Lair's state root, covered by the containment of Seams item 6 | strong | trust: it puts the digest inside the contained folder; no scope, credential or merge-path change |
| R1-2's fix: an entry holds the run's issue, pull request, outcome, `counted` or `unverified` mark, decision count and decisions. Narrowed on 2026-11-22 (Decisions asked, Restarted round 3 advisory): the entry's contents are #611's to design | strong | none |
| R1-2's fix: the Lair window prints only the digest folder's path and the per-run counts, never decision text. Narrowed on 2026-11-22 (Decisions asked, Restarted round 3 advisory): what the Lair window prints is #611's to design | strong | trust: no strain text reaches the terminal |
| C2-1, State and ownership and Component "Decision digest and circuit breaker": one file per run, `control/digest/<run-id>.txt`, written through a temporary file in the same folder, a flush, a rename and a folder flush; a run id is unique per run, so a retry by any session, an `unverified` entry's after a restart included, rewrites the same file; the entry header names the run's session as `session <id>`, the `session` of its outcome marker, or `unknown` for an `unverified` entry; the Lair never reads an entry back. Narrowed on 2026-11-22 (Decisions asked, Restarted round 3 advisory): one file per run under `control/digest/`, never read back, stays; the rest is #611's to design | strong | ADR amendment: it edits in place the ADR-0045 amendment of 2026-11-22 on the digest, which this pull request adds and which is not yet on trunk |
| R2-1, the digest write order: after the route's last marker, or at run end, marked `unverified`, when run end writes no outcome marker; clean-up waits for it; a tick that finds a run whose last marker has landed and whose worktree is not cleaned up writes the entry, then cleans up; a failed write keeps the worktree and result file, the queue report names the run, and the next tick retries. Narrowed on 2026-11-22 (Decisions asked, Restarted round 3 advisory): the entry is written before the run's clean-up removes its result file; the rest is #611's to design | strong | ADR amendment: the same in-place edit names the write after the last marker |
| R2-2, the entry format: a fixed-template header of validated tokens with an untrusted-text label, then one line per decision field, each value escaping LF, `\`, and every character outside the slot's allowed set as `\u{XXXX}`, never rejected or truncated. Narrowed on 2026-11-22 (Decisions asked, Restarted round 3 advisory): each entry labels its decision text as untrusted; the format is #611's to design | strong | trust: it frames strain text as data and keeps it from starting a line |
| R2-3, Seams between the part designs, item 14: `control/digest/` joins claim integrity's `control/` list, with mode 0700 and the `lstat` checks of Lair state root; claim integrity's "the one local item that cannot be rebuilt" reads as one of two. Narrowed on 2026-11-22 (Decisions asked, Restarted round 3 advisory): `control/digest/` in the `control/` list and the one-of-two reading stay, now in all three of claim integrity's statements; the mode, checks and creation are #611's to design | strong | trust: it applies the existing folder checks to the new folder |
| C2-2, Failure modes Budget overrun: 80 is the work-call cap and 83 the hard total, with #607's engine test of the 83 | strong | none: it names strain launch's existing "Agent-call cap" |
| R2-5, State and ownership, the Labels row: the user may remove a label-only `lair:review` to release it | strong | merge path: it names the merge lane's existing release of a label-only hold; no merge gate changes |
| R2-6: integration review IDs in Decisions asked are prefixed "integration", and the ADR-0045 amendment "the circuit breaker counts invalid results" names the integration design review round 3 | strong | ADR amendment: wording only, in an amendment this pull request adds |
| R2-7, the opening paragraphs and Seams item 6: the overlord adds #646's design to the Initiative line of #604, #608 and #612 | strong | none: a body edit that keeps every other byte, made later and reversible |
| R2-8, the release-train Decisions bullet and Seam order: #606 and #612 are not claimable while #647 is open, and the pull request that lands the settling entry closes #647 and stales this record | strong | none |
| R2-4: the tables before restarted round 1 keep their always-ask screens, which name what each decision touches, and gain a Recommendation strength column; the restarted rounds' tables give the recommendation strength and what each decision touches | strong | none |
| Seams between the part designs, item 14, the decision digest: it states the digest's two extensions of frozen part designs, clean-up under strain launch's Lifecycle step 5 also waiting for the entry, and `control/digest/` in claim integrity's `control/` list, created by Start; built by #611, which writes the entry, and #608, which builds the clean-up wait and the folder's creation; the Component, the digest row, Seams item 7, Component "Strain result and liveness" and the Failure modes row point to it. Narrowed on 2026-11-22 (Decisions asked, Restarted round 3 advisory): item 14 states only the `control/` list and the one-local-item extensions, built by #611 after #608, which builds no digest wait | strong | none: it states in one Seams item the extensions the digest design already made, with no new behavior |

Restarted round 3's calls, each taken on a strong recommendation; the digest's narrowing was also asked as the round-cap advisory and answered A (Decisions asked, Restarted round 3 advisory):

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| The decision digest narrowed to its requirement: one file per run under `control/digest/`, written before the run's clean-up removes its result file, each entry labeling its decision text as untrusted strain output, never read back by the Lair, and a session's digest the set of entries #611 attributes to that session; #611 designs the rest during its build, and the overrides of frozen part designs it needs land through a dated Amendments entry; Seams item 14 keeps only the `control/` list and the one-local-item statements, read as one of two in all three places; the review restarts at round 1 | strong | ADR amendment and trust: it edits in place the ADR-0045 amendment of 2026-11-22 on the digest, which this pull request adds and which is not yet on trunk, and moves the digest's escaping and crash safety to #611, keeping the untrusted label and the containment under `control/`; no PRD scope, credential or merge-path change |
| Restarted R3-2: the ADR-0045 amendment of 2026-11-22 on the digest credits the user only with the digest's status, answer A to restarted R1-2, and its narrowing, answer A after restarted round 3; the solution design's digest Decisions bullet says that amendment records the digest's status and #611 designs the rest | strong | ADR amendment: wording only, in an amendment this pull request adds |
| Restarted R3-8: the What it touches column marks restarted R1-1 and R1-9 as restarted R2-5 is marked, and the integration tables' cells read "since integration round 3: integration C3-1" | strong | none |

Second restart round 1's calls, each the recommended fix of a finding, a strong recommendation taken and listed for veto under ADR-0046 decision 8 as amended on 2026-11-22; none was asked, except C1-1's budget, first asked with a weak recommendation and then taken on the data (Decisions asked, Second restart round 1 budget):

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| C1-1, the PRD's Further Notes: budgets start at 6 hours of wall clock and 80 work agent calls, 83 in total, per run, replacing the PR #602 baseline as the starting point, from 94 measured delivery runs; the Budget overrun row notes the PRD names them | strong | PRD scope and acceptance criteria: the starting budget values the Budgets and recovery criterion ends a run on |
| R1-1, Seams item 13: a remediation run's stall detection is the idle signal with both stall rules, and the merge lane's stall window from `started_at` no longer applies | strong | none: a remediation run is ended as a delivery run is; no merge gate changes |
| R1-2, Seams items 4 and 15: a re-claim's start checks run before the claim marker; a refusal or a `start_moved` end hands off with a handoff marker, whose reasons join claim integrity's handoff reasons, and the breaker skips it. Superseded by second restart R2-2: the breaker counts it | strong | none: it applies strain launch's existing `lair:handoff`; no merge gate changes |
| R1-3, Seams item 1: a parked remediation end marker carries only the park's `key` and `type`, the park text only in the question block | strong | trust: it keeps strain text out of a signed payload, as claim integrity's invariant requires |
| R1-4, Seams item 1: the park marker of a park on a remote branch also signs the parked `branch` and `head`, the re-claim's pre-image. Refined by second restart R2-1 | strong | trust: two validated tokens join a signed payload |
| R1-5, Seams item 16: the queue report prints readiness-check codes from #615's closed set and strain launch's reasons from their closed list | strong | none |
| R1-6, Seams item 7: `unpushed_head` is not written to GitHub; the kept worktree is the record | strong | none |
| R1-7, Seams item 9: the claim's branch is the result's, else the kept worktree's, else the pull request falls under the merge lane's recorded residual | strong | merge path: it names which pull request a batch-review route labels; no merge gate changes |
| R1-8, Seams item 14: #611 designs the note of an `--admin` merge, written at the merged exit | strong | none |
| R1-9, Components "Strain result and liveness" and "Unattended autonomy level": the builders named | strong | none |
| R1-10, the PRD's Budgets and recovery criterion: a remediation run that reaches its agent-call budget sends its pull request to batch review | strong | PRD acceptance criteria: wording only; it names the existing route |
| R1-2 follow-on, Seams items 4, 8 and 15: a run-end handoff writes its labels, then a handoff marker that reuses the claim's nonce, then the outcome marker last; one test, a `failed` outcome marker whose nonce a counting handoff marker also carries, lets the breaker skip it and the reconciler map it to `lair:handoff`; an admission-time refusal keeps claim integrity's claim sequence order. Superseded by second restart R2-2: the breaker counts it | strong | trust: a signed handoff marker's nonce may now be a claim's, overriding claim integrity's "which no claim marker records" for it; no payload field is added |
| R1-2 follow-on, Seams item 15: the pull request of a run-end handoff takes item 9's `lair:review` route, as a `failed` delivery run's does | strong | merge path: it applies an existing batch-review route; no merge gate changes |

Second restart round 2's calls, each the recommended fix of a finding or, in the last row, the diminishing-returns advisory's recommendation, a strong recommendation taken and listed for veto under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Standing rule clarification); none was asked:

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| R2-1, Seams item 1: every park whose parked result's branch is on the remote at its head, a re-claim run's park included, signs the parked `branch` and `head`, and #609 reads the pre-image from the park marker of the claim whose counting outcome marker is the issue's latest, with outcome `parked` | strong | trust: the same two validated tokens join the signed payload of one more kind of park |
| R2-2, Seams items 4 and 15: the breaker counts a run-end handoff as the `failed` outcome it records, and item 15's one test serves only the reconciler's mapping to `lair:handoff` | strong | none: the breaker's set again matches the PRD's Stop controls criterion and ADR-0045; no merge gate changes |
| R2-3, Seams item 15: the handoff clause of claim integrity's counting rule, restated for both handoff nonces, which #605's verifier accepts | strong | trust: it states which nonce a signed handoff marker may carry; no payload field is added |
| R2-4, Seams item 16: strain launch's reasons print under stage `admission` | strong | none |
| R2-5, Seams item 14: #611 designs the `--admin` merge note's crash safety and its place relative to the exit marker | strong | none |
| R2-6: the lead-in of Second restart round 1's calls names C1-1's budget as first asked | strong | none |
| R2-7, Seam order: #608's Component heading(s) cell adds "Strain result and liveness" | strong | none |
| The diminishing-returns advisory after round 2: keep going to round 3, the last under the cap | strong | none: the round cap and the pass rule are unchanged |

Second restart round 3's calls, each the recommended fix of a finding or, in the last row, the diminishing-returns advisory's recommendation at the round cap, a strong recommendation taken and listed for veto under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Standing rule clarification); none was asked:

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| R3-1: the lead-in of Second restart round 2's calls names its last row as the diminishing-returns advisory's recommendation and cites the standing rule | strong | none |
| R3-2, Seams item 1: the parked `branch` and `head` are signed for a park that pushed commits, or a park of a run whose start kind is re-claim or remediation, whose start commit the remote held at launch; when the remote has moved since, the next re-claim's moved-head check hands the issue off with reason `branch-moved` | strong | trust: it states by start kind which park signs the same two validated tokens; no payload field is added |
| The diminishing-returns advisory after round 3, at the round cap: restart the review at round 1, with the second restarted review's rounds and findings kept under History | strong | none: the round cap and the pass rule are unchanged |

Third restart round 1's calls, each the recommended fix of a finding, a strong recommendation taken and listed for veto under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Design-decision rule update); none was asked. C1-1, rejected as a repeat of a recorded decision, is not a call of this round (History, Third restarted review findings):

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| R1-1, Seams items 2 and 8: a pull request whose one remediation ended `parked` goes to batch review at its `complete` re-claim's run end, `lair:review` on the issue and the pull request, then a review marker with the new reason `remediation-spent`, then the run-end marker last, a route #610 builds on #609's re-claim run end, its test case landing with whichever of #609 and #610 merges second; the CI-red rule's step 1 reads any start marker for the pull request, under any claim | strong | merge path: such a pull request is never merged by the Lair and never holds the lane without `lair:review`, as strain launch's rule that every change after the one remediation goes to a human already requires; no merge gate changes |
| R1-2, Seams item 4: the merge lane's R14, its #611 Verification case and Seam order row, and the counted set of claim integrity's "Run-outcome to label mapping" are also replaced for invalid results; #611's breaker cases land in `tools/test_lair_claim.sh` | strong | none: it names the part-design text the breaker's one set already replaces |
| R1-3, Verification strategy: #609's marker-selection and park-signing cases move to `tools/test_lair_tick.sh`; `tools/test_lair_strain.sh` keeps the push of the strain record's pre-image | strong | none |
| R1-4, Seam order: a re-claim passes the snapshot's trunk commit to the readiness check, never the parked head, and the #615 comment records it for that initiative's amendment of ADR-0046 decision 3 | strong | ADR amendment: it records, for the idea-to-ready initiative to amend, that ADR-0046 decision 3's spawn commit does not hold for a re-claim; ADR-0046 is not edited here |
| R1-5, Seam order: #608's ADRs cell adds ADR-0046 decision 3 | strong | none |

Third restart round 2's calls, each the recommended fix of a finding or, in the last row, the diminishing-returns advisory's recommendation, a strong recommendation taken and listed for veto under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Standing rule clarification); none was asked:

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| C2-1, Seams items 2 and 8: the `remediation-spent` route writes its review marker only when the pull request has no review marker under any claim, as the merge lane's Write order states; an existing review marker keeps holding it, and the labels and the run-end marker land either way | strong | merge path: the pull request stays held and is never merged by the Lair; it applies the merge lane's existing Write order; no merge gate changes |
| R2-1, Verification strategy: the item 2 case states that a red CI result under the new claim starts no run and writes no second review marker, held by the merge lane's step 4 | strong | none |
| R2-2, Seams item 4: the merge lane's Decisions bullet "The breaker counts only `failed`, `crashed`, `stalled` and `timed-out`" is also replaced for invalid results | strong | none: it names part-design text the breaker's one set already replaces |
| R2-3, Seam order: #608's ADRs cell names ADR-0046 decisions 3 and 4 | strong | none |
| The diminishing-returns advisory after round 2: keep going to round 3, the last under the cap | strong | none: the round cap and the pass rule are unchanged |

First re-review round 1's calls, each the recommended fix of a finding, a strong recommendation taken and listed for veto under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Standing rule clarification); first re-review R1-T1 was asked (Decisions asked, Round 1, finding R1-T1 (2026-11-24)). The IDs are the first re-review's (History, First re-review findings):

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| First re-review R1-1 to R1-7, each fixed now as a contained fix in the solution design's Amendments entry "2026-11-24, Lair re-review round 1" | strong | scope: first re-review R1-2 names strain containment in the sections the join left, and first re-review R1-1, R1-4, R1-6 and R1-7 add to the entry; trust: first re-review R1-3 carries ADR-0045's Amendment 2026-11-24 on #607 into the solution design; no ADR is edited, no credential or merge-path change |

First re-review round 2's calls, each taken on a strong recommendation and listed for veto under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Standing rule clarification); the narrowing was asked as the round's diminishing-returns advisory and answered 1 (Decisions asked, Round 2 diminishing-returns advisory (2026-11-25)). The IDs are the first re-review's (History, First re-review findings):

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| The narrowed requirement's wording: Start refuses a checkout that shares a store with any checkout the user works in | strong | trust, scope: it states the requirement answer B leaves; the mechanism is #608's to design |
| #608 is the builder and designer of the mechanism, through a dated Amendments entry before build | strong | scope: the mechanism moves from this design to a slice that builds it |
| First re-review R2-T1 disposed `fixed` by removing the defective text, with its scope moved to #608 | strong | scope: #608's mechanism design must make the bootstrap crash-safe and recoverable |
| First re-review R2-5's simplification: decision 8 waives no architectural gate in `unattended` until #607 designs a signal | strong | merge path: no gate is waived; #607 may add a waiver with its own signal |
| First re-review round 1's R1-T1 application calls (the clone path, the record, the HTTPS clone and the codes) were superseded by the narrowing, so they are not listed as calls of that round | strong | trust, credentials: the HTTPS clone and its credential handling move to #608's design with the rest of the mechanism |

First re-review round 3's calls, each taken on a strong recommendation and listed for veto under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Standing rule clarification); none was asked. The IDs are the first re-review's (History, First re-review findings):

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| First re-review R3-1's fix: the Decisions asked entry "Round 1, finding R1-T1 (2026-11-24)" gains its narrowing of 2026-11-25, and the entry "Round 2 diminishing-returns advisory (2026-11-25)" says first re-review R2-6 is fixed in this record | strong | none: it corrects this record's bookkeeping |
| First re-review R3-T1 rejected: a round's fixes land after it and the next confirming round checks them, and round 3 was that pass for round 2's fixes | strong | scope: ADR-0046's review process; no ADR is edited, no trust, credential or merge-path change |
| The diminishing-returns advisory after first re-review round 3, at the round cap: restart the re-review at round 1 under the standing rule, with the first re-review's rounds and findings kept under History: 2026-11-25 | strong | scope: ADR-0046's review process; the round cap and the pass rule are unchanged |

Restarted re-review round 1's calls, each taken on a strong recommendation and listed for veto under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Standing rule clarification); none was asked. The IDs are this restarted re-review's (Findings):

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| R1-1 to R1-7, each fixed now as a contained fix in the solution design's Amendments entry "2026-11-25, restarted Lair re-review round 1" | strong | trust: R1-1 puts the proxy-up read in the tick as a guard on claims and remediation, and R1-3 gates a strain-written branch name before it reaches the rescue command; scope: R1-2 assigns the proxy, relay and forwarder to #604 and their start, stop and check to #608, and R1-4 widens the Snapshot rule to any change adding a field the readiness check reads; none for R1-5, R1-6 and R1-7; no ADR is edited, no credential or merge-path change |
| R1-T1 rejected as a repeat of the maintainer's answer 1 (Decisions asked, Round 2 diminishing-returns advisory (2026-11-25)), its added cases moved to #608's scope | strong | scope: the checkout-isolation mechanism stays #608's to design, through a dated Amendments entry before build |

Restarted re-review round 2's calls, each taken on a strong recommendation and listed for veto under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Standing rule clarification); none was asked. The IDs are this restarted re-review's (Findings):

| Decision | Recommendation strength | What it touches |
| --- | --- | --- |
| R2-1 to R2-4, each fixed now, R2-1 to R2-3 as contained fixes in the solution design's Amendments entry "2026-11-25, restarted Lair re-review round 2" and R2-4 in this record | strong | scope: R2-1 adds a claim integrity override, a proxy found down at the step-5 re-take ends the attempt with no write and no count; none for R2-2, R2-3 and R2-4; no ADR is edited, no trust, credential or merge-path change |
| R2-T1 rejected as a repeat of first re-review R3-T1, rejected and recorded (Decisions taken, listed for veto, First re-review round 3's calls) | strong | scope: round 2 is the confirming round, at the commit carrying round 1's fixes |
| Keep going to round 3 per the diminishing-returns advisory after round 2 | strong | scope (ADR-0046 process): the round count, within the 3-round cap |

## Decisions asked

- **Design-decision rule update.** The user's rule update of 2026-11-22, landed on `main` by PR #649 as the ADR-0046 amendment of 2026-11-22 to decision 8 and merged into this branch at `b9ca37df`. A design-stage decision with a strong recommendation is taken and listed for veto whatever it touches: PRD scope or acceptance criteria, an amendment of an accepted ADR, a trust-boundary, credential or merge-path change. Only a decision with a weak or absent recommendation and an action that is irreversible now, outside the unmerged pull request, are asked. This record lists each taken decision with its recommendation strength and what it touches, in every table (Decisions taken, listed for veto). Every restarted round 2 fix had a strong recommendation, so none was asked.

- **Second restart round 1 budget.** The budget question of second restart C1-1 was first asked with a weak recommendation. The user asked for data. With the 94-run data under second restart C1-1's Findings note (History, Second restarted review findings), the recommendation became strong, 6 hours and 80 work agent calls, and it was taken under the user's standing rule (Standing rule clarification) and listed for veto (Second restart round 1's calls).

- **Standing rule clarification.** The user's clarification of 2026-11-22, given with the answer to the Restarted round 3 advisory below: a strong recommendation is taken and listed for veto, not asked, in every case, a split or restart decision at the round cap included. Applied after the second restarted review's round 3: its restart at the round cap was taken, not asked (Second restart round 3's calls).

- **Restarted round 1 questions.** Tier A, asked after the restarted review's round 1. The user answered "Go" on 2026-11-22.
  - The question: "Approve these three changes? (1) R1-2, option A: widen ADR-0045's 2026-11-21 amendment to decision 2 with a dated amendment that names the decision digest file beside the marker key as a local item GitHub cannot give again. (2) R1-8: change the PRD's Post-PR feedback criterion to 'Review findings or a red CI result on an open Lair pull request start at most one remediation run for it, and none while the Lair is halted.' (3) R1-3: open the issue 'Lair design: release-train decisions' as a native blocker on #606, to settle the fragment format, release cadence and release trigger."
  - Answer: "Go". Applied: the ADR-0045 amendment of 2026-11-22, "the decision digest is a local item GitHub cannot give again", with the digest row under the solution design's State and ownership; the PRD's Post-PR feedback criterion; and #647, filed on 2026-11-22, with the solution design's Seam order and issue edits naming its native link on #606.

- **Restarted round 2 advisory.** The diminishing-returns advisory (D35), asked after the restarted review's round 2. The user first asked whether option B would prevent unattended work, was told #611 is built in a normal session before the Lair exists, and then answered "A" on 2026-11-22.
  - The question: "What should happen next? A: Keep going and run round 3, the last allowed. (recommended, medium) B: Narrow the claim: keep the digest crash/recovery rules as a requirement and leave their detail to #611. C: Accept what's left as recorded residuals and run round 3 only on what's left."
  - Answer: "A". Round 3, the last under the cap, runs next.

- **Restarted round 3 advisory.** The diminishing-returns advisory (D35), asked after the restarted review's round 3, which reached the 3-round cap. The user answered "A" on 2026-11-22.
  - The question: "What should happen next? A: narrow the digest to a requirement, move crash safety, entry format, recovery, session grouping and the clean-up wait to #611; fix R3-2 and the label consistency; restart at round 1. (recommended, strong) B: fix all 9 and restart. C: stop, leave draft, separate digest design issue."
  - Answer: "A". Applied: the solution design's Amendments entry of 2026-11-22, restarted review round 3 and digest narrowing; the ADR-0045 amendment of 2026-11-22 on the digest, edited in place; and this review's restart at round 1.

- **Round 1 questions.** Tier A, asked after this design's integration review round 1. The user answered "1A 2A 3A" on 2026-11-22.
  - Q1 (integration R1-1, R1-2, R1-5, R1-12), containment. Answer A: #604 builds per-platform containment. On Linux, the strain sandbox that hides the Lair's processes also hides `control/` and every tmux socket, and the Lair's own window runs on its own tmux server no strain can reach. On macOS, a `sandbox-exec` profile denies `control/` and the Lair's tmux sockets. A #608 preflight probe `sandbox` makes the Lair claim nothing when containment cannot be confirmed, stopping with `strain_env_preflight`, probe `sandbox`. The merge lane's cache moves under `control/`. Strain launch's "tmux global environment" residual does not apply under containment. #604's probe cases, on each supported platform: from inside a strain, `tmux -S <socket> list-sessions` and `new-window` fail for each Lair socket, and Bash cannot read `control/marker.key`, append to `control/halt` or delete it.
  - Q2 (integration R1-18), docs pull requests and the auto tier. Answer A: `docs/prds/`, `docs/initiatives/` and `docs/adr/` go into the auto-tier script's built-in floor, built by #605, so ADR-0046's "A docs pull request never takes the Lair's auto tier (#623)" holds in every consumer project. #623's overlap with #608, the readiness-check call at claim, is recorded in Seam order with who builds it.
  - Q3 (integration R1-17, R1-20, R1-22), issue-body edits. Answer A: the edits are made after the clean round, before the pull request leaves draft: #604's stale acceptance criteria; #606's Dependencies gaining #605, with the native link; and the `## Design` blocks of #604 to #612. The solution design's Seam order states this obligation. The overlord makes these edits; they are still to be made.

- **Round 2 direction.** The user directed "Take recs" on 2026-11-22: each integration round 2 finding takes its reviewer's recommended fix, and each such call is listed under Decisions taken, listed for veto. This answers the always-ask screens of integration C2-1 and R2-1, which narrow a strain's reach.

- **Round 3 questions.** Tier A, asked after this design's integration review round 3, which reached the 3-round cap. The user replied "Take recs" on 2026-11-22, taking the recommended option of each.
  - Q1 (integration R3-1 to R3-4, R3-6 and C3-1), "How should the review proceed?" Options: A, "split strain containment into its own part design under a new issue with its own review; item 6 goes back to what the three part designs approved and points at the new design; fix the other round-3 findings here, naming invalid results in the PRD and ADR-0045; restart this PR's review at round 1 with current rounds moved to History" (recommended); B, "drop cross-strain isolation claims, keep strain launch's residual"; C, "raise the cap, run round 4". Answer A: #646, Lair design: strain containment, is filed and blocks #604, #608 and #612; the PRD Stop controls criterion and the ADR-0045 amendment of 2026-11-22, "the circuit breaker counts invalid results", name `invalid-result`; this review restarts at round 1.
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

- **Round 1, finding R1-T1 (2026-11-24).** Asked after the first re-review's round 1, on the local review tool's high finding first re-review R1-T1, "Writable shared Git stores violate the repository's structural concurrency rule" (P16). The maintainer answered B.
  - The question: how to dispose of first re-review R1-T1. Options: A, reject and keep the residual; B, the Lair runs only from its own clone, siblings keep sharing the store as a residual; C, per-strain clones, a redesign of ADR-0017's model.
  - Answer: "B". Applied: the solution design's Amendments entry "2026-11-24, Lair re-review round 1" states that the Lair runs only from a clone it makes, so the user's unpushed work never shares a store with strains. Siblings sharing the store stays strain containment's residual "the shared object and ref store", under ADR-0017's worktree model. First re-review R1-T1 is rejected with that reason. Narrowed on 2026-11-25 (Decisions asked, Round 2 diminishing-returns advisory (2026-11-25)): the entry now states the requirement, and the mechanism is #608's.

- **Round 2 diminishing-returns advisory (2026-11-25).** The diminishing-returns advisory (D35), asked after the first re-review's round 2. The maintainer answered 1 on 2026-11-25.
  - The question: what to do with the round's findings, 7 of 10 of which come from first re-review R1-T1's clone mechanism. Options: (1) narrow the claim and hand the rest to the slice that builds it as a tracked follow-up; (2) accept the rest as recorded residuals; (3) keep going.
  - Answer: "1". Narrow answer B to a requirement and hand the clone mechanism to #608 ([issue comment](https://github.com/brenpike/hivemind/issues/608#issuecomment-7162158378)). Simplify first re-review R1-3. Applied: first re-review R2-1 to R2-4, R2-7 and R2-8 deferred to #608; first re-review R2-T1, R2-5 and R2-9 fixed in the solution design, and R2-6 in this record; First re-review round 2's calls under Decisions taken, listed for veto.

## Residuals

- **A part-design edit with no Amendments entry stales no stamp.**
  - Scope: an edit to [strain launch](strain-launch-design.md), the [merge lane](merge-lane-design.md), [claim integrity](claim-integrity-design.md), or #646's design once it joins as a fourth part design (solution design, opening paragraphs), that lands with no dated entry under the solution design's Amendments.
  - Ground: the stamp path allowlist (idea-to-ready design, Contracts and seams, "Slice design section format") admits no other file of this folder than the solution design and this record, so no part design can be stamped.
  - Bounded impact: a docs pull request never takes the Lair's auto tier (solution design, Component "Merge lane and auto tier"). The bound is the reviewer of the part-design pull request, when there is one, who sees the edit in its diff; a pull request that edits only a part design leaves this record unchanged. With `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a Bot approval with no human review, the residual the idea-to-ready design records under D24.
  - Recorded: here, and under Reviewed documents.

## History: 2026-11-22

This section keeps four earlier reviews of this design: the first review, from here to its decisions asked; then the integration review, under Integration review below; then the restarted review, under Restarted review below; and then the second restarted review, under Second restarted review below.

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

The review of the integrated design under #633, rounds 1 to 3 of 2026-11-22, kept as it stood after round 3. Its front matter then held `verdict` `fail`, every open count 0, `rounds` 3 and `clean_round` `false`. Round 3 reached the 3-round cap without converging on strain containment, and the user split containment into its own part design, #646, Lair design: strain containment (Decisions asked, Round 3 questions). The containment rows R1-1, R1-2, R1-5, R1-12, R2-1 and C2-1 keep their dispositions, each with a note naming the split: R3-1 is fixed by removing the claims they added from this design, and #646 designs the mechanism. The integration review's finding IDs are cited as "integration R1-n"; the restarted review's IDs start again at R1-1 and are cited as "restarted R1-n" (Restarted review).

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

### Restarted review

The restarted review of this design, rounds 1 to 3 of 2026-11-22, kept as it stood after round 3. Its front matter then held `verdict` `fail`, every open count 0, `rounds` 3 and `clean_round` `false`. Round 3 reached the 3-round cap, recurring on the decision digest, and per the user's answer A (Decisions asked, Restarted round 3 advisory) the digest is narrowed to a requirement, #611 designs the rest, and this review restarts at round 1. The digest rows R1-2, R2-1, R2-2, R2-3 and C2-1 keep their dispositions, each with a note naming the narrowing. The restarted review's finding IDs are cited as "restarted R1-n"; the second restarted review's IDs start again at R1-1 and are cited as "second restart R1-n" (Second restarted review).

### Restarted review rounds

#### Restarted round 1

- **Date:** 2026-11-22.
- **Reviewed commit:** `7ac4387dff0d7e46d07650e20abc55b532aa55be`.
- **Scope:** the whole PRD, solution design and ADR-0045, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`, covering every angle. Model: `claude-opus-5-5`. It raised 11 findings, R1-1 to R1-11: 0 critical, 0 high, 4 medium and 7 low.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. The tool returned 0 findings in the diff. It dropped 1 item outside the diff, the merge lane's breaker list under Lifecycle "Stage 4: halt and circuit breaker", which Seams between the part designs, item 4, already replaces by its explicit override. The pass's reviewer agent added one note, C1-1, low.
- **Result:** 0 critical, 0 high, 4 medium and 8 low, all new. The user approved R1-2 option A, R1-8 and R1-3 with "Go" on 2026-11-22 (Decisions asked, Restarted round 1 questions); the other findings take the recommended fix, each listed for veto. Every finding is disposed below, so none is open. The round raised new findings, so it is not clean, and a confirming round follows.

#### Restarted round 2

- **Date:** 2026-11-22.
- **Reviewed commit:** `08488abe891b69357e68307a78d068a482653448`.
- **Scope:** a confirming round: the change since `7ac4387d` and round 1's fixes, in the PRD, the solution design, ADR-0045 and `CONTEXT.md`, with the part designs read as the text they supersede. The merge of `main` at `b9ca37df` into this branch after that commit, PR #649, touched no reviewed document.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`. Model: `claude-opus-5-5`. It raised 8 findings, R2-1 to R2-8: 0 critical, 0 high, 2 medium and 6 low.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, an angle review. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It raised 2 findings, C2-1, high, and C2-2, medium.
- **Result:** 1 high, 3 medium and 6 low, all new. R2-1, R2-2 and R2-3 are fixed together with C2-1, in one digest design. Under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Design-decision rule update), every finding takes its recommended fix, each a strong recommendation, listed for veto. Every finding is disposed below, so none is open, and no high is deferred. The round raised new findings, so it is not clean, and round 3, the last under the cap, follows.
- **Diminishing-returns advisory:** signal 1, recurrence: the digest (R1-2: R2-1, R2-2, R2-3, C2-1), the Budget overrun row (R1-6: C2-2), the Labels row (R1-9: R2-5), the integration citations (R1-11: R2-6), the #646 join (R1-4: R2-7) and the release-train text (R1-3: R2-8); signals 2 and 3 did not fire; the maintainer's answer: A, keep going to round 3.

#### Restarted round 3

- **Date:** 2026-11-22.
- **Reviewed commit:** `bbeecb4dc8ecd2d7fd71fae4d57326d26189126b`.
- **Scope:** a confirming round: the change since `08488abe` and round 2's fixes, in the PRD, the solution design, ADR-0045 and `CONTEXT.md`, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`. Model: `claude-opus-5-5`. It raised 8 findings, R3-1 to R3-8: 0 critical, 0 high, 2 medium and 6 low.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, an angle review. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It raised 1 finding, C3-1, medium: an `unverified` digest entry omitted the session token.
- **Result:** 0 critical, 0 high, 3 medium and 6 low, all new. The round is not clean, and the 3-round cap is reached. Per the user's answer A of 2026-11-22 (Decisions asked, Restarted round 3 advisory), the decision digest is narrowed to a requirement and #611 designs the rest, so R3-1, R3-3 to R3-7 and C3-1 are deferred to #611; R3-2 and R3-8 are fixed; and the review restarts at round 1. Every finding is disposed below, so none is open.
- **Diminishing-returns advisory:** signal 1, recurrence: the digest (R2-1, R2-2, R2-3, C2-1: R3-1, R3-3 to R3-7, C3-1); signal 2, severity falling (1 high to 0 high) while each fix added text; signal 3, partly: R3-6 bounded by the containment of `control/`; the maintainer's answer: A, narrow the digest to a requirement and restart.

### Restarted review findings

| ID | Round | Angle | Severity | Disposition | Note |
| --- | --- | --- | --- | --- | --- |
| R1-1 | 1 | B | medium | fixed | The Crash and Stall rows and the Lifecycle run-end bullet sent a pull request to `lair:review` by strain launch's rows alone, against Seams items 2 and 9. Fixed: solution design, Failure modes, the Crash and Stall rows, a delivery run's route narrowed by Seams item 9 and a remediation run under the merge lane's "Fix-up run lost in flight" with the claim end stopping every merge (Seams item 2); Lifecycle, the "every run end and exit" bullet names Seams items 2 and 9. |
| R1-2 | 1 | A | medium | fixed | The decision digest had no State and ownership row, and as a local item GitHub cannot give again it conflicted with ADR-0045 decision 2 and its 2026-11-21 amendment. Fixed per the user's approval of option A: solution design, State and ownership, the digest row at `control/digest/<session-id>.txt` and the intro sentence; Component "Decision digest and circuit breaker", the Decisions bullet, the Verification strategy case and #611's ADRs cell; [ADR-0045](../../adr/0045-lair-software-factory.md), the amendment of 2026-11-22, "the decision digest is a local item GitHub cannot give again"; `CONTEXT.md`, the **Lair** entry. The digest sits under `control/`, so #646's containment requirement covers it. Round 2 (C2-1) made it one file per run, `control/digest/<run-id>.txt`. Narrowed after round 3 (Decisions asked, Restarted round 3 advisory): the solution design states only the digest's requirement, and #611 designs the rest. |
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
| R2-1 | 2 | confirm | medium | fixed | The digest write could come before the route's last marker and race clean-up, and nothing said what happens when it fails. Fixed with C2-1: solution design, Component "Decision digest and circuit breaker", the write after the run's route has written its last marker (Seams between the part designs, item 8), or at run end, marked `unverified`, when run end writes no outcome marker under claim integrity's "Reader failure direction"; clean-up under strain launch's Lifecycle step 5 waits for it; a tick that finds a run whose last marker has landed and whose worktree is not cleaned up writes the entry, then cleans up; a failed write keeps the worktree and result file, the queue report names the run, and the next tick retries; Component "Strain result and liveness" and Seams item 7; Failure modes, the row "Digest write fails or is cut off"; Verification strategy, #611's digest cases. Narrowed after round 3 (Decisions asked, Restarted round 3 advisory): the solution design states only the digest's requirement, and #611 designs the rest. |
| R2-2 | 2 | confirm | medium | fixed | A digest entry had no fixed form, so strain text could forge an entry or a header. Fixed with C2-1: solution design, State and ownership, the digest row, a fixed-template header line of validated tokens with a label marking the decision text as untrusted strain output, then one line per decision field with a fixed indent and label, each value escaping LF, `\`, and every character outside the slot's allowed set as `\u{XXXX}`, never rejected or truncated; Verification strategy, the case of a decision holding LF and a forged header, ESC, CR and U+202E. Narrowed after round 3 (Decisions asked, Restarted round 3 advisory): the solution design states only the digest's requirement, and #611 designs the rest. |
| R2-3 | 2 | confirm | low | fixed | The digest folder was not in claim integrity's `control/` list, with no mode or `lstat` check. Fixed with C2-1: solution design, Seams between the part designs, item 14, `control/digest/` joins that list, created by Start with mode 0700 under the `lstat` checks of Lair state root, and claim integrity's "the one local item that cannot be rebuilt" reads as one of two; State and ownership, the paragraph after the table, points to it. Narrowed after round 3 (Decisions asked, Restarted round 3 advisory): the solution design states only the digest's requirement, and #611 designs the rest. |
| R2-4 | 2 | confirm | low | fixed | The digest design's calls were not listed for veto. Fixed: this record, Decisions taken, listed for veto, Restarted round 2's calls, with the recommendation strength and what each touches. |
| R2-5 | 2 | confirm | low | fixed | The Labels row did not name the user's release of a label-only `lair:review`. Fixed: solution design, State and ownership, the Labels row, citing the merge lane's Contracts and seams "Write order" and Lifecycle "Run outcome to labels". |
| R2-6 | 2 | confirm | low | fixed | Decisions asked and ADR-0045 cited integration review IDs and rounds bare. Fixed: this record, Decisions asked, Round 1 questions, Round 2 direction and Round 3 questions, each ID list prefixed "integration"; [ADR-0045](../../adr/0045-lair-software-factory.md), the amendment of 2026-11-22, "the circuit breaker counts invalid results", names the integration design review round 3. |
| R2-7 | 2 | confirm | low | fixed | When #646's design joins, nothing named the Initiative line of #604, #608 and #612, where the slices name their part designs. Fixed: solution design, the opening paragraphs and Seams between the part designs, item 6, the overlord adds #646's design to that line, a body edit that keeps every other byte. |
| R2-8 | 2 | confirm | low | fixed | The release-train text said neither #606 nor #612 is ready until the settling Amendments entry closes #647, but an entry closes no issue, an open blocker stops only a claim, and that entry stales this record. Fixed: solution design, the release-train Decisions bullet, neither is claimable while #647 is open (ADR-0046 decision 4), and the settling entry stales the review record, so neither passes the readiness check until its re-review; Seam order, the pull request that lands that entry closes #647; this record, the parent design's row on the release-train decisions. |
| C2-1 | 2 | review | high | fixed | The digest append was not crash-idempotent, had no entry framing and no atomic write, and did not mark strain text as untrusted. Fixed in one digest design with R2-1, R2-2 and R2-3: solution design, State and ownership, the digest row at `control/digest/<run-id>.txt`, one file per run, written through a temporary file in the same folder, a flush and a rename, so a retry by any session rewrites the same run's file and no partial entry is visible, and the Lair never reads an entry back; Component "Decision digest and circuit breaker", Decisions, Verification strategy and the Failure modes row "Digest write fails or is cut off"; [ADR-0045](../../adr/0045-lair-software-factory.md), the amendment of 2026-11-22, "the decision digest is a local item GitHub cannot give again", names the per-run files and the write after the last marker. Narrowed after round 3 (Decisions asked, Restarted round 3 advisory): the solution design states only the digest's requirement, and #611 designs the rest. |
| C2-2 | 2 | review | medium | fixed | The Budget overrun row's agent-call cap did not match strain launch's "Agent-call cap", which allows 80 work calls and 83 calls in all. Fixed: solution design, Failure modes, Budget overrun, 80 as the work-call cap and 83 as the hard total, citing strain launch, Components "Launch inputs", "Agent-call cap"; Verification strategy, #607's engine test of the hard maximum 83. |
| R3-1 | 3 | confirm | medium | deferred | The clean-up wait for the digest entry was assigned to #608, which is built before #611 writes any entry. The design now states only the digest's requirement, and #611 designs the rest: solution design, Seams between the part designs, item 14, built by #611 after #608, with the clean-up wait landing with #611; Seams item 7 and Component "Strain result and liveness" name the wait #611 builds. Deferred to #611. |
| R3-2 | 3 | confirm | medium | fixed | The ADR-0045 digest amendment credited the user with mechanics the user's answer did not cover, and the solution design called the write order it records not ADR-worthy. Fixed: [ADR-0045](../../adr/0045-lair-software-factory.md), the amendment of 2026-11-22, "the decision digest is a local item GitHub cannot give again", credits the user with the digest's status as a local item, answer A to restarted R1-2, and its narrowing to a requirement, answer A after restarted round 3, and no mechanics; solution design, Decisions, the digest bullet says that amendment records the digest's status and #611 designs the rest. |
| R3-3 | 3 | confirm | low | deferred | The `unverified` marking dropped the condition that the run's claim marker does not count, so a transient read could mark an entry `unverified`. The design now states only the digest's requirement, and #611 designs the rest, the `counted` or `unverified` marking among it (solution design, Seams between the part designs, item 14). Deferred to #611. |
| R3-4 | 3 | confirm | low | deferred | Seams item 14 read only one of claim integrity's three statements of the one local item as one of two, and claim integrity's queue report had no line for a failed digest write. The design now states only the digest's requirement, and #611 designs the rest: item 14 reads all three statements as one of two, and #611 designs how the queue report reports a failed write, with its override of claim integrity's "Queue report" through a dated Amendments entry. Deferred to #611. |
| R3-5 | 3 | confirm | low | deferred | The recovery rule keyed on a worktree not cleaned up, so it missed runs with no worktree and repeated for worktrees kept for good. The design now states only the digest's requirement, and #611 designs the rest, the recovery of an interrupted write and the clean-up wait among it (solution design, Seams between the part designs, item 14). Deferred to #611. |
| R3-6 | 3 | confirm | low | deferred | The temporary file was reopened and truncated rather than created exclusively, a leftover could stay in the folder, and Start's checks of `control/digest/` were unstated; bounded by the containment of `control/` (Seams between the part designs, item 6). The design now states only the digest's requirement, and #611 designs the rest, the write's crash safety, temporary-file hygiene and the folder's mode, checks and creation among it (solution design, Seams item 14). Deferred to #611. |
| R3-7 | 3 | confirm | low | deferred | Per-run files did not say how they form the per-session digest of ADR-0045 decision 14 and the PRD. The design now states only the digest's requirement, and #611 designs the rest: a session's digest is the set of entries #611 attributes to that session (solution design, State and ownership, the digest row; the ADR-0045 digest amendment), and #611 designs the attribution. Deferred to #611. |
| R3-8 | 3 | confirm | low | fixed | The "What it touches" column marked the same kind of change differently. Fixed: this record, Decisions taken, listed for veto, Restarted round 1's calls, restarted R1-1 "merge path: it names existing routes; no merge gate changes" and restarted R1-9 "trust, merge path: it names existing channels and holds; no boundary or gate changes", matching restarted R2-5; the integration tables' cells for integration R1-10 and R2-4 read "since integration round 3: integration C3-1". |
| C3-1 | 3 | review | medium | deferred | An `unverified` digest entry omitted the session token, so it belonged to no session's digest. The design now states only the digest's requirement, and #611 designs the rest, the attribution of entries to sessions among it (solution design, Seams between the part designs, item 14). Deferred to #611. |

### Second restarted review

The second restarted review of this design, rounds 1 to 3 of 2026-11-22, kept as it stood after round 3. Its front matter then held `verdict` `fail`, every open count 0, `rounds` 3 and `clean_round` `false`. Round 3 reached the 3-round cap with 2 low findings, both fixed, and under the user's standing rule (Decisions asked, Standing rule clarification) the conductor's strong recommendation was taken: the third restarted review restarts at round 1 (Decisions taken, listed for veto, Second restart round 3's calls). The second restarted review's finding IDs are cited as "second restart R1-n"; the third restarted review's IDs start again at R1-1.

### Second restarted review rounds

#### Second restart round 1

- **Date:** 2026-11-22.
- **Reviewed commit:** `659554a95fb32d7e1ae036354297b47fdc1a79ca`.
- **Scope:** the whole PRD, solution design and ADR-0045, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`, covering every angle. Model: `claude-opus-5-5`. It raised 10 findings, R1-1 to R1-10: 0 critical, 1 high, 4 medium and 5 low.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It raised 1 finding, C1-1, medium.
- **Result:** 0 critical, 1 high, 5 medium and 5 low, all new. Under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Design-decision rule update), every finding takes its recommended fix, each a strong recommendation, listed for veto; C1-1's became strong with the run data the user asked for (Decisions asked, Second restart round 1 budget). Every finding is disposed below, so none is open, and the high is fixed. The round raised new findings, so it is not clean, and a confirming round follows.

#### Second restart round 2

- **Date:** 2026-11-22.
- **Reviewed commit:** `b600e13b88c63c5bef60d4f6a389f076a1d70a2f`.
- **Scope:** a confirming round: the change since `659554a9` and round 1's fixes, in the PRD, the solution design, ADR-0045 and `CONTEXT.md`, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`. Model: `claude-opus-5-5`. It raised 7 findings, R2-1 to R2-7: 0 critical, 0 high, 2 medium and 5 low.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It returned 0 findings, clean.
- **Result:** 0 critical, 0 high, 2 medium and 5 low, all new. Under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Design-decision rule update), every finding takes its recommended fix, each a strong recommendation, listed for veto (Second restart round 2's calls). Every finding is disposed below, so none is open. The planner pass raised new findings, so the round is not clean, and round 3, the last under the cap, follows.
- **Diminishing-returns advisory:** signal 1, recurrence: the re-claim's pre-image (R1-4: R2-1), the run-end handoff (R1-2: R2-2, R2-3), the queue report reasons (R1-5: R2-4) and the `--admin` merge note (R1-8: R2-5); signal 2, severity falling (1 high to 0 high) while round 1's fixes added text, Seams items 15 and 16 among them; signal 3 did not fire; the maintainer's standing rule: a strong recommendation is taken (Decisions asked, Standing rule clarification); the conductor's recommendation, strong: keep going to round 3.

#### Second restart round 3

- **Date:** 2026-11-22.
- **Reviewed commit:** `21452859717d61ec82ace96aa9fd0d36754acbec`.
- **Scope:** a confirming round: the change since `b600e13b` and round 2's fixes, in the solution design and this record, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`. Model: `claude-opus-5-5`. It raised 2 findings, R3-1 and R3-2: 0 critical, 0 high, 0 medium and 2 low.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, an angle review. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It returned 0 findings, clean.
- **Result:** 0 critical, 0 high, 0 medium and 2 low, all new. Under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Design-decision rule update), each finding takes its recommended fix, a strong recommendation, listed for veto (Second restart round 3's calls). Every finding is disposed below, so none is open. The planner pass raised new findings, so the round is not clean, and the 3-round cap is reached. Under the user's standing rule (Decisions asked, Standing rule clarification), the conductor's strong recommendation is taken: the review restarts at round 1.
- **Diminishing-returns advisory:** signal 1, recurrence: the park payload's `branch` and `head` (R1-4, R2-1: R3-2); signal 2, severity falling to low only (2 medium in round 2, none in round 3) while round 2's fixes added more text than they removed; signal 3 did not fire; the maintainer's standing rule: a strong recommendation is taken, including a restart at the round cap (Decisions asked, Standing rule clarification); the conductor's strong recommendation: restart at round 1.

### Second restarted review findings

| ID | Round | Angle | Severity | Disposition | Note |
| --- | --- | --- | --- | --- | --- |
| R1-1 | 1 | B | high | fixed | A remediation run kept the merge lane's stall window measured from the start marker's `started_at`, so an active run could end `stalled`, against the idle signal of Seams item 13. Fixed: solution design, Seams between the part designs, item 13, a remediation run's stall detection is the idle signal with both stall rules, and the merge lane's `started_at` stall window no longer applies in Components "Fix-up runs", the Failure modes row "Fix-up run lost in flight", Decided for you ("A fix-up run is supervised from its markers", R15), its Seam order #610 row and its #610 test; Failure modes, the Stall row; Decisions, the idle-signal bullet; Verification strategy, the replaced #610 case and a `tools/test_lair_tick.sh` case of an active remediation run past 30 minutes that is not ended. |
| R1-2 | 1 | A | medium | fixed | A re-claim refusal ran after the claim marker, so claim integrity's crash rule ended it `crashed` and a re-claim's `start_moved` end took the merge lane's `lair:failed`, both counted, against strain launch's `lair:handoff`. Fixed: solution design, Seams between the part designs, new item 15, the re-claim checks run before the claim marker as admission checks, a refusal writes a handoff marker with reason `branch-moved`, `start-config-changed` or `design-superseded`, then `lair:handoff`, `unpushed_work` stays not claimed, and a `start_moved` end, a run-end handoff, takes `lair:handoff` under a handoff marker that reuses the claim's nonce, written before the outcome marker, and its pull request `lair:review`; item 4, the breaker skips that end; item 8, its write order and the claim-sequence order of an admission-time refusal; Failure modes, the Crash row, a remediation run's budget clause replaced by item 3; Lifecycle, the refused-start bullet and stage 2; Component "Park answer round trip"; Decisions; Verification strategy, the `tools/test_lair_tick.sh` cases. Superseded in part by R2-2: the breaker counts a run-end handoff as its `failed` outcome. |
| R1-3 | 1 | B | medium | fixed | Seams item 1 brought the merge lane's park record into a parked remediation run's signed end marker, against claim integrity's invariant Lair-written text and the 4096-byte payload cap. Fixed: solution design, Seams item 1, that end marker carries only the park's `key` and `type`, the park text goes only into the park marker's question block, and the merge lane's "or the park record when parked" no longer applies; Verification strategy, #610's case. |
| R1-4 | 1 | A | medium | fixed | The re-claim's pre-image, the parked branch and head, was recorded nowhere, since claim integrity's park payload carries only `key` and `type`. Fixed: solution design, Seams item 1, the park marker of a park whose branch is on the remote also signs `branch`, under the identifier gate and at most 255 bytes, and `head`, 40 or 64 hex digits, and #609's re-claim reads its pre-image from the issue's latest counting park marker; Component "Park answer round trip"; Verification strategy, the `tools/test_lair_strain.sh` case. Refined by R2-1. |
| R1-5 | 1 | A | medium | fixed | The queue report printed #615's snake_case readiness codes and strain launch's reasons as `unknown-reason` under claim integrity's reason-code pattern. Fixed: solution design, Seams between the part designs, new item 16, a readiness-check code prints as itself when its stem is in the idea-to-ready design's closed set and its suffix meets that contract's placeholders, a code over 200 bytes as its stem then `:too-long`, and strain launch's reasons from their closed list; Decisions, the queue report bullet and a new bullet; Verification strategy, #608's cases. |
| R1-6 | 1 | A | low | fixed | Strain launch's `unpushed_head` had no place to be written, since clean-up comes after the outcome marker. Fixed: solution design, Seams item 7, `unpushed_head` is not written to GitHub, the kept worktree is the record, and the queue report reads it locally. |
| R1-7 | 1 | B | low | fixed | Seams item 9's "the claim's branch" had no source for a run that left no result. Fixed: solution design, Seams item 9, the result's `branch` when the result passes the schema check, else the kept worktree's checked-out branch read at run end, else the merge lane's "Recorded residual: a pull request no result names". |
| R1-8 | 1 | A | low | fixed | Seams item 14 did not name the digest note of an `--admin` merge, written at the merged exit after the digest row's timing. Fixed: solution design, Seams item 14, #611's list adds that note, written at the merged exit after the run's entry, and the digest row's timing governs only the run's entry. |
| R1-9 | 1 | A | low | fixed | Component "Strain result and liveness" did not name the builder of crash and stall detection, and Component "Unattended autonomy level" did not name the engine's park record, key and agent-call cap. Fixed: solution design, both Components. |
| R1-10 | 1 | A | low | fixed | The PRD's Budgets and recovery criterion did not cover a remediation run's agent-call end, which sends its pull request to batch review. Fixed: the PRD, Acceptance Criteria, Budgets and recovery. |
| C1-1 | 1 | review | medium | fixed | The PRD started budgets from the PR #602 baseline of about four hours and 54 agents, against strain launch's 6 hours and 80 work agent calls, 83 in all. The user asked for data: the overlord measured 94 past standard-delivery workflow runs in this repository's Claude Code logs, runs with at least 5 agent calls from 2026-10-22 to 2026-11-22. Agent calls: median 21, p75 36, p90 54, p95 67, max 82; 7 runs exceeded 54 and 1 exceeded 80. Active hours, the union of agent activity with user waits excluded: median 1.0, p90 2.4, p95 2.9, max 6.5; 4 runs exceeded 4 hours and 1 exceeded 6. A run that hits a cap ends failed and counts toward the breaker, so a cap near p90 fails about 1 run in 13. Fixed: the PRD, Further Notes, budgets start at 6 hours and 80 work agent calls, 83 in total, replacing the #602 baseline; solution design, Failure modes, the Budget overrun row notes the PRD names these values. |
| R2-1 | 2 | confirm | medium | fixed | Seams item 1 signed the parked `branch` and `head` only for a park that pushed commits or a remediation run's park, so a re-claim run that parked with no new commits left no pre-image, and "the issue's latest counting park marker" was not bound to the latest claim. Fixed: solution design, Seams between the part designs, item 1, the park payload carries `branch` and `head` for every park whose parked result's branch is on the remote at its head, a re-claim run's park included, and #609 reads the pre-image from the park marker of the claim whose counting outcome marker is the issue's latest, with outcome `parked`; Component "Park answer round trip"; item 15, its first bullet; Decisions, the park bullet; Verification strategy, #609's `tools/test_lair_strain.sh` case, a re-claim run that parks with no commits past its start commit signs that branch and head, and the next re-claim continues there. |
| R2-2 | 2 | confirm | medium | fixed | Seams item 4 skipped a run-end handoff, a breaker set that neither the PRD's Stop controls criterion nor ADR-0045 states, while strain launch counts a first claim's `start_moved`. Fixed: solution design, Seams between the part designs, item 4, the skip bullet is removed, so its set again matches the PRD and ADR-0045; item 15, the breaker counts a run-end handoff as the `failed` outcome it records, as it counts a first claim's `start_moved` end (strain launch, Components "Start points", "Handling by start kind"), and the one test serves only the reconciler's mapping to `lair:handoff`, which never re-adds `lair:failed`; Decisions, the re-claim bullet; Verification strategy, the re-claim case "the breaker counts it". |
| R2-3 | 2 | confirm | low | fixed | Item 15 said claim integrity's counting rule held for a run-end handoff marker while one of its clauses did not apply. Fixed: solution design, Seams between the part designs, item 15, a bullet restates the handoff clause of claim integrity's Contracts and seams, "Counting rule", for this design: a handoff marker carries the nonce of the claim attempt the handoff stopped, by a scan or a re-claim refusal at admission, or, for a run-end handoff, the nonce of a counting claim marker on the same issue; #605's verifier accepts both. |
| R2-4 | 2 | confirm | low | fixed | Item 16 did not say under which stage strain launch's reasons print. Fixed: solution design, Seams between the part designs, item 16, they print under stage `admission` in claim integrity's issue line `issue <number>: <stage> <code>`; Verification strategy, #608's queue report case asserts the stage. |
| R2-5 | 2 | confirm | low | fixed | Item 14's #611 list named the `--admin` merge note but not its crash safety. Fixed: solution design, Seams between the part designs, item 14, #611 also designs the note's crash safety, a stop between the merge call and the note included, and its place relative to the exit marker. |
| R2-6 | 2 | confirm | low | fixed | The lead-in of Second restart round 1's calls said none was asked, while C1-1's budget was first asked. Fixed: this record, Decisions taken, listed for veto, that lead-in names C1-1's budget, first asked with a weak recommendation and then taken on the data. |
| R2-7 | 2 | confirm | low | fixed | #608 builds crash and stall detection (Component "Strain result and liveness"), but its Component heading(s) cell in Seam order did not name that heading. Fixed: solution design, Seam order, #608's row adds "Strain result and liveness". |
| R3-1 | 3 | confirm | low | fixed | The lead-in of Second restart round 2's calls called every row the recommended fix of a finding, though its last row is the diminishing-returns advisory's recommendation, and cited no rule for taking it. Fixed: this record, Decisions taken, listed for veto, that lead-in names the last row as the advisory's recommendation and cites Decisions asked, Standing rule clarification. |
| R3-2 | 3 | confirm | low | fixed | Seams item 1 stated the park payload's condition as a park whose parked result's branch is on the remote at its head, then glossed it with park kinds that do not all meet it: a re-claim or remediation run that parks with no commits pushes nothing, and the remote may have moved since its launch. Fixed: solution design, Seams between the part designs, item 1, the rule by start kind, a park that pushed commits (strain launch, Components "Start points", "A park after commits pushes"), or a park of a run whose start kind is re-claim or remediation, whose start commit the remote held at launch, carries `branch` and `head`, and when the remote has moved since, the next re-claim's moved-head check hands the issue off with reason `branch-moved` (item 15); Decisions, the park bullet; Verification strategy, #609's case, a run of start kind re-claim that parks with no commits past its start commit. |

## History: 2026-11-24

### Third restarted review

The third restarted review of this design, rounds 1 to 3 of 2026-11-22, kept as they stood when the review passed. Its front matter then held `verdict` `pass`, every open count 0, `rounds` 3 and `clean_round` `true`, and stamps at the blobs of `66c4858d38cae6b287c2816dadc17b0afc457047`. The third restarted review's finding IDs are cited as "third restart R1-n"; this re-review's IDs start again at R1-1.

### Third restarted review rounds

#### Third restart round 1

- **Date:** 2026-11-22.
- **Reviewed commit:** `2fd1b055416ceb9b4cf2fa80cf9c94bc8ef87f2a`.
- **Scope:** the whole PRD, solution design and ADR-0045, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`, covering every angle. Model: `claude-opus-5-5`. It raised 5 findings, R1-1 to R1-5: 0 critical, 0 high, 2 medium and 3 low.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, an angle review. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It raised 1 finding, C1-1, high.
- **Result:** 0 critical, 1 high, 2 medium and 3 low. R1-1 to R1-5 are new, and under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Design-decision rule update) each takes its recommended fix, a strong recommendation, listed for veto (Decisions taken, listed for veto, Third restart round 1's calls). C1-1 contests a recorded decision of claim integrity, so it is a repeat and is rejected with that reason, not fixed and not asked. Every finding is disposed below, so none is open, and the high is rejected with a reason. The round raised new findings, so it is not clean, and a confirming round follows.

#### Third restart round 2

- **Date:** 2026-11-22.
- **Reviewed commit:** `56eddef438963d06b3378888d899e8e2d30c0395`.
- **Scope:** a confirming round: the change since `2fd1b055` and round 1's fixes, in the solution design and this record, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`. Model: `claude-opus-5-5`. It raised 3 findings, R2-1 to R2-3: 0 critical, 0 high, 1 medium and 2 low. It judged the C1-1 rejection valid.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, an angle review. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It raised 1 finding, C2-1, rated high by the tool and medium by the pass's reviewer agent, recorded as medium.
- **Result:** 0 critical, 0 high, 2 medium and 2 low, all new. Under ADR-0046 decision 8 as amended on 2026-11-22 (Decisions asked, Design-decision rule update), each finding takes its recommended fix, a strong recommendation, listed for veto (Decisions taken, listed for veto, Third restart round 2's calls). Every finding is disposed below, so none is open. The round raised new findings, so it is not clean, and round 3, the last under the cap, follows.
- **Diminishing-returns advisory:** signal 1, recurrence: the `remediation-spent` route (R1-1: R2-1, C2-1), item 4's list of text replaced for invalid results (R1-2: R2-2) and #608's ADRs cell (R1-5: R2-3); signal 2 did not fire: severity flat at medium and low, 2 medium in each round, round 1's one high a rejected repeat; signal 3, partly: C2-1's case, a remediation that parks on an already-held pull request, is one the merge lane's Write order already bounds; the maintainer's standing rule: a strong recommendation is taken (Decisions asked, Standing rule clarification); the conductor's strong recommendation: keep going to round 3.

#### Third restart round 3

- **Date:** 2026-11-22.
- **Reviewed commit:** `66c4858d38cae6b287c2816dadc17b0afc457047`.
- **Scope:** a confirming round: the change since `56eddef4` and round 2's fixes, in the solution design and this record, with the part designs read as the text they supersede.
- **Planner pass:** reviewer `hivemind:cerebrate`, a fresh read-only pass with `Memory context: none`. Model: `claude-opus-5-5`. It raised 0 findings and found every round-2 fix closed.
- **Local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, an angle review. Model: the tool's own default (ADR-0042 decision 7), from another vendor than the planner pass's. It raised 0 findings and approved.
- **Result:** clean round. No pass raised a new finding or found an earlier finding unfixed, and no finding is open at any severity, so the review passes under the pass rule of ADR-0046 decision 7.

### Third restarted review findings

| ID | Round | Angle | Severity | Disposition | Note |
| --- | --- | --- | --- | --- | --- |
| R1-1 | 1 | A | medium | fixed | A pull request whose one remediation ended `parked`, recorded again by a later `complete` re-claim, could never meet strain launch's Tick-order condition, so it never merged and held the lane with no `lair:review`; and the CI-red rule's step 1 read a start marker only under the current claim. Fixed: solution design, Seams between the part designs, item 2, the re-claim's run end sends that pull request to batch review, `lair:review` on the issue and the pull request, then a review marker with the new reason `remediation-spent`, then the run-end marker last, matching strain launch's rule that every change after the one remediation goes to a human, a route #610 builds on #609's re-claim run end, and the CI-red rule's step 1 reads any start marker for the pull request, under any claim; item 8, that route's write order and its builder; Lifecycle, the run-end bullet; Decisions, the item 2 bullet; Verification strategy, the write-boundary cases and a `tools/test_lair_tick.sh` case of a remediation park, its answer and a `complete` re-claim, which ends at batch review with `remediation-spent`, never a merge and never a lane hold without `lair:review`, and of a red CI result under the new claim, which ends `checks-failed`, a case of both #609 and #610 landing with whichever merges second. |
| R1-2 | 1 | A | medium | fixed | Seams item 4 named the merge lane's Breaker column and Failure modes clauses as replaced for invalid results, but not the other lists that skip them, and no test covered its counted set. Fixed: solution design, Seams between the part designs, item 4, also names as replaced for invalid results the merge lane's Decided for you, R14, its #611 case under Verification strategy, its #611 row under Seam order, and the counted set of claim integrity's "Assumptions about #631", "Run-outcome to label mapping"; Verification strategy, #611's breaker cases in `tools/test_lair_claim.sh`: `invalid-result` counts for a delivery run and for a remediation run under a live claim, a run this session ended whose outcome marker does not count counts, `no-pr`, `not-launched` and `blocked` are skipped, and a run-end handoff counts as `failed`. |
| R1-3 | 1 | A | low | fixed | #609's marker-selection and park-signing cases read recorded GitHub states but sat in `tools/test_lair_strain.sh`. Fixed: solution design, Verification strategy, those cases move to `tools/test_lair_tick.sh`, against recorded GitHub states, and `tools/test_lair_strain.sh` keeps only the case that the strain record's pre-image reaches the push. |
| R1-4 | 1 | A | low | fixed | ADR-0046 decision 3 says the Lair passes the readiness check the commit it spawns the strain from, which for a re-claim is the parked head, not the trunk commit claim integrity passes. Fixed: solution design, Seam order, a cross-epic seam states that for a re-claim the Lair passes the snapshot's trunk commit, never the parked head, and the #615 issue-edit comment records it for that initiative's amendment of ADR-0046 decision 3 and of the idea-to-ready design's Component "Lair admission". |
| R1-5 | 1 | A | low | fixed | #608 builds the readiness-check call at claim, but its ADRs cell did not name ADR-0046 decision 3. Fixed: solution design, Seam order, #608's ADRs cell adds ADR-0046 decision 3. |
| C1-1 | 1 | review | high | rejected | The finding held that resetting the marker key makes existing Lair state unreadable, citing ADR-0045's amendment of 2026-11-21, the marker key is the one local file the Lair cannot rebuild. Rejected as a repeat of a recorded decision: the [claim integrity review record](claim-integrity-review-record.md), Decisions taken (listed for veto), records that a candidate under another `kid` is foreign, never counting and never halting, so a key reset needs no stored list of retired keys while a replaced key or a second Lair is still caught by the `lair:claimed` rule, and that the retired id is not stored; the [claim integrity design](claim-integrity-design.md) states the same under Decisions, Lifecycle (the user's key reset, which ends the old key's strains and handles each named issue first, a remaining `lair:claimed` halting with `marker-missing`) and Failure modes, "Key replaced or invalid". The halt is the designed fail-safe, and changing it is a change to a frozen part design. Listed for the user before the merge as a repeat rejection. |
| R2-1 | 2 | confirm | medium | fixed | The item 2 case under Verification strategy said the CI-red rule, applied to a red CI result on the pull request under the new claim, ends at batch review with reason `checks-failed`, which is false: the pull request is already held on its review marker, and no route writes a second one. Fixed: solution design, Verification strategy, the item 2 case, a red CI result on that pull request under the new claim starts no run and writes no second review marker, since the merge lane's step 4 holds it on its review marker and the remediation step dispatches nothing, the pull request having a dispatch marker and `lair:review`. Item 2's reading of the CI-red rule's step 1, a start marker under any claim, stays. R1-1's Note keeps its round 1 text as history. |
| R2-2 | 2 | confirm | low | fixed | Seams item 4's list of text replaced for invalid results left out the merge lane's Decisions bullet "The breaker counts only `failed`, `crashed`, `stalled` and `timed-out`". Fixed: solution design, Seams between the part designs, item 4, names that bullet; Amendments, the entry of 2026-11-22, third restarted review round 2, mentions it. |
| R2-3 | 2 | confirm | low | fixed | #608's ADRs cell named ADR-0046 decision 3 but not decision 4, the native blocked-by links its admission reads. Fixed: solution design, Seam order, #608's ADRs cell ends "ADR-0044 decision 17; ADR-0046 decisions 3 and 4". |
| C2-1 | 2 | review | medium | fixed | Rated high by the tool; the pass's reviewer agent rated it medium, and it is recorded as medium. Seams items 2 and 8 had the `remediation-spent` route always write a review marker, while item 8 adopts the merge lane's Write order, under which a route writes no review marker when the pull request already has one on the claimed issue, under any claim, and a remediation can park on an already-held pull request (merge lane, Lifecycle "Run outcome to labels"; Failure modes "Parked fix-up run"). Fixed: solution design, Seams between the part designs, item 2, the route writes the `remediation-spent` review marker only when the pull request has no review marker under any claim, an existing review marker keeps holding it, as the merge lane's Write order states, and the labels and the run-end marker land either way; item 8, the same; Lifecycle, the run-end bullet; Decisions, the item 2 bullet; Verification strategy, a case of a remediation run that parks on a pull request that already has a review marker under the old claim, then a `complete` re-claim: no second review marker, `lair:review` applied, no merge, with a tick stopped after the labels or after the check for an existing review marker. |

## History: 2026-11-25

### First re-review

The first re-review of this design, rounds 1 to 3 of 2026-11-24 and 2026-11-25, over the change since `66c4858d`, kept as it stood after round 3. Its front matter then held `verdict` `fail`, every open count 0, `rounds` 3 and `clean_round` `false`, and the third restarted review's stamps. Round 3 reached the 3-round cap with no design finding, its one low fixed in this record and its one high rejected, and under the user's standing rule (Decisions asked, Standing rule clarification) the conductor's strong recommendation was taken: the re-review restarts at round 1 (Decisions taken, listed for veto, First re-review round 3's calls). The first re-review's finding IDs are cited as "first re-review R1-n", "first re-review R2-n" and "first re-review R3-n"; this restarted re-review's IDs start again at R1-1.

### First re-review rounds

#### First re-review round 1

- **Date:** 2026-11-24.
- **Reviewed commit:** `116241952cb82c7ce61cd0dd10dd61c3d2b26437`, merge-base `eb40ed9804b7ad92498ed42a8478b8edd3311e82`.
- **Scope:** the Review rule's round-1 scope, the change since `66c4858d`: #668's ADR-0045 amendment, "Amendment 2026-11-24"; #672's solution design Amendments entry of 2026-11-24; the PRD's `**UI:**` line. Each is checked against the whole PRD and solution design, with the part designs read as the text they supersede.
- **Pass 1, planner pass:** reviewer `hivemind:cerebrate`, on cerebrate's own model (`model=default`), a fresh read-only pass with `Memory context: none`. It raised 7 findings, R1-1 to R1-7: 0 critical, 0 high, 4 medium and 3 low.
- **Pass 2, local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, on the tool's own default model (ADR-0042 decision 7), base the merge-base. It raised 1 finding, R1-T1, high.
- **Result:** not clean. Every finding is disposed below, so none is open: R1-1 to R1-7 are fixed, and R1-T1 is rejected on the maintainer's answer B (Decisions asked, Round 1, finding R1-T1 (2026-11-24)). The fixes are in the solution design's Amendments entry "2026-11-24, Lair re-review round 1".
- **Diminishing-returns check:** no signal fired. This is round 1, so no earlier round of this re-review exists for recurrence or trend.

#### First re-review round 2

- **Date:** 2026-11-25.
- **Reviewed commit:** `542411ad8dc34f55c85539481c99b6093d23fa44`, previous round's reviewed commit `116241952cb82c7ce61cd0dd10dd61c3d2b26437`.
- **Scope:** a confirming round over the change since `116241952cb82c7ce61cd0dd10dd61c3d2b26437` and round 1's fixes.
- **Pass 1, planner pass:** reviewer `hivemind:cerebrate`, on cerebrate's own model (`model=default`), a fresh read-only pass with `Memory context: none`. It covered the diff and round 1's fixes, with `unfixed: none`. It raised 9 findings, R2-1 to R2-9: 0 critical, 0 high, 6 medium and 3 low.
- **Pass 2, local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, on the tool's own default model (ADR-0042 decision 7), base the previous round's reviewed commit. It raised 1 finding, R2-T1, high.
- **Result:** not clean. Every finding is disposed below, so none is open: R2-1 to R2-4, R2-7 and R2-8 are deferred to #608 on the maintainer's answer 1 (Decisions asked, Round 2 diminishing-returns advisory (2026-11-25)); R2-5, R2-6, R2-9 and R2-T1 are fixed.
- **Diminishing-returns advisory:** fired after round 2. Recurrence: R1-T1's clone mechanism drew 7 of round 2's 10 findings, and R1-3's fix drew 1. Trend: severity did not fall, a high in each round, while each fix added surface. Options given: (1) narrow the claim and hand the rest to the slice that builds it as a tracked follow-up; (2) accept the rest as recorded residuals; (3) keep going. The maintainer's answer (2026-11-25): 1. Narrow answer B to a requirement and hand the clone mechanism to #608 ([issue comment](https://github.com/brenpike/hivemind/issues/608#issuecomment-7162158378)). Simplify R1-3.

#### First re-review round 3

- **Date:** 2026-11-25.
- **Reviewed commit:** `069d03cbd1040c01d68528cad99c113975783d45`, previous round's reviewed commit `542411ad8dc34f55c85539481c99b6093d23fa44`.
- **Scope:** a confirming round over the change since `542411ad8dc34f55c85539481c99b6093d23fa44` and round 2's fixes.
- **Pass 1, planner pass:** reviewer `hivemind:cerebrate`, on cerebrate's own model (`model=default`), a fresh read-only pass with `Memory context: none`. It covered the diff and round 2's fixes, with `unfixed: none`. It raised 1 finding, R3-1: 0 critical, 0 high, 0 medium and 1 low.
- **Pass 2, local review tool pass:** reviewer the `codex-plugin` preset, through `hivemind:adaptation-cycle`, on the tool's own default model (ADR-0042 decision 7), base the previous round's reviewed commit. It raised 1 finding, R3-T1, high.
- **Result:** not clean. Every finding is disposed below, so none is open: R3-1 is fixed in Decisions asked, and R3-T1 is rejected with its reason. The round raised new findings, so the 3-round cap is reached. Under the user's standing rule (Decisions asked, Standing rule clarification), the conductor's strong recommendation is taken and listed for veto: the re-review restarts at round 1 (Decisions taken, listed for veto, First re-review round 3's calls).
- **Diminishing-returns advisory:** fired at the round cap. Recurrence did not fire on the design: no design text drew a finding. Trend: the design findings fell to zero, and the one low, R3-1, is record bookkeeping from round 2. Bounded edge cases: R3-T1 restates the confirming-round process this round ran. The maintainer's standing rule: a strong recommendation is taken, a restart at the round cap included (Decisions asked, Standing rule clarification); the conductor's strong recommendation: restart at round 1.

### First re-review findings

| ID | Round | Angle | Severity | Disposition | Note |
| --- | --- | --- | --- | --- | --- |
| R1-1 | 1 | A | medium | fixed | #667 changed claim integrity's Snapshot (`blockedBy` numbers and states) with no Amendments entry. Fixed: the entry records it, and Seam order "Cross-epic seams with #614" requires a dated entry for any field #615 adds. |
| R1-2 | 1 | A | medium | fixed | The join updated only the sentences that named #646. Fixed: strain containment is now named, with its governing section, in Components "Strain launch and settings", "Strain result and liveness" and "Controller tick and admission", Seams items 6 and 7, State and ownership, Existing-path coverage, Verification strategy and the Seam order issue edits. |
| R1-3 | 1 | B | medium | fixed | ADR-0045's Amendment 2026-11-24 on #607 was not carried into the solution design. Fixed: it is carried into Component "Unattended autonomy level", the #607 ADRs cell, the Decisions bullet and a Verification strategy case. |
| R1-4 | 1 | A | medium | fixed | The 2026-11-24 entry said containment's review was "not run in this pull request", while containment's local-review fixes (L-2 to L-6, D18, L-8) were also checked by no round. Fixed: the new entry states that those fixes were checked by no round, and corrects the 2026-11-24 entry's clause "which is not run in this pull request". |
| R1-5 | 1 | A | low | fixed | Three statements of the stop "Strain containment cannot be confirmed" named the stop but not the case id. Fixed: "and the case id" added to all three. |
| R1-6 | 1 | A | low | fixed | Part-design citations of PRD line numbers no longer match the PRD after its `**UI:**` line. Fixed: the new entry says they refer to the PRD before its `**UI:**` line. |
| R1-7 | 1 | A | low | fixed | The 2026-11-24 entry made body edits it did not list. Fixed: the new entry names them. |
| R1-T1 | 1 | review | high | rejected | Local review finding `2a58431ec67cd57997e612e667478ec71c07e717d6e7b103eddb5e1768885c16`, "Writable shared Git stores violate the repository's structural concurrency rule" (P16). Rejected on the maintainer's answer B (Decisions asked, Round 1, finding R1-T1 (2026-11-24)): the Lair runs only from a checkout sharing no store with the user's, so the user's unpushed work never shares a store with strains (solution design, Amendments entry "2026-11-24, Lair re-review round 1"). Siblings sharing the store stays strain containment's residual "the shared object and ref store", under ADR-0017's worktree model. Per-strain clones would change ADR-0017's model, `spawn-brood.sh` and `brood-status`. |
| R2-1 | 2 | confirm | medium | deferred | Start's common-dir check admits a linked worktree of the clone, where the user's work would share the strains' store. Reason: the mechanism moved to the slice that builds it (Decisions asked, Round 2 diminishing-returns advisory (2026-11-25), answer 1). #608 |
| R2-2 | 2 | confirm | medium | deferred | The clone step writes outside claim integrity's invariant Lock scope, so two clone steps can race. Reason: as R2-1. #608 |
| R2-3 | 2 | confirm | medium | deferred | Clone-step failures have no recovery path, the record write is not crash-atomic, and no Failure modes rows exist for the codes. Reason: as R2-1. #608 |
| R2-4 | 2 | confirm | medium | deferred | HTTPS clone credentials, no SSH fallback (P26), and the reftable default ref format. Reason: as R2-1. #608 |
| R2-5 | 2 | confirm | medium | fixed | R1-3's "design departure" waiver could not be told apart from brief inputs. Fixed: until #607 designs a signal, decision 8 waives no architectural gate in `unattended`; the Verification case is on inputs only. |
| R2-6 | 2 | confirm | medium | fixed | Round 1's veto list left out the calls made to apply answer B. Fixed: the round-2 veto entry lists the narrowing's calls; the mechanism's calls were removed with it. |
| R2-7 | 2 | confirm | low | deferred | A fresh clone lacks `.claude/settings.local.json`; `brood-status`, the rescue push and start must run in the clone. Reason: as R2-1. #608 |
| R2-8 | 2 | confirm | low | deferred | The Start check has no fixed step relative to the `extensions.refStorage` read. Reason: as R2-1. #608 |
| R2-9 | 2 | confirm | low | fixed | #608's acceptance-criteria edit lacked the checkout requirement. Fixed in Seam order. |
| R2-T1 | 2 | review | high | fixed | Local review finding `316072b38bd403bb30e930911be07844cf5b2eb0752aeb29e2c21ac0754dbce2`, "Clone bootstrap can strand the repository in an unrecoverable half-created state". Fixed: the bootstrap is removed from the design and answer B stays as a requirement. #608's mechanism design must make bootstrap crash-safe and recoverable (its issue comment lists this scope). |
| R3-1 | 3 | confirm | low | fixed | Two Decisions asked "Applied:" lines no longer matched after round 2. (1) "Round 1, finding R1-T1 (2026-11-24)" still described the removed clone. (2) "Round 2 diminishing-returns advisory (2026-11-25)" said R2-6 was fixed in the solution design. Fixed: (1) gains "Narrowed on 2026-11-25 (Decisions asked, Round 2 diminishing-returns advisory (2026-11-25)): the entry now states the requirement, and the mechanism is #608's."; (2) now reads "R2-T1, R2-5 and R2-9 fixed in the solution design, and R2-6 in this record". |
| R3-T1 | 3 | review | high | rejected | Local review finding `32f176f002062ce40e6954bd165fb775ef6a74f939df773228505fb1ec7b9b18`, "Round 2 did not review the changes that dispose its findings". Rejected: under the design-review record format and this record's Review rule, a round's fixes land after it, and the next confirming round checks them. Round 3 is that confirming pass, at `069d03cb`, the commit that carries round 2's fixes. Its cerebrate pass found every round-2 row closed (`unfixed: none`). |
