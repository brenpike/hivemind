# Brood Ledger Model

Read this file to understand how the brood manifest bridges to per-strain run ledgers: the per-brood JSON `manifest_version: 4` shape (top-level `brood_id` + `created_at` + `hatchery` block, per-strain `run` pointer with `suggested_id` only), the ledger-path derivation from git ground truth, the injected child-task metadata, hatchery read-only monitoring with status-derivation priority (live child-ledger projection, informational-only, never overriding observable status), and the reconciliation concept.

## Format split: manifest JSON, child ledgers JSON

The brood manifest is **JSON** — `ADR-0018 §A format-follows-consumer` now applies to the manifest too, because `brood-status` projects it via `jq` (a machine consumer). A real parser cannot confuse attacker content for structure, which is why the manifest is JSON: this closes the hand-parse injection class (the sed/awk block-scalar/nested-mapping/multiline-description spoofing class that YAML hand-parsing admitted). The per-strain **run ledgers** it points to are also JSON, for the same reason — the deterministic engine reads and writes those with `jq` (see [run-ledger-schema.md](${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md)).

The child-task `task.md` preamble and the inter-agent contract embedded in it **stay YAML** — that is an agent-to-agent document, not a machine-parsed artifact, and `ADR-0018 §A` continues to govern it separately. Only the manifest artifact flipped; not all brood YAML flipped.

The manifest is the registry and coordination artifact. It is NOT the source of truth for child workflow state — that lives in each child's run ledger.

## Per-brood layout (`.hivemind/broods/<brood-id>/`)

Each brood owns a DISJOINT directory `.hivemind/broods/<brood-id>/{manifest.json,inputs.json}` under the SPAWNING checkout root (`git rev-parse --show-toplevel`) — for the top-level hatchery that IS the main checkout; for a nested hatchery it is that child's worktree, where `<brood-id>` is the machine-generated `brood-<uuidv4>` (full decision in ADR-0021). The singleton `.hivemind/brood/manifest.json` is gone. The hatchery enumerates every discovered brood — running and terminal alike — via the committed deterministic discovery script `${CLAUDE_PLUGIN_ROOT}/skills/brood-status/scripts/brood-discover.sh`, which globs `.hivemind/broods/brood-*/manifest.json` anchored to the current checkout root (`git rev-parse --show-toplevel`) and emits the lexicographically-sorted manifest paths (ADR-0020; the glob was moved out of inline navigator prose). Each discovered brood is shown with its status. Because discovery anchors to the current checkout (the same anchor spawn-brood writes against), nested broods are visible at each hatchery level: each level sees its direct children, no tree-walk. The brood-id also namespaces each strain's branch (`strain/<brood-id>/<short>`), worktree (`.claude/worktrees/<brood-id>/<short>`), and tmux session (`<brood-id>-<short>`), so concurrent same-checkout broods never collide. There is no liveness guard and no lock — per-brood isolation replaces both.

## Manifest extension (`manifest_version: 4`)

The manifest is JSON (`manifest_version: 4`, integer), written to a temp file under the per-brood state dir and `mv`'d into place atomically. The shape carries top-level `brood_id` (the generated GUID) and `created_at` (UTC ISO-8601), a `hatchery` block (the dispatching coordinator's run metadata), and a per-strain `run` block carrying ONLY `suggested_id` and `workflow_hint`. All values are emitted via `jq -nc`/`jq -s` with every untrusted value bound as a `--arg`, so attacker content is structurally confined to string values — it cannot become sibling keys or alter manifest topology.

```json
{
  "manifest_version": 4,
  "brood_id": "brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f",
  "created_at": "2026-06-01T22:10:00Z",
  "base": "main",
  "hatchery": {
    "run_id": "brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f-hatchery",
    "ledger": ".hivemind/runs/brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f-hatchery/state.json",
    "workflow": "hatchery-dispatch"
  },
  "overlap_risk": "low",
  "overlap_details": "No shared file scopes detected.",
  "strains": [
    {
      "name": "api",
      "description": "Implement the API slice.",
      "worktree_path": "/repo/.claude/worktrees/brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f/api",
      "branch": "strain/brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f/api",
      "tmux_session": "brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f-api",
      "status": "running",
      "pr": null,
      "merged": false,
      "rebased_after": [],
      "run": {
        "suggested_id": "brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f--api",
        "workflow_hint": "standard-delivery"
      }
    }
  ],
  "merge_order": []
}
```

Field semantics: top-level `brood_id` is the generated GUID `brood-<uuidv4>` and `created_at` is the UTC instant the manifest was written; the per-strain `branch` is DERIVED (`strain/<brood-id>/<short>`, the spawn-time scratch ref) and is display/context only on the read side; `worktree_path` is the read side's exact-match worktree LOOKUP KEY (it is matched as a string against git's worktree-path set, never consumed as a path anchor; the read side gates it through the path-SELECTOR value-class, which PERMITS a `..` directory-name substring — validity is git-set membership — while still rejecting framing/command-sub/leading-dash/empty, so a legitimate worktree under a `..`-bearing dir name is located rather than false-rejected); and the manifest records NO ledger path — the read side derives it from git ground truth, so recording it would be redundant manifest-path trust. `run.suggested_id` is the lineage reconciliation key.

Field derivation (emitted by `spawn-brood.sh` via `jq -nc` per strain then `jq -s` to fold the array, all untrusted values bound as `--arg`):

- `brood_id` — generated internally as `brood-<uuidv4>`; any caller-supplied value is ignored.
- `created_at` — UTC ISO-8601 instant the manifest was written.
- `hatchery.run_id` — overlord-supplied, or defaults to `<brood_id>-hatchery`.
- `hatchery.ledger` — `.hivemind/runs/<hatchery.run_id>/state.json`, anchored to the coordinator checkout root.
- `hatchery.workflow` — overlord-supplied, or defaults to `hatchery-dispatch`.
- `run.suggested_id` — `<brood-id>--<short>`, where `<short>` is the strain name sanitized to `[a-z0-9-]`.
- `run.workflow_hint` — an OPTIONAL, NON-BINDING suggestion (overlord-supplied per strain, default `standard-delivery`); the child's own `hivemind:route-workflow` makes the actual selection.

None of these fields point at a ledger the hatchery creates — they are pointers only. The child creates its own ledger; the hatchery creates only its own. The child still receives its suggested ledger PATH in the injected `task.md` (below) so it knows where to initialize its own ledger; that path is no longer recorded in the manifest.

## Ledger-path derivation (read side, ground-truth-anchored)

`brood-status` does NOT trust the manifest `worktree_path` as a path anchor. It parses `git worktree list --porcelain` into a SET of git-reported worktree absolute PATHS and selects each strain's REAL worktree using the manifest's per-strain `worktree_path` ONLY as an exact-match lookup KEY against that set — the manifest value is never consumed as a path, only ever compared as a string against git's trusted set. That selector is gated through the path-SELECTOR value-class, which PERMITS a `..` directory-name substring (validity is git-set membership, not a traversal check) while still rejecting framing/command-sub/leading-dash/empty, so a legitimate worktree under a `..`-bearing dir name is located. The ledger is then derived as:

```text
<git-worktree>/.hivemind/runs/<suggested_id>/state.json
```

where only `<suggested_id>` is manifest-sourced (gated as a strict single-component identifier — no slash). The full containment chain is `CHECKOUT_ROOT ⊇ git-worktree ⊇ ledger`: a git-reported worktree outside the checkout fails closed, and the ledger leaf must sit beneath that worktree. A `worktree_path` that matches no live worktree selects nothing (fail-closed → `MISSING`). A tampered manifest path can no longer redirect the bounded reader, because no manifest path is consumed as an anchor (ADR-0021, ADR-0019 amendment).

**Worktree PATH is the lookup key; `branch` is display/context only.** The lookup keys on the per-strain `worktree_path`, gated through the path-SELECTOR value-class (PERMITS a `..` directory-name substring since the value is matched against git's set and never traversed; still rejects framing/command-sub/leading-dash/empty). The worktree PATH is STABLE across a child branch switch — a brood child boots on the spawn-time scratch ref `strain/<brood-id>/<short>` and then derives its own compliant `<type>/<slug>-<token>` working branch via `hivemind:create-working-branch` (off `base`), switching the worktree HEAD — and the child opens its PR from THAT derived branch, leaving the manifest `branch` stale. Path-keying is immune to that switch because the worktree path never moves. The manifest `branch` field is recorded and emitted as the display `branch` column, but it is not the selector. Two consequences of path-keying: a **detached-HEAD** worktree (which carries no `branch refs/heads/...` line) is located, since every porcelain record has a `worktree` line; and a path key cannot collide — git guarantees worktree-path uniqueness. A `bare` repo record is excluded from the selectable set. `manifest_version` is 4; both `worktree_path` and `branch` fields are recorded.

**The PR probe keys on the worktree's git-reported LIVE branch, not the display `branch`.** The worktree LOOKUP keys on `worktree_path`, which makes the manifest `branch` column display-only, but the PR probe still needs a branch to query (`gh pr list --head <branch>`). It keys that probe on the worktree's git-reported LIVE branch — the `branch refs/heads/<name>` line of the SAME porcelain record the path lookup selected, captured in parallel with the path set and emitted as the last projector field (`live_branch`, index 10). This closes post-switch PR-head drift: after a child derives its compliant working branch and opens its PR from it, the manifest `branch` is the stale scratch ref, so `gh pr list --head <scratch>` finds nothing and the strain falsely derives `failed (session ended, no PR)`. Keying on the live branch follows the worktree HEAD onto the derived branch and finds the real PR. The live branch is gated through the same identifier value-class as the display branch (it becomes a `gh --head` argument) and is GROUND-TRUTH metadata only — never a path, never a confinement input; the git path remains the sole confinement anchor. A **detached-HEAD** worktree emits no `branch refs/heads/...` line, so its `live_branch` resolves to `MISSING` → the collector's sentinel gate SKIPS the PR probe → on a dead session it derives `failed (session ended, no PR)`. That is ACCEPTED fail-closed, not a regression: a worktree that never switched onto a derived branch genuinely has no PR head to probe.

## Injected child-task metadata

The task injected into each child strain carries the data-boundary preamble FIRST, then a YAML metadata block whose `task.description` field carries the task description. This is an inter-agent contract, so it is YAML.

```yaml
parent:
  kind: brood
  brood_id: "brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f"
  hatchery_run_id: "brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f-hatchery"
  hatchery_manifest: "/repo/.hivemind/broods/brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f/manifest.json"

strain:
  id: "api"
  name: "api"
  branch: "strain/brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f/api"
  worktree_path: "/repo/.claude/worktrees/brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f/api"

run:
  suggested_id: "brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f--api"
  suggested_ledger: ".hivemind/runs/brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f--api/state.json"
  workflow_hint: "standard-delivery"

instructions:
  - You are a normal hivemind:overlord instance assigned to one strain of a brood.
  - Use the normal workflow router and workflow state machine.
  - Initialize your own run ledger in this worktree.
  - Set parent.kind = brood in your ledger.
  - Do not write the hatchery manifest.
  - Do not write the hatchery run ledger.

task:
  description: |-
    Implement the API slice.
```

`spawn-brood.sh` emits the canonical external-content data-boundary preamble FIRST in the child's injected `task.md`, then this YAML metadata block (whose `task.description` carries the untrusted task description) below it, using the same block-scalar discipline as the manifest emitter (`|-` for exact-value fields, `|` for the free-text `task.description`). The untrusted strain name/branch/worktree-path/description are reproduced at each block-scalar's content indent and stripped of C0 control bytes, so an issue-sourced value cannot break the metadata's YAML validity or the paste boundary.

The child reads this, routes via `hivemind:route-workflow`, initializes its own JSON run ledger (with `parent.kind: brood` populated from this metadata — see run-ledger-schema.md), and executes the selected workflow normally. The child owns its ledger; it does not write the hatchery manifest or hatchery ledger.

## Hatchery monitoring (read-only)

The hatchery monitors a brood by reading only. It never mutates child ledgers, and `brood-status` never writes discovered ledger paths back to the manifest.

`brood-status` derives each strain's status from **external observables + the manifest's static fields + the child run ledger (informational)**. The entire collection loop — multi-brood discovery, per-strain external-observable probing (tmux/branch/PR), child-ledger workflow-state projection, status derivation, and aggregation — lives in committed shell (ADR-0020): a THIN executable entrypoint `${CLAUDE_PLUGIN_ROOT}/skills/brood-status/scripts/brood-status-collect.sh` plus a PURE source-safe library `_shared/brood-status-derive.sh` (status-derivation rule table + bucket classification + per-brood/global aggregation — no I/O). The entrypoint internally calls the committed discovery script (`brood-discover.sh`) and the PURE single-manifest projector (`brood-status-project.sh`), runs the impure tmux/branch/PR probes itself, derives status via the pure lib, and emits ONE JSON document (schema `brood-status-collect/1`). The **navigator** (SKILL.md) is reduced to: run the entrypoint, render markdown from its JSON, write the human summary — it no longer runs any loop, probe, or derivation in prose. This closes the path-splice **structurally**: the entrypoint invokes the projector with inert shell variables (`"$manifest"`, `"$root"`), so untrusted discovered manifest paths AND the operator-controlled checkout root NEVER cross into LLM-authored command source (per security-policy.md / ADR-0019: double-quoting does not neutralize `$(...)`/backtick/`${}` in command SOURCE) — both the brood-id residual and the checkout-root residual close by construction.

Reading child-ledger workflow-state is **LIVE**, implemented in the PURE projector `${CLAUDE_PLUGIN_ROOT}/skills/brood-status/scripts/brood-status-project.sh`. The projector sources four single-responsibility libs: `_shared/allowlist.sh` (floor-at-input value-class gate), `_shared/manifest-json.sh` (jq-based JSON field extraction), `_shared/ledger-project.sh` (jq scalar projection + validation), and `_shared/containment.sh` (path confinement). It projects exactly two scalars per strain: `run.status` (validated against the exact enum `running|complete|blocked|cancelled`) and `state.current` (validated against `^[a-z0-9_]+$`, length ≤ 64). Values that are absent yield the fixed token `MISSING`; values that are present but out-of-allowlist or unparseable yield `MALFORMED` — raw bytes are never emitted; every display cell is output-encoded at the emit boundary (escape `|`, strip C0/DEL). The ledger path is derived from **git ground truth**: the strain's REAL worktree comes from `git worktree list --porcelain` keyed by EXACT-MATCH on the manifest `worktree_path` (lookup key only, never consumed as a path — gated through the path-SELECTOR value-class, which PERMITS a `..` directory-name substring (git-set membership is the validation) while still rejecting framing/command-sub/leading-dash/empty), and the ledger is `<git-worktree>/.hivemind/runs/<suggested_id>/state.json` — confined by the `CHECKOUT_ROOT ⊇ git-worktree ⊇ ledger` chain. The manifest `branch` is display/context only and is NOT the selector; a `worktree_path` matching no live worktree is rejected (fail-closed → `MISSING`) and never read. The same porcelain parse also captures each worktree's git-reported LIVE branch (`branch refs/heads/<name>`) into a parallel set keyed by the same path, emitted as the projector's last field (`live_branch`); the collector keys its `gh pr list --head` PR probe on THAT live branch — not the display `branch` — so the probe follows the worktree HEAD onto a child's derived branch and finds the PR it opened there. A detached-HEAD worktree has no live branch → `live_branch` is `MISSING` → the PR probe is skipped (fail-closed). This projection is **informational only**: it populates the `Strain State (claimed)` / `Strain Status (claimed)` display columns but never overrides the observable-derived `Hatchery Status (observed)` column (external observables remain ground truth — ADR-0007).

The hatchery may read:

```text
.hivemind/broods/brood-*/manifest.json   (one per discovered brood, running or terminal; enumerated by the committed brood-discover.sh — glob anchored to git rev-parse --show-toplevel, nested broods visible per level)
git worktree list --porcelain            (ground-truth worktree per strain branch)
tmux session state
git branch existence
PR state
child run ledger (brood-status-project.sh — informational, bounded projection)
```

### Status-derivation priority

When deriving a strain's status, prefer sources in this order:

```text
1. external observables: tmux session, branch existence, PR state (probed on the worktree's git
   LIVE branch — `live_branch`, field 10 — not the display-only manifest `branch`)
2. manifest static fields
3. child run ledger: run.status / state.current (informational — never overrides tier 1 or 2 Status;
   MAY DEMOTE an alive child OUT of `running` to `starting`, but never promotes / never hides a dead session)
```

External observables win because they reflect ground truth. Manifest static fields are the fallback. The child run ledger (tier 3) populates the `Strain State (claimed)` and `Strain Status (claimed)` display columns via `brood-status-project.sh`'s bounded projection, but it is strictly informational — a hostile child cannot hide a runaway session or alter the observable-derived `Hatchery Status (observed)` column through its ledger. The leaf symlink-swap micro-TOCTOU on the child-ledger read is an ACCEPTED BOUNDED RESIDUAL (not structurally closed by per-brood namespacing — per-brood namespacing isolates broods from each other, not the hatchery from its children): it is bounded by a post-read containment re-assert, never-echo-raw projection, and the informational-only contract (ADR-0021 §10; ADR-0019 amendment).

#### Turn-start verification (two independent mechanisms)

Two independent mechanisms address a child that was injected but never started its workflow.

**Mechanism 1 — spawn-time inject verification (spawn-brood).** After all strains are submitted in Pass 2, `spawn-brood` runs a separate Pass 3 in which each strain's turn-start verification executes on its OWN independent per-strain deadline — decoupled from the shared Pass-2 readiness scheduler so one slow child cannot consume another strain's readiness budget. Within its budget, `spawn-brood` polls the child's run-ledger `state.current` for started-evidence; on no started-evidence it resends `send-keys Enter` up to a retry cap. On retry-cap exhaustion with still no started-evidence, the strain is recorded in the manifest with `status: "failed"` (failed-to-launch); `brood-status` renders it via the existing `failed`-precedence rule. This is NOT a new manifest field and `manifest_version` stays 4.

**Mechanism 2 — brood-status liveness projection (independent).** An alive tmux session alone is NOT proof a child started its workflow: a child can have its task pasted into a live session but never submit it, so the session is alive while no run ledger exists yet. To prevent that idle-but-unsubmitted child from masquerading as a healthy `running` strain, the running derivation is GATED on RUN-LEDGER EVIDENCE. The ground-truth started signal is a present, non-`MISSING`/non-`MALFORMED` `state.current` (the child wrote its run ledger). The rule table the derivation library ports is:

```text
| tmux  | PR     | started-evidence (state.current present & non-MISSING/non-MALFORMED) | Status                                            |
| alive | none   | yes                                                                 | running                                           |
| alive | open   | yes                                                                 | running (PR #N open)                              |
| alive | *      | NO                                                                  | starting (session alive, workflow not yet started) |
| dead  | merged | -                                                                  | complete                                          |
| dead  | open   | -                                                                  | blocked (session ended, PR #N still open)         |
| dead  | none   | -                                                                  | failed (session ended, no PR)                     |
```

`starting (session alive, workflow not yet started)` is a DISTINCT, TRANSIENT (non-terminal) status — non-`running`, non-`complete`, and distinct from `failed`. It buckets into `blocked/failed` for the per-brood summary line so the three-bucket count keeps summing to total (it has made no forward progress, so it is counted against completion, never silently dropped).

The `PR` column above reflects the probe on the worktree's git LIVE branch (`live_branch`), so a child that switched onto its derived branch and opened a PR there reads `merged`/`open` on the dead branch (→ `complete`/`blocked`) instead of falsely falling to `failed (session ended, no PR)`. A **detached-HEAD** worktree has no live branch → `live_branch` is `MISSING` → the PR probe is SKIPPED (sentinel gate) → its `PR` column is `none`, so a detached-HEAD DEAD session derives `failed (session ended, no PR)`. That is ACCEPTED fail-closed (a worktree that never switched to a derived branch genuinely has no PR head to probe), no worse than before and never a fabricated/garbage probe.

This is tier-3 child-ledger evidence applied within its informational-only contract: it DEMOTES an alive-but-unstarted child away from `running`, but it NEVER promotes a strain to `complete` and NEVER hides a dead session (the started-evidence gate touches only the alive branch; the dead branch derives `complete`/`blocked`/`failed` from observables regardless of ledger content). A `MALFORMED` `state.current` is fail-closed — it does NOT count as started-evidence, so a corrupt ledger demotes to `starting`, never up to `running`. ADR-0007's invariant that the ledger never OVERRIDES observable status is preserved: an alive session is still observably alive; the ledger only refines whether that alive session reads as `running` or `starting`.

## Reconciliation concept

Before resuming work that touches a brood, the overlord reconciles state against external observables + the manifest's static fields + the child run ledger (informational) — brood manifest presence, tmux sessions alive or dead, worktrees and branches existing, PRs existing, and the bounded `run.status` / `state.current` projection from `brood-status-project.sh`. Child-ledger reading is **live**. The projection is informational only: it informs the display but does not override observable-derived state. Reconciliation is a concept the docs define, not a v1 skill.

A dedicated `reconcile-run` skill is DEFERRED — it is NOT part of v1. In v1, reconciliation is performed by the overlord's resume-on-start judgment using the status-derivation priority above.
