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
# flags on every call.
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
# a fresh bash under <prelude>; prints its exit status.
run_lib_mode() {
  local prelude="$1" cwd="$2" in_file="$3" out_file="$4" err_file="$5" status=0
  shift 5
  (
    cd "$cwd" || exit 97
    PATH="$WRAP_DIR:$PATH" RC_TEST_GIT_LOG="$GIT_LOG" RC_TEST_REAL_GIT="$REAL_GIT" \
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

test_library_form
test_codes
test_commit_forms
test_doc_entry
test_doc_read
test_sha256_repo
test_seed_marker
test_record_front_matter
test_path_kind

# ── Summary ───────────────────────────────────────────────────────────────────────
echo
echo "readiness-check: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
