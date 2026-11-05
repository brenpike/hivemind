---
name: record-state-result
description: Records a state outcome in the run ledger, validates the transition and advances state.current. Use after a state ends.
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/record-state-result/scripts/record-state-result.sh" *)
  - Read(~/.claude/plugins/cache/brenpike/hivemind/**)
  - Edit(.hivemind/runs/.record-inputs-*.json)
shell: bash
---

# Record State Result

Record the current workflow state's outcome in the run ledger, append a ledger event,
validate the transition against the workflow definition, and advance `state.current`
to the legal next state. The engine is the committed script
`${CLAUDE_PLUGIN_ROOT}/skills/record-state-result/scripts/record-state-result.sh`; this
body authors one JSON inputs file and runs the script once. The script reads the
allowed-result set from the workflow definition; the model never supplies it.

Rules: ADR-0018 §A (ledger and definitions are JSON), §C (engine is the committed
script), §I (the engine hard-rejects a workflow id/version mismatch and exposes no
rebind). The overlord resume-on-start gate owns the two version-skew doors (start
fresh / proceed intent-driven); the engine op for both is `hivemind:mark-intent-fallback`.

## Required Inputs

The caller resolves and passes these; the skill does not invent them.

- `run_id`: the run identifier (from `init-run-ledger`). The engine derives the ledger
  (`<git-root>/.hivemind/runs/<run_id>/state.json`) and the workflow definition (the
  ledger's `run.workflow` in the script's own packaged `workflows/` dir); the caller
  passes no ledger or workflow path.
- `state`: the state the run is in (must equal `ledger.state.current`).
- `result`: the named outcome (must be a legal transition key under that state).
- `summary`: human-readable summary; untrusted, stored exactly.
- `outputs` (optional): a JSON object of named outputs; untrusted, stored as data.
- `plan_steps` (optional): cerebrate's plan `steps` as a JSON array; untrusted, stored
  as data. Pass it when recording any cerebrate planning state result (§A below).
- `plan_path` (optional): path to the cerebrate directive; untrusted, stored exactly.

## The §A Plan-Steps Seam

Cerebrate's plan `steps` arrive as YAML; the ledger is JSON, with no maintained
converter. The primary, live writer of `plan.steps` is here, at record time: the
caller inits the ledger before any cerebrate planning state runs. When recording any
cerebrate planning state result (`plan` / `review_remediation_plan` /
`review_remediation_plan_postpr` / `brood_plan`), reformat cerebrate's YAML `steps`
into a JSON array as `plan_steps` (and optionally `plan_path`) in the inputs file; the
script sets `.plan.steps` (and `.plan.path`). When those keys are absent (missing or
null), `.plan.*` is left untouched, never clobbered to `[]`. `init-run-ledger`'s
`plan_steps` only seeds a child/resume run (default `[]`; see that skill's §A
Plan-Steps Seam). `outputs` is the event's free-form object, never a plan-steps
writer.

Recording any cerebrate planning-state result also advances the engine-owned
monotonic plan epoch (`.plan.epoch`), and every appended event, for any state, is
stamped with the current `plan_epoch`. The caller supplies nothing for it.

## Inputs JSON

The script owns the deterministic read -> validate -> mutate -> atomic-write; the
navigator authors one JSON inputs file and passes its path as the one positional
argument. The script first checks the whole inputs file against its contract (one
JSON object; the field rules below), on the intact JSON values, before it reads any
field or opens the ledger. Shape:

```json
{
  "run_id": "<required> run identifier; the engine derives the ledger and the workflow definition from it. No path is accepted.",
  "state": "<required> state the run is currently in (must match ledger.state.current)",
  "result": "<required> named outcome to record (must be a legal transition key)",
  "summary": "<required> human-readable summary (UNTRUSTED, stored exactly)",
  "outputs": {},
  "plan_steps": [],
  "plan_path": "<optional> path to the cerebrate directive (sets plan.path)"
}
```

Field rules (all checked by the one whole-file contract check, in this order):
- Absent: a key that is missing or `null` is absent. `""` is present.
- `run_id`, `state`, `result` are required names: 1 to 255 of `A-Z a-z 0-9 . _ -`, not
  `.` or `..`. `run_id` is a single safe path component and the only identity the
  caller supplies.
- `summary` is a required string, not empty. Stored exactly: no byte is lost,
  including a trailing line feed.
- `outputs` is optional; when present it must be a JSON object, recorded verbatim
  (absent gives `{}`). `outputs.completed_steps`, when present, must be an array and
  is authorized only per check 11 below.
- `plan_steps` is optional (sets `.plan.steps`; absent leaves `.plan.*` untouched);
  when present it must be a JSON array. Every entry must be an object whose `id` is a
  required step id (1 to 64 of `A-Z a-z 0-9 . _ -`), and every `depends_on` entry
  (when present, `depends_on` must be an array) likewise a step id. A `null` entry
  fails. `.`/`..` are not rejected (step ids never become path components).
- `plan_path` is optional (sets `.plan.path`; absent leaves it untouched); when
  present it is a string, stored exactly.
- A failure is one blocker `record-state-result inputs file: <position>: <problem>`.
  The position is the dotted path with `[N]` indexes (for example
  `plan_steps[2].depends_on[0]`); the problem is a fixed phrase. A blocker never names
  the value.
- Every value is data. None is interpolated into generated shell command source.

The script validates, in order, all before any write:

1. The whole inputs contract (field rules above).
2. The ledger at the derived `<git-root>/.hivemind/runs/<run_id>/state.json`
   (`git rev-parse --show-toplevel`; outside a git checkout → blocker) must exist and
   be exactly one JSON object.
3. `ledger.run.id == run_id`.
4. The whole ledger meets its contract (`run.id`, `run.workflow`, `state.current`
   required names; `run.workflow_version` a required whole number; blocker
   `record-state-result ledger: <position>: <problem>`). Then the definition is
   derived from `run.workflow` in the script's self-located packaged `workflows/`
   dir (`BASH_SOURCE` + `pwd -P`, independent of `${CLAUDE_PLUGIN_ROOT}` and of any
   caller value).
5. `definition.id == ledger.run.workflow` (binding guard).
6. `definition.version == ledger.run.workflow_version` (binding guard). There is no
   rebind and no deterministic-resume door: the engine never reconciles skew.
7. `ledger.state.current == state`.
8. `state` exists in `definition.states` (state existence, not version skew).
9. `result` is a key under `states.<state>.transitions`, and its `next_state` must be
   declared in `definition.states`.
10. Plan-write authorization: if `plan_steps` or `plan_path` is present (non-null),
    the state must be a cerebrate planning state
    (`states.<state>.agent == "hivemind:cerebrate"`: `plan` / `review_remediation_plan`
    / `review_remediation_plan_postpr` / `brood_plan`). Key presence alone authorizes
    no plan write.
11. Producer authorization: if `outputs` carries a present, non-null `completed_steps`,
    the state must be a wave-producing agent state (`states.<state>.type == "agent"`,
    `states.<state>` declares `allowed_agents`, and `"hivemind:cerebrate"` is not in
    it, from the packaged definition). Key presence alone authorizes no credit.

Any failure exits 1 with a blocker and leaves the ledger byte-unchanged.

Then it appends the event and updates `state.previous`/`state.current`/`state.status`,
`run.updated_at`, `run.status` if `next_state` is terminal, and `plan.steps` /
`plan.path` when present (non-null). Terminal `run.status` mapping (enum
`running|complete|blocked|cancelled`): `complete`→`complete`, `blocked`→`blocked`,
`cancelled`→`cancelled`, the human-intervention terminals (`user_input_required` /
`review_rejected` / `review_exhausted`)→`blocked`, never masked as success, and any
other done-terminal (e.g. `hatchery_monitor`, `review_window_elapsed`)→`complete`.
Every write is temp-write + atomic rename.

## Procedure

1. **Build the inputs object** in your reasoning from the Required Inputs. When
   recording a cerebrate planning state result, include `plan_steps` (and `plan_path`
   if known) per §A. Each untrusted value (`summary`, `outputs`, `plan_steps`,
   `plan_path`) is structured JSON data, never spliced into command source.

2. **Write the inputs file** with the Write tool, per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern):
   `file_path` = `.hivemind/runs/.record-inputs-<token>.json`, where `<token>` is new for each
   invocation (a UTC timestamp plus a random part, such as `20260601T014132Z-a1b2c3`);
   `content` = the JSON object from step 1. No cleanup is needed.
   If the Write call does not succeed, stop blocked per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).

3. **Execute the script** with one Bash call, passing the inputs file path:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/record-state-result/scripts/record-state-result.sh" .hivemind/runs/.record-inputs-<token>.json
   ```
   Execute (do not Read) the script.
4. **Interpret the result.** Exit 0: the script printed YAML routing lines on stdout:
   ```yaml
   previous_state: <state>
   result: <result>
   current_state: <next_state>
   ledger: <path>
   state_definition: <compact JSON of next_state from the packaged definition>
   ```
   Advance only to `current_state` and execute it as `state_definition` defines it,
   with no read of the workflow definition file. Exit 1: the script printed
   `blocker: <reason>` on stderr and the ledger is byte-unchanged; surface it and stop.

## Pointers

- Execute (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/record-state-result/scripts/record-state-result.sh`.
- Ledger schema: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

## Silence Discipline

Follow `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Silence Discipline). The step 2 Write
is the inputs-file Write; the procedure ends at the step 3 Bash call, which performs every
atomic ledger write. Exit 0: the caller advances to `current_state`, which the
`state_definition` line defines. Exit 1: the ledger is unchanged.

## Do Not

- supply or guess the allowed-result set.
- advance to any state other than the `current_state` the script returns.
- mutate the ledger by hand or with any tool other than this script. The version-skew
  intent-fallback write and the start-fresh stale-run closeout go through
  `hivemind:mark-intent-fallback`, never by hand.
- use the Write tool for anything other than the `.hivemind/runs/.record-inputs-<token>.json`
  inputs file.
- author the inputs file by any transport other than the Write tool; see
  `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
- commit, push, or open a PR.
- Read or reconstruct the script body; invoke it with the documented inputs file path.
