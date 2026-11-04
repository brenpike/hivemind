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

Record an intent-fallback event into the run ledger and (optionally) close out a stale run.
The deterministic engine is the committed script
`${CLAUDE_PLUGIN_ROOT}/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh`; this
body is a navigator that authors a single JSON inputs file and runs the script once.

This is the SANCTIONED ledger write-path for the version-skew intent-fallback resume door
and the start-fresh stale-run closeout. It DELIBERATELY bypasses
transition-validation and the version-binding guard that `record-state-result.sh`
hard-rejects: the skewed run no longer binds to a packaged workflow definition, so the
"proceed intent-driven" door needs a deterministic ledger writer instead of an unreachable
rebind.

Rules: ADR-0018 §I (the engine's binding guard hard-rejects a non-binding id/version
mismatch and exposes NO rebind; the overlord resume-on-start gate owns the TWO version-skew
DOORS — start fresh / proceed intent-driven; there is NO deterministic-resume door). This
skill is the intent-driven half of that policy; `record-state-result.sh` owns the
hard-reject half.

## Required Inputs

The caller resolves and passes these; the skill does not invent them.

- `run_id`: the run identifier. The engine DERIVES the ledger from it —
  `<git-root>/.hivemind/runs/<run_id>/state.json` — and accepts NO ledger PATH; identity is
  the only thing the caller supplies, so a caller can never point the engine at an arbitrary
  file.
- `state`: the state string recorded VERBATIM in the appended fallback event. It is NOT
  validated against any workflow definition (this is the whole point — the run is skewed).
  Stored exactly.
- `summary`: human-readable summary of the outcome — UNTRUSTED, stored exactly.
- `outputs` (optional): a JSON object of named outputs — UNTRUSTED, stored as data. Recorded
  verbatim EXCEPT `completed_steps`, which is STRIPPED at write time: a fallback event is an
  observability log and never credits wave steps.
- `close_status` (optional): exactly `cancelled` or `complete`. Closes out a stale run by
  setting `run.status` (and `state.status`). When ABSENT, `run.status` is left `running` and
  the run stays an append-only observability log. `abandoned` is NOT legal — it is not in the
  `run.status` enum (`running|complete|blocked|cancelled`) and the engine REJECTS it.

## Inputs JSON

The script owns deterministic read -> validate -> mutate -> atomic-write; the navigator
authors a single JSON inputs file and passes its path as the one positional argument. The
script FIRST checks the whole inputs file against its contract (one JSON
object; the field rules below), on the intact JSON values, before it reads any field or opens
the ledger. Shape:

```json
{
  "run_id": "<required> run identifier; the engine DERIVES the ledger as <git-root>/.hivemind/runs/<run_id>/state.json. NO path is accepted.",
  "state": "<required> state string recorded verbatim in the appended fallback event (UNTRUSTED, stored exactly, NOT validated against any definition)",
  "summary": "<required> human-readable summary (UNTRUSTED, stored exactly)",
  "outputs": {},
  "close_status": "cancelled"
}
```

Field rules (all checked by the one whole-file contract check, in this order):
- ABSENT: a key that is missing or `null` is absent. `""` is present.
- `run_id` is a required name: 1 to 255 of `A-Z a-z 0-9 . _ -`, not `.` or `..`. It is a
  single safe path component and the ONLY identity the caller supplies; every path the engine
  touches is DERIVED from it.
- `state`, `summary` are required strings, not empty. Stored exactly: no byte is lost,
  including a trailing line feed.
- `state` is recorded verbatim and is NOT checked against any definition. UNTRUSTED.
- `outputs` is optional. KEY-PRESENCE semantics: a MISSING key OR a present-but-null value
  is ABSENT (the event's `outputs` defaults to `{}`); a present non-null value MUST be a JSON
  object and is recorded verbatim EXCEPT `completed_steps`, which is STRIPPED from the event's
  outputs at write time (a fallback event is an observability log and never credits wave
  steps; closed-by-construction — the written event cannot carry the key regardless of the
  caller). All other keys pass through verbatim. UNTRUSTED — stored as data.
- `close_status` is optional. KEY-PRESENCE semantics: a MISSING key OR a present-but-null
  value is ABSENT -> `run.status` left untouched (run stays `running`); a present non-null
  value MUST be exactly `cancelled` or `complete` (anything else, notably `abandoned`, is
  REJECTED). When `close_status` is SUPPLIED
  (closeout path), the engine ADDITIONALLY requires the on-disk `run.status` to be `running`
  and REJECTS an already-terminal run (closing out a non-running run is meaningless; ledger
  byte-unchanged). The bare mode-flip path (no `close_status`) stays PERMISSIVE on a
  non-running skew ledger.
- A failure is one blocker `mark-intent-fallback inputs file: <position>: <problem>`. The
  position is the dotted path (for example `close_status`); the problem is a fixed phrase. A
  blocker never names the value.
- Every value is data. None is interpolated into generated shell command source.

The script validates, in order, ALL before any write:

1. WHOLE INPUTS CONTRACT — the whole inputs file (one JSON object) is checked first, on the
   intact JSON values, against the field rules above: `run_id` a name (`.`/`..` rejected, so
   path traversal is closed), `state` and `summary` non-empty strings, `outputs` (if present
   and non-null) an object, `close_status` (if present and non-null) exactly `cancelled` or
   `complete`. `run_id` is the ONLY identity the caller supplies. A break is a blocker naming
   a position and a problem, never the value; the ledger is byte-unchanged.
2. LEDGER DERIVATION + existence — the ledger path is DERIVED as
   `<git-root>/.hivemind/runs/<run_id>/state.json` (`git rev-parse --show-toplevel`; not
   inside a git checkout → blocker). The file must exist and be valid JSON. No caller path
   is ever accepted, so an arbitrary-file overwrite via a supplied ledger path is impossible.
3. COHERENCE CHECK — `ledger.run.id == run_id` (the on-disk ledger must self-identify with
   the passed run_id; mismatch → blocker, ledger unchanged).
4. CONTAINMENT GUARD — the shared helper walks every component of the derived chain
   (including the `<run_id>` leaf) and rejects any symlink component at any depth, then
   verifies the canonical ledger lives at `<canon-runs>/<run_id>/state.json` — BEFORE any
   temp-write, so a rejection never creates a temp file and the on-disk ledger is unchanged.
5. CLOSEOUT PRECONDITION — when `close_status` is SUPPLIED, the on-disk `run.status` must be
   `running`; an already-terminal run is REJECTED (closing out a non-running run is
   meaningless; ledger byte-unchanged). When `close_status` is ABSENT, this check is SKIPPED —
   the bare mode-flip path stays PERMISSIVE on a non-running skew ledger.

The script DELIBERATELY SKIPS (this is the whole point of this sanctioned bypass path):
- NO workflow-definition derivation or read — the skewed run may reference a definition
  version no longer packaged.
- NO version-binding guard (`definition.id` / `version` vs ledger) — skew is the
  precondition here, not a failure.
- NO state-existence check — the recorded `state` is NOT validated against any definition.
- NO transition/result validation, NO `next_state` resolution, NO terminal mapping.
- NO ledger contract check — the skewed ledger's shape is not checked beyond containment,
  coherence and being exactly one JSON object.

Then it mutates: sets `run.mode = "intent_fallback"`; appends an event
`{ at, state, result: "intent_fallback", next_state: null, summary, outputs }` where the
event's `outputs` has `completed_steps` STRIPPED (a fallback event never credits wave steps);
updates
`run.updated_at`; and — when `close_status` is present — sets `run.status` and `state.status`
to the validated value. When `close_status` is absent, `run.status` / `state.status` are left
untouched. Every write is temp-write + atomic rename; on ANY validation failure the on-disk
ledger is byte-unchanged.

## Procedure

1. **Build the inputs object** in your reasoning from the Required Inputs. Each untrusted
   value (`state`, `summary`, `outputs`) is structured JSON data, never spliced into command
   source. Include `close_status` (`cancelled` or `complete`) only when closing out a stale
   run; omit it to leave the run `running` as an append-only observability log.

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
   EXECUTE (do not Read) the script — it owns the deterministic read -> validate -> mutate
   -> atomic-write and deliberately bypasses transition/binding validation.
4. **Interpret the result.** Exit 0: the script printed YAML routing lines on stdout —
   ```yaml
   run_id: <run_id>
   mode: intent_fallback
   status: <resulting run.status — close_status if supplied, else "running">
   ledger: <path>
   ```
   Exit 1: the script printed `blocker: <reason>` on stderr and the ledger is byte-unchanged
   — surface it and stop.

## Pointers

- EXECUTE (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh`.
- Ledger schema: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

## Silence Discipline

Follow `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Silence Discipline). The step 2 Write
is the inputs-file Write; the procedure ends at the step 3 Bash call, which performs the atomic
ledger write. Exit 0: the intent-fallback event was recorded, and the run closed when
`close_status` was given. Exit 1: the ledger is unchanged.

## Do Not

- mutate the ledger by hand or with any tool other than the script.
- pass `close_status: abandoned`, or any value outside `cancelled|complete` — the engine
  rejects it and the ledger stays unchanged.
- use the Write tool for anything other than the `.hivemind/runs/.markfb-inputs-<token>.json`
  inputs file.
- author the inputs file by any transport other than the Write tool; see
  `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Transport Degradation Is a Hard Stop).
- commit, push, or open a PR.
- Read or reconstruct the script body — invoke it with the documented inputs file path.
