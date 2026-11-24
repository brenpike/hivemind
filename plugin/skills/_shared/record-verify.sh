# shellcheck shell=bash
#
# record-verify.sh — shared review record verify library (ADR-0046 decision 7): the one
# implementation of verify, which checks each design review record a pull request touches
# against the solution design's Review record front matter and Review record body rules. Its
# callers are the guide's script before `gh pr ready`, the design review skill's script and a
# repository's own validation; each sources it from its own script entry.
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources the readiness check library
# first, then this file, both by absolute path derived from its OWN script_dir
# (`. "$plugin_root/skills/_shared/record-verify.sh"`). It defines functions only; it runs no
# top-level statements, sources no other file and changes no caller state beyond defining the
# functions below. Sourcing it twice is harmless. `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately
# OMITS the P18 shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced
# file mutates the SOURCING shell's option state, so installing those here would corrupt
# every caller's shell; the floor is therefore the documented exception, not the full
# `set -euo pipefail`. This file carries no top-level `set` at all (pure function
# definitions); each caller owns its own `set -u` and error routing. Allowlisted under
# CHECK13 as a P18 documented exception.
#
# SINGLE RESPONSIBILITY: decide whether review records are consistent and current, never the
# quality of the review. It writes nothing: no file, no scratch path. Every repository path, a
# record found by discovery, a stamp path or a recorded Note's path, is read only through the
# readiness check library's Document existence test (hivemind_doc_entry, hivemind_doc_read).
# Text reaches jq only on stdin, never in argv or program text, and is parsed by the readiness
# check's jq definitions (hivemind_readiness_jq_defs), so a line's ending CR is removed first.
# Every git call is `git --no-replace-objects --literal-pathspecs ...`, resolves no ref and makes
# no network call; each commit argument passes hivemind_readiness_commit_ok before any git call.
# Changed paths come from `git diff --no-renames --name-only -z`. It makes no `gh` call. The
# functions behave the same under a caller's `set -euo pipefail` or `set -u` alone.
#
# FAILURE CONTRACT: exit status 0 when every checked record passes. Status 1 prints one line
# `record-verify-failed: <record path>` per failing record, sorted, to stdout. Status 2 leaves
# stdout empty and prints exactly one stderr line `record-verify-error: <token>`. Tokens: usage,
# missing-readiness-lib (a readiness check function is not defined), commit-malformed,
# commit-unresolvable, git-failed. The library never exits and never prints document text.
#
# PUBLIC API:
#   hivemind_record_verify <head> <base>
#       Pull request mode, <base> the merge-base with trunk. Each record the pull request adds or
#       edits (`docs/initiatives/<slug>/review-record.md`) gets every check, whether or not its
#       design is delivered: the front matter shape; a stamp of `docs/prds/<slug>.md`, whose
#       first non-blank line after its title is exactly `**UI:** yes` or `**UI:** no` at <head>;
#       the Findings table; each `recorded` Note's path; and the pass rule when `verdict` is
#       pass. When `verdict` is pass, its stamps also include both UI prototype files when the
#       PRD says yes and every ADR the pull request adds or edits, and each stamp equals its
#       blob at <head>. Every other record at <head> whose `verdict` is pass and whose design is
#       not delivered gets stamp equality only; any other record is skipped. The Residuals and
#       History sections are never read.
#   hivemind_record_verify_merge <head> <merge-base> <base-tip>
#       Merge mode, the changes read from <merge-base> to <head>: every pull request mode check,
#       and each record the pull request adds or edits, and the record of every
#       `docs/initiatives/<s>/` folder it changes, must meet the pass rule; a changed folder
#       with no record fails, named by its record path, and none of those records is skipped as
#       delivered. A stamp-equality record also fails when a stamp path's blob at <base-tip>
#       differs from its blob at <merge-base>.
#
# CHECKS: the Findings table is the one table under the record's one `## Findings` section,
# with the exact header `| ID | Round | Angle | Severity | Disposition | Note |`, a delimiter
# row and six cells per row; an empty section holds no finding. IDs are non-empty and unique;
# Angle is A, B, confirm or review; Severity is critical, high, medium or low; Disposition is
# fixed, rejected, deferred, recorded or open. A deferred Note holds a `#<n>` reference, by shape
# only. A recorded Note holds at least one path, a Markdown link target read from the record's
# folder or a code span read from the repository root, that normalizes inside the repository,
# holds no `.git` part and no control character, and passes the Document existence test at
# <head>. Each front matter open count equals the table's rows of that severity whose
# Disposition is open, a critical or high one counting open unless fixed or rejected. The pass
# rule: `verdict` pass, every open count 0, `clean_round` true and `rounds` 2 to 3; a record
# whose `verdict` is pass fails unless it meets the rule.

# _hivemind_rv_error <token>: prints the one failure line to stderr.
_hivemind_rv_error() {
  printf 'record-verify-error: %s\n' "$1" >&2
}

# _hivemind_rv_jq_defs: prints the constant jq definitions of verify; they need
# hivemind_readiness_jq_defs before them. Each filter runs under rc_doc_eval, so its input is
# {prefix, texts}: the prefix line is the document's repository path.
_hivemind_rv_jq_defs() {
  printf '%s\n' '
def rv_ui:
  .texts | rc_parse | rc_after_title
  | if . == "**UI:** yes" then "yes" elif . == "**UI:** no" then "no" else "invalid" end;
def rv_delivered:
  if (.texts | rc_parse | rc_after_title) == "**Status:** delivered" then "delivered"
  else "not-delivered" end;
def rv_pass_rule:
  .verdict == "pass" and all(.open[]; . == 0) and .clean_round == true
  and .rounds >= 2 and .rounds <= 3;
def rv_one_of($values): . as $value | any($values[]; . == $value);
def rv_cells:
  rc_trim
  | if test("\\A\\|.*[^\\\\]\\|\\z") then [.[1:-1] | splits("(?<!\\\\)\\|") | rc_trim]
    else null end;
def rv_findings:
  . as $doc
  | if ([$doc[] | select(.level == 2 and .title == "Findings")] | length) != 1 then null
    else [($doc | rc_section(2; "Findings") // [])[] | select(.text | rc_blank | not)] as $body
    | if ($body | length) == 0 then []
      elif any($body[]; .fenced or .level > 0) then null
      elif $body[0].text != "| ID | Round | Angle | Severity | Disposition | Note |" then null
      elif ($body | length) < 2 then null
      elif ($body[1].text | rv_cells
            | . == null or length != 6 or any(.[]; test("\\A:?-+:?\\z") | not)) then null
      else [$body[2:][] | .text | rv_cells] as $rows
      | if any($rows[]; . == null or length != 6) then null
        else [$rows[] | {id: .[0], angle: .[2], severity: .[3], disposition: .[4], note: .[5]}] end
      end
    end;
def rv_rows_ok:
  ([.[] | .id] | all(.[]; length > 0) and ((unique | length) == length))
  and all(.[]; (.angle | rv_one_of(["A", "B", "confirm", "review"]))
      and (.severity | rv_one_of(["critical", "high", "medium", "low"]))
      and (.disposition | rv_one_of(["fixed", "rejected", "deferred", "recorded", "open"])))
  and all(.[] | select(.disposition == "deferred");
      .note | test("(?<![A-Za-z0-9_/&])#[1-9][0-9]*(?![A-Za-z0-9_])"));
def rv_open_counts:
  reduce .[] as $row ({critical: 0, high: 0, medium: 0, low: 0};
    if $row.disposition == "open"
       or (($row.severity == "critical" or $row.severity == "high")
           and $row.disposition != "fixed" and $row.disposition != "rejected")
    then .[$row.severity] += 1 else . end);
def rv_normalize:
  if (explode | any(.[]; . < 32 or . == 127)) or startswith("/") then null
  else reduce split("/")[] as $segment ([];
      if . == null then null
      elif $segment == "" or $segment == "." then .
      elif $segment == ".." then (if length == 0 then null else .[:-1] end)
      else . + [$segment] end)
    | if . == null or length == 0 or any(.[]; ascii_downcase == ".git") then null
      else join("/") end
  end;
def rv_note_paths($folder):
  [(match("\\]\\(([^()[:space:]]*)\\)"; "g") | .captures[0].string // ""
    | sub("#.*\\z"; "") | select(length > 0) | $folder + "/" + .),
   (match("`([^`]+)`"; "g") | .captures[0].string // "")]
  | map(rv_normalize | select(. != null)) | unique;
def rv_record:
  ("docs/initiatives/" + (.prefix | rc_path_slug)) as $folder
  | [.texts | rc_front_matter] as $front
  | if ($front | length) == 0 then "malformed"
    else $front[0] as $fm
    | (.texts | rc_parse | rv_findings) as $rows
    | "verdict\t" + $fm.verdict,
      (if $fm | rv_pass_rule then "pass-rule" else empty end),
      (if $rows == null or ($rows | rv_rows_ok | not) or ($rows | rv_open_counts) != $fm.open
          or ($fm.verdict == "pass" and ($fm | rv_pass_rule | not))
       then "invalid" else empty end),
      ($fm.stamps[] | "stamp\t" + .path + "\t" + .blob),
      (($rows // []) | to_entries[] | select(.value.disposition == "recorded")
       | (.key | tostring) as $row
       | "recorded\t" + $row,
         (.value.note | rv_note_paths($folder) | .[] | "path\t" + $row + "\t" + .))
    end;
'
}

# _hivemind_rv_lib_ok: 0 when every readiness check function verify calls is defined, else 1.
_hivemind_rv_lib_ok() {
  declare -F hivemind_readiness_commit_ok hivemind_readiness_path_kind hivemind_doc_entry \
    hivemind_doc_read hivemind_readiness_jq_defs >/dev/null 2>&1
}

# _hivemind_rv_commit_resolves <commit>: 0 when <commit> names a commit object, else 1.
_hivemind_rv_commit_resolves() {
  local object_type=""
  object_type="$(git --no-replace-objects --literal-pathspecs cat-file -t "$1" </dev/null 2>/dev/null)" \
    || object_type=""
  [ "$object_type" = commit ]
}

# _hivemind_rv_preflight <commit>...: checks the readiness library and every commit, with no git
# call before each commit passes its shape check; prints the token and returns 2 on the first
# failure.
_hivemind_rv_preflight() {
  local commit=""
  if ! _hivemind_rv_lib_ok; then
    _hivemind_rv_error missing-readiness-lib
    return 2
  fi
  for commit in "$@"; do
    if ! hivemind_readiness_commit_ok "$commit" 2>/dev/null; then
      _hivemind_rv_error commit-malformed
      return 2
    fi
  done
  for commit in "$@"; do
    if ! _hivemind_rv_commit_resolves "$commit"; then
      _hivemind_rv_error commit-unresolvable
      return 2
    fi
  done
}

# _hivemind_rv_z_lines: reads NUL-terminated path records, then one trailer record holding git's
# exit status, from stdin; prints `ok` then one line per path, each control character shown as
# `?`, or prints `failed` when git failed or the trailer is missing.
_hivemind_rv_z_lines() {
  local record="" previous="" have_previous=0
  local -a paths=()
  while IFS= read -r -d '' record; do
    if [ "$have_previous" -eq 1 ]; then
      paths+=("${previous//[[:cntrl:]]/?}")
    fi
    previous="$record"
    have_previous=1
  done
  if [ "$have_previous" -eq 0 ] || [ "$previous" != 0 ]; then
    printf 'failed\n'
    return 0
  fi
  printf 'ok\n'
  if [ "${#paths[@]}" -gt 0 ]; then
    printf '%s\n' "${paths[@]}"
  fi
}

# _hivemind_rv_git_paths <git-arg>...: runs one NUL-separated git listing and prints its paths,
# one per line, in the form _hivemind_rv_z_lines gives; returns 2 when git failed.
_hivemind_rv_git_paths() {
  local git_rc=0 output=""
  output="$(
    {
      git --no-replace-objects --literal-pathspecs "$@" </dev/null 2>/dev/null || git_rc=$?
      printf '%s\0' "$git_rc"
    } | _hivemind_rv_z_lines
  )" || output=failed
  if [ "${output%%$'\n'*}" != ok ]; then
    return 2
  fi
  if [ "$output" != ok ]; then
    printf '%s\n' "${output#ok$'\n'}"
  fi
}

# _hivemind_rv_changed_paths <from> <to> [<diff-option>]: prints the paths the diff from <from> to
# <to> changes, one per line; returns 2 when git failed.
_hivemind_rv_changed_paths() {
  _hivemind_rv_git_paths -c diff.relative=false diff --no-renames --name-only -z "${@:3}" \
    "$1" "$2" --
}

# _hivemind_rv_kind <path>: prints the readiness path kind of <path>, or nothing.
_hivemind_rv_kind() {
  case "$1" in
    docs/initiatives/* | docs/adr/*) hivemind_readiness_path_kind "$1" 2>/dev/null || true ;;
  esac
}

# _hivemind_rv_doc_eval <commit> <path> <filter>: streams the line <path>, the bytes of the
# document at <path> and its hivemind_doc_read status into one jq program running
# rc_doc_eval(<filter>), and prints its raw output: `missing` for a missing document, else the
# filter's lines. Returns 2 on a failure.
_hivemind_rv_doc_eval() {
  local commit="$1" path="$2" read_rc=0 output="" program
  program="$(hivemind_readiness_jq_defs)$(_hivemind_rv_jq_defs)rc_doc_eval($3)"
  if ! output="$(
    {
      printf '%s\n' "$path"
      hivemind_doc_read "$commit" "$path" 2>/dev/null || read_rc=$?
      printf '\n%s' "$read_rc"
    } | jq -Rsr "$program" 2>/dev/null
  )"; then
    return 2
  fi
  if [ "$output" = failed ]; then
    return 2
  fi
  printf '%s\n' "$output"
}

# _hivemind_rv_summary_has <summary> <line>: 0 when <summary> holds exactly the line <line>.
_hivemind_rv_summary_has() {
  case $'\n'"$1"$'\n' in
    *$'\n'"$2"$'\n'*) return 0 ;;
  esac
  return 1
}

# _hivemind_rv_stamped <summary>: prints the summary's stamp paths, space-separated and
# space-delimited, as ` <path> <path> `.
_hivemind_rv_stamped() {
  local line="" stamp="" stamped=" "
  local -a lines=()
  mapfile -t lines < <(printf '%s\n' "$1")
  for line in "${lines[@]}"; do
    case "$line" in
      stamp$'\t'*)
        stamp="${line#stamp$'\t'}"
        stamped+="${stamp%%$'\t'*} "
        ;;
    esac
  done
  printf '%s\n' "$stamped"
}

# _hivemind_rv_entry_state <commit> <path>: prints `0 <blob id>` when <path> passes the Document
# existence test at <commit>, else `1`; returns 2 on a failure.
_hivemind_rv_entry_state() {
  local oid="" entry_rc=0
  oid="$(hivemind_doc_entry "$1" "$2" 2>/dev/null)" || entry_rc=$?
  case "$entry_rc" in
    0) printf '0 %s\n' "$oid" ;;
    1) printf '1\n' ;;
    *) return 2 ;;
  esac
}

# _hivemind_rv_stamps_match <commit> <summary>: 0 when each stamp equals its path's blob at
# <commit>, 1 when one differs or its path fails the Document existence test, 2 on a failure.
_hivemind_rv_stamps_match() {
  local commit="$1" line="" stamp="" state=""
  local -a lines=()
  mapfile -t lines < <(printf '%s\n' "$2")
  for line in "${lines[@]}"; do
    case "$line" in
      stamp$'\t'*)
        stamp="${line#stamp$'\t'}"
        state="$(_hivemind_rv_entry_state "$commit" "${stamp%%$'\t'*}")" || return 2
        if [ "$state" != "0 ${stamp#*$'\t'}" ]; then
          return 1
        fi
        ;;
    esac
  done
}

# _hivemind_rv_stamps_stable <merge-base> <base-tip> <summary>: 0 when each stamp path's entry
# at <base-tip> equals its entry at <merge-base>, 1 when one differs, 2 on a failure.
_hivemind_rv_stamps_stable() {
  local line="" path="" before="" after=""
  local -a lines=()
  mapfile -t lines < <(printf '%s\n' "$3")
  for line in "${lines[@]}"; do
    case "$line" in
      stamp$'\t'*)
        path="${line#stamp$'\t'}"
        path="${path%%$'\t'*}"
        before="$(_hivemind_rv_entry_state "$1" "$path")" || return 2
        after="$(_hivemind_rv_entry_state "$2" "$path")" || return 2
        if [ "$before" != "$after" ]; then
          return 1
        fi
        ;;
    esac
  done
}

# _hivemind_rv_recorded_ok <head> <summary>: 0 when every recorded row of the summary names at
# least one path that passes the Document existence test at <head>, 1 when one names none, 2 on
# a failure.
_hivemind_rv_recorded_ok() {
  local head="$1" line="" row="" state=""
  local -a lines=()
  local -A wanted=() found=()
  mapfile -t lines < <(printf '%s\n' "$2")
  for line in "${lines[@]}"; do
    case "$line" in
      recorded$'\t'*)
        wanted["${line#recorded$'\t'}"]=1
        ;;
      path$'\t'*)
        row="${line#path$'\t'}"
        if [ -z "${found[${row%%$'\t'*}]-}" ]; then
          state="$(_hivemind_rv_entry_state "$head" "${row#*$'\t'}")" || return 2
          if [ "${state%% *}" = 0 ]; then
            found["${row%%$'\t'*}"]=1
          fi
        fi
        ;;
    esac
  done
  for row in "${!wanted[@]}"; do
    if [ -z "${found[$row]-}" ]; then
      return 1
    fi
  done
}

# _hivemind_rv_pass_stamps_ok <head> <slug> <ui> <summary> <required-adr>...: the checks of a
# record whose verdict is pass: its stamps include both UI prototype files when <ui> is yes and
# every <required-adr>, and each stamp equals its blob at <head>. 0, 1 or 2 on a failure.
_hivemind_rv_pass_stamps_ok() {
  local head="$1" slug="$2" ui="$3" summary="$4" stamped="" path=""
  local -a required=()
  shift 4
  if [ "$ui" = yes ]; then
    required+=("docs/initiatives/$slug/prototype/index.html" "docs/initiatives/$slug/prototype/notes.md")
  fi
  required+=("$@")
  stamped="$(_hivemind_rv_stamped "$summary")"
  for path in "${required[@]}"; do
    case "$stamped" in
      *" $path "*) ;;
      *) return 1 ;;
    esac
  done
  _hivemind_rv_stamps_match "$head" "$summary"
}

# _hivemind_rv_full_ok <head> <record> <pass-rule> <required-adr>...: every check of a record the
# pull request adds or edits, or of a changed folder's record in merge mode; <pass-rule> yes also
# requires the pass rule. 0 when it passes, 1 when it fails, 2 on a failure.
_hivemind_rv_full_ok() {
  local head="$1" record="$2" pass_rule="$3" summary="" slug="" ui="" check_rc=0
  shift 3
  if [ "$(_hivemind_rv_kind "$record")" != review-record ]; then
    return 1
  fi
  summary="$(_hivemind_rv_doc_eval "$head" "$record" rv_record)" || return 2
  case "$summary" in
    missing | malformed) return 1 ;;
  esac
  if _hivemind_rv_summary_has "$summary" invalid; then
    return 1
  fi
  if [ "$pass_rule" = yes ] && ! _hivemind_rv_summary_has "$summary" pass-rule; then
    return 1
  fi
  slug="${record#docs/initiatives/}"
  slug="${slug%%/*}"
  case "$(_hivemind_rv_stamped "$summary")" in
    *" docs/prds/$slug.md "*) ;;
    *) return 1 ;;
  esac
  ui="$(_hivemind_rv_doc_eval "$head" "docs/prds/$slug.md" rv_ui)" || return 2
  case "$ui" in
    yes | no) ;;
    *) return 1 ;;
  esac
  if _hivemind_rv_summary_has "$summary" $'verdict\tpass'; then
    _hivemind_rv_pass_stamps_ok "$head" "$slug" "$ui" "$summary" "$@" || check_rc=$?
    if [ "$check_rc" -ne 0 ]; then
      return "$check_rc"
    fi
  fi
  _hivemind_rv_recorded_ok "$head" "$summary"
}

# _hivemind_rv_other_ok <head> <record> [<merge-base> <base-tip>]: the check of a record verify
# does not fully check. A record whose verdict is pass and whose design is not delivered gets
# stamp equality at <head>, and in merge mode stable stamp paths from <merge-base> to <base-tip>;
# any other record is skipped. 0 when it passes or is skipped, 1 when it fails, 2 on a failure.
_hivemind_rv_other_ok() {
  local head="$1" record="$2" summary="" slug="" status="" check_rc=0
  summary="$(_hivemind_rv_doc_eval "$head" "$record" rv_record)" || return 2
  if ! _hivemind_rv_summary_has "$summary" $'verdict\tpass'; then
    return 0
  fi
  slug="${record#docs/initiatives/}"
  slug="${slug%%/*}"
  status="$(_hivemind_rv_doc_eval "$head" "docs/initiatives/$slug/solution-design.md" rv_delivered)" \
    || return 2
  if [ "$status" = delivered ]; then
    return 0
  fi
  _hivemind_rv_stamps_match "$head" "$summary" || check_rc=$?
  if [ "$check_rc" -ne 0 ] || [ "$#" -ne 4 ]; then
    return "$check_rc"
  fi
  _hivemind_rv_stamps_stable "$3" "$4" "$summary"
}

# _hivemind_rv_discover <head>: prints the path of each record at <head>, one per line: the
# review record path of each `docs/initiatives/` folder that passes the Document existence test.
# Returns 2 on a failure.
_hivemind_rv_discover() {
  local head="$1" listing="" name="" record="" state=""
  local -a names=()
  listing="$(_hivemind_rv_git_paths ls-tree --full-tree -z --name-only "$head" -- docs/initiatives/)" \
    || return 2
  mapfile -t names < <(printf '%s' "$listing")
  for name in "${names[@]}"; do
    record="docs/initiatives/${name#docs/initiatives/}/review-record.md"
    if [ "$(_hivemind_rv_kind "$record")" != review-record ]; then
      continue
    fi
    state="$(_hivemind_rv_entry_state "$head" "$record")" || return 2
    if [ "${state%% *}" = 0 ]; then
      printf '%s\n' "$record"
    fi
  done
}

# _hivemind_rv_check_one <check-fn> <head> <record> <arg>...: runs one record check and prints
# <record> when it fails; returns 2 on a failure.
_hivemind_rv_check_one() {
  local check_rc=0
  "$@" || check_rc=$?
  case "$check_rc" in
    0) ;;
    1) printf '%s\n' "$3" ;;
    *) return 2 ;;
  esac
}

# _hivemind_rv_run <head> <from> [<base-tip>]: verifies the records of the changes from <from> to
# <head>; with <base-tip>, in merge mode. Prints the sorted failure lines and returns 0 or 1, or
# prints git-failed and returns 2 with stdout empty.
_hivemind_rv_run() {
  local head="$1" from="$2" listing="" path="" kind="" rest="" record="" failures="" output=""
  local edited_rule=no check_rc=0
  local -a changed=() kept=() adrs=() discovered=() merge_args=()
  local -A full=()
  if [ "$#" -eq 3 ]; then
    merge_args=("$2" "$3")
    edited_rule=yes
  fi
  if ! listing="$(_hivemind_rv_changed_paths "$from" "$head" --diff-filter=d)"; then
    _hivemind_rv_error git-failed
    return 2
  fi
  mapfile -t kept < <(printf '%s' "$listing")
  for path in "${kept[@]}"; do
    kind="$(_hivemind_rv_kind "$path")"
    case "$kind" in
      review-record) full["$path"]=edited ;;
      adr) adrs+=("$path") ;;
    esac
  done
  if [ "$#" -eq 3 ]; then
    if ! listing="$(_hivemind_rv_changed_paths "$from" "$head")"; then
      _hivemind_rv_error git-failed
      return 2
    fi
    mapfile -t changed < <(printf '%s' "$listing")
    for path in "${changed[@]}"; do
      rest="${path#docs/initiatives/}"
      if [ "$rest" != "$path" ] && [ "${rest#*/}" != "$rest" ]; then
        record="docs/initiatives/${rest%%/*}/review-record.md"
        full["$record"]="${full[$record]-folder}"
      fi
    done
  fi
  if ! listing="$(_hivemind_rv_discover "$head")"; then
    _hivemind_rv_error git-failed
    return 2
  fi
  mapfile -t discovered < <(printf '%s' "$listing")
  for record in "${!full[@]}"; do
    check_rc=0
    if [ "${full[$record]}" = edited ]; then
      output="$(_hivemind_rv_check_one _hivemind_rv_full_ok "$head" "$record" "$edited_rule" \
        "${adrs[@]}")" || check_rc=$?
    else
      output="$(_hivemind_rv_check_one _hivemind_rv_full_ok "$head" "$record" yes)" || check_rc=$?
    fi
    if [ "$check_rc" -ne 0 ]; then
      _hivemind_rv_error git-failed
      return 2
    fi
    failures+="${output:+$output$'\n'}"
  done
  for record in "${discovered[@]}"; do
    if [ -n "${full[$record]-}" ]; then
      continue
    fi
    if ! output="$(_hivemind_rv_check_one _hivemind_rv_other_ok "$head" "$record" "${merge_args[@]}")"; then
      _hivemind_rv_error git-failed
      return 2
    fi
    failures+="${output:+$output$'\n'}"
  done
  if [ -z "$failures" ]; then
    return 0
  fi
  if ! output="$(printf '%s' "$failures" | LC_ALL=C sort -u)"; then
    _hivemind_rv_error git-failed
    return 2
  fi
  printf 'record-verify-failed: %s\n' "${output//$'\n'/$'\nrecord-verify-failed: '}"
  return 1
}

# hivemind_record_verify <head> <base>: pull request mode (see PUBLIC API).
hivemind_record_verify() {
  if [ "$#" -ne 2 ]; then
    _hivemind_rv_error usage
    return 2
  fi
  _hivemind_rv_preflight "$1" "$2" || return 2
  _hivemind_rv_run "$1" "$2"
}

# hivemind_record_verify_merge <head> <merge-base> <base-tip>: merge mode (see PUBLIC API).
hivemind_record_verify_merge() {
  if [ "$#" -ne 3 ]; then
    _hivemind_rv_error usage
    return 2
  fi
  _hivemind_rv_preflight "$1" "$2" "$3" || return 2
  _hivemind_rv_run "$1" "$2" "$3"
}
