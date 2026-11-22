# Solution design: Lair strain launch and containment

This is the solution design for issue #630, the strain launch and containment part of the Lair, epic #603. It links the [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md) and the parent [solution design](solution-design.md) rather than restating them, cites ADR-0045 as "ADR-0045 decision N", and adds only what they lack. For this scope it replaces these parts of the parent design:

- the Components "Strain launch and settings" and "Strain result and liveness";
- the governance side of the Component "Unattended autonomy level", and the launch side of the Component "Post-PR remediation strains";
- the Contracts "Strain result", "Lair-written settings" and "Settled decisions";
- the strain-containment paragraph of Trust boundaries;
- the strain-settings, result-file and idle-marker rows of State and ownership;
- the sentence of Lifecycle stage 1 that ends the session and removes the worktree after the branch is pushed;
- the Crash, Stall, `Stop` hook, `/exit` and Budget-overrun rows of Failure modes.

Every other part of the parent design stands. The design review is recorded in the [strain launch review record](strain-launch-review-record.md).

## Context and code truth

The design builds on this code, as it stands on trunk.

**Correction to the parent design.** Its Context section says `spawn-brood.sh` "has no way to write per-strain settings". That is wrong. Trunk `plugin/skills/spawn-brood/scripts/spawn-brood.sh`:

- writes a per-brood `.hivemind/broods/<brood-id>/strain-settings.json` holding only `permissions.allow`, one `Read(/<root>/**)` rule per plugin-root spelling that passes its charset gate;
- launches each strain as `claude --permission-mode auto --settings ../../../../.hivemind/broods/<brood-id>/strain-settings.json` (line 670), a path relative to the worktree, so the tmux command string holds only fixed literals and the asserted brood id (ADR-0010, amendment 2026-10-31);
- still copies the coordinator's `.claude/settings.local.json` into every strain worktree (source path at line 606, the copy at line 821), refusing a symlinked leaf;
- anchors on the caller's `git rev-parse --show-toplevel` (line 427) and puts each worktree at `<that top>/.claude/worktrees/<brood-id>/<short>` (line 485). Run from a linked worktree, that top is the linked worktree, not the main checkout;
- still starts each worktree detached, with `git worktree add --detach "$wt" "$base_commit"`, and creates no branch;
- still turns on remote control (`/rc <short>`) for every strain that started, through `plugin/skills/enable-brood-remote/scripts/rc-brood.sh`;
- writes `inputs.json` and `manifest.json` (manifest version 4) under `.hivemind/broods/<brood-id>/`, and `task.md` under the worktree's `.hivemind/brood/`, starting with the data-boundary preamble and then a YAML data block of `parent`, `strain`, `run`, `working_branch.base` and `task.description`;
- starts the tmux session with `tmux new-session -d -s <session> -c <worktree> "<launch command>"` (lines 933 to 934). tmux starts the command in its server's environment, not the caller's;
- generates the brood id itself (lines 341 to 343, with its comment block at lines 301 to 308), so no caller knows the worktree path before the script runs;
- writes the manifest only after Pass 3 has waited for each strain's started evidence (Pass 3 from line 1251, manifest emission from line 1321). The manifest's `worktree_path` is display-only (line 1358);
- exits 1 with live sessions when the manifest write fails, and prints them on a `recovery:` line (for example lines 1441, 1453 and 1461).

Other code this design relies on:

- `docs/adr/0010-permission-allowlist-posture.md`, amendment 2026-10-31, records the documented facts this design uses: `--settings` sits below managed settings and above local, project and user settings; deny and ask rules from any source win over an allow; and since Claude Code 2.1.211 a worktree session reads `.claude/settings.local.json` at the main checkout's root. A copy into the worktree therefore keeps nothing out.
- `plugin/skills/github-review-loop/scripts/merge-approved.sh` reads `MERGE_METHOD="${HIVEMIND_AUTO_MERGE:-}"` and reports `MERGE=off` when it is unset or empty (lines 229 to 233). Any value other than `merge`, `squash` or `rebase` prints `MERGE=skipped:bad-setting` and exits 0 (lines 234 to 237). It tests `HIVEMIND_AUTO_MERGE_ADMIN` with `-z` (line 426), so an empty value is off.
- `plugin/workflow-src/standard-delivery/main.js` reads the launch args `request`, `trunk`, `references`, `local_review`, `draft` and `decisions`, plus the pause keys `answers`, `build` and `reply`. "An autonomy key is never read": `run.level` is `resolveLevel(undefined, AUTONOMY_TABLE)`, the table's `default_level`, `high`. `decisions` is 1 to `maxDecisions()` (10) non-blank strings of at most `maxDecisionLength()` (2000) code points. There is no `branch` launch arg: the plan names the working branch.
- `plugin/workflow-src/pr-feedback-remediation/main.js` takes only `references`, naming exactly one pull request, and `trunk`. Its `run.level` is the table's `default_level`. Its facts step runs with the pull request as its one reference. It runs one `hivemind:github-reviewer` fix pass, then, after an escalation, a tail that pushes again through the pull request step (lines 5 to 10).
- `plugin/workflow-src/pr-feedback-remediation/fix.js` reads a `blocked` fix pass through `blocker_reason`, free text of at most 600 code points (line 155), and puts it in the stop cause (lines 272 to 273).
- `plugin/workflow-src/lib/decide.js` is pure, with no I/O. The levels are those of `plugin/references/decision-autonomy-table.json`: `high`, `balanced` and `low`, default `high`. Nothing under `plugin/workflow-src/` reads `process.env`, and per [P24](../../engineering-principles.md) a running workflow script cannot read files. So today the engine reads no process environment.
- `plugin/workflow-src/lib/facts.js` runs committed scripts through `hivemind:synapse` from a command block, and a file block's content is written as is. Its `--inputs` value class takes only `.hivemind/molt-inputs-<token>.json` and `.hivemind/pr-inputs-<token>.json` (line 304).
- The synapse runner gate. `plugin/governance/security-policy.md` (Synapse Runner Gate) knows five runner scripts (line 153) and two synapse Write kinds (line 161). `plugin/hooks/synapse-gate.sh` registers the five scripts as `add_gate_member` lines (lines 91 to 96) and passes the kinds `molt pr` to the inputs-path rule (line 402). That rule, `hivemind_inputs_path_problem` in `plugin/skills/_shared/containment.sh` (line 66), takes the kinds as arguments. `plugin/skills/_shared/settings-merge.sh`, which `seed-hive` runs, seeds `Edit(.hivemind/molt-inputs-*.json)` and `Edit(.hivemind/pr-inputs-*.json)` (lines 395 to 396). `tests/policy/safety-synapse-gate.json` pins the members in equal mode: one agent type and the five scripts. The gate denies a call from any agent that names a member script file but is not in that script's exact form (`plugin/hooks/synapse-gate.sh` line 11; `security-policy.md` line 159).
- `plugin/skills/gather-facts/scripts/gather-facts.sh`, step (7), reads for each `--ref` the issue or pull request title, body and author and every top-level comment with its body. Step (6) reads the branch's pull requests as number, state, URL, head commit and base only.
- `plugin/skills/github-review-loop/scripts/fetch-normalize.sh` reads review threads, reviews and top-level comments with each author's login and `__typename`. `reviewer-identity.jq` applies the Bot gate of ADR-0043. Its review records carry no body (lines 88 to 104), and its `ci-check-failure` records carry no author (lines 106 to 116). A review record carries its node `id` (line 97); a `ci-check-failure` record carries the check `name` (line 111).
- `plugin/skills/adaptation-cycle/scripts/run-review.sh` reports any other non-zero exit of the review tool as `skipped: tool-failed` (lines 498 to 506). ADR-0045 decision 12 merges unattended only when local review was not skipped (ADR-0045 line 69).
- `plugin/agents/github-reviewer.md` reads a `ci-check-failure` record's `description` as its body (line 64) and scans each candidate's body (line 66), fetching review bodies itself. Step 7 pushes its fix commit with `push-branch.sh` (line 76). Step 8 confirms a defer home with `gh issue view` (line 79).
- `plugin/agents/cerebrate.md`, `plugin/agents/drone.md` and `plugin/agents/changeling.md` list `WebSearch` and `WebFetch` among their tools.
- `plugin/skills/create-working-branch/scripts/create-working-branch.sh` switches onto an existing local branch with `git switch --no-guess <branch>` (lines 105 to 110). It refuses a dirty tree and a branch checked out in another worktree.
- `plugin/skills/open-plan-pr/scripts/open-plan-pr.sh` leaves a reused pull request's title, body and draft state unchanged (lines 48 and 148).
- `plugin/agents/overlord.md`: `## Engine` falls back to Instinct when a `standard-delivery` launch is refused or ends blocked, and a request routed to `pr-feedback-remediation` first checks out the pull request's head branch; `## Resume On Start` offers resume or start fresh; `## Review Remediation Posture` holds the default post-PR watch and its `HIVEMIND_SKIP_PR_WATCH` short-circuit; `## Brood Execution` gets the user's approval of the strain text before spawn, and its "Brood child" paragraph derives a fresh branch off `working_branch.base`.
- `plugin/governance/security-policy.md` (Brood Spawn Bypass-Mode Mitigation) names pre-spawn human approval as the injection gate for strain text. It also says a base's committed hooks, `.claude/` settings and `.mcp.json` servers run at child launch, before any permission check (line 33). `plugin/governance/decision-autonomy.md` (Tier A — Always Surface) lists brood strain approval, a tool call failed after retry exhaustion, a fact only the user holds and a question with no recommendation among the closed Ask Set.
- `plugin/hooks/hooks.json` holds one `PreToolUse` hook, `synapse-gate.sh` on `Bash|Write`. That gate exists to check the runner commands of `hivemind:synapse`, a workflow agent.
- No agent-call cap exists under `plugin/workflow-src/`.
- `tools/validate.sh --self-test` fails any `tools/*.sh` suite missing from `KNOWN_SUITES`. `tools/test_workflow_scripts.sh` runs every `tests/workflow-scripts/*.test.mjs`. `tests/workflow-scripts/overlord-contract.test.mjs` pins sentences of `plugin/agents/overlord.md`.
- Two sites push in a run. Both engines open the pull request through `runPullRequestStep` in `plugin/workflow-src/lib/pr.js`, whose header calls that runner the only push the workflow makes (line 55). That runner runs `plugin/skills/open-plan-pr/scripts/open-plan-pr.sh`, which runs `plugin/skills/push-branch/scripts/push-branch.sh` as a child with `--on-reject warn --no-upstream origin --expect-commit <commit>`. The `pr-feedback-remediation` fix pass is the second site: `hivemind:github-reviewer` step 7 runs `push-branch.sh` itself. So the header holds for `standard-delivery` only, and a remediation run with an escalation pushes twice.
- In upstream mode, `push-branch.sh` retries a non-fast-forward or fetch-first rejection once with `--force-with-lease` and no expected value (lines 441 to 445), so the lease is the clone's own remote-tracking ref. A fetch after the remote branch moved refreshes that ref, and the retry then overwrites the move.
- After a push in origin or explicit mode, `push-branch.sh` records `branch.<b>.remote` and `branch.<b>.merge`. Git config is shared by every worktree of the checkout, so while that record stands, a branch an earlier strain pushed is in upstream mode on a re-claim and on a remediation.
- In origin mode, `--on-reject warn` turns a rejection into exit 0 with the warning `push was rejected; the branch is not on its remote`. `open-plan-pr.sh` then goes on to the pull request create and its head check, and prints `pushed: no` before any later blocker. So the engine meets a moved branch only as a later pull request blocker, never as a named cause.
- `git push` documents `--force-with-lease=<refname>:<expect>`: the remote ref is updated only when its current value is `<expect>`, no remote-tracking branch is needed, and an empty `<expect>` means the ref must not exist yet. The git docs call this explicit form stable and every other lease form experimental.
- The NOT CHECKED note (b) of `push-branch.sh` (lines 125 to 128) rejects capturing the lease's expected value early, because that only narrows a window. That holds for the upstream-mode retry lease. It does not hold for a value the Lair captured once at claim, outside the push process: that value names the state the run started from, not a moment before the push. #604 updates the note.
- `plugin/governance/security-policy.md` (Shell Identifier Discipline), pinned by `tests/policy/safety-push-single-process.json`: a push runs in the same Bash call, or the same committed script, as every check on the ref it writes.
- `isTransientFailure` in `plugin/workflow-src/lib/stop.js` lists only network and HTTP failures.
- `isInputsRefusal` in `plugin/workflow-src/lib/pr.js` matches fixed blocker lines of `open-plan-pr.sh`, and its parity test in `tests/workflow-scripts/standard-delivery.test.mjs` pins it to the script.
- The pull request body's closing lines name only integers the plan check found among the launch references (`plugin/workflow-src/lib/pr.js` lines 100 to 104). A launch with `references: []` closes no issue.
- `tools/test_push_branch.sh` and `tools/test_open_plan_pr.sh` run the scripts for real, against local bare repositories as remotes.

## Components

### Strain launch and settings

Built by #604. The Lair starts each strain through `spawn-brood.sh`, one strain per brood, so the per-brood `strain-settings.json` is the strain's own settings file (ADR-0045 decision 4). The Lair calls the script directly, not through the overlord's brood gate.

- **Lair mode.** `spawn-brood.sh` gains one optional per-strain input, `lair_nonce`, an identifier, never a path. With it, the script derives the Lair strain record `.hivemind/lair/strains/<nonce>/` from the checkout root. It refuses a nonce whose `strain.json` is missing or whose `spawn.json` already exists. Then it:
  - creates the worktree detached at the record's start commit, never at `base`;
  - writes `spawn.json` in the strain record, before `tmux new-session`: the brood id, the strain short and the worktree path. The write uses noclobber, so a second spawn on one nonce fails;
  - writes `strain-settings.json` as the union of the plugin read rules, the Lair's settings fragment from the record, and the two parts only it can know, because they hold the worktree path: the liveness hooks and the deny rule `Edit(//<worktree>/.hivemind/lair/**)`;
  - does not copy the coordinator's `.claude/settings.local.json`;
  - writes a fixed Lair `task.md` description naming `.hivemind/lair/launch.json`, and copies the record's `launch.json` there, with the same leaf containment checks as `task.md`;
  - starts the session with an empty environment plus a fixed list of names (Contract "Strain environment"): `env -i ${HOME+HOME="$HOME"} ${PATH+PATH="$PATH"} ... claude --permission-mode auto --settings ../../../../.hivemind/broods/<brood-id>/strain-settings.json`. Each name is one `${NAME+NAME="$NAME"}` word, so a name unset in the tmux server's environment is not passed at all, never passed empty. tmux starts a command in its server's environment, so the list is applied in the command itself. The string still holds only fixed literals and the asserted brood id;
  - keeps remote control on, as for any strain.
- **Without `lair_nonce`** the script behaves exactly as today.
- **The settings fragment** is the Contract "Strain settings". It sets the merge keys to empty values, so they override the user, project and local scopes, and it holds the marker and the deny rules.
- **Environment preflight.** Built by #608. Before its first claim of a session, the Lair runs three probes under the same `env -i` name list a strain gets: `gh auth status`, `git ls-remote origin`, and one dry run of the local review tool a strain would pick (`HIVEMIND_LOCAL_REVIEWER` from the user's settings, else the `codex-plugin` preset) through `run-review.sh`. When a probe fails, or the review run reports any skip other than `no-reviewer` (`run-review.sh` line 262), the Lair claims nothing and stops with the named cause `strain_env_preflight` and the fixed probe name (`gh_auth`, `git_remote` or `local_review`). So a missing name stops the Lair once, visibly, instead of failing or skipping local review in every strain.
- **A failed spawn.** When `spawn-brood.sh` exits non-zero, the Lair reads `spawn.json` and kills the session `<brood-id>-<short>` if it is alive, before it reconciles the claim. So a spawn that failed after `tmux new-session` never leaves a live strain beside a second one.

### Launch inputs

Built by #604, with the level path in #607. The Lair writes every launch input. None is derived from the issue text by a model.

- The Lair writes `launch.json` (Contract "Launch file") in the strain record before spawn. Its `args` are exactly the `Workflow` launch args. The level is not a launch arg.
- The overlord of a verified strain launches the workflow `launch.json` names with its `args` verbatim, and nothing else.
- **The copy is checked, not trusted.** The engine writes the args it received to `.hivemind/lair-launch-inputs-<token>.json` through a synapse file block, and runs the fixed runner `lair-launch-check.sh --inputs <that path>`. The runner compares them as JSON values with the Lair's record copy, outside the worktree. A mismatch ends the run `failed` with cause `launch_mismatch` before any planner call.
- **The level reaches the engine by a path task text cannot set.** `HIVEMIND_LAIR_STRAIN` is set only by the Lair's settings file. `gather-facts.sh` reads it and prints a `lair_strain` routing line (`none`, `verified` or `unverified`) through the marker check (Contract "Marker check"). With `verified` and a matching launch check, the engine sets `run.level` to `unattended`. With `none` the level is today's default, and no extra agent call runs. With `unverified` the run ends blocked with cause `lair_marker_unverified`: a stray marker in an interactive session stops visibly and never selects unattended.
- **Facts come only from the captured issue text.** A delivery launch has `references: []`. The request is the issue title and body captured at claim (ADR-0045 decision 10). With a verified marker, `gather-facts.sh` refuses any `--trunk` or `--ref` word that differs from `launch.json` before its first GitHub call. So the delivery workflow makes no live read of the issue, its references or comments. A prompt-injected strain could still read them with the user's rights (Trust boundaries). Because the pull request names no issue, it closes none; the merge lane closes the issue (Contract "Assumptions about #631").
- **`decisions`** holds the settled decisions (Contract "Settled decisions"), absent when there are none. **`draft`** is `false` at every Lair launch. **`local_review`** is `true` at every Lair launch, so a skipped local review shows only as the engine's own skip.
- **Agent-call cap.** #607 owns it. At the `unattended` level the engine counts each agent call of the run. At `maxUnattendedAgentCalls()`, 80, it makes no further work call and ends the run `failed` with cause `agent_budget`. The calls a run's end needs are not counted: the cap always keeps back the record call and, for a park after commits, the park's pull request step with its one transient retry (`plugin/workflow-src/lib/pr.js` lines 63 to 64). So a run reaches at most 83 calls. A park reached before the cap still pushes its draft, and the record, with the decisions taken before the cap, still reaches the result.

### Start points

Built by #604, with re-claim in #609 and remediation in #610. Every worktree is created detached, and the run is told which existing branch to work on.

| Start | Worktree commit | Branch | Pre-image | Who checks |
| --- | --- | --- | --- | --- |
| First claim | the fetched trunk commit, `refs/remotes/origin/<trunk>` after `git fetch` | none: the plan names a fresh branch, as for any brood child | none: the branch must not exist on the remote | #608 |
| Re-claim | the parked head, recorded in the park marker from the parked result | `args.branch`, the parked branch | the parked head | #609 |
| Remediation | the pull request's head commit, read at dispatch | the pull request's head branch, recorded in `launch.json` `start.branch` | the pull request head read at dispatch | #610 |

The pre-image is the commit the remote branch held when the run started. It is the strain record's start commit, or none when the start kind is `first_claim`.

- **Start configuration check, an authority.** Before a re-claim or remediation launch, the Lair lists the paths the branch side changed: `git diff --name-only <merge base> <start commit>`, where the merge base is `git merge-base` of the fetched trunk commit and the start commit. When the two commits have no single merge base, the launch is refused. It refuses the launch when any listed path is under `.claude/`, is `.mcp.json`, or is under the git hooks folder that `core.hooksPath` names inside the checkout. Those files run at launch or at commit with the user's rights (`plugin/governance/security-policy.md` line 33), and only trunk's history is the user's. A path the branch did not change holds a copy from trunk's history, so a trunk-side settings edit after the fork refuses nothing. A refused re-claim gets `lair:handoff` with reason `start_config_changed`. A refused remediation routes the pull request to `lair:review` (#631), the remediation form of a handoff. The check reads two immutable commits, so no later move can race it. A first claim starts on trunk and needs no such check.
- **Moved-head check, a fail-fast with no authority.** Before a re-claim or remediation launch, the Lair fetches `origin/<branch>`. It launches only when the remote head equals the pre-image, the local `refs/heads/<branch>` is absent or equal to it, and no worktree has the branch checked out. When the local ref is absent, the Lair creates it at the pre-image with `git branch --no-track`. It never moves an existing ref; the local-ref and worktree conditions keep that rule. The remote-head comparison uses the same pre-image as the push, so it only saves a launch whose first push would end `start_moved`. The push, not this check, is the authority. No other comparison is part of this check. Each refusal has one effect:
  - re-claim, remote or local head other than the parked head: `lair:handoff` with reason `branch_moved`;
  - re-claim, the branch checked out in a kept worktree: not claimed, queue report reason `unpushed_work`, no new label;
  - remediation, any refusal: the pull request goes to `lair:review` (#631).
- **`args.branch`** is a new optional `standard-delivery` launch arg (#604). It must pass the identifier gate. When present, the plan's working branch must equal it, or the plan check refuses the plan, and `create-working-branch.sh` finds the run already on it and does not switch.
- **A first claim refuses an old local branch.** In Lair mode, with start kind `first_claim`, `create-working-branch.sh` refuses a branch that already exists locally, with a fixed blocker, instead of switching onto it. The run ends `failed`. The Lair also deletes a strain's local branch ref when it removes the worktree (Lifecycle step 5), so the refusal should not arise.
- **A re-claim or remediation strain's overlord** only switches onto `start.branch` with `git switch --no-guess` before launching, as `## Engine` already does for a remediation request (governance edit "Strain runs"). It makes no fetch and no head check after the switch, so the overlord never produces `start_moved`.
- **The push rule: the remote compares the expected commit at the write.** `push-branch.sh` gains a Lair mode, selected when the shared marker check (Contract "Marker check") prints `verified`; Contract "Strain push" gives the other modes. Both push sites of a run go through it: the pull request step's `open-plan-pr.sh` child call, in both engines, and `hivemind:github-reviewer` step 7, in the remediation fix pass. In Lair mode:
  - the expected commit is the last commit a Lair-mode push of this strain landed, read from the worktree's `.hivemind/lair/pushed`, or the pre-image when that file is absent;
  - it pushes with `git push --porcelain --force-with-lease=refs/heads/<b>:<expected> <remote> <sha>^{commit}:refs/heads/<b>`, with an empty `<expected>` on a first claim before any push;
  - it reads the pre-image from the verified strain record through the marker-check library, and refuses an expected value that is not a 40 or 64 digit hex object id, or a `pushed` value that does not descend from the pre-image. The value is never the remote-tracking ref. The push is never retried, and it behaves the same in upstream, origin and explicit mode;
  - before a push whose expected value is a commit, it refuses unless `git merge-base --is-ancestor <expected> <sha>` holds. Ancestry of two immutable commits cannot race. So the push can only create the branch, or fast-forward it from the strain's own last state, and never rewrites it. This refusal is a fault in the strain's own history, not a move of the remote, so it keeps the blocker `push was rejected` and never gives `start_moved`;
  - after the push lands, in the same process, it writes the pushed commit to `.hivemind/lair/pushed`. A failed write exits 1 with its own fixed blocker line, never the start-moved line. The file lives in the strain's worktree, so a new strain never inherits it;
  - it treats `--on-reject warn` as `block`;
  - a `[rejected]` summary on the destination ref (`stale info`, `non-fast-forward` or `fetch first`), and only that, exits 1 with the one fixed line `blocker: start moved: the push does not continue from the state this run started on`, and nothing on stdout. The line echoes no caller value;
  - `[remote rejected]`, the ancestry refusal and every other failure keep the blocker `push was rejected`;
  - a repeat push of an already pushed commit still exits 0, because the expected value is then that commit and the engine retries the pull request step (`plugin/workflow-src/lib/pr.js` lines 63 to 64 and 297; `plugin/workflow-src/pr-feedback-remediation/contract.js` PFR-24). A real-remote test pins it. When another writer moved the branch after this strain's last push, the next push refuses with the fixed line; the Lair's clean-up (Lifecycle step 5) decides from the remote, not from the engine record's `pushed` field.
- **Closed by construction.** The class made impossible is any remote state other than the strain's own last state at the write, whatever its direction, ancestry or timing, because the remote itself refuses it; every earlier check, the Lair's moved-head check included, is a fail-fast the push does not depend on.
- **The engine owns the mapping.** `plugin/workflow-src/lib/pr.js` gains `isStartMoved(stderr)` beside `isGateDenial` and `isInputsRefusal`, matching the fixed line. A blocked pull request relay that holds it ends the run blocked, and the engine record carries outcome `failed`, cause `start_moved` and `pushed` `no`. It is never retried as transient. A parity test pins the matcher to the script text. For the fix-pass push, the `blocked` exit of `plugin/workflow-src/pr-feedback-remediation/fix.js` gains a `push_blocker` field: the last `blocker:` line of a refused `push-branch.sh` call, verbatim, or null. The engine runs `isStartMoved` on it. A model relays that field, so it can be wrong; every failed remediation end has the same effect (Handling by start kind), so a wrong value changes only the cause the Lair records. `lair-result.sh` copies the cause from the engine record; the overlord writes none.
- **Handling by start kind.** On a re-claim the issue gets `lair:handoff` with reason `branch_moved` (#609). On a first claim the issue gets `lair:failed`, counted toward the circuit breaker (#608). On a remediation, every end other than `complete`, `start_moved` included, routes the pull request to `lair:review` (#610, #631); a crash, stall or budget overrun also counts toward the circuit breaker, as for a delivery strain. #610 dispatches no remediation on a pull request labeled `lair:review`. Each dispatch marker lists the finding keys it was dispatched for: a review record's node `id`, or a failed check's `name`. On one head, the Lair dispatches again only for a finding key no earlier dispatch marker on that head lists. So a tick never dispatches the same finding again, and a finding posted after a remediation that ended `complete` without a push still gets a strain.
- **Work kept.** A refused push leaves the strain's commits on the local branch in its worktree. Lifecycle step 5 keeps that worktree, since its head is not on the remote, and the queue report names it. Nothing is overwritten or lost.
- **Recorded residual: wasted run time.** Only the push sees a move made during the run, so a strain whose branch moved mid-run can spend up to its 6-hour budget before the push refuses.
  - Scope: the class "point-in-time start checks race with later branch moves", found at local review iterations 1, 3 and 4.
  - Bounded impact: nothing is overwritten, the commits are kept, and the user is told by the label.
  - Ground: a mid-run Lair poll would be one more check at a fixed time, which cannot be authoritative, and it would add a tick path and a session end. It is not designed. The decision was taken under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and is listed for veto.
- **A park after commits pushes.** At the `unattended` level, a run that parks with commits past the start commit runs the pull request step with `draft` true before it writes its record (#607). So the parked head is on the remote, the park record names the draft pull request, and the worktree is removed at clean-up. A refused push there ends the run `failed` with the push's cause, not `parked`.
- **A completed re-claim is marked ready.** A re-claim reuses the parked draft pull request, and `open-plan-pr.sh` leaves a reused pull request's draft state unchanged. After a `complete` re-claim result whose pull request is a draft, the Lair runs `gh pr ready` on it before the merge lane reads it (#609). If that fails, the pull request goes to `lair:review`.
- **Superseded design.** At claim the Lair records the review record's stamp blobs on fetched trunk as `design_stamps` in the claim marker, for an initiative slice only. When a re-claim finds other stamps, the parked work was built for an earlier design. The issue gets `lair:handoff` with reason `design_superseded`.
- **Unanswered park.** An issue relabeled `readiness:ready` while one of its open park keys has no admitted answer is not claimed. It is named in the queue report with reason `park_unanswered` and gets no new label, as for a failed readiness check.
- **Decisions too large.** A park record has one key, and a third park hands the issue off (ADR-0045 decision 7), so at most 2 settled decisions exist. The Lair still checks both limits before launch. More than 10 entries, or any entry over 2000 code points, means the issue is not claimed. It is named in the queue report with reason `too_many_decisions` or `decision_too_long` and gets no new label. The user can post a shorter answer. The Lair never truncates an answer.
- **A parked run with no commits** has no branch on the remote. The Lair deletes its local ref at clean-up, and its re-claim starts as a first claim.

### Strain result and liveness

Built by #604. ADR-0045 decision 5 holds: the strain's overlord runs one fixed script, `lair-result.sh`, that writes the result.

- **The engine writes its own record, through a separate script.** At every end of a run whose `lair_strain` line is `verified`, whatever its level, the engine runs `lair-record.sh --inputs .hivemind/lair-record-inputs-<token>.json` through a synapse file block. So `launch_mismatch`, which ends the run before the level is set, and `agent_budget` reach the record. The record holds the level, outcome, cause, pull request, branch, head, park record, the gates that held, and `decisions` built from the run's taken decisions (`run.taken`). The script checks it and writes `.hivemind/lair/record.json` in the worktree. It never writes the result.
- **Two scripts, one gate member.** `lair-record.sh` is a synapse runner gate member, with `--inputs` required. `lair-result.sh` takes no argument and is not a gate member, so the gate makes no decision on the overlord's call and normal permission flow applies. A no-argument call never meets the gate's exact-form deny, and synapse can never write the result.
- **Every ask parks.** At the `unattended` level the engine never pauses for a reply: every ask becomes a park it builds (ADR-0045 decision 6; governance edit "Tier A"). A pause that still reaches the overlord breaks that contract. The overlord sends no reply and ends as usual, and the result is `failed` with cause `no_engine_record`.
- **The overlord's call writes the result.** At run end the overlord runs `lair-result.sh` with no argument. The script runs the marker check first.
  - With `verified`, it reads the engine record, checks it against the schema, and writes `.hivemind/lair/result.json` once, through a temporary file and a rename. The result's `decisions` come only from the engine record, never from model prose.
  - With `verified` and no engine record, for example after a refused launch, the result is `failed` with cause `no_engine_record` and `decisions` null, never an empty list. So the digest shows the decisions as unknown, not as none.
  - With `unverified`, it ignores any engine record and writes `failed` with cause `lair_marker_unverified` and `decisions` null.
  - A result with no engine record behind it sets `level`, `pr`, `branch`, `head`, `park`, `gates` and `decisions` to null. It reads no value from git or from model prose. The Lair's clean-up decides from the remote and the worktree, not from these fields.
- **The cause comes only from the engine record or the marker check.** `lair-result.sh` copies the record's cause, `start_moved` included, or writes `lair_marker_unverified` or `no_engine_record` itself. The overlord writes no cause.
- **Liveness files.** `spawn-brood.sh` adds two hooks to `strain-settings.json`, in exec form per ADR-0028, each a fixed `touch` of an absolute path in the strain's worktree:
  - a `PreToolUse` and `PostToolUse` hook with matcher `*` touches `.hivemind/lair/activity`;
  - a `Stop` hook touches `.hivemind/lair/idle`.
- **Run activity** is the activity file's modification time. Claude Code produces it on each tool call of the strain session. Plugin hooks firing on workflow agents' tool calls is what `synapse-gate.sh` already relies on; #604 verifies the same for a `--settings` hook.
- **Session end** is in Lifecycle. It never waits on a push.

### Unattended governance edits

Each edit below is a governance or agent text change that unattended runs need. The slice named makes it. Each changed load-bearing section gets its consumer pin, per CLAUDE.md.

| Edit | Target | Slice |
| --- | --- | --- |
| **Tier A.** In a verified Lair strain nothing is surfaced: every ask becomes a park the engine builds. A safety rail (Destructive Fix Gate, a direct trunk commit or push, injection-suspect content) and an external effect (an action whose effect lands outside the strain's branch and pull request) become `approval` parks. A fact only the user holds becomes a `fact` park. A question with no recommendation, a tool call failed after retries, and a tripped gate other than the safety clause whose action has no external effect become `decision` parks. The router `ambiguous` outcome and the resume and version-skew doors do not arise, because the launch names the workflow and each strain is a fresh session. A strain makes no merge recommendation. | `plugin/governance/decision-autonomy.md` (Tier A — Always Surface) | #607 |
| **user_gate.** A verified strain never enters the state machine. A refused or blocked engine launch ends the strain `failed` with no Instinct fallback, so no `user_gate` state is reached. The Instinct ask and the Question gate are skipped the same way. | `plugin/agents/overlord.md` (`## Engine`, `## Instinct`, `## Workflow State Execution` step 5, `### Stop Conditions`) | #607 |
| **Pre-spawn approval.** For a Lair strain, admission (ADR-0045 decision 10 and its amendment) and the pre-spawn injection scan replace the human approval of strain text. The scan covers every text of the launch args, the settled decisions included. It runs on #632's scan executor. This is a seam with #632. | `plugin/governance/security-policy.md` (Brood Spawn Bypass-Mode Mitigation), `plugin/agents/overlord.md` (`## Brood Execution`), the brood strain approval bullet of `plugin/governance/decision-autonomy.md` (Tier A — Always Surface) | #608 |
| **Strain runs.** A brood child runs `lair-strain-check.sh` before its first launch. With `verified` it switches onto `start.branch` with `git switch --no-guess` when `launch.json` names one, launches from `launch.json` verbatim, runs no Resume On Start question, no post-PR watch and no Instinct fallback, sends no reply to a pause, and ends by running `lair-result.sh` with no argument. With `unverified` it launches nothing and runs `lair-result.sh` with no argument. | `plugin/agents/overlord.md` (`## Engine`, `## Resume On Start`, `## Review Remediation Posture`, `## Brood Execution`) | #607 |
| **Lair strain branch.** A Lair strain with `args.branch` works on that branch, not on a fresh one. | `plugin/agents/overlord.md` (`## Brood Execution`, "Brood child") | #604 |
| **Strain settings.** The Lair settings content beside the plugin read rule. | `plugin/governance/security-policy.md` (Brood Spawn Bypass-Mode Mitigation, "Strain plugin-read grant") | #604 |
| **Synapse runner gate.** Two more runner scripts, `lair-launch-check.sh` and `lair-record.sh`, each at `skills/<name>/scripts/<name>.sh` with `--inputs` required, and two more synapse Write kinds, `.hivemind/lair-launch-inputs-<token>.json` and `.hivemind/lair-record-inputs-<token>.json`. The five-script and two-kind statements, and the "What the gate does not guard" counts, become seven and four. `lair-result.sh` is not a member. | `plugin/governance/security-policy.md` (Synapse Runner Gate); `plugin/agents/synapse.md` (the inputs-file forms); `plugin/hooks/synapse-gate.sh` (the `add_gate_member` lines and the Write kinds); `plugin/skills/_shared/containment.sh` (the documented kinds); `plugin/workflow-src/lib/facts.js` (the `--inputs` class); `plugin/skills/_shared/settings-merge.sh` (the seeded `Edit(.hivemind/...)` rules); `tests/policy/safety-synapse-gate.json` (the equal-mode set) | #604 |
| **Remediation fix pass.** `hivemind:github-reviewer` reads a candidate's body from its `fetch-normalize.sh` record when the record carries `body`, and fetches none. A refused push at step 7 also sets `push_blocker` to the script's last `blocker:` line. At the `unattended` level the fix-pass prompt carries a fixed engine line: a finding left unfixed goes only to a recorded-residual home, and a finding that needs a tracked issue returns `user-input-required`, which parks. | `plugin/agents/github-reviewer.md` (steps 3, 7 and 8), `plugin/governance/remediation-doctrine.md` (Defer-with-Scope) | #610 |

### Remediation strain launch

Built by #610. A remediation strain uses the same settings, marker, liveness and result contract as a delivery strain (ADR-0045 decision 13). Its start point is under Start points.

- **Its args** are `{"references": [<pr>], "trunk": "<trunk>"}`, the only keys `pr-feedback-remediation` takes. `launch.json` also carries `start.branch` and `review_authors`.
- **Its claim.** A remediation has no issue claim. The Lair writes a dispatch marker comment on the pull request instead, and it plays the claim marker's part: it holds the remediation's own `claim_nonce`, `dispatched_at`, the head read at dispatch and the finding keys it was dispatched for (Start points, "Handling by start kind"), and at run end the `outcome` and `ended_at`. The nonce keys the strain record. A crash outcome goes into it. `dispatched_at` starts the 6-hour budget. #632 owns its form and write order, as for the claim marker.
- **Review text that reaches it:**
  - through the facts step, with the pull request as its one reference: the pull request's title, body and top-level comments;
  - through the fix pass and `fetch-normalize.sh`: review threads, reviews, top-level comments and CI check results.
- **The author filter.** With a verified marker, `gather-facts.sh` and `fetch-normalize.sh` drop every text whose author is neither an in-scope reviewer Bot (ADR-0043's Bot gate in `reviewer-identity.jq`) nor a login in `launch.json` `review_authors`. They report the count dropped. The Lair fills `review_authors` at dispatch with the users with write permission who wrote review text. An in-scope Bot passes without a write-permission check: a Bot account is a GitHub App, and only an administrator can install an app on the repository, so an in-scope Bot counts as trusted, as a user with write permission does. `github-actions[bot]` is in scope only when listed (ADR-0043). Comments by other users without write permission therefore never reach the strain through its workflow. This Bot exception needs the PRD and ADR-0045 wording of changes 4 and 5 below.
- **CI records pass the filter.** A `ci-check-failure` record has no author. It passes, because a check run comes from a GitHub App an administrator installed and a commit status needs write access. Its `description` is still external content and is scanned.
- **Bodies come from the filter.** With a verified marker, `fetch-normalize.sh` adds each passing review record's `body`, so `hivemind:github-reviewer` reads no review text the filter did not pass. The strain's deny rules on `gh api` and `gh pr view --comments` block the reviewer's own unfiltered reads.
- **Scanning.** Every remaining text is external content. The facts-step injection scan of `lib/facts.js` runs on the facts texts before the fix pass. The `hivemind:github-reviewer` classifies each finding per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Injection-Suspect Classification). An injection-suspect verdict ends the run as an `approval` park. The Lair then routes the pull request to `lair:review` (#631).
- **Deferring.** `gh issue view` and `gh issue create` are denied in a strain, so a remediation strain cannot confirm or file an issue home. It defers only to a recorded-residual home (governance edit "Remediation fix pass").

## State and ownership

GitHub alone is authoritative (ADR-0045 decision 2). These rows replace the parent design's strain-settings, result-file and idle-marker rows and add the files this design and `spawn-brood.sh` write. Paths under `.hivemind/` are in the Lair's checkout unless they say worktree.

| State | Writer | Readers | Authoritative |
| --- | --- | --- | --- |
| Lair strain record `.hivemind/lair/strains/<nonce>/strain.json`: nonce, issue or pull request, start kind, start commit and branch | Lair, before spawn | `spawn-brood.sh`, the marker check, Lair | no; rebuilt from the claim |
| Spawn record `.hivemind/lair/strains/<nonce>/spawn.json`: brood id, strain short, worktree path | `spawn-brood.sh`, before `tmux new-session`, once | the marker check, Lair | no |
| Launch file `.hivemind/lair/strains/<nonce>/launch.json` | Lair, before spawn | `spawn-brood.sh`, `lair-launch-check.sh`, `gather-facts.sh`, `fetch-normalize.sh` | no; rebuilt from the claim |
| Settings fragment `.hivemind/lair/strains/<nonce>/settings.json` | Lair, before spawn | `spawn-brood.sh` | no |
| Remediation dispatch marker comment on the pull request | Lair, at dispatch, updated with the outcome at run end | Lair (budget, crash outcome, repeat guard) | yes |
| `.hivemind/broods/<brood-id>/inputs.json` | `spawn-brood.sh` | record only | no |
| `.hivemind/broods/<brood-id>/manifest.json` | `spawn-brood.sh` | Lair and `brood-status`, through `brood-state.sh` | no |
| `.hivemind/broods/<brood-id>/strain-settings.json`: plugin read rules, the fragment, the liveness hooks and the worktree deny rule | `spawn-brood.sh` | Claude Code in the strain session, the marker check | no |
| Worktree `.claude/worktrees/<brood-id>/<short>/` | `spawn-brood.sh` creates it; the strain commits in it; the Lair removes it | strain, Lair | no; the pushed branch is |
| Local branch ref `refs/heads/<branch>` of a Lair strain | the Lair creates it for a re-claim or remediation; the run creates it on a first claim; the Lair deletes it when it removes the worktree | strain, Lair | no |
| Worktree `.hivemind/brood/task.md` | `spawn-brood.sh` | the strain's overlord | no |
| Worktree `.hivemind/lair/launch.json`, a copy | `spawn-brood.sh` | the strain's overlord, the marker check | no; the record copy is checked |
| tmux session `<brood-id>-<short>` | `spawn-brood.sh` starts it; the Lair ends it | Lair, `brood-status`, the user | no |
| Worktree `.hivemind/lair/activity` | the strain's `PreToolUse` and `PostToolUse` hooks | Lair | no |
| Worktree `.hivemind/lair/idle` | the strain's `Stop` hook | Lair | no |
| Worktree `.hivemind/lair/pushed`, the last commit a Lair-mode push landed | `push-branch.sh` in Lair mode | `push-branch.sh` in Lair mode | no; the remote branch is |
| Worktree `.hivemind/lair/record.json`, the engine record | the engine, through `lair-record.sh` | `lair-result.sh` | no |
| Worktree `.hivemind/lair/result.json` | `lair-result.sh`, on the overlord's call | Lair | no; the Lair turns it into labels and markers |
| Main checkout `.claude/settings.local.json` and every `.claude/settings*.json` | the user | Claude Code, the merge lane (#631) | the user's; a strain is denied writes |

## Contracts and seams

Fields and seams only. Each slice builds the code.

- **Launch file.** `schema` (`lair-launch/1`), `claim_nonce`, `workflow` (`standard-delivery` or `pr-feedback-remediation`), `start` (`kind`: `first_claim`, `re_claim` or `remediation`; `commit`; `branch` or null), `args` (exactly the `Workflow` launch args), `review_authors` (a list of logins; empty outside remediation). Delivery `args`: `request` (the captured title, a blank line, then the captured body), `trunk`, `references` (`[]`), `local_review` (`true`), `draft` (`false`), `decisions` when any, `branch` on a re-claim. Remediation `args`: `references` (`[<pr>]`) and `trunk`.
- **Strain settings,** the fragment the Lair writes.
  - `env`: `HIVEMIND_LAIR_STRAIN` = `v1:<claim nonce>:unattended`; `HIVEMIND_AUTO_MERGE` = `""`; `HIVEMIND_AUTO_MERGE_ADMIN` = `""`; `HIVEMIND_SKIP_PR_WATCH` = `"1"`; `HIVEMIND_ENABLE_DECISION_REPORT` = `""`.
  - `permissions.deny`: `Bash(gh pr merge *)`, `Bash(gh pr edit *)`, `Bash(gh pr close *)`, `Bash(gh pr view *--comments*)`, `Bash(gh issue create *)`, `Bash(gh issue edit *)`, `Bash(gh issue comment *)`, `Bash(gh issue close *)`, `Bash(gh issue reopen *)`, `Bash(gh issue view *)`, `Bash(gh label *)`, `Bash(gh api *)`, `Bash(gh search *)`, `Bash(*merge-approved.sh*)`, `WebFetch`, `WebSearch`, `Edit(//**/.claude/settings*.json)`, and `Edit(//<Lair checkout>/.hivemind/lair/**)` and `Edit(//<Lair checkout>/.hivemind/broods/**)` with the absolute checkout path behind the same charset gate as the read rule.
  - `spawn-brood.sh` adds the liveness hooks (Strain result and liveness) and `Edit(//<worktree>/.hivemind/lair/**)`, with the worktree path behind the same charset gate.
  - Deny rules match the Bash command a model writes, not the commands a committed script runs. So the skill scripts still reach GitHub. The agents' own direct calls do match: `hivemind:github-reviewer`'s body read and defer check are moved to a script or forbidden in a strain (Remediation strain launch).
  - #604 verifies the rule forms, the empty-value override and the hooks headlessly and records them in an ADR-0010 amendment, as ADR-0010's issue 455 check did.
  - **Fallback if an empty value does not override.** The fragment sets `HIVEMIND_AUTO_MERGE` to `off` instead. `merge-approved.sh` reads it as `MERGE=skipped:bad-setting` and does not merge, and `HIVEMIND_AUTO_MERGE_ADMIN` matters only after a merge attempt.
- **Strain environment.** This is exactly what the strain holds, for #632's marker rule to be judged against:
  - the launch command starts from an empty environment (`env -i`) and passes only these names, each as a `${NAME+NAME="$NAME"}` word, so only when set in the tmux server's environment:
    - session: `HOME`, `PATH`, `USER`, `SHELL`, `TERM`, `LANG`, `TMPDIR`, `XDG_CONFIG_HOME` and `XDG_RUNTIME_DIR`;
    - credentials and config: `GH_TOKEN`, `GITHUB_TOKEN`, `GH_HOST`, `GH_CONFIG_DIR`, `SSH_AUTH_SOCK`, `DBUS_SESSION_BUS_ADDRESS` (the keyring `gh` and git credential helpers use), `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` and `CLAUDE_CONFIG_DIR`;
    - network: `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`, `https_proxy`, `http_proxy`, `no_proxy`, `SSL_CERT_FILE`, `SSL_CERT_DIR` and `NODE_EXTRA_CA_CERTS`;
    - local review tool: `OPENAI_API_KEY` and `CODEX_HOME`.

    #604's headless check confirms a strain can start, push, call GitHub and run the configured local review tool with this list. The Lair's environment preflight (Strain launch and settings) checks the same on the user's machine at each session start. A name the check or the preflight finds missing is added by a dated amendment here, never by a wildcard;
  - then the settings `env` of the user, project and local scopes, with the five keys above taken from the Lair's file, which sits above them;
  - so other `HIVEMIND_*` keys, such as `HIVEMIND_LOCAL_REVIEWER`, are as the user set them in settings;
  - the user's GitHub credentials, as for any session (ADR-0045 decision 9);
  - its own claim nonce: in the marker, the settings file, the strain record, the spawn record, both launch file copies, the engine record and the result.

  No other claim's nonce and no Lair secret is in its environment, its settings or its worktree. The strain can still read any file the user can, the Lair's state folder and other strains' records included.
- **Marker check,** one shared library, `plugin/skills/_shared/lair-marker.sh`, used by `gather-facts.sh`, `fetch-normalize.sh`, `create-working-branch.sh`, `push-branch.sh`, `lair-strain-check.sh`, `lair-launch-check.sh`, `lair-record.sh` and `lair-result.sh`.
  - **The Lair checkout** is the top `spawn-brood.sh` anchored on: the caller's `git rev-parse --show-toplevel`, four path levels up (`.claude/worktrees/<brood-id>/<short>`). It must report the same `git rev-parse --git-common-dir` as the caller. So the check holds whether the Lair runs in the main checkout or in a linked worktree.
  - It prints `none` when `HIVEMIND_LAIR_STRAIN` is unset or empty and the caller's `git rev-parse --show-toplevel` holds no `.hivemind/lair/launch.json`. With that file present and no marker, it prints `unverified`, so a marker that failed to reach a workflow agent's Bash fails closed, never as today's behavior.
  - It prints `verified` only when all of these hold, and `unverified` otherwise:
    - the value matches `^v1:[0-9a-f]{32}:unattended$`;
    - the strain record and spawn record for that nonce exist as contained regular files under the Lair checkout's `.hivemind/lair/strains/<nonce>/`;
    - the spawn record's brood `strain-settings.json` holds an `env.HIVEMIND_LAIR_STRAIN` byte-equal to the value;
    - `<Lair checkout>/.claude/worktrees/<brood-id>/<short>`, built from the spawn record's brood id and short, equals the caller's `git rev-parse --show-toplevel`.

  The check reads no manifest, so it passes before `spawn-brood.sh` has written one. A marker set in user, project or local settings, or one copied from another strain, fails a check. That is how a Lair-written marker is told from a stray or mistaken one. The check reads files a strain can rewrite with the user's rights, so it does not authenticate a marker against a prompt-injected strain; that is the named residual under Trust boundaries.

  For a verified marker, the library also hands the record's start kind and start commit to `push-branch.sh` and `create-working-branch.sh`, read in the same process as the write. No flag of the library or its callers changes. The new output lines are the `lair_strain` routing line of `gather-facts.sh`, the start-moved and `pushed`-write blocker lines of `push-branch.sh`, and the first-claim blocker line of `create-working-branch.sh`.
- **Strain push.** `push-branch.sh` selects its mode from the marker check: `verified` is Lair mode, whose push rule is under Start points; `none` is today's behavior byte for byte; `unverified` is a blocker before any push. Its flags are unchanged, and `open-plan-pr.sh` still passes `--on-reject warn --no-upstream origin --expect-commit <commit>`. Lair mode adds the fixed `blocker: start moved: the push does not continue from the state this run started on`, with nothing on stdout, and keeps `.hivemind/lair/pushed`. The engine alone maps that line to cause `start_moved`, through `isStartMoved` in `plugin/workflow-src/lib/pr.js`.
- **Strain result.** `schema` (`lair-result/1`), `claim_nonce`, `workflow`, `level` (as the engine record shows it), `outcome` (`complete`, `parked`, `blocked` or `failed`), `cause` (null or a code such as `launch_mismatch`, `start_moved` (produced only by the engine), `lair_marker_unverified`, `agent_budget`, `no_engine_record`), `pr` (number or null), `branch`, `head` (commit), `park` (a park record as in the parent design, or null), `gates` (each configured gate and whether it held or was skipped, local review included), `decisions` (each with its key, choice and reason, from the engine record; null when there is no engine record). The schema allows a null `level`, `branch`, `head`, `gates` or `decisions` only in a result with no engine record: outcome `failed`, cause `no_engine_record` or `lair_marker_unverified`, and `pr` and `park` null too. Every other result takes these fields from the engine record. The Lair treats a result whose `level` is not `unattended` as `failed`.
- **Settled decisions.** They enter the run through the `decisions` launch arg. The Lair alone builds each entry from an admitted answer, in this form:

  ```text
  Question <key>: <question, as parked>
  Answer: <option id and label, or the fact text>
  Provenance: answered by <login> in <answer comment URL>, to the park marker <park marker URL>.
  ```

  The question and option text was written by an earlier strain, so it is untrusted. The pre-spawn injection scan covers it with the rest of the launch args. Each entry is at most 2000 code points and there are at most 10. Over either limit, the issue is not claimed (Start points).
- **Assumptions about #631, the merge lane.**
  - The Lair reads the merge settings from the user's settings files and its own environment, never from a strain's settings, environment or files. The strain's empty merge keys therefore never stop the Lair merging.
  - #631 checks the result's `pr`, `branch` and `head` against GitHub. This design guarantees only that the result is schema-checked and that `decisions` and `gates` come from the engine record.
  - The protected-path floor holds `.claude/**`, so a strain's commit to a committed settings file never merges in the auto tier.
  - #631 routes to `lair:review` a remediation that ended other than `complete` or was refused before launch, and a pull request whose head moved.
  - When the merge lane sees a Lair pull request merged, it closes the issue as well as labeling it `readiness:done`, since the pull request names no issue to close.
- **Assumptions about #632, claim integrity.**
  - A claim nonce is not a secret from a strain. #632's marker rule may rely on the nonce being unknown to GitHub users without write permission. It must not rely on it being unknown to a strain. If #632 needs an authenticator a strain cannot forge, it uses a value no strain receives.
  - No secret sits in the Lair's environment or in a file the user's account can read. A strain runs as the same user and can read every such file, and a strain can change the tmux global environment the Lair may later inherit.
  - #632 owns the claim nonce's form. This design assumes 32 lowercase hex digits, so the nonce can sit in a path and in the marker.
  - #632 owns the claim marker form, the remediation dispatch marker form and the `body_sha256` form. `args.request` is built from the same captured bytes the hash covers.
  - The claim marker carries `design_stamps` for an initiative slice.
  - #632's scan executor runs the pre-spawn injection scan on every text of the launch args, the captured issue text and the settled decisions, before the Lair writes the launch file.
  - #632's claim write order and lock scope cover the strain record, launch file and settings fragment. They are written after the claim marker and labels, and a claim that stopped before spawn is reconciled by #632's rule.
- **Seam with #615.** The superseded-design check reads the review record's stamps on fetched trunk directly. It does not need more readiness-check output.

## Trust boundaries

Only a user with write permission steers the Lair, through the parent design's channels and one more:

- remote control on a Lair strain, turned on by `spawn-brood.sh` through `rc-brood.sh` (ADR-0027). Only the user's own Claude account holds it. Input typed there is the user's own and the Lair does not read it. A strain steered by hand still reports only through its result file.

**Strain containment.** This paragraph replaces the parent design's. The strain is untrusted after spawn.

- It starts from an empty environment plus a fixed list of names, so no merge key and no Lair variable reaches it from the Lair or the tmux server. It runs with both merge keys empty in settings that sit above the user, project and local scopes. Nothing it inherits from those scopes turns a merge on; managed settings are the named residual below.
- Its launch inputs are Lair-written and checked against the Lair's copy. Its level comes from the settings marker, which task text cannot set.
- Its branch's own configuration is never trusted. A re-claim or remediation start commit whose branch side changes `.claude/`, `.mcp.json` or the git hooks folder since its merge base with trunk is refused before launch (Start points), because those files run at launch and at commit.
- Through its workflow, a delivery strain reads no issue text but the capture, and a remediation strain reads review text only from in-scope Bots, trusted because only an administrator installs an app, write-access users and CI checks, scanned before use.
- **Untrusted channels a strain could open by itself**, each denied as a barrier: live issue and pull request reads (`gh issue view`, `gh pr view --comments`, `gh api`), `gh search`, and the `WebFetch` and `WebSearch` tools that `hivemind:cerebrate`, `hivemind:drone` and `hivemind:changeling` hold. Writes outside its branch and pull request (`gh issue create`, comments, labels, merges) are denied the same way.
- **The deny rules are a barrier against a strain that makes a mistake, not containment of a prompt-injected strain.** A Bash call can run `bash -c`, a script, `curl` or another interpreter that no deny rule matches. The strain runs with the user's GitHub credentials and can read any file the user can.
- **The workflow's push can only create the branch or fast-forward it from the strain's own last state.** Its lease is pinned to a value the Lair captured, or to the strain's own last landed push, never the clone's tracking ref (Start points). A push a strain runs by hand, outside the workflow, or a rewrite of its own record's pre-image or `pushed` file, stays inside the named residual "a prompt-injected strain holds the user's rights" below. No deny rule on force flags is added: a list of flags is a complete-the-known-set rule that another spelling escapes.
- **Named residual: a prompt-injected strain holds the user's rights.** It could merge, relabel, comment, admit or answer other issues, write the user's settings by a path no rule matches, or rewrite the Lair's strain records, so that a forged marker passes the marker check or another strain's result is replaced. What narrows it is upstream of the strain: admission, the pre-spawn injection scan, the captured text and the author filter. A dedicated identity (ADR-0045 decision 9) is the real fix and is deferred. This is the ADR-0045 residual of that name, as change 9 rewords it.
- **Named residual: the tmux global environment.** A strain can run `tmux set-environment -g`. The names the launch command passes, such as `PATH`, are read from that environment, so a strain could change them for later strains and for a restarted Lair. This sits inside the residual above. #632 keeps secrets out of the Lair's environment (Contracts and seams).
- **Named residual: a merge key exported from the user's shell profile** reaches the strain's Bash calls, because the shell is started from the profile. The merge keys belong in settings files (CLAUDE.md), and `merge-approved.sh` is reached only from the review watch, which a strain never runs.
- **Named residual: managed settings** sit above `--settings`, so an administrator's managed merge key would win.

## Lifecycle

A strain moves through these steps:

1. **Write.** After the claim marker and labels, or the remediation dispatch marker, the Lair writes the strain record, the launch file and the settings fragment, and checks the start point (Start points).
2. **Spawn.** The Lair calls `spawn-brood.sh` with `lair_nonce`. It creates the detached worktree, writes `spawn.json`, `strain-settings.json`, `task.md` and the launch copy, and starts the session from the fixed environment. If the script exits non-zero, the Lair kills any live session named in `spawn.json` before it reconciles the claim.
3. **Run.** The overlord checks the marker, switches onto `start.branch` when one is named, launches from `launch.json` verbatim, and the engine checks the copy and sets the level. The run delivers or remediates unattended, writes its engine record, and the overlord runs `lair-result.sh`.
4. **End.** The Lair ends the session when it reads a valid result, or on a crash, a stall or a budget overrun (Failure modes). It sends `/exit` to the pane, waits a 60-second grace period, then kills the session if it is still alive. It never waits on a push.
5. **Clean up.** After a fetch, when the worktree's head is on the remote, or no commit was made past the start commit, the Lair removes the worktree and deletes the strain's local branch ref. Otherwise it keeps the worktree and the ref, records `unpushed_head` in the claim outcome, and names it in the queue report until the user removes it. The queue report text gives the rescue step: the worktree holds `.hivemind/lair/launch.json`, so the plugin scripts fail closed there; delete that file, or push by hand. The Lair never pushes for a strain. A kept worktree holds the branch, so the issue is not re-claimed while it exists, with reason `unpushed_work`.

The three start points are first claim, re-claim and remediation, as under Start points.

## Existing-path coverage

- **Interactive standard-delivery and pr-feedback-remediation** are unchanged when `HIVEMIND_LAIR_STRAIN` is unset or empty and the checkout holds no `.hivemind/lair/launch.json`. `gather-facts.sh` prints `lair_strain: none`, the engine runs no launch check and writes no engine record, and the level is today's default.
- **A non-Lair brood**, a `spawn-brood.sh` call without `lair_nonce`, keeps today's behavior, the settings copy, the launch environment and fresh-branch rule included.
- **`merge-approved.sh`, the review watch and interactive auto-merge** are unchanged. The strain's empty merge keys apply only in the strain session.
- **The `branch` launch arg** is optional. Without it `standard-delivery` plans as today.
- **`push-branch.sh`, `open-plan-pr.sh` and `create-working-branch.sh`** are unchanged when the marker check prints `none`: the upstream-mode `--force-with-lease` retry, the `--on-reject warn` warning and the switch onto an existing branch stay as today.
- **`fetch-normalize.sh` and `hivemind:github-reviewer`** are unchanged when the marker check prints `none`: no record carries `body`, so the reviewer reads bodies as today, and the fix-pass prompt has no unattended line.
- **The synapse runner gate** keeps its five commands and two Write kinds as they are; the two new commands and kinds only add to the set.
- **The author filter** applies only with a verified marker.
- **The agent-call cap** applies only at the `unattended` level.

## Failure modes

These rows replace the parent design's Crash, Stall, `Stop` hook, `/exit` and Budget-overrun rows and add the launch failures. A row's effect on an issue applies to a delivery strain; a remediation strain's every failed end routes its pull request to `lair:review` (Start points, "Handling by start kind").

| Failure | Detection | Resulting state |
| --- | --- | --- |
| Crash | `tmux has-session -t =<session>` fails and there is no valid result file. | `lair:failed`; the outcome `crashed` goes into the claim marker, or the dispatch marker for a remediation, and counts toward the circuit breaker. A remediation's pull request goes to `lair:review`. |
| Invalid result | The result file fails the schema check, or its `claim_nonce` is not the claim's. | Treated as a crash. |
| Stall | The session is alive with no result, and either the idle marker is newer than the last activity and 5 minutes old, or the last activity is more than 30 minutes old. | The Lair ends the session (Lifecycle step 4); `lair:failed`, counted as a stall toward the circuit breaker. A remediation's pull request goes to `lair:review`. |
| A tool call that runs longer than 30 minutes | Looks like a stall by the activity rule. | Ended as a stall. Accepted: the window is a controller constant tuned in use. |
| The `Stop` hook does not fire while a workflow runs in the background | Found while building #604. | Fallback: the idle rule is off, and the activity rule and the wall-clock budget judge a stall. |
| Hooks from `--settings` do not fire on workflow agents' tool calls | Found while building #604. | Fallback: run activity cannot be observed, so both stall rules are off and the wall-clock budget alone ends a stalled run. |
| An empty `--settings` env value does not override a lower scope | #604's headless check. | Fallback: the fragment sets `HIVEMIND_AUTO_MERGE` to `off`, which `merge-approved.sh` reads as `MERGE=skipped:bad-setting` (Contract "Strain settings"). |
| The settings `env` does not reach a workflow agent's Bash | #604's headless check; at run time, the marker check sees `.hivemind/lair/launch.json` with no marker. | The marker check prints `unverified`, so every script fails closed: no Lair-mode push, no filter bypass. The run ends with cause `lair_marker_unverified`. |
| `/exit` sent through tmux does not end a session | The session is still alive after the 60-second grace period. | The Lair kills the tmux session, then cleans up as in Lifecycle step 5. |
| Budget overrun | Wall-clock time since the claim marker's `claimed_at`, or the dispatch marker's `dispatched_at`, exceeds 6 hours, or the engine's agent-call cap ends the run with cause `agent_budget`. | The Lair ends the session without waiting. The issue becomes `lair:failed` (timed out), or is parked when a parked result was written first. A timeout counts toward the circuit breaker. A remediation's pull request goes to `lair:review`. |
| Unpushed work at session end | The worktree's head is not on the remote after a fetch. | The worktree is kept and named in the queue report, with the rescue step: delete its `.hivemind/lair/launch.json`, or push by hand. The issue is not re-claimed while it exists. |
| Strain environment preflight fails | A probe fails under the `env -i` name list, or local review reports a skip other than `no-reviewer`. | The Lair claims nothing and stops with cause `strain_env_preflight` and the probe name. The user adds the missing name by a dated amendment, or fixes the machine, and restarts the Lair. |
| Start moved | Lair mode of `push-branch.sh` gets a `[rejected]` summary from the lease and prints its fixed blocker line (Start points); the engine matches that line with `isStartMoved`, from the pull request relay or the fix pass's `push_blocker`. | The result is `failed` with cause `start_moved`. Nothing more is pushed, and the commits stay in the kept worktree. The Lair handles it by start kind: `lair:handoff` with reason `branch_moved` on a re-claim, `lair:review` (#631) on a remediation, `lair:failed` counted toward the circuit breaker on a first claim. |
| Second push in one run | The fix pass pushed, then the remediation tail pushes. | The tail's lease expects the fix pass's landed commit from `.hivemind/lair/pushed`, so the push succeeds. No false `start_moved`. |
| Marker unverified | The marker check prints `unverified`. | The overlord launches nothing, or the engine ends blocked. `lair-result.sh` writes `failed` with cause `lair_marker_unverified`. In an interactive session the run stops with that cause and the user removes the stray marker. |
| Launch mismatch | `lair-launch-check.sh` finds the engine's args differ from the Lair's copy. | The run ends `failed` with cause `launch_mismatch` before any planner call. The engine record carries it. |
| A refused or blocked engine launch | The `Workflow` call is denied, or the run ends blocked before its record. | No Instinct fallback. `lair-result.sh` writes `failed` with cause `no_engine_record` and `decisions` null. |
| A pause reaches the overlord | The engine returned a question at the `unattended` level. | The overlord sends no reply. `lair-result.sh` finds no engine record and writes `failed` with cause `no_engine_record`. |
| Old local branch on a first claim | Lair mode of `create-working-branch.sh` finds the planned branch already exists locally. | The run ends `failed`; `lair:failed`. |
| Start configuration changed | The start configuration check finds a path under `.claude/`, `.mcp.json` or the git hooks folder that the branch side changed since its merge base with trunk, or finds no single merge base. | No strain starts. A re-claim gets `lair:handoff`, reason `start_config_changed`; a remediation's pull request goes to `lair:review`. |
| Moved head before a re-claim launch | The Lair's moved-head check finds the remote or local branch head differs from the pre-image, the parked head. | No strain starts; `lair:handoff`, reason `branch_moved`. |
| Branch held by a kept worktree before a re-claim launch | The moved-head check finds the branch checked out in a worktree. | No strain starts; not claimed, queue report reason `unpushed_work`, no new label. |
| Moved head before a remediation launch | The Lair's moved-head check (Start points) finds the remote head differs from the pre-image, the pull request head read at dispatch, or the local ref differs from it, or a worktree holds the branch. | No strain starts; the pull request goes to `lair:review` (#631). |
| Repeat remediation dispatch | A pull request labeled `lair:review`, or a head whose dispatch markers already list every current finding key. | No dispatch. A finding key no marker on that head lists gets one new dispatch. |
| A completed re-claim's pull request stays a draft | `gh pr ready` fails after a `complete` re-claim result. | The pull request goes to `lair:review`. |
| Superseded design on a re-claim | The review record stamps on trunk differ from the claim marker's `design_stamps`. | `lair:handoff`, reason `design_superseded`. |
| Unanswered park | An open park key has no admitted answer at re-admission. | Not claimed; queue report reason `park_unanswered`; no new label. |
| Decisions over the launch limits | More than 10 entries, or one over 2000 code points. | Not claimed; queue report reason `too_many_decisions` or `decision_too_long`; no new label. |
| A change that needs a `.claude` settings file | The deny rule refuses the edit. | The run parks or fails as the engine decides. Such an issue needs an interactive run. |
| Settings or launch write fails | `spawn-brood.sh` or the Lair cannot write a file, or the record is missing. | No session starts. The claim is reconciled by #632's rule for a claim that stopped before spawn. |
| `spawn-brood.sh` exits non-zero with a live session | Non-zero exit; `spawn.json` names the session. | The Lair kills the session before it reconciles, so no second strain starts beside it. |

## Decisions

A decision that is not ADR-worthy names the [P20](../../engineering-principles.md) condition it fails.

- **One settings file per strain, passed with `--settings`, with the merge keys empty, and a launch environment of fixed names only.** ADR-0045 decision 4, as reworded by change 1 below; ADR-0010 for the precedence.
- **Strains launch under `env -i` with a fixed list of names.** The list is `HOME`, `PATH`, `USER`, `SHELL`, `TERM`, `LANG`, `TMPDIR` and the named credential and config names (Contract "Strain environment"). The tmux global environment is a named residual, and #632 is told that no secret may sit in the Lair's environment or in same-user files. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **Deny rules are a barrier, not containment; the injected strain is a named residual.** ADR-0045 decision 4 as reworded by change 1, PRD line 64 as reworded by change 2, and the ADR-0045 residual as reworded by change 9.
- **The barrier list adds `gh issue create`, `gh pr view --comments`, `gh search`, `WebFetch` and `WebSearch`.** A remediation strain defers only to a recorded-residual home, never through `gh issue view`. ADR-0045 decision 4 ("nothing more"). Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **Three start points with detached worktrees.** ADR-0045 decision 3, as reworded by change 3, and PRD line 84 as reworded by change 6.
- **A re-claim or remediation start commit that changes `.claude/`, `.mcp.json` or committed hook files is refused before launch and handed off.** `plugin/governance/security-policy.md` (Brood Spawn Bypass-Mode Mitigation): broods are spawned only against trusted bases. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **A marker is verified against the Lair's record, the spawn record and the strain's worktree, and fails closed in a worktree that holds a launch file.** Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The level reaches the engine through the marker, read by `gather-facts.sh`, and the engine checks the launch args against the Lair's copy.** ADR-0045 decision 6 ("never by task text"). The mechanism is not ADR-worthy: fails P20's hard-to-reverse condition. #607 records it in an ADR-0037 amendment, because it changes ADR-0037's "an autonomy key is never read".
- **Every ask an unattended run still raises becomes a park the engine builds, not a failed result; an external effect is an approval park.** ADR-0045 decisions 6 and 7. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **The synapse runner gate grows by two runner scripts and two Write kinds.** The edits are named in the governance edit "Synapse runner gate": `plugin/governance/security-policy.md` (Synapse Runner Gate), `plugin/agents/synapse.md`, `plugin/skills/_shared/containment.sh`, the Write kinds of `plugin/hooks/synapse-gate.sh`, the `--inputs` class of `plugin/workflow-src/lib/facts.js`, the seed-hive rules in `plugin/skills/_shared/settings-merge.sh`, and `tests/policy/safety-synapse-gate.json`. This widens the surface synapse runs with no prompt, and the gate's cross-script residual covers seven commands instead of five. ADR-0037 and ADR-0040 hold the synapse runner model. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **A delivery strain reads no issue text but the capture, and `gather-facts.sh` refuses refs the launch file does not name.** ADR-0045 decision 10.
- **A remediation strain's review text is filtered to in-scope Bots, write-access users and CI checks, and its bodies come from the filter.** Extends ADR-0045 decision 11's rule on outsiders to review text, with the in-scope Bot exception that change 5 adds to decision 11 and change 4 to the PRD. The filter mechanism is not ADR-worthy: fails P20's hard-to-reverse condition.
- **The result's decisions and gates come from the engine record, written at every verified end with the end's calls kept back.** Keeps ADR-0045 decision 5's one fixed script. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The engine record has its own script, `lair-record.sh`, the one gate member; the overlord's `lair-result.sh` stays outside the synapse runner gate.** The other option, an exact form with `--inputs` optional, would let synapse write the result early, and the overlord's later write-once call would then fail. The split closes that by construction. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **The agent-call cap keeps back a park's pull request step and its one transient retry, beside the record call.** The other option, ending a park past the cap as `failed` with cause `agent_budget`, would keep the work only in a kept worktree. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **A result with no engine record holds nulls, never git-read values.** The schema allows those nulls only with causes `no_engine_record` and `lair_marker_unverified`. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **The remediation repeat guard is keyed on the head and the finding keys.** A dispatch marker lists its finding keys, and a key no marker on that head lists gets one new dispatch. The other option, routing new findings after a `complete` dispatch to `lair:review`, would skip ADR-0045 decision 13's dispatch for review findings. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **The moved-head check before a remediation launch is the one check under Start points.** It compares the remote head and the local ref with the pre-image, and has no comparison with the last result's head. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The start configuration check diffs the branch side only, from the merge base.** A trunk-side settings edit after the fork refuses nothing, and no single merge base refuses the launch. The other option, accepting the over-refusal of a two-tree diff, would hand off every parked issue after a trunk settings edit. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **Strain environment names pass only when set, the list adds keyring, XDG, proxy, CA and local-review names, and the Lair runs an environment preflight.** The `${NAME+NAME="$NAME"}` word stays a fixed literal in the command string. The other option, building the argv in `spawn-brood.sh`, would put caller values in the tmux command string. The preflight stops the Lair once with a named cause instead of failing or skipping local review in every strain. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **The Lair checkout is the strain's top four path levels up, with the same git common dir.** The other option, requiring the Lair to run in the main checkout, would add a rule `spawn-brood.sh` does not have. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken by the run under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **A launch file with no marker fails closed, and the PRD's "marker absent" test line names that exception.** The user chose option A on 2026-11-22: change 10 below, and the rescue step in the `unpushed_work` queue report text.
- **Run activity is the hook-touched activity file; stall windows of 5 minutes idle and 30 minutes inactive; a 6-hour wall-clock budget; an agent-call cap of 80 owned by #607.** ADR-0045 decision 17. The values are not ADR-worthy: each fails P20's hard-to-reverse condition.
- **Session end never waits on a push; unpushed work is kept and reported.** Not ADR-worthy: fails P20's hard-to-reverse condition.
- **A moved head or a superseded design hands the issue off; an unanswered park or over-limit decisions leave it unclaimed with no new label.** Extends ADR-0045 decisions 7 and 11 and the 2026-11-21 amendment's no-label rule. Not ADR-worthy: each fails P20's hard-to-reverse condition.
- **The strain's push is keyed on the remote branch's expected commit, which the remote compares at the write.** The rule is under Start points: an explicit lease on the pre-image the Lair captured, advanced to each commit the strain's own Lair-mode push landed; an ancestry check so the push never rewrites the branch; and one fixed blocker line that the engine alone maps to `start_moved`. The Lair's moved-head check is a hint, and the overlord makes no start check. This reverses this design's earlier rule of an unforced push keyed on fast-forward acceptance, which accepted a move the strain had fetched and merged, a rewound remote and a first-claim branch already at an ancestor. ADR-0045 decision 3 (the start points) and decision 4 (a strain may push its own branch, nothing more) are the context. Not ADR-worthy: fails P20's hard-to-reverse condition. Taken under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal), a strong recommendation with a clean gate, and listed for veto.
- **No mid-run poll of the remote branch is designed; wasted run time after a mid-run move is a recorded residual (Start points).** Not ADR-worthy: fails P20's hard-to-reverse condition. Taken under `plugin/governance/decision-autonomy.md` (Tier B — Auto-Decide and Journal) and listed for veto.
- **Remote control stays on for Lair strains, as a channel only the user's account holds.** ADR-0027. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The ADR-0045 residual "A prompt-injected strain holds the user's rights" is reworded by change 9.** With changes 1 and 9 applied, decision 4 and the residual both call the settings a barrier, and the residual names the risk this design keeps.

### Changes to shared documents

The user answered each change with option A: changes 1 to 3 at design, changes 4 and 5 at the local review of this design, and changes 6 to 9 at design review round 1, each accepted 2026-11-21; change 10 at design review round 2, accepted 2026-11-22. None is applied in this pull request. This design's own sections follow the accepted wording.

1. **`docs/adr/0045-lair-software-factory.md`, decision 4 (line 29 and its sub-bullets, lines 30 to 33).** Proposed text:

   ```markdown
   4. **Strain settings come from the Lair.** The Lair writes one settings file per strain and passes it with `--settings`. The coordinator's `.claude/settings.local.json` is not copied in.
      - The file carries `HIVEMIND_LAIR_STRAIN` (claim nonce and autonomy level) and sets the merge keys `HIVEMIND_AUTO_MERGE` and `HIVEMIND_AUTO_MERGE_ADMIN` to empty values. `--settings` sits above the user, project and local settings scopes and below managed settings (ADR-0010), and `merge-approved.sh` reads an empty value as off. The strain starts in an environment without the merge keys.
      - Deny rules on the merge, label and issue-edit commands are a barrier against a strain's mistake, not full containment. A prompt-injected strain stays a named residual.
      - A `Stop` hook records an idle marker.
      - The strain may push its own branch and open or update its PR, nothing more. It never writes to the issue.
   ```

   User's answer: option A, accepted 2026-11-21.

2. **`docs/prds/autonomous-ready-issue-loop.md`, line 64.** It replaces `- Only the Lair merges. A strain cannot merge, change labels or edit the issue.` Proposed text:

   ```markdown
     - Only the Lair merges. A strain runs with the merge settings empty and with settings that deny the merge, label and issue-edit commands. A prompt-injected strain that runs with the user's GitHub rights stays a named residual.
   ```

   User's answer: option A, accepted 2026-11-21.

3. **`docs/adr/0045-lair-software-factory.md`, decision 3 (line 28).** Proposed text:

   ```markdown
   3. **Strains are interactive sessions.** Each strain is an interactive `claude` session in tmux in its own worktree, started by the brood tooling. A first claim starts off the fetched trunk commit, a re-claim at its pushed branch's head, and a remediation on its pull request's branch. Worktrees stay detached. Headless `claude -p` and the Agent SDK are not used.
   ```

   User's answer: option A, accepted 2026-11-21.

4. **`docs/prds/autonomous-ready-issue-loop.md`, line 62.** It replaces `- Comments by users without write permission never reach a strain.` Proposed text:

   ```markdown
     - Comments by users without write permission never reach a strain. An in-scope reviewer Bot (ADR-0043) counts as trusted, because only an administrator can install the app behind it.
   ```

   User's answer: option A, accepted 2026-11-21.

5. **`docs/adr/0045-lair-software-factory.md`, decision 11 (line 62).** It replaces the sentence `Comments by users without write permission never reach a strain.` Proposed text:

   ```markdown
   Comments by users without write permission never reach a strain. An in-scope reviewer Bot (ADR-0043) counts as trusted, because only an administrator can install the app behind it, so a remediation strain reads its review text.
   ```

   User's answer: option A, accepted 2026-11-21.

Changes 6 to 9 answer one question, asked at design review round 1: "Your earlier answers changed ADR-0045 decisions 3 and 4 and PRD line 64. Four more lines still say the old thing and now contradict the design ... Should these four lines get the matching rewording, recorded under 'Changes to shared documents' for a later issue to apply?"

6. **`docs/prds/autonomous-ready-issue-loop.md`, line 84.** It replaces `- **Strains are interactive sessions in tmux, one per claimed issue,** each in its own worktree off the fetched trunk commit. Headless runs are not used.` Proposed text:

   ```markdown
   - **Strains are interactive sessions in tmux, one per claimed issue,** each in its own worktree. A first claim starts off the fetched trunk commit, a re-claim at its pushed branch's head, and a remediation on its pull request's branch. Headless runs are not used.
   ```

   User's answer: option A, accepted 2026-11-21.

7. **`docs/prds/autonomous-ready-issue-loop.md`, line 86.** It replaces `  - they carry the unattended marker and no merge settings, with deny rules on merging and issue writes;` Proposed text:

   ```markdown
     - they carry the unattended marker and the merge keys set empty, with deny rules on merging and issue writes;
   ```

   User's answer: option A, accepted 2026-11-21.

8. **`docs/prds/autonomous-ready-issue-loop.md`, line 107.** It replaces `- **Strain contract tests:** result schema, crash and stall detection, and settings that carry no merge keys and deny merges and issue writes.` Proposed text:

   ```markdown
   - **Strain contract tests:** result schema, crash and stall detection, and settings that carry the merge keys set empty and deny merges and issue writes.
   ```

   User's answer: option A, accepted 2026-11-21.

9. **`docs/adr/0045-lair-software-factory.md`, line 109.** It replaces `- **A prompt-injected strain holds the user's rights.** Containment is the Lair-written settings (deny rules, no merge keys), not a separate identity.` Proposed text:

   ```markdown
   - **A prompt-injected strain holds the user's rights.** The Lair-written settings (deny rules, merge keys set empty) are a barrier against a strain's mistake, not full containment. A prompt-injected strain stays a named residual until a separate identity exists.
   ```

   User's answer: option A, accepted 2026-11-21.

Change 10 answers one question, asked at design review round 2 (L2-C9): "PRD line 100 says 'the marker absent means today's behavior'. The round-1 fix makes the scripts fail closed instead ... Record a PRD change for this?"

10. **`docs/prds/autonomous-ready-issue-loop.md`, line 100.** It replaces `- **Contract tests for unattended mode:** each stop kind resolves to take, park or handoff as the ask policy states; no unattended path waits for input; the marker absent means today's behavior.` Proposed text:

    ```markdown
    - **Contract tests for unattended mode:** each stop kind resolves to take, park or handoff as the ask policy states; no unattended path waits for input; the marker absent means today's behavior, unless the worktree holds a Lair launch file.
    ```

    User's answer: option A, accepted 2026-11-22.

## Verification strategy

The tests are the PRD's [Testing Decisions](../../prds/autonomous-ready-issue-loop.md#testing-decisions). This section adds where each test of this scope lives and how it is registered.

- **Strain launch shell tests,** a new `tools/test_lair_strain.sh` (#604): Lair mode of `spawn-brood.sh` with tmux and `claude` stubbed, as `tools/test_brood_compat.sh` Assertion 9a does; the settings content (empty merge keys, marker, deny rules, hooks, the worktree deny rule); the launch command string, its `env -i` form and its fixed name list as a pin, with an unset name not passed at all, never passed empty; no settings copy; `spawn.json` written before `tmux new-session`, and a second spawn on one nonce refused; the detached start commit for each start point; for each start kind, that the record's pre-image reaches the push (the parked head on a re-claim, the pull request head on a remediation, an empty value on a first claim); the refusals for a missing or reused nonce; the marker check's `none`, `verified` and `unverified` cases, `verified` before any manifest exists, `verified` when the Lair runs in a linked worktree, and `unverified` for a launch file with no marker; `lair-record.sh` writing only the engine record; and `lair-result.sh` with and without an engine record, with an unverified marker, its schema check, the record-less nulls (`level`, `pr`, `branch`, `head`, `park`, `gates` and `decisions`), and its single write.
- **Lair controller tests,** a new `tools/test_lair_tick.sh`, against recorded GitHub states with stubbed tmux, as the parent design's controller tests are: crash, invalid result and stall detection, the `/exit` grace and kill, the wall-clock budget, the start configuration check (a branch-side `.claude/` change refused, a trunk-side one after the fork not refused, no single merge base refused), the moved-head check and each of its refusal effects, `start_moved` handling by start kind, clean-up with the local ref delete, `unpushed_work` with its rescue text, `design_superseded`, `park_unanswered`, the decision limits, the remediation terminal effects, the repeat guard (no dispatch for listed keys, one dispatch for a new finding key after a `complete` remediation on the same head), `gh pr ready` after a complete re-claim, the kill of a live session after a failed spawn, and the environment preflight stop for each probe (#608, #609, #610). The PRD's crash and stall tests live here.
- **`tools/test_brood_compat.sh`** gains the case that a call without `lair_nonce` is byte-for-byte today's spawn.
- **`tools/test_push_branch.sh`** gains the Lair-mode cases, each a remote state on a real bare remote with its stated exit (#604). On every refusal the exit is 1, the remote is unchanged, stderr ends with the fixed blocker line unless the case names another, and stdout is empty:
  - remote at the pre-image: pushed, exit 0, `.hivemind/lair/pushed` holds the commit;
  - two pushes in one run, the second from the first's landed commit: both pushed, exit 0;
  - remote advanced by a commit the clone never fetched: refused;
  - remote advanced by a commit the clone fetched and merged: refused, the case a plain push accepts;
  - remote branch rewound, or deleted: refused;
  - first claim with the branch absent: created, exit 0; first claim with the branch present at an ancestor of the commit: refused;
  - local branch that lacks the expected commit, with the remote still at it: refused by the ancestry check before any push, with the blocker `push was rejected`, never the start-moved line;
  - a `pushed` value that does not descend from the pre-image: refused before any push;
  - repeat push of the already pushed commit: exit 0;
  - upstream mode after a fetch refreshed the tracking ref: refused;
  - origin mode with `--on-reject warn`: refused, exit 1;
  - marker `none`: the lease retry and the warning stay as today;
  - marker `unverified`: blocked before any push.
- **`tools/test_open_plan_pr.sh`** gains the case that the Lair-mode blocker is relayed as the last stderr line and no pull request is created (#604).
- **`tools/test_create_working_branch.sh`** gains the first-claim refusal of an existing local branch, and the marker `none` case that still switches (#604).
- **`tools/test_gather_facts.sh`** gains the marker cases: `lair_strain` lines, refused refs that differ from the launch file, and the author filter (#610).
- **`tools/test_fetch_normalize.sh`** gains the author filter cases, CI records passing with no author, and the `body` field only with a verified marker (#610).
- **`tools/test_synapse_gate.sh`** gains the new runner command forms of `lair-launch-check.sh` and `lair-record.sh`, a `lair-record.sh` call without `--inputs` denied, the two new Write kinds, allowed and refused, and a non-synapse agent's no-argument `lair-result.sh` call, which gets no decision (#604, #607).
- **Engine tests** in `tests/workflow-scripts/`: the level path (`none`, `verified` with a match, a mismatch, `unverified`), the `branch` launch arg and its plan check, the engine record at every verified end, `launch_mismatch` and `agent_budget` included, the agent-call cap with its kept-back record call, a park at the cap that still runs its pull request step, transient retry included, and its record call, every ask at the `unattended` level ending as a park, and a park after commits running the pull request step with `draft` true (#604, #607). In `tests/workflow-scripts/standard-delivery.test.mjs` and `tests/workflow-scripts/pr-feedback-remediation.test.mjs`, a pull request relay blocked with the fixed line gives cause `start_moved` after one runner call, a relay blocked with `push was rejected` never does, and a parity test pins `isStartMoved` to the fixed `blocker: start moved:` line of `push-branch.sh`, as the `isInputsRefusal` one does for `open-plan-pr.sh` (#604). `tests/workflow-scripts/pr-feedback-remediation.test.mjs` also covers a fix pass whose `push_blocker` holds the fixed line, and a fix-pass push followed by a tail push with no false `start_moved` (#610).
- **Overlord prose tests.** `tests/workflow-scripts/overlord-contract.test.mjs` pins the new `plugin/agents/overlord.md` sentences: the marker check before the first launch, the switch onto `start.branch`, the verbatim launch from `launch.json`, no Instinct fallback, no Resume On Start question, no post-PR watch, no reply to a pause, `lair-result.sh` at run end on both marker results, the `user_gate` edits, and the Lair strain branch rule. `tests/policy/safety-ask-set.json` gains the consumer pin for the Tier A edit and for the brood strain approval bullet. A new `tests/policy/safety-lair-strain.json` pins the security-policy edits for pre-spawn approval and strain settings, and the `hivemind:github-reviewer` and remediation-doctrine edits, per the pin-authoring contract in `tests/policy/README.md`. `tests/policy/safety-synapse-gate.json` moves to eight members. #607 either fits `plugin/agents/overlord.md` within its byte budget in `tests/policy/prose-byte-budget.json`, or asks the user for a raise in `tests/policy/prose-budget-raises.json`.
- **Registration in `tools/validate.sh`.** Every new `tools/test_*.sh` named here, `tools/test_lair_strain.sh` and `tools/test_lair_tick.sh` included, is added in the same pull request to `KNOWN_SUITES`, `ALL_SUITES`, a `SUITE_*` constant, and a `map_path` rule for each script and fixture it covers, so `tools/validate.sh --self-test` passes and `--changed` selects it. The paths:
  - `plugin/skills/lair-launch-check/**`, `plugin/skills/lair-record/**`, `plugin/skills/lair-result/**` and `plugin/skills/lair-strain-check/**` route to `tools/test_lair_strain.sh`; the first two also route to `tools/test_synapse_gate.sh` and the `test_workflow_scripts` route, as `synapse-gate.sh` does;
  - `plugin/skills/spawn-brood/**` and `plugin/skills/push-branch/**` also route to `tools/test_lair_strain.sh`, beside their routes today (`tools/validate.sh` lines 580 and 649), because that suite runs Lair mode of `spawn-brood.sh` and the pre-image reaching the push;
  - the shared marker-check library `plugin/skills/_shared/lair-marker.sh` routes to every suite that runs a consumer: `tools/test_lair_strain.sh`, `tools/test_push_branch.sh`, `tools/test_open_plan_pr.sh`, `tools/test_gather_facts.sh`, `tools/test_fetch_normalize.sh` and `tools/test_create_working_branch.sh`, as `plugin/skills/_shared/git-refusals.sh` does;
  - the Lair controller's own paths route to `tools/test_lair_tick.sh`.
  The `tests/policy/safety-push-single-process.json` pin stays valid: `push-branch.sh` is the one push site its set_check leaves out by design, and `tools/test_push_branch.sh` asserts its behavior. New `tests/workflow-scripts/*.test.mjs` files need no registration: `tools/test_workflow_scripts.sh` runs the glob. New `tests/policy/*.json` fixtures run under `policy_check.sh`.
- **Headless checks,** recorded in an ADR-0010 amendment by #604: an empty `--settings` env value overrides a local one; the settings `env` reaches a workflow agent's Bash; each deny rule form refuses its command, `WebFetch` and `WebSearch` included; `--settings` hooks fire on main-session and workflow-agent tool calls; the `Stop` hook during a background workflow; `/exit` through tmux; and a strain under the `env -i` list can start, push, call GitHub and run the configured local review tool with no skip.
- **The live smoke run** on a throwaway issue, by hand, as in the parent design, also checks that the strain's `env` shows both merge keys empty.

## Seam order

The build order is the parent design's. This design changes these slices; #605, #606 and #612 are not changed.

| Slice | What this design changes | ADRs |
| --- | --- | --- |
| #604 | Lair mode of `spawn-brood.sh` with `spawn.json`, the `env -i` launch and the per-worktree settings parts, the settings fragment, the launch file and its check, start points, the `branch` launch arg, the marker check, `lair-result.sh`, `lair-record.sh` and the engine record, liveness hooks, the overlord branch rule, the strain-settings and synapse runner gate edits, Lair mode of `push-branch.sh` with its lease push, `pushed` file and ancestry check, the first-claim refusal of `create-working-branch.sh`, and the engine matcher `isStartMoved` | ADR-0045 decisions 3, 4 and 5; ADR-0007; ADR-0010; ADR-0017; ADR-0019; ADR-0020; ADR-0021; ADR-0027; ADR-0028; ADR-0029; ADR-0030; ADR-0037; ADR-0040; ADR-0042; ADR-0044 |
| #607 | the level path into both engines, the agent-call cap and its kept-back end calls, engine-built parks for every ask, the park push, the Tier A and user_gate edits, and the overlord's strain-run prose | ADR-0045 decisions 5, 6, 7, 8 and 17; ADR-0026; ADR-0029; ADR-0030; ADR-0036; ADR-0037; ADR-0039; ADR-0040 |
| #608 | the pre-spawn approval edit, the environment preflight, the writes before spawn, the kill after a failed spawn, session end, stall and budget detection, unpushed-work handling and the local ref delete, and the first-claim handling of `start_moved` | ADR-0045 decisions 5, 10 and 17 and the 2026-11-21 amendment; ADR-0007; ADR-0017; ADR-0026 |
| #609 | the settled-decision entry form and limits, the re-claim start point, the start configuration and moved-head checks for a re-claim, the re-claim handling of `start_moved`, marking a completed re-claim ready, superseded design and unanswered park | ADR-0045 decisions 3, 7, 11 and 16; ADR-0017; ADR-0037 |
| #610 | the remediation start point, its checks and its handling of every failed end, the dispatch marker and repeat guard, args, author filter, CI rule and filtered bodies, the fix pass's `push_blocker` and defer rule, and the review text scan | ADR-0045 decisions 3, 11 and 13; ADR-0017; ADR-0023; ADR-0032; ADR-0040; ADR-0043 |
| #611 | the digest takes decisions from the result, which comes from the engine record, and shows null decisions as unknown | ADR-0045 decision 14; ADR-0026; ADR-0030 |

## Open questions

None

## Amendments

This design was written on 2026-11-21, after the user accepted the three changes under Decisions. Those changes are not applied in this pull request. Later changes to this design are appended here as dated entries.

- **2026-11-21, local review.** The user chose option A for the remediation author filter: an in-scope reviewer Bot counts as trusted without a write-permission check. Changes 4 and 5 propose the matching PRD and ADR-0045 decision 11 wording.
- **2026-11-21, local review root-cluster remediation.** Local review iterations 1, 3 and 4 each found a branch move that fell after a start check, and each patch moved the check later. This entry fixes the class at its source: the strain's push in Lair mode of `push-branch.sh` is the one authority on a moved branch, the engine alone maps its fixed blocker line to `start_moved`, the overlord's post-switch fetch and head recheck are removed, and the Lair's pre-launch check stays as a fail-fast. Context and code truth recorded the trunk facts behind it and corrected the claim "A strain's push is never forced". Wasted run time after a mid-run move is a recorded residual, with no mid-run poll designed. This entry's key, fast-forward acceptance at the push, is superseded by the next entry.
- **2026-11-21, local review, changed approach.** A fourth finding showed that a key on fast-forward acceptance still misses moves: a move the strain fetched and merged, a rewound or deleted remote branch, and a first-claim branch that already exists at an ancestor. The user chose to change the approach rather than patch the rule again. The new key is the remote branch's pre-image, the commit the run started from, which the remote compares at the write through an explicit lease; an ancestry check before the push keeps it from rewriting the branch (Start points). Closed-by-construction answer: any remote state other than the captured pre-image at the write, whatever its direction, ancestry or timing, is refused by the remote itself, and every earlier check is a hint. The design is unbuilt, so no code changed.
- **2026-11-21, design review round 1.** The round's findings are answered in place; the review record maps each to its section. The main changes: the lease advances to the strain's own last landed push, since a remediation run pushes twice; `spawn-brood.sh` writes a spawn record before the session starts, and the marker check reads it instead of the manifest; strains launch under `env -i`; a re-claim or remediation start commit that changes `.claude/`, `.mcp.json` or the git hooks folder is refused; every unattended ask parks; the synapse runner gate's edits are named; remediation strains get a dispatch marker, terminal effects and a repeat guard; review bodies come from the author filter; and changes 6 to 9 reword the four shared lines still at odds with the design.
- **2026-11-22, design review round 2.** The round's findings are answered in place; the review record maps each to its section. The main changes: the engine record has its own runner script, `lair-record.sh`, and the overlord's no-argument `lair-result.sh` stays outside the synapse runner gate; the remediation moved-head row follows Start points; the remediation repeat guard is keyed on the head and the finding keys; strain environment names pass only when set, the list grows, and the Lair runs an environment preflight; the marker check anchors on the Lair checkout, four levels above the strain; a result with no engine record holds nulls; the agent-call cap keeps back a park's pull request step; the start configuration check diffs the branch side from the merge base; `tools/validate.sh` routes `spawn-brood` and `push-branch` to the strain suite; and change 10 rewords PRD line 100.
