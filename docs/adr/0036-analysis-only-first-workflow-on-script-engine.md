# analysis-only is the first workflow on the script engine

**Status:** accepted, 2026-10-18

## Context

ADR-0035 chose one Claude Workflow script per workflow and left several open items. Issue #409 step 2 builds the first slice of that engine. This ADR records the decisions for that slice and the reasons. It does not restate the rules. Each rule is stated once in its home file, named below as "text:".

## Scope

This ADR governs the new engine as far as this slice builds it: the `analysis-only` workflow script and the build step that generates it. It also records two git fixes made in the same slice (decision 12). Everything else stays as ADR-0035 left it. The current engine, including `plugin/workflows/analysis-only.json`, is unchanged and stays the fallback.

## Decision

1. **analysis-only goes first.** It is read-only, so it carries no git risk. It has the same bug as the other workflows, where open questions end the run as blocked. It matches the autonomy table's `analyze` site. standard-delivery is slice 2. The user chose this order.
2. **Selection.** Decided: `hivemind:route-workflow` stays the single classifier and runs before launch. When it selects `<id>` and `hivemind:<id>` is available, the overlord launches that workflow; otherwise the current engine runs the work. Brood children follow the same rule. The script's `meta.name`, its file stem and the JSON workflow id are the same string, and a test asserts it, so there is no hand-kept mapping. Text: `plugin/agents/overlord.md` (`## Engine`); test: `tests/workflow-scripts/`.
3. **`plugin/workflows/` holds both engines.** Decided: each workflow keeps `<id>.json` for the current engine (the fallback) beside its generated `<id>.js`. Reason: S7 showed the plugin loader ignores `.json` files, so the two do not clash. Text: `plugin/workflows/`.
4. **Build sources.** Decided: data lives in `plugin/references/*.json`, shared libraries in `plugin/workflow-src/lib/`, and each workflow's source in `plugin/workflow-src/<id>/`. `tools/build_workflows.mjs` builds the scripts, and its `--check` mode is the drift check that `tools/validate.sh` runs. The new engine's hard-stop source is the autonomy table's `hard_stops` array. Text: `tools/build_workflows.mjs`, `plugin/references/decision-autonomy-table.json`.
5. **Data copied with one change.** Decided: the autonomy table and the decision-brief schema keep the #408 data structure, but six clauses that point to `decision-autonomy.md` sections are removed. This departs from the word "unchanged" in ADR-0035 decision 1. Reason: those sections do not exist on this branch, and the schema descriptions are shown to the model at runtime, so the clauses would point it at sections that are not there. Text: `plugin/references/decision-autonomy-table.json`, `plugin/references/decision-brief-schema.json`.
6. **One resolution function.** Decided: `decide()` is the only place a decision is resolved. The decision kind comes from the call site in code, never from `brief.kind`. Weak recommendations are taken. Criticality never makes it ask. An invalid level asks, treated as `low`. Any other failure asks. Text: `plugin/workflow-src/lib/decide.js`.
7. **Pause contract.** Decided: the contract for pausing to ask the user lives in one file. A run pauses at most 3 times. After that it completes and lists the questions still open. It never ends as blocked because of questions. Text: `plugin/workflow-src/lib/result.js`.
8. **Autonomy level knob deferred.** Decided: slice 1 runs at the autonomy table's default level. The user-set level comes in slice 3, as plugin `userConfig`. Text: `plugin/references/decision-autonomy-table.json`.
9. **Relation to ADR-0026.** Decided: ADR-0026 stays current engine only. On the new engine, the decisions a run took are listed in the run's final message. This slice has no decision journal and no post-merge report. Text: `plugin/workflow-src/lib/result.js`.
10. **No run record for analysis-only.** Decided: the analysis-only workflow keeps no run record. A paused run resumes in the same session or after `claude --resume`. A fresh session starts the run over. Text: `plugin/workflow-src/analysis-only/main.js`.
11. **Permissions this slice.** Decided: the only approval is the user's one-time approval to launch the workflow. This slice commits no `Workflow` or git allow rules. A user who puts `Workflow(hivemind:analysis-only)` in `permissions.deny` gets the current engine, because the overlord falls back. Text: `plugin/agents/overlord.md` (`## Engine`).
12. **Git fixes in the same slice.** Decided: `hivemind:create-working-branch` creates branches with `--no-track` and unsets an upstream whose name does not match the branch. `hivemind:open-plan-pr` makes its first push with `git push -u origin HEAD:<branch>`. Reason: `git switch -c <branch> origin/main` made the working branch track main, so a plain `git push` or a force-with-lease retry could target trunk. The earlier session worked around it with `git push -u origin <branch>:<branch>`. The fix removes that workaround, and the user asked for it in this PR rather than a follow-up issue. Text: `plugin/skills/create-working-branch/SKILL.md` (requirement 6), `plugin/skills/open-plan-pr/SKILL.md` (step 6); pin: `tests/policy/safety-working-branch-no-track.json`.

## Settled ADR-0035 open items

| ADR-0035 open item | Settled by |
|---|---|
| Workflow selection | Decision 2 |
| Build-step sources, including the hard-stop source and the ADR-0026 relation | Decisions 4, 5 and 9 |
| Whether `plugin/workflows/` keeps the JSON engine files | Decision 3 |
| Where the run record lives | Decision 10, for analysis-only only. standard-delivery is still open |

## Considered Options

| Option | Rejected because |
|---|---|
| standard-delivery first | Carries git risk and needs the open permission model, idempotency and run record answers |
| A hand-kept map from route-workflow ids to script names | Drifts. A test on equal names cannot drift |
| Script files in a folder separate from the JSON files | S7 shows no clash, and one folder keeps both engines of a workflow side by side |
| Copy the #408 data byte for byte | The six pointer clauses would send the model to sections that do not exist |
| Let the brief's own `kind` pick the decision rule | The model could pick the rule that lets it act. The call site in code is fixed |
| End the run as blocked when questions remain | This is the bug the slice fixes |
| Ship the autonomy level knob now | Not needed to prove the engine; it needs plugin `userConfig` |
| Journal decisions as in ADR-0026 | Adds a run record and report path this slice does not need |
| Commit `Workflow` and git allow rules now | analysis-only runs no git. The rules belong with standard-delivery |
| analysis-only first, one classifier, names equal by test, both engines in `plugin/workflows/`, built from `plugin/workflow-src/` (CHOSEN) | (chosen) |

## Consequences

**Positive**

- analysis-only no longer ends as blocked when it has questions.
- Decisions resolve in tested code with one entry point.
- The build drift check keeps generated scripts in step with their sources.

**Negative or costs**

- Two engines run side by side until slice 5.
- Contributors need Node 18 or later to run the workflow script tests.
- analysis-only runs at the default autonomy level only, until slice 3.

## Deferred open items

| Item | Target slice |
|---|---|
| Git permission model (committed or local rules, brood children) | 2 (standard-delivery) |
| Auto mode for git run from workflow agents | 2 |
| Idempotency for side-effect agents (ADR-0035 decision 8) | 2 |
| Run record and how brood fits | 2 |
| Spike S9 (cost of an agent-written run record) | 2 |
| Git hard stops as code | 2 |
| Check the cerebrate tool-list finding | 2, before the slice starts |
| Autonomy level as plugin `userConfig` | 3 |
| Reviewer briefs | 3 |
| Brood on the new engine, spike S8 (worktree base) | 4 |
| `--permission-mode auto` for brood children (ADR-0035 decision 12) | 4 |
| Retire the JSON engine, slim the overlord | 5 |
| Spike S6 (a long wait inside an agent) | Only if the PR watch leaves the main session |

## References

- https://github.com/brenpike/hivemind/issues/409
- https://github.com/brenpike/hivemind/issues/408
- `docs/adr/0035-one-script-per-workflow-engine.md`
- `docs/adr/0026-decision-autonomy-and-post-merge-report.md`
