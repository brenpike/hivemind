# tests/merge-approved

Home of the suite `tools/test_merge_approved.sh`, the offline behavioral runner for
`plugin/skills/github-review-loop/scripts/merge-approved.sh`, the opt-in merge
script of the post-PR watch (ADR-0044). The script's header holds its full
contract; this file describes how the suite tests it.

The suite holds no fixture files. Every GraphQL body is built inline from one
clean base body, a merge-ready PR, with one `jq` edit, so each case differs from
that PR in one place. The base PR is open, not a draft, on head `aaaa…`, with
`mergeStateStatus` `CLEAN`, base `main` at `1111…`, a `SUCCESS` rollup, one
`COMMENTED` latest review from a Bot, an empty THUMBS_UP group, one resolved
thread and one changed file, `README.md`, so the record gate is off. Every
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
  `READ <n> state=<s> head=<h> rollup=<r> reviews=<states>` (the PR state, and
  the comma-joined state of every latestReviews node, or `NONE`),
  `MERGE <n> after_head=<h> after_rollup=<r> after_reviews=<states> argv=<argv>`
  (with the head, rollup and review states of the last read before it), or
  `OTHER argv=<argv>` for any other call.

A fake `git` first on `PATH` runs the real git and appends
`GIT argv=<argv>` to `calls.log` per call. On `fetch` it adds a
`url.<server>.insteadOf=<the remote's URL>` setting, so the remote's configured
URL is fetched from a local bare fixture server. `FIXTURE_GIT_FAIL=<subcommand>`
makes that git subcommand exit 1. `HOME` points into the scratch space and
`GIT_CONFIG_NOSYSTEM` is set, so no user or system git config reaches a case.

The fake writes a line to stderr on each call, and the merge call also prints to
stdout. A case asserts the script's one stdout line, its exit code, an empty
stderr, and its counts of reads and merge calls. So no `gh` output can leak
through. The stdout line is also kept in the case folder for the property scan.

A merge call that exits 0 is followed by the confirm read. A case that expects
`merged` or `merged-admin` serves it as one more read, the base body with state
`MERGED`, and counts it: a plain merge makes 2 reads and 1 merge call, an
`--admin` merge 3 reads and 2 merge calls.

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
- **Confirm read.** The plain merge exits 0 and the confirm read decides. A
  confirm read showing `OPEN` or `CLOSED` prints `wait:merge-pending` with no
  further merge call, with the admin setting set too. A failed confirm read
  prints `MERGE_ERROR=graphql-read-failed`, an incomplete one `read-incomplete`
  and a malformed one `malformed-read`, each exit 1, even when it shows
  `MERGED`.
- **Reads.** `hasNextPage: true` on latestReviews, a THUMBS_UP group or
  reviewThreads prints `read-incomplete`. A HEART group's next page is ignored.
  A gh exit code that is not 0 prints `graphql-read-failed`. The envelope and
  shape tokens come out as `graphql-<token>` and `shape-<token>`. A wrong type,
  a review `state` that is missing or not a string, an unknown PR state, a
  non-hex head or base oid, a base name that is empty or not a string, a lost
  `files` connection or page flag, a file path or changeType that is not a
  string, a head that does not match the last commit, or no commit prints
  `malformed-read`. Each of these makes no merge call.
- **Refused merge.** The plain merge exits 1 and a second read decides. A
  second read showing `UNKNOWN` is read again, at most 2 more times, and the
  last read decides; the suite exports `HIVEMIND_AUTO_MERGE_REREAD_DELAY=0`, so
  no case waits:
  - a moved head on any re-read prints `wait:head-moved`, with no further read;
  - `DIRTY` prints `skipped:conflicts`;
  - `BLOCKED` or `BEHIND` with the admin setting unset or empty prints
    `skipped:blocked`, since an empty value is off;
  - with the setting set to a non-empty value, the `--admin` rerun that exits
    0 prints `merged-admin` when its confirm read shows `MERGED`, and
    `wait:merge-pending` when it shows `OPEN`;
  - with the setting and a re-read that fails any gate (closed, draft, no
    approval, an open thread, or a rollup that is not `SUCCESS`), that gate's
    line prints and no `--admin` call is made. A re-read showing a new
    `CHANGES_REQUESTED`, from the Bot or a human, prints `skipped:no-approval`
    this way;
  - an `--admin` refusal prints `skipped:admin-refused` (2 reads, 2 merge
    calls);
  - `UNKNOWN` on all 3 re-reads prints `wait:merge-state-unknown` (4 reads, 1
    merge call), with or without the admin setting;
  - `UNKNOWN` that settles on the last re-read follows that state: `BLOCKED`
    with the admin setting reruns with `--admin` (`merged-admin`, 6 reads, 2
    merge calls), `BLOCKED` without it prints `skipped:blocked`, `BLOCKED` with
    a failed rollup prints `wait:checks-failed`, `DIRTY` prints
    `skipped:conflicts` and `CLEAN` prints `skipped:refused`;
  - any other state (`CLEAN`, `UNSTABLE`, `HAS_HOOKS`) prints
    `skipped:refused`;
  - a failed or incomplete re-read, the first or a later one, prints
    `MERGE_ERROR`.
- **Re-read delay.** `HIVEMIND_AUTO_MERGE_REREAD_DELAY` outside 0 to 99 whole
  seconds (`abc`, `100`, `-1`, `1 `, `1.5`) prints
  `MERGE_ERROR=bad-reread-delay`, exit 1, with zero `gh` calls; with
  `HIVEMIND_AUTO_MERGE` unset it still prints `MERGE=off`. Empty is the default.

- **Record gate off.** A PR whose files hold no `docs/prds/`, `docs/initiatives/`
  or `docs/adr/` path, no `RENAMED` file and no next page makes no git call and
  no extra read, even in a repository tied to the PR: 2 reads and 1 merge call,
  as before. A `docs/references/` path, a `docsx/prds/` path or no files at all
  leave it off.
- **Record gate on.** The record cases run in a case folder that is a git
  repository, against a bare fixture server built with the real git. Its
  branches are `main`, `trunk-demo` (a demo initiative whose record passes) and
  `trunk-drift` (`trunk-demo` with the demo PRD edited and not re-stamped). Its
  PR heads are 11 (record passes), 12 (verdict fail), 13 (verdict pass with an
  open finding), 14 (PRD and solution design, no record), 15 (`trunk-demo` with
  the solution design marked delivered) and 16 (`trunk-demo` plus a second
  initiative whose record passes). PR 18 has no head ref.
  - A passing record merges: 3 reads (the first, the fresh read and the confirm
    read) and 1 merge call. The fetch is exactly
    `fetch --quiet --no-tags --no-recurse-submodules --no-prune --refmap= --
    origin refs/pull/11/head refs/heads/main`, and the case repository holds no
    ref afterwards while the head commit is in its object store.
  - A `docs/prds/` path, a `docs/adr/` path, a `RENAMED` file and a files page
    overflow each run the gate (on PR 12, so each prints `record-blocked`); an
    overflow is never `read-incomplete`.
  - The tied remote is found in scp form with mixed case, in ssh form with a
    trailing slash, on `GH_HOST`, and as the second remote after a fork; the
    fetch names that remote.
  - `skipped:record-unread`, with no merge call: no tied remote (no fetch), no
    remote, a host other than the gh host, a base name that fails the
    identifier gate (no fetch), a fetch failure, a head or base oid missing
    after the fetch, and a verify error (`ls-tree` made to fail).
  - `skipped:record-blocked`, with no merge call: a failing record, the same
    with the admin setting set, an open finding, a changed initiative folder
    with no record, a delivered flip of a stamped solution design, and base
    drift of another record's stamp. PR 16 on `trunk-demo`, with no drift,
    merges.
  - The fresh read: a moved base prints `wait:base-moved`, a moved head
    `wait:head-moved`, and a failed gate its line (`checks-failed`,
    `no-approval`), each with 2 reads and no merge call.
  - The `--admin` path: after a refused plain merge, a `BLOCKED` re-read on the
    same base reruns with `--admin` and the same `--match-head-commit`
    (`merged-admin`, 4 reads, 2 merge calls); a `BLOCKED` re-read on a moved
    base prints `wait:base-moved` with no `--admin` call, as does an `UNKNOWN`
    re-read followed by a `BLOCKED` one on a moved base (4 reads).

## Properties over every case

After the cases run, the suite scans every `calls.log`:

- no merge call carries `--auto` or `--delete-branch`;
- every merge call carries `--match-head-commit` equal to the head of the read
  before it;
- no merge call follows a read whose rollup was not `SUCCESS`;
- no merge call follows a read holding a review state outside `APPROVED`,
  `COMMENTED` or `DISMISSED`;
- `--admin` appears only as the second merge call of a case that set the admin
  setting, after a refused plain merge on the same head with a `SUCCESS` rollup;
- a `merged` or `merged-admin` line requires the case's last call to be a read
  showing `state=MERGED`, after its last merge call;
- a case outside the record cases makes no git call.

The scan fails if it finds no merge call at all, no `merged` or
`merged-admin` case, or no case on either side of the git check, so it can
never pass empty.
