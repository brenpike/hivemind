#!/usr/bin/env bash
#
# Table-driven suite for the synapse runner gate hook:
#   plugin/hooks/synapse-gate.sh   (PreToolUse, Bash and Write)
#   plugin/hooks/hooks.json        (the exec-form hook registration)
#
# Each case pipes one hook-input JSON object into the hook with CLAUDE_PLUGIN_ROOT set and checks
# the decision: allow, deny, or none (no output, so the normal permission flow applies). Every case
# also checks the exit status: 0 for every decision path, and never 2, because exit 2 blocks the
# tool call. Rules under test: plugin/governance/security-policy.md (Synapse Runner Gate).
#
# OFFLINE: needs bash and jq only. Writes only under a mktemp folder removed on EXIT.
#
# Usage:
#   ./tools/test_synapse_gate.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PLUGIN_ROOT="$REPO_ROOT/plugin"
HOOK="$PLUGIN_ROOT/hooks/synapse-gate.sh"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"

[ -f "$HOOK" ] || { echo "FAIL: hook under test missing: $HOOK" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: required dependency 'jq' is not installed" >&2; exit 2; }

WORK_ROOT="$(mktemp -d)"
remove_work_root() { rm -rf "$WORK_ROOT"; }
trap remove_work_root EXIT

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

SYNAPSE='hivemind:synapse'
DRONE='hivemind:drone'
SHA40='0123456789abcdef0123456789abcdef01234567'
SHA64='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
TOKEN65='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
TOKEN64="${TOKEN65%a}"

# script_path <root> <script>: print the runner script path under <root>.
script_path() { printf '%s/skills/%s/scripts/%s.sh' "$1" "$2" "$2"; }

# bash_input <agent> <command> [cwd]: print a Bash hook input; an empty agent omits agent_type.
bash_input() {
  jq -cn --arg agent "$1" --arg command "$2" --arg cwd "${3:-$WORK_ROOT}" \
    '{session_id: "s", cwd: $cwd, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $command}}
     + (if $agent == "" then {} else {agent_type: $agent} end)'
}

# write_input <agent> <file-path> <cwd>: print a Write hook input.
write_input() {
  jq -cn --arg agent "$1" --arg file_path "$2" --arg cwd "$3" \
    '{session_id: "s", cwd: $cwd, hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {file_path: $file_path, content: "{}"}}
     + (if $agent == "" then {} else {agent_type: $agent} end)'
}

# run_hook <root> <input> [path]: run the hook; set hook_output and hook_status.
run_hook() {
  if [ -n "${3:-}" ]; then
    hook_output="$(printf '%s' "$2" | PATH="$3" CLAUDE_PLUGIN_ROOT="$1" "$BASH" "$HOOK" 2>/dev/null)"
  else
    hook_output="$(printf '%s' "$2" | CLAUDE_PLUGIN_ROOT="$1" "$BASH" "$HOOK" 2>/dev/null)"
  fi
  hook_status=$?
}

# read_decision: print allow, deny, none, or invalid for hook_output.
read_decision() {
  if [ -z "$hook_output" ]; then
    printf 'none'
    return 0
  fi
  printf '%s' "$hook_output" | jq -r '
    if (.hookSpecificOutput.hookEventName == "PreToolUse")
       and ((.hookSpecificOutput.permissionDecisionReason | type) == "string")
       and (.hookSpecificOutput.permissionDecision == "allow" or .hookSpecificOutput.permissionDecision == "deny")
    then .hookSpecificOutput.permissionDecision else "invalid" end' 2>/dev/null || printf 'invalid'
}

# expect_decision <id> <expected> <root> <input> [path]: run one case and record the result.
expect_decision() {
  local actual
  run_hook "$3" "$4" "${5:-}"
  actual="$(read_decision)"
  if [ "$actual" = "$2" ] && [ "$hook_status" -eq 0 ]; then
    pass "$1" "$2"
  else
    failed "$1" "expected $2 exit 0, got $actual exit $hook_status output=$hook_output"
  fi
}

# expect_bash <id> <agent> <expected> <command>: one Bash case under the real plugin root.
expect_bash() { expect_decision "$1" "$3" "$PLUGIN_ROOT" "$(bash_input "$2" "$4")"; }

# ── exact forms ─────────────────────────────────────────────────────────────────
MOLT_ARGS='--trunk main --inputs .hivemind/molt-inputs-Tok-1.json'
FACTS_ARGS='--trunk main --remote origin --ref 12 --ref 7'
BRANCH_ARGS='--base main --branch feature/467-x --classification feature --trunk-freshness fresh --trunk main'
BUMP_ARGS="$SHA40 --bump-trigger yes --no-bump-match no --version-file plugin/.claude-plugin/plugin.json --version-file CHANGELOG.md"
PR_ARGS="--head feature/x --base main --remote origin --expect-commit $SHA64 --inputs .hivemind/pr-inputs-abc.json"

exact_args() {
  case "$1" in
    molt) printf '%s' "$MOLT_ARGS" ;;
    gather-facts) printf '%s' "$FACTS_ARGS" ;;
    create-working-branch) printf '%s' "$BRANCH_ARGS" ;;
    bump-type) printf '%s' "$BUMP_ARGS" ;;
    open-plan-pr) printf '%s' "$PR_ARGS" ;;
  esac
}

RUNNERS='molt gather-facts create-working-branch bump-type open-plan-pr'
for runner in $RUNNERS; do
  bare_command="bash $(script_path "$PLUGIN_ROOT" "$runner") $(exact_args "$runner")"
  quoted_command="bash \"$(script_path "$PLUGIN_ROOT" "$runner")\" $(exact_args "$runner")"
  expect_bash "exact:$runner:synapse" "$SYNAPSE" allow "$quoted_command"
  expect_bash "exact:$runner:drone" "$DRONE" none "$quoted_command"
  expect_bash "exact:$runner:main-session" '' none "$quoted_command"
  expect_bash "bare-path:$runner:synapse" "$SYNAPSE" deny "$bare_command"
  expect_bash "bare-path:$runner:drone" "$DRONE" deny "$bare_command"
done

MOLT="$(script_path "$PLUGIN_ROOT" molt)"
FACTS="$(script_path "$PLUGIN_ROOT" gather-facts)"
BRANCH="$(script_path "$PLUGIN_ROOT" create-working-branch)"
BUMP="$(script_path "$PLUGIN_ROOT" bump-type)"
PR="$(script_path "$PLUGIN_ROOT" open-plan-pr)"
QUOTED_MOLT="\"$MOLT\""
QUOTED_FACTS="\"$FACTS\""
QUOTED_BRANCH="\"$BRANCH\""
QUOTED_BUMP="\"$BUMP\""
QUOTED_PR="\"$PR\""

expect_bash 'exact:flags-any-order' "$SYNAPSE" allow "bash $QUOTED_MOLT --inputs .hivemind/molt-inputs-z.json --trunk main"
expect_bash 'exact:facts-trunk-only' "$SYNAPSE" allow "bash $QUOTED_FACTS --trunk main"
expect_bash 'exact:pr-minimal' "$SYNAPSE" allow "bash $QUOTED_PR --head feature/x --base main --inputs .hivemind/pr-inputs-a.json"
expect_bash 'exact:pr-commit-40' "$SYNAPSE" allow "bash $QUOTED_PR --head feature/x --base main --expect-commit $SHA40 --inputs .hivemind/pr-inputs-a.json"
expect_bash 'exact:bump-no-version-file' "$SYNAPSE" allow "bash $QUOTED_BUMP main --bump-trigger no --no-bump-match yes"
expect_bash 'exact:token-64' "$SYNAPSE" allow "bash $QUOTED_MOLT --trunk main --inputs .hivemind/molt-inputs-$TOKEN64.json"
expect_bash 'exact:value-naming-a-script' "$SYNAPSE" allow "bash $QUOTED_FACTS --trunk molt.sh"
for freshness in stale skipped; do
  expect_bash "exact:freshness-$freshness" "$SYNAPSE" allow "bash $QUOTED_BRANCH --base main --branch fix/a --classification bugfix --trunk-freshness $freshness --trunk main"
done

# ── not exact: denied for synapse and, as lookalikes, for every agent ──────────────
MOLT_EXACT="bash $QUOTED_MOLT $MOLT_ARGS"
NL=$'\n'
TAB=$'\t'
NOT_EXACT_CASES=(
  "semicolon|$MOLT_EXACT; touch x"
  "and-list|$MOLT_EXACT && echo done"
  "pipe|$MOLT_EXACT | cat"
  "redirect-2>&1|$MOLT_EXACT 2>&1"
  "redirect-out|$MOLT_EXACT >out.txt"
  "newline|$MOLT_EXACT${NL}touch x"
  "trailing-newline|$MOLT_EXACT${NL}"
  "tab-separator|bash $QUOTED_MOLT --trunk${TAB}main --inputs .hivemind/molt-inputs-a.json"
  "quoted-argument|bash $QUOTED_MOLT --trunk \"main\" --inputs .hivemind/molt-inputs-a.json"
  "single-quoted-argument|bash $QUOTED_MOLT --trunk 'main' --inputs .hivemind/molt-inputs-a.json"
  "dotdot-value|bash $QUOTED_MOLT --trunk ../main --inputs .hivemind/molt-inputs-a.json"
  "dash-value|bash $QUOTED_MOLT --trunk -x --inputs .hivemind/molt-inputs-a.json"
  "command-substitution|bash $QUOTED_MOLT --trunk \$(id) --inputs .hivemind/molt-inputs-a.json"
  "backtick|bash $QUOTED_MOLT --trunk \`id\` --inputs .hivemind/molt-inputs-a.json"
  "variable|bash $QUOTED_MOLT --trunk \$HOME --inputs .hivemind/molt-inputs-a.json"
  "glob-value|bash $QUOTED_MOLT --trunk ma* --inputs .hivemind/molt-inputs-a.json"
  "inputs-absolute|bash $QUOTED_MOLT --trunk main --inputs /tmp/molt-inputs-a.json"
  "inputs-wrong-kind|bash $QUOTED_MOLT --trunk main --inputs .hivemind/pr-inputs-a.json"
  "inputs-empty-token|bash $QUOTED_MOLT --trunk main --inputs .hivemind/molt-inputs-.json"
  "inputs-token-65|bash $QUOTED_MOLT --trunk main --inputs .hivemind/molt-inputs-$TOKEN65.json"
  "inputs-subfolder|bash $QUOTED_MOLT --trunk main --inputs .hivemind/molt-inputs-a/b.json"
  "inputs-traversal|bash $QUOTED_MOLT --trunk main --inputs .hivemind/../molt-inputs-a.json"
  "inputs-dot-slash|bash $QUOTED_MOLT --trunk main --inputs ./.hivemind/molt-inputs-a.json"
  "inputs-token-underscore|bash $QUOTED_MOLT --trunk main --inputs .hivemind/molt-inputs-a_b.json"
  "duplicate-flag|bash $QUOTED_MOLT --trunk main --trunk main --inputs .hivemind/molt-inputs-a.json"
  "missing-required|bash $QUOTED_MOLT --trunk main"
  "no-arguments|bash $QUOTED_MOLT"
  "unknown-flag|bash $QUOTED_MOLT --trunk main --inputs .hivemind/molt-inputs-a.json --force yes"
  "flag-without-value|bash $QUOTED_MOLT --inputs .hivemind/molt-inputs-a.json --trunk"
  "equals-form|bash $QUOTED_MOLT --trunk=main --inputs=.hivemind/molt-inputs-a.json"
  "double-space|bash $QUOTED_MOLT --trunk  main --inputs .hivemind/molt-inputs-a.json"
  "double-space-after-bash|bash  $QUOTED_MOLT $MOLT_ARGS"
  "trailing-space|$MOLT_EXACT "
  "leading-space| $MOLT_EXACT"
  "sh-interpreter|sh $QUOTED_MOLT $MOLT_ARGS"
  "bash-option|bash -x $QUOTED_MOLT $MOLT_ARGS"
  "env-prefix|env bash $QUOTED_MOLT $MOLT_ARGS"
  "direct-exec|$QUOTED_MOLT $MOLT_ARGS"
  "whole-command-quoted|\"bash $MOLT\" $MOLT_ARGS"
  "single-quoted-path|bash '$MOLT' $MOLT_ARGS"
  "partly-quoted-path|bash \"$PLUGIN_ROOT\"/skills/molt/scripts/molt.sh $MOLT_ARGS"
  "planted-relative-copy|bash \"skills/molt/scripts/molt.sh\" $MOLT_ARGS"
  "planted-dot-relative|bash \"./plugin/skills/molt/scripts/molt.sh\" $MOLT_ARGS"
  "another-root|bash \"/tmp/other/skills/molt/scripts/molt.sh\" $MOLT_ARGS"
  "root-traversal|bash \"$PLUGIN_ROOT/../plugin/skills/molt/scripts/molt.sh\" $MOLT_ARGS"
  "script-mismatch|bash \"$PLUGIN_ROOT/skills/molt/scripts/gather-facts.sh\" --trunk main"
  "path-quote-unclosed|bash \"$MOLT $MOLT_ARGS"
  "path-quote-doubled|bash \"$QUOTED_MOLT\" $MOLT_ARGS"
  "facts-ref-not-digits|bash $QUOTED_FACTS --trunk main --ref 12a"
  "facts-ref-hash|bash $QUOTED_FACTS --trunk main --ref #12"
  "branch-bad-classification|bash $QUOTED_BRANCH --base main --branch f/a --classification feat --trunk-freshness fresh --trunk main"
  "branch-bad-freshness|bash $QUOTED_BRANCH --base main --branch f/a --classification feature --trunk-freshness diverged --trunk main"
  "branch-missing-trunk|bash $QUOTED_BRANCH --base main --branch f/a --classification feature --trunk-freshness fresh"
  "bump-base-not-first|bash $QUOTED_BUMP --bump-trigger yes $SHA40 --no-bump-match no"
  "bump-two-bases|bash $QUOTED_BUMP main main --bump-trigger yes --no-bump-match no"
  "bump-bad-yes-no|bash $QUOTED_BUMP main --bump-trigger maybe --no-bump-match no"
  "bump-version-file-dotdot|bash $QUOTED_BUMP main --bump-trigger yes --no-bump-match no --version-file ../x.json"
  "pr-commit-uppercase|bash $QUOTED_PR --head f/x --base main --expect-commit 0123456789ABCDEF0123456789ABCDEF01234567 --inputs .hivemind/pr-inputs-a.json"
  "pr-commit-39|bash $QUOTED_PR --head f/x --base main --expect-commit ${SHA40%7} --inputs .hivemind/pr-inputs-a.json"
  "pr-molt-inputs|bash $QUOTED_PR --head f/x --base main --inputs .hivemind/molt-inputs-a.json"
  "pr-missing-inputs|bash $QUOTED_PR --head f/x --base main"
)
for case_row in "${NOT_EXACT_CASES[@]}"; do
  case_id="${case_row%%|*}"
  case_command="${case_row#*|}"
  expect_bash "not-exact:$case_id:synapse" "$SYNAPSE" deny "$case_command"
  expect_bash "not-exact:$case_id:drone" "$DRONE" deny "$case_command"
  expect_bash "not-exact:$case_id:main-session" '' deny "$case_command"
done

# ── lookalike detection and unrelated commands ─────────────────────────────────
LOOKALIKE_CASES=(
  "cat-relative|cat plugin/skills/molt/scripts/molt.sh"
  "grep|grep -n trunk plugin/skills/gather-facts/scripts/gather-facts.sh"
  "git-diff|git diff -- plugin/skills/open-plan-pr/scripts/open-plan-pr.sh"
  "shellcheck|shellcheck plugin/skills/bump-type/scripts/bump-type.sh"
  "bash-n|bash -n plugin/skills/create-working-branch/scripts/create-working-branch.sh"
  "bare-name|echo molt.sh"
  "quoted-name|echo \"open-plan-pr.sh\""
  "upper-case|cat plugin/skills/molt/scripts/MOLT.SH"
  "name-then-tilde|cat molt.sh~"
)
for case_row in "${LOOKALIKE_CASES[@]}"; do
  case_id="${case_row%%|*}"
  case_command="${case_row#*|}"
  expect_bash "lookalike:$case_id:drone" "$DRONE" deny "$case_command"
  expect_bash "lookalike:$case_id:synapse" "$SYNAPSE" deny "$case_command"
done

UNRELATED_CASES=(
  "ls|ls -la"
  "git-status|git status --porcelain"
  "prefixed-name|cat xmolt.sh"
  "suffixed-name|cat molt.sh.bak"
  "dashed-name|cat my-bump-type.sh"
  "push-branch|bash $(script_path "$PLUGIN_ROOT" push-branch) --head x"
  "script-folder|ls plugin/skills/molt/scripts/"
)
for case_row in "${UNRELATED_CASES[@]}"; do
  case_id="${case_row%%|*}"
  case_command="${case_row#*|}"
  expect_bash "unrelated:$case_id:drone" "$DRONE" none "$case_command"
  expect_bash "unrelated:$case_id:main-session" '' none "$case_command"
  expect_bash "unrelated:$case_id:synapse" "$SYNAPSE" deny "$case_command"
done

expect_bash 'agent-type:bare-synapse-name' 'synapse' deny "$MOLT_EXACT;"
expect_bash 'agent-type:bare-synapse-name-exact' 'synapse' none "$MOLT_EXACT"
expect_bash 'agent-type:other-plugin-synapse' 'other:synapse' none "$MOLT_EXACT"

run_hook "$PLUGIN_ROOT" "$(bash_input "$DRONE" "cat plugin/skills/molt/scripts/molt.sh")"
deny_reason="$(printf '%s' "$hook_output" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)"
case "$deny_reason" in
  *"bash $QUOTED_MOLT --trunk <branch> --inputs .hivemind/molt-inputs-<token>.json"*"Read tool"*)
    pass 'lookalike:reason' 'deny reason states the exact form and points to Read' ;;
  *) failed 'lookalike:reason' "reason=$deny_reason" ;;
esac

# ── synapse Write ───────────────────────────────────────────────────────────────
CHECKOUT="$WORK_ROOT/checkout"
mkdir -p "$CHECKOUT/.hivemind/molt-inputs-dir.json"
ln -s "$WORK_ROOT/outside.json" "$CHECKOUT/.hivemind/molt-inputs-leaf.json"
SYMLINKED="$WORK_ROOT/symlinked"
mkdir -p "$SYMLINKED" "$WORK_ROOT/elsewhere"
ln -s "$WORK_ROOT/elsewhere" "$SYMLINKED/.hivemind"
NO_FOLDER="$WORK_ROOT/no-folder"
mkdir -p "$NO_FOLDER"
CHECKOUT_LINK="$WORK_ROOT/checkout-link"
ln -s "$CHECKOUT" "$CHECKOUT_LINK"

WRITE_CASES=(
  "molt-relative|$SYNAPSE|.hivemind/molt-inputs-a1.json|$CHECKOUT|allow"
  "pr-relative|$SYNAPSE|.hivemind/pr-inputs-a1.json|$CHECKOUT|allow"
  "molt-absolute|$SYNAPSE|$CHECKOUT/.hivemind/molt-inputs-Z-9.json|$CHECKOUT|allow"
  "pr-absolute|$SYNAPSE|$CHECKOUT/.hivemind/pr-inputs-$TOKEN64.json|$CHECKOUT|allow"
  "cwd-through-symlink|$SYNAPSE|$CHECKOUT_LINK/.hivemind/pr-inputs-a.json|$CHECKOUT_LINK|allow"
  "token-65|$SYNAPSE|.hivemind/pr-inputs-$TOKEN65.json|$CHECKOUT|deny"
  "other-name|$SYNAPSE|$CHECKOUT/.hivemind/other.json|$CHECKOUT|deny"
  "checkout-root|$SYNAPSE|$CHECKOUT/molt-inputs-a.json|$CHECKOUT|deny"
  "other-folder|$SYNAPSE|$WORK_ROOT/.hivemind/molt-inputs-a.json|$CHECKOUT|deny"
  "subfolder|$SYNAPSE|.hivemind/sub/molt-inputs-a.json|$CHECKOUT|deny"
  "traversal|$SYNAPSE|$CHECKOUT/.hivemind/../.hivemind/molt-inputs-a.json|$CHECKOUT|deny"
  "dot-slash|$SYNAPSE|./.hivemind/molt-inputs-a.json|$CHECKOUT|deny"
  "suffix|$SYNAPSE|.hivemind/molt-inputs-a.json.bak|$CHECKOUT|deny"
  "source-file|$SYNAPSE|$CHECKOUT/plugin/skills/molt/scripts/molt.sh|$CHECKOUT|deny"
  "symlinked-folder|$SYNAPSE|$SYMLINKED/.hivemind/molt-inputs-a.json|$SYMLINKED|deny"
  "symlinked-folder-relative|$SYNAPSE|.hivemind/molt-inputs-a.json|$SYMLINKED|deny"
  "symlinked-leaf|$SYNAPSE|.hivemind/molt-inputs-leaf.json|$CHECKOUT|deny"
  "directory-leaf|$SYNAPSE|.hivemind/molt-inputs-dir.json|$CHECKOUT|deny"
  "missing-folder|$SYNAPSE|.hivemind/molt-inputs-a.json|$NO_FOLDER|deny"
  "relative-cwd|$SYNAPSE|.hivemind/molt-inputs-a.json|checkout|deny"
  "drone-inputs|$DRONE|.hivemind/molt-inputs-a.json|$CHECKOUT|none"
  "drone-elsewhere|$DRONE|/etc/passwd|$CHECKOUT|none"
  "main-session|-|$CHECKOUT/x.txt|$CHECKOUT|none"
)
for case_row in "${WRITE_CASES[@]}"; do
  IFS='|' read -r case_id case_agent case_path case_cwd case_expected <<<"$case_row"
  [ "$case_agent" != '-' ] || case_agent=''
  expect_decision "write:$case_id" "$case_expected" "$PLUGIN_ROOT" "$(write_input "$case_agent" "$case_path" "$case_cwd")"
done
expect_decision 'write:newline-path' deny "$PLUGIN_ROOT" "$(write_input "$SYNAPSE" ".hivemind/molt-inputs-a.json${NL}" "$CHECKOUT")"
expect_decision 'write:nul-path' deny "$PLUGIN_ROOT" \
  "$(jq -cn --arg cwd "$CHECKOUT" '{tool_name: "Write", agent_type: "hivemind:synapse", cwd: $cwd, tool_input: {file_path: ".hivemind/molt-inputs-a.json\u0000x"}}')"
expect_decision 'bash:nul-command' deny "$PLUGIN_ROOT" \
  "$(jq -cn --arg command "$MOLT_EXACT" '{tool_name: "Bash", agent_type: "hivemind:synapse", tool_input: {command: ($command + "\u0000")}}')"

# ── root used byte for byte and path quoting ────────────────────────────────────
expect_decision 'root:trailing-slash' allow "$PLUGIN_ROOT/" "$(bash_input "$SYNAPSE" "bash \"$(script_path "$PLUGIN_ROOT/" molt)\" $MOLT_ARGS")"
expect_decision 'root:trailing-slashes' allow "$PLUGIN_ROOT//" "$(bash_input "$SYNAPSE" "bash \"$(script_path "$PLUGIN_ROOT//" molt)\" $MOLT_ARGS")"
expect_decision 'root:trailing-slash:rewritten' deny "$PLUGIN_ROOT/" "$(bash_input "$SYNAPSE" "$MOLT_EXACT")"

# make_root <name>: create a fake plugin root holding allowlist.sh; print its path.
make_root() {
  mkdir -p "$WORK_ROOT/$1/skills/_shared"
  cp "$PLUGIN_ROOT/skills/_shared/allowlist.sh" "$WORK_ROOT/$1/skills/_shared/allowlist.sh"
  printf '%s' "$WORK_ROOT/$1"
}

SPACE_ROOT="$(make_root 'plug root')"
SPACE_MOLT="$(script_path "$SPACE_ROOT" molt)"
expect_decision 'root:space:quoted' allow "$SPACE_ROOT" "$(bash_input "$SYNAPSE" "bash \"$SPACE_MOLT\" $MOLT_ARGS")"
expect_decision 'root:space:bare' deny "$SPACE_ROOT" "$(bash_input "$SYNAPSE" "bash $SPACE_MOLT $MOLT_ARGS")"
expect_decision 'root:space:quoted:drone' none "$SPACE_ROOT" "$(bash_input "$DRONE" "bash \"$SPACE_MOLT\" $MOLT_ARGS")"
expect_decision 'root:space:bare:drone' deny "$SPACE_ROOT" "$(bash_input "$DRONE" "bash $SPACE_MOLT $MOLT_ARGS")"

for unsafe_name in 'plug$root' 'plug"root' 'plug`root' 'plug\root'; do
  UNSAFE_ROOT="$(make_root "$unsafe_name")"
  UNSAFE_MOLT="$(script_path "$UNSAFE_ROOT" molt)"
  expect_decision "root:unsafe:$unsafe_name:quoted" deny "$UNSAFE_ROOT" "$(bash_input "$SYNAPSE" "bash \"$UNSAFE_MOLT\" $MOLT_ARGS")"
  expect_decision "root:unsafe:$unsafe_name:bare" deny "$UNSAFE_ROOT" "$(bash_input "$SYNAPSE" "bash $UNSAFE_MOLT $MOLT_ARGS")"
done

BACKSLASH_ROOT="$(make_root 'bs/a\b')"
SIBLING_ROOT="$(make_root 'bs/a/b')"
SIBLING_COMMAND="bash \"$(script_path "$SIBLING_ROOT" molt)\" $MOLT_ARGS"
expect_decision 'root:backslash:sibling-command' deny "$BACKSLASH_ROOT" "$(bash_input "$SYNAPSE" "$SIBLING_COMMAND")"

EXIT2_BACKSLASH_ROOT="$(make_root 'bs-exit2/a\b')"
mkdir -p "$WORK_ROOT/bs-exit2/a/b/skills/_shared"
printf 'exit 2\n' >"$WORK_ROOT/bs-exit2/a/b/skills/_shared/allowlist.sh"
EXIT2_SIBLING_COMMAND="bash \"$(script_path "$WORK_ROOT/bs-exit2/a/b" molt)\" $MOLT_ARGS"
expect_decision 'root:backslash:sibling-never-sourced' deny "$EXIT2_BACKSLASH_ROOT" "$(bash_input "$SYNAPSE" "$EXIT2_SIBLING_COMMAND")"

# ── fail open: no output, exit 0 ────────────────────────────────────────────────
LOOKALIKE_INPUT="$(bash_input "$DRONE" "cat plugin/skills/molt/scripts/molt.sh")"
SYNAPSE_WRITE_INPUT="$(write_input "$SYNAPSE" "/etc/passwd" "$CHECKOUT")"
expect_decision 'fail-open:empty-root' none '' "$(bash_input "$SYNAPSE" "$MOLT_EXACT")"
expect_decision 'fail-open:empty-root-lookalike' none '' "$LOOKALIKE_INPUT"
expect_decision 'fail-open:empty-root-write' none '' "$SYNAPSE_WRITE_INPUT"
expect_decision 'fail-open:slash-only-root' none '/' "$LOOKALIKE_INPUT"
expect_decision 'fail-open:relative-root' none 'plugin' "$LOOKALIKE_INPUT"
expect_decision 'fail-open:root-without-allowlist' none "$WORK_ROOT/no-such-root" "$LOOKALIKE_INPUT"
expect_decision 'fail-open:malformed-json' none "$PLUGIN_ROOT" '{"tool_name": "Bash", "tool_input": '
expect_decision 'fail-open:empty-input' none "$PLUGIN_ROOT" ''
expect_decision 'fail-open:non-object' none "$PLUGIN_ROOT" '[1, 2]'
expect_decision 'fail-open:command-not-string' none "$PLUGIN_ROOT" '{"tool_name": "Bash", "agent_type": "hivemind:synapse", "tool_input": {"command": 5}}'
expect_decision 'fail-open:agent-not-string' none "$PLUGIN_ROOT" '{"tool_name": "Bash", "agent_type": 1, "tool_input": {"command": "cat molt.sh"}}'
expect_decision 'fail-open:other-tool' none "$PLUGIN_ROOT" '{"tool_name": "Edit", "agent_type": "hivemind:synapse", "tool_input": {"file_path": "/etc/passwd"}}'

EMPTY_BIN="$WORK_ROOT/empty-bin"
mkdir -p "$EMPTY_BIN"
expect_decision 'fail-open:missing-jq' none "$PLUGIN_ROOT" "$LOOKALIKE_INPUT" "$EMPTY_BIN"
expect_decision 'fail-open:missing-jq-synapse-write' none "$PLUGIN_ROOT" "$SYNAPSE_WRITE_INPUT" "$EMPTY_BIN"

EXIT2_ROOT="$WORK_ROOT/exit2-root"
mkdir -p "$EXIT2_ROOT/skills/_shared"
printf 'exit 2\n' >"$EXIT2_ROOT/skills/_shared/allowlist.sh"
run_hook "$EXIT2_ROOT" "$LOOKALIKE_INPUT"
if [ -z "$hook_output" ] && [ "$hook_status" -eq 1 ]; then
  pass 'fail-open:internal-exit-2-becomes-1' 'no output, exit 1'
else
  failed 'fail-open:internal-exit-2-becomes-1' "status=$hook_status output=$hook_output"
fi

BROKEN_ROOT="$WORK_ROOT/broken-root"
mkdir -p "$BROKEN_ROOT/skills/_shared"
printf 'hivemind_assert_identifier() {\n' >"$BROKEN_ROOT/skills/_shared/allowlist.sh"
run_hook "$BROKEN_ROOT" "$LOOKALIKE_INPUT"
if [ -z "$hook_output" ] && [ "$hook_status" -ne 2 ]; then
  pass 'fail-open:unparseable-allowlist' "no output, exit $hook_status"
else
  failed 'fail-open:unparseable-allowlist' "status=$hook_status output=$hook_output"
fi

if bash -n "$HOOK" 2>/dev/null; then
  pass 'hook:parses' 'bash -n'
else
  failed 'hook:parses' 'bash -n failed'
fi

# ── hooks.json ──────────────────────────────────────────────────────────────────
EXPECTED_ENTRY='{"type":"command","command":"bash","args":["${CLAUDE_PLUGIN_ROOT}/hooks/synapse-gate.sh"],"timeout":10}'
if jq -e --argjson entry "$EXPECTED_ENTRY" '
     (.hooks | keys) == ["PreToolUse"]
     and (.hooks.PreToolUse | length) == 1
     and .hooks.PreToolUse[0].matcher == "Bash|Write"
     and .hooks.PreToolUse[0].hooks == [$entry]' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass 'hooks-json:exec-form' 'parses and holds the one exec-form PreToolUse entry'
else
  failed 'hooks-json:exec-form' "unexpected content in $HOOKS_JSON"
fi

echo ''
echo "synapse gate: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
