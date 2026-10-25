# The workflow engine is one Claude Workflow script per workflow, launched by name from plain requests

**Status:** accepted, 2026-10-18

## Context

The current engine has the overlord model drive each state transition by hand. Every transition costs a model turn, which makes runs slow and expensive (see the usage analysis in `docs/research/2026-10-hivemind-usage-analysis.md`).

Claude dynamic Workflows arrived after HIVEMIND was built. A Workflow script runs a sequence of agents as code, so transitions no longer need a model turn.

The prose state machine approach in #408 (autonomy levels and decision briefs) failed.

Issue #409 holds the research and spikes behind this ADR:

- the issue body (problem statement)
- desk research: https://github.com/brenpike/hivemind/issues/409#issuecomment-6251786842
- ultracode: https://github.com/brenpike/hivemind/issues/409#issuecomment-6252100198
- spikes S1 to S3, launch reliability, and the decisions: https://github.com/brenpike/hivemind/issues/409#issuecomment-6254020683
- spikes S4, S5 and S7: https://github.com/brenpike/hivemind/issues/409#issuecomment-6254377722

## Decision

1. **One script per workflow (option B).** Rules and tables stay as data: the hard stops, plus the autonomy table and the decision-brief schema, which come over unchanged from the #408 branch in the retry (#409 step 2). A build step copies them into the scripts, because a running script cannot read files (desk research). The exact source files are an open item.
2. **Workflows ship as plugin workflows and run by namespaced name.** The user approves each workflow once, through "don't ask again" or a `Workflow(<plugin>:<name>)` allow rule (S7).
3. **Runs start from plain user requests.** A slim, intent-only overlord launches the named workflow itself. Slash commands are not the entry point. Plain-request launching worked in 10 of 10 trials (launch reliability). Which workflow to launch is an open item.
4. **Fallback.** If a launch is refused or blocked, the overlord says so in one line and the current engine runs the work.
5. **The engine rule comes first in the overlord prompt.** The full overlord prompt launched the workflow in only 2 of 3 trials (launch reliability).
6. **Only the harness completion notice counts as a run's result.** The model's own summary never counts. In 1 of 12 trials the model printed a fake result (launch reliability).
7. **Git work runs inside workflow agents under project allow rules for the exact commands.** Without those rules, every Bash call prompts the user (S4).
8. **Every workflow agent with side effects checks for its own prior effect before acting.** On resume, every agent after the first changed call reruns live (S5).
9. **Pausing to ask the user means the workflow returns.** The overlord relays the question, then resumes the workflow with the answer (S2, S5).
10. **The PR watch stays in the main session with Monitor.** ADR-0029 governs it; this ADR does not change it.
11. **Ultracode is not the engine's switch.** It stays an occasional per-prompt tool for exploratory work only (ultracode research).
12. **Brood children run with `--permission-mode auto`, not `--dangerously-skip-permissions`.** The switch lands in engine work, after a re-check of reason 1 in ADR-0017's 2026-06-02 amendment (#170): under auto mode a child runs no Bash while the classifier model is unavailable. Reason 2 in that amendment (hooks and MCP servers run at launch, before any permission check) stays covered by the trusted-base precondition. Detached children cannot answer prompts, so allow rules must cover every action they take. Until the switch lands, children keep the current flag. Amended 2026-10-24: this decision landed in slice 4 (ADR-0037, Amendment 2026-10-24: brood children on the script engine (slice 4)). The user accepted reason 1 of ADR-0017's #170 amendment as a cost. The condition that allow rules must cover every action is replaced by remote control plus user monitoring: spawn-brood turns on remote control for each strain started when spawn ends, and the user, who owns monitoring the brood, answers a child's prompt through it or the attach line (ADR-0017, Amendment 2026-10-24).

## What moves where

| Home | Holds |
|---|---|
| Workflow scripts | Step sequence, waves, review loops, the autonomy decision as code over the autonomy table, brief validation through the schema |
| Data files | The tables and schemas, copied into scripts at build time |
| Slim overlord | Talking to the user, launching workflows, relaying questions and resuming, the PR watch, the fallback |
| Unchanged for now | The current engine, kept as the fallback |

## Scope relative to other ADRs

Every earlier ADR keeps governing the current engine, which is also the fallback, and anything else it governs today. The one exception is brood child launch, which both engines share (see the ADR-0017 row).

The new engine is governed by this ADR and by the ADRs and clauses that the table below marks `applies` or `partial`. The table has one row for each of ADR-0001 to ADR-0033. No other clause of those ADRs governs the new engine. Any ADR not in the table states its own scope.

Scope values:

- `applies`: the ADR governs the new engine the same way it governs the current engine.
- `partial`: only the clauses the note lists after "Applies" govern the new engine.
- `current engine only`: the ADR does not govern the new engine.
- `superseded`: the ADR already governs neither engine.

| ADR | Title | New engine | Note |
|---|---|---|---|
| 0001 | Two specialist reviewer agents | partial | Applies: separate local and GitHub reviewer agents. Current engine only: the ADR-0011 update note that `local-reviewer` keeps its own loop, since review loops move into workflow scripts. |
| 0002 | Self-owning delegation for reviewers | superseded | Superseded by ADR-0005. |
| 0003 | Immediate stop on planner escalation | superseded | Superseded by ADR-0006 and ADR-0026. |
| 0004 | Fix mode reports clean without waiting for CI | applies | Part of the PR watch (decision 10). |
| 0005 | Agent tool unavailable in subagents | applies | Review policy: reviewers fix at most 2 files themselves and escalate larger fixes. |
| 0006 | Intent-based governance | partial | Applies: the "Where mechanical survived" list, and intent for the judgment inside each agent. Current engine only: prose workflow sequencing and routing between steps, which the new engine runs as code (decision 1). |
| 0007 | Brood children unaware, hatchery a dashboard | applies | Brood topology, shared by both engines. |
| 0008 | Swap cerebrate and overlord names | applies | Agent names, not engine behavior. |
| 0009 | Foreground-blocking watch | superseded | Superseded by ADR-0011. |
| 0010 | Permission allowlist posture | partial | Applies: the verified permission-engine facts in Findings and in the amendments. Current engine only: the allowlist posture (Decisions 1 to 6 and the amendments that change it). The new engine's allow rules are an open item (permission model details). |
| 0011 | Review loop in a main-session skill | partial | Applies: the PR watch loop as a main-session skill with Monitor, run by the overlord, with `github-reviewer` as a stateless fix worker (decision 10). Current engine only: the Consequences note that `local-reviewer` keeps its own loop. |
| 0012 | Path-agnostic artifact transforms | partial | Applies: `plan-to-prd` and `prd-to-issues` never decide the execution path. Current engine only: the clause that cerebrate overlap analysis alone picks single-branch or brood, since new-engine workflow selection is an open item. |
| 0013 | Decoupled leaf pipeline skills | applies | Skill design, not engine behavior. |
| 0014 | Read-only architecture blueprint skill | applies | Skill design, not engine behavior. In the new engine, a workflow runs the git lifecycle it names. |
| 0015 | Deepening refactor execution skill | applies | Skill design, not engine behavior. |
| 0016 | Structural containment of write-capable skills | partial | Applies: decision 1, the decision 4 invariant that no user-reachable write-capable context exists outside the lifecycle, and decision 5. Current engine only: decisions 2 and 3, which describe the current overlord's tools and spawn topology. |
| 0017 | Brood spawn mechanism | applies | Brood launch is shared by both engines. Once decision 12 lands, the permission part of decision 2 (`--dangerously-skip-permissions` and the `skipDangerousModePermissionPrompt` setting) and the choice in the 2026-06-02 amendment (#170) to keep that flag are superseded for both engines. The detached tmux launch, the trusted-base precondition, and that amendment's reasons 2 and 3 stay in force. Amended 2026-10-24: decision 12 landed in slice 4, so this supersession now holds. Reason 1 of the #170 amendment is accepted as a cost, and remote control plus user monitoring replaces the condition that allow rules must cover every action (ADR-0017, Amendment 2026-10-24). |
| 0018 | Declarative workflow state machine | current engine only | Defines the JSON state machine, the router, the run ledger engine and its fallback. Decision 5 keeps governing the current engine; new-engine workflow selection is an open item. Brood state, including the manifest, is covered for both engines by ADR-0021. |
| 0019 | Trust-boundary discipline | partial | Applies: the discipline for committed shell scripts (identifiers, not paths; paths derived from ground truth and checked for containment; hostile content projected to bounded tokens), including boundary 3 and the brood writers. Current engine only: boundaries 1 and 2, and the packaged JSON workflow definition as the sole transition source. |
| 0020 | Single-responsibility shell libraries | applies | Covers shell code only. Its title's "new engine logic" means new shell logic, not this ADR's engine. |
| 0021 | Per-brood-id namespacing | applies | Brood state, shared by both engines. |
| 0022 | Local review parity | applies | Review policy. |
| 0023 | Root-cause remediation doctrine | partial | Applies: decisions 1, 3 and 4, the 2026-09-18 amendment, and decision 2 as far as reviewers return `root-cluster-suspected`. Current engine only: decision 2's routing through the `review_remediation_plan` states. |
| 0024 | No workflow-calls-workflow | current engine only | About the JSON engine's state types and its duplicated review states. |
| 0025 | Young-surface recurrence, GitHub as ledger | applies | Review policy. |
| 0026 | Decision autonomy and post-merge report | current engine only | Its tiers, 2x2, promotion gate, journal and report run on the current engine. The new engine's autonomy decision is code over the autonomy table (decision 1); how that relates to ADR-0026 is an open item (build-step sources). |
| 0027 | Agent-invocable brood remote control | applies | Brood tooling, shared by both engines. |
| 0028 | Seeded hooks in exec form | applies | Setup tooling, not engine behavior. |
| 0029 | Default PR watch and idle window | applies | Governs the PR watch (decision 10). Its rules hold for both engines; the workflow states, terminal and ledger fields it names are the current engine's (see Open items, run record). |
| 0030 | Opt-in post-merge decision report | current engine only | Gates the ADR-0026 report, which runs on the current engine. |
| 0031 | Checked discovery for policy_check.sh | applies | Repo validation tooling, not engine behavior. |
| 0032 | Defer reply marker sentinel | applies | GitHub review policy. |
| 0033 | Automated reviewer identity registry | applies | GitHub review policy. |

## Considered Options

| Option | Rejected because |
|---|---|
| A: JSON workflow files plus one interpreter script | A running script cannot read JSON files. The v1 JSON format cannot express waves, gates or computed decisions |
| C: one workflow per stage | Keeps the order between stages model-driven. Not needed, since pause and resume works inside one workflow |
| D: JSON compiled to scripts | Largest effort. Moves bugs into a generator |
| Ultracode as the engine switch | Improvises workflows, costs more, and skips the safety checks |
| Slash commands as the entry point | Superseded by plain-request launching |
| B: one script per workflow, data tables copied in at build time, launched by name from plain requests, current engine as fallback (CHOSEN) | (chosen) |

## Consequences

**Positive**

- No model turn per transition.
- Workflow logic is code, so it can be tested.
- The overlord prompt gets slim.
- Each run uses its own copy of the script, so a plugin update during a session does not change a run in flight.

**Negative or costs**

- A build step is needed for the tables and shared helpers, because scripts cannot import.
- Side-effect agents carry an idempotency burden (decision 8).
- The engine depends on Claude Code's Workflow tool and its opt-in rule. The fallback (decision 4) limits the damage.
- Users approve each workflow once per project.

## Open items for later steps

This ADR decides none of these. Where a lean is given, it is recorded, not decided.

- Workflow selection. Lean: keep a single classifier that picks the workflow once per request, before launch. ADR-0018 decision 5 keeps governing the current engine; it does not govern the new engine. The answer must cover brood children, whose request text comes from issue bodies.
- Permission model details. Decision 7 settles exact-command allow rules for git work. Still open: whether those rules live in committed or local settings, which rules brood children need under decision 12, and how this relates to ADR-0010 and ADR-0019. Lean: committed settings.
- Build-step sources. Lean: `plugin/references/decision-autonomy-table.json` and `plugin/references/decision-brief-schema.json` on branch `origin/feature/autonomy-knob-decision-briefs`, with a CI drift check. The hard-stop source is not named yet. How this relates to ADR-0026 is not settled.
- Where hard-stop rules live for work outside workflows (the fallback, trivial changes).
- The cerebrate tool-list finding in the S4, S5 and S7 comment.
- Whether `plugin/workflows/` keeps the JSON engine files, given that plugin workflows load `.js` from that folder. S7 shows `.json` files are ignored, so there is no clash today.
- Where the run record lives, and how brood fits.
- How auto mode behaves for git from workflow agents.
- Spike S6 (a long wait inside an agent).
- Spike S8 (worktree base).
- Spike S9 (cost of an agent-written run record).

## References

- https://github.com/brenpike/hivemind/issues/409
- https://github.com/brenpike/hivemind/issues/409#issuecomment-6251786842 (desk research)
- https://github.com/brenpike/hivemind/issues/409#issuecomment-6252100198 (ultracode)
- https://github.com/brenpike/hivemind/issues/409#issuecomment-6254020683 (S1 to S3, launch reliability, decisions)
- https://github.com/brenpike/hivemind/issues/409#issuecomment-6254377722 (S4, S5, S7)
- https://github.com/brenpike/hivemind/issues/408
- `docs/research/2026-10-hivemind-usage-analysis.md`
- `docs/adr/0010-permission-allowlist-posture.md`
- `docs/adr/0017-brood-spawn-mechanism.md`
- `docs/adr/0018-declarative-workflow-state-machine.md`
- `docs/adr/0019-trust-boundary-discipline-ledger-engine.md`
- `docs/adr/0024-no-workflow-calls-workflow-reviewer-composition.md`
- `docs/adr/0026-decision-autonomy-and-post-merge-report.md`
- `docs/adr/0029-default-pr-watch-and-idle-window-lifecycle.md`
