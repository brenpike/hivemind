#!/usr/bin/env bash
#
# Behavior test runner for the open-plan-pr engine (plugin/skills/open-plan-pr/scripts/open-plan-pr.sh,
# with its child plugin/skills/push-branch/scripts/push-branch.sh and the shared libraries
# plugin/skills/_shared/allowlist.sh, containment.sh and git-refusals.sh).
#
# The engine takes REQUIRED `--head <branch> --base <branch> --inputs <path>` plus optional
# `--remote <name>` and `--expect-commit <sha>`. It gates the identifiers, reads the inputs file
# once (after the containment read-guard) and checks its fields, refuses gh missing, an
# in-progress operation, unmerged paths, a dirty tree and a failed open-PR lookup, then pushes
# through push-branch.sh, reuses the open PR on the pushed commit (re-reading to absorb head SHA
# lag) or creates one, and verifies the created PR. On success it prints
#     url: <url> / head_ref_oid: <sha> / created: true|false [/ warning: <text>]
# on stdout, exit 0, with `commented: true|false` after `created:` only when the inputs carry
# comment (posted with `gh pr comment` on a reused PR only). On any blocker it prints nothing on stdout, exit 1, and the LAST stderr line
# is `blocker: <fixed reason>`.
#
# ISOLATION: the REAL committed engine and the REAL push-branch.sh run unmodified by absolute path.
# Each case builds a THROWAWAY world under a mktemp WORKDIR: a local bare repo `github/o/r.git` and
# a working checkout `w` on feat/x whose origin is `git@github.com:o/r.git`. An offline fake ssh
# transport (GIT_SSH_COMMAND, GIT_SSH_VARIANT=simple) maps `git@github.com:<path>` to the world's
# `github/<path>` bare repo, so pushes stay local and no network and no real remote is reached.
# A stub `gh` is first on PATH: it records each call's argv and the body file it is given, and
# serves scripted responses, so no real GitHub call is ever made. It answers `gh repo view` with
# `{"id":"R_o"}` unless a case scripts it. The gh-missing case runs with a PATH of only
# the tools the scripts need. Host git config is excluded: GIT_CONFIG_NOSYSTEM=1, HOME and
# XDG_CONFIG_HOME point into WORKDIR (a private ~/.gitconfig carries the identity), and
# GIT_CEILING_DIRECTORIES stops discovery from escaping WORKDIR. The strict parse of the child's
# output runs against a COPY of the skills tree whose push-branch.sh is a scripted fake.
#
# Every success case asserts exit 0 and the FULL stdout block (exact equality). Every blocker case
# asserts exit 1, EMPTY stdout, exactly one `blocker:` line and it last. Refusal cases also assert
# that the remote refs and the local repository are unchanged and that gh created no PR.
#
# Prints PASS/FAIL per assertion. Exits non-zero if ANY assertion FAILs.
#
# Usage:
#   ./tools/test_open_plan_pr.sh

set -euo pipefail

# ── Path setup ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ENGINE="$REPO_ROOT/plugin/skills/open-plan-pr/scripts/open-plan-pr.sh"

# ── Dependency / input preflight ────────────────────────────────────────────

command -v git >/dev/null 2>&1 \
    || { echo "FAIL: required dependency 'git' is not installed" >&2; exit 2; }
command -v jq >/dev/null 2>&1 \
    || { echo "FAIL: required dependency 'jq' is not installed" >&2; exit 2; }
[[ -f "$ENGINE" ]] \
    || { echo "FAIL: required input missing: $ENGINE" >&2; exit 2; }

# ── Disposable workdir + host-config isolation ──────────────────────────────

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-open-plan-pr-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

mkdir -p "$WORKDIR/home" "$WORKDIR/tmp" "$WORKDIR/stub-bin" "$WORKDIR/no-gh-bin"
export HOME="$WORKDIR/home"
export XDG_CONFIG_HOME="$WORKDIR/home/.config"
export TMPDIR="$WORKDIR/tmp"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$WORKDIR"
export GIT_TERMINAL_PROMPT=0
export GIT_EDITOR=:
export HIVEMIND_OPEN_PLAN_PR_REREAD_DELAY=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_LITERAL_PATHSPECS
unset GH_REPO GH_HOST GH_TOKEN GITHUB_TOKEN
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

# The gh-missing PATH: only the tools the engine, push-branch.sh and git need, resolved before
# the stub goes on PATH.
for tool_name in bash git jq mktemp rm dirname basename tr cat tail sleep sh; do
    tool_path="$(command -v "$tool_name")" \
        || { echo "FAIL: required tool '$tool_name' is not installed" >&2; exit 2; }
    ln -s "$tool_path" "$WORKDIR/no-gh-bin/$tool_name"
done
NO_GH_PATH="$WORKDIR/no-gh-bin"

# Stub gh. Each call N writes its argv (one per line) to $GH_STUB_DIR/<sub>-<cmd>.<k>.args, where
# k counts the calls of that subcommand, and copies a --body-file to .body beside it. It serves
# $GH_STUB_DIR/<sub>-<cmd>.<k>.{out,err,rc}, falling back to <sub>-<cmd>.{out,err,rc}.
cat >"$WORKDIR/stub-bin/gh" <<'EOF'
#!/usr/bin/env bash
set -u
stub_dir="$GH_STUB_DIR"
call_key="${1:-none}-${2:-none}"
count_file="$stub_dir/$call_key.count"
call_count=0
[ -f "$count_file" ] && call_count="$(cat "$count_file")"
call_count=$((call_count + 1))
printf '%s' "$call_count" >"$count_file"
call_base="$stub_dir/$call_key.$call_count"
printf '%s\n' "$@" >"$call_base.args"
for call_arg in "$@"; do
    case "$call_arg" in
        --body-file=*) cat -- "${call_arg#--body-file=}" >"$call_base.body" ;;
    esac
done
response_base="$call_base"
[ -e "$response_base.out" ] || [ -e "$response_base.rc" ] || [ -e "$response_base.err" ] || response_base="$stub_dir/$call_key"
[ -e "$response_base.out" ] && cat -- "$response_base.out"
[ -e "$response_base.err" ] && cat -- "$response_base.err" >&2
response_rc=0
[ -e "$response_base.rc" ] && response_rc="$(cat "$response_base.rc")"
exit "$response_rc"
EOF
chmod +x "$WORKDIR/stub-bin/gh"
export PATH="$WORKDIR/stub-bin:$PATH"

# Fake ssh transport. With GIT_SSH_VARIANT=simple git runs it as `<script> <host> <command>`. It
# serves `git-receive-pack '<path>'` and `git-upload-pack '<path>'` for git@github.com from the
# bare repo $FAKE_SSH_ROOT/<path>, and fails any other host or command.
cat >"$WORKDIR/stub-bin/fake-ssh" <<'EOF'
#!/usr/bin/env bash
set -eu
unset GIT_PROTOCOL
[ "$#" -eq 2 ] || { echo 'fake ssh: unexpected arguments' >&2; exit 255; }
[ "$1" = 'git@github.com' ] || { echo 'fake ssh: unknown host' >&2; exit 255; }
case "$2" in
    "git-receive-pack '"*"'") ssh_service='receive-pack' ;;
    "git-upload-pack '"*"'") ssh_service='upload-pack' ;;
    *) echo 'fake ssh: unknown command' >&2; exit 255 ;;
esac
ssh_path="${2#* \'}"
ssh_path="${ssh_path%\'}"
ssh_path="${ssh_path#/}"
exec git "$ssh_service" "$FAKE_SSH_ROOT/$ssh_path"
EOF
chmod +x "$WORKDIR/stub-bin/fake-ssh"
export GIT_SSH_COMMAND="$WORKDIR/stub-bin/fake-ssh"
export GIT_SSH_VARIANT=simple
unset GIT_SSH

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ── Contracted strings (restated from the engine header; a change here is a contract change) ──

BRANCH='feat/x'
INPUTS_REL='.hivemind/pr-inputs-t.json'
PR_URL='https://github.com/o/r/pull/7'
USAGE_REASON='invalid arguments; usage: open-plan-pr.sh --head <branch> --base <branch> [--remote <name>] [--expect-commit <sha>] --inputs <path>'
IDENTIFIER_REASON='head, base or push_remote contains characters outside the safe allowlist'
EXPECT_FORMAT_REASON='expected commit is not a full object id'
DELAY_REASON='HIVEMIND_OPEN_PLAN_PR_REREAD_DELAY must be a whole number of seconds'
GH_MISSING_REASON='gh not found on PATH'
NOT_A_CHECKOUT_REASON='not inside a git checkout'
INPUTS_MISSING_REASON='inputs file not found'
INPUTS_OUTSIDE_REASON='inputs file resolves outside the checkout'
INPUTS_JSON_REASON='inputs file is not valid JSON'
NOT_OBJECT_REASON='inputs must be a JSON object'
UNKNOWN_FIELD_REASON='inputs have a field other than title, body, draft and comment'
TITLE_REASON='title must be one line of text'
BODY_REASON='body must be text with no control characters other than newline and tab'
DRAFT_REASON='draft must be true or false'
COMMENT_REASON='comment must be non-blank text with no control characters other than newline and tab'
COMMENT_POST_REASON='the PR comment could not be posted'
MERGE_REASON='a merge is in progress'
UNMERGED_REASON='the index has unmerged paths'
STAGED_REASON='the index has staged changes'
UNSTAGED_REASON='the working tree has unstaged changes'
UNTRACKED_REASON='the working tree has untracked files'
LOOKUP_REASON='cannot look up the open PRs for head'
UNEXPECTED_PUSH_REASON='the push script printed unexpected output'
PUSH_FAILED_REASON='the push script failed'
REREAD_FAILED_REASON='the open PRs could not be read after the push'
MANY_CARRYING_REASON='more than one open PR carries the pushed commit'
CREATE_FAILED_REASON='the PR could not be created'
URL_REASON='PR URL contains characters outside the safe allowlist'
VIEW_REASON='could not read the PR head branch or head SHA'
HEAD_MISMATCH_REASON='PR head branch does not match head'
OID_MISMATCH_REASON='PR head SHA does not match the pushed commit'
REPO_MISMATCH_REASON='PR head repository does not match the push remote'
REPO_VIEW_REASON='cannot read the GitHub repository of the push remote'
REPO_UNKNOWN_WARNING='gh cannot read the push remote as a GitHub repository; the PR head repository was not checked'
PUSH_MISMATCH_REASON='current branch does not match head or equals base'
EXPECT_MISMATCH_REASON='HEAD is not the expected commit'
REJECT_WARNING='push was rejected; the branch is not on its remote'
DEFERRED_WARNING='no upstream and no origin remote; push deferred'
LIST_ARGS="$(printf 'pr\nlist\n--head\n%s\n--base\nmain\n--state\nopen\n--limit\n100\n--json\nnumber,url,headRefName,headRefOid,baseRefName,headRepository' "$BRANCH")"
ORIGIN_URL='git@github.com:o/r.git'

# ── World helpers ───────────────────────────────────────────────────────────

# run_git <gitroot> <git args...> -> git in <gitroot> (test-side setup only).
run_git() {
    local gitroot="$1"
    shift
    git -C "$gitroot" "$@"
}

# create_world <name> -> builds $WORKDIR/<name>/{github/o/r.git,w,gh}. origin carries main; `w`
# has remote origin at ORIGIN_URL (served by the fake ssh transport), no upstream, and HEAD on
# feat/x one commit ahead of main (unpushed). main has a .gitignore that ignores .hivemind/. Sets
# WORLD_ROOT, WORK_TREE, ORIGIN_DIR, INPUTS_PATH, GH_STUB_DIR and FAKE_SSH_ROOT (exported),
# TRUNK_SHA and HEAD_SHA, writes a valid inputs file, and scripts `gh repo view` to print R_o.
create_world() {
    WORLD_ROOT="$WORKDIR/$1"
    WORK_TREE="$WORLD_ROOT/w"
    export FAKE_SSH_ROOT="$WORLD_ROOT/github"
    ORIGIN_DIR="$FAKE_SSH_ROOT/o/r.git"
    INPUTS_PATH="$WORK_TREE/$INPUTS_REL"
    export GH_STUB_DIR="$WORLD_ROOT/gh"
    mkdir -p "$WORK_TREE/sub" "$GH_STUB_DIR" "$FAKE_SSH_ROOT/o"
    run_git "$FAKE_SSH_ROOT/o" init -q --bare r.git
    run_git "$ORIGIN_DIR" symbolic-ref HEAD refs/heads/main
    stub_respond repo-view '' '{"id":"R_o"}'$'\n'
    run_git "$WORK_TREE" init -q
    run_git "$WORK_TREE" symbolic-ref HEAD refs/heads/main
    printf '.hivemind/\n' >"$WORK_TREE/.gitignore"
    printf 'keep\n' >"$WORK_TREE/sub/keep.txt"
    printf 'base\n' >"$WORK_TREE/f.txt"
    run_git "$WORK_TREE" add .gitignore sub/keep.txt f.txt
    run_git "$WORK_TREE" commit -q -m init
    run_git "$WORK_TREE" remote add origin "$ORIGIN_URL"
    run_git "$WORK_TREE" push -q origin refs/heads/main:refs/heads/main
    TRUNK_SHA="$(run_git "$WORK_TREE" rev-parse refs/heads/main)"
    run_git "$WORK_TREE" checkout -q -b "$BRANCH"
    printf 'branch\n' >"$WORK_TREE/b.txt"
    run_git "$WORK_TREE" add b.txt
    run_git "$WORK_TREE" commit -q -m 'branch start'
    HEAD_SHA="$(run_git "$WORK_TREE" rev-parse HEAD)"
    mkdir -p "$WORK_TREE/.hivemind"
    write_inputs '{"title":"Add thing","body":"Summary\n\n- one\n"}'
}

# write_inputs <json text> -> writes the inputs file of the current world.
write_inputs() {
    printf '%s\n' "$1" >"$INPUTS_PATH"
}

# stub_respond <call key> <k or empty> <stdout text> [rc] [stderr text] -> scripts the stub's
# response to call k of <call key> (pr-list, pr-create, pr-view, repo-view), or to every call when
# k is empty.
stub_respond() {
    local response_base="$GH_STUB_DIR/$1"
    [[ -z "$2" ]] || response_base="$response_base.$2"
    printf '%s' "$3" >"$response_base.out"
    printf '%s' "${4:-0}" >"$response_base.rc"
    if [[ -n "${5:-}" ]]; then
        printf '%s\n' "$5" >"$response_base.err"
    fi
}

# repo_json <repo id or null> -> the headRepository value gh prints: null, or an object with id.
repo_json() {
    if [[ "$1" == null ]]; then
        printf 'null'
    else
        printf '{"id":"%s","name":"r"}' "$1"
    fi
}

# pr_entry <number> <head> <base> <oid> [repo id or null] -> one PR object as gh pr list prints
# it, with headRepository <repo id> (default R_o).
pr_entry() {
    printf '{"number":%s,"url":"https://github.com/o/r/pull/%s","headRefName":"%s","headRefOid":"%s","baseRefName":"%s","headRepository":%s}' \
        "$1" "$1" "$2" "$4" "$3" "$(repo_json "${5:-R_o}")"
}

# stub_create_ok [head] [oid] [repo id or null] -> gh pr create prints PR_URL; gh pr view reports
# <head> (default BRANCH) at <oid> (default HEAD_SHA) in <repo id> (default R_o).
stub_create_ok() {
    stub_respond pr-create '' "$PR_URL"$'\n'
    stub_respond pr-view '' "{\"headRefName\":\"${1:-$BRANCH}\",\"headRefOid\":\"${2:-$HEAD_SHA}\",\"headRepository\":$(repo_json "${3:-R_o}")}"$'\n'
}

# call_count <call key> -> prints how many times the stub served <call key>.
call_count() {
    if [[ -f "$GH_STUB_DIR/$1.count" ]]; then
        cat "$GH_STUB_DIR/$1.count"
    else
        printf '0'
    fi
}

# list_remote_refs -> prints `<refname> <sha>` for every ref of origin.
list_remote_refs() {
    git --git-dir="$ORIGIN_DIR" for-each-ref --format='%(refname) %(objectname)'
}

# local_snapshot -> prints HEAD, every local ref, the index, the tree status and the branch config.
local_snapshot() {
    run_git "$WORK_TREE" symbolic-ref -q HEAD || printf 'detached'
    printf '\n'
    run_git "$WORK_TREE" for-each-ref --format='%(refname) %(objectname)'
    run_git "$WORK_TREE" ls-files -s
    run_git "$WORK_TREE" status --porcelain=v1 --untracked-files=all
    run_git "$WORK_TREE" config --get-regexp '^branch\.' || true
}

# ── Engine helpers ───────────────────────────────────────────────────────────

ENGINE_UNDER_TEST="$ENGINE"
RUN_PATH="$PATH"

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
        PATH="$RUN_PATH" bash "$ENGINE_UNDER_TEST" "$@" 2>"$errfile" || engine_rc=$?
        printf 'x'
        exit "$engine_rc")" || rc=$?
    printf -v "$__outvar" '%s' "${__out%x}"
    return "$rc"
}

# assert_equal <name> <expected> <actual> <what>
assert_equal() {
    if [[ "$2" == "$3" ]]; then
        pass "$1" "$4"
    else
        failed "$1" "$4; expected: $(printf '%s' "$2" | tr '\n' '|') actual: $(printf '%s' "$3" | tr '\n' '|')"
    fi
}

# expected_block <created> [warning] -> the exact success stdout for PR_URL at HEAD_SHA.
expected_block() {
    printf 'url: %s\nhead_ref_oid: %s\ncreated: %s\n' "$PR_URL" "$HEAD_SHA" "$1"
    if [[ -n "${2:-}" ]]; then
        printf 'warning: %s\n' "$2"
    fi
}

# expected_comment_block <created> <commented> [warning] -> the exact success stdout for PR_URL at
# HEAD_SHA when the inputs carry comment.
expected_comment_block() {
    printf 'url: %s\nhead_ref_oid: %s\ncreated: %s\ncommented: %s\n' "$PR_URL" "$HEAD_SHA" "$1" "$2"
    if [[ -n "${3:-}" ]]; then
        printf 'warning: %s\n' "$3"
    fi
}

# assert_success <name> <cwd> <expected stdout> <engine args...>
# Runs the engine, asserts exit 0, no blocker line on stderr, and stdout exactly <expected stdout>
# plus its trailing newline.
assert_success() {
    local name="$1" run_cwd="$2" expected="$3"$'\n'
    shift 3
    local errfile="$WORKDIR/$name.err" out rc=0
    run_engine "$run_cwd" out "$errfile" "$@" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        failed "$name" "expected exit 0, got $rc (stderr: $(tail -n 3 "$errfile" | tr '\n' '|'))"
        return 0
    fi
    if grep -q '^blocker: ' "$errfile"; then
        failed "$name" "expected no blocker line, got: $(tr '\n' '|' <"$errfile")"
        return 0
    fi
    assert_equal "$name" "$expected" "$out" "stdout block"
}

# assert_blocker <name> <cwd> <reason> <engine args...>
# Runs the engine, asserts exit 1, EMPTY stdout, exactly one `blocker:` stderr line, and it last.
assert_blocker() {
    local name="$1" run_cwd="$2" reason="$3"
    shift 3
    local errfile="$WORKDIR/$name.err" out rc=0 last_err_line blocker_lines
    run_engine "$run_cwd" out "$errfile" "$@" || rc=$?
    if [[ "$rc" -ne 1 ]]; then
        failed "$name" "expected exit 1, got $rc (stdout: $(printf '%s' "$out" | tr '\n' '|'); stderr: $(tr '\n' '|' <"$errfile"))"
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
        failed "$name" "expected one stderr line 'blocker: $reason' last; got $blocker_lines blocker line(s), stderr: $(tr '\n' '|' <"$errfile")"
    fi
}

# assert_refused_unchanged <name> <cwd> <reason> <engine args...>
# assert_blocker, plus the remote refs and the local repository unchanged and no PR created.
assert_refused_unchanged() {
    local name="$1" remote_before local_before
    remote_before="$(list_remote_refs)"
    local_before="$(local_snapshot)"
    assert_blocker "$@"
    assert_equal "$name-remote" "$remote_before" "$(list_remote_refs)" "remote refs unchanged"
    assert_equal "$name-local" "$local_before" "$(local_snapshot)" "local repository unchanged"
    assert_equal "$name-no-create" 0 "$(call_count pr-create)" "no gh pr create"
}

# assert_input_refused <name> <inputs json> <reason> -> writes the inputs and asserts the refusal.
assert_input_refused() {
    write_inputs "$2"
    assert_refused_unchanged "$1" "$WORK_TREE" "$3" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
}

# assert_branch_pushed <name> -> origin carries feat/x at HEAD_SHA beside main.
assert_branch_pushed() {
    assert_equal "$1" "$(printf 'refs/heads/%s %s\nrefs/heads/main %s' "$BRANCH" "$HEAD_SHA" "$TRUNK_SHA")" \
        "$(list_remote_refs)" "feat/x pushed at HEAD"
}

# ── Usage, identifier and expect-commit gates ───────────────────────────────

test_usage_errors() {
    create_world usage
    assert_refused_unchanged usage-no-args "$WORK_TREE" "$USAGE_REASON"
    assert_refused_unchanged usage-unknown-flag "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL" --draft yes
    assert_refused_unchanged usage-duplicate-head "$WORK_TREE" "$USAGE_REASON" \
        --head "$BRANCH" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_refused_unchanged usage-missing-inputs "$WORK_TREE" "$USAGE_REASON" --head "$BRANCH" --base main
    assert_refused_unchanged usage-missing-head "$WORK_TREE" "$USAGE_REASON" --base main --inputs "$INPUTS_REL"
    assert_refused_unchanged usage-missing-base "$WORK_TREE" "$USAGE_REASON" --head "$BRANCH" --inputs "$INPUTS_REL"
    assert_refused_unchanged usage-valueless "$WORK_TREE" "$USAGE_REASON" --head "$BRANCH" --base main --inputs
    assert_refused_unchanged usage-empty-inputs "$WORK_TREE" "$USAGE_REASON" --head "$BRANCH" --base main --inputs ''
    assert_equal usage-no-gh 0 "$(call_count pr-list)" "no gh call"
}

test_identifier_gates() {
    local bad_value index=0
    create_world gates
    for bad_value in '$(touch pwned)' '`touch pwned`' '-main' 'a..b' 'ma in' ''; do
        index=$((index + 1))
        assert_refused_unchanged "gate-head-$index" "$WORK_TREE" "$IDENTIFIER_REASON" \
            --head "$bad_value" --base main --inputs "$INPUTS_REL"
        assert_refused_unchanged "gate-base-$index" "$WORK_TREE" "$IDENTIFIER_REASON" \
            --head "$BRANCH" --base "$bad_value" --inputs "$INPUTS_REL"
        assert_refused_unchanged "gate-remote-$index" "$WORK_TREE" "$IDENTIFIER_REASON" \
            --head "$BRANCH" --base main --remote "$bad_value" --inputs "$INPUTS_REL"
    done
    for bad_value in 'abc' "$(printf 'A%.0s' $(seq 1 40))" "${HEAD_SHA:0:39}" "${HEAD_SHA}0" ''; do
        index=$((index + 1))
        assert_refused_unchanged "gate-expect-$index" "$WORK_TREE" "$EXPECT_FORMAT_REASON" \
            --head "$BRANCH" --base main --expect-commit "$bad_value" --inputs "$INPUTS_REL"
    done
    assert_equal gate-no-expansion '' "$(find "$WORKDIR" -name pwned)" "no command ran"
    assert_equal gate-no-gh 0 "$(call_count pr-list)" "no gh call"
}

test_delay_gate() {
    local bad_delay index=0
    create_world delay
    for bad_delay in 'x' '-1' '1.5' ' 2'; do
        index=$((index + 1))
        HIVEMIND_OPEN_PLAN_PR_REREAD_DELAY="$bad_delay" assert_refused_unchanged "delay-$index" \
            "$WORK_TREE" "$DELAY_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    done
}

# ── Tools and checkout ──────────────────────────────────────────────────────

test_gh_missing() {
    create_world gh-missing
    RUN_PATH="$NO_GH_PATH"
    assert_refused_unchanged gh-missing "$WORK_TREE" "$GH_MISSING_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    RUN_PATH="$PATH"
}

test_not_a_checkout() {
    mkdir -p "$WORKDIR/nogit"
    printf '{}\n' >"$WORKDIR/nogit/in.json"
    local errfile="$WORKDIR/not-a-checkout.err" out rc=0
    run_engine "$WORKDIR/nogit" out "$errfile" --head "$BRANCH" --base main --inputs in.json || rc=$?
    assert_equal not-a-checkout "1|blocker: $NOT_A_CHECKOUT_REASON" "$rc|$(cat "$errfile")" "exit and stderr"
}

# ── Inputs file ─────────────────────────────────────────────────────────────

test_inputs_file_refusals() {
    local outside_dir
    create_world inputs-file
    assert_refused_unchanged inputs-missing "$WORK_TREE" "$INPUTS_MISSING_REASON" \
        --head "$BRANCH" --base main --inputs .hivemind/none.json
    assert_input_refused inputs-invalid-json '{"title":' "$INPUTS_JSON_REASON"
    assert_input_refused inputs-two-values '{"title":"a","body":""} {"title":"b","body":""}' "$INPUTS_JSON_REASON"
    : >"$INPUTS_PATH"
    assert_refused_unchanged inputs-empty-file "$WORK_TREE" "$INPUTS_JSON_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    outside_dir="$WORKDIR/outside-target"
    mkdir -p "$outside_dir"
    printf '{"title":"t","body":"b"}\n' >"$outside_dir/in.json"
    ln -s "$outside_dir/in.json" "$WORK_TREE/.hivemind/leaf.json"
    assert_refused_unchanged inputs-symlink-leaf "$WORK_TREE" "$INPUTS_OUTSIDE_REASON" \
        --head "$BRANCH" --base main --inputs .hivemind/leaf.json
    ln -s "$outside_dir" "$WORK_TREE/.hivemind/linked"
    assert_refused_unchanged inputs-symlink-folder "$WORK_TREE" "$INPUTS_OUTSIDE_REASON" \
        --head "$BRANCH" --base main --inputs .hivemind/linked/in.json
    assert_refused_unchanged inputs-absolute-outside "$WORK_TREE" "$INPUTS_OUTSIDE_REASON" \
        --head "$BRANCH" --base main --inputs "$outside_dir/in.json"
    assert_equal inputs-no-gh 0 "$(call_count pr-list)" "no gh call"
}

test_inputs_field_refusals() {
    create_world fields
    assert_input_refused field-array '["t"]' "$NOT_OBJECT_REASON"
    assert_input_refused field-string '"t"' "$NOT_OBJECT_REASON"
    assert_input_refused field-unknown '{"title":"t","body":"b","head":"x"}' "$UNKNOWN_FIELD_REASON"
    assert_input_refused field-title-missing '{"body":"b"}' "$TITLE_REASON"
    assert_input_refused field-title-number '{"title":1,"body":"b"}' "$TITLE_REASON"
    assert_input_refused field-title-empty '{"title":"","body":"b"}' "$TITLE_REASON"
    assert_input_refused field-title-spaces '{"title":"   ","body":"b"}' "$TITLE_REASON"
    assert_input_refused field-title-two-lines '{"title":"a\nb","body":"b"}' "$TITLE_REASON"
    assert_input_refused field-title-tab '{"title":"a\tb","body":"b"}' "$TITLE_REASON"
    assert_input_refused field-title-cr '{"title":"a\rb","body":"b"}' "$TITLE_REASON"
    assert_input_refused field-title-nul '{"title":"a\u0000b","body":"b"}' "$TITLE_REASON"
    assert_input_refused field-body-missing '{"title":"t"}' "$BODY_REASON"
    assert_input_refused field-body-number '{"title":"t","body":1}' "$BODY_REASON"
    assert_input_refused field-body-null '{"title":"t","body":null}' "$BODY_REASON"
    assert_input_refused field-body-cr '{"title":"t","body":"a\r\nb"}' "$BODY_REASON"
    assert_input_refused field-body-nul '{"title":"t","body":"a\u0000b"}' "$BODY_REASON"
    assert_input_refused field-draft-string '{"title":"t","body":"b","draft":"yes"}' "$DRAFT_REASON"
    assert_input_refused field-draft-null '{"title":"t","body":"b","draft":null}' "$DRAFT_REASON"
    assert_equal fields-no-gh 0 "$(call_count pr-list)" "no gh call"
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
    run_git "$WORK_TREE" merge -q other >/dev/null 2>&1 || true
    assert_refused_unchanged merge-in-progress "$WORK_TREE" "$MERGE_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world unmerged
    blob="$(run_git "$WORK_TREE" hash-object -w f.txt)"
    printf '0 %s\tf.txt\n100644 %s 1\tf.txt\n100644 %s 2\tf.txt\n100644 %s 3\tf.txt\n' \
        "0000000000000000000000000000000000000000" "$blob" "$blob" "$blob" \
        | run_git "$WORK_TREE" update-index --index-info
    assert_refused_unchanged unmerged-paths "$WORK_TREE" "$UNMERGED_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world staged
    printf 'staged\n' >"$WORK_TREE/f.txt"
    run_git "$WORK_TREE" add f.txt
    assert_refused_unchanged dirty-staged "$WORK_TREE" "$STAGED_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world unstaged
    printf 'unstaged\n' >"$WORK_TREE/f.txt"
    assert_refused_unchanged dirty-unstaged "$WORK_TREE" "$UNSTAGED_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world untracked
    printf 'new\n' >"$WORK_TREE/new.txt"
    assert_refused_unchanged dirty-untracked "$WORK_TREE" "$UNTRACKED_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world inputs-not-ignored
    printf 'other\n' >"$WORK_TREE/.gitignore"
    run_git "$WORK_TREE" commit -q -am 'stop ignoring .hivemind'
    assert_refused_unchanged inputs-not-ignored "$WORK_TREE" "$UNTRACKED_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal git-state-no-gh 0 "$(call_count pr-list)" "no gh call"
}

# ── Open PR lookup ──────────────────────────────────────────────────────────

test_lookup_refusals() {
    create_world lookup-fails
    stub_respond pr-list '' '' 1 'HTTP 401: Bad credentials'
    assert_refused_unchanged lookup-gh-fails "$WORK_TREE" "$LOOKUP_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal lookup-gh-fails-args "$LIST_ARGS" "$(cat "$GH_STUB_DIR/pr-list.1.args")" "gh pr list argv"

    create_world lookup-not-json
    stub_respond pr-list '' 'not json'
    assert_refused_unchanged lookup-not-json "$WORK_TREE" "$LOOKUP_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world lookup-not-array
    stub_respond pr-list '' '{"number":1}'
    assert_refused_unchanged lookup-not-array "$WORK_TREE" "$LOOKUP_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world lookup-bad-entry
    stub_respond pr-list '' '[{"number":"7","url":"u","headRefName":"feat/x","headRefOid":"x","baseRefName":"main"}]'
    assert_refused_unchanged lookup-bad-entry "$WORK_TREE" "$LOOKUP_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world lookup-scalar-entry
    stub_respond pr-list '' '["x"]'
    assert_refused_unchanged lookup-scalar-entry "$WORK_TREE" "$LOOKUP_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
}

# ── Create path ─────────────────────────────────────────────────────────────

test_create() {
    local create_args
    create_world create
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success create "$WORK_TREE" "$(expected_block true)" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_branch_pushed create-pushed
    assert_equal create-upstream "origin|refs/heads/$BRANCH" \
        "$(run_git "$WORK_TREE" config --get "branch.$BRANCH.remote")|$(run_git "$WORK_TREE" config --get "branch.$BRANCH.merge")" \
        "upstream recorded by push-branch.sh"
    assert_equal create-list-reads 2 "$(call_count pr-list)" "one lookup before and one read after the push"
    create_args="$(cat "$GH_STUB_DIR/pr-create.1.args")"
    assert_equal create-args "$(printf 'pr\ncreate\n--base\nmain\n--title=Add thing')" \
        "$(printf '%s' "$create_args" | sed -n '1,5p')" "gh pr create argv"
    assert_equal create-args-count 6 "$(printf '%s\n' "$create_args" | wc -l | tr -d ' ')" "six arguments, no --draft"
    assert_equal create-body-file-arg "--body-file=$TMPDIR/" \
        "$(printf '%s\n' "$create_args" | sed -n '6p' | sed 's#hivemind-open-plan-pr\.[^/]*/body\.md$##')" \
        "body file in the private work folder"
    assert_equal create-no-head '' "$(printf '%s\n' "$create_args" | grep -e '--head' || true)" "no --head"
    assert_equal create-body "$(printf 'Summary\n\n- one\nx')" "$(cat "$GH_STUB_DIR/pr-create.1.body"; printf 'x')" "body passed verbatim"
    assert_equal create-view-args "$(printf 'pr\nview\n7\n--json\nheadRefName,headRefOid,headRepository')" \
        "$(cat "$GH_STUB_DIR/pr-view.1.args")" "gh pr view argv"
    assert_equal create-repo-view-args "$(printf 'repo\nview\n--json\nid\n--\n%s' "$ORIGIN_URL")" \
        "$(cat "$GH_STUB_DIR/repo-view.1.args")" "gh repo view argv"
    assert_equal create-repo-view-calls 1 "$(call_count repo-view)" "one gh repo view"
    assert_equal create-work-dir-removed '' "$(ls "$TMPDIR")" "private work folder removed"

    create_world create-expect
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success create-expect-commit "$WORK_TREE" "$(expected_block true)" \
        --head "$BRANCH" --base main --expect-commit "$HEAD_SHA" --inputs "$INPUTS_REL"

    create_world create-remote
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success create-remote "$WORK_TREE" "$(expected_block true)" \
        --head "$BRANCH" --base main --remote origin --inputs "$INPUTS_REL"
    assert_branch_pushed create-remote-pushed

    create_world create-empty-body
    write_inputs '{"title":"t","body":""}'
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success create-empty-body "$WORK_TREE" "$(expected_block true)" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal create-empty-body-file 'x' "$(cat "$GH_STUB_DIR/pr-create.1.body"; printf 'x')" "empty body file"
}

test_title_not_expanded() {
    local hostile_title create_args
    create_world hostile
    hostile_title='$(touch pwned) `touch pwned2` ${HOME} "q" '"'"'s'"'"' -x'
    write_inputs "$(jq -cn --arg title "$hostile_title" --arg body "\$(touch pwned3)"$'\n'"\`touch pwned4\`" '{title: $title, body: $body}')"
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success hostile "$WORK_TREE" "$(expected_block true)" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    create_args="$(cat "$GH_STUB_DIR/pr-create.1.args")"
    assert_equal hostile-title "--title=$hostile_title" "$(printf '%s\n' "$create_args" | sed -n '5p')" "title passed as one literal argument"
    assert_equal hostile-body "\$(touch pwned3)"$'\n'"\`touch pwned4\`" "$(cat "$GH_STUB_DIR/pr-create.1.body")" "body passed verbatim"
    assert_equal hostile-no-expansion '' "$(find "$WORKDIR" -name 'pwned*')" "no command ran"

    create_world dash-title
    write_inputs '{"title":"--draft","body":"b"}'
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success dash-title "$WORK_TREE" "$(expected_block true)" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal dash-title-arg '--title=--draft' "$(sed -n '5p' "$GH_STUB_DIR/pr-create.1.args")" "dash title bound to --title"
}

test_draft() {
    create_world draft
    write_inputs '{"title":"t","body":"b","draft":true}'
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success draft "$WORK_TREE" "$(expected_block true)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal draft-flag '--draft' "$(sed -n '7p' "$GH_STUB_DIR/pr-create.1.args")" "--draft passed"

    create_world draft-false
    write_inputs '{"title":"t","body":"b","draft":false}'
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success draft-false "$WORK_TREE" "$(expected_block true)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal draft-false-flag 6 "$(wc -l <"$GH_STUB_DIR/pr-create.1.args" | tr -d ' ')" "no --draft"
}

# ── Comment ─────────────────────────────────────────────────────────────────

test_comment_field_refusals() {
    create_world comment-fields
    assert_input_refused comment-number '{"title":"t","body":"b","comment":1}' "$COMMENT_REASON"
    assert_input_refused comment-null '{"title":"t","body":"b","comment":null}' "$COMMENT_REASON"
    assert_input_refused comment-array '{"title":"t","body":"b","comment":["c"]}' "$COMMENT_REASON"
    assert_input_refused comment-empty '{"title":"t","body":"b","comment":""}' "$COMMENT_REASON"
    assert_input_refused comment-blank '{"title":"t","body":"b","comment":" \t\n "}' "$COMMENT_REASON"
    assert_input_refused comment-cr '{"title":"t","body":"b","comment":"a\r\nb"}' "$COMMENT_REASON"
    assert_input_refused comment-nul '{"title":"t","body":"b","comment":"a\u0000b"}' "$COMMENT_REASON"
    assert_input_refused comment-del '{"title":"t","body":"b","comment":"a\u007fb"}' "$COMMENT_REASON"
    assert_input_refused comment-esc '{"title":"t","body":"b","comment":"a\u001bb"}' "$COMMENT_REASON"
    assert_input_refused comment-after-unknown '{"title":"t","body":"b","comment":"","head":"x"}' "$UNKNOWN_FIELD_REASON"
    assert_input_refused comment-after-title '{"title":"","body":"b","comment":""}' "$TITLE_REASON"
    assert_input_refused comment-after-body '{"title":"t","body":1,"comment":""}' "$BODY_REASON"
    assert_input_refused comment-after-draft '{"title":"t","body":"b","draft":"yes","comment":""}' "$DRAFT_REASON"
    assert_equal comment-fields-no-gh 0 "$(call_count pr-list)" "no gh call"
}

test_comment() {
    local comment_text comment_args
    comment_text="Run again"$'\n\n'"- \$(touch pwned5) \`touch pwned6\`"$'\t'"tab"$'\n'
    create_world comment-reuse
    run_git "$WORK_TREE" push -q origin "refs/heads/$BRANCH:refs/heads/$BRANCH"
    stub_respond pr-list '' "[$(pr_entry 7 "$BRANCH" main "$HEAD_SHA")]"
    write_inputs "$(jq -cn --arg comment "$comment_text" '{title: "t", body: "b", comment: $comment}')"
    assert_success comment-reuse "$WORK_TREE" "$(expected_comment_block false true)" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal comment-reuse-calls 1 "$(call_count pr-comment)" "one gh pr comment"
    comment_args="$(cat "$GH_STUB_DIR/pr-comment.1.args")"
    assert_equal comment-reuse-args "$(printf 'pr\ncomment\n7')" \
        "$(printf '%s' "$comment_args" | sed -n '1,3p')" "gh pr comment argv"
    assert_equal comment-reuse-args-count 4 "$(printf '%s\n' "$comment_args" | wc -l | tr -d ' ')" "four arguments"
    assert_equal comment-reuse-body-file-arg "--body-file=$TMPDIR/" \
        "$(printf '%s\n' "$comment_args" | sed -n '4p' | sed 's#hivemind-open-plan-pr\.[^/]*/comment\.md$##')" \
        "comment file in the private work folder"
    assert_equal comment-reuse-body "${comment_text}x" "$(cat "$GH_STUB_DIR/pr-comment.1.body"; printf 'x')" "comment passed verbatim"
    assert_equal comment-reuse-no-expansion '' "$(find "$WORKDIR" -name 'pwned*')" "no command ran"
    assert_equal comment-reuse-no-create 0 "$(call_count pr-create)" "no gh pr create"
    assert_equal comment-reuse-work-dir-removed '' "$(ls "$TMPDIR")" "private work folder removed"

    create_world comment-reuse-rerun
    stub_respond pr-list '' "[$(pr_entry 7 "$BRANCH" main "$HEAD_SHA")]"
    write_inputs '{"title":"t","body":"b","comment":"again"}'
    assert_success comment-rerun-1 "$WORK_TREE" "$(expected_comment_block false true)" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_success comment-rerun-2 "$WORK_TREE" "$(expected_comment_block false true)" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal comment-rerun-calls 2 "$(call_count pr-comment)" "each run that reuses the PR posts its own comment"

    create_world comment-create
    stub_respond pr-list '' '[]'
    stub_create_ok
    write_inputs '{"title":"t","body":"b","comment":"c"}'
    assert_success comment-create "$WORK_TREE" "$(expected_comment_block true false)" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal comment-create-no-comment 0 "$(call_count pr-comment)" "no gh pr comment on a created PR"
    assert_equal comment-create-body 'bx' "$(cat "$GH_STUB_DIR/pr-create.1.body"; printf 'x')" "body unchanged by the comment"

    create_world comment-create-warning
    stub_respond pr-list '' '[]'
    stub_respond repo-view '' '' 1
    stub_create_ok
    write_inputs '{"title":"t","body":"b","comment":"c"}'
    assert_success comment-create-warning "$WORK_TREE" "$(expected_comment_block true false "$REPO_UNKNOWN_WARNING")" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal comment-create-warning-no-comment 0 "$(call_count pr-comment)" "no gh pr comment on a created PR"

    create_world comment-post-fails
    stub_respond pr-list '' "[$(pr_entry 7 "$BRANCH" main "$HEAD_SHA")]"
    stub_respond pr-comment '' '' 1 'HTTP 403: Resource not accessible'
    write_inputs '{"title":"t","body":"b","comment":"c"}'
    assert_blocker comment-post-fails "$WORK_TREE" "$COMMENT_POST_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal comment-post-fails-gh-stderr 1 "$(grep -c 'HTTP 403: Resource not accessible' "$WORKDIR/comment-post-fails.err")" "gh stderr relayed"
    assert_equal comment-post-fails-calls 1 "$(call_count pr-comment)" "one gh pr comment, no retry"
    assert_equal comment-post-fails-no-create 0 "$(call_count pr-create)" "no gh pr create"
    assert_branch_pushed comment-post-fails-pushed
}

# ── Reuse path ──────────────────────────────────────────────────────────────

test_reuse() {
    local other_sha
    create_world reuse
    run_git "$WORK_TREE" push -q origin "refs/heads/$BRANCH:refs/heads/$BRANCH"
    stub_respond pr-list '' "[$(pr_entry 7 "$BRANCH" main "$HEAD_SHA")]"
    write_inputs '{"title":"t","body":"b","draft":true}'
    assert_success reuse "$WORK_TREE" "$(expected_block false)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal reuse-no-create 0 "$(call_count pr-create)" "no gh pr create"
    assert_equal reuse-no-view 0 "$(call_count pr-view)" "no gh pr view"
    assert_equal reuse-reads 2 "$(call_count pr-list)" "no re-read when the PR carries the commit"

    create_world reuse-lag
    other_sha="$TRUNK_SHA"
    stub_respond pr-list 1 "[$(pr_entry 7 "$BRANCH" main "$other_sha")]"
    stub_respond pr-list 2 "[$(pr_entry 7 "$BRANCH" main "$other_sha")]"
    stub_respond pr-list 3 "[$(pr_entry 7 "$BRANCH" main "$other_sha")]"
    stub_respond pr-list '' "[$(pr_entry 7 "$BRANCH" main "$HEAD_SHA")]"
    assert_success reuse-lag "$WORK_TREE" "$(expected_block false)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal reuse-lag-reads 4 "$(call_count pr-list)" "re-read until the head SHA caught up"
    assert_equal reuse-lag-no-create 0 "$(call_count pr-create)" "no gh pr create"
    assert_branch_pushed reuse-lag-pushed

    create_world reuse-lag-exhausted
    stub_respond pr-list '' "[$(pr_entry 7 "$BRANCH" main "$TRUNK_SHA")]"
    stub_respond pr-create '' '' 1 'a pull request for branch already exists'
    assert_blocker reuse-lag-exhausted "$WORK_TREE" "$CREATE_FAILED_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal reuse-lag-exhausted-reads 6 "$(call_count pr-list)" "one lookup and five reads after the push"
    assert_equal reuse-lag-exhausted-gh-stderr 1 "$(grep -c 'a pull request for branch already exists' "$WORKDIR/reuse-lag-exhausted.err")" "gh stderr relayed"

    create_world reuse-fork-name
    stub_respond pr-list '' "[$(pr_entry 9 "$BRANCH" main "$TRUNK_SHA")]"
    stub_create_ok
    assert_success reuse-fork-name "$WORK_TREE" "$(expected_block true)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal reuse-fork-name-reads 6 "$(call_count pr-list)" "a same-name PR on another SHA is never reused"

    create_world reuse-other-base
    stub_respond pr-list '' "[$(pr_entry 8 "$BRANCH" release "$HEAD_SHA"),$(pr_entry 9 other main "$HEAD_SHA")]"
    stub_create_ok
    assert_success reuse-other-base "$WORK_TREE" "$(expected_block true)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal reuse-other-base-reads 2 "$(call_count pr-list)" "PRs with another head or base are ignored"

    create_world reuse-many
    stub_respond pr-list '' "[$(pr_entry 7 "$BRANCH" main "$HEAD_SHA"),$(pr_entry 8 "$BRANCH" main "$HEAD_SHA")]"
    assert_blocker reuse-many "$WORK_TREE" "$MANY_CARRYING_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal reuse-many-no-create 0 "$(call_count pr-create)" "no gh pr create"

    create_world reuse-bad-url
    stub_respond pr-list '' "[{\"number\":7,\"url\":\"https://github.com/o/r/pull/7\$(x)\",\"headRefName\":\"$BRANCH\",\"headRefOid\":\"$HEAD_SHA\",\"baseRefName\":\"main\",\"headRepository\":{\"id\":\"R_o\"}}]"
    assert_blocker reuse-bad-url "$WORK_TREE" "$URL_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal reuse-bad-url-no-create 0 "$(call_count pr-create)" "no gh pr create"

    create_world reread-fails
    stub_respond pr-list 1 '[]'
    stub_respond pr-list '' '' 1
    assert_blocker reread-fails "$WORK_TREE" "$REREAD_FAILED_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_branch_pushed reread-fails-pushed
    assert_equal reread-fails-no-create 0 "$(call_count pr-create)" "no gh pr create"
}

# ── Head repository ─────────────────────────────────────────────────────────

test_head_repository() {
    local bad_entry bad_view index=0
    create_world repo-fork-same-commit
    stub_respond pr-list '' "[$(pr_entry 9 "$BRANCH" main "$HEAD_SHA" R_f)]"
    stub_create_ok
    assert_success repo-fork-same-commit "$WORK_TREE" "$(expected_block true)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal repo-fork-same-commit-reads 2 "$(call_count pr-list)" "a fork PR causes no re-read"
    assert_equal repo-fork-same-commit-create 1 "$(call_count pr-create)" "a fork PR on the pushed commit is not reused"

    create_world repo-fork-and-own
    stub_respond pr-list '' "[$(pr_entry 9 "$BRANCH" main "$HEAD_SHA" R_f),$(pr_entry 7 "$BRANCH" main "$HEAD_SHA")]"
    assert_success repo-fork-and-own "$WORK_TREE" "$(expected_block false)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal repo-fork-and-own-no-create 0 "$(call_count pr-create)" "own PR reused beside a fork PR"

    create_world repo-deleted-fork
    stub_respond pr-list '' "[$(pr_entry 9 "$BRANCH" main "$HEAD_SHA" null)]"
    stub_create_ok
    assert_success repo-deleted-fork "$WORK_TREE" "$(expected_block true)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal repo-deleted-fork-reads 2 "$(call_count pr-list)" "a null head repository is not reused"

    for bad_entry in '"R_o"' '{"id":5}' '{"name":"r"}' '[]' 'true'; do
        index=$((index + 1))
        create_world "repo-lookup-bad-$index"
        stub_respond pr-list '' "[{\"number\":7,\"url\":\"$PR_URL\",\"headRefName\":\"$BRANCH\",\"headRefOid\":\"$HEAD_SHA\",\"baseRefName\":\"main\",\"headRepository\":$bad_entry}]"
        assert_refused_unchanged "repo-lookup-bad-$index" "$WORK_TREE" "$LOOKUP_REASON" \
            --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    done

    create_world repo-view-mismatch
    stub_respond pr-list '' '[]'
    stub_create_ok "$BRANCH" "$HEAD_SHA" R_x
    assert_blocker repo-view-mismatch "$WORK_TREE" "$REPO_MISMATCH_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world repo-view-null
    stub_respond pr-list '' '[]'
    stub_create_ok "$BRANCH" "$HEAD_SHA" null
    assert_blocker repo-view-null "$WORK_TREE" "$REPO_MISMATCH_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world repo-view-bad-type
    stub_respond pr-list '' '[]'
    stub_respond pr-create '' "$PR_URL"$'\n'
    stub_respond pr-view '' "{\"headRefName\":\"$BRANCH\",\"headRefOid\":\"$HEAD_SHA\",\"headRepository\":\"R_o\"}"
    assert_blocker repo-view-bad-type "$WORK_TREE" "$VIEW_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world repo-view-bad-type-unknown
    stub_respond pr-list '' '[]'
    stub_respond repo-view '' '' 1
    stub_respond pr-create '' "$PR_URL"$'\n'
    stub_respond pr-view '' "{\"headRefName\":\"$BRANCH\",\"headRefOid\":\"$HEAD_SHA\",\"headRepository\":\"R_o\"}"
    assert_blocker repo-view-bad-type-unknown "$WORK_TREE" "$VIEW_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world repo-gh-fails
    stub_respond pr-list '' '[]'
    stub_respond repo-view '' '' 1 'GraphQL: Could not resolve to a Repository'
    stub_create_ok "$BRANCH" "$HEAD_SHA" R_x
    assert_success repo-gh-fails "$WORK_TREE" "$(expected_block true "$REPO_UNKNOWN_WARNING")" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal repo-gh-fails-reads 1 "$(call_count pr-list)" "no read after the push when the id is unknown"
    assert_branch_pushed repo-gh-fails-pushed

    create_world repo-gh-fails-own-pr
    stub_respond pr-list '' "[$(pr_entry 7 "$BRANCH" main "$HEAD_SHA")]"
    stub_respond repo-view '' '' 1
    stub_respond pr-create '' '' 1 "a pull request for branch \"$BRANCH\" into branch \"main\" already exists"
    assert_blocker repo-gh-fails-own-pr "$WORK_TREE" "$CREATE_FAILED_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal repo-gh-fails-own-pr-reads 1 "$(call_count pr-list)" "no text-keyed reuse when the id is unknown"
    assert_equal repo-gh-fails-own-pr-create 1 "$(call_count pr-create)" "create ran"

    create_world repo-local-path
    run_git "$WORK_TREE" remote set-url origin "$ORIGIN_DIR"
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success repo-local-path "$WORK_TREE" "$(expected_block true "$REPO_UNKNOWN_WARNING")" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal repo-local-path-no-repo-view 0 "$(call_count repo-view)" "a local path is never passed to gh"
    assert_branch_pushed repo-local-path-pushed

    create_world repo-ssh-scheme
    run_git "$WORK_TREE" remote set-url origin 'ssh://git@github.com/o/r.git'
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success repo-ssh-scheme "$WORK_TREE" "$(expected_block true)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal repo-ssh-scheme-args "$(printf 'repo\nview\n--json\nid\n--\nssh://git@github.com/o/r.git')" \
        "$(cat "$GH_STUB_DIR/repo-view.1.args")" "gh repo view reads the ssh:// URL"

    index=0
    for bad_view in 'not json' '{"id":5}' '{"id":"a b"}' '{"id":""}' '{"id":"R_o\n"}' '[]' '{"name":"r"}' \
        '{"id":"R_o"}{"id":"R_x"}' ''; do
        index=$((index + 1))
        create_world "repo-view-bad-$index"
        stub_respond pr-list '' '[]'
        stub_respond repo-view '' "$bad_view"
        stub_create_ok
        assert_blocker "repo-view-bad-$index" "$WORK_TREE" "$REPO_VIEW_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
        assert_branch_pushed "repo-view-bad-$index-pushed"
        assert_equal "repo-view-bad-$index-no-create" 0 "$(call_count pr-create)" "no gh pr create"
    done

    create_world repo-triangular
    mkdir -p "$FAKE_SSH_ROOT/f"
    run_git "$FAKE_SSH_ROOT/f" init -q --bare r.git
    run_git "$WORK_TREE" remote add fork 'git@github.com:f/r.git'
    run_git "$WORK_TREE" push -q origin "refs/heads/$BRANCH:refs/heads/$BRANCH"
    run_git "$WORK_TREE" config "branch.$BRANCH.remote" origin
    run_git "$WORK_TREE" config "branch.$BRANCH.merge" "refs/heads/$BRANCH"
    run_git "$WORK_TREE" config "branch.$BRANCH.pushRemote" fork
    stub_respond repo-view '' '{"id":"R_f"}'$'\n'
    stub_respond pr-list '' "[$(pr_entry 9 "$BRANCH" main "$HEAD_SHA"),$(pr_entry 7 "$BRANCH" main "$HEAD_SHA" R_f)]"
    assert_success repo-triangular "$WORK_TREE" "$(expected_block false)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal repo-triangular-args "$(printf 'repo\nview\n--json\nid\n--\ngit@github.com:f/r.git')" \
        "$(cat "$GH_STUB_DIR/repo-view.1.args")" "gh repo view reads the push remote URL"
    assert_equal repo-triangular-fork-ref "$HEAD_SHA" \
        "$(git --git-dir="$FAKE_SSH_ROOT/f/r.git" rev-parse "refs/heads/$BRANCH")" "push landed in the fork"
}

# ── Create and verify failures ──────────────────────────────────────────────

test_create_failures() {
    create_world create-gh-fails
    stub_respond pr-list '' '[]'
    stub_respond pr-create '' '' 1 'GraphQL: something went wrong'
    assert_blocker create-gh-fails "$WORK_TREE" "$CREATE_FAILED_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal create-gh-fails-no-view 0 "$(call_count pr-view)" "no gh pr view"

    local bad_output index=0
    for bad_output in '' 'not a url' "$PR_URL extra" "$PR_URL"$'\n'"$PR_URL" 'https://github.com/o/r/pull/7$(x)' \
        'http://github.com/o/r/pull/7' 'https://github.com/o/r/issues/7' 'https://github.com/o/r/pull/'; do
        index=$((index + 1))
        create_world "create-bad-url-$index"
        stub_respond pr-list '' '[]'
        stub_respond pr-create '' "$bad_output"$'\n'
        assert_blocker "create-bad-url-$index" "$WORK_TREE" "$URL_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    done

    create_world view-fails
    stub_respond pr-list '' '[]'
    stub_respond pr-create '' "$PR_URL"$'\n'
    stub_respond pr-view '' '' 1
    assert_blocker view-fails "$WORK_TREE" "$VIEW_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world view-bad-json
    stub_respond pr-list '' '[]'
    stub_respond pr-create '' "$PR_URL"$'\n'
    stub_respond pr-view '' '{"headRefName":"feat/x"}'
    assert_blocker view-bad-json "$WORK_TREE" "$VIEW_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world view-head-mismatch
    stub_respond pr-list '' '[]'
    stub_create_ok main
    assert_blocker view-head-mismatch "$WORK_TREE" "$HEAD_MISMATCH_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world view-oid-mismatch
    stub_respond pr-list '' '[]'
    stub_create_ok "$BRANCH" "$TRUNK_SHA"
    assert_blocker view-oid-mismatch "$WORK_TREE" "$OID_MISMATCH_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
}

# ── Push outcomes through the real push-branch.sh ───────────────────────────

test_push_outcomes() {
    local hook_path
    create_world push-rejected
    hook_path="$ORIGIN_DIR/hooks/pre-receive"
    printf '#!/bin/sh\necho denied >&2\nexit 1\n' >"$hook_path"
    chmod +x "$hook_path"
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success push-rejected-warn "$WORK_TREE" "$(expected_block true "$REJECT_WARNING")" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal push-rejected-remote "refs/heads/main $TRUNK_SHA" "$(list_remote_refs)" "branch not on its remote"

    create_world push-rejected-gh-aborts
    hook_path="$ORIGIN_DIR/hooks/pre-receive"
    printf '#!/bin/sh\nexit 1\n' >"$hook_path"
    chmod +x "$hook_path"
    stub_respond pr-list '' '[]'
    stub_respond pr-create '' '' 1 'aborted: you must first push the current branch to a remote'
    assert_blocker push-rejected-gh-aborts "$WORK_TREE" "$CREATE_FAILED_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world push-rejected-explicit
    hook_path="$ORIGIN_DIR/hooks/pre-receive"
    printf '#!/bin/sh\nexit 1\n' >"$hook_path"
    chmod +x "$hook_path"
    stub_respond pr-list '' '[]'
    assert_blocker push-rejected-explicit "$WORK_TREE" 'push was rejected' \
        --head "$BRANCH" --base main --remote origin --inputs "$INPUTS_REL"
    assert_equal push-rejected-explicit-no-create 0 "$(call_count pr-create)" "no gh pr create"

    create_world no-origin
    run_git "$WORK_TREE" remote remove origin
    stub_respond pr-list '' '[]'
    stub_respond pr-create '' '' 1 'aborted: you must first push the current branch to a remote'
    assert_blocker no-origin "$WORK_TREE" "$CREATE_FAILED_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world no-origin-reuse
    run_git "$WORK_TREE" remote remove origin
    stub_respond pr-list '' "[$(pr_entry 7 "$BRANCH" main "$HEAD_SHA")]"
    stub_respond pr-create '' '' 1 "a pull request for branch \"$BRANCH\" into branch \"main\" already exists"
    assert_blocker no-origin-reuse "$WORK_TREE" "$CREATE_FAILED_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world expect-mismatch
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_refused_unchanged expect-mismatch "$WORK_TREE" "$EXPECT_MISMATCH_REASON" \
        --head "$BRANCH" --base main --expect-commit "$TRUNK_SHA" --inputs "$INPUTS_REL"

    create_world head-mismatch
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_refused_unchanged head-mismatch "$WORK_TREE" "$PUSH_MISMATCH_REASON" \
        --head other --base main --inputs "$INPUTS_REL"

    create_world base-is-branch
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_refused_unchanged base-is-branch "$WORK_TREE" "$PUSH_MISMATCH_REASON" \
        --head "$BRANCH" --base "$BRANCH" --inputs "$INPUTS_REL"
}

# ── Strict parse of push-branch.sh output (fake child in a copied tree) ─────

test_push_output_parse() {
    local copy_root="$WORKDIR/plugin-copy" fake_out index=0
    mkdir -p "$copy_root/skills/push-branch/scripts" "$copy_root/skills/open-plan-pr/scripts"
    cp -R "$REPO_ROOT/plugin/skills/_shared" "$copy_root/skills/_shared"
    cp "$ENGINE" "$copy_root/skills/open-plan-pr/scripts/open-plan-pr.sh"
    cat >"$copy_root/skills/push-branch/scripts/push-branch.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$FAKE_PUSH_OUT"
[ -z "${FAKE_PUSH_ERR:-}" ] || printf '%s\n' "$FAKE_PUSH_ERR" >&2
exit "${FAKE_PUSH_RC:-0}"
EOF
    ENGINE_UNDER_TEST="$copy_root/skills/open-plan-pr/scripts/open-plan-pr.sh"

    create_world fake-push-ok
    stub_respond pr-list '' '[]'
    stub_create_ok
    FAKE_PUSH_OUT="$(printf 'branch: %s\ncommit: %s\nremote: origin\n' "$BRANCH" "$HEAD_SHA")" \
        assert_success fake-push-ok "$WORK_TREE" "$(expected_block true)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    for fake_out in \
        '' \
        "branch: $BRANCH" \
        "$(printf 'branch: other\ncommit: %s' "$HEAD_SHA")" \
        "$(printf 'commit: %s\nbranch: %s' "$HEAD_SHA" "$BRANCH")" \
        "$(printf 'branch: %s\ncommit: %s' "$BRANCH" "${HEAD_SHA:0:12}")" \
        "$(printf 'branch: %s\ncommit: %s\nwarning: something else' "$BRANCH" "$HEAD_SHA")" \
        "$(printf 'branch: %s\ncommit: %s\nwarning: %s\nextra' "$BRANCH" "$HEAD_SHA" "$REJECT_WARNING")" \
        "$(printf ' branch: %s\ncommit: %s' "$BRANCH" "$HEAD_SHA")"; do
        index=$((index + 1))
        create_world "fake-push-bad-$index"
        stub_respond pr-list '' '[]'
        stub_create_ok
        FAKE_PUSH_OUT="$fake_out" assert_blocker "fake-push-bad-$index" "$WORK_TREE" "$UNEXPECTED_PUSH_REASON" \
            --head "$BRANCH" --base main --inputs "$INPUTS_REL"
        assert_equal "fake-push-bad-$index-no-create" 0 "$(call_count pr-create)" "no gh pr create"
    done

    create_world fake-push-expect
    stub_respond pr-list '' '[]'
    stub_create_ok
    FAKE_PUSH_OUT="$(printf 'branch: %s\ncommit: %s\nremote: origin\n' "$BRANCH" "$HEAD_SHA")" assert_blocker fake-push-expect \
        "$WORK_TREE" "$UNEXPECTED_PUSH_REASON" --head "$BRANCH" --base main --expect-commit "$TRUNK_SHA" --inputs "$INPUTS_REL"

    index=0
    for fake_out in \
        "$(printf 'branch: %s\ncommit: %s' "$BRANCH" "$HEAD_SHA")" \
        "$(printf 'branch: %s\ncommit: %s\nremote: ' "$BRANCH" "$HEAD_SHA")" \
        "$(printf 'branch: %s\ncommit: %s\nremote:origin' "$BRANCH" "$HEAD_SHA")" \
        "$(printf 'branch: %s\ncommit: %s\nremote: -x' "$BRANCH" "$HEAD_SHA")" \
        "$(printf 'branch: %s\ncommit: %s\nremote: a..b' "$BRANCH" "$HEAD_SHA")" \
        "$(printf 'branch: %s\ncommit: %s\nremote: o r' "$BRANCH" "$HEAD_SHA")" \
        "$(printf 'branch: %s\ncommit: %s\nremote: origin\nremote: origin' "$BRANCH" "$HEAD_SHA")" \
        "$(printf 'branch: %s\ncommit: %s\nremote: origin\nwarning: %s' "$BRANCH" "$HEAD_SHA" "$DEFERRED_WARNING")" \
        "$(printf 'branch: %s\ncommit: %s\nwarning: %s\nremote: origin' "$BRANCH" "$HEAD_SHA" "$DEFERRED_WARNING")" \
        "$(printf 'branch: %s\ncommit: %s\nwarning: %s\nwarning: %s' "$BRANCH" "$HEAD_SHA" "$DEFERRED_WARNING" "$REJECT_WARNING")" \
        "$(printf 'branch: %s\ncommit: %s\nremote: origin\nwarning: something else' "$BRANCH" "$HEAD_SHA")" \
        "$(printf 'branch: %s\ncommit: %s\nremote: origin\nwarning: %s\nextra' "$BRANCH" "$HEAD_SHA" "$REJECT_WARNING")" \
        "$(printf 'branch: %s\nremote: origin\ncommit: %s' "$BRANCH" "$HEAD_SHA")"; do
        index=$((index + 1))
        create_world "fake-push-remote-bad-$index"
        stub_respond pr-list '' '[]'
        stub_create_ok
        FAKE_PUSH_OUT="$fake_out" assert_blocker "fake-push-remote-bad-$index" "$WORK_TREE" "$UNEXPECTED_PUSH_REASON" \
            --head "$BRANCH" --base main --inputs "$INPUTS_REL"
        assert_equal "fake-push-remote-bad-$index-no-create" 0 "$(call_count pr-create)" "no gh pr create"
    done

    create_world fake-push-remote-other
    stub_respond pr-list '' '[]'
    stub_create_ok
    FAKE_PUSH_OUT="$(printf 'branch: %s\ncommit: %s\nremote: other\n' "$BRANCH" "$HEAD_SHA")" assert_blocker fake-push-remote-other \
        "$WORK_TREE" "$UNEXPECTED_PUSH_REASON" --head "$BRANCH" --base main --remote origin --inputs "$INPUTS_REL"

    create_world fake-push-remote-explicit
    stub_respond pr-list '' '[]'
    stub_create_ok
    FAKE_PUSH_OUT="$(printf 'branch: %s\ncommit: %s\nremote: origin\n' "$BRANCH" "$HEAD_SHA")" assert_success fake-push-remote-explicit \
        "$WORK_TREE" "$(expected_block true)" --head "$BRANCH" --base main --remote origin --inputs "$INPUTS_REL"

    create_world fake-push-rejected
    stub_respond pr-list '' "[$(pr_entry 7 "$BRANCH" main "$HEAD_SHA")]"
    stub_create_ok
    FAKE_PUSH_OUT="$(printf 'branch: %s\ncommit: %s\nremote: origin\nwarning: %s\n' "$BRANCH" "$HEAD_SHA" "$REJECT_WARNING")" \
        assert_success fake-push-rejected "$WORK_TREE" "$(expected_block true "$REJECT_WARNING")" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal fake-push-rejected-no-repo-view 0 "$(call_count repo-view)" "no gh repo view after a rejected push"
    assert_equal fake-push-rejected-reads 1 "$(call_count pr-list)" "no reuse after a rejected push"

    create_world fake-push-deferred
    stub_respond pr-list '' '[]'
    stub_create_ok
    FAKE_PUSH_OUT="$(printf 'branch: %s\ncommit: %s\nwarning: %s\n' "$BRANCH" "$HEAD_SHA" "$DEFERRED_WARNING")" \
        assert_success fake-push-deferred "$WORK_TREE" "$(expected_block true "$DEFERRED_WARNING")" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal fake-push-deferred-no-repo-view 0 "$(call_count repo-view)" "no gh repo view after a deferred push"

    create_world fake-push-two-urls
    run_git "$WORK_TREE" remote set-url --add --push origin "$ORIGIN_URL"
    run_git "$WORK_TREE" remote set-url --add --push origin 'git@github.com:o/r2.git'
    stub_respond pr-list '' '[]'
    stub_create_ok
    FAKE_PUSH_OUT="$(printf 'branch: %s\ncommit: %s\nremote: origin\n' "$BRANCH" "$HEAD_SHA")" \
        assert_success fake-push-two-urls "$WORK_TREE" "$(expected_block true "$REPO_UNKNOWN_WARNING")" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal fake-push-two-urls-no-repo-view 0 "$(call_count repo-view)" "two push URLs are never passed to gh"

    create_world fake-push-https-userinfo
    run_git "$WORK_TREE" remote set-url --push origin 'https://u@github.com/o/r.git'
    stub_respond pr-list '' '[]'
    stub_create_ok
    FAKE_PUSH_OUT="$(printf 'branch: %s\ncommit: %s\nremote: origin\n' "$BRANCH" "$HEAD_SHA")" \
        assert_success fake-push-https-userinfo "$WORK_TREE" "$(expected_block true "$REPO_UNKNOWN_WARNING")" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal fake-push-https-userinfo-no-repo-view 0 "$(call_count repo-view)" "an https URL with @ is never passed to gh"

    create_world fake-push-https
    run_git "$WORK_TREE" remote set-url --push origin 'https://github.com/o/r.git'
    stub_respond pr-list '' '[]'
    stub_create_ok
    FAKE_PUSH_OUT="$(printf 'branch: %s\ncommit: %s\nremote: origin\n' "$BRANCH" "$HEAD_SHA")" \
        assert_success fake-push-https "$WORK_TREE" "$(expected_block true)" --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal fake-push-https-args "$(printf 'repo\nview\n--json\nid\n--\nhttps://github.com/o/r.git')" \
        "$(cat "$GH_STUB_DIR/repo-view.1.args")" "gh repo view reads the push URL"

    create_world fake-push-unknown-remote
    stub_respond pr-list '' '[]'
    stub_create_ok
    FAKE_PUSH_OUT="$(printf 'branch: %s\ncommit: %s\nremote: gone\n' "$BRANCH" "$HEAD_SHA")" \
        assert_success fake-push-unknown-remote "$WORK_TREE" "$(expected_block true "$REPO_UNKNOWN_WARNING")" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal fake-push-unknown-remote-no-repo-view 0 "$(call_count repo-view)" "a remote with no URL is never passed to gh"

    create_world fake-push-blocker
    stub_respond pr-list '' '[]'
    FAKE_PUSH_OUT='' FAKE_PUSH_RC=1 FAKE_PUSH_ERR='blocker: push was rejected' assert_blocker fake-push-blocker \
        "$WORK_TREE" 'push was rejected' --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world fake-push-crash
    stub_respond pr-list '' '[]'
    FAKE_PUSH_OUT='' FAKE_PUSH_RC=2 FAKE_PUSH_ERR='boom' assert_blocker fake-push-crash \
        "$WORK_TREE" "$PUSH_FAILED_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    create_world fake-push-silent
    stub_respond pr-list '' '[]'
    FAKE_PUSH_OUT='' FAKE_PUSH_RC=1 assert_blocker fake-push-silent \
        "$WORK_TREE" "$PUSH_FAILED_REASON" --head "$BRANCH" --base main --inputs "$INPUTS_REL"

    rm -f "$copy_root/skills/push-branch/scripts/push-branch.sh"
    create_world push-script-missing
    stub_respond pr-list '' '[]'
    assert_refused_unchanged push-script-missing "$WORK_TREE" \
        'required script missing: skills/push-branch/scripts/push-branch.sh; refusing to proceed' \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
    assert_equal push-script-missing-no-gh 0 "$(call_count pr-list)" "no gh call"

    ENGINE_UNDER_TEST="$ENGINE"
}

# ── Subfolder invocation ────────────────────────────────────────────────────

test_subfolder_invocation() {
    create_world subfolder
    stub_respond pr-list '' '[]'
    stub_create_ok
    assert_success subfolder "$WORK_TREE/sub" "$(expected_block true)" \
        --head "$BRANCH" --base main --inputs "../$INPUTS_REL"
    assert_branch_pushed subfolder-pushed

    create_world subfolder-relative
    assert_refused_unchanged subfolder-relative-to-start "$WORK_TREE/sub" "$INPUTS_MISSING_REASON" \
        --head "$BRANCH" --base main --inputs "$INPUTS_REL"
}

# ── Run ──────────────────────────────────────────────────────────────────────

test_usage_errors
test_identifier_gates
test_delay_gate
test_gh_missing
test_not_a_checkout
test_inputs_file_refusals
test_inputs_field_refusals
test_git_state_refusals
test_lookup_refusals
test_create
test_title_not_expanded
test_draft
test_comment_field_refusals
test_comment
test_reuse
test_head_repository
test_create_failures
test_push_outcomes
test_push_output_parse
test_subfolder_invocation

echo
echo "open-plan-pr engine tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
