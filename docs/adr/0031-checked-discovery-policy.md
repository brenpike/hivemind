# One discovery policy for policy_check.sh: follow symlinks, fail closed on what can't be followed

**Status:** accepted — 2026-09-25

## Context

`tools/policy_check.sh` finds its input files with plain `find` at roughly thirty call sites. POSIX `find` defaults to `-P`, so it never descends into a symlinked directory. Most of these sites also filter with `-type f`, which drops a name-matching symlink before any read or status check ever sees it. A few sites additionally discard `find`'s exit status with `2>/dev/null` or by piping into another command. The net effect: a check's input set can be narrowed silently, ahead of the layer that is supposed to fail closed, and the check still reports green on input it never saw.

CHECK 15 hit exactly this shape first. Its fix (tracked in the repo's recent history, not named here as a live source of current behavior — see `tools/policy_check.sh` and `tests/policy/README.md` for the maintained description) moved CHECK 15's discovery to name-only matching (dropping `-type f`) behind a checked, status-bearing discovery helper, so every name-matching path reaches CHECK 15's read gate. It recorded the missing `-L` — symlinked directories still going undescended — as a residual, because fixing CHECK 15 alone would leave it disagreeing with every other discovery site in the same script, and adding `-L` changes `find`'s error behavior (dangling links, symlink loops) script-wide.

Issue brenpike/hivemind#377 generalized that residual: the input-narrowing pattern is present at roughly thirty sites, not one, and needs a single script-wide decision rather than a per-site patch.

## Decision

`tools/policy_check.sh` adopts one discovery policy for the whole script: **follow symlinks**. Every discovery site uses `find -L` (or the equivalent checked-discovery helper) instead of default `-P`. Anything a followed traversal cannot resolve — a dangling symlink, a symlink loop — surfaces as a finding. It is never a silent skip and never a suppressed `find` exit status.

The policy is implemented once, as a shared checked-discovery helper generalized from CHECK 15's sentinel-status helper, and every discovery call site is routed through it rather than reimplementing `find` invocations locally. The helper is status-bearing: callers can distinguish "found N paths" from "discovery itself failed," and a status-bearing gate classifies each discovered path (files, directories, or raw/unfiltered) so call sites keep the granularity they had before, without reintroducing a second traversal mechanism to get it.

This is a single discovery engine for the script. No check gets a second, separate way to walk the filesystem.

The policy is witnessed by a committed `DISCOVERY` canary: a committed symlinked-directory fixture (proving a symlinked directory is now descended and its contents reach the read gate) and a committed dangling-symlink fixture (proving an unresolvable target surfaces as a finding rather than vanishing), plus a `-P` negative control (proving the canary fixtures would NOT be caught under the old default, so the canary is actually exercising the new policy and not passing by accident).

## Alternatives rejected

| Option | Rejected because |
|---|---|
| Ban symlinks under scanned roots (reject any symlink found, follow none) | Reverses CHECK 15's already-shipped read-through behavior for name-matching symlinks, and forces allowlist entries for the repo's own existing test fixtures that happen to be symlinks. Trades a real gap for a maintenance tax on legitimate fixtures. |
| Hybrid: read file symlinks, reject directory symlinks | Needs a second, separate symlink sweep to distinguish the two cases ahead of the main discovery pass — i.e., two traversal mechanisms doing overlapping work, which is the coupling this decision is trying to avoid. |
| Follow symlinks everywhere, fail closed on the unresolvable (chosen) | — |

## Consequences

- Every `tools/policy_check.sh` discovery site sees the same input set a symlink-following traversal would produce; a symlinked directory or a name-matching symlink can no longer make a check report green on input it never read.
- A dangling symlink or symlink loop under a scanned root is now a loud finding rather than an invisible one.
- **Residual: symlink loops are not witnessed by a committed fixture.** A committed loop under `tests/` would make any `-L` scan over that tree error, which is disruptive to every other test that walks the same directory. The canary instead witnesses status propagation through the nonexistent-root probe (a root that cannot be discovered at all), which exercises the same fail-closed status path without requiring a permanently-broken fixture on disk.
- **Residual: a symlinked directory pointing back inside the scanned root** materializes the same underlying file under two path spellings (the real path and the path through the symlink). An allowlist entry keyed to one spelling does not cover the other. This is not addressed by this decision and is left for a future policy fixture if it becomes a real allowlisting problem.
- **On `core.symlinks=false` checkouts**, the committed symlink fixtures (both the directory fixture and the dangling-link fixture) check out as plain text files containing their target path string, not as symlinks. The canary fails loudly on such a checkout — by design, not as a silent skip — because CI runs on `ubuntu-latest`, where `core.symlinks` is true, and a contributor on a non-symlink-capable checkout needs to know their local run cannot validate this policy rather than have it quietly pass.
- **Sibling scripts are not migrated by this decision.** `tools/validate.sh`, `tools/validate_workflows.sh`, `tools/validate_reports.sh`, and the `tools/test_*.sh` leak probes have the same discovery shape and are tracked separately in brenpike/hivemind#381.
- **Symlinks as shipped content inside `plugin/` are a separate question from discovery.** Whether `tools/policy_check.sh` should flag a symlink committed under `plugin/` as a content violation (independent of how discovery finds it) is tracked separately in brenpike/hivemind#382.

References: `tools/policy_check.sh`, `tests/policy/README.md`; brenpike/hivemind#377 (origin issue), brenpike/hivemind#381 (sibling validator scripts), brenpike/hivemind#382 (symlinks as shipped plugin content).
