# shellcheck shell=bash
#
# stage-derivation.sh — shared initiative stage derivation library (ADR-0046, solution design
# "Stage derivation and handoff check"): a pure function from GitHub evidence and git to an
# initiative's stage and next action. No progress state is stored (D2). Its caller is the guide's
# script, which reads the evidence and passes it on stdin.
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources the readiness check library
# and the record verify library first, then this file, all by absolute path derived from its OWN
# script_dir (`. "$plugin_root/skills/_shared/stage-derivation.sh"`). It defines functions only;
# it runs no top-level statements, sources no other file and changes no caller state beyond
# defining the functions below. Sourcing it twice is harmless. `bash -n` validates it as a
# sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately
# OMITS the P18 shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced
# file mutates the SOURCING shell's option state, so installing those here would corrupt
# every caller's shell; the floor is therefore the documented exception, not the full
# `set -euo pipefail`. This file carries no top-level `set` at all (pure function
# definitions); each caller owns its own `set -u` and error routing. Allowlisted under
# CHECK13 as a P18 documented exception.
#
# SINGLE RESPONSIBILITY: derive the stage, never judge a document's quality. It writes nothing:
# no file, no scratch path. It makes no `gh` call: every GitHub fact arrives as evidence on
# stdin. Every document (the PRD, both UI prototype files, the solution design and the review
# record) is read only through the readiness check library's Document existence test
# (hivemind_doc_entry, hivemind_doc_read) at the trunk commit or at the evidence's docs head,
# so a symlink, a submodule, a tree or a path under a symlinked directory is missing evidence.
# Text reaches jq only on stdin and is parsed by the readiness check's jq definitions
# (hivemind_readiness_jq_defs); only arguments already checked against their fixed patterns are
# passed with `jq --arg`. Every git call is `git --no-replace-objects --literal-pathspecs ...`,
# resolves no ref and makes no network call. The commit argument and the slug are checked before
# any git call. The functions behave the same under a caller's `set -euo pipefail` or `set -u`
# alone.
#
# FAILURE CONTRACT: status 2 leaves stdout empty and prints exactly one stderr line
# `stage-derivation-error: <token>`. Tokens: usage, missing-library (a readiness check or record
# verify function is not defined), commit-malformed, commit-unresolvable, evidence-malformed,
# truncated, gh-failed, git-failed. gh-failed is reserved for the evidence read; derive itself
# never gives it. The library never exits and never prints evidence or document text.
#
# PUBLIC API:
#   hivemind_stage_derive <trunk-commit> <owner/repo> <trunk-name> <slug>  (evidence on stdin)
#       <trunk-commit> is the fetched remote trunk commit id, 40 or 64 lowercase hex, never a
#       branch name or a local ref (commit-malformed, no git call). <owner/repo>, <trunk-name>
#       and <slug> (`^[a-z0-9]+(-[a-z0-9]+)*$`) are checked with no git call (usage). Stdin is
#       exactly one JSON value, the evidence, checked in full before any git call. Prints one
#       compact JSON object and returns 0:
#       {"slug", "trunk": <trunk-commit>, "seed": <issue number or null>,
#        "docs": {"commit", "pull_request", "draft", "source": "pull_request"|"branch"|null},
#        "stage": <stage or null>, "status", "next", "reasons": [<reason>...],
#        "ignored": [{"kind": "issue"|"pull_request", "number", "reason"}...],
#        "slices": [{"number", "state"}...]}
#       A null stage comes with status `ambiguous` or `out-of-order` and next `ask`.
#
# EVIDENCE JSON v1 (normalized by the caller's GitHub read; every key below is required, other
# keys are ignored; a timestamp is `YYYY-MM-DDTHH:MM:SSZ`; an object id is 40 or 64 lowercase
# hex; numbers are unique within each list, branch names within branches):
#   {"version": 1,
#    "seeds": [{"number", "state": "OPEN"|"CLOSED", "author_can_write": <bool>,
#               "body": <string or null>}...],
#        every issue the seed marker search returned for <slug>;
#    "pull_requests": [{"number", "head_ref", "head_oid", "head_repository": <owner/repo or null>,
#                       "author_can_write": <bool>, "draft": <bool>}...],
#        every open pull request whose head ref starts with `docs/`;
#    "branches": [{"name", "oid", "pull_request_count": <n>}...],
#        every branch of <owner/repo> whose name starts with `docs/`, with the count of pull
#        requests, open or closed, that used it as their head;
#    "epic": null | {"number", "state", "sub_issue_total": <n>},
#        the seed issue as epic with its sub-issue count; null when no seed was read;
#    "slices": [{"readiness": <readiness check issue snapshot>, "last_edited_at": <timestamp or
#                null>, "ready_events": [{"actor_can_write": <bool>, "created_at"}...],
#                "renamed_at": [<timestamp>...]}...]}
#        every sub-issue of the epic; the snapshot is the readiness check's snapshot mode input.
#   Fewer slices than `sub_issue_total`, or any snapshot `pageInfo.hasNextPage` true, is
#   truncated. Slices with a null epic, more slices than `sub_issue_total`, or an epic that is
#   not the one seed, are evidence-malformed.
#
# RESOLUTION: the seed is the one open issue whose body's first line, one ending CR removed, is
# `<!-- hivemind-initiative: <slug> -->` and whose author has write permission. A marker-shaped
# first line with a malformed slug is ignored as `seed_marker_malformed`, with no git call; a
# closed one as `seed_closed`; a non-writer's as `seed_author_not_writer`; an issue whose first
# line is no marker or another slug's marker is not this initiative's and is not named. A pull
# request counts when its head ref matches `^docs/<slug>(-[a-z0-9]+(-[a-z0-9]+)*)?$`, its head
# repository is <owner/repo> and its author has write permission; a matching fork is ignored as
# `docs_pr_fork`, a non-writer's as `docs_pr_author_not_writer`. The docs head is the one
# counting pull request's head, else, with none, the one branch of that name no pull request
# has used. Trunk is current when the PRD and the solution design pass the existence test at
# trunk, the review record meets the pass rule there and `hivemind_record_verify <trunk>
# <trunk>` names no failure of this slug's record.
#
# PRECEDENCE, first match wins (stage / status / next [reasons]):
#   1. Design delivered at trunk: close-out / done / none.
#   2. Two or more seeds: null / ambiguous / ask [seed_ambiguous]. No seed but a counting pull
#      request, a counting branch or a PRD at trunk: null / ambiguous / ask [seed_missing]. No
#      seed and nothing else: none / not-started / capture.
#   3. Two or more counting pull requests: null / ambiguous / ask [docs_pr_ambiguous]. None, and
#      two or more counting branches: null / ambiguous / ask [docs_branch_ambiguous].
#   4. Design delivered at the docs head: close-out / in-progress / merge-docs.
#   5. Trunk current: no sub-issue: docs-pull-request / done / slice; every sub-issue closed:
#      handoff / done / close-out; some closed: handoff / delivering / deliver; an open slice
#      the readiness check gives a `rating_missing:` code: slicing / done / triage; else
#      triage / done / handoff-check.
#   6. Otherwise read at D, the docs head, else trunk:
#      no PRD: interrogation / in-progress / interrogate at a docs head, capture / done /
#      interrogate at trunk; a `**UI:**` value other than yes or no: null / ambiguous / ask
#      [prd_ui_invalid] (no line reads as no); UI yes and the prototype not done (both files
#      present and notes.md holding a filled `## Verdict` section) while a solution design
#      exists at D or trunk: null / out-of-order / ask [design_before_prototype]; both prototype
#      files missing: prd / done / build-prototype; one missing: ui-prototype / incomplete /
#      build-prototype; no filled Verdict: ui-prototype / waiting-approval / approve-prototype;
#      no solution design: ui-prototype (UI yes) or prd / done / design; no review record:
#      solution-design / done / review; a malformed record: null / ambiguous / ask
#      [record_malformed]; a record failing the pass rule: design-review / in-progress / review;
#      verify, `hivemind_record_verify <D> <merge-base of D and trunk>` (at trunk, <trunk>
#      <trunk>), naming this record: design-review / stale / re-review; naming other records:
#      docs-pull-request / verify-failed / ask [verify_failed:<record path>...]; no pull
#      request: docs-pull-request / no-pull-request / ask; a draft: docs-pull-request /
#      in-progress / mark-ready; else docs-pull-request / in-progress / merge-docs.

# _hivemind_sd_error <token>: prints the one failure line to stderr.
_hivemind_sd_error() {
  printf 'stage-derivation-error: %s\n' "$1" >&2
}

# _hivemind_sd_jq_defs: prints the constant jq definitions of the document reads; they need
# hivemind_readiness_jq_defs before them. Each filter runs under rc_doc_eval.
_hivemind_sd_jq_defs() {
  printf '%s\n' '
def sd_delivered:
  if (.texts | rc_parse | rc_after_title) == "**Status:** delivered" then "delivered" else "open" end;
def sd_verdict:
  if (.texts | rc_parse | rc_section(2; "Verdict") | rc_filled) then "filled" else "unfilled" end;
def sd_record:
  [.texts | rc_front_matter]
  | if length == 0 then "malformed"
    elif (.[0] | .verdict == "pass" and all(.open[]; . == 0) and .clean_round == true
          and .rounds >= 2 and .rounds <= 3) then "pass"
    else "fail" end;
'
}

# _hivemind_sd_evidence_jq_defs: prints the constant jq definitions that validate the evidence
# and resolve the seed and the docs head; they need hivemind_readiness_jq_defs before them.
_hivemind_sd_evidence_jq_defs() {
  printf '%s\n' '
def sd_hex: type == "string" and test("\\A([0-9a-f]{40}|[0-9a-f]{64})\\z");
def sd_count: type == "number" and . == floor and . >= 0;
def sd_number: sd_count and . > 0;
def sd_bool: type == "boolean";
def sd_text: type == "string";
def sd_time: sd_text and test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z");
def sd_state: . == "OPEN" or . == "CLOSED";
def sd_list(f): type == "array" and all(.[]; f);
def sd_unique(f): [.[] | f] | length == (unique | length);
def sd_seed_ok:
  type == "object" and (.number | sd_number) and (.state | sd_state)
  and (.author_can_write | sd_bool) and has("body") and (.body == null or (.body | sd_text));
def sd_pull_request_ok:
  type == "object" and (.number | sd_number) and (.head_ref | sd_text) and (.head_oid | sd_hex)
  and has("head_repository") and (.head_repository == null or (.head_repository | sd_text))
  and (.author_can_write | sd_bool) and (.draft | sd_bool);
def sd_branch_ok:
  type == "object" and (.name | sd_text) and (.oid | sd_hex) and (.pull_request_count | sd_count);
def sd_epic_ok:
  . == null
  or (type == "object" and (.number | sd_number) and (.state | sd_state)
      and (.sub_issue_total | sd_count));
def sd_event_ok: type == "object" and (.actor_can_write | sd_bool) and (.created_at | sd_time);
def sd_slice_ok:
  type == "object" and (.readiness | type) == "object" and (.readiness.number | sd_number)
  and (.readiness.state | sd_state)
  and has("last_edited_at") and (.last_edited_at == null or (.last_edited_at | sd_time))
  and (.ready_events | sd_list(sd_event_ok)) and (.renamed_at | sd_list(sd_time));
def sd_evidence_ok:
  type == "object" and .version == 1
  and (.seeds | sd_list(sd_seed_ok)) and (.seeds | sd_unique(.number))
  and (.pull_requests | sd_list(sd_pull_request_ok)) and (.pull_requests | sd_unique(.number))
  and (.branches | sd_list(sd_branch_ok)) and (.branches | sd_unique(.name))
  and has("epic") and (.epic | sd_epic_ok)
  and (.slices | sd_list(sd_slice_ok)) and (.slices | sd_unique(.readiness.number))
  and (if .epic == null then (.slices | length) == 0
       else (.slices | length) <= .epic.sub_issue_total end);
def sd_truncated:
  (.epic != null and (.slices | length) < .epic.sub_issue_total)
  or any(.slices[];
      [.readiness | .. | objects | select(has("pageInfo")) | .pageInfo]
      | any(.[]; type == "object" and .hasNextPage == true));
def sd_seed_status($slug):
  ((.body // "") | rc_lines | .[0] // "") as $first
  | [$first | capture("\\A<!-- hivemind-initiative: (?<s>.*) -->\\z") | .s] as $found
  | if ($found | length) == 0 then "unrelated"
    elif ($found[0] | test("\\A" + rc_slug + "\\z") | not) then "seed_marker_malformed"
    elif $found[0] != $slug then "unrelated"
    elif .state != "OPEN" then "seed_closed"
    elif (.author_can_write | not) then "seed_author_not_writer"
    else "seed" end;
def sd_pull_request_status($repo):
  if ((.head_repository // "") | ascii_downcase) != ($repo | ascii_downcase) then "docs_pr_fork"
  elif (.author_can_write | not) then "docs_pr_author_not_writer"
  else "counts" end;
def sd_docs($prs; $branches):
  if ($prs | length) == 1 then
    {commit: $prs[0].head_oid, pull_request: $prs[0].number, draft: $prs[0].draft,
     source: "pull_request"}
  elif ($prs | length) == 0 and ($branches | length) == 1 then
    {commit: $branches[0].oid, pull_request: null, draft: null, source: "branch"}
  else {commit: null, pull_request: null, draft: null, source: null} end;
def sd_plan($repo; $slug):
  . as $ev
  | ("\\Adocs/" + $slug + "(-" + rc_slug + ")?\\z") as $docs_name
  | [$ev.seeds[] | {number, status: sd_seed_status($slug)}] as $seeds
  | [$seeds[] | select(.status == "seed") | .number] as $seed_numbers
  | [$ev.pull_requests[] | select(.head_ref | test($docs_name))
     | . + {status: sd_pull_request_status($repo)}] as $named
  | [$named[] | select(.status == "counts")] as $prs
  | [$ev.branches[] | select((.name | test($docs_name)) and .pull_request_count == 0)] as $branches
  | if ($seed_numbers | length) == 1 and $ev.epic != null and $ev.epic.number != $seed_numbers[0]
    then "evidence-malformed"
    else
      {seed: (if ($seed_numbers | length) == 1 then $seed_numbers[0] else null end),
       seed_count: ($seed_numbers | length), pr_count: ($prs | length),
       branch_count: ($branches | length), docs: sd_docs($prs; $branches),
       ignored: ([$seeds[] | select(.status != "seed" and .status != "unrelated")
                  | {kind: "issue", number, reason: .status}]
                 + [$named[] | select(.status != "counts")
                    | {kind: "pull_request", number, reason: .status}]),
       slices: [$ev.slices[] | .readiness | {number, state}],
       open_snapshots: [$ev.slices[] | .readiness | select(.state == "OPEN")]}
    end;
'
}

# _hivemind_sd_lib_ok: 0 when every readiness check and record verify function derive calls is
# defined, else 1.
_hivemind_sd_lib_ok() {
  declare -F hivemind_readiness_commit_ok hivemind_doc_entry hivemind_doc_read \
    hivemind_readiness_jq_defs hivemind_readiness_check_snapshot hivemind_record_verify \
    >/dev/null 2>&1
}

# _hivemind_sd_owner_repo_ok <owner/repo>: 0 when the argument is a safe owner/repo pair, else 1.
_hivemind_sd_owner_repo_ok() {
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

# _hivemind_sd_trunk_ok <trunk-name>: 0 when the argument is a safe trunk branch name, else 1.
_hivemind_sd_trunk_ok() {
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

# _hivemind_sd_slug_ok <slug>: 0 when the argument matches `^[a-z0-9]+(-[a-z0-9]+)*$`, else 1.
_hivemind_sd_slug_ok() {
  local part='[abcdefghijklmnopqrstuvwxyz0123456789]+'
  [[ "$1" =~ ^${part}(-${part})*$ ]]
}

# _hivemind_sd_args_ok <commit> <owner/repo> <trunk-name> <slug>: checks every argument with no
# git call; prints commit-malformed or usage and returns 2 on the first bad one.
_hivemind_sd_args_ok() {
  if ! hivemind_readiness_commit_ok "$1" 2>/dev/null; then
    _hivemind_sd_error commit-malformed
    return 2
  fi
  if ! _hivemind_sd_owner_repo_ok "$2" || ! _hivemind_sd_trunk_ok "$3" || ! _hivemind_sd_slug_ok "$4"; then
    _hivemind_sd_error usage
    return 2
  fi
}

# _hivemind_sd_plan <owner/repo> <slug>: reads the evidence on stdin, validates it and prints the
# resolution plan as one compact JSON object; prints evidence-malformed or truncated and returns
# 2 on a failure. The plan holds no evidence text but the open slices' snapshots.
_hivemind_sd_plan() {
  local plan="" program
  program="$(hivemind_readiness_jq_defs)$(_hivemind_sd_evidence_jq_defs)"'
[inputs] as $input
| if ($input | length) != 1 or ($input[0] | sd_evidence_ok | not) then "evidence-malformed"
  elif ($input[0] | sd_truncated) then "truncated"
  else $input[0] | sd_plan($repo; $slug) end'
  if ! plan="$(jq -nc --arg repo "$1" --arg slug "$2" "$program" 2>/dev/null)"; then
    _hivemind_sd_error evidence-malformed
    return 2
  fi
  case "$plan" in
    '"evidence-malformed"' | '"truncated"')
      _hivemind_sd_error "${plan//\"/}"
      return 2
      ;;
    '{'*) ;;
    *)
      _hivemind_sd_error evidence-malformed
      return 2
      ;;
  esac
  printf '%s\n' "$plan"
}

# _hivemind_sd_resolves <commit>: 0 when <commit> names a commit object, else prints
# commit-unresolvable and returns 2.
_hivemind_sd_resolves() {
  local object_type=""
  object_type="$(git --no-replace-objects --literal-pathspecs cat-file -t "$1" </dev/null 2>/dev/null)" \
    || object_type=""
  if [ "$object_type" != commit ]; then
    _hivemind_sd_error commit-unresolvable
    return 2
  fi
}

# _hivemind_sd_exists <commit> <path>: the Document existence test; 0 when the document exists,
# 1 when it is missing, 2 on a failure whose token it printed.
_hivemind_sd_exists() {
  local output="" entry_rc=0
  output="$(hivemind_doc_entry "$1" "$2" 2>&1)" || entry_rc=$?
  case "$entry_rc" in
    0 | 1) return "$entry_rc" ;;
  esac
  if [ "$output" = 'readiness-check-error: commit-unresolvable' ]; then
    _hivemind_sd_error commit-unresolvable
  else
    _hivemind_sd_error git-failed
  fi
  return 2
}

# _hivemind_sd_read <commit> <path> <filter>: streams the line <path>, the bytes of the document
# at <path> and its hivemind_doc_read status into one jq program running rc_doc_eval(<filter>),
# and prints its raw output: `missing` for a missing document, else the filter's line. Returns 2
# on a failure whose token it printed.
_hivemind_sd_read() {
  local commit="$1" path="$2" read_rc=0 output="" program
  program="$(hivemind_readiness_jq_defs)$(_hivemind_sd_jq_defs)rc_doc_eval($3)"
  if ! output="$(
    {
      printf '%s\n' "$path"
      hivemind_doc_read "$commit" "$path" 2>/dev/null || read_rc=$?
      printf '\n%s' "$read_rc"
    } | jq -Rsr "$program" 2>/dev/null
  )" || [ "$output" = failed ]; then
    _hivemind_sd_error git-failed
    return 2
  fi
  printf '%s\n' "$output"
}

# _hivemind_sd_merge_base <commit> <trunk>: prints the merge-base of the two commits; prints
# git-failed and returns 2 when there is none.
_hivemind_sd_merge_base() {
  local base=""
  base="$(git --no-replace-objects --literal-pathspecs merge-base "$1" "$2" </dev/null 2>/dev/null)" \
    || base=""
  if ! hivemind_readiness_commit_ok "$base" 2>/dev/null; then
    _hivemind_sd_error git-failed
    return 2
  fi
  printf '%s\n' "$base"
}

# _hivemind_sd_verify <head> <base>: runs hivemind_record_verify and prints the path of each
# failing record, one per line; prints git-failed and returns 2 on a failure.
_hivemind_sd_verify() {
  local output="" verify_rc=0
  output="$(hivemind_record_verify "$1" "$2" 2>/dev/null)" || verify_rc=$?
  case "$verify_rc" in
    0) return 0 ;;
    1) printf '%s\n' "${output//record-verify-failed: /}" ;;
    *)
      _hivemind_sd_error git-failed
      return 2
      ;;
  esac
}

# _hivemind_sd_lines_hold <lines> <line>: 0 when <lines> holds exactly the line <line>.
_hivemind_sd_lines_hold() {
  case $'\n'"$1"$'\n' in
    *$'\n'"$2"$'\n'*) return 0 ;;
  esac
  return 1
}

# _hivemind_sd_trunk_current <trunk> <slug>: prints `yes` when trunk is current for <slug>, else
# `no`; returns 2 on a failure.
_hivemind_sd_trunk_current() {
  local trunk="$1" slug="$2" path="" entry_rc=0 record="" failing=""
  for path in "docs/prds/$slug.md" "docs/initiatives/$slug/solution-design.md"; do
    entry_rc=0
    _hivemind_sd_exists "$trunk" "$path" || entry_rc=$?
    case "$entry_rc" in
      0) ;;
      1)
        printf 'no\n'
        return 0
        ;;
      *) return 2 ;;
    esac
  done
  record="$(_hivemind_sd_read "$trunk" "docs/initiatives/$slug/review-record.md" sd_record)" || return 2
  if [ "$record" != pass ]; then
    printf 'no\n'
    return 0
  fi
  failing="$(_hivemind_sd_verify "$trunk" "$trunk")" || return 2
  if _hivemind_sd_lines_hold "$failing" "docs/initiatives/$slug/review-record.md"; then
    printf 'no\n'
  else
    printf 'yes\n'
  fi
}

# _hivemind_sd_rating_missing <trunk> <owner/repo> <trunk-name> <plan>: runs the readiness check
# in snapshot mode on the plan's open slices and prints `yes` when any gives a `rating_missing:`
# code, else `no`; returns 2 on a failure whose token it printed.
_hivemind_sd_rating_missing() {
  local output="" check_rc=0 token=""
  output="$(printf '%s\n' "$4" | jq -c '.open_snapshots' 2>/dev/null \
    | hivemind_readiness_check_snapshot "$1" "$2" "$3" 2>&1)" || check_rc=$?
  if [ "$check_rc" -ne 0 ]; then
    token="${output#readiness-check-error: }"
    case "$token" in
      snapshot-malformed) _hivemind_sd_error evidence-malformed ;;
      truncated | commit-unresolvable | usage) _hivemind_sd_error "$token" ;;
      *) _hivemind_sd_error git-failed ;;
    esac
    return 2
  fi
  if ! printf '%s\n' "$output" \
    | jq -nr '[inputs | .reasons[] | select(startswith("rating_missing:"))]
      | if length > 0 then "yes" else "no" end' 2>/dev/null; then
    _hivemind_sd_error git-failed
    return 2
  fi
}

# _hivemind_sd_slice_stage <trunk> <owner/repo> <trunk-name> <plan>: prints the result of a
# current trunk from the slices (precedence row 5); returns 2 on a failure.
_hivemind_sd_slice_stage() {
  local total="" closed="" missing=""
  read -r total closed < <(printf '%s\n' "$4" \
    | jq -r '[(.slices | length), ([.slices[] | select(.state == "CLOSED")] | length)] | @tsv' 2>/dev/null) \
    || true
  if [ -z "$total" ] || [ -z "$closed" ]; then
    _hivemind_sd_error evidence-malformed
    return 2
  fi
  if [ "$total" -eq 0 ]; then
    printf 'docs-pull-request\tdone\tslice\n'
  elif [ "$closed" -eq "$total" ]; then
    printf 'handoff\tdone\tclose-out\n'
  elif [ "$closed" -gt 0 ]; then
    printf 'handoff\tdelivering\tdeliver\n'
  else
    missing="$(_hivemind_sd_rating_missing "$1" "$2" "$3" "$4")" || return 2
    if [ "$missing" = yes ]; then
      printf 'slicing\tdone\ttriage\n'
    else
      printf 'triage\tdone\thandoff-check\n'
    fi
  fi
}

# _hivemind_sd_prototype_stage <at> <trunk> <slug>: prints the result of a UI initiative's
# prototype stage at <at>, or nothing when the prototype is done; returns 2 on a failure.
_hivemind_sd_prototype_stage() {
  local at="$1" trunk="$2" folder="docs/initiatives/$3" index_rc=0 notes="" design_rc=0
  _hivemind_sd_exists "$at" "$folder/prototype/index.html" || index_rc=$?
  if [ "$index_rc" -eq 2 ]; then
    return 2
  fi
  notes="$(_hivemind_sd_read "$at" "$folder/prototype/notes.md" sd_verdict)" || return 2
  if [ "$index_rc" -eq 0 ] && [ "$notes" = filled ]; then
    return 0
  fi
  _hivemind_sd_exists "$at" "$folder/solution-design.md" || design_rc=$?
  if [ "$design_rc" -eq 1 ] && [ "$at" != "$trunk" ]; then
    design_rc=0
    _hivemind_sd_exists "$trunk" "$folder/solution-design.md" || design_rc=$?
  fi
  case "$design_rc" in
    0) printf '\tout-of-order\task\ndesign_before_prototype\n' ;;
    1)
      if [ "$index_rc" -eq 1 ] && [ "$notes" = missing ]; then
        printf 'prd\tdone\tbuild-prototype\n'
      elif [ "$index_rc" -eq 1 ] || [ "$notes" = missing ]; then
        printf 'ui-prototype\tincomplete\tbuild-prototype\n'
      else
        printf 'ui-prototype\twaiting-approval\tapprove-prototype\n'
      fi
      ;;
    *) return 2 ;;
  esac
}

# _hivemind_sd_review_stage <at> <trunk> <slug> <source> <draft>: prints the result once the
# solution design exists at <at>, from the review record, verify and the docs pull request;
# returns 2 on a failure.
_hivemind_sd_review_stage() {
  local at="$1" trunk="$2" record="docs/initiatives/$3/review-record.md" state="" base="$2"
  local failing="" path=""
  local -a paths=()
  state="$(_hivemind_sd_read "$at" "$record" sd_record)" || return 2
  case "$state" in
    missing)
      printf 'solution-design\tdone\treview\n'
      return 0
      ;;
    malformed)
      printf '\tambiguous\task\nrecord_malformed\n'
      return 0
      ;;
    fail)
      printf 'design-review\tin-progress\treview\n'
      return 0
      ;;
  esac
  if [ "$at" != "$trunk" ]; then
    base="$(_hivemind_sd_merge_base "$at" "$trunk")" || return 2
  fi
  failing="$(_hivemind_sd_verify "$at" "$base")" || return 2
  if _hivemind_sd_lines_hold "$failing" "$record"; then
    printf 'design-review\tstale\tre-review\n'
  elif [ -n "$failing" ]; then
    printf 'docs-pull-request\tverify-failed\task\n'
    mapfile -t paths < <(printf '%s\n' "$failing")
    for path in "${paths[@]}"; do
      if [ -n "$path" ]; then
        printf 'verify_failed:%s\n' "$path"
      fi
    done
  elif [ "$4" != pull_request ]; then
    printf 'docs-pull-request\tno-pull-request\task\n'
  elif [ "$5" = true ]; then
    printf 'docs-pull-request\tin-progress\tmark-ready\n'
  else
    printf 'docs-pull-request\tin-progress\tmerge-docs\n'
  fi
}

# _hivemind_sd_document_stage <trunk> <slug> <docs-commit or -> <source> <draft>: prints the
# result read from the documents at the docs head, else trunk (precedence row 6); returns 2 on
# a failure.
_hivemind_sd_document_stage() {
  local trunk="$1" slug="$2" at="$1" ui="" result="" design_rc=0 done_stage=prd
  if [ "$3" != - ]; then
    at="$3"
  fi
  ui="$(_hivemind_sd_read "$at" "docs/prds/$slug.md" rc_prd_ui)" || return 2
  case "$ui" in
    missing)
      if [ "$at" != "$trunk" ]; then
        printf 'interrogation\tin-progress\tinterrogate\n'
      else
        printf 'capture\tdone\tinterrogate\n'
      fi
      return 0
      ;;
    invalid)
      printf '\tambiguous\task\nprd_ui_invalid\n'
      return 0
      ;;
    yes)
      result="$(_hivemind_sd_prototype_stage "$at" "$trunk" "$slug")" || return 2
      if [ -n "$result" ]; then
        printf '%s\n' "$result"
        return 0
      fi
      done_stage=ui-prototype
      ;;
  esac
  _hivemind_sd_exists "$at" "docs/initiatives/$slug/solution-design.md" || design_rc=$?
  case "$design_rc" in
    0) _hivemind_sd_review_stage "$at" "$trunk" "$slug" "$4" "$5" ;;
    1) printf '%s\tdone\tdesign\n' "$done_stage" ;;
    *) return 2 ;;
  esac
}

# _hivemind_sd_stage <trunk> <owner/repo> <trunk-name> <slug> <plan>: applies the precedence and
# prints the result: one line `<stage>\t<status>\t<next>`, the stage empty when null, then one
# line per reason. Returns 2 on a failure whose token it printed.
_hivemind_sd_stage() {
  local trunk="$1" slug="$4" plan="$5" design="docs/initiatives/$4/solution-design.md"
  local state="" seeds="" prs="" branches="" docs_commit="" draft="" docs_source="" prd_rc=0 current=""
  state="$(_hivemind_sd_read "$trunk" "$design" sd_delivered)" || return 2
  if [ "$state" = delivered ]; then
    printf 'close-out\tdone\tnone\n'
    return 0
  fi
  read -r seeds prs branches docs_commit draft docs_source < <(printf '%s\n' "$plan" | jq -r '
    [.seed_count, .pr_count, .branch_count, (.docs.commit // "-"),
     (if .docs.draft == null then "-" else (.docs.draft | tostring) end), (.docs.source // "-")]
    | @tsv' 2>/dev/null) || true
  if [ -z "$docs_source" ]; then
    _hivemind_sd_error evidence-malformed
    return 2
  fi
  if [ "$seeds" -gt 1 ]; then
    printf '\tambiguous\task\nseed_ambiguous\n'
    return 0
  fi
  if [ "$seeds" -eq 0 ]; then
    if [ "$prs" -eq 0 ] && [ "$branches" -eq 0 ]; then
      _hivemind_sd_exists "$trunk" "docs/prds/$slug.md" || prd_rc=$?
      case "$prd_rc" in
        0) ;;
        1)
          printf 'none\tnot-started\tcapture\n'
          return 0
          ;;
        *) return 2 ;;
      esac
    fi
    printf '\tambiguous\task\nseed_missing\n'
    return 0
  fi
  if [ "$prs" -gt 1 ]; then
    printf '\tambiguous\task\ndocs_pr_ambiguous\n'
    return 0
  fi
  if [ "$prs" -eq 0 ] && [ "$branches" -gt 1 ]; then
    printf '\tambiguous\task\ndocs_branch_ambiguous\n'
    return 0
  fi
  if [ "$docs_commit" != - ]; then
    _hivemind_sd_resolves "$docs_commit" || return 2
    state="$(_hivemind_sd_read "$docs_commit" "$design" sd_delivered)" || return 2
    if [ "$state" = delivered ]; then
      printf 'close-out\tin-progress\tmerge-docs\n'
      return 0
    fi
  fi
  current="$(_hivemind_sd_trunk_current "$trunk" "$slug")" || return 2
  if [ "$current" = yes ]; then
    _hivemind_sd_slice_stage "$trunk" "$2" "$3" "$plan"
    return
  fi
  _hivemind_sd_document_stage "$trunk" "$slug" "$docs_commit" "$docs_source" "$draft"
}

# _hivemind_sd_emit <trunk> <slug> <plan> <result>: prints the output object; prints git-failed
# and returns 2 when jq fails.
_hivemind_sd_emit() {
  local program='
($result | split("\n") | map(select(length > 0))) as $lines
| ($lines[0] | split("\t")) as $head
| {slug: $slug, trunk: $trunk, seed: .seed, docs: .docs,
   stage: (if $head[0] == "" then null else $head[0] end), status: $head[1], next: $head[2],
   reasons: $lines[1:], ignored: .ignored, slices: .slices}'
  if ! printf '%s\n' "$3" | jq -c --arg trunk "$1" --arg slug "$2" --arg result "$4" "$program" 2>/dev/null; then
    _hivemind_sd_error git-failed
    return 2
  fi
}

# hivemind_stage_derive <trunk-commit> <owner/repo> <trunk-name> <slug>: derives the initiative's
# stage from the evidence on stdin (see PUBLIC API).
hivemind_stage_derive() {
  if [ "$#" -ne 4 ]; then
    _hivemind_sd_error usage
    return 2
  fi
  local trunk="${1-}" owner_repo="${2-}" trunk_name="${3-}" slug="${4-}" plan="" result="" output=""
  if ! _hivemind_sd_lib_ok; then
    _hivemind_sd_error missing-library
    return 2
  fi
  _hivemind_sd_args_ok "$trunk" "$owner_repo" "$trunk_name" "$slug" || return 2
  plan="$(_hivemind_sd_plan "$owner_repo" "$slug")" || return 2
  _hivemind_sd_resolves "$trunk" || return 2
  result="$(_hivemind_sd_stage "$trunk" "$owner_repo" "$trunk_name" "$slug" "$plan")" || return 2
  output="$(_hivemind_sd_emit "$trunk" "$slug" "$plan" "$result")" || return 2
  printf '%s\n' "$output"
}
