# Abathur council: one decision service for calls with no strong recommendation

**Status:** accepted, 2026-11-21. Amends ADR-0026 decision 2 (in the design stages and standard-delivery, a weak or absent recommendation with a clean gate goes to the council before defer-or-record), ADR-0036 decision 6 (a weak recommendation is consulted before it is taken: the consult step runs ahead of an unchanged `decide()`, which stays the only place a decision is resolved) and ADR-0045 decision 7 (a choice with no recommendation goes to the council before it parks). The user approved these amendments on 2026-11-21. None of the three ADR files is edited. It does not amend ADR-0037: `decide()`'s closed Ask Set, list reasons and check order are unchanged. It does not amend ADR-0042 decision 9: `run-review.sh` still runs every local review.

## Context

[docs/prds/idea-to-ready.md](../prds/idea-to-ready.md) asks for a council: a decision service for choices with no strong recommendation. Several members look at one call from different angles and, where configured, on different models. Abathur weighs them into one recommendation, and the caller composes a brief that keeps the dissent. The HOW is in [docs/initiatives/idea-to-ready/solution-design.md](../initiatives/idea-to-ready/solution-design.md), sections Abathur council, Mid-delivery consult, Council brief contract, Runner member brief mode, Consult setting and Consult step, and decisions D12, D13, D14, D18, D21, D22, D23, D25 and D26. The idea-to-ready process itself is [ADR-0046](0046-idea-to-ready-process.md); the council has its own ADR so it can be amended alone.

Today a call with no strong recommendation has no second opinion:
- `decide()` returns only `ask` or `take`, and takes a weak recommendation (ADR-0036 decision 6).
- Under ADR-0026 decision 2, a weak or absent recommendation with a clean gate is deferred or recorded.
- Under ADR-0045 decision 7, a choice with no recommendation parks an unattended Lair strain.
- `plugin/references/decision-brief-schema.json` carries `recommendation.strength` but no dissent or member provenance.

The council absorbs and rescopes the council work of the earlier Abathur and Scout epic (#440, closed). That epic named its council member Synapse, a name now taken by the runner agent.

## Decision

1. **One decision service, two callers, one contract.** Abathur is called from the design stages, when the solution design or the design review raises a choice with no strong recommendation, and from standard-delivery mid-run, when the engine would otherwise ask or park. Both callers use the same contract.
2. **The contract is the decision brief, composed by the caller.** Input is a brief valid against `plugin/references/decision-brief-schema.json`. #618 adds an optional per-option `gate` object (`irreversible`, `architectural`, `safety`), the producer's read of that option; existing briefs stay valid.
   - Each member returns `{option_id, strength, why}`, with strength `strong`, `weak` or `none`.
   - Abathur gets the input brief and the opinions as data and returns only `{option_id, strength, why}`, with strength `strong` or `none`. A split is `none`. A `weak` strength, an `option_id` not among the input's option ids, or any other shape means no council result.
   - The caller composes the output brief: the input brief unchanged except `recommendation`, which is Abathur's, plus an optional `council` object. `members` has one entry per member that returned a valid opinion: `id`, `angle` and `model` from the caller's own launch record, and `option_id`, `strength` and `why` from that member's own output. `dissent` has one entry per member whose `option_id` differs from the council's: `member_id`, `option_id` and `why`.
   - No text a member or Abathur writes reaches the gate, options, problem or criticality, and a claimed model is ignored. When the council's option differs from the input's recommended option, the caller sets the composed `gate` from that option's own `gate`. When that option carries none, the caller sets strength `none`, so the call asks.
   - Bounds: `members` holds 2 to 4 items and `dissent` at most 3. Each `why` has maxLength 200 and is written for the user. `id`, `angle` and `model` have maxLength 64.
3. **The convening rule is data: a consult setting with a per-run cap.** The autonomy table gains a top-level `council_consult` object beside `rows`, never a row. It holds one value per level, `consult` or `skip`, including `unattended` once #607 adds that level, and an integer `per_run_cap`.
   - In standard-delivery the consult step wraps an unchanged `decide()`. It calls `decide()` on the input brief and convenes the council only when the result is a take of a `weak` recommendation or an ask with reason `no_recommendation`, the kind is not a routine one (`plan_acceptance`, `remediation_plan_acceptance`, `gate_rerun`), `council_consult` at the run's level is `consult`, and the run's consult count is below `per_run_cap`. With a council result, a second `decide()` runs on the composed brief with the same kind, level and listed, and that result stands.
   - The count rises by one per convened council, whether or not it returns a result. It is a script-local counter that starts at 0 on each launch and is rebuilt as a replay passes the same steps, so `resume_args` stays `{answers, build}`.
   - `decide()` gains no consult action and no `consults_used` input. No `council_split` ask reason and no `council` list reason exist.
   - In the design stages the conductor reads the value at the table's `default_level` and allows at most `per_run_cap` consults per guide invocation.
4. **Hard stops and promotion-gate trips are never consulted.** The step convenes only on a weak take or a `no_recommendation` ask. A hard stop, a malformed brief, `table_surface`, `bad_cell` and every gate trip keep the first `decide()` result and never reach the council.
5. **The caller launches the members, then Abathur.** Abathur never picks the members whose opinions it judges.
   - In the main session the conductor launches them. The overlord's Agent allowlist gains `hivemind:abathur` and `hivemind:overseer`, and its Write grant is unchanged (#622; asked, answer Q4 A).
   - In standard-delivery the workflow script launches the Claude members. Synapse runs the runner member as a sixth Synapse Runner Gate script, and the brief reaches that script only through one fixed inputs file, `.hivemind/council-inputs-<token>.json` (#618; asked, answer Q3 A). The main-session guide reaches the script through its own skill grant.
   - Abathur and every member are read-only agents. A safety fixture under `tests/policy/` pins the `abathur` and `overseer` tools lists with no Bash, Write, Edit or agent-launch tool (#618).
6. **At least two members, on different models.** A council result counts only with at least two members whose `model` values differ.
   - The runner member runs only when `HIVEMIND_LOCAL_REVIEWER` is a JSON argv list. Unset or the `codex-plugin` preset means no runner member, and the council then needs two Claude members on two Claude models.
   - The runner member's `model` is `runner:` plus the basename of argv[0]. It names the tool, never a model (ADR-0042 decision 7).
   - Per `docs/engineering-principles.md` P9 the brief mode shares only the runner's kernel with `run-review.sh`: the reviewer-setting read and argv check, the no-shell argv run under `timeout -k 5 <deadline>`, the before/after work-tree check, where any change blocks and discards the opinion, and the reply JSON extraction. The kernel moves to `plugin/skills/_shared/`. Review mode's behavior and output do not change.
7. **What happens to a council result.** The second `decide()` re-checks hard stops and every gate on the recommended option.
   - A strong result with a clean gate is taken, journaled and shown in the pull request decisions.
   - A split comes back with strength `none`, so it asks `no_recommendation`. In an interactive run it is one question with the dissent attached. In an unattended run a split or an always-ask call parks, carrying the brief and its dissent (#607).
   - Every member and Abathur delegation carries `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Delegation Data-Boundary Constraint).
   - Member opinions and Abathur's output are injection-scanned. A suspect one ends the consult with no council result and stops at the `injection_suspect` hard stop: asked in an interactive run, an approval park in an unattended run (ADR-0045 decision 7).
8. **The member is named Overseer.** The member agent is `overseer`, because Synapse is now the runner agent. The judge is `abathur`.
9. **Amendments of accepted ADRs.** With the user's approval, the council weighs a call with no strong recommendation before it is asked or parked:
   - ADR-0026 decision 2: in the design stages and standard-delivery, a weak or absent recommendation with a clean gate goes to the council before defer-or-record.
   - ADR-0036 decision 6: a weak recommendation is consulted before it is taken. The consult step runs ahead of an unchanged `decide()`, which stays the only place a decision is resolved.
   - ADR-0045 decision 7: a choice with no recommendation goes to the council before it parks.

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

## Consequences

- Fewer runs stop on a weak call: a council either returns a strong recommendation, which is taken and shown in the pull request decisions, or a real split with the dissent laid out.
- Each consult costs at least three agent runs, bounded by `per_run_cap`.
- A member that fails, times out or returns off schema leaves Abathur the rest. With fewer than two members on two models, or off-schema Abathur output, there is no council result and the first `decide()` result stands. The attempt counts toward the cap.
- Once the cap is reached, the first `decide()` result stands.
- `decide()` is unchanged: its Ask Set, list reasons, check order and `resume_args` stay as they are.
- Member opinions and Abathur's output are data per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (External Content Boundary). A parked split or always-ask call carries its text encoded as untrusted data in the park record.
- The council adds no credential and does not change the merge path.

References: `docs/adr/0026-decision-autonomy-and-post-merge-report.md`, `docs/adr/0036-analysis-only-first-workflow-on-script-engine.md`, `docs/adr/0045-lair-software-factory.md`, `docs/adr/0046-idea-to-ready-process.md`, `docs/prds/idea-to-ready.md`, `docs/initiatives/idea-to-ready/solution-design.md`.
