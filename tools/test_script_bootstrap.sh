#!/usr/bin/env bash
#
# Contract test for the fail-closed bootstrap prologue of every self-locating plugin engine
# script: docs/adr/0020-single-responsibility-shell-libraries.md, "Amendment — 2026-09-29"
# (canonical forms C1-C5 and the emitter rule).
#
# SEAM: the self-location + source-or-die prologue of each plugin/**/*.sh that references
# ${BASH_SOURCE[0]} — C1 (entrypoint stage-1 self-location), C2 (stage-2 derivation relative to the
# stage-1 dir), C3 (sourced library locating a sibling), C4 (source-or-die pairs), C5 (the emitter
# is defined before the first derivation line). The BOOTSTRAP TABLE below is the enrolment list:
# every git-tracked plugin/**/*.sh whose non-comment lines reference BASH_SOURCE[0] must be a row,
# so a new self-locating script fails this suite until it is enrolled.
#
# LAYERS:
#   S   static  — closure, exact C1/C3 lines, no legacy idiom, exact C2 lines, C4 pairs + every
#                 `. <path>` line carries an `||` handler, emitter defined before its C1.
#   R1  dirname fails / prints nothing        -> exact contracted self-locate line on its channel.
#   R2  cd refuses any `/../` path            -> exact contracted stage-2 line (C1 unaffected).
#   R3  a sourced library is missing          -> exact contracted "missing" line / token.
#   R4  a sourced library is a syntax error   -> contracted "unparseable" line is the LAST stderr
#                                               line (or the exact stdout token); the bash parse
#                                               diagnostic above it is the ADR's accepted residual.
#   CDPATH  a decoy CDPATH cannot redirect a relative invocation.
#   Canaries  a reverted C1 must be classified as a regression by the probe checker, and an
#             unenrolled self-locating script in a synthetic root must be flagged by the closure.
#
# ASSUMPTION: the R1/R2 probes rely on the external `dirname` and the `cd` builtin being
# overridable via EXPORTED BASH FUNCTIONS (bash imports BASH_FUNC_* from the environment and a
# function shadows both an external command and a builtin). An engine that calls dirname by
# absolute path or via `command`/`builtin` would evade those probes; the static layer still pins
# the exact canonical text.
#
# ISOLATION: R1/R2/CDPATH run the REAL committed engines unmodified by absolute canonical path with
# cwd = the engine's own directory (the worst case, where a cwd fallback would silently succeed).
# R3/R4 and the canaries mutate only `cp -a` COPIES of plugin/ under a mktemp WORKDIR (never
# symlinks: pwd -P would resolve back into the real tree). Every probe runs with stub gh/tmux/claude
# first on PATH and HOME inside WORKDIR, so no probe can reach a real gh, tmux, or claude. Host HOME
# is left intact for the harness's own git reads (safe.directory may live in host config). A
# fingerprint of the real plugin/ tree is compared before and after the run.
#
# Prints PASS/FAIL per assertion. Exits non-zero if ANY assertion FAILs.
#
# Usage:
#   ./tools/test_script_bootstrap.sh

set -euo pipefail
unset CDPATH

# ── Path setup ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PLUGIN_ROOT="$REPO_ROOT/plugin"

# ── Dependency / input preflight ────────────────────────────────────────────

command -v git >/dev/null 2>&1 \
    || { echo "FAIL: required dependency 'git' is not installed" >&2; exit 2; }
command -v jq >/dev/null 2>&1 \
    || { echo "FAIL: required dependency 'jq' is not installed (spawn-brood checks it before C1)" >&2; exit 2; }
[[ -d "$PLUGIN_ROOT/skills" ]] \
    || { echo "FAIL: required input missing: $PLUGIN_ROOT/skills" >&2; exit 2; }

# ── Disposable workdir + host isolation ─────────────────────────────────────

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-script-bootstrap-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

mkdir -p "$WORKDIR/home" "$WORKDIR/probe" "$WORKDIR/copies" "$WORKDIR/stub-bin"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
unset STARTED_EVIDENCE_TIMEOUT RECONCILE_SETTLE

PROBE_HOME="$WORKDIR/home"
PROBE_DIR="$WORKDIR/probe"
STUB_BIN="$WORKDIR/stub-bin"
DECOY_ROOT="$WORKDIR/decoy"
SOURCE_LIB_HELPER="$WORKDIR/source-lib.sh"
BROOD_INPUTS_FILE="$WORKDIR/brood-inputs.json"

printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB_BIN/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB_BIN/claude"
printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB_BIN/gh"
chmod +x "$STUB_BIN/tmux" "$STUB_BIN/claude" "$STUB_BIN/gh"
printf '. "$1"\n' >"$SOURCE_LIB_HELPER"
printf 'not json\n' >"$BROOD_INPUTS_FILE"
mkdir -p "$DECOY_ROOT/skills/bump-type/scripts"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ── Bootstrap table ─────────────────────────────────────────────────────────
# INVARIANT: these rows restate the COMMITTED contract; a row edit is a contract change and must
# land together with the engine edit it describes.

C1_BODY='="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || '
LEGACY_SELF_LOCATE='cd "$(dirname "${BASH_SOURCE[0]}")"'
INTERIM_SELF_LOCATE='CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")"'
SELF_LOCATE_REASON='cannot self-locate the script directory; refusing to proceed'
PLUGIN_ROOT_REASON='cannot resolve the plugin root from the script directory; refusing to proceed'
BUMP_TYPE_USAGE_REASON='missing positional base ref; usage: bump-type.sh <base> --bump-trigger yes|no --no-bump-match yes|no'

# ENTRY_ROWS: <path>|<stage-1 var>|<emitter>|<C1 reason>   (C1 entrypoints)
ENTRY_ROWS=(
    "plugin/skills/bump-type/scripts/bump-type.sh|script_dir|blocker|$SELF_LOCATE_REASON"
    "plugin/skills/record-state-result/scripts/record-state-result.sh|script_dir|blocker|$SELF_LOCATE_REASON"
    "plugin/skills/init-run-ledger/scripts/init-run-ledger.sh|script_dir|blocker|$SELF_LOCATE_REASON"
    "plugin/skills/next-wave/scripts/next-wave.sh|script_dir|blocker|$SELF_LOCATE_REASON"
    "plugin/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh|script_dir|blocker|$SELF_LOCATE_REASON"
    "plugin/skills/seed-hive/scripts/seed-hive.sh|script_dir|fail|$SELF_LOCATE_REASON"
    "plugin/skills/spawn-brood/scripts/spawn-brood.sh|script_dir|blocker|$SELF_LOCATE_REASON"
    "plugin/skills/brood-status/scripts/brood-status-collect.sh|script_dir|blocker|$SELF_LOCATE_REASON"
    "plugin/skills/brood-status/scripts/brood-status-project.sh|script_dir|blocker|$SELF_LOCATE_REASON"
    "plugin/skills/github-review-loop/scripts/ledger-reconstruct.sh|script_dir|ledgerrecon_fail|cannot-self-locate"
    "plugin/skills/github-review-loop/scripts/loop-state.sh|SCRIPT_DIR|die|$SELF_LOCATE_REASON"
    "plugin/skills/github-review-loop/scripts/fetch-normalize.sh|SCRIPT_DIR|fetchnorm_fail|cannot-self-locate"
    "plugin/skills/github-review-loop/scripts/prefilter.sh|SCRIPT_DIR|prefilter_fail|cannot-self-locate"
)

# LIB_ROWS: <path>|<var>|<sibling lib in the same dir>   (C3 sourced libraries)
LIB_ROWS=(
    "plugin/skills/_shared/settings-merge.sh|__settings_merge_shared_dir|json-normalize.sh"
    "plugin/skills/_shared/claude-mem-path.sh|__cm_path_shared_dir|json-normalize.sh"
)

# STAGE2_ROWS: <path>|<stage-2 var>|<rel>|<C2 reason>   (stage-1 var + emitter come from ENTRY_ROWS)
STAGE2_ROWS=(
    "plugin/skills/bump-type/scripts/bump-type.sh|shared_dir|../../_shared|cannot resolve skills/_shared from the script directory; refusing to proceed"
    "plugin/skills/brood-status/scripts/brood-status-collect.sh|plugin_root|../../..|$PLUGIN_ROOT_REASON"
    "plugin/skills/brood-status/scripts/brood-status-project.sh|plugin_root|../../..|$PLUGIN_ROOT_REASON"
    "plugin/skills/init-run-ledger/scripts/init-run-ledger.sh|plugin_root|../../..|$PLUGIN_ROOT_REASON"
    "plugin/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh|plugin_root|../../..|$PLUGIN_ROOT_REASON"
    "plugin/skills/next-wave/scripts/next-wave.sh|plugin_root|../../..|$PLUGIN_ROOT_REASON"
    "plugin/skills/record-state-result/scripts/record-state-result.sh|plugin_root|../../..|$PLUGIN_ROOT_REASON"
    "plugin/skills/seed-hive/scripts/seed-hive.sh|plugin_root|../../..|$PLUGIN_ROOT_REASON"
    "plugin/skills/spawn-brood/scripts/spawn-brood.sh|plugin_root|../../..|$PLUGIN_ROOT_REASON"
    "plugin/skills/github-review-loop/scripts/ledger-reconstruct.sh|plugin_root|../../..|cannot-resolve-plugin-root"
)

# build_std_source_row <path> <path-expr dir> <lib> -> prints a SOURCE_ROWS row carrying the
# standard `required shared library missing` / `failed to source ... (unparseable)` reasons.
build_std_source_row() {
    printf '%s|%s/%s|required shared library missing: skills/_shared/%s; refusing to proceed|failed to source skills/_shared/%s (unparseable); refusing to proceed|%s' \
        "$1" "$2" "$3" "$3" "$3" "$3"
}

# SOURCE_ROWS: <path>|<path expr>|<missing reason>|<unparseable reason>|<libs sourced by the pair>
# Libs are filenames under plugin/skills/_shared/. A literal `$lib` in a reason is substituted per
# lib for the behavioural layers (seed-hive's loop pair).
SOURCE_ROWS=(
    "$(build_std_source_row plugin/skills/bump-type/scripts/bump-type.sh '$shared_dir' allowlist.sh)"
    "$(build_std_source_row plugin/skills/bump-type/scripts/bump-type.sh '$shared_dir' bump-type-derive.sh)"
    "$(build_std_source_row plugin/skills/brood-status/scripts/brood-status-collect.sh '$plugin_root/skills/_shared' brood-status-derive.sh)"
    "$(build_std_source_row plugin/skills/brood-status/scripts/brood-status-project.sh '$plugin_root/skills/_shared' containment.sh)"
    "$(build_std_source_row plugin/skills/brood-status/scripts/brood-status-project.sh '$plugin_root/skills/_shared' allowlist.sh)"
    "$(build_std_source_row plugin/skills/brood-status/scripts/brood-status-project.sh '$plugin_root/skills/_shared' manifest-json.sh)"
    "$(build_std_source_row plugin/skills/brood-status/scripts/brood-status-project.sh '$plugin_root/skills/_shared' ledger-project.sh)"
    "$(build_std_source_row plugin/skills/init-run-ledger/scripts/init-run-ledger.sh '$plugin_root/skills/_shared' containment.sh)"
    "$(build_std_source_row plugin/skills/init-run-ledger/scripts/init-run-ledger.sh '$plugin_root/skills/_shared' ledger-engine-io.sh)"
    "$(build_std_source_row plugin/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh '$plugin_root/skills/_shared' containment.sh)"
    "$(build_std_source_row plugin/skills/mark-intent-fallback/scripts/mark-intent-fallback.sh '$plugin_root/skills/_shared' ledger-engine-io.sh)"
    "$(build_std_source_row plugin/skills/next-wave/scripts/next-wave.sh '$plugin_root/skills/_shared' containment.sh)"
    "$(build_std_source_row plugin/skills/next-wave/scripts/next-wave.sh '$plugin_root/skills/_shared' ledger-engine-io.sh)"
    "$(build_std_source_row plugin/skills/record-state-result/scripts/record-state-result.sh '$plugin_root/skills/_shared' containment.sh)"
    "$(build_std_source_row plugin/skills/record-state-result/scripts/record-state-result.sh '$plugin_root/skills/_shared' ledger-engine-io.sh)"
    "$(build_std_source_row plugin/skills/spawn-brood/scripts/spawn-brood.sh '$plugin_root/skills/_shared' containment.sh)"
    "$(build_std_source_row plugin/skills/spawn-brood/scripts/spawn-brood.sh '$plugin_root/skills/_shared' allowlist.sh)"
    "$(build_std_source_row plugin/skills/spawn-brood/scripts/spawn-brood.sh '$plugin_root/skills/_shared' ledger-project.sh)"
    "$(build_std_source_row plugin/skills/seed-hive/scripts/seed-hive.sh '$shared_dir' containment.sh)"
    'plugin/skills/seed-hive/scripts/seed-hive.sh|$shared_dir/$lib|required shared library missing: skills/_shared/$lib; refusing to proceed|failed to source skills/_shared/$lib (unparseable); refusing to proceed|settings-merge.sh claude-mem-path.sh file-guard.sh test-detect.sh'
    'plugin/skills/github-review-loop/scripts/ledger-reconstruct.sh|$plugin_root/skills/_shared/ledger-reconstruct-parse.sh|missing-shared-lib|unparseable-shared-lib|ledger-reconstruct-parse.sh'
    'plugin/skills/github-review-loop/scripts/ledger-reconstruct.sh|$plugin_root/skills/_shared/ledger-reconstruct-fold.sh|missing-shared-lib|unparseable-shared-lib|ledger-reconstruct-fold.sh'
    'plugin/skills/github-review-loop/scripts/fetch-normalize.sh|$FETCHNORM_CORE|missing-core|unparseable-core|fetch-normalize-core.sh'
)

# ── Table helpers ───────────────────────────────────────────────────────────

# lookup_entry_row <path> -> sets ROW_VAR / ROW_EMITTER / ROW_REASON from ENTRY_ROWS; returns 1 when
# <path> is not an entrypoint row.
lookup_entry_row() {
    local row row_path
    for row in "${ENTRY_ROWS[@]}"; do
        IFS='|' read -r row_path ROW_VAR ROW_EMITTER ROW_REASON <<<"$row"
        [[ "$row_path" == "$1" ]] && return 0
    done
    return 1
}

# list_table_paths -> prints every enrolled path (entrypoints then libraries), one per line.
list_table_paths() {
    local row
    for row in "${ENTRY_ROWS[@]}" "${LIB_ROWS[@]}"; do
        printf '%s\n' "${row%%|*}"
    done
}

# emitter_contract <emitter> -> sets EC_RC / EC_CHANNEL (out|err) / EC_PREFIX for the emitter's
# contracted failure line; returns 1 for an emitter the table does not know.
emitter_contract() {
    case "$1" in
        blocker)          EC_RC=1; EC_CHANNEL=err; EC_PREFIX='blocker: ' ;;
        fail)             EC_RC=2; EC_CHANNEL=err; EC_PREFIX='seed-hive: ' ;;
        die)              EC_RC=1; EC_CHANNEL=err; EC_PREFIX='loop-state: ' ;;
        ledgerrecon_fail) EC_RC=1; EC_CHANNEL=err; EC_PREFIX='LEDGERRECON_ERROR=' ;;
        fetchnorm_fail)   EC_RC=1; EC_CHANNEL=out; EC_PREFIX='FETCHNORM_ERROR=' ;;
        prefilter_fail)   EC_RC=1; EC_CHANNEL=out; EC_PREFIX='PREFILTER_ERROR=' ;;
        *) return 1 ;;
    esac
}

# set_probe_args <path> -> sets PROBE_ARGS to the argv that reaches the bootstrap of <path>
# (everything before C1 must accept it; confirmed by reading each prologue).
set_probe_args() {
    case "$1" in
        */prefilter.sh|*/fetch-normalize.sh) PROBE_ARGS=(owner repo 1 codex-only me) ;;
        */spawn-brood.sh) PROBE_ARGS=("$BROOD_INPUTS_FILE") ;;
        */loop-state.sh) PROBE_ARGS=(floor) ;;
        *) PROBE_ARGS=() ;;
    esac
}

# build_c1_line <var> <tail> -> prints the exact C1/C3 self-location line.
build_c1_line() {
    printf '%s%s%s' "$1" "$C1_BODY" "$2"
}

# count_exact_lines <file> <line> -> prints how many lines of <file> equal <line> exactly.
count_exact_lines() {
    grep -Fxc -- "$2" "$1" || true
}

# first_line_number <file> <exact line> -> prints the 1-based number of the first exact match, or 0.
first_line_number() {
    LINE_TEXT="$2" awk '$0 == ENVIRON["LINE_TEXT"] { print NR; found = 1; exit } END { if (!found) print 0 }' "$1"
}

# replace_exact_line <src> <dst> <old> <new> -> writes <src> to <dst> with the single line equal to
# <old> replaced by <new>; returns non-zero unless exactly one line was replaced.
replace_exact_line() {
    OLD_LINE="$3" NEW_LINE="$4" awk '
        $0 == ENVIRON["OLD_LINE"] { print ENVIRON["NEW_LINE"]; replaced++; next }
        { print }
        END { if (replaced != 1) exit 3 }' "$1" >"$2"
}

# ── Probe machinery ─────────────────────────────────────────────────────────

# install_probe_override <mode> -> defines and EXPORTS the requested override in the CURRENT shell.
# Called only inside a probe subshell, never at the harness top level. Exported functions receive
# `--` first, so the -for variants inspect the LAST argument (${!#}).
install_probe_override() {
    case "$1" in
        none) ;;
        dirname-fail) dirname() { return 1; }; export -f dirname ;;
        dirname-empty) dirname() { return 0; }; export -f dirname ;;
        dirname-fail-for)
            dirname() { case "${!#}" in *"$PROBE_SUFFIX") return 1 ;; esac; command dirname "$@"; }
            export -f dirname ;;
        dirname-empty-for)
            dirname() { case "${!#}" in *"$PROBE_SUFFIX") return 0 ;; esac; command dirname "$@"; }
            export -f dirname ;;
        cd-dotdot)
            cd() { local arg; for arg in "$@"; do case "$arg" in */../*) return 1 ;; esac; done; builtin cd "$@"; }
            export -f cd ;;
        cdpath-decoy) export CDPATH="$DECOY_ROOT" ;;
        *) return 1 ;;
    esac
}

PROBE_SEQ=0

# run_probe <mode> <cwd> <script> [args...] -> runs `bash <script> args` from <cwd> with the stub
# PATH, HOME inside WORKDIR, and the <mode> override. Stdout/stderr land in PROBE_OUT / PROBE_ERR; returns the exit code
# (callers use `|| rc=$?`).
run_probe() {
    local mode="$1" run_cwd="$2" script="$3"
    shift 3
    PROBE_SEQ=$((PROBE_SEQ + 1))
    PROBE_OUT="$PROBE_DIR/$PROBE_SEQ.out"
    PROBE_ERR="$PROBE_DIR/$PROBE_SEQ.err"
    (
        export HOME="$PROBE_HOME" XDG_CONFIG_HOME="$PROBE_HOME/.config"
        cd "$run_cwd" || exit 97
        install_probe_override "$mode" || exit 98
        PATH="$STUB_BIN:$PATH" exec bash "$script" "$@"
    ) >"$PROBE_OUT" 2>"$PROBE_ERR"
}

# describe_probe_output -> prints a one-line summary of the last probe's stdout/stderr.
describe_probe_output() {
    printf 'stdout=%q stderr=%q' "$(head -c 300 "$PROBE_OUT")" "$(head -c 300 "$PROBE_ERR")"
}

# probe_matches_contract <rc> <emitter> <reason> <mode> -> returns 0 when the last probe satisfies
# the emitter's contract for <reason>; otherwise sets CONTRACT_DIAG and returns 1.
#   mode exact: exit code, contracted channel is exactly the one line, other channel empty.
#   mode last:  (unparseable library) stderr emitters: the LAST stderr line is the contracted line
#               and stdout is empty; stdout emitters: stdout is exactly the token, stderr is
#               unconstrained (it carries the bash parse diagnostic — the ADR's accepted residual).
probe_matches_contract() {
    local rc="$1" emitter="$2" reason="$3" mode="$4"
    local expected_line chan_file other_file last_line
    emitter_contract "$emitter" || { CONTRACT_DIAG="unknown emitter '$emitter'"; return 1; }
    expected_line="$EC_PREFIX$reason"
    if [[ "$EC_CHANNEL" == out ]]; then
        chan_file="$PROBE_OUT"; other_file="$PROBE_ERR"
    else
        chan_file="$PROBE_ERR"; other_file="$PROBE_OUT"
    fi
    if [[ "$rc" -ne "$EC_RC" ]]; then
        CONTRACT_DIAG="exit $rc, want $EC_RC; $(describe_probe_output)"
        return 1
    fi
    if [[ "$mode" == last && "$EC_CHANNEL" == err ]]; then
        last_line="$(tail -n 1 "$chan_file")"
        if [[ "$last_line" != "$expected_line" || -s "$other_file" ]]; then
            CONTRACT_DIAG="want last stderr line '$expected_line' and empty stdout; $(describe_probe_output)"
            return 1
        fi
        return 0
    fi
    if ! printf '%s\n' "$expected_line" | cmp -s - "$chan_file"; then
        CONTRACT_DIAG="want exactly '$expected_line' on $EC_CHANNEL; $(describe_probe_output)"
        return 1
    fi
    if [[ "$mode" == exact && -s "$other_file" ]]; then
        CONTRACT_DIAG="other channel not empty; $(describe_probe_output)"
        return 1
    fi
    return 0
}

# assert_contract <name> <rc> <emitter> <reason> <mode>
assert_contract() {
    if probe_matches_contract "$2" "$3" "$4" "$5"; then
        pass "$1" "exit $2 + contracted line"
    else
        failed "$1" "$CONTRACT_DIAG"
    fi
}

# assert_silent_return <name> <rc> <stderr-policy empty|any> -> a C3 library returned 1 with empty
# stdout (and empty stderr unless the policy is `any`).
assert_silent_return() {
    if [[ "$2" -ne 1 || -s "$PROBE_OUT" ]] || [[ "$3" == empty && -s "$PROBE_ERR" ]]; then
        failed "$1" "want exit 1 + silent; got exit $2; $(describe_probe_output)"
    else
        pass "$1" "exit 1, silent"
    fi
}

# make_plugin_copy <name> -> copies the real plugin/ to $WORKDIR/copies/<name>/plugin (cp -a, never a
# symlink) and prints the copy root.
make_plugin_copy() {
    local copy_root="$WORKDIR/copies/$1"
    mkdir -p "$copy_root"
    cp -a "$PLUGIN_ROOT" "$copy_root/plugin"
    printf '%s' "$copy_root"
}

# break_library <lib path> <missing|unparseable> -> removes the library or replaces it with a bash
# syntax error; returns non-zero if the mutation did not take.
break_library() {
    case "$2" in
        missing) rm -f "$1"; [[ ! -e "$1" ]] ;;
        unparseable) printf 'if true; then\n' >"$1"; grep -qx 'if true; then' "$1" ;;
        *) return 1 ;;
    esac
}

# fingerprint_plugin_tree -> prints a checksum listing of every file under the real plugin/.
fingerprint_plugin_tree() {
    (cd "$PLUGIN_ROOT" && find . -type f -print0 | sort -z | xargs -0 cksum)
}

# ── S: static contract ──────────────────────────────────────────────────────

# list_closure_findings <root> -> prints one finding per closure violation under <root>:
# `zero-discovered`, `unenrolled <path>` (self-locating but not a table row), `missing-row <path>`
# (a table row whose file does not exist). Discovery keys on BASH_SOURCE[0] in NON-comment lines of
# git-tracked plugin/**/*.sh — never on dirname, so data-path `cd "$(dirname "$x")"` sites stay out.
list_closure_findings() {
    local root="$1" rel row_path
    local -a discovered=()
    while IFS= read -r -d '' rel; do
        if awk '!/^[[:space:]]*#/ && index($0, "BASH_SOURCE[0]") { hit = 1 } END { exit !hit }' "$root/$rel"; then
            discovered+=("$rel")
        fi
    done < <(git -C "$root" ls-files -z -- 'plugin/*.sh')
    if [[ "${#discovered[@]}" -eq 0 ]]; then
        printf 'zero-discovered\n'
        return 0
    fi
    for rel in "${discovered[@]}"; do
        list_table_paths | grep -Fxq -- "$rel" || printf 'unenrolled %s\n' "$rel"
    done
    while IFS= read -r row_path; do
        [[ -f "$root/$row_path" ]] || printf 'missing-row %s\n' "$row_path"
    done < <(list_table_paths)
}

test_static_closure() {
    local findings
    findings="$(list_closure_findings "$REPO_ROOT")"
    if [[ -z "$findings" ]]; then
        pass s-closure "every self-locating plugin script is enrolled and every row exists"
    else
        failed s-closure "$(printf '%s' "$findings" | tr '\n' ';')"
    fi
}

test_static_c1_lines() {
    local row row_path var emitter reason count
    for row in "${ENTRY_ROWS[@]}"; do
        IFS='|' read -r row_path var emitter reason <<<"$row"
        count="$(count_exact_lines "$REPO_ROOT/$row_path" "$(build_c1_line "$var" "$emitter \"$reason\"")")"
        if [[ "$count" -eq 1 ]]; then
            pass "s-c1 ${row_path##*/}" "exact C1 line once"
        else
            failed "s-c1 ${row_path##*/}" "exact C1 line count $count, want 1"
        fi
    done
}

# check_c3_lines <path> <var> <sibling> -> 0 when the four C3 lines each occur exactly once, in order.
check_c3_lines() {
    local file="$REPO_ROOT/$1" var="$2" sibling="$3"
    local -a c3_lines=(
        "$(build_c1_line "$var" 'return 1')"
        "[ -f \"\$$var/$sibling\" ] || return 1"
        ". \"\$$var/$sibling\" || return 1"
        "unset $var"
    )
    local c3_line previous=0 number
    for c3_line in "${c3_lines[@]}"; do
        [[ "$(count_exact_lines "$file" "$c3_line")" -eq 1 ]] || return 1
        number="$(first_line_number "$file" "$c3_line")"
        [[ "$number" -gt "$previous" ]] || return 1
        previous="$number"
    done
}

test_static_c3_lines() {
    local row row_path var sibling
    for row in "${LIB_ROWS[@]}"; do
        IFS='|' read -r row_path var sibling <<<"$row"
        if check_c3_lines "$row_path" "$var" "$sibling"; then
            pass "s-c3 ${row_path##*/}" "exact C3 block once, in order"
        else
            failed "s-c3 ${row_path##*/}" "C3 block lines missing, duplicated, or out of order"
        fi
    done
}

test_static_no_legacy_idiom() {
    local hits
    hits="$(git -C "$REPO_ROOT" grep -n -F -e "$LEGACY_SELF_LOCATE" -e "$INTERIM_SELF_LOCATE" -- 'plugin/*.sh' || true)"
    if [[ -z "$hits" ]]; then
        pass s-no-legacy "no plugin .sh carries a pre-amendment self-location idiom"
    else
        failed s-no-legacy "$(printf '%s' "$hits" | tr '\n' ';')"
    fi
}

test_static_c2_lines() {
    local row row_path var2 rel reason line count
    for row in "${STAGE2_ROWS[@]}"; do
        IFS='|' read -r row_path var2 rel reason <<<"$row"
        if ! lookup_entry_row "$row_path"; then
            failed "s-c2 ${row_path##*/}" "stage-2 row has no ENTRY_ROWS row"
            continue
        fi
        line="$var2=\"\$(CDPATH= cd -- \"\$$ROW_VAR/$rel\" 2>/dev/null && pwd -P 2>/dev/null)\" || $ROW_EMITTER \"$reason\""
        count="$(count_exact_lines "$REPO_ROOT/$row_path" "$line")"
        if [[ "$count" -eq 1 ]]; then
            pass "s-c2 ${row_path##*/}" "exact C2 line once"
        else
            failed "s-c2 ${row_path##*/}" "exact C2 line count $count, want 1"
        fi
    done
}

# count_c4_pair <file> <missing line> <source line> -> prints "<missing count> <source count>
# <paired count>" with leading whitespace ignored; a pair is the source line as the next
# non-comment line after the missing line.
count_c4_pair() {
    MISS_LINE="$2" SRC_LINE="$3" awk '
        { text = $0; sub(/^[ \t]+/, "", text) }
        text == ENVIRON["SRC_LINE"] { sources++ }
        pending && text !~ /^#/ { if (text == ENVIRON["SRC_LINE"]) paired++; pending = 0 }
        text == ENVIRON["MISS_LINE"] { misses++; pending = 1 }
        END { print misses + 0, sources + 0, paired + 0 }' "$1"
}

test_static_c4_pairs() {
    local row row_path path_expr missing unparseable libs counts
    for row in "${SOURCE_ROWS[@]}"; do
        IFS='|' read -r row_path path_expr missing unparseable libs <<<"$row"
        if ! lookup_entry_row "$row_path"; then
            failed "s-c4 ${row_path##*/} $libs" "source row has no ENTRY_ROWS row"
            continue
        fi
        counts="$(count_c4_pair "$REPO_ROOT/$row_path" \
            "[ -f \"$path_expr\" ] || $ROW_EMITTER \"$missing\"" \
            ". \"$path_expr\" || $ROW_EMITTER \"$unparseable\"")"
        if [[ "$counts" == "1 1 1" ]]; then
            pass "s-c4 ${row_path##*/} $libs" "source-or-die pair present once"
        else
            failed "s-c4 ${row_path##*/} $libs" "missing/source/paired counts $counts, want 1 1 1"
        fi
    done
}

# count_source_lines <file> -> prints "<source lines> <source lines lacking ||>" over non-comment
# `. <path>` / `source <path>` lines (quoted or $-expanded path).
count_source_lines() {
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*(\.|source)[[:space:]]+["$]/ { total++; if (index($0, "||") == 0) bare++ }
        END { print total + 0, bare + 0 }' "$1"
}

test_static_source_census() {
    local row row_path total bare expected source_row
    for row in "${ENTRY_ROWS[@]}" "${LIB_ROWS[@]}"; do
        row_path="${row%%|*}"
        read -r total bare <<<"$(count_source_lines "$REPO_ROOT/$row_path")"
        expected=1
        if lookup_entry_row "$row_path"; then
            expected=0
            for source_row in "${SOURCE_ROWS[@]}"; do
                [[ "${source_row%%|*}" == "$row_path" ]] && expected=$((expected + 1))
            done
        fi
        if [[ "$bare" -eq 0 && "$total" -eq "$expected" ]]; then
            pass "s-source-census ${row_path##*/}" "$total source line(s), all with an || handler, all enrolled"
        else
            failed "s-source-census ${row_path##*/}" "$total source line(s) ($bare without ||), $expected enrolled"
        fi
    done
}

test_static_emitter_order() {
    local row row_path var emitter reason emitter_line c1_line_number
    for row in "${ENTRY_ROWS[@]}"; do
        IFS='|' read -r row_path var emitter reason <<<"$row"
        emitter_line="$(grep -n -E "^${emitter}\(\) *\{" "$REPO_ROOT/$row_path" | head -n 1 | cut -d: -f1 || true)"
        c1_line_number="$(first_line_number "$REPO_ROOT/$row_path" "$(build_c1_line "$var" "$emitter \"$reason\"")")"
        if [[ -n "$emitter_line" && "$c1_line_number" -gt 0 && "$emitter_line" -lt "$c1_line_number" ]]; then
            pass "s-c5 ${row_path##*/}" "$emitter() defined on line $emitter_line, before C1 on line $c1_line_number"
        else
            failed "s-c5 ${row_path##*/}" "$emitter() line '${emitter_line:-none}' not before C1 line $c1_line_number"
        fi
    done
}

# ── R1: dirname fails / prints nothing ──────────────────────────────────────

test_r1_entrypoints() {
    local row row_path var emitter reason script variant rc
    for row in "${ENTRY_ROWS[@]}"; do
        IFS='|' read -r row_path var emitter reason <<<"$row"
        script="$REPO_ROOT/$row_path"
        set_probe_args "$row_path"
        for variant in dirname-fail dirname-empty; do
            rc=0
            run_probe "$variant" "${script%/*}" "$script" ${PROBE_ARGS[@]+"${PROBE_ARGS[@]}"} || rc=$?
            assert_contract "r1-$variant ${row_path##*/}" "$rc" "$emitter" "$reason" exact
            if [[ "$row_path" == */loop-state.sh ]] && grep -qx '6' "$PROBE_OUT"; then
                failed "r1-$variant loop-state-no-floor" "floor printed 6 despite a failed self-location"
            fi
        done
    done
}

test_r1_libraries() {
    local row row_path var sibling lib variant rc
    for row in "${LIB_ROWS[@]}"; do
        IFS='|' read -r row_path var sibling <<<"$row"
        lib="$REPO_ROOT/$row_path"
        rc=0
        run_probe none "${lib%/*}" "$SOURCE_LIB_HELPER" "$lib" || rc=$?
        if [[ "$rc" -eq 0 && ! -s "$PROBE_OUT" && ! -s "$PROBE_ERR" ]]; then
            pass "r1-baseline ${row_path##*/}" "sources cleanly without an override"
        else
            failed "r1-baseline ${row_path##*/}" "exit $rc; $(describe_probe_output)"
        fi
        for variant in dirname-fail dirname-empty; do
            rc=0
            run_probe "$variant" "${lib%/*}" "$SOURCE_LIB_HELPER" "$lib" || rc=$?
            assert_silent_return "r1-$variant ${row_path##*/}" "$rc" empty
        done
    done
}

test_r1_seed_hive_library_chain() {
    local seed_hive="$REPO_ROOT/plugin/skills/seed-hive/scripts/seed-hive.sh"
    local lib variant rc
    for lib in settings-merge.sh claude-mem-path.sh; do
        for variant in dirname-fail-for dirname-empty-for; do
            rc=0
            PROBE_SUFFIX="/$lib" run_probe "$variant" "${seed_hive%/*}" "$seed_hive" || rc=$?
            assert_contract "r1-$variant seed-hive<-$lib" "$rc" fail \
                "failed to source skills/_shared/$lib (unparseable); refusing to proceed" exact
        done
    done
}

# ── R2: cd refuses `/../` (stage 2 fails, stage 1 unaffected) ───────────────

test_r2_stage2() {
    local row row_path var2 rel reason script rc
    for row in "${STAGE2_ROWS[@]}"; do
        IFS='|' read -r row_path var2 rel reason <<<"$row"
        lookup_entry_row "$row_path" || { failed "r2 ${row_path##*/}" "no ENTRY_ROWS row"; continue; }
        script="$REPO_ROOT/$row_path"
        set_probe_args "$row_path"
        rc=0
        run_probe cd-dotdot "${script%/*}" "$script" ${PROBE_ARGS[@]+"${PROBE_ARGS[@]}"} || rc=$?
        assert_contract "r2 ${row_path##*/}" "$rc" "$ROW_EMITTER" "$reason" exact
    done
}

# ── R3/R4: missing / unparseable sourced library (on copies) ────────────────

# probe_broken_library <name> <site path> <lib> <missing|unparseable> <emitter> <reason>
probe_broken_library() {
    local name="$1" row_path="$2" lib="$3" kind="$4" emitter="$5" reason="$6"
    local copy_root script rc=0 mode=exact
    copy_root="$(make_plugin_copy "case-$PROBE_SEQ")"
    if ! break_library "$copy_root/plugin/skills/_shared/$lib" "$kind"; then
        failed "$name" "could not make $lib $kind in the copy"
        rm -rf "$copy_root"
        return 0
    fi
    script="$copy_root/$row_path"
    set_probe_args "$row_path"
    run_probe none "${script%/*}" "$script" ${PROBE_ARGS[@]+"${PROBE_ARGS[@]}"} || rc=$?
    [[ "$kind" == unparseable ]] && mode=last
    assert_contract "$name" "$rc" "$emitter" "$reason" "$mode"
    rm -rf "$copy_root"
}

test_r3_r4_entrypoints() {
    local row row_path path_expr missing unparseable libs lib
    for row in "${SOURCE_ROWS[@]}"; do
        IFS='|' read -r row_path path_expr missing unparseable libs <<<"$row"
        lookup_entry_row "$row_path" || { failed "r3 ${row_path##*/}" "no ENTRY_ROWS row"; continue; }
        for lib in $libs; do
            probe_broken_library "r3-missing ${row_path##*/}<-$lib" "$row_path" "$lib" missing \
                "$ROW_EMITTER" "${missing//'$lib'/$lib}"
            probe_broken_library "r4-unparseable ${row_path##*/}<-$lib" "$row_path" "$lib" unparseable \
                "$ROW_EMITTER" "${unparseable//'$lib'/$lib}"
        done
    done
}

test_r3_r4_libraries() {
    local row row_path var sibling kind copy_root rc stderr_policy
    for row in "${LIB_ROWS[@]}"; do
        IFS='|' read -r row_path var sibling <<<"$row"
        for kind in missing unparseable; do
            copy_root="$(make_plugin_copy "lib-case-$PROBE_SEQ")"
            if ! break_library "$copy_root/plugin/skills/_shared/$sibling" "$kind"; then
                failed "r3r4-$kind ${row_path##*/}<-$sibling" "could not make $sibling $kind in the copy"
                rm -rf "$copy_root"
                continue
            fi
            rc=0
            run_probe none "$copy_root/plugin/skills/_shared" "$SOURCE_LIB_HELPER" "$copy_root/$row_path" || rc=$?
            stderr_policy=empty
            [[ "$kind" == unparseable ]] && stderr_policy=any
            assert_silent_return "r3r4-$kind ${row_path##*/}<-$sibling" "$rc" "$stderr_policy"
            rm -rf "$copy_root"
        done
    done
    probe_broken_library "r3-missing seed-hive<-settings-merge.sh<-json-normalize.sh" \
        plugin/skills/seed-hive/scripts/seed-hive.sh json-normalize.sh missing fail \
        "failed to source skills/_shared/settings-merge.sh (unparseable); refusing to proceed"
    probe_broken_library "r4-unparseable seed-hive<-settings-merge.sh<-json-normalize.sh" \
        plugin/skills/seed-hive/scripts/seed-hive.sh json-normalize.sh unparseable fail \
        "failed to source skills/_shared/settings-merge.sh (unparseable); refusing to proceed"
}

# ── CDPATH neutralisation ───────────────────────────────────────────────────

test_cdpath_decoy() {
    local rc=0
    run_probe cdpath-decoy "$PLUGIN_ROOT" skills/bump-type/scripts/bump-type.sh || rc=$?
    assert_contract "cdpath-decoy bump-type.sh (relative)" "$rc" blocker "$BUMP_TYPE_USAGE_REASON" exact
}

# ── Canaries (self-proof of the checker and the closure) ────────────────────

test_canary_reverted_c1_loop_state() {
    local skeleton="$WORKDIR/canary-loop-state/scripts"
    local source_script="$REPO_ROOT/plugin/skills/github-review-loop/scripts/loop-state.sh"
    local rc=0
    mkdir -p "$skeleton"
    if ! replace_exact_line "$source_script" "$skeleton/loop-state.sh" \
        "$(build_c1_line SCRIPT_DIR "die \"$SELF_LOCATE_REASON\"")" \
        "SCRIPT_DIR=\"\$($LEGACY_SELF_LOCATE && pwd -P)\""; then
        failed canary-loop-state "could not revert C1 in the canary copy"
        return 0
    fi
    run_probe dirname-empty "$skeleton" "$skeleton/loop-state.sh" floor || rc=$?
    if probe_matches_contract "$rc" die "$SELF_LOCATE_REASON" exact; then
        failed canary-loop-state "checker ACCEPTED a reverted (fail-open) C1"
    elif [[ "$rc" -eq 0 ]] && grep -qx '6' "$PROBE_OUT"; then
        pass canary-loop-state "reverted C1 fails open (exit 0, prints 6) and the checker flags it"
    else
        failed canary-loop-state "reverted C1 did not reproduce the fail-open shape; exit $rc; $(describe_probe_output)"
    fi
}

test_canary_reverted_c1_cdpath() {
    local copy_root script rc=0
    copy_root="$(make_plugin_copy canary-cdpath)"
    script="$copy_root/plugin/skills/bump-type/scripts/bump-type.sh"
    if ! replace_exact_line "$PLUGIN_ROOT/skills/bump-type/scripts/bump-type.sh" "$script.reverted" \
        "$(build_c1_line script_dir "blocker \"$SELF_LOCATE_REASON\"")" \
        "script_dir=\"\$($LEGACY_SELF_LOCATE && pwd -P)\""; then
        failed canary-cdpath "could not revert C1 in the canary copy"
        rm -rf "$copy_root"
        return 0
    fi
    mv "$script.reverted" "$script"
    run_probe cdpath-decoy "$copy_root/plugin" skills/bump-type/scripts/bump-type.sh || rc=$?
    if probe_matches_contract "$rc" blocker "$BUMP_TYPE_USAGE_REASON" exact; then
        failed canary-cdpath "checker ACCEPTED a reverted C1 under a decoy CDPATH"
    else
        pass canary-cdpath "reverted C1 is redirected by the decoy CDPATH and the checker flags it"
    fi
    rm -rf "$copy_root"
}

# init_synthetic_root <name> -> creates an empty git checkout under $WORKDIR and prints its path.
init_synthetic_root() {
    local root="$WORKDIR/$1"
    mkdir -p "$root"
    git -C "$root" -c init.defaultBranch=main init -q
    printf '%s' "$root"
}

test_canary_closure() {
    local root findings scripts_dir
    root="$(init_synthetic_root synthetic-root)"
    scripts_dir="$root/plugin/skills/new-skill/scripts"
    mkdir -p "$scripts_dir"
    printf '#!/usr/bin/env bash\nhere="$(dirname -- "${BASH_SOURCE[0]}")"\n' >"$scripts_dir/new-engine.sh"
    printf '#!/usr/bin/env bash\n# only a comment names BASH_SOURCE[0]\n' >"$scripts_dir/comment-only.sh"
    printf '#!/usr/bin/env bash\nledger_dir="$(cd "$(dirname "$ledger")" && pwd -P)"\n' >"$scripts_dir/data-path.sh"
    git -C "$root" add -A
    findings="$(list_closure_findings "$root")"
    if grep -Fxq 'unenrolled plugin/skills/new-skill/scripts/new-engine.sh' <<<"$findings"; then
        pass canary-closure-unenrolled "an unenrolled self-locating script is flagged"
    else
        failed canary-closure-unenrolled "not flagged; findings: $(printf '%s' "$findings" | tr '\n' ';')"
    fi
    if grep -Eq 'comment-only|data-path' <<<"$findings"; then
        failed canary-closure-keying "comment-only or data-path dirname site was enrolled by discovery"
    else
        pass canary-closure-keying "comment-only and data-path dirname sites are not discovered"
    fi
    root="$(init_synthetic_root empty-root)"
    findings="$(list_closure_findings "$root")"
    if [[ "$findings" == zero-discovered ]]; then
        pass canary-closure-empty "zero discovered files is a finding"
    else
        failed canary-closure-empty "findings: $(printf '%s' "$findings" | tr '\n' ';')"
    fi
}

# ── Run ─────────────────────────────────────────────────────────────────────

fingerprint_plugin_tree >"$WORKDIR/plugin-fingerprint.before"

test_static_closure
test_static_c1_lines
test_static_c3_lines
test_static_no_legacy_idiom
test_static_c2_lines
test_static_c4_pairs
test_static_source_census
test_static_emitter_order
test_r1_entrypoints
test_r1_libraries
test_r1_seed_hive_library_chain
test_r2_stage2
test_r3_r4_entrypoints
test_r3_r4_libraries
test_cdpath_decoy
test_canary_reverted_c1_loop_state
test_canary_reverted_c1_cdpath
test_canary_closure

fingerprint_plugin_tree >"$WORKDIR/plugin-fingerprint.after"
if cmp -s "$WORKDIR/plugin-fingerprint.before" "$WORKDIR/plugin-fingerprint.after"; then
    pass real-tree-untouched "the real plugin/ tree is byte-identical after the run"
else
    failed real-tree-untouched "the real plugin/ tree changed during the run"
fi

echo
echo "script bootstrap tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
