# CLAUDE.md

Guidance for Claude Code instances working **on this repo** (not consuming the published plugin).

## What this repo is

Source for the `hivemind` Claude Code plugin + a single-plugin marketplace pointing at it. Plugin defines four agents (overlord, cerebrate, drone, changeling) and ten skills; governance docs are plugin **runtime data** loaded by agents, not just human reference.

## Engineering principles

Project engineering principles governing how prose, scripts, and skills are factored across agents/skills/governance live in `docs/engineering-principles.md`. Consult it before extracting procedure out of an agent or skill, or when deciding whether something belongs in a script, a skill, or a governance doc.

## Repository layout

```
.claude-plugin/marketplace.json   # marketplace manifest at repo root → source: ./plugin
plugin/                           # plugin root (resolves to ${CLAUDE_PLUGIN_ROOT})
  .claude-plugin/plugin.json      # plugin manifest (name, version)
  agents/{overlord,cerebrate,drone,changeling}.md
  skills/<skill-name>/SKILL.md
  skills/_shared/                 # cross-skill shared docs; first use = architecture vocabulary (LANGUAGE.md) + deepening mechanics (DEEPENING.md), shared by improving-architecture and refactor-to-depth
  governance/                     # *.md loaded by agents at runtime
README.md
CLAUDE.md
```

`${CLAUDE_PLUGIN_ROOT}` resolves to `plugin/` because that's where `plugin.json` lives. All cross-refs inside `plugin/` use `${CLAUDE_PLUGIN_ROOT}/...` paths — never relative or repo-rooted paths.

Anything the runtime loads must live under `plugin/`.

## Editing rules specific to this repo

- **Path refs across plugin files MUST use `${CLAUDE_PLUGIN_ROOT}/...`.** Bare `governance/foo.md` or `agents/foo.md` paths break when consumers install the plugin. Grep for bare paths before merging.
- **Agent frontmatter limits:** Claude Code plugin system does not honor `mcpServers` or `permissionMode` in agent frontmatter. Read-only enforcement on cerebrate is done by restricting `tools:` list, not by `permissionMode`. Don't re-add these fields.
- **Skills are namespaced as `hivemind:<skill>`** when consumed. Internal cross-references in skill/agent bodies should use the namespaced form so docs match runtime behavior.
- **Governance docs are load-bearing.** Renaming a section header inside `plugin/governance/*.md` may break agent rules that reference that header by name (e.g. `(Required Git Preflight)`, `(Definitions → Trivial change)`). Search for header references before renaming.

## Versioning

Single source of truth: `plugin/.claude-plugin/plugin.json` `"version"`. Bump triggers and policy: `plugin/governance/versioning.md`. README does not carry a version.

## Branching / PR workflow

This repo dogfoods its own plugin's workflow. Authoritative rules: `plugin/governance/workflow.md`, `plugin/governance/definitions.md`. When working here, follow them — overlord → working branch → checkpoint commits → PR → Codex review.

Default branches:
- Trunk / PR base: `main`
- Working branch naming: per `workflow.md` (Branch Creation)

## Validation

No compiler or code-coverage suite — this is a Markdown plugin. The full validation suite (`tools/validate.sh --all`) enforces three categories of gates:

1. **JSON manifests parse** — both `plugin/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
2. **Prose/contract linter** — `tools/policy_check.sh --strict`. Validates `plugin/` files against fixtures in `tests/policy/`, `tests/plugin/`, and `tests/workflows/`, and checks that `${CLAUDE_PLUGIN_ROOT}/...` path refs resolve. Advisory by default; `--strict` fails on any finding not in `tests/policy/policy-lint-allowlist.json`. Bare-path invariant enforced here (`CHECK8`).
3. **Report-format linter** — `tools/validate_reports.sh --batch tests/reports/`. Validates agent report fixtures against report format contracts.

### Local pre-merge

Validation runs **once, before opening the PR**, at the `validate` workflow state. The canonical local command is:

```bash
bash tools/validate.sh --changed
```

This resolves the merge-base against `origin/main` → `main` → `HEAD~1`, computes the changed-file set (committed diff + uncommitted working-tree changes), and runs only the suites relevant to those paths. The path→suite mapping lives in `tools/validate.sh`; docs here summarise it rather than duplicate it.

**FAIL-CLOSED guarantee:** any unmapped path inside a code-bearing tree, an unresolvable base ref, or any edit to `tools/**` (validator bootstrap) escalates automatically to the full suite. `.claude/settings.json` routes to two suites: the policy suite, because a policy fixture asserts its rule set as raw text, and the `json-manifests` parse gate, because only a real `json.load` proves Claude Code can still load the file after an edit; the rest of `.claude/` stays docs-only by design. Nothing relevant is ever silently skipped.

For an exhaustive local run identical to the push-to-main CI gate:

```bash
bash tools/validate.sh --all
```

To assert the path→suite mapping covers every suite and test directory (no coverage gaps):

```bash
bash tools/validate.sh --self-test
```

Smoke install in a scratch Claude Code session before publishing breaking layout changes:

```text
/plugin marketplace add <local-path-or-git-url>
/plugin install hivemind@brenpike
```

### CI behavior

CI runs via `.github/workflows/policy-check.yml` (job: `policy-check`), enforced on every PR and every push to `main`:

- **PR:** `bash tools/validate.sh --changed --base origin/main` — path-selective subset.
- **Push to main:** `bash tools/validate.sh --all` — full suite merge gate (belt-and-suspenders).

### Change-Class Validation

`tools/validate.sh --changed` performs change-class selection automatically. There is no manual table to consult: the dispatcher maps each changed path to the relevant suites (FAIL-CLOSED) and runs only those. Edits outside every code-bearing tree (e.g. `README.md`, `docs/`) produce no code-suite runs; edits inside `plugin/`, `.claude-plugin/`, `tools/`, or `tests/` trigger the appropriate suites or, when a path is unmapped, the full suite.

## Common pitfalls

- Adding a new governance doc but forgetting to reference it from an agent → dead file.
- Adding a new skill but forgetting `${CLAUDE_PLUGIN_ROOT}/skills/_shared/...` ref when reusing shared helpers.
- Editing `marketplace.json` `source` away from `./plugin` — breaks consumer installs.
- Putting plugin content at repo root instead of under `plugin/` — `${CLAUDE_PLUGIN_ROOT}` will not resolve where authors expect.
- Adding/renaming a load-bearing governance section with named consumers (or editing a `tests/policy/safety-*.json`) without adding the consumer-assertion fixture → unprotected coupling (P3).
- Authoring a `tests/policy/safety-*.json` fixture without reading the pin-authoring contract in `tests/policy/README.md` → overclaimed or wrong-clause pins that leave the suite green through a real regression.

## Companion plugins referenced

`claude-mem` is optional — cerebrate reads its memory directly via the MCP search tool (`mcp__plugin_claude-mem_mcp-search__*`) when present, skips when absent. Writes go through claude-mem's automatic capture (there is no write MCP tool). When `claude_mem=yes` and claude-mem is installed, `seed-hive` provisions claude-mem's `CLAUDE_CODE_PATH` in `~/.claude-mem/settings.json` (only when currently empty) so its background worker can locate the `claude` binary. Do not hard-require it from any agent or skill.

`codex@openai-codex` is optional — the overlord uses `codex-plugin-cc` for pre-PR local review via the `local-reviewer` agent (`hivemind:adaptation-cycle`). If not installed, the overlord skips local review and proceeds to PR. Run `codex:setup` after installation. Do not hard-require it from any agent or skill.

The local Codex review model is operator-overridable via `HIVEMIND_LOCAL_REVIEW_MODEL`, set in the `env` block of `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored, per-account). Empty/unset → codex uses its own default (zero consumer regression). The value passes a charset gate `^[a-zA-Z0-9/_.\-]+$` (e.g. `gpt-5.3-codex`, `gpt-5.5` are valid). The unavailable-model `400` case is account-specific. Reference: ADR-0022.

The default post-PR watch (see Branching / PR workflow above) can be switched off standing-wide via `HIVEMIND_SKIP_PR_WATCH`, set in the `env` block of `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored, per-account). Unset/empty → the overlord watches normally per its default-watch rule (zero behavior change). Set (checked by presence) → the overlord never watches, short-circuiting the per-run `request.raw` read entirely. Because the committed settings file is in-repo, the key inherits into brood worktrees. Reference: ADR-0029.

The post-merge decision report is opt-in via `HIVEMIND_ENABLE_DECISION_REPORT`, set in the `env` block of `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored, per-account). Unset/empty → the report is off: the deferred-report scan renders nothing and makes no GitHub call, but still touches the zero-byte `.decision-report-done` marker for awaiting runs, so enabling it later only reports runs that finish after it is enabled. Set (checked by presence) → the overlord surfaces the post-merge decision report as before. The decision journal is written either way. Because the committed settings file is in-repo, the key inherits into brood worktrees. Reference: ADR-0030.

## Brood execution

The plugin supports parallel multi-overlord execution via spawn-brood and brood-status skills. Each brood session runs in its own git worktree as an independent Claude Code instance.

- **Architecture decision:** `docs/adr/0007-fleet-children-unaware-coordinator-dashboard.md` — children have zero brood awareness; coordinator is a status dashboard
- **Brood manifest:** `.hivemind/brood/manifest.json` (in main checkout; already gitignored under `.hivemind/`)
- **Worktree sessions:** `.claude/worktrees/` (gitignored)

Children are standard overlord sessions receiving a task description. No brood-specific code paths exist in child sessions.

## Local developer setup

To eliminate permission prompts for the local Codex review flow (`hivemind:adaptation-cycle`), add your Codex cache path to `.claude/settings.local.json` (gitignored):

```json
{
  "permissions": {
    "allow": [
      "Bash(node /path/to/.claude/plugins/cache/openai-codex/codex/*)"
    ]
  }
}
```

Replace `/path/to/` with your actual home directory path. This file is gitignored and must be created locally by each contributor. Reference: ADR-0010 for the rationale on where this placeholder may and may not be copied.

Periodically prune stale entries from `.claude/settings.local.json`. Common dead rules to remove: old project-name allowlist entries (e.g. `agent-framework` paths that no longer exist), malformed pseudo-Bash entries that don't match Claude Code's `Bash(...)` syntax, and version-pinned codex paths superseded by the `codex/*` wildcard. A bloated local allowlist accumulates false grants and obscures the actual permission surface.
