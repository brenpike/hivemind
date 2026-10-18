#!/usr/bin/env bash
#
# Validates agent report text against the REL-4 report contracts
# (worker, blocked, planner, PR output, address-pr-feedback,
# watch-pr-feedback) from agent-system-policy.md and skill SKILL.md files.
#
# Parses a report file and checks structural compliance:
# - Detects report type via ordered heuristics
# - For worker (complete/partial): required sections and no standalone prose
# - For blocked: required fields with value constraints
# - For planner (compact/full): required fields and list sections
# - For PR output (open-plan-pr): required fields including PR URL
# - For address-pr-feedback: required fields with sub-field groups
# - For watch-pr-feedback: required fields with sub-field groups
#   (owned by the github-review-loop skill's terminal report, not the
#    github-reviewer agent; a returned run reports Monitoring: stopped)
# - Unknown type: diagnostic and fail
#
# Run against a single file or in batch mode against all .txt files in
# tests/reports/.
#
# Usage:
#   ./tools/validate_reports.sh -f tests/reports/valid-worker-complete.txt
#   ./tools/validate_reports.sh
#   ./tools/validate_reports.sh -b tests/reports/

set -euo pipefail

SCRIPT_DIR=$(dirname "$(realpath "$0")")
REPO_ROOT=$(dirname "$SCRIPT_DIR")

# ── Argument Parsing ──────────────────────────────────────────────────────

REPORT_FILE=""
BATCH_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|-ReportFile|--report-file)
            REPORT_FILE="$2"
            shift 2
            ;;
        -b|-Batch|--batch)
            BATCH_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# ── Constants ─────────────────────────────────────────────────────────────

VALID_STATUS_VALUES=("complete" "partial" "blocked")

WORKER_REQUIRED_SECTIONS=("Changed" "Validated" "Need scope change" "Issues")

BLOCKED_REQUIRED_FIELDS=("Stage" "Blocker" "Retry status" "Fallback used" "Impact" "Next action")

VALID_STAGE_VALUES=(
    "planning" "implementation" "validation" "git workflow"
    "versioning" "review remediation" "monitoring"
    "skill selection" "fetch" "parse" "route"
)

VALID_RETRY_STATUS_VALUES=("not attempted" "retried once" "exhausted")

OPTIONAL_WORKER_FIELDS=(
    "Refs"
    "States handled"
    "Commit"
    "Version"
    "Review item"
    "Git issue"
    "Ready to resolve"
    "Session facts"
)

# ── Planner Constants ────────────────────────────────────────────────────

PLANNER_COMPACT_INLINE_FIELDS=("Summary")

PLANNER_COMPACT_LIST_SECTIONS=("Memory reused" "Steps" "Workflow loadout" "Open questions")

# Recognized as a section boundary label; never required.
PLANNER_OPTIONAL_LIST_SECTIONS=("Decisions taken")

# Sub-fields stored as "Parent|Child1|Child2|..."
PLANNER_COMPACT_SUB_FIELDS=("Versioning|Impact|Artifact(s)")

PLANNER_FULL_EXTRA_LIST_SECTIONS=("Edge cases" "Shared-file risks")

PLANNER_FULL_EXTRA_SUB_FIELDS=("Delivery|Shape|Branch/PR|Worktrees")

# ── PR Output Constants ──────────────────────────────────────────────────

PR_OUTPUT_INLINE_FIELDS=(
    "Status" "Base" "Head" "Local HEAD" "Pushed"
    "Push remote" "PR head SHA" "Head verified" "PR title" "PR URL"
)

PR_OUTPUT_LIST_SECTIONS=("Warnings")

# ── address-pr-feedback Constants ────────────────────────────────────────

ADDRESS_FEEDBACK_SUB_FIELDS=(
    "PR|Number|Branch|Target"
    "Feedback|Source|Author|URL|Classification"
    "Git|Commit|Pushed"
    "Reply|Posted"
)

ADDRESS_FEEDBACK_LIST_SECTIONS=("Changed" "Validated" "Issues")

# ── watch-pr-feedback Constants ──────────────────────────────────────────
# Required fields of the github-review-loop skill's terminal report (the skill
# owns the watch loop and emits this report; the github-reviewer agent no longer
# does). A returned run is no longer monitoring, so Monitoring reports `stopped`.

WATCH_FEEDBACK_SUB_FIELDS=(
    "PR|Number|State|Branch|Target"
    "Watch|Mode|Monitoring|Parser|Cycles|Seen comments|New actionable comments"
)

WATCH_FEEDBACK_LIST_SECTIONS=("Routed" "Stopped because" "Next action" "Issues")

# ── Utility Functions ────────────────────────────────────────────────────

contains_value() {
    local target="$1"
    shift
    local item
    for item in "$@"; do
        if [[ "$item" == "$target" ]]; then
            return 0
        fi
    done
    return 1
}

contains_value_ci() {
    local target
    target=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    shift
    local item item_lower
    for item in "$@"; do
        item_lower=$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]')
        if [[ "$item_lower" == "$target" ]]; then
            return 0
        fi
    done
    return 1
}

# INVARIANT: label_prefixes_str is a newline-separated string of recognized field labels.
# This function does case-insensitive lookup against that string.
labels_contain() {
    local target="$1"
    local labels_str="$2"
    local target_lower
    target_lower=$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')
    local line line_lower
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        line_lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
        if [[ "$line_lower" == "$target_lower" ]]; then
            return 0
        fi
    done <<< "$labels_str"
    return 1
}

is_blank_line() {
    [[ "$1" =~ ^[[:space:]]*$ ]]
}

regex_escape() {
    printf '%s' "$1" | sed 's/[.[\*^$()+?{|\\]/\\&/g'
}

trim() {
    local val="$1"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    printf '%s' "$val"
}

# ── Build Label Prefix Lists (newline-delimited) ─────────────────────────

build_worker_labels() {
    local labels=("Status")
    labels+=("${WORKER_REQUIRED_SECTIONS[@]}")
    labels+=("${OPTIONAL_WORKER_FIELDS[@]}")
    local IFS=$'\n'
    printf '%s\n' "${labels[@]}"
}

build_blocked_labels() {
    local labels=("Status")
    labels+=("${BLOCKED_REQUIRED_FIELDS[@]}")
    labels+=("${OPTIONAL_WORKER_FIELDS[@]}")
    local IFS=$'\n'
    printf '%s\n' "${labels[@]}"
}

build_planner_labels() {
    local is_full_plan="$1"
    local labels=()
    labels+=("${PLANNER_COMPACT_INLINE_FIELDS[@]}")
    labels+=("${PLANNER_COMPACT_LIST_SECTIONS[@]}")
    labels+=("${PLANNER_OPTIONAL_LIST_SECTIONS[@]}")
    local entry
    for entry in "${PLANNER_COMPACT_SUB_FIELDS[@]}"; do
        IFS='|' read -ra parts <<< "$entry"
        labels+=("${parts[0]}")
    done
    labels+=("Owner" "Files" "Outcome" "Depends on")
    if $is_full_plan; then
        labels+=("${PLANNER_FULL_EXTRA_LIST_SECTIONS[@]}")
        for entry in "${PLANNER_FULL_EXTRA_SUB_FIELDS[@]}"; do
            IFS='|' read -ra parts <<< "$entry"
            labels+=("${parts[0]}")
        done
        labels+=("Likely bump" "Release files likely needed" "Item(s)" "Classification" "User decision needed")
    fi
    local IFS=$'\n'
    printf '%s\n' "${labels[@]}"
}

build_pr_output_labels() {
    local labels=()
    labels+=("${PR_OUTPUT_INLINE_FIELDS[@]}")
    labels+=("${PR_OUTPUT_LIST_SECTIONS[@]}")
    local IFS=$'\n'
    printf '%s\n' "${labels[@]}"
}

build_address_feedback_labels() {
    local labels=("Status")
    local entry
    for entry in "${ADDRESS_FEEDBACK_SUB_FIELDS[@]}"; do
        IFS='|' read -ra parts <<< "$entry"
        labels+=("${parts[0]}")
    done
    labels+=("${ADDRESS_FEEDBACK_LIST_SECTIONS[@]}")
    local IFS=$'\n'
    printf '%s\n' "${labels[@]}"
}

build_watch_feedback_labels() {
    local labels=("Status")
    local entry
    for entry in "${WATCH_FEEDBACK_SUB_FIELDS[@]}"; do
        IFS='|' read -ra parts <<< "$entry"
        labels+=("${parts[0]}")
    done
    labels+=("${WATCH_FEEDBACK_LIST_SECTIONS[@]}")
    local IFS=$'\n'
    printf '%s\n' "${labels[@]}"
}

# ── Report Type Detection ────────────────────────────────────────────────

detect_report_type() {
    local -n _lines_ref=$1
    local status_value="$2"
    local line

    # 1. PR output: contains any PR-output-exclusive field
    for line in "${_lines_ref[@]}"; do
        if [[ "$line" =~ ^(PR\ head\ SHA|PR\ title|Head\ verified|Local\ HEAD|Push\ remote):[[:space:]]* ]]; then
            echo "pr-output"
            return
        fi
    done

    # 2. address-pr-feedback: Feedback: section with Classification: sub-field
    local in_feedback=false
    for line in "${_lines_ref[@]}"; do
        if [[ "$line" =~ ^Feedback:[[:space:]]* ]]; then
            in_feedback=true
            continue
        fi
        if $in_feedback && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*Classification:[[:space:]]* ]]; then
            echo "address-pr-feedback"
            return
        fi
        if $in_feedback && [[ "$line" =~ ^[A-Z][^:]*:[[:space:]]* ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
            in_feedback=false
        fi
    done

    # 3. watch-pr-feedback: Watch: section with Monitoring: sub-field
    local in_watch=false
    for line in "${_lines_ref[@]}"; do
        if [[ "$line" =~ ^Watch:[[:space:]]* ]]; then
            in_watch=true
            continue
        fi
        if $in_watch && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*Monitoring:[[:space:]]* ]]; then
            echo "watch-pr-feedback"
            return
        fi
        if $in_watch && [[ "$line" =~ ^[A-Z][^:]*:[[:space:]]* ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
            in_watch=false
        fi
    done

    # 4. Blocked vs blocked-worker: Status is "blocked" but worker body
    #    sections override -> route to worker
    if [[ "$status_value" == "blocked" ]]; then
        local has_worker_section=false
        for line in "${_lines_ref[@]}"; do
            if [[ "$line" =~ ^(Changed|Validated|Need\ scope\ change|Issues):[[:space:]]* ]]; then
                has_worker_section=true
                break
            fi
        done
        if $has_worker_section; then
            echo "worker"
        else
            echo "blocked"
        fi
        return
    fi

    # 5. Worker: Status is complete/partial AND no Watch: AND no Feedback:
    if [[ "$status_value" == "complete" || "$status_value" == "partial" ]]; then
        local has_watch=false
        local has_feedback=false
        for line in "${_lines_ref[@]}"; do
            if [[ "$line" =~ ^Watch:[[:space:]]* ]]; then has_watch=true; fi
            if [[ "$line" =~ ^Feedback:[[:space:]]* ]]; then has_feedback=true; fi
        done
        if ! $has_watch && ! $has_feedback; then
            echo "worker"
            return
        fi
    fi

    # 6. Worker (statusless fallback): worker-exclusive section headers present
    #    but no Status: line
    if [[ "$status_value" == "" ]]; then
        local has_need_scope=false
        local has_changed=false
        local has_validated=false
        local has_issues=false
        for line in "${_lines_ref[@]}"; do
            if [[ "$line" =~ ^Need\ scope\ change:[[:space:]]* ]]; then has_need_scope=true; fi
            if [[ "$line" =~ ^Changed:[[:space:]]* ]]; then has_changed=true; fi
            if [[ "$line" =~ ^Validated:[[:space:]]* ]]; then has_validated=true; fi
            if [[ "$line" =~ ^Issues:[[:space:]]* ]]; then has_issues=true; fi
        done
        if $has_need_scope || { $has_changed && $has_validated && $has_issues; }; then
            echo "worker"
            return
        fi
    fi

    # 7. Planner: first non-blank line is exactly "Plan"
    for line in "${_lines_ref[@]}"; do
        if ! is_blank_line "$line"; then
            local trimmed
            trimmed=$(trim "$line")
            if [[ "$trimmed" == "Plan" ]]; then
                echo "planner"
                return
            fi
            break
        fi
    done

    echo "unknown"
}

# ── Line Classification ──────────────────────────────────────────────────

# INVARIANT: field_active is managed via a global variable FIELD_ACTIVE.

is_valid_line() {
    local line="$1"
    local labels_str="$2"

    # Blank line
    if is_blank_line "$line"; then
        return 0
    fi

    # Heading — resets active-field context
    if [[ "$line" =~ ^[[:space:]]*\#+[[:space:]] ]]; then
        FIELD_ACTIVE=false
        return 0
    fi

    # Labeled field: "SomeLabel: value" where label is a known prefix
    if [[ "$line" =~ ^([^:]+):[[:space:]]* ]]; then
        local label
        label=$(trim "${BASH_REMATCH[1]}")
        if labels_contain "$label" "$labels_str"; then
            FIELD_ACTIVE=true
            return 0
        fi
    fi

    # List item (with optional leading whitespace) — only valid under a field
    if [[ "$line" =~ ^[[:space:]]*(-|[0-9]+\.)[[:space:]] ]]; then
        if $FIELD_ACTIVE; then
            return 0
        fi
        return 1
    fi

    return 1
}

# ── Check for standalone prose lines ─────────────────────────────────────

check_standalone_prose() {
    local -n _prose_lines_ref=$1
    local labels_str="$2"
    local -n _prose_diag_ref=$3
    local plan_heading="${4:-}"

    FIELD_ACTIVE=false
    local i line line_num
    for ((i = 0; i < ${#_prose_lines_ref[@]}; i++)); do
        line="${_prose_lines_ref[$i]}"
        line_num=$((i + 1))

        # INVARIANT: "Plan" on the first non-blank line is the report heading, not prose.
        if [[ -n "$plan_heading" ]]; then
            local trimmed
            trimmed=$(trim "$line")
            if [[ "$trimmed" == "Plan" ]]; then
                FIELD_ACTIVE=false
                continue
            fi
        fi

        if is_valid_line "$line" "$labels_str"; then
            continue
        fi

        _prose_diag_ref+=("Line ${line_num}: standalone prose: $line")
    done
}

# ── Required List Sections ───────────────────────────────────────────────

check_required_list_sections() {
    local -n _rls_lines_ref=$1
    local -n _rls_sections_ref=$2
    local labels_str="$3"
    local -n _rls_diag_ref=$4

    local section section_idx has_list_item j next_label
    for section in "${_rls_sections_ref[@]}"; do
        section_idx=-1
        local escaped_section
        escaped_section=$(regex_escape "$section")
        for ((i = 0; i < ${#_rls_lines_ref[@]}; i++)); do
            if [[ "${_rls_lines_ref[$i]}" =~ ^${escaped_section}:[[:space:]]* ]]; then
                section_idx=$i
                break
            fi
        done
        if [[ $section_idx -eq -1 ]]; then
            _rls_diag_ref+=("Missing required section: $section")
            continue
        fi

        has_list_item=false
        for ((j = section_idx + 1; j < ${#_rls_lines_ref[@]}; j++)); do
            if [[ "${_rls_lines_ref[$j]}" =~ ^([^:]+):[[:space:]]* ]]; then
                next_label=$(trim "${BASH_REMATCH[1]}")
                if labels_contain "$next_label" "$labels_str"; then
                    break
                fi
            fi
            if [[ "${_rls_lines_ref[$j]}" =~ ^[[:space:]]*(-|[0-9]+\.)[[:space:]] ]]; then
                has_list_item=true
                break
            fi
        done
        if ! $has_list_item; then
            _rls_diag_ref+=("Required section '$section' must contain at least one list item")
        fi
    done
}

# ── Required Sub-fields ──────────────────────────────────────────────────

check_required_sub_fields() {
    local -n _rsf_lines_ref=$1
    local -n _rsf_map_ref=$2
    local -n _rsf_diag_ref=$3

    local entry parent required_subs parent_idx escaped_parent
    local sub_label sub_value found_subs j

    for entry in "${_rsf_map_ref[@]}"; do
        IFS='|' read -ra parts <<< "$entry"
        parent="${parts[0]}"
        required_subs=("${parts[@]:1}")

        escaped_parent=$(regex_escape "$parent")
        parent_idx=-1
        for ((i = 0; i < ${#_rsf_lines_ref[@]}; i++)); do
            if [[ "${_rsf_lines_ref[$i]}" =~ ^${escaped_parent}:[[:space:]]* ]]; then
                parent_idx=$i
                break
            fi
        done
        if [[ $parent_idx -eq -1 ]]; then
            _rsf_diag_ref+=("Missing required field group: $parent")
            continue
        fi

        found_subs=()
        for ((j = parent_idx + 1; j < ${#_rsf_lines_ref[@]}; j++)); do
            # Stop at the next top-level field (non-indented label)
            if [[ "${_rsf_lines_ref[$j]}" =~ ^[A-Za-z] ]] && [[ "${_rsf_lines_ref[$j]}" =~ ^([^:]+):[[:space:]]* ]]; then
                break
            fi
            if [[ "${_rsf_lines_ref[$j]}" =~ ^[[:space:]]*-[[:space:]]*([^:]+):[[:space:]]*(.*) ]]; then
                sub_label=$(trim "${BASH_REMATCH[1]}")
                sub_value=$(trim "${BASH_REMATCH[2]}")
                found_subs+=("$sub_label")
                if [[ -z "$sub_value" ]]; then
                    _rsf_diag_ref+=("Required sub-field '$sub_label' has no value")
                fi
            fi
        done

        local sub
        for sub in "${required_subs[@]}"; do
            if ! contains_value_ci "$sub" "${found_subs[@]+"${found_subs[@]}"}"; then
                _rsf_diag_ref+=("Missing required sub-field '$sub' under '$parent'")
            fi
        done
    done
}

# ── Planner Step Sub-field Validation ────────────────────────────────────

check_planner_step_sub_fields() {
    local -n _psf_lines_ref=$1
    local is_full_plan="$2"
    local labels_str="$3"
    local -n _psf_diag_ref=$4

    # Locate Steps: section
    local steps_idx=-1
    for ((i = 0; i < ${#_psf_lines_ref[@]}; i++)); do
        if [[ "${_psf_lines_ref[$i]}" =~ ^Steps:[[:space:]]* ]]; then
            steps_idx=$i
            break
        fi
    done
    if [[ $steps_idx -eq -1 ]]; then
        return
    fi

    # Find the end of the Steps section (next top-level labeled field at column 0)
    local steps_end_idx=${#_psf_lines_ref[@]}
    local candidate_label
    for ((j = steps_idx + 1; j < ${#_psf_lines_ref[@]}; j++)); do
        if [[ "${_psf_lines_ref[$j]}" =~ ^[A-Za-z] ]] && [[ "${_psf_lines_ref[$j]}" =~ ^([^:]+):[[:space:]]* ]]; then
            candidate_label=$(trim "${BASH_REMATCH[1]}")
            if labels_contain "$candidate_label" "$labels_str"; then
                steps_end_idx=$j
                break
            fi
        fi
    done

    # Collect step block start indices and labels
    local step_starts=()
    local step_labels=()
    for ((i = steps_idx + 1; i < steps_end_idx; i++)); do
        if [[ "${_psf_lines_ref[$i]}" =~ ^[[:space:]]*-[[:space:]]+S([0-9]+) ]]; then
            step_starts+=("$i")
            step_labels+=("S${BASH_REMATCH[1]}")
        elif [[ "${_psf_lines_ref[$i]}" =~ ^[[:space:]]*([0-9]+)\.[[:space:]] ]]; then
            step_starts+=("$i")
            step_labels+=("Step ${BASH_REMATCH[1]}")
        fi
    done

    if [[ ${#step_starts[@]} -eq 0 ]]; then
        return
    fi

    local required_sub_fields=("Owner" "Files" "Outcome")
    if $is_full_plan; then
        required_sub_fields=("Owner" "Files" "Outcome" "Depends on")
    fi

    local inline_sub_fields=("Owner" "Depends on")
    local list_sub_fields=("Files" "Outcome")

    local s block_start block_end step_label found_fields
    local k sub_label sub_value step_num has_list_item m required_field

    for ((s = 0; s < ${#step_starts[@]}; s++)); do
        block_start=${step_starts[$s]}
        if ((s < ${#step_starts[@]} - 1)); then
            block_end=${step_starts[$((s + 1))]}
        else
            block_end=$steps_end_idx
        fi
        step_label="${step_labels[$s]}"

        found_fields=()

        # Check the step header line for inline Owner
        if [[ "${_psf_lines_ref[$block_start]}" =~ Owner:[[:space:]]*[^[:space:]] ]]; then
            found_fields+=("Owner")
        elif [[ "${_psf_lines_ref[$block_start]}" =~ Owner:[[:space:]]*$ ]]; then
            found_fields+=("Owner")
            step_num=$(echo "$step_label" | sed 's/^S//;s/^Step *//')
            _psf_diag_ref+=("Step ${step_num}: required field 'Owner' has no value")
        fi

        # Scan continuation lines for sub-fields and validate values
        for ((k = block_start + 1; k < block_end; k++)); do
            if [[ "${_psf_lines_ref[$k]}" =~ ^[[:space:]]+([^:]+):[[:space:]]*(.*) ]]; then
                sub_label=$(trim "${BASH_REMATCH[1]}")
                sub_value=$(trim "${BASH_REMATCH[2]}")
                found_fields+=("$sub_label")

                if contains_value_ci "$sub_label" "${inline_sub_fields[@]}" && [[ -z "$sub_value" ]]; then
                    step_num=$(echo "$step_label" | sed 's/^S//;s/^Step *//')
                    _psf_diag_ref+=("Step ${step_num}: required field '$sub_label' has no value")
                elif contains_value_ci "$sub_label" "${list_sub_fields[@]}" && [[ -z "$sub_value" ]]; then
                    # List field with no inline value — check for list items
                    has_list_item=false
                    for ((m = k + 1; m < block_end; m++)); do
                        if [[ "${_psf_lines_ref[$m]}" =~ ^[[:space:]]+([^:]+):[[:space:]]* ]]; then
                            break
                        fi
                        if [[ "${_psf_lines_ref[$m]}" =~ ^[[:space:]]+[-][[:space:]]+[^[:space:]] ]] || \
                           [[ "${_psf_lines_ref[$m]}" =~ ^[[:space:]]+[0-9]+\.[[:space:]]+[^[:space:]] ]]; then
                            has_list_item=true
                            break
                        fi
                    done
                    if ! $has_list_item; then
                        step_num=$(echo "$step_label" | sed 's/^S//;s/^Step *//')
                        _psf_diag_ref+=("Step ${step_num}: required field '$sub_label' has no list items")
                    fi
                fi
            fi
        done

        for required_field in "${required_sub_fields[@]}"; do
            if ! contains_value_ci "$required_field" "${found_fields[@]+"${found_fields[@]}"}"; then
                _psf_diag_ref+=("$step_label missing required field: $required_field")
            fi
        done
    done
}

# ── Worker Report Validation (complete | partial) ────────────────────────

validate_worker_report() {
    local -n _wr_lines_ref=$1
    local -n _wr_diag_ref=$2
    local labels_str
    labels_str=$(build_worker_labels)

    # ── Check required sections ─────────────────────────────────────────
    local section found_section
    for section in "${WORKER_REQUIRED_SECTIONS[@]}"; do
        found_section=false
        for line in "${_wr_lines_ref[@]}"; do
            if [[ "$line" =~ ^([^:]+):[[:space:]]* ]]; then
                local label
                label=$(trim "${BASH_REMATCH[1]}")
                if [[ "$label" == "$section" ]]; then
                    found_section=true
                    break
                fi
            fi
        done
        if ! $found_section; then
            _wr_diag_ref+=("Missing required section: $section")
        fi
    done

    # ── Check required sections are non-empty ──────────────────────────
    local section_line_index start_idx has_list_item j next_label
    for section in "${WORKER_REQUIRED_SECTIONS[@]}"; do
        section_line_index=-1
        for ((i = 0; i < ${#_wr_lines_ref[@]}; i++)); do
            if [[ "${_wr_lines_ref[$i]}" =~ ^([^:]+):[[:space:]]* ]]; then
                local label
                label=$(trim "${BASH_REMATCH[1]}")
                if [[ "$label" == "$section" ]]; then
                    section_line_index=$i
                    break
                fi
            fi
        done
        if [[ $section_line_index -eq -1 ]]; then
            continue
        fi

        start_idx=$((section_line_index + 1))
        has_list_item=false
        for ((j = start_idx; j < ${#_wr_lines_ref[@]}; j++)); do
            if [[ "${_wr_lines_ref[$j]}" =~ ^([^:]+):[[:space:]]* ]]; then
                next_label=$(trim "${BASH_REMATCH[1]}")
                if labels_contain "$next_label" "$labels_str"; then
                    break
                fi
            fi
            if [[ "${_wr_lines_ref[$j]}" =~ ^[[:space:]]*-[[:space:]] ]]; then
                has_list_item=true
                break
            fi
        done
        if ! $has_list_item; then
            _wr_diag_ref+=("Required section '$section' must contain at least one list item (- entry or - None)")
        fi
    done

    # ── Check for standalone prose lines ────────────────────────────────
    check_standalone_prose _wr_lines_ref "$labels_str" _wr_diag_ref
}

# ── Blocked Report Validation ────────────────────────────────────────────

validate_blocked_report() {
    local -n _br_lines_ref=$1
    local -n _br_diag_ref=$2
    local labels_str
    labels_str=$(build_blocked_labels)

    # ── Check required fields ───────────────────────────────────────────
    local field found_field
    for field in "${BLOCKED_REQUIRED_FIELDS[@]}"; do
        found_field=false
        for line in "${_br_lines_ref[@]}"; do
            if [[ "$line" =~ ^([^:]+):[[:space:]]* ]]; then
                local label
                label=$(trim "${BASH_REMATCH[1]}")
                if [[ "$label" == "$field" ]]; then
                    found_field=true
                    break
                fi
            fi
        done
        if ! $found_field; then
            _br_diag_ref+=("Missing required blocked field: $field")
        fi
    done

    # ── Check blocked required fields have non-empty values ────────────
    local inline_fields=("Stage" "Blocker" "Retry status" "Fallback used" "Impact")
    local list_fields=("Next action")

    local i label value
    for ((i = 0; i < ${#_br_lines_ref[@]}; i++)); do
        if [[ "${_br_lines_ref[$i]}" =~ ^([^:]+):[[:space:]]*(.*) ]]; then
            label=$(trim "${BASH_REMATCH[1]}")
            value=$(trim "${BASH_REMATCH[2]}")

            if contains_value "$label" "${inline_fields[@]}"; then
                if [[ -z "$value" ]]; then
                    _br_diag_ref+=("Required blocked field '$label' has no value (must not be empty)")
                elif [[ "$label" == "Stage" ]]; then
                    if ! contains_value "$value" "${VALID_STAGE_VALUES[@]}"; then
                        _br_diag_ref+=("Invalid Stage value '$value' (must be one of: $(IFS=', '; echo "${VALID_STAGE_VALUES[*]}"))")
                    fi
                elif [[ "$label" == "Retry status" ]]; then
                    if ! contains_value "$value" "${VALID_RETRY_STATUS_VALUES[@]}"; then
                        _br_diag_ref+=("Invalid Retry status value '$value' (must be one of: $(IFS=', '; echo "${VALID_RETRY_STATUS_VALUES[*]}"))")
                    fi
                fi
            fi

            if contains_value "$label" "${list_fields[@]}"; then
                local has_list_item=false
                local all_placeholders=true
                local j bullet_value bullet_value_lower
                for ((j = i + 1; j < ${#_br_lines_ref[@]}; j++)); do
                    if [[ "${_br_lines_ref[$j]}" =~ ^[[:space:]]*-[[:space:]](.*) ]]; then
                        has_list_item=true
                        bullet_value=$(trim "${BASH_REMATCH[1]}")
                        bullet_value_lower=$(printf '%s' "$bullet_value" | tr '[:upper:]' '[:lower:]')
                        if [[ -n "$bullet_value" && "$bullet_value_lower" != "none" && "$bullet_value_lower" != "n/a" && "$bullet_value" != "-" ]]; then
                            all_placeholders=false
                        fi
                        continue
                    fi
                    if is_blank_line "${_br_lines_ref[$j]}"; then
                        continue
                    fi
                    break
                done
                if ! $has_list_item; then
                    _br_diag_ref+=("Required blocked field '$label' has no list items (must have at least one)")
                elif $all_placeholders; then
                    _br_diag_ref+=("Required blocked field '$label' must contain a concrete step (not a placeholder)")
                fi
            fi
        fi
    done

    # ── Check for standalone prose lines ────────────────────────────────
    check_standalone_prose _br_lines_ref "$labels_str" _br_diag_ref
}

# ── Planner Report Validation ────────────────────────────────────────────

validate_planner_report() {
    local -n _pr_lines_ref=$1
    local -n _pr_diag_ref=$2

    # Determine compact vs full by presence of Delivery: line
    local is_full_plan=false
    for line in "${_pr_lines_ref[@]}"; do
        if [[ "$line" =~ ^Delivery:[[:space:]]* ]]; then
            is_full_plan=true
            break
        fi
    done

    local labels_str
    labels_str=$(build_planner_labels "$is_full_plan")

    # Check required inline fields
    local field field_found
    for field in "${PLANNER_COMPACT_INLINE_FIELDS[@]}"; do
        field_found=false
        local escaped_field
        escaped_field=$(regex_escape "$field")
        for line in "${_pr_lines_ref[@]}"; do
            if [[ "$line" =~ ^${escaped_field}:[[:space:]]*.+ ]]; then
                field_found=true
                break
            fi
        done
        if ! $field_found; then
            _pr_diag_ref+=("Missing required field: $field")
        fi
    done

    # Check required list sections
    local required_list_sections=("${PLANNER_COMPACT_LIST_SECTIONS[@]}")
    if $is_full_plan; then
        required_list_sections+=("${PLANNER_FULL_EXTRA_LIST_SECTIONS[@]}")
    fi
    check_required_list_sections _pr_lines_ref required_list_sections "$labels_str" _pr_diag_ref

    # Check required sub-field groups
    check_required_sub_fields _pr_lines_ref PLANNER_COMPACT_SUB_FIELDS _pr_diag_ref
    if $is_full_plan; then
        check_required_sub_fields _pr_lines_ref PLANNER_FULL_EXTRA_SUB_FIELDS _pr_diag_ref
    fi

    # Check per-step required sub-fields within Steps section
    check_planner_step_sub_fields _pr_lines_ref "$is_full_plan" "$labels_str" _pr_diag_ref

    # ── Check for standalone prose lines ────────────────────────────────
    check_standalone_prose _pr_lines_ref "$labels_str" _pr_diag_ref "plan"
}

# ── PR Output Report Validation ─────────────────────────────────────────

validate_pr_output_report() {
    local -n _pro_lines_ref=$1
    local -n _pro_diag_ref=$2

    local labels_str
    labels_str=$(build_pr_output_labels)

    # Check required inline fields
    local field field_found
    for field in "${PR_OUTPUT_INLINE_FIELDS[@]}"; do
        field_found=false
        local escaped_field
        escaped_field=$(regex_escape "$field")
        for line in "${_pro_lines_ref[@]}"; do
            if [[ "$line" =~ ^${escaped_field}:[[:space:]]* ]]; then
                field_found=true
                break
            fi
        done
        if ! $field_found; then
            _pro_diag_ref+=("Missing required field: $field")
        fi
    done

    # Check Status value against open-plan-pr contract (complete | blocked)
    local valid_pr_status_values=("complete" "blocked")
    for line in "${_pro_lines_ref[@]}"; do
        if [[ "$line" =~ ^Status:[[:space:]]*(.+) ]]; then
            local pr_status_value
            pr_status_value=$(trim "${BASH_REMATCH[1]}")
            if ! contains_value "$pr_status_value" "${valid_pr_status_values[@]}"; then
                _pro_diag_ref+=("Invalid PR output Status value '$pr_status_value' (must be one of: $(IFS=', '; echo "${valid_pr_status_values[*]}"))")
            fi
            break
        fi
    done

    # Check required list sections
    check_required_list_sections _pro_lines_ref PR_OUTPUT_LIST_SECTIONS "$labels_str" _pro_diag_ref

    # Check for standalone prose
    check_standalone_prose _pro_lines_ref "$labels_str" _pro_diag_ref
}

# ── address-pr-feedback Report Validation ────────────────────────────────

validate_address_feedback_report() {
    local -n _afr_lines_ref=$1
    local -n _afr_diag_ref=$2

    local labels_str
    labels_str=$(build_address_feedback_labels)

    # Check Status present
    local has_status=false
    for line in "${_afr_lines_ref[@]}"; do
        if [[ "$line" =~ ^Status:[[:space:]]* ]]; then
            has_status=true
            break
        fi
    done
    if ! $has_status; then
        _afr_diag_ref+=("Missing required field: Status")
    fi

    # Check required sub-field groups
    check_required_sub_fields _afr_lines_ref ADDRESS_FEEDBACK_SUB_FIELDS _afr_diag_ref

    # Check required list sections
    check_required_list_sections _afr_lines_ref ADDRESS_FEEDBACK_LIST_SECTIONS "$labels_str" _afr_diag_ref

    # Check for standalone prose
    check_standalone_prose _afr_lines_ref "$labels_str" _afr_diag_ref
}

# ── watch-pr-feedback Report Validation ──────────────────────────────────

validate_watch_feedback_report() {
    local -n _wfr_lines_ref=$1
    local -n _wfr_diag_ref=$2

    local labels_str
    labels_str=$(build_watch_feedback_labels)

    # Check Status present
    local has_status=false
    for line in "${_wfr_lines_ref[@]}"; do
        if [[ "$line" =~ ^Status:[[:space:]]* ]]; then
            has_status=true
            break
        fi
    done
    if ! $has_status; then
        _wfr_diag_ref+=("Missing required field: Status")
    fi

    # Check required sub-field groups
    check_required_sub_fields _wfr_lines_ref WATCH_FEEDBACK_SUB_FIELDS _wfr_diag_ref

    # Check required list sections
    check_required_list_sections _wfr_lines_ref WATCH_FEEDBACK_LIST_SECTIONS "$labels_str" _wfr_diag_ref

    # Check for standalone prose
    check_standalone_prose _wfr_lines_ref "$labels_str" _wfr_diag_ref
}

# ── Main Validation Function ─────────────────────────────────────────────

validate_report() {
    local report_path="$1"
    local diagnostics=()

    if [[ ! -f "$report_path" ]]; then
        echo "File not found: $report_path"
        return 1
    fi

    # Read file into array
    local lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$report_path"

    # ── Check 1: Status line ────────────────────────────────────────────
    local status_value=""
    local i
    for ((i = 0; i < ${#lines[@]}; i++)); do
        if [[ "${lines[$i]}" =~ ^Status:[[:space:]]*(.+) ]]; then
            status_value=$(trim "${BASH_REMATCH[1]}")
            break
        fi
    done

    # ── Detect report type ──────────────────────────────────────────────
    local report_type
    report_type=$(detect_report_type lines "$status_value")

    # ── Route by detected type ──────────────────────────────────────────
    case "$report_type" in
        blocked)
            if [[ -z "$status_value" ]]; then
                diagnostics+=("Missing required Status: line")
                printf '%s\n' "${diagnostics[@]}"
                return 0
            fi
            if ! contains_value "$status_value" "${VALID_STATUS_VALUES[@]}"; then
                diagnostics+=("Invalid Status value '$status_value' (must be one of: $(IFS=', '; echo "${VALID_STATUS_VALUES[*]}"))")
                printf '%s\n' "${diagnostics[@]}"
                return 0
            fi
            validate_blocked_report lines diagnostics
            ;;
        worker)
            if [[ -z "$status_value" ]]; then
                diagnostics+=("Missing required Status: line")
                printf '%s\n' "${diagnostics[@]}"
                return 0
            fi
            if ! contains_value "$status_value" "${VALID_STATUS_VALUES[@]}"; then
                diagnostics+=("Invalid Status value '$status_value' (must be one of: $(IFS=', '; echo "${VALID_STATUS_VALUES[*]}"))")
                printf '%s\n' "${diagnostics[@]}"
                return 0
            fi
            validate_worker_report lines diagnostics
            ;;
        planner)
            validate_planner_report lines diagnostics
            ;;
        pr-output)
            validate_pr_output_report lines diagnostics
            ;;
        address-pr-feedback)
            if [[ -z "$status_value" ]]; then
                diagnostics+=("Missing required Status: line")
                printf '%s\n' "${diagnostics[@]}"
                return 0
            fi
            if ! contains_value "$status_value" "${VALID_STATUS_VALUES[@]}"; then
                diagnostics+=("Invalid Status value '$status_value' (must be one of: $(IFS=', '; echo "${VALID_STATUS_VALUES[*]}"))")
                printf '%s\n' "${diagnostics[@]}"
                return 0
            fi
            validate_address_feedback_report lines diagnostics
            ;;
        watch-pr-feedback)
            if [[ -z "$status_value" ]]; then
                diagnostics+=("Missing required Status: line")
                printf '%s\n' "${diagnostics[@]}"
                return 0
            fi
            if ! contains_value "$status_value" "${VALID_STATUS_VALUES[@]}"; then
                diagnostics+=("Invalid Status value '$status_value' (must be one of: $(IFS=', '; echo "${VALID_STATUS_VALUES[*]}"))")
                printf '%s\n' "${diagnostics[@]}"
                return 0
            fi
            validate_watch_feedback_report lines diagnostics
            ;;
        *)
            diagnostics+=("Unknown report type")
            ;;
    esac

    if [[ ${#diagnostics[@]} -gt 0 ]]; then
        printf '%s\n' "${diagnostics[@]}"
    fi
    return 0
}

# ── Entry Point ──────────────────────────────────────────────────────────

if [[ -n "$REPORT_FILE" ]]; then
    resolved_path="$REPORT_FILE"
    if [[ "$REPORT_FILE" != /* ]]; then
        resolved_path="$REPO_ROOT/$REPORT_FILE"
    fi

    results=$(validate_report "$resolved_path")
    if [[ -z "$results" ]]; then
        echo "[PASS] $REPORT_FILE"
        exit 0
    else
        echo "[FAIL] $REPORT_FILE"
        while IFS= read -r diag; do
            echo "  $diag"
        done <<< "$results"
        exit 1
    fi
else
    if [[ -n "$BATCH_DIR" ]]; then
        if [[ "$BATCH_DIR" == /* ]]; then
            fixture_dir="$BATCH_DIR"
        else
            fixture_dir="$REPO_ROOT/$BATCH_DIR"
        fi
    else
        fixture_dir="$REPO_ROOT/tests/reports"
    fi

    if [[ ! -d "$fixture_dir" ]]; then
        echo "Fixture directory not found: $fixture_dir"
        exit 1
    fi

    fixtures=()
    while IFS= read -r -d '' f; do
        fixtures+=("$f")
    done < <(find "$fixture_dir" -maxdepth 1 -name '*.txt' -type f -print0 | sort -z)

    if [[ ${#fixtures[@]} -eq 0 ]]; then
        echo "No .txt fixtures found in $fixture_dir"
        exit 1
    fi

    total_passed=0
    total_failed=0
    batch_failed=false

    for fixture in "${fixtures[@]}"; do
        fixture_name=$(basename "$fixture")
        rel_path="tests/reports/$fixture_name"

        if [[ "$fixture_name" =~ ^valid- ]]; then
            expect_valid=true
        else
            expect_valid=false
        fi

        results=$(validate_report "$fixture")
        if [[ -z "$results" ]]; then
            report_is_valid=true
        else
            report_is_valid=false
        fi

        if $expect_valid && $report_is_valid; then
            echo "[PASS] $rel_path"
            total_passed=$((total_passed + 1))
        elif $expect_valid && ! $report_is_valid; then
            echo "[FAIL] $rel_path (expected valid, got diagnostics)"
            while IFS= read -r diag; do
                echo "  $diag"
            done <<< "$results"
            total_failed=$((total_failed + 1))
            batch_failed=true
        elif ! $expect_valid && ! $report_is_valid; then
            echo "[PASS] $rel_path (correctly rejected)"
            while IFS= read -r diag; do
                echo "  $diag"
            done <<< "$results"
            total_passed=$((total_passed + 1))
        elif ! $expect_valid && $report_is_valid; then
            echo "[FAIL] $rel_path (expected invalid, but passed validation)"
            total_failed=$((total_failed + 1))
            batch_failed=true
        fi
    done

    echo ""
    echo "Results: $total_passed passed, $total_failed failed out of ${#fixtures[@]} fixtures"

    if $batch_failed; then
        exit 1
    fi
    exit 0
fi
