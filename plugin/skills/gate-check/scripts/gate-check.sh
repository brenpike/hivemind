#!/usr/bin/env bash
#
# gate-check — READ-ONLY gate engine for the hivemind:gate-check skill.
#
# Finds the next gate the pull request still needs on the state-machine path of the
# standard-delivery workflow. A gate holds only for the commit its step ended on, per
# ${CLAUDE_PLUGIN_ROOT}/governance/workflow.md (PR Requirements). The engine reads the run ledger
# and the gate contract, reads HEAD and the working tree, and PRINTS a routing decision. It
# writes NOTHING. It belongs to the committed-script engine-op family of next-wave.sh (shebang,
# blocker() helper, jq into inert variables, YAML routing on stdout, exit codes) and reuses its
# shared ledger-open guard.
#
# INPUT (single positional argument):
#   $1  run_id — the ONLY caller identity, validated by SAFE_ID_RE plus a reserved-component
#       reject and referenced only as "$run_id". No caller-supplied path is accepted.
#
# PATH POSTURE — DERIVE-ONLY, READ-ONLY:
#   The ledger is "<git-root>/.hivemind/runs/<run_id>/state.json", opened through the shared
#   hivemind_open_ledger guard (ancestor containment, symlinked-state.json-leaf reject,
#   existence, JSON validity, .run.id coherence) before any jq read of ledger content. The gate
#   contract is "gate-contract.json" beside this script, found by self-location.
#
# GATE CONTRACT (gate-contract.json): the workflow name, the gates in order (each with an id, a
#   due outcome, its holding transitions "<state>.<result>" and optional skip transitions), the
#   rerun bound max_reruns, and the all_held and rerun_limit outcome names.
#
# COMPUTATION:
#   1. Only events whose plan_epoch equals .plan.epoch count (both default 0).
#   2. A holding event is an event whose "<state>.<result>" is a holding transition of a gate.
#      A gate's held commit is the top-level head of its LATEST holding event. An event with no
#      string head holds nothing.
#   3. A gate with skip transitions is not configured when the latest event of a skip
#      transition's state ended on a skip transition. A gate that is not configured neither
#      holds nor blocks.
#   4. reruns = the number of adjacent differing pairs in the sequence of holding-event heads
#      (event order, missing heads dropped) followed by HEAD.
#   5. reruns > max_reruns -> the rerun_limit outcome. The workflow script's runGates() lets
#      maxGateReruns() reruns run and asks on the next one, so a 5th rerun is the first refused.
#      Else the due outcome of the first configured gate whose held commit is not HEAD. Else
#      the all_held outcome.
#
# VALIDATION (fail-closed -> `blocker: <reason>` on stderr, exit 1, nothing on stdout):
#   missing/malformed gate contract; missing/unsafe run_id; not inside a git checkout; ledger
#   missing, invalid, incoherent or not contained; run.workflow is not the contract workflow;
#   events present but not an array; HEAD has no commit; the working tree reports any changed or
#   untracked path; the working tree status cannot be read.
#
# OUTPUT on success (exit 0):
#     outcome: <due outcome|all_held|rerun_limit>
#     head: <full object id of HEAD>
#     reruns: <N>
#     max_reruns: <N>
#
# SHELL FLOOR: full P18 `set -euo pipefail`. The helpers whose nonzero returns this engine
# inspects are called as `if` conditions, which suppresses errexit inside them.

set -euo pipefail

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

SAFE_ID_RE='^[A-Za-z0-9._-]+$'
HEAD_OID_RE='^[0-9a-f]{40}([0-9a-f]{24})?$'

script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve the plugin root from the script directory; refusing to proceed"

[ -f "$plugin_root/skills/_shared/containment.sh" ] || blocker "required shared library missing: skills/_shared/containment.sh; refusing to proceed"
. "$plugin_root/skills/_shared/containment.sh" || blocker "failed to source skills/_shared/containment.sh (unparseable); refusing to proceed"
[ -f "$plugin_root/skills/_shared/ledger-engine-io.sh" ] || blocker "required shared library missing: skills/_shared/ledger-engine-io.sh; refusing to proceed"
. "$plugin_root/skills/_shared/ledger-engine-io.sh" || blocker "failed to source skills/_shared/ledger-engine-io.sh (unparseable); refusing to proceed"
[ -f "$plugin_root/skills/_shared/git-refusals.sh" ] || blocker "required shared library missing: skills/_shared/git-refusals.sh; refusing to proceed"
. "$plugin_root/skills/_shared/git-refusals.sh" || blocker "failed to source skills/_shared/git-refusals.sh (unparseable); refusing to proceed"

command -v jq >/dev/null 2>&1 \
  || blocker "jq is required to read the run ledger but is not installed"

# ── Gate contract (self-located) ──────────────────────────────────────────────
contract_file="$script_dir/gate-contract.json"
[ -f "$contract_file" ] || blocker "gate contract missing: gate-contract.json; refusing to proceed"
contract_ok="$(jq --arg re "$SAFE_ID_RE" '
  def transition: type == "string" and test("^[A-Za-z0-9_]+\\.[A-Za-z0-9_-]+$");
  def outcome_name: type == "string" and test($re);
  (.workflow | outcome_name)
  and (.gates | type == "array" and length > 0)
  and (.gates | all(
        type == "object"
        and (.id | type == "string")
        and (.due | outcome_name)
        and (.holds | type == "array" and length > 0 and all(transition))
        and ((.skip // []) | type == "array" and all(transition))))
  and (.max_reruns | type == "number" and . >= 0 and . == floor)
  and (.outcomes | type == "object")
  and (.outcomes.all_held | outcome_name)
  and (.outcomes.rerun_limit | outcome_name)' "$contract_file" 2>/dev/null)" || contract_ok=""
[ "$contract_ok" = "true" ] || blocker "gate contract is malformed: gate-contract.json; refusing to proceed"
contract_workflow="$(jq -r '.workflow' "$contract_file")"
max_reruns="$(jq -r '.max_reruns' "$contract_file")"

# ── Input: run_id ─────────────────────────────────────────────────────────────
run_id="${1:-}"
[ -n "$run_id" ] || blocker "missing required argument: run_id (\$1)"
printf '%s' "$run_id" | grep -Eq "$SAFE_ID_RE" \
  || blocker "run_id is not a safe path component: $run_id"
case "$run_id" in
  .|..) blocker "run_id is a reserved path component: $run_id" ;;
esac

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || repo_root=""
[ -n "$repo_root" ] || blocker "not inside a git repository"
ledger="$repo_root/.hivemind/runs/$run_id/state.json"

# ── Ledger-open machinery (shared helper) — BEFORE any ledger read ─────────────
if ledger_open_out="$(hivemind_open_ledger "$repo_root" "$run_id")"; then
  ledger_open_rc=0
else
  ledger_open_rc=$?
fi
case $ledger_open_rc in
  0)
    if ! canon_ledger_dir="$(cd "$(dirname "$ledger")" && pwd -P)" || [ -z "$canon_ledger_dir" ]; then
      blocker "failed to canonicalize the ledger directory; ledger unchanged"
    fi
    ledger="$canon_ledger_dir/state.json"
    ;;
  2) blocker "refusing: ${repo_root}/.hivemind/runs/$run_id resolves outside the checkout (symlinked ancestor or leaf)" ;;
  6) blocker "refusing to read the ledger: $ledger resolves outside the checkout (symlinked ancestor or leaf)" ;;
  *) blocker "$ledger_open_out" ;;
esac

workflow_matches="$(jq --arg w "$contract_workflow" '((.run | objects | .workflow) // null) == $w' "$ledger")"
[ "$workflow_matches" = "true" ] || blocker "the run's workflow is not $contract_workflow; gate-check reads only $contract_workflow runs"

events_ok="$(jq '(.events // []) | type == "array"' "$ledger")"
[ "$events_ok" = "true" ] || blocker "events is not an array"

# ── HEAD and the working tree ─────────────────────────────────────────────────
head_oid="$(git rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" || head_oid=""
[ -n "$head_oid" ] || blocker "HEAD has no commit; no gate can hold"
printf '%s' "$head_oid" | grep -Eq "$HEAD_OID_RE" \
  || blocker "HEAD did not resolve to a full object id"

if hivemind_read_dirty_kinds; then
  dirty_rc=0
else
  dirty_rc=$?
fi
case $dirty_rc in
  0) ;;
  1) blocker "the working tree has uncommitted or untracked changes; a gate holds only for a commit" ;;
  *) blocker "cannot read the working tree status" ;;
esac

# ── Gate computation (single jq program; emits <outcome>\t<reruns>) ──────────
main="$(jq -r --slurpfile contract "$contract_file" --arg head "$head_oid" '
  $contract[0] as $c
  | (.plan | if type == "object" then (.epoch // 0) else 0 end) as $cur
  | [ (.events // [])[]
      | objects
      | select((.plan_epoch // 0) == $cur)
      | select((.state | type) == "string" and (.result | type) == "string")
      | {state: .state, key: (.state + "." + .result), head: (.head | if type == "string" then . else null end)}
    ] as $ev
  | [ $c.gates[].holds[] ] as $all_holds
  | [ $ev[] | select(.key as $k | $all_holds | any(. == $k)) ] as $holding
  | ([ $holding[] | .head | strings ] + [$head]) as $seq
  | ([ range(1; $seq | length) as $i | select($seq[$i - 1] != $seq[$i]) ] | length) as $reruns
  | [ $c.gates[]
      | . as $g
      | (($g.skip // []) | map(split(".")[0]) | unique) as $skip_states
      | ([ $ev[] | select(.state as $s | $skip_states | any(. == $s)) ] | last) as $latest_skip_state
      | select(($latest_skip_state != null and (($g.skip // []) | any(. == $latest_skip_state.key))) | not)
      | ([ $holding[] | select(.key as $k | $g.holds | any(. == $k)) ] | last) as $latest_hold
      | select(($latest_hold.head // null) != $head)
      | $g.due
    ] as $due
  | (if $reruns > $c.max_reruns then $c.outcomes.rerun_limit
     elif ($due | length) > 0 then $due[0]
     else $c.outcomes.all_held end) as $outcome
  | [$outcome, ($reruns | tostring)] | join("\t")
' "$ledger")"

IFS=$'\t' read -r outcome reruns <<< "$main"
printf '%s' "$outcome" | grep -Eq "$SAFE_ID_RE" || blocker "computed outcome is not a safe name"

printf 'outcome: %s\n' "$outcome"
printf 'head: %s\n' "$head_oid"
printf 'reruns: %s\n' "$reruns"
printf 'max_reruns: %s\n' "$max_reruns"
exit 0
