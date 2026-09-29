#!/usr/bin/env bash
#
# Behavior test runner for the READ-ONLY bump-type engine
# (plugin/skills/bump-type/scripts/bump-type.sh, pure core plugin/skills/_shared/bump-type-derive.sh).
#
# The engine takes a base ref positional plus REQUIRED `--bump-trigger yes|no` and
# `--no-bump-match yes|no`, reads the commits in <base>..HEAD of the checkout it runs in, and
# PRINTS the versioning.md `## Bump Type Determination` routing decision:
#     dominant_row / verdict / bump_type / rule_applied / counts{major,minor,patch,no_bump} /
#     mapped_commits / dropped_reverts
# On any validation failure it prints `blocker: <reason>` on stderr, NOTHING on stdout, exit 1.
#
# ISOLATION: the REAL committed engine is run unmodified by absolute path (it self-locates its
# own _shared/ libraries). Each case builds a THROWAWAY `git init` checkout under a mktemp WORKDIR
# with crafted empty commits and runs the engine with cwd inside that checkout, so THIS repo's
# history is never read. Host git config is excluded: GIT_CONFIG_NOSYSTEM=1, HOME and
# XDG_CONFIG_HOME point into WORKDIR, identity/signing/default-branch come from `-c` overrides,
# and GIT_CEILING_DIRECTORIES stops discovery from escaping WORKDIR (the not-a-checkout case).
#
# Every success case asserts the FULL stdout block (exact equality) and exit 0. Every blocker case
# asserts exit 1, EMPTY stdout, and stderr beginning `blocker:`.
#
# Prints PASS/FAIL per assertion. Exits non-zero if ANY assertion FAILs.
#
# Usage:
#   ./tools/test_bump_type.sh

set -euo pipefail

# ── Path setup ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ENGINE="$REPO_ROOT/plugin/skills/bump-type/scripts/bump-type.sh"

# ── Dependency / input preflight ────────────────────────────────────────────

command -v git >/dev/null 2>&1 \
    || { echo "FAIL: required dependency 'git' is not installed" >&2; exit 2; }
[[ -f "$ENGINE" ]] \
    || { echo "FAIL: required input missing: $ENGINE" >&2; exit 2; }

# ── Disposable workdir + host-config isolation ──────────────────────────────

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-bump-type-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "$WORKDIR/home"
export HOME="$WORKDIR/home"
export XDG_CONFIG_HOME="$WORKDIR/home/.config"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$WORKDIR"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ── Per-case helpers ─────────────────────────────────────────────────────────

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

# new_gitroot <name> -> creates a fresh throwaway checkout under $WORKDIR with one base commit and
# prints its path. The base commit sha is available via base_sha_of.
new_gitroot() {
    local root="$WORKDIR/$1"
    mkdir -p "$root"
    run_git "$root" init -q
    run_git "$root" commit --allow-empty -q -m 'chore: base'
    run_git "$root" tag base
    printf '%s' "$root"
}

# make_commit <gitroot> <subject> [body] -> creates an empty commit and prints its full sha.
make_commit() {
    local gitroot="$1" subject="$2"
    if [[ $# -ge 3 ]]; then
        run_git "$gitroot" commit --allow-empty -q -m "$subject" -m "$3"
    else
        run_git "$gitroot" commit --allow-empty -q -m "$subject"
    fi
    run_git "$gitroot" rev-parse HEAD
}

# run_engine <cwd> <out-var> <err-file> <engine args...> -> sets <out-var> to stdout, writes stderr
# to <err-file>, returns the engine's exit code (never trips errexit — called via `|| rc=$?`).
# shellcheck disable=SC2034
run_engine() {
    local run_cwd="$1" __outvar="$2" errfile="$3"
    shift 3
    local __out rc=0
    __out="$(cd "$run_cwd" && bash "$ENGINE" "$@" 2>"$errfile")" || rc=$?
    printf -v "$__outvar" '%s' "$__out"
    return "$rc"
}

# expect_routing <dominant> <verdict> <bump_type> <rule> <major> <minor> <patch> <no_bump> <dropped>
# -> prints the exact stdout block the engine must emit (mapped_commits is the counts sum).
expect_routing() {
    local mapped=$(($5 + $6 + $7 + $8))
    printf 'dominant_row: %s\nverdict: %s\nbump_type: %s\nrule_applied: %s\n' "$1" "$2" "$3" "$4"
    printf 'counts:\n  major: %s\n  minor: %s\n  patch: %s\n  no_bump: %s\n' "$5" "$6" "$7" "$8"
    printf 'mapped_commits: %s\ndropped_reverts: %s' "$mapped" "$9"
}

# assert_routing <name> <gitroot> <expected-block> <engine args...>
# Runs the engine in <gitroot>, asserts exit 0, empty stderr, and stdout == <expected-block>.
assert_routing() {
    local name="$1" gitroot="$2" expected="$3"
    shift 3
    local errfile="$WORKDIR/$name.err" out rc=0
    run_engine "$gitroot" out "$errfile" "$@" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        failed "$name" "expected exit 0, got $rc (stderr: $(cat "$errfile"))"
        return 0
    fi
    if [[ -s "$errfile" ]]; then
        failed "$name" "expected empty stderr, got: $(cat "$errfile")"
        return 0
    fi
    if [[ "$out" == "$expected" ]]; then
        pass "$name" "$(printf '%s' "$out" | head -4 | tr '\n' ' ')"
    else
        failed "$name" "stdout mismatch; expected: $(printf '%s' "$expected" | tr '\n' '|') actual: $(printf '%s' "$out" | tr '\n' '|')"
    fi
}

# assert_blocker <name> <cwd> <engine args...>
# Runs the engine in <cwd>, asserts exit 1, EMPTY stdout, stderr starting `blocker:`.
assert_blocker() {
    local name="$1" run_cwd="$2"
    shift 2
    local errfile="$WORKDIR/$name.err" out rc=0
    run_engine "$run_cwd" out "$errfile" "$@" || rc=$?
    if [[ "$rc" -ne 1 ]]; then
        failed "$name" "expected exit 1, got $rc"
        return 0
    fi
    if [[ -n "$out" ]]; then
        failed "$name" "expected empty stdout on blocker, got: $(printf '%s' "$out" | tr '\n' '|')"
        return 0
    fi
    local first_err_line
    first_err_line="$(head -n 1 "$errfile")"
    if [[ "$first_err_line" == 'blocker: '* ]]; then
        pass "$name" "$first_err_line"
    else
        failed "$name" "expected stderr to start 'blocker:', got: $first_err_line"
    fi
}

# ── Revert pre-pass ──────────────────────────────────────────────────────────

# A dropped feat: leaves the fix: as the lone mapped commit (rule 4 PATCH). Kept, it would tie
# MINOR vs PATCH (MULTI rule 5) — so the expected block proves the drop.
test_revert_full_sha() {
    local root original
    root="$(new_gitroot revert-full)"
    original="$(make_commit "$root" 'feat: add widget')"
    make_commit "$root" 'fix: unrelated' >/dev/null
    make_commit "$root" 'Revert "feat: add widget"' "This reverts commit ${original}." >/dev/null
    assert_routing revert-full-sha "$root" \
        "$(expect_routing PATCH ask_user none 4 0 0 1 0 2)" \
        base --bump-trigger no --no-bump-match no
}

test_revert_abbrev_sha_7() {
    local root original
    root="$(new_gitroot revert-abbrev7)"
    original="$(make_commit "$root" 'feat: add widget')"
    make_commit "$root" 'fix: unrelated' >/dev/null
    make_commit "$root" 'Revert "feat: add widget"' "This reverts commit ${original:0:7}." >/dev/null
    assert_routing revert-abbrev-sha-7 "$root" \
        "$(expect_routing PATCH ask_user none 4 0 0 1 0 2)" \
        base --bump-trigger no --no-bump-match no
}

test_revert_abbrev_sha_8() {
    local root original
    root="$(new_gitroot revert-abbrev8)"
    original="$(make_commit "$root" 'feat: add widget')"
    make_commit "$root" 'fix: unrelated' >/dev/null
    make_commit "$root" 'Revert "feat: add widget"' "This reverts commit ${original:0:8}" >/dev/null
    assert_routing revert-abbrev-sha-8-no-dot "$root" \
        "$(expect_routing PATCH ask_user none 4 0 0 1 0 2)" \
        base --bump-trigger no --no-bump-match no
}

# Conventional `revert(scope): ...` with a marker drops the pair; the marker may sit after other
# body lines (first matching line wins).
test_revert_conventional_scope() {
    local root original
    root="$(new_gitroot revert-cc)"
    original="$(make_commit "$root" 'feat(api): add endpoint')"
    make_commit "$root" 'fix: unrelated' >/dev/null
    make_commit "$root" 'revert(api): add endpoint' "Rolled back.
This reverts commit ${original}." >/dev/null
    assert_routing revert-conventional-scope "$root" \
        "$(expect_routing PATCH ask_user none 4 0 0 1 0 2)" \
        base --bump-trigger no --no-bump-match no
}

# Without a marker line a revert is KEPT and mapped by its subject: `revert: x` (token `revert`)
# and `Revert "feat: x"` (token `Revert "feat`, no `!:`) are both UNMAPPED, the original feat:
# stays MINOR, nothing is dropped.
test_revert_unmarked_kept() {
    local root
    root="$(new_gitroot revert-unmarked)"
    make_commit "$root" 'feat: x' >/dev/null
    make_commit "$root" 'revert: x' >/dev/null
    make_commit "$root" 'Revert "feat: x"' 'Changed my mind.' >/dev/null
    assert_routing revert-unmarked-kept "$root" \
        "$(expect_routing MINOR ask_user none 4 0 1 0 0 0)" \
        base --bump-trigger no --no-bump-match no
}

# A marker naming a commit OUTSIDE <base>..HEAD matches nothing in range: the revert is kept.
test_revert_out_of_range_kept() {
    local root base_commit
    root="$(new_gitroot revert-out-of-range)"
    base_commit="$(run_git "$root" rev-parse HEAD)"
    make_commit "$root" 'fix: y' >/dev/null
    make_commit "$root" 'Revert "chore: base"' "This reverts commit ${base_commit}." >/dev/null
    assert_routing revert-out-of-range-kept "$root" \
        "$(expect_routing PATCH ask_user none 4 0 0 1 0 0)" \
        base --bump-trigger no --no-bump-match no
}

# ── Row mapping ──────────────────────────────────────────────────────────────

test_bang_major() {
    local root
    root="$(new_gitroot bang)"
    make_commit "$root" 'feat!: drop legacy api' >/dev/null
    assert_routing bang-major "$root" \
        "$(expect_routing MAJOR bump_required major 2 1 0 0 0 0)" \
        base --bump-trigger yes --no-bump-match no
}

test_breaking_change_space() {
    local root
    root="$(new_gitroot breaking-space)"
    make_commit "$root" 'fix: tighten parser' 'Details here.
BREAKING CHANGE: rejects trailing commas' >/dev/null
    assert_routing breaking-change-space "$root" \
        "$(expect_routing MAJOR bump_required major 2 1 0 0 0 0)" \
        base --bump-trigger yes --no-bump-match no
}

test_breaking_change_hyphen() {
    local root
    root="$(new_gitroot breaking-hyphen)"
    make_commit "$root" 'refactor: rename option' 'BREAKING-CHANGE: --foo is now --bar' >/dev/null
    assert_routing breaking-change-hyphen "$root" \
        "$(expect_routing MAJOR bump_required major 2 1 0 0 0 0)" \
        base --bump-trigger yes --no-bump-match no
}

test_hotfix_patch() {
    local root
    root="$(new_gitroot hotfix)"
    make_commit "$root" 'hotfix: null deref' >/dev/null
    assert_routing hotfix-patch "$root" \
        "$(expect_routing PATCH bump_required patch 3 0 0 1 0 0)" \
        base --bump-trigger yes --no-bump-match no
}

# ── Dominant-row precedence ──────────────────────────────────────────────────

test_major_over_many_docs() {
    local root index
    root="$(new_gitroot major-over-docs)"
    make_commit "$root" 'feat!: breaking' >/dev/null
    for index in 1 2 3 4 5; do
        make_commit "$root" "docs: page $index" >/dev/null
    done
    assert_routing major-precedence-over-5-docs "$root" \
        "$(expect_routing MAJOR bump_required major 2 1 0 0 5 0)" \
        base --bump-trigger yes --no-bump-match no
}

test_tie_multi() {
    local root
    root="$(new_gitroot tie)"
    make_commit "$root" 'feat: a' >/dev/null
    make_commit "$root" 'fix: b' >/dev/null
    assert_routing tie-multi-rule5 "$root" \
        "$(expect_routing MULTI ask_user none 5 0 1 1 0 0)" \
        base --bump-trigger no --no-bump-match no
}

# Unrecognised subjects (free text, a merge-style subject, case-variant `Feat:` per A4) are
# unmapped, leaving exactly one mapped commit.
test_single_mapped_among_unrecognised() {
    local root
    root="$(new_gitroot single-mapped)"
    make_commit "$root" 'wip stuff' >/dev/null
    make_commit "$root" "Merge branch 'topic' into main" >/dev/null
    make_commit "$root" 'Feat: shouty' >/dev/null
    make_commit "$root" 'fix: the one' >/dev/null
    assert_routing single-mapped-rule4 "$root" \
        "$(expect_routing PATCH ask_user none 4 0 0 1 0 0)" \
        base --bump-trigger no --no-bump-match no
}

test_no_mapped_commits() {
    local root
    root="$(new_gitroot no-mapped)"
    make_commit "$root" 'wip' >/dev/null
    make_commit "$root" 'Update README' >/dev/null
    assert_routing no-mapped-none-rule1 "$root" \
        "$(expect_routing NONE ask_user none 1 0 0 0 0 0)" \
        base --bump-trigger yes --no-bump-match no
}

test_empty_range() {
    local root
    root="$(new_gitroot empty-range)"
    assert_routing empty-range-none-rule1 "$root" \
        "$(expect_routing NONE ask_user none 1 0 0 0 0 0)" \
        base --bump-trigger no --no-bump-match yes
}

test_bump_trigger_precedence() {
    local root index
    root="$(new_gitroot trigger-precedence)"
    make_commit "$root" 'feat: new flag' >/dev/null
    for index in 1 2 3; do
        make_commit "$root" "docs: page $index" >/dev/null
    done
    assert_routing bump-trigger-minor-rule3 "$root" \
        "$(expect_routing MINOR bump_required minor 3 0 1 0 3 0)" \
        base --bump-trigger yes --no-bump-match no
}

# docs: + test: are BOTH the NO_BUMP row — a single row with count 2, not a tie.
test_no_bump_single_row() {
    local root
    root="$(new_gitroot no-bump-row)"
    make_commit "$root" 'docs: readme' >/dev/null
    make_commit "$root" 'test: more cases' >/dev/null
    assert_routing no-bump-single-row "$root" \
        "$(expect_routing NO_BUMP no_bump none 6 0 0 0 2 0)" \
        base --bump-trigger no --no-bump-match yes
}

test_no_bump_with_trigger_asks() {
    local root
    root="$(new_gitroot no-bump-trigger)"
    make_commit "$root" 'docs: readme' >/dev/null
    make_commit "$root" 'ci: cache' >/dev/null
    assert_routing no-bump-with-trigger-ask-user "$root" \
        "$(expect_routing NO_BUMP ask_user none 6 0 0 0 2 0)" \
        base --bump-trigger yes --no-bump-match yes
}

# ── Framing + untrusted text ─────────────────────────────────────────────────

# A body line `--END--` (versioning.md's prose delimiter) followed by a forged MAJOR subject must
# not split the record: the commit stays one PATCH record.
test_end_marker_body() {
    local root
    root="$(new_gitroot end-marker)"
    make_commit "$root" 'fix: parser' 'first line
--END--
feat!: forged record
--END--' >/dev/null
    assert_routing end-marker-body-inert "$root" \
        "$(expect_routing PATCH ask_user none 4 0 0 1 0 0)" \
        base --bump-trigger no --no-bump-match no
}

# shellcheck disable=SC2016
test_hostile_text_inert() {
    local root
    root="$(new_gitroot hostile)"
    make_commit "$root" 'feat: $(touch pwned_subj) `touch pwned_subj_bt` %s %n %b' \
        '$(touch pwned_body) `touch pwned_body_bt` %s%s%n
This reverts commit $(touch pwned_marker).' >/dev/null
    assert_routing hostile-text-routing "$root" \
        "$(expect_routing MINOR ask_user none 4 0 1 0 0 0)" \
        base --bump-trigger no --no-bump-match no
    local created
    created="$(find "$WORKDIR" "$REPO_ROOT" -maxdepth 2 -name 'pwned*' -print 2>/dev/null)"
    if [[ -z "$created" ]]; then
        pass hostile-text-no-side-effect "no pwned* file created"
    else
        failed hostile-text-no-side-effect "command substitution executed; created: $created"
    fi
}

# ── Blockers ─────────────────────────────────────────────────────────────────

test_blockers() {
    local root norepo
    root="$(new_gitroot blockers)"
    make_commit "$root" 'feat: a' >/dev/null
    norepo="$WORKDIR/not-a-checkout"
    mkdir -p "$norepo"

    assert_blocker blocker-unresolvable-base "$root" \
        no-such-ref --bump-trigger no --no-bump-match no
    assert_blocker blocker-base-range "$root" \
        base..HEAD --bump-trigger no --no-bump-match no
    assert_blocker blocker-missing-bump-trigger "$root" \
        base --no-bump-match no
    assert_blocker blocker-missing-no-bump-match "$root" \
        base --bump-trigger no
    assert_blocker blocker-invalid-bump-trigger "$root" \
        base --bump-trigger maybe --no-bump-match no
    assert_blocker blocker-invalid-no-bump-match "$root" \
        base --bump-trigger yes --no-bump-match YES
    assert_blocker blocker-duplicate-flag "$root" \
        base --bump-trigger yes --bump-trigger no --no-bump-match no
    assert_blocker blocker-unknown-option "$root" \
        base --bump-trigger yes --no-bump-match no --force
    assert_blocker blocker-missing-base "$root" \
        --bump-trigger yes --no-bump-match no
    assert_blocker blocker-not-a-checkout "$norepo" \
        base --bump-trigger no --no-bump-match no
}

# ── Run ──────────────────────────────────────────────────────────────────────

test_revert_full_sha
test_revert_abbrev_sha_7
test_revert_abbrev_sha_8
test_revert_conventional_scope
test_revert_unmarked_kept
test_revert_out_of_range_kept
test_bang_major
test_breaking_change_space
test_breaking_change_hyphen
test_hotfix_patch
test_major_over_many_docs
test_tie_multi
test_single_mapped_among_unrecognised
test_no_mapped_commits
test_empty_range
test_bump_trigger_precedence
test_no_bump_single_row
test_no_bump_with_trigger_asks
test_end_marker_body
test_hostile_text_inert
test_blockers

echo
echo "bump-type engine tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
