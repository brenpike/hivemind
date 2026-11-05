---
name: github-review-loop
description: Watches an open PR and remediates review feedback to a terminal state. Overlord in main session only. Use to watch a PR.
allowed-tools:
  - Read(~/.claude/plugins/cache/brenpike/hivemind/**)
  - Monitor
  - Agent(hivemind:github-reviewer)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/preflight.sh" *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/pr-change-detect-poll.sh" *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/prefilter.sh" *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/exit-precedence.sh" *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh" *)
  - Bash(date +%s)
shell: bash
---

# GitHub Review Loop

Watch one open PR and drive remediation to a terminal state. Classifying feedback is `hivemind:github-reviewer` fix-mode work, never this skill's. The loop runs in the main session: a subagent dispatch orphans any Monitor armed inside it, and only the top-level orchestrator can spawn the reviewer (ADR-0005).

Load and follow: `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` whole, `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` whole, `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` whole.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `pr` | (required) | PR number or URL. |
| `working_branch` | (required) | Branch the reviewer pushes fixes to. |
| `base` | (required) | PR base/target branch. |
| `reviewer_filter` | `automated` | Actionable reviewer identities (`automated` \| `codex-only` \| `all` \| `<author>`). |
| `max_watch_duration` | `3600` | Idle-window seconds per Monitor arm (1h). |
| `max_remediation_cycles` | `$(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh" floor)` | Max real remediation rounds (findings_resolved ≥ 1). |
| `poll_interval` | `60` | Seconds between polls. |
| `user_answer` | (none) | Optional `{candidate_url, question, reply}`: the user's answer to a question the reviewer asked, per `${CLAUDE_PLUGIN_ROOT}/agents/github-reviewer.md` (Fix Mode Input). |

`max_watch_duration` is an idle window, not a total budget: a completed remediation
cycle re-arms a fresh full window, and a window that elapses with no actionable
arrival ends the watch. The poll's deadline is per process, so a fresh arm is a
fresh window.

**Window deadline.** The remaining idle budget of the current window comes only from
the window deadline: epoch seconds recorded when an arm opens a window, held until
the next arm opens one. Exactly two arms open a window: the first arm after cycle 0
(step 4) and a productive re-arm (step 6). Each passes the full `max_watch_duration`
and records `$(date +%s)` plus that value as the deadline. The other two arms
continue the current window: an expired-arm re-arm (step 4) and the re-arm after a
non-productive return when no poll is running (step 6). Each passes
`max(0, deadline - $(date +%s))` as its `max_watch_duration` argument, never the full
value, and leaves the deadline unchanged.

`max_remediation_cycles` is a floor declared and enforced by
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh`, and no
literal is restated here. Its `floor` subcommand prints the value as a bare integer
with no `KEY=` label, usable as is in any argv expecting it, `cycle-decision`'s
`<max_cycles>` included. A caller that invokes this loop with a lower value is
rejected.

## Lifecycle

**1. Preflight.** Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/preflight.sh"`
with `pr`, `working_branch`, `base` as positional args. Any `PREFLIGHT_ERROR=`
line or non-zero exit → terminal `blocked`. Confirm git state is not unsafe per
`${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State).

**2. Capture baseline.** Before cycle 0 dispatches anything, capture the poll's
baseline seed:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/pr-change-detect-poll.sh" --snapshot initial <OWNER> <REPO> <PR_NUMBER> <max_watch_duration> <poll_interval> <reviewer_filter> <SELF_LOGIN>
```

`--snapshot` first, then the arm kind (`initial` here; see Arm kind), then the same 7
positional args the Monitor arm uses, all required and validated, so pass the
concrete values the arm will use. stdout is exactly one `BASELINE=<seed>` line; keep
the bare token (`sed -n 's/^BASELINE=//p' | head -1`). A `SNAPSHOT_ERROR` line or
non-zero exit → retry once; a second failure is terminal `blocked`. Never arm the
Monitor with an empty or absent seed.

**3. Cycle 0.** Before arming the Monitor, dispatch `hivemind:github-reviewer` fix
mode (Dispatch contract) over pre-existing PR feedback, never prefiltered. Pass
`user_answer`, when given, to this dispatch only. Handle the return per step 6 and
pass it through `loop-state.sh cycle-decision`: arm the Monitor only on
`EXIT_REASON=none`. Any other `EXIT_REASON` is terminal: emit the terminal report and
end the loop without arming the Monitor. "End the loop" ends this skill's own
procedure only (Terminal report).

**4. Arm Monitor.** Arm a Monitor in the main session on:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/pr-change-detect-poll.sh" <OWNER> <REPO> <PR_NUMBER> <max_watch_duration> <poll_interval> <reviewer_filter> <SELF_LOGIN> "<BASELINE_SEED>"
```

Pass the resolved preflight values and skill inputs as positional args in that order,
with the step-2 seed as arg 8. Quote the seed: it contains `|`, and unquoted it
becomes a shell pipeline and breaks the arm. Pass it verbatim: never lowercase, trim
or re-wrap it. The poll emits only on a real delta or terminal state. Read its lines
directly, never into a functional pipe. The first poll may fire `CHANGED` off cycle
0's own `Fixed in <SHA>` replies, because the seed predates them; `prefilter.sh`
absorbs that as `PREFILTER_SKIP`. Over-reporting is safe and under-reporting loses
findings, so add no duplicate-suppression.

An arm that returns without printing a marker that ends the poll (a terminal marker
or `REVIEWER_APPROVED`, step 5) expired; the watch has not ended. Re-arm for the
remaining idle budget of the current window (Window deadline), reusing the same seed
the expired arm carried (Seed-Advance invariant).

**Arm kind.** Every seed is stamped `initial` or `re-arm` at capture, inside the
token, so carrying a seed forward carries its kind. The kind decides whether an
in-scope reviewer approval that predates the arm surfaces: `initial` (step 2) yes,
so it fires `REVIEWER_APPROVED` on the first poll; `re-arm` (step 5) no, because the
reviewer pass about to run consumes that state, so a stale approval predating the
pass must never re-fire. The two capture sites of the Seed-Advance invariant map
one-to-one onto the two kinds.

**Seed-Advance invariant.** The baseline seed advances only where a reviewer pass is
about to consume the state it snapshots. There are exactly two capture sites: step
2, before cycle 0, and step 5, before a dispatch. There is no third. The QUIET-EXIT
CHECK (step 6) is not a capture site: `--check` reads a pending seed, prints no seed,
and leaves the baseline where it was. An arm boundary (step 4) and a post-dispatch
re-arm (step 6) are not capture sites: each must reuse the seed it already carries,
and a fresh `--snapshot` at either is forbidden. The resulting duplicate wakes, and
re-fires on our own `Fixed in <SHA>` replies, are absorbed by `prefilter.sh` as
`PREFILTER_SKIP`. Assume no specific figure for the Monitor's own per-arm ceiling.

**5. Per event.** `CHANGED` → run
`bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/prefilter.sh" <OWNER> <REPO> <PR_NUMBER> <reviewer_filter> <SELF_LOGIN>`:
`PREFILTER_SKIP` → keep Monitor armed, no dispatch, no cycle/`Routed` increment.
`PREFILTER_DISPATCH` or `PREFILTER_ERROR=<reason>` → dispatch reviewer fix mode (no
`target`); `PREFILTER_ERROR` is fail-open. Handle the return per step 6.
`REVIEWER_APPROVED` → confirmation pass (no `target`); use only the latest poll's
approval: a stale prior approval must never short-circuit later pushback.
If the reviewer finds nothing actionable, the loop ends `clean` only after the QUIET-EXIT CHECK (step 6) reports nothing new since the pending seed.
The pending seed's `re-arm` kind keeps an approval present at the pre-dispatch
capture from firing again in that check or on the re-armed poll. Only after that check, map
the terminal via `loop-state.sh cycle-decision <current_count> <max_cycles> 0 approval-clean`
(`approval-clean` emits `EXIT_REASON=clean`). If actionable items remain, the reviewer
processes them and returns a normal fix-mode exit_reason, handled per step 6. The
poll exits right after printing `REVIEWER_APPROVED`, so no poll runs during the
confirmation pass: skip every stop-Monitor instruction for that pass's return and
handle it per step 6's no-poll-running rules. `STATE=MERGED` → `pr-merged`.
`STATE=CLOSED` → `pr-closed`. `WATCH_TIMEOUT` → `watch-window-elapsed`, except a
timeout from an arm a productive return supersedes, which step 6 discards.
`POLL_ERROR` → stop Monitor; `blocked`. For the last four, use
`bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh" token-map <signal>`.

Pre-dispatch seed. Before spawning the reviewer for any dispatch in this step, the
`PREFILTER_DISPATCH` / `PREFILTER_ERROR` fix pass and the `REVIEWER_APPROVED`
confirmation pass alike, capture a pending seed per step 2's `--snapshot` procedure
with `re-arm` as the arm kind, and hold it. This is capture site 2 of the Seed-Advance
invariant. For a dispatch made while a poll is running, the Monitor stays armed
meanwhile. When no poll is running (the confirmation pass, or a dispatch the
QUIET-EXIT CHECK routed), the pass's activity is caught only afterwards, by diffing this
pending seed in the next arm's first poll or in the QUIET-EXIT CHECK. A
`SNAPSHOT_ERROR` or non-zero exit: retry once, then terminal `blocked`.
`PREFILTER_SKIP` does not dispatch and captures no pending seed.

**6. Reviewer-return handling.** `clean` → keep watching. `planner-escalation` |
`blocked` | `injection-suspect` | `high-severity-rejection` | `user-input-required`
→ hard stop; one terminal with the matching `exit_reason` and the
escalation-conditional fields. `root-cluster-suspected` → hard stop; one terminal
with the reviewer's cluster payload; the caller routes it to cerebrate zoom-out, and
the loop only propagates it. `merge-advised` → hard stop; one `merge-advised` terminal
with `advisory_reason` + `structural_home` + `recommendation_text`; advisory only, and
the loop never merges. Pass every reviewer return, the escalation terminals included,
through
`bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh" cycle-decision <current_count> <max_cycles> <findings_resolved> <exit_reason>`
for cycle increments, ceiling, `same-finding-repeat`, and terminal-vs-cycle. It counts
a completed remediation round (`findings_resolved ≥ 1`) even on an escalation hard
stop, since a mixed fix+escalate pass is a cycle, and keeps `root-cluster-suspected`
and `merge-advised` no-increment. When multiple tokens fire, delegate to
`loop-state.sh resolve-precedence` (→
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/exit-precedence.sh`). When any
guard fires, stop the Monitor if one is running and emit one terminal report. A poll
is running from the start of its arm until it prints any marker other than `CHANGED`
(or its arm expires, step 4); `--check` never leaves one running.

A productive cycle (`findings_resolved ≥ 1` returned with `EXIT_REASON=none`) re-arms
the idle window: stop the Monitor if a poll is running and arm per step 4 with the
pending seed captured before this cycle's dispatch (step 5) and a full fresh
`max_watch_duration`, recording a new window deadline. The re-arm is not a capture
site: the pending seed is never replaced by a fresh one.
Superseded-arm timeout. The pre-dispatch arm stays armed across a dispatch made while
a poll is running (step 5), so its `max_watch_duration` can elapse while the reviewer
runs and queue a `WATCH_TIMEOUT` for the arm this productive return supersedes.
Discard that `WATCH_TIMEOUT` before re-arming: it must not map to
`watch-window-elapsed` and must not be passed to `loop-state.sh resolve-precedence`.
Discard the timeout token only, never that arm's `CHANGED` events. The discard
applies to the productive return only; on a non-productive return and on every
terminal, `WATCH_TIMEOUT` is handled per step 5.
Gating: only a productive cycle resets the idle window. A `PREFILTER_SKIP` event is
not a productive cycle, does not dispatch, and must not reset the idle window. A
non-productive return (`findings_resolved = 0` with `EXIT_REASON=none`) keeps
watching on the current window, which does not reset. If a poll is still running,
leave it armed and discard the pending seed.
If no poll is running, run the QUIET-EXIT CHECK; on `UNCHANGED`, arm per step 4 with the pending seed
for the remaining idle budget of the current window, computed from the recorded
deadline (Window deadline), never the full `max_watch_duration`, and floored at 0
(the poll rejects a negative budget as `POLL_ERROR`; 0 prints `WATCH_TIMEOUT` at
once). Never arm with the seed the exited arm carried: an `initial` seed re-fires the
same approval and loops the confirmation pass. This arm is not a capture site. On any
terminal `EXIT_REASON`, discard the pending seed and stop any running Monitor.

QUIET-EXIT CHECK. Before the loop ends `clean` after an approval, or keeps watching
with no poll running, compare the PR once against the pending seed:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/pr-change-detect-poll.sh" --check <OWNER> <REPO> <PR_NUMBER> <max_watch_duration> <poll_interval> <reviewer_filter> <SELF_LOGIN> "<PENDING_SEED>"
```

`--check` first, then the same 7 positional args the step-4 arm uses, with the
pending seed as arg 8, quoted and verbatim. It runs one poll iteration and prints one
line: the marker, or `UNCHANGED`. `UNCHANGED` → finish the return: the
`approval-clean` terminal (step 5), or the arm for the remaining budget (Gating
above). `CHANGED` → run `prefilter.sh` per step 5: `PREFILTER_SKIP` counts as
`UNCHANGED`; `PREFILTER_DISPATCH` or `PREFILTER_ERROR` dispatches per step 5, with a
new pending seed. `REVIEWER_APPROVED` → confirmation pass (step 5). `STATE=MERGED` /
`STATE=CLOSED` → the `token-map` terminal (step 5). `CHECK_ERROR` or non-zero exit →
retry once, then terminal `blocked`. A confirmation return the check routes elsewhere
ends no cycle and maps no terminal. Only the moment between the check and the
terminal report stays unwatched, the bounded gap every terminal has.

## Dispatch contract

Spawn `hivemind:github-reviewer` with `mode: fix`, `pr`, `working_branch`, `base`,
`reviewer_filter` (scoped per `${CLAUDE_PLUGIN_ROOT}/references/github-pr-review-graphql.md`
Author Filtering), and `user_answer` only per step 3. Omit `target`: an absent target
is the full pass over unresolved feedback. Returns `exit_reason ∈ {clean,
injection-suspect, user-input-required, planner-escalation, high-severity-rejection,
root-cluster-suspected, merge-advised, blocked}` plus `findings_resolved` /
`findings_open` and escalation-conditional fields. The skill consumes the return and
never re-fetches or re-classifies.

## Termination guard set

Terminates on: `max_remediation_cycles` reached, the ceiling `loop-state.sh` declares
and enforces (→ `max-cycles-reached`); an idle `max_watch_duration` window elapsing
with no actionable arrival (→ `watch-window-elapsed`, a quiet window and never the
cycle ceiling); `same-finding-repeat` oscillation (→ `max-cycles-reached`, an
oscillation guard and never a quiet window); any reviewer `planner-escalation` /
`blocked` / `injection-suspect` / `high-severity-rejection` / `user-input-required` /
`root-cluster-suspected` / `merge-advised`; PR merged or closed; in-scope reviewer
approval with nothing actionable remaining, confirmed by the QUIET-EXIT CHECK (step
6). Cycle arithmetic, ceiling, terminal-vs-cycle, and `same-finding-repeat` mapping:
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh`. Multi-token
precedence order:
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/exit-precedence.sh`.

No local ledger is persisted: GitHub is the ledger, and its handled markers make
re-invocation idempotent on restart. The markers (a `Fixed in <SHA>` reply, a
`<!-- hivemind-defer-v1 -->` defer reply, an `EYES` reaction from
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/react-marker.sh`, a
findings-free Codex Review Summary) and their signal contract:
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/fix-history-classify.jq`
(header §1).

## Terminal report

The terminal report is this skill's return value, handed back to whatever invoked
it; it does not end the caller's turn. Once it is emitted, this skill's procedure
ends: it returns control to whatever invoked it, and the caller then continues from the point at which it invoked this skill, mapping `exit_reason` to the workflow transition and recording the state result.

Emit exactly one terminal report (validated by `tools/validate_reports.sh`
watch-pr-feedback). Fields: `Status: complete`; `PR` (Number / State / Branch /
Target); `Watch` (Mode: Monitor | Monitoring: stopped | Parser: gh --jq | Cycles |
Seen comments | New actionable comments); `Routed: github-reviewer: <count>`;
`Stopped because: <exit_reason> — <explanation>`; `Next action`; `Issues`.

`exit_reason` drawn from: `clean | pr-merged | pr-closed | max-cycles-reached | watch-window-elapsed | planner-escalation | root-cluster-suspected | merge-advised | blocked | injection-suspect | high-severity-rejection | user-input-required`. For `root-cluster-suspected`: cluster payload under `Issues`; cerebrate zoom-out under `Next action`. For `merge-advised`: `advisory_reason` + `structural_home` + `recommendation_text` under `Issues`. For escalation/blocked: escalation-conditional fields under `Issues`. `Cycles` = `cycles_completed`; `New actionable comments` = `findings_resolved`; restate `findings_open` in `Issues` when non-zero.

## Safety

- Never merge, close, or approve PRs.
- Never request external review or re-review.
- Do not start a second Monitor.
- Never wrap the poll in an `until`/`while`/`grep -q EXIT=` loop: the Monitor is the wait primitive; read its emitted lines directly.
- Never claim the watch is still active in a returned report: a returned run reports `Monitoring: stopped`.
- Single PR per invocation.
