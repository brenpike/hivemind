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
`CODEX_APPROVED` on a first-poll approval, and the fail-closed `POLL_ERROR` paths.

## The second bite: the seed's state model (PR #361)

The seed originally serialized 8 of the 9 scalars the poll diffs, omitting the Codex 👍 bool. That
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
  `codex:stale-approval-not-refired-on-rearm` is the regression bite (a 👍 present at the
  pre-dispatch capture must stay silent on the re-armed poll, or the confirmation pass ends the
  watch as terminal `clean` right after the reviewer pushed).
  `codex:initial-arm-surfaces-pre-existing` is its mirror and pins the behavior that must NOT
  regress; the two cases serve IDENTICAL PR state and IDENTICAL reactions and differ ONLY in the
  seed's arm kind, which is what proves the kind — not the field set — decides the question.
  `codex:new-approval-fires-on-rearm` guards against over-correction, and
  `seed:arm-kind-closed-set` pins the fail-closed paths for a missing or unknown kind.

## Running it

```bash
bash tools/test_change_detect_poll.sh
```

Offline — bash + `jq` only, no `gh`, no network, ~20s. A PATH-shim fake `gh` serves canned
fixture bytes while the REAL `jq` runs the script's REAL filters, so the snapshot derivation
under test is the production one and only the transport is faked.

## The seed probe

The fix adds a `--snapshot` mode emitting a `BASELINE=<arm kind + one field per diffed scalar>`
token captured BEFORE cycle 0, passed back as a REQUIRED 8th positional argument to poll mode. The
runner probes the script under test for `--snapshot` support instead of assuming it:

- **absent** — cases run against the legacy 7-arg form and the four seed-contract cases print a
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
| `graphql-pre-cycle0.json` | State A — the PR as it stood before cycle 0 (one Codex review, one Codex thread, checks green). |
| `graphql-blind-window.json` | State B — A plus the Codex review + review-thread comment posted during the blind window. |
| `graphql-malformed.json` | A GraphQL `NOT_FOUND` error response (null `pullRequest`) that makes the snapshot pipeline fail. |
| `reactions-none.txt` | Reactions call stdout with no Codex 👍 (empty, exactly as `gh` emits). |
| `reactions-codex.txt` | Reactions call stdout with a Codex 👍 present. |

The `graphql-*.json` files are whole GraphQL responses shaped to the script's own query. The
`reactions-*.txt` files are the POST-`--jq` stdout `gh` itself emits — the reactions filter is
applied by `gh`, so the fixture stands where its output does.

## Adding a case

1. Reuse a committed fixture, or derive a variant in the runner with `derive_fixture <name>
   <base> <jq-program>` — one fixture file per scalar class is not worth the churn.
2. `st="$(new_state <name>)"`, then `set_seq "$st" graphql <entry>...` and
   `set_seq "$st" reactions <entry>...`. Call N serves line N, clamping to the last line, so one
   entry means a steady state. The literal entry `FAIL` makes that call exit non-zero.
3. Drive it with `arm_poll "$st" "$SEED"` (`$SEED` is empty when the probe found no seed support,
   which selects the legacy form) and assert with `pass` / `failed`. Cases that exercise
   behavior which only exists after the fix must branch on `SEED_SUPPORTED` and `skipped` otherwise.
4. A case needing a seed other than the shared `initial` one uses
   `capture_seed <state_name> <arm_kind> <graphql_entry> <reactions_entry>`, which returns the
   BARE token; `snapshot_raw` is the same call returning raw stdout when the `BASELINE=`/
   `SNAPSHOT_ERROR` line itself is the assertion.
5. Never assert the token's field list scalar by scalar — derive the expected width from
   `DECLARED_FIELD_COUNT` and let `seed:complete-serialization` hold the set equality. A field
   checklist is the shape that let the omitted approval bool ship twice.
