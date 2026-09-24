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
#       never enters generated shell/jq SOURCE — it is validated by SAFE_ID_RE + reserved-
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
# ORDER: a POSITIVE SHAPE GATE runs FIRST (before (a)-(f)), so no later check ever indexes or
# iterates an untrusted plan field of the WRONG TYPE and crashes raw jq (exit 5) under
# `set -euo pipefail` BEFORE the intended clean blocker is reached. Full ordering is:
# shape gate -> (a) non-empty -> (b)-(f).
#   - SHAPE GATE (closes the whole raw-jq crash class):
#       * `.plan.steps` is not an array — a non-array string like "BAD" formerly PASSED (a) via
#         `"BAD" // [] | length` (== 3) then crashed (b) at the `.id` index.
#       * a plan step is not an object — formerly crashed (b) at the `.id` index.
#       * a step `id` is missing or not a string.
#       * a `depends_on` is present/non-null but not an array — formerly crashed (d) on iterate.
#       * a `depends_on` entry is not a string.
#     Every (a)-(f) check below then runs on SHAPE-VALID data and reaches its advertised clean
#     blocker for these shapes.
#   - empty / absent plan.steps
#   - a step missing an id
#   - duplicate step ids
#   - a depends_on referencing an unknown step id
#   - a step `id` or any `depends_on` entry that fails SAFE_ID_RE (reader-side charset belt,
#     symmetric to the `files` grammar projection and to the write-boundary guards in
#     record-state-result / init-run-ledger; a PRE-EXISTING seeded/resume ledger predating those
#     write guards could still carry a malformed id). The earlier shape gate now guarantees this
#     check runs on known-strings; its non-object/non-array arms are kept as defense-in-depth.
#     Guarantees a malformed id can NEVER reach the wave: [...] join emit.
#   - a dependency cycle
#   - remaining > 0 but wave empty with no cycle (defensive; a cycle-free acyclic notdone
#     subgraph always has a ready minimal element, so this cannot occur without a cycle)
#   - ledger missing / not valid JSON / not inside a git checkout / containment rejection
#     (delegated to the shared hivemind_open_ledger guard)
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
# SHELL FLOOR: full P18 `set -euo pipefail`. The one nonzero-returning helper this engine must
# INSPECT (hivemind_open_ledger returns 0/1/2/6) is called as an `if` condition, which suppresses
# errexit throughout the function body — so its documented return codes stay inspectable while the
# floor still guards this engine's own top-level statements.

set -euo pipefail

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# SAFE_ID charset for the run_id identity component (mirrors the sibling engines). The reserved
# components "." and ".." pass this class but are rejected explicitly (path traversal). The SAME
# constant is REUSED reader-side (validation (f)) to charset-validate every plan step `id` and
# every `depends_on` entry before the wave emit — a belt symmetric to the `files` grammar
# projection and to the write-boundary guards in record-state-result / init-run-ledger.
SAFE_ID_RE='^[A-Za-z0-9._-]+$'

# ── Script self-location (portable; independent of ${CLAUDE_PLUGIN_ROOT} and the caller) ──
# Resolve the plugin root from THIS script's own location, never from a caller value.
# `cd ... && pwd -P` is portable (no GNU-only readlink -f); BASH_SOURCE is set under
# `#!/usr/bin/env bash`. Layout: plugin/skills/next-wave/scripts/ => 3 dirs up is the plugin root.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
plugin_root="$(cd "$script_dir/../../.." && pwd -P)"

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
# so this MUST follow that source.
[ -f "$plugin_root/skills/_shared/ledger-engine-io.sh" ] || blocker "required shared library missing: skills/_shared/ledger-engine-io.sh; refusing to proceed"
. "$plugin_root/skills/_shared/ledger-engine-io.sh" || blocker "failed to source skills/_shared/ledger-engine-io.sh (unparseable); refusing to proceed"

# ── Dependency check ──────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 \
  || blocker "jq is required to read the run ledger but is not installed"

# ── Input: run_id (the ONLY caller identity) ──────────────────────────────────
run_id="${1:-}"
[ -n "$run_id" ] || blocker "missing required argument: run_id (\$1)"

# run_id must be a single safe path component (SAFE_ID_RE + reserved-component reject). This is
# the ONLY identity the caller supplies; every path below is derived from it.
printf '%s' "$run_id" | grep -Eq "$SAFE_ID_RE" \
  || blocker "run_id is not a safe path component: $run_id"
case "$run_id" in
  .|..) blocker "run_id is a reserved path component: $run_id" ;;
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
# SHAPE-VALIDATION GATE — runs FIRST, before checks (a)-(f). The (a)-(f) checks index/iterate
# untrusted plan.steps fields; several malformed SHAPES (non-array steps, non-object step,
# non-array depends_on) otherwise crash raw jq (exit 5) under `set -euo pipefail` BEFORE the
# intended clean blocker is reached. This POSITIVE shape grammar, validated FIRST, closes the whole
# raw-crash class so every check below runs on SHAPE-VALID data and its clean-blocker contract is
# reachable. Ledger untouched (read-only) on any violation, matching the rest of validation.

# `.plan.steps` MUST be an array. A non-array (e.g. the string "BAD") formerly passed the (a)
# non-empty check via `"BAD" // [] | length` (== 3) and then crashed (b) at the `.id` index.
# Checked FIRST so no later map/iteration ever touches a non-array `.plan.steps`.
steps_is_array="$(jq '(.plan.steps | type) == "array"' "$ledger")"
[ "$steps_is_array" = "true" ] || blocker "plan.steps is not an array"

# Per-step shape pass (single jq, type-first lazy-`or` via an `if/elif` chain, FIRST offender only):
# every step IS an object; `.id` is present and a string; `.depends_on` (if present/non-null) IS an
# array; every `.depends_on` entry IS a string. The `if/elif` chain short-circuits on the failing
# type gate so no field of the offending step is indexed/iterated raw. Offenders are emitted via
# `@json` (as guard (f) does) so an empty / whitespace / null offender stays a visible token.
bad_shape="$(jq -r '
  [ .plan.steps[]
    | if (type != "object") then "a plan step is not an object: " + (. | @json)
      elif (has("id") | not) then "a plan step is missing an id"
      elif ((.id | type) != "string") then "a plan step id is not a string: " + (.id | @json)
      elif (.depends_on != null) and ((.depends_on | type) != "array")
        then "a plan step depends_on is not an array: " + (.depends_on | @json)
      elif (.depends_on != null) and (.depends_on | any((type) != "string"))
        then "a plan step depends_on entry is not a string: "
             + (.depends_on | map(select((type) != "string")) | .[0] | @json)
      else empty end
  ] | .[0] // empty' "$ledger")"
[ -z "$bad_shape" ] || blocker "$bad_shape"

# (a) plan.steps present and non-empty.
steps_len="$(jq '(.plan.steps // []) | length' "$ledger")"
[ "$steps_len" -gt 0 ] || blocker "plan.steps is empty or absent; nothing to schedule"

# (b) every step carries a non-empty id.
missing_id="$(jq '[.plan.steps[] | select((.id // "") == "")] | length' "$ledger")"
[ "$missing_id" = "0" ] || blocker "a plan step is missing an id"

# (c) no duplicate step ids (report the first offender).
dup_id="$(jq -r '[.plan.steps[].id] | (group_by(.) | map(select(length > 1) | .[0]))[0] // empty' "$ledger")"
[ -z "$dup_id" ] || blocker "duplicate plan step id: $dup_id"

# (d) every depends_on references a known step id (report the first offender).
unknown_dep="$(jq -r '
  [.plan.steps[].id] as $ids
  | [ .plan.steps[] | (.depends_on // [])[] as $d | select(($ids | index($d)) == null) | $d ]
  | .[0] // empty' "$ledger")"
[ -z "$unknown_dep" ] || blocker "depends_on references unknown step id: $unknown_dep"

# (e) no dependency cycle. Kahn-style peel: each pass removes every node whose deps are all
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

# (f) every step `id` and every `depends_on` entry is a safe id (SAFE_ID_RE charset). READER-SIDE
# belt: the write-boundary guards in record-state-result / init-run-ledger stop NEW bad ids, but a
# PRE-EXISTING seeded/resume ledger predating those guards could still carry a malformed id — and a
# malformed id must NEVER reach the `wave: [...]` join emit. Symmetric to the `files` grammar
# projection in the wave jq below. The earlier SHAPE-VALIDATION GATE now guarantees this check runs
# on KNOWN-STRINGS (every step is an object, every id/dep is a string) and delivers the advertised
# clean-blocker contract for those shapes; its non-object-step and non-array-depends_on arms below
# are RETAINED as defense-in-depth belt. FAIL-CLOSED: the charset check still gates on
# `type == "string"` FIRST (jq `or` is lazy) so `test` never runs against a non-string. Offenders
# are emitted via `@json` so an empty-string offender stays a non-empty ("") token and cannot be
# misread as "no offense".
bad_id="$(jq -r --arg re "$SAFE_ID_RE" '
  [ .plan.steps[]
    | if (type != "object") then "non-object step"
      else
        ( if ((.id | type) != "string") or ((.id | test($re)) | not)
          then (.id | @json) else empty end ),
        ( if (.depends_on != null) and ((.depends_on | type) != "array")
          then "non-array depends_on"
          else ( (.depends_on // [])[]
                 | if (type != "string") or ((test($re)) | not) then @json else empty end )
          end )
      end
  ] | .[0] // empty' "$ledger")"
[ -z "$bad_id" ] || blocker "plan step id or depends_on entry fails the safe-id charset: $bad_id"

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
  blocker "remaining steps exist but no step is ready (unsatisfiable dependencies); ledger unchanged"
fi

# ── Success routing ───────────────────────────────────────────────────────────
printf 'all_done: %s\n' "$all_done"
printf 'wave: %s\n' "$wave_display"
printf 'remaining: %s\n' "$remaining"
exit 0
