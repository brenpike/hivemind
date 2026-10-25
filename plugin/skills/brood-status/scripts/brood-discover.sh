#!/usr/bin/env bash
#
# brood-discover — deterministic brood-manifest discovery/enumeration for hivemind:brood-status
# (ADR-0020). Extracts the discovery step that was previously inline navigator-body prose in
# brood-status's SKILL.md (steps 1a–1c) into a committed, testable engine — the exact "inline
# navigator-body logic" ADR-0020 rejects.
#
# BROOD STATE THROUGH ONE READER (Trust-Boundary Discipline, security-policy.md: accept
# identifiers, never paths): this script never names, globs or opens a brood-state path. It
# lists the brood ids with hivemind_brood_list_ids and renders each one's manifest location with
# hivemind_brood_manifest_path (both in _shared/brood-state.sh, the only code that reads brood
# state). The listing tests each directory under the canonical checkout root and refuses a
# symlinked or non-directory one, never following it. Each listed id matches the brood-id pattern held in hivemind_brood_id_matches (^brood-[0-9a-fA-F-]+$): the
# literal `brood-` prefix followed by hex digits and dashes only, which structurally excludes ALL
# shell metacharacters, so an emitted path carries no injection payload in its variable segment.
# Non-conforming names are skipped silently.
#
# INPUT (positional, optional):
#   $1  TEST-ONLY override for the checkout root. Defaults to `git rev-parse --show-toplevel`
#       (the CURRENT checkout). This is the SAME anchor `spawn-brood.sh` writes against, so the
#       read side and the write side agree by construction. From the main checkout it equals the
#       main checkout root; from a linked worktree it yields THAT worktree's root, so
#       nested/child-spawned broods are visible at each hatchery level (same anchor at every
#       level, no tree-walk).
#
# OUTPUT (CONTRACT):
#   One ABSOLUTE manifest path per line on stdout, sorted with LC_ALL=C (= brood-id order, since
#   all ids share the `brood-` prefix). ZERO broods → ZERO lines, exit 0 — an empty listing is
#   SUCCESS (the navigator renders "No broods found." on zero lines), NOT an error. A brood
#   directory with no manifest entry is skipped. A symlinked brood entry IS listed, so the
#   projector that reads it refuses it loudly.
#
# EXIT CONTRACT:
#   0  listed (zero or more paths).
#   1  `blocker: <reason>` on stderr: a bad checkout root, a refused listing (a symlinked,
#      non-directory brood-state directory), or a missing/unparseable shared library.
#
# NOT THIS SCRIPT'S JOB:
#   - manifest CONTENTS validation (torn/garbage JSON) — that stays the projector's job
#     (`brood-status-project.sh` exit 2).
#
# Conventions (ADR-0020 thin-entrypoint): `set -euo pipefail`, an EXIT trap ending in a
# guaranteed-zero `:`, the canonical fail-closed self-location (Amendment 2026-09-29, forms
# C1/C2/C4/C5), NO `realpath`/`readlink` (BSD/macOS portability).

set -euo pipefail
trap ':' EXIT
blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# ── Self-location + shared libs ───────────────────────────────────────────────────
# layout plugin/skills/brood-status/scripts/ => 3 dirs up is the plugin root. NO
# ${CLAUDE_PLUGIN_ROOT} inside an engine script — the path is derived from BASH_SOURCE.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve the plugin root from the script directory; refusing to proceed"
[ -f "$plugin_root/skills/_shared/containment.sh" ] || blocker "required shared library missing: skills/_shared/containment.sh; refusing to proceed"
. "$plugin_root/skills/_shared/containment.sh" || blocker "failed to source skills/_shared/containment.sh (unparseable); refusing to proceed"
[ -f "$plugin_root/skills/_shared/brood-state.sh" ] || blocker "required shared library missing: skills/_shared/brood-state.sh; refusing to proceed"
. "$plugin_root/skills/_shared/brood-state.sh" || blocker "failed to source skills/_shared/brood-state.sh (unparseable); refusing to proceed"

# Resolve the checkout root: explicit test override, else git ground truth. `git rev-parse
# --show-toplevel` fails (nonzero, empty stdout) outside a git repo — a clean blocker rather than
# listing under an empty root.
root="${1:-}"
if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || blocker "not inside a git checkout (git rev-parse --show-toplevel failed)"
fi
[ -n "$root" ] && [ -d "$root" ] \
  || blocker "checkout root is empty or not a directory: '$root'"

# List the brood ids. A refused listing carries its reason on stderr and becomes a blocker,
# never a silent empty list.
ids_out="$(hivemind_brood_list_ids "$root")" \
  || blocker "refusing to list the broods of checkout $root: brood state is a symlink or not a directory"

# Zero ids → zero lines, exit 0 (empty is success — "No broods found." is the navigator's call).
[ -n "$ids_out" ] || exit 0

# Render each id's manifest location. hivemind_brood_list_ids already sorts with LC_ALL=C; the
# final sort keeps the output order pinned to byte order regardless of the caller's locale.
manifest_paths=""
while IFS= read -r brood_id || [ -n "$brood_id" ]; do
  manifest_path="$(hivemind_brood_manifest_path "$root" "$brood_id")" \
    || blocker "listed brood id does not match the brood-id pattern; refusing to proceed"
  manifest_paths="$manifest_paths$manifest_path"$'\n'
done <<< "$ids_out"
printf '%s' "$manifest_paths" | LC_ALL=C sort
