# shellcheck shell=bash
#
# claude-mem-path.sh — shared claude-mem `CLAUDE_CODE_PATH` provisioning core (seed-hive).
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute
# path derived from its OWN script_dir (`. "$plugin_root/skills/_shared/claude-mem-path.sh"`).
# It defines functions only; it runs no top-level statements and changes no caller state
# beyond defining the functions below. `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately
# OMITS the P18 shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced
# file mutates the SOURCING shell's option state, so installing those here would corrupt
# every caller's shell; the floor is therefore the documented exception, not the full
# `set -euo pipefail`. This file carries no top-level `set` at all (pure function
# definitions); each caller owns its own `set -u` and error routing. Allowlisted under
# CHECK13 as a P18 documented exception.
#
# SINGLE RESPONSIBILITY: provision claude-mem's OWN `CLAUDE_CODE_PATH` setting (seed-hive
# SKILL.md step 11). This is DISTINCT from settings-merge.sh (which is a pure, I/O-free merge
# of the PROJECT `.claude/settings.json`): this lib resolves the `claude` binary path
# dynamically and performs a conditional, never-clobber, malformed-safe single-key write into
# claude-mem's OWN config in the user's HOME (`~/.claude-mem/settings.json`). It touches NO
# project file, NO other claude-mem key, and resolves no project root.
#
# WHY THIS LIB WRITES (vs settings-merge.sh which returns a string): the never-clobber +
# malformed-safe + preserve-every-other-key semantics REQUIRE reading the target file to decide
# whether to write at all (file-missing → skipped; key non-empty → already set; malformed →
# skipped). The decision and the application are inseparable from the read, and the target is a
# single FIXED file (claude-mem's OWN config), not a project artifact the entrypoint marshals.
# So the self-contained provisioning op — read, decide, write — lives here as ONE function. The
# entrypoint passes the target path + HOME (so the op is testable against a tmp HOME) and the
# resolved-or-resolvable binary, and consumes the in-band status word. This is the cleanest
# split given the semantics: a "return a decision, caller applies" shape would force the
# entrypoint to re-implement the read + malformed guard, duplicating the exact logic this lib
# exists to own (P1: one home for the rule).
#
# DATA-BOUNDARY: the resolved binary path enters jq as an inert `--arg` binding, NEVER
# interpolated into the jq program source. The target file is parsed via jq (`-e`), which
# validates it; malformed input is reported and NEVER partially written.
#
# DYNAMIC BINARY RESOLUTION (mirror SKILL.md step 11e, EXACT order):
#   (1) `command -v claude` — but only when it reports a REAL executable file. `command -v` can
#       resolve to a shell alias/function name rather than an executable path; the result is
#       accepted only when `test -x` passes on it. Otherwise resolution CONTINUES to the
#       fallbacks (it is not treated as found).
#   (2) `$HOME/.local/bin/claude` — accepted when `test -x` passes.
#   (3) `$HOME/.claude/local/claude` — accepted when `test -x` passes.
#   The first candidate that resolves to an executable wins. `~` is expanded at RUNTIME via
#   `$HOME` (never a hard-coded home path). If NONE resolve → the provisioning op reports
#   `skipped (claude binary not found)` and writes NOTHING.
#
# CONDITIONAL NEVER-CLOBBER WRITE (mirror SKILL.md step 11b-f, EXACT wording):
#   - target file MISSING            → `skipped (claude-mem not installed)`, write NOTHING.
#   - target NOT valid JSON          → `skipped (malformed json)`, write NOTHING, file unchanged.
#   - `CLAUDE_CODE_PATH` PRESENT (a NON-EMPTY string, OR a non-string value — boolean/null/
#     number/object/array) → `already set`, write NOTHING (never overwrite a user-provided value,
#     even a now-invalid one). A present non-string is PRESENT-MALFORMED and is treated as
#     never-clobber-skip, NOT clobbered. An explicitly-present JSON null counts as PRESENT here
#     (a literal null is a user-provided value), so it too is skipped — it is NOT treated as ABSENT.
#   - `CLAUDE_CODE_PATH` ABSENT (key MISSING or an EMPTY string `""`) → resolve the binary; if
#     none → `skipped (claude binary not found)`; otherwise set ONLY that key (every other key
#     preserved byte-for-byte via jq's structural set) and report `set`. Written with two-space
#     indentation and a trailing newline (matching SKILL.md step 11f).
#
# OUTPUT CONTRACT (consumed by the seed-hive entrypoint, future step): each function emits ONE
# status word on stdout and returns 0. The status is signalled IN-BAND on stdout (consistent
# with settings-merge.sh's in-band `status`), NOT via exit code, so the caller branches on the
# word. The status words are exactly the SKILL.md step 11 `claude_mem_path:` report tokens:
#     set | already set | skipped (claude-mem not installed) | skipped (malformed json)
#       | skipped (claude binary not found)
#
# DEPENDENCY: jq only (POSIX + jq). No yq, no sed/awk.

# ── self-location + sibling-lib source (SOURCE-OR-DIE) ──────────────────────────
# THIS file is itself a SOURCED lib (no shebang); BASH_SOURCE[0] still resolves to this file's own
# path when sourced, so we self-locate the _shared dir from it (never a caller value) and source the
# json-normalize.sh sibling that supplies hivemind_jq_is_single_object_file. SOURCE-OR-DIE: a missing
# or unparseable sibling returns non-zero from this fragment so the caller (entrypoint / test harness)
# fails closed exactly as it does for this file. Re-sourcing is idempotent (pure function definitions).
# Each step carries an explicit `|| return 1`: errexit is off inside a file sourced under the caller's
# `|| fail`, so without it a failed cd or sibling source would fall through and this fragment return 0.
__cm_path_shared_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || return 1
[ -f "$__cm_path_shared_dir/json-normalize.sh" ] || return 1
# shellcheck source=/dev/null
. "$__cm_path_shared_dir/json-normalize.sh" || return 1
unset __cm_path_shared_dir

# hivemind_claude_mem_resolve_binary [home_dir]
# Resolve the `claude` binary path DYNAMICALLY per SKILL.md step 11e, taking the first candidate
# that resolves to an executable file. Emits the resolved absolute path on stdout and returns 0
# when found; emits NOTHING and returns 1 when no candidate resolves. Pure (reads the filesystem
# and `command -v` only; writes nothing, no exit).
#
# ARGUMENTS
#   [home_dir]  the HOME directory to expand the `~` fallbacks against. Defaults to $HOME when
#               omitted. Passed explicitly by the test harness so resolution is hermetic against
#               a tmp HOME and never reads the developer's real `~/.local/bin`.
hivemind_claude_mem_resolve_binary() {
  local home_dir="${1:-$HOME}"
  local candidate

  # (1) command -v claude — accept ONLY when it names a real, ABSOLUTE executable file. `command -v`
  # may report an alias/function name (not an executable path); guard with test -x so those fall
  # through to the fallbacks. It may ALSO return a CWD-relative path (e.g. `bin/claude`) when PATH
  # carries a relative component (`PATH=bin:$PATH`); such a path passes -x/-f but breaks worker
  # resolution from another CWD once persisted as CLAUDE_CODE_PATH, so it MUST be absolute (leading
  # `/`). A non-absolute candidate is rejected and resolution falls through to the absolute fallbacks.
  candidate="$(command -v claude 2>/dev/null || true)"
  case "$candidate" in
    /*) ;;
    *)  candidate="" ;;
  esac
  if [ -n "$candidate" ] && [ -x "$candidate" ] && [ -f "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  # (2) ~/.local/bin/claude ; (3) ~/.claude/local/claude — first executable wins. $HOME expanded
  # at runtime; never a hard-coded path.
  for candidate in "$home_dir/.local/bin/claude" "$home_dir/.claude/local/claude"; do
    if [ -x "$candidate" ] && [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

# hivemind_claude_mem_provision_path <settings_file> [home_dir]
# Provision claude-mem's OWN `CLAUDE_CODE_PATH` per SKILL.md step 11b-f: read <settings_file>,
# decide under never-clobber + malformed-safe semantics, and (only when warranted) write ONLY
# that single key back, preserving every other key byte-for-byte. Emits ONE status word on
# stdout (the SKILL.md step 11 token) and returns 0.
#
# ARGUMENTS
#   <settings_file>  absolute path to claude-mem's OWN config (the entrypoint passes
#                    `$HOME/.claude-mem/settings.json`). The function reads and MAY write this
#                    exact file; it touches no other path.
#   [home_dir]       HOME for the binary-resolution fallbacks; defaults to $HOME. The test
#                    harness passes a tmp HOME so the whole op is hermetic.
#
# The resolved binary path enters jq as an inert --arg binding; the target is parsed by jq
# (which validates it). NO dynamic value is ever spliced into the jq program text.
hivemind_claude_mem_provision_path() {
  local settings_file="$1"
  local home_dir="${2:-$HOME}"

  # File MISSING → claude-mem is not actually installed (SKILL.md step 11b). Never create it.
  if [ ! -f "$settings_file" ]; then
    printf '%s\n' "skipped (claude-mem not installed)"
    return 0
  fi

  # MALFORMED → no crash, no clobber (SKILL.md step 11c). Validate as a SINGLE JSON object before
  # any read of the key; a torn real file (including a multi-document stream) must be left
  # byte-unchanged. hivemind_jq_is_single_object_file returns 0 IFF the file is exactly one JSON
  # document AND it is an object — rejects multi-doc streams, non-object single docs, and
  # unparseable content (subsumes the former `type=="object"` test and closes the stream gap).
  if ! hivemind_jq_is_single_object_file "$settings_file"; then
    printf '%s\n' "skipped (malformed json)"
    return 0
  fi

  # SCALAR VALUE-STATE NORMALIZATION AT ONE CHOKEPOINT (ABSENT / PRESENT-CANONICAL /
  # PRESENT-MALFORMED): this lib touches ONE scalar key (CLAUDE_CODE_PATH) on a top-level object
  # already validated by the pre-check above. It does NOT index any nested container-typed key
  # (no enabledPlugins / permissions / hooks / array read), so NO canon_obj/canon_arr helper is
  # needed or applicable here. This is the scalar-only conforming site of the cluster rule; the
  # three-state classification and never-clobber decision are complete at this single predicate.
  # Cluster peers: settings-merge.sh (SHAPE-NORMALIZE-AT-ONE-CHOKEPOINT, container keys via
  # canon_obj/canon_arr) and file-guard.sh (VALUE-STATE NORMALIZATION, prose section states).
  #
  # Key value-state normalization (never-clobber). The key is PRESENT-CANONICAL (a non-empty
  # string) OR PRESENT-MALFORMED (present but a non-string: boolean/null/number/object/array) →
  # `already set`, write NOTHING. Both are user-provided values that must NEVER be overwritten,
  # even a now-invalid one (SKILL.md step 11d header). ABSENT (key missing OR empty string `""`)
  # is the ONLY candidate for the write and falls through below.
  # INVARIANT: an explicitly-present JSON null is PRESENT-MALFORMED (skip), not ABSENT — a literal
  # null IS a user-provided value, so never-clobber treats it like any other present non-string.
  # `has("CLAUDE_CODE_PATH") and .CLAUDE_CODE_PATH != ""` is TRUE for any non-empty string and for
  # every present non-string (false/null/0/{}/[] all compare `!= ""`); only key-missing or the
  # empty string `""` is FALSE and falls through to the resolve+write ABSENT branch.
  if jq -e 'has("CLAUDE_CODE_PATH") and .CLAUDE_CODE_PATH != ""' "$settings_file" >/dev/null 2>&1; then
    printf '%s\n' "already set"
    return 0
  fi

  # Key MISSING or EMPTY → resolve the binary dynamically (SKILL.md step 11e). None → skip.
  local resolved
  if ! resolved="$(hivemind_claude_mem_resolve_binary "$home_dir")"; then
    printf '%s\n' "skipped (claude binary not found)"
    return 0
  fi

  # Set ONLY the CLAUDE_CODE_PATH key, preserving every other key (SKILL.md step 11f). The path
  # enters as an inert --arg; jq's structural set never touches sibling keys. Write to a temp in
  # the SAME directory then atomically rename, so a torn write never half-clobbers the file. Two-
  # space indentation + trailing newline (jq default) per SKILL.md step 11f.
  local tmp_out
  tmp_out="$(mktemp "${settings_file}.XXXXXX")" || {
    printf '%s\n' "skipped (malformed json)"
    return 0
  }
  if jq --arg path "$resolved" '.CLAUDE_CODE_PATH = $path' "$settings_file" >"$tmp_out" 2>/dev/null \
       && mv -f "$tmp_out" "$settings_file"; then
    printf '%s\n' "set"
    return 0
  fi

  # Write or render failed for any reason → leave the original untouched; report a non-clobbering
  # skip rather than erasing failure context.
  rm -f "$tmp_out"
  printf '%s\n' "skipped (malformed json)"
  return 0
}
