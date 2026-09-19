# Hivemind

Domain glossary for the hivemind Claude Code plugin — a multi-agent system that orchestrates planning, implementation, review, and delivery through governed specialist agents.

## Language

### Agents

**Overmind**:
The user — the supreme intelligence whose will the swarm enacts. Not an agent; the human operator whose intent drives all overlord activity.
_Avoid_: admin, operator, client

**Overlord**:
The control-plane agent — session-level orchestrator and psionic relay. Routes the Overmind's directives, consults the cerebrate for the plan, then distributes execution: owns task intake, spawn sequencing, branch/PR decisions, version bump detection, and review routing. Directs and executes work but never implements. Multiple overlords operate in a brood, each coordinating its own strain.
_Alias_: orchestrator
_Avoid_: planner, strategist, dispatcher, controller

**Cerebrate**:
The read-only strategist — the brain of the swarm. Scans the problem territory and produces the directive (file scopes, step sequencing, risk assessment) before execution begins. Originates the plan and intelligence the swarm executes; reports back but never modifies.
_Alias_: planner, architect
_Avoid_: orchestrator, coordinator, analyst, scout

**Drone**:
A modifying agent — builder caste that implements code changes within an explicitly assigned file scope.
_Alias_: coder
_Avoid_: developer, implementer, worker

**Changeling**:
A modifying agent — shapeshifter that owns presentational markup, styling, and static accessibility within an explicitly assigned file scope. Reshapes visual form, presentation, and UI.
_Alias_: designer
_Avoid_: UI agent, stylist

**Local-Reviewer**:
The agent that runs pre-PR Codex review in a loop, classifies findings, and reports terminal results to the overlord before the PR is opened.
_Avoid_: linter, pre-check

**GitHub-Reviewer**:
The stateless fix-mode agent that remediates post-PR review feedback: deep-fetches and classifies comments, applies simple fixes, pushes, posts fix-SHA replies, resolves threads, and reports terminal results to the overlord. It does NOT monitor — the **GitHub Review Loop** skill watches the PR and dispatches this agent per actionable event.
_Avoid_: PR bot, review handler, watcher

**Bioform**:
The four primary agent archetypes in the swarm — overlord, cerebrate, drone, and changeling. Reviewer agents (local-reviewer, github-reviewer) are operational composites that delegate to bioforms, not distinct castes themselves.
_Avoid_: agent type, role, archetype

**Swarm**:
The entire hivemind collective — all bioforms and their operational composites acting as one governed system. The civilization-scale term for the unified agent framework.
_Avoid_: brood (which is a tactical subgroup), fleet, cluster

### Execution

**Phase**:
A single spawn round-trip: one worker agent receives a step, executes, and reports back.
_Avoid_: stage, iteration (when meaning a sequential plan step)

**Spawn**:
A structured message from overlord to a specialist agent, creating an agent instance with an embedded purpose — containing task objective, file scope, step ID, and completion criteria.
_Alias_: delegation
_Avoid_: assignment, dispatch, handoff (which has a different meaning)

**Essence**:
The distilled knowledge artifact (worker report) produced at phase completion and passed forward to enable the next phase to reconstruct context.
_Avoid_: transfer, relay, spawn, handoff (which is the session-resumption artifact)

**Checkpoint Commit**:
A git commit made at a phase boundary or milestone, preserving incremental progress on the working branch.
_Alias_: molt
_Avoid_: save point, intermediate commit

**Molt**:
The act of shedding progress into a checkpoint commit at a phase boundary, milestone, version bump, or review remediation. The skill `hivemind:molt` performs this.
_Alias_: checkpoint commit
_Avoid_: save, snapshot

**Step**:
The cerebrate's unit of work within a directive, identified as `STEP-NNN`. Each step specifies file scope, assigned bioform type (drone or changeling), and completion criteria. Corresponds 1:1 with a phase during execution; reflex tasks have no steps.
_Avoid_: phase (which is the overlord's execution unit), task, item

**Directive**:
The cerebrate's output — the strategic intent the swarm executes, containing steps, file scopes, decisions, risks, and assumptions. The cerebrate originates it; the overlord interprets and relays it to the swarm. Required before execution begins for non-trivial tasks.
_Alias_: plan artifact, psionic directive
_Avoid_: map, blueprint, spec, design doc

**Reflex**:
An instinctive response that bypasses the cerebrate when all reflex conditions are met: one owner, one known file, trivial change, clear branch classification, no version impact, no review remediation.
_Alias_: trivial fast path (TFP)
_Avoid_: quick path, shortcut

**Session Facts**:
Cached resolved values (trunk name, task-type, claude-mem status, active-step) that persist within a task to avoid redundant lookups.
_Avoid_: state, config, environment

### Governance

**Governance Doc**:
A markdown file under `plugin/governance/` loaded by agents at runtime as binding policy.
_Avoid_: reference doc, guide, spec

**Scope**:
The explicit list of files a modifying agent is permitted to touch during a spawn.
_Avoid_: assignment, context, area

**Validation**:
The set of project-declared commands (from CLAUDE.md) that must pass before a phase is accepted.
_Avoid_: tests, checks (which is broader)

**Verification**:
The overlord's post-phase acceptance checks — scope compliance, report schema conformance, and git state safety. Performed after every phase, independent of project-declared validation commands.
_Avoid_: validation (which means running project-declared commands), review

**Flare**:
An urgent signal from any agent back to the overlord when a condition is encountered that cannot be safely resolved. The mandatory stop-and-report action.
_Alias_: escalation
_Avoid_: error, block (which has a different meaning)

### Git / Delivery

**Working Branch**:
The non-trunk branch created for a single approved directive's implementation and PR.
_Avoid_: feature branch (which is only one classification prefix), dev branch

**Trunk**:
The resolved main integration branch (default: `main`) that must remain stable and deployable.
_Avoid_: master, base branch (which can differ for hotfixes)

**Branch Classification**:
The single prefix (`feature/`, `bugfix/`, `hotfix/`, `refactor/`, `chore/`, `docs/`, `test/`, `ci/`) assigned to a working branch based on the nature of the change.
_Avoid_: branch type, category

**Bump Trigger**:
A change to files affecting a published artifact's runtime behavior, public API, compatibility contract, generated output, packaged output, distribution metadata, or documented consumer expectation, requiring a version increment.
_Avoid_: version trigger, release trigger

**Trunk Freshness**:
The pre-branch sub-check within Git Preflight verifying trunk is up-to-date with its remote tracking branch before creating a working branch. Staleness triggers a user decision: fix-and-continue or proceed-at-risk.
_Avoid_: sync check, remote check

**Git Preflight**:
The set of checks (classification, base branch, trunk freshness, branch name, commit policy, PR target) that must all be defined before implementation begins.
_Avoid_: pre-check, setup

### Review

**Adaptation Cycle**:
The iterative cycle where a reviewer agent invokes Codex, classifies findings, fixes simple issues directly (≤2 files), flares complex ones to the overlord, validates, and repeats until stable or a stop condition fires. The bare alias "review loop" always means THIS local pre-PR Codex cycle — distinct from the **GitHub Review Loop** skill, which is the post-PR watch.
_Alias_: review loop
_Avoid_: review cycle (ambiguous with remediation cycle), feedback loop

**Remediation**:
The act of addressing a review finding: classify, fix directly (≤2 files) or flare to overlord, validate, checkpoint-commit, push.
_Avoid_: resolution, fix (too generic)

**Mutation Decay**:
The detected oscillation where fixing one finding reintroduces a previously fixed finding (2-of-3 signal match), indicating unstable evolution. Forces a mandatory stop. Operational detail (detection signals, precedence) now in `hivemind:detect-remediation-signals`; policy meaning in the **Remediation Doctrine**.
_Alias_: break-fix-break cycle
_Avoid_: regression loop, flip-flop

**Creep Stagnation**:
The detected pattern where the adaptation cycle yields diminishing returns across 2+ iterations — the loop spreads but gains no new ground. Recognized from the fix ledger by one or more signals: shrinking yield (fewer findings and/or lower max severity each pass), style drift (findings trending subjective/low-severity with no security/contract/architecture impact), re-litigation of already-accepted tradeoffs, or non-converging churn. Unlike Mutation Decay, this is an ADVISORY early exit (`diminishing-returns`), not a mandatory stop: the local-reviewer recommends ending the loop and returns the decision to the overlord/Overmind. Guarded — runs only after auto-fixable findings are fixed and checkpointed and never fires while any actionable finding is open, and never at or after the iteration ceiling (`max-iterations-reached` wins there). Operational detail (signals, guards) now in `hivemind:detect-remediation-signals`; policy meaning in the **Remediation Doctrine**.
_Alias_: diminishing-returns exit
_Avoid_: decay (reserved for Mutation Decay), regression loop, flip-flop

**Fix Ledger**:
The persisted YAML artifact (`.hivemind/review-loop/fix-ledger.yaml`) tracking finding status across adaptation cycle iterations; status transitions: open → fixing → fixed/regressed, fixed → cycling.
_Avoid_: review log, finding tracker

**Fix Mode**:
The one-shot operating mode of the github-reviewer agent that processes existing unresolved feedback in a single remediation pass without polling.
_Avoid_: one-shot mode, immediate mode

**GitHub Review Loop**:
The main-session skill (`hivemind:github-review-loop`, executed by the overlord) that watches a single PR via a thin change-detection poll armed on a Monitor and dispatches the github-reviewer agent in fix mode per actionable event. It owns the loop lifecycle — cycle counting, continue/stop decisions, and the single terminal report to the overlord — but never reads, interprets, or classifies feedback (that is the reviewer's job). It returns ONLY on a terminal condition: merged, closed, max cycles, an idle window elapsing with no new review activity (distinct from the cycle ceiling), same-finding-repeat, deferred escalation, injection-suspect, or Codex approval with nothing actionable remaining. Distinct from the **Adaptation Cycle** ("review loop"), which is the local pre-PR Codex cycle. Operational detail of its remediation signals now in `hivemind:detect-remediation-signals`; remediation policy in the **Remediation Doctrine**.
_Avoid_: watch mode, polling mode, monitor mode, continuous mode, background watch

**Codex Approval**:
The terminal signal that the Codex reviewer bot (`chatgpt-codex-connector`) is satisfied with a PR: a 👍 `THUMBS_UP` reaction on the pull request object authored by that bot identity. Codex never files a GitHub `APPROVED` review, so detection uses the `reactions(content: THUMBS_UP)` connection, not review state. Terminal for the github-reviewer only when no unresolved non-self actionable items remain.
_Avoid_: codex sign-off, approved review, thumbs-up comment

**Remediation Doctrine**:
The governance doc (`plugin/governance/remediation-doctrine.md`) holding the shared, definitional policy meaning of root-cause review remediation — Root-Cluster, Same-Framing Test, Closed-by-Construction Preference, Bounded-Impact Gating, Defer-with-Scope (which routes an unfixed finding by destination — a tracked issue when it is work someone should do, a Recorded Residual when it is a decision rather than work), Stop-and-Merge, and Severity as Sensitivity Modifier — loaded by both reviewers, the overlord, and the cerebrate so all four share one vocabulary. Policy only; detection mechanics live in **detect-remediation-signals**.
_Avoid_: remediation policy, doctrine doc, remediation rules

**Root-Cluster**:
A set of N-or-more review findings sharing a root cause, surface, or fix-framing — the signal to stop per-finding patching and zoom out, because the findings are symptoms of one defect. The cluster threshold N is severity-tuned (N=2 on a high-severity just-touched surface, N=3 by default).
_Avoid_: finding group, batch, duplicate set

**`root-cluster-suspected`**:
The reviewer exit_reason that carries a detected **Root-Cluster** (shared surface, member thread/finding refs, hypothesized root cause, same-framing rationale). Routes the overlord to a cerebrate remediation zoom-out (`review_remediation_plan` / `review_remediation_plan_postpr`) for one structural fix instead of N narrow patches.
_Avoid_: cluster-found, zoom-out signal, whack-a-mole exit

**Merge-Advised**:
The advisory terminal (`merge_advised`) recommending a human merge of a converged bounded-tail PR — fired only when zero actionable threads remain, the remaining tail is bounded on a hardened surface with a structural home (per **Defer-with-Scope**), and each push spawns only a fresh bounded tail. Agents never merge; the reason is carried as `advisory_reason`, `structural_home`, and `recommendation_text`.
_Alias_: stop-and-merge advisory
_Avoid_: auto-merge, merge signal, approved-to-merge

**detect-remediation-signals**:
The shared, store-agnostic detection skill (`hivemind:detect-remediation-signals`) invoked by both reviewers over a supplied fix-ledger; returns ONE verdict across four detectors (root-cluster, break-fix, diminishing-returns, merge-advisory). Emits a verdict, not an exit_reason — each reviewer maps the verdict to its own terminal. Operationalizes the **Remediation Doctrine**; carries the detection mechanics that the Mutation Decay / Creep Stagnation / GitHub Review Loop glossary entries point to.
_Avoid_: signal detector, classifier, cluster checker

### Decision Autonomy

**Decision Tier**:
The A/B classification of an overlord decision. Tier A = always surfaced to the Overmind (safety rails, merge recommendations, genuine ambiguity-with-risk); Tier B = auto-decided and journaled by default.
_Avoid_: priority, severity

**Promotion Gate**:
The test that promotes a Tier-B decision back to a surface — trips when the recommended action is irreversible OR architectural blast radius OR safety-relevant (destructive-fix categories).
_Avoid_: escalation gate, risk gate

**Decision Journal**:
The per-decision record (situation, options, trade-offs, recommendation strength, gate outcome, disposition, decision, rationale, reversibility) the overlord appends to the run ledger's `event.outputs.decisions[]` for every autonomous (and surfaced) decision.
_Avoid_: audit log, decision log

**Decision Report**:
The post-merge narrative the overlord ALWAYS surfaces after a PR merges, recounting each autonomous decision in the consumer project's ubiquitous language; produced by `hivemind:decision-report`.
_Avoid_: summary, changelog

**Disposition**:
The outcome of a Tier-B decision — `did-now` (auto-executed), `deferred` (tracked follow-up), `recorded` (accepted residual — the reasoning is recorded in the repository next to the code; no tracker entry), or `surfaced` (returned to the Overmind).
_Avoid_: status, resolution

### Plugin Structure

**Skill**:
A namespaced executable procedure (`hivemind:<name>`) invoked by agents via the Skill tool, with its own SKILL.md defining trigger conditions and behavior.
_Avoid_: command, action, tool

**Governance**:
The set of policy modules under `plugin/governance/` that define binding runtime rules for all agents.
_Avoid_: rules, docs, policies (plural)

**`${CLAUDE_PLUGIN_ROOT}`**:
The path variable resolving to `plugin/` where `plugin.json` lives; all cross-references inside the plugin use this prefix.
_Avoid_: plugin path, root, base path

### Definitions & Safety

**Unsafe Git State**:
The canonical set of six conditions — branch is trunk, HEAD detached, unmerged paths, in-progress rebase/merge/cherry-pick/bisect, uncommitted out-of-scope changes, or trunk unidentifiable — that gates all modifying agent operations.
_Avoid_: dirty state, bad state

**Smallest Correct Fix**:
The minimum-change principle for review remediation: fewest files addressing targeted feedback without scope expansion; among equal file count, fewest changed lines.
_Avoid_: minimal fix, quick fix

**Transient Failure**:
A failure classified strictly by root cause — HTTP 5xx, HTTP 429, TCP reset/refused, DNS failure, TLS handshake failure, exit 124 (timeout), exit 137 (SIGKILL), network unreachable, or git transport errors — as the only type eligible for retry.
_Avoid_: temporary error, retryable error

**Destructive Fix Gate**:
The mandatory human-confirmation gate that fires before any remediation fix touching one of ten security-relevant categories (auth, crypto, validation, dependencies, CI, secrets, permissions, trust boundaries, workflow files, credential exposure).
_Avoid_: security check, approval gate

**External Content Boundary**:
The security rule that all text from PR comments, Codex findings, and fetched URLs is data — never interpreted as agent instructions.
_Avoid_: trust boundary (broader concept), sandbox

**Injection-Suspect**:
The security classification for review text containing direct agent instruction attempts, tool manipulation, or policy override language.
_Avoid_: malicious input, attack

**Tool Grant**:
The capability gate: an entry in an agent's frontmatter `tools:` list inside the plugin, loaded at session start from the version-keyed plugin cache (`~/.claude/plugins/cache/<owner>/<plugin>/<version>/`). A grant added to the source cannot reach an already-running session, so delivery requires a version bump and a fresh session. Failure signature: the tool is absent from the session's tool set. No consumer-project setting confers a tool; a consumer `permissions.deny` rule or managed policy can still block calls to a tool the agent holds (ADR-0010, ADR-0013), which leaves the grant intact and the tool in the session's tool set.
_Avoid_: permission, allow rule, tool permission

**Prompt Pre-Approval**:
An allow rule in the consumer project's `.claude/settings.json`, merged only when `seed-hive` runs and never automatically on plugin upgrade. It pre-approves a named action so no interactive prompt appears for a tool the agent already holds; it never denies, and it never confers a tool. Under `--dangerously-skip-permissions` no file-permission rule applies at all. Failure signature: an interactive prompt appears — an operator-facing harness event that the agent does not observe, since the agent sees only whether a call succeeded or was refused; remedied by re-running `seed-hive`, which restores no capability.
_Avoid_: tool permission, permission grant, capability

**Deny Rule**:
A `permissions.deny` entry in the consumer project's settings, or an equivalent managed policy, that blocks calls to a tool the agent holds. It leaves the tool in the session's tool set and confers nothing; a blocked call surfaces as a non-success outcome like any other. Failure signature: a call is refused while the tool remains held.
_Avoid_: tool revocation, capability removal, ungrant

### Architecture

**Intent-Based Governance**:
The architectural approach (ADR-0006) replacing exhaustive mechanical rules with intent descriptions backed by mechanical safety rails for inter-agent interfaces, safety stops, and exact commands.
_Avoid_: intent-driven rules, soft governance

**Composition by Intent**:
The sanctioned way skills compose: a skill expresses the intent of the work to be done, and the framework's skill-selection may route that intent to an appropriate skill when it matches — without the expressing skill naming, invoking, or depending on the target. Creates no dependency and survives the target skill's absence (the work is done inline). The forbidden alternative is a skill naming or invoking a specific `hivemind:<skill>` (ADR-0013).
_Avoid_: skill chaining, skill invocation, skill dependency

**Worker Report**:
The YAML artifact produced by a modifying agent at phase completion, in one of three schemas: complete (with decisions, risks, and essence fields), blocked (with stage, blocker, and next), or trivial (minimal for single-file changes).
_Avoid_: phase report, agent output, result

### Brood

**Brood**:
A set of parallel overlord sessions working on independent tasks in the same repository, each in its own git worktree. Spawned by the overlord in hatchery mode via brood-dispatch.
_Avoid_: fleet, cluster, swarm, pool

**Hatchery**:
The overlord execution mode entered when a brood-plan is dispatched. The top-level hatchery remains on trunk in the main checkout; but ANY orchestrator may act as a hatchery for its OWN brood, in its own checkout or worktree. A hatchery owns the brood manifests under its own checkout's `.hivemind/broods/` (anchored via `git rev-parse --show-toplevel`), enumerates every brood, with status, and serves as the status dashboard and on-demand helper for the brood lifecycle.
_Alias_: coordinator mode
_Avoid_: manager mode, supervisor mode

**Brood-Id**:
The machine-generated `brood-<uuidv4>` identifier (charset `^brood-[0-9a-f-]+$`) that names one brood — the per-brood isolation key. Generated internally by spawn-brood, injective by construction, and propagated into the per-brood state dir (`.hivemind/broods/<brood-id>/`), each strain's branch (`strain/<brood-id>/<short>`), worktree (`.claude/worktrees/<brood-id>/<short>`), and tmux session (`<brood-id>-<short>`), so concurrent same-checkout broods never collide.
_Avoid_: brood slug, brood key, brood name

**Brood-Plan**:
The cerebrate's output artifact when work decomposes into multiple independent strains. Contains strain-level descriptions and scope boundaries, not step-level detail. Each strain becomes a separate child overlord session with its own full pipeline.
_Avoid_: multi-plan (which means sequential PRs, not parallel), meta-plan

**Strain**:
One independent unit of work within a brood-plan, assigned to a single child overlord session. Each strain has its own worktree, branch, pipeline execution, and PR.
_Avoid_: stream, task (too generic), work item, lane

**Brood Manifest**:
The per-brood JSON file at `.hivemind/broods/<brood-id>/manifest.json` (schema `manifest_version: 4`) in the spawning checkout (the current worktree; the main checkout for the top-level hatchery), tracking one brood's strains — their display worktree paths, derived branches, tmux sessions, and status. Each brood owns a disjoint manifest under its brood-id directory; the hatchery enumerates them by globbing `.hivemind/broods/brood-*/manifest.json`.
_Avoid_: brood config, brood state, registry

### Pipeline & Artifacts

**Initiative**:
The unit of work correlated by a single slug across its plan, Handoff, PRD, and issue set. One slug per initiative; the slug names `.hivemind/plans/<slug>.md`, `.hivemind/handoffs/<slug>.md`, `docs/prds/<slug>.md`, and corresponds to the PRD-level parent (epic) issue whose native sub-issues are the sliced work items.
_Avoid_: project, epic, feature

**PRD**:
The committed, durable specification of WHAT an Initiative delivers, at `docs/prds/<slug>.md`. Contains problem statement, solution, user stories, acceptance criteria, implementation decisions (architectural/contract level), testing decisions, success metrics, and out-of-scope. Never carries file scope or step sequencing — that is the Directive. Produced by `hivemind:plan-to-prd` (planned skill — not yet implemented).
_Avoid_: spec, design doc, directive

**Vertical Slice**:
A thin, end-to-end unit of behavior cutting every layer, small enough to be independently grabbable; one slice = one GitHub issue = one Strain candidate. Produced by `hivemind:prd-to-issues` (planned skill — not yet implemented).
_Alias_: tracer bullet
_Avoid_: module, horizontal slice, layer

**Handoff**:
The optional, ephemeral session-resumption artifact at `.hivemind/handoffs/<slug>.md`, produced by `hivemind:create-handoff` (planned skill — not yet implemented). Carries volatile session state (locked decisions, first actions, open questions, pointers) to bridge into a fresh session; points to the plan/PRD rather than duplicating them. Gitignored, disposable once loaded.
_Avoid_: essence (which is the worker report), spawn

### Workflow State Machine

**Workflow Definition**:
A declarative JSON file under `plugin/workflows/<id>.json` enumerating a workflow's legal states and named transitions. Read-only at runtime, parsed by `jq`. Names WHO acts (agent/skill/overlord decision) and WHAT outcomes are legal next — never WHY an outcome is chosen (the WHO/WHAT-not-WHY invariant, ADR-0018). Authored as JSON (not YAML) because the deterministic engine parses it; `description` fields replace comments.
_Avoid_: workflow YAML, STT, state table, workflow spec

**Run Ledger**:
The per-instance JSON file at `.hivemind/runs/<run-id>/state.json` recording one overlord instance's workflow progress — current state, event log, facts, blockers. The source of truth for progress (conversation memory is not). Written via temp-write + atomic rename; untrusted fields serialized with `jq --arg`. Owned and mutated only by the instance whose worktree contains it.
_Avoid_: state file, run state, progress log

**Workflow Router**:
The `hivemind:route-workflow` skill — the sole classifier that selects a workflow for a request by judgment (never a keyword lookup table). Outcomes: `selected`, `ambiguous` (2+ known → confirm gate), `exploratory` (no known match → catch-all), `blocked` (unsafe/illegible only). Keeps the overlord flat as the workflow catalog grows: a new workflow = a new definition + one routing rule.
_Avoid_: classifier, dispatcher, intent matcher

**Exploratory Intent Session**:
The catch-all workflow (`exploratory-intent-session`) the router selects when no concrete workflow matches. Handles novel requests in a bounded, ledgered, observable way and emits an advisory recommendation on whether the pattern should be codified into a new workflow — never auto-authoring one. The data-driven nursery for future workflows; the router must prefer concrete workflows over it.
_Avoid_: default workflow, fallback workflow, misc

**Transition Engine**:
The committed `record-state-result.sh` script (with `init-run-ledger.sh`) that deterministically reads the ledger + definition, validates `result ∈ allowed`, mutates, and atomically writes. The skill is a thin navigator; the script owns the determinism (the `spawn-brood.sh` precedent).
_Avoid_: advance-workflow, state updater

**Run Ownership**:
The policy (RUN-OWNERSHIP-01) that a run ledger is owned and mutated only by the overlord instance whose worktree contains it; cross-instance reads (hatchery → child ledger) are read-only. Enforced by worktree isolation, not convention; the brood manifest is the sole shared artifact and only the hatchery writes it.
_Avoid_: ledger lock, write policy

**Intent-Driven Fallback**:
The universal degradation posture: whenever the deterministic substrate is unavailable or invalidated — workflow-definition version skew across a plugin upgrade, a torn/missing ledger, an unresolvable state — the overlord finishes by judgment (transition gating suspended, run marked `intent_fallback`) rather than hard-failing. Determinism only ever adds safety/observability; it never strands a run. Worst case equals pure-intent behavior.
_Avoid_: degraded mode, manual mode, safe mode

## Relationships

- An **Overlord** (orchestrator) spawns exactly one **Cerebrate**, **Drone**, **Changeling**, **Local-Reviewer**, or **GitHub-Reviewer** per **Phase**
- A **Directive** (plan artifact) contains one or more steps (`STEP-NNN`), each assigned to exactly one **Drone** or **Changeling**
- A **Spawn** (delegation) targets exactly one **Step** (`STEP-NNN`) from the **Directive**, or a single task when the **Reflex** (trivial fast path) applies
- A **Phase** produces exactly one **Essence** (handoff) on success
- A **Working Branch** maps to exactly one **Directive** and one PR
- An **Adaptation Cycle** (review loop) may produce zero or more **Remediation** cycles
- A **Mutation Decay** (break-fix-break cycle) terminates an **Adaptation Cycle** with mandatory **Flare** (escalation)
- **Creep Stagnation** (diminishing-returns exit) ends an **Adaptation Cycle** advisorily — the local-reviewer recommends stopping; the **Overlord** surfaces the choice to the **Overmind**. Checked only after the **Mutation Decay** check clears AND after the fix step's checkpoint has committed every auto-fixable finding's fix, never while any actionable finding (critical/high, escalatable, or otherwise fixable) is open, and never at the iteration ceiling
- A **Bump Trigger** fires at most one version increment per PR
- Each agent loads specific **Governance Docs** per its `Load and follow` list
- A **Bioform** is the collective genus; each **Overlord**, **Cerebrate**, **Drone**, and **Changeling** is a bioform
- **Trunk Freshness** is a sub-check within **Git Preflight**, gating **Working Branch** creation
- The **Swarm** is the whole; a **Brood** is a tactical subgroup of the **Swarm**
- hivemind maps StarCraft canon by cognitive function, not command rank: the **Overmind** (user) issues the swarm's will; the **Cerebrate** (strategist) is the brain that encodes that will into a **Directive** (strategic intent); the **Overlord** (orchestrator) is the psionic relay that interprets the Directive and distributes execution to **Drone**/**Changeling**. (Canon: cerebrates planned campaigns; overlords served operationally, relaying directives and sustaining swarm cohesion.)

- A **Fix Ledger** persists across iterations of an **Adaptation Cycle**, tracking finding status from open through fixed or cycling
- The **Destructive Fix Gate** overrides normal **Remediation** flow, requiring human approval before commit
- A **Fix Mode** invocation processes existing unresolved feedback in a single **Remediation** pass
- The **Overlord** executes the **GitHub Review Loop** skill by default once a PR is opened — watching is opt-out only — and hosts its **Monitor**; the skill dispatches the **GitHub-Reviewer** in fix mode per actionable event, producing zero or more **Remediation** cycles bounded by `max_remediation_cycles`, whose floor is declared and enforced by the loop's own bookkeeping script `plugin/skills/github-review-loop/scripts/loop-state.sh`: each completed cycle re-arms a fresh idle window, while a quiet window with no new arrivals ends the watch as a terminal distinct from the cycle ceiling
- The **GitHub Review Loop** skill — not the **GitHub-Reviewer** — owns monitoring; the reviewer is stateless and only remediates. The **Overlord** must not claim active monitoring for a returned reviewer run
- A **Codex Approval** ends a **GitHub Review Loop** invocation only when no unresolved non-self actionable items remain
- A **Worker Report** is the structured output of every **Phase**, consumed as input to an **Essence**
- **Intent-Based Governance** defines which rules remain mechanical (**Unsafe Git State**, **Destructive Fix Gate**, **External Content Boundary**, report schemas) vs intent-described
- An **Unsafe Git State** blocks all modifying agent operations until resolved

- An **Overlord** records a **Decision Journal** entry for every Tier-B decision; the **Promotion Gate** decides whether the decision is auto-taken or surfaced to the **Overmind**
- A **Decision Report** is produced once per merged PR that contains ≥1 auto **Disposition** (`did-now`, `deferred`, or `recorded`), rendered in the consumer's ubiquitous language
- **Remediation** Tier-B choices (planner-escalation, root-cluster routing) are auto-taken + journaled unless the **Promotion Gate** trips

- A **Brood** contains one or more **Strains**, each running in a separate git worktree
- A **Brood-Plan** produces exactly one **Strain** per independent work bucket
- Each **Strain** maps to exactly one child **Overlord** session, one **Working Branch**, and one PR
- A **Hatchery** (coordinator mode) overlord dispatches one **Brood** and monitors via the **Brood Manifest**
- A **Brood-Plan** is distinct from a **Directive**: brood-plans contain strain descriptions, directives contain steps (`STEP-NNN`)

- A completed phase produces **Essence** consumed by the next phase's **Spawn**
- A **Flare** terminates a phase and returns control to the **Overlord**
- A **Reflex** bypasses the **Cerebrate** entirely — **Overlord** spawns directly
- An **Adaptation Cycle** may trigger **Mutation Decay**, forcing a **Flare**

- An **Initiative** correlates exactly one plan, at most one **Handoff**, at most one **PRD**, and zero or more slice issues, all under one slug
- A **PRD** (WHAT) is distinct from a **Directive** (HOW): the PRD carries stories/acceptance/metrics; the Directive carries steps/file-scope/sequence — no duplication
- `hivemind:plan-to-prd`, `hivemind:prd-to-issues`, and `hivemind:create-handoff` (planned skills — not yet implemented) are designed as decoupled leaf transforms — none invokes another (ADR-0013); their output is path-agnostic (ADR-0012)
- A **Vertical Slice** becomes one GitHub issue and one **Strain** candidate; the **Cerebrate** re-derives file overlap at brood-time and remains the sole independence authority (issues never self-declare scope)

- A **Workflow Router** selects exactly one **Workflow Definition** for a request, or routes to the **Exploratory Intent Session** when no concrete workflow matches; the **Overlord** then executes that definition's states, advancing only via the **Transition Engine** and recording progress in the **Run Ledger**
- A **Reflex** (trivial fast path) bypasses the **Workflow Router** and the **Run Ledger** entirely — the **Overlord** drives the short delivery tail by intent, just as it skips the **Cerebrate**
- **Intent-Driven Fallback** is the floor beneath every **Workflow Definition**: when the deterministic substrate is invalidated, execution degrades to judgment rather than failing
- **Run Ownership** (RUN-OWNERSHIP-01) is enforced by worktree isolation; a **Hatchery** reads child **Run Ledgers** read-only and never mutates them (consistent with ADR-0007)
- The declarative **Workflow Definition** + **Run Ledger** are JSON (parsed by `jq`); all inter-agent/human-read contracts stay YAML — format follows consumer (ADR-0018)

## Example dialogue

> **Dev:** "This is a one-line typo fix in a governance doc — do I still need the **Cerebrate** (planner)?"
> **Domain expert:** "Check the **Reflex** (trivial fast path) conditions. If they all pass — one owner, one known file, trivial change, clear **Branch Classification**, no version impact, not **Remediation** — the **Overlord** skips the **Cerebrate** and spawns a **Drone** directly."

> **Dev:** "The **Adaptation Cycle** (review loop) keeps flipping between two states — what happens?"
> **Domain expert:** "That's **Mutation Decay** (break-fix-break). When 2-of-3 signals fire (line-range overlap, git revert, N-2 oscillation), the cycle stops and the **Overlord** flares to the user. No more automatic **Remediation** until a human decides."

> **Dev:** "The **GitHub Review Loop** dispatched the **GitHub-Reviewer**, which found a fix that removes an auth check — does it apply it?"
> **Domain expert:** "No. That hits the **Destructive Fix Gate** — category 1, removing authentication. The reviewer returns blocked and surfaces the proposed change for human approval before committing."

> **Dev:** "I have three independent features to build — should I use a brood?"
> **Domain expert:** "If the **Cerebrate** confirms they decompose into independent **Strains** with minimal file overlap, yes. The **Overlord** will present the **Brood-Plan** for your confirmation, then enter **Hatchery** (coordinator mode) to dispatch each **Strain** as a separate session via **spawn-brood**. Each child session runs a full pipeline independently — same as any solo task."

> **Dev:** "The **Cerebrate** produced a **Directive** with 5 **Steps** — does the **Overlord** execute them all at once?"
> **Domain expert:** "No. Each **Step** becomes one **Phase** — a single **Spawn** round-trip to a **Drone** or **Changeling**. The **Overlord** runs them sequentially: spawn, wait for **Essence**, **Verify** (scope compliance, report schema, git safety), **Molt** the progress, then spawn the next. The **Overmind** (you) only hears about it if something flares."

> **Dev:** "What's the difference between the **Swarm** and a **Brood**?"
> **Domain expert:** "The **Swarm** is the whole — every **Bioform** and operational composite acting as one governed system. A **Brood** is a tactical subgroup: multiple **Overlords** running independent **Strains** in parallel worktrees. One **Swarm**, many possible **Broods**."

## Flagged ambiguities

- "phase" vs "step" — resolved and promoted to glossary terms: **Step** is the cerebrate's unit of work (`STEP-NNN`); **Phase** is the overlord's unit of execution (one spawn round-trip). They correspond 1:1 for planned work; reflex tasks have a single phase with no step.
- "essence" vs "spawn" — resolved: **Spawn** (delegation) flows downward (overlord to worker); **Essence** (handoff) flows upward/forward (worker report stored for future phases).
- "scope" — resolved: always means file scope (the explicit file list in a spawn), never task scope or project scope.
- "validation" vs "verification" — resolved and promoted to glossary terms: **Validation** means running declared project commands; **Verification** means the overlord's post-phase acceptance checks (scope compliance, report schema conformance, git state safety).
