# GitHub PR Review GraphQL Reference

Script and maintainer reference for the review-loop scripts under `plugin/skills/github-review-loop/scripts/`; no agent reads it at runtime.

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
- [Reaction Marker](#reaction-marker) — self-authored `EYES` reaction that marks a fixed, deferred or noise non-thread surface handled while it is unchanged since marked
- [Author Filtering](#author-filtering) — `reviewer_filter` modes, the Bot-type + login identity rule for scoping feedback to reviewer identities, and the User-type + login self rule
- [Reviewer Approval Detection](#reviewer-approval-detection) — the per-PR Automated Reviewer set and the three approval signals (paginated PR 👍 reaction lookup, paginated per-author `latestReviews` lookup for `APPROVED` and comment-free `COMMENTED`)

## Shell and Parsing Rules

Use `gh --jq` only for inline value extraction. No ad-hoc standalone `jq`, `python3`, `python`, `node`, or PowerShell. No `/tmp/` for data processing. If `gh --jq` cannot produce the required value, return `blocked`.

Sanctioned exception — canonical fix-history classification: `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/fetch-normalize.sh` (which the github-reviewer agent calls) captures the raw `gh api graphql` JSON (threads/comments/reviews/top-level, with the contract fields `isResolved`, `comments.totalCount`, comment `databaseId`, `author.login`, `author.__typename`, `body`, top-level/review `url`, review `state`) and pipes it through the shared filter FILE `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/fix-history-classify.jq` via `jq -L <scripts dir> -f`. The script supplies the `-L` module search path because the classifier `include`s the reviewer identity module `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reviewer-identity.jq`. This is a pure offline function over already-fetched JSON and is the single source of truth for the skip/order/overflow predicate; it is NOT the ad-hoc inline `jq` munging this rule prohibits. The same exception covers evaluating that module's identity predicates over rows a `gh --jq` transport filter emitted, and over rows extracted locally from raw GraphQL pages that already passed the response check below (see [Reviewer Approval Detection](#reviewer-approval-detection)).

Every review-loop script checks each `gh api graphql` response, and each page of a paginated walk, through `${CLAUDE_PLUGIN_ROOT}/skills/_shared/graphql-response.sh` before reading any field. `hivemind_graphql_response_check` takes one response; `hivemind_graphql_pages_check` takes the raw `gh api graphql --paginate` stream (no `--jq`, no `--slurp`; the pages arrive concatenated) and parses it with `jq -s`. Acceptance rule: `errors` is absent, null, or `[]` AND `data` is an object; anything else fails the read. The exit code is not enough: `gh` exits 0, and still runs `--jq`, for a message-less error object, a non-array `errors`, and an `errors` array holding elements that are neither objects nor strings, so a read that trusts the exit code or a `--jq` filter takes an errored response for data. A message-less error object therefore fails the read even though `gh` exits 0. REST is excluded: `gh` turns every HTTP status above 299 into a non-zero exit and REST has no 200-with-errors shape, so the exit code is sufficient there.

The three review-activity skeleton readers (fetch-normalize, prefilter, and the change-detect poll snapshot) then pass the body through `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-surface-shape.sh` (`hivemind_review_surface_shape_check`), which is type-strict per skeleton position: a non-object repository or pullRequest, or an absent, null, or wrong-typed comments, reviews, or reviewThreads connection, `nodes` list, thread element, or per-thread comments connection fails the read; a valid-but-empty PR passes. Mutations (reaction marker, thread reply, thread resolve) succeed only when the response carries the object they requested (reaction content, reply comment id, thread `isResolved` true); no response text is ever read as success.

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

An `APPROVED` review is never actionable feedback, and these filters do not detect approval. Approval is the same three signals for every Automated Reviewer: its latest review is `APPROVED`, its latest review is `COMMENTED` with no inline review comments, or it left a 👍 on the PR object. All are scoped by the active `reviewer_filter` (see [Reviewer Approval Detection](#reviewer-approval-detection)).

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

Maps each feedback surface to the mutation(s) used to mark a fixed, deferred or noise surface handled. Only `toplevel` and `review` take a noise mark; a noise thread gets no reply. The mapping is closed-by-construction — no runtime fallback, no `addComment` mutation, no `Addresses: <url>` body convention. `reply-resolve.sh` remains the THREAD-ONLY mutation path (reply + conditional resolve); the non-thread `toplevel`/`review` surfaces are marked handled by a self-authored `EYES` reaction (see [Reaction Marker](#reaction-marker)), NOT by `reply-resolve.sh`.

| Surface | Mutation(s) | Notes |
|---------|-------------|-------|
| `thread` | `addPullRequestReviewThreadReply` then (conditional) `resolveReviewThread` | Reply targets the thread node id (`PRRT_...`) with one of two sanctioned bodies: `Fixed in <SHA>. <summary>.` (fix) or `<!-- hivemind-defer-v1 --> Deferred to <TRACKED_HOME>. <summary>.` (defer, sentinel-first — the sentinel is the machine marker, not the prose). Resolve fires only when the thread is unresolved after reply. Executed by `reply-resolve.sh`. |
| `toplevel` | `addReaction` (`EYES`) on the IssueComment node, after `removeReaction` (`EYES`) when our mark is already there | A self-authored `EYES` (👀) reaction is added to the reviewer's top-level IssueComment node as the handled marker. NOT reply-targeted, NOT thread-resolvable (top-level PR comments have no thread node). `reply-resolve.sh` is NOT invoked for this surface — it is a silent no-op for `toplevel`; posting `addPullRequestReviewThreadReply` against a non-thread node fails, because a top-level IssueComment has no review-thread node to target. |
| `review` | `addReaction` (`EYES`) on the PullRequestReview node, after `removeReaction` (`EYES`) when our mark is already there | Same as `toplevel`: a self-authored `EYES` (👀) reaction is added to the reviewer's PullRequestReview summary node as the handled marker. Review-summary nodes have no thread node, so they are NOT reply-targeted and NOT thread-resolvable. `reply-resolve.sh` is NOT invoked — its `review` silent no-op is UNCHANGED. |
| unmapped / unknown | fail-closed | Any surface value not in the table above causes the script to exit with an error rather than fall through silently. |

Thread replies carry only the fix or defer summary: no `Addresses: <url>` back-reference line is appended on the emit path. The handled marker for non-thread surfaces is the `EYES` reaction described below; ZERO new PR comments are posted.

## Reaction Marker

Non-thread reviewer surfaces (`toplevel` = IssueComment, `review` = PullRequestReview summary) carry `thread_id: null` and have no thread node to reply to or resolve. A committed fix, a deferral, or a noise skip of such a surface is recorded handled by adding a self-authored `EYES` (👀) reaction to the reviewer's own comment/review node. The mark counts only while the node is unchanged since marked (see [Harvest](#harvest-detect-handled)). The rule is the same for every reviewer the active `reviewer_filter` admits; no reviewer gets its own case. Both `IssueComment` and `PullRequestReview` implement `Reactable`, so the same mutation and harvest fragment apply to both.

### Emit (mark handled)

`$nodeId` is the reviewer's IssueComment or PullRequestReview GraphQL node id (the `id` selected in [Fetch Top-Level PR Comments](#fetch-top-level-pr-comments) / [Fetch Reviews](#fetch-reviews)).

```bash
gh api graphql \
  -f nodeId="NODE_ID" \
  -f query='
mutation($nodeId: ID!) {
  addReaction(input: { subjectId: $nodeId, content: EYES }) {
    reaction { content }
    subject { ... on IssueComment { lastEditedAt } ... on PullRequestReview { lastEditedAt } }
  }
}'
```

`EYES` is the single named marker constant — a member of the `ReactionContent` enum. It is chosen because it reads semantically as "seen/handled".

`react-marker.sh --edited-at "$last_edited_at" NODE_ID SURFACE CANDIDATE_URL` sends the mutation. Its success proof is the requested `reaction` object in the response: gh exits 0, the shared GraphQL response check passes, `.data.addReaction.reaction.content` is `EYES`, and `.data.addReaction.subject` holds a `lastEditedAt` key. Before the mutation it proves the node belongs to the current branch's open PR, in one `node(id:)` lookup that also selects `author { login __typename }`, `reactionGroups { content viewerHasReacted }` and `lastEditedAt`.

**Edit gate.** `--edited-at` is required on `toplevel` and `review`, in fix and noise mode. Its value is the version of the node the reviewer read: its `lastEditedAt` as read, a time matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`, or `never`. The script checks it before any git or gh call. The `thread` surface ignores it. After the PR binding and the noise author check, and before the re-mark removal, a node whose `lastEditedAt` (null read as `never`, a missing key matching nothing) differs from the value is refused with `edited-since-read` and no mutation. When the `addReaction` response's `subject.lastEditedAt` differs from the value, an edit landed between the lookup and the mark: the script removes the fresh mark with the removal below and its proof, then exits `edited-since-read`. A removal without proof is `react-failed`. Values compare as exact strings. Residual: GitHub reports `lastEditedAt` to the second, so a second edit in the same second as the read version's edit time keeps an equal value and goes undetected.

**Re-mark refresh.** A re-mark leaves exactly one fresh mark, so its `createdAt` is later than any edit before it. When the lookup shows our `EYES` already on the node, and the edit gate passes, the script first removes it (the edit gate's undo of a fresh mark sends the same removal):

```bash
gh api graphql \
  -f nodeId="NODE_ID" \
  -f query='
mutation($nodeId: ID!) {
  removeReaction(input: { subjectId: $nodeId, content: EYES }) {
    reactionGroups { content viewerHasReacted }
  }
}'
```

The removal's proof: gh exits 0, the response check passes, and `.data.removeReaction.reactionGroups` is an array with no `EYES` group whose `viewerHasReacted` is true. Without that proof the script fails `react-failed` and sends no `addReaction`. A duplicate `addReaction` is never relied on: it would keep the old reaction and its old `createdAt`.

**Noise mode.** `react-marker.sh --noise "$reviewer_filter" --edited-at "$last_edited_at" NODE_ID SURFACE CANDIDATE_URL` marks a comment or review skipped as noise. After the PR binding, the node's GitHub-reported author must pass `is_bot` and `reviewer_matches_filter` against the `--noise` value, both from `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reviewer-identity.jq`; the filter is judged against the per-PR Automated Reviewer set (see [Reviewer Approval Detection](#reviewer-approval-detection)). A human, a Bot outside the filter, or a null author is refused with no mutation sent. The check reads only the author, never the body or URL. Fix mode makes no author check, so a human's fixed comment can be marked.

New reason tokens: `missing-value-for-noise` (`--noise` with no value), `missing-identity-module` (noise mode without `reviewer-identity.jq`, before any gh call), `noise-author-refused`, `missing-edited-at` (no `--edited-at` on `toplevel` or `review`), `missing-value-for-edited-at` (`--edited-at` with no value), `invalid-edited-at` (any other value shape), `edited-since-read` (the node changed after the read version, before or during the mark). A failed fixed or deferred mark blocks the reviewer with `marker-write-failed`. A failed noise mark leaves the candidate unmarked and never blocks.

### Harvest (detect handled)

Add this fragment to the IssueComment node selection in [Fetch Top-Level PR Comments](#fetch-top-level-pr-comments) and to the PullRequestReview node selection in [Fetch Reviews](#fetch-reviews):

```graphql
reactionGroups { content viewerHasReacted } lastEditedAt reactions(content: EYES, last: 20) { nodes { content createdAt user { login __typename } } }
```

`prefilter.sh` and `fetch-normalize.sh` append it to both selections. A surface is handled through our mark only while it is unchanged since marked. All of these hold:

- `reactionGroups` contains an entry with `content == "EYES"` and `viewerHasReacted == true`;
- the node has a `lastEditedAt` key; and
- `lastEditedAt` is null (never edited), or strictly earlier than the latest `createdAt` among `reactions.nodes[]` with `content` `EYES` whose `user` is self (`is_self`).

Both times must match `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$` and compare as strings. Equal times are not handled. A missing `lastEditedAt` key, no self `EYES` reaction node, or a malformed time is not handled; the surface stays actionable. So a reviewer that edits a marked comment in place, adding findings to an old body, makes it actionable again. The `reactions` page holds the last 20 `EYES` reactions; a self reaction outside it reads as absent, which fails toward actionable. `fix-history-classify.jq` owns the rule.

`viewerHasReacted` is scoped to the authenticated `gh` viewer (OUR identity), and the mark time is read only from a self reaction node. So a human or a bot reacting with the same 👀 emoji from ANOTHER account never false-positives our handled signal and cannot refresh our mark past an edit.

The legacy `Addresses: <url>` harvest and the thread `Fixed in` and defer dispositions are unchanged; the edit gate covers only the `EYES` mark on `toplevel` and `review`. No reviewer-product summary signal exists: a summary comment a reviewer edits in place re-arms under this one rule (ADR-0043).

### Disambiguation — two different `EYES` subjects

The `EYES` marker here is OUR self-authored reaction on a per-COMMENT / per-REVIEW node. It is a DISJOINT subject from any 👀 (`eyes`) reaction a reviewer bot leaves on the PR OBJECT. The two share an emoji but never the same subject:

- **This marker:** `EYES` reaction on an `IssueComment` / `PullRequestReview` node, authored by our viewer, detected via `reactionGroups { content viewerHasReacted }` and the self reaction's `createdAt` on that node → surface handled while unchanged since marked.
- **A reviewer's `eyes` on the PR object:** authored by a reviewer bot, detected via the REST reactions endpoint or the PR-level `reactionGroups` evidence selection → never approval, and the approval lookup's `+1` filter excludes it. The 👀 is not read as a "still running" signal either (ADR-0043).

A reader must not conflate them: per-node viewer-scoped handled marker vs PR-object reviewer-authored reaction.

## Author Filtering

Agents read this section, so it lives in the installed plugin: `${CLAUDE_PLUGIN_ROOT}/references/github-pr-review-graphql.md` (Author Filtering). Self identity keys on the account-type field too, which is why every template above selects `author { login __typename }`.

## Reviewer Approval Detection

An automated reviewer's approval is the signal that lets a watched PR end cleanly. No reviewer product is named in code: one rule set covers every Automated Reviewer (ADR-0043, which supersedes the registry and per-reviewer approval kinds of ADR-0033). Products appear below only as examples.

### Automated Reviewer set

The set is per PR and judged on Bot accounts only, through the `is_bot` predicate in `${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/reviewer-identity.jq`. A Bot is in the set when any of these holds:

- it authored a review, or a review-thread comment, on the PR;
- it holds an entry in the PR's `latestReviews` connection;
- it left a 👍 (`THUMBS_UP`) reaction on the PR object.

`HIVEMIND_PR_REVIEWERS` names more Bot logins, comma- or space-separated, the `[bot]` suffix optional. It only adds to the set and never narrows it. Every listed login is still Bot-gated, so a human account with the same bare login never matches. It covers a bot that only posts plain PR comments. `github-actions[bot]` is in the set only when listed there, and is excluded otherwise even when it submits a review. The `codex-only` `reviewer_filter` mode is retired and rejected at the input gate; use `automated` or `<login>` mode.

The PR-level evidence for the set is two selections on `pullRequest`. In `fetch-normalize.sh`, `prefilter.sh` and `react-marker.sh` they are single reads, not paginated walks:

```graphql
latestReviews(first: 100) { nodes { author { login __typename } } }
reactionGroups { content reactors(first: 100) { nodes { __typename ... on Bot { login } ... on User { login } } } }
```

`reactionGroups` reactors are typed by GraphQL, so a Bot reactor arrives as `Bot`: verified live 2026-11-17, `chatgpt-codex-connector` on PR 583 returned typed `Bot`. A reactor that is neither a `Bot` nor a `User` selects no `login` and never enters the set. In those three scripts `first: 100` is a bound: they read no further page, and a missing evidence field reads as empty. On a PR with more than 100 review authors or 👍 reactors, a Bot whose only evidence lies past the bound is not in their set; the error only narrows the set, never trusting a wrong author. ADR-0043 (Consequences) records this known limit. The poll (`pr-change-detect-poll.sh`) is different: its `latestReviews` read is a paginated walk checked through `hivemind_graphql_pages_check` (see [Shell and Parsing Rules](#shell-and-parsing-rules)), and its 👍 reactors come from the paginated REST reactions endpoint.

### Approval signals

Approval counts only from an Automated Reviewer in scope under the active `reviewer_filter`, so a filtered-out reviewer never ends the loop it was filtered out of. Any one signal is a Reviewer Approval:

| Signal | Evidence |
|--------|----------|
| latest review `APPROVED` | the author's `latestReviews` entry has `state` `APPROVED` |
| latest review `COMMENTED`, no inline comments | the author's `latestReviews` entry has `state` `COMMENTED` and `comments.totalCount == 0` |
| 👍 on the PR object | a `+1` reaction on the PR from the Bot |

A 👍 from any Bot other than `github-actions[bot]` also makes that Bot an Automated Reviewer, so a clean-PR 👍 ends the watch with no review and no configuration. Review text is never read for approval. Approval never overrides open feedback: while unresolved non-self actionable items remain, the PR is not clean. A reviewer that posts no review and no 👍 leaves the watch to end through its idle window; the loop never requests a review.

### PR 👍 reaction

Read the paginated REST reactions endpoint so the approver's reaction is found even when the PR has more than one page of reactions. The `gh --jq` filter is transport only: it emits one JSON object `{login, type}` per `+1` reaction, carrying `user.type` verbatim, and makes no identity decision. REST reports a bot reactor typed `User`, so the transport never reads or rewrites `type`; the module's `is_bot` decides Bot-ness from the type or the reserved `[bot]` login suffix.

```bash
gh api --paginate "repos/OWNER/REPO/issues/PR_NUMBER/reactions" \
  --jq '.[] | select(.content == "+1") | {login: .user.login, type: .user.type} | tojson'
```

Each row is `tojson`-encoded because `gh` prints a string result raw and uncolored, one per line, while an object result may be colorized; the encoded row is plain JSON text whatever the output stream. The rows are JSON values, parsed by jq, never split: slurp every row from every page into one array (`jq -s`) and match them all at once through the module's approver and `reviewer_matches_filter` predicates, which decide Bot-ness through `is_bot`. No delimiter is ever cut out of a row, so no byte of a login can be read as a field boundary or forge the account type. Empty output slurps to an empty array (no approval); a row that is not JSON is a jq error and fails the lookup rather than reading as no approval.

REST content `+1` is the 👍 reaction. The 👀 `eyes` reaction (REST content `eyes`) is never approval (the `+1` filter already excludes it).

### Latest review (`APPROVED` or comment-free `COMMENTED`)

Read the PR's `latestReviews` connection. GitHub keeps one entry per author: that author's latest submitted review, never a pending one. Approval fires when some entry is `APPROVED`, or is `COMMENTED` with `comments.totalCount == 0`, and its author passes the module's approver and `reviewer_matches_filter` predicates. Verified live 2026-11-17: `latestReviews` returned a bot `COMMENTED` review with its `comments.totalCount` (PR 566).

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
        nodes { state author { login __typename } comments { totalCount } }
      }
    }
  }
}'
```

Because an author holds one entry, a later `CHANGES_REQUESTED` or `DISMISSED` review, or a `COMMENTED` review with inline comments, from the same approver supersedes its earlier approval, which then never counts. Never rebuild an approver's latest review from the `reviews` history (see [Fetch Reviews](#fetch-reviews)): a bounded page of that history can hold neither the approval nor the review that superseded it, so a verdict rebuilt from it would depend on how many reviews the PR has.

`first: 100` is a page size, not a bound. `gh api graphql --paginate` passes each page's `pageInfo.endCursor` back as `$endCursor` and walks until `hasNextPage` is false, so every entry is read however many distinct reviewers the PR has. `gh` follows only the first `pageInfo` in a response, so the query holds exactly one paginated connection. The walk carries no `--jq`: a `--jq` filter runs on an errored page and hides the failure. Capture the raw pages, check every page through `hivemind_graphql_pages_check` (see [Shell and Parsing Rules](#shell-and-parsing-rules)), then extract the rows locally with `jq -c '.data.repository.pullRequest.latestReviews.nodes[] | {state, login: .author.login, type: .author.__typename, comments: .comments.totalCount}'`: one `{state, login, type, comments}` object per entry on every page, no identity decision. Slurp every row from every page into one array (`jq -s`) and judge approval once over the whole array. A successful walk of an empty connection slurps to an empty array (no approval). A failed page, a response carrying GraphQL errors (including a message-less error object, on which `gh` exits 0), or a null or missing `latestReviews` connection fails the read; never default it to empty or read it as not-approved.
