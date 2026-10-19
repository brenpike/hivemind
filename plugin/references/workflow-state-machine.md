# Workflow State Machine Reference

Read this file to understand the declarative workflow substrate: how workflow definitions are shaped, the legal v1 state types, the governing invariant, and the universal fallback. The runtime contract is established in ADR-0018.

## What a workflow definition is

A workflow definition is a declarative JSON file under `plugin/workflows/<id>.json` enumerating one workflow's legal states and named transitions. It is read-only at runtime and parsed by `jq`. It does not execute anything by itself — the engine skills (`hivemind:init-run-ledger`, `hivemind:record-state-result`) read the selected definition and print the current state's definition, which the overlord executes using normal Hivemind delegation rules.

Workflow definitions are JSON (not YAML) because the deterministic engine reads and writes them with `jq`, the required runtime dependency (ADR-0017). `description` fields replace inline comments. All inter-agent and human-read contracts — router I/O, skill I/O, the cerebrate plan block, injected child-task metadata, delegation payloads — stay YAML for readability. No file is read by both `jq` and "only a human."

## WHO/WHAT-not-WHY invariant

A workflow state names WHO acts (an agent, a skill, or an overlord decision) and WHAT named outcomes are legal next. It MUST NEVER encode WHY an outcome was chosen. Every classification, judgment, and edge call lives in the agent or skill the state points to.

INVARIANT: a `decision`-type state lists legal outcome names only; the overlord supplies the "why" from context. A construct like `agent_from: current_step.owner` violates this invariant and is NOT used — bioform selection is a static `allowed_agents` list plus overlord intent (see [Agent states](#agent)).

## Definition format

A workflow definition is a JSON object with these top-level keys:

| Key | Type | Purpose |
|---|---|---|
| `id` | string | Workflow identifier; matches the filename stem. |
| `version` | integer | Definition version; compared against `ledger.run.workflow_version` on resume. |
| `start` | string | The state the run begins in; must exist in `states`. |
| `terminal` | array of strings | Declared final state names. |
| `states` | object | Map of state name to state object. |

Each state object carries a `type` and a `transitions` map (except `terminal` states, which have neither). A `transitions` map keys named outcomes to target state names. Comments are expressed as `description` fields, never `#` lines.

```json
{
  "id": "standard-delivery",
  "version": 1,
  "start": "plan",
  "terminal": ["complete", "blocked", "cancelled"],
  "states": {
    "plan": {
      "type": "agent",
      "description": "Cerebrate produces the directive and delivery shape.",
      "agent": "hivemind:cerebrate",
      "transitions": {
        "single": "git_preflight",
        "brood": "brood_confirm",
        "open_questions": "blocked",
        "blocked": "blocked"
      }
    },
    "complete": { "type": "terminal" },
    "blocked": { "type": "terminal" },
    "cancelled": { "type": "terminal" }
  }
}
```

## V1 state types

Only these five state types are supported in v1:

### `decision`

The overlord derives a named result from context. Carries `owner: overlord`. The outcome names are listed under `transitions`; the reasoning that selects one is intent, not data.

```json
{
  "type": "decision",
  "owner": "overlord",
  "transitions": {
    "ready": "branch",
    "user_decision_required": "blocked",
    "blocked": "blocked"
  }
}
```

### `agent`

The overlord delegates to a named agent. Either a single `agent` field or a static `allowed_agents` array names the legal bioform(s); the overlord picks from `allowed_agents` by intent.

INVARIANT: `agent_from` is NOT a recognized field. Dynamic agent resolution from ledger fields violates the WHO/WHAT-not-WHY invariant. The legal set is always static data in the definition.

Only a cerebrate-agent state (`agent: "hivemind:cerebrate"`) may persist plan steps: the deterministic engine honors `record-state-result --plan-steps` / `--plan-path` ONLY when the recording state's `agent` is `hivemind:cerebrate`, and rejects (ledger byte-unchanged) every other state. This authorizes exactly the cerebrate planning states and derives entirely from the existing `agent` key — no schema field is added.

Executing an `agent` state MAY dispatch N CONCURRENT delegations to bioforms from the static `allowed_agents` set within ONE state execution — a WAVE. This does NOT introduce a new state type and does NOT violate execute-current-state-only (one state execution = one wave; see the looping paragraph under "Deferred state types — NOT in v1" below). The overlord still picks each dispatched step's bioform by intent from the static `allowed_agents` set, per the WHO/WHAT-not-WHY invariant above. Wave membership — which plan steps are dispatched together — is deterministic data derived from the ledger (`plan.steps` plus each step's `depends_on` and file-disjointness against its wave-mates), not a definition field; see [run-ledger-schema.md](${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md) for how completed steps are recorded per wave.

```json
{
  "type": "agent",
  "allowed_agents": ["hivemind:drone", "hivemind:changeling"],
  "transitions": {
    "complete": "checkpoint",
    "blocked": "blocked",
    "needs_replan": "plan"
  }
}
```

### `skill`

The overlord invokes a named `skill`.

```json
{
  "type": "skill",
  "skill": "hivemind:create-working-branch",
  "transitions": {
    "complete": "implement_next_step",
    "blocked": "blocked"
  }
}
```

### `user_gate`

Execution must stop for explicit user input.

```json
{
  "type": "user_gate",
  "transitions": {
    "approved": "spawn_brood",
    "rejected": "blocked",
    "cancelled": "cancelled"
  }
}
```

### `terminal`

A final state. Has no `transitions`. Reaching one updates `run.status` in the ledger.

```json
{ "type": "terminal" }
```

### Deferred state types — NOT in v1

These types are explicitly NOT implemented in v1 and MUST NOT appear in any v1 definition:

- `foreach`
- `subflow`
- `gate`
- `parallel`
- `join`
- `timer`
- `condition`

`parallel`, `join`, and `foreach` explicitly REMAIN deferred and NOT in v1 — this stands even with intra-`agent`-state wave dispatch (see [Agent states](#agent) above). Waves are EXECUTION SEMANTICS layered on the existing `decision` + `agent` + `skill` states — one `agent` state execution fanning out to N concurrent bioform delegations — not new state types added to the five in [V1 state types](#v1-state-types). The v1 deferral of `parallel`/`join`/`foreach` as declared state types STANDS.

Looping is expressed with an explicit `decision` state (e.g. `implement_next_step`) that branches `has_next_step` back to the work state and `all_steps_complete` forward. Each loop iteration drains one WAVE — the ready set of plan steps whose `depends_on` are satisfied and whose file scopes are mutually disjoint — not a single step; a linear plan with no cross-step parallelism opportunity degrades to waves of one, which is indistinguishable from the prior single-step-per-iteration loop. No expression language, no embedded conditionals, no workflow composition engine. These can be revisited after the first deterministic loop is stable.

## Run ownership

A run ledger is owned and mutated only by the overlord instance whose worktree contains it; cross-instance reads (the hatchery reading a child ledger for status) are read-only, enforced by worktree isolation rather than convention — each instance's `.hivemind/runs/` lives in its own working tree; the brood manifest is the sole shared artifact and only the hatchery writes it. See [run-ledger-schema.md](${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md) for the ledger shape and [brood-ledger-model.md](${CLAUDE_PLUGIN_ROOT}/references/brood-ledger-model.md) for the manifest.

## Intent-driven execution is the universal fallback

Whenever the deterministic substrate is unavailable or invalidated — workflow-definition version skew across a plugin upgrade, a torn or missing ledger, a missing definition, or a `state.current` the engine cannot resolve — the overlord degrades to intent-driven completion rather than hard-failing. It reads the ledger for facts, finishes by judgment, and keeps appending events as an observability log with transition gating suspended and the run marked `mode: intent_fallback` (see run-ledger-schema.md). Determinism can only ever ADD safety and observability; it never strands a run. Worst case equals today's pure-intent behavior, never worse.
