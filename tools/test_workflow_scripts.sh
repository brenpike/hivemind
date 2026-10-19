#!/usr/bin/env bash
#
# Workflow-script suite runner (issue #409): validation gate 4.
#
# Runs, in order:
#   1. node tools/build_workflows.mjs --check
#        drift check: every generated plugin/workflows/*.js must match a fresh
#        in-memory build of its plugin/workflow-src/ and plugin/references/ sources.
#   2. node --test tests/workflow-scripts/*.test.mjs
#        the node:test unit and contract tests for the workflow libraries, the
#        built scripts and the builder itself.
#
# Requires Node 18 or later (node:test and `node --test <files>`). Fails closed with a
# message naming node when node is absent or older.
#
# Output: on success, only the drift-check result and the node:test summary counts are
# printed. On failure, the full output of the failing step is printed. Exits non-zero on
# any failure.
#
# Usage:
#   ./tools/test_workflow_scripts.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
MIN_NODE_MAJOR=18
BUILDER="tools/build_workflows.mjs"
TEST_DIR="tests/workflow-scripts"

command -v node >/dev/null 2>&1 || {
  echo "FAIL: node is required (Node ${MIN_NODE_MAJOR} or later) but was not found on PATH" >&2
  exit 2
}

node_version="$(node -p 'process.versions.node')"
node_major="${node_version%%.*}"
if ! [[ "$node_major" =~ ^[0-9]+$ ]] || (( node_major < MIN_NODE_MAJOR )); then
  echo "FAIL: node ${node_version} found; Node ${MIN_NODE_MAJOR} or later is required" >&2
  exit 2
fi

cd "$REPO_ROOT"

[[ -f "$BUILDER" ]] || { echo "FAIL: builder missing: $BUILDER" >&2; exit 2; }

test_files=()
for test_file in "$TEST_DIR"/*.test.mjs; do
  [[ -f "$test_file" ]] && test_files+=("$test_file")
done
if [[ ${#test_files[@]} -eq 0 ]]; then
  echo "FAIL: no test files match $TEST_DIR/*.test.mjs" >&2
  exit 2
fi

TMPDIR_TEST="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

check_log="$TMPDIR_TEST/build-check.log"
check_rc=0
node "$BUILDER" --check >"$check_log" 2>&1 || check_rc=$?
if [[ "$check_rc" -ne 0 ]]; then
  cat "$check_log" >&2
  echo "FAIL: node $BUILDER --check exited $check_rc (generated workflow scripts are stale or the build failed)" >&2
  exit 1
fi
echo "PASS: node $BUILDER --check (generated workflow scripts match their sources)"

test_log="$TMPDIR_TEST/node-test.log"
test_rc=0
node --test "${test_files[@]}" >"$test_log" 2>&1 || test_rc=$?
if [[ "$test_rc" -ne 0 ]]; then
  cat "$test_log" >&2
  echo "FAIL: node --test exited $test_rc over ${#test_files[@]} file(s) in $TEST_DIR" >&2
  exit 1
fi
grep -E '^(# |ℹ )(tests|suites|pass|fail|cancelled|skipped|todo) ' "$test_log" || true
echo "PASS: node --test over ${#test_files[@]} file(s) in $TEST_DIR"
