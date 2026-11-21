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
#   MERGE=skipped:no-approval      no in-scope Automated Reviewer has a latest
#                                  review or a 👍 on the PR (exit 0)
#   MERGE=skipped:open-threads     a review thread fails `is_settled_thread`
#                                  (exit 0)
#   MERGE=skipped:no-checks        the head commit has no check rollup (exit 0)
#   MERGE=wait:checks-pending      the rollup is PENDING or EXPECTED (exit 0)
#   MERGE=wait:checks-failed       the rollup is FAILURE or ERROR (exit 0)
#   MERGE=merged                   the plain merge succeeded (exit 0)
#   MERGE=wait:head-moved          the plain merge was refused and the PR head
#                                  is no longer the commit that was read (exit 0)
#   MERGE=skipped:conflicts        refused; mergeStateStatus is DIRTY (exit 0)
#   MERGE=merged-admin             refused; the `--admin` rerun succeeded (exit 0)
#   MERGE=skipped:blocked          refused; mergeStateStatus is BLOCKED or
#                                  BEHIND and HIVEMIND_AUTO_MERGE_ADMIN is
#                                  unset or empty (exit 0)
#   MERGE=skipped:refused          refused for any other mergeStateStatus, or
#                                  the `--admin` rerun was refused too (exit 0)
#   MERGE_ERROR=<reason>           bad arguments, a failed bootstrap, or a
#                                  failed or incomplete read (exit 1)
# `wait:*` means the watch keeps running: pending or failed CI is fixed or
# awaited, and the merge is tried again at the next settled approval.
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
# ONE GraphQL query reads: state, isDraft, headRefOid, mergeStateStatus, the
# last PR commit's oid and statusCheckRollup state, latestReviews (first: 100)
# with each author's login and `__typename`, the THUMBS_UP reactors (first: 100)
# with login and `__typename`, and reviewThreads (first: 100) with isResolved
# and each thread's last comment author (login and `__typename`). The comments
# and reviews connections are read as a one-node skeleton only, so the shared
# shape check sees every connection it requires.
# The body must pass hivemind_graphql_response_check
# (${CLAUDE_PLUGIN_ROOT}/skills/_shared/graphql-response.sh) and then
# hivemind_review_surface_shape_check
# (${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-surface-shape.sh). The local
# projection then type-checks every field it reads; a wrong type, an unknown
# PR state or rollup state, a headRefOid that is not a hex commit id, or a last
# commit whose oid differs from headRefOid is `MERGE_ERROR=malformed-read`.
# A READ PAST ITS PAGE FAILS CLOSED: when latestReviews, the THUMBS_UP
# reactors or reviewThreads report `hasNextPage: true`, the read is
# incomplete and the run prints `MERGE_ERROR=read-incomplete`, so no approval
# or settled verdict is ever drawn from a partial read.
# Failed reads: gh exits non-zero (`graphql-read-failed`), the envelope check
# fails (`graphql-<token>`), the shape check fails (`shape-<token>`).
#
# 5. GATES, in order (the first that applies prints its line)
# -----------------------------------------------------------
#   1. state is not OPEN                                   skipped:not-open
#   2. isDraft                                             skipped:draft
#   3. no latestReviews author and no 👍 reactor that is
#      an Automated Reviewer (`is_automated_reviewer`)
#      and matches the filter (`reviewer_matches_filter`),
#      over the set `automated_reviewer_set` derives from
#      those rows plus HIVEMIND_PR_REVIEWERS               skipped:no-approval
#   4. any thread fails `is_settled_thread`                skipped:open-threads
#   5. rollup null                                         skipped:no-checks
#   6. rollup PENDING or EXPECTED                          wait:checks-pending
#   7. rollup FAILURE or ERROR                             wait:checks-failed
#   8. rollup SUCCESS: run
#        gh pr merge <n> --repo <owner>/<repo> --<method> --match-head-commit <headRefOid>
#      exit 0                                              merged
# A plain merge that exits non-zero is REFUSED; its output is discarded. The
# script then reads the PR again through the same query and checks (§4):
#   a. headRefOid differs from the first read              wait:head-moved
#   b. mergeStateStatus is DIRTY                           skipped:conflicts
#   c. mergeStateStatus is BLOCKED or BEHIND:
#      - HIVEMIND_AUTO_MERGE_ADMIN unset or empty          skipped:blocked
#      - set, and the re-read rollup is not SUCCESS        the rollup line of
#                                                          gates 5-7
#      - set, and the re-read rollup is SUCCESS: rerun the same command with
#        `--admin` and the same `--match-head-commit`
#          exit 0                                          merged-admin
#          non-zero                                        skipped:refused
#   d. any other mergeStateStatus                          skipped:refused
# So `--admin` runs only after a refused plain merge, only with the admin
# setting set to a non-empty value, and only when both reads saw a SUCCESS
# rollup on the same head.
# Every merge call carries `--match-head-commit`, so a commit pushed after the
# read is never merged. The script NEVER passes `--auto` or `--delete-branch`,
# and never merges a head whose rollup it did not see SUCCESS.
#
# 6. IDENTITY
# -----------
# Every identity decision (Bot, self, the Automated Reviewer set, the filter
# modes, the retired filter value, the settled thread) is delegated to the
# sibling module reviewer-identity.jq, loaded by search path
# (`jq -L "$SCRIPT_DIR"`, `include "reviewer-identity"`). This script carries no
# login literal and no login compare of its own.
#
# 7. BOOTSTRAP
# ------------
# The script locates its own directory (ADR-0020 C1) and fails closed with
# `MERGE_ERROR=cannot-self-locate`; the identity module, graphql-response.sh
# and review-surface-shape.sh must be present and source cleanly
# (missing-identity-module, missing-graphql-check, unparseable-graphql-check,
# missing-review-surface-check, unparseable-review-surface-check). The
# bootstrap runs before argument checks and before any gh call.
#
# P18 floor: `set -euo pipefail`. Every expected non-zero status (gh, jq, a
# shared check) is tested by `if` or `||` and routed to merge_approved_fail or
# to a refused-merge branch, so errexit never ends a run without its one line.
#
# DEPENDENCY: bash, jq (1.6+), gh. coreutils `timeout` (or `gtimeout`) bounds
# each read when present; merge calls are never wrapped, so a merge is never
# cut off mid-flight.

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

GH_READ_TIMEOUT_SECONDS=45
GH_READ_TIMEOUT=()
if command -v timeout >/dev/null 2>&1; then
  GH_READ_TIMEOUT=(timeout "$GH_READ_TIMEOUT_SECONDS")
elif command -v gtimeout >/dev/null 2>&1; then
  GH_READ_TIMEOUT=(gtimeout "$GH_READ_TIMEOUT_SECONDS")
fi

PR_QUERY='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      state
      isDraft
      headRefOid
      mergeStateStatus
      commits(last: 1) {
        nodes { commit { oid statusCheckRollup { state } } }
      }
      comments(last: 1) { nodes { id } }
      reviews(last: 1) { nodes { id } }
      latestReviews(first: 100) {
        pageInfo { hasNextPage }
        nodes { author { login __typename } }
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
    }
  }
}'

# INVARIANT: the projection either prints one tab-separated line of eight
# fields or fails; every field it prints was type-checked first, so the bash
# gates never compare an unchecked value.
# Fields: complete, state, is_draft, head_oid, merge_state, rollup (NONE when
# null), approved, settled.
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
      | (.author // {}) | {login: .login, type: .__typename} | actor_row ] as $review_rows
  | [ $thumbs_groups[] | node_list | .[] | checked(type == "object")
      | {login: .login, type: .__typename} | actor_row ] as $thumb_rows
  | automated_reviewer_set($review_rows + $thumb_rows; $reviewers) as $set
  | any(($review_rows + $thumb_rows)[];
        is_automated_reviewer(.login; .type; $set)
        and reviewer_matches_filter(.login; .type; $self; $filter; $set)) as $approved
  | all($threads.nodes[];
        (.comments.nodes | last // {}) as $last_comment
        | ($last_comment.author // {}) as $last_author
        | is_settled_thread(.isResolved; $last_author.login; $last_author.__typename; $self)) as $settled
  | [$complete, $state, $is_draft, $head, $merge_state, $rollup, $approved, $settled]
  | map(tostring) | @tsv'

# read_pr: one read of the PR through PR_QUERY, both shared checks and the
# projection. Sets READ_COMPLETE, READ_STATE, READ_IS_DRAFT, READ_HEAD,
# READ_MERGE_STATE, READ_ROLLUP, READ_APPROVED and READ_SETTLED. Every failure,
# an incomplete read included, is merge_approved_fail.
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
    READ_ROLLUP READ_APPROVED READ_SETTLED <<<"$projected_line" \
    || merge_approved_fail "malformed-read"
  [ -n "$READ_SETTLED" ] || merge_approved_fail "malformed-read"
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
# on the head the gates read. Its output is discarded; only the exit status is
# used.
run_merge() {
  gh pr merge "$PR_NUMBER" --repo "$OWNER/$REPO" "--$MERGE_METHOD" \
    --match-head-commit "$GATED_HEAD" "$@" >/dev/null 2>&1
}

read_pr
if [ "$READ_STATE" != "OPEN" ]; then
  echo "MERGE=skipped:not-open"; exit 0
fi
if [ "$READ_IS_DRAFT" = "true" ]; then
  echo "MERGE=skipped:draft"; exit 0
fi
if [ "$READ_APPROVED" != "true" ]; then
  echo "MERGE=skipped:no-approval"; exit 0
fi
if [ "$READ_SETTLED" != "true" ]; then
  echo "MERGE=skipped:open-threads"; exit 0
fi
if [ "$READ_ROLLUP" != "SUCCESS" ]; then
  rollup_line; exit 0
fi

GATED_HEAD="$READ_HEAD"
if run_merge; then
  echo "MERGE=merged"; exit 0
fi

read_pr
if [ "$READ_HEAD" != "$GATED_HEAD" ]; then
  echo "MERGE=wait:head-moved"; exit 0
fi
case "$READ_MERGE_STATE" in
  DIRTY)
    echo "MERGE=skipped:conflicts" ;;
  BLOCKED|BEHIND)
    if [ -z "${HIVEMIND_AUTO_MERGE_ADMIN:-}" ]; then
      echo "MERGE=skipped:blocked"
    elif [ "$READ_ROLLUP" != "SUCCESS" ]; then
      rollup_line
    elif run_merge --admin; then
      echo "MERGE=merged-admin"
    else
      echo "MERGE=skipped:refused"
    fi ;;
  *)
    echo "MERGE=skipped:refused" ;;
esac
exit 0
