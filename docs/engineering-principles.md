# Engineering Principles

Project-specific engineering principles for the hivemind plugin, distilled from the reviewer-prose-rescue interrogation. They govern how prose, scripts, and skills are factored across agents, skills, and governance. Where a principle is rooted in external best-practice it cites the source; otherwise it is a project decision. Referenced by `CLAUDE.md`.

## P1 — Single-source contract

A contract or spec lives in exactly ONE place. An extraction is not "done" until the duplicated prose copy is DELETED, not merely supplemented. Multi-site contracts drift, and one lagging site is a real defect — this was the root cause of the node-id escalation chain, where the same contract was smeared across a jq header, two agent steps, and a graphql reference doc.

## P2 — Spec moves with the mechanism

When procedure is extracted to a script, its spec moves WITH it as a contract-only header — the input/output schema, the invariants, and the WHY. The spec never just evaporates into undocumented code. The header narrates the contract, not the code line-by-line.

## P3 — Header without a test is decoration

A header comment can drift from the code below it in the same file; nothing enforces it. The same logic extends to governance: a section header naming specific consumers is an assertion about coupling, and nothing enforces it without a fixture. The general principle: any load-bearing contract — whether a script or a governance section with named consumers — is decoration until a CI fixture asserts the coupling.

This produces two enforcement triples in this repo:

1. **Script triple:** the script, the contract header, and a `test_*.sh` CI fixture. The test is the behavioral guarantee; the header is human-readable intent. (Precedent: `fix-history-classify.jq` paired with `test_fix_history_classify.sh`.)
2. **Governance triple:** the governance section, its named consumer list, and a `tests/policy/safety-*.json` consumer-assertion fixture. The fixture is the coupling guarantee; the section header is human-readable intent. (Precedent: a `## Worker Self-Check` governance section consumed by `drone.md` and `changeling.md` once shipped WITHOUT a `tests/policy/safety-*.json` consumer-assertion fixture; review caught the missing-fixture gap post-hoc and the fixture was added as a follow-up.)

How to author the fixture itself — what a pin can honestly claim, which clause to pin, and how to prove it bites — is governed by the pin-authoring contract in `tests/policy/README.md`.

## P4 — Extraction-home policy

Pure deterministic mechanism goes to a shared committed SCRIPT, called directly via Bash. Judgment-bearing procedure that is reusable or ad-hoc-invokable goes to a SKILL. Single-use judgment stays in the agent body as narrative. (Rooted in Anthropic guidance that deterministic work belongs in executed scripts and reusable procedure belongs in skills — see Sources.)

## P5 — Bash cannot invoke a Skill

A shell script can only call another script, never a Skill — skills are invoked by an LLM agent via the Skill tool. Therefore any substrate that must be shared with a bash caller MUST be a script, not a skill. This is a forced home, not a preference.

## P6 — Scripts are execute-not-load

An agent or subagent body is loaded in FULL as the system prompt on every dispatch — eager, permanent prompt weight. A skill body loads only on activation (lazy). A script invoked via Bash is EXECUTED, never read into context. Moving a dense contract out of agent prose into a script is therefore a runtime-token win, not just a tidiness win. (Rooted in Anthropic progressive-disclosure guidance — see Sources.)

## P7 — Don't hollow the agent (illegibility guard)

Over-extracting an agent's CORE judgment into opaque script or skill calls is its own failure mode. Extract the shared CRITERIA, but keep the per-instance decision in the agent so it still reads as a coherent judgment narrative.

## P8 — When a skill is warranted

Extract prose into a skill when BOTH hold: (1) it is judgment prose legitimately too complex to reduce to a deterministic script — an LLM must run it — AND (2) it has standalone or generic value, reusable by another agent OR ad-hoc user-invokable. (Rooted in Anthropic's create-a-skill trigger — see Sources.)

## P9 — Don't over-generalize a shared script

If forcing one script to serve two callers requires heavy parameterization or a leaky abstraction, keep the machines separate and extract only the genuinely-shared kernel — for example, an exit-precedence resolver shared by two otherwise-divergent review loops, not the whole loop.

## P10 — Procedure → skill; fact/binding-policy → governance

The deciding axis between a lazy skill and an always-loaded governance doc is procedure-vs-fact. Executable, procedural how-to that runs at a decision point goes to a skill (progressive disclosure, loaded on demand). Facts, definitions, invariants, glossary, and always-binding policy or safety posture go to governance docs (eager-loaded BY NECESSITY — a binding posture demoted to a lazy skill is silently OFF whenever it is not invoked). Do not put executable procedure in eager governance; do not demote always-binding policy to a lazy skill. This applies only when a skill genuinely makes sense (see P8). (Rooted in Anthropic's "procedure rather than a fact" guidance — see Sources.)

## P11 — Judgment is not extractable mechanism (P7 corollary)

Mechanism — deterministic, reproducible, contract-stable — is extractable to scripts (P5/P6 win). Judgment — holistic, context-dependent, operating on a lossy source — is not: encoding it as a heuristic produces a brittle approximation that satisfies a consumer's SCHEMA but not its SEMANTICS, and accretes endless edge-case patches. Two warning signs: the source is lossy for the question being asked (the data does not actually contain the answer), or the extraction keeps accumulating new special-cases as reviewers find edges. Extract to a script ONLY the lossless, factual skeleton; keep interpretation in the agent (P7). (Precedent: `ledger-reconstruct.sh` once tried to reconstruct fix-ledger judgments — "what is a prior fix", review-iteration grouping, oscillation-as-cycling — deterministically from `git log`, but git commits ≠ review iterations, a lossy source. It satisfied `detect-remediation-signals`' schema but not its semantics, and drew ~7 recurring Codex findings. The structural fix was to stop encoding the judgment and de-scope the script to the genuinely-deterministic skeleton: machine-channel path parsing, JSON escaping, fail-closed I/O.)

## P12 — Reference skills by intent, not by name

Narrative prose invokes a skill by what it accomplishes, not by its name. ~~"when X, call `hivemind:zoom-out`"~~ → "when X, zoom out to understand the broader picture." A name in narrative is decoration: it survives no rename and adds no reasoning. The discriminator is the **rename test** — if renaming the skill would BREAK this reference, the name is load-bearing and stays; if renaming would leave the sentence true, the name is decoration and is replaced by intent. Carve-out (name REQUIRED, not narrative): dispatch registries, the agent's skill list, frontmatter, and invocation contracts — there the exact name IS the API the Skill tool dispatches on. (Shares a decoupling root with P13/P14; cf. ADR-0006 intent-based-governance.)

## P13 — Respect the ADR; don't cite it as justification

Instructional prose is written to be CORRECT under its governing ADR, not to quote the ADR as its reason. ~~"According to ADR-XYZ, do X"~~ → prose that simply does X correctly, the ADR governing silently. The discriminator: *is this prose telling someone what to DO, or recording why the contract IS what it is?* A DO step carries no citation; the reader executes, not audits genealogy. This **refines P2** — the WHY and ADR traceability still belong WITH the mechanism, in contract headers, design-record blocks, and commit trailers, where a maintainer reading the contract wants the lineage. The anti-pattern is only the in-line citation at the point of action. (Shares a decoupling root with P12/P14.)

## P14 — Name no concrete consumer in reusable-skill prose

A reusable skill names no single calling bioform as an incidental actor. ~~"The overlord resolves and passes these"~~ → "The caller resolves and passes these." Naming one consumer couples a reusable skill to one caller and violates its generic value (P8). The discriminator: *could a different caller satisfy this role unchanged?* Yes → genericize to "the caller"/"the consumer." No, because a hard capability constraint binds it (e.g. the review loop must run in a Monitor-hosting main session per ADR-0005) → keep it, but frame it as the REQUIREMENT (the capability the caller must have), not as the bare bioform name. Out of scope: governance consumer-assertion sections (P3) — naming consumers THERE is the coupling contract a fixture enforces, not a leak. (Shares a decoupling root with P12/P13.)

## P15 — Test-mode is a flag, not a presence

A script seam that swaps a live side-effect (network, `gh`, or filesystem mutation) for an offline test fixture gates on an explicit dedicated test-mode flag (e.g. `*_TEST_MODE=1`), NEVER on the mere PRESENCE of a fixture-path env var. Presence-activation means a single leaked env var in a CI or dev shell silently runs the whole loop offline against production intent — a benign-looking variable becomes a live/offline switch. Sibling seams move together: a one-sided hardening is worse than the uniform status quo, because it makes the convention look reliable where it is not. (Precedent: the offline-capture seams in `reply-resolve.sh` and `fetch-normalize.sh` activated on env-var presence alone — flagged twice in review as a cross-cutting convention defect, not a one-file bug.) Distinct from ADR-0019, which governs hostile cross-boundary CONTENT; this governs benign test/prod mode SELECTION — operator misconfiguration, not adversarial input.

## P16 — Concurrency safety is structural, not check-then-act

Concurrency safety is achieved by REMOVING the shared mutable resource — per-id namespacing so each writer owns a disjoint path — not by guarding one shared resource with a check-then-act liveness read. A check-then-act read across a time-of-check/time-of-use window is a non-reservation and is unsafe by default: two writers can both pass the check and both proceed. When a single shared artifact is genuinely unavoidable, ownership is explicit (RUN-OWNERSHIP-01) and writes are serialized by a lock, never by a prior read. (Precedent: the brood concurrency line cost ADR-0019 eleven amendments and ADR-0017 ten, clustered on TOCTOU; the residual singleton-manifest race was finally closed STRUCTURALLY by per-brood-id namespacing in ADR-0021, not by another guard. The remaining same-run ledger-write race is out of envelope by construction: a run ledger is owned and mutated by exactly one instance (RUN-OWNERSHIP-01), so there is no sanctioned second writer to serialize.) Distinct from ADR-0021 (a brood-scoped instance) and ADR-0019 (hostile content): this elevates the generalizable rule so the next concurrent-writer feature inherits it without re-deriving the lesson through its own multi-amendment ADR.

## P17 — Genericness is CI-guarded, not eyeballed

The reusable/project-coupled boundary in plugin prose is load-bearing, so a mechanizable genericness rule MUST be enforced by a CI guard, not left to reviewer vigilance. Project-specific tokens in generic governance/agent prose, and the P12–P14 decoupling violations (skill-by-name, ADR-as-justification, named-consumer leak), are pattern-detectable and therefore get a `policy_check` guard; an un-guarded mechanizable rule is decoration. This is **P3 applied to genericness** — "a load-bearing contract is decoration until a CI fixture asserts it" — extended from script/governance triples to the decoupling rules. Manual remediation of a leak without a guard only resets the clock; the leak class returns with the next skill. (Precedent: a project-token leak survived three review passes and a green gate, caught only by human review; the leak class recurs across genericness findings.) The non-mechanizable residue — the judgment discriminators in P12–P14, like the rename test — stays in human review by design; P17 governs only the pattern-detectable subset.

## P18 — Fail-closed shell is the floor

Every NEW or CHANGED committed `*.sh` under the plugin MUST open with `set -euo pipefail` (or a documented, justified exception) as a non-negotiable hygiene floor, and existing scripts are brought to the floor as they are next touched. This is a prescriptive rule, not a claim about the current tree — today only a fraction of plugin scripts carry the floor, and the gap is closed incrementally plus tracked as a retrofit, never asserted as already-true. Default bash is fail-open: an unset variable expands to empty, a mid-pipeline failure is swallowed, execution marches past a failed command — so a broken script reports success while doing the wrong thing. The floor is enforced by convention and ideally a lightweight lint, not by per-author taste; net-new-script-heavy initiatives will otherwise propagate whatever neighbor they copy. Distinct from ADR-0019 (trust-boundary content handling) and ADR-0020 (single-responsibility libraries): this is a universal shell-EXECUTION hygiene floor for every script regardless of boundary, with the retrofit of currently-non-compliant scripts tracked as a separate follow-up.

## P19 — Doctrine anchors on durable records, not tracker IDs

A principle outlives the tickets that motivated it, so it cites only durable anchors — ADRs, named invariants (e.g. `RUN-OWNERSHIP-01`), and the principles themselves — never ephemeral issue or PR numbers. A bare `#NNN` couples permanent doctrine to a mutable tracker: the ticket closes, is renumbered in meaning, or is superseded, and the principle silently rots — closing one deferred issue once instantly staled an earlier principle's "open instance" footnote. When a precedent lives only in a ticket, that is the signal to describe the pattern in prose or promote it into an ADR and cite that, not to cite the ticket. (Shares a decoupling root with P12–P14: name nothing volatile that durable prose will outlive. Self-applying — this principle, like the rest of this revision, names no issue.)

## P20 — Doctrine homes: decision → ADR, reusable rule → principle, runtime policy → governance

Three doctrine homes sit at three altitudes; a given claim lives in exactly one. An **ADR** records a dated, hard-to-reverse DECISION made between real alternatives — it is immutable (superseded, never edited) and answers "why we chose X over Y, then." Its gate is three-fold: hard-to-reverse AND surprising-without-context AND a genuine trade-off; fail any one and it is not an ADR. An **engineering principle** is a timeless, reusable FACTORING RULE distilled across one or more decisions — it answers "how we build here, always," generalizes its ADRs, and cites them as precedent rather than restating the decision. A **governance doc** is runtime-loaded BINDING POLICY the agent executes or refuses at a decision point — it answers "what must happen now"; it may OPERATIONALIZE an ADR's decision, but the normative text has exactly one authoritative home (P1), so the ADR records while governance executes and the same rule is not normatively stated in both.

The smell of a blurred home: an ADR phrased as a standing rule that rejected no alternative (it is probably a principle); a principle that applies to exactly one situation (it is probably an ADR); or the same normative sentence appearing in both an ADR and a governance doc (a P1 single-source defect — keep the runtime statement in governance and leave the ADR a pointer to it, or vice versa, but not both). This is the meta-rule the other principles already follow implicitly when they tag an ADR as "a scoped instance" and elevate the generalizable rule (e.g. P16 vs ADR-0021); P20 makes the three-home boundary explicit so it stops being applied by unwritten judgment alone.

## P21 — SOLID, led by single responsibility

A script, skill, or agent does ONE job; when it accumulates responsibilities it is SPLIT, not grown. The operative test is single responsibility's classic form: if more than one KIND of change forces edits to the same unit, it has more than one responsibility and wants splitting. This generalizes ADR-0020, which operationalized the rule for engine logic (focused, unit-tested `_shared/` function libraries composed behind a thin entrypoint); P21 extends that same discipline to ALL plugin scripts, not just engine internals. The SOLID corollaries that earn their place in this codebase: **open/closed** — extend behavior by composing a NEW small unit, not by editing a god-script; and **dependency-inversion** — a skill or agent depends on a script's CONTRACT (its P2 header), never its internals, so the implementation can change behind a stable interface. Liskov-substitution and interface-segregation have weak purchase in a non-OO prose-and-shell codebase and are NOT force-fit — applying a principle where it earns no relevance is cargo-cult, the same illegibility failure P7/P11 warn against. Smell: a script you can only describe with an "and," or one whose line count keeps climbing as unrelated concerns accrete.

## P22 — DRY: one authoritative home per piece of knowledge

Every rule, fact, or contract is expressed ONCE, in one authoritative home; a second normative copy is a drift defect, not a convenience. Several existing principles are DRY applied to a specific surface — P1 (single-source contract) is DRY for specs and contracts, P19/P20 are DRY for doctrine homes — and P22 is the general rule they each instantiate. The critical caveat, which keeps DRY from colliding with P9 and P23: DRY is about a single source of KNOWLEDGE, not coincidental textual similarity. Two units that merely look alike today are not a duplication to fold — deduplicate shared knowledge, never shared coincidence (P9: extract only the genuinely-shared kernel). When in doubt, the first duplication is cheaper to carry than the wrong abstraction is to unwind.

## P23 — YAGNI: build for the requirement at hand

Do not add an abstraction, parameter, configuration knob, or layer of generality for a speculative future need — extract it only once a genuine THIRD use proves the shared need (the rule of three), tolerating the first and second occurrences as cheaper to carry than a premature abstraction is to unwind. Speculative generality is a present, certain cost (maintenance surface, prompt weight per P6, leak-prone abstractions per P9) paid for a future benefit that may never land. The growing multi-responsibility scripts are partly a YAGNI failure as much as a P21 one: a unit absorbing future-proofing nobody asked for. YAGNI is the counterweight to a naive reading of DRY — the single threshold is the rule of three, because the wrong early abstraction is harder to remove than a little duplication is to tolerate (pairs with P9 and P11: do not encode generality, or mechanism, that is not actually there yet).

## P24 — Scripts orchestrate, agents own their prose

A workflow script passes an agent three things: the task, the run's data, and short user-facing message templates. It never restates an agent's or a skill's own instructions. When a prompt seems to need a rule its target lacks, the rule goes into that agent definition or skill, not into the script. The reason is where each side can read. An agent reads its definition and its skills when it runs, but a running script cannot read files, so a rule copied into a script is a second copy that drifts from its home (P22) and grows the bundle toward the approval limit. Per P3, the guard is a test, not this paragraph: the per-script prose budget and the duplication check in `tools/build_workflows.mjs` fail the build when a script grows past its budget or a prompt sentence copies a sentence of any agent definition or skill. Raising a budget is a visible, reviewed change to that file, never a quiet edit to make the build pass.

## Sources

- https://code.claude.com/docs/en/skills — Claude Code "Extend Claude with skills": the create-a-skill trigger ("a section of CLAUDE.md has grown into a procedure rather than a fact"; "a skill's body loads only when it's used"). Roots for P4/P6/P8/P10.
- https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills — Agent Skills launch: deterministic reliability of code; progressive disclosure. Roots for P4/P6/P8/P10.
- https://agentskills.io/specification — Agent Skills spec: the `scripts/` directory is "executed, not loaded"; metadata / SKILL.md / resources disclosure levels. Roots for P4/P6/P8/P10.
- Robert C. Martin, "Design Principles and Design Patterns" / *Agile Software Development* — the SOLID principles, single-responsibility's "one reason to change" form. Root for P21.
- Andrew Hunt & David Thomas, *The Pragmatic Programmer* — "Don't Repeat Yourself": every piece of knowledge has a single, unambiguous, authoritative representation. Root for P22.
- Extreme Programming / "You Aren't Gonna Need It" (Jeffries, Beck) — implement things when you actually need them, never when you just foresee needing them. Root for P23.
