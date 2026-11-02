#!/usr/bin/env bash
#
# next-wave — READ-ONLY deterministic ready-wave engine for the hivemind:next-wave skill.
#
# Computes the READY SET and the next dispatchable WAVE of plan steps for the intra-run
# parallel-wave implement loop. This is the engine that lets the overlord fan out
# independent plan steps concurrently while running serially when the
# plan graph forces it. It reads the run ledger and PRINTS a routing decision; it mutates
# NOTHING (no ledger write, no temp file, no atomic rename) — a pure read -> derive -> emit
# engine. It sits in the same committed-script engine-op family as record-state-result.sh /
# init-run-ledger.sh (shebang, blocker() helper, jq parsing into inert variables, structured
# YAML routing on stdout, exit codes) and REUSES their shared read/containment machinery.
#
# INPUT (single positional argument):
#   $1  run_id — the ONLY caller identity. A bare scalar positional (NOT an inputs-file path)
#       is used DELIBERATELY: the sole input is a charset-constrained identity token, so the
#       inert Write-tool inputs-file transport (which exists to carry UNTRUSTED free-form text
#       injection-safely, e.g. record-state-result's summary/outputs) buys nothing here. run_id
#       never enters generated shell/jq SOURCE — it is validated by hivemind_is_safe_id + reserved-
#       component reject and referenced only as "$run_id". This keeps the caller surface minimal
#       while holding the family's containment posture: NO caller-supplied PATH is ever accepted.
#
# PATH POSTURE — DERIVE-ONLY, READ-ONLY:
#   The engine NEVER accepts a path. It DERIVES the ledger as
#   "<git-root>/.hivemind/runs/<run_id>/state.json" (repo_root = git rev-parse --show-toplevel;
#   empty = not inside a checkout = blocker). The ledger read is routed through the SHARED
#   ledger-open guard (hivemind_open_ledger): depth-complete ancestor containment, canonical
#   runs-dir prefix-match, symlinked-state.json-LEAF reject, existence + JSON-validity, and the
#   coherence check (.run.id == run_id) — ALL before any jq read of ledger content. A
#   caller-supplied ledger path (arbitrary-file read) is therefore structurally impossible.
#
# COMPUTATION (all derived from ledger content; NEVER from plan.steps[].status):
#   1. steps       = .plan.steps[]  (each: id, owner, files[], depends_on[], status).
#   2. DONE SET    = union of .events[].outputs.completed_steps[] (a flat list of step-id
#                    strings), de-duplicated, SCOPED TO THE CURRENT PLAN EPOCH: a
#                    completed_steps credit counts ONLY from events whose `plan_epoch` equals
#                    the ledger's `.plan.epoch` (default 0); a credit stamped with a DIFFERENT
#                    epoch is ignored. This closes the FAIL-OPEN class `cross-generation
#                    positional-id collision` — where a prior plan generation's credit for a
#                    reused STEP-NNN id satisfied the new generation's same-id step, skipping it
#                    and silently losing work. Both `.plan_epoch` and `.plan.epoch` default to 0
#                    via `//0`, so a pre-epoch ledger (no `plan_epoch` on events, no
#                    `.plan.epoch`) behaves BYTE-IDENTICALLY to before: every event matches epoch
#                    0. Done-ness lives in EVENTS, never in plan.steps[].status (which stays
#                    planner-emitted `pending`); the engine must not depend on that status field.
#   3. READY       = steps NOT in done whose depends_on is a SUBSET of done.
#   4. WAVE        = greedy, PLAN-ORDER, maximal subset of READY that is pairwise FILE-DISJOINT.
#                    Disjointness = EXACT raw-string match over GRAMMAR-VALIDATED CANONICAL
#                    declared paths. There is NO normalization step: a positive canonical-scope
#                    grammar (item 5) admits exactly ONE spelling per path, so exact raw compare
#                    over grammar-passing paths is sound BY CONSTRUCTION. This closes the former
#                    FAIL-OPEN class `textual-alias-judged-disjoint` — where a normalize-then-
#                    compare primitive judged `src/./foo` vs `src/foo`, or `src/../pkg` vs `pkg`,
#                    DISJOINT while they hit the same real file. Any non-canonical spelling, or an
#                    under-declared (missing / null / non-array / empty) scope, is now conflicts-
#                    with-all (item 5) and runs ALONE. Walk READY in plan order; add a grammar-
#                    passing step iff its raw file set shares NO exact path with any file already
#                    claimed by an earlier wave member.
#                    RESIDUAL (documented, deferred): FILESYSTEM aliases — symlinked paths and
#                    case-insensitive-FS collisions (`src/Foo` vs `src/foo`) — can still alias to
#                    one real file yet compare distinct. Resolving them needs realpath of
#                    possibly-NONEXISTENT declared paths, which conflicts with this engine's
#                    declared-path (not filesystem-existence) comparison design; tracked as a
#                    separate issue rather than closed here.
#   5. CONFLICTS-WITH-ALL guard (conservative; the ONLY scope-classification primitive): a step
#                    runs ALONE (a wave of exactly itself) when ANY of the following hold on its
#                    RAW declared scope — the grammar is checked FAIL-CLOSED, non-array/null/
#                    missing short-circuiting FIRST so no `map`/iteration ever touches a non-array:
#                      - `.files` is missing / null / not an array / an empty array
#                      - any entry is a non-string or an empty string
#                      - any path has an EMPTY component when split on `/` (bans leading `/`,
#                        trailing `/`, and `//`)
#                      - any path component equals `.` or `..`
#                      - any path carries a glob metacharacter (`*`, `?`, `[`)
#                      - any of its files is a directory-prefix (`f + "/"`) of ANOTHER step's file
#                    This protects against planner-underdeclared/vague/non-canonical scopes forcing
#                    unsafe concurrency. Run-alone = serial = always correct; it never strands a
#                    drainable plan (same conservative lane the glob case already used).
#
# VALIDATION (all fail-closed -> `blocker: <reason>` on stderr, exit 1, nothing on stdout).
# No blocker names a value from argv or from the ledger: a plan problem names its position only,
# so a model-written id cannot add a line, a control character or bulk to the blocker. In order:
#   - run_id missing, not 1 to 255 bytes of [A-Za-z0-9._-] over the WHOLE string
#     (hivemind_is_safe_id), or the reserved component "." / "..". Checked before any read.
#   - ledger missing / not exactly one JSON object / not inside a git checkout / containment or
#     coherence rejection (delegated to the shared hivemind_open_ledger guard).
#   - CONTRACT: ONE hivemind_check_json `wave-ledger` call checks the whole ledger inside one jq
#     program, on the intact JSON values, before any other read of plan content. Its rows:
#     plan.steps required array; plan.steps[] object; plan.steps[].id required step id
#     (\A[A-Za-z0-9._-]{1,64}\z); plan.steps[].depends_on optional array;
#     plan.steps[].depends_on[] step id. Absent means missing or null; an array element is never
#     absent, so a null element fails its kind. Rows run in table order and positions in
#     ascending index (row-major), and the FIRST failure is the blocker, verbatim, as
#     `<position>: <problem>` (e.g. `plan.steps[2].depends_on[0]: not a step id (1 to 64 of
#     A-Z a-z 0-9 . _ -)`). Every later check therefore runs on shape-valid, safe-id data, so no
#     jq read below can crash on a wrong type.
#   - `plan.steps: empty, nothing to schedule`
#   - `plan.steps[N].id: duplicate step id` (N = the first index that repeats an earlier id)
#   - `plan.steps[N].depends_on[M]: unknown step id` (the first in plan order)
#   - `dependency cycle detected among plan steps`
#   - `remaining steps exist but no step is ready (unsatisfiable dependencies)` (defensive; a
#     cycle-free acyclic notdone subgraph always has a ready minimal element, so this cannot
#     occur without a cycle)
#   plugin/workflow-src/lib/waves.js mirrors the contract rows, their order and every text above;
#   tests/workflow-scripts/waves.test.mjs requires the same text from both engines.
#
# OUTPUT on success (exit 0), YAML routing lines on stdout (mirrors the sibling engines'
# YAML routing style):
#     all_done: true|false
#     wave: [STEP-00X, STEP-00Y]     # step ids to dispatch this iteration; [] when all_done
#     remaining: <N>                 # count of not-done steps
#   all_done is true IFF the done set covers every step (wave empty, remaining 0).
#
# EXIT CONTRACT:
#   0  wave computed; routing YAML on stdout
#   1  validation failure / containment rejection (nothing on stdout)
#
# SHELL FLOOR: full P18 `set -euo pipefail`. The two nonzero-returning helpers this engine must
# INSPECT (hivemind_open_ledger returns 0/1/2/6, hivemind_check_json returns 0/1/2) are called as
# `if` conditions, which suppress errexit throughout the function body — so their documented
# return codes stay inspectable while the floor still guards this engine's own top-level statements.

set -euo pipefail

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# ── Script self-location (portable; independent of ${CLAUDE_PLUGIN_ROOT} and the caller) ──
# Resolve the plugin root from THIS script's own location, never from a caller value.
# `cd ... && pwd -P` is portable (no GNU-only readlink -f); BASH_SOURCE is set under
# `#!/usr/bin/env bash`. Layout: plugin/skills/next-wave/scripts/ => 3 dirs up is the plugin root.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve the plugin root from the script directory; refusing to proceed"

# Source the shared containment helper ONCE, early. hivemind_open_ledger (sourced next)
# ORCHESTRATES its guards (hivemind_assert_contained / hivemind_assert_ledger_contained), so
# containment.sh MUST be sourced first. SOURCE-OR-DIE: a missing/unparseable shared library
# fails closed BEFORE any consumer logic — the ledger-read containment guards live in these
# libs, so proceeding without them would silently disarm containment.
[ -f "$plugin_root/skills/_shared/containment.sh" ] || blocker "required shared library missing: skills/_shared/containment.sh; refusing to proceed"
. "$plugin_root/skills/_shared/containment.sh" || blocker "failed to source skills/_shared/containment.sh (unparseable); refusing to proceed"

# Source the shared ledger engine-IO helper by the SAME self-located absolute path. It provides
# hivemind_open_ledger (the depth-complete ledger-read/containment/coherence chain). This engine
# READS an existing ledger, so it uses hivemind_open_ledger (NOT hivemind_read_inputs_file, which
# is for the inputs-file navigators). The helper ORCHESTRATES the containment.sh helpers above,
# so this MUST follow that source. It also provides the whole-string safe-id check shared with
# the sibling engines, hivemind_is_safe_id, for the run_id identity component (the reserved
# components "." and ".." pass the charset and are rejected explicitly below), and
# hivemind_check_json, whose `wave-ledger` contract checks every plan step `id` and every
# `depends_on` entry reader-side before the wave emit — a belt symmetric to the `files` grammar
# projection and to the write-boundary guards in record-state-result / init-run-ledger.
[ -f "$plugin_root/skills/_shared/ledger-engine-io.sh" ] || blocker "required shared library missing: skills/_shared/ledger-engine-io.sh; refusing to proceed"
. "$plugin_root/skills/_shared/ledger-engine-io.sh" || blocker "failed to source skills/_shared/ledger-engine-io.sh (unparseable); refusing to proceed"

# ── Dependency check ──────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 \
  || blocker "jq is required to read the run ledger but is not installed"

# ── Input: run_id (the ONLY caller identity) ──────────────────────────────────
run_id="${1:-}"
[ -n "$run_id" ] || blocker "missing required argument: run_id (\$1)"

# run_id must be a single safe path component (hivemind_is_safe_id + reserved-component reject).
# This is the ONLY identity the caller supplies; every path below is derived from it.
hivemind_is_safe_id "$run_id" \
  || blocker "run_id is not a safe path component (1 to 255 of A-Z a-z 0-9 . _ -)"
case "$run_id" in
  .|..) blocker "run_id is a reserved path component (. or ..)" ;;
esac

# ── DERIVE the ledger path from git-root + run_id (NO caller path) ─────────────
# repo_root anchors the ledger to the checkout root, mirroring the sibling engines. Empty =
# not inside a git checkout = blocker. Guarded with `|| repo_root=""` so a non-repo `git`
# exit (128) does not trip errexit before the emptiness check reports the friendly blocker.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || repo_root=""
[ -n "$repo_root" ] || blocker "not inside a git repository"
ledger="$repo_root/.hivemind/runs/$run_id/state.json"

# ── Ledger-open machinery (shared helper) — BEFORE any ledger read ─────────────
# hivemind_open_ledger performs, IN EXACT ORDER: ledger-path derivation, ancestor containment,
# canonical runs-dir prefix guard, the symlinked-state.json-LEAF reject, `[ -f ]` existence +
# `jq -e .` validity, and the coherence check (.run.id == run_id). On SUCCESS it returns 0 with
# NO stdout; the consumer DERIVES the canonical ledger path locally. The helper never exits.
# Called as an `if` condition so its nonzero returns (2 ancestor reject, 6 leaf reject, 1 any
# other failure) stay inspectable under `set -e` (errexit is suppressed inside a function run
# as an `if` condition). Failure-shape parity with the sibling engines: for 2/6 the inner
# helper's own UNPREFIXED detail line already flowed to fd2 (uncaptured); for 1 the reason text
# is on the captured stdout and re-emitted through blocker().
if ledger_open_out="$(hivemind_open_ledger "$repo_root" "$run_id")"; then
  ledger_open_rc=0
else
  ledger_open_rc=$?
fi
case $ledger_open_rc in
  0)
    # Containment/coherence proven by return 0. DERIVE the canonical ledger path LOCALLY now,
    # ONLY in this arm, AFTER the helper validated the path. FAIL-CLOSED: guard the `cd` status
    # AND emptiness so a run dir that vanished mid-flight cannot leave an empty path.
    if ! canon_ledger_dir="$(cd "$(dirname "$ledger")" && pwd -P)" || [ -z "$canon_ledger_dir" ]; then
      blocker "failed to canonicalize the ledger directory; ledger unchanged"
    fi
    ledger="$canon_ledger_dir/state.json"
    ;;
  2) blocker "refusing: ${repo_root}/.hivemind/runs/$run_id resolves outside the checkout (symlinked ancestor or leaf)" ;;
  6) blocker "refusing to read the ledger: $ledger resolves outside the checkout (symlinked ancestor or leaf)" ;;
  *) blocker "$ledger_open_out" ;;
esac

# ── Validation (all before the wave computation) ──────────────────────────────
# CONTRACT GATE — runs FIRST, before any other read of plan content. One hivemind_check_json
# `wave-ledger` call checks plan.steps, every step's shape, every step `id` and every
# `depends_on` entry on the intact JSON values (see VALIDATION in the header). Its failure line
# names a position, never a value, and is the blocker verbatim. Every check below then runs on
# shape-valid, safe-id data, so none of them can crash raw jq (exit 5) under `set -euo pipefail`.
# Ledger untouched (read-only) on any violation, matching the rest of validation.
if contract_problem="$(hivemind_check_json "$ledger" wave-ledger)"; then
  contract_rc=0
else
  contract_rc=$?
fi
case $contract_rc in
  0) ;;
  1) blocker "$contract_problem" ;;
  *) blocker "failed to check the ledger against the wave-ledger contract" ;;
esac

steps_len="$(jq '.plan.steps | length' "$ledger")"
[ "$steps_len" -gt 0 ] || blocker "plan.steps: empty, nothing to schedule"

# The first index whose id repeats an id at an earlier index.
dup_position="$(jq -r '
  [.plan.steps[].id] as $ids
  | first(range(1; $ids | length) as $i
      | select(any($ids[0:$i][]; . == $ids[$i]))
      | "plan.steps[\($i)].id") // empty' "$ledger")"
[ -z "$dup_position" ] || blocker "$dup_position: duplicate step id"

# The first depends_on entry, in plan order, that names no step id.
unknown_position="$(jq -r '
  .plan.steps as $steps
  | [$steps[].id] as $ids
  | first(range(0; $steps | length) as $i
      | ($steps[$i].depends_on // []) as $deps
      | range(0; $deps | length) as $j
      | select(any($ids[]; . == $deps[$j]) | not)
      | "plan.steps[\($i)].depends_on[\($j)]") // empty' "$ledger")"
[ -z "$unknown_position" ] || blocker "$unknown_position: unknown step id"

# No dependency cycle. Kahn-style peel: each pass removes every node whose deps are all
# already removed; after N passes an acyclic graph is fully drained. Any residue is a cycle
# (self-dependency included — a node depending on itself never drains).
cycle_residue="$(jq '
  .plan.steps as $steps
  | ([$steps[] | {key: .id, value: (.depends_on // [])}] | from_entries) as $deps
  | reduce range(0; ($steps | length)) as $_ (
      [$steps[].id];
      . as $rem
      | ($rem | map(select(. as $id | ($deps[$id] // []) | any(. as $d | ($rem | index($d)) != null) | not))) as $ready
      | ($rem - $ready)
    )
  | length' "$ledger")"
[ "$cycle_residue" = "0" ] || blocker "dependency cycle detected among plan steps"

# ── Wave computation (single jq program; emits tab-separated routing facts) ────
# Emits: <remaining>\t<all_done>\t<wave_count>\t<wave_display>
#   NO normalization: disjointness is EXACT RAW-STRING match over GRAMMAR-VALIDATED canonical
#                   declared paths. The canonical-scope grammar admits one spelling per path, so
#                   raw compare is sound — see the header (item 4/5) for the closed alias class.
#   $done           union of events[].outputs.completed_steps[] SCOPED to the current plan epoch
#                   ($cur = .plan.epoch // 0): only credits from events whose plan_epoch // 0 == $cur
#                   count (done-ness lives in events; //0 keeps pre-epoch ledgers byte-identical).
#                   TYPE-PROJECTED so a malformed event is SKIPPED, not crashed: events flow through
#                   `objects` before any field access, `.outputs` through `objects`, and each credit
#                   through `strings` — a non-object event element or non-string credit is projected
#                   OUT, never indexed/iterated raw. Well-formed events keep byte-identical semantics.
#   $allfiles       every {id, f} over grammar-CLEAN string entries only, built defensively so a
#                   non-array / non-string `files` cannot error the directory-prefix scan.
#   .ca             conflicts-with-all (run ALONE) when the RAW scope fails the canonical grammar:
#                   missing/null/non-array/empty files, a non-string or empty entry, an empty path
#                   component (leading/trailing/`//`), a `.`/`..` component, a glob metachar, OR a
#                   file that is a directory-prefix (f + "/") of ANOTHER step's file. The checks
#                   are ORDERED so the non-array/null/missing case short-circuits FIRST — `or` is
#                   lazy in jq, so no map/iteration ever runs against a non-array `files`.
#   greedy reduce   walk READY in plan order; the first step always joins (locking the wave to
#                   itself when it is conflicts-with-all); each subsequent non-conflicting step
#                   joins iff exact-file-disjoint from the already-claimed set.
main="$(jq -r '
  .plan.steps as $steps
  | (.plan.epoch // 0) as $cur
  | ([ .events[]?
       | objects
       | select((.plan_epoch // 0) == $cur)
       | (.outputs? | objects | .completed_steps[]? | strings)
     ] | unique) as $done
  | ([$steps[] | .id as $id | (.files // []) | select(type == "array") | .[] | select(type == "string") | {id: $id, f: .}]) as $allfiles
  | ($steps | map(
      .id as $id
      | . + {ca: (
          ((.files | type) != "array")
          or ((.files | length) == 0)
          or (.files | any((type != "string") or (. == "")))
          or (.files | any(split("/") | any(. == "" or . == "." or . == "..")))
          or (.files | any(test("[*?\\[]")))
          or (.files | any(. as $f | $allfiles | any((.id != $id) and (.f | startswith($f + "/")))))
        )}
    )) as $S2
  | ($S2 | map(select(.id as $id | ($done | index($id)) == null))) as $notdone
  | ($notdone | length) as $remaining
  | ($notdone | map(select((.depends_on // []) | all(. as $d | ($done | index($d)) != null)))) as $ready
  | (reduce $ready[] as $st (
        {wave: [], claimed: [], locked: false};
        . as $acc
        | if $acc.locked then $acc
          elif $st.ca then
            (if ($acc.wave | length) == 0 then {wave: [$st.id], claimed: [], locked: true} else $acc end)
          elif ($st.files | any(. as $f | ($acc.claimed | index($f)) != null)) then $acc
          else {wave: ($acc.wave + [$st.id]), claimed: ($acc.claimed + $st.files), locked: false}
          end
      ) | .wave) as $wave
  | [
      ($remaining | tostring),
      (($remaining == 0) | tostring),
      ($wave | length | tostring),
      (if ($wave | length) == 0 then "[]" else "[" + ($wave | join(", ")) + "]" end)
    ] | join("\t")
' "$ledger")"

IFS=$'\t' read -r remaining all_done wave_count wave_display <<< "$main"

# Defensive: a cycle-free notdone subgraph always exposes a ready minimal element, so a
# non-empty remainder with an empty wave is unreachable without a cycle (already rejected).
# Guard it anyway — fail closed rather than emit a stalled, actionless wave.
if [ "$remaining" -gt 0 ] && [ "$wave_count" -eq 0 ]; then
  blocker "remaining steps exist but no step is ready (unsatisfiable dependencies)"
fi

# ── Success routing ───────────────────────────────────────────────────────────
printf 'all_done: %s\n' "$all_done"
printf 'wave: %s\n' "$wave_display"
printf 'remaining: %s\n' "$remaining"
exit 0
