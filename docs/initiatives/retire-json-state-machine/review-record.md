---
stamps:
  - path: docs/initiatives/retire-json-state-machine/solution-design.md
    blob: 46e74677105b5a7cea24bd6ad067c43e6f3a0765
  - path: docs/adr/0048-retire-json-state-machine.md
    blob: b819e8d4dee726eb3be1dd1065853c1ef2e9f479
verdict: fail
open:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 3
clean_round: false
---

# Design review record: Retire the JSON state machine

The design review has completed three rounds and has not passed. Every finding is fixed, and the user has answered Tier A questions Q7 on D11 and Q8 on D12, and the round-3 cap question. No round has been clean, so `clean_round` is `false`. Round 3 was the last round under the three-round cap (ADR-0046 decision 6). The user answered A to the cap question: narrow the design's Verification strategy, then run one round 4 over that change only, a one-time exception for this initiative. The three-round cap stays the general rule.

The passing record stamps the solution design and ADR-0048. No PRD exists; `docs/prds/retire-json-state-machine.md` is needed before any slice can pass the readiness check. The stamps are the blobs at commit `aa9342a244b13150eb141b42ac566611b6b5f268`, the commit round 1 reviewed; a record with `verdict` `fail` keeps its stamps, and only the passing record re-stamps, to the commit its clean pass reviewed.

## Reviewed documents

- [Solution design: Retire the JSON state machine](solution-design.md)
- [ADR-0048](../../adr/0048-retire-json-state-machine.md): retire the JSON state machine

No PRD is reviewed, since none exists.

## Rounds

### Round 1

Two passes. Neither reviewer wrote the design. Both reviewed commit `aa9342a244b13150eb141b42ac566611b6b5f268`.

- Reviewer `hivemind:cerebrate`. One fresh, read-only pass with `Memory context: none`, covering the whole documents, angles A and B. The model is `opus`, cerebrate's own model (`HIVEMIND_DESIGN_REVIEW_MODEL` unset).
- Local review tool pass, run because the design touches trust boundaries. The tool is the `codex-plugin` default preset (`HIVEMIND_LOCAL_REVIEWER` unset), its model the tool's own. It reviewed the same commit and returned two findings:
  - "Universal question rule overrides the Lair's unattended park semantics": real, fixed by R1-01.
  - "The new journal rule makes pre-merge PR listing the Lair veto channel": partly real, fixed by R1-05.

The round raised 12 findings, R1-01 to R1-12. Two are high (R1-01, R1-03), seven are medium (R1-02, R1-04 to R1-09) and three are low (R1-10 to R1-12). After the fixes, none is open. The two local review tool findings are recorded as R1-T1 and R1-T2.

The overlord also made five consistency edits after the round, listed here for the user's veto: the D2 level-check wording; the phrase "live only in text this design deletes"; the ADR Considered options wording on the journal; the design's line 3 record status; the R1-10 `:30` wording.

### Round 2

A confirming round. Neither reviewer wrote the design. It covers the change since `aa9342a2` and round 1's fixes.

An earlier cerebrate pass at commit `63ff83f2b93b5533981da5b795d3f44d51d269c3`, first recorded here as "Round 2", is an incomplete pass. Its local review tool pass did not run with it, though the design touches trust boundaries (ADR-0046 decision 6), so it yields no round. The user answered A on this question: that pass does not count as a round. Its findings, R2-01 to R2-05, were raised before round 2 and fixed in `2c9a26cd`; they are attributed to round 2 in the Findings table, keeping their IDs.

- Local review tool pass: preset `codex-plugin` (`HIVEMIND_LOCAL_REVIEWER` unset), model the tool's own. Review base `2c9a26cd61227bc3bb2c4fdbfa0bedd6b8c29948`. It ran through the local reviewer's fix loop, which may commit fixes, and returned two findings, recorded as R2-T1 and R2-T2. Both are fixed.
- Reviewer `hivemind:cerebrate`, model `opus`, `Memory context: none`. A fresh, read-only confirming pass over the change since `aa9342a2` and the fixes, run after the tool pass, so it reviewed the tool pass's fixes. It reviewed commit `316261f898f1e8b16ad8b03526adf9da537f9c55` and raised R2-C01 to R2-C03.

The incomplete cerebrate pass raised five findings, R2-01 to R2-05. Three are medium (R2-01 to R2-03) and two are low (R2-04, R2-05). The tool pass raised R2-T1 (high) and R2-T2 (medium). The confirming cerebrate pass raised R2-C01 (medium), R2-C02 (medium) and R2-C03 (low). After the fixes, none is open. Round 1's fixes R1-01 to R1-05, R1-09, R1-11 and R1-12 close their findings; R1-10 was correct, and its `:87` edit exposed R2-03. Round 2 is not clean, so `clean_round` is `false`: its tool pass raised findings, and a round is clean only when every completed pass of it raises no new finding (ADR-0046 decision 6). The verdict is `fail`.

### Round 3

Two passes over the design as it stood after round 2. Neither reviewer wrote the design.

- Local review tool pass: preset `codex-plugin` (`HIVEMIND_LOCAL_REVIEWER` unset), model the tool's own. Review base `4c1df0f6891d4fad68cdb69f5d58ae83121e78c3`, two iterations. It returned R3-T1 (high) and R3-T2 (high). R3-T1 was fixed in `3c584eb0` and R3-T2 in `c094d278`; the narrowing below supersedes both fixes.
- Reviewer `hivemind:cerebrate`, model `opus`, `Memory context: none`. A fresh, read-only pass over the change since `316261f8`, run after the tool pass. It reviewed commit `c094d2782086119508d992d9078ba05624b415a4` and raised R3-01 to R3-03 (medium) and R3-04 (low).

The round raised 6 findings, so it is not clean and the verdict is `fail`. The round is the cap. The user answered A to the cap question, with a strong recommendation: narrow, do not split. The design's Verification strategy now states what each slice must prove and names no check file, name list, scan path or test mechanism; each slice's own design and review builds the checks. D18 keeps only the decision, and D12 stays the one statement of the confirmation rule, which the Verification strategy adds once before its per-slice list. Every round-3 finding is fixed by that narrowing. The overlord also conformed each design decision's screen to ADR-0046 decision 8 as amended 2026-11-22 (the gate reads Promotion Gate clause 1 only, applied to the action taken now), and restructured the taken-decisions table below to carry each decision's recommendation strength and what it touches.

Diminishing-returns advisory: signals: recurrence on the Verification strategy's coverage checks, which R1-07, R2-02 and R2-C01 fixed and R3-T1, R3-01 and R3-02 found again; answer A (user), given to the round-3 cap question: narrow the claim and hand the checks to each slice's own design (ADR-0046 decision 6).

### Round 4

One-time exception approved by the user for this initiative only (answer A to the cap question). The three-round cap stays the general rule. It is recorded here like the Idea to Ready design's round-4 exception (`docs/initiatives/idea-to-ready/review-record.md`, D31 and Q9): it does not change `rounds`, which stays 3, as that round 4 did not (answer Q11 A there), so a passing record still meets the pass rule's `rounds` of 2 to 3 (ADR-0046 decision 7).

Two passes over the change since `c094d278` and round 3's fixes. Neither reviewer wrote the design.

- Local review tool pass: preset `codex-plugin` (`HIVEMIND_LOCAL_REVIEWER` unset), the tool's own model. Review base `d2dada8bb6665488edd9f50ca762013fb93123e3`, 1 iteration. It was clean and returned no findings.
- Reviewer `hivemind:cerebrate`, model `opus`, `Memory context: none`. A fresh, read-only confirming pass over the change since `c094d278` and round 3's fixes. It reviewed commit `d2dada8bb6665488edd9f50ca762013fb93123e3`. On the design and ADR-0048 it raised no findings. On this record it raised R4-01 (medium) and R4-02 (low). Both touch only the record and are fixed in this commit.

A record-only closing check follows: one fresh cerebrate pass (model `opus`, `Memory context: none`) over this record change only, as the Idea to Ready record's round-4 confirming checks did. It is pending. `rounds` stays 3.

## Findings

| ID | Round | Angle | Severity | Disposition | Note |
|---|---|---|---|---|---|
| R1-01 | 1 | B | high | fixed | The level clause covered refused launches only, so a failed started `standard-delivery` run at an unattended level still took an Instinct takeover that asks instead of parking (ADR-0045 decision 6). The level clause now covers both Instinct takeovers, in the design and ADR-0048 decision 2. Also raised by the local review tool pass. |
| R1-02 | 1 | A | medium | fixed | The design claimed ADR-0046 decision 10's guide exception, but the text S4 lands holds none. The design now says that exception lands through its own initiative and S4 keeps it, and the fallback text replaces only the sentences of `:37` it restates. |
| R1-03 | 1 | A | high | fixed | The facts-file check in Trust boundaries was misstated: brood-status keys on the worktree path and uses the manifest `worktree_path` only as an exact-match selector, and spawn-brood checks the worktree it derived. Keying on branch would regress #270. Trust boundaries and the security-policy row now state the check as the code does. |
| R1-04 | 1 | A | medium | fixed | D7 called the scripts' list "the journal" but kept the ledger-era definition. An entry is now the line a script writes under "Decided for you"; the Decision Journal glossary entry and README `:264` agree; the item that forced two named sentences' wording is removed. |
| R1-05 | 1 | B | medium | fixed | The journal's purpose and ADR-0048's bounded impact were false under `HIVEMIND_AUTO_MERGE` and the Lair, where a merge the user does not make can land first. The journal now lives on the pull request because the user reviews the change there, and a veto after such a merge is a revert, with the Lair digest (ADR-0045 decision 14) as the Lair veto channel. Also raised by the local review tool pass. |
| R1-06 | 1 | A | medium | fixed | D12 restated the destructive-fix categories more narrowly than `security-policy.md` (Destructive Fix Confirmation Gate). D12 now applies the gate read at its broadest to every deletion or narrowing, and the slice cells follow. |
| R1-07 | 1 | A | medium | fixed | Existing-path coverage missed live references to the retired engine: the seed-hive grants, `bump-type/SKILL.md`, `spawn-brood/SKILL.md`, `standard-delivery/contract.js`, `route-workflow/SKILL.md`, comments naming `ledger-project.sh` and `tools/test_workflow_scripts.sh`. Rows are added, and the S5 check now scans `plugin/`, `tools/` and `.claude/settings.json` for every retired identifier. |
| R1-08 | 1 | A | medium | fixed | ADR-0048 decision 8 contradicted itself on ADR-0036 decision 9, whose first sentence scopes ADR-0026 to the removed engine. Decision 8 now says a clause that scopes an ADR to the current engine is history and is not amended, while ADR-0036 decisions 9 and 10 stand as written (taken reading, listed for veto below). |
| R1-09 | 1 | B | medium | fixed | D11 was a decision the design took itself, but ADR-0046 decision 8 always asks a trust-boundary change. Answered: Q7 A (user). D11 moves two rules, the facts and injection-scan rule and the PR head rule, to `## Safety Rails`, and drops the `expect_commit` sentence, since the input gates of `hivemind:open-plan-pr` and `hivemind:push-branch` own it. D11 is no longer taken by the design. |
| R1-10 | 1 | A | low | fixed | Code-truth errors: the PR head rule is also stated at `overlord.md:29`; the definition-graph cases run to `standard-delivery.test.mjs:4913`; the brood-status sentence on claimed columns is at `SKILL.md:56`; the autonomy table's site coverage was misdescribed for `step_stop`, `gate_rerun` and the `analysis-only` script site. All are corrected. |
| R1-11 | 1 | A | low | fixed | ADR-0018's Status line was not updated. S5 now changes it to superseded by ADR-0048, as a shared-document item. |
| R1-12 | 1 | B | low | fixed | The residual bounded impact for a waiting brood child assumed remote control. It now says the session stays alive and reachable through its `attach:` line, or through remote control when enabled. |
| R1-T1 | 1 | review | high | fixed | Local review tool pass: the same defect as R1-01, fixed by it. |
| R1-T2 | 1 | review | medium | fixed | Local review tool pass: partly the same defect as R1-05, fixed by it. |
| R2-01 | 2 | confirm | medium | fixed | R1-08's fix declared ADR-0026 inert, an unasked amendment of an accepted ADR (ADR-0044, ADR-0045 and ADR-0046 amend ADR-0026 for remaining paths, and the design keeps its Promotion Gate). ADR-0048 decision 8 and the Decisions taken row now say only that the clause is history and is not amended. |
| R2-02 | 2 | confirm | medium | fixed | The S5 "No retired reference" check could not pass: `next-wave` matched kept text, and `.hivemind/runs/.` matched the CHECK 16 canary glob. The check now lists `next-wave.sh`, `hivemind:next-wave` and `skills/next-wave`, and Existing-path coverage gains a row for the canary. The check now keys on D10's removal list (R2-C01). |
| R2-03 | 2 | confirm | medium | fixed | The Components bullet on `overlord.md:29` kept the third sentence while the proposed fallback text deleted the last two. Both now agree: the fallback replaces the second sentence, and the third loses only "first checks out the PR's head branch, then". |
| R2-04 | 2 | confirm | low | fixed | R1-06's fix was applied only partly: "such an item", the destructive-fix row of Failure modes, the S5 check bullet and the seed order rows still used the narrower reading. Each now names the items D12 names, read at its broadest, and S1 to S4 link D12. |
| R2-05 | 2 | confirm | low | fixed | The record departed from ADR-0046 decisions 6 to 8: it held no stamps on a failing record, did not name each pass's model or tool, pointed to the design for the decisions taken, and did not record the local review tool findings. It now stamps the commit round 1 reviewed, names the models and the tool, lists each taken decision, and records R1-T1 and R1-T2. The design's line 3 follows. |
| R2-T1 | 2 | review | high | fixed | Destructive gate did not cover security-policy guards the design removes; D12 now points to the gate's categories read at their broadest, with no list of its own (commit 7752569892380c6f1949f9f468769729080d4c83). |
| R2-T2 | 2 | review | medium | fixed | Round 2 was counted without its trust-boundary tool pass; answered A by the user: that pass yields no round. |
| R2-C01 | 2 | confirm | medium | fixed | The S5 "No retired reference" check carried an identifier list that contradicted the CHECK 16 canary row, and the grant sites in `settings-merge.sh`, `tools/test_shared_libs.sh` and README `:66`, `:76` were missed. The check now carries no list of its own and keys on D10's removal list; the canary and `test_shared_libs.sh` rows no longer claim a live navigator keeps the `.hivemind/runs/.` prefix; README `:66` and `:76` gain items. |
| R2-C02 | 2 | confirm | medium | fixed | D12's enforcement path did not exist for planned slice work: the destructive-fix gate covers review fixes only, and a drone running an assigned deletion step does not stop. Answered: Q8 A. D12 now states the rule once: the user confirms each covered item in the main session before the slice's run starts. Every other site points to D12. |
| R2-C03 | 2 | confirm | low | fixed | The round-count question was missing from the record's Decisions asked. It and Q8 are now listed. |
| R3-T1 | 3 | review | high | fixed | Local review tool pass: the S5 retired-reference check had no defined name set and missed documents the design edits. Fixed in `3c584eb0`, then superseded: the narrowing names no check and no name set. |
| R3-T2 | 3 | review | high | fixed | Local review tool pass: D18 pinned six of the twelve `hivemind:github-review-loop` outcomes by hand (root cluster: coverage checks built on hand-kept name lists). Zoom-out `c094d278`, then superseded: D18 states the decision only, and the slice designs the test. |
| R3-01 | 3 | confirm | medium | fixed | The coverage checks read names from D10, which holds no name list; backtick spans include live replacements; the S4 check kept its own list; `request.raw` is a live router field. Fixed by the narrowing: Verification strategy names no check, list or identifier. |
| R3-02 | 3 | confirm | medium | fixed | The S5 scan covered paths the slice cannot clean (stamped Lair documents, ADR-0045, test sources that pin an absence, gitignored `.hivemind/runs/`), and some scanned paths never run the check at the PR gate. Fixed by the narrowing: the S5 requirement covers what the slice changes, apart from text a later re-review owns (D19) and text that pins an absence. |
| R3-03 | 3 | confirm | medium | fixed | The rule named an Output Contract that `hivemind:github-review-loop` does not have (its outcomes are under `## Terminal report`); D18's "ends the watch" escape had no source; the `hivemind:github-reviewer` fix-pass coverage (`validate_workflows.sh:121`, via `github_reviewer_fix`) moved nowhere, so the claim that the `:163` coverage moves was false for it. Fixed by the narrowing: the reviewer-outcomes requirement and D18 cover both producers and name no source section. |
| R3-04 | 3 | confirm | low | fixed | D12's review backstop sat under S5 only, though D12 binds S1 to S5. Fixed by the narrowing: Verification strategy states it once before the per-slice list, and the S5-only bullet is deleted. |
| R4-01 | 4 | confirm | medium | fixed | The record said round 4 does not change `rounds` until it runs, which contradicts the Idea to Ready round-4 exception it cites (that round 4 left `rounds` unchanged, answer Q11 A). The Round 4 entry now says `rounds` stays 3, so a passing record still meets the pass rule's `rounds` of 2 to 3 (ADR-0046 decision 7). |
| R4-02 | 4 | confirm | low | fixed | The record held no diminishing-returns advisory for round 3, and it said the cap question was asked under ADR-0046 decision 8. Round 3 now carries the advisory, and the cap question is recorded as asked under the three-round cap of decision 6. |

## Decisions taken, listed for veto

Each decision carries its recommendation strength and what it touches, per ADR-0046 decision 8 as amended 2026-11-22: PRD scope or acceptance, an ADR amendment, a trust boundary, credential or merge path, or none. A decision the user answered shows its recommendation strength and that the user chose it.

| Decision | Recommendation strength | Touches |
|---|---|---|
| Q1 A: retire the state machine (D1, D10). | strong; asked before #649, user chose it | ADR amendment (ADR-0018 superseded); trust boundary (Trust-Boundary Discipline boundaries 1 and 2 retire) |
| Q2 A: one Instinct fallback for every refused or blocked launch (D2, D3). | strong; asked before #649, user chose it | ADR amendment (through ADR-0048 decision 8) |
| Q3 A: brood dispatch runs on Instinct behind the strain-approval ask (D4). | strong; asked before #649, user chose it | Trust boundary (the strain-approval gate stays Tier A) |
| Q4 A: retire the post-merge decision report, keep the pre-merge journal (D7). | strong; asked before #649, user chose it | ADR amendment (ADR-0030 report retired) |
| Q5 A: the brood dashboard drops its claimed-state columns (D8). | strong; asked before #649, user chose it | ADR amendment (ADR-0007 dashboard columns); trust boundary (child-ledger read side retires) |
| Q6 A: remove the exploratory workflow (D5). | strong; asked before #649, user chose it | none beyond ADR-0048 decision 8 |
| Q7 A: re-home two rules in `## Safety Rails` (D11). | strong; asked before #649, user chose it | Trust boundary |
| Q8 A: the user confirms each covered deletion before the slice's run starts (D12). | strong; asked before #649, user chose it | Trust boundary (Destructive Fix Confirmation Gate categories) |
| ADR-0048 decision 8, the amendment rule. | strong; asked before #649, user chose it | ADR amendment |
| ADR-0036 decisions 9 and 10 stand as written. | strong; asked before #649, user chose it | none |
| The round count after round 2's tool pass: the pass at `63ff83f2` yields no round. | strong; asked before #649, user chose it | none |
| The round-3 cap: narrow the Verification strategy, then one round 4 over that change only, a one-time exception for this initiative. | strong; asked under ADR-0046 decision 6's three-round cap, user chose it | none |
| R1-08: a clause that scopes an ADR to the current engine is history under ADR-0048 decision 8, so it is not amended (overlord). | Strong | none |
| D9: ADR-0005 is unchanged (design). | Strong | none |
| D13: waves.js keeps its parity fixtures as frozen expectations (design). | Strong | none |
| D15: The manifest keeps version 4 without the hatchery block (design). | Strong | none |
| D16: The Reflex heading is kept (design). | Strong | none |
| D17: The proactive zoom-out marker rides the cluster payload (design). | Strong | none |
| D18: Exit-reason routing coverage moves to a workflow-scripts test, for both producers (design). | Strong | none |
| D19: Stamped documents change only through their own re-review (design). | Strong | none |
| Sequencing the tool pass before the cerebrate pass in each round from round 2 on (overlord). | Strong | none |
| Each rule stated once at its owner; other sites point to it (overlord). | Strong | none |
| Passing record stamps the design and ADR-0048 only; PRD needed before readiness (overlord). | Strong | none |
| The round-3 narrowing's wording, and each design decision's screen conformed to ADR-0046 decision 8 as amended (overlord). | Strong | none |
| Close round 4 with one record-only confirming check, since round 4's design and ADR passes found nothing and its two findings touched only the record (overlord). | strong | none (review procedure only; reversible, the PR stays a draft) |

D11 is answered (Q7 A), D12 is answered (Q8 A), and D14 is answered (Q1 A); none is a taken decision.

## Decisions asked

- Q1 A to Q6 A, answered before round 1, rest ADR-0048 decisions 1 to 7: Q1 A retires the state machine; Q2 A gives every refused or blocked launch one Instinct fallback; Q3 A runs brood dispatch on Instinct behind the strain-approval ask; Q4 A retires the post-merge decision report and keeps the pre-merge journal; Q5 A drops the dashboard's claimed-state columns; Q6 A removes the exploratory workflow.
- ADR-0048 decision 8, the amendment rule. After local review the user chose A: a clause of an accepted ADR that relies on a removed item or run ledger field now relies on its replacement, or lapses where the design names none. A clause that only mentions the state machine as history is not amended.
- ADR-0036 decisions 9 and 10. After a later local review the user decided they stand as written. The design's Decision journal and State and ownership sections follow them.
- Q7, D11, Tier A. Answered: Q7 A. Move only two rules, the facts and injection-scan rule and the PR head rule, to `## Safety Rails`. Drop the `expect_commit` sentence, since the skills' input gates own it.
- Q8, D12's confirmation point. Answered: A (user): the user confirms each covered deletion before that slice's run starts.
- The round count, after round 2's local review tool pass. Answered: A. The cerebrate pass at `63ff83f2` yields no round, since its trust-boundary tool pass did not run with it; its findings R2-01 to R2-05 keep their IDs and are attributed to round 2.
- The round-3 cap. Answered: A (user, strong recommendation). Narrow the design's Verification strategy to what each slice must prove, with no check file, name list, scan path or test mechanism; then run one round 4 over that change only, a one-time exception to the three-round cap for this initiative, recorded like the Idea to Ready design's D31 (Q9). Asked because the three-round cap of ADR-0046 decision 6 stops the review after round 3 and reaches the maintainer; the diminishing-returns check of the same decision fired after round 3 (Round 3).
