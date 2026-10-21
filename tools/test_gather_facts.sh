#!/usr/bin/env bash
#
# Behavior test runner for the gather-facts engine
# (plugin/skills/gather-facts/scripts/gather-facts.sh, its assembly gather-facts.jq, and the
# contract plugin/references/facts-schema.json).
#
# The engine takes `--trunk <name>`, an optional `--remote <name>` and up to 20 `--ref <number>`.
# It fetches trunk, reads the branch state, the dirty paths, the history against the merge-base,
# the branch's pull requests and each named issue or pull request, writes one facts file under
# .hivemind/facts/, and prints fixed routing lines. On a blocker it prints `blocker: <fixed
# reason>` on stderr and nothing on stdout, exit 1.
#
# ISOLATION: the REAL committed engine is run unmodified by absolute path. Each case builds a
# THROWAWAY world under a mktemp WORKDIR: a local bare repo `origin.git` as the remote and a work
# tree `w` on feat/x, so no network is ever reached. Host git config is excluded:
# GIT_CONFIG_NOSYSTEM=1, HOME and XDG_CONFIG_HOME point into WORKDIR, identity and signing come
# from `-c` overrides, and GIT_CEILING_DIRECTORIES stops discovery from escaping WORKDIR.
# The engine runs with PATH set to a folder of links to the tools it needs, so the host gh is
# never reached. A fake gh, first on PATH when a case wants it, answers `gh api graphql` from
# page files under the world's gh/ folder and logs each call; with no page file it fails. The
# engine has no test mode: the fake is only a program on PATH.
#
# Every facts file a case produces is checked for the text invariants (each text's chunks join to
# its length, no chunk passes 1000 characters) and, at the end, validated against
# facts-schema.json through plugin/workflow-src/lib/schema.js loaded by
# tests/workflow-scripts/harness.mjs. That needs Node 18 or later; without it the runner fails.
#
# THE LINE BOUND (every line of a facts file at most 1100 code points) is checked three ways.
# test_line_bound_property feeds a corpus from a seeded generator (CORPUS_SEED, no clock; the seed
# is printed on any failure) through the real engine as GitHub texts, commit subjects and paths,
# reading the whitespace set from gather-facts.jq, and a node oracle that does not use jq checks
# each text against its source. test_line_bound_every_field fills every field near its bound at
# once, with escape-dense full-cost chunks at every text site. test_line_gate gives a trunk,
# remote and branch name past the bound and expects the line blocker with nothing published.
#
# THE SCALE TESTS (test_scaling) check that the engine's work grows in line with its input. Each
# case runs the engine on a small world and on one 4 times larger: a commit subject of 250,000 and
# 1,000,000 U+0001 bytes, 10,000 and 40,000 untracked paths, 5,000 and 20,000 history paths. The
# larger run must take less than SCALE_RATIO_LIMIT times the smaller one (a quadratic cost gives
# about 16 times) and less than SCALE_SECONDS_LIMIT seconds. Times are wall clock seconds from
# bash's time keyword and are printed with each result.
#
# Prints PASS/FAIL per assertion. Exits non-zero if ANY assertion FAILs.
#
# Usage:
#   ./tools/test_gather_facts.sh

set -euo pipefail

# ── Path setup ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ENGINE="$REPO_ROOT/plugin/skills/gather-facts/scripts/gather-facts.sh"
ASSEMBLY="$REPO_ROOT/plugin/skills/gather-facts/scripts/gather-facts.jq"
SCHEMA="$REPO_ROOT/plugin/references/facts-schema.json"
SCHEMA_LIB="$REPO_ROOT/plugin/workflow-src/lib/schema.js"
HARNESS="$REPO_ROOT/tests/workflow-scripts/harness.mjs"
MIN_NODE_MAJOR=18

# ── Dependency / input preflight ────────────────────────────────────────────

for required_tool in git jq node bash; do
    command -v "$required_tool" >/dev/null 2>&1 \
        || { echo "FAIL: required dependency '$required_tool' is not installed" >&2; exit 2; }
done
node_version="$(node -p 'process.versions.node')"
node_major="${node_version%%.*}"
if ! [[ "$node_major" =~ ^[0-9]+$ ]] || (( node_major < MIN_NODE_MAJOR )); then
    echo "FAIL: node ${node_version} found; Node ${MIN_NODE_MAJOR} or later is required for the schema check" >&2
    exit 2
fi
for required_input in "$ENGINE" "$ASSEMBLY" "$SCHEMA" "$SCHEMA_LIB" "$HARNESS"; do
    [[ -f "$required_input" ]] || { echo "FAIL: required input missing: $required_input" >&2; exit 2; }
done

# ── Disposable workdir + host-config isolation ──────────────────────────────

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-gather-facts-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

mkdir -p "$WORKDIR/home" "$WORKDIR/base-bin" "$WORKDIR/stub-bin"
export HOME="$WORKDIR/home"
export XDG_CONFIG_HOME="$WORKDIR/home/.config"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$WORKDIR"
export GIT_TERMINAL_PROMPT=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GH_STUB_DIR

BASH_BIN="$(command -v bash)"
FACTS_LIST="$WORKDIR/facts-files.list"
: >"$FACTS_LIST"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ── Contracted strings (restated from the engine header; a change here is a contract change) ──

BRANCH='feat/x'
USAGE_REASON='invalid arguments; usage: gather-facts.sh --trunk <name> [--remote <name>] [--ref <number>]...'
IDENTIFIER_REASON='trunk or remote contains characters outside the safe allowlist'
NOT_WORK_TREE_REASON='not inside a git work tree'
CONTAIN_REASON='the facts folder is not contained in the checkout'
LINE_REASON='a facts line is longer than the line bound'

# ── Tool folders: links to what the engine needs, and the fake gh ───────────

for linked_tool in git jq cat mktemp mv rm mkdir date od wc dirname basename sh; do
    ln -s "$(command -v "$linked_tool")" "$WORKDIR/base-bin/$linked_tool"
done
BASE_PATH="$WORKDIR/base-bin"
STUB_PATH="$WORKDIR/stub-bin:$WORKDIR/base-bin"

cat >"$WORKDIR/stub-bin/gh" <<'STUB'
#!/bin/sh
# fake gh: answers `gh api graphql --paginate` from $GH_STUB_DIR/<pr|ref-N>.pages and .rc.
[ -n "${GH_STUB_DIR:-}" ] || exit 1
call_kind=other
call_number=''
call_fields=''
for call_arg in "$@"; do
    case "$call_arg" in
        query=*pullRequests*) call_kind=pr ;;
        query=*issueOrPullRequest*) call_kind=ref ;;
        query=*) ;;
        number=*) call_number="${call_arg#number=}"; call_fields="$call_fields $call_arg" ;;
        *) call_fields="$call_fields $call_arg" ;;
    esac
done
printf '%s%s\n' "$call_kind" "$call_fields" >>"$GH_STUB_DIR/calls.log"
if [ "$call_kind" = pr ]; then
    answer_base="$GH_STUB_DIR/pr"
else
    answer_base="$GH_STUB_DIR/ref-$call_number"
fi
[ -f "$answer_base.pages" ] || exit 1
cat "$answer_base.pages"
answer_rc=0
[ -f "$answer_base.rc" ] && answer_rc="$(cat "$answer_base.rc")"
exit "$answer_rc"
STUB
chmod +x "$WORKDIR/stub-bin/gh"

# ── World helpers ───────────────────────────────────────────────────────────

# run_git <gitroot> <git args...> -> git with every identity/signing knob pinned by -c overrides.
run_git() {
    local gitroot="$1"
    shift
    git -C "$gitroot" \
        -c user.name=t -c user.email=t@example.invalid \
        -c commit.gpgsign=false -c tag.gpgsign=false \
        -c init.defaultBranch=main -c core.autocrlf=false \
        -c advice.detachedHead=false -c merge.conflictStyle=merge \
        "$@"
}

# create_world <name> -> builds $WORKDIR/<name>/{origin.git,w,gh} and sets WORLD_ROOT, WORK_TREE,
# ORIGIN_DIR, GH_DIR, TRUNK_SHA. origin carries main (TRUNK_SHA); `w` has remote origin and HEAD
# on feat/x one commit ahead of main, with base.txt tracked. GH_STUB_DIR points at GH_DIR.
create_world() {
    WORLD_ROOT="$WORKDIR/$1"
    WORK_TREE="$WORLD_ROOT/w"
    ORIGIN_DIR="$WORLD_ROOT/origin.git"
    GH_DIR="$WORLD_ROOT/gh"
    mkdir -p "$WORK_TREE" "$GH_DIR"
    run_git "$WORLD_ROOT" init -q --bare origin.git
    run_git "$ORIGIN_DIR" symbolic-ref HEAD refs/heads/main
    run_git "$WORK_TREE" init -q
    run_git "$WORK_TREE" symbolic-ref HEAD refs/heads/main
    printf 'base\n' >"$WORK_TREE/base.txt"
    run_git "$WORK_TREE" add base.txt
    run_git "$WORK_TREE" commit -q -m init
    run_git "$WORK_TREE" remote add origin "$ORIGIN_DIR"
    run_git "$WORK_TREE" push -q origin refs/heads/main:refs/heads/main
    run_git "$WORK_TREE" checkout -q -b "$BRANCH"
    run_git "$WORK_TREE" commit --allow-empty -q -m one
    TRUNK_SHA="$(run_git "$WORK_TREE" rev-parse refs/heads/main)"
    export GH_STUB_DIR="$GH_DIR"
}

# commit_file <path> <content> <message> -> writes, stages and commits one file in `w`.
commit_file() {
    printf '%s' "$2" >"$WORK_TREE/$1"
    run_git "$WORK_TREE" add -- "$1"
    run_git "$WORK_TREE" commit -q -m "$3"
}

# advance_origin_trunk -> a second clone pushes one more main commit to origin. Sets NEW_TRUNK_SHA.
advance_origin_trunk() {
    local second_tree="$WORLD_ROOT/w2"
    rm -rf "$second_tree"
    run_git "$WORLD_ROOT" clone -q "$ORIGIN_DIR" w2
    run_git "$second_tree" checkout -q main
    run_git "$second_tree" commit --allow-empty -q -m elsewhere
    run_git "$second_tree" push -q origin refs/heads/main:refs/heads/main
    NEW_TRUNK_SHA="$(run_git "$second_tree" rev-parse HEAD)"
}

# advance_local_trunk -> adds one commit to the local main without checking it out.
advance_local_trunk() {
    local trunk_tree new_commit
    trunk_tree="$(run_git "$WORK_TREE" rev-parse 'refs/heads/main^{tree}')"
    new_commit="$(run_git "$WORK_TREE" commit-tree -p refs/heads/main -m local "$trunk_tree")"
    run_git "$WORK_TREE" update-ref refs/heads/main "$new_commit"
}

# head_sha -> prints the full sha of HEAD in `w`.
head_sha() {
    run_git "$WORK_TREE" rev-parse HEAD
}

# ── Engine helpers ───────────────────────────────────────────────────────────

# run_engine <name> <cwd> <PATH> <engine args...> -> runs the engine; sets LAST_OUT (stdout, exact),
# LAST_RC, LAST_ERR (stderr file), and LAST_FACTS (absolute facts file) on exit 0. Every facts file
# is recorded for the final schema check and checked here for the text invariants.
LAST_OUT=''
LAST_RC=0
LAST_ERR=''
LAST_FACTS=''
run_engine() {
    local name="$1" run_cwd="$2" run_path="$3"
    shift 3
    LAST_ERR="$WORKDIR/$name.err"
    LAST_RC=0
    LAST_FACTS=''
    local captured
    captured="$(cd "$run_cwd" || exit 97
        engine_rc=0
        PATH="$run_path" "$BASH_BIN" "$ENGINE" "$@" 2>"$LAST_ERR" || engine_rc=$?
        printf 'x'
        exit "$engine_rc")" || LAST_RC=$?
    LAST_OUT="${captured%x}"
    if [[ "$LAST_RC" -eq 0 ]]; then
        local facts_relative
        facts_relative="$(route_value facts_file)"
        LAST_FACTS="$run_cwd/$facts_relative"
        printf '%s\n' "$LAST_FACTS" >>"$FACTS_LIST"
        check_text_invariants "$name"
        check_text_ids "$name"
    fi
}

# route_value <key> -> prints the value of the `<key>: ` routing line in LAST_OUT, or nothing.
route_value() {
    local route_line
    while IFS= read -r route_line; do
        if [[ "$route_line" == "$1: "* ]]; then
            printf '%s' "${route_line#"$1: "}"
            return 0
        fi
    done <<<"$LAST_OUT"
}

# route_keys -> prints the routing keys of LAST_OUT, comma-joined, in order.
route_keys() {
    local route_line keys=''
    while IFS= read -r route_line; do
        [[ -n "$route_line" ]] || continue
        keys="$keys${keys:+,}${route_line%%: *}"
    done <<<"$LAST_OUT"
    printf '%s' "$keys"
}

# facts_value <jq filter> -> runs the filter over LAST_FACTS, raw output.
facts_value() {
    jq -r "$1" "$LAST_FACTS"
}

# check_text_invariants <name> -> every text object's chunks join to its length and no chunk
# passes 1000 characters.
check_text_invariants() {
    local verdict
    verdict="$(jq -r '[.. | objects | select(has("chunks") and has("length"))] as $texts
        | if all($texts[]; (.chunks | join("") | length) == .length)
             and all($texts[]; all(.chunks[]; length <= 1000)) then "ok" else "bad" end' "$LAST_FACTS")"
    if [[ "$verdict" == ok ]]; then
        pass "$1-text" "every text's chunks join to its length, each chunk at most 1000"
    else
        failed "$1-text" "a text object breaks the chunk invariants"
    fi
}

# check_text_ids <name> -> the objects with a text_id are exactly the external texts (origin
# external and chunks), their ids are t1..tN in document order, each right after origin, and
# summary.external_texts and the external_texts routing line both equal N.
check_text_ids() {
    local text_count route_count
    text_count="$(jq -r '[.. | objects | select(has("text_id"))] as $tagged
        | [.. | objects | select(.origin == "external" and has("chunks"))] as $texts
        | if $tagged == $texts
             and [$texts[].text_id] == [range(1; ($texts | length) + 1) | "t\(.)"]
             and all($texts[]; keys_unsorted[0:2] == ["origin", "text_id"])
             and .summary.external_texts == ($texts | length)
          then $texts | length else "bad" end' "$LAST_FACTS")"
    route_count="$(route_value external_texts)"
    if [[ "$text_count" =~ ^[0-9]+$ && "$route_count" == "$text_count" ]]; then
        pass "$1-text-ids" "external texts carry ids t1..tN in order with N = $text_count, as summary and routing say"
    else
        failed "$1-text-ids" "text ids or their count are wrong: facts '$text_count', routing '$route_count'"
    fi
}

# assert_ok <name> -> asserts the last run exited 0 with an empty stderr.
assert_ok() {
    if [[ "$LAST_RC" -eq 0 ]]; then
        pass "$1" "exit 0"
    else
        failed "$1" "expected exit 0, got $LAST_RC (stderr: $(tail -n 2 "$LAST_ERR" | tr '\n' '|'))"
    fi
}

# assert_blocker <name> <cwd> <PATH> <reason> <engine args...>
# Runs the engine, asserts exit 1, EMPTY stdout, and exactly one stderr line `blocker: <reason>`.
assert_blocker() {
    local name="$1" run_cwd="$2" run_path="$3" reason="$4"
    shift 4
    run_engine "$name" "$run_cwd" "$run_path" "$@"
    local err_text
    err_text="$(cat "$LAST_ERR")"
    if [[ "$LAST_RC" -eq 1 && -z "$LAST_OUT" && "$err_text" == "blocker: $reason" ]]; then
        pass "$name" "blocker: $reason"
    else
        failed "$name" "expected exit 1, empty stdout, stderr 'blocker: $reason'; got rc $LAST_RC, stdout '$(printf '%s' "$LAST_OUT" | tr '\n' '|')', stderr '$(printf '%s' "$err_text" | tr '\n' '|')'"
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

# assert_route <name> <key> <expected>
assert_route() {
    assert_equal "$1" "$3" "$(route_value "$2")" "routing line $2"
}

# assert_fact <name> <jq filter> <expected>
assert_fact() {
    assert_equal "$1" "$3" "$(facts_value "$2")" "facts $2"
}

# assert_absent <name> <path>
assert_absent() {
    if [[ -e "$2" || -L "$2" ]]; then
        failed "$1" "expected no file at ${2#"$WORKDIR"/}"
    else
        pass "$1" "no file at ${2#"$WORKDIR"/}"
    fi
}

# assert_line_bound <name> -> every line of LAST_FACTS is at most 1100 bytes.
assert_line_bound() {
    local max_line_bytes
    max_line_bytes="$(LC_ALL=C awk '{ if (length($0) > longest) longest = length($0) } END { print longest + 0 }' "$LAST_FACTS")"
    if [[ "$max_line_bytes" -le 1100 ]]; then
        pass "$1" "longest line is $max_line_bytes bytes"
    else
        failed "$1" "longest line is $max_line_bytes bytes, past 1100"
    fi
}

# assert_line_chars <name> -> every line of LAST_FACTS is at most 1100 Unicode code points.
assert_line_chars() {
    local max_line_chars
    max_line_chars="$(jq -R -n '[inputs | length] | max // 0' "$LAST_FACTS" 2>/dev/null)" || max_line_chars='unreadable'
    if [[ "$max_line_chars" =~ ^[0-9]+$ && "$max_line_chars" -le 1100 ]]; then
        pass "$1" "longest line is $max_line_chars code points"
    else
        failed "$1" "longest line: $max_line_chars, not at most 1100 code points"
    fi
}

# assert_unpublished <name> -> the facts folder of `w` holds no facts-*.json and no temp file or
# work folder.
assert_unpublished() {
    local facts_folder="$WORK_TREE/.hivemind/facts"
    assert_equal "$1-unpublished" '' "$(find "$facts_folder" -name 'facts-*.json' -print)" "no facts-*.json published"
    assert_equal "$1-no-temp" '' "$(find "$facts_folder" -name '.*' ! -name .gitignore -print)" \
        "no temp file or work folder left"
}

# snapshot_tree <gitroot> -> prints local branches, HEAD, the index entries, status, tags and
# every remote-tracking ref except origin/main.
snapshot_tree() {
    run_git "$1" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags
    run_git "$1" symbolic-ref -q HEAD || true
    run_git "$1" rev-parse HEAD
    run_git "$1" ls-files -s
    run_git "$1" status --porcelain=v1 --untracked-files=all
    run_git "$1" for-each-ref --format='%(refname) %(objectname)' refs/remotes | grep -v ' refs/remotes/origin/main ' | grep -v '^refs/remotes/origin/main ' || true
}

# DIRTY_PATH_FILTER: jq definition selecting the dirty item whose joined path is $p.
DIRTY_ITEM='def item($p): .dirty.paths.items[] | select((.path.chunks | join("")) == $p);'
CHANGE_ITEM='def item($p): .history.paths.items[] | select((.path.chunks | join("")) == $p);'

# dirty_field <path> <field filter> -> prints <field filter> of the dirty item for <path>.
dirty_field() {
    jq -r --arg p "$1" "$DIRTY_ITEM item(\$p) | $2" "$LAST_FACTS"
}

# change_field <path> <field filter> -> prints <field filter> of the history path item for <path>.
change_field() {
    jq -r --arg p "$1" "$CHANGE_ITEM item(\$p) | $2" "$LAST_FACTS"
}

# write_page <file> <jq program> [jq args...] -> appends one GitHub page built by jq to <file>.
write_page() {
    local page_file="$1" page_program="$2"
    shift 2
    jq -c -n "$@" "$page_program" >>"$page_file"
}

# pr_page <hasNextPage> <totalCount> <node JSON...> -> prints one pullRequests page.
pr_page() {
    local has_next="$1" total_count="$2"
    shift 2
    local nodes_json
    nodes_json="$(printf '%s\n' "$@" | jq -c -s '.')"
    jq -c -n --argjson next "$has_next" --argjson total "$total_count" --argjson nodes "$nodes_json" \
        '{data: {repository: {pullRequests: {totalCount: $total,
          pageInfo: {hasNextPage: $next, endCursor: (if $next then "c" else null end)}, nodes: $nodes}}}}'
}

# pr_node <number> <STATE> <head oid> -> prints one pull request node.
pr_node() {
    jq -c -n --argjson number "$1" --arg state "$2" --arg oid "$3" \
        '{number: $number, state: $state, url: ("https://github.com/o/r/pull/" + ($number | tostring)),
          headRefOid: $oid, baseRefName: "main", isCrossRepository: false}'
}

# ref_page <kind> <number> <body file or empty> <hasNextPage> <totalCount> <comment JSON...>
ref_page() {
    local ref_kind="$1" ref_number="$2" body_file="$3" has_next="$4" total_count="$5"
    shift 5
    local comments_json body_source="$WORKDIR/no-body"
    comments_json="$(printf '%s\n' "$@" | jq -c -s '.')"
    : >"$body_source"
    if [[ -n "$body_file" ]]; then
        body_source="$body_file"
    fi
    jq -c -n --arg kind "$ref_kind" --argjson number "$ref_number" --rawfile body_text "$body_source" \
        --argjson next "$has_next" --argjson total "$total_count" --argjson comments "$comments_json" \
        '{data: {repository: {issueOrPullRequest: {__typename: $kind, number: $number, state: "OPEN",
          url: ("https://github.com/o/r/issues/" + ($number | tostring)), title: "  A title  ",
          body: (if $body_text == "" then null else $body_text end), author: null,
          comments: {totalCount: $total, pageInfo: {hasNextPage: $next, endCursor: (if $next then "c" else null end)},
                     nodes: $comments}}}}}'
}

# comment_node <body> -> prints one comment node.
comment_node() {
    jq -c -n --arg body "$1" '{url: "https://github.com/o/r/issues/1#c", body: $body, author: {login: "someone"}}'
}

# ── Usage and gate errors ────────────────────────────────────────────────────

test_usage_errors() {
    create_world usage
    local marker="$WORLD_ROOT/injected"
    local before after
    before="$(snapshot_tree "$WORK_TREE"; run_git "$WORK_TREE" for-each-ref refs/remotes)"
    assert_blocker usage-no-args "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON"
    assert_blocker usage-unknown-flag "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON" --trunk main --base main
    assert_blocker usage-duplicate-trunk "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON" --trunk main --trunk main
    assert_blocker usage-duplicate-remote "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON" \
        --trunk main --remote origin --remote origin
    assert_blocker usage-missing-value "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON" --trunk
    assert_blocker usage-missing-trunk "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON" --remote origin
    assert_blocker usage-positional "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON" main
    assert_blocker usage-ref-not-number "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON" --trunk main --ref 12a
    assert_blocker usage-ref-empty "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON" --trunk main --ref ''
    assert_blocker usage-ref-injection "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON" \
        --trunk main --ref "\$(touch $marker)"
    local -a many_refs=()
    local ref_index
    for ref_index in $(seq 1 21); do
        many_refs+=(--ref "$ref_index")
    done
    assert_blocker usage-21-refs "$WORK_TREE" "$STUB_PATH" "$USAGE_REASON" --trunk main "${many_refs[@]}"

    local -a value_names=(dollar-paren backtick dotdot leading-dash empty space)
    local -a bad_values=("\$(touch $marker)" "\`touch $marker\`" 'ma..in' '-x' '' 'ma in')
    local value_index
    for value_index in "${!bad_values[@]}"; do
        assert_blocker "gate-trunk-${value_names[$value_index]}" "$WORK_TREE" "$STUB_PATH" "$IDENTIFIER_REASON" \
            --trunk "${bad_values[$value_index]}"
        assert_blocker "gate-remote-${value_names[$value_index]}" "$WORK_TREE" "$STUB_PATH" "$IDENTIFIER_REASON" \
            --trunk main --remote "${bad_values[$value_index]}"
    done
    assert_absent usage-no-marker "$marker"
    assert_absent usage-no-facts-folder "$WORK_TREE/.hivemind"
    assert_absent usage-gh-not-called "$GH_DIR/calls.log"
    after="$(snapshot_tree "$WORK_TREE"; run_git "$WORK_TREE" for-each-ref refs/remotes)"
    assert_equal usage-no-side-effect "$before" "$after" "refs, HEAD, index and status unchanged"

    mkdir -p "$WORKDIR/not-a-repo"
    assert_blocker not-a-work-tree "$WORKDIR/not-a-repo" "$STUB_PATH" "$NOT_WORK_TREE_REASON" --trunk main
    assert_blocker inside-git-folder "$WORK_TREE/.git" "$STUB_PATH" "$NOT_WORK_TREE_REASON" --trunk main
    assert_absent not-a-work-tree-nothing-written "$WORKDIR/not-a-repo/.hivemind"

    local -a twenty_refs=()
    for ref_index in $(seq 1 20); do
        twenty_refs+=(--ref "$ref_index")
    done
    run_engine usage-20-refs "$WORK_TREE" "$STUB_PATH" --trunk main "${twenty_refs[@]}"
    assert_ok usage-20-refs
    assert_fact usage-20-refs-total '.references.total' '20'
    assert_fact usage-20-refs-unavailable '[.references.items[] | select(.lookup == "unavailable")] | length' '20'
    assert_route usage-20-refs-ready delivery ready
}

# ── The fetch writes only the remote-tracking trunk ─────────────────────────

test_fetch_isolation() {
    create_world fetch
    run_git "$WORK_TREE" push -q origin "refs/heads/$BRANCH:refs/heads/other"
    run_git "$WORK_TREE" fetch -q origin '+refs/heads/other:refs/remotes/origin/other'
    printf 'tracked\n' >"$WORK_TREE/base.txt"
    printf 'new\n' >"$WORK_TREE/untracked.txt"
    advance_origin_trunk
    run_git "$WORLD_ROOT/w2" push -q origin refs/heads/main:refs/heads/other --force
    run_git "$WORLD_ROOT/w2" tag v1
    run_git "$WORLD_ROOT/w2" push -q origin refs/tags/v1
    local before after
    before="$(snapshot_tree "$WORK_TREE")"
    run_engine fetch "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok fetch
    after="$(snapshot_tree "$WORK_TREE")"
    assert_equal fetch-tree-unchanged "$before" "$after" \
        "refs/heads, tags, HEAD, ls-files -s, status and other remote-tracking refs unchanged"
    assert_equal fetch-tracking-moved "$NEW_TRUNK_SHA" "$(run_git "$WORK_TREE" rev-parse refs/remotes/origin/main)" \
        "refs/remotes/origin/main moved to the new remote trunk"
    assert_route fetch-behind trunk_freshness behind
    assert_route fetch-behind-count trunk_behind 1
    assert_route fetch-dirty delivery_stops dirty_paths
}

# ── Trunk freshness ─────────────────────────────────────────────────────────

test_freshness() {
    create_world fresh
    run_engine fresh "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok fresh
    assert_equal fresh-keys 'facts_file,facts_lines,head_state,branch,head,trunk,trunk_freshness,trunk_ahead,trunk_behind,cut,external_texts,delivery,delivery_stops' \
        "$(route_keys)" "routing keys and order"
    assert_route fresh-state trunk_freshness fresh
    assert_route fresh-branch branch "$BRANCH"
    assert_route fresh-head head "$(head_sha)"
    assert_route fresh-trunk trunk main
    assert_route fresh-ready delivery ready
    assert_route fresh-no-stops delivery_stops none
    assert_route fresh-no-cut cut none
    assert_route fresh-no-texts external_texts 0
    assert_fact fresh-no-text-ids '[.. | objects | select(has("text_id"))] | length' 0
    assert_fact fresh-remote '.repository.remote' origin
    assert_fact fresh-base '.history.base' remote_trunk
    local facts_lines
    facts_lines="$(wc -l <"$LAST_FACTS" | tr -d ' ')"
    assert_route fresh-facts-lines facts_lines "$facts_lines"
    assert_equal fresh-facts-ignored '*' "$(cat "$WORK_TREE/.hivemind/facts/.gitignore")" "facts folder .gitignore holds *"

    advance_origin_trunk
    run_engine behind "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route behind-state trunk_freshness behind
    assert_route behind-counts trunk_ahead 0
    assert_route behind-count trunk_behind 1

    create_world ahead
    advance_local_trunk
    run_engine ahead "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route ahead-state trunk_freshness ahead
    assert_route ahead-count trunk_ahead 1
    assert_route ahead-behind trunk_behind 0

    advance_origin_trunk
    run_engine diverged "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route diverged-state trunk_freshness diverged
    assert_route diverged-ahead trunk_ahead 1
    assert_route diverged-behind trunk_behind 1

    create_world no-remote
    run_git "$WORK_TREE" remote remove origin
    run_engine no-remote "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route no-remote-state trunk_freshness no_remote
    assert_fact no-remote-base '.history.base' local_trunk
    assert_fact no-remote-history '.history.status' available
    assert_fact no-remote-no-remote-key '.repository | has("remote")' false
    assert_route no-remote-ready delivery ready

    run_git "$WORK_TREE" branch -q -D main
    run_engine no-trunk "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route no-trunk-state trunk_freshness no_trunk
    assert_fact no-trunk-history '.history.status' unavailable
    assert_fact no-trunk-commits '[.history.commits.complete, .history.commits.total] | @tsv' $'false\t0'
    assert_route no-trunk-stop delivery_stops history_unavailable

    create_world fetch-failed
    run_git "$WORK_TREE" remote set-url origin "$WORLD_ROOT/missing.git"
    run_engine fetch-failed "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route fetch-failed-state trunk_freshness fetch_failed
    assert_route fetch-failed-counts trunk_behind 0
    assert_fact fetch-failed-base '.history.base' remote_trunk
    assert_route fetch-failed-not-a-stop delivery ready

    create_world no-local-trunk
    run_git "$WORK_TREE" branch -q -D main
    run_engine no-local-trunk "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route no-local-trunk-state trunk_freshness no_local_trunk
    assert_fact no-local-trunk-key '.repository | has("local_trunk")' false
    assert_fact no-local-trunk-history '.history.commits.total' 1

    create_world explicit-remote
    run_git "$WORLD_ROOT" clone -q --bare "$ORIGIN_DIR" mirror.git
    run_git "$WORK_TREE" remote add mirror "$WORLD_ROOT/mirror.git"
    run_engine explicit-remote "$WORK_TREE" "$STUB_PATH" --trunk main --remote mirror
    assert_route explicit-remote-state trunk_freshness fresh
    assert_fact explicit-remote-name '.repository.remote' mirror
    assert_equal explicit-remote-tracking "$TRUNK_SHA" "$(run_git "$WORK_TREE" rev-parse refs/remotes/mirror/main)" \
        "refs/remotes/mirror/main fetched"
}

# ── Dirty paths ─────────────────────────────────────────────────────────────

test_dirty_kinds() {
    create_world dirty
    local file_name
    for file_name in a.txt b.txt c.txt d.txt e.txt f.txt; do
        printf '%s\n' "$file_name" >"$WORK_TREE/$file_name"
    done
    printf '*.log\n' >"$WORK_TREE/.gitignore"
    run_git "$WORK_TREE" add .
    run_git "$WORK_TREE" commit -q -m files
    printf 'changed\n' >>"$WORK_TREE/a.txt"
    printf 'staged\n' >>"$WORK_TREE/b.txt"
    run_git "$WORK_TREE" add b.txt
    run_git "$WORK_TREE" rm -q c.txt
    rm "$WORK_TREE/d.txt"
    run_git "$WORK_TREE" mv e.txt e2.txt
    rm "$WORK_TREE/f.txt"
    ln -s a.txt "$WORK_TREE/f.txt"
    printf 'added\n' >"$WORK_TREE/n.txt"
    run_git "$WORK_TREE" add n.txt
    printf 'untracked\n' >"$WORK_TREE/u.txt"
    printf 'ignored\n' >"$WORK_TREE/x.log"
    run_engine dirty "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok dirty
    assert_equal dirty-worktree-modified $'unmodified\tmodified\tfalse' \
        "$(dirty_field a.txt '[.index_status, .worktree_status, .unmerged] | @tsv')" "a.txt modified in the work tree"
    assert_equal dirty-index-modified $'modified\tunmodified' \
        "$(dirty_field b.txt '[.index_status, .worktree_status] | @tsv')" "b.txt modified in the index"
    assert_equal dirty-index-deleted $'deleted\tunmodified' \
        "$(dirty_field c.txt '[.index_status, .worktree_status] | @tsv')" "c.txt deleted in the index"
    assert_equal dirty-worktree-deleted $'unmodified\tdeleted' \
        "$(dirty_field d.txt '[.index_status, .worktree_status] | @tsv')" "d.txt deleted in the work tree"
    assert_equal dirty-renamed $'renamed\te.txt' \
        "$(dirty_field e2.txt '[.index_status, (.old_path.chunks | join(""))] | @tsv')" "e2.txt renamed from e.txt"
    assert_equal dirty-type-changed $'unmodified\ttype_changed' \
        "$(dirty_field f.txt '[.index_status, .worktree_status] | @tsv')" "f.txt type changed"
    assert_equal dirty-added $'added\tunmodified' \
        "$(dirty_field n.txt '[.index_status, .worktree_status] | @tsv')" "n.txt added"
    assert_equal dirty-untracked $'untracked\tuntracked' \
        "$(dirty_field u.txt '[.index_status, .worktree_status] | @tsv')" "u.txt untracked"
    assert_fact dirty-ignored-not-listed '[.dirty.paths.items[] | .path.chunks | join("") | select(endswith(".log"))] | length' 0
    assert_fact dirty-facts-folder-not-listed '[.dirty.paths.items[] | .path.chunks | join("") | select(startswith(".hivemind"))] | length' 0
    assert_fact dirty-total '.dirty.paths.total' 8
    assert_route dirty-stop delivery_stops dirty_paths
    assert_route dirty-delivery delivery stop
}

# ── Merge conflict and other operations in progress ─────────────────────────

# make_conflict_branches -> on feat/x and on a new branch `side`, conflicting edits of c.txt.
make_conflict_branches() {
    commit_file c.txt $'base\n' 'c base'
    run_git "$WORK_TREE" branch side
    commit_file c.txt $'feat\n' 'c feat'
    run_git "$WORK_TREE" checkout -q side
    commit_file c.txt $'side\n' 'c side'
    run_git "$WORK_TREE" checkout -q "$BRANCH"
}

test_operations() {
    create_world merge
    make_conflict_branches
    run_git "$WORK_TREE" merge -q side >/dev/null 2>&1 || true
    run_engine merge "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok merge
    assert_equal merge-unmerged $'unmerged\tunmerged\ttrue' \
        "$(dirty_field c.txt '[.index_status, .worktree_status, .unmerged] | @tsv')" "c.txt unmerged (UU)"
    assert_fact merge-operation '.dirty.operations.items | join(",")' merge
    assert_route merge-stops delivery_stops dirty_paths,operation_in_progress

    create_world cherry-pick
    make_conflict_branches
    run_git "$WORK_TREE" cherry-pick side >/dev/null 2>&1 || true
    run_engine cherry-pick "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_fact cherry-pick-operation '.dirty.operations.items | join(",")' cherry_pick

    create_world revert
    commit_file c.txt $'one\n' 'c one'
    commit_file c.txt $'two\n' 'c two'
    run_git "$WORK_TREE" revert --no-edit HEAD~1 >/dev/null 2>&1 || true
    run_engine revert "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_fact revert-operation '.dirty.operations.items | join(",")' revert

    create_world rebase
    make_conflict_branches
    run_git "$WORK_TREE" rebase side >/dev/null 2>&1 || true
    run_engine rebase "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_fact rebase-operation '.dirty.operations.items | join(",")' rebase

    create_world bisect
    run_git "$WORK_TREE" bisect start >/dev/null 2>&1
    run_engine bisect "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_fact bisect-operation '.dirty.operations.items | join(",")' bisect
    assert_route bisect-stops delivery_stops operation_in_progress
}

# ── Odd paths, subjects, injection ──────────────────────────────────────────

test_paths_and_subjects() {
    create_world odd
    local marker="$WORLD_ROOT/injected"
    local space_name='with space.txt' tab_name=$'with\ttab.txt' newline_name=$'with\nnewline.txt'
    printf 'x\n' >"$WORK_TREE/$space_name"
    printf 'x\n' >"$WORK_TREE/$tab_name"
    printf 'x\n' >"$WORK_TREE/$newline_name"
    run_git "$WORK_TREE" add -A
    run_git "$WORK_TREE" commit -q -m "\$(touch $marker) \`touch $marker\` \"quoted\" back\\slash"
    local long_subject
    long_subject="$(printf 'word%.0s ' $(seq 1 600))end"
    run_git "$WORK_TREE" commit -q --allow-empty -m "$long_subject"
    run_git "$WORK_TREE" commit -q --allow-empty --allow-empty-message -m ''
    run_git "$WORK_TREE" commit -q --allow-empty --cleanup=verbatim -m '   '
    printf 'x\n' >"$WORK_TREE/untracked $tab_name"
    printf 'x\n' >"$WORK_TREE/untracked $newline_name"
    run_engine odd "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok odd
    assert_absent odd-no-injection "$marker"
    assert_equal odd-space 'added' "$(change_field "$space_name" '.status')" "path with a space"
    assert_equal odd-tab 'added' "$(change_field "$tab_name" '.status')" "path with a tab"
    assert_equal odd-newline 'added' "$(change_field "$newline_name" '.status')" "path with a newline"
    assert_equal odd-untracked-tab 'untracked' "$(dirty_field "untracked $tab_name" '.worktree_status')" "untracked path with a tab"
    assert_equal odd-untracked-newline 'untracked' "$(dirty_field "untracked $newline_name" '.worktree_status')" \
        "untracked path with a newline"
    assert_fact odd-injection-subject '.history.commits.items[1].subject.chunks | join("")' \
        "\$(touch $marker) \`touch $marker\` \"quoted\" back\\slash"
    assert_fact odd-long-subject '.history.commits.items[2].subject.chunks | join("")' "$long_subject"
    assert_fact odd-long-length '.history.commits.items[2].subject.length' "${#long_subject}"
    assert_fact odd-long-chunked '.history.commits.items[2].subject.chunks | length > 1' true
    assert_fact odd-long-chunk-visible '[.history.commits.items[2].subject.chunks[] | test("\\S$")] | all' true
    assert_fact odd-empty-subject '.history.commits.items[3].subject | [.length, (.chunks | length)] | @tsv' $'0\t0'
    assert_fact odd-blank-subject '.history.commits.items[4].subject | [.length, (.chunks | length)] | @tsv' $'0\t0'
    assert_line_bound odd-line-bound
    assert_fact odd-oldest-first '.history.commits.items[0].subject.chunks | join("")' one
}

# ── History shapes: merge, rename, delete, type change, binary ──────────────

test_history_shapes() {
    create_world shapes
    commit_file keep.txt $'one\ntwo\nthree\n' 'keep'
    commit_file move.txt $'stays the same\nacross the rename\n' 'move'
    commit_file gone.txt $'bye\n' 'gone'
    commit_file link.txt $'target\n' 'link'
    run_git "$WORK_TREE" push -q origin "refs/heads/$BRANCH:refs/heads/main"
    run_git "$WORK_TREE" fetch -q origin '+refs/heads/main:refs/remotes/origin/main'
    run_git "$WORK_TREE" branch -q -f main "$BRANCH"
    run_git "$WORK_TREE" branch side
    printf 'one\nTWO\nthree\nfour\n' >"$WORK_TREE/keep.txt"
    run_git "$WORK_TREE" mv move.txt moved.txt
    run_git "$WORK_TREE" rm -q gone.txt
    rm "$WORK_TREE/link.txt"
    ln -s keep.txt "$WORK_TREE/link.txt"
    printf 'bin\000ary\n' >"$WORK_TREE/blob.bin"
    run_git "$WORK_TREE" add -A
    run_git "$WORK_TREE" commit -q -m changes
    run_git "$WORK_TREE" checkout -q side
    commit_file side.txt $'side\n' 'side work'
    run_git "$WORK_TREE" checkout -q "$BRANCH"
    run_git "$WORK_TREE" merge -q --no-ff -m 'merge side' side
    run_engine shapes "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok shapes
    assert_equal shapes-modified $'modified\tfalse\t2\t1' \
        "$(change_field keep.txt '[.status, .binary, .added, .removed] | @tsv')" "keep.txt modified with line counts"
    assert_equal shapes-renamed $'renamed\tmove.txt\t100' \
        "$(change_field moved.txt '[.status, (.old_path.chunks | join("")), .similarity] | @tsv')" "moved.txt renamed"
    assert_equal shapes-deleted 'deleted' "$(change_field gone.txt '.status')" "gone.txt deleted"
    assert_equal shapes-type-changed 'type_changed' "$(change_field link.txt '.status')" "link.txt type changed"
    assert_equal shapes-binary $'true\tfalse' \
        "$(change_field blob.bin '[.binary, has("added")] | @tsv')" "blob.bin binary with no line counts"
    assert_fact shapes-merge-commit '[.history.commits.items[] | select(.parent_count == 2)] | length' 1
    assert_fact shapes-merge-last '.history.commits.items[-1].subject.chunks | join("")' 'merge side'
    assert_equal shapes-commit-count "$(run_git "$WORK_TREE" rev-list --count refs/remotes/origin/main..HEAD)" \
        "$(facts_value '.history.commits.total')" "commit count equals git's"
}

# ── On trunk, detached HEAD, unsafe branch name, shallow clone ──────────────

test_head_states() {
    create_world on-trunk
    run_git "$WORK_TREE" checkout -q main
    run_engine on-trunk "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok on-trunk
    assert_route on-trunk-branch branch main
    assert_fact on-trunk-history '[.history.status, .history.commits.complete, .history.commits.total, .history.paths.total] | @tsv' \
        $'available\ttrue\t0\t0'
    assert_fact on-trunk-pr '.pull_requests.lookup' not_applicable
    assert_absent on-trunk-gh-not-called "$GH_DIR/calls.log"
    assert_route on-trunk-ready delivery ready

    create_world detached
    run_git "$WORK_TREE" checkout -q --detach HEAD
    run_engine detached "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route detached-state head_state detached
    assert_equal detached-no-branch-line '' "$(route_value branch)" "no branch line"
    assert_fact detached-no-branch-key '.repository | has("branch")' false
    assert_fact detached-pr '.pull_requests.lookup' not_applicable
    assert_route detached-not-a-stop delivery ready
    assert_fact detached-history '.history.commits.total' 1

    create_world unsafe-name
    local marker="$WORLD_ROOT/injected"
    run_git "$WORK_TREE" checkout -q -b 'feat/$(touch${IFS}injected)'
    run_engine unsafe-name "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok unsafe-name
    assert_route unsafe-name-state head_state unsafe_name
    assert_equal unsafe-name-keys 'facts_file,facts_lines,head_state,head,trunk,trunk_freshness,trunk_ahead,trunk_behind,cut,external_texts,delivery,delivery_stops' \
        "$(route_keys)" "no branch line"
    assert_fact unsafe-name-no-branch-key '.repository | has("branch")' false
    assert_route unsafe-name-stop delivery_stops branch_name_unsafe
    assert_fact unsafe-name-pr '.pull_requests.lookup' not_applicable
    assert_absent unsafe-name-gh-not-called "$GH_DIR/calls.log"
    assert_absent unsafe-name-no-injection "$marker"
    assert_absent unsafe-name-no-injection-in-tree "$WORK_TREE/injected"

    create_world shallow
    run_git "$WORK_TREE" commit --allow-empty -q -m two
    run_git "$WORK_TREE" push -q origin "refs/heads/$BRANCH:refs/heads/$BRANCH"
    run_git "$WORLD_ROOT" clone -q --depth 1 --branch "$BRANCH" "file://$ORIGIN_DIR" shallow
    run_engine shallow "$WORLD_ROOT/shallow" "$STUB_PATH" --trunk main
    assert_ok shallow
    assert_route shallow-fetched trunk_freshness no_local_trunk
    assert_fact shallow-history '[.history.status, .history.commits.complete] | @tsv' $'unavailable\tfalse'
    assert_route shallow-stop delivery_stops history_unavailable
}

# ── Past the bound: a history whose facts file passes 256 KB ────────────────

test_big_history() {
    create_world big
    local stream_file="$WORLD_ROOT/history.stream" commit_index subject content message_length
    local commit_total=1500
    {
        for commit_index in $(seq 1 "$commit_total"); do
            subject="change $commit_index: update the module that handles part $commit_index of the large history case"
            message_length="${#subject}"
            printf 'commit refs/heads/big\nmark :%d\ncommitter t <t@example.invalid> %d +0000\ndata %d\n%s\n' \
                "$commit_index" "$((1700000000 + commit_index))" "$((message_length + 1))" "$subject"
            if [[ "$commit_index" -eq 1 ]]; then
                printf 'from refs/heads/main^0\n'
            else
                printf 'from :%d\n' "$((commit_index - 1))"
            fi
            content="line $commit_index"
            printf 'M 100644 inline dir%d/file-%d.txt\ndata %d\n%s\n' \
                "$((commit_index % 40))" "$commit_index" "$((${#content} + 1))" "$content"
            if [[ "$commit_index" -le 1000 ]]; then
                printf 'M 100644 inline extra%d/more-%d.txt\ndata %d\n%s\n' \
                    "$((commit_index % 25))" "$commit_index" "$((${#content} + 1))" "$content"
            fi
            printf '\n'
        done
    } >"$stream_file"
    run_git "$WORK_TREE" fast-import --quiet <"$stream_file"
    run_git "$WORK_TREE" checkout -q big
    run_engine big "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok big
    local facts_bytes git_commits git_paths
    facts_bytes="$(wc -c <"$LAST_FACTS" | tr -d ' ')"
    if [[ "$facts_bytes" -gt 262144 ]]; then
        pass big-size "facts file is $facts_bytes bytes, past 256 KB"
    else
        failed big-size "facts file is $facts_bytes bytes, not past 256 KB"
    fi
    assert_line_bound big-line-bound
    assert_route big-facts-lines facts_lines "$(wc -l <"$LAST_FACTS" | tr -d ' ')"
    git_commits="$(run_git "$WORK_TREE" rev-list --count refs/remotes/origin/main..HEAD)"
    git_paths="$(run_git "$WORK_TREE" diff-tree -r --name-only -z refs/remotes/origin/main HEAD | tr -cd '\000' | wc -c | tr -d ' ')"
    assert_fact big-commits-complete '[.history.commits.complete, .history.commits.total, (.history.commits.items | length)] | @tsv' \
        "$(printf 'true\t%s\t%s' "$git_commits" "$git_commits")"
    assert_fact big-paths-complete '[.history.paths.complete, .history.paths.total, (.history.paths.items | length)] | @tsv' \
        "$(printf 'true\t%s\t%s' "$git_paths" "$git_paths")"
    assert_equal big-counts-expected "1500 2500" "$git_commits $git_paths" "world holds 1500 commits and 2500 paths"
    assert_fact big-oldest-first '.history.commits.items[0].subject.chunks[0] | startswith("change 1:")' true
    assert_route big-ready delivery ready
}

# ── Named issues and pull requests ──────────────────────────────────────────

test_references() {
    create_world refs
    local body_file="$WORLD_ROOT/body.txt"
    yes 'lorem "ipsum" back\slash dolor sit amet ' | tr -d '\n' | head -c 200000 >"$body_file" || true
    ref_page Issue 7 "$body_file" false 2 "$(comment_node 'first comment')" "$(comment_node '   ')" \
        >"$GH_DIR/ref-7.pages"
    ref_page PullRequest 8 '' true 3 "$(comment_node 'page one')" >"$GH_DIR/ref-8.pages"
    ref_page PullRequest 8 '' false 3 "$(comment_node 'page two a')" "$(comment_node 'page two b')" \
        >>"$GH_DIR/ref-8.pages"
    run_engine refs "$WORK_TREE" "$STUB_PATH" --trunk main --ref 7 --ref 8 --ref 9
    assert_ok refs
    local verdict
    verdict="$(jq -r --rawfile body "$body_file" '.references.items[0].item.body as $text
        | if ($text.chunks | join("")) == ($body | sub("\\s+$"; "")) and $text.length == ($body | sub("\\s+$"; "") | length)
          then "equal" else "different" end' "$LAST_FACTS")"
    assert_equal refs-body-rejoins equal "$verdict" "200 KB single-line body re-joins exactly"
    assert_line_bound refs-line-bound
    assert_fact refs-body-chunked '.references.items[0].item.body.chunks | length > 199' true
    assert_fact refs-origin '[.references.items[0].item.origin, .references.items[0].item.body.origin, .references.items[0].item.comments.items[0].origin] | @tsv' \
        $'external\texternal\texternal'
    assert_fact refs-kind '[.references.items[0].item.kind, .references.items[1].item.kind] | @tsv' $'issue\tpull_request'
    assert_fact refs-title '.references.items[0].item.title | [.length, (.chunks | join(""))] | @tsv' $'9\t  A title'
    assert_fact refs-no-author '.references.items[0].item | has("author")' false
    assert_fact refs-blank-comment '.references.items[0].item.comments.items[1].body | [.length, (.chunks | length)] | @tsv' $'0\t0'
    assert_fact refs-comment-pages '.references.items[1].item.comments | [.complete, .total, (.items | length)] | @tsv' $'true\t3\t3'
    assert_fact refs-null-body '.references.items[1].item.body | [.length, (.chunks | length)] | @tsv' $'0\t0'
    assert_fact refs-missing '.references.items[2] | [.number, .lookup, has("item")] | @tsv' $'9\tunavailable\tfalse'
    assert_route refs-no-cut cut none
    assert_route refs-text-count external_texts 9
    assert_fact refs-text-count-summary '.summary.external_texts' 9
    assert_fact refs-text-id-order '[.references.items[0].item | .title.text_id, .body.text_id, (.comments.items[].body.text_id)]
        + [.references.items[1].item | .title.text_id, .body.text_id, (.comments.items[].body.text_id)] | join(",")' \
        't1,t2,t3,t4,t5,t6,t7,t8,t9'
    assert_fact refs-blank-comment-id '.references.items[0].item.comments.items[1].body.text_id' t4
    assert_fact refs-short-values-no-id '[.references.items[].item | select(. != null) | ., .comments.items[] | has("text_id")] | any' false
    assert_route refs-ready delivery ready
    assert_equal refs-gh-fields 'ref -F owner={owner} -F repo={repo} -F number=7 -f' \
        "$(grep '^ref ' "$GH_DIR/calls.log" | head -n 1 | sed 's/ --paginate//; s/^ref api graphql/ref/')" "ref call uses gh placeholders"

    create_world refs-cut
    ref_page Issue 4 '' true 5 "$(comment_node 'only page')" >"$GH_DIR/ref-4.pages"
    printf '1\n' >"$GH_DIR/ref-4.rc"
    run_engine refs-cut "$WORK_TREE" "$STUB_PATH" --trunk main --ref 4
    assert_fact refs-cut-comments '.references.items[0].item.comments | [.complete, .total, (.items | length)] | @tsv' $'false\t5\t1'
    assert_route refs-cut-field cut references
    assert_route refs-cut-stop delivery_stops cut_fields
}

# ── The branch's pull requests ──────────────────────────────────────────────

test_pull_requests() {
    create_world prs
    local in_history ahead_oid unrelated_oid unknown_oid head_tree
    in_history="$(head_sha)"
    head_tree="$(run_git "$WORK_TREE" rev-parse 'HEAD^{tree}')"
    ahead_oid="$(run_git "$WORK_TREE" commit-tree -p HEAD -m ahead "$head_tree")"
    run_git "$WORK_TREE" update-ref refs/heads/ahead "$ahead_oid"
    unrelated_oid="$(run_git "$WORK_TREE" commit-tree -p refs/heads/main -m side "$head_tree")"
    run_git "$WORK_TREE" update-ref refs/heads/side "$unrelated_oid"
    unknown_oid="$(printf 'ab%.0s' $(seq 1 20))"

    pr_page true 4 "$(pr_node 1 OPEN "$in_history")" "$(pr_node 2 MERGED "$unrelated_oid")" >"$GH_DIR/pr.pages"
    pr_page false 4 "$(pr_node 3 MERGED "$unknown_oid")" "$(pr_node 4 OPEN "$ahead_oid")" >>"$GH_DIR/pr.pages"
    run_engine prs "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok prs
    assert_fact prs-complete '.pull_requests | [.lookup, .complete, .total, (.items | length)] | @tsv' $'fetched\ttrue\t4\t4'
    assert_fact prs-relations '[.pull_requests.items[] | "\(.number)=\(.state)/\(.relation)"] | join(",")' \
        '1=open/in_history,2=merged/unrelated,3=merged/unknown,4=open/ahead_of_head'
    assert_fact prs-origin '[.pull_requests.items[].origin] | unique | join(",")' external
    assert_fact prs-no-text-id '[.pull_requests.items[] | has("text_id")] | any' false
    assert_route prs-no-texts external_texts 0
    assert_route prs-ready delivery ready
    assert_equal prs-gh-fields "pr -F owner={owner} -F repo={repo} -f branch=$BRANCH -f" \
        "$(head -n 1 "$GH_DIR/calls.log" | sed 's/ --paginate//; s/^pr api graphql/pr/')" "pr call uses gh placeholders"

    pr_page false 1 "$(pr_node 5 MERGED "$in_history")" >"$GH_DIR/pr.pages"
    run_engine prs-merged "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route prs-merged-stop delivery_stops closed_pr_on_branch

    pr_page false 1 "$(pr_node 6 CLOSED "$ahead_oid")" >"$GH_DIR/pr.pages"
    run_engine prs-closed-ahead "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route prs-closed-ahead-stop delivery_stops closed_pr_on_branch

    pr_page false 2 "$(pr_node 7 CLOSED "$unrelated_oid")" "$(pr_node 8 MERGED "$unknown_oid")" >"$GH_DIR/pr.pages"
    run_engine prs-unrelated "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_route prs-unrelated-ready delivery ready

    pr_page true 5 "$(pr_node 9 OPEN "$in_history")" "$(pr_node 10 OPEN "$unrelated_oid")" >"$GH_DIR/pr.pages"
    printf '1\n' >"$GH_DIR/pr.rc"
    run_engine prs-page-failed "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_fact prs-page-failed-cut '.pull_requests | [.lookup, .complete, .total, (.items | length)] | @tsv' $'fetched\tfalse\t5\t2'
    assert_route prs-page-failed-field cut pull_requests
    assert_route prs-page-failed-stop delivery_stops cut_fields

    pr_page false 1 "$(pr_node 12 OPEN "$in_history")" >"$GH_DIR/pr.pages"
    run_engine prs-gh-exit-failed "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_fact prs-gh-exit-failed-cut '.pull_requests | [.complete, .total, (.items | length)] | @tsv' $'false\t1\t1'
    assert_route prs-gh-exit-failed-stop delivery_stops cut_fields

    pr_page true 5 "$(pr_node 11 OPEN "$in_history")" >"$GH_DIR/pr.pages"
    printf '{"errors":[{"message":"boom"}],"data":null}\n' >>"$GH_DIR/pr.pages"
    rm -f "$GH_DIR/pr.rc"
    run_engine prs-page-errors "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_fact prs-page-errors-cut '.pull_requests | [.complete, .total, (.items | length)] | @tsv' $'false\t5\t1'
    assert_route prs-page-errors-stop delivery_stops cut_fields

    printf '{"errors":[{"message":"boom"}],"data":null}\n' >"$GH_DIR/pr.pages"
    run_engine prs-first-page-error "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_fact prs-first-page-error '.pull_requests.lookup' unavailable
    assert_route prs-first-page-error-ready delivery ready

    rm -f "$GH_DIR/pr.pages"
    run_engine prs-gh-fails "$WORK_TREE" "$STUB_PATH" --trunk main --ref 3
    assert_fact prs-gh-fails '[.pull_requests.lookup, .references.items[0].lookup] | @tsv' $'unavailable\tunavailable'
    assert_route prs-gh-fails-ready delivery ready
    assert_route prs-gh-fails-no-cut cut none

    run_engine prs-gh-missing "$WORK_TREE" "$BASE_PATH" --trunk main --ref 3
    assert_ok prs-gh-missing
    assert_fact prs-gh-missing '[.pull_requests.lookup, .references.items[0].lookup] | @tsv' $'unavailable\tunavailable'
    assert_route prs-gh-missing-ready delivery ready
}

# ── GitHub values that are not free text fit one chunk ──────────────────────

# with_value <jq path> <value> -> reads one JSON document on stdin, sets <jq path> to the string
# <value>, prints it compact.
with_value() {
    jq -c --arg value "$2" "$1 = \$value"
}

# repeat_text <count> <character> -> prints <character> <count> times, no newline.
repeat_text() {
    local text_index
    for text_index in $(seq 1 "$1"); do
        printf '%s' "$2"
    done
}

# assert_pr_refused <name> <node JSON> -> a first pull request page holding <node JSON> gives
# lookup unavailable and delivery ready.
assert_pr_refused() {
    pr_page false 1 "$2" >"$GH_DIR/pr.pages"
    run_engine "$1" "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok "$1"
    assert_fact "$1-unavailable" '.pull_requests | [.lookup, .complete, (.items | length)] | @tsv' $'unavailable\tfalse\t0'
    assert_route "$1-ready" delivery ready
}

# assert_ref_refused <name> <page JSON> -> a first reference page <page JSON> for --ref 5 gives
# lookup unavailable and delivery ready.
assert_ref_refused() {
    printf '%s\n' "$2" >"$GH_DIR/ref-5.pages"
    run_engine "$1" "$WORK_TREE" "$STUB_PATH" --trunk main --ref 5
    assert_ok "$1"
    assert_fact "$1-unavailable" '.references.items[0] | [.lookup, has("item")] | @tsv' $'unavailable\tfalse'
    assert_route "$1-ready" delivery ready
}

test_short_values() {
    create_world short
    local oid long_value quote_value boundary_value ref_root='.data.repository.issueOrPullRequest'
    oid="$(head_sha)"
    long_value="$(repeat_text 1001 a)"
    quote_value="$(repeat_text 501 '"')"
    boundary_value="$(repeat_text 996 b)\"\""

    assert_pr_refused short-pr-url "$(pr_node 1 OPEN "$oid" | with_value .url "$long_value")"
    assert_pr_refused short-pr-base "$(pr_node 1 OPEN "$oid" | with_value .baseRefName "$long_value")"
    assert_pr_refused short-pr-quotes "$(pr_node 1 OPEN "$oid" | with_value .url "$quote_value")"
    assert_equal short-quotes-cost '501 1002' \
        "$(jq -n -r --arg value "$quote_value" '[($value | length), ($value | tojson | length - 2)] | join(" ")')" \
        "the 501-quote value has 501 characters and costs 1002"

    assert_ref_refused short-ref-url "$(ref_page Issue 5 '' false 0 | with_value "$ref_root.url" "$long_value")"
    assert_ref_refused short-ref-author \
        "$(ref_page Issue 5 '' false 0 | jq -c --arg value "$long_value" "$ref_root.author = {login: \$value}")"
    assert_ref_refused short-comment-url \
        "$(ref_page Issue 5 '' false 1 "$(comment_node 'a comment' | with_value .url "$long_value")")"
    assert_ref_refused short-comment-author \
        "$(ref_page Issue 5 '' false 1 "$(comment_node 'a comment' | with_value .author.login "$long_value")")"

    pr_page true 3 "$(pr_node 2 OPEN "$oid")" >"$GH_DIR/pr.pages"
    pr_page false 3 "$(pr_node 3 OPEN "$oid" | with_value .url "$long_value")" >>"$GH_DIR/pr.pages"
    run_engine short-later-page "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok short-later-page
    assert_fact short-later-page-cut '.pull_requests | [.lookup, .complete, .total, (.items | length)] | @tsv' $'fetched\tfalse\t3\t1'
    assert_route short-later-page-field cut pull_requests
    assert_route short-later-page-stop delivery_stops cut_fields

    assert_equal short-boundary-cost '998 1000' \
        "$(jq -n -r --arg value "$boundary_value" '[($value | length), ($value | tojson | length - 2)] | join(" ")')" \
        "the boundary value has 998 characters and costs 1000"
    pr_page false 1 "$(pr_node 4 OPEN "$oid" | with_value .url "$boundary_value" | with_value .baseRefName "$boundary_value")" \
        >"$GH_DIR/pr.pages"
    printf '%s\n' "$(ref_page Issue 5 '' false 1 \
        "$(comment_node 'a comment' | with_value .url "$boundary_value" | with_value .author.login "$boundary_value")" \
        | with_value "$ref_root.url" "$boundary_value" \
        | jq -c --arg value "$boundary_value" "$ref_root.author = {login: \$value}")" >"$GH_DIR/ref-5.pages"
    run_engine short-boundary "$WORK_TREE" "$STUB_PATH" --trunk main --ref 5
    assert_ok short-boundary
    assert_fact short-boundary-pr '.pull_requests | [.lookup, .complete] + (.items[0] | [.url, .base_ref]) | @json' \
        "$(jq -n -c --arg value "$boundary_value" '["fetched", true, $value, $value]')"
    assert_fact short-boundary-ref '.references.items[0] | [.lookup] + (.item | [.url, .author, .comments.items[0].url, .comments.items[0].author]) | @json' \
        "$(jq -n -c --arg value "$boundary_value" '["fetched", $value, $value, $value, $value]')"
    assert_route short-boundary-ready delivery ready
    assert_line_bound short-boundary-line-bound
}

# ── The line bound: a seeded corpus through every text source ───────────────

CORPUS_SEED=20261020

# CORPUS_GENERATOR: node program. Args: seed, gather-facts.jq, out folder, work tree, branch, blob
# sha. Reads the facts_space_points code points from gather-facts.jq, makes 40 texts, and writes
# corpus.json (texts, title_index, body_index, history_paths, untracked_path), subjects.stream (a
# fast-import stream of one commit per text on the branch, CR and LF removed) and paths.z
# (update-index -z --index-info records naming the blob), and creates the whitespace-only
# untracked file in the work tree.
CORPUS_GENERATOR='
const fs = require("node:fs");
const path = require("node:path");
const [seedText, programPath, outDir, workTree, branchName, blobSha] = process.argv.slice(1);
function failGenerator(message) {
  throw new Error(message + " (seed " + seedText + ")");
}
const spaceMatch = /def facts_space_points: \[([0-9, ]+)\];/.exec(fs.readFileSync(programPath, "utf8"));
if (spaceMatch === null) failGenerator("facts_space_points not found in " + programPath);
const spacePoints = spaceMatch[1].split(",").map((term) => Number(term.trim()));
if (spacePoints.length !== 25) failGenerator("read " + spacePoints.length + " whitespace code points, expected 25");
let randomState = Number(seedText) >>> 0;
function nextRandom() {
  randomState = (randomState + 0x6d2b79f5) >>> 0;
  let mixedState = randomState;
  mixedState = Math.imul(mixedState ^ (mixedState >>> 15), mixedState | 1);
  mixedState ^= mixedState + Math.imul(mixedState ^ (mixedState >>> 7), mixedState | 61);
  return ((mixedState ^ (mixedState >>> 14)) >>> 0) / 4294967296;
}
function pickIndex(count) {
  return Math.floor(nextRandom() * count);
}
function pickBetween(low, high) {
  return low + pickIndex(high - low + 1);
}
function visibleCharacter() {
  const characterKind = pickIndex(7);
  if (characterKind === 0) return String.fromCodePoint(pickBetween(0x21, 0x7e));
  if (characterKind === 1) return String.fromCodePoint(0x22);
  if (characterKind === 2) return String.fromCodePoint(0x5c);
  if (characterKind === 3) return String.fromCodePoint(0x01);
  if (characterKind === 4) return String.fromCodePoint(0x7f);
  if (characterKind === 5) return String.fromCodePoint(pickBetween(0x4e00, 0x9fff));
  return String.fromCodePoint(pickBetween(0x1f600, 0x1f64f));
}
function visibleSegment() {
  const segmentLength = pickBetween(1, 200);
  let segmentText = "";
  for (let index = 0; index < segmentLength; index += 1) segmentText += visibleCharacter();
  return segmentText;
}
function whitespaceRun(runLength, fixedPoint) {
  let runText = "";
  for (let index = 0; index < runLength; index += 1) {
    const runPoint = fixedPoint === undefined ? spacePoints[pickIndex(spacePoints.length)] : fixedPoint;
    runText += String.fromCodePoint(runPoint);
  }
  return runText;
}
function randomRun() {
  const runBounds = [[0, 3], [4, 50], [51, 300], [301, 1100], [1101, 2500], [2501, 6000]][pickIndex(6)];
  const runLength = pickBetween(runBounds[0], runBounds[1]);
  return whitespaceRun(runLength, pickIndex(2) === 0 ? spacePoints[pickIndex(spacePoints.length)] : undefined);
}
function randomText() {
  let generatedText = pickIndex(3) === 0 ? randomRun() : "";
  const segmentCount = pickBetween(1, 3);
  for (let segment = 0; segment < segmentCount; segment += 1) {
    generatedText += visibleSegment();
    if (segment < segmentCount - 1) generatedText += randomRun();
  }
  if (pickIndex(3) === 0) generatedText += randomRun();
  return generatedText;
}
const allSpaces = spacePoints.map((point) => String.fromCodePoint(point)).join("");
const texts = [
  allSpaces + whitespaceRun(2000),
  visibleSegment() + whitespaceRun(3200, 0x20) + visibleSegment(),
  visibleSegment() + whitespaceRun(1100, 0x0b) + visibleSegment(),
  whitespaceRun(1500) + visibleSegment() + randomRun() + visibleSegment(),
  visibleSegment() + whitespaceRun(6000),
  spacePoints.map((point) => visibleSegment() + whitespaceRun(pickBetween(1, 400), point)).join("") + visibleSegment(),
  "",
];
while (texts.length < 40) texts.push(randomText());
const lineBreaks = new RegExp("[" + String.fromCodePoint(0x0d, 0x0a) + "]", "g");
function subjectCommitParts(text, index) {
  const messageBytes = Buffer.from(text.replace(lineBreaks, ""), "utf8");
  const parentLine = index === 0 ? "from refs/heads/" + branchName + "^0" : "from :" + index;
  return [Buffer.from("commit refs/heads/" + branchName + "\nmark :" + (index + 1)
    + "\ncommitter t <t@example.invalid> " + (1800000000 + index) + " +0000\ndata " + messageBytes.length + "\n"),
    messageBytes, Buffer.from("\n" + parentLine + "\n\n")];
}
fs.writeFileSync(path.join(outDir, "subjects.stream"), Buffer.concat(texts.flatMap(subjectCommitParts)));
const historyPaths = [...new Set(texts
  .map((text) => text.split("/").join("_"))
  .filter((name) => name !== "")
  .map((name) => (name === "." || name === ".." ? "_" + name : name)))];
fs.writeFileSync(path.join(outDir, "paths.z"),
  historyPaths.map((name) => "100644 " + blobSha + "\t" + name + "\0").join(""));
const untrackedPath = allSpaces + String.fromCodePoint(0x3000).repeat(60);
if (Buffer.byteLength(untrackedPath) > 255) failGenerator("the untracked name passes 255 bytes");
fs.writeFileSync(path.join(workTree, untrackedPath), "untracked\n");
fs.writeFileSync(path.join(outDir, "corpus.json"), JSON.stringify({
  texts, title_index: 3, body_index: 1, history_paths: historyPaths, untracked_path: untrackedPath,
}));
'

# CORPUS_ORACLE: node program, no jq. Args: seed, facts file, corpus.json, the NUL-separated
# subjects git prints with %s, and the regression body. Prints one `PASS|FAIL<TAB>case<TAB>text`
# line per check. A text re-joins its expected source (right-trimmed GitHub text, git's subject
# right-trimmed, the exact path), its length is that source's code points, and each chunk is
# non-empty and costs at most 1000 as jq writes it (JSON.stringify, with U+007F written as an
# escape of 6). Every line holds at most 1100 code points.
CORPUS_ORACLE='
const fs = require("node:fs");
const [seedText, factsPath, corpusPath, subjectsPath, regressionPath] = process.argv.slice(1);
const factsText = fs.readFileSync(factsPath, "utf8");
const facts = JSON.parse(factsText);
const corpus = JSON.parse(fs.readFileSync(corpusPath, "utf8"));
const deleteCharacter = String.fromCodePoint(0x7f);
function writtenCost(chunk) {
  return [...JSON.stringify(chunk)].length - 2 + 5 * (chunk.split(deleteCharacter).length - 1);
}
function textProblems(label, textObject, expectedText) {
  if (!textObject || !Array.isArray(textObject.chunks)) return [label + ": no text object"];
  const problems = [];
  if (textObject.chunks.join("") !== expectedText) problems.push(label + ": chunks do not re-join the source");
  if (textObject.length !== [...expectedText].length) {
    problems.push(label + ": length " + textObject.length + ", expected " + [...expectedText].length);
  }
  textObject.chunks.forEach((chunk, index) => {
    if (chunk === "") problems.push(label + ": chunk " + index + " is empty");
    if (writtenCost(chunk) > 1000) problems.push(label + ": chunk " + index + " costs " + writtenCost(chunk));
  });
  return problems;
}
function pathProblems(label, items, expectedNames) {
  const expectedSet = new Set(expectedNames);
  const seenNames = new Set();
  const problems = [];
  for (const [index, item] of items.entries()) {
    const joinedName = item.path.chunks.join("");
    if (!expectedSet.has(joinedName)) {
      problems.push(label + " item " + index + ": the path is not an expected name");
    } else {
      seenNames.add(joinedName);
      problems.push(...textProblems(label + " item " + index, item.path, joinedName));
    }
  }
  if (items.length !== expectedNames.length || seenNames.size !== expectedNames.length) {
    problems.push(label + ": " + items.length + " items, " + seenNames.size + " distinct, expected " + expectedNames.length);
  }
  return problems;
}
function report(caseName, problems, summary) {
  if (problems.length === 0) {
    console.log("PASS\t" + caseName + "\t" + summary);
  } else {
    console.log("FAIL\t" + caseName + "\t" + problems.slice(0, 3).join("; ")
      + " (" + problems.length + " problems, seed " + seedText + ")");
  }
}
const corpusRef = facts.references.items[0];
const corpusItem = corpusRef.lookup === "fetched" ? corpusRef.item : {};
const githubProblems = textProblems("title", corpusItem.title, corpus.texts[corpus.title_index].trimEnd())
  .concat(textProblems("body", corpusItem.body, corpus.texts[corpus.body_index].trimEnd()));
const commentItems = corpusItem.comments ? corpusItem.comments.items : [];
if (commentItems.length !== corpus.texts.length) githubProblems.push(commentItems.length + " comments, expected " + corpus.texts.length);
corpus.texts.forEach((text, index) => {
  githubProblems.push(...textProblems("comment " + index, commentItems[index] && commentItems[index].body, text.trimEnd()));
});
report("property-github", githubProblems, corpus.texts.length + " texts as title, body and comments re-join their right-trimmed source");
const regressionText = fs.readFileSync(regressionPath, "utf8");
const regressionRef = facts.references.items[1];
const regressionBody = regressionRef.lookup === "fetched" ? regressionRef.item.body : undefined;
const regressionProblems = textProblems("regression body", regressionBody, regressionText);
if (regressionBody && regressionBody.chunks.length < 6) {
  regressionProblems.push("regression body has " + regressionBody.chunks.length + " chunks, expected at least 6");
}
report("property-regression-b86d0065", regressionProblems, "x, 5000 spaces, y splits into at least 6 chunks that re-join");
const gitSubjects = fs.readFileSync(subjectsPath, "utf8").split("\0");
if (gitSubjects[gitSubjects.length - 1] === "") gitSubjects.pop();
const commitItems = facts.history.commits.items;
const subjectProblems = [];
if (gitSubjects.length !== corpus.texts.length + 2) subjectProblems.push(gitSubjects.length + " git subjects, expected " + (corpus.texts.length + 2));
if (commitItems.length !== gitSubjects.length) subjectProblems.push(commitItems.length + " commits, git has " + gitSubjects.length);
if (!gitSubjects.some((subject) => subject.includes(" ".repeat(3000)))) subjectProblems.push("no git subject holds the 3000-space run");
gitSubjects.forEach((subject, index) => {
  subjectProblems.push(...textProblems("subject " + index, commitItems[index] && commitItems[index].subject, subject.trimEnd()));
});
report("property-subjects", subjectProblems, gitSubjects.length + " subjects re-join git %s right-trimmed");
report("property-history-paths", pathProblems("history", facts.history.paths.items, corpus.history_paths),
  corpus.history_paths.length + " history paths re-join their exact names");
report("property-dirty-paths", pathProblems("dirty", facts.dirty.paths.items, corpus.history_paths.concat([corpus.untracked_path])),
  (corpus.history_paths.length + 1) + " dirty paths re-join their exact names");
const longLines = factsText.split("\n").map((line) => [...line].length).filter((lineLength) => lineLength > 1100);
report("property-lines", longLines.length === 0 ? [] : [longLines.length + " lines past 1100 code points, longest " + Math.max(...longLines)],
  "every facts line at most 1100 code points");
'

# report_oracle <oracle output> -> one PASS or FAIL per `PASS|FAIL<TAB>case<TAB>text` line.
report_oracle() {
    local verdict_word case_name verdict_text
    while IFS=$'\t' read -r verdict_word case_name verdict_text; do
        if [[ "$verdict_word" == PASS ]]; then
            pass "$case_name" "$verdict_text"
        else
            failed "$case_name" "$verdict_text"
        fi
    done <<<"$1"
}

test_line_bound_property() {
    create_world corpus
    local corpus_dir="$WORLD_ROOT/corpus" paths_index="$WORLD_ROOT/corpus/paths.index"
    local blob_sha paths_tree paths_commit oracle_output
    local regression_file="$WORLD_ROOT/regression-body.txt"
    mkdir -p "$corpus_dir"
    blob_sha="$(run_git "$WORK_TREE" hash-object -w --stdin </dev/null)"
    node -e "$CORPUS_GENERATOR" "$CORPUS_SEED" "$ASSEMBLY" "$corpus_dir" "$WORK_TREE" "$BRANCH" "$blob_sha"
    run_git "$WORK_TREE" fast-import --quiet <"$corpus_dir/subjects.stream"
    GIT_INDEX_FILE="$paths_index" run_git "$WORK_TREE" read-tree HEAD
    GIT_INDEX_FILE="$paths_index" run_git "$WORK_TREE" update-index -z --index-info <"$corpus_dir/paths.z"
    paths_tree="$(GIT_INDEX_FILE="$paths_index" run_git "$WORK_TREE" write-tree)"
    paths_commit="$(run_git "$WORK_TREE" commit-tree -p HEAD -m paths "$paths_tree")"
    run_git "$WORK_TREE" update-ref "refs/heads/$BRANCH" "$paths_commit"
    ref_page Issue 6 '' false 0 | jq -c --slurpfile corpus "$corpus_dir/corpus.json" '$corpus[0] as $source
        | .data.repository.issueOrPullRequest |= (.title = $source.texts[$source.title_index]
            | .body = $source.texts[$source.body_index]
            | .comments.totalCount = ($source.texts | length)
            | .comments.nodes = [$source.texts[]
                | {url: "https://github.com/o/r/issues/6#c", body: ., author: {login: "someone"}}])' \
        >"$GH_DIR/ref-6.pages"
    printf 'x%sy' "$(repeat_text 5000 ' ')" >"$regression_file"
    ref_page Issue 7 "$regression_file" false 0 >"$GH_DIR/ref-7.pages"
    run_engine property "$WORK_TREE" "$STUB_PATH" --trunk main --ref 6 --ref 7
    assert_ok property
    assert_line_chars property-line-chars
    run_git "$WORK_TREE" log -z --reverse --topo-order --no-show-signature --no-color --format=%s \
        refs/remotes/origin/main..HEAD >"$corpus_dir/subjects.z"
    oracle_output="$(node -e "$CORPUS_ORACLE" "$CORPUS_SEED" "$LAST_FACTS" "$corpus_dir/corpus.json" \
        "$corpus_dir/subjects.z" "$regression_file")" \
        || oracle_output="$oracle_output"$'\n'"FAIL"$'\t'"property-oracle"$'\t'"the oracle stopped (seed $CORPUS_SEED)"
    report_oracle "$oracle_output"
}

# ── The line bound: every field near its bound in one run ───────────────────

# component_name <character> <components> <component length> -> prints <components> runs of
# <character>, each <component length> long, joined by `/`.
component_name() {
    local component_text joined_name='' component_index
    component_text="$(repeat_text "$3" "$1")"
    for component_index in $(seq 1 "$2"); do
        joined_name="$joined_name${joined_name:+/}$component_text"
    done
    printf '%s' "$joined_name"
}

test_line_bound_every_field() {
    create_world every-field
    local long_branch long_remote long_trunk dense_value dense_text dense_component path_stem
    local ref_root='.data.repository.issueOrPullRequest'
    long_branch="$(component_name b 4 249)"
    long_remote="$(component_name r 4 249)"
    dense_value="$(repeat_text 100 $'"\\\001')"
    dense_text="$(repeat_text 200 $'"\\\001')"
    dense_component="$(repeat_text 124 '"\')"
    path_stem="$dense_component/$dense_component/$dense_component"
    mkdir -p "$WORK_TREE/$dense_component/$dense_component"
    printf 'moved\n' >"$WORK_TREE/${path_stem}x"
    run_git "$WORK_TREE" add -A
    run_git "$WORK_TREE" commit -q -m 'dense path'
    run_git "$WORK_TREE" branch -q -f main HEAD
    run_git "$WORK_TREE" checkout -q -b "$long_branch"
    mv "$WORK_TREE/${path_stem}x" "$WORK_TREE/${path_stem}y"
    run_git "$WORK_TREE" add -A
    run_git "$WORK_TREE" commit -q --cleanup=verbatim -m "$dense_text"
    mv "$WORK_TREE/${path_stem}y" "$WORK_TREE/${path_stem}w"
    run_git "$WORK_TREE" add -A
    printf 'untracked\n' >"$WORK_TREE/${path_stem}z"
    pr_page false 1 "$(pr_node 1 OPEN "$(head_sha)" | with_value .url "$dense_value" | with_value .baseRefName "$dense_value")" \
        >"$GH_DIR/pr.pages"
    printf '%s\n' "$(ref_page Issue 5 '' false 1 \
        "$(comment_node "$dense_text" | with_value .url "$dense_value" | with_value .author.login "$dense_value")" \
        | with_value "$ref_root.url" "$dense_value" | with_value "$ref_root.title" "$dense_text" \
        | with_value "$ref_root.body" "$dense_text" \
        | jq -c --arg value "$dense_value" "$ref_root.author = {login: \$value}")" >"$GH_DIR/ref-5.pages"
    assert_equal every-field-dense-costs '1000 2000 1000' \
        "$(jq -n -r --arg value "$dense_value" --arg text "$dense_text" --arg path "${path_stem}x" \
            '[$value, $text, ($path | explode | .[0:501] | implode)] | map(tojson | length - 2) | join(" ")')" \
        "the dense value costs 1000, the dense text 2000, and the dense path's first 501 characters 1000"
    run_engine every-field "$WORK_TREE" "$STUB_PATH" --trunk main --remote "$long_remote" --ref 5
    assert_ok every-field
    assert_line_chars every-field-line-chars
    assert_equal every-field-names $'999\t999' \
        "$(facts_value '[.repository.branch, .repository.remote] | map(length) | @tsv')" "branch and remote of 999 characters"
    assert_equal every-field-short-values $'6\t1000' \
        "$(facts_value '[(.pull_requests.items[0] | .url, .base_ref),
            (.references.items[0].item | .url, .author, .comments.items[0].url, .comments.items[0].author)]
            | [length, (map(tojson | length - 2) | unique | join(","))] | @tsv')" \
        "pull request url and base_ref, reference url and author, comment url and author each cost 1000"
    assert_equal every-field-full-chunks $'9\t1000' \
        "$(facts_value '[(.history.commits.items[0].subject, .history.paths.items[0].path,
              .history.paths.items[0].old_path, (.dirty.paths.items[] | .path, (.old_path // empty)),
              (.references.items[0].item | .title, .body, .comments.items[0].body)) | .chunks[0]]
            | [length, (map(tojson | length - 2) | unique | join(","))] | @tsv')" \
        "the first chunk at each of the 9 text sites costs 1000"
    assert_equal every-field-sites $'renamed\trenamed,untracked' \
        "$(facts_value '[.history.paths.items[0].status, (.dirty.paths.items | map(.index_status) | sort | join(","))] | @tsv')" \
        "a history rename, a staged rename and an untracked path"

    create_world every-field-trunk
    long_trunk="$(component_name t 4 249)"
    run_engine every-field-trunk "$WORK_TREE" "$STUB_PATH" --trunk "$long_trunk"
    assert_ok every-field-trunk
    assert_line_chars every-field-trunk-line-chars
    assert_fact every-field-trunk-name '.repository.trunk | length' 999
}

# ── The line bound blocks a value past it ───────────────────────────────────

test_line_gate() {
    create_world line-gate-trunk
    assert_blocker line-gate-trunk "$WORK_TREE" "$STUB_PATH" "$LINE_REASON" --trunk "$(repeat_text 1100 a)"
    assert_unpublished line-gate-trunk
    create_world line-gate-remote
    assert_blocker line-gate-remote "$WORK_TREE" "$STUB_PATH" "$LINE_REASON" \
        --trunk main --remote "$(repeat_text 1100 r)"
    assert_unpublished line-gate-remote
    create_world line-gate-branch
    run_git "$WORK_TREE" checkout -q -b "$(component_name b 5 240)"
    assert_blocker line-gate-branch "$WORK_TREE" "$STUB_PATH" "$LINE_REASON" --trunk main
    assert_unpublished line-gate-branch
}

# ── Concurrent runs, symlinked facts folder ─────────────────────────────────

test_concurrency_and_containment() {
    create_world concurrent
    local first_out="$WORLD_ROOT/first.out" second_out="$WORLD_ROOT/second.out"
    local first_rc=0 second_rc=0 first_file second_file
    (cd "$WORK_TREE" && PATH="$STUB_PATH" "$BASH_BIN" "$ENGINE" --trunk main >"$first_out" 2>/dev/null) &
    local first_pid=$!
    (cd "$WORK_TREE" && PATH="$STUB_PATH" "$BASH_BIN" "$ENGINE" --trunk main >"$second_out" 2>/dev/null) &
    local second_pid=$!
    wait "$first_pid" || first_rc=$?
    wait "$second_pid" || second_rc=$?
    assert_equal concurrent-exit '0 0' "$first_rc $second_rc" "both runs exit 0"
    first_file="$(sed -n 's/^facts_file: //p' "$first_out")"
    second_file="$(sed -n 's/^facts_file: //p' "$second_out")"
    if [[ -n "$first_file" && -n "$second_file" && "$first_file" != "$second_file" \
          && -f "$WORK_TREE/$first_file" && -f "$WORK_TREE/$second_file" ]]; then
        pass concurrent-distinct "two distinct facts files"
    else
        failed concurrent-distinct "expected two distinct facts files, got '$first_file' and '$second_file'"
    fi
    printf '%s\n%s\n' "$WORK_TREE/$first_file" "$WORK_TREE/$second_file" >>"$FACTS_LIST"
    assert_equal concurrent-no-leftovers '' \
        "$(find "$WORK_TREE/.hivemind/facts" -name '.*' ! -name .gitignore -print)" "no temp file or work folder left"

    create_world symlinked-hivemind
    local outside="$WORLD_ROOT/outside"
    mkdir -p "$outside"
    ln -s "$outside" "$WORK_TREE/.hivemind"
    assert_blocker symlinked-hivemind "$WORK_TREE" "$STUB_PATH" "$CONTAIN_REASON" --trunk main
    assert_equal symlinked-hivemind-outside-empty '' "$(ls -A "$outside")" "nothing written outside"

    create_world symlinked-facts
    outside="$WORLD_ROOT/outside"
    mkdir -p "$outside" "$WORK_TREE/.hivemind"
    ln -s "$outside" "$WORK_TREE/.hivemind/facts"
    assert_blocker symlinked-facts "$WORK_TREE" "$STUB_PATH" "$CONTAIN_REASON" --trunk main
    assert_equal symlinked-facts-outside-empty '' "$(ls -A "$outside")" "nothing written outside"

    create_world symlinked-ignore
    outside="$WORLD_ROOT/outside"
    mkdir -p "$outside" "$WORK_TREE/.hivemind/facts"
    ln -s "$outside/ignore" "$WORK_TREE/.hivemind/facts/.gitignore"
    run_engine symlinked-ignore "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok symlinked-ignore
    assert_equal symlinked-ignore-outside-empty '' "$(ls -A "$outside")" "a symlinked .gitignore is never written through"
}

# ── Scale: the engine's work grows in line with its input ───────────────────

SCALE_RATIO_LIMIT=10
SCALE_SECONDS_LIMIT=15

# timed_engine <name> <cwd> <PATH> <engine args...> -> run_engine under bash's time keyword; sets
# LAST_SECONDS to the wall clock seconds. LC_ALL=C keeps the decimal point a dot, so the value
# parses as JSON.
LAST_SECONDS=''
timed_engine() {
    local TIMEFORMAT=%R
    local LC_ALL=C
    local timing_file="$WORKDIR/$1.seconds"
    { time run_engine "$@"; } 2>"$timing_file"
    LAST_SECONDS="$(tail -n 1 "$timing_file")"
}

# assert_scaled <name> <small seconds> <large seconds> -> the large run took less than
# SCALE_RATIO_LIMIT times the small one and less than SCALE_SECONDS_LIMIT seconds.
assert_scaled() {
    local verdict verdict_word scale_ratio
    verdict="$(jq -n -r --argjson small "$2" --argjson large "$3" \
        --argjson ratio_limit "$SCALE_RATIO_LIMIT" --argjson seconds_limit "$SCALE_SECONDS_LIMIT" \
        '([$small, 0.01] | max) as $floor
         | (if $large < $ratio_limit * $floor and $large < $seconds_limit then "ok" else "bad" end) as $word
         | [$word, ($large / $floor * 100 | floor / 100)] | @tsv')"
    IFS=$'\t' read -r verdict_word scale_ratio <<<"$verdict"
    local scale_text="small ${2}s, large ${3}s, ratio ${scale_ratio}x (limits ${SCALE_RATIO_LIMIT}x and ${SCALE_SECONDS_LIMIT}s)"
    if [[ "$verdict_word" == ok ]]; then
        pass "$1" "$scale_text"
    else
        failed "$1" "$scale_text"
    fi
}

# many_files <dir> <count> -> creates the empty files f1 to f<count> in <dir>.
many_files() {
    mkdir -p "$1"
    printf 'f%d\n' $(seq 1 "$2") | (cd "$1" && xargs touch)
}

# subject_world <name> <bytes> -> create_world, then one more commit on the branch, made by
# fast-import, whose subject is <bytes> U+0001 bytes. The commit keeps the tree, so nothing is
# dirty.
subject_world() {
    create_world "$1"
    local stream_file="$WORLD_ROOT/subject.stream"
    {
        printf 'commit refs/heads/%s\ncommitter t <t@example.invalid> 1700000000 +0000\ndata %d\n' \
            "$BRANCH" "$(($2 + 1))"
        head -c "$2" /dev/zero | tr '\000' '\001'
        printf '\nfrom refs/heads/%s^0\n\n' "$BRANCH"
    } >"$stream_file"
    run_git "$WORK_TREE" fast-import --quiet <"$stream_file"
}

test_scaling() {
    local small_seconds

    subject_world scale-subject-small 250000
    timed_engine scale-subject-small "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok scale-subject-small
    assert_fact scale-subject-small-chunks '.history.commits.items[-1].subject | [.length, (.chunks | length)] | @json' \
        '[250000,1507]'
    small_seconds="$LAST_SECONDS"
    subject_world scale-subject-large 1000000
    timed_engine scale-subject-large "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok scale-subject-large
    assert_fact scale-subject-large-chunks '.history.commits.items[-1].subject | [.length, (.chunks | length)] | @json' \
        '[1000000,6025]'
    assert_scaled scale-subject "$small_seconds" "$LAST_SECONDS"

    create_world scale-dirty-small
    many_files "$WORK_TREE/many" 10000
    timed_engine scale-dirty-small "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok scale-dirty-small
    assert_fact scale-dirty-small-total '.dirty.paths.total' 10000
    small_seconds="$LAST_SECONDS"
    create_world scale-dirty-large
    many_files "$WORK_TREE/many" 40000
    timed_engine scale-dirty-large "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok scale-dirty-large
    assert_fact scale-dirty-large-total '.dirty.paths.total' 40000
    assert_scaled scale-dirty "$small_seconds" "$LAST_SECONDS"

    create_world scale-history-small
    many_files "$WORK_TREE/many" 5000
    run_git "$WORK_TREE" add -A
    run_git "$WORK_TREE" commit -q -m many
    timed_engine scale-history-small "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok scale-history-small
    assert_fact scale-history-small-total '.history.paths.total' 5000
    small_seconds="$LAST_SECONDS"
    create_world scale-history-large
    many_files "$WORK_TREE/many" 20000
    run_git "$WORK_TREE" add -A
    run_git "$WORK_TREE" commit -q -m many
    timed_engine scale-history-large "$WORK_TREE" "$STUB_PATH" --trunk main
    assert_ok scale-history-large
    assert_fact scale-history-large-total '.history.paths.total' 20000
    assert_scaled scale-history "$small_seconds" "$LAST_SECONDS"
}

# ── Schema check of every facts file ────────────────────────────────────────

test_schema_validation() {
    local validator_output validator_rc=0
    validator_output="$(node --input-type=module -e '
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const [harnessPath, libPath, schemaPath, listPath] = process.argv.slice(1);
const { loadLibs } = await import(pathToFileURL(harnessPath).href);
const lib = loadLibs([libPath]);
const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
const files = readFileSync(listPath, "utf8").split("\n").filter((line) => line !== "");
let bad = 0;
for (const file of files) {
  const verdict = lib.validateSchema(schema, JSON.parse(readFileSync(file, "utf8")));
  if (!verdict.ok) {
    bad += 1;
    console.log("INVALID " + file + " " + JSON.stringify(verdict.errors.slice(0, 3)));
  }
}
console.log("checked " + files.length + " invalid " + bad);
process.exit(bad === 0 && files.length > 0 ? 0 : 1);
' "$HARNESS" "$SCHEMA_LIB" "$SCHEMA" "$FACTS_LIST")" || validator_rc=$?
    if [[ "$validator_rc" -eq 0 ]]; then
        pass schema-all-facts "$(tail -n 1 <<<"$validator_output")"
    else
        failed schema-all-facts "$(tr '\n' '|' <<<"$validator_output")"
    fi
}

# ── Run ──────────────────────────────────────────────────────────────────────

test_usage_errors
test_fetch_isolation
test_freshness
test_dirty_kinds
test_operations
test_paths_and_subjects
test_history_shapes
test_head_states
test_big_history
test_references
test_pull_requests
test_short_values
test_line_bound_property
test_line_bound_every_field
test_line_gate
test_concurrency_and_containment
test_scaling
test_schema_validation

echo
echo "gather-facts engine tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
