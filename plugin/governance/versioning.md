# Versioning Policy

## Purpose

SemVer workflow for repositories publishing versioned artifacts. Package names, artifact paths, version-file and changelog locations, tag prefixes and validation commands live in `CLAUDE.md` or docs it references.

## Scope

Covers every artifact the project versions (package, library, application, plugin, container, distributable binary, or similar), each independently unless project docs say otherwise. An internal shared component with no standalone distribution has no version unless the project defines one; its change may require bumps in dependent artifacts whose public API, runtime behavior, generated output, package contents or compatibility contracts change.

## SemVer Rules

Versions follow Semantic Versioning 2.0.0: `MAJOR.MINOR.PATCH`.

| Increment | Trigger |
|---|---|
| MAJOR | Breaking change to public API, compatibility contract, data format, runtime behavior contract, or documented consumer expectation |
| MINOR | Backward-compatible public API, capability, option, behavior, or artifact surface |
| PATCH | Bug fix, internal refactor, or implementation change with no public compatibility impact |

A `0.x.y` artifact may take a minor increment for a breaking change, still with a changelog entry under `Changed` or `Removed` naming the breaking surface (function, type, flag, file, endpoint) and the migration path.

Pre-release labels such as `1.2.0-beta.1` need overlord coordination and project release-workflow support.

## Bump Trigger

A PR needs a version bump when it changes files affecting a published artifact's:

- runtime behavior
- public API
- compatibility contract
- generated output
- packaged output
- distribution metadata
- documented consumer expectation

`CLAUDE.md` or docs it references define the exact bump-trigger paths.

No bump is required by default for these changes:

- documentation-only
- test-only
- CI-only
- hivemind/governance
- changelog-only maintenance
- markdown-only

Project docs may add required or excluded paths. When `CLAUDE.md` defines no bump-trigger paths, these lists are exhaustive, and **Bump Trigger wins on overlap**: a change matching any Bump Trigger bullet needs a bump even if it also matches a No-bump bullet, as does a markdown-only change altering a documented consumer expectation or a CI change altering packaged output.

## Bump Type Determination

The overlord derives bump type from conventional commit types; impact on public API, compatibility, runtime, data format, generated output, package or documented behavior; and breaking-change markers (`!`, `BREAKING CHANGE:`) or actual compatibility impact.

| Commit / impact | Increment |
|---|---|
| `feat` with backward-compatible public capability | MINOR |
| `feat!` or `BREAKING CHANGE:` | MAJOR |
| `fix` / `bugfix` without breaking change | PATCH |
| `refactor` without public compatibility impact | PATCH |
| `refactor!` | MAJOR |
| `chore` / `docs` / `test` / `ci` without artifact impact | No bump |

The overlord makes two judgments, whether the change satisfies any Bump Trigger bullet (`--bump-trigger yes|no`) and whether it matches one or more "No bump is required by default" bullets (`--no-bump-match yes|no`), then runs the `hivemind:bump-type` engine (`${CLAUDE_PLUGIN_ROOT}/skills/bump-type/scripts/bump-type.sh`), `<base>` being the resolved base branch from `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (Framework Defaults):

`bash "${CLAUDE_PLUGIN_ROOT}/skills/bump-type/scripts/bump-type.sh" <base> --bump-trigger <yes|no> --no-bump-match <yes|no>`

A change matches a row when that row is the dominant row across all working-branch commits since the branch diverged from `<base>`, as the engine computes it, and the row's impact condition holds: MAJOR, MINOR and PATCH need a Bump Trigger bullet; No bump needs a No-bump bullet and no Bump Trigger bullet. Act on the engine's `verdict`:

- `bump_required`: bump by the reported `bump_type`.
- `no_bump`: no bump.
- `ask_user`: the change matches more than one row or none (a dominant row failing its impact condition counts as none); ask the user before delegating version edits.
- exit 1 with `blocker: <reason>` on stderr: surface the blocker, never hand-computing the dominant row.

Only the engine holds the revert pre-pass, the per-commit row mapping and the dominant-row precedence, reading commits NUL-separated; never restate or hand-apply them.

## Bump Execution

The overlord delegates version and release file edits to drone; the bump ships in the triggering change's PR unless the user explicitly directs otherwise.

Project docs must name the files to update atomically: canonical version file, changelog or release notes, package or artifact metadata, documentation mirrors, release validation files, and the like. Each artifact has one canonical version source; mirrors are informational, kept in sync.

If `CLAUDE.md` lists no artifact files for a triggered bump, the overlord stops and asks the user before delegating any version edit. The drone must not infer artifact files.

## CHANGELOG / Release Notes

Each versioned artifact keeps a changelog or release notes unless `CLAUDE.md` defines another mechanism. Recommended Keep a Changelog sections: Added, Changed, Deprecated, Removed, Fixed, Security.

On a bump, turn pending unreleased entries into a dated release section, then, unless `CLAUDE.md` says otherwise, reset the unreleased section to:

```markdown
## [Unreleased]

### Added

### Changed

### Fixed
```

## Tags

Tags follow the project release workflow, whose docs must define manual or CI-created tags, the format, the per-artifact prefix when several exist, annotated or lightweight, and timing relative to publish or deploy. Recommended: `vX.Y.Z` for one artifact, `<artifact-prefix>/vX.Y.Z` for several.
