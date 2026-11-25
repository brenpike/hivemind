#!/usr/bin/env bash
#
# merge-approved.sh — opt-in merge of an approved, settled, green PR for the
# github-review-loop skill (ADR-0044).
#
# Usage:
#   merge-approved.sh <OWNER> <REPO> <PR_NUMBER> <REVIEWER_FILTER> <SELF_LOGIN>
#
# The skill runs this ONCE after an `approval-clean` end of the post-PR watch.
# It makes NO judgment of its own beyond the fixed gates below: the checks in
# this file are the whole merge rule. It never reads review text.
#
# 1. OUTPUT CONTRACT
# ------------------
# Every run prints EXACTLY ONE line on stdout and nothing on stderr.
#   MERGE=off                      HIVEMIND_AUTO_MERGE is unset or empty; no gh
#                                  call is made (exit 0)
#   MERGE=skipped:bad-setting      HIVEMIND_AUTO_MERGE is set to a value other
#                                  than merge, squash or rebase; no gh call is
#                                  made (exit 0)
#   MERGE=skipped:not-open         the PR state is not OPEN (exit 0)
#   MERGE=skipped:draft            the PR is a draft (exit 0)
#   MERGE=skipped:no-approval      the latest reviews hold no settled evidence
#                                  (`has_settled_evidence`): some author's
#                                  latest review is not APPROVED, COMMENTED or
#                                  DISMISSED, or no in-scope Automated Reviewer
#                                  has a latest review in APPROVED or COMMENTED
#                                  or a 👍 on the PR (exit 0)
#   MERGE=skipped:open-threads     a review thread fails `is_settled_thread`
#                                  (exit 0)
#   MERGE=skipped:no-checks        the head commit has no check rollup (exit 0)
#   MERGE=wait:checks-pending      the rollup is PENDING or EXPECTED (exit 0)
#   MERGE=wait:checks-failed       the rollup is FAILURE or ERROR (exit 0)
#   MERGE=merged                   the plain merge exited 0 and the confirm
#                                  read shows the PR MERGED (exit 0)
#   MERGE=skipped:record-unread    the PR touches docs and the record gate could
#                                  not read the review records: no remote tied
#                                  to <OWNER>/<REPO>, a bad base name, a failed
#                                  fetch, a missing commit, no merge-base or a
#                                  verify error (exit 0)
#   MERGE=skipped:record-blocked   the PR touches docs and record verify, merge
#                                  mode, fails a review record (exit 0)
#   MERGE=wait:head-moved          the plain merge was refused and a re-read
#                                  shows a PR head other than the commit that
#                                  was read, or the PR touches docs and the
#                                  fresh read before a merge call shows a new
#                                  head (exit 0)
#   MERGE=wait:base-moved          the PR touches docs and the fresh read before
#                                  a merge call shows a baseRefOid other than
#                                  the one the record gate verified (exit 0)
#   MERGE=skipped:conflicts        refused; mergeStateStatus is DIRTY (exit 0)
#   MERGE=merged-admin             refused; the `--admin` rerun exited 0 and
#                                  the confirm read shows the PR MERGED (exit 0)
#   MERGE=skipped:blocked          refused; mergeStateStatus is BLOCKED or
#                                  BEHIND and HIVEMIND_AUTO_MERGE_ADMIN is
#                                  unset or empty (exit 0)
#   MERGE=skipped:admin-refused    refused; mergeStateStatus is BLOCKED or
#                                  BEHIND, and the `--admin` rerun exited
#                                  non-zero (exit 0)
#   MERGE=wait:merge-state-unknown refused; mergeStateStatus is still UNKNOWN
#                                  after the bounded re-reads of §5 (exit 0)
#   MERGE=skipped:refused          refused; the last re-read shows a
#                                  mergeStateStatus other than DIRTY, BLOCKED,
#                                  BEHIND or UNKNOWN (exit 0)
#   MERGE=wait:merge-pending       a merge call, plain or `--admin`, exited 0
#                                  but the confirm read shows the PR not MERGED:
#                                  OPEN (queued in a merge queue, or GitHub
#                                  lag) or CLOSED (exit 0)
#   MERGE_ERROR=<reason>           bad arguments, a failed bootstrap, a bad
#                                  re-read delay (`bad-reread-delay`), a failed
#                                  wait between re-reads (`reread-wait-failed`),
#                                  or a failed or incomplete read (exit 1)
# `wait:*` means the watch keeps running: pending or failed CI is fixed or
# awaited, and the merge is tried again at the next settled approval.
# `wait:merge-pending` makes no further merge call: the poll's STATE=MERGED or
# the idle window ends a pending merge.
#
# 2. SETTINGS (environment)
# -------------------------
#   HIVEMIND_AUTO_MERGE        the merge method: `merge`, `squash` or `rebase`.
#                              Unset or empty is off. Read before any gh call.
#   HIVEMIND_AUTO_MERGE_ADMIN  checked by PRESENCE (any non-empty value). Unset
#                              or empty is off. Allows ONE `--admin` rerun after
#                              a refused plain merge, under the conditions in §5.
#   HIVEMIND_PR_REVIEWERS      optional; more Bot logins for the Automated
#                              Reviewer set. Passed to jq as `--arg` data, never
#                              as program text. It only adds to the set.
#   HIVEMIND_AUTO_MERGE_REREAD_DELAY
#                              optional; whole seconds, 0 to 99, waited before
#                              each re-read of an UNKNOWN mergeStateStatus (§5).
#                              Unset or empty is 5. Any other value is
#                              `MERGE_ERROR=bad-reread-delay`, checked after
#                              HIVEMIND_AUTO_MERGE and before any gh call. The
#                              test suite sets it to 0.
#
# 3. ARGUMENTS
# ------------
#   $1 OWNER            base-repo owner: a GitHub login (letters, digits and
#                       single inner hyphens, at most 39 characters)
#   $2 REPO             base-repo name: letters, digits, `.`, `_`, `-`, at most
#                       100 characters, and never `.` or `..`
#   $3 PR_NUMBER        a positive decimal integer, at most 18 digits, no
#                       leading zero
#   $4 REVIEWER_FILTER  "automated" | "all" | "<login>" (empty means
#                       "automated"); the module's retired filter value is
#                       refused
#   $5 SELF_LOGIN       the viewer login (required, non-empty)
# Exactly five arguments are required. Each is checked before any gh call:
# bad-arguments, bad-owner, bad-repo, bad-pr-number, missing-self-login,
# retired-filter, identity-check-failed.
#
# 4. THE READ
# -----------
# ONE GraphQL query reads: state, isDraft, headRefOid, mergeStateStatus,
# baseRefName, baseRefOid, the
# last PR commit's oid and statusCheckRollup state, latestReviews (first: 100)
# with each review's state and its author's login and `__typename`, the
# THUMBS_UP reactors (first: 100)
# with login and `__typename`, reviewThreads (first: 100) with isResolved
# and each thread's last comment author (login and `__typename`), and files
# (first: 100) with each file's path and changeType. The comments
# and reviews connections are read as a one-node skeleton only, so the shared
# shape check sees every connection it requires.
# The body must pass hivemind_graphql_response_check
# (${CLAUDE_PLUGIN_ROOT}/skills/_shared/graphql-response.sh) and then
# hivemind_review_surface_shape_check
# (${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-surface-shape.sh). The local
# projection then type-checks every field it reads; a wrong type (a review
# state that is not a string included), an unknown PR state or rollup state, a
# headRefOid or baseRefOid that is not a hex commit id, a baseRefName that is
# not a non-empty string, a file path or changeType that is not a string, or a
# last commit whose oid differs from headRefOid is `MERGE_ERROR=malformed-read`.
# The projection sets DOCS TOUCH when a file path starts with `docs/prds/`,
# `docs/initiatives/` or `docs/adr/`, a changeType is RENAMED (the old path is
# not read), or files reports `hasNextPage: true`. A files page overflow only
# turns the record gate on; it never fails the read.
# The projection builds one {state, login, type} row per latestReviews node, of
# every author: a review whose author is null is kept as a row with a null
# login and type, so it still counts toward the state rule of gate 3.
# A READ PAST ITS PAGE FAILS CLOSED: when latestReviews, the THUMBS_UP
# reactors or reviewThreads report `hasNextPage: true`, the read is
# incomplete and the run prints `MERGE_ERROR=read-incomplete`, so no approval
# or settled verdict is ever drawn from a partial read.
# Failed reads: gh exits non-zero (`graphql-read-failed`), the envelope check
# fails (`graphql-<token>`), the shape check fails (`shape-<token>`).
# The same read, with both checks and the projection, runs again after a
# refused plain merge (the re-read, repeated while UNKNOWN, §5), after every
# merge call that exits 0
# (the confirm read, §5) and, on a DOCS TOUCH PR, after the record gate (the
# fresh read, §5); each fails as above.
#
# 5. GATES, in order (the first that applies prints its line)
# -----------------------------------------------------------
#   1. state is not OPEN                                   skipped:not-open
#   2. isDraft                                             skipped:draft
#   3. `has_settled_evidence` over the latestReviews rows
#      and the 👍 rows is false: some latest review, of
#      any author, is not APPROVED, COMMENTED or
#      DISMISSED (a standing block no approval outweighs),
#      or no in-scope reviewer (`is_automated_reviewer`
#      and `reviewer_matches_filter`, over the set
#      `automated_reviewer_set` derives from those rows
#      plus HIVEMIND_PR_REVIEWERS) has a latest review in
#      APPROVED or COMMENTED or a 👍                       skipped:no-approval
#   4. any thread fails `is_settled_thread`                skipped:open-threads
#   5. rollup null                                         skipped:no-checks
#   6. rollup PENDING or EXPECTED                          wait:checks-pending
#   7. rollup FAILURE or ERROR                             wait:checks-failed
#   R. DOCS TOUCH only, after gates 1-7 hold on the first read, the RECORD
#      GATE, before any merge call:
#      (1) the remote: the first remote, in `git remote` order, whose name
#          passes the identifier gate of
#          ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Shell Identifier Discipline)
#          and whose fetch URL (`git remote get-url`) names <OWNER>/<REPO> on
#          the gh host (GH_HOST, else github.com), compared case-insensitively,
#          in https (`https://[user@]host/owner/repo[.git][/]`), scp-style
#          (`[user@]host:owner/repo[.git]`) or ssh
#          (`ssh://[user@]host/owner/repo[.git][/]`) form; none   skipped:record-unread
#      (2) baseRefName passes the identifier gate and
#          `git check-ref-format --branch` returns it unchanged; then
#            git fetch --quiet --no-tags --no-recurse-submodules --no-prune
#              --refmap= -- <remote> refs/pull/<n>/head refs/heads/<baseRefName>
#          runs with GIT_TERMINAL_PROMPT=0. An empty `--refmap=` keeps the
#          remote's configured refspecs out, so the fetch writes FETCH_HEAD
#          only: no local branch and no remote-tracking ref. The read
#          headRefOid and baseRefOid must then each name a local commit
#      (3) `git merge-base <headRefOid> <baseRefOid>` gives a hex commit id;
#          a failure in (2) or (3)                         skipped:record-unread
#      (4) hivemind_record_verify_merge <headRefOid> <merge-base> <baseRefOid>
#          (${CLAUDE_PLUGIN_ROOT}/skills/_shared/record-verify.sh), its stdout
#          and stderr discarded:
#            0                                             (gate holds)
#            1                                             skipped:record-blocked
#            anything else                                 skipped:record-unread
#      When the record gate holds, the FRESH READ runs (§4), and:
#        headRefOid differs from the first read            wait:head-moved
#        baseRefOid differs from the first read            wait:base-moved
#        a gate of 1-7 fails                               that gate's line
#      A PR without DOCS TOUCH skips R: no git call, no fresh read.
#   8. rollup SUCCESS: run
#        gh pr merge <n> --repo <owner>/<repo> --<method> --match-head-commit <headRefOid>
#      exit 0, confirm read MERGED                         merged
#      exit 0, confirm read not MERGED                     wait:merge-pending
# A merge call that exits 0, plain or `--admin`, is never taken as the verdict:
# a merge queue can accept the call and leave the PR OPEN. The script reads
# the PR again through the same query and checks (§4), the confirm read, and
# prints merged or merged-admin only when its state is MERGED. No merge call
# follows the confirm read, so a plain call that exits 0 never reaches
# `--admin`.
# A plain merge that exits non-zero is REFUSED; its output is discarded. The
# script then reads the PR again through the same query and checks (§4), the
# re-read. GitHub can report mergeStateStatus UNKNOWN while it recomputes the
# state after the refused call, so while a re-read shows UNKNOWN the script
# waits HIVEMIND_AUTO_MERGE_REREAD_DELAY seconds and re-reads, at most 3 more
# times. The head check (a) runs on every re-read; b-e judge the last one:
#   a. headRefOid differs from the first read              wait:head-moved
#   b. mergeStateStatus is DIRTY                           skipped:conflicts
#   c. mergeStateStatus is BLOCKED or BEHIND:
#      - HIVEMIND_AUTO_MERGE_ADMIN unset or empty          skipped:blocked
#      - set, DOCS TOUCH, and the last re-read, which is
#        the fresh read before the `--admin` call, shows a
#        baseRefOid other than the first read's            wait:base-moved
#      - set, and a gate of 1-7 fails on the last re-read  that gate's line
#      - set, and gates 1-7 all hold on the last re-read: rerun the same
#        command with `--admin` and the same `--match-head-commit`
#          exit 0, confirm read MERGED                     merged-admin
#          exit 0, confirm read not MERGED                 wait:merge-pending
#          non-zero                                        skipped:admin-refused
#   d. mergeStateStatus is still UNKNOWN                   wait:merge-state-unknown
#   e. any other mergeStateStatus                          skipped:refused
# So `--admin` runs only after a refused plain merge, only with the admin
# setting set to a non-empty value, and only when the first read and the last
# re-read passed every gate of 1-7 on the same head, and on a DOCS TOUCH PR
# the same baseRefOid the record gate verified. A standing block prints skipped:no-approval
# on either read, so a review that requests changes between the two reads
# stops the retry before any `--admin` call.
# Every merge call carries `--match-head-commit`, so a commit pushed after the
# read is never merged. The script NEVER passes `--auto` or `--delete-branch`,
# and never merges a head whose rollup it did not see SUCCESS.
# NOT CHECKED: a base that moves between the fresh read and the merge call;
# `--match-head-commit` pins the head only. The window is one gh call wide.
#
# 6. IDENTITY
# -----------
# Every identity decision (Bot, self, the Automated Reviewer set, the filter
# modes, the retired filter value, the settled thread) and the approval
# verdict of gate 3 (`has_settled_evidence`, keyed on review state, never on
# who reviewed) are delegated to the
# sibling module reviewer-identity.jq, loaded by search path
# (`jq -L "$SCRIPT_DIR"`, `include "reviewer-identity"`). This script carries no
# login literal and no login compare of its own.
#
# 7. BOOTSTRAP
# ------------
# The script locates its own directory (ADR-0020 C1) and fails closed with
# `MERGE_ERROR=cannot-self-locate`; the identity module, graphql-response.sh,
# review-surface-shape.sh, readiness-check.sh and then record-verify.sh (which
# needs readiness-check.sh sourced first) must be present and source cleanly
# (missing-identity-module, missing-graphql-check, unparseable-graphql-check,
# missing-review-surface-check, unparseable-review-surface-check,
# missing-readiness-check, unparseable-readiness-check, missing-record-verify,
# unparseable-record-verify). The bootstrap runs before argument checks and
# before any gh or git call; sourcing defines functions only.
#
# P18 floor: `set -euo pipefail`. Every expected non-zero status (gh, git, jq,
# sleep, a shared check) is tested by `if` or `||` and routed to merge_approved_fail,
# to a refused-merge branch or to a record gate line, so errexit never ends a
# run without its one line.
#
# DEPENDENCY: bash (4+), jq (1.6+), gh. git (2.1+, for `--refmap`) runs only
# in the record gate of a DOCS TOUCH PR, in the current directory's
# repository; with no git, or no repository, that gate prints
# skipped:record-unread. coreutils `timeout` (or `gtimeout`) bounds each read
# when present, the record gate's fetch included; merge calls are never
# wrapped, so a merge is never cut off mid-flight. `sleep` waits between the
# re-reads of an UNKNOWN mergeStateStatus.

set -euo pipefail

# merge_approved_fail <reason>: print MERGE_ERROR=<reason> on stdout, exit 1.
merge_approved_fail() {
  echo "MERGE_ERROR=$1"
  exit 1
}

SCRIPT_DIR="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || merge_approved_fail "cannot-self-locate"
[ -f "$SCRIPT_DIR/reviewer-identity.jq" ] || merge_approved_fail "missing-identity-module"
[ -f "$SCRIPT_DIR/../../_shared/graphql-response.sh" ] || merge_approved_fail "missing-graphql-check"
# shellcheck source=../../_shared/graphql-response.sh
. "$SCRIPT_DIR/../../_shared/graphql-response.sh" || merge_approved_fail "unparseable-graphql-check"
[ -f "$SCRIPT_DIR/../../_shared/review-surface-shape.sh" ] || merge_approved_fail "missing-review-surface-check"
# shellcheck source=../../_shared/review-surface-shape.sh
. "$SCRIPT_DIR/../../_shared/review-surface-shape.sh" || merge_approved_fail "unparseable-review-surface-check"
[ -f "$SCRIPT_DIR/../../_shared/readiness-check.sh" ] || merge_approved_fail "missing-readiness-check"
# shellcheck source=../../_shared/readiness-check.sh
. "$SCRIPT_DIR/../../_shared/readiness-check.sh" || merge_approved_fail "unparseable-readiness-check"
[ -f "$SCRIPT_DIR/../../_shared/record-verify.sh" ] || merge_approved_fail "missing-record-verify"
# shellcheck source=../../_shared/record-verify.sh
. "$SCRIPT_DIR/../../_shared/record-verify.sh" || merge_approved_fail "unparseable-record-verify"

[ "$#" -eq 5 ] || merge_approved_fail "bad-arguments"
OWNER="$1"
REPO="$2"
PR_NUMBER="$3"
REVIEWER_FILTER="$4"
SELF_LOGIN="$5"

[[ "$OWNER" =~ ^[A-Za-z0-9]([A-Za-z0-9]|-[A-Za-z0-9]){0,38}$ ]] || merge_approved_fail "bad-owner"
[[ "$REPO" =~ ^[A-Za-z0-9._-]{1,100}$ ]] || merge_approved_fail "bad-repo"
[ "$REPO" != "." ] && [ "$REPO" != ".." ] || merge_approved_fail "bad-repo"
[[ "$PR_NUMBER" =~ ^[1-9][0-9]{0,17}$ ]] || merge_approved_fail "bad-pr-number"
[ -n "$SELF_LOGIN" ] || merge_approved_fail "missing-self-login"
[ -n "$REVIEWER_FILTER" ] || REVIEWER_FILTER="automated"
if ! retired_filter="$(jq -n -r -L "$SCRIPT_DIR" --arg filter "$REVIEWER_FILTER" '
  include "reviewer-identity";
  is_retired_filter($filter)
' 2>/dev/null)"; then
  merge_approved_fail "identity-check-failed"
fi
[ "$retired_filter" = "false" ] || merge_approved_fail "retired-filter"

MERGE_METHOD="${HIVEMIND_AUTO_MERGE:-}"
if [ -z "$MERGE_METHOD" ]; then
  echo "MERGE=off"
  exit 0
fi
case "$MERGE_METHOD" in
  merge|squash|rebase) ;;
  *) echo "MERGE=skipped:bad-setting"; exit 0 ;;
esac

MERGE_STATE_REREADS=3
REREAD_DELAY_SECONDS="${HIVEMIND_AUTO_MERGE_REREAD_DELAY:-5}"
[[ "$REREAD_DELAY_SECONDS" =~ ^[0-9]{1,2}$ ]] || merge_approved_fail "bad-reread-delay"

GH_READ_TIMEOUT_SECONDS=45
GIT_FETCH_TIMEOUT_SECONDS=120
GH_READ_TIMEOUT=()
GIT_FETCH_TIMEOUT=()
if command -v timeout >/dev/null 2>&1; then
  GH_READ_TIMEOUT=(timeout "$GH_READ_TIMEOUT_SECONDS")
  GIT_FETCH_TIMEOUT=(timeout "$GIT_FETCH_TIMEOUT_SECONDS")
elif command -v gtimeout >/dev/null 2>&1; then
  GH_READ_TIMEOUT=(gtimeout "$GH_READ_TIMEOUT_SECONDS")
  GIT_FETCH_TIMEOUT=(gtimeout "$GIT_FETCH_TIMEOUT_SECONDS")
fi

PR_QUERY='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      state
      isDraft
      headRefOid
      mergeStateStatus
      baseRefName
      baseRefOid
      commits(last: 1) {
        nodes { commit { oid statusCheckRollup { state } } }
      }
      comments(last: 1) { nodes { id } }
      reviews(last: 1) { nodes { id } }
      latestReviews(first: 100) {
        pageInfo { hasNextPage }
        nodes { state author { login __typename } }
      }
      reactionGroups {
        content
        reactors(first: 100) {
          pageInfo { hasNextPage }
          nodes { __typename ... on Actor { login } }
        }
      }
      reviewThreads(first: 100) {
        pageInfo { hasNextPage }
        nodes {
          isResolved
          comments(last: 1) {
            nodes { author { login __typename } }
          }
        }
      }
      files(first: 100) {
        pageInfo { hasNextPage }
        nodes { path changeType }
      }
    }
  }
}'

# INVARIANT: the projection either prints one tab-separated line of eleven
# fields or fails; every field it prints was type-checked first, so the bash
# gates never compare an unchecked value. base_name, the one free-text field,
# is non-empty, so no empty field collapses under the tab IFS, and @tsv
# escapes any tab or newline inside it.
# Fields: complete, state, is_draft, head_oid, merge_state, rollup (NONE when
# null), approved, settled, docs_touch, base_oid, base_name.
PROJECTION_PROGRAM='
  include "reviewer-identity";
  def checked(cond): if cond then . else error("malformed") end;
  def node_list: .nodes | checked(type == "array");
  def page_flag: .pageInfo.hasNextPage | checked(type == "boolean");
  def actor_row: {login: .login, type: .type} | select((.login | type) == "string");
  .data.repository.pullRequest as $pr
  | ($pr.state | checked(. == "OPEN" or . == "CLOSED" or . == "MERGED")) as $state
  | ($pr.isDraft | checked(type == "boolean")) as $is_draft
  | ($pr.headRefOid | checked(type == "string" and test("\\A[0-9a-f]{40}([0-9a-f]{24})?\\z"))) as $head
  | ($pr.mergeStateStatus | checked(type == "string" and test("\\A[A-Z_]{1,32}\\z"))) as $merge_state
  | ($pr.baseRefName | checked(type == "string" and length > 0)) as $base_name
  | ($pr.baseRefOid | checked(type == "string" and test("\\A[0-9a-f]{40}([0-9a-f]{24})?\\z"))) as $base_oid
  | ($pr.files | checked(type == "object")) as $files
  | ([$files | node_list | .[] | checked(type == "object")
      | (.path | checked(type == "string")) as $path
      | (.changeType | checked(type == "string")) as $change_type
      | $change_type == "RENAMED"
        or ($path | startswith("docs/prds/") or startswith("docs/initiatives/") or startswith("docs/adr/"))]
      | any(.[]; .) or ($files | page_flag)) as $docs_touch
  | ($pr.commits | checked(type == "object") | node_list | checked(length == 1) | .[0]
      | checked(type == "object") | .commit | checked(type == "object")) as $commit
  | ($commit.oid | checked(. == $head)) as $commit_oid
  | ($commit.statusCheckRollup
      | if . == null then "NONE"
        else checked(type == "object") | .state
          | checked(. == "SUCCESS" or . == "PENDING" or . == "EXPECTED" or . == "FAILURE" or . == "ERROR")
        end) as $rollup
  | ($pr.latestReviews | checked(type == "object")) as $latest
  | ($pr.reactionGroups | checked(type == "array")
      | map(checked(type == "object") | select(.content == "THUMBS_UP")
            | .reactors | checked(type == "object"))) as $thumbs_groups
  | $pr.reviewThreads as $threads
  | ([$latest | page_flag] + [$thumbs_groups[] | page_flag] + [$threads | page_flag]
      | any(.[]; . == true) | not) as $complete
  | [ $latest | node_list | .[] | checked(type == "object")
      | (.state | checked(type == "string")) as $review_state
      | (.author // {}) | {state: $review_state, login: .login, type: .__typename} ] as $review_rows
  | [ $thumbs_groups[] | node_list | .[] | checked(type == "object")
      | {login: .login, type: .__typename} | actor_row ] as $thumb_rows
  | automated_reviewer_set($review_rows + $thumb_rows; $reviewers) as $set
  | has_settled_evidence($review_rows; $thumb_rows; $self; $filter; $set) as $approved
  | all($threads.nodes[];
        (.comments.nodes | last // {}) as $last_comment
        | ($last_comment.author // {}) as $last_author
        | is_settled_thread(.isResolved; $last_author.login; $last_author.__typename; $self)) as $settled
  | [$complete, $state, $is_draft, $head, $merge_state, $rollup, $approved, $settled,
     $docs_touch, $base_oid, $base_name]
  | map(tostring) | @tsv'

# read_pr: one read of the PR through PR_QUERY, both shared checks and the
# projection. Sets READ_COMPLETE, READ_STATE, READ_IS_DRAFT, READ_HEAD,
# READ_MERGE_STATE, READ_ROLLUP, READ_APPROVED, READ_SETTLED, READ_DOCS_TOUCH,
# READ_BASE_OID and READ_BASE_NAME. Every failure, an incomplete read
# included, is merge_approved_fail.
read_pr() {
  local pr_body check_token projected_line
  if ! pr_body="$("${GH_READ_TIMEOUT[@]+"${GH_READ_TIMEOUT[@]}"}" gh api graphql \
      -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUMBER" \
      -f query="$PR_QUERY" 2>/dev/null)"; then
    merge_approved_fail "graphql-read-failed"
  fi
  if ! check_token="$(hivemind_graphql_response_check "$pr_body")"; then
    merge_approved_fail "graphql-$check_token"
  fi
  if ! check_token="$(hivemind_review_surface_shape_check "$pr_body")"; then
    merge_approved_fail "shape-$check_token"
  fi
  if ! projected_line="$(printf '%s' "$pr_body" | jq -r -L "$SCRIPT_DIR" \
      --arg self "$SELF_LOGIN" --arg filter "$REVIEWER_FILTER" \
      --arg reviewers "${HIVEMIND_PR_REVIEWERS-}" "$PROJECTION_PROGRAM" 2>/dev/null)"; then
    merge_approved_fail "malformed-read"
  fi
  IFS=$'\t' read -r READ_COMPLETE READ_STATE READ_IS_DRAFT READ_HEAD READ_MERGE_STATE \
    READ_ROLLUP READ_APPROVED READ_SETTLED READ_DOCS_TOUCH READ_BASE_OID READ_BASE_NAME \
    <<<"$projected_line" || merge_approved_fail "malformed-read"
  [ -n "$READ_SETTLED" ] || merge_approved_fail "malformed-read"
  [ -n "$READ_BASE_NAME" ] || merge_approved_fail "malformed-read"
  [ "$READ_COMPLETE" = "true" ] || merge_approved_fail "read-incomplete"
}

# rollup_line: the gate line for a rollup that is not SUCCESS (gates 5-7).
# Prints nothing for SUCCESS.
rollup_line() {
  case "$READ_ROLLUP" in
    NONE) echo "MERGE=skipped:no-checks" ;;
    PENDING|EXPECTED) echo "MERGE=wait:checks-pending" ;;
    FAILURE|ERROR) echo "MERGE=wait:checks-failed" ;;
  esac
}

# run_merge [--admin]: the one merge command, always with --match-head-commit
# on the head the gates read. Its output is discarded. Its exit status only
# decides whether --admin may follow; it is never the merge verdict, which
# confirm_merge reads.
run_merge() {
  gh pr merge "$PR_NUMBER" --repo "$OWNER/$REPO" "--$MERGE_METHOD" \
    --match-head-commit "$GATED_HEAD" "$@" >/dev/null 2>&1
}

# confirm_merge <merged_line>: the confirm read after a merge call that exited
# 0. Prints <merged_line> when the PR state is MERGED, else
# MERGE=wait:merge-pending. A failed or incomplete read is merge_approved_fail.
confirm_merge() {
  read_pr
  if [ "$READ_STATE" = "MERGED" ]; then
    echo "$1"
  else
    echo "MERGE=wait:merge-pending"
  fi
}

# gates_hold: gates 1-7 over the last read_pr. Prints the gate line and fails
# when one does not hold; prints nothing when all hold. Every merge call, the
# --admin retry included, runs only after it passes on a fresh read.
gates_hold() {
  if [ "$READ_STATE" != "OPEN" ]; then
    echo "MERGE=skipped:not-open"; return 1
  fi
  if [ "$READ_IS_DRAFT" = "true" ]; then
    echo "MERGE=skipped:draft"; return 1
  fi
  if [ "$READ_APPROVED" != "true" ]; then
    echo "MERGE=skipped:no-approval"; return 1
  fi
  if [ "$READ_SETTLED" != "true" ]; then
    echo "MERGE=skipped:open-threads"; return 1
  fi
  if [ "$READ_ROLLUP" != "SUCCESS" ]; then
    rollup_line; return 1
  fi
}

# identifier_ok <name>: the identifier gate for a branch or remote name:
# non-empty, only `A-Za-z0-9._/-`, no leading `-` and no `..`.
identifier_ok() {
  [[ "$1" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "$1" != -* ]] && [[ "$1" != *..* ]]
}

# url_names_repo <url>: 0 when <url> names OWNER/REPO on the gh host (GH_HOST,
# else github.com) in https, scp-style or ssh form, compared
# case-insensitively; else 1.
url_names_repo() {
  local remote_url="${1,,}" gh_host="${GH_HOST:-github.com}" authority="" repo_path=""
  gh_host="${gh_host,,}"
  case "$remote_url" in
    https://* | ssh://*)
      authority="${remote_url#*://}"
      [[ "$authority" == */* ]] || return 1
      repo_path="${authority#*/}"
      authority="${authority%%/*}" ;;
    *://*)
      return 1 ;;
    *:*)
      authority="${remote_url%%:*}"
      repo_path="${remote_url#*:}"
      [[ "$authority" != */* ]] || return 1 ;;
    *)
      return 1 ;;
  esac
  [ "${authority##*@}" = "$gh_host" ] || return 1
  repo_path="${repo_path%/}"
  [ "$repo_path" = "${OWNER,,}/${REPO,,}" ] || [ "$repo_path" = "${OWNER,,}/${REPO,,}.git" ]
}

# record_remote: prints the first remote, in `git remote` order, whose name
# passes identifier_ok and whose fetch URL names OWNER/REPO; fails when none
# does or git fails.
record_remote() {
  local remote_list="" remote_name="" remote_url=""
  remote_list="$(git remote </dev/null 2>/dev/null)" || return 1
  while IFS= read -r remote_name; do
    identifier_ok "$remote_name" || continue
    remote_url="$(git remote get-url "$remote_name" </dev/null 2>/dev/null)" || continue
    if url_names_repo "$remote_url"; then
      printf '%s\n' "$remote_name"
      return 0
    fi
  done <<<"$remote_list"
  return 1
}

# base_ref_ok <name>: 0 when <name> passes identifier_ok and
# `git check-ref-format --branch` returns it unchanged; else 1.
base_ref_ok() {
  local checked_name=""
  identifier_ok "$1" || return 1
  checked_name="$(git check-ref-format --branch "$1" </dev/null 2>/dev/null)" || return 1
  [ "$checked_name" = "$1" ]
}

# commit_present <oid>: 0 when <oid> names a commit in the local object store.
commit_present() {
  local object_type=""
  object_type="$(git --no-replace-objects cat-file -t "$1" </dev/null 2>/dev/null)" || return 1
  [ "$object_type" = "commit" ]
}

# fetch_record_commits <remote>: fetches the PR head and the base branch from
# <remote> into the object store, writing FETCH_HEAD only; fails on any error.
fetch_record_commits() {
  GIT_TERMINAL_PROMPT=0 "${GIT_FETCH_TIMEOUT[@]+"${GIT_FETCH_TIMEOUT[@]}"}" git --no-replace-objects \
    fetch --quiet --no-tags --no-recurse-submodules --no-prune --refmap= \
    -- "$1" "refs/pull/$PR_NUMBER/head" "refs/heads/$READ_BASE_NAME" </dev/null >/dev/null 2>&1
}

# record_gate: the record gate (§5 R) over GATED_HEAD and GATED_BASE. Prints
# MERGE=skipped:record-unread or MERGE=skipped:record-blocked and fails when
# the records cannot be read or a record fails; prints nothing when it holds.
record_gate() {
  local remote_name="" merge_base="" verify_rc=0
  if ! remote_name="$(record_remote)" \
     || ! base_ref_ok "$READ_BASE_NAME" \
     || ! fetch_record_commits "$remote_name" \
     || ! commit_present "$GATED_HEAD" || ! commit_present "$GATED_BASE" \
     || ! merge_base="$(git --no-replace-objects merge-base "$GATED_HEAD" "$GATED_BASE" </dev/null 2>/dev/null)" \
     || ! hivemind_readiness_commit_ok "$merge_base" 2>/dev/null; then
    echo "MERGE=skipped:record-unread"; return 1
  fi
  hivemind_record_verify_merge "$GATED_HEAD" "$merge_base" "$GATED_BASE" >/dev/null 2>&1 || verify_rc=$?
  case "$verify_rc" in
    0) return 0 ;;
    1) echo "MERGE=skipped:record-blocked" ;;
    *) echo "MERGE=skipped:record-unread" ;;
  esac
  return 1
}

# read_unmoved: 0 when the last read_pr shows GATED_HEAD and GATED_BASE; else
# prints MERGE=wait:head-moved or MERGE=wait:base-moved and fails.
read_unmoved() {
  if [ "$READ_HEAD" != "$GATED_HEAD" ]; then
    echo "MERGE=wait:head-moved"; return 1
  fi
  if [ "$READ_BASE_OID" != "$GATED_BASE" ]; then
    echo "MERGE=wait:base-moved"; return 1
  fi
}

# reread_after_refusal: the re-read after a refused plain merge (§5). Reads the
# PR; while the read shows mergeStateStatus UNKNOWN, waits REREAD_DELAY_SECONDS
# and reads again, at most MERGE_STATE_REREADS more times. Prints
# MERGE=wait:head-moved and fails when any read shows a head other than
# GATED_HEAD; else leaves the last read in the READ_* fields.
reread_after_refusal() {
  local reread_count=0
  read_pr
  while :; do
    if [ "$READ_HEAD" != "$GATED_HEAD" ]; then
      echo "MERGE=wait:head-moved"; return 1
    fi
    [ "$READ_MERGE_STATE" = "UNKNOWN" ] || return 0
    [ "$reread_count" -lt "$MERGE_STATE_REREADS" ] || return 0
    reread_count=$((reread_count + 1))
    sleep "$REREAD_DELAY_SECONDS" </dev/null >/dev/null 2>&1 || merge_approved_fail "reread-wait-failed"
    read_pr
  done
}

read_pr
gates_hold || exit 0

GATED_HEAD="$READ_HEAD"
GATED_BASE="$READ_BASE_OID"
DOCS_TOUCH="$READ_DOCS_TOUCH"
if [ "$DOCS_TOUCH" = "true" ]; then
  record_gate || exit 0
  read_pr
  read_unmoved || exit 0
  gates_hold || exit 0
fi
if run_merge; then
  confirm_merge "MERGE=merged"; exit 0
fi

reread_after_refusal || exit 0
case "$READ_MERGE_STATE" in
  DIRTY)
    echo "MERGE=skipped:conflicts" ;;
  BLOCKED|BEHIND)
    if [ -z "${HIVEMIND_AUTO_MERGE_ADMIN:-}" ]; then
      echo "MERGE=skipped:blocked"
    elif [ "$DOCS_TOUCH" = "true" ] && ! read_unmoved; then
      :
    elif ! gates_hold; then
      :
    elif run_merge --admin; then
      confirm_merge "MERGE=merged-admin"
    else
      echo "MERGE=skipped:admin-refused"
    fi ;;
  UNKNOWN)
    echo "MERGE=wait:merge-state-unknown" ;;
  *)
    echo "MERGE=skipped:refused" ;;
esac
exit 0
