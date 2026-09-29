# tests/reply-resolve

Fixture home for `tools/test_reply_resolve.sh`, the offline behavioral runner for
`plugin/skills/github-review-loop/scripts/reply-resolve.sh` (issue #205).

`reply-resolve.sh` is driven entirely through its `REPLYRESOLVE_CAPTURE_FILE`
seam: each mutation is appended to a scratch capture file (one line per mutation)
instead of being issued against `gh`, and the simulated mutation exit status is
supplied via `REPLYRESOLVE_REPLY_STATUS` / `REPLYRESOLVE_RESOLVE_STATUS`.

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
the capture files live in a disposable `mktemp -d` tmpdir removed on `EXIT`.

This directory is the designated fixture home should a future case require a
canned on-disk fixture (it is referenced by file scope for issue #205); it is kept
committed via this README so the home exists ahead of that need.
