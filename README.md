# Hivemind

Multi-agent orchestration framework for Claude Code. Coordinates specialized bioforms to plan, build, review, and ship code, so you don't have to manage the pipeline yourself.

You are the **Overmind**. You state the intent; the swarm acts on it.

## Install

Inside Claude Code, add the marketplace then install the plugin:

```text
/plugin marketplace add https://github.com/brenpike/hivemind.git
/plugin install hivemind@brenpike
```

Then run `/hivemind:seed-hive` once in each project (see [Per-project setup](#per-project-setup)).

## Requirements

- **bash** (macOS, Linux, or WSL on Windows)
- **git** and **gh** (GitHub CLI)
- **jq**: required by the run-ledger engines (`hivemind:init-run-ledger`, `hivemind:record-state-result`), by the facts and git scripts (`hivemind:gather-facts`, `hivemind:molt`, `hivemind:open-plan-pr`), and by `hivemind:seed-hive`
- Claude Code CLI. When Claude Code's Workflow tool is available, analysis requests run as a workflow script, delivery requests run as one or on Instinct, and an escalated PR review runs as one. Otherwise analysis requests run on the workflow state machine, and Instinct is the `standard-delivery` fallback (see [Two engines](#two-engines)).
- **tmux**: only for brood execution (`hivemind:spawn-brood`, `hivemind:brood-status`)
- **node**: only for the optional local Codex review (`codex` companion)

PowerShell and native Windows are not supported. All toolchain scripts are bash-based.

## Per-project setup

1. Enable the plugin and set the overlord as the session default agent in `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "hivemind@brenpike": true
  },
  "agent": "hivemind:overlord"
}
```

The `agent` key sets the default agent for the project session. Without it, Claude Code starts with the default agent and the overlord is only reachable on-demand via the Agent tool, which bypasses the workflow guarantees.

Or run the setup skill once to apply the required keys automatically:

```text
/hivemind:seed-hive
```

`seed-hive` never overwrites a different existing `agent` value; it stops and asks you first. It also:

- Adds `.hivemind/` and `.claude/worktrees/` to your project's `.gitignore`.
- Detects which companion plugins are installed (caveman, claude-mem, codex) and asks you **one consolidated confirmation** covering all of them, recommending `yes` for each one it detects. Pass an explicit `=yes` or `=no` argument to skip the prompt for that companion (e.g. `caveman=no`, `claude_mem=yes`). In headless mode (no user turn available) it auto-enables detected companions and skips absent ones instead of waiting on the prompt.
- Merges the least-privilege permission allowlist (`seed_allowlist` defaults to `yes`; see below).
- Invokes `hivemind:creep-spread` to generate or enrich the project's `CONTEXT.md` domain glossary.
- Detects the project's test command and records it under `## Validation` in the repo-root `CLAUDE.md` when that section has no command yet (append-if-absent; it never runs the command).

`.hivemind/` is runtime state created by the overlord and its skills. It should not be committed. It holds:

- `.hivemind/runs/<run-id>/state.json`: the run ledger, one per state-machine run. Workflow-script runs keep no run ledger.
- `.hivemind/facts/`: the branch facts files `hivemind:gather-facts` writes, one per facts run
- `.hivemind/broods/<brood-id>/manifest.json`: one manifest per brood
- `.hivemind/review-loop/fix-ledger.yaml`: the local reviewer's finding ledger
- `.hivemind/handoffs/` (and `.hivemind/plans/`): session-resumption handoffs and the plans they point at
- short-lived inputs files that skills pass to their engine scripts, e.g. `.hivemind/seed-inputs-<token>.json`, `.hivemind/runs/.init-inputs-<token>.json`, and the molt and PR inputs files `.hivemind/molt-inputs-<token>.json` (the commit message and its file list) and `.hivemind/pr-inputs-<token>.json` (the PR title, draft flag and reuse comment) with its body file `.hivemind/pr-inputs-<token>-body.json` (the raw PR body)

If you prefer manual setup, add `.hivemind/` and `.claude/worktrees/` to your project's `.gitignore` directly.

**Least-privilege permission allowlist.** By default, `seed-hive` merges a recommended set of `permissions.allow` entries into `.claude/settings.json`. Pass `seed_allowlist=no` to skip this step:

```text
/hivemind:seed-hive seed_allowlist=no
```

The seeded entries cover read/output helper Bash commands (`echo`, `printf`, `cat`, `grep`, `jq`, `head`, `tail`, `ls`, `wc`, `sort`, `uniq`) and scoped git read subcommands (`git ls-files`, `git ls-tree`, and `git grep` are read-only listers/searchers; `git stash list` and `git stash show *` are read-only stash inspection; `git tag` is list-only). The `Skill(hivemind:route-workflow)` entry stops the permission prompt on the read-only routing call the overlord makes for each request. Next to it sit the inputs-file rules, each an `Edit(.hivemind/...)` entry for one fixed path a skill writes with the Write tool for its engine script: `Edit(.hivemind/review-loop/*)`, `Edit(.hivemind/runs/.init-inputs-*.json)`, `Edit(.hivemind/runs/.record-inputs-*.json)`, `Edit(.hivemind/runs/.markfb-inputs-*.json)`, `Edit(.hivemind/spawn-inputs.*.json)`, `Edit(.hivemind/seed-inputs-*.json)`, `Edit(.hivemind/molt-inputs-*.json)` and `Edit(.hivemind/pr-inputs-*.json)`. Each one only stops the Write prompt for its path. No `Workflow(...)` rule is seeded: the workflow approval prompt's don't-ask-again choice is the per-project opt-in. The entries are appended-if-absent: existing entries are never overwritten or removed. `echo`/`printf`/`cat`/`sort` **are** included: Claude Code re-prompts (ask/deny) on any command that writes or redirects to a path outside the session working directory (only `> /dev/null` is exempt) and splits compound commands (`&&`/`||`/`;`/`|`/newline), requiring each subcommand to match a rule independently, so granting them does not create an arbitrary-file-write vector (`echo evil > /etc/passwd`, `printf x > ~/.bashrc`, `cmd && rm -rf y` all re-prompt). The only silent write any of these helpers permits is bounded to the working directory, identical to `grep`/`jq`/`head`/`tail`/`ls`/`wc`/`uniq`. `node`, and `Edit` or `Write` on any path outside those inputs files, are not auto-approved; those require explicit per-project decisions.

**Skill tool grants.** A skill's `allowed-tools` entries pre-approve tools while the skill runs, for the rest of that turn and for workflow agents started in it. So a skill's file-tool grants cover only the paths it serves: the Write of its own inputs file, through an `Edit(...)` entry for that path (for example `Edit(.hivemind/molt-inputs-*.json)` in `hivemind:molt`), and Reads of the plugin's own files under `~/.claude/plugins/cache/brenpike/hivemind/`, through `Read(~/.claude/plugins/cache/brenpike/hivemind/**)`. That Read rule also covers Grep searches of those files. The Claude Code permissions docs say so, and a headless test on Claude Code 2.1.310 confirmed it for a plugin installed in that cache (ADR-0010, amendment 2026-10-23). Apart from the six user-invoked executor skills, no skill pre-approves a Read or Write of any other path. Those six (`hivemind:tdd`, `hivemind:refactor-to-depth`, `hivemind:plan-to-prd`, `hivemind:plan-interrogation`, `hivemind:create-handoff` and `hivemind:creep-spread`) still carry broad `Read`, `Write` and `Edit`. If the plugin loads from a local path (`--plugin-dir`, or a marketplace added from a local folder), its files are not under that cache path, so Reads of them outside the project prompt. To pre-approve those Reads, add `Read(//<absolute plugin folder>/**)` to the project's gitignored `.claude/settings.local.json`. The seeded rules above are unchanged.

**After upgrading the plugin, re-run `/hivemind:seed-hive`.** A newer version may recommend `permissions.allow` entries your project does not have yet, and those entries are merged only when `seed-hive` runs, never automatically on upgrade. Skipping the re-run does not take away any capability (tool grants ship inside the plugin itself and load at session start); it only leaves those newer allow rules unmerged in your `.claude/settings.json`. Re-running is always safe: the merge is idempotent and your existing entries are preserved.

The supported setup for local Codex review (`hivemind:adaptation-cycle`) is a per-contributor grant: add your Codex cache path to the gitignored `.claude/settings.local.json`, never the tracked `.claude/settings.json`, because this entry hard-codes one machine's absolute `$HOME` path and the tracked file is shared across a team and across machines:

```json
"Bash(node /path/to/.claude/plugins/cache/openai-codex/codex/*)"
```

Replace `/path/to/` with your actual home directory path. The `codex/*` wildcard covers all Codex CLI entry points so the entry does not need updating when Codex is upgraded. `seed-hive`'s allowlist template deliberately seeds no provider grant at all, because a machine-specific path cannot be templated into a committed file without becoming a permanently dead rule.

**Upgrading an already-seeded project.** A project seeded by an earlier plugin version may still carry a literal `Bash(node /path/to/.claude/plugins/cache/openai-codex/codex/*)` line in its committed `.claude/settings.json`. The `/path/to/` placeholder was never expanded there, so the rule matches nothing, so delete it by hand. Re-running `/hivemind:seed-hive` will not re-add it; the merge is union append-if-absent and never removes, so the fix stops new and repeat seeds but does not clean up an existing file.

2. Create or extend `CLAUDE.md` with project-specific details:
   - Build/test commands (the `## Validation` section is what the overlord runs at the `validate` state)
   - Package names and version file paths
   - Versioning configuration (bump triggers, changelogs, tag prefixes)
   - Architecture and code style notes

3. Create `AGENTS.md` at the project root with project-specific Codex review guidance. Include:
   - Review focus areas
   - Severity definitions
   - Project-specific conventions for reviewers

Once configured, the overlord is the session default agent. All skills are available namespaced as `hivemind:<skill-name>`.

## Configuration

Three optional operator overrides are read from the `env` block of `.claude/settings.json` (committed, inherited by brood worktrees because the file lives in the repository) or `.claude/settings.local.json` (gitignored, per-account). Leaving any of them unset changes nothing.

```json
{
  "env": {
    "HIVEMIND_LOCAL_REVIEW_MODEL": "gpt-5.3-codex",
    "HIVEMIND_SKIP_PR_WATCH": "1",
    "HIVEMIND_ENABLE_DECISION_REPORT": "1"
  }
}
```

| Key | Effect | Reference |
|---|---|---|
| `HIVEMIND_LOCAL_REVIEW_MODEL` | Model for the local pre-PR Codex review. Empty or unset means Codex uses its own default. The value must match `^[a-zA-Z0-9/_.\-]+$` (e.g. `gpt-5.3-codex`, `gpt-5.5`); anything else blocks the review before Codex is invoked. Whether a given model is available depends on your Codex account. | `docs/adr/0022-local-review-parity-with-post-pr-review.md` |
| `HIVEMIND_SKIP_PR_WATCH` | Checked by presence (any non-empty value): the overlord never watches a PR after opening it, and does not read your request for a watch opt-out. Unset or empty means the default watch applies. | `docs/adr/0029-default-pr-watch-and-idle-window-lifecycle.md` |
| `HIVEMIND_ENABLE_DECISION_REPORT` | Covers state-machine runs only: workflow-script runs keep no run ledger, so the report does not see them, and a script run instead lists decisions it took, for veto before merge, in its final message and on the PR, and Decisions on the PR under The Lifecycle says which. Opt-in, checked by presence (any non-empty value). When set, after a run's PR merges or closes the overlord shows you a report of the decisions it made on your behalf (`hivemind:decision-report`, chat only). The decision journal in the run ledger is written either way. When unset or empty, no report is rendered and no GitHub call is made, but runs that would have reported still get a zero-byte `.decision-report-done` marker, so enabling the key later only reports runs that finish after you enable it. | `docs/adr/0030-config-gated-post-merge-decision-report.md` |

To keep a workflow off its workflow script, add a `Workflow(hivemind:analysis-only)`, `Workflow(hivemind:standard-delivery)` or `Workflow(hivemind:pr-feedback-remediation)` entry to `permissions.deny` in `.claude/settings.json` or `.claude/settings.local.json`. The launch is then refused with no prompt and falls back: `analysis-only` and `pr-feedback-remediation` to the state machine, and `standard-delivery` to Instinct (see [Two engines](#two-engines)).

## Recommended companion plugins

- [`claude-mem`](https://github.com/thedotmack/claude-mem): provides optional cross-session memory and continuity. Install separately as a Claude Code plugin. Hivemind works without it. When it is present, the cerebrate reads claude-mem memory directly via the MCP search tools (`mcp__plugin_claude-mem_mcp-search__*`) while planning. It skips memory cleanly when the session facts say `claude-mem: absent`, or when a memory tool call returns `No such tool available`; when the overlord forwards a `Memory context:` block in the delegation, the cerebrate uses that and does not search again. Writes happen through claude-mem's automatic capture (there is no write MCP tool). `uvx` (from [Astral's `uv`](https://astral.sh/uv)) is an optional dependency of claude-mem that enables its semantic (vector/Chroma) search backend; without it, claude-mem falls back to keyword search and MCP tools remain fully callable. Install with `curl -LsSf https://astral.sh/uv/install.sh | sh`; diagnostics at `~/.claude-mem/logs/` (look for `CHROMA_MCP` entries).

- [`codex`](https://github.com/openai/codex-plugin-cc): provides local Codex code review. Install and configure with:
  ```text
  /plugin marketplace add https://github.com/openai/codex-plugin-cc.git
  /plugin install codex@openai-codex
  /reload-plugins
  /codex:setup
  ```
  Once it is installed and enabled for the project (`seed-hive` enables it when you confirm it), it adds only the local pre-PR review: the `local-reviewer` agent, backed by `hivemind:adaptation-cycle`. If it is not installed or not enabled, the overlord skips local review and goes straight to the PR. The post-PR watch (`hivemind:github-review-loop` plus the `github-reviewer` agent) does not need it; it works from GitHub review feedback.

- [`caveman`](https://github.com/juliusbrussee/caveman) (`caveman@caveman`): token-compressed communication. Optional. When enabled through `seed-hive`, framework agents output in caveman ultra mode. `seed-hive` detects it and includes it in its companion confirmation, or add manually to `.claude/settings.json`:
  ```json
  "enabledPlugins": { "caveman@caveman": true },
  "pluginConfigs": { "caveman@caveman": { "options": { "defaultLevel": "ultra" } } }
  ```

## Dev container

This repo ships a `.devcontainer/` that provisions the validation toolchain so contributors can run the validation suite locally (in GitHub Codespaces or in VS Code Dev Containers, via Dev Containers: Reopen in Container) and dogfood the plugin. The base image is Ubuntu (Debian/Ubuntu family is mandatory: the policy linter uses GNU `grep -P` and `perl`, which Alpine/BusyBox lack).

**Auto-provisioned** by `.devcontainer/postCreate.sh`:

- Validation toolchain: `jq` and `perl` are explicitly installed via apt before any gate runs (idempotent: skipped if already present); `gh`, Node 20, `python3`, GNU `grep`, and `git` are verified at startup and the script hard-fails if any are missing.
- CLI tools via npm global: Claude Code CLI (`@anthropic-ai/claude-code`), Codex CLI (`@openai/codex`), `claude-mem`.
- `uv` / `uvx` (Astral) via the official install script: claude-mem's optional vector-search backend.
- `tmux` via apt: terminal multiplexer used by the `hivemind:spawn-brood` / `hivemind:brood-status` skills.
- `bun` via the official installer (`bun.sh/install`): fast JS runtime required by `claude-mem`.
- A **smoke test** of three gates: the `python3` JSON-manifest parse, `tools/policy_check.sh --strict`, and `tools/validate_reports.sh --batch tests/reports/`. It also trips on CRLF line endings, which have corrupted these linters before.

The smoke test is a subset of CI, not a copy of it. CI (`.github/workflows/policy-check.yml`) runs `bash tools/validate.sh --changed --base origin/main` on pull requests and `bash tools/validate.sh --all` on pushes to `main`. For the closest local match to CI, run:

```bash
bash tools/validate.sh --all
```

Even that is best-effort rather than a guarantee: CI runs on `ubuntu-latest` while this container pins `ubuntu-20.04`, so coreutils/grep/perl/python versions can differ.

**Stays manual**: installing the Claude Code *plugins* requires an authenticated `claude` CLI, which a fresh container does not have. `postCreate.sh` registers the marketplaces (no auth needed) and prints the exact install commands to run once you have signed in:

```text
claude plugin install hivemind@brenpike
claude plugin install codex@openai-codex
claude plugin install claude-mem@thedotmack
claude plugin install caveman@caveman
/codex:setup
```

**Caveman marketplace is registered automatically.** `postCreate.sh` registers the caveman marketplace (no auth required). Caveman *enablement* (`enabledPlugins`, `pluginConfigs`, SubagentStart hook, `.envrc`) is handled by `hivemind:seed-hive caveman=yes` (the canonical path for all plugin config) rather than being hand-seeded by postCreate.

The optional npm installs are wrapped so a single failure (for example in an offline/locked-down Codespace) prints a warning but does not abort; only the smoke-test gates are must-pass. The script is idempotent: re-running `bash .devcontainer/postCreate.sh` is safe.

The Codex cache permission grant (container `$HOME` node path) is seeded into the **gitignored** `.claude/settings.local.json` (never the tracked `.claude/settings.json`), using a jq-merge that does not clobber existing entries.

See `.devcontainer/README.md` for full launch instructions (Codespaces and local Dev Containers), the complete list of what is auto-provisioned, and troubleshooting.

## After cloning a project that uses this plugin

```text
/plugin marketplace add https://github.com/brenpike/hivemind.git
/plugin install hivemind@brenpike
```

## The Swarm

Hivemind coordinates specialized bioforms to plan, build, review, and ship code, so you don't have to manage the pipeline yourself. You are the Overmind; the swarm acts on your intent.

### Know Your Bioforms

| Bioform | Role | What it does |
|---|---|---|
| :eye: **Overlord** | Orchestrator | The control plane and your main interface. Routes each request to a workflow, then launches its workflow script, runs a `standard-delivery` request on Instinct, or runs the workflow state machine and its run ledger. Owns branches, checkpoint commits, version-bump decisions, PRs, and review routing. Delegates all implementation; never writes code. |
| :brain: **Cerebrate** | Strategist | Researches the codebase and returns the **directive**: `STEP-NNN` steps with exact file scopes, dependencies, risks, and a delivery shape (single, multi, or brood). Has no shell: its tools are Read, Glob, Grep, LSP, the web tools, and the claude-mem search tools. Takes branch state only from the facts file. Never writes files. |
| :hammer: **Drone** | Builder | Implements code, fixes bugs, refactors, and updates tests and release metadata within an explicitly assigned file scope. The default owner of every step. |
| :performing_arts: **Changeling** | Shaper | Presentational UI/UX: markup, styling, layout, design tokens, visual states, presentational accessibility, within its assigned file scope. |

Two more agents handle review. They are composites rather than bioforms: each one classifies findings, fixes the simple ones itself, and hands everything else back to the overlord.

- **Local-Reviewer** (pre-PR): runs an adversarial Codex review loop before the PR exists (needs the `codex` companion).
- **GitHub-Reviewer** (post-PR): a stateless, one-shot worker that fetches and classifies GitHub review feedback, fixes, pushes, replies, and resolves threads. `hivemind:github-review-loop` dispatches it.

One more agent, the **Synapse**, runs the committed runner scripts for the workflow scripts: the facts, commit, push and pull request steps. Only workflow scripts start it. The overlord never delegates to it.

### Two engines

`hivemind:route-workflow` selects the workflow first, for every request that is not a Reflex. One of two engines, or Instinct, then runs it:

- **Workflow scripts.** `analysis-only`, `standard-delivery` and `pr-feedback-remediation` launch as the `hivemind:analysis-only`, `hivemind:standard-delivery` and `hivemind:pr-feedback-remediation` Workflow scripts when Claude Code's Workflow tool is available. `analysis-only` has been a script since 6.0.0, `standard-delivery` since 7.0.0, and `pr-feedback-remediation` since 8.0.0.
- **The workflow state machine.** Every other workflow (`hatchery-dispatch`, `exploratory-intent-session`) runs on its JSON state machine, and so does an `analysis-only` or `pr-feedback-remediation` request whose launch is refused.
- **Instinct.** A `standard-delivery` request can also run on Instinct, a delivery path the overlord drives by judgment, with no workflow script and no run ledger. It keeps the plan, the working branch and every delivery gate. When a delivery request names neither the engine nor Instinct, the overlord asks you which to use; a brood child, whose task carries a `working_branch.base` ref, takes the engine. Instinct is also the engine's fallback for `standard-delivery` (ADR-0039).

Launching a script:

- In manual mode, the Workflow tool's approval prompt is the opt-in. A No at the prompt interrupts the turn: nothing runs and nothing falls back.
- A `Workflow(hivemind:<id>)` entry in `permissions.deny` refuses the launch with no prompt. For `standard-delivery`, Instinct is the fallback for a refused launch and for a started run that fails; any other refused launch runs on the state machine. The fallback rules are in `plugin/agents/overlord.md` (`## Engine`) and `docs/adr/0039-instinct-delivery-path.md`.
- In auto mode, the classifier decides the launch and no approval prompt is shown.
- Brood children launch the scripts like any session. They start in auto mode, so no approval prompt is shown, and a refused launch falls back as it does in any session.

How a script run behaves:

- **No run ledger.** The working branch, its commits and the PR are the record. A paused run resumes in the same session. A new session plans what is left: the planner reads the branch's history from the facts file and the files as they are now.
- **Questions.** Routine planner questions are decided by the autonomy table (`plugin/references/decision-autonomy-table.json`). Only a call in the closed Ask Set, defined in `plugin/governance/decision-autonomy.md` (Decision Tiers, Review Calls), pauses the run with a decision brief, such as an irreversible call, an architectural call, a hard stop or a call with no recommendation. The run takes any other call with its recommendation, and Decisions on the PR below says which taken calls are listed. A stale trunk follows the table too. A remediation plan is decided for you unless accepting it trips the promotion gate or the plan grows the surface. Questions show short fields the agents write for you, such as what a plan addresses, what it changes and what it touches, never pasted agent text. A question that asks you pauses a delivery run, and your reply resumes the same run, with no pause limit: the agents that already finished replay from cache. A delivery run ends blocked, lists its open questions and names the next action only when the replies are too long to carry, or the exact text of a question is too long to show, so a completed delivery run always has a PR. An analysis-only run pauses at most 3 times, then completes and lists the questions still open.
- **Stops pause.** Only a stop with a cause you can clear, or an approval to give, asks you, and your reply takes that step again. A step whose own output failed, such as a report it could not use, a block with no reason, or an agent call with no result, ends the run blocked with its cause and next action instead of asking you to retry. A blocked runner whose failure is transient, such as a network error or an HTTP 5xx, still runs once more first. After any reply, the run reads the branch head again before a gate holds or the pull request is pushed, so a commit you made while the run waited is seen. A stop before or during the waves, or a local review that ends without converging, plans again from fresh facts instead. The run also ends on a stop no reply can clear: a prompt injection suspect, a git script refusal, a branch or pushed commit other than the planned one, a PR text over its size limit, a settled question that comes back, an agent call that returned no result, replies too long to carry, or a failed launch check.
- **Runner steps.** The facts, commit, push and pull request steps run on `hivemind:synapse`, a haiku agent that runs one committed script and relays its output. A plugin `PreToolUse` hook (`plugin/hooks/`) allows synapse the five exact runner commands with no prompt, including the push and the PR. Any command that names one of those five scripts in another form is denied for every agent. To read those files, use Read.
- **Stopping a run.** You can stop a launched run from any surface, Remote Control included, by asking the overlord. The stopped run keeps every completed agent result, and when you ask the overlord to go on, later in the same session, it resumes the run from there.
- **Effects outside the repo.** A plan step that declares an irreversible effect outside the repo, such as a deploy, a publish, a migration or a write to an outside service, asks you before the first wave.
- **Request options.** A delivery request can ask for a draft PR, or to skip local review. Local review is also skipped when the Codex plugin is not available in the session.

### The Lifecycle

A `standard-delivery` script run, from request to PR:

1. **Facts.** A runner gathers the branch facts into one facts file (`hivemind:gather-facts`).
2. **Scan.** A runner scans the text of the issues and PRs the request names for prompt injection (`hivemind:injection-scan`).
3. **Scope.** The cerebrate, on Sonnet, returns the line each section of the documents the request names starts on, and checks each path a section names. The planner reads the whole section at each of those lines, taking where it starts and ends from the file, and checks no named path again. A scope result that fails its check goes back to the cerebrate with the exact problem, at most 2 retries; one that still fails ends the run before planning.
4. **Plan.** The cerebrate plans what is left of the request on this branch, and the plan is checked against `plugin/references/plan-schema.json`. A plan or revised plan that fails its check goes back to the cerebrate the same way, with no stop for you: at most 2 retries, and one that still fails ends the run. A title that starts with the plan's own commit type is cleaned in code. A run started on a branch outside the branch taxonomy stops before planning. A planner question whose recommendation goes beyond the request without being strong at trivial or small effort, or whose brief is malformed, goes back to the planner. After a pause, the planner revises the plan with your reply.
5. **Branch.** A runner creates or confirms the working branch (`hivemind:create-working-branch`).
6. **Waves.** The script computes each ready wave of plan steps in `plugin/workflow-src/lib/waves.js`. Workers run each wave in parallel, and a runner commits the wave's files after each wave (`hivemind:molt`).
7. **Validate.** A drone runs each validation command the plan names, once. When the plan names none, it runs the gate command the project's `CLAUDE.md` names, once, so validation is never skipped. A test case that hits its own time limit in a file the branch does not change runs once more alone; if it passes there, validation passes and the PR lists the case as slow. When the plan names version files, the same drone also runs the version check (`hivemind:bump-type --version-file`), read-only: each version file must hold its trunk version raised by the bump the branch's commits call for. A plan step sets that version, beside the change log, so a version already at its target passes. A mismatch gets a fix round with no question. A version the check cannot derive or read asks you, and your reply runs one fix round and never plans again. Validation edits nothing and makes no commit: a path it leaves dirty stops the next commit or the PR step. A failure gets a bounded number of fix rounds, one at a time, each one committed; a failure is kept for its commit, so a round that commits nothing does not validate the same commit again. After the last round the run asks you.
8. **Review.** The local reviewer reviews the branch and commits its simple fixes, when local review is on. A fix that fails its check is undone, with only its own files going back to the last commit, and the run lists it. When an outside service is down and says when it is back, such as a Codex usage limit with a retry time, the run waits it out, bounded, and asks nothing.
9. **PR.** A runner pushes the commit every gate held on and opens its pull request, or reuses the open one (`hivemind:open-plan-pr`). At a loop cap (the local review iteration limit, a break-fix-break cycle, the replan cap, the gate rerun cap or the wait cap) validation passes first, then the run opens a draft PR that says why and lists the open findings.

**Gates hold on one commit.** Validation, with its version check, and local review are gates. Each gate holds only for the commit it ended on, and the PR step pushes only a commit every configured gate held on. So a later commit, such as a validation fix round or a local-review fix, reruns the gates it invalidates: every gate that ended on an earlier commit. Validation, which makes no commit, ends on the commit it ran on. The reruns are bounded; at the bound the run opens a draft PR and no longer asks. A gate not configured for the run, such as local review without the Codex plugin, is listed on the PR.

**Decisions on the PR.** A new PR's body is built in code for a reviewer who never saw the chat. It holds the closing lines, the plan digest (the problem, then the change), and the steps with their files and outcomes, then the run record: the reversible effects; the gates; the slow test cases; for a draft PR, why it is a draft and the findings local review left open; the short ids of the findings any local review of the run rejected or whose fix it undid; the destructive changes you approved; and one line per decision under "Decided for you". External text in it is neutralized, so it mentions no one and closes or links no issue. When the run reuses an open PR, the same run record goes in a PR comment. The final message lists the same decisions as the run record, so you can veto them before you merge. Three kinds of decision are not listed: accepting the plan, accepting a remediation plan, and rerunning a gate after a later commit. A plan or remediation plan acceptance is listed anyway when the plan changes a file outside your stated limits or repeats a surface whose earlier fix left its class open. A gate rerun is never listed. A script run keeps no decision journal, so the final message and the run record on the PR are its only record of decisions. A local review call is taken when `plugin/governance/decision-autonomy.md` (Review Calls) lets the run take it, and asked otherwise; a taken call is recorded at its source, naming the run as the one who decided, and listed, so you can veto it before you merge. A review question in the Ask Set, and any other Ask Set question that comes up after the last wave, pauses the run with the question open and nothing pushed. Your answer to a local review question goes back to the local reviewer, which reviews the same commit again with your answer: a finding you reject is recorded at its source and committed, and the review goes on. Your answer to a version question runs one fix round, and your reply to a stop with a cause you can clear, or an approval to give, takes that step again. Any other answer starts a new planning pass with your answer. No pull request opens from those commits until a run holds every configured gate on them, or hits a loop cap and opens a draft PR.

**Post-PR watch.** When the run opened or reused a PR, the overlord applies the default watch rule (see **Post-PR watch** below) and runs the watch as `hivemind:github-review-loop` in the main session. That watch has no run ledger. A `planner-escalation` or `root-cluster-suspected` launches `hivemind:pr-feedback-remediation`, and a result with a PR restarts the watch. On Instinct, the overlord handles an escalation by judgment.

**State machine.** A `standard-delivery` run that started on the state machine resumes there and runs on it from request to watched PR. A new `standard-delivery` run does not fall back to it: Instinct is the `standard-delivery` fallback, per `plugin/agents/overlord.md` (`## Engine`) and `docs/adr/0039-instinct-delivery-path.md`. A planner's open questions, and a reviewer's question or high-severity rejection, go to the `question` gate: the overlord asks you only an Ask Set question and takes any other with its recommendation, and the answer goes back to the state that asked, in the same run. A commit made after validation, such as a local review fix, sends the run back through validation at `gate_check`, so the PR opens on a commit every gate held on, with no stop before it:

```
You --> Overlord --> route-workflow --> standard-delivery
                     (Reflex: skip router, ledger, cerebrate)
    plan ................ Cerebrate --> directive (STEP-NNN, delivery shape)
    git_preflight ------> branch (feature/ bugfix/ hotfix/ refactor/ chore/ docs/ test/ ci/)
    implement_next_step -> implement_step (wave: parallel Drones/Changelings)
            ^                   |
            +---- checkpoint <--+   (one molt per wave)
    version_bump_decision -> [version_bump -> version_checkpoint] -> validate
    local_review_decision -> local_review (Local-Reviewer + Codex, or skipped)
    local_review (diminishing-returns) -> diminishing_returns_decision (only taken -> gate_check)
    gate_check (validation held on the head -> open_pr; a later commit -> validate)
    open_pr --> github_review_decision --> github_review_loop (GitHub-Reviewer)
    plan, local_review, github_review_loop, review_remediation_plan(_postpr)
        open_questions | user-input-required | high-severity-rejection -> question
    question (asks only an Ask Set question, takes any other with its recommendation; the answer goes back to the state that asked)
```

1. **Route.** `hivemind:route-workflow` picks the workflow: `standard-delivery`, `analysis-only`, `pr-feedback-remediation`, `hatchery-dispatch`, or `exploratory-intent-session`. The overlord checks for a **Reflex** first, a trivial task that meets every condition in `plugin/agents/overlord.md` (`## Reflex (Ledger-Skip)`); a Reflex takes the fast path and skips the router, the run ledger, and the cerebrate.
2. **Record.** The overlord writes a run ledger to `.hivemind/runs/<run-id>/state.json`. Each state result is normally validated against the workflow definition before the run advances (a resumed run on a changed workflow version can fall back to judgment instead).
3. **Plan.** At `plan`, the cerebrate returns the directive. Before every cerebrate delegation, in every planning state and on every replan, the state machine runs `hivemind:gather-facts` and passes the facts file to the cerebrate. It stops before planning on a failed facts run, a cut field, or injection-suspect text.
4. **Branch.** `git_preflight` checks git state, then `branch` creates or confirms a compliant working branch (`feature/`, `bugfix/`, `hotfix/`, `refactor/`, `chore/`, `docs/`, `test/`, `ci/`). Nothing is ever committed to trunk.
5. **Build in waves.** `implement_next_step` asks `hivemind:next-wave` for the ready wave; `implement_step` dispatches it as parallel drones and changelings; `checkpoint` molts once for the whole wave.
6. **Gate.** `version_bump_decision` (via `hivemind:bump-type`; a required bump goes through `version_bump` and `version_checkpoint`), then `validate` runs the project's validation commands.
7. **Review.** `local_review_decision`, then `local_review`: the local-reviewer runs the Codex review. It needs the `codex` companion (see [Recommended companion plugins](#recommended-companion-plugins)); without it, the step is skipped. A `diminishing-returns` exit goes through `diminishing_returns_decision` first: only a taken advisory reaches `gate_check`, and one not taken ends the run blocked before the PR.
8. **Gate check.** `gate_check` opens the PR only on the commit validation passed on. A commit after validation, such as a local review fix, sends the run back through `validate`; local review, which held on that commit, does not run again.
9. **Ship and watch.** `open_pr` opens the PR, then `github_review_decision` and `github_review_loop` watch it by default, fixing, pushing, replying to, and resolving feedback from the Codex, Copilot, or Claude reviewer bots until approval, merge, close, or an idle hour. Opt out in your request or with `HIVEMIND_SKIP_PR_WATCH`. Agents never merge.

**Waves.** Each wave is the largest set of plan steps whose dependencies are done and whose file scopes do not overlap, so parallel workers never write the same file. A worker deletes only files and empty folders in its scope or created by its own task, each by name, so it never removes a sibling's files. Workers in a wave do not commit; one checkpoint commit (one molt) closes each wave, made by a runner in a script run and by the overlord on Instinct and on the state machine. On the state machine, `hivemind:next-wave` computes each wave from the run ledger; the script computes its waves in `plugin/workflow-src/lib/waves.js`.

**Post-PR watch.** Watching is the default. It is off only when your original request explicitly says not to watch the PR, or when `HIVEMIND_SKIP_PR_WATCH` is set. Which reviewers count is set by `reviewer_filter`: `automated` (default; the Codex, Copilot, and Claude bot accounts), `codex-only`, `all`, or a single login. Approval is a 👍 reaction from Codex on the PR or an `APPROVED` review from Copilot. `max_watch_duration` (default `3600` seconds) is an idle window, re-armed after each remediation cycle rather than a total budget. `max_remediation_cycles` defaults to a floor published by `loop-state.sh floor` (in `plugin/skills/github-review-loop/scripts/`); a caller may raise it but never go below it. The loop ends at a terminal: `clean`, `pr-merged`, `pr-closed`, `max-cycles-reached`, `watch-window-elapsed`, `planner-escalation`, `root-cluster-suspected`, `merge-advised`, `injection-suspect`, `high-severity-rejection`, `user-input-required`, or `blocked`. On every path, `user-input-required` and `high-severity-rejection` go to the overlord's question gate, which asks you only an Ask Set question and takes any other with its recommendation; the watch then runs again, and the answer goes back to the GitHub reviewer that asked. A high-severity rejection you keep is recorded at its source, so review stops raising it. Agents never merge. `merge-advised` is advice to you.

**Decision autonomy.** Routine judgment calls are decided for you; every merge comes back to you. **Tier A** is the closed Ask Set, always surfaced, defined in `plugin/governance/decision-autonomy.md` (Decision Tiers); who decides a reviewer's question is set by `plugin/governance/decision-autonomy.md` (Review Calls). On the state machine the `question` gate asks only the Ask Set; it takes every other call with its recommendation and journals it in the run ledger, including a strong small extra fix, a plan file outside your stated limits, and a repeated remediation plan. **Tier B** decisions are auto-decided and journaled in the run ledger with one disposition: `did-now`, `deferred`, `recorded`, or `surfaced` (when the promotion gate trips). Policy: `plugin/governance/decision-autonomy.md`. Script runs show their decisions differently: only the Ask Set (see Questions above) asks you; a script run lists decisions it took, for veto before merge, in its final message and on the PR, and Decisions on the PR above says which; there is no decision journal and no post-merge decision report.

### Workflows

Workflow definitions (JSON state machines) and the generated workflow scripts live in `plugin/workflows/`:

| Workflow | Purpose | Workflow script |
|---|---|---|
| `workflow-router.json` | Classifies a non-Reflex request (`selected`, `ambiguous`, `exploratory`, `blocked`) and initializes the run ledger | none |
| `standard-delivery.json` | Plan, branch, build in waves, gate, review, open the PR, and watch it | `standard-delivery.js` |
| `analysis-only.json` | Analyze and report; no code changes | `analysis-only.js` |
| `pr-feedback-remediation.json` | Remediate feedback on an existing PR. Intake picks `watch` (run the review loop) or `fix` (one-shot fix pass by `github-reviewer`), after checking out the PR branch | `pr-feedback-remediation.js` |
| `hatchery-dispatch.json` | Brood plan, strain approval, spawn the brood, then monitor it | none |
| `exploratory-intent-session.json` | Open-ended exploration with user checkpoints, ending in a report | none |

A workflow with a script runs it when the launch goes ahead. Otherwise `standard-delivery` runs on Instinct, and `analysis-only` and `pr-feedback-remediation` on their JSON state machines (see [Two engines](#two-engines)). The scripts are built from `plugin/workflow-src/` by `tools/build_workflows.mjs`.

### Brood Mode: Parallel Execution

When the work is big enough, the cerebrate can return a brood delivery shape: independent **strains**, each run as its own session.

```
You --> Overlord --> Cerebrate (decompose)
                 --> "3 independent strains. Approve brood?"
                 --> Yes --> Hatchery mode (hivemind:spawn-brood)
                           --> Strain A (tmux session + worktree) --> own overlord, own branch, own PR
                           --> Strain B (tmux session + worktree) --> own overlord, own branch, own PR
                           --> Strain C (tmux session + worktree) --> own overlord, own branch, own PR
```

- **Approval gate.** The overlord shows you the normalized strain tasks and dispatches nothing until you approve.
- **One worktree and one detached tmux session per strain.** Each strain runs its own overlord in `.claude/worktrees/<brood-id>/<short>`, started in auto mode, so it launches the workflow scripts with no approval prompt. Strains read the plugin's files with no prompt through a read-only rule in a per-brood settings file that spawn passes to each strain.
- **Manifest.** `hivemind:spawn-brood` writes `.hivemind/broods/<brood-id>/manifest.json`.
- **Children are brood-unaware.** Each child starts on a detached HEAD at the base, plans and names its own working branch, runs the full lifecycle, and opens its own PR.
- **Remote control.** Once a strain has started, spawn turns on remote control for it (`/rc <short>`), so you can watch and answer it from claude.ai or the Claude app. Monitoring the brood is your job. Remote control needs a claude.ai subscription login. A strain that had not started when spawn ended gets no remote control until you ask for `hivemind:enable-brood-remote`.
- **Hatchery.** The spawning overlord enters hatchery mode and watches the brood with `hivemind:brood-status` (tmux session state, branch existence, PR status per strain). Spawn turns on remote control for the strains that started; on your explicit request, `hivemind:enable-brood-remote` sends it again to every live strain.

### Signals

| Signal | Meaning |
|---|---|
| :fire: **Flare** | Urgent: an agent hit something it can't resolve alone. The overlord stops and asks you. |
| :zap: **Reflex** | Trivial task that meets every condition in `plugin/agents/overlord.md` (`## Reflex (Ledger-Skip)`), such as a one-file change or a version-only edit. The overlord checks for it before routing, skips the router, the run ledger, and the cerebrate, and delegates the change directly. |
| :dna: **Mutation Decay** | Two fixes are fighting each other (break-fix-break). The swarm stops. You decide. |
| :hourglass: **Creep Stagnation** | The local review loop keeps finding less and less. Advisory exit (`diminishing-returns`). The overlord decides to stop and open the PR on its own and asks you only when the call is in the Ask Set. The state machine journals the call; a script run lists it. |
| :link: **Root-Cluster** | Several findings share one root cause. The reviewer stops patching them one by one and the overlord sends the cerebrate to plan one structural fix. |
| :checkered_flag: **Merge-Advised** | The PR has converged and only a bounded tail remains. Advice to merge: agents never merge; you do. |

### Plain English Still Works

Every themed term maps to a plain concept. You don't need to learn the language to use the framework:

| You can say... | Or say... | Same thing |
|---|---|---|
| "checkpoint commit" | "molt" | Save progress at a phase boundary |
| "run these in parallel" | "spawn a brood" | Run parallel sessions |
| "what's the status" | "brood status" | Check progress across sessions |
| "plan this" | "send the cerebrate" | Get a plan before building |

The theme is for fun. The framework works with or without it.

## Repository layout

```
.claude-plugin/
  marketplace.json          # marketplace manifest (lives at repo root; points to ./plugin)
.devcontainer/              # dev container (devcontainer.json, postCreate.sh, README.md)
.github/workflows/
  policy-check.yml          # validation CI (tools/validate.sh)
  pages.yml                 # builds, tests, and deploys the website in web/
plugin/                     # plugin root; everything Claude Code loads lives here
  .claude-plugin/
    plugin.json             # plugin manifest
  agents/                   # agent definitions (overlord, cerebrate, drone, changeling, synapse, local-reviewer, github-reviewer)
  hooks/                    # plugin hooks (hooks.json, synapse-gate.sh: the synapse runner gate)
  skills/                   # skill definitions (incl. _shared/ helpers)
  governance/               # runtime governance docs loaded via ${CLAUDE_PLUGIN_ROOT}/governance/
  workflows/                # JSON workflow definitions (state machines) and the generated .js workflow scripts
  workflow-src/             # workflow script sources (<id>/meta.js, <id>/main.js, lib/), built into workflows/
  references/               # runtime reference docs (ledger, facts, plan and brief schemas, autonomy table, Author Filtering)
web/                        # GitHub Pages website (HTML, styles, TypeScript in src/, vitest tests)
docs/
  adr/                      # architecture decision records
  prds/                     # product requirement documents
  references/               # maintainer specs for scripts
  design/prototypes/        # archived design explorations (not deployed)
  design/design-system.html # style system reference (not deployed)
  engineering-principles.md
tools/                      # dev-only validation scripts (validate.sh dispatcher, policy linter, report validator)
  build_workflows.mjs       # builds plugin/workflow-src/ into plugin/workflows/*.js; --check is the drift check;
                            # each built script's prose budget lives in tests/policy/prose-byte-budget.json,
                            # and raising one needs a user-approved entry that CHECK 18 checks
  vendor/acorn/             # the vendored acorn parser that build_workflows.mjs reads sources with
tests/                      # dev-only test fixtures and checks (policy, reports, plugin compatibility)
  workflow-scripts/         # node tests for the workflow scripts (run by tools/test_workflow_scripts.sh)
package.json                # website tooling (npm scripts: build, test)
package-lock.json
tsconfig.json               # website TypeScript build (web/src -> web/scripts)
vitest.config.ts            # website test config
AGENTS.md                   # project-specific Codex reviewer guidance
CHANGELOG.md                # project changelog (Keep a Changelog format)
CLAUDE.md                   # project instructions for Claude Code
CONTEXT.md                  # project domain glossary
README.md
```

`plugin/governance/` is the active runtime governance directory. Agents and skills reference these files via `${CLAUDE_PLUGIN_ROOT}/governance/` paths; they are loaded at runtime and affect agent behavior.

`tools/` and `tests/` contain development-time validation scripts and test fixtures. They live outside `plugin/` and are not distributed as plugin runtime data.

`${CLAUDE_PLUGIN_ROOT}` resolves to the `plugin/` directory at runtime, so all internal cross-references (e.g. `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md`) resolve correctly without per-consumer configuration.

## Agents

| Agent | Model | Role |
|---|---|---|
| `hivemind:overlord` | opus | Session default agent. Routes each request to a workflow, then launches its workflow script, runs a `standard-delivery` request on Instinct, or runs the workflow state machine and run ledger. Owns branches, checkpoint commits, version-bump decisions, PRs, and review routing. Delegates all implementation and never writes code. |
| `hivemind:cerebrate` | opus | Research and implementation planning: returns `STEP-NNN` steps with exact file scopes, dependencies, risks, and a delivery shape. No shell (Read, Glob, Grep, LSP, web tools, claude-mem search) and no file writes; branch state comes from the facts file. |
| `hivemind:drone` | opus | Implementation within explicitly assigned file scope; the default owner of every step. |
| `hivemind:changeling` | sonnet | Presentational UI/UX work within explicitly assigned file scope. |
| `hivemind:synapse` | haiku | Runs one committed runner script (facts, commit, push or pull request) and relays its output word for word. Started only by workflow scripts, never by the overlord or a user. Tools: Bash and Write. A plugin hook allows only the five exact runner commands. |
| `hivemind:local-reviewer` | opus | Pre-PR adversarial Codex review loop (`max_iterations` 10). Fixes simple findings itself (2 files or fewer, no architecture or contract impact); a fix that fails its check is undone (only its own files go back to the last commit) and listed. Escalates complex ones to the overlord, and stops on break-fix cycles. Needs the `codex` companion. |
| `hivemind:github-reviewer` | opus | Stateless, one-shot post-PR worker: fetches and classifies review feedback, applies fixes, pushes, replies, and resolves threads. Dispatched by `hivemind:github-review-loop`, which does the monitoring. |

## Skills

All skills are invoked using the namespaced form:

| Skill | Purpose |
|---|---|
| `hivemind:creep-spread` | Analyze project artifacts and generate a populated CONTEXT.md (or CONTEXT-MAP.md for multi-context repos) with domain terms extracted from code, docs, and config |
| `hivemind:molt` | Commit a completed phase, milestone, version bump, or review-remediation item through the committed `molt.sh` script, which commits exactly the listed files, refuses any other dirty path before it changes anything, and reports `committed: false` when there is nothing to commit. Takes an optional commit `subject`; given both its files and a subject, it runs no git command of its own. Used by both engines; in a workflow script it closes each wave and each gate step that can change files, with a subject built by the script |
| `hivemind:create-working-branch` | Create or confirm a compliant working branch before implementation, through a committed script that refuses a dirty tree, an in-progress merge, rebase, cherry-pick, revert or bisect, and a working branch that is trunk, before any change. Used by both engines |
| `hivemind:gather-facts` | Report the branch as it is: branch state, its history against a freshly fetched trunk, the branch's PRs, and the text of any issue or PR the request names, in one complete facts file under `.hivemind/facts/`. The facts step of both workflow scripts, and run by the overlord before every cerebrate delegation on the state machine |
| `hivemind:adaptation-cycle` | Run a pre-PR local Codex review on the current branch diff and return normalized findings. Review-only (it fixes nothing); invoked by the `local-reviewer` agent only |
| `hivemind:github-review-loop` | Watch a PR in the main session and dispatch the fix-mode `github-reviewer` per actionable event; owns the post-PR review loop |
| `hivemind:detect-remediation-signals` | Shared root-cluster / break-fix / diminishing-returns / stop-and-merge detector over a fix-ledger; emits one verdict both reviewers map to their own exit_reason |
| `hivemind:injection-scan` | Scan external-content items for prompt-injection / instruction-override attempts against the security-policy taxonomy; shared judgment skill used by both reviewer agents. Also scans issue and PR text in the branch facts before the planner reads it: the scan step of both workflow scripts, and on the state machine before each cerebrate delegation |
| `hivemind:open-plan-pr` | Open a pull request after completion, validation, and versioning gates pass, through a committed script that takes the PR body from its own file (`--body-file`), pushes through `push-branch.sh`, then reuses an open PR on the same head, base and commit (posting an optional comment there) or creates the PR, optionally as a draft, and verifies it. Used by both engines |
| `hivemind:push-branch` | Push the current working branch to its remote (no PR creation) through the committed `push-branch.sh`, which every push runs through and which refuses trunk; it takes a required `--expect-commit` and refuses when HEAD is another commit. Used to land remediation commits before resuming a review loop |
| `hivemind:plan-interrogation` | Interactive plan interview: challenges a plan against the project's domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) as decisions crystallise |
| `hivemind:create-handoff` | Generate an optional session-resumption handoff doc from a plan |
| `hivemind:plan-to-prd` | Turn an interrogated plan into a committed WHAT-only PRD |
| `hivemind:prd-to-issues` | Slice a PRD into vertically-sliced, brood-ready GitHub issues |
| `hivemind:triage-backlog` | Judgment-driven triage of the entire open GitHub issue backlog across 7 mutually-exclusive label families (readiness/type/effort/moscow/priority/risk/difficulty) plus native GitHub issue dependencies; renders a delta table and applies labels behind a confirm gate; honors the human-only `triage:locked` control label |
| `hivemind:seed-hive` | Per-project setup: write required `.claude/settings.json` keys (enabledPlugins + default agent), gitignore `.hivemind/` and `.claude/worktrees/`, confirm companions, seed the allowlist, invoke `hivemind:creep-spread`, and record the test command in `CLAUDE.md` |
| `hivemind:tdd` | Implement features using Test-Driven Development (TDD) with the red-green-refactor cycle; invoke only in a context that can modify source and test files |
| `hivemind:spawn-brood` | Dispatch parallel overlord sessions: spawns N Claude Code instances in separate git worktrees via tmux and writes the brood manifest |
| `hivemind:brood-status` | Check status of broods under the current checkout, with per-strain status; reports per-strain tmux session state, branch existence, and PR status |
| `hivemind:enable-brood-remote` | User-invoked. Spawn already turns remote control on for the strains that started; on request, this skill sends the Claude `/rc` remote-control command again to every live strain in a brood (tmux keystroke injection) |
| `hivemind:route-workflow` | Sole workflow classifier: selects which workflow handles a non-Reflex request by judgment (never a keyword table); emits selected / ambiguous / exploratory / blocked |
| `hivemind:init-run-ledger` | State machine only. Initialize the run ledger for the current overlord instance: creates `.hivemind/runs/<run-id>/` and writes the initial `state.json` via the committed engine script |
| `hivemind:record-state-result` | State machine only. Record the outcome of the current workflow state into the run ledger and advance `state.current` to the legal next state, validated against the workflow definition |
| `hivemind:next-wave` | State machine only (the `standard-delivery` script computes its waves in code, in `plugin/workflow-src/lib/waves.js`, with parity tests against this engine). Read-only engine for the overlord's intra-run parallel implement loop: reads the run ledger and computes the ready WAVE (the maximal, file-disjoint set of dependency-satisfied plan steps) to dispatch as concurrent agent delegations this iteration |
| `hivemind:bump-type` | Read-only engine for the overlord's `version_bump_decision` workflow state and for the version check of the `standard-delivery` validate step: derives the dominant Bump Type Determination row and bump verdict from the working-branch commits since the base, and with `--version-file` checks each version file against its trunk version raised by that bump; the Bump Trigger / No-bump judgments stay with the caller |
| `hivemind:mark-intent-fallback` | Sanctioned engine write-path for the version-skew intent-fallback resume door and start-fresh stale-run closeout: sets `run.mode:intent_fallback`, appends a fallback event, and optionally closes a stale run via `run.status` |
| `hivemind:decision-report` | State-machine runs only, because it reads the run ledger's decision journal. Render a chronological narrative of the auto-decisions a run made on your behalf, in the consumer project's domain language, and return it as chat text (writes nothing to disk). The automatic post-merge invocation is opt-in via `HIVEMIND_ENABLE_DECISION_REPORT` (see [Configuration](#configuration)); invoking the skill explicitly works regardless of the key |
| `hivemind:zoom-out` | User-invoked only (model invocation disabled): zoom out for broader context; maps relevant modules and callers using the project's domain glossary vocabulary |
| `hivemind:improving-architecture` | Read-only architecture analysis: emits a ranked refactoring blueprint of deepening opportunities (shallow → deep modules) for testability and AI-navigability |
| `hivemind:refactor-to-depth` | Execution skill that performs a behavior-preserving deepening refactor via a refactor-under-green loop; the in-implementation counterpart to the read-only `improving-architecture` blueprint |

`plugin/skills/_shared/` is not a skill: it holds cross-skill reference docs (`LANGUAGE.md`, `DEEPENING.md`) and shell libraries sourced by the skills' engine scripts.

## Governance

Reference documentation in `plugin/governance/`:

| File | Contents |
|---|---|
| `definitions.md` | Canonical vocabulary, authority matrix, agent roles, and cross-agent constraints |
| `workflow.md` | Branch taxonomy, naming rules, commit and PR policy, overlord workflow |
| `safety-rails.md` | Hard-stop rules, commit authority, security constraints, and escalation triggers |
| `report-format.md` | Phase-closing report schemas, handoff formats, and step-delta structure |
| `versioning.md` | SemVer rules, bump triggers, changelog and tag policy |
| `security-policy.md` | External content boundaries, destructive-fix confirmation gate, injection classification |
| `remediation-doctrine.md` | Shared root-cause remediation vocabulary and policy, the one home for both engines: first-finding triage, root-cluster, same-framing test, closed-by-construction, surface-growth escalation, bounded-impact gating, recorded decisions and repeat findings, stop-and-merge |
| `decision-autonomy.md` | Tier A / Tier B decision tiers, the autonomy 2x2, the promotion gate, dispositions, the decision journal, and the post-merge decision-report trigger |

Governance docs are plugin runtime data: agents load them via `${CLAUDE_PLUGIN_ROOT}/governance/` paths at runtime. They are load-bearing: renaming section headers or files can break agent rules that reference them. See `CLAUDE.md` for editing constraints.

### References

Runtime reference docs in `plugin/references/`, and maintainer specs in `docs/references/` (the rows say which):

| File | Contents |
|---|---|
| `run-ledger-schema.md` | Run ledger shape (`.hivemind/runs/<run-id>/state.json`), event shape, and decision-journal convention |
| `docs/references/workflow-state-machine.md` | Maintainer spec, not loaded at runtime: workflow definition shape, legal state types, and the governing invariant |
| `docs/references/brood-ledger-model.md` | Maintainer spec for the brood scripts, not loaded at runtime: brood manifest shape and how it bridges to per-strain run ledgers |
| `fix-ledger-schema.md` | Local reviewer fix-ledger schema |
| `github-pr-review-graphql.md` | Author Filtering only: reviewer identity scoping for `reviewer_filter`. The GraphQL and shell spec for PR review remediation is in `docs/references/github-pr-review-graphql.md` |
| `docs/references/github-subissue-graphql.md` | Maintainer spec for the sub-issue scripts, not loaded at runtime: GitHub operations for native sub-issues |
| `facts-schema.json` | Shape of the branch facts file `hivemind:gather-facts` writes: branch state, history against trunk, the branch's PRs, and the external texts, each list saying whether it is complete |
| `plan-schema.json` | The plan payload the cerebrate returns to the `standard-delivery` script: branch, the pull request title, classification, bump judgments, the validation commands the validate step runs, delivery, and steps with file scopes, dependencies and declared effects outside the repo |
| `decision-autonomy-table.json` | The autonomy table workflow scripts decide by: hard stops, and per decision kind whether each autonomy level decides it or asks you |
| `decision-brief-schema.json` | Shape of a decision brief, the question a script run shows you when it pauses |

### Workflow definitions

State machines in `plugin/workflows/`, read at runtime by the engine skills (`hivemind:init-run-ledger`, `hivemind:record-state-result`), next to the generated workflow scripts. What each one is for: [The Swarm → Workflows](#workflows).

| File | Start state | Generated script |
|---|---|---|
| `workflow-router.json` | `classify` | none |
| `standard-delivery.json` | `plan` | `standard-delivery.js` |
| `analysis-only.json` | `analyze` | `analysis-only.js` |
| `pr-feedback-remediation.json` | `intake` | `pr-feedback-remediation.js` |
| `hatchery-dispatch.json` | `brood_plan` | none |
| `exploratory-intent-session.json` | `intake` | none |

## Website

`web/` is the project's GitHub Pages site. It mirrors this README, which is the source of truth for its content. Build and test it from the repo root:

```bash
npm ci
npm run build
npm test
```

`npm run build` compiles `web/src/` TypeScript into `web/scripts/`; `npm test` runs the vitest suite in `web/tests/`. `.github/workflows/pages.yml` runs the build and tests on pull requests that touch the site, and on pushes to `main` it also deploys `web/` to GitHub Pages.

The site uses the Swarm Glyph design: one stylesheet (`web/styles/main.css`) and one TypeScript engine (`web/src/main.ts`) shared by all three pages, system fonts, no external requests, and it honours `prefers-reduced-motion`. The design explorations are archived in `docs/design/prototypes/` and are not deployed. The style system (tokens, typography, components, motion, authoring rules) is documented in `docs/design/design-system.html`, a repo-only reference that loads the production stylesheet and engine and is not deployed or linked from the site.

## Plugin limitations

The following agent frontmatter fields are not supported by the Claude Code plugin system and are omitted from plugin agent definitions:

- `mcpServers`: configure MCP servers at the project or global level instead
- `permissionMode`: read-only enforcement is the cerebrate's `tools` frontmatter, which holds no Bash, Write or Edit; see the `tools` list in `plugin/agents/cerebrate.md`. A `Bash(...)` entry would grant the whole Bash tool, so the list has none

## License

MIT. [github.com/brenpike/hivemind](https://github.com/brenpike/hivemind)
