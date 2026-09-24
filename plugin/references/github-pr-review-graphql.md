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
- [Author Filtering](#author-filtering) — rules for scoping feedback to specific reviewer identities
- [Codex Approval Detection](#codex-approval-detection) — paginated 👍 reaction lookup that signals Codex approval

## Shell and Parsing Rules

Use `gh --jq` only for inline value extraction. No ad-hoc standalone `jq`, `python3`, `python`, `node`, or PowerShell. No `/tmp/` for data processing. If `gh --jq` cannot produce the required value, return `blocked`.

Sanctioned exception — canonical fix-history classification: the github-reviewer agent captures the raw `gh api graphql` JSON (threads/comments/reviews/top-level, with the contract fields `isResolved`, `comments.totalCount`, comment `databaseId`, `author.login`, `body`, top-level/review `url`, review `state`) and pipes it through the shared filter FILE `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/fix-history-classify.jq` via `jq -f`. This is a pure offline function over already-fetched JSON and is the single source of truth for the skip/order/overflow predicate; it is NOT the ad-hoc inline `jq` munging this rule prohibits.

## Pagination Requirement

Page all connections via `-F after="CURSOR"` using `endCursor` from `pageInfo`. Omit `-F after` on first page. Nested connections (e.g., thread comments) require per-item queries with the item's `id`. This requirement governs the reviewer's deep body-level fetch (reviews, review threads, thread comments, top-level comments) and the Codex approval reactions lookup — NOT the `github-review-loop` thin poll, which is exempt by design: it reads scalar `totalCount`s only and walks no connections.

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
          author { login }
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
              author { login }
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
      | select(.author.login != $ENV.SELF_LOGIN)
      | "THREAD=\($thread.id) COMMENT=\(.id) AUTHOR=\(.author.login) PATH=\($thread.path) LINE=\($thread.line // "") URL=\(.url)"'
# SELF_LOGIN is resolved at runtime via: gh api user --jq .login
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
          author { login }
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
          author { login }
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
        | select(.author.login != $ENV.SELF_LOGIN)
        | "COMMENT=\(.id) AUTHOR=\(.author.login) URL=\(.url)"'
# SELF_LOGIN is resolved at runtime via: gh api user --jq .login
```

## Detection Filtering

All queries must apply both filters before yielding results as actionable feedback. Silently skip items that fail either filter.

1. **Exclude empty body:** `select(.body != null and (.body | gsub("[[:space:]]+"; "") != ""))`
2. **Exclude self-authored:** `select(.author.login != $ENV.SELF_LOGIN)` — resolve once per poll: `export SELF_LOGIN=$(gh api user --jq .login)`

The Fetch Review Threads (unresolved summary output) and Fetch Top-Level PR Comments templates apply both filters inline. The Fetch Reviews and Fetch Thread Comments (Paginated) templates return raw nodes — consuming agents must apply both filters to their results before yielding as actionable feedback. For Fetch Reviews, also filter to `state` values `CHANGES_REQUESTED` or `COMMENTED`.

An `APPROVED` review state is NOT how Codex signals approval — Codex never files an `APPROVED` review. Codex approval is a 👍 reaction on the PR object (see [Codex Approval Detection](#codex-approval-detection)).

## Reply to Review Thread

```bash
gh api graphql \
  -f threadId="THREAD_ID" \
  -f body="Fixed in COMMIT_SHA. Summary: ..." \
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

Maps each feedback surface to the mutation(s) used to mark a fixed surface handled. The mapping is closed-by-construction — no runtime fallback, no `addComment` mutation, no `Addresses: <url>` body convention. `reply-resolve.sh` remains the THREAD-ONLY mutation path (reply + conditional resolve); the non-thread `toplevel`/`review` surfaces are marked handled by a self-authored `EYES` reaction (see [Reaction Marker](#reaction-marker)), NOT by `reply-resolve.sh`.

| Surface | Mutation(s) | Notes |
|---------|-------------|-------|
| `thread` | `addPullRequestReviewThreadReply` then (conditional) `resolveReviewThread` | Reply targets the thread node id (`PRRT_...`). Resolve fires only when the thread is unresolved after reply. Executed by `reply-resolve.sh`. |
| `toplevel` | `addReaction` (`EYES`) on the IssueComment node | A self-authored `EYES` (👀) reaction is added to the reviewer's top-level IssueComment node as the handled marker. NOT reply-targeted, NOT thread-resolvable (top-level PR comments have no thread node). `reply-resolve.sh` is NOT invoked for this surface — it is a silent no-op for `toplevel`; posting `addPullRequestReviewThreadReply` against a non-thread node fails, because a top-level IssueComment has no review-thread node to target. |
| `review` | `addReaction` (`EYES`) on the PullRequestReview node | Same as `toplevel`: a self-authored `EYES` (👀) reaction is added to the reviewer's PullRequestReview summary node as the handled marker. Review-summary nodes have no thread node, so they are NOT reply-targeted and NOT thread-resolvable. `reply-resolve.sh` is NOT invoked — its `review` silent no-op is UNCHANGED. |
| unmapped / unknown | fail-closed | Any surface value not in the table above causes the script to exit with an error rather than fall through silently. |

Thread replies carry only the fix summary: no `Addresses: <url>` back-reference line is appended on the emit path. The handled marker for non-thread surfaces is the `EYES` reaction described below; ZERO new PR comments are posted.

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

The `EYES` marker here is OUR self-authored reaction on a per-COMMENT / per-REVIEW node. It is a DISJOINT subject from the 👀 reaction described in [Codex Approval Detection](#codex-approval-detection), which is Codex's reaction on the PR OBJECT meaning "still running". The two share an emoji but never the same subject:

- **This marker:** `EYES` reaction on an `IssueComment` / `PullRequestReview` node, authored by our viewer, detected via `reactionGroups { content viewerHasReacted }` on that node → surface handled.
- **Codex "still running" (existing):** `eyes` reaction on the PR object, authored by Codex, detected via the REST reactions endpoint → never approval.

A reader must not conflate them: per-node viewer-scoped handled marker vs PR-object Codex-authored progress signal.

## Author Filtering

When `reviewer_filter` is `codex-only`, include only comments from the Codex reviewer identity. The Codex reviewer's canonical login base is `chatgpt-codex-connector`. Inside `reactions` nodes the login carries a `[bot]` suffix (`chatgpt-codex-connector[bot]`); match by stripping a trailing `[bot]` and comparing equal to `chatgpt-codex-connector`. If identity is unclear, ask the user before processing.

## Codex Approval Detection

Codex signals approval via a 👍 reaction on the PR object (not an `APPROVED` review). Detect it with the paginated REST reactions endpoint so the bot's reaction is found even when a PR has more than one page of reactions:

```bash
gh api --paginate "repos/OWNER/REPO/issues/PR_NUMBER/reactions" \
  --jq '.[] | select(.content == "+1") | ((.user.login // "") | sub("\\[bot\\]$"; "")) | select(. == "chatgpt-codex-connector")'
```

REST content `+1` is the 👍 reaction. A reactor matches Codex when its login, with a trailing `[bot]` stripped, equals `chatgpt-codex-connector`. Codex approval is terminal for the github-reviewer ONLY when no unresolved non-self actionable items remain. The 👀 `eyes` reaction (REST content `eyes`) means "still running" — never treat it as approval (the `+1` filter already excludes it).
