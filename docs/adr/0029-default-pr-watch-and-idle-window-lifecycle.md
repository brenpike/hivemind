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

That predicate sentence is the normative rule, and this record does NOT change it. It lives in `plugin/agents/overlord.md`, where it is pinned byte-for-byte by a policy fixture; the rule text has not moved. What is corrected below is how that rule is CHARACTERIZED.

An earlier draft of this record called the test a MECHANICAL ground-truth lookup over `request.raw`. That label was wrong, and a pre-PR review escalated it. Deciding whether a sentence of free prose "carries an explicit instruction not to watch" is a NATURAL-LANGUAGE READ OF UNTRUSTED TEXT; no amount of if-and-only-if phrasing makes a model's read of prose deterministic, and calling it mechanical invites readers to trust it as if it were.

The honest characterization is a FIXED-DEFAULT BINARY READ: one default (`watch_requested`), one admissible escape (`not_requested`), and the escape must be affirmatively found in `request.raw`. **The safety property is BIAS, not determinism.** The construction makes the unsafe outcome the one that requires evidence, so every failure of the read that is a failure to FIND evidence lands on the safe side.

The rule is nevertheless still NOT a Tier-B judgment call and is still NOT journaled (`plugin/governance/decision-autonomy.md`). The reason is not that the read is mechanical — it is that the rule presents NO CHOICE AMONG OUTCOMES. There is one fixed default, one admissible escape keyed to a found fact, and no discretion to weigh between them. A journal entry records a choice the overlord made on the user's behalf; here there is no choice to record.

`request.raw` is external content — read only to answer that single question, never to alter other routing, expand scope, or override policy.

**Recorded residual: a confident literal misread can still reach `not_requested`.** Recorded per the **Recorded Residual** clause of `plugin/governance/remediation-doctrine.md`. The bias closes one failure mode and not the other. An UNCERTAIN read — the model is unsure whether a sentence declines the watch — falls to `watch_requested`, because ambiguity is named in the predicate and routes to the default. A CONFIDENT LITERAL MISREAD does not: a request that merely MENTIONS not watching — quoting it, citing it, giving it as an example, or dictating prose to be written into a file — can be read as an instruction, and the escape is then taken. The bias protects against HEDGING; it does not protect against CONFIDENT LITERALISM. The claim that "every misread lands on `watch_requested`" appeared in an earlier draft of this argument, is FALSE, and must not be reproduced. Bounded impact: the failure costs one un-watched PR on one run, recoverable by re-running the review loop against the same PR; it cannot corrupt the repository, the ledger, or any other routing decision, because `request.raw` is read for this one question only. The sharpest concrete case is a BROOD CHILD: there `request.raw` is machine-authored strain task text, and no human is present in that session at all — the text being read was never written by anyone intending to answer this question, and no operator is standing by to notice a misread. The obvious remediations were considered and rejected on the merits; see the Decision 1 options table below.

**Taking the escape obliges a verbatim citation.** An outcome of `not_requested` requires the overlord to record the VERBATIM substring of `request.raw` it relied on into the free-form `event.outputs` of the `github_review_decision` state-result. No citable span means the escape is not available and the outcome is `watch_requested`. This is the closest available thing to a ground-truth derivation of the escape: the outcome is ANCHORED TO BYTES that exist in the field and is AUDITABLE IN THE LEDGER after the fact, rather than merely asserted by the model. A reader can diff the cited span against `request.raw` and see whether the escape was earned — it converts an unfalsifiable read into a checkable claim. Mechanically it rides the EXISTING sanctioned free-form `event.outputs` path, the same one `outputs.pr`, `recurrence_origin`, and `decisions[]` already use; it is NOT a new ledger field and needs no schema change. The exact output key is named in the agent contract in `plugin/agents/overlord.md`; this record states the obligation, not the key.

**A standing "never watch" preference gets a non-prose channel.** An operator may set an env key in the project's `.claude/settings.json` `env` block meaning "never watch", checked by simple PRESENCE — no prose read at all. The precedent is `HIVEMIND_LOCAL_REVIEW_MODEL` (ADR-0022; see also CLAUDE.md), already an operator-set env key in that same block. It is a genuine improvement on three counts: it is MECHANICAL in the sense the prose read only claimed to be — presence of a key, not interpretation of a sentence; it is set by a HUMAN BEFORE the run rather than inferred by a model DURING it; and because the settings file is in-repo it INHERITS into brood worktrees, which is exactly the case where `request.raw` is machine-authored and no human is present. Its LIMIT, recorded honestly: it is a standing PREFERENCE, not a per-run instruction — it cannot say "don't watch this one". It narrows the surface the prose read must cover; it does NOT replace the per-run read, and the residual above stands for every run where no such key is set. The key's name is given in the agent contract alongside the rule.

The normative statement lives in `plugin/agents/overlord.md`; the workflow definition's state description mirrors it and must stay in lockstep.

### 2. The state is KEPT; the fix branch is REMOVED

`github_review_decision` stays as a state. `fix_requested` is removed from it, and the standard-delivery `github_reviewer_fix` state is removed with it. The state now has exactly two non-error outcomes: `watch_requested` and `not_requested`.

The state is kept because it is where the rule is both evaluable and observable: `request.raw` is readable there, so the ground-truth test runs at the point of effect, and the state is the ledger seam where the outcome is recorded. A third branch would reopen the discretionary escape the mechanical rule exists to close — with three outcomes and no mechanical discriminator for the third, the choice slides back into judgment.

A one-shot fix pass is not lost: it stays reachable by explicit user request through the `pr-feedback-remediation` workflow's `intake: fix` route, which retains its own `github_reviewer_fix` state.

### 3. The watch window becomes a per-cycle idle timer, implemented at the skill layer

`max_watch_duration` is redefined as an IDLE window, not a total budget. A PRODUCTIVE remediation cycle (`findings_resolved ≥ 1` returned with `EXIT_REASON=none`) re-arms a full fresh window; a window that elapses with no actionable arrival ends the watch. Only a productive cycle re-arms — a `PREFILTER_SKIP` does not. The re-arm does NOT capture a seed at the re-arm point: the fresh window is armed with the seed captured BEFORE that cycle's dispatch, per the ordering below. The total watch remains bounded by `max_remediation_cycles`, whose floor is declared and enforced by `plugin/skills/github-review-loop/scripts/loop-state.sh`; this record asserts no figure and cites that script as the only home of the current value.

This is implemented by stop/re-arm discipline in `plugin/skills/github-review-loop/SKILL.md`, NOT by changing the poll script. The script keeps its per-process deadline; the idle semantics live entirely in the arm/re-arm sequence.

**The re-seed is captured BEFORE dispatching the reviewer for the cycle**, mirroring the pre-cycle-0 discipline. This ordering is load-bearing. A seed taken AFTER the remediation push absorbs any reviewer comment that landed *during* the fix into the baseline, so that comment never fires `CHANGED` — silent feedback loss. Taking it before can only re-fire `CHANGED` on our own `Fixed in <SHA>` replies, which is the already-documented, already-absorbed case downstream. Over-reporting is safe; under-reporting loses findings. The operative capture rule is NOT restated here: the single authoritative statement is the `INVARIANT` block in `plugin/skills/github-review-loop/SKILL.md` — the baseline seed advances ONLY at a point where a reviewer pass is about to consume the state it snapshots. This record states WHY that ordering was chosen; the skill states WHAT it is.

### 4. Arm expiry is cap-agnostic

An arm that returns with NO terminal marker means the arm EXPIRED — not that the watch ended. The loop re-arms for the REMAINING idle budget of the current window, REUSING the SAME seed the expired arm carried; it NEVER takes a fresh snapshot at an arm boundary, because an arm expiry is not a reviewer pass and nothing has consumed the PR state there. That is the section-3 `INVARIANT` applied at the arm boundary, and its operative form lives in `plugin/skills/github-review-loop/SKILL.md`, not here. Because no Monitor per-arm ceiling is documented in this repository, the rule asserts no figure and is written to hold whatever that ceiling turns out to be. The watch never silently dies at an arm boundary.

### 5. A quiet window is a DONE terminal, not an exhaustion

`WATCH_TIMEOUT` previously mapped to `max-cycles-reached` → `review_exhausted` → `run.status: blocked`. That is now wrong: once watching is the default, a quiet PR with no review activity is the NORMAL healthy ending of a run, and reporting the common case as blocked is dishonest observability.

The loop's `watch-window-elapsed` exit_reason therefore maps to a new terminal, `review_window_elapsed`, which is DONE-terminal and resolves to `complete`. `review_exhausted` is left to mean what it says — the cycle ceiling or an oscillation guard fired — so `max-cycles-reached` and `same-finding-repeat` continue to route there.

This follows ADR-0023, which refused to fold `merge-advised` into `review_exhausted` on exactly this reasoning: labeling a success as an exhaustion failure misreports it. No engine change was required — the terminal-status mapping's default arm already yields `complete`.

## Considered Options

### Decision 1 — how the default is set

| Option | Rejected because |
|---|---|
| Delete `github_review_decision` and always watch | Removes the user's ability to opt out at all; an opt-out is wanted, just not as the default |
| Keep the state as a discretionary judgment call, with prose added to guide it | A named discretionary escape IS the failure mode — the option exists, so the model takes it. Prose that says "use judgment" reproduces the original outcome with better documentation. The relabel adopted above is NOT this option: the vice named here is an OPEN CHOICE among outcomes plus "use judgment", whereas the relabel preserves the fixed default, the if-and-only-if keying, and the single admissible escape, and changes only how the rule is characterized |
| Harden the predicate with a directive-vs-mention carve-out (quoted / cited / to-be-written-into-a-file text does not count) | ENUMERATES handled cases, so it fails this repo's own **Closed-by-Construction Acceptance Test** (`plugin/governance/remediation-doctrine.md`). The next finding arrives same-framed with different bytes — reported speech, conditionals, a negated mention. It also RELOCATES the natural-language judgment ("is this a directive or a mention?") rather than removing it |
| Require a structured non-prose opt-out flag on the ledger | The non-brood path has NO human input point between planning and the terminal — the only `user_gate` is the brood-confirm gate — so the only party who could set the flag is the overlord reading the same `request.raw` at intake. The repo already does exactly that for the router's `context` booleans. It moves the identical read one file earlier and adds a ledger field for no epistemic gain |
| Fixed-default binary read of `request.raw`, biased to `watch_requested`, with a verbatim-citation obligation on the escape and a presence-checked standing-preference env key (CHOSEN) | — |

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
- **The preventive half of this record's remediation is DEFERRED.** Two structural checks — one asserting that no caller invokes the loop below the `max_remediation_cycles` floor, one asserting that no prose outside `plugin/skills/github-review-loop/SKILL.md` restates the seed-capture rule — were identified and NOT built. They are tracked at https://github.com/brenpike/hivemind/issues/362, raised by review threads https://github.com/brenpike/hivemind/pull/361#discussion_r4051925782 and https://github.com/brenpike/hivemind/pull/361#discussion_r4051925784. The exposure is bounded to FUTURE AUTHORING: every current caller honors the floor, which is now declared and enforced at runtime by `plugin/skills/github-review-loop/scripts/loop-state.sh`, and no current prose restates the seed rule, the copies in this record having been reduced to citations above. What is unprotected is a NEW caller or a NEW prose copy added later, which nothing in the suite would catch.
- **ADR-0009's 4h figure is now stale** and is deliberately not edited. ADRs are historical records; the drift is resolved forward by the current value recorded above.
