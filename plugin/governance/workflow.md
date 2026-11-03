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

Format: `<prefix>/<short-description>` or `<prefix>/<ticket>-<short-description>`: lowercase, hyphens between words, no spaces, underscores or extra slashes. Include the ticket ID when one exists.

One approved plan = one branch = one PR.

## Commit Messages

Conventional commits: `type(scope): description`, with types matching the branch taxonomy: `feat`, `fix`, `hotfix`, `refactor`, `docs`, `test`, `chore`, `ci`. Do not mix unrelated changes in one commit.

## Trunk Freshness

Before branch creation, verify trunk is current:

```
git fetch origin <trunk>:refs/remotes/origin/<trunk>
git rev-list --left-right --count <local-trunk>...origin/<trunk>
```

The output is two tab-separated integers; both must be `0` to proceed. Otherwise present the user fix-and-continue or proceed-at-risk options.

## Version Bumps

A PR needs a bump when it changes files affecting runtime behavior, public API, compatibility contract, generated or packaged output, distribution metadata, or documented consumer expectation; docs-only, test-only, CI-only, governance-only, changelog-only and markdown-only changes need none unless they alter a documented consumer expectation. Full rules: `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md` (Bump Trigger).

SemVer: **MAJOR** for a breaking change to public API, compatibility, data format, or runtime contract; **MINOR** for a backward-compatible new capability, option, or behavior; **PATCH** for a bug fix or internal refactor with no public impact.

## PR Requirements

Open PR only when: plan complete, validation passed, version bump included if required, branch pushed.

Local review gate: when local review ran on the branch, the PR opens only when the last exit reason it returned holds the gate. The exit reasons that hold the gate are `clean`, and `diminishing-returns` once its advisory exit is taken. Every other exit reason holds nothing, max-iterations-reached included, and stops the PR on every path: the workflow script, the state machine, and any step taken outside both. Local review that did not run, because it is not configured or was skipped, neither holds nor blocks the PR.

PR content: a summary of what changed and why, at the length the change needs; file paths modified, grouped by plan step; validation status; version and release notes when a bump applies.

## Framework Defaults

- Trunk: `main`
- Merge strategy: squash
- Review: at least one human approval required
- PR target: resolved trunk branch

## Brood Execution

When cerebrate finds work splits into multiple independent strains with minimal file-scope overlap, it may recommend `delivery: brood`. The overlord confirms with the user before dispatching, then enters hatchery (coordinator) mode:

1. invokes `hivemind:spawn-brood` to spawn child sessions
2. monitors via `hivemind:brood-status` on demand
3. reports aggregate status when all strains complete

Each child is a standard overlord running a full pipeline, with no brood awareness; "one plan = one branch = one PR" holds per child. Each child handles its own version bumps, merge conflicts and PR ordering, like parallel developers on a team.

A Brood-Plan is distinct from a plan artifact: it holds strain-level descriptions and scope boundaries, while a plan artifact holds implementation steps (STEP-NNN).
