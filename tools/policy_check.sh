#!/usr/bin/env bash
#
# Policy linter for the hivemind plugin.
#
# Runs structural and content checks against plugin/ files, plus safety
# regression fixtures (tests/policy/) and compatibility fixtures (tests/plugin/).
# Advisory mode (default): reports findings, exits 0 unless the harness itself fails.
# Strict mode (--strict): exits non-zero when findings exist that are not in the allowlist.
#
# Usage:
#   ./tools/policy_check.sh
#   ./tools/policy_check.sh --strict

set -euo pipefail

# ── Argument parsing ────────────────────────────────────────────────────────

STRICT=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict|-Strict)
            STRICT=true
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
PLUGIN_ROOT="$REPO_ROOT/plugin"
ALLOWLIST_PATH="$REPO_ROOT/tests/policy/policy-lint-allowlist.json"

resolve_repo_path() {
    echo "$REPO_ROOT/$1"
}

# ── Helpers ─────────────────────────────────────────────────────────────────

# INVARIANT (#305): every unit-separator-delimited jq stream in this script is
# MATERIALISED into a plain variable before its read loop -- never piped in via
# process substitution. A failing producer inside `< <(...)` is invisible to the
# reading loop's exit status, so a malformed input silently yields zero
# iterations and leaves the assertion inert while its PASS banner still prints.
# A plain assignment makes that same failure terminal under `set -e`, matching
# the pre-#305 indexed-jq behaviour.
#
# `nosep` is the companion guard prepended to every such jq program: it refuses
# to emit any field containing the separator, so allowlist or fixture content
# can never shift a record's field boundaries (a shifted field could redirect a
# presence check into an absence check). Refusal is an error, and the
# materialisation above makes that error terminal.
JQ_NOSEP_DEF='def nosep: tostring | if index("\u001f") then error("field contains the U+001F record separator") else . end; '

# JQ_WSNORM_DEF (#350): jq-side mirror of normalize_ws for fixture PATTERNS,
# applied during the extraction pass so the hot fixture loop spawns no
# per-pattern process. The class is exactly tr's C-locale [:space:] byte set
# (space, tab, LF, VT, FF, CR; the trailing hex escape is the vertical tab) --
# deliberately NOT Oniguruma [[:space:]], which also matches unicode spaces
# (e.g. U+00A0) that normalize_ws leaves untouched. The normalize-ws canary
# fixture's newline-embedded patterns keep this mirror honest: divergence on
# newline handling turns the suite red.
JQ_WSNORM_DEF='def wsnorm: gsub("[ \t\r\n\f\\x0B]+"; " "); '

load_allowlist() {
    if [[ -f "$ALLOWLIST_PATH" ]]; then
        cat "$ALLOWLIST_PATH"
    else
        echo "[]"
    fi
}

ALLOWLIST_JSON="$(load_allowlist)"

# Allowlist preload: one jq pass at startup into parallel bash arrays so the
# per-finding path (test_allowlisted) spawns zero processes.
declare -a ALLOWLIST_RULES=()
declare -a ALLOWLIST_PATHS=()
# INVARIANT: ALLOWLIST_LINESPECS entries are "W" (no "line" key = wildcard) or
# "L<value>" (the entry's line rendered exactly as jq -r renders the scalar).
declare -a ALLOWLIST_LINESPECS=()

preload_allowlist() {
    local tuples
    tuples="$(jq -j "$JQ_NOSEP_DEF"'.[]
        | (.rule|nosep), "\u001f",
          (.path|nosep), "\u001f",
          ((if has("line") then "L\(.line)" else "W" end)|nosep), "\u001f"' \
        <<< "$ALLOWLIST_JSON")"
    if [[ -z "$tuples" ]]; then
        return 0
    fi
    local rule_f path_f spec_f
    while IFS= read -r -d $'\x1f' rule_f \
       && IFS= read -r -d $'\x1f' path_f \
       && IFS= read -r -d $'\x1f' spec_f; do
        ALLOWLIST_RULES+=("$rule_f")
        ALLOWLIST_PATHS+=("$path_f")
        ALLOWLIST_LINESPECS+=("$spec_f")
    done <<< "$tuples"
}
preload_allowlist

# Findings storage: parallel arrays
declare -a FINDING_RULES=()
declare -a FINDING_PATHS=()
declare -a FINDING_LINES=()
declare -a FINDING_DESCS=()
declare -a FINDING_ALLOWED=()

test_allowlisted() {
    local rule="$1"
    local fpath="$2"
    local line="$3"

    local count=${#ALLOWLIST_RULES[@]}
    local i=0
    while [[ $i -lt $count ]]; do
        if [[ "${ALLOWLIST_RULES[$i]}" != "$rule" ]]; then
            i=$((i + 1))
            continue
        fi
        if [[ "${ALLOWLIST_PATHS[$i]}" != "$fpath" ]]; then
            i=$((i + 1))
            continue
        fi
        local line_spec="${ALLOWLIST_LINESPECS[$i]}"
        if [[ "$line_spec" != "W" ]]; then
            local entry_line="${line_spec#L}"
            if [[ "$entry_line" != "0" && "$entry_line" != "$line" ]]; then
                i=$((i + 1))
                continue
            fi
        fi
        echo "true"
        return
    done
    echo "false"
}

add_finding() {
    local rule="$1"
    local filepath="$2"
    local line="$3"
    local description="$4"

    local rel_path="$filepath"
    if [[ "$filepath" == "$REPO_ROOT"* ]]; then
        rel_path="${filepath#"$REPO_ROOT"/}"
    fi
    # Normalize backslashes to forward slashes
    rel_path="${rel_path//\\//}"

    local is_allowlisted
    is_allowlisted="$(test_allowlisted "$rule" "$rel_path" "$line")"

    FINDING_RULES+=("$rule")
    FINDING_PATHS+=("$rel_path")
    FINDING_LINES+=("$line")
    FINDING_DESCS+=("$description")
    FINDING_ALLOWED+=("$is_allowlisted")

    local line_label=""
    if [[ "$line" -gt 0 ]]; then
        line_label=":$line"
    fi
    local prefix="[FIND]"
    if [[ "$is_allowlisted" == "true" ]]; then
        prefix="[ALLOW]"
    fi
    echo "$prefix [$rule] ${rel_path}${line_label} -- $description"
}

get_frontmatter() {
    local filepath="$1"
    local in_frontmatter=false
    local frontmatter_started=false
    local result=""
    while IFS= read -r textline || [[ -n "$textline" ]]; do
        local trimmed
        trimmed="${textline#"${textline%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        if [[ "$trimmed" == "---" ]]; then
            if [[ "$frontmatter_started" == false ]]; then
                frontmatter_started=true
                in_frontmatter=true
                continue
            else
                break
            fi
        fi
        if [[ "$in_frontmatter" == true ]]; then
            if [[ -n "$result" ]]; then
                result="$result"$'\n'"$textline"
            else
                result="$textline"
            fi
        fi
    done < "$filepath"
    echo "$result"
}

# normalize_ws TEXT
# INVARIANT: fixture pattern matching is whitespace-normalized on both sides
# (#337) — every [[:space:]]+ run collapses to a single space so that line
# wrapping and indentation (incidental layout) cannot mask a pinned word
# sequence. No other byte is altered.
normalize_ws() {
    printf '%s' "$1" | tr -s '[:space:]' ' '
}

# ── Whitespace-normalization cache (#350) ───────────────────────────────────
# Fixture matching normalizes the SAME file for many assertions (105 consumer
# assertions over ~30 files spawned ~270 tr subprocesses and re-read each file
# per assertion). Cache the normalized text once per (scope, path). The key
# MUST carry the scope: WHOLE-file and FRONTMATTER-only normalization of the
# SAME path are different texts, and a path-only key would corrupt the
# frontmatter-scoped `absent` checks with whole-file content.
declare -A NORM_WS_CACHE=()

# norm_ws_cached SCOPE PATH
# Sets NORM_WS_RESULT to the whitespace-normalized text of PATH for SCOPE
# (whole | frontmatter), computing via normalize_ws once per (scope, path) and
# serving every later request from the cache with zero spawns. Result is
# returned in a global rather than by command substitution so cache hits fork
# nothing.
NORM_WS_RESULT=""
norm_ws_cached() {
    local scope="$1" path="$2"
    local key="${scope}:${path}"
    if [[ -z "${NORM_WS_CACHE[$key]+x}" ]]; then
        local raw
        if [[ "$scope" == "frontmatter" ]]; then
            raw="$(get_frontmatter "$path")"
        else
            raw="$(<"$path")"
        fi
        NORM_WS_CACHE[$key]="$(normalize_ws "$raw")"
    fi
    NORM_WS_RESULT="${NORM_WS_CACHE[$key]}"
}

# frontmatter_contains_ws_norm FILE PATTERN_NORM
# Exit 0 when FILE's YAML frontmatter, whitespace-normalized, contains the
# already-normalized PATTERN_NORM. This is the SINGLE containment predicate for
# frontmatter-scoped `absent` fixture checks AND for the SAFETY-CANARY
# self-test, so removing the normalization here turns that self-test red
# instead of silently weakening `absent` matching. (A standing green fixture
# cannot witness this normalization: for absent semantics a raw-substring hit
# always survives normalization, so its removal can only flip a red detection
# to green — hence the self-test asserts the red direction.)
frontmatter_contains_ws_norm() {
    local file="$1" pattern_norm="$2"
    norm_ws_cached frontmatter "$file"
    [[ "$NORM_WS_RESULT" == *"$pattern_norm"* ]]
}

# file_candidates MODE PATTERN FILE
# Per-FILE candidate prefilter (#305): ONE grep spawn per file emits
# "lineno:body" lines for the hot per-line loops, replacing a spawn per line.
# MODE is the grep matcher flag (P, E, or F); the PATTERN is unchanged from
# the per-line logic it feeds. grep exit 1 (zero candidates) is normal and
# yields empty output; any other grep exit propagates so a genuine scan error
# fails the run instead of reading as "clean".
file_candidates() {
    local mode="$1"
    local pattern="$2"
    local file="$3"
    local out="" rc=0
    out="$(grep "-n${mode}" -- "$pattern" "$file")" || rc=$?
    if [[ "$rc" -gt 1 ]]; then
        return "$rc"
    fi
    printf '%s' "$out"
}

# ── Checked discovery ───────────────────────────────────────────────────────
# The single file-discovery engine for this script. Contract:
#
#   Policy: every discovery find runs with DISCOVERY_FIND_BASE (-L), so
#   symlinks are FOLLOWED script-wide -- a symlinked file or directory is
#   scanned as its target. Failures are loud, never silently skipped:
#     - a symlink loop makes find print an error and exit non-zero (it keeps
#       traversing), so discover_paths returns that status and
#       discover_checked_paths reports it through flag_discovery_failure;
#     - a dangling symlink is printed by find -L with exit 0, so it is the
#       `files` gate of discovery_gate_status that rejects it (missing), and
#       discover_checked_paths reports it through flag_discovery_gate.
#   Call sites: every scanning check discovers through discover_checked_paths,
#   the one composition of the pieces below. discover_paths is called directly
#   only by canaries, which assert its status without emitting a real finding.
#   discovery_gate_status is called directly by canaries and, outside a
#   discovery, to classify a ROOT before discovering under it -- CHECK 14's
#   OPTIONAL skill scripts directory, and the REQUIRED SAFETY, COMPAT and
#   WORKFLOW-FIXTURES fixture roots -- whose rejection is still reported
#   through flag_discovery_gate. A root is never pre-guarded by a bare `-d`
#   test: that skips the discovery entirely, so a missing or non-directory
#   root would become a silent green run over an empty set instead of a
#   finding.
#   Precondition: every ROOT must exist. This is the CALLER's job; there is
#   no swallow mode and find's stderr is never suppressed, so a missing root
#   fails discovery with find's non-zero status and must be reported.
#   Findings: both reporting wrappers emit through add_finding, so --strict
#   and the allowlist apply. Neither they nor discover_checked_paths set any
#   per-check found/pass flag; discover_checked_paths returns non-zero when it
#   emitted a finding, and the caller owns its flag.
#   Residuals: symlink-loop reporting is not witnessed by a committed fixture;
#   a symlinked directory that points back inside a scanned root materialises
#   the same file under two paths (it is scanned twice, never skipped).

DISCOVERY_FIND_BASE=(-L)
DISCOVERY_FIND_STATUS_TAG='__DISCOVERY_FIND_STATUS='
DISCOVERY_RC_TRUNCATED=20
DISCOVERY_RC_USAGE=21
DISCOVERY_GATE_RC_MISSING=22
DISCOVERY_GATE_RC_NOT_REGULAR=23
DISCOVERY_GATE_RC_UNREADABLE=24
DISCOVERY_GATE_RC_NOT_DIR=25
DISCOVERY_GATE_RC_UNKNOWN_GATE=26

# discover_paths DEST_ARRAY ROOT... -- FIND_ARGS...
# Materialises the paths
#   find "${DISCOVERY_FIND_BASE[@]}" ROOT... FIND_ARGS... -print0
# emits into the caller-named array DEST_ARRAY (replacing its contents), and
# returns find's exit status, DISCOVERY_RC_TRUNCATED when the stream does not
# end in exactly one status record, or DISCOVERY_RC_USAGE (with a stderr
# message) when no ROOT or no `--` separator is given. Paths found before a
# failure are still materialised so they are scanned; the non-zero status is
# what keeps the caller from reading the list as clean.
#
# DEST_ARRAY is bound by nameref, so nested discovery (a discovery inside
# another discovery's loop) must use distinct destination names; it must also
# not be one of this function's own `discovery_*` locals.
#
# INVARIANT: a failing producer inside `< <(...)` is invisible to the reading
# loop (see the materialisation invariant above), so the producer appends its
# own status as a trailing NUL-delimited sentinel record. The
# `|| discovery_find_status=$?` is load-bearing: errexit is inherited by the
# process substitution, so a bare `find ...; printf ... "$?"` dies before the
# sentinel is written whenever find fails.
#
# INVARIANT: every emitted path begins with one of the ROOTs, so a path record
# can only collide with DISCOVERY_FIND_STATUS_TAG if a ROOT itself begins with
# it; callers pass absolute roots.
discover_paths() {
    local -n discovery_dest_ref="$1"
    shift
    local -a discovery_roots=()
    local discovery_saw_separator=false
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == '--' ]]; then
            discovery_saw_separator=true
            shift
            break
        fi
        discovery_roots+=("$1")
        shift
    done
    if [[ "$discovery_saw_separator" != true || "${#discovery_roots[@]}" -eq 0 ]]; then
        echo "discover_paths: usage: discover_paths DEST_ARRAY ROOT... -- FIND_ARGS..." >&2
        return "$DISCOVERY_RC_USAGE"
    fi
    local discovery_record discovery_status_record=''
    local discovery_sentinel_total=0 discovery_last_was_sentinel=false
    discovery_dest_ref=()
    while IFS= read -r -d '' discovery_record; do
        if [[ "$discovery_record" == "$DISCOVERY_FIND_STATUS_TAG"* ]]; then
            discovery_sentinel_total=$((discovery_sentinel_total + 1))
            discovery_status_record="$discovery_record"
            discovery_last_was_sentinel=true
        else
            discovery_dest_ref+=("$discovery_record")
            discovery_last_was_sentinel=false
        fi
    done < <(discovery_find_status=0; find "${DISCOVERY_FIND_BASE[@]}" "${discovery_roots[@]}" "$@" -print0 || discovery_find_status=$?; printf '%s%d\0' "$DISCOVERY_FIND_STATUS_TAG" "$discovery_find_status")
    if [[ "$discovery_sentinel_total" -ne 1 || "$discovery_last_was_sentinel" != true ]]; then
        return "$DISCOVERY_RC_TRUNCATED"
    fi
    return "${discovery_status_record#"$DISCOVERY_FIND_STATUS_TAG"}"
}

# discovery_gate_status PATH GATE
# Status-bearing classifier for one discovered PATH (symlinks resolved, per
# the -L policy). GATE is one of:
#   files -- 0 only for a readable regular file; otherwise
#            DISCOVERY_GATE_RC_MISSING (missing or dangling symlink),
#            DISCOVERY_GATE_RC_NOT_REGULAR, or DISCOVERY_GATE_RC_UNREADABLE;
#   dirs  -- 0 for a directory (a symlinked directory passes); otherwise
#            DISCOVERY_GATE_RC_MISSING or DISCOVERY_GATE_RC_NOT_DIR;
#   raw   -- always 0; the caller does its own read gating.
# An unknown GATE returns DISCOVERY_GATE_RC_UNKNOWN_GATE with a stderr message.
discovery_gate_status() {
    local candidate_path="$1" gate_name="$2"
    case "$gate_name" in
        files)
            if [[ ! -e "$candidate_path" ]]; then
                return "$DISCOVERY_GATE_RC_MISSING"
            fi
            if [[ ! -f "$candidate_path" ]]; then
                return "$DISCOVERY_GATE_RC_NOT_REGULAR"
            fi
            if [[ ! -r "$candidate_path" ]]; then
                return "$DISCOVERY_GATE_RC_UNREADABLE"
            fi
            ;;
        dirs)
            if [[ ! -e "$candidate_path" ]]; then
                return "$DISCOVERY_GATE_RC_MISSING"
            fi
            if [[ ! -d "$candidate_path" ]]; then
                return "$DISCOVERY_GATE_RC_NOT_DIR"
            fi
            ;;
        raw)
            ;;
        *)
            echo "discovery_gate_status: unknown gate '${gate_name}' (expected files, dirs, or raw)" >&2
            return "$DISCOVERY_GATE_RC_UNKNOWN_GATE"
            ;;
    esac
    return 0
}

# flag_discovery_failure RULE ROOT LABEL STATUS
# Thin reporting wrapper: records the RULE finding for a discover_paths call
# (described by LABEL, anchored at ROOT) that returned non-zero STATUS. A
# partial path list is never a clean one.
flag_discovery_failure() {
    local rule_name="$1" discovery_root="$2" discovery_label="$3" discovery_rc="$4" failure_reason
    case "$discovery_rc" in
        "$DISCOVERY_RC_TRUNCATED") failure_reason='its path stream ended without exactly one trailing find-status record (truncated)' ;;
        "$DISCOVERY_RC_USAGE") failure_reason='discover_paths was called without a ROOT or without the -- separator' ;;
        *) failure_reason="find exited ${discovery_rc} (a missing root, an unreadable directory, or a symlink loop)" ;;
    esac
    add_finding "$rule_name" "$discovery_root" 0 \
        "Discovery of ${discovery_label} failed: ${failure_reason}, so paths in it may never have been checked -- fix the tree; a failed discovery is NOT clean"
}

# flag_discovery_gate RULE PATH RC
# Thin reporting wrapper: records the RULE finding for a discovered PATH that
# discovery_gate_status rejected with non-zero RC.
flag_discovery_gate() {
    local rule_name="$1" candidate_path="$2" gate_rc="$3" rejection_reason
    case "$gate_rc" in
        "$DISCOVERY_GATE_RC_MISSING") rejection_reason='is missing or is a dangling symlink' ;;
        "$DISCOVERY_GATE_RC_NOT_REGULAR") rejection_reason='is not a regular file' ;;
        "$DISCOVERY_GATE_RC_UNREADABLE") rejection_reason='is not readable' ;;
        "$DISCOVERY_GATE_RC_NOT_DIR") rejection_reason='is not a directory' ;;
        *) rejection_reason="was rejected by the discovery gate with status ${gate_rc}" ;;
    esac
    add_finding "$rule_name" "$candidate_path" 0 \
        "this discovered path ${rejection_reason}, so it was never checked -- fix or remove it; an unchecked path is NOT clean"
}

# discover_checked_paths RULE DEST_ARRAY GATE LABEL ROOT... -- FIND_ARGS...
# The checked discovery every scanning check calls. Runs
#   discover_paths ROOT... -- FIND_ARGS...
# and reports a non-zero status through flag_discovery_failure (anchored at
# the first ROOT, described by LABEL); then gates each materialised path with
# discovery_gate_status PATH GATE and reports each rejection through
# flag_discovery_gate. DEST_ARRAY is replaced with ONLY the accepted paths, in
# find order. Returns 1 when it emitted any RULE finding, else 0, so the
# caller sets its own flag: `discover_checked_paths ... || checkN_found=true`.
#
# INVARIANT: DEST_ARRAY is bound by nameref, so it must not be one of this
# function's own `checked_discovery_*` locals (the nameref would bind the
# local, not the caller's array) and, like every discover_paths DEST, must not
# be `discovery_*`-prefixed. Nested use -- a discovery inside another
# discovery's loop -- needs distinct DEST names.
discover_checked_paths() {
    local checked_discovery_rule="$1" checked_discovery_gate="$3" checked_discovery_label="$4"
    local -n checked_discovery_dest_ref="$2"
    shift 4
    local -a checked_discovery_materialised=()
    local checked_discovery_rc=0 checked_discovery_flagged=false
    local checked_discovery_path checked_discovery_gate_rc
    discover_paths checked_discovery_materialised "$@" || checked_discovery_rc=$?
    if [[ "$checked_discovery_rc" -ne 0 ]]; then
        checked_discovery_flagged=true
        flag_discovery_failure "$checked_discovery_rule" "$1" "$checked_discovery_label" "$checked_discovery_rc"
    fi
    checked_discovery_dest_ref=()
    for checked_discovery_path in "${checked_discovery_materialised[@]}"; do
        checked_discovery_gate_rc=0
        discovery_gate_status "$checked_discovery_path" "$checked_discovery_gate" || checked_discovery_gate_rc=$?
        if [[ "$checked_discovery_gate_rc" -ne 0 ]]; then
            checked_discovery_flagged=true
            flag_discovery_gate "$checked_discovery_rule" "$checked_discovery_path" "$checked_discovery_gate_rc"
            continue
        fi
        checked_discovery_dest_ref+=("$checked_discovery_path")
    done
    if [[ "$checked_discovery_flagged" == true ]]; then
        return 1
    fi
    return 0
}

# ── Timing instrumentation ──────────────────────────────────────────────────
# Permanent per-check profiling (#305, precedent #304). Emits one
# "[TIME] <label> <elapsed>s" line after each check block and a per-check
# timing table immediately before the Summary block.

declare -a TIMING_LABELS=()
declare -a TIMING_SECS=()

get_epoch_us() {
    local raw="${EPOCHREALTIME:-}"
    if [[ -n "$raw" ]]; then
        echo "${raw//[.,]/}"
    else
        echo "$((SECONDS * 1000000))"
    fi
}

format_us() {
    local us="$1"
    printf '%d.%03d' "$((us / 1000000))" "$(((us % 1000000) / 1000))"
}

TIMING_MARK_US="$(get_epoch_us)"
TIMING_RUN_START_US="$TIMING_MARK_US"

mark_time() {
    local label="$1"
    local now_us
    now_us="$(get_epoch_us)"
    local elapsed
    elapsed="$(format_us "$((now_us - TIMING_MARK_US))")"
    TIMING_MARK_US="$now_us"
    TIMING_LABELS+=("$label")
    TIMING_SECS+=("$elapsed")
    echo "[TIME] $label ${elapsed}s"
}

print_timing_table() {
    echo ''
    echo '=== TIMING: Per-check wall time ==='
    local i
    for ((i = 0; i < ${#TIMING_LABELS[@]}; i++)); do
        printf '%-20s %10ss\n' "${TIMING_LABELS[$i]}" "${TIMING_SECS[$i]}"
    done
    local total
    total="$(format_us "$(($(get_epoch_us) - TIMING_RUN_START_US))")"
    printf '%-20s %10ss\n' 'TOTAL' "$total"
}

# ── State ───────────────────────────────────────────────────────────────────

CHECKS_PASSED=0
CHECKS_FAILED=0

# ── DISCOVERY CANARY ────────────────────────────────────────────────────────
# Witnesses the checked-discovery helpers (see the Checked discovery section).
# It sits directly after State, the first point where its CHECKS_PASSED /
# CHECKS_FAILED accounting survives the counter initialisation. Assertions:
#   * precondition: the committed fixture symlinks ARE symlinks in this checkout
#     (a core.symlinks=false checkout turns them into plain files) -- a loud
#     finding, never a self-skip;
#   * args pin: DISCOVERY_FIND_BASE is exactly the single element `-L`;
#   * positive: discover_paths over the canary tree materialises exactly
#     real/inner.md and link-dir/inner.md, both accepted by the `files` gate --
#     proving -L descends a symlinked directory;
#   * negative control: one raw `find -P` over the same tree materialises only
#     real/inner.md, so the positive probe discriminates -L from -P;
#   * gates in both directions, against the status-bearing classifier
#     discovery_gate_status (never the reporting wrappers, so no probe emits a
#     real finding), each probe path chosen so no earlier gate arm shadows the
#     arm under test; a regular fixture accepted by `files` is the positive
#     control, so the failure arms cannot all pass by the gate failing
#     unconditionally;
#   * status propagation: discover_paths over a nonexistent root returns
#     find's own non-zero status (not TRUNCATED or USAGE);
#   * composition: discover_checked_paths over the whole canary root under the
#     `files` gate keeps exactly real/inner.md and link-dir/inner.md, returns
#     non-zero, and emits exactly one finding, naming broken/dangling.md. It
#     runs inside a command substitution so that finding is captured as text
#     and its FINDING_* append dies with the subshell -- no real finding.
# The fixtures are committed, so no probe creates a filesystem object at run
# time. stderr is discarded only for the nonexistent-root probe, whose find
# error is the expected outcome.
# Residuals: the symlink-loop case is not witnessed by a committed fixture --
# find reports a loop through the same non-zero exit status the
# nonexistent-root probe witnesses; a symlinked directory that points back
# inside a scanned root materialises the same file under two paths (scanned
# twice, never skipped), which this canary does not assert.

echo ''
echo '=== DISCOVERY: Checked-discovery canary ==='

DISCOVERY_CANARY_REL='tests/policy/fixtures/discovery-canary'
dcanary_root="$REPO_ROOT/$DISCOVERY_CANARY_REL"
dcanary_tree="$dcanary_root/tree"
dcanary_real_dir="$dcanary_tree/real"
dcanary_link_dir="$dcanary_tree/link-dir"
dcanary_real_file="$dcanary_real_dir/inner.md"
dcanary_linked_file="$dcanary_link_dir/inner.md"
dcanary_dangling_file="$dcanary_root/broken/dangling.md"
dcanary_missing_root="$dcanary_root/__discovery_nonexistent__"
dcanary_found=false

# flag_discovery_canary DESCRIPTION
# Records a DISCOVERY finding for a canary assertion that came back wrong.
flag_discovery_canary() {
    dcanary_found=true
    add_finding 'DISCOVERY' 'tools/policy_check.sh' 0 \
        "discovery canary: $1 -- the checked-discovery engine no longer holds its follow-symlinks, fail-loud contract, so a symlinked, dangling, or undiscoverable path could be read as clean"
}

# expect_discovery_gate PATH_LABEL PATH GATE EXPECTED_RC
# Asserts discovery_gate_status PATH GATE returns exactly EXPECTED_RC.
expect_discovery_gate() {
    local path_label="$1" candidate_path="$2" gate_name="$3" expected_rc="$4" gate_rc=0
    discovery_gate_status "$candidate_path" "$gate_name" || gate_rc=$?
    if [[ "$gate_rc" -ne "$expected_rc" ]]; then
        flag_discovery_canary "discovery_gate_status on ${path_label} under the '${gate_name}' gate returned ${gate_rc}, expected ${expected_rc}"
    fi
}

if [[ ! -L "$dcanary_link_dir" || ! -L "$dcanary_dangling_file" ]]; then
    flag_discovery_canary "precondition: ${DISCOVERY_CANARY_REL}/tree/link-dir and ${DISCOVERY_CANARY_REL}/broken/dangling.md must both be symlinks in this checkout, but at least one is not -- the likely cause is core.symlinks=false materialising them as plain files; set core.symlinks=true and re-checkout, never skip this canary"
fi

if [[ "${#DISCOVERY_FIND_BASE[@]}" -ne 1 || "${DISCOVERY_FIND_BASE[0]}" != '-L' ]]; then
    flag_discovery_canary "DISCOVERY_FIND_BASE is '${DISCOVERY_FIND_BASE[*]}' (${#DISCOVERY_FIND_BASE[@]} element(s)) but must be exactly the single element '-L' -- discovery must follow symlinks script-wide"
fi

declare -a dcanary_paths=()
dcanary_rc=0
discover_paths dcanary_paths "$dcanary_tree" -- -name '*.md' || dcanary_rc=$?
dcanary_accepted_total=0
dcanary_saw_real=false
dcanary_saw_linked=false
for dcanary_path in "${dcanary_paths[@]}"; do
    dcanary_gate_rc=0
    discovery_gate_status "$dcanary_path" files || dcanary_gate_rc=$?
    if [[ "$dcanary_gate_rc" -eq 0 ]]; then
        dcanary_accepted_total=$((dcanary_accepted_total + 1))
    fi
    if [[ "$dcanary_path" == "$dcanary_real_file" ]]; then
        dcanary_saw_real=true
    elif [[ "$dcanary_path" == "$dcanary_linked_file" ]]; then
        dcanary_saw_linked=true
    fi
done
if [[ "$dcanary_rc" -ne 0 || "${#dcanary_paths[@]}" -ne 2 || "$dcanary_accepted_total" -ne 2 \
   || "$dcanary_saw_real" != true || "$dcanary_saw_linked" != true ]]; then
    flag_discovery_canary "discover_paths over ${DISCOVERY_CANARY_REL}/tree returned status ${dcanary_rc} and materialised ${#dcanary_paths[@]} path(s) [${dcanary_paths[*]}], ${dcanary_accepted_total} accepted by the 'files' gate; expected status 0 and exactly real/inner.md and link-dir/inner.md, both accepted -- -L no longer descends a symlinked directory"
fi

# INTENTIONAL NON-HELPER FIND: the only raw find in this canary, run with an
# explicit -P as the negative control for the -L probe above; it is not a
# discovery call site and must never be migrated to discover_paths.
dcanary_raw_rc=0
dcanary_raw_listing="$(find -P "$dcanary_tree" -name '*.md' -print)" || dcanary_raw_rc=$?
if [[ "$dcanary_raw_rc" -ne 0 || "$dcanary_raw_listing" != "$dcanary_real_file" ]]; then
    dcanary_raw_flat="${dcanary_raw_listing//$'\n'/ | }"
    flag_discovery_canary "negative control: find -P over ${DISCOVERY_CANARY_REL}/tree returned status ${dcanary_raw_rc} and [${dcanary_raw_flat}], expected status 0 and exactly real/inner.md -- the positive probe no longer discriminates -L from -P"
fi

expect_discovery_gate 'broken/dangling.md' "$dcanary_dangling_file" files "$DISCOVERY_GATE_RC_MISSING"
expect_discovery_gate 'broken/dangling.md' "$dcanary_dangling_file" raw 0
expect_discovery_gate 'tree/real (a directory)' "$dcanary_real_dir" files "$DISCOVERY_GATE_RC_NOT_REGULAR"
expect_discovery_gate 'tree/link-dir (a symlinked directory)' "$dcanary_link_dir" dirs 0
expect_discovery_gate 'tree/real/inner.md (a regular file)' "$dcanary_real_file" dirs "$DISCOVERY_GATE_RC_NOT_DIR"
expect_discovery_gate 'tree/real/inner.md (positive control)' "$dcanary_real_file" files 0

dcanary_missing_rc=0
discover_paths dcanary_paths "$dcanary_missing_root" -- -name '*.md' 2>/dev/null || dcanary_missing_rc=$?
if [[ "$dcanary_missing_rc" -eq 0 || "$dcanary_missing_rc" -eq "$DISCOVERY_RC_TRUNCATED" \
   || "$dcanary_missing_rc" -eq "$DISCOVERY_RC_USAGE" ]]; then
    flag_discovery_canary "discover_paths over the nonexistent root ${DISCOVERY_CANARY_REL}/__discovery_nonexistent__ returned ${dcanary_missing_rc}, expected find's own non-zero status -- a failing find (a missing root or a symlink loop) no longer propagates, so it would read as a clean tree"
fi

# probe_checked_discovery_composition
# Prints discover_checked_paths' output over the canary root (its findings),
# then `rc=STATUS` and one `accepted=PATH` line per accepted path. Called only
# inside a command substitution, so the finding it emits stays in the subshell.
probe_checked_discovery_composition() {
    local -a dcanary_checked_paths=()
    local dcanary_checked_rc=0 dcanary_checked_path
    discover_checked_paths 'DISCOVERY' dcanary_checked_paths files 'discovery canary Markdown files' "$dcanary_root" -- -name '*.md' || dcanary_checked_rc=$?
    printf 'rc=%d\n' "$dcanary_checked_rc"
    for dcanary_checked_path in "${dcanary_checked_paths[@]}"; do
        printf 'accepted=%s\n' "$dcanary_checked_path"
    done
}

dcanary_composition_output="$(probe_checked_discovery_composition)"
dcanary_composition_rc=''
dcanary_composition_finding_total=0
dcanary_composition_saw_dangling=false
dcanary_composition_accepted_total=0
dcanary_composition_saw_real=false
dcanary_composition_saw_linked=false
while IFS= read -r dcanary_composition_line; do
    case "$dcanary_composition_line" in
        'rc='*)
            dcanary_composition_rc="${dcanary_composition_line#rc=}"
            ;;
        'accepted='*)
            dcanary_composition_accepted_total=$((dcanary_composition_accepted_total + 1))
            if [[ "${dcanary_composition_line#accepted=}" == "$dcanary_real_file" ]]; then
                dcanary_composition_saw_real=true
            elif [[ "${dcanary_composition_line#accepted=}" == "$dcanary_linked_file" ]]; then
                dcanary_composition_saw_linked=true
            fi
            ;;
        *'[DISCOVERY] '*)
            dcanary_composition_finding_total=$((dcanary_composition_finding_total + 1))
            if [[ "$dcanary_composition_line" == *"[DISCOVERY] ${DISCOVERY_CANARY_REL}/broken/dangling.md -- "* ]]; then
                dcanary_composition_saw_dangling=true
            fi
            ;;
    esac
done <<< "$dcanary_composition_output"
if [[ "$dcanary_composition_rc" != 1 || "$dcanary_composition_accepted_total" -ne 2 \
   || "$dcanary_composition_saw_real" != true || "$dcanary_composition_saw_linked" != true \
   || "$dcanary_composition_finding_total" -ne 1 || "$dcanary_composition_saw_dangling" != true ]]; then
    dcanary_composition_flat="${dcanary_composition_output//$'\n'/ | }"
    flag_discovery_canary "discover_checked_paths over ${DISCOVERY_CANARY_REL} under the 'files' gate produced [${dcanary_composition_flat}]; expected rc=1, exactly real/inner.md and link-dir/inner.md accepted, and exactly one finding naming broken/dangling.md -- the call-site composition no longer gates, reports, or returns its findings"
fi

if [[ "$dcanary_found" == false ]]; then
    echo '[PASS] DISCOVERY: checked discovery follows symlinked directories, gates dangling and wrong-type paths, and propagates find failures'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo '[FAIL] DISCOVERY: checked-discovery canary'
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'DISCOVERY'

# ── CHECK 1: Forbidden hedge ───────────────────────────────────────────────

echo ''
echo '=== CHECK 1: Forbidden hedge ==='

check1_found=false

declare -a check1_md_files=()
discover_checked_paths 'CHECK1' check1_md_files files 'plugin Markdown files' "$PLUGIN_ROOT" -- -name '*.md' || check1_found=true
for md_file in "${check1_md_files[@]}"; do
    # Candidate prefilter (#305): one grep per FILE on the BROADEST pattern.
    # Every finding-producing line must pass the ladder's \bambiguous\b gate
    # below, so non-matching lines can never add a finding; the
    # rule-definition skip only ever DROPS lines and needs no wider net.
    candidates="$(file_candidates P '\bambiguous\b' "$md_file")"
    [[ -z "$candidates" ]] && continue
    while IFS= read -r candidate; do
        line_num="${candidate%%:*}"
        textline="${candidate#*:}"

        # INVARIANT: The rule definition itself in governance docs is not a violation.
        if grep -qP 'Do not use the word.*ambiguous.*as a hedge' <<< "$textline"; then
            continue
        fi

        if ! grep -qP '\bambiguous\b' <<< "$textline"; then
            continue
        fi

        is_hedge=false

        # Pattern: "unsafe or ambiguous"
        if grep -qP '\bunsafe\s+or\s+ambiguous\b' <<< "$textline"; then
            is_hedge=true
        fi

        # Pattern: "is ambiguous"
        if grep -qP '\bis\s+ambiguous\b' <<< "$textline"; then
            is_hedge=true
        fi

        # Pattern: "or ambiguous" preceded by a stop/gate word
        if grep -qP '\bor\s+ambiguous\b' <<< "$textline"; then
            if ! grep -qP 'non-human\s+or\s+ambiguous' <<< "$textline"; then
                if ! grep -qP '/ambiguous' <<< "$textline"; then
                    if grep -qP '\b(continue|proceed|stop|when|if)\b.*\bor\s+ambiguous\b' <<< "$textline"; then
                        is_hedge=true
                    fi
                    if grep -qP '\bor\s+ambiguous\b.*\b(continue|proceed|stop|when|if)\b' <<< "$textline"; then
                        is_hedge=true
                    fi
                fi
            fi
        fi

        # Pattern: "proceed if ... ambiguous" or "continue ... ambiguous" as gate
        if grep -qP '\b(proceed|continue|stop)\b.*\bambiguous\b' <<< "$textline"; then
            if ! grep -qP '/ambiguous' <<< "$textline"; then
                if ! grep -qP 'non-human' <<< "$textline"; then
                    is_hedge=true
                fi
            fi
        fi

        if [[ "$is_hedge" == false ]]; then
            continue
        fi

        check1_found=true
        add_finding 'CHECK1' "$md_file" "$line_num" \
            "Forbidden hedge: 'ambiguous' used as gate-level uncertainty"
    done <<< "$candidates"
done

if [[ "$check1_found" == false ]]; then
    echo '[PASS] Check 1: No forbidden hedge violations found'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK1'

# ── CHECK 2: Required files exist ──────────────────────────────────────────

echo ''
echo '=== CHECK 2: Required files exist ==='

REQUIRED_FILES=(
    'plugin/governance/definitions.md'
    'plugin/governance/report-format.md'
    'plugin/governance/safety-rails.md'
    'plugin/governance/security-policy.md'
    'plugin/governance/versioning.md'
    'plugin/governance/workflow.md'
    'plugin/agents/cerebrate.md'
    'plugin/agents/overlord.md'
    'plugin/agents/drone.md'
    'plugin/agents/changeling.md'
)

check2_found=false
for rel_file in "${REQUIRED_FILES[@]}"; do
    abs_path="$(resolve_repo_path "$rel_file")"
    if [[ ! -e "$abs_path" ]]; then
        check2_found=true
        add_finding 'CHECK2' "$rel_file" 0 \
            "Required file missing: $rel_file"
    fi
done

if [[ "$check2_found" == false ]]; then
    echo '[PASS] Check 2: All required files exist'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK2'

# ── CHECK 3: Skill names exist ─────────────────────────────────────────────

echo ''
echo '=== CHECK 3: Skill names exist ==='

AGENT_NAMES=('cerebrate' 'overlord' 'drone' 'changeling' 'local-reviewer' 'github-reviewer')

check3_found=false

# Collect scan sources
declare -a SCAN_FILES=()
declare -a check3_agent_files=()
discover_checked_paths 'CHECK3' check3_agent_files files 'agent Markdown files' "$PLUGIN_ROOT/agents" -- -maxdepth 1 -name '*.md' || check3_found=true
declare -a check3_skill_files=()
discover_checked_paths 'CHECK3' check3_skill_files files 'skill SKILL.md files' "$PLUGIN_ROOT/skills" -- -name 'SKILL.md' || check3_found=true
declare -a check3_governance_files=()
discover_checked_paths 'CHECK3' check3_governance_files files 'governance Markdown files' "$PLUGIN_ROOT/governance" -- -maxdepth 1 -name '*.md' || check3_found=true
SCAN_FILES+=("${check3_agent_files[@]}" "${check3_skill_files[@]}" "${check3_governance_files[@]}")

# Extract all hivemind:* references.
# skill_refs: associative array mapping skill name -> space-separated source file paths
# agent_refs: associative array mapping agent name -> space-separated source file paths
declare -A SKILL_REF_SOURCES=()
declare -A AGENT_REF_SOURCES=()

is_agent_name() {
    local name="$1"
    for aname in "${AGENT_NAMES[@]}"; do
        if [[ "$aname" == "$name" ]]; then
            return 0
        fi
    done
    return 1
}

for scan_file in "${SCAN_FILES[@]}"; do
    scan_content="$(<"$scan_file")"
    while IFS= read -r ref_name; do
        [[ -z "$ref_name" ]] && continue

        if is_agent_name "$ref_name"; then
            if [[ -z "${AGENT_REF_SOURCES[$ref_name]:-}" ]]; then
                AGENT_REF_SOURCES[$ref_name]="$scan_file"
            elif [[ "${AGENT_REF_SOURCES[$ref_name]}" != *"$scan_file"* ]]; then
                AGENT_REF_SOURCES[$ref_name]="${AGENT_REF_SOURCES[$ref_name]}"$'\n'"$scan_file"
            fi
        else
            if [[ -z "${SKILL_REF_SOURCES[$ref_name]:-}" ]]; then
                SKILL_REF_SOURCES[$ref_name]="$scan_file"
            elif [[ "${SKILL_REF_SOURCES[$ref_name]}" != *"$scan_file"* ]]; then
                SKILL_REF_SOURCES[$ref_name]="${SKILL_REF_SOURCES[$ref_name]}"$'\n'"$scan_file"
            fi
        fi
    done < <(echo "$scan_content" | grep -oP 'hivemind:\K[a-zA-Z0-9_-]+' | sort -u)
done

skill_ref_count=${#SKILL_REF_SOURCES[@]}
for skill_name in "${!SKILL_REF_SOURCES[@]}"; do
    skill_md_path="$PLUGIN_ROOT/skills/$skill_name/SKILL.md"
    if [[ ! -f "$skill_md_path" ]]; then
        check3_found=true
        while IFS= read -r source_file; do
            [[ -z "$source_file" ]] && continue
            add_finding 'CHECK3' "$source_file" 0 \
                "Skill referenced but SKILL.md missing: plugin/skills/$skill_name/SKILL.md"
        done <<< "${SKILL_REF_SOURCES[$skill_name]}"
    fi
done

if [[ "$check3_found" == false ]]; then
    echo "[PASS] Check 3: All $skill_ref_count skill references resolve to SKILL.md files"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK3'

# ── CHECK 4: Agent names exist ─────────────────────────────────────────────

echo ''
echo '=== CHECK 4: Agent names exist ==='

check4_found=false
agent_ref_count=${#AGENT_REF_SOURCES[@]}
for agent_ref_name in "${!AGENT_REF_SOURCES[@]}"; do
    agent_md_path="$PLUGIN_ROOT/agents/$agent_ref_name.md"
    if [[ ! -f "$agent_md_path" ]]; then
        check4_found=true
        while IFS= read -r source_file; do
            [[ -z "$source_file" ]] && continue
            add_finding 'CHECK4' "$source_file" 0 \
                "Agent referenced but file missing: plugin/agents/$agent_ref_name.md"
        done <<< "${AGENT_REF_SOURCES[$agent_ref_name]}"
    fi
done

if [[ "$check4_found" == false ]]; then
    echo "[PASS] Check 4: All $agent_ref_count agent references resolve to .md files"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK4'

# ── CHECK 5: Unsupported frontmatter fields ────────────────────────────────

echo ''
echo '=== CHECK 5: Unsupported frontmatter fields ==='

check5_found=false
declare -a check5_agent_files=()
discover_checked_paths 'CHECK5' check5_agent_files files 'agent Markdown files' "$PLUGIN_ROOT/agents" -- -maxdepth 1 -name '*.md' || check5_found=true
for agent_file in "${check5_agent_files[@]}"; do
    in_frontmatter=false
    frontmatter_started=false
    line_num=0
    while IFS= read -r textline || [[ -n "$textline" ]]; do
        line_num=$((line_num + 1))
        trimmed="${textline#"${textline%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        if [[ "$trimmed" == "---" ]]; then
            if [[ "$frontmatter_started" == false ]]; then
                frontmatter_started=true
                in_frontmatter=true
                continue
            else
                break
            fi
        fi
        if [[ "$in_frontmatter" == false ]]; then
            continue
        fi

        if grep -qP '^\s*mcpServers\s*:' <<< "$textline"; then
            check5_found=true
            add_finding 'CHECK5' "$agent_file" "$line_num" \
                'Unsupported frontmatter field: mcpServers'
        fi
        if grep -qP '^\s*permissionMode\s*:' <<< "$textline"; then
            check5_found=true
            add_finding 'CHECK5' "$agent_file" "$line_num" \
                'Unsupported frontmatter field: permissionMode'
        fi
    done < "$agent_file"
done

if [[ "$check5_found" == false ]]; then
    echo '[PASS] Check 5: No unsupported frontmatter fields found'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK5'

# ── CHECK 6: Governance reference paths resolve ────────────────────────────

echo ''
echo '=== CHECK 6: Governance reference paths resolve ==='

check6_found=false
# PLUGIN_ROOT is invariant across the scan; resolve it once (#305).
normalized_plugin_root="$(realpath -m "$PLUGIN_ROOT")"
declare -a check6_md_files=()
discover_checked_paths 'CHECK6' check6_md_files files 'plugin Markdown files' "$PLUGIN_ROOT" -- -name '*.md' || check6_found=true
for md_file in "${check6_md_files[@]}"; do
    # Candidate prefilter (#305): the extraction below requires the literal
    # ${CLAUDE_PLUGIN_ROOT}/ prefix, so one fixed-string grep per FILE finds
    # every line that can yield a reference.
    candidates="$(file_candidates F '${CLAUDE_PLUGIN_ROOT}/' "$md_file")"
    [[ -z "$candidates" ]] && continue
    while IFS= read -r candidate; do
        line_num="${candidate%%:*}"
        textline="${candidate#*:}"
        # Extract all ${CLAUDE_PLUGIN_ROOT}/... references from this line
        while IFS= read -r ref_rel_path; do
            [[ -z "$ref_rel_path" ]] && continue
            # Strip trailing punctuation that is not part of file paths.
            while true; do
                case "$ref_rel_path" in
                    *.|*,|*';'|*':'|*')') ref_rel_path="${ref_rel_path%?}" ;;
                    *) break ;;
                esac
            done
            resolved_path="$PLUGIN_ROOT/$ref_rel_path"
            normalized_resolved="$(realpath -m "$resolved_path" 2>/dev/null || echo "$resolved_path")"

            if [[ "$normalized_resolved" != "$normalized_plugin_root" && "$normalized_resolved" != "$normalized_plugin_root/"* ]]; then
                check6_found=true
                add_finding 'CHECK6' "$md_file" "$line_num" \
                    "Path escapes plugin root: \${CLAUDE_PLUGIN_ROOT}/$ref_rel_path"
            else
                if [[ ! -f "$resolved_path" && ! -d "$resolved_path" ]]; then
                    check6_found=true
                    add_finding 'CHECK6' "$md_file" "$line_num" \
                        "Path does not resolve: \${CLAUDE_PLUGIN_ROOT}/$ref_rel_path"
                fi
            fi
        done < <(echo "$textline" | grep -oP '\$\{CLAUDE_PLUGIN_ROOT\}/\K[^\s`\)]+' || true)
    done <<< "$candidates"
done

if [[ "$check6_found" == false ]]; then
    echo '[PASS] Check 6: All governance reference paths resolve'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK6'

# ── CHECK 7: Skill frontmatter completeness ────────────────────────────────

echo ''
echo '=== CHECK 7: Skill frontmatter completeness ==='

REQUIRED_FRONTMATTER_FIELDS=('name' 'description' 'allowed-tools' 'shell')
check7_found=false
skill_file_count=0

declare -a check7_skill_files=()
discover_checked_paths 'CHECK7' check7_skill_files files 'skill SKILL.md files' "$PLUGIN_ROOT/skills" -- -name 'SKILL.md' || check7_found=true
for skill_file in "${check7_skill_files[@]}"; do
    skill_file_count=$((skill_file_count + 1))

    fm_content="$(get_frontmatter "$skill_file")"
    for field_name in "${REQUIRED_FRONTMATTER_FIELDS[@]}"; do
        if ! grep -qP "^\s*${field_name}\s*:" <<< "$fm_content"; then
            check7_found=true
            add_finding 'CHECK7' "$skill_file" 0 \
                "Missing required frontmatter field: $field_name"
        fi
    done
done

if [[ "$check7_found" == false ]]; then
    echo "[PASS] Check 7: All $skill_file_count skill files have complete frontmatter"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK7'

# ── CHECK 8: No bare governance/agents/skills path refs ────────────────────

echo ''
echo '=== CHECK 8: No bare governance/agents/skills path refs ==='

check8_found=false
declare -a check8_md_files=()
discover_checked_paths 'CHECK8' check8_md_files files 'plugin Markdown files' "$PLUGIN_ROOT" -- -name '*.md' || check8_found=true
for md_file in "${check8_md_files[@]}"; do
    # Candidate prefilter (#305): one grep per FILE for the bare-ref shape
    # WITHOUT the left-boundary group. Sound superset: every flagged ref is
    # built solely of characters inside the strip-token class below, and the
    # strip never leaves a class character at a deletion join point (its
    # token regex is greedy over that class), so a post-strip match always
    # exists verbatim in the raw line.
    candidates="$(file_candidates E '(agents|skills|governance|references|workflows)/([A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.(md|sh|json)' "$md_file")"
    [[ -z "$candidates" ]] && continue
    while IFS= read -r candidate; do
        line_num="${candidate%%:*}"
        textline="${candidate#*:}"
        # Strip every correct ${CLAUDE_PLUGIN_ROOT}/<path> token first so its
        # inner governance|agents|skills segment cannot trigger a false match.
        stripped="$(echo "$textline" | sed -E 's#\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./{}-]+##g')"
        # Flag any residual bare ref that carries a filename suffix. The suffix
        # requirement keeps generic prose like "the governance/ layer" clean.
        while IFS= read -r bare_ref; do
            [[ -z "$bare_ref" ]] && continue
            check8_found=true
            add_finding 'CHECK8' "$md_file" "$line_num" \
                "Bare path ref (missing \${CLAUDE_PLUGIN_ROOT}/ prefix): $bare_ref"
        done < <(echo "$stripped" | grep -oP '(^|[^A-Za-z0-9_./-])\K(agents|skills|governance|references|workflows)/([A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.(md|sh|json)' || true)
    done <<< "$candidates"
done

if [[ "$check8_found" == false ]]; then
    echo '[PASS] Check 8: No bare governance/agents/skills path refs'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK8'

# ── CHECK 9: Containment guard precedes guarded read in engine scripts ──────
#
# STRUCTURAL PREVENTION for issue #163: the "containment-guard-before-read"
# defect (a guarded path token READ at a line BEFORE its containment guard)
# recurred because safe ordering was convention, not enforced. This check makes
# the class non-regressable.
#
# Scope: every committed engine script matching plugin/skills/*/scripts/*.sh
# that SOURCES _shared/containment.sh. Scripts that do not source it (e.g.
# brood-discover.sh) are excluded — they have no guard to order against.
#
# For each (script, guarded-token) pair we locate:
#   * the GUARD line (the containment helper invocation for that token), and
#   * the FIRST DANGEROUS READ line (the first jq/cat that actually opens the
#     file, or — for $ledger — the first existence/validity probe on the
#     post-derivation path).
# We FIRE when a token is read but (a) has NO guard at all, or (b) its first
# dangerous read occurs at a line number BEFORE the guard.
#
# The $INPUTS_FILE containment guard may be satisfied EITHER by an inline
# hivemind_assert_inputs_contained call OR by delegation to the
# hivemind_read_inputs_file shared helper, which performs that assertion
# internally (per the ADR-0020 engine-IO extraction, issue #245). Both forms
# are recognized as the guard line. This recognizes a real guard and does NOT
# weaken the check: a script that reads $INPUTS_FILE with NEITHER an inline
# assertion NOR the helper call still fires a missing-guard finding.
#
# Deliberate exclusions to avoid false positives:
#   * the GUARD line itself names the token as an argument — never counted as a read.
#   * `[ -f "$INPUTS_FILE" ]` / `[ -n "$INPUTS_FILE" ]` are pure existence/arg
#     presence probes that legitimately precede the inputs guard; only the first
#     `jq` open of $INPUTS_FILE is the read the guard must gate (the jq validity
#     probe is the canonical read-oracle, per the engine reference script).
#   * `[ -L "$MANIFEST" ]` / `[ -f "$MANIFEST" ]` are leaf/existence probes that
#     precede the manifest guard by design; only `cat`/`jq` opens are reads.
#   * for $ledger the path is DERIVED after the runs-dir guard, so its first
#     `[ -f "$ledger" ]` existence probe IS a real read of the derived path and
#     the guard must precede it.
#
# Two distinct guards are enforced for the ledger, as SEPARATE token rows:
#   * $ledger      — the ANCESTOR/runs-dir ordering guard (hivemind_assert_contained)
#                    must precede the first ledger read. Its guard pattern is anchored
#                    to the EXECUTABLE invocation (^[[:space:]]*[^#]*hivemind_assert_contained
#                    [^#]*\.hivemind/runs/$run_id) so the prose comments that merely NAME
#                    hivemind_assert_contained are not miscounted as the guard line —
#                    otherwise the first match would be an explanatory comment ABOVE the
#                    real call, and a $ledger read moved above the real guard could pass.
#                    The read pattern is likewise line-start anchored (^[[:space:]]*) so a
#                    `[ -f "$ledger" ]` appearing inside a comment is not miscounted as the
#                    first read.
#   * $ledger-leaf — the LEAF symlink guard (hivemind_assert_ledger_contained) must
#                    ALSO precede the first ledger read. This makes the leaf guard
#                    TERMINAL: a containment-sourcing engine that reads "$ledger"
#                    without first calling hivemind_assert_ledger_contained fires a
#                    missing-guard or ordering finding, so a reverted leaf guard or a
#                    new unguarded ledger reader cannot regress silently. The
#                    $ledger-leaf row anchors its read/guard patterns at line start
#                    (^[[:space:]]*) so prose in comments naming the symbols is not
#                    miscounted as a guard or a read.

echo ''
echo '=== CHECK 9: Containment guard precedes guarded read in engine scripts ==='

# first_match_line PATTERN FILE [EXCLUDE_PATTERN]
# Echoes the line number of the first line matching PATTERN. When EXCLUDE_PATTERN
# is supplied, lines also matching it are skipped. Echoes empty when no match.
first_match_line() {
    local pattern="$1"
    local file="$2"
    local exclude="${3:-}"
    local matched
    while IFS= read -r matched; do
        [[ -z "$matched" ]] && continue
        local lineno="${matched%%:*}"
        local body="${matched#*:}"
        if [[ -n "$exclude" ]] && grep -qE "$exclude" <<< "$body"; then
            continue
        fi
        echo "$lineno"
        return
    done < <(grep -nE "$pattern" "$file" 2>/dev/null || true)
    echo ""
}

check9_found=false
check9_script_count=0

declare -a check9_engine_scripts=()
discover_checked_paths 'CHECK9' check9_engine_scripts files 'skill engine scripts' "$PLUGIN_ROOT/skills" -- -path '*/scripts/*.sh' || check9_found=true
for engine_script in "${check9_engine_scripts[@]}"; do
    # Only engine scripts that source the containment helper participate.
    if ! grep -qE '(^|[[:space:]])(\.|source)[[:space:]][^#]*containment\.sh' "$engine_script"; then
        continue
    fi
    check9_script_count=$((check9_script_count + 1))

    # Token table: TOKEN | GUARD_PATTERN | READ_PATTERN | READ_EXCLUDE
    # READ_EXCLUDE removes existence/arg-presence/symlink probes that legitimately
    # precede the guard so they are not mistaken for the gated open. For
    # $INPUTS_FILE the GUARD_PATTERN and READ_EXCLUDE both accept the
    # hivemind_read_inputs_file helper call as the guard (it runs
    # hivemind_assert_inputs_contained internally; ADR-0020 / #245), so the
    # bootstrap helper-call line is neither a missing guard nor a counted read.
    # EVERY GUARD_PATTERN is anchored to an EXECUTABLE line (^[[:space:]]*[^#]*)
    # so a COMMENT that merely NAMES the guard helper (e.g. a `# hivemind_read_inputs_file
    # "$INPUTS_FILE"` doc line above the first real read) is NOT miscounted as the
    # guard — otherwise an engine reading $INPUTS_FILE/$MANIFEST with no real guard
    # could pass on the strength of a comment mention.
    declare -a token_labels=('$INPUTS_FILE' '$MANIFEST' '$ledger' '$ledger-leaf')
    declare -a token_guards=(
        '^[[:space:]]*[^#]*(hivemind_assert_inputs_contained|hivemind_read_inputs_file)[^#]*"\$INPUTS_FILE"'
        '^[[:space:]]*[^#]*(hivemind_assert_inputs_contained|\[ -L )[^#]*"\$MANIFEST"'
        '^[[:space:]]*[^#]*hivemind_assert_contained[^#]*\.hivemind/runs/\$run_id'
        '^[[:space:]]*hivemind_assert_ledger_contained'
    )
    declare -a token_reads=(
        '(jq |cat )[^#]*"\$INPUTS_FILE"'
        '(jq |cat )[^#]*"\$MANIFEST"'
        '^[[:space:]]*(jq |cat |\[ -f )[^#]*"\$ledger"'
        '^[[:space:]]*(jq |cat |\[ -f )[^#]*"\$ledger"'
    )
    declare -a token_read_excludes=(
        'hivemind_assert_inputs_contained|hivemind_read_inputs_file|\[ -[fnL] '
        'hivemind_assert_inputs_contained|\[ -[fnL] '
        'hivemind_assert(_contained|_ledger_contained)'
        'hivemind_assert(_contained|_ledger_contained)'
    )

    ti=0
    while [[ $ti -lt ${#token_labels[@]} ]]; do
        token_label="${token_labels[$ti]}"
        read_line="$(first_match_line "${token_reads[$ti]}" "$engine_script" "${token_read_excludes[$ti]}")"
        ti_next=$((ti + 1))

        # Token not read in this script — nothing to order.
        if [[ -z "$read_line" ]]; then
            ti=$ti_next
            continue
        fi

        guard_line="$(first_match_line "${token_guards[$ti]}" "$engine_script")"

        if [[ -z "$guard_line" ]]; then
            check9_found=true
            add_finding 'CHECK9' "$engine_script" "$read_line" \
                "Containment guard missing: ${token_label} is read here but no containment guard for it exists in this engine script"
            ti=$ti_next
            continue
        fi

        if [[ "$read_line" -lt "$guard_line" ]]; then
            check9_found=true
            add_finding 'CHECK9' "$engine_script" "$read_line" \
                "Containment guard ordering: ${token_label} is read at line $read_line BEFORE its guard at line $guard_line — guard must precede the read"
        fi
        ti=$ti_next
    done

    unset token_labels token_guards token_reads token_read_excludes
done

if [[ "$check9_found" == false ]]; then
    echo "[PASS] Check 9: All $check9_script_count containment-sourcing engine scripts guard each token before its first read"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK9'

# ── CHECK 10: No literal NUL byte in plugin Markdown payload ───────────────
#
# Packaged plugin .md files (skills, agents, governance, references) are
# runtime-loaded TEXT assets. A literal NUL byte makes a file binary to
# `file`, truncates shell-based validators and Markdown tooling, and may be
# dropped or mistaken for binary by plugin consumers. Forbid it outright; a
# textual escape such as `\u0000` or `<NUL>` represents the byte in prose.
echo ''
echo '=== CHECK 10: No literal NUL byte in plugin Markdown payload ==='

check10_found=false
check10_md_count=0
declare -a check10_md_files=()
discover_checked_paths 'CHECK10' check10_md_files files 'plugin Markdown files' "$PLUGIN_ROOT" -- -name '*.md' || check10_found=true
for md_file in "${check10_md_files[@]}"; do
    check10_md_count=$((check10_md_count + 1))
    if LC_ALL=C grep -qaP '\x00' "$md_file" 2>/dev/null; then
        check10_found=true
        add_finding 'CHECK10' "$md_file" 0 \
            "Literal NUL byte in plugin Markdown payload — replace with a textual escape (e.g. \\u0000 or <NUL>); NUL makes the file binary and breaks Markdown/shell tooling and plugin consumers"
    fi
done

if [[ "$check10_found" == false ]]; then
    echo "[PASS] Check 10: All $check10_md_count plugin Markdown payload files are free of literal NUL bytes"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK10'

# ── CHECK 11: No bare calling-bioform name in skill body prose (P14) ────────
#
# Reusable skills are role-agnostic and may be invoked by any agent. Naming a
# specific calling bioform (overlord/drone/changeling) in skill BODY prose
# couples the skill to one caller and violates engineering-principles.md P14:
# reference the caller by role/intent, not by bioform name. Agents legitimately
# own these names, so scope is skills/ only. Structural exclusions (YAML
# frontmatter, fenced code blocks, table rows) and a KEEP-phrase allowlist for
# legitimate architectural-invariant/topology mentions keep the scan tight.

echo ''
echo '=== CHECK 11: No bare calling-bioform name in skill body prose (P14) ==='

# Denylist of calling-bioform names — single variable for trivial extension.
# cerebrate is intentionally NOT in v1; it is deferred to issue #254.
BIOFORM_DENYLIST='overlord|drone|changeling'
# KEEP-phrase regex: legitimate architectural-invariant/topology mentions that
# must NOT be flagged even though they contain a denylisted word.
CHECK11_KEEP_REGEX='RUN-OWNERSHIP-01|overlord instance|overlord session|overlord-invocable|overlord resume|overlord step|hivemind:overlord|parallel overlord sessions'

# Candidate prefilter words (#305): derived by splitting the two variables
# above on '|'. INVARIANT: every alternative in BIOFORM_DENYLIST and
# CHECK11_KEEP_REGEX must stay a LITERAL (no regex metacharacters) so the
# lowercase substring gate below stays a SUPERSET of both the case-insensitive
# denylist word-match and the KEEP-phrase strip — a non-candidate line has
# residual == line and no denylist word, so it can never produce a finding.
declare -a CHECK11_CANDIDATE_WORDS=()
IFS='|' read -ra CHECK11_CANDIDATE_WORDS <<< "${BIOFORM_DENYLIST,,}|${CHECK11_KEEP_REGEX,,}"

check11_found=false
declare -a check11_skill_files=()
discover_checked_paths 'CHECK11' check11_skill_files files 'skill SKILL.md files' "$PLUGIN_ROOT/skills" -- -name 'SKILL.md' || check11_found=true
for skill_file in "${check11_skill_files[@]}"; do
    # One-pass awk state machine emits surviving BODY lines as "line_num<TAB>line",
    # excluding YAML frontmatter, fenced code blocks, and markdown table rows.
    while IFS=$'\t' read -r line_num textline; do
        [[ -z "$line_num" ]] && continue
        # Pure-bash candidate gate (#305): skip the per-line sed+grep spawns
        # for lines carrying no denylist word and no KEEP phrase.
        lc_line="${textline,,}"
        line_is_candidate=false
        for candidate_word in "${CHECK11_CANDIDATE_WORDS[@]}"; do
            if [[ "$lc_line" == *"$candidate_word"* ]]; then
                line_is_candidate=true
                break
            fi
        done
        if [[ "$line_is_candidate" == false ]]; then
            continue
        fi
        # Strip legitimate KEEP-phrase spans first (mirrors CHECK 8's
        # ${CLAUDE_PLUGIN_ROOT} strip at line ~504), so a real leak sharing a
        # line with a legit mention is still caught instead of the whole line
        # being exempted.
        residual="$(echo "$textline" | sed -E "s/(${CHECK11_KEEP_REGEX})//Ig")"
        if grep -qiwE "($BIOFORM_DENYLIST)" <<< "$residual"; then
            bare_word="$(echo "$residual" | grep -oiwE "($BIOFORM_DENYLIST)" | head -n1)"
            check11_found=true
            add_finding 'CHECK11' "$skill_file" "$line_num" \
                "bare calling-bioform name '$bare_word' in skill body prose -- reference the caller by role/intent (P14); see engineering-principles.md P14"
        fi
    done < <(awk '
        BEGIN { in_fm = 0; fm_done = 0; in_fence = 0 }
        {
            # YAML frontmatter: first line "---" opens, next "---" closes.
            if (!fm_done && NR == 1 && $0 == "---") { in_fm = 1; next }
            if (in_fm) { if ($0 == "---") { in_fm = 0; fm_done = 1 } next }
            # Fenced code blocks toggle on lines starting with ```.
            if ($0 ~ /^```/) { in_fence = !in_fence; next }
            if (in_fence) next
            # Markdown table rows.
            if ($0 ~ /^[ \t]*\|/) next
            print NR "\t" $0
        }
    ' "$skill_file")
done

if [[ "$check11_found" == false ]]; then
    echo '[PASS] Check 11: No bare calling-bioform name in skill body prose (P14)'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK11'

# ── CHECK 12: No bare validation-tool/manifest token in governance/agents prose ─
#
# Governance and agent docs are runtime-loaded instructions. Naming a concrete
# validation-tool or manifest filename in prose (e.g. a validate script, a
# syntax-check invocation, a language manifest) hard-codes a project-specific
# toolchain detail into role-agnostic doctrine — the same coupling class CHECK 8
# guards for path refs. Scope is governance/ and agents/ only (maxdepth 1, NOT
# skills — skills are covered by their own checks). The denylist names whole
# concrete tool/manifest tokens, never bare generics like jq, json, or version.
#
# Structural exclusions mirror CHECK 11: YAML frontmatter, fenced code blocks,
# and >=4-space indented (code) lines are skipped via a per-file in_fence
# toggle, and backtick inline-code spans are stripped before matching so a
# token shown as inline code is not flagged.

echo ''
echo '=== CHECK 12: No bare validation-tool/manifest token in governance/agents prose ==='

# Denylist of concrete validation-tool / manifest tokens. Whole tokens only —
# deliberately excludes bare generics (jq, json, version) to avoid false hits.
CHECK12_DENYLIST='tools/validate\.sh|bash -n|python3 -m json\.tool|test_[a-z0-9_]+\.sh|package\.json|pyproject\.toml|Cargo\.toml|go\.mod|requirements\.txt|plugin\.json|marketplace\.json'

check12_found=false
declare -a check12_doc_files=()
discover_checked_paths 'CHECK12' check12_doc_files files 'governance and agent Markdown files' "$PLUGIN_ROOT/governance" "$PLUGIN_ROOT/agents" -- -maxdepth 1 -name '*.md' || check12_found=true
for doc_file in "${check12_doc_files[@]}"; do
    # One-pass awk state machine emits surviving BODY lines as "line_num<TAB>line",
    # excluding YAML frontmatter, fenced code blocks, and >=4-space indented lines.
    while IFS=$'\t' read -r line_num textline; do
        [[ -z "$line_num" ]] && continue
        # Pure-bash candidate gate (#305). INVARIANT: this gate must stay a
        # SUPERSET of lines whose backtick-stripped residual can match
        # CHECK12_DENYLIST — a backticked line may change under the strip
        # (deleting a span can join fragments), so every backticked line is a
        # candidate; a backtick-free line has residual == line, and every
        # denylist alternative contains one of the literal fragments below.
        # Extend the fragment list when CHECK12_DENYLIST gains an alternative.
        case "$textline" in
            *'`'*|*'tools/validate.sh'*|*'bash -n'*|*'python3 -m json.tool'*|*'test_'*|*'.json'*|*'.toml'*|*'go.mod'*|*'requirements.txt'*) ;;
            *) continue ;;
        esac
        # Strip backtick inline-code spans first (mirrors CHECK 11's KEEP-phrase
        # strip at line ~730), so a token shown as inline code is exempt while a
        # real bare occurrence sharing a line with inline code is still caught.
        # A backtick-free candidate needs no strip: residual == line.
        if [[ "$textline" == *'`'* ]]; then
            residual="$(echo "$textline" | sed -E 's/`[^`]*`//g')"
        else
            residual="$textline"
        fi
        if grep -qE "($CHECK12_DENYLIST)" <<< "$residual"; then
            bare_token="$(echo "$residual" | grep -oE "($CHECK12_DENYLIST)" | head -n1)"
            check12_found=true
            add_finding 'CHECK12' "$doc_file" "$line_num" \
                "bare validation-tool/manifest token '$bare_token' in governance/agents prose -- reference the toolchain by role/intent, not a concrete tool or manifest filename"
        fi
    done < <(awk '
        BEGIN { in_fm = 0; fm_done = 0; in_fence = 0 }
        {
            # YAML frontmatter: first line "---" opens, next "---" closes.
            if (!fm_done && NR == 1 && $0 == "---") { in_fm = 1; next }
            if (in_fm) { if ($0 == "---") { in_fm = 0; fm_done = 1 } next }
            # Fenced code blocks toggle on lines starting with ```.
            if ($0 ~ /^```/) { in_fence = !in_fence; next }
            if (in_fence) next
            # Indented code lines (>=4 leading spaces).
            if ($0 ~ /^    /) next
            print NR "\t" $0
        }
    ' "$doc_file")
done

if [[ "$check12_found" == false ]]; then
    echo '[PASS] Check 12: No bare validation-tool/manifest token in governance/agents prose'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK12'

# ── CHECK 13: P18 fail-closed shell floor ──────────────────────────────────
#
# Every committed plugin runtime shell script (plugin/**/*.sh) MUST enable the
# fail-closed shell floor — errexit, nounset, and pipefail — before its first
# executable statement, OR carry a documented CHECK13 allowlist exception. The
# three options may be set across one or more top-level `set` lines and in any
# spelling (set -euo pipefail, set -e + set -u + set -o pipefail, set -eu +
# set -o pipefail, set -o errexit -o nounset -o pipefail, etc.). Each `set` line
# is parsed by a left-to-right argument tokenizer that mirrors Bash's own
# interpretation: clustered short flags (-euo), long-form `-o name`, the `+`/`+o`
# disable forms, and the `--` end-of-options terminator (after which tokens are
# positional, NOT options) are all handled in one ordered walk. Option state
# persists across lines so a split-line floor and a later disable resolve to the
# final state. Scope is plugin runtime scripts only — tools/ and tests/ are
# intentionally excluded.
#
# Detection reads top-of-file lines, skipping the shebang and comment/blank
# lines, and stops scanning `set` options at the first non-comment executable
# statement. Lines are CRLF-tolerant: a trailing carriage return is stripped
# before matching so an autocrlf checkout does not produce false findings.
#
# SCOPE / LIMITATION: CHECK 13 is a BEST-EFFORT lint. It detects the PRESENCE of
# a floor STATEMENT at the top of a script — a standalone `set -euo pipefail`
# equivalent that runs as a simple command in the main shell. It does NOT prove
# floor EFFECTIVENESS under every pathological construct: a floor `set` reached
# only inside a conditional or function after the scan window, or an eval'd /
# dynamically-built `set`, is outside what this scanner can verify and is a
# documented limitation tracked separately. The scanner DOES fail closed on the
# common ineffective forms — a `set` that is piped, subshelled, backgrounded,
# chained, or `;`-separated is treated as establishing nothing (see the
# effectiveness guard below), so those constructs are flagged rather than
# silently credited.
#
# Finding line: a documented exception script carries a `P18 FLOOR EXCEPTION`
# comment marking the deliberate omission; the marker is recognized by canonical
# normalized match (see the marker branch below) and the finding is anchored to
# that line so the CHECK13 allowlist entry (seeded to that comment line) matches
# via the established test_allowlisted path. A script with no such marker (e.g. a
# new unguarded script) falls back to its first executable line, or line 1.

echo ''
echo '=== CHECK 13: P18 fail-closed shell floor ==='

check13_found=false
declare -a check13_shell_scripts=()
discover_checked_paths 'CHECK13' check13_shell_scripts files 'plugin shell scripts' "$PLUGIN_ROOT" -- -name '*.sh' || check13_found=true
for shell_script in "${check13_shell_scripts[@]}"; do
    has_errexit=false
    has_nounset=false
    has_pipefail=false
    first_set_line=0
    exception_line=0
    line_num=0
    while IFS= read -r textline || [[ -n "$textline" ]]; do
        line_num=$((line_num + 1))
        # CRLF tolerance: strip a single trailing carriage return.
        textline="${textline%$'\r'}"
        trimmed="${textline#"${textline%%[![:space:]]*}"}"
        # Skip the shebang, blank lines, and comment lines. The documented
        # P18 FLOOR EXCEPTION marker, when present, anchors the finding line.
        if [[ "$line_num" -eq 1 && "$trimmed" == '#!'* ]]; then
            continue
        fi
        # Recognize the documented P18 FLOOR EXCEPTION marker by CANONICAL
        # NORMALIZED match rather than a brittle contiguous-substring test. All
        # shipped markers are single-sourced to the exact phrase
        # `P18 FLOOR EXCEPTION`; normalizing the candidate line before the
        # contains-test additionally tolerates future whitespace/punctuation
        # drift (extra spaces, ASCII hyphen `-`, em-dash, en-dash) on that same
        # 3-word phrase. Normalization: strip a leading `#` and surrounding
        # whitespace, strip a trailing CR (already stripped above, belt-and-
        # suspenders), collapse internal runs of whitespace AND dash characters
        # to a single space, then uppercase. Recognition is contiguous (the
        # normalized line must CONTAIN the normalized canonical token), NOT a
        # gappy subsequence, so unrelated comments cannot falsely match.
        if [[ "$exception_line" -eq 0 ]]; then
            # Candidate pretest (#305): the canonical token contains the
            # contiguous run 'P18', and no normalization step below can
            # CREATE that run (collapsing inserts a single space; the strips
            # only remove edge characters), so a line without a
            # case-insensitive 'p18' can never normalize to contain the
            # token. Skip the sed|tr spawns for such lines.
            if [[ "${trimmed^^}" == *'P18'* ]]; then
                norm_line="$(printf '%s' "$trimmed" \
                    | sed -e 's/\r$//' \
                          -e 's/^#//' \
                          -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                          -e 's/[[:space:]–—-]\{1,\}/ /g' \
                    | tr '[:lower:]' '[:upper:]')"
                if [[ "$norm_line" == *'P18 FLOOR EXCEPTION'* ]]; then
                    exception_line="$line_num"
                fi
            fi
        fi
        if [[ -z "$trimmed" || "$trimmed" == '#'* ]]; then
            continue
        fi
        # Parse top-level `set` lines with a left-to-right argument tokenizer
        # that mirrors how Bash itself interprets `set` arguments, rather than a
        # bag of independent per-line regexes. The previous regex approach was
        # FAIL-OPEN for `set -- -e -u -o pipefail`: Bash treats every token after
        # `--` as a POSITIONAL PARAMETER, not an option, so such a line floors
        # NOTHING — but the regexes still counted the trailing -e/-u/-o pipefail
        # and let an unfloored script pass strict validation. Tokenizing in order
        # and stopping at `--` closes that hole and dissolves the whole flag-side
        # edge-case class (clusters, long-form `-o name`, `+`/`+o` disables, and
        # `--` terminator are all one walk).
        if [[ "$trimmed" == 'set '* || "$trimmed" == 'set' ]]; then
            [[ "$first_set_line" -eq 0 ]] && first_set_line="$line_num"
            # Strip a trailing inline comment before tokenizing: a `#` preceded
            # by whitespace begins a shell comment, so flags appearing only after
            # it (e.g. `set -u # TODO add -e -o pipefail`) must NOT count toward
            # the floor. Without this strip, comment text would falsely satisfy
            # errexit/pipefail and skip both the finding and the CHECK13
            # allowlist path.
            set_flags="$trimmed"
            if [[ "$set_flags" =~ ^(.*[[:space:]])#.*$ ]]; then
                set_flags="${BASH_REMATCH[1]}"
            fi
            # Strip a SINGLE optional trailing list terminator before the
            # effectiveness guard below. A standalone `set -euo pipefail;` (or,
            # after the inline-comment strip above, `set -euo pipefail; # note`)
            # is still ONE valid Bash simple command that floors the current
            # shell — the trailing `;` is a list terminator, not a separator
            # introducing a SECOND command. Removing only a `;` that is the last
            # non-whitespace character keeps such a floor effective while leaving
            # a `;` that DOES introduce another command (`set -e; cmd`) intact,
            # so the guard below still marks THAT line inert. Strictness is
            # preserved: this only un-inerts a genuine trailing-terminator floor.
            if [[ "$set_flags" =~ ^(.*[^[:space:];])[[:space:]]*\;[[:space:]]*$ ]]; then
                set_flags="${BASH_REMATCH[1]}"
            fi
            # FAIL-CLOSED effectiveness guard: a `set` only changes the script's
            # main-shell options when it runs as a STANDALONE SIMPLE COMMAND. A
            # `set` that is piped (`set -euo pipefail | cat`), subshelled
            # (`(set -euo pipefail)`), backgrounded (`set ... &`), chained
            # (`set ... && cmd`), command-substituted, or split off with a `;`
            # that introduces another command runs in a subshell or is not the
            # floor statement at all, so its flags do NOT establish the floor.
            # Detecting any of these operator characters in the set statement
            # marks the line INERT: we do not tokenize it and do not credit its
            # flags, so the script is judged on the remaining effective `set`
            # lines (and is flagged if none floor it). This is strictness-only —
            # it can never fail open. The option NAME `pipefail` contains no `|`,
            # so a clean `set -euo pipefail`, `set -o pipefail`, `set -e`,
            # `set -u`, split-line floors, a trailing-`;` floor (stripped above),
            # and `set --` carry NONE of these characters and are unaffected.
            if [[ "$set_flags" == *'|'* || "$set_flags" == *'&'* \
                || "$set_flags" == *'('* || "$set_flags" == *')'* \
                || "$set_flags" == *';'* || "$set_flags" == *'`'* \
                || "$set_flags" == *'$'* ]]; then
                continue
            fi
            # has_errexit/has_nounset/has_pipefail PERSIST across `set` lines and
            # are NOT reset here: a split-line floor (set -e + set -u + set -o
            # pipefail) and a disable-after-floor (set -euo pipefail; set +e)
            # both depend on order across lines, so the FINAL state before the
            # first executable statement decides the floor.
            read -ra set_args <<< "$set_flags"
            arg_count=${#set_args[@]}
            arg_index=1   # set_args[0] is the literal `set`
            while [[ "$arg_index" -lt "$arg_count" ]]; do
                token="${set_args[$arg_index]}"
                if [[ "$token" == '--' ]]; then
                    # Everything after `--` is positional, not options. Stop.
                    break
                elif [[ "$token" == '-o' || "$token" == '+o' ]]; then
                    # Long-form option: the NAME is the next token. Enable for
                    # `-o`, disable for `+o`. Guard the trailing-token case.
                    if [[ "$((arg_index + 1))" -lt "$arg_count" ]]; then
                        opt_name="${set_args[$((arg_index + 1))]}"
                        case "$opt_name" in
                            errexit)  [[ "$token" == '-o' ]] && has_errexit=true  || has_errexit=false ;;
                            nounset)  [[ "$token" == '-o' ]] && has_nounset=true  || has_nounset=false ;;
                            pipefail) [[ "$token" == '-o' ]] && has_pipefail=true || has_pipefail=false ;;
                        esac
                        arg_index=$((arg_index + 1))   # consume the name token
                    fi
                elif [[ "$token" == '-' || "$token" == '+' ]]; then
                    : # bare - / + : ignore safely
                elif [[ "$token" == -[a-zA-Z]* ]]; then
                    # Clustered SHORT enable flags, e.g. -e, -eu, -euo. Walk the
                    # cluster letters; a cluster `o` consumes the NEXT WHOLE TOKEN
                    # as the long option name (the `-euo pipefail` case).
                    cluster="${token#-}"
                    cluster_i=0
                    while [[ "$cluster_i" -lt "${#cluster}" ]]; do
                        letter="${cluster:$cluster_i:1}"
                        case "$letter" in
                            e) has_errexit=true ;;
                            u) has_nounset=true ;;
                            o)
                                if [[ "$((arg_index + 1))" -lt "$arg_count" ]]; then
                                    opt_name="${set_args[$((arg_index + 1))]}"
                                    case "$opt_name" in
                                        errexit)  has_errexit=true ;;
                                        nounset)  has_nounset=true ;;
                                        pipefail) has_pipefail=true ;;
                                    esac
                                    arg_index=$((arg_index + 1))   # consume name
                                fi
                                break   # `o` ends cluster scanning
                                ;;
                        esac
                        cluster_i=$((cluster_i + 1))
                    done
                elif [[ "$token" == +[a-zA-Z]* ]]; then
                    # Clustered SHORT disable flags, e.g. +e, +eu. A cluster `o`
                    # consumes the next token as the name and disables it.
                    cluster="${token#+}"
                    cluster_i=0
                    while [[ "$cluster_i" -lt "${#cluster}" ]]; do
                        letter="${cluster:$cluster_i:1}"
                        case "$letter" in
                            e) has_errexit=false ;;
                            u) has_nounset=false ;;
                            o)
                                if [[ "$((arg_index + 1))" -lt "$arg_count" ]]; then
                                    opt_name="${set_args[$((arg_index + 1))]}"
                                    case "$opt_name" in
                                        errexit)  has_errexit=false ;;
                                        nounset)  has_nounset=false ;;
                                        pipefail) has_pipefail=false ;;
                                    esac
                                    arg_index=$((arg_index + 1))   # consume name
                                fi
                                break
                                ;;
                        esac
                        cluster_i=$((cluster_i + 1))
                    done
                fi
                # anything else (positional-looking / unknown long opt) → ignore
                arg_index=$((arg_index + 1))
            done
            continue
        fi
        # First non-comment, non-set executable statement ends the floor window:
        # `set` options enabled below here would not establish the floor.
        break
    done < "$shell_script"

    if [[ "$has_errexit" == true && "$has_nounset" == true && "$has_pipefail" == true ]]; then
        continue
    fi

    # Anchor the finding to (in precedence order) the documented P18 FLOOR
    # EXCEPTION comment, the first partial `set` line, or line 1 — so a
    # documented-exception script's finding line matches its seeded CHECK13
    # allowlist entry via test_allowlisted (the exception comment for scripts
    # that carry one, the partial-floor `set` line otherwise, line 1 for a
    # bare sourced library). A new unguarded script with none of these still
    # fires on line 1.
    if [[ "$exception_line" -gt 0 ]]; then
        finding_line="$exception_line"
    elif [[ "$first_set_line" -gt 0 ]]; then
        finding_line="$first_set_line"
    else
        finding_line=1
    fi
    # The pass/fail tally counts only NON-allowlisted findings as failures: a
    # script with a documented CHECK13 exception is a clean (allowlisted) state,
    # not a check failure. Resolve allowlist status on the same rel-path
    # normalization add_finding applies so the two agree.
    rel_script="$shell_script"
    if [[ "$shell_script" == "$REPO_ROOT"* ]]; then
        rel_script="${shell_script#"$REPO_ROOT"/}"
    fi
    rel_script="${rel_script//\\//}"
    if [[ "$(test_allowlisted 'CHECK13' "$rel_script" "$finding_line")" != "true" ]]; then
        check13_found=true
    fi
    add_finding 'CHECK13' "$shell_script" "$finding_line" \
        "missing P18 fail-closed shell floor (set -euo pipefail) -- add the floor or document a justified CHECK13 allowlist exception"
done

if [[ "$check13_found" == false ]]; then
    echo '[PASS] Check 13: All plugin shell scripts carry the P18 fail-closed floor or a CHECK13 exception'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK13'

# ── CHECK 14: Inert inputs-file navigator obligations ──────────────────────
#
# WHAT IT GUARANTEES. CHECK 9 enforces guard-before-read ONLY for engine
# scripts that ALREADY source containment.sh, so NOT sourcing it is a silent
# opt-out: a skill promoted to an inputs-file navigator without a
# containment-sourcing engine is invisible to CHECK 9 forever. CHECK 14 makes
# that source MANDATORY for every navigator that CARRIES the discovery marker
# below — enrolling the navigator into CHECK 9 is the obligation, so across the
# MARKED set CHECK 9 stops being optional. The check also fails CLOSED on the
# discovery key itself: zero discovered navigators is an ERROR, not a pass, so
# the marker disappearing repo-wide cannot silently disarm the check.
#
# WHAT IT DOES NOT. A Write-carrying skill that never adopts the marker stays
# INVISIBLE to this check. The CHECK 9 opt-out is NARROWED to that one case and
# made LOUD everywhere else — it is not eliminated. Marker adoption on a NEWLY
# authored navigator is an AUTHORING CONVENTION, not a machine-verified
# property; that residual gap is tracked at #319.
#
# DISCOVERY KEY (no hand-kept list): every navigator's `allowed-tools` Write
# entry carries the literal marker `# inert inputs-file only:` (see
# security-policy.md "Inert Inputs-File Navigator Pattern", which declares this
# marker the validator's load-bearing discovery key BY CONVENTION). Executor
# skills carry a BARE `- Write` with no marker and carry NEITHER obligation.
# Because discovery is driven off that marker, adding a navigator without its
# obligations turns this suite red automatically ONLY IF the new navigator
# adopts the marker.
#
# Matching is FIXED-STRING on both the marker and the `- Write` entry token,
# scoped to the file's YAML frontmatter. A frontmatter parser is deliberately
# NOT written: the frontmatter form is stable and a parser is a new failure
# surface.
#
# Each discovered navigator must satisfy BOTH obligations:
#   (a) at least one plugin/skills/<name>/scripts/*.sh sources containment.sh in
#       the DIRECT `. <path>/containment.sh` form. The predicate is CHECK 9's own
#       enrollment regex, byte for byte, so obligation (a) and CHECK 9 enrollment
#       are the SAME condition and cannot diverge. A script that sources the
#       library indirectly (e.g. through a `for lib in ...` loop variable) is NOT
#       enrolled by CHECK 9 and therefore does NOT satisfy (a) — that is the point,
#       not a false positive: an unenrolled navigator has no guard-ordering
#       enforcement.
#   (b) the literal `hivemind:<name>` appears inside the Inert Inputs-File
#       Navigator Pattern section of plugin/governance/security-policy.md, i.e.
#       the navigator is in the policy's enumerated covered set.
echo ''
echo '=== CHECK 14: Inert inputs-file navigator obligations ==='

CHECK14_MARKER='# inert inputs-file only:'
CHECK14_WRITE_ENTRY='- Write'
CHECK14_POLICY_DOC="$PLUGIN_ROOT/governance/security-policy.md"
CHECK14_SECTION_HEADING='### Inert Inputs-File Navigator Pattern'

# Body of the covered-set section: the heading's lines up to (not including) the
# next `### ` heading. Obligation (b) is asserted against this span alone, so a
# `hivemind:<name>` mention elsewhere in the policy doc cannot satisfy it.
# A trailing CR is stripped before the heading comparison: governance docs in this
# repo are stored CRLF, and an exact match against a CR-terminated line would
# silently yield an EMPTY section and fail every navigator.
check14_section="$(awk -v heading="$CHECK14_SECTION_HEADING" '
    { sub(/\r$/, "") }
    $0 == heading { in_section = 1; next }
    in_section && /^### / { exit }
    in_section { print }
' "$CHECK14_POLICY_DOC")"

# skill_declares_navigator_marker FILE
# Echoes "true" when the skill's frontmatter carries a `- Write` entry bearing
# the inert-inputs-file marker, "false" otherwise.
skill_declares_navigator_marker() {
    local skill_file="$1"
    local fm_line
    while IFS= read -r fm_line; do
        [[ "$fm_line" != *"$CHECK14_WRITE_ENTRY"* ]] && continue
        [[ "$fm_line" != *"$CHECK14_MARKER"* ]] && continue
        echo "true"
        return
    done <<< "$(get_frontmatter "$skill_file")"
    echo "false"
}

# skill_sources_containment SKILL_DIR
# Sets SKILL_SOURCES_CONTAINMENT_RESULT to "true" when any engine script under
# SKILL_DIR/scripts sources containment.sh under CHECK 9's enrollment predicate
# (reused verbatim), "false" otherwise -- including when SKILL_DIR/scripts is
# absent. A scripts path that exists but is not a followable directory, a
# failed discovery, or a rejected script is reported as a CHECK14 finding (and
# sets check14_found), so the result is returned in a global rather than by
# command substitution: a subshell would drop those findings.
SKILL_SOURCES_CONTAINMENT_RESULT=""
skill_sources_containment() {
    local skill_dir="$1"
    local scripts_dir="$skill_dir/scripts"
    local engine_script
    SKILL_SOURCES_CONTAINMENT_RESULT="false"
    if [[ ! -e "$scripts_dir" && ! -L "$scripts_dir" ]]; then
        return 0
    fi
    local scripts_dir_rc=0
    discovery_gate_status "$scripts_dir" dirs || scripts_dir_rc=$?
    if [[ "$scripts_dir_rc" -ne 0 ]]; then
        check14_found=true
        flag_discovery_gate 'CHECK14' "$scripts_dir" "$scripts_dir_rc"
        return 0
    fi
    local -a check14_engine_scripts=()
    discover_checked_paths 'CHECK14' check14_engine_scripts files 'skill engine scripts' "$scripts_dir" -- -maxdepth 1 -name '*.sh' || check14_found=true
    for engine_script in "${check14_engine_scripts[@]}"; do
        if grep -qE '(^|[[:space:]])(\.|source)[[:space:]][^#]*containment\.sh' "$engine_script"; then
            SKILL_SOURCES_CONTAINMENT_RESULT="true"
            return 0
        fi
    done
}

check14_found=false
check14_navigator_count=0

declare -a check14_skill_files=()
discover_checked_paths 'CHECK14' check14_skill_files files 'skill SKILL.md files' "$PLUGIN_ROOT/skills" -- -maxdepth 2 -name 'SKILL.md' || check14_found=true
for skill_file in "${check14_skill_files[@]}"; do
    if [[ "$(skill_declares_navigator_marker "$skill_file")" != "true" ]]; then
        continue
    fi
    check14_navigator_count=$((check14_navigator_count + 1))

    skill_dir="$(dirname "$skill_file")"
    skill_name="$(basename "$skill_dir")"
    marker_line="$(grep -nF "$CHECK14_MARKER" "$skill_file" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
    [[ -z "$marker_line" ]] && marker_line=0

    skill_sources_containment "$skill_dir"
    if [[ "$SKILL_SOURCES_CONTAINMENT_RESULT" != "true" ]]; then
        check14_found=true
        add_finding 'CHECK14' "$skill_file" "$marker_line" \
            "Inert inputs-file navigator hivemind:${skill_name} fails obligation (a): no plugin/skills/${skill_name}/scripts/*.sh sources containment.sh in the direct '. <path>/containment.sh' form CHECK 9 enrolls on (an indirect loop-variable source does not enroll) -- until it does, CHECK 9's guard-before-read enforcement never applies to this navigator"
    fi

    if [[ "$check14_section" != *"hivemind:${skill_name}"* ]]; then
        check14_found=true
        add_finding 'CHECK14' "$skill_file" "$marker_line" \
            "Inert inputs-file navigator hivemind:${skill_name} fails obligation (b): literal 'hivemind:${skill_name}' is absent from the '${CHECK14_SECTION_HEADING}' section of plugin/governance/security-policy.md -- add it to the covered-set enumeration"
    fi
done

# FAIL-CLOSED on the discovery key itself: zero navigators means the marker was
# renamed or dropped, which would silently disarm this check rather than fail it.
if [[ "$check14_navigator_count" -eq 0 ]]; then
    check14_found=true
    add_finding 'CHECK14' "$CHECK14_POLICY_DOC" 0 \
        "Inert inputs-file navigator discovery found ZERO navigators -- the '${CHECK14_MARKER}' discovery key is missing from every skill frontmatter, which disarms this check; restore the marker or retire the pattern deliberately"
fi

if [[ "$check14_found" == false ]]; then
    echo "[PASS] Check 14: All $check14_navigator_count inert inputs-file navigators source containment.sh and are enumerated in the security policy's covered set"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK14'

# ── CHECK 15: No tracker references in plugin runtime prose ────────────────
#
# WHAT IT GUARANTEES. docs/engineering-principles.md P19 (doctrine anchors on
# durable records, not tracker IDs) forbids a bare `#NNN` in runtime doctrine:
# the ticket closes, is renumbered in meaning, or is superseded, and the prose
# silently rots. P17 says a mechanizable rule left to reviewer vigilance is
# decoration, so P19 is only real once a CI guard asserts it -- this is that
# guard.
#
# SCOPE. plugin/**/*.md plus plugin/workflows/*.json: the runtime-loaded
# instruction payload an agent reads as its own context. Committed shell under
# plugin/ is deliberately OUT of scope -- its comments are developer-facing and
# are never loaded into an agent's context, so a tracker ID there stales a
# maintainer note rather than doctrine.
#
# SCAN SHAPE. One POSIX awk program, CHECK15_CLASSIFY_AWK, is the single source
# of classification: scan_prose_file_refs runs it over a whole file and
# tracker_ref_tokens runs it over one line, so the predicate the canaries assert
# and the traversal CI runs cannot drift apart. It carries no state across
# records: one record per physical line, every per-line variable reset on
# entry. NO line is exempt by POSITION -- YAML frontmatter, fenced code blocks,
# and indented continuation lines are all scanned. Exemption is by SHAPE only.
# Two reasons, both load-bearing. First, a region skipper is a state machine
# whose failure mode is silent: one unclosed region opener swallows the entire
# remaining file body and the check still reports PASS over prose it never
# read, so that whole class of failure is DELETED here rather than guarded.
# Second, frontmatter in this payload is not inert metadata -- it is
# runtime-loaded agent context (a skill's name and description are read before
# its body), so it carries doctrine and earns the same rule as the body.
#
# DETECTION IS A POSITIVE ALLOWLIST. Each record first loses a trailing CR, so a
# CRLF checkout yields records and tokens byte-identical to the LF case. A
# left-to-right walk then classifies the line:
#   * CANDIDATE: a `#` followed by a digit run, UNCONDITIONALLY -- whatever
#     character follows the run. The token is the `#` plus that digit run and
#     never the word characters after it. Only a candidate can become a
#     finding, so ATX headings and a `#!` shebang are never candidates: their
#     `#` is not followed by a digit.
#   * SAFE SHAPES, each an anchored prefix match at the walk position, consumed
#     whole so nothing inside the span is classified:
#       S1 inline code -- a backtick run of length L, closed by the next
#          backtick run of EXACTLY length L on the line. With no such closer
#          the opening run is literal text and the walk continues right after
#          it (CommonMark spec, "Code spans"), so an unclosed span, or a fence
#          delimiter line such as ```text, exempts nothing.
#          Exempts literal placeholders such as the issue-number placeholder
#          in plugin/skills/prd-to-issues/SKILL.md.
#       S3 in-page anchor -- `](#` through the first `)`, including the
#          digit-leading slugs a letter-first rule would miss.
#       S2 cross-repo citation -- owner/repo#NNN with exactly one `/`, each
#          side starting alphanumeric, the digit run followed by end of line
#          or a character outside [0-9A-Za-z_], and tried only at a LEFT
#          BOUNDARY (line start, or a previous character outside
#          [A-Za-z0-9._/-]). It names its repo, so it does not rot, and
#          `[cli/cli#12258](...)` stays legal.
#       S4 hex colour -- `#` plus a run of [0-9A-Fa-f] of length exactly 3,
#          4, 6 or 8 that carries at least one letter, with the character
#          before the `#` and the character after the run each end of line or
#          outside [0-9A-Za-z_]. `#1a2b3c` and `#1af` stay legal; a pure-digit
#          run such as `#123456` has no letter and stays a candidate.
#   * ESCAPES -- a backslash followed by ASCII punctuation other than `#` is a
#     CommonMark backslash escape: the pair is literal text and is stepped over
#     BEFORE any safe shape is tried, so an escaped delimiter (a backtick, a
#     `]`, or a backslash) can never open S1 or S3. `#` is excluded so an
#     escaped `#` stays a candidate. Escapes are not processed inside a span
#     already consumed, matching CommonMark code spans.
#   The walk tries an escape, then S1, then S3, then S2, then S4; on a match it
#   jumps past the span, else a candidate is emitted and stepped over, else it
#   advances one character.
#
# ELIMINATED CLASS: OVER-BROAD EXEMPTION. A `#` is exempt only when a safe shape
# matches an exact span around it at the walk position. There is no deletion
# pass over the line, so no exemption can reach past its own span: a `#` glued
# to an arbitrary word (`issue#123`, `x#9`) has no shape that admits it, a
# backtick run can be closed only by a run of its own length, and escape
# processing precedes every shape, so a backslash-escaped delimiter opens no
# span. All three are unrepresentable as exemptions rather than guarded against.
#
# ELIMINATED CLASS: SILENT INPUT-SET NARROWING. Nothing ahead of the fail-closed
# layers shrinks what the check reads. The candidate rule has no right-boundary
# condition, so `#123g`, `#123_` and `_#123_` are candidates rather than silently
# dropped; the only narrowing is by a named safe shape. Discovery selects by
# NAME only, never by type, and follows symlinks, so every name-matching path
# -- a symlink, a directory named `*.md`, a dangling link, a file beneath a
# symlinked directory -- reaches the read gate, where it is read or becomes a
# finding instead of vanishing inside find.
#
# CARDINALITY. A candidate consumes only its own token and never the separator
# after it, so every reference on a line is reported, not just the first. A
# context-consuming matcher eats the separator between neighbours and misses the
# second (`x #12 #34` reports only `#12`), and that is not cosmetic here: the
# allowlist keys on (rule, path, line), so a finding that is not line-COMPLETE
# lets an allowlist entry absolve a reference no reviewer ever saw.
#
# WITNESSES, three layers, because they fail independently:
#   * the DETECTION CANARY asserts the pure predicate `tracker_ref_tokens` over
#     literal lines -- the candidate rule and each safe shape, in both
#     directions, and by EXACT token string so a dropped neighbour is caught.
#   * the SCANNER CANARY asserts `scan_prose_file_refs` over committed fixtures.
#     It is the only layer that can witness the file-level traversal: the awk
#     record shape, the line numbering, and the absence of any region skipping
#     (including an unclosed-frontmatter fixture that no predicate test reaches).
#   * the TRAVERSAL CANARY asserts that discovery, the read gate, and the awk
#     layer each return non-zero on failure instead of empty output, and that
#     discovery selects by name only and descends a symlinked directory.
#
# Discovery FAILS CLOSED PER ARM: each of the two discovery arms (`plugin/**/*.md`
# and `plugin/workflows/*.json`) carries its OWN zero-file assertion. An aggregate
# count cannot carry this guarantee -- a missing, renamed, or unreadable workflows
# tree yields zero JSON files while the markdown arm keeps the aggregate nonzero,
# so half the stated scope would vanish with the check still green. A find that
# fails, or a path stream that ends without its trailing status record, is its
# own finding. Because discovery passes no type test, every name-matching path is
# handed to the read gate: a symlink to a regular file is read through it, and a
# path that is missing (a dangling symlink), not a regular file (a directory or a
# symlink to one), or unreadable is a finding, as is a classifier that exits
# non-zero on a file -- never a clean file.
#
# Both arms discover through the shared checked-discovery engine
# (discover_checked_paths under CHECK15_DISCOVERY_GATE, see the Checked
# discovery section), which follows symlinks with -L script-wide: a symlinked
# directory under plugin/ is descended and every name-matching path beneath it
# is scanned; a dangling link is materialised and, under the `raw` gate,
# reaches CHECK 15's own read gate, where it is a finding; a symlink loop makes
# find exit non-zero, which is a CHECK15 discovery-failure finding.
#
# RESIDUALS, stated plainly:
#   * allowlist granularity is the LINE, not the token. An entry added for one
#     reference on a line would also absolve a reference added to that same line
#     later. Zero CHECK15 allowlist entries exist today, so nothing is absolved
#     in practice; closing this for real needs a token-level key in the shared
#     preload_allowlist/test_allowlisted machinery, which every check shares.
#   * bare anchor TEXT such as `(#2-slug)` written outside a `](...)` link is
#     reported as a reference. Move it into a real link or into inline code.
#   * a pure-digit hex colour (`#123456`) is reported as a tracker reference.
#     Deliberate: an unbounded digit run keeps a tracker id of any length in
#     reach, and a loud allowlistable false positive beats a silent permanent
#     false negative.
#   * a `#` glued to a word (`word#123`) and a digit-leading URL fragment
#     (`https://ex.com/p#123`) are reported, including inside a link target.
#     Neither occurs in plugin/ today; the remedy is inline code.
#   * the reported token for a reference glued to trailing word characters is
#     its `#`-plus-digits prefix only: `#123g` reports `#123`, and
#     `word#1a2b3c` (left-glued, so S4 does not apply) reports `#1`.
#   * S4 exempts ANY left- and right-bounded 3, 4, 6 or 8 hex run carrying a
#     letter, so `#12ab` is indistinguishable from a tracker id glued to letters
#     and is exempt. Bounded: a tracker id is pure digits, and a pure-digit run
#     is never S4.
#   * a symlinked directory that points back inside plugin/ materialises the
#     same file under two paths: it is scanned twice, never skipped, but an
#     allowlist entry keyed to one path does not cover the other. A symlink
#     loop is not witnessed by a committed fixture; it reports through the same
#     non-zero find status the traversal canary's nonexistent-root probe
#     witnesses.
#   * discovery coverage is split: the traversal canary's exact args and gate
#     pins witness the production CALL SITES, and its discovery probes witness
#     the production COMPOSITION (discover_checked_paths under
#     CHECK15_DISCOVERY_GATE over the shared engine). Neither alone covers both.
#   * an inline code span broken across physical lines is not recognized: each
#     line is classified alone, so a reference on either half is reported.
#   * the scanner canary pins fixture LINE NUMBERS in this file. The fixtures say
#     so in-file; edit fixture and canary together.
echo ''
echo '=== CHECK 15: No tracker references in plugin runtime prose ==='

CHECK15_CLASSIFY_AWK="$(cat <<'CHECK15_AWK'
function backtick_run_len(text, at,    run_len) {
    run_len = 0
    while (substr(text, at + run_len, 1) == "`") run_len++
    return run_len
}
function code_span_end(text, at, open_len,    scan_pos, run_len) {
    scan_pos = at + open_len
    while (scan_pos <= length(text)) {
        if (substr(text, scan_pos, 1) != "`") { scan_pos++; continue }
        run_len = backtick_run_len(text, scan_pos)
        if (run_len == open_len) return scan_pos + run_len
        scan_pos += run_len
    }
    return 0
}
function is_left_boundary(text, at) {
    return at == 1 || substr(text, at - 1, 1) !~ /[A-Za-z0-9._\/-]/
}
function is_right_boundary(text, at) {
    return substr(text, at, 1) !~ /[0-9A-Za-z_]/
}
function is_word_left_boundary(text, at) {
    return at == 1 || substr(text, at - 1, 1) !~ /[0-9A-Za-z_]/
}
function is_escape(text, at,    next_char) {
    if (substr(text, at, 1) != "\\") return 0
    next_char = substr(text, at + 1, 1)
    return next_char != "" && index("!\"$%&'()*+,-./:;<=>?@[\\]^_`{|}~", next_char) > 0
}
function hex_colour_len(text, at,    hex_len) {
    if (!is_word_left_boundary(text, at)) return 0
    if (!match(substr(text, at), /^#[0-9A-Fa-f]+/)) return 0
    hex_len = RLENGTH - 1
    if (hex_len != 3 && hex_len != 4 && hex_len != 6 && hex_len != 8) return 0
    if (substr(text, at + 1, hex_len) !~ /[A-Fa-f]/) return 0
    if (!is_right_boundary(text, at + RLENGTH)) return 0
    return RLENGTH
}
{
    sub(/\r$/, "")
    if (index($0, "#") == 0) next
    line_text = $0
    line_len = length(line_text)
    found_tokens = ""
    token_sep = ""
    pos = 1
    while (pos <= line_len) {
        cur_char = substr(line_text, pos, 1)
        if (is_escape(line_text, pos)) {
            pos += 2
            continue
        }
        if (cur_char == "`") {
            open_len = backtick_run_len(line_text, pos)
            span_end = code_span_end(line_text, pos, open_len)
            pos = span_end ? span_end : pos + open_len
            continue
        }
        if (cur_char == "]" && match(substr(line_text, pos), /^\]\(#[^)]*\)/)) {
            pos += RLENGTH
            continue
        }
        if (is_left_boundary(line_text, pos) && match(substr(line_text, pos), /^[A-Za-z0-9][A-Za-z0-9._-]*\/[A-Za-z0-9][A-Za-z0-9._-]*#[0-9]+/) && is_right_boundary(line_text, pos + RLENGTH)) {
            pos += RLENGTH
            continue
        }
        if (cur_char == "#") {
            colour_len = hex_colour_len(line_text, pos)
            if (colour_len) {
                pos += colour_len
                continue
            }
        }
        if (cur_char == "#" && match(substr(line_text, pos + 1), /^[0-9]+/)) {
            found_tokens = found_tokens token_sep "#" substr(line_text, pos + 1, RLENGTH)
            token_sep = " "
            pos += 1 + RLENGTH
            continue
        }
        pos++
    }
    if (found_tokens != "") print NR "\t" found_tokens
}
CHECK15_AWK
)"

check15_found=false
check15_file_count=0

# tracker_ref_tokens TEXTLINE
# Prints EVERY bare tracker reference in TEXTLINE, space-separated in source
# order, or nothing when the line carries none. PURE -- no findings, no globals;
# exits non-zero only when the classifier itself fails -- so the detection
# canary below can assert the guard's semantics directly rather than merely
# asserting that the guard exists.
tracker_ref_tokens() {
    local textline="$1" record
    # Cheap gate: the overwhelming majority of prose lines carry no `#` at all,
    # so the classifier fork is only paid for candidates.
    case "$textline" in
        *'#'*) ;;
        *) return 0 ;;
    esac
    record="$(printf '%s\n' "$textline" | awk "$CHECK15_CLASSIFY_AWK")" || return
    printf '%s' "${record#*$'\t'}"
}

# Status codes the read layer returns for its own failures, distinct from each
# other and from the 0/1/2 that awk exits with. Discovery status is the shared
# checked-discovery engine's (see the Checked discovery section).
CHECK15_RC_NOT_REGULAR=10
CHECK15_RC_UNREADABLE=11

# check15_awk_records FILE
# Runs the classifier over FILE, ungated, and returns awk's own exit status.
# The traversal canary witnesses that this status is propagated, not swallowed.
check15_awk_records() {
    awk "$CHECK15_CLASSIFY_AWK" "$1"
}

# check15_read_records FILE
# Prints the classifier records for FILE. Returns CHECK15_RC_NOT_REGULAR when
# FILE is missing or not a regular file, CHECK15_RC_UNREADABLE when it cannot
# be read, and awk's non-zero status when the classifier fails -- never 0 with
# empty output for a file it did not actually read.
check15_read_records() {
    local prose_file="$1" records
    # INVARIANT: the -f gate is load-bearing, not redundant with awk's own
    # error handling -- gawk (and nawk) exit 0 with ZERO records when handed a
    # directory, which would read as a clean file.
    if [[ ! -f "$prose_file" ]]; then
        return "$CHECK15_RC_NOT_REGULAR"
    fi
    if [[ ! -r "$prose_file" ]]; then
        return "$CHECK15_RC_UNREADABLE"
    fi
    records="$(check15_awk_records "$prose_file")" || return
    if [[ -n "$records" ]]; then
        printf '%s\n' "$records"
    fi
}

# scan_prose_file_refs FILE
# Prints one record per offending line, `LINENO<TAB>tok1 tok2 ...`, in file
# order. No findings, no globals; STATUS-BEARING -- non-zero when FILE is not a
# regular file, is unreadable, or the classifier fails (see check15_read_records)
# -- so the scanner canary below can assert the file-level traversal (record
# shape, line numbering, and the absence of any region skipping) over committed
# fixtures, and a caller can never mistake an unread file for a clean one.
scan_prose_file_refs() {
    check15_read_records "$1"
}

# scan_file_for_tracker_refs FILE
# Thin reporting wrapper: turns each record from scan_prose_file_refs into a
# CHECK15 finding, and any read or classifier failure into a finding of its
# own. Carries no detection logic of its own.
scan_file_for_tracker_refs() {
    local prose_file="$1"
    local line_num tokens records failure_reason scan_rc=0
    records="$(scan_prose_file_refs "$prose_file")" || scan_rc=$?
    if [[ "$scan_rc" -ne 0 ]]; then
        case "$scan_rc" in
            "$CHECK15_RC_NOT_REGULAR") failure_reason='is missing or is not a regular file' ;;
            "$CHECK15_RC_UNREADABLE") failure_reason='is not readable' ;;
            *) failure_reason="made the CHECK15_CLASSIFY_AWK classifier exit ${scan_rc}" ;;
        esac
        check15_found=true
        add_finding 'CHECK15' "$prose_file" 0 \
            "this runtime prose file ${failure_reason}, so none of it was scanned for tracker references -- fix the file or the classifier; an unreadable runtime-prose file is NOT clean"
        return 0
    fi
    if [[ -z "$records" ]]; then
        return 0
    fi
    while IFS=$'\t' read -r line_num tokens; do
        check15_found=true
        add_finding 'CHECK15' "$prose_file" "$line_num" \
            "tracker reference(s) ${tokens} in plugin runtime prose -- cite a durable anchor (ADR, named invariant, or a present-tense description of the rule), never an issue or PR number; every reference on the line is listed because an allowlist entry covers the whole line, not one token"
    done <<< "$records"
}

# INVARIANT: discovery selects by NAME only, never by type: every name-matching
# path reaches the read gate, where a path that is missing or not a regular file becomes a
# finding instead of being dropped silently by find. The traversal canary pins
# these arrays literally.
CHECK15_MD_FIND_ARGS=(-name '*.md')
CHECK15_JSON_FIND_ARGS=(-maxdepth 1 -name '*.json')

# INVARIANT: both arms discover under the `raw` gate. check15_read_records is
# CHECK 15's type gate; a `files` gate ahead of it would reject a directory or
# dangling link before the read gate, leaving the traversal canary's read-gate
# probes guarding a path production never reaches. The traversal canary pins
# this value and runs its discovery probes under it.
CHECK15_DISCOVERY_GATE='raw'

declare -a check15_md_files=()
discover_checked_paths 'CHECK15' check15_md_files "$CHECK15_DISCOVERY_GATE" 'plugin/**/*.md' "$PLUGIN_ROOT" -- "${CHECK15_MD_FIND_ARGS[@]}" || check15_found=true
check15_md_count="${#check15_md_files[@]}"
for prose_file in "${check15_md_files[@]}"; do
    scan_file_for_tracker_refs "$prose_file"
done

declare -a check15_json_files=()
discover_checked_paths 'CHECK15' check15_json_files "$CHECK15_DISCOVERY_GATE" 'plugin/workflows/*.json' "$PLUGIN_ROOT/workflows" -- "${CHECK15_JSON_FIND_ARGS[@]}" || check15_found=true
check15_json_count="${#check15_json_files[@]}"
for prose_file in "${check15_json_files[@]}"; do
    scan_file_for_tracker_refs "$prose_file"
done

check15_file_count=$((check15_md_count + check15_json_count))

# Per-arm fail-closed. Each arm's tree is non-empty by construction, so a zero
# count means that arm was moved, renamed, or is unreadable -- and a per-arm
# assertion is the only shape that catches it: an aggregate count stays nonzero
# while one arm silently contributes nothing.
if [[ "$check15_md_count" -eq 0 ]]; then
    check15_found=true
    add_finding 'CHECK15' "$PLUGIN_ROOT" 0 \
        "Tracker-reference discovery found ZERO plugin/**/*.md runtime prose files, which disarms half this check; restore the payload tree or retire the check deliberately"
fi

if [[ "$check15_json_count" -eq 0 ]]; then
    check15_found=true
    add_finding 'CHECK15' "$PLUGIN_ROOT/workflows" 0 \
        "Tracker-reference discovery found ZERO plugin/workflows/*.json runtime definitions, which disarms half this check; restore the workflow-definition tree or retire the check deliberately"
fi

# ── CHECK 15 DETECTION CANARY ──────────────────────────────────────────────
# The candidate rule and each safe shape, in BOTH directions, plus exact-token
# cases that pin CARDINALITY. A narrowed candidate rule, a widened or dropped
# safe shape, or a walk that stops after the first token turns this run red
# where the presence-pinning safety fixture would stay green.

# check15_flag_classifier_failure LINE
# Records a canary finding for a classifier that exited non-zero on LINE, so a
# broken CHECK15_CLASSIFY_AWK program is loud rather than read as "no tokens".
check15_flag_classifier_failure() {
    check15_found=true
    add_finding 'CHECK15' 'tools/policy_check.sh' 0 \
        "detection canary: the CHECK15_CLASSIFY_AWK classifier exited non-zero on \"$1\" -- the program no longer runs under this awk, so the guard classifies nothing"
}

check15_expect_hit() {
    local got
    if ! got="$(tracker_ref_tokens "$1")"; then
        check15_flag_classifier_failure "$1"
        return 0
    fi
    if [[ -z "$got" ]]; then
        check15_found=true
        add_finding 'CHECK15' 'tools/policy_check.sh' 0 \
            "detection canary: no tracker reference detected in \"$1\" -- the CHECK15_CLASSIFY_AWK candidate rule has been narrowed, or a safe shape now admits a real reference, and the guard no longer catches the class it claims to ban"
    fi
}

check15_expect_miss() {
    local hit
    if ! hit="$(tracker_ref_tokens "$1")"; then
        check15_flag_classifier_failure "$1"
        return 0
    fi
    if [[ -n "$hit" ]]; then
        check15_found=true
        add_finding 'CHECK15' 'tools/policy_check.sh' 0 \
            "detection canary: exempt construct \"$1\" was flagged as tracker reference '${hit}' -- a CHECK15_CLASSIFY_AWK safe shape has been dropped or the candidate rule widened, and the guard now fires on legal prose"
    fi
}

# check15_expect_tokens LINE EXPECTED
# Exact-string assertion on the FULL token list. expect_hit only proves that
# something was found; only this shape catches a matcher that reports the first
# reference on a line and silently drops its neighbours.
check15_expect_tokens() {
    local got
    if ! got="$(tracker_ref_tokens "$1")"; then
        check15_flag_classifier_failure "$1"
        return 0
    fi
    if [[ "$got" != "$2" ]]; then
        check15_found=true
        add_finding 'CHECK15' 'tools/policy_check.sh' 0 \
            "detection canary: line \"$1\" yielded tokens '${got}' but expected '${2}' -- the CHECK15_CLASSIFY_AWK walk no longer reports every reference on a line, and a line-keyed allowlist entry would then absolve the references it drops"
    fi
}

check15_expect_hit 'see #123 for the rationale'
check15_expect_hit 'tracked as #7.'
check15_expect_hit '(#42) covers the remainder'
check15_expect_hit '#5 is the earliest'
check15_expect_hit 'superseded by #123456'
check15_expect_hit 'superseded by #1000000'
check15_expect_hit 'issue#123 stays flagged'
check15_expect_hit 'PR#456 stays flagged'
check15_expect_hit 'x#9 glued'
check15_expect_hit 'an unclosed ``#123 double run'
check15_expect_hit 'an unclosed ```#123 triple run'
check15_expect_hit 'host path example.com/a/b#12'
check15_expect_hit 'a mismatched ``#123` run'
# Escapes: an escaped delimiter opens no safe shape, and an escaped `#` stays a candidate.
check15_expect_hit '\``#123`` escaped opener'
check15_expect_hit '\](#123) escaped bracket'
check15_expect_hit '\#123 escaped hash'

check15_expect_miss '# Heading'
check15_expect_miss '## Subheading'
check15_expect_miss '#!/usr/bin/env bash'
check15_expect_miss 'cross-repo citation cli/cli#12258 names its repo'
check15_expect_miss 'see [the anchor](#section-2) above'
check15_expect_miss 'the literal placeholder `#123` inside inline code'
# S4 hex colour: a left- and right-bounded 3, 4, 6 or 8 hex run carrying a letter.
check15_expect_miss 'the colour #1a2b3c is letter-bearing'
check15_expect_miss 'the colour #1af is short'
check15_expect_miss 'the colour #1af8 carries alpha'
check15_expect_miss 'the colour #1a2b3c4d carries alpha'
check15_expect_miss 'no hash here at all'
check15_expect_miss 'the ``#123`` double run'
check15_expect_miss 'the ```#123``` triple run'
check15_expect_miss 'see [the section](#2-section) above'
check15_expect_miss '[cli/cli#12258](https://github.com/cli/cli/pull/12258)'
# An escaped backslash escapes nothing after it, so the backtick run still opens S1.
check15_expect_miss '\\``#123`` escaped backslash'

check15_expect_tokens 'see #123 for context' '#123'
check15_expect_tokens 'tracked as #7.' '#7'
check15_expect_tokens '(#42) noted' '#42'
check15_expect_tokens '#5 first' '#5'
check15_expect_tokens 'superseded by #123456' '#123456'
check15_expect_tokens 'superseded by #1000000' '#1000000'
check15_expect_tokens 'x #12 #34' '#12 #34'
check15_expect_tokens '#12 #34' '#12 #34'
check15_expect_tokens 'a #12, #34.' '#12 #34'
check15_expect_tokens "$(printf 'tracked as #7.\r')" '#7'
check15_expect_tokens 'issue#123 stays flagged' '#123'
check15_expect_tokens 'PR#456 stays flagged' '#456'
check15_expect_tokens 'x#9 glued' '#9'
check15_expect_tokens '``code`` and #123' '#123'
check15_expect_tokens 'bare (#2-slug) text' '#2'
check15_expect_tokens 'cli/cli#1 and issue#2 and `#3` and #4' '#2 #4'
check15_expect_tokens 'host path example.com/a/b#12' '#12'
check15_expect_tokens 'a mismatched ``#123` run' '#123'
check15_expect_tokens 'see #123_ underscore' '#123'
check15_expect_tokens '_#123_' '#123'
check15_expect_tokens '__#123__' '#123'
check15_expect_tokens 'see #123g letter' '#123'
check15_expect_tokens '#12ab5' '#12'
check15_expect_tokens 'glued word#1a2b3c' '#1'
check15_expect_tokens '#1a2b3c_' '#1'
check15_expect_tokens '#12345678' '#12345678'
check15_expect_tokens '#1234' '#1234'
check15_expect_tokens '#12g #34' '#12 #34'
check15_expect_tokens 'colour #1a2b3c then ref #45' '#45'
check15_expect_tokens '\``#123`` escaped opener' '#123'
check15_expect_tokens '\#12 and \`#34`' '#12 #34'
# A backslash inside a code span is literal, so it cannot extend the span.
check15_expect_tokens '`a\` #5 `' '#5'

# ── CHECK 15 SCANNER CANARY ────────────────────────────────────────────────
# The detection canary above witnesses the PREDICATE. This layer witnesses the
# FILE-LEVEL TRAVERSAL -- awk record shape, line numbering, and the absence of
# any region skipping -- by running scan_prose_file_refs over committed fixtures
# whose expected records (including their LINE NUMBERS) are pinned right here.
# A reintroduced frontmatter skip, an off-by-one in the record, or a deleted
# fixture reference turns this red; no predicate test can see any of those.
check15_expect_scan() {
    local fixture_rel="$1" expected="$2"
    local fixture_path got got_flat expected_flat scan_rc=0
    fixture_path="$REPO_ROOT/$fixture_rel"
    if [[ ! -f "$fixture_path" ]]; then
        check15_found=true
        add_finding 'CHECK15' 'tools/policy_check.sh' 0 \
            "scanner canary: fixture ${fixture_rel} is missing -- the file-level traversal has no witness, so a reintroduced region skip or an off-by-one line number could ship unseen; restore the fixture rather than deleting the assertion"
        return 0
    fi
    got="$(scan_prose_file_refs "$fixture_path")" || scan_rc=$?
    if [[ "$scan_rc" -ne 0 ]]; then
        check15_found=true
        add_finding 'CHECK15' 'tools/policy_check.sh' 0 \
            "scanner canary: scan_prose_file_refs exited ${scan_rc} on ${fixture_rel} -- the file-level traversal did not run, so its records cannot be trusted"
        return 0
    fi
    if [[ "$got" != "$expected" ]]; then
        got_flat="${got//$'\n'/ | }"
        expected_flat="${expected//$'\n'/ | }"
        check15_found=true
        add_finding 'CHECK15' 'tools/policy_check.sh' 0 \
            "scanner canary: scanning ${fixture_rel} produced records [${got_flat}] but expected [${expected_flat}] -- the file-level traversal changed shape (a skipped region, a renumbered line, or a dropped token); fix the scanner, or update fixture and pinned records together if the fixture moved"
    fi
}

check15_expect_scan 'tests/policy/fixtures/tracker-ref-scan-canary.md' \
    $'3\t#11\n13\t#21\n16\t#31\n20\t#41\n22\t#12 #34 #56'
check15_expect_scan 'tests/policy/fixtures/tracker-ref-unclosed-frontmatter.md' \
    $'10\t#77'
check15_expect_scan 'tests/policy/fixtures/tracker-ref-allowlist-canary.md' \
    $'9\t#123\n11\t#456\n13\t#9\n19\t#123\n21\t#123\n23\t#123\n27\t#2\n29\t#2 #4\n31\t#12\n37\t#123\n39\t#123\n41\t#123\n45\t#1\n47\t#1\n49\t#12345678'

# ── CHECK 15 TRAVERSAL CANARY ──────────────────────────────────────────────
# Witnesses that each traversal layer FAILS CLOSED: a failed discovery, a
# missing path, a directory, and a failing awk must each surface as a non-zero
# status rather than as empty output that reads as a clean file. A positive
# control proves the read layer still returns records for a real fixture, so
# the failure arms cannot all pass by the layer failing unconditionally. Each
# probe runs under `if !` so set -euo pipefail cannot abort the run; stderr is
# discarded only here, because these failures are the expected outcome.
# Discovery coverage is split across two witnesses: the args and gate pins
# below witness the production CALL SITES (their arrays select by name only,
# under the `raw` gate), and the discovery probes witness the production
# COMPOSITION -- discover_checked_paths under CHECK15_DISCOVERY_GATE, over the
# shared discover_paths engine:
#   * a nonexistent root makes it return non-zero and emit a CHECK15
#     find-failure finding, run inside a command substitution so the finding is
#     captured as text and dies with the subshell;
#   * a name-matching committed symlink is materialised; a raw `find -P` with
#     `-type f` drops it -- the negative control proving that fixture is still
#     a symlink rather than a plain file;
#   * over the DISCOVERY canary root, CHECK15_MD_FIND_ARGS materialise the file
#     under a symlinked directory (the -L policy) and a dangling link (name-only
#     selection plus the raw gate hand it to the read gate); the same probe with
#     `-type f` appended drops only the dangling link -- the negative control.
# Every fixture is committed, so no probe creates a filesystem object at run
# time.
# Residual: the reporting wrapper's finding emission on a read failure has no
# canary -- asserting it would emit a real finding -- and it is a thin
# translation of the status-bearing layer these probes do witness.

# check15_flag_traversal_canary DESCRIPTION
# Records a traversal-canary finding for a probe whose status came back wrong.
check15_flag_traversal_canary() {
    check15_found=true
    add_finding 'CHECK15' 'tools/policy_check.sh' 0 \
        "traversal canary: $1 -- a traversal layer now fails open, so a missing, unreadable, or undiscoverable runtime-prose file would be reported clean"
}

check15_canary_missing_path="$REPO_ROOT/tests/policy/fixtures/__check15_nonexistent__"
check15_canary_dir_path="$REPO_ROOT/tests/policy/fixtures"
check15_canary_fixture_path="$REPO_ROOT/tests/policy/fixtures/tracker-ref-scan-canary.md"
check15_canary_symlink_name='tracker-ref-symlink-canary.md'
check15_canary_symlink_path="$REPO_ROOT/tests/policy/fixtures/$check15_canary_symlink_name"

# check15_expect_find_args ARRAY_NAME EXPECTED ARGS...
# Exact-string pin of one production discovery args array, joined by single
# spaces. Any drift -- a re-added `-type f` above all -- is a canary finding.
check15_expect_find_args() {
    local array_name="$1" expected_args="$2" IFS=' '
    shift 2
    if [[ "$*" != "$expected_args" ]]; then
        check15_flag_traversal_canary "${array_name} is '$*' but must be exactly '${expected_args}' -- discovery selects by NAME only, never by type, so every name-matching path reaches the read gate"
    fi
}

check15_expect_find_args 'CHECK15_MD_FIND_ARGS' '-name *.md' "${CHECK15_MD_FIND_ARGS[@]}"
check15_expect_find_args 'CHECK15_JSON_FIND_ARGS' '-maxdepth 1 -name *.json' "${CHECK15_JSON_FIND_ARGS[@]}"
if [[ "$CHECK15_DISCOVERY_GATE" != 'raw' ]]; then
    check15_flag_traversal_canary "CHECK15_DISCOVERY_GATE is '${CHECK15_DISCOVERY_GATE}' but must be exactly 'raw' -- check15_read_records is the type gate, so a discovery gate ahead of it rejects a directory or dangling link before the read gate ever sees it"
fi

# probe_check15_missing_root_discovery
# Prints the findings the production discovery composition emits over the
# nonexistent canary root, then `rc=STATUS`. Called only inside a command
# substitution, so the finding stays in the subshell.
probe_check15_missing_root_discovery() {
    local -a check15_canary_missing_paths=()
    local check15_canary_missing_rc=0
    discover_checked_paths 'CHECK15' check15_canary_missing_paths "$CHECK15_DISCOVERY_GATE" 'the traversal canary nonexistent root' "$check15_canary_missing_path" -- "${CHECK15_MD_FIND_ARGS[@]}" 2>/dev/null || check15_canary_missing_rc=$?
    printf 'rc=%d\n' "$check15_canary_missing_rc"
}

check15_canary_missing_output="$(probe_check15_missing_root_discovery)"
check15_canary_missing_rel="${check15_canary_missing_path#"$REPO_ROOT"/}"
if [[ "$check15_canary_missing_output" != *'rc=1' \
   || "$check15_canary_missing_output" != *"[CHECK15] ${check15_canary_missing_rel} -- Discovery of the traversal canary nonexistent root failed: find exited "* ]]; then
    check15_flag_traversal_canary "discover_checked_paths over the nonexistent root ${check15_canary_missing_path} produced [${check15_canary_missing_output//$'\n'/ | }], expected rc=1 and a CHECK15 finding that find exited non-zero, so a failing find is read as an empty tree"
fi
if check15_read_records "$check15_canary_missing_path" >/dev/null 2>&1; then
    check15_flag_traversal_canary "check15_read_records returned 0 for the nonexistent path ${check15_canary_missing_path}"
fi
if check15_read_records "$check15_canary_dir_path" >/dev/null 2>&1; then
    check15_flag_traversal_canary "check15_read_records returned 0 for the directory ${check15_canary_dir_path}, so the regular-file gate is gone and awk's zero-record directory skip reads as clean"
fi
if check15_awk_records "$check15_canary_missing_path" >/dev/null 2>&1; then
    check15_flag_traversal_canary "check15_awk_records returned 0 for the nonexistent path ${check15_canary_missing_path}, so awk's own failure status is being swallowed"
fi
if ! check15_canary_records="$(check15_read_records "$check15_canary_fixture_path")"; then
    check15_flag_traversal_canary "positive control: check15_read_records failed on the committed fixture ${check15_canary_fixture_path}"
elif [[ -z "$check15_canary_records" ]]; then
    check15_flag_traversal_canary "positive control: check15_read_records returned no records for the committed fixture ${check15_canary_fixture_path}, which carries known references"
fi
declare -a check15_canary_paths=()
check15_canary_discovery_rc=0
discover_checked_paths 'CHECK15' check15_canary_paths "$CHECK15_DISCOVERY_GATE" 'the committed symlink canary' "$REPO_ROOT/tests/policy/fixtures" -- -maxdepth 1 -name "$check15_canary_symlink_name" || check15_canary_discovery_rc=$?
if [[ "$check15_canary_discovery_rc" -ne 0 || "${#check15_canary_paths[@]}" -ne 1 ]]; then
    check15_flag_traversal_canary "discover_checked_paths materialised ${#check15_canary_paths[@]} path(s) with status ${check15_canary_discovery_rc} for the committed symlink ${check15_canary_symlink_path}, expected exactly 1 with status 0, so discovery drops a name-matching path before the read gate"
fi
# INTENTIONAL NON-HELPER FIND: run with an explicit -P as the negative control
# for the committed-symlink probe above (under -L, `-type f` matches a symlink
# to a regular file, so no helper call can drop it); it is not a discovery call
# site and must never be migrated to discover_paths.
check15_canary_raw_rc=0
check15_canary_raw_listing="$(find -P "$REPO_ROOT/tests/policy/fixtures" -maxdepth 1 -name "$check15_canary_symlink_name" -type f -print)" || check15_canary_raw_rc=$?
if [[ "$check15_canary_raw_rc" -ne 0 || -n "$check15_canary_raw_listing" ]]; then
    check15_flag_traversal_canary "negative control: find -P with -type f listed [${check15_canary_raw_listing//$'\n'/ | }] with status ${check15_canary_raw_rc} for the committed symlink ${check15_canary_symlink_path}, expected nothing with status 0, so that fixture is no longer a symlink and the probe above no longer exercises a symlinked runtime-prose file"
fi

# expect_check15_canary_tree_discovery LABEL EXPECTED_TOTAL EXPECT_DANGLING FIND_ARGS...
# Asserts the production composition over the DISCOVERY canary root returns 0
# and materialises exactly EXPECTED_TOTAL paths, always including the file
# under the symlinked directory, and the dangling link iff EXPECT_DANGLING.
expect_check15_canary_tree_discovery() {
    local probe_label="$1" expected_total="$2" expect_dangling="$3"
    shift 3
    local -a check15_tree_paths=()
    local check15_tree_rc=0 check15_tree_path saw_linked=false saw_dangling=false
    discover_checked_paths 'CHECK15' check15_tree_paths "$CHECK15_DISCOVERY_GATE" 'the DISCOVERY canary tree' "$dcanary_root" -- "$@" || check15_tree_rc=$?
    for check15_tree_path in "${check15_tree_paths[@]}"; do
        if [[ "$check15_tree_path" == "$dcanary_linked_file" ]]; then
            saw_linked=true
        elif [[ "$check15_tree_path" == "$dcanary_dangling_file" ]]; then
            saw_dangling=true
        fi
    done
    if [[ "$check15_tree_rc" -ne 0 || "${#check15_tree_paths[@]}" -ne "$expected_total" \
       || "$saw_linked" != true || "$saw_dangling" != "$expect_dangling" ]]; then
        check15_flag_traversal_canary "${probe_label}: discover_checked_paths over ${DISCOVERY_CANARY_REL} with '$*' returned ${check15_tree_rc} and materialised ${#check15_tree_paths[@]} path(s) [${check15_tree_paths[*]}], expected status 0 and exactly ${expected_total} including tree/link-dir/inner.md, with broken/dangling.md present=${expect_dangling} -- CHECK 15 discovery no longer follows a symlinked directory, or no longer hands a dangling link to the read gate"
    fi
}

expect_check15_canary_tree_discovery 'symlinked-directory and dangling-link probe' 3 true "${CHECK15_MD_FIND_ARGS[@]}"
expect_check15_canary_tree_discovery 'negative control' 2 false "${CHECK15_MD_FIND_ARGS[@]}" -type f
check15_canary_symlink_rc=0
check15_canary_symlink_records="$(check15_read_records "$check15_canary_symlink_path")" || check15_canary_symlink_rc=$?
if [[ "$check15_canary_symlink_rc" -ne 0 || "$check15_canary_symlink_records" != $'10\t#77' ]]; then
    check15_flag_traversal_canary "check15_read_records returned status ${check15_canary_symlink_rc} and records [${check15_canary_symlink_records}] for the committed symlink ${check15_canary_symlink_path}, expected status 0 and the pinned records of its target, so a symlinked runtime-prose file is not read through"
fi

if [[ "$check15_found" == false ]]; then
    echo "[PASS] Check 15: No tracker references in $check15_file_count plugin runtime prose files"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'CHECK15'

# ── SAFETY REGRESSION TESTS ────────────────────────────────────────────────

echo ''
echo '=== SAFETY: Regression fixture tests ==='

SAFETY_DIR="$REPO_ROOT/tests/policy"
declare -a SAFETY_FIXTURES=()
SAFETY_DISCOVERY_FAILED=false
# REQUIRED root: classify it with the status-bearing `dirs` gate rather than a
# bare `-d` pre-guard. A `-d` test that simply skips the discovery makes a
# missing or non-directory root a silent green run over an empty fixture set --
# the exact input-set narrowing ahead of the fail-closed layer this engine
# exists to prevent.
SAFETY_DIR_RC=0
discovery_gate_status "$SAFETY_DIR" dirs || SAFETY_DIR_RC=$?
if [[ "$SAFETY_DIR_RC" -ne 0 ]]; then
    SAFETY_DISCOVERY_FAILED=true
    flag_discovery_gate 'SAFETY' "$SAFETY_DIR" "$SAFETY_DIR_RC"
else
    discover_checked_paths 'SAFETY' SAFETY_FIXTURES files 'safety-*.json fixture files' "$SAFETY_DIR" -- -maxdepth 1 -name 'safety-*.json' || SAFETY_DISCOVERY_FAILED=true
fi

SAFETY_PASSED=0
SAFETY_FAILED=0
if [[ "$SAFETY_DISCOVERY_FAILED" == true ]]; then
    echo '[FAIL] SAFETY: safety-*.json fixture discovery'
    SAFETY_FAILED=$((SAFETY_FAILED + 1))
fi

test_set_check() {
    local rule_name="$1"
    local set_check_json="$2"
    local passed=true

    if ! command -v perl > /dev/null 2>&1; then
        add_finding 'SAFETY' '<fixture>' 0 \
            "[$rule_name] set_check requires perl (REQUIRED dependency: it is the only regex engine set_check compiles and extracts with) and perl was not found on PATH"
        TEST_SET_CHECK_RESULT="false"
        return
    fi

    local regex_text
    regex_text="$(echo "$set_check_json" | jq -r '.extract_regex // empty')"
    if [[ -z "$regex_text" ]]; then
        add_finding 'SAFETY' '<fixture>' 0 \
            "[$rule_name] set_check.extract_regex is required"
        TEST_SET_CHECK_RESULT="false"
        return
    fi

    # The compile oracle is the extraction engine itself: the regex reaches
    # perl as DATA through the environment and is compiled with qr//, exactly
    # as the extractor below compiles it.
    if ! RE="$regex_text" perl -e 'qr/$ENV{RE}/' 2>/dev/null; then
        add_finding 'SAFETY' '<fixture>' 0 \
            "[$rule_name] set_check.extract_regex did not compile"
        TEST_SET_CHECK_RESULT="false"
        return
    fi

    # Independent capture-group validation: the compile oracle above only
    # proves the regex compiles -- it says nothing about whether the regex
    # captures a group. A capture-free regex that matches ZERO times in the
    # extraction loop below never runs the `defined($1) or die` guard (the
    # while-loop body never executes), so it would otherwise vacuously pass as
    # a legitimate empty-capture zero-match result. Count the regex's own
    # capture groups independently of whether it matches anything: wrap it in
    # a synthetic always-matching alternation `(?:$re)|(?:)` against the empty
    # string. Perl populates @+ with one slot per capture group defined
    # ANYWHERE in the pattern (participating or not), regardless of which
    # alternation branch actually matched, so `scalar(@+) - 1` reports the
    # true group count without requiring the regex to match real content.
    if ! RE="$regex_text" perl -e '
        my $re = qr/$ENV{RE}/;
        "" =~ /(?:$re)|(?:)/;
        exit(scalar(@+) - 1 > 0 ? 0 : 1);
    ' 2>/dev/null; then
        add_finding 'SAFETY' '<fixture>' 0 \
            "[$rule_name] set_check.extract_regex has no capture group -- a capture-free regex that matches nothing would vacuously pass as an empty result"
        TEST_SET_CHECK_RESULT="false"
        return
    fi

    # Build expected set
    local expected_json
    expected_json="$(echo "$set_check_json" | jq -r '.expected_set // []')"

    # Expected-set values preloaded once (#305): the per-value jq spawns in
    # the extras/missing scans below become pure-bash array membership.
    local -a expected_vals=()
    local expected_val expected_stream
    expected_stream="$(jq -j "$JQ_NOSEP_DEF"'.[] | nosep, "\u001f"' <<< "$expected_json")"
    while IFS= read -r -d $'\x1f' expected_val; do
        expected_vals+=("$expected_val")
    done <<< "$expected_stream"

    # Process each file entry (path/mode streamed in one jq pass; #305)
    local rel_path mode abs_path files_stream
    files_stream="$(jq -j "$JQ_NOSEP_DEF"'(.files // [])[]
        | (.path|nosep), "\u001f", ((.mode // "equal")|nosep), "\u001f"' \
        <<< "$set_check_json")"
    while IFS= read -r -d $'\x1f' rel_path \
       && IFS= read -r -d $'\x1f' mode; do
        abs_path="$(resolve_repo_path "$rel_path")"

        if [[ ! -f "$abs_path" ]]; then
            passed=false
            add_finding 'SAFETY' "$rel_path" 0 \
                "[$rule_name] set_check file missing: $rel_path"
            continue
        fi

        local content
        content="$(<"$abs_path")"

        # Extract capture group 1 of every match, line by line. The regex is
        # passed to perl as DATA (the RE environment variable) and compiled
        # with qr//, never spliced into program source, so a `/` in the regex
        # cannot break the program. A match with no group-1 capture dies: a
        # regex that cannot capture is a broken extraction, not zero matches.
        # perl prints a trailing \x1f record mark so the command substitution
        # cannot strip a final empty capture; the mark is removed below.
        # INVARIANT: the capture must never swallow the extractor's status. It
        # is read into extract_rc and tested explicitly; the `|| extract_rc=$?`
        # form also suppresses errexit for this one command only. Rewriting it
        # as `|| extract_out=''` (or defaulting an empty result to '{}') makes
        # a failed extraction indistinguishable from a real zero-match result
        # and lets a zero-count subset fixture pass vacuously.
        local extract_out extract_rc jq_rc captured_json
        extract_rc=0
        extract_out="$(RE="$regex_text" perl -ne 'BEGIN { $re = qr/$ENV{RE}/ } while (/$re/g) { defined($1) or die "no capture group\n"; print "$1\n" } END { print "\x1f" }' <<< "$content" 2>/dev/null)" || extract_rc=$?
        if [[ "$extract_rc" -ne 0 ]]; then
            passed=false
            add_finding 'SAFETY' "$rel_path" 0 \
                "[$rule_name] set_check extraction FAILED for ${rel_path} (perl rc=$extract_rc): the extract_regex did not compile or matched without a group-1 capture -- a broken extraction is not a zero-match result"
            continue
        fi
        extract_out="${extract_out%$'\x1f'}"

        jq_rc=0
        captured_json="$(printf '%s' "$extract_out" | jq -R . | jq -s 'group_by(.) | map({key: .[0], value: length}) | from_entries')" || jq_rc=$?
        if [[ "$jq_rc" -ne 0 || -z "$captured_json" ]]; then
            passed=false
            add_finding 'SAFETY' "$rel_path" 0 \
                "[$rule_name] set_check capture aggregation FAILED for ${rel_path} (jq rc=$jq_rc): no capture object was produced"
            continue
        fi

        local captured_set
        captured_set="$(echo "$captured_json" | jq -r 'keys[]' 2>/dev/null || true)"

        # Compute extras (captured \ expected) and missing (expected \ captured)
        local extras=""
        local missing=""
        local val_in_expected
        while IFS= read -r val; do
            [[ -z "$val" ]] && continue
            # Pure-bash membership over the preloaded expected set (#305).
            val_in_expected=false
            for expected_val in "${expected_vals[@]}"; do
                if [[ "$expected_val" == "$val" ]]; then
                    val_in_expected=true
                    break
                fi
            done
            if [[ "$val_in_expected" == false ]]; then
                if [[ -n "$extras" ]]; then extras="$extras, $val"; else extras="$val"; fi
            fi
        done <<< "$captured_set"

        local exp_val
        for exp_val in "${expected_vals[@]}"; do
            if ! grep -qxF "$exp_val" <<< "$captured_set"; then
                if [[ -n "$missing" ]]; then missing="$missing, $exp_val"; else missing="$exp_val"; fi
            fi
        done

        case "$mode" in
            equal)
                if [[ -n "$extras" || -n "$missing" ]]; then
                    passed=false
                    local detail=""
                    if [[ -n "$missing" ]]; then detail="missing: $missing"; fi
                    if [[ -n "$extras" ]]; then
                        if [[ -n "$detail" ]]; then detail="$detail; "; fi
                        detail="${detail}extras: $extras"
                    fi
                    add_finding 'SAFETY' "$rel_path" 0 \
                        "[$rule_name] set_check (equal) failed for ${rel_path}: $detail"
                fi
                ;;
            subset)
                if [[ -n "$extras" ]]; then
                    passed=false
                    add_finding 'SAFETY' "$rel_path" 0 \
                        "[$rule_name] set_check (subset) failed for ${rel_path}: extras: $extras"
                fi
                ;;
            superset)
                if [[ -n "$missing" ]]; then
                    passed=false
                    add_finding 'SAFETY' "$rel_path" 0 \
                        "[$rule_name] set_check (superset) failed for ${rel_path}: missing: $missing"
                fi
                ;;
            *)
                passed=false
                add_finding 'SAFETY' "$rel_path" 0 \
                    "[$rule_name] set_check unknown mode '$mode' (expected equal|subset|superset)"
                ;;
        esac

        # Optional per-element occurrence-count assertion (one jq pass per
        # file entry; #305). sort_by(.key) preserves the former keys[]
        # iteration order.
        local count_key want got counts_stream
        counts_stream="$(jq -j --argjson captured "$captured_json" \
            "$JQ_NOSEP_DEF"'(.expected_counts // {}) | to_entries | sort_by(.key) | .[]
             | (.key|nosep), "\u001f", (.value|nosep), "\u001f", (($captured[.key] // 0)|nosep), "\u001f"' \
            <<< "$set_check_json")"
        while IFS= read -r -d $'\x1f' count_key \
           && IFS= read -r -d $'\x1f' want \
           && IFS= read -r -d $'\x1f' got; do
            [[ -z "$count_key" ]] && continue
            if [[ "$got" != "$want" ]]; then
                passed=false
                add_finding 'SAFETY' "$rel_path" 0 \
                    "[$rule_name] set_check expected_counts mismatch in ${rel_path}: '$count_key' has $got occurrence(s), expected $want"
            fi
        done <<< "$counts_stream"
    done <<< "$files_stream"

    TEST_SET_CHECK_RESULT="$passed"
}

for fixture_file in "${SAFETY_FIXTURES[@]}"; do
    fixture_raw="$(<"$fixture_file")"
    # One jq pass for the per-fixture header fields (#305).
    fixture_header="$(jq -r "$JQ_NOSEP_DEF"'[(.rule|nosep), (has("source")|tostring), (has("consumers")|tostring), (has("set_check")|tostring)] | join("\u001f")' <<< "$fixture_raw")"
    rule_name="${fixture_header%%$'\x1f'*}"
    fixture_header="${fixture_header#*$'\x1f'}"
    has_source="${fixture_header%%$'\x1f'*}"
    fixture_header="${fixture_header#*$'\x1f'}"
    has_consumers="${fixture_header%%$'\x1f'*}"
    has_set_check="${fixture_header##*$'\x1f'}"
    fixture_passed=true

    if [[ "$has_source" != "true" && "$has_consumers" != "true" && "$has_set_check" != "true" ]]; then
        fixture_passed=false
        add_finding 'SAFETY' "$(basename "$fixture_file")" 0 \
            "[$rule_name] fixture has none of source / consumers / set_check"
    fi

    # Set-check assertion
    if [[ "$has_set_check" == "true" ]]; then
        set_check_json="$(echo "$fixture_raw" | jq '.set_check')"
        TEST_SET_CHECK_RESULT=""
        test_set_check "$rule_name" "$set_check_json"
        if [[ "$TEST_SET_CHECK_RESULT" != "true" ]]; then
            fixture_passed=false
        fi
    fi

    # Legacy source presence check. One jq pass extracts the source fields AND
    # the whitespace-normalized pattern (wsnorm, #350) so the loop spawns no
    # per-pattern tr process; the raw pattern is retained for finding text.
    if [[ "$has_source" == "true" ]]; then
        source_stream="$(jq -j "$JQ_NOSEP_DEF$JQ_WSNORM_DEF"'.source
            | (.file|nosep), "\u001f", (.pattern|nosep), "\u001f",
              ((.pattern|wsnorm)|nosep), "\u001f"' <<< "$fixture_raw")"
        {
            IFS= read -r -d $'\x1f' source_file_rel
            IFS= read -r -d $'\x1f' source_pattern
            IFS= read -r -d $'\x1f' source_pattern_norm
        } <<< "$source_stream"
        source_abs_path="$(resolve_repo_path "$source_file_rel")"

        if [[ ! -f "$source_abs_path" ]]; then
            fixture_passed=false
            add_finding 'SAFETY' "$source_file_rel" 0 \
                "[$rule_name] Source file missing: $source_file_rel"
        else
            norm_ws_cached whole "$source_abs_path"
            if [[ "$NORM_WS_RESULT" != *"$source_pattern_norm"* ]]; then
                fixture_passed=false
                add_finding 'SAFETY' "$source_file_rel" 0 \
                    "[$rule_name] Source pattern not found: $source_pattern"
            fi
        fi
    fi

    # Legacy consumers presence check (fields streamed in one jq pass; #305).
    # Unit-separator-delimited so a pattern may carry any byte except the
    # separator itself (an embedded newline still parses).
    if [[ "$has_consumers" == "true" ]]; then
        consumers_stream="$(jq -j "$JQ_NOSEP_DEF$JQ_WSNORM_DEF"'.consumers[]
            | (.file|nosep), "\u001f", (.pattern|nosep), "\u001f",
              ((.pattern|wsnorm)|nosep), "\u001f", ((.absent // false)|nosep), "\u001f"' \
            <<< "$fixture_raw")"
        while IFS= read -r -d $'\x1f' consumer_file_rel \
           && IFS= read -r -d $'\x1f' consumer_pattern \
           && IFS= read -r -d $'\x1f' consumer_pattern_norm \
           && IFS= read -r -d $'\x1f' is_absent; do
            consumer_abs_path="$(resolve_repo_path "$consumer_file_rel")"

            if [[ ! -f "$consumer_abs_path" ]]; then
                fixture_passed=false
                add_finding 'SAFETY' "$consumer_file_rel" 0 \
                    "[$rule_name] Consumer file missing: $consumer_file_rel"
                continue
            fi

            if [[ "$is_absent" == "true" ]]; then
                # INVARIANT: absent checks scope to YAML frontmatter only.
                if frontmatter_contains_ws_norm "$consumer_abs_path" "$consumer_pattern_norm"; then
                    fixture_passed=false
                    add_finding 'SAFETY' "$consumer_file_rel" 0 \
                        "[$rule_name] Consumer frontmatter must NOT contain: $consumer_pattern"
                fi
            else
                norm_ws_cached whole "$consumer_abs_path"
                if [[ "$NORM_WS_RESULT" != *"$consumer_pattern_norm"* ]]; then
                    fixture_passed=false
                    add_finding 'SAFETY' "$consumer_file_rel" 0 \
                        "[$rule_name] Consumer pattern not found: $consumer_pattern"
                fi
            fi
        done <<< "$consumers_stream"
    fi

    if [[ "$fixture_passed" == true ]]; then
        echo "[PASS] SAFETY: $rule_name"
        SAFETY_PASSED=$((SAFETY_PASSED + 1))
    else
        echo "[FAIL] SAFETY: $rule_name"
        SAFETY_FAILED=$((SAFETY_FAILED + 1))
    fi
done

if [[ ${#SAFETY_FIXTURES[@]} -eq 0 && "$SAFETY_FAILED" -eq 0 ]]; then
    echo '[SKIP] No safety fixture files found'
else
    echo "Safety fixtures: $SAFETY_PASSED passed, $SAFETY_FAILED failed out of $((SAFETY_PASSED + SAFETY_FAILED))"
    CHECKS_PASSED=$((CHECKS_PASSED + SAFETY_PASSED))
    CHECKS_FAILED=$((CHECKS_FAILED + SAFETY_FAILED))
fi

# ── SAFETY-CANARY: frontmatter-absent normalization self-test ──────────────
# `absent: true` matching is frontmatter-scoped and whitespace-normalized on
# both sides. NO standing green fixture can witness that normalization: for
# absent semantics a raw-substring hit always survives normalization (raw
# containment implies normalized containment), so removing the normalization
# can only flip a RED detection to GREEN — never a green fixture to red. This
# self-test therefore asserts the RED direction directly: the shipped canary
# target's frontmatter carries a forbidden token WRAPPED across lines, which
# only whitespace-normalized matching can see as one word sequence. If the
# frontmatter-side normalization is removed from frontmatter_contains_ws_norm,
# detection is lost and this check fails the run. The control assertion guards
# the opposite failure (a predicate that claims containment of anything).
NORMALIZE_ABSENT_CANARY_REL='tests/policy/fixtures/normalize-absent-canary.md'
normalize_absent_canary_target="$(resolve_repo_path "$NORMALIZE_ABSENT_CANARY_REL")"
normalize_absent_canary_pattern='normalize-absent-canary: this forbidden frontmatter token is deliberately wrapped across lines so only whitespace-normalized matching detects it'
normalize_absent_canary_control='normalize-absent-canary: token that appears nowhere in the target'
normalize_absent_canary_ok=true
if [[ ! -f "$normalize_absent_canary_target" ]]; then
    normalize_absent_canary_ok=false
    add_finding 'SAFETY-CANARY' "$NORMALIZE_ABSENT_CANARY_REL" 0 \
        'normalize-absent canary target missing -- the frontmatter-absent normalization self-test cannot run'
else
    if ! frontmatter_contains_ws_norm "$normalize_absent_canary_target" "$normalize_absent_canary_pattern"; then
        normalize_absent_canary_ok=false
        add_finding 'SAFETY-CANARY' "$NORMALIZE_ABSENT_CANARY_REL" 0 \
            'frontmatter-absent matching failed to detect the wrapped canary token -- whitespace normalization on the frontmatter side of absent checks has regressed (frontmatter_contains_ws_norm in tools/policy_check.sh)'
    fi
    if frontmatter_contains_ws_norm "$normalize_absent_canary_target" "$normalize_absent_canary_control"; then
        normalize_absent_canary_ok=false
        add_finding 'SAFETY-CANARY' "$NORMALIZE_ABSENT_CANARY_REL" 0 \
            'frontmatter-absent matching claimed containment of a token absent from the canary target -- the containment predicate is unsound'
    fi
fi
if [[ "$normalize_absent_canary_ok" == true ]]; then
    echo '[PASS] SAFETY-CANARY: frontmatter-absent normalization detects the wrapped canary token'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo '[FAIL] SAFETY-CANARY: frontmatter-absent normalization self-test'
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# ── SAFETY-CANARY: set_check zero-match self-test ──────────────────────────
# A files entry whose extract_regex matches NOTHING must still produce a valid
# empty capture object, and a BROKEN extraction must never be mistaken for
# that zero-match result. No standing green fixture witnesses these branches:
# real fixtures always capture something. Each assertion calls test_set_check
# in a SUBSHELL and reads its verdict back over stdout, so a regression that
# ABORTS the call (e.g. malformed capture JSON rejected by the downstream
# --argjson) kills only the subshell, empty output means FAIL, and the run
# continues to a summary. Subshell isolation also keeps the must-fail
# assertions' findings out of the real report.
#   1. zero-match: a regex matching nothing must pass (the zero-match witness).
#   2. non-vacuity control: a deliberately wrong occurrence count must fail,
#      proving assertion 1 asserts something.
#   3. non-compiling regex: must fail through the perl compile oracle.
#   4. broken extraction: a regex that compiles, HAS a capture group (so it
#      clears the independent group count), and matches, but whose group 1
#      does not participate in the match must fail -- the extractor's
#      `defined($1) or die` fires at run time, and that nonzero status must
#      never collapse into an empty capture object that reads as a vacuous
#      zero-match pass. This is the only assertion that reaches the extractor
#      exit-status path; branch 6 is stopped earlier by the group count.
#   5. unescaped slash: a regex containing `/` must extract normally, proving
#      the regex reaches perl as data rather than as program source.
#   6. capture-free zero-match: a regex with NO capture group that ALSO
#      matches nothing must fail -- without an independent capture-group
#      count, this exact combination never reaches the `defined($1) or die`
#      guard (the while-loop body never runs) and would vacuously pass as the
#      same clean empty result as branch 1.
# INVARIANT: the capture must NOT be written as `out="$( ... )" || out=''` --
# bash disables errexit inside a command substitution that is part of an
# AND-OR list, so the regression would be swallowed INSIDE the subshell and
# the canary would report a false PASS. The parent therefore drops errexit
# around the capture and the subshell re-arms it with its own `set -e`.
SET_CHECK_ZERO_CANARY_REL='tests/policy/fixtures/set-check-zero-match-canary.md'
set_check_zero_canary_target="$(resolve_repo_path "$SET_CHECK_ZERO_CANARY_REL")"
set_check_zero_canary_ok=true
if [[ ! -f "$set_check_zero_canary_target" ]]; then
    set_check_zero_canary_ok=false
    add_finding 'SAFETY-CANARY' "$SET_CHECK_ZERO_CANARY_REL" 0 \
        'set_check zero-match canary target missing -- the zero-match capture self-test cannot run'
else
    set_check_zero_spec="$(jq -n --arg path "$SET_CHECK_ZERO_CANARY_REL" '{
        extract_regex: "SETCHECK-ZERO-MATCH-CANARY ([0-9]+):",
        expected_set: ["1", "2"],
        expected_counts: {"1": 0, "2": 0},
        files: [{path: $path, mode: "subset"}]
    }')"
    set_check_zero_result=''
    set +e
    set_check_zero_result="$(
        set -e
        TEST_SET_CHECK_RESULT=''
        test_set_check 'set-check-zero-match-canary' "$set_check_zero_spec" 1>&2
        echo "$TEST_SET_CHECK_RESULT"
    )"
    set -e
    if [[ "$set_check_zero_result" != 'true' ]]; then
        set_check_zero_canary_ok=false
        add_finding 'SAFETY-CANARY' "$SET_CHECK_ZERO_CANARY_REL" 0 \
            "set_check over a zero-match file did not return a clean pass (empty result = the call aborted the run; a false result = the zero-match capture was not a valid empty object -- see test_set_check in tools/policy_check.sh)"
    fi

    set_check_control_spec="$(jq -n --arg path "$SET_CHECK_ZERO_CANARY_REL" '{
        extract_regex: "SETCHECK-PRESENT-CANARY ([0-9]+):",
        expected_set: ["1", "2"],
        expected_counts: {"1": 2, "2": 1},
        files: [{path: $path, mode: "equal"}]
    }')"
    set_check_control_result=''
    set +e
    set_check_control_result="$(
        set -e
        TEST_SET_CHECK_RESULT=''
        test_set_check 'set-check-zero-match-canary-control' "$set_check_control_spec" > /dev/null 2>&1
        echo "$TEST_SET_CHECK_RESULT"
    )"
    set -e
    if [[ "$set_check_control_result" != 'false' ]]; then
        set_check_zero_canary_ok=false
        add_finding 'SAFETY-CANARY' "$SET_CHECK_ZERO_CANARY_REL" 0 \
            'set_check control did not fail -- capture/count assertion is vacuous'
    fi

    set_check_uncompiled_spec="$(jq -n --arg path "$SET_CHECK_ZERO_CANARY_REL" '{
        extract_regex: "(SETCHECK-UNCLOSED",
        expected_set: [],
        expected_counts: {},
        files: [{path: $path, mode: "subset"}]
    }')"
    set_check_uncompiled_result=''
    set +e
    set_check_uncompiled_result="$(
        set -e
        TEST_SET_CHECK_RESULT=''
        test_set_check 'set-check-zero-match-canary-uncompiled' "$set_check_uncompiled_spec" > /dev/null 2>&1
        echo "$TEST_SET_CHECK_RESULT"
    )"
    set -e
    if [[ "$set_check_uncompiled_result" != 'false' ]]; then
        set_check_zero_canary_ok=false
        add_finding 'SAFETY-CANARY' "$SET_CHECK_ZERO_CANARY_REL" 0 \
            'set_check accepted a non-compiling extract_regex -- the perl compile oracle is not failing closed'
    fi

    set_check_nocapture_spec="$(jq -n --arg path "$SET_CHECK_ZERO_CANARY_REL" '{
        extract_regex: "SETCHECK-PRESENT-CANARY (x)?[0-9]:",
        expected_set: [],
        expected_counts: {},
        files: [{path: $path, mode: "subset"}]
    }')"
    set_check_nocapture_result=''
    set +e
    set_check_nocapture_result="$(
        set -e
        TEST_SET_CHECK_RESULT=''
        test_set_check 'set-check-zero-match-canary-nocapture' "$set_check_nocapture_spec" > /dev/null 2>&1
        echo "$TEST_SET_CHECK_RESULT"
    )"
    set -e
    if [[ "$set_check_nocapture_result" != 'false' ]]; then
        set_check_zero_canary_ok=false
        add_finding 'SAFETY-CANARY' "$SET_CHECK_ZERO_CANARY_REL" 0 \
            'set_check passed a broken extraction (the regex has a capture group, but group 1 did not participate in a match, so the extractor died with a nonzero status) -- a failed extraction is being read as a zero-match result'
    fi

    set_check_slash_spec="$(jq -n --arg path "$SET_CHECK_ZERO_CANARY_REL" '{
        extract_regex: "SETCHECK-SLASH-CANARY (a/[a-z]+):",
        expected_set: ["a/b"],
        expected_counts: {"a/b": 1},
        files: [{path: $path, mode: "equal"}]
    }')"
    set_check_slash_result=''
    set +e
    set_check_slash_result="$(
        set -e
        TEST_SET_CHECK_RESULT=''
        test_set_check 'set-check-zero-match-canary-slash' "$set_check_slash_spec" 1>&2
        echo "$TEST_SET_CHECK_RESULT"
    )"
    set -e
    if [[ "$set_check_slash_result" != 'true' ]]; then
        set_check_zero_canary_ok=false
        add_finding 'SAFETY-CANARY' "$SET_CHECK_ZERO_CANARY_REL" 0 \
            'set_check failed to extract with a regex containing an unescaped slash -- the regex is reaching perl as program source instead of data'
    fi

    # Branch 6: a capture-free regex reusing the reserved zero-match token
    # prefix (guaranteed to match nothing in this fixture per the file's own
    # docstring) must still FAIL -- without the independent capture-group
    # count above, this exact combination never runs the extraction loop's
    # `defined($1) or die` guard and would vacuously pass as a clean
    # zero-match result identical to branch 1.
    set_check_nocapture_zero_match_spec="$(jq -n --arg path "$SET_CHECK_ZERO_CANARY_REL" '{
        extract_regex: "SETCHECK-ZERO-MATCH-CANARY [0-9]+:",
        expected_set: [],
        expected_counts: {},
        files: [{path: $path, mode: "subset"}]
    }')"
    set_check_nocapture_zero_match_result=''
    set +e
    set_check_nocapture_zero_match_result="$(
        set -e
        TEST_SET_CHECK_RESULT=''
        test_set_check 'set-check-zero-match-canary-nocapture-zero-match' "$set_check_nocapture_zero_match_spec" > /dev/null 2>&1
        echo "$TEST_SET_CHECK_RESULT"
    )"
    set -e
    if [[ "$set_check_nocapture_zero_match_result" != 'false' ]]; then
        set_check_zero_canary_ok=false
        add_finding 'SAFETY-CANARY' "$SET_CHECK_ZERO_CANARY_REL" 0 \
            'set_check passed a capture-free extract_regex that matches nothing -- a capture-free regex is being vacuously accepted as a zero-match result'
    fi
fi
if [[ "$set_check_zero_canary_ok" == true ]]; then
    echo '[PASS] SAFETY-CANARY: set_check returns a clean pass over a zero-match file'
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo '[FAIL] SAFETY-CANARY: set_check zero-match self-test'
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

mark_time 'SAFETY'

# ── COMPATIBILITY TESTS ────────────────────────────────────────────────────

echo ''
echo '=== COMPAT: Plugin compatibility fixture tests ==='

COMPAT_DIR="$REPO_ROOT/tests/plugin"
declare -a COMPAT_FIXTURES=()
COMPAT_DISCOVERY_FAILED=false
# REQUIRED root: see the SAFETY root gate above -- a bare `-d` pre-guard would
# turn a missing or non-directory root into a silent SKIP over zero fixtures.
COMPAT_DIR_RC=0
discovery_gate_status "$COMPAT_DIR" dirs || COMPAT_DIR_RC=$?
if [[ "$COMPAT_DIR_RC" -ne 0 ]]; then
    COMPAT_DISCOVERY_FAILED=true
    flag_discovery_gate 'COMPAT' "$COMPAT_DIR" "$COMPAT_DIR_RC"
else
    discover_checked_paths 'COMPAT' COMPAT_FIXTURES files 'compatibility fixture files' "$COMPAT_DIR" -- -maxdepth 1 -name '*.json' || COMPAT_DISCOVERY_FAILED=true
fi

COMPAT_PASSED=0
COMPAT_FAILED=0
if [[ "$COMPAT_DISCOVERY_FAILED" == true ]]; then
    echo '[FAIL] COMPAT: compatibility fixture discovery'
    COMPAT_FAILED=$((COMPAT_FAILED + 1))
fi

for fixture_file in "${COMPAT_FIXTURES[@]}"; do
    fixture_raw="$(<"$fixture_file")"
    check_desc="$(echo "$fixture_raw" | jq -r '.check')"
    check_type="$(echo "$fixture_raw" | jq -r '.type')"
    fixture_passed=true

    case "$check_type" in

        json-fields)
            target_rel="$(echo "$fixture_raw" | jq -r '.file')"
            target_path="$(resolve_repo_path "$target_rel")"
            if [[ ! -f "$target_path" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$target_rel" 0 \
                    "[$check_desc] File missing: $target_rel"
            else
                json_obj="$(<"$target_path")"
                req_count="$(echo "$fixture_raw" | jq '.required | length')"
                ri=0
                while [[ $ri -lt $req_count ]]; do
                    req_field="$(echo "$fixture_raw" | jq -r ".required[$ri]")"
                    if ! echo "$json_obj" | jq -e --arg f "$req_field" 'has($f)' > /dev/null 2>&1; then
                        fixture_passed=false
                        add_finding 'COMPAT' "$target_rel" 0 \
                            "[$check_desc] Missing required JSON field: $req_field"
                    fi
                    ri=$((ri + 1))
                done
            fi
            ;;

        json-field-value)
            target_rel="$(echo "$fixture_raw" | jq -r '.file')"
            target_path="$(resolve_repo_path "$target_rel")"
            if [[ ! -f "$target_path" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$target_rel" 0 \
                    "[$check_desc] File missing: $target_rel"
            else
                json_obj="$(<"$target_path")"

                # Check required arrays if specified
                has_req_arrays="$(echo "$fixture_raw" | jq 'has("required-arrays")')"
                if [[ "$has_req_arrays" == "true" ]]; then
                    ra_count="$(echo "$fixture_raw" | jq '."required-arrays" | length')"
                    rai=0
                    while [[ $rai -lt $ra_count ]]; do
                        arr_name="$(echo "$fixture_raw" | jq -r ".\"required-arrays\"[$rai]")"
                        if ! echo "$json_obj" | jq -e --arg f "$arr_name" 'has($f)' > /dev/null 2>&1; then
                            fixture_passed=false
                            add_finding 'COMPAT' "$target_rel" 0 \
                                "[$check_desc] Missing required array: $arr_name"
                        else
                            arr_len="$(echo "$json_obj" | jq --arg f "$arr_name" '.[$f] | if type == "array" then length else -1 end')"
                            if [[ "$arr_len" -le 0 ]]; then
                                fixture_passed=false
                                add_finding 'COMPAT' "$target_rel" 0 \
                                    "[$check_desc] Field is not a non-empty array: $arr_name"
                            fi
                        fi
                        rai=$((rai + 1))
                    done
                fi

                # Check field value
                field_name="$(echo "$fixture_raw" | jq -r '.field')"
                expected_value="$(echo "$fixture_raw" | jq -r '.expected')"
                field_found=false

                has_plugins="$(echo "$json_obj" | jq 'has("plugins") and (.plugins | length > 0)' 2>/dev/null || echo "false")"
                if [[ "$has_plugins" == "true" ]]; then
                    field_found=true
                    plugin_count="$(echo "$json_obj" | jq '.plugins | length')"
                    pi=0
                    while [[ $pi -lt $plugin_count ]]; do
                        has_field="$(echo "$json_obj" | jq --arg f "$field_name" ".plugins[$pi] | has(\$f)")"
                        if [[ "$has_field" != "true" ]]; then
                            fixture_passed=false
                            add_finding 'COMPAT' "$target_rel" 0 \
                                "[$check_desc] plugins[] entry missing required field '$field_name'"
                        else
                            actual_value="$(echo "$json_obj" | jq -r --arg f "$field_name" ".plugins[$pi][\$f]")"
                            if [[ "$actual_value" != "$expected_value" ]]; then
                                fixture_passed=false
                                add_finding 'COMPAT' "$target_rel" 0 \
                                    "[$check_desc] plugins[].$field_name = '$actual_value', expected '$expected_value'"
                            fi
                        fi
                        pi=$((pi + 1))
                    done
                else
                    has_field="$(echo "$json_obj" | jq --arg f "$field_name" 'has($f)' 2>/dev/null || echo "false")"
                    if [[ "$has_field" == "true" ]]; then
                        field_found=true
                        actual_value="$(echo "$json_obj" | jq -r --arg f "$field_name" '.[$f]')"
                        if [[ "$actual_value" != "$expected_value" ]]; then
                            fixture_passed=false
                            add_finding 'COMPAT' "$target_rel" 0 \
                                "[$check_desc] $field_name = '$actual_value', expected '$expected_value'"
                        fi
                    fi
                fi

                if [[ "$field_found" == false ]]; then
                    fixture_passed=false
                    add_finding 'COMPAT' "$target_rel" 0 \
                        "[$check_desc] Field '$field_name' not found"
                fi
            fi
            ;;

        frontmatter-all-files)
            target_dir_rel="$(echo "$fixture_raw" | jq -r '.dir')"
            target_dir="$(resolve_repo_path "$target_dir_rel")"
            if [[ ! -d "$target_dir" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$target_dir_rel" 0 \
                    "[$check_desc] Directory missing: $target_dir_rel"
            else
                glob_pattern="$(echo "$fixture_raw" | jq -r '.glob // "*.md"')"
                exclude_pattern="$(echo "$fixture_raw" | jq -r '.exclude // empty')"

                declare -a target_files=()
                if [[ "$glob_pattern" == *"/"* ]]; then
                    # Glob with subdirectory (e.g. */SKILL.md) — recurse and filter
                    local_filter="${glob_pattern##*/}"
                    discover_checked_paths 'COMPAT' target_files files "[$check_desc] files named '$local_filter' under $target_dir_rel" "$target_dir" -- -name "$local_filter" || fixture_passed=false
                else
                    discover_checked_paths 'COMPAT' target_files files "[$check_desc] files matching '$glob_pattern' in $target_dir_rel" "$target_dir" -- -maxdepth 1 -name "$glob_pattern" || fixture_passed=false
                fi

                if [[ -n "$exclude_pattern" ]]; then
                    declare -a filtered_files=()
                    for tf in "${target_files[@]}"; do
                        if ! grep -q "/$exclude_pattern/" <<< "$tf"; then
                            filtered_files+=("$tf")
                        fi
                    done
                    target_files=("${filtered_files[@]}")
                fi

                if [[ ${#target_files[@]} -eq 0 ]]; then
                    fixture_passed=false
                    add_finding 'COMPAT' "$target_dir_rel" 0 \
                        "[$check_desc] No files matched glob '$glob_pattern' in $target_dir_rel"
                fi

                req_count="$(echo "$fixture_raw" | jq '.required | length')"
                for target_file in "${target_files[@]}"; do
                    fm_content="$(get_frontmatter "$target_file")"
                    ri=0
                    while [[ $ri -lt $req_count ]]; do
                        req_field="$(echo "$fixture_raw" | jq -r ".required[$ri]")"
                        if ! grep -qP "^\s*${req_field}\s*:" <<< "$fm_content"; then
                            fixture_passed=false
                            rel_file="${target_file#"$REPO_ROOT"/}"
                            rel_file="${rel_file//\\//}"
                            add_finding 'COMPAT' "$rel_file" 0 \
                                "[$check_desc] Missing frontmatter field: $req_field"
                        fi
                        ri=$((ri + 1))
                    done
                done
            fi
            ;;

        frontmatter-field-absent)
            target_dir_rel="$(echo "$fixture_raw" | jq -r '.dir')"
            target_dir="$(resolve_repo_path "$target_dir_rel")"
            if [[ ! -d "$target_dir" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$target_dir_rel" 0 \
                    "[$check_desc] Directory missing: $target_dir_rel"
            else
                declare -a field_absent_files=()
                discover_checked_paths 'COMPAT' field_absent_files files "[$check_desc] Markdown files in $target_dir_rel" "$target_dir" -- -maxdepth 1 -name '*.md' || fixture_passed=false
                for target_file in "${field_absent_files[@]}"; do
                    fm_content="$(get_frontmatter "$target_file")"
                    absent_count="$(echo "$fixture_raw" | jq '.absent | length')"
                    ai=0
                    while [[ $ai -lt $absent_count ]]; do
                        absent_field="$(echo "$fixture_raw" | jq -r ".absent[$ai]")"
                        if grep -qP "^\s*${absent_field}\s*:" <<< "$fm_content"; then
                            fixture_passed=false
                            rel_file="${target_file#"$REPO_ROOT"/}"
                            rel_file="${rel_file//\\//}"
                            add_finding 'COMPAT' "$rel_file" 0 \
                                "[$check_desc] Forbidden frontmatter field present: $absent_field"
                        fi
                        ai=$((ai + 1))
                    done
                done
            fi
            ;;

        dir-names-in-file)
            target_dir_rel="$(echo "$fixture_raw" | jq -r '.dir')"
            ref_file_rel="$(echo "$fixture_raw" | jq -r '.file')"
            exclude_pattern="$(echo "$fixture_raw" | jq -r '.exclude // empty')"
            target_dir="$(resolve_repo_path "$target_dir_rel")"
            ref_file_path="$(resolve_repo_path "$ref_file_rel")"

            if [[ ! -d "$target_dir" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$target_dir_rel" 0 \
                    "[$check_desc] Directory missing: $target_dir_rel"
            elif [[ ! -f "$ref_file_path" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$ref_file_rel" 0 \
                    "[$check_desc] Reference file missing: $ref_file_rel"
            else
                ref_content="$(<"$ref_file_path")"
                # INVARIANT: under DISCOVERY_FIND_BASE (-L) `-type d` is true for
                # a directory AND a symlink to one, and `-type l` is true only for
                # a symlink find cannot follow (dangling), so this predicate hands
                # every subdirectory plus every dangling entry to the `dirs` gate,
                # which rejects the dangling ones loudly; plain files stay out.
                declare -a named_subdirs=()
                discover_checked_paths 'COMPAT' named_subdirs dirs "[$check_desc] subdirectories of $target_dir_rel" "$target_dir" -- -mindepth 1 -maxdepth 1 '(' -type d -o -type l ')' || fixture_passed=false
                for subdir in "${named_subdirs[@]}"; do
                    dir_name="$(basename "$subdir")"
                    if [[ -n "$exclude_pattern" && "$dir_name" == "$exclude_pattern" ]]; then
                        continue
                    fi
                    # Fixed-string substring test via the bash builtin, NOT `echo | grep -qF`.
                    # `grep -q` exits on the FIRST match and closes the pipe; when the needle
                    # matches early in a multi-KB haystack, echo's remaining writes take EPIPE
                    # (exit 141) and `set -o pipefail` turns the MATCHING pipeline into a
                    # non-zero status — a false "not found" for a string that IS present. That
                    # false negative failed CI on PR #341 for `adaptation-cycle` (first skill dir,
                    # earliest README match) alongside "echo: write error: Broken pipe". The
                    # builtin has no pipe and no reader to exit early, so the failure mode cannot
                    # occur; the quoted needle keeps the match literal/fixed-string.
                    if [[ "$ref_content" != *"$dir_name"* ]]; then
                        fixture_passed=false
                        add_finding 'COMPAT' "$ref_file_rel" 0 \
                            "[$check_desc] Directory name not found in $ref_file_rel: $dir_name"
                    fi
                done
            fi
            ;;

        file-names-in-file)
            target_dir_rel="$(echo "$fixture_raw" | jq -r '.dir')"
            ref_file_rel="$(echo "$fixture_raw" | jq -r '.file')"
            target_dir="$(resolve_repo_path "$target_dir_rel")"
            ref_file_path="$(resolve_repo_path "$ref_file_rel")"

            if [[ ! -d "$target_dir" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$target_dir_rel" 0 \
                    "[$check_desc] Directory missing: $target_dir_rel"
            elif [[ ! -f "$ref_file_path" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$ref_file_rel" 0 \
                    "[$check_desc] Reference file missing: $ref_file_rel"
            else
                ref_content="$(<"$ref_file_path")"
                declare -a named_md_files=()
                discover_checked_paths 'COMPAT' named_md_files files "[$check_desc] Markdown files in $target_dir_rel" "$target_dir" -- -maxdepth 1 -name '*.md' || fixture_passed=false
                for file_in_dir in "${named_md_files[@]}"; do
                    base_name="$(basename "$file_in_dir" .md)"
                    # Builtin fixed-string test — same EPIPE/pipefail false-negative class as the
                    # dir-names-in-file arm above (see its comment).
                    if [[ "$ref_content" != *"$base_name"* ]]; then
                        fixture_passed=false
                        add_finding 'COMPAT' "$ref_file_rel" 0 \
                            "[$check_desc] Filename not found in $ref_file_rel: $base_name"
                    fi
                done
            fi
            ;;

        file-exists-and-referenced)
            target_rel="$(echo "$fixture_raw" | jq -r '.file')"
            ref_file_rel="$(echo "$fixture_raw" | jq -r '.["referenced-in"]')"
            target_path="$(resolve_repo_path "$target_rel")"
            ref_file_path="$(resolve_repo_path "$ref_file_rel")"

            if [[ ! -f "$target_path" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$target_rel" 0 \
                    "[$check_desc] File missing: $target_rel"
            fi

            if [[ ! -f "$ref_file_path" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$ref_file_rel" 0 \
                    "[$check_desc] Reference file missing: $ref_file_rel"
            elif [[ -f "$target_path" ]]; then
                ref_content="$(<"$ref_file_path")"
                file_base_name="$(basename "$target_rel")"
                # Builtin fixed-string test — same EPIPE/pipefail false-negative class as the
                # dir-names-in-file arm above (see its comment).
                if [[ "$ref_content" != *"$file_base_name"* ]]; then
                    fixture_passed=false
                    add_finding 'COMPAT' "$ref_file_rel" 0 \
                        "[$check_desc] $ref_file_rel does not reference $file_base_name"
                fi
            fi
            ;;

        pattern-absent-in-dir)
            target_dir_rel="$(echo "$fixture_raw" | jq -r '.dir')"
            search_pattern="$(echo "$fixture_raw" | jq -r '.pattern')"
            target_dir="$(resolve_repo_path "$target_dir_rel")"

            if [[ ! -d "$target_dir" ]]; then
                fixture_passed=false
                add_finding 'COMPAT' "$target_dir_rel" 0 \
                    "[$check_desc] Directory missing: $target_dir_rel"
            else
                # INVARIANT: under DISCOVERY_FIND_BASE (-L) `-type d` is true for
                # a directory AND a symlink to one, so `! -type d` keeps every
                # directory out while regular files, symlinks to files, dangling
                # symlinks, and special files all reach the `files` gate, which
                # rejects all but readable regular files loudly.
                declare -a pattern_scan_files=()
                discover_checked_paths 'COMPAT' pattern_scan_files files "[$check_desc] files under $target_dir_rel" "$target_dir" -- '!' -type d || fixture_passed=false
                for scan_file in "${pattern_scan_files[@]}"; do
                    scan_content="$(<"$scan_file")"
                    if [[ "$scan_content" == *"$search_pattern"* ]]; then
                        fixture_passed=false
                        rel_file="${scan_file#"$REPO_ROOT"/}"
                        rel_file="${rel_file//\\//}"
                        add_finding 'COMPAT' "$rel_file" 0 \
                            "[$check_desc] Forbidden pattern found: $search_pattern"
                    fi
                done
            fi
            ;;

        *)
            fixture_passed=false
            add_finding 'COMPAT' "$(basename "$fixture_file")" 0 \
                "[$check_desc] Unknown fixture type: $check_type"
            ;;
    esac

    if [[ "$fixture_passed" == true ]]; then
        echo "[PASS] COMPAT: $check_desc"
        COMPAT_PASSED=$((COMPAT_PASSED + 1))
    else
        echo "[FAIL] COMPAT: $check_desc"
        COMPAT_FAILED=$((COMPAT_FAILED + 1))
    fi
done

if [[ ${#COMPAT_FIXTURES[@]} -eq 0 && "$COMPAT_FAILED" -eq 0 ]]; then
    echo '[SKIP] No compatibility fixture files found'
else
    echo "Compatibility fixtures: $COMPAT_PASSED passed, $COMPAT_FAILED failed out of $((COMPAT_PASSED + COMPAT_FAILED))"
    CHECKS_PASSED=$((CHECKS_PASSED + COMPAT_PASSED))
    CHECKS_FAILED=$((CHECKS_FAILED + COMPAT_FAILED))
fi

mark_time 'COMPAT'

# ── WORKFLOW FIXTURE TESTS ─────────────────────────────────────────────────

echo ''
echo '=== WORKFLOW-FIXTURES: Golden-path workflow tests ==='

test_workflow_fixtures() {
    local fixtures_dir="$REPO_ROOT/tests/workflows"
    declare -a fixtures=()
    local wf_discovery_failed=false
    # REQUIRED root: see the SAFETY root gate above. This site already failed
    # loudly on zero fixtures, but it is gated the same way so the `-d`
    # pre-guard shape exists nowhere in this script and cannot be copied
    # forward into a call site that has no such backstop.
    local wf_dir_rc=0
    discovery_gate_status "$fixtures_dir" dirs || wf_dir_rc=$?
    if [[ "$wf_dir_rc" -ne 0 ]]; then
        wf_discovery_failed=true
        flag_discovery_gate 'WORKFLOW-FIXTURES' "$fixtures_dir" "$wf_dir_rc"
    else
        discover_checked_paths 'WORKFLOW-FIXTURES' fixtures files 'golden-*.json workflow fixture files' "$fixtures_dir" -- -maxdepth 1 -name 'golden-*.json' || wf_discovery_failed=true
    fi

    WF_PASSED=0
    WF_FAILED=0
    if [[ "$wf_discovery_failed" == true ]]; then
        echo 'FAIL [WORKFLOW-FIXTURES] golden-*.json fixture discovery'
        WF_FAILED=$((WF_FAILED + 1))
    fi

    if [[ ${#fixtures[@]} -eq 0 ]]; then
        echo "FAIL [WORKFLOW-FIXTURES] No golden-*.json fixtures found in tests/workflows/"
        add_finding 'WORKFLOW-FIXTURES' "$fixtures_dir" 0 \
            'No golden-*.json fixtures found in tests/workflows/'
        WF_FAILED=1
        return
    fi

    local expected_fixtures=(
        'golden-feature.json'
        'golden-monitor-request.json'
        'golden-pr-open.json'
        'golden-review-remediation.json'
        'golden-trivial-edit.json'
    )

    for expected in "${expected_fixtures[@]}"; do
        local expected_path="$fixtures_dir/$expected"
        if [[ ! -f "$expected_path" ]]; then
            echo "FAIL [WORKFLOW-FIXTURES] Missing required fixture: $expected"
            add_finding 'WORKFLOW-FIXTURES' "$fixtures_dir/$expected" 0 \
                "Missing required fixture: $expected"
            WF_FAILED=$((WF_FAILED + 1))
        fi
    done

    for f in "${fixtures[@]}"; do
        local f_name
        f_name="$(basename "$f")"
        local data
        data="$(<"$f")" || true
        if ! echo "$data" | jq empty 2>/dev/null; then
            echo "FAIL [WORKFLOW-FIXTURES] $f_name: JSON parse error"
            add_finding 'WORKFLOW-FIXTURES' "$f" 0 \
                "Fixture JSON parse error: $f_name"
            WF_FAILED=$((WF_FAILED + 1))
            continue
        fi

        local step_count
        step_count="$(echo "$data" | jq '.steps // [] | length')"
        if [[ "$step_count" -eq 0 ]]; then
            echo "FAIL [WORKFLOW-FIXTURES] $f_name: fixture has no steps"
            add_finding 'WORKFLOW-FIXTURES' "$f" 0 \
                "Fixture has no steps: $f_name"
            WF_FAILED=$((WF_FAILED + 1))
            continue
        fi

        local file_passed=true
        local si=0
        while [[ $si -lt $step_count ]]; do
            local step_state
            step_state="$(echo "$data" | jq -r ".steps[$si].state")"
            local src_file_rel
            src_file_rel="$(echo "$data" | jq -r ".steps[$si].source.file")"
            local src_pattern
            src_pattern="$(echo "$data" | jq -r ".steps[$si].source.pattern")"
            local src_path
            src_path="$(resolve_repo_path "$src_file_rel")"

            if [[ ! -f "$src_path" ]]; then
                echo "FAIL [WORKFLOW-FIXTURES] $f_name state=$step_state: source file not found: $src_file_rel"
                add_finding 'WORKFLOW-FIXTURES' "$src_file_rel" 0 \
                    "Workflow fixture source file not found: $src_file_rel"
                file_passed=false
                si=$((si + 1))
                continue
            fi

            local content
            content="$(<"$src_path")"
            if [[ "$content" == *"$src_pattern"* ]]; then
                echo "PASS [WORKFLOW-FIXTURES] $f_name state=$step_state"
            else
                echo "FAIL [WORKFLOW-FIXTURES] $f_name state=$step_state: pattern not found: $src_pattern"
                add_finding 'WORKFLOW-FIXTURES' "$src_file_rel" 0 \
                    "Workflow fixture pattern not found in $src_file_rel: $src_pattern"
                file_passed=false
            fi
            si=$((si + 1))
        done

        if [[ "$file_passed" == true ]]; then
            WF_PASSED=$((WF_PASSED + 1))
        else
            WF_FAILED=$((WF_FAILED + 1))
        fi
    done
}

WF_PASSED=0
WF_FAILED=0
test_workflow_fixtures
CHECKS_PASSED=$((CHECKS_PASSED + WF_PASSED))
CHECKS_FAILED=$((CHECKS_FAILED + WF_FAILED))

mark_time 'WORKFLOW-FIXTURES'

print_timing_table

# ── Summary ─────────────────────────────────────────────────────────────────

echo ''
echo '=== Summary ==='

TOTAL_FINDINGS=${#FINDING_RULES[@]}
ALLOWLISTED_COUNT=0
for allowed in "${FINDING_ALLOWED[@]}"; do
    if [[ "$allowed" == "true" ]]; then
        ALLOWLISTED_COUNT=$((ALLOWLISTED_COUNT + 1))
    fi
done
NON_ALLOWLISTED_COUNT=$((TOTAL_FINDINGS - ALLOWLISTED_COUNT))

echo "Checks passed: $CHECKS_PASSED / $((CHECKS_PASSED + CHECKS_FAILED))"
echo "Total findings: $TOTAL_FINDINGS"
echo "Allowlisted:    $ALLOWLISTED_COUNT"
echo "New findings:   $NON_ALLOWLISTED_COUNT"

if [[ "$STRICT" == true && "$NON_ALLOWLISTED_COUNT" -gt 0 ]]; then
    echo ''
    echo "STRICT MODE: $NON_ALLOWLISTED_COUNT finding(s) not in allowlist. Exiting with error."
    exit 1
fi

exit 0
