# Review Record Format

A design review record is `docs/initiatives/<slug>/review-record.md`, where `<slug>` matches `^[a-z0-9]+(-[a-z0-9]+)*$` and names the PRD `docs/prds/<slug>.md` and the solution design `docs/initiatives/<slug>/solution-design.md`. The PRD's first non-blank line after its title is exactly `**UI:** yes` or `**UI:** no`.

A document exists at a commit only when `git ls-tree --full-tree <commit> -- <path>` prints exactly one entry, with exactly that path, of type `blob` and mode `100644` or `100755`. Its blob id is that entry's object id. A symlink, a submodule, a tree or a path under a symlinked directory reads as missing.

## Front Matter

The record starts with this front matter, keys in this order and indented as shown, one `path` and `blob` pair per stamp, or `stamps: []` with none. Any other shape makes the record malformed.

```yaml
---
stamps:
  - path: docs/prds/<slug>.md
    blob: <blob id>
  - path: docs/initiatives/<slug>/solution-design.md
    blob: <blob id>
verdict: fail
open:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 1
clean_round: false
---
```

- `verdict` is `pass` or `fail`, and `clean_round` is `true` or `false`. Each count and `rounds` is a decimal integer with no leading zero.
- Each `blob` matches `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$`.
- Each stamp `path` appears once and names one document: the PRD, the solution design, an ADR `docs/adr/<NNNN>-<name>.md`, or a UI prototype file, `docs/initiatives/<slug>/prototype/index.html` or `docs/initiatives/<slug>/prototype/notes.md`.

### Stamps

- The reviewed commit is the docs pull request's head commit, recorded before a pass with the checkout clean at it. Each `blob` is its path's blob id at the reviewed commit; a path missing there is not stamped.
- The first record of an initiative stamps the commit round 1 reviewed. A record written with `verdict` `fail` keeps its stamps. Only the record that sets `verdict` `pass` re-stamps, to the commit its clean pass reviewed.
- A passing record stamps the PRD, the solution design, both UI prototype files when the PRD says `**UI:** yes`, and every ADR its docs pull request adds or edits, never an ADR it only cites.
- Staleness: the record is stale when a stamped path's blob id at a commit differs from its `blob`, or the path is missing there. Any edit to a stamped file makes the record stale until a review of the change re-stamps it.

### Pass and Open Rules

- Pass rule: the record passes when `verdict` is `pass`, every open count is 0, `clean_round` is `true` and `rounds` is 2 to 3. `verdict` is `pass` only under this rule.
- Open rule: each `open.<severity>` count equals that severity's Findings rows whose Disposition is `open`. A critical or high row counts as open unless its Disposition is `fixed` or `rejected`.

## Body

The body has these sections, in this order:

- `## Reviewed documents`.
- `## Rounds`: one `### Round <n>` per round, naming per pass its reviewer (cerebrate, or the local review tool's preset or argv list), its model and what it covered. A tool pass's model is the tool's own default unless its argv list sets one. A round whose tool pass was skipped says so. When the diminishing-returns check fired after a round, its `### Round <n>` carries a `Diminishing-returns advisory:` line giving the signals and the maintainer's answer.
- `## Findings`: the Findings table, the only `## Findings` heading.
- `## Decisions taken, listed for veto`: each with its recommendation strength and what it touches: scope, an ADR amendment, trust, credentials or the merge path.
- `## Decisions asked`: each with the maintainer's answer.
- `## Residuals`, optional: each residual's scope, ground, bounded impact and where it is recorded.
- `## History: <date>`, optional, per Re-review.

### Findings Table

The Findings section holds one table and nothing else; with no finding it is empty. The header is exactly `| ID | Round | Angle | Severity | Disposition | Note |`, then a delimiter row, then one row of six cells per finding. A `|` inside a cell is written `\|`.

- ID: non-empty and unique in the table.
- Round: the round that disposed the finding.
- Angle: `A` or `B` for a finding a round-1 cerebrate pass raised: `A` for code truth, conflicts with the project's documented principles, governance and ADR conflicts or existing-path coverage; `B` for failure modes, trust and injection or testability. `confirm` for a finding a confirming round's cerebrate pass raised. `review` for a finding the local review tool pass, local review or the post-PR review of the docs pull request raised.
- Severity: `critical`, `high`, `medium` or `low`.
- Disposition: exactly one of `fixed`, `rejected`, `deferred`, `recorded` or `open`. A critical or high finding is only `fixed` or `rejected`.
- Note: the summary. For `rejected`, the reason, which for a repeat cites the recorded decision it repeats. For `deferred`, the reason and an issue reference `#<n>`, `<n>` a decimal number from 1, checked by shape only. For `recorded`, the reason and the repository path where it is recorded: a Markdown link target, read relative to the record's folder, or a code span, read from the repository root. The path resolves inside the repository, holds no `.git` part and no control character, and names a file present at the pull request head.

## Re-review

Review fix: when a fix changes a stamped document of a passing record after the review exited, a record wave sets `verdict` to `fail` and `clean_round` to `false`, keeping the stamps, `rounds` and the open counts. One confirming pass then runs over the change since the stamped blobs. With no new finding and no earlier finding unfixed, a record-only run re-stamps to the commit that pass reviewed, sets `verdict` to `pass` and `clean_round` to `true`, and appends the pass under Rounds; `rounds` is unchanged. A new finding makes it a re-review.

Re-review after an amendment:

- Passes run over the change since the stamped blobs, with rounds counted from 1, or over the whole documents when no record of the initiative has passed.
- The front matter is reset: `verdict` `fail`, `rounds` 0, every open count 0 and `clean_round` `false`. The stamps are kept.
- The earlier Rounds and Findings move unchanged under one `## History: <date>` section, each heading one level down. When an earlier History section has that date, the new heading gains a short parenthesized suffix, such as `## History: 2026-11-22 (re-review)`.
- Rounds and Findings start empty; the decision lists and Residuals stay current.

## Findings Block

A cerebrate pass returns its findings as one fenced block whose info string is `design-review-findings`:

````text
```design-review-findings
reviewed: <reviewed commit>
unfixed: none
| Angle | Severity | Where | Finding |
| --- | --- | --- | --- |
| A | high | docs/initiatives/<slug>/solution-design.md (Heading) | <finding and its fix> |
```
````

- `reviewed` is the commit the delegation named.
- `unfixed` is `none`, or the comma-separated IDs of earlier Findings rows the pass found unfixed.
- One row per new finding, none when the pass raises none. Angle is `A` or `B` in round 1 and `confirm` in a confirming round; Severity is as in the Findings table.

## Verify

Verify checks each record a pull request adds or edits: the front matter shape, a stamp of `docs/prds/<slug>.md` whose `**UI:**` line is valid at the head, the Findings table, each `deferred` and `recorded` Note, and the open rule. When its `verdict` is `pass`, it also checks the pass rule, that the stamps include both UI prototype files when the PRD says `**UI:** yes` and every ADR the pull request adds or edits, and that each stamp equals its path's blob at the head. Every other record at the head whose `verdict` is `pass` gets stamp equality only, unless its solution design is delivered: the first non-blank line after its title is exactly `**Status:** delivered`. Verify never reads Residuals or History, and prints `record-verify-failed: <record path>` per failing record.
