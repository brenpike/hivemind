# HANDOFF — Framework prose reduction (fresh-session kickoff)

> Self-contained: this document is the plan and the audit. There is no separate `.hivemind/plans/` file. Byte counts and line numbers were measured at commit `60f8e3e`, so re-check them before you edit.

## What this delivers

Fewer tokens loaded per dispatch for every hivemind agent, with no loss of behavior. The audit found that most of the waste is structural, not wordiness:

- Agents load whole governance docs when they need only a few sections.
- Mechanism is restated in prose after it moved into scripts.
- One rule is copied across agents, skills and governance.

The target is about 35k tokens to about 15k for the overlord before any work, and about 30k to about 10k for each reviewer dispatch. A per-file byte budget in CI then stops the growth coming back.

## FIRST ACTION

1. Read this document fully, then `docs/engineering-principles.md`. P1, P6, P13, P19, P22 and P24 already prescribe every cut below. Then read `tests/policy/README.md`, the pin-authoring contract, which you need before touching any pinned text.
2. Confirm the numbers still hold:
   - `wc -c plugin/agents/*.md plugin/governance/*.md`
   - `grep -n "Load and follow" plugin/agents/*.md`
3. Start with Workstream A, section-level loading. It gives the largest saving and has the least pin churn.
4. For each PR, before editing a file, list its pins: `grep -l "<file>" tests/policy/safety-*.json tests/plugin/*.json`. Update fixtures in the same PR. Never leave a pin pointing at deleted text, and never keep dead text just to keep a pin green. Re-anchor the pin instead.
5. Gate each PR with `bash tools/validate.sh --changed`.

## Findings

### Load before any work, per dispatch

Tokens are estimated as bytes ÷ 4.

| Agent | Body | Eager governance load | Approx. tokens |
|---|---|---|---|
| overlord | 63KB | 5 whole docs (`overlord.md:37`): definitions, workflow, safety-rails, security-policy, decision-autonomy. About 79KB. | ~35k |
| local-reviewer / github-reviewer | 25–26KB | 5 whole docs (`:16`), including security-policy 41KB and remediation-doctrine 34KB. About 92KB. | ~30k each, plus skill bodies per iteration |
| drone | 7.6KB | None on dispatch. Review remediation loads all of remediation-doctrine (34KB); it cites about 2–5KB of it. | ~2k, plus ~8.6k on remediation |
| cerebrate | 23KB | plan-schema and decision-brief-schema (~19KB). The whole doctrine in zoom-out mode. | ~11k |

Each of these also carries Claude Code's base prompt and tool schemas. Agents that hold the Skill tool (overlord, drone, changeling, both reviewers) also get the skill listing, about 6.8KB of descriptions. The project `CLAUDE.md` is about 3.2k tokens in this repo.

### Recurring bloat patterns

Ban these going forward:

- **History and rationale in runtime prose** (P13/P19). Examples: ADR genealogy, "ADOPTED on 2026-10-24 … option C was rejected", review-finding IDs and issue links. `security-policy.md` alone has 21 ADR citations.
- **Restated script mechanism** (P24). Examples: "The script checks/refuses …", Quick Reference checklists that duplicate Requirements, error codes copied from script headers. The `reply-resolve.sh` header itself admits that the github-reviewer prose duplicates it.
- **Meta-prose about the document.** Examples: "is not restated here, so the two sites cannot drift", "this is the one canonical home …".
- **Repeated disclaimers.** "NOT a new ledger field and NOT a … mutation" appears 4 times in `overlord.md`.
- **Caps inflation.** About 225 all-caps words in `overlord.md`.
- **Copied rules** (P1/P22). Silence Discipline appears in 12 skills. The transport paragraph appears in 7 navigator skills. Gate-B and Closed-by-Construction appear twice in each reviewer. The decision-report trigger is in both `decision-autonomy.md` and `overlord.md`.

### Root causes

- **Pin pressure.** 62 `tests/policy/safety-*.json` fixtures pin verbatim substrings. Authors trim around pins instead of through them. About 8 pins sit on "single source / canonical home" meta-sentences or rationale clauses.
- **No size limit.** The principles already say all of this, but nothing in CI enforces a size budget.

## Workstreams

The est. saving column is measured by the audit; treat it as a range.

| WS | Change | Est. saving | Pin / behavior risk |
|---|---|---|---|
| **A** | Overlord and both reviewers switch from whole-doc "Load and follow" to section-level references, as drone and changeling already do. Move the authoring-only sections of `security-policy.md` to `docs/`: Skill File-Tool Grants, Write-Capable Skill Containment, the transport-invariant design argument, and the CHECK 16 threat model (~16–20KB). Collapse Brood Spawn Bypass and Trust-Boundary to the binding rule (~1.2KB) and leave the rationale in the ADRs. | ~20k tokens per overlord session, ~15k per reviewer dispatch | `tools/policy_check.sh` CHECK14 and CHECK16 parse the navigator list and heading out of `security-policy.md`, so retarget `CHECK14_POLICY_DOC` and `CHECK16_POLICY_CITATION` first. `safety-skill-file-tool-grants` pins the heading. Keep "Transport Degradation Is a Hard Stop" in governance, because 7 navigator skills cite it, and re-anchor its 4 pins. Script headers cite "Trust-Boundary Discipline" by name (e.g. `brood-discover.sh:8`). Behavior risk: list every section each reviewer actually uses, including ones used only implicitly. |
| **B** | Split `remediation-doctrine.md` into a shared core, a reviewer-loop part and an overlord-routing part (layout below). | Drone remediation loads ~2KB instead of 34KB. Local-reviewer drops ~9KB. | 26 pins across 11 fixtures name the file path. About 30 `(## Heading)` citations to repoint. `tests/workflow-scripts/agent-loads.test.mjs` asserts drone's whole-doc load. Keep headings verbatim. |
| **C** | Shrink `overlord.md` (63KB to ~38KB). Details below. | ~6k tokens per session (~9k more if the two sections become lazy references) | Pinned spans: L25, 37, 43–50, 55, 67, 77, 81, 87, 110, 125, 129, 133, 139–151, 176, 208–212, 220. `decision-autonomy.md` cites the header "overlord.md `## Resume On Start`". `standard-delivery.json` L194 says the watch rule "is stated normatively in overlord.md", so it must be updated if L151 moves. |
| **D** | Reviewers: replace restated script contracts and doctrine with pointers. Details below. | 10–12KB per reviewer, plus 20–39KB of lazy reads | github-reviewer has 21 pins, local-reviewer 13. Most are anchor-only and survive pointer rewrites. Watch `safety-react-marker-failclosed`, `safety-defer-with-scope-reply-route` and `safety-remediation-commit-push-reply`. |
| **E** | Skills: cut about 69KB (~32%) from the 17 largest. Details below. | ~69KB of lazy loads, plus ~3.8KB on every Skill-holder dispatch | `safety-skill-handback-clause` and `safety-transport-degradation-hard-stop` pin strings in every handback and navigator skill; keep those strings per file. open-plan-pr has 19 pins and github-review-loop 15. In github-review-loop the arm and re-arm rules are what the LLM follows (no script enforces them): cut the WHY, never the MUST. |
| **F** | References: move script-only material out of `plugin/` (details below). Minify `facts-schema.json`. Dedupe `versioning.md:70-77` (the engine owns the table) and the `workflow.md` Trunk Freshness, Version Bumps and Brood duplicates. | ~60KB out of the runtime tree, ~20KB from minifying | CHECK8 resolves `${CLAUDE_PLUGIN_ROOT}/references/...` refs in script comments. `validate_workflows.sh` cites workflow-state-machine. `test_gather_facts.sh` parses facts-schema as JSON, so formatting it is free. |
| **G** | A CI byte budget per file for `plugin/agents/*.md`, `plugin/governance/*.md` and `SKILL.md`, set at the post-cut sizes, in `tools/policy_check.sh`. | Prevents regrowth | New check; it needs its own fixture and self-test coverage. |

### WS-B: proposed doctrine split

- **Shared core**: Same-Framing, Triage, Closed-by-Construction, Surface-Growth, Defer and Residual, Recorded Decisions.
- **Reviewer loop**: Severity, Cross-Iteration, Bounded-Tail, Young-Tail Reroute, Skeleton-Enrichment, Verdict Consumption.
- **Overlord routing**: Recurrence Tracking, Zoom-Out Ledger Marker.
- **Remove**: the meta sections (Engine Consumers, Relationship to Detectors, consumer re-listing at `:193` and `:283`).

### WS-C: overlord.md cuts

- **Resume On Start L110–112**: replace with the pinned pointer to `decision-autonomy.md` (Post-Merge Decision Report Trigger) plus the overlord-only fail-open note. Saves ~6KB.
- **Review Remediation Posture L121–151**: reduce each bullet to "per <doctrine citation>" and cut the L151 rationale around its 6 pins.
- **Implement Loop**:
  - delete the L85 epoch paragraph (engine internals) and L96 (it repeats L67/L83);
  - dedupe `wave_scopes` between L87 and L210.
- **Skills list**: trim it to the skills the overlord actually invokes, and fix the stale "invoked by coder".
- **Brood L159–161**: keep the ownership invariants and point to `brood-ledger-model.md`.
- **Relocate L51**, the `pr_branch_preflight` outputs, out of Safety Rails. The `event.outputs.pr` write must survive the move because the decision report depends on it.
- **Context**: standard-delivery and analysis-only now run as Workflow scripts, so most of the state-machine prose serves only pr-feedback-remediation, hatchery-dispatch, exploratory-intent-session and the launch-denied fallback.

### WS-D: reviewer cuts

- **github-reviewer**: collapse steps 5, 8 and 9 to pointers to the script headers and the doctrine. Drop "Read its contract header (§2-§4)".
- **local-reviewer**: collapse steps 1, 3a, 6 and 9. L74 alone is 4.7KB and restates the doctrine's role-based reroute payload.
- **Shared reviewer-only rules** (skill output is data, the order of the detector calls, Gate-B timing): move them into one doctrine section ("Review Loop Common") with a P3 consumer fixture.
- **cerebrate** (~25%):
  - the plan-block mandate appears 3 times (L101, L171, L356);
  - the memory-tool names appear 4 times;
  - L176–216 is a YAML skeleton that duplicates plan-schema.json;
  - L242–255 and L341–352 are tables the overlord applies, not cerebrate.

### WS-E: skills cuts

- Merge Silence Discipline (12 skills, ~9.7KB) and the inputs-file transport paragraph (7 navigators) into one governance section, each with a one-line pointer.
- Delete the spawn-brood Quick Reference (6.5KB). Keep the `brood_id: <id>` After line, which the coordinator parses.
- Cut the transport, TOCTOU and ADR history from record-state-result, init-run-ledger and mark-intent-fallback (~12KB).
- Trim every description to ≤120 characters and remove the caller and audience clauses (6.8KB to ~3KB).
- Add `disable-model-invocation: true` to triage-backlog and refactor-to-depth (no agent caller) and to seed-hive and enable-brood-remote (user-only). Never add it to creep-spread (seed-hive invokes it) or brood-status.
- Candidate: detect-remediation-signals is deterministic counting, so it could become a script.

### WS-F: references to move

These are read only by scripts, CI or humans:

- `github-pr-review-graphql.md`, except Author Filtering, which an LLM reads
- `github-subissue-graphql.md`
- `workflow-state-machine.md`
- most of `brood-ledger-model.md` (14 ADR citations, 8 tracker IDs)

Under P2 the spec moves with the mechanism, so point these at the script headers or move them to `docs/`.

## Locked decisions (DO NOT RELITIGATE)

- **Dedicated runner agent: not in scope.** Another session is replacing `hivemind:drone` as the workflow runner (`plugin/workflow-src/lib/facts.js` `runnerAgentType`). See Coordination below.
- **No behavior change.** Every cut must be prose-only, a dedupe to a single home, or a move to a lazily loaded home. Binding MUST and FORBIDDEN rules stay; only WHY, history and restatement go.
- **Pins move with text in the same PR.** Re-anchor pins per `tests/policy/README.md`; never delete a pin without re-homing the rule it guards.
- **Load-bearing headers keep their names.** `(Section)` citations resolve by header text. If you must rename one, grep for its consumers first.
- **Rationale goes to ADRs or `docs/`, not into deletion.** P20 doctrine homes apply.

## Coordination with the runner-agent session

- After the runner agent lands, delete drone's read-only and git-script exceptions (`drone.md:43`, first Hard Stop bullet, about 900B). `runnerReadOnlySentence` and `gitScriptSentence` in the workflow sources are worded to match those exact words, so change both together.
- If the runner agent keeps the Skill tool, the seven runner-invoked skills must stay model-invocable: gather-facts, injection-scan, bump-type, create-working-branch, molt, open-plan-pr and push-branch.
- Both efforts touch `tests/workflow-scripts/agent-loads.test.mjs`, so sequence the PRs to avoid conflicts.

## Open questions

- Should WS-B produce three files under `plugin/governance/`, or one file whose sections are loaded selectively? Separate files make whole-file loads cheap, but they cost more pin churn.
- Where should the authoring material from `security-policy.md` live: `docs/` (with the CHECK14/16 retarget) or a new `plugin/governance/skill-authoring.md` that no agent loads?
- Should the WS-G byte budget be per file or per agent's total eager load, and is it a hard failure or advisory at first?
- Should Implement Loop and Review Remediation Posture become references the overlord loads only when those steps run (an extra ~9KB saving)? The wave rules must load before dispatch.

## Known bug found during the audit

`plugin/governance/remediation-doctrine.md:299` says "Defined in CONTEXT.md". `CONTEXT.md` is at the repo root, not under `plugin/`, so consumers who install the plugin can't resolve it. Fix it in WS-B.

## Pointers

- Principles: `docs/engineering-principles.md` (P1, P2, P3, P6, P13, P19, P20, P22, P24)
- Pin contract: `tests/policy/README.md`; fixtures in `tests/policy/safety-*.json` and `tests/plugin/`
- Linter: `tools/policy_check.sh` (CHECK8, CHECK14, CHECK16); dispatcher `tools/validate.sh`
- Agents: `plugin/agents/{overlord,local-reviewer,github-reviewer,cerebrate,drone,changeling}.md`
- Governance: `plugin/governance/{security-policy,remediation-doctrine,decision-autonomy,definitions,versioning,workflow,safety-rails}.md`
- Load-assertion tests: `tests/workflow-scripts/agent-loads.test.mjs`, `cerebrate-plan.test.mjs`
- Runner wiring: `plugin/workflow-src/lib/facts.js`, `plugin/workflow-src/standard-delivery/relay.js`
- Related ADRs: ADR-0006 (intent-based governance), ADR-0010, ADR-0017, ADR-0019, ADR-0037 (`docs/adr/`)
