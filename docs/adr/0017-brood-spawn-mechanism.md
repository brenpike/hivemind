# Brood spawn uses detached tmux sessions, explicit worktree creation, and two-pass injection

**Status:** accepted — 2026-05-30

ADR-0007 deferred the brood SPAWN MECHANISM. The first real launch exposed that `claude --worktree --tmux` is unusable from a non-TTY Bash tool context and mangles branch names; this ADR records the mechanism that replaced it.

## Context

Five root-cause failures emerged at first launch:

1. `claude --tmux` requires a real terminal; the Bash tool provides none → "open terminal failed: not a terminal".
2. `claude --worktree <NAME>` derives `worktree-<NAME>` as the branch name and mangles slash-separated names — never the intended strain branch.
3. Foreground `claude --tmux` never returns; a sequential spawn loop hung on strain #1.
4. Detached children have no human to approve Claude Code permission prompts.
5. `printf '%q' | tmux send-keys` mangled multi-line task strings.

## Decision

1. **Worktree creation:** `git worktree add -b <exact-strain-branch> <path> <base>`. The `base` input (resolved trunk SHA/ref) is passed by the hatchery and recorded in the brood manifest; worktrees branch off it exactly.
2. **Session launch:** `tmux new-session -d` (detached) running `claude --dangerously-skip-permissions --settings '{"skipDangerousModePermissionPrompt":true}'`. The detached session supplies a PTY. The settings injection pre-accepts the one-time "Bypass Permissions mode" trust gate non-interactively, avoiding screen-scraping.
3. **Spawn topology:** two-pass — pass 1 launches all strain sessions in parallel; pass 2 polls each session for readiness then injects its task.
4. **Task injection:** each strain task is written to a temp file; delivered via `tmux load-buffer <file>` + `paste-buffer` + Enter. Bypasses send-keys quoting entirely.
5. **Readiness detection:** `tmux capture-pane` polled until the pane contains the string `hivemind:overlord` (READY_TIMEOUT=90 s, POLL_INTERVAL=2 s).
6. **Cleanup split:** hard failures before launch → kill session + remove worktree; post-launch timeout/inject failures → leave session alive, mark strain `failed` in manifest (recoverable by user).

## Considered Options

| Option | Rejected because |
|---|---|
| `claude --worktree <NAME> --tmux` directly | Requires a TTY the Bash tool cannot provide; mangles branch names |
| Foreground serial spawn | Blocks on strain #1 indefinitely; no parallel boot |
| Screen-scrape the bypass-permissions gate + keystroke injection | Brittle TUI coupling; the settings key `skipDangerousModePermissionPrompt` is a stable contract |
| `tmux send-keys` with `printf '%q'` escaping | Mangled multi-line prompts; quoting complexity grows with prompt content |

## Consequences

- ONE remaining TUI coupling: the `hivemind:overlord` ready-detection substring. If the overlord prompt changes, READY_TIMEOUT exhausts before injection. This is a documented maintenance point.
- `--dangerously-skip-permissions` widens child blast radius (consistent with ADR-0007: unattended children run the full standard pipeline with no human in the loop).
- New `base` input on `spawn-brood` and top-level `base` field in the brood manifest.
- Naming is now deterministic: tmux session `brood-<short-id>`, worktree `.claude/worktrees/<short-id>`.

## Amendment — 2026-05-30 (PR #154)

The bypass-mode blast radius above interacts with untrusted input: a strain task description may be sourced from a GitHub issue body and pasted into the child prompt, while the detached child has no interactive permission gate. Two compensating controls now mitigate the brood injection surface (defense-in-depth), plus a structural backstop:

1. **Data-boundary preamble in `task.md`** — `hivemind:spawn-brood` prepends the canonical external-content data-boundary preamble above the description payload (inside the same heredoc), so it is injected ahead of every strain description.
2. **Pre-spawn human approval of normalized task text** — the overlord brood gate (`overlord.md` steps 3a/3b) surfaces the normalized `{name, description}` task text to the human for explicit approval before spawn; with no downstream permission prompt, this approval is the injection gate.

Partial structural backstop (scoped to product-file mutation): the child is itself a delegating overlord whose `tools:` carry no `Write`/`Edit`, so embedded instructions that would mutate product files still route through branch → checkpoint → review → PR rather than direct file writes (Write-Capable Skill Containment, `plugin/governance/security-policy.md`). It does NOT contain all execution — the child holds `Bash` and runs `--dangerously-skip-permissions`, so a surviving injected instruction could drive Bash directly; the three compensating controls (preamble, human approval, allowlist) remain the real boundary. Status remains accepted.

## Amendment — 2026-05-30 (PR #154, I/O-primitive change)

The brood file writes (`task.md` and `manifest.yaml`) migrate from shell heredoc to the **Write tool**. Embedding untrusted text in heredoc syntax was the wrong primitive: `cat > file <<"$DELIM"` does NOT parameter-expand the delimiter word `$DELIM` (a quoted heredoc word is taken literally), so the "per-call random delimiter" scheme never actually randomized — the literal token `$DELIM` was the real delimiter on every spawn, and a payload line equal to the literal `$DELIM` would terminate the heredoc early and execute the subsequent lines in the hatchery shell. This is the same injection class the random-delimiter scheme was meant to close.

Decision:

1. **Write tool for both files.** `task.md` and `manifest.yaml` are each written with a single Write tool call. Write performs no shell parsing of untrusted bytes, eliminating the heredoc-delimiter injection class entirely (no delimiter to collide with, no path to hatchery-shell execution). The Write tool emits no chat text, so Silence Discipline is preserved (it is a permitted non-final tool call; the final routing/exit Bash call still follows).
2. **YAML validity is assured by the block-scalar discipline, not the removed delimiter.** Every manifest scalar derived from planner output, issue text, or a filesystem path is emitted as a YAML literal block scalar (`|`); only fixed-shape trusted literals stay inline. The sole residual YAML-authoring rule: an embedded newline inside an untrusted value must be reproduced indented to the block scalar's content indent. Refinement (2.17.5): exact-value fields (`name`, `branch`, `base`, `worktree_path`) use `|-` (strip chomping) so the parsed value has no trailing newline, and `hivemind:brood-status` double-quotes every manifest value it interpolates into a shell command — block scalars give YAML-injection safety, `|-` gives exact values, consumer quoting gives shell safety.
3. **P1 linked-worktree exclude-path fix.** Pre-flight 1f's repo-local exclude path is now resolved via `git rev-parse --git-path info/exclude` instead of a hardcoded `<repo_root>/.git/info/exclude`, which is wrong in a linked git worktree (`<repo_root>/.git` is a gitdir-pointer FILE, not a directory) — a supported context under recursive brood (a spawned child overlord spawning from a worktree).

Considered and rejected: a TRUE YAML serializer (`python3 -c 'import yaml; yaml.safe_dump(...)'` or `yq`). Rejected because (a) it adds a runtime dependency not guaranteed on consumers, and (b) passing untrusted input into a `-c` program reintroduces the same injection class unless the values are first written to files — which is the Write-tool primitive again. The Write tool is therefore the correct and sufficient primitive; the serializer fallback is recorded here only and is NOT placed in the SKILL body.

The prior amendment's "inside the same heredoc" phrasing for the `task.md` preamble is superseded by the Write-tool primitive (recorded here as an append; prior text is left intact). Status remains accepted.

## Amendment — 2026-05-30 (PR #154, shell-injection class closure)

Prior fixes leaned on "double-quote every dynamic token" as the shell-safety story. That is wrong: **double-quoting is not a shell-safety encoding.** When untrusted LITERAL bytes appear in the SOURCE of a command the agent hands to the Bash tool, bash command substitution `$(...)`, backticks, and `${}` STILL expand even inside double quotes. `git check-ref-format --branch` ACCEPTS branches like `feat/x$(touch${IFS}/tmp/pwn)`, so emitting `git check-ref-format --branch "feat/x$(touch...)"` runs `touch` before git ever validates the ref. Quoting stops only word-splitting and globbing.

Decision (closes the entire shell-injection class on `branch`/`base`):

1. **Agent-reasoning allowlist gate (primary).** `hivemind:spawn-brood` adds an **Input Validation Gate** applied by the agent in its OWN reasoning — the model matches each `branch`/`base` value against the literal rule `^[A-Za-z0-9._/-]+$` (non-empty, not starting with `-`, no `..`) BEFORE any Bash call, so raw untrusted bytes NEVER enter generated shell source. Only an already-clean value is ever placed into a (still double-quoted) shell token. The charset excludes every shell-special byte while keeping real branches valid (`feat/x.y`, `release/1.2.3`, `bugfix/foo-bar`).
2. **Derived values safe-by-construction.** `short` (sanitized `[a-z0-9-]`), `worktree_path` (`<repo_root>/.claude/worktrees/<short>`), and `tmux_session` (`brood-<short>`) carry no untrusted bytes and need no gate; they are quoted as defense-in-depth only.
3. **brood-status re-gates the manifest branch.** `hivemind:brood-status` re-applies the SAME allowlist (in agent reasoning) to every manifest value before its first shell use, skipping a strain's probes and reporting `blocked (branch failed safety allowlist)` on failure while continuing other strains. Defense in depth — the consumer does not trust the manifest file even though spawn-brood's gate should have prevented an unsafe value.
4. **`check-ref-format` demoted to defense-in-depth.** It runs AFTER the gate as ref-SHAPE validation on an already-safe value; it is never the shell-safety boundary (it accepts injection-bearing names).

Considered and rejected as PRIMARY: the out-of-band approach (Write-then-`cat`, or read into a shell variable referenced only as `"$var"`, which is inert because bash does not re-evaluate command substitution from variable contents). Recorded as a documented fallback only — rejected as primary because no real branch needs a forbidden byte, and clean rejection of a hostile name beats faithful execution of it. Status remains accepted.

## Amendment — 2026-05-30 (PR #154, behavior-preserving structural refactor)

The deterministic shell that `hivemind:spawn-brood` previously hand-templated in
its SKILL.md body is extracted into one committed script,
`plugin/skills/spawn-brood/scripts/spawn-brood.sh`. Same inputs produce identical
worktrees, sessions, manifest, and exit codes — no observable-behavior change.

Decision:

1. **File-based Write-tool inputs parsed by jq into inert variables.** The agent
   authors a single JSON inputs file (`.hivemind/brood/inputs.json`) with the
   Write tool; the script parses it with `jq` into shell variables referenced only
   as `"$var"`. This makes the command-substitution injection class STRUCTURALLY
   closed by architecture rather than per-snippet quoting: untrusted bytes never
   enter generated command source, and bash does not re-evaluate command
   substitution from variable contents. The round-7 allowlist gate is retained in
   the script as defense-in-depth ref-shape validation, no longer load-bearing.
2. **`jq` is now a required runtime dependency** (READ-only, for inputs parsing).
   The script blocks with a verbose `blocker: jq is required …` + exit 1 if
   absent, alongside the existing `tmux`/`claude` checks. ADR-0017's earlier
   rejection of a true YAML serializer for manifest WRITING still holds — manifest
   emission stays `printf` block-scalar.
3. **SKILL.md slimmed to a ~4-step navigator with the inputs schema inline.** The
   skill body is now ~4 imperative steps (build inputs → Write file → run script →
   interpret exit), and the authoritative inputs schema lives inline in that body.
   The security WHY, three-layer manifest model, block-scalar chomping reasoning,
   and ready-substring maintenance point are documented in this ADR and in the
   script's own header comments — not in a separate doc. The broad `allowed-tools`
   Bash grants collapse to the single precise
   `Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/spawn-brood/scripts/spawn-brood.sh *)`
   grant plus `Read`/`Write`, matching the `github-review-loop` precedent.

Status remains accepted.

## Amendment — 2026-05-30 (PR #154, filesystem-path out-of-band + tmux paste/buffer hardening)

The round-7 shell-injection closure (allowlist gate) covered `branch`/`base` but left filesystem PATHS treated as "safe-by-construction because `repo_root` came from `git rev-parse`" / "the user's own filesystem path, not in the threat model." That carve-out is SUPERSEDED and was wrong: the checkout DIRECTORY NAME is filesystem-controlled and can legally contain shell metacharacters (a repo cloned under `repo$(touch${IFS}PWNED)`), and command substitution `$(...)`/backticks expand even inside double quotes when those literal bytes appear in command source. Paths cannot be charset-allowlisted (legit paths contain spaces).

Decision (extends the round-7 closure to filesystem paths):

1. **Out-of-band path variables.** `repo_root` and the derived `worktree_path` are NEVER emitted as literal path text into command source. Each shell command derives the path INLINE via command substitution — `rr="$(git rev-parse --show-toplevel)"`, `wt="$rr/.claude/worktrees/<short>"` — whose output is captured into a variable and is then inert (bash does not re-evaluate command substitution from variable contents); the path is referenced only as `"$rr"`/`"$wt"`. The only literal interpolated is `<short>` (already sanitized to `[a-z0-9-]`). Because each Bash tool call runs in a fresh shell, the variable is re-derived within every command that needs it. Applied to every path-bearing shell site (`git worktree add`, the `task.md` parent `mkdir`, Pass-2 `load-buffer`, config-copy `mkdir`/`cp`, HARD-failure `git worktree remove --force`, and the pre-flight worktree-existence test). `worktree_path` is still recorded in the manifest as an absolute path via the Write tool — a tool parameter, no shell, so inert there.
2. **tmux bracketed paste (`paste-buffer -p`).** The task is always multiline (data-boundary preamble + blank line + description); `paste-buffer` without `-p` replaces linefeeds with carriage returns, so the TUI could receive the preamble and each description line as separate Enter-terminated submissions instead of one bounded prompt. `-p` (bracketed paste) injects the whole multiline issue-sourced payload as a single bounded prompt; the explicit `send-keys Enter` still submits it once.
3. **Best-effort named-buffer deletion on inject-failure.** `paste-buffer -d` deletes the per-strain named buffer (`brood-<short>`) only on a SUCCESSFUL paste. A `load-buffer` success followed by a `paste-buffer` failure (child pane exits between readiness and paste) leaves the untrusted issue-sourced task resident on the shared tmux server. Every inject-failure path now best-effort deletes the buffer (`tmux delete-buffer -b "brood-<short>" 2>/dev/null || true`), so an untrusted task never persists in the shared tmux buffer regardless of outcome.

Status remains accepted.

## Amendment — 2026-05-30 (PR #154, Per-brood-id namespaced state)

Prior amendments treated `inputs.json` and `manifest.yaml` as singleton paths per checkout and added a **single-brood model**: a server-global `tmux list-sessions | grep '^brood-'` active-brood guard plus an in-flight `mkdir "$STATE/.spawn-lock"` atomic lock with an `EXIT` trap. That model rejected concurrent broods entirely — two distinct `brood_id`s from the same checkout could not run, and review flagged the lock/guard as the wrong mechanism (a checkout-global lock blocks legitimate parallel broods and a `brood-*` grep cannot distinguish one brood's sessions from another's).

Decision (replaces the single-brood model with per-brood-id namespacing):

1. **`brood_slug` derivation.** A filesystem-safe key is derived from the parsed `brood_id` by mapping every byte outside `[A-Za-z0-9._-]` to `-` (re-derived from the PARSED `brood_id`, never trusted from the inputs arg path; rejected if it sanitizes empty or contains `..`). It names the per-brood state dir, the manifest sibling, and the tmux session suffix.
2. **Disjoint per-brood state layout.** State moves from singleton `.hivemind/brood/{inputs.json,manifest.yaml}` to per-brood `.hivemind/brood/<brood_slug>/{inputs.json,manifest.yaml}`. Two distinct `brood_id`s resolve to two distinct directories, so concurrent broods — same checkout AND across checkouts — never collide on inputs or manifest state. An inputs-path/slug consistency check (the inputs file's parent-dir basename MUST equal the slug re-derived from `brood_id`) is a defense-in-depth caller-error signal.
3. **Removal of the server-global guard and the mkdir lock.** The `tmux list-sessions | grep '^brood-'` active-brood guard, the `mkdir "$STATE/.spawn-lock"` atomic lock, and its `EXIT` trap are DELETED. They are unnecessary: distinct `brood_id`s touch disjoint directories, so there is nothing for a checkout-global lock or a server-global session grep to protect. Their removal dissolves the review findings (NEW-H1/H2/M1) that the lock/guard mechanism raised — those findings described defects in a mechanism that no longer exists.
4. **Brood-scoped same-brood_id guard.** The only remaining collision a guard must catch is re-spawning the SAME `brood_id` while its own sessions are still live. After `STATE` is set, if `$STATE/manifest.yaml` already exists, its recorded `tmux_session:` values are extracted and probed with `tmux has-session`; any live session blocks (`brood <brood_id> is already active (live session <name>); refusing to overwrite`). If none is live, the stale completed state is overwritten. This guard inspects ONLY this brood's own manifest — never a sibling brood's.
5. **Session naming carries the slug.** The tmux session is renamed `brood-<short>` → `brood-<short>-<brood_slug>`, so sessions from concurrent broods are distinguishable and a brood's own sessions are recoverable from its manifest.
6. **`brood-status` multi-brood discovery.** `hivemind:brood-status` replaces the singleton manifest read with the glob `<main_checkout>/.hivemind/brood/*/manifest.yaml`, runs the existing per-strain probe (and its untrusted-manifest re-gate) per discovered manifest, and emits one labeled status table + summary per brood keyed by `brood_id` (most-recent-first), with a leading `Broods: N active` roll-up line. No matches still reports "No active brood found."

Status remains accepted.

## Amendment — 2026-05-30 (PR #154, concurrency model scoped to option Y)

Local review iteration 3 surfaced three findings in the per-brood-id namespacing above (F1 slug injectivity, F2 worktree/branch namespacing + same-brood in-flight race, F3 brood-status session-name grammar). The scope decision was **option Y (scope down)** over **option X (full same-checkout concurrency)** and **Z (minimal)**.

**Key realization:** cross-checkout concurrent broods (different repos / checkouts) never shared files — `.hivemind/` is per-checkout state, so two checkouts resolve to two disjoint `.hivemind/brood/<slug>/` paths. They only ever collided on server-global tmux session names, which the `brood-<short>-<brood_slug>` session rename (v2.18.0) ALREADY fixed. The only scenario that needs worktree-path/branch namespacing is two SAME-checkout concurrent broods reusing a strain `name` — a rare, low-value case. Option Y therefore rejects same-checkout concurrent broods via one correct atomic reservation rather than paying the surface cost of namespacing the worktree path and branch.

Decision:

1. **F1 — injective slug via UTC canonicalization.** `brood_id` is canonicalized to a single UTC instant before sanitizing: `brood_canon="$(date -u -d "$brood_id" +%Y%m%dT%H%M%SZ 2>/dev/null || printf '%s' "$brood_id")"`, then the slug is `tr -c 'A-Za-z0-9._-' '-'` on `brood_canon`. Without this, the ISO offsets `+01:00` and `-01:00` both sanitize their offset punctuation to `-`, collapsing two DISTINCT instants to the same slug — and the slug is the per-brood disjointness key. Canonicalizing first makes offset-equivalent timestamps that denote different instants get distinct slugs, and the same instant always get the same slug. `date -d "$brood_id"` passes `brood_id` as an inert quoted ARGUMENT (date parses, never executes it); no command substitution runs on untrusted content. A non-GNU `date` (or a value date rejects) falls back to the raw `brood_id`, which still slugs safely.

2. **F2 dissolved — atomic same-checkout reservation, NO worktree/branch namespacing.** The prior brood-scoped guard probed `$STATE/manifest.yaml` for live `tmux_session:` values AFTER Pass 1+2 wrote the manifest — an in-flight race: two same-`brood_id` spawns both saw no manifest and both launched. It is replaced by a single atomic reservation BEFORE Pass 1/2: `mkdir -p "$STATE"` (idempotent — the agent already created `$STATE` when it wrote `$STATE/inputs.json` via the Write tool, which makes parent dirs), then `mkdir "$STATE/.reservation"` (NON-`-p`) as the gate. `mkdir` is an atomic syscall that fails if the target exists, so exactly one of two racing same-`brood_id` same-checkout spawns wins; the loser fails closed with a clear blocker. **Worktree path and branch are deliberately NOT slug-namespaced** (option X, rejected): namespacing them would let two same-checkout broods co-exist, but that case is rare and low-value, and rejecting it via one atomic reservation is far less surface than threading a slug through every worktree-path/branch derivation, pre-flight collision check, manifest field, and the `brood-status`/cleanup consumers. A stale `.reservation` dir from a crashed spawn is operator-removed (gitignored runtime state).

3. **F3 — brood-status session-name grammar widened to the producer's grammar.** The producer emits `brood-<short>-<brood_slug>` where `brood_slug` is the canonical `YYYYMMDDTHHMMSSZ` form — uppercase `T`/`Z` and possible `.`. `brood-status`'s expected-shape re-validation of `tmux_session` was `brood-[a-z0-9-]+`, which rejects every real session and marks every brood blocked. It is widened to `^brood-[A-Za-z0-9._-]+$` — still a strict allowlist (no shell metacharacters), now matching the emitted grammar.

Status remains accepted.

## Amendment — 2026-05-30 (PR #154, concurrency machinery amputated → single-brood)

The per-brood-id concurrency model became an unbounded local-review rabbit hole. Each review iteration closed findings on the namespacing/lock machinery and immediately opened new ones on the SAME machinery: the slug was not collision-free (F1), the reservation had an in-flight race (F2), the worktree path and branch were un-namespaced (F2 again), and the brood-status session-name grammar rejected the producer's own emitted names (F3). The single use case this machinery served — two SAME-checkout concurrent broods reusing a strain name — is rare and low-value. Per the user decision (Option A), the machinery is DELETED rather than hardened further. Deleting the code dissolves the open findings STRUCTURALLY — the same dissolution move this ADR already used once when it removed the old server-global session guard and the `mkdir .spawn-lock` lock to dissolve the NEW-H1/H2/M1 findings. Cross-checkout broods never share `.hivemind/` state (it is per-checkout), so their manifests, inputs, and worktrees are disjoint without any namespacing. `brood-<short>` tmux session names are server-global and carry no checkout identifier, so two different checkouts each spawning a brood with a same-named strain produce the same session name and collide on the shared tmux server — the same single-namespace trade-off as the rejected same-checkout concurrency. This is accepted under the "one brood at a time per checkout, operator responsibility" stance.

Decision (reverts the per-brood-id model to a singleton single-brood model):

1. **What is removed.** Deleted: the `brood_slug` derivation + UTC canonicalization (`date -u -d "$brood_id" …`), the per-brood-id namespaced state dirs `.hivemind/brood/<brood_slug>/{inputs.json,manifest.yaml}`, the `.reservation` `mkdir` gate, the slug session-name suffix, the inputs-path/slug consistency check, and `brood-status`'s multi-brood `*/manifest.yaml` glob discovery. State reverts to the singleton pair `.hivemind/brood/{inputs.json,manifest.yaml}` anchored to `repo_root`; tmux sessions revert to `brood-<short>`; `brood-status` reverts to reading the single manifest.

2. **Overlap protection — option (b): a single singleton-manifest liveness reject, NOT a `mkdir` reservation.** If the singleton `manifest.yaml` records a `tmux_session` that `tmux has-session` reports live, spawn blocks with `a brood is already active in this checkout (live session <name>); refusing to overwrite`. If the manifest is absent, records no live session, or is malformed, spawn proceeds and overwrites (fail-open to overwrite stale state, matching the existing "stale state is overwritten" stance). This is non-racy by construction relative to the prior machinery: it reads ONE fixed path, so there is no slug to canonicalize, no atomic-reservation TOCTOU window, and no server-global `tmux list-sessions | grep '^brood-'` (itself a prior finding — a `brood-*` grep cannot tell one brood's sessions from another's). The only residual window is two operators racing the very FIRST spawn before any manifest exists; this is documented as operator responsibility — "one brood at a time per checkout." A `mkdir` lock is deliberately not reintroduced: it would only re-add the stale-lock finding this ADR just removed.

3. **Supersession.** The prior amendments "Per-brood-id namespaced state" and "concurrency model scoped to option Y" are SUPERSEDED by this amendment. Their text is left intact above (append-only history), but the singleton single-brood model described here is now authoritative: there is no `brood_slug`, no per-brood-id state dir, no reservation, and no multi-brood discovery. The injection-closure architecture from the earlier amendments (Write-tool inputs, jq-into-inert-variables, out-of-band path derivation, bracketed paste, buffer cleanup) is unaffected and remains in force.

Status remains accepted.

## Amendment — 2026-06-01 (#168: per-brood-id namespacing reinstated structurally; singleton liveness guard removed; manifest v4)

The singleton single-brood model above (the "concurrency machinery amputated" amendment) is SUPERSEDED for the layout/concurrency axis. The earlier per-brood-id attempts were amputated because each review iteration opened new findings on the slug/reservation MACHINERY; the structural fix landed in #168 reinstates per-brood-id namespacing WITHOUT that machinery — a uuidv4 brood-id and disjoint directories replace the slug, the canonicalization, and the lock entirely. The full coherent decision (layout, brood-id format/generation, ground-truth-anchored reads, value-class model) is recorded in **ADR-0021**; this amendment records the SPAWN-side deltas to the mechanism this ADR owns.

Decision:

1. **Per-brood state directory + atomic write.** Brood state moves from the singleton `.hivemind/brood/{inputs,manifest}.json` to a disjoint per-brood directory `.hivemind/broods/<brood-id>/{inputs.json,manifest.json}`, anchored to the canonicalized checkout root. The manifest is written to a temp file UNDER that state dir and `mv`'d into place (same-filesystem atomic rename), so a concurrent reader sees either the old or the complete new manifest, never a torn file. The navigator authors its inputs to a per-invocation mktemp-unique STAGING path under `.hivemind/` (no singleton inputs file to clobber); the script validates it (exists, valid JSON, contained), reads it into inert variables, then atomically `mv`s it into `<state>/inputs.json` for the record.

2. **brood-id generated internally; namespaces every derived name.** The script generates `brood-<uuidv4>` (charset `^brood-[0-9a-f-]+$`, lowercased; portable `uuidgen`/kernel-uuid/`/dev/urandom` chain, fail-closed) and ignores any caller-supplied `brood_id`. The id carries into the branch (`strain/<brood-id>/<short>`, now DERIVED, not caller-supplied), the worktree (`.claude/worktrees/<brood-id>/<short>`), and the tmux session (`<brood-id>-<short>`). The `brood-<short-id>`/`.claude/worktrees/<short-id>` naming in the original Consequences is thereby superseded by the brood-id-prefixed grammar.

3. **Singleton liveness guard REMOVED; NO replacement lock.** The ADR-0017 singleton-manifest liveness reject (and any same-brood in-flight reservation) is deleted. Per-brood-id disjoint directories dissolve both the spawn TOCTOU and the singleton inputs-clobber by construction (ADR-0019 fifth amendment named the singleton layout as the residual; this removes the sharing rather than locking it). Isolation replaces the lock — the same posture as #167. Concurrent same-checkout broods are now supported.

4. **Manifest v4.** `manifest_version: 4`: ADD top-level `brood_id` + `created_at`; per-strain `branch` DERIVED and `worktree_path` retained as DISPLAY-ONLY; DROP `run.suggested_ledger` (the read side derives it from ground truth) and KEEP `run.suggested_id` (lineage reconciliation key). No back-compat (single-user, unreleased 2.20.0): drain any running brood before upgrade.

The injection-closure architecture (Write-tool/staging inputs, jq-into-inert-variables, out-of-band path derivation, bracketed paste, buffer cleanup, canonical-containment + leaf guards) is unaffected and remains in force. This amendment is APPEND-ONLY; prior text stands as history. Status remains accepted.

## Amendment — 2026-06-02 (#170: permission posture — `--permission-mode auto` + config-provisioning evaluated, rejected; `--dangerously-skip-permissions` retained)

Issue #170 proposed switching brood children off `--dangerously-skip-permissions` to `--permission-mode auto` (with attach-on-demand), and optionally provisioning the child `.claude/` config from the trusted coordinator while sanitizing the base tree's `.claude/` before launch (option C). Both were evaluated against live probes this session and REJECTED; the child retains `--dangerously-skip-permissions`. Base-trust remains the boundary: broods MUST be spawned only against trusted bases.

Rejection reasons:

1. **`--permission-mode auto` introduces a classifier-model Bash dependency.** Under `auto`, every child Bash operation is gated through a safety-classifier model (`claude-opus-4-8`). When that model is unavailable or rate-limited the child can run NO Bash at all (read-only ops still work) — hit live during evaluation. This is a recurring reliability/throughput/cost dependency, amplified across N concurrent strains.

2. **`auto` does not close the flagged channel.** The P0 channel Codex flagged in #156 — a hostile base's committed `.claude/settings.json` SessionStart hooks, `.claude/hooks/` scripts, and `.mcp.json` MCP declarations — executes at child LAUNCH, before any tool-permission gating. Permission mode gates tool ACTIONS, not hook/MCP startup. So `auto` pays a recurring cost to harden an already-trusted-by-precondition channel while leaving the flagged channel open.

3. **Option C would strip load-bearing config.** The base's committed `.claude/settings.json` carries a load-bearing `enabledPlugins` entry enabling the `hivemind` plugin plus `defaultAgent` set to the `hivemind:overlord` agent — that config is what makes a child boot AS an overlord (the `hivemind:overlord` READY substring). Sanitizing/replacing the base `.claude/` before launch would break the child's boot-as-overlord and thus break every strain. C would only help the out-of-scope untrusted-base case while risking breakage of legitimate trusted-base config.

The folder-trust boot gate under `auto` is NOT itself the blocker: folder-trust inherits to subdirectories, and brood worktrees live inside the already-trusted checkout, so children inherit trust at launch. The blocker is reason 1 (classifier dependency), compounded by reasons 2 and 3.

This amendment is APPEND-ONLY; prior text stands as history. Status remains accepted.

## Amendment — 2026-07-27 (orchestrator `Write` grant)

The backstop claim above ("`tools:` carry no `Write`/`Edit`") has weakened in its literal text: the child overlord now carries `Write`, bounded to fixed-literal inputs-file transport paths under the gitignored `.hivemind/` tree, with `Edit` still absent. This confers no new capability in a `--dangerously-skip-permissions` child — `Bash` already affords arbitrary file authoring there, as that same passage already concedes — and the compensating controls are unchanged. Status remains accepted.

## Amendment 2026-10-24 (slice 4 of #409: auto mode, detached worktrees, remote control after start)

Slice 4 of https://github.com/brenpike/hivemind/issues/409 runs brood children on the script engine. ADR-0037 records the slice (Amendment 2026-10-24: brood children on the script engine (slice 4)). This amendment records the spawn-side deltas to the mechanism this ADR owns.

1. **Auto mode replaces bypass mode.** Each child launches with `claude --permission-mode auto`. This supersedes the permission part of decision 2 (`--dangerously-skip-permissions` and the `skipDangerousModePermissionPrompt` setting) and the #170 amendment's choice to keep bypass mode. The Consequences line on the bypass blast radius no longer applies.
2. **Reason 1 of the #170 amendment is accepted.** The user accepts the classifier dependency as a cost, by decision on 2026-10-24, with remote control as the monitoring channel: a child that the classifier pauses, or whose classifier is unavailable, waits until the user answers through remote control or the attach line. The user owns monitoring the brood. Where auto mode is unavailable, the child starts in manual mode and waits at its first prompt (ADR-0037 records this residual).
3. **Reason 2 still holds, so trusted bases stay required.** Hooks and MCP servers declared in the base still run at launch, before any permission check, in auto mode as in bypass mode. Broods must still be spawned only against trusted bases. Reason 3 is unaffected.
4. **The worktree is created detached.** Each worktree is created with `git worktree add --detach <path> <base commit>` at the resolved base commit. This supersedes decision 1's `-b <exact-strain-branch>` and the derived `strain/<brood-id>/<short>` branch of the #168 amendment. spawn-brood creates no branch, and the child's planner names its own working branch.
5. **The launch drops `--disallowedTools`.** spawn-brood no longer passes `--disallowedTools Workflow`, so the child launches the script engine (ADR-0037 decision 10 has ended).
6. **Started-evidence includes the facts file.** Beside a run-ledger `state.current`, a gather-facts output file under the child worktree's `.hivemind/facts/` counts as started-evidence, because a script run writes no run ledger. One shared function, `hivemind_detect_facts_evidence` in `plugin/skills/_shared/brood-state.sh`, serves spawn and brood-status. Neither source can come from the base: the run-ledger leaf is keyed by the run id spawn generates from the brood GUID, and spawn refuses a strain whose new worktree already holds `.hivemind/facts`, so every facts file spawn or brood-status reads was written after launch. The pane is still never read for started-evidence.
7. **Remote control starts after started-evidence.** After the manifest is written, spawn-brood runs `rc-brood.sh --only` for each strain that showed started-evidence and was alive when spawn ended (status `running`). A strain still `starting` gets a skipped line and no keystroke. A remote-control failure prints a warning line and changes neither the manifest nor the exit code (ADR-0027, Amendment 2026-10-24).

The injection-closure architecture (Write-tool inputs, jq into inert variables, out-of-band path derivation, bracketed paste, buffer cleanup) and the pre-spawn human approval of the task text are unaffected. `task.md` keeps the data-boundary preamble first and now carries data only below it (ADR-0037 decision 24). This amendment is append-only; prior text stands as history. Status remains accepted.

## Amendment 2026-10-31 (issue 455: strain launch carries `--settings`)

Issue 455 (https://github.com/brenpike/hivemind/issues/455): a strain's Reads and Greps of its own plugin files prompted, because the plugin folder is outside the strain worktree. ADR-0010 records the cause, the decision and the rejected options (Amendment 2026-10-31). This amendment records the spawn-side delta.

1. **The child launch command now carries `--settings`.** In pre-flight, spawn-brood writes one per-brood file, `.hivemind/broods/<brood-id>/strain-settings.json`, in the coordinator state dir. It holds only `permissions.allow`, with one read-only `Read(...)` rule per plugin-root spelling. Each child launches with `claude --permission-mode auto --settings ../../../../.hivemind/broods/<brood-id>/strain-settings.json`. The `--settings` path is relative to the worktree, so the command typed into tmux holds only fixed literals and the asserted brood id. When no plugin-root spelling passes the charset gate, no file is written and the launch stays `claude --permission-mode auto`. The out-of-band path architecture of the 2026-05-30 amendments still holds: no plugin path byte reaches the tmux command string.
2. **This is not the config provisioning rejected on 2026-06-02.** Option C of the #170 amendment replaced the child `.claude/` config and sanitized the base tree's `.claude/` before launch, which would have stripped the `enabledPlugins` and `defaultAgent` keys a child boots on. This change leaves the base tree's `.claude/` untouched. The file sets no key other than `permissions.allow`, and allow lists merge across settings sources, so the base's committed settings still load as before (ADR-0010, Amendment 2026-10-31). Reasons 2 and 3 of the #170 amendment are unaffected, and broods must still be spawned only against trusted bases.

The coordinator `settings.local.json` copy into each worktree is unchanged. This amendment is append-only; prior text stands as history. Status remains accepted.
