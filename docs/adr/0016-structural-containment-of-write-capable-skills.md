# Write-capable user-driven skills are structurally contained by tool capability and spawn topology

**Status:** accepted — 2026-05-27

User-driven skills that carry `Write`/`Edit` in `allowed-tools` (e.g. `tdd`, `refactor-to-depth`) cannot mutate source outside the branch → checkpoint → review → PR lifecycle. Containment is structural — a property of agent tool grants and spawn topology — not an advisory rule, so no per-skill governance preflight is needed and the invariant covers all present and future write/edit skills.

## Context

The `refactor-to-depth` local review raised: can a write-capable skill the user invokes mutate product code outside the governed lifecycle? `refactor-to-depth` and `tdd` run tight write→test→edit→test loops, so they must edit locally; the question is whether that escapes governance. This ADR records why it structurally cannot.

## Decision

1. A skill is loaded instructions executing in the **invoking agent's** context, using that agent's `tools:`. `allowed-tools` only pre-approves (skips permission prompts) for tools the agent already holds; it never grants a capability the agent lacks.
2. The user reaches only the orchestrator (`hivemind:overlord`), whose `tools:` are `Read, Bash, Skill, Monitor, Agent(...)` — no `Write`, no `Edit`. A write/edit skill invoked at the orchestrator level physically cannot mutate files; its write intent routes through the orchestrator's normal delegate-to-executor lifecycle (git preflight → working branch → drone/changeling).
3. Write-capable executors (`hivemind:drone`, `hivemind:changeling`) are spawned only by the orchestrator, after git preflight, inside an established working branch. Loop-heavy write skills run **inside** such a delegated executor — the orchestrator delegates the whole task and the executor runs the loop locally — because ping-ponging each micro-write through the orchestrator would lose working state.
4. Therefore no user-reachable write-capable context exists outside the lifecycle. Containment follows from tool capability plus spawn topology, so no per-skill governance preflight is required.
5. Boundary: outside hivemind (a raw host session invoking the skill directly), the host framework owns governance; the skills stay portable and assume no lifecycle.

## Consequences

- No per-skill governance preflight is needed; the invariant generalizes to every current and future write/edit skill without per-skill review.
- The portability boundary (point 5) holds: the skills carry no hivemind lifecycle assumptions, so a raw-host invocation is governed by that host, not this plugin.
- `plugin/governance/security-policy.md` references this ADR as the rationale for treating write-capable skills as contained.

## Amendment 2026-11-02 (the containment rule and the skill-authoring rules live in `docs/skill-authoring.md`, outside the shipped plugin)

**Decision, by the user (2026-11-02, local review finding ebf6043b).** The Write-Capable Skill Containment rule, the Skill File-Tool Grants rule, the inputs-file transport argument, the transport-path invariant and the covered-navigator list stay in `docs/skill-authoring.md`, a repository file that is not part of the installed plugin. They do not move back into `plugin/governance/security-policy.md`, and they do not move to a shipped `plugin/governance/` file.

**Why.** These rules are authoring rules. Only skill authors, code review and CI (CHECK 14 and CHECK 16 in `tools/policy_check.sh`) use them, and no agent applies them at run time. The rationale behind them is already repository-only, in this ADR and in ADR-0010, ADR-0017, ADR-0018, ADR-0019 and ADR-0037. The runtime rules an agent follows stay in `plugin/governance/security-policy.md` ("Inert Inputs-File Navigator Pattern" and "Transport Degradation Is a Hard Stop").

**Bounded impact.** An installed plugin no longer carries the authoring rules, so a consumer who audits only the installed files does not see them. No runtime behavior changes: containment is structural, a property of agent tool grants and spawn topology per the Decision above, and holds whether or not any document states it. The grant rule is enforced in this repository by CHECK 16 before release.

**Pointers.** Each pointer below names where a rule is written. Each is read through this amendment, and the ADR texts themselves are unchanged.

1. This ADR, Consequences, third bullet: the containment rule this ADR gives the rationale for is the Write-Capable Skill Containment section of `docs/skill-authoring.md`, not `plugin/governance/security-policy.md`.
2. ADR-0017, Decision, the partial structural backstop paragraph: "Write-Capable Skill Containment, `plugin/governance/security-policy.md`" reads as the Write-Capable Skill Containment section of `docs/skill-authoring.md`.
3. ADR-0019, the transport-path invariant amendment, item 1: the invariant is written in `docs/skill-authoring.md` ("Transport-path invariant"), not in `plugin/governance/security-policy.md`.
4. ADR-0019, the live-source pointers for inputs-file transport: the transport argument, its path invariant and its covered set are in `docs/skill-authoring.md` ("Inputs-File Navigator Transport", "Transport-path invariant", "Covered Navigators"). The runtime rules stay in `plugin/governance/security-policy.md` ("Inert Inputs-File Navigator Pattern"), as ADR-0018's 2026-11-02 amendment states for the same pointers.

A later review finding that asks to move these rules back into the shipped plugin, only because the installed plugin lacks them, contests this decision and is a repeat.

This amendment is APPEND-ONLY. The original Decision and Consequences stand. Status remains accepted.
