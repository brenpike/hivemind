# Solution design: Idea to Ready

This is the HOW for [docs/prds/idea-to-ready.md](../../prds/idea-to-ready.md), as merged in #626. It does not reopen the PRD. Epic #614 tracks the slices #615 to #624; #627 is this second by-hand pilot. ADRs: [ADR-0046](../../adr/0046-idea-to-ready-process.md) (the idea-to-ready process) and [ADR-0047](../../adr/0047-abathur-council.md) (the Abathur council). The design review record is [review-record.md](review-record.md) in this folder.

## Context and code truth

Checked against main at commit `49787cc9`. Each fact below names what exists today; the components say what changes.

- **Pipeline skills exist.** `hivemind:plan-interrogation`, `hivemind:plan-to-prd`, `hivemind:prd-to-issues` and `hivemind:create-handoff` are all implemented. [CONTEXT.md](../../../CONTEXT.md) still calls the last three "planned skill — not yet implemented"; this pull request's glossary edits fix that.
- **plan-interrogation** holds `Read`, `Write` and `Edit`, and is the named writer of `CONTEXT.md` terms and ADRs. It offers an ADR only when a decision is hard to reverse, surprising without context and a real trade-off. Those three are the ADR conditions this design cites.
- **plan-to-prd** writes a nine-section, WHAT-only PRD to `docs/prds/<slug>.md`. One slug names the plan, the handoff, the PRD and the epic.
- **prd-to-issues** is a leaf skill that names no sibling ([ADR-0013](../../adr/0013-decoupled-leaf-pipeline-skills.md)). Its issue body has exactly four sections: Initiative, What to build, Acceptance Criteria, Dependencies. Blockers are only `#123` refs in the Dependencies section; it writes no native blocked-by edge. `subissue-ops.sh ensure-parent --existing-number <n>` already resolves a known issue as the epic, and `find-by-title` makes a rerun create no duplicates. Its hard rules include "No file paths or code snippets".
- **create-handoff** writes `.hivemind/handoffs/<slug>.md`, which is gitignored. It is session state on one machine and can never be stage evidence.
- **triage-backlog** is user-only (`disable-model-invocation: true`), so no model, the guide included, can start it. It rates seven families (readiness, type, effort, moscow, priority, risk, difficulty). `readiness:ready` is a rubric judgment ("plan clear, no open questions") with no check behind it, and `readiness:blocked` means "would be ready but a dependency blocks it". `triage-ops.sh` has five subcommands: `ensure-labels`, `list-issues`, `apply-labels`, `deps-read`, `deps-add`. `list-issues` returns number, title, labels, body and node id, with no parent or sub-issue fields. `deps-add` writes native blocked-by edges behind the confirm gate. `triage-ops.sh` fails closed when a read's `pageInfo.hasNextPage` is true.
- **decision-autonomy.md, Review Calls** says who decides a reviewer's question. A call is taken when the recommended option is reversible and not architectural (Promotion Gate clauses 1 and 2). It is asked when irreversible, architectural, at strength none, or when the table cell is `surface`. There is no rule for design decisions.
- **Prose budgets.** Measured as CHECK 18 measures (bytes with CR stripped): `plugin/governance/decision-autonomy.md` is 12165 bytes of a 12173 budget (8 bytes free); `plugin/governance/remediation-doctrine.md` is 19901 of 19906 (5 bytes free); `plugin/governance/security-policy.md` is 24143 of 24145 (2 bytes free); `plugin/agents/synapse.md` is 1716 of 1727 (11 bytes free). `plugin/agents/overlord.md` (39038), `plugin/skills/triage-backlog/SKILL.md` (11952), `plugin/skills/prd-to-issues/SKILL.md` (14566) and `plugin/skills/adaptation-cycle/SKILL.md` (5421) are each exactly at their budget. The budgets live in `tests/policy/prose-byte-budget.json`.
- **Built-script budgets.** `plugin/workflows/standard-delivery.js` holds 41976 characters of string and template literals against its 42100 budget in the same file (124 free). It is 190836 characters long against `MAX_BUILT_SCRIPT_LENGTH`, 191000 (164 free). `tools/build_workflows.mjs` enforces both.
- **decision-autonomy-table.json** is version 1, levels `high`, `balanced`, `low` (default `high`), 17 row kinds with cells `auto` or `surface`, and 6 hard stops, `injection_suspect` among them. It has no consult setting.
- **The table projection.** `projectAutonomyTable` in `tools/build_workflows.mjs` keeps only `levels`, `default_level`, `hard_stops` and each row's `kind`, `high`, `balanced` and `low`. `tests/workflow-scripts/build.test.mjs` pins those keys, and `tests/workflow-scripts/data.test.mjs` requires an `auto` or `surface` cell per row per level.
- **decide.js** returns only `ask` or `take`. Its check order is hard_stop, malformed_brief, recommendation_not_an_option, unknown_kind, table_surface, bad_cell, gate_irreversible, gate_architectural, gate_safety, no_recommendation. A weak recommendation is taken ([ADR-0036](../../adr/0036-analysis-only-first-workflow-on-script-engine.md) decision 6). There is no park.
- **Levels.** `resolveLevel` maps an unknown level to `low`, and each workflow resolves the table's default level. The `unattended` level and the park arrive with Lair unattended mode (#607, ADR-0045 decision 6).
- **The closed Ask Set.** `askReasons()` and `listReasons()` are closed lists ([ADR-0037](../../adr/0037-standard-delivery-on-script-engine.md), amendment for issue 549). `pauseDelivery` in `plugin/workflow-src/lib/record.js` refuses an ask whose reason is outside `askReasons()`, pinned by `tests/workflow-scripts/ask-set.test.mjs` and `tests/policy/safety-ask-set.json`.
- **decide() call sites.** `decide()` is called directly in three places: `resolveDecision` in `plugin/workflow-src/lib/plan.js`, `hasDefectQuestion` in `plugin/workflow-src/lib/retry.js` (a planner-question check) and `plugin/workflow-src/analysis-only/main.js`. `plugin/workflow-src/lib/tails.js`, `plugin/workflow-src/standard-delivery/review.js` and pr-feedback-remediation reach it through `resolveDecision`.
- **Shown decisions.** `isShownDecision` in `plugin/workflow-src/lib/record.js` shows the routine kinds `plan_acceptance`, `remediation_plan_acceptance` and `gate_rerun` only when they are listed.
- **decision-brief-schema.json** carries `recommendation.strength` of `strong`, `weak` or `none`, and has no dissent or member provenance fields. Its `gate` is the producer's read of the recommended option only. Options carry `reversible`, `beyond_request` and an optional `destructive` list, but no gate of their own.
- **standard-delivery** resolves every question through `decide()` and pauses through `pauseDelivery`; it has no cumulative pause cap. It stops on a dirty tree (`dirty_paths`, `plugin/workflow-src/lib/facts.js`). plan-interrogation and plan-to-prd hold no git grant and leave the files they write uncommitted.
- **`resume_args`** is `{answers, build}` alone (`plugin/workflow-src/lib/args.js`).
- **The synapse agent** is the haiku runner that relays one committed script. The name Synapse is taken. The earlier council epic #440 (closed) used it for a bioform.
- **The Synapse Runner Gate** (`plugin/hooks/synapse-gate.sh`; `plugin/governance/security-policy.md`, Synapse Runner Gate) admits five scripts: molt, gather-facts, create-working-branch, bump-type and open-plan-pr. `run-review.sh` is not one. Synapse's Write is limited to `.hivemind/molt-inputs-<token>.json` and `.hivemind/pr-inputs-<token>.json`.
- **The tool-neutral review runner** `plugin/skills/adaptation-cycle/scripts/run-review.sh` reads `HIVEMIND_LOCAL_REVIEWER` (the `codex-plugin` preset or a JSON argv list run with no shell). Its prompt is fixed: an adversarial review of a branch diff against `--base`, checked against the findings schema. It cannot carry a decision brief today. The `codex-plugin` preset runs a fixed companion command with no prompt path. Per [ADR-0042](../../adr/0042-tool-neutral-local-review.md) decision 7, Hivemind never names a model.
- **Test homes.** Runner cases live in `tools/test_run_review.sh`; `tests/run-review/` holds only a README. Subissue-ops cases are in `tools/test_subissue_ops.sh` with fixtures in `tests/prd-to-issues/`. Triage-ops cases are in `tools/test_triage_ops.sh` with `tests/triage-backlog/`. Gate cases are in `tools/test_synapse_gate.sh`.
- **cerebrate** is read-only by its `tools:` list (Read, Glob, Grep, LSP, web and claude-mem search). A delegation line `Memory context:` stops its memory search.
- **The overlord's** Agent allowlist in `plugin/agents/overlord.md` holds general-purpose, hivemind:cerebrate, hivemind:drone, hivemind:changeling, hivemind:local-reviewer and hivemind:github-reviewer. Its Write grant covers only fixed-prefix inputs files under `.hivemind/`.
- **ADR-0045 decision 12** keeps any pull request touching a file in its protected-path list out of the auto tier.
- **ADR-0045 decision 10** sets Lair admission: latest ready label from a user with write permission, title and body unedited since, no open blocked-by dependency. This design cites it only as "ADR-0045 decision 10, as amended by #625": #625 adds the epic exclusion and the readiness check at claim time. This design never stamps ADR-0045.
- **Ready Issue** in `CONTEXT.md` requires no open blocked-by dependency. That rule stays: a slice may carry `readiness:ready` with open blockers, but it is a Ready Issue, and claimable, only once they close.
- **No folder** `docs/initiatives/` exists on main before this pull request.

## Components

### Guide skill

A user-only conductor skill (`disable-model-invocation: true`) that runs in the main session. Given nothing, it lists in-flight initiatives with their derived stage. Given an idea, it starts one. Given an initiative, it reports the stage, the evidence found and the next action, then starts that stage without asking to continue. It is written as stage must-haves with judgment, not a numbered state machine. It invokes the leaf skills by intent, and they stay uncoupled. It never applies `readiness:ready`: at the triage stage it tells the maintainer to run `/hivemind:triage-backlog`, which is user-only.

The guide owns the docs branch (#622):

- Before stage 2 writes any tracked file, it creates `docs/<slug>` from the fetched trunk.
- It commits the stage-2 and stage-3 outputs on that branch through `hivemind:molt` with exact paths: the glossary and ADR edits from `hivemind:plan-interrogation` and the PRD from `hivemind:plan-to-prd`. The tree is then clean before stage 4's standard-delivery run, whose `dirty_paths` stop would otherwise refuse it.
- It opens the docs pull request as a draft with no closing keyword.
- It runs the record verify against the pull request head before `gh pr ready`. When it later pushes a change to a stamped path, it returns the pull request to draft.

Docs writing happens in a standard-delivery run on the docs branch, whose steps give a drone exact file scope. The design review runs from the main session between those runs. A standalone idea ends with an issue carrying the spec block, per Standalone spec block format, ready for triage.

### Readiness check

One deterministic shell library, `plugin/skills/_shared/readiness-check.sh`, sourced by each caller's own script entry: a `readiness` subcommand of `triage-ops.sh`, the guide's script and the Lair controller. It reads issues through `gh`. Each caller fetches and passes the remote trunk commit id, never a branch name or local ref. The library rejects a value not matching `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$` before any git call. At that commit it tests existence with `git cat-file -e <commit>:<path>`, reads contents with `git show` and reads blob ids with `git rev-parse`. The Lair passes the commit it spawns the strain from. It checks structure, existence, versions and labels, never quality. It writes nothing.

### Track fact

The track is read, never judged. An issue with a native parent is an initiative slice; any other issue is standalone. The parent must carry `type:epic`, else the slice fails `parent_not_epic`. A standalone issue whose `type:` label is not `bug`, `chore`, `documentation`, `refactor` or `enhancement`, or whose `effort:` label is `l` or `xl`, fails with a promote reason. The type and effort labels are human-confirmed, because triage applies them only after its confirm gate.

### Initiative folder

`docs/initiatives/<slug>/` holds `solution-design.md` and `review-record.md`, with the same slug as `docs/prds/<slug>.md`. The PRD stays in `docs/prds/`. ADRs stay global and numbered in `docs/adr/`.

### Solution design skill

A leaf skill that turns a merged-or-branch PRD into `docs/initiatives/<slug>/solution-design.md` with every section of the solution design template. It applies the design-decision rule and lists each decision with its ADR or the ADR condition it fails. It names no sibling skill. The file itself is written by a drone with exact file scope.

### Design review

A main-session skill that runs fresh read-only cerebrate analysis passes with `Memory context: none`. Round 1 is angles A and B in parallel; a confirming round follows. It records every finding with exactly one disposition. Only the design review's drone step writes or re-stamps a record, and it rewrites the record after every round. It exits per the design review rounds lifecycle.

### Slice design section

`hivemind:prd-to-issues` adds a fifth body section, `## Design`, to each slice, and reuses the initiative's seed issue as the epic through `ensure-parent --existing-number`. A rerun creates no duplicates, through the existing `find-by-title` preflight.

### Triage readiness gate

Triage runs the readiness check on every issue it would propose as `readiness:ready`. The `readiness` subcommand of `triage-ops.sh` takes an overlay, in an inputs file, of the labels and blocked-by edges the pending apply would write, and checks as if they were present. A failing issue never enters the apply set as ready, and its reason codes show in the Notes column. A slice that passes is proposed ready even with open blocked-by links. `readiness:blocked` is kept only for a block with no issue link.

At apply, triage first writes the ratings and, through `deps-add`, the native blocked-by edge for each `#123` ref in a slice's Dependencies section. It then re-runs the check on the live state and applies `readiness:ready` only to issues that still pass. An issue that now fails is dropped from the ready set and named with its reasons.

### Stage derivation and handoff check

A pure function from GitHub and git to a stage and next action, run by the guide's script. Its evidence: the seed issue or epic, the docs branch and its pull request, then trunk, the review record, sub-issues, labels and readiness results. It reads the design's `**Status:** delivered` before record staleness.

- The seed is the one open issue carrying the seed issue marker whose author has write permission.
- Only same-repository pull request heads named `docs/<slug>` or `docs/<slug>-<suffix>` count.
- Fork pull requests, and issues or pull requests by users without write permission, are ignored and named in the report.

Handoff mode passes only when every condition of the PRD's handoff check holds, and reports each slice as claimable now or blocked, with the reason. Per slice it verifies that the latest `readiness:ready` labeled event comes from a user with write permission and that the title and body are unedited since. That is the test of ADR-0045 decision 10, as amended by #625.

### Lair admission

At claim time the Lair controller (#608) runs the readiness check against the trunk commit it will spawn from. It never claims an epic or a failing issue. A failing issue stays unclaimed, with no new label, and is named in the tick's queue report with its reason codes. The queue report shows reason codes encoded as untrusted text. This is ADR-0045 decision 10, as amended by #625; slice #623 implements it.

#623, with the #625 amendment, adds `docs/prds/`, `docs/initiatives/` and `docs/adr/` to the Lair's protected-path list (ADR-0045 decision 12). So a pull request touching them never takes the auto tier.

### Abathur council

Two read-only agents: `abathur` and the council member `overseer` (#618). The caller launches two to four Overseer members, each with an angle and a model, then Abathur. Each member returns one opinion. Abathur weighs the opinions and returns only a recommendation. The caller composes the council's brief, per the council brief contract. Abathur never picks the members it judges.

In the main session the conductor launches them. #622 adds `hivemind:abathur` and `hivemind:overseer` to the overlord's Agent allowlist; its Write grant is unchanged (D23). In standard-delivery the workflow script launches the Claude members, and synapse runs the runner member's committed script (D22). Every member and Abathur delegation carries `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Delegation Data-Boundary Constraint).

### Mid-delivery consult

Inside standard-delivery, the consult step runs before the script acts on a `decide()` result. `decide()` is unchanged. It gains no third action and no `consults_used` input. There is no `council_split` ask reason and no `council` list reason. A strong council result with a clean gate is taken, journaled and shown in the pull request decisions. A split comes back with strength `none`, so it asks `no_recommendation`. In an interactive run the ask carries the dissent. In an unattended run it parks (#607).

### Design-decision rule

An extension of Review Calls in `plugin/governance/decision-autonomy.md` for the design stages. A decision is taken when its recommendation is strong, it is inside the PRD's scope and its gate is clean.

A design decision's gate reads Promotion Gate clause 1, irreversible, and clause 3, safety-relevant. The always-ask list replaces clause 2. So a decision inside the PRD's scope that amends no accepted ADR does not trip it.

These are always asked: a change to the PRD's scope or acceptance criteria, an amendment of an accepted ADR, a trust-boundary, credential or merge-path change, and anything irreversible. A weak or absent recommendation goes to the council first, and a split is asked.

The design stages run no `decide()`. Take or ask is the conductor's judgment, checked by review. The review record lists each taken decision with its always-ask screen: an answer to each of the four always-ask items. The confirming pass checks every screen. A taken decision that should have been asked is a finding (#619).

## State and ownership

No progress state is stored anywhere. Every row below is ground truth in GitHub or git, except the interrogated plan and the consult count, which live only in one session or run.

| State | Home | Writer | Readers |
|---|---|---|---|
| Seed issue, later the epic | GitHub issue, identified by the Seed issue marker and a write-permission author | the guide at capture; `hivemind:prd-to-issues` reuses it | stage derivation, readiness check |
| Interrogated plan | live session, `.hivemind/plans/<slug>.md` | `hivemind:plan-interrogation`, `hivemind:create-handoff` | the same session only |
| PRD | `docs/prds/<slug>.md` | `hivemind:plan-to-prd` | design stages, readiness check |
| Solution design | `docs/initiatives/<slug>/solution-design.md` | a drone with exact file scope | design review, slices, readiness check |
| ADRs | `docs/adr/NNNN-<title>.md` | a drone with exact file scope at the design stage; `hivemind:plan-interrogation` during interrogation | readiness check |
| Review record | `docs/initiatives/<slug>/review-record.md` | the design review's drone step only | readiness check, stage derivation, the design review's verify |
| Slices and blocked-by edges | GitHub sub-issues and issue dependencies | `hivemind:prd-to-issues` (sub-issues); triage `deps-add` (edges) | readiness check, handoff check, the Lair |
| Rating labels | GitHub labels | triage only, behind its confirm gate | readiness check |
| `readiness:ready` | GitHub label | a user with write permission, through triage (D29) | the handoff check, the Lair, under ADR-0045 decision 10 as amended by #625 |
| Consult setting | the `council_consult` object of `plugin/references/decision-autonomy-table.json` | #624, by pull request | the Consult step, the conductor |
| Consults used in a run | never stored: a script-local counter in the standard-delivery script, recomputed as a replay passes the same steps, so `resume_args` stays `{answers, build}`; in the design stages, the conductor's count per guide invocation | the Consult step; the conductor for its own count | the Consult step; the conductor for its own count |

## Contracts and seams

### Readiness check output contract

Output: one JSON line per issue, `{"issue": <number>, "commit": "<evaluated trunk commit id>", "track": "standalone" | "slice", "result": "pass" | "fail", "reasons": [<code>, ...]}`, built with `jq --arg` and `--argjson`, never by splicing text. `reasons` is empty only on a pass.

Exit and failure rules:

- Exit 0 means every issue was evaluated. A missing document is a reason code, never a failure.
- Only an unresolvable commit id or a failed `gh` or `git` process exits non-zero.
- A read is truncated when any `pageInfo.hasNextPage` is true on labels, sub-issues or blockedBy, the rule `triage-ops.sh` already applies. A truncated read exits non-zero.
- Callers discard every line of a run that exits non-zero, and none treats it as a pass.

Reason codes, a closed set:

- Every issue: `issue_closed`, `rating_missing:<family>`, `is_epic`, `is_idea`, `has_subissues`, `no_acceptance_criteria`.
- Standalone: `spec_problem_missing`, `spec_evidence_missing`, `spec_scope_missing`, `open_questions_not_none`, `promote_type`, `promote_effort`.
- Slice: `epic_closed`, `parent_not_epic`, `design_block_missing`, `design_link_invalid`, `prd_missing`, `design_missing`, `record_missing`, `template_section_missing:<name>`, `template_order`, `heading_duplicate`, `design_section_unfilled:<n>`, `design_open_questions`, `adr_missing:<path>`, `adr_not_accepted:<path>`, `record_malformed`, `record_not_passed`, `record_open_blocking`, `record_rounds_exceeded`, `record_stale:<path>`, `record_unstamped:<path>`, `heading_unmatched:<n>`, `heading_ambiguous:<n>`, `dependency_edge_missing:<n>`. `design_block_missing` replaces the earlier `design_section_missing`.

Placeholders:

- In `design_section_unfilled`, `heading_unmatched` and `heading_ambiguous`, `<n>` is the 1-based index of the `- Heading:` line in the issue's Design block, never its text.
- In `dependency_edge_missing`, `<n>` is the number of a Dependencies `#<n>` ref with no native blocked-by edge.
- `<path>` appears only for a path that passed the path allowlist in Slice design section format.
- `<family>` and `<name>` come from closed lists.

An ADR is accepted when its `**Status:**` line's value starts with `accepted`.

### Document parsing rules

These rules serve issue bodies, the solution design and the record body (#615; #619's verify uses them).

- Headings are ATX lines, `#` to `######` then a space, outside fenced code blocks, which open with three backticks or `~~~`.
- Heading text is trimmed, and any trailing run of `#` is stripped.
- A section's body runs to the next heading of the same or a higher level, so subsections are inside it.
- A section is filled when its body holds a non-blank line that is not a heading.

### Standalone spec block format

A standalone issue body carries these sections: `## Problem`, `## Evidence`, `## Acceptance Criteria`, `## Scope boundary`, `## Open questions`. Each must be non-empty, Acceptance Criteria must hold at least one `- [ ]` or `- [x]` item, and Open questions must read exactly `None`.

### Slice design section format

A slice body's `## Design` section holds one item per line:

- `- Solution design: [<path>](<link>)`
- `- Heading: <exact heading text>`, one line per heading
- `- ADR: [<path>](<link>)`, one line per ADR
- `- Review record: [<path>](<link>)`

Link rules, the path allowlist:

- A link is a bare path or `https://github.com/<owner>/<repo>/blob/<trunk>/<path>`.
- The slug matches `^[a-z0-9]+(-[a-z0-9]+)*$`. The Solution design link must resolve to `docs/initiatives/<slug>/solution-design.md`, and the Review record link to `docs/initiatives/<slug>/review-record.md` with the same slug.
- Each ADR link must resolve to a path matching `^docs/adr/[0-9]{4}-[a-z0-9]+(-[a-z0-9]+)*\.md$`.
- The PRD is derived as `docs/prds/<slug>.md`, never read from the issue.
- A link failing any rule yields `design_link_invalid`, and no git call is made for it.
- The record must stamp the PRD and the solution design, else `record_unstamped:<path>`.

Each heading must match exactly one heading of the solution design, at any level, as literal text without `#` marks, per Document parsing rules.

### Seed issue marker

The guide writes `<!-- hivemind-initiative: <slug> -->` as the first line of the seed issue body at capture (#622). #617 keeps the line when it reuses the seed as the epic. Stage derivation (#621) takes as seed only an open issue with that line whose author has write permission. Any other issue carrying it is ignored and named. Two qualifying issues for one slug are ambiguous.

### Solution design template

These `## ` sections, in this order: Context and code truth; Components; State and ownership; Contracts and seams; Trust boundaries; Lifecycle; Existing-path coverage; Failure modes; Decisions; Verification strategy; Seam order; Open questions; Amendments. Every heading in the file is unique. Open questions reads exactly `None`. Amendments may read `None yet.`.

The check parses the file per Document parsing rules:

- A missing `## ` section gives `template_section_missing:<name>`.
- Sections out of order give `template_order`.
- A heading text appearing twice gives `heading_duplicate`.
- An Open questions body other than exactly `None` gives `design_open_questions`.

After close-out the file gains `**Status:** delivered` under its title and an `## As-built deltas` section.

### Review record front matter

The record starts with this front matter, keys in this order, and the check parses only this fixed shape:

```yaml
---
stamps:
  - path: docs/prds/<slug>.md
    blob: <40 or 64 hex blob id>
  - path: docs/initiatives/<slug>/solution-design.md
    blob: <40 or 64 hex blob id>
verdict: pass | fail
open:
  critical: <n>
  high: <n>
  medium: <n>
  low: <n>
rounds: <n>
clean_round: true | false
---
```

Each `blob` is the output of `git rev-parse HEAD:<path>` on the docs branch when the record is written.

- Each blob matches `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$`.
- Each stamp path passes the path allowlist in Slice design section format, else `record_malformed`.
- Stamps must include the PRD, the solution design and every ADR the docs pull request adds or edits, never an ADR it only cites.
- The record passes when `verdict` is `pass`, `open.critical` and `open.high` are 0, `clean_round` is `true` and `rounds` is 2 to 3. Round 1 is always followed by a confirming round.
- `open.<severity>` counts that severity's findings whose disposition is `open`. Any critical or high whose disposition is not `fixed` or `rejected` counts as open.
- A record is authoritative only through a human-reviewed merge (D24). Only the design review's drone step writes or re-stamps it.

Staleness rule: the record is stale when any stamped path's `git rev-parse <commit>:<path>` differs from its blob, or the path is missing. A blob id is a content hash, so the merge method does not matter, and any edit to a stamped file makes the record stale until a review of the change re-stamps it.

### Review record body

The body has these sections:

- `## Reviewed documents`.
- `## Rounds`, with one `### Round <n>` per round naming each pass's reviewer agent, model and angle.
- `## Findings`.
- `## Decisions taken, listed for veto`, each with its always-ask screen.
- `## Decisions asked`, each with the user's answer.

Findings is one Markdown table with the header `| ID | Round | Angle | Severity | Disposition | Note |` and one row per finding:

- ID is unique. Round is the round that disposed the finding.
- Angle is one of `A`, `B`, `confirm` or `review`. `review` marks a finding raised by local review or the post-PR review of the docs pull request.
- Severity is `critical`, `high`, `medium` or `low`.
- Disposition is exactly one of `fixed`, `rejected`, `deferred`, `recorded` or `open`.
- Note holds the summary and, for `rejected`, `deferred` or `recorded`, the reason and destination.

The readiness check never reads the body. The design review skill's `verify` (#619, D28) checks:

- the front matter shape;
- that each stamp equals the blob at the pull request head;
- that the stamps include every ADR the pull request adds or edits, read from its diff against the merge-base with trunk; on trunk, only stamp equality is checked;
- that the Findings table parses, IDs are unique and every row has exactly one disposition from the set;
- that the open counts equal the table under the open rule;
- that `verdict` is `pass` only under the pass rule.

The guide runs verify before `gh pr ready`. `tools/validate.sh` runs it in CI for every record whose verdict is `pass` and whose design is not delivered; #619 maps `docs/initiatives/` to that suite.

### Council brief contract

Input: a decision brief valid against `plugin/references/decision-brief-schema.json`. #618 adds an optional per-option `gate` object with `irreversible`, `architectural` and `safety`. It is the producer's read of that option. Existing briefs stay valid.

Member output: each member returns `{option_id, strength, why}`, with strength `strong`, `weak` or `none`.

Abathur output: Abathur gets the input brief and the opinions as data. It returns only `{option_id, strength, why}`, with strength `strong` or `none`. A split is `none`. A `weak` strength, an `option_id` not among the input's option ids, or any other shape means no council result.

Composed output: the caller composes the output brief. It is the input brief unchanged except `recommendation`, which is Abathur's, plus the optional `council` object:

- `members` has one entry per member that returned a valid opinion. `id`, `angle` and `model` come from the caller's own launch record. `option_id`, `strength` and `why` come from that member's own output.
- `dissent` has one entry per member whose `option_id` differs from the council's: `member_id`, `option_id`, `why`.

No text a member or Abathur writes reaches the gate, options, problem or criticality. A claimed model is ignored. When the council's `option_id` differs from the input's recommended option, the caller sets the composed `gate` from that option's own `gate`. When that option carries none, the caller sets strength `none`, so the call asks.

Schema bounds: `members` holds 2 to 4 items and `dissent` at most 3. Each `why` has maxLength 200 and is described "Written for the user". `id`, `angle` and `model` have maxLength 64. The engine shows only bounded fields written for the user; #618 extends `tests/workflow-scripts/data.test.mjs` for them. A result counts only with at least two members whose `model` values differ.

### Runner member brief mode

The runner member runs only when `HIVEMIND_LOCAL_REVIEWER` is a JSON argv list. Unset or the `codex-plugin` preset means no runner member. The council then needs two Claude members on two Claude models. The runner member's `model` value is `runner:` plus the basename of argv[0]. That names the tool, never a model (ADR-0042 decision 7).

It is a sixth script of the Synapse Runner Gate. #618 edits `plugin/hooks/synapse-gate.sh`, `plugin/governance/security-policy.md` (Synapse Runner Gate), `tests/policy/safety-synapse-gate.json` and `tools/test_synapse_gate.sh`. Synapse's Write allow gains one fixed inputs file, `.hivemind/council-inputs-<token>.json`. It is the only way the brief reaches the script, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Inert Inputs-File Navigator Pattern). The engine reaches the script through synapse. The main-session guide reaches it through its own skill grant.

Per [docs/engineering-principles.md](../../engineering-principles.md) P9 it shares only the runner's kernel with `run-review.sh`. The kernel is:

- the reviewer-setting read and argv check;
- the no-shell argv run under `timeout -k 5 <deadline>`;
- the before/after work-tree check, where any change blocks and discards the opinion;
- the reply JSON extraction.

The kernel moves to `plugin/skills/_shared/`. Review mode's behavior and output do not change, and `tools/test_run_review.sh` stays green. `run-review.sh` still runs every local review (ADR-0042 decision 9).

### Consult setting

A top-level object `council_consult` in `plugin/references/decision-autonomy-table.json`, beside `rows` and never a row. It holds one value per level, `consult` or `skip`, and an integer `per_run_cap`. `rows` and `hard_stops` are unchanged, so no call site can pass it as a kind.

#624 extends `projectAutonomyTable` in `tools/build_workflows.mjs` to project it, and updates `tests/workflow-scripts/build.test.mjs` and `tests/workflow-scripts/data.test.mjs`. #624 sets the `unattended` value and lands after #607 adds that level (ADR-0045 decision 6). In the design stages the conductor reads the value at the table's `default_level`. It allows at most `per_run_cap` consults per guide invocation (#622).

### Consult step

Only standard-delivery runs the step. analysis-only and pr-feedback-remediation carry no council settings, so their call sites resolve through `decide()` alone. `resolveDecision` in `plugin/workflow-src/lib/plan.js` runs the step only when the run carries council settings (#624). `hasDefectQuestion` in `plugin/workflow-src/lib/retry.js` keeps `decide()` alone.

1. Call `decide()` on the input brief with the call site's kind, level and listed.
2. Convene the council only when all of these hold:
   - the result is a take of a `weak` recommendation or an ask with reason `no_recommendation`;
   - the kind is not `plan_acceptance`, `remediation_plan_acceptance` or `gate_rerun`, the routine kinds the record shows only when listed;
   - `council_consult` at the run's level is `consult`;
   - the run's consult count is below `per_run_cap`.

   Otherwise the first result stands. So a hard stop, a malformed brief, `table_surface`, `bad_cell` and every gate trip never reach the council.
3. The count rises by one per convened council, whether or not it returns a result.
4. With no council result, the first result stands.
5. With a council result, call `decide()` on the composed brief with the same kind, level and listed. That result stands.
6. `askReasons()`, `listReasons()`, the check order and `pauseDelivery`'s guard are unchanged. So ADR-0037's closed Ask Set is not amended.
7. The count is a script-local counter. It starts at 0 on each launch and is rebuilt as a replay passes the same steps. `resume_args` stays `{answers, build}` (`plugin/workflow-src/lib/args.js`).

## Trust boundaries

- **External content stays data.** Issue bodies, PRD and design text, review findings, member opinions and Abathur's brief are data per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (External Content Boundary). The readiness check parses fixed shapes and literal heading text and never runs or evaluates content. Links pass the path allowlist before any git call. Reason codes carry line indexes, never issue text. JSON is built with `jq --arg`. The Lair queue report and parks show reason codes encoded as untrusted data, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Trust-Boundary Discipline).
- **Write permission authorizes the ready label.** The authorization is write permission on the latest `readiness:ready` labeled event, with the title and body unedited since (ADR-0045 decision 10, as amended by #625; D29). The handoff check verifies the same (#621), and the Lair keeps its check (#623). "Maintainer" names a role, and triage's confirm gate is a workflow step, not an authorization boundary. The guide and the Lair never apply the label.
- **Reviewers are fresh and read-only.** Review passes run on cerebrate, whose tool list holds no Bash, Write or Edit. `Memory context: none` keeps the writing session's memory from steering a reviewer. A pass that errors, times out or returns unparseable output yields no round.
- **Stamps bind the reviewed content.** The record ships in the same pull request as the design, so it passes the same local review and bot review. Trunk never holds an unreviewed design, and any later edit is detected by blob id. Authority is a human-reviewed merge (D24). Only the design review's drone step writes or re-stamps a record. Verify runs before the pull request leaves draft and in CI (D28). #623 keeps docs paths out of the Lair's auto tier. Recorded residual: with `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a bot approval with no human review of the design. It is recorded per the user's decision, on the ground that it is outside the threat model as the maintainer's own opt-in (ADR-0044). It is bounded because verify keeps a merged record consistent and current (ADR-0046, Residuals).
- **The council cannot widen authority.** `decide()` resolves a caller-composed brief. Abathur writes only a recommendation. Member provenance comes from the caller's launch records. A switched option is gated by its own producer-written gate, or the call asks. The `abathur` and `overseer` tools lists hold no Bash, Write, Edit or agent-launch tool, pinned by a safety fixture under `tests/policy/` (#618). The runner member runs under the kernel's no-shell argv run and before/after check. Member opinions and Abathur's output are injection-scanned. A suspect one ends the consult with no council result and stops at the `injection_suspect` hard stop. That stop is asked in an interactive run and is an approval park in an unattended run (ADR-0045 decision 7) (#618, #624).
- **Unattended runs never decide a split.** A split or always-ask call parks with the brief and dissent. Its text is encoded as untrusted data in the park record (#624, with #607).
- **No new credential and no merge-path change.** Everything runs under the executing user's credentials, and `merge-approved.sh` is untouched. The two trust-boundary changes, a sixth runner-gate script and the overlord's two new agents, were asked (D22, D23).

## Lifecycle

### Initiative stages

1. **Capture.** The guide creates the seed issue. Its body links `docs/prds/<slug>.md`, which may not resolve until the docs merge.
2. **Interrogation.** The guide has created the docs branch before interrogation writes tracked files. `hivemind:plan-interrogation` runs in one session. This is the one single-machine window: its plan lives in the session or `.hivemind/`, so another machine sees only the seed issue.
3. **PRD.** `hivemind:plan-to-prd` writes the PRD on the docs branch `docs/<slug>` or `docs/<slug>-<suffix>`. The guide commits the PRD and the interrogation outputs on that branch.
4. **Solution design and ADRs.** Written on the docs branch by drones with exact file scope.
5. **Design review.** Per the design review rounds below; the record is written on the docs branch.
6. **Docs pull request.** The guide opens it as a draft with no closing keyword. It leaves draft only after verify passes at its head, and merges to trunk. A later push by the guide that changes a stamped path returns it to draft.
7. **Slicing.** `hivemind:prd-to-issues` reuses the seed issue as the epic and adds each slice's design section.
8. **Triage.** The maintainer runs triage; it gates `readiness:ready` on the readiness check and writes native blocked-by edges.
9. **Handoff check.** It passes only when every slice passes, and names each slice as claimable now or blocked.

Stage derivation picks the latest stage whose evidence exists. Evidence it cannot resolve to one answer, such as two seed issues for one slug or two open docs pull requests, is reported as ambiguous and asked, never guessed.

### Design review rounds

Round 1 is two parallel fresh passes: angle A (code truth, governance and ADR conflicts, existing-path coverage) and angle B (failure modes, trust and injection, testability). Findings are fixed on the docs branch. Each later round is one fresh confirming pass over both angles. A pass that errors, times out or returns output the skill cannot parse yields no round and is re-run. Only a completed pass whose parsed list of new findings is empty makes a clean round. The review exits only with zero open critical or high findings and one clean round, so a passing review has 2 or 3 rounds. A review that has not converged after round 3 stops and reaches the maintainer as a signal to split the initiative. Every finding gets exactly one disposition: `fixed`, `rejected` with its reason, `deferred` or `recorded`. Critical and high findings are only `fixed` or `rejected`. Mediums follow `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Defer-with-Scope, Recorded Residual).

The drone rewrites the record after every round: `verdict` stays `fail` until exit, and `rounds`, the open counts and the Findings table stay current. A lost session resumes from the record's rounds.

### Re-review and re-stamp

- Review fix: when local review or the post-PR review changes a stamped document after the review exited, the design review runs one fresh confirming pass over the diff since the stamped blobs. With no new finding the drone re-stamps, and the pass is appended under Rounds as a confirming pass that does not change `rounds` and does not count toward the cap. With a new finding it becomes a re-review.
- Re-review after an amendment: fresh passes run over the diff since the stamped blobs, with rounds counted from 1 for that review. The front matter is replaced, and the body history is appended under a dated heading.

### Close-out

When every slice is done, the solution design gains `**Status:** delivered` and an `## As-built deltas` section in one docs pull request, and is never maintained afterward. The truth then lives in code, ADRs, the glossary and governance.

Close-out edits the stamped design, so its record goes stale by design. Stage derivation reads `**Status:** delivered` first, and a delivered design's record is never re-stamped.

## Existing-path coverage

One row per existing path, with its effect and the slice that makes it. "Unchanged" rows name the slice that relies on them, or none.

| Existing path | Effect | Slice |
|---|---|---|
| `plugin/skills/triage-backlog/SKILL.md`, `plugin/skills/triage-backlog/scripts/triage-ops.sh` | Gains the `readiness` subcommand with the overlay, the apply order (ratings and edges, then the re-check, then `readiness:ready`), reason codes in Notes, `readiness:blocked` narrowed to blocks with no issue link, and `deps-add` edges from Dependencies refs. The confirm gate, `triage:locked` and the per-family mutex are unchanged. | #615, #620 |
| `tools/test_triage_ops.sh`, `tests/triage-backlog/` | Gain the readiness gate, overlay and re-check cases. | #620 |
| `plugin/skills/plan-interrogation/SKILL.md` | Unchanged. The guide commits its outputs on the docs branch. | #622 |
| `plugin/skills/plan-to-prd/SKILL.md` | Unchanged. The guide commits the PRD on the docs branch. | #622 |
| `plugin/skills/molt/SKILL.md` | Unchanged. The guide commits through it with exact paths. | none |
| `plugin/skills/prd-to-issues/SKILL.md`, `plugin/skills/prd-to-issues/scripts/subissue-ops.sh` | Gain the `## Design` section, seed reuse through `ensure-parent --existing-number` with the seed marker line kept, and a carve-out of the "No file paths or code snippets" rule for Design links. Idempotency and the four existing sections are unchanged. | #617 |
| `tools/test_subissue_ops.sh`, `tests/prd-to-issues/` | Gain the Design section and seed reuse cases. | #617 |
| `plugin/skills/create-handoff/SKILL.md` | Unchanged. Its handoff is never stage evidence. | none |
| `plugin/governance/decision-autonomy.md`, Review Calls and Tier A | Gains the design-decision rule and one consult-step sentence. The Tier A line "On the script engine, `decide()` asks only for" is unchanged. Each edit fits the byte budget by cutting. | #616, #624 |
| `plugin/governance/remediation-doctrine.md` | No edit planned; the design review skill cites Defer-with-Scope and Recorded Residual. | none |
| `plugin/references/decision-autonomy-table.json` | Gains the top-level `council_consult` object. Rows and hard stops are unchanged. | #624 |
| `tools/build_workflows.mjs` | `projectAutonomyTable` projects `council_consult`. | #624 |
| `tests/workflow-scripts/build.test.mjs`, `tests/workflow-scripts/data.test.mjs` | Pin the projected keys and the setting's values; check the bounded council fields written for the user. | #618, #624 |
| `plugin/references/decision-brief-schema.json` | Gains the bounded `council` object and the optional per-option `gate`. Existing briefs stay valid. | #618 |
| `plugin/workflow-src/lib/decide.js`, `tests/workflow-scripts/decide.test.mjs` | Unchanged. | none |
| `plugin/workflow-src/lib/plan.js` | `resolveDecision` runs the Consult step only when the run carries council settings. | #624 |
| `plugin/workflow-src/lib/retry.js`, `plugin/workflow-src/lib/tails.js`, `plugin/workflow-src/lib/record.js` | Unchanged. `hasDefectQuestion` checks planner questions with `decide()` alone; `tails.js` reaches the Consult step through `resolveDecision`; the `pauseDelivery` guard and `isShownDecision` are unchanged. | none |
| `plugin/workflow-src/lib/args.js` | Unchanged; `resume_args` stays `{answers, build}`. | none |
| `tests/policy/safety-ask-set.json`, `tests/workflow-scripts/ask-set.test.mjs` | Unchanged and green. | none |
| `plugin/workflow-src/standard-delivery/` | Gains the council settings, the council launch and the consult count. The pause contract is unchanged, and the built script stays within its literal and length budgets. | #624 |
| `plugin/workflow-src/analysis-only/`, `plugin/workflow-src/pr-feedback-remediation/` | Unchanged; they carry no council settings, so they never consult. | none |
| `plugin/hooks/synapse-gate.sh`, `plugin/governance/security-policy.md` (Synapse Runner Gate), `tests/policy/safety-synapse-gate.json`, `tools/test_synapse_gate.sh` | Gain the sixth runner script and synapse's `.hivemind/council-inputs-<token>.json` Write. | #618 |
| `plugin/agents/synapse.md` | Unchanged. Its name is not reused. | none |
| `plugin/skills/adaptation-cycle/scripts/run-review.sh`, `tools/test_run_review.sh` | The runner kernel moves to `plugin/skills/_shared/`. Review mode is unchanged and its cases stay green. | #618 |
| `plugin/agents/cerebrate.md` | Unchanged; review passes use it with `Memory context: none`. | none |
| `plugin/agents/overlord.md` | The Agent allowlist gains hivemind:abathur and hivemind:overseer. The Write grant is unchanged. | #622 |
| `CONTEXT.md` | This pull request adds the initiative's terms and fixes the stale "planned" notes. | #627 |
| `docs/adr/0045-lair-software-factory.md` | Not edited here; decision 10 is amended by #625. | #625 |
| `tools/validate.sh` | Maps `docs/initiatives/` to the verify suite. | #619 |
| Lair controller, not yet built (#608) | The readiness check is its admission step. Its protected-path list gains `docs/prds/`, `docs/initiatives/` and `docs/adr/` under the #625 amendment. | #623 |
| Lair initiative, epic #603 | The PRD's Lair retrofit criterion is covered by #625, the first pilot. #625's acceptance criteria verify it: the record passes with stamps equal to trunk, and every Lair slice passes the readiness checklist by hand. Once #615 and #620 land, triage's readiness gate also checks the Lair slices before any is labeled ready under the new rule. | #625 |

## Failure modes

| Failure | Handling | Slice |
|---|---|---|
| A stamped document is edited after review | The record is stale (`record_stale:<path>`) until a review of the change re-stamps it; every slice fails the check meanwhile. | #615, #619 |
| A merge conflict resolution edits a stamped document | Same as above, seen on trunk; a follow-up docs pull request re-reviews and re-stamps. | #615, #619 |
| A passing record goes stale on a later push | Verify fails in CI, and the guide returns the pull request to draft. | #619, #622 |
| #625 merges first and changes ADR-0045 | No effect: this design cites ADR-0045 decision 10 by number and never stamps ADR-0045. | #625 |
| ADR number 0046 or 0047 is taken on main | Checked before the pull request opens and before it leaves draft; the ADR is renumbered and every link updated. | #627 |
| A design review pass errors, times out or returns unparseable output | It gives no round and is re-run. | #619 |
| A session is lost mid-review | The next session resumes from the record's rounds. | #619 |
| Local review or a post-PR fix changes a stamped document | One confirming pass over the diff, then a re-stamp; the pass does not count toward the cap. A new finding makes it a re-review. | #619 |
| The design review does not converge by round 3 | It stops and reaches the maintainer as a signal to split the initiative. | #619 |
| `gh` or `git` fails, or a read is truncated | The check exits non-zero; no caller reads it as a pass, and the Lair leaves the issue unclaimed. | #615, #623 |
| A linked document is missing | A reason code; the run continues to the next issue. | #615 |
| A caller passes a branch name, a local ref or a malformed id | Rejected before any git call. Callers pass the fetched remote commit id, so a stale local ref is never read. | #615, #620, #621, #623 |
| Link or heading text in an issue body is hostile | A link failing the path allowlist gives `design_link_invalid` with no git call. Heading codes carry the line index, never the text. | #615 |
| A named heading matches zero or several headings | `heading_unmatched` or `heading_ambiguous`; the slice fails. | #615 |
| The review record's front matter is off its shape | `record_malformed`; the slice fails. | #615 |
| A Dependencies ref has no native blocked-by edge | `dependency_edge_missing:<n>`; triage writes the edge through `deps-add`. | #615, #620 |
| Labels are applied after the check | The overlay checks the pending labels, and the post-apply re-check drops any issue that now fails. | #620 |
| A slice passes with open blockers | It may be labeled ready; the Lair still claims it only when no blocked-by dependency is open. | #620, #623 |
| The issue is edited between the check and the claim | ADR-0045 decision 10's unedited check and the body hash captured at claim time stop it. | #623 |
| A council member fails, times out or returns off schema | Abathur weighs the rest. With fewer than two valid members on two models, or off-schema Abathur output, there is no council result; the first `decide()` result stands. The attempt counts toward the cap. | #618, #624 |
| Abathur picks an option other than the input's recommendation | The caller uses that option's own `gate`; with none, it sets strength `none`, so the call asks. | #618, #624 |
| A member opinion or Abathur's output is injection-suspect | The consult ends with no council result at the `injection_suspect` hard stop: asked in an interactive run, an approval park in an unattended run. | #618, #624 |
| A member claims a model or provenance | Ignored; `id`, `angle` and `model` come from the caller's launch record. | #618 |
| `HIVEMIND_LOCAL_REVIEWER` is unset or the `codex-plugin` preset | No runner member; the council needs two Claude members on two Claude models. | #618 |
| The runner member changes the work tree | The before/after check blocks it, and its opinion is discarded. | #618 |
| The per-run cap is reached | No consult; the first `decide()` result stands. | #624 |
| A council splits in an unattended run | Strength `none`, so `decide()` at the `unattended` level parks it, with the brief and dissent encoded as untrusted data. | #624 |
| Two guide sessions work on one stage | The later one stops and re-derives the stage. | #621, #622 |
| Stage evidence is ambiguous, such as two open docs pull requests | The guide reports it and asks; it never guesses a stage. | #621, #622 |
| A seed-marked issue comes from a user without write permission, or a fork pull request uses `docs/<slug>` | Ignored and named in the report. | #621 |
| An interrogation session is lost | Only the seed issue survives; the guide reports the interrogation stage and restarts it. | #621, #622 |
| A budgeted file cannot fit its budget by cutting | The slice stops and asks the user with the measured size, the budget and the size needed (D20). | every slice |

## Decisions

Taken decisions are listed for veto in the pull request body and the review record. Asked decisions carry the user's answer.

### D1: Guide is a user-only conductor skill

Taken and listed for veto; set by the PRD. A main-session skill, not a workflow (workflows take no input mid-run) and not an overlord section (it would load in every session). ADR-0046.

### D2: Stage derived only from GitHub and git

Taken and listed for veto; set by the PRD. No progress state or pointer is stored. ADR-0046.

### D3: One deterministic readiness check shared by three callers

Taken and listed for veto; set by the PRD. Triage, the guide's handoff check and Lair admission share one check that judges no quality. Lair admission is ADR-0045 decision 10, as amended by #625. ADR-0046.

### D4: Track read from the native parent and labels

Taken and listed for veto; set by the PRD. The track is a native parent epic plus the human-confirmed type and effort labels. ADR-0046.

### D5: Per-initiative docs folder

Taken and listed for veto; set by the PRD. `docs/initiatives/<slug>/` holds the solution design and review record; the PRD stays at `docs/prds/<slug>.md`. ADR-0046.

### D6: Design review by fresh read-only planner passes

Taken and listed for veto; set by the PRD. Fresh cerebrate passes with `Memory context: none`, angles A and B in parallel, a confirming round, exit at zero open critical or high and one round with no new findings, capped at three rounds. ADR-0046.

### D7: Review record front matter with blob stamps

Taken and listed for veto; set by the PRD. The fixed front matter and its staleness rule. ADR-0046.

### D8: Ready label allowed with open blockers

Taken and listed for veto; set by the PRD. A passing slice is ready with open blocked-by links; `readiness:blocked` is kept for blocks with no issue link. Ready Issue keeps its no-open-blocked-by rule. ADR-0046.

### D9: Design-decision always-ask rule

Taken and listed for veto; set by the PRD. Review Calls gains the rule in the design-decision rule component. ADR-0046.

### D10: Delivered design frozen as history

Taken and listed for veto; set by the PRD. Close-out adds the delivered status and as-built deltas, then the file is never maintained. ADR-0046.

### D11: No dedicated different-model design pass in v1

Taken and listed for veto; set by the PRD. ADR-0046 records it as a deferred option. It fails hard to reverse, because the record already names each pass's reviewer, so a pass can be added later with no schema change.

### D12: Abathur council with two callers

Taken and listed for veto; set by the PRD. One decision service called from the design stages and from standard-delivery. The caller launches two to four Overseer members, then Abathur. A council result needs at least two members with different `model` values from the caller's launch record. A runner member joins only when `HIVEMIND_LOCAL_REVIEWER` is a JSON argv list. ADR-0047.

### D13: Consult setting as data with a per-run cap

Taken and listed for veto; set by the PRD. The convening rule is the top-level `council_consult` object in the autonomy table, beside `rows` and never a row, per Consult setting: one value per level and an integer `per_run_cap`. Hard stops, `table_surface` asks and promotion-gate trips are never consulted. ADR-0047.

### D14: Council member named Overseer

Taken and listed for veto. Synapse is now the runner agent, so the member takes a new name. ADR-0047.

### D15: Drone with exact file scope writes designs and records

Taken and listed for veto. Solution designs, review records and design-stage ADRs are written by a drone with exact file scope; `hivemind:plan-interrogation`'s writer exception is not extended. ADR-0046 (decision 11).

### D16: Process and council get separate ADRs

Taken and listed for veto. ADR-0046 records the process and ADR-0047 the council, so the council can be amended alone. ADR-0047 records it among its considered options.

### D17: Readiness check is a shared library

Taken and listed for veto. `plugin/skills/_shared/readiness-check.sh` is sourced by each caller's own script, so no skill calls another's script. ADR-0046 (decision 3).

### D18: Initial consult setting values

Taken and listed for veto. `consult` at `high`, `balanced` and `unattended`, `skip` at `low`, `per_run_cap` 2. #624 sets the `unattended` value after #607 adds that level. A run at `low` asked to be asked; each consult costs at least three agent runs. No ADR: fails hard to reverse, because the values are table data.

### D19: Native blocked-by edges written at triage

Taken and listed for veto. Triage writes the edge for each Dependencies ref through `deps-add`, behind its confirm gate; `hivemind:prd-to-issues` keeps body refs. ADR-0046 (decision 4).

### D20: Prose budget with no pre-approved raise

Asked, answer Q1 B: no budget raise is pre-approved. A slice fits every budgeted file it edits by cutting, measured as that file's check measures. If it cannot, it stops and asks the user with the measured size, the budget and the size needed. The budgets the slices meet:

- `plugin/governance/decision-autonomy.md`, 12173 bytes (#616, #624).
- `plugin/governance/security-policy.md`, 24145 bytes (#618).
- `plugin/agents/overlord.md`, 39038 bytes (#622).
- `plugin/skills/triage-backlog/SKILL.md`, 11952 bytes (#620).
- `plugin/skills/prd-to-issues/SKILL.md`, 14566 bytes (#617).
- `plugin/governance/remediation-doctrine.md`, 19906 bytes (any slice that edits it).
- `plugin/workflows/standard-delivery.js`, 42100 characters of string and template literals and the 191000-character `MAX_BUILT_SCRIPT_LENGTH` (#624), both enforced by `tools/build_workflows.mjs`.

A new file takes a new budget entry, which needs no raise. This pull request edits nothing under `tests/policy/`. No ADR: fails hard to reverse, because a raise is one user-approved entry in `tests/policy/prose-budget-raises.json`.

### D21: Accepted-ADR amendments recorded in ADR-0047

Asked, answer Q2 A. ADR-0047's status line and decisions record three amendments of accepted ADRs:

- ADR-0026 decision 2: in the design stages and standard-delivery, a weak or absent recommendation with a clean gate goes to the council before defer-or-record.
- ADR-0036 decision 6: a weak recommendation is consulted before it is taken. The consult step runs ahead of an unchanged `decide()`, which stays the only place a decision is resolved.
- ADR-0045 decision 7, worded as first approved: a choice with no recommendation goes to the council before it parks.

None of those three ADR files is edited. Taken and listed for veto, with a strong recommendation: ADR-0037's closed Ask Set and ADR-0042 decision 9 are not amended, because `decide()` and `run-review.sh` keep their contracts (D22, D25). ADR-0047.

### D22: Runner member through a sixth runner-gate script

Asked, answer Q3 A. The runner member runs only when `HIVEMIND_LOCAL_REVIEWER` is a JSON argv list, as a sixth script of the Synapse Runner Gate, per Runner member brief mode. Synapse's Write allow gains one fixed inputs file, `.hivemind/council-inputs-<token>.json`, the only way the brief reaches the script. The script shares only the runner's kernel with `run-review.sh`. ADR-0042 decision 9 is not amended, because `run-review.sh` still runs every local review. ADR-0047.

### D23: Overlord may launch the council agents

Asked, answer Q4 A. #622 adds `hivemind:abathur` and `hivemind:overseer` to the overlord's Agent allowlist, and its Write grant is unchanged. A safety fixture under `tests/policy/` pins both agents' tools lists with no Bash, Write, Edit or agent-launch tool (#618). ADR-0047.

### D24: Review record authority is a human-reviewed merge

Asked, answer Q5 A. A review record is authoritative only through a human-reviewed merge, and only the design review's drone step writes or re-stamps it. #623, with the #625 amendment, adds `docs/prds/`, `docs/initiatives/` and `docs/adr/` to the Lair's protected-path list, so a docs pull request never takes the auto tier. Recorded residual: with `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a bot approval with no human review of the design. ADR-0046 (decision 7 and Residuals).

### D25: Consult step with decide unchanged

Taken and listed for veto. The consult step calls `decide()` first and convenes the council only on a weak take or a `no_recommendation` ask. With a council result, a second `decide()` on the composed brief stands, per Consult step. `decide()`, the Ask Set, the list reasons, the check order and `resume_args` are unchanged. ADR-0047.

### D26: Caller composes the council brief

Taken and listed for veto. Abathur writes only the recommendation, member provenance comes from the caller's launch records, and a switched option takes its own producer-written gate or asks, per Council brief contract. Its always-ask screen: it narrows the council's authority within this unmerged design, so it widens no trust boundary and amends no accepted ADR. ADR-0047.

### D27: Design-stage resolution is judgment checked by review

Taken and listed for veto. The design stages run no `decide()`. Take or ask is the conductor's judgment under the design-decision rule. The review record lists each taken decision with its always-ask screen, and the confirming pass checks every screen (#619). ADR-0046.

### D28: Record verified before ready and on every push

Taken and listed for veto. The design review skill's verify checks the front matter, the stamps and the Findings table, per Review record body. The guide runs it before `gh pr ready`, and `tools/validate.sh` runs it in CI on every push for each passing record whose design is not delivered. ADR-0046.

### D29: Write permission is the ready label's authority

Taken and listed for veto. The authorization for `readiness:ready` is write permission on its latest labeled event, with the title and body unedited since. The handoff check verifies it (#621), and the Lair keeps its check (#623). "Maintainer" names a role, and triage's confirm gate is not an authorization boundary. ADR-0046 and ADR-0045 decision 10, as amended by #625.

## Verification strategy

Each slice runs `bash tools/validate.sh --changed` at its validate state. Per slice:

- **#615:** contract tests over recorded issue fixtures for each track and each reason code. Cases include a document edited after stamping, an epic, a standalone issue that must be promoted, a slice with open blockers that passes, hostile link and heading text, a design link and record of different slugs, an unstamped PRD, a missing blocked-by edge, a truncated read, a missing document versus a `git` failure, a malformed commit id, and template order, duplicate heading and missing-section cases.
- **#616:** a fixture run on the Lair PRD yields every template section filled; skill authoring checks prove the skill names no sibling.
- **#617:** `tools/test_subissue_ops.sh` with `tests/prd-to-issues/` fixtures: the Design section, seed reuse with the marker line kept, and no duplicate on rerun. A policy fixture under `tests/policy/` pins the Design section and the Design-link carve-out of the "No file paths or code snippets" rule in `plugin/skills/prd-to-issues/SKILL.md`.
- **#618:** `tests/workflow-scripts/data.test.mjs` checks the schema bounds. Composed-brief tests: a switch to an architectural option asks, a switch to an option with no gate asks, a claimed model is ignored, fewer than two distinct `model` values give no result, and an injection-suspect opinion stops at the `injection_suspect` hard stop. A safety fixture pins both agents' tools lists. `tools/test_synapse_gate.sh` with `tests/policy/safety-synapse-gate.json` covers the sixth script and its inputs file. `tools/test_run_review.sh` stays green.
- **#619:** stamping then verify passes. Each of these fails: an open high, a deferred high, a missing clean round, `rounds` of 1 or 4, an errored pass counted as a round, an unstamped added ADR, and a Findings table that disagrees with the open counts. A resume continues from the record's rounds, a confirming pass flags a taken decision that amends an accepted ADR, and the CI suite fails a stale passing record.
- **#620:** `tools/test_triage_ops.sh` with `tests/triage-backlog/`: the overlay, a post-apply re-check that drops a now-failing issue, edges written before readiness, a failing issue that never enters the apply set as ready with its reasons shown, a passing slice with open blockers proposed ready, and the existing cases.
- **#621:** recorded fixtures for every stage give the expected stage and next action. Cases: `**Status:** delivered` read before staleness, seed identity, fork and non-write evidence ignored and named, the latest-label check, and two open docs pull requests reported as ambiguous. Handoff mode passes only when every slice passes.
- **#622:** the skill is user-only. A live smoke takes a throwaway idea to ready slices: it creates the docs branch, commits the stage-2 and stage-3 outputs so the tree is clean, and runs verify before `gh pr ready`. A fresh session resumes at the derived stage.
- **#623:** a tick contract test where an epic and a stale design are not claimed and are named in the queue report with encoded reason codes, and a docs pull request never takes the auto tier.
- **#624:** `tests/workflow-scripts/` engine tests:
  - consult turns into take, ask or park by session type, and an unattended split parks;
  - the per-run cap holds;
  - hard stops, `table_surface` and gate trips are never consulted;
  - a weak take is confirmed by a strong council, and a split asks `no_recommendation`;
  - analysis-only and pr-feedback-remediation never consult;
  - replay rebuilds the count with `resume_args` `{answers, build}`, and the table projection includes `council_consult`;
  - `tests/workflow-scripts/decide.test.mjs`, `tests/workflow-scripts/ask-set.test.mjs`, `tests/policy/safety-ask-set.json` and case SD-82 in `tests/workflow-scripts/standard-delivery.test.mjs` are unchanged and green.

  One live delivery run resolves a weak-recommendation question through the council.

### Prose budget check

Every slice that edits a file in D20's list measures it as its check measures: bytes with CR stripped for CHECK 18 of `tools/policy_check.sh` against `tests/policy/prose-byte-budget.json`, and literal and script length for `tools/build_workflows.mjs`. It fits by cutting per P25. If it cannot, it stops and asks the user, showing the measured size, the budget and the size needed. A prose budget raise lands only with a user-approved entry in `tests/policy/prose-budget-raises.json`. Governance citations pass `tests/workflow-scripts/governance-section-refs.test.mjs`.

## Seam order

Slices start in this order; a slice waits on its blockers.

| Slice | Blocked by | Headings it implements |
|---|---|---|
| #615 Readiness check | none | Readiness check; Track fact; Readiness check output contract; Document parsing rules; Standalone spec block format; Slice design section format; Review record front matter; D3: One deterministic readiness check shared by three callers; D4: Track read from the native parent and labels; D17: Readiness check is a shared library |
| #618 Abathur council | none | Abathur council; Council brief contract; Runner member brief mode; Trust boundaries; Failure modes; D12: Abathur council with two callers; D14: Council member named Overseer; D22: Runner member through a sixth runner-gate script; D26: Caller composes the council brief |
| #616 Solution design skill and template | #618 | Solution design skill; Initiative folder; Design-decision rule; Solution design template; D5: Per-initiative docs folder; D9: Design-decision always-ask rule; D15: Drone with exact file scope writes designs and records; D20: Prose budget with no pre-approved raise; D27: Design-stage resolution is judgment checked by review |
| #617 Slice design links and seed epic | none | Slice design section; Slice design section format; Seed issue marker |
| #619 Design review and record | #615 | Design review; Design review rounds; Re-review and re-stamp; Review record front matter; Review record body; D6: Design review by fresh read-only planner passes; D7: Review record front matter with blob stamps; D11: No dedicated different-model design pass in v1; D24: Review record authority is a human-reviewed merge; D27: Design-stage resolution is judgment checked by review; D28: Record verified before ready and on every push |
| #620 Triage readiness gate | #615 | Triage readiness gate; Readiness check output contract; D8: Ready label allowed with open blockers; D19: Native blocked-by edges written at triage; D29: Write permission is the ready label's authority |
| #621 Stage derivation and handoff check | #615, #619 | Stage derivation and handoff check; Initiative stages; Readiness check output contract; Seed issue marker; D2: Stage derived only from GitHub and git; D29: Write permission is the ready label's authority |
| #622 Guided initiative command | #616, #617, #618, #619, #620, #621 | Guide skill; Initiative stages; Close-out; Standalone spec block format; Abathur council; Consult setting; D1: Guide is a user-only conductor skill; D10: Delivered design frozen as history; D23: Overlord may launch the council agents; D27: Design-stage resolution is judgment checked by review |
| #623 Lair admission | #615, #608 | Lair admission; Readiness check output contract; D24: Review record authority is a human-reviewed merge; D29: Write permission is the ready label's authority |
| #624 Mid-delivery consult | #618, #607 | Mid-delivery consult; Consult setting; Consult step; Trust boundaries; Failure modes; D13: Consult setting as data with a per-run cap; D18: Initial consult setting values; D20: Prose budget with no pre-approved raise; D21: Accepted-ADR amendments recorded in ADR-0047; D25: Consult step with decide unchanged |

## Open questions

None

## Amendments

None yet.
