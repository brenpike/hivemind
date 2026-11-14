# tests/react-marker

Fixture home for `tools/test_react_marker.sh`, the offline behavioral runner for
`plugin/skills/github-review-loop/scripts/react-marker.sh` (issue #265).

`react-marker.sh` is driven entirely through its capture seam, which requires BOTH
`REACTMARKER_TEST_MODE=1` AND `REACTMARKER_CAPTURE_FILE`: the EYES reaction is
appended to a scratch capture file (one line per reaction, format
`REACT node=<NODE_ID> content=EYES`) instead of being issued against `gh`. The
simulated live mutation exit status is supplied via `REACTMARKER_REACT_STATUS` for
the failure-path case. Reason tokens asserted on the hard-failure paths are
`missing-node-id`, `unmapped-surface`, and `react-failed`.

The live-path cases (issue #393) leave `REACTMARKER_TEST_MODE` and
`REACTMARKER_CAPTURE_FILE` unset and put a stub `gh` first on `PATH`. The stub
prints a canned GraphQL response body on stdout, writes an unrelated line on
stderr, and exits with a chosen status. A live reaction has exactly one definition
of success, positive proof: `gh` exits 0, the shared validator
`hivemind_graphql_response_check` (`plugin/skills/_shared/graphql-response.sh`)
accepts the body, AND `.data.addReaction.reaction.content` equals the requested
`EYES`. Every other response fails with `react-failed`: a top-level `errors` value
(an array with a message, `[{}]`, or an object), a null `addReaction` payload, a
different reaction content, or a non-zero `gh` exit even when the body is a clean
`EYES` payload. No response text is pattern-matched, so a body whose error message
says the viewer already reacted is `react-failed` too. A duplicate reaction is a
server-side success that returns the normal payload, so it needs no special case.
Each case asserts the stub mutation was reached.

Every live-path case, the `REACTMARKER_CAPTURE_FILE`-without-`REACTMARKER_TEST_MODE`
case included, runs from a scratch git repo under the tmpdir, never from the
hivemind checkout (CI checks pull requests out at a detached HEAD). The repo is on
branch `bugfix/fixture-branch`, set with `git symbolic-ref`, with a fake https
GitHub origin. Git runs with `GIT_DIR` and `GIT_WORK_TREE` unset, a scratch
`HOME`, and `GIT_CONFIG_NOSYSTEM=1`. The one commit (the detached-HEAD repo) uses
`-c commit.gpgsign=false`. The stub `gh` tells apart `gh repo view` (the origin
repository id), the PR binding `gh api graphql` lookup, and the `addReaction`
mutation. Existing live cases get a binding that matches the fixture PR.

The PR binding cases each assert exit 1, the exact token on stderr, and no
reaction sent:

- `pr-binding-refused`: a node on another PR; a node whose PR head has the same
  branch name in another repo; a `CLOSED` PR; a `MERGED` PR; a toplevel candidate
  whose node is a `PullRequestReview`; a review candidate whose node is an
  `IssueComment`; an `IssueComment` with a null `pullRequest`; a null node; a null
  `headRepository`.
- `pr-binding-lookup-failed`: a non-zero `gh` exit on the binding query; an exit-0
  `NOT_FOUND` errors envelope; a non-JSON body; a failed `gh repo view`; no
  `origin` remote; an https origin URL holding `@`; two push URLs.
- `pr-binding-no-branch`: a detached HEAD, with `gh` never reached.

One more case asserts the binding passes the node id as a variable, never in the
query text. A thread-surface run from a non-git directory, with stub `git` and
`gh` first on `PATH`, stays a silent no-op that reaches neither.

The bootstrap tokens `cannot-self-locate`,
`missing-graphql-check`, and `unparseable-graphql-check` are documented in the
script header; the shared self-location suite covers them.

The suite uses REAL production-shaped reviewer node ids — `IC_...` for a toplevel
IssueComment and `PRR_...` for a review PullRequestReview — not fake placeholder
ids, so validation-order bugs cannot hide behind a non-production node shape. The
inputs are short positional args (`NODE_ID`, `surface`, `candidate_url`) and the
assertions are over the captured reaction log, so the suite needs no on-disk
input/expected JSON fixtures — the capture files, scratch repos and stubs live in
a disposable `mktemp -d` tmpdir removed on `EXIT`.

This directory is the designated fixture home should a future case require a canned
on-disk fixture (it is referenced by `tools/validate.sh`'s self-test probe map for
issue #265); it is kept committed via this README so the home exists ahead of that
need.
