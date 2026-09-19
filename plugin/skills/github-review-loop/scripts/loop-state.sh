#!/usr/bin/env bash
#
# loop-state.sh
#
# 1. PURPOSE
# ----------
# Single source of truth for the github-review-loop's OWN deterministic loop
# bookkeeping. Before this script, the cycle-increment / cycle-ceiling /
# terminal-vs-cycle / same-finding-repeat / guard-token-mapping decisions lived
# only as prose scattered through SKILL.md sections 4/5/6 + the Termination guard
# set. This script encodes ONLY those deterministic mechanics so the skill body
# can describe intent without re-deriving the arithmetic in prose.
#
# This is NOT a generic state machine. It is watch-loop-scoped bookkeeping for the
# github-review-loop alone. It does NOT read, classify, or interpret feedback
# content (that is the reviewer's job) and it does NOT encode the cross-consumer
# precedence ladder (that is exit-precedence.sh — see subcommand `cycle-decision`'s
# multi-token delegation below).
#
# 2. INPUT CONTRACT
# -----------------
# Subcommand dispatch on $1. Each subcommand takes a fixed positional arg list.
# Every argv is consumed as exactly ONE field — no word-splitting, no glob
# expansion (guards against the malformed-argv class fixed in exit-precedence.sh).
#
#   loop-state.sh cycle-decision <current_count> <max_cycles> <findings_resolved> <reviewer_exit_reason>
#     current_count        non-negative integer — remediation cycles completed SO FAR.
#                          PASSED IN by the caller; never persisted by this script.
#                          GitHub is the only ledger (no persisted loop ledger).
#     max_cycles           integer >= the max_remediation_cycles FLOOR THIS script
#                          declares (see `floor` below) — the cycle ceiling the caller
#                          runs with. A lower value is REJECTED, not clamped.
#     findings_resolved    non-negative integer — findings the reviewer resolved THIS return.
#     reviewer_exit_reason one reviewer fix-mode exit_reason token (see token set below),
#                          the literal `same-finding-repeat` for the oscillation guard,
#                          or the literal `approval-clean` for the approval
#                          confirmation pass where the reviewer found nothing
#                          actionable. The CODEX_APPROVED marker raised by the
#                          sibling pr-change-detect-poll.sh routes here.
#
#   loop-state.sh token-map <signal>
#     signal one deterministic loop-input signal the loop itself observes:
#       STATE=MERGED   -> pr-merged
#       STATE=CLOSED   -> pr-closed
#       WATCH_TIMEOUT  -> watch-window-elapsed
#       POLL_ERROR     -> blocked
#
#   loop-state.sh floor
#     ZERO args (a surplus arg is rejected loudly). Prints the declared
#     max_remediation_cycles floor as a BARE integer so prose and callers CITE the
#     number from here instead of restating it.
#     Deliberately UNLIKE every sibling subcommand's `KEY=VALUE` routing data:
#     `floor` is a VALUE-PUBLISHING command, not a routing emitter. Its whole job is
#     to be substituted where the literal used to sit, so
#     `$(loop-state.sh floor)` drops straight into cycle-decision's <max_cycles>
#     argv and into the SKILL.md Inputs-table default. A `KEY=VALUE` form would make
#     every citing site restate a strip expression — trading one duplicated number
#     for one duplicated parse — and a caller following the documented default
#     verbatim would feed `require_uint` a labelled string and die before the watch
#     could arm. Nothing machine-ROUTES on `floor`; callers only substitute it.
#
#   loop-state.sh resolve-precedence <token> [token ...]
#     When the caller holds MORE THAN ONE fired exit_reason at once (e.g. a reviewer
#     terminal AND a poll guard token from token-map in the same wake), forward them
#     to the sibling exit-precedence.sh, which is the single source of truth for the
#     14-rank ladder. This script does NOT re-encode that ladder (reuse / P9); it
#     only delegates. The tokens pass through UNMODIFIED (one argv = one token).
#
# Any unknown subcommand, wrong arg count, non-integer numeric field, or unknown
# token / signal → stderr diagnostic + exit 1 (REJECT LOUDLY). Silent fallthrough
# would mask a caller bug where a new signal/token was introduced without updating
# this script.
#
# 3. OUTPUT
# ---------
# cycle-decision → two lines on stdout, exit 0:
#     NEXT_COUNT=<int>      the cycle count AFTER this return (caller carries it
#                           forward; the script does not persist it).
#     EXIT_REASON=<token>   the terminal exit_reason if the loop must stop now, or
#                           the literal `none` if the loop should keep watching.
# token-map → one line on stdout, exit 0:
#     EXIT_REASON=<token>
# floor → one line on stdout, exit 0, carrying a BARE integer and NO `KEY=` label:
#     <int>
#
# 4. ENCODED DECISIONS (SKILL.md sections 4/5/6 + Termination guard set)
# ---------------------------------------------------------------------
#   (a) cycle-increment: increment IFF findings_resolved >= 1 (section 6). This
#       is UNCONDITIONAL on the exit_reason — a real remediation round
#       (findings_resolved >= 1) is counted whether the reviewer then kept the
#       loop going (`clean`) OR hard-stopped on an escalation terminal. A mixed
#       fix+escalate pass (e.g. simple items fixed, then `planner-escalation`)
#       is a completed round and MUST be counted, or `Cycles` under-reports and
#       the loop's cost accounting is lost.
#   (b) cycle-ceiling: when the resulting count reaches max_cycles, emit
#       `max-cycles-reached` (section 6). On an escalation terminal the terminal
#       exit_reason itself still wins — the increment is for accounting only and
#       does NOT convert the terminal into `max-cycles-reached`.
#   (c) terminal-vs-cycle: `root-cluster-suspected` and `merge-advised` are
#       TERMINALS that are NOT remediation cycles — never increment on them
#       (section 5), even when findings_resolved >= 1. The OTHER reviewer
#       escalation terminals (planner-escalation, blocked, injection-suspect,
#       high-severity-rejection, user-input-required) hard-stop too, but DO
#       increment when findings_resolved >= 1 per (a): they can carry a completed
#       remediation round (the reviewer fixed simple items, then escalated the
#       complex remainder).
#   (d) same-finding-repeat: oscillation guard maps to `max-cycles-reached`
#       (Termination guard set), no increment. This is an OSCILLATION guard, not
#       a quiet window — it stays `max-cycles-reached` and must NOT be folded
#       into the WATCH_TIMEOUT / `watch-window-elapsed` mapping below.
#   (g) WATCH_TIMEOUT (token-map): the per-cycle idle window elapsed with no new
#       review activity — a QUIET PR, not an exhausted cycle budget. It maps to
#       `watch-window-elapsed`, distinct from the (b)/(d) `max-cycles-reached`
#       cases, so the caller can tell "nothing more arrived" apart from "the
#       cycle ceiling was hit".
#   (e) `clean`: the keep-watching case — increment per (a)/(b), emit `none`
#       unless the ceiling is hit.
#   (f) `approval-clean`: an approval confirmation pass found nothing
#       actionable — TERMINAL `clean` (SKILL.md section 4 approval path). The
#       CODEX_APPROVED marker raised by the sibling pr-change-detect-poll.sh
#       feeds this token; this script sees only `approval-clean`.
#       Distinct from `clean`: a plain `clean` keeps watching, but an approved PR
#       with nothing actionable remaining is a successful terminal and must emit
#       `EXIT_REASON=clean` rather than keep watching to timeout. No increment
#       (a confirmation pass that finds nothing is not a remediation round,
#       section 6).
#   (h) max_remediation_cycles FLOOR: the ceiling a caller may run with has a
#       DECLARED minimum, owned by this script (MAX_REMEDIATION_CYCLES_FLOOR) and
#       enforced in cycle-decision. A caller passing a lower ceiling is REJECTED
#       loudly rather than silently terminating remediation early; 0 still rejects,
#       so the former `>= 1` check is subsumed, not lost. The `floor` subcommand
#       publishes the value as a bare integer so no consumer has to restate it and
#       none has to parse it: what `floor` prints IS what cycle-decision accepts as
#       <max_cycles>.
#
# 5. PRECEDENCE DELEGATION
# ------------------------
# cycle-decision and token-map each yield at most one candidate exit_reason. When
# more than one fired exit_reason is held simultaneously (e.g. a reviewer terminal
# AND a poll guard token in the same wake), the `resolve-precedence` subcommand
# DELEGATES ordering to the sibling exit-precedence.sh — this script does NOT
# re-encode the 14-rank ladder (reuse constraint / P9). The sibling is resolved
# relative to ${SCRIPT_DIR}:
#   ${SCRIPT_DIR}/exit-precedence.sh
#
# 6. INVARIANTS
# -------------
# INVARIANT: pure function — no /tmp, no stop-file, no persisted state, no network,
# no gh, no git, no Monitor; side effects are stdout/stderr + exit code only.
# INVARIANT: the cycle counter is an INPUT, never persisted here — GitHub is the
# only ledger; there is NO persisted loop ledger.
# INVARIANT: unknown subcommand / token / signal / malformed numeric → exit 1 +
# stderr; never silently ignored.
# INVARIANT: this script is the SOLE source of the max_remediation_cycles floor —
# it both DECLARES the number (MAX_REMEDIATION_CYCLES_FLOOR) and ENFORCES it in
# cycle-decision. No prose anywhere restates the number; consumers cite it, and
# `loop-state.sh floor` is how they read it.
# INVARIANT: `floor` stdout is DIRECTLY acceptable as cycle-decision's <max_cycles>
# argv — a documented default of `$(loop-state.sh floor)` composes with no strip or
# reformat step. Adding a `KEY=` label here breaks that composition.

set -euo pipefail

# INVARIANT: this line is the SINGLE SOURCE of the max_remediation_cycles floor.
# Prose cites `loop-state.sh floor` (or this line) — it never restates the number.
MAX_REMEDIATION_CYCLES_FLOOR=6

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

die() {
  printf 'loop-state: %s\n' "$1" >&2
  exit 1
}

# INVARIANT: a field must be a non-negative integer (no sign, no whitespace, no
# glob). Reject anything else loudly rather than letting bash arithmetic coerce it.
require_uint() {
  local name="$1" value="$2"
  case "$value" in
    ''|*[!0-9]*) die "$name must be a non-negative integer: '$value'" ;;
  esac
}

# Reviewer fix-mode TERMINAL tokens that hard-stop the loop. Split by cycle-count
# semantics (encoded decision 4c):
#
#   is_terminal_no_increment — root-cluster-suspected and merge-advised are
#   propagated reviewer terminals that are NOT remediation cycles; never count
#   them, even when findings_resolved >= 1.
#
#   is_terminal_increment_on_resolved — the reviewer escalations hard-stop too,
#   but can carry a completed remediation round (simple items fixed, complex
#   remainder escalated), so they DO increment when findings_resolved >= 1.
is_terminal_no_increment() {
  case "$1" in
    root-cluster-suspected|merge-advised) return 0 ;;
    *) return 1 ;;
  esac
}

is_terminal_increment_on_resolved() {
  case "$1" in
    planner-escalation|blocked|injection-suspect|\
high-severity-rejection|user-input-required) return 0 ;;
    *) return 1 ;;
  esac
}

cmd_cycle_decision() {
  [ "$#" -eq 4 ] || die "cycle-decision expects 4 args: <current_count> <max_cycles> <findings_resolved> <reviewer_exit_reason>"
  local current_count="$1" max_cycles="$2" findings_resolved="$3" reviewer_exit_reason="$4"

  require_uint "current_count" "$current_count"
  require_uint "max_cycles" "$max_cycles"
  require_uint "findings_resolved" "$findings_resolved"
  # cycle-ceiling floor guard (decision 4h): max_cycles must be at least the floor
  # THIS script declares. This SUBSUMES the former `>= 1` check — 0 still rejects.
  [ "$max_cycles" -ge "$MAX_REMEDIATION_CYCLES_FLOOR" ] || die "max_cycles must be >= the declared max_remediation_cycles floor of $MAX_REMEDIATION_CYCLES_FLOOR: '$max_cycles'"

  # same-finding-repeat oscillation guard → max-cycles-reached, no increment.
  if [ "$reviewer_exit_reason" = "same-finding-repeat" ]; then
    printf 'NEXT_COUNT=%s\n' "$current_count"
    printf 'EXIT_REASON=max-cycles-reached\n'
    return 0
  fi

  # approval-clean: an approval confirmation pass (CODEX_APPROVED) found nothing
  # actionable → TERMINAL `clean` (decision 4f). No increment — a confirmation
  # pass that finds nothing is not a remediation round. Distinct from plain
  # `clean`, which keeps watching; this is the successful approval terminal an
  # approved PR must emit rather than keep watching until timeout.
  if [ "$reviewer_exit_reason" = "approval-clean" ]; then
    printf 'NEXT_COUNT=%s\n' "$current_count"
    printf 'EXIT_REASON=clean\n'
    return 0
  fi

  # root-cluster-suspected / merge-advised: TERMINALS that are NOT remediation
  # cycles — hard-stop WITHOUT incrementing, even when findings_resolved >= 1.
  if is_terminal_no_increment "$reviewer_exit_reason"; then
    printf 'NEXT_COUNT=%s\n' "$current_count"
    printf 'EXIT_REASON=%s\n' "$reviewer_exit_reason"
    return 0
  fi

  # Reviewer escalation terminals hard-stop, but DO count a completed remediation
  # round: increment IFF findings_resolved >= 1 (decision 4a/4c). The terminal
  # exit_reason still wins — the increment is accounting only and does NOT convert
  # the terminal into max-cycles-reached.
  if is_terminal_increment_on_resolved "$reviewer_exit_reason"; then
    local esc_count="$current_count"
    if [ "$findings_resolved" -ge 1 ]; then
      esc_count=$((current_count + 1))
    fi
    printf 'NEXT_COUNT=%s\n' "$esc_count"
    printf 'EXIT_REASON=%s\n' "$reviewer_exit_reason"
    return 0
  fi

  # Only `clean` remains as a valid keep-watching return. Any other token is a
  # caller bug (unknown reviewer exit_reason reached the loop bookkeeper).
  [ "$reviewer_exit_reason" = "clean" ] || die "unknown reviewer_exit_reason: '$reviewer_exit_reason'"

  # cycle-increment: increment IFF the reviewer resolved >= 1 finding.
  local next_count="$current_count"
  if [ "$findings_resolved" -ge 1 ]; then
    next_count=$((current_count + 1))
  fi

  # cycle-ceiling: reaching max_cycles is terminal max-cycles-reached.
  if [ "$next_count" -ge "$max_cycles" ]; then
    printf 'NEXT_COUNT=%s\n' "$next_count"
    printf 'EXIT_REASON=max-cycles-reached\n'
    return 0
  fi

  printf 'NEXT_COUNT=%s\n' "$next_count"
  printf 'EXIT_REASON=none\n'
}

cmd_token_map() {
  [ "$#" -eq 1 ] || die "token-map expects 1 arg: <signal>"
  local signal="$1"
  case "$signal" in
    STATE=MERGED)  printf 'EXIT_REASON=pr-merged\n' ;;
    STATE=CLOSED)  printf 'EXIT_REASON=pr-closed\n' ;;
    WATCH_TIMEOUT) printf 'EXIT_REASON=watch-window-elapsed\n' ;;
    POLL_ERROR)    printf 'EXIT_REASON=blocked\n' ;;
    *) die "unknown loop signal: '$signal'" ;;
  esac
}

cmd_floor() {
  [ "$#" -eq 0 ] || die "floor expects 0 args"
  # BARE integer, no `KEY=` label: this value is SUBSTITUTED into cycle-decision's
  # <max_cycles> argv (and into the documented default), never routed by key.
  printf '%s\n' "$MAX_REMEDIATION_CYCLES_FLOOR"
}

cmd_resolve_precedence() {
  [ "$#" -ge 1 ] || die "resolve-precedence expects >= 1 token arg"
  local sibling="$SCRIPT_DIR/exit-precedence.sh"
  [ -f "$sibling" ] || die "sibling precedence kernel missing: $sibling"
  # Forward each token UNMODIFIED (one argv = one token). exit-precedence.sh owns
  # validation, the 14-rank ladder, and loud rejection of unknown tokens.
  bash "$sibling" "$@"
}

[ "$#" -ge 1 ] || die "usage: loop-state.sh <cycle-decision|token-map|floor|resolve-precedence> ..."
subcommand="$1"
shift

case "$subcommand" in
  cycle-decision)     cmd_cycle_decision "$@" ;;
  token-map)          cmd_token_map "$@" ;;
  floor)              cmd_floor "$@" ;;
  resolve-precedence) cmd_resolve_precedence "$@" ;;
  *) die "unknown subcommand: '$subcommand' (expected cycle-decision | token-map | floor | resolve-precedence)" ;;
esac

exit 0
