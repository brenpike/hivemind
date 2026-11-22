# Abathur council: one decision service for calls with no strong recommendation

**Status:** accepted, 2026-11-21. Amends ADR-0026 decision 2 (for design-stage decisions and planner questions in standard-delivery, a weak or absent recommendation with a clean gate goes to the council before defer-or-record, unless it needs a fact only the user holds), ADR-0036 decision 6 (a weak planner question in standard-delivery goes to the council before it is taken: the consult runs ahead of an unchanged `decide()`, which stays the only place a decision is resolved) and ADR-0045 decision 7 (a planner question with no recommendation goes to the council before it parks, unless it needs a fact only the user holds). The user approved these amendments on 2026-11-21 and narrowed them to planner questions and design-stage decisions (D30; asked in design review round 2, answer Q6 A). None of the three ADR files is edited. It does not amend ADR-0037: `decide()`, `resolveDecision`, the Ask Set, list reasons and check order are unchanged, injection-suspect stays terminal, and a council re-plan enters planning through the facts step (ADR-0037 invariant 3). It does not amend ADR-0042 decision 9: `run-review.sh` still runs every local review.

## Context

[docs/prds/idea-to-ready.md](../prds/idea-to-ready.md) asks for a council: a decision service for choices with no strong recommendation. Several members look at one call from different angles and, where configured, on different models. Abathur weighs them into one recommendation, and the caller composes a brief that keeps the dissent. The HOW is in [docs/initiatives/idea-to-ready/solution-design.md](../initiatives/idea-to-ready/solution-design.md), sections Abathur council, Mid-delivery consult, Council brief contract, Runner member brief mode, Consult setting and Consult step, and decisions D12, D13, D14, D18, D21, D22, D23, D25, D26 and D30. The idea-to-ready process itself is [ADR-0046](0046-idea-to-ready-process.md); the council has its own ADR so it can be amended alone.

Today a call with no strong recommendation has no second opinion:
- `decide()` returns only `ask` or `take`, and takes a weak recommendation (ADR-0036 decision 6).
- Under ADR-0026 decision 2, a weak or absent recommendation with a clean gate is deferred or recorded.
- Under ADR-0045 decision 7, a choice with no recommendation parks an unattended Lair strain.
- `plugin/references/decision-brief-schema.json` carries `recommendation.strength` but no dissent or member provenance.

The council absorbs and rescopes the council work of the earlier Abathur and Scout epic (#440, closed). That epic named its council member Synapse, a name now taken by the runner agent.

## Decision

1. **One decision service, two callers, one contract.** Abathur is called from the design stages, for a design decision with no strong recommendation, and from standard-delivery, for a planner question with no strong recommendation, before the run asks or parks. Both callers use the same contract.
2. **The contract is the decision brief, composed by the caller.** Input is a brief valid against `plugin/references/decision-brief-schema.json`. #618 adds two optional fields: the `needs_user_fact` boolean, which a producer sets true when the answer needs a fact only the user holds and false otherwise, and the bounded `council` object. Options gain no `gate`. Existing briefs stay valid.
   - Each member returns `{option_id, strength, why}`, with strength `strong`, `weak` or `none`.
   - Abathur gets the input brief and the opinions as data and returns only `{option_id, strength, why}`: an `option_id` among the input's option ids and strength `strong` or `none`. A split is `none`. A `weak` strength, an unknown `option_id` or any other shape means no council result.
   - The caller composes the output brief: the input brief unchanged except `recommendation`, `gate` and `council`. Options, option ids, problem, criticality, assumptions and `needs_user_fact` never change.
   - On a strong Abathur result, `recommendation` is Abathur's option with strength `strong` and Abathur's why. The `gate` is the input's when that option is the input's recommended option, else a fresh producer gate read of that option: a fresh planner call in standard-delivery, the conductor in the design stages. With no usable gate read, or when Abathur returns `none`, the composed brief keeps the input's recommendation with strength `none` and the input's `gate`.
   - `members` has one entry per member that returned a valid opinion: `id`, `angle` and `model` from the caller's own launch record, and `option_id`, `strength` and `why` from that member's own output. `dissent` has one entry per member whose `option_id` differs from the composed recommendation's option: `member_id`, `option_id` and `why`.
   - No text a member or Abathur writes reaches options, problem, criticality, assumptions or `gate`, and a claimed model is ignored.
   - Bounds: `members` holds 2 to 4 items, counting a runner member, and `dissent` at most 4. Each `why` has maxLength 200 and is written for the user. `id`, `angle` and `model` have maxLength 64.
3. **The convening rule is data plus the site.** The autonomy table gains a top-level `council_consult` object beside `rows`, never a row. It holds one value per level, `consult` or `skip`, including `unattended` once #607 adds that level, and an integer `per_run_cap`.
   - In standard-delivery the consult weighs only planner questions, in `runPlanningPass` before `resolvePlanAsks`, once per new checked planner result.
   - It reads each question through `resolveDecision` with a scratch resolution. It convenes only when the question is not already settled, `needs_user_fact` is false, the read is a take of a `weak` recommendation or an ask with reason `no_recommendation`, `council_consult` at the run's level is `consult`, and the run's consult count is below `per_run_cap`.
   - It reads each composed brief the same way. A take on another option is listed as taken, and the run plans again from the facts step with the council's answer as a settled answer entry, outside `maxReplans()` and bounded by `per_run_cap`. A reason outside `askReasons()` gives no council result. Otherwise the composed brief replaces the question, and the unchanged `resolvePlanAsks` resolves it. A composed ask carries its raw question's key, so a reply settles the raw question: raised again, it resolves as answered and is never convened or taken. Within a pass, a raw question raised again reuses its composed brief, rebuilt on replay.
   - The count rises by one per convened council, whether or not it returns a result. The count and the council answers are script-local, start empty on each launch and are rebuilt as a replay passes the same steps. They never enter `run.answerLog` or `resume_args`, which stays `{answers, build}`.
   - `decide()` gains no consult action and no `consults_used` input. No `council_split` ask reason and no `council` list reason exist.
   - In the design stages the conductor reads the value at the table's `default_level` and allows at most `per_run_cap` consults per guide invocation.
4. **What is never consulted.** Hard stops, malformed briefs, `table_surface`, `bad_cell`, gate trips, code-built briefs, every `buildUndecidedAsk` site (the validation fix limit among them), review calls (Review Calls: no second agent judges), and any question whose `needs_user_fact` is true or absent. Each is resolved as it came.
5. **The caller launches the members, then Abathur.** Abathur never picks the members whose opinions it judges. The caller launches two to four members in all: Overseers plus at most one runner member.
   - In the main session the conductor launches them. The overlord's Agent allowlist gains `hivemind:abathur` and `hivemind:overseer`, and its Write grant is unchanged (#622; asked, answer Q4 A).
   - In standard-delivery the workflow script launches the Claude members. Synapse runs the runner member as a sixth Synapse Runner Gate script, and the brief reaches that script only through one fixed inputs file, `.hivemind/council-inputs-<token>.json` (#618; asked, answer Q3 A). #618 seeds the `Edit(.hivemind/council-inputs-*.json)` rule through `plugin/skills/_shared/settings-merge.sh` (asked in design review round 2, answer Q7 A). The main-session guide reaches the script through `hivemind:council-member`, whose skill grant holds the script's Bash grant and its inputs-file entry. #618 widens two residual bullets of the Synapse Runner Gate in `plugin/governance/security-policy.md` to the sixth script, which runs the configured reviewer tool, and its inputs file.
   - Abathur and every member are read-only agents. A safety fixture under `tests/policy/` pins the `abathur` and `overseer` tools lists with no Bash, Write, Edit or agent-launch tool (#618).
6. **At least two members, on different models.** A council result counts only with at least two members whose `model` values differ.
   - The runner member runs only when `HIVEMIND_LOCAL_REVIEWER` is a JSON argv list. Unset or the `codex-plugin` preset means no runner member, and the council then needs two Claude members on two Claude models.
   - The runner member's `model` is `runner:` plus the basename of argv[0]. It names the tool, never a model (ADR-0042 decision 7).
   - Per `docs/engineering-principles.md` P9 the brief mode shares only the runner's kernel with `run-review.sh`: the reviewer-setting read and argv check, the no-shell argv run under `timeout -k 5 <deadline>`, the before/after work-tree check, where any change blocks and discards the opinion, and the reply JSON extraction. The kernel moves to `plugin/skills/_shared/`. Review mode's behavior and output do not change.
7. **What happens to a council result.** `decide()` resolves every composed brief, so a gate trip asks.
   - A strong result on the producer's option is taken, journaled and shown in the pull request decisions.
   - A strong result on another option with a clean producer gate read is journaled and shown, and the run plans again with it settled, so the plan that runs is built on it. A gate trip asks, or parks in an unattended run.
   - A split or `none` asks `no_recommendation` with the dissent attached. In an unattended run it parks, carrying the brief and its dissent (#607).
   - A question marked `needs_user_fact` true, or with the field absent, is never convened, so it reaches the user as it would with no council.
   - Every member and Abathur delegation carries `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Delegation Data-Boundary Constraint).
   - Member opinions are injection-scanned before Abathur, and Abathur's output before compose. A suspect one ends the run with the pass scan's terminal stop (ADR-0037), is an approval park in an unattended run (ADR-0045 decision 7), and is asked in the design stages. The first result never stands. A scan that fails, times out or returns an unusable result gives no council result, and the question is resolved as it came. In the design stages the conductor classifies each opinion before launching Abathur, and Abathur's output before writing, per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Injection-Suspect Classification). Council text reaches a planner prompt only inside a question shown to the user: scanned, each why at most 200 characters, encoded as untrusted text.
8. **The member is named Overseer.** The member agent is `overseer`, because Synapse is now the runner agent. The judge is `abathur`.
9. **Amendments of accepted ADRs.** With the user's approval, narrowed by D30 (asked in design review round 2, answer Q6 A), the council weighs a planner question or design-stage decision with no strong recommendation before it is asked or parked:
   - ADR-0026 decision 2: for design-stage decisions and planner questions in standard-delivery, a weak or absent recommendation with a clean gate goes to the council before defer-or-record, unless it needs a fact only the user holds.
   - ADR-0036 decision 6: a weak planner question in standard-delivery goes to the council before it is taken. The consult runs ahead of an unchanged `decide()`, which stays the only place a decision is resolved.
   - ADR-0045 decision 7: a planner question with no recommendation goes to the council before it parks, unless it needs a fact only the user holds.

## Considered options

- **Abathur picks its own members.** Rejected: the judge would choose whose opinions it weighs.
- **A convening rule in prose or in code.** Rejected: the rule is table data, so a level or cap change is a data edit and `decide()` stays the one place a decision is resolved.
- **Consulting hard stops and gate trips too.** Rejected: those always reach the user, and a council could only delay them.
- **A single-model council.** Rejected: members on one model share one model's blind spots.
- **Reusing the name Synapse for the member.** Rejected: Synapse is the runner agent.
- **Recording the council in ADR-0046.** Rejected: a separate ADR lets the council be amended alone.
- **Consult as a third `decide()` action with a `council_split` ask reason.** Rejected: it amends ADR-0037's closed Ask Set and breaks the build projection.
- **Abathur writing the whole output brief.** Rejected: it could rewrite a gate or member provenance.
- **The consult setting as a table row.** Rejected: rows hold only auto or surface cells, and a call site could pass it as a kind.
- **A runner member under the `codex-plugin` preset.** Rejected: the preset has no prompt path.
- **Consulting inside `resolveDecision` at every call site.** Rejected: `resolveDecision` is synchronous, the validation fix limit throws on a take, and review calls admit no second agent.
- **A council that may only confirm the producer's weak recommendation.** Rejected by the user (asked in design review round 2, answer Q6 A): it removes no stop.
- **A per-option gate on every option.** Rejected: it is a second brief field where Q6 A adds one, and a gate read reads only the option the council picked.
- **Taking a switched option without a re-plan.** Rejected: it journals a take the plan does not implement.
- **A council answering a question whose `needs_user_fact` is absent.** Rejected: a producer that leaves the field out would let the council answer a fact only the user holds.
- **Ending the consult at the `injection_suspect` hard stop.** Rejected: that stop asks, and ADR-0037 keeps injection-suspect terminal.

## Consequences

- Fewer runs stop: a weak or unanswered planner question the council answers strongly is taken, on the planner's option or, with a clean gate read, on another, and a real split is asked with the dissent. A question that needs a fact only the user holds never goes to the council.
- Each standard-delivery consult costs at least five agent runs (two members, Abathur, two scans), and a switch adds a gate read and a new pass, bounded by `per_run_cap`.
- A member that fails, times out or returns off schema leaves Abathur the rest. With fewer than two members on two models, or off-schema Abathur output, there is no council result and the question is resolved as it came. The attempt counts toward the cap. A failed scan gives no council result, and the attempt counts toward the cap.
- Once the cap is reached, the question is resolved as it came.
- `decide()`, `resolveDecision` and `resolvePlanAsks` are unchanged: the Ask Set, list reasons, check order and `resume_args` stay as they are.
- Whether a later plan honors a council answer is the planner's judgment, as for a user's answer. Both are listed for veto in the pull request decisions.
- Member opinions and Abathur's output are data per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (External Content Boundary). A parked split or always-ask call carries its text encoded as untrusted data in the park record.
- The council adds no credential and does not change the merge path.

References: `docs/adr/0026-decision-autonomy-and-post-merge-report.md`, `docs/adr/0036-analysis-only-first-workflow-on-script-engine.md`, `docs/adr/0045-lair-software-factory.md`, `docs/adr/0046-idea-to-ready-process.md`, `docs/prds/idea-to-ready.md`, `docs/initiatives/idea-to-ready/solution-design.md`.
