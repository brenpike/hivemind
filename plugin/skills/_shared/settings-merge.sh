# shellcheck shell=bash
#
# settings-merge.sh — shared `.claude/settings.json` required-key merge core (seed-hive).
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute
# path derived from its OWN script_dir (`. "$plugin_root/skills/_shared/settings-merge.sh"`).
# It defines functions only; it runs no top-level statements and changes no caller state
# beyond defining the functions below. `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately
# OMITS the P18 shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced
# file mutates the SOURCING shell's option state, so installing those here would corrupt
# every caller's shell; the floor is therefore the documented exception, not the full
# `set -euo pipefail`. This file carries no top-level `set` at all (pure function
# definitions); each caller owns its own `set -u` and error routing. Allowlisted under
# CHECK13 as a P18 documented exception.
#
# SINGLE RESPONSIBILITY: merge the hivemind required keys into a `.claude/settings.json`
# object with PRESERVE-EXISTING semantics, detect the `agent` conflict, and union-append the
# frozen `permissions.allow` template. This file is PURE MERGE: it does not read or write any
# file, resolve the project root, perform companion detection, touch `.gitignore` / `.envrc` /
# hooks, or invoke any skill — the entrypoint owns all of that. The settings JSON enters and
# leaves as a string; the caller does the I/O.
#
# SINGLE-SOURCE FROZEN TEMPLATE (P1): the recommended least-privilege `permissions.allow`
# template lives in EXACTLY ONE place — `hivemind_settings_permissions_template` below — as
# DATA. seed-hive/SKILL.md holds NO mirror of the rule list — it points here as the single
# source. No other site re-states the rule list; a caller that needs the template calls the
# function. The rule ORDER is load-bearing (the create-from-absent path emits the array in
# template order); do not reorder, drop, or reword an entry. New rules APPEND at the END.
#
# DATA-BOUNDARY: every dynamic value (the existing settings JSON, the agent target, each
# template rule) enters jq as an inert `--arg` / `--argjson` binding, NEVER interpolated into
# the jq program source. The settings JSON is parsed once via `--argjson` so jq validates it;
# malformed input is reported, never partially merged.
#
# MERGE INVARIANTS (mirror seed-hive/SKILL.md step 6 + Merge Rules, byte-preserving):
#   - PRESERVE-EXISTING: every key the caller already had that is not a required key is kept
#     untouched, in place. A required key already at the correct value is `already present`,
#     not re-added.
#   - enabledPlugins["hivemind@brenpike"] = true — add-if-absent; idempotent. VALUE-EQUALITY
#     classification: `already present` IFF the existing value already EQUALS the canonical
#     target (== true). The build unconditionally writes `true`, so a key present-but-false /
#     null / wrong-typed is NOT already present — it is reported `added` (corrected), matching
#     the write. An absent key is `added`; a key already `== true` is `already present`.
#   - enabledPlugins["caveman@caveman"] / ["claude-mem@thedotmack"] / ["codex@openai-codex"]
#     = true — written ONLY when the matching companion flag resolves yes; add-if-absent. Same
#     VALUE-EQUALITY classification (== true) once resolved yes; the `resolved no` short-circuit
#     (companion not resolved-yes) is checked FIRST, before the value test.
#   - agent = "<agent_target>" — add-if-absent. VALUE-STATE NORMALIZATION (ABSENT detection): an
#     existing `agent` that is missing, `null`, or a string that is EMPTY or WHITESPACE-ONLY ("",
#     " ", "\t") normalizes to ABSENT → classified `added` and the target is written. An empty /
#     whitespace agent is NOT a real conflicting value; it never blocks. A present NON-STRING value
#     (number/bool/object/array) is a real wrong-type value the user set and stays in the conflict
#     branch (NOT normalized to absent). CONFLICT DETECTION: if `agent` already holds a real
#     non-empty value DIFFERENT from the target, behavior is GATED by the 7th arg
#     <agent_conflict_approved>:
#       * approved != "yes" (default): the merge does NOT overwrite; it flags `agent_conflict`
#         with the existing value, returns `status: conflict`, and keeps the existing `agent`
#         byte-unchanged so the caller can stop blocked and seek user approval (SKILL.md Merge
#         Rules: "stop blocked and report the conflict. Do not overwrite without explicit user
#         approval").
#       * approved == "yes": the merge OVERWRITES `.settings.agent` to the target, classifies it
#         `overwritten`, returns `status: ok`, and `agent_conflict` is null. This restores the
#         base-prose contract: overwrite is permitted ONLY WITH explicit user approval.
#     NEVER-SILENTLY-OVERWRITE INVARIANT PRESERVED: an overwrite happens ONLY when the caller
#     passes approved=="yes", a flag the navigator sets ONLY after obtaining user approval. With
#     the flag absent/any-other-value the never-overwrite-on-conflict behavior is byte-identical
#     to the no-approval path. The approval gate is the conflict branch ONLY; an absent or
#     already-equal `agent` makes approval inert (normal add / already-present classification).
#   - pluginConfigs["caveman@caveman"].options.defaultLevel = "ultra" — caveman=yes only,
#     NESTED-LEAF add/correct on the SPECIFIC .options.defaultLevel leaf, NOT on the presence of
#     the parent "caveman@caveman" key. A parent config object that already exists but LACKS
#     defaultLevel (or holds a non-"ultra" value) is NOT configured for ultra mode: the leaf is
#     set to "ultra" while every sibling key in the config object and in .options is PRESERVED.
#     `already present` requires defaultLevel to ALREADY equal "ultra". Each container on the path
#     (config object, .options) is canon_obj-normalized so a wrong-typed nested container collapses
#     to {} before the leaf is set — a malformed nested config never crashes or clobbers.
#   - hooks.SubagentStart — the caveman ultra-mode hook entry (caveman=yes only). STRUCTURAL
#     IDENTITY on an EXEC-FORM entry, never substring matching. The canonical entry is
#     `{type:"command", command:"${CLAUDE_PROJECT_DIR}/.claude/hooks/caveman-ultra-subagent.sh",
#     args:[]}` — command UNQUOTED, `args` present and empty (see HOOK COMMAND ANCHORING below).
#     TWO-PASS build over each SubagentStart element's `.hooks[]`:
#       1. MIGRATE. A `{type:"command"}` entry with NO `args` key whose string `.command` is a
#          MEMBER of the FROZEN authored-shell-command list (the two shell-form commands hivemind
#          ITSELF ever wrote) is rewritten IN PLACE: `.command` = the canonical command AND
#          `.args` = []. Every sibling key on the entry, every sibling entry, any `matcher` on the
#          wrapping element, and array ORDER survive. The map runs ONLY when `.hooks` IS an array;
#          a wrong-typed `.hooks` is left exactly as the user had it.
#       2. APPEND-IF-ABSENT. The canonical entry is appended only when, AFTER pass 1, no entry
#          satisfies CANONICAL IDENTITY: `.type == "command"` AND `.args == []` AND
#          `.command == <canonical command>` — EXACT VALUE equality on ALL THREE fields, none of
#          them judged by TYPE. `contains()` appears nowhere. A non-empty or malformed `args`
#          (`[null]`, `[1]`, `["--x"]`) is therefore NOT the canonical entry: it is user-authored
#          variation, left byte-untouched, and it does NOT suppress the append.
#     An entry hivemind did NOT author is never removed or rewritten. An entry whose `.type` !=
#     "command" is an INVALID hook: neither migrated nor counted as present, left in place, and the
#     canonical entry is appended beside it. An existing unrelated SubagentStart array is PRESERVED.
#     TOTAL ELEMENT ACCESS (issue #355): EVERY ELEMENT POSITION this block reads — a SubagentStart
#     element, an entry inside its `.hooks` array, and any element position a future nesting level
#     adds — is read through `canon_elem` (`canon_obj(.)`), the element-position member of the SAME
#     canon_* law. Every element access is total. A non-conforming element is never migrated, never
#     counted present, and always preserved. A non-object element ("x", 1, true, ["x"]) reads as
#     `{}`, so every field test on it is false; `canon_elem` is a READ-VIEW ONLY and is NEVER the
#     value written back, so the ORIGINAL element survives byte-unchanged. This is NOT a new
#     contract — it is the wrong-`.type` rule above, made TOTAL.
#     NO-DUPLICATE-BY-CONSTRUCTION: pass 1 runs FIRST, so a migrated entry already satisfies
#     CANONICAL IDENTITY and suppresses the append — duplication is impossible by build ORDER, not
#     by a dedupe pass.
#     REPORT DERIVED FROM THE MUTATION (no second predicate exists): `already present` IFF the
#     POST-BUILD `.hooks.SubagentStart` deep-equals the canon-normalized PRE-STATE, else `added`
#     (append OR in-place migration — one token for both, exactly as the nested-leaf pluginConfigs
#     correction does, so the SKILL.md Output schema is unchanged); `resolved no` when caveman != yes.
#   - permissions.allow — union/append-if-absent of the frozen template (seed_allowlist=yes):
#     keep every existing entry in its original order, then append each template rule whose
#     exact string is NOT already present. NEVER overwrite, remove, dedupe, or reorder existing
#     entries. Absent `permissions.allow` → created containing only the template rules in
#     template order. `permissions` present without `allow` → `allow` added, sibling permissions
#     keys preserved. seed_allowlist=no → `permissions.allow` left untouched.
#   - IDEMPOTENT + BYTE-STABLE: re-merging an already-seeded settings object is a no-op — every
#     key reports `already present`, and the emitted `.settings` equals the input (modulo jq's
#     canonical key ordering, which is stable across re-runs).
#   - SHAPE-NORMALIZE-AT-ONE-CHOKEPOINT: every container-typed key (object-typed enabledPlugins /
#     pluginConfigs / hooks / permissions, array-typed permissions.allow) is normalized via the
#     shared canon_obj/canon_arr defs (sourced from json-normalize.sh, spliced as program text)
#     BEFORE any predicate (has() / index() / membership) or build assignment runs. A WRONG-TYPED
#     existing container is the canonical absent/needs-seed state: it collapses to {} / [] (it held
#     no contract-type entries to preserve), and the required seed is then add-if-absent over that
#     empty — so a malformed container NEVER aborts the jq program (no crash → no empty `.status` →
#     no seed abort) and NEVER clobbers a real value. ONE normalizer routes every container site,
#     classification AND build (so the report and the written settings share one canonical shape);
#     there is no per-key type branch. The law is NOT confined to KEY positions: EVERY ELEMENT
#     POSITION the merge reads is normalized by the SAME law through `canon_elem` (`canon_obj(.)`),
#     so a non-object element reads as `{}` — never migrated, never counted present, always
#     preserved — instead of aborting the program. Key positions and element positions are ONE law,
#     not two. A CORRECTLY-typed container is returned untouched, so correctly-typed inputs are
#     byte-identical to the pre-normalization behavior. This guard is NESTED-only: the top-level
#     non-object pre-check (status "malformed") still runs first.
#
# MALFORMED / EMPTY INPUT (SKILL.md step 4: "otherwise treat existing settings as {}"):
#   an EMPTY settings string is treated as `{}` (the absent-file case the caller passes through).
#   A NON-EMPTY but UNPARSEABLE settings string is NOT silently coerced to `{}` — that would
#   erase a user's real-but-torn file. It is reported via `status: "malformed"` and the caller
#   fails closed; no merge is performed.
#
# OUTPUT CONTRACT (consumed by the seed-hive entrypoint, future step):
#   hivemind_settings_merge emits ONE JSON object on stdout (exit 0 on a produced result; the
#   conflict and malformed cases are signalled IN-BAND in that object's `status`, not via exit
#   code, so the caller branches on `status`). Shape:
#     {
#       "status": "ok" | "conflict" | "malformed",
#       "settings": <merged settings object>,   // on malformed: the input is NOT echoed; null
#       "agent_conflict": null | { "existing": <str>, "required": <str> },  // null when overwritten
#       "keys": {                                // classification per required key
#         "enabledPlugins.hivemind@brenpike": "added" | "already present",
#           // VALUE-EQUALITY: "already present" IFF the value is ALREADY == true; a
#           // present-but-false/null/wrong-typed key is "added" (the build corrects it to true).
#         "agent": "added" | "already present" | "unchanged" | "conflict" | "overwritten",
#         "enabledPlugins.caveman@caveman": "added" | "already present" | "resolved no",
#         "enabledPlugins.claude-mem@thedotmack": "...",
#         "enabledPlugins.codex@openai-codex": "...",
#         "pluginConfigs.caveman@caveman": "added" | "already present" | "resolved no",
#           // NESTED-LEAF: "already present" ONLY when .options.defaultLevel is ALREADY
#           // "ultra"; "added" when the leaf had to be set or corrected (parent absent, OR
#           // parent present but defaultLevel missing / != "ultra"); "resolved no" when caveman != yes.
#         "hooks.SubagentStart": "added" | "already present" | "resolved no"
#           // DERIVED FROM THE MUTATION, never from an independent classification predicate:
#           // "already present" IFF the POST-BUILD `.hooks.SubagentStart` deep-equals the
#           // canon-normalized PRE-STATE `.hooks.SubagentStart` (the build changed nothing);
#           // "added" whenever the build APPENDED the canonical exec-form entry *or* MIGRATED an
#           // authored shell-form entry in place — there is no separate token for the correction,
#           // exactly as for pluginConfigs above; "resolved no" when caveman != yes. The enum is
#           // UNCHANGED; because the token is read off the mutation itself, a report that
#           // disagrees with what was written is arithmetically impossible.
#       },
#       "permissions_allow": [                   // one entry per template rule, in template
#         { "rule": <str>, "result": "added" | "already present" },   // order; [] when
#         ...                                                          // seed_allowlist=no
#       ]
#     }
#   `agent` classification: `added` (was absent — key missing/null, OR an empty/whitespace-only
#   string, which normalizes to ABSENT and the target is written), `already present`/`unchanged`
#   (already equal to the target — both map here; SKILL.md output allows either token), `conflict`
#   (a real non-empty value, OR a present non-string value, differing from the target AND not
#   approved; the conflict block is populated and `.settings.agent` is the existing value),
#   `overwritten` (differing real value AND approved=="yes"; `.settings.agent` is the target and
#   the conflict block is null).
#
# HOOK COMMAND ANCHORING (issue #352) — the canonical SubagentStart entry is EXEC (argv) FORM:
# `{type:"command", command:"${CLAUDE_PROJECT_DIR}/.claude/hooks/caveman-ultra-subagent.sh",
# args:[]}`. Not a bare relative path, and no longer a quoted shell-form command string.
#   VERIFIED MECHANISM (AUTHORITY: read from the hook-exec function in the INSTALLED Claude Code
#   2.1.243 binary plus the official hooks reference — established as engine evidence, NOT inferred
#   from docs prose or from how the previous form appeared to behave):
#     * The hook exec function BRANCHES on whether `args` is DEFINED. The test is `!== undefined`,
#       NOT a length test, and the Zod schema is `args: z.array(z.string()).optional()` — so `[]`
#       is valid AND selects the exec branch. `args: []` is the minimal opt-in.
#     * EXEC branch (`args` PRESENT): the harness substitutes `${CLAUDE_PROJECT_DIR}` PER ELEMENT
#       as a plain string, then spawns the command directly via execve. There is NO `shell:` option
#       on that spawn. NO SHELL PARSES THE COMMAND.
#     * SHELL branch (`args` ABSENT): spawned with `shell:true` on POSIX, and the `${...}`
#       substitution NEVER RUNS — it was the shell's OWN environment expansion that made the
#       previously-shipped quoted form work at all.
#     * `args` was introduced in Claude Code 2.1.139 (2026-05-12).
#   The former header claim that "the harness substitutes it before execution, so no shell is
#   required" was FALSE for the shell form this file used to ship, and has been DELETED rather than
#   softened: under the shell branch the harness performs no substitution whatsoever.
#   MINIMUM ENGINE: the seeded exec-form entry expects Claude Code >= 2.1.139. On an engine older
#   than that, `args` is not in the schema and the entry does not select exec form.
#   WHY THE COMMAND IS UNQUOTED: under exec form the substituted string reaches execve VERBATIM, so
#   surrounding double quotes would become LITERAL leading/trailing path characters and break the
#   spawn. The quotes the shell form needed are precisely what the exec form must NOT carry.
#   STRUCTURAL IDENTITY CONTRACT, and the CLASSES it makes IMPOSSIBLE (not merely handled):
#     * No shell is anywhere in the execution path, so "a byte stored in the command string is
#       re-interpreted by a shell" is UNREPRESENTABLE. Spaces, quotes, `$`, `;`, and backticks in
#       the project root are inert path bytes to execve. There is no quoting to get right here, so
#       there is no quoting bug for a later pass to find. This is why the fix changes the PRIMITIVE
#       (the command string stops being an unparsed shell payload) instead of adding another
#       escaping rule to the same string.
#     * Identity is EXACT VALUE EQUALITY on an exec-form entry — `.type == "command"` AND
#       `.args == []` AND `.command == <canonical command>` — never substring containment, and
#       never a type test standing in for a value. Because the identity key is exactly the value
#       this file WRITES, "which nearby shapes also count as ours" is UNREPRESENTABLE — there is no
#       loosely-judged field left for a later pass to tighten one accepted value at a time.
#       The substring FALSE-POSITIVE class is gone for seeded wiring: `echo <path>`,
#       `/some/other/project/<path>`, and `true # <path>` no longer count as "hivemind's hook is
#       wired". `contains()` MUST NOT reappear anywhere in this block.
#     * Every element access is total. A non-conforming element is never migrated, never counted
#       present, and always preserved. EVERY element position is read through `canon_elem`
#       (`canon_obj(.)`), so "a malformed element aborts the merge before anything is written" is
#       UNREPRESENTABLE — for EVERY element position, present and future, not for an enumerated
#       pair of them. A second class dies with it: a non-object element can never satisfy the
#       identity predicate above, so it can never suppress the canonical append. This is
#       deliberately NOT a per-site `type == "object"` guard: with `canon_elem` the guard count is
#       a function of the data's NESTING DEPTH (2, fixed by the settings schema), NOT of the NUMBER
#       OF FIELD READS (unbounded, and it grows every time someone adds a conjunct). Guard-per-read
#       is complete-the-known-set — the discriminator that already failed twice on this surface.
#   FROZEN AUTHORED-SHELL-COMMAND LIST: migration matches ONLY the two shell-form commands hivemind
#   ITSELF ever wrote — the bare relative path (released at 2.40.10) and the double-quoted anchored
#   path (added on this branch at the unreleased 2.40.11). The list is CLOSED BY OUR OWN GIT
#   HISTORY: it enumerates what THIS file emitted in past releases, so it can NEVER grow from user
#   input and no user-authored string can enter it. Both members are built from the single
#   `$hook_rel` literal, so the script path appears in exactly ONE place.
#   REPORT DERIVED FROM THE MUTATION: the `hooks.SubagentStart` token is computed by comparing the
#   POST-BUILD `.hooks.SubagentStart` against the canon-normalized PRE-STATE — there is NO second,
#   independent classification predicate. With nothing to disagree with, a report that contradicts
#   what was actually written is arithmetically impossible rather than merely unlikely.
#   DELIBERATE DROP (accepted, one-way): a user's OWN shell-form wrapper around this script is
#   still left BYTE-UNTOUCHED — the merge never rewrites what it did not author — but it NO LONGER
#   SUPPRESSES the canonical append. Such a project gains ONE additional entry, ONCE; the append is
#   idempotent thereafter. FAILURE-DIRECTION RATIONALE: suppression-by-heuristic failed as "the
#   hook is SILENTLY NEVER WIRED" — the reviewer reproduced three shapes (`echo <path>`,
#   `/some/other/project/<path>`, `true # <path>`) that each suppressed the append while wiring
#   nothing. Exact identity fails in the OPPOSITE direction: "the context hook fires twice" —
#   visible, harmless, bounded, and idempotent. The visible bounded failure is the one to prefer.
#   FAILURE MECHANISM THIS ACTUALLY REPAIRS: INTRA-SESSION WORKING-DIRECTORY DRIFT. A bare
#   relative command is resolved against the session's CURRENT working directory at hook-fire
#   time, so a `cd` issued through the Bash tool — or an RC attach carrying its own
#   session_context.cwd — moves the resolution root out from under an ALREADY-REGISTERED hook and
#   it silently stops firing. Anchoring removes that dependency on cwd entirely.
#   FAILURE MECHANISM THIS CANNOT REPAIR (do NOT verify the fix against it): a session LAUNCHED
#   from a subdirectory never loads the repo-root `.claude/settings.json` at all — settings
#   discovery does not walk upward — so the hook is never REGISTERED in that session. Anchoring a
#   command that was never read changes nothing. The issue's own reproduction steps describe THAT
#   scenario, which is a different defect from the one repaired here.
#   WHY NO DEFENSE IN THE HOOK SCRIPT BODY: a script-body guard against an unset/empty anchor is
#   ineffective BY CONSTRUCTION — if the anchor resolves empty, the COMMAND fails to locate the
#   script, the script therefore never executes, and nothing written inside it can run.
#   DRIFT NOTE (TWO-SIDED COUPLING): the path TAIL of this command must remain identical to the
#   path `hivemind_scaffold_hook_file` (file-guard.sh) CREATES and to the path the seed-hive
#   entrypoint passes that function. The command and the file move together or not at all.
#
# DEPENDENCY: jq only (POSIX + jq). No yq, no sed/awk.
#
# SHAPE-NORMALIZATION AT ONE CHOKEPOINT (P22 / canon_obj+canon_arr): every container-typed key the
# merge reads (the object-typed enabledPlugins / pluginConfigs / hooks / permissions, and the
# array-typed permissions.allow) is normalized to its canonical empty container BEFORE any predicate
# runs. A WRONG-TYPED existing container (e.g. enabledPlugins as an array/string, permissions.allow as
# a string) is NOT a preservable user value — it holds no entries of the contract type — so it
# collapses to {} / [] via the shared canon_obj/canon_arr defs (sourced from json-normalize.sh and
# spliced as fixed PROGRAM TEXT at the top of the single jq program). The required seed is then
# add-if-absent over that canonical empty: the merge returns status "ok" (NEVER crashes the jq program
# and NEVER clobbers a real value), because a malformed container held no real entry to preserve. ONE
# normalizer routes every container site (classification AND build) — no per-key type branch. The
# top-level non-object pre-check (status "malformed") still runs FIRST; only NESTED container keys are
# shape-normalized here. A CORRECTLY-typed container is returned untouched, so correctly-typed inputs
# are byte-identical to before.
# THE SAME LAW COVERS ELEMENT POSITIONS (issue #355): the chokepoint is not container KEYS only.
# EVERY ELEMENT POSITION the merge reads is normalized by the same law through the local
# `def canon_elem: canon_obj(.);` — the TOTAL OBJECT VIEW of an element, and a READ-VIEW ONLY (never
# the value written back). Every element access is total: a non-conforming element is never migrated,
# never counted present, and always preserved. `canon_elem` is named into the `canon_*` family
# deliberately — it is the element-position member of ONE law, not a second mechanism — and it stays
# LOCAL to this program rather than moving into json-normalize.sh: rule-of-three is UNMET (see the
# P23 placement evidence at the SubagentStart build below, and ADR-0028's element-access amendment).

# ── self-location + sibling-lib source (SOURCE-OR-DIE) ──────────────────────────
# THIS file is itself a SOURCED lib (no shebang); BASH_SOURCE[0] still resolves to this file's own
# path when sourced, so we self-locate the _shared dir from it (never a caller value) and source the
# json-normalize.sh sibling that supplies the canon_obj/canon_arr def text. SOURCE-OR-DIE: a missing
# or unparseable sibling returns non-zero from this fragment so the caller (entrypoint loop / test
# harness) fails closed exactly as it does for this file — the merge cannot run its shape guard
# without those defs. Re-sourcing is idempotent (it only redefines a pure echo function).
# Each step carries an explicit `|| return 1`: errexit is off inside a file sourced under the caller's
# `|| fail`, so without it a failed cd or sibling source would fall through and this fragment return 0.
__settings_merge_shared_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || return 1
[ -f "$__settings_merge_shared_dir/json-normalize.sh" ] || return 1
# shellcheck source=/dev/null
. "$__settings_merge_shared_dir/json-normalize.sh" || return 1
unset __settings_merge_shared_dir

# hivemind_settings_permissions_template
# Emit the frozen least-privilege `permissions.allow` template, ONE rule per line, in the
# canonical (load-bearing) order. This is the SINGLE DATA source for the template (P1); the
# merge function reads it through this function, and any caller that needs to display or test
# the template uses it too. Pure: no side effects, no exit, reads no input.
#
# INVARIANT: this list is the SINGLE source of the frozen template — no mirror exists in
# seed-hive/SKILL.md. The order is canonical and load-bearing (absent-array creation emits in
# this order). Do not reorder, drop, or reword an entry; add new rules at the END only, since
# the merge is union append-if-absent and never reorders an existing consumer's array.
#
# INVARIANT (REACH): a rule appended here reaches an ALREADY-SEEDED consumer ONLY when
# `hivemind:seed-hive` is re-run against that project. This template is merged into a consumer's
# `.claude/settings.json` at seed time and at NO other time — a plugin upgrade alone delivers
# NOTHING, because upgrading never re-merges settings. Adding a rule here is therefore only half
# a fix; the consumer-facing half is telling upgraders to re-seed (the upgrade-path bullet under
# `## When to Use` in seed-hive/SKILL.md). The merge is idempotent append-if-absent, so the
# re-seed is always safe and preserves existing entries. See issue #323.
#
# ONE-TIME DROP: the former `Bash(node /path/to/.claude/plugins/cache/openai-codex/codex/*)` entry
# was deleted from this template. `/path/to/` is a DOCUMENTATION PLACEHOLDER that had been frozen
# into runtime data, and this heredoc is single-quoted, so nothing ever expanded it — the rule
# shipped verbatim and matched NO real path on ANY machine. It was therefore unmatchable as
# shipped, so nothing could ever have depended on it. The drop also mutates NO existing consumer
# file: the merge is union append-if-absent and NEVER removes, so dropping the entry only stops
# new seeds and re-seeds from adding it. An ALREADY-SEEDED consumer keeps the dead entry until a
# human deletes it by hand. Automatic removal is DELIBERATELY NOT IMPLEMENTED — it would break the
# never-remove invariant above, and it could delete a rule a user had already repaired to point at
# their real `$HOME` cache path.
#
# INVARIANT (NO-PROVIDER-GRANT): no local-review provider grant — codex today, or copilot or
# any future provider — may be added to this template. Two reasons:
#   1. This template merges into a COMMITTED, team-shared `.claude/settings.json`, so a
#      machine-specific `$HOME` cache path is wrong-by-construction for everyone but the seeder.
#   2. Per-contributor grants belong in the GITIGNORED `.claude/settings.local.json`, which is
#      exactly what `.devcontainer/postCreate.sh` already does.
# The full rationale for this invariant lives in ADR-0010.
#
# INVARIANT (NO-PATH-ANCHOR-IN-PERMISSION-RULES): the six navigator-transport rules below that
# target `.hivemind/` paths stay RELATIVE BY DECISION. They must NOT be anchored the way the
# SubagentStart hook command is (see HOOK COMMAND ANCHORING in the header) — the two surfaces are
# not analogous:
#   1. Permission rules perform NO `${...}` expansion. An anchored rule is matched LITERALLY, so
#      it would only ever match a directory actually NAMED `${CLAUDE_PROJECT_DIR}` — it would
#      silently grant nothing while looking correct.
#   2. A leading `/` is no better: it anchors to the SESSION's ORIGINAL cwd, not to the project
#      root, so it does not express "relative to the project" either.
#   3. `Bash(...)` rules match command TEXT, not filesystem paths, so a path anchor is meaningless
#      in them by construction.
# ADR-0010 carries the full rationale. Do not "fix" these rules by anchoring them.
hivemind_settings_permissions_template() {
  cat <<'TEMPLATE'
Bash(echo *)
Bash(printf *)
Bash(cat *)
Bash(grep *)
Bash(jq *)
Bash(head *)
Bash(tail *)
Bash(ls *)
Bash(wc *)
Bash(sort *)
Bash(uniq *)
Bash(git ls-files *)
Bash(git ls-tree *)
Bash(git grep *)
Bash(git tag)
Bash(git tag -l*)
Bash(git tag --list*)
Bash(git stash list)
Bash(git stash show *)
Edit(.hivemind/review-loop/*)
Edit(.hivemind/runs/.init-inputs-*.json)
Edit(.hivemind/runs/.record-inputs-*.json)
Edit(.hivemind/runs/.markfb-inputs-*.json)
Edit(.hivemind/spawn-inputs.*.json)
Edit(.hivemind/seed-inputs-*.json)
TEMPLATE
}

# hivemind_settings_merge <settings_json> <agent_target> <caveman_yes> <claude_mem_yes> \
#                         <codex_yes> <seed_allowlist_yes> [<agent_conflict_approved>]
#
# Merge the hivemind required keys into <settings_json> per the MERGE INVARIANTS in the header
# and emit the OUTPUT CONTRACT JSON object on stdout. The first six arguments are required; the
# 7th (<agent_conflict_approved>) is optional and defaults to "no" so existing 6-arg callers are
# byte-unchanged.
#
# ARGUMENTS
#   <settings_json>     the current `.claude/settings.json` contents as a string. EMPTY → treated
#                       as `{}` (absent-file case). Non-empty unparseable → status "malformed".
#   <agent_target>      the required `agent` value, e.g. "hivemind:overlord". Enters jq as --arg.
#   <caveman_yes>       "yes" → write the caveman enabledPlugins/pluginConfigs/hook keys; any
#                       other value → those keys are skipped (classified "resolved no").
#   <claude_mem_yes>    "yes" → write enabledPlugins["claude-mem@thedotmack"]; else "resolved no".
#   <codex_yes>         "yes" → write enabledPlugins["codex@openai-codex"]; else "resolved no".
#   <seed_allowlist_yes>"yes" → union-append the frozen permissions.allow template; any other
#                       value → permissions.allow left untouched, permissions_allow = [].
#   <agent_conflict_approved>  OPTIONAL (default "no"). "yes" → authorize an `agent` OVERWRITE on
#                       the conflict branch (existing differs from target): write the target,
#                       classify `overwritten`, status "ok", no conflict block. Any other value /
#                       absent → never overwrite on conflict (status "conflict", agent unchanged).
#                       Inert when `agent` is absent or already equal to the target. Evaluated
#                       ONLY AFTER the malformed-settings fail-closed check: a non-empty
#                       unparseable blob with approved=="yes" STILL returns status "malformed" —
#                       approval authorizes an agent overwrite, NEVER clobbering a torn file.
#
# The settings JSON enters jq as --argjson (jq validates it); the agent target and each toggle
# enter as --arg; the template enters as --argjson (a JSON array built from the single DATA
# source). No dynamic value is ever spliced into the jq program text. The whole classification
# and merge run INSIDE one jq program so the verdict is computed against the parsed document,
# never against post-extraction bash strings.
hivemind_settings_merge() {
  local settings_json="$1"
  local agent_target="$2"
  local caveman_yes="$3"
  local claude_mem_yes="$4"
  local codex_yes="$5"
  local seed_allowlist_yes="$6"
  # OPTIONAL 7th arg: authorize an agent overwrite on the conflict branch. Default "no" so
  # existing 6-arg callers are byte-unchanged. This is a controlled "yes"/"no" string bound
  # inertly into jq as --arg below — it is NEVER spliced into jq program source.
  local agent_conflict_approved="${7:-no}"

  # EMPTY input is the absent-file case (SKILL.md step 4): treat as {}. A NON-EMPTY but
  # invalid input is NOT coerced — report malformed so the caller fails closed rather than
  # silently erasing a torn real file. "Invalid" covers: unparseable JSON, valid JSON that is
  # not an object (a settings file must be an object), AND a multi-document stream (two or more
  # concatenated top-level documents). The bare `jq -e 'type=="object"'` precheck accepted
  # multi-doc streams because jq streams them and exits 0 on the last document; the downstream
  # `--argjson settings` then rejected the stream and crashed. hivemind_jq_is_single_object_stdin
  # (STEP-001, json-normalize.sh) slurps into an array and requires length==1 AND type==object,
  # closing the multi-doc case while subsuming the old type check.
  if [ -z "$settings_json" ]; then
    settings_json='{}'
  elif ! printf '%s' "$settings_json" | hivemind_jq_is_single_object_stdin; then
    # Multi-document stream, unparseable JSON, or valid JSON that is not an object.
    jq -n '{status:"malformed", settings:null, agent_conflict:null, keys:{}, permissions_allow:[]}'
    return 0
  fi

  # Build the template as a JSON array from the SINGLE DATA source, passed inert via --argjson.
  local template_json
  template_json="$(hivemind_settings_permissions_template | jq -R . | jq -s .)"

  # Capture the shared container-normalization defs as PROGRAM TEXT (a constant def block; no
  # runtime value is interpolated). Spliced verbatim at the TOP of the single jq program below so
  # canon_obj/canon_arr are in scope before any predicate uses them. DATA-BOUNDARY preserved: this
  # is jq source text only — every runtime value still enters via --argjson/--arg.
  local canon_defs
  canon_defs="$(hivemind_jq_canon_defs)"

  # Single jq program: classify every required key against the PARSED input, then build the
  # merged settings with preserve-existing semantics. Toggles and the agent target are inert
  # --arg bindings; the template and parsed settings are inert --argjson bindings.
  jq -n \
    --argjson settings "$settings_json" \
    --arg agent "$agent_target" \
    --arg caveman "$caveman_yes" \
    --arg claude_mem "$claude_mem_yes" \
    --arg codex "$codex_yes" \
    --arg seed_allow "$seed_allowlist_yes" \
    --arg agent_approved "$agent_conflict_approved" \
    --argjson template "$template_json" '
    # ── shared container-shape normalizers (spliced PROGRAM TEXT from json-normalize.sh) ──
    # canon_obj(f) → f when f is an object, else {}; canon_arr(f) → f when an array, else [].
    # These collapse a wrong-typed container to its canonical empty BEFORE any predicate runs.
    '"$canon_defs"'
    # ── total ELEMENT view: the element-position member of the SAME canon_* law ───
    # CONTRACT: every element access is total. A non-conforming element is never migrated, never
    # counted present, and always preserved. canon_elem is the TOTAL OBJECT VIEW of an element (a
    # non-object reads as {}, so every field test on it is false). It is a READ-VIEW ONLY: it is
    # NEVER the value written back, so the ORIGINAL element survives byte-unchanged through the
    # `else . end` branches. Named into the canon_* family on purpose — key positions and element
    # positions are ONE law. Kept LOCAL (rule-of-three unmet); the P23 placement evidence sits at
    # the SubagentStart build below.
    def canon_elem: canon_obj(.);
    # ── helpers ──────────────────────────────────────────────────────────────────
    # getpath-safe presence test for a nested key, run over the SHAPE-normalized enabledPlugins
    # object so a wrong-typed enabledPlugins (array/string/etc.) collapses to {} instead of
    # aborting has() — an absent enabledPlugins then classifies every companion as "added".
    def has_enabled($k): canon_obj($settings.enabledPlugins) | has($k);

    # VALUE-EQUALITY presence test for an enabledPlugins entry, run over the SHAPE-normalized
    # enabledPlugins object: true IFF the existing value already EQUALS the canonical target (true).
    # The build unconditionally writes `true`, so a key present-but-false/null/wrong-typed needs
    # correcting and must classify "added", NOT "already present" — this is value-not-presence.
    def enabled_true($k): canon_obj($settings.enabledPlugins) | (.[$k] == true);

    # ── caveman SubagentStart hook identity constants (PROGRAM TEXT, not --arg) ──
    # SINGLE LITERAL: the hook script path is written ONCE in this program; every site that needs
    # it — the migrate pass, the append predicate, and the written value — routes through these
    # bindings. They are FIXED program constants, not runtime values, so the DATA-BOUNDARY rule
    # above (which governs DYNAMIC values only) does not require a --arg here.
    #   $hook_rel  — the relative script path, the SINGLE literal every other constant is built
    #                from. It is NOT an identity substring: nothing matches on containment.
    #   $hook_cmd  — the canonical EXEC-FORM command. UNQUOTED by construction: under exec form the
    #                substituted string reaches execve verbatim, so surrounding `"` would become
    #                literal path characters and break the spawn. See HOOK COMMAND ANCHORING above.
    #   $hook_entry— the canonical entry. `args: []` is what SELECTS exec form (the engine branches
    #                on `args` being defined, not on its length), so it is load-bearing, not filler.
    #   $authored_shell_cmds — the FROZEN list of shell-form commands hivemind ITSELF wrote: the
    #                bare relative path (released 2.40.10) and the double-quoted anchored path
    #                (unreleased 2.40.11). CLOSED BY OUR OWN GIT HISTORY — it enumerates the past
    #                output of THIS file, so it can never grow from user input. Migration matches
    #                MEMBERSHIP in this list; a command hivemind did not author is never rewritten.
    ".claude/hooks/caveman-ultra-subagent.sh" as $hook_rel
    | ("${CLAUDE_PROJECT_DIR}/" + $hook_rel) as $hook_cmd
    | ({ type: "command", command: $hook_cmd, args: [] }) as $hook_entry
    | ([ $hook_rel, ("\"${CLAUDE_PROJECT_DIR}\"/" + $hook_rel) ]) as $authored_shell_cmds

    # Every container-typed key is normalized at binding time so a wrong-typed existing value
    # collapses to its canonical empty container ({} / []) here, once, for both classification and
    # build. permissions.allow normalizes its parent object first, then the allow array.
    | ($settings) as $s
    | canon_obj($s.enabledPlugins) as $ep
    | canon_obj($s.permissions) as $perm
    | (canon_arr($perm.allow)) as $existing_allow
    # CANON-NORMALIZED PRE-STATE of the SubagentStart array. This is the ONLY input to the
    # hooks.SubagentStart report token: it is compared against the POST-BUILD array below, so the
    # token is READ OFF THE MUTATION rather than recomputed by an independent predicate that could
    # disagree with it. Normalized here (not raw) so the comparison is against the same canonical
    # shape the build starts from — a wrong-typed hooks/SubagentStart collapses identically on both
    # sides and therefore reports on the real difference, not on the normalization.
    | (canon_arr(canon_obj($s.hooks).SubagentStart)) as $pre_subagent

    # ── agent value-state normalization (ABSENT / PRESENT-CANONICAL / PRESENT-MALFORMED) ──
    # An existing `agent` is ABSENT when the key is missing/null OR is a string that is empty or
    # whitespace-only — an empty/whitespace string is not a real conflicting value the user chose,
    # so it normalizes to ABSENT and the target is written (classified "added"), NOT "conflict".
    # A real non-empty string equal to the target is PRESENT-CANONICAL ("already present"); a real
    # non-empty string DIFFERING from the target is the genuine conflict, gated by approval below.
    # A present NON-STRING value (number/bool/object/array) is a real wrong-type value the user set
    # and is NOT in the normalized-ABSENT set: it is treated as a differing value (conflict branch).
    | ($s.agent) as $cur_agent
    | (($cur_agent | type) == "string"
       and (($cur_agent | gsub("^\\s+|\\s+$"; "")) == "")) as $agent_is_blank
    # ── agent conflict detection (PRESERVE-EXISTING; overwrite ONLY with explicit approval) ──
    # Differing existing agent: classify "overwritten" when the caller passed approved=="yes"
    # (the navigator sets this ONLY after user approval), else "conflict" (never overwrite).
    | (if ($cur_agent == null or $agent_is_blank) then "added"
       elif ($cur_agent == $agent) then "already present"
       elif ($agent_approved == "yes") then "overwritten"
       else "conflict" end) as $agent_class
    | (if $agent_class == "conflict"
       then {existing: $cur_agent, required: $agent}
       else null end) as $agent_conflict

    # ── permissions.allow union/append-if-absent (seed_allowlist = yes) ───────────
    # Keep existing entries in order, then append only template rules not already present.
    # $existing_allow is already canon_arr-normalized above (always an array, never null/wrong-typed),
    # so index()/$base + [...] cannot abort even when the source permissions.allow was wrong-typed.
    | (if $seed_allow == "yes"
       then $existing_allow
       else null end) as $base_allow
    | (if $seed_allow == "yes"
       then [ $template[] | . as $r | { rule: $r, result:
                ( if ($existing_allow | index($r)) != null
                  then "already present" else "added" end ) } ]
       else [] end) as $allow_report
    | (if $seed_allow == "yes"
       then ($base_allow + [ $template[] | . as $r | select( ($base_allow | index($r)) == null ) ])
       else $existing_allow end) as $merged_allow

    # ── required-key classification ──────────────────────────────────────────────
    | (if enabled_true("hivemind@brenpike") then "already present" else "added" end) as $c_hive
    | (if $caveman != "yes" then "resolved no"
       elif enabled_true("caveman@caveman") then "already present" else "added" end) as $c_cave
    | (if $claude_mem != "yes" then "resolved no"
       elif enabled_true("claude-mem@thedotmack") then "already present" else "added" end) as $c_mem
    | (if $codex != "yes" then "resolved no"
       elif enabled_true("codex@openai-codex") then "already present" else "added" end) as $c_codex
    # NESTED-LEAF classification: the contract value is pluginConfigs["caveman@caveman"]
    # .options.defaultLevel == "ultra", NOT the mere presence of the parent key. A parent
    # object present WITHOUT (or with a non-"ultra") defaultLevel is NOT configured for ultra
    # mode — it must be corrected (classified "added"). canon_obj normalizes the config object
    # and its .options so a wrong-typed nested container collapses to {} before the leaf read.
    | (if $caveman != "yes" then "resolved no"
       elif ((canon_obj($s.pluginConfigs) | canon_obj(.["caveman@caveman"]) | canon_obj(.options).defaultLevel) == "ultra")
         then "already present"
       else "added" end) as $c_pcfg
    # NOTE: there is deliberately NO SubagentStart classification predicate here. Its report token
    # is DERIVED from the effect of the build itself further below ($c_hook, after $merged) — see HOOK
    # COMMAND ANCHORING in the header. A second predicate is exactly what allowed the report and
    # the written settings to diverge; removing it makes that divergence unrepresentable.

    # ── build the merged settings (PRESERVE-EXISTING) ────────────────────────────
    | $s
    # enabledPlugins required entry + conditional companion entries (add-if-absent: setpath
    # only widens, never removes a key the user already had).
    | .enabledPlugins = ($ep + {"hivemind@brenpike": true})
    | (if $caveman == "yes" then .enabledPlugins += {"caveman@caveman": true} else . end)
    | (if $claude_mem == "yes" then .enabledPlugins += {"claude-mem@thedotmack": true} else . end)
    | (if $codex == "yes" then .enabledPlugins += {"codex@openai-codex": true} else . end)
    # agent: write the target when absent, already equal, or "overwritten" (differing + approved);
    # on "conflict" (differing + NOT approved) leave the existing value byte-unchanged (the caller
    # stops blocked on $agent_conflict). Overwrite happens ONLY via the approved=="yes" gate.
    | (if $agent_class == "conflict" then . else .agent = $agent end)
    # caveman pluginConfigs — NESTED-LEAF merge (add/correct the specific
    # .options.defaultLevel == "ultra" leaf, PRESERVING every sibling key). The earlier
    # parent-presence test left an existing caveman config that lacked (or mis-set)
    # defaultLevel unchanged, so ultra mode was never actually configured. Here every
    # container on the path is canon_obj-normalized (the config object and its .options) so a
    # wrong-typed nested container collapses to {} BEFORE the leaf is set — a malformed config
    # can neither crash nor clobber. Sibling keys in the config object and in .options are kept;
    # only .options.defaultLevel is set to "ultra". Already-ultra → byte-stable no-op.
    | (if $caveman == "yes"
       then .pluginConfigs = (canon_obj(.pluginConfigs)
              | .["caveman@caveman"] = (canon_obj(.["caveman@caveman"])
                  | .options = (canon_obj(.options) | .defaultLevel = "ultra")))
       else . end)
    # caveman SubagentStart hook — TWO-PASS build. The ORDER is what makes duplication impossible
    # BY CONSTRUCTION rather than by a dedupe pass:
    #   (a) MIGRATE: every entry that is `{type:"command"}`, has NO `args` key, and whose STRING
    #       `.command` is a MEMBER of $authored_shell_cmds is rewritten IN PLACE to exec form —
    #       `.command` = $hook_cmd AND `.args` = []. Only those two keys are assigned, so every
    #       sibling key on that entry (e.g. timeout), its sibling entries in the `.hooks` array, any
    #       `matcher` key on the wrapping SubagentStart element, and array ORDER all survive. The
    #       map runs ONLY when `.hooks` IS an array — a wrong-typed `.hooks` is left exactly as the
    #       user had it rather than being clobbered by the normalizer. Membership (not containment)
    #       is the gate, and the list is closed by our own git history, so this pass can only ever
    #       touch wiring hivemind itself wrote.
    #   (b) APPEND-IF-ABSENT: the canonical entry is appended only when, AFTER (a), no entry
    #       satisfies CANONICAL IDENTITY — `.type == "command"` AND `.args == []` AND
    #       `.command == $hook_cmd`. All THREE conjuncts are EXACT VALUE equality against what this
    #       file EMITS; not one field is judged by TYPE. That is what makes identity closed by
    #       construction rather than a set of accepted shapes: there is no remaining field whose
    #       "close enough" values a later pass could enumerate. In particular `args: [null]`,
    #       `args: [1]`, or any non-empty `args` is NOT the canonical entry — it is user-authored
    #       variation, so it is left BYTE-UNTOUCHED and does NOT suppress the append (same accepted
    #       DELIBERATE DROP, and same failure direction, as the user-authored shell wrapper below).
    #       Pass (a) has already converted every authored shell-form entry to exactly the canonical
    #       shape (it assigns `.args = []`), so a migrated entry suppresses the append and no
    #       duplicate can be created. GIVEN AN OBJECT ENTRY, `.args == []` and
    #       `.command == $hook_cmd` are total over every VALUE those two fields can hold, so no
    #       malformed `command`/`args` VALUE can abort this predicate.
    #   TOTAL ELEMENT ACCESS (issue #355) — the totality claim now covers the ELEMENT itself, not
    #       only the two FIELD VALUES. EVERY ELEMENT ACCESS IS TOTAL. A NON-CONFORMING ELEMENT IS
    #       NEVER MIGRATED, NEVER COUNTED PRESENT, AND ALWAYS PRESERVED. Both passes read their
    #       element through `canon_elem` (`canon_obj(.)`) — the TOTAL OBJECT VIEW of an element, and
    #       a READ-VIEW ONLY: it is never the value written back. A non-object element (a scalar or
    #       an array sitting directly in `SubagentStart[]`, or inside a `.hooks[]` array) reads as
    #       `{}`, so every field test below is false, the migrate branch cannot fire, the identity
    #       predicate cannot be satisfied, and `else . end` writes the ORIGINAL element back. That
    #       makes preservation STRUCTURAL — there is no added preserve case. Formerly-aborting
    #       inputs now merge cleanly: `{"hooks":{"SubagentStart":["x"]}}` and
    #       `{"hooks":{"SubagentStart":[{"hooks":["x"]}]}}`.
    #       NOT A NEW CONTRACT: this file already applies exactly this rule to a wrong-`.type`
    #       entry — neither migrated nor counted present, left in place, canonical entry appended
    #       beside it. This change makes that existing rule TOTAL. The rejected alternative was
    #       routing a wrong-typed element to the `malformed` fail-closed status: that invents a new
    #       failure path for input the merge can simply walk past.
    #   WHY NOT A PER-SITE `type == "object"` GUARD: with `canon_elem` the guard count is a function
    #       of the NESTING DEPTH of the data (2, fixed by the settings schema), NOT of the NUMBER OF
    #       FIELD READS (unbounded, and it grows every time someone adds a conjunct). Guard-per-read
    #       is complete-the-known-set — the exact discriminator that failed twice before on this
    #       same surface. Do NOT reintroduce per-site guards.
    #   WHY LOCAL, NOT A SHARED PRIMITIVE (P23 placement evidence; rule-of-three UNMET):
    #       `canon_obj`/`canon_arr` have exactly ONE functional consumer — THIS file
    #       (`claude-mem-path.sh` names them in prose comments only, with no call). The
    #       unguarded-element idiom exists NOWHERE ELSE under `plugin/`. The nearest relative,
    #       `plugin/skills/next-wave/scripts/next-wave.sh`, FILTERS non-conforming elements
    #       (`select(type == "string")`) where this file must PRESERVE them — a DIFFERENT kernel,
    #       so P9 says do not fold them. A shared primitive would ship with one consumer.
    #       `canon_elem` is nonetheless named into the `canon_*` family deliberately: it is the
    #       element-position member of the SAME law, and renaming it out of that family would weaken
    #       the one-law claim the header makes. See ADR-0028 (element-access amendment).
    # An existing unrelated SubagentStart array is PRESERVED and the caveman entry APPENDED to it.
    # An entry whose `.type` != "command" is an INVALID hook: neither migrated nor counted as
    # present, left in place, canonical entry appended beside it. A USER-AUTHORED shell wrapper
    # around this script is likewise left BYTE-UNTOUCHED and no longer suppresses the append — the
    # accepted DELIBERATE DROP, with its failure-direction rationale, in the header.
    # PRESERVE-EXISTING over dedupe: a consumer who had wired BOTH authored shell commands keeps two
    # entries (both canonical after (a)) — this merge never removes an entry the user authored.
    # Re-merge of the canonical entry stays byte-stable and idempotent.
    | (if $caveman == "yes"
       then .hooks = (canon_obj(.hooks)
              | (canon_arr(.SubagentStart)
                 | map(if (canon_elem | .hooks | type) == "array"
                       then .hooks = [ .hooks[]
                              | if (canon_elem
                                    | .type == "command"
                                    and (has("args") | not)
                                    and (.command | type) == "string"
                                    and (.command as $c
                                         | ($authored_shell_cmds | index($c)) != null))
                                then (.command = $hook_cmd | .args = [])
                                else . end ]
                       else . end)) as $migrated_subagent
              | if ($migrated_subagent
                     | any(canon_elem
                          | canon_arr(.hooks)
                          | any(canon_elem
                                | .type == "command"
                                and .args == []
                                and .command == $hook_cmd)))
                then .SubagentStart = $migrated_subagent
                else .SubagentStart = ($migrated_subagent + [ { hooks: [ $hook_entry ] } ]) end)
       else . end)
    # permissions.allow union (seed_allowlist = yes): preserve sibling permissions keys.
    | (if $seed_allow == "yes"
       then .permissions = (($perm) | .allow = $merged_allow)
       else . end)
    | . as $merged

    # ── hooks.SubagentStart report token, DERIVED FROM THE MUTATION ──────────────
    # Not a classification predicate: the token is read off what the build actually did. Under
    # caveman == "yes" the build always leaves `.hooks` an object and `.SubagentStart` an array, so
    # this deep-equality against the canon-normalized PRE-STATE is total. Equal ⇒ the build was a
    # no-op ⇒ "already present". Different ⇒ the build appended the canonical entry or migrated an
    # authored shell-form entry in place ⇒ "added" (one token for both, per the OUTPUT CONTRACT).
    # Because no independent predicate exists, the report CANNOT disagree with the written settings.
    | (if $caveman != "yes" then "resolved no"
       elif ($merged.hooks.SubagentStart == $pre_subagent) then "already present"
       else "added" end) as $c_hook

    # ── emit the OUTPUT CONTRACT object ──────────────────────────────────────────
    | {
        status: (if $agent_class == "conflict" then "conflict" else "ok" end),
        settings: $merged,
        agent_conflict: $agent_conflict,
        keys: {
          "enabledPlugins.hivemind@brenpike": $c_hive,
          "agent": $agent_class,
          "enabledPlugins.caveman@caveman": $c_cave,
          "enabledPlugins.claude-mem@thedotmack": $c_mem,
          "enabledPlugins.codex@openai-codex": $c_codex,
          "pluginConfigs.caveman@caveman": $c_pcfg,
          "hooks.SubagentStart": $c_hook
        },
        permissions_allow: $allow_report
      }'
}
