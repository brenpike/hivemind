# Idea to Ready: two tracks, one readiness check and a reviewed design

**Status:** accepted, 2026-11-21. Amends no accepted ADR. The guide is an orchestrator under [ADR-0013](0013-decoupled-leaf-pipeline-skills.md)'s carve-out. Lair admission is [ADR-0045](0045-lair-software-factory.md) decision 10, as amended by #625.

## Context

The Lair (ADR-0045) delivers only Ready Issues, unattended. Today `readiness:ready` is a rubric judgment applied in triage, with no artifact behind it and no check a machine can repeat. On the Lair initiative, two adversarial design reviews found 3 critical and 6 high gaps that the diff-based reviews missed. Gaps left in a design become blocked steps, replans and parks inside factory runs.

There is also no guided path from an idea to a ready issue, and a half-finished initiative leaves no trace of where it stopped.

The [PRD](../prds/idea-to-ready.md) sets the WHAT. The [solution design](../initiatives/idea-to-ready/solution-design.md) sets the HOW. This ADR records the process decisions from that design that are hard to reverse. The Abathur council is recorded separately in [ADR-0047](0047-abathur-council.md), so it can be amended alone.

## Decision

### Tracks and readiness

1. **Two tracks.** The initiative track is for features, epics and any change to a public contract or governance semantics: capture, interrogation, PRD, solution design and ADRs, design review, docs merge, slicing, triage, then a handoff check. The standalone track is for bugs, chores, docs and small refactors: an issue carrying a spec block, then triage. The spec block is `## Problem`, `## Evidence`, `## Acceptance Criteria`, `## Scope boundary` and `## Open questions`. Each is non-empty, Acceptance Criteria holds at least one `- [ ]` or `- [x]` item, and Open questions reads exactly `None`.
2. **The track is a script-readable fact.** It is read, never judged.
   - An issue with a native parent is an initiative slice. Any other issue is standalone.
   - The parent must carry `type:epic`, else the slice fails `parent_not_epic`.
   - A standalone issue whose `type:` label is not `bug`, `chore`, `documentation`, `refactor` or `enhancement`, or whose `effort:` label is `l` or `xl`, fails with a promote reason.
   - The type and effort labels are human-confirmed, because triage applies them only after its confirm gate.
3. **One deterministic readiness check, three callers.** Triage, the guide's handoff check and Lair admission share one check. Lair admission is ADR-0045 decision 10, as amended by #625.
   - The check is one shell library, `plugin/skills/_shared/readiness-check.sh`, sourced by each caller's own script, so no skill calls another's script.
   - It checks structure, existence, versions and labels, never quality. It writes nothing.
   - It reads issues through `gh`. Each caller fetches and passes the remote trunk commit id, never a branch name or local ref. The check rejects a value not matching `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$` before any git call. The Lair passes the commit it spawns the strain from.
   - Design and record links bind to the slug of the parent epic's seed marker, never read from the issue. An epic without a valid marker fails `epic_marker_missing`, and a link to another slug fails `design_slug_mismatch`. The PRD path is derived as `docs/prds/<slug>.md`, never read from the issue. Every path passes a fixed allowlist before any git call. Reason codes carry line indexes, never issue text.
   - It returns one JSON line per issue naming the evaluated commit, with a track, a result and reason codes from a closed set. A missing document is a reason code. Only an unresolvable commit or a failed `gh` or `git` process exits non-zero.
   - A read where any `pageInfo.hasNextPage` is true is truncated and exits non-zero. Callers discard every line of a run that exits non-zero, and none treats it as a pass.
4. **Ready may carry open blockers.** A passing slice is proposed ready even with open blocked-by links. `readiness:blocked` is kept only for a block with no issue link. Ready Issue keeps its rule: a slice is claimable only once no blocked-by dependency is open.
   - Each `#<n>` ref in a slice's Dependencies section needs its native blocked-by edge, else `dependency_edge_missing:<n>`.
   - Triage runs the check on every issue it would propose as `readiness:ready`, with an overlay of the labels and edges its apply would write. A failing issue never enters the apply set as ready.
   - At apply, triage writes the ratings and edges first, re-runs the check and applies `readiness:ready` only to issues that still pass.
   - **Ready label authority.** The authorization is write permission on the latest `readiness:ready` labeled event, with the title and body unedited since (ADR-0045 decision 10, as amended by #625). The handoff check verifies it. "Maintainer" names a role, and triage's confirm gate is not an authorization boundary.

### Design artifacts and review

5. **Per-initiative docs folder.** `docs/initiatives/<slug>/` holds `solution-design.md` and `review-record.md`, with the same slug as `docs/prds/<slug>.md`. The PRD stays in `docs/prds/`. ADRs stay global and numbered in `docs/adr/`.
6. **Design review shape.** Review passes are fresh, read-only cerebrate analysis passes with `Memory context: none`, run from the main session.
   - Round 1 is two parallel passes: angle A (code truth, governance and ADR conflicts, existing-path coverage) and angle B (failure modes, trust and injection, testability).
   - Findings are fixed on the docs branch. Each later round is one fresh confirming pass over both angles.
   - A pass that errors, times out or returns unparseable output yields no round and is re-run. Only a completed pass with an empty list of new findings makes a clean round.
   - **Exit rule:** the review exits only with every open count (critical, high, medium and low) at 0 and one clean round, so a passing review has two or three rounds.
   - **Three-round cap:** a review that has not converged after round 3 stops and reaches the maintainer as a signal to split the initiative.
   - Every finding gets exactly one disposition: `fixed`, `rejected` with its reason, `deferred` or `recorded`. Critical and high findings are only `fixed` or `rejected`.
   - The record is rewritten after every round, and a lost session resumes from its rounds.
   - **Review fix.** A review fix to a stamped document after exit gets one fresh confirming pass over the diff since the stamps before the re-stamp. That pass changes no `rounds` count and does not count toward the cap. A new finding makes it a re-review.
   - **Re-review after an amendment.** Rounds count from 1, the front matter is replaced and the body history is appended.
7. **Review record contract.** The record starts with fixed front matter, which is the only part the readiness check parses: `stamps` (each a `path` and a `blob`), `verdict`, `open` counts by severity, `rounds` and `clean_round`.
   - **Blob stamps.** Each `blob` is `git rev-parse HEAD:<path>` on the docs branch when the record is written, and matches `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$`. Stamps must include the PRD, the solution design and every ADR its own docs pull request adds or edits, never an ADR it only cites.
   - **Pass.** The record passes when `verdict` is `pass`, every open count (critical, high, medium and low) is 0, `clean_round` is `true` and `rounds` is 2 to 3.
   - **Open counts.** Each severity's count is its findings with disposition `open`. Any critical or high whose disposition is not `fixed` or `rejected` counts as open.
   - **Staleness.** The record is stale when any stamped path's `git rev-parse <commit>:<path>` at the passed trunk commit differs from its blob, or the path is missing. A blob id is a content hash, so the merge method does not matter. Any edit to a stamped file makes the record stale until a review of the change re-stamps it.
   - **Verify.** The body holds a fixed Findings table. The design review skill's verify checks the front matter, the stamps and the table, and prints one `record-verify-failed: <record path>` line per failing record.
     - The guide runs it before the pull request leaves draft, in any repository.
     - In a repository that wires it into CI, as this one does through `tools/validate.sh`, CI maps `docs/initiatives/`, `docs/prds/` and `docs/adr/` to it. Every record the pull request adds or edits gets every check, whether or not its design is delivered. Every other passing record whose design is not delivered gets stamp equality only. ADR inclusion is checked only for a record the pull request adds or edits.
     - A verify failure is never fixed in place. The validate step reads verify's line in code and stops the run blocked, naming the record, before any fix decision, so no fix round runs.
     - A repository with no verify in CI keeps the guide's verify, the readiness check and the commit refusal.
   - **Authority.** A record is authoritative only through a human-reviewed merge. Only the design review's record step, a drone with exact file scope, writes or re-stamps it. Every commit except a standard-delivery wave, the record step's path, refuses a review record path in code, a terminal stop naming it, so no validation fix round and no pr-feedback-remediation commit carries one. #623, with the #625 amendment, adds `docs/prds/`, `docs/initiatives/` and `docs/adr/` to the Lair's protected-path list.
   - The record ships in the same pull request as the design, whose draft rule is decision 10.
8. **Design-decision rule.** Review Calls in the autonomy governance gains a rule for the design stages. A decision with a strong recommendation inside the PRD's scope and a clean gate is taken and listed in the review record for veto. These are always asked: a change to the PRD's scope or acceptance criteria, an amendment of an accepted ADR, a trust-boundary, credential or merge-path change, and anything irreversible.
   - A decision with a weak recommendation or none goes to the council first (ADR-0047). It is asked instead, never sent to the council, when its brief marks it as needing a fact only the user holds or leaves the mark out.
   - A strong council result on the producer's option with a clean gate is taken and listed for veto.
   - For a strong result on another option, the conductor, as producer, first reads that option's gate and always-ask screen. When both are clean, the design is written with that answer settled and listed for veto.
   - A split is asked.
   - A design decision's gate reads Promotion Gate clause 1, irreversible, and clause 3, safety-relevant. The always-ask list replaces clause 2.
   - The design stages run no `decide()`. Take or ask is the conductor's judgment. The review record lists each taken decision with its always-ask screen, which the confirming pass checks.
9. **A delivered design is frozen.** When every slice is done, the solution design gains `**Status:** delivered` and an `## As-built deltas` section in one docs pull request, and is never maintained afterward. The truth then lives in code, ADRs, the glossary and governance. Stage derivation reads `**Status:** delivered` before record staleness, and a delivered design's record is never re-stamped. A design is delivered when the first non-blank line after its title is exactly `**Status:** delivered`. Its slices then fail the readiness check with `design_delivered`, and CI verify skips its unedited record.

### Conductor and writers

10. **The guide is a user-only conductor skill with no stored progress state.** It runs in the main session with `disable-model-invocation: true`.
    - It is an orchestrator that owns the coupling, within ADR-0013's carve-out. It invokes the leaf skills by intent, and they stay uncoupled from each other.
    - No progress state or pointer is stored anywhere. The stage is a pure function of GitHub and git: the latest stage whose evidence exists. Evidence that does not resolve to one answer is reported as ambiguous and asked, never guessed.
    - It never applies `readiness:ready`. At the triage stage it sends the maintainer to `/hivemind:triage-backlog`, which is user-only.
    - **Docs branch.** Before stage 2 writes any tracked file, it creates `docs/<slug>` from the fetched trunk. It commits the stage-2 and stage-3 outputs through `hivemind:molt`, so the tree is clean for stage 4. Every docs-branch standard-delivery run launches with draft true and no launch reference it could close. The first opens the draft pull request, and later runs reuse it. The pull request leaves draft only after verify passes at its head. A later push that changes a stamped path returns the pull request to draft.
    - The seed issue carries a fixed marker line, and its author has write permission. The marker slug must match `^[a-z0-9]+(-[a-z0-9]+)*$` before any git or `gh` use, else the issue is ignored and named. The epic keeps the marker. Epics created before the guide gain it in #615's delivery, which adds it by hand to epics #603 and #614 before the readiness check is first used to label any slice ready. Until then their slices fail `epic_marker_missing`.
    - Only same-repository pull request heads and authors with write permission count. Ignored issues and pull requests are named in the report.
    - **Concurrent sessions.** A non-fast-forward push or a second docs pull request stops the later session, which re-derives its stage.
11. **A drone with exact file scope writes design artifacts.** Solution designs, review records and design-stage ADRs are written by a drone with exact file scope, in a standard-delivery run on the docs branch. The design review's record step is the only writer and re-stamper of review records. The writer exception of `hivemind:plan-interrogation` is not extended: it stays the glossary and ADR writer during interrogation only.

## Considered options

- **Readiness stays a triage judgment.** Rejected: nothing a machine can repeat backs the label the Lair trusts.
- **Each caller writes its own readiness check.** Rejected: triage, the guide and the Lair would drift and disagree on one issue.
- **The track judged from the issue text.** Rejected: model judgment would decide what the Lair admits.
- **The guide as a workflow-engine workflow.** Rejected: workflows take no input mid-run and resume only in the same session.
- **The guide as an overlord section.** Rejected: it would load in every session and strain.
- **A stored progress pointer or ledger.** Rejected: the stage is derived from GitHub and git, on the same principle as the Lair.
- **A guide agent or a dedicated reviewer agent.** Rejected: the main-session conductor and fresh planner passes cover both.
- **A dedicated different-model design pass in v1.** Deferred: the record names each pass's reviewer, so a pass can be added later with no schema change.
- **Stamps by commit id.** Rejected: a squash or rebase merge changes the commit, while a blob id changes only with the content.
- **Moving the PRD into the initiative folder.** Rejected: PRDs stay where they live today.
- **Extending the interrogation skill's writer exception.** Not taken: a drone's exact file scope bounds each write with no new exception.
- **The readiness check parses the record body.** Rejected: the check stays a fixed front-matter parser, and verify checks the body before ready and in CI.
- **Each caller passes its own trunk ref.** Rejected: a stale local main would pass.
- **Fix rounds kept off records by prose and agent reports.** Rejected: three review rounds found paths around it; the commit step refuses a record in code.
- **The guide passes verify as a validation command.** Rejected: a plan's validation commands are the planner's reading of the project's documented commands, so no code carries a guide-passed command to the validate step.

## Consequences

- A `readiness:ready` label on a slice now means its PRD, solution design, ADRs and review record exist on trunk and its record is current.
- Any edit to a stamped document fails every slice of the initiative until a review of the change re-stamps the record.
- The interrogation stage is the one single-machine window: its plan lives in the session or `.hivemind/`, so another machine sees only the seed issue.
- An initiative pays for design review rounds before slicing. One that has not converged after round 3 reaches the maintainer as a signal to split it.
- The readiness check depends on #625 for Lair admission and on the Lair controller (#608) to run at claim time.
- A docs pull request never takes the Lair's auto tier (#623).
- A slice whose solution design is delivered fails the readiness check (`design_delivered`).

### Residuals

- **The check judges no quality.** A well-formed design that is wrong still passes. Quality rests on the design review.
- **A taken design decision can be wrong.** It is listed for veto in the pull request body and the review record.
- **Auto-merge of a docs pull request.**
  - Scope: with `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a bot approval and green checks with no human review of the design.
  - Ground: the user's decision of 2026-11-21 (answer Q5). It is outside the threat model as the maintainer's own opt-in under [ADR-0044](0044-settled-approval-and-opt-in-auto-merge.md).
  - Bounded impact: in a repository that wires verify in CI, verify keeps a merged record consistent and current. In any repository, every commit except a standard-delivery wave refuses a record, the guide runs verify before ready, the readiness check fails every slice of a stale or delivered design, and #623 closes the Lair path. A wrong design is caught only by a later review.
  - Source: design review round 1, finding B5, recorded in the [review record](../initiatives/idea-to-ready/review-record.md).

References: [docs/prds/idea-to-ready.md](../prds/idea-to-ready.md), [docs/initiatives/idea-to-ready/solution-design.md](../initiatives/idea-to-ready/solution-design.md), [ADR-0013](0013-decoupled-leaf-pipeline-skills.md), [ADR-0045](0045-lair-software-factory.md), [ADR-0047](0047-abathur-council.md).
