# tests/merge-approved

Home of the suite `tools/test_merge_approved.sh`, the offline behavioral runner for
`plugin/skills/github-review-loop/scripts/merge-approved.sh`, the opt-in merge
script of the post-PR watch (ADR-0044). The script's header holds its full
contract; this file describes how the suite tests it.

The suite holds no fixture files. Every GraphQL body is built inline from one
clean base body, a merge-ready PR, with one `jq` edit, so each case differs from
that PR in one place. The base PR is open, not a draft, on head `aaaa…`, with
`mergeStateStatus` `CLEAN`, a `SUCCESS` rollup, one `COMMENTED` latest review
from a Bot, an empty THUMBS_UP group and one resolved thread. Every
latestReviews node a case writes carries a `state`.

## Fake gh

A fake `gh` first on `PATH` stands in for the real one. Scratch space comes from
`make_scratch_dir` in `tools/lib/scratch.sh` and is removed on exit. Each case
has its own folder:

- `read-<n>.json` is the body of the n-th `gh api graphql` read, and
  `read-<n>.status` its exit code (default 0). A missing `read-<n>.json` falls
  back to `read-1.json`.
- `merge-<n>.status` is the exit code of the n-th `gh pr merge` (default 0).
- `calls.log` gets one line per call:
  `READ <n> head=<h> rollup=<r> reviews=<states>` (the comma-joined state of
  every latestReviews node, or `NONE`),
  `MERGE <n> after_head=<h> after_rollup=<r> after_reviews=<states> argv=<argv>`
  (with the head, rollup and review states of the last read before it), or
  `OTHER argv=<argv>` for any other call.

The fake writes a line to stderr on each call, and the merge call also prints to
stdout. A case asserts the script's one stdout line, its exit code, an empty
stderr, and its counts of reads and merge calls. So no `gh` output can leak
through.

## Cases

- **Setting.** Unset or empty `HIVEMIND_AUTO_MERGE` prints `MERGE=off`. Any
  value other than `merge`, `squash` or `rebase` prints
  `MERGE=skipped:bad-setting`. Both make zero `gh` calls.
- **Arguments.** A wrong count, a bad owner, repo or PR number, an empty self
  login and the retired filter value each print `MERGE_ERROR=<reason>`, exit 1,
  with zero `gh` calls. Arguments are checked before the setting. An empty
  filter means `automated`.
- **Gates in order.** `not-open` (CLOSED, MERGED), `draft`, `no-approval`,
  `open-threads`, `no-checks`, `checks-pending` (PENDING, EXPECTED) and
  `checks-failed` (FAILURE, ERROR). Pairs of failing gates prove the order.
- **Approval.** Approval is keyed on review state. Every latest review, of any
  author, must be `APPROVED`, `COMMENTED` or `DISMISSED`, and an in-scope Bot
  must have an `APPROVED` or `COMMENTED` latest review or a THUMBS_UP. These
  count: a Bot `APPROVED` or `COMMENTED` review, a `[bot]` login typed `User`, a
  Bot with the self login, a THUMBS_UP from a Bot, a Bot `DISMISSED` review
  with a Bot THUMBS_UP, `github-actions[bot]` when `HIVEMIND_PR_REVIEWERS`
  names it, and a `<login>` filter that matches. These do not: a human review,
  a null author, a self `User` review, `github-actions[bot]` when not named, a
  human THUMBS_UP, a Bot HEART, a `<login>` filter naming another bot, a human
  review under the `all` filter, and a Bot `DISMISSED` review alone. A Bot
  `CHANGES_REQUESTED` review prints `skipped:no-approval` with no merge call,
  with or without the admin setting and with or without a Bot THUMBS_UP. A
  human `CHANGES_REQUESTED`, a null-author `CHANGES_REQUESTED`, a `PENDING`
  review and an unknown state each block a Bot `APPROVED` review the same way.
- **Threads.** A thread is settled when it is resolved or its last comment is the
  self `User`. It is open when its last comment is a Bot with the self login, a
  human or a null author, when `isResolved` is null, or when it has no comments.
- **Merge.** For each method, the exact command is
  `pr merge 5 --repo o/r --<method> --match-head-commit <head>`. With the admin
  setting set, the plain merge still goes first.
- **Reads.** `hasNextPage: true` on latestReviews, a THUMBS_UP group or
  reviewThreads prints `read-incomplete`. A HEART group's next page is ignored.
  A gh exit code that is not 0 prints `graphql-read-failed`. The envelope and
  shape tokens come out as `graphql-<token>` and `shape-<token>`. A wrong type,
  a review `state` that is missing or not a string, an unknown PR state, a
  non-hex head, a head that does not match the last commit, or no commit prints
  `malformed-read`. Each of these makes no merge call.
- **Refused merge.** The plain merge exits 1 and a second read decides:
  - a moved head prints `wait:head-moved`;
  - `DIRTY` prints `skipped:conflicts`;
  - `BLOCKED` or `BEHIND` with the admin setting unset or empty prints
    `skipped:blocked`, since an empty value is off;
  - with the setting set to a non-empty value, the `--admin` rerun prints
    `merged-admin`;
  - with the setting and a re-read that fails any gate (closed, draft, no
    approval, an open thread, or a rollup that is not `SUCCESS`), that gate's
    line prints and no `--admin` call is made. A re-read showing a new
    `CHANGES_REQUESTED`, from the Bot or a human, prints `skipped:no-approval`
    this way;
  - an `--admin` refusal, or any other state, prints `skipped:refused`;
  - a failed or incomplete re-read prints `MERGE_ERROR`.

## Properties over every case

After the cases run, the suite scans every `calls.log`:

- no merge call carries `--auto` or `--delete-branch`;
- every merge call carries `--match-head-commit` equal to the head of the read
  before it;
- no merge call follows a read whose rollup was not `SUCCESS`;
- no merge call follows a read holding a review state outside `APPROVED`,
  `COMMENTED` or `DISMISSED`;
- `--admin` appears only as the second merge call of a case that set the admin
  setting, after a refused plain merge on the same head with a `SUCCESS` rollup.

The scan fails if it finds no merge call at all, so it can never pass empty.
