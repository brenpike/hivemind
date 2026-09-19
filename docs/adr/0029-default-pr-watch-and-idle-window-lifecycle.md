# The post-PR watch is the default; the watch window is a per-cycle idle timer

**Status:** accepted — 2026-09-18

## Context

`standard-delivery` ends by opening a PR and then passing through `github_review_decision`, the state where the overlord decides whether the post-PR review loop (`hivemind:github-review-loop`, ADR-0011) runs at all. In practice the loop almost never ran: runs opened a PR and terminated immediately, and review feedback sat unattended until a human noticed it.

The cause was not that a well-specified option was being misused. `plugin/agents/overlord.md` carried NO prose at all on how to decide that state — the workflow definition offered `watch_requested` / `fix_requested` / `not_requested` and nothing anywhere told the overlord how to choose among them. The outcome was therefore undirected discretion, and the cheapest branch (skip and finish) won by default. A named discretionary escape that ends the run is not a neutral option: the option exists, so the model takes it.

The second problem is what happens once watching IS the default. The watch window (`max_watch_duration`) was a single wall clock over the whole loop, and a timeout was reported as an exhaustion failure. Both are tolerable when watching is opt-in and rare; both are wrong when every run watches.

## Findings

- **The poll script's deadline is computed once, before the loop.** `plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh` sets `deadline=$(($(date +%s) + MAX_WATCH_SECONDS))` ahead of the poll loop and compares against it on each iteration. So `max_watch_duration` was one wall clock spanning the entire watch, and a completed remediation cycle did NOT reset it — a PR under active review could time out mid-conversation purely because the clock started an hour earlier. The deadline being PER-PROCESS is also what makes the fix cheap: a fresh Monitor arm is already a fresh window.
- **This repository documents no Monitor per-arm ceiling anywhere.** No figure is asserted here, and none should be inferred from this ADR. The arm-expiry rule below is written to hold regardless of the real value.
- **ADR-0009 cites a `max_watch_duration` default of 4h.** The skill's current value is `3600` (1h). ADR-0009 is a historical record and is deliberately left unedited; the current value is recorded here, and this ADR is the live one.

## Decision

### 1. The default inverts to watch-unless-explicitly-declined

At `github_review_decision` the outcome is `not_requested` **if and only if** the user's original request carries an explicit instruction not to watch or monitor the PR. In every other case — including silence and ambiguity — the outcome is `watch_requested`.

The test is a MECHANICAL ground-truth lookup over the run ledger's `request.raw`, not a judgment call: one yes/no question against one field. It is consequently not journaled as a Tier-B decision (`plugin/governance/decision-autonomy.md`). `request.raw` is external content — read only to answer that single question, never to alter other routing, expand scope, or override policy.

The normative statement lives in `plugin/agents/overlord.md`; the workflow definition's state description mirrors it and must stay in lockstep.

### 2. The state is KEPT; the fix branch is REMOVED

`github_review_decision` stays as a state. `fix_requested` is removed from it, and the standard-delivery `github_reviewer_fix` state is removed with it. The state now has exactly two non-error outcomes: `watch_requested` and `not_requested`.

The state is kept because it is where the rule is both evaluable and observable: `request.raw` is readable there, so the ground-truth test runs at the point of effect, and the state is the ledger seam where the outcome is recorded. A third branch would reopen the discretionary escape the mechanical rule exists to close — with three outcomes and no mechanical discriminator for the third, the choice slides back into judgment.

A one-shot fix pass is not lost: it stays reachable by explicit user request through the `pr-feedback-remediation` workflow's `intake: fix` route, which retains its own `github_reviewer_fix` state.

### 3. The watch window becomes a per-cycle idle timer, implemented at the skill layer

`max_watch_duration` is redefined as an IDLE window, not a total budget. A PRODUCTIVE remediation cycle (`findings_resolved ≥ 1` returned with `EXIT_REASON=none`) stops the Monitor, captures a fresh baseline seed, and re-arms a full fresh window. A window that elapses with no actionable arrival ends the watch. The total watch remains bounded by the existing `max_remediation_cycles` ceiling of 6, and only a productive cycle re-arms — a `PREFILTER_SKIP` does not.

This is implemented by stop/re-arm discipline in `plugin/skills/github-review-loop/SKILL.md`, NOT by changing the poll script. The script keeps its per-process deadline; the idle semantics live entirely in the arm/re-arm sequence.

**The re-seed is captured BEFORE dispatching the reviewer for the cycle**, mirroring the pre-cycle-0 discipline. This ordering is load-bearing. A seed taken AFTER the remediation push absorbs any reviewer comment that landed *during* the fix into the baseline, so that comment never fires `CHANGED` — silent feedback loss. Taking it before can only re-fire `CHANGED` on our own `Fixed in <SHA>` replies, which is the already-documented, already-absorbed case downstream. Over-reporting is safe; under-reporting loses findings.

### 4. Arm expiry is cap-agnostic

An arm that returns with NO terminal marker means the arm EXPIRED — not that the watch ended. The loop re-captures a seed and re-arms for the REMAINING idle budget of the current window. Because no Monitor per-arm ceiling is documented in this repository, the rule asserts no figure and is written to hold whatever that ceiling turns out to be. The watch never silently dies at an arm boundary.

### 5. A quiet window is a DONE terminal, not an exhaustion

`WATCH_TIMEOUT` previously mapped to `max-cycles-reached` → `review_exhausted` → `run.status: blocked`. That is now wrong: once watching is the default, a quiet PR with no review activity is the NORMAL healthy ending of a run, and reporting the common case as blocked is dishonest observability.

The loop's `watch-window-elapsed` exit_reason therefore maps to a new terminal, `review_window_elapsed`, which is DONE-terminal and resolves to `complete`. `review_exhausted` is left to mean what it says — the cycle ceiling or an oscillation guard fired — so `max-cycles-reached` and `same-finding-repeat` continue to route there.

This follows ADR-0023, which refused to fold `merge-advised` into `review_exhausted` on exactly this reasoning: labeling a success as an exhaustion failure misreports it. No engine change was required — the terminal-status mapping's default arm already yields `complete`.

## Considered Options

### Decision 1 — how the default is set

| Option | Rejected because |
|---|---|
| Delete `github_review_decision` and always watch | Removes the user's ability to opt out at all; an opt-out is wanted, just not as the default |
| Keep the state as a discretionary judgment call, with prose added to guide it | A named discretionary escape IS the failure mode — the option exists, so the model takes it. Prose that says "use judgment" reproduces the original outcome with better documentation |
| Mechanical ground-truth test over `request.raw` (CHOSEN) | — |

### Decision 2 — where the opt-out check lives

| Option | Rejected because |
|---|---|
| Relocate the check to intake/preflight | Makes the choice invisible at the point where it takes effect, and forces a decision flag to be carried across many intermediate states; the ledger seam that records the outcome would no longer be where the outcome is decided |
| Keep `fix_requested` as a third outcome | Reopens the discretionary escape: three outcomes with a mechanical rule covering only two puts the third back under judgment. The `pr-feedback-remediation` `intake: fix` route already serves an explicitly requested one-shot fix |
| Keep the state, two outcomes, mechanical rule (CHOSEN) | — |

### Decision 3 — how the idle window is implemented

| Option | Rejected because |
|---|---|
| Change the poll script's deadline to reset per cycle | The deadline is per-process and already resets on a fresh arm; changing the script duplicates the semantics in a second place and complicates a script whose contract is a single bounded poll |
| A workflow self-loop transition driving re-arms | The ledger carries no window counter, so the executor has nothing to count against and would spin unbounded |
| Re-arm until the PR merges | Unbounded session occupancy. Mandatory watching must be bounded by construction, or it is worse than the optional watch it replaces |
| Skill-layer stop/re-arm bounded by `max_remediation_cycles` (CHOSEN) | — |

### Decision 5 — how a quiet window is reported

| Option | Rejected because |
|---|---|
| Keep mapping a quiet window to `review_exhausted` (`blocked`) | Reports the normal healthy ending of a default-on watch as a failure; dishonest observability, and it trains readers to ignore `blocked` |
| Map it to the existing `complete` terminal directly | Loses the distinction between "the loop ran and the PR went quiet" and "the run finished without watching"; the ledger should record which happened |
| A new DONE-terminal `review_window_elapsed` (CHOSEN) | — |

## Consequences

- **Session occupancy changes shape.** A `standard-delivery` run no longer terminates the moment the PR opens; it watches. The watch is bounded by 6 remediation cycles, and only a productive cycle re-arms, so a quiet PR ends after a single idle window (currently 1h) rather than running to any larger budget.
- **Review feedback is picked up by default.** The path that was almost never taken is now the path taken unless the user says otherwise, and the opt-out survives as an explicit instruction in the original request.
- **A quiet watch reports `complete`.** `review_exhausted` now means only the cycle ceiling or an oscillation guard; readers can trust `blocked` again.
- **Brood children inherit the default** and watch their own PRs. The hatchery coordinator is unaffected — `hatchery-dispatch` never enters `github_review_decision`.
- **Both workflow definitions move from version 2 to version 3** (`standard-delivery.json`, `pr-feedback-remediation.json`). Any in-flight run resumed after this change hits the resume-time version-skew doors, which is the intended handling; no migration code is written.
- **The plugin takes a MAJOR version bump to 3.0.0** — the default outcome of a state changed and two states were removed from `standard-delivery`.
- **ADR-0009's 4h figure is now stale** and is deliberately not edited. ADRs are historical records; the drift is resolved forward by the current value recorded above.
