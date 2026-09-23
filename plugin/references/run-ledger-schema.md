# Run Ledger Schema

Read this file when initializing, reading, or mutating a run ledger. The run ledger records progress for one overlord instance and is the source of truth for workflow progress — conversation memory is not.

## Path

```text
.hivemind/runs/<run-id>/state.json
```

For a child strain session this path lives inside the child worktree. The ledger is JSON, parsed and written with `jq`. Untrusted fields (`request.raw`, `request.normalized`, child-task text) are written via `jq --arg` for injection-safe serialization. The engine writes via temp-write + atomic rename so a concurrent reader (the hatchery reading a child ledger) never sees a torn file. Ledger ownership is specified under "Run ownership" in [workflow-state-machine.md](${CLAUDE_PLUGIN_ROOT}/references/workflow-state-machine.md).

## Schema

```json
{
  "schema_version": 1,
  "run": {
    "id": "2026-05-30T22-10-00Z-standard-delivery",
    "workflow": "standard-delivery",
    "workflow_version": 1,
    "status": "running",
    "mode": "deterministic",
    "created_at": "2026-05-30T22:10:00Z",
    "updated_at": "2026-05-30T22:10:00Z"
  },
  "parent": {
    "kind": "none",
    "run_id": null,
    "brood_id": null,
    "strain_id": null,
    "manifest": null
  },
  "request": {
    "raw": "",
    "normalized": ""
  },
  "state": {
    "current": "plan",
    "previous": null,
    "status": "running"
  },
  "facts": {
    "branch": null,
    "base": null,
    "pr": null
  },
  "plan": {
    "path": null,
    "current_step": null,
    "steps": []
  },
  "artifacts": {},
  "events": [],
  "blockers": []
}
```

## Field notes

### `schema_version` (integer)

Ledger schema version. Distinct from `run.workflow_version`, which tracks the workflow definition.

### `run.*`

- `id` — run identifier; matches the `<run-id>` directory name.
- `workflow` — selected workflow id (matches a definition under `plugin/workflows/<id>.json`).
- `workflow_version` — the definition `version` at init time. On resume, a mismatch against the on-disk definition triggers the version-skew gate.
- `status` — `running` | `complete` | `blocked` | `cancelled`. Terminal-state mapping when `record-state-result` reaches a declared terminal: `complete`→`complete`, `blocked`→`blocked`, `cancelled`→`cancelled`, the human-intervention terminals (`user_input_required` / `review_rejected` / `review_exhausted`)→`blocked` (stopped, needs attention — never masked as success), and any other done-terminal (e.g. `hatchery_monitor`, `review_window_elapsed`)→`complete`. `review_window_elapsed` is not an intervention terminal: a quiet idle window with no new review arrivals is the normal healthy ending of watching a quiet PR, never "stopped, needs attention". The enum is fixed; intervention terminals reuse `blocked` rather than adding a new value.
- `mode` — `deterministic` (default) or `intent_fallback` (see below). The `hivemind:mark-intent-fallback` skill is the sanctioned writer that flips this to `intent_fallback` at a version-skew resume.
- `created_at` / `updated_at` — ISO 8601 UTC timestamps.

### `parent.*`

Identifies the run's relationship to a brood. The `kind` field selects the variant; see [Parent-block variants](#parent-block-variants). For a `brood` child, `brood_id` holds the brood id — the machine-generated GUID `brood-<uuidv4>` (ADR-0021), persisted verbatim so the child ledger reconciles 1:1 with the coordinator manifest's `brood_id`. The `parent.brood_id` field of the INIT inputs JSON object accepts this value and the init engine derives the filesystem-safe run id as `<brood-id>--<strain-id>`. The GUID carries NO colons (the prior brood-id was a colon-bearing ISO-8601 timestamp), so the colon-to-dash sanitization the init engine previously applied to derive a filesystem-safe stem is now INERT/no-op — a uuidv4 is already a safe path component, and `.parent.brood_id` and the run-path stem are identical.

### `request.*`

- `raw` — the original user request (untrusted; written via `jq --arg`).
- `normalized` — the overlord's summary of the request.

### `state.*`

- `current` — the state the run is in now; must exist in the workflow definition.
- `previous` — the state advanced from, or `null` at start.
- `status` — `running` | `complete` | `blocked` | `cancelled`.

### `facts.*`

Reconciliation anchors derived from git observables: `branch`, `base`, `pr`.

### `plan.*`

- `path` — path to the cerebrate directive, or `null`. Written by the same two writers as `steps`, via the `plan_path` field of each writer's inputs object.
- `current_step` — the step id currently executing, or `null`.
- `steps` — array reformatted from the cerebrate YAML plan block at the §A boundary (no maintained converter). Two writers, each carrying the steps in the `plan_steps` field of its inputs JSON object, validated as a JSON array and bound via `--argjson` in each:
  - **PRIMARY (live):** the `plan_steps` field of the RECORD inputs object (`record-state-result`), passed by the overlord when recording the `plan` (cerebrate) state result. The overlord inits the ledger BEFORE the `plan` state runs, so this record-time write is what populates `plan.steps` for the implement loop on a fresh root run. When the field is absent (missing key or `null`) the engine leaves `plan.steps` UNTOUCHED (never clobbered to `[]`). The engine honors the `plan_steps` / `plan_path` fields ONLY when the recording state is a cerebrate planning state (`states.<state>.agent == "hivemind:cerebrate"` — `plan` / `review_remediation_plan` / `brood_plan`); recording any other state with these fields present is rejected (ledger byte-unchanged), so `plan.steps` is record-time-writable only at cerebrate planning states.
  - **SEED (child/resume):** the `plan_steps` field of the INIT inputs object (`init-run-ledger`), which seeds `plan.steps` at init time for a child/resume run that already has the steps in hand; absent the field it defaults to `[]`.

  Each step's `id` and every entry of its `depends_on` are SAFE-CHARSET-validated against `^[A-Za-z0-9._-]+$` — the same charset class already applied to `run.workflow` / `run_id` (see [security-policy.md](${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md)). The guard is enforced at BOTH write boundaries — `record-state-result` when `plan_steps` is recorded, and `init-run-ledger` when a child/resume ledger seeds `plan.steps` — and is defensively re-checked by the next-wave reader before ids are emitted into routing output. Rationale: step ids are emitted into the next wave's routing YAML, so an unvalidated id in an untrusted seeded ledger is an injection surface; the charset guard makes an unsafe id unrepresentable in a guard-era ledger.
- `epoch` — integer, ENGINE-OWNED. Written ONLY by `record-state-result`, never by a caller-supplied input field. Bumped by 1 on every `plan.steps` replace — i.e. every cerebrate planning-state record (see the PRIMARY writer above). Absent means `0` (pre-epoch ledgers, before this field existed). Consumed by the `completed_steps` wave-marker convention below to scope done-ness to the current plan generation.

### `artifacts` (object)

Free-form named outputs. The hatchery run stores its brood relationship here rather than in `parent` (see [Hatchery run](#hatchery-run)).

### `events` (array)

Append-only event log. One entry per recorded state result.

### `blockers` (array)

Append-only blocker log.

## Event shape

```json
{
  "at": "2026-05-30T22:10:00Z",
  "state": "plan",
  "result": "single",
  "next_state": "git_preflight",
  "summary": "Cerebrate returned a single-delivery plan.",
  "plan_epoch": 0,
  "outputs": {
    "plan_path": ".hivemind/runs/2026-05-30T22-10-00Z-standard-delivery/plan.json"
  }
}
```

`plan_epoch` is a TOP-LEVEL, ENGINE-WRITTEN event field — distinct from the free-form, caller-supplied `outputs` object below. `record-state-result` stamps it on EVERY event it appends, recording the `.plan.epoch` value the ledger held at append time. Because it is engine-written rather than caller-supplied, it cannot be forged or omitted by a caller the way anything under `outputs` can.

`event.outputs` is free-form and recorded verbatim. NO schema change and NO new REQUIRED field is implied by the convention that follows — `event.outputs` stays free-form/optional.

**Convention (proactive-recurrence-origin marker):** on a `root-cluster-suspected` transition, `event.outputs` MAY carry the named origin-marker key (`recurrence_origin`). Its presence distinguishes a proactively-derived zoom-out from a reviewer-returned one. The key's name, values, and absence semantics are defined SOLELY in `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md (### Proactive Zoom-Out Ledger Marker)` — that subsection is the single source; this note does not restate them.

**Convention (open_pr PR identity):** on an `open_pr` transition, `event.outputs` MAY carry the opened PR's identity — `pr` (the PR URL) and `head_ref_oid` (the PR head SHA) — recorded verbatim like `recurrence_origin`. The overlord forwards these from the routing YAML `hivemind:open-plan-pr` returns (`url` → `pr`, `head_ref_oid`). The deferred post-merge decision report derives the run's PR from `event.outputs.pr` — that report is CONFIG-GATED (opt-in via `HIVEMIND_ENABLE_DECISION_REPORT`, OFF by default), so recording these keys does NOT imply a report will fire; the trigger and policy single source is `${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md (## Post-Merge Decision Report Trigger)`. This is additive and free-form — NO schema change and NO new required field.

**Convention (pr-feedback-remediation PR identity):** a `pr-feedback-remediation` run has no `open_pr` state, so on a `pr_branch_preflight` (and/or `intake`) transition `event.outputs` MAY carry the resolved PR's `pr` (URL) and `head_ref_oid` (head SHA), recorded verbatim like the `open_pr` keys above. The overlord records these from the PR it resolves and checks out at `pr_branch_preflight`. The deferred post-merge decision report derives the run's PR from `event.outputs.pr` of EITHER event and is CONFIG-GATED the same way (opt-in via `HIVEMIND_ENABLE_DECISION_REPORT`, OFF by default), single-sourced to `${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md (## Post-Merge Decision Report Trigger)`. This is additive and free-form — NO schema change, NO new required field, and a key/path DISTINCT from `decisions[]`, `recurrence_origin`, and `plan.steps`.

**Convention (decision-journal array):** `event.outputs` MAY carry an OPTIONAL, free-form `decisions[]` array, recorded verbatim like `recurrence_origin`. Each entry carries the fields `ts`, `state`, `situation`, `options`, `tradeoffs`, `rec_strength`, `gate`, `disposition`, `decision`, `rationale`, and `reversible`. The semantics single source — the autonomy posture, the 2x2, the promotion gate, the disposition vocabulary, and these fields — is `${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md (## Decision Journal)`; this note does not restate the 2x2 or promotion-gate mechanics. `decisions[]`, `recurrence_origin`, the `pr` / `head_ref_oid` open_pr keys, and the `plan.steps` plan-steps writers are DISTINCT keys/paths on or around `event.outputs` and do not collide.

**Convention (completed_steps wave marker):** `event.outputs` MAY carry an OPTIONAL, free-form `completed_steps` array, recorded verbatim like `recurrence_origin` — this is the SAME sanctioned free-form `event.outputs` write-path already used by `decisions[]` and `recurrence_origin`, NOT a new ledger schema field and NOT a `facts.*` mutation. `completed_steps` is a JSON array of plan-step id strings (e.g. `["STEP-001","STEP-004"]`), recorded when the overlord records an `implement_step` state result for a completed WAVE. A single-step wave records a `completed_steps` array of length 1 — a strict subset of the multi-step case, not a distinct shape.

This convention is producer-authorized at the write boundary: `record-state-result` honors `outputs.completed_steps` ONLY when the recording state is a wave-producing agent state — `states.<state>.type == "agent"` AND `states.<state>` declares `allowed_agents` AND `hivemind:cerebrate` is NOT a member of that `allowed_agents` set, derived from the packaged workflow definition — any other recording state is rejected (blocker, ledger byte-unchanged), symmetric to the plan-write authorization guard that restricts `plan.steps` persistence to cerebrate planning states. Exactly TWO engines append events to the ledger: `record-state-result`, which enforces the guard above, and `mark-intent-fallback`, which strips `completed_steps` from its fallback event outputs unconditionally; `init-run-ledger` only creates the ledger (`events: []`) and appends nothing. Because every event appender enforces this producer-authorization discipline, an unauthorized `completed_steps` credit for the current epoch is UNREPRESENTABLE in the ledger — so `next-wave.sh` reads `events[].outputs.completed_steps` unconditionally and remains a pure ledger reader, with no workflow-def knowledge of its own.

Done-ness of a plan step is DERIVED from the union of `events[].outputs.completed_steps`, SCOPED TO THE CURRENT PLAN EPOCH ONLY — i.e. events whose top-level `plan_epoch` equals the ledger's current `.plan.epoch` (`//0` for pre-epoch ledgers, preserving identical behavior to the prior unscoped-union reading) — NOT from `plan.steps[].status`, which stays planner-emitted `pending` and is inert for execution purposes, and NOT from an unscoped union across the entire event log. The epoch scope exists because positional `STEP-NNN` ids are reused across plan generations: a `needs_replan` transition replaces `plan.steps` in the same append-only ledger, and an unscoped union would let a prior generation's `completed_steps` credit satisfy a new generation's same-id step, silently skipping it. Keying done-ness by `plan_epoch` makes that cross-generation collision unrepresentable. This split exists because the `record-state-result` engine forbids non-cerebrate plan writes (see [workflow-state-machine.md](${CLAUDE_PLUGIN_ROOT}/references/workflow-state-machine.md) `(### agent)`): only a cerebrate-agent state may persist `plan.steps`, so step done-ness cannot live there without violating that authorization guard. Recording done-ness in events instead leaves the plan-write authorization guard untouched. `completed_steps`, `decisions[]`, `recurrence_origin`, the `pr` / `head_ref_oid` open_pr keys, and the `plan.steps` plan-steps writers are DISTINCT keys/paths on or around `event.outputs` and do not collide. `plan_epoch` is a separate, TOP-LEVEL, engine-written event field — not a free-form `outputs` key, and not part of this distinct-keys-under-`outputs` set.

**Non-change clarifications (so a future reader does not "fix" a non-bug):**

- NO `schema_version` bump is implied by the decision-journal convention — `decisions[]` is a free-form `event.outputs` key, not a required ledger field.
- NO new `run.status` value is introduced — the enum stays `running | complete | blocked | cancelled`. The post-merge report's "awaiting" condition is DERIVED at Resume-On-Start (a PR exists, `event.outputs.decisions[]` carries ≥1 `did-now`/`deferred`/`recorded` entry, and the zero-byte `.decision-report-done` marker is absent), NOT stored. That derived predicate is IDENTICAL whether or not the report is enabled — when `HIVEMIND_ENABLE_DECISION_REPORT` is unset or empty the same awaiting set is derived from the same local ledger reads, with no PR-state check and no report rendered, per `${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md (## Post-Merge Decision Report Trigger)`.
- NO `artifacts.decision_report` ledger marker is used — the post-merge report is CHAT-ONLY (rendered and surfaced to the user, never written to disk). Its idempotency token is the EXISTENCE of a zero-byte `.decision-report-done` marker `touch`ed in the run dir — NOT a `decision-report.md` content file (which no longer exists), and not a ledger field. The marker means "this run will produce no further decision report" — it is written on BOTH paths: already reported, OR suppressed while the report was off. Marker shape is unchanged by that wider meaning: still zero-byte, still the sole idempotency token, still no ledger marker and no schema change.

## Blocker shape

```json
{
  "at": "2026-05-30T22:18:00Z",
  "state": "git_preflight",
  "reason": "trunk is stale",
  "retry": "not_attempted",
  "next": "Ask user whether to update trunk or proceed at risk."
}
```

## Parent-block variants

### None (normal root run)

A standalone interactive, resumed, or analysis run.

```json
{
  "parent": {
    "kind": "none",
    "run_id": null,
    "brood_id": null,
    "strain_id": null,
    "manifest": null
  }
}
```

### Brood (child strain run)

A spawned strain. Populated from the injected child-task metadata; lives inside the child worktree.

```json
{
  "parent": {
    "kind": "brood",
    "run_id": "brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f-hatchery",
    "brood_id": "brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f",
    "strain_id": "api",
    "manifest": "/repo/.hivemind/broods/brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f/manifest.json"
  }
}
```

### Hatchery (coordinator run)

The hatchery is itself a normal root run, so its `parent.kind` is `none`. Its relationship to the brood it dispatched is stored in `artifacts`, not `parent`.

```json
{
  "parent": {
    "kind": "none",
    "run_id": null,
    "brood_id": null,
    "strain_id": null,
    "manifest": null
  },
  "artifacts": {
    "brood": {
      "id": "brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f",
      "manifest": ".hivemind/broods/brood-7f3c9a2e-1b4d-4c8a-9e6f-2a1b3c4d5e6f/manifest.json"
    }
  }
}
```

## Intent-fallback marker

When the deterministic substrate is invalidated (version skew, torn ledger, missing definition, unresolvable `state.current`), the run degrades to intent-driven completion. Transition gating is suspended; the ledger becomes an append-only observability log. The run records the degradation with `run.mode`:

```json
{
  "run": {
    "id": "2026-05-30T22-10-00Z-standard-delivery",
    "workflow": "standard-delivery",
    "workflow_version": 1,
    "status": "running",
    "mode": "intent_fallback"
  }
}
```

The `hivemind:mark-intent-fallback` skill is the sanctioned writer of this marker. It sets `run.mode: intent_fallback`, appends a fallback event to the `events` log, and — when its `close_status` input is supplied — optionally closes the run by setting `run.status` ∈ {`cancelled`, `complete`}. Closeout applies ONLY to a `running` run — the engine rejects closing out an already-terminal run (ledger byte-unchanged). When `close_status` is omitted the run stays `running` and the ledger continues as an append-only observability log.

`abandoned` is NOT a legal `run.status` value — the enum is fixed at `running` | `complete` | `blocked` | `cancelled`. Stale skew-run closeout therefore reuses `cancelled` rather than introducing a new value.

Determinism only ever adds safety and observability; the `intent_fallback` mode guarantees a run is never stranded. See "Intent-driven execution is the universal fallback" in [workflow-state-machine.md](${CLAUDE_PLUGIN_ROOT}/references/workflow-state-machine.md).
