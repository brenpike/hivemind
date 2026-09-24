---
name: github-review-loop
description: Watches an open PR and remediates review feedback in a loop until a terminal condition. Executed by the overlord only — loop must run in the main session where Monitor survives subagent dispatches. Use when watching a PR for the GitHub review loop.
allowed-tools:
  - Read
  - Monitor
  - Agent(hivemind:github-reviewer)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/preflight.sh *)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/pr-change-detect-poll.sh *)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/prefilter.sh *)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/exit-precedence.sh *)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh *)
shell: bash
---

# GitHub Review Loop

Watch one open PR and drive remediation to a terminal state. Does NOT classify feedback — that is `hivemind:github-reviewer` fix-mode work.

Load and follow: `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md`, `${CLAUDE_PLUGIN_ROOT}/governance/safety-rails.md`, `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md`.

## Why this runs in the main session

Monitor is a main-session cross-turn primitive — a subagent dispatch orphans any Monitor armed inside it. The loop lives here so Monitor survives across reviewer dispatches; only the top-level orchestrator can spawn the reviewer (ADR-0005).

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `pr` | (required) | PR number or URL. |
| `working_branch` | (required) | Branch the reviewer pushes fixes to. |
| `base` | (required) | PR base/target branch. |
| `reviewer_filter` | `codex-only` | Actionable reviewer identities (`codex-only` \| `all` \| `<author>`). |
| `max_watch_duration` | `3600` | Idle-window seconds per Monitor arm (1h). |
| `max_remediation_cycles` | `$(bash ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh floor)` | Max real remediation rounds (findings_resolved ≥ 1). |
| `poll_interval` | `60` | Seconds between polls. |

`max_watch_duration` is an IDLE window, not a total budget: a completed remediation
cycle re-arms a fresh full window, and a window that elapses with no actionable
arrival ends the watch. The poll script's own deadline is PER-PROCESS, so a fresh
arm IS a fresh window — the idle semantics live here, in the arm/re-arm discipline.

`max_remediation_cycles` is a FLOOR. The floor value is DECLARED and ENFORCED by
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh`, and no
literal is restated here — query it with
`bash ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh floor`,
which prints a BARE integer and no `KEY=` label. That is why the default above is a
command SUBSTITUTION: the published value goes straight into any argv expecting the
number — including `cycle-decision`'s `<max_cycles>` — with nothing to strip.
A caller that invokes this loop with a lower value is REJECTED.

## Lifecycle

**1. Preflight.** Run `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/preflight.sh`
with `pr`, `working_branch`, `base` as positional args. Any `PREFLIGHT_ERROR=`
line or non-zero exit → terminal `blocked`. Confirm git state is not unsafe per
`${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State).

**2. Capture baseline.** BEFORE cycle 0 dispatches anything, capture the poll's
baseline seed:

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/pr-change-detect-poll.sh --snapshot initial <OWNER> <REPO> <PR_NUMBER> <max_watch_duration> <poll_interval> <reviewer_filter> <SELF_LOGIN>
```

`--snapshot` FIRST, then the ARM KIND (`initial` here — see Arm kind below), then
the SAME 7 positional args the Monitor arm uses — all 7
required and validated in snapshot mode, so pass the concrete values the arm will
use. stdout is exactly ONE `BASELINE=<seed>` line; strip the label and keep the
BARE token (`sed -n 's/^BASELINE=//p' | head -1`). A `SNAPSHOT_ERROR` line or
non-zero exit → RETRY ONCE; a second failure is terminal `blocked` (same posture
as `PREFLIGHT_ERROR`). NEVER arm the Monitor with an empty or absent seed — the
poll rejects it as `POLL_ERROR` regardless, so failing here is the honest path.
Capture BEFORE cycle 0: a seed taken after cycle 0 opens a blind window, in
which feedback that arrived during cycle 0 is never seen by the watch.

**3. Cycle 0.** Dispatch `hivemind:github-reviewer` fix mode (see Dispatch contract)
over pre-existing PR feedback before arming the Monitor. NEVER prefiltered. Handle
return per Reviewer-return handling. Pass the return through `loop-state.sh
cycle-decision`; arm the Monitor ONLY when `EXIT_REASON=none`. Any other
`EXIT_REASON` is terminal — emit the terminal report and end the loop here; do NOT arm the Monitor.
"End the loop" is scoped to this skill's own procedure only — see Terminal
report for how this skill hands control back to its caller.

**4. Arm Monitor.** Arm a Monitor in the main session on:

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/pr-change-detect-poll.sh <OWNER> <REPO> <PR_NUMBER> <max_watch_duration> <poll_interval> <reviewer_filter> <SELF_LOGIN> "<BASELINE_SEED>"
```

Resolved preflight values / skill inputs as positional args in that order, with the
step-2 seed as arg 8. QUOTE the seed — it contains `|`, and unquoted it becomes a
shell pipeline and breaks the arm. Pass the token verbatim: never lowercase, trim,
or re-wrap it. Poll emits ONLY on a real delta or terminal state. Read lines
directly — never into a functional pipe. EXPECTED: the first poll may fire
`CHANGED` off cycle 0's OWN `Fixed in <SHA>` replies, because the seed predates
them; that is absorbed downstream by `prefilter.sh` as `PREFILTER_SKIP`.
Over-reporting is SAFE here, under-reporting loses findings — add NO
duplicate-suppression.

An arm that returns with NO terminal marker means the arm EXPIRED, not that the
watch ended: re-arm for the REMAINING idle budget of the current window, reusing
the SAME seed the expired arm carried, per the Seed-Advance INVARIANT below.

**Arm kind.** Every seed is stamped `initial` or `re-arm` at capture, and the
stamp travels INSIDE the token — so carrying a seed forward carries its kind
forward, with no separate argument for a caller to forget. The kind answers one
question, once: does a Codex 👍 that PREDATES this arm surface? `initial` (step
2, before cycle 0) — YES: the watch has never observed the approval edge, so an
approval that landed in the blind window fires `CODEX_APPROVED` on the first
poll rather than idling to `WATCH_TIMEOUT`. `re-arm` (step 5's pre-dispatch
capture) — NO: the seed was taken immediately before a reviewer pass that
consumed that exact state, so a stale 👍 predating the pass must never re-fire.
The two capture sites of the Seed-Advance INVARIANT map one-to-one onto the two
kinds, and the seed serializes EVERY scalar the poll diffs — the approval bool
included — so the answer can never depend on which fields a token happens to
carry.

**Seed-Advance INVARIANT.** The baseline seed advances ONLY at a point where a
reviewer pass is about to consume the state it snapshots. There are exactly TWO
capture sites: step 2, before cycle 0, and step 5, before a dispatch. There is NO
third capture site, so the baseline can never advance past state nobody read. An
arm boundary (step 4) and a post-dispatch re-arm (step 6) are NOT capture sites:
each MUST reuse the seed it already carries, and taking a fresh `--snapshot` at
either boundary is FORBIDDEN. WHY: neither boundary is a reviewer pass, so
nothing has consumed the PR state there — at an arm boundary a fresh seed absorbs
any comment that arrived after the expired arm's final poll, and at a re-arm,
where the remediation push has already landed, a fresh seed absorbs any comment
that arrived DURING the fix; either way that comment never fires `CHANGED` and
— absent later activity — is lost for the life of the watch. Carrying the seed
forward costs at most a duplicate wake on activity the previous arm already
reported, or — because a pending seed predates its dispatch — a re-fire on our
own `Fixed in <SHA>` replies, the case step 4 documents above; `prefilter.sh`
absorbs both downstream as `PREFILTER_SKIP`. Over-reporting is SAFE,
under-reporting loses findings. This holds whatever the Monitor's own per-arm
ceiling turns out to be — assume no specific figure. The watch never silently
dies at an arm boundary.

**5. Per event.** `CHANGED` → run
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/prefilter.sh <OWNER> <REPO> <PR_NUMBER> <reviewer_filter> <SELF_LOGIN>`:
`PREFILTER_SKIP` → keep Monitor armed, no dispatch, no cycle/`Routed` increment.
`PREFILTER_DISPATCH` or `PREFILTER_ERROR=<reason>` → dispatch reviewer fix mode
(no `target`); `PREFILTER_ERROR` is fail-open. Handle return per Reviewer-return
handling. `CODEX_APPROVED` → confirmation pass (no `target`); use only the latest
poll's approval — a stale prior 👍 must never short-circuit later pushback. If the
reviewer finds nothing actionable, this is terminal `clean`. That staleness rule
is ENFORCED by the `re-arm` arm kind, not left to judgement: the pending seed
records the approval state as of the pre-dispatch capture, so a 👍 already
present then cannot fire again on the re-armed poll. Map the terminal via
`loop-state.sh cycle-decision <current_count> <max_cycles> 0 approval-clean`
(the `approval-clean` token emits `EXIT_REASON=clean`, distinguishing the approval
terminal from a plain keep-watching `clean`). If actionable items remain, the
reviewer processes them and returns a normal fix-mode exit_reason handled per
Reviewer-return handling. `STATE=MERGED` → `pr-merged`. `STATE=CLOSED` →
`pr-closed`. `WATCH_TIMEOUT` → `watch-window-elapsed`, EXCEPT a timeout from an arm a
productive return supersedes, which step 6 discards. `POLL_ERROR` → stop Monitor;
`blocked`. For the last four, use
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh token-map <signal>`.

PRE-DISPATCH SEED. BEFORE spawning the reviewer for ANY dispatch in this step —
the `PREFILTER_DISPATCH` / `PREFILTER_ERROR` fix pass AND the `CODEX_APPROVED`
confirmation pass alike — capture a PENDING re-arm seed per step
2's `--snapshot` procedure, with `re-arm` as the ARM KIND in place of step 2's
`initial`, and HOLD it; the Monitor stays armed meanwhile, so
nothing is missed while the reviewer runs. This is capture site 2 of the
Seed-Advance INVARIANT (step 4). A `SNAPSHOT_ERROR` or non-zero exit follows
step 2's posture: RETRY ONCE, then terminal `blocked`. `PREFILTER_SKIP` does not
dispatch and captures no pending seed. Step 6 consumes the pending seed on a productive return and
discards it on every other return.

**6. Reviewer-return handling.** `clean` → keep watching. `planner-escalation` |
`blocked` | `injection-suspect` | `high-severity-rejection` | `user-input-required`
→ HARD-STOP; ONE terminal with matching `exit_reason` + escalation-conditional
fields. `root-cluster-suspected` → HARD-STOP; ONE terminal with reviewer's cluster
payload; the caller routes to cerebrate zoom-out (classification-free — loop
propagates only). `merge-advised` → HARD-STOP; ONE `merge-advised` terminal with
`advisory_reason` + `structural_home` + `recommendation_text`; ADVISORY ONLY — loop NEVER merges
(classification-free). Pass EVERY reviewer return (including the escalation
terminals above) through
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh cycle-decision <current_count> <max_cycles> <findings_resolved> <exit_reason>`
for cycle increments, ceiling, `same-finding-repeat`, and terminal-vs-cycle: it
counts a completed remediation round (`findings_resolved ≥ 1`) even on an
escalation hard-stop — a mixed fix+escalate pass IS a cycle — while keeping
`root-cluster-suspected` and `merge-advised` no-increment. When
multiple tokens fire, delegate to `loop-state.sh resolve-precedence` (→
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/exit-precedence.sh`).
When any guard fires, stop Monitor and emit ONE terminal report.

A PRODUCTIVE cycle — `findings_resolved ≥ 1` returned with `EXIT_REASON=none` —
re-arms the idle window: stop the Monitor and arm per step 4 with the PENDING
seed captured before this cycle's dispatch (step 5) and a full fresh
`max_watch_duration`; a re-arm is not a capture site, and the pending seed is
never substituted for a fresh one, per the Seed-Advance INVARIANT (step 4).
SUPERSEDED-ARM TIMEOUT. The Monitor is deliberately left armed across dispatch
(step 5), so the pre-dispatch arm's `max_watch_duration` can elapse WHILE the
reviewer runs and queue a `WATCH_TIMEOUT` for the very arm this productive return
supersedes. DISCARD that superseded arm's `WATCH_TIMEOUT` before re-arming: the
window was NOT quiet — the reviewer just resolved findings — so it MUST NOT map to
`watch-window-elapsed` and MUST NOT be passed to `loop-state.sh
resolve-precedence`. Discard the timeout token ONLY, never that arm's `CHANGED`
events: staying armed across dispatch is what keeps change detection alive, and
dropping those loses findings. The discard is scoped to the PRODUCTIVE return; on a
non-productive return and on every terminal, `WATCH_TIMEOUT` is handled normally
per step 5. The fresh full `max_watch_duration` this re-arm grants IS the
replacement window — no seed is re-snapshotted, so the Seed-Advance INVARIANT is
untouched.
GATING: only a productive cycle consumes the pending seed and re-arms. A
`PREFILTER_SKIP` event is NOT a productive cycle, does not dispatch, and MUST
NOT reset the idle window. A NON-productive return (`findings_resolved = 0` with `EXIT_REASON=none`) keeps
watching on the CURRENT window: the Monitor was never stopped, so leave it armed
and DISCARD the pending seed — the window does not reset. On any terminal
`EXIT_REASON` the pending seed is discarded with the Monitor. Once the cycle
ceiling declared and enforced by
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh` is
reached, that script emits `max-cycles-reached` and the loop TERMINATES rather
than re-arming — which is why the re-arm is gated on
`EXIT_REASON=none`.

## Dispatch contract

Spawn `hivemind:github-reviewer` with `mode: fix`, `pr`, `working_branch`, `base`,
`reviewer_filter` (scoped per `${CLAUDE_PLUGIN_ROOT}/references/github-pr-review-graphql.md`
Author Filtering). Omit `target` — absent target is the full pass over unresolved
feedback. Returns `exit_reason ∈ {clean, injection-suspect, user-input-required,
planner-escalation, high-severity-rejection, root-cluster-suspected, merge-advised,
blocked}` plus `findings_resolved` / `findings_open` and escalation-conditional
fields. Skill consumes; does not re-fetch or re-classify.

## Termination guard set

Terminates on: `max_remediation_cycles` reached — the ceiling declared and
enforced by
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh` — (→
`max-cycles-reached`); an idle `max_watch_duration` window elapsing with no
actionable arrival (→ `watch-window-elapsed`, a QUIET window and never the cycle
ceiling); `same-finding-repeat` oscillation (→ `max-cycles-reached`, an
oscillation guard and never a quiet window); any reviewer
`planner-escalation` / `blocked` / `injection-suspect` / `high-severity-rejection`
/ `user-input-required` / `root-cluster-suspected` / `merge-advised`; PR merged
or closed; Codex approval with nothing actionable remaining.
Cycle arithmetic, ceiling, terminal-vs-cycle, and `same-finding-repeat` mapping:
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh`.
Multi-token precedence ORDER:
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/exit-precedence.sh`.
No persisted local ledger — GitHub is the ledger. Thread surfaces converge via
`Fixed in <SHA>` replies (fix-SHA skip makes re-invocation idempotent on restart).
Non-thread surfaces (`toplevel` / `review`) converge via a self-authored `EYES`
reaction on the reviewer node, written by
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/react-marker.sh` — the
"handled" marker lives durably on the PR, not on disk, so it survives loop polls
and session restarts with no `.hivemind` state. Both mechanisms keep the marker on
GitHub, strengthening the GitHub-is-the-ledger claim.

## Terminal report

This skill's terminal report is its RETURN VALUE, handed back to whatever
invoked it — it is not the caller's own terminal output, and emitting it does
not end the caller's turn. Once emitted, this skill's procedure ends: it
returns control to whatever invoked it, and the caller then continues from the point at which it invoked this skill, mapping `exit_reason` to the workflow transition and recording the state result.

Emit exactly ONE terminal report (validated by `tools/validate_reports.sh`
watch-pr-feedback). Fields: `Status: complete`; `PR` (Number / State / Branch /
Target); `Watch` (Mode: Monitor | Monitoring: stopped | Parser: gh --jq | Cycles |
Seen comments | New actionable comments); `Routed: github-reviewer: <count>`;
`Stopped because: <exit_reason> — <explanation>`; `Next action`; `Issues`.

`exit_reason` drawn from: `clean | pr-merged | pr-closed | max-cycles-reached | watch-window-elapsed | planner-escalation | root-cluster-suspected | merge-advised | blocked | injection-suspect | high-severity-rejection | user-input-required`. For `root-cluster-suspected`: cluster payload under `Issues`; cerebrate zoom-out under `Next action`. For `merge-advised`: `advisory_reason` + `structural_home` + `recommendation_text` under `Issues`. For escalation/blocked: escalation-conditional fields under `Issues`. `Cycles` = `cycles_completed`; `New actionable comments` = `findings_resolved`; restate `findings_open` in `Issues` when non-zero.

## Safety

- Never merge, close, or approve PRs.
- Never request external review or re-review.
- Do not start a second Monitor.
- Do NOT wrap the poll in an additional `until`/`while`/`grep -q EXIT=` loop — the Monitor IS the wait primitive; read its emitted lines directly.
- Never claim the watch is still active in a returned report — a returned run is no
  longer monitoring (`Monitoring: stopped`).
- Single PR per invocation.
