#!/usr/bin/env bash
#
# Behavioral unit runner for the design review engine and the record verify library:
#   plugin/skills/_shared/record-verify.sh
#   plugin/skills/design-review/scripts/design-review.sh
#
# OFFLINE git/jq/bash TEST — needs only bash, git and jq (NO gh / network / auth). Every library
# case sources the readiness check library, then the record verify library, in a fresh `bash -c`
# twice, once under `set -euo pipefail` and once under `set -u` alone, and asserts both runs give
# identical stdout, stderr and exit status. Every pull request mode verify case also runs through
# `design-review.sh verify` and must give the library's result unchanged. Git fixtures are scratch
# commits built with plumbing only, so every tree entry mode is exact (100644, 120000 symlink,
# 160000 gitlink, tree), and a `.git` path part is grafted in with mktree. A recording `git`
# wrapper shadowed on PATH logs each git argv, proving the "no git call" cases and the global git
# flags on every library call. A recording `gh` stub beside it logs every gh argv and exits 1;
# the suite fails when any case called it.
#
# Fixture data lives in tests/design-review/cases.json; tests/design-review/README.md describes
# its layout. Sections are functions (test_<area>). Mirrors tools/test_readiness_check.sh's
# pass/fail counter, exit 1 on any failure, exit 2 on set-up failure and scratch dir removed on
# EXIT. Read-only: the only writes are in the scratch dir.
#
# Usage:
#   ./tools/test_design_review.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
RC_LIB="$REPO_ROOT/plugin/skills/_shared/readiness-check.sh"
RV_LIB="$REPO_ROOT/plugin/skills/_shared/record-verify.sh"
DR_SCRIPT="$REPO_ROOT/plugin/skills/design-review/scripts/design-review.sh"
DR_SKILL="$REPO_ROOT/plugin/skills/design-review/SKILL.md"
DR_FORMAT="$REPO_ROOT/plugin/skills/design-review/references/record-format.md"
CASES="$REPO_ROOT/tests/design-review/cases.json"

for required_file in "$RC_LIB" "$RV_LIB" "$DR_SCRIPT" "$DR_SKILL" "$DR_FORMAT" "$CASES"; do
  [ -f "$required_file" ] || { echo "FAIL: file under test missing: $required_file" >&2; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this suite" >&2; exit 2; }
REAL_GIT="$(command -v git)" || { echo "FAIL: git is required to run this suite" >&2; exit 2; }
REAL_DIRNAME="$(command -v dirname)" || { echo "FAIL: dirname is required to run this suite" >&2; exit 2; }

make_scratch_dir TMPDIR_TEST
trap 'rm -rf "$TMPDIR_TEST"' EXIT

export HOME="$TMPDIR_TEST/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=design-review-test GIT_AUTHOR_EMAIL=design-review-test@example.invalid
export GIT_COMMITTER_NAME=design-review-test GIT_COMMITTER_EMAIL=design-review-test@example.invalid
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
unset HIVEMIND_DESIGN_REVIEW_MODEL
mkdir -p "$HOME" || { echo "FAIL: cannot create scratch HOME" >&2; exit 2; }

WRAP_DIR="$TMPDIR_TEST/wrap-bin"
GIT_LOG="$TMPDIR_TEST/git-calls.log"
GH_LOG="$TMPDIR_TEST/gh-calls.log"
mkdir -p "$WRAP_DIR" || { echo "FAIL: cannot create wrapper dir" >&2; exit 2; }
: >"$GH_LOG" || { echo "FAIL: cannot create the gh log" >&2; exit 2; }
printf '%s\n' '#!/bin/sh' \
  'printf "%s\n" "$*" >>"$DR_TEST_GIT_LOG"' \
  'exec "$DR_TEST_REAL_GIT" "$@"' >"$WRAP_DIR/git" \
  && chmod +x "$WRAP_DIR/git" \
  || { echo "FAIL: cannot write the recording git wrapper" >&2; exit 2; }
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' \
  'printf "<%s>" "$@" >>"$DR_TEST_GH_LOG"' \
  'printf "\n" >>"$DR_TEST_GH_LOG"' \
  'exit 1' >"$WRAP_DIR/gh" \
  && chmod +x "$WRAP_DIR/gh" \
  || { echo "FAIL: cannot write the recording gh stub" >&2; exit 2; }
LIB_PATH="$WRAP_DIR:$PATH"
NOJQ_DIR="$TMPDIR_TEST/nojq-bin"
mkdir -p "$NOJQ_DIR" && ln -s "$REAL_DIRNAME" "$NOJQ_DIR/dirname" && ln -s "$WRAP_DIR/git" "$NOJQ_DIR/git" \
  || { echo "FAIL: cannot build the jq-free PATH" >&2; exit 2; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
setup_fail() { echo "FAIL: set-up: $1" >&2; exit 2; }

CALL_N=0
CALL_RC=0
CALL_OUT=""
CALL_ERR=""
LIB_FILES=("$RC_LIB" "$RV_LIB")
SCRIPT_ENV=()

# run_lib_mode <prelude> <cwd> <out> <err> <fn> [arg...]: runs one library call in a fresh bash
# under <prelude>, after sourcing each LIB_FILES entry, with PATH set to LIB_PATH; prints its exit
# status.
run_lib_mode() {
  local prelude="$1" cwd="$2" out_file="$3" err_file="$4" status=0
  shift 4
  (
    cd "$cwd" || exit 97
    PATH="$LIB_PATH" DR_TEST_GIT_LOG="$GIT_LOG" DR_TEST_REAL_GIT="$REAL_GIT" DR_TEST_GH_LOG="$GH_LOG" \
      bash -c "$prelude"'; lib_count="$1"; shift
while [ "$lib_count" -gt 0 ]; do . "$1"; shift; lib_count=$((lib_count - 1)); done
"$@"' design-review-test "${#LIB_FILES[@]}" "${LIB_FILES[@]}" "$@"
  ) </dev/null >"$out_file" 2>"$err_file" || status=$?
  printf '%s' "$status"
}

# lib_call <case> <cwd> <fn> [arg...]: runs the call under both shell modes, fails <case>:modes
# when they differ, and leaves the strict run's results in CALL_RC, CALL_OUT, CALL_ERR. GIT_LOG
# holds every git argv of both runs.
lib_call() {
  local case_name="$1" cwd="$2" strict_rc lax_rc base
  shift 2
  CALL_N=$((CALL_N + 1))
  base="$TMPDIR_TEST/call.$CALL_N"
  : >"$GIT_LOG"
  strict_rc="$(run_lib_mode 'set -euo pipefail' "$cwd" "$base.s.out" "$base.s.err" "$@")"
  lax_rc="$(run_lib_mode 'set -u' "$cwd" "$base.u.out" "$base.u.err" "$@")"
  if [ "$strict_rc" != "$lax_rc" ] || ! cmp -s "$base.s.out" "$base.u.out" \
    || ! cmp -s "$base.s.err" "$base.u.err"; then
    failed "$case_name:modes" "set -euo pipefail and set -u runs differ (rc $strict_rc vs $lax_rc)"
  fi
  CALL_RC="$strict_rc"
  CALL_OUT="$base.s.out"
  CALL_ERR="$base.s.err"
}

# script_call <cwd> <arg>...: runs design-review.sh once with PATH set to LIB_PATH, the model
# setting unset and each SCRIPT_ENV assignment applied; leaves its results in CALL_RC, CALL_OUT,
# CALL_ERR and its git argv in GIT_LOG.
script_call() {
  local cwd="$1" base status=0
  shift
  CALL_N=$((CALL_N + 1))
  base="$TMPDIR_TEST/call.$CALL_N"
  : >"$GIT_LOG"
  (
    cd "$cwd" || exit 97
    env -u HIVEMIND_DESIGN_REVIEW_MODEL PATH="$LIB_PATH" DR_TEST_GIT_LOG="$GIT_LOG" \
      DR_TEST_REAL_GIT="$REAL_GIT" DR_TEST_GH_LOG="$GH_LOG" ${SCRIPT_ENV[@]+"${SCRIPT_ENV[@]}"} \
      bash "$DR_SCRIPT" "$@"
  ) </dev/null >"$base.out" 2>"$base.err" || status=$?
  CALL_RC="$status"
  CALL_OUT="$base.out"
  CALL_ERR="$base.err"
}

# file_is <file> <expected-bytes>: 0 when <file> holds exactly <expected-bytes>.
file_is() {
  local expected_file="$TMPDIR_TEST/expected.$CALL_N"
  printf '%s' "$2" >"$expected_file" || setup_fail "cannot write $expected_file"
  cmp -s "$1" "$expected_file"
}

# expect_call <case> <rc> <stdout-bytes> <stderr-bytes>: asserts the last call's results.
expect_call() {
  local case_name="$1" want_rc="$2" want_out="$3" want_err="$4"
  if [ "$CALL_RC" != "$want_rc" ]; then
    failed "$case_name" "rc $CALL_RC, want $want_rc (stdout: $(cat "$CALL_OUT") stderr: $(cat "$CALL_ERR"))"
  elif ! file_is "$CALL_OUT" "$want_out"; then
    failed "$case_name" "stdout: $(cat "$CALL_OUT"), want: $want_out"
  elif ! file_is "$CALL_ERR" "$want_err"; then
    failed "$case_name" "stderr: $(cat "$CALL_ERR"), want: $want_err"
  else
    pass "$case_name" "rc $CALL_RC"
  fi
}

# expect_no_git <case>: asserts the last call ran no git command.
expect_no_git() {
  if [ -s "$GIT_LOG" ]; then
    failed "$1:no-git" "git ran: $(head -n 1 "$GIT_LOG")"
  else
    pass "$1:no-git" "no git call"
  fi
}

# expect_git_flags <case>: asserts git ran and every logged call starts with the global flags.
expect_git_flags() {
  local line bad=0
  [ -s "$GIT_LOG" ] || bad=1
  while IFS= read -r line; do
    case "$line" in
      '--no-replace-objects --literal-pathspecs '*) ;;
      *) bad=1 ;;
    esac
  done <"$GIT_LOG"
  if [ "$bad" -eq 0 ]; then
    pass "$1:git-flags" "every git call carries the global flags"
  else
    failed "$1:git-flags" "git log: $(cat "$GIT_LOG")"
  fi
}

# ── Scratch repository ──────────────────────────────────────────────────────────────

REPO="$TMPDIR_TEST/repo"
"$REAL_GIT" init -q "$REPO" || setup_fail "git init"
mkdir -p "$REPO/docs/prds" || setup_fail "cannot create work-tree subdirectory"

# rgit <arg...>: real git in the scratch repo.
rgit() { "$REAL_GIT" -C "$REPO" "$@"; }

# store_blob <var> <bytes>: writes a blob object and assigns its id to <var>.
store_blob() {
  local blob_id
  blob_id="$(printf '%s' "$2" | rgit hash-object -w --stdin)" || setup_fail "hash-object"
  printf -v "$1" '%s' "$blob_id"
}

# object_file <oid>: prints the loose object path of <oid> in the scratch repo.
object_file() { printf '%s/.git/objects/%s/%s' "$REPO" "${1:0:2}" "${1:2}"; }

store_blob SEED_BLOB 'seed'
SEED_TREE="$(printf '100644 blob %s\tseed.md\n' "$SEED_BLOB" | rgit mktree)" || setup_fail "seed tree"
SEED_COMMIT="$(rgit commit-tree "$SEED_TREE" -m seed </dev/null)" || setup_fail "seed commit"

DOCS_FILE="$TMPDIR_TEST/docs.json"
jq -e 'type == "object" and (keys == ["diff", "docs", "round", "stamps", "verify"])
  and (.docs | type == "object" and length > 0 and all(.[]; type == "string"))
  and all(.verify[]; (keys - ["base", "exists", "expect", "head", "name", "tip"] == [])
    and has("name") and has("head") and (.expect | type == "object" and length > 0
      and (keys - ["merge", "pr"] == []) and all(.[]; type == "array")))
  and all(.stamps[]; (keys - ["error", "expect", "head", "name", "paths"] == [])
    and (has("expect") != has("error")))
  and all(.round[]; keys == ["expect", "head", "name"])
  and all(.diff[]; (keys - ["cwd", "empty", "expect", "from", "holds", "lacks", "name", "names", "to"] == [])
    and has("from") and has("to"))
  and ([.verify[], .stamps[], .round[], .diff[] | .name] | length == (unique | length))' \
  "$CASES" >/dev/null 2>&1 || setup_fail "cases file missing or off its shape: $CASES"
jq '.docs' "$CASES" >"$DOCS_FILE" || setup_fail "cannot extract the shared documents"

# ── Case documents ─────────────────────────────────────────────────────────────────
#
# A spec is {docs, records, objects}. The commit holds the shared `docs` of cases.json, then the
# spec's `docs` (null deletes a path), then each record of `records` rendered at its path. Its
# `objects` turn paths into a symlink, a gitlink, a tree or a symlinked directory, or graft a
# blob at a path the index refuses. A document's `{{blob:<path>}}` placeholder renders as the
# blob id of <path>'s content in the spec, before any object change, and `{{base:<path>}}` as the
# blob id of <path>'s content in the shared docs.
#
# SPEC_PLAN_JQ prints one tab-separated line per document: `map` lines give each placeholder-free
# document's content before object changes, then `entry`, `gitlink` and `graft` lines give the
# tree.

# shellcheck disable=SC2016
SPEC_PLAN_JQ='
def table_row: "| " + join(" | ") + " |\n";
def findings_text:
  if has("findings_raw") then .findings_raw
  elif (.findings // []) | length == 0 then ""
  else "| ID | Round | Angle | Severity | Disposition | Note |\n| --- | --- | --- | --- | --- | --- |\n"
    + (.findings | map(table_row) | add) + "\n" end;
def record_text:
  (.path // "docs/initiatives/demo/review-record.md") as $path
  | if has("raw") then {path: $path, text: .raw}
    else ($path | capture("\\Adocs/initiatives/(?<s>[^/]+)/").s) as $slug
    | ({critical: 0, high: 0, medium: 0, low: 0} + (.open // {})) as $open
    | ((.stamps // ["docs/prds/\($slug).md", "docs/initiatives/\($slug)/solution-design.md"])
       | map(if type == "string" then {path: ., blob: "{{blob:\(.)}}"}
             elif .base then {path, blob: "{{base:\(.path)}}"}
             else {path, blob} end)) as $stamps
    | ("---\n"
       + (if ($stamps | length) == 0 then "stamps: []\n"
          else "stamps:\n" + ($stamps | map("  - path: \(.path)\n    blob: \(.blob)\n") | add) end)
       + "verdict: \(.verdict // "pass")\nopen:\n  critical: \($open.critical)\n  high: \($open.high)\n"
       + "  medium: \($open.medium)\n  low: \($open.low)\nrounds: \(.rounds // 2)\n"
       + "clean_round: \(if has("clean_round") then .clean_round else true end)\n---\n\n"
       + "# Design review record\n\n## Reviewed documents\n\n- The PRD and the solution design.\n\n"
       + "## Rounds\n\n### Round 1\n\ncerebrate, its own model, the whole documents.\n\n"
       + "## Findings\n\n" + findings_text
       + "## Decisions taken, listed for veto\n\nNone.\n\n## Decisions asked\n\nNone.\n"
       + (.extra // "")) as $text
    | {path: $path, text: (if .crlf then $text | gsub("\n"; "\r\n") else $text end)}
    end;
def parent_dir: sub("/[^/]*\\z"; "");
def apply_object($object):
  if $object.type == "symlink" then
    map(select(.path != $object.path)) + [{path: $object.path, mode: "120000", text: $object.target}]
  elif $object.type == "gitlink" then
    map(select(.path != $object.path)) + [{path: $object.path, mode: "160000", gitlink: true}]
  elif $object.type == "tree" then
    map(if .path == $object.path then .path += "/child.md" else . end)
  elif $object.type == "symlinked-dir" then
    map(if (.path | startswith($object.path + "/"))
        then .path = ($object.path | parent_dir) + "/" + $object.target + .path[($object.path | length):]
        else . end)
    + [{path: $object.path, mode: "120000", text: $object.target}]
  elif $object.type == "graft" then .
  else error("unknown object type \($object.type)") end;
. as $spec
| ($docs[0] + ($spec.docs // {})
   + ([($spec.records // [])[] | record_text | {(.path): .text}] | add // {})
   | with_entries(select(.value != null))) as $merged
| ($merged | to_entries | map(select(.value | contains("{{") | not))[]
   | "map\t100644\t\(.key)\t\(.value | @base64)"),
  (reduce ($spec.objects // [])[] as $object
     ($merged | to_entries | map({path: .key, mode: "100644", text: .value}); apply_object($object))
   | .[]
   | if .gitlink then "gitlink\t160000\t\(.path)\t-"
     else "entry\t\(.mode)\t\(.path)\t\(.text | @base64)" end),
  (($spec.objects // [])[] | select(.type == "graft") | "graft\t100644\t\(.path)\t\(.text | @base64)")'

declare -A HASH_CACHE=() BASE_BLOBS=() SPEC_BLOBS=()
GRAFT_TREE=""

# decode_text <var> <base64>: assigns the decoded bytes, ending newlines kept, to <var>.
decode_text() {
  local decoded
  decoded="$(printf '%s' "$2" | base64 -d && printf x)" || setup_fail "base64 decode"
  printf -v "$1" '%s' "${decoded%x}"
}

# hash_encoded <var> <base64>: writes a blob of the decoded bytes once and assigns its id to <var>.
hash_encoded() {
  local text stored_id
  if [ -z "${HASH_CACHE[$2]+set}" ]; then
    decode_text text "$2"
    store_blob stored_id "$text"
    HASH_CACHE[$2]="$stored_id"
  fi
  printf -v "$1" '%s' "${HASH_CACHE[$2]}"
}

# render_text <var> <bytes>: assigns <bytes> with every placeholder rendered to <var>.
render_text() {
  local rendered="$2" path
  for path in "${!SPEC_BLOBS[@]}"; do
    rendered="${rendered//"{{blob:$path}}"/${SPEC_BLOBS[$path]}}"
  done
  for path in "${!BASE_BLOBS[@]}"; do
    rendered="${rendered//"{{base:$path}}"/${BASE_BLOBS[$path]}}"
  done
  case "$rendered" in
    *'{{'*) setup_fail "unrendered placeholder in a case document" ;;
  esac
  printf -v "$1" '%s' "$rendered"
}

# graft_tree <tree> <path> <blob>: sets GRAFT_TREE to the id of <tree> with a 100644 entry for
# <blob> at <path>, built with mktree so a path part the index refuses, such as `.git`, is stored.
graft_tree() {
  local tree="$1" path="$2" blob="$3" name="${2%%/*}" child="" kept="" line=""
  if [ "$name" = "$path" ]; then
    line="100644 blob $blob"$'\t'"$name"
  else
    child="$(rgit rev-parse --verify --quiet "$tree:$name")" || child="$(rgit mktree </dev/null)" \
      || setup_fail "graft subtree $name"
    graft_tree "$child" "${path#*/}" "$blob"
    line="040000 tree $GRAFT_TREE"$'\t'"$name"
  fi
  kept="$(rgit ls-tree "$tree" | grep -v -F -x -e "$(rgit ls-tree "$tree" -- "$name")")" || kept=""
  GRAFT_TREE="$(printf '%s%s\n' "${kept:+$kept$'\n'}" "$line" | rgit mktree)" \
    || setup_fail "graft mktree $path"
}

# build_spec_commit <var> <spec-json>: builds the spec's document tree as a commit and assigns its
# id to <var>; SPEC_BLOBS holds the spec's placeholder blob ids afterwards.
build_spec_commit() {
  local var="$1" spec_file="$TMPDIR_TEST/spec.$1.json" plan_file="$TMPDIR_TEST/plan.$1"
  local index_file="$TMPDIR_TEST/index.$1" kind mode path encoded oid text tree_id commit_id
  local index_info=""
  local -a grafts=()
  printf '%s' "$2" >"$spec_file" || setup_fail "cannot write $spec_file"
  jq -r --slurpfile docs "$DOCS_FILE" "$SPEC_PLAN_JQ" "$spec_file" >"$plan_file" \
    || setup_fail "spec plan for $var"
  SPEC_BLOBS=()
  while IFS=$'\t' read -r kind mode path encoded; do
    case "$kind" in
      map)
        hash_encoded oid "$encoded"
        SPEC_BLOBS[$path]="$oid"
        ;;
      gitlink) index_info+="$mode $SEED_COMMIT"$'\t'"$path"$'\n' ;;
      entry)
        decode_text text "$encoded"
        if [[ "$text" == *'{{'* ]]; then
          render_text text "$text"
          store_blob oid "$text"
        else
          hash_encoded oid "$encoded"
        fi
        index_info+="$mode $oid"$'\t'"$path"$'\n'
        ;;
      graft)
        hash_encoded oid "$encoded"
        grafts+=("$path"$'\t'"$oid")
        ;;
      *) setup_fail "spec plan line kind $kind" ;;
    esac
  done <"$plan_file"
  rm -f "$index_file"
  printf '%s' "$index_info" | GIT_INDEX_FILE="$index_file" rgit update-index --index-info \
    || setup_fail "update-index for $var"
  tree_id="$(GIT_INDEX_FILE="$index_file" rgit write-tree)" || setup_fail "write-tree for $var"
  for path in ${grafts[@]+"${grafts[@]}"}; do
    graft_tree "$tree_id" "${path%%$'\t'*}" "${path#*$'\t'}"
    tree_id="$GRAFT_TREE"
  done
  commit_id="$(rgit commit-tree "$tree_id" -m "$var" </dev/null)" || setup_fail "commit-tree for $var"
  printf -v "$var" '%s' "$commit_id"
}

build_spec_commit BASE_COMMIT '{}'
for shared_path in "${!SPEC_BLOBS[@]}"; do
  BASE_BLOBS[$shared_path]="${SPEC_BLOBS[$shared_path]}"
done
RECORD_PATH='docs/initiatives/demo/review-record.md'

# verify_lines <json-array>: prints the expected verify stdout for the failing record paths.
verify_lines() {
  printf '%s' "$1" | jq -r '.[] | "record-verify-failed: " + .' || setup_fail "verify lines"
}

# ── Sections ───────────────────────────────────────────────────────────────────────

test_verify_cases() {
  local count index name base_spec head_spec tip_spec pr_expect merge_expect exists_paths
  local want_out want_rc path
  count="$(jq '.verify | length' "$CASES")" || setup_fail "cannot count verify cases"
  for ((index = 0; index < count; index++)); do
    {
      read -r name
      read -r base_spec
      read -r head_spec
      read -r tip_spec
      read -r pr_expect
      read -r merge_expect
      read -r exists_paths
    } < <(jq -r --argjson i "$index" '.verify[$i]
      | .name, (.base // {} | tojson), (.head | tojson), (.tip // .base // {} | tojson),
        (.expect.pr // null | tojson), (.expect.merge // null | tojson), (.exists // [] | tojson)' \
      "$CASES")
    build_spec_commit CASE_BASE "$base_spec"
    build_spec_commit CASE_TIP "$tip_spec"
    build_spec_commit CASE_HEAD "$head_spec"
    while IFS= read -r path; do
      lib_call "verify:$name:exists" "$REPO" hivemind_doc_entry "$CASE_HEAD" "$path"
      expect_call "verify:$name:exists:$path" 0 "$(rgit rev-parse "$CASE_HEAD:$path")"$'\n' ""
    done < <(printf '%s' "$exists_paths" | jq -r '.[]')
    if [ "$pr_expect" != null ]; then
      want_out="$(verify_lines "$pr_expect")"
      want_rc=0
      if [ -n "$want_out" ]; then
        want_out+=$'\n'
        want_rc=1
      fi
      lib_call "verify:$name:pr" "$REPO" hivemind_record_verify "$CASE_HEAD" "$CASE_BASE"
      expect_call "verify:$name:pr" "$want_rc" "$want_out" ""
      expect_git_flags "verify:$name:pr"
      script_call "$REPO" verify --head "$CASE_HEAD" --base "$CASE_BASE"
      expect_call "verify:$name:script-relay" "$want_rc" "$want_out" ""
    fi
    if [ "$merge_expect" != null ]; then
      want_out="$(verify_lines "$merge_expect")"
      want_rc=0
      if [ -n "$want_out" ]; then
        want_out+=$'\n'
        want_rc=1
      fi
      lib_call "verify:$name:merge" "$REPO" hivemind_record_verify_merge "$CASE_HEAD" "$CASE_BASE" "$CASE_TIP"
      expect_call "verify:$name:merge" "$want_rc" "$want_out" ""
      expect_git_flags "verify:$name:merge"
    fi
  done
}

test_verify_errors() {
  local form unknown blob_id gone_tree
  build_spec_commit ERR_HEAD '{"records": [{}]}'
  unknown="$(printf '%040d' 0)"
  blob_id="${BASE_BLOBS[docs/prds/demo.md]}"

  lib_call "verify-error:usage-one-arg" "$REPO" hivemind_record_verify "$ERR_HEAD"
  expect_call "verify-error:usage-one-arg" 2 "" $'record-verify-error: usage\n'
  expect_no_git "verify-error:usage-one-arg"
  lib_call "verify-error:usage-three-args" "$REPO" hivemind_record_verify "$ERR_HEAD" "$BASE_COMMIT" "$BASE_COMMIT"
  expect_call "verify-error:usage-three-args" 2 "" $'record-verify-error: usage\n'
  expect_no_git "verify-error:usage-three-args"
  lib_call "verify-error:merge-usage" "$REPO" hivemind_record_verify_merge "$ERR_HEAD" "$BASE_COMMIT"
  expect_call "verify-error:merge-usage" 2 "" $'record-verify-error: usage\n'
  expect_no_git "verify-error:merge-usage"

  for form in HEAD "${ERR_HEAD:0:7}" "$(printf '%s' "$ERR_HEAD" | tr 'a-f' 'A-F')" "" "-x" "$ERR_HEAD"$'\n'; do
    lib_call "verify-error:commit-malformed" "$REPO" hivemind_record_verify "$form" "$BASE_COMMIT"
    expect_call "verify-error:commit-malformed:head:$(printf '%q' "$form")" 2 "" \
      $'record-verify-error: commit-malformed\n'
    expect_no_git "verify-error:commit-malformed:head:$(printf '%q' "$form")"
  done
  lib_call "verify-error:commit-malformed-base" "$REPO" hivemind_record_verify "$ERR_HEAD" main
  expect_call "verify-error:commit-malformed-base" 2 "" $'record-verify-error: commit-malformed\n'
  expect_no_git "verify-error:commit-malformed-base"
  lib_call "verify-error:commit-malformed-tip" "$REPO" hivemind_record_verify_merge "$unknown" "$BASE_COMMIT" main
  expect_call "verify-error:commit-malformed-tip" 2 "" $'record-verify-error: commit-malformed\n'
  expect_no_git "verify-error:commit-malformed-tip"

  lib_call "verify-error:commit-unresolvable" "$REPO" hivemind_record_verify "$unknown" "$BASE_COMMIT"
  expect_call "verify-error:commit-unresolvable" 2 "" $'record-verify-error: commit-unresolvable\n'
  lib_call "verify-error:blob-unresolvable" "$REPO" hivemind_record_verify "$ERR_HEAD" "$blob_id"
  expect_call "verify-error:blob-unresolvable" 2 "" $'record-verify-error: commit-unresolvable\n'
  lib_call "verify-error:tip-unresolvable" "$REPO" hivemind_record_verify_merge "$ERR_HEAD" "$BASE_COMMIT" "$unknown"
  expect_call "verify-error:tip-unresolvable" 2 "" $'record-verify-error: commit-unresolvable\n'

  LIB_FILES=("$RV_LIB")
  lib_call "verify-error:missing-readiness-lib" "$REPO" hivemind_record_verify "$ERR_HEAD" "$BASE_COMMIT"
  LIB_FILES=("$RC_LIB" "$RV_LIB")
  expect_call "verify-error:missing-readiness-lib" 2 "" $'record-verify-error: missing-readiness-lib\n'
  expect_no_git "verify-error:missing-readiness-lib"

  build_spec_commit GONE_HEAD '{"docs": {"docs/prds/gone.md": "# Gone\n\nOnly under the deleted tree.\n"}, "records": [{}]}'
  gone_tree="$(rgit rev-parse "$GONE_HEAD:docs/prds")" || setup_fail "rev-parse deleted tree"
  rm -f "$(object_file "$gone_tree")" || setup_fail "cannot delete tree object"
  lib_call "verify-error:git-failed" "$REPO" hivemind_record_verify "$GONE_HEAD" "$BASE_COMMIT"
  expect_call "verify-error:git-failed" 2 "" $'record-verify-error: git-failed\n'
  script_call "$REPO" verify --head "$GONE_HEAD" --base "$BASE_COMMIT"
  expect_call "verify-error:git-failed:script-relay" 2 "" $'record-verify-error: git-failed\n'

  script_call "$REPO" verify --head "$ERR_HEAD" --base HEAD
  expect_call "verify-error:commit-malformed:script-relay" 2 "" $'record-verify-error: commit-malformed\n'
  expect_no_git "verify-error:commit-malformed:script-relay"
  script_call "$REPO" verify --head "$ERR_HEAD" --base "$unknown"
  expect_call "verify-error:commit-unresolvable:script-relay" 2 "" $'record-verify-error: commit-unresolvable\n'
  for form in "verify --head $ERR_HEAD" "verify --head $ERR_HEAD --base $BASE_COMMIT --base $BASE_COMMIT" \
    "verify --head $ERR_HEAD --base $BASE_COMMIT --extra" "verify --head" "" "unknown"; do
    # shellcheck disable=SC2086
    script_call "$REPO" $form
    expect_call "script-usage:$form" 2 "" $'design-review-error: usage\n'
    expect_no_git "script-usage:$form"
  done
}

test_stamps_cases() {
  local count index name head_spec paths_json want_json error_token want_out line stamp_line
  local -a paths=()
  count="$(jq '.stamps | length' "$CASES")" || setup_fail "cannot count stamps cases"
  for ((index = 0; index < count; index++)); do
    {
      read -r name
      read -r head_spec
      read -r paths_json
      read -r want_json
      read -r error_token
    } < <(jq -r --argjson i "$index" '.stamps[$i]
      | .name, (.head | tojson), (.paths | tojson), (.expect // null | tojson), (.error // "")' "$CASES")
    build_spec_commit STAMPS_HEAD "$head_spec"
    mapfile -t paths < <(printf '%s' "$paths_json" | jq -r '.[]')
    script_call "$REPO" stamps --commit "$STAMPS_HEAD" "${paths[@]}"
    if [ -n "$error_token" ]; then
      expect_call "stamps:$name" 2 "" "design-review-error: $error_token"$'\n'
      expect_no_git "stamps:$name"
      continue
    fi
    want_out=""
    while IFS= read -r line; do
      render_text stamp_line "$line"
      want_out+="$stamp_line"$'\n'
    done < <(printf '%s' "$want_json" | jq -r '.[]')
    expect_call "stamps:$name" 0 "$want_out" ""
  done
  script_call "$REPO" stamps --commit "$BASE_COMMIT"
  expect_call "stamps:no-path" 2 "" $'design-review-error: usage\n'
  script_call "$REPO" stamps --commit HEAD docs/prds/demo.md
  expect_call "stamps:commit-malformed" 2 "" $'design-review-error: commit-malformed\n'
  expect_no_git "stamps:commit-malformed"
  script_call "$REPO" stamps --commit "$(printf '%040d' 0)" docs/prds/demo.md
  expect_call "stamps:commit-unresolvable" 2 "" $'design-review-error: commit-unresolvable\n'
}

test_round_cases() {
  local count index name head_spec want_json want_out
  count="$(jq '.round | length' "$CASES")" || setup_fail "cannot count round cases"
  for ((index = 0; index < count; index++)); do
    {
      read -r name
      read -r head_spec
      read -r want_json
    } < <(jq -r --argjson i "$index" '.round[$i] | .name, (.head | tojson), (.expect | tojson)' "$CASES")
    build_spec_commit ROUND_HEAD "$head_spec"
    want_out="$(printf '%s' "$want_json" | jq -r '.[]')"$'\n'
    script_call "$REPO" round --commit "$ROUND_HEAD" --slug demo
    expect_call "round:$name" 0 "$want_out" ""
  done
  for name in Demo demo-- -demo 'demo/x' ''; do
    script_call "$REPO" round --commit "$BASE_COMMIT" --slug "$name"
    expect_call "round:slug-malformed:$(printf '%q' "$name")" 2 "" $'design-review-error: usage\n'
    expect_no_git "round:slug-malformed:$(printf '%q' "$name")"
  done
  script_call "$REPO" round --commit "$BASE_COMMIT" --slug demo --slug demo
  expect_call "round:repeated-flag" 2 "" $'design-review-error: usage\n'
  script_call "$REPO" round --commit "${BASE_COMMIT:0:12}" --slug demo
  expect_call "round:commit-malformed" 2 "" $'design-review-error: commit-malformed\n'
  expect_no_git "round:commit-malformed"
  script_call "$REPO" round --commit "$(printf '%040d' 0)" --slug demo
  expect_call "round:commit-unresolvable" 2 "" $'design-review-error: commit-unresolvable\n'
  CALL_N=$((CALL_N + 1))
  : >"$GIT_LOG"
  CALL_RC=0
  CALL_OUT="$TMPDIR_TEST/call.$CALL_N.out"
  CALL_ERR="$TMPDIR_TEST/call.$CALL_N.err"
  (
    cd "$REPO" || exit 97
    env -u HIVEMIND_DESIGN_REVIEW_MODEL PATH="$NOJQ_DIR" DR_TEST_GIT_LOG="$GIT_LOG" \
      DR_TEST_REAL_GIT="$REAL_GIT" "$BASH" "$DR_SCRIPT" round --commit "$BASE_COMMIT" --slug demo
  ) </dev/null >"$CALL_OUT" 2>"$CALL_ERR" || CALL_RC=$?
  expect_call "round:jq-missing" 2 "" $'design-review-error: jq-missing\n'
  expect_no_git "round:jq-missing"
}

test_diff_cases() {
  local count index name from_spec to_spec names cwd empty want_json holds_json lacks_json
  local want_out needle bad
  count="$(jq '.diff | length' "$CASES")" || setup_fail "cannot count diff cases"
  for ((index = 0; index < count; index++)); do
    {
      read -r name
      read -r from_spec
      read -r to_spec
      read -r names
      read -r cwd
      read -r empty
      read -r want_json
      read -r holds_json
      read -r lacks_json
    } < <(jq -r --argjson i "$index" '.diff[$i]
      | .name, (.from | tojson), (.to | tojson), (.names // false), (.cwd // ""), (.empty // false),
        (.expect // [] | tojson), (.holds // [] | tojson), (.lacks // [] | tojson)' "$CASES")
    build_spec_commit DIFF_FROM "$from_spec"
    build_spec_commit DIFF_TO "$to_spec"
    if [ "$names" = true ]; then
      script_call "$REPO/$cwd" diff --from "$DIFF_FROM" --to "$DIFF_TO" --names
      want_out="$(printf '%s' "$want_json" | jq -r '.[]')"
      expect_call "diff:$name" 0 "${want_out:+$want_out$'\n'}" ""
      continue
    fi
    script_call "$REPO/$cwd" diff --from "$DIFF_FROM" --to "$DIFF_TO"
    if [ "$empty" = true ]; then
      expect_call "diff:$name" 0 "" ""
      continue
    fi
    bad=""
    if [ "$CALL_RC" != 0 ] || [ -s "$CALL_ERR" ] || ! [ -s "$CALL_OUT" ]; then
      bad="rc $CALL_RC, stderr: $(cat "$CALL_ERR")"
    fi
    while IFS= read -r needle; do
      grep -q -F -x -e "$needle" "$CALL_OUT" || bad+=" lacks line: $needle"
    done < <(printf '%s' "$holds_json" | jq -r '.[]')
    while IFS= read -r needle; do
      if grep -q -F -e "$needle" "$CALL_OUT"; then
        bad+=" holds: $needle"
      fi
    done < <(printf '%s' "$lacks_json" | jq -r '.[]')
    if [ -z "$bad" ]; then
      pass "diff:$name" "docs-only unified diff"
    else
      failed "diff:$name" "$bad"
    fi
  done
  script_call "$REPO" diff --from "$BASE_COMMIT" --to HEAD
  expect_call "diff:commit-malformed" 2 "" $'design-review-error: commit-malformed\n'
  expect_no_git "diff:commit-malformed"
  script_call "$REPO" diff --from "$(printf '%040d' 0)" --to "$BASE_COMMIT" --names
  expect_call "diff:commit-unresolvable" 2 "" $'design-review-error: commit-unresolvable\n'
  script_call "$REPO" diff --from "$BASE_COMMIT" --to "$BASE_COMMIT" --names --names
  expect_call "diff:repeated-names" 2 "" $'design-review-error: usage\n'
  expect_no_git "diff:repeated-names"
}

test_head() {
  local head_repo="$TMPDIR_TEST/head-repo" first second
  "$REAL_GIT" init -q "$head_repo" || setup_fail "head repo init"
  printf 'one\n' >"$head_repo/file.md" || setup_fail "head repo file"
  "$REAL_GIT" -C "$head_repo" add file.md && "$REAL_GIT" -C "$head_repo" commit -q -m one \
    || setup_fail "head repo first commit"
  first="$("$REAL_GIT" -C "$head_repo" rev-parse HEAD)" || setup_fail "head repo rev-parse"
  script_call "$head_repo" head --commit "$first"
  expect_call "head:ok" 0 $'head=ok\n' ""
  printf 'untracked\n' >"$head_repo/new.md" || setup_fail "head repo untracked file"
  script_call "$head_repo" head --commit "$first"
  expect_call "head:dirty-untracked" 1 $'head=dirty\n' ""
  rm -f "$head_repo/new.md" || setup_fail "head repo cleanup"
  printf 'two\n' >"$head_repo/file.md" || setup_fail "head repo edit"
  script_call "$head_repo" head --commit "$first"
  expect_call "head:dirty-modified" 1 $'head=dirty\n' ""
  "$REAL_GIT" -C "$head_repo" commit -q -a -m two || setup_fail "head repo second commit"
  second="$("$REAL_GIT" -C "$head_repo" rev-parse HEAD)" || setup_fail "head repo rev-parse two"
  script_call "$head_repo" head --commit "$first"
  expect_call "head:moved" 1 $'head=moved\n' ""
  printf 'untracked\n' >"$head_repo/new.md" || setup_fail "head repo untracked file"
  script_call "$head_repo" head --commit "$first"
  expect_call "head:dirty-checked-first" 1 $'head=dirty\n' ""
  rm -f "$head_repo/new.md" || setup_fail "head repo cleanup"
  script_call "$head_repo" head --commit "$second"
  expect_call "head:ok-after-commit" 0 $'head=ok\n' ""
  script_call "$head_repo" head --commit HEAD
  expect_call "head:commit-malformed" 2 "" $'design-review-error: commit-malformed\n'
  expect_no_git "head:commit-malformed"
}

test_model() {
  local value
  SCRIPT_ENV=()
  script_call "$REPO" model
  expect_call "model:unset" 0 $'model=default\n' ""
  SCRIPT_ENV=(HIVEMIND_DESIGN_REVIEW_MODEL=)
  script_call "$REPO" model
  expect_call "model:empty" 0 $'model=default\n' ""
  for value in claude-opus-4-1 'claude-sonnet-4-5[1m]' gpt-5.1-codex o3:high \
    "a$(printf 'b%.0s' $(seq 1 63))"; do
    SCRIPT_ENV=("HIVEMIND_DESIGN_REVIEW_MODEL=$value")
    script_call "$REPO" model
    expect_call "model:valid:$value" 0 "model=$value"$'\n' ""
  done
  for value in 'bad model' 'x;rm -rf /' '-leading' '$(id)' "a$(printf 'b%.0s' $(seq 1 64))" \
    $'line\nbreak' 'model/slash'; do
    SCRIPT_ENV=("HIVEMIND_DESIGN_REVIEW_MODEL=$value")
    script_call "$REPO" model
    expect_call "model:malformed:$(printf '%q' "$value")" 0 $'model=default\nsetting=invalid\n' ""
  done
  SCRIPT_ENV=()
  script_call "$REPO" model extra
  expect_call "model:usage" 2 "" $'design-review-error: usage\n'
}

test_principle_free() {
  local doc hits
  for doc in "$DR_SKILL" "$DR_FORMAT"; do
    hits="$(grep -n -E -e 'engineering-principles' -e '\bP[0-9]+\b' "$doc")" || hits=""
    if [ -z "$hits" ]; then
      pass "principle-free:${doc#"$REPO_ROOT"/}" "no engineering-principles reference or principle id"
    else
      failed "principle-free:${doc#"$REPO_ROOT"/}" "$hits"
    fi
  done
}

test_no_gh() {
  if [ -s "$GH_LOG" ]; then
    failed "no-gh" "gh ran: $(head -n 1 "$GH_LOG")"
  else
    pass "no-gh" "no gh call across the suite"
  fi
}

test_verify_cases
test_verify_errors
test_stamps_cases
test_round_cases
test_diff_cases
test_head
test_model
test_principle_free
test_no_gh

echo ""
echo "Passed: $PASS_COUNT, failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
