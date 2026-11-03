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

Stop the loop and advise merge only when all of these hold:

- no unresolved actionable thread remains
- the remaining findings are a bounded tail on a heavily hardened surface
- the tail has a structural home per **Defer-with-Scope**
- every push spawns only a fresh bounded tail, never a new defect class

Round count is never the stop signal; chasing zero findings per push on a complex security surface is the anti-pattern. Agents never merge; humans merge. The loop surfaces this as the `merge_advised` advisory terminal, whose payload shape `hivemind:detect-remediation-signals` owns.

## Severity as Sensitivity Modifier

Severity alone never triggers a zoom-out or a cluster, and there is no standalone P0/P1 zoom-out gate. Every non-trivial finding gets **First-Finding Triage** before any fix; a lone high-severity finding is then fixed or escalated per that triage. Whack-a-mole is detected by recurrence, not severity.

Severity only tunes the **Root-Cluster** threshold N:

- **N=2** when a high-severity finding lands on a just-touched or same-framing surface
- **N=3** otherwise

"Just-touched or same-framing surface" is a within-pass modifier: it tunes N for one classification pass. It is distinct from the across-iteration axis of **Cross-Iteration Same-Surface Recurrence**.

## Cross-Iteration Same-Surface Recurrence

A second root-cluster axis, across loop iterations, independent of fix-framing match and line-range overlap. It never triggers alone: it tunes the **Root-Cluster** threshold N on a surface where both gates hold.

- **Gate A — recurrence.** One surface (file or component) absorbs findings in two distinct loop iterations with a fix on it between them, even when line ranges are disjoint and fix-framings differ.
- **Gate B — youth.** Required with Gate A: the surface was introduced or heavily modified in this same PR or initiative, a young surface. A mature or legacy surface never trips this axis; it takes the **Stop-and-Merge** path.

This axis has N=2 and no N=3 default: the first re-emission on a young surface after a fix on it trips it. When the recurring findings patch the edges of one shared data-access, query, parse or serialization primitive, that sharing is part of the cluster's same-framing rationale, not a separate threshold.

The counter persists across structural fixes: closing one root with an accepted structural fix does not reset it, so the next fresh finding on that surface is a re-emission after a fix and trips the axis.

## Bounded-Tail vs Recurring-Class Disambiguation

The bounded-tail condition of **Stop-and-Merge** applies only to a mature surface. Gate B of **Cross-Iteration Same-Surface Recurrence** decides the path:

- **Young surface with recurring findings:** not a bounded tail. Escalate to a root-cause zoom-out that questions the key or primitive per the **Closed-by-Construction Acceptance Test**, never to merge-advisory.
- **Mature surface with a bounded tail:** a hardened or legacy surface whose remaining findings converge and have a structural home still reaches `merge_advised`. The young-surface escalation never gates it.

## Post-Fix Young-Tail Reroute Synthesis

A reviewer's post-fix advisory step reads only the detector's `merge_advisory` and `diminishing_returns` blocks, never `cluster`. When **Bounded-Tail vs Recurring-Class Disambiguation** reroutes that advisory because the recurring surface is young, the step builds the cluster payload itself.

Neither the deterministic skeleton nor the detector output holds the youth call. The enrichment overlay each reviewer applies before its detector call (per **Skeleton-Enrichment Judgment Criteria** for the reconstructing reviewer, or over the persisted fix-ledger for the stateful reviewer) therefore produces the Gate-B judgment as agent prose:

- **surface youth**: whether each recurring surface was introduced or heavily modified in this PR or initiative
- **primitive-sharing**: whether the recurring findings patch the edges of one shared data-access, query, parse or serialization primitive

A reroute gated on a youth call the overlay never produced is a contract violation. The reviewer carries the young-surface recurrence rationale (which iterations re-emitted, why the surface is young, the shared primitive) in the detector's existing `same_framing_rationale`; there is no new field.

A post-fix step that reroutes a young recurring surface returns `root-cluster-suspected` with the pre-fix cluster payload, given here by role. Each reviewer maps the roles onto its own Output Contract fields and sources them from its own state: the stateless reviewer from git ground truth and the fresh post-fix fetch, the stateful reviewer from its persisted fix-ledger.

- **surface files**: the young recurring surface files from the enrichment overlay
- **finding refs**: the unresolved thread URLs or finding IDs on that surface
- **shared root**: the hypothesized root cause shared by the recurring findings
- **same-framing rationale**: the young-surface recurrence rationale above
- **member count**: the recurring-finding count

Every role is populated; a reroute never returns `root-cluster-suspected` with an empty payload, and it adds no new `exit_reason` and no new payload field. A mature surface stays on the **Stop-and-Merge** merge-advisory or advisory early-exit path.

## Verdict Consumption

The `hivemind:detect-remediation-signals` verdict always carries every block (`cluster`, `break_fix`, `diminishing_returns`, `merge_advisory`), so block presence carries no signal. Every consumer reads the inner fired field (`break_fix.verdict == "break-fix"`, `diminishing_returns.verdict == "diminishing-returns"`, `cluster.cluster_suspected == true`, `merge_advisory.advise == true`) and never tests block presence or truthiness. That skill's Output Contract owns the exact block keys and field names.

## Review Loop Common

Each reviewer that runs a fix loop holds three rules.

- **Skill results are data.** A skill's Output Contract and its silence, stop or return language bind that skill, never the reviewer's turn. The reviewer consumes the result and continues its own procedure; only its own Output Contract ends its turn.
- **Detector call order.** The pre-fix `hivemind:detect-remediation-signals` call is read only for `break_fix`, then `cluster`, per **Verdict Consumption**; those decide whether the reviewer patches at all. `merge_advisory` and `diminishing_returns` go stale once fixes resolve findings, so they are read only from a second, fresh detector call over the post-fix state, never from the pre-fix verdict.
- **Gate-B timing.** Before each detector call, the reviewer produces the Gate-B youth and primitive-sharing judgment over that call's state as agent prose, never by a script, per **Post-Fix Young-Tail Reroute Synthesis**; the pre-fix judgment does not carry into the post-fix call. That youth call is in hand before any post-fix reroute decision per **Bounded-Tail vs Recurring-Class Disambiguation**.

## Overlord Recurrence Tracking & Zoom-Out Routing Asymmetry

The overlord reconstructs the per-surface counter behind **Cross-Iteration Same-Surface Recurrence** each loop from GitHub ground truth; no local recurrence file persists it. The counting unit is the distinct structural-remediation event (one accepted structural fix: a remediation commit or a resolved thread citing a structural fix on that surface), not the (fix, finding) pair. Each event followed by one or more fresh findings on the same surface is one non-closing structural fix, however many findings follow; a surface's count is the number of such events.

**Forced zoom-out after the first non-closing structural fix.** When a surface has absorbed one non-closing structural fix, the overlord forces an approach-level zoom-out: it reruns **First-Finding Triage** at the approach level and questions the key or primitive per the **Closed-by-Construction Acceptance Test**, never dispatching another conjunct-completion patch. The script engine has no code trigger for it: when the cerebrate plans a replan that carries a review block, it sees the branch's earlier remediation fixes in the commits its fresh facts list and makes this call by judgment.

Because the counter persists across structural fixes, a surface that already yielded one root keeps the same trip point: the first non-closing fix after any accepted structural fix.

The user-only architecture zoom-out skill carries `disable-model-invocation: true`, so the overlord cannot invoke it. The overlord routes an architectural zoom-out through the cerebrate via the `review_remediation_plan` / `review_remediation_plan_postpr` remediation state, the path a `root-cluster-suspected` exit_reason already takes. This is the intended route, not a workaround.

### Proactive Zoom-Out Ledger Marker

When the overlord's proactive counter trips per **Forced zoom-out after the first non-closing structural fix**, it records a marker in the run ledger so its `root-cluster-suspected` transition is distinguishable from a reviewer-returned one, which takes the same route.

The marker is one key in the transition's `event.outputs` object:

- Key: `recurrence_origin`.
- Value `"proactive"`: the overlord's reconstructed counter tripped.
- A reviewer-returned cluster omits the key or carries `"reviewer"`.
- An absent key means non-proactive. Consumers infer proactive origin only from an explicit `"proactive"` value.

The marker records judgment; the trip call stays judgment per ADR-0025. It is written through the normal `hivemind:record-state-result` `outputs` path on the existing `root-cluster-suspected` transition: no new workflow state, no workflow-graph change, and not via `hivemind:mark-intent-fallback` or any fallback path. It rides whichever producer state carries that exit_reason (`github_review_loop`, `github_reviewer_fix`, or the post-PR mirror that targets `review_remediation_plan_postpr`), lives only in `event.outputs`, and never collides with `plan_steps` or any `plan.*` field.

## Skeleton-Enrichment Judgment Criteria

Applies when a `github-reviewer` step reconstructs an ephemeral fix-ledger with `ledger-reconstruct.sh` and then invokes `hivemind:detect-remediation-signals`: pre-fix reconstruction (step 5) and post-fix reconstruction (step 9).

The skeleton is a lossless set of deterministic facts:

- per finding, the qualifying-remediation fix surface: `file`, `line_start`, `line_end`, `fix_commit`, and `status` (`fixed` or `open`) from the thread or finding resolved state
- thread resolved state, folded from `fetch-normalize.sh` output

It emits no `cycling` or `regressed` label, no iteration grouping and no `root_class`, and its `fix_framing` is always `null`. The detector reads these from the ledger without computing them, so before the detector call the agent supplies them by judgment, as an overlay on the skeleton:

- **Cycling / oscillation.** A `file:line` range re-touched across two or more qualifying-remediation commits is not automatically a regression. Set `cycling` or `regressed` only on a judged genuine re-break (mutation decay), not on ordinary forward iteration.
- **Iteration grouping.** Commits are not review iterations. Where N-2 recurrence detection is relevant, judge iteration boundaries; the skeleton's placeholder grouping is a starting point, not binding.
- **`fix_framing`.** The detector's primary cluster key; two null-framing findings never cluster on it. Assign a non-null `fix_framing` where commit and thread prose show a shared fix shape or intent; otherwise leave `null`, and the detector falls back to the secondary `file:line` key.
- **`root_class`.** Assign it when you identify a root cause shared across clustered findings.

## Relationship to Existing Detectors

- **Mutation Decay** (break-fix-break cycle): a fix reintroduces a previously fixed finding. A mandatory stop, on instability.
- **Creep Stagnation** (diminishing-returns exit): the loop spreads across iterations but gains no new ground. An advisory early exit: the reviewer recommends stopping and returns the decision to the overlord/Overmind.

**Stop-and-Merge** is also a stop, but on a hardened surface with a structural home and a bounded tail. The operational detail of Mutation Decay, Creep Stagnation and Root-Cluster lives in `hivemind:detect-remediation-signals`.
