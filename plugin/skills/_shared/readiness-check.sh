# shellcheck shell=bash
#
# readiness-check.sh — shared readiness check library (ADR-0046 decision 3): the one
# implementation of the Document existence test, the seed issue marker parse and the review
# record front matter parse, plus the closed set of readiness reason codes. Its callers are
# triage's readiness subcommand, the guide's handoff script, Lair admission, the slicing script
# and verify's record check; each sources it from its own script entry.
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute path
# derived from its OWN script_dir (`. "$plugin_root/skills/_shared/readiness-check.sh"`).
# It defines functions only; it runs no top-level statements, sources no other file and changes
# no caller state beyond defining the functions below. Sourcing it twice is harmless.
# `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately
# OMITS the P18 shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced
# file mutates the SOURCING shell's option state, so installing those here would corrupt
# every caller's shell; the floor is therefore the documented exception, not the full
# `set -euo pipefail`. This file carries no top-level `set` at all (pure function
# definitions); each caller owns its own `set -u` and error routing. Allowlisted under
# CHECK13 as a P18 documented exception.
#
# SINGLE RESPONSIBILITY: decide structure, existence and versions of initiative documents and
# issue text, never their quality. It writes nothing: no file, no scratch path. Input reaches jq
# only on stdin, never in argv or program text; only an argument the library has already checked
# against its fixed pattern (commit, owner/repo, trunk name, issue number) is passed with
# `jq --arg`. Every git call is `git --no-replace-objects --literal-pathspecs ...` and resolves no
# ref and makes no network call; a commit argument must be a full lowercase object id before any
# git call. The only GitHub read is hivemind_readiness_fetch_snapshot's `gh` call. The
# functions behave the same under a caller's `set -euo pipefail` or `set -u` alone.
#
# FAILURE CONTRACT: a failure prints exactly one stderr line `readiness-check-error: <token>`
# and returns non-zero; the library never exits and never echoes its input. Tokens: usage,
# commit-malformed, commit-unresolvable, snapshot-malformed, truncated, gh-failed, git-failed.
# A checking call prints its result to stdout only when it returns 0.
#
# PUBLIC API:
#   hivemind_readiness_commit_ok <commit>
#       0 when <commit> is 40 or 64 lowercase hex, else 1. No git call.
#   hivemind_readiness_codes
#       Prints the closed reason-code set, one base code per line, in the order of the solution
#       design's Readiness check output contract. A parameterized code ends with `:`.
#   hivemind_readiness_path_kind <path>
#       Path allowlist: prints the kind (prd, solution-design, review-record, prototype-index,
#       prototype-notes, adr) and returns 0 when <path> matches one allowlisted shape, else 1.
#       The stamp allowlist is all six kinds.
#   hivemind_doc_entry <commit> <path>
#       Document existence test: prints the blob id and returns 0 only when the commit's tree
#       holds exactly one entry at exactly <path>, of type blob and mode 100644 or 100755.
#       Returns 1 when missing (a malformed path is missing, with no git call). Returns 2 on
#       commit-malformed (no git call), commit-unresolvable or git-failed.
#       Shape-only by decision: it checks path syntax, never the allowlist. A caller passing an
#       issue-derived path MUST pass it through hivemind_readiness_path_kind first, as snapshot
#       mode does. The allowlist stays out of this entry point because verify (#619) must read
#       recorded Note paths that lie outside it. Decided by the run (review call taken per
#       decision-autonomy.md Review Calls) on the local review finding that asked for the
#       allowlist here; a later finding asking the same is a repeat of this record.
#   hivemind_doc_read <commit> <path>
#       Streams the document's bytes, read only by the blob id the existence test printed.
#       Returns 1 when missing, 2 on failure; a caller discards stdout on any non-zero return.
#   hivemind_seed_marker_slug  (issue body on stdin)
#       Prints the slug and returns 0 when the body's first line, one ending CR removed, is
#       exactly `<!-- hivemind-initiative: <slug> -->`; else returns 1 with no output.
#   hivemind_record_front_matter  (review record on stdin)
#       Parses the fixed front matter shape and prints one compact JSON object
#       {"stamps":[{"path","blob"}...],"verdict","open":{"critical","high","medium","low"},
#       "rounds","clean_round"} and returns 0; any other shape returns 1 with no output. The
#       zero-stamp form is the line `stamps: []`; a bare `stamps:` needs at least one stamp.
#   hivemind_readiness_jq_defs
#       Prints the constant jq definitions of PARSING, then those of the document layer, so a
#       caller's own jq program parses documents by the same rules. Takes no argument.
#   hivemind_readiness_check_snapshot <commit> <owner/repo> <trunk-name>  (snapshot on stdin)
#       Snapshot mode: stdin is exactly one JSON array of issue snapshot objects (GitHub GraphQL
#       Issue nodes); prints one line per element, in order,
#       {"issue","commit","track","result","reasons"}, and makes no GitHub read. A slice's
#       documents (PRD, solution design, ADRs, review record, UI prototype files) are read at
#       <commit> only through hivemind_doc_entry and hivemind_doc_read. Failure tokens:
#       commit-malformed, usage, commit-unresolvable, snapshot-malformed, truncated and the
#       document layer's git-failed.
#   hivemind_readiness_fetch_snapshot <owner/repo> <number>
#       Reads one issue snapshot through exactly one `gh api graphql` call, whose query is a
#       constant taking the owner, name and number as GraphQL variables, and prints the
#       response's `.data.repository.issue` node as one compact JSON object. A bad argument gives
#       usage with no gh call. gh missing from PATH, a non-zero gh exit, a body that is not exactly
#       one JSON object, a non-empty `errors` or a non-object issue node give gh-failed. The node
#       then takes snapshot mode's validation: snapshot-malformed, also for a node whose number
#       is not <number> or whose labels, blockedBy, subIssues or parent labels lack a pageInfo
#       object with a boolean hasNextPage, then truncated.
#   hivemind_readiness_check_gh <commit> <owner/repo> <trunk-name> <number>...
#       gh mode: checks every argument before any git or gh call (commit-malformed, usage; each
#       <number> matches `^[1-9][0-9]*$`), resolves the commit once (commit-unresolvable),
#       fetches each issue with hivemind_readiness_fetch_snapshot, then evaluates the snapshots,
#       in argument order, with snapshot mode's evaluator. Any failure leaves stdout empty.
#
# PARSING: the jq definitions in _hivemind_rc_jq_defs are the one implementation of the solution
# design's Document parsing rules, shared by issue bodies and documents: rc_lines splits a text
# into lines with one ending CR removed, rc_parse turns lines into line records
# {text, fenced, level, title}, rc_section, rc_filled and rc_reads_none read sections, and
# rc_front_matter parses the review record front matter for hivemind_record_front_matter and the
# document layer alike.

# _hivemind_rc_error <token>: prints the one failure line to stderr.
_hivemind_rc_error() {
  printf 'readiness-check-error: %s\n' "$1" >&2
}

# _hivemind_rc_jq_defs: prints the constant jq definitions shared by the jq programs below.
_hivemind_rc_jq_defs() {
  printf '%s\n' '
def rc_slug: "[a-z0-9]+(-[a-z0-9]+)*";
def rc_path_kind:
  if test("\\Adocs/prds/" + rc_slug + "\\.md\\z") then "prd"
  elif test("\\Adocs/initiatives/" + rc_slug + "/solution-design\\.md\\z") then "solution-design"
  elif test("\\Adocs/initiatives/" + rc_slug + "/review-record\\.md\\z") then "review-record"
  elif test("\\Adocs/initiatives/" + rc_slug + "/prototype/index\\.html\\z") then "prototype-index"
  elif test("\\Adocs/initiatives/" + rc_slug + "/prototype/notes\\.md\\z") then "prototype-notes"
  elif test("\\Adocs/adr/[0-9]{4}-" + rc_slug + "\\.md\\z") then "adr"
  else null end;
def rc_count($line; $key):
  $line | capture("\\A" + $key + ": (?<v>0|[1-9][0-9]*)\\z") | .v | tonumber;
def rc_strip_cr: if endswith("\r") then .[:-1] else . end;
def rc_lines: split("\n") | map(rc_strip_cr);
def rc_trim: capture("\\A[ \t]*(?<t>.*?)[ \t]*\\z").t;
def rc_blank: test("\\A[ \t]*\\z");
def rc_fence_run: [capture("\\A {0,3}(?<run>`{3,}|~{3,})")] | if length == 0 then null else .[0].run end;
def rc_line_record:
  . as $text
  | [capture("\\A(?<hashes>#{1,6}) (?<rest>.*)\\z")]
  | if length == 0 then {text: $text, fenced: false, level: 0, title: null}
    else .[0] as $heading
    | {text: $text, fenced: false, level: ($heading.hashes | length),
          title: ($heading.rest | rc_trim | capture("\\A(?<t>.*?)#*\\z").t | rc_trim)} end;
def rc_parse:
  reduce .[] as $text ({fence: null, records: []};
    .fence as $fence
    | if $fence != null then
        .records += [{text: $text, fenced: true, level: 0, title: null}]
        | if ($text | test("\\A {0,3}" + $fence.char + "{" + ($fence.len | tostring) + ",}[ \t]*\\z"))
          then .fence = null else . end
      else
        ($text | rc_fence_run) as $run
        | if $run != null then
            .fence = {char: $run[0:1], len: ($run | length)}
            | .records += [{text: $text, fenced: true, level: 0, title: null}]
          else .records += [$text | rc_line_record] end
      end)
  | .records;
def rc_section($level; $title):
  . as $records
  | [range(0; $records | length) | select($records[.].level == $level and $records[.].title == $title)]
  | if length == 0 then null
    else (.[0] + 1) as $start
    | ([range($start; $records | length) | select($records[.].level > 0 and $records[.].level <= $level)]
       | .[0] // ($records | length)) as $stop
    | $records[$start:$stop] end;
def rc_filled: . != null and any(.[]; .level == 0 and (.text | rc_blank | not));
def rc_reads_none: . != null and ([.[] | .text | select(rc_blank | not)] == ["None"]);
def rc_marker_slug:
  [.[0] // empty | capture("\\A<!-- hivemind-initiative: (?<slug>" + rc_slug + ") -->\\z") | .slug]
  | .[0];
def rc_codes_if($condition; $code): if $condition then [$code] else [] end;
def rc_path_slug: capture("\\Adocs/initiatives/(?<s>[^/]+)/").s;
def rc_front_matter:
  . as $lines
  | [range(1; $lines | length) | select($lines[.] == "---")] as $closers
  | select(($lines | length) > 0 and $lines[0] == "---" and ($closers | length) > 0)
  | $lines[1:$closers[0]] as $fm
  | ($fm | length) as $fm_len
  | select($fm_len >= 9)
  | $fm[1:$fm_len - 8] as $pairs
  | $fm[$fm_len - 8:] as $tail
  | select(($fm[0] == "stamps:" and ($pairs | length) > 0)
      or ($fm[0] == "stamps: []" and ($pairs | length) == 0))
  | select(($pairs | length) % 2 == 0)
  | [range(0; $pairs | length; 2) as $i
      | {path: ($pairs[$i] | capture("\\A  - path: (?<v>.*)\\z") | .v),
         blob: ($pairs[$i + 1] | capture("\\A    blob: (?<v>[0-9a-f]{40}|[0-9a-f]{64})\\z") | .v)}]
    as $stamps
  | select(($stamps | length) * 2 == ($pairs | length))
  | select(all($stamps[]; .path | rc_path_kind != null))
  | select(($stamps | map(.path) | unique | length) == ($stamps | length))
  | select($tail[1] == "open:")
  | {stamps: $stamps,
     verdict: ($tail[0] | capture("\\Averdict: (?<v>pass|fail)\\z") | .v),
     open: {critical: rc_count($tail[2]; "  critical"),
            high: rc_count($tail[3]; "  high"),
            medium: rc_count($tail[4]; "  medium"),
            low: rc_count($tail[5]; "  low")},
     rounds: rc_count($tail[6]; "rounds"),
     clean_round: ($tail[7] | capture("\\Aclean_round: (?<v>true|false)\\z") | .v == "true")};
'
}

# hivemind_readiness_commit_ok <commit>: 0 for 40 or 64 lowercase hex, else 1. No git call.
hivemind_readiness_commit_ok() {
  if [ "$#" -ne 1 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local commit="${1-}"
  if [[ "$commit" =~ ^[0123456789abcdef]{40}$ ]] || [[ "$commit" =~ ^[0123456789abcdef]{64}$ ]]; then
    return 0
  fi
  return 1
}

# hivemind_readiness_codes: prints the closed reason-code set, one base code per line.
hivemind_readiness_codes() {
  if [ "$#" -ne 0 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  printf '%s\n' \
    issue_closed 'rating_missing:' is_epic is_idea has_subissues no_acceptance_criteria \
    spec_problem_missing spec_evidence_missing spec_scope_missing open_questions_not_none \
    promote_type promote_effort \
    epic_closed parent_not_epic epic_marker_missing design_block_missing design_link_invalid \
    design_slug_mismatch prd_missing prd_ui_invalid design_missing design_delivered \
    prototype_missing record_missing 'template_section_missing:' template_order \
    heading_duplicate 'design_section_unfilled:' design_open_questions 'adr_missing:' \
    'adr_not_accepted:' record_malformed record_not_passed record_open record_rounds_exceeded \
    'record_stale:' 'record_unstamped:' 'heading_unmatched:' 'heading_ambiguous:' \
    'dependency_edge_missing:'
}

# hivemind_readiness_path_kind <path>: prints the allowlisted kind of <path> (0), else 1.
hivemind_readiness_path_kind() {
  if [ "$#" -ne 1 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local path="${1-}" kind="" program
  program="$(_hivemind_rc_jq_defs)"'
rc_path_kind // empty'
  if ! kind="$(printf '%s' "$path" | jq -Rsr "$program" 2>/dev/null)"; then
    return 1
  fi
  if [ -z "$kind" ]; then
    return 1
  fi
  printf '%s\n' "$kind"
}

# _hivemind_rc_path_shape_ok <path>: 0 when <path> is relative, holds no empty, `.` or `..`
# segment and no control character; else 1.
_hivemind_rc_path_shape_ok() {
  local path="$1"
  if [ -z "$path" ]; then
    return 1
  fi
  case "$path" in
    /* | */ | *//*) return 1 ;;
    . | .. | ./* | ../* | */. | */.. | */./* | */../*) return 1 ;;
    *[$'\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037\177']*) return 1 ;;
  esac
  return 0
}

# _hivemind_rc_ls_tree_verdict <path> <commit-length>: reads `git ls-tree -z` records then one
# trailer record holding git's exit status from stdin, and prints one verdict line:
# `ok <oid>`, `missing`, `unresolvable` or `failed`.
_hivemind_rc_ls_tree_verdict() {
  local want_path="$1" commit_len="$2" record="" previous="" have_previous=0 count=0
  local meta="" entry_path="" mode="" type="" oid="" found_oid="" mismatch=0
  while IFS= read -r -d '' record; do
    if [ "$have_previous" -eq 1 ]; then
      count=$((count + 1))
      meta="${previous%%$'\t'*}"
      entry_path="${previous#*$'\t'}"
      mode="${meta%% *}"
      type="${meta#* }"
      oid="${type#* }"
      type="${type%% *}"
      if [ "${#oid}" -ne "$commit_len" ]; then
        mismatch=1
      fi
      if [ "$entry_path" == "$want_path" ] && [ "$type" = blob ] \
        && { [ "$mode" = 100644 ] || [ "$mode" = 100755 ]; }; then
        found_oid="$oid"
      fi
    fi
    previous="$record"
    have_previous=1
  done
  if [ "$have_previous" -eq 0 ] || [ "$previous" != 0 ]; then
    printf 'failed\n'
  elif [ "$mismatch" -eq 1 ]; then
    printf 'unresolvable\n'
  elif [ "$count" -eq 1 ] && [ -n "$found_oid" ] && hivemind_readiness_commit_ok "$found_oid"; then
    printf 'ok %s\n' "$found_oid"
  else
    printf 'missing\n'
  fi
}

# hivemind_doc_entry <commit> <path>: the Document existence test (see PUBLIC API).
hivemind_doc_entry() {
  if [ "$#" -ne 2 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local commit="${1-}" path="${2-}" verdict="" git_rc=0
  if ! hivemind_readiness_commit_ok "$commit"; then
    _hivemind_rc_error commit-malformed
    return 2
  fi
  if ! _hivemind_rc_path_shape_ok "$path"; then
    return 1
  fi
  verdict="$(
    {
      git --no-replace-objects --literal-pathspecs ls-tree --full-tree -z "$commit" -- "$path" \
        2>/dev/null || git_rc=$?
      printf '%s\0' "$git_rc"
    } | _hivemind_rc_ls_tree_verdict "$path" "${#commit}"
  )" || verdict=failed
  case "$verdict" in
    'ok '*)
      printf '%s\n' "${verdict#ok }"
      return 0
      ;;
    missing)
      return 1
      ;;
    unresolvable)
      _hivemind_rc_error commit-unresolvable
      return 2
      ;;
  esac
  _hivemind_rc_error git-failed
  return 2
}

# hivemind_doc_read <commit> <path>: streams the document's bytes by its blob id (see PUBLIC API).
hivemind_doc_read() {
  if [ "$#" -ne 2 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local oid="" entry_rc=0
  oid="$(hivemind_doc_entry "$1" "$2")" || entry_rc=$?
  if [ "$entry_rc" -ne 0 ]; then
    return "$entry_rc"
  fi
  if git --no-replace-objects --literal-pathspecs cat-file blob "$oid" 2>/dev/null; then
    return 0
  fi
  _hivemind_rc_error git-failed
  return 2
}

# hivemind_seed_marker_slug: issue body on stdin; prints the seed marker slug (see PUBLIC API).
hivemind_seed_marker_slug() {
  if [ "$#" -ne 0 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local slug="" program
  program="$(_hivemind_rc_jq_defs)"'
[inputs] | map(rc_strip_cr) | rc_marker_slug // empty'
  if ! slug="$(jq -nRr "$program" 2>/dev/null)"; then
    return 1
  fi
  if [ -z "$slug" ]; then
    return 1
  fi
  printf '%s\n' "$slug"
}

# hivemind_record_front_matter: review record on stdin; prints its front matter as compact JSON
# (see PUBLIC API).
hivemind_record_front_matter() {
  if [ "$#" -ne 0 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local parsed="" program
  program="$(_hivemind_rc_jq_defs)"'
[inputs | rc_strip_cr] | rc_front_matter'
  if ! parsed="$(jq -nRc "$program" 2>/dev/null)"; then
    return 1
  fi
  if [ -z "$parsed" ]; then
    return 1
  fi
  printf '%s\n' "$parsed"
}

# _hivemind_rc_issue_jq_defs: prints the constant jq definitions that validate an issue snapshot
# and evaluate its issue layer; they need _hivemind_rc_jq_defs before them.
#
# Pagination completeness: rc_page_ok accepts an absent or null pageInfo or hasNextPage, so
# snapshot mode reads such a connection as complete. Completeness of a recorded snapshot is its
# caller's contract: the Lair records snapshots paged to the end. gh mode builds its own reply,
# whose query always asks for pageInfo, so it holds every connection to rc_page_strict and gives
# snapshot-malformed when one fails. Decided by the run (review call taken per
# decision-autonomy.md Review Calls) on the local review finding that asked to fail closed on
# missing pagination fields in both modes; a later finding asking the same for snapshot mode is
# a repeat of this record.
_hivemind_rc_issue_jq_defs() {
  printf '%s\n' '
def rc_number_ok: type == "number" and . == floor and . > 0;
def rc_page_ok:
  .pageInfo == null
  or ((.pageInfo | type) == "object"
      and (.pageInfo.hasNextPage == null or (.pageInfo.hasNextPage | type) == "boolean"));
def rc_page_strict:
  (.pageInfo | type) == "object" and (.pageInfo.hasNextPage | type) == "boolean";
def rc_snapshot_pages_strict:
  (.labels | rc_page_strict) and (.blockedBy | rc_page_strict) and (.subIssues | rc_page_strict)
  and (.parent == null or (.parent.labels | rc_page_strict));
def rc_labels_ok:
  type == "object" and (.nodes | type) == "array"
  and all(.nodes[]; type == "object" and (.name | type) == "string") and rc_page_ok;
def rc_parent_ok:
  . == null
  or (type == "object" and (.number | rc_number_ok) and (.state == "OPEN" or .state == "CLOSED")
      and has("body") and (.body == null or (.body | type) == "string") and (.labels | rc_labels_ok));
def rc_snapshot_ok:
  type == "object"
  and (.number | rc_number_ok)
  and (.state == "OPEN" or .state == "CLOSED")
  and has("body") and (.body == null or (.body | type) == "string")
  and (.labels | rc_labels_ok)
  and ((.blockedBy | type) == "object" and (.blockedBy.nodes | type) == "array"
       and all(.blockedBy.nodes[]; type == "object" and (.number | type) == "number" and .number == (.number | floor))
       and (.blockedBy | rc_page_ok))
  and ((.subIssues | type) == "object" and (.subIssues.totalCount | type) == "number"
       and .subIssues.totalCount == (.subIssues.totalCount | floor) and .subIssues.totalCount >= 0
       and (.subIssues | rc_page_ok))
  and has("parent") and (.parent | rc_parent_ok);
def rc_truncated: .pageInfo.hasNextPage == true;
def rc_snapshot_truncated:
  (.labels | rc_truncated) or (.blockedBy | rc_truncated) or (.subIssues | rc_truncated)
  or (.parent != null and (.parent.labels | rc_truncated));
def rc_has_checkbox:
  . != null and any(.[]; (.fenced | not) and (.text | test("\\A[ \t]*- \\[[ xX]\\]([ \t]|\\z)")));
def rc_common_codes($sn; $names; $doc):
  rc_codes_if($sn.state != "OPEN"; "issue_closed")
  + [("readiness", "type", "effort", "moscow", "priority", "risk", "difficulty") as $family
     | select(any($names[]; startswith($family + ":") and length > ($family | length) + 1) | not)
     | "rating_missing:" + $family]
  + rc_codes_if(any($names[]; . == "type:epic"); "is_epic")
  + rc_codes_if(any($names[]; . == "type:idea"); "is_idea")
  + rc_codes_if($sn.subIssues.totalCount > 0; "has_subissues")
  + rc_codes_if($doc | rc_section(2; "Acceptance Criteria") | rc_has_checkbox | not; "no_acceptance_criteria");
def rc_standalone_codes($names; $doc):
  rc_codes_if($doc | rc_section(2; "Problem") | rc_filled | not; "spec_problem_missing")
  + rc_codes_if($doc | rc_section(2; "Evidence") | rc_filled | not; "spec_evidence_missing")
  + rc_codes_if($doc | rc_section(2; "Scope boundary") | rc_filled | not; "spec_scope_missing")
  + rc_codes_if($doc | rc_section(2; "Open questions") | rc_reads_none | not; "open_questions_not_none")
  + rc_codes_if(any($names[]; startswith("type:") and length > 5
      and (.[5:] as $type | any("bug", "chore", "documentation", "refactor", "enhancement"; . == $type) | not));
      "promote_type")
  + rc_codes_if(any($names[]; . == "effort:l" or . == "effort:xl"); "promote_effort");
def rc_dependency_codes($sn; $doc):
  [($doc | rc_section(2; "Dependencies") // [])[] | select(.fenced | not) | .text
   | match("(?<![A-Za-z0-9_/&])#([1-9][0-9]*)(?![A-Za-z0-9_])"; "g") | .captures[0].string]
  | unique
  | [$sn.blockedBy.nodes[].number | tostring] as $edges
  | [.[] | select(. as $ref | any($edges[]; . == $ref) | not) | "dependency_edge_missing:" + .];
def rc_target_path($repo; $trunk):
  ("https://github.com/" | length) as $host_len
  | ($repo | length) as $repo_len
  | ("/blob/" + $trunk + "/") as $blob
  | if startswith("https://") then
      if startswith("https://github.com/")
         and (.[$host_len:$host_len + $repo_len] | ascii_downcase) == ($repo | ascii_downcase)
         and (.[$host_len + $repo_len:] | startswith($blob))
      then .[$host_len + $repo_len + ($blob | length):] else null end
    elif contains("://") then null
    else . end;
def rc_link_path($repo; $trunk; $kind):
  [capture("\\A\\[(?<text>[^\\]\\[]*)\\]\\((?<target>[^()[:space:]]*)\\)\\z")]
  | if length == 0 then null
    else .[0] as $link
    | ($link.target | rc_target_path($repo; $trunk)) as $path
    | if $path != null and $path == $link.text and ($path | rc_path_kind) == $kind then $path else null end
    end;
def rc_design_items:
  [.[] | select(.fenced | not) | .text
   | capture("\\A- (?<key>Solution design|Heading|ADR|Review record|Prototype):(?<rest>.*)\\z")
   | select(.rest == "" or (.rest | startswith(" ")))
   | {key: .key, value: (.rest | rc_trim)}];
def rc_design($slug; $repo; $trunk):
  . as $doc
  | ([$doc[] | select(.level == 2 and .title == "Design")] | length) as $blocks
  | ($doc | rc_section(2; "Design") // [] | rc_design_items) as $items
  | [$items[] | select(.key == "Solution design") | .value] as $design_values
  | [$items[] | select(.key == "Review record") | .value] as $record_values
  | [$items[] | select(.key == "Heading") | .value] as $headings
  | if $blocks != 1 or ($design_values | length) != 1 or ($record_values | length) != 1
       or ($headings | length) == 0 then
      {codes: ["design_block_missing"], documents: null}
    else
      ($design_values[0] | rc_link_path($repo; $trunk; "solution-design")) as $design_path
      | ($record_values[0] | rc_link_path($repo; $trunk; "review-record")) as $record_path
      | [$items[] | select(.key == "ADR") | .value | rc_link_path($repo; $trunk; "adr")] as $adr_paths
      | ($design_path == null or $record_path == null or any($adr_paths[]; . == null)) as $invalid
      | {codes: (rc_codes_if($invalid; "design_link_invalid")
                 + rc_codes_if($slug != null
                     and any($design_path, $record_path; . != null and rc_path_slug != $slug);
                     "design_slug_mismatch")),
         documents: (if $invalid then null
           else {slug: $slug, solution_design: $design_path, review_record: $record_path,
                 adrs: $adr_paths,
                 headings: [range(0; $headings | length) as $i | {index: ($i + 1), text: $headings[$i]}],
                 prototypes: [$items[] | select(.key == "Prototype") | .value
                              | rc_link_path($repo; $trunk; "prototype-index")]} end)}
    end;
def rc_issue_layer($repo; $trunk):
  . as $sn
  | [$sn.labels.nodes[].name] as $names
  | ($sn.body // "" | rc_lines | rc_parse) as $doc
  | rc_common_codes($sn; $names; $doc) as $common
  | if $sn.parent == null then
      {issue: $sn.number, track: "standalone", reasons: ($common + rc_standalone_codes($names; $doc)),
       documents: null}
    else
      ($sn.parent.body // "" | rc_lines | rc_marker_slug) as $slug
      | ($doc | rc_design($slug; $repo; $trunk)) as $design
      | {issue: $sn.number, track: "slice",
         reasons: ($common
           + rc_codes_if($sn.parent.state != "OPEN"; "epic_closed")
           + rc_codes_if(any($sn.parent.labels.nodes[]; .name == "type:epic") | not; "parent_not_epic")
           + rc_codes_if($slug == null; "epic_marker_missing")
           + rc_dependency_codes($sn; $doc)
           + $design.codes),
         documents: $design.documents}
    end;
'
}

# _hivemind_rc_owner_repo_ok <owner/repo>: 0 when the argument is a safe owner/repo pair, else 1.
_hivemind_rc_owner_repo_ok() {
  local value="$1" name_chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-'
  local pattern="^[${name_chars}]+/[${name_chars}]+\$"
  if ! [[ "$value" =~ $pattern ]]; then
    return 1
  fi
  case "$value" in
    -* | .* | */-* | */.* | *..*) return 1 ;;
  esac
  return 0
}

# _hivemind_rc_trunk_ok <trunk-name>: 0 when the argument is a safe trunk branch name, else 1.
_hivemind_rc_trunk_ok() {
  local value="$1"
  local pattern='^[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]+$'
  if ! [[ "$value" =~ $pattern ]]; then
    return 1
  fi
  case "$value" in
    -* | *..*) return 1 ;;
  esac
  return 0
}

# _hivemind_rc_doc_jq_defs: prints the constant jq definitions that plan and evaluate the slice
# document layer; they need _hivemind_rc_jq_defs before them. rc_doc_eval reads one framed
# document: a prefix line, the document's bytes, then one last line holding the read status, so
# a document of any size reaches jq on stdin only.
_hivemind_rc_doc_jq_defs() {
  printf '%s\n' '
def rc_template_sections:
  [["context-and-code-truth", "Context and code truth"], ["components", "Components"],
   ["state-and-ownership", "State and ownership"], ["contracts-and-seams", "Contracts and seams"],
   ["trust-boundaries", "Trust boundaries"], ["lifecycle", "Lifecycle"],
   ["existing-path-coverage", "Existing-path coverage"], ["failure-modes", "Failure modes"],
   ["decisions", "Decisions"], ["verification-strategy", "Verification strategy"],
   ["seam-order", "Seam order"], ["open-questions", "Open questions"], ["amendments", "Amendments"]];
def rc_document_plan:
  .documents as $docs
  | if $docs == null or $docs.slug == null then empty
    else $docs.slug as $slug
    | ($docs.prototypes | length) as $count
    | "slug\t" + $slug,
      (if ($docs.solution_design | rc_path_slug) == $slug then "design\t" + $docs.solution_design
       else empty end),
      (if ($docs.review_record | rc_path_slug) == $slug then "record\t" + $docs.review_record
       else empty end),
      ($docs.adrs | unique | .[] | "adr\t" + .),
      (if $count > 0 then "ui-no\tdesign_block_missing" else empty end),
      (if $count == 0 then "ui-yes\tprototype_missing"
       elif $count > 1 then "ui-yes\tdesign_block_missing"
       elif $docs.prototypes[0] == null then "ui-yes\tdesign_link_invalid"
       elif ($docs.prototypes[0] | rc_path_slug) != $slug then "ui-yes\tdesign_slug_mismatch"
       else empty end)
    end;
def rc_doc_eval(f):
  split("\n") as $all
  | if $all[-1] == "0" then {prefix: $all[0], texts: ($all[1:-1] | map(rc_strip_cr))} | f
    elif $all[-1] == "1" then "missing"
    else "failed" end;
def rc_after_title:
  . as $records
  | ([range(0; $records | length) | select($records[.].level == 1)] | .[0]) as $title
  | if $title == null then null
    else [$records[$title + 1:][] | .text | select(rc_blank | not)] | .[0] end;
def rc_prd_ui:
  .texts | rc_parse | rc_after_title
  | if . == "**UI:** yes" then "yes"
    elif . == "**UI:** no" then "no"
    elif . != null and startswith("**UI:**") then "invalid"
    else "no" end;
def rc_adr_status:
  [.texts | rc_parse | .[] | select((.fenced | not) and (.text | startswith("**Status:**"))) | .text]
  | if length > 0 and (.[0] | test("\\A\\*\\*Status:\\*\\* *accepted")) then "accepted"
    else "not-accepted" end;
def rc_heading_codes($doc; $headings):
  [$headings[] | .index as $index | .text as $text
   | [$doc[] | select(.level > 0 and .title == $text)] as $matches
   | if $text == "" or ($matches | length) == 0 then "heading_unmatched:\($index)"
     elif ($matches | length) > 1 then "heading_ambiguous:\($index)"
     elif ($doc | rc_section($matches[0].level; $text) | rc_filled) then empty
     else "design_section_unfilled:\($index)" end];
def rc_design_codes:
  (.prefix | fromjson | .documents.headings) as $headings
  | (.texts | rc_parse) as $doc
  | [$doc[] | select(.level > 0) | .title] as $titles
  | [$doc[] | select(.level == 2) | .title] as $sections
  | [rc_template_sections[] | .[1] as $title
     | {name: .[0], at: ([range(0; $sections | length) | select($sections[.] == $title)] | .[0])}]
    as $template
  | [$template[] | .at | select(. != null)] as $order
  | ($doc | rc_section(2; "Open questions")) as $open
  | (rc_codes_if(($doc | rc_after_title) == "**Status:** delivered"; "design_delivered")
     + [$template[] | select(.at == null) | "template_section_missing:" + .name]
     + rc_codes_if($order != ($order | sort); "template_order")
     + rc_codes_if(($titles | length) != ($titles | unique | length); "heading_duplicate")
     + rc_codes_if($open != null and ($open | rc_reads_none | not); "design_open_questions")
     + rc_heading_codes($doc; $headings))[];
def rc_record_codes:
  [.texts | rc_front_matter] as $parsed
  | if ($parsed | length) == 0 then "malformed"
    else $parsed[0]
    | (rc_codes_if(.verdict != "pass" or .clean_round != true or .rounds < 2; "record_not_passed")
       + rc_codes_if(.rounds > 3; "record_rounds_exceeded")
       + rc_codes_if(any(.open[]; . > 0); "record_open"))[],
      (.stamps[] | "stamp\t" + .path + "\t" + .blob)
    end;
'
}

# hivemind_readiness_jq_defs: prints the shared jq definitions, then the document layer's (see
# PUBLIC API).
hivemind_readiness_jq_defs() {
  if [ "$#" -ne 0 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  _hivemind_rc_jq_defs
  _hivemind_rc_doc_jq_defs
}

# _hivemind_rc_doc_eval <commit> <path> <prefix> <filter>: streams the line <prefix>, the bytes of
# the document at <path> and its hivemind_doc_read status into one jq program running <filter>,
# and prints its raw output: `missing` for a missing document, else the filter's lines. Returns 2
# on a failure, whose token hivemind_doc_read or this function has printed.
_hivemind_rc_doc_eval() {
  local commit="$1" path="$2" prefix="$3" read_rc=0 output="" program
  program="$(_hivemind_rc_jq_defs)$(_hivemind_rc_doc_jq_defs)$4"
  if ! output="$(
    {
      printf '%s\n' "$prefix"
      hivemind_doc_read "$commit" "$path" || read_rc=$?
      printf '\n%s' "$read_rc"
    } | jq -Rsr "$program" 2>/dev/null
  )"; then
    _hivemind_rc_error git-failed
    return 2
  fi
  if [ "$output" = failed ]; then
    return 2
  fi
  printf '%s\n' "$output"
}

# _hivemind_rc_record_codes <commit> <record-path> <required-path>...: prints the review record's
# reason codes, one per line: its pass-rule codes, a stale code per stamp whose path fails the
# Document existence test or holds another blob, and an unstamped code per required path.
_hivemind_rc_record_codes() {
  local commit="$1" record_path="$2" output="" line="" stamp="" path="" blob="" oid="" entry_rc=0
  local stamped=" "
  local -a lines=()
  shift 2
  output="$(_hivemind_rc_doc_eval "$commit" "$record_path" "" 'rc_doc_eval(rc_record_codes)')" || return 2
  case "$output" in
    missing | malformed)
      printf 'record_%s\n' "$output"
      return 0
      ;;
  esac
  mapfile -t lines < <(printf '%s\n' "$output")
  for line in "${lines[@]}"; do
    case "$line" in
      '') ;;
      stamp$'\t'*)
        stamp="${line#stamp$'\t'}"
        path="${stamp%%$'\t'*}"
        blob="${stamp#*$'\t'}"
        stamped+="$path "
        entry_rc=0
        oid="$(hivemind_doc_entry "$commit" "$path")" || entry_rc=$?
        if [ "$entry_rc" -eq 2 ]; then
          return 2
        fi
        if [ "$entry_rc" -ne 0 ] || [ "$oid" != "$blob" ]; then
          printf 'record_stale:%s\n' "$path"
        fi
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
  for path in "$@"; do
    case "$stamped" in
      *" $path "*) ;;
      *) printf 'record_unstamped:%s\n' "$path" ;;
    esac
  done
}

# _hivemind_rc_prototype_codes <commit> <slug>: prints `prototype_missing` when either UI prototype
# file of <slug> fails the Document existence test; returns 2 on a failure.
_hivemind_rc_prototype_codes() {
  local commit="$1" slug="$2" path="" entry_rc=0
  for path in "docs/initiatives/$slug/prototype/index.html" "docs/initiatives/$slug/prototype/notes.md"; do
    entry_rc=0
    hivemind_doc_entry "$commit" "$path" >/dev/null || entry_rc=$?
    if [ "$entry_rc" -eq 2 ]; then
      return 2
    fi
    if [ "$entry_rc" -eq 1 ]; then
      printf 'prototype_missing\n'
    fi
  done
}

# _hivemind_rc_slice_document_codes <commit> <layer>: prints one JSON array of the slice document
# layer's reason codes for one issue layer line. The layer's `documents` field is null unless the
# issue is a slice whose Design block counts and Solution design, Review record and ADR links
# passed; it then holds {slug (null when the epic marker is missing), solution_design,
# review_record, adrs, headings: [{index, text}], prototypes: [path or null]}. No document is read
# without a slug, and a link is read only when it passed its shape and slug checks. A non-zero
# return is a failure that has already printed its token; the caller propagates it.
_hivemind_rc_slice_document_codes() {
  local commit="$1" layer="$2" plan="" line="" slug="" design="" record="" ui="" ui_yes="" ui_no=""
  local prd="" path="" output="" codes="" program
  local -a plan_lines=() adrs=() required=()
  program="$(_hivemind_rc_jq_defs)$(_hivemind_rc_doc_jq_defs)"'
rc_document_plan'
  if ! plan="$(printf '%s\n' "$layer" | jq -r "$program" 2>/dev/null)"; then
    _hivemind_rc_error snapshot-malformed
    return 2
  fi
  mapfile -t plan_lines < <(printf '%s\n' "$plan")
  for line in "${plan_lines[@]}"; do
    case "$line" in
      slug$'\t'*) slug="${line#*$'\t'}" ;;
      design$'\t'*) design="${line#*$'\t'}" ;;
      record$'\t'*) record="${line#*$'\t'}" ;;
      adr$'\t'*) adrs+=("${line#*$'\t'}") ;;
      ui-yes$'\t'*) ui_yes+="${line#*$'\t'}"$'\n' ;;
      ui-no$'\t'*) ui_no+="${line#*$'\t'}"$'\n' ;;
    esac
  done
  if [ -z "$slug" ]; then
    printf '[]\n'
    return 0
  fi
  prd="docs/prds/$slug.md"
  required=("$prd" "docs/initiatives/$slug/solution-design.md")
  ui="$(_hivemind_rc_doc_eval "$commit" "$prd" "" 'rc_doc_eval(rc_prd_ui)')" || return 2
  case "$ui" in
    missing) codes+=$'prd_missing\n' ;;
    invalid) codes+=$'prd_ui_invalid\n' ;;
    no) codes+="$ui_no" ;;
    yes)
      required+=("docs/initiatives/$slug/prototype/index.html" "docs/initiatives/$slug/prototype/notes.md")
      output="$(_hivemind_rc_prototype_codes "$commit" "$slug")" || return 2
      codes+="$ui_yes$output"$'\n'
      ;;
  esac
  if [ -n "$design" ]; then
    output="$(_hivemind_rc_doc_eval "$commit" "$design" "$layer" 'rc_doc_eval(rc_design_codes)')" || return 2
    if [ "$output" = missing ]; then
      output=design_missing
    fi
    codes+="$output"$'\n'
  fi
  # Document counts: ADR entries here and review record stamps in _hivemind_rc_record_codes have
  # no count limit; each costs a few git calls. Accepted risk: an issue body holds at most 65536
  # characters, a maintainer approves it, and a review record is a committed file. Decided by the
  # run (review call taken per decision-autonomy.md Review Calls) on the local review finding that
  # asked for count limits or batched git reads; a later finding asking the same is a repeat of
  # this record.
  for path in "${adrs[@]}"; do
    output="$(_hivemind_rc_doc_eval "$commit" "$path" "" 'rc_doc_eval(rc_adr_status)')" || return 2
    case "$output" in
      missing) codes+="adr_missing:$path"$'\n' ;;
      not-accepted) codes+="adr_not_accepted:$path"$'\n' ;;
    esac
  done
  if [ -n "$record" ]; then
    output="$(_hivemind_rc_record_codes "$commit" "$record" "${required[@]}")" || return 2
    codes+="$output"$'\n'
  fi
  if ! printf '%s' "$codes" | jq -nRc '[inputs | select(length > 0)] | unique' 2>/dev/null; then
    _hivemind_rc_error snapshot-malformed
    return 2
  fi
}

# _hivemind_rc_finish_layers <commit> <layers>: joins each issue layer line with its document
# layer codes and prints the output contract lines; returns 2 on a failure.
_hivemind_rc_finish_layers() {
  local commit="$1" rest="$2" layer="" codes="" pairs="" program
  while [ -n "$rest" ]; do
    layer="${rest%%$'\n'*}"
    if [ "$layer" = "$rest" ]; then
      rest=""
    else
      rest="${rest#*$'\n'}"
    fi
    if ! codes="$(_hivemind_rc_slice_document_codes "$commit" "$layer")"; then
      return 2
    fi
    pairs+="$layer"$'\n'"$codes"$'\n'
  done
  if [ -z "$pairs" ]; then
    return 0
  fi
  program='
[inputs] as $all
| range(0; $all | length; 2) as $i
| $all[$i] as $layer
| ($layer.reasons + $all[$i + 1] | unique) as $reasons
| {issue: $layer.issue, commit: $commit, track: $layer.track,
   result: (if ($reasons | length) == 0 then "pass" else "fail" end), reasons: $reasons}'
  if ! printf '%s' "$pairs" | jq -nc --arg commit "$commit" "$program" 2>/dev/null; then
    _hivemind_rc_error snapshot-malformed
    return 2
  fi
}

# _hivemind_rc_number_ok <number>: 0 when the argument is an issue number `^[1-9][0-9]*$`, else 1.
_hivemind_rc_number_ok() {
  [[ "$1" =~ ^[123456789][0123456789]*$ ]]
}

# _hivemind_rc_target_ok <commit> <owner/repo> <trunk-name>: checks the arguments both modes share,
# with no git call; prints commit-malformed or usage and returns 2 on the first bad one.
_hivemind_rc_target_ok() {
  if ! hivemind_readiness_commit_ok "$1"; then
    _hivemind_rc_error commit-malformed
    return 2
  fi
  if ! _hivemind_rc_owner_repo_ok "$2" || ! _hivemind_rc_trunk_ok "$3"; then
    _hivemind_rc_error usage
    return 2
  fi
}

# _hivemind_rc_commit_resolves <commit>: 0 when <commit> names a commit object in the repository,
# else prints commit-unresolvable and returns 2.
_hivemind_rc_commit_resolves() {
  local object_type=""
  object_type="$(git --no-replace-objects --literal-pathspecs cat-file -t "$1" </dev/null 2>/dev/null)" \
    || object_type=""
  if [ "$object_type" != commit ]; then
    _hivemind_rc_error commit-unresolvable
    return 2
  fi
}

# _hivemind_rc_evaluate <commit> <owner/repo> <trunk-name>: the one evaluator of snapshot mode and
# gh mode. Reads one JSON array of issue snapshots on stdin, validates every element, and prints
# the output contract lines only when it returns 0; returns 2 on a failure whose token it printed.
_hivemind_rc_evaluate() {
  local commit="$1" owner_repo="$2" trunk="$3" layers="" output="" program
  program="$(_hivemind_rc_jq_defs)$(_hivemind_rc_issue_jq_defs)"'
[inputs] as $input
| if ($input | length) != 1 or ($input[0] | type) != "array" then "snapshot-malformed"
  elif any($input[0][]; rc_snapshot_ok | not) then "snapshot-malformed"
  elif any($input[0][]; rc_snapshot_truncated) then "truncated"
  else $input[0][] | rc_issue_layer($owner_repo; $trunk) end'
  if ! layers="$(jq -nc --arg owner_repo "$owner_repo" --arg trunk "$trunk" "$program" 2>/dev/null)"; then
    _hivemind_rc_error snapshot-malformed
    return 2
  fi
  case "$layers" in
    '"snapshot-malformed"' | '"truncated"')
      _hivemind_rc_error "${layers//\"/}"
      return 2
      ;;
  esac
  if ! output="$(_hivemind_rc_finish_layers "$commit" "$layers")"; then
    return 2
  fi
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
  fi
}

# hivemind_readiness_check_snapshot <commit> <owner/repo> <trunk-name>: snapshot mode; the issue
# snapshot array is on stdin (see PUBLIC API).
hivemind_readiness_check_snapshot() {
  if [ "$#" -ne 3 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local commit="${1-}" owner_repo="${2-}" trunk="${3-}"
  _hivemind_rc_target_ok "$commit" "$owner_repo" "$trunk" || return 2
  _hivemind_rc_commit_resolves "$commit" || return 2
  _hivemind_rc_evaluate "$commit" "$owner_repo" "$trunk"
}

# hivemind_readiness_fetch_snapshot <owner/repo> <number>: reads one issue snapshot through one gh
# GraphQL call and prints its issue node (see PUBLIC API). gh's output and exit status reach jq
# on stdin as one framed stream: the body, a newline, then the status. jq stops at a non-JSON body,
# so the writer's stderr is discarded: a broken-pipe write error never reaches the caller.
hivemind_readiness_fetch_snapshot() {
  if [ "$#" -ne 2 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local owner_repo="${1-}" number="${2-}" node="" gh_rc=0 query program
  if ! _hivemind_rc_owner_repo_ok "$owner_repo" || ! _hivemind_rc_number_ok "$number"; then
    _hivemind_rc_error usage
    return 2
  fi
  if ! command -v gh >/dev/null 2>&1; then
    _hivemind_rc_error gh-failed
    return 2
  fi
  query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){number state body labels(first:100){pageInfo{hasNextPage} nodes{name}} blockedBy(first:100){pageInfo{hasNextPage} nodes{number state}} subIssues(first:100){totalCount pageInfo{hasNextPage}} parent{number state body labels(first:100){pageInfo{hasNextPage} nodes{name}}}}}}'
  program="$(_hivemind_rc_jq_defs)$(_hivemind_rc_issue_jq_defs)"'
[inputs] as $all
| if ($all | length) != 2 or $all[1] != 0 or ($all[0] | type) != "object" then "gh-failed"
  elif ($all[0].errors | . != null and . != []) then "gh-failed"
  else ($all[0] | try .data.repository.issue catch null) as $sn
  | if ($sn | type) != "object" then "gh-failed"
    elif ($sn | rc_snapshot_ok | not) or ($sn | rc_snapshot_pages_strict | not)
      or ($sn.number | tostring) != $number then "snapshot-malformed"
    elif ($sn | rc_snapshot_truncated) then "truncated"
    else $sn end
  end'
  if ! node="$(
    {
      gh api graphql -f query="$query" -f owner="${owner_repo%%/*}" -f name="${owner_repo#*/}" \
        -F number="$number" </dev/null 2>/dev/null || gh_rc=$?
      printf '\n%s' "$gh_rc"
    } 2>/dev/null | jq -nc --arg number "$number" "$program" 2>/dev/null
  )"; then
    _hivemind_rc_error gh-failed
    return 2
  fi
  case "$node" in
    '"gh-failed"' | '"snapshot-malformed"' | '"truncated"')
      _hivemind_rc_error "${node//\"/}"
      return 2
      ;;
  esac
  printf '%s\n' "$node"
}

# hivemind_readiness_check_gh <commit> <owner/repo> <trunk-name> <number>...: gh mode; reads each
# issue through gh and evaluates the snapshots with snapshot mode's evaluator (see PUBLIC API).
hivemind_readiness_check_gh() {
  if [ "$#" -lt 4 ]; then
    _hivemind_rc_error usage
    return 2
  fi
  local commit="${1-}" owner_repo="${2-}" trunk="${3-}" number="" node="" nodes=""
  shift 3
  _hivemind_rc_target_ok "$commit" "$owner_repo" "$trunk" || return 2
  for number in "$@"; do
    if ! _hivemind_rc_number_ok "$number"; then
      _hivemind_rc_error usage
      return 2
    fi
  done
  _hivemind_rc_commit_resolves "$commit" || return 2
  for number in "$@"; do
    node="$(hivemind_readiness_fetch_snapshot "$owner_repo" "$number")" || return 2
    nodes+="${nodes:+,}$node"
  done
  printf '[%s]\n' "$nodes" | _hivemind_rc_evaluate "$commit" "$owner_repo" "$trunk"
}
