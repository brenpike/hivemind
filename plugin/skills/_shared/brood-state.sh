# shellcheck shell=bash
#
# brood-state.sh — the ONLY code that reads coordinator brood state: the brood listing, a brood
# manifest, a child run ledger, a child's facts evidence and the pre-launch facts guard.
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute path derived
# from its OWN script_dir (`. "$plugin_root/skills/_shared/brood-state.sh"`). It defines functions
# only. It runs no top-level statements, never exits and changes no caller state beyond defining
# the functions below. `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately OMITS the P18
# shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced file mutates the
# SOURCING shell's option state, so installing those here would corrupt every caller's shell; the
# floor is therefore the documented exception, not the full `set -euo pipefail`. This file
# carries no top-level `set` at all (pure function definitions); each caller owns its own
# `set -u` and error routing. Allowlisted under CHECK13 as a P18 documented exception.
#
# CALLER CONTRACT: source containment.sh BEFORE this file (every reader resolves its root with
# hivemind_canon_root). Source ledger-project.sh before calling hivemind_brood_read_child_ledger
# (it projects the two ledger scalars with hivemind_project_state_current_content /
# hivemind_project_run_status_content).
#
# TRUST BOUNDARY: ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Trust-Boundary Discipline,
# item 3) and the ADR-0037 slice 4 amendment. Brood children run as the same OS user as the
# coordinator, so they are not a security boundary against it; these checks catch ACCIDENTS (a
# stray symlink, a non-regular file, a NUL byte, several JSON documents), not a hostile child.
# Every function takes IDENTIFIERS (a checkout or worktree root the caller derived from git, a
# brood id, a run id) and derives every location from them; no function accepts a file path.
# Each directory component under the canonical root is tested in turn: a symlinked or
# non-directory component is refused, never followed.
#
# SINGLE READ, BYTES INTACT: bash command substitution silently drops NUL bytes, and some jq
# versions drop the bytes after a NUL, so neither may decide whether a file held one. The one
# read maps every NUL to \001 (LC_ALL=C tr), so the captured snapshot still shows where each NUL
# was. The snapshot is refused when it holds any raw C0 control byte other than TAB, LF or CR
# (JSON forbids them raw, and every NUL is now a \001). That same snapshot is then parsed as
# exactly one JSON document.
#
# BROOD ID: one pattern, ^brood-[0-9a-fA-F-]+$, held only in hivemind_brood_id_matches and shared
# by the listing and every read.
#
# CONTRACT
#   hivemind_brood_id_matches <name>
#     Returns 0 when <name> matches the brood-id pattern (tested under LC_ALL=C), 1 otherwise.
#
#   hivemind_brood_read_json <canonical_dir> <leaf>
#     Reads <canonical_dir>/<leaf> once (see SINGLE READ above) and prints it as compact JSON on
#     one line. Returns 0 ok; 2 directory refused (not a directory); 3 leaf refused (symlink,
#     non-regular, invalid name); 4 leaf absent; 5 unreadable (NUL or raw control byte, invalid
#     JSON, zero or several documents, open or read error on a present leaf).
#
#   hivemind_brood_manifest_path <checkout_root> <brood_id>
#     Prints the manifest location as a DISPLAY string only. Callers never open it. A brood id
#     outside the pattern prints nothing and returns 1.
#
#   hivemind_brood_read_manifest <checkout_root> <brood_id>
#     A brood id outside the pattern returns 1. Tests .hivemind, broods and <brood_id> under the
#     canonical checkout root: an absent component returns 4; a symlinked or non-directory
#     component (or an unresolvable root) returns 2. Then runs hivemind_brood_read_json on
#     manifest.json and returns its code.
#
#   hivemind_brood_list_ids <checkout_root>
#     An absent .hivemind or .hivemind/broods prints nothing and returns 0. A symlinked or
#     non-directory one (or an unresolvable root) returns 2 with a reason on stderr. Otherwise
#     prints, one per line and sorted with LC_ALL=C, each entry of the broods directory whose
#     name matches the brood-id pattern and that is either a real directory holding a
#     manifest.json entry of any type, or a symlink (listed so the read refuses it loudly; it is
#     never followed). Non-matching names and real directories without a manifest.json entry
#     are skipped.
#
#   hivemind_brood_read_child_ledger <worktree_root> <run_id>
#     <run_id> must be one safe path component (non-empty, no '/', not . or ..), else both lines
#     are MALFORMED. Tests .hivemind, runs and <run_id> under the canonical worktree and reads
#     state.json. Prints exactly two lines, state.current then run.status:
#       MISSING / MISSING     the chain or the leaf is absent
#       MALFORMED / MALFORMED the chain or the leaf is refused, or the leaf is unreadable
#       otherwise each line is hivemind_project_state_current_content /
#       hivemind_project_run_status_content over the one snapshot (a validated value, MISSING
#       or MALFORMED). Always returns 0. Never prints raw ledger bytes.
#
#   hivemind_detect_facts_evidence <worktree_root>
#     Prints `yes` when a REGULAR, NON-SYMLINK file whose name has the exact gather-facts output
#     shape facts-<8 digits>T<6 digits>Z-<12 lowercase hex>.json sits directly in the worktree's
#     .hivemind/facts, reached through non-symlinked directories. Prints `no` otherwise,
#     including a refused or absent chain. Exactly one line; never a path, never file content.
#     Always returns 0.
#
#   hivemind_brood_facts_absent <worktree_root>
#     Returns 0 only when the worktree's .hivemind is absent, or is a real directory with no
#     facts entry of any type (a dangling symlink counts as present). Returns 1 when a facts
#     entry exists and 2 when the root or .hivemind is refused.
#
# PROVENANCE (facts evidence): hivemind_detect_facts_evidence counts a facts-shaped file that
# post-dates launch by construction: spawn-brood's pre-launch facts guard
# (hivemind_brood_facts_absent) refuses a strain (marked failed, worktree removed, never launched)
# when its fresh worktree already holds `.hivemind/facts` in any form, so a facts file committed
# in a hostile base ref (force-added past the .hivemind/ gitignore) and materialized by
# `git worktree add` never reaches a launched strain. The run-ledger source carries the same
# guarantee: its leaf is keyed by the spawn-generated brood GUID run id. A match proves the file
# was written after launch, NOT that gather-facts wrote it: any process that runs after launch can
# write a facts-shaped file (or, knowing the run id from task.md, a run-ledger state.current).
# Recorded residual, ADR-0037 amendment 2026-10-24 (slice 4), "A process that runs after launch
# can write a facts-shaped file".
#
# DEPENDENCIES: containment.sh, ledger-project.sh (child ledger only), jq, tr, sort.

# hivemind_brood_id_matches <name>
# Contract: see CONTRACT in the header.
hivemind_brood_id_matches() {
  local candidate_name="$1"
  local brood_id_pattern='^brood-[0-9a-fA-F-]+$'
  local LC_ALL=C
  [[ "$candidate_name" =~ $brood_id_pattern ]]
}

# hivemind__brood_walk_dir <canonical_dir> <component>...
# Tests each single-component directory name under <canonical_dir> in turn and prints the path of
# the last directory. Returns 0 ok; 2 refused (invalid name, symlink, non-directory); 4 a
# component is absent. Prints a reason on stderr for a refusal only.
hivemind__brood_walk_dir() {
  local walk_dir="$1"
  shift
  local walk_component
  for walk_component in "$@"; do
    case "$walk_component" in
      ''|.|..|*/*)
        printf 'refusing component %s under %s: not a single path component\n' "$walk_component" "$walk_dir" >&2
        return 2
        ;;
    esac
    walk_dir="${walk_dir%/}/$walk_component"
    if [ -L "$walk_dir" ]; then
      printf 'refusing symlinked directory %s\n' "$walk_dir" >&2
      return 2
    fi
    if [ ! -e "$walk_dir" ]; then
      return 4
    fi
    if [ ! -d "$walk_dir" ]; then
      printf 'refusing non-directory %s\n' "$walk_dir" >&2
      return 2
    fi
  done
  printf '%s' "$walk_dir"
  return 0
}

# hivemind_brood_read_json <canonical_dir> <leaf>
# Contract: see CONTRACT and SINGLE READ in the header.
hivemind_brood_read_json() {
  local canonical_dir="$1"
  local leaf_name="$2"
  if [ ! -d "$canonical_dir" ]; then
    printf 'refusing directory %s: not a directory\n' "$canonical_dir" >&2
    return 2
  fi
  case "$leaf_name" in
    ''|.|..|*/*)
      printf 'refusing leaf %s under %s: not a single path component\n' "$leaf_name" "$canonical_dir" >&2
      return 3
      ;;
  esac
  local leaf_path="${canonical_dir%/}/$leaf_name"
  if [ -L "$leaf_path" ]; then
    printf 'refusing symlinked leaf %s\n' "$leaf_path" >&2
    return 3
  fi
  if [ ! -e "$leaf_path" ]; then
    return 4
  fi
  if [ ! -f "$leaf_path" ]; then
    printf 'refusing non-regular leaf %s\n' "$leaf_path" >&2
    return 3
  fi
  local leaf_snapshot
  if ! leaf_snapshot="$(LC_ALL=C tr '\000' '\001' < "$leaf_path" 2>/dev/null)"; then
    printf 'failed to read leaf %s\n' "$leaf_path" >&2
    return 5
  fi
  local control_bytes
  if ! control_bytes="$(printf '%s' "$leaf_snapshot" | LC_ALL=C tr -cd '\001-\010\013\014\016-\037')"; then
    printf 'failed to scan leaf %s for control bytes\n' "$leaf_path" >&2
    return 5
  fi
  if [ -n "$control_bytes" ]; then
    printf 'refusing leaf %s: it holds a NUL or raw control byte\n' "$leaf_path" >&2
    return 5
  fi
  local compact_json
  if ! compact_json="$(printf '%s' "$leaf_snapshot" \
      | jq -c -s 'if length == 1 then .[0] else error("not exactly one JSON document") end' 2>/dev/null)"; then
    printf 'refusing leaf %s: not exactly one valid JSON document\n' "$leaf_path" >&2
    return 5
  fi
  printf '%s\n' "$compact_json"
  return 0
}

# hivemind_brood_manifest_path <checkout_root> <brood_id>
# Contract: see CONTRACT in the header.
hivemind_brood_manifest_path() {
  local checkout_root="$1"
  local brood_id="$2"
  hivemind_brood_id_matches "$brood_id" || return 1
  printf '%s/.hivemind/broods/%s/manifest.json\n' "$checkout_root" "$brood_id"
  return 0
}

# hivemind_brood_read_manifest <checkout_root> <brood_id>
# Contract: see CONTRACT in the header.
hivemind_brood_read_manifest() {
  local checkout_root="$1"
  local brood_id="$2"
  if ! hivemind_brood_id_matches "$brood_id"; then
    printf 'refusing brood id: it does not match the brood-id pattern\n' >&2
    return 1
  fi
  local canon_root
  if ! canon_root="$(hivemind_canon_root "$checkout_root")"; then
    printf 'refusing checkout root %s: cannot resolve its physical path\n' "$checkout_root" >&2
    return 2
  fi
  local brood_dir walk_status
  brood_dir="$(hivemind__brood_walk_dir "$canon_root" .hivemind broods "$brood_id")"
  walk_status=$?
  if [ "$walk_status" -ne 0 ]; then
    return "$walk_status"
  fi
  hivemind_brood_read_json "$brood_dir" manifest.json
}

# hivemind__brood_list_entries <broods_dir>
# The listing half of hivemind_brood_list_ids, run inside a subshell so the glob options it sets
# never reach the caller.
hivemind__brood_list_entries() (
  local broods_dir="$1"
  set +f
  shopt -u nullglob failglob dotglob nocaseglob 2>/dev/null
  unset GLOBIGNORE
  local entry_path entry_name listed_names=""
  for entry_path in "$broods_dir"/brood-*; do
    entry_name="${entry_path##*/}"
    hivemind_brood_id_matches "$entry_name" || continue
    if [ -L "$entry_path" ]; then
      listed_names="$listed_names$entry_name"$'\n'
    elif [ -d "$entry_path" ] \
        && { [ -e "$entry_path/manifest.json" ] || [ -L "$entry_path/manifest.json" ]; }; then
      listed_names="$listed_names$entry_name"$'\n'
    fi
  done
  if [ -z "$listed_names" ]; then
    return 0
  fi
  printf '%s' "$listed_names" | LC_ALL=C sort
)

# hivemind_brood_list_ids <checkout_root>
# Contract: see CONTRACT in the header.
hivemind_brood_list_ids() {
  local checkout_root="$1"
  local canon_root
  if ! canon_root="$(hivemind_canon_root "$checkout_root")"; then
    printf 'refusing checkout root %s: cannot resolve its physical path\n' "$checkout_root" >&2
    return 2
  fi
  local broods_dir walk_status
  broods_dir="$(hivemind__brood_walk_dir "$canon_root" .hivemind broods)"
  walk_status=$?
  case "$walk_status" in
    0) ;;
    4) return 0 ;;
    *) return 2 ;;
  esac
  hivemind__brood_list_entries "$broods_dir"
}

# hivemind_brood_read_child_ledger <worktree_root> <run_id>
# Contract: see CONTRACT in the header.
hivemind_brood_read_child_ledger() {
  local worktree_root="$1"
  local run_id="$2"
  case "$run_id" in
    ''|.|..|*/*)
      printf 'MALFORMED\nMALFORMED\n'
      return 0
      ;;
  esac
  local canon_wt
  if ! canon_wt="$(hivemind_canon_root "$worktree_root")"; then
    printf 'MALFORMED\nMALFORMED\n'
    return 0
  fi
  local run_dir ledger_json read_status
  run_dir="$(hivemind__brood_walk_dir "$canon_wt" .hivemind runs "$run_id" 2>/dev/null)"
  read_status=$?
  if [ "$read_status" -eq 0 ]; then
    ledger_json="$(hivemind_brood_read_json "$run_dir" state.json 2>/dev/null)"
    read_status=$?
  fi
  case "$read_status" in
    0) ;;
    4) printf 'MISSING\nMISSING\n' ;;
    *) printf 'MALFORMED\nMALFORMED\n' ;;
  esac
  if [ "$read_status" -ne 0 ]; then
    return 0
  fi
  hivemind_project_state_current_content "$ledger_json"
  hivemind_project_run_status_content "$ledger_json"
  return 0
}

# hivemind__brood_facts_match <facts_dir>
# Prints `yes` when a regular, non-symlink, gather-facts-shaped file sits directly in the facts
# directory, `no` otherwise. Runs in a subshell so the glob options it sets never reach the
# caller.
hivemind__brood_facts_match() (
  local facts_dir="$1"
  local digit='[0123456789]'
  local hex='[0123456789abcdef]'
  set +f
  shopt -u nullglob failglob dotglob nocaseglob 2>/dev/null
  unset GLOBIGNORE
  local facts_path facts_name
  for facts_path in "$facts_dir"/facts-*.json; do
    facts_name="${facts_path##*/}"
    # shellcheck disable=SC2254
    case "$facts_name" in
      facts-$digit$digit$digit$digit$digit$digit$digit$digit"T"$digit$digit$digit$digit$digit$digit"Z-"$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex".json") : ;;
      *) continue ;;
    esac
    [ -L "$facts_path" ] && continue
    [ -f "$facts_path" ] || continue
    printf 'yes\n'
    return 0
  done
  printf 'no\n'
  return 0
)

# hivemind_detect_facts_evidence <worktree_root>
# Contract: see CONTRACT and PROVENANCE in the header.
hivemind_detect_facts_evidence() {
  local worktree_root="$1"
  local canon_wt facts_dir
  if ! canon_wt="$(hivemind_canon_root "$worktree_root")" \
      || ! facts_dir="$(hivemind__brood_walk_dir "$canon_wt" .hivemind facts 2>/dev/null)"; then
    printf 'no\n'
    return 0
  fi
  hivemind__brood_facts_match "$facts_dir"
}

# hivemind_brood_facts_absent <worktree_root>
# Contract: see CONTRACT and PROVENANCE in the header.
hivemind_brood_facts_absent() {
  local worktree_root="$1"
  local canon_wt
  if ! canon_wt="$(hivemind_canon_root "$worktree_root")"; then
    printf 'refusing worktree root %s: cannot resolve its physical path\n' "$worktree_root" >&2
    return 2
  fi
  local hivemind_dir walk_status
  hivemind_dir="$(hivemind__brood_walk_dir "$canon_wt" .hivemind)"
  walk_status=$?
  case "$walk_status" in
    0) ;;
    4) return 0 ;;
    *) return 2 ;;
  esac
  if [ -e "$hivemind_dir/facts" ] || [ -L "$hivemind_dir/facts" ]; then
    return 1
  fi
  return 0
}
