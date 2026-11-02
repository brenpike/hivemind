# shellcheck shell=bash
#
# ledger-engine-io.sh — shared run-ledger READ + BOOTSTRAP machinery for the three
# committed hivemind ledger engines and the next-wave reader. Defines two functions extracted
# VERBATIM (pure code-move, behavior byte-preserving) from the engine monoliths:
#   hivemind_read_inputs_file — the inputs-file arg/existence/read-guard/JSON-validity
#     bootstrap, shared by ALL THREE engines (init-run-ledger, record-state-result,
#     mark-intent-fallback).
#   hivemind_open_ledger — the repo-root → ledger-path derivation + depth-complete
#     containment + ledger-read + coherence + post-existence canonical confirmation,
#     shared by record-state-result + mark-intent-fallback (NOT init, which CREATES a
#     ledger rather than opening an existing one).
# and the ONE whole-string safe-id check for an argv value (issue #424):
#   hivemind_is_safe_id — the shell-side check for one argv value (1 to 255 bytes). An id read
#     from a JSON file is checked by hivemind_check_json instead, on the intact JSON value.
# and the ONE contract check for an untrusted JSON file (issue #424):
#   hivemind_check_json — checks a whole JSON file against a fixed contract table, inside one
#     constant jq program, on the intact JSON values, and prints a failure as one fixed line
#     that never contains a value from the file.
# Both readers (hivemind_read_inputs_file, hivemind_open_ledger) accept only a file that holds
# exactly one JSON document, and that document must be an object.
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each engine sources it by absolute
# path derived from its OWN script_dir (`. "$plugin_root/skills/_shared/ledger-engine-io.sh"`).
# It defines functions only; it runs no top-level statements and changes no caller state
# beyond defining the functions below. `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately
# OMITS the P18 shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced
# file mutates the SOURCING shell's option state, so installing those here would corrupt
# every engine's shell; the floor is therefore the documented exception, not the full
# `set -euo pipefail`. This file carries no top-level `set` at all (pure function
# definitions); each ENGINE owns its own `set -u`, EXIT trap, and error routing.
# Allowlisted under CHECK13 as a P18 documented exception.
#
# VARIABLE CONTRACT: every function runs in the SOURCING (engine) shell under `set -u`.
# Every variable they touch is `local` or a passed argument — they read NO caller-shell
# globals. No function calls `exit`; each returns non-zero on failure (the two IO functions
# with a message on stderr or stdout, per their contracts below), and the engine maps that
# non-zero return to its OWN blocker()/exit contract (mirroring the never-exit contract of the
# containment.sh helpers these functions orchestrate).
#
# DEPENDENCY CONTRACT: the IO functions ORCHESTRATE the containment.sh helpers
# (hivemind_assert_inputs_contained, hivemind_assert_contained, hivemind_assert_ledger_contained)
# at CALL time — this library does NOT source containment.sh. The ENGINE MUST have sourced
# containment.sh BEFORE calling either IO function. They also require `jq` and `git`
# on PATH (the engine's own up-front `command -v jq` dependency check covers jq).
# hivemind_is_safe_id needs neither; hivemind_check_json needs jq.

# hivemind_is_safe_id <value>
#
# Returns 0 iff the WHOLE <value> is 1 to 255 bytes of the safe-id charset [A-Za-z0-9._-],
# else 1. Pure: no output, never exits. The reserved components "." and ".." pass this check;
# a caller that uses the value as a path component rejects them itself. The 255 cap matches the
# `name` kind of hivemind_check_json and the longest file name most file systems allow.
#
# WHY NOT `printf '%s' "$v" | grep -Eq '^[A-Za-z0-9._-]+$'` (the form this replaces): grep is
# line-based, so a value with an embedded line feed passes when ANY one of its lines is safe
# (e.g. "ok<LF>../x"). The bash `=~` match anchors `^`/`$` to the whole string, and a line feed
# is outside the class. LC_ALL=C pins the ranges to ASCII: under a UTF-8 locale such as
# en_US.UTF-8, `[A-Za-z]` also admits letters such as "é".
hivemind_is_safe_id() {
  local LC_ALL=C
  [[ $1 =~ ^[A-Za-z0-9._-]{1,255}$ ]]
}

# hivemind_check_json <json_file> <contract> [<field>]
#
# Checks the WHOLE <json_file> against the fixed contract table named <contract>, inside ONE
# constant jq program, on the intact JSON values. WHY: a field-at-a-time `x="$(jq -r .f)"` read
# drops every trailing line feed and cuts the value at a NUL, so a later shell-side check sees a
# different value than the file holds. The contract name and the field enter jq only as --arg
# data, never as program text. NEVER exits.
#
# The file must hold exactly one JSON document, an object; the readers hivemind_read_inputs_file
# and hivemind_open_ledger already require that, so a contract check never meets anything else.
#
# KINDS (each a whole-value check; a string kind refuses any non-string):
#   step-id   \A[A-Za-z0-9._-]{1,64}\z
#   name      \A[A-Za-z0-9._-]{1,255}\z, and not "." or ".."
#   brood-id  \A[A-Za-z0-9._:-]{1,255}\z
#   enum      one of the listed strings
#   count     a JSON number that is a whole number of 0 or more (never a string)
#   text      a string; when required, not ""
#   object, array
# NEED: required or optional. Absent means the key is missing or null; "" is present. An array
# element ([] in a path) is never absent: a null element fails its kind. A missing or null
# parent makes its children absent; a parent that is present but not an object (or not an
# array, for []) fails at the parent's position.
#
# CONTRACTS (rows in table order; "step rows at R" is: R array; R[] object; R[].id required
# step-id; R[].depends_on optional array; R[].depends_on[] step-id):
#   init-inputs        workflow required name; workflow_version optional count; start_state
#                      optional name; user_request required text; normalized required text;
#                      parent optional object; parent.kind optional enum none, brood;
#                      parent.run_id optional text; parent.brood_id optional brood-id;
#                      parent.strain_id optional name; parent.manifest optional text;
#                      suggested_run_id optional name; step rows at plan_steps (optional);
#                      plan_path optional text.
#   init-brood-parent  parent.run_id required text; parent.brood_id required brood-id;
#                      parent.strain_id required name; parent.manifest required text.
#   record-inputs      run_id, state, result required name; summary required text; outputs
#                      optional object; outputs.completed_steps optional array; step rows at
#                      plan_steps (optional); plan_path optional text.
#   record-ledger      run.id required name; run.workflow required name; run.workflow_version
#                      required count; state.current required name.
#   intent-inputs      run_id required name; state required text; summary required text;
#                      outputs optional object; close_status optional enum cancelled, complete.
#   wave-ledger        step rows at plan.steps (required).
# The six contracts cover the inputs files and two ledgers: record-state-result checks its ledger
# against record-ledger and next-wave against wave-ledger. mark-intent-fallback has NO ledger
# contract, by design (see its header).
#
# ORDER: rows run in table order; within a [] row, positions run in ascending index (row-major
# for nested []). The FIRST failure is the only one printed.
#
# FIELD FORM: with <field> (a dotted row path of <contract> holding no []), the whole file is
# checked first; then the value of that field is printed on one line, or nothing when it is
# absent. Only a step-id, name, brood-id, enum or count field may be printed; each of those is a
# checked token, so the printed line is the whole value. A count prints as a whole number.
#
# OUTPUT: a failure prints exactly one line `<position>: <problem>` on stdout. <position> is the
# dotted path with [N] indexes (e.g. plan_steps[2].depends_on[0]); <problem> is one of the fixed
# words: missing | not an object | not an array | not a string | empty |
# not a step id (1 to 64 of A-Z a-z 0-9 . _ -) |
# not a name (1 to 255 of A-Z a-z 0-9 . _ -, not . or ..) |
# not a brood id (1 to 255 of A-Z a-z 0-9 . _ : -) | not one of <the enum values, ", "-joined> |
# not a whole number of 0 or more. The line never contains a value from the file.
#   Return codes:
#     0 the file meets the contract (whole form: no output; field form: the value or nothing)
#     1 the file breaks the contract (one problem line on stdout)
#     2 caller or tool error, one `hivemind_check_json: <reason>` line on stderr: an unknown
#       contract, an unknown field, a field that is not a token kind, a file that is not exactly
#       one JSON object, or a jq failure (unreadable file, invalid JSON)
hivemind_check_json() {
  local json_file="$1"
  local contract_name="$2"
  local field_name="${3-}"
  local check_mode=whole
  [ "$#" -ge 3 ] && check_mode=field
  local check_program='
    def row($dotted; $kind; $need): {path: ($dotted | split(".")), kind: $kind, need: $need};
    def enum_row($dotted; $need; $values): row($dotted; "enum"; $need) + {values: $values};
    def step_rows($root; $need):
      [ {path: $root, kind: "array", need: $need},
        {path: ($root + ["[]"]), kind: "object", need: "element"},
        {path: ($root + ["[]", "id"]), kind: "step-id", need: "required"},
        {path: ($root + ["[]", "depends_on"]), kind: "array", need: "optional"},
        {path: ($root + ["[]", "depends_on", "[]"]), kind: "step-id", need: "element"} ];
    def contract_table: {
      "init-inputs": ([
          row("workflow"; "name"; "required"),
          row("workflow_version"; "count"; "optional"),
          row("start_state"; "name"; "optional"),
          row("user_request"; "text"; "required"),
          row("normalized"; "text"; "required"),
          row("parent"; "object"; "optional"),
          enum_row("parent.kind"; "optional"; ["none", "brood"]),
          row("parent.run_id"; "text"; "optional"),
          row("parent.brood_id"; "brood-id"; "optional"),
          row("parent.strain_id"; "name"; "optional"),
          row("parent.manifest"; "text"; "optional"),
          row("suggested_run_id"; "name"; "optional") ]
        + step_rows(["plan_steps"]; "optional")
        + [ row("plan_path"; "text"; "optional") ]),
      "init-brood-parent": [
          row("parent.run_id"; "text"; "required"),
          row("parent.brood_id"; "brood-id"; "required"),
          row("parent.strain_id"; "name"; "required"),
          row("parent.manifest"; "text"; "required") ],
      "record-inputs": ([
          row("run_id"; "name"; "required"),
          row("state"; "name"; "required"),
          row("result"; "name"; "required"),
          row("summary"; "text"; "required"),
          row("outputs"; "object"; "optional"),
          row("outputs.completed_steps"; "array"; "optional") ]
        + step_rows(["plan_steps"]; "optional")
        + [ row("plan_path"; "text"; "optional") ]),
      "record-ledger": [
          row("run.id"; "name"; "required"),
          row("run.workflow"; "name"; "required"),
          row("run.workflow_version"; "count"; "required"),
          row("state.current"; "name"; "required") ],
      "intent-inputs": [
          row("run_id"; "name"; "required"),
          row("state"; "text"; "required"),
          row("summary"; "text"; "required"),
          row("outputs"; "object"; "optional"),
          enum_row("close_status"; "optional"; ["cancelled", "complete"]) ],
      "wave-ledger": step_rows(["plan", "steps"]; "required")
    };
    def token_kinds: ["step-id", "name", "brood-id", "enum", "count"];
    def render_position:
      reduce .[] as $seg ("";
        if ($seg | type) == "number" then . + "[\($seg)]"
        elif . == "" then $seg
        else . + "." + $seg end);
    def resolve_positions($segs; $pos; $elem):
      if ($segs | length) == 0 then {pos: $pos, value: ., elem: $elem}
      elif $segs[0] == "[]" then
        if . == null and ($elem | not) then empty
        elif type == "array" then
          . as $items | range(length) as $index
          | $items[$index] | resolve_positions($segs[1:]; $pos + [$index]; true)
        else {pos: $pos, problem: "not an array"} end
      elif . == null and ($elem | not) then resolve_positions($segs[1:]; $pos + [$segs[0]]; false)
      elif type == "object" then .[$segs[0]] | resolve_positions($segs[1:]; $pos + [$segs[0]]; false)
      else {pos: $pos, problem: "not an object"} end;
    def kind_problem($row):
      if $row.kind == "object" then (if type == "object" then null else "not an object" end)
      elif $row.kind == "array" then (if type == "array" then null else "not an array" end)
      elif $row.kind == "text" then
        (if type != "string" then "not a string"
         elif $row.need == "required" and . == "" then "empty"
         else null end)
      elif $row.kind == "step-id" then
        (if type == "string" and test("\\A[A-Za-z0-9._-]{1,64}\\z") then null
         else "not a step id (1 to 64 of A-Z a-z 0-9 . _ -)" end)
      elif $row.kind == "name" then
        (if type == "string" and test("\\A[A-Za-z0-9._-]{1,255}\\z") and . != "." and . != ".."
         then null else "not a name (1 to 255 of A-Z a-z 0-9 . _ -, not . or ..)" end)
      elif $row.kind == "brood-id" then
        (if type == "string" and test("\\A[A-Za-z0-9._:-]{1,255}\\z") then null
         else "not a brood id (1 to 255 of A-Z a-z 0-9 . _ : -)" end)
      elif $row.kind == "enum" then
        (. as $value
         | if any($row.values[]; . == $value) then null
           else "not one of " + ($row.values | join(", ")) end)
      elif $row.kind == "count" then
        (if type == "number" and . == floor and . >= 0 then null
         else "not a whole number of 0 or more" end)
      else error("unknown kind") end;
    def failure_line($row):
      (.pos | render_position) as $where
      | if has("problem") then $where + ": " + .problem
        elif .value == null and (.elem | not) then
          (if $row.need == "required" then $where + ": missing" else empty end)
        else (.value | kind_problem($row)) as $problem
          | if $problem == null then empty else $where + ": " + $problem end
        end;
    def field_rows($rows):
      [ $rows[] | select((any(.path[]; . == "[]") | not) and (.path | join(".")) == $field) ];
    def field_value($doc; $field_row):
      [ $doc | resolve_positions($field_row.path; []; false) ][0].value
      | if . == null then "0"
        elif type == "number" then "0" + (floor | tostring)
        else "0" + . end;
    contract_table[$contract] as $rows
    | if $rows == null then "2unknown contract"
      elif $mode == "field" and (field_rows($rows) | length) == 0 then "2unknown field"
      elif $mode == "field" and (field_rows($rows)[0].kind as $kind | any(token_kinds[]; . == $kind) | not)
        then "2field is not a token kind"
      elif length != 1 or (.[0] | type) != "object" then "2not exactly one JSON object"
      else .[0] as $doc
        | [ first($rows[] as $row | $doc | resolve_positions($row.path; []; false) | failure_line($row)) ]
        | if length > 0 then "1" + .[0]
          elif $mode == "field" then field_value($doc; field_rows($rows)[0])
          else "0" end
      end'
  local check_output
  if ! check_output="$(jq -j -s --arg contract "$contract_name" --arg field "$field_name" \
      --arg mode "$check_mode" "$check_program" "$json_file" 2>/dev/null)"; then
    printf 'hivemind_check_json: jq failed\n' >&2
    return 2
  fi
  local check_status="${check_output:0:1}"
  local check_detail="${check_output:1}"
  case "$check_status" in
    0)
      [ -n "$check_detail" ] && printf '%s\n' "$check_detail"
      return 0
      ;;
    1)
      printf '%s\n' "$check_detail"
      return 1
      ;;
    2)
      printf 'hivemind_check_json: %s\n' "$check_detail" >&2
      return 2
      ;;
    *)
      printf 'hivemind_check_json: jq failed\n' >&2
      return 2
      ;;
  esac
}

# hivemind_read_inputs_file <inputs_file_path> <label>
#
# VERBATIM inputs-file bootstrap shared by all three engines. <label> is the human-readable
# script noun each engine interpolates so its EXACT current blocker strings reproduce
# byte-for-byte (record-state-result → "record-state-result", mark-intent-fallback →
# "mark-intent-fallback", init-run-ledger → "run-ledger"). Encapsulates, IN ORDER:
#   1. the `INPUTS_FILE="${1:-}"`-style non-empty arg check,
#   2. the `[ -f ]` existence check,
#   3. the hivemind_assert_inputs_contained defense-in-depth read-guard (run BEFORE the
#      jq validity probe — `jq -e` on an attacker path is itself a JSON-validity read oracle),
#   4. the one-object probe: `jq -s` must read exactly one JSON document, an object. A plain
#      `jq -e .` accepts a file of several documents (`{}{}`), which a later field read then
#      reads as several values.
#
# Lifted verbatim from:
#   record-state-result.sh   L154-173 (label "record-state-result")
#   mark-intent-fallback.sh  L115-130, L132-133 (label "mark-intent-fallback")
#   init-run-ledger.sh       L164-181, L183-184 (label "run-ledger")
# The three differed ONLY in the label noun interpolated into the blocker strings (and the
# inputs-guard blocker text was already byte-identical across all three).
#
# STDERR / RETURN-CODE CONTRACT (byte-preservation):
#   This function emits NO stderr of its own. The non-containment failure reasons (missing
#   arg, missing file, invalid JSON) were SINGLE-LINE `blocker:` lines pre-extraction with no
#   preceding detail line, so this function only signals WHICH failure occurred via a distinct
#   non-zero return code; the ENGINE owns the (label-interpolated) fixed `blocker:` text. The
#   containment failure was a TWO-LINE sequence pre-extraction: the inner
#   hivemind_assert_inputs_contained helper's own UNPREFIXED detail line on fd2, THEN the
#   engine's `blocker:` line. To preserve that byte-for-byte, the inner-helper stderr is
#   deliberately PASS-THROUGH (UNCAPTURED — only its STDOUT is `>/dev/null`'d) so its detail
#   line reaches fd2 as a distinct line ABOVE the engine's blocker line; this function adds no
#   line of its own for the containment reject. NEVER exits.
#   Return codes (the engine maps each to its exact current blocker text):
#     0 success
#     2 missing required argument
#     3 inputs file does not exist
#     4 containment reject (inner helper already emitted its detail line to fd2, uncaptured)
#     5 inputs file is not exactly one JSON object (invalid JSON, empty, several documents,
#       or one document that is not an object)
hivemind_read_inputs_file() {
  local inputs_file="$1"
  local label="$2"

  if [ -z "$inputs_file" ]; then
    return 2
  fi
  if [ ! -f "$inputs_file" ]; then
    return 3
  fi

  # Defense-in-depth inputs READ-guard (shared helper). Refuse to READ the inputs file when
  # its canonical path escapes the checkout (e.g. via a symlinked ancestor) — converting a
  # silent external-read into a hard return BEFORE the jq validity probe below. Running this
  # BEFORE the `jq -e` probe is REQUIRED: `jq -e` opening an attacker-supplied external path
  # is itself an external-file JSON-validity read oracle, so the containment guard must gate
  # it. The helper never exits. Its STDOUT (the canonical root) is discarded with `>/dev/null`;
  # its STDERR is left UNCAPTURED so the helper's own detail line flows to fd2 as the FIRST of
  # the two byte-preserved lines (the engine adds the second, `blocker:`-prefixed line).
  if ! hivemind_assert_inputs_contained "$(git rev-parse --show-toplevel 2>/dev/null)" "$inputs_file" >/dev/null; then
    return 4
  fi

  if ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$inputs_file" >/dev/null 2>&1; then
    return 5
  fi

  return 0
}

# hivemind_open_ledger <repo_root> <run_id>
#
# VERBATIM ledger-open machinery shared by record-state-result + mark-intent-fallback (NOT
# init, which CREATES a ledger). The caller passes the already-derived <repo_root>
# (git rev-parse --show-toplevel, already non-empty-checked by the engine) and the
# already-validated <run_id> (hivemind_is_safe_id + reserved-component reject already applied by the
# engine). This function then performs, IN THIS EXACT ORDER (a reordering silently breaks
# engine determinism):
#   1. derive ledger = "$repo_root/.hivemind/runs/$run_id/state.json",
#   2. hivemind_assert_contained "$repo_root" ".hivemind/runs/$run_id" ancestor guard,
#   3. canonical-runs-dir canonicalization (cd && pwd -P) + trailing-slash prefix case-guard,
#   4. hivemind_assert_ledger_contained leaf guard (rejects a symlinked state.json LEAF),
#   5. `[ -f ]` existence + one-object ledger reads (`jq -s`: exactly one JSON document, an
#      object),
#   6. coherence check (`.run.id == run_id`),
#   7. post-existence canonical ledger-dir confirmation (canon dir + state.json/run_id
#      basename asserts).
#
# Lifted verbatim from:
#   record-state-result.sh   L229-311 (THE HOT PATH — strictest source of truth)
#   mark-intent-fallback.sh  L177-250 (byte-identical executable block; only comment prose differs)
# The two blocks (incl. every blocker string) were byte-identical, so no label parameter is
# needed — the blocker text below reproduces both engines' exact current strings.
#
# On SUCCESS: returns 0 with NO stdout. The full validation chain above (containment,
# canonicalization, leaf guard, existence, one-object read, coherence, post-existence canonical
# confirmation) is asserted via the return CODE alone; the function emits no path values. The
# locals $canon_ledger / $canon_ledger_dir computed by the post-existence confirmation block are
# confirmation-only and are NOT serialized. Consumers DERIVE the canonical ledger path locally
# after observing return 0 (the derivation is `"$repo_root/.hivemind/runs/$run_id/state.json"`
# plus the same canonicalization, which this function has already proven coherent).
#
# ELIMINATED CLASS (issue #285): the former success-path TWO-LINE positional stdout protocol
# (`printf '%s\n%s\n' "$canon_ledger" "$canon_ledger_dir"`, read back positionally by the engine
# with `IFS= read -r canon_ledger; IFS= read -r canon_ledger_dir`) is REMOVED. That newline- and
# ordering-fragile multi-value channel is closed by construction: success now carries zero stdout
# and consumers derive the path locally, so there is no positional protocol left to desync.
#
# STDERR / RETURN-CODE CONTRACT (byte-preservation):
#   Two failure SHAPES, distinguished by return code:
#
#   SHAPE A — inner-helper containment rejects (return 2 = hivemind_assert_contained ancestor
#   guard; return 6 = hivemind_assert_ledger_contained leaf guard). Pre-extraction these were
#   TWO-LINE sequences: the inner helper's own UNPREFIXED detail line on fd2, THEN the engine's
#   `blocker:` line. To preserve that byte-for-byte the inner-helper STDERR is deliberately
#   PASS-THROUGH (UNCAPTURED — only its STDOUT is `>/dev/null`'d) so its detail line reaches fd2
#   as the line ABOVE the engine's blocker line; this function writes NOTHING (neither stdout
#   nor stderr) for these two rejects. The engine maps 2/6 to its OWN fixed `blocker:` text,
#   which interpolates only values the engine already holds ($run_id for 2, $ledger for 6).
#
#   SHAPE B — every OTHER failure (canon-root empty, runs-dir canon empty, the inline runs-dir
#   trailing-slash case-guard which has NO inner helper, `[ -f ]` missing, not exactly one JSON object,
#   coherence `.run.id` mismatch, post-existence canon-dir / basename asserts). Pre-extraction
#   these were SINGLE-LINE `blocker:` lines with no preceding detail line. Some interpolate
#   values computed only INSIDE this function ($canon_ledger, $canon_ledger_dir),
#   so this function PRINTS the exact reason text (UNPREFIXED, no `blocker: `) to STDOUT and
#   returns 1; the engine captures that stdout and re-emits it through blocker() (adding the
#   `blocker: ` prefix + exit 1). One printed line in, one `blocker:` line out — matching the
#   pre-extraction single-line shape exactly. This SINGLE-LINE failure-reason channel is ONE
#   value (not the eliminated positional multi-line success protocol) and STAYS.
#
#   Success emits no stdout; SHAPE-B failure emits exactly one reason line; the two are mutually
#   exclusive by return, so the engine's single stdout capture is non-empty IFF a SHAPE-B failure
#   occurred. No `2>&1` is used on any read, so inner-helper / SHAPE-B stderr never leaks onto
#   stdout. NEVER exits.
#   Return codes: 0 success (NO stdout); 2 ancestor-guard reject (stdout empty);
#   6 leaf-guard reject (stdout empty); 1 any SHAPE-B failure (single reason line on stdout).
hivemind_open_ledger() {
  local repo_root="$1"
  local run_id="$2"

  # ── DERIVE the ledger path from git-root + run_id (NO caller path) ─────────────
  local ledger="$repo_root/.hivemind/runs/$run_id/state.json"

  # ── Depth-complete canonical-containment guard (shared helper) — BEFORE any ledger read ──
  # The shared helper walks EVERY component of the FULL chain (INCLUDING the <run_id> leaf)
  # and rejects any existing symlink component at ANY depth, then verifies the deepest existing
  # prefix stays inside the checkout — BEFORE any read, mktemp, or mv, so a rejection never
  # opens or creates a file and the on-disk ledger is byte-unchanged. Its STDOUT is captured
  # (the canonical root); its STDERR is left UNCAPTURED so the helper's own detail line flows
  # to fd2 as the FIRST of the two byte-preserved lines (the engine adds the second, `blocker:`
  # line). Capturing stdout alone (no `2>&1`) keeps that detail line on fd2.
  local canon_repo_root
  if ! canon_repo_root="$(hivemind_assert_contained "$repo_root" ".hivemind/runs/$run_id")"; then
    return 2
  fi
  if [ -z "$canon_repo_root" ]; then
    printf 'failed to canonicalize repo root %s; ledger unchanged\n' "$repo_root"
    return 1
  fi

  # Canonicalize the contained runs dir, then require the ledger live at
  # "$canon_runs/<run_id>/state.json". Trailing-slash-guarded prefix so a sibling like
  # .hivemind/runs-evil cannot prefix-match.
  local canon_runs
  canon_runs="$(cd "$canon_repo_root/.hivemind/runs" && pwd -P)"
  if [ -z "$canon_runs" ]; then
    printf 'failed to canonicalize %s/.hivemind/runs; ledger unchanged\n' "$canon_repo_root"
    return 1
  fi
  case "$canon_runs/$run_id/state.json/" in
    "$canon_runs/"*) : ;;
    *)
      printf 'ledger resolves outside the checkout runs dir; ledger unchanged\n'
      return 1
      ;;
  esac

  # ── Ledger-read LEAF guard (shared helper) — rejects a symlinked state.json LEAF ──
  # The ancestor/runs-dir guard above proves the chain DOWN TO the <run_id> run-dir but does
  # NOT inspect the state.json leaf itself. This shared helper [ -L ]-rejects the leaf on the
  # RAW path FIRST (firing even for a dangling target) before any [ -f ]/jq read. Its STDERR
  # is left UNCAPTURED (only STDOUT `>/dev/null`'d) so its detail line flows to fd2 as the
  # FIRST of the two byte-preserved lines for this reject.
  if ! hivemind_assert_ledger_contained "$repo_root" "$ledger" >/dev/null; then
    return 6
  fi

  if [ ! -f "$ledger" ]; then
    printf 'ledger file does not exist: %s\n' "$ledger"
    return 1
  fi
  if ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$ledger" >/dev/null 2>&1; then
    printf 'ledger file is not exactly one JSON object: %s\n' "$ledger"
    return 1
  fi

  # ── COHERENCE CHECK: the on-disk ledger must self-identify with the passed run_id ──
  # Compared inside jq on the intact JSON value: a `jq -r` read drops trailing line feeds, so a
  # ledger run.id "<run_id><LF>" would compare equal in the shell. The blocker names no ledger
  # value; it prints only the caller's already-checked run_id.
  if ! jq -e --arg id "$run_id" '(.run.id // "") == $id' "$ledger" >/dev/null 2>&1; then
    printf "ledger run.id does not match run_id '%s'; ledger unchanged\n" "$run_id"
    return 1
  fi

  # ── Post-existence canonical ledger-dir confirmation ───────────────────────────
  # Now that the ledger file is confirmed to exist, canonicalize its own dir and re-verify the
  # leaf/dir basenames against the contained runs dir.
  local canon_ledger_dir canon_ledger
  canon_ledger_dir="$(cd "$(dirname "$ledger")" && pwd -P)"
  if [ -z "$canon_ledger_dir" ]; then
    printf 'failed to canonicalize the ledger directory; ledger unchanged\n'
    return 1
  fi
  canon_ledger="$canon_ledger_dir/state.json"
  case "$canon_ledger/" in
    "$canon_runs/"*) : ;;
    *)
      printf 'ledger resolves outside the checkout runs dir: %s; ledger unchanged\n' "$canon_ledger"
      return 1
      ;;
  esac
  if [ "$(basename "$canon_ledger")" != "state.json" ]; then
    printf 'canonical ledger leaf is not state.json: %s; ledger unchanged\n' "$canon_ledger"
    return 1
  fi
  if [ "$(basename "$canon_ledger_dir")" != "$run_id" ]; then
    printf "canonical ledger dir name does not match run_id '%s': %s; ledger unchanged\n" "$run_id" "$canon_ledger_dir"
    return 1
  fi

  # SUCCESS: all validation passed. Return 0 with NO stdout — the engine derives the
  # canonical ledger path locally post-return-0 (see header contract). The locals
  # $canon_ledger / $canon_ledger_dir above are confirmation-only and no longer echoed.
  return 0
}
