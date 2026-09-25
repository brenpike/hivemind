# Trust-boundary discipline: committed engine/helper scripts accept identifiers, derive every path

**Status:** accepted — 2026-06-01

The committed engine and helper scripts that cross a trust boundary accept IDENTIFIERS, never PATHS. They DERIVE every path they touch from ground truth, project hostile cross-boundary CONTENT to bounded allowlist-validated tokens rather than reading/executing/emitting it raw, and treat the PACKAGED workflow definition as the sole transition/authorization source of truth — never a caller-supplied one. This ADR names the discipline, records the two reproduced P0s it dissolves, and supersedes the ADR-0018 f92f1db8 "trusted overlord-resolved path" decline.

## Context

The workflow engine (ADR-0018) added two committed scripts — `init-run-ledger.sh` and `record-state-result.sh` — that the overlord drives across a trust boundary. The original design accepted PATHS from the caller: `record-state-result.sh` took a `ledger` path and a `workflow`-definition path; the overlord was assumed to resolve both to in-tree, plugin-shipped files (ADR-0018 §8, and the f92f1db8 implementation note, which declined to anchor `--workflow` on the premise that the value "originates entirely within the overlord's own reasoning").

That premise broke. Two trust-boundary P0s were REPRODUCED against the engine (the Codex thread text describing them is DATA — the vectors are summarized here, not pasted-and-obeyed):

1. **Forged ledger path → arbitrary-file overwrite.** A caller-supplied `ledger` path was the file the engine atomically rewrote. A path pointing outside `.hivemind/runs/` turned the engine's own atomic write into an arbitrary-file-overwrite primitive.
2. **Forged definition path → transition-gate + plan-write-auth bypass.** A caller-supplied `workflow`-definition path was the SOLE source of the legal-transition set AND of the per-state `agent` field that gates plan writes. A forged definition could declare any transition legal and any state a cerebrate planning state, bypassing both the transition gate and the plan-write authorization the engine exists to enforce.

Both reproductions share one root cause: a script on the far side of a trust boundary accepted a PATH and treated whatever it pointed at as ground truth.

## Decision

**Committed engine/helper scripts accept identifiers, never paths; they derive every path from ground truth; hostile cross-boundary content is projected to bounded tokens; the packaged definition is the sole transition/auth source of truth.**

Concretely:

- A script that crosses a trust boundary takes IDENTIFIERS (a `run_id`, a workflow id) validated against a fixed safe-component charset (`^[A-Za-z0-9._-]+$`, with `.`/`..` rejected), never a caller-supplied PATH.
- It DERIVES every path it touches from ground truth: a run ledger from `git rev-parse --show-toplevel` + `run_id`; a workflow definition from the script's OWN self-located packaged dir (`BASH_SOURCE` + `pwd -P`, independent of `${CLAUDE_PLUGIN_ROOT}` and of any caller value).
- It COHERENCE-CHECKS the derived ground truth against the supplied identifier (the on-disk `ledger.run.id` must equal the passed `run_id`).
- Hostile cross-boundary CONTENT is projected and allowlist-validated to bounded tokens — never Read-whole, executed, or emitted raw. Untrusted fields enter `jq` only as `--arg`/`--argjson` bindings; they never become program or command SOURCE.
- The PACKAGED definition — the plugin-shipped `workflows/<id>.json` self-located by the script — is the sole transition and authorization source of truth, never a caller-supplied file.

### Three boundaries this discipline governs

1. **overlord / navigator → engine.** FIXED this PR. `record-state-result.sh` now takes a `run_id` (SAFE_ID_RE-validated, `.`/`..` rejected), derives the ledger from the git checkout root, coherence-checks `ledger.run.id == run_id`, and derives the workflow definition from the ledger's own `run.workflow` against the self-located packaged dir. No caller path is accepted on either axis.
2. **init → packaged definition.** FIXED this PR (#162). `init-run-ledger.sh` self-locates its packaged `workflows/` dir and validates the supplied workflow id against the packaged definition (the file must EXIST, its `.version` must equal `workflow_version`, its `.start` must equal `start_state`) BEFORE creating the run dir, failing early so a bad id/version/start never leaves an orphan run dir.
3. **hostile `--dangerously-skip-permissions` child → coordinator.** STAGED (#161). The brood child reads child-ledger content across a boundary into the coordinator dashboard; bringing that read under this same discipline (identifiers + derivation + bounded-token projection of hostile ledger content) is tracked in #161 and to be implemented against this ADR.

### Precedent — the discipline generalizes existing ad-hoc hardening

This principle is not new invention; it codifies hardening already landed piecemeal:

- **`spawn-brood.sh`** (ADR-0017) keeps filesystem checkout paths OUT of generated shell source by deriving them out-of-band (`wt="$(git rev-parse --show-toplevel)/.claude/worktrees/<short>"`, then referenced only as `"$wt"`), and gates `branch`/`base` through a charset allowlist in agent reasoning before any shell use. Identifiers + derivation + allowlist — the same shape.
- **`github-review-loop`** preflight / prefilter / poll scripts use their positional arguments only as inert `"$var"` references and project untrusted GitHub API content through `jq` to fixed tokens — hostile content never becomes command source.

The two reproduced P0s above are instances of a boundary that had NOT yet received this treatment; the discipline dissolves them the same way it already hardened spawn-brood and the review-loop.

## Considered Options

| Option | Rejected because |
|---|---|
| Keep accepting a caller `ledger`/`workflow` path, anchor/canonicalize it | Guards a path the caller still controls; the f92f1db8 decline already showed "trusted overlord-resolved path" is not a real boundary once the vector is in-model. Derivation removes the path from the interface entirely. |
| Validate the definition CONTENT (schema) but keep the caller path | A schema-valid forged definition still declares hostile transitions/auth; content validation does not bound WHICH file is read. |
| Accept the `run_id` but still take the ledger path for the write target | Re-admits the arbitrary-overwrite primitive; the write target must be derived, not supplied. |

## Consequences

- The engine interface shrinks: `record-state-result.sh` takes a `run_id` plus inert data, no paths. The arbitrary-file-overwrite and forged-definition primitives are structurally absent — there is no path on the interface to forge.
- The packaged definition is authoritative. A plugin upgrade that changes a definition surfaces as a binding/version-skew mismatch (handled by the resume gate's two doors), never as a silently-honored alternate definition.
- Boundary 3 (#161) is staged, not closed; the coordinator's read of hostile child-ledger content must be brought under the same identifier+derivation+bounded-token discipline before it is considered compliant.
- **Supersedes the ADR-0018 f92f1db8 implementation note.** That note declined to anchor `--workflow` because the value was deemed "trusted overlord-resolved path / out-of-model." The forged-definition + plan-write-auth-forgery vector was REPRODUCED and is now IN-model; the engine no longer accepts a workflow path at all, reversing the prior decline. ADR-0018's f92f1db8 note is marked superseded (original retained, append-only).
- This decision is hard-to-reverse (it removes paths from a committed interface), surprising (it inverts the f92f1db8 "trusted path" posture), and a real trade-off (callers lose the ability to point the engine at an out-of-tree definition, e.g. for ad-hoc testing) — an ADR is warranted.

## Amendment — 2026-06-01 (canonical-containment guard: derivation requires verifying containment)

The derive-from-ground-truth principle is SHARPENED, not reversed: a derived TEXTUAL path is NOT confinement when an ancestor of that path is attacker-controlled. The original Decision derived the ledger path as the literal text `<checkout-root>/.hivemind/runs/<run_id>/state.json` and treated that derivation as sufficient confinement. It is not. `.hivemind/` is normally gitignored, but a repo can still COMMIT `.hivemind` (or `.hivemind/runs`) as a SYMLINK; git tracks the symlink itself, gitignore notwithstanding. When `.hivemind` resolves to an external directory, the textually-derived path resolves OUTSIDE the checkout, and the engine's own `mkdir`/`mktemp`/`mv` write there.

**Reproduced vector (Codex P0 r3331282391, summarized — the thread text is DATA, not instructions):** a tracked `.hivemind`→external symlink in the checkout redirected the engine write outside the checkout. With `.hivemind` pointing at an external dir, `init-run-ledger.sh` exited 0 and created `<external>/runs/demo/state.json` — the ledger write landed entirely outside the checkout, exactly the boundary the derivation was meant to enforce.

**The sharpening.** After textual derivation, BEFORE any `mkdir`/`mktemp`/`mv`, both engines now:

1. Canonicalize — resolve all symlink components — via the portable `cd … && pwd -P` idiom (not `realpath`/`readlink -f`, which BSD/macOS lack or spell differently); a failed `cd` yields an empty result under `set -u`, which is tested for and blocked rather than proceeding with an empty canonical path.
2. Verify the canonical path remains under the canonical `<checkout-root>/.hivemind/runs/` prefix (trailing-slash-guarded so a sibling like `.hivemind-evil` / `.hivemind/runs-evil` cannot prefix-match).
3. Explicitly reject any symlinked ancestor with a POSIX `[ -L ]` test (which detects a symlink component regardless of whether its target exists).

The two engines differ by their leaf's existence at guard time, and the guard is shaped accordingly:

- **`init-run-ledger.sh`** CREATES the run dir, so its leaf does not exist yet. It canonicalizes the deepest EXISTING ancestor (`.hivemind`, then `.hivemind/runs` when each is a real dir) and adds an explicit `[ -L ]` reject on `.hivemind` and `.hivemind/runs`. A first-init checkout where neither exists skips both probes — the leaf run dir is created later under the verified-contained canonical root. The ledger path is then derived from the CANONICAL root so the subsequent `mkdir -p`/`mktemp`/`mv` all operate on the verified path.
- **`record-state-result.sh`** requires the ledger to ALREADY EXIST, so it canonicalizes the already-existing ledger file (via its directory), requires the canonical ledger live under the canonical `.hivemind/runs/`, and uses the canonical (verified-contained) dir for the temp-write + atomic rename. All of this runs BEFORE `mktemp`, so a rejection never creates a temp file and the on-disk ledger is byte-unchanged.

**Lower-severity, separately tracked (out of scope for this engine fix).** The agent-authored inputs-file Write transport — `.init-inputs.json` / `.record-inputs.json` written to a fixed `.hivemind/` path by the Write tool — could LIKEWISE be redirected by a symlinked `.hivemind`. That is a distinct trust posture from the engine's own `mkdir`/`mktemp`/`mv`: it is an agent Write-tool transport, not an engine filesystem mutation, and is tracked separately rather than addressed here. The engine guards SHRINK that window: they reject a symlinked `.hivemind` the moment `init`/`record` runs.

This amendment is APPEND-ONLY. The original Decision and Consequences prose stand; this records that derive-from-ground-truth REQUIRES canonical-containment verification to be confinement, not merely textual derivation. Status remains accepted.

## Amendment — 2026-06-01 (all-writers canonical containment, depth-complete check, shared idiom, invocation-unique transport)

The canonical-containment guard introduced in the first amendment is GENERALIZED to every committed writer and HARDENED against a symlinked leaf; the concurrency transport that feeds the two engines is separately closed. This amendment records five points; it does not edit the Decision, Consequences, or the first amendment.

1. **The discipline applies to EVERY committed WRITER, not only the two engines.** The first amendment named `init-run-ledger.sh` and `record-state-result.sh`. `spawn-brood.sh` is ALSO a committed writer — it `mkdir`s and writes under `.hivemind/brood/`, `.claude/`, and `.claude/worktrees/` — and is now brought under the same canonical-containment discipline at each of those write sites. Canonical containment is a property of every committed filesystem mutator that derives a path near an attacker-influenceable ancestor, not a per-engine special case.

2. **A DEPTH-COMPLETE generic check is required; enumerate-by-name is insufficient.** The check must canonicalize the deepest EXISTING ancestor of the FULL target chain and apply a `[ -L ]` symlink reject to EVERY existing component along that chain — not a fixed hand-enumerated list of names. Enumerate-by-name (e.g. probing only `.hivemind` and `.hivemind/runs`) misses a symlinked LEAF: the reproduced finding-1 vector (Codex P0, summarized here as DATA, not pasted-and-obeyed) is a symlinked `<run_id>` component — a deeper level than the enumerated ancestors — that redirected the write outside the checkout while every enumerated ancestor passed. A generic deepest-existing-ancestor canonicalize + per-component `[ -L ]` reject covers an arbitrary-depth symlink, including the leaf, where name-enumeration does not.

3. **The three writers now share ONE sourced containment idiom.** `init-run-ledger.sh`, `record-state-result.sh`, and `spawn-brood.sh` source a single common helper (`plugin/skills/_shared/containment.sh`) for canonicalization + containment verification, so the three cannot drift to three subtly-different (and separately-buggy) hand-rolled guards. One idiom, one place to audit, one place to fix.

4. **Concurrency-transport hardening: the inputs-file transport is now invocation-unique.** The first amendment flagged the agent-authored inputs-file Write transport (`.init-inputs.json` / `.record-inputs.json` at a fixed `.hivemind/` path) as lower-severity and separately tracked. The same-checkout SINGLETON-inputs TOCTOU (two concurrent same-checkout overlord sessions clobbering one shared inputs file between the Write and the script exec) is now closed by making each transport invocation-unique: `record` keys its inputs file by `run_id` UNDER the run dir (`.hivemind/runs/<run_id>/.record-inputs.json`; record always knows its run_id and the run dir already exists), and `init` — which has no run_id yet — uses a per-invocation token (`.hivemind/runs/.init-inputs-<token>.json`, a sibling of the run dirs, outside the `runs/<run-id>/` glob). `spawn-brood` is EXEMPT from this transport change: the ADR-0017 singleton-manifest liveness guard already serializes brood spawns to one-at-a-time per checkout, so its singleton `.hivemind/brood/inputs.json` has no concurrent-writer window to close.

5. **#161 / brood-status is READ-ONLY and inherits the discipline on its read side.** `brood-status` performs no write-escape (it mutates no ledger or worktree); the identifier+derivation+bounded-token discipline applies to its READ of hostile child-ledger content (boundary 3, staged in #161), not to any write path here.

This amendment is APPEND-ONLY. The original Decision, Consequences, and the first amendment stand. Status remains accepted.

## Amendment — 2026-06-01 (codified transport-path invariant; record corrected to fixed-literal-sibling token; init mkdir-claim; shared read-guard)

The second amendment (point 4) documented `record`'s inputs-file transport as run-id-keyed UNDER the run dir (`.hivemind/runs/<run_id>/.record-inputs.json`). That INTERIM form is itself the finding-1 (F1) write-through-symlinked-leaf vector — a caller-derived `<run_id>` component below the fixed-literal level — so this amendment SUPERSEDES that specific claim. It records four points; it does not edit the Decision, Consequences, the first amendment, or the rest of the second amendment.

1. **The transport-path invariant is now CODIFIED in `plugin/governance/security-policy.md`** ("Inert Inputs-File Navigator Pattern" → Transport-path invariant). It requires every inputs-file navigator's Write target to be a FIXED-LITERAL path with NO caller-derived component below the fixed-literal level, to live under gitignored `.hivemind/`, and to be per-invocation-unique (carry an invocation `<token>`) UNLESS the navigator is otherwise serialized to one writer per checkout. The forbidding of a caller-derived component below the fixed level is the structural rule that the run-id-keyed interim form violated.

2. **`record`'s transport is corrected from the interim run-id-keyed form to the fixed-literal-SIBLING token form** `.hivemind/runs/.record-inputs-<token>.json` (a sibling of the run dirs, outside the `runs/<run-id>/` glob). This dissolves F1 (P0) — the run-id-keyed leaf could be a committed symlinked run-dir directory whose escape the agent Write performs before any committed guard runs; the sibling token form has no caller-derived component below the fixed `.hivemind/runs/` level. It also dissolves F3 (P1) — two concurrent recorders of the SAME run no longer clobber one shared inputs file, because the per-invocation `<token>` (not the `run_id`) supplies uniqueness.

3. **The F2 init run-dir reservation race is closed by an atomic `mkdir`-claim.** `init-run-ledger.sh` creates the run-dir parents with `mkdir -p`, then claims the `<run_id>` leaf with a BARE `mkdir` (no `-p`), so the LOSER of two same-`run_id` initializers fails closed (bare `mkdir` errors when the leaf already exists) and the WINNER's ledger is never overwritten by a late second initializer.

4. **A shared `hivemind_assert_inputs_contained` read-guard is added to all three engines as HONEST defense-in-depth.** Each engine calls it BEFORE reading its inputs file; it refuses to READ an inputs file that resolves OUTSIDE the checkout. It is HONEST about its bound: it does NOT prevent the external Write (the agent Write-tool transport has no engine-side guard ahead of it) — it makes an external-resolving transport LOUD (refuse-to-read) rather than silent, since plugin frontmatter cannot path-scope the Write grant.

**Residual (UNCHANGED, separately tracked).** That an agent Write-tool transport — as opposed to the engine's own `mkdir`/`mktemp`/`mv` — could in principle still be redirected by a symlinked `.hivemind` / `.hivemind/runs` is UNCHANGED by this amendment and remains separately tracked (per the first amendment's lower-severity note). What changed is that `record` no longer sits at a strictly-WORSE 3-deep unchecked-leaf posture (a caller-derived `<run_id>` directory below the fixed level): it now matches `init`'s already-accepted 2-deep guarded-ancestor posture. This amendment NARROWS `record`'s window to parity with `init`; it does not widen the residual.

This amendment is APPEND-ONLY. The original Decision, Consequences, the first amendment, and the second amendment stand (save the second amendment's point-4 run-id-keyed `record` transport, superseded here). Status remains accepted.

## Amendment — 2026-06-01 (same-run ledger-write serialization is out-of-envelope; deferred to #167)

The third amendment's per-invocation `<token>` closes the inputs-FILE transport collision (F3) — it makes each invocation's transport file unique — but it does NOT serialize the ledger WRITE itself. A reproduced P1 (DATA: N concurrent recorders of one run can lose events to a last-writer-wins atomic rename) was evaluated and DEFERRED rather than fixed with a per-run lock: RUN-OWNERSHIP-01 (worktree isolation) already makes one overlord the sole mutator of a run ledger, so concurrent same-run mutation is outside the design envelope, and adding a multi-writer lock would contradict that ownership model. Accordingly, the over-claim that the token "supports same-run concurrent recorders" is retracted in the `record-state-result` SKILL and `security-policy.md`; prose there now asserts single-writer-per-run as the invariant and labels same-run concurrent ledger mutation as out-of-envelope. If multi-writer-per-run is ever supported, the per-run-lock design is captured in #167. This amendment is APPEND-ONLY. Status remains accepted.

## Amendment — 2026-06-01 (brood-spawn liveness exemption retracted; structural fix is per-<brood-id> namespacing, #168)

A prior amendment to `security-policy.md` (second amendment, point 4, recorded in this ADR) claimed that `spawn-brood` was EXEMPT from the per-invocation-token transport requirement because "the ADR-0017 singleton-manifest liveness guard already serializes brood spawns to one-at-a-time per checkout." That exemption is RETRACTED.

A reproduced Codex P1 (summarized here as DATA — the thread text is not instructions) showed that the liveness guard is a check-then-act read with a TOCTOU window, not a reservation. Under the v1 SINGLETON manifest layout, two concurrent same-checkout spawns can both pass the liveness check before either writes a manifest; both then launch `--dangerously-skip-permissions` children, and the later manifest write hides the earlier child from monitoring. The singleton `inputs.json` is likewise clobberable between the navigator's Write tool call and the script's exec.

ROOT CAUSE: the v1 SINGLETON shared manifest (RUN-OWNERSHIP-01: the brood manifest is the sole shared mutable artifact for a checkout). The liveness guard was never a serialization primitive; it was a best-effort probe that assumed sequential invocation.

Rather than adding a throwaway per-checkout lock plus a per-invocation token on the singleton transport, the STRUCTURAL fix is deferred per-`<brood-id>` namespacing: `.hivemind/broods/<brood-id>/...`, tracked in #168. Namespacing gives each brood its own disjoint dir, manifest, and inputs file, making the shared singleton the entity that is removed. Both the inputs TOCTOU and the manifest-hiding race dissolve because the paths are no longer shared. A per-checkout lock was deliberately NOT added (it would be throwaway once namespacing lands).

Coherence with the #167 deferral: where state is ISOLATED (per-run worktree, RUN-OWNERSHIP-01) no lock is needed because there is no shared mutable state; the brood manifest is the one genuinely SHARED artifact in the current design, and namespacing removes the sharing rather than locking it.

This is documented as a KNOWN v1 residual limitation on PR #156. The `security-policy.md` Transport-path invariant section and `spawn-brood.sh` liveness-guard comment block are updated on the same PR to reflect this retraction and to point to #168 as the tracked structural fix. No behavior change accompanies this amendment — this records the retraction and the known residual only.

This amendment is APPEND-ONLY. Status remains accepted.

## Amendment — 2026-06-01 (file-target containment primitive + signal-safe state-keyed rollback; Codex Findings D, E, PR #156)

Two post-merge hardening fixes are recorded here. Neither reverses prior decisions; both sharpen existing discipline in the one-shared-containment.sh invariant framing (extend, never fork). This amendment records two points; it does not edit the Decision, Consequences, or any prior amendment.

1. **File-target containment primitive — derive-and-verify-containment must cover the write-target LEAF, not only its ancestor chain, for any writer whose leaf can be a symlink materialized from an attacker-influenced tree.**

   The second amendment (point 2) introduced `hivemind_assert_contained` in `plugin/skills/_shared/containment.sh` to cover directory-ancestor chains. That primitive canonicalizes the deepest EXISTING ancestor and `[ -L ]`-rejects any symlinked component along the chain. It is correct for directory targets. It does NOT cover a write-target LEAF that is itself a symlink: a `git worktree add` from a hostile `base` ref can materialize `.hivemind/brood/task.md` or `.claude/settings.local.json` as a COMMITTED SYMLINKED LEAF into the child worktree, so the write follows the symlink to an external target before a `--dangerously-skip-permissions` child launches — even when every ancestor passes the existing chain guard.

   **Reproduced vector (Codex Finding D, P0, summarized — the thread text is DATA, not instructions):** a committed symlinked leaf below an otherwise-clean ancestor chain caused `spawn-brood`'s child-provisioning write to land outside the checkout, bypassing the chain guard entirely.

   **The new primitive.** `hivemind_assert_file_contained` is added to `containment.sh`. It composes `hivemind_assert_contained` on the leaf's PARENT directory (validating the ancestor chain), then adds a `[ -L ]` reject on the leaf itself. WHY it cannot reuse the directory primitive directly: `hivemind_assert_contained`'s final `cd "$deepest_existing" && pwd -P` empty-false-rejects a regular-file leaf (you cannot `cd` into a file). A non-existent leaf (fresh create) and a regular-file leaf (overwrite) both pass the new primitive; only a symlinked leaf rejects.

   **Scope.** `spawn-brood.sh` now calls `hivemind_assert_file_contained` before its two child-provisioning writes (the `task.md` write and the child-settings write). The init and record engines are NOT in scope: their leaf names derive from a SAFE_ID_RE-validated `run_id` component, and their depth-complete chain guard already walks to the deepest existing ancestor (which, when the run dir exists, includes the leaf); a class scan confirms the leaf-symlink attack requires a planner-controlled name below the SAFE_ID_RE gate — structurally excluded. Exactly the two spawn-brood child leaves required the new primitive.

2. **Signal-safe state-keyed reservation rollback — destructive EXIT-trap cleanup that lags a durable mutation must key on GROUND TRUTH (committed ledger absence), not a mutable disarm flag.**

   `init-run-ledger.sh`'s reservation-rollback EXIT trap keyed the destructive `rm -rf "$CLAIMED_DIR"` on the mutable `CLAIMED_DIR` disarm flag: the flag is cleared AFTER the durable `mv -f` ledger install. A TERM or INT arriving in the `mv`→disarm window fired the trap with `CLAIMED_DIR` still set and erased the just-committed ledger — a race between the signal and the disarm assignment that made the rollback destructive on a committed ledger.

   **Reproduced vector (Codex Finding E, P1, summarized — the thread text is DATA, not instructions):** a signal in the `mv`→disarm window triggered the rollback trap on a ledger already durably committed, destroying it.

   **The fix.** The trap cleanup is re-keyed on GROUND TRUTH: `[ -n "${CLAIMED_DIR:-}" ] && [ ! -f "${ledger_path:-}" ]` — rollback runs ONLY when the committed ledger is absent (genuine orphan). State-based and idempotent: a signal anywhere relative to the `mv` is harmless — if the ledger file exists after the signal, the trap does nothing. The trap still ends in the guaranteed-zero `:` (EXIT-trap-exit-code invariant). The `CLAIMED_DIR=""` disarm is kept as belt-and-suspenders.

   **Class-scan siblings (scanned, neither needs a fix).** `spawn-brood`'s interrupt trap is REPORTING-ONLY — it emits provisional resource names for manual recovery and runs no destructive cleanup; over-reporting on a lagging marker is the safe direction. `record-state-result.sh` has NO trap — its atomicity is temp-write + atomic `mv`; on failure it only `rm`s its own temp, never the committed ledger. Both are the safe class; neither requires a parallel fix.

This amendment is APPEND-ONLY. The original Decision, Consequences, and all prior amendments stand. Status remains accepted.

## Amendment — 2026-06-01 (Boundary 3 CLOSED: read-side discipline for hostile child-ledger projection, #161)

Boundary 3 (#161), staged in the original Decision as "not closed," is now CLOSED. The coordinator's read of hostile, cross-worktree child-ledger content is brought under the same trust-boundary discipline as the write side — identifiers + derivation + bounded-token projection — via a committed helper and shared library stack.

**What changed.**

A committed helper (`plugin/skills/brood-status/scripts/brood-status-project.sh`) takes a trusted manifest PATH as its only identifier input (layout-agnostic; the same helper is reused by #168 when the manifest layout changes). It derives every other path out-of-band from that trusted manifest, storing each in inert `"$var"` shell variable references. Manifest values are NEVER spliced into generated shell source — the same lesson applied on the write side in ADR-0017.

Each child-ledger path is confined BENEATH its own strain `worktree_path` as `.hivemind/runs/<safe-id>/state.json` via the shared `_shared/containment.sh` (`hivemind_assert_file_contained`), which rejects a symlinked or non-regular-file leaf and performs a canonical-prefix recheck, closing the same leaf-symlink escape class closed on the write side.

Exactly two scalars are jq-projected from the untrusted child ledger and validated before any use:

- `run.status` — validated against the exact enum `running|complete|blocked|cancelled`; emits the fixed token `MALFORMED` on mismatch, `MISSING` when the field is absent.
- `state.current` — validated against `^[a-z0-9_]+$` with length ≤ 64; same fixed-token fallback.

Neither raw bytes nor any other ledger field ever reaches agent context. The whole untrusted ledger is never read into agent context (project-before-ingest).

The projection is INFORMATIONAL-ONLY and never overrides observable-derived status. ADR-0007 ground-truth observables (tmux liveness, git branch state, PR state) remain authoritative; a hostile child cannot hide a runaway session by corrupting its ledger.

**Shared library decomposition (ADR-0020).** The logic is factored across three focused `_shared/` function libraries — `_shared/allowlist.sh` (safe-token gate), `_shared/manifest.sh` (manifest field extraction), `_shared/ledger-project.sh` (ledger scalar projection and validation) — each unit-tested in `tools/test_shared_libs.sh` and orchestrated by the thin `brood-status/scripts/brood-status-project.sh` entrypoint. This factoring is the first deliberate application of the single-responsibility shell library pattern recorded in ADR-0020.

**Four PR-#156 read-side P0 review comments resolved.** The following Codex review thread IDs were explicitly deferred to #161 on PR #156 and are closed by this implementation:

- `3330646588` — confine reads: each child-ledger read is path-confined beneath its own strain `worktree_path` via `hivemind_assert_file_contained`.
- `3330904208` — project-before-ingest: only the two validated scalar tokens reach agent context; the raw ledger is never surfaced.
- `3330936097` — keep manifest paths out of generated shell: manifest values are stored in inert `"$var"` references, never spliced into command source.
- `3330936099` — reject untrusted projected strings: both projected scalars are allowlist-validated; only fixed `MALFORMED`/`MISSING` tokens are emitted on failure, never raw ledger bytes.

This amendment is APPEND-ONLY. The original Decision, Consequences, and all prior amendments stand. Boundary 3 (#161) is now CLOSED. Status remains accepted.

## Amendment — 2026-06-01 (Boundary 3 closure rests on jq-parse of a JSON manifest; hand-parse injection class closed by construction; 3-class value-validation contract)

> Active end-state (this amendment only): ADR-0021 and `plugin/references/brood-ledger-model.md` (brood state layout and manifest schema). The trust-boundary decision in this ADR still governs; the brood-manifest literals of this amendment that the 2026-09-25 amendment names are superseded.

**Superseded in part by the 2026-09-25 amendment at the end of this ADR (#375).** That amendment names which of this amendment's literals are superseded and which live source owns each subject. Read no current value from this amendment; take the brood state layout and manifest schema from the sources named above. The original text is retained for history.

The Boundary 3 CLOSED amendment above recorded that `brood-status-project.sh` brings the coordinator's read of hostile child-ledger content under trust-boundary discipline. This amendment sharpens the description of the MANIFEST read side: the closure rests on a `jq`-parse of a JSON manifest — NOT a block-scalar-aware `sed` extractor — and the ad-hoc `safe_token`/`safe_path` validator pair is replaced by a 3-class canonical contract.

**JSON manifest root fix.** The brood manifest is now JSON (`manifest_version: 3`), written by `spawn-brood.sh` via `jq --arg`/`--argjson` and read by `jq` in both `spawn-brood`'s liveness guard and `brood-status`. `_shared/manifest.sh` (the `sed`/`awk` hand-scraper) is DELETED; replaced by `_shared/manifest-json.sh` (jq projections). A real `jq` parser cannot conflate structure with content, closing the hand-parse injection class by construction:

- **Block-scalar field-override** — a strain's `description:` block body containing a counterfeit `branch:` / `worktree_path:` / `status:` line can no longer override the genuine field. The structure/content boundary is enforced by the parser, not a per-field line-anchor heuristic.
- **Multiline-name injection** — an issue-sourced name spanning multiple lines cannot insert a synthetic strain entry or corrupt field adjacency.
- **Nested-mapping key spoof** — a `description` block cannot emit a fake `run:` sub-object or `suggested_ledger:` key that the extractor misreads as a peer field.

These three attack shapes all required the `sed`/`awk` extractor to confuse CONTENT for STRUCTURE; `jq` on JSON has no such confusion surface.

**3-class value-validation contract.** The ad-hoc `safe_token` / `safe_path` validator pair used in the earlier `_shared/manifest.sh` is replaced by THREE canonical value-class validators in `_shared/allowlist.sh`, sharing one security floor (reject `$`/backtick command-substitution, `..`, leading `-`, and TAB/LF/CR framing):

| Class | Validator | Charset | Applies to |
|---|---|---|---|
| Identifier | `hivemind_assert_identifier` | `^[A-Za-z0-9._/-]+$` | branch, tmux session name, status enum, ledger-id |
| Path | `hivemind_assert_path` | identifier + space + `# = ~ !` | worktree_path, suggested_ledger |
| Presentation | `hivemind_assert_presentation` | printable display (no command-sub, no framing control) | strain name |

All three classes share the same security floor; the presentation class adds a printable-character pass gate rather than a charset allowlist, because strain names are display-only and never shell-interpolated. The two former ad-hoc validators are subsumed: `safe_token` maps to identifier, `safe_path` maps to path.

This amendment records that the manifest read-side of Boundary 3 is sound because a `jq` parser on a JSON artifact is the read primitive — not a line-oriented heuristic that required per-pattern block-scalar awareness to resist injection. The three-call-site decomposition (allowlist + manifest-json + ledger-project) remains as described in the previous amendment. Status remains accepted.

## Amendment — 2026-06-01 (#168: containment anchor is git ground truth, not a manifest path; `path` value-class removed from the read side; item-4 structural-closure claim CORRECTED to accepted bounded residual)

The Boundary 3 CLOSED amendment confined each child ledger BENEATH the manifest's own `worktree_path`. That field is UNTRUSTED. #168 (full decision in ADR-0021) re-anchors the read side on git ground truth and corrects an over-claim about the leaf symlink-swap residual. This amendment records three points; it does not edit the Decision, Consequences, or any prior amendment.

1. **The containment anchor is git ground truth, NOT the manifest `worktree_path`.** `brood-status-project.sh` now parses `git worktree list --porcelain` into a branch→path map and selects each strain's REAL worktree by using the manifest's per-strain `branch` ONLY as a lookup KEY — the branch never becomes a path itself. The ledger is derived as `<git-worktree>/.hivemind/runs/<suggested_id>/state.json`, where only `<suggested_id>` is manifest-sourced (gated as a strict single-component identifier). The full chain is `CHECKOUT_ROOT ⊇ git-worktree ⊇ ledger`: the git-derived worktree must canonically sit beneath the checkout (a linked/sibling worktree git reports OUTSIDE the checkout fails closed), and the ledger leaf beneath that worktree. A garbage/non-matching branch selects nothing (fail-closed); a branch on two worktrees is `MALFORMED` (ambiguous). The manifest `worktree_path` residency gate is REMOVED — that field is now DISPLAY-ONLY. A tampered manifest path can no longer redirect the bounded reader, because no manifest path is consumed as an anchor.

2. **The `path` value-class is REMOVED from the read side.** With no manifest path consumed as an anchor, the `hivemind_assert_path` charset/floor gate no longer gates a load-bearing path on the read side; `worktree_path` survives only as a display column, gated by the floor and rendered through the projector's output encoder (escape `|`, strip C0/DEL). This is the floor-at-input / encode-at-output model (ADR-0021 §8): the input floor stays permissive (killing the #177 charset treadmill) and Markdown-cell safety lives at the render boundary.

3. **The item-4 leaf symlink-swap micro-TOCTOU is an ACCEPTED BOUNDED RESIDUAL — NOT structurally closed by #168 (CORRECTION).** Earlier prose framed per-brood isolation as the STRUCTURAL closure of the cross-worktree single-open leaf-swap window ("no cross-worktree reads of hostile-child files … tracked in #168"). That framing is CORRECTED. Per-brood-id namespacing isolates broods FROM EACH OTHER; it does NOT isolate the hatchery FROM its children. The hatchery reads untrusted child ledgers BY DESIGN — that is the monitoring feature — so a child swapping its OWN ledger leaf to a symlink in the micro-window between the `[ -L ]` re-check and the `cat` is in-scope for the read, not dissolved by namespacing. The residual is BOUNDED, not closed: a post-read `realpath` re-assert of containment beneath the git-worktree, never echoing raw bytes (only the validated `run.status` enum + `state.current` charset ever surface), and informational-only projection that never overrides observable status. bash has no portable `O_NOFOLLOW`; the window is deliberately narrowed, not engineered shut. The accurate statement is "accepted bounded residual," not "structurally dissolved."

This amendment is APPEND-ONLY. The original Decision, Consequences, and all prior amendments stand. Status remains accepted.

## Amendment — 2026-06-03 (read-guard leaf-symlink reject; closes the read-side ancestor/leaf asymmetry, #160)

The third amendment (point 4, ~line 108 above) and the inputs-file navigator prose recorded that `hivemind_assert_inputs_contained` makes each engine "refuse to READ an inputs file that resolves OUTSIDE the checkout." That guard previously rejected only a symlinked ANCESTOR of the inputs file; a symlinked inputs-file LEAF was NOT rejected — a documented asymmetry with the write-guard `hivemind_assert_file_contained`, which already `[ -L ]`-rejects a symlinked leaf (file-target containment primitive, recorded above). The earlier "structurally excluded" framing for the inputs leaf assumed a SAFE_ID_RE-gated leaf name; that assumption does NOT hold for the navigator-authored inputs-file path, where the leaf can be a symlink materialized below an otherwise-clean ancestor chain.

`hivemind_assert_inputs_contained` (in `plugin/skills/_shared/containment.sh`) now `[ -L ]`-rejects a symlinked inputs-file LEAF in addition to its existing symlinked-ancestor reject — the leaf reject fires even on a dangling target — mirroring the write-guard `hivemind_assert_file_contained`'s leaf reject. The read-guard's stated bound is corrected from "ancestor-only" to "ancestor OR leaf": it refuses to read an inputs file whose ancestor or leaf is a symlink resolving/pointing outside the checkout. The guard remains HONEST defense-in-depth — it does NOT prevent the external Write (the agent Write-tool transport has no engine-side guard ahead of it); it makes an external-resolving transport LOUD (refuse-to-read) rather than silent.

This amendment is APPEND-ONLY. The original Decision, Consequences, and all prior amendments stand. Status remains accepted.

## Amendment — 2026-06-03 (LEDGER-READ leaf now `[ -L ]`-rejected; leaf-symmetry across inputs/write/ledger-read complete, #160)

The prior framing — recorded in the third amendment (point 4, ~"shared read-guard") and in the `hivemind_assert_inputs_contained` amendment — stated that the ledger leaf (`state.json`) was covered by the ancestor walk via `hivemind_assert_contained`. That framing is INCORRECT. `hivemind_assert_contained` walks the chain passed to it; both ledger-reading engines passed `.hivemind/runs/<run_id>` — the run-directory, NOT the `state.json` leaf below it. A real-directory run-dir with a symlinked `state.json` leaf passed every ancestor check; the subsequent `[ -f "$ledger" ]` and `jq` reads followed the symlink to an external target — a content/validity read oracle the guard never inspected.

**The fix.** A new shared guard, `hivemind_assert_ledger_contained` (in `plugin/skills/_shared/containment.sh`), is called by both ledger-reading engines (`mark-intent-fallback.sh`, `record-state-result.sh`) BEFORE the first ledger read. It `[ -L ]`-rejects the `state.json` leaf on the RAW passed path (fires even for a dangling target, before any `[ -f ]`/`jq` read that follows symlinks), then canonicalizes the leaf's dirname and prefix-matches against the canonical checkout root — catching a symlinked ancestor as defense-in-depth. The guard mirrors `hivemind_assert_inputs_contained`'s read-guard structure.

**Leaf-symmetry complete.** This closes the last open leaf class, completing symmetry across all three leaf classes:
- Inputs-file leaf — `hivemind_assert_inputs_contained` (`[ -L ]` reject, closed earlier)
- Write-target leaf — `hivemind_assert_file_contained` (`[ -L ]` reject, closed earlier)
- Ledger-read leaf — `hivemind_assert_ledger_contained` (`[ -L ]` reject, THIS amendment)

**CHECK9 extended.** `policy_check.sh` CHECK9 is extended to assert that every containment-sourcing engine that reads a ledger calls `hivemind_assert_ledger_contained` before its first ledger read — terminal lint failure on absence, preventing regression.

This amendment is APPEND-ONLY. The original Decision, Consequences, and all prior amendments stand. Status remains accepted.

## Amendment — 2026-09-25 (the 2026-06-01 JSON-manifest amendment's brood-manifest literals are superseded; every dated literal in this ADR's notes and amendments is a snapshot, not authority; #375)

This amendment corrects two claims carried by the "JSON manifest root fix" paragraph of the 2026-06-01 JSON-manifest amendment above. Each item names the superseded claim and the live source that owns its subject. No item restates a current value, because a restated value is the defect being corrected: this ADR is append-only, so any value written here is frozen at its date while the source keeps moving. Item 3 states the standing rule that closes that whole class. This amendment does not edit the Decision, the Consequences, or any prior implementation note or amendment.

1. **The `manifest_version: 3` literal is SUPERSEDED.** That paragraph records the brood manifest's schema version as `manifest_version: 3`. The manifest schema, its version included, is owned by ADR-0021 and `plugin/references/brood-ledger-model.md`. This ADR states neither; a reader takes both from those sources.
2. **The claim that the manifest is "read by `jq` in both `spawn-brood`'s liveness guard and `brood-status`" is SUPERSEDED.** The `spawn-brood` liveness guard that sentence names no longer exists, so the sentence no longer describes the manifest's readers. Which components read the manifest, and how, is owned by ADR-0021 and `plugin/references/brood-ledger-model.md`; the inputs-file transport is owned by `plugin/governance/security-policy.md` ("Inert Inputs-File Navigator Pattern"). This ADR asserts no reader set and no replacement mechanism.
3. **Everything DATED in this ADR is a snapshot, not authority — this rule closes the class items 1-2 enumerate.** Items 1-2 each retire one stale literal, and that enumeration structurally cannot keep up: this ADR is append-only, so every note freezes the world as of its own date while the sources it describes keep moving. The standing rule, which needs no future amendment: every filesystem path, schema or format version number, count, membership list, and named mechanism that ANY implementation note or amendment of this ADR states as a value is dated as of THAT note's date and carries no authority today. A pointer that only names which live document or section owns a subject — such as the pointers in items 1-2, in the callout under the 2026-06-01 JSON-manifest amendment heading, and at the end of this item — is not such a value and is exempt: it states no value, only where the current value lives. A reader takes the current value from the live source, never from this file. This holds for every note and amendment above without exception. Live sources by subject — brood state layout and manifest schema: ADR-0021 and `plugin/references/brood-ledger-model.md`; inputs-file transport: `plugin/governance/security-policy.md` ("Inert Inputs-File Navigator Pattern"). A future divergence of this kind is corrected THERE and needs no further amendment here.

This amendment is APPEND-ONLY. The original Decision, Consequences, and all prior amendments stand. Status remains accepted.
