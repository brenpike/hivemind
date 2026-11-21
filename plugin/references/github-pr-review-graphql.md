# GitHub PR Review GraphQL Reference

## Author Filtering

`reviewer_filter` selects which non-self authors' feedback is in scope. Every mode first excludes self-authored content. An author is self (the `is_self` predicate) only when its account type (GraphQL `author.__typename`, REST `user.type`) is `User` and its login equals `SELF_LOGIN`. A Bot with the operator's login, or an author whose account type is missing or null, is never self.

An Automated Reviewer is a Bot that submitted a review on the PR or left a 👍 on the PR object, plus each login in `HIVEMIND_PR_REVIEWERS` (comma- or space-separated, `[bot]` optional). That setting only adds, and a login it names matches only a Bot. `github-actions[bot]` counts only when named there. A Bot (the `is_bot` predicate) has account type `Bot` or a raw login ending in `[bot]`, since REST types a bot reactor `User`. A login alone is never an identity: a human `User` can share a bot's bare login.

| Mode | In scope |
|------|----------|
| `automated` (default) | every Automated Reviewer |
| `all` | every author |
| `<login>` | the author whose login, with a trailing `[bot]` stripped, equals the value; type-agnostic. The keywords above shadow a same-named login |

`codex-only` is retired: the filter rejects it. Use `<login>`.

A Reviewer Approval comes from an in-scope Automated Reviewer: its latest review is `APPROVED`, or `COMMENTED` with no inline comments, its 👍 on the PR object, or a settled approval (`REVIEWER_SETTLED`). Review text is never read. Approval is terminal only when nothing actionable remains.

Every identity predicate (the `[bot]` strip, Bot, self, filter and approver matching) lives only in `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reviewer-identity.jq`. Consumers include that module; never restate a reviewer login or copy a predicate inline.

If identity is unclear, ask the user before processing.
