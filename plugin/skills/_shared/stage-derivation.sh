# shellcheck shell=bash
#
# stage-derivation.sh — shared initiative stage derivation library (ADR-0046, solution design
# "Stage derivation and handoff check"): a pure function from GitHub evidence and git to an
# initiative's stage and next action. No progress state is stored (D2). Its caller is the guide's
# script, which reads the evidence with hivemind_stage_evidence_gh and passes it on stdin.
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
# no file, no scratch path. Derive and the handoff check make no `gh` call: every GitHub fact
# arrives as evidence on stdin. The evidence read, hivemind_stage_evidence_gh, is the library's one
# GitHub reader and makes no git call. Every document (the PRD, both UI prototype files, the solution design and the review
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
# truncated, gh-failed, git-failed. gh-failed is given only by the evidence read; derive and the
# handoff check never give it. A readiness check failure is translated: snapshot-malformed to
# evidence-malformed, truncated, commit-unresolvable and usage kept, any other to git-failed. The
# library never exits; derive and the handoff check never print evidence or document text.
#
# PUBLIC API (every function shares the failure contract):
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
#   hivemind_stage_handoff <trunk-commit> <owner/repo> <trunk-name> <slug>  (evidence on stdin)
#       The handoff check, with derive's arguments, evidence and failures. Prints one compact
#       JSON object and returns 0:
#       {"slug", "commit": <trunk-commit>, "result": "pass"|"fail", "reasons": [<code>...],
#        "slices": [{"issue", "result": "pass"|"fail", "claimable": <bool>,
#                    "reasons": [<code>...]}...], "ignored": [as derive's]}
#       Slices are sorted by number. `reasons` holds the initiative codes, a closed set, in this
#       order: seed_missing (no seed), seed_ambiguous (two or more), design_delivered (the
#       solution design at trunk), docs_not_on_trunk (the PRD or the solution design fails the
#       existence test at trunk), record_not_current (trunk's review record is missing, malformed,
#       fails the pass rule or is named by verify), epic_closed and epic_type_missing (the epic
#       is closed, or has no `type:epic` label, so it could be claimed), no_slices. A slice's
#       reasons are its readiness codes from one hivemind_readiness_check_snapshot call over every
#       slice snapshot, then the label authority codes, then `blocked_by:<n>` per open blocked-by
#       edge, ascending. Label authority (D29; ADR-0045 decision 10, as amended by #625): no
#       `readiness:ready` label gives ready_label_missing; else the latest `readiness:ready`
#       labeled event, every event at that latest time, must come from a writer, an actor of
#       type User with write permission (a Bot or a null actor never is), else
#       ready_actor_not_writer, also with no event; and last_edited_at or a title rename at or
#       after that event gives edited_since_ready. A slice passes when it has no readiness or
#       label authority code, and is claimable when it passes with no open blocked-by edge. The
#       result is `pass` only with no initiative code and every slice passing.
#   hivemind_stage_evidence_gh <owner/repo> <slug>
#       The evidence read: prints evidence JSON v1 as one compact object and returns 0. Both
#       arguments are checked before any gh call (usage); it makes no git call. Each read is one
#       `gh api graphql` call whose query is a constant taking every value as a GraphQL variable,
#       each connection first:100, in this order: the seed marker search `repo:<owner/repo>
#       is:issue in:body "hivemind-initiative: <slug>"`, the docs pull request search
#       `repo:<owner/repo> is:pr is:open head:docs/<slug>`, the branches under refs/heads/ whose
#       name holds `docs/<slug>` with their pull request counts; then, for the one resolved seed,
#       its labels and sub-issues; then per sub-issue, in order, its snapshot through
#       hivemind_readiness_fetch_snapshot and its lastEditedAt with its labeled and renamed-title
#       timeline events. Any pageInfo.hasNextPage true is truncated. Write permission is one
#       `gh api repos/<owner/repo>/collaborators/<login>/permission` read per distinct login,
#       admin or write being a writer, made only for the author of an open seed whose first line
#       is this slug's marker, the author of a same-repository pull request whose head ref counts,
#       and each actor of a slice's latest `readiness:ready` events, and only for an account of
#       type User whose login matches `^[A-Za-z0-9][A-Za-z0-9-]{0,38}$`. author_can_write and
#       actor_can_write are true only for a login such a read found a writer; any other account,
#       a Bot, a null one or a malformed-marker issue's author, is no writer and costs no call.
#       Seeds hold every search result; pull requests and branches only those named `docs/...`.
#       gh missing from PATH, a non-zero gh exit (a 404 included), a reply that is not exactly one
#       JSON object with `errors` null or [] and a `data` object, or a reply off its query's shape
#       gives gh-failed; a snapshot's truncated stays truncated and any other snapshot failure is
#       gh-failed. Failure tokens: usage, missing-library, truncated, gh-failed.
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
#    "epic": null | {"number", "state", "sub_issue_total": <n>,
#                    "labels": {"nodes": [{"name"}...], "pageInfo": {"hasNextPage": <bool>}}},
#        the seed issue as epic with its sub-issue count and labels; null when no seed was read;
#    "slices": [{"readiness": <readiness check issue snapshot, its labels nodes holding each
#                name and its blockedBy nodes each number and state>,
#                "last_edited_at": <timestamp or null>,
#                "ready_events": [{"actor": null | {"login", "__typename"}, "actor_can_write":
#                                  <bool>, "created_at"}...],
#                "renamed_at": [<timestamp>...]}...]}
#        every sub-issue of the epic; the snapshot is the readiness check's snapshot mode input;
#        ready_events holds every `readiness:ready` labeled event, renamed_at every title rename.
#   Fewer slices than `sub_issue_total`, any snapshot `pageInfo.hasNextPage` true, or the epic's
#   labels `hasNextPage` true, is truncated. Slices with a null epic, more slices than
#   `sub_issue_total`, or an epic that is not the one seed, are evidence-malformed.
#
# RESOLUTION: the seed is the one open issue whose body's first line, one ending CR removed, is
# `<!-- hivemind-initiative: <slug> -->` and whose author has write permission. A marker-shaped
# first line with a malformed slug is ignored as `seed_marker_malformed`, with no git call; a
# closed one as `seed_closed`; a non-writer's as `seed_author_not_writer`. An issue whose first
# line is no marker or another slug's marker, but a later line of whose body, one ending CR
# removed, is this slug's marker, is ignored as `seed_marker_not_first_line`; with no such line
# it is not this initiative's and is not named. A pull
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
#      the readiness check gives a `rating_missing:` code: slicing / done / triage; else the
#      handoff check: a pass gives handoff / done / deliver, a fail triage / blocked /
#      resolve-blockers [<initiative code>..., slice_failed:<n> per failing slice, ascending].
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
def sd_names_ok: type == "object" and (.nodes | sd_list(type == "object" and (.name | sd_text)));
def sd_epic_ok:
  . == null
  or (type == "object" and (.number | sd_number) and (.state | sd_state)
      and (.sub_issue_total | sd_count) and (.labels | sd_names_ok)
      and (.labels.pageInfo | type) == "object" and (.labels.pageInfo.hasNextPage | sd_bool));
def sd_actor_ok: . == null or (type == "object" and (.login | sd_text) and (.__typename | sd_text));
def sd_event_ok:
  type == "object" and has("actor") and (.actor | sd_actor_ok) and (.actor_can_write | sd_bool)
  and (.created_at | sd_time);
def sd_blocker_ok: type == "object" and (.number | sd_number) and (.state | sd_state);
def sd_slice_ok:
  type == "object" and (.readiness | type) == "object" and (.readiness.number | sd_number)
  and (.readiness.state | sd_state) and (.readiness.labels | sd_names_ok)
  and (.readiness.blockedBy | type) == "object" and (.readiness.blockedBy.nodes | sd_list(sd_blocker_ok))
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
  (.epic != null and ((.slices | length) < .epic.sub_issue_total or .epic.labels.pageInfo.hasNextPage))
  or any(.slices[];
      [.readiness | .. | objects | select(has("pageInfo")) | .pageInfo]
      | any(.[]; type == "object" and .hasNextPage == true));
def sd_seed_status($slug):
  ((.body // "") | rc_lines) as $lines
  | [($lines[0] // "") | capture("\\A<!-- hivemind-initiative: (?<s>.*) -->\\z") | .s] as $found
  | if ($found | length) == 1 and ($found[0] | test("\\A" + rc_slug + "\\z") | not)
    then "seed_marker_malformed"
    elif ($found | length) == 1 and $found[0] == $slug then
      if .state != "OPEN" then "seed_closed"
      elif (.author_can_write | not) then "seed_author_not_writer"
      else "seed" end
    elif any($lines[1:][]; . == "<!-- hivemind-initiative: " + $slug + " -->")
    then "seed_marker_not_first_line"
    else "unrelated" end;
def sd_writer_event: .actor != null and .actor.__typename == "User" and .actor_can_write;
def sd_authority:
  .readiness as $sn
  | (.ready_events | map(.created_at) | max) as $latest
  | [.ready_events[] | select(.created_at == $latest)] as $latest_events
  | {issue: $sn.number,
     codes: (if any($sn.labels.nodes[]; .name == "readiness:ready") | not then ["ready_label_missing"]
             else
               (if ($latest_events | length) == 0 or any($latest_events[]; sd_writer_event | not)
                then ["ready_actor_not_writer"] else [] end)
               + (if $latest != null
                     and ((.last_edited_at != null and .last_edited_at >= $latest)
                          or any(.renamed_at[]; . >= $latest))
                  then ["edited_since_ready"] else [] end)
             end),
     blockers: ([$sn.blockedBy.nodes[] | select(.state == "OPEN") | .number] | unique)};
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
       epic: (if $ev.epic == null then null
              else {state: $ev.epic.state, typed: any($ev.epic.labels.nodes[]; .name == "type:epic")} end),
       snapshots: [$ev.slices[] | .readiness],
       authority: [$ev.slices[] | sd_authority]}
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
# 2 on a failure. The plan holds no evidence text but the slices' snapshots.
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
# the initiative code naming why not, docs_not_on_trunk or record_not_current; returns 2 on a
# failure.
_hivemind_sd_trunk_current() {
  local trunk="$1" slug="$2" path="" entry_rc=0 record="" failing=""
  for path in "docs/prds/$slug.md" "docs/initiatives/$slug/solution-design.md"; do
    entry_rc=0
    _hivemind_sd_exists "$trunk" "$path" || entry_rc=$?
    case "$entry_rc" in
      0) ;;
      1)
        printf 'docs_not_on_trunk\n'
        return 0
        ;;
      *) return 2 ;;
    esac
  done
  record="$(_hivemind_sd_read "$trunk" "docs/initiatives/$slug/review-record.md" sd_record)" || return 2
  if [ "$record" != pass ]; then
    printf 'record_not_current\n'
    return 0
  fi
  failing="$(_hivemind_sd_verify "$trunk" "$trunk")" || return 2
  if _hivemind_sd_lines_hold "$failing" "docs/initiatives/$slug/review-record.md"; then
    printf 'record_not_current\n'
  else
    printf 'yes\n'
  fi
}

# _hivemind_sd_readiness <trunk> <owner/repo> <trunk-name> <plan>: runs the readiness check once in
# snapshot mode over every slice snapshot of the plan and prints its output lines; translates a
# readiness check failure to this library's token and returns 2.
_hivemind_sd_readiness() {
  local output="" check_rc=0 token=""
  output="$(printf '%s\n' "$4" | jq -c '.snapshots' 2>/dev/null \
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
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
  fi
}

# _hivemind_sd_initiative_git_codes <trunk> <slug>: prints the initiative codes read from git, one
# per line: design_delivered, then docs_not_on_trunk or record_not_current; returns 2 on a
# failure.
_hivemind_sd_initiative_git_codes() {
  local state="" current=""
  state="$(_hivemind_sd_read "$1" "docs/initiatives/$2/solution-design.md" sd_delivered)" || return 2
  if [ "$state" = delivered ]; then
    printf 'design_delivered\n'
  fi
  current="$(_hivemind_sd_trunk_current "$1" "$2")" || return 2
  if [ "$current" != yes ]; then
    printf '%s\n' "$current"
  fi
}

# _hivemind_sd_handoff <trunk> <owner/repo> <trunk-name> <slug> <plan> <git-codes>: prints the
# handoff check's output object from the plan, the readiness check over every slice and the
# initiative codes read from git (empty when none); returns 2 on a failure whose token it printed.
_hivemind_sd_handoff() {
  local checks="" program='
[inputs] as $all
| $all[0] as $plan
| $all[1:] as $checks
| if ($checks | length) != ($plan.authority | length) then error("readiness line count") else . end
| ($plan.authority | map({key: (.issue | tostring), value: .}) | from_entries) as $authority
| [$checks[] | . as $check | $authority[$check.issue | tostring] as $slice
   | if $slice == null then error("readiness issue unknown") else . end
   | (($check.reasons + $slice.codes) | length == 0) as $pass
   | {issue: $check.issue, result: (if $pass then "pass" else "fail" end),
      claimable: ($pass and ($slice.blockers | length) == 0),
      reasons: ($check.reasons + $slice.codes + [$slice.blockers[] | "blocked_by:\(.)"])}]
  | sort_by(.issue) as $slices
| (($git_codes | split("\n") | map(select(length > 0)))
   + (if $plan.seed_count == 0 then ["seed_missing"] else [] end)
   + (if $plan.seed_count > 1 then ["seed_ambiguous"] else [] end)
   + (if $plan.epic != null and $plan.epic.state != "OPEN" then ["epic_closed"] else [] end)
   + (if $plan.epic != null and ($plan.epic.typed | not) then ["epic_type_missing"] else [] end)
   + (if ($plan.slices | length) == 0 then ["no_slices"] else [] end)) as $found
| [("seed_missing", "seed_ambiguous", "design_delivered", "docs_not_on_trunk", "record_not_current",
    "epic_closed", "epic_type_missing", "no_slices") as $code
   | select(any($found[]; . == $code)) | $code] as $reasons
| {slug: $slug, commit: $trunk,
   result: (if ($reasons | length) == 0 and all($slices[]; .result == "pass") then "pass" else "fail" end),
   reasons: $reasons, slices: $slices, ignored: $plan.ignored}'
  checks="$(_hivemind_sd_readiness "$1" "$2" "$3" "$5")" || return 2
  if ! printf '%s\n%s\n' "$5" "$checks" \
    | jq -nc --arg trunk "$1" --arg slug "$4" --arg git_codes "$6" "$program" 2>/dev/null; then
    _hivemind_sd_error git-failed
    return 2
  fi
}

# _hivemind_sd_slice_stage <trunk> <owner/repo> <trunk-name> <slug> <plan>: prints the result of
# a current trunk from the slices (precedence row 5); returns 2 on a failure.
_hivemind_sd_slice_stage() {
  local total="" closed="" handoff="" program='
if any(.slices[].reasons[]; startswith("rating_missing:")) then "slicing\tdone\ttriage"
elif .result == "pass" then "handoff\tdone\tdeliver"
else "triage\tblocked\tresolve-blockers", .reasons[],
  (.slices[] | select(.result != "pass") | "slice_failed:\(.issue)") end'
  read -r total closed < <(printf '%s\n' "$5" \
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
    handoff="$(_hivemind_sd_handoff "$1" "$2" "$3" "$4" "$5" "")" || return 2
    if ! printf '%s\n' "$handoff" | jq -r "$program" 2>/dev/null; then
      _hivemind_sd_error git-failed
      return 2
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
    _hivemind_sd_slice_stage "$trunk" "$2" "$3" "$slug" "$plan"
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

# hivemind_stage_handoff <trunk-commit> <owner/repo> <trunk-name> <slug>: runs the handoff check on
# the evidence on stdin (see PUBLIC API).
hivemind_stage_handoff() {
  if [ "$#" -ne 4 ]; then
    _hivemind_sd_error usage
    return 2
  fi
  local trunk="${1-}" owner_repo="${2-}" trunk_name="${3-}" slug="${4-}" plan="" codes="" output=""
  if ! _hivemind_sd_lib_ok; then
    _hivemind_sd_error missing-library
    return 2
  fi
  _hivemind_sd_args_ok "$trunk" "$owner_repo" "$trunk_name" "$slug" || return 2
  plan="$(_hivemind_sd_plan "$owner_repo" "$slug")" || return 2
  _hivemind_sd_resolves "$trunk" || return 2
  codes="$(_hivemind_sd_initiative_git_codes "$trunk" "$slug")" || return 2
  output="$(_hivemind_sd_handoff "$trunk" "$owner_repo" "$trunk_name" "$slug" "$plan" "$codes")" || return 2
  printf '%s\n' "$output"
}

# _hivemind_sd_gh_jq_defs: prints the constant jq definitions that check each gh reply and build
# the evidence from the replies; they need hivemind_readiness_jq_defs and
# _hivemind_sd_evidence_jq_defs before them. Each sd_gh_<read> filter runs on a reply's `data`
# object and gives the read's value, "truncated" or "gh-failed".
_hivemind_sd_gh_jq_defs() {
  printf '%s\n' '
def sd_gh_envelope_ok: type == "object" and (.errors == null or .errors == []) and (.data | type) == "object";
def sd_gh_page_ok(f): type == "object" and (.pageInfo | type) == "object" and (.pageInfo.hasNextPage | sd_bool)
  and (.nodes | sd_list(f));
def sd_gh_more: .pageInfo.hasNextPage;
def sd_gh_login_ok: sd_text and test("\\A[A-Za-z0-9][A-Za-z0-9-]{0,38}\\z");
def sd_gh_account_ok: . == null or (type == "object" and (.login | sd_text) and (.__typename | sd_text));
def sd_gh_user: . != null and .__typename == "User" and (.login | sd_gh_login_ok);
def sd_gh_writer($writers): sd_gh_user and ($writers[.login] // false) == true;
def sd_gh_seed_ok:
  type == "object" and (.number | sd_number) and (.state | sd_state) and has("body")
  and (.body == null or (.body | sd_text)) and has("author") and (.author | sd_gh_account_ok);
def sd_gh_pull_request_ok:
  type == "object" and (.number | sd_number) and (.headRefName | sd_text) and (.headRefOid | sd_hex)
  and (.isDraft | sd_bool) and has("headRepository")
  and (.headRepository == null or (type == "object" and (.headRepository.nameWithOwner | sd_text)))
  and has("author") and (.author | sd_gh_account_ok);
def sd_gh_ref_ok:
  type == "object" and (.name | sd_text) and (.target | type) == "object" and (.target.oid | sd_hex)
  and (.associatedPullRequests | type) == "object" and (.associatedPullRequests.totalCount | sd_count);
def sd_gh_labeled_ok:
  type == "object" and (.createdAt | sd_time) and (.label | type) == "object" and (.label.name | sd_text)
  and has("actor") and (.actor | sd_gh_account_ok);
def sd_gh_search(f):
  .search
  | if sd_gh_page_ok(f) | not then "gh-failed" elif sd_gh_more then "truncated" else .nodes end;
def sd_gh_seeds: sd_gh_search(sd_gh_seed_ok);
def sd_gh_pull_requests: sd_gh_search(sd_gh_pull_request_ok);
def sd_gh_refs:
  .repository
  | if type != "object" or (.refs | sd_gh_page_ok(sd_gh_ref_ok) | not) then "gh-failed"
    elif .refs | sd_gh_more then "truncated" else .refs.nodes end;
def sd_gh_epic($number):
  .repository
  | if type != "object" then "gh-failed"
    else .issue
    | if type != "object" or .number != $number or (.state | sd_state | not)
         or (.labels | sd_gh_page_ok(type == "object" and (.name | sd_text)) | not)
         or (.subIssues | sd_gh_page_ok(type == "object" and (.number | sd_number)) | not)
         or (.subIssues.totalCount | sd_count | not) then "gh-failed"
      elif (.labels | sd_gh_more) or (.subIssues | sd_gh_more) then "truncated"
      else . end
    end;
def sd_gh_timeline($number):
  .repository
  | if type != "object" then "gh-failed"
    else .issue
    | if type != "object" or .number != $number or (has("lastEditedAt") | not)
         or (.lastEditedAt != null and (.lastEditedAt | sd_time | not))
         or (.labeled | sd_gh_page_ok(sd_gh_labeled_ok) | not)
         or (.renamed | sd_gh_page_ok(type == "object" and (.createdAt | sd_time)) | not) then "gh-failed"
      elif (.labeled | sd_gh_more) or (.renamed | sd_gh_more) then "truncated"
      else . end
    end;
def sd_gh_ready_events: [.labeled.nodes[] | select(.label.name == "readiness:ready")];
def sd_gh_latest_ready_logins:
  sd_gh_ready_events as $events
  | ($events | map(.createdAt) | max) as $latest
  | $events[] | select(.createdAt == $latest) | .actor | select(sd_gh_user) | .login;
def sd_gh_seed($writers):
  {number, state, author_can_write: (.author | sd_gh_writer($writers)), body};
def sd_gh_pull_request($writers):
  {number, head_ref: .headRefName, head_oid: .headRefOid,
   head_repository: (if .headRepository == null then null else .headRepository.nameWithOwner end),
   author_can_write: (.author | sd_gh_writer($writers)), draft: .isDraft};
def sd_gh_candidate_logins($repo; $slug):
  ("\\Adocs/" + $slug + "(-" + rc_slug + ")?\\z") as $docs_name
  | (.[0][] | select(.author | sd_gh_user)
     | select((sd_gh_seed({}) + {author_can_write: true} | sd_seed_status($slug)) == "seed") | .author.login),
    (.[1][] | select((.author | sd_gh_user) and (.headRefName | test($docs_name)))
     | select((sd_gh_pull_request({}) + {author_can_write: true} | sd_pull_request_status($repo)) == "counts")
     | .author.login);
def sd_gh_writer_map:
  split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] == "true")}) | from_entries;
def sd_gh_resolved_seed($slug; $writers):
  [.[] | sd_gh_seed($writers) | select(sd_seed_status($slug) == "seed") | .number]
  | if length == 1 then .[0] else empty end;
def sd_gh_slice($writers):
  .[1] as $timeline
  | {readiness: .[0], last_edited_at: $timeline.lastEditedAt,
     ready_events: [$timeline | sd_gh_ready_events[]
                    | {actor: (if .actor == null then null
                               else {login: .actor.login, __typename: .actor.__typename} end),
                       actor_can_write: (.actor | sd_gh_writer($writers)), created_at: .createdAt}],
     renamed_at: [$timeline.renamed.nodes[] | .createdAt]};
def sd_gh_evidence($writers):
  . as $all
  | {version: 1,
     seeds: [$all[0][] | sd_gh_seed($writers)],
     pull_requests: [$all[1][] | select(.headRefName | startswith("docs/")) | sd_gh_pull_request($writers)],
     branches: [$all[2][] | select(.name | startswith("docs/"))
                | {name, oid: .target.oid, pull_request_count: .associatedPullRequests.totalCount}],
     epic: ($all[3] | if . == null then null
                      else {number, state, sub_issue_total: .subIssues.totalCount,
                            labels: {nodes: [.labels.nodes[] | {name}],
                                     pageInfo: {hasNextPage: .labels.pageInfo.hasNextPage}}} end),
     slices: [$all[4:] as $rest | range(0; $rest | length; 2) | [$rest[.], $rest[. + 1]]
              | sd_gh_slice($writers)]};
'
}

# _hivemind_sd_gh_query <seeds|pull-requests|refs|epic|timeline>: prints the read's constant
# GraphQL query; every value it reads arrives as a GraphQL variable.
_hivemind_sd_gh_query() {
  case "$1" in
    seeds)
      printf '%s\n' 'query($q:String!){search(query:$q,type:ISSUE,first:100){pageInfo{hasNextPage} nodes{... on Issue{number state body author{login __typename}}}}}'
      ;;
    pull-requests)
      printf '%s\n' 'query($q:String!){search(query:$q,type:ISSUE,first:100){pageInfo{hasNextPage} nodes{... on PullRequest{number headRefName headRefOid isDraft headRepository{nameWithOwner} author{login __typename}}}}}'
      ;;
    refs)
      printf '%s\n' 'query($owner:String!,$name:String!,$q:String!){repository(owner:$owner,name:$name){refs(refPrefix:"refs/heads/",query:$q,first:100){pageInfo{hasNextPage} nodes{name target{oid} associatedPullRequests(states:[OPEN,CLOSED,MERGED]){totalCount}}}}}'
      ;;
    epic)
      printf '%s\n' 'query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){number state labels(first:100){pageInfo{hasNextPage} nodes{name}} subIssues(first:100){totalCount pageInfo{hasNextPage} nodes{number}}}}}'
      ;;
    timeline)
      printf '%s\n' 'query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){number lastEditedAt labeled:timelineItems(itemTypes:[LABELED_EVENT],first:100){pageInfo{hasNextPage} nodes{... on LabeledEvent{createdAt label{name} actor{login __typename}}}} renamed:timelineItems(itemTypes:[RENAMED_TITLE_EVENT],first:100){pageInfo{hasNextPage} nodes{... on RenamedTitleEvent{createdAt}}}}}}'
      ;;
  esac
}

# _hivemind_sd_graphql <filter> <number> <gh-arg>...: runs one `gh api graphql <gh-arg>...` call
# and prints the value <filter>, one sd_gh_<read> definition taking <number> (0 for a search),
# gives on the reply's data. gh's output and exit status reach jq on stdin as one framed stream:
# the body, a newline, then the status. Prints truncated or gh-failed and returns 2 on a failure.
_hivemind_sd_graphql() {
  local filter="$1" number="$2" reply="" gh_rc=0 program
  shift 2
  if ! command -v gh >/dev/null 2>&1; then
    _hivemind_sd_error gh-failed
    return 2
  fi
  program="$(hivemind_readiness_jq_defs)$(_hivemind_sd_evidence_jq_defs)$(_hivemind_sd_gh_jq_defs)"'
[inputs] as $all
| if ($all | length) != 2 or $all[1] != 0 or ($all[0] | sd_gh_envelope_ok | not) then "gh-failed"
  else $all[0].data | '"$filter"' end'
  if ! reply="$(
    {
      gh api graphql "$@" </dev/null 2>/dev/null || gh_rc=$?
      printf '\n%s' "$gh_rc"
    } 2>/dev/null | jq -nc --argjson number "$number" "$program" 2>/dev/null
  )"; then
    _hivemind_sd_error gh-failed
    return 2
  fi
  case "$reply" in
    '"gh-failed"' | '"truncated"' | '')
      reply="${reply//\"/}"
      _hivemind_sd_error "${reply:-gh-failed}"
      return 2
      ;;
  esac
  printf '%s\n' "$reply"
}

# _hivemind_sd_login_ok <login>: 0 when the argument matches `^[A-Za-z0-9][A-Za-z0-9-]{0,38}$`.
_hivemind_sd_login_ok() {
  local alnum='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
  local pattern="^[${alnum}][${alnum}-]{0,38}\$"
  [[ "$1" =~ $pattern ]]
}

# _hivemind_sd_writer <owner/repo> <login>: reads <login>'s permission on <owner/repo> through one
# gh REST call and prints `true` for admin or write, else `false`; prints gh-failed and returns 2
# on a failure. The caller checks <login> first.
_hivemind_sd_writer() {
  local verdict="" gh_rc=0 program='
[inputs] as $all
| if ($all | length) != 2 or $all[1] != 0 or ($all[0] | type) != "object"
     or ($all[0].permission | type) != "string" then "gh-failed"
  else ($all[0].permission == "admin" or $all[0].permission == "write") end'
  if ! command -v gh >/dev/null 2>&1; then
    _hivemind_sd_error gh-failed
    return 2
  fi
  if ! verdict="$(
    {
      gh api "repos/$1/collaborators/$2/permission" </dev/null 2>/dev/null || gh_rc=$?
      printf '\n%s' "$gh_rc"
    } 2>/dev/null | jq -n "$program" 2>/dev/null
  )"; then
    _hivemind_sd_error gh-failed
    return 2
  fi
  case "$verdict" in
    true | false) printf '%s\n' "$verdict" ;;
    *)
      _hivemind_sd_error gh-failed
      return 2
      ;;
  esac
}

# _hivemind_sd_writers <owner/repo> <known> <login>...: reads the permission of each <login> that
# matches the login pattern and is not yet in <known>, the lines `<login>\t<true|false>` read so
# far, once each, and prints one such line per new read; returns 2 on a failure.
_hivemind_sd_writers() {
  local owner_repo="$1" known="$2" login="" verdict=""
  shift 2
  for login in "$@"; do
    if ! _hivemind_sd_login_ok "$login"; then
      continue
    fi
    case $'\n'"$known" in
      *$'\n'"$login"$'\t'*) continue ;;
    esac
    verdict="$(_hivemind_sd_writer "$owner_repo" "$login")" || return 2
    known+="$login"$'\t'"$verdict"$'\n'
    printf '%s\t%s\n' "$login" "$verdict"
  done
}

# _hivemind_sd_jq_lines <program> <slug> <owner/repo> <writers>: runs one constant program over the
# JSON values on stdin, with the gh jq definitions, and prints its raw lines; prints gh-failed and
# returns 2 when jq fails.
_hivemind_sd_jq_lines() {
  local program
  program="$(hivemind_readiness_jq_defs)$(_hivemind_sd_evidence_jq_defs)$(_hivemind_sd_gh_jq_defs)$1"
  if ! jq -nr --arg slug "$2" --arg repo "$3" --arg writers "$4" "$program" 2>/dev/null; then
    _hivemind_sd_error gh-failed
    return 2
  fi
}

# _hivemind_sd_snapshot <owner/repo> <number>: prints the issue's snapshot through
# hivemind_readiness_fetch_snapshot; keeps its truncated and gives gh-failed for any other failure.
_hivemind_sd_snapshot() {
  local output="" fetch_rc=0
  output="$(hivemind_readiness_fetch_snapshot "$1" "$2" 2>&1)" || fetch_rc=$?
  if [ "$fetch_rc" -ne 0 ]; then
    if [ "$output" = 'readiness-check-error: truncated' ]; then
      _hivemind_sd_error truncated
    else
      _hivemind_sd_error gh-failed
    fi
    return 2
  fi
  printf '%s\n' "$output"
}

# hivemind_stage_evidence_gh <owner/repo> <slug>: reads the initiative's evidence from GitHub and
# prints evidence JSON v1 (see PUBLIC API).
hivemind_stage_evidence_gh() {
  if [ "$#" -ne 2 ]; then
    _hivemind_sd_error usage
    return 2
  fi
  local owner_repo="${1-}" slug="${2-}" seeds="" prs="" refs="" logins="" writers="" new="" seed=""
  local epic=null number="" snapshot="" timeline="" slices="" evidence=""
  local -a login_list=() numbers=()
  if ! declare -F hivemind_readiness_jq_defs hivemind_readiness_fetch_snapshot >/dev/null 2>&1; then
    _hivemind_sd_error missing-library
    return 2
  fi
  if ! _hivemind_sd_owner_repo_ok "$owner_repo" || ! _hivemind_sd_slug_ok "$slug"; then
    _hivemind_sd_error usage
    return 2
  fi
  seeds="$(_hivemind_sd_graphql sd_gh_seeds 0 -f query="$(_hivemind_sd_gh_query seeds)" \
    -f q="repo:$owner_repo is:issue in:body \"hivemind-initiative: $slug\"")" || return 2
  prs="$(_hivemind_sd_graphql sd_gh_pull_requests 0 -f query="$(_hivemind_sd_gh_query pull-requests)" \
    -f q="repo:$owner_repo is:pr is:open head:docs/$slug")" || return 2
  refs="$(_hivemind_sd_graphql sd_gh_refs 0 -f query="$(_hivemind_sd_gh_query refs)" \
    -f owner="${owner_repo%%/*}" -f name="${owner_repo#*/}" -f q="docs/$slug")" || return 2
  logins="$(printf '%s\n%s\n' "$seeds" "$prs" \
    | _hivemind_sd_jq_lines '[inputs] | sd_gh_candidate_logins($repo; $slug)' "$slug" "$owner_repo" "")" \
    || return 2
  mapfile -t login_list <<<"$logins"
  writers="$(_hivemind_sd_writers "$owner_repo" "" "${login_list[@]}")" || return 2
  seed="$(printf '%s\n' "$seeds" \
    | _hivemind_sd_jq_lines 'input | sd_gh_resolved_seed($slug; $writers | sd_gh_writer_map)' \
      "$slug" "$owner_repo" "$writers")" || return 2
  if [ -n "$seed" ]; then
    epic="$(_hivemind_sd_graphql 'sd_gh_epic($number)' "$seed" -f query="$(_hivemind_sd_gh_query epic)" \
      -f owner="${owner_repo%%/*}" -f name="${owner_repo#*/}" -F number="$seed")" || return 2
    mapfile -t numbers < <(printf '%s\n' "$epic" | jq -r '.subIssues.nodes[].number' 2>/dev/null)
  fi
  logins=""
  for number in "${numbers[@]}"; do
    snapshot="$(_hivemind_sd_snapshot "$owner_repo" "$number")" || return 2
    timeline="$(_hivemind_sd_graphql 'sd_gh_timeline($number)' "$number" \
      -f query="$(_hivemind_sd_gh_query timeline)" -f owner="${owner_repo%%/*}" \
      -f name="${owner_repo#*/}" -F number="$number")" || return 2
    slices+="$snapshot"$'\n'"$timeline"$'\n'
    new="$(printf '%s\n' "$timeline" | _hivemind_sd_jq_lines 'input | sd_gh_latest_ready_logins' \
      "$slug" "$owner_repo" "")" || return 2
    logins+="$new"$'\n'
  done
  mapfile -t login_list <<<"$logins"
  new="$(_hivemind_sd_writers "$owner_repo" "$writers"$'\n' "${login_list[@]}")" || return 2
  writers+=$'\n'"$new"
  evidence="$(printf '%s\n%s\n%s\n%s\n%s' "$seeds" "$prs" "$refs" "$epic" "$slices" \
    | _hivemind_sd_jq_lines '[inputs] | sd_gh_evidence($writers | sd_gh_writer_map) | tojson' \
      "$slug" "$owner_repo" "$writers")" || return 2
  printf '%s\n' "$evidence"
}
