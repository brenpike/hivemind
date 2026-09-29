# tests/reply-resolve

Fixture home for `tools/test_reply_resolve.sh`, the offline behavioral runner for
`plugin/skills/github-review-loop/scripts/reply-resolve.sh` (issue #205).

`reply-resolve.sh` is driven entirely through its `REPLYRESOLVE_CAPTURE_FILE`
seam: each mutation is appended to a scratch capture file (one line per mutation)
instead of being issued against `gh`, and the simulated mutation exit status is
supplied via `REPLYRESOLVE_REPLY_STATUS` / `REPLYRESOLVE_RESOLVE_STATUS`. Because
the inputs are short positional args (`thread_id`, `fix-SHA`, `summary`, surface,
`candidate_url`) plus the optional `--defer <tracked-home>` flag that selects the
sanctioned deferral reply body, and the assertions are over the captured mutation
log, the suite needs no on-disk input/expected JSON fixtures — the capture files
live in a disposable `mktemp -d` tmpdir removed on `EXIT`.

This directory is the designated fixture home should a future case require a
canned on-disk fixture (it is referenced by file scope for issue #205); it is kept
committed via this README so the home exists ahead of that need.
