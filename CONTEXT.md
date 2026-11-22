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

**Synapse**:
The runner agent — a haiku relay that runs one committed hivemind script (facts, commit, push or pull request) and reports its output word for word. Only workflow scripts start it; the overlord never delegates to it. A plugin `PreToolUse` hook allows it the five exact runner commands with no prompt and denies any other command that names one of those scripts, for every agent. Not a bioform.
_Avoid_: runner, shell agent

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
An instinctive response that bypasses the cerebrate and the router when every Reflex condition in `plugin/agents/overlord.md` (`## Reflex (Ledger-Skip)`) holds; the overlord checks it before routing.
_Alias_: trivial fast path (TFP)
_Avoid_: quick path, shortcut

**Instinct**:
A permanent, named delivery path for a non-Reflex `standard-delivery` request, beside the script engine. The overlord drives it by judgment — no workflow script, no **Run Ledger**, no state-machine gating. Pairs with **Reflex**: Reflex is the trivial fast path, Instinct the full delivery done by intent. It names what every run must have (a plan, a **Working Branch**, delegated edits, **Molt** commits and the delivery gates) and leaves order to judgment; not a step sequence. It is also the fallback for a refused or failed `standard-delivery` engine run. A started run the **Guide** launched is the exception: when it fails or ends blocked it returns to the **Guide** (ADR-0046). The path choice and the fallback rules live in `plugin/agents/overlord.md` (`## Engine`, `## Instinct`) and ADR-0039.
_Avoid_: light path (the placeholder name), intent-driven fallback (the degraded mode of a ledgered run), manual mode

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
The pre-branch sub-check within Git Preflight verifying trunk is up-to-date with its remote tracking branch before creating a working branch. Staleness is decided by the `trunk_stale` row of the decision autonomy table (taken at high autonomy, surfaced otherwise), not always asked.
_Avoid_: sync check, remote check

**Git Preflight**:
The set of checks (classification, base branch, trunk freshness, branch name, commit policy, PR target) that must all be defined before implementation begins.
_Avoid_: pre-check, setup

**Ready Issue**:
An open issue labeled `readiness:ready` (the `hivemind:triage-backlog` readiness ladder, gated on the **Readiness Check**) whose latest ready label came from a user with write access and whose title and body are unedited since. It is never an epic, it passes the **Readiness Check** at claim time, and it has no open blocked-by dependency. It is the only kind of issue the **Lair** claims. The Lair never applies the ready label itself. An issue that fails the check stays unclaimed, gets no new label, and is named in the tick's queue report. An issue may carry the ready label while blocked-by links are open, but the Lair claims it only when none is open. Lair admission is ADR-0045 decision 10, as amended by #625.
_Avoid_: groomed issue, actionable issue, loop-eligible issue

### Review

**Adaptation Cycle**:
The iterative cycle where a reviewer agent runs the configured **Local Reviewer**, classifies findings, fixes simple issues directly (≤2 files), flares complex ones to the overlord, validates, and repeats until stable or a stop condition fires. The bare alias "review loop" always means THIS local pre-PR cycle, which runs the configured **Local Reviewer** — distinct from the **GitHub Review Loop** skill, which is the post-PR watch.
_Alias_: review loop
_Avoid_: review cycle (ambiguous with remediation cycle), feedback loop

**Local Reviewer**:
The `HIVEMIND_LOCAL_REVIEWER` setting that picks the tool the **Adaptation Cycle** runs: a **Review Preset** name or a JSON argv list with an optional `{prompt}` slot; unset falls back to the `codex-plugin` preset when Codex is installed, else local review is skipped.
_Avoid_: review CLI, codex override

**Review Preset**:
A named, built-in **Local Reviewer** configuration; today only `codex-plugin`, which calls the Codex plugin's own adversarial-review command.
_Avoid_: adapter, profile

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
The main-session skill (`hivemind:github-review-loop`, executed by the overlord) that watches a single PR via a thin change-detection poll armed on a Monitor and dispatches the github-reviewer agent in fix mode per actionable event. It owns the loop lifecycle — cycle counting, continue/stop decisions, and the single terminal report to the overlord — but never reads, interprets, or classifies feedback (that is the reviewer's job). It returns ONLY on a terminal condition: merged, closed, max cycles, an idle window elapsing with no new review activity (distinct from the cycle ceiling), same-finding-repeat, deferred escalation, injection-suspect, or a **Reviewer Approval** with nothing actionable remaining. Distinct from the **Adaptation Cycle** ("review loop"), which is the local pre-PR cycle that runs the configured **Local Reviewer**. Operational detail of its remediation signals now in `hivemind:detect-remediation-signals`; remediation policy in the **Remediation Doctrine**.
_Avoid_: watch mode, polling mode, monitor mode, continuous mode, background watch

**Automated Reviewer**:
A Bot account that has submitted a PR review on the watched PR or left a 👍 on the pull request object, plus any Bot login named in `HIVEMIND_PR_REVIEWERS`, which adds to that set and never narrows it. No reviewer product is named in code. Identity is actor type `Bot`, never login alone: a bare login can collide with a human account (the human `claude` vs the `claude[bot]` app). `github-actions[bot]` counts only when named in `HIVEMIND_PR_REVIEWERS` (ADR-0033).
_Avoid_: review bot, any bot, reviewer app, reviewer registry

**Reviewer Filter**:
The `reviewer_filter` setting that scopes which comment authors the **GitHub Review Loop** treats as actionable: `automated` (default — every **Automated Reviewer**, Bot-gated), `all` (every author), or `<login>` (that one login, matched whatever its actor type). A keyword shadows a same-named login. `codex-only` is retired and rejected. The active filter also scopes which reviewers can produce a **Reviewer Approval**.
_Avoid_: author filter, bot filter

**Reviewer Approval**:
The terminal signal that an in-scope **Automated Reviewer** is satisfied with a PR, with no product-specific signal: its latest review is `APPROVED`, or is `COMMENTED` with no inline review comments, or it left a 👍 `THUMBS_UP` reaction on the pull request object (👀 is never approval). A 👍 from any Bot account other than `github-actions[bot]` makes that Bot an **Automated Reviewer**. A settled form also counts: an in-scope **Automated Reviewer** has reviewed or 👍'd, no reviewer's latest review requests changes, no poll marker has printed for `SETTLE_SECONDS` (600) since the arm or the last `CHANGED`/`CI_FAILED`, and every review thread is resolved or ends in HIVEMIND's own reply, with the thread read complete. It covers a bot that leaves inline threads, sees them fixed and resolved, and never reviews again. Review text is never read for approval. Counts only from a reviewer in scope under the active **Reviewer Filter**. Surfaced to the loop as the `REVIEWER_APPROVED` marker, or `REVIEWER_SETTLED` for the settled form (poll-only, clock-based), which the loop handles exactly like `REVIEWER_APPROVED`. Terminal for the github-reviewer only when no unresolved non-self actionable items remain.
_Avoid_: codex approval, codex sign-off, thumbs-up comment

**Auto-Merge**:
The opt-in merge of a watched PR by the fixed script `merge-approved.sh`, run once by the **GitHub Review Loop** after a `clean` end on a **Reviewer Approval**. Off unless `HIVEMIND_AUTO_MERGE` names the method (`merge`, `squash` or `rebase`). No AI judgment: it merges only when the PR is open and not a draft, an in-scope **Automated Reviewer** reviewed or 👍'd, no reviewer's latest review requests changes, every review thread is settled, and the head commit's check rollup is `SUCCESS`, and it passes `--match-head-commit`. It retries with `--admin` only when the plain merge is refused, `HIVEMIND_AUTO_MERGE_ADMIN` is set, and its own check saw every check pass. Pending or failed CI keeps the watch running. ADR-0044 records it, amending ADR-0026 (the human always merges).
_Avoid_: merge-advised, agent merge, merge decision

**Remediation Doctrine**:
The governance doc (`plugin/governance/remediation-doctrine.md`) holding the shared, definitional policy meaning of root-cause review remediation — **First-Finding Triage**, Root-Cluster, Same-Framing Test, Closed-by-Construction Preference, Surface-Growth Escalation (a fix that adds more surface than it removes goes to the user as one architectural call), Bounded-Impact Gating, Defer-with-Scope (only for a finding that is not a found root cause; it routes the finding by destination — a tracked issue when it is work someone should do, a Recorded Residual when it is a decision rather than work), Recorded Residual (admissible only outside the recorded threat model, or for a class no fix on this engine can close, by user decision; never on origin), Recorded Decisions and **Repeat Findings**, Stop-and-Merge, and Severity as Sensitivity Modifier — loaded by both reviewers, the overlord, and the cerebrate so all four share one vocabulary. The one home for these rules on both engines: the standard-delivery script's review handling follows it too, and no consumer copies it (ADR-0038). Policy only; detection mechanics live in **detect-remediation-signals**.
_Avoid_: remediation policy, doctrine doc, remediation rules

**First-Finding Triage**:
The four questions answered at the first non-trivial review finding, before any fix is planned or applied: introduced or inherited (either way a found root cause is fixed at its source in the PR that found it), root class and owning layer, whether the surface can be removed instead of hardened, and whether the attacker or failure the finding assumes is inside the recorded threat model (if not, the finding is rejected by citing the record). Keyed on the first finding, never on a finding count. Defined in the **Remediation Doctrine**.
_Avoid_: cluster triage, triage at N findings, inherited-finding deferral

**Repeat Finding**:
A later review finding that contests a decision recorded in the repo — a user's rejection of a finding, or a threat model — on the branch or on trunk. The reviewer rejects it by citing the record, lists it for the user before the merge, does not fix it, and never asks again. Keyed on the recorded decision, never on a finding id (new every run) or a question (lives one run). A finding that shows a failure the record does not cover is new, not a repeat, and gets **First-Finding Triage**. Defined in the **Remediation Doctrine**.
_Avoid_: duplicate finding, same-finding-repeat (the GitHub Review Loop terminal), re-raised finding

**Root-Cluster**:
A set of N-or-more review findings sharing a root cause, surface, or fix-framing — the signal to stop per-finding patching and zoom out, because the findings are symptoms of one defect. The cluster threshold N is severity-tuned (N=2 on a high-severity just-touched surface, N=3 by default).
_Avoid_: finding group, batch, duplicate set

**`root-cluster-suspected`**:
The reviewer exit_reason that carries a detected **Root-Cluster** (shared surface, member thread/finding refs, hypothesized root cause, same-framing rationale). Routes the overlord to a cerebrate remediation zoom-out (`review_remediation_plan` / `review_remediation_plan_postpr`) for one structural fix instead of N narrow patches.
_Avoid_: cluster-found, zoom-out signal, whack-a-mole exit

**Merge-Advised**:
The advisory terminal (`merge_advised`) recommending a human merge of a converged bounded-tail PR — fired only when zero actionable threads remain, the remaining tail is bounded on a hardened surface with a structural home (per **Defer-with-Scope**), and each push spawns only a fresh bounded tail. The watch never merges on it, even with **Auto-Merge** on; the reason is carried as `advisory_reason`, `structural_home`, and `recommendation_text`.
_Alias_: stop-and-merge advisory
_Avoid_: merge signal, approved-to-merge

**detect-remediation-signals**:
The shared, store-agnostic detection skill (`hivemind:detect-remediation-signals`) invoked by both reviewers over a supplied fix-ledger; returns ONE verdict across four detectors (root-cluster, break-fix, diminishing-returns, merge-advisory). Emits a verdict, not an exit_reason — each reviewer maps the verdict to its own terminal. Operationalizes the **Remediation Doctrine**; carries the detection mechanics that the Mutation Decay / Creep Stagnation / GitHub Review Loop glossary entries point to.
_Avoid_: signal detector, classifier, cluster checker

### Decision Autonomy

**Decision Tier**:
The A/B classification of an overlord decision. Tier A = the closed Ask Set, always surfaced to the Overmind, such as an irreversible call, an architectural call, a hard stop or a call with no recommendation; Tier B = auto-decided and journaled by default. On the script engine only a call in the closed Ask Set asks. The run takes the rest and lists taken decisions under "Decided for you" on the PR for veto before merge, except the kinds README's Decisions on the PR names. Rules: `plugin/governance/decision-autonomy.md` (Decision Tiers, Review Calls).
_Avoid_: priority, severity

**Promotion Gate**:
The test that promotes a Tier-B decision back to a surface — trips when the recommended action is irreversible OR architectural blast radius OR safety-relevant (destructive-fix categories). A review call reads only the irreversible and architectural clauses, per `plugin/governance/decision-autonomy.md` (Review Calls).
_Avoid_: escalation gate, risk gate

**Decision Journal**:
The per-decision record (situation, options, trade-offs, recommendation strength, gate outcome, disposition, decision, rationale, reversibility) the overlord appends to the run ledger's `event.outputs.decisions[]` for every autonomous (and surfaced) decision.
_Avoid_: audit log, decision log

**Decision Report**:
The OPT-IN post-merge narrative the overlord surfaces after a PR merges — only when the decision report is enabled via `HIVEMIND_ENABLE_DECISION_REPORT` — recounting each autonomous decision in the consumer project's ubiquitous language; produced by `hivemind:decision-report`.
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
The machine-generated `brood-<uuidv4>` identifier (charset `^brood-[0-9a-f-]+$`) that names one brood — the per-brood isolation key. Generated internally by spawn-brood, injective by construction, and propagated into the per-brood state dir (`.hivemind/broods/<brood-id>/`), each strain's worktree (`.claude/worktrees/<brood-id>/<short>`), and tmux session (`<brood-id>-<short>`), so concurrent same-checkout broods never collide. Each child's working branch is named by its own run, not by the brood-id.
_Avoid_: brood slug, brood key, brood name

**Brood-Plan**:
The cerebrate's output artifact when work decomposes into multiple independent strains. Contains strain-level descriptions and scope boundaries, not step-level detail. Each strain becomes a separate child overlord session with its own full pipeline.
_Avoid_: multi-plan (which means sequential PRs, not parallel), meta-plan

**Strain**:
One independent unit of work within a brood-plan, assigned to a single child overlord session. Each strain has its own worktree, branch, pipeline execution, and PR. A Lair strain is started by the **Lair** per claim, or per **Lair Pull Request** as its remediation strain, outside any brood-plan; a remediation strain works on its pull request's branch.
_Avoid_: stream, task (too generic), work item, lane

**Brood Manifest**:
The per-brood JSON file at `.hivemind/broods/<brood-id>/manifest.json` (schema `manifest_version: 4`) in the spawning checkout (the current worktree; the main checkout for the top-level hatchery), tracking one brood's strains — their display worktree paths, tmux sessions, and status. New manifests carry no per-strain branch. Each brood owns a disjoint manifest under its brood-id directory; the hatchery enumerates them by globbing `.hivemind/broods/brood-*/manifest.json`.
_Avoid_: brood config, brood state, registry

**Lair**:
The Software Factory: a deterministic controller, with no model in it, that runs in a long-lived tmux window and reconciles GitHub each tick. It claims **Ready Issues**, starts one strain per claimed issue (an interactive session in its own worktree running standard-delivery in unattended mode) and at most one remediation strain per **Lair Pull Request**, on review feedback or a red CI result, reads each strain's result, owns the issue's labels, and is the only merger of its pull requests. GitHub holds its state; its local files are a rebuildable cache, except the key that signs its marker comments and its decision digest (ADR-0045 amendments of 2026-11-21 and 2026-11-22 to decision 2). For its strains it owns lifecycle, merge order and version coordination (ADR-0045).
_Alias_: Software Factory
_Avoid_: loop, autopilot, scheduler, daemon, Overmind

**Lair Pull Request**:
A pull request the **Lair** recorded on its claimed issue after checking a strain's complete result against GitHub: same repository, trunk base, the Lair's own login as author, and the result's branch and head. It stays one while its claim is live and the issue is open and carries `lair:claimed`. Only a Lair Pull Request can be merged by the Lair.
_Avoid_: strain PR, factory PR

**Park**:
The unattended-mode outcome for a stop a run may not take itself: the run ends without asking, pushes its branch when it has commits, and reports a typed park. An answerable park (a decision or a fact) puts its question on the issue and moves it to `readiness:needs-decision`, unless it is the issue's third park, which hands the issue off; a user with write access answers on the issue, and the answer re-enters as a settled decision when the issue is re-admitted. An approval park (a destructive fix, an external effect, injection-suspect content) hands the issue off for an interactive run. Distinct from the triage label `readiness:parked`, which means shelved.
_Avoid_: pause, block, hold, escalate

### Pipeline & Artifacts

**Initiative**:
The unit of work correlated by a single slug across its plan, Handoff, PRD, and issue set. One slug per initiative; the slug names `.hivemind/plans/<slug>.md`, `.hivemind/handoffs/<slug>.md`, `docs/prds/<slug>.md` and the folder `docs/initiatives/<slug>/`, which holds `solution-design.md` and `review-record.md`, and corresponds to the PRD-level parent (epic) issue whose native sub-issues are the sliced work items.
_Avoid_: project, epic, feature

**PRD**:
The committed, durable specification of WHAT an Initiative delivers, at `docs/prds/<slug>.md`. Contains problem statement, solution, user stories, acceptance criteria, implementation decisions (architectural/contract level), testing decisions, success metrics, and out-of-scope. Never carries file scope or step sequencing — that is the Directive. Produced by `hivemind:plan-to-prd`.
_Avoid_: spec, design doc, directive

**Vertical Slice**:
A thin, end-to-end unit of behavior cutting every layer, small enough to be independently grabbable; one slice = one GitHub issue = one Strain candidate. Produced by `hivemind:prd-to-issues`.
_Alias_: tracer bullet
_Avoid_: module, horizontal slice, layer

**Handoff**:
The optional, ephemeral session-resumption artifact at `.hivemind/handoffs/<slug>.md`, produced by `hivemind:create-handoff`. Carries volatile session state (locked decisions, first actions, open questions, pointers) to bridge into a fresh session; points to the plan/PRD rather than duplicating them. Gitignored, disposable once loaded.
_Avoid_: essence (which is the worker report), spawn

**Solution Design**:
The committed HOW of an **Initiative**, at `docs/initiatives/<slug>/solution-design.md`, written after the **PRD** and before slicing. It names the components, state and ownership, contracts, trust boundaries, failure modes and decisions, each decision with its ADR or the ADR condition it fails, and its Open questions read exactly `None`. Each slice names the exact headings it implements. Once every slice is done it is marked delivered and never maintained again, and a slice that links it fails the **Readiness Check** (ADR-0046).
_Avoid_: design doc, directive (which is one run's plan), architecture doc

**Design Review**:
The review of an **Initiative**'s **PRD**, **Solution Design** and ADRs before the docs merge. Each round is one fresh read-only **Cerebrate** pass that carries no session memory and covers every angle, on the configured reviewer model, plus one pass by the configured local review tool when the design touches a trust boundary, credentials or the merge path. Round 1 covers the whole documents; each later, confirming round covers only the change since the previous round and the fixes to its findings. A round's findings land, each fixed or disposed, before the next round runs. It exits only with every open count (critical, high, medium and low) at 0 and one round with no new findings. A pass that errors yields no round, and a passing review has two or three rounds. A review not converged by round 3 reaches the maintainer, and the **Initiative** is split before its docs merge. Every finding gets exactly one disposition: fixed, rejected, deferred or recorded (ADR-0046).
_Avoid_: plan interrogation (which interviews the user), **Adaptation Cycle** (which reviews a code diff), design pass

**Review Record**:
The committed outcome of a **Design Review**, at `docs/initiatives/<slug>/review-record.md`, shipped in the same pull request as the **Solution Design**. It stamps the **PRD** and the **Solution Design**, and a passing record also every ADR its docs pull request adds or edits, each by its git blob id at the commit a review pass read, and records the verdict, the open findings by severity, the rounds, each pass's reviewer and model, every finding's disposition, the decisions taken (listed for veto) and the decisions asked (with the user's answer). Any later edit to a stamped document makes it stale until a review of the change re-stamps it. Its authority is a human-reviewed merge (ADR-0046). A record with an open finding or a failed verdict keeps its pull request a draft. Only the design review's record step writes or re-stamps it; a validation fix-round commit and a pr-feedback-remediation wave commit refuse it in code.
_Avoid_: review log, **Fix Ledger** (which tracks a pull request's review findings), **Decision Journal**

**Readiness Check**:
The one deterministic check, shared by triage, the **Guide**'s handoff check and **Lair** admission, that decides whether an issue may be a **Ready Issue** on its track. It checks structure, existence, versions and labels, never quality, and writes nothing. Each issue gets its track, pass or fail, and reason codes. A failed read is never a pass (ADR-0046).
_Avoid_: readiness rating, quality gate, triage (which applies the labels)

**Initiative Track**:
The track of an issue with a native parent epic, an initiative slice. Features and any change to a public contract or governance semantics take it. Its epic is the slices' native parent and never a slice itself. Its stages are the **PRD**, **Solution Design** and ADRs, **Design Review**, merged docs, slicing, triage, then the handoff check. A slice passes the **Readiness Check** only when its design section names a **Solution Design** whose **Review Record** passes and is not stale.
_Avoid_: feature track, full path, heavy track

**Standalone Track**:
The track of any issue with no native parent: bugs, chores, docs and small refactors, which carry a **Spec Block** in place of design documents and then go to triage. An issue whose type label is not bug, chore, documentation, refactor or enhancement, or whose effort label is large or extra-large, fails the **Readiness Check** with a promote reason: it belongs on the **Initiative Track**.
_Avoid_: light track, quick path, small-issue path

**Spec Block**:
The sections a **Standalone Track** issue body carries in place of design documents: Problem, Evidence, Acceptance Criteria, Scope boundary and Open questions. Each is non-empty, Acceptance Criteria holds at least one checklist item, and Open questions reads exactly `None`.
_Avoid_: issue template, mini-PRD, spec

**Guide**:
The user-only conductor skill, run in the main session, that takes the maintainer from an idea to **Ready Issues** with one command. Given nothing, it lists in-flight **Initiatives** with their stage. Given an idea, it starts one. Given an **Initiative**, it reports the stage, the evidence found and the next action, then starts that stage. It stores no progress: the stage is derived from GitHub and git. It invokes the leaf skills by intent and never applies `readiness:ready`; at the triage stage it sends the maintainer to triage (ADR-0046).
_Alias_: conductor
_Avoid_: wizard, pipeline runner, workflow (which takes no input mid-run)

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
- A **Reviewer Approval** ends a **GitHub Review Loop** invocation only when no unresolved non-self actionable items remain, and only from an **Automated Reviewer** in scope under the active **Reviewer Filter**
- **Auto-Merge** runs only after a **Reviewer Approval** ends a **GitHub Review Loop** clean, only when `HIVEMIND_AUTO_MERGE` is set, and never on **Merge-Advised**; with it off, the **Overmind** merges
- A **Worker Report** is the structured output of every **Phase**, consumed as input to an **Essence**
- **Intent-Based Governance** defines which rules remain mechanical (**Unsafe Git State**, **Destructive Fix Gate**, **External Content Boundary**, report schemas) vs intent-described
- An **Unsafe Git State** blocks all modifying agent operations until resolved

- An **Overlord** records a **Decision Journal** entry for every Tier-B decision; the **Promotion Gate** decides whether the decision is auto-taken or surfaced to the **Overmind**
- A **Decision Report** is produced once per merged PR that contains ≥1 auto **Disposition** (`did-now`, `deferred`, or `recorded`) when the decision report is enabled via `HIVEMIND_ENABLE_DECISION_REPORT`, rendered in the consumer's ubiquitous language
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

- An **Initiative** correlates exactly one plan, at most one **Handoff**, at most one **PRD** (exactly one on the **Initiative Track**), and zero or more slice issues, all under one slug
- A **PRD** (WHAT) is distinct from a **Directive** (HOW): the PRD carries stories/acceptance/metrics; the Directive carries steps/file-scope/sequence — no duplication
- `hivemind:plan-to-prd`, `hivemind:prd-to-issues`, and `hivemind:create-handoff` are designed as decoupled leaf transforms — none invokes another (ADR-0013); their output is path-agnostic (ADR-0012)
- A **Vertical Slice** becomes one GitHub issue and one **Strain** candidate; the **Cerebrate** re-derives file overlap at brood-time and remains the sole independence authority (issues never self-declare scope)
- An **Initiative** on the **Initiative Track** has exactly one **PRD**, one **Solution Design** and one **Review Record**, all under its slug; ADRs stay global and numbered in `docs/adr/`
- A **Design Review** produces exactly one **Review Record**, which stamps the **PRD** and the **Solution Design**, and once it passes every ADR its docs pull request adds or edits; an edit to any stamped document makes the record stale
- The **Readiness Check** reads an issue's track, never judges it: a native parent epic puts it on the **Initiative Track**, else it is on the **Standalone Track** and must carry a **Spec Block**
- Triage proposes `readiness:ready` only for an issue that passes the **Readiness Check**; the **Lair** re-runs the check at claim time and claims only a **Ready Issue**
- The **Guide** (conductor) orchestrates `hivemind:plan-interrogation`, `hivemind:plan-to-prd`, the **Design Review** and `hivemind:prd-to-issues` by intent, and leaves `readiness:ready` to the maintainer through triage

- A **Workflow Router** selects exactly one **Workflow Definition** for a request, or routes to the **Exploratory Intent Session** when no concrete workflow matches; outside **Instinct**, the **Overlord** then executes that definition's states, advancing only via the **Transition Engine** and recording progress in the **Run Ledger**
- A **Reflex** (trivial fast path) bypasses the **Workflow Router** and the **Run Ledger** entirely — the **Overlord** drives the short delivery tail by intent, just as it skips the **Cerebrate**
- **Instinct** follows the **Workflow Router** (it is taken only for `standard-delivery`) but bypasses the **Run Ledger** and the **Transition Engine** — unlike a **Reflex**, it keeps the **Cerebrate** plan, the **Working Branch**, and every delivery gate
- **Instinct** is the fallback for a refused or failed `standard-delivery` script-engine run, except a started run the **Guide** launched; its rules live in ADR-0039 and ADR-0046
- **Intent-Driven Fallback** is the floor beneath every **Workflow Definition**: when the deterministic substrate is invalidated, execution degrades to judgment rather than failing
- **Run Ownership** (RUN-OWNERSHIP-01) is enforced by worktree isolation; a **Hatchery** reads child **Run Ledgers** read-only and never mutates them (consistent with ADR-0007)
- The declarative **Workflow Definition** + **Run Ledger** are JSON (parsed by `jq`); all inter-agent/human-read contracts stay YAML — format follows consumer (ADR-0018)

## Example dialogue

> **Dev:** "This is a one-line typo fix in a governance doc — do I still need the **Cerebrate** (planner)?"
> **Domain expert:** "Check the **Reflex** (trivial fast path) conditions in `plugin/agents/overlord.md` first. If they all pass, the **Overlord** skips the **Cerebrate** and spawns a **Drone** directly."

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
- "light path" — placeholder name, resolved to **Instinct**.
