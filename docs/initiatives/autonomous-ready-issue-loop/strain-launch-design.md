# Solution design: Lair strain launch and containment

This is the solution design for issue #630, the strain launch and containment part of the Lair, epic #603. It links the [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md) and the parent [solution design](solution-design.md) rather than restating them, cites ADR-0045 as "ADR-0045 decision N", and adds only what they lack. For this scope it replaces these parts of the parent design:

- the Components "Strain launch and settings" and "Strain result and liveness";
- the governance side of the Component "Unattended autonomy level", and the launch side of the Component "Post-PR remediation strains";
- the Contracts "Strain result", "Lair-written settings" and "Settled decisions";
- the strain-containment paragraph of Trust boundaries;
- the strain-settings, result-file and idle-marker rows of State and ownership;
- the Crash, Stall, `Stop` hook, `/exit` and Budget-overrun rows of Failure modes.

Every other part of the parent design stands. The design review is recorded in the [strain launch review record](strain-launch-review-record.md).

## Context and code truth

The design builds on this code, as it stands on trunk.

**Correction to the parent design.** Its Context section says `spawn-brood.sh` "has no way to write per-strain settings". That is wrong. Trunk `plugin/skills/spawn-brood/scripts/spawn-brood.sh`:

- writes a per-brood `.hivemind/broods/<brood-id>/strain-settings.json` holding only `permissions.allow`, one `Read(/<root>/**)` rule per plugin-root spelling that passes its charset gate;
- launches each strain as `claude --permission-mode auto --settings ../../../../.hivemind/broods/<brood-id>/strain-settings.json`, a path relative to the worktree, so the tmux command string holds only fixed literals and the asserted brood id (ADR-0010, amendment 2026-10-31);
- still copies the coordinator's `.claude/settings.local.json` into every strain worktree, refusing a symlinked leaf;
- still starts each worktree detached, with `git worktree add --detach "$wt" "$base_commit"`, and creates no branch;
- still turns on remote control (`/rc <short>`) for every strain that started, through `plugin/skills/enable-brood-remote/scripts/rc-brood.sh`;
- writes `inputs.json` and `manifest.json` (manifest version 4) under `.hivemind/broods/<brood-id>/`, and `task.md` under the worktree's `.hivemind/brood/`, starting with the data-boundary preamble and then a YAML data block of `parent`, `strain`, `run`, `working_branch.base` and `task.description`;
- starts the tmux session with `tmux new-session -d -s <session> -c <worktree> "<launch command>"`.

Other code this design relies on:

- `docs/adr/0010-permission-allowlist-posture.md`, amendment 2026-10-31, records the documented facts this design uses: `--settings` sits below managed settings and above local, project and user settings; deny and ask rules from any source win over an allow; and since Claude Code 2.1.211 a worktree session reads `.claude/settings.local.json` at the main checkout's root. A copy into the worktree therefore keeps nothing out.
- `plugin/skills/github-review-loop/scripts/merge-approved.sh` reads `MERGE_METHOD="${HIVEMIND_AUTO_MERGE:-}"` and reports `MERGE=off` when it is unset or empty. It tests `HIVEMIND_AUTO_MERGE_ADMIN` with `-z`, so an empty value is off.
- `plugin/workflow-src/standard-delivery/main.js` reads the launch args `request`, `trunk`, `references`, `local_review`, `draft` and `decisions`, plus the pause keys `answers`, `build` and `reply`. "An autonomy key is never read": `run.level` is `resolveLevel(undefined, AUTONOMY_TABLE)`, the table's `default_level`, `high`. `decisions` is 1 to `maxDecisions()` (10) non-blank strings of at most `maxDecisionLength()` (2000) code points. There is no `branch` launch arg: the plan names the working branch.
- `plugin/workflow-src/pr-feedback-remediation/main.js` takes only `references`, naming exactly one pull request, and `trunk`. Its `run.level` is the table's `default_level`. Its facts step runs with the pull request as its one reference.
- `plugin/workflow-src/lib/decide.js` is pure, with no I/O. The levels are those of `plugin/references/decision-autonomy-table.json`: `high`, `balanced` and `low`, default `high`. Nothing under `plugin/workflow-src/` reads `process.env`, and per [P24](../../engineering-principles.md) a running workflow script cannot read files. So today the engine reads no process environment.
- `plugin/workflow-src/lib/facts.js` runs committed scripts through `hivemind:synapse` from a command block, and a file block's content is written as is, for the `--inputs .hivemind/molt-inputs-<token>.json` and `.hivemind/pr-inputs-<token>.json` forms. `plugin/hooks/synapse-gate.sh` allows only the listed command forms.
- `plugin/skills/gather-facts/scripts/gather-facts.sh`, step (7), reads for each `--ref` the issue or pull request title, body and author and every top-level comment with its body. Step (6) reads the branch's pull requests as number, state, URL, head commit and base only.
- `plugin/skills/github-review-loop/scripts/fetch-normalize.sh` reads review threads, reviews and top-level comments with each author's login and `__typename`. `reviewer-identity.jq` applies the Bot gate of ADR-0043.
- `plugin/skills/create-working-branch/scripts/create-working-branch.sh` switches onto an existing local branch with `git switch --no-guess <branch>`. It refuses a dirty tree and a branch checked out in another worktree.
- `plugin/agents/overlord.md`: `## Engine` falls back to Instinct when a `standard-delivery` launch is refused or ends blocked; `## Resume On Start` offers resume or start fresh; `## Review Remediation Posture` holds the default post-PR watch and its `HIVEMIND_SKIP_PR_WATCH` short-circuit; `## Brood Execution` gets the user's approval of the strain text before spawn, and its "Brood child" paragraph derives a fresh branch off `working_branch.base`.
- `plugin/governance/security-policy.md` (Brood Spawn Bypass-Mode Mitigation) names pre-spawn human approval as the injection gate for strain text. `plugin/governance/decision-autonomy.md` (Tier A — Always Surface) lists brood strain approval, a fact only the user holds and a question with no recommendation among the closed Ask Set.
- `plugin/hooks/hooks.json` holds one `PreToolUse` hook, `synapse-gate.sh` on `Bash|Write`. That gate exists to check the runner commands of `hivemind:synapse`, a workflow agent.
- No agent-call cap exists under `plugin/workflow-src/`.
- `tools/validate.sh --self-test` fails any `tools/*.sh` suite missing from `KNOWN_SUITES`. `tools/test_workflow_scripts.sh` runs every `tests/workflow-scripts/*.test.mjs`. `tests/workflow-scripts/overlord-contract.test.mjs` pins sentences of `plugin/agents/overlord.md`.

## Components

### Strain launch and settings

Built by #604. The Lair starts each strain through `spawn-brood.sh`, one strain per brood, so the per-brood `strain-settings.json` is the strain's own settings file (ADR-0045 decision 4). The Lair calls the script directly, not through the overlord's brood gate.

- **Lair mode.** `spawn-brood.sh` gains one optional per-strain input, `lair_nonce`, an identifier, never a path. With it, the script derives the Lair strain record `.hivemind/lair/strains/<nonce>/` from the checkout root and refuses a nonce whose record is missing or already names a brood. Then it:
  - writes `strain-settings.json` as the union of the plugin read rules and the Lair's settings fragment from the record;
  - does not copy the coordinator's `.claude/settings.local.json`;
  - creates the worktree detached at the record's start commit, never at `base`;
  - writes a fixed Lair `task.md` description naming `.hivemind/lair/launch.json`, and copies the record's `launch.json` there, with the same leaf containment checks as `task.md`;
  - starts the session with `env -u HIVEMIND_AUTO_MERGE -u HIVEMIND_AUTO_MERGE_ADMIN -u HIVEMIND_LAIR_STRAIN claude --permission-mode auto --settings ../../../../.hivemind/broods/<brood-id>/strain-settings.json`. tmux starts a command in its server's environment, not the caller's, so the keys are removed in the command itself. The string still holds only fixed literals and the asserted brood id;
  - keeps remote control on, as for any strain.
- **Without `lair_nonce`** the script behaves exactly as today.
- **The settings fragment** is the Contract "Strain settings". It sets the merge keys to empty values, so they override the user, project and local scopes, and it holds the marker, the deny rules and the liveness hooks.

### Launch inputs

Built by #604, with the level path in #607. The Lair writes every launch input. None is derived from the issue text by a model.

- The Lair writes `launch.json` (Contract "Launch file") in the strain record before spawn. Its `args` are exactly the `Workflow` launch args. The level is not a launch arg.
- The overlord of a verified strain launches the workflow `launch.json` names with its `args` verbatim, and nothing else.
- **The copy is checked, not trusted.** The engine writes the args it received to an inputs file through a synapse file block, and runs the fixed runner `lair-launch-check.sh`. The runner compares them as JSON values with the Lair's record copy, outside the worktree. A mismatch ends the run `failed` with cause `launch_mismatch` before any planner call.
- **The level reaches the engine by a path task text cannot set.** `HIVEMIND_LAIR_STRAIN` is set only by the Lair's settings file. `gather-facts.sh` reads it and prints a `lair_strain` routing line (`none`, `verified` or `unverified`) through the marker check (Contract "Marker check"). With `verified` and a matching launch check, the engine sets `run.level` to `unattended`. With `none` the level is today's default, and no extra agent call runs. With `unverified` the run ends blocked with cause `lair_marker_unverified`: a stray marker in an interactive session stops visibly and never selects unattended.
- **Facts come only from the captured issue text.** A delivery launch has `references: []`. The request is the issue title and body captured at claim (ADR-0045 decision 10). With a verified marker, `gather-facts.sh` refuses any `--trunk` or `--ref` word that differs from `launch.json` before its first GitHub call. So the delivery workflow makes no live read of the issue, its references or comments. A prompt-injected strain could still read them with the user's rights (Trust boundaries).
- **`decisions`** holds the settled decisions (Contract "Settled decisions"), absent when there are none. **`draft`** is `false` at every Lair launch. **`local_review`** is `true` at every Lair launch, so a skipped local review shows only as the engine's own skip.
- **Agent-call cap.** #607 owns it. At the `unattended` level the engine counts each agent call of the run. At `maxUnattendedAgentCalls()`, 80, it makes no further call and ends the run `failed` with cause `agent_budget`.

### Start points

Built by #604, with re-claim in #609 and remediation in #610. Every worktree is created detached, and the run is told which existing branch to work on.

| Start | Worktree commit | Branch | Who checks |
| --- | --- | --- | --- |
| First claim | the fetched trunk commit, `refs/remotes/origin/<trunk>` after `git fetch` | none: the plan names a fresh branch, as for any brood child | #608 |
| Re-claim | the parked head, recorded in the park marker from the parked result | `args.branch`, the parked branch | #609 |
| Remediation | the pull request's head commit, read at dispatch | the pull request's head branch, recorded in `launch.json` `start.branch` | #610 |

- **Before a re-claim or remediation launch**, the Lair fetches `origin/<branch>`. It launches only when the remote head equals the expected head, the local `refs/heads/<branch>` is absent or equal to it, and no worktree has the branch checked out. When the local ref is absent, the Lair creates it at the expected head with `git branch --no-track`. It never moves an existing ref.
- **`args.branch`** is a new optional `standard-delivery` launch arg (#604). It must pass the identifier gate. When present, the plan's working branch must equal it, or the plan check refuses the plan, and `create-working-branch.sh` finds the run already on it and does not switch.
- **A re-claim or remediation strain's overlord** switches onto `start.branch` with `git switch --no-guess` before launching, as `## Engine` already does for a remediation request. It then fetches `origin/<branch>` and checks that both `HEAD` and the fetched remote head are `start.commit`. Another head, or a failed fetch, means the branch moved or cannot be confirmed: the overlord launches nothing and the result is `failed` with cause `start_moved`, which the Lair handles as a moved head.
- **The push is the authoritative check.** The start checks are a fail-fast, not a guarantee: the remote branch can move at any time during the run. A strain's push is never forced, so a branch that moved after the checks refuses it as a non-fast-forward, and the run ends `failed` with cause `start_moved`. A strain therefore never overwrites a moved branch. **Named residual:** a move during the run is found only at that push, so the strain's work up to then, within its 6-hour budget, is lost.
- **Moved head.** On a re-claim, a remote or local head other than the parked head means someone else changed the branch. The issue gets `lair:handoff` with reason `branch_moved`. On a remediation, a pull request head other than the last Lair result's head starts no strain, and the pull request is routed to `lair:review` (#631).
- **Superseded design.** At claim the Lair records the review record's stamp blobs on fetched trunk as `design_stamps` in the claim marker, for an initiative slice only. When a re-claim finds other stamps, the parked work was built for an earlier design. The issue gets `lair:handoff` with reason `design_superseded`.
- **Unanswered park.** An issue relabeled `readiness:ready` while one of its open park keys has no admitted answer is not claimed. It is named in the queue report with reason `park_unanswered` and gets no new label, as for a failed readiness check.
- **Decisions too large.** A park record has one key, and a third park hands the issue off (ADR-0045 decision 7), so at most 2 settled decisions exist. The Lair still checks both limits before launch. More than 10 entries, or any entry over 2000 code points, means the issue is not claimed. It is named in the queue report with reason `too_many_decisions` or `decision_too_long` and gets no new label. The user can post a shorter answer. The Lair never truncates an answer.
- **A parked run with no commits** has no branch. Its re-claim starts as a first claim.

### Strain result and liveness

Built by #604. ADR-0045 decision 5 holds: the strain's overlord runs one fixed script, `lair-result.sh`, that writes the result.

- **The engine writes its own record.** At every end of an `unattended` run, the engine runs `lair-result.sh --inputs .hivemind/lair-record-<token>.json` through a synapse file block. The record holds the outcome, cause, pull request, branch, head, park record, the gates that held, and `decisions` built from the run's taken decisions (`run.taken`). The script checks it and writes `.hivemind/lair/record.json` in the worktree.
- **The overlord's call writes the result.** At run end the overlord runs `lair-result.sh` with no argument. The script reads the engine record and the marker, checks them against the schema, and writes `.hivemind/lair/result.json` once, through a temporary file and a rename. The result's `decisions` come only from the engine record, never from model prose. With no engine record, for example after a refused launch, the result is `failed` with cause `no_engine_record` and no decisions.
- **Liveness files.** The settings fragment adds two hooks, in exec form per ADR-0028, each a fixed `touch` of an absolute path in the strain's worktree:
  - a `PreToolUse` and `PostToolUse` hook with matcher `*` touches `.hivemind/lair/activity`;
  - a `Stop` hook touches `.hivemind/lair/idle`.
- **Run activity** is the activity file's modification time. Claude Code produces it on each tool call of the strain session. Plugin hooks firing on workflow agents' tool calls is what `synapse-gate.sh` already relies on; #604 verifies the same for a `--settings` hook.
- **Session end** is in Lifecycle. It never waits on a push.

### Unattended governance edits

Each edit below is a governance or agent text change that unattended runs need. The slice named makes it. Each changed load-bearing section gets its consumer pin, per CLAUDE.md.

| Edit | Target | Slice |
| --- | --- | --- |
| **Tier A.** In a verified Lair strain nothing is surfaced. A safety rail (Destructive Fix Gate, a direct trunk commit or push, injection-suspect content) becomes an `approval` park. A fact only the user holds becomes a `fact` park. A question with no recommendation, and a tripped gate other than the safety clause, becomes a `decision` park. A tool call failed after retries ends the run `failed`. The router `ambiguous` outcome and the resume and version-skew doors do not arise, because the launch names the workflow and each strain is a fresh session. A strain makes no merge recommendation. | `plugin/governance/decision-autonomy.md` (Tier A — Always Surface) | #607 |
| **user_gate.** A verified strain never enters the state machine. A refused or blocked engine launch ends the strain `failed` with no Instinct fallback, so no `user_gate` state is reached. The Instinct ask and the Question gate are skipped the same way. | `plugin/agents/overlord.md` (`## Engine`, `## Instinct`, `## Workflow State Execution` step 5, `### Stop Conditions`) | #607 |
| **Pre-spawn approval.** For a Lair strain, admission (ADR-0045 decision 10 and its amendment) and the pre-spawn injection scan replace the human approval of strain text. The scan runs on #632's scan executor. This is a seam with #632. | `plugin/governance/security-policy.md` (Brood Spawn Bypass-Mode Mitigation), `plugin/agents/overlord.md` (`## Brood Execution`), the brood strain approval bullet of `plugin/governance/decision-autonomy.md` (Tier A — Always Surface) | #608 |
| **Strain runs.** A brood child runs `lair-strain-check.sh` before its first launch. With `verified` it launches from `launch.json` verbatim, runs no Resume On Start question, no post-PR watch and no Instinct fallback, turns any question the engine still returns into a `failed` result, and ends by running `lair-result.sh`. With `unverified` it launches nothing and stops. | `plugin/agents/overlord.md` (`## Engine`, `## Resume On Start`, `## Review Remediation Posture`, `## Brood Execution`) | #607 |
| **Lair strain branch.** A Lair strain with `args.branch` works on that branch, not on a fresh one. | `plugin/agents/overlord.md` (`## Brood Execution`, "Brood child") | #604 |
| **Strain settings.** The Lair settings content beside the plugin read rule. | `plugin/governance/security-policy.md` (Brood Spawn Bypass-Mode Mitigation, "Strain plugin-read grant") | #604 |

### Remediation strain launch

Built by #610. A remediation strain uses the same settings, marker, liveness and result contract as a delivery strain (ADR-0045 decision 13). Its start point is under Start points.

- **Its args** are `{"references": [<pr>], "trunk": "<trunk>"}`, the only keys `pr-feedback-remediation` takes. `launch.json` also carries `start.branch` and `review_authors`.
- **Review text that reaches it:**
  - through the facts step, with the pull request as its one reference: the pull request's title, body and top-level comments;
  - through the fix pass and `fetch-normalize.sh`: review threads, reviews, top-level comments and CI check results.
- **The author filter.** With a verified marker, `gather-facts.sh` and `fetch-normalize.sh` drop every text whose author is neither an in-scope reviewer Bot (ADR-0043's Bot gate in `reviewer-identity.jq`) nor a login in `launch.json` `review_authors`. They report the count dropped. The Lair fills `review_authors` at dispatch with the users with write permission who wrote review text. An in-scope Bot passes without a write-permission check: a Bot account is a GitHub App, and only an administrator can install an app on the repository, so an in-scope Bot counts as trusted, as a user with write permission does. `github-actions[bot]` is in scope only when listed (ADR-0043). Comments by other users without write permission therefore never reach the strain through its workflow. This Bot exception needs the PRD and ADR-0045 wording of changes 4 and 5 below.
- **Scanning.** Every remaining text is external content. The facts-step injection scan of `lib/facts.js` runs on the facts texts before the fix pass. The `hivemind:github-reviewer` classifies each finding per `${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Injection-Suspect Classification). An injection-suspect verdict ends the run as an `approval` park. The Lair then routes the pull request to `lair:review` (#631).

## State and ownership

GitHub alone is authoritative (ADR-0045 decision 2). These rows replace the parent design's strain-settings, result-file and idle-marker rows and add the files this design and `spawn-brood.sh` write. Paths under `.hivemind/` are in the Lair's checkout unless they say worktree.

| State | Writer | Readers | Authoritative |
| --- | --- | --- | --- |
| Lair strain record `.hivemind/lair/strains/<nonce>/strain.json`: nonce, issue, start kind, start commit and branch | Lair, before spawn | `spawn-brood.sh`, the marker check, Lair | no; rebuilt from the claim |
| Launch file `.hivemind/lair/strains/<nonce>/launch.json` | Lair, before spawn | `spawn-brood.sh`, `lair-launch-check.sh`, `gather-facts.sh`, `fetch-normalize.sh` | no; rebuilt from the claim |
| Settings fragment `.hivemind/lair/strains/<nonce>/settings.json` | Lair, before spawn | `spawn-brood.sh` | no |
| `.hivemind/broods/<brood-id>/inputs.json` | `spawn-brood.sh` | record only | no |
| `.hivemind/broods/<brood-id>/manifest.json` | `spawn-brood.sh` | Lair and `brood-status`, through `brood-state.sh` | no |
| `.hivemind/broods/<brood-id>/strain-settings.json`: plugin read rules plus the fragment | `spawn-brood.sh` | Claude Code in the strain session, the marker check | no |
| Worktree `.claude/worktrees/<brood-id>/<short>/` | `spawn-brood.sh` creates it; the strain commits in it; the Lair removes it | strain, Lair | no; the pushed branch is |
| Worktree `.hivemind/brood/task.md` | `spawn-brood.sh` | the strain's overlord | no |
| Worktree `.hivemind/lair/launch.json`, a copy | `spawn-brood.sh` | the strain's overlord | no; the record copy is checked |
| tmux session `<brood-id>-<short>` | `spawn-brood.sh` starts it; the Lair ends it | Lair, `brood-status`, the user | no |
| Worktree `.hivemind/lair/activity` | the strain's `PreToolUse` and `PostToolUse` hooks | Lair | no |
| Worktree `.hivemind/lair/idle` | the strain's `Stop` hook | Lair | no |
| Worktree `.hivemind/lair/record.json`, the engine record | the engine, through `lair-result.sh` | `lair-result.sh` | no |
| Worktree `.hivemind/lair/result.json` | `lair-result.sh`, on the overlord's call | Lair | no; the Lair turns it into labels and markers |
| Main checkout `.claude/settings.local.json` and every `.claude/settings*.json` | the user | Claude Code, the merge lane (#631) | the user's; a strain is denied writes |

## Contracts and seams

Fields and seams only. Each slice builds the code.

- **Launch file.** `schema` (`lair-launch/1`), `claim_nonce`, `workflow` (`standard-delivery` or `pr-feedback-remediation`), `start` (`kind`: `first_claim`, `re_claim` or `remediation`; `commit`; `branch` or null), `args` (exactly the `Workflow` launch args), `review_authors` (a list of logins; empty outside remediation). Delivery `args`: `request` (the captured title, a blank line, then the captured body), `trunk`, `references` (`[]`), `local_review` (`true`), `draft` (`false`), `decisions` when any, `branch` on a re-claim. Remediation `args`: `references` (`[<pr>]`) and `trunk`.
- **Strain settings,** the fragment the Lair writes.
  - `env`: `HIVEMIND_LAIR_STRAIN` = `v1:<claim nonce>:unattended`; `HIVEMIND_AUTO_MERGE` = `""`; `HIVEMIND_AUTO_MERGE_ADMIN` = `""`; `HIVEMIND_SKIP_PR_WATCH` = `"1"`; `HIVEMIND_ENABLE_DECISION_REPORT` = `""`.
  - `permissions.deny`: `Bash(gh pr merge *)`, `Bash(gh pr edit *)`, `Bash(gh pr close *)`, `Bash(gh issue edit *)`, `Bash(gh issue comment *)`, `Bash(gh issue close *)`, `Bash(gh issue reopen *)`, `Bash(gh issue view *)`, `Bash(gh label *)`, `Bash(gh api *)`, `Bash(*merge-approved.sh*)`, `WebFetch(domain:github.com)`, `Edit(//**/.claude/settings*.json)`, and `Edit(//<Lair checkout>/.hivemind/lair/**)` and `Edit(//<Lair checkout>/.hivemind/broods/**)` with the absolute checkout path behind the same charset gate as the read rule. Skills reach GitHub through their own scripts, which these rules do not match.
  - `hooks`: the liveness hooks under Strain result and liveness.
  - #604 verifies the rule forms, the empty-value override and the hooks headlessly and records them in an ADR-0010 amendment, as ADR-0010's issue 455 check did.
- **Strain environment.** This is exactly what the strain holds, for #632's marker rule to be judged against:
  - the tmux server's global environment, less `HIVEMIND_AUTO_MERGE`, `HIVEMIND_AUTO_MERGE_ADMIN` and `HIVEMIND_LAIR_STRAIN`, which the launch command removes;
  - then the settings `env` of the user, project and local scopes, with the five keys above taken from the Lair's file, which sits above them;
  - so other `HIVEMIND_*` keys, such as `HIVEMIND_LOCAL_REVIEWER`, are as the user set them;
  - the user's GitHub credentials, as for any session (ADR-0045 decision 9);
  - its own claim nonce: in the marker, the settings file, the strain record, both launch file copies, the engine record and the result.

  No other claim's nonce and no Lair secret is in its environment, its settings or its worktree. The strain can still read any file the user can, the Lair's state folder and other strains' records included.
- **Marker check,** one shared library, used by `gather-facts.sh`, `lair-strain-check.sh`, `lair-launch-check.sh` and `lair-result.sh`. It prints `none` when `HIVEMIND_LAIR_STRAIN` is unset or empty. It prints `verified` only when all of these hold, and `unverified` otherwise:
  - the value matches `^v1:[0-9a-f]{32}:unattended$`;
  - the strain record for that nonce exists as a contained regular file under the main checkout's `.hivemind/lair/strains/`;
  - the record's brood `strain-settings.json` holds an `env.HIVEMIND_LAIR_STRAIN` byte-equal to the value;
  - the brood manifest's worktree for the strain equals the caller's `git rev-parse --show-toplevel`.

  A marker set in user, project or local settings, or one copied from another strain, fails a check. That is how a Lair-written marker is told from a stray or mistaken one. The check reads files a strain can rewrite with the user's rights, so it does not authenticate a marker against a prompt-injected strain; that is the named residual under Trust boundaries.
- **Strain result.** `schema` (`lair-result/1`), `claim_nonce`, `workflow`, `level` (as the engine record shows it), `outcome` (`complete`, `parked`, `blocked` or `failed`), `cause` (null or a code such as `launch_mismatch`, `start_moved`, `lair_marker_unverified`, `agent_budget`, `no_engine_record`), `pr` (number or null), `branch`, `head` (commit), `park` (a park record as in the parent design, or null), `gates` (each configured gate and whether it held or was skipped, local review included), `decisions` (each with its key, choice and reason, from the engine record). The Lair treats a result whose `level` is not `unattended` as `failed`.
- **Settled decisions.** They enter the run through the `decisions` launch arg. The Lair alone builds each entry from an admitted answer, in this form:

  ```text
  Question <key>: <question, as parked>
  Answer: <option id and label, or the fact text>
  Provenance: answered by <login> in <answer comment URL>, to the park marker <park marker URL>.
  ```

  Each entry is at most 2000 code points and there are at most 10. Over either limit, the issue is not claimed (Start points).
- **Assumptions about #631, the merge lane.**
  - The Lair reads the merge settings from the user's settings files and its own environment, never from a strain's settings, environment or files. The strain's empty merge keys therefore never stop the Lair merging.
  - #631 checks the result's `pr`, `branch` and `head` against GitHub. This design guarantees only that the result is schema-checked and that `decisions` and `gates` come from the engine record.
  - The protected-path floor holds `.claude/**`, so a strain's commit to a committed settings file never merges in the auto tier.
  - #631 routes to `lair:review` a remediation that ended injection-suspect and a pull request whose head moved.
- **Assumptions about #632, claim integrity.**
  - A claim nonce is not a secret from a strain. #632's marker rule may rely on the nonce being unknown to GitHub users without write permission. It must not rely on it being unknown to a strain. If #632 needs an authenticator a strain cannot forge, it uses a value no strain receives.
  - #632 owns the claim nonce's form. This design assumes 32 lowercase hex digits, so the nonce can sit in a path and in the marker.
  - #632 owns the claim marker form and the `body_sha256` form. `args.request` is built from the same captured bytes the hash covers.
  - The claim marker carries `design_stamps` for an initiative slice.
  - #632's scan executor runs the pre-spawn injection scan on the captured text before the Lair writes the launch file.
  - #632's claim write order and lock scope cover the strain record, launch file and settings fragment. They are written after the claim marker and labels, and a claim that stopped before spawn is reconciled by #632's rule.
- **Seam with #615.** The superseded-design check reads the review record's stamps on fetched trunk directly. It does not need more readiness-check output.

## Trust boundaries

Only a user with write permission steers the Lair, through the parent design's channels and one more:

- remote control on a Lair strain, turned on by `spawn-brood.sh` through `rc-brood.sh` (ADR-0027). Only the user's own Claude account holds it. Input typed there is the user's own and the Lair does not read it. A strain steered by hand still reports only through its result file.

**Strain containment.** This paragraph replaces the parent design's. The strain is untrusted after spawn.

- It starts with no merge key in its environment and runs with both merge keys empty in settings that sit above the user, project and local scopes. Nothing it inherits from those scopes turns a merge on; managed settings are the named residual below.
- Its launch inputs are Lair-written and checked against the Lair's copy. Its level comes from the settings marker, which task text cannot set.
- Through its workflow, a delivery strain reads no issue text but the capture, and a remediation strain reads review text only from in-scope Bots, trusted because only an administrator installs an app, and write-access users, scanned before use.
- **The deny rules are a barrier against a strain that makes a mistake, not containment of a prompt-injected strain.** A Bash call can run `bash -c`, a script, `curl` or another interpreter that no deny rule matches. The strain runs with the user's GitHub credentials and can read any file the user can.
- **Named residual: a prompt-injected strain holds the user's rights.** It could merge, relabel, comment, admit or answer other issues, write the user's settings by a path no rule matches, or rewrite the Lair's strain records, so that a forged marker passes the marker check or another strain's result is replaced. What narrows it is upstream of the strain: admission, the pre-spawn injection scan, the captured text and the author filter. A dedicated identity (ADR-0045 decision 9) is the real fix and is deferred. This is the ADR-0045 residual of that name.
- **Named residual: a merge key exported from the user's shell profile** reaches the strain's Bash calls, because the shell is started from the profile. The merge keys belong in settings files (CLAUDE.md), and `merge-approved.sh` is reached only from the review watch, which a strain never runs.
- **Named residual: managed settings** sit above `--settings`, so an administrator's managed merge key would win.

## Lifecycle

A strain moves through these steps:

1. **Write.** After the claim marker and labels, the Lair writes the strain record, the launch file and the settings fragment, and checks the start point (Start points).
2. **Spawn.** The Lair calls `spawn-brood.sh` with `lair_nonce`. It creates the detached worktree, writes `strain-settings.json`, `task.md` and the launch copy, and starts the session with the merge keys and marker removed.
3. **Run.** The overlord checks the marker, launches from `launch.json` verbatim, and the engine checks the copy and sets the level. The run delivers or remediates unattended, writes its engine record, and the overlord runs `lair-result.sh`.
4. **End.** The Lair ends the session when it reads a valid result, or on a crash, a stall or a budget overrun (Failure modes). It sends `/exit` to the pane, waits a 60-second grace period, then kills the session if it is still alive. It never waits on a push.
5. **Clean up.** After a fetch, when the worktree's head is on the remote, or no commit was made past the start commit, the Lair removes the worktree. Otherwise it keeps the worktree, records `unpushed_head` in the claim outcome, and names it in the queue report until the user removes it. The Lair never pushes for a strain. A kept worktree holds the branch, so the issue is not re-claimed while it exists, with reason `unpushed_work`.

The three start points are first claim, re-claim and remediation, as under Start points.

## Existing-path coverage

- **Interactive standard-delivery and pr-feedback-remediation** are unchanged when `HIVEMIND_LAIR_STRAIN` is unset or empty. `gather-facts.sh` prints `lair_strain: none`, the engine runs no launch check, and the level is today's default.
- **A non-Lair brood**, a `spawn-brood.sh` call without `lair_nonce`, keeps today's behavior, the settings copy and fresh-branch rule included.
- **`merge-approved.sh`, the review watch and interactive auto-merge** are unchanged. The strain's empty merge keys apply only in the strain session.
- **The `branch` launch arg** is optional. Without it `standard-delivery` plans as today.
- **The author filter** applies only with a verified marker.
- **The agent-call cap** applies only at the `unattended` level.

## Failure modes

These rows replace the parent design's Crash, Stall, `Stop` hook, `/exit` and Budget-overrun rows and add the launch failures.

| Failure | Detection | Resulting state |
| --- | --- | --- |
| Crash | `tmux has-session -t =<session>` fails and there is no valid result file. | `lair:failed`; the outcome `crashed` goes into the claim marker and counts toward the circuit breaker. |
| Invalid result | The result file fails the schema check, or its `claim_nonce` is not the claim's. | Treated as a crash. |
| Stall | The session is alive with no result, and either the idle marker is newer than the last activity and 5 minutes old, or the last activity is more than 30 minutes old. | The Lair ends the session (Lifecycle step 4); `lair:failed`, counted as a stall toward the circuit breaker. |
| A tool call that runs longer than 30 minutes | Looks like a stall by the activity rule. | Ended as a stall. Accepted: the window is a controller constant tuned in use. |
| The `Stop` hook does not fire while a workflow runs in the background | Found while building #604. | Fallback: the idle rule is off, and the activity rule and the wall-clock budget judge a stall. |
| Hooks from `--settings` do not fire on workflow agents' tool calls | Found while building #604. | Fallback: run activity cannot be observed, so both stall rules are off and the wall-clock budget alone ends a stalled run. |
| `/exit` sent through tmux does not end a session | The session is still alive after the 60-second grace period. | The Lair kills the tmux session, then cleans up as in Lifecycle step 5. |
| Budget overrun | Wall-clock time since the claim marker's `claimed_at` exceeds 6 hours, or the engine's agent-call cap ends the run with cause `agent_budget`. | The Lair ends the session without waiting. The issue becomes `lair:failed` (timed out), or is parked when a parked result was written first. A timeout counts toward the circuit breaker. |
| Unpushed work at session end | The worktree's head is not on the remote after a fetch. | The worktree is kept and named in the queue report. The issue is not re-claimed while it exists. |
| Start moved | After the switch onto `start.branch`, `HEAD` or the fetched remote head is not `start.commit`, the fetch fails, or the strain's push is refused as a non-fast-forward. | The overlord launches nothing; the result is `failed` with cause `start_moved`. The Lair handles it as a moved head: `lair:handoff` with reason `branch_moved` on a re-claim, `lair:review` (#631) on a remediation. |
| Marker unverified | The marker check prints `unverified`. | The overlord launches nothing, or the engine ends blocked with cause `lair_marker_unverified`. The result is `failed`. In an interactive session the run stops with that cause and the user removes the stray marker. |
| Launch mismatch | `lair-launch-check.sh` finds the engine's args differ from the Lair's copy. | The run ends `failed` with cause `launch_mismatch` before any planner call. |
| A refused or blocked engine launch | The `Workflow` call is denied, or the run ends blocked before its record. | No Instinct fallback. `lair-result.sh` writes `failed` with cause `no_engine_record`. |
| Moved head on a re-claim | The remote or local branch head differs from the parked head. | `lair:handoff`, reason `branch_moved`. |
| Moved head on a remediation | The pull request head differs from the last Lair result's head. | No strain; the pull request goes to `lair:review` (#631). |
| Superseded design on a re-claim | The review record stamps on trunk differ from the claim marker's `design_stamps`. | `lair:handoff`, reason `design_superseded`. |
| Unanswered park | An open park key has no admitted answer at re-admission. | Not claimed; queue report reason `park_unanswered`; no new label. |
| Decisions over the launch limits | More than 10 entries, or one over 2000 code points. | Not claimed; queue report reason `too_many_decisions` or `decision_too_long`; no new label. |
| A change that needs a `.claude` settings file | The deny rule refuses the edit. | The run parks or fails as the engine decides. Such an issue needs an interactive run. |
| Settings or launch write fails | `spawn-brood.sh` or the Lair cannot write a file, or the record is missing. | No session starts. The claim is reconciled by #632's rule for a claim that stopped before spawn. |

## Decisions

A decision that is not ADR-worthy names the [P20](../../engineering-principles.md) condition it fails.

- **One settings file per strain, passed with `--settings`, with the merge keys empty, and a launch environment without them.** ADR-0045 decision 4, as reworded by change 1 below; ADR-0010 for the precedence.
- **Deny rules are a barrier, not containment; the injected strain is a named residual.** ADR-0045 decision 4 as reworded by change 1, and PRD line 64 as reworded by change 2.
- **Three start points with detached worktrees.** ADR-0045 decision 3, as reworded by change 3.
- **A marker is verified against the Lair's record and the strain's worktree.** Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The level reaches the engine through the marker, read by `gather-facts.sh`, and the engine checks the launch args against the Lair's copy.** ADR-0045 decision 6 ("never by task text"). The mechanism is not ADR-worthy: fails P20's hard-to-reverse condition. #607 records it in an ADR-0037 amendment, because it changes ADR-0037's "an autonomy key is never read".
- **A delivery strain reads no issue text but the capture, and `gather-facts.sh` refuses refs the launch file does not name.** ADR-0045 decision 10.
- **A remediation strain's review text is filtered to in-scope Bots and write-access users.** Extends ADR-0045 decision 11's rule on outsiders to review text, with the in-scope Bot exception that change 5 adds to decision 11 and change 4 to the PRD. The filter mechanism is not ADR-worthy: fails P20's hard-to-reverse condition.
- **The result's decisions and gates come from the engine record.** Keeps ADR-0045 decision 5's one fixed script. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Run activity is the hook-touched activity file; stall windows of 5 minutes idle and 30 minutes inactive; a 6-hour wall-clock budget; an agent-call cap of 80 owned by #607.** ADR-0045 decision 17. The values are not ADR-worthy: each fails P20's hard-to-reverse condition.
- **Session end never waits on a push; unpushed work is kept and reported.** Not ADR-worthy: fails P20's hard-to-reverse condition.
- **A moved head or a superseded design hands the issue off; an unanswered park or over-limit decisions leave it unclaimed with no new label.** Extends ADR-0045 decisions 7 and 11 and the 2026-11-21 amendment's no-label rule. Not ADR-worthy: each fails P20's hard-to-reverse condition.
- **Remote control stays on for Lair strains, as a channel only the user's account holds.** ADR-0027. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The ADR-0045 residual "A prompt-injected strain holds the user's rights" is left as worded.** With change 1 applied, decision 4 calls the settings a barrier, and that residual names the risk this design keeps.

### Changes to shared documents

The user answered each change with option A, accepted 2026-11-21: changes 1 to 3 at design, changes 4 and 5 at the local review of this design. None is applied in this pull request. This design's own sections follow the accepted wording.

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

## Verification strategy

The tests are the PRD's [Testing Decisions](../../prds/autonomous-ready-issue-loop.md#testing-decisions). This section adds where each test of this scope lives and how it is registered.

- **Strain launch shell tests,** a new `tools/test_lair_strain.sh` (#604): Lair mode of `spawn-brood.sh` with tmux and `claude` stubbed, as `tools/test_brood_compat.sh` Assertion 9a does; the settings content (empty merge keys, marker, deny rules, hooks); the launch command string; no settings copy; the detached start commit for each start point; `start_moved` when the remote branch advances between the Lair's check and the overlord's switch; the refusals for a missing or reused nonce; the marker check's `none`, `verified` and `unverified` cases; and `lair-result.sh` with and without an engine record, its schema check and its single write.
- **`tools/test_brood_compat.sh`** gains the case that a call without `lair_nonce` is byte-for-byte today's spawn.
- **`tools/test_gather_facts.sh`** gains the marker cases: `lair_strain` lines, refused refs that differ from the launch file, and the author filter (#610).
- **`tools/test_fetch_normalize.sh`** gains the author filter cases (#610).
- **`tools/test_synapse_gate.sh`** gains the new runner command forms of `lair-launch-check.sh` and `lair-result.sh` (#604, #607).
- **Engine tests** in `tests/workflow-scripts/`: the level path (`none`, `verified` with a match, a mismatch, `unverified`), the `branch` launch arg and its plan check, the engine record at every end, and the agent-call cap (#604, #607).
- **Overlord prose tests.** `tests/workflow-scripts/overlord-contract.test.mjs` pins the new `plugin/agents/overlord.md` sentences: the marker check before the first launch, the verbatim launch from `launch.json`, no Instinct fallback, no Resume On Start question, no post-PR watch, a question turned into a `failed` result, `lair-result.sh` at run end, and the Lair strain branch rule. `tests/policy/safety-ask-set.json` gains the consumer pin for the Tier A edit. A new `tests/policy/safety-lair-strain.json` pins the security-policy edits for pre-spawn approval and strain settings, per the pin-authoring contract in `tests/policy/README.md`. #607 either fits `plugin/agents/overlord.md` within its byte budget in `tests/policy/prose-byte-budget.json`, or asks the user for a raise in `tests/policy/prose-budget-raises.json`.
- **Registration in `tools/validate.sh`.** Every new `tools/test_*.sh` named here, `tools/test_lair_strain.sh` included, is added in the same pull request to `KNOWN_SUITES`, `ALL_SUITES`, a `SUITE_*` constant, and a `map_path` rule for each script and fixture it covers, so `tools/validate.sh --self-test` passes and `--changed` selects it. Each new runner script and shared library is also added to the `test_workflow_scripts` route, as `synapse-gate.sh` is. New `tests/workflow-scripts/*.test.mjs` files need no registration: `tools/test_workflow_scripts.sh` runs the glob. New `tests/policy/*.json` fixtures run under `policy_check.sh`.
- **Headless checks,** recorded in an ADR-0010 amendment by #604: an empty `--settings` env value overrides a local one; each deny rule form refuses its command; `--settings` hooks fire on main-session and workflow-agent tool calls; the `Stop` hook during a background workflow; `/exit` through tmux.
- **The live smoke run** on a throwaway issue, by hand, as in the parent design, also checks that the strain's `env` shows both merge keys empty.

## Seam order

The build order is the parent design's. This design changes these slices; #605, #606 and #612 are not changed.

| Slice | What this design changes | ADRs |
| --- | --- | --- |
| #604 | Lair mode of `spawn-brood.sh`, the settings fragment and launch environment, the launch file and its check, start points, the `branch` launch arg, the marker check, `lair-result.sh` and the engine record, liveness hooks, the overlord branch rule and the strain-settings governance edit | ADR-0045 decisions 3, 4 and 5; ADR-0007; ADR-0010; ADR-0017; ADR-0019; ADR-0021; ADR-0027; ADR-0028; ADR-0037 |
| #607 | the level path into both engines, the agent-call cap, the Tier A and user_gate edits, and the overlord's strain-run prose | ADR-0045 decisions 6, 7, 8 and 17; ADR-0026; ADR-0029; ADR-0030; ADR-0036; ADR-0037; ADR-0039; ADR-0040 |
| #608 | the pre-spawn approval edit, the writes before spawn, session end, stall and budget detection, and unpushed-work handling | ADR-0045 decisions 10 and 17 and the 2026-11-21 amendment; ADR-0007; ADR-0017; ADR-0026 |
| #609 | the settled-decision entry form and limits, the re-claim start point, moved head, superseded design and unanswered park | ADR-0045 decisions 7, 11 and 16; ADR-0037 |
| #610 | the remediation start point, args and author filter, and the review text scan | ADR-0045 decision 13; ADR-0040; ADR-0043 |
| #611 | the digest takes decisions from the result, which comes from the engine record | ADR-0045 decision 14; ADR-0026; ADR-0030 |

## Open questions

None

## Amendments

This design was written on 2026-11-21, after the user accepted the three changes under Decisions. Those changes are not applied in this pull request. Later changes to this design are appended here as dated entries.

- **2026-11-21, local review.** The user chose option A for the remediation author filter: an in-scope reviewer Bot counts as trusted without a write-permission check. Changes 4 and 5 propose the matching PRD and ADR-0045 decision 11 wording.
