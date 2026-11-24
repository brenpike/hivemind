#!/usr/bin/env bash
#
# Record verify suite for this repository: runs the shared review record verify library
#   plugin/skills/_shared/record-verify.sh
# (hivemind_record_verify, pull request mode) over this repository's own design review records,
# so a pull request whose `docs/initiatives/<slug>/review-record.md`, PRD or ADR leaves a record
# inconsistent or stale fails validation before review.
#
# READS COMMITS, NOT THE WORKING TREE: verify runs at HEAD's commit against the merge-base, and
# reads every record, stamp and changed path from git objects. An uncommitted or unstaged edit
# is invisible to this suite; commit it first.
#
# BASE: the merge-base of HEAD with VERIFY_RECORDS_BASE when that variable is set, else with
# origin/main, else with main. A set VERIFY_RECORDS_BASE is the only candidate, never narrowed to
# the fallbacks. A base that does not resolve fails the suite; it never passes.
#
# OUTPUT AND EXIT: status 0 prints one PASS line. Verify status 1 passes through each
# `record-verify-failed: <record path>` line on stdout, status 2 its one
# `record-verify-error: <token>` line on stderr; either ends with one FAIL line on stderr and
# exits with that status. A set-up failure (missing library, git or jq, no HEAD commit, no base)
# prints one `verify_records: <reason>` line on stderr and exits 2.
#
# Needs only bash, git and jq: no gh, no network. Read-only: it writes no file and no scratch
# path, and makes no git write.
#
# Usage:
#   bash tools/verify_records.sh
#   VERIFY_RECORDS_BASE=<ref> bash tools/verify_records.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SHARED_DIR="$REPO_ROOT/plugin/skills/_shared"

# fail_setup <reason>: prints the one set-up failure line to stderr and exits 2.
fail_setup() {
  printf 'verify_records: %s\n' "$1" >&2
  exit 2
}

command -v git >/dev/null 2>&1 || fail_setup "git is required"
command -v jq >/dev/null 2>&1 || fail_setup "jq is required"
[ -f "$SHARED_DIR/readiness-check.sh" ] || fail_setup "missing library $SHARED_DIR/readiness-check.sh"
[ -f "$SHARED_DIR/record-verify.sh" ] || fail_setup "missing library $SHARED_DIR/record-verify.sh"
# shellcheck source=../plugin/skills/_shared/readiness-check.sh
. "$SHARED_DIR/readiness-check.sh" || fail_setup "sourcing readiness-check.sh failed"
# shellcheck source=../plugin/skills/_shared/record-verify.sh
. "$SHARED_DIR/record-verify.sh" || fail_setup "sourcing record-verify.sh failed"

cd "$REPO_ROOT"

# resolve_base_commit: prints the merge-base of HEAD with VERIFY_RECORDS_BASE when it is set,
# else with the first of origin/main and main that has one. Returns 1 when no candidate resolves.
resolve_base_commit() {
  local base_candidate merge_base
  local -a base_candidates=(origin/main main)
  if [[ -n "${VERIFY_RECORDS_BASE+set}" ]]; then
    base_candidates=("$VERIFY_RECORDS_BASE")
  fi
  for base_candidate in "${base_candidates[@]}"; do
    if [[ -n "$base_candidate" && "$base_candidate" != -* ]] \
      && git rev-parse --verify --quiet "${base_candidate}^{commit}" >/dev/null 2>&1 \
      && merge_base="$(git merge-base "$base_candidate" HEAD 2>/dev/null)" \
      && [[ -n "$merge_base" ]]; then
      printf '%s\n' "$merge_base"
      return 0
    fi
  done
  return 1
}

head_commit="$(git rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null)" \
  || fail_setup "HEAD does not name a commit"
base_commit="$(resolve_base_commit)" \
  || fail_setup "no merge-base of HEAD resolved (tried ${VERIFY_RECORDS_BASE+VERIFY_RECORDS_BASE=}${VERIFY_RECORDS_BASE-origin/main, main}) -- fetch the base branch or set VERIFY_RECORDS_BASE"

verify_rc=0
hivemind_record_verify "$head_commit" "$base_commit" || verify_rc=$?

if [[ "$verify_rc" -eq 0 ]]; then
  printf 'verify_records: PASS (HEAD %s, merge-base %s)\n' "${head_commit:0:12}" "${base_commit:0:12}"
  exit 0
fi
printf 'verify_records: FAIL, record verify exited %s (HEAD %s, merge-base %s)\n' \
  "$verify_rc" "${head_commit:0:12}" "${base_commit:0:12}" >&2
if [[ "$verify_rc" -eq 1 ]]; then
  exit 1
fi
exit 2
