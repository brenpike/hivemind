# standard-delivery is the second workflow on the script engine

**Status:** accepted, 2026-10-20

## Context

ADR-0035 chose one Claude Workflow script per workflow. ADR-0036 put analysis-only on that engine as slice 1 and deferred the git questions to slice 2. Issue #409 tracks the work. Slice 2 moves the pre-PR part of standard-delivery onto the engine.

Three things in standard-delivery cost the user today. Every planner question ends the run as blocked. Every transition costs an overlord turn, and 52% of overlord tool calls are ledger bookkeeping. Git safety is written in prose. The slice must also avoid a new state machine in prose and side-effect agents that repeat their effects when a run is replayed (ADR-0035 decision 8, spike S5).

This ADR records the slice decisions, the user's three calls, and the results of spikes S11 and S12. It does not restate the rules. Each rule is stated once in its home file, named below as "Text:". Most homes do not exist yet; "Lands in:" names the PR in the outline below that creates each one.

## Scope

This ADR governs:

- the new engine's standard-delivery workflow, from the request up to and including opening the PR;
- the committed git scripts behind the git skills, which both engines use;
- the interim start of brood children without the Workflow tool (decision 10);
- the removal of Bash from cerebrate (decision 1), which also changes the current engine.

The post-PR watch and pr-feedback-remediation stay on the current engine until slice 3. Every other ADR keeps the scope ADR-0035 gave it. New permission-engine facts are recorded in ADR-0010 under "## Amendment 2026-10-20: tool grants and prompts for workflow agents"; this ADR uses them and does not repeat them.

## Workflow outline

`hivemind:standard-delivery` runs these steps in code. Each step's rules live in the homes the decisions name.

1. Facts: a runner runs a read-only facts script (branch, trunk, HEAD, dirty paths, trunk freshness, and the text of any issue or PR the request names).
2. Plan: cerebrate returns a plan checked against a schema. Its questions and the plan acceptance go through `decide()` or the pause contract.
3. Branch: a runner creates or confirms the working branch.
4. Waves: code computes each ready wave and runs the workers in parallel. A runner commits once per wave.
5. Version bump: a runner runs the bump-type engine, a drone makes the edit, a runner commits it.
6. Validate: a drone runs the project's validation commands, with bounded fix rounds.
7. Local review: `hivemind:local-reviewer` runs, and a code table routes its exit reasons.
8. PR: a runner pushes through `push-branch.sh` and opens the PR or reuses an open one.
9. The overlord relays the message, applies the ADR-0029 watch rule, and hands the watch to pr-feedback-remediation on the current engine.

A workflow script cannot run a shell, so it sees only what agents report. The hard stops sit in the committed scripts, and the workflow reads their routing lines from a schema field and blocks when a line is missing or malformed.

## Decision

Decisions 1 to 3 are the user's calls. Decisions 4 to 23 are journal items J1 to J20 of the slice plan. Decisions 24 and 25 come from the S11 surprises.

1. **The planner has no shell (call 1, option A).** Decided: cerebrate's `tools:` drops Bash and every `Bash(...)` entry. A read-only facts step gives the planner what the shell gave it: branch state and the text of any issue or PR the request names. standard-delivery runs that step anyway. analysis-only gains a facts step. On the current engine, the overlord passes issue and PR text through the facts skill when it delegates. Reason: the cerebrate tool-list finding below. Read-only becomes true by construction instead of by prompt, Glob and Grep come back (S11-c), and planner prompts drop to near zero. S11 surprise 3 backs it: any agent with Bash loses Glob and Grep. Text: `plugin/agents/cerebrate.md` (frontmatter, and the line that prefers Read, Glob and Grep), the CLAUDE.md line on read-only enforcement, a pin in `tests/policy/` that replaces the overclaimed rule in `safety-planner-no-write.json`, the new facts skill, `plugin/workflow-src/analysis-only/main.js`, `plugin/agents/overlord.md`. Lands in: PR2 (facts skill and script), PR3 (the rest).
2. **No run record for standard-delivery (call 2, option A).** Decided: git and GitHub are the record: the working branch, one commit per wave, and the PR. A new session restarts the request. The planner plans what is left on the branch, and each git step checks for its own earlier effect (decision 5). This matches analysis-only (ADR-0036 decision 10). Reason: a second record duplicates durable state and can go stale; 35 of 37 fallback runs were on old definitions. Spike S9 is not needed. Text: `plugin/workflow-src/standard-delivery/main.js`. Lands in: PR6.
3. **Trust the planner's gate flags and show every taken decision (call 3, option A).** Decided: `decide()` keeps trusting the planner's irreversible, architectural and safety flags, as in slice 1. Every decision a run takes for the user is listed in the final message and in the PR body. Reason: in delivery nothing leaves the branch before the user merges, and the merge is the one irreversible step. The PR body puts every taken decision in front of the user at that step, and a branch change undoes one. Text: `plugin/workflow-src/lib/decide.js` (unchanged), `plugin/workflow-src/lib/result.js`, the PR step in `plugin/workflow-src/standard-delivery/`. Lands in: PR7.
4. **Scope (J1).** Decided: the pre-PR part of delivery goes on the engine. When the result names a PR, the overlord applies the ADR-0029 watch rule and runs pr-feedback-remediation (intake `watch`) on the current engine. Reason: the watch stays in the main session (ADR-0035 decision 10), and post-PR remediation is already tested there. Post-PR on the engine moves to slice 3 with reviewer briefs. Text: `plugin/agents/overlord.md` (`## Engine`). Lands in: PR8.
5. **Git side effects only through committed scripts (J2).** Decided: branch, commit, push and PR open run only through committed scripts behind the plugin skills. The scripts hold the hard stops and the checks for earlier effects: an existing branch is confirmed, nothing to commit means already done, an open PR is reused, a repeated push is harmless. The skills keep their contracts and routing lines, so the current engine uses the same scripts. Reason: ADR-0035 decision 8 and ADR-0036's deferred item "git hard stops as code". Text: scripts under `plugin/skills/create-working-branch/`, `plugin/skills/molt/` and `plugin/skills/open-plan-pr/`, plus `plugin/skills/push-branch/scripts/push-branch.sh`; shell tests; the `tools/validate.sh` mapping. Lands in: PR2.
6. **No seeded deny or ask rule for raw git push (J3).** Decided: the seed template gets no rule that tries to stop `git push` to trunk. Reason: Bash rules match the command as written, so `git -C . push` gets past them, and such a rule is a deny-list. S12 confirmed that nothing in the harness stops it: the auto-mode classifier accepted a raw `git push origin HEAD:main` from a workflow agent, and the push landed. Trunk safety lives in `push-branch.sh`, and server-side branch protection closes the gap. See Recorded residuals. Text: `plugin/skills/push-branch/scripts/push-branch.sh`. Lands in: no change; the script already refuses trunk.
7. **No committed allow rules for git writes (J4).** Decided: the git scripts run under each skill's own `allowed-tools` grant, which names the exact plugin path. Wildcard script-path rules are rejected. This replaces the project allow rules for exact commands in ADR-0035 decision 7. Reason: S11-a passed, so the primary branch holds: the script ran with no prompt in manual mode, and S12 shows the same grant path in auto mode. A wildcard rule would run a file planted at a matching path without a prompt. Each Skill call from a workflow agent still prompts once in manual mode unless a `Skill(...)` rule covers it (S11-a, S11-f); see Deferred items. Text: the `allowed-tools` frontmatter of the git skills. Lands in: PR2.
8. **Resume by name, no seeded `Workflow(...)` rule (J5).** Decided: the overlord resumes a paused run with `Workflow({name, resumeFromRunId, args})`, never with `scriptPath`. The harness's "don't ask again" is the user's per-project opt-in, and the seed template adds no `Workflow(...)` rule. Reason: S11-e. A resume by name served earlier agents from cache and raised no prompt once "don't ask again" had written `Workflow(<name>)` to the project's `.claude/settings.local.json`. Left alone, the model resumed by `scriptPath` on its persisted copy, which prompts every time and is not covered by that rule (S11 surprise 2). See Recorded residuals. Text: `plugin/agents/overlord.md` (`## Engine`). Lands in: PR5.
9. **Seed-template additions (J6).** Decided: the seed template gains `Skill(hivemind:route-workflow)` and a Read rule for the plugin install folder, and nothing else. Reason: S11-f showed the Skill rule stops the main-session Skill prompt, and the same rule form stops workflow-agent Skill prompts. S11-d showed a `Read(//<plugin folder>/**)` rule stops workflow-agent Read prompts for plugin files while other outside-repo Reads still prompt. The Read rule must name the folder `${CLAUDE_PLUGIN_ROOT}` resolves to, which for a marketplace install is the install path. Text: `plugin/skills/seed-hive/`, `plugin/skills/_shared/settings-merge.sh`. Lands in: PR5.
10. **Brood children stay on the current engine until slice 4 (J7).** Decided: spawn-brood starts children with `--disallowedTools Workflow`, so the hatchery's started-evidence keeps working. This supersedes the brood clause of ADR-0036 decision 2 until slice 4. Reason: S11-h showed the Workflow tool is absent from such a session and the overlord falls back in one line and runs the state machine to `complete`. Text: `plugin/skills/spawn-brood/scripts/spawn-brood.sh`. Lands in: PR8.
11. **Runners are `hivemind:drone` on haiku, invoking the skill (J8).** Decided: every runner is a haiku `hivemind:drone` that invokes the skill for its step. The six-agent roster stays. Reason: S11-g. Both the drone and an untyped haiku agent were correct 3 of 3. The drone used about 28% fewer tokens (76k against 106k) and took about 1.6 s longer (8.2 s against 6.6 s). The haiku drone read none of the governance docs its body says to load; see Risks. Text: `plugin/workflow-src/standard-delivery/main.js`. Lands in: PR6.
12. **One commit per wave (J9).** Decided: a runner makes one checkpoint commit after each wave finishes, waves of one included. Parallel workers never commit. Reason: one code path. Text: `plugin/workflow-src/standard-delivery/main.js`. Lands in: PR6.
13. **Waves are a pure function that mirrors next-wave (J10).** Decided: code computes each ready wave from dependencies and file scopes, with parity tests against the next-wave fixtures. Reason: one rule set for both engines, tested. Text: `plugin/workflow-src/lib/waves.js`; tests: `tests/workflow-scripts/`. Lands in: PR4.
14. **The plan is checked against a schema (J11).** Decided: the planner's plan is validated against a schema. Delivery is single or multi only, and both run as one branch and one PR, as in the current engine graph. Brood stays out until slice 4. Text: `plugin/references/plan-schema.json`. Lands in: PR4.
15. **Taken decisions are shown (J12).** Decided: decisions taken for the user go in the final message and, under decision 3, in the PR body. Text: as decision 3. Lands in: PR7.
16. **Validation is a drone step with bounded fix rounds (J13).** Decided: a drone runs the project's documented validation commands. Failures get a bounded number of fix rounds through `decide()` kind `validation_remediation`, then the run asks. Text: `plugin/workflow-src/standard-delivery/main.js`, `plugin/references/decision-autonomy-table.json`. Lands in: PR7.
17. **Local review runs inside the workflow (J14).** Decided: escalation and root-cluster go back to planning. A remediation plan always asks, as the table says. user-input-required and high-severity-rejection ask in plain words until slice 3. Text: the local-review table in `plugin/workflow-src/standard-delivery/`. Lands in: PR7.
18. **Draft marker in the build (J15).** Decided: the build skips a workflow marked as a draft, and tests build it in memory, so delivery lands in pieces without going live. Text: `tools/build_workflows.mjs`. Lands in: PR4.
19. **No new opt-in for go-live (J16).** Decided: the workflow approval prompt is the opt-in and a `permissions.deny` rule is the opt-out, as in slice 1. Text: `plugin/agents/overlord.md` (`## Engine`). Lands in: PR8.
20. **Spikes run and skipped (J17).** Decided: S11 and S12 ran (see Spike results). S9 is not needed under decision 2, S6 is not needed while the watch stays in the main session, and S8 belongs to slice 4. Text: this ADR. Lands in: PR1.
21. **smoke-603 low items (J18).** Decided: N1 (open questions recorded as complete on the state machine) is a recorded residual. N2 (the routing YAML printed to chat) is fixed. N3 (the planner tries to run scripts) is dissolved by decision 1. N4 (made-up inputs-file tokens) is a recorded residual. Text: `plugin/agents/overlord.md` (`## Engine`) for N2. Lands in: PR5 (N2), PR3 (N3).
22. **New engine facts go to ADR-0010 first (J19).** Decided: the facts S11 and S12 verified are recorded in ADR-0010, as its own authority rule requires, and the pinned NON-FINDING there is left as it is. Text: `docs/adr/0010-permission-allowlist-posture.md` ("## Amendment 2026-10-20: tool grants and prompts for workflow agents"). Lands in: PR1.
23. **Autonomy level stays at the table default (J20).** Decided: standard-delivery runs at the autonomy table's default level until slice 3, as ADR-0036 decision 8 does for analysis-only. Text: `plugin/workflow-src/standard-delivery/main.js`, `plugin/references/decision-autonomy-table.json`. Lands in: PR6.
24. **Launch and resume text carries no runner instructions (S11 surprise 1).** Decided: runners get their task only from the script. The overlord's launch args and resume reply carry no instruction that could conflict with a runner's task. Reason: the harness relays the user message that started or resumed a run to every workflow agent and tells the agent that this message wins over the script's prompt. In S11, haiku agents tried to call Workflow themselves, skipped their task, or obeyed "Do not edit anything" from the main message, and a resume message overrode a resumed agent's task. See Risks. Text: `plugin/agents/overlord.md` (`## Engine`). Lands in: PR5.
25. **Plain `git` from the repo folder (S11 surprise 4).** Decided: the scripts, the skill text runners follow, and runner prompts use plain `git` run from the repo folder, never `git -C <dir>`. Reason: in S11-b, `git status --short` ran with no prompt and `git -C <repo> status --short` prompted. In S11-h, cerebrate used `git -C` and every call prompted. Text: the git skills and scripts, `plugin/workflow-src/standard-delivery/`. Lands in: PR2, PR6.

## Cerebrate tool-list finding

At runtime cerebrate has Read, WebSearch, WebFetch and Bash, and nothing else that matters here. Glob, Grep, LSP and the claude-mem tools are missing, and Bash is the whole tool.

Evidence:

- **Tool list.** Claude Code 2.1.304, cerebrate spawned through the Agent tool outside a workflow: Read, WebSearch, WebFetch, Bash and SubagentHandback. Spike S3 (2.1.302, a workflow agent) showed the same set plus StructuredOutput and advisor, so the finding is not specific to workflows.
- **Glob and Grep.** The tools reference (code.claude.com/docs/en/tools-reference, "Glob tool behavior") says that on macOS, Linux and WSL they are left out of the default tool set, and a subagent gets them back only when its `tools:` lists them and leaves out Bash. cerebrate's 28 `Bash(git ...)` and `Bash(gh ...)` entries count as Bash. S11-c and S11 surprise 3 confirm it.
- **LSP** stays inactive until a code-intelligence plugin is installed. The **claude-mem tools** are inherited MCP tools and are absent when claude-mem is not connected.
- **Bash is not scoped.** The sub-agents docs define no `Bash(...)` specifier for `tools:`. In smoke-414, smoke-602 and smoke-603, planner commands outside the patterns reached a normal permission prompt, not a refusal. S11-b confirmed it: an agent with `tools: Read, Bash(git status *)` had the whole Bash tool, and `touch` prompted.

What follows: the planner was read-only only because its prompt said so. The CLAUDE.md line "Read-only enforcement on cerebrate is done by restricting `tools:` list" is false as written. `tests/policy/safety-planner-no-write.json` pins only that Write and Edit are absent, so its rule "Planner cannot write files" claims more than it checks. cerebrate's line that prefers Read, Glob and Grep points at tools it does not have, so every search becomes a Bash call, the main source of planner prompts in manual mode (up to 19 per round in smoke-602). Decision 1 resolves all four.

## Spike results

Claude Code 2.1.304. S11 ran in manual mode and S12 in auto mode, with haiku workflow agents, in throwaway repos with local bare remotes. Full results: `~/code/hivemind-workflow-spikes/results-s11s12.md` and https://github.com/brenpike/hivemind/issues/409#issuecomment-6281842682.

| Item | Verdict | Decides | Branch taken |
|---|---|---|---|
| S11-a: a skill's script runs under the skill's exact-path grant inside a workflow agent with no prompt. The Skill call itself prompts once without a `Skill(...)` rule | PASS (script); Skill call prompts | J4 (decision 7) | Primary: no committed git allow rules. The J4 fallback is not needed for the script call |
| S11-b: `tools: Read, Bash(git status *)` grants the whole Bash tool; `touch` prompts, not refused | PASS | Backs J4 and decision 1 | None |
| S11-c: an agent with `Read, Glob, Grep` and no Bash gets Glob and Grep | PASS | Backs call 1 option A | Option A |
| S11-d: a workflow agent's Read of plugin files prompts; a `Read(//<plugin folder>/**)` project rule stops it | PASS | J6 (decision 9) | Seed the Read rule |
| S11-e: resume by `name` serves earlier agents from cache, and "don't ask again" covers it | PASS, with two conditions (resume by name must be required; the relayed resume message) | J5 (decision 8) | Adopt resume by name; decision 24 covers the relay |
| S11-f: a `Skill(...)` rule stops main-session and workflow-agent Skill prompts | PASS | J6 (decision 9) | Seed `Skill(hivemind:route-workflow)` |
| S11-g: haiku drone against untyped haiku, one skill each: both 3 of 3; drone 8.2 s and 76k tokens, untyped 6.6 s and 106k | PASS, no large cost | J8 (decision 11) | Keep the drone |
| S11-h: with `--disallowedTools Workflow` the tool is absent and the overlord runs the state machine to `complete` | PASS | J7 (decision 10) | Adopt |
| S12 flow: commit, scripted push and `gh pr create --dry-run` from workflow agents in auto mode, untyped and drone, 0 prompts, 0 blocks | PASS | ADR-0036 deferred item "auto mode for git run from workflow agents" | Auto-mode delivery can go live |
| S12 raw push: the auto-mode classifier accepts `git push origin HEAD:main` from a workflow agent, and it lands | Recorded | J3 (decision 6) | Residual stands |

Spike limits: S12 used pre-placed `Workflow(...)` rules, so it did not observe auto mode's own launch prompt. Its `gh pr create --dry-run` exited before any GitHub call, because origin was a local path; it proves the command is not blocked, not the dry-run output. The live delivery smoke in PR8 covers both.

## Settled ADR-0035 open items and ADR-0036 deferred items

| Item | Source | Settled by |
|---|---|---|
| Permission model details (committed or local rules, brood children) | ADR-0035 open item; ADR-0036 deferred item | Decisions 7, 8 and 9. Brood children: decision 10 until slice 4 |
| Manual-mode prompt reduction | ADR-0036 decision 11 and deferred item | Decisions 1, 8, 9 and 25 |
| Where hard-stop rules live for work outside workflows | ADR-0035 open item | Decision 5, for git side effects: the scripts serve both engines. Other hard stops outside workflows stay open |
| The cerebrate tool-list finding | ADR-0035 open item; ADR-0036 deferred item | The finding above and decision 1 |
| Where the run record lives, and how brood fits | ADR-0035 open item; ADR-0036 deferred item | Decision 2 for standard-delivery. Brood stays slice 4 (decisions 10 and 14) |
| How auto mode behaves for git from workflow agents | ADR-0035 open item; ADR-0036 deferred item | S12: it works |
| Idempotency for side-effect agents | ADR-0036 deferred item | Decision 5 |
| Git hard stops as code | ADR-0036 deferred item | Decision 5 |
| Gate flags checked in code | ADR-0036 deferred item | Decision 3: not checked in code, by choice; every taken decision is shown |
| Spike S9 | ADR-0035 open item; ADR-0036 deferred item | Not needed (decision 2) |
| Spike S6 | ADR-0035 open item; ADR-0036 deferred item | Not needed while the watch stays in the main session (decision 4) |
| Shell interpolation of git identifiers | ADR-0036 deferred item | Outside this slice: #413 closed by #417; the github-reviewer remainder is tracked in #416 |

## Considered Options

| Option | Rejected because |
|---|---|
| Call 1 B: keep the planner's shell and add code checks | Read-only stays a promise. Prompts remain, because allow rules cannot cover every way of writing a command. analysis-only gets no check |
| Call 1 C: fix the docs and the pin only | Leaves every observed problem in place |
| Call 2 B: agents write a run record at milestones, plus a resume-point argument | An extra agent call per milestone, needs S9, and brings back record drift and version skew |
| Call 2 C: the overlord writes a run record when a run pauses or ends | The model copies data, smoke-602 showed copy errors, and the record is coarse |
| Call 3 B: code raises gate flags for plan steps on a project-declared list of sensitive paths | The list is a deny-list that grows with each miss and needs setting up per project |
| Call 3 C: a second model reviews each decision before it is taken | An extra model call per decision, and it is still model judgment |
| J3: a seeded deny or ask rule for raw `git push` | Bash rules match the command as written, so `git -C . push` gets past them. A deny-list |
| J4: wildcard allow rules for plugin script paths | A file planted at a matching path would run without a prompt |
| J4: committed exact-command allow rules for git writes (ADR-0035 decision 7) | Not needed: S11-a shows the skill's own exact-path grant runs the script with no prompt |
| J5: a seeded `Workflow(...)` allow rule | "Don't ask again" already writes that rule as the user's own per-project opt-in |
| J5: resume by `scriptPath` | Prompts on every resume and is not covered by the `Workflow(<name>)` rule (S11-e) |
| J8: an untyped runner agent | No large cost from the drone in S11-g. The drone keeps the six-agent roster and used fewer tokens |
| Calls 1 A, 2 A and 3 A, with the journal as recorded (CHOSEN) | (chosen) |

## Consequences

**Positive**

- Delivery transitions cost no model turns. Fixed agent calls per run are facts, plan, branch, bump, validate, review and PR; each wave adds its workers plus one commit runner.
- Planner questions are decided or asked; they never end the run as blocked.
- Git hard stops and the checks for earlier effects are code, shared by both engines.
- The planner is read-only by construction, and its searches no longer prompt.
- Delivery keeps no state that can drift from git and GitHub.

**Negative or costs**

- A new session re-plans a paused delivery run, which takes a few minutes. A crash mid-wave leaves uncommitted edits, and the git check stops on them until the user decides.
- An under-flagged architectural choice still costs a round of rework.
- On the current engine, the overlord must pass issue and PR text to the planner, and WebFetch covers only public GitHub.
- In manual mode, each Skill call from a workflow agent prompts once unless a `Skill(...)` rule covers it.
- Users approve the workflow once per project, through "don't ask again".

## Risks

- **The relayed user message outranks runner tasks.** Decision 24 keeps the overlord's own text clean, but the user's request is relayed to every runner as written. A delivery request worded like "no changes", or one that names a git action, can make a runner skip or change its step. The workflow blocks when a script's routing line is missing or malformed, which catches a skipped git step, but not a drone that edits less than its task asks. The PR8 smoke must cover it.
- **Runners skip governance.** The haiku drone in S11-g read none of the governance docs its body says to load. Runner safety rests on the committed scripts, not on the drone's reading.
- ADR-0037 names text homes that do not exist yet. A later PR that changes a decision amends this ADR in the same PR.
- PR2 changes git skills the fallback uses. Their contracts and routing lines stay unchanged, with tests on both call paths.
- The spike facts are tied to Claude Code 2.1.304.

## Landing PRs

| PR | Content | Depends on |
|---|---|---|
| PR1 | This ADR and the ADR-0010 amendment | Calls 1 to 3, S11, S12 |
| PR2 | Git and facts engines shared by both engines: committed scripts behind create-working-branch, molt and open-plan-pr; a new read-only facts skill and script; shell tests; validate.sh mapping. May split into facts and branch, then commit and PR open | PR1 |
| PR3 | Planner posture (decision 1): drop Bash from cerebrate and its prose, fix the CLAUDE.md line, replace the overclaimed pin, pass issue and PR text through the facts skill, add a facts step to analysis-only | PR2 |
| PR4 | Engine libraries: `waves.js` with parity tests, a routing-line parser, `plugin/references/plan-schema.json`, the build's draft marker | PR1 |
| PR5 | Prompt reduction: seed-template additions, resume by name, launch and resume text with no runner instructions, routing outcome kept out of chat | PR1 |
| PR6 | Delivery core as a draft: facts, plan, decide or ask, branch, waves, commits | PR2, PR3, PR4 |
| PR7 | Delivery tail as a draft: bump, validate, local review, PR open with taken decisions in the PR body, `pr` in the result | PR6 |
| PR8 | Go-live: build `standard-delivery.js`, the overlord PR handoff, spawn-brood starts children without Workflow, contract tests, then a live delivery smoke in manual and auto mode | PR5, PR7 |

PR3 and PR4 touch disjoint files and can proceed in parallel, and so can PR4 and PR5.

## Deferred items

| Item | Target |
|---|---|
| Whether the seed template also gets `Skill(...)` rules for the skills runners invoke. Without them, each such Skill call prompts once in manual mode (S11-a, S11-f) | Slice 2, PR5 |
| Each drone run creates an empty `.claude/agent-memory/hivemind-drone/` folder in the consumer repo (`memory: project`; S11-g). An observed side effect to examine before delivery runs many drones per run | Slice 2, PR8 |
| Auto mode's own workflow launch prompt, which S12 did not observe, and `gh pr create` against a real GitHub remote | Slice 2, PR8 live smoke |
| Hard stops outside workflows other than git side effects | Unassigned |
| Post-PR remediation on the engine, reviewer briefs, autonomy level as plugin `userConfig` | 3 |
| Brood on the new engine, `--permission-mode auto` for brood children, spike S8 | 4 |
| Retire the JSON engine and the fallback, slim the overlord | 5 |

## Recorded residuals

- **Raw push to trunk (decision 6).** Root cause: the harness has no control that stops a raw `git push origin HEAD:main`. Bash rules match the command as written, and the auto-mode classifier accepted that push from a workflow agent in S12, where it landed. Bounded impact: hivemind's own pushes go through `push-branch.sh`, which refuses trunk. Only an agent that steps outside its scripts can push to trunk, and server-side branch protection on the remote stops it there. A typed drone in S12 refused on its own, which helps but is not a control. Why the obvious fix was rejected: a deny or ask rule is a deny-list that `git -C . push` gets past.
- **A plugin update between pause and resume (decision 8).** Root cause: a resume by `name` runs the currently installed script, not the copy the run started with. Bounded impact: only when the plugin updates while a run is paused. Earlier agents are served from cache, and every git step checks for its own earlier effect (decision 5). Why the obvious fix was rejected: resume by `scriptPath` runs the stored copy, but it prompts on every resume and no rule covers it.
- **Open questions recorded as complete on the current engine (smoke-603 N1).** Root cause: the fallback's `analyze` state maps open questions to blocked, while the overlord in one of three sessions recorded `complete` and listed the questions, as the script engine would. The two engines disagree on this case. Bounded impact: current engine only, low severity, and the questions were shown to the user. Why the obvious fix was rejected: rebuilding `decide()` in fallback prose is what failed in #408, and the fallback retires in slice 5.
- **Made-up inputs-file tokens (smoke-603 N4).** Root cause: the overlord writes the inputs-file token itself, with a fixed fake timestamp and a low-entropy suffix, while the skill relies on it for per-invocation uniqueness (ADR-0019). Bounded impact: current engine only, and it matters only with two concurrent overlords in one checkout. Why the obvious fix was rejected: it costs one extra tool call per transition, and the code retires in slice 5.

smoke-603 N3 (the planner tries to run scripts) is not a residual: decision 1 removes the shell.

## References

- https://github.com/brenpike/hivemind/issues/409
- https://github.com/brenpike/hivemind/issues/409#issuecomment-6281842682 (S11 and S12)
- https://github.com/brenpike/hivemind/issues/409#issuecomment-6281012540 (smoke-603)
- https://github.com/brenpike/hivemind/issues/409#issuecomment-6279153393 (smoke-602)
- https://github.com/brenpike/hivemind/issues/409#issuecomment-6258711406 (smoke-414)
- https://github.com/brenpike/hivemind/issues/408
- `docs/adr/0010-permission-allowlist-posture.md` ("## Amendment 2026-10-20: tool grants and prompts for workflow agents")
- `docs/adr/0029-default-pr-watch-and-idle-window-lifecycle.md`
- `docs/adr/0035-one-script-per-workflow-engine.md`
- `docs/adr/0036-analysis-only-first-workflow-on-script-engine.md`
