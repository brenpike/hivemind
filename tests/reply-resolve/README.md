# tests/reply-resolve

Fixture home for `tools/test_reply_resolve.sh`, the offline behavioral runner for
`plugin/skills/github-review-loop/scripts/reply-resolve.sh` (issue #205).

Most cases drive `reply-resolve.sh` through its `REPLYRESOLVE_CAPTURE_FILE`
seam: each mutation is appended to a scratch capture file (one line per mutation)
instead of being issued against `gh`, and the simulated mutation exit status is
supplied via `REPLYRESOLVE_REPLY_STATUS` / `REPLYRESOLVE_RESOLVE_STATUS`.

The live-path cases (issue #393) leave every `REPLYRESOLVE_*` test variable unset
and put a stub `gh` first on `PATH`. The stub tells the REPLY call from the
RESOLVE call by its `query=` text, prints that call's canned GraphQL response body
on stdout, writes an unrelated line on stderr, exits with that call's chosen
status, and appends the call kind to a call log. A live mutation succeeds only
when `gh` exits 0 AND the shared validator `hivemind_graphql_response_check`
(`plugin/skills/_shared/graphql-response.sh`) accepts the body. An exit-0 REPLY
response carrying a top-level `errors` value (with a message, or `[{}]`) fails
with `reply-failed` and the call log shows NO resolve was sent. An exit-0 RESOLVE
response carrying `errors` logs `REPLYRESOLVE_RESOLVE_FAILED` and the script
still exits 0. A clean envelope is not enough: the body must also prove the
requested object (REPLY: a non-empty `comment.id`; RESOLVE: `thread.isResolved`
true), so an exit-0 REPLY with a null payload, a null `comment`, or an empty id
fails with `reply-failed` and sends no resolve, and an exit-0 RESOLVE with a
null payload or `isResolved: false` logs `REPLYRESOLVE_RESOLVE_FAILED` and still
exits 0. The bootstrap tokens `cannot-self-locate`, `missing-graphql-check`,
and `unparseable-graphql-check` are documented in the script header; the shared
self-location suite covers them.

Every live write is bound to the current PR first (`reply-resolve.sh` §4, PR
BINDING), so every live-path case runs from a scratch git repo under the
tmpdir, never from this checkout, whose branch and remotes vary (CI checks out
PRs at detached HEAD). The scratch repo has branch `bugfix/fixture-branch` set
with `git symbolic-ref`, one empty commit made with `-c commit.gpgsign=false`,
and origin set to a fake https GitHub URL. Git runs with `GIT_DIR`,
`GIT_WORK_TREE` and `XDG_CONFIG_HOME` unset, `HOME` pointed at a scratch dir and
`GIT_CONFIG_NOSYSTEM=1`, so no user or system git config reaches a case. The
stub `gh` also answers `gh repo view` (the origin repository id) and the binding
query (`node(id:)`), and logs both. The binding cases each assert exit 1, the
exact `REPLYRESOLVE_ERROR=<token>` on stdout, and that no reply or resolve was
sent:

- `pr-binding-refused`: a thread on another PR of the same repo, a PR head with
  the same branch name in another repo, a CLOSED PR, a MERGED PR, an
  `IssueComment` node, a null node, and a null `headRepository`.
- `pr-binding-lookup-failed`: a non-zero exit on the binding query, an exit-0
  `NOT_FOUND` errors envelope, a non-JSON body, a failed `gh repo view`, a repo
  id outside the charset, no origin remote, an https origin URL holding `@`, and
  two push URLs (the last three never reach `gh`).
- `pr-binding-no-branch`: a detached HEAD (`gh` is never reached).

A matching binding is asserted to send `gh repo view` with the origin URL and
the binding query with the thread id only as the `threadId` variable, before
the reply and resolve; an ssh-form origin binds too. The capture seam skips the
binding, so a capture-mode run from a non-git directory still captures its
reply and resolve and reaches no `gh`. The case that sets
`REPLYRESOLVE_CAPTURE_FILE` without `REPLYRESOLVE_TEST_MODE` runs from the
scratch repo and asserts the binding, reply and resolve all went live.

ONE MUTATION IS ONE CAPTURE LINE, so the seam only round-trips a reply body that
is itself a SINGLE LINE: an embedded newline would split one mutation across two
capture lines and break every assertion over the log. That is the test-side face
of the one-line-body invariant in `reply-resolve.sh` §4. It matters most for the
DEFER body, which leads with the machine sentinel `<!-- hivemind-defer-v1 -->` at
byte 0 — `<!-- hivemind-defer-v1 --> Deferred to <tracked-home>. <summary>.` —
because a newline anywhere in it would put the sentinel and its prose on different
lines, where the classifier's byte-0 constant comparison can no longer see them as
one deferral.

Because the inputs are short positional args (`thread_id`, `fix-SHA`, `summary`,
surface, `candidate_url`) plus the optional `--defer <tracked-home>` flag that
selects the sanctioned deferral reply body, and the assertions are over the
captured mutation log, the suite needs no on-disk input/expected JSON fixtures —
the capture files, shim bodies and scratch git repos live in a disposable
`mktemp -d` tmpdir removed on `EXIT`.

This directory is the designated fixture home should a future case require a
canned on-disk fixture (it is referenced by file scope for issue #205); it is kept
committed via this README so the home exists ahead of that need.
