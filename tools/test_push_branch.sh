#!/usr/bin/env bash
#
# Behavior test runner for the push-branch engine
# (plugin/skills/push-branch/scripts/push-branch.sh, gate library plugin/skills/_shared/allowlist.sh).
#
# The engine takes REQUIRED `--head <branch> --base <branch>` plus optional `--remote <name>`,
# `--on-reject block|warn`, `--no-upstream block|origin`, and `--expect-commit <sha>`. It refuses
# when the base text or any ref the base names names the current branch, and, with
# --expect-commit, when HEAD is another commit, before any push. It reads the current branch, HEAD,
# the upstream config, and the push remote ONCE, gates every value, then pushes the explicit
# refspec <sha>^{commit}:refs/heads/<b> (the captured commit by object id, never `-u`) and
# (upstream mode only) retries a non-fast-forward once with --force-with-lease on the SAME captured
# values. After a successful push in explicit or origin mode it records branch.<b>.remote and
# branch.<b>.merge itself. On success it prints
#     branch: <b> / commit: <sha> [/ warning: <fixed text>]
# on stdout, exit 0. On any blocker it prints `blocker: <fixed reason>` as the LAST stderr line,
# NOTHING on stdout, exit 1.
#
# DRIFT REGRESSIONS: a client pre-push hook rewrites `branch.<b>.merge` to refs/heads/main,
# repoints HEAD at refs/heads/main, or rewrites the local refs/heads/<b> to the trunk commit, during
# the first (non-fast-forward) push. The retry must still write only refs/heads/<b> with the
# captured branch and SHA, leaving the remote trunk untouched. A procedure that re-read the branch,
# the upstream, or the branch ref between the push and the retry would aim the forced retry at
# trunk or write the trunk commit to the branch.
#
# PUSH SOURCE AND UPSTREAM RECORD: a local ref named after the head SHA (refs/tags/<sha>) must not
# shadow the pushed commit; an origin-mode hook that repoints HEAD must not move the recorded
# upstream off branch.<b>; and a config write that fails after the push blocks with the
# upstream-record reason while the branch stays on its remote.
#
# ISOLATION: the REAL committed engine is run unmodified by absolute path (it self-locates its own
# _shared/ library). Each case builds a THROWAWAY world under a mktemp WORKDIR: local bare repos
# `origin.git` and `other.git` as remotes plus a working checkout `w` on feat/x, so no network and
# no real remote is ever reached. Host git config is excluded: GIT_CONFIG_NOSYSTEM=1, HOME and
# XDG_CONFIG_HOME point into WORKDIR, identity/signing come from `-c` overrides, and
# GIT_CEILING_DIRECTORIES stops discovery from escaping WORKDIR (the not-a-checkout case).
#
# Every success case asserts exit 0 and the FULL stdout block (exact equality, including the
# trailing newline). Every blocker case asserts exit 1, EMPTY stdout, exactly one `blocker:`
# line on stderr, and that line (the last stderr line) equal to the contracted reason.
#
# Prints PASS/FAIL per assertion. Exits non-zero if ANY assertion FAILs.
#
# Usage:
#   ./tools/test_push_branch.sh

set -euo pipefail

# ── Path setup ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ENGINE="$REPO_ROOT/plugin/skills/push-branch/scripts/push-branch.sh"

# ── Dependency / input preflight ────────────────────────────────────────────

command -v git >/dev/null 2>&1 \
    || { echo "FAIL: required dependency 'git' is not installed" >&2; exit 2; }
[[ -f "$ENGINE" ]] \
    || { echo "FAIL: required input missing: $ENGINE" >&2; exit 2; }

# ── Disposable workdir + host-config isolation ──────────────────────────────

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-push-branch-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

mkdir -p "$WORKDIR/home"
export HOME="$WORKDIR/home"
export XDG_CONFIG_HOME="$WORKDIR/home/.config"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$WORKDIR"
export GIT_TERMINAL_PROMPT=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ── Contracted strings (restated from the engine header; a change here is a contract change) ──

BRANCH='feat/x'
USAGE_REASON='invalid arguments; usage: push-branch.sh --head <branch> --base <branch> [--remote <name>] [--on-reject block|warn] [--no-upstream block|origin] [--expect-commit <sha>]'
IDENTIFIER_REASON='head, base, or remote contains characters outside the safe allowlist'
DETACHED_REASON='HEAD is detached'
CURRENT_BRANCH_REASON='current branch contains characters outside the safe allowlist'
MISMATCH_REASON='current branch does not match head or equals base'
NOT_A_CHECKOUT_REASON='not inside a git checkout'
UPSTREAM_REASON='upstream does not match the working branch'
PUSH_REMOTE_GATE_REASON='configured push remote contains characters outside the safe allowlist'
LOCAL_REMOTE_REASON='push remote is the local repository, not a remote'
NO_UPSTREAM_REASON='no upstream and no remote supplied'
REJECTED_REASON='push was rejected'
LEASE_REASON='force-with-lease retry was rejected; the remote has commits this clone has not seen'
UPSTREAM_RECORD_REASON='pushed, but the upstream could not be recorded'
EXPECT_FORMAT_REASON='expected commit is not a full object id'
EXPECT_MISMATCH_REASON='HEAD is not the expected commit'
UNREADABLE_BASE_REASON='cannot read base'
REJECT_WARNING='push was rejected; the branch is not on its remote'
DEFERRED_WARNING='no upstream and no origin remote; push deferred'

# ── World helpers ───────────────────────────────────────────────────────────

# run_git <gitroot> <git args...> -> git with every identity/signing knob pinned by -c overrides.
run_git() {
    local gitroot="$1"
    shift
    git -C "$gitroot" \
        -c user.name=t -c user.email=t@example.invalid \
        -c commit.gpgsign=false -c tag.gpgsign=false \
        -c init.defaultBranch=main -c core.autocrlf=false \
        "$@"
}

# create_world <name> -> builds $WORKDIR/<name>/{origin.git,other.git,w} and sets WORLD_ROOT,
# WORK_TREE, ORIGIN_DIR, OTHER_DIR, TRUNK_SHA. origin carries refs/heads/main (TRUNK_SHA); `w` has
# remotes origin and other, no upstream, and HEAD on feat/x one commit ahead of main (unpushed).
create_world() {
    WORLD_ROOT="$WORKDIR/$1"
    WORK_TREE="$WORLD_ROOT/w"
    ORIGIN_DIR="$WORLD_ROOT/origin.git"
    OTHER_DIR="$WORLD_ROOT/other.git"
    mkdir -p "$WORK_TREE"
    run_git "$WORLD_ROOT" init -q --bare origin.git
    run_git "$ORIGIN_DIR" symbolic-ref HEAD refs/heads/main
    run_git "$WORLD_ROOT" init -q --bare other.git
    run_git "$OTHER_DIR" symbolic-ref HEAD refs/heads/main
    run_git "$WORK_TREE" init -q
    run_git "$WORK_TREE" symbolic-ref HEAD refs/heads/main
    run_git "$WORK_TREE" commit --allow-empty -q -m init
    run_git "$WORK_TREE" remote add origin "$ORIGIN_DIR"
    run_git "$WORK_TREE" remote add other "$OTHER_DIR"
    run_git "$WORK_TREE" push -q origin refs/heads/main:refs/heads/main
    run_git "$WORK_TREE" checkout -q -b "$BRANCH"
    run_git "$WORK_TREE" commit --allow-empty -q -m one
    TRUNK_SHA="$(run_git "$WORK_TREE" rev-parse refs/heads/main)"
}

# publish_branch_with_upstream -> pushes feat/x to origin under its own name and records the
# upstream (origin, refs/heads/feat/x) in config, as a prior successful push would have.
publish_branch_with_upstream() {
    run_git "$WORK_TREE" push -q origin "refs/heads/$BRANCH:refs/heads/$BRANCH"
    set_upstream origin "refs/heads/$BRANCH"
}

# set_upstream <remote> <merge> -> writes branch.feat/x.remote and branch.feat/x.merge.
set_upstream() {
    run_git "$WORK_TREE" config "branch.$BRANCH.remote" "$1"
    run_git "$WORK_TREE" config "branch.$BRANCH.merge" "$2"
}

# advance_branch_elsewhere -> a second clone pushes a new feat/x commit to origin, so the remote
# tip is an object `w` has never seen (a `fetch first` rejection with a stale lease). Sets
# ELSEWHERE_SHA to the new remote tip.
advance_branch_elsewhere() {
    local second_tree="$WORLD_ROOT/w2"
    run_git "$WORLD_ROOT" clone -q "$ORIGIN_DIR" w2
    run_git "$second_tree" checkout -q -b "$BRANCH" "origin/$BRANCH"
    run_git "$second_tree" commit --allow-empty -q -m elsewhere
    run_git "$second_tree" push -q origin "refs/heads/$BRANCH:refs/heads/$BRANCH"
    ELSEWHERE_SHA="$(run_git "$second_tree" rev-parse HEAD)"
}

# install_pre_push_hook [extra shell line] -> client pre-push hook in `w` that appends one line to
# $WORLD_ROOT/pre-push.log per push attempt, then runs the optional extra line (the drift).
install_pre_push_hook() {
    local hook_path="$WORK_TREE/.git/hooks/pre-push"
    printf '#!/bin/sh\necho ran >>'"'"'%s'"'"'\n%s\nexit 0\n' "$WORLD_ROOT/pre-push.log" "${1:-:}" >"$hook_path"
    chmod +x "$hook_path"
}

# install_reject_hook <bare repo> -> server pre-receive hook that rejects every push.
install_reject_hook() {
    local hook_path="$1/hooks/pre-receive"
    printf '#!/bin/sh\necho denied >&2\nexit 1\n' >"$hook_path"
    chmod +x "$hook_path"
}

# count_push_attempts -> prints how many times the pre-push hook ran in the current world.
count_push_attempts() {
    local log_path="$WORLD_ROOT/pre-push.log"
    if [[ -f "$log_path" ]]; then
        wc -l <"$log_path" | tr -d ' '
    else
        printf '0'
    fi
}

# list_remote_refs <bare repo> -> prints `<refname> <sha>` for every ref, sorted by refname.
list_remote_refs() {
    git --git-dir="$1" for-each-ref --format='%(refname) %(objectname)'
}

# head_sha -> prints the full sha of HEAD in `w`.
head_sha() {
    run_git "$WORK_TREE" rev-parse HEAD
}

# read_branch_config <key suffix> -> prints branch.feat/x.<suffix> in `w`, or nothing when unset.
read_branch_config() {
    run_git "$WORK_TREE" config --get "branch.$BRANCH.$1" || true
}

# ── Engine helpers ───────────────────────────────────────────────────────────

# run_engine <cwd> <out-var> <err-file> <engine args...> -> sets <out-var> to stdout (exact,
# trailing newlines preserved), writes stderr to <err-file>, returns the engine's exit code
# (never trips errexit — called via `|| rc=$?`).
# shellcheck disable=SC2034
run_engine() {
    local run_cwd="$1" __outvar="$2" errfile="$3"
    shift 3
    local __out rc=0
    __out="$(cd "$run_cwd" || exit 97
        engine_rc=0
        bash "$ENGINE" "$@" 2>"$errfile" || engine_rc=$?
        printf 'x'
        exit "$engine_rc")" || rc=$?
    printf -v "$__outvar" '%s' "${__out%x}"
    return "$rc"
}

# assert_success <name> <cwd> <sha> <warning or empty> <engine args...>
# Runs the engine, asserts exit 0 and stdout exactly the routing block for feat/x at <sha>.
assert_success() {
    local name="$1" run_cwd="$2" sha="$3" warning="$4"
    shift 4
    local errfile="$WORKDIR/$name.err" out rc=0 expected
    printf -v expected 'branch: %s\ncommit: %s\n' "$BRANCH" "$sha"
    if [[ -n "$warning" ]]; then
        printf -v expected '%swarning: %s\n' "$expected" "$warning"
    fi
    run_engine "$run_cwd" out "$errfile" "$@" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        failed "$name" "expected exit 0, got $rc (stderr: $(tail -n 3 "$errfile" | tr '\n' '|'))"
        return 0
    fi
    if [[ "$out" == "$expected" ]]; then
        pass "$name" "$(printf '%s' "$out" | tr '\n' '|')"
    else
        failed "$name" "stdout mismatch; expected: $(printf '%s' "$expected" | tr '\n' '|') actual: $(printf '%s' "$out" | tr '\n' '|')"
    fi
}

# assert_blocker <name> <cwd> <reason> <engine args...>
# Runs the engine, asserts exit 1, EMPTY stdout, exactly one `blocker:` stderr line, and the last
# stderr line equal to `blocker: <reason>`.
assert_blocker() {
    local name="$1" run_cwd="$2" reason="$3"
    shift 3
    local errfile="$WORKDIR/$name.err" out rc=0 last_err_line blocker_lines
    run_engine "$run_cwd" out "$errfile" "$@" || rc=$?
    if [[ "$rc" -ne 1 ]]; then
        failed "$name" "expected exit 1, got $rc (stdout: $(printf '%s' "$out" | tr '\n' '|'))"
        return 0
    fi
    if [[ -n "$out" ]]; then
        failed "$name" "expected empty stdout on blocker, got: $(printf '%s' "$out" | tr '\n' '|')"
        return 0
    fi
    last_err_line="$(tail -n 1 "$errfile")"
    blocker_lines="$(grep -c '^blocker: ' "$errfile" || true)"
    if [[ "$last_err_line" == "blocker: $reason" && "$blocker_lines" -eq 1 ]]; then
        pass "$name" "$last_err_line"
    else
        failed "$name" "expected one stderr line 'blocker: $reason' last; got $blocker_lines blocker line(s), last: $last_err_line"
    fi
}

# assert_equal <name> <expected> <actual> <what>
assert_equal() {
    if [[ "$2" == "$3" ]]; then
        pass "$1" "$4"
    else
        failed "$1" "$4; expected: $(printf '%s' "$2" | tr '\n' '|') actual: $(printf '%s' "$3" | tr '\n' '|')"
    fi
}

# assert_remote_refs <name> <bare repo> <expected listing>
assert_remote_refs() {
    assert_equal "$1" "$3" "$(list_remote_refs "$2")" "remote refs of ${2##*/}"
}

# trunk_only_listing -> prints the listing of a remote that carries only main at TRUNK_SHA.
trunk_only_listing() {
    printf 'refs/heads/main %s' "$TRUNK_SHA"
}

# branch_and_trunk_listing <branch sha> -> prints the listing of a remote carrying feat/x at
# <branch sha> and main at TRUNK_SHA (for-each-ref order: feat/x sorts before main).
branch_and_trunk_listing() {
    printf 'refs/heads/%s %s\nrefs/heads/main %s' "$BRANCH" "$1" "$TRUNK_SHA"
}

# ── Usage errors ─────────────────────────────────────────────────────────────

test_usage_errors() {
    create_world usage
    assert_blocker usage-no-args "$WORK_TREE" "$USAGE_REASON"
    assert_blocker usage-unknown-flag "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH" --base main --force yes
    assert_blocker usage-duplicate-head "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH" --head "$BRANCH" --base main
    assert_blocker usage-duplicate-remote "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH" --base main --remote origin --remote origin
    assert_blocker usage-missing-value "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH" --base
    assert_blocker usage-missing-head "$WORK_TREE" "$USAGE_REASON" \
        --base main
    assert_blocker usage-missing-base "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH"
    assert_blocker usage-positional "$WORK_TREE" "$USAGE_REASON" \
        "$BRANCH" main
    assert_blocker usage-bad-on-reject "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH" --base main --on-reject maybe
    assert_blocker usage-bad-no-upstream "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH" --base main --no-upstream yes
    assert_remote_refs usage-nothing-pushed "$ORIGIN_DIR" "$(trunk_only_listing)"
}

# ── Identifier gate (head, base, remote) ─────────────────────────────────────

test_identifier_gate() {
    create_world gate
    local marker="$WORLD_ROOT/injected"
    local -a value_names=(dollar-paren backtick dotdot leading-dash empty)
    local -a bad_values=("\$(touch $marker)" "\`touch $marker\`" 'feat/../x' '-x' '')
    local index value_name bad_value
    for index in "${!bad_values[@]}"; do
        value_name="${value_names[$index]}"
        bad_value="${bad_values[$index]}"
        assert_blocker "gate-head-$value_name" "$WORK_TREE" "$IDENTIFIER_REASON" \
            --head "$bad_value" --base main
        assert_blocker "gate-base-$value_name" "$WORK_TREE" "$IDENTIFIER_REASON" \
            --head "$BRANCH" --base "$bad_value"
        assert_blocker "gate-remote-$value_name" "$WORK_TREE" "$IDENTIFIER_REASON" \
            --head "$BRANCH" --base main --remote "$bad_value"
    done
    if [[ -e "$marker" ]]; then
        failed gate-no-side-effect "a gated value was expanded: $marker exists"
    else
        pass gate-no-side-effect "no gated value was expanded"
    fi
    assert_remote_refs gate-nothing-pushed "$ORIGIN_DIR" "$(trunk_only_listing)"
}

# ── Branch state ─────────────────────────────────────────────────────────────

test_branch_state() {
    local not_a_checkout="$WORKDIR/not-a-checkout"
    mkdir -p "$not_a_checkout"
    assert_blocker not-a-checkout "$not_a_checkout" "$NOT_A_CHECKOUT_REASON" \
        --head "$BRANCH" --base main

    create_world branch-state
    assert_blocker head-mismatch "$WORK_TREE" "$MISMATCH_REASON" \
        --head feat/y --base main
    assert_blocker head-equals-base "$WORK_TREE" "$MISMATCH_REASON" \
        --head "$BRANCH" --base "$BRANCH"
    run_git "$WORK_TREE" checkout -q main
    assert_blocker on-trunk "$WORK_TREE" "$MISMATCH_REASON" \
        --head main --base main --remote origin
    run_git "$WORK_TREE" checkout -q --detach "$BRANCH"
    assert_blocker detached-head "$WORK_TREE" "$DETACHED_REASON" \
        --head "$BRANCH" --base main --remote origin
    run_git "$WORK_TREE" checkout -q -b 'feat/a$b'
    assert_blocker current-branch-outside-allowlist "$WORK_TREE" "$CURRENT_BRANCH_REASON" \
        --head "$BRANCH" --base main --remote origin
    assert_remote_refs branch-state-nothing-pushed "$ORIGIN_DIR" "$(trunk_only_listing)"
}

# ── Base names the current branch ────────────────────────────────────────────

# The base stop keys on ref identity, not on spelling. Base stops only when one of git's six
# lookup candidates for it, or the end a candidate resolves to, is refs/heads/<b> or
# refs/remotes/<remote>/<b> for a remote `git remote` lists, compared exactly after an ASCII case
# fold. So every git qualifier of the branch, in any case, a symbolic ref whose chain ends at the
# branch (dangling or not), and a remote HEAD alias all stop with nothing pushed, while a base that
# only ends with `/<b>` passes. A stop that compares spelling only lets every refusal case here
# through to the push.
test_base_any_spelling() {
    local index spelling_name base_spelling
    local -a spelling_names=(refs-heads heads origin refs-remotes-origin upper-case mixed-case refs-heads-case)
    local -a base_spellings=("refs/heads/$BRANCH" "heads/$BRANCH" "origin/$BRANCH" \
        "refs/remotes/origin/$BRANCH" 'FEAT/X' 'Feat/x' 'Refs/Heads/Feat/X')
    create_world base-spelling
    install_pre_push_hook
    for index in "${!base_spellings[@]}"; do
        spelling_name="${spelling_names[$index]}"
        base_spelling="${base_spellings[$index]}"
        assert_blocker "base-spelling-$spelling_name" "$WORK_TREE" "$MISMATCH_REASON" \
            --head "$BRANCH" --base "$base_spelling" --remote origin
    done
    run_git "$WORK_TREE" symbolic-ref refs/heads/release "refs/heads/$BRANCH"
    assert_blocker base-symbolic-alias "$WORK_TREE" "$MISMATCH_REASON" \
        --head "$BRANCH" --base release --remote origin
    run_git "$WORK_TREE" symbolic-ref refs/heads/legacy refs/heads/release
    assert_blocker base-symbolic-chain "$WORK_TREE" "$MISMATCH_REASON" \
        --head "$BRANCH" --base legacy --remote origin
    run_git "$WORK_TREE" symbolic-ref refs/heads/upper refs/heads/FEAT/X
    assert_blocker base-symbolic-alias-dangling-case "$WORK_TREE" "$MISMATCH_REASON" \
        --head "$BRANCH" --base upper --remote origin
    run_git "$WORK_TREE" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$BRANCH"
    assert_blocker base-remote-head-alias "$WORK_TREE" "$MISMATCH_REASON" \
        --head "$BRANCH" --base origin --remote origin
    assert_blocker base-unreadable "$WORK_TREE" "$UNREADABLE_BASE_REASON" \
        --head "$BRANCH" --base main.lock --remote origin
    assert_equal base-refusals-no-push 0 "$(count_push_attempts)" "push attempts"
    assert_remote_refs base-refusals-nothing-pushed "$ORIGIN_DIR" "$(trunk_only_listing)"
}

# A base that names other refs passes: a branch that only ends with the base name, a base that
# names more than one ref (a tag and a branch), and a symbolic alias whose chain ends elsewhere.
test_base_names_other_refs() {
    local sha out rc=0 expected
    create_world base-trunk-suffix
    run_git "$WORK_TREE" checkout -q -b feat/main
    sha="$(head_sha)"
    printf -v expected 'branch: feat/main\ncommit: %s\n' "$sha"
    run_engine "$WORK_TREE" out "$WORKDIR/base-trunk-suffix.err" \
        --head feat/main --base main --remote origin || rc=$?
    assert_equal base-trunk-suffix-exit 0 "$rc" "exit code"
    assert_equal base-trunk-suffix-passes "$expected" "$out" "stdout"
    assert_remote_refs base-trunk-suffix-pushed "$ORIGIN_DIR" \
        "$(printf 'refs/heads/feat/main %s\nrefs/heads/main %s' "$sha" "$TRUNK_SHA")"

    create_world base-ambiguous
    sha="$(head_sha)"
    run_git "$WORK_TREE" tag main refs/heads/main
    assert_success base-ambiguous-passes "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base main --remote origin
    assert_remote_refs base-ambiguous-pushed "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"

    create_world base-alias-elsewhere
    sha="$(head_sha)"
    run_git "$WORK_TREE" symbolic-ref refs/heads/trunk-alias refs/heads/main
    assert_success base-alias-elsewhere-passes "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base trunk-alias --remote origin
    assert_remote_refs base-alias-elsewhere-pushed "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"
}

# assert_base_passes <name> <base> -> in the current world, asserts the engine pushes feat/x at
# HEAD with --base <base> --remote origin, and that origin then carries feat/x and main.
assert_base_passes() {
    local name="$1" base_spelling="$2" sha
    sha="$(head_sha)"
    assert_success "$name-passes" "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base "$base_spelling" --remote origin
    assert_remote_refs "$name-pushed" "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"
}

# A base names the current branch only by ref identity. A base whose text ends with `/<b>` but
# whose lookup candidates and their ends are other refs passes: the PR #421 repro (on main,
# --base team/main with refs/heads/team/main present), an absent base, a refs/heads/ spelling of
# another branch, a symbolic alias to another branch, and a stray remote-tracking ref under a
# name `git remote` does not list. A stop that matches the text suffix refuses every case here.
test_base_ref_identity_passes() {
    local sha out rc=0 expected
    create_world base-identity-codex-repro
    run_git "$WORK_TREE" checkout -q main
    run_git "$WORK_TREE" branch team/main
    run_git "$WORK_TREE" commit --allow-empty -q -m on-main
    sha="$(head_sha)"
    printf -v expected 'branch: main\ncommit: %s\n' "$sha"
    run_engine "$WORK_TREE" out "$WORKDIR/base-identity-codex-repro.err" \
        --head main --base team/main --remote origin || rc=$?
    assert_equal base-identity-codex-repro-exit 0 "$rc" "exit code"
    assert_equal base-identity-codex-repro-passes "$expected" "$out" "stdout"
    assert_remote_refs base-identity-codex-repro-pushed "$ORIGIN_DIR" "refs/heads/main $sha"

    create_world base-identity-absent
    assert_base_passes base-identity-absent "release/$BRANCH"

    create_world base-identity-refs-heads-other
    run_git "$WORK_TREE" branch "team/$BRANCH"
    assert_base_passes base-identity-refs-heads-other "refs/heads/team/$BRANCH"

    create_world base-identity-alias-other
    run_git "$WORK_TREE" branch "team/$BRANCH"
    run_git "$WORK_TREE" symbolic-ref refs/heads/trunk-alias "refs/heads/team/$BRANCH"
    assert_base_passes base-identity-alias-other trunk-alias

    create_world base-identity-stray-remote-ref
    run_git "$WORK_TREE" update-ref "refs/remotes/gone/$BRANCH" "$TRUNK_SHA"
    assert_base_passes base-identity-stray-remote-ref "gone/$BRANCH"
}

# A base that names the branch's image on a remote `git remote` lists stops with nothing pushed:
# a configured remote other than the push remote, a remotes/ spelling, a case variant, a remote
# added under a name that only looked like a branch prefix, and a remote name that contains `/`.
test_base_remote_image_refused() {
    local index spelling_name base_spelling
    local -a spelling_names=(other-remote remotes-origin case-folded)
    local -a base_spellings=("other/$BRANCH" "remotes/origin/$BRANCH" 'Origin/Feat/X')
    create_world base-remote-image
    install_pre_push_hook
    for index in "${!base_spellings[@]}"; do
        spelling_name="${spelling_names[$index]}"
        base_spelling="${base_spellings[$index]}"
        assert_blocker "base-remote-image-$spelling_name" "$WORK_TREE" "$MISMATCH_REASON" \
            --head "$BRANCH" --base "$base_spelling" --remote origin
    done
    run_git "$WORK_TREE" remote add team "$WORLD_ROOT/team.git"
    assert_blocker base-remote-image-added-remote "$WORK_TREE" "$MISMATCH_REASON" \
        --head "$BRANCH" --base "team/$BRANCH" --remote origin
    run_git "$WORK_TREE" remote add up/stream "$WORLD_ROOT/upstream.git"
    assert_blocker base-remote-image-slash-remote "$WORK_TREE" "$MISMATCH_REASON" \
        --head "$BRANCH" --base "up/stream/$BRANCH" --remote origin
    assert_equal base-remote-image-no-push 0 "$(count_push_attempts)" "push attempts"
    assert_remote_refs base-remote-image-origin-unchanged "$ORIGIN_DIR" "$(trunk_only_listing)"
    assert_remote_refs base-remote-image-other-unchanged "$OTHER_DIR" ''
}

# ── Expected commit (--expect-commit) ────────────────────────────────────────

# The engine pushes only when HEAD is the commit the caller's gates held for. The value must be
# a full 40- or 64-digit lowercase hex object id, checked before any git command, and HEAD is
# compared with it in the same process as the push, so a refusal pushes nothing.
test_expect_commit() {
    local sha upper_sha index malformed_name
    create_world expect-commit
    sha="$(head_sha)"
    upper_sha="$(printf '%s' "$sha" | tr 'a-f' 'A-F')"
    install_pre_push_hook
    assert_blocker expect-commit-duplicate "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH" --base main --remote origin --expect-commit "$sha" --expect-commit "$sha"
    assert_blocker expect-commit-missing-value "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH" --base main --remote origin --expect-commit
    local -a malformed_names=(short one-short one-long upper-case non-hex empty ref-name)
    local -a malformed_values=("${sha:0:12}" "${sha:0:39}" "${sha}0" "$upper_sha" \
        "${sha:0:39}g" '' HEAD)
    for index in "${!malformed_values[@]}"; do
        malformed_name="${malformed_names[$index]}"
        assert_blocker "expect-commit-malformed-$malformed_name" "$WORK_TREE" "$EXPECT_FORMAT_REASON" \
            --head "$BRANCH" --base main --remote origin --expect-commit "${malformed_values[$index]}"
    done
    assert_blocker expect-commit-mismatch "$WORK_TREE" "$EXPECT_MISMATCH_REASON" \
        --head "$BRANCH" --base main --remote origin --expect-commit "$TRUNK_SHA"
    assert_blocker expect-commit-mismatch-64 "$WORK_TREE" "$EXPECT_MISMATCH_REASON" \
        --head "$BRANCH" --base main --remote origin --expect-commit "${sha}${sha:0:24}"
    assert_equal expect-commit-refusals-no-push 0 "$(count_push_attempts)" "push attempts"
    assert_remote_refs expect-commit-refusals-nothing-pushed "$ORIGIN_DIR" "$(trunk_only_listing)"

    assert_success expect-commit-match "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base main --remote origin --expect-commit "$sha"
    assert_equal expect-commit-match-pushed-once 1 "$(count_push_attempts)" "push attempts"
    assert_remote_refs expect-commit-match-writes-commit "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"
}

# ── Explicit mode (--remote) ─────────────────────────────────────────────────

test_explicit_sets_upstream() {
    local sha
    create_world explicit-first
    sha="$(head_sha)"
    assert_success explicit-sets-upstream "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base main --remote origin
    assert_remote_refs explicit-writes-own-name "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"
    assert_equal explicit-upstream-remote origin "$(read_branch_config remote)" "branch.$BRANCH.remote"
    assert_equal explicit-upstream-merge "refs/heads/$BRANCH" "$(read_branch_config merge)" "branch.$BRANCH.merge"
}

test_explicit_non_ff_no_retry() {
    local published_sha
    create_world explicit-non-ff
    publish_branch_with_upstream
    published_sha="$(head_sha)"
    run_git "$WORK_TREE" commit --amend --allow-empty -q -m one-amended
    install_pre_push_hook
    assert_blocker explicit-non-ff-blocks "$WORK_TREE" "$REJECTED_REASON" \
        --head "$BRANCH" --base main --remote origin
    assert_equal explicit-non-ff-no-retry 1 "$(count_push_attempts)" "push attempts"
    assert_remote_refs explicit-non-ff-remote-unchanged "$ORIGIN_DIR" "$(branch_and_trunk_listing "$published_sha")"
}

test_explicit_rejections() {
    create_world explicit-reject
    install_reject_hook "$ORIGIN_DIR"
    assert_blocker explicit-reject-blocks "$WORK_TREE" "$REJECTED_REASON" \
        --head "$BRANCH" --base main --remote origin
    assert_blocker explicit-reject-warn-still-blocks "$WORK_TREE" "$REJECTED_REASON" \
        --head "$BRANCH" --base main --remote origin --on-reject warn
    assert_blocker explicit-unknown-remote "$WORK_TREE" "$REJECTED_REASON" \
        --head "$BRANCH" --base main --remote nosuch
    assert_blocker explicit-dot-remote "$WORK_TREE" "$LOCAL_REMOTE_REASON" \
        --head "$BRANCH" --base main --remote .
    assert_remote_refs explicit-reject-remote-unchanged "$ORIGIN_DIR" "$(trunk_only_listing)"
    assert_equal explicit-reject-no-upstream-written '' "$(read_branch_config remote)" "branch.$BRANCH.remote"
}

# ── Upstream mode ────────────────────────────────────────────────────────────

test_upstream_own_name() {
    local sha
    create_world upstream-own-name
    publish_branch_with_upstream
    run_git "$WORK_TREE" commit --allow-empty -q -m two
    sha="$(head_sha)"
    assert_success upstream-push "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base main
    assert_remote_refs upstream-push-writes-own-name "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"
}

test_upstream_non_ff_lease_succeeds() {
    local sha
    create_world upstream-non-ff
    publish_branch_with_upstream
    run_git "$WORK_TREE" commit --amend --allow-empty -q -m one-amended
    sha="$(head_sha)"
    install_pre_push_hook
    assert_success upstream-non-ff-lease-succeeds "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base main
    assert_equal upstream-non-ff-retried 2 "$(count_push_attempts)" "push attempts"
    assert_remote_refs upstream-non-ff-remote-updated "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"
}

test_upstream_fetch_first_lease_blocks() {
    create_world upstream-fetch-first
    publish_branch_with_upstream
    advance_branch_elsewhere
    run_git "$WORK_TREE" commit --allow-empty -q -m local-only
    install_pre_push_hook
    assert_blocker upstream-fetch-first-lease-blocks "$WORK_TREE" "$LEASE_REASON" \
        --head "$BRANCH" --base main
    assert_equal upstream-fetch-first-retried 2 "$(count_push_attempts)" "push attempts"
    assert_blocker upstream-fetch-first-warn-still-blocks "$WORK_TREE" "$LEASE_REASON" \
        --head "$BRANCH" --base main --on-reject warn
    assert_equal upstream-fetch-first-warn-retried 4 "$(count_push_attempts)" "push attempts"
    assert_remote_refs upstream-fetch-first-remote-unchanged "$ORIGIN_DIR" "$(branch_and_trunk_listing "$ELSEWHERE_SHA")"
}

test_upstream_mismatch() {
    create_world upstream-mismatch
    set_upstream origin refs/heads/main
    install_pre_push_hook
    assert_blocker upstream-merge-is-trunk "$WORK_TREE" "$UPSTREAM_REASON" \
        --head "$BRANCH" --base main
    assert_equal upstream-merge-is-trunk-no-push 0 "$(count_push_attempts)" "push attempts"
    assert_remote_refs upstream-merge-is-trunk-remote-unchanged "$ORIGIN_DIR" "$(trunk_only_listing)"

    run_git "$WORK_TREE" config --unset "branch.$BRANCH.merge"
    assert_blocker upstream-half-set-remote-only "$WORK_TREE" "$UPSTREAM_REASON" \
        --head "$BRANCH" --base main
    run_git "$WORK_TREE" config --unset "branch.$BRANCH.remote"
    run_git "$WORK_TREE" config "branch.$BRANCH.merge" "refs/heads/$BRANCH"
    assert_blocker upstream-half-set-merge-only "$WORK_TREE" "$UPSTREAM_REASON" \
        --head "$BRANCH" --base main
    set_upstream https://example.invalid/repo.git "refs/heads/$BRANCH"
    assert_blocker upstream-url-remote "$WORK_TREE" "$UPSTREAM_REASON" \
        --head "$BRANCH" --base main
    set_upstream . "refs/heads/$BRANCH"
    assert_blocker upstream-dot-remote "$WORK_TREE" "$LOCAL_REMOTE_REASON" \
        --head "$BRANCH" --base main
    set_upstream origin "refs/heads/$BRANCH"
    run_git "$WORK_TREE" config "branch.$BRANCH.pushRemote" -evil
    assert_blocker upstream-push-remote-gate "$WORK_TREE" "$PUSH_REMOTE_GATE_REASON" \
        --head "$BRANCH" --base main
    run_git "$WORK_TREE" config --unset "branch.$BRANCH.pushRemote"
    run_git "$WORK_TREE" config remote.pushDefault 'a..b'
    assert_blocker upstream-push-default-gate "$WORK_TREE" "$PUSH_REMOTE_GATE_REASON" \
        --head "$BRANCH" --base main
    assert_equal upstream-gates-no-push 0 "$(count_push_attempts)" "push attempts"
    assert_remote_refs upstream-gates-remote-unchanged "$ORIGIN_DIR" "$(trunk_only_listing)"
}

test_triangular_push_remote() {
    local sha
    create_world triangular-push-remote
    set_upstream origin "refs/heads/$BRANCH"
    run_git "$WORK_TREE" config "branch.$BRANCH.pushRemote" other
    sha="$(head_sha)"
    assert_success triangular-push-remote "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base main
    assert_remote_refs triangular-push-remote-writes-other "$OTHER_DIR" "refs/heads/$BRANCH $sha"
    assert_remote_refs triangular-push-remote-origin-untouched "$ORIGIN_DIR" "$(trunk_only_listing)"
}

test_triangular_push_default() {
    local sha
    create_world triangular-push-default
    set_upstream origin "refs/heads/$BRANCH"
    run_git "$WORK_TREE" config remote.pushDefault other
    sha="$(head_sha)"
    assert_success triangular-push-default "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base main
    assert_remote_refs triangular-push-default-writes-other "$OTHER_DIR" "refs/heads/$BRANCH $sha"
    assert_remote_refs triangular-push-default-origin-untouched "$ORIGIN_DIR" "$(trunk_only_listing)"
}

# ── Drift regressions: config/HEAD/branch ref rewritten between the push and the retry ──

# run_drift_case <name> <hook drift line> -> the first push is non-fast-forward (local amend after
# publish); the pre-push hook applies the drift on every attempt. The retry must write only
# refs/heads/feat/x with the captured branch and SHA; origin main stays at TRUNK_SHA.
run_drift_case() {
    local name="$1" drift_line="$2" sha
    create_world "$name"
    publish_branch_with_upstream
    run_git "$WORK_TREE" commit --amend --allow-empty -q -m one-amended
    sha="$(head_sha)"
    install_pre_push_hook "$drift_line"
    assert_success "$name" "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base main
    assert_equal "$name-retried" 2 "$(count_push_attempts)" "push attempts (first push + lease retry)"
    assert_remote_refs "$name-trunk-untouched" "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"
}

test_drift_merge_rewrite() {
    run_drift_case drift-merge-rewrite "git config branch.$BRANCH.merge refs/heads/main"
    assert_equal drift-merge-rewrite-took-effect refs/heads/main "$(read_branch_config merge)" \
        "hook rewrote branch.$BRANCH.merge"
}

test_drift_head_repoint() {
    run_drift_case drift-head-repoint 'git symbolic-ref HEAD refs/heads/main'
    assert_equal drift-head-repoint-took-effect refs/heads/main \
        "$(run_git "$WORK_TREE" symbolic-ref HEAD)" "hook repointed HEAD"
}

test_drift_branch_ref_rewrite() {
    run_drift_case drift-branch-ref-rewrite "git update-ref refs/heads/$BRANCH \$(git rev-parse refs/heads/main)"
    assert_equal drift-branch-ref-rewrite-took-effect "$TRUNK_SHA" \
        "$(run_git "$WORK_TREE" rev-parse "refs/heads/$BRANCH")" "hook rewrote refs/heads/$BRANCH"
}

# ── Push source and upstream record ──────────────────────────────────────────

test_source_shadow_ref() {
    local sha
    create_world source-shadow-ref
    sha="$(head_sha)"
    run_git "$WORK_TREE" update-ref "refs/tags/$sha" "$TRUNK_SHA"
    assert_success source-shadow-ref "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base main --remote origin
    assert_remote_refs source-shadow-ref-writes-commit "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"
}

test_origin_head_repoint_upstream() {
    create_world origin-head-repoint-upstream
    install_pre_push_hook 'git symbolic-ref HEAD refs/heads/main'
    assert_success origin-head-repoint-upstream "$WORK_TREE" "$(head_sha)" '' \
        --head "$BRANCH" --base main --no-upstream origin
    assert_equal origin-head-repoint-upstream-remote origin "$(read_branch_config remote)" "branch.$BRANCH.remote"
    assert_equal origin-head-repoint-upstream-merge "refs/heads/$BRANCH" "$(read_branch_config merge)" "branch.$BRANCH.merge"
    assert_equal origin-head-repoint-upstream-trunk-untouched '' \
        "$(run_git "$WORK_TREE" config --get branch.main.remote || true)" "branch.main.remote"
}

test_explicit_upstream_record_fails() {
    local sha
    create_world explicit-upstream-record-fails
    sha="$(head_sha)"
    install_pre_push_hook "touch '$WORK_TREE/.git/config.lock'"
    assert_blocker explicit-upstream-record-fails-blocks "$WORK_TREE" "$UPSTREAM_RECORD_REASON" \
        --head "$BRANCH" --base main --remote origin
    assert_remote_refs explicit-upstream-record-fails-pushed "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"
    assert_equal explicit-upstream-record-fails-unrecorded '' "$(read_branch_config remote)" "branch.$BRANCH.remote"
}

# ── Server-side rejection (--on-reject) ──────────────────────────────────────

test_upstream_rejection() {
    create_world upstream-reject
    set_upstream origin "refs/heads/$BRANCH"
    install_reject_hook "$ORIGIN_DIR"
    assert_blocker upstream-reject-blocks "$WORK_TREE" "$REJECTED_REASON" \
        --head "$BRANCH" --base main
    assert_blocker upstream-reject-block-explicit "$WORK_TREE" "$REJECTED_REASON" \
        --head "$BRANCH" --base main --on-reject block
    assert_success upstream-reject-warn "$WORK_TREE" "$(head_sha)" "$REJECT_WARNING" \
        --head "$BRANCH" --base main --on-reject warn
    assert_remote_refs upstream-reject-remote-unchanged "$ORIGIN_DIR" "$(trunk_only_listing)"
}

test_origin_rejection() {
    create_world origin-reject
    install_reject_hook "$ORIGIN_DIR"
    assert_blocker origin-reject-blocks "$WORK_TREE" "$REJECTED_REASON" \
        --head "$BRANCH" --base main --no-upstream origin
    assert_success origin-reject-warn "$WORK_TREE" "$(head_sha)" "$REJECT_WARNING" \
        --head "$BRANCH" --base main --no-upstream origin --on-reject warn
    assert_remote_refs origin-reject-remote-unchanged "$ORIGIN_DIR" "$(trunk_only_listing)"
    assert_equal origin-reject-no-upstream-written '' "$(read_branch_config remote)" "branch.$BRANCH.remote"
}

# ── No upstream (--no-upstream) ──────────────────────────────────────────────

test_no_upstream_block() {
    create_world no-upstream-block
    assert_blocker no-upstream-default-blocks "$WORK_TREE" "$NO_UPSTREAM_REASON" \
        --head "$BRANCH" --base main
    assert_blocker no-upstream-block "$WORK_TREE" "$NO_UPSTREAM_REASON" \
        --head "$BRANCH" --base main --no-upstream block
    assert_remote_refs no-upstream-block-remote-unchanged "$ORIGIN_DIR" "$(trunk_only_listing)"
}

test_no_upstream_origin() {
    local sha
    create_world no-upstream-origin
    sha="$(head_sha)"
    assert_success no-upstream-origin "$WORK_TREE" "$sha" '' \
        --head "$BRANCH" --base main --no-upstream origin
    assert_remote_refs no-upstream-origin-writes-own-name "$ORIGIN_DIR" "$(branch_and_trunk_listing "$sha")"
    assert_equal no-upstream-origin-upstream-remote origin "$(read_branch_config remote)" "branch.$BRANCH.remote"
    assert_equal no-upstream-origin-upstream-merge "refs/heads/$BRANCH" "$(read_branch_config merge)" "branch.$BRANCH.merge"
}

test_no_upstream_origin_absent() {
    create_world no-upstream-no-origin
    run_git "$WORK_TREE" remote remove origin
    install_pre_push_hook
    assert_success no-upstream-origin-deferred "$WORK_TREE" "$(head_sha)" "$DEFERRED_WARNING" \
        --head "$BRANCH" --base main --no-upstream origin
    assert_equal no-upstream-origin-deferred-no-push 0 "$(count_push_attempts)" "push attempts"
    assert_remote_refs no-upstream-origin-deferred-other-untouched "$OTHER_DIR" ''
}

# ── Run ──────────────────────────────────────────────────────────────────────

test_usage_errors
test_identifier_gate
test_branch_state
test_base_any_spelling
test_base_names_other_refs
test_base_ref_identity_passes
test_base_remote_image_refused
test_expect_commit
test_explicit_sets_upstream
test_explicit_non_ff_no_retry
test_explicit_rejections
test_upstream_own_name
test_upstream_non_ff_lease_succeeds
test_upstream_fetch_first_lease_blocks
test_upstream_mismatch
test_triangular_push_remote
test_triangular_push_default
test_drift_merge_rewrite
test_drift_head_repoint
test_drift_branch_ref_rewrite
test_source_shadow_ref
test_origin_head_repoint_upstream
test_explicit_upstream_record_fails
test_upstream_rejection
test_origin_rejection
test_no_upstream_block
test_no_upstream_origin
test_no_upstream_origin_absent

echo
echo "push-branch engine tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
