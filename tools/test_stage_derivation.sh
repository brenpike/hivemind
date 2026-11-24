#!/usr/bin/env bash
#
# Behavioral unit runner for the stage derivation library:
#   plugin/skills/_shared/stage-derivation.sh
#
# OFFLINE git/jq/bash TEST — needs only bash, git and jq (NO gh / network / auth). Every case
# sources the readiness check library, the record verify library and the stage derivation library,
# in that order, in a fresh `bash -c` twice, once under `set -euo pipefail` and once under `set -u`
# alone, and asserts both runs give identical stdout, stderr and exit status. Git fixtures are
# scratch commits built with plumbing only, so every tree entry mode is exact (100644, 120000
# symlink, 160000 gitlink, tree); a case's docs head commit has its trunk commit as parent, so the
# merge-base verify reads is real. A recording `git` wrapper shadowed on PATH logs each git argv,
# proving the "no git call" cases and the global git flags on every call. A recording `gh` stub
# beside it logs every gh argv and serves only canned routes; the suite fails when any derive or
# handoff case called it. The evidence read, hivemind_stage_evidence_gh, runs against that stub
# alone, served from tests/stage-derivation/gh-cases.json: no live gh call.
#
# Fixture data lives in tests/stage-derivation/cases.json, handoff-cases.json, gh-cases.json and
# docs.json;
# tests/stage-derivation/README.md describes their layout. Sections are functions (test_<area>).
# Mirrors tools/test_readiness_check.sh's pass/fail counter, exit 1 on any failure, exit 2 on
# set-up failure and scratch dir removed on EXIT. Read-only: the only writes are in the scratch
# dir.
#
# Usage:
#   ./tools/test_stage_derivation.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
RC_LIB="$REPO_ROOT/plugin/skills/_shared/readiness-check.sh"
RV_LIB="$REPO_ROOT/plugin/skills/_shared/record-verify.sh"
SD_LIB="$REPO_ROOT/plugin/skills/_shared/stage-derivation.sh"
CASES="$REPO_ROOT/tests/stage-derivation/cases.json"
DOCS="$REPO_ROOT/tests/stage-derivation/docs.json"
HANDOFF_CASES="$REPO_ROOT/tests/stage-derivation/handoff-cases.json"
GH_CASES="$REPO_ROOT/tests/stage-derivation/gh-cases.json"

for required_file in "$RC_LIB" "$RV_LIB" "$SD_LIB" "$CASES" "$DOCS" "$HANDOFF_CASES" "$GH_CASES"; do
  [ -f "$required_file" ] || { echo "FAIL: file under test missing: $required_file" >&2; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this suite" >&2; exit 2; }
REAL_GIT="$(command -v git)" || { echo "FAIL: git is required to run this suite" >&2; exit 2; }

make_scratch_dir TMPDIR_TEST
trap 'rm -rf "$TMPDIR_TEST"' EXIT

export HOME="$TMPDIR_TEST/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=stage-test GIT_AUTHOR_EMAIL=stage-test@example.invalid
export GIT_COMMITTER_NAME=stage-test GIT_COMMITTER_EMAIL=stage-test@example.invalid
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
mkdir -p "$HOME" || { echo "FAIL: cannot create scratch HOME" >&2; exit 2; }

WRAP_DIR="$TMPDIR_TEST/wrap-bin"
GIT_LOG="$TMPDIR_TEST/git-calls.log"
GH_LOG="$TMPDIR_TEST/gh-calls.log"
GH_SERVE_DIR="$TMPDIR_TEST/gh-serve"
NO_GH_DIR="$TMPDIR_TEST/no-gh-bin"
mkdir -p "$WRAP_DIR" "$GH_SERVE_DIR" "$NO_GH_DIR" || { echo "FAIL: cannot create wrapper dirs" >&2; exit 2; }
: >"$GH_LOG" || { echo "FAIL: cannot create the gh log" >&2; exit 2; }
printf '%s\n' '#!/bin/sh' \
  'printf "%s\n" "$*" >>"$SD_TEST_GIT_LOG"' \
  'exec "$SD_TEST_REAL_GIT" "$@"' >"$WRAP_DIR/git" \
  && chmod +x "$WRAP_DIR/git" \
  || { echo "FAIL: cannot write the recording git wrapper" >&2; exit 2; }
# The recording gh stub logs each call's argv as one line of <arg> fields, then serves the canned
# body and exit status of the route in SD_TEST_GH_DIR whose key is exactly that line, else exits 1.
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' \
  'key="$(printf "<%s>" "$@")"' \
  'printf "%s\n" "$key" >>"$SD_TEST_GH_LOG"' \
  'id="$(printf "%s" "$key" | cksum | cut -d " " -f 1)"' \
  'if [ -n "${SD_TEST_GH_DIR-}" ] && [ -f "$SD_TEST_GH_DIR/$id.key" ] \' \
  '  && [ "$(cat "$SD_TEST_GH_DIR/$id.key")" = "$key" ]; then' \
  '  cat "$SD_TEST_GH_DIR/$id.body"' \
  '  exit "$(cat "$SD_TEST_GH_DIR/$id.rc")"' \
  'fi' \
  'exit 1' >"$WRAP_DIR/gh" \
  && chmod +x "$WRAP_DIR/gh" \
  || { echo "FAIL: cannot write the recording gh stub" >&2; exit 2; }
LIB_PATH="$WRAP_DIR:$PATH"
# NO_GH_DIR is a PATH holding only bash and jq, for the case where gh is not installed.
for tool_name in bash jq; do
  tool_path="$(command -v "$tool_name")" && ln -s "$tool_path" "$NO_GH_DIR/$tool_name" \
    || { echo "FAIL: cannot link $tool_name into the no-gh PATH" >&2; exit 2; }
done
CALL_PATH="$LIB_PATH"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
setup_fail() { echo "FAIL: set-up: $1" >&2; exit 2; }

CALL_N=0
CALL_RC=0
CALL_OUT=""
CALL_ERR=""
CALL_LIBS=("$RC_LIB" "$RV_LIB" "$SD_LIB")
NO_INPUT="$TMPDIR_TEST/empty-input"
: >"$NO_INPUT" || setup_fail "cannot create the empty input file"

# run_lib_mode <prelude> <cwd> <stdin-file> <out> <err> <fn> [arg...]: sources CALL_LIBS in order,
# then runs one library call, in a fresh bash under <prelude> with PATH set to CALL_PATH; prints
# its exit status.
run_lib_mode() {
  local prelude="$1" cwd="$2" in_file="$3" out_file="$4" err_file="$5" status=0
  shift 5
  (
    cd "$cwd" || exit 97
    PATH="$CALL_PATH" SD_TEST_GIT_LOG="$GIT_LOG" SD_TEST_REAL_GIT="$REAL_GIT" SD_TEST_GH_LOG="$GH_LOG" \
      SD_TEST_GH_DIR="$GH_SERVE_DIR" bash -c "$prelude"'; while [ "$1" != -- ]; do . "$1"; shift; done; shift; "$@"' \
      stage-test "${CALL_LIBS[@]}" -- "$@"
  ) <"$in_file" >"$out_file" 2>"$err_file" || status=$?
  printf '%s' "$status"
}

# lib_call <case> <cwd> <stdin-file> <fn> [arg...]: runs the call under both shell modes, fails
# <case>:modes when they differ, and leaves the strict run's results in CALL_RC, CALL_OUT,
# CALL_ERR. GIT_LOG holds every git argv of both runs.
lib_call() {
  local case_name="$1" cwd="$2" in_file="$3" strict_rc lax_rc base
  shift 3
  CALL_N=$((CALL_N + 1))
  base="$TMPDIR_TEST/call.$CALL_N"
  : >"$GIT_LOG"
  strict_rc="$(run_lib_mode 'set -euo pipefail' "$cwd" "$in_file" "$base.s.out" "$base.s.err" "$@")"
  lax_rc="$(run_lib_mode 'set -u' "$cwd" "$in_file" "$base.u.out" "$base.u.err" "$@")"
  if [ "$strict_rc" != "$lax_rc" ] || ! cmp -s "$base.s.out" "$base.u.out" \
    || ! cmp -s "$base.s.err" "$base.u.err"; then
    failed "$case_name:modes" "set -euo pipefail and set -u runs differ (rc $strict_rc vs $lax_rc)"
  fi
  CALL_RC="$strict_rc"
  CALL_OUT="$base.s.out"
  CALL_ERR="$base.s.err"
}

# file_is <file> <expected-bytes>: 0 when <file> holds exactly <expected-bytes>.
file_is() {
  local expected_file="$TMPDIR_TEST/expected.$CALL_N"
  printf '%s' "$2" >"$expected_file" || setup_fail "cannot write $expected_file"
  cmp -s "$1" "$expected_file"
}

# expect_call <case> <rc> <stdout-bytes> <stderr-bytes>: asserts the last lib_call's results.
expect_call() {
  local case_name="$1" want_rc="$2" want_out="$3" want_err="$4"
  if [ "$CALL_RC" != "$want_rc" ]; then
    failed "$case_name" "rc $CALL_RC, want $want_rc (stderr: $(cat "$CALL_ERR"))"
  elif ! file_is "$CALL_OUT" "$want_out"; then
    failed "$case_name" "stdout: $(cat "$CALL_OUT"), want: $want_out"
  elif ! file_is "$CALL_ERR" "$want_err"; then
    failed "$case_name" "stderr: $(cat "$CALL_ERR"), want: $want_err"
  else
    pass "$case_name" "rc $CALL_RC"
  fi
}

# expect_no_git <case>: asserts the last lib_call ran no git command.
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

# write_input <name> <bytes>: writes a stdin file into the scratch dir and prints its path.
write_input() {
  local input_file="$TMPDIR_TEST/input.$1"
  printf '%s' "$2" >"$input_file" || setup_fail "cannot write $input_file"
  printf '%s' "$input_file"
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

# decode_text <var> <base64>: assigns the decoded bytes, ending newlines kept, to <var>.
decode_text() {
  local decoded
  decoded="$(printf '%s' "$2" | base64 -d && printf x)" || setup_fail "base64 decode"
  printf -v "$1" '%s' "${decoded%x}"
}

store_blob GITLINK_BLOB 'gitlink target content'
GITLINK_TREE="$(printf '100644 blob %s\tREADME.md\n' "$GITLINK_BLOB" | rgit mktree)" || setup_fail "mktree"
GITLINK_COMMIT="$(rgit commit-tree "$GITLINK_TREE" -m gitlink </dev/null)" || setup_fail "gitlink commit"
UNFETCHED='0123456789abcdef0123456789abcdef01234567'

declare -A NAME_BLOBS=()
NAME_LINES="$(jq -r 'to_entries[] | "\(.key)\t\(.value | @base64)"' "$DOCS")" \
  || setup_fail "docs file does not parse: $DOCS"
while IFS=$'\t' read -r doc_name encoded; do
  decode_text doc_text "$encoded"
  store_blob doc_oid "$doc_text"
  NAME_BLOBS[$doc_name]="$doc_oid"
done < <(printf '%s\n' "$NAME_LINES")
[ "${#NAME_BLOBS[@]}" -gt 0 ] || setup_fail "docs file holds no document: $DOCS"

jq -e 'type == "array" and length > 0
  and all(.[]; (.name | type) == "string" and has("trunk") and (has("expect") != has("error"))
    and (keys - ["docs", "error", "evidence", "evidence_raw", "expect", "lacks", "name", "no_git",
                 "no_git_text", "repo_arg", "slug_arg", "trunk", "trunk_arg", "trunk_name_arg"] == [])
    and (if has("expect") then (.expect | has("stage") and has("status") and has("next")
                                and has("reasons")) else true end))' "$CASES" >/dev/null 2>&1 \
  || setup_fail "cases file missing or off its shape: $CASES"

jq -e 'type == "array" and length > 0
  and all(.[]; (.name | type) == "string" and (has("expect") != has("error"))
    and (keys - ["derive", "error", "evidence", "expect", "name", "no_git", "trunk", "trunk_arg"] == [])
    and (if has("expect") then (.expect | has("result") and has("reasons") and has("slices")) else true end)
    and (if has("derive") then (.derive | has("stage") and has("status") and has("next")
                                and has("reasons")) else true end))' "$HANDOFF_CASES" >/dev/null 2>&1 \
  || setup_fail "handoff cases file missing or off its shape: $HANDOFF_CASES"

# ── Case commits ────────────────────────────────────────────────────────────────────
#
# SPEC_PLAN_JQ reads a case and prints one tab-separated line per tree entry of its trunk spec
# (`$which` "trunk") or its docs spec (`$which` "docs": the trunk spec's documents and records
# with the docs spec's overrides, and only the docs spec's objects). A record's stamp blob is the
# placeholder `{{name:<docs.json key>}}`, rendered from NAME_BLOBS.

# shellcheck disable=SC2016
SPEC_PLAN_JQ='
def record_text($docs):
  (.path // "docs/initiatives/demo/review-record.md") as $path
  | if has("raw") then {path: $path, text: ($names[0][.raw] // error("unknown record name"))}
    else ($path | capture("\\Adocs/initiatives/(?<s>[^/]+)/").s) as $slug
    | ({critical: 0, high: 0, medium: 0, low: 0} + (.open // {})) as $open
    | ((.stamps // ["docs/prds/\($slug).md", "docs/initiatives/\($slug)/solution-design.md"])
       | map(if type == "string" then {path: ., name: ($docs[.] // error("stamp of an absent path"))}
             else {path, name: .doc} end)) as $stamps
    | {path: $path,
       text: ("---\nstamps:\n"
         + ($stamps | map("  - path: \(.path)\n    blob: {{name:\(.name)}}\n") | add)
         + "verdict: \(.verdict // "pass")\nopen:\n  critical: \($open.critical)\n"
         + "  high: \($open.high)\n  medium: \($open.medium)\n  low: \($open.low)\n"
         + "rounds: \(.rounds // 2)\n"
         + "clean_round: \(if has("clean_round") then .clean_round else true end)\n---\n\n"
         + "# Design review record\n\n## Reviewed documents\n\n- The PRD and the solution design.\n\n"
         + "## Rounds\n\n### Round 1\n\nOne pass.\n\n### Round 2\n\nA confirming pass.\n\n"
         + "## Findings\n\n| ID | Round | Angle | Severity | Disposition | Note |\n"
         + "|---|---|---|---|---|---|\n| F1 | 1 | A | low | fixed | A typo. |\n")}
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
  else error("unknown object type") end;
. as $case
| (if $which == "trunk" then $case.trunk
   else {docs: (($case.trunk.docs // {}) + ($case.docs.docs // {})),
         records: (if ($case.docs | has("records")) then $case.docs.records
                   else ($case.trunk.records // []) end),
         objects: ($case.docs.objects // [])} end) as $spec
| ($spec.docs // {} | with_entries(select(.value != null))) as $docs
| ([$docs | to_entries[]
    | {path: .key, mode: "100644", text: ($names[0][.value] // error("unknown document name"))}]
   + [($spec.records // [])[] | record_text($docs) | {path, mode: "100644", text}]) as $entries
| reduce ($spec.objects // [])[] as $object ($entries; apply_object($object))
| .[]
| if .gitlink then "gitlink\t160000\t\(.path)\t-"
  else "entry\t\(.mode)\t\(.path)\t\(.text | @base64)" end'

# render_names <var> <bytes>: assigns <bytes> with every `{{name:<key>}}` placeholder rendered to
# <var>.
render_names() {
  local rendered="$2" doc_name
  for doc_name in "${!NAME_BLOBS[@]}"; do
    rendered="${rendered//"{{name:$doc_name}}"/${NAME_BLOBS[$doc_name]}}"
  done
  case "$rendered" in
    *'{{'*) setup_fail "unrendered placeholder in a case document" ;;
  esac
  printf -v "$1" '%s' "$rendered"
}

# build_spec_commit <var> <case-file> <trunk|docs> [<parent>]: builds the case's trunk or docs
# tree as a commit, with <parent> when given, and assigns its id to <var>.
build_spec_commit() {
  local var="$1" plan_file="$TMPDIR_TEST/plan.$1" index_file="$TMPDIR_TEST/index.$1"
  local kind mode path encoded oid text tree_id commit_id index_info=""
  local -a parent_args=()
  if [ -n "${4-}" ]; then
    parent_args=(-p "$4")
  fi
  jq -r --arg which "$3" --slurpfile names "$DOCS" "$SPEC_PLAN_JQ" "$2" >"$plan_file" \
    || setup_fail "spec plan $3 of $2"
  while IFS=$'\t' read -r kind mode path encoded; do
    case "$kind" in
      gitlink) index_info+="$mode $GITLINK_COMMIT"$'\t'"$path"$'\n' ;;
      entry)
        decode_text text "$encoded"
        render_names text "$text"
        store_blob oid "$text"
        index_info+="$mode $oid"$'\t'"$path"$'\n'
        ;;
      *) setup_fail "spec plan line kind $kind" ;;
    esac
  done <"$plan_file"
  rm -f "$index_file"
  printf '%s' "$index_info" | GIT_INDEX_FILE="$index_file" rgit update-index --index-info \
    || setup_fail "update-index for $var"
  tree_id="$(GIT_INDEX_FILE="$index_file" rgit write-tree)" || setup_fail "write-tree for $var"
  commit_id="$(rgit commit-tree "$tree_id" "${parent_args[@]}" -m "$var" </dev/null)" \
    || setup_fail "commit-tree for $var"
  printf -v "$var" '%s' "$commit_id"
}

# ── Case evidence ───────────────────────────────────────────────────────────────────
#
# EVIDENCE_JQ expands a case's shorthand evidence to evidence JSON v1: defaults fill every key, a
# seed defaults to issue 1 with the demo marker and a CRLF body, a pull request to an open
# same-repository `docs/demo` pull request by a writer, a branch to an unused one, a slice to an
# open slice under issue 1 whose labels hold every rating family (`rated` false keeps only the
# type, `labels` replaces them), with no blocked-by edge, no ready event and no edit, and the epic
# to issue 1, labeled `type:epic`, with one sub-issue per slice. A ready event defaults to a User
# writer.

# shellcheck disable=SC2016
EVIDENCE_JQ='
def default($key; $value): if has($key) then .[$key] else $value end;
def seed_full:
  {number, state: default("state"; "OPEN"), author_can_write: default("author_can_write"; true),
   body: default("body"; "<!-- hivemind-initiative: demo -->\r\nSeed issue.\n")};
def pull_request_full:
  {number, head_ref: default("head_ref"; "docs/demo"), head_oid: default("head_oid"; "{{docs}}"),
   head_repository: default("head_repository"; "acme/widgets"),
   author_can_write: default("author_can_write"; true), draft: default("draft"; false)};
def branch_full:
  {name, oid: default("oid"; "{{docs}}"), pull_request_count: default("pull_request_count"; 0)};
def rating_names($rated):
  if $rated then ["readiness:ready", "type:enhancement", "effort:s", "moscow:must", "priority:p1",
                  "risk:low", "difficulty:easy"]
  else ["type:enhancement"] end;
def ready_event_full:
  {actor: default("actor"; {login: "maintainer", __typename: "User"}),
   actor_can_write: default("actor_can_write"; true), created_at};
def slice_full:
  {readiness: ({number, state: default("state"; "OPEN"),
                body: default("body"; "## Acceptance Criteria\n\n- [ ] It works.\n"),
                labels: {nodes: (if has("labels") then .labels else rating_names(default("rated"; true)) end
                                 | map({name: .})),
                         pageInfo: {hasNextPage: default("labels_truncated"; false)}},
                blockedBy: {nodes: default("blocked_by"; [])}, subIssues: {totalCount: 0},
                parent: {number: 1, state: "OPEN", body: "<!-- hivemind-initiative: demo -->",
                         labels: {nodes: [{name: "type:epic"}]}}}
               + default("readiness_patch"; {})),
   last_edited_at: default("last_edited_at"; null),
   ready_events: (default("ready_events"; []) | map(ready_event_full)),
   renamed_at: default("renamed_at"; [])};
(.evidence // {}) as $evidence
| {version: ($evidence | default("version"; 1)),
   seeds: ($evidence | default("seeds"; [{number: 1}]) | map(seed_full)),
   pull_requests: ($evidence.pull_requests // [] | map(pull_request_full)),
   branches: ($evidence.branches // [] | map(branch_full)),
   epic: (if ($evidence | has("epic")) then $evidence.epic
          elif ($evidence.slices // [] | length) > 0 then
            {number: 1, state: "OPEN", sub_issue_total: ($evidence.slices | length),
             labels: {nodes: [{name: "type:epic"}], pageInfo: {hasNextPage: false}}}
          else null end),
   slices: ($evidence.slices // [] | map(slice_full))}'

# render_ids <var> <bytes> <trunk> <docs>: assigns <bytes> with the commit placeholders rendered to
# <var>: `{{trunk}}`, `{{docs}}`, `{{short}}` (the trunk's 7-hex prefix), `{{upper}}` (the trunk in
# capitals) and `{{unfetched}}` (a well-formed id of no object in the repository).
render_ids() {
  local rendered="$2" upper
  upper="$(printf '%s' "$3" | tr 'abcdef' 'ABCDEF')" || setup_fail "tr"
  rendered="${rendered//"{{trunk}}"/$3}"
  rendered="${rendered//"{{short}}"/${3:0:7}}"
  rendered="${rendered//"{{upper}}"/$upper}"
  rendered="${rendered//"{{unfetched}}"/$UNFETCHED}"
  if [ -n "$4" ]; then
    rendered="${rendered//"{{docs}}"/$4}"
  fi
  case "$rendered" in
    *'{{'*) setup_fail "unrendered placeholder in case evidence or arguments" ;;
  esac
  printf -v "$1" '%s' "$rendered"
}

# ── Sections ───────────────────────────────────────────────────────────────────────

test_library_form() {
  if [ "$(head -n 1 "$SD_LIB")" = '# shellcheck shell=bash' ]; then
    pass "form:line-1" "shellcheck directive, no shebang"
  else
    failed "form:line-1" "line 1 is not '# shellcheck shell=bash'"
  fi
  if grep -q 'BASH_SOURCE' "$SD_LIB"; then
    failed "form:no-bash-source" "BASH_SOURCE appears in the library"
  else
    pass "form:no-bash-source" "absent"
  fi
  if grep -Eq '^[[:space:]]*(\.|source)[[:space:]]+["$/~]' "$SD_LIB"; then
    failed "form:sources-nothing" "the library sources a file"
  else
    pass "form:sources-nothing" "no source statement"
  fi
  if grep -q '^# P18 FLOOR EXCEPTION (ADR-0020)' "$SD_LIB"; then
    pass "form:p18-marker" "marker in the leading header"
  else
    failed "form:p18-marker" "P18 FLOOR EXCEPTION marker missing"
  fi
  local gh_lines want_gh_lines
  gh_lines="$(grep -E '^[^#]*\bgh (api|pr|issue|search|repo)' "$SD_LIB" | sed 's/^[[:space:]]*//')"
  # shellcheck disable=SC2016
  want_gh_lines='gh api graphql "$@" </dev/null 2>/dev/null || gh_rc=$?'$'\n'
  # shellcheck disable=SC2016
  want_gh_lines+='gh api "repos/$1/collaborators/$2/permission" </dev/null 2>/dev/null || gh_rc=$?'
  if [ "$gh_lines" = "$want_gh_lines" ]; then
    pass "form:gh-calls" "only the evidence read's GraphQL and permission calls name gh"
  else
    failed "form:gh-calls" "gh command lines: $gh_lines"
  fi
  if bash -n "$SD_LIB"; then
    pass "form:syntax" "bash -n"
  else
    failed "form:syntax" "bash -n failed"
  fi
  local probe_out probe_status=0
  # shellcheck disable=SC2016
  probe_out="$(bash -c 'set -u
before_opts=""; after_opts=""; before_vars=""; after_vars=""
before_opts="$-:$SHELLOPTS:$BASHOPTS"; before_vars="$(compgen -v)"
. "$1"; . "$1"
after_opts="$-:$SHELLOPTS:$BASHOPTS"; after_vars="$(compgen -v)"
[ "$before_opts" = "$after_opts" ] || { echo options-changed; exit 1; }
[ "$before_vars" = "$after_vars" ] || { echo variables-changed; exit 1; }
echo unchanged' stage-form "$SD_LIB" 2>&1)" || probe_status=$?
  if [ "$probe_status" -eq 0 ] && [ "$probe_out" = unchanged ]; then
    pass "form:source-twice" "no output, no option or variable change"
  else
    failed "form:source-twice" "$probe_out"
  fi
}

# case_verdict <out-file> <expect-json> <trunk>: prints `ok` when <out-file> holds one compact
# output object with the expected values, else the first mismatch.
case_verdict() {
  jq -Rnr --argjson expect "$2" --arg trunk "$3" '
[inputs] as $lines
| if ($lines | length) != 1 then "\($lines | length) lines, want 1"
  else ($lines[0] | try fromjson catch null) as $out
  | if ($out | type) != "object" then "output does not parse"
    elif $lines[0] != ($out | tojson) then "output is not compact JSON"
    elif ($out | keys_unsorted)
         != ["slug", "trunk", "seed", "docs", "stage", "status", "next", "reasons", "ignored", "slices"]
    then "keys \($out | keys_unsorted | tojson)"
    elif $out.slug != "demo" or $out.trunk != $trunk then "slug or trunk \($lines[0])"
    elif ($out | {stage, status, next, reasons}) != ($expect | {stage, status, next, reasons})
    then "got \($out | {stage, status, next, reasons} | tojson)"
    elif $out.ignored != ($expect.ignored // []) then "ignored \($out.ignored | tojson)"
    elif ($expect | has("seed")) and $out.seed != $expect.seed then "seed \($out.seed)"
    elif ($expect | has("docs")) and $out.docs != $expect.docs then "docs \($out.docs | tojson)"
    elif ($expect | has("slices")) and $out.slices != $expect.slices then "slices \($out.slices | tojson)"
    else "ok" end
  end' <"$1" 2>&1
}

# expect_case_lacks <case> <case-file>: asserts the last call's stdout holds none of the case's
# `lacks` strings and its git log none of its `no_git_text`.
expect_case_lacks() {
  local text=""
  while IFS= read -r text; do
    if [ -n "$text" ] && grep -qF -- "$text" "$CALL_OUT"; then
      failed "$1:lacks" "stdout holds evidence text $text"
    elif [ -n "$text" ]; then
      pass "$1:lacks" "stdout holds no evidence text"
    fi
  done < <(jq -r '.lacks // [] | .[]' "$2")
  text="$(jq -r '.no_git_text // ""' "$2")" || setup_fail "case no_git_text"
  if [ -n "$text" ]; then
    if grep -qF -- "$text" "$GIT_LOG"; then
      failed "$1:no-git-text" "a git call names $text"
    else
      pass "$1:no-git-text" "no git call names it"
    fi
  fi
}

# run_case <index>: builds case <index>'s commits and evidence, runs derive and asserts its result.
run_case() {
  local index="$1" case_file="$TMPDIR_TEST/case.$1" input="$TMPDIR_TEST/input.case-$1"
  local case_name has_docs has_raw token no_git trunk_arg repo_arg trunk_name_arg slug_arg
  local trunk_commit docs_commit="" evidence expect verdict
  jq -c --argjson i "$index" '.[$i]' "$CASES" >"$case_file" || setup_fail "case file $index"
  {
    IFS= read -r case_name && IFS= read -r has_docs && IFS= read -r has_raw && IFS= read -r token \
      && IFS= read -r no_git && IFS= read -r trunk_arg && IFS= read -r repo_arg \
      && IFS= read -r trunk_name_arg && IFS= read -r slug_arg
  } < <(jq -r '.name, has("docs"), has("evidence_raw"), (.error // ""), (.no_git // false),
    (.trunk_arg // "{{trunk}}"), (.repo_arg // "acme/widgets"), (.trunk_name_arg // "main"),
    (.slug_arg // "demo")' "$case_file") || setup_fail "case fields $index"
  build_spec_commit trunk_commit "$case_file" trunk
  if [ "$has_docs" = true ]; then
    build_spec_commit docs_commit "$case_file" docs "$trunk_commit"
  fi
  if [ "$has_raw" = true ]; then
    jq -j '.evidence_raw' "$case_file" >"$input" || setup_fail "case raw evidence $index"
  else
    evidence="$(jq -c "$EVIDENCE_JQ" "$case_file")" || setup_fail "case evidence $index"
    render_ids evidence "$evidence" "$trunk_commit" "$docs_commit"
    printf '%s\n' "$evidence" >"$input" || setup_fail "case input $index"
  fi
  render_ids trunk_arg "$trunk_arg" "$trunk_commit" ""
  lib_call "case:$case_name" "$REPO" "$input" hivemind_stage_derive \
    "$trunk_arg" "$repo_arg" "$trunk_name_arg" "$slug_arg"
  if [ -n "$token" ]; then
    expect_call "case:$case_name" 2 "" "stage-derivation-error: $token"$'\n'
    if [ "$no_git" = true ]; then
      expect_no_git "case:$case_name"
    fi
  else
    expect="$(jq -c '.expect' "$case_file")" || setup_fail "case expect $index"
    render_ids expect "$expect" "$trunk_commit" "$docs_commit"
    verdict="$(case_verdict "$CALL_OUT" "$expect" "$trunk_commit")"
    if [ "$CALL_RC" != 0 ] || [ -s "$CALL_ERR" ]; then
      failed "case:$case_name" "rc $CALL_RC, stderr: $(cat "$CALL_ERR")"
    elif [ "$verdict" != ok ]; then
      failed "case:$case_name" "$verdict"
    else
      pass "case:$case_name" "stage, status, next and reasons match"
    fi
  fi
  if [ -s "$GIT_LOG" ]; then
    expect_git_flags "case:$case_name"
  fi
  expect_case_lacks "case:$case_name" "$case_file"
}

test_cases() {
  local count index
  count="$(jq 'length' "$CASES")" || setup_fail "cannot count cases"
  for ((index = 0; index < count; index++)); do
    run_case "$index"
  done
}

# HANDOFF_PREP_JQ fills a handoff case's defaults: a trunk where the docs are current (the PRD,
# the full solution design and a passing record), and per slice a body whose Design block links
# them and one `readiness:ready` labeled event by a User writer.

# shellcheck disable=SC2016
HANDOFF_PREP_JQ='
.trunk = (.trunk // {docs: {"docs/prds/demo.md": "prd", "docs/initiatives/demo/solution-design.md": "design-full"},
                     records: [{}]})
| .evidence = ((.evidence // {})
    | if has("slices") then
        .slices |= map({body: ("## What to build\n\nThe slice.\n\n## Acceptance Criteria\n\n- [ ] It works.\n\n"
                               + "## Design\n\n"
                               + "- Solution design: [docs/initiatives/demo/solution-design.md](docs/initiatives/demo/solution-design.md)\n"
                               + "- Heading: Readiness check\n"
                               + "- Review record: [docs/initiatives/demo/review-record.md](docs/initiatives/demo/review-record.md)\n"),
                        ready_events: [{created_at: "2026-02-01T00:00:00Z"}]} + .)
      else . end)'

# handoff_verdict <out-file> <expect-json> <trunk>: prints `ok` when <out-file> holds one compact
# handoff object with the expected values, else the first mismatch.
handoff_verdict() {
  jq -Rnr --argjson expect "$2" --arg trunk "$3" '
[inputs] as $lines
| if ($lines | length) != 1 then "\($lines | length) lines, want 1"
  else ($lines[0] | try fromjson catch null) as $out
  | if ($out | type) != "object" then "output does not parse"
    elif $lines[0] != ($out | tojson) then "output is not compact JSON"
    elif ($out | keys_unsorted) != ["slug", "commit", "result", "reasons", "slices", "ignored"]
    then "keys \($out | keys_unsorted | tojson)"
    elif $out.slug != "demo" or $out.commit != $trunk then "slug or commit \($lines[0])"
    elif ($out | {result, reasons}) != ($expect | {result, reasons})
    then "got \($out | {result, reasons} | tojson)"
    elif $out.slices != $expect.slices then "slices \($out.slices | tojson)"
    elif $out.ignored != ($expect.ignored // []) then "ignored \($out.ignored | tojson)"
    else "ok" end
  end' <"$1" 2>&1
}

# run_handoff_case <index>: builds handoff case <index>'s trunk commit and evidence, runs the
# handoff check and, when the case gives `derive`, derive on the same evidence, and asserts both.
run_handoff_case() {
  local index="$1" case_file="$TMPDIR_TEST/handoff.$1" input="$TMPDIR_TEST/input.handoff-$1"
  local case_name token no_git trunk_arg has_derive trunk_commit evidence expect verdict
  jq -c --argjson i "$index" ".[\$i] | $HANDOFF_PREP_JQ" "$HANDOFF_CASES" >"$case_file" \
    || setup_fail "handoff case file $index"
  {
    IFS= read -r case_name && IFS= read -r token && IFS= read -r no_git && IFS= read -r trunk_arg \
      && IFS= read -r has_derive
  } < <(jq -r '.name, (.error // ""), (.no_git // false), (.trunk_arg // "{{trunk}}"), has("derive")' \
    "$case_file") || setup_fail "handoff case fields $index"
  build_spec_commit trunk_commit "$case_file" trunk
  evidence="$(jq -c "$EVIDENCE_JQ" "$case_file")" || setup_fail "handoff case evidence $index"
  render_ids evidence "$evidence" "$trunk_commit" ""
  printf '%s\n' "$evidence" >"$input" || setup_fail "handoff case input $index"
  render_ids trunk_arg "$trunk_arg" "$trunk_commit" ""
  lib_call "handoff:$case_name" "$REPO" "$input" hivemind_stage_handoff "$trunk_arg" acme/widgets main demo
  if [ -n "$token" ]; then
    expect_call "handoff:$case_name" 2 "" "stage-derivation-error: $token"$'\n'
    if [ "$no_git" = true ]; then
      expect_no_git "handoff:$case_name"
    fi
  else
    expect="$(jq -c '.expect' "$case_file")" || setup_fail "handoff case expect $index"
    verdict="$(handoff_verdict "$CALL_OUT" "$expect" "$trunk_commit")"
    if [ "$CALL_RC" != 0 ] || [ -s "$CALL_ERR" ]; then
      failed "handoff:$case_name" "rc $CALL_RC, stderr: $(cat "$CALL_ERR")"
    elif [ "$verdict" != ok ]; then
      failed "handoff:$case_name" "$verdict"
    else
      pass "handoff:$case_name" "result, reasons and slices match"
    fi
  fi
  if [ -s "$GIT_LOG" ]; then
    expect_git_flags "handoff:$case_name"
  fi
  if [ "$has_derive" = true ]; then
    expect="$(jq -c '.derive + {ignored: (.expect.ignored // [])}' "$case_file")" \
      || setup_fail "handoff case derive $index"
    lib_call "handoff-derive:$case_name" "$REPO" "$input" hivemind_stage_derive "$trunk_arg" acme/widgets main demo
    verdict="$(case_verdict "$CALL_OUT" "$expect" "$trunk_commit")"
    if [ "$CALL_RC" != 0 ] || [ -s "$CALL_ERR" ]; then
      failed "handoff-derive:$case_name" "rc $CALL_RC, stderr: $(cat "$CALL_ERR")"
    elif [ "$verdict" != ok ]; then
      failed "handoff-derive:$case_name" "$verdict"
    else
      pass "handoff-derive:$case_name" "derive's row matches"
    fi
  fi
}

test_handoff_cases() {
  local count index
  count="$(jq 'length' "$HANDOFF_CASES")" || setup_fail "cannot count handoff cases"
  for ((index = 0; index < count; index++)); do
    run_handoff_case "$index"
  done
}

test_handoff_script_cases() {
  local evidence trunk_commit
  complete_trunk trunk_commit
  evidence="$(write_input handoff-arguments '{"version":1,"seeds":[],"pull_requests":[],"branches":[],"epic":null,"slices":[]}')"
  lib_call "handoff-arguments:none" "$REPO" "$evidence" hivemind_stage_handoff
  expect_call "handoff-arguments:none" 2 "" $'stage-derivation-error: usage\n'
  expect_no_git "handoff-arguments:none"
  lib_call "handoff-arguments:slug-path" "$REPO" "$evidence" hivemind_stage_handoff "$trunk_commit" acme/widgets main ../demo
  expect_call "handoff-arguments:slug-path" 2 "" $'stage-derivation-error: usage\n'
  expect_no_git "handoff-arguments:slug-path"
  CALL_LIBS=("$RC_LIB" "$SD_LIB")
  lib_call "handoff-missing-library:no-verify" "$REPO" "$evidence" hivemind_stage_handoff "$trunk_commit" acme/widgets main demo
  expect_call "handoff-missing-library:no-verify" 2 "" $'stage-derivation-error: missing-library\n'
  expect_no_git "handoff-missing-library:no-verify"
  CALL_LIBS=("$RC_LIB" "$RV_LIB" "$SD_LIB")
}

# complete_trunk <var>: builds the trunk commit of the cases file's trunk-current-no-slices case
# and assigns its id to <var>.
complete_trunk() {
  local case_file="$TMPDIR_TEST/case.complete"
  jq -c '.[] | select(.name == "trunk-current-no-slices")' "$CASES" >"$case_file" \
    || setup_fail "complete trunk case"
  build_spec_commit "$1" "$case_file" trunk
}

test_arguments() {
  local evidence trunk_commit
  complete_trunk trunk_commit
  evidence="$(write_input arguments '{"version":1,"seeds":[],"pull_requests":[],"branches":[],"epic":null,"slices":[]}')"
  lib_call "arguments:none" "$REPO" "$evidence" hivemind_stage_derive
  expect_call "arguments:none" 2 "" $'stage-derivation-error: usage\n'
  expect_no_git "arguments:none"
  lib_call "arguments:five" "$REPO" "$evidence" hivemind_stage_derive "$trunk_commit" acme/widgets main demo extra
  expect_call "arguments:five" 2 "" $'stage-derivation-error: usage\n'
  expect_no_git "arguments:five"
  lib_call "arguments:sha256-shape" "$REPO" "$evidence" hivemind_stage_derive \
    "$trunk_commit${trunk_commit:0:24}" acme/widgets main demo
  expect_call "arguments:sha256-shape" 2 "" $'stage-derivation-error: commit-unresolvable\n'
}

test_missing_library() {
  local evidence trunk_commit
  complete_trunk trunk_commit
  evidence="$(write_input missing-library '{"version":1,"seeds":[],"pull_requests":[],"branches":[],"epic":null,"slices":[]}')"
  CALL_LIBS=("$SD_LIB")
  lib_call "missing-library:alone" "$REPO" "$evidence" hivemind_stage_derive "$trunk_commit" acme/widgets main demo
  expect_call "missing-library:alone" 2 "" $'stage-derivation-error: missing-library\n'
  expect_no_git "missing-library:alone"
  CALL_LIBS=("$RC_LIB" "$SD_LIB")
  lib_call "missing-library:no-verify" "$REPO" "$evidence" hivemind_stage_derive "$trunk_commit" acme/widgets main demo
  expect_call "missing-library:no-verify" 2 "" $'stage-derivation-error: missing-library\n'
  expect_no_git "missing-library:no-verify"
  CALL_LIBS=("$RC_LIB" "$RV_LIB" "$SD_LIB")
}

test_git_failure() {
  local evidence lost_commit tree_id case_file="$TMPDIR_TEST/case.git-failure"
  jq -nc '{name: "git-failure", trunk: {docs: {"docs/prds/demo.md": "prd-other"}}}' >"$case_file" \
    || setup_fail "git failure case"
  build_spec_commit lost_commit "$case_file" trunk
  tree_id="$(rgit rev-parse "$lost_commit^{tree}")" || setup_fail "rev-parse lost tree"
  rm -f "$(object_file "$tree_id")" || setup_fail "cannot delete tree object"
  evidence="$(write_input git-failure '{"version":1,"seeds":[],"pull_requests":[],"branches":[],"epic":null,"slices":[]}')"
  lib_call "git-failed:lost-tree" "$REPO" "$evidence" hivemind_stage_derive "$lost_commit" acme/widgets main demo
  expect_call "git-failed:lost-tree" 2 "" $'stage-derivation-error: git-failed\n'
}

test_subdirectory() {
  local evidence trunk_commit root_out
  complete_trunk trunk_commit
  evidence="$(write_input subdirectory '{"version":1,"seeds":[{"number":1,"state":"OPEN","author_can_write":true,"body":"<!-- hivemind-initiative: demo -->"}],"pull_requests":[],"branches":[],"epic":null,"slices":[]}')"
  lib_call "subdirectory:root" "$REPO" "$evidence" hivemind_stage_derive "$trunk_commit" acme/widgets main demo
  root_out="$(cat "$CALL_OUT")"
  lib_call "subdirectory:docs" "$REPO/docs/prds" "$evidence" hivemind_stage_derive "$trunk_commit" acme/widgets main demo
  if [ "$CALL_RC" = 0 ] && [ -n "$root_out" ] && file_is "$CALL_OUT" "$root_out"$'\n' \
    && [[ "$root_out" == *'"stage":"docs-pull-request"'* ]]; then
    pass "subdirectory:same-result" "a subdirectory working directory derives the same stage"
  else
    failed "subdirectory:same-result" "root: $root_out, subdirectory: $(cat "$CALL_OUT")"
  fi
}

test_no_gh() {
  if [ -s "$GH_LOG" ]; then
    failed "no-gh" "gh ran: $(head -n 1 "$GH_LOG")"
  else
    pass "no-gh" "no case called gh"
  fi
}

# ── Evidence read (gh mode) ─────────────────────────────────────────────────────────
#
# gh-cases.json holds `base`, the canned replies of one full read, `cases`, each run with
# hivemind_stage_evidence_gh against the base replies with its own `replies` and `patch` applied,
# and `pipes`, recorded fixtures whose evidence is served as gh replies and read back. A reply is
# `json` (its body, one line) or `raw` text, with `rc` gh's exit status, 0 by default. Its key names
# the call: seeds, pull-requests, refs, epic:<n>, snapshot:<n>, timeline:<n> or permission:<login>.
# The GraphQL queries below are pinned: a call whose argv differs in any byte finds no route.

# shellcheck disable=SC2016
Q_SEEDS='query($q:String!){search(query:$q,type:ISSUE,first:100){pageInfo{hasNextPage} nodes{... on Issue{number state body author{login __typename}}}}}'
# shellcheck disable=SC2016
Q_PULL_REQUESTS='query($q:String!){search(query:$q,type:ISSUE,first:100){pageInfo{hasNextPage} nodes{... on PullRequest{number headRefName headRefOid isDraft headRepository{nameWithOwner} author{login __typename}}}}}'
# shellcheck disable=SC2016
Q_REFS='query($owner:String!,$name:String!,$q:String!){repository(owner:$owner,name:$name){refs(refPrefix:"refs/heads/",query:$q,first:100){pageInfo{hasNextPage} nodes{name target{oid} associatedPullRequests(states:[OPEN,CLOSED,MERGED]){totalCount}}}}}'
# shellcheck disable=SC2016
Q_EPIC='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){number state labels(first:100){pageInfo{hasNextPage} nodes{name}} subIssues(first:100){totalCount pageInfo{hasNextPage} nodes{number}}}}}'
# shellcheck disable=SC2016
Q_TIMELINE='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){number lastEditedAt labeled:timelineItems(itemTypes:[LABELED_EVENT],first:100){pageInfo{hasNextPage} nodes{... on LabeledEvent{createdAt label{name} actor{login __typename}}}} renamed:timelineItems(itemTypes:[RENAMED_TITLE_EVENT],first:100){pageInfo{hasNextPage} nodes{... on RenamedTitleEvent{createdAt}}}}}}'
# shellcheck disable=SC2016
Q_SNAPSHOT='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){number state body labels(first:100){pageInfo{hasNextPage} nodes{name}} blockedBy(first:100){pageInfo{hasNextPage} nodes{number state}} subIssues(first:100){totalCount pageInfo{hasNextPage}} parent{number state body labels(first:100){pageInfo{hasNextPage} nodes{name}}}}}}'
SERVE_N=0

jq -e 'type == "object" and (keys == ["base", "cases", "pipes"]) and (.base | type == "object")
  and (.cases | type == "array" and length > 0)
  and all(.cases[]; (.name | type) == "string" and (.calls | type) == "array"
    and ([has("expect"), has("checks"), has("error")] | map(select(.)) | length) == 1
    and (keys - ["args", "calls", "checks", "error", "expect", "gh", "libs", "name", "patch", "replies"] == []))
  and (.pipes | type == "array" and length > 0)
  and all(.pipes[]; (.name | type) == "string" and (.fixture == "cases" or .fixture == "handoff"))' \
  "$GH_CASES" >/dev/null 2>&1 || setup_fail "gh cases file missing or off its shape: $GH_CASES"

# shellcheck disable=SC2016
ROUTE_LINES_JQ='to_entries[]
| "\(.key)\t\(.value.rc // 0)\t\(.value | if has("raw") then .raw else (.json | tojson) + "\n" end | @base64)"'

# EVIDENCE_GH_JQ turns expanded evidence JSON v1 into the replies gh would give for it: each seed's
# author is the User `seed-author-<n>` and each pull request's `pr-author-<n>`, each a writer per
# its author_can_write, and each ready event's actor a writer per its actor_can_write. A null epic,
# which a recorded fixture gives when it has no slice, becomes an epic with no sub-issue for each
# seed, as gh mode reads the resolved seed's epic.
# shellcheck disable=SC2016
EVIDENCE_GH_JQ='
def page($nodes): {pageInfo: {hasNextPage: false}, nodes: $nodes};
def paged: if has("pageInfo") then . else .pageInfo = {hasNextPage: false} end;
def reply($data): {json: {data: $data}};
def permission($writer): {json: {permission: (if $writer then "write" else "read" end)}};
. as $ev
| {seeds: reply({search: page([$ev.seeds[]
     | {number, state, body, author: {login: "seed-author-\(.number)", __typename: "User"}}])}),
   "pull-requests": reply({search: page([$ev.pull_requests[]
     | {number, headRefName: .head_ref, headRefOid: .head_oid, isDraft: .draft,
        headRepository: (if .head_repository == null then null else {nameWithOwner: .head_repository} end),
        author: {login: "pr-author-\(.number)", __typename: "User"}}])}),
   refs: reply({repository: {refs: page([$ev.branches[]
     | {name, target: {oid}, associatedPullRequests: {totalCount: .pull_request_count}}])}})}
+ ([$ev.seeds[] | {key: "permission:seed-author-\(.number)", value: permission(.author_can_write)}]
   | from_entries)
+ ([$ev.pull_requests[] | {key: "permission:pr-author-\(.number)", value: permission(.author_can_write)}]
   | from_entries)
+ (if $ev.epic == null then
     [$ev.seeds[] | {key: "epic:\(.number)", value: reply({repository: {issue: {number, state,
        labels: page([{name: "type:epic"}]), subIssues: ({totalCount: 0} + page([]))}}})}] | from_entries
   else {"epic:\($ev.epic.number)": reply({repository: {issue: {number: $ev.epic.number,
           state: $ev.epic.state, labels: $ev.epic.labels,
           subIssues: {totalCount: $ev.epic.sub_issue_total, pageInfo: {hasNextPage: false},
                       nodes: [$ev.slices[] | {number: .readiness.number}]}}}})} end)
+ ([$ev.slices[] | {key: "snapshot:\(.readiness.number)",
     value: reply({repository: {issue: (.readiness | .labels |= paged | .blockedBy |= paged
       | .subIssues |= paged | if .parent == null then . else .parent.labels |= paged end)}})}]
   | from_entries)
+ ([$ev.slices[] | {key: "timeline:\(.readiness.number)",
     value: reply({repository: {issue: {number: .readiness.number, lastEditedAt: .last_edited_at,
       labeled: page([.ready_events[] | {createdAt: .created_at, label: {name: "readiness:ready"}, actor}]),
       renamed: page([.renamed_at[] | {createdAt: .}])}}})}]
   | from_entries)
+ ([$ev.slices[].ready_events[] | select(.actor != null)
    | {key: "permission:\(.actor.login)", value: permission(.actor_can_write)}] | from_entries)'

# route_argv <key> <owner/repo> <slug>: prints the gh argv record, as the stub logs it, of the call
# whose reply key is <key>.
route_argv() {
  local key="$1" owner_repo="$2" slug="$3" owner="${2%%/*}" name="${2#*/}"
  case "$key" in
    seeds)
      printf '<api><graphql><-f><query=%s><-f><q=repo:%s is:issue in:body "hivemind-initiative: %s">' \
        "$Q_SEEDS" "$owner_repo" "$slug"
      ;;
    pull-requests)
      printf '<api><graphql><-f><query=%s><-f><q=repo:%s is:pr is:open head:docs/%s>' \
        "$Q_PULL_REQUESTS" "$owner_repo" "$slug"
      ;;
    refs)
      printf '<api><graphql><-f><query=%s><-f><owner=%s><-f><name=%s><-f><q=docs/%s>' \
        "$Q_REFS" "$owner" "$name" "$slug"
      ;;
    epic:*)
      printf '<api><graphql><-f><query=%s><-f><owner=%s><-f><name=%s><-F><number=%s>' \
        "$Q_EPIC" "$owner" "$name" "${key#epic:}"
      ;;
    snapshot:*)
      printf '<api><graphql><-f><query=%s><-f><owner=%s><-f><name=%s><-F><number=%s>' \
        "$Q_SNAPSHOT" "$owner" "$name" "${key#snapshot:}"
      ;;
    timeline:*)
      printf '<api><graphql><-f><query=%s><-f><owner=%s><-f><name=%s><-F><number=%s>' \
        "$Q_TIMELINE" "$owner" "$name" "${key#timeline:}"
      ;;
    permission:*)
      printf '<api><repos/%s/collaborators/%s/permission>' "$owner_repo" "${key#permission:}"
      ;;
    *) setup_fail "unknown gh reply key $key" ;;
  esac
}

# serve_replies <replies-file> <owner/repo> <slug>: points GH_SERVE_DIR at a new serve dir and
# writes each reply of the JSON object in <replies-file> into it as the route of its call's argv.
serve_replies() {
  local key status encoded argv route_id body
  SERVE_N=$((SERVE_N + 1))
  GH_SERVE_DIR="$TMPDIR_TEST/gh-serve.$SERVE_N"
  mkdir "$GH_SERVE_DIR" || setup_fail "cannot create the gh serve dir"
  while IFS=$'\t' read -r key status encoded; do
    argv="$(route_argv "$key" "$2" "$3")"
    route_id="$(printf '%s' "$argv" | cksum | cut -d ' ' -f 1)" || setup_fail "cksum"
    [ ! -e "$GH_SERVE_DIR/$route_id.key" ] || setup_fail "gh route id collision for $key"
    decode_text body "$encoded"
    { printf '%s' "$argv" >"$GH_SERVE_DIR/$route_id.key" \
      && printf '%s' "$body" >"$GH_SERVE_DIR/$route_id.body" \
      && printf '%s\n' "$status" >"$GH_SERVE_DIR/$route_id.rc"; } || setup_fail "gh route $key"
  done < <(jq -r "$ROUTE_LINES_JQ" "$1")
}

# gh_call <case> <fn> [arg...]: clears the gh log, then runs lib_call from the scratch repo root
# with no stdin.
gh_call() {
  local case_name="$1"
  shift
  : >"$GH_LOG"
  lib_call "$case_name" "$REPO" "$NO_INPUT" "$@"
}

# expect_gh_calls <case> <owner/repo> <slug> <key>...: asserts the gh log holds, for each of the two
# shell-mode runs, exactly the calls named by <key>..., in order.
expect_gh_calls() {
  local case_name="$1" owner_repo="$2" slug="$3" per_run="" key
  shift 3
  for key in "$@"; do
    per_run+="$(route_argv "$key" "$owner_repo" "$slug")"$'\n'
  done
  if file_is "$GH_LOG" "$per_run$per_run"; then
    pass "$case_name:gh-calls" "$# gh calls per run, in order"
  else
    failed "$case_name:gh-calls" "gh log: $(cat "$GH_LOG")"
  fi
}

# gh_evidence_verdict <out-file> <expect> <checks> <replies>: prints `ok` when <out-file> holds one
# compact evidence object equal to <expect> (a `{"$reply": <key>}` value stands for that reply's
# issue node) when it is not null, and holding each check's value at its path; else the mismatch.
gh_evidence_verdict() {
  jq -Rnr --argjson expect "$2" --argjson checks "$3" --argjson replies "$4" '
[inputs] as $lines
| if ($lines | length) != 1 then "\($lines | length) lines, want 1"
  else ($lines[0] | try fromjson catch null) as $out
  | if ($out | type) != "object" then "output does not parse"
    elif $lines[0] != ($out | tojson) then "output is not compact JSON"
    elif ($out | keys_unsorted) != ["version", "seeds", "pull_requests", "branches", "epic", "slices"]
    then "keys \($out | keys_unsorted | tojson)"
    elif $expect != null
      and $out != ($expect | walk(if type == "object" and has("$reply")
                                  then $replies[.["$reply"]].json.data.repository.issue else . end))
    then "evidence \($lines[0])"
    else [$checks[] | .path as $path | select(($out | getpath($path)) != .value)
          | "at \($path | tojson): \($out | getpath($path) | tojson)"]
      | if length == 0 then "ok" else .[0] end end
  end' <"$1" 2>&1
}

# run_gh_case <index>: serves gh case <index>'s replies, runs the evidence read and asserts its
# result and its gh calls.
run_gh_case() {
  local index="$1" case_name token has_gh libs replies_file="$TMPDIR_TEST/gh-replies.$1"
  local expect checks replies verdict call_repo=acme/widgets call_slug=demo
  local -a args=() calls=()
  jq -c --argjson i "$index" '.base as $base | .cases[$i] as $case
    | ($base + ($case.replies // {})) | with_entries(select(.value != null))
    | reduce ($case.patch // [])[] as $p (.; .[$p.reply].json |= setpath($p.path; $p.value))' \
    "$GH_CASES" >"$replies_file" || setup_fail "gh case replies $index"
  {
    IFS= read -r case_name && IFS= read -r token && IFS= read -r has_gh && IFS= read -r libs
  } < <(jq -r --argjson i "$index" '.cases[$i] | .name, (.error // ""), (if has("gh") then .gh else true end), (.libs // "all")' \
    "$GH_CASES") || setup_fail "gh case fields $index"
  mapfile -t args < <(jq -r --argjson i "$index" '.cases[$i] | .args // ["acme/widgets", "demo"] | .[]' "$GH_CASES")
  mapfile -t calls < <(jq -r --argjson i "$index" '.cases[$i].calls[]' "$GH_CASES")
  if [ "${#args[@]}" -eq 2 ]; then
    call_repo="${args[0]}"
    call_slug="${args[1]}"
  fi
  serve_replies "$replies_file" "$call_repo" "$call_slug"
  if [ "$has_gh" = false ]; then
    CALL_PATH="$NO_GH_DIR"
  fi
  if [ "$libs" = stage-only ]; then
    CALL_LIBS=("$SD_LIB")
  fi
  gh_call "gh:$case_name" hivemind_stage_evidence_gh "${args[@]}"
  CALL_PATH="$LIB_PATH"
  CALL_LIBS=("$RC_LIB" "$RV_LIB" "$SD_LIB")
  if [ -n "$token" ]; then
    expect_call "gh:$case_name" 2 "" "stage-derivation-error: $token"$'\n'
  else
    expect="$(jq -c --argjson i "$index" '.cases[$i].expect // null' "$GH_CASES")" || setup_fail "gh expect $index"
    checks="$(jq -c --argjson i "$index" '.cases[$i].checks // []' "$GH_CASES")" || setup_fail "gh checks $index"
    replies="$(cat "$replies_file")" || setup_fail "gh replies $index"
    verdict="$(gh_evidence_verdict "$CALL_OUT" "$expect" "$checks" "$replies")"
    if [ "$CALL_RC" != 0 ] || [ -s "$CALL_ERR" ]; then
      failed "gh:$case_name" "rc $CALL_RC, stderr: $(cat "$CALL_ERR")"
    elif [ "$verdict" != ok ]; then
      failed "gh:$case_name" "$verdict"
    else
      pass "gh:$case_name" "evidence matches"
    fi
  fi
  expect_gh_calls "gh:$case_name" "$call_repo" "$call_slug" "${calls[@]}"
  expect_no_git "gh:$case_name"
}

test_gh_cases() {
  local count index
  count="$(jq '.cases | length' "$GH_CASES")" || setup_fail "cannot count gh cases"
  for ((index = 0; index < count; index++)); do
    run_gh_case "$index"
  done
}

# pipe_fixture_file <name> <cases|handoff> <out-file>: writes the named recorded fixture, a handoff
# one with its handoff defaults, to <out-file>.
pipe_fixture_file() {
  if [ "$2" = handoff ]; then
    jq -c --arg name "$1" "first(.[] | select(.name == \$name)) | $HANDOFF_PREP_JQ" "$HANDOFF_CASES" >"$3"
  else
    jq -c --arg name "$1" 'first(.[] | select(.name == $name))' "$CASES" >"$3"
  fi
  [ -s "$3" ] || setup_fail "pipe fixture $2:$1 not found"
}

# expect_derive_matches <case> <fixture-file> <cases|handoff> <trunk> <docs> <evidence-file>: runs
# derive, and for a handoff fixture the handoff check, on <evidence-file> and asserts the fixture's
# expectations, with no gh call.
expect_derive_matches() {
  local case_name="$1" case_file="$2" kind="$3" trunk_commit="$4" docs_commit="$5" input="$6"
  local expect verdict has_derive=true
  if [ "$kind" = handoff ]; then
    has_derive="$(jq -r 'has("derive")' "$case_file")" || setup_fail "pipe derive $case_name"
    : >"$GH_LOG"
    lib_call "$case_name:handoff" "$REPO" "$input" hivemind_stage_handoff "$trunk_commit" acme/widgets main demo
    expect="$(jq -c '.expect' "$case_file")" || setup_fail "pipe handoff expect $case_name"
    verdict="$(handoff_verdict "$CALL_OUT" "$expect" "$trunk_commit")"
    if [ "$CALL_RC" = 0 ] && [ ! -s "$CALL_ERR" ] && [ "$verdict" = ok ] && [ ! -s "$GH_LOG" ]; then
      pass "$case_name:handoff" "the handoff check on gh evidence matches the fixture"
    else
      failed "$case_name:handoff" "rc $CALL_RC, $verdict, stderr: $(cat "$CALL_ERR")"
    fi
    expect="$(jq -c '.derive + {ignored: (.expect.ignored // [])}' "$case_file")" \
      || setup_fail "pipe derive expect $case_name"
  else
    expect="$(jq -c '.expect' "$case_file")" || setup_fail "pipe expect $case_name"
    render_ids expect "$expect" "$trunk_commit" "$docs_commit"
  fi
  if [ "$has_derive" != true ]; then
    return 0
  fi
  : >"$GH_LOG"
  lib_call "$case_name:derive" "$REPO" "$input" hivemind_stage_derive "$trunk_commit" acme/widgets main demo
  verdict="$(case_verdict "$CALL_OUT" "$expect" "$trunk_commit")"
  if [ "$CALL_RC" = 0 ] && [ ! -s "$CALL_ERR" ] && [ "$verdict" = ok ] && [ ! -s "$GH_LOG" ]; then
    pass "$case_name:derive" "derive on gh evidence gives the fixture's stage"
  else
    failed "$case_name:derive" "rc $CALL_RC, $verdict, stderr: $(cat "$CALL_ERR")"
  fi
}

# run_gh_pipe <index>: serves pipe <index>'s fixture evidence as gh replies, reads it back with the
# evidence read and asserts derive on it gives the fixture's result.
run_gh_pipe() {
  local index="$1" name kind case_file="$TMPDIR_TEST/pipe.$1" replies_file="$TMPDIR_TEST/pipe-replies.$1"
  local input="$TMPDIR_TEST/input.pipe-$1" trunk_commit docs_commit="" evidence
  {
    IFS= read -r name && IFS= read -r kind
  } < <(jq -r --argjson i "$index" '.pipes[$i] | .name, .fixture' "$GH_CASES") || setup_fail "pipe fields $index"
  pipe_fixture_file "$name" "$kind" "$case_file"
  build_spec_commit trunk_commit "$case_file" trunk
  if [ "$(jq -r 'has("docs")' "$case_file")" = true ]; then
    build_spec_commit docs_commit "$case_file" docs "$trunk_commit"
  fi
  evidence="$(jq -c "$EVIDENCE_JQ" "$case_file")" || setup_fail "pipe evidence $name"
  render_ids evidence "$evidence" "$trunk_commit" "$docs_commit"
  printf '%s\n' "$evidence" | jq -c "$EVIDENCE_GH_JQ" >"$replies_file" || setup_fail "pipe replies $name"
  serve_replies "$replies_file" acme/widgets demo
  gh_call "gh-pipe:$kind:$name" hivemind_stage_evidence_gh acme/widgets demo
  if [ "$CALL_RC" != 0 ] || [ -s "$CALL_ERR" ]; then
    failed "gh-pipe:$kind:$name" "rc $CALL_RC, stderr: $(cat "$CALL_ERR")"
    return 0
  fi
  pass "gh-pipe:$kind:$name" "the evidence read succeeds"
  cp "$CALL_OUT" "$input" || setup_fail "pipe input $name"
  expect_derive_matches "gh-pipe:$kind:$name" "$case_file" "$kind" "$trunk_commit" "$docs_commit" "$input"
}

test_gh_pipes() {
  local count index
  count="$(jq '.pipes | length' "$GH_CASES")" || setup_fail "cannot count pipes"
  for ((index = 0; index < count; index++)); do
    run_gh_pipe "$index"
  done
}

test_library_form
test_cases
test_handoff_cases
test_handoff_script_cases
test_arguments
test_missing_library
test_git_failure
test_subdirectory
test_no_gh
test_gh_cases
test_gh_pipes

# ── Summary ───────────────────────────────────────────────────────────────────────
echo
echo "stage-derivation: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
