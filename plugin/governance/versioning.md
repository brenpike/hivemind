# Versioning Policy

## Purpose

Generic SemVer workflow for repositories that publish versioned artifacts.

Project-specific package names, artifact paths, version-file locations, changelog locations, tag prefixes, and validation commands live in `CLAUDE.md` or project docs referenced by `CLAUDE.md`.

## Scope

Applies to every independently versioned artifact defined by the project: packages, libraries, applications, plugins, containers, distributable binaries, or similar artifacts.

Each artifact is versioned independently unless project documentation says otherwise.

Internal shared components with no standalone distribution carry no version unless the project defines one. Changes to shared components may require bumps in dependent artifacts if public API, runtime behavior, generated output, package contents, or compatibility contracts change.

## SemVer Rules

This repository follows Semantic Versioning 2.0.0.

Format: `MAJOR.MINOR.PATCH`

| Increment | Trigger |
|---|---|
| MAJOR | Breaking change to public API, compatibility contract, data format, runtime behavior contract, or documented consumer expectation |
| MINOR | Backward-compatible public API, capability, option, behavior, or artifact surface |
| PATCH | Bug fix, internal refactor, or implementation change with no public compatibility impact |

For `0.x.y` artifacts, SemVer permits minor increments for breaking changes. Breaking changes must still include a changelog entry under `Changed` or `Removed` that names the breaking surface (function, type, flag, file, endpoint) and the migration path.

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

Exact bump-trigger paths are project-specific and must be defined in `CLAUDE.md` or referenced project documentation.

No bump is required by default for:

- documentation-only changes
- test-only changes
- CI-only changes
- hivemind/governance changes
- changelog-only maintenance
- markdown-only changes

Project documentation may define additional required or excluded paths. When `CLAUDE.md` does not define bump-trigger paths, this section's lists are exhaustive with the following precedence:

- **Bump Trigger wins on overlap**: if a change matches any bullet in Bump Trigger AND any bullet in "No bump is required by default", a bump is required. The No-bump list applies only when the change matches one or more No-bump bullets AND matches no Bump Trigger bullet.

Examples of overlap that go to bump-required: a markdown-only change that alters a documented consumer expectation (matches `markdown-only changes` AND `documented consumer expectation`); a CI workflow change that alters packaging (`CI-only changes` AND `packaged output`).

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

Ask the user before delegating version edits when the change matches more than one row of the table above, OR matches no row.

A change "matches a row" when both:

- the dominant Bump Type Determination row across all commits on the working branch since it diverged from `<base>`, as computed by `hivemind:bump-type` below, equals the row in question, AND
- the row's impact condition is satisfied:
  - for the MAJOR, MINOR, and PATCH rows: at least one bullet in Bump Trigger above is satisfied by the change
  - for the No-bump row: the change matches one or more bullets in the "No bump is required by default" list above and matches no bullet in Bump Trigger

To compute the dominant row, the overlord makes two judgments and then runs the `hivemind:bump-type` engine (`${CLAUDE_PLUGIN_ROOT}/skills/bump-type/scripts/bump-type.sh`):

1. Decide whether the change satisfies any bullet in Bump Trigger above; pass the answer as `--bump-trigger yes|no`.
2. Decide whether the change matches one or more bullets in the "No bump is required by default" list above; pass the answer as `--no-bump-match yes|no`.
3. Run `bash ${CLAUDE_PLUGIN_ROOT}/skills/bump-type/scripts/bump-type.sh <base> --bump-trigger <yes|no> --no-bump-match <yes|no>`, where `<base>` is the resolved base branch from `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (Framework Defaults).

Act on the engine's `verdict`:

- `bump_required`: a bump is required; the increment is the reported `bump_type`.
- `no_bump`: no bump is required.
- `ask_user`: the change matches more than one row or matches no row (a dominant row whose impact condition above is unsatisfied counts as no row); ask the user before delegating version edits, per the rule above.
- exit 1 with `blocker: <reason>` on stderr: surface the blocker; do not hand-compute the dominant row instead.

The engine is the single source for the revert pre-pass, the per-commit row mapping, and the dominant-row precedence; it reads commits NUL-separated. Do not restate or hand-apply those rules.

## Bump Execution

The overlord delegates version/release file edits to drone.

A bump is included in the same PR as the triggering change unless the user explicitly directs otherwise.

Project-specific documentation must define the exact files to update atomically, such as:

- canonical version file
- changelog/release notes
- package/artifact metadata
- documentation mirrors
- release validation files

Every artifact must have one canonical version source. Mirrors are informational and must be kept in sync.

If `CLAUDE.md` does not list the artifact files for a triggered bump, the overlord stops and asks the user before delegating any version edit. The drone must not infer artifact files.

## CHANGELOG / Release Notes

Each versioned artifact must maintain release notes or a changelog unless `CLAUDE.md` defines a different release documentation mechanism.

Recommended sections follow Keep a Changelog:

- Added
- Changed
- Deprecated
- Removed
- Fixed
- Security

When bumping, convert pending unreleased entries into a dated release section. If `CLAUDE.md` does not specify how to reset the unreleased section, reset it to:

```markdown
## [Unreleased]

### Added

### Changed

### Fixed
```

## Tags

Tags are created according to the project release workflow.

Project documentation must define:

- manual vs CI-created tags
- tag format
- prefix per artifact when multiple artifacts exist
- annotated vs lightweight
- timing relative to publish/deploy

Recommended generic formats:

- single artifact: `vX.Y.Z`
- multiple artifacts: `<artifact-prefix>/vX.Y.Z`
