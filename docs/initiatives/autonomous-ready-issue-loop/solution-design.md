# Solution design: Lair — Software Factory

This is the solution design for the Lair, epic #603. It covers the HOW that the slices share. It links the [PRD](../../prds/autonomous-ready-issue-loop.md) and [ADR-0045](../../adr/0045-lair-software-factory.md) rather than restating them, cites them as "ADR-0045 decision N", and adds only what they lack. The design review is recorded in the [review record](review-record.md).

## Context and code truth

The Lair builds on this code, as it stands on trunk:

- `plugin/skills/spawn-brood/scripts/spawn-brood.sh` starts each strain as a detached tmux session running `claude` in auto mode in its own worktree. It copies the coordinator's `.claude/settings.local.json` into every strain worktree. It has no way to write per-strain settings.
- `plugin/skills/brood-status/scripts/brood-status-collect.sh` reports, per strain, whether the tmux session is alive, the pull request state and the run ledger state. It reads no run result, so for the Lair it gives liveness only: it cannot tell a run end, a park or a stall apart.
- `plugin/skills/github-review-loop/scripts/merge-approved.sh` is the only merge path. It reads `HIVEMIND_AUTO_MERGE` (the merge method) and `HIVEMIND_AUTO_MERGE_ADMIN` (by presence) each time it runs. Its tests are `tools/test_merge_approved.sh`.
- `plugin/workflow-src/lib/decide.js`, with `plugin/references/decision-autonomy-table.json`, has the levels `high`, `balanced` and `low`. An unknown level resolves to `low`. Its only actions are `take` and `ask`. There is no `unattended` level and no park action.
- `plugin/hooks/hooks.json` holds `PreToolUse` hooks only. There is no `Stop` hook.
- `plugin/agents/overlord.md` holds the `## Instinct` path, which asks the user which delivery path to take, and the `## Resume On Start` path. It also holds the default post-PR watch under `## Review Remediation Posture`.
- `plugin/skills/triage-backlog/scripts/triage-ops.sh` defines the `readiness:*` labels and `type:epic`. It defines no `lair:*` family.
- `plugin/skills/prd-to-issues/scripts/subissue-ops.sh` creates the epic and attaches slices as native sub-issues through the GraphQL `addSubIssue` mutation. It creates no native blocked-by link: `plugin/skills/prd-to-issues/SKILL.md` writes blocked-by as `#N` refs in a slice's `## Dependencies` section.
- The standard-delivery launch in `plugin/workflow-src/standard-delivery/main.js` already takes settled decisions and a draft flag. `decisions` is a list of 1 to 10 non-blank strings of at most 2000 code points each, held as `run.decisions`. `draft` is a boolean that defaults to false.
- No readiness check exists yet. It is built under #615.
- Nothing under `plugin/` reads `HIVEMIND_LAIR_STRAIN` or uses a `lair:*` label.

## Components

### Strain launch and settings

Built by #604. The Lair starts each strain through the brood tooling, as an interactive session in tmux in its own worktree (ADR-0045 decision 3). A first claim starts off the fetched trunk commit. A re-claimed issue starts on its pushed branch (ADR-0045 decision 11). For a Lair strain the launch writes the strain's settings file and does not copy the coordinator's (ADR-0045 decision 4); the fields are under Contracts and seams. The run's request is the issue text captured at claim (ADR-0045 decision 10). The run also receives the settled decisions and the draft flag through the standard-delivery launch inputs.

### Strain result and liveness

Built by #604. At run end the strain's overlord runs one fixed script that writes the result file (ADR-0045 decision 5). The Lair schema-checks the result, ends the session, and removes the worktree once the branch is pushed. Crash and stall detection follow ADR-0045 decision 5. #604 also settles the two unverified items in the ADR-0045 residuals, with the fallbacks under Failure modes.

### Unattended autonomy level

Built by #607. It adds the `unattended` level to the autonomy table and the park action to `decide()`. The level is selected only by `HIVEMIND_LAIR_STRAIN` (ADR-0045 decision 6). With the marker set, the overlord's Instinct fallback, Resume On Start question and post-PR watch are replaced as ADR-0045 decision 6 states. Park types follow ADR-0045 decision 7, and the architectural gate follows ADR-0045 decision 8. With the marker absent, the levels and actions are today's.

### Controller tick and admission

Built by #608. The controller is a deterministic script in a tmux window under a single-instance lock (ADR-0045 decision 2). #608 covers:

- the tick loop: observe GitHub, reconcile strains, work the merge lane, take park answers, claim and dispatch;
- the claim: admission per ADR-0045 decision 10 and its 2026-11-21 amendment, the readiness-check call, the injection scan before spawn, and the claim-time capture of the issue text and its hash;
- labels and marker comments (ADR-0045 decision 16);
- the halt switch and the wall-clock budget (ADR-0045 decision 17);
- orphan recovery in the start-up sweep (ADR-0045 decision 17);
- the change to `triage-ops.sh` so that triage leaves `lair:*` issues alone (ADR-0045 decision 16);
- the queue report.

Admission reads native blocked-by links only (ADR-0045 decisions 2 and 10). A `#N` ref in a `## Dependencies` section is not read.

### Merge lane and auto tier

Built by #605. Only the tick merges, through `merge-approved.sh`, with the merge settings read fresh each tick (ADR-0045 decision 12). A script computes the auto tier v0 from the ADR-0044 gates, the protected-path list, the bump type and whether local review was skipped (ADR-0045 decision 12). A pull request outside the auto tier is labeled `lair:review`. While one strain runs at a time, the lane rule of ADR-0045 decision 12 holds: no claim while a non-draft Lair pull request is open.

### Park answer round trip

Built by #609. A park writes the park marker comment and moves the issue per ADR-0045 decision 16. An answer counts only as ADR-0045 decision 11 states. Relabeling `readiness:ready` re-admits the issue. The Lair alone builds the settled decisions from the answers, and the re-claimed run continues on the pushed branch. A third park, or an `approval` park, hands the issue off (ADR-0045 decision 7).

### Post-PR remediation strains

Built by #610. The tick polls each open Lair pull request. Review findings start exactly one unattended `pr-feedback-remediation` strain for that pull request (ADR-0045 decision 13). That strain uses the same settings and result contract as a delivery strain.

### Decision digest and circuit breaker

Built by #611. Each Lair session produces a digest of every decision taken for the user, with its issue and pull request (ADR-0045 decision 14). The circuit breaker halts the Lair after 3 consecutive failed, crashed or timed-out outcomes, recomputed from GitHub markers, with a stated cause (ADR-0045 decision 17). The count covers runs that ended in the current Lair session, so a restart by the user re-arms the Lair.

### Release-train versioning mode

Built by #606. It is the opt-in mode of ADR-0045 decision 15: each pull request adds a change fragment, and a script-built release pull request applies the highest bump. Its open choices are deferred to #606, as recorded under Decisions.

### Parallel strains

Built by #612, after #606. More than one strain runs at once. Parallel Lair pull requests merge in sequence, each up to date with trunk and green on its merged head, per the PRD's Parallelism criterion.

## State and ownership

GitHub alone is authoritative (ADR-0045 decision 2). Every local file is a cache, a control input or a hand-off from a strain.

| State | Writer | Readers | Authoritative |
| --- | --- | --- | --- |
| Labels | The user through triage writes `readiness:ready` and `type:*`. The Lair writes the other `readiness:*` moves and every `lair:*` label. | Lair, triage, user | yes |
| Claim marker comment | Lair, at claim, updated with the outcome at run end | Lair (budget, orphan sweep, circuit breaker), user | yes |
| Park marker comment | Lair, from the strain's park record | Lair, user | yes |
| Answer comments | User with write permission | Lair only | yes, when the answer rule admits them |
| Captured issue text and its hash | Lair, at claim; the hash also goes into the claim marker | Strain, as its request; Lair | no; the hash in the claim marker is |
| Strain settings | Lair, at launch | Claude Code in the strain session | no; rebuilt from the claim |
| Result file | The strain's fixed result script | Lair | no; the Lair turns it into labels and markers |
| Idle marker | The strain's `Stop` hook | Lair | no |
| Halt file | User | Lair, each tick | no; a control input |
| Single-instance lock | Lair | Lair | no; process exclusion only |
| Local cache | Lair | Lair | no; rebuildable from GitHub |

## Contracts and seams

Fields and seams only. Each slice builds the code.

- **Strain result.** `schema`, `claim_nonce`, `outcome` (`complete`, `parked`, `blocked` or `failed`), `pr` (number or null), `branch`, `head` (commit), `park` (a park record or null), `decisions` (the decisions taken, each with its key, choice and reason).
- **Lair-written settings.**
  - An `env` entry `HIVEMIND_LAIR_STRAIN` holding the claim nonce and the level `unattended`.
  - No `HIVEMIND_AUTO_MERGE` or `HIVEMIND_AUTO_MERGE_ADMIN` key.
  - Deny rules on merging, label edits, and issue edits and comments.
  - A `Stop` hook that writes the idle marker.
- **Claim marker comment.** A machine-readable marker naming `claim_nonce`, `claimed_at`, the admitting labeled event, and `body_sha256` of the captured title and body. At run end the Lair adds `outcome` and `ended_at`.
- **Park marker comment.** The question, options and recommendation in readable text, plus a machine-readable park record and the `claim_nonce` of the run that parked.
- **Park record.** `key`, `type` (`decision`, `fact` or `approval`), `question`, `options`, `recommendation`, `branch`, `pr` (a draft pull request or null). The `key` is stable: the same question on the same issue keeps the same key across runs, whatever its wording.
- **Answer form.** `/lair answer <key> <option or text>`. `<key>` names an open park on that issue. A `decision` answer names one option. A `fact` answer is free text.
- **Settled decisions.** They enter the run through the standard-delivery `decisions` launch input. The Lair alone builds each entry from an admitted answer. Each entry names the question key, the answer and its provenance: the answering user, the answer comment and the park marker it answers.
- **Auto-tier script result.** `tier` (`auto` or `review`) and, for `review`, `reasons`: one reason code per failed condition among the ADR-0044 gates, a protected path, a major bump and local review skipped.
- **Readiness-check call at claim.** The Lair calls the check for each candidate before claiming it. The result is the one the [idea-to-ready PRD](../../prds/idea-to-ready.md) names under "Readiness check output": track, pass or fail, and reason codes. Only a pass is claimed.
- **Queue report.** The Ready Issue count, and each ready-labeled issue that failed admission with its reason codes. The Lair emits it on start, on each tick that finds nothing to claim, and on any tick where a ready-labeled issue fails the readiness check. When the queue is empty it points the user to the triage-backlog skill.

## Trust boundaries

Only a user with write permission steers the Lair, through these channels:

- the `readiness:ready` label on an unedited issue, as admission (ADR-0045 decision 10 and its 2026-11-21 amendment);
- `/lair answer` comments, as park answers (ADR-0045 decision 11);
- the halt file and the merge settings on the user's own machine (ADR-0045 decisions 12 and 17);
- the batch review of `lair:review` pull requests, and the decision digest as the veto channel (ADR-0045 decisions 12 and 14).

The strain is untrusted after spawn. It works only from the captured issue text, treated as data, and never re-reads the issue. Comments by users without write permission never reach it. An issue the injection scan flags never runs. The Lair-written settings contain the strain (ADR-0045 decision 4). The remaining risks are the [ADR-0045 residuals](../../adr/0045-lair-software-factory.md#residuals).

## Lifecycle

Issue labels move as ADR-0045 decision 16 states:

- `readiness:ready` to `readiness:implementation` with `lair:claimed` at claim;
- to `readiness:done` when GitHub shows the pull request merged;
- to `readiness:needs-decision` on an answerable park, with `lair:claimed` removed;
- `lair:handoff` on an approval park, a third park or an injection-suspect issue;
- `lair:failed` on a failed, crashed, stalled or over-budget run;
- `lair:review` on a pull request outside the auto tier.

A run moves through these stages:

1. **Claim, spawn, run, result, labels, merge.** The tick admits an issue, writes the claim marker and labels, and spawns the strain. The strain runs standard-delivery unattended and writes its result. The Lair records the outcome in the claim marker, ends the session and removes the worktree after the branch is pushed. The merge lane merges an auto-tier pull request, or labels it `lair:review`.
2. **Park, answer, re-admit, continue.** A parked result becomes a park marker and a label move. The user answers and relabels `readiness:ready`. Admission runs again, the readiness check included. The new strain starts on the pushed branch with the answers as settled decisions.
3. **Post-PR remediation.** Review findings on an open Lair pull request start one remediation strain. It pushes to the same branch, and the merge lane evaluates the pull request again on a later tick.
4. **Halt and circuit breaker.** The halt file, or a tripped circuit breaker, stops new claims while strains in flight finish. Unsetting `HIVEMIND_AUTO_MERGE` stops merges from the next tick.
5. **Start-up sweep.** On start the Lair takes the lock and removes orphaned sessions and worktrees. Each issue in `readiness:implementation` with no live strain and no pull request becomes `lair:failed`, never ready again.

## Existing-path coverage

- Interactive standard-delivery is unchanged when the `HIVEMIND_LAIR_STRAIN` marker is absent.
- Non-Lair brood strains keep today's behavior. That includes the settings copy noted in PR #613, which this design neither covers nor changes.
- Triage, the review watch and interactive auto-merge are unchanged, except that triage leaves `lair:*` issues alone.

## Failure modes

| Failure | Detection | Resulting state |
| --- | --- | --- |
| Crash | The strain session has exited with no result file. | `lair:failed`; the outcome `crashed` goes into the claim marker and counts toward the circuit breaker. |
| Stall | An idle marker, no result and no run activity past the stall window. | The Lair ends the session after the branch is pushed; `lair:failed`, counted as a stall toward the circuit breaker. |
| The `Stop` hook does not fire while a workflow runs in the background | Found while building #604. | Fallback: the Lair judges a stall on run activity and the wall-clock budget alone, with the same result as a stall. |
| `/exit` sent through tmux does not end a session | The session is still alive after `/exit` and a grace period. | Fallback: once the branch is pushed, the Lair kills the tmux session, then removes the worktree. |
| GitHub API failure or rate limit | A failed or rate-limited GitHub call. | The tick changes no state: no claim, label, comment or merge. The next tick retries. |
| Lock already held | The single-instance lock cannot be taken. | The second Lair exits and changes nothing. |
| Merge refused | `merge-approved.sh` reports a result other than merged. | The pull request stays open and holds the lane; it is labeled `lair:review` unless checks are still pending, in which case the next tick retries. |
| CI red | The head commit's check rollup has failed. | One remediation strain for the pull request, as for review findings. A second red result labels it `lair:review`. |
| Issue edited after claim | The title and body hash differs from the claim marker's `body_sha256`. | The strain keeps its captured text. The Lair does not merge the pull request and labels it `lair:review`. |
| Edited answer, or an answer from a user without write access | The comment's edit history, or the user's permission. | The answer is ignored and never reaches a strain. The issue stays in `readiness:needs-decision`. |
| Third park | The issue's park marker count reaches 3. | `lair:handoff`; the issue leaves the factory. |
| Budget overrun | Wall-clock time since the claim marker exceeds the budget, or the engine's agent-call cap ends the run. | The Lair ends the session after the branch is pushed. The issue becomes `lair:failed` (timed out) or is parked, per the result. A timeout counts toward the circuit breaker. |
| Orphaned claim | The start-up sweep finds an issue in `readiness:implementation` with no live strain and no pull request. | `lair:failed`, never back to ready. |
| Stale design, or an epic | The readiness check fails at claim, or the issue carries `type:epic`. | Not claimed and given no new label. It is named in the queue report with its reason codes. |

## Decisions

A decision that is not ADR-worthy names the [P20](../../engineering-principles.md) condition it fails.

- **Admission by the readiness check, never an epic.** ADR-0045's 2026-11-21 amendment.
- **Triage leaves `lair:*` issues alone, built in #608.** ADR-0045 decision 16. Placing it in #608 is not ADR-worthy: it fails P20's hard-to-reverse condition.
- **Admission reads native blocked-by links only.** ADR-0045 decisions 2 and 10.
- **Lair strains through the brood tooling, owned by the Lair.** ADR-0045 decision 3, amending ADR-0007.
- **Admission replaces brood strain approval for Lair strains.** ADR-0045 decision 10, amending ADR-0026.
- **The `unattended` level and park action.** ADR-0045 decision 6, amending ADR-0036 decision 8.
- **Merges only through `merge-approved.sh` and its gates.** ADR-0044, kept by ADR-0045 decision 12.
- **The stall and exit fallbacks.** Not ADR-worthy: each fails P20's hard-to-reverse condition. They cover the unverified items in the ADR-0045 residuals.
- **The queue report contents.** Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The outcome recorded in the claim marker, and the circuit-breaker count scoped to the Lair session.** Not ADR-worthy: each fails P20's hard-to-reverse condition. Both keep ADR-0045 decision 17's rule that counts come from GitHub markers.
- **A red CI result gets one remediation strain, then `lair:review`.** Extends ADR-0045 decision 13. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **An issue edited after claim is not merged and goes to `lair:review`.** Extends ADR-0045 decision 10. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The release-train decisions are deferred with full scope to #606.** ADR-0045 decision 15. These are the fragment format, the release cadence, and who triggers the release pull request. #606 and #612 are therefore not ready until a dated entry under Amendments settles them.

## Verification strategy

The tests are the PRD's [Testing Decisions](../../prds/autonomous-ready-issue-loop.md#testing-decisions). This section adds only where each test lives:

- Engine tests, for the unattended level, the park action and the settled-decisions launch input, go in `tests/workflow-scripts/`.
- Shell-script tests are `tools/test_*.sh` scripts, such as `tools/test_merge_approved.sh` for the merge lane. New ones cover the strain launch and settings, the result schema, crash and stall detection, the auto-tier script, the park round trip and the controller tick.
- Controller tests use recorded GitHub states, with no live GitHub.
- The live smoke run is by hand, on a throwaway issue in this repository.

## Seam order

The build order is:

1. #604;
2. then #607 and #605;
3. then #608;
4. then #609, #610 and #611;
5. with #606 before #612.

Cross-epic seam: #608's admission needs the readiness check from #615. It is recorded here. The maintainer adds the native blocked-by link.

| Slice | Component heading(s) | ADRs |
| --- | --- | --- |
| #604 | Strain launch and settings; Strain result and liveness | ADR-0045 decisions 3, 4 and 5; ADR-0007 |
| #605 | Merge lane and auto tier | ADR-0045 decision 12; ADR-0044 |
| #606 | Release-train versioning mode | ADR-0045 decision 15 |
| #607 | Unattended autonomy level | ADR-0045 decisions 6, 7 and 8; ADR-0026; ADR-0036 |
| #608 | Controller tick and admission | ADR-0045 decisions 2, 10, 16 and 17 and the 2026-11-21 amendment; ADR-0007; ADR-0026 |
| #609 | Park answer round trip | ADR-0045 decisions 7, 11 and 16 |
| #610 | Post-PR remediation strains | ADR-0045 decision 13 |
| #611 | Decision digest and circuit breaker | ADR-0045 decisions 14 and 17 |
| #612 | Parallel strains | ADR-0045 decisions 12 and 15; ADR-0007 |

## Open questions

None

## Amendments

This design was written with the ADR-0045 amendment of 2026-11-21, which excludes epics from admission and requires a passing readiness check at claim time. Later changes to this design are appended here as dated entries.
