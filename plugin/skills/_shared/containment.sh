# shellcheck shell=bash
#
# containment.sh — shared symlink-write-escape containment idiom for the three
# committed hivemind run-ledger / brood writers (init-run-ledger, record-state-result,
# spawn-brood); it also provides the ledger-read leaf guard (hivemind_assert_ledger_contained)
# for the ledger-reading engines (mark-intent-fallback, record-state-result, next-wave),
# completing leaf-symmetry across inputs-file / write-target / ledger-read leaves.
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute
# path derived from its OWN script_dir (`. "$plugin_root/skills/_shared/containment.sh"`).
# It defines functions only; it runs no top-level statements and changes no caller state
# beyond defining the functions below. `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately
# OMITS the P18 shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced
# file mutates the SOURCING shell's option state, so installing those here would corrupt
# every caller's shell; the floor is therefore the documented exception, not the full
# `set -euo pipefail`. This file carries no top-level `set` at all (it is pure function
# definitions); each caller owns its own `set -u` and error routing. Allowlisted under
# CHECK13 as a P18 documented exception.
#
# WHY ONE SHARED HELPER: the three writers each DERIVE a write path textually from the git
# checkout root (e.g. "$repo_root/.hivemind/runs/<run_id>"). Textual derivation does NOT
# confine the write when an ANCESTOR component of the chain is a SYMLINK pointing outside
# the checkout — a repo that commits .hivemind, .hivemind/runs, or a deeper component as a
# symlink to an external dir makes the derived path resolve OUTSIDE the checkout, so a
# subsequent mkdir/mktemp/mv/worktree-add writes EXTERNALLY. Previously each writer guarded
# only a hand-enumerated set of ancestor names (.hivemind, .hivemind/runs), which left the
# `<run_id>` leaf (and any future component) unguarded — the finding-1 escape vector. This
# helper closes the class DEPTH-COMPLETELY (every component of the chain, generically, not
# by name) in ONE place so the three writers cannot diverge again.
#
# CONTRACT
#   hivemind_assert_contained <raw_repo_root> <relative_chain>
#     <raw_repo_root>  the git checkout root (e.g. `git rev-parse --show-toplevel`).
#     <relative_chain> a checkout-relative path whose write target lives at its leaf,
#                      e.g. ".hivemind/runs/<run_id>" or ".claude/worktrees".
#     On success: echoes the CANONICAL checkout root (cd && pwd -P) to stdout and returns 0.
#                 Callers MUST derive their write paths from this canonical root.
#     On reject:  prints a human-readable reason to stderr and returns non-zero. The caller
#                 maps the non-zero return to its OWN blocker() (this helper never exits).
#
#   hivemind_assert_file_contained <raw_repo_root> <relative_file_chain>
#     <raw_repo_root>       the git checkout root (e.g. `git rev-parse --show-toplevel`).
#     <relative_file_chain> a checkout-relative path whose LEAF is a write-target FILE,
#                           e.g. ".hivemind/brood/task.md" or ".claude/settings.local.json".
#     On success: echoes the CANONICAL checkout root (cd && pwd -P) to stdout and returns 0.
#     On reject:  prints a reason to stderr and returns non-zero (never exits).
#     LEAF BEHAVIOR CONTRACT: a NON-EXISTENT leaf passes (caller CREATES it fresh); a
#       REGULAR-FILE leaf passes (caller OVERWRITES in place); any OTHER existing leaf type
#       is REJECTED — a SYMLINK leaf (via [ -L ], fires even for a dangling target) AND a
#       DIRECTORY / FIFO / device leaf (an existing leaf that is not a regular file). The
#       directory case matters because `cp <src> <leaf>` treats an existing directory leaf
#       as a DESTINATION DIR and copies the source INTO it, following any nested symlink to
#       an external target. A symlinked ANCESTOR is caught by the reused parent-dir guard
#       below — no gap.
#     PRECONDITION: the leaf must be a file target. A chain whose leaf is "." or ".." is
#       OUT OF CONTRACT (no special handling); callers must not pass such chains.
#
# WHY A SEPARATE FILE-TARGET VARIANT (hivemind_assert_contained CANNOT take a file chain):
#   hivemind_assert_contained's final containment step does `cd "$canon_root/$deepest_existing"
#   && pwd -P`. When the deepest-existing component is a REGULAR FILE, that `cd` FAILS (you
#   cannot cd into a file), yielding an EMPTY string — which the empty-test rejects. So a
#   legitimately-tracked, non-symlink leaf we MEAN to overwrite would be wrongly FALSE-REJECTED.
#   hivemind_assert_file_contained sidesteps this by canonicalizing only the PARENT dir (via the
#   reused dir guard) and applying a single `[ -L ]` symlink test to the leaf — never cd-ing
#   into the leaf. This closes the symlinked-write-target-LEAF escape that the directory-only
#   guard leaves open: a hostile base ref committing a symlinked `.hivemind/brood/task.md` or
#   `.claude/settings.local.json` LEAF, materialized into a child worktree by `git worktree add`,
#   would otherwise be followed on write. The parent-dir guard alone never inspects the leaf.
#
# DEPTH-COMPLETE: every component of <relative_chain> that ALREADY EXISTS is checked for
#   being a symlink ([ -L ]); the deepest existing prefix is canonicalized and required to
#   stay under "<canon_root>/<expected-sub-prefix>/". Non-existent leaf components are fine
#   (init/spawn-brood CREATE them) — only existing components are checked. This covers
#   .hivemind, .hivemind/runs, .hivemind/runs/<run_id>, .claude, .claude/worktrees, and any
#   deeper/future component generically, NOT by enumerated name.
#
# PORTABLE: canonicalization is `cd "$dir" && pwd -P` (pwd -P resolves EVERY symlink
#   component) — NEVER realpath / readlink -f, which BSD/macOS lack or spell differently.
#   Symlink detection is POSIX `[ -L path ]` (fires regardless of whether the target
#   exists). Prefix-containment appends a trailing slash to BOTH operands so a sibling like
#   .hivemind-evil cannot prefix-match .hivemind.
#
# SET -U SAFETY: callers run under `set -u` (no `set -e`). A failed `cd` in a command
#   substitution yields an EMPTY string; every canonicalization below is empty-tested and
#   rejected rather than allowed to proceed with an empty path.
#
# DEPENDENCY-FREE: pure bash / POSIX test builtins (cd, pwd, [ -L ], case). No jq, no
#   realpath, no external canonicalizer.

# hivemind_canon_root <raw_repo_root>
# Echo the canonical checkout root (cd && pwd -P), or echo nothing and return 1 on failure.
# Canonicalizing the root handles a repo_root that itself sits under a symlinked path (e.g.
# macOS /tmp -> /private/tmp) so an equal-but-symlinked root does not false-reject later.
hivemind_canon_root() {
  local raw_root="$1"
  local canon_root
  canon_root="$(cd "$raw_root" 2>/dev/null && pwd -P)"
  if [ -z "$canon_root" ]; then
    return 1
  fi
  printf '%s' "$canon_root"
  return 0
}

# hivemind_assert_contained <raw_repo_root> <relative_chain>
# Depth-complete symlink-containment check over every existing component of the chain.
# Echoes the canonical root on success (return 0); prints a reason to stderr and returns
# non-zero on reject. Never exits — the caller maps non-zero to its own blocker.
hivemind_assert_contained() {
  local raw_root="$1"
  local rel_chain="$2"

  local canon_root
  canon_root="$(hivemind_canon_root "$raw_root")"
  if [ -z "$canon_root" ]; then
    printf 'failed to canonicalize repo root %s\n' "$raw_root" >&2
    return 1
  fi

  # Walk every component of the relative chain from the root down. `partial` accumulates the
  # checkout-relative prefix; `deepest_existing` tracks the deepest prefix that exists on
  # disk (canonicalized and prefix-checked after the walk). IFS='/' splits the chain into
  # components without invoking a subshell or external tool.
  local partial=""
  local deepest_existing=""
  local component
  local old_ifs="$IFS"
  IFS='/'
  # shellcheck disable=SC2086
  set -- $rel_chain
  IFS="$old_ifs"
  for component in "$@"; do
    # Skip empty components (leading/duplicate slashes) defensively.
    [ -n "$component" ] || continue
    if [ -n "$partial" ]; then
      partial="$partial/$component"
    else
      partial="$component"
    fi
    local abs="$canon_root/$partial"
    if [ -L "$abs" ]; then
      printf 'refusing symlinked component %s under %s\n' "$partial" "$canon_root" >&2
      return 1
    fi
    if [ -e "$abs" ]; then
      deepest_existing="$partial"
    fi
  done

  # Canonicalize the deepest EXISTING prefix and require it stay under the canonical root
  # (and, transitively, under the expected sub-prefix the chain names — the canonical prefix
  # text starts with "$canon_root/<chain-prefix>"). A non-existent leaf is fine; only the
  # existing prefix is verified. Trailing-slash-guarded so a sibling like .hivemind-evil
  # cannot prefix-match .hivemind.
  if [ -n "$deepest_existing" ]; then
    local canon_prefix
    canon_prefix="$(cd "$canon_root/$deepest_existing" 2>/dev/null && pwd -P)"
    if [ -z "$canon_prefix" ]; then
      printf 'failed to canonicalize %s/%s\n' "$canon_root" "$deepest_existing" >&2
      return 1
    fi
    case "$canon_prefix/" in
      "$canon_root/$deepest_existing/") : ;;
      *)
        printf 'component %s resolves outside the checkout: %s\n' "$deepest_existing" "$canon_prefix" >&2
        return 1
        ;;
    esac
  fi

  printf '%s' "$canon_root"
  return 0
}

# hivemind_assert_file_contained <raw_repo_root> <relative_file_chain>
# File-target containment: the chain's LEAF is a write-target FILE, not a directory.
# COMPOSES hivemind_assert_contained — it does NOT reimplement the ancestor walk. The parent
# directory chain is validated by the existing depth-complete guard; the leaf gets an
# additional [ -L ] symlink test PLUS a non-regular-file reject (existing dir/FIFO/device).
# See the WHY block in the header for the false-reject the directory-only guard would hit on
# a regular-file leaf.
# Echoes the canonical root on success (return 0); prints a reason to stderr and returns
# non-zero on reject. Never exits — the caller maps non-zero to its own blocker.
hivemind_assert_file_contained() {
  local raw_root="$1"
  local rel_chain="$2"

  # Split the chain into parent-dir chain + leaf basename. A single-component chain has a
  # dirname of "." — normalize it to "" so the parent guard validates the root only.
  local parent_chain leaf
  parent_chain="$(dirname "$rel_chain")"
  leaf="$(basename "$rel_chain")"
  if [ "$parent_chain" = "." ]; then
    parent_chain=""
  fi

  # Reuse the existing depth-complete ancestor symlink walk + canonicalization on the PARENT
  # chain. On reject (non-zero) OR empty canon_root, propagate — the existing fn already
  # printed a reason to stderr.
  local canon_root
  canon_root="$(hivemind_assert_contained "$raw_root" "$parent_chain")"
  if [ $? -ne 0 ] || [ -z "$canon_root" ]; then
    return 1
  fi

  # Leaf test on the FULL leaf path. A non-existent leaf passes (caller CREATES it); a
  # regular-file leaf passes (caller OVERWRITES in place). Any OTHER existing leaf type is
  # REJECTED. [ -L ] (checked first, before -e/-f which follow symlinks) covers a symlinked
  # leaf incl. a dangling one. The [ -e ] && ! [ -f ] arm covers a DIRECTORY (or FIFO/device)
  # occupying the leaf path: a real `.claude/settings.local.json/` dir tracked by a hostile
  # base ref passes [ -L ], but then `cp <src> <leaf>` treats the dir as a DESTINATION and
  # copies the source INTO it (following any nested symlink to an external target before the
  # privileged child launches). Rejecting a non-regular existing leaf closes that vector while
  # preserving the non-existent-leaf and regular-file-leaf pass behaviors.
  local leaf_path="$canon_root/$rel_chain"
  if [ -L "$leaf_path" ]; then
    printf 'refusing symlinked file leaf %s under %s\n' "$rel_chain" "$canon_root" >&2
    return 1
  fi
  if [ -e "$leaf_path" ] && [ ! -f "$leaf_path" ]; then
    printf 'refusing non-regular file leaf %s under %s\n' "$rel_chain" "$canon_root" >&2
    return 1
  fi

  printf '%s' "$canon_root"
  return 0
}

# hivemind_assert_ledger_contained <raw_repo_root> <ledger_file_path>
#
# LEDGER-READ leaf guard for the ledger-reading engines (mark-intent-fallback,
# record-state-result, next-wave). Those engines read the run-ledger state.json via
# [ -f "$ledger" ], jq -e . "$ledger", and jq -r '.run.id' "$ledger" — all of which FOLLOW
# SYMLINKS. Their existing hivemind_assert_contained "$repo_root" ".hivemind/runs/$run_id"
# guard validates the chain only DOWN TO the <run_id> run-dir, NOT the state.json leaf below
# it. When the run dir is real but state.json is itself a symlink, the ledger reads follow it
# to an external target — a content/validity read oracle the ancestor guard never inspects.
#
# This function REFUSES TO READ such a leaf, mirroring hivemind_assert_inputs_contained's
# read-guard structure exactly. It completes leaf-symmetry across the three leaf classes:
# inputs-file leaf (hivemind_assert_inputs_contained), write-target leaf
# (hivemind_assert_file_contained), and ledger-read leaf (this function).
#
# LEAF REJECT: rejects a symlinked LEAF (the ledger file itself) via [ -L ] on the RAW
# passed path FIRST — fires even when the symlink target is dangling/non-existent, and
# before any [ -f ]/jq read (which follow symlinks). Then canonicalizes the leaf's DIRNAME
# (cd && pwd -P), re-appends the basename, and prefix-matches against the canonical root —
# catching a symlinked ANCESTOR as well.
#
# CALLER CONTRACT: callers run this AFTER deriving repo_root/run_id and BEFORE the first
# ledger read. It does NOT replace the existing ancestor/runs-dir containment guard or the
# post-existence canonical confirmation — those remain in the callers as defense-in-depth.
#
# On success: echoes the canonical repo root and returns 0.
# On reject:  prints a concise reason to stderr and returns non-zero. Never exits.
hivemind_assert_ledger_contained() {
  local raw_root="$1"
  local ledger_file_path="$2"

  local canon_root
  canon_root="$(hivemind_canon_root "$raw_root")"
  if [ -z "$canon_root" ]; then
    printf 'failed to canonicalize repo root %s\n' "$raw_root" >&2
    return 1
  fi

  # Reject a symlinked LEAF before any path resolution. Tests the RAW passed path so it fires
  # even for a dangling symlink target, and before the [ -f ]/jq reads that follow symlinks.
  # Mirrors hivemind_assert_inputs_contained's [ -L ] leaf reject. A regular-file leaf is
  # [ -L ]-false and proceeds to the ancestor check below.
  if [ -L "$ledger_file_path" ]; then
    printf 'refusing symlinked ledger file leaf %s under %s\n' "$ledger_file_path" "$canon_root" >&2
    return 1
  fi

  # Canonicalize the ledger file path using the same cd && pwd -P idiom as the rest of this
  # file. We cd into dirname (which must already exist) and re-append the basename. This
  # resolves every symlink component in the directory path.
  local ledger_dir ledger_base canon_ledger
  ledger_dir="$(dirname "$ledger_file_path")"
  ledger_base="$(basename "$ledger_file_path")"
  canon_ledger="$(cd "$ledger_dir" 2>/dev/null && pwd -P)"
  if [ -z "$canon_ledger" ]; then
    printf 'failed to canonicalize ledger file directory %s\n' "$ledger_dir" >&2
    return 1
  fi
  canon_ledger="$canon_ledger/$ledger_base"

  # Trailing-slash-guarded prefix match — mirrors hivemind_assert_inputs_contained's case
  # pattern exactly so a sibling path like /repo-evil cannot prefix-match /repo.
  case "$canon_ledger/" in
    "$canon_root/"*)
      ;;
    *)
      printf 'ledger file %s resolves outside the checkout: %s\n' "$ledger_file_path" "$canon_ledger" >&2
      return 1
      ;;
  esac

  printf '%s' "$canon_root"
  return 0
}

# hivemind_assert_inputs_contained <raw_repo_root> <inputs_file_path>
#
# Defense-in-depth READ-guard for the inputs-file navigators. The model authors an inputs
# JSON file via the Write tool BEFORE the committed engine runs. This function lets each
# engine REFUSE TO READ an inputs file whose canonical path escapes the checkout (e.g. via a
# symlinked ancestor), converting a silent external-write-and-consume into a hard, loud
# blocker.
#
# HONEST SCOPE NOTE: this does NOT prevent the external Write itself — the model's Write tool
# runs before any committed code executes, so a path escaped via symlink is already written
# by the time this guard runs. What this guard does is REFUSE TO READ such a file, making
# the violation loud (hard non-zero return) rather than silent. The PRIMARY fix for the
# write-through-symlink class is the navigator transport-path correction (record's
# fixed-literal-sibling path + token transport), not this guard. This guard is a
# defense-in-depth backstop only.
#
# PRECONDITION: the caller must verify the file exists ([ -f "$inputs_file" ]) before
# calling this function. Behavior on a missing file is unspecified.
#
# LEAF REJECT: in addition to rejecting a symlinked ANCESTOR (caught by the dirname
# cd && pwd -P canonicalization + prefix case below), this guard rejects a symlinked LEAF
# (the inputs file itself) via [ -L ] on the RAW passed path — fires even when the symlink
# target is dangling/non-existent. Without this, a symlinked leaf whose parent dir is
# in-checkout passes the ancestor check, then the caller's `jq -e . "$INPUTS_FILE"` follows
# the symlink to an external target — a content/validity read oracle. [ -f ]/[ -e ] do NOT
# help (they follow symlinks). This MIRRORS hivemind_assert_file_contained's write-guard
# [ -L ] leaf reject; the two guards are now symmetric on leaf-symlink handling.
#
# On success: echoes the canonical repo root and returns 0.
# On reject:  prints a concise reason to stderr and returns non-zero. Never exits.
hivemind_assert_inputs_contained() {
  local raw_root="$1"
  local inputs_file_path="$2"

  local canon_root
  canon_root="$(hivemind_canon_root "$raw_root")"
  if [ -z "$canon_root" ]; then
    printf 'failed to canonicalize repo root %s\n' "$raw_root" >&2
    return 1
  fi

  # Reject a symlinked LEAF before any path resolution. Tests the RAW passed path so it fires
  # even for a dangling symlink target. Mirrors hivemind_assert_file_contained's [ -L ] leaf
  # reject. A regular-file leaf is [ -L ]-false and proceeds to the ancestor check below.
  if [ -L "$inputs_file_path" ]; then
    printf 'refusing symlinked inputs file leaf %s under %s\n' "$inputs_file_path" "$canon_root" >&2
    return 1
  fi

  # Canonicalize the inputs file path using the same cd && pwd -P idiom as the rest of this
  # file. We cd into dirname (which must already exist — the file exists per precondition)
  # and re-append the basename. This resolves every symlink component in the directory path.
  local inputs_dir inputs_base canon_inputs
  inputs_dir="$(dirname "$inputs_file_path")"
  inputs_base="$(basename "$inputs_file_path")"
  canon_inputs="$(cd "$inputs_dir" 2>/dev/null && pwd -P)"
  if [ -z "$canon_inputs" ]; then
    printf 'failed to canonicalize inputs file directory %s\n' "$inputs_dir" >&2
    return 1
  fi
  canon_inputs="$canon_inputs/$inputs_base"

  # Trailing-slash-guarded prefix match — mirrors hivemind_assert_contained's case pattern
  # exactly so a sibling path like /repo-evil cannot prefix-match /repo.
  case "$canon_inputs/" in
    "$canon_root/"*)
      ;;
    *)
      printf 'inputs file %s resolves outside the checkout: %s\n' "$inputs_file_path" "$canon_inputs" >&2
      return 1
      ;;
  esac

  printf '%s' "$canon_root"
  return 0
}
