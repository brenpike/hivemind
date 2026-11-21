# Lair: a software factory that schedules Ready Issues into unattended strains

**Status:** accepted, 2026-11-21. Amends ADR-0007 (for Lair strains, the Lair owns strain lifecycle, merge order and version coordination), ADR-0026 (brood strain approval as a Tier A ask, for Lair strains only) and ADR-0036 decision 8 (the autonomy level, for `unattended` only). Keeps ADR-0044's merge rules.

## Context

Since ADR-0044 HIVEMIND can merge a PR on its own. The user wants a software factory: open, ready issues taken to merged PRs with no human in the loop, and only truly impactful questions asked. A question that has a single option or a strong recommendation is taken, never asked.

Research over autonomous coding agents (GitHub Copilot coding agent, Devin, Jules, OpenHands, Factory, Kiro, Cursor, Codex) and agent frameworks (LangGraph, Temporal) found one pattern:
- actions are gated by risk and reversibility, never by asking to confirm a one-answer step;
- the PR is the asynchronous review boundary;
- ambiguity is caught before work starts;
- the work item waits for a human, not the run;
- budgets end runs instead of asking;
- many items run in parallel, each on its own branch.

Two adversarial reviews of the first draft found that the Lair could not see a run end, that unattended mode covered only the engine's `decide()`, that issue text and park answers were an injection path, and that the merge controls did not reach strains. The decisions below come from plan-interrogation sessions with the user on 2026-11-21.

## Decision

### Shape

1. **Name.** The software factory is the **Lair**, the upgraded Hatchery of the Zerg tech tree. "Software Factory" stays as its descriptor.
2. **Three layers.**
   - The work graph is the issues, their native blocked-by dependencies and their labels, held in GitHub.
   - The Lair is a controller: a deterministic script with no model in it, run in a tmux window under a single-instance lock. Each tick it observes GitHub, reconciles strains, works the merge lane, takes park answers, and claims and dispatches. It holds no authoritative local state: GitHub labels and marker comments are the state, and local files are a cache it can rebuild.
   - Each claimed issue runs in the execution graph, standard-delivery.
3. **Strains are interactive sessions.** Each strain is an interactive `claude` session in tmux in its own worktree, started by the brood tooling off the fetched trunk commit. Headless `claude -p` and the Agent SDK are not used.
4. **Strain settings come from the Lair.** The Lair writes each strain's settings file. The coordinator's `.claude/settings.local.json` is not copied in.
   - The settings carry `HIVEMIND_LAIR_STRAIN` (claim nonce and autonomy level) and no `HIVEMIND_AUTO_MERGE*` key.
   - Deny rules stop the strain merging, editing labels and editing issues.
   - A `Stop` hook records an idle marker.
   - The strain may push its own branch and open or update its PR, nothing more. It never writes to the issue.
5. **Run end is a result file.** When the run ends, the strain's overlord runs one fixed script that writes a schema-checked result: outcome (`complete`, `parked`, `blocked` or `failed`), PR, branch, head, a typed park record, and the decisions taken.
   - The Lair reads the result, ends the session, and removes the worktree after the branch is pushed.
   - An exit code with no result is a crash.
   - An idle marker with no result and no run activity is a stall.
   - Brood-status is used for liveness only.

### Unattended mode

6. **One switch.** `unattended` is an autonomy level selected only by `HIVEMIND_LAIR_STRAIN` in the Lair-written settings, never by task text or a user setting.
   - In it `decide()` gains a third action, park.
   - A stop with a single option or a strong recommendation and a clean gate is taken and journaled.
   - A `step_stop` whose lead is `fix_cause` is taken once per cause identity (step, cause code and paths): the run replans with the cause as a planner constraint. A repeat parks.
   - With the marker set, the overlord has no Instinct fallback, no Resume On Start question and no post-PR watch, and every place it would ask the user becomes a park.
7. **What parks.** A safety rail; an irreversible recommended action, a major version bump included; an architectural change beyond what the issue asks; a choice with no recommendation; a fact only the user holds. Each park is typed:
   - `decision` and `fact` parks are answerable on the issue.
   - `approval` parks are not: a destructive fix, an external effect, injection-suspect content. Their issue leaves the factory for an interactive run.
   - A third park on one issue also hands it off.
8. **Architectural gate inside the issue's ask.** In unattended mode the architectural clause of the Promotion Gate does not park an action the issue itself asks for. The irreversible and safety clauses are unchanged.

### Trust

9. **Credentials.** Everything runs under the executing user's credentials, as today. A dedicated GitHub App identity is deferred to a later phase.
10. **Admission.** The Lair claims an issue only when:
    - the latest `readiness:ready` labeled event comes from a user with write permission;
    - the title and body are unedited since that event;
    - no blocked-by dependency is open.

    Because the Lair acts under the same account, it never applies `readiness:ready` itself. The issue body is captured with its hash at claim time and passed as the request; the strain never re-reads the issue. An injection scan runs before spawn and returns a verdict only. A suspect issue is handed off and never run. This replaces brood strain approval for Lair strains.
11. **Park answers.** An answer is a `/lair answer <key> <option or text>` comment from a user with write permission, unedited, posted after the park marker. Relabeling the issue `readiness:ready` re-admits it. The Lair alone builds the keyed `decisions` entries from answers. Comments by users without write permission never reach a strain. A re-claimed issue continues on its pushed branch, so the work done before a park is kept.

### Merge and versioning

12. **One merge lane.**
    - Only the Lair's tick merges, through `merge-approved.sh`, re-reading `HIVEMIND_AUTO_MERGE` and `HIVEMIND_AUTO_MERGE_ADMIN` every tick. The `--admin` bypass works as today when the user's setting allows it.
    - While the factory runs one issue at a time, the Lair claims nothing while a non-draft Lair PR is open. A draft PR belongs to its parked issue and does not hold the lane.
    - A PR merges unattended only in the auto tier. Tier v0 is computed by a script: the ADR-0044 gates, no file in a protected-path list, no major bump, and local review not skipped. Any other PR is labeled `lair:review` for the user's batch review.
13. **Post-PR feedback.** The Lair's tick polls each open Lair PR. Review findings dispatch an unattended `pr-feedback-remediation` strain for that PR.
14. **The decision list is the veto channel after merge.** `merge-approved.sh` never reads the PR body, so a "Decided for you" list does not block a merge. A veto of a merged decision is a revert. A decision digest per Lair session is the veto channel.
15. **Release train before parallelism.** No release train while the factory runs one issue at a time. Before running issues in parallel, the repository gains an opt-in versioning mode: each PR adds a change fragment, and a script-built release PR applies the highest bump.

### Labels and stop controls

16. **Labels.**
    - Readiness moves `ready` → `implementation` → `done`, and to `needs-decision` on an answerable park.
    - The Lair owns a `lair:*` family: `claimed`, `review`, `handoff`, `failed`.
    - The Lair never uses `readiness:blocked` or `readiness:parked`, which keep their triage meanings.
    - Triage leaves issues carrying a `lair:*` label alone.
17. **Stop controls.**
    - A halt file stops new claims while strains in flight finish.
    - Unsetting `HIVEMIND_AUTO_MERGE` stops merges from the next tick.
    - A circuit breaker halts the Lair after 3 consecutive failed, crashed or timed-out outcomes, recomputed from GitHub markers; parks and review waits do not count.
    - Wall-clock time per issue is watched by the Lair; agent calls are capped inside the engine.
    - On start the Lair sweeps orphaned sessions, worktrees and claims: an issue in `implementation` with no live strain and no PR is marked failed, never returned to ready.

## Considered options

- **A plain agent loop that reruns until done (a "Ralph" loop).** Rejected: no isolation, budget or park.
- **A durable workflow engine such as Temporal.** Rejected: new infrastructure outside Claude Code.
- **Headless strains (`claude -p`, Agent SDK).** Rejected by the user; strains stay interactive tmux sessions.
- **The Lair's own session launching each workflow in turn.** Rejected: every strain would share one checkout, so the Lair could never run issues in parallel, and the scheduler would no longer be a plain script.
- **A dedicated GitHub App identity now.** Deferred by the user until the factory works.
- **Dropping the ruleset's required approval, or keeping it and never merging alone.** Rejected by the user: merges work as today.
- **Discarding a parked run's work.** Rejected: a late park would cost a full rerun.
- **A risk tier judged from plan fields.** Rejected: model judgment in the merge path, against ADR-0044.
- **Blocking auto-merge on the "Decided for you" list.** Rejected: nearly every Lair PR carries one.
- **Parallel strains with each PR bumping the version.** Rejected: every pair conflicts at merge.

## Consequences

- The quality of the `readiness:ready` label decides the Lair's throughput: an issue that is not truly ready costs one run and comes back parked.
- A Lair PR can merge with decisions the user has not seen. The digest shows them; a veto is a revert.

### Residuals

- **The Lair is the user on GitHub.** Under the user's credentials, the Lair's label, comment and merge writes are indistinguishable from the user's. The admission rule cannot exclude the Lair by actor and relies on the Lair never applying `readiness:ready`.
- **A prompt-injected strain holds the user's rights.** Containment is the Lair-written settings (deny rules, no merge keys), not a separate identity.
- **`--admin` skips the ruleset's required review.** With `HIVEMIND_AUTO_MERGE_ADMIN` set, an auto-tier Lair PR merges on the script gates alone.
- **Unverified until the strain contract is built:** whether the `Stop` hook fires while a workflow runs in the background, and whether `/exit` sent through tmux reliably ends an idle session.

References: `docs/adr/0007-fleet-children-unaware-coordinator-dashboard.md`, `docs/adr/0026-decision-autonomy-and-post-merge-report.md`, `docs/adr/0036-analysis-only-first-workflow-on-script-engine.md`, `docs/adr/0044-settled-approval-and-opt-in-auto-merge.md`, `docs/prds/autonomous-ready-issue-loop.md`.
