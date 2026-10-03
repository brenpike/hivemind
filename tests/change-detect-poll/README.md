# tests/change-detect-poll

Fixture home for `tools/test_change_detect_poll.sh`, the offline behavioral runner for
`plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh` (issue #324).

## What the suite proves

The poll treats its FIRST successful poll as the baseline: it emits nothing and records
everything already present as seen. The skill arms the Monitor only AFTER cycle 0 finishes
dispatching (`SKILL.md` Lifecycle steps 2-3), so the entire cycle-0 duration is a **blind
window** — feedback posted inside it missed cycle 0's fetch AND is counted as pre-existing by
the poll, so it never fires `CHANGED`. Case `blind-window:comment-surfaces` is the bite-proof:
it serves the post-comment state to every poll and asserts a `CHANGED` event. It FAILS on the
unfixed script.

The remaining cases pin the behavior the fix must not break: silence on no delta, `CHANGED` on
each scalar class (`LATEST_NONSELF_ISSUE_COMMENT_ID`, a `*_TOTAL` tripwire alone, `FAILED_CHECKS`),
`REVIEWER_APPROVED` on a first-poll approval, and the fail-closed `POLL_ERROR` paths.

## Reviewer identity (ADR-0033)

Every login, filter, and approver decision the poll makes is delegated to the shared
`reviewer-identity.jq` registry module. The poll's `approval` scalar is true on EITHER a 👍
reaction from a Bot-account `pr-reaction-thumbs-up` registry member (Codex) OR a Bot-account
`review-approved` member (Copilot) whose latest review is `APPROVED`, both scoped by the active
reviewer filter, and an approval edge surfaces as the `REVIEWER_APPROVED` marker. A Bot account is
the module's `is_bot`: typed `Bot`, OR a raw login ending in the reserved `[bot]` suffix. The REST
reactions endpoint reports a bot reactor's `user.type` as `User`, so the Codex 👍 arrives
User-typed with a `[bot]`-suffixed login; a GitHub login is alphanumerics and hyphens only, so no
human account can carry the suffix. The latest
review is the one GitHub reports per author in `latestReviews`, never one rebuilt from the bounded
`reviews` history window, and it is read by an exhaustive paginated walk in a query of its own:
`first: 100` is the page size, not a bound, and a walk that fails on any page fails the capture.
The suite pins:

- `approval:thumbs-up-on-first-poll` — a Codex 👍 row in the REST shape (User-typed,
  `[bot]`-suffixed login) fires `REVIEWER_APPROVED` first.
- `approval:rest-user-typed-bot-thumbs-up-approves` — the same REST-shaped Codex 👍 fires
  `REVIEWER_APPROVED` first under `automated` AND `codex-only`, and so does a variant re-typing
  the row `Bot`; a gate on the account type alone idles to `WATCH_TIMEOUT`.
- `approval:human-thumbs-up-never-approves` — User-typed 👍 rows with bare logins (one carrying the
  Codex registry login itself) never approve, under `automated`, `codex-only`, OR `all`; `all`
  admits every login to the filter, so the approver's Bot-account gate is the only thing under
  test.
- `approval:reaction-login-cannot-forge-type` — a User-typed 👍 whose login is the Codex bot login
  followed by a TAB and `Bot` never approves, under `automated`, `codex-only`, OR `all`. Reaction
  rows travel as JSON objects, so no login byte can be read as a field boundary, and the login does
  not END in the `[bot]` suffix, so it is no Bot account.
- `approval:eyes-reaction-never-approves` — a REST-shaped Codex `eyes` reaction never approves;
  only a +1 is the Codex approval signal.
- `approval:copilot-review-scoped-by-filter` — a Copilot `APPROVED` latest review fires
  `REVIEWER_APPROVED` first under `automated`, and only `CHANGED` (never an approval) under
  `codex-only`.
- `approval:superseded-review-never-approves` — a Copilot `latestReviews` entry in state
  `CHANGES_REQUESTED`, `COMMENTED`, or `DISMISSED` after an earlier `APPROVED` never approves and
  fires `CHANGED`; a latest `APPROVED` after an earlier `COMMENTED` still fires.
- `approval:review-window-overflow-still-approves` — with `REVIEWS_TOTAL` at 120 and no Copilot
  review inside the 50-review window, a Copilot `APPROVED` in `latestReviews` still fires
  `REVIEWER_APPROVED` first under `automated`.
- `approval:latest-review-not-history` — a Copilot `APPROVED` that is the latest Copilot review in
  the `reviews` window, with no Copilot `latestReviews` entry, never approves and fires `CHANGED`.
- `approval:user-typed-review-never-approves` — a User-typed `APPROVED` latest review under the
  Copilot registry login never approves under `all`, and fires `CHANGED`.
- `approval:latest-reviews-every-page-read` — a Copilot `APPROVED` on the LAST page of a 2-page and
  a 3-page `latestReviews` walk, behind 100 / 200 distinct User-typed `COMMENTED` authors, fires
  `REVIEWER_APPROVED` first under `automated`; the snapshot query's own `latestReviews` holds
  exactly page 1, so a read bounded to one page idles to `WATCH_TIMEOUT`. The same walks ending in
  a Copilot `COMMENTED` review stay silent to `WATCH_TIMEOUT` (discrimination).
- `approval:latest-reviews-partial-walk-fails-closed` — a walk whose page 1 reports
  `hasNextPage` true and whose next page fails is `SNAPSHOT_ERROR`, exit 1, in snapshot mode and
  `POLL_ERROR`, exit 1, in poll mode; no approval verdict is drawn from a partial walk.
- `approval:latest-reviews-graphql-errors-fail-closed` — see GraphQL error envelopes below.
- `filter:empty-slot-is-automated` — over one mixed review state, the seed token captured with an
  empty filter slot equals the `automated` token and differs from both the `codex-only` and `all`
  tokens; an empty-slot arm fires `REVIEWER_APPROVED` on the Copilot approval.
- `identity:comment-self-keys-on-type` — a higher-id issue comment whose login IS the self login,
  `COMMENTS_TOTAL` unchanged, fires `CHANGED` when Bot-typed or untyped (the module's `is_self` is
  User-gated, and a null type is never self) and stays silent to `WATCH_TIMEOUT` when User-typed
  (self-echo suppression intact). A login-only self compare idles the Bot and untyped variants.
- `identity:thread-self-keys-on-type` — the same three swaps on a review thread's last comment, over
  a base whose thread ends in a User-typed self reply, with `REVIEW_THREADS_TOTAL` unchanged.

## GraphQL error envelopes (#393)

`gh` exits 0 on several GraphQL error envelopes (a top-level `errors` value), so an exit-0
response is usable only when the shared `plugin/skills/_shared/graphql-response.sh` check
accepts it. The snapshot body passes `hivemind_graphql_response_check` before any field is
projected; the `latestReviews` walk carries no `--jq`, so its raw page stream (every page's
JSON object concatenated) passes `hivemind_graphql_pages_check` before the script projects one
row per entry itself. The fake `gh` serves every case below exit 0.

- `response:snapshot-graphql-errors-fail-closed` — the pre-cycle-0 state, `data` intact, with a
  top-level `errors` of `[{"message":"x"}]`, `[{}]`, or `{}` is `SNAPSHOT_ERROR`, exit 1, in
  snapshot mode and `POLL_ERROR`, exit 1, in poll mode. The `data` alone would yield a valid
  baseline and a silent poll.
- `approval:latest-reviews-graphql-errors-fail-closed` — a 2-page walk ending in a Bot-typed
  `review-approved` `APPROVED` review (which alone fires `REVIEWER_APPROVED` first, as in
  `approval:latest-reviews-every-page-read`), with a top-level `errors` value on page 2 or on
  page 1, is `SNAPSHOT_ERROR` / `POLL_ERROR`, exit 1, and never fires `REVIEWER_APPROVED`.

### Review-surface shape (#393)

After the envelope check, the snapshot body passes the shared
`plugin/skills/_shared/review-surface-shape.sh` check (`hivemind_review_surface_shape_check`),
which requires the whole review-activity skeleton: an object `pullRequest`; `comments`, `reviews`,
and `reviewThreads` each an object with a `nodes` array; and every thread an object whose
`comments` is an object with a `nodes` array. A body missing any of these would otherwise project
as no activity and idle the poll past real feedback. `nodes: []` passes at every level.

- `response:snapshot-hollow-surface-fail-closed` — the pre-cycle-0 state with no `errors` value
  and a thread whose `comments.nodes` is null, a thread with `comments` deleted, a null thread
  (the three bites: each yields a valid baseline without the check), a null `reviews`, or a null
  `pullRequest` (locks) is `SNAPSHOT_ERROR` / `POLL_ERROR`, exit 1.
- `response:empty-surface-valid-baseline` — every connection empty, and a variant whose one thread
  holds an empty `comments.nodes`, each capture the exact expected `BASELINE=` line, exit 0, and a
  poll armed with it idles silently to `WATCH_TIMEOUT`.

## Process lifetime

`CHANGED` is the only marker after which the poll keeps running. `REVIEWER_APPROVED` and every
terminal marker are the last line the process prints, and `REVIEWER_APPROVED` exits 0. The
skill's confirmation pass is a full fix pass, and any return that keeps watching arms a fresh poll
from the pending `re-arm` seed, so a poll left running past the approval marker is an orphan
that can trail a stale `CHANGED`.

- `approval:marker-ends-poll-process` — (i) a lone approval edge (pre-cycle-0 state, reactions
  none then Codex 👍) prints exactly `REVIEWER_APPROVED`, exit 0, and the fake `gh` sees exactly
  two snapshot queries under a watch window long enough for several more; (ii) the approval
  co-firing with a new comment delta prints exactly `REVIEWER_APPROVED`, with no trailing marker;
  (iii) discrimination: the same comment delta without an approval prints `CHANGED` and keeps
  polling to a last line of `WATCH_TIMEOUT`, so only the approval edge ends the process.

## The second bite: the seed's state model (PR #361)

The seed originally serialized 8 of the 9 scalars the poll diffs, omitting the approval bool
(then the Codex-only 👍 bool, field `codex`; now `approval`). That
omission was correct while the seed had ONE consumer — the initial arm, which WANTS a pre-existing
👍 to surface. The productive-cycle re-arm is a SECOND consumer with the opposite requirement, so
one token was carrying two contradictory semantics, decided per-scalar by which fields it happened
to carry. Two halves close the class rather than the instance, and the suite holds both:

- **Complete serialization.** `seed:complete-serialization` is STRUCTURAL: it reads the script's
  own `SNAPSHOT_FIELDS` declaration and the set of literal `cur_<name>=` assignments and asserts
  the two sets are EQUAL. The serializer, the seed parser, the `SEED_FORMAT_RE` width, the
  completeness assertion, and the `CHANGED` diff are all derived by iterating that one
  declaration, so a scalar cannot be diffed without being serialized — and an author who adds one
  without declaring it goes red here. A per-scalar assertion would have caught neither instance,
  which is why this case is set-equality and not a field checklist.
- **Explicit arm kind.** Each seed is stamped `initial` or `re-arm` at capture and the stamp lives
  INSIDE the token, so carrying a seed forward carries its kind forward.
  `approval:stale-not-refired-on-rearm` is the regression bite (a 👍 present at the
  pre-dispatch capture must stay silent on the re-armed poll, or the confirmation pass ends the
  watch as terminal `clean` right after the reviewer pushed).
  `approval:initial-arm-surfaces-pre-existing` is its mirror and pins the behavior that must NOT
  regress; the two cases serve IDENTICAL PR state and IDENTICAL reactions and differ ONLY in the
  seed's arm kind, which is what proves the kind — not the field set — decides the question.
  `approval:new-fires-on-rearm` guards against over-correction, and
  `seed:arm-kind-closed-set` pins the fail-closed paths for a missing or unknown kind.

## Running it

```bash
bash tools/test_change_detect_poll.sh
```

Offline — bash + `jq` only, no `gh`, no network, ~130s. A PATH-shim fake `gh` serves canned
fixture bytes while the REAL `jq` runs the script's REAL filters, so the snapshot derivation
under test is the production one and only the transport is faked.

## The seed probe

The fix adds a `--snapshot` mode emitting a `BASELINE=<arm kind + one field per diffed scalar>`
token captured BEFORE cycle 0, passed back as a REQUIRED 8th positional argument to poll mode. The
runner probes the script under test for `--snapshot` support instead of assuming it:

- **absent** — cases run against the legacy 7-arg form and the seed-contract cases print a
  visible `SKIP` line. A silent pass on an unimplemented feature is the false-pass class of #321.
- **present** — the seed is captured at the pre-cycle-0 state and passed as arg 8; the
  seed-contract cases run.

Post-merge the probe is a regression guard: if seed support ever disappears, the bite-proof case
goes red again rather than quietly passing.

The runner asserts (does not guess) this seed contract: snapshot mode is
`pr-change-detect-poll.sh --snapshot <initial|re-arm> <OWNER> <REPO> <PR> <MAX_WATCH> <INTERVAL>
<FILTER> <SELF>`, emitting one `BASELINE=<value>` line whose BARE `<value>` is arg 8 of poll mode;
a snapshot that cannot be captured, or one given a missing or unknown arm kind, emits
`SNAPSHOT_ERROR` and exits 1.

## Fixtures

| File | Role |
| --- | --- |
| `graphql-pre-cycle0.json` | State A — the PR as it stood before cycle 0 (two User-typed self issue comments, one Bot-typed Codex review and its `COMMENTED` `latestReviews` entry, one Bot-typed Codex thread, checks green). |
| `graphql-blind-window.json` | State B — A plus the Codex review + review-thread comment posted during the blind window. |
| `graphql-malformed.json` | A GraphQL `NOT_FOUND` error response (`errors` array, null `pullRequest`) that the snapshot capture rejects. |
| `reactions-none.json` | Raw REST reactions page with no reaction (`[]`). |
| `reactions-codex.json` | Raw REST reactions page with one +1 from `chatgpt-codex-connector[bot]`, in the shape the REST endpoint returns for a bot reactor (`user.type` `User`, plus `id` and `user_view_type`). |
| `reactions-human.json` | Raw REST reactions page with two User-typed +1s (`chatgpt-codex-connector`, `claude`) that must never approve. |
| `reactions-forged.json` | Raw REST reactions page with one User-typed +1 whose login is `chatgpt-codex-connector[bot]`, a TAB, and `Bot`; it must never approve. |
| `reactions-codex-eyes.json` | Raw REST reactions page with one `eyes` reaction from `chatgpt-codex-connector[bot]`, in the same REST bot-reactor shape (`user.type` `User`); it must never approve. |

The `graphql-*.json` files are whole GraphQL responses shaped to the script's own query; every
author (issue comments, reviews, and review-thread comments) carries `__typename` (`Bot` for
automated reviewers, `User` for humans and the self login) because every author selection requests
it and the registry's self, filter, and approver tests are all type-gated. Every
`graphql-*.json` state other than the malformed one carries a `latestReviews` connection, because
the poll reads review approval from it and a missing connection fails the capture. The Copilot
`APPROVED`, superseded, window-overflow, and mixed-review states are derived in the runner rather
than committed; each adds its Copilot review to `reviews` and, where GitHub would report it as
that author's latest, to `latestReviews`. The multi-page `latestReviews` walks are generated in
the runner (`review_page`, `review_pages`, `review_walk`) rather than committed. The
`reactions-*.json` files are raw REST reactions pages, the bytes the API returns before `gh`
applies `--jq`. The fake `gh` reads the script's own `--jq` argument and applies it to each
served page with the real `jq -r`, so the production transport expression runs under test; a jq
error on any page exits non-zero, and a call without `--jq` (the snapshot GraphQL query and
the `latestReviews` walk; only the reactions read carries `--jq`) is served raw. The fake `gh` strips CR when serving, so a `core.autocrlf` checkout of a fixture
cannot carry CR into the parsed bytes.

The fake `gh` routes three call kinds: `graphql` (the snapshot query), `latestreviews` (a
`graphql` call carrying `--paginate`, the approval walk), and `reactions`. With no
`latestreviews` sequence set, a `latestreviews` call mirrors the `graphql` sequence entry at its
OWN call counter, so every committed state fixture serves both calls and the existing cases need
no walk of their own. Caveat: the two counters advance independently, so a case whose `graphql`
sequence has a `FAIL` or malformed entry before a good one desynchronises the mirror and must set
its own `latestreviews` sequence. A sequence entry ending `.pages` is a paginated walk: a file
listing one page path per line, served raw in order as one call (every page's JSON object
concatenated, the stream the script hands to the shared pages check); a `FAIL` line exits
non-zero after
the earlier pages are printed. The fake `gh` serves pages after the first ONLY when the
whitespace-normalized query declares `$endCursor: String`, passes `after: $endCursor`, and
selects `pageInfo { hasNextPage endCursor }` — otherwise page 1 alone, as real `gh` returns for a
query it cannot walk — so the GraphQL pagination contract is enforced behaviourally.

## Adding a case

1. Reuse a committed fixture, or derive a variant in the runner with `derive_fixture <name>
   <base> <jq-program>` — one fixture file per scalar class is not worth the churn.
2. `st="$(new_state <name>)"`, then `set_seq "$st" graphql <entry>...` and
   `set_seq "$st" reactions <entry>...` (plus `set_seq "$st" latestreviews <entry>...` when the
   approval walk must differ from the mirrored `graphql` entry). Call N serves line N, clamping to
   the last line, so one entry means a steady state. The literal entry `FAIL` makes that call exit
   non-zero.
3. Drive it with `arm_poll "$st" "$SEED" [filter]` (`$SEED` is empty when the probe found no seed
   support, which selects the legacy form; `[filter]` defaults to `codex-only` when omitted, and an
   explicit `""` passes an empty filter slot) and assert with `pass` / `failed`. Cases that exercise
   behavior which only exists after the fix must branch on `SEED_SUPPORTED` and `skipped` otherwise.
4. A case needing a seed other than the shared `initial` one uses
   `capture_seed <state_name> <arm_kind> <graphql_entry> <reactions_entry> [filter]`, which returns the
   BARE token; `snapshot_raw` is the same call returning raw stdout when the `BASELINE=`/
   `SNAPSHOT_ERROR` line itself is the assertion.
5. Never assert the token's field list scalar by scalar — derive the expected width from
   `DECLARED_FIELD_COUNT` and let `seed:complete-serialization` hold the set equality. A field
   checklist is the shape that let the omitted approval bool ship twice.
