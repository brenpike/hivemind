#!/usr/bin/env bash
#
# bump-type — THIN executable entrypoint for the hivemind:bump-type engine (ADR-0020). Computes
# the versioning.md `## Bump Type Determination` dominant row + verdict for the commits on the
# working branch since <base>, so the overlord reads a routing decision instead of hand-running
# the revert pre-pass / row mapping / precedence arithmetic in prose. READ-ONLY: it mutates
# nothing (no ledger, no temp file, no git write).
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
#   Flags may appear before or after the positional; each exactly once; `--flag value` form only.
#
# COMMIT READ: `git log -z --format='%H%n%s%n%b' <resolved-base-sha>..HEAD --`. Records are
# NUL-terminated — a DELIBERATE deviation from versioning.md's `--END--` line delimiter, because a
# commit body line reading `--END--` could forge record framing, while git refuses NUL in commit
# messages. Every record's first line must be a full hex object id; anything else is a framing
# violation and fails closed. `log.showSignature` is forced off so signature text cannot enter the
# record stream. git's exit status is checked (pipefail); a failed read is a blocker.
#
# DERIVATION: the pure rules live in _shared/bump-type-derive.sh (see its header for the rule
# re-encoding and the A1/A2/A3/A4/A6/A8 residuals). This entrypoint only frames records, runs the
# revert pre-pass union, tallies rows, and emits.
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
#
# EXIT CONTRACT:
#   0  routing YAML on stdout
#   1  `blocker: <reason>` on stderr, NOTHING on stdout. Blocker text never carries commit text.
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
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
shared_dir="$(cd "$script_dir/../../_shared" && pwd -P)"
[ -f "$shared_dir/allowlist.sh" ] || blocker "required shared library missing: skills/_shared/allowlist.sh; refusing to proceed"
. "$shared_dir/allowlist.sh" || blocker "failed to source skills/_shared/allowlist.sh (unparseable); refusing to proceed"
[ -f "$shared_dir/bump-type-derive.sh" ] || blocker "required shared library missing: skills/_shared/bump-type-derive.sh; refusing to proceed"
. "$shared_dir/bump-type-derive.sh" || blocker "failed to source skills/_shared/bump-type-derive.sh (unparseable); refusing to proceed"

# ── Argument parsing ──────────────────────────────────────────────────────────────
base_ref=''
base_seen=false
bump_trigger=''
no_bump_match=''
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
git rev-parse --verify --quiet 'HEAD^{commit}' >/dev/null 2>&1 || blocker "HEAD does not resolve to a commit"

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

printf '%s\n' "$routing"
exit 0
