#!/usr/bin/env bash
#
# idea-to-ready.sh — engine entrypoint for the hivemind:idea-to-ready guide skill (ADR-0046
# decision 10; solution design "Guide skill", "Initiative stages", "Re-review and re-stamp",
# "Close-out"). It reads the facts the guide needs between stages, composes the fixed request of
# each standard-delivery run the guide launches, and makes the guide's GitHub writes: the seed
# issue, a standalone issue, the docs pull request comments, and the docs pull request's draft
# state. It judges no document's quality, stores no progress state (D2) and never writes a label:
# it never applies readiness:ready (D29). It makes no git write except the FETCH_HEAD each fetch
# writes; it writes no file outside a private work folder it removes on exit.
#
# Usage:
#   idea-to-ready.sh list
#   idea-to-ready.sh stage --slug <slug>
#   idea-to-ready.sh handoff --slug <slug>
#   idea-to-ready.sh seed --slug <slug> --title-file <inputs> [--body-file <inputs>]
#   idea-to-ready.sh standalone --title-file <inputs> --body-file <inputs>
#   idea-to-ready.sh reviewed --slug <slug> --pr <n>
#   idea-to-ready.sh compose --kind <kind> --slug <slug> --pr <n>|none [--commit <commit>]
#                            [--round <n>]
#   idea-to-ready.sh comment --kind round|approval|review|veto --slug <slug> --pr <n>
#                            [--round <n>] [--commit <commit>] [--body-file <inputs>]
#   idea-to-ready.sh approval --slug <slug> --pr <n>
#   idea-to-ready.sh redraft --slug <slug> --pr <n>
#   idea-to-ready.sh ready --slug <slug> --pr <n>
#
# Every flag is given once, as `--flag value`. A <slug> matches ^[a-z0-9]+(-[a-z0-9]+)*$, an <n>
# ^[1-9][0-9]{0,8}$ and a <commit> is 40 or 64 lowercase hex; each is checked before any git or
# gh call. No subcommand takes free text in argv: text reaches the script only as an <inputs>
# file, `.hivemind/guide-inputs-<token>.json` (<token> 1 to 64 of [A-Za-z0-9-]), relative to the
# folder the script runs in or absolute. Each inputs file passes hivemind_inputs_path_problem
# (kind guide) and the containment guard before its one read, hivemind_read_input_file, into a
# private copy; a file that is not valid UTF-8 is refused. Once the GitHub write an inputs file
# fed has succeeded (seed's and standalone's issue, comment's post), every inputs file the
# subcommand read is deleted, so no untracked inputs file is left to make a later reviewed print
# head=dirty: only when it still passes hivemind_inputs_path_problem (kind guide), its leaf under
# the canonical start folder's .hivemind is a regular file and not a symlink, and git lists no
# index entry for it; the rm runs from inside that .hivemind after cd -P and a pwd -P re-check,
# so it never follows a symlink. When any such file is not deleted, the subcommand prints
# inputs=kept after its result line. A failure, a refusal or a write that did not succeed exits
# before the delete and keeps every inputs file for a retry. A title is one line, the ending
# newline dropped, with a non-space character and no control character; a body has a non-space
# character and no control character but newline, tab and carriage return.
#
# READS. The repository is `gh repo view`'s nameWithOwner. The trunk is one GraphQL read of
# defaultBranchRef {name target{oid}}, then `git fetch --refmap= origin refs/heads/<trunk>`,
# which writes FETCH_HEAD only; the read's commit must be the fetched tip or its ancestor, and the
# trunk commit is the fetched tip. A docs pull request is read by number; it counts only when it
# is open, its head repository is this repository, its head ref is docs/<slug> or
# docs/<slug>-<suffix> (<suffix> a slug) and its author is a User with write permission. Its head
# is fetched the same way, and a fetched tip that is not the read's head commit is
# docs-head-moved. Write permission is one `gh api repos/<owner/repo>/collaborators/<login>/
# permission` read per distinct login, admin or write being a writer. Pull request conversation
# comments are read 100 per page, at most 10 pages; more is truncated. A comment counts only when
# its first line, one ending CR removed, is a guide marker for <slug> (COMMENT MARKERS), its URL
# is this pull request's comment URL and its author is a User with write permission; any other
# comment is ignored. "Latest" is the latest createdAt. Every search or page read fails truncated
# when its pageInfo.hasNextPage is true. Every document is read at a commit only through the
# readiness check library's Document existence test (hivemind_doc_entry, hivemind_doc_read).
# Every GitHub reply and document reaches jq only on stdin; only checked values reach jq as
# --arg. Every git call carries --no-replace-objects.
#
# COMMENT MARKERS: the first line of each comment the script posts, built by the script:
#   <!-- hivemind-guide: round slug=<slug> round=<n> commit=<commit> -->
#   <!-- hivemind-guide: approval slug=<slug> commit=<commit> -->
#   <!-- hivemind-guide: review slug=<slug> commit=<commit> -->
#   <!-- hivemind-guide: veto slug=<slug> commit=<commit> -->
#
# OUTPUT CONTRACT (stdout is buffered: a failure prints none of it)
#   list     Searches open issues whose body holds `hivemind-initiative:`. For each distinct slug
#            of a first-line seed marker, sorted, prints stage's line. Then, per issue whose first
#            line starts `<!-- hivemind-initiative:` with no valid slug, prints
#            {"issue":<n>,"ignored":"seed_marker_malformed"}. Exit 0.
#   stage    Reads the trunk, then hivemind_stage_evidence_gh, then fetches the head of each
#            counting docs pull request and each docs/<slug>(-<suffix>) branch in the evidence;
#            a fetched tip other than the evidence's commit is docs-head-moved. Prints
#            hivemind_stage_derive's one JSON line unchanged. Exit 0.
#   handoff  As stage, printing hivemind_stage_handoff's one JSON line. Exit 0.
#   seed     Refuses seed-exists when an open issue by a writer has the first line
#            `<!-- hivemind-initiative: <slug> -->`. Creates the issue with `gh issue create
#            --title=<title> --body-file`, the body being that marker line, then
#            `PRD: [docs/prds/<slug>.md](https://github.com/<owner/repo>/blob/<trunk>/docs/prds/<slug>.md)`,
#            then, with --body-file, a blank line and the body. Prints issue=<n>, or
#            issue=created when gh's URL is off its shape, then deletes the inputs files it read
#            by the inputs file rule above. Exit 0.
#   standalone  Evaluates the body with hivemind_readiness_check_snapshot as an open issue with
#            no parent, at the trunk commit. When its reasons hold spec_problem_missing,
#            spec_evidence_missing, spec_scope_missing, open_questions_not_none or
#            no_acceptance_criteria, prints refused=<code> per such code, in that order, creates
#            no issue, keeps both inputs files and exits 1. Else creates the issue, prints and
#            deletes as seed does.
#   reviewed Reads the trunk and the docs pull request head. Prints head=dirty when
#            `git status --porcelain`, untracked files included, is not empty, else head=moved
#            when HEAD is not the head commit, and exits 1. Else prints reviewed=<head commit>,
#            merge_base=<merge-base of head and trunk> and previous=<commit>, the commit of the
#            latest round comment of the highest round, or previous=none. Exit 0.
#   compose  Prints the request of one guide-launched standard-delivery run. Line 1 is exactly
#            `hivemind-guide-run: <slug>`; line 2 is exactly `Docs pull request: #<n>` or
#            `Docs pull request: none`, and no other line holds `Docs pull request:`. #<n> must
#            be a counting docs pull request that is a draft (not-docs-pr, not-draft). none is
#            refused docs-pr-exists while a counting docs pull request is open, and is taken
#            only by the prototype-build, design and close-out kinds (pr-required): the run then
#            opens the docs pull request, the close-out one after the first has merged. Line 3 names
#            hivemind:standard-delivery on the script engine with draft true. Only record-pass
#            adds `Launch with local_review false.`. Then the kind's fixed lines:
#              prototype-build   a hivemind:changeling step for prototype/index.html, then a
#                                hivemind:drone step for prototype/notes.md with no Verdict.
#              prototype-refine  the approval comment URL (kept, else approval-missing or
#                                approval-stale); a changeling fold of index.html first, then
#                                a drone step writing the Verdict in the last non-record wave.
#              prototype-verdict the approval comment URL, index.html folded (else not-folded);
#                                one drone step writing the Verdict.
#              design            a drone step for the solution design and ADRs; on a UI
#                                initiative both prototype files and the approval URL.
#              round             --round and --commit; the URL of the latest round comment of
#                                that round (round-comment-missing), whose commit must be
#                                --commit (round-commit-mismatch); on a UI initiative the
#                                prototype file owners, and for round 1 the approval URL, copied
#                                under ## Decisions asked; the record wave last, naming the
#                                reviewed commit.
#              record-pass       --commit; only the record wave, verdict pass, reviewed commit.
#              review-fix        --commit; fix waves, then the record wave setting verdict fail
#                                and keeping stamps, rounds and open counts.
#              close-out         **Status:** delivered and ## As-built deltas; no record.
#            The prototype kinds need the PRD's `**UI:** yes` (not-ui). A stamping record wave,
#            record-pass or a round with no record at the head (round 1 only, else
#            record-missing), lists `<path> <blob>` per stamp read at --commit by the Document
#            existence test: the PRD, the solution design, both UI prototype files when the PRD
#            says yes at --commit, and each ADR added or modified from the merge-base of --commit
#            and the trunk to --commit; a missing path, a symlink or a submodule included, is not
#            listed. Any other record wave says to keep the stamps. --commit must be the head or
#            its ancestor (commit-not-in-pr). The request holds no comment text. Exit 0.
#   comment  Posts one comment with `gh pr comment <n> --body-file`: the marker line, then the
#            inputs file's bytes. round needs --round, --commit (the head or its ancestor) and
#            --body-file; approval and review need --body-file and mark the head commit; veto
#            takes no flag but the pull request and posts the record's `## Decisions taken,
#            listed for veto` section at the head, its heading line then its body, or `None` when
#            empty (record-missing when there is no record). Prints comment=<url>, or
#            comment=posted when gh's URL is off its shape. After the post succeeds, the
#            --body-file is deleted by the inputs file rule above. Exit 0.
#   approval Prints approval=none with no counting approval comment. Else, for the latest one,
#            approval=stale when its commit is not the head or its ancestor or index.html is
#            missing at either commit, else approval=kept then folded=yes when index.html's blob
#            differs between its commit and the head, folded=no when equal; then url=<url>.
#            Exit 0.
#   redraft  Prints draft=yes then changed=no for a draft, or runs `gh pr ready <n> --undo` and
#            prints draft=yes then changed=yes. Exit 0.
#   ready    The pull request must be a draft (not-draft). Runs hivemind_record_verify <head>
#            <merge-base> and relays each `record-verify-failed: <path>` line, exit 1. Else the
#            record at the head must meet the pass rule: record=missing, record=malformed or
#            record=not-passed, exit 1. Else, when the pull request edits the record (merge-base
#            to head), the latest counting veto comment must name the head: veto=missing or
#            veto=stale, exit 1. Only then runs `gh pr ready <n>` and prints ready=yes. Exit 0.
#
# FAILURE CONTRACT: a failure leaves stdout empty, prints exactly one stderr line
# `idea-to-ready-error: <token>` and exits 2. Tokens:
#   cannot-self-locate, cannot-resolve-shared-dir     bootstrap
#   missing-readiness-check, unparseable-readiness-check, missing-record-verify,
#   unparseable-record-verify, missing-stage-derivation, unparseable-stage-derivation,
#   missing-containment, unparseable-containment      a shared library is missing or unparseable
#   usage            unknown subcommand or flag, a repeated flag, a missing value, a malformed slug,
#                    number or kind, or a flag the subcommand or kind does not take
#   jq-missing, git-missing, gh-missing               a tool is not on PATH
#   not-a-checkout   not inside a git work tree
#   commit-malformed a <commit> is not 40 or 64 lowercase hex (no git call)
#   repo-malformed   the repository name is off its shape
#   trunk-malformed  the trunk read is off its shape or the name fails check-ref-format
#   fetch-failed     a fetch failed or its tip is unreadable
#   trunk-moved      the trunk read's commit is not the fetched tip or its ancestor
#   gh-failed        a gh call failed or its reply is off its shape
#   truncated        a search or a page read has more pages, or the comment page cap is reached
#   evidence-malformed, commit-unresolvable          relayed from the stage derivation library
#   git-failed       a git call or a document read failed
#   not-docs-pr, not-draft, docs-pr-exists, docs-head-moved, pr-required
#   seed-exists, prd-missing, prd-ui-invalid, not-ui, approval-missing, approval-stale,
#   not-folded, round-comment-missing, round-commit-mismatch, commit-not-in-pr, record-missing
#   inputs-path      an inputs path fails hivemind_inputs_path_problem
#   inputs-missing   an inputs file does not exist
#   inputs-outside   an inputs file resolves outside the checkout
#   inputs-not-utf8, inputs-unreadable, inputs-invalid
#   workdir-failed   the private work folder cannot be made
#
# P18 floor: `set -euo pipefail` before the first statement. Self-location (C1), the shared
# directory (C2) and source-or-die of each shared library (C4) follow ADR-0020's canonical forms;
# tools/test_script_bootstrap.sh pins them.

set -euo pipefail

idea_to_ready_fail() { printf 'idea-to-ready-error: %s\n' "$1" >&2; exit 2; }

script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || idea_to_ready_fail "cannot-self-locate"
shared_dir="$(CDPATH= cd -- "$script_dir/../../_shared" 2>/dev/null && pwd -P 2>/dev/null)" || idea_to_ready_fail "cannot-resolve-shared-dir"
[ -f "$shared_dir/readiness-check.sh" ] || idea_to_ready_fail "missing-readiness-check"
# shellcheck source=../../_shared/readiness-check.sh
. "$shared_dir/readiness-check.sh" || idea_to_ready_fail "unparseable-readiness-check"
[ -f "$shared_dir/record-verify.sh" ] || idea_to_ready_fail "missing-record-verify"
# shellcheck source=../../_shared/record-verify.sh
. "$shared_dir/record-verify.sh" || idea_to_ready_fail "unparseable-record-verify"
[ -f "$shared_dir/stage-derivation.sh" ] || idea_to_ready_fail "missing-stage-derivation"
# shellcheck source=../../_shared/stage-derivation.sh
. "$shared_dir/stage-derivation.sh" || idea_to_ready_fail "unparseable-stage-derivation"
[ -f "$shared_dir/containment.sh" ] || idea_to_ready_fail "missing-containment"
# shellcheck source=../../_shared/containment.sh
. "$shared_dir/containment.sh" || idea_to_ready_fail "unparseable-containment"

COMMENT_PAGE_CAP=10
# shellcheck disable=SC2016
Q_TRUNK='query IdeaToReadyTrunk($owner:String!,$name:String!){repository(owner:$owner,name:$name){defaultBranchRef{name target{oid}}}}'
# shellcheck disable=SC2016
Q_PULL_REQUEST='query IdeaToReadyPullRequest($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){number state isDraft headRefName headRefOid headRepository{nameWithOwner} author{login __typename}}}}'
# shellcheck disable=SC2016
Q_DOCS_PULLS='query IdeaToReadyDocsPulls($q:String!){search(query:$q,type:ISSUE,first:100){pageInfo{hasNextPage} nodes{... on PullRequest{number state headRefName headRepository{nameWithOwner} author{login __typename}}}}}'
# shellcheck disable=SC2016
Q_SEEDS='query IdeaToReadySeeds($q:String!){search(query:$q,type:ISSUE,first:100){pageInfo{hasNextPage} nodes{... on Issue{number state body author{login __typename}}}}}'
# shellcheck disable=SC2016
Q_COMMENTS='query IdeaToReadyComments($owner:String!,$name:String!,$number:Int!,$after:String){repository(owner:$owner,name:$name){pullRequest(number:$number){comments(first:100,after:$after){pageInfo{hasNextPage endCursor} nodes{url createdAt body author{login __typename}}}}}}'

OWNER_REPO=""
SLUG=""
PR_NUMBER=""
TOP=""
WORK_DIR=""
TRUNK_NAME=""
TRUNK_COMMIT=""
HEAD_COMMIT=""
PR_HEAD_REF=""
PR_DRAFT=""
GH_RESULT=""
FETCHED=""
COMMENT_ITEMS=""
MARKER_COMMIT=""
MARKER_URL=""
MARKER_ROUND=""
APPROVAL_STATE=""
APPROVAL_FOLDED=""
OUT=""
declare -A WRITERS=()
declare -a READ_INPUTS=()

# idea_to_ready_jq_defs: prints the constant jq definitions of the script; they need
# hivemind_readiness_jq_defs before them. Each gh filter runs on one parsed reply and gives one
# string: the read's value, "gh-failed" or "truncated".
idea_to_ready_jq_defs() {
  printf '%s\n' '
def ir_text: type == "string";
def ir_bool: type == "boolean";
def ir_hex: ir_text and test("\\A([0-9a-f]{40}|[0-9a-f]{64})\\z");
def ir_time: ir_text and test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z");
def ir_user: type == "object" and .__typename == "User" and (.login | ir_text)
  and (.login | test("\\A[A-Za-z0-9][A-Za-z0-9-]{0,38}\\z"));
def ir_data(f):
  if (.errors == null or .errors == []) and (.data | type) == "object" then .data | f
  else "gh-failed" end;
def ir_docs_ref: test("\\Adocs/" + $slug + "(-" + rc_slug + ")?\\z");
def ir_page(f):
  if type != "object" or (.pageInfo | type) != "object" or (.pageInfo.hasNextPage | ir_bool | not)
     or (.nodes | type) != "array" then "gh-failed"
  elif .pageInfo.hasNextPage then "truncated"
  else f end;
def ir_trunk:
  ir_data(.repository.defaultBranchRef
    | if type == "object" and (.name | ir_text) and (.name | test("\\A[A-Za-z0-9._/-]+\\z"))
         and (.target | type) == "object" and (.target.oid | ir_hex)
      then .name + "\t" + .target.oid
      elif type == "object" and (.target | type) == "object" and (.target.oid | ir_hex)
      then "trunk-malformed"
      else "gh-failed" end);
def ir_pull_request:
  ir_data(.repository.pullRequest
    | if type != "object" or (.number | tostring) != $number or (.state | ir_text | not)
         or (.isDraft | ir_bool | not) or (.headRefName | ir_text | not) or (.headRefOid | ir_hex | not)
         or (has("headRepository") | not) or (has("author") | not) then "gh-failed"
      elif .state == "OPEN" and (.headRepository | type) == "object"
           and .headRepository.nameWithOwner == $repo and (.headRefName | ir_docs_ref)
           and (.author | ir_user)
      then [(.isDraft | tostring), .headRefName, .headRefOid, .author.login] | join("\t")
      else "not-docs-pr" end);
def ir_docs_pulls:
  ir_data(.search | ir_page(
    [.nodes[] | select(type == "object" and .state == "OPEN" and (.headRepository | type) == "object"
                       and .headRepository.nameWithOwner == $repo and (.headRefName | ir_text)
                       and (.headRefName | ir_docs_ref) and (.author | ir_user))
     | .author.login] | unique | ["logins"] + . | join("\n")));
def ir_seeds:
  ir_data(.search | ir_page(
    if all(.nodes[]; type == "object" and (.number | type) == "number" and .number > 0
                     and has("body") and (.body == null or (.body | ir_text)))
    then [.nodes[] | (.body // "" | rc_lines) as $lines
          | {number, slug: ($lines | rc_marker_slug),
             marked: ($lines[0] // "" | startswith("<!-- hivemind-initiative:")),
             login: (if (.author | ir_user) then .author.login else null end),
             open: (.state == "OPEN")}] | tojson
    else "gh-failed" end));
def ir_permission:
  if type == "object" and (.permission | ir_text) then
    (if .permission == "admin" or .permission == "write" then "true" else "false" end)
  else "gh-failed" end;
def ir_marker:
  capture("\\A<!-- hivemind-guide: (?<kind>round|approval|review|veto) slug=(?<slug>"
    + rc_slug + ")( round=(?<round>[1-9][0-9]{0,8}))? commit=(?<commit>[0-9a-f]{40}|[0-9a-f]{64}) -->\\z");
def ir_comment_url:
  ir_text and startswith("https://github.com/" + $repo + "/pull/" + $number + "#issuecomment-")
  and test("#issuecomment-[1-9][0-9]*\\z");
def ir_comments:
  ir_data(.repository.pullRequest.comments
    | if type != "object" or (.pageInfo | type) != "object" or (.pageInfo.hasNextPage | ir_bool | not)
         or (.nodes | type) != "array" then "gh-failed"
      elif .pageInfo.hasNextPage and ((.pageInfo.endCursor | ir_text | not)
           or (.pageInfo.endCursor | test("\\A[A-Za-z0-9+/=_:-]{1,256}\\z") | not)) then "gh-failed"
      else {more: .pageInfo.hasNextPage,
            cursor: (if .pageInfo.hasNextPage then .pageInfo.endCursor else "" end),
            items: [.nodes[]
                    | select(type == "object" and (.body | ir_text) and (.url | ir_comment_url)
                             and (.createdAt | ir_time) and (.author | ir_user))
                    | . as $c
                    | [.body | rc_lines | .[0] // "" | ir_marker] | .[0] // empty
                    | select(.slug == $slug and ((.kind == "round") == (.round != null)))
                    | {kind, round: (if .round == null then null else (.round | tonumber) end),
                       commit, url: $c.url, created: $c.createdAt, login: $c.author.login}]}
        | tojson end);
def ir_record:
  [.texts | rc_front_matter]
  | if length == 0 then "malformed"
    elif (.[0] | .verdict == "pass" and all(.open[]; . == 0) and .clean_round == true
          and .rounds >= 2 and .rounds <= 3) then "pass"
    else "fail" end;
def ir_veto:
  [(.texts | rc_parse | rc_section(2; "Decisions taken, listed for veto")) // [] | .[] | .text] as $lines
  | [range(0; $lines | length) | select($lines[.] | rc_blank | not)] as $filled
  | "section\n" + (if ($filled | length) == 0 then "None"
                   else $lines[$filled[0]:$filled[-1] + 1] | join("\n") end);
def ir_controls($allowed): [explode[] | . as $c | select(($c < 32 or $c == 127) and ($allowed | index([$c]) == null))];
def ir_text_ok($title):
  if $title then
    (if endswith("\n") then .[:-1] else . end)
    | if (ir_controls([]) | length) > 0 or (test("\\S") | not) or length > 256 then "inputs-invalid"
      else "ok" end
  elif (ir_controls([9, 10, 13]) | length) > 0 or (test("\\S") | not) then "inputs-invalid"
  else "ok" end;
'
}

# require_flag_value <seen> <remaining-arg-count>: fails usage when the flag was already given or
# has no value after it.
require_flag_value() {
  if [ "$1" -ne 0 ] || [ "$2" -lt 2 ]; then
    idea_to_ready_fail usage
  fi
}

# slug_ok <slug>: 0 when <slug> matches ^[a-z0-9]+(-[a-z0-9]+)*$.
slug_ok() {
  local part='[abcdefghijklmnopqrstuvwxyz0123456789]+'
  [[ "$1" =~ ^${part}(-${part})*$ ]]
}

# number_ok <n>: 0 when <n> matches ^[1-9][0-9]{0,8}$.
number_ok() {
  [[ "$1" =~ ^[123456789][0123456789]{0,8}$ ]]
}

# require_commit <commit>: fails commit-malformed unless <commit> is 40 or 64 lowercase hex.
require_commit() {
  hivemind_readiness_commit_ok "$1" 2>/dev/null || idea_to_ready_fail commit-malformed
}

# require_tools: fails jq-missing, git-missing or gh-missing for the first tool not on PATH.
require_tools() {
  command -v jq >/dev/null 2>&1 || idea_to_ready_fail jq-missing
  command -v git >/dev/null 2>&1 || idea_to_ready_fail git-missing
  command -v gh >/dev/null 2>&1 || idea_to_ready_fail gh-missing
}

# git_run <arg>...: runs one git call with the global flags, no stdin and no stderr.
git_run() {
  git --no-replace-objects --literal-pathspecs "$@" </dev/null 2>/dev/null
}

# require_checkout: sets TOP to the work tree top level; fails not-a-checkout.
require_checkout() {
  local inside=""
  inside="$(git_run rev-parse --is-inside-work-tree)" || inside=""
  [ "$inside" = true ] || idea_to_ready_fail not-a-checkout
  TOP="$(git_run rev-parse --show-toplevel)" || idea_to_ready_fail not-a-checkout
  [ -n "$TOP" ] || idea_to_ready_fail not-a-checkout
}

# make_work_dir: makes the private work folder once and removes it on exit.
make_work_dir() {
  if [ -n "$WORK_DIR" ]; then
    return 0
  fi
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-idea-to-ready.XXXXXX" 2>/dev/null)" \
    || idea_to_ready_fail workdir-failed
  [ -n "$WORK_DIR" ] || idea_to_ready_fail workdir-failed
  trap 'rm -rf -- "$WORK_DIR" 2>/dev/null; :' EXIT
}

# gh_read <filter> <gh-arg>...: runs one gh call and the jq filter <filter> on its reply; the body
# and exit status reach jq on stdin as one framed stream. Sets GH_RESULT, or fails with the
# filter's failure token (gh-failed, truncated, trunk-malformed, not-docs-pr).
gh_read() {
  local filter="$1" result="" gh_rc=0 program
  shift
  program="$(hivemind_readiness_jq_defs)$(idea_to_ready_jq_defs)"'
[inputs] as $all
| if ($all | length) != 2 or $all[1] != 0 or ($all[0] | type) != "object" then "gh-failed"
  else $all[0] | '"$filter"' end'
  if ! result="$(
    {
      gh "$@" </dev/null 2>/dev/null || gh_rc=$?
      printf '\n%s' "$gh_rc"
    } 2>/dev/null | jq -nr --arg repo "$OWNER_REPO" --arg slug "$SLUG" --arg number "$PR_NUMBER" \
      "$program" 2>/dev/null
  )"; then
    idea_to_ready_fail gh-failed
  fi
  case "$result" in
    '' | gh-failed | truncated | trunk-malformed | not-docs-pr) idea_to_ready_fail "${result:-gh-failed}" ;;
  esac
  GH_RESULT="$result"
}

# owner_repo_ok <owner/repo>: 0 when the argument is a safe owner/repo pair.
owner_repo_ok() {
  local name_chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-'
  local pattern="^[${name_chars}]+/[${name_chars}]+\$"
  [[ "$1" =~ $pattern ]] || return 1
  case "$1" in
    -* | .* | */-* | */.* | *..*) return 1 ;;
  esac
}

# resolve_repo: sets OWNER_REPO from `gh repo view`; fails gh-failed or repo-malformed.
resolve_repo() {
  local name=""
  name="$(gh repo view --json nameWithOwner --jq .nameWithOwner </dev/null 2>/dev/null)" \
    || idea_to_ready_fail gh-failed
  owner_repo_ok "$name" || idea_to_ready_fail repo-malformed
  OWNER_REPO="$name"
}

# fetch_ref <branch>: fetches refs/heads/<branch> from origin into FETCH_HEAD only and sets
# FETCHED to the fetched tip; fails fetch-failed.
fetch_ref() {
  local tip=""
  GIT_TERMINAL_PROMPT=0 git --no-replace-objects fetch --quiet --no-tags --no-recurse-submodules \
    --no-prune --refmap= -- origin "refs/heads/$1" </dev/null >/dev/null 2>&1 \
    || idea_to_ready_fail fetch-failed
  tip="$(git_run rev-parse --verify --quiet 'FETCH_HEAD^{commit}')" || idea_to_ready_fail fetch-failed
  hivemind_readiness_commit_ok "$tip" 2>/dev/null || idea_to_ready_fail fetch-failed
  FETCHED="$tip"
}

# is_ancestor <ancestor> <commit>: 0 when <ancestor> is <commit> or its ancestor, 1 when not or
# when <ancestor> names no commit object; fails git-failed on any other git failure.
is_ancestor() {
  local object_type="" rc=0
  object_type="$(git_run cat-file -t "$1")" || object_type=""
  if [ "$object_type" != commit ]; then
    return 1
  fi
  git_run merge-base --is-ancestor "$1" "$2" || rc=$?
  case "$rc" in
    0 | 1) return "$rc" ;;
  esac
  idea_to_ready_fail git-failed
}

# read_trunk <fetch:yes|no>: reads the trunk's name and commit; with yes, fetches it and sets
# TRUNK_COMMIT to the fetched tip, which the read's commit must be or descend from.
read_trunk() {
  local read_oid=""
  gh_read ir_trunk api graphql -f "query=$Q_TRUNK" -f "owner=${OWNER_REPO%%/*}" -f "name=${OWNER_REPO#*/}"
  TRUNK_NAME="${GH_RESULT%%$'\t'*}"
  read_oid="${GH_RESULT#*$'\t'}"
  case "$TRUNK_NAME" in
    -* | *..*) idea_to_ready_fail trunk-malformed ;;
  esac
  git --no-replace-objects check-ref-format --branch "$TRUNK_NAME" </dev/null >/dev/null 2>&1 || idea_to_ready_fail trunk-malformed
  if [ "$1" = no ]; then
    return 0
  fi
  fetch_ref "$TRUNK_NAME"
  is_ancestor "$read_oid" "$FETCHED" || idea_to_ready_fail trunk-moved
  TRUNK_COMMIT="$FETCHED"
}

# writer_check <login>: sets WRITER to true or false from one permission read per login.
writer_check() {
  if [ -z "${WRITERS[$1]-}" ]; then
    gh_read ir_permission api "repos/$OWNER_REPO/collaborators/$1/permission"
    WRITERS[$1]="$GH_RESULT"
  fi
  WRITER="${WRITERS[$1]}"
}

# read_pr: reads pull request PR_NUMBER, fails not-docs-pr unless it is a counting docs pull
# request of SLUG, fetches its head (docs-head-moved) and sets PR_DRAFT, PR_HEAD_REF and
# HEAD_COMMIT.
read_pr() {
  local fields="" head_oid="" login=""
  gh_read ir_pull_request api graphql -f "query=$Q_PULL_REQUEST" -f "owner=${OWNER_REPO%%/*}" \
    -f "name=${OWNER_REPO#*/}" -F "number=$PR_NUMBER"
  fields="$GH_RESULT"
  IFS=$'\t' read -r PR_DRAFT PR_HEAD_REF head_oid login <<<"$fields"
  writer_check "$login"
  [ "$WRITER" = true ] || idea_to_ready_fail not-docs-pr
  fetch_ref "$PR_HEAD_REF"
  [ "$FETCHED" = "$head_oid" ] || idea_to_ready_fail docs-head-moved
  HEAD_COMMIT="$head_oid"
}

# require_no_docs_pr: fails docs-pr-exists while an open counting docs pull request of SLUG exists.
require_no_docs_pr() {
  local logins="" login=""
  local -a login_list=()
  gh_read ir_docs_pulls api graphql -f "query=$Q_DOCS_PULLS" \
    -f "q=repo:$OWNER_REPO is:pr is:open head:docs/$SLUG"
  logins="${GH_RESULT#logins}"
  mapfile -t login_list <<<"$logins"
  for login in "${login_list[@]}"; do
    if [ -n "$login" ]; then
      writer_check "$login"
      [ "$WRITER" = false ] || idea_to_ready_fail docs-pr-exists
    fi
  done
}

# read_comments: reads every conversation comment page of PR_NUMBER and sets COMMENT_ITEMS to the
# marker comments of SLUG, one JSON object per line; fails truncated past the page cap.
read_comments() {
  local page=0 after="" more="" items=""
  local -a cursor_args=()
  COMMENT_ITEMS=""
  while :; do
    page=$((page + 1))
    cursor_args=()
    if [ -n "$after" ]; then
      cursor_args=(-f "after=$after")
    fi
    gh_read ir_comments api graphql -f "query=$Q_COMMENTS" -f "owner=${OWNER_REPO%%/*}" \
      -f "name=${OWNER_REPO#*/}" -F "number=$PR_NUMBER" "${cursor_args[@]}"
    more="$(printf '%s\n' "$GH_RESULT" | jq -r '.more' 2>/dev/null)" || idea_to_ready_fail gh-failed
    after="$(printf '%s\n' "$GH_RESULT" | jq -r '.cursor' 2>/dev/null)" || idea_to_ready_fail gh-failed
    items="$(printf '%s\n' "$GH_RESULT" | jq -c '.items[]' 2>/dev/null)" || idea_to_ready_fail gh-failed
    COMMENT_ITEMS+="$items${items:+$'\n'}"
    if [ "$more" != true ]; then
      return 0
    fi
    if [ "$page" -ge "$COMMENT_PAGE_CAP" ]; then
      idea_to_ready_fail truncated
    fi
  done
}

# latest_marker <kind> [<round>|highest]: picks, from COMMENT_ITEMS, the latest comment of <kind>
# (of round <round>, or of the highest round) whose author is a writer, and sets MARKER_COMMIT,
# MARKER_URL and MARKER_ROUND, each empty when there is none.
latest_marker() {
  local kind="$1" round="${2-}" logins="" login="" writers="" picked=""
  local -a login_list=()
  MARKER_COMMIT=""
  MARKER_URL=""
  MARKER_ROUND=""
  logins="$(printf '%s' "$COMMENT_ITEMS" | jq -r --arg kind "$kind" 'select(.kind == $kind) | .login' \
    2>/dev/null | LC_ALL=C sort -u)" || idea_to_ready_fail gh-failed
  mapfile -t login_list <<<"$logins"
  for login in "${login_list[@]}"; do
    if [ -n "$login" ]; then
      writer_check "$login"
      if [ "$WRITER" = true ]; then
        writers+="$login"$'\n'
      fi
    fi
  done
  picked="$(printf '%s' "$COMMENT_ITEMS" | jq -rs --arg kind "$kind" --arg round "$round" \
    --arg writers "$writers" '
    ($writers | split("\n")) as $names
    | [.[] | select(.kind == $kind and (.login as $l | $names | index([$l]) != null))
       | select($round == "" or $round == "highest" or (.round | tostring) == $round)]
    | if $round == "highest" then sort_by(.round, .created) else sort_by(.created) end
    | last // empty | "\(.commit)\t\(.url)\t\(.round // "")"' 2>/dev/null)" \
    || idea_to_ready_fail gh-failed
  if [ -n "$picked" ]; then
    IFS=$'\t' read -r MARKER_COMMIT MARKER_URL MARKER_ROUND <<<"$picked"
  fi
}

# read_doc_filter <commit> <path> <filter>: streams the line <path>, the document's bytes and its
# hivemind_doc_read status into one jq program running rc_doc_eval(<filter>) and prints its
# output: `missing` for a missing document, else the filter's text. Returns 2 on a failure.
read_doc_filter() {
  local commit="$1" path="$2" read_rc=0 output="" program
  program="$(hivemind_readiness_jq_defs)$(idea_to_ready_jq_defs)rc_doc_eval($3)"
  if ! output="$(
    {
      printf '%s\n' "$path"
      hivemind_doc_read "$commit" "$path" 2>/dev/null || read_rc=$?
      printf '\n%s' "$read_rc"
    } | jq -Rsr --arg repo "" --arg slug "" --arg number "" "$program" 2>/dev/null
  )"; then
    return 2
  fi
  if [ "$output" = failed ]; then
    return 2
  fi
  printf '%s\n' "$output"
}

# read_ui <commit>: sets UI to yes or no from the PRD at <commit>; fails prd-missing or
# prd-ui-invalid.
read_ui() {
  UI="$(read_doc_filter "$1" "docs/prds/$SLUG.md" rc_prd_ui)" || idea_to_ready_fail git-failed
  case "$UI" in
    yes | no) ;;
    missing) idea_to_ready_fail prd-missing ;;
    *) idea_to_ready_fail prd-ui-invalid ;;
  esac
}

# read_record <commit>: sets RECORD to missing, malformed, pass or fail for the review record at
# <commit>.
read_record() {
  RECORD="$(read_doc_filter "$1" "docs/initiatives/$SLUG/review-record.md" ir_record)" \
    || idea_to_ready_fail git-failed
}

# merge_base_of <commit> <trunk>: sets MERGE_BASE; fails git-failed.
merge_base_of() {
  MERGE_BASE="$(git_run merge-base "$1" "$2")" || idea_to_ready_fail git-failed
  hivemind_readiness_commit_ok "$MERGE_BASE" 2>/dev/null || idea_to_ready_fail git-failed
}

# approval_state: sets APPROVAL_STATE (none, stale or kept), APPROVAL_FOLDED (yes or no when kept)
# and MARKER_URL from the latest counting approval comment and HEAD_COMMIT; needs COMMENT_ITEMS.
approval_state() {
  local marked_rc=0 head_rc=0 marked_blob="" head_blob=""
  local index="docs/initiatives/$SLUG/prototype/index.html"
  APPROVAL_FOLDED=""
  latest_marker approval
  if [ -z "$MARKER_COMMIT" ]; then
    APPROVAL_STATE=none
    return 0
  fi
  if ! is_ancestor "$MARKER_COMMIT" "$HEAD_COMMIT"; then
    APPROVAL_STATE=stale
    return 0
  fi
  marked_blob="$(hivemind_doc_entry "$MARKER_COMMIT" "$index" 2>/dev/null)" || marked_rc=$?
  head_blob="$(hivemind_doc_entry "$HEAD_COMMIT" "$index" 2>/dev/null)" || head_rc=$?
  if [ "$marked_rc" -ge 2 ] || [ "$head_rc" -ge 2 ]; then
    idea_to_ready_fail git-failed
  fi
  if [ "$marked_rc" -ne 0 ] || [ "$head_rc" -ne 0 ]; then
    APPROVAL_STATE=stale
    return 0
  fi
  APPROVAL_STATE=kept
  if [ "$marked_blob" = "$head_blob" ]; then
    APPROVAL_FOLDED=no
  else
    APPROVAL_FOLDED=yes
  fi
}

# read_guide_input <path-arg> <copy> <title|body>: checks the inputs path, guards it, reads it
# once into <copy>, checks its text and adds <path-arg> to READ_INPUTS.
read_guide_input() {
  local INPUTS_FILE="" read_rc=0 verdict=""
  hivemind_inputs_path_problem "$START_DIR" "$1" guide >/dev/null 2>&1 || idea_to_ready_fail inputs-path
  case "$1" in
    /*) INPUTS_FILE="$1" ;;
    *) INPUTS_FILE="$START_DIR/$1" ;;
  esac
  [ -f "$INPUTS_FILE" ] || idea_to_ready_fail inputs-missing
  hivemind_assert_inputs_contained "$TOP" "$INPUTS_FILE" >/dev/null 2>&1 || idea_to_ready_fail inputs-outside
  hivemind_read_input_file "$INPUTS_FILE" "$2" || read_rc=$?
  case "$read_rc" in
    0) ;;
    2) idea_to_ready_fail inputs-not-utf8 ;;
    *) idea_to_ready_fail inputs-unreadable ;;
  esac
  verdict="$(jq -Rsr --argjson title "$([ "$3" = title ] && printf true || printf false)" \
    --arg repo "" --arg slug "" --arg number "" \
    "$(hivemind_readiness_jq_defs)$(idea_to_ready_jq_defs)ir_text_ok(\$title)" <"$2" 2>/dev/null)" \
    || idea_to_ready_fail inputs-unreadable
  [ "$verdict" = ok ] || idea_to_ready_fail inputs-invalid
  READ_INPUTS+=("$1")
}

# create_issue <title-copy> <body-file>: creates the issue and appends issue=<n> to OUT.
create_issue() {
  local title="" url="" number=""
  title="$(cat -- "$1" && printf .)" || idea_to_ready_fail inputs-unreadable
  title="${title%.}"
  title="${title%$'\n'}"
  url="$(gh issue create --repo "$OWNER_REPO" --title="$title" --body-file "$2" </dev/null 2>/dev/null)" \
    || idea_to_ready_fail gh-failed
  number="${url#"https://github.com/$OWNER_REPO/issues/"}"
  if [ "$number" != "$url" ] && number_ok "$number"; then
    OUT+="issue=$number"$'\n'
  else
    OUT+="issue=created"$'\n'
  fi
}

# remove_guide_input <path-arg>: deletes the inputs file the caller read from <path-arg>, by the
# inputs file rule of the header. Returns 0 when it deleted the file and 1 when the file is kept.
remove_guide_input() {
  local canon_start="" canon_hivemind="" leaf="${1##*/}" tracked=""
  hivemind_inputs_path_problem "$START_DIR" "$1" guide >/dev/null 2>&1 || return 1
  canon_start="$(hivemind_canon_root "$START_DIR")" || return 1
  canon_hivemind="${canon_start%/}/.hivemind"
  if [ -L "$canon_hivemind/$leaf" ] || [ ! -f "$canon_hivemind/$leaf" ]; then
    return 1
  fi
  tracked="$(git_run -C "$canon_start" ls-files --cached -- ".hivemind/$leaf")" || return 1
  [ -z "$tracked" ] || return 1
  (
    CDPATH='' cd -P -- "$canon_hivemind" 2>/dev/null || exit 1
    [ "$(pwd -P)" = "$canon_hivemind" ] || exit 1
    if [ -L "./$leaf" ] || [ ! -f "./$leaf" ]; then exit 1; fi
    rm -f -- "./$leaf" 2>/dev/null
  )
}

# remove_read_inputs: runs once the GitHub write the inputs files fed has succeeded. Deletes each
# file of READ_INPUTS once per leaf with remove_guide_input and appends inputs=kept to OUT when
# any is kept.
remove_read_inputs() {
  local path_arg="" leaf="" kept=0
  local -A seen_leaves=()
  for path_arg in "${READ_INPUTS[@]}"; do
    leaf="${path_arg##*/}"
    if [ -z "${seen_leaves[$leaf]-}" ]; then
      seen_leaves[$leaf]=1
      remove_guide_input "$path_arg" || kept=1
    fi
  done
  if [ "$kept" -eq 1 ]; then
    OUT+="inputs=kept"$'\n'
  fi
}

# post_comment <body-file>: posts the comment and appends comment=<url> to OUT.
post_comment() {
  local url="" suffix=""
  url="$(gh pr comment "$PR_NUMBER" --repo "$OWNER_REPO" --body-file "$1" </dev/null 2>/dev/null)" \
    || idea_to_ready_fail gh-failed
  url="${url%$'\n'}"
  suffix="${url#"https://github.com/$OWNER_REPO/pull/$PR_NUMBER#issuecomment-"}"
  if [ "$suffix" != "$url" ] && [[ "$suffix" =~ ^[123456789][0123456789]*$ ]]; then
    OUT+="comment=$url"$'\n'
  else
    OUT+="comment=posted"$'\n'
  fi
}

# parse_pr_flags <arg>...: parses exactly --slug and --pr <n> (no none).
parse_pr_flags() {
  local have_slug=0 have_pr=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --slug) require_flag_value "$have_slug" "$#"; SLUG="$2"; have_slug=1; shift 2 ;;
      --pr) require_flag_value "$have_pr" "$#"; PR_NUMBER="$2"; have_pr=1; shift 2 ;;
      *) idea_to_ready_fail usage ;;
    esac
  done
  if [ "$have_slug" -eq 0 ] || [ "$have_pr" -eq 0 ] || ! slug_ok "$SLUG" || ! number_ok "$PR_NUMBER"; then
    idea_to_ready_fail usage
  fi
}

# parse_slug_flag <arg>...: parses exactly --slug.
parse_slug_flag() {
  local have_slug=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --slug) require_flag_value "$have_slug" "$#"; SLUG="$2"; have_slug=1; shift 2 ;;
      *) idea_to_ready_fail usage ;;
    esac
  done
  if [ "$have_slug" -eq 0 ] || ! slug_ok "$SLUG"; then
    idea_to_ready_fail usage
  fi
}

# relay_stage_error <output>: fails with the stage derivation library's token.
relay_stage_error() {
  local token="${1#stage-derivation-error: }"
  case "$token" in
    truncated | gh-failed | git-failed | evidence-malformed | commit-unresolvable) idea_to_ready_fail "$token" ;;
  esac
  idea_to_ready_fail git-failed
}

# derive_slug <derive|handoff>: reads SLUG's evidence, fetches its docs heads and appends the
# library's line to OUT. Needs OWNER_REPO, TRUNK_NAME and TRUNK_COMMIT.
derive_slug() {
  local evidence="" heads="" line="" ref="" oid="" result="" rc=0
  local -a head_lines=()
  evidence="$(hivemind_stage_evidence_gh "$OWNER_REPO" "$SLUG" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    relay_stage_error "$evidence"
  fi
  heads="$(printf '%s\n' "$evidence" | jq -r --arg repo "$OWNER_REPO" --arg slug "$SLUG" \
    --arg number "" "$(hivemind_readiness_jq_defs)$(idea_to_ready_jq_defs)"'
    [(.pull_requests[] | select(.head_repository == $repo and .author_can_write
                               and (.head_ref | ir_docs_ref)) | [.head_ref, .head_oid]),
     (.branches[] | select(.name | ir_docs_ref) | [.name, .oid])] | unique | .[] | @tsv' 2>/dev/null)" \
    || idea_to_ready_fail evidence-malformed
  mapfile -t head_lines <<<"$heads"
  for line in "${head_lines[@]}"; do
    if [ -n "$line" ]; then
      IFS=$'\t' read -r ref oid <<<"$line"
      fetch_ref "$ref"
      [ "$FETCHED" = "$oid" ] || idea_to_ready_fail docs-head-moved
    fi
  done
  rc=0
  if [ "$1" = derive ]; then
    result="$(printf '%s\n' "$evidence" | hivemind_stage_derive "$TRUNK_COMMIT" "$OWNER_REPO" "$TRUNK_NAME" "$SLUG" 2>&1)" || rc=$?
  else
    result="$(printf '%s\n' "$evidence" | hivemind_stage_handoff "$TRUNK_COMMIT" "$OWNER_REPO" "$TRUNK_NAME" "$SLUG" 2>&1)" || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    relay_stage_error "$result"
  fi
  OUT+="$result"$'\n'
}

# run_stage <derive|handoff> <arg>...: the stage and handoff subcommands.
run_stage() {
  local mode="$1"
  shift
  parse_slug_flag "$@"
  require_tools
  require_checkout
  resolve_repo
  read_trunk yes
  derive_slug "$mode"
  printf '%s' "$OUT"
}

# run_list <arg>...: the list subcommand.
run_list() {
  local seeds="" slugs="" ignored="" slug=""
  local -a slug_list=()
  if [ "$#" -ne 0 ]; then
    idea_to_ready_fail usage
  fi
  require_tools
  require_checkout
  resolve_repo
  read_trunk yes
  gh_read ir_seeds api graphql -f "query=$Q_SEEDS" -f "q=repo:$OWNER_REPO is:issue is:open in:body \"hivemind-initiative:\""
  seeds="$GH_RESULT"
  slugs="$(printf '%s\n' "$seeds" | jq -r '[.[] | select(.open and .slug != null) | .slug] | unique | .[]' 2>/dev/null)" \
    || idea_to_ready_fail gh-failed
  ignored="$(printf '%s\n' "$seeds" | jq -c '.[] | select(.open and .slug == null and .marked)
    | {issue: .number, ignored: "seed_marker_malformed"}' 2>/dev/null)" || idea_to_ready_fail gh-failed
  mapfile -t slug_list <<<"$slugs"
  for slug in "${slug_list[@]}"; do
    if [ -n "$slug" ]; then
      SLUG="$slug"
      derive_slug derive
    fi
  done
  OUT+="$ignored${ignored:+$'\n'}"
  printf '%s' "$OUT"
}

# parse_issue_flags <need-slug:yes|no> <arg>...: parses --slug (when yes), --title-file and
# --body-file into SLUG, TITLE_ARG and BODY_ARG.
parse_issue_flags() {
  local need_slug="$1" have_slug=0 have_title=0 have_body=0
  shift
  TITLE_ARG=""
  BODY_ARG=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --slug)
        [ "$need_slug" = yes ] || idea_to_ready_fail usage
        require_flag_value "$have_slug" "$#"; SLUG="$2"; have_slug=1; shift 2 ;;
      --title-file) require_flag_value "$have_title" "$#"; TITLE_ARG="$2"; have_title=1; shift 2 ;;
      --body-file) require_flag_value "$have_body" "$#"; BODY_ARG="$2"; have_body=1; shift 2 ;;
      *) idea_to_ready_fail usage ;;
    esac
  done
  if [ "$have_title" -eq 0 ]; then
    idea_to_ready_fail usage
  fi
  if [ "$need_slug" = yes ] && { [ "$have_slug" -eq 0 ] || ! slug_ok "$SLUG"; }; then
    idea_to_ready_fail usage
  fi
  if [ "$need_slug" = no ] && [ "$have_body" -eq 0 ]; then
    idea_to_ready_fail usage
  fi
}

# run_seed <arg>...: the seed subcommand.
run_seed() {
  local seeds="" logins="" login="" body_file=""
  local -a login_list=()
  parse_issue_flags yes "$@"
  require_tools
  require_checkout
  make_work_dir
  read_guide_input "$TITLE_ARG" "$WORK_DIR/title.txt" title
  if [ -n "$BODY_ARG" ]; then
    read_guide_input "$BODY_ARG" "$WORK_DIR/body.txt" body
  fi
  resolve_repo
  read_trunk no
  gh_read ir_seeds api graphql -f "query=$Q_SEEDS" \
    -f "q=repo:$OWNER_REPO is:issue is:open in:body \"hivemind-initiative: $SLUG\""
  seeds="$GH_RESULT"
  logins="$(printf '%s\n' "$seeds" | jq -r --arg slug "$SLUG" \
    '[.[] | select(.open and .slug == $slug and .login != null) | .login] | unique | .[]' 2>/dev/null)" \
    || idea_to_ready_fail gh-failed
  mapfile -t login_list <<<"$logins"
  for login in "${login_list[@]}"; do
    if [ -n "$login" ]; then
      writer_check "$login"
      [ "$WRITER" = false ] || idea_to_ready_fail seed-exists
    fi
  done
  body_file="$WORK_DIR/issue-body.md"
  {
    printf '<!-- hivemind-initiative: %s -->\n' "$SLUG"
    printf 'PRD: [docs/prds/%s.md](https://github.com/%s/blob/%s/docs/prds/%s.md)\n' \
      "$SLUG" "$OWNER_REPO" "$TRUNK_NAME" "$SLUG"
    if [ -n "$BODY_ARG" ]; then
      printf '\n'
      cat -- "$WORK_DIR/body.txt"
    fi
  } >"$body_file" || idea_to_ready_fail workdir-failed
  create_issue "$WORK_DIR/title.txt" "$body_file"
  remove_read_inputs
  printf '%s' "$OUT"
}

# run_standalone <arg>...: the standalone subcommand.
run_standalone() {
  local snapshot="" result="" refused="" rc=0
  parse_issue_flags no "$@"
  require_tools
  require_checkout
  make_work_dir
  read_guide_input "$TITLE_ARG" "$WORK_DIR/title.txt" title
  read_guide_input "$BODY_ARG" "$WORK_DIR/body.txt" body
  resolve_repo
  read_trunk yes
  snapshot="$(jq -Rsc '[{number: 1, state: "OPEN", body: .,
    labels: {nodes: [], pageInfo: {hasNextPage: false}},
    blockedBy: {nodes: [], pageInfo: {hasNextPage: false}},
    subIssues: {totalCount: 0, pageInfo: {hasNextPage: false}}, parent: null}]' \
    <"$WORK_DIR/body.txt" 2>/dev/null)" || idea_to_ready_fail inputs-unreadable
  result="$(printf '%s\n' "$snapshot" \
    | hivemind_readiness_check_snapshot "$TRUNK_COMMIT" "$OWNER_REPO" "$TRUNK_NAME" 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] || idea_to_ready_fail git-failed
  refused="$(printf '%s\n' "$result" | jq -r '.reasons as $r
    | ["spec_problem_missing", "spec_evidence_missing", "spec_scope_missing",
       "open_questions_not_none", "no_acceptance_criteria"][]
    | select(. as $c | $r | index([$c]) != null) | "refused=" + .' 2>/dev/null)" \
    || idea_to_ready_fail git-failed
  if [ -n "$refused" ]; then
    printf '%s\n' "$refused"
    exit 1
  fi
  create_issue "$WORK_DIR/title.txt" "$WORK_DIR/body.txt"
  remove_read_inputs
  printf '%s' "$OUT"
}

# run_reviewed <arg>...: the reviewed subcommand.
run_reviewed() {
  local status="" current=""
  parse_pr_flags "$@"
  require_tools
  require_checkout
  resolve_repo
  read_trunk yes
  read_pr
  status="$(git --no-optional-locks --no-replace-objects status --porcelain --untracked-files=all \
    </dev/null 2>/dev/null)" || idea_to_ready_fail git-failed
  if [ -n "$status" ]; then
    printf 'head=dirty\n'
    exit 1
  fi
  current="$(git_run rev-parse --verify --quiet HEAD)" || current=""
  if [ "$current" != "$HEAD_COMMIT" ]; then
    printf 'head=moved\n'
    exit 1
  fi
  merge_base_of "$HEAD_COMMIT" "$TRUNK_COMMIT"
  read_comments
  latest_marker round highest
  printf 'reviewed=%s\nmerge_base=%s\nprevious=%s\n' "$HEAD_COMMIT" "$MERGE_BASE" "${MARKER_COMMIT:-none}"
}

# adr_paths <base> <commit>: prints each ADR path added or modified from <base> to <commit>,
# sorted; returns 2 on a failure.
adr_paths() {
  local record="" git_rc=0 index=0 count=0 lines=""
  local -a records=()
  while IFS= read -r -d '' record; do
    records+=("$record")
  done < <(
    git -C "$TOP" --no-replace-objects --literal-pathspecs -c diff.relative=false \
      -c core.quotePath=true diff --no-renames --no-ext-diff --no-textconv --no-color \
      --name-status -z "$1" "$2" -- docs/adr/ </dev/null 2>/dev/null || git_rc=$?
    printf '%s\0' "$git_rc"
  )
  count="${#records[@]}"
  if [ "$count" -eq 0 ] || [ "${records[count - 1]}" != 0 ] || [ $(((count - 1) % 2)) -ne 0 ]; then
    return 2
  fi
  for ((index = 0; index < count - 1; index += 2)); do
    case "${records[index]}" in
      A | M)
        if [ "$(hivemind_readiness_path_kind "${records[index + 1]}" 2>/dev/null)" = adr ]; then
          lines+="${records[index + 1]}"$'\n'
        fi
        ;;
    esac
  done
  if [ -n "$lines" ]; then
    printf '%s' "$lines" | LC_ALL=C sort
  fi
}

# stamp_lines <commit>: sets STAMPS to one `<path> <blob>` line per stamp read at <commit>.
stamp_lines() {
  local commit="$1" path="" blob="" entry_rc=0 adrs=""
  local folder="docs/initiatives/$SLUG"
  local -a paths=("docs/prds/$SLUG.md" "$folder/solution-design.md") adr_list=()
  read_ui "$commit"
  if [ "$UI" = yes ]; then
    paths+=("$folder/prototype/index.html" "$folder/prototype/notes.md")
  fi
  merge_base_of "$commit" "$TRUNK_COMMIT"
  adrs="$(adr_paths "$MERGE_BASE" "$commit")" || idea_to_ready_fail git-failed
  mapfile -t adr_list <<<"$adrs"
  for path in "${adr_list[@]}"; do
    if [ -n "$path" ]; then
      paths+=("$path")
    fi
  done
  STAMPS=""
  for path in "${paths[@]}"; do
    entry_rc=0
    blob="$(hivemind_doc_entry "$commit" "$path" 2>/dev/null)" || entry_rc=$?
    case "$entry_rc" in
      0) STAMPS+="$path $blob"$'\n' ;;
      1) ;;
      *) idea_to_ready_fail git-failed ;;
    esac
  done
}

# compose_flags_ok <kind> <have-commit> <have-round>: fails usage when the kind does not take, or
# lacks, --commit or --round.
compose_flags_ok() {
  local need_commit=0 need_round=0
  case "$1" in
    round) need_commit=1; need_round=1 ;;
    record-pass | review-fix) need_commit=1 ;;
    prototype-build | prototype-refine | prototype-verdict | design | close-out) ;;
    *) idea_to_ready_fail usage ;;
  esac
  if [ "$2" -ne "$need_commit" ] || [ "$3" -ne "$need_round" ]; then
    idea_to_ready_fail usage
  fi
}

# compose_ui_owner_line: appends the UI prototype file owner rule of a fix run to OUT.
compose_ui_owner_line() {
  OUT+="A fix to docs/initiatives/$SLUG/prototype/index.html is a hivemind:changeling step with exact file scope; a fix to docs/initiatives/$SLUG/prototype/notes.md is a hivemind:drone step with exact file scope."$'\n'
}

# compose_stamp_lines <commit>: appends the stamp list of a stamping record wave to OUT.
compose_stamp_lines() {
  stamp_lines "$1"
  OUT+="Write exactly these stamps in the record's front matter, path then blob id, in this order:"$'\n'
  OUT+="$STAMPS"
}

# compose_kind_lines <kind> <commit> <round>: appends the kind's fixed lines to OUT.
compose_kind_lines() {
  local kind="$1" commit="$2" round="$3" folder="docs/initiatives/$SLUG" approval_url=""
  case "$kind" in
    prototype-build)
      OUT+="UI prototype build run for docs/prds/$SLUG.md."$'\n'
      OUT+="Step 1: a hivemind:changeling step with exact file scope writes $folder/prototype/index.html with 3 to 5 structurally different variants behind the ?variant= switcher, with stub data only."$'\n'
      OUT+="Step 2, after step 1: a hivemind:drone step with exact file scope writes $folder/prototype/notes.md with one ## Variant <key>: <name> section per variant and no ## Verdict section."$'\n'
      OUT+="This run writes no review record."$'\n'
      ;;
    prototype-refine)
      approval_state
      [ "$APPROVAL_STATE" != none ] || idea_to_ready_fail approval-missing
      [ "$APPROVAL_STATE" = kept ] || idea_to_ready_fail approval-stale
      OUT+="UI prototype refinement run. The maintainer's approval is comment $MARKER_URL; the maintainer's feedback and verdict follow this wording."$'\n'
      OUT+="Step 1: a hivemind:changeling step with exact file scope folds the verdict into one approved variant in $folder/prototype/index.html, which then holds only that variant."$'\n'
      OUT+="Step 2, in the run's last non-record wave, after step 1: a hivemind:drone step with exact file scope writes the feedback and a filled ## Verdict section into $folder/prototype/notes.md."$'\n'
      OUT+="This run writes no review record."$'\n'
      ;;
    prototype-verdict)
      approval_state
      [ "$APPROVAL_STATE" != none ] || idea_to_ready_fail approval-missing
      [ "$APPROVAL_STATE" = kept ] || idea_to_ready_fail approval-stale
      [ "$APPROVAL_FOLDED" = yes ] || idea_to_ready_fail not-folded
      OUT+="UI prototype verdict run: $folder/prototype/index.html already holds the one approved variant. The maintainer's approval is comment $MARKER_URL."$'\n'
      OUT+="Step 1: a hivemind:drone step with exact file scope writes the feedback and a filled ## Verdict section into $folder/prototype/notes.md, from the approval comment's text after its first line."$'\n'
      OUT+="No step edits $folder/prototype/index.html."$'\n'
      OUT+="This run writes no review record."$'\n'
      ;;
    design)
      OUT+="Solution design run for docs/prds/$SLUG.md."$'\n'
      OUT+="A hivemind:drone step with exact file scope writes $folder/solution-design.md with every section of the solution design template, and each design-stage ADR under docs/adr/."$'\n'
      if [ "${UI-}" = yes ]; then
        approval_state
        [ "$APPROVAL_STATE" != none ] || idea_to_ready_fail approval-missing
        [ "$APPROVAL_STATE" = kept ] || idea_to_ready_fail approval-stale
        OUT+="The design cites the approved UI prototype, $folder/prototype/index.html and $folder/prototype/notes.md, approved in comment $MARKER_URL; no step edits either file."$'\n'
      fi
      OUT+="This run writes no review record."$'\n'
      ;;
    round)
      if [ "$UI" = yes ] && [ "$round" = 1 ]; then
        approval_state
        [ "$APPROVAL_STATE" != none ] || idea_to_ready_fail approval-missing
        [ "$APPROVAL_STATE" = kept ] || idea_to_ready_fail approval-stale
        approval_url="$MARKER_URL"
      fi
      latest_marker round "$round"
      [ -n "$MARKER_URL" ] || idea_to_ready_fail round-comment-missing
      [ "$MARKER_COMMIT" = "$commit" ] || idea_to_ready_fail round-commit-mismatch
      OUT+="Design review round $round fix run. The round's findings and record update are comment $MARKER_URL."$'\n'
      OUT+="Fix each finding of that comment in the solution design, the PRD, an ADR or the UI prototype, or give it the disposition that comment names."$'\n'
      if [ "$UI" = yes ]; then
        compose_ui_owner_line
      fi
      OUT+="The last wave is the record wave: a hivemind:drone step with exact file scope writes $folder/review-record.md for round $round, reviewed commit $commit."$'\n'
      if [ "$RECORD" = missing ]; then
        compose_stamp_lines "$commit"
      else
        OUT+="Keep the record's stamps unchanged."$'\n'
      fi
      if [ -n "$approval_url" ]; then
        OUT+="Copy the maintainer's approval in comment $approval_url, its text after its first line, word for word under ## Decisions asked."$'\n'
      fi
      ;;
    record-pass)
      OUT+="Record pass run: this run carries only the record wave."$'\n'
      OUT+="A hivemind:drone step with exact file scope writes $folder/review-record.md with verdict pass and clean_round true, reviewed commit $commit."$'\n'
      compose_stamp_lines "$commit"
      ;;
    review-fix)
      OUT+="Review fix run after the design review exited. The fix is named in the docs pull request's review comments."$'\n'
      if [ "$UI" = yes ]; then
        compose_ui_owner_line
      fi
      OUT+="The last wave is the record wave: a hivemind:drone step with exact file scope writes $folder/review-record.md with verdict fail and clean_round false, keeping rounds and the open counts, reviewed commit $commit."$'\n'
      OUT+="Keep the record's stamps unchanged."$'\n'
      ;;
    close-out)
      OUT+="Close-out run: a hivemind:drone step with exact file scope adds **Status:** delivered as the first line after the title of $folder/solution-design.md and an ## As-built deltas section."$'\n'
      OUT+="This run writes no review record."$'\n'
      ;;
  esac
}

# run_compose <arg>...: the compose subcommand.
run_compose() {
  local kind="" pr_arg="" commit="" round="" have_kind=0 have_slug=0 have_pr=0 have_commit=0 have_round=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --kind) require_flag_value "$have_kind" "$#"; kind="$2"; have_kind=1; shift 2 ;;
      --slug) require_flag_value "$have_slug" "$#"; SLUG="$2"; have_slug=1; shift 2 ;;
      --pr) require_flag_value "$have_pr" "$#"; pr_arg="$2"; have_pr=1; shift 2 ;;
      --commit) require_flag_value "$have_commit" "$#"; commit="$2"; have_commit=1; shift 2 ;;
      --round) require_flag_value "$have_round" "$#"; round="$2"; have_round=1; shift 2 ;;
      *) idea_to_ready_fail usage ;;
    esac
  done
  if [ "$have_kind" -eq 0 ] || [ "$have_slug" -eq 0 ] || [ "$have_pr" -eq 0 ] || ! slug_ok "$SLUG"; then
    idea_to_ready_fail usage
  fi
  if [ "$pr_arg" != none ] && ! number_ok "$pr_arg"; then
    idea_to_ready_fail usage
  fi
  if [ "$have_round" -eq 1 ] && ! number_ok "$round"; then
    idea_to_ready_fail usage
  fi
  compose_flags_ok "$kind" "$have_commit" "$have_round"
  if [ "$have_commit" -eq 1 ]; then
    require_commit "$commit"
  fi
  require_tools
  require_checkout
  resolve_repo
  OUT="hivemind-guide-run: $SLUG"$'\n'
  if [ "$pr_arg" = none ]; then
    case "$kind" in
      prototype-build | design | close-out) ;;
      *) idea_to_ready_fail pr-required ;;
    esac
    require_no_docs_pr
    UI=no
    OUT+="Docs pull request: none"$'\n'
  else
    PR_NUMBER="$pr_arg"
    read_pr
    [ "$PR_DRAFT" = true ] || idea_to_ready_fail not-draft
    read_ui "$HEAD_COMMIT"
    case "$kind" in
      prototype-*) [ "$UI" = yes ] || idea_to_ready_fail not-ui ;;
    esac
    if [ "$have_commit" -eq 1 ]; then
      is_ancestor "$commit" "$HEAD_COMMIT" || idea_to_ready_fail commit-not-in-pr
    fi
    case "$kind" in
      round | record-pass | review-fix)
        read_record "$HEAD_COMMIT"
        if [ "$RECORD" = missing ] && { [ "$kind" != round ] || [ "$round" != 1 ]; }; then
          idea_to_ready_fail record-missing
        fi
        read_trunk yes
        ;;
    esac
    case "$kind" in
      prototype-refine | prototype-verdict | design | round) read_comments ;;
    esac
    OUT+="Docs pull request: #$PR_NUMBER"$'\n'
  fi
  OUT+="Deliver with hivemind:standard-delivery on the script engine, on the checked-out docs branch, launched with draft true; every step writes only its named files."$'\n'
  if [ "$kind" = record-pass ]; then
    OUT+="Launch with local_review false."$'\n'
  fi
  compose_kind_lines "$kind" "$commit" "$round"
  printf '%s' "$OUT"
}

# run_comment <arg>...: the comment subcommand.
run_comment() {
  local kind="" commit="" round="" body_arg="" have_kind=0 have_slug=0 have_pr=0 have_commit=0
  local have_round=0 have_body=0 marker="" section="" body_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --kind) require_flag_value "$have_kind" "$#"; kind="$2"; have_kind=1; shift 2 ;;
      --slug) require_flag_value "$have_slug" "$#"; SLUG="$2"; have_slug=1; shift 2 ;;
      --pr) require_flag_value "$have_pr" "$#"; PR_NUMBER="$2"; have_pr=1; shift 2 ;;
      --commit) require_flag_value "$have_commit" "$#"; commit="$2"; have_commit=1; shift 2 ;;
      --round) require_flag_value "$have_round" "$#"; round="$2"; have_round=1; shift 2 ;;
      --body-file) require_flag_value "$have_body" "$#"; body_arg="$2"; have_body=1; shift 2 ;;
      *) idea_to_ready_fail usage ;;
    esac
  done
  if [ "$have_kind" -eq 0 ] || [ "$have_slug" -eq 0 ] || [ "$have_pr" -eq 0 ] || ! slug_ok "$SLUG" \
    || ! number_ok "$PR_NUMBER"; then
    idea_to_ready_fail usage
  fi
  case "$kind:$have_round$have_commit$have_body" in
    round:111 | approval:001 | review:001 | veto:000) ;;
    *) idea_to_ready_fail usage ;;
  esac
  if [ "$have_round" -eq 1 ] && ! number_ok "$round"; then
    idea_to_ready_fail usage
  fi
  if [ "$have_commit" -eq 1 ]; then
    require_commit "$commit"
  fi
  require_tools
  require_checkout
  make_work_dir
  if [ "$have_body" -eq 1 ]; then
    read_guide_input "$body_arg" "$WORK_DIR/comment-input.txt" body
  fi
  resolve_repo
  read_pr
  case "$kind" in
    round)
      is_ancestor "$commit" "$HEAD_COMMIT" || idea_to_ready_fail commit-not-in-pr
      marker="<!-- hivemind-guide: round slug=$SLUG round=$round commit=$commit -->"
      ;;
    *) marker="<!-- hivemind-guide: $kind slug=$SLUG commit=$HEAD_COMMIT -->" ;;
  esac
  body_file="$WORK_DIR/comment.md"
  if [ "$kind" = veto ]; then
    section="$(read_doc_filter "$HEAD_COMMIT" "docs/initiatives/$SLUG/review-record.md" ir_veto)" \
      || idea_to_ready_fail git-failed
    case "$section" in
      section$'\n'*) ;;
      missing) idea_to_ready_fail record-missing ;;
      *) idea_to_ready_fail git-failed ;;
    esac
    printf '%s\n## Decisions taken, listed for veto\n\n%s\n' "$marker" "${section#section$'\n'}" \
      >"$body_file" || idea_to_ready_fail workdir-failed
  else
    { printf '%s\n' "$marker" && cat -- "$WORK_DIR/comment-input.txt"; } >"$body_file" \
      || idea_to_ready_fail workdir-failed
  fi
  post_comment "$body_file"
  remove_read_inputs
  printf '%s' "$OUT"
}

# run_approval <arg>...: the approval subcommand.
run_approval() {
  parse_pr_flags "$@"
  require_tools
  require_checkout
  resolve_repo
  read_pr
  read_comments
  approval_state
  printf 'approval=%s\n' "$APPROVAL_STATE"
  if [ "$APPROVAL_STATE" = kept ]; then
    printf 'folded=%s\n' "$APPROVAL_FOLDED"
  fi
  if [ "$APPROVAL_STATE" != none ]; then
    printf 'url=%s\n' "$MARKER_URL"
  fi
}

# run_redraft <arg>...: the redraft subcommand.
run_redraft() {
  parse_pr_flags "$@"
  require_tools
  require_checkout
  resolve_repo
  read_pr
  if [ "$PR_DRAFT" = true ]; then
    printf 'draft=yes\nchanged=no\n'
    return 0
  fi
  gh pr ready "$PR_NUMBER" --repo "$OWNER_REPO" --undo </dev/null >/dev/null 2>&1 || idea_to_ready_fail gh-failed
  printf 'draft=yes\nchanged=yes\n'
}

# run_ready <arg>...: the ready subcommand.
run_ready() {
  local verify="" verify_rc=0 edited=""
  local record_path=""
  parse_pr_flags "$@"
  record_path="docs/initiatives/$SLUG/review-record.md"
  require_tools
  require_checkout
  resolve_repo
  read_trunk yes
  read_pr
  [ "$PR_DRAFT" = true ] || idea_to_ready_fail not-draft
  merge_base_of "$HEAD_COMMIT" "$TRUNK_COMMIT"
  verify="$(hivemind_record_verify "$HEAD_COMMIT" "$MERGE_BASE" 2>/dev/null)" || verify_rc=$?
  case "$verify_rc" in
    0) ;;
    1)
      printf '%s\n' "$verify"
      exit 1
      ;;
    *) idea_to_ready_fail git-failed ;;
  esac
  read_record "$HEAD_COMMIT"
  case "$RECORD" in
    pass) ;;
    missing | malformed)
      printf 'record=%s\n' "$RECORD"
      exit 1
      ;;
    *)
      printf 'record=not-passed\n'
      exit 1
      ;;
  esac
  edited="$(git -C "$TOP" --no-replace-objects --literal-pathspecs -c diff.relative=false diff \
    --no-renames --no-ext-diff --name-only "$MERGE_BASE" "$HEAD_COMMIT" -- "$record_path" \
    </dev/null 2>/dev/null)" || idea_to_ready_fail git-failed
  if [ -n "$edited" ]; then
    read_comments
    latest_marker veto
    if [ -z "$MARKER_COMMIT" ]; then
      printf 'veto=missing\n'
      exit 1
    fi
    if [ "$MARKER_COMMIT" != "$HEAD_COMMIT" ]; then
      printf 'veto=stale\n'
      exit 1
    fi
  fi
  gh pr ready "$PR_NUMBER" --repo "$OWNER_REPO" </dev/null >/dev/null 2>&1 || idea_to_ready_fail gh-failed
  printf 'ready=yes\n'
}

START_DIR="$PWD"
if [ "$#" -eq 0 ]; then
  idea_to_ready_fail usage
fi
subcommand="$1"
shift
case "$subcommand" in
  list) run_list "$@" ;;
  stage) run_stage derive "$@" ;;
  handoff) run_stage handoff "$@" ;;
  seed) run_seed "$@" ;;
  standalone) run_standalone "$@" ;;
  reviewed) run_reviewed "$@" ;;
  compose) run_compose "$@" ;;
  comment) run_comment "$@" ;;
  approval) run_approval "$@" ;;
  redraft) run_redraft "$@" ;;
  ready) run_ready "$@" ;;
  *) idea_to_ready_fail usage ;;
esac
