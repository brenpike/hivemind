#!/usr/bin/env bash
#
# brood-status-project — read-side child-ledger projection engine for hivemind:brood-status
#The read-side analog of spawn-brood.sh's write-side injection closure
# (ADR-0017): spawn-brood WRITES the manifest + provisions child worktrees out-of-band; this
# script READS the manifest + each child run-ledger out-of-band and emits a machine-parseable
# per-strain projection line. The skill body (navigator) calls this once; this script OWNS the
# deterministic read + validation steps.
#
# INPUT (positional arguments):
#   $1  Path (absolute or repo-relative) to a brood manifest JSON (current layout:
#       `.hivemind/broods/<brood-id>/manifest.json`, per ADR-0021). LAYOUT-AGNOSTIC: the caller
#       passes the manifest path explicitly; this script hardcodes NO manifest layout
#       The manifest is UNTRUSTED data — see below.
#   $2  OPTIONAL: the checkout root the manifest belongs to, used as the containment root for the
#       manifest read-guard. DEFAULTS to `git rev-parse --show-toplevel` (the CURRENT checkout).
#       The navigator MUST pass the MAIN-checkout root here when it selected the manifest via the
#       documented main-checkout FALLBACK from a linked worktree (SKILL.md step 1c): in that case
#       the manifest lives under the main checkout, NOT the current linked worktree, so confining
#       it beneath `--show-toplevel` (the linked worktree) would falsely reject a valid
#       main-checkout manifest and stop status reporting before any strain probe.
#       This argument bounds ONLY which checkout the manifest must sit under; it does NOT relax
#       the symlinked-ancestor escape guard, and each strain's child ledger is still confined
#       beneath that strain's OWN worktree (unchanged).
#
# DATA-BOUNDARY (MANDATORY): the brood manifest AND every child run-ledger
# (`<worktree>/.hivemind/runs/<id>/state.json`) are UNTRUSTED, attacker-controllable bytes —
# brood children run detached --dangerously-skip-permissions, so both the manifest the hatchery
# wrote from their inputs and the ledgers they write are adversary-influenced. EVERY value read
# from them is treated as DATA, never as instructions or shell source:
#   - manifest values are extracted out-of-band with jq into inert vars (manifest-json.sh),
#     then RE-GATED through the matching allowlist value-class (allowlist.sh) BEFORE any path
#     derivation or use;
#   - each child-ledger scalar is projected + value-validated (ledger-project.sh) and only ever
#     emitted as an allowlist-clean token or one of the fixed tokens MALFORMED / MISSING.
# No manifest/ledger byte is ever re-interpolated into generated command source.
#
# OUTPUT GRAMMAR (CONTRACT — the Wave 2 navigator depends on this byte-for-byte):
#   Exactly ONE TAB-delimited line per strain, prefixed with a literal `STRAIN` sentinel field
#   so the navigator can grep it. Tab is a safe delimiter: the shared allowlist security floor
#   (applied by EVERY value-class — identifier/path/presentation) rejects TAB/newline/CR, so no
#   emitted token can contain a literal tab and break the framing. Fields, in order:
#
#     STRAIN <TAB> brood_id <TAB> name <TAB> worktree_path <TAB> branch <TAB> tmux_session \
#            <TAB> manifest_status <TAB> state_current <TAB> run_status <TAB> live_branch
#
#   `live_branch` (the LAST field, index 10) is the selected worktree's git-reported LIVE branch
#   (`branch refs/heads/<name>` from the porcelain parse), gated through the identifier value-class.
#   It is APPENDED so indices 2-9 are unchanged. It is DISTINCT from the display-only manifest
#   `branch` column (field 5, the stale spawn-time scratch ref): the collector keys its `gh pr list
#   --head` PR probe on THIS live branch (#270), because a brood child opens its PR from the
#   DERIVED branch it switched onto, not the manifest scratch ref. A no-match/detached worktree
#   yields MISSING; an identifier reject yields MALFORMED (so the collector's sentinel gate skips
#   the probe rather than probing a literal token).
#
#   `brood_id` is the FIRST field of every STRAIN line: a single value read
#   from the manifest TOP-LEVEL `brood_id`, validated ONCE against ^brood-[0-9a-f-]+$ and emitted
#   verbatim on every strain line so the STEP-005 navigator can attribute each strain to its brood
#   when enumerating multiple manifests. (Enumeration across broods is the navigator's concern;
#   this script remains a SINGLE-manifest projector and does NOT glob.)
#
#   Each remaining value is either an allowlist-clean token OR one of the fixed tokens
#   MALFORMED / MISSING / NO_LEDGER_POINTER. A raw, un-validated scalar is NEVER emitted.
#   `state_current` carries a THIRD fixed token NO_LEDGER_POINTER, emitted ONLY at the
#   legacy/no-run-block branch below: it means the manifest carries no ledger pointer (no
#   `run.suggested_id`), so started-evidence is STRUCTURALLY unavailable and the downstream
#   started-evidence gate does NOT apply (the strain falls back to its observable status).
#   This is DISTINCT from MISSING (a ledger pointer exists but the child has not yet written
#   started-evidence) and from MALFORMED (a present-but-rejected ledger). Example (tabs shown as
#   <TAB>):
#     STRAIN<TAB>brood-1a2b<TAB>auth<TAB>/abs/wt/auth<TAB>strain/brood-1a2b/auth<TAB>brood-1a2b-auth<TAB>spawned<TAB>implement_step<TAB>running<TAB>bugfix/auth-fix-9f3a
#
#   The full field ORDER is: brood_id, name, worktree_path, branch, tmux_session,
#   manifest_status, state_current, run_status, live_branch.
#
#   INTEGRITY SENTINEL (distinct from any STRAIN line): when the manifest is PRESENT but
#   UNREADABLE — either UNPARSEABLE (torn / truncated / invalid JSON) OR VALID-JSON-BUT-WRONG-SHAPE
#   (`.strains` missing / null / non-array, or any non-object element) — the script emits exactly
#   ONE line
#     MANIFEST_UNREADABLE <TAB> <manifest_path>
#   to stdout and exits nonzero (see EXIT CONTRACT). The wrong-shape class joins the
#   syntactically-invalid class via a SINGLE shape-validating read (one open, one verdict). This
#   is DISTINCT from "manifest absent" (a pre-flight blocker on stderr) and from "valid empty
#   brood" (`{"strains":[]}` → exit 0, zero STRAIN lines, no sentinel). A present-but-unreadable
#   manifest must NEVER be silently projected as zero strains: corruption (or a wrong-shape
#   manifest) is otherwise indistinguishable from an empty brood and would hide live children from
#   the monitoring dashboard. (A strain object that is well-formed but lacks `name` is NOT a
#   structural failure — it projects with per-strain MALFORMED/MISSING tokens.)
#
# EXIT CONTRACT:
#   0  projected all strains (including zero strains for a VALID empty manifest). PER-STRAIN
#      MALFORMED / MISSING is NOT a failure — a strain with a bad field or an unreadable ledger
#      still emits its line (with token fields) and the script continues to the next strain.
#   1  pre-flight blocker ONLY: missing arg, jq absent, manifest path escapes the checkout
#      (symlinked ancestor). Reported via blocker() on stderr. No per-strain condition reaches
#      exit 1.
#   2  manifest PRESENT but UNREADABLE (unparseable OR valid-JSON-but-wrong-shape): emits the
#      MANIFEST_UNREADABLE sentinel line to stdout (above) and exits 2. A distinct nonzero code so
#      the navigator can tell a corruption/wrong-shape integrity-failure (live children may exist
#      but cannot be enumerated) apart from the absent-manifest stderr blocker.
#
# set -u: every value is read explicitly; an unset variable is a programming error here. We do
# NOT use `set -e`: per-strain field/ledger problems are caught and rendered as tokens, never
# allowed to abort the whole read. There is no EXIT trap.
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: per-item failures route
# through blocker() with explicit exit codes, and unguarded jq/grep value-tests legitimately
# return non-zero in normal flow (rendering MALFORMED/MISSING tokens) — `set -e` would abort
# the read mid-projection.

set -u

# blocker: emit a verbose pre-flight blocker to stderr in the canonical form and exit 1.
# Mirrors spawn-brood.sh's blocker() helper.
blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# ── ENCODE-AT-OUTPUT boundary (Markdown-cell safety) ──────────────────────────────
# encode_cell <value> -> writes a Markdown-table-cell-safe rendering of <value> to stdout.
#
# This is the ENCODE-AT-OUTPUT half of the floor-at-input / encode-at-output model documented in
# allowlist.sh (see its header: "MARKDOWN SAFETY LIVES AT THE RENDER BOUNDARY, NOT HERE"). The
# `path` value-class is FLOOR-ONLY: it deliberately admits any
# byte that survives the shared floor as inert quoted data — INCLUDING the Markdown table-cell
# delimiter `|`. The floor rejects framing bytes (TAB/newline/CR) and command-substitution, but a
# literal `|` is valid path/display data. The STEP-005 navigator lands `worktree_path` (and other
# display columns) inside Markdown TABLE cells, where an un-encoded `|` would inject column
# structure. That defense MUST be deterministic, so it lives HERE at the emit boundary — NOT in the
# agent-driven SKILL.md. DO NOT "fix" a `|` leak by re-adding a charset carve-out to the `path`
# value-class: charset whack-a-mole at the input floor is the wrong layer — the floor
# stays permissive, this encoder owns cell safety.
#
# Transformation, applied UNIFORMLY to every display field (not per-class carve-outs):
#   1. Strip C0 control bytes (0x00–0x1F) and DEL (0x7F) that could survive into a cell. The floor
#      already rejects these on validated values, so this is belt-and-suspenders for the fixed
#      tokens and any future value class — uniform and harmless on already-clean tokens.
#   2. Escape `|` (0x7C) -> `\|` (the Markdown cell escape), so an inert quoted `|` cannot forge a
#      table column.
# The TAB field SEPARATOR is NOT touched here: this operates WITHIN a single field value only; the
# caller still joins fields with literal TABs, preserving the 10-field TAB-delimited STRAIN grammar.
encode_cell() {
  # `tr -d` drops C0 + DEL; `sed` escapes any remaining `|`. Order: strip controls first, then
  # escape `|`, so a stripped control byte can never split the `|` escape. Operates on stdin via a
  # here-string to avoid re-parsing the value as shell.
  printf '%s' "$1" | tr -d '\000-\037\177' | sed 's/|/\\|/g'
}

# ── Script self-location + shared libs (sourced once) ───────────────────────────
# Self-locate from THIS script (layout plugin/skills/brood-status/scripts/ => 3 dirs up is the
# plugin root). cd && pwd -P is portable (no realpath/readlink -f). NO ${CLAUDE_PLUGIN_ROOT}
# inside an engine script — the path is derived from BASH_SOURCE.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
plugin_root="$(cd "$script_dir/../../.." && pwd -P)"
. "$plugin_root/skills/_shared/containment.sh"
. "$plugin_root/skills/_shared/allowlist.sh"
. "$plugin_root/skills/_shared/manifest-json.sh"
. "$plugin_root/skills/_shared/ledger-project.sh"

# ── Dependency check ────────────────────────────────────────────────────────────
# jq is required (the child ledgers are JSON). tmux/claude/gh are NOT required — this read
# path runs in CI with only jq.
command -v jq >/dev/null 2>&1 \
  || blocker "jq is required to project child run-ledgers but is not installed"

# ── Manifest argument validation ────────────────────────────────────────────────
MANIFEST="${1:-}"
[ -n "$MANIFEST" ] \
  || blocker "missing required argument: path to brood manifest JSON (\$1)"
# Reject a SYMLINKED manifest leaf BEFORE the [ -f ] regular-file test (which FOLLOWS
# symlinks and would pass a symlink-to-regular-file). hivemind_assert_inputs_contained below
# canonicalizes only the manifest's dirname and re-appends the basename textually, so a
# symlinked manifest LEAF pointing at an external file would otherwise resolve outside and be
# read as an attacker-controlled JSON manifest. [ -L ] fires for a symlink leaf even when
# its target is missing; checking it first closes the leaf-symlink escape the dirname-only
# canonicalization leaves open. A symlinked ANCESTOR is still caught by the containment guard.
[ -L "$MANIFEST" ] \
  && blocker "refusing to read the manifest: $MANIFEST is a symlink leaf"
[ -f "$MANIFEST" ] \
  || blocker "brood manifest $MANIFEST does not exist or is not a regular file"

# Determine the containment root the manifest must sit beneath. DEFAULT: the current checkout
# (`git rev-parse --show-toplevel`). OVERRIDE: an explicit $2 supplied by the navigator when it
# selected the manifest via the main-checkout fallback from a linked worktree (see header
# The override must name an EXISTING DIRECTORY; an unreadable or non-directory override
# is a pre-flight blocker (we never silently fall back, which could hide a wrong root).
CHECKOUT_ROOT="${2:-}"
if [ -n "$CHECKOUT_ROOT" ]; then
  [ -d "$CHECKOUT_ROOT" ] \
    || blocker "supplied checkout root $CHECKOUT_ROOT does not exist or is not a directory"
else
  CHECKOUT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

# Defense-in-depth READ-guard: refuse to read a manifest whose canonical path escapes the
# selected checkout root (e.g. via a symlinked ancestor). The helper never exits; map non-zero
# to blocker. With a fallback-supplied root this confines the manifest beneath the MAIN checkout
# (where the fallback manifest actually lives) instead of the current linked worktree.
hivemind_assert_inputs_contained "$CHECKOUT_ROOT" "$MANIFEST" >/dev/null \
  || blocker "refusing to read the manifest: $MANIFEST resolves outside the checkout root $CHECKOUT_ROOT (symlinked ancestor)"

# ── Single-snapshot read + shape validation (one open, one verdict) ───────────────
# The manifest passed every pre-flight (present, regular file, not a symlink leaf, contained).
# Open it EXACTLY ONCE into an in-memory snapshot; every projection below runs against THIS
# snapshot via jq stdin, never re-opening the file. This closes BOTH read-side issues at once:
#   1. SNAPSHOT SKEW — probe and per-field projections previously re-opened the manifest at
#      different instants, so a concurrent write mid-read could yield inconsistent reads. One
#      open means one consistent view.
#   2. SCHEMA GAP — the old `jq empty` probe was SYNTAX-only: a valid-JSON-but-wrong-shape
#      manifest ({}, {"strains":null}, {"strains":"x"}, {"strains":[1]}) passed it, then the
#      per-field projection yielded zero strains and was reported as a legitimate EMPTY brood,
#      hiding live children. The shape validation here requires `.strains` to EXIST as an ARRAY
#      with every element an OBJECT, folding the wrong-shape class into the UNREADABLE class.
# On shape failure (invalid JSON OR wrong shape) emit one MANIFEST_UNREADABLE sentinel to stdout
# and exit 2 (integrity failure). A VALID empty manifest (`{"strains":[]}`) PASSES shape (all()
# over an empty array is true) and falls through to the loop, exiting 0 with no STRAIN lines
# (legit empty brood). An element that IS an object but lacks `name` passes shape validation and
# projects with per-strain MALFORMED/MISSING tokens — per-strain degradation is the existing
# contract, distinct from a whole-manifest structural failure. This is the READ-side response
# only; the WRITE-side liveness guard in spawn-brood.sh deliberately keeps its
# fail-open-on-malformed behavior (a corrupt manifest must not wedge spawning).
# The manifest is UNTRUSTED bytes; held only in a shell var passed to jq stdin, never eval'd.
#
# FILE-LEVEL NUL REJECTION: bash `$(...)` SILENTLY STRIPS NUL bytes, so a
# manifest whose on-disk bytes are e.g. `{"strains":<NUL>[]}` would, after the `$(...)` read below,
# become the valid-looking `{"strains":[]}` — it would pass shape validation and project as an empty
# brood, emitting no MANIFEST_UNREADABLE and exiting 0 (live children hidden). JSON never legitimately
# contains a literal NUL, so we reject a NUL-bearing manifest at the FILE level (bytes still intact)
# BEFORE the `$(...)` read can erase it: MANIFEST_UNREADABLE + exit 2, same integrity verdict as a
# torn/wrong-shape manifest. (A control byte that arrives via a JSON ` ` ESCAPE — not a literal NUL
# in the file — is a separate vector handled INSIDE jq during per-field projection; this file-level
# check only catches a literal NUL the `$(...)` capture would silently drop.)
if hivemind_path_has_nul "$MANIFEST"; then
  printf 'MANIFEST_UNREADABLE\t%s\n' "$MANIFEST"
  exit 2
fi
manifest_content="$(cat -- "$MANIFEST")"
if ! hivemind_manifest_validate_shape "$manifest_content"; then
  printf 'MANIFEST_UNREADABLE\t%s\n' "$MANIFEST"
  exit 2
fi

# Canonical containment anchor for the per-strain GROUND-TRUTH worktree-containment chain below.
# (locked OQ3, PATH-keyed for #270): the per-strain ledger anchor is the REAL worktree git itself
# reports — selected by EXACT-MATCH of the manifest's UNTRUSTED `worktree_path` against git's
# trusted worktree-path set (the manifest path is ONLY a selector string, never a path anchor).
# Path-keying is STABLE across a child branch switch (a brood child creates its compliant working
# branch off the spawn-time scratch ref; the worktree PATH does not move), which is the whole point
# — branch-keying broke the moment the child switched. The full containment chain is unchanged:
# CHECKOUT_ROOT ⊇ git-worktree ⊇ ledger — the git-derived worktree must still canonically sit
# beneath this checkout (git may report linked/sibling worktrees deliberately OUTSIDE the
# checkout — those are fail-closed), and the ledger leaf must sit beneath that worktree. The git
# path stays the SOLE confinement anchor; no manifest value reaches a path derivation un-anchored.
# Canonicalize CHECKOUT_ROOT once here.
canon_checkout="$(hivemind_canon_root "$CHECKOUT_ROOT")"
[ -n "$canon_checkout" ] \
  || blocker "failed to canonicalize checkout root $CHECKOUT_ROOT for worktree containment"

# ── Top-level brood_id (single read, validated once) ──────────────────────────────
# The brood_id is the FIRST field of every STRAIN line. It is read ONCE from
# the manifest TOP-LEVEL `brood_id` and validated against ^brood-[0-9a-f-]+$ (the exact shape
# spawn-brood.sh generates: brood-<uuidv4>). The manifest is UNTRUSTED, so a tampered/absent
# brood_id renders the fixed token MALFORMED (never a raw byte) — it is still emitted on every
# strain line so the navigator can tell an unattributable brood apart from a valid one. Read via
# jq stdin against the single snapshot, with the SAME in-jq C0-control rejection used elsewhere
# (bash $(...) strips NUL; a \u00NN control escape must be rejected while bytes are intact).
brood_id_raw="$(printf '%s' "$manifest_content" | jq -r '(.brood_id // empty) | select((tostring | test("[[:cntrl:]]")) | not)' 2>/dev/null)"
brood_id_out="MALFORMED"
case "$brood_id_raw" in
  brood-*)
    brood_id_body="${brood_id_raw#brood-}"   # the id body after the literal `brood-` prefix
    case "$brood_id_body" in
      '')                : ;;          # prefix only, empty id body → MALFORMED
      *[!a-f0-9-]*)      : ;;          # any byte outside [0-9a-f-] in the body → MALFORMED
      *)                 brood_id_out="$brood_id_raw" ;;
    esac
    ;;
esac

# ── Ground-truth worktree discovery (locked OQ3 anchor, PATH-keyed) ───────────────
# Parse `git worktree list --porcelain` ONCE into a SET of git-reported worktree ABSOLUTE PATHS.
# Each porcelain record is a blank-line-separated block whose FIRST line is ALWAYS
# `worktree <abs-path>`; that path — present on EVERY record — is the STABLE key. The optional
# `branch refs/heads/<name>` line is NO LONGER the key: it is absent for a detached-HEAD worktree
# and changes when a child switches branches, so keying on it broke the lookup the instant a
# brood child created its compliant working branch off the spawn-time scratch ref. The worktree
# PATH does not move when HEAD switches, so it is the stable anchor (#270).
#
# The manifest's per-strain `worktree_path` is UNTRUSTED and is used ONLY as an exact-match
# SELECTOR string against this git-reported set; it NEVER becomes a path itself, so a
# garbage/non-matching/absent worktree_path selects NOTHING (fail-closed → MISSING). git
# guarantees worktree-path uniqueness across the set, so a path key cannot collide — the prior
# duplicate-branch→MALFORMED case is unreachable for a path key and is gone.
#
# Record-class handling:
#   - a `bare` record (carries a `worktree` line AND a `bare` line) is the bare repo and is
#     EXCLUDED from the selectable set — a manifest worktree_path pointing at the bare repo must
#     not match a selectable worktree.
#   - a detached-HEAD worktree (a `worktree` line, no `branch` line) is now INCLUDED: path-keying
#     locates it, fixing the prior branch-keying drop.
#   - every other `worktree` record contributes its path to the set regardless of branch.
#
# git is run against CHECKOUT_ROOT (-C) so we enumerate the worktrees of the checkout the manifest
# belongs to. tmux/claude are not required on this path, but git is — if git is unavailable the
# set is empty and every strain fails closed to MISSING worktree/ledger columns.
#
# Storage without associative arrays (portable to bash 3.2): a newline-delimited set of git
# worktree paths, one per line. A manifest worktree_path is looked up by exact whole-line match.
# Every path in the set comes from git (trusted); the manifest path we match against is gated by
# the path value-class before it is used as a selector, so no untrusted byte drives the match. (A
# worktree path containing a TAB/newline cannot occur in a sane checkout and would at worst fail
# to match — never forge a different worktree. The set is built record-at-a-time so a `bare` line
# can retroactively drop the current record's path before the record terminates.)
# PARALLEL LIVE-BRANCH SET (#270 PR-probe re-anchor): alongside the path set, capture each
# record's git-reported LIVE branch from its `branch refs/heads/<name>` line, stored as a
# newline-delimited `<path>\t<live_branch>` set keyed by the SAME exact git path. The live branch
# is the GROUND-TRUTH branch the worktree HEAD points at NOW — it tracks a child's switch off the
# spawn-time scratch ref onto its derived working branch, so it is the correct `gh pr list --head`
# argument (the manifest `branch` column is the stale scratch ref and is display-only). A
# detached-HEAD record emits no `branch` line → its live branch stays empty (→ MISSING downstream).
# live_branch is TRUSTED ground-truth metadata, NEVER a path and NEVER a confinement input — the
# git PATH remains the SOLE confinement anchor.
worktree_set=""
worktree_branch_set=""
{
  cur_wt=""
  cur_bare=0
  cur_branch=""
  flush_record() {
    # Commit the current record's path to the set UNLESS it is a bare repo. Called at each
    # record terminator (blank line) and once at EOF for a trailing record. The parallel
    # live-branch row is committed in lock-step, keyed by the SAME path.
    if [ -n "$cur_wt" ] && [ "$cur_bare" -eq 0 ]; then
      worktree_set="$worktree_set$cur_wt
"
      worktree_branch_set="$worktree_branch_set$cur_wt	$cur_branch
"
    fi
    cur_wt=""
    cur_bare=0
    cur_branch=""
  }
  while IFS= read -r porcelain_line || [ -n "$porcelain_line" ]; do
    case "$porcelain_line" in
      "worktree "*)
        # A new record begins. (Records are blank-line separated, so a `worktree` line always
        # opens a fresh record; flush any prior in case of a missing trailing blank line.)
        flush_record
        cur_wt="${porcelain_line#worktree }"
        ;;
      "branch refs/heads/"*)
        # The record's LIVE branch (ground truth). Absent for a detached-HEAD record, so
        # cur_branch stays empty there → live branch resolves to MISSING at selection time.
        cur_branch="${porcelain_line#branch refs/heads/}"
        ;;
      "bare")
        # Marks the current record as the bare repo → excluded from the selectable set.
        cur_bare=1
        ;;
      "")
        # Blank line terminates a record: commit its path (unless bare). Detached-HEAD records
        # (no `branch` line) are committed here just like branch-bearing ones — path-keyed.
        flush_record
        ;;
    esac
  done
  flush_record   # trailing record with no terminating blank line
} <<EOF
$(git -C "$CHECKOUT_ROOT" worktree list --porcelain 2>/dev/null)
EOF

# ── Per-strain projection ───────────────────────────────────────────────────────
# For each strain, extract the manifest static fields out-of-band into inert vars, re-gate every
# downstream value through the allowlist, select the strain's GROUND-TRUTH worktree from the
# git-derived path set (keyed by EXACT-MATCH on the strain's untrusted worktree_path — STABLE
# across a child branch switch, #270), confine the ledger path beneath that REAL worktree, and
# project the two ledger scalars. Any per-strain problem renders the affected field(s) as a token
# and CONTINUES — never aborts the whole read.
#
# DELIMITER-INJECTION AVOIDANCE: the loop is driven by INDEX off the strain COUNT, not by
# splitting a newline-delimited name stream. An untrusted strain name containing a newline is
# rejected by the presentation value-class floor — but that rejection happens AFTER extraction,
# so splitting a name stream on newline could forge an extra loop iteration BEFORE validation.
# Index-based extraction (hivemind_manifest_field_at, name read via `.strains[$i].name`) selects
# each strain by position against the in-memory snapshot, so no field value is ever parsed as a
# loop delimiter before it has passed its value class.
strain_count="$(hivemind_manifest_strain_count_snapshot "$manifest_content")"
idx=0
while [ "$idx" -lt "$strain_count" ]; do
  # 1. Extract the strain NAME + static fields + the run.suggested_id out-of-band, all selected by
  #    INDEX against the single in-memory snapshot. EXIT-CODE CONTRACT (F2/F3): every field
  #    below comes from hivemind_manifest_field_at, which signals presence-vs-rejection OUT-OF-BAND
  #    via exit code: 0 = present+valid (value on stdout), 1 = ABSENT -> MISSING, 2 = present-but-
  #    INVALID (non-string scalar / C0-control byte / multi-document) -> MALFORMED. We capture each
  #    field's value AND its exit code, then branch on the code below; a rejected (exit 2) value is
  #    NEVER collapsed into MISSING.
  # The name is resolved with the SAME in-jq C0-control rejection: bash $(...)
  # strips NUL, so a JSON \u00NN control escape that jq -r would decode to a real control byte must
  # be rejected INSIDE jq (bytes intact), else the post-cmd-subst presentation gate would validate a
  # control-stripped name. A control-bearing name resolves to empty here -> name_out MALFORMED.
  # [[:cntrl:]] matches the DECODED codepoints (NUL..US, DEL); a [\u0000-\u001f] range does NOT work
  # in jq (its JSON parser turns \u into a literal backslash+u, matching printable text instead).
  strain_name="$(printf '%s' "$manifest_content" | jq -r -s --argjson i "$idx" '(.[0].strains[$i].name // empty) | select((tostring | test("[[:cntrl:]]")) | not)' 2>/dev/null)"

  worktree_path="$(hivemind_manifest_field_at "$manifest_content" "$idx" "worktree_path")"; wt_rc=$?
  branch="$(hivemind_manifest_field_at "$manifest_content" "$idx" "branch")"; branch_rc=$?
  tmux_session="$(hivemind_manifest_field_at "$manifest_content" "$idx" "tmux_session")"; tmux_rc=$?
  manifest_status="$(hivemind_manifest_field_at "$manifest_content" "$idx" "status")"; status_rc=$?
  suggested_id="$(hivemind_manifest_field_at "$manifest_content" "$idx" "run.suggested_id")"; sid_rc=$?

  # 2. Re-gate every value via the allowlist value-class matching its field. The exit-code from
  #    hivemind_manifest_field_at (F2/F3) ALREADY distinguishes ABSENT (rc 1 -> MISSING) from
  #    present-but-INVALID (rc 2 -> MALFORMED) for the string fields; we honor that code FIRST and
  #    never collapse a rejected (rc 2) value into MISSING. A returned value (rc 0) still passes its
  #    value-class floor before it is emitted.
  #
  #    The strain NAME is DISPLAY-ONLY — emitted in the output field; selection is by INDEX, so it
  #    never reaches a shell probe token. spawn-brood derives names containing SPACES, so a valid
  #    `api worker` strain must not be rendered MALFORMED (which would make the navigator lose its
  #    status — Gate the name with the broadest PRESENTATION class.
  name_out="MALFORMED"
  hivemind_assert_presentation "$strain_name" && name_out="$strain_name"

  # worktree_path is the WORKTREE LOOKUP SELECTOR (locked OQ3, re-keyed for #270): it keys the
  # strain's REAL git-reported worktree by EXACT-MATCH against the trusted git path set built above.
  # It is NEVER a path itself — it is ONLY ever compared as a string against git's set, so a
  # tampered/non-matching value selects NOTHING and fails closed (it can never redirect the bounded
  # ledger reader). Because git-set MEMBERSHIP is the validation (a value absent from git's trusted
  # set selects nothing), the gate is the PATH-SELECTOR value-class (hivemind_assert_path_selector):
  # it rejects empty, leading '-', command-sub ($/backtick), and framing bytes (TAB/LF/CR) — the
  # bytes that could forge the TAB-delimited output grammar or expand in a command word — but it
  # PERMITS a `..` directory-NAME substring, since the selector is never traversed and a legitimate
  # worktree under a `..`-bearing dir name (e.g. /tmp/hm..repo/wt) must match its real git entry
  # rather than false-reject to MALFORMED → false MISSING. This is NARROWER than the path class ONLY
  # in dropping the `..` reject; it does NOT widen confinement — the matched GIT path (never this
  # manifest value) remains the sole anchor. rc 1 -> MISSING (absent), rc 2 -> MALFORMED (rejected),
  # rc 0 -> the selector-clean value (else MALFORMED). Only a fully-clean wt_out (not a token) drives
  # the lookup below.
  if [ "$wt_rc" -eq 1 ]; then
    wt_out="MISSING"
  elif [ "$wt_rc" -eq 2 ]; then
    wt_out="MALFORMED"
  else
    wt_out="MALFORMED"
    hivemind_assert_path_selector "$worktree_path" && wt_out="$worktree_path"
  fi

  # branch is now DISPLAY-ONLY (re-keyed for #270): it is the display `branch` column, NO LONGER
  # the worktree selector. The worktree PATH is stable across a child branch switch; the branch is
  # not (the child creates its compliant working branch off the spawn-time scratch ref), so it
  # cannot key the lookup. Still read via the same safe exit-code contract and gated by the strict
  # IDENTIFIER class for safe DISPLAY only. rc 1 -> MISSING, rc 2 -> MALFORMED, rc 0 ->
  # identifier-clean value (else MALFORMED).
  if [ "$branch_rc" -eq 1 ]; then
    branch_out="MISSING"
  elif [ "$branch_rc" -eq 2 ]; then
    branch_out="MALFORMED"
  else
    branch_out="MALFORMED"
    hivemind_assert_identifier "$branch" && branch_out="$branch"
  fi

  if [ "$tmux_rc" -eq 1 ]; then
    tmux_out="MISSING"
  elif [ "$tmux_rc" -eq 2 ]; then
    tmux_out="MALFORMED"
  else
    tmux_out="MALFORMED"
    hivemind_assert_identifier "$tmux_session" && tmux_out="$tmux_session"
  fi

  if [ "$status_rc" -eq 1 ]; then
    status_out="MISSING"
  elif [ "$status_rc" -eq 2 ]; then
    status_out="MALFORMED"
  else
    status_out="MALFORMED"
    hivemind_assert_identifier "$manifest_status" && status_out="$manifest_status"
  fi

  # ── GROUND-TRUTH WORKTREE for this strain (locked OQ3 anchor, PATH-keyed) ─────────
  # Select the strain's REAL worktree from the git-derived path SET by EXACT-MATCH on the
  # path-class-clean wt_out. The manifest worktree_path is ONLY a selector string — a
  # garbage/non-matching/absent path matches no set entry and fails closed (worktree/ledger
  # columns become MISSING/unavailable). gt_worktree holds the matched real path (identical to
  # wt_out on a hit, since both are the same git-reported path) or empty on a miss.
  #
  # git guarantees worktree-path uniqueness, so a path key cannot duplicate; the prior
  # duplicate-key→MALFORMED branch-collision case is unreachable here and has been removed.
  gt_worktree=""
  if [ "$wt_out" != "MALFORMED" ] && [ "$wt_out" != "MISSING" ]; then
    while IFS= read -r set_path; do
      [ "$set_path" = "$wt_out" ] && { gt_worktree="$set_path"; break; }
    done <<EOF
$worktree_set
EOF
  fi

  # ── LIVE BRANCH for the selected worktree (#270 PR-probe re-anchor) ──────────────
  # Resolve the matched worktree's git-reported LIVE branch from the parallel `<path>\t<branch>`
  # set, keyed by the SAME exact path match used above. This becomes the collector's `gh --head`
  # probe argument, so it is gated through the SAME strict IDENTIFIER class as the display branch
  # (same trust/charset class). No-match or detached(empty live branch) → MISSING; an identifier
  # reject → MALFORMED. Reusing the MISSING/MALFORMED sentinel vocabulary makes the collector's
  # existing sentinel gate skip the PR probe for a worktree with no resolvable live branch. The
  # live branch is GROUND-TRUTH metadata, NEVER a path and NEVER a confinement input.
  live_branch_out="MISSING"
  if [ -n "$gt_worktree" ]; then
    live_branch_raw=""
    while IFS="	" read -r set_path set_branch; do
      [ "$set_path" = "$gt_worktree" ] && { live_branch_raw="$set_branch"; break; }
    done <<EOF
$worktree_branch_set
EOF
    if [ -n "$live_branch_raw" ]; then
      live_branch_out="MALFORMED"
      hivemind_assert_identifier "$live_branch_raw" && live_branch_out="$live_branch_raw"
    fi
  fi

  # 3. Derive the ledger path under the GROUND-TRUTH worktree:
  #    "<git-worktree>/.hivemind/runs/<suggested_id>/state.json". Only <suggested_id> is
  #    manifest-sourced; gate it as a STRICT single-component identifier (no slash, no space) so it
  #    cannot escape the worktree's runs/ dir. The `.hivemind/runs/.../state.json` segment is a
  #    literal we own. Default both ledger scalars to tokens; only a fully-confined, readable,
  #    CHECKOUT_ROOT-contained git-worktree path gets projected.
  state_out="MISSING"
  run_out="MISSING"

  # Pre-validate suggested_id once via the exit-code contract; reused below.
  sid_clean=0
  case "$sid_rc" in
    0) hivemind_assert_identifier "$suggested_id" && case "$suggested_id" in
         */*) : ;;                       # reject any '/': must be a single component
         *) sid_clean=1 ;;
       esac ;;
  esac

  if [ -z "$gt_worktree" ]; then
    # No live worktree matches this strain's worktree_path selector -> fail-closed: worktree/ledger
    # unavailable. We NEVER fall back to the manifest worktree_path as a path anchor (it is only an
    # exact-match selector into git's trusted set). "Nothing to anchor on" -> MISSING. (git
    # guarantees path uniqueness, so there is no ambiguous-duplicate case to handle here.)
    state_out="MISSING"
    run_out="MISSING"
  elif [ "$sid_rc" -eq 1 ]; then
    # suggested_id absent (legacy manifest / no run block): there is NO ledger pointer to anchor
    # on, so started-evidence is STRUCTURALLY unavailable — never read. Emit the distinct token
    # NO_LEDGER_POINTER (NOT MISSING) so the started-evidence gate downstream does NOT apply and
    # the strain falls back to its observable status (legacy no-pointer fall-through). MISSING is
    # reserved for the modern case where a pointer EXISTS but the child has not yet written
    # started-evidence. run_status has no legacy token of its own: leave it MISSING.
    state_out="NO_LEDGER_POINTER"
    run_out="MISSING"
  elif [ "$sid_rc" -eq 2 ] || [ "$sid_clean" -ne 1 ]; then
    # suggested_id present but rejected, or fails the strict single-component id charset: escape
    # attempt -> MALFORMED, no path derivation.
    state_out="MALFORMED"
    run_out="MALFORMED"
  else
    # Assert the git-derived worktree is canonicalized + CONTAINED under CHECKOUT_ROOT. git may
    # report linked/sibling worktrees deliberately OUTSIDE the checkout; such an out-of-checkout
    # worktree fails closed here (no read). This is the CHECKOUT_ROOT ⊇ git-worktree link of the
    # full containment chain.
    canon_gt_wt="$(cd "$gt_worktree" 2>/dev/null && pwd -P)"
    gt_resident=0
    if [ -n "$canon_gt_wt" ]; then
      case "$canon_gt_wt/" in
        "$canon_checkout/"*) gt_resident=1 ;;
      esac
    fi
    if [ "$gt_resident" -ne 1 ]; then
      # git-worktree escapes (or fails to canonicalize beneath) CHECKOUT_ROOT: fail closed.
      state_out="MALFORMED"
      run_out="MALFORMED"
    else
      # Confined single-snapshot child-ledger read, delegated to the shared primitive
      # hivemind_read_confined_state_current (_shared/ledger-project.sh). It performs the
      # 6-layer hardened confined read — leaf [ -L ] + non-regular reject AND depth-complete
      # ancestor symlink walk under the worktree root, a [ -L ] re-check at the read, FILE-LEVEL
      # NUL rejection, a single `cat` snapshot, the ITEM-4 post-read re-canonicalize + re-assert,
      # and BOTH _content projections from that ONE snapshot — and is byte-equivalent to the
      # inline block it replaced. The relative chain is .hivemind/runs/<suggested_id>/state.json.
      # gt_worktree is the git-derived worktree ALREADY proven resident under CHECKOUT_ROOT by
      # the canon_gt_wt / gt_resident link above (the shared function has no CHECKOUT_ROOT notion,
      # so that link MUST stay inline here and run FIRST).
      #
      # OUTPUT GRAMMAR (exactly two lines): line 1 = state.current result, line 2 = run.status
      # result, each ∈ { MISSING | MALFORMED | <validated value> }. On any guard/read failure both
      # lines carry the SAME terminal token. Parse with a set-u-safe `read` pair from a process
      # substitution so a short/empty read leaves the vars defined rather than tripping `set -u`.
      rel_chain=".hivemind/runs/$suggested_id/state.json"
      state_out=""
      run_out=""
      { IFS= read -r state_out; IFS= read -r run_out; } \
        < <(hivemind_read_confined_state_current "$gt_worktree" "$rel_chain")
    fi
  fi

  # 5. Emit exactly one TAB-delimited STRAIN line. Field order:
  #    brood_id, name, worktree_path, branch, tmux_session, manifest_status, state_current,
  #    run_status, live_branch. brood_id is the single top-level value validated ONCE before the
  #    loop and emitted verbatim on every strain line. live_branch (field 10) is APPENDED LAST so
  #    existing 1-based field indices 2-9 are unchanged (#270 PR-probe re-anchor): it carries the
  #    selected worktree's git-reported LIVE branch (or MISSING/MALFORMED), distinct from the
  #    display-only manifest `branch` column (field 5).
  #
  #    ENCODE-AT-OUTPUT (see encode_cell above): every display column is run through encode_cell
  #    UNIFORMLY before emission — not per-class carve-outs. The strict columns (brood_id,
  #    tmux/status/state/run identifier-class tokens, live_branch) and the fixed tokens (MISSING /
  #    MALFORMED) need no escaping, but applying the encoder to them too keeps the boundary uniform
  #    and self-documenting; encode_cell is a no-op on values that already lack `|` and controls.
  #    Only the value-classes that can carry a `|` as inert quoted data (worktree_path / branch —
  #    the FLOOR-ONLY path/identifier inputs) are materially affected. The literal TABs joining the
  #    fields are added by printf AFTER per-field encoding, so the 10-field framing is preserved.
  printf 'STRAIN\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(encode_cell "$brood_id_out")" \
    "$(encode_cell "$name_out")" \
    "$(encode_cell "$wt_out")" \
    "$(encode_cell "$branch_out")" \
    "$(encode_cell "$tmux_out")" \
    "$(encode_cell "$status_out")" \
    "$(encode_cell "$state_out")" \
    "$(encode_cell "$run_out")" \
    "$(encode_cell "$live_branch_out")"

  idx=$((idx + 1))
done

exit 0
