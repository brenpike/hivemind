# Local review parity with post-PR review

**Status:** accepted — 2026-06-04

**Status note (2026-11-16):** supporting decision (a), the `HIVEMIND_LOCAL_REVIEW_MODEL` override, is superseded by ADR-0042 (`docs/adr/0042-tool-neutral-local-review.md`).

## Context

The pre-PR local adversarial Codex review (`local-reviewer` agent + `hivemind:adaptation-cycle` skill) historically UNDER-CAUGHT relative to the post-PR GitHub Codex review. Security, injection, contract, and performance defects — including P0s — slipped past the fast local loop and surfaced only on the slow GitHub round-trips. The goal of issue #165 is to SHIFT-LEFT to parity: the local loop should find what the GitHub round catches, before the PR opens.

This is a CONSUMER-AGNOSTIC plugin. It runs across many languages, frameworks, and project types, so parity cannot be bought with project-specific checklists or a curated corpus from any single past incident. Whatever closes the gap must derive from the PR under review, not from a fixed list.

## Decision

**The local review loop now reviews the FULL branch diff vs base on EVERY iteration (`--scope branch`), reversing the prior deliberate incremental-diff design in which iteration 2+ diffed only against the prior `HEAD`.**

This is the load-bearing change. Reasons:

1. **Parity.** The post-PR GitHub Codex review re-reads the WHOLE PR every round. Reviewing only the incremental diff locally is, by construction, a different and smaller surface than the thing it is meant to match. Full-branch-diff-every-iteration is the surface that achieves parity.
2. **Fixes mutate already-reviewed code.** A remediation commit edits code an earlier iteration already cleared. Whole-surface re-review catches fix-induced and fix-revealed defects — a fix that introduces a new injection sink, or one that uncovers a latent flaw in adjacent code — that an incremental diff is STRUCTURALLY BLIND to, because that code is no longer in the incremental delta.
3. **Precondition for generalize-the-finding.** A reviewer can only enumerate sibling occurrences of a pattern it can SEE. Incremental scope hides the siblings that live outside the latest delta, so pattern generalization is impossible without full-branch scope.
4. **Adversarial findings are cross-file relationships.** The dangerous shapes are flows — untrusted bytes originating in an UNTOUCHED file and reaching a CHANGED file. An incremental diff that shows only changed lines cannot represent the source end of that flow.

**Tradeoff:** parity costs more per iteration than an incremental diff. The cost is SELF-LIMITING. The loop only continues after `HEAD` advances; a zero-fix non-actionable pass converges within that SAME pass — the deterministic no-progress guard returns `clean` intra-iteration, without advancing to a re-review — so full re-review re-runs ONLY on iterations that actually changed code. Because that guard tests the current pass and carries no prior-HEAD dependency, it fires on iteration 1 too: an all-noise first pass costs exactly ONE review, not two. The existing anti-churn guards — break-fix detection, diminishing-returns, and max-iterations — already bound runaway re-litigation. Parity is therefore bought without an unbounded per-iteration tax.

### Supporting decisions

**(a) Configurable review model.** The codex review model is operator-overridable via `HIVEMIND_LOCAL_REVIEW_MODEL`. The value passes a charset gate and is forwarded as `--model`. When UNSET the flag is OMITTED entirely, so codex falls back to its own default — ZERO consumer regression and no plugin-shipped default model. The override lives in the `env` block of `.claude/settings.json` (committed) or `.claude/settings.local.json` (gitignored, per-account). The unavailable-model `400` case is account-specific and is not the plugin's to predict.

**(b) Context-derived ADDITIVE focus directive.** The reviewer judges, PER-PR, which classes of a universal language-agnostic risk taxonomy apply — untrusted-input, injection (shell / SQL / template / path), authz, resource/path safety, concurrency, secrets-exposure, performance, ADR-compliance. It discovers ADRs at the repo root and in nested `docs/adr` trees and folds the diff-relevant constraints in. It composes its OWN abstracted framing — never raw diff bytes — and passes that to codex as a positional focus argument forwarded after a `--` option terminator, which forces codex's parser to treat it as a positional regardless of leading dashes (position alone does not make it inert). The directive is additive: it sharpens, never narrows, the review.

**(c) Generalize-the-finding on BOTH sides.** For a pattern finding, codex enumerates the analogous sibling sites it can see. The reviewer then fixes ALL siblings when they fall within the ≤2-file bar, or escalates the whole pattern as a single item when they do not. The pattern is handled as one unit rather than as per-site whack-a-mole.

Escalation TIMING is unchanged by this ADR. ADR-0003 (immediate-stop-on-planner-escalation) was already superseded by ADR-0006; this ADR does not touch when escalation fires.

## Considered Options

| Option | Rejected because |
|---|---|
| Keep the incremental diff (cheaper per iteration) | Structurally blind to fix-induced defects in already-reviewed/untouched code and hides sibling sites — this IS the parity gap. The marginal saving buys back the exact under-catching #165 exists to close |
| Hardcode a security checklist from the #156 corpus | The plugin is consumer-agnostic across languages and project types; a fixed checklist over-fits one corpus and under-covers everything else. Focus must be DERIVED from the PR under review, not from a frozen list |
| Ship a default review model | Model availability is account-specific; a wrong default would `400` or silently change review quality. Omitting the flag when unset defers to codex's own default — no regression |

## Consequences

- **Parity-driven higher per-iteration cost,** bounded and self-limiting: full re-review only re-runs on iterations that advanced `HEAD`; a zero-fix non-actionable pass converges to `clean` WITHIN that same pass (no extra review), including on iteration 1, and break-fix / diminishing-returns / max-iterations bound the loop.
- **Operators can tune the review model** without a plugin change via `HIVEMIND_LOCAL_REVIEW_MODEL`; unset is a no-op that defers to codex's default.
- **The ADR-compliance probe makes the loop enforce project ADRs** — diff-relevant constraints from root and nested `docs/adr` are folded into the focus directive; a no-op when the consumer has no ADRs.
- **Generalize-the-finding closes the sibling-gap whack-a-mole** — patterns are enumerated and remediated (or escalated) as one unit on both the codex and reviewer sides.

Reference: issue #165.
