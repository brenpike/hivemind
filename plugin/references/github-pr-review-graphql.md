# GitHub PR Review GraphQL Reference

Use these operations for pull request review remediation.

Resolvable pull request review threads are GraphQL objects. Do not try to resolve review threads using REST review-comment IDs.

## Contents

- [Shell and Parsing Rules](#shell-and-parsing-rules) — deterministic CLI commands and jq usage constraints
- [Pagination Requirement](#pagination-requirement) — mandatory paging for all connections that may exceed page size
- [Fetch Reviews](#fetch-reviews) — retrieve review summaries including `CHANGES_REQUESTED` and `COMMENTED` states
- [Fetch Review Threads](#fetch-review-threads) — retrieve inline review threads with comments and metadata
- [Fetch Thread Comments (Paginated)](#fetch-thread-comments-paginated) — retrieve additional comment pages from a single thread
- [Fetch Top-Level PR Comments](#fetch-top-level-pr-comments) — retrieve issue-level comments (not inline review threads)
- [Detection Filtering](#detection-filtering) — filters to apply before yielding any result as actionable feedback
- [Reply to Review Thread](#reply-to-review-thread) — mutation to post a reply to an existing review thread
- [Resolve Review Thread](#resolve-review-thread) — mutation to mark a review thread as resolved
- [Surface-to-Delivery Contract](#surface-to-delivery-contract) — canonical mapping of feedback surface to mutation(s) used
- [Reaction Marker](#reaction-marker) — self-authored `EYES` reaction that marks a fixed non-thread surface handled
- [Author Filtering](#author-filtering) — `reviewer_filter` modes, the Bot-type + login identity rule for scoping feedback to reviewer identities, and the User-type + login self rule
- [Reviewer Approval Detection](#reviewer-approval-detection) — in-scope automated-reviewer approval signals (paginated PR 👍 reaction lookup, paginated per-author `latestReviews` APPROVED lookup)

## Shell and Parsing Rules

Use `gh --jq` only for inline value extraction. No ad-hoc standalone `jq`, `python3`, `python`, `node`, or PowerShell. No `/tmp/` for data processing. If `gh --jq` cannot produce the required value, return `blocked`.

Sanctioned exception — canonical fix-history classification: `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/fetch-normalize.sh` (which the github-reviewer agent calls) captures the raw `gh api graphql` JSON (threads/comments/reviews/top-level, with the contract fields `isResolved`, `comments.totalCount`, comment `databaseId`, `author.login`, `author.__typename`, `body`, top-level/review `url`, review `state`) and pipes it through the shared filter FILE `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/fix-history-classify.jq` via `jq -L <scripts dir> -f`. The script supplies the `-L` module search path because the classifier `include`s the reviewer identity module `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reviewer-identity.jq`. This is a pure offline function over already-fetched JSON and is the single source of truth for the skip/order/overflow predicate; it is NOT the ad-hoc inline `jq` munging this rule prohibits. The same exception covers evaluating that module's identity predicates over rows a `gh --jq` transport filter emitted (see [Reviewer Approval Detection](#reviewer-approval-detection)).

## Pagination Requirement

Page all connections via `-F after="CURSOR"` using `endCursor` from `pageInfo`. Omit `-F after` on first page. Nested connections (e.g., thread comments) require per-item queries with the item's `id`. This requirement governs the reviewer's deep body-level fetch (reviews, review threads, thread comments, top-level comments) and both approval lookups, each a `gh api --paginate` walk: the REST reactions read for the PR 👍 and the GraphQL `latestReviews` read for the `APPROVED` review (see [Reviewer Approval Detection](#reviewer-approval-detection)). The `github-review-loop` thin poll is exempt by design for its change-detection tokens only: it reads one bounded page of each change-detection GraphQL connection plus `totalCount` tripwires and walks no cursors for them. The exemption never covers an approval read; the poll runs both approval lookups as the same exhaustive walks.

## Fetch Reviews

Use this query to retrieve review summaries (including `CHANGES_REQUESTED` and `COMMENTED` reviews whose body contains actionable feedback not captured in inline threads).

```bash
gh api graphql \
  -f owner="OWNER" \
  -f repo="REPO" \
  -F pr=123 \
  -f query='
query($owner: String!, $repo: String!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviews(first: 50, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          databaseId
          author { login __typename }
          state
          body
          submittedAt
          url
        }
      }
    }
  }
}'
```

## Fetch Review Threads

```bash
gh api graphql \
  -f owner="OWNER" \
  -f repo="REPO" \
  -F pr=123 \
  -f query='
query($owner: String!, $repo: String!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      number
      url
      state
      reviewThreads(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 20) {
            totalCount
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              databaseId
              author { login __typename }
              body
              createdAt
              url
              path
              line
              diffHunk
            }
          }
        }
      }
    }
  }
}'
```

### Unresolved summary output

```
--jq '.data.repository.pullRequest.reviewThreads.nodes[]
      | select(.isResolved == false)
      | . as $thread
      | $thread.comments.nodes[]
      | select(.body != null and (.body | gsub("[[:space:]]+"; "") != ""))
      | select((.author.__typename == "User" and .author.login == $ENV.SELF_LOGIN) | not)
      | "THREAD=\($thread.id) COMMENT=\(.id) AUTHOR=\(.author.login) PATH=\($thread.path) LINE=\($thread.line // "") URL=\(.url)"'
# SELF_LOGIN is resolved at runtime via: gh api user --jq 'select(.type == "User") | .login'
```

## Fetch Thread Comments (Paginated)

Use this query to retrieve additional pages of comments from a single review thread when `comments(first: 20)` returns `pageInfo.hasNextPage == true`. `threadId` is the thread's GraphQL node id (e.g., `PRRT_...`).

The thread node `id` selected in [Fetch Review Threads](#fetch-review-threads) (`reviewThreads.nodes[].id`) is the value `fix-history-classify.jq` carries as the `thread_id` field on each thread-surface classifier record (per-comment AND the overflow sentinel). A consumer paginating an overflowed thread feeds that `thread_id` straight back as this query's `threadId` argument.

```bash
gh api graphql \
  -f threadId="THREAD_NODE_ID" \
  -f query='
query($threadId: ID!, $after: String) {
  node(id: $threadId) {
    ... on PullRequestReviewThread {
      comments(first: 20, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          databaseId
          author { login __typename }
          body
          createdAt
          url
        }
      }
    }
  }
}'
```

## Fetch Top-Level PR Comments

Top-level PR comments are issue comments because every PR is also an issue.

```bash
gh api graphql \
  -f owner="OWNER" \
  -f repo="REPO" \
  -F pr=123 \
  -f query='
query($owner: String!, $repo: String!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      comments(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          author { login __typename }
          body
          createdAt
          url
        }
      }
    }
  }
}' \
  --jq '.data.repository.pullRequest.comments.nodes[]
        | select(.body != null and (.body | gsub("[[:space:]]+"; "") != ""))
        | select((.author.__typename == "User" and .author.login == $ENV.SELF_LOGIN) | not)
        | "COMMENT=\(.id) AUTHOR=\(.author.login) URL=\(.url)"'
# SELF_LOGIN is resolved at runtime via: gh api user --jq 'select(.type == "User") | .login'
```

## Detection Filtering

All queries must apply both filters before yielding results as actionable feedback. Silently skip items that fail either filter.

1. **Exclude empty body:** `select(.body != null and (.body | gsub("[[:space:]]+"; "") != ""))`
2. **Exclude self-authored:** `select((.author.__typename == "User" and .author.login == $ENV.SELF_LOGIN) | not)` — the `gh --jq` form of the `is_self` predicate in `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reviewer-identity.jq`. Self is a `User`-typed author whose login equals `SELF_LOGIN`: a Bot sharing the operator's login is never self, and a missing or null `__typename` never reads as self, so such an item stays actionable. Resolve once per poll: `export SELF_LOGIN=$(gh api user --jq 'select(.type == "User") | .login')` — empty output means the authenticated identity is not a `User` account; stop rather than poll with an empty `SELF_LOGIN`.

The Fetch Review Threads (unresolved summary output) and Fetch Top-Level PR Comments templates apply both filters inline. The Fetch Reviews and Fetch Thread Comments (Paginated) templates return raw nodes — consuming agents must apply both filters to their results before yielding as actionable feedback. For Fetch Reviews, also filter to `state` values `CHANGES_REQUESTED` or `COMMENTED`.

An `APPROVED` review is never actionable feedback, and these filters do not detect approval. Approval is per reviewer: an `APPROVED` review state is approval only from a reviewer whose approval kind is `review-approved` (Copilot); Codex never files an `APPROVED` review — its approval is a 👍 reaction on the PR object. Both are scoped by the active `reviewer_filter` (see [Reviewer Approval Detection](#reviewer-approval-detection)).

## Reply to Review Thread

```bash
gh api graphql \
  -f threadId="THREAD_ID" \
  -f body="Fixed in COMMIT_SHA. SUMMARY." \
  -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(
    input: {
      pullRequestReviewThreadId: $threadId,
      body: $body
    }
  ) {
    comment { id url }
  }
}'
```

The reply body is one of two sanctioned forms depending on remediation outcome: `Fixed in COMMIT_SHA. SUMMARY.` (shown above) for a committed fix, or `<!-- hivemind-defer-v1 --> Deferred to TRACKED_HOME. SUMMARY.` for a deferred candidate. A defer body MUST START WITH the exact `<!-- hivemind-defer-v1 -->` sentinel: the sentinel is the machine marker that records the thread as already deferred, and the `Deferred to TRACKED_HOME.` prose alone records nothing. No other body shape is emitted on this mutation.

## Resolve Review Thread

```bash
gh api graphql \
  -f threadId="THREAD_ID" \
  -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) {
    thread { id isResolved }
  }
}'
```

## Surface-to-Delivery Contract

Maps each feedback surface to the mutation(s) used to mark a fixed or deferred surface handled. The mapping is closed-by-construction — no runtime fallback, no `addComment` mutation, no `Addresses: <url>` body convention. `reply-resolve.sh` remains the THREAD-ONLY mutation path (reply + conditional resolve); the non-thread `toplevel`/`review` surfaces are marked handled by a self-authored `EYES` reaction (see [Reaction Marker](#reaction-marker)), NOT by `reply-resolve.sh`.

| Surface | Mutation(s) | Notes |
|---------|-------------|-------|
| `thread` | `addPullRequestReviewThreadReply` then (conditional) `resolveReviewThread` | Reply targets the thread node id (`PRRT_...`) with one of two sanctioned bodies: `Fixed in <SHA>. <summary>.` (fix) or `<!-- hivemind-defer-v1 --> Deferred to <TRACKED_HOME>. <summary>.` (defer, sentinel-first — the sentinel is the machine marker, not the prose). Resolve fires only when the thread is unresolved after reply. Executed by `reply-resolve.sh`. |
| `toplevel` | `addReaction` (`EYES`) on the IssueComment node | A self-authored `EYES` (👀) reaction is added to the reviewer's top-level IssueComment node as the handled marker. NOT reply-targeted, NOT thread-resolvable (top-level PR comments have no thread node). `reply-resolve.sh` is NOT invoked for this surface — it is a silent no-op for `toplevel`; posting `addPullRequestReviewThreadReply` against a non-thread node fails, because a top-level IssueComment has no review-thread node to target. |
| `review` | `addReaction` (`EYES`) on the PullRequestReview node | Same as `toplevel`: a self-authored `EYES` (👀) reaction is added to the reviewer's PullRequestReview summary node as the handled marker. Review-summary nodes have no thread node, so they are NOT reply-targeted and NOT thread-resolvable. `reply-resolve.sh` is NOT invoked — its `review` silent no-op is UNCHANGED. |
| unmapped / unknown | fail-closed | Any surface value not in the table above causes the script to exit with an error rather than fall through silently. |

Thread replies carry only the fix or defer summary: no `Addresses: <url>` back-reference line is appended on the emit path. The handled marker for non-thread surfaces is the `EYES` reaction described below; ZERO new PR comments are posted.

## Reaction Marker

Non-thread reviewer surfaces (`toplevel` = IssueComment, `review` = PullRequestReview summary) carry `thread_id: null` and have no thread node to reply to or resolve. A committed fix to such a surface is recorded handled by adding a self-authored `EYES` (👀) reaction to the reviewer's own comment/review node. Both `IssueComment` and `PullRequestReview` implement `Reactable`, so the same mutation and harvest fragment apply to both.

### Emit (mark handled)

`$nodeId` is the reviewer's IssueComment or PullRequestReview GraphQL node id (the `id` selected in [Fetch Top-Level PR Comments](#fetch-top-level-pr-comments) / [Fetch Reviews](#fetch-reviews)).

```bash
gh api graphql \
  -f nodeId="NODE_ID" \
  -f query='
mutation($nodeId: ID!) {
  addReaction(input: { subjectId: $nodeId, content: EYES }) {
    reaction { content }
  }
}'
```

`EYES` is the single named marker constant — a member of the `ReactionContent` enum. It is chosen because it reads semantically as "seen/handled". `addReaction` against a node the authenticated viewer has ALREADY reacted to with the same content is a server-side no-op / success — the emit path tolerates re-marking the same node without special-casing duplicates.

### Harvest (detect handled)

Add this fragment to the IssueComment node selection in [Fetch Top-Level PR Comments](#fetch-top-level-pr-comments) and to the PullRequestReview node selection in [Fetch Reviews](#fetch-reviews):

```graphql
reactionGroups { content viewerHasReacted }
```

A surface is handled when its `reactionGroups` contains an entry with `content == "EYES"` and `viewerHasReacted == true`. `viewerHasReacted` is scoped to the authenticated `gh` viewer (OUR identity), so a human or Codex reacting with the same 👀 emoji from ANOTHER account never false-positives our handled signal — only our own reaction counts.

### Disambiguation — two different `EYES` subjects

The `EYES` marker here is OUR self-authored reaction on a per-COMMENT / per-REVIEW node. It is a DISJOINT subject from the 👀 reaction noted in [Reviewer Approval Detection](#reviewer-approval-detection), which is Codex's reaction on the PR OBJECT meaning "still running" — never approval. The two share an emoji but never the same subject:

- **This marker:** `EYES` reaction on an `IssueComment` / `PullRequestReview` node, authored by our viewer, detected via `reactionGroups { content viewerHasReacted }` on that node → surface handled.
- **Codex "still running" (existing):** `eyes` reaction on the PR object, authored by Codex, detected via the REST reactions endpoint → never approval.

A reader must not conflate them: per-node viewer-scoped handled marker vs PR-object Codex-authored progress signal.

## Author Filtering

`reviewer_filter` selects which non-self authors' feedback is in scope. Every mode first excludes self-authored content. An author is self only when its account type is `User` (GraphQL `author.__typename`, REST `user.type`) AND its login equals `SELF_LOGIN` — the module's `is_self` predicate. A Bot whose login equals the operator's is never self, and a missing or null account type never reads as self, so that author's content stays in scope for the filter below.

| Mode | In scope |
|------|----------|
| `automated` (default) | every automated reviewer in the registry — Codex, Copilot, and Claude — Bot-gated |
| `codex-only` | the Codex registry entry only, Bot-gated |
| `all` | every author |
| `<login>` | the author whose login, with a trailing `[bot]` stripped, equals the value; type-agnostic. The keywords above shadow a same-named login |

Identity key for the registry modes (`automated`, `codex-only`): an author matches a registry entry only when it is a Bot account AND its login, with a trailing `[bot]` stripped, is one of that entry's recognized login forms. "Bot-gated" in the table above means exactly this Bot-account requirement. An author is a Bot account — the module's `is_bot` predicate — when its account type is `Bot` (GraphQL `author.__typename`, REST `user.type`) OR its raw login ends in the reserved `[bot]` suffix. The account type alone is not enough: the REST reactions endpoint reports a bot reactor's `user.type` as `User` while its login keeps the `[bot]` suffix, and GraphQL reports the same bot under its bare login typed `Bot`. No human can carry the suffix, because a GitHub login is alphanumerics and hyphens only. A login alone is not an identity: a human GitHub `User` account shares the Claude app's bare login once `[bot]` is stripped, so login-only matching would admit that human as an automated reviewer. A login without the suffix whose account type is missing or null never matches a registry mode. Self identity keys on the account-type field too, which is why every template above selects `author { login __typename }`.

The registry and every identity predicate — recognized login forms, the `[bot]` strip, self matching, filter matching, approver matching — live in one home: `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reviewer-identity.jq`. Consumers include that module; never restate a reviewer login or copy a predicate inline.

`github-actions[bot]` is deliberately not in the registry. It is the generic CI identity every workflow step posts as, so admitting it by default would admit arbitrary CI output and widen the injection surface. Operators whose review bot posts as `github-actions[bot]` select it with `all` or an explicit `<login>` filter.

If identity is unclear, ask the user before processing.

## Reviewer Approval Detection

An automated reviewer's approval is the signal that lets a watched PR end cleanly. Each registry entry in `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reviewer-identity.jq` declares its approval kind. Approval counts only from an approver of that kind that is a Bot account per the module's `is_bot` that is also in scope under the active `reviewer_filter`, so a filtered-out reviewer never ends the loop it was filtered out of.

| Approval kind | Reviewer | Signal |
|---------------|----------|--------|
| `pr-reaction-thumbs-up` | Codex | a 👍 (`+1`) reaction on the PR object |
| `review-approved` | Copilot | its per-author `latestReviews` entry has `state` `APPROVED` |

Claude declares no approval kind; a Claude-reviewed loop ends through the idle watch window, never through an approval signal. Approval never overrides open feedback: while unresolved non-self actionable items remain, the PR is not clean.

### PR 👍 reaction (`pr-reaction-thumbs-up`)

Read the paginated REST reactions endpoint so the approver's reaction is found even when the PR has more than one page of reactions. The `gh --jq` filter is transport only: it emits one JSON object `{login, type}` per `+1` reaction, carrying `user.type` verbatim, and makes no identity decision. REST reports a bot reactor typed `User`, so the transport never reads or rewrites `type`; the module's `is_bot` decides Bot-ness from the type or the reserved `[bot]` login suffix.

```bash
gh api --paginate "repos/OWNER/REPO/issues/PR_NUMBER/reactions" \
  --jq '.[] | select(.content == "+1") | {login: .user.login, type: .user.type} | tojson'
```

Each row is `tojson`-encoded because `gh` prints a string result raw and uncolored, one per line, while an object result may be colorized; the encoded row is plain JSON text whatever the output stream. The rows are JSON values, parsed by jq, never split: slurp every row from every page into one array (`jq -s`) and match them all at once through the module's `reviewer_is_approver` (kind `pr-reaction-thumbs-up`) and `reviewer_matches_filter` predicates, which decide Bot-ness through `is_bot`. No delimiter is ever cut out of a row, so no byte of a login can be read as a field boundary or forge the account type. Empty output slurps to an empty array (no approval); a row that is not JSON is a jq error and fails the lookup rather than reading as no approval.

REST content `+1` is the 👍 reaction. The 👀 `eyes` reaction (REST content `eyes`) is Codex's "still running" signal on the PR object — never treat it as approval (the `+1` filter already excludes it).

### APPROVED review (`review-approved`)

Read the PR's `latestReviews` connection. GitHub keeps one entry per author: that author's latest submitted review, never a pending one. Approval fires when some entry has `state` `APPROVED` and its author passes the module's `reviewer_is_approver` (kind `review-approved`) and `reviewer_matches_filter` predicates.

```bash
gh api graphql --paginate \
  -f owner="OWNER" \
  -f repo="REPO" \
  -F pr=123 \
  -f query='
query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      latestReviews(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes { state author { login __typename } }
      }
    }
  }
}' \
  --jq '.data.repository.pullRequest.latestReviews.nodes[] | {state, login: .author.login, type: .author.__typename} | tojson'
```

Because an author holds one entry, a later `COMMENTED`, `CHANGES_REQUESTED`, or `DISMISSED` review from the same approver supersedes its earlier `APPROVED`, which then never counts. Never rebuild an approver's latest review from the `reviews` history (see [Fetch Reviews](#fetch-reviews)): a bounded page of that history can hold neither the approval nor the review that superseded it, so a verdict rebuilt from it would depend on how many reviews the PR has.

`first: 100` is a page size, not a bound. `gh api graphql --paginate` passes each page's `pageInfo.endCursor` back as `$endCursor` and walks until `hasNextPage` is false, so every entry is read however many distinct reviewers the PR has. `gh` follows only the first `pageInfo` in a response, so the query holds exactly one paginated connection. The `gh --jq` filter is transport only, as for the 👍 rows: it emits one `tojson`-encoded `{state, login, type}` object per entry on every page and makes no identity decision. Slurp every row from every page into one array (`jq -s`) and decide approval once over the whole array. A successful walk of an empty connection slurps to an empty array (no approval). A failed page, a response carrying GraphQL errors, or a null or missing `latestReviews` connection fails the read; never default it to empty or read it as not-approved.

Codex never files an `APPROVED` review. When the reviewer's `APPROVED` capability is unavailable or not opted into, this kind never fires and the loop ends through the watch window instead.
