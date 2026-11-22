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

# Design review record: Retire the JSON state machine

The design review is at round 1 and has not passed. Every finding is fixed, and the user has answered Tier A question Q7 on D11. Round 2, a confirming round, has not run. No round has been clean, so `clean_round` is `false`. The record carries no stamps: only the record that sets `verdict` `pass` stamps, and a stamp needs the PRD.

No PRD exists for this initiative. `docs/prds/retire-json-state-machine.md` is needed before any slice can pass the readiness check (ADR-0046 decision 3), so it is written before slicing. The passing record will stamp the PRD, the solution design and ADR-0048, each at the commit its clean pass reviewed, under the stamp rule of Review record front matter in the Idea to Ready design.

## Reviewed documents

- [Solution design: Retire the JSON state machine](solution-design.md)
- [ADR-0048](../../adr/0048-retire-json-state-machine.md): retire the JSON state machine

No PRD is reviewed, since none exists.

## Rounds

### Round 1

Two passes. Neither reviewer wrote the design. Both reviewed commit `aa9342a244b13150eb141b42ac566611b6b5f268`.

- Reviewer `hivemind:cerebrate`. One fresh, read-only pass with `Memory context: none`, covering the whole documents, angles A and B. The model is not recorded in the run's report.
- Local review tool pass, run because the design touches trust boundaries. The configured local review tool reviewed the same commit and returned two findings:
  - "Universal question rule overrides the Lair's unattended park semantics": real, fixed by R1-01.
  - "The new journal rule makes pre-merge PR listing the Lair veto channel": partly real, fixed by R1-05.

The round raised 12 findings, R1-01 to R1-12. Two are high (R1-01, R1-03), seven are medium (R1-02, R1-04 to R1-09) and three are low (R1-10 to R1-12). After the fixes, none is open. Round 2, a confirming round, has not run.

The overlord also made five consistency edits after the round, listed here for the user's veto: the D2 level-check wording; the phrase "live only in text this design deletes"; the ADR Considered options wording on the journal; the design's line 3 record status; the R1-10 `:30` wording.

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

## Decisions taken, listed for veto

Each decision has its always-ask screen: an answer to each of the four always-ask items. "no" means the decision does not do that.

| Decision | Scope change | ADR amendment | Trust, credential or merge path | Irreversible |
|---|---|---|---|---|
| Round 1 fix R1-08: a clause that scopes an ADR to the current engine is history under ADR-0048 decision 8, so it is not amended and the ADR it scopes governs no remaining path. Taken by the overlord as a strong in-scope recommendation. | no | no: it states that no clause is amended | no | no |

The decisions D9 and D12 to D19, which the design takes itself, are listed for veto in the design with their screens. D11 is answered (Q7 A).

## Decisions asked

- Q1 A to Q6 A, answered before round 1, rest ADR-0048 decisions 1 to 7: Q1 A retires the state machine; Q2 A gives every refused or blocked launch one Instinct fallback; Q3 A runs brood dispatch on Instinct behind the strain-approval ask; Q4 A retires the post-merge decision report and keeps the pre-merge journal; Q5 A drops the dashboard's claimed-state columns; Q6 A removes the exploratory workflow.
- ADR-0048 decision 8, the amendment rule. After local review the user chose A: a clause of an accepted ADR that relies on a removed item or run ledger field now relies on its replacement, or lapses where the design names none. A clause that only mentions the state machine as history is not amended.
- ADR-0036 decisions 9 and 10. After a later local review the user decided they stand as written. The design's Decision journal and State and ownership sections follow them.
- Q7, D11, Tier A. Answered: Q7 A. Move only two rules, the facts and injection-scan rule and the PR head rule, to `## Safety Rails`. Drop the `expect_commit` sentence, since the skills' input gates own it.
