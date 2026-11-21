# Abathur council: one decision service for calls with no strong recommendation

**Status:** accepted, 2026-11-21. Amends ADR-0026 decision 2 (a weak or absent recommendation with a clean gate goes to the council before defer-or-record), ADR-0036 decision 6 (`decide()` gains the consult action, so a weak recommendation is consulted before it is taken) and ADR-0045 decision 7 (a choice with no recommendation goes to the council before it parks). The user approved these amendments on 2026-11-21. None of the three ADR files is edited.

## Context

[docs/prds/idea-to-ready.md](../prds/idea-to-ready.md) asks for a council: a decision service for choices with no strong recommendation. Several members look at one call from different angles and, where configured, on different models. Abathur weighs them into one brief that keeps the dissent. The HOW is in [docs/initiatives/idea-to-ready/solution-design.md](../initiatives/idea-to-ready/solution-design.md), sections Abathur council, Mid-delivery consult, Council brief contract and Consult row, and decisions D12, D13, D14 and D21. The idea-to-ready process itself is [ADR-0046](0046-idea-to-ready-process.md); the council has its own ADR so it can be amended alone.

Today a call with no strong recommendation has no second opinion:
- `decide()` returns only `ask` or `take`, and takes a weak recommendation (ADR-0036 decision 6).
- Under ADR-0026 decision 2, a weak or absent recommendation with a clean gate is deferred or recorded.
- Under ADR-0045 decision 7, a choice with no recommendation parks an unattended Lair strain.
- `plugin/references/decision-brief-schema.json` carries `recommendation.strength` but no dissent or member provenance.

The council absorbs and rescopes the council work of the earlier Abathur and Scout epic (#440, closed). That epic named its council member Synapse, a name now taken by the runner agent.

## Decision

1. **One decision service, two callers, one contract.** Abathur is called from the design stages, when the solution design or the design review raises a choice with no strong recommendation, and from standard-delivery mid-run, when the engine would otherwise ask or park. Both callers use the same contract.
2. **The contract is the decision brief, extended.** Input is a brief valid against `plugin/references/decision-brief-schema.json`. Output is a brief valid against the same schema, extended with an optional `council` object:
   - `members`, each with `id`, `angle`, `model`, `option_id`, `strength` and `why`;
   - `dissent`, each with `member_id`, `option_id` and `why`.

   `recommendation.strength` is the council's strength. Abathur may recommend only one of the input brief's option ids; `decide()` already asks `recommendation_not_an_option` otherwise.
3. **The convening rule is data: a consult row with a per-run cap.** The autonomy table gains one row, kind `council_consult`, with a cell per level of `consult` or `skip` and an integer `per_run_cap`. `decide()` gains an optional `consults_used` input; with it absent, nothing changes. With it present, after every existing check through `gate_safety` passes, `decide()` returns `{action: 'consult'}` when the strength is `weak` or `none`, the brief has no `council` object, the cell at the run's level is `consult`, and `consults_used` is below `per_run_cap`. A call site never passes `council_consult` as its kind; if one does, `decide()` asks `bad_cell` and fails closed.
4. **Hard stops and promotion-gate trips are never consulted.** Hard stops, `table_surface` and gate trips ask before the consult check, so they never reach the council.
5. **The caller launches the members, then Abathur.** In the main session the conductor launches them. In standard-delivery the workflow script launches the Claude members, and the synapse agent runs the non-Claude member's committed runner command. Abathur never picks the members whose opinions it judges. Abathur and every member are read-only agents.
6. **At least two members, on different models.** A council result is used only with at least two members on at least two models. One member can be a non-Claude reviewer, run through the tool-neutral runner's reviewer setting and no-shell argv run in a brief mode. Per `docs/engineering-principles.md` P9 that mode shares only the runner's kernel, and the review mode's behavior and output do not change.
7. **What happens to a council result.** The council's brief re-enters `decide()`, which re-checks hard stops and every gate on the recommended option.
   - A strong result with a clean gate is taken, journaled and listed for veto under the list reason `council`.
   - A result below `strong` is a split and asks the new reason `council_split`.
   - A split or an always-ask call is asked in an interactive run, as one question with the dissent attached. In an unattended run it parks, carrying the brief and its dissent.
8. **The member is named Overseer.** The member agent is `overseer`, because Synapse is now the runner agent. The judge is `abathur`.
9. **Amendments of accepted ADRs.** With the user's approval, the council weighs a call with no strong recommendation before it is asked or parked:
   - ADR-0026 decision 2: a weak or absent recommendation with a clean gate goes to the council before defer-or-record.
   - ADR-0036 decision 6: `decide()` gains the consult action, so a weak recommendation is consulted before it is taken.
   - ADR-0045 decision 7: a choice with no recommendation goes to the council before it parks.

## Considered options

- **Abathur picks its own members.** Rejected: the judge would choose whose opinions it weighs.
- **A convening rule in prose or in code.** Rejected: the rule is table data, so a level or cap change is a data edit and `decide()` stays the one place a decision is resolved.
- **Consulting hard stops and gate trips too.** Rejected: those always reach the user, and a council could only delay them.
- **A single-model council.** Rejected: members on one model share one model's blind spots.
- **Reusing the name Synapse for the member.** Rejected: Synapse is the runner agent.
- **Recording the council in ADR-0046.** Rejected: a separate ADR lets the council be amended alone.

## Consequences

- Fewer runs stop on a weak call: a council either returns a strong recommendation, which is taken and listed for veto, or a real split with the dissent laid out.
- Each consult costs at least three agent runs, bounded by `per_run_cap`.
- A member that fails, times out or returns off schema leaves Abathur the rest. With fewer than two members, or off-schema Abathur output, there is no council result and the pre-consult outcome applies: ask, or park when unattended. The attempt counts toward the cap.
- Once the cap is reached, `decide()` resolves as it does without the council.
- Member opinions and Abathur's brief are data per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (External Content Boundary). A parked split shows its text encoded as untrusted data.
- The council adds no credential and does not change the merge path.

References: `docs/adr/0026-decision-autonomy-and-post-merge-report.md`, `docs/adr/0036-analysis-only-first-workflow-on-script-engine.md`, `docs/adr/0045-lair-software-factory.md`, `docs/adr/0046-idea-to-ready-process.md`, `docs/prds/idea-to-ready.md`, `docs/initiatives/idea-to-ready/solution-design.md`.
