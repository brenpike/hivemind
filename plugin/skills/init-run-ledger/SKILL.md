---
name: init-run-ledger
description: Creates the run ledger `.hivemind/runs/<run-id>/state.json` for this overlord instance. Use when starting a new run.
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/init-run-ledger/scripts/init-run-ledger.sh" *)
  - Read(~/.claude/plugins/cache/brenpike/hivemind/**)
  - Edit(.hivemind/runs/.init-inputs-*.json)
shell: bash
---

# Init Run Ledger

Create the run ledger for the current overlord instance. The engine is the committed
script `${CLAUDE_PLUGIN_ROOT}/skills/init-run-ledger/scripts/init-run-ledger.sh`; this
body builds the inputs file and runs the script once. The ledger is JSON
(`<checkout-root>/.hivemind/runs/<run-id>/state.json`, anchored to the git checkout
root) per `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

Rules: ADR-0018 §A (ledger is JSON); §C (engine is the committed script).

## Required Inputs

The caller resolves and passes these; the skill does not invent them.

- `workflow`: the selected workflow id (for example `standard-delivery`).
- `user_request`: the raw user request; untrusted data, stored exactly.
- `normalized`: the caller's normalized summary of the request, stored exactly.

The caller supplies no `workflow_version` or `start_state` and reads no workflow
definition file: the script derives both from the packaged definition and prints the
start state with its definition (Procedure step 4).

Optional (brood child / id control):

- `parent_kind`: `none | brood` (default `none`).
- `parent_run_id`, `parent_brood_id`, `parent_strain_id`, `parent_manifest`: required
  for the `brood` variant. `parent_brood_id` is the canonical brood id, the GUID
  `spawn-brood` generates (`brood-<uuidv4>`), persisted verbatim into
  `.parent.brood_id` so the child ledger reconciles with the manifest.
- `suggested_run_id`: caller-suggested run id, used verbatim. An unsafe value is a
  blocker, never a silent fallback to a derived id. Absent gives the derived id.
- `plan_steps`: cerebrate's plan `steps` as a JSON array, the child/resume seed for
  `ledger.plan.steps` (see §A); untrusted, stored as data. Default `[]`.
- `plan_path`: path to the cerebrate directive, the child/resume seed for
  `ledger.plan.path`. Default `null`.

### The §A Plan-Steps Seam

Cerebrate's plan `steps` arrive as YAML; the ledger is JSON, with no maintained
converter. `plan_steps` / `plan_path` here only seed a child/resume run that already
has the steps in hand: the caller inits the ledger before the `plan` (cerebrate) state
runs, so a fresh root run has none. The primary, live writer of `plan.steps` is
`hivemind:record-state-result`, at record time (see that skill's §A Plan-Steps Seam).

## Inputs JSON

The script owns the deterministic create-and-write; the navigator authors one JSON
inputs file and passes its path as the one positional argument. The script first
checks the whole inputs file against its contract (one JSON object; the field rules
below), on the intact JSON values; nothing else is read or created until that passes.
Shape:

```json
{
  "workflow": "<required> selected workflow id",
  "user_request": "<required> raw user request (UNTRUSTED, serialized only)",
  "normalized": "<required> caller's normalized summary",
  "parent": {
    "kind": "none | brood",
    "run_id": "<required when kind=brood> parent run id",
    "brood_id": "<required when kind=brood> canonical brood id brood-<uuidv4>, persisted verbatim",
    "strain_id": "<required when kind=brood> strain id",
    "manifest": "<required when kind=brood> manifest path"
  },
  "suggested_run_id": "<optional> caller-suggested run id, used verbatim; a name, else blocker",
  "plan_steps": [],
  "plan_path": "<optional> path to the cerebrate directive (seeds plan.path)"
}
```

Field rules (all checked by the one whole-file contract check, in this order):
- Absent: a key that is missing or `null` is absent. `""` is present.
- `workflow` is a required name: 1 to 255 of `A-Z a-z 0-9 . _ -`, not `.` or `..`.
- `user_request`, `normalized` are required strings, not empty. Stored exactly: no byte
  is lost, including a trailing line feed.
- `workflow_version` and `start_state` are not caller fields: the script takes them
  from the packaged definition's `version` and `start`. An inputs file that still
  carries them (a legacy caller) is checked against the definition, and a mismatch is
  a blocker. `workflow_version`, when supplied, is a whole number of 0 or more (a JSON
  number, never a string); `start_state`, when supplied, is a name.
- `parent` is optional (an object); `parent.kind` is `none` or `brood`, default `none`.
  `parent.run_id` and `parent.manifest` are strings; `parent.brood_id` is 1 to 255 of
  `A-Z a-z 0-9 . _ : -` (`:` is tolerated only for the retired timestamp form);
  `parent.strain_id` is a name. When `parent.kind` is `brood`, all four are required
  (the brood-parent contract, checked after the first).
- `suggested_run_id` is optional; when present it is a name. An unsafe one is a
  blocker.
- `plan_steps` is an optional JSON array, default `[]`. Every entry must be an object
  whose `.id` is a required step id (1 to 64 of `A-Z a-z 0-9 . _ -`); every
  `.depends_on` entry (when present, `.depends_on` must be an array) must likewise be
  a step id. A `null` entry fails. Any unsafe id is a blocker and no run dir is
  created.
- `plan_path` is an optional string, default `null`. Stored exactly.
- A failure is one blocker `run-ledger inputs file breaks its contract: <position>: <problem>`.
  The position is the dotted path with `[N]` indexes (for example `plan_steps[2].id`);
  the problem is a fixed phrase. A blocker never names the value.
- Every value is data. None is interpolated into generated shell command source.

Run-id derivation: `brood` -> `<brood-id>--<strain-id>` (`.parent.brood_id` keeps the
canonical value); else `suggested_run_id` verbatim when present; else
`<utc-timestamp>-<workflow-id>`. The composed id must still be 1 to 255 of
`A-Z a-z 0-9 . _ -` and not `.` or `..`; a joined brood id over 255 is a blocker that
names no value.

## Procedure

1. **Build the inputs object** in your reasoning from the Required Inputs. Each
   untrusted value (`user_request`, `normalized`, any `plan_steps` text) is structured
   JSON data, never spliced into command source. Leave out `workflow_version` and
   `start_state`.

2. **Write the inputs file** with the Write tool, per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern):
   `file_path` = `.hivemind/runs/.init-inputs-<token>.json`, where `<token>` is new for each
   invocation (a UTC timestamp plus a random part, such as `20260601T014132Z-a1b2c3`);
   `content` = the JSON object from step 1. No cleanup is needed.
   If the Write call does not succeed, stop blocked per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).

3. **Execute the script** with one Bash call, passing the inputs file path:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/init-run-ledger/scripts/init-run-ledger.sh" .hivemind/runs/.init-inputs-<token>.json
   ```
   Execute (do not Read) the script. Before creating the run dir it reads the packaged
   `workflows/<workflow>.json` in its self-located `workflows/` dir (it must exist),
   takes `workflow_version` from `.version` and the start state from `.start`, and
   reads that state's definition from `.states`. A missing definition, an undeclared
   start state, or a mismatched legacy `workflow_version` or `start_state` is a
   blocker raised early, leaving no orphan run dir.

4. **Interpret the result.** Exit 0: the script printed YAML routing lines on stdout:
   ```yaml
   run_id: <id>
   ledger: <checkout-root>/.hivemind/runs/<id>/state.json
   current_state: <start state>
   state_definition: <compact JSON of the start state from the packaged definition>
   ```
   The run dir is anchored to the git checkout root (`git rev-parse --show-toplevel`),
   not the CWD, and init must run inside a git checkout. Proceed with that ledger and
   execute `current_state` as `state_definition` defines it, with no read of the
   workflow definition file. Exit 1: the script printed `blocker: <reason>` on stderr
   and wrote no ledger; surface it and stop.

## Pointers

- Execute (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/init-run-ledger/scripts/init-run-ledger.sh`.
- Ledger schema: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

## Silence Discipline

Follow `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Silence Discipline). The step 2 Write
is the inputs-file Write; the procedure ends at the step 3 Bash call.

## Do Not

- invent values for `workflow`, `user_request`, or `normalized`; the script exits 1
  with a blocker if any required input is missing.
- read a workflow definition file to find `workflow_version`, `start_state`, or a
  state's definition.
- write the ledger by hand or with any tool other than the script.
- use the Write tool for anything other than the `.hivemind/runs/.init-inputs-<token>.json`
  inputs file.
- author the inputs file by any transport other than the Write tool; see
  `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
- commit, push, or open a PR.
- Read or reconstruct the script body; invoke it with the documented inputs file path.
