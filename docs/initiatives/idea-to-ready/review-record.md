---
stamps:
  - path: docs/prds/idea-to-ready.md
    blob: c76d18328baf3a6663b00231098eaf6e9f809b65
  - path: docs/initiatives/idea-to-ready/solution-design.md
    blob: cdf4af08adae0bd713828b7256578781dc38d36e
  - path: docs/adr/0046-idea-to-ready-process.md
    blob: 3a5bdea131e6526bf010ed9d32d44df42796c70a
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

This is a re-review after the amendment of 2026-11-22: the UI prototype stage decided in #663 and the Lair design's corrections ([ADR-0046](../../adr/0046-idea-to-ready-process.md), Amendments, "2026-11-22: UI prototype stage and Lair corrections"; [solution design](solution-design.md), Amendments). Under Re-review and re-stamp of the solution design, the front matter is reset (`verdict` `fail`, `rounds` 0, every open count 0 and `clean_round` `false`) and the stamps are kept. Rounds count from 1. A record of this initiative has passed, so the re-review covers the diff since the stamped blobs.

The first review, rounds 1 to 4, did not converge; after its round 4 the user split the council out into #638 (answers Q12 A and Q14 B) and approved the narrowing of ADR-0037 decision 16 (answer Q13 A). It is kept under History: 2026-11-22. The re-review that followed passed at its round 4 confirming checks; its Rounds and Findings are kept unchanged under History: 2026-11-22 (re-review).

The stamps are the blobs at commit `d634e9f6b6a143d051bc7645057b44d0dd993585`, the commit the passing re-review's clean check reviewed (History: 2026-11-22 (re-review), Round 4 confirming checks, check C), read with `git rev-parse <commit>:<path>`. Under the stamp rule of Review record front matter, a record with `verdict` `fail` keeps its stamps, and only the passing record re-stamps, to the commit its clean pass reviewed. The design review skill's verify does not exist yet (#619), so this record is checked by hand.

Before round 1, each stamp was checked against main at commit `8ea1526ba9532ca588f6a70f72be9306c49f8fb8` with `git rev-parse <commit>:<path>`:

- `docs/prds/idea-to-ready.md`: differs; the stamp is `c76d18328baf3a6663b00231098eaf6e9f809b65` and main's blob is `19b31b129d9d60fab15386f70414574a588ef5de`.
- `docs/initiatives/idea-to-ready/solution-design.md`: differs; the stamp is `cdf4af08adae0bd713828b7256578781dc38d36e` and main's blob is `121f0b360b701247749716c8a49c4646193f3913`.
- `docs/adr/0046-idea-to-ready-process.md`: differs; the stamp is `3a5bdea131e6526bf010ed9d32d44df42796c70a` and main's blob is `0f5c85ff357f9a89dbedc50823ab9a5e75165e49`.

Main changed each differing document after the stamped review, for example by the 2026-11-22 amendment of ADR-0046 decision 8, so the record was stale on main; round 1's diff since the stamped blobs covers those changes too.

This record's commits run on Instinct, outside the fix-round commit step (`runCommitStep`), so they fall inside the recorded residual Record commits outside the fix-round commit step ([ADR-0046](../../adr/0046-idea-to-ready-process.md), Residuals; Residuals below). A record edit is authoritative only through the human-reviewed merge (D24).

## Reviewed documents

- [PRD: Idea to Ready](../../prds/idea-to-ready.md)
- [Solution design: Idea to Ready](solution-design.md)
- [ADR-0046](../../adr/0046-idea-to-ready-process.md): the idea-to-ready process

The council ADR drafted in the first docs pull request was withdrawn to #638. The [glossary](../../../CONTEXT.md) edits are reviewed but not stamped. This initiative's PRD says `**UI:** no`, so it has no UI prototype to review or stamp.

## Rounds

This amendment touches a trust boundary and the merge path: the readiness check's snapshot mode for Lair admission, the Lair's auto-tier floor for docs pull requests, and the stamp paths of the path allowlist. So each round runs one fresh `hivemind:cerebrate` pass covering every angle and adds one local review tool pass when a tool is configured (`HIVEMIND_LOCAL_REVIEWER`, or the `codex-plugin` default when the Codex plugin is installed); a round with none configured, or whose tool cannot run, says the pass was skipped.

### Round 1

The first round of the re-review, under the three-round cap. Neither reviewer wrote the design. Its scope was the diff since the stamped blobs, which includes main's 2026-11-22 amendment of ADR-0046 decision 8 (#649), because each stamp differed from main at `8ea1526b` before the round, plus `CONTEXT.md` and this record since the merge-base with main, `8ea1526ba9532ca588f6a70f72be9306c49f8fb8`.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), cerebrate's own model (D11). One fresh, read-only pass with `Memory context: none`, covering every angle. It reviewed commit `193abe9d4fd46748da9feb7c2e9bbdb36b4317d8`, the branch head with a clean tree, and raised 15 findings, R1-1 to R1-15: 0 critical, 1 high, 7 medium and 7 low.
- Reviewer: the local review tool, run by `hivemind:local-reviewer` through `hivemind:adaptation-cycle` and `run-review.sh`, the `codex-plugin` preset, model gpt-5.6-sol, read from the Codex configuration (`~/.codex/config.toml`). It ran because the amendment touches a trust boundary: the path allowlist and the readiness check's input mode. Its base was `8ea1526ba9532ca588f6a70f72be9306c49f8fb8`, the merge-base with main. Iteration 1 reviewed commit `193abe9d4fd46748da9feb7c2e9bbdb36b4317d8` and iteration 2 reviewed commit `8f322f5002015b93828850b6afd58d9a81dbd0bb`. It raised 5 findings, all high: 687d54b5, 15e0bfa2, d53e191d, 6d349cd2 and bf0ada2f.

The fixes landed in commits `e2fbda4b5e228e2b8dc037b0df9a03bf13ef281a` and `8f322f5002015b93828850b6afd58d9a81dbd0bb` (from the local review tool pass), `a526e25d3404b915653fbc5a0622671a171c64ee` (the round's fix wave) and this record wave. Every finding is fixed or rejected; none is deferred, recorded or open. After the round the user answered the prototype trust question (answer A of 2026-11-23, Decisions asked). The round raised findings, so it is not clean. Round 2, a confirming round, follows.

The diminishing-returns check (D35) ran after the round, round 1 of 3. No signal fired, so no advisory was raised: the findings fell to fixes, with no recurrence on a surface an earlier round fixed.

### Round 2

A confirming round, round 2 of 3: it reviewed only the change since round 1's reviewed commit and the fixes to round 1's findings. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), cerebrate's own model (D11). One fresh, read-only pass with `Memory context: none`, covering every angle. It reviewed commit `5219c499b7921ae8ca57b583721d4ef118b54a8e` and raised 11 findings, R2-1 to R2-11: 0 critical, 0 high, 5 medium (R2-1, R2-2, R2-3, R2-4 and R2-8) and 6 low (R2-5, R2-6, R2-7, R2-9, R2-10 and R2-11).
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh`, with the model set in the Codex configuration (`~/.codex/config.toml`, gpt-5.6-sol at round 1); the round's output named no model. Its base was `193abe9d4fd46748da9feb7c2e9bbdb36b4317d8`, round 1's reviewed commit. Iteration 1 reviewed commit `5219c499b7921ae8ca57b583721d4ef118b54a8e` and iteration 2 reviewed commit `768fe3bb0fde4d316a6891da20ef130b8e41d903`. It raised 7 findings: c990e86a high, e224800e high, 3f7d8dd4 medium, 65737ca5 medium, and 9bcca72b, f3664c09 and c42622c2 high.

The round raised 18 findings: 0 critical, 5 high (9bcca72b, f3664c09, c42622c2, c990e86a and e224800e), 7 medium and 6 low.

The fixes landed in commits `768fe3bb0fde4d316a6891da20ef130b8e41d903` (from the local review tool pass: 9bcca72b, f3664c09, c42622c2 and 65737ca5), `f96d4733a2f35659d6089c4157377c861e7e9890` (the round's fix wave) and this record wave. Every critical and high finding is fixed. R2-3 and R2-5 are deferred to #622 by the maintainer's answer. None is open. The round raised findings, so it is not clean. Round 3, the last under the cap, follows.

Diminishing-returns advisory: signals 1 to 3 below; answer A of 2026-11-23 (narrow and hand off).

Diminishing-returns advisory, raised after the round, round 2 of 3 (D35). The signals as shown to the maintainer:

```text
1. Recurrence: almost every new finding sits on something round 1 fixed: the regular-file test was added one reader at a time and each round finds another reader that skips it (verify, then stage derivation, then stamp writing; the tool flagged it as a root cluster); the slicing test 'the initiative folder exists on trunk' disagrees with the track definition and lets a UI initiative be sliced with no prototype. 2. Severity falls while text grows: round 1 had 6 high findings, round 2's cerebrate pass had none; each fix adds prose. 3. Edge cases already bounded: a refinement run that dies between the fold and the verdict (R2-5), `git ls-tree` without `--full-tree` from a subdirectory, and where the prototype approval answer is stored before the record exists (R2-3) are cases the readiness check or the human merge already covers.
```

Read against the findings:

- Signal 1, recurrence: the object-type surface fixed for 15e0bfa2 drew e224800e, 3f7d8dd4 and 65737ca5; the slicing condition fixed for R1-3 drew c990e86a and R2-1.
- Signal 2: severity trends down while fixes add text.
- Signal 3: R2-3 and R2-5 are edge cases that D38, the readiness check and D24 already bound.

The maintainer's answer, 2026-11-23: A, narrow and hand off. Word for word: "A" (Decisions asked).

### Round 3

A confirming round, round 3 of 3, the last under the cap: it reviewed the change since round 2's reviewed commit, `5219c499b7921ae8ca57b583721d4ef118b54a8e`, and the fixes to round 2's findings. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), cerebrate's own model (D11). One fresh, read-only pass with `Memory context: none`, covering every angle. It reviewed commit `29af7b10c2f21eb596466b16174d46ac992bc85e` and raised 4 findings, R3-1 to R3-4, all low: 0 critical, 0 high, 0 medium and 4 low.
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh`, with the model the Codex configuration's default; the round's output named no model. Its base was `5219c499b7921ae8ca57b583721d4ef118b54a8e`, round 2's reviewed commit. Its one iteration reviewed commit `29af7b10c2f21eb596466b16174d46ac992bc85e` and raised 1 finding, e9fd803f high, rejected as a repeat of a recorded decision. The loop exited clean, with no fix commits.

The round raised 5 findings: 0 critical, 1 high (e9fd803f, rejected), 0 medium and 4 low.

The fixes landed in commit `9cceeadb0ce173281305145795628b4b62d8bcee` (R3-1 and R3-2) and this record wave (R3-2's record copies, R3-3 and R3-4). Every finding is fixed or rejected; none is deferred, recorded or open. The round raised findings, so it is not clean. A fourth, confirming round follows, past the three-round cap.

Diminishing-returns advisory: signal 3 fired, every finding a bounded edge case, and signal 1 in part, since R3-1 and R3-2 sit on round 2's two structural fixes; severity fell from six high findings in round 1 and five in round 2 to none high or medium in round 3. Round 3 was not clean and was the last under the cap, so the maintainer was asked; answer A of 2026-11-23: fix all four findings and run a fourth, confirming round past the cap (Decisions asked).

## Findings

| ID | Round | Angle | Severity | Disposition | Note |
|---|---|---|---|---|---|
| R1-1 | 1 | A | high | fixed | The changeling's contract forbade the UI prototype's runtime behavior: the `?variant=` switcher, the key cycling and the in-memory stub state, and its intended variants. #622 gives `plugin/agents/changeling.md` a carve-out scoped to `docs/initiatives/<slug>/prototype/index.html` only, within D20's budget, with an Existing-path coverage row (D39, ADR-0046 decision 11). The option taken is listed for veto. |
| R1-2 | 1 | B | medium | fixed | A filled `## Verdict` section in `notes.md` did not prove the maintainer's approval or the fold. The build run writes no Verdict; only the refinement run writes it, after the fold, and #621 and #622 test both cases (UI prototype, UI prototype format, Guide skill). |
| R1-3 | 1 | A | medium | fixed | The `hivemind:prd-to-issues` refusal broke the standalone path. The refusal and the Prototype line apply only when `docs/initiatives/<slug>/` exists on trunk, and #617 gains a fixture for it (Slice design section format). The test taken is listed for veto. Superseded in round 2 by c990e86a and R2-1: the condition is now the seed issue. |
| R1-4 | 1 | B | medium | fixed | Under `HIVEMIND_AUTO_MERGE` a taken design decision can merge unseen, and nothing said so. The residuals name it with its bound (Design-decision rule, Trust boundaries, ADR-0046 Residuals). The weaker option, asking before `gh pr ready`, is recorded in ADR-0046 Residuals and not taken. |
| R1-5 | 1 | A | medium | fixed | The veto list was said to be in the docs pull request's body, which is never updated. It is in the review record and in a docs pull request comment the guide posts with `gh pr comment` (ADR-0046 decision 8, Design-decision rule, PRD). The home taken is listed for veto. |
| R1-6 | 1 | B | medium | fixed | A #619 test case encoded the removed always-ask rule. It is rewritten to the current design-decision rule (Verification strategy). |
| R1-7 | 1 | A | medium | fixed | The retire-json D19 section 8 edits were not applied. They are applied verbatim, the ADR-0039 decision 3 references are aligned to ADR-0048, and stale `plugin/agents/overlord.md` line references are replaced by section names. Applying them in this pull request is listed for veto. |
| R1-8 | 1 | B | medium | rejected | The UI prototype's "no network request" read as a trust claim that nothing checks. Rejected by the user's answer A of 2026-11-23 (Decisions asked): the prototype is a stub page the maintainer opens in their own browser, agents treat its files only as data, and nothing checks or sandboxes it; the sentence is narrowed to a build rule. Recorded in the [solution design](solution-design.md), Trust boundaries, "The UI prototype is a stub page", and UI prototype format. The same issue as bf0ada2f. |
| R1-9 | 1 | A | low | fixed | ADR-0046's Status line credited the clause-1-only gate to answer Q18 A. It credits the amendment of 2026-11-22 (#649). |
| R1-10 | 1 | A | low | fixed | Moving the passing re-review under History turned "#640" into "##640". It is restored under History: 2026-11-22 (re-review). |
| R1-11 | 1 | A | low | fixed | The always-ask screen intro read as covering every taken decision, and four D36 rows set by the maintainer (#663) were listed as taken. The intro is scoped to the pre-amendment table, those rows moved to Decisions asked as the maintainer's decisions in #663, and the removal of the always-ask list (#649) is under Decisions asked. |
| R1-12 | 1 | A | low | fixed | "Only two kinds are asked" read as the complete ask set. The Design-decision rule names Tier A, Surface-Growth Escalation and the UI prototype approval gate (D38) beside them. |
| R1-13 | 1 | A | low | fixed | Cross-reference nits: the record-last rule's decision citation, a clause of Review record front matter and D9's historical name. The citations are corrected, and D9 says its name is historical (#649). |
| R1-14 | 1 | B | low | fixed | No fixture pinned the PRD's `**UI:**` line template. #622 adds a `tests/policy` fixture for it (Verification strategy). |
| R1-15 | 1 | B | low | fixed | The gh-mode contract cases and the evaluation of the Prototype line under `prd_ui_invalid` were unstated. Readiness check output contract and Verification strategy state them. |
| 687d54b5 | 1 | review | high | rejected | Local review tool pass, finding_id `687d54b54fed0129ab7ef3f1fed2fbd994ed33a515ad8f51576bfeb80f6d7f84`: a filled `## Verdict` section could stand in for the maintainer's approval. Rejected: stage derivation is a progress read, not an authorization boundary. The Verdict marks progress only, and the approval's authority is the D38 ask, the stamps and the human-reviewed merge (D24). Recorded in the [solution design](solution-design.md), Trust boundaries, "The prototype verdict marks progress, not approval", a review call the run took (`plugin/governance/decision-autonomy.md`, Review Calls), listed for veto. |
| 15e0bfa2 | 1 | review | high | fixed | Local review tool pass, finding_id `15e0bfa2c0f0ec5bf361d41a003da9bddf75bf1659ff6d22cea11580314318aa`: a symlink blob passed the path checks. The check reads only regular-file blobs, by their mode from `git ls-tree` (commit `e2fbda4b`). |
| d53e191d | 1 | review | high | fixed | Local review tool pass, finding_id `d53e191decee731b2662539e5292e0cb9a5b98b2210f2f3bcc75cf51c3f3d9d0`: the UI prototype files were missing from the data-only list. Trust boundaries lists `index.html` and `notes.md` as data (commit `e2fbda4b`). |
| 6d349cd2 | 1 | review | high | rejected | Local review tool pass, finding_id `6d349cd2e2e44e265b1ed7e8625684185e0b01099236bce238623f18c29053fd`: a repeat of 687d54b5. Rejected under the same record: the [solution design](solution-design.md), Trust boundaries, "The prototype verdict marks progress, not approval". |
| bf0ada2f | 1 | review | high | rejected | Local review tool pass, finding_id `bf0ada2f088177d9f4a52dde97c6d34698ca56344e2d1702d06289208b6e3f8c`: opening the UI prototype runs agent-written script in the maintainer's browser, and nothing checks its no-network rule. Rejected by the user's answer A of 2026-11-23 (Decisions asked), the same record as R1-8: the [solution design](solution-design.md), Trust boundaries, "The UI prototype is a stub page". |
| R2-1 | 2 | confirm | medium | fixed | `hivemind:prd-to-issues`'s initiative test, `docs/initiatives/<slug>/` existing on trunk, disagreed with the Track fact and let a UI initiative be sliced with no prototype. The Design section, seed reuse, the Prototype line and the refusal now apply only when the resolved epic is the seed issue for the PRD's slug, the readiness check's own binding. Otherwise it slices as today, and its slices fail the readiness check: `epic_marker_missing` under an epic with no valid marker, `design_block_missing` under another initiative's seed (Slice design section, ADR-0046 decision 12, PRD). The same issue as c990e86a. |
| R2-2 | 2 | confirm | medium | fixed | Nothing built the veto list comment. After each record wave and before `gh pr ready`, the guide posts the record's Decisions taken, listed for veto section as one docs pull request comment, the latest superseding earlier ones, and #622 tests it (Guide skill, Verification strategy). |
| R2-3 | 2 | confirm | medium | deferred | Nothing keeps the maintainer's UI prototype approval answer between stage 4 and the record's first write at stage 6. Deferred by the maintainer's answer A to the D35 advisory: #622 builds where the guide keeps it, for example a docs pull request comment that the first record step copies under Decisions asked (UI prototype). Bounded: before the refinement run writes the Verdict, a lost answer makes the guide ask again; after it, the maintainer's own words are in `notes.md`, the Verdict authorizes nothing, and the approval's authority is the human-reviewed merge (D24). #622 |
| R2-4 | 2 | confirm | medium | fixed | The changeling carve-out lifted only the Hard Stop Rules, and nothing named each prototype file's owner or pinned the carve-out. It now lifts `## Do Not Own` and the Hard Stop Rules for `prototype/index.html` only; the guide's fixed wording names each file's owner; the cerebrate row says the planner reads the carve-out; and a `tests/policy/safety-*.json` fixture pins it (D39, Existing-path coverage, #622). |
| R2-5 | 2 | confirm | low | deferred | A refinement run that stops after the fold and before the Verdict leaves stage derivation asking for approval again over a folded `index.html`. Deferred by the maintainer's answer A to the D35 advisory: #622 builds the resolution, with #621's stage reading (Failure modes). Bounded: one repeated ask. #622 |
| R2-6 | 2 | confirm | low | fixed | The Residuals named a state-machine implement loop that no longer exists, the `plugin/agents/overlord.md` coverage row was ungrammatical and named a stale budget, and D20's numbers were undated and stale. The loop is dropped and the row reworded. D20 restates the budgets from `tests/policy/prose-byte-budget.json` at commit `768fe3bb` and dates the `49787cc9` measurements. |
| R2-7 | 2 | confirm | low | fixed | "Only two kinds are asked" read as the whole ask set and missed the D35 advisory. It now covers design decisions only, and the asks other rules set are unchanged (Design-decision rule, ADR-0046 decision 8, PRD). |
| R2-8 | 2 | confirm | medium | fixed | R1-4's choice had no taken row, ADR-0046 called the option not taken a weak-recommendation decision, and Trust boundaries split one bound over two sentences. The taken row is added, the option is named the weaker one, and the bound is one sentence. |
| R2-9 | 2 | confirm | low | fixed | D36 opened as taken though the maintainer set it, and the R1-1 taken row did not match D39. D36 now says the maintainer set it and it is recorded under Decisions asked, with its recommended details taken. The R1-1 row matches D39. |
| R2-10 | 2 | confirm | low | fixed | `git ls-tree <commit> -- <path>` reads relative to the working directory, and the stamp and staleness rules read blob ids with no object-type test. The Document existence test uses `--full-tree`, and every blob id comes from its entry (Contracts and seams). |
| R2-11 | 2 | confirm | low | fixed | The Prototype line rule left `**UI:** no`, a missing UI line and `prd_ui_invalid` unstated, and External content stays data left out #619 and #622. Both are now stated (Slice design section format, Trust boundaries). |
| c990e86a | 2 | review | high | fixed | Local review tool pass, finding_id `c990e86a61696cf13430947edfbb2d58890ad764538e0714a4cf75f24f497fbd`: planner escalation. The slicing gate keyed on the folder conflicts with the Track fact and lets a UI initiative be sliced with no prototype. Fixed as R2-1. |
| e224800e | 2 | review | high | fixed | Local review tool pass, finding_id `e224800eb83faf58a4302f24e7acbb67bfd886e56504750c7dfaaa174cf994b`: stage derivation read the PRD, the prototype files, the design and the record with no regular-file test. It now reads every document through the Document existence test (Stage derivation and handoff check). Root cluster with 15e0bfa2, 65737ca5 and 3f7d8dd4: one named test, implemented once in the readiness check library. |
| 3f7d8dd4 | 2 | review | medium | fixed | Local review tool pass, finding_id `3f7d8dd4ec2dcb5c248abbb468118879b7cd4cbcd4a86465d377a1eb1ed2f5e1`: the stamp write read blob ids directly. Each stamp's blob is now the blob id the Document existence test reads (Review record front matter). |
| 65737ca5 | 2 | review | medium | fixed | Local review tool pass, finding_id `65737ca5f2532c1eb3abcab13ca3ce596219629d1525e183bb07854a96f79a4c`: record verify accepted a tree or symlink as a recorded Note's path. Fixed in commit `768fe3bb`, and verify now cites the Document existence test by name. |
| 9bcca72b | 2 | review | high | fixed | Local review tool pass, finding_id `9bcca72bda59982b2f639c305aa27d898297554606368738cb893b1201405bfe`: ADR-0046 decisions 8 and 12 still called the `notes.md` Verdict the approval. Fixed in commit `768fe3bb`. |
| f3664c09 | 2 | review | high | fixed | Local review tool pass, finding_id `f3664c0933caeca1bd59c38e63023b0e2a4615aa4ee33957507d47e62cd34dfb`: the PRD allowed open medium and low findings while the ADR and the design allow none. Fixed in commit `768fe3bb`. |
| c42622c2 | 2 | review | high | fixed | Local review tool pass, finding_id `c42622c2dc030652a9dd4f61cfac26364cb83578a4543f05a17aa0fa5115d146`: the PRD said only the maintainer may write the ready label, while the design says anyone with write permission. Fixed in commit `768fe3bb`. |
| R3-1 | 3 | confirm | low | fixed | The stamp write had no path to the Document existence test's one implementation. The guide's script now reads each stamp path's blob id at the reviewed commit through the readiness check library, the record wave's fixed wording names them, and the record step writes them as given (Review record front matter, Guide skill, Seam order #622, Verification #622, ADR-0046 decision 7). Fixed in commit `9cceeadb`. |
| R3-2 | 3 | confirm | low | fixed | Slices outside the seed fail `epic_marker_missing` under an epic with no valid marker and `design_block_missing` under another initiative's seed; `subissue-ops.sh` tests the condition with the library's seed-marker parse on the epic body it reads itself; the guide names the seed issue number, passed to ensure-parent as `--existing-number` (Slice design section, Readiness check, Failure modes, Initiative stages, Guide skill, ADR-0046 decision 12). Fixed in commit `9cceeadb` and in this record's R2-1 Note and its taken row. |
| R3-3 | 3 | confirm | low | fixed | Round 2 lacked the contracted `Diminishing-returns advisory:` line, and the amendment's taken-table intro said "round 1" only. Fixed in this record wave. |
| R3-4 | 3 | confirm | low | fixed | R2-3's deferral Note stated a bound that held only before the Verdict is written. Reworded in this record wave. |
| e9fd803f | 3 | review | high | rejected | Local review tool pass, finding_id `e9fd803fd6c1a41760290ee8fada0cf67a5ad1f9f74369eb852b9918dc8f399e`: stage derivation counts the prototype stage done once the Verdict is filled, so a forged Verdict could move the guide on early. Rejected as a repeat of the recorded decision of 687d54b5: the [solution design](solution-design.md), Trust boundaries, "The prototype verdict marks progress, not approval". |

## Decisions taken, listed for veto

Each decision in this first table, all taken before the always-ask list was removed (#649), has its always-ask screen: an answer to each of the four always-ask items. "no" means the decision does not do that.

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
| D28 keeps two sentences after the new reach sentence that repeat its after-ready residual and the #619 clause; left as is, judged harmless by the clean check | no | no | no | no |

Moved to #638 with the council, so no longer listed here: D12, D13, D14, D16, D18 and D18's `skip` at `balanced`, D25, D26, the A1 redesign, ADR-0042 decision 9 not amended, A15, R2A3, the switched-option gate, the `needs_user_fact` absent rule, the council switch re-plan, script-local council answers, the composed-brief defect, the `dissent` bound, `council.js`, the merges of A5 with B12, A6 with B13, R2A1 with R2B1, R2A4 with B15, R2B7 with A2, R3A8 with R3B1 and R3B8 with R3A2, R3B1, R3B2, R3B3, R3A2, R3A3, R3A4 and R3B7.

The commit refusal, the code-read verify stop, verify on every record the pull request adds or edits (in a repository's own CI where it wires verify there, optional per Q21 A) and `design_delivered` were asked (Q10 A), and the round-4 count was asked (Q11 A). After round 4 the council split (Q12 A, Q14 B), the narrowing of ADR-0037 decision 16 (Q13 A), the commit refusal's scope (Q15 A), the ADR-0026 decision 2 amendment (Q16 A) and the remediation plan (Q17 A) were asked. In re-review round 1 the narrowing of ADR-0026 decision 3 (Q18 A, D9), the return of a guide-launched run to the guide (Q19 A, D33) and the remediation plan (Q20 A) were asked. In re-review round 2 the plugin-only merge check with the narrowing of ADR-0044's merge conditions (Q21 A, D28) and the remediation plan (Q22 A) were asked. After re-review round 3 the broadened merge check (Q23 A, D28), its git fetch and base-drift details (Q24 A, D28) and the one-time fourth re-review round (Q23 A, D34) were asked. After re-review round 4 the move of merge-time enforcement out to #619 (Q25 A, D28, D34) and the diminishing-returns check (D35, the user's directive) were asked, and the taken rows for merge mode's details left with it. After round 1 of the re-review of the 2026-11-22 amendment the UI prototype's trust boundary was asked (answer A of 2026-11-23). After round 2 of that re-review the D35 advisory was asked (answer A of 2026-11-23). After round 3 of that re-review the round cap and the D35 advisory were asked (answer A of 2026-11-23). So none of them has a taken row.

The 2026-11-22 amendment's decisions, and those taken in rounds 1 and 2 of its re-review, are taken under ADR-0046 decision 8 as amended. Each lists its recommendation strength and what it touches, from scope, ADR amendment, trust, credential and merge path. None acts irreversibly now. The parts of D36 the maintainer set in #663 are under Decisions asked.

| Decision | Recommendation strength | What it touches |
|---|---|---|
| D36: `notes.md` describes each variant in words | strong | scope; ADR amendment (decisions 7 and 12) |
| D36: no design tool, hosted service, build step, framework or account (P26); a published link optional; as a build rule, not a trust claim and unchecked, the file references nothing outside itself and makes no network request | strong (#663 detail 2) | trust (the file the maintainer opens); ADR amendment (decision 12) |
| D37: the `**UI:**` line, the PRD's first non-blank line after its title, exactly `yes` or `no`, set during interrogation and written by `hivemind:plan-to-prd` (#622) | strong (#663 detail 1) | scope; ADR amendment (decision 12) |
| D37: a missing line reads as `no`; any other value gives `prd_ui_invalid`; #619's verify fails a record the pull request adds or edits whose stamped PRD lacks a valid line; this PRD gains `**UI:** no` | strong | scope (this PRD); ADR amendment (decisions 7 and 12) |
| D38: the prototype approval is the stage's approval gate, asked beside the two asked kinds and recorded under Decisions asked; a strong UI choice inside the prototype is taken and listed for veto | strong (#663 detail 4) | ADR amendment (decision 8) |
| D39: a changeling writes `index.html` and a drone `notes.md`, in standard-delivery waves on the docs branch, the record wave last; the build run is the first docs-branch run and opens the docs pull request | strong (#663 detail 3) | ADR amendment (decisions 10 and 11) |
| The design review covers the prototype and checks the design against it; the three-round cap stays | strong (#663 detail 5) | ADR amendment (decision 6) |
| The Prototype line, exactly one on a `**UI:** yes` slice and none otherwise; `prototype_missing`; `record_unstamped:<path>` for each prototype file; structure and existence only | strong (#663 detail 6) | trust (the path allowlist); ADR amendment (decision 12) |
| The path allowlist and stamp shapes add exactly `docs/initiatives/<s>/prototype/index.html` and `docs/initiatives/<s>/prototype/notes.md`, never a directory prefix; any other stamp path gives `record_malformed` | strong | trust (the path allowlist); ADR amendment (decision 7) |
| `hivemind:prd-to-issues` adds the Prototype line and refuses a `**UI:** yes` initiative whose prototype is missing or not stamped by a passing record, read through the readiness check library, so #617 is blocked by #615 | strong (#663 detail 7) | none |
| Stage derivation and the guide gain the UI prototype stage, stage 4, entered only on `**UI:** yes` and done when `notes.md`'s Verdict section is filled; a solution design before it is out of order; the later stages renumber to 5 to 10 | strong (#663 detail 8) | none |
| The standalone track is unchanged: a change needing a prototype is promoted | strong (#663 detail 9) | none |
| ADR-0046 amended in place with a dated entry, not a new ADR | strong | ADR amendment (ADR-0046, Amendments) |
| Each new build piece is homed in an open slice of #614 (#615, #617, #619, #621, #622) and named in its Seam order row, and #617 gains #615 as a blocker | strong | none |
| The UI prototype is kept apart from the Prototype exception of `hivemind:plan-to-prd`, which is unchanged; the glossary term is UI Prototype | strong | none |
| D40: given a recorded issue snapshot and a trunk commit, the readiness check makes no GitHub read of its own; triage and the guide keep `gh` | strong; the Lair design's correction (answer 3A of 2026-11-22, recorded on #615) | trust (the check's inputs); ADR amendment (decision 3) |
| D40: a re-claim passes the snapshot's trunk commit, never the parked head it spawns the strain from | strong; the Lair design's correction (answer 3A of 2026-11-22) | trust; ADR amendment (decision 3) |
| D24: `docs/prds/`, `docs/initiatives/` and `docs/adr/` are in the auto-tier floor #605 builds, not added by #623; the Lair's merge is #605's merge lane | strong; the Lair design (answer 2A of 2026-11-22) | merge path; ADR amendment (decision 7, Consequences and Residuals) |
| Lair admission inherits the new reason codes and prototype paths through the shared check, read by the headings Readiness check output contract and Slice design section format | strong | none |
| A History heading whose date an earlier History section uses gains a short suffix; the passing re-review moves under History: 2026-11-22 (re-review) | strong | none |
| R1-1: the changeling keeps building `index.html`, through a #622 carve-out in `plugin/agents/changeling.md` scoped to `docs/initiatives/<slug>/prototype/index.html` only. Not taken: a drone owns `index.html`, which would undo #663 detail 3, the builder taken with a strong recommendation and listed for veto (D39) | strong | D39; D20; ADR amendment (ADR-0046 decision 11); #622 |
| 687d54b5, a review call the run took: option A, the prototype Verdict marks progress only, and the approval's authority is the D38 ask, the stamps and the human-reviewed merge (D24) | strong; reversible; not architectural | trust (Trust boundaries) |
| c990e86a and R2-1, superseding R1-3: the Design section, seed reuse, the Prototype line and the slicing refusal apply only when the epic `hivemind:prd-to-issues` resolves is the seed issue for the PRD's slug, the readiness check's own binding; otherwise it slices as today and its slices fail the readiness check: `epic_marker_missing` under an epic with no valid marker, `design_block_missing` under another initiative's seed. Not taken: R1-3's folder test, a second definition of an initiative; the PRD's `**UI:**` line alone, which would refuse a standalone use whose PRD says `**UI:** yes` | strong | scope (slicing); ADR amendment (decision 12); PRD; #617 |
| R1-5: the veto list's home is the review record and a docs pull request comment the guide posts with `gh pr comment` | strong | ADR amendment (ADR-0046 decision 8); Design-decision rule; PRD |
| R1-7: the retire-json D19 section 8 edits are applied in this pull request rather than deferred | strong | ADR amendment (ADR-0046 decision 10); solution design Context and code truth and Failure modes |
| e224800e, 3f7d8dd4, 65737ca5, 15e0bfa2 and R2-10: one Document existence test under Contracts and seams, `git ls-tree --full-tree`, implemented once in the readiness check library; every git read of an initiative document goes through it, and every blob id and content read comes from its entry. Not taken: extending Document parsing rules, which parse text, not git objects | strong | trust (object-type reads); ADR amendment (decisions 3 and 7); #615, #617, #619, #621 |
| R1-4: under auto-merge, taken design decisions join the auto-merge residual with its bound. Not taken: an ask before `gh pr ready` under `HIVEMIND_AUTO_MERGE` | strong | merge path; ADR-0046 Residuals |
| R2-2: the guide posts the record's Decisions taken, listed for veto section as one docs pull request comment after each record wave and before `gh pr ready`; the latest supersedes earlier ones | strong | none; #622 |
| R2-4: the changeling carve-out lifts `## Do Not Own` and the Hard Stop Rules for `prototype/index.html` only; the guide's fixed wording names each prototype file's owner; a `tests/policy/safety-*.json` fixture pins the carve-out | strong | D39; #622 |
| R2-6: D20 restates the budgets from `tests/policy/prose-byte-budget.json` at commit `768fe3bb`, not only dating each old number | strong | none |
| R2-7: the ask sentence covers design decisions only, and the asks other rules set are unchanged | strong | ADR amendment (decision 8); PRD |

## Decisions asked

- D9, design-decision always-ask rule. Asked in re-review round 1. The user's answer: Q18 A: ADR-0046 records narrowing ADR-0026 decision 3 for design-stage decisions only; the always-ask list replaces the Promotion Gate's architectural clause (clause 2). D9 and D32 cite it.
- D9, removal of the always-ask list. Set by the maintainer's direction of 2026-11-22 (#649), merged from main: ADR-0046 decision 8 has no always-ask list. A design-stage decision with a strong recommendation is taken and listed for veto whatever it touches, only a weak or absent recommendation and an action irreversible now are asked, and the gate reads Promotion Gate clause 1 only ([ADR-0046](../../adr/0046-idea-to-ready-process.md), Amendments, "2026-11-22: strong design decisions are taken in every category"). It supersedes the always-ask list of answer Q18 A.
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
- D36, UI prototype between the PRD and the solution design. The maintainer's decisions of 2026-11-22 in #663, taken as set:
  - The artifact: "A UI prototype is a conditional, required initiative artifact. It is produced and approved between the PRD and the solution design."
  - Its shape: "Several radically different variants. Default 3, cap 5." "All variants live in a single self-contained `docs/initiatives/<slug>/prototype/index.html`". "The variant is chosen by a `?variant=` URL parameter". "`docs/initiatives/<slug>/prototype/notes.md` holds the review feedback: one section per variant, plus a verdict section". "Each variant renders with realistic stub data, in memory only". "Skip the polish."
  - Approval, then refinement: "The maintainer reviews the variants and writes notes. The builder then folds the verdict into one approved variant in the same file, and the record stamps that."
  - The approved prototype on trunk, a recorded deviation from the upstream prototype skill: "Here the approved prototype is a stamped initiative artifact on main, because slices link to it and the readiness check verifies it. The losing variants are kept in the docs pull request's history and are not carried forward once a verdict is recorded."
- D35 advisories after the round-4 confirming checks. The user's answers:
  - Q26 A, asked after the D34 confirming round: fix the four findings and run a narrow check on those edits.
  - Q27 A, asked after the narrow check: fix the one sentence and run a one-sentence check.
- Round-2 remediation plan. Asked in re-review round 2. The user's answer: Q22 A, the plan is accepted. Review findings reach a guide run only as docs pull request comments under the pass scan, the guide request has a fixed layout (RR2-C1, RR2-2; D33), stamp equality and ADR inclusion are checked only on a passing record (RR2-1; D28), and the Note shapes are defined (RR2-3).
- Round-3 remediation plan. Asked after re-review round 3. The user's answer: Q24 A, the plan is accepted.
- UI prototype trust boundary, from findings bf0ada2f and R1-8. Asked after round 1 of the re-review of the 2026-11-22 amendment, on 2026-11-23. The question, word for word:

  ```text
  Two passes raised the same issue: local review (finding bf0ada2f, high) and cerebrate (R1-8, medium). The approval step has you open the model-written docs/initiatives/<slug>/prototype/index.html in your own browser, so its scripts run. The design says the file "references nothing outside itself and makes no network request". Nothing checks that, and no review happens before you open it. The recommendation from both passes is weak, so I'm asking you. A. Record it as an accepted threat model in the solution design's Trust boundaries. Agents treat the file only as data, and your browser runs it. The risk is bounded by four things: the file comes from your own run on your own branch, the request is fixed, the source is reviewed, and the human merge is still required. The "no network request" sentence is narrowed to match. (Recommended, weak.) B. Add a fail-closed check: index.html must start <head> with a fixed Content-Security-Policy <meta> that blocks the network, and it may hold no external URLs. The readiness check (#615) and verify (#619) check this by line match, and the guide also checks it before asking you to approve. C. Sandboxed preview only: you view the prototype only through a sandbox with scripts and network turned off, and never open the raw file. Reply A, B or C.
  ```

  The user's answer, word for word: "The fact we are even acting like a prototype is a threat model is absolutely insane. A". Recorded in the [solution design](solution-design.md), Trust boundaries, "The UI prototype is a stub page".
- D35 advisory after round 2 of the re-review of the 2026-11-22 amendment, on 2026-11-23. The signals and options as shown, word for word:

  ```text
  1. Recurrence: almost every new finding sits on something round 1 fixed: the regular-file test was added one reader at a time and each round finds another reader that skips it (verify, then stage derivation, then stamp writing; the tool flagged it as a root cluster); the slicing test 'the initiative folder exists on trunk' disagrees with the track definition and lets a UI initiative be sliced with no prototype. 2. Severity falls while text grows: round 1 had 6 high findings, round 2's cerebrate pass had none; each fix adds prose. 3. Edge cases already bounded: a refinement run that dies between the fold and the verdict (R2-5), `git ls-tree` without `--full-tree` from a subdirectory, and where the prototype approval answer is stored before the record exists (R2-3) are cases the readiness check or the human merge already covers.

  A. Narrow and hand off (recommended): fix the two high findings with one structural rule (a single document existence test named once and used by every reader; slicing keys on the same track fact the readiness check uses); apply the cheap, strongly recommended text fixes; hand R2-3, R2-5 and the other edge cases to the slices that build them (#621, #622, #619) as tracked follow-ups in those issues; then round 3 confirms. B. Record the rest as residuals. C. Keep going.
  ```

  The user's answer, word for word: "A". The user chose to narrow and hand off: fix the two high findings with one structural rule (one Document existence test used by every reader, and slicing keyed on the readiness check's own initiative binding), apply the cheap strong text fixes, and hand R2-3 and R2-5 to the slices that build them (#622, with #621) as tracked follow-ups; round 3 confirms.
- Round cap and D35 advisory after round 3 of the re-review of the 2026-11-22 amendment, on 2026-11-23. The question as shown, word for word:

  ```text
  Round 3 is not clean, and it was the last round under the cap. The cap and the diminishing-returns advisory are your call.

  **Round 3 results:**
  - **Cerebrate pass:** 4 findings, all low and text-only. Each is bounded by verify, the readiness check or the human merge.
    - **R3-1.** The record step writes stamps without going through the one Document existence test implementation. Fix: the guide reads the blob ids through the library and passes them to the record wave.
    - **R3-2.** The slicing condition names the wrong failure code under another initiative's seed. It also isn't tied to the library's seed-marker parse, and it never says how prd-to-issues learns the seed issue number.
    - **R3-3.** Two record defects: the `Diminishing-returns advisory:` line is missing, and the intro of the taken-decisions table is stale.
    - **R3-4.** R2-3's deferral note states a bound that only holds before the Verdict is written.
  - **Local review tool pass:** one high finding, rejected as a repeat of the recorded "verdict marks progress, not approval" decision (finding 687d54b5). No edits.

  **Diminishing returns (D35) fired again:**
  - Signal 3 fully: every finding is a bounded edge case.
  - Signal 1 in part: R3-1 and R3-2 sit on round 2's two structural fixes.

  The severity trend: round 1 had 6 high findings, round 2 had 5, round 3 has 0 high or medium.

  Your options:

  - **A. One more round (recommended).** I fix all four in the documents. Each has a strong recommendation and is text-only. Then a fourth, confirming round reviews only that diff. If it's clean, I re-stamp and open the PR. This goes past the three-round cap.
  - **B. Hand off and confirm.** Defer R3-1 to #622 and R3-2 to #617 as tracked follow-ups, and fix only the record text (R3-3, R3-4). A fourth round then confirms that small diff. This also goes past the cap, with less change.
  - **C. Stop here.** No pull request. The branch stays with the record at verdict fail.

  Reply A, B or C.
  ```

  The user's answer, word for word: "A". The user chose to fix all four round-3 findings in the documents and run a fourth, confirming round past the three-round cap over that diff only; if it is clean, the documents are re-stamped and the pull request opened.

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

Auto-merge of a docs pull request, from findings B5 and R1-4:

- Scope: with `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a bot approval and green checks with no human review of the design. Since the 2026-11-22 (#649) amendment of decision 8, strong design decisions touching scope, an ADR, trust, credentials or the merge path are taken, so under auto-merge they can reach trunk unseen; each is listed for veto in the review record and a docs pull request comment, is reversible by a later docs pull request, and changes no code until a slice builds it.
- Ground: the user's decision of 2026-11-21 (answer Q5). It is outside the threat model as the maintainer's own opt-in under [ADR-0044](../../adr/0044-settled-approval-and-opt-in-auto-merge.md).
- Bounded impact: in any repository, `merge-approved.sh` never merges a draft, and the guide keeps the pull request a draft until verify passes at its head and the record passes (ADR-0046 decision 7). The fix-round commit refusal holds, the readiness check fails every slice of a stale, failing or delivered record, and #605's auto-tier floor closes the Lair path. Where a repository adds verify to its own CI, verify there also keeps a merged record consistent and current. A wrong design is caught only by a later review.
- Recorded in [ADR-0046](../../adr/0046-idea-to-ready-process.md), Residuals.

Record commits outside the fix-round commit step, from findings R4A1, R4B1 and RR1A3:

- Scope: every commit route outside `runCommitStep` can carry a review record path with no code refusal, such as Instinct, chosen or as the fallback after a refused launch or a failed or blocked run the guide did not launch, the Reflex tail's molt checkpoint, the local reviewer's molt fix commits on every path, the github-reviewer's git commits and the guide's own molt commits. A run the guide launched does not fall back to Instinct (answer Q19 A).
- Ground: unclosable on this engine, because a model that writes a molt inputs file or runs git can carry any path. The user decided so (asked after design review round 4, answer Q15 A).
- Bounded impact: the guide's verify before ready, the readiness check failing every slice of a stale record, and verify in the repository's own CI where it adds it. A re-stamp without review reaches trunk only through a human-reviewed merge (D24) or under the auto-merge residual.
- Recorded in [ADR-0046](../../adr/0046-idea-to-ready-process.md), Residuals.

Human merge of a record that does not pass, from re-review rounds 2 and 4:

- Scope: a human with write permission who deliberately marks the docs pull request ready and merges it can merge a record with an open finding or a failed verdict, unless the repository adds its own merge block. A push after the pull request is ready can likewise leave its record stale or failing when a human, or `merge-approved.sh` under `HIVEMIND_AUTO_MERGE`, merges it.
- Ground: HIVEMIND requires no consumer CI, so it has no merge gate a human cannot pass (`docs/engineering-principles.md` P26). The user decided so (asked in re-review round 2, answer Q21 A). After re-review round 4 the user moved merge-time enforcement on the plugin's merge paths to #619's own design question (answer Q25 A).
- Bounded impact: the merge is a human-reviewed merge (D24) or the maintainer's auto-merge opt-in. The guide keeps the pull request a draft until the record passes, and the readiness check fails every slice of a stale record or one that does not pass the pass rule, so no slice of it is labeled ready or claimed. A repository may add verify to its own CI as an optional capability.
- Recorded in [ADR-0046](../../adr/0046-idea-to-ready-process.md), Residuals.

## History: 2026-11-22 (re-review)

The re-review that passed follows, unchanged apart from each heading one level down. Its front matter then held the stamps above, `verdict` `pass`, every open count 0, `rounds` 3 and `clean_round` `true`.

### Rounds

From round 2, by the user's instruction after round 1:

- Each round runs one `hivemind:cerebrate` pass covering both angles, A (code truth, governance and ADR conflicts, existing-path coverage) and B (failure modes, trust and injection, testability), delegated with effort high. Two parallel passes no longer run.
- When the design touches trust, credentials or the merge path and a local review tool is configured (`HIVEMIND_LOCAL_REVIEWER`, or the `codex-plugin` default when the Codex plugin is installed), one more pass runs through that tool via `run-review.sh`. When none is configured, that pass is skipped and the skip is recorded in this record.
- The confirming round reviews only the diff since the previous round and the fixes to open findings, with effort medium.

#640, #641 and #643, merged from main after round 2, set this procedure in the PRD, so the PRD and this note now agree. The PRD names no effort level.

This design touches trust and the merge path. `HIVEMIND_LOCAL_REVIEWER` is unset and the Codex plugin is installed, so the `codex-plugin` default runs the extra pass.

#### Round 1

Two parallel passes. Each was fresh and read-only, ran with `Memory context: none`, and neither reviewer wrote the design. Both reviewed commit `92c9981f905531d8f4ba20040baf0cab2b855916`.

- Angle A: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Code truth, governance and ADR conflicts, existing-path coverage.
- Angle B: reviewer `hivemind:cerebrate`, model opus (Claude Opus). Failure modes, trust and injection, testability.

The round raised 15 findings, RR1A1 to RR1A6 and RR1B1 to RR1B9. RR1B1 is high. After the round the user answered Q18 A and Q19 A and accepted the remediation plan (Q20 A). Round 2, a confirming round, follows.

#### Round 2

The confirming round. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), effort medium. One fresh, read-only pass with `Memory context: none`, covering both angles, A and B, over the change since round 1 and the fixes to its findings. It reviewed commit `20169518422a183c3735c5ca3ccd61ddc507a9f6`.
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh` against base `92c9981f905531d8f4ba20040baf0cab2b855916`. The tool names no model (ADR-0042 decision 7). Its verdict was needs-attention, with one high finding.

The cerebrate pass confirmed all 15 round-1 findings fixed. The round raised 4 new findings, RR2-C1 (high, from the tool pass), RR2-1, RR2-2 and RR2-3, so it is not clean.

After the round the branch merged main at `5881e389`, bringing in #628, #640, #641, #642 and #643. #642 added principle P26, which drove a consumer-portability sweep of the design: CI, `tools/validate.sh`, the Codex plugin and Fable are each optional, with a stated fallback. The user answered the merge check question (Q21 A) and accepted the remediation plan (Q22 A).

Round 3, the confirming round and the last under the three-round cap, follows. It reviews the diff since `20169518`, which includes the merge of main, and the fixes to round 2's findings.

#### Round 3

The confirming round and the last under the three-round cap. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), effort medium. One fresh, read-only pass with `Memory context: none`, covering every angle, over the change since round 2's reviewed commit `20169518422a183c3735c5ca3ccd61ddc507a9f6`, which includes the merge of main, and the fixes to round 2's findings. It reviewed commit `5d2cf651544c4a7c5105d0a3cdcf98ddb91f5650`.
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh` against base `20169518422a183c3735c5ca3ccd61ddc507a9f6`. The tool names no model (ADR-0042 decision 7). Its verdict was needs-attention, with one high finding.

The cerebrate pass confirmed all four round-2 findings fixed: RR2-C1, RR2-1, RR2-2 and RR2-3. The round raised 5 new findings, RR3-C1 (high, from the tool pass) and RR3-1 to RR3-4. RR3-1 is a duplicate of RR3-C1. So the round is not clean, and the review has not converged under the three-round cap.

After the round the user answered Q23 A: fix every round-3 finding, broaden the ADR-0044 narrowing in the merge check of D28, and run round 4 of the re-review as a one-time confirming round (D34). The user also answered Q24 A: the round-3 remediation plan is accepted, with `merge-approved.sh` fetching the head and base from origin with git, and merge mode refusing a stamp path the base changed after the merge-base.

Round 4, the D34 confirming round, follows. It reviews the diff since `5d2cf651` and the fixes to round 3's findings, covering every angle with the local review tool pass. It does not change `rounds`, as D31's round 4 did not (answer Q11 A). If it raises any new critical or high finding, the merge enforcement moves out to #619's own design, and the design narrows its claim to the guide's draft rule and the readiness check.

#### Round 4

The D34 confirming round. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), effort medium. One fresh, read-only pass with `Memory context: none`, covering every angle, over the change since round 3's reviewed commit `5d2cf651544c4a7c5105d0a3cdcf98ddb91f5650` and the fixes to round 3's findings. It reviewed commit `94156faf9286efac684a5e468efd129f39688996`.
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh` against base `5d2cf651544c4a7c5105d0a3cdcf98ddb91f5650`. The tool names no model (ADR-0042 decision 7). Its verdict was needs-attention, with one high finding.

The cerebrate pass confirmed all five round-3 findings fixed: RR3-C1 and RR3-1 to RR3-4. The round raised 4 new findings, RR4-C1 (high, from the tool pass) and RR4-1 to RR4-3, so it is not clean. It does not change `rounds` (answer Q11 A).

After the round the user answered Q25 A: as D34 set, merge-time enforcement on the plugin's merge paths leaves this design and is #619's own design question, with RR4-C1 and RR4-1 to RR4-3 as its input, superseding the merge-check parts of Q21 A, Q23 A and Q24 A. The guarantee narrows to the guide's draft rule and the readiness check (D28). The user also judged the remaining findings to be diminishing returns and directed that the design review check for diminishing returns after every round and raise it unprompted (D35).

Three confirming checks over the narrowing change followed, recorded under Round 4 confirming checks. None changes `rounds` (answer Q11 A). Checks A and B were not clean. Check C was clean, so the record step re-stamped to the commit it reviewed, `d634e9f6`, and set `verdict` `pass` and `clean_round` `true`.

Diminishing-returns advisory: raised by the maintainer after round 4 (before D35 existed); signals: recurrence on the merge-check surface across rounds 2 to 4, severity trending to edge cases bounded by the readiness check; answer Q25 A (narrow and move merge-time enforcement to #619).

#### Round 4 confirming checks

Check A, the D34 confirming round over the narrowing. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), effort medium. One fresh, read-only pass with `Memory context: none`, covering every angle, over the diff since `94156faf9286efac684a5e468efd129f39688996`. It reviewed commit `be545476622e13014e66fbd9730081f8f6b83591` and found RRF-1 (medium), RRF-2 (medium) and RRF-3 (low).
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh` against base `94156faf9286efac684a5e468efd129f39688996`. The tool names no model (ADR-0042 decision 7). It reviewed commit `be545476622e13014e66fbd9730081f8f6b83591` and found RRF-C1 (medium, finding_id `9ac5f15dd2842743193fb8ec3941ab7bda969993c7c65df4f28dffee52256ef3`).

Check A is not clean.

Diminishing-returns advisory: signals: severity medium and low only, findings are wording on text added in the previous change, no new risk; answer Q26 A (fix the four and run a narrow check on those edits).

Check B, the narrow check of the four fixes. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), effort medium. One fresh, read-only pass with `Memory context: none`, covering every angle, over the diff since `be545476622e13014e66fbd9730081f8f6b83591`. It reviewed commit `8b9bd06cf17ccd398efd139be1cc7826c606d086` and confirmed RRF-C1, RRF-1, RRF-2 and RRF-3 fixed, with no new finding.
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh` against base `be545476622e13014e66fbd9730081f8f6b83591`. The tool names no model (ADR-0042 decision 7). It reviewed commit `8b9bd06cf17ccd398efd139be1cc7826c606d086` and found RRN-C1 (medium, finding_id `1312aa586f77adf5ac402f11eaf12e42defea26cba0567ae859f5c07e3a29971`): the draft rule was claimed for every plugin-controlled merge path, though `merge-approved.sh` can merge after ready.

Check B is not clean.

Diminishing-returns advisory: signals: the finding is on the sentence fixed in the previous check, medium wording, the risk already recorded; answer Q27 A (fix that sentence and run a one-sentence check).

Check C, the one-sentence check. Neither reviewer wrote the design.

- Reviewer `hivemind:cerebrate`, model opus (Claude Opus), effort medium. One fresh, read-only pass with `Memory context: none`, covering every angle, over the diff since `8b9bd06cf17ccd398efd139be1cc7826c606d086`. It reviewed commit `d634e9f6b6a143d051bc7645057b44d0dd993585` and confirmed RRN-C1 fixed, with no new finding.
- Reviewer: the local review tool, the `codex-plugin` preset, run through `run-review.sh` against base `8b9bd06cf17ccd398efd139be1cc7826c606d086`. The tool names no model (ADR-0042 decision 7). It reviewed commit `d634e9f6b6a143d051bc7645057b44d0dd993585`. Its verdict was approve, with no findings.

Check C is clean: it is this record's clean round. The record step re-stamped to `d634e9f6` and set `verdict` `pass`.

### Findings

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
| RRF-C1 | 4 | review | medium | fixed | Local review tool pass, finding_id `9ac5f15dd2842743193fb8ec3941ab7bda969993c7c65df4f28dffee52256ef3`: the design said the draft rule fully met the PRD's cannot-merge rule. D28 and ADR-0046 decision 7 now say it does not in full, and #619 delivers the full guarantee. |
| RRF-1 | 4 | confirm | medium | fixed | D35 claimed to reuse the signals of `hivemind:detect-remediation-signals`. D35 now has its own signals, modeled on that skill, run whatever the severity. |
| RRF-2 | 4 | confirm | medium | fixed | D35's options now stay within the disposition rule: a critical or high finding is only fixed or rejected. |
| RRF-3 | 4 | confirm | low | fixed | Review record body now names the `Diminishing-returns advisory:` line under each round. |
| RRN-C1 | 4 | review | medium | fixed | Local review tool pass, finding_id `1312aa586f77adf5ac402f11eaf12e42defea26cba0567ae859f5c07e3a29971`: the draft rule was claimed for every plugin-controlled merge path. It is now limited to while the pull request is a draft, with the merge after ready left to #619. |

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
