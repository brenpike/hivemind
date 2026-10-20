#!/usr/bin/env bash
#
# Behavior test runner for the molt engine (plugin/skills/molt/scripts/molt.sh, with the shared
# libraries plugin/skills/_shared/allowlist.sh, containment.sh and git-refusals.sh).
#
# The engine takes REQUIRED `--trunk <branch> --inputs <path>`. It gates trunk as an identifier,
# moves to the top of the work tree, reads the inputs file once (after the containment read-guard)
# and checks its fields, then refuses an in-progress operation, unmerged paths, a detached or
# unborn HEAD, a branch name that fails the identifier gate, a trunk that names the current
# branch, and an unreadable trunk. A dirty path outside `files` is printed as an
# `outside: <JSON string>` stderr line before the blocker. With nothing listed dirty it prints
# `committed: false`; otherwise it stages exactly the dirty listed paths, commits them with the
# message built from the inputs, verifies the commit, and prints
#     branch: <b> / commit: <full sha> / committed: true|false
# on stdout, exit 0. On any blocker it prints nothing on stdout, exit 1, and the LAST stderr line
# is `blocker: <fixed reason>`.
#
# ISOLATION: the REAL committed engine is run unmodified by absolute path (it self-locates its own
# _shared/ libraries). Each case builds a THROWAWAY repository under a mktemp WORKDIR, so no real
# repository and no network is touched. Host git config is excluded: GIT_CONFIG_NOSYSTEM=1, HOME
# and XDG_CONFIG_HOME point into WORKDIR (a private ~/.gitconfig carries the identity the engine's
# plain `git commit` uses), and GIT_CEILING_DIRECTORIES stops discovery from escaping WORKDIR.
#
# Every success case asserts exit 0 and the FULL stdout block (exact equality). Every blocker case
# asserts exit 1, EMPTY stdout, exactly one `blocker:` line and it last, and the exact `outside:`
# lines before it. Refusal cases also assert that HEAD, every ref, the index and the tree status
# are unchanged.
#
# Prints PASS/FAIL per assertion. Exits non-zero if ANY assertion FAILs.
#
# Usage:
#   ./tools/test_molt.sh

set -euo pipefail

# ── Path setup ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ENGINE="$REPO_ROOT/plugin/skills/molt/scripts/molt.sh"

# ── Dependency / input preflight ────────────────────────────────────────────

command -v git >/dev/null 2>&1 \
    || { echo "FAIL: required dependency 'git' is not installed" >&2; exit 2; }
command -v jq >/dev/null 2>&1 \
    || { echo "FAIL: required dependency 'jq' is not installed" >&2; exit 2; }
[[ -f "$ENGINE" ]] \
    || { echo "FAIL: required input missing: $ENGINE" >&2; exit 2; }

# ── Disposable workdir + host-config isolation ──────────────────────────────

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-molt-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

mkdir -p "$WORKDIR/home" "$WORKDIR/tmp"
export HOME="$WORKDIR/home"
export XDG_CONFIG_HOME="$WORKDIR/home/.config"
export TMPDIR="$WORKDIR/tmp"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$WORKDIR"
export GIT_TERMINAL_PROMPT=0
export GIT_EDITOR=:
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_LITERAL_PATHSPECS
cat >"$HOME/.gitconfig" <<'EOF'
[user]
	name = t
	email = t@example.invalid
[commit]
	gpgsign = false
[core]
	autocrlf = false
[init]
	defaultBranch = main
EOF

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ── Contracted strings (restated from the engine header; a change here is a contract change) ──

BRANCH='feature/x'
INPUTS_REL='.hivemind/molt-inputs-t.json'
USAGE_REASON='invalid arguments; usage: molt.sh --trunk <branch> --inputs <path>'
TRUNK_IDENTIFIER_REASON='trunk contains characters outside the safe allowlist'
NOT_A_CHECKOUT_REASON='not inside a git checkout'
INPUTS_MISSING_REASON='inputs file not found'
INPUTS_OUTSIDE_REASON='inputs file resolves outside the checkout'
INPUTS_JSON_REASON='inputs file is not valid JSON'
NOT_OBJECT_REASON='inputs must be a JSON object'
UNKNOWN_FIELD_REASON='inputs have a field other than type, scope, breaking, subject, body and files'
TYPE_REASON='type must be one of feat fix hotfix refactor docs test chore ci'
SCOPE_REASON='scope contains characters outside the safe allowlist'
BREAKING_REASON='breaking must be true or false'
SUBJECT_LINE_REASON='subject must be one line of text'
SUBJECT_LENGTH_REASON='subject must be 72 characters or fewer'
BODY_REASON='body must be text with no control characters other than newline and tab'
MARKER_REASON='the subject or body has a breaking change marker but breaking is not true'
FILES_REASON='files must be an array of exact paths relative to the top of the work tree'
DIRECTORY_REASON='a files entry names a directory'
MERGE_REASON='a merge is in progress'
UNMERGED_REASON='the index has unmerged paths'
DETACHED_REASON='HEAD is detached'
UNBORN_REASON='the current branch has no commit'
BRANCH_NAME_REASON='the current branch name contains characters outside the safe allowlist'
IS_TRUNK_REASON='the current branch is trunk'
UNREADABLE_TRUNK_REASON='cannot read trunk'
OUTSIDE_REASON='the working tree has dirty paths outside files'
COMMIT_FAILED_REASON='the commit failed'
STILL_DIRTY_REASON='a listed path is still dirty after the commit'
COMMIT_OUTSIDE_REASON='the commit has a path outside files'

# ── World helpers ───────────────────────────────────────────────────────────

# run_git <gitroot> <git args...> -> git in <gitroot> (test-side setup only).
run_git() {
    local gitroot="$1"
    shift
    git -C "$gitroot" "$@"
}

# create_world <name> -> builds $WORKDIR/<name>/w on BRANCH, one commit ahead of main. main has
# f.txt, g.txt, sub/keep.txt and a .gitignore that ignores *.log and .hivemind/. Sets WORLD_ROOT,
# WORK_TREE, INPUTS_PATH, MAIN_SHA and HEAD_SHA (the BRANCH tip).
create_world() {
    WORLD_ROOT="$WORKDIR/$1"
    WORK_TREE="$WORLD_ROOT/w"
    INPUTS_PATH="$WORK_TREE/$INPUTS_REL"
    mkdir -p "$WORK_TREE/sub" "$WORK_TREE/.hivemind"
    run_git "$WORK_TREE" init -q
    run_git "$WORK_TREE" symbolic-ref HEAD refs/heads/main
    printf '*.log\n.hivemind/\n' >"$WORK_TREE/.gitignore"
    printf 'keep\n' >"$WORK_TREE/sub/keep.txt"
    printf 'base\n' >"$WORK_TREE/f.txt"
    printf 'gee\n' >"$WORK_TREE/g.txt"
    run_git "$WORK_TREE" add .gitignore sub/keep.txt f.txt g.txt
    run_git "$WORK_TREE" commit -q -m init
    MAIN_SHA="$(run_git "$WORK_TREE" rev-parse refs/heads/main)"
    run_git "$WORK_TREE" checkout -q -b "$BRANCH"
    printf 'branch\n' >"$WORK_TREE/b.txt"
    run_git "$WORK_TREE" add b.txt
    run_git "$WORK_TREE" commit -q -m 'branch start'
    HEAD_SHA="$(run_git "$WORK_TREE" rev-parse HEAD)"
}

# write_inputs <json text> -> writes the inputs file of the current world.
write_inputs() {
    printf '%s\n' "$1" >"$INPUTS_PATH"
}

# write_basic_inputs <files json array> -> a valid inputs file (feat, scope core, subject s).
write_basic_inputs() {
    write_inputs "{\"type\":\"feat\",\"scope\":\"core\",\"subject\":\"add thing\",\"files\":$1}"
}

# repo_snapshot -> prints HEAD, every ref, the index and the tree status (ignored files included)
# of the current world, for before/after equality.
repo_snapshot() {
    run_git "$WORK_TREE" symbolic-ref -q HEAD || printf 'detached'
    printf '\n'
    run_git "$WORK_TREE" rev-parse -q --verify HEAD || printf 'unborn\n'
    run_git "$WORK_TREE" for-each-ref --format='%(refname) %(objectname)'
    run_git "$WORK_TREE" ls-files -s
    run_git "$WORK_TREE" status --porcelain=v1 --untracked-files=all --ignored
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

# expected_block <sha> <committed> -> the exact success stdout block for BRANCH.
expected_block() {
    printf 'branch: %s\ncommit: %s\ncommitted: %s\n' "$BRANCH" "$1" "$2"
}

# assert_equal <name> <expected> <actual> <what>
assert_equal() {
    if [[ "$2" == "$3" ]]; then
        pass "$1" "$4"
    else
        failed "$1" "$4; expected: $(printf '%s' "$2" | tr '\n' '|') actual: $(printf '%s' "$3" | tr '\n' '|')"
    fi
}

# assert_success <name> <cwd> <expected stdout> <engine args...>
# Runs the engine, asserts exit 0, empty stderr, and stdout exactly <expected stdout>.
assert_success() {
    local name="$1" run_cwd="$2" expected="$3"$'\n'
    shift 3
    local errfile="$WORKDIR/$name.err" out rc=0
    run_engine "$run_cwd" out "$errfile" "$@" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        failed "$name" "expected exit 0, got $rc (stderr: $(tail -n 3 "$errfile" | tr '\n' '|'))"
        return 0
    fi
    if [[ -s "$errfile" ]]; then
        failed "$name" "expected empty stderr, got: $(tr '\n' '|' <"$errfile")"
        return 0
    fi
    assert_equal "$name" "$expected" "$out" "stdout block"
}

# assert_blocker <name> <cwd> <reason> <expected outside lines> <engine args...>
# Runs the engine, asserts exit 1, EMPTY stdout, and stderr exactly <expected outside lines>
# (each ending in a newline, or empty) followed by `blocker: <reason>`.
assert_blocker() {
    local name="$1" run_cwd="$2" reason="$3" outside="$4"
    shift 4
    local errfile="$WORKDIR/$name.err" out rc=0 expected_err actual_err
    run_engine "$run_cwd" out "$errfile" "$@" || rc=$?
    if [[ "$rc" -ne 1 ]]; then
        failed "$name" "expected exit 1, got $rc (stdout: $(printf '%s' "$out" | tr '\n' '|'); stderr: $(tr '\n' '|' <"$errfile"))"
        return 0
    fi
    if [[ -n "$out" ]]; then
        failed "$name" "expected empty stdout on blocker, got: $(printf '%s' "$out" | tr '\n' '|')"
        return 0
    fi
    expected_err="${outside}blocker: $reason"$'\n'
    actual_err="$(cat "$errfile"; printf 'x')"
    actual_err="${actual_err%x}"
    assert_equal "$name" "$expected_err" "$actual_err" "stderr"
}

# assert_refused_unchanged <name> <cwd> <reason> <expected outside lines> <engine args...>
# assert_blocker, plus HEAD, refs, index and tree status unchanged by the run.
assert_refused_unchanged() {
    local name="$1" before after
    before="$(repo_snapshot)"
    assert_blocker "$@"
    after="$(repo_snapshot)"
    assert_equal "$name-unchanged" "$before" "$after" "HEAD, refs, index and tree"
}

# assert_input_refused <name> <inputs json> <reason> -> writes the inputs and asserts the refusal
# with nothing changed. The tree carries a dirty listed file, so a missed refusal would commit.
assert_input_refused() {
    write_inputs "$2"
    assert_refused_unchanged "$1" "$WORK_TREE" "$3" '' --trunk main --inputs "$INPUTS_REL"
}

# assert_committed <name> <expected name-status> <expected message>
# After a committed:true run: HEAD is BRANCH, its one parent is HEAD_SHA, it changed exactly
# <expected name-status> (`git show --name-status` lines), its message is <expected message>, and
# the tree status shows no tracked or untracked change. Then HEAD_SHA moves to the new commit.
assert_committed() {
    local name="$1" new_sha
    new_sha="$(run_git "$WORK_TREE" rev-parse HEAD)"
    assert_equal "$name-branch" "refs/heads/$BRANCH" "$(run_git "$WORK_TREE" symbolic-ref HEAD)" "HEAD ref"
    assert_equal "$name-parent" "$new_sha $HEAD_SHA" "$(run_git "$WORK_TREE" rev-list --parents --max-count=1 HEAD)" "one parent, the old HEAD"
    assert_equal "$name-paths" "$2" "$(run_git "$WORK_TREE" -c core.quotePath=false show --no-renames --name-status --format= HEAD)" "committed paths"
    assert_equal "$name-message" "$3" "$(run_git "$WORK_TREE" log -1 --format=%B HEAD)" "commit message"
    assert_equal "$name-clean" '' "$(run_git "$WORK_TREE" status --porcelain=v1 --untracked-files=all)" "tree clean"
    HEAD_SHA="$new_sha"
}

# ── Usage, trunk gate, not a checkout ───────────────────────────────────────

test_usage_errors() {
    create_world usage
    write_basic_inputs '[]'
    assert_refused_unchanged usage-no-args "$WORK_TREE" "$USAGE_REASON" ''
    assert_refused_unchanged usage-unknown-flag "$WORK_TREE" "$USAGE_REASON" '' \
        --trunk main --inputs "$INPUTS_REL" --force yes
    assert_refused_unchanged usage-duplicate-trunk "$WORK_TREE" "$USAGE_REASON" '' \
        --trunk main --trunk main --inputs "$INPUTS_REL"
    assert_refused_unchanged usage-missing-inputs "$WORK_TREE" "$USAGE_REASON" '' --trunk main
    assert_refused_unchanged usage-missing-trunk "$WORK_TREE" "$USAGE_REASON" '' --inputs "$INPUTS_REL"
    assert_refused_unchanged usage-valueless-inputs "$WORK_TREE" "$USAGE_REASON" '' --trunk main --inputs
    assert_refused_unchanged usage-empty-inputs "$WORK_TREE" "$USAGE_REASON" '' --trunk main --inputs ''
    assert_refused_unchanged usage-positional "$WORK_TREE" "$USAGE_REASON" '' main "$INPUTS_REL"
}

test_trunk_gate() {
    local bad_trunk index=0
    create_world trunk-gate
    write_basic_inputs '[]'
    for bad_trunk in '$(touch pwned)' '-main' 'a..b' 'ma in' '' "$(printf 'main\nx')"; do
        index=$((index + 1))
        assert_refused_unchanged "trunk-gate-$index" "$WORK_TREE" "$TRUNK_IDENTIFIER_REASON" '' \
            --trunk "$bad_trunk" --inputs "$INPUTS_REL"
    done
    assert_equal trunk-gate-no-expansion '' "$(ls "$WORK_TREE" | grep -x pwned || true)" "no command ran"
}

test_not_a_checkout() {
    mkdir -p "$WORKDIR/nogit"
    printf '{}\n' >"$WORKDIR/nogit/in.json"
    local errfile="$WORKDIR/not-a-checkout.err" out rc=0
    run_engine "$WORKDIR/nogit" out "$errfile" --trunk main --inputs in.json || rc=$?
    assert_equal not-a-checkout "1|blocker: $NOT_A_CHECKOUT_REASON" "$rc|$(cat "$errfile")" "exit and stderr"
}

# ── Inputs file ─────────────────────────────────────────────────────────────

test_inputs_file_refusals() {
    local outside_dir
    create_world inputs-file
    printf 'changed\n' >"$WORK_TREE/f.txt"

    assert_refused_unchanged inputs-missing "$WORK_TREE" "$INPUTS_MISSING_REASON" '' \
        --trunk main --inputs .hivemind/none.json
    assert_input_refused inputs-invalid-json '{"type":' "$INPUTS_JSON_REASON"
    assert_input_refused inputs-two-values '{"type":"feat"} {"type":"fix"}' "$INPUTS_JSON_REASON"
    write_inputs ''
    : >"$INPUTS_PATH"
    assert_refused_unchanged inputs-empty-file "$WORK_TREE" "$INPUTS_JSON_REASON" '' \
        --trunk main --inputs "$INPUTS_REL"

    outside_dir="$WORKDIR/outside-target"
    mkdir -p "$outside_dir"
    printf '{"type":"feat","subject":"s","files":["f.txt"]}\n' >"$outside_dir/in.json"
    ln -s "$outside_dir/in.json" "$WORK_TREE/.hivemind/leaf.json"
    assert_refused_unchanged inputs-symlink-leaf "$WORK_TREE" "$INPUTS_OUTSIDE_REASON" '' \
        --trunk main --inputs .hivemind/leaf.json
    ln -s "$outside_dir" "$WORK_TREE/.hivemind/linked"
    assert_refused_unchanged inputs-symlink-folder "$WORK_TREE" "$INPUTS_OUTSIDE_REASON" '' \
        --trunk main --inputs .hivemind/linked/in.json
    assert_refused_unchanged inputs-absolute-outside "$WORK_TREE" "$INPUTS_OUTSIDE_REASON" '' \
        --trunk main --inputs "$outside_dir/in.json"
}

test_inputs_field_refusals() {
    local long_subject
    create_world fields
    printf 'changed\n' >"$WORK_TREE/f.txt"
    long_subject="$(printf 'a%.0s' $(seq 1 73))"

    assert_input_refused field-array '["f.txt"]' "$NOT_OBJECT_REASON"
    assert_input_refused field-string '"feat"' "$NOT_OBJECT_REASON"
    assert_input_refused field-unknown '{"type":"feat","subject":"s","files":["f.txt"],"file":"x"}' "$UNKNOWN_FIELD_REASON"
    assert_input_refused field-type-missing '{"subject":"s","files":["f.txt"]}' "$TYPE_REASON"
    assert_input_refused field-type-number '{"type":1,"subject":"s","files":["f.txt"]}' "$TYPE_REASON"
    assert_input_refused field-type-unknown '{"type":"feature","subject":"s","files":["f.txt"]}' "$TYPE_REASON"
    assert_input_refused field-type-case '{"type":"Feat","subject":"s","files":["f.txt"]}' "$TYPE_REASON"
    assert_input_refused field-scope-number '{"type":"feat","scope":1,"subject":"s","files":["f.txt"]}' "$SCOPE_REASON"
    assert_input_refused field-scope-space '{"type":"feat","scope":"a b","subject":"s","files":["f.txt"]}' "$SCOPE_REASON"
    assert_input_refused field-scope-dash '{"type":"feat","scope":"-a","subject":"s","files":["f.txt"]}' "$SCOPE_REASON"
    assert_input_refused field-scope-dotdot '{"type":"feat","scope":"a..b","subject":"s","files":["f.txt"]}' "$SCOPE_REASON"
    assert_input_refused field-scope-paren '{"type":"feat","scope":"a)b","subject":"s","files":["f.txt"]}' "$SCOPE_REASON"
    assert_input_refused field-scope-newline '{"type":"feat","scope":"a\n","subject":"s","files":["f.txt"]}' "$SCOPE_REASON"
    assert_input_refused field-scope-empty '{"type":"feat","scope":"","subject":"s","files":["f.txt"]}' "$SCOPE_REASON"
    assert_input_refused field-breaking-string '{"type":"feat","breaking":"yes","subject":"s","files":["f.txt"]}' "$BREAKING_REASON"
    assert_input_refused field-subject-missing '{"type":"feat","files":["f.txt"]}' "$SUBJECT_LINE_REASON"
    assert_input_refused field-subject-number '{"type":"feat","subject":5,"files":["f.txt"]}' "$SUBJECT_LINE_REASON"
    assert_input_refused field-subject-empty '{"type":"feat","subject":"","files":["f.txt"]}' "$SUBJECT_LINE_REASON"
    assert_input_refused field-subject-spaces '{"type":"feat","subject":"   ","files":["f.txt"]}' "$SUBJECT_LINE_REASON"
    assert_input_refused field-subject-two-lines '{"type":"feat","subject":"a\nb","files":["f.txt"]}' "$SUBJECT_LINE_REASON"
    assert_input_refused field-subject-cr '{"type":"feat","subject":"a\rb","files":["f.txt"]}' "$SUBJECT_LINE_REASON"
    assert_input_refused field-subject-tab '{"type":"feat","subject":"a\tb","files":["f.txt"]}' "$SUBJECT_LINE_REASON"
    assert_input_refused field-subject-nul '{"type":"feat","subject":"a\u0000b","files":["f.txt"]}' "$SUBJECT_LINE_REASON"
    assert_input_refused field-subject-73 "{\"type\":\"feat\",\"subject\":\"$long_subject\",\"files\":[\"f.txt\"]}" "$SUBJECT_LENGTH_REASON"
    assert_input_refused field-body-number '{"type":"feat","subject":"s","body":1,"files":["f.txt"]}' "$BODY_REASON"
    assert_input_refused field-body-null '{"type":"feat","subject":"s","body":null,"files":["f.txt"]}' "$BODY_REASON"
    assert_input_refused field-body-cr '{"type":"feat","subject":"s","body":"a\r\nb","files":["f.txt"]}' "$BODY_REASON"
    assert_input_refused field-body-nul '{"type":"feat","subject":"s","body":"a\u0000b","files":["f.txt"]}' "$BODY_REASON"
    assert_input_refused field-marker-subject '{"type":"feat","subject":"x!: y","files":["f.txt"]}' "$MARKER_REASON"
    assert_input_refused field-marker-body '{"type":"feat","subject":"s","body":"a\nBREAKING CHANGE: z","files":["f.txt"]}' "$MARKER_REASON"
    assert_input_refused field-marker-body-first '{"type":"feat","subject":"s","body":"BREAKING-CHANGE: z","breaking":false,"files":["f.txt"]}' "$MARKER_REASON"
    assert_input_refused field-files-missing '{"type":"feat","subject":"s"}' "$FILES_REASON"
    assert_input_refused field-files-string '{"type":"feat","subject":"s","files":"f.txt"}' "$FILES_REASON"
    assert_input_refused field-files-number '{"type":"feat","subject":"s","files":["f.txt",1]}' "$FILES_REASON"
    assert_input_refused field-files-empty-entry '{"type":"feat","subject":"s","files":[""]}' "$FILES_REASON"
    assert_input_refused field-files-absolute "{\"type\":\"feat\",\"subject\":\"s\",\"files\":[\"$WORK_TREE/f.txt\"]}" "$FILES_REASON"
    assert_input_refused field-files-dotdot '{"type":"feat","subject":"s","files":["sub/../f.txt"]}' "$FILES_REASON"
    assert_input_refused field-files-dot '{"type":"feat","subject":"s","files":["./f.txt"]}' "$FILES_REASON"
    assert_input_refused field-files-double-slash '{"type":"feat","subject":"s","files":["sub//keep.txt"]}' "$FILES_REASON"
    assert_input_refused field-files-trailing-slash '{"type":"feat","subject":"s","files":["sub/"]}' "$FILES_REASON"
    assert_input_refused field-files-git '{"type":"feat","subject":"s","files":[".git/config"]}' "$FILES_REASON"
    assert_input_refused field-files-git-case '{"type":"feat","subject":"s","files":["sub/.GIT/x"]}' "$FILES_REASON"
    assert_input_refused field-files-newline '{"type":"feat","subject":"s","files":["f.txt\ng.txt"]}' "$FILES_REASON"
    assert_input_refused field-files-directory '{"type":"feat","subject":"s","files":["f.txt","sub"]}' "$DIRECTORY_REASON"
}

# ── Git state refusals ──────────────────────────────────────────────────────

test_git_state_refusals() {
    local blob
    create_world merge
    run_git "$WORK_TREE" checkout -q -b other main
    printf 'other\n' >"$WORK_TREE/f.txt"
    run_git "$WORK_TREE" commit -q -am other
    run_git "$WORK_TREE" checkout -q "$BRANCH"
    printf 'mine\n' >"$WORK_TREE/f.txt"
    run_git "$WORK_TREE" commit -q -am mine
    HEAD_SHA="$(run_git "$WORK_TREE" rev-parse HEAD)"
    run_git "$WORK_TREE" merge -q other >/dev/null 2>&1 || true
    write_basic_inputs '["f.txt"]'
    assert_refused_unchanged merge-in-progress "$WORK_TREE" "$MERGE_REASON" '' --trunk main --inputs "$INPUTS_REL"

    create_world unmerged
    blob="$(run_git "$WORK_TREE" hash-object -w f.txt)"
    printf '0 %s\tf.txt\n100644 %s 1\tf.txt\n100644 %s 2\tf.txt\n100644 %s 3\tf.txt\n' \
        "0000000000000000000000000000000000000000" "$blob" "$blob" "$blob" \
        | run_git "$WORK_TREE" update-index --index-info
    write_basic_inputs '["f.txt"]'
    assert_refused_unchanged unmerged-paths "$WORK_TREE" "$UNMERGED_REASON" '' --trunk main --inputs "$INPUTS_REL"

    create_world detached
    run_git "$WORK_TREE" checkout -q --detach HEAD
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_refused_unchanged detached-head "$WORK_TREE" "$DETACHED_REASON" '' --trunk main --inputs "$INPUTS_REL"

    create_world unborn
    run_git "$WORK_TREE" symbolic-ref HEAD refs/heads/newborn
    write_basic_inputs '["f.txt"]'
    assert_refused_unchanged unborn-head "$WORK_TREE" "$UNBORN_REASON" '' --trunk main --inputs "$INPUTS_REL"

    create_world bad-branch-name
    run_git "$WORK_TREE" checkout -q -b 'feat$(touch${IFS}pwned)'
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_refused_unchanged bad-branch-name "$WORK_TREE" "$BRANCH_NAME_REASON" '' --trunk main --inputs "$INPUTS_REL"
    assert_equal bad-branch-name-no-expansion '' "$(ls "$WORK_TREE" | grep -x pwned || true)" "no command ran"
}

test_trunk_refusals() {
    local trunk_spelling index=0
    create_world on-trunk
    run_git "$WORK_TREE" checkout -q main
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    for trunk_spelling in main MAIN refs/heads/main heads/main origin/main; do
        index=$((index + 1))
        assert_refused_unchanged "on-trunk-$index" "$WORK_TREE" "$IS_TRUNK_REASON" '' \
            --trunk "$trunk_spelling" --inputs "$INPUTS_REL"
    done

    create_world trunk-alias
    run_git "$WORK_TREE" symbolic-ref refs/heads/trunk-alias "refs/heads/$BRANCH"
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_refused_unchanged trunk-symbolic-alias "$WORK_TREE" "$IS_TRUNK_REASON" '' \
        --trunk trunk-alias --inputs "$INPUTS_REL"

    create_world trunk-unreadable
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_refused_unchanged trunk-unreadable "$WORK_TREE" "$UNREADABLE_TRUNK_REASON" '' \
        --trunk main.lock --inputs "$INPUTS_REL"

    create_world trunk-ambiguous
    run_git "$WORK_TREE" tag main "$HEAD_SHA"
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_commit_run trunk-ambiguous-proceeds "$WORK_TREE" "$INPUTS_REL"
    assert_committed trunk-ambiguous-proceeds "$(printf 'M\tf.txt')" 'feat(core): add thing'
}

# ── Outside paths ───────────────────────────────────────────────────────────

test_outside_paths() {
    create_world outside
    printf 'changed\n' >"$WORK_TREE/f.txt"
    printf 'changed\n' >"$WORK_TREE/g.txt"
    printf 'new\n' >"$WORK_TREE/sub/new file.txt"
    printf 'quote\n' >"$WORK_TREE/q\"uo\\te.txt"
    printf 'uni\n' >"$WORK_TREE/ünï.txt"
    printf 'staged\n' >"$WORK_TREE/staged.txt"
    run_git "$WORK_TREE" add staged.txt
    write_basic_inputs '["f.txt"]'
    assert_refused_unchanged outside-named "$WORK_TREE" "$OUTSIDE_REASON" \
        "$(printf '%s\n' 'outside: "g.txt"' 'outside: "staged.txt"' 'outside: "q\"uo\\te.txt"' 'outside: "sub/new file.txt"' 'outside: "ünï.txt"')"$'\n' \
        --trunk main --inputs "$INPUTS_REL"

    create_world outside-rename
    run_git "$WORK_TREE" mv g.txt h.txt
    write_basic_inputs '["h.txt"]'
    assert_refused_unchanged outside-rename-old-side "$WORK_TREE" "$OUTSIDE_REASON" \
        'outside: "g.txt"'$'\n' --trunk main --inputs "$INPUTS_REL"

    create_world outside-deleted
    rm "$WORK_TREE/g.txt"
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_refused_unchanged outside-deletion "$WORK_TREE" "$OUTSIDE_REASON" \
        'outside: "g.txt"'$'\n' --trunk main --inputs "$INPUTS_REL"

    create_world outside-directory
    printf 'changed\n' >"$WORK_TREE/sub/keep.txt"
    write_basic_inputs '["sub/keep.txt.bak"]'
    assert_refused_unchanged outside-not-a-prefix "$WORK_TREE" "$OUTSIDE_REASON" \
        'outside: "sub/keep.txt"'$'\n' --trunk main --inputs "$INPUTS_REL"
}

# ── Nothing to commit ───────────────────────────────────────────────────────

test_nothing_to_commit() {
    create_world clean
    write_basic_inputs '[]'
    assert_success clean-empty-files "$WORK_TREE" "$(expected_block "$HEAD_SHA" false)" --trunk main --inputs "$INPUTS_REL"
    write_basic_inputs '["f.txt","not-there.txt"]'
    assert_success clean-listed-not-dirty "$WORK_TREE" "$(expected_block "$HEAD_SHA" false)" --trunk main --inputs "$INPUTS_REL"
    assert_equal clean-head-unchanged "$HEAD_SHA" "$(run_git "$WORK_TREE" rev-parse HEAD)" "HEAD"

    create_world ignored-scratch
    printf 'scratch\n' >"$WORK_TREE/.hivemind/other-scratch.json"
    printf 'log\n' >"$WORK_TREE/run.log"
    write_basic_inputs '[]'
    assert_success ignored-scratch-allowed "$WORK_TREE" "$(expected_block "$HEAD_SHA" false)" --trunk main --inputs "$INPUTS_REL"
}

# ── Commits ─────────────────────────────────────────────────────────────────

# assert_commit_run <name> <cwd> <inputs rel> -> runs the engine, asserts exit 0, empty stderr, and
# the stdout block with the new HEAD and committed true.
assert_commit_run() {
    local name="$1" run_cwd="$2" inputs_rel="$3"
    local errfile="$WORKDIR/$name.err" out rc=0
    run_engine "$run_cwd" out "$errfile" --trunk main --inputs "$inputs_rel" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        failed "$name" "expected exit 0, got $rc (stderr: $(tr '\n' '|' <"$errfile"))"
        return 0
    fi
    assert_equal "$name-stderr" '' "$(cat "$errfile")" "stderr empty"
    assert_equal "$name" "$(expected_block "$(run_git "$WORK_TREE" rev-parse HEAD)" true)"$'\n' "$out" "stdout block"
    assert_equal "$name-moved" yes "$([[ "$(run_git "$WORK_TREE" rev-parse HEAD)" != "$HEAD_SHA" ]] && echo yes || echo no)" "HEAD moved"
}

test_commits() {
    create_world modify-add
    printf 'changed\n' >"$WORK_TREE/f.txt"
    printf 'new\n' >"$WORK_TREE/sub/new.txt"
    printf 'log\n' >"$WORK_TREE/ignored.log"
    write_basic_inputs '["f.txt","sub/new.txt","ignored.log"]'
    assert_commit_run modify-add "$WORK_TREE" "$INPUTS_REL"
    assert_committed modify-add "$(printf 'M\tf.txt\nA\tsub/new.txt')" 'feat(core): add thing'
    assert_equal modify-add-ignored-left "!! ignored.log" "$(run_git "$WORK_TREE" status --porcelain=v1 --ignored -- ignored.log)" "ignored file not committed"

    create_world deletions
    rm "$WORK_TREE/f.txt"
    run_git "$WORK_TREE" rm -q g.txt
    write_basic_inputs '["f.txt","g.txt"]'
    assert_commit_run deletions "$WORK_TREE" "$INPUTS_REL"
    assert_committed deletions "$(printf 'D\tf.txt\nD\tg.txt')" 'feat(core): add thing'

    create_world renames
    run_git "$WORK_TREE" mv f.txt f2.txt
    mv "$WORK_TREE/g.txt" "$WORK_TREE/g2.txt"
    write_basic_inputs '["f.txt","f2.txt","g.txt","g2.txt"]'
    assert_commit_run renames "$WORK_TREE" "$INPUTS_REL"
    assert_committed renames "$(printf 'D\tf.txt\nA\tf2.txt\nD\tg.txt\nA\tg2.txt')" 'feat(core): add thing'

    create_world odd-names
    printf 'a\n' >"$WORK_TREE/sp ace.txt"
    printf 'b\n' >"$WORK_TREE/*"
    printf 'c\n' >"$WORK_TREE/-dash.txt"
    printf 'd\n' >"$WORK_TREE/ünï code.txt"
    printf 'e\n' >"$WORK_TREE/:colon"
    printf 'f\n' >"$WORK_TREE/[ab]"
    printf 'g\n' >"$WORK_TREE/a"
    write_basic_inputs '["sp ace.txt","*","-dash.txt","ünï code.txt",":colon","[ab]","a"]'
    assert_commit_run odd-names "$WORK_TREE" "$INPUTS_REL"
    assert_committed odd-names "$(printf 'A\t*\nA\t-dash.txt\nA\t:colon\nA\t[ab]\nA\ta\nA\tsp ace.txt\nA\tünï code.txt')" 'feat(core): add thing'

    create_world star-literal
    printf 'x\n' >"$WORK_TREE/*.txt"
    printf 'tracked change\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["*.txt","f.txt"]'
    run_git "$WORK_TREE" add f.txt
    printf 'unstaged again\n' >"$WORK_TREE/f.txt"
    assert_commit_run star-literal "$WORK_TREE" "$INPUTS_REL"
    assert_committed star-literal "$(printf 'A\t*.txt\nM\tf.txt')" 'feat(core): add thing'
    assert_equal star-literal-content 'unstaged again' "$(run_git "$WORK_TREE" show HEAD:f.txt)" "work tree side committed"

    create_world staged-only
    printf 'staged\n' >"$WORK_TREE/f.txt"
    run_git "$WORK_TREE" add f.txt
    write_basic_inputs '["f.txt"]'
    assert_commit_run staged-only "$WORK_TREE" "$INPUTS_REL"
    assert_committed staged-only "$(printf 'M\tf.txt')" 'feat(core): add thing'
}

test_messages() {
    create_world message-full
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_inputs '{"type":"fix","scope":"skills/molt","breaking":true,"subject":"keep $(touch pwned) and `touch pwned2` literal","body":"Why: reason.\n\nBREAKING CHANGE: new contract\n\tindented","files":["f.txt"]}'
    assert_commit_run message-full "$WORK_TREE" "$INPUTS_REL"
    assert_committed message-full "$(printf 'M\tf.txt')" \
        "$(printf 'fix(skills/molt)!: keep $(touch pwned) and `touch pwned2` literal\n\nWhy: reason.\n\nBREAKING CHANGE: new contract\n\tindented')"
    assert_equal message-no-expansion '' "$(ls "$WORK_TREE" "$WORKDIR" | grep -x -e pwned -e pwned2 || true)" "no command ran"

    create_world message-plain
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_inputs '{"type":"docs","subject":"say it plainly","body":" \n\t\n","breaking":false,"files":["f.txt"]}'
    assert_commit_run message-plain "$WORK_TREE" "$INPUTS_REL"
    assert_committed message-plain "$(printf 'M\tf.txt')" 'docs: say it plainly'

    create_world message-72-unicode
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_inputs "{\"type\":\"chore\",\"subject\":\"$(printf 'é%.0s' $(seq 1 72))\",\"files\":[\"f.txt\"]}"
    assert_commit_run message-72-unicode "$WORK_TREE" "$INPUTS_REL"
    assert_committed message-72-unicode "$(printf 'M\tf.txt')" "chore: $(printf 'é%.0s' $(seq 1 72))"
}

test_subfolder_invocation() {
    create_world subfolder
    printf 'changed\n' >"$WORK_TREE/sub/keep.txt"
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["sub/keep.txt","f.txt"]'
    assert_commit_run subfolder "$WORK_TREE/sub" "../$INPUTS_REL"
    assert_committed subfolder "$(printf 'M\tf.txt\nM\tsub/keep.txt')" 'feat(core): add thing'

    create_world subfolder-relative-missing
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_refused_unchanged subfolder-relative-to-start "$WORK_TREE/sub" "$INPUTS_MISSING_REASON" '' \
        --trunk main --inputs "$INPUTS_REL"
}

test_hooks() {
    create_world hook-fails
    printf '#!/bin/sh\nexit 1\n' >"$WORK_TREE/.git/hooks/pre-commit"
    chmod +x "$WORK_TREE/.git/hooks/pre-commit"
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_blocker hook-fails "$WORK_TREE" "$COMMIT_FAILED_REASON" '' --trunk main --inputs "$INPUTS_REL"
    assert_equal hook-fails-head "$HEAD_SHA" "$(run_git "$WORK_TREE" rev-parse HEAD)" "HEAD unchanged"
    assert_equal hook-fails-refs "refs/heads/$BRANCH" "$(run_git "$WORK_TREE" symbolic-ref HEAD)" "still on the branch"

    create_world hook-rewrites
    printf '#!/bin/sh\nprintf "hooked\\n" >>f.txt\n' >"$WORK_TREE/.git/hooks/pre-commit"
    chmod +x "$WORK_TREE/.git/hooks/pre-commit"
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_blocker hook-rewrites "$WORK_TREE" "$STILL_DIRTY_REASON" '' --trunk main --inputs "$INPUTS_REL"
    assert_equal hook-rewrites-committed "$HEAD_SHA" "$(run_git "$WORK_TREE" rev-parse HEAD~1)" "the commit was made on the old HEAD"

    create_world hook-stages-unlisted
    printf '#!/bin/sh\nprintf "hooked\\n" >>g.txt\ngit add g.txt\n' >"$WORK_TREE/.git/hooks/pre-commit"
    chmod +x "$WORK_TREE/.git/hooks/pre-commit"
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_blocker hook-stages-unlisted "$WORK_TREE" "$COMMIT_OUTSIDE_REASON" '' --trunk main --inputs "$INPUTS_REL"
    assert_equal hook-stages-unlisted-parent "$HEAD_SHA" "$(run_git "$WORK_TREE" rev-parse HEAD~1)" "the commit was made on the old HEAD"
    assert_equal hook-stages-unlisted-paths "$(printf 'M\tf.txt\nM\tg.txt')" \
        "$(run_git "$WORK_TREE" show --no-renames --name-status --format= HEAD)" "the hook's path is in the commit the blocker names"

    create_world hook-stages-listed
    printf '#!/bin/sh\nprintf "hooked\\n" >>f.txt\ngit add f.txt\n' >"$WORK_TREE/.git/hooks/pre-commit"
    chmod +x "$WORK_TREE/.git/hooks/pre-commit"
    printf 'changed\n' >"$WORK_TREE/f.txt"
    write_basic_inputs '["f.txt"]'
    assert_commit_run hook-stages-listed "$WORK_TREE" "$INPUTS_REL"
    assert_committed hook-stages-listed "$(printf 'M\tf.txt')" 'feat(core): add thing'
}

# ── Run ──────────────────────────────────────────────────────────────────────

test_usage_errors
test_trunk_gate
test_not_a_checkout
test_inputs_file_refusals
test_inputs_field_refusals
test_git_state_refusals
test_trunk_refusals
test_outside_paths
test_nothing_to_commit
test_commits
test_messages
test_subfolder_invocation
test_hooks

echo
echo "molt engine tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
