# shellcheck shell=bash
#
# Checked scratch paths for tools/ scripts. A bare `X="$(mktemp -d)"` leaves X empty when mktemp
# fails, so later writes, and a cleanup trap's `rm -rf`, aim at the filesystem root. These helpers
# assign the variable only from a fresh, empty, non-symlink path whose full path resolves.
#
#   make_scratch_dir <var> [<template>]    runs `mktemp -d [<template>]`
#   make_scratch_file <var> [<template>]   runs `mktemp [<template>]`
#
# The template, when given, is passed to mktemp as given (a template with no folder is created in
# the working directory). On success <var> holds the resolved absolute path (`pwd -P` of the
# folder, or of the file's parent folder plus the file name). <var> is assigned only when mktemp
# exited 0 and printed a non-empty path that is a directory (file form: a regular file), is not a
# symlink, is empty, and resolves. Any other result prints `FAIL: ...` to stderr and exits 2,
# leaving <var> untouched. A <var> that is not a shell identifier, or that starts with the reserved
# local prefix `__scratch_`, also exits 2. The helpers never remove anything, never set shell
# options and print nothing to stdout.
#
# Caller contract:
#   - source with `. "$SCRIPT_DIR/lib/scratch.sh" || exit 2`
#   - call as a bare statement in the shell that uses the variable, never inside $( ); a call in a
#     subshell exits only that subshell and assigns nothing the parent sees
#   - arm the cleanup trap only after the call, so a failed call exits before any cleanup can run

# make_scratch_dir <var> [<template>]: assigns <var> a fresh, empty, resolved scratch folder.
make_scratch_dir() { _scratch_create_checked dir "$@"; }

# make_scratch_file <var> [<template>]: assigns <var> a fresh, empty, resolved scratch file.
make_scratch_file() { _scratch_create_checked file "$@"; }

# _scratch_fail <message>: prints `FAIL: <message>` to stderr and exits 2.
_scratch_fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 2
}

# _scratch_create_checked <dir|file> <var> [<template>]: the shared body of the two helpers.
# INVARIANT: every local name starts with `__scratch_`, and <var> may not, so `printf -v` always
# reaches the caller's variable (a caller's local included) and never one of these locals.
_scratch_create_checked() {
  local __scratch_kind="$1"
  shift
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] \
    || _scratch_fail "make_scratch_$__scratch_kind: usage: make_scratch_$__scratch_kind <var> [<template>]"
  local __scratch_var="$1"
  [[ "$__scratch_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || _scratch_fail "make_scratch_$__scratch_kind: not a shell variable name: $__scratch_var"
  [[ "$__scratch_var" != __scratch_* ]] \
    || _scratch_fail "make_scratch_$__scratch_kind: variable name uses the reserved prefix __scratch_: $__scratch_var"

  local -a __scratch_args=()
  [ "$__scratch_kind" = dir ] && __scratch_args+=(-d)
  [ "$#" -eq 2 ] && __scratch_args+=("$2")

  local __scratch_raw
  if ! __scratch_raw="$(mktemp ${__scratch_args[@]+"${__scratch_args[@]}"})"; then
    _scratch_fail "make_scratch_$__scratch_kind: mktemp failed"
  fi
  [ -n "$__scratch_raw" ] || _scratch_fail "make_scratch_$__scratch_kind: mktemp printed no path"
  [ ! -L "$__scratch_raw" ] || _scratch_fail "make_scratch_$__scratch_kind: mktemp gave a symlink: $__scratch_raw"

  local __scratch_resolved __scratch_listing __scratch_parent
  if [ "$__scratch_kind" = dir ]; then
    [ -d "$__scratch_raw" ] || _scratch_fail "make_scratch_dir: mktemp gave no directory: $__scratch_raw"
    __scratch_listing="$(ls -A -- "$__scratch_raw")" \
      || _scratch_fail "make_scratch_dir: cannot list the scratch directory: $__scratch_raw"
    [ -z "$__scratch_listing" ] || _scratch_fail "make_scratch_dir: mktemp gave a non-empty directory: $__scratch_raw"
    __scratch_resolved="$(CDPATH='' cd -- "$__scratch_raw" && pwd -P)" && [ -n "$__scratch_resolved" ] \
      && [ -d "$__scratch_resolved" ] \
      || _scratch_fail "make_scratch_dir: cannot resolve the scratch directory: $__scratch_raw"
  else
    [ -f "$__scratch_raw" ] || _scratch_fail "make_scratch_file: mktemp gave no regular file: $__scratch_raw"
    [ ! -s "$__scratch_raw" ] || _scratch_fail "make_scratch_file: mktemp gave a non-empty file: $__scratch_raw"
    __scratch_parent="$(dirname -- "$__scratch_raw")" \
      && __scratch_parent="$(CDPATH='' cd -- "$__scratch_parent" && pwd -P)" && [ -n "$__scratch_parent" ] \
      || _scratch_fail "make_scratch_file: cannot resolve the scratch file's folder: $__scratch_raw"
    __scratch_resolved="${__scratch_parent%/}/$(basename -- "$__scratch_raw")"
    [ -f "$__scratch_resolved" ] && [ ! -L "$__scratch_resolved" ] \
      || _scratch_fail "make_scratch_file: cannot resolve the scratch file: $__scratch_raw"
  fi

  printf -v "$__scratch_var" '%s' "$__scratch_resolved"
}
