# shellcheck shell=bash
#
# ledger-project.sh — shared child run-ledger scalar projector (read side).
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute
# path derived from its OWN script_dir (`. "$plugin_root/skills/_shared/ledger-project.sh"`).
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
# SINGLE RESPONSIBILITY: project + validate the two workflow-state scalars (run.status and
# state.current) from a CONFINED child run-ledger path. The ledger is JSON, parsed READ-ONLY
# with jq. This file sources nothing and writes nothing — pure projection. It also holds the
# second started-evidence source, hivemind_detect_facts_evidence (end of file): a gather-facts
# output file in the child worktree, for script-engine children that write no run ledger.
#
# PROVENANCE (facts evidence): hivemind_detect_facts_evidence counts a regular, non-symlink file
# whose NAME matches the gather-facts output shape. Every match post-dates launch by construction:
# spawn-brood's pre-launch facts guard refuses a strain (marked failed, worktree removed, never
# launched) when its fresh worktree already holds `.hivemind/facts` in any form, so a facts file
# committed in a hostile base ref (force-added past the .hivemind/ gitignore) and materialized by
# `git worktree add` never reaches a launched strain. The run-ledger source carries the same
# guarantee: its leaf is keyed by the spawn-generated brood GUID run id. No file content is ever
# read or emitted.
#
# DATA-BOUNDARY (MANDATORY): a child run-ledger (`<worktree>/.hivemind/runs/<id>/state.json`)
# is UNTRUSTED, attacker-controllable bytes — a brood child runs detached, and child content
# stays adversary-influenced whatever its permission mode, so its ledger contents are too. These
# functions NEVER echo raw ledger bytes: they emit ONLY a value that passed strict validation,
# or one of the fixed tokens MISSING / MALFORMED. The caller is expected to have already
# CONFINED the ledger path (containment + allowlist) before calling; these functions add the
# value-shape validation layer.
#
# PER-SCALAR INDEPENDENCE: the two projectors are independent. A bad run.status never blanks
# state.current and vice versa — the caller reads both and renders each on its own merit.
#
# TOKEN SEMANTICS:
#   MISSING   — the ledger file/dir is absent, OR the field is absent/empty in a parseable file
#               (`// empty` yielded nothing). "Nothing to report", not an attack.
#   MALFORMED — the file exists but jq could not parse it (torn/partial/invalid JSON), OR the
#               field is present but fails its value contract (out-of-enum status, or a
#               state.current that violates the identifier shape / length cap). "Present but
#               invalid" — never echoed raw.

# SINGLE-SNAPSHOT READ (read-side projection path): the projection engine
# (brood-status-project.sh) reads the ledger file EXACTLY ONCE into an in-memory shell variable
# and projects BOTH scalars from THAT snapshot via jq stdin (`printf '%s' "$content" | jq ...`),
# never re-opening the file. This mirrors the manifest single-snapshot pattern (manifest-json.sh)
# and collapses the prior per-scalar reopen window: the OLD path-based projectors each independently
# re-stat + re-open the leaf via jq (which FOLLOWS symlinks), so a hostile child could swap the
# regular-file leaf to a symlink in the post-check window and the per-scalar reopens would follow it.
# The content-snapshot projectors below (suffix `_content`) take the CONTENT, not the path; the
# legacy path-based pair (hivemind_project_run_status / hivemind_project_state_current) is retained
# as a thin read-once wrapper for the unit-test callers that pass a fixture path directly.

# hivemind_path_has_nul <file>
# Returns 0 (true) iff <file> contains at least one literal NUL byte. JSON never legitimately
# contains a literal NUL, so its presence marks the file UNREADABLE/MALFORMED.
#
# WHY THIS EXISTS: bash command substitution `$(...)` SILENTLY STRIPS NUL bytes from its
# captured output. A file read with `content="$(cat -- "$f")"` therefore yields a value that
# DIFFERS from the on-disk bytes whenever a NUL is present — e.g. an on-disk
# `{"strains":<NUL>[]}` becomes the valid-looking `{"strains":[]}` and passes shape validation.
# We must therefore reject a NUL-bearing file at the FILE level, BEFORE any `$(...)` read can
# erase the NUL. `grep`/bash-string approaches cannot carry a NUL in the pattern (the NUL is
# itself stripped from the pattern), so detection is done byte-accurately via `tr`: strip every
# NUL and compare the byte length to the original — any difference means a NUL was present.
# LC_ALL=C keeps `tr`/`wc` byte-oriented (no locale multibyte interpretation).
hivemind_path_has_nul() {
  local file="$1"
  [ -f "$file" ] || return 1
  local orig stripped
  orig="$(LC_ALL=C wc -c < "$file" 2>/dev/null)" || return 1
  stripped="$(LC_ALL=C tr -d '\000' < "$file" 2>/dev/null | LC_ALL=C wc -c)"
  [ "$orig" != "$stripped" ]
}

# hivemind_project_run_status_content <content>
# Emit the validated run.status from an in-memory ledger CONTENT snapshot, or MISSING
# (empty content / absent-or-empty field) or MALFORMED (unparseable JSON / value outside the
# fixed enum running|complete|blocked|cancelled). The content is UNTRUSTED bytes; it enters jq
# ONLY via stdin pipe, never spliced into the program, never eval'd.
#
# IN-JQ VALIDATION (framing-preserving): the type gate, empty/absent classification, AND the
# enum membership test ALL run INSIDE jq, so the verdict is computed while the bytes are still
# intact. jq emits ONLY a fixed token (MISSING / MALFORMED) or a value that is byte-for-byte
# one of the four enum literals. This closes two distinct gaps that a post-extraction bash
# `case` left open:
#   1. NUL/control-byte stripping: bash command substitution SILENTLY DROPS NUL
#      bytes, so a hostile `"run\u0000ning"` would, after extraction, become `running` and pass
#      a bash enum check. Comparing inside jq (where the NUL is intact) rejects it as MALFORMED,
#      and a value that DOES pass `IN(...)` is exactly an enum literal — it can carry no NUL.
#   2. Falsy non-string values: the prior `.run.status // empty` treated JSON
#      `false` as absent (`//` is alternative-on-falsy), projecting a tamper value as MISSING.
#      The explicit `type` gate reports a PRESENT non-string as MALFORMED; only an absent/null
#      field or an explicit empty string is MISSING.
#
# SINGLE-DOCUMENT DISCIPLINE: jq accepts a STREAM of concatenated JSON documents, so a
# non-slurped `jq -r` runs the program ONCE PER document and a child state.json holding TWO valid
# objects would emit TWO output lines — the embedded newline corrupts the one-line STRAIN frame the
# caller builds. We SLURP with `-s` and require `length==1` (exactly one top-level document); 0 or
# >1 documents → MALFORMED. The scalar is projected from `.[0]` of the slurped array. This mirrors
# the single-document discipline in manifest-json.sh (hivemind_manifest_validate_shape et al).
hivemind_project_run_status_content() {
  local content="$1"
  if [ -z "$content" ]; then
    printf 'MISSING\n'
    return 0
  fi
  local verdict
  if ! verdict="$(printf '%s' "$content" | jq -r -s '
      if (length != 1) then "MALFORMED"
      elif (.[0]|type)!="object" then "MALFORMED"
      elif (.[0]|has("run")|not) or (.[0].run|type)!="object" or (.[0].run.status==null) then "MISSING"
      elif (.[0].run.status|type)!="string" then "MALFORMED"
      elif (.[0].run.status=="") then "MISSING"
      elif (.[0].run.status|IN("running","complete","blocked","cancelled")) then .[0].run.status
      else "MALFORMED" end' 2>/dev/null)"; then
    # jq failed: unparseable / torn JSON.
    printf 'MALFORMED\n'
    return 0
  fi
  printf '%s\n' "$verdict"
  return 0
}

# hivemind_project_state_current_content <content>
# Emit the validated state.current from an in-memory ledger CONTENT snapshot, or MISSING (empty
# content / absent-or-empty field) or MALFORMED (unparseable JSON / value failing ^[a-z0-9_]+$ /
# value longer than 64 chars). The content enters jq ONLY via stdin pipe, never spliced/eval'd.
#
# IN-JQ VALIDATION (framing-preserving): the JSON-type gate, length cap, AND the charset test
# ALL run INSIDE jq, so the verdict is computed while the bytes are still intact, and jq emits
# ONLY a fixed token (MISSING / MALFORMED) or a value that has already satisfied ^[a-z0-9_]+$.
# This closes two gaps a post-extraction bash check left open:
#   1. NUL/control-byte stripping: bash command substitution SILENTLY DROPS NUL
#      bytes, so a hostile `"imp lement"` would, after extraction, become `implement` and pass
#      a bash charset `case`. Testing inside jq (NUL intact) rejects it as MALFORMED, and a value
#      that DOES pass `test("^[a-z0-9_]+$")` contains only [a-z0-9_] — it can carry no NUL.
#   2. Non-string scalars (the pre-existing type gate): jq -r stringifies a JSON true to "true"
#      etc.; a PRESENT non-string is a tamper indicator → MALFORMED. An ABSENT/null field or an
#      explicit empty string is the intended "nothing to report" case → MISSING.
#
# SINGLE-DOCUMENT DISCIPLINE: same rationale as hivemind_project_run_status_content — a
# non-slurped `jq -r` over a child state.json holding TWO concatenated valid objects would emit TWO
# lines, and the embedded newline corrupts the one-line STRAIN frame. We SLURP with `-s` and require
# `length==1`; 0 or >1 documents → MALFORMED. The scalar is projected from `.[0]`.
hivemind_project_state_current_content() {
  local content="$1"
  if [ -z "$content" ]; then
    printf 'MISSING\n'
    return 0
  fi
  local verdict
  if ! verdict="$(printf '%s' "$content" | jq -r -s '
      if (length != 1) then "MALFORMED"
      elif (.[0]|type)!="object" then "MALFORMED"
      elif (.[0]|has("state")|not) or (.[0].state|type)!="object" or (.[0].state.current==null) then "MISSING"
      elif (.[0].state.current|type)!="string" then "MALFORMED"
      elif (.[0].state.current=="") then "MISSING"
      elif (.[0].state.current|length>64) then "MALFORMED"
      elif (.[0].state.current|test("^[a-z0-9_]+$")) then .[0].state.current
      else "MALFORMED" end' 2>/dev/null)"; then
    # jq failed: unparseable / torn JSON.
    printf 'MALFORMED\n'
    return 0
  fi
  printf '%s\n' "$verdict"
  return 0
}

# hivemind_project_run_status <ledger_path>
# Legacy path-based wrapper retained for unit-test callers that pass a fixture path. Reads the
# ledger ONCE and delegates to hivemind_project_run_status_content. Emit the validated run.status,
# or MISSING (absent file / absent-or-empty field) or MALFORMED (unparseable JSON / value outside
# the fixed enum). An absent file is MISSING (the wrapper short-circuits before any read).
hivemind_project_run_status() {
  local ledger_path="$1"
  if [ ! -f "$ledger_path" ]; then
    printf 'MISSING\n'
    return 0
  fi
  # FILE-LEVEL NUL REJECTION: the `cat` below captures via `$(...)`, which
  # SILENTLY STRIPS NUL bytes, so a NUL-bearing ledger would parse as a different document than
  # what is on disk. JSON never legitimately contains a literal NUL → "present but invalid" →
  # MALFORMED, checked at the FILE level before the `$(...)` read can erase the NUL.
  if hivemind_path_has_nul "$ledger_path"; then
    printf 'MALFORMED\n'
    return 0
  fi
  local content
  # READ FAILURE on a PRESENT file (unreadable perms, I/O error) is "present but cannot be
  # read" → MALFORMED, never MISSING. `cat` returns empty AND non-zero on failure; the
  # `2>/dev/null` silences stderr only, not the exit status the `if !` tests. Mirrors the
  # pre-single-snapshot jq-open-failure semantics and the content-snapshot read site. The
  # re-test `[ -e ]` keeps a file that VANISHED after the `[ -f ]` guard above as MISSING
  # (genuine absence), reporting MALFORMED only for a present-but-unreadable file.
  if ! content="$(cat -- "$ledger_path" 2>/dev/null)"; then
    if [ -e "$ledger_path" ]; then
      printf 'MALFORMED\n'
    else
      printf 'MISSING\n'
    fi
    return 0
  fi
  hivemind_project_run_status_content "$content"
  return 0
}

# hivemind_project_state_current <ledger_path>
# Legacy path-based wrapper retained for unit-test callers that pass a fixture path. Reads the
# ledger ONCE and delegates to hivemind_project_state_current_content. Emit the validated
# state.current, or MISSING (absent file / absent-or-empty field) or MALFORMED (unparseable JSON /
# value failing ^[a-z0-9_]+$ / value longer than 64 chars).
hivemind_project_state_current() {
  local ledger_path="$1"
  if [ ! -f "$ledger_path" ]; then
    printf 'MISSING\n'
    return 0
  fi
  # FILE-LEVEL NUL REJECTION: see hivemind_project_run_status — a literal NUL in
  # the ledger would be silently stripped by the `$(...)` read; a NUL-bearing ledger is MALFORMED.
  if hivemind_path_has_nul "$ledger_path"; then
    printf 'MALFORMED\n'
    return 0
  fi
  local content
  # READ FAILURE on a PRESENT file (unreadable perms, I/O error) is "present but cannot be
  # read" → MALFORMED, never MISSING. `cat` returns empty AND non-zero on failure; the
  # `2>/dev/null` silences stderr only, not the exit status the `if !` tests. Mirrors the
  # pre-single-snapshot jq-open-failure semantics and the content-snapshot read site. The
  # re-test `[ -e ]` keeps a file that VANISHED after the `[ -f ]` guard above as MISSING
  # (genuine absence), reporting MALFORMED only for a present-but-unreadable file.
  if ! content="$(cat -- "$ledger_path" 2>/dev/null)"; then
    if [ -e "$ledger_path" ]; then
      printf 'MALFORMED\n'
    else
      printf 'MISSING\n'
    fi
    return 0
  fi
  hivemind_project_state_current_content "$content"
  return 0
}

# hivemind_read_confined_state_current <worktree_root> <relative_ledger_chain>
#
# SINGLE SOURCE OF THE 6-LAYER HARDENED CONFINED READ of a child run-ledger leaf. Both
# spawn-brood's verify_started_evidence and brood-status-project.sh's inner ledger read call
# THIS function instead of maintaining two byte-near-identical copies (the duplicate-drift root
# class that absorbed two P1 findings on PR #278). It performs the confined, single-snapshot
# read of `<worktree_root>/<relative_ledger_chain>` and projects BOTH workflow-state scalars
# (state.current AND run.status) from that ONE snapshot.
#
# WHY BOTH SCALARS FROM ONE SNAPSHOT: brood-status renders both state.current and run.status.
# Re-opening the ledger a second time to project the second scalar would reintroduce the
# multi-open TOCTOU window the single-snapshot design closed (a hostile child could swap the
# leaf between the two opens). So this function reads ONCE and projects both from the same
# in-memory `cat` snapshot via the existing _content projectors.
#
# CALLER CONTRACT: the caller MUST source containment.sh BEFORE ledger-project.sh — this
# function calls hivemind_assert_file_contained and hivemind_path_has_nul, both defined in
# containment.sh. (Both current callers already source in that order.)
#
# DATA-BOUNDARY (MANDATORY): the child run-ledger is UNTRUSTED, attacker-controllable bytes (a
# brood child runs detached; child content stays adversary-influenced whatever its permission
# mode). This function NEVER echoes raw
# ledger bytes: each emitted scalar is ONLY a value that passed the _content projectors' strict
# in-jq validation, or one of the fixed tokens MISSING / MALFORMED. Confinement is enforced here
# (containment + leaf/NUL/ITEM-4 guards) so neither caller has to reimplement it.
#
# ARGUMENTS
#   <worktree_root>          the GROUND-TRUTH worktree root the leaf is confined beneath. The
#                            caller MUST pass a script-derived, trusted root (spawn-brood's
#                            S_WT[idx]; brood-status's git-worktree-list-discovered, already
#                            CHECKOUT_ROOT-confined path) — NEVER a manifest/child-supplied path.
#   <relative_ledger_chain>  the checkout-relative chain to the leaf, e.g.
#                            ".hivemind/runs/<run_id>/state.json".
#
# OUTPUT GRAMMAR (exactly two lines, stable for STEP-002/003/004 callers to parse):
#   line 1 = state.current result  ∈ { MISSING | MALFORMED | <validated value> }
#   line 2 = run.status result     ∈ { MISSING | MALFORMED | <validated value> }
# A <validated value> on line 1 satisfies ^[a-z0-9_]+$ and length<=64; on line 2 it is one of
# running|complete|blocked|cancelled. Neither line can carry a NUL or newline (the _content
# projectors emit only fixed tokens or charset/enum-validated values). spawn-brood consumes only
# line 1 (state.current); brood-status consumes both lines. Both lines take the SAME terminal
# token on every guard-failure path below (a confinement/read failure is not scalar-specific).
#
# LAYER ORDERING (do NOT reorder — byte-equivalent to the two reference inner reads):
#   1. hivemind_assert_file_contained — leaf [ -L ] + non-regular reject AND depth-complete
#      ancestor symlink walk under <worktree_root>; echoes the CANONICAL worktree root. On
#      reject => fail-closed MALFORMED (both), never read.
#   2. derive canon_ledger = "$canon_wt/$rel_chain".
#   3. [ -L "$canon_ledger" ] re-check as close to the read as possible — narrows (does not
#      close; bash has no portable O_NOFOLLOW) the irreducible single-open micro-TOCTOU. =>
#      MALFORMED.
#   4. hivemind_path_has_nul — FILE-LEVEL NUL reject: bash $(...) silently strips NUL, so a
#      NUL-bearing ledger would parse as a different document than what is on disk. JSON never
#      legitimately carries a literal NUL => MALFORMED, rejected before the $(...) read.
#   5. single `cat -- "$canon_ledger"` snapshot. On cat success: ITEM-4 post-read re-canonicalize
#      the leaf PARENT (cd && pwd -P resolves every symlink component) + re-append basename +
#      re-assert still under canon_wt — bounds the ancestor-swap micro-TOCTOU between the guard
#      and the cat to an ACCEPTED residual (not a structural closure). On escape => MALFORMED.
#   6. project state.current AND run.status from the ONE snapshot via the existing _content
#      projectors. On cat FAILURE: [ -e "$canon_ledger" ] => MALFORMED (present-but-unreadable:
#      perms / I/O), else MISSING (genuine absence — the child may not have written its ledger
#      yet, or it vanished).
hivemind_read_confined_state_current() {
  local worktree_root="$1"
  local rel_chain="$2"

  # LAYER 1: confine the leaf beneath the ground-truth worktree. hivemind_assert_file_contained
  # rejects a symlinked / non-regular state.json leaf ([ -L ] fires even on a dangling target)
  # AND any symlinked ancestor of the chain, echoing the CANONICAL worktree root. A non-existent
  # leaf PASSES (the child may not have written its ledger yet) => MISSING on the cat-failure
  # path below. Reject (non-zero) => fail-closed MALFORMED (both), never read.
  local canon_wt
  if ! canon_wt="$(hivemind_assert_file_contained "$worktree_root" "$rel_chain" 2>/dev/null)"; then
    printf 'MALFORMED\nMALFORMED\n'
    return 0
  fi
  # LAYER 2: derive the canonical ledger path under the canonical worktree.
  local canon_ledger="$canon_wt/$rel_chain"

  # LAYER 3: re-assert the leaf is not a symlink as close to the read as possible (narrows, does
  # not close, the irreducible single-open micro-TOCTOU — bash has no portable O_NOFOLLOW). An
  # ACCEPTED bounded residual: only the validated state.current charset / run.status enum ever
  # surfaces, never raw bytes.
  if [ -L "$canon_ledger" ]; then
    printf 'MALFORMED\nMALFORMED\n'
    return 0
  fi
  # LAYER 4: FILE-LEVEL NUL REJECTION — bash $(...) silently strips NUL; a NUL-bearing ledger
  # would parse as a different document than what is on disk. JSON never legitimately carries a
  # literal NUL => MALFORMED, rejected at the FILE level before the $(...) read can erase it.
  if hivemind_path_has_nul "$canon_ledger"; then
    printf 'MALFORMED\nMALFORMED\n'
    return 0
  fi
  # LAYER 5: single in-memory snapshot. cat returns empty AND non-zero on failure; the
  # 2>/dev/null silences only stderr, not the exit status the `if` tests.
  local ledger_content
  if ledger_content="$(cat -- "$canon_ledger" 2>/dev/null)"; then
    # READ SUCCEEDED.
    # ITEM-4 DEFENSE-IN-DEPTH (locked): after the read, resolve the ACTUAL read target —
    # canonicalize the leaf's PARENT (cd && pwd -P resolves every symlink component) and
    # re-append the basename — and RE-ASSERT it is STILL contained under the canonical worktree
    # (canon_wt). An ANCESTOR such as .hivemind/runs/<run_id> can be swapped to a symlink AFTER
    # hivemind_assert_file_contained returned but BEFORE this cat; without a post-read check the
    # projection would accept the escaped target's bytes. Project ONLY if still contained;
    # otherwise MALFORMED. This bounds (does NOT structurally close — bash has no portable
    # O_NOFOLLOW) the irreducible one-open micro-TOCTOU to an ACCEPTED residual.
    local ledger_dir reread_target ledger_still_contained
    ledger_dir="$(cd "$(dirname -- "$canon_ledger")" 2>/dev/null && pwd -P)"
    reread_target=""
    [ -n "$ledger_dir" ] && reread_target="$ledger_dir/$(basename -- "$canon_ledger")"
    ledger_still_contained=0
    if [ -n "$reread_target" ]; then
      case "$reread_target/" in
        "$canon_wt/"*) ledger_still_contained=1 ;;
      esac
    fi
    if [ "$ledger_still_contained" -ne 1 ]; then
      # The resolved read target escaped the worktree after the read => fail closed.
      printf 'MALFORMED\nMALFORMED\n'
      return 0
    fi
    # LAYER 6: confined post-read. Project BOTH scalars from the single in-memory snapshot via
    # the CONTENT projectors — the same canonical validation both callers used independently
    # (single-document JSON, object shape, charset / enum, length cap). Never the path-based
    # projectors (they re-open the leaf and would reintroduce the multi-open window). The
    # _content projectors each emit exactly one line, so the combined output is exactly two
    # lines in the documented order: state.current, then run.status.
    hivemind_project_state_current_content "$ledger_content"
    hivemind_project_run_status_content "$ledger_content"
    return 0
  elif [ -e "$canon_ledger" ]; then
    # Present but unreadable (perms / I/O) => present-but-invalid => MALFORMED, never MISSING.
    # The existence re-test runs ONLY on the failure path, so it never enlarges the success-path
    # read window above.
    printf 'MALFORMED\nMALFORMED\n'
    return 0
  else
    # Absent leaf (child has not initialized its ledger yet, or it vanished) => MISSING, per the
    # documented TOKEN SEMANTICS — distinct from the present-but-unreadable case above.
    printf 'MISSING\nMISSING\n'
    return 0
  fi
}

# hivemind_detect_facts_evidence <worktree_root>
#
# STARTED-EVIDENCE for script-engine children. A script-engine run writes no run ledger, but its
# first step (hivemind:gather-facts) publishes `.hivemind/facts/facts-<UTC>-<random>.json` inside
# the child worktree. This function prints `yes` when a REGULAR, NON-SYMLINK file whose name has
# the exact gather-facts output shape
#   facts-<8 digits>T<6 digits>Z-<12 lowercase hex>.json
# sits DIRECTLY in `<worktree_root>/.hivemind/facts`, and `no` otherwise. It reads NO file
# content: only names and file types. A gather-facts temp file (`.facts-XXXXXX`), a directory or
# symlink carrying a matching name, a non-matching name, or a nested file never counts.
#
# CALLER CONTRACT: the caller MUST source containment.sh BEFORE calling — the folder chain is
# checked by hivemind_assert_contained (defined there). <worktree_root> MUST be a script-derived,
# trusted, git-reported worktree root (brood-status's ground-truth worktree, spawn-brood's
# S_WT[idx]) — NEVER a manifest/child-supplied path. <worktree_root> MUST be a strain worktree
# spawn-brood created and launched behind its pre-launch facts guard (`.hivemind/facts` proven
# absent before launch), so any match post-dates launch.
#
# FOLDER CHAIN: hivemind_assert_contained walks `.hivemind` and `.hivemind/facts`, rejecting a
# symlinked component and any existing component that canonicalizes outside the worktree. A
# reject, an absent folder, or a non-directory folder => `no`.
#
# OUTPUT GRAMMAR: exactly one line, `yes` or `no`. Never a path, never file content.
hivemind_detect_facts_evidence() {
  local worktree_root="$1"
  local digit='[0123456789]'
  local hex='[0123456789abcdef]'

  local canon_wt
  if ! canon_wt="$(hivemind_assert_contained "$worktree_root" ".hivemind/facts" 2>/dev/null)"; then
    printf 'no\n'
    return 0
  fi
  local facts_dir="$canon_wt/.hivemind/facts"
  if [ -L "$facts_dir" ] || [ ! -d "$facts_dir" ]; then
    printf 'no\n'
    return 0
  fi

  local facts_entry facts_name
  for facts_entry in "$facts_dir"/facts-*.json; do
    facts_name="${facts_entry##*/}"
    # shellcheck disable=SC2254
    case "$facts_name" in
      facts-$digit$digit$digit$digit$digit$digit$digit$digit"T"$digit$digit$digit$digit$digit$digit"Z-"$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex".json") : ;;
      *) continue ;;
    esac
    [ -L "$facts_entry" ] && continue
    [ -f "$facts_entry" ] || continue
    printf 'yes\n'
    return 0
  done
  printf 'no\n'
  return 0
}
