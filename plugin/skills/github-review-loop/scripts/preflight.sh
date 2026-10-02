#!/usr/bin/env bash
#
# Preflight resolution for the github-review-loop skill.
#
# Resolves and verifies the facts the skill needs before it dispatches the
# cycle-0 reviewer pass and arms the change-detect poll:
#   - PR number, owner, repo
#   - PR is OPEN
#   - the local working branch matches the expected working_branch
#   - the resolved base branch
#   - SELF_LOGIN (the authenticated gh User-account login, for self-comment filtering)
#
# Emits labeled results on stdout for the skill to read directly. No /tmp. No
# stop-file. On any failure it prints a PREFLIGHT_ERROR line and exits non-zero.
#
# Positional arguments supplied by the skill at invocation:
#   $1  PR_REF          PR number or URL
#   $2  WORKING_BRANCH  expected working branch
#   $3  BASE_BRANCH     expected base branch (PR target)
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: every `gh ... || fail` and
# `[ ... ] || fail` relies on a non-zero result NOT aborting so fail() can emit a structured
# PREFLIGHT_ERROR with an explicit exit code — `set -e` would abort before fail() runs.

set -u

fail() {
  echo "PREFLIGHT_ERROR=$1"
  exit 1
}

PR_REF="${1:-}"
WORKING_BRANCH="${2:-}"
BASE_BRANCH="${3:-}"

[ -n "$PR_REF" ] || fail "missing required argument: PR_REF (\$1)"
[ -n "$WORKING_BRANCH" ] || fail "missing required argument: WORKING_BRANCH (\$2)"
[ -n "$BASE_BRANCH" ] || fail "missing required argument: BASE_BRANCH (\$3)"

# Resolve PR number, state, and base via gh's own --jq (no standalone jq).
pr_number=$(gh pr view "$PR_REF" --json number --jq '.number' 2>/dev/null) \
  || fail "could not resolve PR number"
pr_state=$(gh pr view "$PR_REF" --json state --jq '.state' 2>/dev/null) \
  || fail "could not resolve PR state"
pr_base=$(gh pr view "$PR_REF" --json baseRefName --jq '.baseRefName' 2>/dev/null) \
  || fail "could not resolve PR base"

# The PR and its review threads live in the BASE repository regardless of the
# head (fork or same-repo), so resolve owner/repo from the base repository
# unconditionally. gh builds the PR `url` from the base repository where the PR
# lives; parse owner/repo from that canonical path. Strip scheme and host
# generically (not a fixed github.com prefix) so this also works against GHES
# and other gh hosts.
pr_url=$(gh pr view "$PR_REF" --json url --jq '.url' 2>/dev/null) \
  || fail "could not resolve base repo owner/name"
[ -n "$pr_url" ] || fail "could not resolve base repo owner/name"
url_noscheme="${pr_url#*://}"           # drop scheme (https://, http://)
url_path="${url_noscheme#*/}"           # drop host segment, leaving owner/repo/...
owner="${url_path%%/*}"
url_rest="${url_path#*/}"
repo="${url_rest%%/*}"
[ -n "$owner" ] && [ -n "$repo" ] && [ "$owner" != "$url_path" ] \
  || fail "could not resolve base repo owner/name"

[ "$pr_state" = "OPEN" ] || fail "PR is not OPEN (state=$pr_state)"

# Guard against a retargeted PR: the resolved base must match the expected
# BASE_BRANCH the skill was invoked with. A mismatch means the PR target moved
# (e.g. retargeted off the working branch's intended base), so remediation and
# terminal reporting would run under stale branch assumptions. Stop as blocked
# before dispatching the reviewer.
[ "$pr_base" = "$BASE_BRANCH" ] \
  || fail "PR base '$pr_base' does not match expected base_branch '$BASE_BRANCH'"

self_login=$(gh api user --jq 'select(.type == "User") | .login' 2>/dev/null) \
  || fail "could not resolve SELF_LOGIN"
[ -n "$self_login" ] || fail "SELF_LOGIN is not a User account"

current_branch=$(git branch --show-current 2>/dev/null) \
  || fail "could not read current git branch"
[ "$current_branch" = "$WORKING_BRANCH" ] \
  || fail "current branch '$current_branch' does not match working_branch '$WORKING_BRANCH'"

# Emit resolved facts for the skill.
echo "PR_NUMBER=$pr_number"
echo "OWNER=$owner"
echo "REPO=$repo"
echo "STATE=$pr_state"
echo "BASE=$pr_base"
echo "WORKING_BRANCH=$current_branch"
echo "SELF_LOGIN=$self_login"
echo "PREFLIGHT_OK=true"
