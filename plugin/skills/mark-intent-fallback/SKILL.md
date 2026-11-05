---
name: mark-intent-fallback
description: Records a version-skew intent-fallback in the run ledger and can close a stale run. Use on resume skew or stale runs.
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh" *)
  - Read(~/.claude/plugins/cache/brenpike/hivemind/**)
  - Edit(.hivemind/runs/.markfb-inputs-*.json)
shell: bash
---

# Mark Intent Fallback

Record an intent-fallback event in the run ledger and, optionally, close out a stale
run. The engine is the committed script
`${CLAUDE_PLUGIN_ROOT}/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh`;
this body authors one JSON inputs file and runs the script once.

This is the sanctioned ledger write path for the version-skew intent-fallback resume
door and the start-fresh stale-run closeout. It skips the transition validation and
the version-binding guard that `record-state-result.sh` enforces, because a skewed run
no longer binds to a packaged workflow definition (ADR-0018 §I: the
overlord resume-on-start gate owns the two version-skew doors, start fresh / proceed
intent-driven, with no deterministic-resume door).

## Required Inputs

The caller resolves and passes these; the skill does not invent them.

- `run_id`: the run identifier. The engine derives the ledger
  (`<git-root>/.hivemind/runs/<run_id>/state.json`) and accepts no ledger path.
- `state`: the state string recorded verbatim in the appended fallback event, never
  validated against a workflow definition. Stored exactly.
- `summary`: human-readable summary; untrusted, stored exactly.
- `outputs` (optional): a JSON object of named outputs; untrusted, stored as data,
  verbatim except `completed_steps`, which is stripped: a fallback event never credits
  wave steps.
- `close_status` (optional): exactly `cancelled` or `complete`. Closes out a stale run
  by setting `run.status` (and `state.status`). Absent, `run.status` stays `running`
  and the run stays an append-only observability log. `abandoned` is not in the
  `run.status` enum (`running|complete|blocked|cancelled`), and the engine rejects it.

## Inputs JSON

The script owns the deterministic read -> validate -> mutate -> atomic-write; the
navigator authors one JSON inputs file and passes its path as the one positional
argument. The script first checks the whole inputs file against its contract (one
JSON object; the field rules below), on the intact JSON values, before it reads any
field or opens the ledger. Shape:

```json
{
  "run_id": "<required> run identifier; the engine derives the ledger from it. No path is accepted.",
  "state": "<required> state string recorded verbatim in the fallback event (UNTRUSTED, stored exactly, not validated)",
  "summary": "<required> human-readable summary (UNTRUSTED, stored exactly)",
  "outputs": {},
  "close_status": "cancelled"
}
```

Field rules (all checked by the one whole-file contract check, in this order):
- Absent: a key that is missing or `null` is absent. `""` is present.
- `run_id` is a required name: 1 to 255 of `A-Z a-z 0-9 . _ -`, not `.` or `..`, a
  single safe path component and the only identity the caller supplies.
- `state`, `summary` are required strings, not empty. Stored exactly: no byte is lost,
  including a trailing line feed. `state` is not checked against any definition.
- `outputs` is optional; when present it must be a JSON object (absent gives `{}`).
  `completed_steps` is stripped from the event's outputs at write time, whatever the
  caller sends; every other key passes through verbatim.
- `close_status` is optional; absent leaves `run.status` untouched (`running`). When
  present it must be exactly `cancelled` or `complete` (anything else, notably
  `abandoned`, is rejected), and the on-disk `run.status` must be `running`: closing
  out an already-terminal run is rejected. Without `close_status` the mode flip is
  allowed on a non-running skew ledger.
- A failure is one blocker `mark-intent-fallback inputs file: <position>: <problem>`.
  The position is the dotted path (for example `close_status`); the problem is a fixed
  phrase. A blocker never names the value.
- Every value is data. None is interpolated into generated shell command source.

The script validates, in order, all before any write:

1. The whole inputs contract (field rules above).
2. The ledger at the derived `<git-root>/.hivemind/runs/<run_id>/state.json`
   (`git rev-parse --show-toplevel`; outside a git checkout → blocker) must exist and
   be valid JSON.
3. `ledger.run.id == run_id`.
4. Containment: no component of the derived chain, the `<run_id>` leaf included, is a
   symlink, and the canonical ledger is `<canon-runs>/<run_id>/state.json`, checked
   before any temp-write.
5. Closeout precondition: with `close_status`, the on-disk `run.status` is `running`.

Any failure exits 1 with a blocker and leaves the ledger byte-unchanged.

The script skips: any workflow-definition read, the version-binding guard, the
state-existence check, transition/result validation, `next_state` resolution,
terminal mapping, and the ledger contract check (the skewed ledger is checked only
for containment, coherence and being exactly one JSON object).

Then it sets `run.mode = "intent_fallback"`; appends an event
`{ at, state, result: "intent_fallback", next_state: null, summary, outputs }` with
`completed_steps` stripped from `outputs`; updates `run.updated_at`; and, only when
`close_status` is present, sets `run.status` and `state.status` to it. Every write is
temp-write + atomic rename.

## Procedure

1. **Build the inputs object** in your reasoning from the Required Inputs. Each
   untrusted value (`state`, `summary`, `outputs`) is structured JSON data, never
   spliced into command source. Include `close_status` (`cancelled` or `complete`)
   only when closing out a stale run.

2. **Write the inputs file** with the Write tool, per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern):
   `file_path` = `.hivemind/runs/.markfb-inputs-<token>.json`, where `<token>` is new for each
   invocation (a UTC timestamp plus a random part, such as `20260603T150142Z-a1b2c3`);
   `content` = the JSON object from step 1. No cleanup is needed.
   If the Write call does not succeed, stop blocked per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).

3. **Execute the script** with one Bash call, passing the inputs file path:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh" .hivemind/runs/.markfb-inputs-<token>.json
   ```
   Execute (do not Read) the script.
4. **Interpret the result.** Exit 0: the script printed YAML routing lines on stdout:
   ```yaml
   run_id: <run_id>
   mode: intent_fallback
   status: <resulting run.status — close_status if supplied, else "running">
   ledger: <path>
   ```
   Exit 1: the script printed `blocker: <reason>` on stderr and the ledger is
   byte-unchanged; surface it and stop.

## Pointers

- Execute (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh`.
- Ledger schema: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

## Silence Discipline

Follow `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Silence Discipline). The step 2 Write
is the inputs-file Write; the procedure ends at the step 3 Bash call, which performs the atomic
ledger write. Exit 0: the intent-fallback event was recorded, and the run closed when
`close_status` was given. Exit 1: the ledger is unchanged.

## Do Not

- mutate the ledger by hand or with any tool other than the script.
- pass `close_status: abandoned`, or any value outside `cancelled|complete`.
- use the Write tool for anything other than the `.hivemind/runs/.markfb-inputs-<token>.json`
  inputs file.
- author the inputs file by any transport other than the Write tool; see
  `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
- commit, push, or open a PR.
- Read or reconstruct the script body; invoke it with the documented inputs file path.
