#!/usr/bin/env bash
#
# Behavior test runner for the create-working-branch engine
# (plugin/skills/create-working-branch/scripts/create-working-branch.sh, gate library
# plugin/skills/_shared/allowlist.sh).
#
# The engine takes REQUIRED `--base <branch> --branch <branch> --classification <kind>
# --trunk-freshness fresh|stale|skipped --trunk <branch>`. Before any git command it gates base,
# branch and trunk as identifiers, then refuses a branch equal to base and a trunk one of whose
# six git lookup candidates, ignoring ASCII case, is refs/heads/<branch> (trunk need not exist
# locally; base may equal trunk). It refuses an in-progress merge, rebase, cherry-pick, revert or
# bisect, unmerged paths, any staged, unstaged or untracked path, a branch whose ref is symbolic or
# is the end of trunk's symbolic ref, a trunk that names the branch by ref identity or names more
# than one ref, and a branch checked out in another worktree. Trunk names the branch when a lookup
# candidate, or the end a candidate resolves to, is refs/heads/<branch> or
# refs/remotes/<remote>/<branch> for a remote `git remote` lists, compared exactly after an ASCII
# case fold. A trunk that only ends with `/<branch>` does not. Whatever trunk names, it also refuses
# a branch that is the default branch of a remote `git remote` lists, the end of that remote's
# symbolic refs/remotes/<remote>/HEAD, dangling or not, compared after the same case fold; a listed
# remote with no such HEAD ref, or one that is not symbolic, passes, and a remote HEAD git cannot
# read stops with `cannot read trunk`. It reads trunk's ref once, before any
# change, in git's lookup order, following symbolic refs to their end even when the end does not
# exist yet, and makes every refusal before any change. It resolves the base once (local branch,
# then any commit name, then a fetch from origin), switches to an existing branch (removing an
# upstream that is not <remote>/<branch>) or creates a new one with --no-track at the base
# commit, and prints
#     branch: <b> / commit: <sha> / created: true|false [/ warning: <fixed text>]
# on stdout, exit 0. On any blocker it prints `blocker: <fixed reason>` as the ONLY stderr line,
# NOTHING on stdout, exit 1.
#
# ISOLATION: the REAL committed engine is run unmodified by absolute path (it self-locates its own
# _shared/ library). Each case builds a THROWAWAY world under a mktemp WORKDIR: a local bare repo
# `origin.git` as the remote plus a working checkout `w` on main, so no network and no real remote
# is ever reached. Host git config is excluded: GIT_CONFIG_NOSYSTEM=1, HOME and XDG_CONFIG_HOME
# point into WORKDIR, identity/signing come from `-c` overrides, and GIT_CEILING_DIRECTORIES stops
# discovery from escaping WORKDIR (the not-a-checkout case).
#
# Every success case asserts exit 0 and the FULL stdout block (exact equality, including the
# trailing newline). Every blocker case asserts exit 1, EMPTY stdout, exactly one stderr line,
# and that line a `blocker:` line equal to the contracted reason (no git stderr around it). Refusal
# cases also assert that HEAD, every ref, the index, the tree status and the branch config are
# unchanged.
#
# Prints PASS/FAIL per assertion. Exits non-zero if ANY assertion FAILs.
#
# Usage:
#   ./tools/test_create_working_branch.sh

set -euo pipefail

# ── Path setup ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ENGINE="$REPO_ROOT/plugin/skills/create-working-branch/scripts/create-working-branch.sh"

# ── Dependency / input preflight ────────────────────────────────────────────

command -v git >/dev/null 2>&1 \
    || { echo "FAIL: required dependency 'git' is not installed" >&2; exit 2; }
[[ -f "$ENGINE" ]] \
    || { echo "FAIL: required input missing: $ENGINE" >&2; exit 2; }

# ── Disposable workdir + host-config isolation ──────────────────────────────

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-create-working-branch-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

mkdir -p "$WORKDIR/home"
export HOME="$WORKDIR/home"
export XDG_CONFIG_HOME="$WORKDIR/home/.config"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$WORKDIR"
export GIT_TERMINAL_PROMPT=0
export GIT_EDITOR=:
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ── Contracted strings (restated from the engine header; a change here is a contract change) ──

BRANCH='feature/x'
USAGE_REASON='invalid arguments; usage: create-working-branch.sh --base <branch> --branch <branch> --classification feature|bugfix|hotfix|refactor|chore|docs|test|ci --trunk-freshness fresh|stale|skipped --trunk <branch>'
IDENTIFIER_REASON='base or working_branch contains characters outside the safe allowlist'
TRUNK_IDENTIFIER_REASON='trunk contains characters outside the safe allowlist'
EQUALS_BASE_REASON='working_branch equals base'
EQUALS_TRUNK_REASON='working_branch equals trunk'
SYMBOLIC_BRANCH_REASON='working_branch is a symbolic ref'
UNREADABLE_BRANCH_REASON='cannot read working_branch'
UNREADABLE_TRUNK_REASON='cannot read trunk'
NOT_A_CHECKOUT_REASON='not inside a git checkout'
MERGE_REASON='a merge is in progress'
REBASE_REASON='a rebase is in progress'
CHERRY_PICK_REASON='a cherry-pick is in progress'
REVERT_REASON='a revert is in progress'
BISECT_REASON='a bisect is in progress'
UNMERGED_REASON='the index has unmerged paths'
STAGED_REASON='the index has staged changes'
UNSTAGED_REASON='the working tree has unstaged changes'
UNTRACKED_REASON='the working tree has untracked files'
WORKTREE_REASON='working_branch is checked out in another worktree'
BASE_REASON='base does not resolve to a commit locally or on origin'
STALE_WARNING='trunk is stale or diverged from origin; proceeding as acknowledged at preflight'
SKIPPED_WARNING='trunk freshness check was skipped'

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

# commit_file <gitroot> <path> <content> <message> -> writes, stages and commits one file.
commit_file() {
    printf '%s\n' "$3" >"$1/$2"
    run_git "$1" add -- "$2"
    run_git "$1" commit -q -m "$4"
}

# create_world <name> -> builds $WORKDIR/<name>/{origin.git,w} and sets WORLD_ROOT, WORK_TREE,
# ORIGIN_DIR, TRUNK_SHA. `w` is on main at TRUNK_SHA (f.txt, sub/keep.txt, and a .gitignore that
# ignores *.log), with remote origin carrying main and refs/remotes/origin/main fetched.
create_world() {
    WORLD_ROOT="$WORKDIR/$1"
    WORK_TREE="$WORLD_ROOT/w"
    ORIGIN_DIR="$WORLD_ROOT/origin.git"
    mkdir -p "$WORK_TREE/sub"
    run_git "$WORLD_ROOT" init -q --bare origin.git
    run_git "$ORIGIN_DIR" symbolic-ref HEAD refs/heads/main
    run_git "$WORK_TREE" init -q
    run_git "$WORK_TREE" symbolic-ref HEAD refs/heads/main
    printf '*.log\n' >"$WORK_TREE/.gitignore"
    printf 'keep\n' >"$WORK_TREE/sub/keep.txt"
    printf 'base\n' >"$WORK_TREE/f.txt"
    run_git "$WORK_TREE" add .gitignore sub/keep.txt f.txt
    run_git "$WORK_TREE" commit -q -m init
    run_git "$WORK_TREE" remote add origin "$ORIGIN_DIR"
    run_git "$WORK_TREE" push -q origin refs/heads/main:refs/heads/main
    run_git "$WORK_TREE" fetch -q origin
    TRUNK_SHA="$(run_git "$WORK_TREE" rev-parse refs/heads/main)"
}

# push_from_second_clone <branch> -> a second clone commits on <branch> (created from origin main
# when origin lacks it) and pushes it to origin, so `w` has not seen the new tip. Sets
# ELSEWHERE_SHA to the pushed commit.
push_from_second_clone() {
    local second_tree="$WORLD_ROOT/w2"
    [[ -d "$second_tree" ]] || run_git "$WORLD_ROOT" clone -q "$ORIGIN_DIR" w2
    run_git "$second_tree" checkout -q -B "$1" origin/main
    commit_file "$second_tree" elsewhere.txt "$1" "elsewhere on $1"
    run_git "$second_tree" push -q origin "refs/heads/$1:refs/heads/$1"
    ELSEWHERE_SHA="$(run_git "$second_tree" rev-parse HEAD)"
}

# create_conflict_branches -> c1 (f.txt=one, then f.txt=three) and c2 (f.txt=two) from main, with
# `w` left on c1. Merging, cherry-picking or rebasing onto c2, or reverting c1~1, conflicts.
create_conflict_branches() {
    run_git "$WORK_TREE" checkout -q -b c2
    commit_file "$WORK_TREE" f.txt two c2
    run_git "$WORK_TREE" checkout -q -b c1 main
    commit_file "$WORK_TREE" f.txt one c1a
    commit_file "$WORK_TREE" f.txt three c1b
}

# delete_remote_head <remote> -> deletes refs/remotes/<remote>/HEAD in `w` itself, symbolic or
# not, and succeeds when it is absent, so a world does not depend on whether the git version's
# fetch wrote it.
delete_remote_head() {
    run_git "$WORK_TREE" update-ref --no-deref -d "refs/remotes/$1/HEAD"
}

# set_upstream <remote> <merge> -> writes branch.feature/x.remote and branch.feature/x.merge.
set_upstream() {
    run_git "$WORK_TREE" config "branch.$BRANCH.remote" "$1"
    run_git "$WORK_TREE" config "branch.$BRANCH.merge" "$2"
}

# read_branch_config <key suffix> -> prints branch.feature/x.<suffix> in `w`, or nothing when unset.
read_branch_config() {
    run_git "$WORK_TREE" config --get "branch.$BRANCH.$1" || true
}

# read_head_ref -> prints the symbolic ref of HEAD in `w`, or `detached`.
read_head_ref() {
    run_git "$WORK_TREE" symbolic-ref -q HEAD || printf 'detached'
}

# repo_snapshot -> prints HEAD, every ref, the index, the tree status (ignored files included) and
# every branch.* config entry of `w`, for before/after equality.
repo_snapshot() {
    read_head_ref
    printf '\n'
    run_git "$WORK_TREE" for-each-ref --format='%(refname) %(objectname)'
    run_git "$WORK_TREE" ls-files -s
    run_git "$WORK_TREE" status --porcelain=v1 --untracked-files=all --ignored
    run_git "$WORK_TREE" config --get-regexp '^branch\.' || true
}

# ── Engine helpers ───────────────────────────────────────────────────────────

# run_engine <cwd> <out-var> <err-file> <engine args...> -> sets <out-var> to stdout (exact,
# trailing newlines preserved), writes stderr to <err-file>, returns the engine's exit code
# (never trips errexit: called via `|| rc=$?`).
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

# expected_block <branch> <sha> <created> [warning] -> prints the exact success stdout block. A
# command substitution of it drops the final newline, which assert_success adds back.
expected_block() {
    printf 'branch: %s\ncommit: %s\ncreated: %s\n' "$1" "$2" "$3"
    if [[ -n "${4:-}" ]]; then
        printf 'warning: %s\n' "$4"
    fi
}

# assert_success <name> <cwd> <expected stdout> <engine args...>
# Runs the engine, asserts exit 0 and stdout exactly <expected stdout> plus a final newline.
assert_success() {
    local name="$1" run_cwd="$2" expected="$3"$'\n'
    shift 3
    local errfile="$WORKDIR/$name.err" out rc=0
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
# Runs the engine, asserts exit 1, EMPTY stdout, exactly one stderr line, and that line equal to
# `blocker: <reason>`.
assert_blocker() {
    local name="$1" run_cwd="$2" reason="$3"
    shift 3
    local errfile="$WORKDIR/$name.err" out rc=0 last_err_line blocker_lines err_lines
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
    err_lines="$(wc -l <"$errfile" | tr -d ' ')"
    if [[ "$last_err_line" == "blocker: $reason" && "$blocker_lines" -eq 1 && "$err_lines" -eq 1 ]]; then
        pass "$name" "$last_err_line"
    else
        failed "$name" "expected one stderr line 'blocker: $reason' last; got $blocker_lines blocker line(s) in $err_lines stderr line(s), last: $last_err_line"
    fi
}

# assert_refused_unchanged <name> <cwd> <reason> <engine args...>
# assert_blocker, plus HEAD, refs, index, tree status and branch config unchanged by the run.
assert_refused_unchanged() {
    local name="$1" before after
    before="$(repo_snapshot)"
    assert_blocker "$@"
    after="$(repo_snapshot)"
    assert_equal "$name-unchanged" "$before" "$after" "HEAD, refs, index, tree and branch config"
}

# assert_equal <name> <expected> <actual> <what>
assert_equal() {
    if [[ "$2" == "$3" ]]; then
        pass "$1" "$4"
    else
        failed "$1" "$4; expected: $(printf '%s' "$2" | tr '\n' '|') actual: $(printf '%s' "$3" | tr '\n' '|')"
    fi
}

# assert_on_branch_without_upstream <name> <sha> -> HEAD is feature/x at <sha> and no upstream.
assert_on_branch_without_upstream() {
    assert_equal "$1-head" "refs/heads/$BRANCH" "$(read_head_ref)" "HEAD"
    assert_equal "$1-at-commit" "$2" "$(run_git "$WORK_TREE" rev-parse HEAD)" "HEAD commit"
    assert_equal "$1-no-upstream-remote" '' "$(read_branch_config remote)" "branch.$BRANCH.remote"
    assert_equal "$1-no-upstream-merge" '' "$(read_branch_config merge)" "branch.$BRANCH.merge"
}

# ── Usage, gate and enum errors ──────────────────────────────────────────────

test_usage_errors() {
    create_world usage
    assert_refused_unchanged usage-no-args "$WORK_TREE" "$USAGE_REASON"
    assert_refused_unchanged usage-unknown-flag "$WORK_TREE" "$USAGE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main --force yes
    assert_refused_unchanged usage-duplicate-branch "$WORK_TREE" "$USAGE_REASON" \
        --base main --branch "$BRANCH" --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_refused_unchanged usage-missing-value "$WORK_TREE" "$USAGE_REASON" \
        --base main --trunk main --branch "$BRANCH" --classification feature --trunk-freshness
    assert_refused_unchanged usage-missing-trunk "$WORK_TREE" "$USAGE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh
    assert_refused_unchanged usage-duplicate-trunk "$WORK_TREE" "$USAGE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main --trunk main
    assert_refused_unchanged usage-valueless-trunk "$WORK_TREE" "$USAGE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk
    assert_refused_unchanged usage-missing-base "$WORK_TREE" "$USAGE_REASON" \
        --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_refused_unchanged usage-missing-branch "$WORK_TREE" "$USAGE_REASON" \
        --base main --classification feature --trunk-freshness fresh --trunk main
    assert_refused_unchanged usage-missing-classification "$WORK_TREE" "$USAGE_REASON" \
        --base main --branch "$BRANCH" --trunk-freshness fresh --trunk main
    assert_refused_unchanged usage-missing-trunk-freshness "$WORK_TREE" "$USAGE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk main
    assert_refused_unchanged usage-positional "$WORK_TREE" "$USAGE_REASON" \
        main "$BRANCH" feature fresh
    assert_refused_unchanged enum-bad-classification "$WORK_TREE" "$USAGE_REASON" \
        --base main --branch "$BRANCH" --classification feat --trunk-freshness fresh --trunk main
    assert_refused_unchanged enum-bad-trunk-freshness "$WORK_TREE" "$USAGE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness maybe --trunk main
    assert_refused_unchanged enum-raw-stale-form "$WORK_TREE" "$USAGE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness 'stale (3 behind)' --trunk main
}

test_identifier_and_enum_gate() {
    create_world gate
    local marker="$WORLD_ROOT/injected"
    local -a value_names=(dollar-paren backtick dotdot leading-dash empty space)
    local -a bad_values=("\$(touch $marker)" "\`touch $marker\`" 'feature/../x' '-x' '' 'feature/a b')
    local index value_name bad_value
    for index in "${!bad_values[@]}"; do
        value_name="${value_names[$index]}"
        bad_value="${bad_values[$index]}"
        assert_refused_unchanged "gate-base-$value_name" "$WORK_TREE" "$IDENTIFIER_REASON" \
            --base "$bad_value" --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
        assert_refused_unchanged "gate-branch-$value_name" "$WORK_TREE" "$IDENTIFIER_REASON" \
            --base main --branch "$bad_value" --classification feature --trunk-freshness fresh --trunk main
        assert_refused_unchanged "enum-classification-$value_name" "$WORK_TREE" "$USAGE_REASON" \
            --base main --branch "$BRANCH" --classification "$bad_value" --trunk-freshness fresh --trunk main
        assert_refused_unchanged "enum-trunk-freshness-$value_name" "$WORK_TREE" "$USAGE_REASON" \
            --base main --branch "$BRANCH" --classification feature --trunk-freshness "$bad_value" --trunk main
        assert_refused_unchanged "gate-trunk-$value_name" "$WORK_TREE" "$TRUNK_IDENTIFIER_REASON" \
            --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk "$bad_value"
    done
    if [[ -e "$marker" ]]; then
        failed gate-no-side-effect "a gated value was expanded: $marker exists"
    else
        pass gate-no-side-effect "no gated value was expanded"
    fi
}

test_branch_equals_base() {
    create_world equals-base
    assert_refused_unchanged branch-equals-base "$WORK_TREE" "$EQUALS_BASE_REASON" \
        --base main --branch main --classification feature --trunk-freshness fresh --trunk main
}

test_branch_equals_trunk() {
    create_world equals-trunk-off-trunk
    run_git "$WORK_TREE" checkout -q -b scratch
    assert_refused_unchanged branch-equals-trunk-off-trunk "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base release --branch main --classification feature --trunk-freshness fresh --trunk main

    create_world equals-trunk
    assert_refused_unchanged branch-equals-trunk-on-trunk "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base release --branch main --classification feature --trunk-freshness fresh --trunk main
    assert_refused_unchanged branch-equals-trunk-remote-base "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base origin/main --branch main --classification feature --trunk-freshness fresh --trunk main
    assert_refused_unchanged branch-equals-trunk-capitalized "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base main --branch Main --classification feature --trunk-freshness fresh --trunk main
    assert_refused_unchanged branch-equals-trunk-upper-case "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base main --branch MAIN --classification feature --trunk-freshness fresh --trunk main
    assert_refused_unchanged branch-equals-trunk-develop "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base main --branch develop --classification feature --trunk-freshness fresh --trunk develop
}

# A symbolic refs/heads/<branch> would let HEAD's commits land on the ref it points at, so the
# branch's own ref must not be symbolic, and trunk's symbolic ref must not end at the branch.
test_trunk_alias() {
    create_world alias-existing
    run_git "$WORK_TREE" checkout -q -b scratch
    run_git "$WORK_TREE" symbolic-ref "refs/heads/$BRANCH" refs/heads/main
    assert_refused_unchanged alias-branch-points-at-trunk "$WORK_TREE" "$SYMBOLIC_BRANCH_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_refused_unchanged alias-branch-points-at-other "$WORK_TREE" "$SYMBOLIC_BRANCH_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk develop

    create_world alias-dangling
    run_git "$WORK_TREE" checkout -q -b scratch
    run_git "$WORK_TREE" symbolic-ref "refs/heads/$BRANCH" refs/heads/develop
    assert_refused_unchanged alias-branch-dangling "$WORK_TREE" "$SYMBOLIC_BRANCH_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk develop
    assert_equal alias-branch-dangling-trunk-absent '' \
        "$(run_git "$WORK_TREE" for-each-ref refs/heads/develop)" "develop absent"

    create_world alias-already-on
    run_git "$WORK_TREE" symbolic-ref "refs/heads/$BRANCH" refs/heads/main
    run_git "$WORK_TREE" symbolic-ref HEAD "refs/heads/$BRANCH"
    assert_refused_unchanged alias-already-on-branch "$WORK_TREE" "$SYMBOLIC_BRANCH_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main

    create_world alias-trunk
    run_git "$WORK_TREE" checkout -q -b scratch
    run_git "$WORK_TREE" symbolic-ref refs/heads/master refs/heads/main
    assert_refused_unchanged alias-trunk-ends-at-branch "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base scratch --branch main --classification feature --trunk-freshness fresh --trunk master
    run_git "$WORK_TREE" symbolic-ref refs/heads/legacy refs/heads/master
    assert_refused_unchanged alias-trunk-chain-ends-at-branch "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base scratch --branch main --classification feature --trunk-freshness fresh --trunk legacy
    run_git "$WORK_TREE" symbolic-ref refs/heads/upper refs/heads/MAIN
    assert_refused_unchanged alias-trunk-ends-at-branch-case "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base scratch --branch main --classification feature --trunk-freshness fresh --trunk upper
    assert_success alias-trunk-elsewhere "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk master
    assert_on_branch_without_upstream alias-trunk-elsewhere "$TRUNK_SHA"

    create_world alias-unreadable
    assert_refused_unchanged alias-unreadable-branch "$WORK_TREE" "$UNREADABLE_BRANCH_REASON" \
        --base main --branch feature/x.lock --classification feature --trunk-freshness fresh --trunk main
    assert_refused_unchanged alias-unreadable-trunk "$WORK_TREE" "$UNREADABLE_TRUNK_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main.lock
}

# The trunk stop keys on the ref git resolves trunk to, not on the caller's spelling. Every git
# qualifier of a branch (refs/heads/, heads/, <remote>/, refs/remotes/<remote>/) and every
# symbolic ref whose chain ends at the branch names the same ref, so each one stops. Trunk's ref
# is read once, before any change, in git's lookup order, following symbolic refs to their end
# even when the end does not exist yet, so a trunk whose chain ends at the branch the run would
# create stops with nothing changed. A trunk that resolves to another branch (HEAD on scratch) or
# to no ref (an object name) does not stop. A stop that compares spelling only fails every
# refusal case here except trunk-guard-symbolic-chain; the success cases pass under both. A branch
# argument is a ref by identity too: heads/main and refs/heads/main name the distinct branches
# refs/heads/heads/main and refs/heads/refs/heads/main, so creating them succeeds and leaves
# refs/heads/main untouched.
test_trunk_any_spelling() {
    local index spelling_name trunk_spelling branch_spelling
    local -a spelling_names=(refs-heads heads origin remotes-origin refs-remotes-origin refs-heads-case origin-case)
    local -a trunk_spellings=(refs/heads/main heads/main origin/main remotes/origin/main refs/remotes/origin/main Refs/Heads/Main Origin/Main)
    for index in "${!trunk_spellings[@]}"; do
        spelling_name="${spelling_names[$index]}"
        trunk_spelling="${trunk_spellings[$index]}"
        create_world "trunk-spelling-$spelling_name"
        run_git "$WORK_TREE" checkout -q -b scratch
        assert_refused_unchanged "trunk-spelling-$spelling_name" "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
            --base scratch --branch main --classification feature --trunk-freshness fresh --trunk "$trunk_spelling"
    done

    create_world trunk-remote-head
    run_git "$WORK_TREE" checkout -q -b scratch
    run_git "$WORK_TREE" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    assert_refused_unchanged trunk-remote-head "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base scratch --branch main --classification feature --trunk-freshness fresh --trunk origin

    create_world trunk-head
    run_git "$WORK_TREE" branch scratch
    assert_refused_unchanged trunk-head "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base scratch --branch main --classification feature --trunk-freshness fresh --trunk HEAD

    spelling_names=(refs-heads-legacy heads-master)
    trunk_spellings=(refs/heads/legacy heads/master)
    for index in "${!trunk_spellings[@]}"; do
        spelling_name="${spelling_names[$index]}"
        trunk_spelling="${trunk_spellings[$index]}"
        create_world "trunk-qualified-alias-$spelling_name"
        run_git "$WORK_TREE" checkout -q -b scratch
        run_git "$WORK_TREE" symbolic-ref refs/heads/master refs/heads/main
        run_git "$WORK_TREE" symbolic-ref refs/heads/legacy refs/heads/master
        assert_refused_unchanged "trunk-qualified-alias-$spelling_name" "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
            --base scratch --branch main --classification feature --trunk-freshness fresh --trunk "$trunk_spelling"
    done

    create_world trunk-remote-alias
    run_git "$WORK_TREE" checkout -q -b scratch
    run_git "$WORK_TREE" symbolic-ref refs/remotes/upstream/HEAD refs/heads/main
    assert_refused_unchanged trunk-remote-alias "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base scratch --branch main --classification feature --trunk-freshness fresh --trunk upstream

    spelling_names=(refs-heads-master heads-master refs-heads-legacy master)
    trunk_spellings=(refs/heads/master heads/master refs/heads/legacy master)
    for index in "${!trunk_spellings[@]}"; do
        spelling_name="${spelling_names[$index]}"
        trunk_spelling="${trunk_spellings[$index]}"
        create_world "trunk-dangling-$spelling_name"
        run_git "$WORK_TREE" checkout -q -b scratch
        run_git "$WORK_TREE" symbolic-ref refs/heads/master refs/heads/develop
        run_git "$WORK_TREE" symbolic-ref refs/heads/legacy refs/heads/master
        assert_refused_unchanged "trunk-dangling-$spelling_name" "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
            --base main --branch develop --classification feature --trunk-freshness fresh --trunk "$trunk_spelling"
        assert_equal "trunk-dangling-$spelling_name-head" refs/heads/scratch "$(read_head_ref)" "HEAD"
        assert_equal "trunk-dangling-$spelling_name-no-branch" '' \
            "$(run_git "$WORK_TREE" for-each-ref refs/heads/develop)" "refs/heads/develop absent"
    done

    create_world trunk-dangling-remote-head
    run_git "$WORK_TREE" checkout -q -b scratch
    run_git "$WORK_TREE" symbolic-ref refs/remotes/upstream/HEAD refs/heads/develop
    assert_refused_unchanged trunk-dangling-remote-head "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base main --branch develop --classification feature --trunk-freshness fresh --trunk upstream

    create_world trunk-dangling-root-ref
    run_git "$WORK_TREE" checkout -q -b scratch
    run_git "$WORK_TREE" symbolic-ref TRUNK_HEAD refs/heads/develop
    assert_refused_unchanged trunk-dangling-root-ref "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base main --branch develop --classification feature --trunk-freshness fresh --trunk TRUNK_HEAD

    create_world trunk-head-elsewhere
    run_git "$WORK_TREE" checkout -q -b scratch
    assert_success trunk-head-elsewhere "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk HEAD
    assert_on_branch_without_upstream trunk-head-elsewhere "$TRUNK_SHA"

    create_world trunk-object-name
    run_git "$WORK_TREE" checkout -q -b scratch
    assert_success trunk-object-name "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk "$TRUNK_SHA"
    assert_on_branch_without_upstream trunk-object-name "$TRUNK_SHA"

    create_world trunk-guard-root-file
    run_git "$WORK_TREE" checkout -q -b scratch
    assert_success trunk-guard-root-file "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk config
    assert_on_branch_without_upstream trunk-guard-root-file "$TRUNK_SHA"

    create_world trunk-ambiguous
    run_git "$WORK_TREE" tag main
    run_git "$WORK_TREE" checkout -q -b scratch
    assert_refused_unchanged trunk-ambiguous "$WORK_TREE" "$UNREADABLE_TRUNK_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main

    spelling_names=(heads refs-heads)
    local -a branch_spellings=(heads/main refs/heads/main)
    for index in "${!branch_spellings[@]}"; do
        spelling_name="${spelling_names[$index]}"
        branch_spelling="${branch_spellings[$index]}"
        create_world "trunk-qualified-branch-$spelling_name"
        run_git "$WORK_TREE" checkout -q -b scratch
        assert_success "trunk-qualified-branch-$spelling_name" "$WORK_TREE" "$(expected_block "$branch_spelling" "$TRUNK_SHA" true)" \
            --base scratch --branch "$branch_spelling" --classification feature --trunk-freshness fresh --trunk main
        assert_equal "trunk-qualified-branch-$spelling_name-head" "refs/heads/$branch_spelling" "$(read_head_ref)" "HEAD"
        assert_equal "trunk-qualified-branch-$spelling_name-unchanged" "$TRUNK_SHA" \
            "$(run_git "$WORK_TREE" rev-parse refs/heads/main)" "refs/heads/main at trunk commit"
    done

    create_world trunk-guard-symbolic-chain
    run_git "$WORK_TREE" checkout -q -b scratch
    run_git "$WORK_TREE" symbolic-ref refs/heads/mid refs/heads/main
    run_git "$WORK_TREE" symbolic-ref "refs/heads/$BRANCH" refs/heads/mid
    assert_refused_unchanged trunk-guard-symbolic-chain "$WORK_TREE" "$SYMBOLIC_BRANCH_REASON" \
        --base scratch --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk refs/heads/main

    spelling_names=(origin-main refs-heads-main)
    trunk_spellings=(origin/main refs/heads/main)
    for index in "${!trunk_spellings[@]}"; do
        spelling_name="${spelling_names[$index]}"
        trunk_spelling="${trunk_spellings[$index]}"
        create_world "trunk-guard-$spelling_name"
        run_git "$WORK_TREE" checkout -q -b scratch
        assert_success "trunk-guard-$spelling_name" "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
            --base scratch --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk "$trunk_spelling"
        assert_on_branch_without_upstream "trunk-guard-$spelling_name" "$TRUNK_SHA"
    done

    create_world trunk-guard-branch-ends-with-trunk
    run_git "$WORK_TREE" checkout -q -b scratch
    assert_success trunk-guard-branch-ends-with-trunk "$WORK_TREE" "$(expected_block feature/main "$TRUNK_SHA" true)" \
        --base scratch --branch feature/main --classification feature --trunk-freshness fresh --trunk main
    assert_equal trunk-guard-branch-ends-with-trunk-head refs/heads/feature/main "$(read_head_ref)" "HEAD"
    assert_equal trunk-guard-branch-ends-with-trunk-at-commit "$TRUNK_SHA" \
        "$(run_git "$WORK_TREE" rev-parse HEAD)" "HEAD commit"
    assert_equal trunk-guard-branch-ends-with-trunk-no-upstream-remote '' \
        "$(run_git "$WORK_TREE" config --get branch.feature/main.remote || true)" "branch.feature/main.remote"
    assert_equal trunk-guard-branch-ends-with-trunk-no-upstream-merge '' \
        "$(run_git "$WORK_TREE" config --get branch.feature/main.merge || true)" "branch.feature/main.merge"
}

test_branch_differs_from_non_main_trunk() {
    create_world trunk-develop
    delete_remote_head origin
    run_git "$WORK_TREE" checkout -q -b develop
    assert_success trunk-develop-switch-to-main "$WORK_TREE" "$(expected_block main "$TRUNK_SHA" false)" \
        --base develop --branch main --classification feature --trunk-freshness fresh --trunk develop
    assert_equal trunk-develop-switch-to-main-head refs/heads/main "$(read_head_ref)" "HEAD"
    assert_success trunk-develop-new-branch "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base develop --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk develop
    assert_on_branch_without_upstream trunk-develop-new-branch "$TRUNK_SHA"

    create_world trunk-not-local
    assert_success trunk-not-local "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk develop
    assert_on_branch_without_upstream trunk-not-local "$TRUNK_SHA"
    assert_equal trunk-not-local-absent '' \
        "$(run_git "$WORK_TREE" for-each-ref refs/heads/develop refs/remotes/origin/develop)" "develop absent"
}

# Trunk names the branch only by ref identity. A trunk whose text ends with `/<branch>` but whose
# lookup candidates and their ends are other refs does not stop: a branch named team/main, an
# absent or present release/feature/x, a refs/heads/ spelling of another branch, a symbolic alias
# to another branch, and a stray remote-tracking ref under a name `git remote` does not list. Once
# `git remote` lists team, trunk team/main names the branch's image on it and stops with nothing
# changed. A stop that matches the text suffix refuses every success case here.
test_trunk_ref_identity() {
    local index case_name trunk_spelling
    local -a case_names=(team-branch refs-heads-team symbolic-alias stray-remote-ref)
    local -a trunk_spellings=(team/main refs/heads/team/main trunk-alias gone/main)
    for index in "${!trunk_spellings[@]}"; do
        case_name="trunk-identity-${case_names[$index]}"
        trunk_spelling="${trunk_spellings[$index]}"
        create_world "$case_name"
        delete_remote_head origin
        run_git "$WORK_TREE" checkout -q -b scratch
        case "$trunk_spelling" in
            gone/main) run_git "$WORK_TREE" update-ref refs/remotes/gone/main "$TRUNK_SHA" ;;
            *) run_git "$WORK_TREE" branch team/main main ;;
        esac
        if [[ "$trunk_spelling" == trunk-alias ]]; then
            run_git "$WORK_TREE" symbolic-ref refs/heads/trunk-alias refs/heads/team/main
        fi
        assert_success "$case_name" "$WORK_TREE" "$(expected_block main "$TRUNK_SHA" false)" \
            --base scratch --branch main --classification feature --trunk-freshness fresh --trunk "$trunk_spelling"
        assert_equal "$case_name-head" refs/heads/main "$(read_head_ref)" "HEAD"
    done

    create_world trunk-identity-release-absent
    assert_success trunk-identity-release-absent "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk "release/$BRANCH"
    assert_on_branch_without_upstream trunk-identity-release-absent "$TRUNK_SHA"
    assert_equal trunk-identity-release-absent-trunk-absent '' \
        "$(run_git "$WORK_TREE" for-each-ref "refs/heads/release/$BRANCH")" "release/$BRANCH absent"

    create_world trunk-identity-release-present
    run_git "$WORK_TREE" branch "release/$BRANCH" main
    assert_success trunk-identity-release-present "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk "release/$BRANCH"
    assert_on_branch_without_upstream trunk-identity-release-present "$TRUNK_SHA"

    create_world trunk-identity-remote-image
    run_git "$WORK_TREE" checkout -q -b scratch
    run_git "$WORK_TREE" remote add team "$WORLD_ROOT/team.git"
    assert_refused_unchanged trunk-identity-remote-image "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base scratch --branch main --classification feature --trunk-freshness fresh --trunk team/main
}

# The caller chooses the trunk name, so the trunk stop also refuses the default branch of every
# remote `git remote` lists, read from the end of its symbolic refs/remotes/<remote>/HEAD, whatever
# trunk names. A spoofed trunk (develop, team/main), a case-variant end, a dangling end, a second
# remote and a remote whose name holds `/` all stop with nothing changed. A remote HEAD that is
# absent or not symbolic gives no default, so the run proceeds. A remote HEAD git cannot read stops
# with `cannot read trunk`. Only the target branch is compared, so a run that starts on the
# default branch still moves off it.
test_remote_default_branch() {
    local index trunk_spelling
    local -a spoof_names=(develop team-main)
    local -a trunk_spellings=(develop team/main)
    create_world remote-default-spoof
    run_git "$WORK_TREE" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    run_git "$WORK_TREE" checkout -q -b develop
    for index in "${!trunk_spellings[@]}"; do
        trunk_spelling="${trunk_spellings[$index]}"
        assert_refused_unchanged "remote-default-spoof-${spoof_names[$index]}" "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
            --base develop --branch main --classification feature --trunk-freshness fresh --trunk "$trunk_spelling"
    done

    create_world remote-default-start-on-trunk
    run_git "$WORK_TREE" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    assert_success remote-default-start-on-trunk "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_on_branch_without_upstream remote-default-start-on-trunk "$TRUNK_SHA"

    create_world remote-default-case
    run_git "$WORK_TREE" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/MAIN
    run_git "$WORK_TREE" checkout -q -b develop
    assert_refused_unchanged remote-default-case "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base develop --branch main --classification feature --trunk-freshness fresh --trunk develop

    create_world remote-default-dangling
    run_git "$WORK_TREE" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/release
    assert_refused_unchanged remote-default-dangling "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base main --branch release --classification feature --trunk-freshness fresh --trunk develop
    assert_equal remote-default-dangling-no-branch '' \
        "$(run_git "$WORK_TREE" for-each-ref refs/heads/release refs/remotes/origin/release)" "release absent"

    create_world remote-default-second-remote
    delete_remote_head origin
    run_git "$WORK_TREE" remote add upstream "$WORLD_ROOT/upstream.git"
    run_git "$WORK_TREE" symbolic-ref refs/remotes/upstream/HEAD refs/remotes/upstream/main
    run_git "$WORK_TREE" checkout -q -b develop
    assert_refused_unchanged remote-default-second-remote "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base develop --branch main --classification feature --trunk-freshness fresh --trunk develop

    create_world remote-default-slash-remote
    delete_remote_head origin
    run_git "$WORK_TREE" remote add team/fork "$WORLD_ROOT/fork.git"
    run_git "$WORK_TREE" symbolic-ref refs/remotes/team/fork/HEAD refs/remotes/team/fork/main
    run_git "$WORK_TREE" checkout -q -b develop
    assert_refused_unchanged remote-default-slash-remote "$WORK_TREE" "$EQUALS_TRUNK_REASON" \
        --base develop --branch main --classification feature --trunk-freshness fresh --trunk develop

    create_world remote-default-absent
    delete_remote_head origin
    run_git "$WORK_TREE" checkout -q -b develop
    assert_success remote-default-absent "$WORK_TREE" "$(expected_block main "$TRUNK_SHA" false)" \
        --base develop --branch main --classification feature --trunk-freshness fresh --trunk develop
    assert_equal remote-default-absent-head refs/heads/main "$(read_head_ref)" "HEAD"

    create_world remote-default-not-symbolic
    delete_remote_head origin
    run_git "$WORK_TREE" update-ref refs/remotes/origin/HEAD "$TRUNK_SHA"
    run_git "$WORK_TREE" checkout -q -b develop
    assert_success remote-default-not-symbolic "$WORK_TREE" "$(expected_block main "$TRUNK_SHA" false)" \
        --base develop --branch main --classification feature --trunk-freshness fresh --trunk develop
    assert_equal remote-default-not-symbolic-head refs/heads/main "$(read_head_ref)" "HEAD"

    create_world remote-default-unreadable
    delete_remote_head origin
    run_git "$WORK_TREE" checkout -q -b develop
    printf 'ref: refs/remotes/origin/ma..in\n' >"$WORK_TREE/.git/refs/remotes/origin/HEAD"
    assert_refused_unchanged remote-default-unreadable "$WORK_TREE" "$UNREADABLE_TRUNK_REASON" \
        --base develop --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk develop
}

test_not_a_checkout() {
    local not_a_checkout="$WORKDIR/not-a-checkout"
    mkdir -p "$not_a_checkout"
    assert_blocker not-a-checkout "$not_a_checkout" "$NOT_A_CHECKOUT_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
}

# ── In-progress operations ───────────────────────────────────────────────────

test_merge_in_progress() {
    create_world merge
    create_conflict_branches
    run_git "$WORK_TREE" merge -q c2 >/dev/null 2>&1 || true
    assert_refused_unchanged merge-in-progress "$WORK_TREE" "$MERGE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_refused_unchanged merge-in-progress-from-subdir "$WORK_TREE/sub" "$MERGE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
}

test_clean_merge_in_progress() {
    create_world clean-merge
    run_git "$WORK_TREE" checkout -q -b side
    commit_file "$WORK_TREE" side.txt side side
    run_git "$WORK_TREE" checkout -q main
    run_git "$WORK_TREE" merge -q --no-ff --no-commit side >/dev/null 2>&1
    assert_refused_unchanged clean-merge-in-progress "$WORK_TREE" "$MERGE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
}

test_rebase_in_progress() {
    create_world rebase
    create_conflict_branches
    run_git "$WORK_TREE" rebase c2 >/dev/null 2>&1 || true
    assert_refused_unchanged rebase-in-progress "$WORK_TREE" "$REBASE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
}

test_cherry_pick_in_progress() {
    create_world cherry-pick
    create_conflict_branches
    run_git "$WORK_TREE" cherry-pick c2 >/dev/null 2>&1 || true
    assert_refused_unchanged cherry-pick-in-progress "$WORK_TREE" "$CHERRY_PICK_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
}

test_revert_in_progress() {
    create_world revert
    create_conflict_branches
    run_git "$WORK_TREE" revert --no-edit c1~1 >/dev/null 2>&1 || true
    assert_refused_unchanged revert-in-progress "$WORK_TREE" "$REVERT_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
}

test_bisect_in_progress() {
    create_world bisect
    run_git "$WORK_TREE" bisect start >/dev/null 2>&1
    assert_refused_unchanged bisect-in-progress "$WORK_TREE" "$BISECT_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
}

# ── Unmerged and dirty paths ─────────────────────────────────────────────────

test_unmerged_paths() {
    local blob
    create_world unmerged
    blob="$(run_git "$WORK_TREE" hash-object -w f.txt)"
    printf '0 %s\tf.txt\n100644 %s 1\tf.txt\n100644 %s 2\tf.txt\n100644 %s 3\tf.txt\n' \
        "0000000000000000000000000000000000000000" "$blob" "$blob" "$blob" \
        | run_git "$WORK_TREE" update-index --index-info
    assert_refused_unchanged unmerged-paths "$WORK_TREE" "$UNMERGED_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
}

test_dirty_kinds() {
    create_world dirty-staged
    printf 'staged\n' >"$WORK_TREE/f.txt"
    run_git "$WORK_TREE" add f.txt
    assert_refused_unchanged dirty-staged "$WORK_TREE" "$STAGED_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main

    create_world dirty-staged-new
    printf 'new\n' >"$WORK_TREE/new.txt"
    run_git "$WORK_TREE" add new.txt
    assert_refused_unchanged dirty-staged-new "$WORK_TREE" "$STAGED_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main

    create_world dirty-unstaged
    printf 'unstaged\n' >"$WORK_TREE/f.txt"
    assert_refused_unchanged dirty-unstaged "$WORK_TREE" "$UNSTAGED_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main

    create_world dirty-deleted
    rm "$WORK_TREE/f.txt"
    assert_refused_unchanged dirty-deleted "$WORK_TREE" "$UNSTAGED_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main

    create_world dirty-untracked
    printf 'untracked\n' >"$WORK_TREE/sub/new.txt"
    assert_refused_unchanged dirty-untracked "$WORK_TREE" "$UNTRACKED_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_equal dirty-untracked-no-branch '' \
        "$(run_git "$WORK_TREE" for-each-ref "refs/heads/$BRANCH")" "refs/heads/$BRANCH absent"
}

test_ignored_files_allowed() {
    create_world ignored
    printf 'ignored\n' >"$WORK_TREE/build.log"
    assert_success ignored-files-allowed "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_on_branch_without_upstream ignored-files-allowed "$TRUNK_SHA"
    assert_equal ignored-files-kept 'ignored' "$(cat "$WORK_TREE/build.log")" "ignored file content"
}

# ── New branch ───────────────────────────────────────────────────────────────

test_new_branch_from_local_base() {
    create_world new-local
    assert_success new-from-local-base "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_on_branch_without_upstream new-from-local-base "$TRUNK_SHA"
}

test_new_branch_from_remote_tracking_base() {
    create_world new-remote-tracking
    push_from_second_clone main
    run_git "$WORK_TREE" fetch -q origin
    run_git "$WORK_TREE" config branch.autoSetupMerge always
    assert_success new-from-origin-main "$WORK_TREE" "$(expected_block "$BRANCH" "$ELSEWHERE_SHA" true)" \
        --base origin/main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_on_branch_without_upstream new-from-origin-main "$ELSEWHERE_SHA"
    assert_equal new-from-origin-main-local-trunk-untouched "$TRUNK_SHA" \
        "$(run_git "$WORK_TREE" rev-parse refs/heads/main)" "refs/heads/main"
}

test_new_branch_from_detached_head() {
    create_world new-detached
    run_git "$WORK_TREE" checkout -q --detach main
    assert_success new-from-detached-head "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true)" \
        --base main --branch "$BRANCH" --classification chore --trunk-freshness fresh --trunk main
    assert_on_branch_without_upstream new-from-detached-head "$TRUNK_SHA"
}

test_base_fetched_from_origin() {
    create_world base-on-origin
    push_from_second_clone release
    assert_equal base-on-origin-not-local '' \
        "$(run_git "$WORK_TREE" for-each-ref refs/remotes/origin/release refs/heads/release)" "release not in w"
    assert_success base-fetched-from-origin "$WORK_TREE" "$(expected_block "$BRANCH" "$ELSEWHERE_SHA" true)" \
        --base release --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_on_branch_without_upstream base-fetched-from-origin "$ELSEWHERE_SHA"
    assert_equal base-fetched-tracking-ref "$ELSEWHERE_SHA" \
        "$(run_git "$WORK_TREE" rev-parse refs/remotes/origin/release)" "refs/remotes/origin/release"
    assert_equal base-fetched-no-local-branch '' \
        "$(run_git "$WORK_TREE" for-each-ref refs/heads/release)" "refs/heads/release absent"
}

test_unresolvable_base() {
    create_world unresolvable-base
    assert_refused_unchanged unresolvable-base-with-origin "$WORK_TREE" "$BASE_REASON" \
        --base nosuch --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    run_git "$WORK_TREE" remote remove origin
    assert_refused_unchanged unresolvable-base-no-origin "$WORK_TREE" "$BASE_REASON" \
        --base nosuch --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
}

# ── Existing branch ──────────────────────────────────────────────────────────

test_existing_branch_trunk_upstream_unset() {
    local branch_sha
    create_world existing-trunk-upstream
    run_git "$WORK_TREE" checkout -q -b "$BRANCH"
    commit_file "$WORK_TREE" work.txt work work
    branch_sha="$(run_git "$WORK_TREE" rev-parse HEAD)"
    run_git "$WORK_TREE" checkout -q main
    set_upstream origin refs/heads/main
    assert_success existing-trunk-upstream "$WORK_TREE" "$(expected_block "$BRANCH" "$branch_sha" false)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_on_branch_without_upstream existing-trunk-upstream "$branch_sha"
}

test_existing_branch_local_upstream_unset() {
    create_world existing-local-upstream
    run_git "$WORK_TREE" branch "$BRANCH"
    set_upstream . refs/heads/main
    assert_success existing-local-upstream "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" false)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_on_branch_without_upstream existing-local-upstream "$TRUNK_SHA"
}

test_existing_branch_half_upstream_unset() {
    create_world existing-half-upstream
    run_git "$WORK_TREE" branch "$BRANCH"
    run_git "$WORK_TREE" config "branch.$BRANCH.merge" "refs/heads/$BRANCH"
    assert_success existing-half-upstream "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" false)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_on_branch_without_upstream existing-half-upstream "$TRUNK_SHA"
}

test_existing_branch_matching_upstream_kept() {
    create_world existing-matching-upstream
    run_git "$WORK_TREE" branch "$BRANCH"
    run_git "$WORK_TREE" push -q origin "refs/heads/$BRANCH:refs/heads/$BRANCH"
    set_upstream origin "refs/heads/$BRANCH"
    assert_success existing-matching-upstream "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" false)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_equal existing-matching-upstream-head "refs/heads/$BRANCH" "$(read_head_ref)" "HEAD"
    assert_equal existing-matching-upstream-remote origin "$(read_branch_config remote)" "branch.$BRANCH.remote"
    assert_equal existing-matching-upstream-merge "refs/heads/$BRANCH" "$(read_branch_config merge)" "branch.$BRANCH.merge"
}

test_already_on_branch_noop() {
    local before after
    create_world already-on
    run_git "$WORK_TREE" checkout -q -b "$BRANCH"
    run_git "$WORK_TREE" push -q origin "refs/heads/$BRANCH:refs/heads/$BRANCH"
    set_upstream origin "refs/heads/$BRANCH"
    before="$(repo_snapshot)"
    assert_success already-on-branch "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" false)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    after="$(repo_snapshot)"
    assert_equal already-on-branch-noop "$before" "$after" "HEAD, refs, index, tree and branch config"
}

test_already_on_branch_trunk_upstream_unset() {
    create_world already-on-trunk-upstream
    run_git "$WORK_TREE" checkout -q -b "$BRANCH"
    set_upstream origin refs/heads/main
    assert_success already-on-trunk-upstream "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" false)" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
    assert_on_branch_without_upstream already-on-trunk-upstream "$TRUNK_SHA"
}

test_checked_out_in_other_worktree() {
    create_world other-worktree
    run_git "$WORK_TREE" branch "$BRANCH"
    run_git "$WORK_TREE" worktree add -q "$WORLD_ROOT/wt2" "$BRANCH" >/dev/null 2>&1
    assert_refused_unchanged checked-out-in-other-worktree "$WORK_TREE" "$WORKTREE_REASON" \
        --base main --branch "$BRANCH" --classification feature --trunk-freshness fresh --trunk main
}

# ── Trunk freshness warnings ─────────────────────────────────────────────────

test_freshness_warnings() {
    create_world stale
    assert_success warning-stale "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true "$STALE_WARNING")" \
        --base main --branch "$BRANCH" --classification bugfix --trunk-freshness stale --trunk main

    create_world skipped
    assert_success warning-skipped "$WORK_TREE" "$(expected_block "$BRANCH" "$TRUNK_SHA" true "$SKIPPED_WARNING")" \
        --trunk-freshness skipped --classification docs --branch "$BRANCH" --base main --trunk main
}

# ── Run ──────────────────────────────────────────────────────────────────────

test_usage_errors
test_identifier_and_enum_gate
test_branch_equals_base
test_branch_equals_trunk
test_trunk_alias
test_trunk_any_spelling
test_branch_differs_from_non_main_trunk
test_trunk_ref_identity
test_remote_default_branch
test_not_a_checkout
test_merge_in_progress
test_clean_merge_in_progress
test_rebase_in_progress
test_cherry_pick_in_progress
test_revert_in_progress
test_bisect_in_progress
test_unmerged_paths
test_dirty_kinds
test_ignored_files_allowed
test_new_branch_from_local_base
test_new_branch_from_remote_tracking_base
test_new_branch_from_detached_head
test_base_fetched_from_origin
test_unresolvable_base
test_existing_branch_trunk_upstream_unset
test_existing_branch_local_upstream_unset
test_existing_branch_half_upstream_unset
test_existing_branch_matching_upstream_kept
test_already_on_branch_noop
test_already_on_branch_trunk_upstream_unset
test_checked_out_in_other_worktree
test_freshness_warnings

echo
echo "create-working-branch engine tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
