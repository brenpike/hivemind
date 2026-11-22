# PRD: Lair — Software Factory

## Problem Statement

HIVEMIND can take one request to a merged pull request, and since ADR-0044 it can merge on its own. It still cannot work through a backlog unattended. Every delivery stops to ask the user questions, many with a single option or a strong recommendation already chosen, so a human must sit with each run. The PR #602 delivery stopped four times in about four hours, and only one stop was a decision the user really had to make. A maintainer with a triaged backlog of ready issues has to start each one by hand and answer its questions while it runs. Throughput is bounded by the user's attention, not by the work.

## Solution

The **Lair** is a software factory. A deterministic controller runs in a long-lived tmux window and, on each tick:
- reads the repository's **Ready Issues** from GitHub;
- claims one;
- runs it in its own strain, an interactive session in its own worktree, through standard-delivery in **unattended mode**;
- merges the resulting pull request when it falls in the auto tier.

In unattended mode no run stops to ask. A stop with a single option or a strong recommendation and a clean gate is taken and journaled, and any other stop **parks** the issue:
- The question goes onto the issue with its options and a recommendation, and the Lair moves on.
- The user answers on the issue at their own pace, and the next run continues on the parked work with that answer settled.
- Approvals that only an interactive session may give, such as a destructive fix, hand the issue off instead.

GitHub is the Lair's state and dashboard. The user steers through labels, park answers, a halt switch, a batch review of pull requests outside the auto tier, and a digest of the decisions the Lair took for them. Everything runs under the executing user's credentials.

## User Stories

- As a maintainer, I want the Lair to deliver every Ready Issue to a merged pull request without me present, so that my backlog moves while I do other work.
- As a maintainer, I want a run to take every question that has a single option or a strong recommendation and a clean gate, so that I am asked only questions that matter.
- As a maintainer, I want a question the run may not take to land on its issue with options and a recommendation, so that I can answer when I choose while the Lair keeps working on other issues.
- As a maintainer, I want my answer on a parked issue to carry into its next run as a settled decision, with the work done before the park kept, so that I never answer twice and no work is redone.
- As a maintainer, I want only a ready label I applied, on an issue unedited since, to admit an issue, so that the Lair never works on text I did not approve.
- As a maintainer, I want comments from people without write access never to reach a run, so that outsiders cannot steer the factory.
- As a maintainer, I want safety approvals, such as a destructive fix or an external effect, to hand the issue back to me for an interactive run, so that unattended work cannot do irreversible harm.
- As a maintainer, I want each issue's labels and comments to show its state (claimed, done, waiting on an answer, handed off, failed, waiting for review) with links to the run and the pull request, so that I can see the factory on GitHub without opening a session.
- As a maintainer, I want auto-tier pull requests to merge on their own and every other pull request to wait for my batch review, so that I review only what carries risk.
- As a maintainer, I want review feedback on an open Lair pull request to be fixed by the factory, so that pull requests reach a mergeable state without me.
- As a maintainer, I want a digest of the decisions the Lair took for me, so that I can veto any of them, by reverting if the change already merged.
- As a maintainer, I want a halt switch, a merge off-switch that takes effect on the next tick, and a circuit breaker on repeated failures, so that a systemic fault cannot burn through the backlog.
- As a maintainer, I want a crashed, stalled or over-budget run to be detected and cleaned up, so that no issue stays claimed forever.
- As a maintainer, I want the Lair to run several issues at once once versioning no longer conflicts between parallel pull requests, so that throughput scales.
- As a maintainer running an interactive delivery, I want unattended mode never to apply to my session, so that I keep my current control.

## Acceptance Criteria

- **Admission.** The Lair claims an issue only when all hold:
  - it is open and labeled `readiness:ready`, and the latest such labeled event comes from a user with write permission;
  - its title and body are unedited since that event;
  - no blocked-by dependency is open;
  - it carries no `triage:locked` and no `lair:` handoff, failed or review label;
  - it is not an epic (no `type:epic` label);
  - the readiness check passes at claim time.

  An issue that fails the readiness check stays unclaimed and is named in the tick's queue report, with no new label. The Lair never applies `readiness:ready` itself.
- **Injection.** An issue the injection scan flags is handed off before any strain starts and never runs.
- **Labels.** On claim the issue moves to `readiness:implementation` with a marker comment naming the run. It moves to `readiness:done` only when GitHub shows the pull request merged, and to `readiness:needs-decision` on an answerable park. It gets a handoff, failed or review marker in the Lair's own label family. The Lair never uses `readiness:blocked` or `readiness:parked`.
- **Unattended runs.**
  - An unattended run never waits for input. Every stop is taken and journaled, or ends the run with a result naming its outcome.
  - The Lair learns of every run end, a crash or stall included, without a human.
  - A stop with a single option or a strong recommendation and a clean gate is taken. A fix-cause step stop is taken once per cause, and the same cause again parks.
  - A safety rail, an irreversible recommended action (a major version bump included), an architectural change beyond what the issue asks, a choice with no recommendation and a fact only the user holds always park.
  - Safety approvals hand the issue off and are never answerable by comment. A third park on one issue hands it off.
- **Park answers.** A park comment carries the question key, options and recommendation.
  - An answer counts only when given in the answer form, by a user with write permission, unedited, after the park marker.
  - On the next claim the answer reaches the run as a settled decision, the run continues from the parked branch, and the question is not asked again.
  - Comments by users without write permission never reach a strain. An in-scope reviewer Bot (ADR-0043) counts as trusted, because only an administrator can install the app behind it.
- **Merges.**
  - Only the Lair merges. A strain runs with the merge settings empty and with settings that deny the merge, label and issue-edit commands. A prompt-injected strain that runs with the user's GitHub rights stays a named residual.
  - While the Lair runs one issue at a time, it claims nothing while a non-draft Lair pull request is open.
  - A pull request merges unattended only when the script-computed auto tier and the ADR-0044 merge rules both pass. Any other Lair pull request is marked for batch review.
- **Post-PR feedback.** Review findings on an open Lair pull request start exactly one remediation run for it.
- **Stop controls.**
  - Setting the halt switch stops new claims within one tick, and strains in flight finish.
  - Unsetting auto-merge stops merges from the next tick.
  - Three consecutive failed, crashed, stalled or timed-out outcomes halt the Lair with a stated cause. Parks and review waits do not count.
- **Budgets and recovery.**
  - A run over its wall-clock or agent-call budget ends and its issue is marked failed or parked.
  - On start the Lair resolves every claimed issue that has no live strain and no pull request to failed, never back to ready.
- **Isolation.** Interactive sessions never enter unattended mode.
- **Observability.**
  - Each Lair session produces a decision digest listing every decision taken for the user, with its issue and pull request.
  - On start and on each tick that finds nothing to claim, the Lair reports the Ready Issue queue size, and when it is empty points the user to the triage-backlog skill.
- **Parallelism.** With more than one strain at once, parallel Lair pull requests merge in sequence, each up to date with trunk and green on its merged head, with no conflict on version metadata.

## Implementation Decisions

- **Three layers (ADR-0045).** The work graph lives in GitHub. The Lair is a deterministic controller with no model in it and no authoritative local state. Standard-delivery is the execution graph inside each strain.
- **Strains are interactive sessions in tmux, one per claimed issue,** each in its own worktree. A first claim starts off the fetched trunk commit, a re-claim at its pushed branch's head, and a remediation on its pull request's branch. Headless runs are not used.
- **Strain settings are written by the Lair:**
  - they carry the unattended marker and the merge keys set empty, with deny rules on merging and issue writes;
  - they are the only channel that selects unattended mode;
  - the coordinator's local settings are not copied into strains.
- **A strain reports through one fixed result contract** that the Lair schema-checks: outcome, pull request, branch, head, typed park and decisions taken. The Lair ends and cleans up the session. An exit with no result is a crash; an idle session with no result and no activity is a stall.
- **Unattended is an autonomy level whose third action is park.** With the marker set, the overlord's interactive paths (fallback to judgment delivery, resume questions, the post-PR watch) are replaced by parks. This amends ADR-0036 decision 8 for this level only.
- **The Lair owns strain lifecycle, merge order and version coordination** (amends ADR-0007 for Lair strains). Strains need no knowledge of the factory beyond the marker.
- **Trust.** A write-access ready label on an unedited issue is the strain approval (amends ADR-0026 for Lair strains). The issue text is captured at claim time and treated as data. Settled decisions entering a run carry their provenance.
- **Credentials.** Everything runs under the executing user's credentials. Merges follow the user's own merge settings, read fresh each tick from `.claude/settings.local.json` and then `~/.claude/settings.json`, never from the committed settings, the admin bypass included. A dedicated identity is a later phase.
- **The auto tier is computed by a script,** never judged by a model.
- **The "Decided for you" list never gates a merge;** the digest is the veto channel.
- **More than one strain at a time requires a release-train versioning mode** in which pull requests carry change fragments and a release pull request applies the bump.

## Testing Decisions

- **Contract tests for unattended mode:** each stop kind resolves to take, park or handoff as the ask policy states; no unattended path waits for input; the marker absent means today's behavior, unless the worktree holds a Lair launch file.
- **Contract tests for the controller tick** against recorded GitHub states, with no live GitHub:
  - admission (label actor, permission, edit time, blocked-by, locked; an epic or an issue failing the readiness check is not claimed and is named in the queue report with no new label);
  - claim, label and marker transitions;
  - the merge lane and auto tier;
  - the halt switch and circuit breaker;
  - orphan recovery.
- **Strain contract tests:** result schema, crash and stall detection, and settings that carry the merge keys set empty and deny merges and issue writes.
- **A park round-trip test:**
  - an answer in the answer form by a write-access user becomes a settled decision that is not asked again, and the run continues from the parked branch;
  - an answer by anyone else, or edited, is ignored.
- **Merge tests:** auto tier versus batch review; no merge by a strain; the "Decided for you" list not gating.
- **A live smoke run on a throwaway issue in this repository:** claim, unattended delivery, merge, label to done, and a digest entry.

## Success Metrics

- At least 60% of the first 20 claimed Ready Issues reach a merged pull request with no human input.
- On average at most one user answer per delivered issue, and no question asked that carried a strong recommendation.
- Share of park answers that pick the recommended option. A high share means the park policy is too strict.
- Reverts of Lair merges caused by a vetoed decision, tracked as the safety signal.
- Circuit-breaker halts, each with a named systemic cause.

## Out of Scope

- **Deciding readiness.** The Lair never applies `readiness:ready` and never runs triage.
- **Changing how interactive deliveries ask questions.** Applying the take-strong rule outside unattended mode is a separate follow-up.
- **A dedicated GitHub App identity for the Lair.** A later phase.
- **Headless runs and hosting outside a tmux session:** cron, scheduled cloud agents, GitHub Actions.
- **Repositories other than the one the Lair runs in.**
- **Changing the ADR-0044 merge rules** beyond the auto-tier precondition and the Lair tick's merge path of ADR-0044's 2026-11-21 amendment (decisions 17 to 20), and changing the repository's ruleset.
- **Requesting reviews from bots,** or reading review text for approval.
- **A web dashboard.** GitHub labels, comments and the decision digest are the user's views.

## Further Notes

- The auto tier starts narrow (ADR-0044 gates, no protected paths, no major bump, local review not skipped). Widening it with triage effort or type labels and diff-size bounds is a later decision.
- Budget values start from the PR #602 baseline of about four hours and 54 agents, and are tuned in use.
- The release-train mode needs its own decision on fragment format, release cadence and who triggers the release pull request.
- The intended sequence is human-confirmed triage first, then the Lair. The triage-backlog skill applies `readiness:ready` under the user's own account, which meets the admission rule. Triage leaves Lair-labeled issues alone.
- Interactive standard-delivery keeps working in the current checkout.
- Unverified until the strain contract is built: whether the session's stop hook fires while a workflow runs in the background, and whether an idle interactive session can be ended reliably from tmux.
- Correction to the seed brief: the "Decided for you" list never blocked auto-merge, because the merge script does not read the pull request body. ADR-0045 records the consequence.
