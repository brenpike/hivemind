#!/usr/bin/env bash
#
# Behavioral unit runner for the readiness check library:
#   plugin/skills/_shared/readiness-check.sh
#
# OFFLINE git/jq/bash TEST — needs only bash, git and jq (NO gh / network / auth). Every case
# sources the library in a fresh `bash -c` twice, once under `set -euo pipefail` and once under
# `set -u` alone, and asserts both runs give identical stdout, stderr and exit status. Git
# fixtures are scratch repositories built with plumbing only, so every tree entry mode is exact
# (100644, 100755, 120000 symlink, 160000 gitlink, tree). A recording `git` wrapper shadowed on
# PATH logs each git argv the library runs, proving the "no git call" cases and the global git
# flags on every call. A recording `gh` stub beside it logs each gh argv and serves canned
# GraphQL responses from tests/readiness-check/gh-cases.json, so gh mode runs offline too.
#
# Sections are functions (test_<area>), so later steps add their own sections beside these.
# Mirrors tools/test_triage_ops.sh's pass/fail counter, exit 1 on any failure, exit 2 on set-up
# failure and scratch dir removed on EXIT. Read-only: the only writes are in the scratch dir.
#
# Usage:
#   ./tools/test_readiness_check.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
LIB="$REPO_ROOT/plugin/skills/_shared/readiness-check.sh"

[ -f "$LIB" ] || { echo "FAIL: library under test missing: $LIB" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this suite" >&2; exit 2; }
REAL_GIT="$(command -v git)" || { echo "FAIL: git is required to run this suite" >&2; exit 2; }

make_scratch_dir TMPDIR_TEST
trap 'rm -rf "$TMPDIR_TEST"' EXIT

export HOME="$TMPDIR_TEST/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=readiness-test GIT_AUTHOR_EMAIL=readiness-test@example.invalid
export GIT_COMMITTER_NAME=readiness-test GIT_COMMITTER_EMAIL=readiness-test@example.invalid
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
mkdir -p "$HOME" || { echo "FAIL: cannot create scratch HOME" >&2; exit 2; }

WRAP_DIR="$TMPDIR_TEST/wrap-bin"
GIT_LOG="$TMPDIR_TEST/git-calls.log"
mkdir -p "$WRAP_DIR" || { echo "FAIL: cannot create wrapper dir" >&2; exit 2; }
printf '%s\n' '#!/bin/sh' \
  'printf "%s\n" "$*" >>"$RC_TEST_GIT_LOG"' \
  'exec "$RC_TEST_REAL_GIT" "$@"' >"$WRAP_DIR/git" \
  && chmod +x "$WRAP_DIR/git" \
  || { echo "FAIL: cannot write the recording git wrapper" >&2; exit 2; }
GH_LOG="$TMPDIR_TEST/gh-calls.log"
GH_SERVE_DIR="$TMPDIR_TEST/gh-serve"
mkdir -p "$GH_SERVE_DIR" || { echo "FAIL: cannot create the gh serve dir" >&2; exit 2; }
# The recording gh stub logs each call's argv as one line of <arg> fields, then serves the canned
# body and exit status for the call's `number=` argv entry from RC_TEST_GH_DIR, else exits 1.
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' \
  'printf "<%s>" "$@" >>"$RC_TEST_GH_LOG"' \
  'printf "\n" >>"$RC_TEST_GH_LOG"' \
  'number=""' \
  'for arg in "$@"; do' \
  '  case "$arg" in number=*) number="${arg#number=}" ;; esac' \
  'done' \
  'if [ -n "${RC_TEST_GH_DIR-}" ] && [ -n "$number" ] && [ -f "$RC_TEST_GH_DIR/$number.rc" ]; then' \
  '  cat "$RC_TEST_GH_DIR/$number.body"' \
  '  exit "$(cat "$RC_TEST_GH_DIR/$number.rc")"' \
  'fi' \
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
NO_INPUT="$TMPDIR_TEST/empty-input"
: >"$NO_INPUT" || setup_fail "cannot create the empty input file"

# run_lib_mode <prelude> <cwd> <stdin-file> <out> <err> <fn> [arg...]: runs one library call in
# a fresh bash under <prelude> with PATH set to LIB_PATH; prints its exit status.
run_lib_mode() {
  local prelude="$1" cwd="$2" in_file="$3" out_file="$4" err_file="$5" status=0
  shift 5
  (
    cd "$cwd" || exit 97
    PATH="$LIB_PATH" RC_TEST_GIT_LOG="$GIT_LOG" RC_TEST_REAL_GIT="$REAL_GIT" \
      RC_TEST_GH_LOG="$GH_LOG" RC_TEST_GH_DIR="$GH_SERVE_DIR" \
      bash -c "$prelude"'; . "$1"; shift; "$@"' readiness-test "$LIB" "$@"
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

# commit_entries <var> <mode,oid,path>...: builds a tree from exactly these index entries in a
# fresh index and assigns a commit of it to <var>.
commit_entries() {
  local var="$1" entry tree_id commit_id index_file="$TMPDIR_TEST/index.$1"
  shift
  rm -f "$index_file"
  for entry in "$@"; do
    GIT_INDEX_FILE="$index_file" rgit update-index --add --cacheinfo "$entry" \
      || setup_fail "update-index $entry"
  done
  tree_id="$(GIT_INDEX_FILE="$index_file" rgit write-tree)" || setup_fail "write-tree"
  commit_id="$(rgit commit-tree "$tree_id" -m "$var" </dev/null)" || setup_fail "commit-tree"
  printf -v "$var" '%s' "$commit_id"
}

# object_file <oid>: prints the loose object path of <oid> in the scratch repo.
object_file() { printf '%s/.git/objects/%s/%s' "$REPO" "${1:0:2}" "${1:2}"; }

PRD_BYTES=$'# PRD\r\n\r\n**UI:** no\r\n'
EXEC_BYTES=$'#!/bin/sh\necho design\nno final newline'
store_blob PRD_BLOB "$PRD_BYTES"
store_blob EXEC_BLOB "$EXEC_BYTES"
store_blob GLOB_BLOB 'glob named file'
store_blob LINK_BLOB 'prds/demo.md'
store_blob PASSWD_BLOB '/etc/passwd'
store_blob ALIAS_BLOB 'docs'
commit_entries SEED_COMMIT "100644,$PRD_BLOB,seed.md"
commit_entries C1 \
  "100644,$PRD_BLOB,docs/prds/demo.md" \
  "100755,$EXEC_BLOB,docs/initiatives/demo/solution-design.md" \
  "100644,$GLOB_BLOB,docs/glob[1].md" \
  "120000,$LINK_BLOB,docs/link.md" \
  "120000,$PASSWD_BLOB,docs/passwd.md" \
  "120000,$ALIAS_BLOB,alias" \
  "160000,$SEED_COMMIT,sub"

store_blob GONE_TREE_BLOB 'content only under the deleted tree'
commit_entries C_TREE_GONE "100644,$GONE_TREE_BLOB,docs/prds/gone.md"
GONE_TREE="$(rgit rev-parse "$C_TREE_GONE^{tree}")" || setup_fail "rev-parse deleted tree"
rm -f "$(object_file "$GONE_TREE")" || setup_fail "cannot delete tree object"

store_blob LOST_BLOB 'content of the deleted blob'
commit_entries C_BLOB_GONE "100644,$LOST_BLOB,docs/prds/lost.md"
rm -f "$(object_file "$LOST_BLOB")" || setup_fail "cannot delete blob object"

# ── Sections ───────────────────────────────────────────────────────────────────────

test_library_form() {
  if [ "$(head -n 1 "$LIB")" = '# shellcheck shell=bash' ]; then
    pass "form:line-1" "shellcheck directive, no shebang"
  else
    failed "form:line-1" "line 1 is not '# shellcheck shell=bash'"
  fi
  if grep -q 'BASH_SOURCE' "$LIB"; then
    failed "form:no-bash-source" "BASH_SOURCE appears in the library"
  else
    pass "form:no-bash-source" "absent"
  fi
  if bash -n "$LIB"; then
    pass "form:syntax" "bash -n"
  else
    failed "form:syntax" "bash -n failed"
  fi
  local probe_out probe_status=0
  # shellcheck disable=SC2016
  probe_out="$(bash -c 'set -u
before_opts=""; after_opts=""; before_vars=""; after_vars=""
before_opts="$-:$SHELLOPTS:$BASHOPTS"; before_vars="$(compgen -v | grep -v "^_HIVEMIND_RC_")"
. "$1"; . "$1"
after_opts="$-:$SHELLOPTS:$BASHOPTS"; after_vars="$(compgen -v | grep -v "^_HIVEMIND_RC_")"
[ "$before_opts" = "$after_opts" ] || { echo options-changed; exit 1; }
[ "$before_vars" = "$after_vars" ] || { echo variables-changed; exit 1; }
echo unchanged' readiness-form "$LIB" 2>&1)" || probe_status=$?
  if [ "$probe_status" -eq 0 ] && [ "$probe_out" = unchanged ]; then
    pass "form:source-twice" "no output, no option or variable change"
  else
    failed "form:source-twice" "$probe_out"
  fi
  lib_call "form:usage" "$REPO" "$NO_INPUT" hivemind_doc_entry "$C1"
  expect_call "form:usage" 2 "" $'readiness-check-error: usage\n'
  expect_no_git "form:usage"
}

test_codes() {
  lib_call "codes" "$REPO" "$NO_INPUT" hivemind_readiness_codes
  local total unique parameterized
  total="$(wc -l <"$CALL_OUT")"
  unique="$(sort -u "$CALL_OUT" | wc -l)"
  parameterized="$(grep -c ':$' "$CALL_OUT")"
  if [ "$CALL_RC" = 0 ] && [ "$total" -eq 40 ] && [ "$unique" -eq 40 ] && [ "$parameterized" -eq 10 ]; then
    pass "codes:closed-set" "40 unique lines, 10 parameterized"
  else
    failed "codes:closed-set" "rc $CALL_RC, $total lines, $unique unique, $parameterized parameterized"
  fi
  if [ "$(head -n 1 "$CALL_OUT")" = issue_closed ] \
    && [ "$(tail -n 1 "$CALL_OUT")" = 'dependency_edge_missing:' ]; then
    pass "codes:order" "contract order ends"
  else
    failed "codes:order" "first or last code out of contract order"
  fi
}

test_commit_forms() {
  local form
  lib_call "commit:40-hex" "$REPO" "$NO_INPUT" hivemind_readiness_commit_ok "$C1"
  expect_call "commit:40-hex" 0 "" ""
  expect_no_git "commit:40-hex"
  lib_call "commit:64-hex" "$REPO" "$NO_INPUT" hivemind_readiness_commit_ok "$C1${C1:0:24}"
  expect_call "commit:64-hex" 0 "" ""
  for form in "$(printf '%s' "$C1" | tr 'a-f' 'A-F')" "${C1:0:7}" HEAD main -x "" "$C1"$'\n' "${C1}0"; do
    lib_call "commit:reject" "$REPO" "$NO_INPUT" hivemind_readiness_commit_ok "$form"
    expect_call "commit:reject:$(printf '%q' "$form")" 1 "" ""
    lib_call "commit:entry-reject" "$REPO" "$NO_INPUT" hivemind_doc_entry "$form" docs/prds/demo.md
    expect_call "commit:entry-reject:$(printf '%q' "$form")" 2 "" $'readiness-check-error: commit-malformed\n'
    expect_no_git "commit:entry-reject:$(printf '%q' "$form")"
  done
}

test_doc_entry() {
  local want_prd want_exec path
  want_prd="$(rgit rev-parse "$C1:docs/prds/demo.md")" || setup_fail "rev-parse prd"
  want_exec="$(rgit rev-parse "$C1:docs/initiatives/demo/solution-design.md")" || setup_fail "rev-parse exec"
  lib_call "entry:100644" "$REPO" "$NO_INPUT" hivemind_doc_entry "$C1" docs/prds/demo.md
  expect_call "entry:100644" 0 "$want_prd"$'\n' ""
  expect_git_flags "entry:100644"
  lib_call "entry:100755" "$REPO" "$NO_INPUT" hivemind_doc_entry "$C1" docs/initiatives/demo/solution-design.md
  expect_call "entry:100755" 0 "$want_exec"$'\n' ""
  lib_call "entry:literal-glob-name" "$REPO" "$NO_INPUT" hivemind_doc_entry "$C1" 'docs/glob[1].md'
  expect_call "entry:literal-glob-name" 0 "$GLOB_BLOB"$'\n' ""
  lib_call "entry:subdirectory" "$REPO/docs/prds" "$NO_INPUT" hivemind_doc_entry "$C1" docs/prds/demo.md
  expect_call "entry:subdirectory" 0 "$want_prd"$'\n' ""

  for path in docs/link.md docs/passwd.md sub sub/README.md docs/prds docs alias/prds/demo.md \
    docs/prds/none.md 'docs/prds/*.md' 'docs/glob?1?.md'; do
    lib_call "entry:missing" "$REPO" "$NO_INPUT" hivemind_doc_entry "$C1" "$path"
    expect_call "entry:missing:$path" 1 "" ""
  done
  for path in ./docs/prds/demo.md docs//prds/demo.md docs/prds/ docs/./prds/demo.md \
    docs/../docs/prds/demo.md /docs/prds/demo.md "" . .. $'docs/prds/demo.md\n' $'docs/\tx.md' \
    $'docs/\001x.md' $'docs/\177x.md'; do
    lib_call "entry:malformed-path" "$REPO" "$NO_INPUT" hivemind_doc_entry "$C1" "$path"
    expect_call "entry:malformed-path:$(printf '%q' "$path")" 1 "" ""
    expect_no_git "entry:malformed-path:$(printf '%q' "$path")"
  done

  lib_call "entry:deleted-tree" "$REPO" "$NO_INPUT" hivemind_doc_entry "$C_TREE_GONE" docs/prds/gone.md
  expect_call "entry:deleted-tree" 2 "" $'readiness-check-error: git-failed\n'
  lib_call "entry:unknown-commit" "$REPO" "$NO_INPUT" hivemind_doc_entry "$(printf '%040d' 0)" docs/prds/demo.md
  expect_call "entry:unknown-commit" 2 "" $'readiness-check-error: git-failed\n'
  lib_call "entry:deleted-blob" "$REPO" "$NO_INPUT" hivemind_doc_entry "$C_BLOB_GONE" docs/prds/lost.md
  expect_call "entry:deleted-blob" 0 "$LOST_BLOB"$'\n' ""
}

test_doc_read() {
  lib_call "read:crlf" "$REPO" "$NO_INPUT" hivemind_doc_read "$C1" docs/prds/demo.md
  expect_call "read:crlf" 0 "$PRD_BYTES" ""
  expect_git_flags "read:crlf"
  if [ "$(grep -c '^--no-replace-objects --literal-pathspecs ls-tree ' "$GIT_LOG")" -eq 2 ] \
    && [ "$(grep -c '^--no-replace-objects --literal-pathspecs cat-file blob ' "$GIT_LOG")" -eq 2 ]; then
    pass "read:one-resolution" "one ls-tree and one cat-file blob per run"
  else
    failed "read:one-resolution" "git log: $(cat "$GIT_LOG")"
  fi
  lib_call "read:no-final-newline" "$REPO" "$NO_INPUT" hivemind_doc_read "$C1" docs/initiatives/demo/solution-design.md
  expect_call "read:no-final-newline" 0 "$EXEC_BYTES" ""
  lib_call "read:missing" "$REPO" "$NO_INPUT" hivemind_doc_read "$C1" docs/link.md
  expect_call "read:missing" 1 "" ""
  lib_call "read:malformed-commit" "$REPO" "$NO_INPUT" hivemind_doc_read HEAD docs/prds/demo.md
  expect_call "read:malformed-commit" 2 "" $'readiness-check-error: commit-malformed\n'
  expect_no_git "read:malformed-commit"
  lib_call "read:deleted-blob" "$REPO" "$NO_INPUT" hivemind_doc_read "$C_BLOB_GONE" docs/prds/lost.md
  expect_call "read:deleted-blob" 2 "" $'readiness-check-error: git-failed\n'
  lib_call "read:deleted-tree" "$REPO" "$NO_INPUT" hivemind_doc_read "$C_TREE_GONE" docs/prds/gone.md
  expect_call "read:deleted-tree" 2 "" $'readiness-check-error: git-failed\n'
}

test_sha256_repo() {
  local repo256="$TMPDIR_TEST/repo256" blob256 tree256 commit256
  if ! "$REAL_GIT" init -q --object-format=sha256 "$repo256" >/dev/null 2>&1; then
    echo "SKIP [sha256] git $("$REAL_GIT" --version) cannot init a sha256 repository"
    return 0
  fi
  blob256="$(printf '%s' "$PRD_BYTES" | "$REAL_GIT" -C "$repo256" hash-object -w --stdin)" \
    || setup_fail "sha256 hash-object"
  GIT_INDEX_FILE="$TMPDIR_TEST/index.sha256" "$REAL_GIT" -C "$repo256" update-index --add \
    --cacheinfo "100644,$blob256,docs/prds/demo.md" || setup_fail "sha256 update-index"
  tree256="$(GIT_INDEX_FILE="$TMPDIR_TEST/index.sha256" "$REAL_GIT" -C "$repo256" write-tree)" \
    || setup_fail "sha256 write-tree"
  commit256="$("$REAL_GIT" -C "$repo256" commit-tree "$tree256" -m sha256 </dev/null)" \
    || setup_fail "sha256 commit-tree"
  lib_call "sha256:entry" "$repo256" "$NO_INPUT" hivemind_doc_entry "$commit256" docs/prds/demo.md
  expect_call "sha256:entry" 0 "$blob256"$'\n' ""
  lib_call "sha256:read" "$repo256" "$NO_INPUT" hivemind_doc_read "$commit256" docs/prds/demo.md
  expect_call "sha256:read" 0 "$PRD_BYTES" ""
}

test_seed_marker() {
  local case_name body
  local -a cases=(
    "valid|0|<!-- hivemind-initiative: idea-to-ready -->"$'\n\nBody text\n'
    "valid-crlf|0|<!-- hivemind-initiative: idea-to-ready -->"$'\r\nBody\r\n'
    "valid-only-line|0|<!-- hivemind-initiative: idea-to-ready -->"
    "leading-blank|1|"$'\n'"<!-- hivemind-initiative: idea-to-ready -->"$'\n'
    "uppercase-slug|1|<!-- hivemind-initiative: Idea-to-ready -->"$'\n'
    "double-hyphen|1|<!-- hivemind-initiative: a--b -->"$'\n'
    "trailing-text|1|<!-- hivemind-initiative: idea-to-ready --> more"$'\n'
    "line-two|1|# Title"$'\n'"<!-- hivemind-initiative: idea-to-ready -->"$'\n'
    "two-crs|1|<!-- hivemind-initiative: idea-to-ready -->"$'\r\r\n'
    "empty|1|"
  )
  local entry want_rc want_out
  for entry in "${cases[@]}"; do
    case_name="${entry%%|*}"
    want_rc="${entry#*|}"
    body="${want_rc#*|}"
    want_rc="${want_rc%%|*}"
    want_out=""
    [ "$want_rc" = 0 ] && want_out=$'idea-to-ready\n'
    lib_call "seed:$case_name" "$REPO" "$(write_input "seed-$case_name" "$body")" hivemind_seed_marker_slug
    expect_call "seed:$case_name" "$want_rc" "$want_out" ""
    expect_no_git "seed:$case_name"
  done
}

test_record_front_matter() {
  local blob40="$C1" blob64="$C1${C1:0:24}" valid valid_json zero zero_json crlf
  valid="---
stamps:
  - path: docs/prds/demo.md
    blob: $blob40
  - path: docs/initiatives/demo/solution-design.md
    blob: $blob64
  - path: docs/initiatives/demo/prototype/index.html
    blob: $blob40
  - path: docs/initiatives/demo/prototype/notes.md
    blob: $blob40
  - path: docs/adr/0046-idea-to-ready-process.md
    blob: $blob40
verdict: pass
open:
  critical: 0
  high: 0
  medium: 2
  low: 10
rounds: 3
clean_round: true
---

# Design review record
"
  valid_json="{\"stamps\":[{\"path\":\"docs/prds/demo.md\",\"blob\":\"$blob40\"},"
  valid_json+="{\"path\":\"docs/initiatives/demo/solution-design.md\",\"blob\":\"$blob64\"},"
  valid_json+="{\"path\":\"docs/initiatives/demo/prototype/index.html\",\"blob\":\"$blob40\"},"
  valid_json+="{\"path\":\"docs/initiatives/demo/prototype/notes.md\",\"blob\":\"$blob40\"},"
  valid_json+="{\"path\":\"docs/adr/0046-idea-to-ready-process.md\",\"blob\":\"$blob40\"}],"
  valid_json+='"verdict":"pass","open":{"critical":0,"high":0,"medium":2,"low":10},"rounds":3,"clean_round":true}'
  zero="---
stamps: []
verdict: fail
open:
  critical: 1
  high: 0
  medium: 0
  low: 0
rounds: 0
clean_round: false
---
"
  zero_json='{"stamps":[],"verdict":"fail","open":{"critical":1,"high":0,"medium":0,"low":0},"rounds":0,"clean_round":false}'
  crlf="${valid//$'\n'/$'\r\n'}"

  lib_call "record:valid" "$REPO" "$(write_input record-valid "$valid")" hivemind_record_front_matter
  expect_call "record:valid" 0 "$valid_json"$'\n' ""
  expect_no_git "record:valid"
  lib_call "record:zero-stamps" "$REPO" "$(write_input record-zero "$zero")" hivemind_record_front_matter
  expect_call "record:zero-stamps" 0 "$zero_json"$'\n' ""
  lib_call "record:crlf" "$REPO" "$(write_input record-crlf "$crlf")" hivemind_record_front_matter
  expect_call "record:crlf" 0 "$valid_json"$'\n' ""

  local -a malformed=(
    "missing-open-fence|${valid#---$'\n'}"
    "missing-close-fence|${zero%---$'\n'}"
    "keys-out-of-order|${valid/rounds: 3$'\n'clean_round: true/clean_round: true$'\n'rounds: 3}"
    "open-before-verdict|${valid/verdict: pass$'\n'open:/open:$'\n'verdict: pass}"
    "extra-key|${valid/clean_round: true/clean_round: true$'\n'extra: 1}"
    "comment-line|${valid/verdict: pass/# note$'\n'verdict: pass}"
    "trailing-space|${valid/rounds: 3/rounds: 3 }"
    "blob-39-hex|${valid/blob: $blob40/blob: ${blob40:0:39}}"
    "blob-uppercase|${valid/blob: $blob40/blob: $(printf '%s' "$blob40" | tr 'a-f' 'A-F')}"
    "stamp-prototype-dir|${valid/docs\/initiatives\/demo\/prototype\/index.html/docs/initiatives/x/prototype/}"
    "stamp-other|${valid/docs\/prds\/demo.md/docs/other.md}"
    "stamp-duplicate|${valid/docs\/initiatives\/demo\/solution-design.md/docs/prds/demo.md}"
    "leading-zero|${valid/rounds: 3/rounds: 01}"
    "verdict-maybe|${valid/verdict: pass/verdict: maybe}"
    "clean-round-yes|${valid/clean_round: true/clean_round: yes}"
    "bare-stamps-no-pairs|${zero/stamps: []/stamps:}"
    "empty-list-with-pairs|${valid/stamps:/stamps: []}"
    "open-counts-key|${zero/open:/open_counts:}"
    "clean-round-null|${zero/clean_round: false/clean_round: null}"
    "empty|"
  )
  local entry case_name record
  for entry in "${malformed[@]}"; do
    case_name="${entry%%|*}"
    record="${entry#*|}"
    lib_call "record:$case_name" "$REPO" "$(write_input "record-$case_name" "$record")" hivemind_record_front_matter
    expect_call "record:$case_name" 1 "" ""
  done
}

test_path_kind() {
  local entry path want
  for entry in docs/prds/demo.md=prd docs/initiatives/demo/solution-design.md=solution-design \
    docs/initiatives/demo/review-record.md=review-record \
    docs/initiatives/demo/prototype/index.html=prototype-index \
    docs/initiatives/demo/prototype/notes.md=prototype-notes docs/adr/0046-idea-to-ready.md=adr \
    docs/initiatives/x/prototype/= docs/other.md= docs/adr/46-x.md= docs/prds/Demo.md= \
    docs/prds/a--b.md= docs/initiatives/demo/../demo/solution-design.md= =; do
    path="${entry%=*}"
    want="${entry##*=}"
    lib_call "path-kind:$path" "$REPO" "$NO_INPUT" hivemind_readiness_path_kind "$path"
    if [ -n "$want" ]; then
      expect_call "path-kind:$path" 0 "$want"$'\n' ""
    else
      expect_call "path-kind:$path" 1 "" ""
    fi
  done
  lib_call "path-kind:trailing-newline" "$REPO" "$NO_INPUT" hivemind_readiness_path_kind $'docs/prds/demo.md\n'
  expect_call "path-kind:trailing-newline" 1 "" ""
}

# ── Snapshot mode ──────────────────────────────────────────────────────────────────

CASES="$REPO_ROOT/tests/readiness-check/cases.json"
DOCS="$REPO_ROOT/tests/readiness-check/docs.json"
SNAP_REPO_ARG='brenpike/hivemind'
SNAP_TRUNK_ARG='main'
SNAP_OUT_ALL="$TMPDIR_TEST/snapshot-lines.all"
: >"$SNAP_OUT_ALL" || setup_fail "cannot create $SNAP_OUT_ALL"
jq -e 'type == "array" and length > 0
  and all(.[]; has("expected") and has("name") and has("snapshot")
    and (keys - ["docs", "expected", "name", "objects", "reads", "record", "snapshot"] == [])
    and (.expected | keys == ["reasons", "result", "track"]))' "$CASES" >/dev/null 2>&1 \
  || setup_fail "cases file missing or off its shape: $CASES"
jq -e 'type == "object" and length > 0 and all(.[]; type == "string")' "$DOCS" >/dev/null 2>&1 \
  || setup_fail "docs file missing or off its shape: $DOCS"

# ── Case documents ─────────────────────────────────────────────────────────────────
#
# docs.json maps repository paths to content. A case's `docs` overrides it (null deletes a path),
# its `record` is a review record spec or a raw template written at the demo record path, and its
# `objects` turn paths into a symlink, a gitlink, a tree or a symlinked directory. A document's
# `{{blob:<path>}}` placeholder renders as the blob id of <path>'s content in the case, before any
# object change, and `{{base:<path>}}` as the blob id of <path>'s content in docs.json.
#
# CASE_PLAN_JQ prints one tab-separated line per document: `map` lines give each placeholder-free
# document's content before object changes, then `entry` and `gitlink` lines give the tree.

# shellcheck disable=SC2016
CASE_PLAN_JQ='
def record_text:
  if type == "string" then {path: "docs/initiatives/demo/review-record.md", text: .}
  else (.path // "docs/initiatives/demo/review-record.md") as $path
  | ($path | capture("\\Adocs/initiatives/(?<s>[^/]+)/").s) as $slug
  | ({critical: 0, high: 0, medium: 0, low: 0} + (.open // {})) as $open
  | ((.stamps // ["docs/prds/\($slug).md", "docs/initiatives/\($slug)/solution-design.md"])
     | map(if type == "string" then {path: ., blob: "{{blob:\(.)}}"}
           elif .base then {path, blob: "{{base:\(.path)}}"}
           else {path, blob} end)) as $stamps
  | {path: $path,
     text: ("---\n"
       + (if ($stamps | length) == 0 then "stamps: []\n"
          else "stamps:\n" + ($stamps | map("  - path: \(.path)\n    blob: \(.blob)\n") | add) end)
       + "verdict: \(.verdict // "pass")\nopen:\n  critical: \($open.critical)\n  high: \($open.high)\n"
       + "  medium: \($open.medium)\n  low: \($open.low)\nrounds: \(.rounds // 2)\n"
       + "clean_round: \(if has("clean_round") then .clean_round else true end)\n---\n\n"
       + "# Design review record\n")}
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
  else error("unknown object type \($object.type)") end;
. as $case
| ($docs[0] + ($case.docs // {})
   + (if $case.record == null then {} else ($case.record | record_text | {(.path): .text}) end)
   | with_entries(select(.value != null))) as $merged
| ($merged | to_entries | map(select(.value | contains("{{") | not))[]
   | "map\t100644\t\(.key)\t\(.value | @base64)"),
  (reduce ($case.objects // [])[] as $object
     ($merged | to_entries | map({path: .key, mode: "100644", text: .value}); apply_object($object))
   | .[]
   | if .gitlink then "gitlink\t160000\t\(.path)\t-"
     else "entry\t\(.mode)\t\(.path)\t\(.text | @base64)" end)'

declare -A HASH_CACHE=() BASE_BLOBS=() CASE_BLOBS=()

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
  for path in "${!CASE_BLOBS[@]}"; do
    rendered="${rendered//"{{blob:$path}}"/${CASE_BLOBS[$path]}}"
  done
  for path in "${!BASE_BLOBS[@]}"; do
    rendered="${rendered//"{{base:$path}}"/${BASE_BLOBS[$path]}}"
  done
  case "$rendered" in
    *'{{'*) setup_fail "unrendered placeholder in a case document" ;;
  esac
  printf -v "$1" '%s' "$rendered"
}

# build_case_commit <var> <case-file>: builds the case's document tree as a commit and assigns its
# id to <var>; CASE_BLOBS holds the case's placeholder blob ids afterwards.
build_case_commit() {
  local var="$1" plan_file="$TMPDIR_TEST/plan.$1" index_file="$TMPDIR_TEST/index.$1"
  local kind mode path encoded oid text tree_id commit_id index_info=""
  jq -r --slurpfile docs "$DOCS" "$CASE_PLAN_JQ" "$2" >"$plan_file" || setup_fail "case plan $2"
  CASE_BLOBS=()
  while IFS=$'\t' read -r kind mode path encoded; do
    case "$kind" in
      map)
        hash_encoded oid "$encoded"
        CASE_BLOBS[$path]="$oid"
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
      *) setup_fail "case plan line kind $kind" ;;
    esac
  done <"$plan_file"
  rm -f "$index_file"
  printf '%s' "$index_info" | GIT_INDEX_FILE="$index_file" rgit update-index --index-info \
    || setup_fail "update-index for $var"
  tree_id="$(GIT_INDEX_FILE="$index_file" rgit write-tree)" || setup_fail "write-tree for $var"
  commit_id="$(rgit commit-tree "$tree_id" -m "$var" </dev/null)" || setup_fail "commit-tree for $var"
  printf -v "$var" '%s' "$commit_id"
}

EMPTY_CASE="$(write_input empty-case '{}')"
build_case_commit BASE_COMMIT "$EMPTY_CASE"
for path in "${!CASE_BLOBS[@]}"; do
  BASE_BLOBS[$path]="${CASE_BLOBS[$path]}"
done
SNAP_COMMIT="$BASE_COMMIT"

# snapshot_call <case> <stdin-file> [arg...]: runs snapshot mode with the given arguments, or
# SNAP_COMMIT, the scratch owner/repo and trunk when none are given.
snapshot_call() {
  local case_name="$1" in_file="$2"
  shift 2
  if [ "$#" -eq 0 ]; then
    set -- "$SNAP_COMMIT" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG"
  fi
  lib_call "$case_name" "$REPO" "$in_file" hivemind_readiness_check_snapshot "$@"
}

# snapshot_lines_verdict <stdin-file> <expected-json-array>: prints `ok` when the last call's
# stdout holds one compact five-key line per snapshot element with the expected values, else the
# first mismatch.
snapshot_lines_verdict() {
  jq -Rnr --slurpfile input "$1" --argjson expected "$2" --arg commit "$SNAP_COMMIT" '
[inputs] as $lines
| if ($lines | length) != ($expected | length) then
    "\($lines | length) lines, want \($expected | length)"
  else
    [range(0; $expected | length) as $i
     | ($lines[$i] | try fromjson catch null) as $line
     | if ($line | type) != "object" then "line \($i + 1) does not parse"
       elif $lines[$i] != ($line | tojson) then "line \($i + 1) is not compact JSON"
       elif ($line | keys_unsorted) != ["issue", "commit", "track", "result", "reasons"] then
         "line \($i + 1) keys \($line | keys_unsorted | tojson)"
       elif $line.issue != $input[0][$i].number then "line \($i + 1) issue \($line.issue)"
       elif $line.commit != $commit then "line \($i + 1) commit \($line.commit)"
       elif ($line | {track, result, reasons}) != $expected[$i] then "line \($i + 1): \($lines[$i])"
       else empty end]
    | if length == 0 then "ok" else .[0] end
  end' <"$CALL_OUT" 2>&1
}

# expect_snapshot_lines <case> <stdin-file> <expected-json-array> [reads-json-array]: asserts a
# passing run and its output lines, that each run resolves the commit once and makes no git call
# but a document existence test or a blob read, and, when given, the exact set of paths tested.
expect_snapshot_lines() {
  local case_name="$1" want_reads="${4-}" verdict line bad=0 resolves=0 reads=""
  local flags='--no-replace-objects --literal-pathspecs'
  verdict="$(snapshot_lines_verdict "$2" "$3")"
  if [ "$CALL_RC" != 0 ] || [ -s "$CALL_ERR" ]; then
    failed "$case_name" "rc $CALL_RC, stderr: $(cat "$CALL_ERR")"
  elif [ "$verdict" != ok ]; then
    failed "$case_name" "$verdict"
  else
    pass "$case_name" "lines match"
  fi
  cat "$CALL_OUT" >>"$SNAP_OUT_ALL" || setup_fail "cannot append to $SNAP_OUT_ALL"
  while IFS= read -r line; do
    case "$line" in
      "$flags cat-file -t $SNAP_COMMIT") resolves=$((resolves + 1)) ;;
      "$flags ls-tree --full-tree -z $SNAP_COMMIT -- "*) reads+="${line##* -- }"$'\n' ;;
      "$flags cat-file blob "*) ;;
      *) bad=1 ;;
    esac
  done <"$GIT_LOG"
  if [ "$bad" -eq 0 ] && [ "$resolves" -eq 2 ]; then
    pass "$case_name:git" "one commit resolution per run, document reads only"
  else
    failed "$case_name:git" "git log: $(cat "$GIT_LOG")"
  fi
  if [ -n "$want_reads" ]; then
    if [ "$(printf '%s' "$reads" | jq -Rnc '[inputs] | unique')" = "$want_reads" ]; then
      pass "$case_name:reads" "exactly the expected paths tested"
    else
      failed "$case_name:reads" "paths tested: $(printf '%s' "$reads" | sort -u | tr '\n' ' ')want: $want_reads"
    fi
  fi
}

test_snapshot_cases() {
  local count index case_name case_file input expected reads snapshot
  count="$(jq 'length' "$CASES")" || setup_fail "cannot count cases"
  for ((index = 0; index < count; index++)); do
    case_file="$TMPDIR_TEST/case.$index"
    jq -c --argjson i "$index" '.[$i]' "$CASES" >"$case_file" || setup_fail "case file $index"
    input="$TMPDIR_TEST/input.case-$index"
    {
      IFS= read -r case_name && IFS= read -r expected && IFS= read -r reads && IFS= read -r snapshot
    } < <(jq -r '.name, ([.expected] | tojson), (.reads // null | if . == null then "" else unique | tojson end),
      ([.snapshot] | tojson)' "$case_file") || setup_fail "case fields $index"
    printf '%s\n' "$snapshot" >"$input" || setup_fail "case input $index"
    build_case_commit SNAP_COMMIT "$case_file"
    snapshot_call "snapshot:$case_name" "$input"
    expect_snapshot_lines "snapshot:$case_name" "$input" "$expected" "$reads"
  done
  SNAP_COMMIT="$BASE_COMMIT"
  if [ -z "$(find "$TMPDIR_TEST" -name pwned -print)" ]; then
    pass "snapshot:hostile-heading-inert" "no pwned file created"
  else
    failed "snapshot:hostile-heading-inert" "a pwned file exists"
  fi
}

test_snapshot_multi() {
  local input expected
  input="$TMPDIR_TEST/input.multi"
  jq -c '[(.[] | select(.name == "slice-pass")), (.[] | select(.name == "issue-closed"))] | map(.snapshot)' \
    "$CASES" >"$input" || setup_fail "multi input"
  expected="$(jq -c '[(.[] | select(.name == "slice-pass")), (.[] | select(.name == "issue-closed"))]
    | map(.expected)' "$CASES")" || setup_fail "multi expected"
  snapshot_call "snapshot:two-elements" "$input"
  expect_snapshot_lines "snapshot:two-elements" "$input" "$expected"
  snapshot_call "snapshot:empty-array" "$(write_input snapshot-empty '[]')"
  expect_call "snapshot:empty-array" 0 "" ""
}

test_snapshot_failures() {
  local base entry path_json input truncated
  base="$(jq -c '.[] | select(.name == "slice-pass") | .snapshot' "$CASES")" || setup_fail "base snapshot"
  for path_json in '["number"]' '["state"]' '["body"]' '["labels"]' '["labels","nodes"]' \
    '["labels","nodes",0,"name"]' '["blockedBy"]' '["blockedBy","nodes"]' \
    '["blockedBy","nodes",0,"number"]' '["subIssues"]' '["subIssues","totalCount"]' '["parent"]' \
    '["parent","number"]' '["parent","state"]' '["parent","body"]' '["parent","labels"]' \
    '["parent","labels","nodes"]' '["parent","labels","nodes",0,"name"]'; do
    input="$TMPDIR_TEST/input.missing-$CALL_N"
    printf '%s' "$base" | jq -c --argjson p "$path_json" '[delpaths([$p])]' >"$input" \
      || setup_fail "missing-field input $path_json"
    snapshot_call "snapshot:missing:$path_json" "$input"
    expect_call "snapshot:missing:$path_json" 2 "" $'readiness-check-error: snapshot-malformed\n'
  done
  for entry in '.number = "201"' '.number = 0' '.number = 1.5' '.state = "open"' '.body = 5' \
    '.labels.nodes[0].name = 5' '.labels.nodes[0] = null' '.blockedBy.nodes[0].number = "150"' \
    '.subIssues.totalCount = -1' '.subIssues.totalCount = null' '.parent = "200"' \
    '.parent.body = false' '.parent.state = null' '.labels.pageInfo = "x"' \
    '.labels.pageInfo.hasNextPage = "true"' '5'; do
    input="$TMPDIR_TEST/input.wrong-$CALL_N"
    printf '%s' "$base" | jq -c "[$entry]" >"$input" || setup_fail "wrong-type input $entry"
    snapshot_call "snapshot:wrong-type:$entry" "$input"
    expect_call "snapshot:wrong-type:$entry" 2 "" $'readiness-check-error: snapshot-malformed\n'
  done
  for entry in '{}' '"x"' '' '[] []' '[' 'null'; do
    snapshot_call "snapshot:not-array:$entry" "$(write_input "not-array-$CALL_N" "$entry")"
    expect_call "snapshot:not-array:$entry" 2 "" $'readiness-check-error: snapshot-malformed\n'
  done
  for entry in labels blockedBy subIssues parent.labels; do
    input="$TMPDIR_TEST/input.truncated-$CALL_N"
    printf '%s' "$base" | jq -c --arg c "$entry" \
      '[setpath(($c | split(".")) + ["pageInfo", "hasNextPage"]; true)]' >"$input" \
      || setup_fail "truncated input $entry"
    snapshot_call "snapshot:truncated:$entry" "$input"
    expect_call "snapshot:truncated:$entry" 2 "" $'readiness-check-error: truncated\n'
  done
  input="$TMPDIR_TEST/input.not-truncated"
  printf '%s' "$base" | jq -c '[.labels.pageInfo.hasNextPage = false | .blockedBy.pageInfo = null
    | .subIssues.pageInfo = {} | .parent.labels.pageInfo.hasNextPage = false]' >"$input" \
    || setup_fail "not-truncated input"
  snapshot_call "snapshot:has-next-page-false" "$input"
  expect_snapshot_lines "snapshot:has-next-page-false" "$input" \
    '[{"track":"slice","result":"pass","reasons":[]}]'
  truncated="$(printf '%s' "$base" | jq -c '.labels.pageInfo.hasNextPage = true')" \
    || setup_fail "truncated element"
  input="$TMPDIR_TEST/input.malformed-first"
  printf '%s' "$base" | jq -c --argjson t "$truncated" '[$t, del(.state)]' >"$input" \
    || setup_fail "malformed-first input"
  snapshot_call "snapshot:malformed-before-truncated" "$input"
  expect_call "snapshot:malformed-before-truncated" 2 "" $'readiness-check-error: snapshot-malformed\n'

  input="$(write_input snapshot-base "[$base]")"
  snapshot_call "snapshot:unknown-commit" "$input" "$(printf '%040d' 0)" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG"
  expect_call "snapshot:unknown-commit" 2 "" $'readiness-check-error: commit-unresolvable\n'
  expect_git_flags "snapshot:unknown-commit"
  snapshot_call "snapshot:blob-commit" "$input" "$PRD_BLOB" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG"
  expect_call "snapshot:blob-commit" 2 "" $'readiness-check-error: commit-unresolvable\n'
  snapshot_call "snapshot:malformed-commit" "$input" HEAD "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG"
  expect_call "snapshot:malformed-commit" 2 "" $'readiness-check-error: commit-malformed\n'
  expect_no_git "snapshot:malformed-commit"
  for entry in '' brenpike -x/y x/-y .x/y x/.y x/y/z x//y 'x/y..z' 'x y/z' $'x/y\n' 'x/y;z' 'ü/y'; do
    snapshot_call "snapshot:bad-owner-repo" "$input" "$C1" "$entry" "$SNAP_TRUNK_ARG"
    expect_call "snapshot:bad-owner-repo:$(printf '%q' "$entry")" 2 "" $'readiness-check-error: usage\n'
    expect_no_git "snapshot:bad-owner-repo:$(printf '%q' "$entry")"
  done
  for entry in '' -main 'a..b' 'ma in' 'main;x' $'main\n' 'main~1' 'main^' 'mäin'; do
    snapshot_call "snapshot:bad-trunk" "$input" "$C1" "$SNAP_REPO_ARG" "$entry"
    expect_call "snapshot:bad-trunk:$(printf '%q' "$entry")" 2 "" $'readiness-check-error: usage\n'
    expect_no_git "snapshot:bad-trunk:$(printf '%q' "$entry")"
  done
  snapshot_call "snapshot:two-args" "$input" "$C1" "$SNAP_REPO_ARG"
  expect_call "snapshot:two-args" 2 "" $'readiness-check-error: usage\n'
  expect_no_git "snapshot:two-args"
}

test_snapshot_no_gh() {
  local stub_rc=0
  PATH="$WRAP_DIR:$PATH" RC_TEST_GH_LOG="$GH_LOG.probe" gh probe >/dev/null 2>&1 || stub_rc=$?
  if [ "$stub_rc" -ne 0 ] && [ -s "$GH_LOG.probe" ]; then
    pass "snapshot:gh-stub" "the stub on PATH fails and records"
  else
    failed "snapshot:gh-stub" "stub rc $stub_rc did not fail and record"
  fi
  if [ -s "$GH_LOG" ]; then
    failed "snapshot:no-gh" "gh ran: $(head -n 1 "$GH_LOG")"
  else
    pass "snapshot:no-gh" "no gh call in any snapshot run"
  fi
}

test_snapshot_code_bases() {
  local codes_file="$TMPDIR_TEST/codes.list" base bad="" seen=0
  lib_call "snapshot:codes" "$REPO" "$NO_INPUT" hivemind_readiness_codes
  cp "$CALL_OUT" "$codes_file" || setup_fail "cannot copy the code list"
  while IFS= read -r base; do
    seen=$((seen + 1))
    grep -qxF -- "$base" "$codes_file" || bad="$bad $base"
  done < <(jq -r '.reasons[] | if test(":") then sub(":.*"; ":") else . end' "$SNAP_OUT_ALL" | sort -u)
  if [ -z "$bad" ] && [ "$seen" -gt 0 ]; then
    pass "snapshot:code-bases" "$seen emitted code bases all in the closed set"
  else
    failed "snapshot:code-bases" "outside the closed set:$bad (seen $seen)"
  fi
  bad=""
  while IFS= read -r base; do
    jq -e --arg base "$base" 'any(.[].expected.reasons[]; . == $base or startswith($base))' "$CASES" \
      >/dev/null || bad="$bad $base"
  done <"$codes_file"
  if [ -z "$bad" ]; then
    pass "snapshot:code-coverage" "the cases expect every base code"
  else
    failed "snapshot:code-coverage" "no case expects:$bad"
  fi
}

# write_case_file <name> <jq-filter>: writes the slice-pass case changed by <jq-filter>, which may
# read $docs, and prints its path.
write_case_file() {
  local case_file="$TMPDIR_TEST/case.$1"
  jq -c --slurpfile docs "$DOCS" ".[] | select(.name == \"slice-pass\") | $2" "$CASES" >"$case_file" \
    || setup_fail "case file $1"
  printf '%s' "$case_file"
}

test_snapshot_subdirectory() {
  local input root_out
  input="$(write_input snapshot-subdir "$(jq -c '[.[] | select(.name == "slice-pass") | .snapshot]' "$CASES")")"
  snapshot_call "snapshot:root-cwd" "$input"
  expect_snapshot_lines "snapshot:root-cwd" "$input" '[{"track":"slice","result":"pass","reasons":[]}]'
  root_out="$CALL_OUT"
  lib_call "snapshot:subdirectory" "$REPO/docs/prds" "$input" hivemind_readiness_check_snapshot \
    "$SNAP_COMMIT" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG"
  if [ "$CALL_RC" = 0 ] && [ -s "$CALL_OUT" ] && cmp -s "$root_out" "$CALL_OUT"; then
    pass "snapshot:subdirectory" "the same line as from the work tree root"
  else
    failed "snapshot:subdirectory" "rc $CALL_RC, stdout: $(cat "$CALL_OUT")"
  fi
}

test_snapshot_git_failure() {
  local case_file input lost_blob
  case_file="$(write_case_file blob-lost \
    '.docs = {"docs/prds/demo.md": ($docs[0]["docs/prds/demo.md"] + "\nOnly in the lost blob.\n")}')"
  build_case_commit SNAP_COMMIT "$case_file"
  lost_blob="$(rgit rev-parse "$SNAP_COMMIT:docs/prds/demo.md")" || setup_fail "rev-parse lost blob"
  rm -f "$(object_file "$lost_blob")" || setup_fail "cannot delete the PRD blob object"
  input="$TMPDIR_TEST/input.blob-lost"
  jq -c '[.snapshot]' "$case_file" >"$input" || setup_fail "blob-lost input"
  snapshot_call "snapshot:deleted-blob" "$input"
  expect_call "snapshot:deleted-blob" 2 "" $'readiness-check-error: git-failed\n'
  SNAP_COMMIT="$BASE_COMMIT"
}

test_snapshot_large_design() {
  local case_file input size
  case_file="$(write_case_file large-design \
    '.docs = {"docs/initiatives/demo/solution-design.md":
       ($docs[0]["docs/initiatives/demo/solution-design.md"]
        | sub("The initiative\u0027s context.\n"; "The initiative\u0027s context.\n"
            + ([range(0; 4000) | "Filler line \(.) holds the context of a large solution design."]
               | join("\n")) + "\n"))}')"
  size="$(jq -r '.docs[] | utf8bytelength' "$case_file")" || setup_fail "large design size"
  [ "$size" -gt 204800 ] || setup_fail "large design is only $size bytes"
  build_case_commit SNAP_COMMIT "$case_file"
  input="$TMPDIR_TEST/input.large-design"
  jq -c '[.snapshot]' "$case_file" >"$input" || setup_fail "large-design input"
  snapshot_call "snapshot:large-design" "$input"
  expect_snapshot_lines "snapshot:large-design" "$input" '[{"track":"slice","result":"pass","reasons":[]}]'
  SNAP_COMMIT="$BASE_COMMIT"
}

# ── gh mode ────────────────────────────────────────────────────────────────────────
#
# gh-cases.json holds gh mode cases. Each names its issue numbers, the canned response per number
# and either `lines`, the cases.json cases whose expected lines it gives, or `token`, its failure
# token. A response is `raw` body text, a `json` body, or an `issue` response wrapping a cases.json
# snapshot, given `pageInfo: {hasNextPage: false}` on each connection that has none as gh's reply
# to the constant query always holds one, with `del` paths removed, `set` paths set, `extra`
# top-level keys and `copies` bodies;
# `rc` is gh's exit status, 0 by default. `commit` names the cases.json case whose documents the
# evaluated commit holds; absent, the base documents.

GH_CASES="$REPO_ROOT/tests/readiness-check/gh-cases.json"
# shellcheck disable=SC2016
GH_QUERY='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){number state body labels(first:100){pageInfo{hasNextPage} nodes{name}} blockedBy(first:100){pageInfo{hasNextPage} nodes{number state}} subIssues(first:100){totalCount pageInfo{hasNextPage}} parent{number state body labels(first:100){pageInfo{hasNextPage} nodes{name}}}}}}'
jq -e 'type == "array" and length > 0
  and all(.[]; has("name") and (.numbers | type == "array" and length > 0)
    and (.responses | type == "object")
    and ((has("lines") and (has("token") | not)) or (has("token") and (has("lines") | not)))
    and (keys - ["commit", "lines", "name", "numbers", "responses", "token"] == []))' \
  "$GH_CASES" >/dev/null 2>&1 || setup_fail "gh cases file missing or off its shape: $GH_CASES"

# shellcheck disable=SC2016
GH_RESPONSE_JQ='
def case_node($name): first($cases[0][] | select(.name == $name) | .snapshot);
def paged: if has("pageInfo") then . else .pageInfo = {hasNextPage: false} end;
def node_of:
  . as $response
  | case_node($response.issue)
  | .labels |= paged | .blockedBy |= paged | .subIssues |= paged
  | if .parent == null then . else .parent.labels |= paged end
  | reduce ($response.del // [])[] as $path (.; delpaths([$path]))
  | reduce ($response.set // [])[] as $change (.; setpath($change.path; $change.value));
def body_of:
  if has("raw") then .raw
  elif has("json") then (.json | tojson) + "\n"
  else . as $response
  | (({data: {repository: {issue: node_of}}} + ($response.extra // {})) | tojson + "\n") as $body
  | [range(0; $response.copies // 1) | $body] | add end;'

# gh_call <case> <fn> [arg...]: clears the gh log, then runs lib_call from the scratch repo root
# with no stdin.
gh_call() {
  local case_name="$1"
  shift
  : >"$GH_LOG"
  lib_call "$case_name" "$REPO" "$NO_INPUT" "$@"
}

# serve_gh_case <case-file>: writes the case's canned gh responses into the serve dir.
serve_gh_case() {
  local number status encoded body
  rm -f "$GH_SERVE_DIR"/* || setup_fail "cannot clear the gh serve dir"
  while IFS=$'\t' read -r number status encoded; do
    decode_text body "$encoded"
    printf '%s' "$body" >"$GH_SERVE_DIR/$number.body" || setup_fail "gh body $number"
    printf '%s\n' "$status" >"$GH_SERVE_DIR/$number.rc" || setup_fail "gh status $number"
  done < <(jq -r --slurpfile cases "$CASES" "$GH_RESPONSE_JQ"'
.responses | to_entries[] | "\(.key)\t\(.value.rc // 0)\t\(.value | body_of | @base64)"' "$1")
}

# expect_gh_argv <case> <number>...: asserts the gh log holds, for each of the two shell-mode runs,
# exactly one call per <number> in order, each with the constant query and separate variables.
expect_gh_argv() {
  local case_name="$1" per_run="" number
  shift
  for number in "$@"; do
    per_run+="<api><graphql><-f><query=$GH_QUERY><-f><owner=${SNAP_REPO_ARG%%/*}>"
    per_run+="<-f><name=${SNAP_REPO_ARG#*/}><-F><number=$number>"$'\n'
  done
  if file_is "$GH_LOG" "$per_run$per_run"; then
    pass "$case_name:gh-argv" "one gh call per number per run, variables as separate entries"
  else
    failed "$case_name:gh-argv" "gh log: $(cat "$GH_LOG")"
  fi
}

# expect_no_gh <case>: asserts the last gh_call ran no gh command.
expect_no_gh() {
  if [ -s "$GH_LOG" ]; then
    failed "$1:no-gh" "gh ran: $(head -n 1 "$GH_LOG")"
  else
    pass "$1:no-gh" "no gh call"
  fi
}

test_gh_query_constant() {
  if [[ "$GH_QUERY" == *'issue(number:$number)'* ]] && ! [[ "$GH_QUERY" =~ number:[[:space:]]*[0-9] ]] \
    && [[ "$GH_QUERY" == 'query($owner:String!,$name:String!,$number:Int!)'* ]]; then
    pass "gh:query-constant" "variables declared, no literal issue number"
  else
    failed "gh:query-constant" "query: $GH_QUERY"
  fi
}

# run_gh_lines_case <case-name> <case-file> <number>...: runs a passing gh mode case and asserts
# its lines, that snapshot mode gives the same bytes for the served nodes, and the fetch output.
run_gh_lines_case() {
  local case_name="$1" case_file="$2" input expected gh_out node_out
  shift 2
  input="$TMPDIR_TEST/input.gh-$CALL_N"
  jq -c --slurpfile cases "$CASES" "$GH_RESPONSE_JQ"'
. as $case | [.numbers[] | tostring | $case.responses[.] | node_of]' "$case_file" >"$input" \
    || setup_fail "gh snapshot input $case_name"
  expected="$(jq -c --slurpfile cases "$CASES" '[.lines[] as $line
    | first($cases[0][] | select(.name == $line) | .expected)]' "$case_file")" \
    || setup_fail "gh expected $case_name"
  gh_call "gh:$case_name" hivemind_readiness_check_gh "$SNAP_COMMIT" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG" "$@"
  gh_out="$CALL_OUT"
  expect_gh_argv "gh:$case_name" "$@"
  expect_snapshot_lines "gh:$case_name" "$input" "$expected"
  snapshot_call "gh:$case_name:snapshot" "$input"
  if [ "$CALL_RC" = 0 ] && [ -s "$gh_out" ] && cmp -s "$gh_out" "$CALL_OUT"; then
    pass "gh:$case_name:same-as-snapshot" "gh mode output equals snapshot mode output"
  else
    failed "gh:$case_name:same-as-snapshot" "gh: $(cat "$gh_out") snapshot: $(cat "$CALL_OUT")"
  fi
  if [ "$#" -eq 1 ]; then
    node_out="$(jq -c '.[0]' "$input")" || setup_fail "gh node $case_name"
    gh_call "gh:$case_name:fetch" hivemind_readiness_fetch_snapshot "$SNAP_REPO_ARG" "$1"
    expect_call "gh:$case_name:fetch" 0 "$node_out"$'\n' ""
    expect_no_git "gh:$case_name:fetch"
  fi
}

# run_gh_token_case <case-name> <token> <number>...: runs a failing gh mode case and asserts its
# token, empty stdout and gh calls; a one-number case also runs the fetch alone.
run_gh_token_case() {
  local case_name="$1" token="$2"
  shift 2
  gh_call "gh:$case_name" hivemind_readiness_check_gh "$SNAP_COMMIT" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG" "$@"
  expect_call "gh:$case_name" 2 "" "readiness-check-error: $token"$'\n'
  expect_gh_argv "gh:$case_name" "$@"
  if [ "$#" -eq 1 ]; then
    gh_call "gh:$case_name:fetch" hivemind_readiness_fetch_snapshot "$SNAP_REPO_ARG" "$1"
    expect_call "gh:$case_name:fetch" 2 "" "readiness-check-error: $token"$'\n'
    expect_gh_argv "gh:$case_name:fetch" "$1"
  fi
}

test_gh_cases() {
  local count index case_file case_name commit_case token commit_file
  local -a numbers=()
  count="$(jq 'length' "$GH_CASES")" || setup_fail "cannot count gh cases"
  for ((index = 0; index < count; index++)); do
    case_file="$TMPDIR_TEST/gh-case.$index"
    jq -c --argjson i "$index" '.[$i]' "$GH_CASES" >"$case_file" || setup_fail "gh case file $index"
    {
      IFS= read -r case_name && IFS= read -r commit_case && IFS= read -r token
    } < <(jq -r '.name, (.commit // ""), (.token // "")' "$case_file") || setup_fail "gh case fields $index"
    mapfile -t numbers < <(jq -r '.numbers[]' "$case_file")
    serve_gh_case "$case_file"
    SNAP_COMMIT="$BASE_COMMIT"
    if [ -n "$commit_case" ]; then
      commit_file="$TMPDIR_TEST/gh-commit.$index"
      jq -c --arg name "$commit_case" 'first(.[] | select(.name == $name))' "$CASES" >"$commit_file" \
        || setup_fail "gh commit case $commit_case"
      build_case_commit SNAP_COMMIT "$commit_file"
    fi
    if [ -n "$token" ]; then
      run_gh_token_case "$case_name" "$token" "${numbers[@]}"
    else
      run_gh_lines_case "$case_name" "$case_file" "${numbers[@]}"
    fi
  done
  SNAP_COMMIT="$BASE_COMMIT"
}

# test_gh_page_info: gh mode holds each of the four connections to a pageInfo object with a
# boolean hasNextPage; a reply missing either, or with another type, is snapshot-malformed.
test_gh_page_info() {
  local connection change case_file index=0
  for connection in labels blockedBy subIssues parent.labels; do
    for change in del:pageInfo null:pageInfo empty:pageInfo del:hasNextPage null:hasNextPage \
      string:hasNextPage; do
      case_file="$(write_input "gh-page-info-$index" "$(jq -nc --arg c "$connection" --arg ch "$change" '
        ($c | split(".")) as $p
        | ($ch | split(":")) as [$kind, $field]
        | (if $field == "pageInfo" then $p + ["pageInfo"] else $p + ["pageInfo", "hasNextPage"] end) as $path
        | {numbers: [201], token: "snapshot-malformed",
           responses: {"201": ({issue: "slice-pass"}
             + if $kind == "del" then {del: [$path]}
               else {set: [{path: $path, value: ({"null": null, "empty": {}, "string": "false"}[$kind])}]} end)}}')")"
      index=$((index + 1))
      serve_gh_case "$case_file"
      run_gh_token_case "page-info:$connection:$change" snapshot-malformed 201
    done
  done
}

test_gh_absent() {
  local no_gh_dir="$TMPDIR_TEST/no-gh-bin" case_file tool
  mkdir -p "$no_gh_dir" || setup_fail "cannot create the no-gh PATH dir"
  ln -sf "$WRAP_DIR/git" "$no_gh_dir/git" || setup_fail "cannot link git"
  for tool in jq bash; do
    ln -sf "$(command -v "$tool")" "$no_gh_dir/$tool" || setup_fail "cannot link $tool"
  done
  case_file="$(write_input gh-absent-case \
    '{"responses": {"101": {"issue": "standalone-pass"}}}')"
  serve_gh_case "$case_file"
  LIB_PATH="$no_gh_dir"
  gh_call "gh:absent" hivemind_readiness_check_gh "$BASE_COMMIT" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG" 101
  expect_call "gh:absent" 2 "" $'readiness-check-error: gh-failed\n'
  expect_no_gh "gh:absent"
  gh_call "gh:absent:fetch" hivemind_readiness_fetch_snapshot "$SNAP_REPO_ARG" 101
  expect_call "gh:absent:fetch" 2 "" $'readiness-check-error: gh-failed\n'
  expect_no_gh "gh:absent:fetch"
  LIB_PATH="$WRAP_DIR:$PATH"
  gh_call "gh:present" hivemind_readiness_check_gh "$BASE_COMMIT" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG" 101
  if [ "$CALL_RC" = 0 ] && [ -s "$CALL_OUT" ]; then
    pass "gh:present" "the same call passes with the gh stub on PATH"
  else
    failed "gh:present" "rc $CALL_RC, stderr: $(cat "$CALL_ERR")"
  fi
}

test_gh_arguments() {
  local entry case_file
  case_file="$(write_input gh-args-case '{"responses": {"101": {"issue": "standalone-pass"}}}')"
  serve_gh_case "$case_file"
  for entry in 0 01 -1 +1 1a '' ' 1' '1 ' $'1\n' 1.0 0x1 '٣' x; do
    gh_call "gh:bad-number" hivemind_readiness_check_gh "$BASE_COMMIT" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG" "$entry"
    expect_call "gh:bad-number:$(printf '%q' "$entry")" 2 "" $'readiness-check-error: usage\n'
    expect_no_gh "gh:bad-number:$(printf '%q' "$entry")"
    expect_no_git "gh:bad-number:$(printf '%q' "$entry")"
    gh_call "gh:fetch-bad-number" hivemind_readiness_fetch_snapshot "$SNAP_REPO_ARG" "$entry"
    expect_call "gh:fetch-bad-number:$(printf '%q' "$entry")" 2 "" $'readiness-check-error: usage\n'
    expect_no_gh "gh:fetch-bad-number:$(printf '%q' "$entry")"
  done
  gh_call "gh:bad-second-number" hivemind_readiness_check_gh "$BASE_COMMIT" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG" 101 0
  expect_call "gh:bad-second-number" 2 "" $'readiness-check-error: usage\n'
  expect_no_gh "gh:bad-second-number"
  expect_no_git "gh:bad-second-number"
  for entry in '' brenpike -x/y x/.y x/y/z 'x/y..z' 'x y/z' $'x/y\n' 'x/y;z'; do
    gh_call "gh:bad-owner-repo" hivemind_readiness_check_gh "$BASE_COMMIT" "$entry" "$SNAP_TRUNK_ARG" 101
    expect_call "gh:bad-owner-repo:$(printf '%q' "$entry")" 2 "" $'readiness-check-error: usage\n'
    expect_no_gh "gh:bad-owner-repo:$(printf '%q' "$entry")"
    expect_no_git "gh:bad-owner-repo:$(printf '%q' "$entry")"
    gh_call "gh:fetch-bad-owner-repo" hivemind_readiness_fetch_snapshot "$entry" 101
    expect_call "gh:fetch-bad-owner-repo:$(printf '%q' "$entry")" 2 "" $'readiness-check-error: usage\n'
    expect_no_gh "gh:fetch-bad-owner-repo:$(printf '%q' "$entry")"
  done
  for entry in '' -main 'a..b' 'main;x'; do
    gh_call "gh:bad-trunk" hivemind_readiness_check_gh "$BASE_COMMIT" "$SNAP_REPO_ARG" "$entry" 101
    expect_call "gh:bad-trunk:$(printf '%q' "$entry")" 2 "" $'readiness-check-error: usage\n'
    expect_no_gh "gh:bad-trunk:$(printf '%q' "$entry")"
    expect_no_git "gh:bad-trunk:$(printf '%q' "$entry")"
  done
  gh_call "gh:malformed-commit" hivemind_readiness_check_gh HEAD "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG" 101
  expect_call "gh:malformed-commit" 2 "" $'readiness-check-error: commit-malformed\n'
  expect_no_gh "gh:malformed-commit"
  expect_no_git "gh:malformed-commit"
  gh_call "gh:no-number" hivemind_readiness_check_gh "$BASE_COMMIT" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG"
  expect_call "gh:no-number" 2 "" $'readiness-check-error: usage\n'
  expect_no_gh "gh:no-number"
  expect_no_git "gh:no-number"
  gh_call "gh:fetch-one-arg" hivemind_readiness_fetch_snapshot "$SNAP_REPO_ARG"
  expect_call "gh:fetch-one-arg" 2 "" $'readiness-check-error: usage\n'
  expect_no_gh "gh:fetch-one-arg"
  gh_call "gh:fetch-three-args" hivemind_readiness_fetch_snapshot "$SNAP_REPO_ARG" 101 101
  expect_call "gh:fetch-three-args" 2 "" $'readiness-check-error: usage\n'
  expect_no_gh "gh:fetch-three-args"
  gh_call "gh:unknown-commit" hivemind_readiness_check_gh "$(printf '%040d' 0)" "$SNAP_REPO_ARG" "$SNAP_TRUNK_ARG" 101
  expect_call "gh:unknown-commit" 2 "" $'readiness-check-error: commit-unresolvable\n'
  expect_no_gh "gh:unknown-commit"
  expect_git_flags "gh:unknown-commit"
}

test_jq_defs() {
  local want_file="$TMPDIR_TEST/jq-defs.want" parsed=""
  bash -c '. "$1"; _hivemind_rc_jq_defs; _hivemind_rc_doc_jq_defs' jq-defs "$LIB" >"$want_file" \
    || setup_fail "cannot print the private jq definitions"
  lib_call "jq-defs" "$REPO" "$NO_INPUT" hivemind_readiness_jq_defs
  if [ "$CALL_RC" = 0 ] && [ -s "$CALL_OUT" ] && cmp -s "$CALL_OUT" "$want_file" && [ ! -s "$CALL_ERR" ]; then
    pass "jq-defs:accessor" "shared then document-layer definitions, in order"
  else
    failed "jq-defs:accessor" "rc $CALL_RC, stdout differs from the private definitions or stderr not empty"
  fi
  expect_no_git "jq-defs"
  parsed="$(printf 'a\r\n# T\n\n**UI:** yes\n' | jq -Rsr "$(cat "$CALL_OUT")"'
{texts: rc_lines} | rc_prd_ui' 2>&1)" || parsed="jq failed: $parsed"
  if [ "$parsed" = yes ]; then
    pass "jq-defs:compiles" "a caller program built on the definitions runs"
  else
    failed "jq-defs:compiles" "$parsed"
  fi
  lib_call "jq-defs:usage" "$REPO" "$NO_INPUT" hivemind_readiness_jq_defs extra
  expect_call "jq-defs:usage" 2 "" $'readiness-check-error: usage\n'
  expect_no_git "jq-defs:usage"
}

test_library_form
test_jq_defs
test_codes
test_commit_forms
test_doc_entry
test_doc_read
test_sha256_repo
test_seed_marker
test_record_front_matter
test_path_kind
test_snapshot_cases
test_snapshot_multi
test_snapshot_failures
test_snapshot_subdirectory
test_snapshot_git_failure
test_snapshot_large_design
test_snapshot_no_gh
test_snapshot_code_bases
test_gh_query_constant
test_gh_cases
test_gh_page_info
test_gh_absent
test_gh_arguments

# ── Summary ───────────────────────────────────────────────────────────────────────
echo
echo "readiness-check: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
