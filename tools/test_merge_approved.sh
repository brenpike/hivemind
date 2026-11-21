#!/usr/bin/env bash
#
# Behavioral unit runner for the opt-in merge script (ADR-0044):
#   plugin/skills/github-review-loop/scripts/merge-approved.sh
#
# OFFLINE bash TEST: no network, no real gh. A PATH-shim fake `gh` serves canned GraphQL bodies,
# one file per read (read-<n>.json, with an optional read-<n>.status exit code), and answers each
# `gh pr merge` with the exit code in merge-<n>.status (default 0). Every gh call is appended to the
# case's calls.log:
#   READ <n> head=<headRefOid> rollup=<state|NONE>      one GraphQL read served
#   MERGE <n> after_head=<h> after_rollup=<r> argv=<...> one merge call, with the head and rollup of
#                                                         the most recent read served before it
#   OTHER argv=<...>                                     any other gh call (always a failure here)
# Each case asserts the script's one stdout line, its exit status, an empty stderr, and the number
# of reads and merge calls. Fixture bodies are derived inline from one clean base body with one jq
# edit each, so a case differs from the merge-ready PR in one place.
#
# Three properties are checked over EVERY case's calls.log after the cases run:
#   - no merge call carries --auto or --delete-branch, and every merge call carries
#     --match-head-commit equal to the head of the read before it;
#   - no merge call follows a read whose rollup was not SUCCESS (no path merges on a non-SUCCESS
#     rollup);
#   - --admin appears only as the second merge call of a case, after a refused plain merge, with
#     HIVEMIND_AUTO_MERGE_ADMIN set, on the same head as the plain merge.
#
# Scratch space comes from tools/lib/scratch.sh (make_scratch_dir), removed on EXIT.
#
# Usage:
#   ./tools/test_merge_approved.sh

set -u

unset HIVEMIND_AUTO_MERGE HIVEMIND_AUTO_MERGE_ADMIN HIVEMIND_PR_REVIEWERS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
MERGE_APPROVED="$REPO_ROOT/plugin/skills/github-review-loop/scripts/merge-approved.sh"

[ -f "$MERGE_APPROVED" ] || { echo "FAIL: script under test missing: $MERGE_APPROVED" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: required dependency 'jq' is not installed" >&2; exit 2; }

make_scratch_dir TMPDIR_TEST
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

SHIM_DIR="$TMPDIR_TEST/shim"
CASES_DIR="$TMPDIR_TEST/cases"
mkdir -p "$SHIM_DIR" "$CASES_DIR"

cat >"$SHIM_DIR/gh" <<'EOF'
#!/usr/bin/env bash
case_dir="${FIXTURE_CASE_DIR:?}"
calls_log="$case_dir/calls.log"
next_count() {
  local counter_file="$case_dir/$1.count" count=0
  [ -f "$counter_file" ] && count="$(cat "$counter_file")"
  count=$((count + 1))
  printf '%s' "$count" >"$counter_file"
  printf '%s' "$count"
}
if [ "${1:-}" = "api" ] && [ "${2:-}" = "graphql" ]; then
  read_number="$(next_count read)"
  body_file="$case_dir/read-$read_number.json"
  [ -f "$body_file" ] || body_file="$case_dir/read-1.json"
  read_status=0
  [ -f "$case_dir/read-$read_number.status" ] && read_status="$(cat "$case_dir/read-$read_number.status")"
  read_head="$(jq -r 'try .data.repository.pullRequest.headRefOid catch "none"' "$body_file" 2>/dev/null)"
  read_rollup="$(jq -r 'try (.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.state // "NONE") catch "none"' "$body_file" 2>/dev/null)"
  printf 'READ %s head=%s rollup=%s\n' "$read_number" "$read_head" "$read_rollup" >>"$calls_log"
  printf '%s %s\n' "$read_head" "$read_rollup" >"$case_dir/last-read"
  cat "$body_file"
  echo "gh: stub stderr line" >&2
  exit "$read_status"
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "merge" ]; then
  merge_number="$(next_count merge)"
  read -r after_head after_rollup <"$case_dir/last-read"
  printf 'MERGE %s after_head=%s after_rollup=%s argv=%s\n' "$merge_number" "$after_head" "$after_rollup" "$*" >>"$calls_log"
  merge_status=0
  [ -f "$case_dir/merge-$merge_number.status" ] && merge_status="$(cat "$case_dir/merge-$merge_number.status")"
  echo "stub merge output"
  echo "stub merge diagnostic" >&2
  exit "$merge_status"
fi
printf 'OTHER argv=%s\n' "$*" >>"$calls_log"
exit 97
EOF
chmod +x "$SHIM_DIR/gh"

HEAD_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
HEAD_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
BOT_LOGIN="review-helper[bot]"
SELF="operator"

# The merge-ready PR: open, not a draft, head HEAD_A, CLEAN, rollup SUCCESS, one latest review from
# a Bot, an empty THUMBS_UP group, and one resolved thread whose last comment is the Bot's.
BASE_BODY="$(jq -n -c --arg head "$HEAD_A" --arg bot "$BOT_LOGIN" '{data: {repository: {pullRequest: {
  state: "OPEN", isDraft: false, headRefOid: $head, mergeStateStatus: "CLEAN",
  commits: {nodes: [{commit: {oid: $head, statusCheckRollup: {state: "SUCCESS"}}}]},
  comments: {nodes: [{id: "IC_1"}]},
  reviews: {nodes: [{id: "PRR_1"}]},
  latestReviews: {pageInfo: {hasNextPage: false}, nodes: [{author: {login: $bot, __typename: "Bot"}}]},
  reactionGroups: [
    {content: "THUMBS_UP", reactors: {pageInfo: {hasNextPage: false}, nodes: []}},
    {content: "HEART", reactors: {pageInfo: {hasNextPage: false}, nodes: []}}
  ],
  reviewThreads: {pageInfo: {hasNextPage: false}, nodes: [
    {isResolved: true, comments: {nodes: [{author: {login: $bot, __typename: "Bot"}}]}}
  ]}
}}}}')"
PR='.data.repository.pullRequest'

# new_case <name>: create and print a fresh case directory.
new_case() {
  local case_dir="$CASES_DIR/$1"
  mkdir -p "$case_dir"
  : >"$case_dir/calls.log"
  printf '%s' "$case_dir"
}

# write_read <case_dir> <n> <jq-edit>: write read-<n>.json as the base body after one jq edit. A
# broken edit aborts the run, so no case can pass on a fixture that never built.
write_read() {
  if ! jq -c --arg head_b "$HEAD_B" --arg bot "$BOT_LOGIN" --arg self "$SELF" "$3" \
      <<<"$BASE_BODY" >"$1/read-$2.json" 2>/dev/null; then
    echo "FAIL: fixture edit failed to build: $3" >&2
    exit 2
  fi
}

# run_case <case_dir> <env-assignment|command word>...: run the given command through `env` with
# the shim first on PATH and the case dir as cwd; sets CASE_OUT, CASE_STATUS and CASE_ERR.
run_case() {
  local case_dir="$1"
  shift
  CASE_OUT="$(cd "$case_dir" && env PATH="$SHIM_DIR:$PATH" FIXTURE_CASE_DIR="$case_dir" "$@" 2>"$case_dir/stderr")"
  CASE_STATUS=$?
  CASE_ERR="$(cat "$case_dir/stderr")"
}

# count_calls <case_dir> <READ|MERGE|OTHER>: print how many calls of that kind the case made.
count_calls() {
  grep -c "^$2 " "$1/calls.log"
}

# expect_case <name> <case_dir> <line> <status> <reads> <merges>: assert the last run_case.
expect_case() {
  local case_name="$1" case_dir="$2" want_line="$3" want_status="$4" want_reads="$5" want_merges="$6"
  local got_reads got_merges got_other
  got_reads="$(count_calls "$case_dir" READ)"
  got_merges="$(count_calls "$case_dir" MERGE)"
  got_other="$(count_calls "$case_dir" OTHER)"
  if [ "$CASE_OUT" = "$want_line" ] && [ "$CASE_STATUS" -eq "$want_status" ] && [ -z "$CASE_ERR" ] \
     && [ "$got_reads" -eq "$want_reads" ] && [ "$got_merges" -eq "$want_merges" ] && [ "$got_other" -eq 0 ]; then
    pass "$case_name" "$want_line rc=$want_status reads=$want_reads merges=$want_merges"
  else
    failed "$case_name" "out='$CASE_OUT' rc=$CASE_STATUS err='$CASE_ERR' reads=$got_reads merges=$got_merges other=$got_other (want '$want_line' rc=$want_status reads=$want_reads merges=$want_merges)"
  fi
}

# gate_case <name> <jq-edit> <line> <merges> [env...]: one read of the edited base body with
# HIVEMIND_AUTO_MERGE=squash plus any extra env, default arguments.
gate_case() {
  local case_name="$1" fixture_edit="$2" want_line="$3" want_merges="$4" case_dir
  shift 4
  case_dir="$(new_case "$case_name")"
  write_read "$case_dir" 1 "$fixture_edit"
  run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash "$@" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "$case_name" "$case_dir" "$want_line" 0 1 "$want_merges"
}

# ── Setting gate: no gh call ─────────────────────────────────────────────────
case_dir="$(new_case setting-unset)"
run_case "$case_dir" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "setting:unset-off-zero-gh" "$case_dir" "MERGE=off" 0 0 0

case_dir="$(new_case setting-empty)"
run_case "$case_dir" HIVEMIND_AUTO_MERGE= HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "setting:empty-off-zero-gh" "$case_dir" "MERGE=off" 0 0 0

for bad_setting in fast MERGE "squash " auto; do
  case_dir="$(new_case "setting-bad-${bad_setting// /_}")"
  run_case "$case_dir" HIVEMIND_AUTO_MERGE="$bad_setting" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "setting:bad-'$bad_setting'-zero-gh" "$case_dir" "MERGE=skipped:bad-setting" 0 0 0
done

# ── Argument checks: MERGE_ERROR, exit 1, no gh call ─────────────────────────
# arg_case <name> <reason> <arg>...: the arguments are checked before the setting and before gh.
arg_case() {
  local case_name="$1" want_reason="$2" case_dir
  shift 2
  case_dir="$(new_case "$case_name")"
  run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash bash "$MERGE_APPROVED" "$@"
  expect_case "$case_name" "$case_dir" "MERGE_ERROR=$want_reason" 1 0 0
}
arg_case "args:none"              bad-arguments
arg_case "args:four"              bad-arguments o r 5 automated
arg_case "args:six"               bad-arguments o r 5 automated "$SELF" extra
arg_case "args:owner-empty"       bad-owner "" r 5 automated "$SELF"
arg_case "args:owner-leading-dash" bad-owner -o r 5 automated "$SELF"
arg_case "args:owner-slash"       bad-owner o/x r 5 automated "$SELF"
arg_case "args:owner-double-dash" bad-owner o--x r 5 automated "$SELF"
arg_case "args:owner-too-long"    bad-owner "$(printf 'o%.0s' {1..40})" r 5 automated "$SELF"
arg_case "args:repo-dotdot"       bad-repo o .. 5 automated "$SELF"
arg_case "args:repo-dot"          bad-repo o . 5 automated "$SELF"
arg_case "args:repo-space"        bad-repo o "r x" 5 automated "$SELF"
arg_case "args:repo-slash"        bad-repo o r/x 5 automated "$SELF"
arg_case "args:pr-zero"           bad-pr-number o r 0 automated "$SELF"
arg_case "args:pr-leading-zero"   bad-pr-number o r 05 automated "$SELF"
arg_case "args:pr-word"           bad-pr-number o r five automated "$SELF"
arg_case "args:pr-flag"           bad-pr-number o r --admin automated "$SELF"
arg_case "args:self-empty"        missing-self-login o r 5 automated ""
arg_case "args:retired-filter"    retired-filter o r 5 codex-only "$SELF"

case_dir="$(new_case args-bad-before-off)"
run_case "$case_dir" bash "$MERGE_APPROVED" o r 0 automated "$SELF"
expect_case "args:checked-before-setting" "$case_dir" "MERGE_ERROR=bad-pr-number" 1 0 0

case_dir="$(new_case args-empty-filter-defaults)"
write_read "$case_dir" 1 '.'
run_case "$case_dir" HIVEMIND_AUTO_MERGE=merge bash "$MERGE_APPROVED" o r 5 "" "$SELF"
expect_case "args:empty-filter-is-automated" "$case_dir" "MERGE=merged" 0 1 1

# ── Gates in order ───────────────────────────────────────────────────────────
gate_case "gate:not-open-closed"  "$PR.state = \"CLOSED\""   "MERGE=skipped:not-open" 0
gate_case "gate:not-open-merged"  "$PR.state = \"MERGED\""   "MERGE=skipped:not-open" 0
gate_case "gate:not-open-before-draft" "$PR.state = \"CLOSED\" | $PR.isDraft = true" "MERGE=skipped:not-open" 0
gate_case "gate:draft"            "$PR.isDraft = true"       "MERGE=skipped:draft" 0
gate_case "gate:draft-before-approval" "$PR.isDraft = true | $PR.latestReviews.nodes = []" "MERGE=skipped:draft" 0

gate_case "approval:none"         "$PR.latestReviews.nodes = []"   "MERGE=skipped:no-approval" 0
gate_case "approval:human-review" "$PR.latestReviews.nodes = [{author: {login: \"alice\", __typename: \"User\"}}]" \
  "MERGE=skipped:no-approval" 0
gate_case "approval:human-review-bot-suffix-typed-user" \
  "$PR.latestReviews.nodes = [{author: {login: \"helper[bot]\", __typename: \"User\"}}]" "MERGE=merged" 1
gate_case "approval:null-author"  "$PR.latestReviews.nodes = [{author: null}]" "MERGE=skipped:no-approval" 0
gate_case "approval:bot-self-login-is-reviewer" \
  "$PR.latestReviews.nodes = [{author: {login: \$self, __typename: \"Bot\"}}]" "MERGE=merged" 1
gate_case "approval:self-user-review" \
  "$PR.latestReviews.nodes = [{author: {login: \$self, __typename: \"User\"}}]" "MERGE=skipped:no-approval" 0
gate_case "approval:github-actions-unconfigured" \
  "$PR.latestReviews.nodes = [{author: {login: \"github-actions[bot]\", __typename: \"Bot\"}}]" "MERGE=skipped:no-approval" 0
gate_case "approval:github-actions-configured" \
  "$PR.latestReviews.nodes = [{author: {login: \"github-actions[bot]\", __typename: \"Bot\"}}]" "MERGE=merged" 1 \
  HIVEMIND_PR_REVIEWERS=github-actions
gate_case "approval:thumbs-up-bot" \
  "$PR.latestReviews.nodes = [] | $PR.reactionGroups[0].reactors.nodes = [{__typename: \"Bot\", login: \$bot}]" "MERGE=merged" 1
gate_case "approval:thumbs-up-human" \
  "$PR.latestReviews.nodes = [] | $PR.reactionGroups[0].reactors.nodes = [{__typename: \"User\", login: \"alice\"}]" \
  "MERGE=skipped:no-approval" 0
gate_case "approval:heart-bot-not-approval" \
  "$PR.latestReviews.nodes = [] | $PR.reactionGroups[1].reactors.nodes = [{__typename: \"Bot\", login: \$bot}]" \
  "MERGE=skipped:no-approval" 0

case_dir="$(new_case approval-login-filter-other)"
write_read "$case_dir" 1 '.'
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash bash "$MERGE_APPROVED" o r 5 other-bot "$SELF"
expect_case "approval:login-filter-other-bot" "$case_dir" "MERGE=skipped:no-approval" 0 1 0

case_dir="$(new_case approval-login-filter-match)"
write_read "$case_dir" 1 '.'
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash bash "$MERGE_APPROVED" o r 5 review-helper "$SELF"
expect_case "approval:login-filter-match" "$case_dir" "MERGE=merged" 0 1 1

case_dir="$(new_case approval-filter-all-human)"
write_read "$case_dir" 1 "$PR.latestReviews.nodes = [{author: {login: \"alice\", __typename: \"User\"}}]"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash bash "$MERGE_APPROVED" o r 5 all "$SELF"
expect_case "approval:filter-all-still-needs-automated" "$case_dir" "MERGE=skipped:no-approval" 0 1 0

gate_case "threads:none"          "$PR.reviewThreads.nodes = []" "MERGE=merged" 1
gate_case "threads:unresolved-bot-last" "$PR.reviewThreads.nodes[0].isResolved = false" "MERGE=skipped:open-threads" 0
gate_case "threads:unresolved-self-last" \
  "$PR.reviewThreads.nodes[0].isResolved = false | $PR.reviewThreads.nodes[0].comments.nodes += [{author: {login: \$self, __typename: \"User\"}}]" \
  "MERGE=merged" 1
gate_case "threads:unresolved-bot-with-self-login-last" \
  "$PR.reviewThreads.nodes[0].isResolved = false | $PR.reviewThreads.nodes[0].comments.nodes = [{author: {login: \$self, __typename: \"Bot\"}}]" \
  "MERGE=skipped:open-threads" 0
gate_case "threads:resolved-null"  "$PR.reviewThreads.nodes[0].isResolved = null" "MERGE=skipped:open-threads" 0
gate_case "threads:unresolved-no-comments" \
  "$PR.reviewThreads.nodes[0].isResolved = false | $PR.reviewThreads.nodes[0].comments.nodes = []" "MERGE=skipped:open-threads" 0
gate_case "threads:unresolved-null-author" \
  "$PR.reviewThreads.nodes[0].isResolved = false | $PR.reviewThreads.nodes[0].comments.nodes = [{author: null}]" \
  "MERGE=skipped:open-threads" 0
gate_case "threads:one-open-of-two" \
  "$PR.reviewThreads.nodes += [{isResolved: false, comments: {nodes: [{author: {login: \"alice\", __typename: \"User\"}}]}}]" \
  "MERGE=skipped:open-threads" 0
gate_case "threads:before-checks" \
  "$PR.reviewThreads.nodes[0].isResolved = false | $PR.commits.nodes[0].commit.statusCheckRollup = null" \
  "MERGE=skipped:open-threads" 0

# Every non-SUCCESS rollup merges nothing, with the admin setting set too.
gate_case "checks:none"     "$PR.commits.nodes[0].commit.statusCheckRollup = null"            "MERGE=skipped:no-checks" 0 HIVEMIND_AUTO_MERGE_ADMIN=1
gate_case "checks:pending"  "$PR.commits.nodes[0].commit.statusCheckRollup.state = \"PENDING\""  "MERGE=wait:checks-pending" 0 HIVEMIND_AUTO_MERGE_ADMIN=1
gate_case "checks:expected" "$PR.commits.nodes[0].commit.statusCheckRollup.state = \"EXPECTED\"" "MERGE=wait:checks-pending" 0 HIVEMIND_AUTO_MERGE_ADMIN=1
gate_case "checks:failure"  "$PR.commits.nodes[0].commit.statusCheckRollup.state = \"FAILURE\""  "MERGE=wait:checks-failed" 0 HIVEMIND_AUTO_MERGE_ADMIN=1
gate_case "checks:error"    "$PR.commits.nodes[0].commit.statusCheckRollup.state = \"ERROR\""    "MERGE=wait:checks-failed" 0 HIVEMIND_AUTO_MERGE_ADMIN=1

# ── Merge on SUCCESS: exact command per method ───────────────────────────────
for merge_method in merge squash rebase; do
  case_dir="$(new_case "merge-$merge_method")"
  write_read "$case_dir" 1 '.'
  run_case "$case_dir" HIVEMIND_AUTO_MERGE="$merge_method" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "merge:$merge_method" "$case_dir" "MERGE=merged" 0 1 1
  want_argv="pr merge 5 --repo o/r --$merge_method --match-head-commit $HEAD_A"
  if grep -qxF "MERGE 1 after_head=$HEAD_A after_rollup=SUCCESS argv=$want_argv" "$case_dir/calls.log"; then
    pass "merge:$merge_method-argv" "$want_argv"
  else
    failed "merge:$merge_method-argv" "calls: $(tr '\n' '|' <"$case_dir/calls.log")"
  fi
done

case_dir="$(new_case merge-admin-set-plain-succeeds)"
write_read "$case_dir" 1 '.'
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "merge:admin-set-plain-first" "$case_dir" "MERGE=merged" 0 1 1

# ── Failed and incomplete reads ──────────────────────────────────────────────
# read_error_case <name> <jq-edit> <reason>: one read, MERGE_ERROR=<reason>, exit 1, no merge.
read_error_case() {
  local case_name="$1" fixture_edit="$2" want_reason="$3" case_dir
  case_dir="$(new_case "$case_name")"
  write_read "$case_dir" 1 "$fixture_edit"
  run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "$case_name" "$case_dir" "MERGE_ERROR=$want_reason" 1 1 0
}
read_error_case "read:reviews-next-page"   "$PR.latestReviews.pageInfo.hasNextPage = true"               read-incomplete
read_error_case "read:thumbs-next-page"    "$PR.reactionGroups[0].reactors.pageInfo.hasNextPage = true"  read-incomplete
read_error_case "read:threads-next-page"   "$PR.reviewThreads.pageInfo.hasNextPage = true"               read-incomplete
read_error_case "read:second-thumbs-group-next-page" "$PR.reactionGroups[1].reactors.pageInfo.hasNextPage = true | $PR.reactionGroups[1].content = \"THUMBS_UP\"" read-incomplete
read_error_case "read:errors-envelope"     '. + {errors: [{message: "boom"}]}'                           graphql-errors
read_error_case "read:data-null"           '.data = null'                                                graphql-missing-data
read_error_case "read:pullrequest-null"    "$PR = null"                                                  shape-null-pullrequest
read_error_case "read:threads-lost"        "del($PR.reviewThreads)"                                      shape-missing-connection
read_error_case "read:unknown-state"       "$PR.state = \"OPENED\""                                      malformed-read
read_error_case "read:draft-null"          "$PR.isDraft = null"                                          malformed-read
read_error_case "read:head-not-hex"        "$PR.headRefOid = \"main\""                                   malformed-read
read_error_case "read:head-commit-mismatch" "$PR.commits.nodes[0].commit.oid = \$head_b"                 malformed-read
read_error_case "read:no-commit"           "$PR.commits.nodes = []"                                      malformed-read
read_error_case "read:unknown-rollup"      "$PR.commits.nodes[0].commit.statusCheckRollup.state = \"NEUTRAL\"" malformed-read
read_error_case "read:merge-state-null"    "$PR.mergeStateStatus = null"                                 malformed-read
read_error_case "read:page-flag-null"      "$PR.reviewThreads.pageInfo = null"                           malformed-read
read_error_case "read:reaction-groups-null" "$PR.reactionGroups = null"                                  malformed-read

gate_case "read:other-group-next-page-ignored" "$PR.reactionGroups[1].reactors.pageInfo.hasNextPage = true" "MERGE=merged" 1

case_dir="$(new_case read-gh-exit)"
write_read "$case_dir" 1 '.'
printf '1' >"$case_dir/read-1.status"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "read:gh-nonzero" "$case_dir" "MERGE_ERROR=graphql-read-failed" 1 1 0

case_dir="$(new_case read-empty-body)"
: >"$case_dir/read-1.json"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "read:empty-body" "$case_dir" "MERGE_ERROR=graphql-empty-body" 1 1 0

# ── Refused plain merge: second read decides ─────────────────────────────────
# refused_case <name> <second-read-edit> <line> <merges> [env...]: the plain merge exits 1, the
# second read is the base body after the edit; an admin rerun, when reached, exits 0.
refused_case() {
  local case_name="$1" fixture_edit="$2" want_line="$3" want_merges="$4" case_dir
  shift 4
  case_dir="$(new_case "$case_name")"
  write_read "$case_dir" 1 '.'
  write_read "$case_dir" 2 "$fixture_edit"
  printf '1' >"$case_dir/merge-1.status"
  run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash "$@" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "$case_name" "$case_dir" "$want_line" 0 2 "$want_merges"
}
refused_case "refused:head-moved" \
  "$PR.headRefOid = \$head_b | $PR.commits.nodes[0].commit.oid = \$head_b | $PR.mergeStateStatus = \"BLOCKED\"" \
  "MERGE=wait:head-moved" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:dirty"            "$PR.mergeStateStatus = \"DIRTY\""   "MERGE=skipped:conflicts" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-no-admin" "$PR.mergeStateStatus = \"BLOCKED\"" "MERGE=skipped:blocked" 1
refused_case "refused:behind-no-admin"  "$PR.mergeStateStatus = \"BEHIND\""  "MERGE=skipped:blocked" 1
refused_case "refused:blocked-admin"    "$PR.mergeStateStatus = \"BLOCKED\"" "MERGE=merged-admin" 2 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:behind-admin"     "$PR.mergeStateStatus = \"BEHIND\""  "MERGE=merged-admin" 2 HIVEMIND_AUTO_MERGE_ADMIN=
refused_case "refused:blocked-admin-checks-failed" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.commits.nodes[0].commit.statusCheckRollup.state = \"FAILURE\"" \
  "MERGE=wait:checks-failed" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-checks-pending" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.commits.nodes[0].commit.statusCheckRollup.state = \"PENDING\"" \
  "MERGE=wait:checks-pending" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-no-checks" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.commits.nodes[0].commit.statusCheckRollup = null" \
  "MERGE=skipped:no-checks" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:clean-admin-set"  "$PR.mergeStateStatus = \"CLEAN\""   "MERGE=skipped:refused" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:unstable"         "$PR.mergeStateStatus = \"UNSTABLE\"" "MERGE=skipped:refused" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:unknown"          "$PR.mergeStateStatus = \"UNKNOWN\"" "MERGE=skipped:refused" 1 HIVEMIND_AUTO_MERGE_ADMIN=1

case_dir="$(new_case refused-admin-refused)"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 "$PR.mergeStateStatus = \"BLOCKED\""
printf '1' >"$case_dir/merge-1.status"
printf '1' >"$case_dir/merge-2.status"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=rebase HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "refused:admin-refused" "$case_dir" "MERGE=skipped:refused" 0 2 2

case_dir="$(new_case refused-reread-fails)"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 '. + {errors: [{message: "boom"}]}'
printf '1' >"$case_dir/merge-1.status"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "refused:reread-fails" "$case_dir" "MERGE_ERROR=graphql-errors" 1 2 1

case_dir="$(new_case refused-reread-incomplete)"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 "$PR.mergeStateStatus = \"BLOCKED\" | $PR.reviewThreads.pageInfo.hasNextPage = true"
printf '1' >"$case_dir/merge-1.status"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "refused:reread-incomplete" "$case_dir" "MERGE_ERROR=read-incomplete" 1 2 1

for admin_case in refused:blocked-admin refused:behind-admin; do
  case_dir="$CASES_DIR/$admin_case"
  want_admin="MERGE 2 after_head=$HEAD_A after_rollup=SUCCESS argv=pr merge 5 --repo o/r --squash --match-head-commit $HEAD_A --admin"
  if grep -qxF "$want_admin" "$case_dir/calls.log"; then
    pass "$admin_case-argv" "admin rerun keeps --match-head-commit $HEAD_A"
  else
    failed "$admin_case-argv" "calls: $(tr '\n' '|' <"$case_dir/calls.log")"
  fi
done

# ── Properties over every case ───────────────────────────────────────────────
merge_call_count=0
for calls_log in "$CASES_DIR"/*/calls.log; do
  case_name="$(basename "$(dirname "$calls_log")")"
  case_env_admin="no"
  case "$case_name" in
    refused:blocked-admin|refused:behind-admin|refused-admin-refused) case_env_admin="yes" ;;
  esac
  while IFS= read -r call_line; do
    case "$call_line" in MERGE\ *) ;; *) continue ;; esac
    merge_call_count=$((merge_call_count + 1))
    merge_number="${call_line#MERGE }"
    merge_number="${merge_number%% *}"
    after_head="${call_line#*after_head=}"
    after_head="${after_head%% *}"
    after_rollup="${call_line#*after_rollup=}"
    after_rollup="${after_rollup%% *}"
    merge_argv="${call_line#*argv=}"
    case " $merge_argv " in
      *" --auto "*|*" --delete-branch "*) failed "property:no-auto-delete" "$case_name: $call_line" ;;
    esac
    case " $merge_argv " in
      *" --match-head-commit $after_head "*) ;;
      *) failed "property:match-head-commit" "$case_name: $call_line" ;;
    esac
    [ "$after_rollup" = "SUCCESS" ] || failed "property:merge-only-on-success" "$case_name: $call_line"
    case " $merge_argv " in
      *" --admin "*)
        if [ "$merge_number" != "2" ] || [ "$case_env_admin" != "yes" ] \
           || ! grep -q "^MERGE 1 after_head=$after_head after_rollup=SUCCESS argv=.* --match-head-commit $after_head$" "$calls_log"; then
          failed "property:admin-only-after-refusal" "$case_name: $call_line"
        fi ;;
    esac
  done <"$calls_log"
done
if [ "$merge_call_count" -gt 0 ]; then
  pass "property:scan-non-vacuous" "$merge_call_count merge calls scanned for --auto, --delete-branch, --match-head-commit, SUCCESS-only and --admin placement"
else
  failed "property:scan-non-vacuous" "no merge call recorded in any case"
fi

echo ''
echo "test_merge_approved: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
