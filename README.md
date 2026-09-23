# Hivemind

Multi-agent orchestration framework for Claude Code. Coordinates specialized bioforms to plan, build, review, and ship code — so you don't have to manage the pipeline yourself.

## Install

Inside Claude Code, add the marketplace then install the plugin:

```text
/plugin marketplace add https://github.com/brenpike/hivemind.git
/plugin install hivemind@brenpike
```

## Requirements

- **bash** (macOS, Linux, or WSL on Windows)
- **git** and **gh** (GitHub CLI)
- Claude Code CLI

As of v1.0.0, PowerShell and native Windows support have been removed. All toolchain scripts are bash-based.

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

The `agent` key sets the default agent for the project session. Without it, Claude Code starts with the default agent and the overlord is only reachable on-demand via the Agent tool — bypassing the workflow guarantees.

Or run the setup skill once to apply the required keys automatically:

```text
/hivemind:seed-hive
```

The setup skill also adds `.hivemind/` to your project's `.gitignore`. This directory is created at runtime by the overlord for ephemeral plans, handoffs, and checkpoints — it should not be committed. If you prefer manual setup, add `.hivemind/` to your project's `.gitignore` directly.

`seed-hive` detects which companion plugins are installed (caveman, claude-mem, codex) and interactively prompts you to enable each one, recommending `yes` for any that are detected. Pass an explicit `=yes` or `=no` argument to skip the prompt for that companion (e.g. `caveman=no` opts out without prompting; `claude_mem=yes` enables without prompting).

**Least-privilege permission allowlist.** By default, `seed-hive` merges a recommended set of `permissions.allow` entries into `.claude/settings.json`. Pass `seed_allowlist=no` to skip this step:

```text
/hivemind:seed-hive seed_allowlist=no
```

The seeded entries cover read/output helper Bash commands (`echo`, `printf`, `cat`, `grep`, `jq`, `head`, `tail`, `ls`, `wc`, `sort`, `uniq`) and scoped git read subcommands (`git ls-files`, `git ls-tree`, and `git grep` are read-only listers/searchers; `git stash list` and `git stash show *` are read-only stash inspection; `git tag` is list-only). They are appended-if-absent — existing entries are never overwritten or removed. `echo`/`printf`/`cat`/`sort` **are** included: Claude Code re-prompts (ask/deny) on any command that writes or redirects to a path outside the session working directory (only `> /dev/null` is exempt) and splits compound commands (`&&`/`||`/`;`/`|`/newline), requiring each subcommand to match a rule independently — so granting them does not create an arbitrary-file-write vector (`echo evil > /etc/passwd`, `printf x > ~/.bashrc`, `cmd && rm -rf y` all re-prompt). The only silent write any of these helpers permits is bounded to the working directory, identical to `grep`/`jq`/`head`/`tail`/`ls`/`wc`/`uniq`. `node`, `Edit`, and `Write` are not auto-approved; those require explicit per-project decisions.

**After upgrading the plugin, re-run `/hivemind:seed-hive`.** A newer version may recommend `permissions.allow` entries your project does not have yet, and those entries are merged only when `seed-hive` runs — never automatically on upgrade. Skipping the re-run does not take away any capability — tool grants ship inside the plugin itself and load at session start — but it does leave those newer allow rules unmerged, so you will see interactive approval prompts on operations the template would otherwise have pre-approved. Re-running is always safe: the merge is idempotent and your existing entries are preserved.

For prompt-free local Codex review (`hivemind:adaptation-cycle`), add your Codex cache path to the gitignored `.claude/settings.local.json` — never the tracked `.claude/settings.json`, because this entry hard-codes one machine's absolute `$HOME` path and the tracked file is shared across a team and across machines:

```json
"Bash(node /path/to/.claude/plugins/cache/openai-codex/codex/*)"
```

Replace `/path/to/` with your actual home directory path. The `codex/*` wildcard covers all Codex CLI entry points so the entry does not need updating when Codex is upgraded. `seed-hive`'s allowlist template deliberately seeds no provider grant at all — a machine-specific path cannot be templated into a committed file without becoming a permanently dead rule.

**Upgrading an already-seeded project.** A project seeded by an earlier plugin version may still carry a literal `Bash(node /path/to/.claude/plugins/cache/openai-codex/codex/*)` line in its committed `.claude/settings.json`. The `/path/to/` placeholder was never expanded there, so the rule matches nothing — delete it by hand. Re-running `/hivemind:seed-hive` will not re-add it; the merge is union append-if-absent and never removes, so the fix stops new and repeat seeds but does not clean up an existing file.

2. Create `CLAUDE.md` with project-specific details:
   - Build/test commands
   - Package names and version file paths
   - Versioning configuration (bump triggers, changelogs, tag prefixes)
   - Architecture and code style notes

3. Create `AGENTS.md` at the project root with project-specific Codex review guidance. Include:
   - Review focus areas
   - Severity definitions
   - Project-specific conventions for reviewers

Once configured, the overlord is the session default agent. All skills are available namespaced as `hivemind:<skill-name>`.

## Recommended companion plugins

- [`claude-mem`](https://github.com/thedotmack/claude-mem) — provides optional cross-session memory and continuity. Install separately as a Claude Code plugin. Hivemind works without it; if installed, the cerebrate reads claude-mem memory directly via the MCP search tool (`mcp__plugin_claude-mem_mcp-search__*`) before every plan unless the repo has zero commits or the user explicitly opts out. Writes happen through claude-mem's automatic capture (there is no write MCP tool). `uvx` (from [Astral's `uv`](https://astral.sh/uv)) is an optional dependency of claude-mem that enables its semantic (vector/Chroma) search backend; without it, claude-mem falls back to keyword search and MCP tools remain fully callable. Install with `curl -LsSf https://astral.sh/uv/install.sh | sh`; diagnostics at `~/.claude-mem/logs/` (look for `CHROMA_MCP` entries).

- [`codex`](https://github.com/openai/codex-plugin-cc) — provides local and GitHub-integrated Codex code review. Install and configure with:
  ```text
  /plugin marketplace add https://github.com/openai/codex-plugin-cc.git
  /plugin install codex@openai-codex
  /reload-plugins
  /codex:setup
  ```
  When installed, enables local pre-PR Codex review via the `local-reviewer` agent (backed by `hivemind:adaptation-cycle`) and post-PR review automation via the `hivemind:github-review-loop` skill (which watches the PR and dispatches the stateless fix-mode `github-reviewer` agent to handle feedback classification, fixes, and thread resolution). The framework works without it; if not installed, local review steps are skipped gracefully.

- [`caveman`](https://github.com/juliusbrussee/caveman) (`caveman@caveman`) — Token-compressed communication. Optional. When installed, all framework agents output in caveman ultra mode. `seed-hive` detects it and prompts to enable it automatically, or add manually to `.claude/settings.json`:
  ```json
  "enabledPlugins": { "caveman@caveman": true },
  "pluginConfigs": { "caveman@caveman": { "options": { "defaultLevel": "ultra" } } }
  ```

## Dev container

This repo ships a `.devcontainer/` that provisions a **CI-parity toolchain** so contributors can run the full validation suite locally — in GitHub Codespaces or in VS Code Dev Containers (Dev Containers: Reopen in Container) — and dogfood the plugin. The base image is Ubuntu (Debian/Ubuntu family is mandatory: the policy linter uses GNU `grep -P` and `perl`, which Alpine/BusyBox lack).

**Auto-provisioned** by `.devcontainer/postCreate.sh`:

- Validation toolchain — `jq` and `perl` are explicitly installed via apt before any gate runs (idempotent: skipped if already present); `gh`, Node 20, `python3`, GNU `grep`, and `git` are verified at startup and the script hard-fails if any are missing.
- CLI tools via npm global — Claude Code CLI (`@anthropic-ai/claude-code`), Codex CLI (`@openai/codex`), `claude-mem`.
- `uv` / `uvx` (Astral) via the official install script — claude-mem's optional vector-search backend.
- `tmux` via apt — terminal multiplexer used by the `hivemind:spawn-brood` / `hivemind:brood-status` skills.
- `bun` via the official installer (`bun.sh/install`) — fast JS runtime required by `claude-mem`.
- A **CI-parity smoke test** that runs the same three gates as `.github/workflows/policy-check.yml`: the `python3` JSON-manifest parse, `tools/policy_check.sh --strict`, and `tools/validate_reports.sh --batch tests/reports/`. A green run is a strong best-effort signal that the branch will pass CI — not an absolute guarantee, since CI runs on `ubuntu-latest` while this container pins `ubuntu-20.04` (coreutils/grep/perl/python versions can differ). It also trips on CRLF line endings, which have corrupted these linters before.

**Stays manual** — installing the Claude Code *plugins* requires an authenticated `claude` CLI, which a fresh container does not have. `postCreate.sh` registers the marketplaces (no auth needed) and prints the exact install commands to run once you have signed in:

```text
claude plugin install hivemind@brenpike
claude plugin install codex@openai-codex
claude plugin install claude-mem@thedotmack
claude plugin install caveman@caveman
/codex:setup
```

**Caveman marketplace is registered automatically.** `postCreate.sh` registers the caveman marketplace (no auth required). Caveman *enablement* (`enabledPlugins`, `pluginConfigs`, SubagentStart hook, `.envrc`) is handled by `hivemind:seed-hive caveman=yes` — the canonical path for all plugin config — rather than being hand-seeded by postCreate.

The optional npm installs are wrapped so a single failure (for example in an offline/locked-down Codespace) prints a warning but does not abort — only the CI-parity gates are must-pass. The script is idempotent: re-running `bash .devcontainer/postCreate.sh` is safe.

The Codex cache permission grant (container `$HOME` node path) is seeded into the **gitignored** `.claude/settings.local.json` (never the tracked `.claude/settings.json`), using a jq-merge that does not clobber existing entries.

See `.devcontainer/README.md` for full launch instructions (Codespaces and local Dev Containers), the complete list of what is auto-provisioned, and troubleshooting.

## After cloning a project that uses this plugin

```text
/plugin marketplace add https://github.com/brenpike/hivemind.git
/plugin install hivemind@brenpike
```

## The Swarm

Hivemind coordinates specialized bioforms to plan, build, review, and ship code — so you don't have to manage the pipeline yourself.

### Know Your Bioforms

| Bioform | Role | What it does |
|---|---|---|
| :eye: **Overlord** | Orchestrator | The control plane. Routes the Overmind's directives, distributes the cerebrate's plan, owns the git lifecycle, spawns specialists. Never writes code. Your main interface. |
| :brain: **Cerebrate** | Strategist | Originates the plan. Scans the territory and produces the **directive** — the intelligence the swarm executes. Read-only; thinks, never writes. |
| :hammer: **Drone** | Builder | Builds code within its assigned scope. The workhorse of the swarm. |
| :performing_arts: **Changeling** | Shaper | Handles UI, styling, and visual presentation. Reshapes how things look and feel. |

### The Lifecycle

```
You --> Overlord --> Cerebrate (plan) --> Directive
                 --> Drone/Changeling (build) --> Essence
                 --> Adaptation Cycle (review) --> PR
```

1. You give the **overlord** a task
2. The **cerebrate** scans the territory and returns a **directive**
3. The overlord **spawns** specialists (**drones** / **changelings**) phase by phase
4. Each phase produces **essence** — knowledge carried forward
5. An **adaptation cycle** reviews the work before shipping
6. A PR is opened when the swarm stabilizes

### Brood Mode — Parallel Execution

When the work is big enough, the overlord can split it into independent **strains** and dispatch a **brood** — multiple parallel sessions, each running its own full lifecycle in a separate git worktree.

```
You --> Overlord --> Cerebrate (decompose)
                 --> "3 independent strains detected. Deploy brood?"
                 --> Yes --> Hatchery mode
                           --> Strain A (tmux tab) --> own branch, own PR
                           --> Strain B (tmux tab) --> own branch, own PR
                           --> Strain C (tmux tab) --> own branch, own PR
```

The overlord enters **hatchery** mode — monitoring the brood from home base while each strain evolves independently.

### Signals

| Signal | Meaning |
|---|---|
| :fire: **Flare** | Urgent — agent hit something it can't resolve alone. Overlord stops and asks you. |
| :zap: **Reflex** | Simple task — overlord skips the cerebrate and spawns a drone directly. |
| :dna: **Mutation Decay** | Two fixes are fighting each other. Swarm stops. You decide. |
| :arrows_counterclockwise: **Adaptation Cycle** | Review in progress — the swarm is stabilizing before shipping. |

### Plain English Still Works

Every themed term maps to a plain concept. You don't need to learn the language to use the framework:

| You can say... | Or say... | Same thing |
|---|---|---|
| "checkpoint commit" | "molt" | Save progress at a phase boundary |
| "spawn a brood" | "dispatch a fleet" | Run parallel sessions |
| "what's the status" | "brood status" | Check progress across sessions |
| "plan this" | "send the cerebrate" | Get a plan before building |

The theme is for fun. The framework works with or without it.

## Repository layout

```
.claude-plugin/
  marketplace.json          # marketplace manifest (lives at repo root; points to ./plugin)
plugin/                     # plugin root — everything Claude Code loads lives here
  .claude-plugin/
    plugin.json             # plugin manifest
  agents/                   # agent definitions (overlord, cerebrate, drone, changeling, local-reviewer, github-reviewer)
  skills/                   # skill definitions (incl. _shared/ helpers)
  governance/               # runtime governance docs loaded via ${CLAUDE_PLUGIN_ROOT}/governance/
docs/
tools/                      # dev-only validation scripts (policy linter, report validator)
tests/                      # dev-only test fixtures and checks (policy, reports, plugin compatibility)
AGENTS.md                   # project-specific Codex reviewer guidance
CHANGELOG.md                # project changelog (Keep a Changelog format)
CLAUDE.md                   # project instructions for Claude Code
README.md
```

`plugin/governance/` is the active runtime governance directory. Agents and skills reference these files via `${CLAUDE_PLUGIN_ROOT}/governance/` paths; they are loaded at runtime and affect agent behavior.

`tools/` and `tests/` contain development-time validation scripts and test fixtures. They live outside `plugin/` and are not distributed as plugin runtime data.

`${CLAUDE_PLUGIN_ROOT}` resolves to the `plugin/` directory at runtime, so all internal cross-references (e.g. `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md`) resolve correctly without per-consumer configuration.

## Agents

| Agent | Role |
|---|---|
| `hivemind:overlord` | Default agent. Coordinates all work, owns git workflow, branch/PR decisions, versioning decisions, and external review routing. |
| `hivemind:cerebrate` | Research and implementation planning. Read-only — no file writes. |
| `hivemind:drone` | Implementation within explicitly assigned file scope. |
| `hivemind:changeling` | Presentational UI/UX work within explicitly assigned file scope. |
| `hivemind:local-reviewer` | Pre-PR iterative Codex review with self-owning fix delegation at sonnet tier. |
| `hivemind:github-reviewer` | Stateless fix-mode worker: deep-fetches and classifies post-PR feedback, applies fixes, pushes, and resolves threads. The `hivemind:github-review-loop` skill does the monitoring. |

## Skills

All skills are invoked using the namespaced form:

| Skill | Purpose |
|---|---|
| `hivemind:creep-spread` | Analyze project artifacts and generate a populated CONTEXT.md (or CONTEXT-MAP.md for multi-context repos) with domain terms extracted from code, docs, and config |
| `hivemind:molt` | Commit a completed phase, milestone, version bump, or review-remediation item |
| `hivemind:create-working-branch` | Create or confirm a compliant working branch before implementation |
| `hivemind:adaptation-cycle` | Run a pre-PR local Codex review on the current branch diff — invocable directly by users or via `hivemind:local-reviewer` |
| `hivemind:github-review-loop` | Watch a PR in the main session and dispatch the fix-mode `github-reviewer` per actionable event — owns the post-PR review loop |
| `hivemind:detect-remediation-signals` | Shared root-cluster / break-fix / diminishing-returns / stop-and-merge detector over a fix-ledger — emits one verdict both reviewers map to their own exit_reason |
| `hivemind:injection-scan` | Scan external-content items for prompt-injection / instruction-override attempts against the security-policy taxonomy — shared judgment skill used by both reviewer agents |
| `hivemind:open-plan-pr` | Open a pull request after completion, validation, and versioning gates pass |
| `hivemind:push-branch` | Push the current working branch to its remote (no PR creation) — used to land remediation commits before resuming a review loop |
| `hivemind:plan-interrogation` | Interactive plan interview — challenges a plan against the project's domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) as decisions crystallise |
| `hivemind:create-handoff` | Generate an optional session-resumption handoff doc from a plan |
| `hivemind:plan-to-prd` | Turn an interrogated plan into a committed WHAT-only PRD |
| `hivemind:prd-to-issues` | Slice a PRD into vertically-sliced, brood-ready GitHub issues |
| `hivemind:triage-backlog` | Judgment-driven triage of the entire open GitHub issue backlog across 7 mutually-exclusive label families (readiness/type/effort/moscow/priority/risk/difficulty) plus native GitHub issue dependencies; renders a delta table and applies labels behind a confirm gate; honors the human-only `triage:locked` control label |
| `hivemind:seed-hive` | One-time project setup: write required `.claude/settings.json` keys (enabledPlugins + default agent) and add `.hivemind/` to `.gitignore` |
| `hivemind:tdd` | Implement features using Test-Driven Development (TDD) with the red-green-refactor cycle — invoke only in a context that can modify source and test files |
| `hivemind:spawn-brood` | Dispatch parallel overlord sessions — spawns N Claude Code instances in separate git worktrees via tmux |
| `hivemind:brood-status` | Check status of broods under the current checkout, with per-strain status — reports per-strain tmux session state, branch existence, and PR status |
| `hivemind:enable-brood-remote` | User-invoked: fan the Claude `/rc` remote-control command out to every strain in a brood (tmux keystroke injection) |
| `hivemind:route-workflow` | Sole workflow classifier — selects which workflow handles a non-Reflex request by judgment (never a keyword table); emits selected / ambiguous / exploratory / blocked |
| `hivemind:init-run-ledger` | Initialize the run ledger for the current overlord instance — creates `.hivemind/runs/<run-id>/` and writes the initial `state.json` via the committed engine script |
| `hivemind:record-state-result` | Record the outcome of the current workflow state into the run ledger and advance `state.current` to the legal next state, validated against the workflow definition |
| `hivemind:next-wave` | Read-only engine for the overlord's intra-run parallel implement loop — reads the run ledger and computes the ready WAVE (the maximal, file-disjoint set of dependency-satisfied plan steps) to dispatch as concurrent agent delegations this iteration |
| `hivemind:mark-intent-fallback` | Sanctioned engine write-path for the version-skew intent-fallback resume door and start-fresh stale-run closeout — sets `run.mode:intent_fallback`, appends a fallback event, and optionally closes a stale run via `run.status` |
| `hivemind:decision-report` | Opt-in, off by default — enable it by setting `HIVEMIND_ENABLE_DECISION_REPORT` in the `env` block of `.claude/settings.json` or `.claude/settings.local.json`. When enabled, after a run's PR merges or closes, render a chronological narrative of the auto-decisions the run made on the user's behalf — in the consumer project's domain language — and return it as chat text (render-to-chat; writes nothing to disk — the overlord surfaces the narrative and touches a zero-byte done-marker) |
| `hivemind:zoom-out` | Zoom out for broader context — maps relevant modules and callers using the project's domain glossary vocabulary |
| `hivemind:improving-architecture` | Read-only architecture analysis — emits a ranked refactoring blueprint of deepening opportunities (shallow → deep modules) for testability and AI-navigability |
| `hivemind:refactor-to-depth` | Execution skill that performs a behavior-preserving deepening refactor via a refactor-under-green loop — the in-implementation counterpart to the read-only `improving-architecture` blueprint |
| `hivemind:setup-project` | DEPRECATED — renamed to `hivemind:seed-hive`. Stub forwards to the new skill; will be removed in a future MAJOR release. |
| `hivemind:bootstrap-context` | DEPRECATED — renamed to `hivemind:creep-spread`. Stub forwards to the new skill; will be removed in a future MAJOR release. |

## Governance

Reference documentation in `plugin/governance/`:

| File | Contents |
|---|---|
| `definitions.md` | Canonical vocabulary, authority matrix, agent roles, and cross-agent constraints |
| `workflow.md` | Branch taxonomy, naming rules, commit and PR policy, overlord workflow |
| `safety-rails.md` | Hard-stop rules, security constraints, secret-handling, and escalation triggers |
| `report-format.md` | Phase-closing report schemas, handoff formats, and step-delta structure |
| `versioning.md` | SemVer rules, bump triggers, changelog and tag policy |
| `security-policy.md` | External content boundaries, destructive-fix confirmation gate, injection classification |
| `remediation-doctrine.md` | Shared root-cause remediation vocabulary and policy — root-cluster, same-framing test, closed-by-construction, bounded-impact gating, stop-and-merge |

Governance docs are plugin runtime data — agents load them via `${CLAUDE_PLUGIN_ROOT}/governance/` paths at runtime. They are load-bearing: renaming section headers or files can break agent rules that reference them. See `CLAUDE.md` for editing constraints.

## Plugin limitations

The following agent frontmatter fields are not supported by the Claude Code plugin system and are omitted from plugin agent definitions:

- `mcpServers` — configure MCP servers at the project or global level instead
- `permissionMode` — read-only enforcement is achieved by limiting the cerebrate's `tools` frontmatter to read-only commands; see the cerebrate's `tools` list in `plugin/agents/cerebrate.md`

## License

MIT
