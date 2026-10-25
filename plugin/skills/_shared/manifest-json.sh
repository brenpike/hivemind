# shellcheck shell=bash
#
# manifest-json.sh — shared brood-manifest field extractor (read side of spawn-brood.sh).
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute
# path derived from its OWN script_dir (`. "$plugin_root/skills/_shared/manifest-json.sh"`).
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
# SINGLE RESPONSIBILITY: extract scalar fields from the JSON brood manifest with jq. The
# manifest is the same JSON spawn-brood.sh writes (manifest_version 3). This file is PURE
# EXTRACTION only: it does NOT validate the extracted bytes (that is allowlist.sh's job).
# Every value emitted here is UNTRUSTED and must be re-gated by the caller through the
# matching allowlist value-class validator (identifier / path / presentation) before use.
#
# READ-SIDE INJECTION CLASS IS DEAD BY CONSTRUCTION: the prior YAML read side (sed/awk)
# could not separate YAML STRUCTURE from attacker CONTENT — a hostile `description` block
# scalar carrying counterfeit `status:`/`worktree_path:`/nested `run:` keys or an injected
# `- name:` entry had to be defended against with hand-rolled block-scalar-aware,
# indent-anchored awk. With the manifest as JSON parsed by jq, jq CANNOT confuse content for
# structure: a string field's bytes are just a string, never re-parsed as sibling keys. The
# ENTIRE block-scalar / nested-mapping / multiline-injection class the YAML reader fought is
# gone by construction. The remaining boundary is purely VALUE-shape (allowlist), applied by
# the caller, not structural.
#
# DATA-BOUNDARY: the manifest content enters jq ONLY via stdin, and a strain index enters as a
# --argjson binding, NEVER interpolated into the jq program string. This file opens no file.
#
# SINGLE-SNAPSHOT READ (read-side projection path): the snapshot comes from
# hivemind_brood_read_manifest (brood-state.sh), which reads the manifest EXACTLY ONCE, refuses
# a NUL or raw control byte, and parses exactly one JSON document from that same read. Every projection below then runs against THAT snapshot via jq stdin
# (`printf '%s' "$content" | jq ...`); nothing re-opens the file. This closes the read-side
# SNAPSHOT-SKEW class: a concurrent write mid-read can no longer make the probe and the per-field
# projections observe different instants. Bytes held in a shell variable and passed only to jq
# stdin are inert — bash does not re-evaluate them as command source. Every helper below (suffix
# `_snapshot` / `_at`, plus the shape validator) takes the CONTENT, never a path.
#
# MANIFEST SHAPE (mirrors spawn-brood.sh's jq emitter): a top-level object with a `strains`
# array; each strain is an object with `name`, `worktree_path`, `branch`, `tmux_session`,
# `status`, and a nested `run` object carrying `suggested_id` / `suggested_ledger` /
# `workflow_hint`. A v1 manifest (no `run` block) yields empty for the run.* fields.
#
# DEPENDENCY: jq only (POSIX + jq). No yq, no sed/awk YAML parsing.

# ── Single-snapshot content helpers (read-side projection path) ──────────────────
# These operate on an in-memory CONTENT snapshot hivemind_brood_read_manifest read ONCE from the
# manifest file, never re-opening it. The content enters jq ONLY via pipe (`printf '%s' "$content" | jq ...`), never spliced into
# the program; an index enters as --argjson. This is what lets the projection engine open the
# manifest exactly once and run all projections + shape validation against one consistent view.

# hivemind_manifest_validate_shape <content>
# Returns 0 iff <content> is valid JSON AND `.strains` EXISTS and is an ARRAY AND every element
# of `.strains` is an OBJECT. Returns non-zero otherwise (invalid JSON, missing/null/non-array
# `.strains`, or any non-object element). This FOLDS the old `jq empty` syntax-only probe into a
# single shape-validating read: invalid JSON fails `jq -e` here just as it failed `jq empty`, and
# a valid-JSON-but-wrong-shape manifest ({}, {"strains":null}, {"strains":"x"}, {"strains":[1]})
# now ALSO fails — joining the wrong-shape class to the syntactically-invalid class so the caller
# treats both as UNREADABLE rather than silently projecting zero strains. A valid `{"strains":[]}`
# passes (all() over an empty array is true): a legitimate EMPTY brood, NOT unreadable. An element
# that IS an object but lacks `name` still passes shape validation — per-strain field degradation
# (MALFORMED/MISSING tokens) is the existing per-strain contract, not a whole-manifest verdict.
# Emits nothing; pure (no side effects, no exit).
# SINGLE-DOCUMENT REQUIREMENT (root cause): jq accepts a STREAM of concatenated JSON
# documents, so a non-slurped `jq -e '(.strains|type=="array") ...'` runs the predicate ONCE PER
# document and a file holding TWO valid manifest objects would pass shape validation. The downstream
# count would then emit one length per document (`1\n1`), the loop's `[ "$idx" -lt "$count" ]`
# integer test would error on the multiline value, and the engine would exit 0 with no STRAIN lines
# — live children rendered as an empty brood. We SLURP with `jq -s` and require the slurped array
# length == 1 (exactly one top-level document) AND that the single element is an object with
# `.strains` an array of objects. A multi-document file → length>1 → fails → caller treats it as
# UNREADABLE. The count/field projectors below slurp the same way and index `.[0]`, so the whole
# read operates on one consistent single document.
hivemind_manifest_validate_shape() {
  local content="$1"
  printf '%s' "$content" \
    | jq -e -s 'length == 1
        and (.[0] | type == "object")
        and (.[0].strains | type == "array")
        and (all(.[0].strains[]; type == "object"))' \
      >/dev/null 2>&1
}

# hivemind_manifest_strain_count_snapshot <content>
# Emit the number of strains (length of the `.strains` array) for the in-memory snapshot. Assumes
# the snapshot already passed hivemind_manifest_validate_shape (so `.strains` is an array). Emits
# `0` on any jq error. The caller drives an INDEX-based loop off this count rather than splitting
# a newline-delimited name stream — so an untrusted field value containing a newline (already
# rejected by the value-class floor, but only AFTER extraction) can never split the loop or forge
# an extra iteration before validation. Pure (no side effects, no exit).
hivemind_manifest_strain_count_snapshot() {
  local content="$1"
  # SLURP + index .[0] (root cause): match hivemind_manifest_validate_shape's single-document
  # discipline so this can never emit one length per document for a multi-document file (which would
  # break the engine's integer loop test). validate_shape has already required exactly one document
  # before this is reached; slurping here keeps the count projection on that same single document.
  printf '%s' "$content" | jq -r -s '.[0].strains | length' 2>/dev/null || printf '0'
}

# hivemind_manifest_field_at <content> <index> <field>
# Emit the validated scalar value of <field> for the strain at array position <index> (0-based)
# in the in-memory snapshot, and signal presence-vs-rejection OUT-OF-BAND via EXIT CODE.
# Supported fields: worktree_path, branch, tmux_session, status, run.suggested_ledger,
# run.suggested_id, workflow_hint; the run.* fields may be passed with or WITHOUT the `run.`
# prefix, and a v1 manifest with no `run` block yields absent for them. The strain is selected by
# INDEX (--argjson i), never by a name that could collide or carry a delimiter. The field
# selector is a fixed literal from the closed case below — never attacker content.
#
# EXIT-CODE CONTRACT (F2, locked OQ1 resolution — consumed by brood-status-project.sh, STEP-004):
# This helper distinguishes ABSENT from REJECTED via the EXIT CODE, NOT via an in-band sentinel
# string (an in-band sentinel could collide with a legit field value). The caller MUST branch on
# the exit code, not on stdout emptiness alone:
#   exit 0 -> field is PRESENT and VALID. The validated value is emitted on stdout (the caller may
#            still apply its value-class allowlist floor, but the value is string-typed and free of
#            C0 control bytes). Stdout MAY legitimately be a value; it is never empty on exit 0.
#   exit 1 -> field is ABSENT (key missing, JSON null, or empty string). Nothing on stdout. The
#            caller renders MISSING. This is the "nothing to report" case, not an attack.
#   exit 2 -> field is PRESENT but INVALID — wrong JSON type (non-string scalar such as branch:123,
#            tmux_session:true, status:123), a value carrying a C0 control byte, or a multi-document
#            snapshot (length != 1). Nothing trustworthy on stdout. The caller renders MALFORMED.
#            REJECTED is NEVER collapsed into MISSING (exit 1).
# An UNRECOGNIZED field selector exits 1 (treated as absent — it is a fixed caller-supplied literal,
# never attacker content, so a typo degrades to MISSING rather than MALFORMED).
#
# TYPE==STRING GATE (F3): every supported field is a STRING in a well-formed manifest. The
# value MUST be type=="string" BEFORE any extraction/coercion. Without this, jq -r would coerce a
# non-string scalar (branch:123 -> "123", tmux_session:true -> "true") into a trusted-LOOKING token
# that flows past the caller as if it were a real string field. A PRESENT non-string is a tamper
# indicator -> exit 2 (MALFORMED), never coerced and never emitted.
#
# CONTROL-BYTE REJECTION INSIDE jq (root cause): the caller consumes stdout via $(...) command
# substitution, which SILENTLY STRIPS NUL bytes — so a value validated AFTER the $(...) round-trip
# differs from what jq produced. A JSON   escape is VALID JSON; jq -r decodes it to a real NUL
# that $(...) would erase. jq is the integrity point: it sees the decoded bytes intact, so a value
# matching jq/Oniguruma [[:cntrl:]] (any C0/C1/DEL control byte, NUL included) is rejected -> exit 2
# (MALFORMED), never emitted. NOTE the regex MUST be [[:cntrl:]]: a [\\u0000-\\u001f] range does NOT
# work in jq — jq's JSON string parser decodes \\u to a single backslash+u that Oniguruma treats as
# the printable letter u, so that range silently matches printable text and never a control byte.
# (next line retains the original illustrative bytes; the active gate uses [[:cntrl:]] below.)
# carrying ANY C0 control byte ( -) is rejected -> exit 2 (MALFORMED), never emitted.
#
# SLURP + index .[0] (root cause): same single-document discipline as
# hivemind_manifest_validate_shape / _strain_count_snapshot — select the strain at $index from the
# ONE top-level document, never from a concatenated stream; a multi-document snapshot exits 2.
#
# IMPLEMENTATION: jq classifies INSIDE the program (while bytes are intact) and emits a fixed
# one-char CLASS tag as the FIRST char of its output: "0"+value (present+valid), "1" (absent),
# "2" (rejected). Bash slices the leading class char and maps it to the exit code; only an exit-0
# value reaches stdout. The class is computed in jq so no untrusted byte ever drives a bash branch.
hivemind_manifest_field_at() {
  local content="$1"
  local index="$2"
  local field="$3"

  local jq_path
  case "$field" in
    worktree_path|branch|tmux_session|status)
      jq_path=".${field}" ;;
    run.suggested_id|suggested_id)
      jq_path=".run.suggested_id" ;;
    run.suggested_ledger|suggested_ledger)
      jq_path=".run.suggested_ledger" ;;
    run.workflow_hint|workflow_hint)
      jq_path=".run.workflow_hint" ;;
    *)
      return 1 ;;
  esac

  # CONTROL-BYTE REJECTION INSIDE jq (root cause): the extracted value is consumed by the
  # caller via `$(...)` command substitution, which SILENTLY STRIPS NUL bytes — so a value the
  # caller validates AFTER the `$(...)` round-trip differs from what jq produced. A JSON ` `
  # escape is VALID JSON; `jq -r` decodes it to a real NUL that `$(...)` would erase, turning a
  # value like `feature/api -slice` into the trusted-looking `feature/api-slice` before the
  # allowlist ever sees it. We make jq the integrity point: jq sees the decoded bytes intact, so
  # if the resolved value contains ANY C0 control byte ( - ) we emit NOTHING (empty), exactly
  # as for an absent field. The caller never receives a control-bearing value to strip, and an
  # empty value is rendered MALFORMED by its value-class gate. (` ` is `\u0000`; `` is the
  # last C0 control byte. jq's regex engine matches the decoded codepoints, not the escapes.)
  # SLURP + index .[0] (root cause): same single-document discipline as
  # hivemind_manifest_validate_shape / _strain_count_snapshot — select the strain at $index from the
  # ONE top-level document, never from a concatenated stream.
  # jq emits a class-tagged value: "0"+raw (present+valid), "1" (absent: null/empty string),
  # "2" (rejected: multi-document, non-string scalar, or C0 control byte). The leading class char
  # is sliced off in bash and mapped to the exit code; only an exit-0 value reaches stdout.
  local tagged
  tagged="$(printf '%s' "$content" \
    | jq -r -s --argjson i "$index" "
        if (length != 1) then \"2\"
        else
          (.[0].strains[\$i] | $jq_path) as \$raw
          | if (\$raw == null) then \"1\"
            elif (\$raw|type) != \"string\" then \"2\"
            elif (\$raw == \"\") then \"1\"
            elif (\$raw | test(\"[[:cntrl:]]\")) then \"2\"
            else \"0\" + \$raw end
        end" 2>/dev/null)" || return 2

  case "$tagged" in
    0*)
      printf '%s\n' "${tagged#0}"
      return 0 ;;
    2*)
      return 2 ;;
    1*)
      return 1 ;;
    *)
      # jq produced no tag at all (torn/empty) → present-but-invalid, never a silent MISSING.
      return 2 ;;
  esac
}
