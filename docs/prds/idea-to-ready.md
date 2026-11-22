# PRD: Idea to Ready

## Problem Statement

The Lair (ADR-0045) delivers only Ready Issues, unattended, so its throughput and safety depend on how good "ready" is. Today `readiness:ready` is a judgment label applied during triage, with no artifact behind it and no check that a machine can repeat.

On the Lair initiative itself, after interrogation and a PRD, two adversarial reviews of the design found 3 critical and 6 high gaps: the controller could not see a run end, unattended mode missed the overlord's own paths, strains inherited the admin merge setting, and park answers were an injection path. The diff-based reviews (local review before the PR, the bot review after) found none of them, because nothing in the diff contradicted itself. Gaps like these, left in a design, become blocked steps, replans and parks inside factory runs, which are the stops the factory exists to remove.

There is also no guided path from an idea to a ready issue. The maintainer has to know which skills to run, in what order, and what each must produce, and a half-finished initiative leaves no trace of where it stopped.

## Solution

A guided, interactive path from idea to Ready Issues that the maintainer starts with one command. It has two tracks:

- **Initiative track**, for features, epics and any change to a public contract or governance semantics: capture the idea, interrogate it, write the PRD, write a **solution design** and the ADRs it needs, run a **design review**, merge the docs, slice into issues, triage, then a handoff check. Steps 1 to 8 can run as one session.
- **Standalone track**, for bugs, chores, docs and small refactors: an issue carrying a spec block (problem, evidence, acceptance criteria, scope boundary, no open questions), then triage.

The **design review** is an adversarial review of the design against the current code, governance and ADRs, run by fresh reviewers who did not write the design. It ends only when no critical or high finding is open and one round found nothing new. Its record is stamped to the exact document versions it reviewed, so any later edit makes it stale.

A **readiness check** that a machine can repeat decides whether an issue may be `readiness:ready`, per track. Triage applies it before proposing ready, the guide uses it for the handoff check, and the Lair re-runs it at claim time.

## User Stories

- As a maintainer, I want one command that guides me from an idea to Ready Issues, telling me the current stage, what it needs and what comes next, so that I never have to remember the process.
- As a maintainer, I want to resume an initiative from any session or machine at the stage its artifacts show, so that a multi-day initiative never loses its place.
- As a maintainer, I want small bugs and chores to qualify as ready with a short spec block and no design documents, so that the factory is not starved by process.
- As a maintainer, I want every initiative to have a PRD, a solution design and the ADRs its hard-to-reverse decisions need, so that the HOW shared across slices is written down once.
- As a maintainer, I want the design reviewed adversarially against the current code before any slice is cut, so that gaps are found while they are cheap and not inside factory runs.
- As a maintainer, I want design decisions with a strong recommendation inside the PRD's scope taken and listed for my veto, and only scope changes, accepted-ADR amendments, trust, credential or merge-path changes, irreversible calls and calls with no strong recommendation asked, so that I answer only what matters.
- As a maintainer, I want `readiness:ready` applied only when a repeatable check passes for the issue's track, so that "ready" means the same thing every time.
- As the factory, I want to claim only issues that pass the readiness check at claim time, and never an epic, so that no unattended run starts against an unreviewed or changed design.
- As a maintainer, I want a slice that passes the check to be ready even while its blockers are open, with its blocked-by links holding it back, so that I do not re-triage after every merge.
- As a maintainer, I want the guide to finish with a handoff report naming which slices are claimable now and what blocks the rest, so that I know the factory can take over.
- As a maintainer, I want a finished initiative's design frozen as history, so that nobody mistakes it for current truth.

## Acceptance Criteria

- **Entry and resume.** One user-only command lists in-flight initiatives with their stage, or starts a new one from an idea. Given an initiative, it reports the stage, the evidence found and the next action, then starts that stage. The stage is derived only from GitHub and git (the seed issue that becomes the epic, the docs branch then trunk, the review record, sub-issues and labels), so a fresh session on another machine resumes at the same stage. Mid-interrogation is the one single-machine window.
- **Tracks.** An issue with a native parent epic is an initiative slice; any other issue is standalone. A standalone issue whose type is not bug, chore, documentation, refactor or enhancement, or whose effort is large or extra-large, fails the check with a promote-to-initiative reason.
- **Readiness check, every issue:** open; all seven rating families present; not an epic or idea; no sub-issues; at least one acceptance criterion.
- **Readiness check, standalone:** problem, evidence and scope boundary present and non-empty; open questions exactly "None".
- **Readiness check, initiative slice:**
  - parent epic open;
  - PRD, solution design and review record present on trunk;
  - every solution-design section present and filled, with open questions "None";
  - each listed ADR present and accepted;
  - the review record passed, with zero open critical and high findings, and its stamped versions equal to the documents on trunk;
  - every design section the issue names matches exactly one heading.
- **Readiness check output.** One result per issue naming its track, pass or fail, and reason codes. The check does not judge whether criteria or scope are right; that stays with the maintainer.
- **Triage.** Triage never proposes `readiness:ready` for an issue that fails the check, and shows the reason codes. A slice that passes is ready even with open blocked-by links. `readiness:blocked` is kept for blocks with no issue link.
- **Lair admission.** The Lair never claims an epic, and never claims an issue that fails the check at claim time. A failing issue stays unclaimed and is named in the tick's queue report, with no new label.
- **Solution design.** Every initiative's solution design holds the template sections: context and code truth, components, state and ownership, contracts and seams, trust boundaries, lifecycle, existing-path coverage, failure modes, decisions, verification strategy, seam order, open questions, amendments. Each decision names its ADR, or the ADR condition it fails.
- **Design review.**
  - It runs on fresh read-only reviewers that did not write the design. Each round is one pass covering every angle: code truth, conflicts with the project's documented principles, governance and ADRs, existing-path coverage, failure modes, trust and injection, testability.
  - When the design touches a trust boundary, credentials or the merge path, one pass by the configured local review tool is added. With no tool configured, that pass is skipped and the record says so.
  - The confirming round reviews only the change since the previous round and the fixes to open findings, not the whole design again.
  - The reviewer's model is configurable. A maintainer with Fable can use it for the full pass; a model the maintainer cannot reach falls back to the default, and the record names the model each pass used.
  - It exits only with zero open critical or high findings and one round with no new ones, capped at three rounds. Non-convergence reaches the maintainer as a signal to split the initiative.
  - Every finding gets exactly one disposition, and mediums follow the existing defer-or-record rules.
  - A round's findings land before the next round runs: each is fixed in the solution design, the PRD or an ADR in the same pull request, or gets a deferred, recorded or rejected disposition with its reason. A finding is never left open to be applied later.
- **Review record.** The record stamps the exact versions of the PRD and solution design it reviewed. Any later edit makes it stale until a review of the change restores it. The record ships in the same docs pull request, and a record with any open finding or a failed verdict cannot merge, so trunk never holds an unreviewed design or one with known open findings. An initiative that does not converge is split before its docs merge.
- **Design decisions.** A strong recommendation inside the PRD's scope with a clean gate is taken and listed in the record for veto. A change to the PRD's scope or acceptance criteria, an amendment of an accepted ADR, a trust-boundary, credential or merge-path change, anything irreversible and a call with no strong recommendation are always asked.
- **Slicing.** Each slice of an initiative carries a design section naming the solution design, the exact headings it implements, its ADRs and the review record. The seed issue becomes the epic, and a rerun creates no duplicates.
- **Handoff check.** Passes only when:
  - the docs are on trunk and the review is current;
  - the epic is open and never claimable;
  - every slice is a native sub-issue with resolving links and native blocked-by edges for its dependencies;
  - every slice carries all ratings, is labeled ready through triage, and passes the readiness check.

  It reports each slice as claimable now or blocked, with the reason.
- **Close-out.** When every slice is done, the solution design is marked delivered and gains an as-built deltas section, and is not maintained afterward.
- **Lair retrofit.** The Lair initiative gets a solution design that links ADR-0045 and adds only what it lacks, plus a review record covering its two completed review passes and one confirming pass. Its slices carry design sections and pass the readiness check before any is labeled ready under the new rule.

## Implementation Decisions

- **The guide is a user-only conductor skill** in the main session, written as stage must-haves with judgment, not a numbered state machine. It orchestrates the existing leaf skills, which stay uncoupled from each other (ADR-0013). It is not a workflow-engine workflow: workflows take no input mid-run and resume only in the same session. It is not an overlord section, which would load in every session and strain.
- **No progress state is stored.** Stage is a pure function of GitHub and git, on the same principle as the Lair.
- **One readiness check** is shared by triage, the guide's handoff check and Lair admission. It is deterministic and checks structure, existence, versions and labels, never quality.
- **The track is decided by a script-readable fact:** a native parent epic, plus the human-confirmed type and effort labels.
- **Design artifacts:** the PRD stays where PRDs live today. Each initiative's solution design and review record live together in a per-initiative docs folder. ADRs stay global and numbered.
- **Design review uses fresh planner passes, not a new agent.** The review record is the contract: stamped versions, verdict, open counts, rounds, findings with dispositions, decisions taken and asked.
- **A second model is used only when configured, never required.** The cross-model design pass reuses the configured local review tool, and Fable is an opt-in reviewer model. Neither Codex nor Fable is required. The record names each pass's reviewer and model.
- **ADR-0045 is amended:** Lair admission excludes epics and requires the readiness check at claim time.
- **The design-decision rule** extends Review Calls in the autonomy governance with the always-ask list above.
- **The maintainer stays the only writer of `readiness:ready`.** The guide sends the maintainer to triage at that stage.

## Testing Decisions

- **Readiness check:** contract tests over recorded issue fixtures for each track and each reason code. These include a document edited after its review was stamped, an epic, a standalone issue that must be promoted, and a slice with open blockers that still passes.
- **Review record:** stamping then verifying passes; an open finding of any severity, a missing clean round or a fourth round fails, and a record with an open finding or a failed verdict blocks the docs merge.
- **Stage derivation:** recorded fixtures for every stage give the expected stage and next action. The handoff mode passes only when every slice passes.
- **Triage gate:** a failing issue never enters the apply set as ready, and its reason shows.
- **Lair admission:** a tick contract test where a stale design or an epic is not claimed and is named in the queue report.
- **Live smoke:** a throwaway idea taken through the guide to ready slices, and a fresh session resuming at the derived stage.
- **Skill authoring rules:** the conductor is user-only, the leaf skills name no siblings, and the prose budgets hold.

## Success Metrics

- Design review finds every critical and high gap before slicing: zero Lair parks or replans caused by a design gap the review should have caught, over the first ten initiative slices delivered.
- Questions asked of the maintainer per initiative during design, against the Lair baseline (most design calls were asked).
- Share of standalone issues that reach ready on the spec block alone, without promotion.
- Initiatives resumed across sessions with no lost stage.

## Out of Scope

- A guide agent or a dedicated reviewer agent. Fresh planner passes and the main-session conductor cover both.
- A workflow-engine or state-machine workflow for the guide, and a stored progress pointer or ledger.
- The guide applying `readiness:ready` itself.
- A dedicated different-model design-review pass in v1.
- A session-start hook that resumes initiatives automatically.
- Moving existing PRDs. Each moves only when next touched, if ever.
- Keeping a delivered solution design current. After close-out the truth lives in code, ADRs, the glossary and governance.
- The Abathur council, now its own initiative (#638), and the Scout research bioform from the earlier epic (#440).
- Running the design review as an unattended factory job. A later option.

## Further Notes

- **Two by-hand pilots come first.** The Lair retrofit, then this initiative's own design stages, run with the existing skills before the new skills codify them.
- **Pen holder.** The overlord's Write grant is limited to `.hivemind/` inputs files, and the interrogation skill is the named writer of glossary terms and ADRs. Writing solution designs and review records needs a drone with exact file scope, or an extension of that exception. To decide in the solution design.
- **Prose headroom** in the autonomy and remediation governance docs is unverified. The design-decision rule and the spec-block reference may need a budget raise, which is a user decision.
- **The council moved out.** After the design review's fourth round (#627) the maintainer split the Abathur council into its own initiative, #638. A design decision with no strong recommendation goes to the maintainer; #638 may change that only by its own ADR.
- **Glossary drift:** CONTEXT.md still calls the three pipeline skills "planned — not yet implemented". Fix it with this initiative's glossary terms.
