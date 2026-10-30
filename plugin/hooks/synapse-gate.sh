#!/usr/bin/env bash
#
# synapse-gate: plugin PreToolUse hook for the Bash and Write tools. It lets the hivemind:synapse
# agent run the five runner scripts with no permission prompt, only in their exact form, and bounds
# everything else synapse can do. Rules and rationale: ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md
# (Synapse Runner Gate).
#
# DECISIONS
#   Bash, agent type hivemind:synapse, exact runner command        allow
#   Bash, any other agent, exact runner command                     no decision (normal flow)
#   Bash, any agent, names a runner script file, not exact          deny; the reason gives the
#                                                                   exact form and points to Read
#   Bash, agent type hivemind:synapse, anything else                deny
#   Write, agent type hivemind:synapse, .hivemind/molt-inputs-<token>.json or
#     .hivemind/pr-inputs-<token>.json, relative or under the input cwd, the parent resolving
#     to <cwd>/.hivemind and the leaf not a symlink                 allow
#   Write, agent type hivemind:synapse, anything else               deny
#   anything else                                                   no decision
#
# EXACT RUNNER COMMAND: `bash`, one space, the script path, then flag/value pairs, every part
# separated by one space. The script path is "<root>/skills/<s>/scripts/<s>.sh", always one
# double-quoted word, where <root> is CLAUDE_PLUGIN_ROOT with backslashes turned to `/` and
# trailing slashes removed. A root that holds `"`, `$`, a backtick or a control byte has no exact
# form, so every runner command under it is denied (a recorded residual). Flags come in any order; each appears once except the repeatable --ref and
# --version-file; required flags must be present; bump-type's positional base comes first. Values
# pass their class: names hivemind_assert_identifier (skills/_shared/allowlist.sh), refs digits,
# commit 40 or 64 lowercase hex, the enums the scripts define, inputs
# .hivemind/<molt|pr>-inputs-<token>.json with <token> 1 to 64 of [A-Za-z0-9-]. A tab, newline or
# other control byte, any other quoting, a redirection or anything appended is not exact.
#
# LOOKALIKE: the command text names <s>.sh (ASCII case ignored) with no [A-Za-z0-9._-] byte
# directly before or after it.
#
# FAIL OPEN, NEVER TOWARD ALLOW: missing jq, an empty or unusable CLAUDE_PLUGIN_ROOT, a missing
# allowlist.sh, or malformed input prints nothing and exits 0, so the normal permission flow
# applies. The EXIT trap turns any other non-zero exit into 1. This hook never exits 2, because
# exit 2 blocks the tool call. A decision is printed only as the last step.
#
# Reads CLAUDE_PLUGIN_ROOT from the hook environment and never BASH_SOURCE. bash 3.2 compatible
# (no mapfile, associative arrays or ${var,,}).

set -euo pipefail
trap 'trap_status=$?; [ "$trap_status" -eq 0 ] || exit 1' EXIT

unset CDPATH
export LC_ALL=C

gate_agent_type=''
runner_scripts=()
runner_count=0

# add_gate_member <kind> <value>
#   Registers one allowed member: kind agent_type sets the one agent type the allow applies to,
#   kind script adds one runner script name.
add_gate_member() {
  case "$1" in
    agent_type) gate_agent_type="$2" ;;
    script)
      runner_scripts[runner_count]="$2"
      runner_count=$((runner_count + 1))
      ;;
    *) exit 1 ;;
  esac
}

add_gate_member agent_type hivemind:synapse
add_gate_member script molt
add_gate_member script gather-facts
add_gate_member script create-working-branch
add_gate_member script bump-type
add_gate_member script open-plan-pr

# runner_usage_text <script>
#   Prints the argument part of the script's exact form, for a deny reason.
runner_usage_text() {
  case "$1" in
    molt) printf '%s' '--trunk <branch> --inputs .hivemind/molt-inputs-<token>.json' ;;
    gather-facts) printf '%s' '--trunk <branch> [--remote <remote>] [--ref <number>]...' ;;
    create-working-branch) printf '%s' '--base <branch> --branch <branch> --classification feature|bugfix|hotfix|refactor|chore|docs|test|ci --trunk-freshness fresh|stale|skipped --trunk <branch>' ;;
    bump-type) printf '%s' '<base> --bump-trigger yes|no --no-bump-match yes|no [--version-file <path>]...' ;;
    open-plan-pr) printf '%s' '--head <branch> --base <branch> [--remote <remote>] [--expect-commit <commit>] --inputs .hivemind/pr-inputs-<token>.json' ;;
    *) return 1 ;;
  esac
}

# runner_required_flags <script>
#   Prints the space-separated flags the script requires.
runner_required_flags() {
  case "$1" in
    molt) printf '%s' '--trunk --inputs' ;;
    gather-facts) printf '%s' '--trunk' ;;
    create-working-branch) printf '%s' '--base --branch --classification --trunk-freshness --trunk' ;;
    bump-type) printf '%s' '--bump-trigger --no-bump-match' ;;
    open-plan-pr) printf '%s' '--head --base --inputs' ;;
    *) return 1 ;;
  esac
}

# set_flag_rule <script> <flag>
#   Sets flag_class and flag_repeat for a flag the script accepts; returns 1 for any other flag.
set_flag_rule() {
  flag_repeat=no
  case "$1 $2" in
    'molt --trunk') flag_class=identifier ;;
    'molt --inputs') flag_class=molt_inputs ;;
    'gather-facts --trunk' | 'gather-facts --remote') flag_class=identifier ;;
    'gather-facts --ref') flag_class=digits; flag_repeat=yes ;;
    'create-working-branch --base' | 'create-working-branch --branch' | 'create-working-branch --trunk') flag_class=identifier ;;
    'create-working-branch --classification') flag_class=classification ;;
    'create-working-branch --trunk-freshness') flag_class=freshness ;;
    'bump-type --bump-trigger' | 'bump-type --no-bump-match') flag_class=yes_no ;;
    'bump-type --version-file') flag_class=identifier; flag_repeat=yes ;;
    'open-plan-pr --head' | 'open-plan-pr --base' | 'open-plan-pr --remote') flag_class=identifier ;;
    'open-plan-pr --expect-commit') flag_class=commit ;;
    'open-plan-pr --inputs') flag_class=pr_inputs ;;
    *) return 1 ;;
  esac
}

# check_inputs_token <token>
#   Succeeds when <token> is 1 to 64 bytes of [A-Za-z0-9-].
check_inputs_token() {
  [ "${#1}" -ge 1 ] && [ "${#1}" -le 64 ] || return 1
  case "$1" in
    *[!A-Za-z0-9-]*) return 1 ;;
  esac
}

# check_inputs_leaf <kind> <leaf>
#   Succeeds when <leaf> is <kind>-inputs-<token>.json.
check_inputs_leaf() {
  local leaf_token
  case "$2" in
    "$1-inputs-"*.json) ;;
    *) return 1 ;;
  esac
  leaf_token="${2#"$1-inputs-"}"
  leaf_token="${leaf_token%.json}"
  check_inputs_token "$leaf_token"
}

# check_value_class <class> <value>
#   Succeeds when <value> belongs to <class>.
check_value_class() {
  case "$1" in
    identifier) hivemind_assert_identifier "$2" ;;
    digits)
      case "$2" in
        '' | *[!0-9]*) return 1 ;;
      esac
      ;;
    commit)
      [ "${#2}" -eq 40 ] || [ "${#2}" -eq 64 ] || return 1
      case "$2" in
        *[!0-9a-f]*) return 1 ;;
      esac
      ;;
    classification)
      case "$2" in
        feature | bugfix | hotfix | refactor | chore | docs | test | ci) ;;
        *) return 1 ;;
      esac
      ;;
    freshness)
      case "$2" in
        fresh | stale | skipped) ;;
        *) return 1 ;;
      esac
      ;;
    yes_no)
      case "$2" in
        yes | no) ;;
        *) return 1 ;;
      esac
      ;;
    molt_inputs | pr_inputs)
      case "$2" in
        .hivemind/*) check_inputs_leaf "${1%_inputs}" "${2#.hivemind/}" ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# split_argument_tokens <arguments>
#   Splits <arguments> on single spaces into argument_tokens / argument_count; returns 1 on an
#   empty token (a doubled, leading or trailing space).
split_argument_tokens() {
  local remaining_text="$1" token_text
  argument_tokens=()
  argument_count=0
  [ -n "$remaining_text" ] || return 0
  while :; do
    token_text="${remaining_text%% *}"
    [ -n "$token_text" ] || return 1
    argument_tokens[argument_count]="$token_text"
    argument_count=$((argument_count + 1))
    [ "$token_text" != "$remaining_text" ] || return 0
    remaining_text="${remaining_text#* }"
  done
}

# check_runner_arguments <script> <arguments>
#   Succeeds when <arguments> is exactly the script's grammar.
check_runner_arguments() {
  local script_name="$1" seen_flags=' ' token_index=0 flag_name required_flag
  case "$2" in
    *[!A-Za-z0-9._/\ -]*) return 1 ;;
  esac
  split_argument_tokens "$2" || return 1
  if [ "$script_name" = bump-type ]; then
    [ "$argument_count" -ge 1 ] || return 1
    check_value_class identifier "${argument_tokens[0]}" || return 1
    token_index=1
  fi
  while [ "$token_index" -lt "$argument_count" ]; do
    flag_name="${argument_tokens[token_index]}"
    set_flag_rule "$script_name" "$flag_name" || return 1
    if [ "$flag_repeat" = no ]; then
      case "$seen_flags" in
        *" $flag_name "*) return 1 ;;
      esac
    fi
    [ $((token_index + 1)) -lt "$argument_count" ] || return 1
    check_value_class "$flag_class" "${argument_tokens[token_index + 1]}" || return 1
    seen_flags="$seen_flags$flag_name "
    token_index=$((token_index + 2))
  done
  for required_flag in $(runner_required_flags "$script_name"); do
    case "$seen_flags" in
      *" $required_flag "*) ;;
      *) return 1 ;;
    esac
  done
}

# match_exact_command <command>
#   Succeeds when <command> is the exact form of one runner script.
match_exact_command() {
  local command_text="$1" script_name command_prefix argument_text
  [ "$quoted_path_allowed" = yes ] || return 1
  case "$command_text" in
    *[[:cntrl:]]*) return 1 ;;
  esac
  for script_name in "${runner_scripts[@]}"; do
    command_prefix="bash \"$plugin_root/skills/$script_name/scripts/$script_name.sh\""
    case "$command_text" in
      "$command_prefix") argument_text='' ;;
      "$command_prefix "*) argument_text="${command_text#"$command_prefix "}" ;;
      *) continue ;;
    esac
    check_runner_arguments "$script_name" "$argument_text" && return 0
  done
  return 1
}

# find_named_script <command>
#   Sets named_script to the first runner script whose file name the command text names as a path
#   part (ASCII case ignored); returns 1 when it names none.
find_named_script() {
  local lowered_text script_name file_name remaining_text text_before text_after byte_before byte_after
  case "$1" in
    *.[Ss][Hh]*) ;;
    *) return 1 ;;
  esac
  lowered_text="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  for script_name in "${runner_scripts[@]}"; do
    file_name="$script_name.sh"
    remaining_text="$lowered_text"
    while :; do
      case "$remaining_text" in
        *"$file_name"*) ;;
        *) break ;;
      esac
      text_before="${remaining_text%%"$file_name"*}"
      text_after="${remaining_text#*"$file_name"}"
      byte_before="${text_before: -1}"
      byte_after="${text_after:0:1}"
      case "$byte_before" in
        [a-z0-9._-]) ;;
        *)
          case "$byte_after" in
            [a-z0-9._-]) ;;
            *)
              named_script="$script_name"
              return 0
              ;;
          esac
          ;;
      esac
      remaining_text="h$text_after"
    done
  done
  return 1
}

# check_inputs_write <file-path> <cwd>
#   Succeeds when <file-path> is a synapse inputs file inside <cwd>/.hivemind, that folder resolves
#   to itself and the leaf is not a symlink or a non-regular file.
check_inputs_write() {
  local file_path="$1" work_dir="$2" leaf_name canonical_dir canonical_parent
  case "$file_path$work_dir" in
    *[[:cntrl:]]*) return 1 ;;
  esac
  case "$work_dir" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$file_path" in
    .hivemind/*) leaf_name="${file_path#.hivemind/}" ;;
    "$work_dir/.hivemind/"*) leaf_name="${file_path#"$work_dir/.hivemind/"}" ;;
    *) return 1 ;;
  esac
  check_inputs_leaf molt "$leaf_name" || check_inputs_leaf pr "$leaf_name" || return 1
  [ ! -L "$work_dir/.hivemind" ] || return 1
  canonical_dir="$(cd -P -- "$work_dir" 2>/dev/null && pwd -P)" || return 1
  canonical_parent="$(cd -P -- "$work_dir/.hivemind" 2>/dev/null && pwd -P)" || return 1
  [ "$canonical_parent" = "$canonical_dir/.hivemind" ] || return 1
  [ ! -L "$work_dir/.hivemind/$leaf_name" ] || return 1
  if [ -e "$work_dir/.hivemind/$leaf_name" ] && [ ! -f "$work_dir/.hivemind/$leaf_name" ]; then
    return 1
  fi
}

# read_input_fields
#   Sets tool_name, agent_type, first_value and second_value from the hook input in one jq run:
#   Bash gives the command and an empty second value, Write gives file_path and cwd, any other
#   tool gives two empty values. Values are kept byte for byte, except that NUL becomes \001, so it
#   stays a visible control byte and cannot end a field early. Returns 1 when the input is not a
#   JSON object or a selected value is not a string.
read_input_fields() {
  local end_marker=''
  {
    IFS= read -r -d '' tool_name \
      && IFS= read -r -d '' agent_type \
      && IFS= read -r -d '' first_value \
      && IFS= read -r -d '' second_value \
      && IFS= read -r -d '' end_marker
  } < <(printf '%s' "$input_json" | jq -j "$input_fields_program" 2>/dev/null) || return 1
  [ "$end_marker" = end ]
}

# emit_decision <allow|deny> <reason>
#   Prints the PreToolUse decision object.
emit_decision() {
  local decision_json
  decision_json="$(jq -cn --arg decision "$1" --arg reason "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $decision, permissionDecisionReason: $reason}}')" || exit 1
  printf '%s\n' "$decision_json"
}

command -v jq >/dev/null 2>&1 || exit 0

plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
plugin_root="${plugin_root//\\//}"
while [ "${plugin_root%/}" != "$plugin_root" ]; do
  plugin_root="${plugin_root%/}"
done
[ -n "$plugin_root" ] || exit 0
case "$plugin_root" in
  /* | [A-Za-z]:/*) ;;
  *) exit 0 ;;
esac
[ -f "$plugin_root/skills/_shared/allowlist.sh" ] || exit 0
. "$plugin_root/skills/_shared/allowlist.sh" || exit 0

quoted_path_allowed=yes
case "$plugin_root" in
  *'"'* | *'$'* | *'`'* | *[[:cntrl:]]*) quoted_path_allowed=no ;;
esac

input_fields_program='def text: if type == "string" then explode | map(if . == 0 then 1 else . end) | implode else error("not a string") end;
(.tool_name | text) as $tool
| [$tool, (.agent_type // "" | text)]
  + (if $tool == "Bash" then [(.tool_input.command // "" | text), ""]
     elif $tool == "Write" then [(.tool_input.file_path // "" | text), (.cwd // "" | text)]
     else ["", ""] end)
  + ["end"]
| map(. + "\u0000") | add'

input_json=''
IFS= read -r -d '' input_json || true
read_input_fields || exit 0

case "$tool_name" in
  Bash)
    if match_exact_command "$first_value"; then
      if [ "$agent_type" = "$gate_agent_type" ]; then
        emit_decision allow "synapse-gate: exact runner command for $gate_agent_type"
      fi
      exit 0
    fi
    named_script=''
    if find_named_script "$first_value"; then
      emit_decision deny "synapse-gate: a Bash command that names $named_script.sh runs only in its exact form: bash \"$plugin_root/skills/$named_script/scripts/$named_script.sh\" $(runner_usage_text "$named_script") (one space between parts, the script path in double quotes, no other quoting, nothing appended). To read the file, use the Read tool."
      exit 0
    fi
    if [ "$agent_type" = "$gate_agent_type" ]; then
      emit_decision deny "synapse-gate: $gate_agent_type may run only the exact form of a runner script command"
    fi
    ;;
  Write)
    [ "$agent_type" = "$gate_agent_type" ] || exit 0
    if check_inputs_write "$first_value" "$second_value"; then
      emit_decision allow "synapse-gate: inputs file write for $gate_agent_type"
    else
      emit_decision deny "synapse-gate: $gate_agent_type may Write only .hivemind/molt-inputs-<token>.json or .hivemind/pr-inputs-<token>.json in the working directory, where .hivemind is a real folder and the file is not a symlink"
    fi
    ;;
esac
exit 0
