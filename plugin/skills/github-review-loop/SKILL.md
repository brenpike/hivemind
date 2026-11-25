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

Watch one open PR and drive remediation to a terminal state. Classifying feedback is `hivemind:github-reviewer` fix-mode work, never this skill's. The loop runs in the main session (ADR-0005).

Load and follow: `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` whole, `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md` whole, `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` whole.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `pr` | (required) | PR number or URL. |
| `working_branch` | (required) | Branch the reviewer pushes fixes to. |
| `base` | (required) | PR base/target branch. |
| `reviewer_filter` | `automated` | Actionable reviewer identities (`automated` \| `all` \| `<author>`); `codex-only` is rejected: use `<author>`. |
| `max_watch_duration` | `3600` | Idle-window seconds per Monitor arm (1h). |
| `max_remediation_cycles` | `$(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh" floor)` | Max real remediation rounds (findings_resolved ≥ 1). |
| `poll_interval` | `60` | Seconds between polls. |
| `user_answer` | (none) | Optional `{candidate_url, question, reply, decided_by}`: the user's answer to a question the reviewer asked, or the run's when `decided_by: run`, per `${CLAUDE_PLUGIN_ROOT}/agents/github-reviewer.md` (Fix Mode Input). |

`max_watch_duration` is an idle window, not a total budget: a completed remediation
cycle re-arms a fresh full window, and a window that elapses with no actionable
arrival ends the watch. The poll's deadline is per process, so a fresh arm is a
fresh window.

**Window deadline.** Only two arms open a window: the first arm after cycle 0 (step
4) and a productive re-arm (step 6). Each passes the full `max_watch_duration` and
records `$(date +%s)` plus it as the deadline. Every other arm continues the current
window: it passes `max(0, deadline - $(date +%s))` as `max_watch_duration`, never the
full value, and keeps the deadline.

`max_remediation_cycles` is a floor declared and enforced by
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh`, and no
literal is restated here. Its `floor` subcommand prints it as a bare integer, usable
in any argv, `cycle-decision`'s `<max_cycles>` included. A lower caller value is
rejected.

## Lifecycle

**1. Preflight.** Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/preflight.sh"`
with `pr`, `working_branch`, `base` as positional args. Any `PREFLIGHT_ERROR=`
line or non-zero exit → terminal `blocked`. Confirm git state is not unsafe per
`${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State). A `codex-only`
`reviewer_filter` is retired: terminal `blocked`; point the user to `<author>` mode.

**2. Capture baseline.** Before cycle 0 dispatches anything, capture the poll's
baseline seed:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/pr-change-detect-poll.sh" --snapshot initial <OWNER> <REPO> <PR_NUMBER> <max_watch_duration> <poll_interval> <reviewer_filter> <SELF_LOGIN>
```

`--snapshot` first, then the arm kind (`initial` here; see Arm kind), then the same 7
positional args the Monitor arm uses, all required, with the concrete values the arm
will use. stdout is exactly one `BASELINE=<seed>` line; keep
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
with the step-2 seed as arg 8. Quote the seed (it contains `|`) and pass it
verbatim: never lowercase, trim or re-wrap it. The poll emits only on a real delta
or terminal state. The first poll may fire `CHANGED` off cycle
0's own `Fixed in <SHA>` replies, because the seed predates them; `prefilter.sh`
absorbs that as `PREFILTER_SKIP`. Add no duplicate-suppression.

An arm that returns without printing a marker that ends the poll (a terminal marker,
`REVIEWER_APPROVED` or `REVIEWER_SETTLED`, step 5) expired; the watch has not ended. Re-arm for the
remaining idle budget of the current window (Window deadline), reusing the same seed
the expired arm carried (Seed-Advance invariant).

**Arm kind.** Every seed is stamped `initial` or `re-arm` at capture, inside the
token, so carrying a seed forward carries its kind. The kind decides whether an
in-scope reviewer approval that predates the arm surfaces: `initial` (step 2) yes,
so it fires `REVIEWER_APPROVED` on the first poll; `re-arm` (step 5) no, because the
reviewer pass about to run consumes that state, so a stale approval predating the
pass must never re-fire.

**Seed-Advance invariant.** The baseline seed advances only where a reviewer pass is
about to consume the state it snapshots, at exactly two capture sites: step 2, before
cycle 0, and step 5, before a dispatch. The QUIET-EXIT CHECK (`--check` reads a
pending seed and prints none), an arm boundary (step 4) and every re-arm capture
nothing: each reuses the seed it carries, and a fresh `--snapshot` there is
forbidden. `prefilter.sh` absorbs the resulting duplicate wakes as `PREFILTER_SKIP`.

**5. Per event.** `CHANGED` → run
`bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/prefilter.sh" <OWNER> <REPO> <PR_NUMBER> <reviewer_filter> <SELF_LOGIN>`:
`PREFILTER_SKIP` → keep Monitor armed, no dispatch, no cycle/`Routed` increment.
`PREFILTER_DISPATCH` or `PREFILTER_ERROR=<reason>` (fail-open) → dispatch reviewer fix
mode (no `target`); handle the return per step 6. `CI_FAILED` (the failed-check count
rose) → that dispatch without `prefilter.sh`, counted like `PREFILTER_DISPATCH`.
`REVIEWER_APPROVED` or `REVIEWER_SETTLED` (an approval, both handled alike) →
confirmation pass (no `target`); use only the latest poll's approval: a stale prior
approval must never short-circuit later pushback.
If the reviewer finds nothing actionable, the loop ends `clean` only after the QUIET-EXIT CHECK (step 6) reports nothing new since the pending seed.
The pending seed's `re-arm` kind keeps an approval present at the pre-dispatch
capture from firing again in that check or on the re-armed poll. On `UNCHANGED`,
apply the merge rule. If items remain actionable, handle the return per step 6. The
poll exits right after printing an approval, so no poll runs during the confirmation
pass: skip every stop-Monitor instruction for that pass's return and handle it per
step 6's no-poll-running rules. `STATE=MERGED` → `pr-merged`.
`STATE=CLOSED` → `pr-closed`. `WATCH_TIMEOUT` → `watch-window-elapsed`, except a
timeout from an arm a productive return supersedes, which step 6 discards.
`POLL_ERROR` → stop Monitor; `blocked`. For the last four, use
`bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh" token-map <signal>`.

Pre-dispatch seed. Before spawning the reviewer for any dispatch in this step, the
`PREFILTER_DISPATCH` / `PREFILTER_ERROR` / `CI_FAILED` fix pass and the
approval confirmation pass alike, capture a pending seed per step 2's
`--snapshot` procedure with `re-arm` as the arm kind, and hold it. This is capture
site 2 of the Seed-Advance invariant. A running poll stays armed during the dispatch.
When no poll is running (the confirmation pass, or a dispatch the
QUIET-EXIT CHECK routed), the pass's activity is caught only afterwards, by diffing this
pending seed in the next arm's first poll or in the QUIET-EXIT CHECK. A
`SNAPSHOT_ERROR` or non-zero exit: retry once, then terminal `blocked`.
`PREFILTER_SKIP` does not dispatch and captures no pending seed.

Merge rule. Only an approval return whose QUIET-EXIT CHECK reports `UNCHANGED` runs
`bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/merge-approved.sh" <OWNER> <REPO> <PR_NUMBER> <reviewer_filter> <SELF_LOGIN>`,
once; no other end runs it, `merge-advised` included. Right before every merge call,
in the same turn, invoke `hivemind:merge-write` (Skill tool), with no other skill call
between; a refused Skill call does not skip the merge call. Route the script's one line:
`MERGE=off` → map the terminal via `loop-state.sh cycle-decision <current_count> <max_cycles> 0 approval-clean`
(`approval-clean` emits `EXIT_REASON=clean`). `MERGE=merged` or `MERGE=merged-admin`
→ `pr-merged` via `loop-state.sh token-map STATE=MERGED`, the line under `Issues`.
`MERGE=wait:*` ends nothing: arm per step 4 with the pending seed for the time left
in the current window; that arm opens no window and is not a capture site.
`MERGE=skipped:*`, `MERGE_ERROR=` or a non-zero exit → the `approval-clean` terminal,
the line under `Issues` and `Next action` telling the human to merge.
A refused merge call (a permission or auto-mode denial, not a script exit) is
`MERGE=skipped:permission-denied`, routed the same with no retry; its `Next action`
also names the rule `Bash(bash "<the script's full path>" *)` for `permissions.allow`
in `.claude/settings.local.json`.

**6. Reviewer-return handling.** `clean` → keep watching. `planner-escalation` |
`blocked` | `injection-suspect` | `high-severity-rejection` | `user-input-required`
→ hard stop; one terminal with the matching `exit_reason` and the
reviewer's conditional fields. `root-cluster-suspected` → hard stop; one terminal
with the reviewer's cluster payload; the caller routes it to cerebrate zoom-out, and
the loop only propagates it. `merge-advised` → hard stop; one `merge-advised` terminal
with `advisory_reason` + `structural_home` + `recommendation_text`; advisory only, it
never runs the merge rule. Pass every reviewer return, the escalation terminals
included, through
`bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh" cycle-decision <current_count> <max_cycles> <findings_resolved> <exit_reason>`
for cycle increments, ceiling, `same-finding-repeat`, and terminal-vs-cycle. It counts
a completed remediation round (`findings_resolved ≥ 1`) even on an escalation hard
stop, since a mixed fix+escalate pass is a cycle, and keeps `root-cluster-suspected`
and `merge-advised` no-increment. When multiple tokens fire, delegate to
`loop-state.sh resolve-precedence` (→
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/exit-precedence.sh`). When any
guard fires, stop the Monitor if one is running and emit one terminal report. A poll
is running from the start of its arm until it prints any marker other than `CHANGED`
or `CI_FAILED` (or its arm expires, step 4); `--check` never leaves one running.

A productive cycle (`findings_resolved ≥ 1` returned with `EXIT_REASON=none`) re-arms
the idle window: stop the Monitor if a poll is running and arm per step 4 with the
pending seed captured before this cycle's dispatch (step 5) and a full fresh
`max_watch_duration`, recording a new window deadline. The re-arm is not a capture
site: the pending seed is never replaced by a fresh one.
Superseded-arm timeout. An arm left running across a dispatch (step 5) can time out
while the reviewer runs. Before a productive re-arm, discard that `WATCH_TIMEOUT`
token, never that arm's `CHANGED` or `CI_FAILED`: never map it to
`watch-window-elapsed` or pass it to `loop-state.sh resolve-precedence`. On a
non-productive return and every terminal, `WATCH_TIMEOUT` is handled per step 5.
Gating: only a productive cycle resets the idle window; a `PREFILTER_SKIP` never
does. A non-productive return (`findings_resolved = 0` with `EXIT_REASON=none`) keeps
watching on the current window. If a poll is still running, leave it armed and
discard the pending seed.
If no poll is running, run the QUIET-EXIT CHECK; on `UNCHANGED`, arm per step 4 with the pending seed
for the time left in the current window (Window deadline; the poll rejects a negative
budget as `POLL_ERROR`, and 0 prints `WATCH_TIMEOUT` at once). Never arm with the
seed the exited arm carried: an `initial` seed re-fires the same approval and loops
the confirmation pass. On any terminal `EXIT_REASON`, discard the pending seed and
stop any running Monitor.

QUIET-EXIT CHECK. Before the loop ends `clean` after an approval, or keeps watching
with no poll running, compare the PR once against the pending seed:

```
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/pr-change-detect-poll.sh" --check <OWNER> <REPO> <PR_NUMBER> <max_watch_duration> <poll_interval> <reviewer_filter> <SELF_LOGIN> "<PENDING_SEED>"
```

`--check` first, then the same 7 positional args the step-4 arm uses, with the
pending seed as arg 8, quoted and verbatim. It runs one poll iteration and prints one
line: the marker, or `UNCHANGED`. `UNCHANGED` → finish the return: the merge rule
(step 5), or the arm for the remaining budget (Gating above). `CHANGED` → run
`prefilter.sh` per step 5: `PREFILTER_SKIP` counts as `UNCHANGED`;
`PREFILTER_DISPATCH` or `PREFILTER_ERROR` dispatches per step 5, with a new pending
seed. `CI_FAILED` likewise.
`REVIEWER_APPROVED` → confirmation pass (step 5). `STATE=MERGED` /
`STATE=CLOSED` → the `token-map` terminal (step 5). `CHECK_ERROR` or non-zero exit →
retry once, then terminal `blocked`. A confirmation return the check routes elsewhere
ends no cycle and maps no terminal.

## Dispatch contract

Spawn `hivemind:github-reviewer` with `mode: fix`, `pr`, `working_branch`, `base`,
`reviewer_filter` (scoped per `${CLAUDE_PLUGIN_ROOT}/references/github-pr-review-graphql.md`
Author Filtering), and `user_answer` only per step 3. Omit `target`: an absent target
is the full pass over unresolved feedback. Returns `exit_reason ∈ {clean,
injection-suspect, user-input-required, planner-escalation, high-severity-rejection,
root-cluster-suspected, merge-advised, blocked}` plus `findings_resolved` /
`findings_open` and its Output Contract's conditional fields. The skill consumes the return and
never re-fetches or re-classifies.

## Termination guard set

Terminates on: `max_remediation_cycles` reached, the ceiling `loop-state.sh` declares
and enforces (→ `max-cycles-reached`); an idle `max_watch_duration` window elapsing
with no actionable arrival (→ `watch-window-elapsed`, a quiet window and never the
cycle ceiling); `same-finding-repeat` oscillation (→ `max-cycles-reached`, an
oscillation guard and never a quiet window); any reviewer `planner-escalation` /
`blocked` / `injection-suspect` / `high-severity-rejection` / `user-input-required` /
`root-cluster-suspected` / `merge-advised`; PR merged or closed; in-scope reviewer
approval, `REVIEWER_APPROVED` or the settled `REVIEWER_SETTLED`, with nothing
actionable remaining, confirmed by the QUIET-EXIT CHECK (step 6). Cycle arithmetic, ceiling, terminal-vs-cycle, and `same-finding-repeat` mapping:
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh`.

No local ledger is persisted: GitHub is the ledger, and its handled markers make
re-invocation idempotent on restart. The markers (a `Fixed in <SHA>` reply, a
`<!-- hivemind-defer-v1 -->` defer reply and an `EYES` reaction from
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/react-marker.sh`) and their signal contract:
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/fix-history-classify.jq`
(header §1).

## Terminal report

The terminal report is this skill's return value; it does not end the caller's
turn. Once it is emitted, this skill's procedure
ends: it returns control to whatever invoked it, and the caller then continues from the point at which it invoked this skill, mapping `exit_reason` to the workflow transition and recording the state result.

Emit exactly one terminal report (validated by `tools/validate_reports.sh`
watch-pr-feedback). Fields: `Status: complete`; `PR` (Number / State / Branch /
Target); `Watch` (Mode: Monitor | Monitoring: stopped | Parser: gh --jq | Cycles |
Seen comments | New actionable comments); `Routed: github-reviewer: <count>`;
`Stopped because: <exit_reason> — <explanation>`; `Next action`; `Issues`.

`exit_reason` drawn from: `clean | pr-merged | pr-closed | max-cycles-reached | watch-window-elapsed | planner-escalation | root-cluster-suspected | merge-advised | blocked | injection-suspect | high-severity-rejection | user-input-required`. For `root-cluster-suspected`: cluster payload under `Issues`; cerebrate zoom-out under `Next action`. For `merge-advised`: `advisory_reason` + `structural_home` + `recommendation_text` under `Issues`. For escalation/blocked: the reviewer's conditional fields under `Issues`. `Cycles` = `cycles_completed`; `New actionable comments` = `findings_resolved`; restate `findings_open` in `Issues` when non-zero.

## Safety

- Never close or approve a PR, and never merge except through the merge rule (step 5).
- Never request a review or re-review. A reviewer that needs a request is set up in the repo or requested by the user; otherwise the watch ends through its idle window.
- Do not start a second Monitor.
- Never wrap the poll in an `until`/`while`/`grep -q EXIT=` loop: the Monitor is the wait primitive; read its emitted lines directly.
- Never claim the watch is still active in a returned report: a returned run reports `Monitoring: stopped`.
- Single PR per invocation.
