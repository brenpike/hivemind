#!/usr/bin/env bash
#
# init-run-ledger — deterministic run-ledger initializer for the
# hivemind:init-run-ledger skill.
#
# Creates the per-run state directory and writes the initial run ledger
# (<checkout-root>/.hivemind/runs/<run-id>/state.json) per
# ${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md. The run dir is anchored to the
# git checkout ROOT (git rev-parse --show-toplevel), NOT $(pwd): a CWD-relative dir placed
# the ledger under whatever subdir the script ran from, so resume-on-start (which looks at
# the checkout-root location) could not find it and spawned a DUPLICATE run. In a LINKED
# worktree --show-toplevel resolves to the worktree root (correct — a brood child's ledger
# lives in the child worktree, matching spawn-brood's per-strain suggested ledger path).
# Init now REQUIRES being inside a git checkout (the overlord only inits inside one).
# This script OWNS the deterministic create-and-write; the skill body is a thin
# navigator that gathers inputs and calls this script once. Mirrors the
# spawn-brood.sh committed-script precedent (shebang, set -u, blocker() helper, jq
# parsing into inert variables, structured stdout routing, exit codes).
#
# PACKAGED-DEFINITION VALIDATION: before creating the run dir, init self-locates its OWN
# packaged workflows dir (BASH_SOURCE + pwd -P, independent of ${CLAUDE_PLUGIN_ROOT} and of
# any caller value; layout: plugin/skills/init-run-ledger/scripts/ => 3 dirs up is the plugin
# root) and validates the supplied workflow id against the packaged definition: the
# definition file must EXIST, its .version must equal workflow_version, and its .start must
# equal start_state. The definition is read ONLY to validate these three facts — it does not
# drive transitions. The caller never supplies a definition path.
# workflow_version and start_state are OPTIONAL inputs. An absent value is DERIVED from the
# packaged definition's .version / .start, so the caller needs no read of the definition. A
# supplied value (legacy caller) must still equal the definition's value, else blocker. The
# start state's own definition (.states[start], compact JSON) is read before any mkdir; a
# start state missing from the definition is a blocker and leaves no run dir.
#
# INPUTS CONTRACT (issue #424): right after the inputs-file bootstrap, ONE
# hivemind_check_json init-inputs call checks the WHOLE inputs file on its intact JSON values
# (ledger-engine-io.sh), plus init-brood-parent when parent.kind is brood. A failure is the
# fixed blocker `run-ledger inputs file breaks its contract: <position>: <problem>`, which names
# no value from the file, and no run dir is created. The contract is the only input check:
# required fields, types, the parent.kind enum, the id charsets, and every plan step row.
#
# INJECTION POSTURE: no `jq -r` reads the inputs file. The tokens workflow, workflow_version,
# start_state, parent.kind, parent.brood_id, parent.strain_id and suggested_run_id are read ONLY
# through the hivemind_check_json field form, so each shell value is a whole checked token with
# no line feed or NUL to lose. The untrusted text fields user_request, normalized,
# parent.run_id, parent.manifest and plan_path, and the plan_steps array, never pass through a
# shell variable: the write program reads them from the inputs file itself (--slurpfile). Every
# other ledger field enters `jq -n` as a named --arg / --argjson binding, NEVER
# string-interpolated into the jq program or any shell command source. Blocker messages name
# only contract-checked tokens, never a text field.
# The ledger is written to a temp file and atomically renamed into place so a
# concurrent reader (the hatchery reading a child ledger) never sees a torn file.
#
# INPUT (single positional argument):
#   $1  Absolute or repo-relative path to a JSON inputs file authored by the agent
#       via the Write tool. The path is the ONLY value passed on the command line.
#       Mirrors spawn-brood.sh; rationale: docs/adr/0017-brood-spawn-mechanism.md.
#
#   Inputs JSON shape (authoritative schema in SKILL.md § Inputs JSON):
#     {
#       "workflow":         "<selected workflow id; matches plugin/workflows/<id>.json>",
#       "workflow_version": <optional int; derived from the definition's .version when
#                           absent; a supplied value must equal it>,
#       "start_state":      "<optional; derived from the definition's .start when absent;
#                            a supplied value must equal it. Becomes state.current at init>",
#       "user_request":     "<raw user request — UNTRUSTED data, serialized only>",
#       "normalized":       "<overlord's normalized summary of the request>",
#       "parent": {
#         "kind":      "none|brood",   // default none
#         "run_id":    "<required when kind=brood> parent run id",
#         "brood_id":  "<required when kind=brood> CANONICAL brood id — spawn-brood's
#                       generated GUID brood-<uuidv4> (^brood-[0-9a-f-]+$, ADR-0021).
#                       Persisted VERBATIM into .parent.brood_id (so the child ledger
#                       reconciles with the manifest). Already filesystem-safe; the
#                       internal colons->dashes pass is a defensive no-op on it.",
#         "strain_id": "<required when kind=brood> strain id",
#         "manifest":  "<required when kind=brood> manifest path"
#       },
#       "suggested_run_id": "<optional> caller-suggested run id; used verbatim. It must be a
#                            name (1 to 255 of [A-Za-z0-9._-], not . or ..), else blocker.
#                            Absent gives a derived id.",
#       "plan_steps": [ ... ],   // optional; cerebrate's plan steps as a JSON array — the
#                                // child/resume SEED path for plan.steps (NOT the primary
#                                // live writer; record-state-result --plan-steps at the
#                                // `plan` state is primary). UNTRUSTED step text — enters jq
#                                // ONLY via --argjson (pre-validated JSON). Default [].
#       "plan_path": "<optional> path to the cerebrate directive — child/resume seed for
#                     plan.path. Default null."
#     }
#
# RUN-ID DERIVATION:
#   - parent.kind=brood: child form <brood-id>--<strain-id>. The brood id is spawn-brood's
#     generated GUID brood-<uuidv4> (already filesystem-safe); it is persisted verbatim into
#     .parent.brood_id and still run through the colons->dashes transform, which is a no-op on
#     the GUID and is retained only for the retired timestamp form. strain id: safe charset.
#   - else if suggested_run_id is present (the contract has already refused an unsafe one):
#     use it verbatim.
#   - else derived: <utc-timestamp>-<workflow-id> (timestamp colons mapped to dashes so
#     the id is a safe directory name).
#   The composed run id must still pass hivemind_is_safe_id (it may exceed 255 bytes) and must
#   not be "." or ".."; that blocker names no value.
#
# OUTPUT:
#   - On success: creates <checkout-root>/.hivemind/runs/<run-id>/ and its evidence/ subdir,
#     writes state.json, prints YAML routing lines to stdout and exits 0:
#       run_id: <id>
#       ledger: <checkout-root>/.hivemind/runs/<id>/state.json
#       current_state: <start state>
#       state_definition: <compact JSON of the start state from the packaged definition>
#   - On any failure: prints `blocker: <reason>` to stderr, exits 1, writes no ledger.
#
# EXIT CONTRACT:
#   0  ledger initialized
#   1  pre-flight blocker (inputs file not a single JSON object, inputs contract broken,
#      packaged-definition mismatch, unsafe composed run id, fs failure)
#
# set -u: an unset variable is a programming error here (every value is parsed
# explicitly from the inputs file). We do NOT use `set -e`: failures are routed through
# the blocker() helper with a verbose reason rather than a bubbled raw tool error.
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: the hivemind_check_json status
# probes and `[ -e ] && blocker` value-tests legitimately return non-zero in normal flow, and the EXIT
# trap performs invocation-owned cleanup — `set -e` would abort before blocker() runs.

set -u

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# Invocation-owned run-dir cleanup. CLAIMED_DIR is set ONLY after the atomic bare
# `mkdir "$run_dir"` below succeeds — the point at which THIS invocation exclusively owns the
# leaf dir. The EXIT trap removes that invocation-owned dir IFF this invocation owns it
# (CLAIMED_DIR non-empty) AND the durable ledger is ABSENT. Set CLAIMED_DIR up front (before
# any post-claim blocker could fire) for set -u safety.
#
# STATE-KEYED, IDEMPOTENT cleanup. The destructive `rm -rf` is keyed on GROUND TRUTH — the
# existence of the durable ledger at $ledger_path — NOT on the mutable disarm flag alone. The
# flag (CLAIMED_DIR) lags the durable `mv -f` install: there is a window between the mv (which
# durably commits state.json) and the `CLAIMED_DIR=""` disarm where a TERM/INT would fire this
# EXIT trap with CLAIMED_DIR still set. Keying the rm additionally on `[ ! -f "$ledger_path" ]`
# dissolves that signal race: a signal ANYWHERE relative to the mv is harmless — once the ledger
# exists the rm never fires, so a cancelled initializer can never erase its own just-committed
# run dir (Codex Finding E, P1). The flag remains as the fast normal-exit path and to scope
# cleanup to dirs THIS invocation claimed (exclusive-ownership orphan cleanup is preserved: a
# genuine pre-ledger failure has CLAIMED_DIR set AND no ledger, so the rm still fires).
#
# ${ledger_path:-} (not bare $ledger_path): the trap is ARMED here but $ledger_path is not
# defined until later. `&&` short-circuits on the leading `[ -n "${CLAIMED_DIR:-}" ]`, and
# CLAIMED_DIR stays "" until AFTER $ledger_path is defined, so the test is never evaluated
# pre-definition today — but :- makes that robust under `set -u` even if ordering ever shifts.
#
# INVARIANT: the trap body MUST end with a guaranteed-zero statement (`:`) so a failing `rm`/test
# can never override the script's intended exit code — this script runs under `set -u` with no
# `set -e`, and blocker() exits 1; an EXIT trap whose last command fails would otherwise clobber
# that 1 (the EXIT-trap-exit-code gotcha fixed in tools/test_brood_compat.sh @ 21290bf).
# Top-level `return` is invalid in a trap here; `:`.
CLAIMED_DIR=""
trap 'if [ -n "${CLAIMED_DIR:-}" ] && [ ! -f "${ledger_path:-}" ]; then rm -rf "$CLAIMED_DIR" 2>/dev/null; fi; :' EXIT

# ── Script self-location (portable; independent of ${CLAUDE_PLUGIN_ROOT} and the caller) ──
# Resolve the packaged workflows dir from THIS script's own location, never from a caller
# value. `cd ... && pwd -P` is portable (no GNU-only readlink -f); BASH_SOURCE is set under
# `#!/usr/bin/env bash`. Layout: plugin/skills/init-run-ledger/scripts/ => 3 dirs up is the
# plugin root (verified against the real tree).
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve the plugin root from the script directory; refusing to proceed"
workflows_dir="$plugin_root/workflows"

# Source the shared containment helper ONCE, early — it provides both the inputs-file
# READ-guard (hivemind_assert_inputs_contained, used right after the inputs validity
# checks) and the write-chain guard (hivemind_assert_contained, used before the run-dir
# create). Sourcing once here keeps a single load point for both call sites below.
# SOURCE-OR-DIE: a missing or unparseable shared library fails closed BEFORE any consumer
# logic — every guard below (the inputs-containment read-guard, the write-chain containment
# guard) lives in these libs, so proceeding without them would silently disarm the guards.
# This runs BEFORE any mkdir / CLAIMED_DIR assignment, so an abort here cannot orphan a run dir.
[ -f "$plugin_root/skills/_shared/containment.sh" ] || blocker "required shared library missing: skills/_shared/containment.sh; refusing to proceed"
. "$plugin_root/skills/_shared/containment.sh" || blocker "failed to source skills/_shared/containment.sh (unparseable); refusing to proceed"

# Source the shared ledger engine-IO helper by the SAME self-located absolute path. It
# provides hivemind_read_inputs_file (the inputs-file bootstrap), hivemind_check_json (the
# inputs contract check) and hivemind_is_safe_id (the composed run-id check). init CREATES a
# ledger rather than opening an existing one, so it does NOT use hivemind_open_ledger. The helper ORCHESTRATES the containment.sh helper sourced above, so
# this MUST follow that source.
[ -f "$plugin_root/skills/_shared/ledger-engine-io.sh" ] || blocker "required shared library missing: skills/_shared/ledger-engine-io.sh; refusing to proceed"
. "$plugin_root/skills/_shared/ledger-engine-io.sh" || blocker "failed to source skills/_shared/ledger-engine-io.sh (unparseable); refusing to proceed"

# ── Dependency check ──────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 \
  || blocker "jq is required to write the run ledger but is not installed"

# ── Inputs file ───────────────────────────────────────────────────────────────
# Single positional argument: the path to a JSON inputs file the agent authored via
# the Write tool. The path is the ONLY value passed on the command line; no field is read
# with `jq -r`, and no field is interpolated into bash source or the jq program SOURCE.
INPUTS_FILE="${1:-}"

# ── Inputs-file bootstrap (shared helper) ──────────────────────────────────────
# hivemind_read_inputs_file performs, IN ORDER: the non-empty-arg check, the `[ -f ]`
# existence check, the hivemind_assert_inputs_contained defense-in-depth read-guard (run
# BEFORE the jq probe — `jq` on an attacker path is itself a JSON-validity read oracle), and
# the one-object probe (exactly one JSON document, an object). This guards the READ source;
# the later hivemind_assert_contained call guards the WRITE chain — both are needed. The helper
# never exits and emits NO stderr of its own: it signals WHICH failure occurred via a distinct
# return code (2 missing arg, 3 missing file, 4 containment reject, 5 not exactly one JSON
# object) and we map each to its fixed blocker text below. For the containment reject (4) the
# inner hivemind_assert_inputs_contained helper's own UNPREFIXED detail line flows to fd2
# UNCAPTURED (we do NOT redirect the call's stderr), so the two-line shape — detail line ABOVE
# our `blocker:` line — is preserved. The non-containment cases (2/3/5) stay single-line. Empty
# git root (not inside a checkout) is tolerated by the helper's own canonical guard; the
# write-chain repo_root check below remains the authoritative not-in-a-repo gate.
hivemind_read_inputs_file "$INPUTS_FILE" "run-ledger"
case $? in
  0) : ;;
  2) blocker "missing required argument: path to run-ledger inputs JSON file (\$1)" ;;
  3) blocker "run-ledger inputs file $INPUTS_FILE does not exist" ;;
  4) blocker "refusing to read the inputs file: $INPUTS_FILE resolves outside the checkout (symlinked ancestor)" ;;
  5) blocker "run-ledger inputs file $INPUTS_FILE is not a single JSON object" ;;
  *) blocker "run-ledger: hivemind_read_inputs_file returned an unmapped status (shared library unavailable or contract drift); ledger/inputs unchanged" ;;
esac

# block_on_contract_failure <status> <problem_line>
#
# Maps one hivemind_check_json whole-file status to its blocker. Status 1 carries the
# `<position>: <problem>` line, which names no value from the file. Any other non-zero status is
# a caller or tool error whose reason hivemind_check_json already printed on stderr.
block_on_contract_failure() {
  case "$1" in
    0) : ;;
    1) blocker "run-ledger inputs file breaks its contract: $2; no run dir created" ;;
    *) blocker "run-ledger: hivemind_check_json could not check the inputs file; no run dir created" ;;
  esac
}

# read_input_token <field>
#
# Prints the init-inputs token at <field> through the hivemind_check_json field form, or
# nothing when it is absent. Run inside a command substitution: on failure blocker() exits that
# subshell, so the caller adds `|| exit 1`.
read_input_token() {
  hivemind_check_json "$INPUTS_FILE" init-inputs "$1" \
    || blocker "run-ledger: hivemind_check_json could not read $1 from the inputs file; no run dir created"
}

# ── Inputs contract (shared helper; issue #424) ───────────────────────────────
# One whole-file check on the intact JSON values: required user_request / normalized /
# workflow, the parent.kind enum, every id charset (workflow, start_state, suggested_run_id,
# parent.brood_id, parent.strain_id) and every plan step row. A brood parent must also carry
# all four ancestry fields (init-brood-parent): a child that omits one would otherwise write a
# brood ledger with null ancestry fields, silently breaking the reconciliation trail.
contract_problem="$(hivemind_check_json "$INPUTS_FILE" init-inputs)"
block_on_contract_failure "$?" "$contract_problem"
workflow="$(read_input_token workflow)" || exit 1
workflow_version="$(read_input_token workflow_version)" || exit 1
start_state="$(read_input_token start_state)" || exit 1
parent_kind="$(read_input_token parent.kind)" || exit 1
[ -n "$parent_kind" ] || parent_kind="none"
parent_brood_id="$(read_input_token parent.brood_id)" || exit 1
parent_strain_id="$(read_input_token parent.strain_id)" || exit 1
suggested_run_id="$(read_input_token suggested_run_id)" || exit 1
if [ "$parent_kind" = "brood" ]; then
  brood_parent_problem="$(hivemind_check_json "$INPUTS_FILE" init-brood-parent)"
  block_on_contract_failure "$?" "$brood_parent_problem"
fi

# workflow_version and start_state are optional: an absent value is derived from the packaged
# definition below (Packaged-definition validation), where the integer guard on the final
# workflow_version also runs, still before any mkdir.

# ── Run-id derivation ─────────────────────────────────────────────────────────
run_id=""
if [ "$parent_kind" = "brood" ]; then
  # Child form <brood-id>--<strain-id>. parent.brood_id is spawn-brood's generated GUID
  # brood-<uuidv4> (asserted ^brood-[0-9a-f-]+$ at generation, ADR-0021), carrying no colons.
  # Its contract kind (brood-id) still ADMITS ':' — deliberate residual tolerance for the
  # retired timestamp-shaped id, harmless because it keeps rejecting path separators, control
  # bytes, and shell metacharacters. It is persisted VERBATIM into .parent.brood_id so the child
  # ledger reconciles with the manifest's canonical brood_id.
  # The colons->dashes pass is ONLY for the filesystem run-id component and is a NO-OP on the
  # GUID (spawn-brood's brood_id_safe is likewise an identity pass); it is retained as
  # defensive tolerance for the retired timestamp form. parent_brood_id stays canonical for
  # verbatim persistence below. Result equals the manifest's run.suggested_id form
  # (<brood-id>--<short>).
  parent_brood_id_safe="$(printf '%s' "$parent_brood_id" | tr ':' '-')"
  run_id="${parent_brood_id_safe}--${parent_strain_id}"
elif [ -n "$suggested_run_id" ]; then
  run_id="$suggested_run_id"
else
  # Derived form <utc-timestamp>-<workflow-id>. Map colons to dashes for a safe dir name.
  utc_ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  run_id="${utc_ts}-${workflow}"
fi

# Final defensive check: the composed run_id must be a safe single path component (a joined
# id can exceed 255 bytes). The messages name no value.
hivemind_is_safe_id "$run_id" \
  || blocker "resolved run id is not a safe path component"
case "$run_id" in
  .|..) blocker "resolved run id is a reserved path component" ;;
esac

# ── Directory creation ────────────────────────────────────────────────────────
# Anchor the run dir to the git checkout ROOT, not $(pwd). Started from a subdir a
# CWD-relative path misplaced the ledger, so resume-on-start (which reads the checkout-root
# location) could not find it and spawned a duplicate run. In a linked worktree
# --show-toplevel resolves to the worktree root (correct for brood children). Mirrors
# spawn-brood.sh's repo_root precedent. Empty result = not inside a git checkout = blocker.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$repo_root" ] || blocker "not inside a git repository"

# ── Depth-complete canonical-containment guard (shared helper; refines ADR-0019) ──
# Derive-from-ground-truth (repo_root) must be PAIRED with canonicalize-and-verify-
# containment. The ledger path is derived TEXTUALLY as
# "$repo_root/.hivemind/runs/<run_id>/state.json"; that text does NOT confine the write
# when ANY component of the chain is a SYMLINK pointing outside the checkout, so a
# subsequent mkdir/mktemp/mv would write externally. The prior inline guard enumerated
# .hivemind / .hivemind/runs BY NAME and missed the <run_id> leaf (finding-1: a symlinked
# .hivemind/runs/<run_id> escaped). The shared helper walks EVERY component of the FULL
# chain INCLUDING the <run_id> leaf, rejecting any existing symlink component at ANY depth,
# and verifies the deepest existing prefix stays inside the checkout — BEFORE the first
# mkdir/mktemp/mv. Non-existent leaf components are fine (init CREATES the run dir). The
# helper is portable (cd && pwd -P + [ -L ], no realpath/readlink -f) and set -u-safe
# (empty canonical => non-zero return). It echoes the canonical root on success; we derive
# every write path from that canonical root. A non-zero return maps to our blocker.
# (containment.sh was sourced once early, just after plugin_root is computed.)
canon_repo_root="$(hivemind_assert_contained "$repo_root" ".hivemind/runs/$run_id")" \
  || blocker "refusing to write the run ledger: ${canon_repo_root:-$repo_root}/.hivemind/runs/$run_id resolves outside the checkout (symlinked ancestor or leaf)"
[ -n "$canon_repo_root" ] || blocker "failed to canonicalize repo root $repo_root"

# Derive the ledger path from the CANONICAL root (not the raw $repo_root) so the subsequent
# mkdir -p / mktemp / mv all operate on the verified-contained canonical path.
run_dir="$canon_repo_root/.hivemind/runs/$run_id"
ledger_path="$run_dir/state.json"

[ -e "$ledger_path" ] && blocker "a ledger already exists at $ledger_path; refusing to overwrite"

# ── Packaged-definition validation ─────────────────────────────────────
# Validate the supplied workflow id against the script's OWN packaged definition BEFORE
# creating any directory (fail early, leave no orphan run dir). The workflow id is already a
# safe single path component, not . or .. (the init-inputs contract's `name` kind), before it
# becomes a path. The definition is read ONLY to confirm
# it exists and that its version/start match the supplied values — it does not drive
# transitions, and the caller never supplies its path. An absent workflow_version or
# start_state takes the definition's value, and the start state's definition is read for the
# success output.
def="$workflows_dir/$workflow.json"
[ -f "$def" ] || blocker "packaged workflow definition does not exist: $def"
def_version="$(jq -r '.version // ""' "$def")"
[ -n "$workflow_version" ] || workflow_version="$def_version"
# workflow_version must be an integer (it becomes a JSON number via --argjson). Runs on the
# final value, so a non-integer supplied value and a non-integer packaged .version both block.
case "$workflow_version" in
  ''|*[!0-9]*) blocker "workflow_version must be a non-negative integer, got: $workflow_version" ;;
esac
[ "$def_version" = "$workflow_version" ] \
  || blocker "packaged workflow definition version '$def_version' does not match workflow_version '$workflow_version'"
def_start="$(jq -r '.start // ""' "$def")"
[ -n "$start_state" ] || start_state="$def_start"
[ "$def_start" = "$start_state" ] \
  || blocker "packaged workflow definition start '$def_start' does not match start_state '$start_state'"
# The start state's own definition, printed on success so the caller needs no read of the
# definition file. Read before any mkdir: a start state the definition does not declare is a
# blocker that leaves no run dir. A jq failure leaves the value empty and blocks the same way.
start_state_definition="$(jq -c --arg s "$start_state" '.states[$s] // null' "$def" 2>/dev/null)"
[ -n "$start_state_definition" ] && [ "$start_state_definition" != "null" ] \
  || blocker "packaged workflow definition declares no state '$start_state' for start_state; no run dir created"

# ── Atomic run-dir reservation (closes the F2 reservation TOCTOU) ──────────────
# The earlier `[ -e "$ledger_path" ]` check is a friendly EARLY blocker for the common
# non-concurrent case, but it is a check-then-create TOCTOU: two same-checkout initializers
# that derive the SAME run_id (identical suggested_run_id, or the same
# <utc-timestamp>-<workflow-id> within one second) can both pass that existence check and
# both proceed, and the second `mv -f` would silently replace the first's ledger. The bare
# `mkdir "$run_dir"` WITHOUT -p below is the ATOMIC CLAIM: mkdir fails if the leaf already
# exists, so the loser of a concurrent race fails closed here and the winner's ledger is
# never overwritten. Parents are created with -p first (a shared ancestor is fine); only the
# <run_id> leaf is claimed atomically. Operating on the canonical $canon_repo_root-derived
# $run_dir keeps the claim on the verified-contained path. OWNERSHIP + ROLLBACK: the invocation
# whose bare `mkdir "$run_dir"` SUCCEEDS exclusively owns the leaf; it records CLAIMED_DIR and
# the EXIT trap removes that invocation-owned dir on ANY pre-ledger failure (evidence mkdir /
# mktemp / jq serialize / mv) so a transient filesystem failure does NOT permanently brick
# retry — critical for brood children, whose suggested_run_id is STABLE, so an orphan would
# reject every same-id retry at this `mkdir`. A concurrent LOSER's `mkdir "$run_dir"` FAILS, so
# it blocks BEFORE setting CLAIMED_DIR and the trap never touches the winner's dir (the
# exclusive-ownership property: cleanup targets only the path THIS invocation created).
mkdir -p "$canon_repo_root/.hivemind/runs" \
  || blocker "failed to create .hivemind/runs under $canon_repo_root"
mkdir "$run_dir" \
  || blocker "run dir already claimed (concurrent init or pre-existing run): $run_dir; refusing to overwrite"
# Claim succeeded: this invocation now exclusively owns $run_dir. Arm rollback so any pre-ledger
# failure below removes it (see the EXIT trap). Cleared only after the final mv -f durably
# installs the ledger.
CLAIMED_DIR="$run_dir"
mkdir -p "$run_dir/evidence" \
  || blocker "failed to create evidence dir under $run_dir"

# ── Parent block (assembled inside the write program) ─────────────────────────
# The parent object is built inside jq: the checked tokens kind / brood_id / strain_id from
# named --arg bindings, the untrusted run_id / manifest text from the inputs file itself, so
# untrusted parent text never enters the jq program SOURCE. An absent or "" field is null.
now_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── Atomic write: temp file in the run dir, then mv into place ─────────────────
# Temp file lives in the same directory as the target so the rename is on the same
# filesystem (atomic). mktemp template keeps it adjacent to state.json.
tmp_ledger="$(mktemp "$run_dir/.state.json.XXXXXX")" \
  || blocker "failed to create temp ledger file under $run_dir"

# The untrusted text fields (user_request, normalized, parent.run_id, parent.manifest,
# plan_path) and the plan_steps array reach the ledger from the inputs file itself
# (--slurpfile, the contract-checked single object), never through a shell variable, so no
# byte is lost or reshaped on the way. Every other field is a checked token or a value this
# script derived, bound with --arg / --argjson.
jq -n \
  --slurpfile inputs "$INPUTS_FILE" \
  --argjson schema_version 1 \
  --arg run_id "$run_id" \
  --arg workflow "$workflow" \
  --argjson workflow_version "$workflow_version" \
  --arg created_at "$now_ts" \
  --arg updated_at "$now_ts" \
  --arg parent_kind "$parent_kind" \
  --arg parent_brood_id "$parent_brood_id" \
  --arg parent_strain_id "$parent_strain_id" \
  --arg start_state "$start_state" \
  '
  def nz(s): if s == "" then null else s end;
  $inputs[0] as $in
  | {
    schema_version: $schema_version,
    run: {
      id: $run_id,
      workflow: $workflow,
      workflow_version: $workflow_version,
      status: "running",
      mode: "deterministic",
      created_at: $created_at,
      updated_at: $updated_at
    },
    parent: {
      kind: $parent_kind,
      run_id: nz($in.parent.run_id // ""),
      brood_id: nz($parent_brood_id),
      strain_id: nz($parent_strain_id),
      manifest: nz($in.parent.manifest // "")
    },
    request: {
      raw: $in.user_request,
      normalized: $in.normalized
    },
    state: {
      current: $start_state,
      previous: null,
      status: "running"
    },
    facts: {
      branch: null,
      base: null,
      pr: null
    },
    plan: {
      path: nz($in.plan_path // ""),
      current_step: null,
      steps: ($in.plan_steps // [])
    },
    artifacts: {},
    events: [],
    blockers: []
  }
  ' > "$tmp_ledger" \
  || { rm -f "$tmp_ledger"; blocker "failed to serialize the run ledger with jq"; }

mv -f "$tmp_ledger" "$ledger_path" \
  || { rm -f "$tmp_ledger"; blocker "failed to atomically install the run ledger at $ledger_path"; }

# Ledger durably written: disarm rollback so the EXIT trap does NOT delete the now-complete run
# dir on normal exit 0. Past this point the run dir is committed state, not an unfinished claim.
CLAIMED_DIR=""

# ── Success routing ───────────────────────────────────────────────────────────
printf 'run_id: %s\n' "$run_id"
printf 'ledger: %s\n' "$ledger_path"
printf 'current_state: %s\n' "$start_state"
printf 'state_definition: %s\n' "$start_state_definition"
exit 0
