# HIVEMIND Usage Analysis (October 2026)

This document records a one-time analysis of how HIVEMIND was used across real Claude Code sessions. It also records what the follow-up work (PR #408) taught us. It is research, not a spec. Later work should start from it, not from the PR #408 branch.

## Method

The analysis ran on 2026-10-17, early in the session that later produced PR #408. It used Python 3 scripts (run with `python3 -I`) and a few shell commands. All figures below come from that run unless a section says otherwise.

**Sources.**

- **Session logs** under `~/.claude/projects/`: 1,318 JSONL files (about 1.2 GB) in 6 project directories. Each session has one main log plus one log per subagent.
- **Run ledgers:** 661 `state.json` files under `~/code/*/.hivemind/runs/`, from 7 checkouts.
- **Date range:** 2026-09-16 to 2026-10-17.

| Project directory | Log files | Main sessions | Subagent logs |
|---|---|---|---|
| Chatter | 661 | 23 | 638 |
| hivemind | 488 | 18 | 470 |
| Chatter-IntegrationEventRelay | 129 | 5 | 124 |
| Chatter-Rest-Hal | 38 | 1 | 37 |
| game-test | 2 | 2 | 0 |
| skills-tracker | 0 | 0 | 0 |

| Checkout | Run ledgers |
|---|---|
| skills-tracker | 295 |
| Chatter | 208 |
| hivemind | 124 |
| Chatter.Rest.UriTemplates | 13 |
| Chatter.Rest.Hal | 11 |
| Chatter.IntegrationEventRelay | 9 |
| Chatter.IntegrationEventRelay-ci | 1 |

**How sessions were read.** For each main session, the script collected the agent setting, total cost (from the `cost-state` record), PR links, slash commands, every tool call by name, Skill and Agent calls, Bash calls that ran a HIVEMIND engine script, and tool errors. Subagent logs were matched to their parent session and typed from their `.meta.json` file. That gave 49 main sessions and 1,269 subagent logs.

**How prompts were classified.** Human prompts were taken from main-thread user records. The script dropped task notifications, subagent hand-backs, skill loads, system reminders, interrupts and continuation summaries. That left 483 prompts. Each prompt was lower-cased and matched against a fixed set of regular expressions (for example "take rec(s)", "go/yes/start", a bare option pick such as "1" or "A", "merged", "handoff", "layman / wall of text / why"). Categories can overlap.

**How tool calls were classified.** Only main-thread (overlord) tool calls were counted: 9,015 in total. They were grouped as:

- **ledger:** any Write under `.hivemind/`, plus any Bash call that runs `record-state-result`, `next-wave`, `init-run-ledger` or `mark-intent-fallback`, or touches `.hivemind/runs`;
- **delegation:** Agent or Task calls;
- **pr-watch/gh:** Monitor calls and Bash calls that run the PR watch scripts or `gh pr` / `gh api`;
- **git:** other Bash calls that run git;
- **skill:** Skill calls;
- everything else by tool name.

**How tokens were counted.** Output tokens were summed from each assistant record's `usage` field, split into the main thread and subagents (by agent type).

**How runs were read.** For each ledger: workflow, status, mode (deterministic or intent fallback), final state, every event's state and result, and duration from `created_at` to `updated_at`.

## Findings

### 1. The orchestrator spends more than the workers

- 52% of the overlord's own tool calls are ledger bookkeeping. That is 2,270 small input files written for `record-state-result` plus about 1,945 Bash calls to run it.
- Each pass of the implement loop records 3 transitions (`implement_next_step`, `implement_step`, `checkpoint`). One pass covers a whole wave of independent plan steps, not one plan step. The ledgers hold 2,294 `implement_step` completions and 2,294 `checkpoint` completions (the "about 2,300" figure counts these wave passes, not plan steps). They also hold 2,339 `implement_next_step` results that started a wave and 800 final `implement_next_step` results that ended the loop. That is about 7,700 recorded transitions in the pre-PR implement loop. The post-PR loop is counted separately and is not included.
- Output tokens: the overlord produced 13.9M. All subagents together produced 12.5M.
- The overlord loads about 160 KB of prompt every turn: `overlord.md` is 54 KB, plus about 110 KB of governance docs.

| Main-thread tool calls | Count | Share |
|---|---|---|
| ledger | 4,699 | 52.1% |
| delegation | 1,269 | 14.1% |
| pr-watch/gh | 902 | 10.0% |
| other Bash | 894 | 9.9% |
| git | 808 | 9.0% |
| skill | 356 | 3.9% |
| Read | 37 | 0.4% |
| other Write | 22 | 0.2% |
| other tools | 28 | 0.3% |
| **Total** | **9,015** | |

| Output tokens | Tokens |
|---|---|
| Main thread (overlord) | 13,923,525 |
| drone | 6,023,545 |
| cerebrate | 3,066,994 |
| local-reviewer | 1,946,634 |
| github-reviewer | 974,928 |
| changeling | 465,093 |
| **All subagents** | **12,477,194** |

### 2. The user acts as a rubber stamp

- About 37% of prompts are pure approval or continuation (the original report's figure). The counts behind it: "Take recs" 53 times, "Go"/"Yes" 48, an option pick 28, "Merged" 46. These four total 175 of 483 prompts.
- The Tier-B auto-decide rule was not reducing how often the user got asked.
- **Root cause (found by the planning agent at the start of the PR #408 run, not in the original report):** a cerebrate `open_questions` result maps to the `blocked` terminal in `standard-delivery`, `pr-feedback-remediation` and `analysis-only`. So every planner question ended the run, and the user replied "Take recs".

### 3. When the user is asked, the decision is presented badly

- 21 complaints about framing, such as "Layman's terms", "wall of text" and "never tell me why".
- 8 requests to steel-man and straw-man the options. 8 requests to get a second opinion from another model (fable), done by hand.
- What the user asked for, every time: what the problem is, how critical it is, the viable options (tested), the recommendation, and why.

### 4. Review remediation drags on

- Local review outcomes: planner escalation 170, root cluster suspected 136, high-severity rejection 48.
- Run endings: 53 runs ended `review_rejected` and 17 ended `review_exhausted`.
- 14 prompts asked "diminishing returns?" or said "extreme edge case", "what are we nitpicking" or "this is going on forever". The system never weighed value against effort on its own.
- `standard-delivery` takes a median of 84 minutes and a p90 of 9 hours.

| Local review passes per run | Runs |
|---|---|
| 0 | 333 |
| 1 | 190 |
| 2 | 81 |
| 3 | 36 |
| 4 | 12 |
| 5 or more | 9 |

### 5. Handoff chains do the job of persistent settings

- 51 prompts asked for a handoff. 27 new sessions started with `.hivemind/handoffs/<name> go`.
- Each handoff repeated the same facts: TDD, local review required, watch the PR. One handoff picked up a made-up rule ("don't open PR unless asked").
- Brood was used only 19 times. The real execution mode was one issue per session, run in sequence.

### 6. Recurring behaviour faults

- **Stalls:** 16 prompts like "why did you stop", "??" or "what's going on".
- **PR watch:** the user still asked why the PR was not being monitored on 2026-10-12, and one approval was missed.
- **Too many issues:** complaints that more issues were created than fixed, even after the issue-creation rules from #360.
- **Invented constraints:** a public-API rule and "can't edit other packages", neither set by the user.
- **Local review skipped,** even though it is meant to be required.

### 7. Prototype and design work does not fit `standard-delivery`

Five GitHub Pages sessions all followed the same ad-hoc loop: make N variants, view them on mobile, pick one, merge them, ship. None of it uses the state machine's strengths.

### 8. The ledger works, but has friction

- 79% of runs completed (523 of 661). 118 ended blocked and 20 were cancelled.
- 37 runs fell into intent fallback, mostly from workflow version mismatches and stale runs. In this repo the workflow definitions change often, so a version change mid-run keeps breaking runs.

| Workflow | Runs | Median minutes | p90 minutes |
|---|---|---|---|
| standard-delivery | 443 | 84 | 541 |
| pr-feedback-remediation | 174 | 21 | 171 |
| analysis-only | 22 | 7 | 25 |
| hatchery-dispatch | 19 | 11 | 26 |
| exploratory-intent-session | 3 | 158 | 659 |

### Supporting figures

- Main-thread tool calls by name: Bash 4,703, Write 2,489, Agent 1,269, Skill 356, Monitor 125, Read 37, TaskStop 19, SendMessage 5, AskUserQuestion 2, ToolSearch 1, SendFeedback 1. These sum to 9,007, which is 8 below the 9,015 total. Skill and Read come from the later pass that produced the category table above. Bash, Write and Monitor come from an earlier pass over the same logs, which were still growing, and the by-name split was not re-run. The 8-call gap therefore sits in those three tools.
- Total recorded cost across the 49 sessions: about $4.2k.
- `standard-delivery.json` has 33 states.
- Tool errors were minor. The largest groups were calls to tools not available in the session (Grep 27, TaskStop 17, the claude-mem search tool 15).

## Claude dynamic Workflows vs the static workflow engine

The original question was whether Claude's dynamic Workflow tool makes the static workflow JSON a relic. The report's answer: both have a place, split by layer.

**How the two differ.** The Workflow tool runs control flow (loops, fan-out, retries, resume from a cache) as code in the harness. The model only does judgment inside each `agent()` call. Those calls can use `agentType: 'hivemind:drone'`, so the existing agents carry over. HIVEMIND today runs deterministic control flow through the model: the overlord reads the JSON, calls Bash for each transition, and writes an input file each time. That executor is the relic. It accounts for the 52% overhead in finding 1.

**What still earns its place as static:**

- **The invariants:** git preflight, never committing to trunk, validating before the PR, required review gates, the destructive-fix gate, and the external-content boundary.
- **The outer lifecycle:** branch, then PR, then watch, then merge advisory.
- **An audit and resume record.** This could be the workflow's own `journal.jsonl` instead of `state.json`.

**Where dynamic workflows clearly win:**

- **Planning:** a judge panel (for example cerebrate against fable), scored and synthesized. This replaces the manual "have fable give a rec".
- **Implementation:** run waves as a pipeline, with worktree isolation in place of the file-disjointness rules.
- **Review:** find, then adversarially verify, then score value (severity × likelihood × blast radius), and only then fix. This targets the nitpick loops directly.
- **Prototypes:** N different variants, an artifact for each so they can be viewed on mobile, then the user picks.
- **Backlog sweeps and triage:** one pipeline stage per issue.

**Recommendation: a hybrid.** Keep the static policy and invariants as data. Replace the executor with a dynamic one. Either one generic Workflow script interprets each JSON definition, or each definition compiles to its own script.

**Open questions the report listed:**

- Whether the overlord agent can use the Workflow tool. It was not in the session's tool list, and the tool needs an opt-in.
- How a `user_gate` maps onto a workflow. Probably: the workflow returns, the main loop asks the user, then it resumes with `resumeFromRunId`.
- Whether a PR watch lasting hours belongs inside a workflow, or should stay as Monitor in the main loop or a scheduled routine.

**Ideas the report proposed:**

1. Keep the JSON as policy and change the engine, so the per-transition Bash ceremony goes away.
2. A fixed decision-brief format for every surfaced choice: the problem in plain terms, how critical it is, steel-manned options, effort against value, the recommendation and why.
3. An autonomy setting that defaults to taking recommendations (`HIVEMIND_AUTONOMY=high`). Only merges, destructive actions and genuinely architectural calls would surface.
4. A standing session profile (TDD, local review, watch cycles), so handoffs carry only task context.
5. A campaign mode: an ordered issue queue processed one fresh context per issue, replacing the manual handoff, `/clear`, "go" cycle.
6. A review value gate: score findings before remediating, and raise "diminishing returns" proactively.
7. Slim the overlord prompt once the engine stops needing all that procedural prose.

The user chose ideas 2 and 3 first. The reasoning given: both are engine-agnostic if built as data files (a JSON schema and a data table), so a later engine change reuses them. Only the enforcement wiring in prose would be redone. Putting the brief format or autonomy rules inline in `overlord.md` would cause real rework.

## PR #408 retrospective

PR #408 implemented ideas 2 and 3.

**What worked:**

- The decision-autonomy table and the decision-brief schema as data. They are engine-agnostic and reusable as-is.
- The goal itself: fewer approval prompts.
- Plain-language decision briefs.
- The one-home rule for rules: each rule exists once, and everything else points to it.

**What failed:**

- **A state machine written in prose.** The resolution order, the fallback re-delegation, the plan-slot routing and the brief-to-journal mapping were all prose rules. That is the exact thing the deterministic ledger exists to avoid. Prose has no compiler, so every review could find another edge case.
- **The PR kept growing.** It reached about 1,700 lines over 7 Codex review rounds, with new P1 findings each round.
- **Findings were fixed one at a time, not by class.**
- **Rules were restated in several files and drifted apart.**
- **Zoom-out warnings were noted but not acted on.**
- **A watch gap after a one-shot fix pass** let a P1 sit for hours.
- **The orchestrator started work the user had not asked for.**

**Outcome:** PR #408 stays open as a reference. It is not merged. Future work starts fresh from `main`.

## Speed insight: invert control

**What is slow.** The ledger idea is not the slow part. The slow part is the model driving deterministic transitions one tool call at a time. Each transition means writing an inputs file, running the engine script and reading the result. Each of those is a full model turn with a large prompt. Adding more engine calls per decision (for example a `resolve-decision` script) makes it slower.

**The fix: code drives the loop, and the model is called only for judgment.** This fixes speed and determinism together.

- **Transitions:** a Workflow script runs the state machine from the workflow JSON. A transition costs no model turns.
- **Judgment work:** planning, implementing and reviewing are `agent()` calls with a `schema`. Cerebrate's output is validated against the brief schema by the tool, not by prose rules.
- **Decisions:** resolution is a pure function over the autonomy table.
- **Parallel work:** waves are `parallel()`. Brood is `parallel()` with worktree isolation.
- **Prose:** agent prompts state intent only.

**Open constraints:**

- Workflow scripts have no filesystem access. The ledger becomes the workflow's own journal, or it is written by an agent.
- Pausing for the user means the script returns, then resumes.
- The PR watch needs Monitor, so it stays in the main session.

## Pointers

- [Issue #409](https://github.com/brenpike/hivemind/issues/409): workflow engine overhaul.
- [Issue #410](https://github.com/brenpike/hivemind/issues/410): AGENTS.md consolidation, including the sweep of pre-existing rule restatements.
- [PR #408](https://github.com/brenpike/hivemind/pull/408): autonomy levels and decision briefs, kept open as a reference.
- [ADR-0034](https://github.com/brenpike/hivemind/blob/feature/autonomy-knob-decision-briefs/docs/adr/0034-autonomy-levels-and-decision-briefs.md): the decisions behind PR #408. It lives on the PR #408 branch, not on `main`.
