#!/usr/bin/env bash
#
# bump-type — THIN executable entrypoint for the hivemind:bump-type engine (ADR-0020), the SINGLE
# SOURCE of the Bump Type Determination arithmetic that versioning.md `## Bump Type Determination`
# delegates to. Computes the dominant row + verdict for the commits on the working branch since
# <base>, so the overlord reads a routing decision instead of hand-computing the revert pre-pass /
# row mapping / precedence. READ-ONLY: it mutates nothing (no ledger, no temp file, no git write).
#
# INPUT:
#   $1                        base ref (positional). Gated by hivemind_assert_identifier
#                             (_shared/allowlist.sh: non-empty, no leading `-`, no `..`, charset
#                             ^[A-Za-z0-9._/-]+$), then resolved with
#                             `git rev-parse --verify --quiet "<base>^{commit}"`. Revision suffix
#                             syntax (`~`, `^`, `@{}`) is rejected by the gate by design.
#   --bump-trigger  yes|no    REQUIRED. The overlord's judgment: does the change satisfy any
#                             versioning.md Bump Trigger bullet?
#   --no-bump-match yes|no    REQUIRED. The overlord's judgment: does the change match one or
#                             more "No bump is required by default" bullets?
#   --version-file  <path>    OPTIONAL, REPEATABLE. A repository path holding a version. Each path
#                             is gated by hivemind_assert_identifier. With none, stdout is exactly
#                             the routing block below.
#   Flags may appear before or after the positional; `--bump-trigger` and `--no-bump-match` exactly
#   once, `--version-file` any number of times; `--flag value` form only.
#
# COMMIT READ: `git log -z --format='%H%n%s%n%b' <resolved-base-sha>..HEAD --`. Records are
# NUL-terminated rather than line-delimited by a sentinel line, because a commit body line equal to
# any sentinel could forge record framing, while git refuses NUL in commit messages. Every record's first line must be a full hex object id; anything else is a framing
# violation and fails closed. `log.showSignature` is forced off so signature text cannot enter the
# record stream. git's exit status is checked (pipefail); a failed read is a blocker.
#
# DERIVATION: the pure rules live in _shared/bump-type-derive.sh (see its header for the rule
# set and the A1/A2/A3/A4/A6/A8 residuals). This entrypoint only frames records, runs the
# revert pre-pass union, tallies rows, and emits.
#
# VERSION READ (only with --version-file): after the verdict, each file is read at the base commit
# and at HEAD with `git show --no-textconv <sha>:<path>` (committed content only, never the working
# tree; no repository textconv driver runs). The version is read by path: `*.json` -> the top-level
# string `version`, read with jq (a missing jq is a blocker); `*.toml` -> the value of the only
# `version = "X.Y.Z"` line; any other path -> the whole file is one version line. A version must be
# a strict SemVer core; anything else, or a file missing at that commit, reads as no version. The
# pure helpers (SemVer core, raise, TOML line, plain line) live in _shared/bump-type-derive.sh.
#
# OUTPUT on success (exit 0), YAML routing lines on stdout, emitted in ONE write at the end:
#   dominant_row: MAJOR|MINOR|PATCH|NO_BUMP|NONE|MULTI
#   verdict: bump_required|no_bump|ask_user
#   bump_type: major|minor|patch|none
#   rule_applied: <1-6>          # dominant-row precedence rule that fired (first match wins)
#   counts:
#     major: <N>
#     minor: <N>
#     patch: <N>
#     no_bump: <N>
#   mapped_commits: <N>          # commits mapped to a row after the revert pre-pass
#   dropped_reverts: <N>         # COMMITS dropped by the revert pre-pass (union of reverts AND
#                                # their originals — a matched pair counts 2), not pairs
#   version_check: match|mismatch|unreadable|undetermined
#                                # ONLY with --version-file. unreadable: any file has no version at
#                                # base or at HEAD, or the base versions differ. Else undetermined:
#                                # verdict is ask_user. Else match: every HEAD version equals
#                                # expected_version. Else mismatch.
#   trunk_version: X.Y.Z         # ONLY with --version-file, and only when every base version reads
#                                # and all agree
#   expected_version: X.Y.Z      # ONLY when trunk_version is present and verdict is bump_required
#                                # (trunk_version raised by bump_type) or no_bump (trunk_version)
#
# EXIT CONTRACT:
#   0  routing YAML on stdout
#   1  `blocker: <reason>` on stderr, NOTHING on stdout. Blocker text never carries commit text
#      or version file text.
#   A version file that reads as no version is never a blocker: it yields version_check unreadable.
#
# Conventions (ADR-0020 thin entrypoint): `set -euo pipefail`, an EXIT trap ending in a
# guaranteed-zero `:`, self-location via `cd && pwd -P`, NO `realpath`/`readlink`; bash 3.2
# compatible (no mapfile / associative arrays / ${var,,}).

set -euo pipefail
trap ':' EXIT

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# ── Self-location + shared libs ───────────────────────────────────────────────────
# layout plugin/skills/bump-type/scripts/ => ../../_shared is the shared-library dir. cd && pwd -P
# is portable (no realpath/readlink). NO ${CLAUDE_PLUGIN_ROOT} inside an engine script.
# SOURCE-OR-DIE: a missing/unparseable library fails closed before any derivation.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
shared_dir="$(CDPATH= cd -- "$script_dir/../../_shared" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve skills/_shared from the script directory; refusing to proceed"
[ -f "$shared_dir/allowlist.sh" ] || blocker "required shared library missing: skills/_shared/allowlist.sh; refusing to proceed"
. "$shared_dir/allowlist.sh" || blocker "failed to source skills/_shared/allowlist.sh (unparseable); refusing to proceed"
[ -f "$shared_dir/bump-type-derive.sh" ] || blocker "required shared library missing: skills/_shared/bump-type-derive.sh; refusing to proceed"
. "$shared_dir/bump-type-derive.sh" || blocker "failed to source skills/_shared/bump-type-derive.sh (unparseable); refusing to proceed"

# ── Argument parsing ──────────────────────────────────────────────────────────────
base_ref=''
base_seen=false
bump_trigger=''
no_bump_match=''
version_files=()
version_file_count=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bump-trigger)
      [ -z "$bump_trigger" ] || blocker "--bump-trigger given more than once"
      [ "$#" -ge 2 ] || blocker "--bump-trigger requires a value (yes|no)"
      bump_trigger="$2"
      [ -n "$bump_trigger" ] || blocker "--bump-trigger must be yes or no"
      shift 2
      ;;
    --no-bump-match)
      [ -z "$no_bump_match" ] || blocker "--no-bump-match given more than once"
      [ "$#" -ge 2 ] || blocker "--no-bump-match requires a value (yes|no)"
      no_bump_match="$2"
      [ -n "$no_bump_match" ] || blocker "--no-bump-match must be yes or no"
      shift 2
      ;;
    --version-file)
      [ "$#" -ge 2 ] || blocker "--version-file requires a path"
      hivemind_assert_identifier "$2" || blocker "--version-file path fails the identifier gate (charset ^[A-Za-z0-9._/-]+\$, no leading '-', no '..')"
      version_files[version_file_count]="$2"
      version_file_count=$((version_file_count + 1))
      shift 2
      ;;
    -*)
      blocker "unknown option; usage: bump-type.sh <base> --bump-trigger yes|no --no-bump-match yes|no"
      ;;
    *)
      [ "$base_seen" = false ] || blocker "exactly one positional base ref is accepted"
      base_ref="$1"
      base_seen=true
      shift
      ;;
  esac
done

[ "$base_seen" = true ] || blocker "missing positional base ref; usage: bump-type.sh <base> --bump-trigger yes|no --no-bump-match yes|no"
case "$bump_trigger" in
  yes|no) ;;
  '') blocker "missing required --bump-trigger yes|no" ;;
  *) blocker "--bump-trigger must be yes or no" ;;
esac
case "$no_bump_match" in
  yes|no) ;;
  '') blocker "missing required --no-bump-match yes|no" ;;
  *) blocker "--no-bump-match must be yes or no" ;;
esac
hivemind_assert_identifier "$base_ref" || blocker "base ref fails the identifier gate (charset ^[A-Za-z0-9._/-]+\$, no leading '-', no '..')"

# ── Git context ───────────────────────────────────────────────────────────────────
command -v git >/dev/null 2>&1 || blocker "git not found on PATH"
git rev-parse --git-dir >/dev/null 2>&1 || blocker "not inside a git checkout"
base_sha="$(git rev-parse --verify --quiet "${base_ref}^{commit}" 2>/dev/null)" || blocker "base ref does not resolve to a commit"
head_sha="$(git rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null)" || blocker "HEAD does not resolve to a commit"
for ((version_index = 0; version_index < version_file_count; version_index++)); do
  case "${version_files[version_index]}" in
    *.json) command -v jq >/dev/null 2>&1 || blocker "jq not found on PATH (needed to read a .json --version-file)" ;;
  esac
done

# ── Record framing + per-commit classification ────────────────────────────────────
# derive_routing_from_stream <bump_trigger> <no_bump_match>
#   Reads NUL-terminated `%H\n%s\n%b` records on stdin, runs the revert pre-pass (single-pass
#   UNION drop set) and row mapping via the pure core, and prints the routing YAML. Returns 3 on a
#   framing violation. Runs in the command-substitution subshell, where errexit is suspended, so
#   every failure is checked explicitly.
derive_routing_from_stream() {
  local stream_bump_trigger="$1"
  local stream_no_bump_match="$2"
  local newline=$'\n'
  local re_object_id='^[0-9a-f]{40}([0-9a-f]{24})?$'
  local commit_shas=()
  local commit_subjects=()
  local commit_bodies=()
  local commit_count=0
  local record after_sha record_sha
  while IFS= read -r -d '' record || [ -n "$record" ]; do
    case "$record" in
      *"$newline"*"$newline"*) ;;
      *) return 3 ;;
    esac
    record_sha="${record%%"$newline"*}"
    [[ $record_sha =~ $re_object_id ]] || return 3
    after_sha="${record#*"$newline"}"
    commit_shas[commit_count]="$record_sha"
    commit_subjects[commit_count]="${after_sha%%"$newline"*}"
    commit_bodies[commit_count]="${after_sha#*"$newline"}"
    commit_count=$((commit_count + 1))
  done

  local drop_flags=()
  local index
  for ((index = 0; index < commit_count; index++)); do
    drop_flags[index]=0
  done

  local target_sha target_index
  for ((index = 0; index < commit_count; index++)); do
    hivemind_bump_is_revert "${commit_subjects[index]}" || continue
    target_sha="$(hivemind_bump_extract_revert_target "${commit_bodies[index]}")" || continue
    target_index="$(hivemind_bump_resolve_revert_index "$target_sha" "${commit_shas[@]}")" || continue
    drop_flags[index]=1
    drop_flags[target_index]=1
  done

  local major_count=0 minor_count=0 patch_count=0 no_bump_count=0 dropped_count=0
  local commit_row
  for ((index = 0; index < commit_count; index++)); do
    if [ "${drop_flags[index]}" -eq 1 ]; then
      dropped_count=$((dropped_count + 1))
      continue
    fi
    commit_row="$(hivemind_bump_map_row "${commit_subjects[index]}" "${commit_bodies[index]}")" || return 1
    case "$commit_row" in
      MAJOR) major_count=$((major_count + 1)) ;;
      MINOR) minor_count=$((minor_count + 1)) ;;
      PATCH) patch_count=$((patch_count + 1)) ;;
      NO_BUMP) no_bump_count=$((no_bump_count + 1)) ;;
    esac
  done

  local dominant_pair dominant_row rule_applied verdict_pair verdict bump_type
  dominant_pair="$(hivemind_bump_select_dominant_row "$stream_bump_trigger" "$major_count" "$minor_count" "$patch_count" "$no_bump_count")" || return 1
  dominant_row="${dominant_pair%% *}"
  rule_applied="${dominant_pair#* }"
  verdict_pair="$(hivemind_bump_derive_verdict "$dominant_row" "$stream_bump_trigger" "$stream_no_bump_match")" || return 1
  verdict="${verdict_pair%% *}"
  bump_type="${verdict_pair#* }"

  printf 'dominant_row: %s\n' "$dominant_row"
  printf 'verdict: %s\n' "$verdict"
  printf 'bump_type: %s\n' "$bump_type"
  printf 'rule_applied: %s\n' "$rule_applied"
  printf 'counts:\n'
  printf '  major: %s\n' "$major_count"
  printf '  minor: %s\n' "$minor_count"
  printf '  patch: %s\n' "$patch_count"
  printf '  no_bump: %s\n' "$no_bump_count"
  printf 'mapped_commits: %s\n' "$((major_count + minor_count + patch_count + no_bump_count))"
  printf 'dropped_reverts: %s\n' "$dropped_count"
  return 0
}

# ── Version check (only with --version-file) ──────────────────────────────────────
# read_version_at <commit_sha> <path>
#   Prints the SemVer core version of <path> at <commit_sha> and returns 0. Returns 1 (prints
#   nothing) when the file is missing at that commit or holds no version for its format. The
#   brace group's 2>/dev/null also silences bash's null-byte warning for a binary file.
read_version_at() {
  local commit_sha="$1"
  local file_path="$2"
  local file_text version_text
  { file_text="$(git show --no-textconv "${commit_sha}:${file_path}")"; } 2>/dev/null || return 1
  case "$file_path" in
    *.json)
      version_text="$(printf '%s' "$file_text" | jq -r 'if type == "object" then (.version | if type == "string" then . else empty end) else empty end' 2>/dev/null)" || return 1
      hivemind_bump_is_semver_core "$version_text" || return 1
      ;;
    *.toml)
      version_text="$(hivemind_bump_extract_toml_version "$file_text")" || return 1
      ;;
    *)
      version_text="$(hivemind_bump_extract_plain_version "$file_text")" || return 1
      ;;
  esac
  printf '%s\n' "$version_text"
  return 0
}

# read_routing_value <routing> <key>
#   Prints the value of the top-level `<key>: ` line of the engine's own routing block and returns
#   0; returns 1 when no such line exists.
read_routing_value() {
  local remaining_text="$1"
  local routing_key="$2"
  local newline=$'\n'
  local routing_line
  while :; do
    routing_line="${remaining_text%%"$newline"*}"
    case "$routing_line" in
      "$routing_key: "*)
        printf '%s\n' "${routing_line#"$routing_key: "}"
        return 0
        ;;
    esac
    case "$remaining_text" in
      *"$newline"*) remaining_text="${remaining_text#*"$newline"}" ;;
      *) return 1 ;;
    esac
  done
}

# derive_version_check <verdict> <bump_type>
#   Reads every --version-file at base and at HEAD and prints the version_check line, then
#   trunk_version and expected_version when the OUTPUT contract calls for them. Returns 1 on an
#   internal derivation failure.
derive_version_check() {
  local verdict="$1"
  local bump_type="$2"
  local bases_read=true heads_read=true bases_agree=true
  local trunk_version='' expected_version='' version_check='match'
  local head_versions=()
  local file_index base_version head_version
  for ((file_index = 0; file_index < version_file_count; file_index++)); do
    if base_version="$(read_version_at "$base_sha" "${version_files[file_index]}")"; then
      if [ -z "$trunk_version" ]; then
        trunk_version="$base_version"
      elif [ "$base_version" != "$trunk_version" ]; then
        bases_agree=false
      fi
    else
      bases_read=false
    fi
    if head_version="$(read_version_at "$head_sha" "${version_files[file_index]}")"; then
      head_versions[file_index]="$head_version"
    else
      heads_read=false
      head_versions[file_index]=''
    fi
  done

  if [ "$bases_read" = true ] && [ "$bases_agree" = true ]; then
    case "$verdict" in
      bump_required|no_bump)
        expected_version="$(hivemind_bump_raise_version "$trunk_version" "$bump_type")" || return 1
        ;;
    esac
  fi

  if [ "$bases_read" = false ] || [ "$heads_read" = false ] || [ "$bases_agree" = false ]; then
    version_check='unreadable'
  elif [ "$verdict" = 'ask_user' ]; then
    version_check='undetermined'
  else
    for ((file_index = 0; file_index < version_file_count; file_index++)); do
      [ "${head_versions[file_index]}" = "$expected_version" ] || version_check='mismatch'
    done
  fi

  printf 'version_check: %s\n' "$version_check"
  if [ "$bases_read" = true ] && [ "$bases_agree" = true ]; then
    printf 'trunk_version: %s\n' "$trunk_version"
  fi
  if [ -n "$expected_version" ]; then
    printf 'expected_version: %s\n' "$expected_version"
  fi
  return 0
}

# INVARIANT: output is buffered in `routing` and written once below, so any failure leaves stdout
# empty. With pipefail the pipeline status is the rightmost non-zero member: 3 = framing violation
# from the parser, any other non-zero = git log failed (or an internal derivation failure).
routing_status=0
routing="$(git -c log.showSignature=false log -z --format='%H%n%s%n%b' "${base_sha}..HEAD" -- 2>/dev/null \
  | derive_routing_from_stream "$bump_trigger" "$no_bump_match")" || routing_status=$?
if [ "$routing_status" -eq 3 ]; then
  blocker "malformed git log record framing; refusing to derive"
elif [ "$routing_status" -ne 0 ]; then
  blocker "git log over <base>..HEAD failed (exit $routing_status)"
fi

if [ "$version_file_count" -gt 0 ]; then
  routing_verdict="$(read_routing_value "$routing" verdict)" || blocker "routing has no verdict line; refusing to check versions"
  routing_bump_type="$(read_routing_value "$routing" bump_type)" || blocker "routing has no bump_type line; refusing to check versions"
  version_lines="$(derive_version_check "$routing_verdict" "$routing_bump_type")" || blocker "version check derivation failed"
  routing="${routing}"$'\n'"${version_lines}"
fi

printf '%s\n' "$routing"
exit 0
