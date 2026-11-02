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
#   - The coherence check (ledger.run.id == run_id) inside hivemind_open_ledger.
#   - Inputs-file READ-guard (exactly one JSON object) + depth-complete write-chain
#     containment (shared helper).
#   - The whole-file input contract check (hivemind_check_json, contract intent-inputs), run
#     FIRST on the intact JSON values: run_id a safe name (not . or ..), state and summary
#     non-empty strings, outputs an optional object, close_status optional and exactly
#     "cancelled" or "complete". A failure prints one fixed, value-free problem line.
#
# NO LEDGER CONTRACT: the skewed ledger is NOT checked against any contract. Beyond the
# containment guards, the coherence check and the reader's exactly-one-JSON-object rule, the
# skew door gains no hard-fail on the ledger's shape.
#   - Atomicity: every write is temp-write + atomic mv on the CANONICAL contained path; on
#     ANY validation failure the on-disk ledger is byte-unchanged (all validation runs
#     BEFORE the temp file is created).
#
# PRODUCER-AUTHORIZATION DISCIPLINE (completed_steps STRIP): this is the SECOND of two ledger
# event appenders (record-state-result.sh is the first). A fallback event is an OBSERVABILITY
# LOG — it must NEVER credit wave steps. So the mutation STRIPS completed_steps from the
# event's outputs at write time (`del(.completed_steps)` on the outputs value the mutate
# program reads from the inputs file): the written event structurally CANNOT carry the key,
# regardless of what the caller supplied. Closed-by-construction, not a caller-trust check. STRIP not REJECT —
# intent-fallback is the last-resort skew-resume door and must never gain a new hard-fail mode
# (universal-fallback doctrine). Both appenders enforce producer-authorization discipline:
# record-state-result.sh GUARDS (rejects unauthorized step credits), this one STRIPS. All
# other outputs keys (summary/note/decisions[]/recurrence_origin/pr/etc.) pass through verbatim.
#
# INJECTION POSTURE: the untrusted fields state, summary, and outputs NEVER enter the shell:
# the mutate program reads them from the inputs file as data (jq --slurpfile), so they never
# enter the jq program or any shell command source. The only values the shell reads from the
# inputs file are the checked tokens run_id and close_status (hivemind_check_json field form;
# each printed line is the whole value). No `jq -r` reads the inputs file or the ledger. The
# ONLY value passed on the command line is the trusted inputs-file path ($1).
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
#                                  // REJECTED). Missing or null is absent: run.status is
#                                  // left untouched (the run stays running).
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
# set -u: an unset variable is a programming error. No `set -e`: failures route through
# blocker() with a verbose reason.
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: the shared helpers'
# non-zero return codes (hivemind_check_json rc 1, the reader and ledger-open codes) are read
# by `case $?` maps, and `jq -e` / `[ ]` gates feed blocker() — `set -e` would abort instead
# of blocking cleanly.

set -u

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

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
# Write tool. The path is the ONLY value passed on the command line; no field from it is ever
# interpolated into bash source or the jq program SOURCE.
INPUTS_FILE="${1:-}"

# ── Inputs-file bootstrap (shared helper) ──────────────────────────────────────
# hivemind_read_inputs_file performs, IN ORDER: the non-empty-arg check, the `[ -f ]`
# existence check, the hivemind_assert_inputs_contained defense-in-depth read-guard (run
# BEFORE the jq validity probe — `jq -e` on an attacker path is itself a JSON-validity read
# oracle), and the one-object probe (exactly one JSON document, an object). The
# "mark-intent-fallback" label reproduces this engine's EXACT current blocker strings. The helper never exits and emits NO stderr of
# its own: it signals WHICH failure occurred via a distinct return code (2 missing arg, 3
# missing file, 4 containment reject, 5 not exactly one JSON object) and we map each to its
# fixed blocker text below. For the containment reject (4) the inner hivemind_assert_inputs_contained helper's own
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
  5) blocker "mark-intent-fallback inputs file $INPUTS_FILE is not a single JSON object" ;;
  *) blocker "mark-intent-fallback: hivemind_read_inputs_file returned an unmapped status (shared library unavailable or contract drift); ledger/inputs unchanged" ;;
esac

# ── Input contract (shared helper) — BEFORE any other read of the inputs file ──
# hivemind_check_json checks the WHOLE inputs file against the intent-inputs contract
# (run_id required name; state, summary required text; outputs optional object; close_status
# optional enum cancelled, complete) inside one constant jq program, on the intact JSON values.
# A failure is one value-free `<position>: <problem>` line on stdout (rc 1), re-emitted behind
# a fixed prefix. rc 2 is a caller/tool error whose reason line flows to fd2 uncaptured.
contract_problem="$(hivemind_check_json "$INPUTS_FILE" intent-inputs)"
case $? in
  0) : ;;
  1) blocker "mark-intent-fallback inputs file: $contract_problem; ledger unchanged" ;;
  *) blocker "mark-intent-fallback: hivemind_check_json failed on the inputs file; ledger/inputs unchanged" ;;
esac

# ── Token fields via the field form (checked tokens; the printed line is the whole value) ──
# run_id is a checked name (safe path component, not . or ..): the ONLY identity the caller
# supplies; every path below is derived from it. close_status is empty when absent (the run
# stays running) and otherwise exactly "cancelled" or "complete". The untrusted text fields
# (state, summary) and the outputs object are NEVER read into the shell: the mutate program
# reads them from the inputs file itself (--slurpfile).
run_id="$(hivemind_check_json "$INPUTS_FILE" intent-inputs run_id)" \
  || blocker "mark-intent-fallback: hivemind_check_json failed reading run_id; ledger/inputs unchanged"
close_status="$(hivemind_check_json "$INPUTS_FILE" intent-inputs close_status)" \
  || blocker "mark-intent-fallback: hivemind_check_json failed reading close_status; ledger/inputs unchanged"
if [ -n "$close_status" ]; then
  have_close_status=true
else
  have_close_status=false
fi

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

# ── Closeout footgun guard (close_status path ONLY) ───────────────────────────
# You cannot close out an already-terminal run. The on-disk run.status (identity/coherence/
# containment all proven above) must be exactly "running"; the comparison runs inside jq and
# the message carries no ledger value. Empty/missing status -> not running -> reject (correct).
# This runs BEFORE any mktemp/temp-write, so a reject leaves the ledger byte-unchanged. The
# bare mode-flip path (no close_status) is intentionally NOT gated and may run on a skew ledger.
if [ "$have_close_status" = true ]; then
  jq -e '.run.status == "running"' "$ledger" >/dev/null 2>&1 \
    || blocker "close_status closeout requires a running run; run.status is not running; ledger unchanged"
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

# Mutate via a single jq program. The untrusted state / summary / outputs enter ONLY as data
# read by jq from the inputs file (--slurpfile; the reader proved it holds exactly one object,
# and the contract check proved their types). Absent outputs (missing or null) becomes {}. The
# close clause is appended to the program ONLY when close_status is present — clause PRESENCE
# (an inert bool), never the VALUE, decides whether the clause runs; the checked token itself
# arrives solely through --arg. When absent, run.status / state.status are left untouched.
# INVARIANT: the input ledger is the file itself; on a jq failure the temp file is removed and
# the on-disk ledger is untouched.
close_program=""
if [ "$have_close_status" = true ]; then
  close_program="
  | .run.status = \$close_status
  | .state.status = \$close_status"
fi

jq \
  --arg at "$now_ts" \
  --slurpfile inputs "$INPUTS_FILE" \
  --arg close_status "$close_status" \
  '
  $inputs[0] as $in
  | .run.mode = "intent_fallback"
  | .events += [{
    at: $at,
    state: $in.state,
    result: "intent_fallback",
    next_state: null,
    summary: $in.summary,
    outputs: (($in.outputs // {}) | del(.completed_steps))
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
