# Workflow

Branch, commit and PR conventions. Loaded by overlord only.

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

Proceed only when both tab-separated integers it prints are `0`; otherwise offer the user fix-and-continue or proceed-at-risk.

## Version Bumps

A PR needs a bump when it changes runtime behavior, public API, compatibility contract, generated or packaged output, distribution metadata or documented consumer expectation; a docs-, test-, CI-, governance-, changelog- or markdown-only change needs none unless it alters a documented consumer expectation. MAJOR: breaking public API, compatibility, data format or runtime contract; MINOR: backward-compatible new capability, option or behavior; PATCH: bug fix or internal refactor, no public impact. Rules: `${CLAUDE_PLUGIN_ROOT}/governance/versioning.md` (Bump Trigger).

## PR Requirements

Open PR only when: plan complete, validation passed, version bump included if required, branch pushed.

Local review gate: if local review ran on the branch, the PR opens only when its last exit reason holds the gate. Gate-holding exits: `clean`, and `diminishing-returns` once its advisory exit is taken. Any other exit, max-iterations-reached included, holds nothing and stops the PR on every path: workflow script, state machine, or any step outside both. Local review that did not run (not configured, or skipped) neither holds nor blocks the PR.

PR body: what changed and why, at the length the change needs; modified paths grouped by plan step; validation status; version and release notes when a bump applies.

## Framework Defaults

- Trunk: `main`
- Merge strategy: squash
- Review: at least one human approval
- PR target: resolved trunk branch

## Brood Execution

When cerebrate finds the work splits into independent strains with minimal file-scope overlap, it may recommend `delivery: brood`. The overlord confirms with the user before dispatch, then in hatchery mode:

1. invokes `hivemind:spawn-brood` to spawn child sessions
2. monitors via `hivemind:brood-status` on demand
3. reports aggregate status when all strains complete

Each child is a standard overlord running a full pipeline with no brood awareness, so one plan = one branch = one PR holds per child; it handles its own version bumps, merge conflicts and PR ordering.
