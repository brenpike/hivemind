# Permission-allowlist posture and Claude Code permission-engine behavior

**Status:** accepted — 2026-05-24

The hivemind workflow generated excessive permission-elevation prompts. A log study of 162 session transcripts (2,440 tool calls) found ~1,023 default-mode would-prompts; the single largest source was decorative `echo` banners (see **Amendment — 2026-05-25**: this attribution was later corrected). This ADR captures the least-privilege allowlist posture we adopted to reduce them and — load-bearing — the empirically established Claude Code permission-engine behavior that justifies it, so a false premise that drove ~6 review iterations of churn does not get re-litigated.

## Context

The reduction effort had three levers: a project `.claude/settings.json` `permissions.allow` allowlist, an opt-in `setup-project` seed template, and agent-prose changes that suppress decorative shell output at the source.

A FALSE belief drove the churn: that a `Bash(<prefix> *)` rule auto-approves a "redirect-write tail" (e.g. `echo x > /etc/passwd`), making read/output-helper grants an arbitrary-file-write vector. Acting on this premise, echo/printf/cat/sort were repeatedly removed and re-added across review iterations. The premise is false; the findings below establish why.

## Findings — Claude Code permission-engine behavior

Empirically established by source-analyzing the installed Claude Code v2.1.150 binary and the official docs at code.claude.com/docs/en/permissions. The load-bearing facts:

- After a Bash prefix rule yields `allow`, CC runs a redirect/path validator that RE-PROMPTS (`ask`/`deny`) on ANY write or redirect to a path OUTSIDE the session working directory (plus configured additional dirs). Only `> /dev/null` is exempt.
- CC splits compound commands on `&&`, `||`, `;`, `|`, `|&`, `&`, and newlines, and requires EACH subcommand to match an allow rule independently.
- `cd` into the working tree is auto-allowed without a rule.
- Over-broad wildcard rules such as `Bash(cd:*)` are a footgun (the trailing `*` swallows `&& rm -rf …`), but a clean `Bash(jq *)`-style prefix does not have this problem.
- Tool-intrinsic write flags not in CC's safe-flag tables (e.g. `sort -o`) re-prompt. A minor read/write misclassification exists (`uniq in out` labels the output arg as read) but stays bounded to readable/in-cwd paths.

CONSEQUENCE: a `Bash(cmd *)` read/output-helper grant is NOT an arbitrary-file-write vector. The only silent write it permits is into the working directory — uniformly true for jq/head/ls as for echo/printf/cat/sort. The earlier "redirect-write tail" premise was false.

- **NON-FINDING (open question, recorded 2026-08-24).** Whether a skill's `allowed-tools` entry — for example `Bash(node *)` — suppresses the permission prompt for a provider binary invoked via node, including in a subagent context, is NOT established by this ADR's evidence. No surface in this repository may assert it until it is verified empirically against an installed Claude Code binary and the official permissions documentation. The consumer-correct instruction is UNAFFECTED either way: the per-contributor grant in the gitignored `.claude/settings.local.json` is correct regardless of how the question resolves.
- **AUTHORITY (scoped to the open question).** The prohibition above binds ONLY that unverified question: no surface — this one included — may state an answer to it until it is verified and recorded here. It is NOT a general claim that every permission-engine statement in this repository must live in this section. Engine facts already VERIFIED and recorded elsewhere STAND exactly as written and are NOT conscripted into compliance by this designation: `plugin/governance/security-policy.md` (a skill's `allowed-tools` entry pre-approves a tool but never PROVISIONS it, the calling agent's `tools:` is the ceiling, and plugin frontmatter cannot path-scope a `Write` grant), ADR-0013 (`allowed-tools` only pre-approves and cannot restrict a skill), and ADR-0018 (the same non-path-scoping fact, as its enforcement model) are correct and mutually consistent with these Findings — several of them recorded by this ADR's own **Amendment — 2026-07-27**. Do not "clean up" those documents against this bullet. What this section remains authoritative for: a NEW engine claim not already verified and recorded elsewhere is established and recorded HERE first, and other surfaces then operationalize the resulting instruction or point here.

## Decision — allowlist posture

1. GRANT read/output helpers: `jq`, `head`, `tail`, `ls`, `wc`, `sort`, `uniq`, `cat`, `echo`, `printf`, `grep` (read-only; `Bash(grep *)` supersedes the narrow `grep -n`/`-rn`/`-rE` forms — see **Amendment — 2026-05-25**).
2. GRANT scoped git reads: `git ls-files`, `git grep`, `git ls-tree` (read-only object lister), `git tag` (list-only forms: bare, `-l*`, `--list*`), `git stash list`, `git stash show *`.
3. EXCLUDE — for GENUINE reasons, NOT the debunked one:
   - `Bash(node *)` — arbitrary code execution.
   - `Edit` / `Write` / `acceptEdits` — broad unprompted write.
   - `Bash(find *)` — `-delete` / `-exec` deletion and arbitrary execution.
   - `Bash(git switch *)` — `-f` discards uncommitted changes.
   - broad `Bash(git stash *)` — `drop` / `clear` / `pop` lose work.
   - broad `Bash(git tag *)` — `-d` / `-f` mutate tags.
4. Decorative shell output (section banners, progress narration, terse status tokens) is suppressed at the source via agent-prose directives (cerebrate, local-reviewer, drone, overlord, github-reviewer) rather than by granting echo — ~93% of echo/printf prompts were gratuitous scaffolding. Load-bearing `printf` routing-data emissions (the pipeline-skill contract output) are exempt.
5. `setup-project` seeds this least-privilege set via the `seed_allowlist` input, which now **defaults to `yes`** — the least-privilege template is union-merged by default and consumers opt OUT via `seed_allowlist=no` (append-if-absent; never overwrites, removes, or reorders a consumer's existing entries). See **Amendment — 2026-05-29**.
6. The follow-up issue proposing to harden pipeline-skill `printf` routing emission (#123) was CLOSED: it rested on the same debunked arbitrary-write premise; skill-level `printf` is not an arbitrary-write vector.

## Considered Options

| Option | Rejected because |
|---|---|
| Omit echo/printf/cat/sort from the allowlist to avoid the "redirect-write tail" | Premise false: CC re-prompts on out-of-cwd writes/redirects and splits compound commands, so these grants are no more write-capable than jq/head/ls; omitting them just keeps the prompt noise |
| Grant `Edit`/`Write`/`node`/`find` to cut more prompts | Genuine arbitrary-write or arbitrary-execution surface; excluded on real risk, not the debunked premise |
| Grant echo to silence banner prompts | Treats the symptom; ~93% of those prompts are gratuitous scaffolding better removed at the source via agent prose |
| Harden pipeline-skill `printf` routing emission (#123) | Rests on the debunked arbitrary-write premise; skill-level `printf` is not an arbitrary-write vector — issue closed |

## Consequences

- Materially fewer permission prompts, plus a documented rationale that prevents re-litigating the false premise (it recurred across multiple review iterations).
- The in-cwd redirect-overwrite is an ACCEPTED, bounded surface, uniform across all Bash grants. Defense relies on CC's out-of-cwd re-prompt and on deny rules — not on omitting read/output helpers.
- A future redesign of routing-data emission (non-shell / exact-match invocation) remains OPTIONAL; it is not required for safety.

## Amendment — 2026-05-25

> Active end-state (Decision #4 echo-banner suppression lever only): the compound-command-batching attribution in this 2026-05-25 amendment. The allowlist-posture decision in this ADR still governs; only Decision #4's agent-prose suppression lever is superseded.

This amendment refines the DIAGNOSIS recorded above. It does not rewrite the accepted record: the False-premise narrative, the engine Findings, the Considered Options, and the Consequences all stand. A 2026-05-25 24h log study (93 Bash calls) corrected the root-cause attribution and a remediation shipped accordingly.

- **Corrected attribution.** The 2026-05-24 framing that "decorative `echo` banners are the single largest source" of permission prompts was a misattribution. `echo` was ALREADY allowlisted, so banner echos never triggered a prompt on their own — the banner is a CORRELATED SYMPTOM, not the cause. Decision #4's agent-prose suppression lever therefore could not reduce the prompts and is SUPERSEDED for that purpose.
- **Actual mechanism.** COMPOUND-COMMAND BATCHING. CC splits a compound command (`&&` / `||` / `;` / `|` / newline) and matches each subcommand independently; one unlisted segment forces a prompt for the whole chain. 51 of 61 (84%) banner-decorated commands contained such an unlisted chain-mate. Measured unlisted triggers: `grep` flag near-misses (`grep -c`, `grep -v`, `grep -E`, `grep -nE`, `grep -rln`, `grep -rEn` — the seed had only `grep -n` / `grep -rn` / `grep -rE`), `git ls-tree`, and repo validation invocations (`bash tools/policy_check.sh`, `bash tools/validate_reports.sh`, `bash -n`).
- **Remediation (shipped v2.8.2 / PR #132).** Static allowlist widening only: added `Bash(grep *)` and `Bash(git ls-tree *)` (both read-only) to the seed. Repo-local `bash ...` validation grants were kept OUT of the consumer seed. No hook, no new behavioral prose.
- **Engine model unchanged.** The engine facts in the Findings section remain valid and load-bearing — the out-of-cwd write/redirect re-prompt and the compound-command split behavior are exactly what this amendment leans on. `grep` and `git ls-tree` are read-only and safe for the same engine reasons; the debunked "redirect-write tail" premise stays debunked.

## Amendment — 2026-05-29

The `seed_allowlist` input default FLIPPED from `no` to `yes` (Decision #5 above updated in place). This makes least-privilege seeding the out-of-the-box behavior: the recommended template is union-merged into the consumer's `.claude/settings.json` unless `seed_allowlist=no` is passed.

- **Merge semantics unchanged.** Append-if-absent / union only — existing consumer entries are NEVER overwritten, removed, or reordered. Re-running is idempotent.
- **Seeded surface unchanged.** Still seeds only read/output helpers, scoped git reads, and the codex-companion node entry. Still seeds NO `acceptEdits` / `Edit` / `Write`.
- **Opt-out preserved.** Consumers retain full opt-out via `seed_allowlist=no`.
- **Safety rationale unchanged.** The template is safe to default-on for the same engine reasons recorded in Findings: Claude Code re-prompts on any write/redirect to a path outside the working directory and splits compound commands, so each granted helper's only silent write is bounded to the working directory. The debunked "redirect-write tail" premise stays debunked.

## Amendment — 2026-07-27

Decision #3's exclusion of BROAD `Edit`/`Write` grants STANDS. One narrow exception is admitted, and one engine fact about rule spelling is corrected.

- **Narrow exception.** The orchestrator's own agent definition (`plugin/agents/overlord.md`) now carries `Write`; `Edit` stays absent. It is bounded to the fixed-literal inputs-file transport paths under the gitignored `.hivemind/` tree (Inert Inputs-File Navigator Pattern, `plugin/governance/security-policy.md`). Reason: a skill's `allowed-tools` PRE-APPROVES a permission but never PROVISIONS a tool, and the calling agent's `tools:` is the ceiling — so the transport several skills documented was unreachable, and the ADR-0017-forbidden heredoc fallback was being used instead on every ledgered state transition.
- **Rule spelling (verified).** From Claude Code 2.1.210 onward a `Write(<pattern>)` allow rule is ACCEPTED but NEVER MATCHED by file permission checks; only `Edit(<pattern>)`/`Read(<pattern>)` rules are, and `Edit` rules cover every file-editing tool including Write. Verified against the official permissions documentation and the installed 2.1.220 binary (warning string `is not matched by file permission checks — only ${a}(path) rules are`). The RULE namespace and the TOOL namespace are different things: an `Edit(...)` rule does NOT grant the `Edit` tool.
- **Consequence.** This repo's pre-existing `Write(.hivemind/review-loop/*)` rule in `.claude/settings.json` is ineffective as written; it takes effect only spelled `Edit(.hivemind/review-loop/*)`.

## Amendment — 2026-08-24

The codex-companion node entry is REMOVED from the `seed-hive` permissions template. This SUPERSEDES the **Amendment — 2026-05-29** bullet "Seeded surface unchanged" insofar as that bullet names the codex-companion node entry as part of the seeded surface; the rest of that amendment (merge semantics, opt-out, safety rationale) stands.

- **The entry was UNMATCHABLE AS SHIPPED.** The seeded rule was `Bash(node /path/to/.claude/plugins/cache/openai-codex/codex/*)`. `/path/to/` is a documentation placeholder that was frozen into runtime data by a single-quoted heredoc in `plugin/skills/_shared/settings-merge.sh`, so it was never expanded to a real `$HOME`. The rule therefore matched no invocation on any machine and never granted anything to anyone — it was dead text in every consumer's committed `.claude/settings.json`, re-added on every re-seed.
- **Standing rule.** No local-review provider grant — `codex` today, or any future provider (a `copilot` adapter or otherwise) — may be seeded into the committed `.claude/settings.json`. Two reasons: (a) that file is committed and team-shared, so a machine-specific `$HOME` cache path is wrong for everyone but the seeder; (b) per-contributor grants belong in the gitignored `.claude/settings.local.json`, which is what `.devcontainer/postCreate.sh` already does.
- **This REINFORCES Decision #3.** Decision #3 excludes `Bash(node *)` from the seeded allowlist for arbitrary-code-execution reasons. Removing a provider-specific `node` grant from the seed keeps that exclusion whole.
- **Append-if-absent consequence.** Because merge semantics are union-only (never remove, never reorder), already-seeded consumers RETAIN the dead entry until they delete it by hand. Automatic removal is DELIBERATELY not implemented: it would break the never-remove invariant recorded in **Amendment — 2026-05-29**, and it could delete a rule a user had already repaired to their real `$HOME`.

## Amendment — 2026-08-25

While fixing issue #352 (the seeded caveman `SubagentStart` hook command was cwd-relative), a sibling finding surfaced: the six seeded `Edit(.hivemind/...)` permission-template rules share the same relative-path shape as the hook command fixed there, and come from the same seeding template. This amendment records the investigation as a **NON-FINDING (recorded 2026-08-25)**: investigated, deliberately scoped out of that fix, decision made below.

- **Observation.** The six seeded `Edit(.hivemind/...)` rules carry the same relative-path shape as the hook command fixed in #352, and come from the same template.
- **Why the impact is materially lower.** Permission allow rules are PROMPT PRE-APPROVAL ONLY, with no deny semantics: an absent or non-matching rule yields an interactive prompt, never a refusal (`${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md`). A relative `Edit(.hivemind/...)` rule that fails to match from a different invocation cwd degrades to the same interactive prompt a consumer would see with no rule at all — it neither silently denies the edit nor silently grants anything it should not.
- **Why no correct anchoring primitive exists.**
  - Permission-rule patterns perform NO `${...}` expansion. An anchored rule built on `${CLAUDE_PROJECT_DIR}` would not have the variable resolved; it would instead match only a literal directory named `${CLAUDE_PROJECT_DIR}` on disk, which does not exist, and would therefore silently grant NOTHING — strictly worse than the current spurious prompt, because the failure carries no visible signal.
  - A leading `/` anchors to the session's ORIGINAL cwd, not the project root, so it does not correct the relative-path shape either — it only relocates which cwd the match depends on.
  - `Bash(...)` rule content is matched as command TEXT, never resolved as a path. A `Bash` rule whose command text happens to redirect into `.hivemind/` is a different class of entry entirely and must be left alone; treating it as a path-anchored rule and rewriting it would not change what it matches.
- **Decision.** The six `Edit(.hivemind/...)` rules stay relative. No fix is required or planned for this NON-FINDING.

---

## Naming update (2026-05-27)

The `setup-project` skill referenced in this ADR has been renamed to `seed-hive`. The substantive decision recorded here (permission-allowlist posture) is unchanged; only the skill identifier rotated. Legacy invocations continue to match via trigger aliases.

## Amendment 2026-10-20: tool grants and prompts for workflow agents

This amendment records engine facts verified on Claude Code 2.1.304 for agents that run inside a workflow script, and for the agent tool lists those agents get. Decisions 1 to 6 are unchanged: nothing here adds, removes or widens a grant. The permission posture of the new workflow script engine (which rules are seeded, how runs launch and resume, where trunk safety sits) lives in ADR-0037 (`docs/adr/0037-standard-delivery-on-script-engine.md`), not here.

Evidence:

- The S11 and S12 spikes, run 2026-10-20 UTC against throwaway repos with local bare remotes. Results are in `~/code/hivemind-workflow-spikes/results-s11s12.md`, outside this repository, with the raw transcripts under its `s11/logs/` and `s12/logs/`. Each verdict is read from the `permissionDecision` field on the tool result and from the tool list in the API request, not from what the model said. S11 ran in manual mode (`--permission-mode default`); S12 ran in auto mode (`--permission-mode auto`).
- A cerebrate run on the same version, spawned through the Agent tool and not inside a workflow.
- The official docs at code.claude.com/docs/en/sub-agents and code.claude.com/docs/en/tools-reference.

These facts are tied to 2.1.304. A later version may change them.

- **A `Bash(<pattern>)` entry in an agent's `tools:` grants the whole Bash tool (S11-b).** An agent with `tools: Read, Bash(git status *)` got the full Bash tool; its tool list was `Read, Bash, StructuredOutput, advisor`. `git status --short` ran with no prompt. `touch`, which is outside the pattern, got a normal permission prompt and not a refusal. The sub-agents docs define no `Bash(...)` specifier for `tools:`; the only specifier they document is `Agent(...)`. So the pattern does not restrict the agent: a command outside it prompts in manual mode and goes to the classifier in auto mode. This also holds for cerebrate, whose `Bash(git ...)` and `Bash(gh ...)` entries do not limit its Bash.
- **Glob and Grep are present only when the agent lists them and has no Bash (S11-c).** An agent with `tools: Read, Glob, Grep` got both (tool list `Read, StructuredOutput, Glob, Grep, advisor`), and both ran with no prompt. Every agent that had Bash lost them, even when it declared them. This matches the tools-reference docs, section "Glob tool behavior": on macOS, Linux and WSL, Glob and Grep are left out of the default tool set and searches run as Bash `find` and `grep`; a subagent gets them back only when its `tools` field lists Glob or Grep and leaves out Bash. The cerebrate run showed the same outside a workflow: Read, WebSearch, WebFetch, Bash and the hand-back tool, with no Glob or Grep.
- **LSP is inactive without a code-intelligence plugin.** The tools-reference docs, section "LSP tool behavior", say Claude Code keeps the LSP tool inactive until a code intelligence plugin for the language is installed. None was installed in these runs, and no agent had LSP. `hivemind:drone` declares Glob, Grep and LSP and also has Bash; its tool list was `Read, Write, Edit, Bash, WebSearch, WebFetch, Skill, StructuredOutput, advisor`, with no Glob, Grep or LSP.
- **`git -C <dir> status` prompts where `git status` does not (S11-b, S11-h).** In manual mode `git status --short` ran with no prompt and `git -C <repo> status --short` prompted. Cerebrate's `git -C <repo> ...` reads in S11-h prompted on every call.
- **S11-a: a skill's exact-path script grant applies inside a workflow agent.** A test skill's `allowed-tools` held `Bash(bash <plugin root>/skills/probe-skill/scripts/probe.sh *)`. A workflow agent invoked the skill and then ran that script with no prompt (`reasonType: subcommandResults`). A control agent that ran the same command without invoking the skill got a prompt, so the grant came from the skill. The Skill call itself prompted once, in the main session and marked as coming from the workflow, because no `Skill(...)` rule existed. The same script grant applied in auto mode (S12). Scope of this finding: one grant shape (`bash`, an exact script path, a trailing `*`), run by a workflow agent, for a script that starts no provider binary. This finding does not settle the NON-FINDING recorded in the Findings section. That open question is about a `node` wildcard grant that launches a provider binary, including in a subagent context, and S11-a tested none of those. The open question and its prohibition stand as written.
- **S11-d: a workflow agent's Read of plugin files prompts, and a project Read rule stops it.** With no rule, all 3 Reads outside the repo prompted, including a plugin skill file and hivemind's `governance/definitions.md`; the Read inside the repo did not. With `Read(//<plugin dir>/**)` allow rules for the plugin folders in the project's `.claude/settings.local.json`, the plugin Reads ran with no prompt (`reasonType: rule`), and a Read outside the repo that was not under a plugin folder still prompted. The test loaded the plugin with `--plugin-dir`. A real rule must name the folder the plugin resolves to at runtime, which for a marketplace install is the install path.
- **S11-e: a `Workflow(<name>)` rule covers resume by name, not resume by scriptPath.** Answering "don't ask again" on a workflow approval prompt wrote `Workflow(<plugin>:<workflow>)` to the project's `.claude/settings.local.json`; user settings did not change. Two resumes of the paused run with `Workflow({name, resumeFromRunId, args})` then ran with no approval prompt, and the agent that had already finished was served from cache. A resume through `scriptPath` on the persisted script copy, which is the path the model took when not told otherwise, raised a fresh approval prompt with no "don't ask again" option, and the rule did not cover it.
- **S11-f: a `Skill(<plugin>:<skill>)` allow rule stops Skill prompts in the main session and in workflow agents.** In the main session, invoking a test skill and `hivemind:route-workflow` raised 2 prompts with no rule and 0 with the rules. In workflow agents, every Skill call under the rule was accepted with `reasonType: rule`.
- **S11-h: `--disallowedTools Workflow` removes the tool.** In a session started with `--agent hivemind:overlord --disallowedTools Workflow`, the tool list had no Workflow tool. The overlord said so in one line and ran analysis-only on the state machine to `complete`.
- **S12: in auto mode, scripted commit, push and PR steps from workflow agents ran with 0 prompts.** An untyped haiku agent and a haiku `hivemind:drone` each ran a commit, the scripted push of a working branch through `hivemind:push-branch`, and `gh pr create --dry-run`, with no prompt and no block. The git commands and the Skill call were classifier accepts. The push script was accepted through the skill's grant (`reasonType: subcommandResults`), the same path as in manual mode. `gh pr create --dry-run` exited 1 before any GitHub call because the remote was a local path; that shows the command was not blocked, not what it prints against GitHub. The workflow launches were pre-approved by `Workflow(...)` rules, so auto mode's own launch prompt was not observed.
- **S12: the auto-mode classifier allowed a raw push to the default branch.** A workflow agent ran `git push origin HEAD:main`. The classifier accepted it (`reasonType: classifier`) and the push landed on the remote's `main`. Nothing in the permission engine stopped it. A `hivemind:drone` given the same task declined on its own because no grant named a push to main; that comes from the agent's prompt, not from a permission control.
- **Correction to the S11-d bullet above: what the test covered.** Its heading calls the rule "a project Read rule". The rule was in the project's gitignored `.claude/settings.local.json`, which Claude Code treats as local settings, not in the committed `.claude/settings.json`, which it treats as project settings. S11-d also used an untyped haiku workflow agent, loaded the plugins with `--plugin-dir` from folders outside the repo, and tested only absolute `//` rules. It establishes nothing about a rule in `.claude/settings.json`, a `~/` rule, a plugin installed from a marketplace into the plugin cache, or a typed hivemind agent. That check moved to the slice 2 PR8 live smoke (ADR-0037, Deferred items) and will record its result here before the seed template gets a Read rule.
