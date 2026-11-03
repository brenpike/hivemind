# Remediation Doctrine

Terms and policy for root-cause review remediation. Detection mechanics live in `hivemind:detect-remediation-signals`. A term defined here binds every rule that uses it.

## Root-Cluster

N or more review findings that share a root cause, surface, or fix-framing. It stops per-finding patching; the loop zooms out.

A reviewer that detects one returns the `root-cluster-suspected` exit_reason with the cluster: the shared files or surface, the N thread URLs or finding IDs, the hypothesized root cause, and the same-framing rationale. The overlord routes it to a structural fix via cerebrate.

Severity tunes N per **Severity as Sensitivity Modifier**.

## Same-Framing Test

Before any one-off fix, ask: would the next review comment be this same shape with a different byte, field, or path? If yes, the root is unfixed: escalate to a structural fix. Apply it per candidate during classification; a yes is **Root-Cluster** evidence.

## First-Finding Triage

At the first non-trivial finding, before any fix is planned or applied, answer four questions. Triage keys on the first finding, never on a finding count.

1. **Introduced or inherited.** Either way, a found root cause is fixed at its source in the PR that found it, even outside the reviewed diff. Origin never licenses a deferral or a residual.
2. **Root class and owning layer.** The fix lands in the layer that owns the root class, not at the symptom.
3. **Remove before harden.** Prefer removing or retiring the surface over hardening it.
4. **Threat model.** When a recorded threat model excludes the assumed attacker or failure, reject the finding at the source by citing the record; do not harden. When none is recorded, recording one is a review call, asked or taken per `${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md` (Review Calls), when a reviewer raises it, and a call for the user otherwise.

The answers feed **Closed-by-Construction Preference** and **Surface-Growth Escalation**. A question 4 rejection is handled per **Recorded Decisions and Repeat Findings**.

## Closed-by-Construction Preference

Prefer a fix that makes the whole class impossible over one that handles the instance:

- positive allowlist over reject-enumeration
- a real parser over hand-parsing
- ground-truth derivation over validating untrusted input
- floor-at-input plus encode-at-output over per-context charset handling
- validate-where-bytes-are-intact over validate-after-a-lossy-round-trip

### Closed-by-Construction Acceptance Test

Before accepting a structural fix as cluster-closing, both reviewers and the overlord ask, by judgment:

> What class of future finding does this make impossible, and why?

- An answer that enumerates handled cases is **complete-the-known-set**, the **Same-Framing Test** answering yes. Keep the cluster open and escalate.
- An answer that names a class eliminated by changing the key, the primitive, or the approach is closed-by-construction: accept it.

A preference above holds only when the fix passes this test.

## Surface-Growth Escalation

A fix that adds more surface than it removes is not applied. Count, by judgment, the files, code paths, checks, state and lines it adds against those it removes. When it grows the surface, ask the user one architectural call instead: a one-line ask, options that include removing the surface and recording the threat model, and a recommendation, on the engine's existing user-question path.

## Bounded-Impact Gating

Judge a finding's actual blast radius: is it informational only, does it touch only already-validated enum or charset surfaces, does the attacker already control the input? For a finding that is not a found root cause, the assessed impact decides fix now, defer, or accept; the severity badge is an input, never a substitute. A found root cause is fixed per **First-Finding Triage**, whatever its impact.

## Defer-with-Scope

Applies only to a finding that is not a found root cause.

Every actionable finding left unfixed in the current loop MUST carry full root-cause scope, its linked threads, and a bounded-impact note per **Bounded-Impact Gating**, in one of two destinations:

- **Tracked issue.** For wanted work out of scope for this loop, or in the family of an already-tracked structural change. Prefer an existing tracked home; create one only when none fits.
- **Recorded residual.** Preferred when the finding is a decision rather than work, per **Recorded Residual** below.

Anything else, or a record missing any of these, is a forbidden silent drop. The originating thread is then replied-to and resolved citing the tracking issue or the recorded residual.

The actor that leaves a finding unfixed files the issue or writes the record before the loop terminates, and carries its location in its own record of the decision.

"Structural home" names a ROLE, not a destination type: the tail's reasoning has a durable home. The admissible destinations are the two defined above — Tracked issue and Recorded residual. A restatement must carry BOTH and cite this section; binding the role noun to a single destination type ("a tracked structural home") re-narrows the role and is the forbidden form.

### Recorded Residual

A found, fixable root cause, introduced or inherited, is never recorded in place of a fix. A residual is admissible only on one of two grounds:

- **Outside the threat model.** The assumed attacker or failure is outside the recorded threat model, per **Recorded Decisions and Repeat Findings**.
- **Unclosable on this engine.** No fix on this engine can close the class, and the user decided so.

Origin is not a ground. On either ground, leave the finding unfixed and write the reasoning next to the code it concerns: in the project's durable design records, named by role, never by a presumed path, or, where it keeps none or a full record is disproportionate, in a code comment. The record carries full root-cause scope, linked threads, a bounded-impact note, and the ground with its citation. Open no tracker entry.

A residual whose reasoning later fails (unbounded impact, an attacker or failure inside the threat model, or a fix on this engine that closes the class) is promoted to a filed issue with the same scope.

## Recorded Decisions and Repeat Findings

A user's rejection of a finding and a threat model are decisions, each recorded at its source in the project's durable design records, named by role, on the branch or on trunk. The key is the recorded decision, never a finding id or a question.

A later finding that contests a recorded decision is a repeat: the reviewer rejects it by citing the record, lists it for the user before the PR, does not fix it, and never asks again. A finding that shows a failure the record does not cover is new and gets **First-Finding Triage**.

A user's rejection is recorded before the next review reads it: by the reviewer that asked, when the answer reaches it in the same run (the local reviewer in a delivery run, the GitHub reviewer in a PR watch), otherwise by the next plan as a plan step. A call the run took under `${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md` (Review Calls) is recorded the same way by the reviewer that asked, naming the run as the decider.

## Stop-and-Merge

Stop the loop and advise merge when ALL of the following hold:

- zero unresolved actionable threads remain
- remaining findings are a bounded tail on a heavily-hardened surface
- the tail has a structural home (per **Defer-with-Scope**)
- every push spawns only a fresh bounded tail, never a new defect class

The stop signal is NOT round count. Chasing zero-findings-per-push on a complex security surface is itself the anti-pattern. Agents never merge — humans merge. The loop surfaces this as the `merge_advised` advisory terminal; its payload shape is owned by the detector that produces it (`hivemind:detect-remediation-signals`).

## Severity as Sensitivity Modifier

Severity does NOT by itself trigger zoom-out or a cluster. Every non-trivial finding, whatever its severity, gets **First-Finding Triage** before any fix. A lone high-severity finding is then fixed or escalated per that triage; a review that finds a real high-severity issue is the process WORKING, not a signal to cluster. There is NO standalone P0/P1 zoom-out gate: a cross-cutting single fix already routes through planner-escalation, and whack-a-mole is detected by recurrence, not by severity.

Severity only TUNES the **Root-Cluster** threshold N:

- **N=2** when a high-severity finding lands on a just-touched or same-framing surface
- **N=3** by default otherwise

The "just-touched / same-framing surface" qualifier here is a WITHIN-PASS modifier: it tunes N for the single classification pass in front of the reviewer. It is orthogonal to, and must not be conflated with, the ACROSS-ITERATION axis defined in **Cross-Iteration Same-Surface Recurrence** below.

## Cross-Iteration Same-Surface Recurrence

A second root-cluster signal, ORTHOGONAL to the within-pass fix-framing + line-overlap cluster key. It fires INDEPENDENT of framing match and INDEPENDENT of line-range overlap: the signal is that one surface keeps absorbing findings across the loop, not that two findings rhyme within a pass. The recurrence rate on a young surface IS itself the cluster signal.

This is a NEW CLUSTERING AXIS THAT TUNES N — the same shape as **Severity as Sensitivity Modifier**, which tunes N by severity. It is NOT a standalone trigger; it sets the threshold at which **Root-Cluster** trips for a qualifying surface. Two gates must both hold:

- **Gate A — recurrence.** One surface (the same file or component) absorbs findings across **two DISTINCT loop iterations with a fix between them**, even when the line ranges are disjoint AND the fix-framings differ. Within-pass framing/line matching is NOT required for this gate; cross-iteration re-emission on the same surface is the whole signal.
- **Gate B — youth (HARD REQUIREMENT, AND'd with Gate A).** The surface was INTRODUCED or HEAVILY MODIFIED in THIS SAME PR or initiative. A young surface that keeps emitting findings is a design smell: code just written should not need repeated reviewer correction. Mature or legacy surfaces NEVER trip cross-iteration recurrence — they route to the existing **Stop-and-Merge** bounded-tail → merge-advisory path instead.

Threshold N for this axis is **N=2**: the first re-emission on a young surface after a fix on it trips the axis. This axis has no N=3 default. When the recurring findings touch a SHARED data-access / query / parse / serialization PRIMITIVE — the same underlying primitive patched at the edges across iterations — that sharing is part of the cluster's same-framing rationale, not a separate threshold.

Distinction from the within-pass axis (do not conflate): the "just-touched / same-framing surface" qualifier in **Severity as Sensitivity Modifier** is a WITHIN-PASS modifier scoped to a single classification pass. THIS axis is ACROSS-ITERATION — it spans the loop's distinct iterations — and is additive to and distinct from the within-pass modifier. A surface can be quiet within every individual pass and still trip this axis by re-emitting across iterations.

Multiple roots per surface: the recurrence counter PERSISTS across structural fixes. Closing the FIRST root with an accepted structural fix does NOT reset the counter: the next fresh finding on that surface is a re-emission after a fix and trips this axis. Having needed a structural fix once is evidence the surface is structurally hot.

## Bounded-Tail vs Recurring-Class Disambiguation

The **Stop-and-Merge** section reserves "every push spawns only a fresh bounded tail, never a new defect class" as a merge precondition. That bounded-tail clause applies ONLY to MATURE surfaces. The disambiguation:

- **Young surface + recurring findings** (the surface was introduced or heavily modified in this PR/initiative): this is NOT a bounded tail. A young surface that keeps emitting findings is a design smell, so it escalates to a root-cause ZOOM-OUT (question the key/primitive per the **Closed-by-Construction Acceptance Test**), never to merge-advisory. This is the escalation path of **Cross-Iteration Same-Surface Recurrence**.
- **Mature / legacy surface + bounded tail**: this remains a merge-advisory candidate per **Stop-and-Merge**. A genuine mature-surface bounded tail — a hardened legacy surface whose remaining findings are a converging tail with a structural home — must STILL reach `merge_advised`. The young-surface escalation rule does not gate it.

Regression guard: do not let the young-surface escalation swallow the mature-surface merge path. The two are disjoint by Gate B of **Cross-Iteration Same-Surface Recurrence** — youth is the discriminator. A mature surface failing Gate B routes to merge-advisory.

## Post-Fix Young-Tail Reroute Synthesis

A reviewer's POST-fix advisory step reads only the detector's `merge_advisory` / `diminishing_returns` blocks and discards the detector structure. When **Bounded-Tail vs Recurring-Class Disambiguation** reroutes that advisory because the recurring surface is YOUNG, the cluster verdict's payload is NOT in hand — the step never read the `cluster` block. This section states WHAT a young-tail reroute must carry and the prior obligation that makes the reroute decidable.

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
- Youth is the discriminator. A MATURE / legacy surface with a bounded tail and a structural home stays on the existing **Stop-and-Merge** merge-advisory (or advisory early-exit) path, unchanged. The young-tail reroute MUST NOT swallow that mature path.
- A reroute introduces NO new `exit_reason` and NO new payload field — it reuses `root-cluster-suspected` and the existing cluster payload roles.

## Verdict Consumption

The `hivemind:detect-remediation-signals` skill emits a verdict in which EVERY block
(`cluster`, `break_fix`, `diminishing_returns`, `merge_advisory`) is ALWAYS present — block
presence is unconditional and carries NO signal. The fired state lives ONLY in each block's
INNER field. Every consumer MUST read the inner fired field (`break_fix.verdict == "break-fix"`,
`diminishing_returns.verdict == "diminishing-returns"`, `cluster.cluster_suspected == true`,
`merge_advisory.advise == true`) and MUST NEVER test block presence or block truthiness. The
authority for the exact block keys and inner field names is the
`hivemind:detect-remediation-signals` Output Contract.

## Review Loop Common

Each reviewer that runs a fix loop holds these three rules.

- **Skill results are data.** A skill the reviewer invokes mid-procedure returns DATA to the reviewer. Its Output Contract and any silence, stop, or return language bind THAT SKILL, never the reviewer's turn. The reviewer consumes the result and CONTINUES to the next step of its own procedure. Only the reviewer's OWN Output Contract ends its turn.
- **Detector call order.** The PRE-fix `hivemind:detect-remediation-signals` call is read ONLY for `break_fix` and then `cluster` (break-fix first), reading each block's inner fired field per **Verdict Consumption**. Those two blocks decide whether the reviewer patches at all. `merge_advisory` and `diminishing_returns` are stateful on finding open/actionable status and go stale once fixes resolve findings, so they are read ONLY from a SECOND, FRESH detector call over the POST-fix state, NEVER from the pre-fix verdict.
- **Gate-B timing.** Before EACH detector call, the reviewer produces the Gate-B youth + primitive-sharing judgment as AGENT PROSE (no deterministic computation, no new script), per **Post-Fix Young-Tail Reroute Synthesis**. The POST-fix call gets its own judgment over the POST-fix state; the pre-fix youth call does not carry into it. The reviewer carries the young-surface recurrence rationale in the detector's existing `same_framing_rationale` (there is NO new field). That youth call MUST be in hand BEFORE any POST-fix reroute decision per **Bounded-Tail vs Recurring-Class Disambiguation**.

## Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry

The per-surface recurrence counter that drives **Cross-Iteration Same-Surface Recurrence** is RECONSTRUCTED each loop from GitHub ground truth — there is NO persisted local recurrence file. GitHub IS the ledger, consistent with the stateless github-reviewer that reconstructs its fix-ledger from ground truth rather than persisting one. The COUNTING UNIT is the distinct structural-remediation EVENT (a single accepted structural fix — one remediation commit / resolved-thread-citing-a-structural-fix on that surface), NOT the (fix, finding) pair. A structural-remediation event counts as ONE non-closing structural fix when it is followed by ONE OR MORE fresh findings on that same surface; multiple later findings attributable to the SAME single fix event are deduplicated to that one event before the threshold is applied. N fresh comments on a surface after ONE structural fix is ONE non-closing structural fix, not N. The count for a surface is reconstructed as: the number of DISTINCT structural-remediation events on that surface that each have at least one subsequent same-surface finding after the event.

**Forced zoom-out after the first non-closing structural fix.** When a surface has absorbed ONE non-closing structural fix — one accepted structural remediation followed by a fresh finding on the same surface — the overlord forces an APPROACH-LEVEL zoom-out. That zoom-out reruns **First-Finding Triage** at the approach level and questions the KEY or PRIMITIVE per the **Closed-by-Construction Acceptance Test**; it does NOT dispatch another conjunct-completion patch. A structural fix that did not close the class is itself evidence the fix is aiming at the wrong primitive. The script engine has no code trigger for this zoom-out. When the cerebrate plans a replan that carries a review block, it sees the branch's earlier remediation fixes in the commits its fresh facts list, and makes this zoom-out call by judgment.

The counter PERSISTS across structural fixes (per **Cross-Iteration Same-Surface Recurrence**): a surface that already yielded one root is held to the same trip point for the next, so the first non-closing fix after any accepted structural fix is the trip point, not the start of a fresh count.

Zoom-out routing asymmetry: the user-only architecture zoom-out skill carries `disable-model-invocation: true`, so the overlord cannot invoke it directly. The overlord therefore routes an architectural zoom-out THROUGH the cerebrate, via the existing `review_remediation_plan` / `review_remediation_plan_postpr` remediation state (the same path a `root-cluster-suspected` exit_reason already takes to reach a structural fix). This is the intended path, not a workaround: cerebrate is the architectural-reasoning surface the overlord delegates to, and the disable-model-invocation constraint on the user-only skill is the reason the route goes via the remediation state rather than a direct skill call.

### Proactive Zoom-Out Ledger Marker

When the overlord's reconstructed PROACTIVE same-surface recurrence counter trips — the first non-closing structural fix per **Forced zoom-out after the first non-closing structural fix** above, the EXISTING proactive trigger — the overlord records a NAMED overlord-judgment marker into the run ledger so the proactive origin of the resulting `root-cluster-suspected` transition is DISTINGUISHABLE from a reviewer-RETURNED `root-cluster-suspected`. Both origins reach the SAME remediation state (`review_remediation_plan` / `review_remediation_plan_postpr`) via the SAME `root-cluster-suspected` exit_reason described in the asymmetry paragraph above; without this marker the two are indistinguishable in the ledger.

The marker is a single key in the transition's `event.outputs` object.

- Key: `recurrence_origin`.
- Value `"proactive"` — the zoom-out was overlord-proactively-derived (the reconstructed proactive recurrence counter tripped).
- A reviewer-RETURNED cluster OMITS the key (or may carry the explicit value `"reviewer"`).
- Absence semantics: an ABSENT `recurrence_origin` key ⇒ reviewer-returned / non-proactive. Consumers MUST treat absent as non-proactive and MUST NOT infer proactive origin from anything other than an explicit `"proactive"` value.

This is RECORDED JUDGMENT, not new determinism. The judgment — whether the surface has absorbed one non-closing structural fix — stays judgment per ADR-0025; the marker only makes the judgment's ORIGIN observable after the fact. It is recorded via the NORMAL `hivemind:record-state-result` `outputs` path on the already-wired `root-cluster-suspected` transition. Explicitly: it introduces NO new workflow state, NO workflow-graph change, and is NOT routed through `hivemind:mark-intent-fallback`. `mark-intent-fallback`'s sanctioned-write pattern — a judgment-origin event made observable in the ledger — is cited here as ANALOGY ONLY; its bypass engine is NOT reused, and `recurrence_origin` rides the standard `outputs` write, not any fallback path.

Producer-state-AGNOSTIC: the marker rides whichever producer-state result carries the `root-cluster-suspected` exit_reason — `github_review_loop`, `github_reviewer_fix`, or the post-PR mirror that targets `review_remediation_plan_postpr` — and is NOT pinned to one state. The marker lives STRICTLY in `event.outputs` and MUST NOT collide with `plan_steps` or any `plan.*` field; it is an origin annotation, not plan content.

## Skeleton-Enrichment Judgment Criteria

Applies whenever a `github-reviewer` step reconstructs an ephemeral fix-ledger via
`ledger-reconstruct.sh` and then invokes `hivemind:detect-remediation-signals`. Both
qualifying steps — pre-fix reconstruction (step 5) and post-fix reconstruction (step 9) —
apply these criteria.

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
before the detector call.

## Relationship to Existing Detectors

- **Mutation Decay** (break-fix-break cycle): fixing one finding reintroduces a previously fixed finding. Policy: a MANDATORY stop.
- **Creep Stagnation** (diminishing-returns exit): the loop spreads across iterations but gains no new ground. Policy: an ADVISORY early exit — the reviewer recommends stopping and returns the decision to the overlord/Overmind.

The operational detail of all three signals — Mutation Decay, Creep Stagnation, and Root-Cluster — lives in `hivemind:detect-remediation-signals`. Mutation Decay and Stop-and-Merge are both stop conditions but differ in cause: Mutation Decay stops on instability (a fix that breaks a prior fix); Stop-and-Merge stops on a hardened surface with a structural home and a bounded tail.
