# Solution design: Idea to Ready

This is the HOW for [docs/prds/idea-to-ready.md](../../prds/idea-to-ready.md), as merged in #626 and amended on main by #640, #641, #642 and #643. It works in a consumer project with only the plugin installed: every capability beyond the plugin, such as CI, a validation suite, a local review tool or a second model, is optional, detected and given a stated fallback (`docs/engineering-principles.md` P26). Its decisions stand except the council, which this pull request removes from the PRD and moves to #638, as the user approved (D32). Epic #614 tracks the slices #615 to #624; #618 and #624 move to the council epic of #638. #627 is this second by-hand pilot. ADR: [ADR-0046](../../adr/0046-idea-to-ready-process.md) (the idea-to-ready process). The design review record is [review-record.md](review-record.md) in this folder. On 2026-11-22 it was amended to add the UI prototype stage of #663 and to apply the Lair design's corrections (Amendments). This initiative's PRD says `**UI:** no`, so it has no UI prototype.

## Context and code truth

Checked against main at commit `49787cc9`; line numbers are at that commit. Each fact below names what exists today; the components say what changes.

- **Pipeline skills exist.** `hivemind:plan-interrogation`, `hivemind:plan-to-prd`, `hivemind:prd-to-issues` and `hivemind:create-handoff` are all implemented. [CONTEXT.md](../../../CONTEXT.md) still calls the last three "planned skill — not yet implemented"; this pull request's glossary edits fix that.
- **plan-interrogation** holds `Read`, `Write` and `Edit`, and is the named writer of `CONTEXT.md` terms and ADRs. It offers an ADR only when a decision is hard to reverse, surprising without context and a real trade-off. Those three are the ADR conditions this design cites.
- **plan-to-prd** writes a nine-section, WHAT-only PRD to `docs/prds/<slug>.md`. One slug names the plan, the handoff, the PRD and the epic.
- **prd-to-issues** is a leaf skill that names no sibling ([ADR-0013](../../adr/0013-decoupled-leaf-pipeline-skills.md)). Its issue body has exactly four sections: Initiative, What to build, Acceptance Criteria, Dependencies. Blockers are only `#123` refs in the Dependencies section; it writes no native blocked-by edge. `subissue-ops.sh ensure-parent --existing-number <n>` already resolves a known issue as the epic, and `find-by-title` makes a rerun create no duplicates. Its hard rules include "No file paths or code snippets".
- **create-handoff** writes `.hivemind/handoffs/<slug>.md`, which is gitignored. It is session state on one machine and can never be stage evidence.
- **triage-backlog** is user-only (`disable-model-invocation: true`), so no model, the guide included, can start it. It rates seven families (readiness, type, effort, moscow, priority, risk, difficulty). `readiness:ready` is a rubric judgment ("plan clear, no open questions") with no check behind it, and `readiness:blocked` means "would be ready but a dependency blocks it". `triage-ops.sh` has five subcommands: `ensure-labels`, `list-issues`, `apply-labels`, `deps-read`, `deps-add`. `list-issues` returns number, title, labels, body and node id, with no parent or sub-issue fields. `deps-add` writes native blocked-by edges behind the confirm gate. `triage-ops.sh` fails closed when a read's `pageInfo.hasNextPage` is true.
- **Triage transport.** triage-backlog passes `apply-labels --targets` as a JSON argument (`plugin/skills/triage-backlog/SKILL.md:231`). Its `allowed-tools` hold no `Edit(.hivemind/` entry.
- **decision-autonomy.md, Review Calls** says who decides a reviewer's question. A call is taken when the recommended option is reversible and not architectural (Promotion Gate clauses 1 and 2). It is asked when irreversible, architectural, at strength none, or when the table cell is `surface`. There is no rule for design decisions.
- **Prose budgets.** Measured as CHECK 18 measures (bytes with CR stripped): `plugin/governance/decision-autonomy.md` is 12165 bytes of a 12173 budget (8 bytes free); `plugin/governance/remediation-doctrine.md` is 19901 of 19906 (5 bytes free). `plugin/skills/triage-backlog/SKILL.md` (11952) and `plugin/skills/prd-to-issues/SKILL.md` (14566) are each exactly at their budget, and `plugin/agents/overlord.md` is 39038 bytes of a 39038 budget (0 bytes free). The budgets live in `tests/policy/prose-byte-budget.json`.
- **Built-script budgets.** Measured at the branch head, whose `plugin/` equals `49787cc9`: literal characters with `countProseCharacters`, exported by `tools/build_workflows.mjs`, against each script's entry in `tests/policy/prose-byte-budget.json`, and length as the string length of the file read as UTF-8 against `MAX_BUILT_SCRIPT_LENGTH`, 191000. `tools/build_workflows.mjs` enforces both. `WORKFLOW_APPROVAL_LIMIT`, 200000, is the length above which the Workflow approval dialog offers only No (`tools/build_workflows.mjs:273-283`), and `MAX_BUILT_SCRIPT_LENGTH` keeps a 9000-character margin below it.
  - `plugin/workflows/standard-delivery.js`: 41976 characters of string and template literals against its 42100 budget (124 free); 190836 characters long (164 free).
  - `plugin/workflows/pr-feedback-remediation.js`: 38053 against its 38200 budget (147 free); 176060 characters long (14940 free).
- **What a built script carries.** A built script carries only the functions and data constants its code reads. The prose measure counts every string literal, data constants included.
- **standard-delivery** stops on a dirty tree (`dirty_paths`, `plugin/workflow-src/lib/facts.js`). plan-interrogation and plan-to-prd hold no git grant and leave the files they write uncommitted.
- **Draft and closing lines.** The standard-delivery `draft` launch arg is absent, true or false, and absent means false (SD-48, `plugin/workflow-src/standard-delivery/contract.js:54`). The pull request body opens with one `Closes #N` line per `plan.closes` number (`renderClosingLines`, `plugin/workflow-src/lib/pr.js:198`), and each number must be a launch reference (`describeClosesProblem`, `plugin/workflow-src/lib/title.js:173`). `open-plan-pr.sh` leaves a reused pull request's title, body and draft state unchanged (`plugin/skills/open-plan-pr/scripts/open-plan-pr.sh:145`).
- **This repository's docs validation mapping.** This repository's own validation suite, `tools/validate.sh`, maps `docs/adr/**` to `policy_check` only, and every other `docs/**` path except `docs/skill-authoring.md` to no suite (`tools/validate.sh:429`).
- **Fix and post-PR commits.** `runValidateGate` (`plugin/workflow-src/lib/gates.js:477`) sends a failed validation to a `validation_remediation` decision (`gates.js:497`). `runFixRound` (`gates.js:420`) then commits the files the fix drone reports through `runCommitStep` (`plugin/workflow-src/lib/commit.js:180`). The validate drone's failures are its own text, under the schema description "Each failing command with its failure output." (`gates.js:217`). pr-feedback-remediation runs the same gate loop (PFR-23) and commits each wave through `runPlanWaves` (`plugin/workflow-src/lib/workers.js:234`, PFR-22), as standard-delivery does. Every other commit route runs outside `runCommitStep`. Known ones:
  - After a refused or blocked launch of any workflow (ADR-0048), or after a started run that fails or ends blocked, the overlord continues on Instinct and commits through `hivemind:molt` (`plugin/agents/overlord.md`, `## Engine` and `## Instinct`). D33 removes the started-run fallback for a run the guide launched.
  - Instinct as a chosen path commits through `hivemind:molt` (`plugin/agents/overlord.md`, `## Instinct`, Delivery).
  - The Reflex tail commits through a `hivemind:molt` checkpoint (`plugin/agents/overlord.md`, `## Reflex (Ledger-Skip)`).
  - The local reviewer commits its own fixes through `hivemind:molt`, on every path. Standard-delivery's review gate passes it `caller_validates` true, so each fix's check is the Worker Self-Check over the files it touched, and the run validates again on its commit (`plugin/workflow-src/standard-delivery/review.js:28-36`, `:215`; `plugin/agents/local-reviewer.md:82-83`).
  - pr-feedback-remediation runs a `hivemind:github-reviewer` fix pass (`plugin/workflow-src/pr-feedback-remediation/main.js:5`, `:95`), as the post-PR watch does. The github-reviewer validates per the Validation Procedure, returns blocked on a failure, and commits its own simple fixes with git (`plugin/agents/github-reviewer.md:76`).
  - `molt.sh` refuses a dirty path outside its file list and has no review record refusal.

  No code refuses a review record path today.
- **Launch args.** The overlord launches standard-delivery with `request` the user's request verbatim, `references` the issue and pull request numbers the request names, and `draft` true only when the request asks for a draft pull request (`plugin/agents/overlord.md:21`). A request that names neither the engine nor Instinct takes the engine only with a `working_branch.base` ref, else the overlord asks (`plugin/agents/overlord.md:67`). `tests/workflow-scripts/overlord-contract.test.mjs` pins those sentences and the Instinct fallback clause.
- **Launch reference text.** `hivemind:gather-facts` carries a named pull request's title, body and conversation comments, not its inline review threads (`plugin/skills/gather-facts/scripts/gather-facts.sh:574-596`). The pass scan (SD-06, `plugin/workflow-src/standard-delivery/contract.js:30`) scans them before planning, and ends the run when it flags an injection suspect. The post-PR watch dispatches only for Bot reviewers (ADR-0043; `plugin/skills/github-review-loop/scripts/prefilter.sh`).
- **Test homes.** Subissue-ops cases are in `tools/test_subissue_ops.sh` with fixtures in `tests/prd-to-issues/`. Triage-ops cases are in `tools/test_triage_ops.sh` with `tests/triage-backlog/`.
- **Navigator checks.** CHECK 14 and CHECK 16 (`tools/policy_check.sh:2283`, `tools/policy_check.sh:3368`) treat a skill whose `allowed-tools` hold an entry starting `- Edit(.hivemind/` as a discovered navigator. One of its scripts must source `containment.sh` in the direct form. `docs/skill-authoring.md` (Covered Navigators) must list it with its Edit glob, and a skill may carry only its own listed glob.
- **cerebrate** is read-only by its `tools:` list (Read, Glob, Grep, LSP, web and claude-mem search, the last used only when claude-mem is installed). A delegation line `Memory context:` stops its memory search. Its own model is `opus` (frontmatter of `plugin/agents/cerebrate.md`).
- **Local review tool.** `hivemind:adaptation-cycle` runs the configured local review tool through `plugin/skills/adaptation-cycle/scripts/run-review.sh` with a `--base` ref and an optional focus, returns normalized findings and fixes none. Its SKILL.md names only the `local-reviewer` agent as its caller (`plugin/skills/adaptation-cycle/SKILL.md:15`). The tool is `HIVEMIND_LOCAL_REVIEWER`, or the `codex-plugin` preset when the Codex plugin is installed; with neither, the review is skipped, never required. Hivemind never names the tool's model (ADR-0042 decisions 2, 6 and 7).
- **Plugin merge paths.** The plugin's one merge today is `plugin/skills/github-review-loop/scripts/merge-approved.sh`, opt-in under `HIVEMIND_AUTO_MERGE` (ADR-0044). The checks in that file are its whole merge rule (`merge-approved.sh:9-11`), it skips a draft (`:22`), and it reads no file of the pull request. The Lair's merge is not built yet: it is the Lair design's merge lane, #605.
- **The overlord's** Write grant in `plugin/agents/overlord.md` covers only fixed-prefix inputs files under `.hivemind/`.
- **ADR-0045 decision 12** keeps any pull request touching a file in its protected-path list out of the auto tier.
- **ADR-0045 decision 10** sets Lair admission: latest ready label from a user with write permission, title and body unedited since, no open blocked-by dependency. This design cites it only as "ADR-0045 decision 10, as amended by #625": #625 adds the epic exclusion and the readiness check at claim time. This design never stamps ADR-0045.
- **Ready Issue** in `CONTEXT.md` requires no open blocked-by dependency. That rule stays: a slice may carry `readiness:ready` with open blockers, but it is a Ready Issue, and claimable, only once they close.
- **No folder** `docs/initiatives/` exists on main before this pull request.
- **UI artifacts.** At main commit `b4138564`, no PRD has a `**UI:**` line and no initiative folder has a `prototype/` folder. The PRD template of `hivemind:plan-to-prd` opens with the `# PRD:` title and its nine sections, with no `**UI:**` line.
- **Prototype exception.** At the same commit, `plugin/skills/plan-to-prd/SKILL.md:122` permits a labelled illustrative code sketch in the `## Solution` or `## Further Notes` of an explicit throwaway prototype or spike initiative's PRD. It is unrelated to this design's UI prototype, which never uses that exception.
- **changeling** handles presentational UI and UX work within explicitly assigned file scope (`plugin/agents/changeling.md`, frontmatter description).
- **Lair claim.** The [Lair design](../autonomous-ready-issue-loop/solution-design.md) takes one snapshot per claim candidate and calls the readiness check with it and the tick's trunk commit, never letting the check read GitHub, and holds every GitHub input of the check in the snapshot's field list ([claim integrity](../autonomous-ready-issue-loop/claim-integrity-design.md), Contracts and seams, "Snapshot" and "Readiness-check call at claim"; "Assumptions about #615"). For a re-claim it passes the snapshot's trunk commit, never the parked head it spawns the strain from. Its merge lane, #605, builds `docs/prds/`, `docs/initiatives/` and `docs/adr/` into the auto-tier script's fixed floor, and #623 builds neither that nor the claim-time call, which #608 builds (Lair design, Seam order, "Cross-epic seams with #614").

## Components

### Guide skill

A user-only conductor skill (`disable-model-invocation: true`) that runs in the main session. Given nothing, it lists in-flight initiatives with their derived stage. Given an idea, it starts one. Given an initiative, it reports the stage, the evidence found and the next action, then starts that stage without asking to continue. It is written as stage must-haves with judgment, not a numbered state machine. It invokes the leaf skills by intent, and they stay uncoupled. It never applies `readiness:ready`: at the triage stage it tells the maintainer to run `/hivemind:triage-backlog`, which is user-only.

The guide owns the docs branch (#622):

- Before stage 2 writes any tracked file, it creates `docs/<slug>` from the fetched trunk.
- It commits the stage-2 and stage-3 outputs on that branch through `hivemind:molt` with exact paths: the glossary and ADR edits from `hivemind:plan-interrogation` and the PRD from `hivemind:plan-to-prd`. The tree is then clean before the first docs-branch standard-delivery run, at stage 4 or 5 of Initiative stages, whose `dirty_paths` stop would otherwise refuse it.
- It launches every standard-delivery run on the docs branch with `draft` true. Its one launch reference, once the docs pull request exists, is that pull request's number, which no run can close: a closing line closes only issues, and a reused pull request keeps its body (`plugin/skills/open-plan-pr/scripts/open-plan-pr.sh:145`). The overlord takes the run's references only from line 2 of the request. So before the docs pull request exists the run has no launch reference, and `plan.closes` can hold none (`describeClosesProblem`). Every later run reuses the pull request, whose body a reuse never changes. So no issue number is ever a launch reference, and the docs pull request never gains a Closes line. It opens as a draft: the first docs-branch run opens it, the UI prototype build run at stage 4 when the PRD says `**UI:** yes`, else the first run of stage 5, and later runs reuse it.
- **Request contract.** Every standard-delivery run the guide launches takes a request in a fixed layout. Line 1 is exactly `hivemind-guide-run: <slug>`, where the slug matches `^[a-z0-9]+(-[a-z0-9]+)*$`. Line 2 is exactly `Docs pull request: #<n>` once the docs pull request exists, where `<n>` is the number of the open same-repository pull request whose head is the docs branch; otherwise it is exactly `Docs pull request: none`. Then come the guide's fixed wording for the stage and then the maintainer's own words, if any. The fixed wording names the script engine; asks for local review off only for the run that writes `verdict` `pass`; names the reviewed commit id for a record wave; and, for a round's fix run, names the round number; for a UI initiative's solution design run, names the approved UI prototype for the design to cite; and for the UI prototype refinement run, the maintainer's own words carry the feedback and the verdict. No review text enters the request: no finding, no quote of one and no summary of one.
- **Findings reach a run only through the docs pull request.** Before a round's fix run, the guide posts that round's design review findings, from every pass, as conversation comments on the docs pull request with `gh pr comment <n> --body-file <file>`. It also posts there any review text it routes that is not already in the pull request's body or conversation comments, such as inline review thread text. It does this from the main session under the executing user's credentials, on the pull request it already writes with `gh pr ready`. The run's one launch reference is that pull request's number, so `hivemind:gather-facts` carries its body and conversation comments as external texts, and the pass scan (SD-06) scans them before planning. A comment the scan flags ends the run, which returns to the guide (D33). The guide names the flagged comment to the maintainer and relaunches only after the maintainer edits or deletes it. The post-PR watch dispatches only for Bot reviewers, so the comment starts no watch fix. The docs pull request exists before any review pass, because the first docs-branch run, at stage 4 or 5, opens it and the design review runs at stage 6.
- **A run that stops returns to the guide.** A standard-delivery run the guide launched that fails or ends blocked returns to the guide, which re-derives the stage; the overlord does not continue it on Instinct. The overlord tells such a run by the marker line opening its `request` launch arg. #622 adds this to `plugin/agents/overlord.md` (`## Engine`): for a request whose line 1 is the marker line, `request` is the guide's composed request, `references` holds only the number of line 2 when line 2 is exactly `Docs pull request: #<n>`, and nothing otherwise, `draft` is true, and a started run that fails or ends blocked returns to the guide. A `Docs pull request:` line anywhere else never reaches `references`. A refused or blocked launch starts no run and still runs on Instinct under ADR-0048. This narrows ADR-0039 decision 4 for guide-launched runs (asked in re-review round 1, answer Q19 A; D33).
- It marks the pull request ready with `gh pr ready` only after verify passes at its head and the record passes the pass rule. Before it launches a run on a docs pull request that is not a draft, it returns the pull request to draft with `gh pr ready --undo`. A push the guide did not launch is caught by the guide's verify before ready and the readiness check, and by verify in the repository's own CI where it adds it.
- **UI prototype stage.** When the PRD says `**UI:** yes` (D37), the guide runs the UI prototype stage after committing the PRD and before any solution design run, per UI prototype, and asks the maintainer for the prototype's approval, the stage's approval gate (D38). At interrogation it makes sure the plan settles whether the initiative has a user-facing UI or UX surface.

Docs writing happens in a standard-delivery run on the docs branch, whose steps give a drone exact file scope, except that a changeling writes the UI prototype's `index.html` within exact file scope (D39). The design review runs from the main session between those runs. A standalone idea ends with an issue carrying the spec block, per Standalone spec block format, ready for triage.

### Readiness check

One deterministic shell library, `plugin/skills/_shared/readiness-check.sh`, sourced by each caller's own script entry: a `readiness` subcommand of `triage-ops.sh`, the guide's script and the Lair controller. It reads issues through `gh`, except in snapshot mode: given a recorded issue snapshot and a trunk commit, it makes no GitHub read of its own, and its GitHub inputs are exactly the snapshot's fields (Readiness check output contract, D40). Lair admission calls it in snapshot mode; triage and the guide read through `gh`. Each caller fetches and passes the remote trunk commit id, never a branch name or local ref. The library rejects a value not matching `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$` before any git call. At that commit it tests existence with `git ls-tree <commit> -- <path>`: a document exists only when that entry is a regular file blob, mode `100644` or `100755`. A symlink, submodule or tree at an allowed path, or a path under a symlinked directory, reads as missing and gives that document's missing code, so no check, stamp, review or slice reads through a link. It reads contents with `git show` and reads blob ids with `git rev-parse`, only for a path that exists by that test. The Lair passes the claim snapshot's trunk commit, the commit a first claim spawns its strain from; for a re-claim it passes the snapshot's trunk commit, never the parked head it spawns the strain from (D40). It reads the PRD's `**UI:**` line (D37) and, on a UI initiative, checks the UI prototype's links, existence and stamps, never its quality. `subissue-ops.sh` of `hivemind:prd-to-issues` also sources the library, for the slicing refusal's record read (#617). It checks structure, existence, versions and labels, never quality. It writes nothing.

### Track fact

The track is read, never judged. An issue with a native parent is an initiative slice; any other issue is standalone. The parent must carry `type:epic`, else the slice fails `parent_not_epic`. A standalone issue whose `type:` label is not `bug`, `chore`, `documentation`, `refactor` or `enhancement`, or whose `effort:` label is `l` or `xl`, fails with a promote reason. The type and effort labels are human-confirmed, because triage applies them only after its confirm gate.

### Initiative folder

`docs/initiatives/<slug>/` holds `solution-design.md`, `review-record.md` and, for an initiative whose PRD says `**UI:** yes`, `prototype/index.html` and `prototype/notes.md` (UI prototype), with the same slug as `docs/prds/<slug>.md`. The PRD stays in `docs/prds/`. ADRs stay global and numbered in `docs/adr/`.

### UI prototype

An initiative whose PRD says `**UI:** yes` has a UI prototype, produced and approved after the PRD and before the solution design (D36). The PRD says WHAT the surface must do, the prototype what it looks like, and the solution design HOW it is built, citing the prototype. Whether the prototype is needed is the PRD's `**UI:**` line, read and never judged (D37). Its two files follow UI prototype format.

- **Build run.** The guide launches one standard-delivery run on the docs branch with `draft` true, per Guide skill. A changeling step writes `prototype/index.html` with 3 to 5 structurally different variants (D39). A drone step then writes `prototype/notes.md`, one section per variant describing it in words, and no `## Verdict` section, so after the build run the stage waits for approval. As the initiative's first docs-branch run, it opens the docs pull request as a draft.
- **Approval.** The maintainer opens the file, reviews every variant and gives feedback on each and a verdict: the chosen variant or the combination wanted, and why. That approval is the stage's approval gate, which the guide asks (D38). A UI choice inside the prototype with a strong recommendation is taken and listed for veto (Design-decision rule).
- **Refinement run.** One standard-delivery run carries the feedback and the verdict as the maintainer's own words in its request (Guide skill). A changeling step folds the verdict into one approved variant in `index.html`, which from then on holds only that variant. A drone step then writes the feedback and the `## Verdict` section into `notes.md`, in the run's last non-record wave. The losing variants stay only in the docs pull request's history, and `notes.md` keeps their descriptions in words, the feedback and the verdict. This departs from the upstream prototype skill, which keeps a prototype off main as throwaway: the approved prototype is a stamped artifact on trunk, because slices link to it and the readiness check verifies it.
- **Review and stamps.** The design review covers the prototype and checks the solution design against it (Design review rounds). A passing record stamps both files (Review record front matter), so an edit to either after stamping makes the record stale. A fix to `index.html` is a changeling wave, and the record wave still runs last.
- **Slices.** Each slice of the initiative links the approved prototype from its Design block as its visual acceptance reference (Slice design section format).
- **Standalone track.** Unchanged. A standalone change whose UI impact needs a prototype is promoted to the initiative track by the existing promote rule.
- **Not the PRD's prototype exception.** The Prototype exception of `hivemind:plan-to-prd` allows a labelled code sketch in the PRD of a throwaway prototype or spike initiative. It is unrelated and unchanged, and never stands in for a UI prototype.

### Solution design skill

A leaf skill that turns a merged-or-branch PRD into `docs/initiatives/<slug>/solution-design.md` with every section of the solution design template. It applies the design-decision rule and lists each decision with its ADR or the ADR condition it fails. It names no sibling skill. The file itself is written by a drone with exact file scope.

### Design review

A main-session skill that runs fresh read-only cerebrate analysis passes with `Memory context: none`. Each round is one fresh pass covering every angle, plus the local review tool pass when the design touches a trust boundary, credentials or the merge path (Design review rounds); a confirming round follows round 1. On an initiative whose PRD says `**UI:** yes`, each round also covers the UI prototype and checks the solution design against it. It runs a later round's pass only when the record's open counts are all 0. It records every finding with exactly one disposition. Only its record step, a standard-delivery wave, writes or re-stamps a record, and it rewrites the record after every round. `runCommitStep` refuses a review record path, compared case-insensitively, in every validation fix-round commit of both workflows and every pr-feedback-remediation wave commit; only a standard-delivery wave may carry one (Review record body). Commits outside `runCommitStep` are a recorded residual (Trust boundaries). A review fix that stales a passing record fails verify, and goes through the confirming pass before the record step re-stamps, per Re-review and re-stamp. Before each pass the guide records the reviewed commit, and the record's stamps follow the stamp rule of Review record front matter. It exits per the design review rounds lifecycle.

### Slice design section

`hivemind:prd-to-issues` adds a fifth body section, `## Design`, to each slice, and reuses the initiative's seed issue as the epic through `ensure-parent --existing-number`. A rerun creates no duplicates, through the existing `find-by-title` preflight. Only on the initiative track, when `docs/initiatives/<slug>/` exists on trunk: on an initiative whose PRD says `**UI:** yes`, each slice's Design block also carries the Prototype line, and `hivemind:prd-to-issues` refuses to slice the initiative while either UI prototype file is missing on trunk or the review record on trunk does not pass with both stamped, read by sourcing the readiness check library (D17). Otherwise `hivemind:prd-to-issues`, a standalone leaf, behaves as today.

### Triage readiness gate

Triage runs the readiness check on every issue it would propose as `readiness:ready`. The `readiness` subcommand of `triage-ops.sh` takes an overlay of the labels and blocked-by edges the pending apply would write, as a `--overlay` JSON argument, the transport `apply-labels --targets` uses: family and value pairs from the seven closed families and issue numbers, so it adds no inputs file and no navigator entry. It checks as if they were present. A failing issue never enters the apply set as ready, and its reason codes show in the Notes column. A slice that passes is proposed ready even with open blocked-by links. `readiness:blocked` is kept only for a block with no issue link.

At apply, triage first writes the ratings and, through `deps-add`, the native blocked-by edge for each `#123` ref in a slice's Dependencies section. It then re-runs the check on the live state with an overlay holding exactly `readiness:ready`, the label it is about to apply; every other family and every edge is read live. Without that overlay a never-triaged issue would fail `rating_missing:readiness`. It applies `readiness:ready` only to issues that still pass. An issue that now fails is dropped from the ready set and named with its reasons.

### Stage derivation and handoff check

A pure function from GitHub and git to a stage and next action, run by the guide's script. Its evidence: the seed issue or epic, the docs branch and its pull request, then trunk, the review record, sub-issues, labels and readiness results. It reads the design's `**Status:** delivered` before record staleness.

On an initiative whose PRD says `**UI:** yes` (D37), the UI prototype stage sits between the PRD stage and the solution design stage, and is entered only then. Its evidence is `prototype/index.html` and `prototype/notes.md` on the docs branch. It waits for approval while `notes.md` has no `## Verdict` section, and it is done when `notes.md` holds a filled one (UI prototype format). A solution design on the docs branch or trunk before that is out of order: the guide reports it and asks, never guessing a stage. A `**UI:**` line with a value other than `yes` or `no` is ambiguous evidence, reported and asked.

- The seed is the one open issue carrying the seed issue marker whose author has write permission.
- Only same-repository pull request heads named `docs/<slug>` or `docs/<slug>-<suffix>` count.
- Fork pull requests, and issues or pull requests by users without write permission, are ignored and named in the report.

Handoff mode passes only when every condition of the PRD's handoff check holds, and reports each slice as claimable now or blocked, with the reason. Per slice it verifies that the latest `readiness:ready` labeled event comes from a user with write permission and that the title and body are unedited since. That is the test of ADR-0045 decision 10, as amended by #625.

Every paged read the guide's script makes (labeled events, edit history, the seed marker search and open docs pull requests) fails when any `pageInfo.hasNextPage` is true; the guide reports the failure and derives no stage, the rule `triage-ops.sh` already applies.

### Lair admission

At claim time the Lair controller runs the readiness check in snapshot mode, with the claim's recorded issue snapshot and the snapshot's trunk commit, the commit a first claim spawns its strain from (D40). The check makes no GitHub read of its own. For a re-claim the Lair passes the snapshot's trunk commit, never the parked head it spawns the strain from. It never claims an epic or a failing issue. A failing issue stays unclaimed, with no new label, and is named in the tick's queue report with its reason codes. The queue report shows reason codes encoded as untrusted text. This is ADR-0045 decision 10, as amended by #625. #608 builds the call at claim. #623 builds no call of its own: its readiness acceptance tests run against #608's call with #615's check.

Lair admission inherits the check's reason codes and path allowlist through the shared library, those this design adds included: the codes join the closed set of Readiness check output contract, and the UI prototype paths join the path allowlist of Slice design section format. The Lair design reads both by those headings.

`docs/prds/`, `docs/initiatives/` and `docs/adr/` are built into the Lair's auto-tier floor by #605 (Lair design, Component "Merge lane and auto tier"; the user's answer 2A of 2026-11-22), not by #623 (D24). So a pull request touching them, UI prototype files included, never takes the auto tier, in any consumer project. #623's docs pull request acceptance test runs against #605's auto-tier script.

### Design-decision rule

An extension of Review Calls in `plugin/governance/decision-autonomy.md` for the design stages. A decision with a strong recommendation is taken and listed for veto in the review record and in a docs pull request comment the guide posts with `gh pr comment`, whatever it touches: PRD scope or acceptance criteria, an amendment of an accepted ADR, a trust-boundary, credential or merge-path change. A design changes nothing until the docs pull request merges, and the maintainer reviews every listed decision at merge. With `HIVEMIND_AUTO_MERGE` set, a design decision taken under the design-decision rule, one touching scope, an ADR, trust, credentials or the merge path included, can merge to trunk with no human seeing it. That is bounded: each is listed for veto in the review record, is reversible by a later docs pull request, and changes no code until a slice builds it.

Besides Tier A, Surface-Growth Escalation and the UI prototype approval gate (D38), only two kinds are asked. A decision with a weak or absent recommendation is asked, never deferred (D32); #638 may change this only by its own ADR. An action that is irreversible now, outside the unmerged pull request, is asked: for example closing or deleting an issue, publishing, a push to trunk.

The UI prototype's approval is not a design decision. It is the UI prototype stage's approval gate, which the guide asks beside the two kinds above (D38). A UI choice inside the prototype with a strong recommendation is taken and listed for veto like any design decision.

The design-decision gate reads Promotion Gate clause 1, irreversible, only, applied to the action taken now, not to what the design proposes. Clauses 2 and 3 are not read for design-stage decisions, because a design proposes changes and performs none. This narrows ADR-0026 decision 3 for design-stage decisions only (previously narrowed by answer Q18 A; D9).

The design stages run no `decide()`. Take or ask is the conductor's judgment, checked by review. The review record lists each taken decision with its recommendation strength and what it touches (scope, ADR amendment, trust, credential, merge path), so the maintainer can veto at merge, or, when `HIVEMIND_AUTO_MERGE` merges it unseen, by a later docs pull request (Trust boundaries). The confirming pass checks that each taken decision had a strong recommendation and took no irreversible action. A taken decision with a weak or absent recommendation is a finding (#619).

## State and ownership

No progress state is stored anywhere. Every row below is ground truth in GitHub or git, except the interrogated plan, which lives only in one session.

| State | Home | Writer | Readers |
|---|---|---|---|
| Seed issue, later the epic | GitHub issue, identified by the Seed issue marker and a write-permission author | the guide at capture; `hivemind:prd-to-issues` reuses it | stage derivation, readiness check |
| Interrogated plan | live session, `.hivemind/plans/<slug>.md` | `hivemind:plan-interrogation`, `hivemind:create-handoff` | the same session only |
| PRD | `docs/prds/<slug>.md` | `hivemind:plan-to-prd` | design stages, readiness check, stage derivation (its `**UI:**` line) |
| Solution design | `docs/initiatives/<slug>/solution-design.md` | a drone with exact file scope | design review, slices, readiness check |
| UI prototype | `docs/initiatives/<slug>/prototype/index.html` and `docs/initiatives/<slug>/prototype/notes.md`, only when the PRD says `**UI:** yes` | `index.html`: a changeling with exact file scope; `notes.md`: a drone with exact file scope (D39) | the maintainer, design review, slices, readiness check, stage derivation, `hivemind:prd-to-issues` |
| ADRs | `docs/adr/NNNN-<title>.md` | a drone with exact file scope at the design stage; `hivemind:plan-interrogation` during interrogation | readiness check |
| Review record | `docs/initiatives/<slug>/review-record.md` | the design review's record step only; `runCommitStep` refuses a review record path, compared case-insensitively, in every validation fix-round commit of both workflows and every pr-feedback-remediation wave commit; only a standard-delivery wave may carry one (#619) | readiness check, stage derivation, the design review's verify, `hivemind:prd-to-issues` (the UI slicing refusal) |
| Slices and blocked-by edges | GitHub sub-issues and issue dependencies | `hivemind:prd-to-issues` (sub-issues); triage `deps-add` (edges) | readiness check, handoff check, the Lair |
| Rating labels | GitHub labels | triage only, behind its confirm gate | readiness check |
| `readiness:ready` | GitHub label | a user with write permission, through triage (D29) | the handoff check, the Lair, under ADR-0045 decision 10, as amended by #625 |

## Contracts and seams

### Readiness check output contract

Output: one JSON line per issue, `{"issue": <number>, "commit": "<evaluated trunk commit id>", "track": "standalone" | "slice", "result": "pass" | "fail", "reasons": [<code>, ...]}`, built with `jq --arg` and `--argjson`, never by splicing text. `reasons` is empty only on a pass.

Exit and failure rules:

- Exit 0 means every issue was evaluated. A missing document is a reason code, never a failure.
- Only an unresolvable commit id or a failed `gh` or `git` process exits non-zero.
- A read is truncated when any `pageInfo.hasNextPage` is true on labels, sub-issues or blockedBy, the rule `triage-ops.sh` already applies. A truncated read exits non-zero.
- Callers discard every line of a run that exits non-zero, and none treats it as a pass.

Input modes (D40):

- Through `gh`, for triage and the guide.
- Snapshot mode, for Lair admission: given a recorded issue snapshot and a trunk commit, the check makes no GitHub read of its own. Its GitHub inputs are exactly the snapshot's fields (Lair claim integrity design, Contracts and seams, "Snapshot"); documents are git objects at the given commit. A field the check needs beyond those is added to that Snapshot list by #615. A snapshot missing a field the check reads exits non-zero, as a failed read does.
- Recorded fixtures for contract tests use snapshot mode. Contract cases for `gh` mode run through a recording `gh` stub, for field mapping and `pageInfo` truncation.

Reason codes, a closed set:

- Every issue: `issue_closed`, `rating_missing:<family>`, `is_epic`, `is_idea`, `has_subissues`, `no_acceptance_criteria`.
- Standalone: `spec_problem_missing`, `spec_evidence_missing`, `spec_scope_missing`, `open_questions_not_none`, `promote_type`, `promote_effort`.
- Slice: `epic_closed`, `parent_not_epic`, `epic_marker_missing`, `design_block_missing`, `design_link_invalid`, `design_slug_mismatch`, `prd_missing`, `prd_ui_invalid`, `design_missing`, `design_delivered`, `prototype_missing`, `record_missing`, `template_section_missing:<name>`, `template_order`, `heading_duplicate`, `design_section_unfilled:<n>`, `design_open_questions`, `adr_missing:<path>`, `adr_not_accepted:<path>`, `record_malformed`, `record_not_passed`, `record_open`, `record_rounds_exceeded`, `record_stale:<path>`, `record_unstamped:<path>`, `heading_unmatched:<n>`, `heading_ambiguous:<n>`, `dependency_edge_missing:<n>`. `design_block_missing` replaces the earlier `design_section_missing`.

Pass-rule codes, one per clause of the pass rule in Review record front matter:

- `verdict` not `pass` gives `record_not_passed`.
- `clean_round` not `true` gives `record_not_passed`.
- `rounds` below 2 gives `record_not_passed`.
- `rounds` above 3 gives `record_rounds_exceeded`.
- Any open count above 0, at any severity, gives `record_open`.

A front matter off its shape, a blob off its pattern or a stamp path outside the path allowlist gives `record_malformed`.

UI codes, read only when the epic's PRD is present:

- The PRD's `**UI:**` line is read per UI prototype format: `yes` makes the initiative a UI initiative; `no`, or no `**UI:**` line, does not; any other value gives `prd_ui_invalid`, and the Prototype line is then not evaluated.
- On a UI initiative, a Design block with no Prototype line, or either UI prototype file missing at the commit, gives `prototype_missing`. A record that does not stamp a UI prototype file gives `record_unstamped:<path>` for it.
- On any other initiative a Prototype line gives `design_block_missing`, and the other codes are unchanged.

Placeholders:

- In `design_section_unfilled`, `heading_unmatched` and `heading_ambiguous`, `<n>` is the 1-based index of the `- Heading:` line in the issue's Design block, never its text.
- In `dependency_edge_missing`, `<n>` is the number of a Dependencies `#<n>` ref with no native blocked-by edge.
- `<path>` appears only for a path that passed the path allowlist in Slice design section format.
- `<family>` and `<name>` come from closed lists.

An ADR is accepted when its `**Status:**` line's value starts with `accepted`.

### Document parsing rules

These rules serve issue bodies, the solution design, the PRD's `**UI:**` line, the UI prototype's `notes.md` and the record body (#615; #619's verify uses them).

- Before any parsing rule of this design, the carriage return ending a line is removed from every line, so a CRLF text parses as its LF form. This covers issue bodies, the seed issue marker line, the solution design and the review record's front matter and body.
- Headings are ATX lines, `#` to `######` then a space, outside fenced code blocks, which open with three backticks or `~~~`.
- Heading text is trimmed, and any trailing run of `#` is stripped.
- A section's body runs to the next heading of the same or a higher level, so subsections are inside it.
- A section is filled when its body holds a non-blank line that is not a heading.

### Standalone spec block format

A standalone issue body carries these sections: `## Problem`, `## Evidence`, `## Acceptance Criteria`, `## Scope boundary`, `## Open questions`. Each must be non-empty, Acceptance Criteria must hold at least one `- [ ]` or `- [x]` item, and Open questions must read exactly `None`.

### Slice design section format

A slice body holds exactly one `## Design` section, with one item per line:

- `- Solution design: [<path>](<link>)`, exactly one line
- `- Heading: <exact heading text>`, at least one line, one per heading
- `- ADR: [<path>](<link>)`, one line per ADR
- `- Review record: [<path>](<link>)`, exactly one line
- `- Prototype: [<path>](<link>)`, exactly one line on a slice whose epic's PRD says `**UI:** yes`, and none otherwise

Any other count of these sections or lines gives `design_block_missing`, except that a UI initiative's slice with no Prototype line gives `prototype_missing`.

The slug is the parent epic's seed issue marker slug, never read from the issue. An epic whose body does not open with a valid seed issue marker gives `epic_marker_missing`.

Link rules, the path allowlist:

- A link is a bare path or `https://github.com/<owner>/<repo>/blob/<trunk>/<path>`.
- The Solution design link must resolve to a path of the shape `docs/initiatives/<s>/solution-design.md`, and the Review record link to `docs/initiatives/<s>/review-record.md`, where `<s>` matches `^[a-z0-9]+(-[a-z0-9]+)*$`.
- Each ADR link must resolve to a path matching `^docs/adr/[0-9]{4}-[a-z0-9]+(-[a-z0-9]+)*\.md$`.
- The Prototype link must resolve to a path of the shape `docs/initiatives/<s>/prototype/index.html`.
- A link failing any shape rule yields `design_link_invalid`.
- A Solution design, Review record or Prototype link whose `<s>` is not the epic's slug yields `design_slug_mismatch`.
- No git call is made for a failing link.
- The PRD is derived as `docs/prds/<slug>.md` from the epic's slug, never read from the issue.
- The PRD path must match `^docs/prds/[a-z0-9]+(-[a-z0-9]+)*\.md$`, both the path derived from the epic's slug and a PRD stamp path.
- The path allowlist's stamp shapes add exactly `docs/initiatives/<s>/prototype/index.html` and `docs/initiatives/<s>/prototype/notes.md`, never a directory prefix; a stamp path outside every shape gives `record_malformed` (Review record front matter).
- The record must stamp the PRD, the solution design and, on a UI initiative, both UI prototype files, else `record_unstamped:<path>`.

Each heading must match exactly one heading of the solution design, at any level, as literal text without `#` marks, per Document parsing rules.

### Seed issue marker

The guide writes `<!-- hivemind-initiative: <slug> -->` as the first line of the seed issue body at capture (#622). The marker slug must match `^[a-z0-9]+(-[a-z0-9]+)*$` before any `git` or `gh` use, else the issue is ignored and named (#621). #617 keeps the line when it reuses the seed as the epic, and #615 binds the epic's slices to its slug. Stage derivation (#621) takes as seed only an open issue with that line whose author has write permission. Any other issue carrying it is ignored and named. Two qualifying issues for one slug are ambiguous.

Epics created before the guide gain the seed marker in #615's delivery, which adds it by hand to epics #603 and #614 before the readiness check is first used to label any slice ready. Until then their slices fail `epic_marker_missing`.

### Solution design template

These `## ` sections, in this order: Context and code truth; Components; State and ownership; Contracts and seams; Trust boundaries; Lifecycle; Existing-path coverage; Failure modes; Decisions; Verification strategy; Seam order; Open questions; Amendments. Every heading in the file is unique. Open questions reads exactly `None`. Amendments may read `None yet.`.

The check parses the file per Document parsing rules:

- A missing `## ` section gives `template_section_missing:<name>`.
- Sections out of order give `template_order`.
- A heading text appearing twice gives `heading_duplicate`.
- An Open questions body other than exactly `None` gives `design_open_questions`.

After close-out the file gains `**Status:** delivered` under its title and an `## As-built deltas` section. A design is delivered when the first non-blank line after its `# ` title line is exactly `**Status:** delivered`. A slice whose design is delivered fails `design_delivered`; stage derivation and verify read the status by the same rule.

### UI prototype format

The PRD's UI line and the UI prototype's two files (D36, D37), parsed per Document parsing rules.

UI line:

- The first non-blank line after the PRD's `# ` title line is exactly `**UI:** yes` or `**UI:** no`. Interrogation settles it, and `hivemind:plan-to-prd` writes it from the plan, asking one targeted question when the plan does not settle it (#622).
- A PRD whose first non-blank line after the title does not start with `**UI:**` reads as `no`, so no PRD stamped before this amendment must change.
- A line there that starts with `**UI:**` with any other value is invalid: the readiness check gives `prd_ui_invalid`, and stage derivation reports it as ambiguous.
- Verify fails a record the pull request adds or edits whose stamped PRD has no valid line, missing or invalid (#619). An initiative whose record is next edited adds the line to its PRD in that pull request, and the review of that change covers it.

`docs/initiatives/<slug>/prototype/index.html`:

- One self-contained HTML file that opens by double-click with no server, build or install. As a build rule, it references no file or URL outside itself and makes no network request; this is not a trust claim, and nothing checks it (Trust boundaries). It needs no design tool, hosted service, build step, framework or account (`docs/engineering-principles.md` P26), and may copy the host app's look when one exists.
- It implements every user story and screen the PRD's UI covers.
- Before the verdict it holds 3 to 5 variants, 3 by default. Each is structurally different in layout, information hierarchy or primary affordance, never only in colour or copy, and variants share no layout code. Two drafts that come out too similar are redone with explicit "do not use <that structure>" guidance.
- The `?variant=` URL parameter chooses the variant, so a variant is shareable and stays the same on reload. A floating bottom-centre bar, visually distinct from the design, shows a previous arrow, the variant key and name (for example `B (Sidebar layout)`) and a next arrow; both wrap. The `←` and `→` keys also cycle, except while an input, textarea or contenteditable element has focus.
- Each variant renders realistic stub data held in memory only: no persistence and no real mutations.
- No polish: no tests and no error handling beyond what makes it run.
- After the verdict it holds only the approved variant.

`docs/initiatives/<slug>/prototype/notes.md`:

- One `## Variant <key>: <name>` section per variant, `<key>` a capital letter from A, describing the variant in words and holding the maintainer's feedback on it. The sections stay after refinement, so each losing variant survives in words.
- One `## Verdict` section naming the chosen variant or the combination wanted, for example "header from B, sidebar from C", and why. The build run writes no `## Verdict` section; the refinement run writes it in its last non-record wave, after the changeling folds the variants into one. Until then `notes.md` has none, and stage derivation reads the UI prototype stage as waiting for approval. Stage derivation reads the stage as done when this section is filled.
- A published link to the prototype may be added; the repository file is the source of truth.

The readiness check reads only both files' existence and stamps, never their content or quality.

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

Stamp rule: before each pass the guide fetches the docs branch, confirms the checkout is clean and at the docs pull request's head commit, and records that commit id, the reviewed commit, which must match `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$`. Each `blob` is the output of `git rev-parse <reviewed commit>:<path>`. One stamp rule decides the reviewed commit: the first record of an initiative stamps the commit round 1 reviewed; a record written with `verdict` `fail` keeps its existing stamps; only the record that sets `verdict` `pass` re-stamps, to the commit its clean pass reviewed.

- Each blob matches `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$`.
- Each stamp path passes the path allowlist in Slice design section format, whose stamp shapes include exactly the two UI prototype files, else `record_malformed`.
- A passing record's stamps include the PRD, the solution design, on a UI initiative both UI prototype files, and every ADR its own docs pull request adds or edits, never an ADR it only cites. A failing record keeps its stamps under the stamp rule, so it may omit an ADR added after them, and verify checks inclusion only when `verdict` is `pass` (Review record body).
- The record passes when `verdict` is `pass`, every open count (`critical`, `high`, `medium`, `low`) is 0, `clean_round` is `true` and `rounds` is 2 to 3. Round 1 is always followed by a confirming round. Each clause gives one reason code, per Readiness check output contract.
- `open.<severity>` counts that severity's findings whose disposition is `open`. Any critical or high whose disposition is not `fixed` or `rejected` counts as open.
- A record is authoritative only through a human-reviewed merge (D24). Only the design review's record step writes or re-stamps it. `runCommitStep` refuses a review record path, compared case-insensitively, in every validation fix-round commit of both workflows and every pr-feedback-remediation wave commit; only a standard-delivery wave may carry one, per Review record body. The github-reviewer commits its own simple fixes with git, outside the workflow scripts: the Validation Procedure it loads forbids a fix that edits a record, and any record edit is authoritative only through the human-reviewed merge. Commits outside `runCommitStep` are a recorded residual (Trust boundaries).

Staleness rule: the record is stale when any stamped path's `git rev-parse <commit>:<path>` differs from its blob, or the path is missing. A blob id is a content hash, so the merge method does not matter, and any edit to a stamped file makes the record stale until a review of the change re-stamps it.

### Review record body

The body has these sections:

- `## Reviewed documents`.
- `## Rounds`, with one `### Round <n>` per round naming, per pass, its reviewer (the agent, or the local review tool's preset or argv list), its model and what it covered. When a round needs the local review tool pass and no tool is configured, it says the tool pass was skipped. When the diminishing-returns check (D35) fired after a round, its `### Round <n>` carries a `Diminishing-returns advisory:` line giving the signals and the maintainer's answer. Verify does not parse that line.
- `## Findings`.
- `## Decisions taken, listed for veto`, each with its recommendation strength and what it touches.
- `## Decisions asked`, each with the user's answer.
- `## Residuals`, optional: each residual's scope, ground, bounded impact and where it is recorded.
- `## History: <date>`, optional, one per earlier review, per Re-review and re-stamp.

Verify reads neither optional section, and parses only the table under `## Findings`.

Findings is one Markdown table with the header `| ID | Round | Angle | Severity | Disposition | Note |` and one row per finding:

- ID is unique. Round is the round that disposed the finding.
- Angle is one of `A`, `B`, `confirm` or `review`. `A` or `B` names the angle group of a finding a round-1 cerebrate pass raised: `A` for code truth, conflicts with the project's documented principles, governance and ADR conflicts or existing-path coverage, `B` for failure modes, trust and injection or testability. `confirm` marks a finding a confirming round's cerebrate pass raised. `review` marks a finding raised by the local review tool's pass, by local review or by the post-PR review of the docs pull request.
- Severity is `critical`, `high`, `medium` or `low`.
- Disposition is exactly one of `fixed`, `rejected`, `deferred`, `recorded` or `open`.
- Note holds the summary; for `rejected`, the reason; for `deferred`, the reason and a `#<n>` issue reference; for `recorded`, the reason and the repository path where it is recorded. A `recorded` Note's repository path is a Markdown link target, read relative to the record's folder, or a code span, read relative to the repository root. Once resolved it stays inside the repository and holds no `.git` part and no control character, and only then does verify check that it names a file present at the pull request head, by the readiness check's existence test (Where verify runs). A `deferred` Note's issue reference is `#` followed by a decimal number from 1, checked by shape only: verify makes no `gh` call, so it does not check that the issue exists or is open, and the confirming pass checks each deferral's destination.

The readiness check never reads the body. The design review skill's `verify` (#619, D28) checks stamp equality, each stamp equal to the blob at the pull request head, and ADR inclusion only for a record whose `verdict` is `pass`. Because a passing record stamps the commit its clean pass reviewed, any change to a stamped document after that pass fails stamp equality at the head: a non-record wave in the run that writes `verdict` `pass`, a push between the clean pass and the record step, or a fix after a clean round. Every record the pull request adds or edits gets every other check:

- the front matter shape;
- that the PRD it stamps holds a valid `**UI:**` line at the head (UI prototype format);
- when its verdict is pass and that PRD says `**UI:** yes`, that its stamps include both UI prototype files;
- when its verdict is pass, that its stamps include every ADR the pull request adds or edits, read from its diff against the merge-base with trunk;
- that the Findings table parses, IDs are unique and every row has exactly one disposition from the set;
- that every `deferred` row's Note holds a `#<n>` issue reference and every `recorded` row's Note holds a repository path, per the Note definitions above;
- that the open counts equal the table under the open rule;
- that `verdict` is `pass` only under the pass rule, so a passing record with any open Findings row fails.

Every other passing record whose design is not delivered gets stamp equality only; a delivered design's unedited record is skipped.

Verify prints one line `record-verify-failed: <record path>` per failing record.

Where verify runs:

- Verify is one shell library, `plugin/skills/_shared/record-verify.sh`, sourced by each caller's own script, so no skill calls another's script (ADR-0013), as with the readiness check (D17). It reads every repository path, each stamped path and each `recorded` Note's path, only through the readiness check library's one existence test (Readiness check): a path exists only when its `git ls-tree` entry at the commit read is a regular file blob, mode `100644` or `100755`, and only then is its blob id or content read. A symlink, submodule or tree, or a path under a symlinked directory, reads as missing and fails the record. Neither library tests a path any other way.
- The guide runs it before `gh pr ready`, in any repository.
- **Draft until the record passes.** The guide keeps the docs pull request a draft until verify passes at its head and the record passes the pass rule, and neither GitHub nor `merge-approved.sh` (`:22`) merges a draft. A human who marks the pull request ready and merges it, or a push after it is ready that `merge-approved.sh` then merges under `HIVEMIND_AUTO_MERGE`, is a recorded residual bounded by the readiness check, which fails every slice of a stale, failing or delivered record, and D24 (Trust boundaries). Under `HIVEMIND_AUTO_MERGE` a taken design decision can so merge unseen, bounded as Trust boundaries states. This design adds no merge check: merge-time enforcement on the plugin's merge paths is #619's own design question (D28).
- **Verify in CI is optional.** A repository may add verify to its own CI or validation, never required. This repository does, through its own `tools/validate.sh`, which #619 maps from `docs/initiatives/`, `docs/prds/` and `docs/adr/`. There every record the pull request adds or edits gets every check above, whether or not its design is delivered. Every other passing record whose design is not delivered gets stamp equality only, as on trunk. A delivered design's unedited record is skipped, because close-out stales it by design.
- A repository with no verify in its CI keeps the guide's verify before ready, the readiness check, which fails every slice of a record that does not pass, and the fix-round commit refusal below. The guide does not pass verify as a validation command, because a plan's validation commands are the planner's reading of the project's documented commands, so no code carries a guide-passed command to the validate step.

A verify failure is never fixed in place (#619):

- Where a run's validation runs verify, the validate step (`plugin/workflow-src/lib/gates.js`, shared with pr-feedback-remediation) reads the failures of a failed validation in code. The stop reads only verify's integrity line. A trimmed line of `record-verify-failed: ` and a path matching `^docs/initiatives/[a-z0-9]+(-[a-z0-9]+)*/review-record\.md$` stops the run blocked, next action report, naming each such record encoded, before any `validation_remediation` decision, so no fix round runs. This narrows ADR-0037 decision 16 (asked after design review round 4, answer Q13 A). The failures description asks for each such line word for word, and the Validation Procedure of `plugin/governance/definitions.md` says the same.
- `runCommitStep` (`plugin/workflow-src/lib/commit.js`) refuses a review record path, compared case-insensitively, in every validation fix-round commit of both workflows and every pr-feedback-remediation wave commit; only a standard-delivery wave may carry one. It refuses, before any runner call, a commit whose file list holds a path matching `^docs/initiatives/[^/]+/review-record\.md$`, as a terminal stop naming the path encoded. A wave commit may carry one only in a workflow whose `main.js` declares record writes, and only standard-delivery's does, because the record step is a standard-delivery wave. Which wave writes it is the accepted plan's, and the record is authoritative only through the human-reviewed merge (D24). So no validation fix round, in either workflow, and no pr-feedback-remediation wave commit carries a record, even when the validate drone leaves verify's line out.
- The guide then starts the re-review path.

## Trust boundaries

- **External content stays data.** Issue bodies, PRD and design text, the UI prototype's `index.html` and `notes.md` (markup, comments, script and visible text alike) and review findings are data per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (External Content Boundary). Every reader of the UI prototype, the refinement run, the solution design run, slicing and every design review pass, reads both files as quoted data, never as instructions. The readiness check parses fixed shapes and literal heading text and never runs or evaluates content. Links pass the path allowlist before any git call. Reason codes carry line indexes, never issue text. JSON is built with `jq --arg`. The Lair queue report and parks show reason codes encoded as untrusted data, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Trust-Boundary Discipline). Slices: #615, #621, #623.
- **Write permission authorizes the ready label.** The authorization is write permission on the latest `readiness:ready` labeled event, with the title and body unedited since (ADR-0045 decision 10, as amended by #625; D29). The handoff check verifies the same (#621), and the Lair keeps its check (#623). "Maintainer" names a role, and triage's confirm gate is a workflow step, not an authorization boundary. The guide and the Lair never apply the label. Slices: #620, #621, #623.
- **Reviewers are fresh and read-only.** Each round's main pass runs on cerebrate, whose tool list holds no Bash, Write or Edit. `Memory context: none` keeps the writing session's memory from steering a reviewer. A pass that errors, times out or returns unparseable output yields no round. The local review tool pass, when a tool is configured, runs through `run-review.sh`, which fixes nothing and checks that the tool left the work tree alone (ADR-0042 decision 10), and the record names each pass's reviewer and model. Slices: #619.
- **Guide runs take a fixed request.** A run's request is its instruction channel. A run the guide launches takes only the fixed layout of Guide skill: the marker line, the `Docs pull request:` line, the guide's fixed wording and the maintainer's own words, and no review text. Design review findings, local review findings and post-PR review text reach a run only as the docs pull request's body and conversation comments, through its number as the one launch reference, under the pass scan (SD-06), which ends the run on a flagged comment. Slices: #622.
- **Stamps bind the reviewed content.** The record ships in the same pull request as the design, so it passes the same local review, when a tool is configured, and the same post-PR review, when one runs. Each stamp is the blob at the commit a pass reviewed, recorded by the guide before the pass, so a stamp never names content no pass read. Any later edit is detected by blob id. A pull request whose record has an open finding or a failed verdict stays a draft under the guide, and neither GitHub nor `merge-approved.sh` merges a draft. Authority is a human-reviewed merge (D24). Only the design review's record step writes or re-stamps a record. Verify runs before the pull request leaves draft, and in the repository's own CI where it adds it (D28). `runCommitStep` refuses a review record path, compared case-insensitively, in every validation fix-round commit of both workflows and every pr-feedback-remediation wave commit; only a standard-delivery wave may carry one. #605's auto-tier floor keeps docs paths, UI prototype files included, out of the Lair's auto tier (D24). Recorded residual: with `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a bot approval, only once the pull request is ready (it never merges a draft), with no human review of the design. With `HIVEMIND_AUTO_MERGE` set, a design decision taken under the design-decision rule, one touching scope, an ADR, trust, credentials or the merge path included, can merge to trunk with no human seeing it. That is bounded: each is listed for veto in the review record, is reversible by a later docs pull request, and changes no code until a slice builds it. It is recorded per the user's decision, on the ground that it is outside the threat model as the maintainer's own opt-in (ADR-0044). It is bounded: in any repository `merge-approved.sh` never merges a draft, which the guide keeps until verify passes at its head and the record passes, and the commit refusal and the readiness check, which fails every slice of a stale, failing or delivered record, hold; where a repository adds verify to its own CI, verify there also keeps a merged record consistent and current (ADR-0046, Residuals). Recorded residual: every commit route outside `runCommitStep` carries no record refusal, such as Instinct, chosen or as a fallback, the Reflex tail, the local reviewer's molt fix commits, the github-reviewer's git commits and the guide's own molt commits (Context and code truth, Guide skill). A run the guide launched no longer falls back to Instinct (D33). It is recorded per the user's decision (asked after design review round 4, answer Q15 A), on the ground that a model that writes a molt inputs file or runs git can carry any path. It is bounded by the guide's verify before ready, the readiness check, which fails every slice of a stale record, D24, and verify in the repository's own CI where it adds it (ADR-0046, Residuals). Recorded residual: a human with write permission who deliberately marks the docs pull request ready and merges it can merge a record with an open finding or a failed verdict, unless the repository adds its own merge block. A push after the pull request is ready can likewise leave its record stale or failing when a human, or `merge-approved.sh` under `HIVEMIND_AUTO_MERGE`, merges it. It is recorded per the user's decision (asked in re-review round 2, answer Q21 A, and after re-review round 4, answer Q25 A), on the ground that HIVEMIND requires no consumer CI, so it has no merge block a human cannot pass (`docs/engineering-principles.md` P26). It is bounded by D24, the guide's draft rule and the readiness check, which fails every slice of a stale record or one that does not pass, so no slice of it is labeled ready or claimed (ADR-0046, Residuals). Slices: #615, #619, #622, #623.
- **No new credential.** Everything runs under the executing user's credentials, the guide's findings comments included. This design adds no merge check (D28). The record refusal narrows only what a `runCommitStep` commit may carry. Slices: #619, #622.
- **Snapshot mode reads no GitHub.** At claim the check's GitHub inputs are exactly the claim snapshot's fields, so it judges the issue state the Lair captured and scanned, and it reads documents only as git objects at the snapshot's trunk commit, for a re-claim too (D40). Slices: #615, #623.
- **The UI prototype is a stub page.** The maintainer opens it in their own browser, and agents treat its files only as data. Nothing checks or sandboxes the page, by the user's decision of 2026-11-23. Slices: #615, #619, #622.
- **The prototype verdict marks progress, not approval.** A filled `## Verdict` section in `notes.md` only tells stage derivation which next action to offer; it carries no approving actor and authorizes nothing. The build run writes no `## Verdict` section: only the refinement run writes it, from the maintainer's own words in its request (Guide skill). The approval's authority is the maintainer's answer to the guide's ask (D38), recorded under Decisions asked in the review record, the design review and the record's stamps over both files, and the human-reviewed merge of the docs pull request (D24). Recorded threat model: an agent-written or forged verdict can advance the derived stage early, but no artifact of the initiative becomes authoritative without a passing, stamped record merged by a human, and the readiness check fails every slice of a record that does not pass. It is recorded per a call the run took under `${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md` (Review Calls), in local review of the UI prototype amendment, listed for veto, on the ground that stage derivation is a progress read, not an authorization boundary. Slices: #615, #622.

## Lifecycle

### Initiative stages

1. **Capture.** The guide creates the seed issue. Its body links `docs/prds/<slug>.md`, which may not resolve until the docs merge.
2. **Interrogation.** The guide has created the docs branch before interrogation writes tracked files. `hivemind:plan-interrogation` runs in one session. This is the one single-machine window: its plan lives in the session or `.hivemind/`, so another machine sees only the seed issue. It settles whether the initiative has a user-facing UI or UX surface, for the PRD's `**UI:**` line.
3. **PRD.** `hivemind:plan-to-prd` writes the PRD on the docs branch `docs/<slug>` or `docs/<slug>-<suffix>`. The guide commits the PRD and the interrogation outputs on that branch. Its first non-blank line after the title is the `**UI:**` line (UI prototype format).
4. **UI prototype.** Only when the PRD says `**UI:** yes`; otherwise the stage is skipped. A build run, the maintainer's approval and a refinement run on the docs branch, per UI prototype. The build run is the first docs-branch run: it opens the docs pull request as a draft with no Closes line, and its request's line 2 reads `Docs pull request: none`.
5. **Solution design and ADRs.** Written on the docs branch by drones with exact file scope, in standard-delivery runs the guide launches with `draft` true and no closable launch reference. When stage 4 did not run, the first run opens the docs pull request as a draft with no Closes line; its request's line 2 reads `Docs pull request: none`. Later runs reuse it. On a UI initiative it starts only after the prototype's approval, and the design cites the prototype; a solution design before that is out of order.
6. **Design review.** Per the design review rounds below; the record is written on the docs branch. The guide posts each round's findings as comments on the docs pull request that the first docs-branch run opened. On a UI initiative the review also covers the UI prototype.
7. **Docs pull request.** It has been a draft since the first docs-branch run opened it. It leaves draft through `gh pr ready` only after verify passes at its head and the record passes the pass rule, then merges to trunk. Before the guide launches a run on it while it is not a draft, the guide returns it to draft with `gh pr ready --undo`. A push the guide did not launch is caught by the guide's verify before ready and the readiness check, and by verify in the repository's own CI where it adds it.
8. **Slicing.** `hivemind:prd-to-issues` reuses the seed issue as the epic and adds each slice's design section, with the Prototype line on a UI initiative, and refuses a UI initiative whose prototype is missing or not stamped by a passing record.
9. **Triage.** The maintainer runs triage; it gates `readiness:ready` on the readiness check and writes native blocked-by edges.
10. **Handoff check.** It passes only when every slice passes, and names each slice as claimable now or blocked.

Stage derivation picks the latest stage whose evidence exists. Evidence it cannot resolve to one answer, such as two seed issues for one slug or two open docs pull requests, is reported as ambiguous and asked, never guessed.

### Design review rounds

Each round is one fresh read-only cerebrate pass with `Memory context: none`, covering every angle: code truth, conflicts with the project's documented principles, governance and ADR conflicts, existing-path coverage, failure modes, trust and injection, and testability. Its model is the configured reviewer model (D11). When the design touches a trust boundary, credentials or the merge path, as the record's Rounds section states, the round adds one pass by the configured local review tool through `hivemind:adaptation-cycle`. That pass takes as base the previous round's reviewed commit (for round 1, the merge-base with trunk) and a fixed focus naming the angles. With no tool configured, or when the tool cannot run (ADR-0042 decision 6), that pass is skipped and the record says so. Round 1 reviews the whole documents. On an initiative whose PRD says `**UI:** yes`, every round also covers the UI prototype, both files, and checks the solution design against it; the round cap and the pass rule are unchanged. Each later round is a confirming round: it reviews only the change since the previous round's reviewed commit and the fixes to that round's findings, not the whole design again. Each pass reviews the reviewed commit the guide recorded before it. A pass that errors, times out or returns output the skill cannot parse yields no round and is re-run. A round is clean only when every completed pass of it raises no new finding and finds no earlier finding unfixed. A round's findings land before the next round runs. After every round the diminishing-returns check runs (D35). Each round's fixes and its record rewrite land in one standard-delivery run, the record wave last: every finding of the round is fixed in the solution design, the PRD, an ADR or the UI prototype in the same pull request, or gets a `deferred`, `recorded` or `rejected` disposition with its reason, so no finding stays open into the next round. The run that writes `verdict` `pass` carries only the record wave and launches with `local_review` false (SD-30). The review exits only when, after dispositions, no finding at any severity is open and one round is clean: the pass rule of Review record front matter. So a passing review has 2 or 3 rounds. A review that has not converged after round 3 stops and reaches the maintainer, and the initiative is split before its docs merge; its pull request stays a draft under the guide. Every finding gets exactly one disposition: `fixed`, `rejected` with its reason, `deferred` or `recorded`. Critical and high findings are only `fixed` or `rejected`. Mediums follow `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Defer-with-Scope, Recorded Residual).

The record step rewrites the record after every round: `verdict` stays `fail` until exit, and `rounds`, the open counts and the Findings table stay current. Its stamps follow the stamp rule of Review record front matter. A lost session resumes from the record's rounds.

This initiative's own review had two user-approved exceptions. D31 added a fourth round to the first review; it is spent, and the re-review started at round 1. D34 adds a fourth round to the re-review (asked after re-review round 3, answer Q23 A). Round 4 of the re-review raised a new high, so the merge enforcement moved out to #619 (D28, answer Q25 A), and one final confirming round over that change follows under D34. The re-review after the 2026-11-22 UI prototype amendment counts rounds from 1 under the three-round cap; D31 and D34 do not carry over.

### Re-review and re-stamp

Review fix: a local-review or post-PR fix that changes a stamped document of a passing record after the review exited runs in this order:

1. The guide returns the pull request to draft.
2. One standard-delivery run lands the fix waves and, last, a record wave that sets `verdict` to `fail` and `clean_round` to `false` and keeps the stamps, `rounds` and the open counts.
3. The design review runs one fresh confirming round, per Design review rounds, over the diff since the stamped blobs.
4. With no new finding and no earlier finding found unfixed, a record-only run with `local_review` false re-stamps to the commit that confirming pass reviewed, sets `verdict` to `pass` and `clean_round` to `true`, and appends the pass under Rounds. `rounds` is unchanged, and the pass does not count toward the cap.
5. With a new finding, it becomes a re-review.
6. The guide marks the pull request ready per stage 7 of Initiative stages.

A fix that lands outside the guide stales the record: verify fails, and where the project's validation runs verify, the validate step stops the run blocked, naming the record (Review record body). Elsewhere the guide's verify before ready and the readiness check catch it. The guide resumes at the confirming pass.

Where the project's validation runs verify, a github-reviewer fix to a stamped document fails it in the Validation Procedure, so the github-reviewer returns blocked with the edit uncommitted. The post-PR watch reports it, and the guide takes it as a review fix. The uncommitted edit stops the next run on `dirty_paths` until the maintainer clears it; the guide never discards it. Elsewhere the fix commits and stales the record, which the guide's verify before ready and the readiness check catch.

Re-review after an amendment:

- Fresh passes run over the diff since the stamped blobs, with rounds counted from 1. A re-review covers the whole documents when no record of the initiative has passed.
- The front matter is reset: `verdict` `fail`, `rounds` 0, every open count 0 and `clean_round` `false`. The stamps are kept, per the stamp rule of Review record front matter.
- The earlier Rounds and Findings move unchanged under one `## History: <date>` section, each heading one level down; when an earlier History section already has that date, the new heading gains a short parenthesized suffix, such as `## History: 2026-11-22 (re-review)`.
- The re-review's Rounds and Findings start empty, and the decision lists and Residuals stay current.

### Close-out

When every slice is done, the solution design gains `**Status:** delivered` and an `## As-built deltas` section in one docs pull request, and is never maintained afterward. The truth then lives in code, ADRs, the glossary and governance.

Close-out edits the stamped design, so its record goes stale by design. Stage derivation reads `**Status:** delivered` first, and a delivered design's record is never re-stamped. Verify skips its unedited record, and its slices fail `design_delivered` (Review record body, Solution design template).

## Existing-path coverage

One row per existing path, with its effect and the slice that makes it. "Unchanged" rows name the slice that relies on them, or none.

| Existing path | Effect | Slice |
|---|---|---|
| `plugin/skills/triage-backlog/SKILL.md`, `plugin/skills/triage-backlog/scripts/triage-ops.sh` | Gains the `readiness` subcommand with the overlay as a `--overlay` JSON argument, as `apply-labels --targets` takes its targets, the apply order (ratings and edges, then the re-check with an overlay holding exactly `readiness:ready`, then `readiness:ready`), reason codes in Notes, `readiness:blocked` narrowed to blocks with no issue link, and `deps-add` edges from Dependencies refs. The confirm gate, `triage:locked` and the per-family mutex are unchanged. | #615, #620 |
| `tools/test_triage_ops.sh`, `tests/triage-backlog/` | Gain the readiness gate, overlay and re-check cases. | #620 |
| `plugin/skills/plan-interrogation/SKILL.md` | Unchanged. The guide's interrogation stage settles whether the initiative has a user-facing UI or UX surface, and the guide commits its outputs on the docs branch. | #622 |
| `plugin/skills/plan-to-prd/SKILL.md` | Its PRD template gains the `**UI:**` line as the first non-blank line after the title, written from the plan with one targeted question when the plan does not settle it (UI prototype format). Its Prototype exception is unchanged and unrelated to the UI prototype. It fits its budget by cutting (D20). A new `tests/policy/safety-*.json` consumer-assertion fixture pins its `**UI:** yes|no` template line (P3). The guide commits the PRD on the docs branch. | #622 |
| `plugin/skills/molt/SKILL.md` | Unchanged. The guide commits through it with exact paths. `molt.sh` has no review record refusal, so its commits are a recorded residual (Trust boundaries). | #622 |
| `plugin/skills/prd-to-issues/SKILL.md`, `plugin/skills/prd-to-issues/scripts/subissue-ops.sh` | Gain the `## Design` section, seed reuse through `ensure-parent --existing-number` with the seed marker line kept, and a carve-out of the "No file paths or code snippets" rule for Design links. Idempotency and the four existing sections are unchanged. Only when `docs/initiatives/<slug>/` exists on trunk, on a UI initiative it adds the Prototype line, and refuses to slice while either UI prototype file is missing on trunk or the review record on trunk does not pass with both stamped, read by sourcing the readiness check library (D17). Otherwise it behaves as today. | #617 |
| `tools/test_subissue_ops.sh`, `tests/prd-to-issues/` | Gain the Design section and seed reuse cases, and the Prototype line and UI refusal cases. | #617 |
| `plugin/skills/create-handoff/SKILL.md` | Unchanged. Its handoff is never stage evidence. | none |
| `plugin/governance/decision-autonomy.md`, Review Calls and Tier A | Gains the design-decision rule. The Tier A line "On the script engine, `decide()` asks only for" is unchanged. The edit fits the byte budget by cutting. The cut never removes a sentence `tests/policy/safety-review-calls.json` pins. A new `tests/policy/safety-*.json` consumer-assertion fixture pins the design-decision rule and its consumers (P3). | #616 |
| `plugin/governance/remediation-doctrine.md` | No edit planned; the design review skill cites Defer-with-Scope and Recorded Residual. | none |
| `plugin/workflow-src/standard-delivery/` | `main.js` declares that its waves may commit a review record, and `contract.js` SD-25 and SD-26 name the record stop and the fix-commit refusal. | #619 |
| `plugin/workflow-src/analysis-only/`, `plugin/workflow-src/pr-feedback-remediation/` | Analysis-only source unchanged. pr-feedback-remediation's `main.js` declares that its waves commit no review record, and `contract.js` PFR-22 and PFR-23 name the refusal and the record stop. | #619 |
| `docs/skill-authoring.md`, Covered Navigators | Unchanged. CHECK 14 and CHECK 16 of `tools/policy_check.sh` read it. The guide and triage-backlog carry no `Edit(.hivemind/` entry, so neither is a navigator. | #620, #622 |
| `plugin/agents/cerebrate.md` | Unchanged. Review passes use it with `Memory context: none` and the configured model (D11). | #619 |
| `plugin/agents/changeling.md` | Gains a carve-out scoped to `docs/initiatives/<slug>/prototype/index.html` only: there it may carry the `?variant=` switcher, the `←` and `→` key cycling and in-memory stub state, which its Hard Stop Rules otherwise stop on; the 3 to 5 variants are the intended alternatives its Design Rules otherwise forbid, and the maintainer's verdict settles the material visual decisions (D39). It writes that file within exact file scope in a standard-delivery wave on the docs branch. It fits its budget by cutting, keeping every sentence a policy fixture pins (D20). | #622 |
| `plugin/skills/adaptation-cycle/SKILL.md` | Gains the design review skill as a caller beside the `local-reviewer`; `run-review.sh`, its reviewer setting and its fix-nothing contract are unchanged. It fits its budget by cutting (D20). | #619 |
| `plugin/agents/overlord.md` | `## Engine` gains the guide-run rule: for a request whose line 1 is `hivemind-guide-run: <slug>`, `request` is the guide's composed request, `references` holds only the number of line 2 when line 2 is exactly `Docs pull request: #<n>`, else none, `draft` is true, and a started run that fails or ends blocked returns to the guide with no Instinct takeover (D33, answer Q19 A). A refused launch, Instinct as a chosen path, the Reflex tail still commits through `hivemind:molt` with no record refusal, a recorded residual (Trust boundaries). It fits its 39038-byte budget by cutting, keeping every sentence a test or policy fixture pins (D20). | #622 |
| `plugin/agents/local-reviewer.md`, `plugin/workflow-src/standard-delivery/review.js` | Unchanged. The local reviewer commits its own fixes through `hivemind:molt` with `caller_validates` true, so its fix check is the Worker Self-Check and the run validates again on its commit. No code refuses a record there, a recorded residual (Trust boundaries). The run that writes `verdict` `pass` launches with `local_review` false (SD-30). | #619, #622 |
| `plugin/workflows/standard-delivery.js`, `plugin/workflows/analysis-only.js`, `plugin/workflows/pr-feedback-remediation.js` | `standard-delivery.js` and `pr-feedback-remediation.js` are regenerated by #619; their BUILD_IDs change, and each fits D20. `analysis-only.js` is unchanged, because #619 changes no function it bundles. | #619 |
| `CONTEXT.md` | This pull request adds the initiative's terms and fixes the stale "planned" notes. The 2026-11-22 amendment adds UI Prototype and updates the Initiative, PRD, Solution Design, Design Review, Review Record, Readiness Check and Initiative Track entries. | #627; the 2026-11-22 amendment |
| `docs/adr/0045-lair-software-factory.md` | Not edited here; decision 10 is amended by #625. | #625 |
| `tools/validate.sh` | This repository's own suite registration, optional and not required by the plugin: it maps `docs/initiatives/`, `docs/prds/` and `docs/adr/` to the record verify suite, and registers the readiness check (#615), design review (#619) and stage derivation (#621) suites. | #615, #619, #621 |
| `plugin/workflow-src/lib/gates.js` | The validate step, shared with pr-feedback-remediation, reads verify's `record-verify-failed:` line from a failed validation in code and stops blocked, naming the record, before any `validation_remediation` decision. Its failures description asks for that line word for word. This narrows ADR-0037 decision 16 (answer Q13 A). Its fix-round commit goes through `runCommitStep`, which refuses a review record path, compared case-insensitively, in every validation fix-round commit of both workflows. | #619 |
| `plugin/workflow-src/lib/commit.js` | `runCommitStep` refuses a review record path, compared case-insensitively, in every validation fix-round commit of both workflows and every pr-feedback-remediation wave commit; only a standard-delivery wave may carry one. The refusal comes before any runner call, a terminal stop naming the path. A wave may carry one only in a workflow whose `main.js` declares record writes. | #619 |
| `plugin/governance/definitions.md`, Validation Procedure | Gains the record rule: each `record-verify-failed:` line of failure output is reported word for word, and no fix edits a review record. It fits its budget by cutting (D20). A new `tests/policy/safety-*.json` consumer-assertion fixture pins the record rule and its consumers (P3). | #619 |
| `plugin/agents/github-reviewer.md` | Unchanged. It loads the Validation Procedure, so the record rule binds its own fix commits. It commits with git, outside `runCommitStep`, a recorded residual (Trust boundaries). A stamped-document fix that fails verify returns blocked with the edit uncommitted, and the guide takes it as a review fix (Re-review and re-stamp). | #619 |
| `tests/workflow-scripts/standard-delivery.test.mjs`, `tests/workflow-scripts/pr-feedback-remediation.test.mjs` | Gain the record stop and commit refusal cases. | #619 |
| `plugin/skills/open-plan-pr/scripts/open-plan-pr.sh` | Unchanged. A reused pull request keeps its draft state, and the `draft` launch arg (SD-48) is unchanged. | #622 |
| `tests/workflow-scripts/overlord-contract.test.mjs` | Gains the guide-run case: it pins the `## Engine` guide-run rule and checks that the guide's SKILL.md names the same marker line. The fallback clause case stays. | #622 |
| `tests/policy/prose-byte-budget.json` | Gains one entry per new skill's SKILL.md, from #616, #619 and #622. A new entry needs no raise (D20). The three slices edit it in Seam order, each on top of the last merged entry. | #616, #619, #622 |
| `README.md`, Skills table and settings table | The Skills table gains one row per new skill: the solution design skill (#616), the design review skill (#619) and the guide (#622). The settings table gains `HIVEMIND_DESIGN_REVIEW_MODEL` (#619). | #616, #619, #622 |
| `CLAUDE.md` | Gains `HIVEMIND_DESIGN_REVIEW_MODEL` with the other `HIVEMIND_` settings. | #619 |
| `plugin/workflow-src/lib/workers.js` | Unchanged. `runPlanWaves` commits each wave with `stepName` `wave` (`workers.js:251`), the wave commit #619's record allowance keys on. | #619 |
| `plugin/workflow-src/lib/facts.js`, `plugin/workflow-src/lib/pr.js`, `plugin/workflow-src/lib/title.js` | Unchanged. #622 relies on the `dirty_paths` stop, `renderClosingLines` and `describeClosesProblem`. | #622 |
| `plugin/skills/gather-facts/scripts/gather-facts.sh` | Unchanged. #622 relies on it carrying a named pull request's body and conversation comments as external texts (`:574-596`), and on the pass scan (SD-06) that ends a run on a flagged text. | #622 |
| `plugin/skills/github-review-loop/scripts/merge-approved.sh` | Unchanged. It never merges a draft (`:22`), which the guide keeps until verify passes at its head and the record passes (Review record body). With `HIVEMIND_AUTO_MERGE` set it can merge a docs pull request once it is ready, taken design decisions included, unseen, a recorded residual (Trust boundaries). Merge-time enforcement on it is #619's own design question (D28). | #622 |
| `docs/prds/idea-to-ready.md` | This pull request narrows it: its council requirements move to #638 (D32), and Further Notes state that a design decision with no strong recommendation is asked, which #638 may change only by its own ADR. The 2026-11-22 amendment adds the UI prototype and its `**UI:** no` line. | #627 |
| Lair controller, not yet built (#608) | The readiness check, called in snapshot mode with the claim's snapshot and trunk commit, is its admission step; #608 builds the call (D40). `docs/prds/`, `docs/initiatives/` and `docs/adr/` are in the auto-tier floor #605 builds (D24). #623's acceptance tests run against #608's call with #615's check and against #605's auto-tier script. | #608, #605, #623 |
| Lair initiative, epic #603 | The PRD's Lair retrofit criterion is covered by #625, the first pilot. #625's acceptance criteria verify it: the record passes with stamps equal to trunk, and every Lair slice passes the readiness checklist by hand. Once #615 and #620 land, triage's readiness gate also checks the Lair slices before any is labeled ready under the new rule. #615's delivery adds the seed marker to epic #603 by hand before the readiness check is first used to label any slice ready; until then its slices fail `epic_marker_missing`. | #625, #615 |

## Failure modes

| Failure | Handling | Slice |
|---|---|---|
| A stamped document is edited after review | The record is stale (`record_stale:<path>`) until a review of the change re-stamps it; every slice fails the check meanwhile. | #615, #619 |
| A merge conflict resolution edits a stamped document | Same as above, seen on trunk; a follow-up docs pull request re-reviews and re-stamps. | #615, #619 |
| A passing record goes stale on a later push | Before the guide launches a run on a docs pull request that is not a draft, it returns the pull request to draft with `gh pr ready --undo`, and marks it ready again only per stage 7 of Initiative stages. A push the guide did not launch fails the guide's verify before ready and verify in the repository's own CI where it adds it. In any repository the readiness check fails every slice with `record_stale:<path>`. | #619, #622, #615 |
| Another initiative's docs pull request adds an ADR | ADR inclusion is checked only for a record the pull request adds or edits whose verdict is pass, so every other passing record gets stamp equality only. | #619 |
| A fix round would re-stamp a record to clear verify | Never: `runCommitStep` refuses a review record path, compared case-insensitively, in every validation fix-round commit of both workflows and every pr-feedback-remediation wave commit, a terminal stop naming it, and the edit stays uncommitted; only a standard-delivery wave may carry one. The validate step reads verify's `record-verify-failed:` line in code and stops blocked before any `validation_remediation` decision. Commits outside `runCommitStep` are a recorded residual (Trust boundaries). | #619 |
| An edited failing record's stamps differ from the head or omit an ADR added after them | Verify checks stamp equality and ADR inclusion only for a record whose `verdict` is `pass`, and gives the record every other check. A failing record keeps its stamps; only the record that sets `verdict` `pass` re-stamps, to the commit its clean pass reviewed, and includes every ADR the pull request adds or edits. | #619 |
| A stamped document changes after the clean pass: a non-record wave in the pass run, a push between the clean pass and the record step, or a fix after a clean round | The passing record stamps the commit its clean pass reviewed, so verify's stamp equality at the head fails: in the guide's verify before ready and in the repository's own CI where it adds it. A push after the pull request is ready is a recorded residual (Trust boundaries). | #619, #622 |
| A deferred or recorded Findings row names no destination | Verify fails: a `deferred` Note needs a `#<n>` issue reference and a `recorded` Note a repository path, per the Note definitions of Review record body. | #619 |
| The github-reviewer fixes a stamped document | Where the project's validation runs verify, the fix fails it, and the github-reviewer returns blocked with the edit uncommitted. The post-PR watch reports it, and the guide takes it as a review fix. The edit stops the next run on `dirty_paths` until the maintainer clears it; the guide never discards it. | #619, #622 |
| A docs-branch run would open a ready pull request or add a Closes line | The guide launches every docs-branch run with `draft` true and no closable launch reference. | #622 |
| A run the guide launched fails or ends blocked | It returns to the guide, which re-derives the stage; the overlord does not continue it on Instinct (D33). A refused or blocked launch starts no run and runs on Instinct under ADR-0048, inside the recorded residual (Trust boundaries). | #622 |
| A design review finding, a local review finding or post-PR review text carries instructions or a fence terminator | No review text enters a guide run's request. It reaches a run only as the docs pull request's body or a comment, carried by `hivemind:gather-facts` under the pass scan (SD-06), and a flagged comment ends the run, which returns to the guide (Guide skill). | #622 |
| A guide request carries a `Docs pull request:` line anywhere but line 2, or an issue number | The overlord reads `references` only from line 2 in its exact form, so no other line reaches it. Before the docs pull request exists line 2 reads `none`, and a reused pull request's body never changes, so no Closes line is written. | #622 |
| A pull request edits a stamped PRD or ADR outside `docs/initiatives/` | Where a repository adds verify to its own CI, `docs/prds/` and `docs/adr/` map to it there, which fails it. A merge leaves the record stale on trunk, failing every slice with `record_stale:<path>` until a re-review. | #619, #615 |
| A record claims pass with an open Findings row | Verify fails. | #619 |
| The validate drone leaves verify's line out of its failures | The failure takes the fix path, but `runCommitStep` refuses the record in every fix-round commit, so verify keeps failing until a review re-stamps it, and the fix limit asks. | #619 |
| A design is marked delivered to escape verify | A record the pull request edits is verified whatever its design's status. Verify skips a delivered design's unedited record, so such a change can merge, and every slice of a delivered design then fails `design_delivered` and is never claimed. | #615, #619 |
| A repository adds no verify to its own CI | The guide's verify before `gh pr ready`, the readiness check and the `runCommitStep` refusal hold; a stale record fails every slice with `record_stale:<path>`. Commits outside `runCommitStep` are a recorded residual bounded by those checks (Trust boundaries). | #615, #619, #622 |
| #625 merges first and changes ADR-0045 | No effect: this design cites only "ADR-0045 decision 10, as amended by #625" and never stamps ADR-0045. | #625 |
| ADR number 0046 is taken on main | Checked before the pull request opens and before it leaves draft; the ADR is renumbered and every link updated. | #627 |
| A design review pass errors, times out or returns unparseable output | It gives no round and is re-run. | #619 |
| A session is lost mid-review | The next session resumes from the record's rounds. | #619 |
| Local review or a post-PR fix changes a stamped document | Per Re-review and re-stamp: the guide returns the pull request to draft, one run lands the fix and a record wave setting `verdict` to `fail`, one confirming pass runs over the diff, and a record-only run with `local_review` false re-stamps; the pass does not count toward the cap. A new finding makes it a re-review. | #619, #622 |
| The design review does not converge by round 3 | It stops and reaches the maintainer, and the initiative is split before its docs merge. | #619 |
| A docs pull request whose record has an open finding, a failed verdict or stale stamps would merge | The guide keeps it a draft, and neither GitHub nor `merge-approved.sh` merges a draft; a human who marks it ready and merges it is the recorded residual (D24), and the readiness check fails every slice of it. | #615, #619, #622 |
| A fix run during the review rounds validates its failing record | Verify's integrity checks pass a well-formed failing record, so the run is not stopped. | #619 |
| A design that touches a trust boundary, credentials or the merge path has no local review tool configured, or the tool cannot run | The tool pass is skipped, and the record's Rounds section says so. | #619 |
| The configured reviewer model cannot be reached | The pass yields no round and re-runs on cerebrate's own model; the record names the model each pass used. | #619 |
| A round's findings are not all disposed when the next round would run | The design review skill runs a later round's pass only when the record's open counts are all 0. | #619, #622 |
| `gh` or `git` fails, or a read is truncated | The check exits non-zero; no caller reads it as a pass, and the Lair leaves the issue unclaimed. Stage derivation reports the failure and derives no stage. | #615, #621, #623 |
| An issue body or document has CRLF line endings | The ending carriage return of each line is removed before parsing, so it parses as LF. | #615 |
| A linked document is missing | A reason code; the run continues to the next issue. | #615 |
| A caller passes a branch name, a local ref or a malformed id | Rejected before any git call. Callers pass the fetched remote commit id, so a stale local ref is never read. | #615, #620, #621, #623 |
| Link or heading text in an issue body is hostile | A link failing the path allowlist gives `design_link_invalid` with no git call. Heading codes carry the line index, never the text. | #615 |
| A named heading matches zero or several headings | `heading_unmatched` or `heading_ambiguous`; the slice fails. | #615 |
| The review record's front matter is off its shape | `record_malformed`; the slice fails. | #615 |
| Design links name another slug, or the epic lacks a seed marker | `design_slug_mismatch` or `epic_marker_missing`; the slice fails. | #615 |
| A Design block has duplicate or missing lines | `design_block_missing`; the slice fails. | #615 |
| A seed marker carries a malformed slug | Ignored and named, with no `git` or `gh` call. | #621 |
| A Dependencies ref has no native blocked-by edge | `dependency_edge_missing:<n>`; triage writes the edge through `deps-add`. | #615, #620 |
| Labels are applied after the check | The overlay checks the pending labels, and the post-apply re-check, with an overlay holding exactly `readiness:ready` and every other family and edge read live, drops any issue that now fails. | #620 |
| A slice passes with open blockers | It may be labeled ready; the Lair still claims it only when no blocked-by dependency is open. | #620, #623 |
| The issue is edited between the check and the claim | The unedited check of ADR-0045 decision 10, as amended by #625, and the body hash captured at claim time stop it. | #623 |
| Two guide sessions work on one stage | The later one stops and re-derives the stage. | #621, #622 |
| Stage evidence is ambiguous, such as two open docs pull requests | The guide reports it and asks; it never guesses a stage. | #621, #622 |
| A seed-marked issue comes from a user without write permission, or a fork pull request uses `docs/<slug>` | Ignored and named in the report. | #621 |
| An interrogation session is lost | Only the seed issue survives; the guide reports the interrogation stage and restarts it. | #621, #622 |
| A UI initiative's slice has no Prototype line, or a UI prototype file is missing | `prototype_missing`; the slice fails. | #615 |
| A stamped UI prototype file is edited after review | `record_stale:<path>` until a review of the change re-stamps the record; every slice fails meanwhile. | #615, #619 |
| A record stamps a prototype path outside the two shapes, such as the `prototype/` directory | `record_malformed`; the slice fails. | #615 |
| The PRD's `**UI:**` line has a value other than `yes` or `no` | `prd_ui_invalid` for every slice; stage derivation reports it as ambiguous and asks; verify fails a record the pull request adds or edits. | #615, #619, #621 |
| A PRD has no `**UI:**` line | The readiness check and stage derivation read it as `no`; verify fails a record the pull request adds or edits whose stamped PRD has none. | #615, #619, #621 |
| A solution design exists before the UI prototype is approved | Out of order: the guide reports it and asks, never guessing a stage. | #621, #622 |
| `hivemind:prd-to-issues` runs on a UI initiative whose prototype is missing or not stamped by a passing record | It refuses and names the reason. | #617 |
| The Lair re-claims a parked issue | The check runs at the snapshot's trunk commit, never at the parked head the strain spawns from (D40). | #615, #623 |
| A snapshot lacks a field the check reads | The check exits non-zero, and the Lair reads it as `check-error`, never a pass. | #615, #623 |
| A budgeted file cannot fit its budget by cutting | The slice stops and asks the user with the measured size, the budget and the size needed (D20). | every slice |

## Decisions

Taken decisions are listed for veto in the review record and in a docs pull request comment the guide posts with `gh pr comment`. Asked decisions carry the user's answer.

### D1: Guide is a user-only conductor skill

Taken and listed for veto; set by the PRD. A main-session skill, not a workflow (workflows take no input mid-run) and not an overlord section (it would load in every session). ADR-0046.

### D2: Stage derived only from GitHub and git

Taken and listed for veto; set by the PRD. No progress state or pointer is stored. ADR-0046.

### D3: One deterministic readiness check shared by three callers

Taken and listed for veto; set by the PRD. Triage, the guide's handoff check and Lair admission share one check that judges no quality. Lair admission is ADR-0045 decision 10, as amended by #625. Lair admission calls it in snapshot mode (D40). ADR-0046.

### D4: Track read from the native parent and labels

Taken and listed for veto; set by the PRD. The track is a native parent epic plus the human-confirmed type and effort labels. ADR-0046.

### D5: Per-initiative docs folder

Taken and listed for veto; set by the PRD. `docs/initiatives/<slug>/` holds the solution design, the review record and, when the PRD says `**UI:** yes`, the UI prototype (D36); the PRD stays at `docs/prds/<slug>.md`. ADR-0046.

### D6: Design review by fresh read-only planner passes

Taken and listed for veto; set by the PRD, as amended by #640, #641 and #643. Each round is one fresh cerebrate pass with `Memory context: none` covering every angle, plus the local review tool pass of D11 when the design touches a trust boundary, credentials or the merge path. Round 1 covers the whole documents, and each confirming round only the change since the previous round and the fixes to its findings. The review is capped at three rounds, and every round's findings land before the next round runs. Exit is the pass rule of Review record front matter: zero open findings at any severity and one clean round. A record with an open finding or a failed verdict keeps its docs pull request a draft (D28). On a UI initiative each round also covers the UI prototype (D36). ADR-0046 (decision 6).

### D7: Review record front matter with blob stamps

Taken and listed for veto; set by the PRD. The fixed front matter and its staleness rule. ADR-0046.

### D8: Ready label allowed with open blockers

Taken and listed for veto; set by the PRD. A passing slice is ready with open blocked-by links; `readiness:blocked` is kept for blocks with no issue link. Ready Issue keeps its no-open-blocked-by rule. ADR-0046.

### D9: Design-decision always-ask rule

The name is historical: the always-ask list was removed by the 2026-11-22 amendment (#649).

Set by the PRD; its gate first asked in re-review round 1, answer Q18 A, and amended 2026-11-22 at the maintainer's direction. Review Calls gains the rule in the design-decision rule component. A strong-recommendation decision is taken and listed for veto in every category. A design decision's gate reads Promotion Gate clause 1 only, applied to the action taken now. ADR-0046 records this as narrowing ADR-0026 decision 3 for design-stage decisions only.

### D10: Delivered design frozen as history

Taken and listed for veto; set by the PRD. Close-out adds the delivered status and as-built deltas, then the file is never maintained. ADR-0046.

### D11: A second model only when configured

Set by the PRD, as amended by #640. A second model is used only when configured, never required. The cross-model pass is the configured local review tool (`HIVEMIND_LOCAL_REVIEWER`, ADR-0042), an optional capability: the design review skill runs it through `hivemind:adaptation-cycle` when the design touches a trust boundary, credentials or the merge path, and skips it, saying so in the record, when none is configured or it cannot run. The cerebrate pass's model is `HIVEMIND_DESIGN_REVIEW_MODEL` when set, else cerebrate's own model. The setting is read from the `env` block of `.claude/settings.json` or `.claude/settings.local.json` and passed as the Agent call's model, so a maintainer with Fable can set it. A model the call cannot reach yields no round, and the pass re-runs on cerebrate's own model. Neither Codex nor Fable is required. The record names each pass's reviewer and model. For the tool pass it names the preset or argv list, and the model as the tool's own default, which hivemind never names (ADR-0042 decision 7), unless the argv list sets one. Taken and listed for veto: the setting name, and the reuse of `hivemind:adaptation-cycle`, whose design review caller owns that coupling under ADR-0013's orchestrator carve-out. ADR-0046 (decision 6).

### D15: Drone with exact file scope writes designs and records

Taken and listed for veto. Solution designs, review records and design-stage ADRs are written by a drone with exact file scope; the UI prototype's `index.html` is written by a changeling (D39); `hivemind:plan-interrogation`'s writer exception is not extended. ADR-0046 (decision 11).

### D17: Readiness check is a shared library

Taken and listed for veto. `plugin/skills/_shared/readiness-check.sh` is sourced by each caller's own script, so no skill calls another's script. ADR-0046 (decision 3).

### D19: Native blocked-by edges written at triage

Taken and listed for veto. Triage writes the edge for each Dependencies ref through `deps-add`, behind its confirm gate; `hivemind:prd-to-issues` keeps body refs. ADR-0046 (decision 4).

### D20: Prose budget with no pre-approved raise

Asked, answer Q1 B: no budget raise is pre-approved. A slice fits every budgeted file it edits by cutting, measured as that file's check measures. If it cannot, it stops and asks the user with the measured size, the budget and the size needed. The budgets the slices meet:

- `plugin/governance/decision-autonomy.md`, 12173 bytes (#616).
- `plugin/governance/definitions.md`, 7084 bytes (#619).
- `plugin/skills/triage-backlog/SKILL.md`, 11952 bytes (#620).
- `plugin/skills/prd-to-issues/SKILL.md`, 14566 bytes (#617).
- `plugin/governance/remediation-doctrine.md`, 19906 bytes (any slice that edits it).
- `plugin/workflows/standard-delivery.js`, 42100 characters of string and template literals (#619).
- `plugin/workflows/pr-feedback-remediation.js`, 38200 characters of string and template literals (#619).
- `plugin/agents/overlord.md`, 39038 bytes (#622).
- `plugin/skills/adaptation-cycle/SKILL.md`, 5421 bytes (#619).
- `plugin/skills/plan-to-prd/SKILL.md`, 7215 bytes (#622).
- `plugin/agents/changeling.md`, 4460 bytes (#622).

`plugin/agents/overlord.md` had 0 bytes free when measured, so #622 fits its `## Engine` edit by cutting, or stops and asks.

Each built script also stays under the 191000-character `MAX_BUILT_SCRIPT_LENGTH`, and `tools/build_workflows.mjs` enforces both limits. At the measured commit, `standard-delivery.js` had 164 characters of length free under it. `WORKFLOW_APPROVAL_LIMIT`, 200000, is the hard ceiling. #619 fits both limits by cutting, or stops and asks. Each regeneration changes that script's `BUILD_ID`.

A new file takes a new budget entry, which needs no raise. This pull request edits nothing under `tests/policy/`. No ADR: fails hard to reverse, because a raise is one user-approved entry in `tests/policy/prose-budget-raises.json`.

### D24: Review record authority is a human-reviewed merge

Asked, answer Q5 A. A review record is authoritative only through a human-reviewed merge, and only the design review's record step writes or re-stamps it. #605 builds `docs/prds/`, `docs/initiatives/` and `docs/adr/` into the Lair's auto-tier floor (Lair design, Component "Merge lane and auto tier"; the user's answer 2A of 2026-11-22), not #623, so a docs pull request never takes the auto tier in any consumer project (corrected 2026-11-22, Amendments). Recorded residual: with `HIVEMIND_AUTO_MERGE` set, `merge-approved.sh` can merge a docs pull request after a bot approval, only once the pull request is ready (it never merges a draft), with no human review of the design. With `HIVEMIND_AUTO_MERGE` set, a design decision taken under the design-decision rule, one touching scope, an ADR, trust, credentials or the merge path included, can merge to trunk with no human seeing it. That is bounded: each is listed for veto in the review record, is reversible by a later docs pull request, and changes no code until a slice builds it. ADR-0046 (decision 7 and Residuals).

### D27: Design-stage resolution is judgment checked by review

Taken and listed for veto. The design stages run no `decide()`. Take or ask is the conductor's judgment under the design-decision rule. The review record lists each taken decision with its recommendation strength and what it touches, and the confirming pass checks each (#619). ADR-0046.

### D28: Record verified before ready

Taken and listed for veto: verify itself. The design review skill's verify checks the front matter, the stamps and the Findings table, per Review record body. A record with `verdict` pass and any open Findings row fails it. Verify is one shared library, `plugin/skills/_shared/record-verify.sh`, sourced by each caller's own script (D17's pattern). The guide runs it before `gh pr ready`. A repository may add verify to its own CI as an optional capability, never required. This repository does, through its own `tools/validate.sh` with `docs/initiatives/`, `docs/prds/` and `docs/adr/` mapped to it, so here it runs on every push, and every other passing record whose design is not delivered gets stamp equality only. The guide does not pass verify as a validation command, because a plan's validation commands are the planner's reading of the project's documented commands.

Taken and listed for veto: the record flow. Verify checks stamp equality and ADR inclusion only for a record whose `verdict` is `pass` (RR2-1). Each round's fixes and its record rewrite land in one standard-delivery run, the record wave last. The run that writes `verdict` `pass` launches with `local_review` false (SD-30). A fix after the review exits follows the order of Re-review and re-stamp. Before each pass the guide records the fetched pull request head commit id the pass reviews; a passing record stamps the commit its clean pass reviewed, and a record written with `verdict` `fail` keeps its stamps. The guide launches every docs-branch run with `draft` true, marks the pull request ready only after verify passes at its head and the record passes the pass rule, and returns it to draft before it launches a run on it.

Asked after design review round 3, answer Q10 A, narrowed after round 4: record integrity is enforced in code. Verify prints `record-verify-failed: <record path>` per failing record. In the repository's own CI, where it adds verify, every record the pull request adds or edits gets every check, whether or not its design is delivered; stamp equality and ADR inclusion apply only when its verdict is pass. A delivered design's slices fail `design_delivered`. The validate step reads verify's line in code and stops the run blocked, naming the record, before any `validation_remediation` decision. `runCommitStep` refuses a review record path, compared case-insensitively, in every validation fix-round commit of both workflows and every pr-feedback-remediation wave commit; only a standard-delivery wave may carry one. A repository with no verify in its CI keeps the guide's verify, the readiness check and the commit refusal.

Asked after design review round 4. Answer Q15 A: the commit refusal covers `runCommitStep` only. Every commit route outside it carries no refusal, a recorded residual (Trust boundaries). Answer Q13 A: the validate step's record stop narrows ADR-0037 decision 16. ADR-0046.

Asked in re-review round 2, answer Q21 A, and after re-review round 3, answers Q23 A and Q24 A: a merge check on the plugin's merge paths that needs no CI. Superseded for the merge check after re-review round 4 by answer Q25 A: merge-time enforcement on the plugin's merge paths, `merge-approved.sh` and the Lair's merge, leaves this design and is #619's own design question, with findings RR4-C1, RR4-1, RR4-2 and RR4-3 of the review record as its input. This design's guarantee is the guide's draft rule, which no merge path passes because neither GitHub nor `merge-approved.sh` (`:22`) merges a draft, and the readiness check, which fails every slice of a stale, failing or delivered record. The draft rule meets the PRD's rule that a record with an open finding or a failed verdict cannot merge (#641) only while the docs pull request is a draft, which the guide keeps it until verify passes at its head and the record passes: while it is a draft, no merge path merges it, neither GitHub nor `merge-approved.sh`. It does not meet the rule in full: after the pull request is ready, a human merge or a `merge-approved.sh` merge of a later push can still merge a failing or stale record (the recorded residual), so the PRD's full guarantee is delivered by #619's own design of merge-time enforcement. A human who marks the pull request ready and merges it, or a push after it is ready that `merge-approved.sh` then merges, can still merge such a record: a recorded residual bounded by the readiness check and D24 (Trust boundaries). The PRD's full guarantee, with its testing decision that a failing record blocks the docs merge, is delivered by #619's own design of merge-time enforcement. Q21 A's rule stands that verify in a repository's own CI is optional, never required (`docs/engineering-principles.md` P26). Asked in re-review round 2, answer Q22 A: the round-2 remediation plan, which takes the verdict-pass-only stamp and ADR-inclusion checks (RR2-1) and the Note definitions (RR2-3). ADR-0046 (decision 7 and Residuals).

### D29: Write permission is the ready label's authority

Taken and listed for veto. The authorization for `readiness:ready` is write permission on its latest labeled event, with the title and body unedited since. The handoff check verifies it (#621), and the Lair keeps its check (#623). "Maintainer" names a role, and triage's confirm gate is not an authorization boundary. ADR-0046 and ADR-0045 decision 10, as amended by #625.

### D31: One-time fourth design review round

Asked after design review round 3, answer Q9 A. Every round-3 finding was fixed, then round 4 ran as one fresh confirming pass over both angles, a one-time exception the user approved for this initiative only. The three-round cap of Design review rounds stays the general rule, and the pass rule and the readiness check are unchanged. Round 4 is added under Rounds as the D31 confirming round and does not change `rounds`, as the review-fix confirming pass of Re-review and re-stamp does not (answer Q11 A). The review record names the exception.

Spent: round 4 ran both angles and raised new high findings, so the council split out into its own initiative (D32). The re-review starts at round 1 under the three-round cap. No ADR: fails hard to reverse, because it is a one-time exception that changes no rule.

### D32: Council split into its own initiative

Asked after design review round 4, answers Q12 A and Q14 B. The council, slices #618 and #624 and the decisions listed under Decisions moved to the council initiative go to #638. The PRD loses its council requirements. A design decision with a weak or absent recommendation is asked; #638 may change that only by its own ADR. That is recorded as an amendment of ADR-0026 decision 2 for design-stage decisions (answer Q16 A), and the design-decision gate's narrowing of ADR-0026 decision 3 (asked in re-review round 1, answer Q18 A; amended 2026-11-22; D9). ADR-0046.

### D33: Guide-launched runs return to the guide

Asked in re-review round 1, answer Q19 A. A standard-delivery run the guide launched that fails or ends blocked returns to the guide, which re-derives the stage, with no Instinct takeover. This narrows ADR-0039 decision 4 for guide-launched runs. Taken and listed for veto: the mechanism. The overlord tells a guide-launched run by the marker line `hivemind-guide-run: <slug>` that opens its request, which only the guide writes, not by a new launch arg, which would change standard-delivery's launch contract, `readDeliveryLaunch` and its built script. It reads `references` only from line 2 of the request (RR2-2). Asked in re-review round 2, answer Q22 A: the round-2 remediation plan, which takes the fixed request layout and routes review findings to a guide run only as docs pull request comments under the pass scan (RR2-C1, RR2-2; Guide skill). A refused or blocked launch starts no run and still runs on Instinct under ADR-0048. #622 edits `plugin/agents/overlord.md` (`## Engine`) and fits its budget by cutting (D20). ADR-0046.

### D34: One-time fourth re-review round

Asked after re-review round 3, answer Q23 A. Every round-3 finding was fixed, then round 4 of the re-review runs as one fresh confirming round covering every angle, with the local review tool pass, a one-time exception the user approved for this initiative only, recorded as D31 was. The three-round cap of Design review rounds stays the general rule, and the pass rule and the readiness check are unchanged. Round 4 is added under Rounds as the D34 confirming round and does not change `rounds`, as D31's round 4 did not (answer Q11 A). If it raises any new critical or high finding, the merge enforcement moves out to #619's own design, and this design narrows its claim to the guide's draft rule and the readiness check. Round 4 raised one, RR4-C1, so the merge enforcement moved out (answer Q25 A; D28). One final confirming round over that change follows under this exception and does not change `rounds`. No ADR: fails hard to reverse, because it is a one-time exception that changes no rule.

### D35: Diminishing-returns check after every round

Asked: the user's directive after re-review round 4. After every design review round, before the next one runs, the design review checks the round's findings for diminishing returns. Its three signals are the design review's own, read over the review record's Findings table and modeled on the fix-ledger signals of `hivemind:detect-remediation-signals`. Unlike that skill's Creep Stagnation check, it runs whatever the severity of the open findings, and it has no non-actionable guard:

1. Recurrence: the same surface or heading draws new findings after an earlier round fixed it.
2. Severity and reach trend down round over round while each fix adds surface, more text, machinery or rows than it removes.
3. The new findings are edge cases an existing safeguard already bounds, such as the readiness check, the draft rule or D24.

When any signal fires, the review tells the maintainer unprompted, in plain words, with three options: narrow the claim and hand the remaining surface to the slice that builds it as a tracked follow-up; accept the rest as recorded residuals; or keep going. The options stay within the disposition rule: a critical or high finding is fixed, including by removing the claim it attacks, as RR4-C1 was, or rejected; only medium and low findings may be deferred or recorded, under `${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md` (Defer-with-Scope, Recorded Residual). The maintainer decides. The check never ends a review by itself, and it changes neither the pass rule nor the round cap. The record lists each time the check fired, its signals and the maintainer's answer. ADR-0046 (decision 6).

### D36: UI prototype between the PRD and the solution design

Taken and listed for veto; set by the maintainer's decision of 2026-11-22 (#663), with its recommended details taken. An initiative whose PRD says `**UI:** yes` has a UI prototype, a required artifact produced and approved after the PRD and before the solution design (UI prototype, UI prototype format). One self-contained `index.html` holds 3 to 5 structurally different variants behind the `?variant=` switcher, with stub data only and no polish, and `notes.md` holds per-variant feedback and a verdict. The maintainer approves, the verdict is folded into one approved variant, and that variant is stamped on trunk. The losing variants stay only in the docs pull request's history and `notes.md` describes each in words: a recorded deviation from the upstream prototype skill, which keeps a prototype off main. The design review covers it, a passing record stamps both files, each UI slice links it, stage derivation and the guide gain its stage, and `hivemind:prd-to-issues` refuses to slice without it. The standalone track is unchanged. No design tool, hosted service, build step, framework or account is required (`docs/engineering-principles.md` P26). Not taken: a throwaway sketch during interrogation, which leaves nothing durable to build against; the prototype as a section of the solution design, which puts UI and architecture in one review round; and variants mounted on an existing app route, which not every consumer project has. ADR-0046 (decision 12).

### D37: UI line read from the PRD

Taken and listed for veto, strong recommendation. The PRD's first non-blank line after its title is exactly `**UI:** yes` or `**UI:** no`, set during interrogation and written by `hivemind:plan-to-prd` (#622). It is a recorded fact, read and never judged. The readiness check and stage derivation read a missing line as `no`, so no existing stamped PRD must change; any other value gives `prd_ui_invalid`. #619's verify fails a record the pull request adds or edits whose stamped PRD lacks a valid line. This initiative's PRD says `**UI:** no`. ADR-0046 (decision 12).

### D38: UI prototype approval is the stage's approval gate

Taken and listed for veto, strong recommendation. The maintainer's approval of the UI prototype, given as the answer to the guide's ask and recorded under Decisions asked in the review record, is the UI prototype stage's one ask. The `## Verdict` section in `notes.md` marks progress only and authorizes nothing (Trust boundaries). The guide asks it beside the two kinds of the design-decision rule. It is an approval gate, not a design decision with a recommendation, so the rule is otherwise unchanged. A UI choice inside the prototype with a strong recommendation is taken and listed for veto, per ADR-0046 decision 8 as amended. ADR-0046 (decision 8, amendment of 2026-11-22, UI prototype stage and Lair corrections).

### D39: Changeling builds the UI prototype

Taken and listed for veto, strong recommendation. A changeling with exact file scope writes `prototype/index.html` in a standard-delivery wave on the docs branch, because presentational UI and UX is its domain. #622 gives `plugin/agents/changeling.md` a carve-out scoped to `docs/initiatives/<slug>/prototype/index.html` only: there it may carry the `?variant=` switcher, the `←` and `→` key cycling and in-memory stub state, which its Hard Stop Rules otherwise stop on; the 3 to 5 variants are the intended alternatives its Design Rules otherwise forbid, and the maintainer's verdict settles the material visual decisions. A drone with exact file scope writes `prototype/notes.md`, a design artifact under ADR-0046 decision 11. In a run that also writes the review record, the record wave runs last. The UI prototype build run is the first docs-branch run of a UI initiative, so it opens the docs pull request. ADR-0046 (decisions 10 and 11).

### D40: Readiness check reads a recorded snapshot at claim

Taken and listed for veto: the Lair design's correction (Lair design, Seam order, "Cross-epic seams with #614"; claim integrity, "Assumptions about #615"; the user's answer 3A of 2026-11-22, recorded on #615). Given a recorded issue snapshot and a trunk commit, the readiness check makes no GitHub read of its own; its GitHub inputs are exactly the snapshot's fields. Triage and the guide keep reading through `gh`. Lair admission passes the snapshot's trunk commit, for a re-claim too, never the parked head a re-claim spawns its strain from. Recorded fixtures use snapshot mode. ADR-0046 (decision 3).

### Decisions moved to the council initiative

Asked after design review round 4, answers Q12 A and Q14 B, these moved to #638. They are not decisions of this design, and their numbers are not reused.

- D12: Abathur council with two callers.
- D13: Consult setting as data with a per-run cap.
- D14: Council member named Overseer.
- D16: Process and council get separate ADRs.
- D18: Initial consult setting values.
- D21: Accepted-ADR amendments recorded in the council ADR, answer Q2 A.
- D22: Runner member through a sixth runner-gate script, answer Q3 A.
- D23: Overlord may launch the council agents, answer Q4 A.
- D25: Consult step with decide unchanged.
- D26: Caller composes the council brief.
- D30: Council settles unmarked weak or unanswered questions, answers Q6 A, Q7 A and Q8 A.

## Verification strategy

Each slice runs this repository's own gate, `bash tools/validate.sh --changed`, at its validate state. The suite registrations below are this repository's own; the plugin requires none of them in a consumer project. Per slice:

- **#615:** contract tests over recorded issue fixtures for each track and each reason code. Cases include a document edited after stamping, an epic, a standalone issue that must be promoted, a slice with open blockers that passes, hostile link and heading text, a design link and record of different slugs, an unstamped PRD, a missing blocked-by edge, a truncated read, a missing document versus a `git` failure, a malformed commit id, and template order, duplicate heading and missing-section cases. More cases: `design_slug_mismatch`, `epic_marker_missing`, and Design blocks with zero or two `## Design` sections, Solution design lines or Review record lines, or no Heading line. A delivered design gives `design_delivered`. One case per pass-rule clause with its code: `verdict` fail, `clean_round` false and `rounds` 1 give `record_not_passed`; `rounds` 4 gives `record_rounds_exceeded`; an open medium gives `record_open`. A PRD stamp path passes the allowlist, and a stamp path outside every shape gives `record_malformed`. A CRLF standalone body and a CRLF epic seed marker pass. Test script `tools/test_readiness_check.sh`, fixtures in `tests/readiness-check/`, and a `tools/validate.sh` suite mapped from `plugin/skills/_shared/readiness-check.sh`, `tests/readiness-check/` and the script. UI and snapshot cases: a PRD with no `**UI:**` line reads as `no`; `**UI:** maybe` gives `prd_ui_invalid`; a `**UI:** yes` slice with no Prototype line, or with `index.html` or `notes.md` missing, gives `prototype_missing`; a Prototype link outside its shape gives `design_link_invalid`, and one of another slug `design_slug_mismatch`; a record stamping one prototype file gives `record_unstamped:<path>` for the other; a stamp of `docs/initiatives/<s>/prototype/` gives `record_malformed`; an edited stamped prototype file gives `record_stale:<path>`; a `**UI:** no` slice with a Prototype line gives `design_block_missing`; snapshot mode makes no `gh` call, and a snapshot missing a field exits non-zero; `gh`-mode cases through a recording `gh` stub check field mapping and `pageInfo` truncation; a `prd_ui_invalid` PRD gives no Prototype-line code. Object-type cases: a symlink at an allowed document path, one targeting a path inside the repository and one outside it, a submodule there and a path under a symlinked directory each read as missing and give that document's missing code.
- **#616:** a fixture run on the Lair PRD yields every template section filled; skill authoring checks prove the skill names no sibling; a `tests/policy/safety-*.json` consumer-assertion fixture pins the design-decision rule in `plugin/governance/decision-autonomy.md` and each consumer that names it (P3), and every sentence `tests/policy/safety-review-calls.json` pins survives the cut.
- **#617:** `tools/test_subissue_ops.sh` with `tests/prd-to-issues/` fixtures: the Design section, seed reuse with the marker line kept, and no duplicate on rerun. A policy fixture under `tests/policy/` pins the Design section and the Design-link carve-out of the "No file paths or code snippets" rule in `plugin/skills/prd-to-issues/SKILL.md`. On a UI initiative: the Prototype line on each slice, and a refusal when a prototype file is missing on trunk or the record does not pass with both stamped. A `**UI:** yes` PRD with no `docs/initiatives/<slug>/` on trunk slices as today, with no Prototype line and no refusal.
- **#619:** stamping then verify passes. Each of these fails: an open high, a deferred high, a missing clean round, `rounds` of 1 or 4, an errored pass counted as a round, a passing record with an unstamped added ADR, and a Findings table that disagrees with the open counts. A resume continues from the record's rounds, a confirming pass flags a taken decision whose recommendation was weak or absent, or that took an action irreversible now, and this repository's suite fails a stale passing record. More cases: an added ADR fails only the record the pull request edits; a verify failure stops the run with no fix round; a pass with an open medium fails; and this repository's suite runs verify on a `docs/prds/` or `docs/adr/` edit. Record-integrity cases: a fix round that reports a review record path is refused before any runner call with a terminal stop naming it, in standard-delivery and pr-feedback-remediation (`tests/workflow-scripts/standard-delivery.test.mjs`, `tests/workflow-scripts/pr-feedback-remediation.test.mjs`); a pr-feedback-remediation wave step whose files hold a record is refused the same way, a case variant of the path included, while a standard-delivery wave commits one; a failed validation whose failures hold a `record-verify-failed:` line stops blocked, naming the record, with no `validation_remediation` decision and no fix round, and a line whose path is outside the record shape is not read; verify of a pull request fails a record it edits whose design is delivered, skips a delivered design's unedited record, and passes an edited failing record whose stamps differ from the head and fails an edited passing one; a record with Residuals or History sections verifies as without them; a non-record wave in the pass run, a push between the clean pass and the record step, and a fix after a clean round each fail verify; a record written with `verdict` `fail` keeps its stamps, and a re-review reset keeps them; a confirming pass that finds an earlier finding unfixed makes no clean round; a `deferred` row whose Note holds no `#<n>` and a `recorded` row whose Note holds no repository path each fail verify; SD-25, SD-26, PFR-22 and PFR-23 name the stop and the refusal; a `tests/policy/safety-*.json` consumer-assertion fixture pins the Validation Procedure record rule in `plugin/governance/definitions.md` and each consumer that names it (P3). Round-2 cases: an edited failing record that omits an ADR added after its stamps passes verify, while a passing record that omits it fails; a run's validation passes a well-formed failing record, so a fix run during the rounds is not stopped; a `recorded` Note's link target resolves from the record's folder and its code span from the repository root; a recorded Note path missing at the head, leaving the repository, or holding a `.git` part fails, and so does a stamped path or recorded Note path that is a symlink, a tree, a submodule or under a symlinked directory at the head; a `deferred` Note's `#<n>` passes by shape with no `gh` call; a round's local review tool pass runs through `hivemind:adaptation-cycle` with base the previous reviewed commit, and with no tool configured, or a tool that cannot run, it is skipped and recorded; an unreachable reviewer model re-runs the pass on cerebrate's own model, and the record names it; a later round's pass runs only when the record's open counts are all 0; a confirming round reviews only the diff since the previous reviewed commit; a round is clean only when every pass of it is. Test script `tools/test_design_review.sh`, fixtures in `tests/design-review/`, and `tools/validate.sh` registrations for the design review suite and the record verify suite. D35 cases: a recurrence on one surface, a downward severity trend with growing surface, and edge cases bounded by an existing safeguard each surface the diminishing-returns advisory with its options before the next round; with no signal the round proceeds; the round's `Diminishing-returns advisory:` line (Review record body) gives each advisory's signals and the answer. A record the pull request edits whose stamped PRD has no valid `**UI:**` line fails verify; a passing record of a UI initiative that omits a prototype stamp fails verify; a round on a UI initiative covers the prototype.
- **#620:** `tools/test_triage_ops.sh` with `tests/triage-backlog/`: the overlay, a post-apply re-check that drops a now-failing issue, edges written before readiness, a failing issue that never enters the apply set as ready with its reasons shown, a passing slice with open blockers proposed ready, a never-triaged issue that passes the overlay check and then passes the post-apply re-check, whose overlay holds exactly `readiness:ready` while every other family and edge is read live, and the existing cases. The overlay is a `--overlay` JSON argument checked as `--targets` is, and CHECK 14 and CHECK 16 pass with no Edit entry in triage-backlog.
- **#621:** recorded fixtures for every stage give the expected stage and next action. Cases: `**Status:** delivered` read before staleness, seed identity, fork and non-write evidence ignored and named, the latest-label check, and two open docs pull requests reported as ambiguous. Handoff mode passes only when every slice passes. A malformed marker slug is ignored and named with no `git` or `gh` call. A truncated read of labeled events, edit history, the seed marker search or open docs pull requests stops with a failure and derives no stage. Test script `tools/test_stage_derivation.sh`, fixtures in `tests/stage-derivation/`, and a `tools/validate.sh` suite. A UI initiative gives the UI prototype stage between the PRD and solution design stages; `notes.md` with no `## Verdict` after the build run gives the UI prototype stage waiting for approval; a filled `## Verdict` in `notes.md` ends it; a solution design before it is reported out of order; a `**UI:** no` or missing line skips it; an invalid line is reported as ambiguous.
- **#622:** the skill is user-only. A live smoke takes a throwaway idea to ready slices: it creates the docs branch, commits the stage-2 and stage-3 outputs so the tree is clean, and runs verify before `gh pr ready`. Every docs-branch run launches with `draft` true, and the pull request stays a draft with no Closes line across reused runs, leaving draft only after verify. A weak or absent design decision is asked; the guide carries no Edit entry, so CHECK 14 and CHECK 16 pass. More cases: each round's fixes and record rewrite land in one run with the record wave last; the run that writes `verdict` `pass` launches with `local_review` false; the guide marks the pull request ready only after verify passes at its head and the record passes the pass rule, and returns it to draft before it launches a run on it; a fix after the review exits follows the order of Re-review and re-stamp; the guide records the fetched head commit id before each pass and gives it to the record step, and the same three post-pass changes fail verify before ready. Guide-run cases: every guide request opens with `hivemind-guide-run: <slug>`, then the fixed wording, then the maintainer's words; line 1 is the marker, and line 2 is `Docs pull request: none` before the docs pull request exists and `Docs pull request: #<n>` after; the request holds no review text; a round's findings reach the run only through the guide's comment, carried by gather-facts and scanned by SD-06; a finding holding an instruction or a fence terminator is scanned and flagged, and the run ends and returns to the guide; a `Docs pull request:` line anywhere but line 2 never reaches references; the docs pull request exists before the first review pass; a guide run's only launch reference is the docs pull request number; a guide-launched run that ends blocked returns to the guide, which re-derives the stage, with no Instinct commit; `tests/workflow-scripts/overlord-contract.test.mjs` gains a case that pins the `## Engine` guide-run rule and checks that the guide's SKILL.md names the same marker line, and its fallback clause case stays green or is updated with the same meaning. A fresh session resumes at the derived stage. For a UI initiative the build run is the first docs-branch run and opens the draft docs pull request; a changeling step writes `index.html` and a drone step `notes.md`; `plugin/agents/changeling.md` carries the carve-out of D39 for `docs/initiatives/<slug>/prototype/index.html` only, and fits its budget; the approval is asked and recorded; the build run writes no `## Verdict` section; the refinement run carries the feedback and verdict as the maintainer's own words, leaves one variant and writes the `## Verdict` section in its last non-record wave, after the changeling step; `hivemind:plan-to-prd` writes the `**UI:**` line, and a `tests/policy/safety-*.json` consumer-assertion fixture pins its `**UI:** yes|no` template line in `plugin/skills/plan-to-prd/SKILL.md` (P3); a solution design run waits for the approval and names the prototype.
- **#623:** a tick contract test where an epic and a stale design are not claimed and are named in the queue report with encoded reason codes; its readiness tests run against #608's snapshot-mode call with #615's check, a re-claim's check runs at the snapshot's trunk commit, and, against #605's auto-tier script, a docs pull request, UI prototype files included, never takes the auto tier.

### Prose budget check

Every slice that edits a file in D20's list measures it as its check measures: bytes with CR stripped for CHECK 18 of `tools/policy_check.sh` against `tests/policy/prose-byte-budget.json`. For `plugin/workflows/standard-delivery.js` and `plugin/workflows/pr-feedback-remediation.js`, `tools/build_workflows.mjs` measures the characters of string and template literals with `countProseCharacters` against the script's entry in the same budget file, and the script's length against `MAX_BUILT_SCRIPT_LENGTH`. It fits by cutting per P25. If it cannot, it stops and asks the user, showing the measured size, the budget and the size needed. A prose budget raise lands only with a user-approved entry in `tests/policy/prose-budget-raises.json`. Governance citations pass `tests/workflow-scripts/governance-section-refs.test.mjs`.

## Seam order

Slices start in this order; a slice waits on its blockers.

Row rule: each row names, by full heading text, the component, contract, state and lifecycle sections its slice builds; Trust boundaries when a trust bullet names the slice; Failure modes, since the budget failure row names every slice; Prose budget check when the slice edits a file in D20's list; and the decisions it carries. Existing-path coverage and Verification strategy name every slice, so no row lists them.

| Slice | Blocked by | Headings it implements |
|---|---|---|
| #615 Readiness check | none | Readiness check; Track fact; Readiness check output contract; Document parsing rules; Standalone spec block format; Slice design section format; Seed issue marker; Solution design template; Review record front matter; Trust boundaries; Failure modes; D3: One deterministic readiness check shared by three callers; D4: Track read from the native parent and labels; D17: Readiness check is a shared library; UI prototype format; D36: UI prototype between the PRD and the solution design; D37: UI line read from the PRD; D40: Readiness check reads a recorded snapshot at claim |
| #616 Solution design skill and template | none | Solution design skill; Initiative folder; Design-decision rule; Solution design template; Failure modes; Prose budget check; D5: Per-initiative docs folder; D9: Design-decision always-ask rule; D15: Drone with exact file scope writes designs and records; D20: Prose budget with no pre-approved raise; D27: Design-stage resolution is judgment checked by review; D32: Council split into its own initiative |
| #617 Slice design links and seed epic | #615 | Slice design section; Slice design section format; Seed issue marker; Failure modes; Prose budget check; D20: Prose budget with no pre-approved raise; UI prototype format; D36: UI prototype between the PRD and the solution design |
| #619 Design review and record | #615 | Design review; Design review rounds; Re-review and re-stamp; Review record front matter; Review record body; Document parsing rules; Slice design section format; Solution design template; State and ownership; Trust boundaries; Failure modes; Prose budget check; D6: Design review by fresh read-only planner passes; D7: Review record front matter with blob stamps; D11: A second model only when configured; D20: Prose budget with no pre-approved raise; D24: Review record authority is a human-reviewed merge; D27: Design-stage resolution is judgment checked by review; D28: Record verified before ready; D35: Diminishing-returns check after every round; UI prototype; UI prototype format; D36: UI prototype between the PRD and the solution design; D37: UI line read from the PRD |
| #620 Triage readiness gate | #615 | Triage readiness gate; Readiness check output contract; Trust boundaries; Failure modes; Prose budget check; D8: Ready label allowed with open blockers; D19: Native blocked-by edges written at triage; D20: Prose budget with no pre-approved raise; D29: Write permission is the ready label's authority |
| #621 Stage derivation and handoff check | #615, #619 | Stage derivation and handoff check; Initiative stages; Close-out; Readiness check output contract; Seed issue marker; Solution design template; Review record front matter; Trust boundaries; Failure modes; D2: Stage derived only from GitHub and git; D29: Write permission is the ready label's authority; UI prototype; UI prototype format; D36: UI prototype between the PRD and the solution design; D37: UI line read from the PRD |
| #622 Guided initiative command | #616, #617, #619, #620, #621 | Guide skill; Initiative stages; Re-review and re-stamp; Close-out; Standalone spec block format; Seed issue marker; Design-decision rule; Trust boundaries; Failure modes; Prose budget check; D1: Guide is a user-only conductor skill; D10: Delivered design frozen as history; D20: Prose budget with no pre-approved raise; D27: Design-stage resolution is judgment checked by review; D28: Record verified before ready; D32: Council split into its own initiative; D33: Guide-launched runs return to the guide; UI prototype; UI prototype format; D36: UI prototype between the PRD and the solution design; D37: UI line read from the PRD; D38: UI prototype approval is the stage's approval gate; D39: Changeling builds the UI prototype |
| #623 Lair admission | #615, #608, #625 | Lair admission; Readiness check output contract; Trust boundaries; Failure modes; D24: Review record authority is a human-reviewed merge; D29: Write permission is the ready label's authority; D40: Readiness check reads a recorded snapshot at claim |

#618 and #624 moved to the council initiative #638 and get no Design section from this design.

#623 builds neither the readiness-check call at claim nor the docs-path protection: #608 builds the call and #605 the auto-tier floor (Lair design, Seam order, "Cross-epic seams with #614"). #623's acceptance tests run against both.

## Open questions

None

## Amendments

After design review round 4 the council split out (D32), asked after that round, answers Q12 A and Q14 B:

- The council, slices #618 and #624 and decisions D12, D13, D14, D16, D18, D21, D22, D23, D25, D26 and D30 went to #638.
- The PRD was narrowed: it lost its council requirements.
- The design review restarts at round 1 under the three-round cap (D31).

After re-review round 1, asked in that round:

- D9's gate narrows ADR-0026 decision 3 (answer Q18 A), and D33 returns a guide-launched run to the guide, narrowing ADR-0039 decision 4 (answer Q19 A).

After re-review round 2, main's PRD changes #640, #641, #642 and #643 merged into this branch, and the user answered Q21 A and Q22 A in that round:

- The review procedure follows them: one pass per round covering every angle, conflicts with the project's documented principles included, the optional local review tool pass, confirming rounds over the change only, a configurable reviewer model (D6, D11), and findings landing before the next round.
- A record with an open finding or a failed verdict cannot merge on the plugin's merge paths, with no CI merge gate (D28, answer Q21 A). Every capability beyond the plugin is optional, with a stated fallback (`docs/engineering-principles.md` P26).
- Review findings reach a guide run only as docs pull request comments under the pass scan, and the request has a fixed layout (Guide skill, D33, answer Q22 A).

After re-review round 3, asked after that round, answers Q23 A and Q24 A:

- Merge mode checks, at the head a merge path would merge, every record that a changed PRD, solution design, ADR or record applies, with every check and the pass rule, and refuses a pull request it cannot read. `merge-approved.sh` fetches the head and base from origin to run it, which broadens the narrowing of ADR-0044's merge conditions (D28).
- A one-time fourth round of the re-review follows (D34).

After re-review round 4, asked after that round, answer Q25 A:

- Merge-time enforcement on the plugin's merge paths moved out to #619's own design, superseding the merge-check parts of Q21 A, Q23 A and Q24 A. The guarantee narrows to the guide's draft rule and the readiness check (D28, D34).
- A diminishing-returns check runs after every design review round (D35), at the user's direction after re-review round 4.

After the maintainer's decision of 2026-11-22:

- The always-ask list is removed (D9). A design-stage decision with a strong recommendation is taken and listed for veto whatever it touches, and, besides Tier A, Surface-Growth Escalation and the UI prototype approval gate (D38), only a weak or absent recommendation and an action irreversible now are asked. The gate reads Promotion Gate clause 1 only. The review record lists each taken decision with its recommendation strength and what it touches. ADR-0046 decision 8 is amended.

After the maintainer's decision of 2026-11-22 on #663, and the Lair design's corrections (Seam order, "Cross-epic seams with #614"):

- A UI prototype is a conditional initiative artifact between the PRD and the solution design, entered only when the PRD says `**UI:** yes` (UI prototype, UI prototype format, D36 to D39). Initiative stages gain stage 4, UI prototype, and the later stages renumber to 5 to 10.
- The readiness check gains `prd_ui_invalid`, `prototype_missing`, the Prototype line and exactly two prototype stamp paths; Lair admission inherits them through the shared check. #617 is now blocked by #615.
- Snapshot mode: given a recorded issue snapshot and a trunk commit, the check makes no GitHub read of its own, and a re-claim passes the snapshot's trunk commit (D40).
- `docs/prds/`, `docs/initiatives/` and `docs/adr/` are in the Lair's auto-tier floor, built by #605, not by #623 (D24).
- ADR-0046 is amended in place (2026-11-22: UI prototype stage and Lair corrections), and the review record is reset for a re-review.
