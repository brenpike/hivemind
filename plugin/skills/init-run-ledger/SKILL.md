---
name: init-run-ledger
description: Creates the run ledger for the current overlord instance, writing .hivemind/runs/<run-id>/state.json. Use when starting or initializing a new run.
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/init-run-ledger/scripts/init-run-ledger.sh *)
  - Read
  - Write   # inert inputs-file only: authors per-invocation-unique path .hivemind/runs/.init-inputs-<token>.json; see security-policy.md "Inert Inputs-File Navigator Pattern" + ADR-0017/0018/0019
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

- `workflow`: the selected workflow id (matches an `<id>.json` under
  `${CLAUDE_PLUGIN_ROOT}/workflows/`).
- `workflow_version`: the definition `version` at init time (non-negative integer).
- `start_state`: the workflow's `start` state (becomes `state.current` at init).
- `user_request`: the raw user request — UNTRUSTED data, serialized only.
- `normalized`: the caller's normalized summary of the request.

Optional (brood child / id control):

- `parent_kind`: `none | brood` (default `none`).
- `parent_run_id`, `parent_brood_id`, `parent_strain_id`, `parent_manifest`: required for
  the `brood` variant. `parent_brood_id` is the CANONICAL brood id — the GUID `spawn-brood`
  generates (`brood-<uuidv4>`, asserted `^brood-[0-9a-f-]+$`; ADR-0021). It is persisted
  VERBATIM into `.parent.brood_id` so the child ledger reconciles with the manifest. The
  internal colon->dash sanitization is retained only as defensive tolerance for the retired
  timestamp-shaped brood id and is a no-op on the GUID form, which is already
  filesystem-safe. `parent_strain_id` must match `[A-Za-z0-9._-]`.
- `suggested_run_id`: caller-suggested run id, used verbatim only if it matches
  `[A-Za-z0-9._-]`, else a derived id is used.
- `plan_steps`: cerebrate's plan `steps` reformatted to a JSON array — child/resume SEED for
  `ledger.plan.steps` (NOT the primary live writer; see §A). UNTRUSTED, serialized only. Default `[]`.
  Every entry MUST be an object whose `.id` is a non-empty string matching `[A-Za-z0-9._-]`
  (SAFE_ID_RE), and every `.depends_on` entry (when present; `.depends_on` must be an array)
  likewise — the seeded ids flow into `next-wave`'s routing YAML, so an unsafe id fails closed
  with a blocker and no run dir is created.
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
inputs file and passes its path as the one positional argument. Every value is inert
data — the script reads each field with `jq` into a shell variable and never
interpolates it into shell source or the jq program source. Shape:

```json
{
  "workflow": "<required> selected workflow id (matches <id>.json under workflows/)",
  "workflow_version": 1,
  "start_state": "<required> the workflow's start state",
  "user_request": "<required> raw user request (UNTRUSTED, serialized only)",
  "normalized": "<required> caller's normalized summary",
  "parent": {
    "kind": "none | brood",
    "run_id": "<required when kind=brood> parent run id",
    "brood_id": "<required when kind=brood> CANONICAL brood id — spawn-brood's generated GUID brood-<uuidv4>; persisted verbatim; already filesystem-safe",
    "strain_id": "<required when kind=brood> strain id",
    "manifest": "<required when kind=brood> manifest path"
  },
  "suggested_run_id": "<optional> caller-suggested run id; verbatim only if it matches [A-Za-z0-9._-]",
  "plan_steps": [],
  "plan_path": "<optional> path to the cerebrate directive (seeds plan.path)"
}
```

Field rules:
- `workflow`, `start_state`, `user_request`, `normalized` are required non-empty strings.
- `workflow_version` is a required JSON number (non-negative integer).
- `parent` is optional; `parent.kind` defaults to `none` when the block is absent.
  When `parent.kind` is `brood`, `parent.run_id`, `parent.brood_id`, `parent.strain_id`,
  and `parent.manifest` are all required.
- `plan_steps` is an optional JSON array (the child/resume SEED for `plan.steps`; see §A);
  defaults to `[]` when omitted. Every entry must be an object whose `.id` is a non-empty
  string matching `[A-Za-z0-9._-]` (SAFE_ID_RE); every `.depends_on` entry (when present;
  `.depends_on` must be an array) must likewise be a non-empty SAFE_ID_RE string. Any unsafe
  id is a blocker and no run dir is created.
- `plan_path` is optional; defaults to `null` when omitted.
- Every value is data. None is interpolated into generated shell command source.

Run-id derivation: `brood` -> `<brood-id>--<strain-id>` (the GUID is already
filesystem-safe, so the retained colon->dash pass is a no-op; `.parent.brood_id` keeps the
canonical value); else a safe `suggested_run_id` verbatim; else derived
`<utc-timestamp>-<workflow-id>`.

## Procedure

1. **Build the inputs object** in your reasoning from the Required Inputs. Each untrusted
   value (`user_request`, `normalized`, any `plan_steps` text) is structured JSON data,
   never spliced into command source. `start_state` MUST be the `start` value declared in
   the chosen workflow definition (`<id>.json` under `${CLAUDE_PLUGIN_ROOT}/workflows/`) —
   derive it from that file.

2. **Write the inputs file** via the Write tool to a PER-INVOCATION-UNIQUE gitignored path
   `.hivemind/runs/.init-inputs-<token>.json`. Init has NO `run_id` yet — the ledger is being
   CREATED — so there is no run dir to key the path on; instead GENERATE an invocation-unique
   `<token>` for the filename (e.g. a UTC timestamp plus a random component, such as
   `20260601T014132Z-a1b2c3`) so two concurrent same-checkout overlord sessions initing at the
   same moment author DISTINCT inputs files and cannot clobber each other's payload between the
   Write and the script exec (closes the singleton-inputs TOCTOU; see ADR-0019). `file_path` =
   `.hivemind/runs/.init-inputs-<token>.json`, `content` = the JSON object from step 1. The
   leading-dot `.init-inputs-*` name is a SIBLING of the run dirs (`runs/<run-id>/`), not one of
   them, so it stays OUT of the `runs/<run-id>/` glob — it never pollutes the run-dir scan or the
   existing-ledger check. `.hivemind/` is gitignored. Do NOT pass the inputs via stdin/heredoc:
   a heredoc reintroduces the very delimiter-injection class the inert Write-tool-file pattern
   exists to avoid (ADR-0017). Cleanup is not required: this is transient gitignored state and
   `.hivemind/` is ephemeral. Write performs no shell parsing of the values, so untrusted
   `user_request` / `normalized` / `plan_steps` text is inert.
   If the Write tool is ABSENT from this session, STOP BLOCKED per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern →
   Transport Degradation Is a Hard Stop).

3. **Execute the script** with one Bash call, passing the inputs file path:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/init-run-ledger/scripts/init-run-ledger.sh .hivemind/runs/.init-inputs-<token>.json
   ```
   EXECUTE (do not Read) the script — it owns dependency check, input validation,
   packaged-definition validation, run-id derivation, directory creation, and the atomic
   temp-write + rename of `state.json`. BEFORE creating the run dir, the script validates the
   packaged workflow definition against the script's self-located `workflows/` dir
   (`workflows/<workflow>.json` must EXIST, its `.version` must equal `workflow_version`, and
   its `.start` must equal `start_state`) and fails early with a blocker on any mismatch, so a
   bad `workflow`/`workflow_version`/`start_state` never leaves an orphan run dir. The caller
   supplies NO definition path — it is derived from the workflow id against the packaged dir.

4. **Interpret the result.** Exit 0: the script printed YAML routing lines on stdout —
   ```yaml
   run_id: <id>
   ledger: <checkout-root>/.hivemind/runs/<id>/state.json
   ```
   the run dir is anchored to the git checkout root (`git rev-parse --show-toplevel`), not the
   CWD, so resume-on-start finds it regardless of which subdir init ran from; init requires being
   inside a git checkout. the caller proceeds with that ledger. Exit 1: the script printed `blocker: <reason>`
   on stderr and wrote no ledger — surface it and stop.

## Pointers

- EXECUTE (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/init-run-ledger/scripts/init-run-ledger.sh`.
- Ledger schema: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own — its steps are tool calls only.
- The Write tool (step 2) is a permitted NON-FINAL tool call — it emits no chat text and
  authors ONLY the inputs file (`.hivemind/runs/.init-inputs-<token>.json`). The final action
  is the Bash script call (step 3).
- The procedure ends at the step 3 Bash script call, which hands the routing data back
  to the caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = caller proceeds; routing data (`run_id:`, `ledger:`) is on stdout.
  Exit 1 = blocked; the reason is on stderr.

## Do Not

- invent values for `workflow`, `workflow_version`, `start_state`, `user_request`, or
  `normalized` — the script exits 1 with a blocker if any required input is missing.
- write the ledger by hand or with any tool other than the script.
- use the Write tool for anything other than the `.hivemind/runs/.init-inputs-<token>.json`
  inputs file.
- author the inputs file via any transport other than the Write tool — no heredoc, no shell
  redirection, no inline python/node script. A missing Write tool is a hard stop, not a
  workaround; see `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md`
  (Transport Degradation Is a Hard Stop).
- commit, push, or open a PR.
- Read or reconstruct the script body — invoke it with the documented inputs file path.
