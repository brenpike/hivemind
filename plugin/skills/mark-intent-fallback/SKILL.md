---
name: mark-intent-fallback
description: Records a version-skew intent-fallback event into the run ledger and optionally closes a stale run. Use when handling version skew on resume or closing out a stale run.
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh *)
  - Read
  - Write   # inert inputs-file only: authors per-invocation-unique path .hivemind/runs/.markfb-inputs-<token>.json; see security-policy.md "Inert Inputs-File Navigator Pattern" + ADR-0017/0018/0019
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
- `summary`: human-readable summary of the outcome — UNTRUSTED, serialized only.
- `outputs` (optional): a JSON object of named outputs — UNTRUSTED, serialized only. Recorded
  verbatim EXCEPT `completed_steps`, which is STRIPPED at write time: a fallback event is an
  observability log and never credits wave steps.
- `close_status` (optional): exactly `cancelled` or `complete`. Closes out a stale run by
  setting `run.status` (and `state.status`). When ABSENT, `run.status` is left `running` and
  the run stays an append-only observability log. `abandoned` is NOT legal — it is not in the
  `run.status` enum (`running|complete|blocked|cancelled`) and the engine REJECTS it.

## Inputs JSON

The script owns deterministic read -> validate -> mutate -> atomic-write; the navigator
authors a single JSON inputs file and passes its path as the one positional argument. Every
value crosses the transport as data only — the script reads each field with `jq` into a shell
variable and never interpolates it into shell source or the jq program source. What the script
does with a field after that read is the field's own contract. Shape:

```json
{
  "run_id": "<required> run identifier; the engine DERIVES the ledger as <git-root>/.hivemind/runs/<run_id>/state.json. NO path is accepted.",
  "state": "<required> state string recorded verbatim in the appended fallback event (UNTRUSTED, NOT validated against any definition)",
  "summary": "<required> human-readable summary (UNTRUSTED, serialized only)",
  "outputs": {},
  "close_status": "cancelled"
}
```

Field rules:
- `run_id`, `state`, `summary` are required non-empty strings. `run_id` must be a single safe
  path component (`^[A-Za-z0-9._-]+$`; `.`/`..` rejected) — it is the ONLY identity the caller
  supplies, and every path the engine touches is DERIVED from it.
- `state` is recorded verbatim and is NOT checked against any definition. UNTRUSTED —
  serialized only via `--arg`.
- `outputs` is optional. KEY-PRESENCE semantics: a MISSING key OR a present-but-null value
  is ABSENT (the event's `outputs` defaults to `{}`); a present non-null value MUST be a JSON
  object and is recorded verbatim EXCEPT `completed_steps`, which is STRIPPED from the event's
  outputs at write time (a fallback event is an observability log and never credits wave
  steps; closed-by-construction — the written event cannot carry the key regardless of the
  caller). All other keys pass through verbatim. UNTRUSTED — serialized only via `--argjson`.
- `close_status` is optional. KEY-PRESENCE semantics: a MISSING key OR a present-but-null
  value is ABSENT -> `run.status` left untouched (run stays `running`); a present non-null
  value MUST be exactly `cancelled` or `complete` (anything else, notably `abandoned`, is
  REJECTED). UNTRUSTED — serialized only via `--arg`. When `close_status` is SUPPLIED
  (closeout path), the engine ADDITIONALLY requires the on-disk `run.status` to be `running`
  and REJECTS an already-terminal run (closing out a non-running run is meaningless; ledger
  byte-unchanged). The bare mode-flip path (no `close_status`) stays PERMISSIVE on a
  non-running skew ledger.
- Every value is data. None is interpolated into generated shell command source.

The script validates, in order, ALL before any write:

1. `run_id` SAFE_ID_RE validation — `run_id` must match `^[A-Za-z0-9._-]+$`; `.`/`..` are
   rejected (path traversal). This is the ONLY identity the caller supplies.
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
5. `outputs` (if present and non-null) must be a JSON object; `close_status` (if present and
   non-null) must be exactly `cancelled` or `complete` — both validated up front for a clear
   blocker before any temp-write.
6. CLOSEOUT PRECONDITION — when `close_status` is SUPPLIED, the on-disk `run.status` must be
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

2. **Write the inputs file** via the Write tool to a PER-INVOCATION-UNIQUE gitignored path
   `.hivemind/runs/.markfb-inputs-<token>.json`. GENERATE an invocation-unique `<token>` for
   the filename (a UTC timestamp plus a random component, such as `20260603T150142Z-a1b2c3`)
   so two concurrent same-checkout overlord sessions (distinct runs) author DISTINCT inputs
   files and cannot clobber each other's payload between the Write and the script exec; safe
   sequential re-records of the same run are also protected (closes the singleton-inputs
   TRANSPORT TOCTOU; see ADR-0019). Note: the token makes the TRANSPORT FILE invocation-unique
   — it does NOT make concurrent mutation of ONE run's ledger safe. A run ledger is owned and
   mutated by exactly one overlord instance (RUN-OWNERSHIP-01, worktree isolation); concurrent
   same-run ledger mutation is outside the design envelope. `file_path` =
   `.hivemind/runs/.markfb-inputs-<token>.json`, `content` = the JSON object from step 1. The
   leading-dot `.markfb-inputs-*` name is a SIBLING of the run dirs (`runs/<run-id>/`), not one
   of them, so it stays OUT of the `runs/<run-id>/` glob — it never collides with `state.json`
   or the engine's atomic temp `.state.json.XXXXXX` inside a run dir (distinct names, different
   dir level), and never pollutes the run-dir scan. The path carries NO `run_id` (no
   caller-derived component below the fixed-literal `.hivemind/runs/` level), so a committed
   symlinked run-dir leaf cannot redirect the Write outside the checkout. `.hivemind/` is
   gitignored. Do NOT pass the inputs via stdin/heredoc: a heredoc reintroduces the very
   delimiter-injection class the inert Write-tool-file pattern exists to avoid (ADR-0017).
   Cleanup is not required: this is transient gitignored state and `.hivemind/` is ephemeral.
   Write performs no shell parsing of the values, and the engine reads each field with `jq`
   into a shell variable, so `state` / `summary` / `outputs` text is never interpolated into
   shell or jq program source.
   If the Write tool is ABSENT from this session, STOP BLOCKED per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern →
   Transport Degradation Is a Hard Stop).

3. **Execute the script** with one Bash call, passing the inputs file path:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh .hivemind/runs/.markfb-inputs-<token>.json
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

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own — its steps are tool calls only.
- The Write tool (step 2) is a permitted NON-FINAL tool call — it emits no chat text and
  authors ONLY the inputs file (`.hivemind/runs/.markfb-inputs-<token>.json`).
- The procedure ends at the step 3 Bash script call, which performs the atomic ledger write and
  hands the routing data back to the caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = the intent-fallback event was recorded (and the run optionally closed); routing
  data is on stdout. Exit 1 = blocked; the reason is on stderr and the ledger is unchanged.

## Do Not

- mutate the ledger by hand or with any tool other than the script.
- pass `close_status: abandoned`, or any value outside `cancelled|complete` — the engine
  rejects it and the ledger stays unchanged.
- use the Write tool for anything other than the `.hivemind/runs/.markfb-inputs-<token>.json`
  inputs file.
- author the inputs file via any transport other than the Write tool — no heredoc, no shell
  redirection, no inline python/node script. A missing Write tool is a hard stop, not a
  workaround; see `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md`
  (Transport Degradation Is a Hard Stop).
- commit, push, or open a PR.
- Read or reconstruct the script body — invoke it with the documented inputs file path.
