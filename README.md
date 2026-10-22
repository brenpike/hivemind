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
- **jq**: required by the run-ledger engines (`hivemind:init-run-ledger`, `hivemind:record-state-result`) and by `hivemind:seed-hive`
- Claude Code CLI
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

- `.hivemind/runs/<run-id>/state.json`: the run ledger, one per overlord run
- `.hivemind/broods/<brood-id>/manifest.json`: one manifest per brood
- `.hivemind/review-loop/fix-ledger.yaml`: the local reviewer's finding ledger
- `.hivemind/handoffs/` (and `.hivemind/plans/`): session-resumption handoffs and the plans they point at
- short-lived inputs files (e.g. `.hivemind/seed-inputs-<token>.json`, `.hivemind/runs/.init-inputs-<token>.json`) that skills pass to their engine scripts

If you prefer manual setup, add `.hivemind/` and `.claude/worktrees/` to your project's `.gitignore` directly.

**Least-privilege permission allowlist.** By default, `seed-hive` merges a recommended set of `permissions.allow` entries into `.claude/settings.json`. Pass `seed_allowlist=no` to skip this step:

```text
/hivemind:seed-hive seed_allowlist=no
```

The seeded entries cover read/output helper Bash commands (`echo`, `printf`, `cat`, `grep`, `jq`, `head`, `tail`, `ls`, `wc`, `sort`, `uniq`) and scoped git read subcommands (`git ls-files`, `git ls-tree`, and `git grep` are read-only listers/searchers; `git stash list` and `git stash show *` are read-only stash inspection; `git tag` is list-only). The `Skill(hivemind:route-workflow)` entry stops the permission prompt on the read-only routing call the overlord makes for each request. They are appended-if-absent: existing entries are never overwritten or removed. `echo`/`printf`/`cat`/`sort` **are** included: Claude Code re-prompts (ask/deny) on any command that writes or redirects to a path outside the session working directory (only `> /dev/null` is exempt) and splits compound commands (`&&`/`||`/`;`/`|`/newline), requiring each subcommand to match a rule independently, so granting them does not create an arbitrary-file-write vector (`echo evil > /etc/passwd`, `printf x > ~/.bashrc`, `cmd && rm -rf y` all re-prompt). The only silent write any of these helpers permits is bounded to the working directory, identical to `grep`/`jq`/`head`/`tail`/`ls`/`wc`/`uniq`. `node`, `Edit`, and `Write` are not auto-approved; those require explicit per-project decisions.

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
| `HIVEMIND_ENABLE_DECISION_REPORT` | Opt-in, checked by presence (any non-empty value). When set, after a run's PR merges or closes the overlord shows you a report of the decisions it made on your behalf (`hivemind:decision-report`, chat only). The decision journal in the run ledger is written either way. When unset or empty, no report is rendered and no GitHub call is made, but runs that would have reported still get a zero-byte `.decision-report-done` marker, so enabling the key later only reports runs that finish after you enable it. | `docs/adr/0030-config-gated-post-merge-decision-report.md` |

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
| :eye: **Overlord** | Orchestrator | The control plane and your main interface. Routes each request to a workflow, runs the workflow state machine and its run ledger, owns branches, checkpoint commits, version-bump decisions, PRs, and review routing. Delegates all implementation; never writes code. |
| :brain: **Cerebrate** | Strategist | Researches the codebase and returns the **directive**: `STEP-NNN` steps with exact file scopes, dependencies, risks, and a delivery shape (single, multi, or brood). Read-only; never writes files. |
| :hammer: **Drone** | Builder | Implements code, fixes bugs, refactors, and updates tests and release metadata within an explicitly assigned file scope. The default owner of every step. |
| :performing_arts: **Changeling** | Shaper | Presentational UI/UX: markup, styling, layout, design tokens, visual states, presentational accessibility, within its assigned file scope. |

Two more agents handle review. They are composites rather than bioforms: each one classifies findings, fixes the simple ones itself, and hands everything else back to the overlord.

- **Local-Reviewer** (pre-PR): runs an adversarial Codex review loop before the PR exists (needs the `codex` companion).
- **GitHub-Reviewer** (post-PR): a stateless, one-shot worker that fetches and classifies GitHub review feedback, fixes, pushes, replies, and resolves threads. `hivemind:github-review-loop` dispatches it.

### The Lifecycle

When the Workflow tool is available, `standard-delivery` runs as the `hivemind:standard-delivery` workflow script: facts, plan, branch, waves with a commit each, version bump, validation, local review, and the PR. It keeps no run ledger, and the decisions it takes go on the PR body. The overlord then watches the PR as described below. The state machine shown here is the fallback, used when the launch is denied (a `Workflow(hivemind:standard-delivery)` entry in `permissions.deny`) or the Workflow tool is absent, as in brood children.

A `standard-delivery` run, from request to watched PR:

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
    open_pr --> github_review_decision --> github_review_loop (GitHub-Reviewer)
```

1. **Route.** `hivemind:route-workflow` picks the workflow: `standard-delivery`, `analysis-only`, `pr-feedback-remediation`, `hatchery-dispatch`, or `exploratory-intent-session`. A **Reflex** (one owner, one known file, trivial change) takes the fast path and skips the router, the run ledger, and the cerebrate.
2. **Record.** The overlord writes a run ledger to `.hivemind/runs/<run-id>/state.json`. Each state result is normally validated against the workflow definition before the run advances (a resumed run on a changed workflow version can fall back to judgment instead).
3. **Plan.** At `plan`, the cerebrate returns the directive.
4. **Branch.** `git_preflight` checks git state, then `branch` creates or confirms a compliant working branch (`feature/`, `bugfix/`, `hotfix/`, `refactor/`, `chore/`, `docs/`, `test/`, `ci/`). Nothing is ever committed to trunk.
5. **Build in waves.** `implement_next_step` asks `hivemind:next-wave` for the ready wave; `implement_step` dispatches it as parallel drones and changelings; `checkpoint` molts once for the whole wave.
6. **Gate.** `version_bump_decision` (via `hivemind:bump-type`; a required bump goes through `version_bump` and `version_checkpoint`), then `validate` runs the project's validation commands.
7. **Review.** `local_review_decision`, then `local_review`: the local-reviewer runs the Codex review. It needs the `codex` companion (see [Recommended companion plugins](#recommended-companion-plugins)); without it, the step is skipped.
8. **Ship and watch.** `open_pr` opens the PR, then `github_review_decision` and `github_review_loop` watch it by default, fixing, pushing, replying to, and resolving feedback from the Codex, Copilot, or Claude reviewer bots until approval, merge, close, or an idle hour. Opt out in your request or with `HIVEMIND_SKIP_PR_WATCH`. Agents never merge.

**Waves.** Each wave is the largest set of plan steps whose dependencies are done and whose file scopes do not overlap, so parallel workers never write the same file. Workers in a wave do not commit; the overlord makes one checkpoint commit (one molt) per wave.

**Post-PR watch.** Watching is the default. It is off only when your original request explicitly says not to watch the PR, or when `HIVEMIND_SKIP_PR_WATCH` is set. Which reviewers count is set by `reviewer_filter`: `automated` (default; the Codex, Copilot, and Claude bot accounts), `codex-only`, `all`, or a single login. Approval is a 👍 reaction from Codex on the PR or an `APPROVED` review from Copilot. `max_watch_duration` (default `3600` seconds) is an idle window, re-armed after each remediation cycle rather than a total budget. `max_remediation_cycles` defaults to a floor published by `loop-state.sh floor` (in `plugin/skills/github-review-loop/scripts/`); a caller may raise it but never go below it. The loop ends at a terminal: `clean`, `pr-merged`, `pr-closed`, `max-cycles-reached`, `watch-window-elapsed`, `planner-escalation`, `root-cluster-suspected`, `merge-advised`, `injection-suspect`, `high-severity-rejection`, `user-input-required`, or `blocked`. Agents never merge. `merge-advised` is advice to you.

**Decision autonomy.** Routine judgment calls are decided for you and journaled; irreversible, architectural, or safety-relevant calls and every merge come back to you. **Tier A** decisions are always surfaced: safety rails, ambiguous routing, resume and version-skew choices, brood strain approval, tool failures after retries, facts only you hold, and every merge recommendation. **Tier B** decisions are auto-decided and journaled in the run ledger with one disposition: `did-now`, `deferred`, `recorded`, or `surfaced` (when the promotion gate trips). Policy: `plugin/governance/decision-autonomy.md`.

### Workflows

Workflow definitions live in `plugin/workflows/`:

| Workflow | Purpose |
|---|---|
| `workflow-router.json` | Classifies a non-Reflex request (`selected`, `ambiguous`, `exploratory`, `blocked`) and initializes the run ledger |
| `standard-delivery.json` | Plan, branch, build in waves, gate, review, open the PR, and watch it |
| `analysis-only.json` | Analyze and report; no code changes |
| `pr-feedback-remediation.json` | Remediate feedback on an existing PR. Intake picks `watch` (run the review loop) or `fix` (one-shot fix pass by `github-reviewer`), after checking out the PR branch |
| `hatchery-dispatch.json` | Brood plan, strain approval, spawn the brood, then monitor it |
| `exploratory-intent-session.json` | Open-ended exploration with user checkpoints, ending in a report |

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
- **One worktree and one detached tmux session per strain.** Each strain runs its own overlord in `.claude/worktrees/<brood-id>/<short>`.
- **Manifest.** `hivemind:spawn-brood` writes `.hivemind/broods/<brood-id>/manifest.json`.
- **Children are brood-unaware.** Each child derives its own compliant working branch, runs the full lifecycle, and opens its own PR.
- **Hatchery.** The spawning overlord enters hatchery mode and watches the brood with `hivemind:brood-status` (tmux session state, branch existence, PR status per strain). On your explicit request, `hivemind:enable-brood-remote` turns on remote control for every strain.

### Signals

| Signal | Meaning |
|---|---|
| :fire: **Flare** | Urgent: an agent hit something it can't resolve alone. The overlord stops and asks you. |
| :zap: **Reflex** | Trivial task: one owner, one known file, no version impact. The overlord skips the router, the run ledger, and the cerebrate, and delegates the change directly. |
| :dna: **Mutation Decay** | Two fixes are fighting each other (break-fix-break). The swarm stops. You decide. |
| :hourglass: **Creep Stagnation** | The local review loop keeps finding less and less. Advisory exit (`diminishing-returns`). The overlord decides to stop and open the PR on its own, journals the call, and asks you only if the promotion gate trips. |
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
  agents/                   # agent definitions (overlord, cerebrate, drone, changeling, local-reviewer, github-reviewer)
  skills/                   # skill definitions (incl. _shared/ helpers)
  governance/               # runtime governance docs loaded via ${CLAUDE_PLUGIN_ROOT}/governance/
  workflows/                # declarative workflow definitions (JSON state machines)
  references/               # runtime reference docs (ledger schemas, GraphQL operations, state machine)
web/                        # GitHub Pages website (HTML, styles, TypeScript in src/, vitest tests)
docs/
  adr/                      # architecture decision records
  prds/                     # product requirement documents
  design/prototypes/        # archived design explorations (not deployed)
  design/design-system.html # style system reference (not deployed)
  engineering-principles.md
tools/                      # dev-only validation scripts (validate.sh dispatcher, policy linter, report validator)
tests/                      # dev-only test fixtures and checks (policy, reports, plugin compatibility)
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
| `hivemind:overlord` | opus | Session default agent. Routes each request to a workflow, runs the workflow state machine and run ledger, owns branches, checkpoint commits, version-bump decisions, PRs, and review routing. Delegates all implementation and never writes code. |
| `hivemind:cerebrate` | opus | Research and implementation planning: returns `STEP-NNN` steps with exact file scopes, dependencies, risks, and a delivery shape. Read-only, no file writes. |
| `hivemind:drone` | opus | Implementation within explicitly assigned file scope; the default owner of every step. |
| `hivemind:changeling` | sonnet | Presentational UI/UX work within explicitly assigned file scope. |
| `hivemind:local-reviewer` | opus | Pre-PR adversarial Codex review loop (`max_iterations` 10). Fixes simple findings itself (2 files or fewer, no architecture or contract impact), escalates complex ones to the overlord, and stops on break-fix cycles. Needs the `codex` companion. |
| `hivemind:github-reviewer` | opus | Stateless, one-shot post-PR worker: fetches and classifies review feedback, applies fixes, pushes, replies, and resolves threads. Dispatched by `hivemind:github-review-loop`, which does the monitoring. |

## Skills

All skills are invoked using the namespaced form:

| Skill | Purpose |
|---|---|
| `hivemind:creep-spread` | Analyze project artifacts and generate a populated CONTEXT.md (or CONTEXT-MAP.md for multi-context repos) with domain terms extracted from code, docs, and config |
| `hivemind:molt` | Commit a completed phase, milestone, version bump, or review-remediation item |
| `hivemind:create-working-branch` | Create or confirm a compliant working branch before implementation |
| `hivemind:gather-facts` | Report the branch as it is: branch state, its history against a freshly fetched trunk, the branch's PRs, and the text of any issue or PR the request names, in one complete facts file |
| `hivemind:adaptation-cycle` | Run a pre-PR local Codex review on the current branch diff and return normalized findings. Review-only (it fixes nothing); invoked by the `local-reviewer` agent only |
| `hivemind:github-review-loop` | Watch a PR in the main session and dispatch the fix-mode `github-reviewer` per actionable event; owns the post-PR review loop |
| `hivemind:detect-remediation-signals` | Shared root-cluster / break-fix / diminishing-returns / stop-and-merge detector over a fix-ledger; emits one verdict both reviewers map to their own exit_reason |
| `hivemind:injection-scan` | Scan external-content items for prompt-injection / instruction-override attempts against the security-policy taxonomy; shared judgment skill used by both reviewer agents. Also scans issue and PR text in the branch facts before the planner reads it |
| `hivemind:open-plan-pr` | Open a pull request after completion, validation, and versioning gates pass |
| `hivemind:push-branch` | Push the current working branch to its remote (no PR creation); used to land remediation commits before resuming a review loop |
| `hivemind:plan-interrogation` | Interactive plan interview: challenges a plan against the project's domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) as decisions crystallise |
| `hivemind:create-handoff` | Generate an optional session-resumption handoff doc from a plan |
| `hivemind:plan-to-prd` | Turn an interrogated plan into a committed WHAT-only PRD |
| `hivemind:prd-to-issues` | Slice a PRD into vertically-sliced, brood-ready GitHub issues |
| `hivemind:triage-backlog` | Judgment-driven triage of the entire open GitHub issue backlog across 7 mutually-exclusive label families (readiness/type/effort/moscow/priority/risk/difficulty) plus native GitHub issue dependencies; renders a delta table and applies labels behind a confirm gate; honors the human-only `triage:locked` control label |
| `hivemind:seed-hive` | Per-project setup: write required `.claude/settings.json` keys (enabledPlugins + default agent), gitignore `.hivemind/` and `.claude/worktrees/`, confirm companions, seed the allowlist, invoke `hivemind:creep-spread`, and record the test command in `CLAUDE.md` |
| `hivemind:tdd` | Implement features using Test-Driven Development (TDD) with the red-green-refactor cycle; invoke only in a context that can modify source and test files |
| `hivemind:spawn-brood` | Dispatch parallel overlord sessions: spawns N Claude Code instances in separate git worktrees via tmux and writes the brood manifest |
| `hivemind:brood-status` | Check status of broods under the current checkout, with per-strain status; reports per-strain tmux session state, branch existence, and PR status |
| `hivemind:enable-brood-remote` | User-invoked: fan the Claude `/rc` remote-control command out to every strain in a brood (tmux keystroke injection) |
| `hivemind:route-workflow` | Sole workflow classifier: selects which workflow handles a non-Reflex request by judgment (never a keyword table); emits selected / ambiguous / exploratory / blocked |
| `hivemind:init-run-ledger` | Initialize the run ledger for the current overlord instance: creates `.hivemind/runs/<run-id>/` and writes the initial `state.json` via the committed engine script |
| `hivemind:record-state-result` | Record the outcome of the current workflow state into the run ledger and advance `state.current` to the legal next state, validated against the workflow definition |
| `hivemind:next-wave` | Read-only engine for the overlord's intra-run parallel implement loop: reads the run ledger and computes the ready WAVE (the maximal, file-disjoint set of dependency-satisfied plan steps) to dispatch as concurrent agent delegations this iteration |
| `hivemind:bump-type` | Read-only engine for the overlord's `version_bump_decision` workflow state: derives the dominant Bump Type Determination row and bump verdict from the working-branch commits since the base; the Bump Trigger / No-bump judgments stay with the caller |
| `hivemind:mark-intent-fallback` | Sanctioned engine write-path for the version-skew intent-fallback resume door and start-fresh stale-run closeout: sets `run.mode:intent_fallback`, appends a fallback event, and optionally closes a stale run via `run.status` |
| `hivemind:decision-report` | Render a chronological narrative of the auto-decisions a run made on your behalf, in the consumer project's domain language, and return it as chat text (writes nothing to disk). The automatic post-merge invocation is opt-in via `HIVEMIND_ENABLE_DECISION_REPORT` (see [Configuration](#configuration)); invoking the skill explicitly works regardless of the key |
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
| `remediation-doctrine.md` | Shared root-cause remediation vocabulary and policy: root-cluster, same-framing test, closed-by-construction, bounded-impact gating, stop-and-merge |
| `decision-autonomy.md` | Tier A / Tier B decision tiers, the autonomy 2x2, the promotion gate, dispositions, the decision journal, and the post-merge decision-report trigger |

Governance docs are plugin runtime data: agents load them via `${CLAUDE_PLUGIN_ROOT}/governance/` paths at runtime. They are load-bearing: renaming section headers or files can break agent rules that reference them. See `CLAUDE.md` for editing constraints.

### References

Runtime reference docs in `plugin/references/`:

| File | Contents |
|---|---|
| `run-ledger-schema.md` | Run ledger shape (`.hivemind/runs/<run-id>/state.json`), event shape, and decision-journal convention |
| `workflow-state-machine.md` | Workflow definition shape, legal state types, and the governing invariant |
| `brood-ledger-model.md` | Brood manifest shape and how it bridges to per-strain run ledgers |
| `fix-ledger-schema.md` | Local reviewer fix-ledger schema |
| `github-pr-review-graphql.md` | GitHub operations for PR review remediation, reviewer filters, and approval detection |
| `github-subissue-graphql.md` | GitHub operations for native sub-issues |

### Workflow definitions

State machines in `plugin/workflows/`, loaded by the overlord at runtime. What each one is for: [The Swarm → Workflows](#workflows).

| File | Start state |
|---|---|
| `workflow-router.json` | `classify` |
| `standard-delivery.json` | `plan` |
| `analysis-only.json` | `analyze` |
| `pr-feedback-remediation.json` | `intake` |
| `hatchery-dispatch.json` | `brood_plan` |
| `exploratory-intent-session.json` | `intake` |

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
