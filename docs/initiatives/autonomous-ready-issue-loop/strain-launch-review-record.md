---
stamps: []
verdict: pending
open_counts:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 1
clean_round: null
---

# Design review record: Lair strain launch and containment

This record covers the design review of issue #630, the strain launch and containment part of the Lair, epic #603. Only the [strain launch design](strain-launch-design.md) is stamped. Its stamp's blob is `git rev-parse HEAD:docs/initiatives/autonomous-ready-issue-loop/strain-launch-design.md`, and the stamp is written last. The [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md) and the parent [solution design](solution-design.md) are reviewed, not stamped.

The review exits only when zero critical or high findings are open and one round raises no new findings. It runs at most 3 rounds.

Round 1 ran under the original procedure: two parallel, fresh, read-only `hivemind:cerebrate` passes (A and B), model opus, effort xhigh, each with "Memory context: none". Its IDs stay `L1-A<n>` and `L1-B<n>`.

From round 2 on, each round runs the procedure in "Procedure change" below. Any edit to the design after a stamp needs a review round of the change and a new stamp, within the cap.

### Procedure change (user, 2026-11-21)

- From round 2 on, by the user's instruction on 2026-11-21, each round runs ONE fresh, read-only `hivemind:cerebrate` pass covering both angles, delegated with effort high, with "Memory context: none". Two parallel passes are no longer run.
- **Angle 1:** code truth, governance and ADR conflicts, and existing-path coverage.
- **Angle 2:** failure modes, trust and injection, and testability.
- Because this design touches trust, credentials and the merge path, each round also runs one pass through the configured local review tool via `plugin/skills/adaptation-cycle/scripts/run-review.sh`. `HIVEMIND_LOCAL_REVIEWER` is unset and the Codex plugin is installed, so the `codex-plugin` preset is used. If no tool were configured, the pass would be skipped and the skip recorded here.
- The confirming round reviews only the diff since the previous round and the fixes to open findings, with effort medium.
- Finding IDs: the cerebrate pass uses `L<round>-C<n>`, such as `L2-C1`. The tool pass uses `L<round>-T<n>`, such as `L2-T1`. Round 1 keeps `L1-A<n>` and `L1-B<n>`.

## Record keys

- `stamps`: one entry per stamped document, with `path` and `blob` keys. Empty until the review passes.
- `verdict`: `pending`, `pass` or `fail`.
- `open_counts`: open findings by severity: `critical`, `high`, `medium` and `low`.
- `rounds`: the number of rounds run.
- `clean_round`: the round that raised no new findings, or `null`.

## Dispositions

Every finding is open until it gets exactly one disposition:

- **fixed**: the record says where.
- **deferred**: the record names a tracked issue.
- **recorded**: the record says where.
- **rejected**: the record says why.

**Open** is a state, not a disposition. An open finding is counted in `open_counts`, and its disposition column reads `open`. `open_counts` counts every finding still without a disposition, the round 3 findings below and every finding a round of this review raises.

### Round 3 findings owned by #630

The round 3 findings come from the parent [review record](review-record.md). #630 owns the findings below. Each disposition names the section of the strain launch design that answers it.

| ID | Severity | Finding | Disposition | Round 1 status |
| --- | --- | --- | --- | --- |
| A3-1 | high | Lair-written settings do not keep merge keys out of strains. | fixed: Components > Strain launch and settings, and Contracts and seams > Strain settings and Strain environment, for the user, project and local scopes; a managed merge key stays the named residual "managed settings" under Trust boundaries > Strain containment | fixed, round 1: pass A found the design text closes it |
| A3-4 | high | There is no contract for the strain's launch inputs or for carrying parked, branch, head and decisions out of the run result. | fixed: Components > Launch inputs, and Contracts and seams > Launch file and Strain result | fixed, round 1: pass A found the design text closes it |
| A3-5 | high | Re-claim and remediation contradict the detached spawn and the brood-child fresh-branch rule. | fixed: Components > Start points, where the remote compares the pre-image at the write: Lair mode of `push-branch.sh` pushes with a lease pinned to the pre-image the Lair captured, after an ancestry check, and the engine maps its fixed blocker line to `start_moved`; and the Failure modes rows "Start moved", "Moved head before a re-claim launch" and "Moved head before a remediation launch" | fixed, round 1: pass A found the design text closes it |
| A3-6 | high | Governance the strain overlord loads still tells it to ask, and no slice owns the edits. | fixed: Components > Unattended governance edits | fixed, round 1: pass A found the design text closes it |
| A3-7 | high | The facts step re-reads referenced issues and outsider comments live. | fixed: Components > Launch inputs ("Facts come only from the captured issue text") | fixed, round 1: pass A found the design text closes it |
| B3-2 | high | The strain's model derives launch inputs from the issue text, and the facts step re-reads GitHub live. | fixed: Components > Launch inputs | fixed, round 1: pass A found the design text closes it |
| B3-9 | high | Deny rules cannot deliver "a strain cannot merge, change labels or edit the issue". | recorded: Trust boundaries > Strain containment, as the named residual "a prompt-injected strain holds the user's rights", with the reworded claims in Decisions > Changes to shared documents, changes 1, 2 and 9 | fixed, round 1: pass A found the design text closes it |
| B3-17 | high | Env values leak into strains both ways, and the marker's source cannot be told. | fixed: Components > Strain launch and settings, and Contracts and seams > Strain environment and Marker check, against a stray or copied marker; a prompt-injected strain that rewrites the Lair's records stays the named residual under Trust boundaries > Strain containment | fixed, round 1: pass A found the design text closes it |
| B3-15 | medium | Re-claim from the pushed branch has four gaps: moved head, superseded design, unanswered park, decision size limit. | fixed: Components > Start points | fixed, round 1: pass A found the design text closes it |
| A3-9 | medium | Stall and agent-call budget rules rely on signals nothing produces, and the agent-call cap has no owner. | fixed: Components > Launch inputs ("Agent-call cap": the cap keeps back the record call) and Strain result and liveness ("The engine writes its own record" at every verified end), so `agent_budget` reaches the result | reopened in round 1 (L1-A4: `agent_budget` could not reach the result); fixed after round 1 |
| B3-12 | medium | Session end waits for "branch pushed", and run activity is undefined. | fixed: the opening list of replaced parent parts now holds the Lifecycle stage 1 sentence; Lifecycle steps 4 and 5 and Strain result and liveness ("Run activity") stand | reopened in round 1 (L1-A14: parent Lifecycle stage 1 still stood); fixed after round 1 |
| A3-14 | low | Remote control on strains is not covered under Trust boundaries. | fixed: Trust boundaries | fixed, round 1: pass A found the design text closes it |
| A3-15 | low | The state table omits spawn-brood's files. | fixed: State and ownership (the spawn record row, written by `spawn-brood.sh` before the session starts) and Components > Strain launch and settings | reopened in round 1 (L1-A3: no brood id write into the strain record); fixed after round 1 |
| B3-21 | low | The decision digest is only as complete as the strain's report. | fixed: Components > Strain result and liveness (the engine record at every verified end, with the record call kept back from the cap) and Contracts and seams > Strain result (`decisions` null, shown as unknown, when no record exists) | reopened in round 1 (L1-A4: decisions lost when no engine record was written); fixed after round 1 |
| B3-20, overlord-prose tests | low | The verification strategy has no overlord prose tests. | fixed: Verification strategy ("Overlord prose tests") | fixed, round 1: pass A found the design text closes it |
| B3-20, `tools/validate.sh` registration | low | The verification strategy does not register new tests in `tools/validate.sh`. | fixed: Verification strategy ("Registration in `tools/validate.sh`") | fixed, round 1: pass A found the design text closes it |
| A3-11 | medium | The Seam order ADR lists are incomplete (ADR-0010, 0017, 0029, 0037, 0042, 0044). | fixed: Seam order, where #604 now lists ADR-0029, ADR-0030, ADR-0042 and ADR-0044 beside ADR-0010, ADR-0017 and ADR-0037, and the other rows gain the ADRs L1-A9 names | reopened in round 1 (L1-A9: the Seam order rows missed ADRs); fixed after round 1 |

The other parts of B3-20, the injection and halt tests and the halt file path, are not owned by #630 and stay in the parent review record.

Round 1 moved A3-11 into this table. The earlier note that the Seam order meets it was a claim, and pass A found the Seam order rows still miss ADRs (L1-A9).

## Round 1

- **Date:** 2026-11-21.
- **Design reviewed:** blob `cb6f0acfdd4b30ffe898cfc0438b1d1c257686c1` at commit `c3898aecf1edcf1f1647fee7f5271fa295ef2b06`.
- **Reviewers:** two fresh read-only `hivemind:cerebrate` passes, model opus, effort xhigh, "Memory context: none".
- **Pass A angle:** code truth, governance and existing paths.
- **Pass B angle:** failure modes, trust and testability.

The passes found the same root in five places: L1-A1 = L1-B2, L1-A2 = L1-B8, L1-A4 = L1-B16, L1-A12 = L1-B4 and L1-A13 = L1-B12. L1-A10 overlaps L1-B3. Each ID is its own open finding in `open_counts`.

Pass A judged 11 owned round 3 findings closed by the design text and reopened 5 (see the round 3 table above): A3-9, A3-15, B3-12, B3-21 and A3-11.

**Remediation after round 1.** Each finding was checked against trunk code, and each round 1 finding and each reopened finding now has a disposition in its table. Every one is fixed in the design; none is deferred, recorded or rejected. The State column holds the disposition and the design section that closes it. Round 2 has not run, so these fixes are unreviewed until it does. The design's Amendments section has the matching entry.

### Pass A

| ID | Severity | Section | Finding | Evidence | Proposed fix | State |
| --- | --- | --- | --- | --- | --- | --- |
| L1-A1 | high | Context; Start points push rule | The claim that `push-branch.sh` is the one push of a run is false. The `github-reviewer` fix pass pushes, then the remediation tail pushes again, and the lease pinned to the start commit rejects the second push as stale, giving a false `start_moved`. The fix-pass start-moved line is relayed as free text, so `isStartMoved` never matches. | `github-reviewer.md:76`; `pr-feedback-remediation/main.js:5-10`; `pr.js:286-290` | List all push sites. The lease's expected value is the last commit this run's Lair-mode push landed, else the pre-image. Carry the fixed line in a schema field. Test two pushes in one run and the fix-pass push. | fixed: Start points (the push rule names both push sites, and the lease's expected commit advances to the strain's last landed push through `.hivemind/lair/pushed`; "The engine owns the mapping" adds the fix pass's `push_blocker` field), Context and code truth (two push sites), Failure modes ("Second push in one run") and Verification strategy |
| L1-A2 | high | Launch inputs, result, governance edits, Verification | The new synapse runner scripts `lair-launch-check.sh` and `lair-result.sh` and the new Write paths need edits the design never names. This widens the synapse no-prompt surface with no recorded decision. | `security-policy.md` Synapse Runner Gate (`:153`, `:161`, `:168`, `:178`, `:183`); `synapse.md`; `_shared/containment.sh`; `facts.js:293-304` (`--inputs` class); seed-hive rules; `tests/policy/safety-synapse-gate.json:4-24` (equal-mode set) | Add a governance-edit row for #604 and #607 that names all of these, plus a decision for veto. | fixed: Components > Unattended governance edits ("Synapse runner gate" names every edit) and Decisions (the wider synapse surface, listed for veto) |
| L1-A3 | medium | Strain launch and settings, State, Marker check, Lifecycle step 1 | The Lair writes the settings fragment before the spawn, but the worktree path, which the liveness hooks need, exists only after `spawn-brood` generates the brood id. No strain record field holds the brood id, and `spawn-brood` is not a listed writer. | `spawn-brood.sh:302-305`, `:485-486` | `spawn-brood` writes the brood id into the strain record and adds the liveness hooks. | fixed: Components > Strain launch and settings (`spawn-brood.sh` writes `spawn.json` before the session starts and adds the liveness hooks) and State and ownership (spawn record row) |
| L1-A4 | medium | Launch inputs, Strain result, Failure modes | The causes `agent_budget`, `lair_marker_unverified` and `launch_mismatch` cannot reach the result. The record write is an agent call past the cap, unverified and mismatch runs never become unattended, and the overlord's unverified path never runs `lair-result.sh`. Decisions taken before the cap drop from the digest. | Design text only | Reserve a call for the record, write the record at every end once `lair_strain` is not `none`, or drop the causes. | fixed: Components > Strain result and liveness (the engine record at every verified end; `lair-result.sh` writes `lair_marker_unverified` itself) and Launch inputs ("Agent-call cap" keeps back the record call) |
| L1-A5 | medium | Start points, Strain environment, Trust | Re-claim and remediation start at untrusted commits whose `.claude/settings.json`, hooks and `.mcp.json` run at launch. This contradicts "as the user set them". | `security-policy.md:33`; `ADR-0017:187` | Refuse start commits that touch `.claude/**`, `.mcp.json` or hooks, or record the residual with a governance edit. | fixed: Components > Start points ("Start configuration check"), Trust boundaries and Decisions; run-decided, listed for veto |
| L1-A6 | medium | Governance edits, Tier A row | External-effect approvals become decision parks, but ADR-0045 decision 7 and the PRD make them approval parks. | `adr:47-49`; PRD `:30`, `:58` | Add external effects to the approval-park list. | fixed: Components > Unattended governance edits (Tier A row: an external effect is an `approval` park) |
| L1-A7 | medium | Governance edits, Tier A and Strain runs rows | Questions and tool failures become failed results, but ADR-0045 decision 6 makes every ask a park. | `adr:46` | Route them through an engine-built park. | fixed: Components > Unattended governance edits (Tier A and Strain runs rows) and Strain result and liveness ("Every ask parks"); run-decided, listed for veto |
| L1-A8 | medium | Changes to shared documents | PRD lines 84, 86 and 107 and ADR-0045 line 109 contradict the design after the approved rewordings, and no change entry covers them. | PRD `:84`, `:86`, `:107`; ADR-0045 `:109` | Add change entries as Tier A questions. | fixed: Decisions > Changes to shared documents, changes 6 to 9, from the user's answer A on 2026-11-21 |
| L1-A9 | medium | Seam order | ADRs are missing: #604 needs ADR-0044, ADR-0029, ADR-0030 and ADR-0042; #608 needs ADR-0045 decision 5; #609 and #610 need decision 3; #610 needs decision 11. | Design text only | Add them. | fixed: Seam order (each row gains the ADRs named) |
| L1-A10 | medium | Strain settings deny; Remediation launch | The deny `Bash(gh issue view *)` blocks the `github-reviewer` defer check. `gh issue create` is not denied, though decision 4 limits a strain to its branch and PR. | `github-reviewer.md:79`; `remediation-doctrine.md:65` | Add an unattended Defer-with-Scope rule. Decide on `gh issue create`. | fixed: Contracts and seams > Strain settings (`gh issue create` denied), Components > Remediation strain launch ("Deferring") and Unattended governance edits ("Remediation fix pass"); run-decided, listed for veto |
| L1-A11 | medium | Remediation launch, Launch file, Failure modes | A remediation has no claim, yet the nonce, the record key, the crash outcome in the claim marker and the budget clock `claimed_at` depend on one. | Design text only | Define them or state the seam with #610 and #632. | fixed: Components > Remediation strain launch ("Its claim": a dispatch marker on the pull request), State and ownership, Failure modes (Crash, Budget overrun) and the #632 assumptions |
| L1-A12 | low | Launch inputs draft; re-claim | A re-claim reuses the parked draft PR. `open-plan-pr.sh` leaves the draft state, and nobody marks it ready. | `open-plan-pr.sh:48`, `:148` | State who marks it ready. | fixed: Components > Start points ("A completed re-claim is marked ready" by the Lair, #609) and Failure modes |
| L1-A13 | low | Remediation author filter | CI check-failure records have no author, and the filter rule for them is unstated. | `fetch-normalize.sh:106-116` | State the rule. | fixed: Components > Remediation strain launch ("CI records pass the filter") |
| L1-A14 | low | Opening paragraph | Parent Lifecycle stage 1 still stands and contradicts Lifecycle steps 4 and 5. | `solution-design.md:134` | Add it to the superseded list. | fixed: the opening list of replaced parent parts (the Lifecycle stage 1 sentence) |
| L1-A15 | low | Launch inputs, references | `references: []` means the PR closes no issue, and nothing says who closes the issue. | `pr.js:100-105` | State the seam with #631 and #608. | fixed: Components > Launch inputs and Contracts and seams > Assumptions about #631 (the merge lane closes the issue) |
| L1-A16 | low | Failure modes; headless checks | No fallback row covers an empty `--settings` env value that fails to override a lower scope. | Design text only | Add a row. | fixed: Contracts and seams > Strain settings (fallback value `off`) and Failure modes |
| L1-A17 | low | Governance edits; Marker check | No overlord edit row covers switching onto `start.branch`. "No output line changes" contradicts the new `push-branch.sh` start-moved line and the `gather-facts` `lair_strain` line. | `overlord.md:177` | Add the row and reword. | fixed: Components > Unattended governance edits (Strain runs row: the switch onto `start.branch`) and Contracts and seams > Marker check (the new output lines named) |

### Pass B

| ID | Severity | Section | Finding | Evidence | Proposed fix | State |
| --- | --- | --- | --- | --- | --- | --- |
| L1-B1 | critical | Marker check; Strain runs | `spawn-brood` writes the manifest only after Pass 3 sees the strain's started evidence, so the first marker check always prints unverified. Every Lair strain stops, and the breaker halts after 3. `worktree_path` is display-only in manifest v4. | `spawn-brood.sh:1252-1260`, `:1091-1112`, `:1321-1336`, `:1456-1463`; `:1355-1358` | `spawn-brood` writes the brood id and strain short into the strain record before `tmux new-session`. Derive the expected worktree from `<checkout>/.claude/worktrees/<brood-id>/<short>`. Test before any manifest exists. | fixed: Components > Strain launch and settings (`spawn.json` before `tmux new-session`) and Contracts and seams > Marker check (the worktree is built from the spawn record; no manifest read), with a test before any manifest exists |
| L1-B2 | high | Context; Start points push rule | Same finding as L1-A1: a double push gives a false `start_moved`, and "Nothing is pushed" is false. | As L1-A1 | The lease advances to each commit this strain pushed. Tests in `tools/test_push_branch.sh` and a remediation engine case. | fixed: as L1-A1, with the two-push cases in `tools/test_push_branch.sh` and `tests/workflow-scripts/pr-feedback-remediation.test.mjs` |
| L1-B3 | high | Remediation author filter; deny rules | `fetch-normalize.sh` outputs no bodies, and `github-reviewer` fetches bodies itself. The deny `Bash(gh api *)` blocks the graphql read, and the fallback `gh pr view --comments` is unfiltered. The deny `gh issue view` breaks the defer check. The claim that deny rules miss skills is false. | `fetch-normalize.sh:88-104`; `github-reviewer.md:79` | The script outputs filtered bodies and the reviewer reads only those. A script does the defer check. Add tests. | fixed: Components > Remediation strain launch ("Bodies come from the filter", "Deferring"), Unattended governance edits ("Remediation fix pass") and Contracts and seams > Strain settings (the deny-rule claim reworded); the defer takes recorded-residual homes only, not a script |
| L1-B4 | high | Re-claim; Launch inputs draft | Same root as L1-A12: `draft:false` has no effect on a reused parked draft PR. A completed re-claim stays draft, never merges and stalls silently. | `open-plan-pr.sh:48`, `:148` | Name the owner of `gh pr ready` (an engine script or #631). Add a failure row and a test. | fixed: as L1-A12, with a Failure modes row and a `tools/test_lair_tick.sh` case |
| L1-B5 | medium | Start points, first claim | A branch from an earlier failed run survives clean-up, and `create-working-branch.sh` switches onto it silently. | `create-working-branch.sh:105-110` | Refuse an existing local branch on a first claim. Check ancestry against the trunk commit. The Lair deletes the local ref on clean-up. Add tests. | fixed: Components > Start points ("A first claim refuses an old local branch"), Lifecycle step 5 (local ref delete) and State and ownership; no separate ancestry check, since the refusal covers it |
| L1-B6 | medium | Re-claim; Lifecycle step 5 | A park after commits leaves the branch unpushed and keeps the worktree. The re-claim is blocked by `unpushed_work`, then `branch_moved`. | Design text only | Seam with #607: a park after commits pushes the branch, or define the re-claim from the local head. | fixed: Components > Start points ("A park after commits pushes", #607) |
| L1-B7 | medium | Failure modes; pre-launch check | Remediation strains have no terminal effect for crash, stall, budget, invalid result, unverified, mismatch and `no_engine_record`. Two pre-launch conditions lack outcomes, and a tick can re-dispatch on every tick. | Design text only | Add terminal effects and a repeat guard, with tests. | fixed: Components > Start points ("Handling by start kind" and the moved-head refusal effects) and Failure modes (repeat guard and remediation effects), with `tools/test_lair_tick.sh` cases |
| L1-B8 | medium | Launch inputs, result, governance edits | Same root as L1-A2: the new Write kinds are denied by the synapse gate, so every record write is refused and every run ends `no_engine_record`. | `synapse-gate.sh:14-16`, `:27-32`, `:405` | Edit `containment.sh`, `synapse-gate.sh` and `security-policy.md`, add a pin and Write-kind tests. | fixed: as L1-A2; the inputs file names fit the `<kind>-inputs-<token>.json` rule of `containment.sh`, and `tools/test_synapse_gate.sh` covers the Write kinds |
| L1-B9 | medium | Result; deny rules | The deny `Edit(//<Lair checkout>/.hivemind/lair/**)` does not cover the worktree's `.hivemind/lair/result.json` and `record.json`, so a model can write `result.json`. | Design text only | Add `Edit(//<worktree>/.hivemind/lair/**)` and a test. | fixed: Components > Strain launch and settings and Contracts and seams > Strain settings (`spawn-brood.sh` adds `Edit(//<worktree>/.hivemind/lair/**)`), with a test |
| L1-B10 | medium | Settled decisions; #632 assumptions | Park question and option text written by an untrusted strain is copied verbatim into the next strain's decisions. The pre-spawn scan covers only issue text. | Design text only | Scan all launch-arg text, or build entries from key, option id and answer only. | fixed: Contracts and seams > Settled decisions (the park text is scanned with all launch-arg text), Unattended governance edits ("Pre-spawn approval") and the #632 assumptions |
| L1-B11 | medium | Trust; Launch inputs | `WebFetch` and `WebSearch` in `cerebrate`, `drone` and `changeling`, plus `gh pr view --comments` and `gh search`, are untrusted channels the design does not list. | Design text only | List them, deny them in strains and add a headless check. | fixed: Trust boundaries ("Untrusted channels"), Contracts and seams > Strain settings (deny list) and Verification strategy (headless check); run-decided, listed for veto |
| L1-B12 | medium | Remediation author filter | Same root as L1-A13: CI records have no author, so the filter drops them (a CI-red remediation ends clean with CI red) or an exception goes unstated. The injection-scan half of the lead is not a defect. | `github-reviewer.md:66` | Pass CI records (admin-installed apps, write-access statuses). Add a test. | fixed: as L1-A13, with a `tools/test_fetch_normalize.sh` case |
| L1-B13 | medium | Launch command; Strain environment | `tmux new-session` inherits the whole tmux global environment minus three keys, including the Lair env and `SSH_AUTH_SOCK`, so the "exact" list is incomplete. A strain can run `tmux set-environment -g` to reach later strains and a restarted Lair. | `spawn-brood.sh:933-934` | Use `env -i` plus a fixed allowlist and a pin test. Tell #632 that no secret goes in the Lair env or same-user files. Add a residual. | fixed: Components > Strain launch and settings and Contracts and seams > Strain environment (`env -i` with a fixed list), Trust boundaries (tmux global environment residual) and the #632 assumptions; run-decided, listed for veto |
| L1-B14 | medium | Failure modes; settings and launch write | `spawn-brood` can exit 1 with a live session, and a reconcile can start a second strain. | `spawn-brood.sh:1384-1385`, `:1421-1423`, `:1440-1462` | Kill session `<brood-id>-<short>` before the reconcile. Add a test. | fixed: Components > Strain launch and settings ("A failed spawn"), Lifecycle step 2 and Failure modes, with a `tools/test_lair_tick.sh` case |
| L1-B15 | medium | Verification | No test file is named for crash, stall, invalid result, `/exit` grace, budget, the pre-launch check, `start_moved` by kind, clean-up and `unpushed_work`, `design_superseded`, `park_unanswered` or the decision limits. The PRD requires crash and stall tests. | PRD `:107` | Name the files and their registration. | fixed: Verification strategy (`tools/test_lair_tick.sh` and the added cases, with their registration) |
| L1-B16 | low | Strain result; Failure modes | Same root as L1-A4: three causes never reach the result, and the overlord cannot turn a question into a failed result because `lair-result.sh` takes no argument. | As L1-A4 | Record at every end once the marker is seen. The overlord runs `lair-result.sh` with a fixed flag. | fixed: as L1-A4; no overlord flag is needed, because `lair-result.sh` runs the marker check and every unattended ask parks |
| L1-B17 | low | Registration; governance edits | The marker-check library and `lair-*.sh` have no named `validate.sh` paths. The library is routed only to the push-branch and open-plan-pr suites, though `gather-facts`, `fetch-normalize` and the lair scripts source it. Overlord-prose pins are missing for the `user_gate` edits and the decision-autonomy brood-approval bullet. | `validate.sh:641-675` | Name the paths, route to every consumer and list the pins. | fixed: Verification strategy ("Registration in `tools/validate.sh`" names the paths and every consumer route; "Overlord prose tests" lists the user_gate and brood-approval pins) |
| L1-B18 | low | Existing-path coverage; push | If the settings env does not reach workflow-agent Bash, the scripts print `none` and fall back to the lease-retry overwrite and no author filter. Nothing cross-checks this. | `push-branch.sh:441-445` | Add a headless check. Fail closed when the worktree holds `.hivemind/lair/launch.json`. | fixed: Contracts and seams > Marker check (`unverified` when the worktree holds `.hivemind/lair/launch.json` with no marker), Failure modes and Verification strategy (headless check) |

## Sources

- The parent [review record](review-record.md): the round 3 findings, their severities and the three-way split.
- Issue #630: the findings it owns and its acceptance criteria.
- The [strain launch design](strain-launch-design.md): the sections each disposition names.
- The local review root-cluster report on the design's start-point paragraph: local review iterations 1, 3 and 4 each found a branch move that fell after a start check, and a fourth finding showed that a plain push accepts a move the strain absorbed, such as a move it fetched and merged during the run.

## Decisions taken (listed for veto)

- B3-17 is held to the high bar. The round 3 table of the parent review record rates it medium, and #630 lists it with its highs.
- B3-9 is recorded, not fixed: the risk stays as a named residual, with the claims reworded per the user's answers below.
- B3-20 is split into the two parts #630 owns, each with its own disposition.
- Each owned finding was dispositioned before round 1, so `open_counts` started at zero. Round 1 checked each disposition: 11 stay fixed and 5 are open again.
- This record keeps the parent record's keys and disposition vocabulary.
- The start-move class is fixed by changing the push's key from fast-forward acceptance to the remote branch's pre-image, the commit the run started from, which the remote compares at the write. The overlord's head recheck after the switch is removed (Components > Start points).
- Lair mode of `push-branch.sh` pushes with a lease pinned to the start commit, `--force-with-lease=refs/heads/<b>:<pre-image>`, with an empty value on a first claim, after an ancestry check so the push never rewrites the branch. This reverses the design's earlier wording that a strain's push is never forced. Taken under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal): a strong recommendation with a clean gate, and reversible.
- A refused first-claim push goes to `lair:failed`, counted toward the circuit breaker (Failure modes, row "Start moved").
- No deny rule on force flags is added: the workflow's lease is pinned to a value the Lair captured, and a push a strain runs by hand stays inside the named residual (Trust boundaries > Strain containment).
- No mid-run poll of the remote branch is designed: only the pinned-lease push sees a move made during the run. The wasted run time of a strain whose branch moved mid-run is a recorded residual in Components > Start points. The run took option A of Q1, a strong recommendation.

Taken by the run at the round 1 remediation, each listed in the design's Decisions:

- L1-A5: the Lair's start configuration check refuses a re-claim or remediation start commit whose diff against trunk touches `.claude/**`, `.mcp.json` or committed hook files, and hands the issue off (Components > Start points).
- L1-B13: strains launch under `env -i` with a fixed list: `HOME`, `PATH`, `USER`, `SHELL`, `TERM`, `LANG`, `TMPDIR` and the named credential and config variables. The tmux global environment (`tmux set-environment -g`) is a named residual, and #632 is told that no secret may sit in the Lair's environment or in same-user files (Contracts and seams > Strain environment, Trust boundaries).
- L1-A7 and L1-A6: every ask an unattended run still raises becomes a park the engine builds, per ADR-0045 decision 6, not a failed result; an external effect is an `approval` park (Components > Unattended governance edits, Tier A row).
- L1-A10 and L1-B11: the barrier list adds `gh issue create`, `gh pr view --comments`, `gh search`, and `WebSearch` and `WebFetch` beyond the earlier github.com rule. A strain defers only to a recorded-residual home, not through `gh issue view` (Contracts and seams > Strain settings, Components > Remediation strain launch).
- L1-A2 and L1-B8: every synapse edit is named (`security-policy.md` Synapse Runner Gate, `synapse.md`, `_shared/containment.sh`, the `synapse-gate.sh` Write kinds, the `facts.js` `--inputs` class, the seed-hive rules in `_shared/settings-merge.sh`, `tests/policy/safety-synapse-gate.json`). The wider synapse no-prompt surface is a decision for veto (Components > Unattended governance edits, "Synapse runner gate").

Taken from the reviewers' proposed fixes, where a choice remained:

- L1-A12 and L1-B4: the Lair, not a strain or `open-plan-pr.sh`, marks a completed re-claim's draft pull request ready, so the script's "a reused PR is not changed" contract stays.
- L1-A16: the fallback for an empty value that does not override is the merge key value `off`, which `merge-approved.sh` reads as `MERGE=skipped:bad-setting`.
- L1-B10: the park text is scanned with the other launch-arg text, rather than dropped from the decision entry, so the next strain keeps the question's wording.
- L1-B5: an existing local branch on a first claim is refused outright, with no separate ancestry check against trunk.
- L1-A11: a remediation's claim is a dispatch marker on the pull request, whose form #632 owns.

## Decisions asked

The user was asked four always-ask (Tier A) questions and answered each with option A on 2026-11-21:

- Reword ADR-0045 decision 4 to what the settings deliver.
- Reword PRD line 64 to what the settings deliver, with an injected strain as a named residual.
- Reword ADR-0045 decision 3 to name the start points for a first claim, a re-claim and a remediation.
- Local review finding f26808d3 on the remediation author filter: keep the in-scope Bot exception as trusted. Changes 4 and 5 of the design propose the matching PRD line 62 and ADR-0045 decision 11 wording.

On 2026-11-21 the user chose "change approach" when local review reported the root cluster on the design's start-point construct: the push is keyed on the remote branch's pre-image instead of another patch to the fast-forward rule.

At design review round 1 (L1-A8), the user was asked one more always-ask (Tier A) question and answered option A on 2026-11-21: "Your earlier answers changed ADR-0045 decisions 3 and 4 and PRD line 64. Four more lines still say the old thing and now contradict the design ... Should these four lines get the matching rewording, recorded under 'Changes to shared documents' for a later issue to apply?" Changes 6 to 9 of the design hold the proposed text: PRD line 84 (the three start points), PRD lines 86 and 107 ("merge keys set empty"), and ADR-0045 line 109 (the settings are a barrier, not full containment, and a prompt-injected strain stays a named residual).

On 2026-11-21 the user directed a change to the review procedure: "each review round runs ONE hivemind:cerebrate pass covering both angles, delegated with effort: high ... The confirming round reviews only the diff since the previous round and the fixes to open findings, with effort: medium." See "Procedure change" at the top of this record.

The design's section Decisions > Changes to shared documents holds each rewording as exact proposed text. A later integration issue applies them. None is applied in this pull request.
