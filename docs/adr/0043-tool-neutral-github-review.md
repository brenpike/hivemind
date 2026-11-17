# Post-PR GitHub review is tool-neutral

**Status:** accepted, 2026-11-16. Supersedes the reviewer registry, the `codex-only` filter and the per-reviewer approval kinds of ADR-0033. Supersedes the recorded decision "a running Codex review keeps the summary handled" (ADR-0037, Amendment 2026-10-27).

## Context

The post-PR watch (`hivemind:github-review-loop` and `hivemind:github-reviewer`) names reviewer products in code. `reviewer-identity.jq` holds a registry of three products (Codex, Copilot, Claude) with their logins and one approval kind each. `reviewer_filter` has a `codex-only` mode. `fix-history-classify.jq` parses the Codex Review Summary comment's private HTML state to mark it handled.

The user runs Codex at home and Copilot at work, and other review bots exist. The goal is one set of rules for every automated reviewer: no product named in code, and no per-request override. ADR-0042 did the same for local review. The decisions below come from a plan-interrogation session with the user on 2026-11-16. https://github.com/brenpike/hivemind/issues/576 tracks the work.

## Decision

1. **Identity.** An Automated Reviewer is a Bot account that has submitted a PR review on the watched PR. The registry is removed. Bots that only post status comments (coverage, deploy previews, dependency bots) never submit a review, so they stay out with no list to maintain.
2. **Optional setting.** `HIVEMIND_PR_REVIEWERS` names more Bot logins, comma- or space-separated, the `[bot]` suffix optional. It adds to the set from rule 1 and never narrows it. Every listed login is still Bot-gated, so a human account with the same bare login never matches. It covers a bot that only posts plain PR comments.
3. **`github-actions[bot]`** counts only when named in `HIVEMIND_PR_REVIEWERS`. It is the generic CI identity, as ADR-0033 found, and is excluded even when it submits a review.
4. **`codex-only` is retired.** The input gate rejects it and points to `<login>` mode. This is a breaking change: MAJOR bump.
5. **Approval.** A Reviewer Approval is any one of these, from an in-scope Automated Reviewer: its latest review is `APPROVED`; its latest review is `COMMENTED` with no inline review comments; or it left a 👍 reaction on the PR object. A 👍 from any Bot other than `github-actions[bot]` also makes that Bot an Automated Reviewer, so Codex's clean-PR 👍 still ends the watch with no review and no config. Review text is never read for approval. The existing guard stays: approval is terminal only when no unresolved actionable items remain.
6. **Codex summary signal dropped.** A summary comment edited in place re-arms under the one handled-marker rule (#568), and the github-reviewer classifies it on each edit.
7. **The loop never requests a review.** A reviewer that needs a request (Copilot without an automatic-review ruleset) is set up in the repo or requested by the user. With no review, the watch ends through its idle window.

## Considered options

- **Any Bot account is a reviewer.** Rejected: status bots would become candidates, widening noise and the injection surface.
- **Keep the registry and add a setting to extend it.** Rejected: products stay named in code.
- **`HIVEMIND_PR_REVIEWERS` replaces the default set.** Rejected: users would have to list every bot to add one.
- **Match approval text** such as Copilot's "Approval Recommended", or a phrase list setting. Rejected: product wording in code, and text matching on external content.
- **Keep `codex-only` as an alias** of `automated` or of the Codex login. Rejected: one silently widens scope; the other keeps a product name in code.

## Consequences

- A Codex user pays one extra github-reviewer dispatch per Codex review round, for the edited summary comment.
- A top-level comment from a Bot that has not yet reviewed or reacted is out of scope under `automated` until it does.
- A bot's 👍 on the PR can end the watch early when no actionable item is open. This is rare for non-review bots.
