# GitHub Sub-Issue GraphQL Reference

Use these operations for managing GitHub native sub-issues from scripts such as
`${CLAUDE_PLUGIN_ROOT}/skills/prd-to-issues/scripts/subissue-ops.sh`. No agent reads it at runtime: the prd-to-issues skill runs every sub-issue operation through that script.

Sub-issues are a distinct feature from issue dependencies (the "blocked by" relationship).
The two share no input fields and must not be conflated — see the field-name warning in
[addSubIssue](#addsubissue) below.

## Contents

- [Feature Header Requirement](#feature-header-requirement) — mandatory request header on every call
- [Node ID Resolution](#node-id-resolution) — issue number → GraphQL node id
- [addSubIssue](#addsubissue) — mutation to attach a child issue to a parent
- [removeSubIssue](#removesubissue) — mutation to detach a child issue from a parent
- [Read: subIssues connection](#read-subissues-connection) — list children of an issue
- [Read: parent field](#read-parent-field) — navigate from child to parent
- [Status and CLI notes](#status-and-cli-notes) — GA date, gh CLI gap

## Feature Header Requirement

Sub-issues are a gated GraphQL feature. Every sub-issue GraphQL call **must** include the
header `GraphQL-Features: sub_issues`. Without it the API returns 404 or rejects the
operation silently.

Pass it via the `-H` flag on every `gh api graphql` invocation:

```bash
gh api graphql -H "GraphQL-Features: sub_issues" -f query='...'
```

This header requirement applies to all four operations in this document (mutations and
queries alike).

## Node ID Resolution

GitHub GraphQL operations require **node ids** (opaque base64 strings such as `I_kwDO...`),
not the human-readable issue number. Resolve a number to a node id before calling any
sub-issue mutation.

**Via `gh issue view`:**

```bash
gh issue view 123 --json id --jq .id
```

**Via GraphQL (useful when batching):**

```bash
gh api graphql \
  -H "GraphQL-Features: sub_issues" \
  -f owner="OWNER" \
  -f repo="REPO" \
  -F number=123 \
  -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) { id }
  }
}'  --jq '.data.repository.issue.id'
```

Resolve both the parent and the child node ids before calling `addSubIssue`.

## addSubIssue

Attaches an existing issue as a child of another existing issue.

```bash
gh api graphql \
  -H "GraphQL-Features: sub_issues" \
  -f parentId="PARENT_NODE_ID" \
  -f childId="CHILD_NODE_ID" \
  -f query='
mutation($parentId: ID!, $childId: ID!) {
  addSubIssue(input: { issueId: $parentId, subIssueId: $childId }) {
    issue    { id number title }
    subIssue { id number title }
  }
}'
```

**Input fields:**

| Field | Type | Description |
|-------|------|-------------|
| `issueId` | `ID!` | Node id of the **parent** issue |
| `subIssueId` | `ID!` | Node id of the **child** issue |

**Field-name warning — NOT the dependency API.** The issue dependency (blocked-by)
mutation uses `blockingIssueId` and `blockedIssueId`. `addSubIssue` uses `issueId` +
`subIssueId`. These are different APIs, different mutations, different fields. Passing a
`blockingIssueId` to `addSubIssue` will produce an unknown-field error; conversely, using
`issueId`/`subIssueId` against the dependency mutation is equally wrong. Never conflate
them.

## removeSubIssue

Detaches a child issue from its parent. Input fields are identical to `addSubIssue`.

```bash
gh api graphql \
  -H "GraphQL-Features: sub_issues" \
  -f parentId="PARENT_NODE_ID" \
  -f childId="CHILD_NODE_ID" \
  -f query='
mutation($parentId: ID!, $childId: ID!) {
  removeSubIssue(input: { issueId: $parentId, subIssueId: $childId }) {
    issue    { id number title }
    subIssue { id number title }
  }
}'
```

## Read: subIssues connection

Returns the direct children of an issue. Paginate via `pageInfo` when a parent may have
more children than the page size.

```bash
gh api graphql \
  -H "GraphQL-Features: sub_issues" \
  -f owner="OWNER" \
  -f repo="REPO" \
  -F number=123 \
  -f query='
query($owner: String!, $repo: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      subIssues(first: 50, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          number
          title
          state
        }
      }
    }
  }
}'
```

Paginate by re-issuing with `-F after="CURSOR"` using `endCursor` while `hasNextPage` is
`true`. Omit `-F after` on the first page.

## Read: parent field

Navigates from a child issue to its parent. A child has at most one parent; the field is
`null` when the issue has no parent.

```bash
gh api graphql \
  -H "GraphQL-Features: sub_issues" \
  -f owner="OWNER" \
  -f repo="REPO" \
  -F number=456 \
  -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      parent { id number title }
    }
  }
}'
```

## Status and CLI notes

**GA status.** GitHub native sub-issues reached general availability in 2025
(announced in the GitHub Changelog and GitHub Community discussions). The
`GraphQL-Features: sub_issues` header remains required even after GA because the feature
is gated at the API layer.

**No first-class `gh` CLI command.** The `gh` CLI has no `gh issue sub-issue` or
equivalent subcommand as of 2026 (tracked in upstream issue
[cli/cli#12258](https://github.com/cli/cli/issues/12258)). All sub-issue operations must
go through `gh api graphql` with the feature header as shown in this document.
