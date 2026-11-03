# Versioning Policy

## Purpose

Generic SemVer workflow for repositories that publish versioned artifacts. Project-specific package names, artifact paths, version-file and changelog locations, tag prefixes, and validation commands live in `CLAUDE.md` or project docs it references.

## Scope

Applies to every independently versioned artifact the project defines: packages, libraries, applications, plugins, containers, distributable binaries, or similar. Each artifact is versioned independently unless project docs say otherwise.

Internal shared components with no standalone distribution carry no version unless the project defines one. A shared-component change may require bumps in dependent artifacts if public API, runtime behavior, generated output, package contents, or compatibility contracts change.

## SemVer Rules

This repository follows Semantic Versioning 2.0.0: `MAJOR.MINOR.PATCH`.

| Increment | Trigger |
|---|---|
| MAJOR | Breaking change to public API, compatibility contract, data format, runtime behavior contract, or documented consumer expectation |
| MINOR | Backward-compatible public API, capability, option, behavior, or artifact surface |
| PATCH | Bug fix, internal refactor, or implementation change with no public compatibility impact |

For `0.x.y` artifacts SemVer permits a minor increment for a breaking change, which still needs a changelog entry under `Changed` or `Removed` naming the breaking surface (function, type, flag, file, endpoint) and the migration path.

Pre-release labels such as `1.2.0-beta.1` require overlord coordination and project release-workflow support.

## Bump Trigger

A version bump is required when a PR changes files that affect a published artifact's:

- runtime behavior
- public API
- compatibility contract
- generated output
- packaged output
- distribution metadata
- documented consumer expectation

Exact bump-trigger paths are project-specific, defined in `CLAUDE.md` or project docs it references.

No bump is required by default for:

- documentation-only changes
- test-only changes
- CI-only changes
- hivemind/governance changes
- changelog-only maintenance
- markdown-only changes

Project docs may define more required or excluded paths. When `CLAUDE.md` defines no bump-trigger paths, these lists are exhaustive, and **Bump Trigger wins on overlap**: a change matching any Bump Trigger bullet requires a bump, even when it also matches a No-bump bullet. The No-bump list applies only to a change that matches one or more No-bump bullets and no Bump Trigger bullet. Examples: a markdown-only change that alters a documented consumer expectation, or a CI workflow change that alters packaged output, requires a bump.

## Bump Type Determination

The overlord determines bump type from:

1. conventional commit type(s)
2. public API, compatibility, runtime, data format, generated output, package, or documented behavior impact
3. breaking-change markers such as `!`, `BREAKING CHANGE:`, or actual compatibility impact

| Commit / impact | Increment |
|---|---|
| `feat` with backward-compatible public capability | MINOR |
| `feat!` or `BREAKING CHANGE:` | MAJOR |
| `fix` / `bugfix` without breaking change | PATCH |
| `refactor` without public compatibility impact | PATCH |
| `refactor!` | MAJOR |
| `chore` / `docs` / `test` / `ci` without artifact impact | No bump |

Ask the user before delegating version edits when the change matches more than one row of this table, or no row. A change matches a row when both:

- the dominant row across all commits on the working branch since it diverged from `<base>`, as `hivemind:bump-type` computes it, is that row, and
- the row's impact condition holds: for the MAJOR, MINOR and PATCH rows, the change satisfies at least one Bump Trigger bullet; for the No-bump row, it matches one or more "No bump is required by default" bullets and no Bump Trigger bullet.

To compute the dominant row, the overlord makes two judgments, then runs the `hivemind:bump-type` engine (`${CLAUDE_PLUGIN_ROOT}/skills/bump-type/scripts/bump-type.sh`):

1. Does the change satisfy any Bump Trigger bullet? Pass `--bump-trigger yes|no`.
2. Does it match one or more "No bump is required by default" bullets? Pass `--no-bump-match yes|no`.
3. Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/bump-type/scripts/bump-type.sh" <base> --bump-trigger <yes|no> --no-bump-match <yes|no>`, where `<base>` is the resolved base branch from `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (Framework Defaults).

Act on the engine's `verdict`:

- `bump_required`: a bump is required; the increment is the reported `bump_type`.
- `no_bump`: no bump is required.
- `ask_user`: the change matches more than one row or no row (a dominant row whose impact condition fails counts as no row); ask the user before delegating version edits.
- exit 1 with `blocker: <reason>` on stderr: surface the blocker; do not hand-compute the dominant row instead.

The engine is the single source for the revert pre-pass, the per-commit row mapping, and the dominant-row precedence; it reads commits NUL-separated. Do not restate or hand-apply those rules.

## Bump Execution

The overlord delegates version and release file edits to drone. A bump ships in the same PR as the triggering change unless the user explicitly directs otherwise.

Project docs must define the exact files to update atomically, such as the canonical version file, changelog or release notes, package or artifact metadata, documentation mirrors, and release validation files. Every artifact has one canonical version source; mirrors are informational and kept in sync.

If `CLAUDE.md` lists no artifact files for a triggered bump, the overlord stops and asks the user before delegating any version edit. The drone must not infer artifact files.

## CHANGELOG / Release Notes

Each versioned artifact keeps release notes or a changelog unless `CLAUDE.md` defines another release documentation mechanism. Recommended Keep a Changelog sections: Added, Changed, Deprecated, Removed, Fixed, Security.

When bumping, convert pending unreleased entries into a dated release section. Unless `CLAUDE.md` says how to reset the unreleased section, reset it to:

```markdown
## [Unreleased]

### Added

### Changed

### Fixed
```

## Tags

Tags are created per the project release workflow. Project docs must define manual vs CI-created tags, tag format, the prefix per artifact when several exist, annotated vs lightweight, and timing relative to publish or deploy. Recommended formats: `vX.Y.Z` for a single artifact, `<artifact-prefix>/vX.Y.Z` for several.
