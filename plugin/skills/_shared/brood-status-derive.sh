# shellcheck shell=bash
#
# brood-status-derive.sh — PURE status-derivation + aggregation library for the brood-status
# collection loop (ADR-0020).
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute path
# derived from its OWN script_dir (`. "$plugin_root/skills/_shared/brood-status-derive.sh"`).
# It defines functions only; it runs no top-level statements and changes no caller state beyond
# defining the functions below. `bash -n` validates it as a sourced fragment.
#
# SINGLE RESPONSIBILITY: turn already-collected per-strain observables (tmux liveness, PR state,
# manifest status) into (a) the rendered Status string, (b) a coarse counting bucket, and
# (c) per-brood / global aggregate counts. EVERYTHING here is PURE arithmetic / string mapping:
# inputs in, string out. There is NO tmux/gh/git/file I/O in this file — the IMPURE probing lives
# in the thin entrypoint (`brood-status-collect.sh`). Keeping derivation pure makes it the primary
# determinism coverage in `tools/test_shared_libs.sh` without standing up tmux/gh/git.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file carries `set -u`
# ONLY and deliberately OMITS the rest of the P18 shell-safety floor — `set -e`, `set -o pipefail`,
# and any EXIT trap. A sourced file mutates the SOURCING shell's option state, so installing those
# here would corrupt every caller's shell; the floor is therefore the documented exception, not the
# full `set -euo pipefail`. `set -u` alone is safe to inherit (an unset variable is a programming
# error here, and every parameter below is read explicitly). Allowlisted under CHECK13 as a P18
# documented exception.

set -u

# ── hivemind_derive_strain_status ─────────────────────────────────────────────────
# hivemind_derive_strain_status <manifest_status> <session_alive:0|1> <pr_state> <pr_number> \
#                               <state_current> <run_status> [<facts_evidence:yes|no>]
#   -> prints the derived Status string to stdout.
#
# <facts_evidence> (OPTIONAL 7th argument) is the projector's field 11: `yes` when a gather-facts
# output file sits in the strain's ground-truth worktree (hivemind_detect_facts_evidence in
# ledger-project.sh), the started-evidence of a script-engine child, which writes no run ledger.
# Only the exact value `yes` counts; an ABSENT argument (every 6-argument call), an empty value or
# any other value means `no`, so every 6-argument call keeps its result.
#
# Ports the SKILL.md rule table EXACTLY. Priority (highest first):
#   1. manifest_status == failed (failed-precedence): a strain recorded failed in the manifest is
#      reported failed regardless of tmux liveness (spawn-brood deliberately leaves the session
#      alive on injection failure for debugging):
#        alive -> "failed (injection failed; session alive for debug)"
#        dead  -> "failed (session ended, no PR)"
#   2. otherwise the tmux x PR observable table:
#        | tmux  | PR     | started-evidence | Status                                    |
#        | alive | none   | yes              | running                                   |
#        | alive | open   | yes              | running (PR #N open)                       |
#        | alive | *      | NO               | starting (session alive, workflow not …)  |
#        | dead  | merged | -                | complete                                  |
#        | dead  | open   | -                | blocked (session ended, PR #N still open) |
#        | dead  | none   | -                | failed (session ended, no PR)             |
#
# <pr_state> is one of: open | merged | none | unknown. `unknown` means the gh probe failed (not
# authenticated / rate-limited). PRESERVE current behavior: an unknown PR is treated like `none`
# for liveness/status derivation (the PR CELL itself is shown as unknown by the renderer; the
# Status derives from tmux + best-known PR). Any unrecognized tmux/PR combination falls through to
# the dead+none "failed" terminal, the conservative default.
#
# <state_current> is the child ledger's `state.current` token as projected by
# brood-status-project.sh — a real workflow-state token, or the fixed sentinels MISSING (a ledger
# pointer exists but the child has not yet written started-evidence), MALFORMED (a present-but-
# rejected ledger), or NO_LEDGER_POINTER (the manifest carries no ledger pointer at all — a legacy
# no-run-block manifest — so started-evidence is STRUCTURALLY unavailable). <run_status> is the
# projected `run.status` token (informational; not part of the started-evidence gate below). These
# are tier-3 child-ledger evidence (informational, never overrides observable status — ADR-0007):
# they only DEMOTE an alive-but-unstarted child away from `running`, never promote to complete and
# never hide a dead session. The demotion applies ONLY when a ledger pointer EXISTS but shows no
# started-evidence (MISSING/MALFORMED/empty). NO_LEDGER_POINTER is the legacy no-pointer
# fall-through: the gate does NOT apply, and the strain derives its observable status (running /
# running (PR #N open)) — preserving ADR-0007's demote-only posture (we never withhold the
# observable `running` claim from a strain that structurally cannot supply ledger evidence).
#
# STARTED-EVIDENCE GATE: an alive session is NOT proof the child
# started its workflow — a pasted-but-never-submitted child has an alive tmux session and no run
# ledger. The ground-truth started signal is EITHER of two sources: RUN-LEDGER EVIDENCE (a
# present, non-MISSING/non-MALFORMED state.current, written by a state-machine child) OR FACTS
# EVIDENCE (<facts_evidence> == yes, a gather-facts output file written by a script-engine child).
# An alive session WITHOUT either source derives the DISTINCT,
# TRANSIENT (non-terminal), non-running, non-complete status below instead of a bare `running`.
# MALFORMED state.current is fail-closed (NOT started-evidence -> demote to starting, not running).
# The gate applies ONLY when a ledger pointer EXISTS but supplies no started-evidence (state.current
# empty/MISSING/MALFORMED). A legacy manifest with NO ledger pointer projects state.current as
# NO_LEDGER_POINTER, for which started-evidence is STRUCTURALLY unavailable: the gate does NOT apply
# (legacy no-pointer fall-through) and an alive session derives its observable status exactly as it
# did before the gate existed. NO_LEDGER_POINTER is DELIBERATELY excluded from the gate's sentinel
# set and is NOT a real workflow-state token — it never leaks into the rendered Status (the non-gated
# alive branch picks running vs running (PR #N open) from pr_for_derive, never from state_current).
hivemind_derive_strain_status() {
  local manifest_status="$1" session_alive="$2" pr_state="$3" pr_number="$4"
  local state_current="$5" run_status="$6" facts_evidence="${7:-no}"

  # 1. failed-precedence (manifest static field beats the alive-session inference).
  if [ "$manifest_status" = "failed" ]; then
    if [ "$session_alive" -eq 1 ]; then
      printf '%s' "failed (injection failed; session alive for debug)"
    else
      printf '%s' "failed (session ended, no PR)"
    fi
    return 0
  fi

  # 2. tmux x PR observable table. `unknown` PR collapses to `none` for derivation.
  local pr_for_derive="$pr_state"
  [ "$pr_for_derive" = "unknown" ] && pr_for_derive="none"

  if [ "$session_alive" -eq 1 ]; then
    # Started-evidence gate: a present, non-MISSING/non-MALFORMED state.current is ground-truth
    # proof the child wrote its run ledger and started its workflow; facts_evidence == yes is the
    # same proof for a script-engine child. Absent both, an alive session is demoted from `running`
    # to the transient `starting` status. The gate fires ONLY for a ledger pointer that EXISTS but
    # supplies no started-evidence (empty/MISSING/MALFORMED) and no facts evidence.
    # NO_LEDGER_POINTER (legacy no-pointer manifest) is INTENTIONALLY absent from this set:
    # started-evidence is structurally unavailable there, so the strain falls through to the
    # observable table below and derives running / running (PR #N open) — the legacy no-pointer
    # fall-through.
    if [ -z "$state_current" ] || [ "$state_current" = "MISSING" ] || [ "$state_current" = "MALFORMED" ]; then
      if [ "$facts_evidence" != "yes" ]; then
        printf '%s' "starting (session alive, workflow not yet started)"
        return 0
      fi
    fi
    case "$pr_for_derive" in
      open) printf 'running (PR #%s open)' "$pr_number" ;;
      *)    printf 'running' ;;
    esac
  else
    case "$pr_for_derive" in
      merged) printf 'complete' ;;
      open)   printf 'blocked (session ended, PR #%s still open)' "$pr_number" ;;
      *)      printf 'failed (session ended, no PR)' ;;
    esac
  fi
  return 0
}

# ── hivemind_classify_status_bucket ───────────────────────────────────────────────
# hivemind_classify_status_bucket <derived_status> -> prints one of:
#   complete | running | blocked_failed
#
# Maps the rendered Status string onto the coarse counting bucket the per-brood summary line uses
# ("N of M strains complete. X running. Y blocked/failed."). Classification is by the Status
# string's leading word, which the derivation above fixes to a small closed set:
#   complete                                          -> complete
#   running, running (PR #N open)                     -> running
#   starting (...), blocked (...), failed (...)       -> blocked_failed
# The `starting` status (alive session with no started-evidence) buckets OUT of
# running and is NOT counted complete: it falls into blocked_failed alongside blocked/failed so the
# three-bucket summary keeps summing to total with no strain dropped. (A `starting` strain has not
# made forward progress, so counting it against completion is the conservative, sum-preserving
# choice — distinct from `running`, which the started-evidence gate now reserves for genuinely
# started children.) Any unexpected string also falls to blocked_failed (conservative — a strain
# we cannot classify as running or complete is counted against completion, never silently dropped).
hivemind_classify_status_bucket() {
  local status="$1"
  case "$status" in
    complete)   printf 'complete' ;;
    running|running\ *) printf 'running' ;;
    *)          printf 'blocked_failed' ;;
  esac
  return 0
}

# ── hivemind_aggregate_brood_summary ──────────────────────────────────────────────
# hivemind_aggregate_brood_summary <bucket-list...>
#   -> prints "complete running blocked_failed total" (4 space-separated integers) for ONE brood.
#
# Each argument is one strain's bucket (the output of hivemind_classify_status_bucket). Pure
# arithmetic; zero arguments yields "0 0 0 0" (an empty brood contributes nothing). An unrecognized
# bucket token is counted into blocked_failed (never dropped from total), matching the conservative
# classifier default.
hivemind_aggregate_brood_summary() {
  local complete=0 running=0 blocked_failed=0 total=0 bucket
  for bucket in "$@"; do
    total=$((total + 1))
    case "$bucket" in
      complete)       complete=$((complete + 1)) ;;
      running)        running=$((running + 1)) ;;
      *)              blocked_failed=$((blocked_failed + 1)) ;;
    esac
  done
  printf '%d %d %d %d' "$complete" "$running" "$blocked_failed" "$total"
  return 0
}

# ── hivemind_aggregate_global ─────────────────────────────────────────────────────
# hivemind_aggregate_global <brood-record...>
#   -> prints "total_broods unreadable complete total_strains" (4 space-separated integers).
#
# Each argument is ONE brood's record, a colon-delimited triple:
#   "<is_unreadable:0|1>:<complete_count>:<strain_total>"
# where:
#   is_unreadable  — 1 if the brood is an unreadable/blocker entry (no strain table), else 0.
#   complete_count — the brood's `complete` bucket count (0 for unreadable/empty broods).
#   strain_total   — the brood's strain count (0 for unreadable/empty broods).
#
# The global line is "Broods: T total. U unreadable. N of M strains complete across all broods."
#   total_broods = number of records (every discovered brood counts, terminal or not).
#   unreadable   = count of records with is_unreadable == 1.
#   complete     = sum of complete_count across all records.
#   total_strains= sum of strain_total across all records.
# Pure arithmetic; zero arguments yields "0 0 0 0" (no broods found).
hivemind_aggregate_global() {
  local total_broods=0 unreadable=0 complete=0 total_strains=0 record
  local is_unreadable rec_complete rec_total
  for record in "$@"; do
    total_broods=$((total_broods + 1))
    is_unreadable="${record%%:*}"
    rec_complete="${record#*:}"; rec_complete="${rec_complete%%:*}"
    rec_total="${record##*:}"
    [ "$is_unreadable" = "1" ] && unreadable=$((unreadable + 1))
    complete=$((complete + rec_complete))
    total_strains=$((total_strains + rec_total))
  done
  printf '%d %d %d %d' "$total_broods" "$unreadable" "$complete" "$total_strains"
  return 0
}
