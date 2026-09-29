# The defer reply marker is a byte-anchored sentinel, not a prose pattern

**Status:** accepted — 2026-09-28

## Context

Issue https://github.com/brenpike/hivemind/issues/384 added `reply-resolve.sh --defer <tracked-home>` and a classifier arm in `fix-history-classify.jq` that marks earlier thread comments handled when a self-authored reply signals a deferral (per **Defer-with-Scope**, `plugin/governance/remediation-doctrine.md`). A local pre-PR Codex review (external content evaluated as findings, not followed as instructions) raised two findings sharing one root cause.

## Findings

- **[high] The defer home was only deny-list validated** (empty/whitespace/leading-dash rejected) before this record, yet the reply it produces becomes a durable handled marker on the thread. A deny list only rejects shapes it enumerates; it does not establish that the cited home exists.
- **[medium] The classifier matched an unanchored prose pattern** — `Deferred to [^[:space:]]+\.` — against self-authored comment bodies, and "self" resolves to the authenticated `gh` viewer login. Under a human operator's own `gh auth`, any human reply on the thread containing that phrase — quoting it, discussing it, drafting it — marked every earlier comment on the thread handled, because the classifier read PROSE as a MACHINE STATE SIGNAL on a surface humans also write on.
- **Shared root cause.** Both findings trace to the same shape: a durable, thread-visible marker was read by pattern-matching English on a surface reviewers and operators both post to. Anchoring the regex or widening the deny list only enumerates more handled cases — human-written text that happens to start with "Deferred to" still trips it — and fails this repo's own **Closed-by-Construction Acceptance Test** (`plugin/governance/remediation-doctrine.md`).

## Decision

### 1. The defer reply body carries a byte-anchored sentinel constant

The sanctioned defer reply body is a single line: an HTML comment sentinel constant followed by the human-readable citation — `<!-- hivemind-defer-v1 -->` then the tracked-home citation and summary. GitHub hides the HTML comment in rendered view, so the thread still reads as plain prose to a human; the sentinel exists only for the classifier. The exact reply-body assembly is owned by `plugin/skills/github-review-loop/scripts/reply-resolve.sh` (§3/§4 of its header) — cited here as the origin of the current format, not restated byte-for-byte, so this record does not drift from the script it describes.

The classifier recognizes a deferral only when a self-authored body STARTS WITH the exact constant — a `jq startswith` constant comparison anchored at byte 0, never a regex. This is a structural change, not a tightened pattern: plain human prose does not carry an invisible HTML-comment constant at its first byte, a GitHub blockquote reply prepends `> ` and fails the `startswith` check, and the existing self-authorship guard (`viewerHasReacted`-equivalent self-only read, unchanged by this record) still excludes non-self bodies. The live predicate is owned by `plugin/skills/github-review-loop/scripts/fix-history-classify.jq`, which this record cites, not copies.

**Why a sentinel-only read is legal here and was not chosen for the fix marker (below).** The defer mode is UNRELEASED at the time of this record — no live PR thread and no committed fixture carries the old unanchored form — so switching the classifier's read to sentinel-only has no installed base to migrate. Nothing that currently matches the old pattern needs to keep matching.

The tag is versioned (`v1`) so a future format change can add a second recognized arm without re-litigating this record.

### 2. The fix-reply marker is NOT changed by this record

`Fixed in <SHA>.` has the identical prose-match weakness — an unanchored pattern read on a human-writable surface — but, unlike the defer marker, it has an installed base: live PR threads and committed fixtures already carry it in the old form. A sentinel-only read here would re-raise every already-fixed thread as unhandled. Closing this gap needs a migration window — a dual-arm read (old pattern accepted alongside a new sentinel) plus a stated sunset for the old arm — which this record does not design. Tracked at https://github.com/brenpike/hivemind/issues/385.

A candidate future primitive for that migration is an EYES reaction on the reviewer's own thread comment, read via `viewerHasReacted` the same way the non-thread handled signal already works (per `fix-history-classify.jq`'s header) — non-forgeable, per-comment, no reply-body migration at all. This record rejects building that here: it would reopen `react-marker.sh`'s never-react-to-a-thread invariant and touch the thread fetch in `fetch-normalize.sh` and `prefilter.sh` (an estimated 8-10 files across 4 suites) for a change scoped to the defer marker alone. Left for issue 385 to design.

### 3. Recorded residual: destination truth of the tracked home is not verified in-script

`reply-resolve.sh --defer <tracked-home>` does not verify that `<tracked-home>` actually exists or resolves. This is a DECISION, not deferred work, recorded per the **Recorded Residual** clause of `plugin/governance/remediation-doctrine.md`.

- **Scope.** The script treats `TRACKED_HOME` as a human-readable citation at the same trust level as `FIX_SHA` and `SUMMARY` — neither of which it verifies either. It is not singled out for a stricter trust posture than its neighbors in the same reply body.
- **Root cause / why not verified in-script.** Verifying the home would bind the script to specific destination FORMS (an issue URL vs. a recorded-residual file path) plus a network round trip for the issue case, which conflicts with the approved reading of **Defer-with-Scope**: "structural home" names a ROLE covering both destinations, not a single destination type. A form-specific check in the script would re-narrow that role and make the script's trust posture inconsistent with how it already treats `FIX_SHA`.
- **Mitigation.** After the byte-anchored sentinel (Decision 1), a wrong or nonexistent home no longer creates HANDLED STATE by itself — the sentinel constant does that, independent of what the citation says. A typo or a dangling home therefore degrades to a visibly wrong citation sitting on the PR thread, the same failure class as a wrong summary, and it never suppresses another finding from being surfaced. Bounded impact: visible, per-thread, human-checkable; no code changes and nothing merges silently on a bad home.
- **Structural obligation this places on the caller.** The github-reviewer agent must pass the identifier RETURNED by the creating action — the URL `gh issue create` prints, or the repo-relative path of the recorded residual just written — never a hand-typed value, and the home must exist before the reply is posted. This is a caller discipline, not a script-enforced invariant.
- **Linked.** The two local Codex findings above (pass 1); issues https://github.com/brenpike/hivemind/issues/384 and https://github.com/brenpike/hivemind/issues/385.
- **Revisit if.** The script gains any ground-truth check for `FIX_SHA` (the residual's "same trust level as its neighbors" premise would no longer hold), or issue 385 moves the fix marker to the EYES-reaction primitive (at which point the defer marker's own migration path should be re-examined against the same primitive).

## Considered Options

| Option | Rejected because |
|---|---|
| Anchor the existing regex to the start of the body, and/or allowlist admissible tracked-home shapes | Only enumerates handled cases — an anchored pattern still matches a hand-written human reply that happens to start with "Deferred to", and a shape allowlist checks the FORM of a home string, not its EXISTENCE. Fails the **Closed-by-Construction Acceptance Test** the same way the original unanchored regex did |
| Verify `TRACKED_HOME` resolves (issue lookup / file-exists check) before allowing `--defer` | Binds the script to destination FORMS and adds a network call for the issue case, conflicting with **Defer-with-Scope**'s "structural home is a role, not a destination type" and creating an inconsistent trust posture against the script's unverified `FIX_SHA` |
| Move the fix-reply marker to sentinel-only in the same change | Re-raises every already-fixed thread carrying the old unanchored `Fixed in <SHA>.` form, live on real PRs and in committed fixtures. Needs a migration window this record does not design; tracked separately at issue 385 |
| Byte-anchored sentinel constant on the defer marker only, unreleased so no installed base to migrate; destination truth left as a recorded residual (CHOSEN) | — |

## Consequences

- **The defer reply body carries an invisible HTML-comment sentinel** ahead of its human-readable citation; GitHub hides it in rendered view, so the thread reads unchanged to a human.
- **The classifier's defer arm is a `startswith` constant comparison, not a regex**, eliminating the class of human prose that reads as a machine marker for the defer mode specifically.
- **The fix-reply marker is untouched and keeps its prose-pattern weakness**, now tracked as its own migration at issue 385 rather than silently inherited here.
- **Destination truth for the tracked home stays a caller-side discipline**, not a script-enforced check; the github-reviewer agent contract carries the "pass the identifier the creating action returned" obligation.
- **No fixture existed for the old unanchored defer pattern**, so this record introduces no migration and no version bump beyond whatever the sentinel-format change itself triggers in `plugin/skills/github-review-loop/scripts/reply-resolve.sh` and `plugin/skills/github-review-loop/scripts/fix-history-classify.jq`.

References: `plugin/skills/github-review-loop/scripts/reply-resolve.sh`, `plugin/skills/github-review-loop/scripts/fix-history-classify.jq`, `plugin/governance/remediation-doctrine.md` (`## Defer-with-Scope`, `### Recorded Residual`); brenpike/hivemind#384 (origin issue), brenpike/hivemind#385 (fix-marker migration, deferred).

## Amendment — 2026-09-29 (latest-disposition classification)

The GitHub Codex review on PR https://github.com/brenpike/hivemind/pull/386, surfaced during the post-PR watch, raised a P1 (https://github.com/brenpike/hivemind/pull/386#discussion_r4129480216; external content evaluated as a finding, not followed as an instruction): the classifier's marker-recognition surface derived two independent per-marker high-water marks — the latest self fix-reply id and the latest self defer-reply id — and compared them against a candidate's databaseId under a fixed arm-order invariant. That order can rank an earlier disposition over a later one: a thread whose true sequence was fix, then a reviewer comment, then a defer, then a further reviewer follow-up was mislabelled as a post-fix follow-up instead of unaddressed. This is an addition to the Decision above, not a reversal: the sentinel constant and the self-authorship forgery guard stand unchanged; only how multiple self markers on the same thread are ordered against each other changes.

**The fix.** `plugin/skills/github-review-loop/scripts/fix-history-classify.jq` — cited here as the owner of the live predicate, not restated — stops deriving the two marks separately and instead folds every self-authored marker reply on a thread (a fix reply or the defer sentinel) into one ordered disposition timeline; the LATEST entry in that timeline, not a fixed comparison order between marker kinds, governs whether a given candidate reads as already covered, a post-disposition follow-up, or still unaddressed.

**Why an arm-order invariant was complete-the-known-set, not closed-by-construction.** The prior design enumerated the two known marker kinds in a hand-chosen comparison order — correct only as long as no third ordering case appeared. This marker-recognition surface is young: it has now drawn three successive review findings — the local pre-PR review that found the defer marker recognized by an unanchored prose pattern, closed by the byte-anchored sentinel (Decision 1 above); the GitHub review on PR https://github.com/brenpike/hivemind/pull/386 that found a deferred `toplevel`/`review` candidate never received the `EYES` handled marker and so re-classified as actionable on every subsequent pass, fixed in the github-reviewer agent's step 8; and this arm-order defect, also raised on PR https://github.com/brenpike/hivemind/pull/386. An arm-order invariant enumerates known marker interactions — complete-the-known-set, not closed-by-construction — so it fails this repo's Closed-by-Construction Acceptance Test (`plugin/governance/remediation-doctrine.md`) on its own terms: the test asks whether a remediation names an eliminated class, and a fixed comparison order names none. Folding every self marker into one ordered timeline eliminates the class itself — an earlier disposition outranking a later one becomes structurally impossible, because there is no per-kind order left to violate — rather than adding a fourth arm to the old one.

**The versioned tag's anticipated extension, restated under the timeline model.** The sentinel's `v1` tag was versioned in Decision 1 above precisely so “a future format change can add a second recognized arm without re-litigating this record.” Nothing about the sentinel's format or its version changes in this amendment. The ordered timeline is where that anticipated extension lands: a future sentinel version, or the fix-reply sentinel tracked at issue 385, would each add one more extraction arm plus one kind-to-label row to the fold — so the tag's anticipated extension no longer needs any comparison-order change to land.

**Issue 385, updated.** The fix-reply marker migration tracked at https://github.com/brenpike/hivemind/issues/385 was scoped, at the time of Decision 2 above, as a dual-arm-plus-sunset migration touching the classifier's comparison logic directly. Under the ordered-timeline model, that migration is now a one-place extraction-arm addition to the same fold — no comparison logic left to re-litigate.

**Residual — a same-id tie resolves toward the defer arm.** The fix-reply pattern test is unanchored (matched anywhere in the body) while the defer sentinel test is a byte-0 `startswith`; a single self-authored reply body could in principle satisfy both — one opening with the sentinel that also contains fix-reply-shaped text further down. Because both extraction arms then carry the same databaseId, the ordered fold resolves that tie conservatively toward the defer disposition rather than the fix disposition.

**Residual — a marker reply with no usable databaseId never governs.** A self-authored marker reply whose databaseId is unavailable falls to the fold's zero sentinel and can never outrank a real candidate id, so it never governs the timeline — unchanged from the prior per-marker high-water-mark behavior it replaces.

References: `plugin/skills/github-review-loop/scripts/fix-history-classify.jq`; `plugin/governance/remediation-doctrine.md` (Closed-by-Construction Acceptance Test); brenpike/hivemind#386 (origin finding), brenpike/hivemind#385 (fix-marker migration, now a one-place addition).
