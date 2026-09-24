# Workflow

Branch, commit, and PR conventions. Loaded by overlord only.

## Branch Taxonomy

| Prefix | Use |
|---|---|
| `feature/` | New capabilities |
| `bugfix/` | Non-emergency defects |
| `hotfix/` | Urgent production fixes |
| `refactor/` | Structural improvement, no behavior change |
| `chore/` | Maintenance |
| `docs/` | Documentation only |
| `test/` | Test only |
| `ci/` | CI/CD changes |

## Branch Naming

Format: `<prefix>/<short-description>` or `<prefix>/<ticket>-<short-description>`

Rules: lowercase, hyphens between words, no spaces, no underscores, no extra slashes. Include ticket ID when one exists.

One approved plan = one branch = one PR.

## Commit Messages

Conventional commits: `type(scope): description`

Types match branch taxonomy: `feat`, `fix`, `hotfix`, `refactor`, `docs`, `test`, `chore`, `ci`. Do not mix unrelated changes in one commit.

## Trunk Freshness

Before branch creation, verify trunk is current:

```
git fetch origin <trunk>:refs/remotes/origin/<trunk>
git rev-list --left-right --count <local-trunk>...origin/<trunk>
```

Output: two tab-separated integers. Both must be `0` to proceed. Non-zero = present user with fix-and-continue or proceed-at-risk options.

## Version Bumps

A bump is required when a PR changes files affecting: runtime behavior, public API, compatibility contract, generated/packaged output, distribution metadata, or documented consumer expectation. Full rules: `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md`.

No bump required for: docs-only, test-only, CI-only, governance-only, changelog-only, markdown-only changes (unless they alter a documented consumer expectation).

SemVer:
- **MAJOR** — breaking change to public API, compatibility, data format, or runtime contract
- **MINOR** — backward-compatible new capability, option, or behavior
- **PATCH** — bug fix, internal refactor with no public impact

## PR Requirements

Open PR only when: plan complete, validation passed, version bump included if required, branch pushed.

PR content must include:
- Summary covering what changed and why, at the length the change needs
- File paths modified, grouped by plan step
- Validation status
- Version/release notes when bump applies

## Framework Defaults

- Trunk: `main`
- Merge strategy: squash
- Review: at least one human approval required
- PR target: resolved trunk branch

## Brood Execution

When the cerebrate determines that work decomposes into multiple independent strains with minimal file-scope overlap, it may recommend `delivery: brood`. The overlord confirms with the user before dispatching.

In brood mode, the overlord enters hatchery (coordinator) mode:
1. Invokes `hivemind:spawn-brood` to spawn child sessions
2. Monitors via `hivemind:brood-status` on demand
3. Reports aggregate status when all strains complete

Each child session is a standard overlord running a full pipeline. Children have no brood awareness. The "one plan = one branch = one PR" invariant holds per child session.

Brood-Plan is a distinct artifact from plan artifact. Brood-Plans contain strain-level descriptions and scope boundaries. Plan artifacts contain implementation steps (STEP-NNN).

Version bumps, merge conflicts, and PR ordering are handled independently by each child, same as parallel developers on a team.
