#!/usr/bin/env bash
#
# Behavioral unit runner for the opt-in merge script (ADR-0044):
#   plugin/skills/github-review-loop/scripts/merge-approved.sh
#
# OFFLINE bash TEST: no network, no real gh. A PATH-shim fake `gh` serves canned GraphQL bodies,
# one file per read (read-<n>.json, with an optional read-<n>.status exit code), and answers each
# `gh pr merge` with the exit code in merge-<n>.status (default 0). Every gh call is appended to the
# case's calls.log:
#   READ <n> state=<state> head=<headRefOid> rollup=<state|NONE> reviews=<states|NONE>
#                                  one GraphQL read served; state is the PR state, reviews is the
#                                  comma-joined state of every latestReviews node, in order
#   MERGE <n> after_head=<h> after_rollup=<r> after_reviews=<s> argv=<...>
#                                  one merge call, with the head, rollup and review states of the
#                                  most recent read served before it
#   OTHER argv=<...>               any other gh call (always a failure here)
# A PATH-shim fake `git` runs the real git and appends `GIT argv=<...>` per call. On `fetch` it adds
# a `url.<fixture server>.insteadOf=<the remote's URL>` setting, so the named remote's configured
# URL is fetched from a local bare fixture repository; FIXTURE_GIT_FAIL=<subcommand> makes that
# subcommand exit 1. The record cases run in a case directory that is a git repository whose
# remote names the PR's repository; every other case's directory is not, and must make no git call.
# Each case asserts the script's one stdout line, its exit status, an empty stderr, and the number
# of reads and merge calls; its stdout line is also kept in the case's stdout file. Fixture bodies
# are derived inline from one clean base body with one jq edit each, so a case differs from the
# merge-ready PR in one place. A merge call that exits 0 is followed by the confirm read, so a case
# that expects merged or merged-admin serves one more read, the base body with state MERGED.
# HIVEMIND_AUTO_MERGE_REREAD_DELAY is exported as 0, so the re-reads of an UNKNOWN mergeStateStatus
# after a refused merge run without a wait; the delay cases set their own value.
#
# Five properties are checked over EVERY case after the cases run:
#   - no merge call carries --auto or --delete-branch, and every merge call carries
#     --match-head-commit equal to the head of the read before it;
#   - no merge call follows a read whose rollup was not SUCCESS (no path merges on a non-SUCCESS
#     rollup);
#   - no merge call follows a read holding a review state outside APPROVED, COMMENTED or
#     DISMISSED (no path merges over a standing block);
#   - --admin appears only as the second merge call of a case, after a refused plain merge, with
#     HIVEMIND_AUTO_MERGE_ADMIN set to a non-empty value, on the same head as the plain merge;
#   - a merged or merged-admin line requires the case's last call to be a READ showing
#     state=MERGED, after its last merge call;
#   - a case outside the record cases makes no git call.
#
# Scratch space comes from tools/lib/scratch.sh (make_scratch_dir), removed on EXIT.
#
# Usage:
#   ./tools/test_merge_approved.sh

set -u

unset HIVEMIND_AUTO_MERGE HIVEMIND_AUTO_MERGE_ADMIN HIVEMIND_PR_REVIEWERS GH_HOST
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
export HIVEMIND_AUTO_MERGE_REREAD_DELAY=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
MERGE_APPROVED="$REPO_ROOT/plugin/skills/github-review-loop/scripts/merge-approved.sh"

[ -f "$MERGE_APPROVED" ] || { echo "FAIL: script under test missing: $MERGE_APPROVED" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: required dependency 'jq' is not installed" >&2; exit 2; }
REAL_GIT="$(command -v git)" || { echo "FAIL: required dependency 'git' is not installed" >&2; exit 2; }

make_scratch_dir TMPDIR_TEST
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT
mkdir -p "$TMPDIR_TEST/home"
export HOME="$TMPDIR_TEST/home" GIT_CONFIG_NOSYSTEM=1

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
  read_reviews="$(jq -r 'try ([.data.repository.pullRequest.latestReviews.nodes[]? | .state | tostring] | if length == 0 then "NONE" else join(",") end) catch "none"' "$body_file" 2>/dev/null)"
  read_state="$(jq -r 'try (.data.repository.pullRequest.state // "NONE" | tostring) catch "none"' "$body_file" 2>/dev/null)"
  printf 'READ %s state=%s head=%s rollup=%s reviews=%s\n' "$read_number" "$read_state" "$read_head" "$read_rollup" "$read_reviews" >>"$calls_log"
  printf '%s %s %s\n' "$read_head" "$read_rollup" "$read_reviews" >"$case_dir/last-read"
  cat "$body_file"
  echo "gh: stub stderr line" >&2
  exit "$read_status"
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "merge" ]; then
  merge_number="$(next_count merge)"
  read -r after_head after_rollup after_reviews <"$case_dir/last-read"
  printf 'MERGE %s after_head=%s after_rollup=%s after_reviews=%s argv=%s\n' "$merge_number" "$after_head" "$after_rollup" "$after_reviews" "$*" >>"$calls_log"
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

GIT_SERVER="$TMPDIR_TEST/server.git"
{
  printf '#!/usr/bin/env bash\n'
  printf 'real_git=%q\n' "$REAL_GIT"
  printf 'git_server=%q\n' "$GIT_SERVER"
  cat <<'EOF'
printf 'GIT argv=%s\n' "$*" >>"${FIXTURE_CASE_DIR:?}/calls.log"
subcommand="" skip_next=0 remote_next=0 remote_name=""
for git_arg in "$@"; do
  if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
  if [ "$remote_next" = 1 ]; then remote_name="$git_arg"; break; fi
  case "$git_arg" in
    -c|-C) skip_next=1 ;;
    --) remote_next=1 ;;
    -*) ;;
    *) [ -n "$subcommand" ] || subcommand="$git_arg" ;;
  esac
done
[ -z "${FIXTURE_GIT_FAIL:-}" ] || [ "$subcommand" != "$FIXTURE_GIT_FAIL" ] || exit 1
if [ "$subcommand" = "fetch" ] && [ -n "$remote_name" ]; then
  remote_url="$("$real_git" remote get-url "$remote_name" 2>/dev/null)" || exit 1
  exec "$real_git" -c "url.$git_server.insteadOf=$remote_url" "$@"
fi
exec "$real_git" "$@"
EOF
} >"$SHIM_DIR/git"
chmod +x "$SHIM_DIR/git"

HEAD_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
HEAD_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
BASE_A="1111111111111111111111111111111111111111"
BOT_LOGIN="review-helper[bot]"
SELF="operator"

# The merge-ready PR: open, not a draft, head HEAD_A, CLEAN, base main at BASE_A, rollup SUCCESS,
# one COMMENTED latest review from a Bot, an empty THUMBS_UP group, one resolved thread whose last
# comment is the Bot's, and one changed file outside the docs paths, so the record gate is off.
BASE_BODY="$(jq -n -c --arg head "$HEAD_A" --arg base "$BASE_A" --arg bot "$BOT_LOGIN" '{data: {repository: {pullRequest: {
  state: "OPEN", isDraft: false, headRefOid: $head, mergeStateStatus: "CLEAN",
  baseRefName: "main", baseRefOid: $base,
  commits: {nodes: [{commit: {oid: $head, statusCheckRollup: {state: "SUCCESS"}}}]},
  comments: {nodes: [{id: "IC_1"}]},
  reviews: {nodes: [{id: "PRR_1"}]},
  latestReviews: {pageInfo: {hasNextPage: false}, nodes: [{state: "COMMENTED", author: {login: $bot, __typename: "Bot"}}]},
  reactionGroups: [
    {content: "THUMBS_UP", reactors: {pageInfo: {hasNextPage: false}, nodes: []}},
    {content: "HEART", reactors: {pageInfo: {hasNextPage: false}, nodes: []}}
  ],
  reviewThreads: {pageInfo: {hasNextPage: false}, nodes: [
    {isResolved: true, comments: {nodes: [{author: {login: $bot, __typename: "Bot"}}]}}
  ]},
  files: {pageInfo: {hasNextPage: false}, nodes: [{path: "README.md", changeType: "MODIFIED"}]}
}}}}')"
PR='.data.repository.pullRequest'
# The confirm-read edit: the base body with the PR merged.
MERGED_EDIT="$PR.state = \"MERGED\""

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
# the shim first on PATH and the case dir as cwd; sets CASE_OUT, CASE_STATUS and CASE_ERR, and
# keeps CASE_OUT in the case's stdout file for the property scan.
run_case() {
  local case_dir="$1"
  shift
  CASE_OUT="$(cd "$case_dir" && env PATH="$SHIM_DIR:$PATH" FIXTURE_CASE_DIR="$case_dir" "$@" 2>"$case_dir/stderr")"
  CASE_STATUS=$?
  CASE_ERR="$(cat "$case_dir/stderr")"
  printf '%s\n' "$CASE_OUT" >"$case_dir/stdout"
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
# HIVEMIND_AUTO_MERGE=squash plus any extra env, default arguments. A case that expects merged
# also serves the confirm read, read-2 with state MERGED, and expects two reads.
gate_case() {
  local case_name="$1" fixture_edit="$2" want_line="$3" want_merges="$4" want_reads=1 case_dir
  shift 4
  case_dir="$(new_case "$case_name")"
  write_read "$case_dir" 1 "$fixture_edit"
  if [ "$want_line" = "MERGE=merged" ]; then
    write_read "$case_dir" 2 "$MERGED_EDIT"
    want_reads=2
  fi
  run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash "$@" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "$case_name" "$case_dir" "$want_line" 0 "$want_reads" "$want_merges"
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

# A re-read delay that is not 0 to 99 whole seconds fails before any gh call, after the method.
for bad_delay in abc 100 -1 "1 " 1.5; do
  case_dir="$(new_case "setting-bad-delay-${bad_delay// /_}")"
  run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_REREAD_DELAY="$bad_delay" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "setting:bad-reread-delay-'$bad_delay'-zero-gh" "$case_dir" "MERGE_ERROR=bad-reread-delay" 1 0 0
done

case_dir="$(new_case setting-bad-delay-off)"
run_case "$case_dir" HIVEMIND_AUTO_MERGE_REREAD_DELAY=abc bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "setting:bad-reread-delay-merge-off" "$case_dir" "MERGE=off" 0 0 0

case_dir="$(new_case setting-empty-delay-default)"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 "$MERGED_EDIT"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_REREAD_DELAY= bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "setting:empty-reread-delay-default" "$case_dir" "MERGE=merged" 0 2 1

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
write_read "$case_dir" 2 "$MERGED_EDIT"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=merge bash "$MERGE_APPROVED" o r 5 "" "$SELF"
expect_case "args:empty-filter-is-automated" "$case_dir" "MERGE=merged" 0 2 1

# ── Gates in order ───────────────────────────────────────────────────────────
gate_case "gate:not-open-closed"  "$PR.state = \"CLOSED\""   "MERGE=skipped:not-open" 0
gate_case "gate:not-open-merged"  "$PR.state = \"MERGED\""   "MERGE=skipped:not-open" 0
gate_case "gate:not-open-before-draft" "$PR.state = \"CLOSED\" | $PR.isDraft = true" "MERGE=skipped:not-open" 0
gate_case "gate:draft"            "$PR.isDraft = true"       "MERGE=skipped:draft" 0
gate_case "gate:draft-before-approval" "$PR.isDraft = true | $PR.latestReviews.nodes = []" "MERGE=skipped:draft" 0

gate_case "approval:none"         "$PR.latestReviews.nodes = []"   "MERGE=skipped:no-approval" 0
gate_case "approval:human-review" "$PR.latestReviews.nodes = [{state: \"COMMENTED\", author: {login: \"alice\", __typename: \"User\"}}]" \
  "MERGE=skipped:no-approval" 0
gate_case "approval:human-review-bot-suffix-typed-user" \
  "$PR.latestReviews.nodes = [{state: \"COMMENTED\", author: {login: \"helper[bot]\", __typename: \"User\"}}]" "MERGE=merged" 1
gate_case "approval:null-author"  "$PR.latestReviews.nodes = [{state: \"COMMENTED\", author: null}]" "MERGE=skipped:no-approval" 0
gate_case "approval:bot-self-login-is-reviewer" \
  "$PR.latestReviews.nodes = [{state: \"COMMENTED\", author: {login: \$self, __typename: \"Bot\"}}]" "MERGE=merged" 1
gate_case "approval:self-user-review" \
  "$PR.latestReviews.nodes = [{state: \"COMMENTED\", author: {login: \$self, __typename: \"User\"}}]" "MERGE=skipped:no-approval" 0
gate_case "approval:github-actions-unconfigured" \
  "$PR.latestReviews.nodes = [{state: \"COMMENTED\", author: {login: \"github-actions[bot]\", __typename: \"Bot\"}}]" "MERGE=skipped:no-approval" 0
gate_case "approval:github-actions-configured" \
  "$PR.latestReviews.nodes = [{state: \"COMMENTED\", author: {login: \"github-actions[bot]\", __typename: \"Bot\"}}]" "MERGE=merged" 1 \
  HIVEMIND_PR_REVIEWERS=github-actions
gate_case "approval:thumbs-up-bot" \
  "$PR.latestReviews.nodes = [] | $PR.reactionGroups[0].reactors.nodes = [{__typename: \"Bot\", login: \$bot}]" "MERGE=merged" 1
gate_case "approval:thumbs-up-human" \
  "$PR.latestReviews.nodes = [] | $PR.reactionGroups[0].reactors.nodes = [{__typename: \"User\", login: \"alice\"}]" \
  "MERGE=skipped:no-approval" 0
gate_case "approval:heart-bot-not-approval" \
  "$PR.latestReviews.nodes = [] | $PR.reactionGroups[1].reactors.nodes = [{__typename: \"Bot\", login: \$bot}]" \
  "MERGE=skipped:no-approval" 0

# Approval is keyed on review state: every latest review, of any author, must be APPROVED, COMMENTED
# or DISMISSED, and a Bot APPROVED or COMMENTED review or a Bot thumbs-up must be present.
BOT_THUMBS_UP="$PR.reactionGroups[0].reactors.nodes = [{__typename: \"Bot\", login: \$bot}]"
gate_case "approval:bot-approved"  "$PR.latestReviews.nodes[0].state = \"APPROVED\""  "MERGE=merged" 1
gate_case "approval:bot-commented" "$PR.latestReviews.nodes[0].state = \"COMMENTED\"" "MERGE=merged" 1
gate_case "approval:bot-changes-requested" \
  "$PR.latestReviews.nodes[0].state = \"CHANGES_REQUESTED\"" "MERGE=skipped:no-approval" 0
gate_case "approval:bot-changes-requested-admin" \
  "$PR.latestReviews.nodes[0].state = \"CHANGES_REQUESTED\"" "MERGE=skipped:no-approval" 0 HIVEMIND_AUTO_MERGE_ADMIN=1
gate_case "approval:bot-changes-requested-bot-thumbs-up" \
  "$PR.latestReviews.nodes[0].state = \"CHANGES_REQUESTED\" | $BOT_THUMBS_UP" "MERGE=skipped:no-approval" 0
gate_case "approval:bot-changes-requested-bot-thumbs-up-admin" \
  "$PR.latestReviews.nodes[0].state = \"CHANGES_REQUESTED\" | $BOT_THUMBS_UP" "MERGE=skipped:no-approval" 0 \
  HIVEMIND_AUTO_MERGE_ADMIN=1
gate_case "approval:human-changes-requested-blocks-bot-approval" \
  "$PR.latestReviews.nodes[0].state = \"APPROVED\" | $PR.latestReviews.nodes += [{state: \"CHANGES_REQUESTED\", author: {login: \"alice\", __typename: \"User\"}}]" \
  "MERGE=skipped:no-approval" 0
gate_case "approval:null-author-changes-requested-blocks-bot-approval" \
  "$PR.latestReviews.nodes[0].state = \"APPROVED\" | $PR.latestReviews.nodes += [{state: \"CHANGES_REQUESTED\", author: null}]" \
  "MERGE=skipped:no-approval" 0
gate_case "approval:pending-blocks-bot-approval" \
  "$PR.latestReviews.nodes[0].state = \"APPROVED\" | $PR.latestReviews.nodes += [{state: \"PENDING\", author: {login: \"alice\", __typename: \"User\"}}]" \
  "MERGE=skipped:no-approval" 0
gate_case "approval:unknown-state-blocks-bot-approval" \
  "$PR.latestReviews.nodes[0].state = \"APPROVED\" | $PR.latestReviews.nodes += [{state: \"REVIEW_STATE_FROM_THE_FUTURE\", author: {login: \"alice\", __typename: \"User\"}}]" \
  "MERGE=skipped:no-approval" 0
gate_case "approval:bot-dismissed-alone" \
  "$PR.latestReviews.nodes[0].state = \"DISMISSED\"" "MERGE=skipped:no-approval" 0
gate_case "approval:bot-dismissed-bot-thumbs-up" \
  "$PR.latestReviews.nodes[0].state = \"DISMISSED\" | $BOT_THUMBS_UP" "MERGE=merged" 1

case_dir="$(new_case approval-login-filter-other)"
write_read "$case_dir" 1 '.'
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash bash "$MERGE_APPROVED" o r 5 other-bot "$SELF"
expect_case "approval:login-filter-other-bot" "$case_dir" "MERGE=skipped:no-approval" 0 1 0

case_dir="$(new_case approval-login-filter-match)"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 "$MERGED_EDIT"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash bash "$MERGE_APPROVED" o r 5 review-helper "$SELF"
expect_case "approval:login-filter-match" "$case_dir" "MERGE=merged" 0 2 1

case_dir="$(new_case approval-filter-all-human)"
write_read "$case_dir" 1 "$PR.latestReviews.nodes = [{state: \"COMMENTED\", author: {login: \"alice\", __typename: \"User\"}}]"
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
  write_read "$case_dir" 2 "$MERGED_EDIT"
  run_case "$case_dir" HIVEMIND_AUTO_MERGE="$merge_method" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "merge:$merge_method" "$case_dir" "MERGE=merged" 0 2 1
  want_argv="pr merge 5 --repo o/r --$merge_method --match-head-commit $HEAD_A"
  if grep -qxF "MERGE 1 after_head=$HEAD_A after_rollup=SUCCESS after_reviews=COMMENTED argv=$want_argv" "$case_dir/calls.log"; then
    pass "merge:$merge_method-argv" "$want_argv"
  else
    failed "merge:$merge_method-argv" "calls: $(tr '\n' '|' <"$case_dir/calls.log")"
  fi
done

case_dir="$(new_case merge-admin-set-plain-succeeds)"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 "$MERGED_EDIT"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "merge:admin-set-plain-first" "$case_dir" "MERGE=merged" 0 2 1

# ── Confirm read: a merge call that exits 0 is not the verdict ───────────────
# confirm_case <name> <confirm-read-edit> <line> <status> [env...]: the plain merge exits 0 and the
# confirm read, read-2, is the base body after the edit; two reads, one merge call.
confirm_case() {
  local case_name="$1" fixture_edit="$2" want_line="$3" want_status="$4" case_dir
  shift 4
  case_dir="$(new_case "$case_name")"
  write_read "$case_dir" 1 '.'
  write_read "$case_dir" 2 "$fixture_edit"
  run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash "$@" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "$case_name" "$case_dir" "$want_line" "$want_status" 2 1
}
confirm_case "confirm:open-pending"           '.' "MERGE=wait:merge-pending" 0
confirm_case "confirm:open-pending-admin-set" '.' "MERGE=wait:merge-pending" 0 HIVEMIND_AUTO_MERGE_ADMIN=1
confirm_case "confirm:closed-pending"         "$PR.state = \"CLOSED\"" "MERGE=wait:merge-pending" 0
confirm_case "confirm:incomplete" \
  "$MERGED_EDIT | $PR.reviewThreads.pageInfo.hasNextPage = true" "MERGE_ERROR=read-incomplete" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
confirm_case "confirm:malformed" \
  "$MERGED_EDIT | $PR.isDraft = null" "MERGE_ERROR=malformed-read" 1 HIVEMIND_AUTO_MERGE_ADMIN=1

case_dir="$(new_case confirm-read-fails)"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 "$MERGED_EDIT"
printf '1' >"$case_dir/read-2.status"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "confirm:read-fails" "$case_dir" "MERGE_ERROR=graphql-read-failed" 1 2 1

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
read_error_case "read:review-state-missing" "del($PR.latestReviews.nodes[0].state)"                      malformed-read
read_error_case "read:review-state-null"   "$PR.latestReviews.nodes[0].state = null"                     malformed-read
read_error_case "read:review-state-number" "$PR.latestReviews.nodes[0].state = 1"                        malformed-read
read_error_case "read:base-oid-not-hex"    "$PR.baseRefOid = \"main\""                                  malformed-read
read_error_case "read:base-oid-null"       "$PR.baseRefOid = null"                                       malformed-read
read_error_case "read:base-name-empty"     "$PR.baseRefName = \"\""                                      malformed-read
read_error_case "read:base-name-number"    "$PR.baseRefName = 1"                                         malformed-read
read_error_case "read:files-lost"          "del($PR.files)"                                              malformed-read
read_error_case "read:files-page-flag-null" "$PR.files.pageInfo = null"                                  malformed-read
read_error_case "read:file-path-null"      "$PR.files.nodes[0].path = null"                              malformed-read
read_error_case "read:file-change-type-number" "$PR.files.nodes[0].changeType = 1"                       malformed-read

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
# second read is the base body after the edit; an admin rerun, when reached, exits 0. A case that
# expects merged-admin also serves the confirm read, read-3 with state MERGED, and expects three
# reads.
refused_case() {
  local case_name="$1" fixture_edit="$2" want_line="$3" want_merges="$4" want_reads=2 case_dir
  shift 4
  case_dir="$(new_case "$case_name")"
  write_read "$case_dir" 1 '.'
  write_read "$case_dir" 2 "$fixture_edit"
  if [ "$want_line" = "MERGE=merged-admin" ]; then
    write_read "$case_dir" 3 "$MERGED_EDIT"
    want_reads=3
  fi
  printf '1' >"$case_dir/merge-1.status"
  run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash "$@" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "$case_name" "$case_dir" "$want_line" 0 "$want_reads" "$want_merges"
}
refused_case "refused:head-moved" \
  "$PR.headRefOid = \$head_b | $PR.commits.nodes[0].commit.oid = \$head_b | $PR.mergeStateStatus = \"BLOCKED\"" \
  "MERGE=wait:head-moved" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:dirty"            "$PR.mergeStateStatus = \"DIRTY\""   "MERGE=skipped:conflicts" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-no-admin" "$PR.mergeStateStatus = \"BLOCKED\"" "MERGE=skipped:blocked" 1
refused_case "refused:behind-no-admin"  "$PR.mergeStateStatus = \"BEHIND\""  "MERGE=skipped:blocked" 1
refused_case "refused:blocked-admin"    "$PR.mergeStateStatus = \"BLOCKED\"" "MERGE=merged-admin" 2 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:behind-admin"     "$PR.mergeStateStatus = \"BEHIND\""  "MERGE=merged-admin" 2 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-empty" "$PR.mergeStateStatus = \"BLOCKED\"" "MERGE=skipped:blocked" 1 HIVEMIND_AUTO_MERGE_ADMIN=
refused_case "refused:behind-admin-empty"  "$PR.mergeStateStatus = \"BEHIND\""  "MERGE=skipped:blocked" 1 HIVEMIND_AUTO_MERGE_ADMIN=
refused_case "refused:blocked-admin-checks-failed" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.commits.nodes[0].commit.statusCheckRollup.state = \"FAILURE\"" \
  "MERGE=wait:checks-failed" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-checks-pending" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.commits.nodes[0].commit.statusCheckRollup.state = \"PENDING\"" \
  "MERGE=wait:checks-pending" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-no-checks" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.commits.nodes[0].commit.statusCheckRollup = null" \
  "MERGE=skipped:no-checks" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-closed" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.state = \"CLOSED\"" \
  "MERGE=skipped:not-open" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-draft" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.isDraft = true" \
  "MERGE=skipped:draft" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-approval-withdrawn" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.latestReviews.nodes = []" \
  "MERGE=skipped:no-approval" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-bot-changes-requested" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.latestReviews.nodes[0].state = \"CHANGES_REQUESTED\"" \
  "MERGE=skipped:no-approval" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-human-changes-requested" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.latestReviews.nodes += [{state: \"CHANGES_REQUESTED\", author: {login: \"alice\", __typename: \"User\"}}]" \
  "MERGE=skipped:no-approval" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:blocked-admin-thread-reopened" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.reviewThreads.nodes[0].isResolved = false" \
  "MERGE=skipped:open-threads" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:clean-admin-set"  "$PR.mergeStateStatus = \"CLEAN\""   "MERGE=skipped:refused" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:unstable"         "$PR.mergeStateStatus = \"UNSTABLE\"" "MERGE=skipped:refused" 1 HIVEMIND_AUTO_MERGE_ADMIN=1
refused_case "refused:has-hooks"        "$PR.mergeStateStatus = \"HAS_HOOKS\"" "MERGE=skipped:refused" 1 HIVEMIND_AUTO_MERGE_ADMIN=1

# An UNKNOWN re-read is read again, at most 3 more times. unknown_case <name> <settled-edit> <line>
# <reads> <merges> [env...]: the plain merge exits 1; reads 2 to 4 show UNKNOWN and read 5, the
# last re-read allowed, is the base body after <settled-edit>; an admin rerun, when reached, exits
# 0 and read 6, the confirm read, shows MERGED.
UNKNOWN_EDIT="$PR.mergeStateStatus = \"UNKNOWN\""
unknown_case() {
  local case_name="$1" fixture_edit="$2" want_line="$3" want_reads="$4" want_merges="$5" case_dir read_number
  shift 5
  case_dir="$(new_case "$case_name")"
  write_read "$case_dir" 1 '.'
  for read_number in 2 3 4; do
    write_read "$case_dir" "$read_number" "$UNKNOWN_EDIT"
  done
  write_read "$case_dir" 5 "$fixture_edit"
  write_read "$case_dir" 6 "$MERGED_EDIT"
  printf '1' >"$case_dir/merge-1.status"
  run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash "$@" bash "$MERGE_APPROVED" o r 5 automated "$SELF"
  expect_case "$case_name" "$case_dir" "$want_line" 0 "$want_reads" "$want_merges"
}
unknown_case "refused:unknown" "$UNKNOWN_EDIT" "MERGE=wait:merge-state-unknown" 5 1 HIVEMIND_AUTO_MERGE_ADMIN=1
unknown_case "refused:unknown-no-admin" "$UNKNOWN_EDIT" "MERGE=wait:merge-state-unknown" 5 1
unknown_case "refused:unknown-settles-blocked-admin" "$PR.mergeStateStatus = \"BLOCKED\"" "MERGE=merged-admin" 6 2 \
  HIVEMIND_AUTO_MERGE_ADMIN=1
unknown_case "refused:unknown-settles-blocked-no-admin" "$PR.mergeStateStatus = \"BLOCKED\"" "MERGE=skipped:blocked" 5 1
unknown_case "refused:unknown-settles-dirty" "$PR.mergeStateStatus = \"DIRTY\"" "MERGE=skipped:conflicts" 5 1 \
  HIVEMIND_AUTO_MERGE_ADMIN=1
unknown_case "refused:unknown-settles-clean" "$PR.mergeStateStatus = \"CLEAN\"" "MERGE=skipped:refused" 5 1 \
  HIVEMIND_AUTO_MERGE_ADMIN=1
unknown_case "refused:unknown-settles-blocked-checks-failed" \
  "$PR.mergeStateStatus = \"BLOCKED\" | $PR.commits.nodes[0].commit.statusCheckRollup.state = \"FAILURE\"" \
  "MERGE=wait:checks-failed" 5 1 HIVEMIND_AUTO_MERGE_ADMIN=1

case_dir="$(new_case refused-unknown-head-moved)"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 "$UNKNOWN_EDIT"
write_read "$case_dir" 3 "$UNKNOWN_EDIT | $PR.headRefOid = \$head_b | $PR.commits.nodes[0].commit.oid = \$head_b"
write_read "$case_dir" 4 "$PR.mergeStateStatus = \"BLOCKED\""
printf '1' >"$case_dir/merge-1.status"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "refused:unknown-head-moved" "$case_dir" "MERGE=wait:head-moved" 0 3 1

case_dir="$(new_case refused-unknown-reread-fails)"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 "$UNKNOWN_EDIT"
write_read "$case_dir" 3 "$UNKNOWN_EDIT"
printf '1' >"$case_dir/read-3.status"
printf '1' >"$case_dir/merge-1.status"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "refused:unknown-reread-fails" "$case_dir" "MERGE_ERROR=graphql-read-failed" 1 3 1

case_dir="$(new_case refused-admin-refused)"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 "$PR.mergeStateStatus = \"BLOCKED\""
printf '1' >"$case_dir/merge-1.status"
printf '1' >"$case_dir/merge-2.status"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=rebase HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "refused:admin-refused" "$case_dir" "MERGE=skipped:admin-refused" 0 2 2

case_dir="$(new_case "refused:blocked-admin-confirm-open")"
write_read "$case_dir" 1 '.'
write_read "$case_dir" 2 "$PR.mergeStateStatus = \"BLOCKED\""
write_read "$case_dir" 3 '.'
printf '1' >"$case_dir/merge-1.status"
run_case "$case_dir" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 5 automated "$SELF"
expect_case "refused:blocked-admin-confirm-open" "$case_dir" "MERGE=wait:merge-pending" 0 3 2

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

for admin_case in refused:blocked-admin refused:behind-admin refused:blocked-admin-confirm-open \
    refused:unknown-settles-blocked-admin; do
  case_dir="$CASES_DIR/$admin_case"
  want_admin="MERGE 2 after_head=$HEAD_A after_rollup=SUCCESS after_reviews=COMMENTED argv=pr merge 5 --repo o/r --squash --match-head-commit $HEAD_A --admin"
  if grep -qxF "$want_admin" "$case_dir/calls.log"; then
    pass "$admin_case-argv" "admin rerun keeps --match-head-commit $HEAD_A"
  else
    failed "$admin_case-argv" "calls: $(tr '\n' '|' <"$case_dir/calls.log")"
  fi
done

# ── Record gate: a PR whose files touch docs ─────────────────────────────────
# The fixture server is a bare repository built with the real git from an author repository. Its
# branches: main (a README), trunk-demo (main plus a demo initiative whose record passes) and
# trunk-drift (trunk-demo with the demo PRD edited and not re-stamped). Its PR heads:
#   11  main + the demo initiative, record passes
#   12  main + the demo initiative, record verdict fail
#   13  main + the demo initiative, record verdict pass with an open finding
#   14  main + the demo PRD and solution design, no record
#   15  trunk-demo + the demo solution design marked delivered
#   16  trunk-demo + a second initiative whose record passes
# PR 18 has no head ref on the server.
AUTHOR_DIR="$TMPDIR_TEST/author"

# author_git <arg>...: the real git in the author repository, with a fixed identity.
author_git() {
  "$REAL_GIT" -C "$AUTHOR_DIR" -c user.name=fixture -c user.email=fixture@example.invalid "$@"
}

# author_file <path> <text>: writes <text> to <path> in the author work tree.
author_file() {
  mkdir -p "$AUTHOR_DIR/$(dirname "$1")" && printf '%s' "$2" >"$AUTHOR_DIR/$1"
}

# author_commit <var> <message>: commits the whole author work tree and sets <var> to its id.
author_commit() {
  author_git add -A >/dev/null 2>&1 && author_git commit -q -m "$2" >/dev/null 2>&1 \
    && printf -v "$1" '%s' "$(author_git rev-parse HEAD)" && [[ "${!1}" =~ ^[0-9a-f]{40}$ ]]
}

# author_initiative <slug>: writes the slug's PRD (UI no) and draft solution design.
author_initiative() {
  author_file "docs/prds/$1.md" "# $1 PRD"$'\n\n'"**UI:** no"$'\n' \
    && author_file "docs/initiatives/$1/solution-design.md" "# $1 design"$'\n\n'"**Status:** draft"$'\n'
}

# author_record <slug> <verdict> <medium-open> <rounds> <clean-round> <disposition>: writes the
# slug's review record, stamping its PRD and solution design at their current blobs, with one
# medium Findings row of the given disposition.
author_record() {
  local prd_blob design_blob
  prd_blob="$(author_git hash-object "docs/prds/$1.md")" || return 1
  design_blob="$(author_git hash-object "docs/initiatives/$1/solution-design.md")" || return 1
  author_file "docs/initiatives/$1/review-record.md" "---
stamps:
  - path: docs/prds/$1.md
    blob: $prd_blob
  - path: docs/initiatives/$1/solution-design.md
    blob: $design_blob
verdict: $2
open:
  critical: 0
  high: 0
  medium: $3
  low: 0
rounds: $4
clean_round: $5
---
# Review record: $1

## Findings

| ID | Round | Angle | Severity | Disposition | Note |
| --- | --- | --- | --- | --- | --- |
| F1 | 1 | A | medium | $6 | Tightened the wording. |
"
}

# author_from <commit>: points the author work tree at <commit>, detached.
author_from() {
  author_git checkout -q --detach "$1" >/dev/null 2>&1
}

# build_fixture_server: builds the author history and pushes it to the bare fixture server.
build_fixture_server() {
  "$REAL_GIT" init -q "$AUTHOR_DIR" && "$REAL_GIT" init -q --bare "$GIT_SERVER" || return 1
  author_file README.md "fixture"$'\n' && author_commit MAIN_OID main || return 1
  author_initiative demo && author_record demo pass 0 2 true fixed && author_commit PASS_OID pass || return 1
  author_from "$MAIN_OID" && author_initiative demo && author_record demo fail 0 1 false fixed \
    && author_commit FAIL_OID fail || return 1
  author_from "$MAIN_OID" && author_initiative demo && author_record demo pass 1 2 true open \
    && author_commit OPEN_OID open || return 1
  author_from "$MAIN_OID" && author_initiative demo && author_commit NORECORD_OID norecord || return 1
  author_from "$PASS_OID" \
    && author_file docs/initiatives/demo/solution-design.md "# demo design"$'\n\n'"**Status:** delivered"$'\n' \
    && author_commit DELIVERED_OID delivered || return 1
  author_from "$PASS_OID" \
    && author_file docs/prds/demo.md "# demo PRD"$'\n\n'"**UI:** no"$'\n\n'"Edited on trunk."$'\n' \
    && author_commit DRIFT_OID drift || return 1
  author_from "$PASS_OID" && author_initiative second && author_record second pass 0 2 true fixed \
    && author_commit SECOND_OID second || return 1
  author_git push -q "$GIT_SERVER" "$MAIN_OID:refs/heads/main" "$PASS_OID:refs/heads/trunk-demo" \
    "$DRIFT_OID:refs/heads/trunk-drift" "$PASS_OID:refs/pull/11/head" "$FAIL_OID:refs/pull/12/head" \
    "$OPEN_OID:refs/pull/13/head" "$NORECORD_OID:refs/pull/14/head" \
    "$DELIVERED_OID:refs/pull/15/head" "$SECOND_OID:refs/pull/16/head" >/dev/null 2>&1
}
build_fixture_server || { echo "FAIL: fixture server failed to build" >&2; exit 2; }

ORIGIN_REMOTE="origin https://github.com/o/r.git"
DOCS_FILES='[{path: "docs/initiatives/demo/review-record.md", changeType: "ADDED"}]'
README_FILES='[{path: "README.md", changeType: "MODIFIED"}]'

# record_edit <head> <base-name> <base-oid> <files-json>: prints a jq edit of the base body for a PR
# on that head and base whose changed files are <files-json>.
record_edit() {
  printf '%s' "$PR.headRefOid = \"$1\" | $PR.commits.nodes[0].commit.oid = \"$1\" | $PR.baseRefName = \"$2\" | $PR.baseRefOid = \"$3\" | $PR.files.nodes = $4"
}
PASS_EDIT="$(record_edit "$PASS_OID" main "$MAIN_OID" "$DOCS_FILES")"

# new_record_case <name> [<remote-name> <remote-url>]...: sets RECORD_CASE_DIR to a fresh case
# directory that is a git repository with the given remotes.
new_record_case() {
  RECORD_CASE_DIR="$(new_case "$1")"
  shift
  "$REAL_GIT" init -q "$RECORD_CASE_DIR" || { echo "FAIL: case repository failed to build" >&2; exit 2; }
  while [ "$#" -ge 2 ]; do
    "$REAL_GIT" -C "$RECORD_CASE_DIR" remote add "$1" "$2" \
      || { echo "FAIL: case remote failed to build" >&2; exit 2; }
    shift 2
  done
}

# record_case <name> <remotes> <pr> <jq-edit> <line> <reads> <merges> [env...]: a case in a
# repository with <remotes> (space-separated name and URL pairs); reads 1 and 2 are the edited base
# body and read 3 the same with state MERGED; HIVEMIND_AUTO_MERGE=squash plus any extra env.
record_case() {
  local case_name="$1" remotes="$2" pr_number="$3" fixture_edit="$4" want_line="$5" want_reads="$6" want_merges="$7"
  shift 7
  # shellcheck disable=SC2086
  new_record_case "$case_name" $remotes
  write_read "$RECORD_CASE_DIR" 1 "$fixture_edit"
  write_read "$RECORD_CASE_DIR" 2 "$fixture_edit"
  write_read "$RECORD_CASE_DIR" 3 "$fixture_edit | $MERGED_EDIT"
  run_case "$RECORD_CASE_DIR" HIVEMIND_AUTO_MERGE=squash "$@" bash "$MERGE_APPROVED" o r "$pr_number" automated "$SELF"
  expect_case "$case_name" "$RECORD_CASE_DIR" "$want_line" 0 "$want_reads" "$want_merges"
}

# expect_git <name> <case_dir> <fetches>: assert the case made a git call and exactly <fetches>
# fetch calls.
expect_git() {
  local got_git got_fetches
  got_git="$(count_calls "$2" GIT)"
  got_fetches="$(grep -c '^GIT argv=.* fetch ' "$2/calls.log")"
  if [ "$got_git" -gt 0 ] && [ "$got_fetches" -eq "$3" ]; then
    pass "$1" "record gate ran: $got_git git calls, $got_fetches fetch"
  else
    failed "$1" "git calls $got_git, fetches $got_fetches (want >0 git calls, $3 fetch)"
  fi
}

# The gate is off without a docs path: no git call and no extra read, even in a tied repository.
new_record_case "record:off-no-docs-path" $ORIGIN_REMOTE
write_read "$RECORD_CASE_DIR" 1 "$(record_edit "$PASS_OID" main "$MAIN_OID" "$README_FILES")"
write_read "$RECORD_CASE_DIR" 2 "$(record_edit "$PASS_OID" main "$MAIN_OID" "$README_FILES") | $MERGED_EDIT"
run_case "$RECORD_CASE_DIR" HIVEMIND_AUTO_MERGE=squash bash "$MERGE_APPROVED" o r 11 automated "$SELF"
expect_case "record:off-no-docs-path" "$RECORD_CASE_DIR" "MERGE=merged" 0 2 1
if [ "$(count_calls "$RECORD_CASE_DIR" GIT)" -eq 0 ]; then
  pass "record:off-no-git-call" "a PR without a docs path makes no git call"
else
  failed "record:off-no-git-call" "calls: $(tr '\n' '|' <"$RECORD_CASE_DIR/calls.log")"
fi
gate_case "docs-touch:off-other-docs-path" \
  "$PR.files.nodes = [{path: \"docs/references/notes.md\", changeType: \"ADDED\"}, {path: \"docsx/prds/a.md\", changeType: \"MODIFIED\"}]" \
  "MERGE=merged" 1
gate_case "docs-touch:off-no-files" "$PR.files.nodes = []" "MERGE=merged" 1

# A passing record merges; the fetch names the tied remote, the PR head ref and the base branch,
# and writes no local branch or remote-tracking ref.
record_case "record:pass-merges" "$ORIGIN_REMOTE" 11 "$PASS_EDIT" "MERGE=merged" 3 1
expect_git "record:pass-merges-ran-gate" "$RECORD_CASE_DIR" 1
want_fetch="GIT argv=--no-replace-objects fetch --quiet --no-tags --no-recurse-submodules --no-prune --refmap= -- origin refs/pull/11/head refs/heads/main"
if grep -qxF "$want_fetch" "$RECORD_CASE_DIR/calls.log"; then
  pass "record:fetch-argv" "${want_fetch#GIT argv=}"
else
  failed "record:fetch-argv" "calls: $(tr '\n' '|' <"$RECORD_CASE_DIR/calls.log")"
fi
written_refs="$("$REAL_GIT" -C "$RECORD_CASE_DIR" for-each-ref)"
if [ -z "$written_refs" ] && "$REAL_GIT" -C "$RECORD_CASE_DIR" cat-file -e "$PASS_OID^{commit}"; then
  pass "record:fetch-writes-no-ref" "head fetched into the object store, no ref written"
else
  failed "record:fetch-writes-no-ref" "refs: $(tr '\n' '|' <<<"$written_refs")"
fi

# Each docs trigger runs the gate: a docs path, a RENAMED file and a files page overflow.
record_case "record:trigger-prds-path" "$ORIGIN_REMOTE" 12 \
  "$(record_edit "$FAIL_OID" main "$MAIN_OID" '[{path: "docs/prds/demo.md", changeType: "ADDED"}]')" \
  "MERGE=skipped:record-blocked" 1 0
record_case "record:trigger-adr-path" "$ORIGIN_REMOTE" 12 \
  "$(record_edit "$FAIL_OID" main "$MAIN_OID" '[{path: "docs/adr/0099-demo.md", changeType: "MODIFIED"}]')" \
  "MERGE=skipped:record-blocked" 1 0
record_case "record:trigger-renamed" "$ORIGIN_REMOTE" 12 \
  "$(record_edit "$FAIL_OID" main "$MAIN_OID" '[{path: "src/tool.sh", changeType: "RENAMED"}]')" \
  "MERGE=skipped:record-blocked" 1 0
expect_git "record:trigger-renamed-ran-gate" "$RECORD_CASE_DIR" 1
record_case "record:trigger-files-overflow" "$ORIGIN_REMOTE" 12 \
  "$(record_edit "$FAIL_OID" main "$MAIN_OID" "$README_FILES") | $PR.files.pageInfo.hasNextPage = true" \
  "MERGE=skipped:record-blocked" 1 0
expect_git "record:trigger-files-overflow-ran-gate" "$RECORD_CASE_DIR" 1

# The remote tied to <OWNER>/<REPO> on the gh host, in each URL form.
record_case "record:remote-scp-mixed-case" "origin git@GitHub.com:O/R.git" 11 "$PASS_EDIT" "MERGE=merged" 3 1
record_case "record:remote-ssh-trailing-slash" "origin ssh://git@github.com/o/r/" 11 "$PASS_EDIT" "MERGE=merged" 3 1
record_case "record:remote-gh-host" "origin https://ghe.example.com/o/r" 11 "$PASS_EDIT" "MERGE=merged" 3 1 \
  GH_HOST=ghe.example.com
record_case "record:remote-second-tied" "fork https://github.com/other/r.git upstream https://github.com/o/r" 11 \
  "$PASS_EDIT" "MERGE=merged" 3 1
if grep -q '^GIT argv=.* fetch .* -- upstream refs/pull/11/head refs/heads/main$' "$RECORD_CASE_DIR/calls.log"; then
  pass "record:remote-second-tied-fetch" "fetch names the tied remote, not the first one"
else
  failed "record:remote-second-tied-fetch" "calls: $(tr '\n' '|' <"$RECORD_CASE_DIR/calls.log")"
fi

# The record cannot be read: record-unread, no merge call.
record_case "record:unread-no-tied-remote" "origin https://github.com/other/r.git" 11 "$PASS_EDIT" \
  "MERGE=skipped:record-unread" 1 0
expect_git "record:unread-no-tied-remote-no-fetch" "$RECORD_CASE_DIR" 0
record_case "record:unread-no-remote" "" 11 "$PASS_EDIT" "MERGE=skipped:record-unread" 1 0
record_case "record:unread-other-host" "origin https://ghe.example.com/o/r" 11 "$PASS_EDIT" \
  "MERGE=skipped:record-unread" 1 0
record_case "record:unread-bad-base-name" "$ORIGIN_REMOTE" 11 \
  "$(record_edit "$PASS_OID" "bad..name" "$MAIN_OID" "$DOCS_FILES")" "MERGE=skipped:record-unread" 1 0
expect_git "record:unread-bad-base-name-no-fetch" "$RECORD_CASE_DIR" 0
record_case "record:unread-fetch-fails" "$ORIGIN_REMOTE" 18 "$PASS_EDIT" "MERGE=skipped:record-unread" 1 0
expect_git "record:unread-fetch-fails-ran-fetch" "$RECORD_CASE_DIR" 1
record_case "record:unread-missing-head-object" "$ORIGIN_REMOTE" 11 \
  "$(record_edit "cccccccccccccccccccccccccccccccccccccccc" main "$MAIN_OID" "$DOCS_FILES")" \
  "MERGE=skipped:record-unread" 1 0
record_case "record:unread-missing-base-object" "$ORIGIN_REMOTE" 11 \
  "$(record_edit "$PASS_OID" main "$BASE_A" "$DOCS_FILES")" "MERGE=skipped:record-unread" 1 0
record_case "record:unread-verify-error" "$ORIGIN_REMOTE" 11 "$PASS_EDIT" "MERGE=skipped:record-unread" 1 0 \
  FIXTURE_GIT_FAIL=ls-tree

# The record fails merge-mode verify: record-blocked, no merge call, with the admin setting too.
record_case "record:blocked-failing-record" "$ORIGIN_REMOTE" 12 \
  "$(record_edit "$FAIL_OID" main "$MAIN_OID" "$DOCS_FILES")" "MERGE=skipped:record-blocked" 1 0
record_case "record:blocked-failing-record-admin" "$ORIGIN_REMOTE" 12 \
  "$(record_edit "$FAIL_OID" main "$MAIN_OID" "$DOCS_FILES")" "MERGE=skipped:record-blocked" 1 0 \
  HIVEMIND_AUTO_MERGE_ADMIN=1
record_case "record:blocked-open-finding" "$ORIGIN_REMOTE" 13 \
  "$(record_edit "$OPEN_OID" main "$MAIN_OID" "$DOCS_FILES")" "MERGE=skipped:record-blocked" 1 0
record_case "record:blocked-folder-without-record" "$ORIGIN_REMOTE" 14 \
  "$(record_edit "$NORECORD_OID" main "$MAIN_OID" "$DOCS_FILES")" "MERGE=skipped:record-blocked" 1 0
record_case "record:blocked-delivered-flip" "$ORIGIN_REMOTE" 15 \
  "$(record_edit "$DELIVERED_OID" trunk-demo "$PASS_OID" "$DOCS_FILES")" "MERGE=skipped:record-blocked" 1 0
record_case "record:blocked-base-drift" "$ORIGIN_REMOTE" 16 \
  "$(record_edit "$SECOND_OID" trunk-drift "$DRIFT_OID" "$DOCS_FILES")" "MERGE=skipped:record-blocked" 1 0
record_case "record:second-without-drift-merges" "$ORIGIN_REMOTE" 16 \
  "$(record_edit "$SECOND_OID" trunk-demo "$PASS_OID" "$DOCS_FILES")" "MERGE=merged" 3 1

# The fresh read right before the merge call.
# fresh_case <name> <read-2 jq-edit> <line>: the record gate holds and read 2, the fresh read, is
# the passing edit plus <read-2 jq-edit>; two reads, no merge call.
fresh_case() {
  new_record_case "$1" $ORIGIN_REMOTE
  write_read "$RECORD_CASE_DIR" 1 "$PASS_EDIT"
  write_read "$RECORD_CASE_DIR" 2 "$PASS_EDIT | $2"
  run_case "$RECORD_CASE_DIR" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 11 automated "$SELF"
  expect_case "$1" "$RECORD_CASE_DIR" "$3" 0 2 0
}
fresh_case "record:fresh-base-moved" "$PR.baseRefOid = \"$BASE_A\"" "MERGE=wait:base-moved"
fresh_case "record:fresh-head-moved" "$PR.headRefOid = \$head_b | $PR.commits.nodes[0].commit.oid = \$head_b" \
  "MERGE=wait:head-moved"
fresh_case "record:fresh-checks-failed" "$PR.commits.nodes[0].commit.statusCheckRollup.state = \"FAILURE\"" \
  "MERGE=wait:checks-failed"
fresh_case "record:fresh-changes-requested" "$PR.latestReviews.nodes[0].state = \"CHANGES_REQUESTED\"" \
  "MERGE=skipped:no-approval"

# The --admin path: the re-read after a refused plain merge is the fresh read before --admin.
new_record_case "record:admin-merged" $ORIGIN_REMOTE
write_read "$RECORD_CASE_DIR" 1 "$PASS_EDIT"
write_read "$RECORD_CASE_DIR" 2 "$PASS_EDIT"
write_read "$RECORD_CASE_DIR" 3 "$PASS_EDIT | $PR.mergeStateStatus = \"BLOCKED\""
write_read "$RECORD_CASE_DIR" 4 "$PASS_EDIT | $MERGED_EDIT"
printf '1' >"$RECORD_CASE_DIR/merge-1.status"
run_case "$RECORD_CASE_DIR" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 11 automated "$SELF"
expect_case "record:admin-merged" "$RECORD_CASE_DIR" "MERGE=merged-admin" 0 4 2
if grep -qxF "MERGE 2 after_head=$PASS_OID after_rollup=SUCCESS after_reviews=COMMENTED argv=pr merge 11 --repo o/r --squash --match-head-commit $PASS_OID --admin" "$RECORD_CASE_DIR/calls.log"; then
  pass "record:admin-merged-argv" "admin rerun keeps --match-head-commit $PASS_OID"
else
  failed "record:admin-merged-argv" "calls: $(tr '\n' '|' <"$RECORD_CASE_DIR/calls.log")"
fi

new_record_case "record:admin-base-moved" $ORIGIN_REMOTE
write_read "$RECORD_CASE_DIR" 1 "$PASS_EDIT"
write_read "$RECORD_CASE_DIR" 2 "$PASS_EDIT"
write_read "$RECORD_CASE_DIR" 3 "$PASS_EDIT | $PR.mergeStateStatus = \"BLOCKED\" | $PR.baseRefOid = \"$BASE_A\""
printf '1' >"$RECORD_CASE_DIR/merge-1.status"
run_case "$RECORD_CASE_DIR" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 11 automated "$SELF"
expect_case "record:admin-base-moved" "$RECORD_CASE_DIR" "MERGE=wait:base-moved" 0 3 1

# An UNKNOWN re-read is read again; the last re-read is the fresh read before --admin.
new_record_case "record:admin-unknown-base-moved" $ORIGIN_REMOTE
write_read "$RECORD_CASE_DIR" 1 "$PASS_EDIT"
write_read "$RECORD_CASE_DIR" 2 "$PASS_EDIT"
write_read "$RECORD_CASE_DIR" 3 "$PASS_EDIT | $PR.mergeStateStatus = \"UNKNOWN\""
write_read "$RECORD_CASE_DIR" 4 "$PASS_EDIT | $PR.mergeStateStatus = \"BLOCKED\" | $PR.baseRefOid = \"$BASE_A\""
printf '1' >"$RECORD_CASE_DIR/merge-1.status"
run_case "$RECORD_CASE_DIR" HIVEMIND_AUTO_MERGE=squash HIVEMIND_AUTO_MERGE_ADMIN=1 bash "$MERGE_APPROVED" o r 11 automated "$SELF"
expect_case "record:admin-unknown-base-moved" "$RECORD_CASE_DIR" "MERGE=wait:base-moved" 0 4 1

# ── Properties over every case ───────────────────────────────────────────────
# check_merge_review_states <case> <call_line> <after_reviews>: fail the merge call when the read
# before it held a review state outside APPROVED, COMMENTED or DISMISSED.
check_merge_review_states() {
  local review_state review_states
  [ "$3" = "NONE" ] && return 0
  IFS=',' read -r -a review_states <<<"$3"
  for review_state in "${review_states[@]}"; do
    case "$review_state" in
      APPROVED|COMMENTED|DISMISSED) ;;
      *) failed "property:merge-only-on-allowed-review-states" "$1: $2" ;;
    esac
  done
}

# check_merged_confirm_read <case> <case_dir> <stdout-line>: for a case that printed merged or
# merged-admin, fail unless it made a merge call and its last call is a READ showing state=MERGED,
# so the confirm read came after its last merge call.
check_merged_confirm_read() {
  local last_call
  last_call="$(tail -n 1 "$2/calls.log")"
  if ! grep -q '^MERGE ' "$2/calls.log" || ! [[ "$last_call" =~ ^READ\ [0-9]+\ state=MERGED\  ]]; then
    failed "property:merged-only-after-merged-confirm-read" "$1: $3, calls: $(tr '\n' '|' <"$2/calls.log")"
  fi
}

merge_call_count=0
merged_case_count=0
record_case_count=0
non_record_case_count=0
for calls_log in "$CASES_DIR"/*/calls.log; do
  case_name="$(basename "$(dirname "$calls_log")")"
  case_dir="$(dirname "$calls_log")"
  if [ -f "$case_dir/stdout" ]; then
    case_out="$(cat "$case_dir/stdout")"
  else
    case_out=""
    failed "property:merged-only-after-merged-confirm-read" "$case_name: no stdout recorded"
  fi
  case "$case_out" in
    MERGE=merged|MERGE=merged-admin)
      merged_case_count=$((merged_case_count + 1))
      check_merged_confirm_read "$case_name" "$case_dir" "$case_out" ;;
  esac
  case_env_admin="no"
  case "$case_name" in
    refused:blocked-admin|refused:behind-admin|refused-admin-refused|refused:blocked-admin-confirm-open) case_env_admin="yes" ;;
    refused:unknown-settles-blocked-admin) case_env_admin="yes" ;;
    record:admin-merged|record:admin-base-moved) case_env_admin="yes" ;;
  esac
  case "$case_name" in
    record:*) record_case_count=$((record_case_count + 1)) ;;
    *)
      if grep -q '^GIT ' "$calls_log"; then
        failed "property:no-git-call-without-docs" "$case_name: $(grep -c '^GIT ' "$calls_log") git calls"
      fi
      non_record_case_count=$((non_record_case_count + 1)) ;;
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
    after_reviews="${call_line#*after_reviews=}"
    after_reviews="${after_reviews%% *}"
    merge_argv="${call_line#*argv=}"
    case " $merge_argv " in
      *" --auto "*|*" --delete-branch "*) failed "property:no-auto-delete" "$case_name: $call_line" ;;
    esac
    case " $merge_argv " in
      *" --match-head-commit $after_head "*) ;;
      *) failed "property:match-head-commit" "$case_name: $call_line" ;;
    esac
    [ "$after_rollup" = "SUCCESS" ] || failed "property:merge-only-on-success" "$case_name: $call_line"
    check_merge_review_states "$case_name" "$call_line" "$after_reviews"
    case " $merge_argv " in
      *" --admin "*)
        if [ "$merge_number" != "2" ] || [ "$case_env_admin" != "yes" ] \
           || ! grep -q "^MERGE 1 after_head=$after_head after_rollup=SUCCESS after_reviews=[^ ]* argv=.* --match-head-commit $after_head$" "$calls_log"; then
          failed "property:admin-only-after-refusal" "$case_name: $call_line"
        fi ;;
    esac
  done <"$calls_log"
done
if [ "$merge_call_count" -gt 0 ]; then
  pass "property:scan-non-vacuous" "$merge_call_count merge calls scanned for --auto, --delete-branch, --match-head-commit, SUCCESS-only, allowed review states and --admin placement"
else
  failed "property:scan-non-vacuous" "no merge call recorded in any case"
fi
if [ "$non_record_case_count" -gt 0 ] && [ "$record_case_count" -gt 0 ]; then
  pass "property:git-scan-non-vacuous" "$non_record_case_count cases outside the record cases scanned for no git call; $record_case_count record cases"
else
  failed "property:git-scan-non-vacuous" "non-record cases $non_record_case_count, record cases $record_case_count"
fi
if [ "$merged_case_count" -gt 0 ]; then
  pass "property:merged-scan-non-vacuous" "$merged_case_count merged or merged-admin cases scanned for a last READ showing state=MERGED after the last merge call"
else
  failed "property:merged-scan-non-vacuous" "no case printed merged or merged-admin"
fi

echo ''
echo "test_merge_approved: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
