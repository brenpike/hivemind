#!/usr/bin/env bash
#
# Behavior test runner for the checked scratch-path helper tools/lib/scratch.sh:
#   make_scratch_dir <var> [<template>] and make_scratch_file <var> [<template>].
#
# OFFLINE bash TEST: needs only bash and coreutils. Each case sources the REAL helper and calls it
# in a subshell whose PATH puts one fake-tool dir first. A fake `mktemp` either prints a fixed
# path and exits a fixed code, or logs its arguments and runs the real mktemp. An EXIT trap armed
# before the call records whether the variable was set, so a failed call that exits the subshell
# still reports the variable's state.
#
# Covered, for both forms: mktemp failing; mktemp failing while printing an existing decoy; exit
# 0 with empty output; a path of the wrong kind or a missing path; a symlink; a non-empty decoy; a
# bad variable name or argument count. Each must exit 2 with `FAIL: ` on stderr and nothing on
# stdout, leave the variable unset, and leave every decoy and its file intact. Success must assign
# the canonical (`pwd -P`) empty path, reach a caller's local, honor the template (and pass none
# when none is given), set no shell option and print nothing. A sample caller that arms
# `trap 'rm -rf'` after the helper must leave the decoy untouched on failure, and a failed call in
# a subshell under `set -e` must stop the parent with exit 2.
#
# Mirrors tools/test_run_review.sh's pass/fail counter and exit-nonzero-on-any-fail convention.
# Its own scratch folder is made through the helper; the only writes are under it, removed on EXIT.
#
# Usage:
#   ./tools/test_scratch.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HELPER="$SCRIPT_DIR/lib/scratch.sh"
[ -f "$HELPER" ] || { echo "FAIL: required input missing: $HELPER" >&2; exit 2; }
# shellcheck source=lib/scratch.sh
. "$HELPER" || exit 2

make_scratch_dir SCRATCH "${TMPDIR:-/tmp}/hivemind-scratch-test.XXXXXX"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

REAL_MKTEMP="$(type -P mktemp)" || { echo "FAIL: mktemp is not an executable on PATH" >&2; exit 2; }
DECOYS="$SCRATCH/decoys"
CASES="$SCRATCH/cases"
FAKES="$SCRATCH/fakes"
SENTINEL_TEXT='DECOY_SENTINEL_CONTENT'
mkdir -p "$DECOYS" "$CASES" "$FAKES" "$SCRATCH/tmp" || exit 2
export TMPDIR="$SCRATCH/tmp"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# assert_check <name> <description> <command...>: PASS when the command succeeds.
assert_check() {
  local check_name="$1" description="$2"
  shift 2
  if "$@"; then
    pass "$check_name" "$description"
  else
    failed "$check_name" "$description"
  fi
}

# ── Fakes and decoys ─────────────────────────────────────────────────────────

# write_fake_mktemp <bin dir> <printed path> <exit code>: a fake mktemp that logs its arguments,
# prints <printed path> (nothing when empty) and exits <exit code>.
write_fake_mktemp() {
  local bin_dir="$1" printed_path="$2" exit_code="$3"
  mkdir -p "$bin_dir" || return 1
  cat >"$bin_dir/mktemp" <<STUB || return 1
#!/usr/bin/env bash
printf '[%s]' "\$@" >>$(printf '%q' "$bin_dir/calls.log")
printf '\n' >>$(printf '%q' "$bin_dir/calls.log")
[ -z $(printf '%q' "$printed_path") ] || printf '%s\n' $(printf '%q' "$printed_path")
exit $exit_code
STUB
  chmod +x "$bin_dir/mktemp"
}

# write_logging_mktemp <bin dir>: a fake mktemp that logs its arguments and runs the real mktemp.
write_logging_mktemp() {
  local bin_dir="$1"
  mkdir -p "$bin_dir" || return 1
  cat >"$bin_dir/mktemp" <<STUB || return 1
#!/usr/bin/env bash
printf '[%s]' "\$@" >>$(printf '%q' "$bin_dir/calls.log")
printf '\n' >>$(printf '%q' "$bin_dir/calls.log")
exec $(printf '%q' "$REAL_MKTEMP") "\$@"
STUB
  chmod +x "$bin_dir/mktemp"
}

# make_decoy_dir <name>: an existing folder holding one sentinel file; prints its path.
make_decoy_dir() {
  local decoy="$DECOYS/$1"
  mkdir -p "$decoy" && printf '%s\n' "$SENTINEL_TEXT" >"$decoy/sentinel" || return 1
  printf '%s\n' "$decoy"
}

# make_decoy_file <name>: an existing file holding the sentinel text; prints its path.
make_decoy_file() {
  local decoy="$DECOYS/$1"
  printf '%s\n' "$SENTINEL_TEXT" >"$decoy" || return 1
  printf '%s\n' "$decoy"
}

# decoy_dir_intact <dir>: the folder and its sentinel file still exist, the sentinel unchanged.
decoy_dir_intact() { [ -d "$1" ] && [ -f "$1/sentinel" ] && [ "$(cat "$1/sentinel")" = "$SENTINEL_TEXT" ]; }

# decoy_file_intact <file>: the file still exists with the sentinel text unchanged.
decoy_file_intact() { [ -f "$1" ] && [ "$(cat "$1")" = "$SENTINEL_TEXT" ]; }

# path_is_absent <path>: nothing, not even a dangling symlink, exists at <path>.
path_is_absent() { [ ! -e "$1" ] && [ ! -L "$1" ]; }

# ── Probe runner ─────────────────────────────────────────────────────────────

# record_probe_var <record file> <var>: writes `set:<value>` when <var> is a set shell variable,
# else `unset`.
record_probe_var() {
  if [[ "$2" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ -n "${!2+x}" ]; then
    printf 'set:%s' "${!2}" >"$1"
  else
    printf 'unset' >"$1"
  fi
}

# run_probe <case> <dir|file> <bin dir or empty> <helper args...>: calls make_scratch_<kind> with
# <helper args> in a subshell with <bin dir> first on PATH and the variable unset. Sets
# PROBE_STATUS, PROBE_DIR (holding stdout, stderr and var) and PROBE_VAR (the var record).
run_probe() {
  local case_name="$1" kind="$2" bin_dir="$3"
  shift 3
  PROBE_DIR="$CASES/$case_name"
  mkdir -p "$PROBE_DIR" || return 1
  PROBE_STATUS=0
  (
    [ -z "$bin_dir" ] || PATH="$bin_dir:$PATH"
    [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && unset "$1"
    trap 'record_probe_var "$PROBE_DIR/var" "${1:-}"' EXIT
    "make_scratch_$kind" "$@"
  ) >"$PROBE_DIR/stdout" 2>"$PROBE_DIR/stderr" || PROBE_STATUS=$?
  PROBE_VAR="$(cat "$PROBE_DIR/var")"
}

# assert_probe_failed <case> <description>: the last probe exited 2, printed nothing on stdout,
# printed a `FAIL: ` line on stderr and left the variable unset.
assert_probe_failed() {
  local stderr_text
  stderr_text="$(cat "$PROBE_DIR/stderr")"
  if [ "$PROBE_STATUS" -eq 2 ] && [ ! -s "$PROBE_DIR/stdout" ] && [[ "$stderr_text" == 'FAIL: '* ]] \
    && [ "$PROBE_VAR" = unset ]; then
    pass "$1" "$2"
  else
    failed "$1" "$2 (status=$PROBE_STATUS var=$PROBE_VAR stderr=$stderr_text)"
  fi
}

# probe_stderr_has <text>: the last probe's stderr contains <text>.
probe_stderr_has() { grep -qF -- "$1" "$PROBE_DIR/stderr"; }

# probe_made_canonical <dir|file> <expected glob>: the last probe exited 0, printed nothing, and
# assigned an absolute path matching <expected glob> that is its own `pwd -P` form, not a symlink,
# and an empty folder (dir) or empty regular file (file).
probe_made_canonical() {
  local kind="$1" expected_glob="$2" made_path resolved_parent
  [ "$PROBE_STATUS" -eq 0 ] && [ ! -s "$PROBE_DIR/stdout" ] && [ ! -s "$PROBE_DIR/stderr" ] || return 1
  [[ "$PROBE_VAR" == set:* ]] || return 1
  made_path="${PROBE_VAR#set:}"
  # shellcheck disable=SC2053
  [[ "$made_path" == /* ]] && [[ "$made_path" == $expected_glob ]] && [ ! -L "$made_path" ] || return 1
  if [ "$kind" = dir ]; then
    [ -d "$made_path" ] && [ -z "$(ls -A -- "$made_path")" ] \
      && [ "$(cd -- "$made_path" && pwd -P)" = "$made_path" ]
  else
    resolved_parent="$(cd -- "$(dirname -- "$made_path")" && pwd -P)" || return 1
    [ -f "$made_path" ] && [ ! -s "$made_path" ] \
      && [ "$resolved_parent/$(basename -- "$made_path")" = "$made_path" ]
  fi
}

# fake_calls_are <bin dir> <expected log>: the fake mktemp's argument log equals <expected log>.
fake_calls_are() { [ "$(cat "$1/calls.log" 2>/dev/null)" = "$2" ]; }

# ── Failure: mktemp fails ────────────────────────────────────────────────────

for kind in dir file; do
  bin_dir="$FAKES/fail-$kind"
  write_fake_mktemp "$bin_dir" '' 1 || exit 2
  run_probe "fail-$kind" "$kind" "$bin_dir" OUT
  assert_probe_failed "$kind:mktemp-fail" "mktemp exits 1: exit 2, FAIL on stderr, variable unset"
  assert_check "$kind:mktemp-fail-reason" "the FAIL line names the mktemp failure" probe_stderr_has 'mktemp failed'
done

# ── Failure: mktemp fails while printing an existing decoy ──────────────────

bin_dir="$FAKES/fail-decoy-dir"
DECOY="$(make_decoy_dir fail-decoy-dir)" || exit 2
write_fake_mktemp "$bin_dir" "$DECOY" 1 || exit 2
run_probe fail-decoy-dir dir "$bin_dir" OUT
assert_probe_failed "dir:fail-decoy" "mktemp exits 1 printing a decoy folder: exit 2, variable unset"
assert_check "dir:fail-decoy-intact" "the decoy folder and its file survive" decoy_dir_intact "$DECOY"

bin_dir="$FAKES/fail-decoy-file"
DECOY="$(make_decoy_file fail-decoy-file)" || exit 2
write_fake_mktemp "$bin_dir" "$DECOY" 1 || exit 2
run_probe fail-decoy-file file "$bin_dir" OUT
assert_probe_failed "file:fail-decoy" "mktemp exits 1 printing a decoy file: exit 2, variable unset"
assert_check "file:fail-decoy-intact" "the decoy file survives" decoy_file_intact "$DECOY"

# ── Failure: exit 0 with empty output ────────────────────────────────────────

for kind in dir file; do
  bin_dir="$FAKES/empty-$kind"
  write_fake_mktemp "$bin_dir" '' 0 || exit 2
  run_probe "empty-$kind" "$kind" "$bin_dir" OUT
  assert_probe_failed "$kind:empty-output" "mktemp exits 0 printing nothing: exit 2, variable unset"
  assert_check "$kind:empty-output-reason" "the FAIL line names the missing path" probe_stderr_has 'printed no path'
done

# ── Failure: a path of the wrong kind, or a missing path ────────────────────

bin_dir="$FAKES/wrong-kind-dir"
DECOY="$(make_decoy_file wrong-kind-dir)" || exit 2
write_fake_mktemp "$bin_dir" "$DECOY" 0 || exit 2
run_probe wrong-kind-dir dir "$bin_dir" OUT
assert_probe_failed "dir:not-a-directory" "mktemp -d printing a regular file: exit 2, variable unset"
assert_check "dir:not-a-directory-reason" "the FAIL line names the missing folder" probe_stderr_has 'mktemp gave no directory'
assert_check "dir:not-a-directory-intact" "the decoy file survives" decoy_file_intact "$DECOY"

bin_dir="$FAKES/wrong-kind-file"
DECOY="$(make_decoy_dir wrong-kind-file)" || exit 2
write_fake_mktemp "$bin_dir" "$DECOY" 0 || exit 2
run_probe wrong-kind-file file "$bin_dir" OUT
assert_probe_failed "file:not-a-file" "mktemp printing a folder: exit 2, variable unset"
assert_check "file:not-a-file-reason" "the FAIL line names the missing file" probe_stderr_has 'mktemp gave no regular file'
assert_check "file:not-a-file-intact" "the decoy folder and its file survive" decoy_dir_intact "$DECOY"

for kind in dir file; do
  bin_dir="$FAKES/missing-$kind"
  missing_path="$DECOYS/missing-$kind"
  write_fake_mktemp "$bin_dir" "$missing_path" 0 || exit 2
  run_probe "missing-$kind" "$kind" "$bin_dir" OUT
  assert_probe_failed "$kind:missing-path" "mktemp printing a path that does not exist: exit 2, variable unset"
  assert_check "$kind:missing-path-not-made" "the helper creates nothing at the printed path" \
    path_is_absent "$missing_path"
done

# ── Failure: a symlink ───────────────────────────────────────────────────────

bin_dir="$FAKES/symlink-dir"
DECOY="$(make_decoy_dir symlink-dir-target)" || exit 2
ln -s "$DECOY" "$DECOYS/symlink-dir" || exit 2
write_fake_mktemp "$bin_dir" "$DECOYS/symlink-dir" 0 || exit 2
run_probe symlink-dir dir "$bin_dir" OUT
assert_probe_failed "dir:symlink" "mktemp -d printing a symlink to a folder: exit 2, variable unset"
assert_check "dir:symlink-reason" "the FAIL line names the symlink" probe_stderr_has 'mktemp gave a symlink'
assert_check "dir:symlink-intact" "the link, its target folder and the file survive" \
  eval '[ -L "$DECOYS/symlink-dir" ] && decoy_dir_intact "$DECOY"'

bin_dir="$FAKES/symlink-file"
DECOY="$(make_decoy_file symlink-file-target)" || exit 2
ln -s "$DECOY" "$DECOYS/symlink-file" || exit 2
write_fake_mktemp "$bin_dir" "$DECOYS/symlink-file" 0 || exit 2
run_probe symlink-file file "$bin_dir" OUT
assert_probe_failed "file:symlink" "mktemp printing a symlink to a file: exit 2, variable unset"
assert_check "file:symlink-reason" "the FAIL line names the symlink" probe_stderr_has 'mktemp gave a symlink'
assert_check "file:symlink-intact" "the link and its target file survive" \
  eval '[ -L "$DECOYS/symlink-file" ] && decoy_file_intact "$DECOY"'

# ── Failure: a non-empty decoy ───────────────────────────────────────────────

bin_dir="$FAKES/non-empty-dir"
DECOY="$(make_decoy_dir non-empty-dir)" || exit 2
write_fake_mktemp "$bin_dir" "$DECOY" 0 || exit 2
run_probe non-empty-dir dir "$bin_dir" OUT
assert_probe_failed "dir:non-empty" "mktemp -d exits 0 printing a non-empty folder: exit 2, variable unset"
assert_check "dir:non-empty-intact" "the decoy folder and its file survive" decoy_dir_intact "$DECOY"

bin_dir="$FAKES/non-empty-file"
DECOY="$(make_decoy_file non-empty-file)" || exit 2
write_fake_mktemp "$bin_dir" "$DECOY" 0 || exit 2
run_probe non-empty-file file "$bin_dir" OUT
assert_probe_failed "file:non-empty" "mktemp exits 0 printing a non-empty file: exit 2, variable unset"
assert_check "file:non-empty-intact" "the decoy file survives" decoy_file_intact "$DECOY"

# ── Failure: a bad variable name or argument count ──────────────────────────

bad_name_index=0
for kind in dir file; do
  for bad_name in '' '1abc' 'a-b' 'x y' 'OUT[0]' '__scratch_var' '__scratch_raw'; do
    bad_name_index=$((bad_name_index + 1))
    bin_dir="$FAKES/bad-name-$kind-$bad_name_index"
    write_logging_mktemp "$bin_dir" || exit 2
    run_probe "bad-name-$kind-$bad_name_index" "$kind" "$bin_dir" "$bad_name"
    assert_probe_failed "$kind:bad-name-$bad_name_index" "variable name '$bad_name' is rejected: exit 2, variable unset"
    assert_check "$kind:bad-name-$bad_name_index-no-mktemp" "mktemp never runs for variable name '$bad_name'" \
      path_is_absent "$bin_dir/calls.log"
  done

  bin_dir="$FAKES/no-args-$kind"
  write_logging_mktemp "$bin_dir" || exit 2
  run_probe "no-args-$kind" "$kind" "$bin_dir"
  assert_probe_failed "$kind:no-args" "no arguments: exit 2"
  assert_check "$kind:no-args-no-mktemp" "mktemp never runs with no arguments" path_is_absent "$bin_dir/calls.log"

  bin_dir="$FAKES/three-args-$kind"
  write_logging_mktemp "$bin_dir" || exit 2
  run_probe "three-args-$kind" "$kind" "$bin_dir" OUT "$SCRATCH/tmp/x.XXXXXX" extra
  assert_probe_failed "$kind:three-args" "three arguments: exit 2, variable unset"
  assert_check "$kind:three-args-no-mktemp" "mktemp never runs with three arguments" path_is_absent "$bin_dir/calls.log"
done

# ── Success: canonical empty path, template honored ─────────────────────────

mkdir -p "$SCRATCH/real" && ln -s real "$SCRATCH/link" || exit 2

bin_dir="$FAKES/ok-dir-default"
write_logging_mktemp "$bin_dir" || exit 2
run_probe ok-dir-default dir "$bin_dir" OUT
assert_check "dir:ok-default" "no template: an empty, canonical folder under TMPDIR, nothing printed" \
  probe_made_canonical dir "$SCRATCH/tmp/*"
assert_check "dir:ok-default-args" "no template: mktemp gets only -d" fake_calls_are "$bin_dir" '[-d]'

bin_dir="$FAKES/ok-dir-template"
write_logging_mktemp "$bin_dir" || exit 2
run_probe ok-dir-template dir "$bin_dir" OUT "$SCRATCH/link/made-dir.XXXXXX"
assert_check "dir:ok-template" "a template under a symlinked folder: the resolved folder path is assigned" \
  probe_made_canonical dir "$SCRATCH/real/made-dir.??????"
assert_check "dir:ok-template-args" "the template is passed to mktemp -d as given" \
  fake_calls_are "$bin_dir" "[-d][$SCRATCH/link/made-dir.XXXXXX]"

bin_dir="$FAKES/ok-file-default"
write_logging_mktemp "$bin_dir" || exit 2
run_probe ok-file-default file "$bin_dir" OUT
assert_check "file:ok-default" "no template: an empty, canonical file under TMPDIR, nothing printed" \
  probe_made_canonical file "$SCRATCH/tmp/*"
assert_check "file:ok-default-args" "no template: mktemp gets no arguments" fake_calls_are "$bin_dir" '[]'

bin_dir="$FAKES/ok-file-template"
write_logging_mktemp "$bin_dir" || exit 2
run_probe ok-file-template file "$bin_dir" OUT "$SCRATCH/link/made-file.XXXXXX"
assert_check "file:ok-template" "a template under a symlinked folder: the resolved file path is assigned" \
  probe_made_canonical file "$SCRATCH/real/made-file.??????"
assert_check "file:ok-template-args" "the template is passed to mktemp as given" \
  fake_calls_are "$bin_dir" "[$SCRATCH/link/made-file.XXXXXX]"

# ── Success: a caller's local, shell options ─────────────────────────────────

# assign_scratch_to_local <dir|file> <record file>: makes a scratch path into a local and records
# it.
assign_scratch_to_local() {
  local made_path
  "make_scratch_$1" made_path
  printf '%s' "$made_path" >"$2"
}

for kind in dir file; do
  local_record="$CASES/local-$kind"
  local_status=0
  (
    unset made_path
    assign_scratch_to_local "$kind" "$local_record"
    printf '%s' "${made_path-unset}" >"$local_record.global"
  ) || local_status=$?
  assert_check "$kind:ok-caller-local" "a caller's local receives the path and no global is set" \
    eval '[ "$local_status" -eq 0 ] && [ -s "$local_record" ] && [ "$(cat "$local_record.global")" = unset ] \
      && [ -e "$(cat "$local_record")" ]'
done

# record_shell_options <file>: writes the shell's option flags, set -o and shopt states to <file>.
record_shell_options() { { printf '%s\n' "$-"; set +o; shopt -p; } >"$1"; }

for kind in dir file; do
  options_status=0
  (
    record_shell_options "$CASES/options-$kind.before"
    "make_scratch_$kind" OUT
    record_shell_options "$CASES/options-$kind.after"
  ) || options_status=$?
  assert_check "$kind:ok-no-shell-options" "a successful call changes no shell option" \
    eval '[ "$options_status" -eq 0 ] && cmp -s "$CASES/options-$kind.before" "$CASES/options-$kind.after"'
done

# ── Sample callers ───────────────────────────────────────────────────────────

SAMPLE_CALLER="$SCRATCH/sample-caller.sh"
cat >"$SAMPLE_CALLER" <<'SAMPLE' || exit 2
#!/usr/bin/env bash
# sample-caller.sh <helper> <dir|file> <record file>: the caller contract with no set -e.
. "$1" || exit 2
"make_scratch_$2" WORK
trap 'rm -rf "$WORK"' EXIT
printf '%s' "$WORK" >"$3"
SAMPLE

SUBSHELL_CALLER="$SCRATCH/subshell-caller.sh"
cat >"$SUBSHELL_CALLER" <<'SAMPLE' || exit 2
#!/usr/bin/env bash
# subshell-caller.sh <helper>: a failed call in a subshell under set -e stops the parent.
set -e
. "$1" || exit 2
( make_scratch_dir WORK )
echo reached
SAMPLE

# run_sample_caller <case> <bin dir or empty> <script> <args...>: runs <script> with <bin dir>
# first on PATH. Sets SAMPLE_STATUS and SAMPLE_DIR (holding stdout and stderr).
run_sample_caller() {
  local case_name="$1" bin_dir="$2" sample_path="$3"
  shift 3
  SAMPLE_DIR="$CASES/$case_name"
  mkdir -p "$SAMPLE_DIR" || return 1
  SAMPLE_STATUS=0
  if [ -n "$bin_dir" ]; then
    PATH="$bin_dir:$PATH" bash "$sample_path" "$@" >"$SAMPLE_DIR/stdout" 2>"$SAMPLE_DIR/stderr" || SAMPLE_STATUS=$?
  else
    bash "$sample_path" "$@" >"$SAMPLE_DIR/stdout" 2>"$SAMPLE_DIR/stderr" || SAMPLE_STATUS=$?
  fi
}

bin_dir="$FAKES/sample-fail-dir"
DECOY="$(make_decoy_dir sample-fail-dir)" || exit 2
write_fake_mktemp "$bin_dir" "$DECOY" 1 || exit 2
run_sample_caller sample-fail-dir "$bin_dir" "$SAMPLE_CALLER" "$HELPER" dir "$CASES/sample-fail-dir.record"
assert_check "sample:dir-fail-exit" "a failed call stops the caller with exit 2 before its trap is armed" \
  eval '[ "$SAMPLE_STATUS" -eq 2 ] && path_is_absent "$CASES/sample-fail-dir.record"'
assert_check "sample:dir-fail-decoy-intact" "the caller's trap 'rm -rf' leaves the decoy folder and its file" \
  decoy_dir_intact "$DECOY"

bin_dir="$FAKES/sample-non-empty-dir"
DECOY="$(make_decoy_dir sample-non-empty-dir)" || exit 2
write_fake_mktemp "$bin_dir" "$DECOY" 0 || exit 2
run_sample_caller sample-non-empty-dir "$bin_dir" "$SAMPLE_CALLER" "$HELPER" dir "$CASES/sample-non-empty-dir.record"
assert_check "sample:dir-non-empty-exit" "a non-empty folder stops the caller with exit 2" \
  eval '[ "$SAMPLE_STATUS" -eq 2 ] && path_is_absent "$CASES/sample-non-empty-dir.record"'
assert_check "sample:dir-non-empty-decoy-intact" "the caller's trap 'rm -rf' leaves the decoy folder and its file" \
  decoy_dir_intact "$DECOY"

bin_dir="$FAKES/sample-fail-file"
DECOY="$(make_decoy_file sample-fail-file)" || exit 2
write_fake_mktemp "$bin_dir" "$DECOY" 1 || exit 2
run_sample_caller sample-fail-file "$bin_dir" "$SAMPLE_CALLER" "$HELPER" file "$CASES/sample-fail-file.record"
assert_check "sample:file-fail-exit" "a failed file call stops the caller with exit 2" \
  eval '[ "$SAMPLE_STATUS" -eq 2 ] && path_is_absent "$CASES/sample-fail-file.record"'
assert_check "sample:file-fail-decoy-intact" "the caller's trap 'rm -rf' leaves the decoy file" \
  decoy_file_intact "$DECOY"

for kind in dir file; do
  run_sample_caller "sample-ok-$kind" '' "$SAMPLE_CALLER" "$HELPER" "$kind" "$CASES/sample-ok-$kind.record"
  assert_check "sample:$kind-ok-cleaned" "a successful caller exits 0 and its trap removes the path it made" \
    eval '[ "$SAMPLE_STATUS" -eq 0 ] && [ -s "$CASES/sample-ok-$kind.record" ] \
      && path_is_absent "$(cat "$CASES/sample-ok-$kind.record")"'
done

bin_dir="$FAKES/subshell-fail"
write_fake_mktemp "$bin_dir" '' 1 || exit 2
run_sample_caller subshell-fail "$bin_dir" "$SUBSHELL_CALLER" "$HELPER"
assert_check "sample:subshell-set-e" "a failed call in a subshell under set -e stops the parent with exit 2" \
  eval '[ "$SAMPLE_STATUS" -eq 2 ] && [ ! -s "$SAMPLE_DIR/stdout" ]'

echo
echo "scratch helper tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
