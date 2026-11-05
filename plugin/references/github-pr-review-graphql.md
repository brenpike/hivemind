# GitHub PR Review GraphQL Reference

## Author Filtering

`reviewer_filter` selects which non-self authors' feedback is in scope. Every mode first excludes self-authored content. An author is self (the `is_self` predicate) only when its account type (GraphQL `author.__typename`, REST `user.type`) is `User` and its login equals `SELF_LOGIN`. A Bot with the operator's login, or an author whose account type is missing or null, is never self, so its content stays in scope for the filter below.

| Mode | In scope |
|------|----------|
| `automated` (default) | every automated reviewer in the registry (Codex, Copilot, Claude), Bot-gated |
| `codex-only` | the Codex registry entry only, Bot-gated |
| `all` | every author |
| `<login>` | the author whose login, with a trailing `[bot]` stripped, equals the value; type-agnostic. The keywords above shadow a same-named login |

Bot-gated: an author matches a registry entry only when it is a Bot account and its login, with a trailing `[bot]` stripped, is one of that entry's recognized login forms. A Bot account (the `is_bot` predicate) has account type `Bot` or a raw login ending in the reserved `[bot]` suffix. Neither the account type alone nor the login alone is an identity: REST reports a bot reactor typed `User`, and a human `User` account shares the Claude app's bare login. A login without the suffix whose account type is missing or null never matches a registry mode.

The registry and every identity predicate (recognized login forms, the `[bot]` strip, self, filter and approver matching) live only in `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reviewer-identity.jq`. Consumers include that module; never restate a reviewer login or copy a predicate inline.

`github-actions[bot]`, the generic CI identity, is not in the registry. Select it with `all` or an explicit `<login>` filter.

If identity is unclear, ask the user before processing.
