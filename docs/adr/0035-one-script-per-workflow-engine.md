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
12. **Brood children run with `--permission-mode auto`, not `--dangerously-skip-permissions`.** The switch lands in engine work, after a re-check of reason 1 in ADR-0017's 2026-06-02 amendment (#170): under auto mode a child runs no Bash while the classifier model is unavailable. Reason 2 in that amendment (hooks and MCP servers run at launch, before any permission check) stays covered by the trusted-base precondition. Detached children cannot answer prompts, so allow rules must cover every action they take. Until the switch lands, children keep the current flag.

## What moves where

| Home | Holds |
|---|---|
| Workflow scripts | Step sequence, waves, review loops, the autonomy decision as code over the autonomy table, brief validation through the schema |
| Data files | The tables and schemas, copied into scripts at build time |
| Slim overlord | Talking to the user, launching workflows, relaying questions and resuming, the PR watch, the fallback |
| Unchanged for now | The current engine, kept as the fallback |

## Supersession of other ADRs

Every existing ADR stays in force. For the new engine, only the clauses listed below are superseded, each within the scope stated with it. Anything not listed is open: it stays in force until an ADR names it as superseded. If the new engine seems to conflict with an unlisted clause, the clause wins and the conflict becomes an open item.

| Superseded clause | Scope | Replaced by |
|---|---|---|
| ADR-0018 decision 2, the part that makes workflow definitions JSON files | New engine only | Decision 1 |
| ADR-0018 decision 8, the part that makes committed transition scripts the executor | New engine only | Decision 1 |
| ADR-0017 2026-06-02 amendment (#170), brood children keep `--dangerously-skip-permissions` | Brood child launch, once decision 12 lands | Decision 12 |

The current engine, which is also the fallback, keeps both ADR-0018 clauses. The run-ledger part of ADR-0018 decisions 2 and 8 is not superseded (see Open items, run record). ADR-0029 keeps governing the PR watch (decision 10).

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

- Workflow selection. Lean: keep a single classifier, run once per request as the workflow's first step. ADR-0018 decision 5 stays in force until this is settled. The answer must cover brood children, whose request text comes from issue bodies.
- Permission model. Lean: exact-command allow rules in committed settings. How this relates to ADR-0010 and ADR-0019 is not settled.
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
