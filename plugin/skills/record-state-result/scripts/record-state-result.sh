#!/usr/bin/env bash
#
# record-state-result — deterministic transition engine for the
# hivemind:record-state-result skill.
#
# Records the outcome of the current workflow state into the run ledger and advances
# state.current to the legal next state, reading the allowed-result set DIRECTLY from
# the workflow definition (the model NEVER supplies it). This script OWNS the
# deterministic read -> validate -> mutate -> atomic-write; the skill body is a thin
# navigator. Mirrors the spawn-brood.sh committed-script precedent (shebang, set -u,
# blocker() helper, jq parsing into inert variables, structured stdout routing, exit
# codes).
#
# DETERMINISM CONTRACT (per ADR-0018 + plan §C/§I):
#   1. ledger.state.current MUST equal --state, else blocker + exit 1, ledger UNCHANGED.
#   2. BINDING GUARD: definition.id MUST equal ledger.run.workflow AND definition.version
#      MUST equal ledger.run.workflow_version, else blocker + exit 1, ledger UNCHANGED. The
#      engine HARD-REJECTS a non-binding id/version mismatch and exposes NO rebind. The §I
#      resume gate offers only TWO doors (start fresh / proceed intent-driven); there is NO
#      deterministic-resume door. This guard is a hard-reject — it never reconciles skew.
#   3. --state MUST exist in definition.states (a renamed/removed state never guesses —
#      this is state-existence, NOT version-skew), else blocker + exit 1, UNCHANGED.
#   5. The allowed-result set is read DIRECTLY from definition.states[<state>].transitions
#      (keys). --result MUST be one of those keys, else blocker + exit 1, UNCHANGED.
#   6. next_state = transitions[result]. next_state must be declared in definition.states
#      (its compact definition is printed on success), else blocker + exit 1, UNCHANGED.
#   7. Append an event {at,state,result,next_state,summary,outputs,plan_epoch}. plan_epoch
#      is an ENGINE-WRITTEN top-level int (NOT a free-form outputs rider): every appended
#      event carries it, so a caller can neither forge nor omit it. See item 12.
#   8. Update state.previous=state, state.current=next_state, state.status.
#   9. Update run.updated_at.
#  10. If next_state is a declared terminal, set run.status + state.status to the
#      matching terminal status (complete->complete, blocked->blocked,
#      cancelled->cancelled). The human-intervention terminals
#      (user_input_required, review_rejected, review_exhausted) are "stopped, needs
#      attention" outcomes — they map to blocked (NOT complete) so a stalled run is
#      never masked as success. Genuine done-terminals (e.g. hatchery_monitor) ->
#      complete-equivalent per the schema doc, which constrains run.status to
#      running|complete|blocked|cancelled.
#  11. Write via temp file + atomic mv so a concurrent hatchery reader never sees a
#      torn file.
#
#  12. PLAN EPOCH OWNERSHIP: the engine is the SOLE owner of a monotonic .plan.epoch (int).
#      It is bumped by exactly 1 ONLY when this call replaces plan.steps (have_plan_steps
#      true — which the plan-write authorization guard already restricts to a cerebrate
#      planning state), alongside the .plan.steps / .plan.path clause; otherwise .plan.epoch
#      is left untouched (absent stays absent until the first bump). Every appended event is
#      stamped with the RESOLVED epoch as a top-level plan_epoch (plan-state or not). A
#      pre-existing ledger with no .plan.epoch reads as 0, so a non-plan record stamps
#      plan_epoch 0 and leaves .plan.epoch absent — identical to prior behavior; the first
#      plan.steps replace bumps to 1. have_plan_steps reaches jq ONLY as an ENGINE-DERIVED
#      inert --argjson bool, never as interpolated or caller-supplied text. Rationale:
#      next-wave scopes its done-set by epoch because positional STEP-NNN ids are reused
#      across plan generations (needs_replan re-plans into the same append-only ledger).
#
#  13. PRODUCER AUTHORIZATION (completed_steps): next-wave's done-set unions
#      outputs.completed_steps from every current-epoch event with NO producer check on the
#      reader side. Because item 12 stamps the freshly-bumped epoch on the very plan event
#      that creates a new generation, an outputs.completed_steps rider on a cerebrate
#      plan/replan record would pre-credit the NEW generation and silently skip replan work.
#      The engine closes this at the WRITE boundary: exactly TWO engines append events to the
#      ledger -- this one, which honors a completed_steps rider ONLY when the recording state
#      is a WAVE-PRODUCING agent state (type == "agent" AND declaring an allowed_agents set
#      excluding "hivemind:cerebrate"), and mark-intent-fallback, which strips completed_steps from
#      its fallback event outputs unconditionally; init-run-ledger only creates the ledger and
#      appends nothing. This is SYMMETRIC to the plan-write authorization guard (item 12 /
#      inline guard (6)): that guard restricts plan.* MUTATION to cerebrate planning states;
#      this one restricts completed_steps CREDITING to wave-producing agent states. Both
#      appenders enforce this discipline, ground-truth-derived from the packaged definition
#      (NO hardcoded state list), so an unauthorized credit is UNREPRESENTABLE and the ledger
#      stays byte-unchanged. next-wave therefore remains a pure reader, unchanged.
#
# CRITICAL ATOMICITY: every write is temp-write + atomic rename. On ANY validation
# failure the on-disk ledger is byte-unchanged — no partial write ever occurs (all
# validation runs BEFORE the temp file is created).
#
# CONTRACT CHECKS (issue #424): before any field is read, hivemind_check_json checks the WHOLE
# inputs file against the record-inputs contract, and, once hivemind_open_ledger returns 0, the
# whole canonical ledger against the record-ledger contract (ledger-engine-io.sh). Both run
# inside one constant jq program on the intact JSON values, so no check ever runs on a value a
# lossy `jq -r` read has changed. A failure blocks with a fixed prefix plus the one
# `<position>: <problem>` line, which never holds a value from the file; the ledger is
# unchanged. Every value then read into the shell (inputs run_id, state, result; ledger
# run.workflow, run.workflow_version, state.current) comes through the field form, a checked
# token printed whole. No `jq -r` reads the inputs file or the ledger, and a blocker names
# only checked tokens.
#
# INJECTION POSTURE: the untrusted fields summary, outputs, plan_steps, and plan_path never
# enter the jq program or any shell command source. outputs and plan_steps reach the mutate
# program solely as --argjson bindings of their compact JSON; summary and plan_path are read by
# the mutate program itself from the inputs file (--slurpfile) and never pass through the
# shell. The ONLY value passed on the command line is the trusted inputs-file path.
#
# PATH POSTURE — the engine NEVER accepts a path as input. It DERIVES every path from
# identity, dissolving two trust-boundary P0s (a caller-supplied ledger path enabled an
# arbitrary-file overwrite; a caller-supplied workflow-definition path enabled a forged
# definition that bypassed the transition gate AND the plan-write authorization). The ONLY
# path on the command line is $1, the inputs-file authored by the trusted skill via Write.
#   - The ledger is DERIVED: repo_root="$(git rev-parse --show-toplevel)" then
#     "$repo_root/.hivemind/runs/<run_id>/state.json". <run_id> comes from the inputs file, a
#     name under the record-inputs contract (safe charset, 1 to 255 bytes, not "." or "..").
#   - A COHERENCE CHECK requires the on-disk ledger.run.id to equal the passed run_id.
#   - The workflow DEFINITION is DERIVED from the (trusted) ledger's run.workflow against the
#     script's OWN packaged workflows dir (self-located via BASH_SOURCE + pwd -P, independent
#     of ${CLAUDE_PLUGIN_ROOT} and of any caller value). The caller NEVER supplies this path,
#     so a forged definition can no longer be injected; the binding guard now compares the
#     trusted ledger against the self-derived PACKAGED definition.
#
# INPUT (single positional argument):
#   $1  Absolute or repo-relative path to a JSON inputs file authored by the agent via the
#       Write tool. The agent writes structured data; this script checks it against the
#       record-inputs contract, then reads only checked tokens into shell VARIABLES (the
#       untrusted text stays in jq). Values read into variables are referenced
#       only as "$var" — bash does not re-evaluate command substitution from variable
#       contents, so the command-substitution injection class is structurally absent (the
#       values never enter generated command SOURCE). Mirrors spawn-brood.sh and
#       init-run-ledger.sh; rationale: docs/adr/0017-brood-spawn-mechanism.md amendment.
#
#   Inputs JSON shape (authoritative schema in SKILL.md § Inputs JSON):
#     {
#       "run_id":     "<required> identity of the run; the ledger path is DERIVED from it as
#                      <git-root>/.hivemind/runs/<run_id>/state.json. NO path is accepted.",
#       "state":      "<required name> state the run is currently in (must match ledger)",
#       "result":     "<required name> named outcome to record (must be a legal transition)",
#       "summary":    "<required, non-empty> human-readable summary — UNTRUSTED, serialized
#                      only, read by the mutate program from this file",
#       "outputs":    { ... },   // optional JSON object of named outputs — UNTRUSTED,
#                                // serialized only. KEY-PRESENCE semantics: a MISSING key OR
#                                // a present-but-null value is ABSENT (-> defaults to {}); a
#                                // present non-null value is SUPPLIED.
#       "plan_steps": [ ... ],   // optional cerebrate plan steps as a JSON array. This is the
#                                // PRIMARY, live writer of ledger.plan.steps: the overlord
#                                // supplies it when recording the `plan` state result (after
#                                // cerebrate returns). KEY-PRESENCE semantics: MISSING key OR
#                                // null value is ABSENT (-> .plan.* left UNTOUCHED, never
#                                // clobbered to []); a present non-null value is SUPPLIED ->
#                                // .plan.steps = the array. UNTRUSTED step text — enters jq
#                                // ONLY via --argjson (contract-checked JSON: step objects
#                                // with step-id ids and depends_on entries).
#       "plan_path":  "<optional> path to the cerebrate directive. KEY-PRESENCE semantics: a
#                      MISSING key OR null value is ABSENT (-> .plan.path UNTOUCHED); a present
#                      non-null value is SUPPLIED -> .plan.path = the (nullable) text.
#                      UNTRUSTED — read by the mutate program from this file."
#     }
#
# OUTPUT:
#   - On success: writes the mutated ledger atomically and prints YAML routing lines:
#       previous_state: <state>
#       result: <result>
#       current_state: <next_state>
#       ledger: <path>
#       state_definition: <compact JSON of next_state from the packaged definition>
#     Exits 0. A next_state the definition does not declare is a blocker raised before any
#     write (ledger byte-unchanged).
#   - On any failure / illegal transition: prints `blocker: <reason>` to stderr, exits 1,
#     ledger byte-unchanged.
#
# EXIT CONTRACT:
#   0  transition recorded + ledger advanced
#   1  validation failure / illegal transition (ledger UNCHANGED)
#
# set -u: an unset variable is a programming error (every value is parsed from the inputs
# file). No `set -e`: failures route through blocker() with a verbose reason.
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: `jq -e has(...)`
# key-presence probes legitimately return non-zero in the normal absent-key flow, and
# transition/binding validation feeds blocker() (ledger left byte-unchanged) — `set -e`
# would abort mid-validation.

set -u

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# ── Script self-location (portable; independent of ${CLAUDE_PLUGIN_ROOT} and the caller) ──
# Resolve the packaged workflows dir from THIS script's own location, never from a caller
# value. `cd ... && pwd -P` is portable (no GNU-only readlink -f); BASH_SOURCE is set under
# `#!/usr/bin/env bash`. Layout: plugin/skills/record-state-result/scripts/ => 3 dirs up is
# the plugin root (verified against the real tree).
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve the plugin root from the script directory; refusing to proceed"
workflows_dir="$plugin_root/workflows"

# Source the shared containment helper ONCE, early — it provides both the inputs-file
# READ-guard (hivemind_assert_inputs_contained, used right after the inputs validity
# checks) and the write-chain guard (hivemind_assert_contained, used before the ledger
# temp-write). Sourcing once here keeps a single load point for both call sites below.
# SOURCE-OR-DIE: a missing or unparseable shared library fails closed BEFORE any consumer
# logic — every guard below (the inputs-containment read-guard, the ledger-open chain) lives
# in these libs, so proceeding without them would silently disarm the containment guards.
[ -f "$plugin_root/skills/_shared/containment.sh" ] || blocker "required shared library missing: skills/_shared/containment.sh; refusing to proceed"
. "$plugin_root/skills/_shared/containment.sh" || blocker "failed to source skills/_shared/containment.sh (unparseable); refusing to proceed"

# Source the shared ledger engine-IO helper by the SAME self-located absolute path. It
# provides hivemind_read_inputs_file (the inputs-file bootstrap) and hivemind_open_ledger
# (the depth-complete ledger-read/containment/coherence/post-existence chain). Both functions
# ORCHESTRATE the containment.sh helpers sourced above, so this MUST follow that source.
[ -f "$plugin_root/skills/_shared/ledger-engine-io.sh" ] || blocker "required shared library missing: skills/_shared/ledger-engine-io.sh; refusing to proceed"
. "$plugin_root/skills/_shared/ledger-engine-io.sh" || blocker "failed to source skills/_shared/ledger-engine-io.sh (unparseable); refusing to proceed"

# ── Dependency check ──────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 \
  || blocker "jq is required to read and write the run ledger but is not installed"

# ── Inputs file ───────────────────────────────────────────────────────────────
# Single positional argument: the path to a JSON inputs file the agent authored via the
# Write tool. The path is the ONLY value passed on the command line; every field (including
# the untrusted summary/outputs/plan_steps/plan_path) is checked by the contract below and
# never interpolated into bash source or the jq program SOURCE.
INPUTS_FILE="${1:-}"

# ── Inputs-file bootstrap (shared helper) ──────────────────────────────────────
# hivemind_read_inputs_file performs, IN ORDER: the non-empty-arg check, the `[ -f ]`
# existence check, the hivemind_assert_inputs_contained defense-in-depth read-guard (run
# BEFORE the jq validity probe — `jq -e` on an attacker path is itself a JSON-validity read
# oracle), and the one-object probe (exactly one JSON document, an object). The
# "record-state-result" label reproduces
# this engine's EXACT current blocker strings. The helper never exits and emits NO stderr of
# its own: it signals WHICH failure occurred via a distinct return code (2 missing arg, 3
# missing file, 4 containment reject, 5 not a single JSON object) and we map each to its fixed
# blocker text below. For the containment reject (4) the inner hivemind_assert_inputs_contained helper's own
# UNPREFIXED detail line flows to fd2 UNCAPTURED (we do NOT redirect the call's stderr), so the
# two-line shape — detail line ABOVE our `blocker:` line — is byte-preserved exactly as before
# extraction. The non-containment cases (2/3/5) had no detail line pre-extraction and stay
# single-line.
hivemind_read_inputs_file "$INPUTS_FILE" "record-state-result"
case $? in
  0) : ;;
  2) blocker "missing required argument: path to record-state-result inputs JSON file (\$1)" ;;
  3) blocker "record-state-result inputs file $INPUTS_FILE does not exist" ;;
  4) blocker "refusing to read the inputs file: $INPUTS_FILE resolves outside the checkout (symlinked ancestor)" ;;
  5) blocker "record-state-result inputs file $INPUTS_FILE is not a single JSON object" ;;
  *) blocker "record-state-result: hivemind_read_inputs_file returned an unmapped status (shared library unavailable or contract drift); ledger/inputs unchanged" ;;
esac

# read_contract_field <var_name> <json_file> <contract> <field>
#
# Sets <var_name> to the value hivemind_check_json prints for <field> of <contract> (empty when
# the field is absent). Every field it reads is a checked token kind, so the printed line is the
# whole value. The whole-file check has already passed before any call, so a non-zero status is
# a tool failure: blocker (the helper's own reason line is already on stderr).
read_contract_field() {
  local var_name="$1" json_file="$2" contract_name="$3" field_name="$4" field_value
  field_value="$(hivemind_check_json "$json_file" "$contract_name" "$field_name")" \
    || blocker "record-state-result: hivemind_check_json could not read $field_name under the $contract_name contract; ledger unchanged"
  printf -v "$var_name" '%s' "$field_value"
}

# ── Inputs contract check (BEFORE any field is read) ──────────────────────────
# hivemind_check_json checks the WHOLE inputs file against the record-inputs contract inside
# one constant jq program, on the intact JSON values: run_id / state / result are names,
# summary is non-empty text, outputs (when present) is an object and outputs.completed_steps an
# array, plan_steps (when present) is a list of step objects with step-id ids and depends_on
# entries, plan_path is text. A failure prints one `<position>: <problem>` line that never holds
# a value from the file; only that stdout is captured, so a rc-2 reason line stays on stderr.
inputs_check_line="$(hivemind_check_json "$INPUTS_FILE" record-inputs)"
case $? in
  0) : ;;
  1) blocker "record-state-result inputs file: $inputs_check_line; ledger unchanged" ;;
  *) blocker "record-state-result: hivemind_check_json could not check the inputs file; ledger unchanged" ;;
esac

# ── Parse fields into inert variables ─────────────────────────────────────────
# run_id / state / result are read through the record-inputs field form: each is a checked
# name, so the printed line is the whole value and nothing is lost to a `jq -r` read. summary
# and plan_path are never read into the shell: the mutate program takes them from the inputs
# file itself (--slurpfile). The presence bools derive from KEY-PRESENCE on the inputs object:
# a MISSING key OR a present-but-null value is ABSENT; a present non-null value is SUPPLIED.
# Absent outputs defaults to {}; absent plan_steps/plan_path leaves .plan.* UNTOUCHED (never
# clobbered to []).
read_contract_field run_id "$INPUTS_FILE" record-inputs run_id
read_contract_field state "$INPUTS_FILE" record-inputs state
read_contract_field result "$INPUTS_FILE" record-inputs result

# outputs: key present AND non-null -> the compact JSON value (an object, by the contract) for
# the --argjson serialization; absent -> {}.
if jq -e 'has("outputs") and .outputs != null' "$INPUTS_FILE" >/dev/null 2>&1; then
  outputs="$(jq -c '.outputs' "$INPUTS_FILE")"
else
  outputs='{}'
fi

# have_plan_steps: plan_steps key present AND non-null (-> .plan.steps written). Absent ->
# .plan.* left untouched. UNTRUSTED step text reaches jq ONLY via --argjson below.
if jq -e 'has("plan_steps") and .plan_steps != null' "$INPUTS_FILE" >/dev/null 2>&1; then
  have_plan_steps=true
  plan_steps="$(jq -c '.plan_steps' "$INPUTS_FILE")"
else
  have_plan_steps=false
  plan_steps=""
fi

# have_plan_path: plan_path key present AND non-null (-> .plan.path written). Absent ->
# .plan.path left untouched. UNTRUSTED — the mutate program reads it from the inputs file.
if jq -e 'has("plan_path") and .plan_path != null' "$INPUTS_FILE" >/dev/null 2>&1; then
  have_plan_path=true
else
  have_plan_path=false
fi

# ── DERIVE the ledger path from git-root + run_id (NO caller path) ─────────────
# repo_root anchors the ledger to the checkout root, mirroring init-run-ledger.sh. Empty =
# not inside a git checkout = blocker. The caller never supplies a ledger path, so an
# arbitrary-file overwrite via a caller path is structurally impossible.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$repo_root" ] || blocker "not inside a git repository"
# Raw textual ledger path (matches the prior inline derivation), used to derive the canonical
# ledger dir and in the open-failure blockers. The contract check and every ledger field read
# below use the CANONICAL path; the containment guards inside hivemind_open_ledger proved that
# the raw path and its canonical form resolve to the same in-checkout file. The atomic-write
# block below re-points $ledger at the CANONICAL path before any mktemp/mv.
ledger="$repo_root/.hivemind/runs/$run_id/state.json"

# ── Ledger-open machinery (shared helper) — BEFORE any ledger read ─────────────
# hivemind_open_ledger performs, IN THIS EXACT ORDER (a reordering silently breaks engine
# determinism): ledger-path derivation, the hivemind_assert_contained ancestor guard, the
# canonical-runs-dir canonicalization + trailing-slash prefix case-guard, the
# hivemind_assert_ledger_contained leaf guard (rejects a symlinked state.json LEAF), the
# `[ -f ]` existence + `jq -e .` validity reads, the coherence check (`.run.id == run_id`),
# and the post-existence canonical ledger-dir confirmation (canon dir + state.json/run_id
# basename asserts). On SUCCESS it returns 0 with NO stdout — containment/coherence are
# proven by the return code alone, so the consumer DERIVES the canonical paths locally in
# the 0) arm below. The helper never exits. Two failure shapes (byte-preserved):
#   - inner-helper containment rejects (return 2 = ancestor guard, 6 = leaf guard): the inner
#     helper's UNPREFIXED detail line flows to fd2 UNCAPTURED (we capture only STDOUT, never
#     `2>&1`), then we add our OWN fixed `blocker:` line below — the two-line shape.
#   - every other failure (return 1): the helper PRINTS the single reason line to STDOUT, which
#     we capture and re-emit through blocker() (adding the `blocker: ` prefix) — single-line.
# The return-1 reason is the ONLY stdout the helper ever emits, so the one stdout capture
# (single-value channel) serves the *) failure arm.
# (containment.sh + the helper were sourced once early, just after plugin_root is computed.)
ledger_open_out="$(hivemind_open_ledger "$repo_root" "$run_id")"
ledger_open_rc=$?
case $ledger_open_rc in
  0)
    # Containment/coherence proven by return 0. DERIVE the canonical paths LOCALLY now —
    # ONLY in this arm, AFTER the wrapper validated the path (never canonicalize an
    # unvalidated path). This mirrors EXACTLY what the lib used to compute on success:
    # canon dir via `cd "$(dirname "$ledger")" && pwd -P`, then state.json beneath it.
    # FAIL-CLOSED: these scripts run without `set -e`, so a `cd` that fails (e.g. the run dir
    # vanished between the helper's post-existence confirmation and this derivation) would
    # otherwise leave canon_ledger_dir EMPTY and fall through to mktemp under "/". Guard the
    # status AND emptiness here, mirroring hivemind_open_ledger's own `[ -z ]` check, so an
    # empty/failed derivation can never reach the atomic mktemp/mv.
    if ! canon_ledger_dir="$(cd "$(dirname "$ledger")" && pwd -P)" || [ -z "$canon_ledger_dir" ]; then
      blocker "failed to canonicalize the ledger directory; ledger unchanged"
    fi
    canon_ledger="$canon_ledger_dir/state.json"
    ;;
  2) blocker "refusing: ${repo_root}/.hivemind/runs/$run_id resolves outside the checkout (symlinked ancestor or leaf); ledger unchanged" ;;
  6) blocker "refusing to read the ledger: $ledger resolves outside the checkout (symlinked ancestor or leaf); ledger unchanged" ;;
  *) blocker "$ledger_open_out" ;;
esac

# ── Ledger contract check (on the CANONICAL ledger, BEFORE any field is read) ──
# hivemind_check_json checks the whole ledger against the record-ledger contract: run.id,
# run.workflow and state.current are names, run.workflow_version is a whole number of 0 or
# more. The ledger is trusted; this is defense in depth, and it means every ledger value this
# engine reads below is a checked token read losslessly through the field form.
ledger_check_line="$(hivemind_check_json "$canon_ledger" record-ledger)"
case $? in
  0) : ;;
  1) blocker "record-state-result ledger: $ledger_check_line; ledger unchanged" ;;
  *) blocker "record-state-result: hivemind_check_json could not check the ledger; ledger unchanged" ;;
esac
read_contract_field run_workflow "$canon_ledger" record-ledger run.workflow
read_contract_field ledger_wf_version "$canon_ledger" record-ledger run.workflow_version
read_contract_field ledger_current "$canon_ledger" record-ledger state.current

# ── DERIVE the workflow definition from the (trusted) ledger's run.workflow ────
# The definition is resolved against the self-located PACKAGED workflows dir, never a caller
# path — so a forged definition cannot bypass the transition gate or the plan-write auth.
# run.workflow is a checked name (not "." or ".."), so it is one safe path component.
workflow="$workflows_dir/$run_workflow.json"
[ -f "$workflow" ] || blocker "packaged workflow definition does not exist: $workflow"
jq -e . "$workflow" >/dev/null 2>&1 || blocker "workflow definition is not valid JSON: $workflow"

# ── Deterministic validation (ALL before any write) ───────────────────────────
# (1) ledger.state.current must equal --state.
[ "$ledger_current" = "$state" ] \
  || blocker "ledger state.current '$ledger_current' does not match --state '$state'; ledger unchanged"

# Workflow id for clear error messages and the definition<->ledger binding guard.
workflow_id="$(jq -r '.id // ""' "$workflow")"

# (2) BINDING GUARD: the supplied definition MUST bind to this ledger. The engine
# HARD-REJECTS a non-binding definition (exit 1, ledger byte-unchanged); it does NOT
# attempt to reconcile. Version-skew reconciliation is owned by the overlord resume-on-start
# gate's two doors (start fresh / proceed intent-driven), NOT here. There is NO
# deterministic-resume door — the engine exposes no rebind surface.
# These checks run BEFORE the state-existence check and BEFORE any temp-file creation, so a
# binding failure never mutates a byte of the on-disk ledger.
#   (2a) definition.id == ledger.run.workflow.
[ "$workflow_id" = "$run_workflow" ] \
  || blocker "workflow definition id '$workflow_id' does not match ledger run.workflow '$run_workflow'; ledger unchanged"
#   (2b) definition.version == ledger.run.workflow_version (engine hard-reject half of the
#   §I policy; the overlord resume gate owns the two version-skew doors).
def_version="$(jq -r '.version // empty' "$workflow")"
[ "$def_version" = "$ledger_wf_version" ] \
  || blocker "workflow definition version '$def_version' does not match ledger run.workflow_version '$ledger_wf_version'; ledger unchanged (resume gate owns version-skew doors)"

# (3) --state must exist in definition.states (named state must exist in the definition;
# a renamed/removed state is never guessed). This is state-existence, NOT version-skew.
state_exists="$(jq --arg s "$state" '.states | has($s)' "$workflow")"
[ "$state_exists" = "true" ] \
  || blocker "state '$state' not found in workflow '$workflow_id'"

# (4) read the allowed-set DIRECTLY from definition.states[state].transitions; --result
# must be a key. The model never supplies this set.
result_valid="$(jq --arg s "$state" --arg r "$result" \
  '(.states[$s].transitions // {}) | has($r)' "$workflow")"
[ "$result_valid" = "true" ] \
  || blocker "result '$result' not valid from state '$state'"

# (5) resolve next_state.
next_state="$(jq -r --arg s "$state" --arg r "$result" \
  '.states[$s].transitions[$r]' "$workflow")"
[ -n "$next_state" ] && [ "$next_state" != "null" ] \
  || blocker "transition '$result' from state '$state' resolves to an empty target"

# (5b) read next_state's own definition (compact JSON) for the success output, so the caller
# needs no read of the definition file. Before mktemp or any write: a target the definition
# does not declare is a blocker with the ledger byte-unchanged. A jq failure leaves the value
# empty and blocks the same way.
next_state_definition="$(jq -c --arg n "$next_state" '.states[$n] // null' "$workflow" 2>/dev/null)"
[ -n "$next_state_definition" ] && [ "$next_state_definition" != "null" ] \
  || blocker "transition '$result' from state '$state' targets '$next_state', which workflow '$workflow_id' does not declare; ledger unchanged"

# (6) PLAN-WRITE AUTHORIZATION: --plan-steps / --plan-path may ONLY be honored when the
# state being recorded is a cerebrate planning state (definition.states[<state>].agent ==
# "hivemind:cerebrate"). This authorizes exactly the cerebrate agent states (plan /
# review_remediation_plan / brood_plan) and forbids every other state from mutating the
# plan — flag PRESENCE alone is NOT sufficient. This guard runs BEFORE mktemp and the
# temp-write, so a rejection leaves the on-disk ledger byte-unchanged. The untrusted plan
# values still reach jq solely via --arg/--argjson; here only the engine-validated $state
# (an existing definition key) is interpolated into the message.
if [ "$have_plan_steps" = true ] || [ "$have_plan_path" = true ]; then
  state_agent="$(jq -r --arg s "$state" '.states[$s].agent // ""' "$workflow")"
  [ "$state_agent" = "hivemind:cerebrate" ] \
    || blocker "plan steps may only be written from a cerebrate planning state; state '$state' (agent '$state_agent') is not authorized; ledger unchanged"
fi

# (7) PRODUCER AUTHORIZATION for outputs.completed_steps: a completed_steps rider inside
# --outputs may ONLY be honored when the recording state is a WAVE-PRODUCING agent state — an
# actual step-executing producer that DECLARES an allowed_agents set. allowed_agents is the
# ground-truth discriminator: it is present ONLY at the wave implement states (implement_step
# / implement_step_postpr / the remediation wave state), always ["hivemind:drone",
# "hivemind:changeling"], and NEVER at cerebrate or singular-agent states (version_bump,
# reviewer states use a SINGULAR agent key), so has("allowed_agents") cleanly selects the
# wave-producer set. The belt clause (allowed_agents excludes "hivemind:cerebrate") preserves
# cerebrate-exclusion even if a future def were to add cerebrate to an allowed set. This is
# SYMMETRIC to the plan-write auth guard (6): where (6) restricts plan.* MUTATION to cerebrate
# planning states, (7) restricts completed_steps CREDITING to wave-producing states.
# Rationale: next-wave unions outputs.completed_steps from every current-epoch event with NO
# producer check, and this engine stamps the freshly-bumped epoch on the very plan event that
# creates the epoch — so a completed_steps rider on a cerebrate plan/replan record would
# pre-credit the NEW generation and silently skip replan work. This guard, together with
# mark-intent-fallback stripping completed_steps from its fallback event outputs
# unconditionally (init-run-ledger only creates the ledger and appends nothing), closes this
# at the WRITE boundary: because BOTH event appenders enforce this discipline, an unauthorized
# credit is UNREPRESENTABLE in the ledger; next-wave stays a pure reader. The predicate is
# GROUND-TRUTH-derived from the packaged definition (type + allowed_agents) — NO hardcoded
# state-name list. KEY-PRESENCE: a missing OR null completed_steps is ABSENT (guard inert).
# This guard runs BEFORE mktemp/temp-write, so a rejection leaves the ledger byte-unchanged;
# only the engine-validated $state (an existing definition key) is interpolated into the
# message — never raw untrusted text.
if printf '%s' "$outputs" | jq -e 'has("completed_steps") and .completed_steps != null' >/dev/null 2>&1; then
  producer_authorized="$(jq -r --arg s "$state" '
    (.states[$s].type == "agent")
    and (.states[$s] | has("allowed_agents"))
    and (.states[$s].allowed_agents | index("hivemind:cerebrate") | not)' "$workflow")"
  [ "$producer_authorized" = "true" ] \
    || blocker "outputs.completed_steps may only be recorded from a wave-producing agent state (one declaring allowed_agents without hivemind:cerebrate); state '$state' is not authorized; ledger unchanged"
fi

# (10 pre-compute) determine whether next_state is a declared terminal and map its
# run/state status. The schema constrains run.status to running|complete|blocked|
# cancelled. The human-intervention terminals (user_input_required, review_rejected,
# review_exhausted) are "stopped, needs attention" outcomes and map to blocked — NOT
# complete — so a stalled run is never masked as success. Only genuine done-terminals
# (e.g. complete, hatchery_monitor) are complete-equivalent.
is_terminal="$(jq --arg n "$next_state" '(.terminal // []) | index($n) != null' "$workflow")"
if [ "$is_terminal" = "true" ]; then
  case "$next_state" in
    blocked)   terminal_status="blocked" ;;
    cancelled) terminal_status="cancelled" ;;
    user_input_required|review_rejected|review_exhausted) terminal_status="blocked" ;;
    *)         terminal_status="complete" ;;
  esac
  run_status="$terminal_status"
  state_status="$terminal_status"
else
  run_status="running"
  state_status="running"
fi

now_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── Atomic write: temp file beside the ledger, then mv into place ──────────────
# Use the CANONICAL (verified-contained) dir for the temp-write + atomic rename so both
# operate on the path that passed containment, not the raw textual one.
ledger_dir="$canon_ledger_dir"
ledger="$canon_ledger"
tmp_ledger="$(mktemp "$ledger_dir/.state.json.XXXXXX")" \
  || blocker "failed to create temp ledger file under $ledger_dir"

# Mutate via a single jq program. Untrusted outputs / plan_steps enter ONLY as --argjson
# bindings; untrusted summary / plan_path are read by the program itself from the inputs file
# (--slurpfile, the intact JSON values, never through the shell); the structural values (state,
# result, next_state, statuses, timestamp) are engine-validated. The plan.* clauses are
# appended to the program ONLY when their flags are present — flag PRESENCE (an inert
# bool), never the untrusted VALUE, decides which clauses run; the values themselves still
# arrive solely as jq data. When a flag is absent the corresponding plan.*
# field is left untouched (NOT clobbered). The engine-owned .plan.epoch is bumped (and
# .plan.epoch set) ONLY inside the have_plan_steps clause; every appended event is stamped
# with the resolved $epoch regardless. have_plan_steps is passed as an ENGINE-DERIVED inert
# --argjson bool (never caller text). INVARIANT: the input ledger is the file itself; on a
# jq failure the temp file is removed and the on-disk ledger is untouched.
plan_program=""
if [ "$have_plan_steps" = true ]; then
  plan_program="$plan_program
  | .plan.steps = \$plan_steps
  | .plan.epoch = \$epoch"
fi
if [ "$have_plan_path" = true ]; then
  plan_program="$plan_program
  | .plan.path = (if \$inputs_doc[0].plan_path == \"\" then null else \$inputs_doc[0].plan_path end)"
fi

jq \
  --arg at "$now_ts" \
  --arg state "$state" \
  --arg result "$result" \
  --arg next_state "$next_state" \
  --slurpfile inputs_doc "$INPUTS_FILE" \
  --argjson outputs "$outputs" \
  --arg run_status "$run_status" \
  --arg state_status "$state_status" \
  --argjson plan_steps "${plan_steps:-[]}" \
  --argjson have_plan_steps "$have_plan_steps" \
  '
  (.plan.epoch // 0) as $cur_epoch
  | (if $have_plan_steps then $cur_epoch + 1 else $cur_epoch end) as $epoch
  | .events += [{
    at: $at,
    state: $state,
    result: $result,
    next_state: $next_state,
    summary: $inputs_doc[0].summary,
    outputs: $outputs,
    plan_epoch: $epoch
  }]
  | .state.previous = $state
  | .state.current = $next_state
  | .state.status = $state_status
  | .run.status = $run_status
  | .run.updated_at = $at'"$plan_program"'
  ' "$ledger" > "$tmp_ledger" \
  || { rm -f "$tmp_ledger"; blocker "failed to serialize the mutated ledger with jq; on-disk ledger unchanged"; }

mv -f "$tmp_ledger" "$ledger" \
  || { rm -f "$tmp_ledger"; blocker "failed to atomically install the mutated ledger at $ledger; on-disk ledger unchanged"; }

# ── Success routing ───────────────────────────────────────────────────────────
printf 'previous_state: %s\n' "$state"
printf 'result: %s\n' "$result"
printf 'current_state: %s\n' "$next_state"
printf 'ledger: %s\n' "$ledger"
printf 'state_definition: %s\n' "$next_state_definition"
exit 0
