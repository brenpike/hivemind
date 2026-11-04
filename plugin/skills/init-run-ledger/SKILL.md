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

Create the run ledger for the current overlord instance. The deterministic engine is the
committed script
`${CLAUDE_PLUGIN_ROOT}/skills/init-run-ledger/scripts/init-run-ledger.sh`; this body is a
navigator that builds the inputs file and runs the script once. The
ledger is JSON (`<checkout-root>/.hivemind/runs/<run-id>/state.json`, anchored to the git
checkout root) per
`${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

Rules: ADR-0018 §A (ledger is JSON); §C (engine is the committed script).

## Required Inputs

The caller resolves and passes these; the skill does not invent them.

- `workflow`: the selected workflow id (for example `standard-delivery`).
- `user_request`: the raw user request — UNTRUSTED data, stored exactly.
- `normalized`: the caller's normalized summary of the request, stored exactly.

The caller does not supply `workflow_version` or `start_state` and reads no workflow
definition file. The script derives both from the packaged definition and prints the start
state with its definition (Procedure step 4).

Optional (brood child / id control):

- `parent_kind`: `none | brood` (default `none`).
- `parent_run_id`, `parent_brood_id`, `parent_strain_id`, `parent_manifest`: required for
  the `brood` variant. `parent_brood_id` is the CANONICAL brood id — the GUID `spawn-brood`
  generates (`brood-<uuidv4>`, asserted `^brood-[0-9a-f-]+$`; ADR-0021). It is persisted
  VERBATIM into `.parent.brood_id` so the child ledger reconciles with the manifest. The
  internal colon->dash sanitization is retained only as defensive tolerance for the retired
  timestamp-shaped brood id and is a no-op on the GUID form, which is already
  filesystem-safe. `parent_strain_id` must be a name (1 to 255 of `A-Z a-z 0-9 . _ -`, not `.`
  or `..`). The contract admits `:` in `parent_brood_id` as well (1 to 255 of
  `A-Z a-z 0-9 . _ : -`), only as tolerance for the retired timestamp form.
- `suggested_run_id`: caller-suggested run id, used verbatim. It must be a name (1 to 255 of
  `A-Z a-z 0-9 . _ -`, not `.` or `..`). An unsafe value is a blocker — there is no silent
  fallback to a derived id. Absent gives the derived id.
- `plan_steps`: cerebrate's plan `steps` reformatted to a JSON array — child/resume SEED for
  `ledger.plan.steps` (NOT the primary live writer; see §A). UNTRUSTED, stored as data. Default `[]`.
  Every entry MUST be an object whose `.id` is a step id (1 to 64 of `A-Z a-z 0-9 . _ -`), and
  every `.depends_on` entry (when present; `.depends_on` must be an array) likewise — the seeded
  ids flow into `next-wave`'s routing YAML, so an unsafe id fails closed with a blocker and no
  run dir is created.
- `plan_path`: path to the cerebrate directive — child/resume seed for `ledger.plan.path`. Default `null`.

### The §A Plan-Steps Seam

The ledger and workflow definitions are JSON; cerebrate's plan `steps` arrive as YAML in the
plan block, with no maintained converter. `plan_steps` / `plan_path` here are the
child/resume SEED path, NOT the primary live writer: the caller inits the ledger BEFORE
the `plan` (cerebrate) state runs, so an init-time seed would be empty on a fresh root run.
The PRIMARY, live persistence of `plan.steps` happens at record-time, when the caller
records the `plan` state result via `hivemind:record-state-result --plan-steps` (see that
skill's §A Plan-Steps Seam). Init-time `plan_steps` exists ONLY to seed `plan.steps` for a
child/resume run that already has the steps in hand; absent the field it defaults to `[]`.

## Inputs JSON

The script owns deterministic create-and-write; the navigator authors a single JSON
inputs file and passes its path as the one positional argument. The script FIRST checks the
whole inputs file against its contract (one JSON object; the field rules below), on the intact JSON values; nothing else is read or created until that passes.
Shape:

```json
{
  "workflow": "<required> selected workflow id",
  "user_request": "<required> raw user request (UNTRUSTED, serialized only)",
  "normalized": "<required> caller's normalized summary",
  "parent": {
    "kind": "none | brood",
    "run_id": "<required when kind=brood> parent run id",
    "brood_id": "<required when kind=brood> CANONICAL brood id — spawn-brood's generated GUID brood-<uuidv4>; persisted verbatim; already filesystem-safe",
    "strain_id": "<required when kind=brood> strain id",
    "manifest": "<required when kind=brood> manifest path"
  },
  "suggested_run_id": "<optional> caller-suggested run id; used verbatim; a name (1 to 255 of A-Z a-z 0-9 . _ -, not . or ..), else blocker",
  "plan_steps": [],
  "plan_path": "<optional> path to the cerebrate directive (seeds plan.path)"
}
```

Field rules (all checked by the one whole-file contract check, in this order):
- ABSENT: a key that is missing or `null` is absent. `""` is present.
- `workflow` is a required name: 1 to 255 of `A-Z a-z 0-9 . _ -`, not `.` or `..`.
- `user_request`, `normalized` are required strings, not empty. Stored exactly: no byte is
  lost, including a trailing line feed.
- `workflow_version` and `start_state` are not caller fields: the script takes them from the
  packaged definition's `version` and `start`. An inputs file that still carries them (a
  legacy caller) is checked against the definition, and a mismatch is a blocker.
  `workflow_version`, when supplied, is a whole number of 0 or more (a JSON number, never a
  string); `start_state`, when supplied, is a name.
- `parent` is optional (an object); `parent.kind` is `none` or `brood` and defaults to `none`
  when absent. `parent.run_id` and `parent.manifest` are strings; `parent.brood_id` is 1 to
  255 of `A-Z a-z 0-9 . _ : -`; `parent.strain_id` is a name. When `parent.kind` is `brood`,
  `parent.run_id`, `parent.brood_id`, `parent.strain_id`, and `parent.manifest` are all
  required (the brood-parent contract, checked after the first).
- `suggested_run_id` is optional; when present it is a name. An unsafe one is a blocker.
- `plan_steps` is an optional JSON array (the child/resume SEED for `plan.steps`; see §A);
  defaults to `[]` when absent. Every entry must be an object whose `.id` is a required step
  id (1 to 64 of `A-Z a-z 0-9 . _ -`); every `.depends_on` entry (when present; `.depends_on`
  must be an array) must likewise be a step id. A `null` entry fails. Any unsafe id is a
  blocker and no run dir is created.
- `plan_path` is an optional string; defaults to `null` when absent. Stored exactly.
- A failure is one blocker `run-ledger inputs file breaks its contract: <position>: <problem>`.
  The position is the dotted path with `[N]` indexes (for example `plan_steps[2].id`); the
  problem is a fixed phrase. A blocker never names the value.
- Every value is data. None is interpolated into generated shell command source.

Run-id derivation: `brood` -> `<brood-id>--<strain-id>` (the GUID is already
filesystem-safe, so the retained colon->dash pass is a no-op; `.parent.brood_id` keeps the
canonical value); else `suggested_run_id` verbatim when present (it was checked above; an
unsafe one never reaches here); else, when absent, derived `<utc-timestamp>-<workflow-id>`.
The composed id must still be 1 to 255 of `A-Z a-z 0-9 . _ -` and not `.` or `..`; a joined
brood id can exceed 255, which is a blocker that names no value.

## Procedure

1. **Build the inputs object** in your reasoning from the Required Inputs. Each untrusted
   value (`user_request`, `normalized`, any `plan_steps` text) is structured JSON data,
   never spliced into command source. Leave out `workflow_version` and `start_state`: the
   script derives both, so no workflow definition file is read for them.

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
   EXECUTE (do not Read) the script — it owns dependency check, the whole-file inputs
   contract check (first, before any other read),
   packaged-definition validation, run-id derivation, directory creation, and the atomic
   temp-write + rename of `state.json`. BEFORE creating the run dir, the script locates the
   packaged workflow definition in its self-located `workflows/` dir (`workflows/<workflow>.json`
   must EXIST), takes `workflow_version` from its `.version` and the start state from its
   `.start`, and reads that start state's definition from its `.states`. A missing definition,
   a start state the definition does not declare, or a legacy supplied `workflow_version` or
   `start_state` that does not match the definition is a blocker raised early, so it never
   leaves an orphan run dir. The caller supplies NO definition path — it is derived from
   the workflow id against the packaged dir.

4. **Interpret the result.** Exit 0: the script printed YAML routing lines on stdout —
   ```yaml
   run_id: <id>
   ledger: <checkout-root>/.hivemind/runs/<id>/state.json
   current_state: <start state>
   state_definition: <compact JSON of the start state from the packaged definition>
   ```
   the run dir is anchored to the git checkout root (`git rev-parse --show-toplevel`), not the
   CWD, so resume-on-start finds it regardless of which subdir init ran from; init requires being
   inside a git checkout. the caller proceeds with that ledger and executes `current_state` as
   `state_definition` defines it, with no read of the workflow definition file. Exit 1: the
   script printed `blocker: <reason>` on stderr and wrote no ledger — surface it and stop.

## Pointers

- EXECUTE (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/init-run-ledger/scripts/init-run-ledger.sh`.
- Ledger schema: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

## Silence Discipline

Follow `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Silence Discipline). The step 2 Write
is the inputs-file Write; the procedure ends at the step 3 Bash call.

## Do Not

- invent values for `workflow`, `user_request`, or `normalized`. The script exits 1 with a
  blocker if any required input is missing.
- read a workflow definition file to find `workflow_version`, `start_state`, or a state's
  definition. The script derives them and prints the start state's definition.
- write the ledger by hand or with any tool other than the script.
- use the Write tool for anything other than the `.hivemind/runs/.init-inputs-<token>.json`
  inputs file.
- author the inputs file by any transport other than the Write tool; see
  `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
- commit, push, or open a PR.
- Read or reconstruct the script body — invoke it with the documented inputs file path.
