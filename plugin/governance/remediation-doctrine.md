# Remediation Doctrine

Shared vocabulary and policy for root-cause review remediation. Loaded by the `github-reviewer` and `local-reviewer` agents, the overlord, and the cerebrate so all four reason about review loops with one vocabulary. This doc is definitional and policy only: it carries no detection algorithm and no case studies. The detection mechanics live in the `hivemind:detect-remediation-signals` skill; few-shot exemplars ship in that skill's `references/`.

When any rule uses a term defined here, this definition is binding.

## Root-Cluster

A set of N-or-more review findings that share a root cause, surface, or fix-framing. A root-cluster is the signal that per-finding patching must STOP and the loop must zoom out: the findings are symptoms of one defect, so patching them individually is a treadmill that spawns the next symptom on the next pass.

When a reviewer detects a root-cluster it returns the `root-cluster-suspected` exit_reason, carrying the cluster: the shared files/surface, the N thread URLs or finding IDs, the hypothesized root cause, and the same-framing rationale. The overlord consumes this signal to route to a structural fix (via cerebrate) instead of dispatching N narrow patches.

The cluster threshold N is tuned by severity per **Severity as Sensitivity Modifier**.

## Same-Framing Test

Before committing to any one-off fix, ask: would the next reviewer comment be this same shape with a different byte, field, or path? If yes, the root is unfixed — escalate to a structural fix rather than patch the instance.

The same-framing test is applied per-candidate during classification. A "yes" answer is a primary input to **Root-Cluster** detection: it converts a lone finding into evidence that a class, not an instance, is at fault.

## Closed-by-Construction Preference

When choosing a structural fix, prefer one that dissolves the whole class by construction over one that handles the observed instance. A closed-by-construction fix makes the next same-framing finding impossible rather than merely unobserved. Ordered preferences:

- positive allowlist over reject-enumeration (blacklist)
- a real parser over hand-parsing
- ground-truth derivation over validating untrusted input
- floor-at-input plus encode-at-output over per-context charset handling
- validate-where-bytes-are-intact over validate-after-a-lossy-round-trip

### Closed-by-Construction Acceptance Test

A named gate applied as PROSE JUDGMENT by both reviewers AND the overlord before accepting any candidate "structural" remediation as cluster-closing. It is the discriminator between a fix that dissolves the class and one that merely extends the handled set under a structural-looking name.

The gate question, asked of every proposed structural fix:

> What class of future finding does this make impossible, and why?

Decision rule on the answer:

- If the answer ENUMERATES handled cases — "we now also check X", "we added the missing attribute", "the predicate now covers this case too" — the fix is NOT closed-by-construction. It is **complete-the-known-set**, and it is still whack-a-mole: the next un-enumerated attribute is the next finding. Keep the cluster OPEN and escalate; do not accept the fix as cluster-closing.
- If the answer NAMES AN ELIMINATED CLASS by changing the KEY, the primitive, or the approach — "title is no longer the key, so title-collision findings cannot exist", "the value is now derived from ground truth rather than validated, so malformed-input findings cannot exist" — the fix IS closed-by-construction. Accept it as cluster-closing.

The two training shapes, generically:

- **Closed.** A fix that was reaching for the wrong primitive (e.g. a fuzzy/approximate lookup used as an exactness oracle) is replaced by a ground-truth-enumerating primitive that cannot produce the failure mode. The class is named and gone.
- **Not closed.** A predicate that gains another conjunct or another checked attribute per finding — the shape stays identical, only the byte/field/path differs each pass. This is the **Same-Framing Test** answering "yes" against a fix dressed as structural.

This gate refines the ordered preferences above: a preference is only satisfied when the chosen fix passes this test. A reject-enumeration that grows one entry per finding fails it; a positive allowlist or a real parser that makes the malformed class unrepresentable passes it.

## Bounded-Impact Gating

Assess the actual blast radius of a finding independent of the reviewer's severity badge: is it informational-only? does it touch only already-validated enum/charset surfaces? does the attacker already control the input? The assessed impact — not the badge — informs the fix-now vs defer vs accept decision. A badge is an input to this assessment, never a substitute for it.

## Defer-with-Scope

A finding is never silently dropped. Every actionable finding left unfixed in the current loop MUST carry full root-cause scope, its linked threads, and a bounded-impact note (per **Bounded-Impact Gating**). That obligation is common to BOTH permitted destinations; what differs is WHERE the record lives.

- **Tracked issue.** File or defer to a tracked issue when the finding is WORK someone should do: it is newly introduced by the change under review, or its remediation is genuinely wanted but out of scope for this loop, or it belongs to the same family as an already-tracked structural change. Default to an EXISTING tracked home; create a NEW issue only when no existing home fits.
- **Recorded residual.** Record the decision in the repository per **Recorded Residual** below.

The discriminating test: an issue asserts that SOMEONE WILL ACT; a recorded residual asserts that WE DECIDED, AND HERE IS WHY. Filing a decision as an issue is a category error — it inflates the backlog and buries the reasoning away from the code it concerns.

Either destination, carrying full scope, is the only permitted way to leave an actionable finding unfixed in the current loop. A record that omits scope, linkage, or impact rationale is a silent drop and is forbidden. The originating thread is then replied-to and resolved citing the tracking issue or the recorded residual.

### Recorded Residual

When — and only when — the behavior is INHERITED rather than introduced by the change under review, AND its impact is BOUNDED and understood, AND the obvious remediation was CONSIDERED AND REJECTED ON THE MERITS, the finding is left unfixed as a recorded residual: write the reasoning into the repository adjacent to the code it concerns — the project's durable design record (an architecture-decision record wherever the project keeps them), or a code comment where a full record would be disproportionate — carrying the root cause, the bounded impact, and why the obvious remediation was rejected, and open NO tracker entry.

All three conditions are CONJUNCTIVE; any one alone is not enough. "Inherited" on its own is a universal escape hatch that launders real work into a silent drop.

A recorded residual is NOT a silent drop. The scope requirement is IDENTICAL to a deferral — full root-cause scope, linked threads, bounded-impact note — only the destination differs. Recording is PREFERRED over filing when the finding is a decision rather than work.

Name the destination by ROLE, never by a presumed path: wherever this project keeps its durable design records. Where the project keeps none, or where a full record would be disproportionate to the finding, a code comment adjacent to the behavior is the FLOOR. Recording nothing is never a permitted destination.

Recording is NOT one-way. A recorded residual whose reasoning is later invalidated — the impact turns out to be unbounded, or the behavior turns out to have been introduced by the change after all — is PROMOTED to a filed issue carrying the same scope.

## Stop-and-Merge

Stop the loop and advise merge when ALL of the following hold:

- zero unresolved actionable threads remain
- remaining findings are a bounded tail on a heavily-hardened surface
- the structural home for that tail is a tracked issue or a recorded residual (per **Defer-with-Scope**)
- every push spawns only a fresh bounded tail, never a new defect class

The stop signal is NOT round count. Chasing zero-findings-per-push on a complex security surface is itself the anti-pattern. Agents never merge — humans merge. The loop surfaces this as the `merge_advised` advisory terminal carrying `advisory_reason` and `recommendation_text`.

## Severity as Sensitivity Modifier

Severity does NOT by itself trigger zoom-out. A lone high-severity finding is patched or escalated as usual; a review that finds a real high-severity issue is the process WORKING, not a signal to cluster. There is NO standalone P0/P1 zoom-out gate: a cross-cutting single fix already routes through planner-escalation, and whack-a-mole is detected by recurrence, not by severity.

Severity only TUNES the **Root-Cluster** threshold N:

- **N=2** when a high-severity finding lands on a just-touched or same-framing surface
- **N=3** by default otherwise

The "just-touched / same-framing surface" qualifier here is a WITHIN-PASS modifier: it tunes N for the single classification pass in front of the reviewer. It is orthogonal to, and must not be conflated with, the ACROSS-ITERATION axis defined in **Cross-Iteration Same-Surface Recurrence** below.

## Cross-Iteration Same-Surface Recurrence

A second root-cluster signal, ORTHOGONAL to the within-pass fix-framing + line-overlap cluster key. It fires INDEPENDENT of framing match and INDEPENDENT of line-range overlap: the signal is that one surface keeps absorbing findings across the loop, not that two findings rhyme within a pass. The recurrence rate on a young surface IS itself the cluster signal.

This is a NEW CLUSTERING AXIS THAT TUNES N — the same shape as **Severity as Sensitivity Modifier**, which tunes N by severity. It is NOT a standalone trigger; it sets the threshold at which **Root-Cluster** trips for a qualifying surface. Two gates must both hold:

- **Gate A — recurrence.** One surface (the same file or component) absorbs findings across **two or more DISTINCT loop iterations**, even when the line ranges are disjoint AND the fix-framings differ. Within-pass framing/line matching is NOT required for this gate; cross-iteration re-emission on the same surface is the whole signal.
- **Gate B — youth (HARD REQUIREMENT, AND'd with Gate A).** The surface was INTRODUCED or HEAVILY MODIFIED in THIS SAME PR or initiative. A young surface that keeps emitting findings is a design smell: code just written should not need repeated reviewer correction. Mature or legacy surfaces NEVER trip cross-iteration recurrence — they route to the existing **Stop-and-Merge** bounded-tail → merge-advisory path instead.

Threshold N for this axis:

- **N=2** when the recurring findings on the young surface touch a SHARED data-access / query / parse / serialization PRIMITIVE — a semantic/primitive clustering axis: the same underlying primitive is being patched at the edges across iterations.
- **N=3** otherwise.

Distinction from the within-pass axis (do not conflate): the "just-touched / same-framing surface" qualifier in **Severity as Sensitivity Modifier** is a WITHIN-PASS modifier scoped to a single classification pass. THIS axis is ACROSS-ITERATION — it spans the loop's distinct iterations — and is additive to and distinct from the within-pass modifier. A surface can be quiet within every individual pass and still trip this axis by re-emitting across iterations.

Multiple roots per surface: the recurrence counter PERSISTS across structural fixes. Closing root #1 with an accepted structural fix does NOT reset the counter. A surface that has already yielded one root is held to a LOWER threshold for the next — having needed a structural fix once is evidence the surface is structurally hot, so the next recurrence trips sooner.

## Bounded-Tail vs Recurring-Class Disambiguation

The **Stop-and-Merge** section reserves "every push spawns only a fresh bounded tail, never a new defect class" as a merge precondition. That bounded-tail clause now applies ONLY to MATURE surfaces. The disambiguation:

- **Young surface + recurring findings** (the surface was introduced or heavily modified in this PR/initiative): this is NOT a bounded tail. A young surface that keeps emitting findings is a design smell, so it escalates to a root-cause ZOOM-OUT (question the key/primitive per the **Closed-by-Construction Acceptance Test**), never to merge-advisory. This is the escalation path of **Cross-Iteration Same-Surface Recurrence**.
- **Mature / legacy surface + bounded tail**: this remains a merge-advisory candidate per **Stop-and-Merge**. A genuine mature-surface bounded tail — a hardened legacy surface whose remaining findings are a converging tail with a tracked structural home — must STILL reach `merge_advised`. The young-surface escalation rule does not gate it.

Regression guard: do not let the young-surface escalation swallow the mature-surface merge path. The two are disjoint by Gate B of **Cross-Iteration Same-Surface Recurrence** — youth is the discriminator. A mature surface failing Gate B routes to merge-advisory exactly as before this section existed.

## Post-Fix Young-Tail Reroute Synthesis

A reviewer's POST-fix advisory step reads only the detector's `merge_advisory` / `diminishing_returns` blocks and discards the detector structure. When **Bounded-Tail vs Recurring-Class Disambiguation** reroutes that advisory because the recurring surface is YOUNG, the cluster verdict's payload is NOT in hand — the step never read the `cluster` block. This section is the SINGLE SOURCE for the obligation that closes that gap and for the role-based shape of the payload the reroute must synthesize. It does not duplicate the disambiguation rule (which decides WHETHER to reroute) or the **Closed-by-Construction Acceptance Test** (which judges whether the tail's tracked fix closes the class); it specifies WHAT a young-tail reroute must carry and the prior obligation that makes the reroute decidable. Both sections are referenced, not restated.

### Gate-B-producing obligation (the overlay must judge youth)

The young-vs-mature reroute discriminator is the Gate-B youth call of **Cross-Iteration Same-Surface Recurrence**. That call is NOT in the deterministic skeleton and NOT in the detector's `merge_advisory` / `diminishing_returns` output. Therefore the pre-fix enrichment overlay each reviewer applies before its detector call (per **Skeleton-Enrichment Judgment Criteria** for the reconstructing reviewer, or directly over the persisted fix-ledger for the stateful reviewer) MUST produce, as agent prose, the Gate-B judgment the POST-fix step depends on:

- **surface YOUTH** — whether each recurring surface was INTRODUCED or HEAVILY MODIFIED in this PR/initiative (the young/mature CALL is judgment, not a script output)
- **PRIMITIVE-SHARING** — whether the recurring findings patch the edges of one shared data-access / query / parse / serialization primitive

INVARIANT: a POST-fix step that may reroute on youth MUST have a youth call available from the enrichment overlay produced before its detector invocation. A reroute gated on a youth judgment the overlay never produced is a contract violation. The reviewer carries the young-surface recurrence rationale (which iterations re-emitted, why the surface is young, the shared primitive) in the detector's existing `same_framing_rationale` — there is NO new field — so it survives into the POST-fix step.

### Role-based reroute payload

When a POST-fix step reroutes a young recurring surface, it returns `root-cluster-suspected` and MUST synthesize the same payload the pre-fix cluster path carries. The payload is specified here BY ROLE; each reviewer maps these roles onto its own Output-Contract field names and sources each role its own way (the stateless reviewer reconstructs from git ground truth + the fresh post-fix fetch; the stateful reviewer reads its persisted fix-ledger). Roles:

- **surface files** — the young recurring surface file(s) from the enrichment overlay
- **finding refs** — the unresolved thread-URLs or finding-IDs on that surface (sourced from each reviewer's own current-state set)
- **shared root** — the hypothesized root cause / root class shared across the recurring findings
- **same-framing rationale** — the young-surface recurrence rationale carried in the enrichment overlay (which iterations re-emitted, why the surface is young, the shared primitive)
- **member count** — the recurring-finding count

### Invariants

- A young-tail reroute MUST NOT return `root-cluster-suspected` with an empty payload. Every role above must be populated from the reviewer's own state.
- Youth is the discriminator. A MATURE / legacy surface with a bounded tail and a tracked structural home stays on the existing **Stop-and-Merge** merge-advisory (or advisory early-exit) path, unchanged. The young-tail reroute MUST NOT swallow that mature path.
- A reroute introduces NO new `exit_reason` and NO new payload field — it reuses `root-cluster-suspected` and the existing cluster payload roles.

The four consumers of this section, per the governance-consumer convention, are: `github-reviewer` step 5 (pre-fix overlay producing the Gate-B youth judgment), `github-reviewer` step 9 (POST-fix young-tail reroute + synthesis), `local-reviewer` step 6 (pre-fix overlay producing the Gate-B youth judgment), and `local-reviewer` step 9 (POST-fix young-tail reroute + synthesis). This section is the single source of the obligation and the payload roles; those steps reference it by name and do not restate it.

## Verdict Consumption

The `hivemind:detect-remediation-signals` skill emits a verdict in which EVERY block
(`cluster`, `break_fix`, `diminishing_returns`, `merge_advisory`) is ALWAYS present — block
presence is unconditional and carries NO signal. The fired state lives ONLY in each block's
INNER field. All four consumers — `github-reviewer`, `local-reviewer`, the overlord, and the
cerebrate — MUST read the inner fired field (`break_fix.verdict == "break-fix"`,
`diminishing_returns.verdict == "diminishing-returns"`, `cluster.cluster_suspected == true`,
`merge_advisory.advise == true`) and MUST NEVER test block presence or block truthiness. The
authority for the exact block keys and inner field names is the
`hivemind:detect-remediation-signals` Output Contract.

## Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry

The per-surface recurrence counter that drives **Cross-Iteration Same-Surface Recurrence** is RECONSTRUCTED each loop from GitHub ground truth — there is NO persisted local recurrence file. GitHub IS the ledger, consistent with the stateless github-reviewer that reconstructs its fix-ledger from ground truth rather than persisting one. The COUNTING UNIT is the distinct structural-remediation EVENT (a single accepted structural fix — one remediation commit / resolved-thread-citing-a-structural-fix on that surface), NOT the (fix, finding) pair. A structural-remediation event counts as ONE non-closing structural fix when it is followed by ONE OR MORE fresh findings on that same surface; multiple later findings attributable to the SAME single fix event are deduplicated to that one event before the threshold is applied. N fresh comments on a surface after ONE structural fix is ONE non-closing structural fix, not N. The count for a surface is reconstructed as: the number of DISTINCT structural-remediation events on that surface that each have at least one subsequent same-surface finding after the event.

Forced zoom-out after the second non-closing structural fix: when a surface has absorbed TWO non-closing structural fixes — two accepted structural remediations each followed by a fresh finding on the same surface — the overlord forces an APPROACH-LEVEL zoom-out. That zoom-out questions the KEY or PRIMITIVE per the **Closed-by-Construction Acceptance Test**; it does NOT dispatch another conjunct-completion patch. A second structural fix that did not close the class is itself evidence the fixes are aiming at the wrong primitive.

The counter PERSISTS across structural fixes (per **Cross-Iteration Same-Surface Recurrence**): a surface that already yielded one root is held to the lower threshold for the next, so the second non-closing fix is the trip point, not the start of a fresh count.

Zoom-out routing asymmetry: the user-only architecture zoom-out skill carries `disable-model-invocation: true`, so the overlord cannot invoke it directly. The overlord therefore routes an architectural zoom-out THROUGH the cerebrate, via the existing `review_remediation_plan` / `review_remediation_plan_postpr` remediation state (the same path a `root-cluster-suspected` exit_reason already takes to reach a structural fix). This is the intended path, not a workaround: cerebrate is the architectural-reasoning surface the overlord delegates to, and the disable-model-invocation constraint on the user-only skill is the reason the route goes via the remediation state rather than a direct skill call.

### Proactive Zoom-Out Ledger Marker

When the overlord's reconstructed PROACTIVE same-surface recurrence counter trips — the second non-closing structural fix per **Forced zoom-out after the second non-closing structural fix** above, the EXISTING proactive trigger — the overlord records a NAMED overlord-judgment marker into the run ledger so the proactive origin of the resulting `root-cluster-suspected` transition is DISTINGUISHABLE from a reviewer-RETURNED `root-cluster-suspected`. Both origins reach the SAME remediation state (`review_remediation_plan` / `review_remediation_plan_postpr`) via the SAME `root-cluster-suspected` exit_reason described in the asymmetry paragraph above; without this marker the two are indistinguishable in the ledger.

The marker is a single key in the transition's `event.outputs` object. This subsection is the SINGLE SOURCE for its name and semantics; `${CLAUDE_PLUGIN_ROOT}/agents/overlord.md` and `${CLAUDE_PLUGIN_ROOT}/references/run-ledger-schema.md` reference it BY NAME and never restate the mechanics.

- Key: `recurrence_origin`.
- Value `"proactive"` — the zoom-out was overlord-proactively-derived (the reconstructed proactive recurrence counter tripped).
- A reviewer-RETURNED cluster OMITS the key (or may carry the explicit value `"reviewer"`).
- Absence semantics: an ABSENT `recurrence_origin` key ⇒ reviewer-returned / non-proactive. Consumers MUST treat absent as non-proactive and MUST NOT infer proactive origin from anything other than an explicit `"proactive"` value.

This is RECORDED JUDGMENT, not new determinism. The judgment — whether the surface has absorbed two non-closing structural fixes — stays judgment per ADR-0025; the marker only makes the judgment's ORIGIN observable after the fact. It is recorded via the NORMAL `hivemind:record-state-result` `outputs` path on the already-wired `root-cluster-suspected` transition. Explicitly: it introduces NO new workflow state, NO workflow-graph change, and is NOT routed through `hivemind:mark-intent-fallback`. `mark-intent-fallback`'s sanctioned-write pattern — a judgment-origin event made observable in the ledger — is cited here as ANALOGY ONLY; its bypass engine is NOT reused, and `recurrence_origin` rides the standard `outputs` write, not any fallback path.

Producer-state-AGNOSTIC: the marker rides whichever producer-state result carries the `root-cluster-suspected` exit_reason — `github_review_loop`, `github_reviewer_fix`, or the post-PR mirror that targets `review_remediation_plan_postpr` — and is NOT pinned to one state. The marker lives STRICTLY in `event.outputs` and MUST NOT collide with `plan_steps` or any `plan.*` field; it is an origin annotation, not plan content.

## Skeleton-Enrichment Judgment Criteria

Applies whenever a `github-reviewer` step reconstructs an ephemeral fix-ledger via
`ledger-reconstruct.sh` and then invokes `hivemind:detect-remediation-signals`. Both
qualifying steps — pre-fix reconstruction (step 5) and post-fix reconstruction (step 9) —
apply these criteria. They are defined here once; neither step restates them.

### (a) What the reconstructed skeleton provides — deterministic facts only

The skeleton emits exactly the facts mechanically derivable from ground truth:

- per-finding qualifying-remediation fix surface: `file`, `line_start`, `line_end`,
  `fix_commit`, and `status` (`fixed` or `open`) derived from the thread/finding resolved state
- thread resolved state (folded from `fetch-normalize.sh` output)

The skeleton DOES NOT emit: a `cycling` or `regressed` label, iteration grouping, a
`fix_framing` value (always `null`), or a `root_class`. These require judgment a deterministic
script cannot supply reliably.

### (b) What the agent MUST judge before invoking the detector

The `hivemind:detect-remediation-signals` skill READS `cycling`/`regressed` status,
iteration grouping, `fix_framing`, and `root_class` from the ledger — it does not compute
them. The agent must supply this interpretation overlay ON TOP of the skeleton before the
detector call:

- **Cycling / oscillation interpretation.** A re-touched surface — the same `file:line` range
  appearing across two or more qualifying-remediation commits, which is derivable from the
  skeleton facts — is not automatically a regression. The agent judges whether the re-touch is
  genuine mutation-decay (`status: cycling` or `regressed`) or ordinary forward iteration.
  Set `cycling` / `regressed` only on a judged genuine re-break.

- **Iteration / cycle grouping.** Git commits are not review iterations. Where N-2 recurrence
  detection is relevant, the agent judges iteration boundaries rather than equating commits
  to iterations. The skeleton's placeholder grouping is a starting point, not a binding
  boundary.

- **`fix_framing`.** The detector's PRIMARY cluster key is `null` in every skeleton finding
  (null-inert: two null-framing findings never cluster on the primary axis). The agent assigns
  a non-null `fix_framing` where it can holistically judge a shared fix shape/intent from
  commit and thread prose. When no reliable framing can be inferred, leave `null`; the
  detector falls back to the secondary `file:line` key.

- **`root_class`.** Assigned by agent judgment when the agent identifies a shared root cause
  across clustered findings.

### (c) Binding rule — single-source

The skeleton is a lossless set of deterministic facts. The interpretation overlay (cycling
label, iteration grouping, `fix_framing`, `root_class`) is agent judgment supplied on top
before the detector call. This section is the single source of these criteria; neither
github-reviewer step 5 nor step 9 restates them — both reference this section by name.

## Relationship to Existing Detectors

Two review-loop detectors predate this doctrine and remain its companions; their policy meaning is unified here so both review loops share one vocabulary.

- **Mutation Decay** (break-fix-break cycle): fixing one finding reintroduces a previously fixed finding. Policy: a MANDATORY stop. Defined in CONTEXT.md.
- **Creep Stagnation** (diminishing-returns exit): the loop spreads across iterations but gains no new ground. Policy: an ADVISORY early exit — the reviewer recommends stopping and returns the decision to the overlord/Overmind. Defined in CONTEXT.md.

The operational detail of all three signals — Mutation Decay, Creep Stagnation, and Root-Cluster — lives in `hivemind:detect-remediation-signals`. This doctrine holds only their policy meaning. Mutation Decay and Stop-and-Merge are both stop conditions but differ in cause: Mutation Decay stops on instability (a fix that breaks a prior fix); Stop-and-Merge stops on a hardened surface with a tracked structural home and a bounded tail.
