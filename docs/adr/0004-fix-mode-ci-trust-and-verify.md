# Fix-mode reports clean without waiting for CI re-run

**Status:** accepted — 2026-05-18

Fix-mode processes all review candidates in a single pass, pushes fixes, and returns `exit_reason: clean` to the orchestrator. It does not poll CI or wait for required checks to re-run before reporting.

The alternative — blocking until the pushed fix produces a green check — was prototyped as a `ci-verification-pending` exit reason (implemented in ed4c062, reverted in b23f37f). It created an unhandled terminal state: fix-mode is one-shot, so a pending-verification outcome had no path to resolution within that invocation. The agent would either block indefinitely (CI runs take minutes to hours) or surface a result the orchestrator couldn't act on. Neither is acceptable.

The `hivemind:github-review-loop` skill already owns the re-failure detection path. Its next poll captures exactly this case: a fix was pushed, the check has not yet re-run, and the subsequent poll cycle will confirm pass or detect regression. Duplicating that loop inside fix-mode would mean two owners of the same problem, with the added cost of indefinite blocking in the one-shot context.

The trust-and-verify pattern is the standard practice in CI workflows: push the fix, trust it resolves the failure, let the next pipeline run verify. The `hivemind:github-review-loop` skill's next poll is the canonical CI re-run verification path; fix-mode pushes-and-trusts, the skill verifies on the subsequent poll.

## Considered Options

| Option | Rejected because |
|---|---|
| `ci-verification-pending` exit reason (block until check passes) | One-shot context has no resolution path; blocks agent indefinitely while CI runs; unhandled exit reason surfaced to orchestrator |
| Poll CI inline before returning clean | Duplicates the github-review-loop skill's poll; fixes the wrong layer; adds minutes of latency to every fix-mode run even when fix is obviously correct |

## Consequences

- Fix-mode CAN report clean while a required check is still pending or re-running; this is expected and acceptable
- The `hivemind:github-review-loop` skill's next poll → reviewer confirmation pass → re-failure detection is the canonical verification path for CI re-run results
- If a fix does not resolve the underlying CI failure, the skill catches it on the subsequent poll cycle and routes accordingly
- No new exit reason is needed in fix-mode for the CI re-run scenario

## Amendment 2026-11-17: the CI re-failure path is the poll's CI_FAILED marker (issue 400)

Before this fix, the Consequences claim that the skill catches an unresolved CI failure on the subsequent poll cycle was false. The change-detect poll folded every non-terminal change into one `CHANGED` marker, and `prefilter.sh` judges only the review surfaces. A wake whose only change was the failed-check count reached the prefilter and was skipped as `PREFILTER_SKIP`. The running poll had already moved its baseline, so the CI failure was lost.

The claim now holds through the `CI_FAILED` marker. The poll prints it when the failed-check count rises against the previous snapshot or the seed, and the skill dispatches the reviewer on it directly, without the prefilter. A drop in the count, or red CI that stays red, still arrives as `CHANGED` and goes to the prefilter, so a steady red run does not re-dispatch.

A re-failure that keeps the same failed count across a push landing between two polls still raises no marker. This is an accepted residual, recorded in the accepted trade-offs of the `pr-change-detect-poll.sh` header. The next rise, or any other reviewer wake, picks it up, since the reviewer reads every failed check on each wake.

The Consequences list above is left as written; this amendment states the mechanism that makes it hold.
