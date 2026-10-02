#!/usr/bin/env bash
# Path-selective validation dispatcher for the hivemind repo (issue #164, STEP-001).
#
# Runs the repo's validation suite ONCE pre-PR. Two run shapes:
#   --all       Full suite, identical to .github/workflows/policy-check.yml (CI parity).
#   --changed   Map the changed-file set to the minimal set of suites that exercise
#               those paths, then run only those. FAIL-CLOSED: any ambiguity runs MORE.
#
# This script gates correctness. A mis-mapped path that skips a relevant heavy suite is a
# false-green. Every unmapped/unknown path therefore escalates to the FULL suite — never a
# silent skip. The mapping globs below were derived by reading each tool to confirm the exact
# inputs it exercises (test_engine.sh, test_brood_compat.sh, test_shared_libs.sh,
# validate_reports.sh, validate_workflows.sh, policy_check.sh).
#
# Usage:
#   bash tools/validate.sh [--all]
#   bash tools/validate.sh --changed [--base <ref>]
#   bash tools/validate.sh --self-test
#   bash tools/validate.sh -h | --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# Scratch dir for the parallel suite runner. Declared at SCRIPT scope (not `local` inside
# run_suites) so the EXIT-trap cleanup can still reference it after run_suites returns —
# a `local` would be out of scope when the trap fires, tripping `set -u`. Empty until the
# runner creates it; the cleanup is guarded with `${SUITES_SCRATCH:-}` so it is a no-op when
# unset/empty.
SUITES_SCRATCH=""
# Cleanup closes over SUITES_SCRATCH by NAME (the value is never interpolated into executable
# trap-string source), so a path derived from a TMPDIR containing a single quote or any shell
# metacharacter cannot break out and run arbitrary shell when the trap fires. The value is only
# ever expanded as a single quoted "$SUITES_SCRATCH" argument to rm.
cleanup_suites_scratch() {
  [[ -n "${SUITES_SCRATCH:-}" ]] && rm -rf -- "$SUITES_SCRATCH"
}

# ── Suite invocations (CI parity — see .github/workflows/policy-check.yml) ────────
# Each constant is the exact command CI runs, in CI order. --all replays them verbatim.
SUITE_JSON_MANIFESTS='json-manifests'   # special: three python3 json.load parses
SUITE_POLICY_CHECK='policy_check.sh --strict'
SUITE_VALIDATE_REPORTS='validate_reports.sh --batch tests/reports/'
SUITE_WORKFLOWS_STRICT='validate_workflows.sh --strict'
SUITE_WORKFLOWS_SELFTEST='validate_workflows.sh --self-test'
SUITE_TEST_ENGINE='test_engine.sh'
SUITE_TEST_SHARED='test_shared_libs.sh'
SUITE_TEST_BROOD='test_brood_compat.sh'
SUITE_TEST_FIX_HISTORY='test_fix_history_classify.sh'
SUITE_TEST_FETCH_NORMALIZE='test_fetch_normalize.sh'
SUITE_TEST_EXIT_PRECEDENCE='test_exit_precedence.sh'
SUITE_TEST_LOOP_STATE='test_loop_state.sh'
SUITE_TEST_REPLY_RESOLVE='test_reply_resolve.sh'
SUITE_TEST_REACT_MARKER='test_react_marker.sh'
SUITE_TEST_LEDGER_RECONSTRUCT='test_ledger_reconstruct.sh'
SUITE_TEST_TRIAGE_OPS='test_triage_ops.sh'
SUITE_TEST_SUBISSUE_OPS='test_subissue_ops.sh'
SUITE_TEST_SEED_HIVE='test_seed_hive.sh'
SUITE_TEST_RC_BROOD='test_rc_brood.sh'
SUITE_TEST_NEXT_WAVE='test_next_wave.sh'
SUITE_TEST_BUMP_TYPE='test_bump_type.sh'
SUITE_TEST_VALIDATE_SUITES='test_validate_suites.sh'
SUITE_TEST_CHANGE_DETECT_POLL='test_change_detect_poll.sh'
SUITE_TEST_SCRIPT_BOOTSTRAP='test_script_bootstrap.sh'
SUITE_TEST_PREFILTER='test_prefilter.sh'

# Full suite, in CI order. Used by --all and by every FAIL-CLOSED escalation.
ALL_SUITES=(
  "$SUITE_JSON_MANIFESTS"
  "$SUITE_POLICY_CHECK"
  "$SUITE_VALIDATE_REPORTS"
  "$SUITE_WORKFLOWS_STRICT"
  "$SUITE_WORKFLOWS_SELFTEST"
  "$SUITE_TEST_ENGINE"
  "$SUITE_TEST_SHARED"
  "$SUITE_TEST_BROOD"
  "$SUITE_TEST_FIX_HISTORY"
  "$SUITE_TEST_FETCH_NORMALIZE"
  "$SUITE_TEST_EXIT_PRECEDENCE"
  "$SUITE_TEST_LOOP_STATE"
  "$SUITE_TEST_REPLY_RESOLVE"
  "$SUITE_TEST_REACT_MARKER"
  "$SUITE_TEST_LEDGER_RECONSTRUCT"
  "$SUITE_TEST_TRIAGE_OPS"
  "$SUITE_TEST_SUBISSUE_OPS"
  "$SUITE_TEST_SEED_HIVE"
  "$SUITE_TEST_RC_BROOD"
  "$SUITE_TEST_NEXT_WAVE"
  "$SUITE_TEST_BUMP_TYPE"
  "$SUITE_TEST_VALIDATE_SUITES"
  "$SUITE_TEST_CHANGE_DETECT_POLL"
  "$SUITE_TEST_SCRIPT_BOOTSTRAP"
  "$SUITE_TEST_PREFILTER"
)

# KNOWN_SUITES: the tools/*.sh validation suites this dispatcher knows about. --self-test
# cross-checks this list against the actual tools/*.sh glob: a new suite that is neither here
# nor in NON_SUITE_TOOLS is a coverage gap and fails --self-test.
KNOWN_SUITES=(
  policy_check.sh
  validate_reports.sh
  validate_workflows.sh
  test_engine.sh
  test_shared_libs.sh
  test_brood_compat.sh
  test_fix_history_classify.sh
  test_fetch_normalize.sh
  test_exit_precedence.sh
  test_loop_state.sh
  test_reply_resolve.sh
  test_react_marker.sh
  test_ledger_reconstruct.sh
  test_triage_ops.sh
  test_subissue_ops.sh
  test_seed_hive.sh
  test_rc_brood.sh
  test_next_wave.sh
  test_bump_type.sh
  test_validate_suites.sh
  test_change_detect_poll.sh
  test_script_bootstrap.sh
  test_prefilter.sh
)

# NON_SUITE_TOOLS: tools/*.sh files that are NOT validation suites (so --self-test does not
# demand a mapping rule for them). This dispatcher is itself excluded.
NON_SUITE_TOOLS=(
  validate.sh
)

# ── Suite execution ──────────────────────────────────────────────────────────────
# run_suite: execute one suite token against the real repo. Returns the suite's exit status.
run_suite() {
  local suite="$1"
  case "$suite" in
    "$SUITE_JSON_MANIFESTS")
      # Every committed JSON file the runtime MUST be able to load. The two plugin manifests
      # are consumed by the plugin/marketplace loaders; .claude/settings.json is consumed by
      # Claude Code itself at session start. A syntax error anywhere in one of them is fatal to
      # its consumer, and no other suite parses them: policy_check's fixtures match RAW TEXT
      # (extract_regex / substring), so a settings file that drops a comma but keeps the
      # expected permission strings passes every text fixture while Claude Code cannot load it.
      # This leg is that parse gate.
      python3 -c "import json; json.load(open('plugin/.claude-plugin/plugin.json'))" \
        && python3 -c "import json; json.load(open('.claude-plugin/marketplace.json'))" \
        && python3 -c "import json; json.load(open('.claude/settings.json'))"
      ;;
    *)
      # shellcheck disable=SC2086 # word-splitting of "script.sh --flag arg" is intentional
      bash "$SCRIPT_DIR"/$suite
      ;;
  esac
}

# run_suites: run a de-duped, CI-ordered subset CONCURRENTLY, then replay results in canonical
# CI order so the report is byte-deterministic regardless of completion order. Exits non-zero if
# any suite fails, after waiting on EVERY selected suite (no early abort — full signal).
#
# Parallelism is pure-bash (`&` + a bounded pid pool + `wait`); GNU parallel is NOT required.
# Concurrency is capped at min(nproc, N) where N is the number of selected suites, so a single
# selected suite (N=1) launches exactly one job and waits on it — no empty-wait, no deadlock.
#
# INVARIANT: aggregate rc is computed AFTER every job is waited on; a non-zero per-suite rc is
# never lost (a lost failure = false-green merge gate). Under `set -e`, both the background job's
# captured rc and `wait` are guarded with `|| rc=$?` so a failing suite cannot abort the dispatcher.
run_suites() {
  local -a requested=("$@")
  local -a ordered=()
  local s w
  # Reorder the requested set into canonical CI order so output is stable and the cheap
  # policy_check/json parse appear first in the replayed report.
  for s in "${ALL_SUITES[@]}"; do
    for w in "${requested[@]}"; do
      if [[ "$s" == "$w" ]]; then
        ordered+=("$s")
        break
      fi
    done
  done

  if [[ ${#ordered[@]} -eq 0 ]]; then
    echo "no impacted files — running nothing, exit 0"
    return 0
  fi

  local n=${#ordered[@]}

  # Concurrency cap: min(nproc, N). nproc self-adjusts across machines/CI runners; if it is
  # unavailable for any reason, fall back to N (run all concurrently) rather than serialize.
  local cap procs
  procs="$(nproc 2>/dev/null || echo "$n")"
  [[ "$procs" =~ ^[0-9]+$ && "$procs" -ge 1 ]] || procs="$n"
  if [[ "$procs" -lt "$n" ]]; then cap="$procs"; else cap="$n"; fi

  # Per-suite scratch: each job writes its OWN combined stdout/stderr to out.<i> and its OWN exit
  # status to rc.<i>, keyed by canonical index so suites with spaces in their token (e.g.
  # "policy_check.sh --strict") never collide on a filename.
  # Assign the SCRIPT-scope scratch var (declared at top) and install the EXIT-trap cleanup.
  # Script scope (not `local`) is required so cleanup_suites_scratch can still see the path
  # after this function returns — the EXIT trap fires post-return, where a `local` would be
  # unbound under `set -u`. `local scratch` below is just a convenience alias used within
  # this function; the trap reads SUITES_SCRATCH.
  SUITES_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/validate-suites.XXXXXX")"
  trap cleanup_suites_scratch EXIT
  local scratch="$SUITES_SCRATCH"

  # run_one_suite: execute suite index $1 in the current (sub)shell, capturing combined output to
  # the scratch out file and the exit status to the scratch rc file. Never aborts the dispatcher.
  run_one_suite() {
    local idx="$1"
    local suite="${ordered[$idx]}"
    local start end
    start="$(date +%s.%N)"
    local job_rc=0
    run_suite "$suite" >"$scratch/out.$idx" 2>&1 || job_rc=$?
    end="$(date +%s.%N)"
    printf '%s\n' "$job_rc" >"$scratch/rc.$idx"
    # Elapsed wall-time (seconds, one decimal) via awk to avoid bc/float-shell dependencies.
    awk -v s="$start" -v e="$end" 'BEGIN { printf "%.1f\n", e - s }' >"$scratch/sec.$idx"
  }

  # Launch with a bounded pid pool: never exceed `cap` concurrent jobs. wait -n drains the
  # earliest-finishing job (bash 5+) so a slow suite cannot starve the pool.
  local -a pids=()
  local i running
  for ((i = 0; i < n; i++)); do
    running=${#pids[@]}
    if [[ "$running" -ge "$cap" ]]; then
      # Block until at least one job finishes, then prune completed pids from the pool.
      wait -n 2>/dev/null || true
      local -a still=()
      local p
      for p in "${pids[@]}"; do
        if kill -0 "$p" 2>/dev/null; then still+=("$p"); fi
      done
      pids=("${still[@]}")
    fi
    run_one_suite "$i" &
    pids+=("$!")
  done

  # Drain the remaining jobs. Guard wait under `set -e` so a non-zero job rc cannot abort here;
  # the authoritative per-suite rc is read back from the scratch rc files below, not from wait.
  local p
  for p in "${pids[@]}"; do
    wait "$p" 2>/dev/null || true
  done

  # Replay in canonical CI order (NOT completion order) so the report is byte-deterministic.
  local rc=0
  local -a summary=()
  for ((i = 0; i < n; i++)); do
    s="${ordered[$i]}"
    local suite_rc suite_sec
    suite_rc="$(cat "$scratch/rc.$i" 2>/dev/null || echo 1)"
    suite_sec="$(cat "$scratch/sec.$i" 2>/dev/null || echo 0.0)"
    echo
    echo "=== validate.sh: running [$s] ==="
    cat "$scratch/out.$i" 2>/dev/null || true
    if [[ "$suite_rc" -eq 0 ]]; then
      echo "--- [$s] PASS ---"
    else
      echo "--- [$s] FAIL ---" >&2
      rc=1
    fi
    echo "[$s] ${suite_sec}s"
    # Carry the canonical ALL_SUITES index ($i) as the THIRD column so the timing sort can
    # break duration ties in canonical order rather than sort's unstable/locale fallback.
    summary+=("$suite_sec"$'\t'"$i"$'\t'"$s")
  done

  # Timing summary, slowest-first (always-on). Sort by elapsed DESCENDING (k1), then by canonical
  # index ASCENDING (k2) as an explicit, byte-deterministic tie-breaker: suites whose rounded
  # elapsed value ties replay in canonical ALL_SUITES order, never in sort's locale fallback. The
  # index column is consumed by the sort key only — it is dropped from the printed line.
  echo
  echo "=== validate.sh: timing summary (slowest first) ==="
  local sec idx name
  while IFS=$'\t' read -r sec idx name; do
    [[ -z "$name" ]] && continue
    printf '  %6ss  %s\n' "$sec" "$name"
  done < <(printf '%s\n' "${summary[@]}" | sort -t$'\t' -k1,1rn -k2,2n)

  return "$rc"
}

# ── Path → suite mapping (FAIL-CLOSED) ─────────────────────────────────────────────
# map_path: append to the global SELECTED array (suite\tpath) every suite a single changed
# path triggers, plus a reason. Composes by UNION — one path may hit several rules. A path
# matching NO rule (and not classified as docs-only) escalates to the FULL suite via the
# FULLSUITE sentinel.
#
# Globs verified against each tool:
#   plugin/workflows/*.json            -> validate_workflows --strict + --self-test
#   plugin/skills/record-state-result/scripts/**, init-run-ledger/scripts/**, tests/engine/**,
#     plugin/skills/_shared/containment.sh
#                                      -> test_engine  (also validate_workflows reads tests/engine;
#                                         containment.sh is copied into test_engine's fake plugin)
#   plugin/skills/spawn-brood/**, brood-status/**, init-run-ledger/scripts/**,
#     plugin/skills/_shared/containment.sh, tests/brood/**
#                                      -> test_brood_compat
#   plugin/skills/_shared/*.sh, tests/brood/**          -> test_shared_libs
#   plugin/skills/github-review-loop/scripts/*.jq      -> test_fix_history_classify, test_fetch_normalize,
#                                                         test_shared_libs, test_change_detect_poll,
#                                                         test_prefilter
#   plugin/skills/github-review-loop/scripts/prefilter.sh, tests/fix-history/*
#                                      -> test_prefilter
#   plugin/skills/github-review-loop/scripts/*.sh       -> test_shared_libs (glob-closure test)
#   plugin/skills/_shared/graphql-response.sh
#                                      -> test_fetch_normalize, test_change_detect_poll, test_prefilter,
#                                         test_react_marker, test_reply_resolve (+ test_shared_libs,
#                                         test_script_bootstrap, policy_check via the generic globs)
#   plugin/skills/bump-type/**, plugin/skills/_shared/bump-type-derive.sh
#                                      -> test_bump_type (derive core ALSO -> test_shared_libs)
#   plugin/**/*.sh                     -> test_script_bootstrap (engine bootstrap/self-location contract)
#   tests/reports/**                                    -> validate_reports
#   plugin/agents/{cerebrate,local-reviewer,github-reviewer}.md,
#     plugin/skills/github-review-loop/SKILL.md         -> validate_workflows (exit_reason contracts)
#   tests/workflow-defs/**                              -> validate_workflows
#   plugin/**, .claude-plugin/**, tests/policy/**, tests/plugin/**, tests/workflows/**, *.md under plugin
#                                      -> policy_check
#   plugin/.claude-plugin/plugin.json or .claude-plugin/marketplace.json -> json-manifests parse
#   .claude/settings.json              -> json-manifests parse + policy_check (fixture asserts
#                                         its rule set as raw text; only the parse leg proves
#                                         Claude Code can still LOAD the file)
#   docs/adr/**, web/**, CLAUDE.md     -> policy_check (fixtures pin their content as raw text)
#   tools/**                           -> FULL suite (validator bootstrap)
#   .github/**                         -> FULL suite (CI bootstrap — the gate harness itself)
#   outside plugin|.claude-plugin|tools|tests|.github and not fixture-pinned above
#     (docs/** other than docs/adr/**)  -> no code suites
#   anything matching no rule          -> FULL suite

SELECTED=()      # lines of "suite<TAB>reason"
FORCE_FULL=0     # set to 1 by any FAIL-CLOSED escalation
FORCE_FULL_REASON=''
FORCE_FULL_SELFTEST=0  # set to 1 when the escalation is a validator-bootstrap change (tools/**,
                       # .github/**): the full suite must ALSO run this dispatcher's --self-test,
                       # since a broken path->suite mapping in validate.sh itself would otherwise
                       # green a --changed run without the mapping-coverage assertions executing.

add_selected() {
  SELECTED+=("$1"$'\t'"$2")
}

force_full() {
  FORCE_FULL=1
  FORCE_FULL_REASON="$1"
}

# force_full_bootstrap: a FAIL-CLOSED escalation triggered by a change to the validator harness
# itself (tools/**, .github/**). In addition to the full suite, the dispatcher's own --self-test
# must run so a broken mapping rule cannot merge behind a green --changed.
force_full_bootstrap() {
  force_full "$1"
  FORCE_FULL_SELFTEST=1
}

map_path() {
  local p="$1"
  local matched=0

  # test_validate_suites: the harness that exercises THIS dispatcher's suite-machinery wiring
  # (KNOWN_SUITES / ALL_SUITES / map_path coverage). It has no plugin/* subject and no fixture
  # dir — it drives validate.sh directly, so unlike the other behavioral suites it has no
  # non-tools probe path. This leg self-routes a probe of the harness's OWN path to its own
  # suite so --self-test check #1 finds it reachable. It runs BEFORE (and does NOT return early
  # from) the tools/** escalation below: a real edit to this file still fail-closes to the full
  # suite via that leg, so the tools/** bootstrap guarantee is preserved.
  if [[ "$p" == tools/test_validate_suites.sh ]]; then
    add_selected "$SUITE_TEST_VALIDATE_SUITES" "$p (validate-suites harness)"
    matched=1
  fi

  # test_rc_brood: the enable-brood-remote RC oracle. Like the other tools/test_*.sh legs, this
  # self-routes a probe of the harness's OWN path to its own suite so --self-test check #1 finds it
  # reachable. It runs BEFORE (and does NOT return early from) the tools/** escalation below: a real
  # edit to this file still fail-closes to the full suite via that leg, so the bootstrap guarantee
  # is preserved.
  if [[ "$p" == tools/test_rc_brood.sh ]]; then
    add_selected "$SUITE_TEST_RC_BROOD" "$p (rc-brood harness)"
    matched=1
  fi

  # tools/** -> validator bootstrap: re-run everything (including this script's --self-test).
  if [[ "$p" == tools/* ]]; then
    force_full_bootstrap "tools change ($p) — validator bootstrap, full suite + self-test"
    return 0
  fi

  # .github/** -> CI bootstrap: the workflow that runs this dispatcher is itself the gate
  # harness. A change there (e.g. rewiring dispatch, dropping the --all branch) is the other
  # half of the validator-bootstrap surface, so fail-closed to the FULL suite — same posture
  # as tools/**. Never docs-only: an unguarded workflow edit could green a --changed run with
  # zero suites executed.
  if [[ "$p" == .github/* ]]; then
    force_full_bootstrap "CI/workflow change ($p) — validator bootstrap, full suite + self-test"
    return 0
  fi

  # JSON manifests.
  if [[ "$p" == "plugin/.claude-plugin/plugin.json" || "$p" == ".claude-plugin/marketplace.json" ]]; then
    add_selected "$SUITE_JSON_MANIFESTS" "$p (JSON manifest)"
    matched=1
  fi

  # validate_workflows: workflow defs.
  if [[ "$p" == plugin/workflows/*.json ]]; then
    add_selected "$SUITE_WORKFLOWS_STRICT" "$p (workflow definition)"
    add_selected "$SUITE_WORKFLOWS_SELFTEST" "$p (workflow definition)"
    matched=1
  fi
  # validate_workflows: exit_reason contract documents.
  case "$p" in
    plugin/agents/cerebrate.md|plugin/agents/local-reviewer.md|plugin/agents/github-reviewer.md|plugin/skills/github-review-loop/SKILL.md)
      add_selected "$SUITE_WORKFLOWS_STRICT" "$p (exit_reason / state contract source)"
      add_selected "$SUITE_WORKFLOWS_SELFTEST" "$p (exit_reason / state contract source)"
      matched=1
      ;;
  esac
  # validate_workflows: workflow-def fixtures.
  if [[ "$p" == tests/workflow-defs/* ]]; then
    add_selected "$SUITE_WORKFLOWS_STRICT" "$p (workflow-def fixture)"
    add_selected "$SUITE_WORKFLOWS_SELFTEST" "$p (workflow-def fixture)"
    matched=1
  fi

  # test_engine: engine scripts + engine fixtures (validate_workflows also reads tests/engine).
  # The three engine scripts (record-state-result, init-run-ledger, mark-intent-fallback) are the
  # engine oracle's subjects: test_engine.sh is the behavior oracle for all three, so an edit to
  # any of them must trigger test_engine or engine regressions go untested under --changed.
  # Also containment.sh: test_engine.sh copies the shared containment guard into its fake plugin
  # and exercises engine symlink/external-path containment cases, so a containment.sh change must
  # trigger test_engine or record/init engine containment regressions go untested under --changed.
  # Also ledger-engine-io.sh: sourced by the three ledger engine entrypoints; test_engine.sh is the
  # behavior oracle for those engines, so a lib-only edit must trigger test_engine or engine
  # regressions go untested under --changed (test_shared_libs alone is not sufficient).
  if [[ "$p" == plugin/skills/record-state-result/scripts/* \
     || "$p" == plugin/skills/init-run-ledger/scripts/* \
     || "$p" == plugin/skills/mark-intent-fallback/scripts/* \
     || "$p" == plugin/skills/_shared/containment.sh \
     || "$p" == plugin/skills/_shared/ledger-engine-io.sh \
     || "$p" == tests/engine/* ]]; then
    add_selected "$SUITE_TEST_ENGINE" "$p (engine script/fixture)"
    matched=1
  fi
  if [[ "$p" == tests/engine/* ]]; then
    add_selected "$SUITE_WORKFLOWS_STRICT" "$p (run-ledger fixture, validate_workflows)"
    add_selected "$SUITE_WORKFLOWS_SELFTEST" "$p (run-ledger fixture, validate_workflows)"
  fi

  # test_brood_compat: spawn-brood / brood-status scripts + init engine + brood fixtures.
  # Also containment.sh: the shared containment guard's regressions are exercised ONLY by
  # test_brood_compat (via spawn-brood.sh / brood-status guards), not test_shared_libs — so a
  # containment.sh change must trigger this suite or its only relevant coverage is skipped.
  if [[ "$p" == plugin/skills/spawn-brood/* \
     || "$p" == plugin/skills/brood-status/* \
     || "$p" == plugin/skills/init-run-ledger/scripts/* \
     || "$p" == plugin/skills/_shared/containment.sh \
     || "$p" == tests/brood/* ]]; then
    add_selected "$SUITE_TEST_BROOD" "$p (brood script/fixture)"
    matched=1
  fi

  # test_shared_libs: shared libs + brood fixtures.
  if [[ "$p" == plugin/skills/_shared/*.sh || "$p" == tests/brood/* ]]; then
    add_selected "$SUITE_TEST_SHARED" "$p (shared lib / brood fixture)"
    matched=1
  fi

  # test_rc_brood: the enable-brood-remote skill + its TWO new RC manifest fixtures. The skill body
  # is ALSO a plugin/* file (policy_check prose-lints it via the wholesale rule below), but
  # policy_check NEVER EXERCISES the RC behavior — so without this rule a skill edit would only be
  # prose-linted, never behaviorally exercised. Route the skill dir and ONLY the two new RC fixtures
  # to the behavioral suite; the other tests/brood/* fixtures stay owned by test_brood_compat /
  # test_shared_libs above. (tools/test_rc_brood.sh itself self-routes via the leg near the top.)
  if [[ "$p" == plugin/skills/enable-brood-remote/* \
     || "$p" == tests/brood/rc-manifest-all-alive.json \
     || "$p" == tests/brood/rc-manifest-hostile-name.json \
     || "$p" == tests/brood/rc-manifest-foreign-session.json \
     || "$p" == tests/brood/rc-manifest-malformed-name.json ]]; then
    add_selected "$SUITE_TEST_RC_BROOD" "$p (rc-brood skill/fixture)"
    matched=1
  fi

  # test_next_wave: the READ-ONLY ready-wave engine (next-wave.sh) + its ledger fixtures. The
  # script is ALSO a plugin/* file (policy_check prose-lints it via the wholesale rule below),
  # but policy_check NEVER EXECUTES bash — so without this rule a next-wave edit would only be
  # prose-linted, never behaviorally exercised. Route both the skill dir and its fixture dir to
  # the behavioral suite. (tools/test_next_wave.sh itself is covered by the tools/** full-suite
  # leg.)
  if [[ "$p" == plugin/skills/next-wave/* \
     || "$p" == tests/next-wave/* ]]; then
    add_selected "$SUITE_TEST_NEXT_WAVE" "$p (next-wave engine script/fixture)"
    matched=1
  fi

  # test_bump_type: the bump-type navigator skill (SKILL.md + scripts/bump-type.sh entrypoint) and
  # the deterministic derivation core it sources (_shared/bump-type-derive.sh). Both are ALSO
  # plugin/* files (policy_check prose-lints them via the wholesale rule below), but policy_check
  # NEVER EXECUTES bash — so without this rule a bump-type edit would only be prose-linted, never
  # behaviorally exercised. The derive core ALSO keeps its _shared/*.sh -> test_shared_libs routing
  # above (same precedent as containment.sh / ledger-engine-io.sh / settings-merge.sh: a _shared lib
  # routed to more than one behavior oracle because test_shared_libs alone does not cover a contract
  # owned elsewhere). (tools/test_bump_type.sh itself is covered by the tools/** full-suite leg.)
  if [[ "$p" == plugin/skills/bump-type/* \
     || "$p" == plugin/skills/_shared/bump-type-derive.sh ]]; then
    add_selected "$SUITE_TEST_BUMP_TYPE" "$p (bump-type engine skill/derive core)"
    matched=1
  fi

  # validate_reports: report fixtures.
  if [[ "$p" == tests/reports/* ]]; then
    add_selected "$SUITE_VALIDATE_REPORTS" "$p (report fixture)"
    matched=1
  fi

  # test_fix_history_classify: the pure jq classification filter + its payload fixtures. The .jq
  # filter is ALSO a plugin/* file (policy_check prose-lints it via the wholesale rule below), but
  # policy_check NEVER EXECUTES jq — so without this rule a filter edit would only be prose-linted,
  # never behaviorally exercised. Route both the filter glob and the fixture dir to the behavioral
  # suite. (tools/test_fix_history_classify.sh itself is covered by the tools/** full-suite leg.)
  if [[ "$p" == plugin/skills/github-review-loop/scripts/*.jq \
     || "$p" == tests/fix-history/* ]]; then
    add_selected "$SUITE_TEST_FIX_HISTORY" "$p (fix-history classify filter/fixture)"
    matched=1
  fi

  # The github-review-loop scripts/*.jq modules (fix-history-classify.jq, reviewer-identity.jq) are
  # executed by more than the fix-history suite: the fetch-normalize builder, the shared fetch core
  # (_shared), and the change-detect poll all include them via `jq -L`. policy_check NEVER EXECUTES
  # jq, so a module edit must route to EVERY suite that runs it, not just test_fix_history_classify.
  if [[ "$p" == plugin/skills/github-review-loop/scripts/*.jq ]]; then
    add_selected "$SUITE_TEST_FETCH_NORMALIZE" "$p (jq module executed by fetch-normalize)"
    add_selected "$SUITE_TEST_SHARED" "$p (jq module executed by shared fetch core)"
    add_selected "$SUITE_TEST_CHANGE_DETECT_POLL" "$p (jq module executed by change-detect poll)"
    add_selected "$SUITE_TEST_PREFILTER" "$p (jq module executed by prefilter)"
    matched=1
  fi

  # test_prefilter: the prefilter script (.sh) + the tests/fix-history/* fixtures it reuses as inputs.
  # The script is ALSO a plugin/* file (policy_check prose-lints it via the wholesale rule below), but
  # policy_check NEVER EXECUTES bash — so a prefilter edit must route to the behavioral suite.
  # tests/fix-history/* is routed here in addition to test_fix_history_classify / test_fetch_normalize
  # above: a fixture edit changes this suite's inputs too. (tools/test_prefilter.sh itself is covered
  # by the tools/** full-suite leg.)
  if [[ "$p" == plugin/skills/github-review-loop/scripts/prefilter.sh \
     || "$p" == tools/test_prefilter.sh \
     || "$p" == tests/fix-history/* ]]; then
    add_selected "$SUITE_TEST_PREFILTER" "$p (prefilter script/fixture)"
    matched=1
  fi

  # _shared/graphql-response.sh: the shared GraphQL errors validator sourced by the review-loop
  # scripts. Its regressions surface in every consumer, so route to each consumer's behavior oracle:
  # fetch-normalize, change-detect-poll, prefilter, react-marker, reply-resolve. (test_shared_libs,
  # test_script_bootstrap and policy_check already match via the generic _shared/*.sh, plugin/**/*.sh
  # and plugin/* rules.)
  if [[ "$p" == plugin/skills/_shared/graphql-response.sh ]]; then
    add_selected "$SUITE_TEST_FETCH_NORMALIZE" "$p (graphql-response lib sourced by fetch-normalize)"
    add_selected "$SUITE_TEST_CHANGE_DETECT_POLL" "$p (graphql-response lib sourced by change-detect poll)"
    add_selected "$SUITE_TEST_PREFILTER" "$p (graphql-response lib sourced by prefilter)"
    add_selected "$SUITE_TEST_REACT_MARKER" "$p (graphql-response lib sourced by react-marker)"
    add_selected "$SUITE_TEST_REPLY_RESOLVE" "$p (graphql-response lib sourced by reply-resolve)"
    matched=1
  fi

  # test_shared_libs: every review-loop script. A forthcoming glob-closure test in test_shared_libs
  # asserts each review-loop script adopts the shared libs, so any scripts/*.sh edit must run it.
  if [[ "$p" == plugin/skills/github-review-loop/scripts/*.sh ]]; then
    add_selected "$SUITE_TEST_SHARED" "$p (review-loop script glob-closure)"
    matched=1
  fi

  # test_fetch_normalize: the fetch + normalize candidate-set builder (.sh) + its payload/expected
  # fixtures. The script is ALSO a plugin/* file (policy_check prose-lints it via the wholesale rule
  # below), but policy_check NEVER EXECUTES bash — so without this rule a fetch-normalize edit would
  # only be prose-linted, never behaviorally exercised. Route both the script and its fixture dir to
  # the behavioral suite. (tools/test_fetch_normalize.sh itself is covered by the tools/** leg.)
  # tests/fix-history/* is ALSO routed here: test_fetch_normalize.sh reuses the fix-history fixtures
  # (FIX_HISTORY_DIR) as its review-path inputs, so a fix-history fixture edit changes this suite's
  # inputs too — without this leg a fixture-only PR would skip the fetch-normalize suite pre-PR and
  # leave stale expected outputs to be caught only by the full push-to-main gate (Codex P2 PR #210).
  if [[ "$p" == plugin/skills/github-review-loop/scripts/fetch-normalize.sh \
     || "$p" == tests/fetch-normalize/* \
     || "$p" == tests/fix-history/* ]]; then
    add_selected "$SUITE_TEST_FETCH_NORMALIZE" "$p (fetch-normalize builder/fixture)"
    matched=1
  fi

  # test_exit_precedence: the exit-precedence decision script + its inline test harness. The .sh
  # script is ALSO a plugin/* file (policy_check prose-lints it via the wholesale rule below), but
  # policy_check NEVER EXECUTES bash — so without this rule a script edit would only be prose-linted,
  # never behaviorally exercised. Tests are inline table-driven (no fixture dir).
  # (tools/test_exit_precedence.sh itself is covered by the tools/** full-suite leg.)
  if [[ "$p" == plugin/skills/github-review-loop/scripts/exit-precedence.sh \
     || "$p" == tools/test_exit_precedence.sh ]]; then
    add_selected "$SUITE_TEST_EXIT_PRECEDENCE" "$p (exit-precedence script/test)"
    matched=1
  fi

  # test_loop_state: the loop-state decision script + its inline test harness. The .sh
  # script is ALSO a plugin/* file (policy_check prose-lints it via the wholesale rule below), but
  # policy_check NEVER EXECUTES bash — so without this rule a script edit would only be prose-linted,
  # never behaviorally exercised. Tests are inline table-driven (no fixture dir).
  # (tools/test_loop_state.sh itself is covered by the tools/** full-suite leg.)
  if [[ "$p" == plugin/skills/github-review-loop/scripts/loop-state.sh \
     || "$p" == tools/test_loop_state.sh ]]; then
    add_selected "$SUITE_TEST_LOOP_STATE" "$p (loop-state script/test)"
    matched=1
  fi

  # test_reply_resolve: the reply + resolve script (.sh) + its fixture dir. The script is ALSO a
  # plugin/* file (policy_check prose-lints it via the wholesale rule below), but policy_check NEVER
  # EXECUTES bash — so without this rule a reply-resolve edit would only be prose-linted, never
  # behaviorally exercised. Route both the script and its fixture dir to the behavioral suite.
  # (tools/test_reply_resolve.sh itself is covered by the tools/** full-suite leg.)
  if [[ "$p" == plugin/skills/github-review-loop/scripts/reply-resolve.sh \
     || "$p" == tools/test_reply_resolve.sh \
     || "$p" == tests/reply-resolve/* ]]; then
    add_selected "$SUITE_TEST_REPLY_RESOLVE" "$p (reply-resolve script/fixture)"
    matched=1
  fi

  # test_react_marker: the react-marker script (.sh) + its fixture dir. The script is ALSO a
  # plugin/* file (policy_check prose-lints it via the wholesale rule below), but policy_check NEVER
  # EXECUTES bash — so without this rule a react-marker edit would only be prose-linted, never
  # behaviorally exercised. Route both the script and its fixture dir to the behavioral suite.
  # (tools/test_react_marker.sh itself is covered by the tools/** full-suite leg.)
  if [[ "$p" == plugin/skills/github-review-loop/scripts/react-marker.sh \
     || "$p" == tools/test_react_marker.sh \
     || "$p" == tests/react-marker/* ]]; then
    add_selected "$SUITE_TEST_REACT_MARKER" "$p (react-marker script/fixture)"
    matched=1
  fi

  # test_change_detect_poll: the thin PR change-detection poll script (.sh) + its fixture dir. The
  # script is ALSO a plugin/* file (policy_check prose-lints it via the wholesale rule below), but
  # policy_check NEVER EXECUTES bash — so without this rule a change-detect-poll edit would only be
  # prose-linted, never behaviorally exercised. Route both the script and its fixture dir to the
  # behavioral suite. (tools/test_change_detect_poll.sh itself is covered by the tools/** leg.)
  if [[ "$p" == plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh \
     || "$p" == tools/test_change_detect_poll.sh \
     || "$p" == tests/change-detect-poll/* ]]; then
    add_selected "$SUITE_TEST_CHANGE_DETECT_POLL" "$p (change-detect-poll script/fixture)"
    matched=1
  fi

  # test_ledger_reconstruct: the ledger-reconstruct script (.sh) + its fixture dir. The script is
  # ALSO a plugin/* file (policy_check prose-lints it via the wholesale rule below), but
  # policy_check NEVER EXECUTES bash — so without this rule a ledger-reconstruct edit would only
  # be prose-linted, never behaviorally exercised. Route both the script and its fixture dir to
  # the behavioral suite. (tools/test_ledger_reconstruct.sh itself is covered by the tools/** leg.)
  if [[ "$p" == plugin/skills/github-review-loop/scripts/ledger-reconstruct.sh \
     || "$p" == tools/test_ledger_reconstruct.sh \
     || "$p" == tests/ledger-reconstruct/* ]]; then
    add_selected "$SUITE_TEST_LEDGER_RECONSTRUCT" "$p (ledger-reconstruct script/fixture)"
    matched=1
  fi

  # test_triage_ops: the triage-backlog ops script(s) (.sh) + its fixture dir. The script is ALSO a
  # plugin/* file (policy_check prose-lints it via the wholesale rule below), but policy_check NEVER
  # EXECUTES bash — so without this rule a triage-ops edit would only be prose-linted, never
  # behaviorally exercised. Route both the script glob and its fixture dir to the behavioral suite.
  # (tools/test_triage_ops.sh itself is covered by the tools/** full-suite leg.)
  if [[ "$p" == plugin/skills/triage-backlog/scripts/*.sh \
     || "$p" == tests/triage-backlog/* ]]; then
    add_selected "$SUITE_TEST_TRIAGE_OPS" "$p (triage-ops script/fixture)"
    matched=1
  fi

  # test_subissue_ops: the prd-to-issues ops script(s) (.sh) + its fixture dir. The script is ALSO
  # a plugin/* file (policy_check prose-lints it via the wholesale rule below), but policy_check
  # NEVER EXECUTES bash — so without this rule a subissue-ops edit would only be prose-linted, never
  # behaviorally exercised. Route both the script glob and its fixture dir to the behavioral suite.
  # (tools/test_subissue_ops.sh itself is covered by the tools/** full-suite leg.)
  if [[ "$p" == plugin/skills/prd-to-issues/scripts/*.sh \
     || "$p" == tools/test_subissue_ops.sh \
     || "$p" == tests/prd-to-issues/* ]]; then
    add_selected "$SUITE_TEST_SUBISSUE_OPS" "$p (subissue-ops script/fixture)"
    matched=1
  fi

  # test_seed_hive: the seed-hive entrypoint (composes the four sourced settings/companion libs)
  # + its integration fixtures. The entrypoint is ALSO a plugin/* file (policy_check prose-lints
  # it via the wholesale rule below), but policy_check NEVER EXECUTES bash — so without this rule
  # an entrypoint edit would only be prose-linted, never behaviorally exercised. test_seed_hive.sh
  # is the integration oracle that drives detect/apply end-to-end against tmp project roots, so an
  # edit to the entrypoint must trigger it or seed-hive regressions go untested under --changed.
  # (The four _shared libs it composes already route to test_shared_libs via the _shared/*.sh rule
  # below — their unit oracle. settings-merge.sh is the exception: see the settings-merge.sh note
  # immediately below — it ALSO routes here, so test_shared_libs is not its sole oracle. Rule below
  # is the sole oracle for the other three. tools/test_seed_hive.sh itself is covered by the
  # tools/** leg.)
  # Also settings-merge.sh: test_seed_hive.sh pins the documented exit-0-with-Output contract for
  # `seed-hive apply` against a settings file holding a non-object hook element — a regression in
  # settings-merge.sh's element-access path. test_shared_libs alone does not exercise that contract,
  # so a settings-merge.sh-only edit must ALSO trigger test_seed_hive or that pin never fires under
  # `--changed` (same precedent as containment.sh -> test_engine + test_brood_compat and
  # ledger-engine-io.sh -> test_engine above: a _shared lib routed to more than one behavior oracle
  # because test_shared_libs alone does not cover a contract owned elsewhere).
  if [[ "$p" == plugin/skills/seed-hive/scripts/* \
     || "$p" == plugin/skills/_shared/settings-merge.sh ]]; then
    add_selected "$SUITE_TEST_SEED_HIVE" "$p (seed-hive entrypoint)"
    matched=1
  fi

  # test_script_bootstrap: the fail-closed bootstrap prologue of every self-locating plugin engine
  # (ADR-0020 Amendment 2026-09-29, forms C1-C5). The suite's closure check fails until a NEW
  # self-locating plugin/**/*.sh is enrolled in its bootstrap table, so EVERY plugin shell file —
  # not only the currently enrolled engines — routes here: a new script, or an existing one that
  # starts to self-locate, must trigger the enrolment gate pre-PR. The .sh files are ALSO plugin/*
  # files (policy_check prose-lints them via the wholesale rule below), but policy_check NEVER
  # EXECUTES bash, so without this rule a bootstrap regression would only be caught on push-to-main.
  # (tools/test_script_bootstrap.sh itself is covered by the tools/** full-suite leg.)
  if [[ "$p" == plugin/* && "$p" == *.sh ]]; then
    add_selected "$SUITE_TEST_SCRIPT_BOOTSTRAP" "$p (engine bootstrap/self-location contract)"
    matched=1
  fi

  # policy_check: all plugin/.claude-plugin runtime + policy/plugin/workflows fixtures.
  if [[ "$p" == plugin/* \
     || "$p" == .claude-plugin/* \
     || "$p" == tests/policy/* \
     || "$p" == tests/plugin/* \
     || "$p" == tests/workflows/* ]]; then
    add_selected "$SUITE_POLICY_CHECK" "$p (policy/contract surface)"
    matched=1
  fi

  # policy_check: README.md. Although README.md lives outside every code tree (docs-only by
  # location), policy_check's compatibility fixtures tests/plugin/readme-agent-names-match.json
  # and tests/plugin/readme-skill-names-match.json READ README.md. A README-only PR would
  # otherwise select no suite and merge with PR CI green, only for the push-to-main full suite
  # to fail if an agent/skill name drifted. Route README.md through policy_check --strict so the
  # README compatibility contract is exercised pre-PR.
  if [[ "$p" == "README.md" ]]; then
    add_selected "$SUITE_POLICY_CHECK" "$p (README compatibility fixtures in policy_check)"
    matched=1
  fi

  # policy_check + json-manifests: .claude/settings.json. Although it lives outside every code
  # tree (docs-only by location), policy_check's fixture
  # tests/policy/safety-navigator-transport-rules.json asserts this file's navigator-transport
  # permission rules in `equal` mode. Those rules MUST be spelled Edit(<pattern>): from Claude
  # Code 2.1.210 onward a Write(<pattern>) rule is accepted by settings parsing but NEVER matched
  # by file permission checks, so respelling Edit( as Write( silently stops suppressing the prompt
  # while still looking correct. That set check is the only mechanical guard against the silent
  # unmatch, so a settings-only PR must exercise it pre-PR rather than pass a green gate that ran
  # nothing.
  #
  # policy_check alone is NOT sufficient: its fixture extracts the permission rules from RAW TEXT,
  # so a settings file whose JSON is broken OUTSIDE the matched rules — dropping the comma after
  # the permissions object, an unterminated string, a trailing comma — still yields the expected
  # rule set and passes, even though Claude Code cannot LOAD the file. Nothing else parses it
  # either: json-manifests' parses were pinned to the two plugin manifests. So route settings.json
  # to json-manifests as well, whose leg now parses it with python3 json.load. Two suites, two
  # distinct properties: policy_check asserts WHAT the rules say, json-manifests asserts the file
  # is still loadable JSON.
  #
  # Deliberately NOT an early return and NOT a .claude/* glob — only settings.json is
  # fixture-asserted and parse-gated, and escalating all of .claude/ would burn full-suite time on
  # files no suite tests. settings.local.json is deliberately excluded: it is gitignored and
  # absent in CI, so a hardcoded parse of it would fail the suite on every runner.
  if [[ "$p" == ".claude/settings.json" ]]; then
    add_selected "$SUITE_POLICY_CHECK" "$p (navigator-transport rule fixture in policy_check)"
    add_selected "$SUITE_JSON_MANIFESTS" "$p (JSON parse gate — Claude Code must be able to load it)"
    matched=1
  fi

  # policy_check: docs/adr/*. ADRs live outside every code tree (docs-only by location), but
  # policy_check fixtures PIN ADR content as raw text (e.g. the permission-allowlist posture
  # recorded in docs/adr/0010-permission-allowlist-posture.md). An ADR-only PR would otherwise
  # select no suite and merge with PR CI green, leaving a broken pin to fire only on the
  # push-to-main full run. Scoped to the DIRECTORY, not per-file, so a fixture pinning a
  # different ADR is covered by construction rather than by remembering to add a rule. Deliberately
  # NOT docs/* — only docs/adr/ is fixture-pinned, and widening would burn the suite on unpinned prose.
  if [[ "$p" == docs/adr/* ]]; then
    add_selected "$SUITE_POLICY_CHECK" "$p (ADR content pinned by policy_check fixture)"
    matched=1
  fi

  # policy_check: web/*. The published web surface lives outside every code tree (docs-only by
  # location), but policy_check fixtures PIN its content as raw text (e.g. the capability copy in
  # web/functionality.html). A web-only PR would otherwise select no suite and merge with PR CI
  # green, leaving a broken pin to fire only on the push-to-main full run. Scoped to the
  # DIRECTORY, not per-file, so a fixture pinning a different web page is covered by construction.
  if [[ "$p" == web/* ]]; then
    add_selected "$SUITE_POLICY_CHECK" "$p (web content pinned by policy_check fixture)"
    matched=1
  fi

  # policy_check: CLAUDE.md. Although it lives outside every code tree (docs-only by location),
  # policy_check fixtures PIN its content as raw text (the repo-guidance contract consumed by
  # agents working in this repo). A CLAUDE.md-only PR would otherwise select no suite and merge
  # with PR CI green, leaving a broken pin to fire only on the push-to-main full run. Literal
  # filename, matching the README.md leg above: only this file is fixture-pinned. CONTEXT.md is
  # deliberately NOT routed — no fixture pins it, and routing an unpinned path would assert
  # coverage that does not exist.
  if [[ "$p" == "CLAUDE.md" ]]; then
    add_selected "$SUITE_POLICY_CHECK" "$p (CLAUDE.md content pinned by policy_check fixture)"
    matched=1
  fi

  if [[ "$matched" -eq 1 ]]; then
    return 0
  fi

  # Docs-only: outside every code-bearing tree -> no code suites.
  case "$p" in
    plugin/*|.claude-plugin/*|tools/*|tests/*)
      # Inside a code tree but matched nothing above -> FAIL-CLOSED.
      force_full "unmapped path inside code tree ($p) — full suite"
      ;;
    *)
      echo "  docs-only (no code suite): $p"
      ;;
  esac
}

# ── --changed plumbing ─────────────────────────────────────────────────────────────
# resolve_base: echo a resolved base ref (a commit-ish usable in `git diff <base>...HEAD`),
# or empty string if none resolves. For each candidate it requires a successful merge-base
# with HEAD.
#
# FAIL-CLOSED on explicit base: when the caller supplies an explicit --base (e.g. the PR
# workflow's `--base origin/main`), that ref is the ONLY candidate. If it cannot be verified
# (detached/shallow checkout where the explicit ref is missing), we return empty rather than
# silently narrowing to origin/main/main/HEAD~1 — a narrower fallback would map only the last
# commit and skip earlier runtime-file changes in a multi-commit PR, defeating the advertised
# fail-closed posture. An empty return drives run_changed to escalate to the FULL suite. The
# origin/main → main → HEAD~1 fallback chain applies ONLY when no explicit base was supplied.
resolve_base() {
  local explicit="$1"
  local cand
  local -a candidates=()
  if [[ -n "$explicit" ]]; then
    candidates+=("$explicit")
  else
    candidates+=(origin/main main HEAD~1)
  fi

  for cand in "${candidates[@]}"; do
    if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then
      local mb
      if mb="$(git merge-base "$cand" HEAD 2>/dev/null)" && [[ -n "$mb" ]]; then
        echo "$mb"
        return 0
      fi
    fi
  done
  echo ""
  return 0
}

# changed_files: print the de-duped changed-file set: committed diff base...HEAD UNION
# unstaged/working diff UNION porcelain status paths (uncommitted/in-progress edits).
changed_files() {
  local base="$1"
  {
    # --no-renames: when Git detects a rename, --name-only reports ONLY the destination, so a
    # PR that moves a runtime file (e.g. plugin/governance/foo.md -> docs/foo.md) would be
    # classified docs-only and skip every suite even though the plugin payload lost a runtime
    # file. Disabling rename detection emits the original (deleted) path AND the new path as
    # separate entries, so the source code-tree path still triggers the fail-closed/policy leg.
    git diff --no-renames --name-only "$base...HEAD" 2>/dev/null || true
    git diff --no-renames --name-only HEAD 2>/dev/null || true
    # Porcelain: strip the 2-char XY status + space; handle "old -> new" renames (both paths).
    git status --porcelain 2>/dev/null | while IFS= read -r line; do
      local rest="${line:3}"
      if [[ "$rest" == *' -> '* ]]; then
        printf '%s\n' "${rest%% -> *}" "${rest##* -> }"
      else
        printf '%s\n' "$rest"
      fi
    done
  } | sed '/^$/d' | sort -u
}

run_changed() {
  local base_arg="$1"
  local base
  base="$(resolve_base "$base_arg")"

  if [[ -z "$base" ]]; then
    echo "validate.sh --changed: NO base ref resolved (tried '${base_arg:-<none>}', origin/main, main, HEAD~1)." >&2
    echo "FAIL-CLOSED: running FULL suite." >&2
    run_suites "${ALL_SUITES[@]}"
    return $?
  fi

  echo "validate.sh --changed"
  echo "resolved base: $base"

  local -a files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done < <(changed_files "$base")

  echo "changed-file set (${#files[@]}):"
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "  (none)"
    echo "no impacted files — exit 0"
    return 0
  fi
  local f
  for f in "${files[@]}"; do
    echo "  $f"
  done

  echo "mapping:"
  for f in "${files[@]}"; do
    map_path "$f"
  done

  if [[ "$FORCE_FULL" -eq 1 ]]; then
    echo "FAIL-CLOSED escalation: $FORCE_FULL_REASON"
    local full_rc=0
    if [[ "$FORCE_FULL_SELFTEST" -eq 1 ]]; then
      echo "validator-bootstrap change — running --self-test (mapping-coverage gate) first."
      echo
      echo "=== validate.sh: running [self-test] ==="
      if self_test; then
        echo "--- [self-test] PASS ---"
      else
        echo "--- [self-test] FAIL ---" >&2
        full_rc=1
      fi
    fi
    echo "running FULL suite."
    run_suites "${ALL_SUITES[@]}" || full_rc=1
    return "$full_rc"
  fi

  # De-dupe SELECTED into a unique suite list, printing WHY each suite was selected.
  local -a suites=()
  local entry suite reason seen
  declare -A reasons_seen=()
  for entry in "${SELECTED[@]}"; do
    suite="${entry%%$'\t'*}"
    reason="${entry#*$'\t'}"
    echo "  select [$suite] <- $reason"
    seen=0
    for s in "${suites[@]:-}"; do
      [[ "$s" == "$suite" ]] && seen=1 && break
    done
    [[ "$seen" -eq 0 ]] && suites+=("$suite")
  done

  echo
  echo "selected ${#suites[@]} suite(s)."
  run_suites "${suites[@]}"
  return $?
}

# ── --self-test (mapping-coverage assertion) ────────────────────────────────────────
self_test() {
  local fails=0
  echo "validate.sh --self-test: mapping coverage"

  # 1. Every KNOWN_SUITES entry must be referenced by at least one mapping rule. We probe by
  #    feeding a representative path per suite and asserting map_path selects it.
  declare -A probe=(
    ["policy_check.sh"]="plugin/agents/overlord.md"
    ["validate_reports.sh"]="tests/reports/some-fixture.txt"
    ["validate_workflows.sh"]="plugin/workflows/main.json"
    ["test_engine.sh"]="tests/engine/ledger-x.json"
    ["test_shared_libs.sh"]="plugin/skills/_shared/allowlist.sh"
    ["test_brood_compat.sh"]="tests/brood/manifest-x.json"
    ["test_fix_history_classify.sh"]="tests/fix-history/case01-x.json"
    ["test_fetch_normalize.sh"]="tests/fetch-normalize/case-x.json"
    ["test_exit_precedence.sh"]="plugin/skills/github-review-loop/scripts/exit-precedence.sh"
    ["test_loop_state.sh"]="plugin/skills/github-review-loop/scripts/loop-state.sh"
    ["test_reply_resolve.sh"]="tests/reply-resolve/README.md"
    ["test_react_marker.sh"]="tests/react-marker/README.md"
    ["test_ledger_reconstruct.sh"]="tests/ledger-reconstruct/README.md"
    ["test_triage_ops.sh"]="tests/triage-backlog/case-x.json"
    ["test_subissue_ops.sh"]="tests/prd-to-issues/case-x.json"
    ["test_seed_hive.sh"]="plugin/skills/seed-hive/scripts/seed-hive.sh"
    ["test_rc_brood.sh"]="plugin/skills/enable-brood-remote/SKILL.md"
    ["test_next_wave.sh"]="tests/next-wave/ledger-x.json"
    ["test_bump_type.sh"]="plugin/skills/bump-type/scripts/bump-type.sh"
    ["test_validate_suites.sh"]="tools/test_validate_suites.sh"
    ["test_change_detect_poll.sh"]="tests/change-detect-poll/README.md"
    ["test_script_bootstrap.sh"]="plugin/skills/_shared/claude-mem-path.sh"
    ["test_prefilter.sh"]="plugin/skills/github-review-loop/scripts/prefilter.sh"
  )
  local script_name expected_suite suite_path probe_path hit
  for script_name in "${KNOWN_SUITES[@]}"; do
    probe_path="${probe[$script_name]:-}"
    if [[ -z "$probe_path" ]]; then
      echo "FAIL: KNOWN_SUITES entry '$script_name' has no --self-test probe path"
      fails=$((fails + 1))
      continue
    fi
    SELECTED=(); FORCE_FULL=0; FORCE_FULL_REASON=''
    map_path "$probe_path" >/dev/null
    hit=0
    for entry in "${SELECTED[@]:-}"; do
      suite_path="${entry%%$'\t'*}"
      # suite_path is like "validate_workflows.sh --strict" or "json-manifests"; match prefix.
      if [[ "$suite_path" == "$script_name"* ]]; then hit=1; break; fi
    done
    if [[ "$hit" -eq 1 ]]; then
      echo "PASS: suite $script_name reachable via $probe_path"
    else
      echo "FAIL: suite $script_name NOT reachable from probe $probe_path"
      fails=$((fails + 1))
    fi
  done

  # 2. Every tools/*.sh validation suite must be in KNOWN_SUITES or NON_SUITE_TOOLS.
  local tool base in_known in_non
  while IFS= read -r tool; do
    base="$(basename "$tool")"
    in_known=0; in_non=0
    for s in "${KNOWN_SUITES[@]}"; do [[ "$s" == "$base" ]] && in_known=1 && break; done
    for s in "${NON_SUITE_TOOLS[@]}"; do [[ "$s" == "$base" ]] && in_non=1 && break; done
    if [[ "$in_known" -eq 1 || "$in_non" -eq 1 ]]; then
      echo "PASS: tools/$base classified (known=$in_known non-suite=$in_non)"
    else
      echo "FAIL: tools/$base is unclassified — add to KNOWN_SUITES (with a mapping rule) or NON_SUITE_TOOLS"
      fails=$((fails + 1))
    fi
  done < <(find "$SCRIPT_DIR" -maxdepth 1 -name '*.sh' -type f | sort)

  # 3. Every top-level tests/<dir>/ must map to some suite (a sentinel path under it must
  #    either select a suite or FAIL-CLOSED to full — never docs-only/no-suite).
  local d dname sentinel
  if [[ -d "$REPO_ROOT/tests" ]]; then
    while IFS= read -r d; do
      dname="$(basename "$d")"
      sentinel="tests/$dname/__selftest_probe__"
      SELECTED=(); FORCE_FULL=0; FORCE_FULL_REASON=''
      map_path "$sentinel" >/dev/null
      if [[ ${#SELECTED[@]} -gt 0 || "$FORCE_FULL" -eq 1 ]]; then
        echo "PASS: tests/$dname maps (suites=${#SELECTED[@]} full=$FORCE_FULL)"
      else
        echo "FAIL: tests/$dname maps to NO suite and does not FAIL-CLOSED"
        fails=$((fails + 1))
      fi
    done < <(find "$REPO_ROOT/tests" -maxdepth 1 -mindepth 1 -type d | sort)
  fi

  # 4. An unmapped sentinel inside a code tree must FAIL-CLOSED to full suite. Use a path
  #    under tests/ whose subdir matches no mapping rule (plugin/* and .claude-plugin/* are
  #    wholesale policy_check surfaces, so they can never be "unmapped").
  SELECTED=(); FORCE_FULL=0; FORCE_FULL_REASON=''
  map_path "tests/__no_such_dir__/unmapped.xyz" >/dev/null
  if [[ "$FORCE_FULL" -eq 1 ]]; then
    echo "PASS: unmapped code-tree sentinel -> FULL suite"
  else
    echo "FAIL: unmapped code-tree sentinel did NOT FAIL-CLOSED"
    fails=$((fails + 1))
  fi

  # 5. tools/** sentinel must FAIL-CLOSED to full suite.
  SELECTED=(); FORCE_FULL=0; FORCE_FULL_REASON=''
  map_path "tools/some_new_thing.sh" >/dev/null
  if [[ "$FORCE_FULL" -eq 1 ]]; then
    echo "PASS: tools/** sentinel -> FULL suite"
  else
    echo "FAIL: tools/** sentinel did NOT FAIL-CLOSED"
    fails=$((fails + 1))
  fi

  # 6. A docs-only sentinel must select NO code suite and NOT escalate. README.md is NOT a
  #    valid docs-only probe — it is routed through policy_check (its compatibility fixtures
  #    read README.md), so use a docs/ path that no rule maps.
  SELECTED=(); FORCE_FULL=0; FORCE_FULL_REASON=''
  map_path "docs/some-doc.md" >/dev/null
  if [[ ${#SELECTED[@]} -eq 0 && "$FORCE_FULL" -eq 0 ]]; then
    echo "PASS: docs/some-doc.md -> no code suites"
  else
    echo "FAIL: docs/some-doc.md selected suites (${#SELECTED[@]}) or escalated (full=$FORCE_FULL)"
    fails=$((fails + 1))
  fi

  # 6b. README.md must route through policy_check (its compatibility fixtures read README.md),
  #     NOT classify as docs-only/no-suite.
  SELECTED=(); FORCE_FULL=0; FORCE_FULL_REASON=''
  map_path "README.md" >/dev/null
  hit=0
  for entry in "${SELECTED[@]:-}"; do
    [[ "${entry%%$'\t'*}" == "$SUITE_POLICY_CHECK" ]] && hit=1 && break
  done
  if [[ "$hit" -eq 1 ]]; then
    echo "PASS: README.md -> policy_check (README compatibility fixtures)"
  else
    echo "FAIL: README.md did NOT route through policy_check (selected ${#SELECTED[@]} suites, full=$FORCE_FULL)"
    fails=$((fails + 1))
  fi

  # 6c. .claude/settings.json must route through policy_check (tests/policy/
  #     safety-navigator-transport-rules.json asserts its navigator-transport rules in equal mode),
  #     NOT classify as docs-only/no-suite.
  SELECTED=(); FORCE_FULL=0; FORCE_FULL_REASON=''
  map_path ".claude/settings.json" >/dev/null
  hit=0
  for entry in "${SELECTED[@]:-}"; do
    [[ "${entry%%$'\t'*}" == "$SUITE_POLICY_CHECK" ]] && hit=1 && break
  done
  if [[ "$hit" -eq 1 ]]; then
    echo "PASS: .claude/settings.json -> policy_check (navigator-transport rule fixture)"
  else
    echo "FAIL: .claude/settings.json did NOT route through policy_check (selected ${#SELECTED[@]} suites, full=$FORCE_FULL)"
    fails=$((fails + 1))
  fi

  # 6d. .claude/settings.json must ALSO route through the json-manifests PARSE gate. policy_check
  #     alone is not sufficient: its fixture matches the permission rules as RAW TEXT, so a
  #     settings file with a JSON syntax error outside those rules keeps the expected set and
  #     passes, even though Claude Code cannot load it. This assertion is what keeps the parse gate
  #     wired to the route; without it, dropping the json-manifests leg would leave a green gate
  #     that never parses the file.
  SELECTED=(); FORCE_FULL=0; FORCE_FULL_REASON=''
  map_path ".claude/settings.json" >/dev/null
  hit=0
  for entry in "${SELECTED[@]:-}"; do
    [[ "${entry%%$'\t'*}" == "$SUITE_JSON_MANIFESTS" ]] && hit=1 && break
  done
  if [[ "$hit" -eq 1 ]]; then
    echo "PASS: .claude/settings.json -> json-manifests (JSON parse gate)"
  else
    echo "FAIL: .claude/settings.json did NOT route through the json-manifests parse gate (selected ${#SELECTED[@]} suites, full=$FORCE_FULL)"
    fails=$((fails + 1))
  fi

  # 7. The CI workflow that runs this dispatcher must FAIL-CLOSED to full suite, never
  #    docs-only — otherwise a workflow-only edit could green a --changed run with no suites.
  SELECTED=(); FORCE_FULL=0; FORCE_FULL_REASON=''
  map_path ".github/workflows/policy-check.yml" >/dev/null
  if [[ "$FORCE_FULL" -eq 1 ]]; then
    echo "PASS: .github/workflows/** -> FULL suite"
  else
    echo "FAIL: .github/workflows/** did NOT FAIL-CLOSED (selected ${#SELECTED[@]} suites)"
    fails=$((fails + 1))
  fi

  # 8. All THREE engine SCRIPT paths must route to test_engine.sh. The KNOWN_SUITES probe (#1)
  #    reaches test_engine.sh via a tests/engine/* fixture, so it would stay green even if a
  #    script->oracle leg were dropped. Probe the three concrete engine-script paths directly so
  #    that removing any one selector glob (especially the mark-intent-fallback leg) FAILS here.
  local engine_script
  for engine_script in \
    "plugin/skills/record-state-result/scripts/record-state-result.sh" \
    "plugin/skills/init-run-ledger/scripts/init-run-ledger.sh" \
    "plugin/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh"; do
    SELECTED=(); FORCE_FULL=0; FORCE_FULL_REASON=''
    map_path "$engine_script" >/dev/null
    hit=0
    for entry in "${SELECTED[@]:-}"; do
      if [[ "${entry%%$'\t'*}" == "$SUITE_TEST_ENGINE"* ]]; then hit=1; break; fi
    done
    if [[ "$hit" -eq 1 ]]; then
      echo "PASS: engine script $engine_script -> test_engine.sh"
    else
      echo "FAIL: engine script $engine_script did NOT route to test_engine.sh"
      fails=$((fails + 1))
    fi
  done

  echo
  if [[ "$fails" -eq 0 ]]; then
    echo "--self-test: ALL PASS"
    return 0
  fi
  echo "--self-test: $fails FAILURE(S)"
  return 1
}

# ── Usage ─────────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
Usage:
  bash tools/validate.sh [--all]              Run the full CI-parity validation suite.
  bash tools/validate.sh --changed [--base R] Run only suites impacted by changed files.
  bash tools/validate.sh --self-test          Assert mapping coverage; no suites run.
  bash tools/validate.sh -h | --help          Show this help.
EOF
}

# ── Arg parsing ─────────────────────────────────────────────────────────────────────
main() {
  local mode='all'
  local base_arg=''

  if [[ $# -eq 0 ]]; then
    mode='all'
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) mode='all'; shift ;;
      --changed) mode='changed'; shift ;;
      --self-test) mode='self-test'; shift ;;
      --base)
        if [[ $# -lt 2 ]]; then
          echo "error: --base requires a ref argument" >&2
          usage >&2
          exit 2
        fi
        base_arg="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *)
        echo "error: unknown flag '$1'" >&2
        usage >&2
        exit 2 ;;
    esac
  done

  case "$mode" in
    all)
      echo "validate.sh --all (CI-parity full suite)"
      run_suites "${ALL_SUITES[@]}"
      ;;
    changed)
      run_changed "$base_arg"
      ;;
    self-test)
      self_test
      ;;
  esac
}

main "$@"
