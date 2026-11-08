# Workflow

Branch, commit and PR conventions.

## Branch Taxonomy

| Prefix | Use |
|---|---|
| `feature/` | New capability |
| `bugfix/` | Non-emergency defect |
| `hotfix/` | Urgent production fix |
| `refactor/` | Structure, no behavior change |
| `chore/` | Maintenance |
| `docs/` | Docs only |
| `test/` | Tests only |
| `ci/` | CI/CD |

## Branch Naming

`<prefix>/<short-description>`, or `<prefix>/<ticket>-<short-description>` when a ticket exists: lowercase, words joined by hyphens, no spaces, underscores or extra slashes.

One approved plan = one branch = one PR.

## Commit Messages

Conventional commits, `type(scope): description`, typed per the branch taxonomy: `feat`, `fix`, `hotfix`, `refactor`, `docs`, `test`, `chore`, `ci`. Never mix unrelated changes in one commit.

## Trunk Freshness

Before creating a branch, check trunk is current:

```
git fetch origin <trunk>:refs/remotes/origin/<trunk>
git rev-list --left-right --count <local-trunk>...origin/<trunk>
```

Proceed only when both tab-separated integers it prints are `0`; otherwise the `trunk_stale` row of the decision autonomy table decides.

## Version Bumps

Judge whether a change needs a version bump, and its type, by `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md` (SemVer Rules, Bump Trigger); read those sections when a run reaches that judgment.

## PR Requirements

Open PR only when: plan complete, validation passed, version bump included if required, branch pushed.

Local review gate: if local review ran on the branch, a ready-for-review PR opens only when its last exit reason holds the gate. Gate-holding exits: `clean`, and `diminishing-returns` once its advisory exit is taken. Any other exit holds nothing and stops that PR on every path: workflow script, state machine, or any step outside both. Local review that did not run (not configured, or skipped) neither holds nor blocks the PR.

Loop-cap draft: at a loop cap, only the workflow script opens the PR as a draft whose body says why and lists open findings; validation still passes. Other paths stop.

PR body must include: what changed and why, at the length the change needs; modified paths grouped by plan step; validation status; version and release notes when a bump applies.

## Framework Defaults

- Trunk: `main`
- Merge strategy: squash
- Review: at least one human approval required
- PR target: resolved trunk branch

## Brood Execution

When work splits into independent strains with minimal file-scope overlap, cerebrate may recommend `delivery: brood`. Once the user confirms, the overlord in hatchery mode spawns via `hivemind:spawn-brood`, monitors via `hivemind:brood-status` on demand and reports aggregate status when all strains finish.

Each child, a brood-unaware overlord with one plan, branch and PR, owns its version bumps, merge conflicts and PR ordering.
