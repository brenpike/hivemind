# Automated reviewer identity is one Bot-gated registry, and the default filter is every registered reviewer

**Status:** accepted — 2026-10-01

## Context

The github-reviewer agent and the `hivemind:github-review-loop` skill recognized exactly one reviewer as actionable by default: Codex, under the login base `chatgpt-codex-connector`, selected by `reviewer_filter: codex-only`. The approval signal that lets a watched PR end cleanly was likewise Codex-only — a 👍 reaction on the PR object, surfaced to the loop as the `CODEX_APPROVED` marker.

Operators also run GitHub Copilot code review and the Anthropic Claude review app on the same PRs. Under the Codex-only default, feedback from those reviewers was invisible to the loop unless the operator switched to `all`, which also admits every human and every unrelated bot on the PR.

The identity predicate itself was not held in one place. It was duplicated across `plugin/skills/github-review-loop/scripts/fix-history-classify.jq` and inline jq inside `plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh`, alongside inline `[bot]`-suffix strips and a Codex login literal embedded in the reactions `gh --jq` expression. Adding a second reviewer by hand would have meant editing every copy and keeping them in agreement.

## Findings

- **A bare login is not an identity.** GitHub's REST `users/claude` is a human `User` account created in 2009 (id 81847). The Claude review app posts as `claude[bot]`, a `Bot` (id 209825114). Stripping `[bot]` and comparing the bare login — the existing Codex technique — would admit that human as an automated reviewer.
- **The Copilot reviewer's login differs by API surface.** REST `users/copilot-pull-request-reviewer[bot]` resolves to the `Bot` login `Copilot` (id 175728472), while secondary sources report GraphQL author nodes carrying `copilot-pull-request-reviewer`. The evidence is conflicting and secondary, so both forms must match.
- **Codex resolves cleanly.** REST `users/chatgpt-codex-connector[bot]` is a `Bot` (id 199175422).
- **The bare org accounts cannot author reviews.** `copilot-pull-request-reviewer` and `chatgpt-codex-connector` without the suffix are `Organization` accounts, so they never appear as a comment or review author.
- **GitHub keeps each reviewer's latest verdict.** The GraphQL `PullRequest.latestReviews` connection is documented as the "latest reviews per user ... that are not also pending review" (primary: GitHub GraphQL reference, pulls). A secondary source (a9n-shoji/rvw pull 88) reports that the sibling connection `latestOpinionatedReviews`, which takes a `writersOnly` argument, keeps an author's `APPROVED` over a later `COMMENTED`, while `latestReviews` lets the later `COMMENTED` replace it. Another secondary source (notaharness/n10 pull 231) reports that `latestReviews` omits an author who has an open review request, and that Bot authors appear in it typed `Bot`.
- **GraphQL reactions cannot type a Bot reactor.** `Reaction.user` is typed `User` (primary: GitHub GraphQL reference, reactions), so a Bot's reaction cannot be read with its account type through the PR's `reactions` connection. `ReactionGroup.reactors` is a union connection that can carry a Bot, but it is capped at 100 reactors.
- **`gh --jq` prints string results raw.** go-gh `pkg/jq/jq.go` writes a string result raw and uncolored, one per line, while an object result may be colorized.
- **`gh api graphql --paginate` walks one connection per query.** The `gh` manual requires a paginated GraphQL query to accept an `$endCursor: String` variable and to select `pageInfo { hasNextPage endCursor }`; `gh` then requests pages until `hasNextPage` is false. Its cursor finder (cli/cli `pkg/cmd/api/pagination.go`, `findEndCursor`) follows the first `pageInfo` it meets in a response, so a query that holds a second paginated connection never walks that second one.
- **jq 1.6 binds data imports as arrays.** `import "x" as $x;` of a JSON data file yields an array wrapper under jq 1.6 (jqlang/jq issue 2208), so a registry held as a JSON data import reads differently across the jq versions this repo supports. A `def` returning a literal reads the same on all of them.

## Decision

### 1. One definitions-only jq module owns reviewer identity

`plugin/skills/github-review-loop/scripts/reviewer-identity.jq` is the single home for reviewer identity. It holds definitions only — no top-level filter — so every consumer pulls it in with `include` via `jq -L` and no consumer carries its own copy. It defines:

- `automated_reviewers` — the registry: Codex, Copilot, and Claude, each with its recognized login forms and its approval kind.
- `approval_kinds` — the closed set of approval signal kinds a registry entry may declare.
- `strip_bot` — the one `[bot]`-suffix normalizer.
- `is_self` — whether an author is the authenticated operator (§7).
- `reviewer_matches_filter` — whether an author is in scope under the active `reviewer_filter`.
- `reviewer_is_approver` — whether an author's signal counts as approval under the active filter.

The registry is a `def` literal, not a JSON data import, because of the jq 1.6 finding above. The live definitions are owned by the module; this record cites it rather than restating its bytes.

Closure tests and a policy pin enforce that no per-site copy of the predicate, the `[bot]` strip, or a reviewer login literal reappears in a consumer.

### 2. The identity key is actor type `Bot` plus login

A registry member matches only when the author's actor type is `Bot` AND its login matches one of the entry's recognized forms. Login alone is not sufficient, because of the human `claude` collision. Both Copilot login forms are listed.

### 3. The default `reviewer_filter` becomes `automated`

`automated` — every registry member, Bot-gated — replaces `codex-only` as the default. `codex-only`, `all`, and `<login>` are retained for backward compatibility. `<login>` stays type-agnostic: it matches that login whatever its actor type, as it did before. A filter keyword shadows a same-named login, so a reviewer whose login is literally `automated` or `all` cannot be selected through `<login>`.

### 4. Approval is generalized per reviewer and scoped by the active filter

Each registry entry declares its approval kind:

| Reviewer | Approval kind | Signal |
|---|---|---|
| Codex | `pr-reaction-thumbs-up` | a 👍 (`+1`) reaction on the PR object; 👀 is never approval |
| Copilot | `review-approved` | its entry in GitHub's per-author `latestReviews` is `APPROVED`; requires an admin opt-in, which per a secondary source arrived in a GitHub changelog dated 2026-09-01 |
| Claude | none | the loop ends through the idle watch window, never through an approval signal |

Approval counts only from a reviewer in scope under the active filter. A `review-approved` reviewer is judged by its entry in GitHub's `PullRequest.latestReviews`, which holds one entry per author: that author's latest submitted, non-pending review. The poll reads that current state from every page of `latestReviews` and never rebuilds it from the `reviews(last: 50)` history, which it keeps only for its change token and review total. An `APPROVED` superseded by a later `CHANGES_REQUESTED`, `COMMENTED`, or `DISMISSED` review from the same reviewer never counts.

A later `COMMENTED` superseding an `APPROVED` is deliberate. The loop asks whether this reviewer is satisfied now, not whether the PR may merge. `latestOpinionatedReviews` would keep the standing approval across the `COMMENTED`, so the approval bool would never fall, and a re-approval after the next remediation pass would raise no fresh false-to-true edge: the loop would end through the watch window instead of through the approval.

`latestReviews` is read exhaustively, with no bound. The poll reads it through its own `gh api graphql --paginate` call, separate from its change-detection snapshot query, which passes each page's `pageInfo.endCursor` back as `$endCursor` until `hasNextPage` is false; `first: 100` is the page size. The rows from every page are slurped into one array and judged through the module once. A partial walk fails the capture: a failed page, a GraphQL error, or a null `latestReviews` connection surfaces as `SNAPSHOT_ERROR` or `POLL_ERROR`, never as not-approved.

The Codex 👍 rows travel from the paginated REST reactions read as JSON objects: the `gh --jq` transport filter emits one `tojson`-encoded `{login, type}` object per `+1` reaction, and the poll decodes all rows with `jq -s` through the module. No row is split on a delimiter, so no byte of a login can be read as a field boundary. Each row is `tojson`-encoded because `gh` prints a string result raw and uncolored, while an object result may be colorized.

The loop marker `CODEX_APPROVED` is renamed `REVIEWER_APPROVED`, and the poll snapshot field `codex` is renamed `approval`. The seed width stays 9 scalars, so a seed written by an older version still parses.

### 5. `github-actions[bot]` is not in the default set

It is a generic CI identity, not a reviewer. Operators whose review bot posts as it use `all` or `<login>`.

### 6. fetch-normalize probes the classifier before use

`plugin/skills/github-review-loop/scripts/fetch-normalize.sh` gains a compile probe of the classifier, which now depends on the included module. A probe failure fails closed. It never degrades to a silent empty candidate array.

### 7. Self is account type `User` plus login

`is_self` holds an author to be the authenticated operator only when its account type is `User` AND its login equals the operator's login, which must be non-empty. Login alone is not sufficient, for the same reason as §2 seen from the other side: the Claude app's bare login in GraphQL is `claude`, which is also the login of the human `User` account `claude`. An operator signed in as that human would read every Claude review as self-authored, so its findings were dropped, its `Fixed in`, defer, and `Addresses:` markers were honored as the operator's own, and the change-detect poll never woke on its activity. A GitHub App's slug cannot collide with another account's login, so a hostile bot cannot take an arbitrary operator's login; the collision is with that one human account, and keying self on type `User` closes it.

The operator's identity comes from REST `/user`, the ground truth for the authenticated credential. `plugin/skills/github-review-loop/scripts/preflight.sh` resolves `SELF_LOGIN` only from a `/user` response whose `type` is `User` and fails closed with `SELF_LOGIN is not a User account` otherwise, so the predicate's `User` gate and the resolved login always describe the same account kind.

The type check is a positive allowlist: a null or missing account type is never self. Each consumer fails safe under that rule:

- **Filter self-exclusion** (`reviewer_matches_filter`) can only over-include: an unverified author is never dropped as self, so its content stays in scope for the active filter.
- **The forgery guard and the `Addresses:` harvest** in `fix-history-classify.jq` honor nothing from an author not verified as self: an unverified `Fixed in`, defer, or `Addresses:` marker is not treated as the operator's.
- **The change-detect poll** wakes: an unverified author's comment or thread reply is not suppressed as a self-echo.

### 8. Compatibility

Changing the default filter is a breaking change to the loop's default behavior, so it takes a major version bump. Migration for an operator who wants the old behavior: set `reviewer_filter: codex-only`.

## Considered Options

| Option | Rejected because |
|---|---|
| Match registry members by login alone | The human `User` `claude` collides with the Claude app's bare login; login-only matching admits a human as an automated reviewer |
| Treat every `__typename == Bot` author as an automated reviewer | Admits dependabot, renovate, coverage, and linter bots as actionable noise, and widens the injection surface to every installed app |
| Include `github-actions[bot]` in the default set | A generic CI identity. `claude-code-action` run with `github_token` posts as it, so admitting it admits every workflow that comments. Operators who need it use `all` or `<login>` |
| A `HIVEMIND_REVIEWER_LOGINS` env extension to the registry | DEFERRED under P23 (YAGNI): not requested, and `all` / `<login>` cover today's needs. Revisit trigger: the first concrete request for a fourth bot, which would also be Bot-gated |
| Hold the registry as a JSON data import | jq 1.6 binds data imports as arrays, so the registry would read differently across supported jq versions |
| Approval independent of the active filter | Would let a filtered-out reviewer end the loop it was filtered out of |
| Recognize self by login alone | A Bot whose bare login equals the operator's is read as self: its findings are dropped, its `Fixed in`, defer, and `Addresses:` markers are honored as the operator's, and the poll never wakes on it |
| Recognize self as any author whose type is not `Bot` (`type != "Bot"`) | A null or missing type would read as self, so an author of unverified type could have its marker honored as the operator's. The positive `User` allowlist fails toward actionable instead |
| Carry the viewer's account type as a predicate argument | Adds a positional argument to every self-aware predicate and call site with no information gain: preflight already guarantees the viewer is a `User`, so the constant `User` gate says the same thing |
| Rebuild each approver's latest review from the `reviews(last: 50)` history (highest `databaseId` per approver) | Windowed: on a PR with more than 50 reviews, the approval or the review that superseded it can fall outside the page, so the verdict depends on how many reviews the PR has. GitHub already reports the per-author latest review |
| Read Copilot approval from `latestOpinionatedReviews` | It keeps an `APPROVED` over a later `COMMENTED`, so a standing approval gives no fresh false-to-true edge after a re-approval, and a re-approved loop would end through the watch window instead of through the approval. The loop asks whether the reviewer is satisfied now, not whether the PR may merge |
| Read the Codex 👍 through GraphQL (`reactions` or `ReactionGroup.reactors`) | `Reaction.user` is typed `User`, so a Bot reactor cannot be read with its account type through `reactions`; `reactors` is capped at 100 and loses the coverage of the paginated REST read |
| Carry the 👍 rows as tab-separated text (`@tsv`) | Needs an enumerated set of escapes and a hand-written split, and a login byte read as a field boundary could forge the account type. JSON rows parsed by jq have no boundary to forge |
| Read `latestReviews` page 1 only (or raise the bound, or add an overflow guard) | An approver whose entry falls past the bound reads as not-approved, so a PR with many distinct reviewers ends through `WATCH_TIMEOUT` instead of through the approval. Raising the bound or guarding the overflow only moves the bound |
| Read each approver's latest review with `reviews(author: $login, last: 1)` | How that argument resolves a Bot login is undocumented and cannot be proven offline; a mismatch reads as not-approved forever. It also needs one alias or one call per recognized login |
| Read page 1 inline in the snapshot query and continue with a second query only when `hasNextPage` is true | Two read paths for one value, each needing its own failure handling and tests |
| One Bot-gated `def`-literal registry in a single included module; default `automated`; approval scoped by filter; self keyed on type `User` plus login; Copilot approval from every page of `latestReviews`, read through its own `gh api graphql --paginate` call with any partial walk failing the capture; 👍 rows carried as JSON (CHOSEN) | — |

## Consequences

- **Copilot and Claude feedback is actionable by default.** A wider default set means more remediation cycles on PRs those reviewers comment on.
- **The Copilot GraphQL login evidence is secondary and conflicting.** Both forms are listed to cover it; a live smoke on a Copilot-reviewed PR is recommended to confirm which form GraphQL actually reports, and that Bot reviewers appear in `latestReviews` typed `Bot`.
- **Copilot's `APPROVED` capability is verified only through a secondary article.** If the capability is absent or not opted into, the `review-approved` kind is inert — it never fires, and the loop ends through the watch window instead.
- **Copilot approval is found however many reviews and distinct reviewers the PR has.** It is read from every page of `latestReviews`, not from a 50-review history window.
- **The exhaustive approval read costs one more GraphQL call per poll iteration (recorded residual).** Each further 100 distinct reviewers adds one call. Every page of the walk runs inside the one 45-second `gh` call timeout, and a failure is a loud `POLL_ERROR` (`SNAPSHOT_ERROR` when capturing the seed), never a silent not-approved.
- **Part of the `latestReviews` semantics is secondary-sourced.** The primary documentation states only "latest reviews per user" that are not pending. The supersede-on-`COMMENTED` behavior, the `Bot` typing of its authors, and the omission of authors with an open review request come from secondary sources.
- **Approval reads false while a re-review request to the approver is pending,** if the secondary omission claim holds: the approver has no `latestReviews` entry until it submits its next review.
- **The Claude entry assumes the Anthropic Claude review app posts as `claude[bot]`.** A deployment that posts under another identity (such as `github-actions[bot]` via `claude-code-action` with `github_token`) is not matched by the default set.
- **A mid-session plugin upgrade may leave loaded prose expecting the old `CODEX_APPROVED` marker.** Bounded: a session restart picks up the new prose.
- **Under a non-registry `<login>` filter, a Codex 👍 no longer fires approval**, because approval is scoped to the active filter.
- **Identity has one home.** Adding a registry member is one entry in `reviewer-identity.jq`; the closure tests and policy pin catch a reintroduced per-site copy.
- **An operator signed in as the human `claude` account now receives Claude-bot feedback.** The Claude app's reviews are no longer mistaken for the operator's own.
- **A Bot sharing the operator's login can no longer forge dispositions or harvests.** Its `Fixed in`, defer, and `Addresses:` markers are not honored as the operator's.
- **Preflight now rejects a non-`User` credential.** A loop authenticated as a Bot or other non-`User` account stops at preflight with `SELF_LOGIN is not a User account` instead of running.

## References

- `plugin/skills/github-review-loop/scripts/reviewer-identity.jq` (owner of the live registry and predicates)
- `plugin/skills/github-review-loop/scripts/fix-history-classify.jq`, `plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh`, `plugin/skills/github-review-loop/scripts/fetch-normalize.sh` (consumers)
- `plugin/skills/github-review-loop/scripts/preflight.sh` (resolves `SELF_LOGIN` from REST `/user` and asserts a `User` account)
- https://api.github.com/users/claude
- https://api.github.com/users/claude%5Bbot%5D
- https://api.github.com/users/copilot-pull-request-reviewer%5Bbot%5D
- https://api.github.com/users/chatgpt-codex-connector%5Bbot%5D
- https://github.com/github/awesome-copilot/blob/main/skills/copilot-pr-autopilot/references/api-quirks.md
- https://github.com/anthropics/claude-code-action/blob/main/docs/faq.md
- https://docs.github.com/en/graphql/reference/pulls
- https://docs.github.com/en/graphql/reference/reactions
- https://github.com/cli/go-gh/blob/trunk/pkg/jq/jq.go
- https://github.com/a9n-shoji/rvw/pull/88
- https://github.com/notaharness/n10/pull/231
- https://cli.github.com/manual/gh_api
- https://github.com/cli/cli/blob/trunk/pkg/cmd/api/pagination.go
- https://jqlang.org/manual/
- https://github.com/jqlang/jq/issues/2208
