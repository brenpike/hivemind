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
# beside it logs every gh argv and exits 1; the suite fails when any case called it.
#
# Fixture data lives in tests/stage-derivation/cases.json and docs.json;
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

for required_file in "$RC_LIB" "$RV_LIB" "$SD_LIB" "$CASES" "$DOCS"; do
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
mkdir -p "$WRAP_DIR" || { echo "FAIL: cannot create wrapper dir" >&2; exit 2; }
: >"$GH_LOG" || { echo "FAIL: cannot create the gh log" >&2; exit 2; }
printf '%s\n' '#!/bin/sh' \
  'printf "%s\n" "$*" >>"$SD_TEST_GIT_LOG"' \
  'exec "$SD_TEST_REAL_GIT" "$@"' >"$WRAP_DIR/git" \
  && chmod +x "$WRAP_DIR/git" \
  || { echo "FAIL: cannot write the recording git wrapper" >&2; exit 2; }
printf '%s\n' '#!/bin/sh' \
  'printf "%s\n" "$*" >>"$SD_TEST_GH_LOG"' \
  'exit 1' >"$WRAP_DIR/gh" \
  && chmod +x "$WRAP_DIR/gh" \
  || { echo "FAIL: cannot write the recording gh stub" >&2; exit 2; }
LIB_PATH="$WRAP_DIR:$PATH"

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
# then runs one library call, in a fresh bash under <prelude> with PATH set to LIB_PATH; prints
# its exit status.
run_lib_mode() {
  local prelude="$1" cwd="$2" in_file="$3" out_file="$4" err_file="$5" status=0
  shift 5
  (
    cd "$cwd" || exit 97
    PATH="$LIB_PATH" SD_TEST_GIT_LOG="$GIT_LOG" SD_TEST_REAL_GIT="$REAL_GIT" SD_TEST_GH_LOG="$GH_LOG" \
      bash -c "$prelude"'; while [ "$1" != -- ]; do . "$1"; shift; done; shift; "$@"' \
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
# type), and the epic to issue 1 with one sub-issue per slice.

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
def rating_labels($rated):
  (if $rated then ["readiness:ready", "type:enhancement", "effort:s", "moscow:must", "priority:p1",
                   "risk:low", "difficulty:easy"]
   else ["type:enhancement"] end)
  | map({name: .});
def slice_full:
  {readiness: {number, state: default("state"; "OPEN"),
               body: "## Acceptance Criteria\n\n- [ ] It works.\n",
               labels: {nodes: rating_labels(default("rated"; true)),
                        pageInfo: {hasNextPage: default("labels_truncated"; false)}},
               blockedBy: {nodes: []}, subIssues: {totalCount: 0},
               parent: {number: 1, state: "OPEN", body: "<!-- hivemind-initiative: demo -->",
                        labels: {nodes: [{name: "type:epic"}]}}},
   last_edited_at: default("last_edited_at"; null), ready_events: [],
   renamed_at: default("renamed_at"; [])};
(.evidence // {}) as $evidence
| {version: ($evidence | default("version"; 1)),
   seeds: ($evidence | default("seeds"; [{number: 1}]) | map(seed_full)),
   pull_requests: ($evidence.pull_requests // [] | map(pull_request_full)),
   branches: ($evidence.branches // [] | map(branch_full)),
   epic: (if ($evidence | has("epic")) then $evidence.epic
          elif ($evidence.slices // [] | length) > 0 then
            {number: 1, state: "OPEN", sub_issue_total: ($evidence.slices | length)}
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
  if grep -Eq '^[^#]*\bgh (api|pr|issue|search|repo)' "$SD_LIB"; then
    failed "form:no-gh" "the library names a gh command outside comments"
  else
    pass "form:no-gh" "no gh command"
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

test_library_form
test_cases
test_arguments
test_missing_library
test_git_failure
test_subdirectory
test_no_gh

# ── Summary ───────────────────────────────────────────────────────────────────────
echo
echo "stage-derivation: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
