---
name: record-state-result
description: Records a workflow state outcome into the run ledger, validates the transition against the workflow definition, and advances state.current to the legal next state. Use when advancing a run after a state completes.
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/record-state-result/scripts/record-state-result.sh" *)
  - Read(~/.claude/plugins/cache/brenpike/hivemind/**)
  - Edit(.hivemind/runs/.record-inputs-*.json)
shell: bash
---

# Record State Result

Record the outcome of the current workflow state into the run ledger, append a ledger
event, validate the transition against the workflow definition, and advance
`state.current` to the legal next state. The deterministic engine is the committed script
`${CLAUDE_PLUGIN_ROOT}/skills/record-state-result/scripts/record-state-result.sh`; this
body is a navigator that authors a single JSON inputs file and runs the script once. The
allowed-result set is read DIRECTLY from the workflow definition by the script — the model
NEVER supplies it.

Rules: ADR-0018 §C (engine is the committed script, reads the allowed-set); §A (ledger and
definitions are JSON); §I (engine hard-rejects a non-binding id/version mismatch and exposes
no rebind; the overlord resume gate owns the two version-skew doors — start fresh / proceed
intent-driven). This script is NOT the fallback writer — it still hard-rejects skew. The
SANCTIONED engine op for both version-skew doors (proceed intent-driven AND start-fresh
stale-run closeout) is the separate `hivemind:mark-intent-fallback` skill and its own
committed engine script; neither door is dangling.

## Required Inputs

The caller resolves and passes these; the skill does not invent them.

- `run_id`: the run identifier (from `init-run-ledger`). The engine DERIVES the ledger
  from it — `<git-root>/.hivemind/runs/<run_id>/state.json` — and DERIVES the workflow
  definition from the ledger's own `run.workflow` against the script's self-located
  packaged `workflows/` dir. The caller passes NO ledger or workflow PATH; both are
  derived from ground truth, so a caller can never point the engine at an arbitrary file.
- `state`: the state the run is currently in (MUST equal `ledger.state.current`).
- `result`: the named outcome to record (MUST be a legal transition key under that state).
- `summary`: human-readable summary of the outcome — UNTRUSTED, stored exactly.
- `outputs` (optional): a JSON object of named outputs — UNTRUSTED, stored as data.
- `plan_steps` (optional): cerebrate's plan `steps` reformatted to a JSON array — UNTRUSTED,
  stored as data. Pass this when recording any cerebrate planning state result (`plan` /
  `review_remediation_plan` / `review_remediation_plan_postpr` / `brood_plan`; see §A below).
- `plan_path` (optional): path to the cerebrate directive — UNTRUSTED, stored exactly.

## The §A Plan-Steps Seam

The ledger and workflow definitions are JSON; cerebrate's plan `steps` arrive as YAML in
the plan block, with no maintained converter. The PRIMARY, live persistence path for
`plan.steps` is **record-time, here**: the caller inits the ledger BEFORE any cerebrate
planning state runs, so an init-time seed would be empty at runtime. When the caller
records any cerebrate planning state result (`plan` / `review_remediation_plan` /
`review_remediation_plan_postpr` / `brood_plan`, after cerebrate returns), it reformats
cerebrate's YAML plan `steps` into a JSON array and includes `plan_steps` (and optionally
`plan_path`) in the inputs file; the script sets `.plan.steps = $plan_steps` (and
`.plan.path`). When those keys are ABSENT (missing or null), `.plan.*` is left UNTOUCHED —
never clobbered to `[]`.

`init-run-ledger`'s `plan_steps` is a writer ONLY for the child/resume SEED path
(default `[]`); the primary live writer is here (see that skill's §A Plan-Steps Seam).

The `outputs` field here is the event's free-form `outputs` object — it is NOT a plan-steps
writer; use `plan_steps` for that.

Recording ANY cerebrate planning-state result also ADVANCES an engine-owned monotonic plan
epoch (`.plan.epoch`), and every appended event — for this and every other state — is
stamped with the current `plan_epoch`. The caller supplies NOTHING for this: it is entirely
engine-maintained, with no inputs-file field to set it.

## Inputs JSON

The script owns deterministic read -> validate -> mutate -> atomic-write; the navigator
authors a single JSON inputs file and passes its path as the one positional argument. Every
value crosses the transport as data only — never interpolated into shell source or the jq
program source. The script FIRST checks the whole inputs file against its contract (one JSON
object; the field rules below), on the intact JSON values, before it reads any field or opens
the ledger. Shape:

```json
{
  "run_id": "<required> run identifier; the engine DERIVES the ledger as <git-root>/.hivemind/runs/<run_id>/state.json and the workflow definition from the ledger's run.workflow against the self-located packaged workflows dir. NO path is accepted.",
  "state": "<required> state the run is currently in (must match ledger.state.current)",
  "result": "<required> named outcome to record (must be a legal transition key)",
  "summary": "<required> human-readable summary (UNTRUSTED, stored exactly)",
  "outputs": {},
  "plan_steps": [],
  "plan_path": "<optional> path to the cerebrate directive (sets plan.path)"
}
```

Field rules (all checked by the one whole-file contract check, in this order):
- ABSENT: a key that is missing or `null` is absent. `""` is present.
- `run_id`, `state`, `result` are required names: 1 to 255 of `A-Z a-z 0-9 . _ -`, not `.` or
  `..`. `run_id` is a single safe path component — it is the ONLY identity the caller
  supplies, and every path the engine touches is DERIVED from it.
- `summary` is a required string, not empty. Stored exactly: no byte is lost, including a
  trailing line feed.
- `outputs` is optional. KEY-PRESENCE semantics: a MISSING key OR a present-but-null value
  is ABSENT (the event's `outputs` defaults to `{}`); a present non-null value MUST be a JSON
  object and is recorded verbatim. UNTRUSTED — stored as data. When `outputs`
  carries a `completed_steps` key (present and non-null), it is honored ONLY when the recording
  state is a WAVE-PRODUCING agent state (`states.<state>.type == "agent"` AND
  `states.<state>` declares `allowed_agents` AND `"hivemind:cerebrate"` is not in that
  `allowed_agents` set, derived from the packaged workflow definition) — symmetric to the
  plan-write authorization below (§10); at any other recording state the record is REJECTED
  (blocker, ledger byte-unchanged). `outputs.completed_steps`, when present, must be an array.
- `plan_steps` is optional (cerebrate plan steps as a JSON array; sets `.plan.steps`).
  KEY-PRESENCE semantics: a MISSING key OR a present-but-null value is ABSENT -> `.plan.*`
  left UNTOUCHED (never clobbered to `[]`); a present non-null value MUST be a JSON array.
  Every entry must be an object whose `id` is a required step id (1 to 64 of `A-Z a-z 0-9 . _ -`),
  and every `depends_on` (when present; it must be an array) entry likewise a step id — a
  write-boundary charset guard so an unsafe id (YAML delimiter/bracket/comma/newline) can never
  persist and forge next-wave's routing YAML. A `null` entry fails. `.`/`..` are NOT rejected
  (step ids never become path components). UNTRUSTED — stored as data.
- `plan_path` is optional (sets `.plan.path`). KEY-PRESENCE semantics: a MISSING key OR a
  present-but-null value is ABSENT -> `.plan.path` left UNTOUCHED; a present non-null value
  is a string, stored exactly. UNTRUSTED.
- A failure is one blocker `record-state-result inputs file: <position>: <problem>`. The
  position is the dotted path with `[N]` indexes (for example `plan_steps[2].depends_on[0]`);
  the problem is a fixed phrase. A blocker never names the value.
- Every value is data. None is interpolated into generated shell command source.

The script validates, in order, ALL before any write:

1. WHOLE INPUTS CONTRACT — the whole inputs file (one JSON object) is checked first, on the
   intact JSON values, against the field rules above: `run_id`/`state`/`result` names (`.`/`..`
   rejected, so path traversal is closed), `summary` a non-empty string, `outputs` (if present
   and non-null) an object, `plan_steps` (if present and non-null) an array of step rows,
   `plan_path` a string. `run_id` is the ONLY identity the caller supplies. A break is a
   blocker naming a position and a problem, never the value; the ledger is byte-unchanged.
2. LEDGER DERIVATION + existence — the ledger path is DERIVED as
   `<git-root>/.hivemind/runs/<run_id>/state.json` (`git rev-parse --show-toplevel`; not
   inside a git checkout → blocker). The file must exist and be exactly one JSON object. No
   caller path is ever accepted, so an arbitrary-file overwrite via a supplied ledger path is
   impossible.
3. COHERENCE CHECK — `ledger.run.id == run_id` (the on-disk ledger must self-identify with
   the passed run_id; mismatch → blocker, ledger unchanged).
4. LEDGER CONTRACT + DEFINITION DERIVATION — the whole canonical ledger is checked against its
   contract first: `run.id`, `run.workflow`, `state.current` required names and
   `run.workflow_version` a required whole number (blocker
   `record-state-result ledger: <position>: <problem>`). Then the workflow definition is
   DERIVED from the (trusted) ledger's `run.workflow` against the script's SELF-LOCATED
   packaged `workflows/` dir (`BASH_SOURCE` + `pwd -P`, independent of
   `${CLAUDE_PLUGIN_ROOT}` and of any caller value). The caller supplies NO definition path,
   so a forged definition can never be injected.
5. `definition.id == ledger.run.workflow` — BINDING GUARD (engine hard-reject; ledger
   unchanged). Now compares the trusted ledger against the self-derived PACKAGED definition,
   not a caller-supplied path.
6. `definition.version == ledger.run.workflow_version` — BINDING GUARD. The engine HARD-REJECTS
   an id/version mismatch and exposes NO rebind; the overlord resume-on-start gate owns the
   TWO version-skew DOORS (start fresh / proceed intent-driven). There is NO deterministic-resume
   door. The engine never reconciles skew — it rejects a non-binding definition outright.
7. `ledger.state.current == state`.
8. `state` exists in `definition.states` (state-existence — a renamed/removed state never
   guesses; this is NOT version-skew).
9. `result` is a key under `states.<state>.transitions`; resolves `next_state`, which must be
   declared in `definition.states`.
10. PLAN-WRITE AUTHORIZATION — if `plan_steps` or `plan_path` was supplied (present and
   non-null), the recording state MUST be a cerebrate planning state
   (`states.<state>.agent == "hivemind:cerebrate"`, i.e. `plan` / `review_remediation_plan` /
   `review_remediation_plan_postpr` / `brood_plan`); otherwise the engine rejects (exit 1,
   ledger byte-unchanged). Key presence alone does NOT authorize a plan write — only a cerebrate
   agent state may persist `plan.steps` / `plan.path`.
11. PRODUCER AUTHORIZATION — if `outputs` carries a `completed_steps` key (present and
   non-null), the recording state MUST be a WAVE-PRODUCING agent state
   (`states.<state>.type == "agent"` AND `states.<state>` has `allowed_agents` AND
   `"hivemind:cerebrate"` is not in that `allowed_agents` set, derived from the packaged
   workflow definition — ground-truth, no hardcoded state names); otherwise the engine rejects
   (exit 1, ledger byte-unchanged). This is symmetric to §10: key presence alone does NOT
   authorize a `completed_steps` credit — only a wave-producing agent state may persist it.

Then it appends the event; updates `state.previous`/`state.current`/`state.status`,
`run.updated_at`, (if `next_state` is terminal) `run.status`, and — when `plan_steps` /
`plan_path` are present (non-null) — `plan.steps` / `plan.path`. Terminal `run.status` mapping
(schema enum `running|complete|blocked|cancelled`): `complete`→`complete`,
`blocked`→`blocked`, `cancelled`→`cancelled`, the human-intervention terminals
(`user_input_required` / `review_rejected` / `review_exhausted`)→`blocked` (stopped, needs
attention — never masked as success), and any other done-terminal (e.g. `hatchery_monitor`,
`review_window_elapsed`)→`complete`. `review_window_elapsed` is not an intervention terminal:
a quiet idle window with no new review arrivals is the normal healthy ending of watching a
quiet PR, never "stopped, needs attention". Every write is temp-write + atomic rename; on ANY
validation failure the on-disk ledger is byte-unchanged.

## Procedure

1. **Build the inputs object** in your reasoning from the Required Inputs. When recording any
   cerebrate planning state result (`plan` / `review_remediation_plan` /
   `review_remediation_plan_postpr` / `brood_plan`), reformat cerebrate's YAML plan `steps`
   into a JSON array per the §A seam and include it as `plan_steps` (and `plan_path` if known)
   — this is the primary, live writer of `ledger.plan.steps`. Each untrusted value (`summary`,
   `outputs`, `plan_steps`, `plan_path`) is structured JSON data, never spliced into command
   source.

2. **Write the inputs file** via the Write tool to a PER-INVOCATION-UNIQUE gitignored path
   `.hivemind/runs/.record-inputs-<token>.json`. GENERATE an invocation-unique `<token>` for the
   filename (a UTC timestamp plus a random component, such as `20260601T014132Z-a1b2c3`) so two
   concurrent same-checkout overlord sessions (distinct runs) author DISTINCT inputs files and
   cannot clobber each other's payload between the Write and the script exec; safe sequential
   re-records of the same run are also protected (closes the singleton-inputs TRANSPORT TOCTOU;
   see ADR-0019). Note: the token makes the TRANSPORT FILE invocation-unique — it does NOT make
   concurrent mutation of ONE run's ledger safe. A run ledger is owned and mutated by exactly one
   overlord instance (RUN-OWNERSHIP-01, worktree isolation); concurrent same-run ledger mutation
   is outside the design envelope. Serializing same-run ledger writes (a per-run lock) is deferred, not implemented here. `file_path` =
   `.hivemind/runs/.record-inputs-<token>.json`, `content` = the JSON object from step 1. The
   leading-dot `.record-inputs-*` name is a SIBLING of the run dirs (`runs/<run-id>/`), not one of
   them, so it stays OUT of the `runs/<run-id>/` glob — it never collides with `state.json` or the
   engine's atomic temp `.state.json.XXXXXX` inside a run dir (distinct names, different dir level),
   and never pollutes the run-dir scan. The path carries NO `run_id` (no caller-derived component
   below the fixed-literal `.hivemind/runs/` level), so a committed symlinked run-dir leaf cannot
   redirect the Write outside the checkout. `.hivemind/` is gitignored. Do NOT pass the inputs via
   stdin/heredoc: a heredoc reintroduces the very delimiter-injection class the inert Write-tool-file
   pattern exists to avoid (ADR-0017). Cleanup is not required: this is transient gitignored state and
   `.hivemind/` is ephemeral. Write performs no shell parsing of the values, and the engine
   keeps `summary` / `plan_path` text out of shell variables and out of shell and jq program
   source (it reads them from the inputs file as data, so each is stored exactly), and
   `outputs` / `plan_steps` enter the write as data only.
   If the Write tool is ABSENT from this session, STOP BLOCKED per
   `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern →
   Transport Degradation Is a Hard Stop).

3. **Execute the script** with one Bash call, passing the inputs file path:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/record-state-result/scripts/record-state-result.sh" .hivemind/runs/.record-inputs-<token>.json
   ```
   EXECUTE (do not Read) the script — it owns the deterministic read -> validate -> mutate
   -> atomic-write and reads the allowed-result set directly from the definition.
4. **Interpret the result.** Exit 0: the script printed YAML routing lines on stdout —
   ```yaml
   previous_state: <state>
   result: <result>
   current_state: <next_state>
   ledger: <path>
   state_definition: <compact JSON of next_state from the packaged definition>
   ```
   the caller advances ONLY to `current_state` and executes it as `state_definition` defines
   it, with no read of the workflow definition file. A `next_state` the definition does not
   declare is a blocker raised before any write. Exit 1: the script printed
   `blocker: <reason>` on stderr and the ledger is byte-unchanged — surface it and stop.

## Pointers

- EXECUTE (do not read) the engine:
  `${CLAUDE_PLUGIN_ROOT}/skills/record-state-result/scripts/record-state-result.sh`.
- Ledger schema: `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md`.

## Silence Discipline

This is a pipeline skill. The rules below govern this skill's own procedure, not the calling
agent's turn — the skill returns control to whatever invoked it, whether that caller runs it
as a workflow state or as one step inside a longer procedure:

- This skill's procedure produces zero chat text of its own — its steps are tool calls only.
- The Write tool (step 2) is a permitted NON-FINAL tool call — it emits no chat text and
  authors ONLY the inputs file (`.hivemind/runs/.record-inputs-<token>.json`). The final
  action is the Bash script call (step 3), which performs every atomic ledger write.
- The procedure ends at the step 3 Bash script call, which hands the routing data back
  to the caller; the caller then continues from the point at which it invoked this skill.
- Exit 0 = caller advances to `current_state`, which the `state_definition` line defines;
  routing data is on stdout.
  Exit 1 = blocked; the reason is on stderr and the ledger is unchanged.

## Do Not

- supply or guess the allowed-result set — the script reads it directly from the workflow
  definition.
- advance to any state other than the `current_state` the script returns.
- mutate the ledger by hand or with any tool other than the script. This stays ABSOLUTE:
  the version-skew intent-fallback write and the start-fresh stale-run closeout are SANCTIONED
  engine ops via the `hivemind:mark-intent-fallback` skill (its own committed engine script),
  NOT hand-mutation.
- use the Write tool for anything other than the `.hivemind/runs/.record-inputs-<token>.json`
  inputs file.
- author the inputs file via any transport other than the Write tool — no heredoc, no shell
  redirection, no inline python/node script. A missing Write tool is a hard stop, not a
  workaround; see `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md`
  (Transport Degradation Is a Hard Stop).
- commit, push, or open a PR.
- Read or reconstruct the script body — invoke it with the documented inputs file path.
