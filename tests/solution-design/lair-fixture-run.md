# Solution design: Lair — Software Factory

This design covers the HOW the slices of epic #603 share. It builds on the PRD, `docs/prds/autonomous-ready-issue-loop.md`, and on ADR-0045, `docs/adr/0045-lair-software-factory.md`, citing them as "ADR-0045 decision N" rather than restating them. Four frozen part designs in `docs/initiatives/autonomous-ready-issue-loop/` govern parts of it: strain launch (`strain-launch-design.md`, #630), the merge lane (`merge-lane-design.md`, #631), claim integrity (`claim-integrity-design.md`, #632) and strain containment (`strain-containment-design.md`, #646). A part this design hands to one of them names that part design and its section. The decisions already settled in the merged design `docs/initiatives/autonomous-ready-issue-loop/solution-design.md`, its review records and ADR-0045 are cited where they were settled.

## Context and code truth

The Lair builds on this code, as it stands on trunk:

- `plugin/skills/spawn-brood/scripts/spawn-brood.sh` starts each strain as a detached tmux session running `claude` in its own worktree, and copies the coordinator's `.claude/settings.local.json` into every strain worktree.
- `plugin/skills/brood-status/scripts/brood-status-collect.sh` reports, per strain, tmux liveness, pull request state and run ledger state. It reads no run result, so for the Lair it gives liveness only.
- `plugin/skills/github-review-loop/scripts/merge-approved.sh` is the only merge path. It reads `HIVEMIND_AUTO_MERGE` and `HIVEMIND_AUTO_MERGE_ADMIN` each time it runs, and never reads the pull request body. Its tests are `tools/test_merge_approved.sh`.
- `plugin/workflow-src/lib/decide.js` with `plugin/references/decision-autonomy-table.json` has the levels `high`, `balanced` and `low`; an unknown level resolves to `low`. Its only actions are `take` and `ask`. There is no `unattended` level and no park action.
- `plugin/hooks/hooks.json` holds `PreToolUse` hooks only. There is no `Stop` hook.
- `plugin/agents/overlord.md` holds the `## Instinct` path, the `## Resume On Start` question and the default post-PR watch, each of which asks the user.
- `plugin/skills/triage-backlog/scripts/triage-ops.sh` defines the `readiness:*` labels and `type:epic`, and no `lair:*` family.
- The standard-delivery launch in `plugin/workflow-src/standard-delivery/main.js` already takes settled `decisions` and a `draft` flag.
- `plugin/skills/_shared/readiness-check.sh` is the readiness check. Its snapshot mode, `hivemind_readiness_check_snapshot <commit> <owner/repo> <trunk-name>`, reads issue snapshots on stdin and makes no GitHub read.
- Nothing under `plugin/` reads `HIVEMIND_LAIR_STRAIN` or uses a `lair:*` label.

The project's documented principles and governance the design relies on, each named as the project names it:

- `CLAUDE.md` and `docs/engineering-principles.md`: P20 (Doctrine homes), which gives the ADR conditions under Decisions; P26, design for the consumer project, so every optional capability is detected with a stated fallback.
- `CONTEXT.md`, whose canonical terms this design uses: strain, brood, overlord, Ready Issue.
- `plugin/governance/decision-autonomy.md` (Review Calls), which resolves the decisions below, and `plugin/governance/security-policy.md` (External Content Boundary), under which the issue text and every comment are data.
- ADR-0045, which this design implements; ADR-0007, ADR-0026 and ADR-0036 decision 8, which ADR-0045 amends for Lair strains only; ADR-0043 for reviewer Bot identity; ADR-0044 decisions 17 to 20 for the Lair tick's merge path; ADR-0046 for the readiness check and the rule that a docs pull request never takes the Lair's auto tier.

## Components

### Strain launch and settings

Built by #604. Writes one settings file per strain, passed with `--settings`, carrying `HIVEMIND_LAIR_STRAIN` and the merge keys set empty, with deny rules on the merge, label and issue-edit commands. Starts the strain in its worktree inside the platform containment strain containment designs. Strain launch governs it: Components "Strain launch and settings", "Launch inputs" and "Start points".

### Strain result and liveness

Built by #604, with crash and stall detection built by #608. Gives the Lair one schema-checked result per run and the liveness files it reads for crash and stall. Strain launch governs the result and liveness files; claim integrity governs crash and stall detection.

### Unattended autonomy level

Built by #607. Adds the `unattended` level to the autonomy table and the park action to `decide()`, selected only by `HIVEMIND_LAIR_STRAIN`. Builds the park record and its key, and the agent-call cap. Replaces the overlord's Instinct fallback, Resume On Start question and post-PR watch with parks for a verified strain (strain launch, Components "Unattended governance edits").

### Controller tick and admission

Built by #608. The deterministic controller in a tmux window: the tick loop, the single-instance lock, admission with the readiness-check call, the injection scan, claim labels and marker comments, the halt file, the wall-clock budget, the start-up sweep, the queue report and the containment probe `sandbox`. Changes `triage-ops.sh` so triage leaves `lair:*` issues alone. Claim integrity governs it, and strain containment its containment work.

### Merge lane and auto tier

Built by #605. The tick's merge step, the settle check and the auto-tier script, whose fixed floor holds `docs/prds/`, `docs/initiatives/` and `docs/adr/`. The merge lane governs it.

### Park answer round trip

Built by #609. Writes the park marker, admits answers in the answer form, builds the settled decisions and re-claims the issue on its pushed branch. Claim integrity governs the marker and counting rule; strain launch governs the settled decisions.

### Post-PR remediation strains

Built by #610. Polls each open Lair pull request and dispatches at most one remediation run for it. Strain launch governs the dispatch and launch; the merge lane governs the markers and the outcome mapping.

### Decision digest and circuit breaker

Built by #611. Writes the local decision digest, one file per run, and halts the Lair on the circuit breaker. Claim integrity governs the breaker; #611 designs the digest's detail during its build.

### Release-train versioning mode

Built by #606, after its decisions are settled through #647. The opt-in mode in which each pull request adds a change fragment and a script-built release pull request applies the highest bump.

### Parallel strains

Built by #612, after #606. Runs more than one strain at once, only where containment is confirmed, with parallel Lair pull requests merged in sequence.

## State and ownership

GitHub alone is authoritative (ADR-0045 decision 2). Every local file is a cache, a control input or a hand-off from a strain, except the marker key and the decision digest, the two local items GitHub cannot give again.

| State | Owner and writer | Readers | Authoritative |
| --- | --- | --- | --- |
| `readiness:ready` and `type:*` labels | The user, through triage | Lair, triage | yes |
| Other `readiness:*` moves and every `lair:*` label | Controller tick and admission; Merge lane and auto tier for `lair:review` | Lair, triage, user | yes |
| Marker comments (claim, outcome, park, handoff, review, exit) | The Lair, signed with the marker key | Lair, user | yes |
| Answer comments | A user with write permission | Lair only | yes, when the answer rule admits them |
| Captured issue text and its hash | Controller tick and admission, at claim | Strain, as its request | no; the hash in the claim marker is |
| Marker key | Controller tick and admission, under `control/` | Lair only | no; a local item GitHub cannot give again |
| Decision digest, one file per run under `control/digest/` | Decision digest and circuit breaker | User only | no, a local item GitHub cannot give again |
| Strain settings, launch file and worktree | Strain launch and settings | Strain | no |
| Result file and liveness files | The strain writes them; Strain result and liveness defines them | Lair | no |
| Halt file | The user | Lair | no; a control input |
| Merge settings | The user, in `.claude/settings.local.json` then `~/.claude/settings.json` on the Lair's machine | Merge lane, read fresh each tick | no; a control input |

Every other row is governed by a part design's State and ownership section.

## Contracts and seams

- **Strain result.** Outcome (`complete`, `parked`, `blocked` or `failed`), pull request, branch, head, a typed park record and the decisions taken, schema-checked by the Lair. An exit with no result is a crash. Strain launch, Contracts and seams, "Strain result".
- **Lair-written settings.** The unattended marker, the merge keys set empty and the deny rules (ADR-0045 decision 4 as amended). They are the only channel that selects unattended mode; the coordinator's local settings are not copied in.
- **Marker comments.** Append-only, signed and posted on the claimed issue. Claim integrity, Contracts and seams, "Marker comment", "Marker payload, every kind" and "Counting rule".
- **Park record.** `key`, `type` (`decision`, `fact` or `approval`), `question`, `options`, `recommendation`, `branch`, `pr`. The `key` is `park-` then the first 16 hex characters of the SHA-256 of the stop's identity fields, so it always matches `^[a-z0-9][a-z0-9-]{0,63}$`, and the same stop on a re-claim gives the same key.
- **Answer form.** `/lair answer <key> <option or text>`. A `decision` answer names one option; a `fact` answer is free text.
- **Settled decisions.** The standard-delivery `decisions` launch input, built by the Lair alone from admitted answers, each carrying its provenance. Strain launch, Contracts and seams, "Settled decisions".
- **Auto-tier script result.** The merge lane, Components "Auto-tier script".
- **Readiness-check call at claim.** `hivemind_readiness_check_snapshot` with the claim's trunk commit, `<owner/repo>` and `<trunk-name>`, and the claim's snapshot on stdin. For a re-claim, the snapshot's trunk commit, never the parked head. Claim integrity, Contracts and seams, "Readiness-check call at claim".
- **Queue report.** The Ready Issue queue size, and readiness-check codes from #615's closed set. Claim integrity, Contracts and seams, "Queue report".

## Trust boundaries

Untrusted input enters through the issue title and body, every comment, review text, CI check descriptions and a strain's own output. Each is data per `plugin/governance/security-policy.md` (External Content Boundary):

- The issue text is captured with its hash at claim, scanned before spawn and passed to the strain as its request; the strain never re-reads the issue. A suspect issue is handed off and never run.
- Only answers in the answer form, by a user with write permission, unedited, after the park marker, reach a strain, and only as settled decisions the Lair builds.
- Review text reaches a remediation strain only through strain launch's author filter, scanned before use; an in-scope reviewer Bot (ADR-0043) counts as trusted.
- Digest entries label their decision text as untrusted strain output.

Authority each actor holds:

- **The user**, with write permission: the `readiness:ready` label on an unedited issue as admission, park answers, review comments, the halt file, the merge settings on the Lair's machine, holds on `lair:review` and `lair:claimed`, the batch review and the digest veto.
- **The Lair**: the claim, every label move other than `readiness:ready`, the signed markers and the only merge, all under the executing user's credentials.
- **A strain**: push its own branch and open or update its pull request, nothing more; it never writes to the issue. Deny rules are a barrier against its mistake, not full containment, and a prompt-injected strain running with the user's rights stays a named residual of ADR-0045.
- **Any commenter**, write permission or not, can spend a pull request's one remediation run or send it to batch review; no comment text reaches a strain this way.

Strain containment keeps every strain out of `control/` and the Lair's tmux servers, per platform. The standing threat model is parity: a strain must be no less safe than the same work run in the maintainer's own session on the same machine.

## Lifecycle

Issue labels move as ADR-0045 decision 16 states:

1. `readiness:ready` to `readiness:implementation` with `lair:claimed` at claim, with a claim marker naming the run.
2. To `readiness:done` when GitHub shows the pull request merged, and the issue is closed before its exit marker.
3. To `readiness:needs-decision` on an answerable park, keeping `lair:claimed`; the user answers and relabels `readiness:ready`, and admission runs again.
4. `lair:handoff`, `lair:failed` and `lair:review` as the merge lane's Lifecycle "Run outcome to labels" and "Exits" map each run end; an approval park, a third park, a suspect scan or a refused re-claim hands the issue off.

A run moves through these stages: claim, spawn, run, result, labels, merge; park, answer, re-admit, continue on the pushed branch; at most one post-PR remediation run; halt and circuit breaker; and the start-up sweep, which resolves every claimed issue with no live strain and no pull request to failed, never back to ready. Each multi-write route writes its route-ending marker last, so a tick stopped partway is repeated by the next tick.

## Existing-path coverage

- Interactive standard-delivery is unchanged when `HIVEMIND_LAIR_STRAIN` is absent and the checkout holds no `.hivemind/lair/launch.json`; with that file and no marker, every Lair script fails closed. Interactive sessions never enter unattended mode.
- Non-Lair brood strains keep today's behavior, the settings copy included.
- Triage is unchanged except that it leaves `lair:*` issues alone.
- The interactive review watch and interactive auto-merge through `merge-approved.sh` are unchanged.
- `spawn-brood.sh`, `push-branch.sh` and `create-working-branch.sh` are unchanged outside Lair mode.
- Each part design's Existing-path coverage section adds the paths its part touches.

## Failure modes

| Failure | Detection | What happens next |
| --- | --- | --- |
| Crash | The session exits with no result file. | Outcome `crashed` in an outcome marker, with labels by the merge lane's Lifecycle "Run outcome to labels"; counts toward the breaker. |
| Stall | The idle signal: no result and no run activity, by strain launch's activity rule. | Outcome `stalled` in an outcome marker, with the merge lane's labels; the session is ended and cleaned up; counts toward the breaker. |
| `/exit` sent through tmux does not end a session | The session is still alive after the result is read. | The Lair kills the session, then cleans up. |
| Budget overrun | The wall-clock clock of 6 hours, or the engine's agent-call cap of 80 work calls. | Wall clock: outcome `timed-out`, or a park when a parked result was written first; counts toward the breaker. Agent-call cap: as strain launch's Failure modes "Budget overrun" states. |
| Invalid result | The schema check fails, or the result head is still absent after a fetch that completes. | Outcome `invalid-result`; counts toward the breaker. |
| Three consecutive counted outcomes | The breaker, recomputed from outcome markers. | The Lair halts with a stated cause; parks and review waits do not count. |
| GitHub read failure or rate limit | The tick's read fails or is incomplete. | As claim integrity's Failure modes "GitHub read failure or rate limit" and the merge lane's "Failed or incomplete tick read" state. |
| Merge refused | `merge-approved.sh` prints a refusal. | The pull request stays open; the merge lane's Failure modes row governs the retry or batch review. |
| CI red | The head's check rollup. | The pull request's one remediation run, never a second. |
| Issue edited after claim | The captured hash differs from the issue. | No merge; the pull request goes to `lair:review`. |
| Edited answer, or an answer by a user without write permission | The comment's edit history, or the user's permission. | Ignored; the issue stays in `readiness:needs-decision`. |
| Orphaned claim | The start-up sweep finds no live strain and no pull request. | `lair:failed`, never back to ready. |
| Strain containment cannot be confirmed | The probe `sandbox` at each start. | The Lair claims nothing and stops with cause `strain_env_preflight`, probe `sandbox` and the case id. |
| A route stopped before its last marker | A route whose last marker is missing. | The next tick computes the route again and repeats its writes, each marker once. |
| Digest write fails | As #611 designs it. | Reported in the queue report, as #611 designs it. |

No failure falls back silently: each ends in an outcome marker, a label, a stop with a cause or a queue report line.

## Decisions

Each decision names its ADR or writes `No ADR: fails <condition>`, with the condition from P20 in `docs/engineering-principles.md`. Every decision below was settled before this run; each cites where.

### D1: GitHub is the only authoritative state

Asked, with the answer: the maintainer accepted ADR-0045 on 2026-11-21. ADR: ADR-0045 decision 2, with its amendments of 2026-11-21 and 2026-11-22 naming the marker key and the decision digest as the local items GitHub cannot give again.

### D2: Strains are interactive tmux sessions the Lair owns

Asked, with the answer: the maintainer accepted ADR-0045 on 2026-11-21. ADR: ADR-0045 decision 3, amending ADR-0007 for Lair strains.

### D3: The Lair writes each strain's settings with the merge keys set empty

Asked, with the answer: the maintainer accepted ADR-0045 on 2026-11-21. ADR: ADR-0045 decision 4 as amended.

### D4: Unattended is an autonomy level whose third action is park

Asked, with the answer: the maintainer accepted ADR-0045 on 2026-11-21. ADR: ADR-0045 decisions 6 and 7, amending ADR-0036 decision 8 for the `unattended` level only.

### D5: Every architectural brief parks until a signal is designed

Asked, with the answer: the maintainer accepted the ADR-0045 amendment of 2026-11-24 to decision 8 (issue 636). Until #607 designs a signal that the issue asks for an action, every brief with `gate.architectural` true parks. ADR: ADR-0045 amendment of 2026-11-24 to decision 8.

### D6: Admission replaces brood strain approval and requires a passing readiness check

Asked, with the answer: the maintainer accepted ADR-0045 and its 2026-11-21 amendment excluding epics and requiring a passing readiness check. ADR: ADR-0045 decision 10 and its 2026-11-21 amendment, amending ADR-0026 for Lair strains.

### D7: Merges only through one merge lane and a script-computed auto tier

Asked, with the answer: the maintainer accepted ADR-0045 on 2026-11-21. ADR: ADR-0045 decision 12, under ADR-0044 decisions 17 to 20.

### D8: The auto-tier floor holds the design document folders

Asked, with the answer: the user's answer 2A of 2026-11-22 (merged design's review record, Decisions asked, Round 1 questions). Touches the merge path. ADR: ADR-0046, whose rule that a docs pull request never takes the Lair's auto tier this implements.

### D9: Per-platform strain containment hides the Lair's control folder

Asked, with the answer: the user's answer 1A of 2026-11-22 to the containment question, the answer A to the key-containment question, and the answer A to Q1 after integration review round 3 that split the mechanism into #646 (merged design's review record, Decisions asked). Touches a trust boundary. ADR: ADR-0045 amendment of 2026-11-22, the Lair's strains can read its key where no sandbox hides its processes.

### D10: One remediation run per pull request

Asked, with the answer: the user's answer A of 2026-11-22 at strain launch's design review round 5 (merged design, Decisions). No ADR: fails hard to reverse.

### D11: The circuit breaker counts failed, crashed, stalled, timed-out and invalid-result outcomes

Asked, with the answer: the user's answers of 2026-11-22, A to the stalled-outcome question and A to Q1 after integration review round 3 (merged design's review record, Decisions asked). ADR: ADR-0045 amendments of 2026-11-22, "more causes stop the Lair" and "the circuit breaker counts invalid results".

### D12: The decision digest is local, one file per run

Asked, with the answer: the user's answer "Go" to the restarted round 1 questions and A to the restarted round 3 advisory, both of 2026-11-22 (merged design's review record, Decisions asked). ADR: ADR-0045 amendment of 2026-11-22, the decision digest is a local item GitHub cannot give again.

### D13: The release train is settled before any parallel strain

Asked, with the answer: the maintainer accepted ADR-0045 on 2026-11-21; the fragment format, release cadence and release trigger are deferred with full scope to #647, which blocks #606. ADR: ADR-0045 decision 15.

### D14: The Lair runs only from a checkout that shares no git store with the user's

Asked, with the answer: the maintainer's answer B of 2026-11-24 to finding R1-T1, narrowed by the answer 1 of 2026-11-25 to a requirement whose mechanism #608 designs (merged design's review record, Decisions asked). No ADR: fails hard to reverse.

### D15: Run budgets of 6 hours and 80 work agent calls

Taken and listed for veto, under the user's standing rule (merged design's review record, Decisions asked, Second restart round 1 budget). Recommendation: strong, from 94 measured delivery runs. Touches: PRD scope. No ADR: fails hard to reverse.

### D16: The park key is a hash of the stop's identity fields

Taken and listed for veto (merged design, Decisions). Recommendation: strong. Touches: none. No ADR: fails hard to reverse.

### D17: The remediation step runs before the merge lane in each tick

Asked, with the answer: the user's answer A of 2026-11-22 at strain launch's design review round 7 (merged design, Decisions). No ADR: fails hard to reverse.

### D18: The threat model is parity with the maintainer's own session

Asked, with the answer: the maintainer's answer A of 2026-11-25 to the fifth re-review round 1 question (merged design's review record, Decisions asked). Touches a trust boundary. No ADR: fails hard to reverse.

## Verification strategy

The tests are the PRD's Testing Decisions, proved with the project's own validation, `bash tools/validate.sh --changed`:

- Engine tests for the unattended level, the park action, the park key and the settled-decisions launch input go in `tests/workflow-scripts/`.
- Shell-script tests are `tools/test_*.sh` suites registered in `tools/validate.sh`: `tools/test_merge_approved.sh` for the merge lane, and new suites for the strain launch and settings, the result schema, crash and stall detection, the auto-tier script, the park round trip, the controller tick and the containment probe.
- Controller tests use recorded GitHub states, with no live GitHub.
- The live smoke run is by hand, on a throwaway issue in this repository.
- Each part design's Verification strategy section names its own cases and suites.

Optional capabilities, each detected with its stated fallback:

- **Local review tool.** The auto tier requires local review not skipped. With no reviewer configured, local review is skipped with a warning and every Lair pull request goes to batch review.
- **Auto-merge.** With `HIVEMIND_AUTO_MERGE` unset, the Lair merges nothing and every pull request waits for the human.
- **Platform sandbox.** Where the probe `sandbox` cannot confirm containment, the Lair stops with cause `strain_env_preflight`.
- **claude-mem and CI** are not required; the merge lane reads the head's check rollup as `merge-approved.sh` reads it today.

## Seam order

1. #604, strain launch and settings, and strain result and liveness.
2. Then #607, the unattended level, and #605, the merge lane and auto tier.
3. Then #608, the controller tick and admission, and #606 after #605 and after #647 settles its decisions.
4. Then #609, #610 and #611, each depending on #608.
5. #612, parallel strains, after #606 and #608.

#646, the strain containment design issue, comes before #604, #608 and #612, which build and use its containment. Each edge is one native blocked-by link matching one `#N` ref in the blocked slice's `## Dependencies` section, except #605 after #604, which is build order only, and the links on #646 and #647, which are not Dependencies refs. #608's admission depends on #615's readiness check, which has landed.

## Open questions

None

## Amendments

None yet.
