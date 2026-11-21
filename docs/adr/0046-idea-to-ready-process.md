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
   - It reads issues through `gh` and documents at the trunk ref the caller passes. The Lair passes the fetched trunk commit it spawns the strain from.
   - It returns one JSON line per issue with a track, a result and reason codes from a closed set. A `gh` or `git` failure, or a truncated read, exits non-zero, and no caller treats it as a pass.
4. **Ready may carry open blockers.** Triage runs the check on every issue it would propose as `readiness:ready`, and a failing issue never enters the apply set as ready. A passing slice is proposed ready even with open blocked-by links. `readiness:blocked` is kept only for a block with no issue link. Ready Issue keeps its rule: a slice is claimable only once no blocked-by dependency is open.

### Design artifacts and review

5. **Per-initiative docs folder.** `docs/initiatives/<slug>/` holds `solution-design.md` and `review-record.md`, with the same slug as `docs/prds/<slug>.md`. The PRD stays in `docs/prds/`. ADRs stay global and numbered in `docs/adr/`.
6. **Design review shape.** Review passes are fresh, read-only cerebrate analysis passes with `Memory context: none`, run from the main session.
   - Round 1 is two parallel passes: angle A (code truth, governance and ADR conflicts, existing-path coverage) and angle B (failure modes, trust and injection, testability).
   - Findings are fixed on the docs branch. Each later round is one fresh confirming pass over both angles.
   - **Exit rule:** the review exits only with zero open critical or high findings and one round with no new findings.
   - **Three-round cap:** a review that has not converged after round 3 stops and reaches the maintainer as a signal to split the initiative.
   - Every finding gets exactly one disposition: `fixed`, `rejected` with its reason, `deferred` or `recorded`. Critical and high findings are only `fixed` or `rejected`.
7. **Review record contract.** The record starts with fixed front matter, which is the only part the check parses: `stamps` (each a `path` and a 40-hex `blob`), `verdict`, `open` counts by severity, `rounds` and `clean_round`.
   - **Blob stamps.** Each `blob` is `git rev-parse HEAD:<path>` on the docs branch when the record is written. Stamps must include the PRD and the solution design and may add ADRs.
   - **Pass.** The record passes when `verdict` is `pass`, critical and high are 0, `clean_round` is `true` and `rounds` is 1 to 3.
   - **Staleness.** The record is stale when any stamped path's `git rev-parse <trunk-ref>:<path>` differs from its blob, or the path is missing. A blob id is a content hash, so the merge method does not matter. Any edit to a stamped file makes the record stale until a review of the change re-stamps it.
   - The record ships in the same pull request as the design. That pull request opens as a draft with no closing keyword and leaves draft only when the record passes and its stamps equal the documents at the pull request head.
8. **Design-decision rule.** Review Calls in the autonomy governance gains a rule for the design stages. A decision with a strong recommendation inside the PRD's scope and a clean gate is taken and listed in the review record for veto. These are always asked: a change to the PRD's scope or acceptance criteria, an amendment of an accepted ADR, a trust-boundary, credential or merge-path change, and anything irreversible. A decision with a weak recommendation or none goes to the council first (ADR-0047).
9. **A delivered design is frozen.** When every slice is done, the solution design gains `**Status:** delivered` and an `## As-built deltas` section in one docs pull request, and is never maintained afterward. The truth then lives in code, ADRs, the glossary and governance.

### Conductor and writers

10. **The guide is a user-only conductor skill with no stored progress state.** It runs in the main session with `disable-model-invocation: true`.
    - It is an orchestrator that owns the coupling, within ADR-0013's carve-out. It invokes the leaf skills by intent, and they stay uncoupled from each other.
    - No progress state or pointer is stored anywhere. The stage is a pure function of GitHub and git: the latest stage whose evidence exists. Evidence that does not resolve to one answer is reported as ambiguous and asked, never guessed.
    - It never applies `readiness:ready`. At the triage stage it sends the maintainer to `/hivemind:triage-backlog`, which is user-only.
11. **A drone with exact file scope writes design artifacts.** Solution designs, review records and design-stage ADRs are written by a drone with exact file scope, in a standard-delivery run on the docs branch. The writer exception of `hivemind:plan-interrogation` is not extended: it stays the glossary and ADR writer during interrogation only.

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

## Consequences

- A `readiness:ready` label on a slice now means its PRD, solution design, ADRs and review record exist on trunk and its record is current.
- Any edit to a stamped document fails every slice of the initiative until a review of the change re-stamps the record.
- The interrogation stage is the one single-machine window: its plan lives in the session or `.hivemind/`, so another machine sees only the seed issue.
- An initiative pays for design review rounds before slicing. One that has not converged after round 3 reaches the maintainer as a signal to split it.
- The readiness check depends on #625 for Lair admission and on the Lair controller (#608) to run at claim time.

### Residuals

- **The check judges no quality.** A well-formed design that is wrong still passes. Quality rests on the design review.
- **A taken design decision can be wrong.** It is listed for veto in the pull request body and the review record.

References: [docs/prds/idea-to-ready.md](../prds/idea-to-ready.md), [docs/initiatives/idea-to-ready/solution-design.md](../initiatives/idea-to-ready/solution-design.md), [ADR-0013](0013-decoupled-leaf-pipeline-skills.md), [ADR-0045](0045-lair-software-factory.md), [ADR-0047](0047-abathur-council.md).
