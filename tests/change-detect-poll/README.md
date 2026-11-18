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
each review scalar class (`LATEST_NONSELF_ISSUE_COMMENT_ID`, a `*_TOTAL` tripwire alone),
`CI_FAILED` on a `FAILED_CHECKS` rise (see CI route below), `REVIEWER_APPROVED` on a first-poll
approval, and the fail-closed `POLL_ERROR` paths.

- `delta:failed-checks` — one check run moving SUCCESS to FAILURE (`FAILED_CHECKS` 0 to 1) with no
  review activity prints exactly `CI_FAILED` then `WATCH_TIMEOUT`: no `CHANGED` for that
  iteration, nothing on the steady red poll after it, and the poll keeps running.

## CI route (#400)

`prefilter.sh` judges only the review surfaces, so a `CHANGED` wake whose only change is the
failed-check count would be `PREFILTER_SKIP`, and the running poll has already moved its baseline.
A rise in `FAILED_CHECKS` against the previous snapshot or the seed therefore prints its own
non-terminal marker, `CI_FAILED`, which the skill dispatches without the prefilter. A drop, and
any other delta, prints `CHANGED`; red CI that stays red at the same count prints nothing, so a
steady red run never re-dispatches. One marker per iteration, in the order `STATE=MERGED`,
`STATE=CLOSED`, `REVIEWER_APPROVED`, `CI_FAILED`, `CHANGED`. Red seeds are captured with
`capture_seed` over `derive_fixture` variants; no committed fixture carries a failed check.

- `ci:drop-fires-changed` — a red `re-arm` seed over the green pre-cycle-0 state prints exactly
  `CHANGED` then `WATCH_TIMEOUT`, never `CI_FAILED`.
- `ci:steady-red-with-comment-fires-changed` — the red seed over the same red count plus a new
  non-self issue comment prints exactly `CHANGED` then `WATCH_TIMEOUT`, never `CI_FAILED`.
- `ci:rise-with-comment-fires-ci-failed` — a rise and a comment delta in one iteration print exactly
  `CI_FAILED` then `WATCH_TIMEOUT`, never `CHANGED`.
- `ci:each-rise-fires-once` — a four-poll watch served 0, 1, 1, 2 failed checks prints exactly
  `CI_FAILED`, `CI_FAILED`, `WATCH_TIMEOUT`: one per rise, nothing on the steady iteration.
- `ci:approval-cofire-wins` — see Process lifetime below.
- `ci:seed-non-digit-failed-checks-fails-closed` — a seed whose `failed_checks` field is `1a` or
  `-1` (located through the `SNAPSHOT_FIELDS` declaration) prints exactly `POLL_ERROR` in poll mode
  and `CHECK_ERROR` in `--check` mode, exit 1, with zero `gh` calls.

## Reviewer identity (ADR-0043)

Every login, filter, and approval decision the poll makes is delegated to the shared
`reviewer-identity.jq` module, and no reviewer product is named in code. Each capture derives ONE
Automated Reviewer set from the PR evidence it read (snapshot review authors, `latestReviews`
authors, 👍 reactors), keeping Bot accounts only and dropping `github-actions` unless listed, plus
the optional `HIVEMIND_PR_REVIEWERS` value, which reaches jq as `--arg` data and only adds to the
set. The poll's `approval` scalar is true when an Automated Reviewer in scope of the active filter
left a 👍 on the PR, or its latest review is `APPROVED` or `COMMENTED` with zero inline review
comments; an approval edge surfaces as the `REVIEWER_APPROVED` marker. A missing or null inline
count is never an approval. A Bot account is the module's `is_bot`: typed `Bot`, OR a raw login
ending in the reserved `[bot]` suffix. The REST reactions endpoint reports a bot reactor's
`user.type` as `User`, so a bot 👍 arrives User-typed with a `[bot]`-suffixed login; a GitHub
login is alphanumerics and hyphens only, so no human account can carry the suffix. The latest
review is the one GitHub reports per author in `latestReviews`, never one rebuilt from the bounded
`reviews` history window, and it is read by an exhaustive paginated walk in a query of its own:
`first: 100` is the page size, not a bound, and a walk that fails on any page fails the capture.
The runner unsets `HIVEMIND_PR_REVIEWERS` at the top and sets it only on a case's own calls. The
bot logins it uses are shapes, not products: a Codex-shaped, a Copilot-shaped, and a generic bot
login, the CI identity `github-actions`, and a status bot. The suite pins:

- `filter:retired-value-rejected` — the filter value the module's `is_retired_filter` names prints
  exactly `SNAPSHOT_ERROR`, `CHECK_ERROR`, or `POLL_ERROR`, exit 1, in snapshot, check, and poll
  mode, with zero `gh` calls.
- `approval:every-bot-shape-approves-identically` — for each bot shape, a REST-shaped 👍, an
  `APPROVED` latest review, and a `COMMENTED` latest review with zero inline comments each fire
  `REVIEWER_APPROVED` first under `automated` with no configuration.
- `approval:commented-with-inline-or-unknown-never-approves` — a `COMMENTED` latest review with 2
  inline comments, an absent `comments` key, a null `comments`, or a null `totalCount` never
  approves under `automated` or `all`, and fires `CHANGED`.
- `approval:ci-identity-only-when-listed` — an unlisted `github-actions` 👍 idles to
  `WATCH_TIMEOUT` and its `APPROVED` review fires only `CHANGED`, under `automated` and `all`;
  listed in `HIVEMIND_PR_REVIEWERS` (with or without `[bot]`, among comma- and space-separated
  logins) each fires `REVIEWER_APPROVED` first. A listed value shaped like jq program text stays
  data: no capture error and no widened set.
- `approval:status-bot-comment-changes-never-approves` — a Bot that only posts an issue comment
  fires `CHANGED` and never `REVIEWER_APPROVED`, under `automated` and `all`.
- `approval:thumbs-up-on-first-poll` — a bot 👍 row in the REST shape (User-typed,
  `[bot]`-suffixed login) fires `REVIEWER_APPROVED` first.
- `approval:rest-user-typed-bot-thumbs-up-approves` — the same REST-shaped bot 👍 fires
  `REVIEWER_APPROVED` first under `automated` AND `<login>` mode naming that bot, and so does a
  variant re-typing the row `Bot`; a gate on the account type alone idles to `WATCH_TIMEOUT`.
- `approval:human-thumbs-up-never-approves` — User-typed 👍 rows with bare logins (one carrying a
  bot login itself) never approve under `automated` or `all`, nor with both logins listed in
  `HIVEMIND_PR_REVIEWERS`; `all` admits every login to the filter, so the Bot-account gate is the
  only thing under test.
- `approval:reaction-login-cannot-forge-type` — a User-typed 👍 whose login is a `[bot]` login
  followed by a TAB and `Bot` never approves, under `automated` OR `all`. Reaction rows travel as
  JSON objects, so no login byte can be read as a field boundary, and the login does not END in
  the `[bot]` suffix, so it is no Bot account.
- `approval:eyes-reaction-never-approves` — a REST-shaped bot `eyes` reaction never approves;
  only a +1 is a reaction approval signal.
- `approval:review-scoped-by-filter` — an `APPROVED` latest review fires `REVIEWER_APPROVED` first
  under `automated` and under `<login>` mode naming its author, and only `CHANGED` (never an
  approval) under `<login>` mode naming another reviewer.
- `approval:superseded-review-never-approves` — a `latestReviews` entry in state
  `CHANGES_REQUESTED`, `COMMENTED` with inline comments, or `DISMISSED` after an earlier
  `APPROVED` never approves and fires `CHANGED`; a latest `APPROVED` after an earlier `COMMENTED`
  still fires.
- `approval:review-window-overflow-still-approves` — with `REVIEWS_TOTAL` at 120 and no review of
  that bot inside the 50-review window, an `APPROVED` in `latestReviews` still fires
  `REVIEWER_APPROVED` first under `automated`.
- `approval:latest-review-not-history` — an `APPROVED` that is the bot's latest review in the
  `reviews` window, with no `latestReviews` entry for it, never approves and fires `CHANGED`.
- `approval:user-typed-review-never-approves` — a User-typed `APPROVED` latest review under a bot
  login never approves under `all`, and fires `CHANGED`.
- `approval:latest-reviews-every-page-read` — an `APPROVED` on the LAST page of a 2-page and a
  3-page `latestReviews` walk, behind 100 / 200 distinct User-typed `COMMENTED` authors, fires
  `REVIEWER_APPROVED` first under `automated`; the snapshot query's own `latestReviews` holds
  exactly page 1, so a read bounded to one page idles to `WATCH_TIMEOUT`. The same walks ending in
  a `COMMENTED` review with 3 inline comments stay silent to `WATCH_TIMEOUT` (discrimination).
- `approval:latest-reviews-partial-walk-fails-closed` — a walk whose page 1 reports
  `hasNextPage` true and whose next page fails is `SNAPSHOT_ERROR`, exit 1, in snapshot mode and
  `POLL_ERROR`, exit 1, in poll mode; no approval verdict is drawn from a partial walk.
- `approval:latest-reviews-graphql-errors-fail-closed` — see GraphQL error envelopes below.
- `filter:empty-slot-is-automated` — over one mixed review state, the seed token captured with an
  empty filter slot equals the `automated` token and differs from both the `<login>` and `all`
  tokens; an empty-slot arm fires `REVIEWER_APPROVED` on the `APPROVED` review.
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
  `APPROVED` review (which alone fires `REVIEWER_APPROVED` first, as in
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

`CHANGED` and `CI_FAILED` are the only markers after which the poll keeps running.
`REVIEWER_APPROVED` and every terminal marker are the last line the process prints, and
`REVIEWER_APPROVED` exits 0. The skill's confirmation pass is a full fix pass that also picks up
failed checks, and any return that keeps watching arms a fresh poll from the pending `re-arm`
seed, so a poll left running past the approval marker is an orphan that can trail a stale
`CHANGED` or `CI_FAILED`. A return that would end clean, or keep watching with no poll
running, first runs `--check` against the pending seed (see Quiet-exit check below).

- `approval:marker-ends-poll-process` — (i) a lone approval edge (pre-cycle-0 state, reactions
  none then bot 👍) prints exactly `REVIEWER_APPROVED`, exit 0, and the fake `gh` sees exactly
  two snapshot queries under a watch window long enough for several more; (ii) the approval
  co-firing with a new comment delta prints exactly `REVIEWER_APPROVED`, with no trailing marker;
  (iii) discrimination: the same comment delta without an approval prints `CHANGED` and keeps
  polling to a last line of `WATCH_TIMEOUT`, so only the approval edge ends the process.
- `delta:failed-checks` and `ci:each-rise-fires-once` — `CI_FAILED` keeps the poll running to a
  last line of `WATCH_TIMEOUT`.
- `ci:approval-cofire-wins` — an approval edge co-firing with a `FAILED_CHECKS` rise prints exactly
  `REVIEWER_APPROVED`, exit 0, and the fake `gh` sees exactly two snapshot queries under the same
  long watch window: the approval outranks `CI_FAILED` and ends the process.

## Watch window

No poll sleep outruns the watch window. Every sleep, the failed-capture retry included, goes
through the poll's one helper, `sleep_to_next_poll`, which reads the clock once through
`read_clock` and sleeps the
smaller of the poll interval and the seconds left to the deadline, or not at all when none is
left, so the loop top prints `WATCH_TIMEOUT` on time. An interval longer than the window is a
legitimate input: the skill's Window deadline re-arm passes the remaining budget as the window
while the interval stays fixed. The fake `date` reads a fixed epoch plus the snapshot-query count,
and the fake `sleep` records its one integer argument to `sleep.calls`, so the recorded sleeps are
exact.

- `watch:sleep-never-outruns-window` — the steady pre-cycle-0 state armed with the shared seed
  under a 5-poll window prints exactly `WATCH_TIMEOUT` and sleeps 4, 3, 2, 1 with interval 3600 and
  with the 18-digit interval `999999999999999999`: each sleep is the time left, none above the
  window. Interval 2 sleeps 2, 2, 2, 1: an interval below the time left passes through unchanged,
  so a clamp to a constant fails. The unfixed script records 3600.
- `watch:failed-capture-sleep-clamped` — a failed first snapshot query then the steady state (with
  its own `latestreviews` sequence, per the mirror caveat under Fixtures), interval 3600, sleeps 4
  first and prints exactly `WATCH_TIMEOUT`, not `POLL_ERROR`.
- `watch:one-sleep-primitive` — structural, like `seed:complete-serialization`: the executable,
  non-comment lines of the poll hold exactly one `sleep` command, inside `sleep_to_next_poll`, so
  a second raw sleep goes red.

## Checked numbers

The poll checks each number where it is read, never where it is used. `read_decimal <name>
<value>` is the only bounded-decimal check (1 to 18 digits, so Bash's 64-bit arithmetic cannot
wrap) and the only base-10 coercion. `read_clock <name>` holds the only `date` command and routes
its reading through `read_decimal`. The PR number, watch window, poll interval, seed
`failed_checks`, capture `FAILED_CHECKS` and all three clock reads go through them. A failed or bad
clock reading is `POLL_ERROR`, exit 1. `--snapshot` and `--check` never read the clock.

The fake `date` counts its calls in the state dir's `date.n`, which `new_state` zeroes. When the
state dir carries `date.seq` (`set_seq "$st" date <entry>...`), call N serves line N: `FAIL` exits
non-zero with no output, `CLOCK` reads the virtual clock, `PADDED` reads the virtual clock
left-padded with zeros to 18 digits, and any other line, an empty one included, is printed as the
reading. Calls past the list, and states with no `date.seq`, read the virtual clock unchanged. The
virtual epoch holds the digit 8, so a padded reading that skips the base-10 coercion is not valid
octal: Bash arithmetic on it errors instead of silently reading another number. The fake `gh`
appends `<kind>:<pr>` to the state dir's `gh.prs` on every call, `<pr>` being the PR number the
call carried, so a case reads the PR number the poll handed to `gh`.

No case scans the poll's text for numbers. Bash evaluates a number in many syntax forms
(arithmetic expansion, `(( ))`, `let`, `declare -i`, `[[ -eq ]]`, subscripts, substring offsets),
so a list of allowed forms cannot be complete. Running the poll at each source is
form-independent: a hostile reading evaluated before its check, in any form, leaves the canary
file behind, and a zero-padded reading used without the base-10 coercion changes the output.
`numbers:one-clock-read` and `watch:one-sleep-primitive` are placement pins for one command word
each, `date` and `sleep`; they are not a safety proof, and the checked-number grid below proves the
rule.

- `clock:bad-reading-fails-closed` — each bad reading (`FAIL`, empty, `abc`, `-1`,
  `9999999999999999999`) served on clock read N, for N = 1 to 4, makes a poll over the steady
  pre-cycle-0 state armed with the shared seed print exactly `POLL_ERROR`, exit 1, after exactly N
  clock reads. Reads 1 to 4 are arm time, the first loop top, the first `sleep_to_next_poll` and
  the second loop top. On N = 1 the fake `gh` sees zero calls. The unfixed script idles to
  `WATCH_TIMEOUT`.
- `clock:snapshot-and-check-never-read-clock` — with a `FAIL` `date.seq`, `--snapshot` prints its
  `BASELINE=` line, exit 0, and `--check` with the shared seed prints `UNCHANGED`, exit 0. Each
  leaves `date.n` at 0.
- `numbers:one-clock-read` — structural placement pin, like `watch:one-sleep-primitive`: the
  executable, non-comment lines of the poll hold exactly one `date` command, inside `read_clock`.
- `validation:oversized-pr-number` — a 19-digit PR number is `POLL_ERROR`, exit 1, with zero `gh`
  calls.

### The checked-number grid

One table in the runner, `NUMBER_SOURCES`, is meant to name every number the poll reads through
`read_decimal` or `read_clock`, how to inject a reading into it, and the modes that read it. It is
kept in step with the poll by hand. The runner generates every probe kind for every (source, mode)
pair of the table, so no source gets a hand-picked subset of probes. Each row is
`name|injector|modes|before_gh|plain|padded|not_applicable`:

RECORDED DECISION (hand-maintained source table): `NUMBER_SOURCES` is maintained by hand. The grid
proves every probe for each (source, mode) pair the table lists, but nothing checks the table
against what the poll really reads. Two gaps are a known limit. A row can list fewer modes than the
ones that read its number. A new `read_decimal` or `read_clock` call added without a row gets no
probes. In both cases the suite stays green. Whoever adds or changes a `read_decimal` or
`read_clock` call in `plugin/skills/github-review-loop/scripts/pr-change-detect-poll.sh` must add or
update its row. The user decided this on local review findings 28072c68 and b531c8bb. A later
finding that asks for the table to be checked against the poll's real reads repeats this decision.
The stronger proof, an execution inventory, is tracked in issue #588.

| Source | Injected through | Modes |
| --- | --- | --- |
| `pr-number` | the PR number argument | poll, `--snapshot`, `--check` |
| `watch-window` | the watch window argument | poll, `--snapshot`, `--check` |
| `poll-interval` | the poll interval argument | poll, `--snapshot`, `--check` |
| `seed-failed-checks` | the shared seed's `failed_checks` field | poll, `--check` |
| `clock-arm-read` | clock read 1 (arm time), through `date.seq` | poll |
| `clock-loop-top-read` | clock read 2 (the loop-top deadline check) | poll |
| `clock-sleep-read` | clock read 3 (`sleep_to_next_poll`) | poll |
| `capture-check-run-failures` | the `checkRunCountsByState` `FAILURE` count of the snapshot query | poll, `--snapshot`, `--check` |
| `capture-status-context-failures` | the `statusContextCountsByState` `FAILURE` count of the snapshot query | poll, `--snapshot`, `--check` |

Each probe is one case named `numbers:<source>:<kind>:<mode>`. The probe kinds:

- `hostile` — `ARITH_PAYLOAD`, `BASH_VERSINFO[$(touch <canary>)]`: arithmetic evaluation runs its
  subscript, which creates `ARITH_CANARY`. Its base name is `BASH_VERSINFO`, an array every Bash
  sets, because the poll runs under `set -u` and an unset base name would abort the evaluation
  before the subscript runs.
- `non-digit` (`abc`), `negative` (`-1`), `empty` (the empty string) and `19-digits`
  (`1234567890123456789`, past the 18-digit bound).
- `padded` — the row's padded reading (`004242`, `0009`, `0008`, `000`, or the fake `date`'s
  `PADDED`) against its plain one (`4242`, `9`, `8`, `0`, or `CLOCK`).

A `hostile`, `non-digit`, `negative`, `empty` or `19-digits` probe passes when the run prints
exactly the mode's error marker (`POLL_ERROR`, `SNAPSHOT_ERROR`, `CHECK_ERROR`), exit 1, and leaves
no `ARITH_CANARY`; a source the row marks `before_gh` (the arguments, the seed, the first two clock
reads) also leaves the fake `gh` at zero calls. A `padded` probe runs the same mode twice, once with
the plain reading and once with the padded one: the plain run exits 0, and the padded run gives
identical status, `gh` calls, sleeps, PR numbers handed to `gh` and output. The probe runs under
window 3 and interval 1; the interval row widens the window to 9, so an interval of 8 reaches
`sleep`. The window, interval and clock readings hold a digit octal lacks, so Bash arithmetic on a
padded reading that skipped the base-10 coercion errors, and the fake `gh` records the PR number
it was handed.

How a reading reaches each source:

- The capture rows drive the count as a JSON string. The poll sums the `FAILURE` counts of both
  buckets with jq's `add`; the injector sets the other bucket's `FAILURE` count to the empty
  string, so `add` concatenates and the reading reaches the poll's `FAILED_CHECKS` line unchanged,
  the payload and the padding included.
- The seed row carries a reading the seed shape (`[A-Za-z0-9_-]`) cannot hold, the payload, through
  an exported variable whose name is the field value, because arithmetic on a name runs its value.
- The clock rows serve the reading on one `read_clock` call site through `date.seq`, the earlier
  reads serving `CLOCK`.

A probe a source cannot take is excluded in its row as `<kind>@<mode>=<reason>`, and the runner
prints an `N/A` line with that reason instead of a case. Only a `padded` probe can be excluded:
a fail-closed probe (`hostile`, `non-digit`, `negative`, `empty`, `19-digits`) always runs, and a row
that excludes one fails the row check. The only exclusions in use are the `padded` probe of the window and interval in `--snapshot` and `--check`: those modes read both arguments
through `read_decimal` but never use them, so a padded reading has nothing to change. Their
`hostile` and rejection probes still run in every mode.

`numbers:source-table` is the self-check. `check_source_row` validates every row before the grid
runs: seven fields, an injector naming a declared function, a mode list drawn from poll, snapshot
and check, a `yes` or `no` `before_gh`, well-formed exclusions that name the `padded` probe and one of the
row's modes, and distinct plain and padded readings unless every mode excludes `padded`. A row that
fails it fails the case and is left out of the grid, so a missing combination cannot pass
silently. The case also confirms the check rejects a row missing its injector, a row missing
its mode list, and, for each fail-closed kind, a row that excludes it. A new number source is one row.

The grid proves only the sources in its table. The other snapshot scalars (`*_TOTAL` and the id
tokens) are not read through `read_decimal`, are not in the table, and the grid claims nothing
about them.

## Quiet-exit check

`pr-change-detect-poll.sh --check <OWNER> <REPO> <PR> <MAX_WATCH> <INTERVAL> <FILTER> <SELF> <SEED>`
is the one-shot compare the skill runs against the pending seed before a watch goes quiet. It takes
ONE capture through the poll's own query path, decides through the poll's own `iteration_marker`,
and prints exactly one line (`STATE=MERGED`, `STATE=CLOSED`, `REVIEWER_APPROVED`, `CI_FAILED`,
`CHANGED`, or `UNCHANGED`), exit 0. A seed whose `failed_checks` field is not all digits is
`CHECK_ERROR`, exit 1, before any `gh` call (`ci:seed-non-digit-failed-checks-fails-closed`). A missing or malformed seed is `CHECK_ERROR`, exit 1, before any `gh` call; a
failed capture is `CHECK_ERROR`, exit 1, never retried. Each case reads the fake `gh` call counters
to pin the number of captures.

- `check:delta-after-pending-seed-detected` — the bite: a `re-arm` seed captured over the
  pre-cycle-0 state with a bot 👍, then a new bot issue comment, prints exactly `CHANGED`,
  exit 0, in one capture. A script with no `--check` mode reads the flag as `OWNER` and prints
  `POLL_ERROR`.
- `check:no-delta-unchanged` — the same seed over the unchanged state prints exactly `UNCHANGED`,
  exit 0, in one capture.
- `check:parity-with-poll-first-iteration` — against a `re-arm` seed captured over the green
  pre-cycle-0 state with no reaction: a `*_TOTAL` tripwire delta (`CHANGED`), a `FAILED_CHECKS`
  rise (`CI_FAILED`), a merged PR, a closed PR, an approval rise, and no delta; and against a red
  `re-arm` seed, the green state, a `FAILED_CHECKS` drop (`CHANGED`). For each row the check's line
  equals the expected marker AND the first line a poll armed with the same seed prints over the
  same state (its `WATCH_TIMEOUT` read as `UNCHANGED`); each check exits 0 in one capture.
- `check:fails-closed` — a failed snapshot query, a missing seed, and a malformed seed each print
  exactly `CHECK_ERROR`, exit 1; the failed query is not retried, and neither seed failure reaches
  `gh`.

## The second bite: the seed's state model (PR #361)

The seed originally serialized 8 of the 9 scalars the poll diffs, omitting the approval bool
(then a single-reviewer 👍 bool, field `codex`; now `approval`). That
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

Offline — bash + `jq` only, no `gh`, no network, ~4 min. A PATH-shim fake `gh` serves canned
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
| `graphql-pre-cycle0.json` | State A — the PR as it stood before cycle 0 (two User-typed self issue comments, one Bot-typed review and its `COMMENTED` `latestReviews` entry carrying one inline comment, one Bot-typed thread, checks green). |
| `graphql-blind-window.json` | State B — A plus the bot's review + review-thread comment posted during the blind window; its `latestReviews` entry still carries one inline comment. |
| `graphql-malformed.json` | A GraphQL `NOT_FOUND` error response (`errors` array, null `pullRequest`) that the snapshot capture rejects. |
| `reactions-none.json` | Raw REST reactions page with no reaction (`[]`). |
| `reactions-codex.json` | Raw REST reactions page with one +1 from `chatgpt-codex-connector[bot]`, in the shape the REST endpoint returns for a bot reactor (`user.type` `User`, plus `id` and `user_view_type`). The runner's `bot_thumbs_up` derives every other bot's 👍 from it. |
| `reactions-human.json` | Raw REST reactions page with two User-typed +1s (`chatgpt-codex-connector`, `claude`) that must never approve. |
| `reactions-forged.json` | Raw REST reactions page with one User-typed +1 whose login is `chatgpt-codex-connector[bot]`, a TAB, and `Bot`; it must never approve. |
| `reactions-codex-eyes.json` | Raw REST reactions page with one `eyes` reaction from `chatgpt-codex-connector[bot]`, in the same REST bot-reactor shape (`user.type` `User`); it must never approve. |

The `graphql-*.json` files are whole GraphQL responses shaped to the script's own query; every
author (issue comments, reviews, and review-thread comments) carries `__typename` (`Bot` for
automated reviewers, `User` for humans and the self login) because every author selection requests
it and the module's self, filter, and Automated Reviewer tests are all type-gated. Every
`graphql-*.json` state other than the malformed one carries a `latestReviews` connection, because
the poll reads review approval from it and a missing connection fails the capture. Each
committed `latestReviews` entry carries `comments.totalCount`, its inline review comment count.
The bot `APPROVED`, `COMMENTED`, superseded, window-overflow, and mixed-review states are derived
in the runner (`derive_fixture`, `bot_review_state`) rather than committed; each adds its bot
review to `reviews` and, where GitHub would report it as that author's latest, to
`latestReviews`. The multi-page `latestReviews` walks are generated in
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
   support, which selects the legacy form; `[filter]` defaults to `automated` when omitted, and an
   explicit `""` passes an empty filter slot) and assert with `pass` / `failed`. Cases that exercise
   behavior which only exists after the fix must branch on `SEED_SUPPORTED` and `skipped` otherwise.
4. A case needing a seed other than the shared `initial` one uses
   `capture_seed <state_name> <arm_kind> <graphql_entry> <reactions_entry> [filter]`, which returns the
   BARE token; `snapshot_raw` is the same call returning raw stdout when the `BASELINE=`/
   `SNAPSHOT_ERROR` line itself is the assertion.
5. Never assert the token's field list scalar by scalar — derive the expected width from
   `DECLARED_FIELD_COUNT` and let `seed:complete-serialization` hold the set equality. A field
   checklist is the shape that let the omitted approval bool ship twice.
6. A `--check` case drives `run_check "$st" [seed] [filter]` (same seed and filter rules as
   `arm_poll`) and reads `gh_call_counts "$st"` (`<graphql> <latestreviews> <reactions>`; one
   capture is `1 1 1`) when the number of captures is part of the assertion.
