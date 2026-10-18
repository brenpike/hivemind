#!/usr/bin/env bash
#
# Workflow-definition structural validator for the hivemind plugin (plan §J.1).
#
# Validates every workflow definition under plugin/workflows/*.json against the
# v1 contract in ${CLAUDE_PLUGIN_ROOT}/references/workflow-state-machine.md, and
# structurally validates the run-ledger JSON shape of every ledger fixture under
# tests/engine/ against ${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md.
#
# Per workflow definition, asserts:
#   - valid JSON
#   - top-level keys id, version, start present
#   - start exists in .states
#   - every transition target is a declared state
#   - every NON-terminal state has a .transitions object (a JSON object)
#   - every declared terminal exists in .states with type "terminal"
#   - (inverse) every terminal-typed state appears in the .terminal array
#   - only v1 state types are used: decision|agent|skill|user_gate|terminal
#
# Per ledger fixture, asserts the required run-ledger fields exist with the right
# shape (schema_version, run.{id,workflow,workflow_version,status,mode}, state.current,
# events array, blockers array, etc.).
#
# Per the decision-autonomy table (${CLAUDE_PLUGIN_ROOT}/references/decision-autonomy-table.json),
# asserts every row binds to decision sites that exist, checked against the UNION of
# states and per-state transition keys across plugin/workflows/*.json. Contract per
# ${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md (Autonomy Level):
#   - R1 every rows[] entry has resolved_at as a non-empty array of strings
#   - R2 each entry's site (text before the first '.') is a declared state in some
#        workflow or a reserved site (AUTONOMY_RESERVED_SITES)
#   - R3 a reserved site carries no outcome part
#   - R4 an entry's outcome (text after the first '.') is a transition key of that
#        state in at least one workflow declaring it
#   - R5 no hard_stops entry carries resolved_at
#   - R6 (inverse) every outcome of a cerebrate PLANNING-mode state whose target is
#        neither a declared terminal nor a user_gate state is bound by some row naming
#        exactly "<state>.<outcome>" (a bare-state binding does not count)
#   - R7 no decision site is named by more than one row; a state and each of its
#        outcomes are distinct sites
#   - R8 no row binding a pre-ledger site (a reserved site, or a state of a workflow
#        whose id is in AUTONOMY_PRE_LEDGER_WORKFLOWS) carries an "auto" cell at any
#        of the table's .levels; a listed workflow id no definition declares fails
# A missing or unparseable table fails; it is never skipped. Honest limit: these rules
# prove sites EXIST, that each names at most one kind, and that no pre-ledger site is
# auto-disposed, not that the kind is semantically right, and the
# inverse rule covers cerebrate planning states only — other decision sites can still
# go unbound without failing here.
# Recorded residual: docs/adr/0034-autonomy-levels-and-decision-briefs.md (Decision 11).
#
# Exit 0 when all definitions and fixtures pass. Non-zero with a clear per-file /
# per-rule message on any failure.
#
# Usage:
#   ./tools/validate_workflows.sh
#   ./tools/validate_workflows.sh --strict
#   ./tools/validate_workflows.sh --self-test
#
# --strict is accepted for parity with tools/policy_check.sh; this validator has no
# advisory findings (every rule is a hard structural invariant), so --strict and the
# default mode behave identically: any failure exits non-zero. The flag exists so CI
# and contributors can invoke this validator with the same discipline as the others.
#
# --self-test runs each deliberately-broken fixture under tests/workflow-defs/broken/
# through the same validation rules and asserts that EACH is rejected (proving the
# validator catches dangling targets, missing start, undeclared terminal, bad state
# type, and non-object transitions). It also confirms the known-good fixture under
# tests/workflow-defs/valid/ passes. It then runs each deliberately-broken autonomy
# table under tests/workflow-defs/autonomy-broken/ through validate_autonomy_bindings
# and asserts EACH is rejected, with the real decision-autonomy table as the positive
# control that MUST pass. Exit 0 only if every broken fixture is rejected and every
# valid fixture (and the real table) passes.

set -euo pipefail

# ── Argument parsing ────────────────────────────────────────────────────────

STRICT=false
SELF_TEST=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict|-Strict)
            STRICT=true
            shift
            ;;
        --self-test)
            SELF_TEST=true
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

# ── Path setup ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="$REPO_ROOT/plugin/workflows"
ENGINE_FIXTURES_DIR="$REPO_ROOT/tests/engine"
AUTONOMY_TABLE_FILE="$REPO_ROOT/plugin/references/decision-autonomy-table.json"

# ── Dependency check ──────────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq is required to validate workflow definitions but is not installed" >&2
    exit 2
fi

# v1 legal state types (workflow-state-machine.md → V1 state types).
V1_STATE_TYPES='["decision","agent","skill","user_gate","terminal"]'

# ── Producer-to-workflow contract vocabularies ──────────────────────────────────
#
# Source of truth — the producer exit_reason vocabularies these reviewer states
# must fully map. Keys are the EXACT producer exit_reason strings (hyphen form,
# = what the overlord passes as --result). If a producer emits an outcome that a
# reviewer state does not declare as a transition key, the workflow cannot route
# that outcome and the run would dead-end. This contract check fails on any such
# gap. Keep these arrays in lockstep with the producer files:
#   - LOCAL_REVIEWER_SET : plugin/agents/local-reviewer.md (Output Contract exit_reason)
#                          NOTE: fix_commits_exist is a scalar field, NOT an
#                          exit_reason — it is intentionally absent here.
#   - REVIEW_LOOP_SET    : plugin/skills/github-review-loop/SKILL.md (terminal exit_reason)
#   - REVIEWER_FIX_SET   : plugin/agents/github-reviewer.md (fix-mode Output Contract exit_reason)
#   root-cluster-suspected is emitted by all three reviewer producers and routes to
#   the planner (remediation plan) like planner-escalation. merge-advised is a
#   github-reviewer producer outcome (emitted in both loop and fix mode): it routes to
#   the merge_advised terminal from BOTH github_review_loop (REVIEW_LOOP_SET) and
#   github_reviewer_fix (REVIEWER_FIX_SET). It is absent from LOCAL_REVIEWER_SET because
#   local-reviewer does not emit merge-advised. watch-window-elapsed is a
#   github_review_loop-only outcome: a QUIET IDLE WINDOW elapsing with no new review
#   activity, routed to the review_window_elapsed done-terminal. It is DISTINCT from
#   max-cycles-reached, which remains the real remediation-cycle ceiling — the idle
#   window and the cycle count are independent bounds.
LOCAL_REVIEWER_SET=(clean max-iterations-reached break-fix-break diminishing-returns injection-suspect user-input-required planner-escalation root-cluster-suspected high-severity-rejection blocked)
REVIEW_LOOP_SET=(clean pr-merged pr-closed max-cycles-reached watch-window-elapsed planner-escalation root-cluster-suspected merge-advised blocked injection-suspect high-severity-rejection user-input-required)
REVIEWER_FIX_SET=(clean injection-suspect user-input-required planner-escalation root-cluster-suspected high-severity-rejection merge-advised blocked)

# CEREBRATE_PLANNING_SET / CEREBRATE_ANALYSIS_SET : cerebrate's two output-mode
# vocabularies.
#   Source of truth = plugin/agents/cerebrate.md
#     - PLANNING mode (Plan Result Mapping):    single multi brood open_questions blocked
#     - ANALYSIS mode (Analysis Result Mapping): complete open_questions blocked
# Cerebrate has TWO output modes. In PLANNING mode it produces a directive and emits
# a delivery mode (single/multi/brood); in ANALYSIS mode it performs read-only
# analysis with no implementation, so delivery modes are meaningless and it emits
# "complete" instead. EVERY state whose .agent == "hivemind:cerebrate" (in any
# workflow) MUST declare transition keys that are a SUPERSET of EITHER the PLANNING
# set OR the ANALYSIS set, because the engine hard-rejects any undeclared outcome —
# leaving a successful plan/analysis with no legal transition. A state that
# satisfies NEITHER set (e.g. {complete, blocked} — missing open_questions for the
# analysis set and missing single/multi/brood for the planning set) is rejected.
# This is applied by AUTO-DISCOVERY (see validate_cerebrate_contract), not via a
# hardcoded state-name row, so future cerebrate states are covered automatically.
CEREBRATE_PLANNING_SET=(single multi brood open_questions blocked)
CEREBRATE_ANALYSIS_SET=(complete open_questions blocked)

# AUTONOMY_RESERVED_SITES : decision sites a decision-autonomy row may bind that are
# NOT workflow states. Hard-coded here because the table's data cannot authorize its
# own sites. Source of truth: plugin/agents/overlord.md (## Resume On Start) for
# resume_on_start.
AUTONOMY_RESERVED_SITES=(resume_on_start)

# AUTONOMY_PRE_LEDGER_WORKFLOWS : ids of workflows whose states, with the reserved
# sites, are the pre-ledger decision sites R8 checks.
# Source of truth: ${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md (Decision Journal)
AUTONOMY_PRE_LEDGER_WORKFLOWS=(workflow-router)

# Contract rows: "<state-name>:<set-var-name>". A reviewer state with the given
# name in a workflow definition must declare every outcome in the named set as a
# transition key. State names are matched only when present in the definition, so
# the same row table applies to both real definitions and contract-class fixtures.
CONTRACT_ROWS=(
    "local_review:LOCAL_REVIEWER_SET"
    "github_review_loop:REVIEW_LOOP_SET"
    "github_reviewer_fix:REVIEWER_FIX_SET"
)

# ── State ─────────────────────────────────────────────────────────────────────

FAILURES=0

fail() {
    # fail <file-label> <message>
    echo "FAIL [$1] $2"
    FAILURES=$((FAILURES + 1))
}

# ── Workflow definition validation ─────────────────────────────────────────────

validate_workflow_definition() {
    local def_file="$1"
    local label
    label="${def_file#"$REPO_ROOT"/}"
    local file_failures_before="$FAILURES"

    # Rule: valid JSON.
    if ! jq -e . "$def_file" >/dev/null 2>&1; then
        fail "$label" "not valid JSON"
        return
    fi

    # Rule: top-level id, version, start present.
    local has_id has_version has_start
    has_id="$(jq -r 'has("id")' "$def_file")"
    has_version="$(jq -r 'has("version")' "$def_file")"
    has_start="$(jq -r 'has("start")' "$def_file")"
    [[ "$has_id" == "true" ]]      || fail "$label" "missing top-level key: id"
    [[ "$has_version" == "true" ]] || fail "$label" "missing top-level key: version"
    [[ "$has_start" == "true" ]]   || fail "$label" "missing top-level key: start"

    # Rule: .states must be an object (everything below depends on it).
    local states_type
    states_type="$(jq -r '.states | type' "$def_file" 2>/dev/null || echo "null")"
    if [[ "$states_type" != "object" ]]; then
        fail "$label" "missing or non-object .states map"
        return
    fi

    # Rule: start exists in .states (only when start is present).
    if [[ "$has_start" == "true" ]]; then
        local start_name start_in_states
        start_name="$(jq -r '.start' "$def_file")"
        start_in_states="$(jq -r --arg s "$start_name" '.states | has($s)' "$def_file")"
        [[ "$start_in_states" == "true" ]] \
            || fail "$label" "start state '$start_name' is not declared in .states"
    fi

    # Rule: only v1 state types are used.
    local bad_types
    bad_types="$(jq -r --argjson allowed "$V1_STATE_TYPES" '
        [.states | to_entries[]
         | select((.value.type // "<missing>") as $t | ($allowed | index($t)) == null)
         | "\(.key)=\(.value.type // "<missing>")"]
        | join(", ")
    ' "$def_file")"
    [[ -z "$bad_types" ]] \
        || fail "$label" "state(s) with unsupported type (allowed: decision|agent|skill|user_gate|terminal): $bad_types"

    # Rule: every NON-terminal state has a .transitions object.
    local missing_transitions
    missing_transitions="$(jq -r '
        [.states | to_entries[]
         | select((.value.type // "") != "terminal")
         | select((.value.transitions | type) != "object")
         | .key]
        | join(", ")
    ' "$def_file")"
    [[ -z "$missing_transitions" ]] \
        || fail "$label" "non-terminal state(s) missing a transitions object: $missing_transitions"

    # Rule: every transition target is a declared state.
    local dangling_targets
    dangling_targets="$(jq -r '
        . as $wf
        | [.states | to_entries[]
           | .key as $from
           | (if (.value.transitions | type) == "object" then .value.transitions else {} end)
           | to_entries[]
           | .key as $outcome
           | .value as $target
           | select(($wf.states | has($target)) | not)
           | "\($from).\($outcome)->\($target)"]
        | join(", ")
    ' "$def_file")"
    [[ -z "$dangling_targets" ]] \
        || fail "$label" "transition target(s) point to undeclared states: $dangling_targets"

    # Rule: every declared terminal exists in .states with type "terminal".
    # (.terminal is optional structurally, but when present each name must resolve.)
    local bad_terminals
    bad_terminals="$(jq -r '
        . as $wf
        | [(.terminal // [])[]
           | select(($wf.states[.].type // "") != "terminal")
           | .]
        | join(", ")
    ' "$def_file")"
    [[ -z "$bad_terminals" ]] \
        || fail "$label" "declared terminal(s) absent from .states or not type terminal: $bad_terminals"

    # Rule (inverse): every state whose type is "terminal" MUST appear in .terminal.
    # The forward rule above only proves listed names resolve; without this inverse
    # rule a state with { "type": "terminal" } omitted from .terminal passes here yet
    # the runtime engine (record-state-result.sh determines completion from .terminal)
    # never marks the run complete — it leaves run.status: running and resume scans
    # keep rediscovering the finished run.
    local unlisted_terminals
    unlisted_terminals="$(jq -r '
        (.terminal // []) as $declared
        | [.states | to_entries[]
           | select((.value.type // "") == "terminal")
           | .key as $name
           | select(($declared | index($name)) == null)
           | $name]
        | join(", ")
    ' "$def_file")"
    [[ -z "$unlisted_terminals" ]] \
        || fail "$label" "terminal-typed state(s) omitted from .terminal array: $unlisted_terminals"

    if [[ "$FAILURES" -eq "$file_failures_before" ]]; then
        echo "PASS [$label] workflow definition valid"
    fi
}

# ── Producer-to-workflow contract validation ────────────────────────────────────
#
# For each contract row, if the workflow declares the named reviewer state, assert
# every producer outcome in the row's set is a transition key of that state. Fails
# (increments FAILURES) on any unmapped producer outcome. This is the check that
# would have caught F1: a reviewer state whose transition keys diverge from the
# producer's emitted exit_reason vocabulary.
#
# It also performs the INVERSE terminal-coverage check: for each producer-state
# transition whose target is a declared terminal, the outcome key MUST appear in
# that state's producer set. A producer state cannot route to an advisory terminal
# via an outcome the set omits — that would mean the terminal is reachable only via
# a producer set out of lockstep with the workflow (the exact merge-advised gap that
# motivated #163/#177). This reuses the same CONTRACT_ROWS traversal and resolved set.
validate_producer_contract() {
    local def_file="$1"
    local label
    label="${def_file#"$REPO_ROOT"/}"
    local file_failures_before="$FAILURES"

    # Skip non-JSON — structural validation already reports that.
    if ! jq -e . "$def_file" >/dev/null 2>&1; then
        return
    fi

    local row state_name set_var
    for row in "${CONTRACT_ROWS[@]}"; do
        state_name="${row%%:*}"
        set_var="${row##*:}"

        # Only check states that actually exist in this definition.
        local state_present
        state_present="$(jq -r --arg s "$state_name" '.states | has($s)' "$def_file" 2>/dev/null || echo "false")"
        [[ "$state_present" == "true" ]] || continue

        # Resolve the named set into a local array (indirect expansion).
        local -n producer_set="$set_var"

        local outcome present
        for outcome in "${producer_set[@]}"; do
            present="$(jq -r --arg st "$state_name" --arg o "$outcome" \
                '(.states[$st].transitions // {}) | has($o)' "$def_file" 2>/dev/null || echo "false")"
            [[ "$present" == "true" ]] \
                || fail "$label" "producer-contract violation: state '$state_name' does not declare producer outcome '$outcome' (set $set_var) as a transition key"
        done

        # INVERSE terminal-coverage: every producer-state transition whose target is
        # a declared terminal MUST be keyed by an outcome present in this producer set.
        local set_json terminal_outcomes uncovered
        set_json="$(printf '%s\n' "${producer_set[@]}" | jq -R . | jq -s .)"
        # Outcomes on this state that route to a declared terminal.
        terminal_outcomes="$(jq -r --arg st "$state_name" '
            (.terminal // []) as $declared
            | [(.states[$st].transitions // {}) | to_entries[]
               | .key as $k | .value as $tgt
               | select(($declared | index($tgt)) != null)
               | $k]
            | .[]
        ' "$def_file" 2>/dev/null || true)"
        while IFS= read -r outcome; do
            [[ -n "$outcome" ]] || continue
            uncovered="$(jq -rn --argjson set "$set_json" --arg o "$outcome" \
                '($set | index($o)) == null')"
            [[ "$uncovered" == "true" ]] \
                && fail "$label" "terminal-coverage violation: state '$state_name' routes outcome '$outcome' to a declared terminal but '$outcome' is absent from its producer set ($set_var) — set is out of lockstep with the workflow"
        done <<< "$terminal_outcomes"
    done

    if [[ "$FAILURES" -eq "$file_failures_before" ]]; then
        echo "PASS [$label] producer-to-workflow contract satisfied"
    fi
}

# ── Cerebrate-state contract validation ──────────────────────────────────────────
#
# AUTO-DISCOVERY: iterate every state in the definition, select the ones whose
# .agent == "hivemind:cerebrate", and assert each declares transition keys that are
# a SUPERSET of EITHER the PLANNING set OR the ANALYSIS set. Cerebrate has two output
# modes (see plugin/agents/cerebrate.md: Plan Result Mapping + Analysis Result
# Mapping), so satisfying either set is legitimate; a state is rejected ONLY when it
# satisfies NEITHER. Unlike validate_producer_contract (keyed on fixed state names),
# this is name-agnostic so any future cerebrate state is covered without editing this
# script. Fails (increments FAILURES) on any state that satisfies neither set.
validate_cerebrate_contract() {
    local def_file="$1"
    local label
    label="${def_file#"$REPO_ROOT"/}"
    local file_failures_before="$FAILURES"

    # Skip non-JSON — structural validation already reports that.
    if ! jq -e . "$def_file" >/dev/null 2>&1; then
        return
    fi

    # Discover cerebrate state names.
    local cerebrate_states
    cerebrate_states="$(jq -r '
        [.states | to_entries[]
         | select(.value.agent == "hivemind:cerebrate")
         | .key]
        | .[]
    ' "$def_file" 2>/dev/null || true)"

    [[ -n "$cerebrate_states" ]] || return 0

    local state_name outcome
    while IFS= read -r state_name; do
        [[ -n "$state_name" ]] || continue

        # A state satisfies a set when it declares a transition key for EVERY outcome
        # in that set. Track whether each set is fully satisfied.
        local planning_ok=true analysis_ok=true present
        for outcome in "${CEREBRATE_PLANNING_SET[@]}"; do
            present="$(jq -r --arg st "$state_name" --arg o "$outcome" \
                '(.states[$st].transitions // {}) | has($o)' "$def_file" 2>/dev/null || echo "false")"
            [[ "$present" == "true" ]] || planning_ok=false
        done
        for outcome in "${CEREBRATE_ANALYSIS_SET[@]}"; do
            present="$(jq -r --arg st "$state_name" --arg o "$outcome" \
                '(.states[$st].transitions // {}) | has($o)' "$def_file" 2>/dev/null || echo "false")"
            [[ "$present" == "true" ]] || analysis_ok=false
        done

        if [[ "$planning_ok" != "true" && "$analysis_ok" != "true" ]]; then
            fail "$label" "cerebrate-contract violation: state '$state_name' (agent hivemind:cerebrate) declares transition keys that are a superset of NEITHER the PLANNING set {${CEREBRATE_PLANNING_SET[*]}} NOR the ANALYSIS set {${CEREBRATE_ANALYSIS_SET[*]}}"
        fi
    done <<< "$cerebrate_states"

    if [[ "$FAILURES" -eq "$file_failures_before" ]]; then
        echo "PASS [$label] cerebrate-state contract satisfied"
    fi
}

# ── Decision-autonomy binding validation ─────────────────────────────────────────
#
# validate_autonomy_bindings <table_file> : checks rules R1-R8 (see header) for the
# given decision-autonomy table against the UNION of states and per-state transition
# keys across every plugin/workflows/*.json. Fails closed: a missing or unparseable
# table, a non-array .rows/.hard_stops, no workflow definitions, or a jq evaluation
# error each fail rather than skip. R6 reuses validate_cerebrate_contract's discovery
# rule (agent hivemind:cerebrate) narrowed to PLANNING mode (keys a superset of
# CEREBRATE_PLANNING_SET).
validate_autonomy_bindings() {
    local table_file="$1"
    local label
    label="${table_file#"$REPO_ROOT"/}"
    local file_failures_before="$FAILURES"

    if [[ ! -f "$table_file" ]]; then
        fail "$label" "decision-autonomy table does not exist"
        return
    fi
    if ! jq -e . "$table_file" >/dev/null 2>&1; then
        fail "$label" "decision-autonomy table is not valid JSON"
        return
    fi
    if [[ "$(jq -r '.rows | type' "$table_file")" != "array" ]]; then
        fail "$label" "decision-autonomy table .rows is missing or not an array"
        return
    fi
    if [[ "$(jq -r '(.hard_stops // []) | type' "$table_file")" != "array" ]]; then
        fail "$label" "decision-autonomy table .hard_stops is not an array"
        return
    fi

    local -a wf_files=()
    local wf
    while IFS= read -r -d '' wf; do
        wf_files+=("$wf")
    done < <(find "$WORKFLOWS_DIR" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null | sort -z)
    if [[ ${#wf_files[@]} -eq 0 ]]; then
        fail "$label" "no plugin/workflows/*.json definitions to bind decision sites against"
        return
    fi

    local reserved_json planning_json pre_ledger_json violations
    reserved_json="$(printf '%s\n' "${AUTONOMY_RESERVED_SITES[@]}" | jq -R . | jq -s .)"
    planning_json="$(printf '%s\n' "${CEREBRATE_PLANNING_SET[@]}" | jq -R . | jq -s .)"
    pre_ledger_json="$(printf '%s\n' "${AUTONOMY_PRE_LEDGER_WORKFLOWS[@]}" | jq -R . | jq -s .)"
    if ! violations="$(jq -r \
        --slurpfile wfs <(cat "${wf_files[@]}") \
        --argjson reserved "$reserved_json" \
        --argjson planning "$planning_json" \
        --argjson pre_ledger "$pre_ledger_json" '
        ($wfs
         | reduce .[] as $wf ({};
             reduce (($wf.states // {}) | to_entries[]) as $st (.;
                 .[$st.key] = (((.[$st.key] // [])
                     + (if ($st.value.transitions | type) == "object"
                        then ($st.value.transitions | keys) else [] end)) | unique)))) as $sites
        | [.rows[] | select(type == "object")
           | (.resolved_at // []) | select(type == "array") | .[] | strings] as $bound
        | (.rows | to_entries[]
           | .key as $idx | .value as $row
           | (if ($row | type) == "object" then ($row.kind // "#\($idx)") else "#\($idx)" end) as $name
           | if ($row | type) != "object" then
                 "R1 violation: row \u0027\($name)\u0027 is not an object"
             elif ($row | has("resolved_at") | not) then
                 "R1 violation: row \u0027\($name)\u0027 has no resolved_at"
             elif ($row.resolved_at | type) != "array" then
                 "R1 violation: row \u0027\($name)\u0027 resolved_at is not an array"
             elif ($row.resolved_at | length) == 0 then
                 "R1 violation: row \u0027\($name)\u0027 resolved_at is an empty array"
             else
                 $row.resolved_at[] as $entry
                 | if ($entry | type) != "string" then
                       "R1 violation: row \u0027\($name)\u0027 resolved_at entry \($entry | tojson) is not a string"
                   else
                       ($entry | index(".")) as $dot
                       | (if $dot == null then $entry else $entry[0:$dot] end) as $site
                       | (if $dot == null then null else $entry[($dot + 1):] end) as $outcome
                       | if ($reserved | index($site)) != null then
                             (if $outcome != null then
                                  "R3 violation: row \u0027\($name)\u0027 entry \u0027\($entry)\u0027 gives reserved site \u0027\($site)\u0027 an outcome part"
                              else empty end)
                         elif ($sites | has($site) | not) then
                             "R2 violation: row \u0027\($name)\u0027 entry \u0027\($entry)\u0027 names site \u0027\($site)\u0027, which is neither a declared workflow state nor a reserved site"
                         elif $outcome != null and (($sites[$site] | index($outcome)) == null) then
                             "R4 violation: row \u0027\($name)\u0027 entry \u0027\($entry)\u0027 names outcome \u0027\($outcome)\u0027, which is not a transition key of state \u0027\($site)\u0027 in any workflow"
                         else empty end
                   end
             end),
          ((.hard_stops // []) | to_entries[]
           | select((.value | type) == "object" and (.value | has("resolved_at")))
           | "R5 violation: hard_stops entry \u0027\(.value.hard_stop // "#\(.key)")\u0027 carries resolved_at; hard stops hold at every site"),
          ($wfs[] | . as $wf
           | ($wf.terminal // []) as $term
           | ($wf.states // {}) | to_entries[]
           | select(.value.agent == "hivemind:cerebrate")
           | select((.value.transitions | type) == "object")
           | .key as $state | .value.transitions as $tr
           | select(($planning - ($tr | keys)) | length == 0)
           | $tr | to_entries[]
           | .key as $outcome | .value as $target
           | select(($term | index($target)) == null)
           | select(($wf.states[$target].type // "") != "user_gate")
           | "\($state).\($outcome)" as $site_outcome
           | select(($bound | index($site_outcome)) == null)
           | "R6 violation: cerebrate planning state \u0027\($state)\u0027 outcome \u0027\($outcome)\u0027 advances to non-terminal, non-user_gate state \u0027\($target)\u0027 (workflow \u0027\($wf.id // "?")\u0027) but no row binds exactly \u0027\($site_outcome)\u0027"),
          ([.rows | to_entries[]
            | .key as $idx | .value
            | select(type == "object")
            | (.kind // "#\($idx)" | tostring) as $name
            | (.resolved_at // []) | select(type == "array") | .[] | strings
            | {site: ., idx: $idx, name: $name}]
           | group_by(.site)[]
           | select((map(.idx) | unique | length) > 1)
           | "R7 violation: decision site \u0027\(.[0].site)\u0027 is named by more than one row (\(map(.name) | unique | join(", "))); a site names at most one kind"),
          ([$wfs[] | select(.id as $id | ($pre_ledger | index($id)) != null)] as $pre_wfs
           | ($pre_ledger - ($pre_wfs | map(.id))) as $missing_ids
           | if ($missing_ids | length) > 0 then
                 ($missing_ids[]
                  | "R8 violation: pre-ledger workflow \u0027\(.)\u0027 is not declared by any plugin/workflows/*.json definition")
             elif (.levels | type) != "array" then
                 "R8 violation: table .levels is missing or not an array; level cells cannot be checked"
             else
                 .levels as $levels
                 | (($reserved + [$pre_wfs[] | (.states // {}) | keys[]]) | unique) as $pre_sites
                 | .rows | to_entries[]
                 | .key as $idx | .value
                 | select(type == "object")
                 | . as $row
                 | (.kind // "#\($idx)" | tostring) as $name
                 | (.resolved_at // []) | select(type == "array") | .[] | strings
                 | index(".") as $dot
                 | (if $dot == null then . else .[0:$dot] end) as $site
                 | select(($pre_sites | index($site)) != null)
                 | $levels[] | strings
                 | . as $level
                 | select($row[$level] == "auto")
                 | "R8 violation: row \u0027\($name)\u0027 binds pre-ledger site \u0027\($site)\u0027 with an `auto` cell at level \u0027\($level)\u0027; a decision there has no bounding event"
             end)
    ' "$table_file" 2>&1)"; then
        fail "$label" "decision-autonomy binding check could not be evaluated: $violations"
        return
    fi

    local violation
    while IFS= read -r violation; do
        [[ -n "$violation" ]] || continue
        fail "$label" "autonomy-binding $violation"
    done <<< "$violations"

    if [[ "$FAILURES" -eq "$file_failures_before" ]]; then
        echo "PASS [$label] decision-autonomy rows bind to declared decision sites"
    fi
}

# ── Run-ledger fixture shape validation ─────────────────────────────────────────

validate_ledger_fixture() {
    local ledger_file="$1"
    local label
    label="${ledger_file#"$REPO_ROOT"/}"
    local file_failures_before="$FAILURES"

    if ! jq -e . "$ledger_file" >/dev/null 2>&1; then
        fail "$label" "ledger fixture is not valid JSON"
        return
    fi

    # Required fields per run-ledger-schema.md. Each entry is a jq path expression
    # evaluated for existence; a null/absent value at the path is a failure.
    local checks=(
        'has("schema_version")'
        '.run | has("id")'
        '.run | has("workflow")'
        '.run | has("workflow_version")'
        '.run | has("status")'
        '.run | has("mode")'
        '.state | has("current")'
        '.state | has("previous")'
        '.state | has("status")'
        '.parent | has("kind")'
        '.request | has("raw")'
        '.request | has("normalized")'
        '(.events | type) == "array"'
        '(.blockers | type) == "array"'
    )
    local check
    for check in "${checks[@]}"; do
        local result
        result="$(jq -r "$check" "$ledger_file" 2>/dev/null || echo "false")"
        [[ "$result" == "true" ]] \
            || fail "$label" "run-ledger shape violation: expected '$check' to hold"
    done

    if [[ "$FAILURES" -eq "$file_failures_before" ]]; then
        echo "PASS [$label] run-ledger fixture shape valid"
    fi
}

# ── Self-test: prove the validator REJECTS broken definitions ───────────────────

run_self_test() {
    local defs_dir="$REPO_ROOT/tests/workflow-defs"
    local broken_dir="$defs_dir/broken"
    local valid_dir="$defs_dir/valid"
    local autonomy_broken_dir="$defs_dir/autonomy-broken"
    local self_failures=0

    echo '=== Self-test: broken fixtures MUST be rejected ==='
    if [[ ! -d "$broken_dir" ]]; then
        echo "FAIL [self-test] missing broken-fixture directory: tests/workflow-defs/broken"
        self_failures=$((self_failures + 1))
    else
        local bf
        while IFS= read -r -d '' bf; do
            local bf_label
            bf_label="${bf#"$REPO_ROOT"/}"
            # Run the validator in a subshell so its FAILURES/exit do not affect us,
            # capturing only its exit code. A correctly-rejecting validator exits 1.
            # A broken fixture is rejected if EITHER the structural rules OR the
            # producer-to-workflow contract check flag it — contract-class fixtures
            # (e.g. missing-producer-outcome.json) are structurally valid and are
            # caught only by validate_producer_contract.
            local rc=0
            ( FAILURES=0; validate_workflow_definition "$bf"; validate_producer_contract "$bf"; validate_cerebrate_contract "$bf"; [[ "$FAILURES" -gt 0 ]] ) >/dev/null 2>&1 || rc=$?
            if [[ "$rc" -eq 0 ]]; then
                # Re-run visibly to show WHY it was rejected.
                local detail
                detail="$( FAILURES=0; validate_workflow_definition "$bf"; validate_producer_contract "$bf"; validate_cerebrate_contract "$bf" 2>&1 | grep '^FAIL' || true )"
                echo "PASS [self-test] correctly rejected: $bf_label"
                while IFS= read -r d; do [[ -n "$d" ]] && echo "    $d"; done <<< "$detail"
            else
                echo "FAIL [self-test] broken fixture was NOT rejected: $bf_label"
                self_failures=$((self_failures + 1))
            fi
        done < <(find "$broken_dir" -maxdepth 1 -name '*.json' -type f -print0 | sort -z)
    fi

    echo ''
    echo '=== Self-test: valid fixtures MUST pass ==='
    if [[ -d "$valid_dir" ]]; then
        local vf
        while IFS= read -r -d '' vf; do
            local vf_label
            vf_label="${vf#"$REPO_ROOT"/}"
            local rc=0
            ( FAILURES=0; validate_workflow_definition "$vf"; validate_producer_contract "$vf"; validate_cerebrate_contract "$vf"; [[ "$FAILURES" -eq 0 ]] ) >/dev/null 2>&1 || rc=$?
            if [[ "$rc" -eq 0 ]]; then
                echo "PASS [self-test] valid fixture accepted: $vf_label"
            else
                echo "FAIL [self-test] valid fixture was rejected: $vf_label"
                ( FAILURES=0; validate_workflow_definition "$vf"; validate_producer_contract "$vf"; validate_cerebrate_contract "$vf" 2>&1 | grep '^FAIL' || true ) \
                    | while IFS= read -r d; do [[ -n "$d" ]] && echo "    $d"; done
                self_failures=$((self_failures + 1))
            fi
        done < <(find "$valid_dir" -maxdepth 1 -name '*.json' -type f -print0 | sort -z)
    else
        echo '[SKIP] tests/workflow-defs/valid/ does not exist'
    fi

    echo ''
    echo '=== Self-test: broken autonomy tables MUST be rejected ==='
    if [[ ! -d "$autonomy_broken_dir" ]]; then
        echo "FAIL [self-test] missing broken-fixture directory: tests/workflow-defs/autonomy-broken"
        self_failures=$((self_failures + 1))
    else
        local af
        while IFS= read -r -d '' af; do
            local af_label
            af_label="${af#"$REPO_ROOT"/}"
            local rc=0
            ( FAILURES=0; validate_autonomy_bindings "$af"; [[ "$FAILURES" -gt 0 ]] ) >/dev/null 2>&1 || rc=$?
            if [[ "$rc" -eq 0 ]]; then
                local detail
                detail="$( ( FAILURES=0; validate_autonomy_bindings "$af" ) 2>&1 | grep '^FAIL' || true )"
                echo "PASS [self-test] correctly rejected: $af_label"
                while IFS= read -r d; do [[ -n "$d" ]] && echo "    $d"; done <<< "$detail"
            else
                echo "FAIL [self-test] broken autonomy table was NOT rejected: $af_label"
                self_failures=$((self_failures + 1))
            fi
        done < <(find "$autonomy_broken_dir" -maxdepth 1 -name '*.json' -type f -print0 | sort -z)
    fi

    echo ''
    echo '=== Self-test: real decision-autonomy table MUST pass ==='
    local table_label
    table_label="${AUTONOMY_TABLE_FILE#"$REPO_ROOT"/}"
    local table_rc=0
    ( FAILURES=0; validate_autonomy_bindings "$AUTONOMY_TABLE_FILE"; [[ "$FAILURES" -eq 0 ]] ) >/dev/null 2>&1 || table_rc=$?
    if [[ "$table_rc" -eq 0 ]]; then
        echo "PASS [self-test] real table accepted: $table_label"
    else
        echo "FAIL [self-test] real table was rejected: $table_label"
        ( FAILURES=0; validate_autonomy_bindings "$AUTONOMY_TABLE_FILE" ) 2>&1 | grep '^FAIL' \
            | while IFS= read -r d; do [[ -n "$d" ]] && echo "    $d"; done
        self_failures=$((self_failures + 1))
    fi

    echo ''
    echo '=== Self-test summary ==='
    if [[ "$self_failures" -gt 0 ]]; then
        echo "Self-test: $self_failures failure(s) — the validator did not behave as required."
        exit 1
    fi
    echo "Self-test: every broken fixture rejected and every valid fixture accepted."
    exit 0
}

if [[ "$SELF_TEST" == true ]]; then
    run_self_test
fi

# ── Drive the real workflow definitions ─────────────────────────────────────────

echo '=== Workflow definitions: plugin/workflows/*.json ==='
if [[ ! -d "$WORKFLOWS_DIR" ]]; then
    fail "plugin/workflows" "directory does not exist"
else
    declare -a def_files=()
    while IFS= read -r -d '' f; do
        def_files+=("$f")
    done < <(find "$WORKFLOWS_DIR" -maxdepth 1 -name '*.json' -type f -print0 | sort -z)

    if [[ ${#def_files[@]} -eq 0 ]]; then
        fail "plugin/workflows" "no *.json workflow definitions found"
    else
        for f in "${def_files[@]}"; do
            validate_workflow_definition "$f"
        done

        echo ''
        echo '=== Producer-to-workflow contract: reviewer-state transitions ==='
        for f in "${def_files[@]}"; do
            validate_producer_contract "$f"
        done

        echo ''
        echo '=== Cerebrate-state contract: planner outcome transitions ==='
        for f in "${def_files[@]}"; do
            validate_cerebrate_contract "$f"
        done

        echo ''
        echo '=== Decision-autonomy bindings: table rows to workflow decision sites ==='
        validate_autonomy_bindings "$AUTONOMY_TABLE_FILE"
    fi
fi

# ── Drive the run-ledger fixtures (shape only) ──────────────────────────────────

echo ''
echo '=== Run-ledger fixtures: tests/engine/*.json ==='
if [[ -d "$ENGINE_FIXTURES_DIR" ]]; then
    declare -a ledger_files=()
    while IFS= read -r -d '' f; do
        ledger_files+=("$f")
    done < <(find "$ENGINE_FIXTURES_DIR" -maxdepth 1 -name 'ledger-*.json' -type f -print0 | sort -z)

    if [[ ${#ledger_files[@]} -eq 0 ]]; then
        echo '[SKIP] No ledger-*.json fixtures found in tests/engine/'
    else
        for f in "${ledger_files[@]}"; do
            validate_ledger_fixture "$f"
        done
    fi
else
    echo '[SKIP] tests/engine/ does not exist'
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ''
echo '=== Summary ==='
if [[ "$FAILURES" -gt 0 ]]; then
    echo "Workflow validation: $FAILURES failure(s)."
    exit 1
fi
echo "Workflow validation: all definitions and ledger fixtures valid."
exit 0
