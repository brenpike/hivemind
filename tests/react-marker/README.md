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
stderr, and exits with a chosen status. A live reaction succeeds only when `gh`
exits 0 AND the shared validator `hivemind_graphql_response_check`
(`plugin/skills/_shared/graphql-response.sh`) accepts the body: an exit-0 response
carrying a top-level `errors` value (with a message, or `[{}]`) fails with
`react-failed`. The idempotency check reads stdout only, so an "already reacted"
body is still a success both on exit 0 and on a non-zero exit (gh copies the
response body to stdout even when it exits non-zero). Each case asserts the stub
was reached. The bootstrap tokens `cannot-self-locate`, `missing-graphql-check`,
and `unparseable-graphql-check` are documented in the script header; the shared
self-location suite covers them.

The suite uses REAL production-shaped reviewer node ids — `IC_...` for a toplevel
IssueComment and `PRR_...` for a review PullRequestReview — not fake placeholder
ids, so validation-order bugs cannot hide behind a non-production node shape. The
inputs are short positional args (`NODE_ID`, `surface`, `candidate_url`) and the
assertions are over the captured reaction log, so the suite needs no on-disk
input/expected JSON fixtures — the capture files live in a disposable `mktemp -d`
tmpdir removed on `EXIT`.

This directory is the designated fixture home should a future case require a canned
on-disk fixture (it is referenced by `tools/validate.sh`'s self-test probe map for
issue #265); it is kept committed via this README so the home exists ahead of that
need.
