#!/usr/bin/env bash
#
# mark-intent-fallback — sanctioned version-skew resume write-path for the
# hivemind:mark-intent-fallback skill.
#
# Provides the resume door that record-state-result.sh DELIBERATELY refuses: it appends an
# intent-fallback event to the run ledger and (optionally) closes the run WITHOUT
# transition-validation and WITHOUT the version-binding guard — the EXACT two conditions
# record-state-result.sh hard-rejects. It is the sole sanctioned write-path for a run whose
# ledger no longer binds to a packaged workflow definition (version skew), so the overlord
# resume-on-start gate's "proceed intent-driven" door has a deterministic ledger writer
# instead of an unreachable rebind.
#
# WHAT IT DELIBERATELY SKIPS (this is the whole point):
#   - NO workflow-definition derivation/read. The skewed run may reference a definition
#     version no longer packaged; reading it is neither possible nor required here.
#   - NO binding guard (definition.id / version vs ledger). Skew is the precondition, not a
#     failure — record-state-result.sh owns the hard-reject half of the §I policy; this is
#     the intent-driven half.
#   - NO state-existence check (the recorded state is NOT validated against any definition).
#   - NO transition/result validation, NO next_state resolution, NO terminal mapping.
#   - NO binding/version precondition on the closeout path either — that guard stays
#     deliberately skipped. The ONLY closeout precondition is the narrow footgun guard below:
#     when close_status is supplied, the on-disk run.status MUST be exactly "running" (you
#     cannot close out an already-terminal run). The bare mode-flip path (no close_status)
#     stays fully permissive and may run on a non-running skew ledger.
#
# WHAT IT REUSES IDENTICALLY from record-state-result.sh (security posture is unchanged):
#   - Identity derivation: run_id is the ONLY identity the caller supplies; the ledger path
#     is DERIVED as <git-root>/.hivemind/runs/<run_id>/state.json. NO path is accepted.
#   - SAFE_ID_RE + ./.. reject on run_id; coherence check (ledger.run.id == run_id).
#   - Inputs-file READ-guard + depth-complete write-chain containment (shared helper).
#   - Atomicity: every write is temp-write + atomic mv on the CANONICAL contained path; on
#     ANY validation failure the on-disk ledger is byte-unchanged (all validation runs
#     BEFORE the temp file is created).
#
# PRODUCER-AUTHORIZATION DISCIPLINE (completed_steps STRIP): this is the SECOND of two ledger
# event appenders (record-state-result.sh is the first). A fallback event is an OBSERVABILITY
# LOG — it must NEVER credit wave steps. So the mutation STRIPS completed_steps from the
# event's outputs at write time (`del(.completed_steps)` on the engine-controlled --argjson
# $outputs binding): the written event structurally CANNOT carry the key, regardless of what
# the caller supplied. Closed-by-construction, not a caller-trust check. STRIP not REJECT —
# intent-fallback is the last-resort skew-resume door and must never gain a new hard-fail mode
# (universal-fallback doctrine). Both appenders enforce producer-authorization discipline:
# record-state-result.sh GUARDS (rejects unauthorized step credits), this one STRIPS. All
# other outputs keys (summary/note/decisions[]/recurrence_origin/pr/etc.) pass through verbatim.
#
# INJECTION POSTURE: the untrusted fields state, summary, and outputs are read from the
# inputs file with jq into inert shell variables and serialized via jq --arg / --argjson
# ONLY; they never enter the jq program or any shell command source. The ONLY value passed on
# the command line is the trusted inputs-file path ($1).
#
# INPUT (single positional argument):
#   $1  Absolute or repo-relative path to a JSON inputs file authored by the navigator skill
#       via the Write tool.
#
#   Inputs JSON shape (authoritative schema in SKILL.md § Inputs JSON):
#     {
#       "run_id":       "<required> identity of the run; the ledger path is DERIVED from it.
#                        NO path is accepted.",
#       "state":        "<required> state string recorded verbatim in the appended event;
#                        NOT validated against any definition — UNTRUSTED, serialized only.",
#       "summary":      "<required> human-readable summary — UNTRUSTED, serialized only",
#       "outputs":      { ... },   // optional JSON object — UNTRUSTED, serialized only.
#                                  // KEY-PRESENCE semantics: a MISSING key OR a present-but-
#                                  // null value is ABSENT (-> defaults to {}); a present
#                                  // non-null value is SUPPLIED.
#       "close_status": "cancelled" | "complete"
#                                  // OPTIONAL. When present MUST be exactly "cancelled" or
#                                  // "complete" (anything else, notably "abandoned", is
#                                  // REJECTED). When absent, run.status is left untouched
#                                  // (the run stays running).
#     }
#
# OUTPUT:
#   - On success: writes the mutated ledger atomically and prints YAML routing lines:
#       run_id: <run_id>
#       mode: intent_fallback
#       status: <resulting run.status — close_status if supplied, else "running">
#       ledger: <canonical ledger path>
#     Exits 0.
#   - On any failure: prints `blocker: <reason>` to stderr, exits 1, ledger byte-unchanged.
#
# EXIT CONTRACT:
#   0  intent-fallback event recorded (and run optionally closed)
#   1  validation failure (ledger UNCHANGED)
#
# set -u: an unset variable is a programming error (every value is parsed from the inputs
# file). No `set -e`: failures route through blocker() with a verbose reason.
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: `jq -e has(...)`
# key-presence probes legitimately return non-zero in the normal absent-key flow, and
# grep -Eq / `[ ]` gates feed blocker() — `set -e` would abort instead of blocking cleanly.

set -u

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# SAFE_ID charset for identity components (mirrors record-state-result.sh). The reserved
# components "." and ".." pass this class but must be rejected explicitly (path traversal).
SAFE_ID_RE='^[A-Za-z0-9._-]+$'

# ── Script self-location (portable; independent of ${CLAUDE_PLUGIN_ROOT} and the caller) ──
# Resolve the plugin root from THIS script's own location, never from a caller value.
# `cd ... && pwd -P` is portable (no GNU-only readlink -f); BASH_SOURCE is set under
# `#!/usr/bin/env bash`. Layout: plugin/skills/mark-intent-fallback/scripts/ => 3 dirs up is
# the plugin root. This script reads NO workflow definition, so workflows_dir is not needed.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve the plugin root from the script directory; refusing to proceed"

# Source the shared containment helper ONCE, early — it provides both the inputs-file
# READ-guard (hivemind_assert_inputs_contained) and the write-chain guard
# (hivemind_assert_contained, used before the ledger temp-write).
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
# the untrusted state/summary/outputs) is read with jq into inert variables below — never
# interpolated into bash source or the jq program SOURCE.
INPUTS_FILE="${1:-}"

# ── Inputs-file bootstrap (shared helper) ──────────────────────────────────────
# hivemind_read_inputs_file performs, IN ORDER: the non-empty-arg check, the `[ -f ]`
# existence check, the hivemind_assert_inputs_contained defense-in-depth read-guard (run
# BEFORE the jq validity probe — `jq -e` on an attacker path is itself a JSON-validity read
# oracle), and the `jq -e .` JSON-validity probe. The "mark-intent-fallback" label reproduces
# this engine's EXACT current blocker strings. The helper never exits and emits NO stderr of
# its own: it signals WHICH failure occurred via a distinct return code (2 missing arg, 3
# missing file, 4 containment reject, 5 invalid JSON) and we map each to its fixed blocker text
# below. For the containment reject (4) the inner hivemind_assert_inputs_contained helper's own
# UNPREFIXED detail line flows to fd2 UNCAPTURED (we do NOT redirect the call's stderr), so the
# two-line shape — detail line ABOVE our `blocker:` line — is byte-preserved exactly as before
# extraction. The non-containment cases (2/3/5) had no detail line pre-extraction and stay
# single-line.
hivemind_read_inputs_file "$INPUTS_FILE" "mark-intent-fallback"
case $? in
  0) : ;;
  2) blocker "missing required argument: path to mark-intent-fallback inputs JSON file (\$1)" ;;
  3) blocker "mark-intent-fallback inputs file $INPUTS_FILE does not exist" ;;
  4) blocker "refusing to read the inputs file: $INPUTS_FILE resolves outside the checkout (symlinked ancestor)" ;;
  5) blocker "mark-intent-fallback inputs file $INPUTS_FILE is not valid JSON" ;;
  *) blocker "mark-intent-fallback: hivemind_read_inputs_file returned an unmapped status (shared library unavailable or contract drift); ledger/inputs unchanged" ;;
esac

# ── Parse fields into inert variables ─────────────────────────────────────────
# Required strings via `jq -r '.field // ""'`. The presence bools derive from KEY-PRESENCE on
# the inputs object: a MISSING key OR a present-but-null value is ABSENT; a present non-null
# value is SUPPLIED. Absent outputs defaults to {}; absent close_status leaves run.status
# untouched (run stays running).
run_id="$(jq -r '.run_id // ""' "$INPUTS_FILE")"
state="$(jq -r '.state // ""' "$INPUTS_FILE")"
summary="$(jq -r '.summary // ""' "$INPUTS_FILE")"

# have_outputs: outputs key present AND non-null. When supplied, read the raw JSON value
# (preserving its type for the up-front object check and the --argjson serialization).
if jq -e 'has("outputs") and .outputs != null' "$INPUTS_FILE" >/dev/null 2>&1; then
  have_outputs=true
  outputs="$(jq -c '.outputs' "$INPUTS_FILE")"
else
  have_outputs=false
  outputs=""
fi

# have_close_status: close_status key present AND non-null (-> run.status + state.status set
# to the validated value). Absent -> run.status left untouched (run stays running).
if jq -e 'has("close_status") and .close_status != null' "$INPUTS_FILE" >/dev/null 2>&1; then
  have_close_status=true
  close_status="$(jq -r '.close_status' "$INPUTS_FILE")"
else
  have_close_status=false
  close_status=""
fi

# ── Required-input validation ─────────────────────────────────────────────────
[ -n "$run_id" ]  || blocker "inputs file is missing required run_id"
[ -n "$state" ]   || blocker "inputs file is missing required state"
[ -n "$summary" ] || blocker "inputs file is missing required summary"

# run_id must be a single safe path component (SAFE_ID_RE + reserved-component reject). This
# is the ONLY identity the caller supplies; every path below is derived from it.
printf '%s' "$run_id" | grep -Eq "$SAFE_ID_RE" \
  || blocker "run_id is not a safe path component: $run_id"
case "$run_id" in
  .|..) blocker "run_id is a reserved path component: $run_id" ;;
esac

# ── DERIVE the ledger path from git-root + run_id (NO caller path) ─────────────
# repo_root anchors the ledger to the checkout root. Empty = not inside a git checkout =
# blocker. The caller never supplies a ledger path, so an arbitrary-file overwrite via a
# caller path is structurally impossible.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$repo_root" ] || blocker "not inside a git repository"
# Raw textual ledger path (matches the prior inline derivation). The reads below
# (close_status footgun guard, coherence already done by the helper) reference this raw path;
# the containment guards inside hivemind_open_ledger proved that the raw path and its canonical
# form resolve to the same in-checkout file. The atomic-write block below re-points $ledger at
# the CANONICAL path before any mktemp/mv.
ledger="$repo_root/.hivemind/runs/$run_id/state.json"

# ── Ledger-open machinery (shared helper) — BEFORE any ledger read ─────────────
# hivemind_open_ledger performs, IN THIS EXACT ORDER (a reordering silently breaks engine
# determinism): ledger-path derivation, the hivemind_assert_contained ancestor guard, the
# canonical-runs-dir canonicalization + trailing-slash prefix case-guard, the
# hivemind_assert_ledger_contained leaf guard (rejects a symlinked state.json LEAF), the
# `[ -f ]` existence + `jq -e .` validity reads, the coherence check (`.run.id == run_id`),
# and the post-existence canonical ledger-dir confirmation (canon dir + state.json/run_id
# basename asserts). On SUCCESS it returns 0 with NO stdout (validation rides the return
# code); the consumer DERIVES the canonical paths locally in the success arm below. The
# helper never exits. Two failure shapes (byte-preserved from before extraction):
#   - inner-helper containment rejects (return 2 = ancestor guard, 6 = leaf guard): the inner
#     helper's UNPREFIXED detail line flows to fd2 UNCAPTURED (we capture only STDOUT, never
#     `2>&1`), then we add our OWN fixed `blocker:` line below — the two-line shape.
#   - every other failure (return 1): the helper PRINTS the single reason line to STDOUT, which
#     we capture and re-emit through blocker() (adding the `blocker: ` prefix) — single-line.
# Success emits no stdout and the return-1 reason is the only stdout, so the one capture
# serves the failure arm safely. (containment.sh + the helper were sourced once early, just
# after plugin_root is computed.)
ledger_open_out="$(hivemind_open_ledger "$repo_root" "$run_id")"
ledger_open_rc=$?
case $ledger_open_rc in
  0)
    # Validation passed (the helper proved $ledger and its canonical form resolve to the same
    # in-checkout file). DERIVE the canonical ledger dir + path locally — strictly here, AFTER
    # the post-validation return 0 — for the close_status footgun read and the atomic-write
    # block below. Both are pwd -P paths under the checkout (no embedded newlines).
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

# If outputs was supplied, it must be a valid JSON object (--argjson rejects non-JSON, but
# validate up front for a clear blocker rather than a jq parse error).
if [ "$have_outputs" = true ]; then
  printf '%s' "$outputs" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || blocker "outputs must be a JSON object"
else
  outputs='{}'
fi

# ── close_status validation (the ONLY permitted close values) ──────────────────
# When supplied, close_status MUST be exactly "cancelled" or "complete". This EXPLICITLY
# rejects "abandoned" (and anything else). When absent, run.status is left untouched.
if [ "$have_close_status" = true ]; then
  case "$close_status" in
    cancelled|complete) : ;;
    *) blocker "close_status must be cancelled or complete, got: $close_status; ledger unchanged" ;;
  esac

  # ── Closeout footgun guard (close_status path ONLY) ─────────────────────────
  # You cannot close out an already-terminal run. Read the on-disk run.status from the
  # validated ledger (identity/coherence/containment all proven above) and reject unless it is
  # exactly "running". Empty/missing status -> not running -> reject (correct). This runs
  # BEFORE any mktemp/temp-write, so a reject leaves the ledger byte-unchanged. The bare
  # mode-flip path (no close_status) is intentionally NOT gated and may run on a skew ledger.
  ledger_status="$(jq -r '.run.status // ""' "$ledger")"
  [ "$ledger_status" = "running" ] \
    || blocker "close_status closeout requires a running run; run.status is '$ledger_status'; ledger unchanged"
fi

# Resulting run.status reported on stdout: the validated close_status if supplied, else the
# run stays running (the ledger's run.status is left untouched by the mutation below).
if [ "$have_close_status" = true ]; then
  result_status="$close_status"
else
  result_status="running"
fi

now_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── Atomic write: temp file beside the ledger, then mv into place ──────────────
# Use the CANONICAL (verified-contained) dir for the temp-write + atomic rename so both
# operate on the path that passed containment, not the raw textual one.
ledger_dir="$canon_ledger_dir"
ledger="$canon_ledger"
tmp_ledger="$(mktemp "$ledger_dir/.state.json.XXXXXX")" \
  || blocker "failed to create temp ledger file under $ledger_dir"

# Mutate via a single jq program. Untrusted --state / --summary / --outputs enter ONLY as
# --arg / --argjson bindings. The close clause is appended to the program ONLY when
# close_status is present — clause PRESENCE (an inert bool), never the untrusted VALUE,
# decides whether the clause runs; the value itself still arrives solely through --arg. When
# absent, run.status / state.status are left untouched. INVARIANT: the input ledger is the
# file itself; on a jq failure the temp file is removed and the on-disk ledger is untouched.
close_program=""
if [ "$have_close_status" = true ]; then
  close_program="
  | .run.status = \$close_status
  | .state.status = \$close_status"
fi

jq \
  --arg at "$now_ts" \
  --arg state "$state" \
  --arg summary "$summary" \
  --argjson outputs "$outputs" \
  --arg close_status "$close_status" \
  '
  .run.mode = "intent_fallback"
  | .events += [{
    at: $at,
    state: $state,
    result: "intent_fallback",
    next_state: null,
    summary: $summary,
    outputs: ($outputs | del(.completed_steps))
  }]
  | .run.updated_at = $at'"$close_program"'
  ' "$ledger" > "$tmp_ledger" \
  || { rm -f "$tmp_ledger"; blocker "failed to serialize the mutated ledger with jq; on-disk ledger unchanged"; }

mv -f "$tmp_ledger" "$ledger" \
  || { rm -f "$tmp_ledger"; blocker "failed to atomically install the mutated ledger at $ledger; on-disk ledger unchanged"; }

# ── Success routing ───────────────────────────────────────────────────────────
printf 'run_id: %s\n' "$run_id"
printf 'mode: intent_fallback\n'
printf 'status: %s\n' "$result_status"
printf 'ledger: %s\n' "$ledger"
exit 0
