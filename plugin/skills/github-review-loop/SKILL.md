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
| `max_watch_duration` | `3600` | Seconds before timeout (1h). |
| `max_remediation_cycles` | `3` | Max real remediation rounds (findings_resolved ≥ 1). |
| `poll_interval` | `60` | Seconds between polls. |

## Lifecycle

**1. Preflight.** Run `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/preflight.sh`
with `pr`, `working_branch`, `base` as positional args. Any `PREFLIGHT_ERROR=`
line or non-zero exit → terminal `blocked`. Confirm git state is not unsafe per
`${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State).

**2. Capture baseline.** BEFORE cycle 0 dispatches anything, capture the poll's
baseline seed:

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/pr-change-detect-poll.sh --snapshot <OWNER> <REPO> <PR_NUMBER> <max_watch_duration> <poll_interval> <reviewer_filter> <SELF_LOGIN>
```

`--snapshot` FIRST, then the SAME 7 positional args the Monitor arm uses — all 7
required and validated in snapshot mode, so pass the concrete values the arm will
use. stdout is exactly ONE `BASELINE=<seed>` line; strip the label and keep the
BARE token (`sed -n 's/^BASELINE=//p' | head -1`). A `SNAPSHOT_ERROR` line or
non-zero exit → RETRY ONCE; a second failure is terminal `blocked` (same posture
as `PREFLIGHT_ERROR`). NEVER arm the Monitor with an empty or absent seed — the
poll rejects it as `POLL_ERROR` regardless, so failing here is the honest path.
Capturing BEFORE cycle 0 IS the fix for the #324 blind window: a seed taken after
cycle 0 re-opens it.

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

**5. Per event.** `CHANGED` → run
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/prefilter.sh <OWNER> <REPO> <PR_NUMBER> <reviewer_filter> <SELF_LOGIN>`:
`PREFILTER_SKIP` → keep Monitor armed, no dispatch, no cycle/`Routed` increment.
`PREFILTER_DISPATCH` or `PREFILTER_ERROR=<reason>` → dispatch reviewer fix mode
(no `target`); `PREFILTER_ERROR` is fail-open. Handle return per Reviewer-return
handling. `CODEX_APPROVED` → confirmation pass (no `target`); use only the latest
poll's approval — a stale prior 👍 must never short-circuit later pushback. If the
reviewer finds nothing actionable, this is terminal `clean`: map it via
`loop-state.sh cycle-decision <current_count> <max_cycles> 0 approval-clean`
(the `approval-clean` token emits `EXIT_REASON=clean`, distinguishing the approval
terminal from a plain keep-watching `clean`). If actionable items remain, the
reviewer processes them and returns a normal fix-mode exit_reason handled per
Reviewer-return handling. `STATE=MERGED` → `pr-merged`. `STATE=CLOSED` →
`pr-closed`. `WATCH_TIMEOUT` → `max-cycles-reached`. `POLL_ERROR` → stop Monitor;
`blocked`. For the last four, use
`${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/loop-state.sh token-map <signal>`.

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

## Dispatch contract

Spawn `hivemind:github-reviewer` with `mode: fix`, `pr`, `working_branch`, `base`,
`reviewer_filter` (scoped per `${CLAUDE_PLUGIN_ROOT}/references/github-pr-review-graphql.md`
Author Filtering). Omit `target` — absent target is the full pass over unresolved
feedback. Returns `exit_reason ∈ {clean, injection-suspect, user-input-required,
planner-escalation, high-severity-rejection, root-cluster-suspected, merge-advised,
blocked}` plus `findings_resolved` / `findings_open` and escalation-conditional
fields. Skill consumes; does not re-fetch or re-classify.

## Termination guard set

Terminates on: `max_remediation_cycles` reached; `max_watch_duration` timeout;
`same-finding-repeat` oscillation (→ `max-cycles-reached`); any reviewer
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

`exit_reason` drawn from: `clean | pr-merged | pr-closed | max-cycles-reached | planner-escalation | root-cluster-suspected | merge-advised | blocked | injection-suspect | high-severity-rejection | user-input-required`. For `root-cluster-suspected`: cluster payload under `Issues`; cerebrate zoom-out under `Next action`. For `merge-advised`: `advisory_reason` + `structural_home` + `recommendation_text` under `Issues`. For escalation/blocked: escalation-conditional fields under `Issues`. `Cycles` = `cycles_completed`; `New actionable comments` = `findings_resolved`; restate `findings_open` in `Issues` when non-zero.

## Safety

- Never merge, close, or approve PRs.
- Never request external review or re-review.
- Do not start a second Monitor.
- Do NOT wrap the poll in an additional `until`/`while`/`grep -q EXIT=` loop — the Monitor IS the wait primitive; read its emitted lines directly.
- Never claim the watch is still active in a returned report — a returned run is no
  longer monitoring (`Monitoring: stopped`).
- Single PR per invocation.
