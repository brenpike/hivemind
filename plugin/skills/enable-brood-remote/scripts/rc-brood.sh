#!/usr/bin/env bash
#
# rc-brood — deterministic engine for the hivemind:enable-brood-remote skill.
#
# Fans the Claude Code slash command `/rc <strain-name>` (alias `/remote-control`) out to
# every LIVE strain session of one brood via tmux keystroke injection. Each strain's OWN live
# tmux session receives `/rc <its-own-strain-name>`, so each strain self-registers for remote
# control under its strain name. The user invokes this (through the skill) on an EXPLICIT
# natural-language request to enable RC for a brood — it is never an autonomous coordination step.
#
# ADR LINEAGE:
#   - ADR-0007 (fleet children unaware; coordinator is a read-only status dashboard): preserved.
#     Issuing the keystrokes on the user's EXPLICIT request is human-initiated addressing —
#     equivalent to the user attaching to each pane and typing the slash command themselves. It
#     does NOT make the coordinator an autonomous controller; the boundary holds.
#   - ADR-0027 (agent-invocable remote control via description scoping): the capability ships as a
#     normal agent-invocable skill scoped by its description; Claude Code has no in-band peer-drive
#     API (upstream anthropics/claude-code#34243), so external `tmux send-keys` is the only
#     delivery path — the same keystroke-injection mechanism spawn-brood already uses.
#     AMENDMENT (spawn-time remote control): spawn-brood calls this engine itself at spawn time with
#     `--only <short>...` naming every strain that showed started-evidence and was alive when spawn
#     ended, so remote control is on by default. The user-requested path through the skill (brood-id
#     only, every strain) is unchanged; it stays the way to reach strains that started later or lost
#     the connection.
#
# INPUT (positional arguments):
#   $1  <broodId> — a brood-id of the EXACT shape spawn-brood generates (`brood-<uuidv4>`,
#       asserted ^brood-[0-9a-f-]+$). Validated as a strict safe single path component BEFORE any
#       use (reject empty / leading-dash / path-traversal / separators / command-substitution /
#       framing bytes). Used to locate the per-brood manifest under the checkout root.
#   $2  optional `--only`, followed by ZERO OR MORE strain shorts. Every argument after `--only` is a
#       short, with no further option parsing. Each short MUST match ^[a-z0-9-]+$ and is checked
#       BEFORE the manifest is read; a bad one is a pre-flight blocker (zero keystrokes). With
#       `--only`, a strain whose derived short is not listed gets one `skipped: <short> (not
#       selected)` line and no keystroke; `--only` with no shorts selects nothing and sends nothing
#       (summary reports 0 applied). Without `--only` every strain is a candidate, exactly as before.
#
# MANIFEST:
#   <checkout-root>/.hivemind/broods/<broodId>/manifest.json  (manifest_version 4, JSON). The
#   checkout root is `git rev-parse --show-toplevel` — the SAME anchor spawn-brood writes against,
#   so read side and write side agree by construction. The read is confined as in
#   brood-status-project.sh: a symlinked leaf or ancestor is a pre-flight blocker, and the file is
#   opened once into an in-memory snapshot that every field read uses.
#
# OUTPUT (stdout):
#   Per-strain disposition lines (`applied|skipped|failed: <strain> ...`) and a final summary line
#   with applied/skipped/failed counts.
#
# EXIT CONTRACT:
#   0  the fan-out COMPLETED — even with some strains skipped (dead/missing session, unsanitizable
#      name) or failed (a per-strain tmux error). Zero strains / zero alive sessions also exit 0.
#   1  ONLY a pre-flight blocker: bad brood-id, a bad `--only` short, missing/unreadable/invalid manifest,
#      a manifest whose leaf or an ancestor is a symlink, a manifest
#      that FAILS THE SHAPE PREFLIGHT (`.strains` missing/null/object/non-array, or a strain
#      element that is not an object / carries a non-string name or tmux_session), or a missing
#      dependency. No keystroke is delivered on a pre-flight blocker. A wrong-shaped/corrupt
#      manifest is ALWAYS blocked here — never a silent `0 applied` no-op and never object-iterated.
#
# SAFETY (injection invariant — the test asserts this):
#   The ONLY bytes ever sent into any session are the FIXED literal `/rc <short>`, where <short> is
#   the strain's CANONICAL `short` identity — the SAME [a-z0-9-] token spawn-brood derives to name
#   the session (lowercase, REPLACE-map non-[a-z0-9-] bytes to `-`). It is NOT a separate slug: the
#   `/rc` name is the de-duped, work-identifying token, so its uniqueness is INHERITED from
#   spawn-brood's in-set short-collision check (spawn-brood.sh ~500) — two raw-distinct strains can
#   never collide to the same `/rc` name. Untrusted manifest strings (names, descriptions) are read
#   as DATA via `jq -r` and are NEVER interpolated into shell command SOURCE, into a buffer file, or
#   into `send-keys` unsanitized. The RAW `short` is used byte-for-byte (no `tr -s`/trim) so the
#   uniqueness guarantee holds; `short` is already [a-z0-9-]-only (stricter than a command-arg
#   charset), so the literal payload cannot carry framing or control bytes. A strain name that
#   derives an empty `short` is SKIPPED — no malformed `/rc` is ever sent.
#
# TARGET-TRUST (identity invariant — ground-truth-derived pane-id addressing):
#   The tmux session a strain's `/rc` is delivered to is NOT taken from the untrusted manifest
#   `tmux_session` field. Each strain's EXPECTED session is DERIVED FROM GROUND TRUTH exactly as
#   spawn-brood derives it at spawn time — `<brood_id>-<short>`, where `short` is the strain name
#   piped `tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-'` (replicated verbatim from
#   spawn-brood.sh). The manifest `tmux_session` is then a VALIDATED COHERENCE SIGNAL only: it MUST
#   equal the derived identity by EXACT EQUALITY, and any mismatch (sibling, prefix, glob, foreign,
#   or stale) SKIPS the strain — it never becomes the targeting key.
#
#   DELIVERY IS PANE-ID-ADDRESSED (not session-name-addressed) to close a TOCTOU prefix-match hole.
#   tmux resolves a target-PANE name exact-first-then-PREFIX-fallback, so a bare
#   `send-keys -t "$expected_session"` could, if the exact session died/renamed between the liveness
#   gate and the send, prefix-match a same-brood SIBLING (e.g. brood-<uuid>-api vs
#   brood-<uuid>-api-migrations) and mis-deliver the `/rc` payload or its Enter. To eliminate that:
#     - The liveness guard uses tmux's exact-match `=` prefix (`has-session -t "=$expected_session"`),
#       a target-SESSION modifier that forces an EXACT session-name match (no prefix/fnmatch fallback)
#       on EVERY tmux version, to SKIP a dead session.
#     - Immediately before delivery we resolve the active pane id (`%N`) of the EXACT session in
#       target-SESSION context via `list-panes -s -t "=$expected_session"` (the `=` prefix IS honored
#       in target-SESSION contexts on 3.0a), selecting the row whose window+pane active flags == `11`.
#     - BOTH sends address that resolved `%N` pane-id handle. A pane id has NO prefix fallback and
#       ERRORS (`can't find pane: %N`, rc=1) if the pane disappears — so a raced death between resolve
#       and send fails CLOSED into a `failed:` disposition, never silently mis-delivering to a sibling.
#   `=` is therefore used ONLY in target-SESSION contexts (has-session, list-panes -s) that 3.0a
#   honors, and is NEVER used as a target-PANE spec (on 3.0a `send-keys -t "=<s>"` fails with
#   `can't find pane`). A stale/tampered manifest cannot steer `/rc` into a sibling or wrong live
#   pane: the address is a ground-truth-derived pane id, and the manifest value is merely cross-checked.
#
# CONVENTIONS (mirrors brood-status-collect.sh / spawn-brood.sh): `set -euo pipefail`, an EXIT
# trap ending in a guaranteed-zero `:`, self-location via `cd && pwd -P` (NO realpath/readlink, NO
# ${CLAUDE_PLUGIN_ROOT} inside an engine script).

set -euo pipefail
trap ':' EXIT

# blocker: emit a pre-flight blocker to stderr in the canonical form and exit 1 (no keystroke
# delivered). Mirrors the spawn-brood.sh / brood-status-collect.sh blocker pattern.
blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# ── Self-location + shared containment helper ─────────────────────────────────────
# layout plugin/skills/enable-brood-remote/scripts/ => 3 dirs up is the plugin root. The helper
# supplies hivemind_assert_inputs_contained for the confined manifest read below.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve the plugin root from the script directory; refusing to proceed"
[ -f "$plugin_root/skills/_shared/containment.sh" ] || blocker "required shared library missing: skills/_shared/containment.sh; refusing to proceed"
. "$plugin_root/skills/_shared/containment.sh" || blocker "failed to source skills/_shared/containment.sh (unparseable); refusing to proceed"

# ── Dependency check ──────────────────────────────────────────────────────────────
# tmux delivers the keystrokes; jq reads the manifest as DATA; git resolves the checkout root.
# All three are hard pre-flight deps — a missing one is a blocker, not a degraded run.
for dep in tmux jq git; do
  command -v "$dep" >/dev/null 2>&1 \
    || blocker "$dep is required but is not installed"
done

# ── Argument: brood-id (validate FAIL-CLOSED before any use) ──────────────────────
# Mirrors spawn-brood.sh's brood-id assertions: the value becomes a filesystem path component, so
# it must be a single safe component. Reject empty / leading-dash / traversal / separators /
# framing bytes BEFORE it is ever interpolated into a path.
brood_id="${1:-}"
[ -n "$brood_id" ] || blocker "missing required argument: <broodId>"
case "$brood_id" in
  -*)       blocker "brood-id must not start with '-': $brood_id" ;;
  *..*)     blocker "brood-id must not contain '..': $brood_id" ;;
  */*|*\\*) blocker "brood-id must not contain a path separator: $brood_id" ;;
esac
# Shape gate: exactly the form spawn-brood generates (brood-<uuidv4>, lowercase hex + dashes).
case "$brood_id" in
  brood-[0-9a-f]*) : ;;
  *) blocker "brood-id must match ^brood-[0-9a-f-]+\$: $brood_id" ;;
esac
case "$brood_id" in
  *[!a-z0-9-]*) blocker "brood-id contains a byte outside [a-z0-9-]: $brood_id" ;;
esac

# ── Optional strain selection: `--only <short>...` (validate FAIL-CLOSED before the manifest read) ─
# Every argument after `--only` is a short, with no further option parsing. Each one MUST match
# ^[a-z0-9-]+$ — the same charset the derived `short` is built from — so a bad one is a pre-flight
# blocker before any manifest read or keystroke. `--only` with zero shorts is valid: it selects
# nothing. Without `--only`, `only_mode` stays 0 and every strain is a candidate as before.
only_mode=0
selected_shorts=()
if [ "${2:-}" = "--only" ]; then
  only_mode=1
  for selected_short in "${@:3}"; do
    case "$selected_short" in
      ''|*[!a-z0-9-]*) blocker "--only short must match ^[a-z0-9-]+\$: $selected_short" ;;
    esac
    selected_shorts+=("$selected_short")
  done
fi

# is_short_selected: succeed when $1 is one of the `--only` shorts (exact byte equality).
is_short_selected() {
  local candidate="$1" selected_idx=0
  while [ "$selected_idx" -lt "${#selected_shorts[@]}" ]; do
    [ "${selected_shorts[$selected_idx]}" = "$candidate" ] && return 0
    selected_idx=$((selected_idx + 1))
  done
  return 1
}

# ── Checkout root + manifest path ─────────────────────────────────────────────────
# The SAME anchor spawn-brood.sh writes against (git rev-parse --show-toplevel), so the manifest
# this read locates is exactly the one the spawn wrote.
root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$root" ] && [ -d "$root" ] \
  || blocker "not inside a git checkout (git rev-parse --show-toplevel failed)"

manifest="$root/.hivemind/broods/$brood_id/manifest.json"

# ── Confined single-snapshot manifest read (mirrors brood-status-project.sh) ─────────
# The manifest sits in the coordinator checkout, but a brood child or any local process can
# replace it or an ancestor dir with a symlink, and [ -f ]/[ -r ]/jq all FOLLOW symlinks. So:
#   1. reject a symlinked LEAF first ([ -L ] fires even for a dangling target);
#   2. require a readable regular file;
#   3. hivemind_assert_inputs_contained rejects a symlinked ANCESTOR (dirname canonicalized
#      with cd && pwd -P, prefix-matched under the canonical checkout root);
#   4. open the file EXACTLY ONCE: jq parses the intact bytes (a literal NUL or a second JSON
#      document fails here) and emits one compact object, held in a shell var;
#   5. re-assert 1 and 3 after the read, so a swap during the read fails closed.
# Every later field read runs against $manifest_content on jq stdin and never reopens the
# file. A failure at any step is a pre-flight blocker: zero keystrokes.
[ -L "$manifest" ] \
  && blocker "refusing to read the brood manifest: $manifest is a symlink leaf"
[ -f "$manifest" ] && [ -r "$manifest" ] \
  || blocker "brood manifest not found or unreadable: $manifest"
hivemind_assert_inputs_contained "$root" "$manifest" >/dev/null 2>&1 \
  || blocker "refusing to read the brood manifest: $manifest resolves outside the checkout (symlinked ancestor)"
manifest_content="$(jq -c -s 'if length == 1 then .[0] else error("not exactly one JSON document") end' "$manifest" 2>/dev/null)" \
  || blocker "brood manifest is not valid JSON: $manifest"
{ [ ! -L "$manifest" ] && hivemind_assert_inputs_contained "$root" "$manifest" >/dev/null 2>&1; } \
  || blocker "refusing to use the brood manifest: $manifest changed into a symlink during the read"
# Validate it is a JSON object before any field read — a corrupt manifest is a pre-flight blocker.
jq -e 'type == "object"' <<< "$manifest_content" >/dev/null 2>&1 \
  || blocker "brood manifest is not valid JSON: $manifest"

# ── Manifest brood-id coherence gate (target-trust) ───────────────────────────────
# The manifest's OWN top-level brood_id MUST equal the requested brood-id. A manifest whose
# recorded brood_id disagrees with the directory it was located under is stale or tampered — its
# strain sessions cannot be trusted as THIS brood's targets. Reject as a pre-flight blocker BEFORE
# any session is probed or addressed. A non-string / missing brood_id also fails this gate.
manifest_brood_id="$(jq -r 'if (.brood_id | type) == "string" then .brood_id else "" end' <<< "$manifest_content" 2>/dev/null || true)"
[ "$manifest_brood_id" = "$brood_id" ] \
  || blocker "manifest brood_id does not match requested brood-id (stale/tampered manifest): $manifest"

# ── Holistic manifest-shape PREFLIGHT (fail-closed schema gate, before any fan-out) ─
# CLOSED-BY-CONSTRUCTION: rather than validate each untrusted manifest field piecemeal as a new
# finding arrives, assert the WHOLE manifest shape up front, ONE fail-closed gate, BEFORE projecting
# any entry or probing any session. This makes the entire "wrong-shaped manifest reaches fan-out"
# class unrepresentable past this point — a corrupt/wrong-shaped manifest is ALWAYS a pre-flight
# blocker (exit 1, zero send-keys), never a silent no-op and never an object-iterated mis-run.
#
# What the gate requires (all checked in a SINGLE jq -e pass, so the first violation fails closed):
#   1. the manifest root is a JSON object                       (already guarded above; re-asserted)
#   2. `.strains` is a NON-NULL ARRAY — NOT missing, NOT null, NOT an object, NOT any other type.
#      This is the P1 fix: the former `.strains // []` projected absent/null into an EMPTY brood
#      (silent `0 applied`) and iterated an OBJECT's VALUES (wrong-shaped manifest processed). A
#      non-array `.strains` is now a hard blocker here, so the projection below never sees a shape
#      it cannot handle.
#   3. EVERY strain element is an OBJECT carrying a STRING `name` AND a STRING `tmux_session`.
#      This consolidates the per-field type-strictness that the projection's `reqstr` previously
#      enforced finding-by-finding into the SAME up-front gate. (The projection keeps its own
#      type-strict `reqstr` as defense-in-depth; this gate is now the primary fail-closed boundary.)
# A missing/null `name` or `tmux_session` is NOT rejected here — those remain RUNTIME per-strain
# SKIPS (empty short / no recorded session) below, preserving existing fail-soft behavior. Only
# present-but-NON-STRING fields (and the container-shape violations) are pre-flight blockers.
jq -e '
  (type == "object")
  and ((.strains | type) == "array")
  and (
    .strains
    | all(
        (type == "object")
        and ((.name         | type) | (. == "string" or . == "null"))
        and ((.tmux_session | type) | (. == "string" or . == "null"))
      )
  )
' <<< "$manifest_content" >/dev/null 2>&1 \
  || blocker "brood manifest failed shape preflight (\`.strains\` must be a non-null array of objects, each with string-or-null name + tmux_session): $manifest"

# ── Enumerate strains (DATA reads — never command source) ─────────────────────────
# Read the name + tmux_session of each strain as TAB-separated DATA via a single jq pass. jq
# emits each value as a string; we strip C0 control bytes defensively at the read boundary (a
# control byte cannot survive into a session, and tab/newline would corrupt the field split). The
# values are consumed ONLY as inert "$var" args below; they never enter generated command source.
TAB="$(printf '\t')"

# Project the strain (name, tmux_session) pairs in a SINGLE jq pass and CAPTURE both the output and
# the exit status BEFORE the loop. Running jq inside process substitution would hide a jq error from
# the surrounding `while`, so the fan-out could exit 0 with a "success" summary after silently
# dropping the bad and remaining strains. The projection is TYPE-STRICT: each strain's `name` and
# `tmux_session` MUST be a JSON string (a present-but-non-string field is a corrupt manifest). The
# `error(...)` makes jq exit non-zero on the first malformed field; the captured `|| blocker` then
# converts that into a PRE-FLIGHT BLOCKER (no keystroke delivered) instead of a silent drop. A
# missing/null field defaults to the empty string and is handled by the slug/session skips below.
projection="$(
  jq -r '
    def reqstr($f): if . == null then "" elif (type == "string") then . else error("strain field \($f) is not a string") end;
    # `.strains` is GUARANTEED a non-null array by the shape preflight above (no `// []` fallback
    # needed — a non-array `.strains` is already a pre-flight blocker, never reached here). The
    # per-field `reqstr` type-strictness is retained as defense-in-depth behind that gate.
    (.strains)[]
    | [ (.name         | reqstr("name")         | gsub("[[:cntrl:]]"; "")),
        (.tmux_session | reqstr("tmux_session") | gsub("[[:cntrl:]]"; "")) ]
    | @tsv
  ' <<< "$manifest_content"
)" || blocker "failed to project strains from manifest (corrupt/non-string name or tmux_session): $manifest"

strain_names=()
strain_sessions=()
# Guard the empty projection (zero strains): a herestring of "" still yields one empty line, which
# would otherwise register as a spurious skipped strain. Only iterate when there is real output, so
# the zero-strain run reports "0 strains" exactly as before.
if [ -n "$projection" ]; then
  while IFS="$TAB" read -r s_name s_session; do
    strain_names+=("$s_name")
    strain_sessions+=("$s_session")
  done <<< "$projection"
fi

# ── Fan-out ───────────────────────────────────────────────────────────────────────
# Per strain: derive the canonical `short` identity, guard session liveness, then deliver the FIXED
# `/rc <short>` literal. One dead session or one tmux error NEVER aborts the rest (FAIL-SOFT) — it
# is recorded and the loop continues.
applied=0
skipped=0
failed=0

strain_count="${#strain_names[@]}"
idx=0
while [ "$idx" -lt "$strain_count" ]; do
  name="${strain_names[$idx]}"
  session="${strain_sessions[$idx]}"
  idx=$((idx + 1))

  # Derive the canonical `short` identity from GROUND TRUTH (target-trust + RC name): spawn-brood
  # names every strain session `<brood_id>-<short>`, where `short` is the strain name lowercased then
  # REPLACE-mapped to the [a-z0-9-] charset. Replicate that derivation VERBATIM from spawn-brood.sh
  # (lines ~394 + ~408) so the address — AND the `/rc` payload — is computed from the brood-id + name
  # we already trust, NOT taken from the untrusted manifest `tmux_session` field. spawn-brood DE-DUPES
  # this RAW `short` (in-set short-collision check ~500), so using the RAW value byte-for-byte (no
  # `tr -s`/trim — squeezing could re-collide two raw-distinct shorts) makes the `/rc` name inherit
  # that uniqueness guarantee. If `short` derives empty (name was empty or wholly outside [a-z0-9-])
  # there is no derivable identity to address and no safe `/rc` argument to send — SKIP. Do NOT fall
  # back to a bare `<brood_id>-` prefix target.
  short="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
  if [ -z "$short" ]; then
    printf 'skipped: strain %q (name does not derive a session identity / safe /rc name)\n' "$name"
    skipped=$((skipped + 1))
    continue
  fi
  expected_session="$brood_id-$short"

  # Selection gate: with `--only`, a strain whose derived short is not listed is skipped before any
  # session probe, so it never receives a keystroke.
  if [ "$only_mode" -eq 1 ] && ! is_short_selected "$short"; then
    printf 'skipped: %s (not selected)\n' "$short"
    skipped=$((skipped + 1))
    continue
  fi

  # A strain whose recorded session is empty or sentinel-shaped has no recorded value to cross-check.
  if [ -z "$session" ]; then
    printf 'skipped: %s (no tmux session recorded)\n' "$short"
    skipped=$((skipped + 1))
    continue
  fi

  # Coherence gate (target-trust): the manifest-recorded session is now a VALIDATED SIGNAL, not the
  # targeting key. It MUST equal the ground-truth-derived identity by EXACT EQUALITY. Any mismatch —
  # sibling, prefix, glob, foreign, or stale — SKIPS the strain; we never address the manifest value.
  if [ "$session" != "$expected_session" ]; then
    printf 'skipped: %s (manifest session %s does not match derived identity %s)\n' "$short" "$session" "$expected_session"
    skipped=$((skipped + 1))
    continue
  fi

  # Liveness guard: a dead/missing session is SKIPPED, never failed — it simply is not a delivery
  # target. Address the GROUND-TRUTH identity with tmux's exact-match `=` prefix so tmux accepts ONLY
  # an exact session-name match (no prefix/fnmatch fallback into a sibling pane). `has-session`
  # against an absent session is a normal negative, not an error.
  if ! tmux has-session -t "=$expected_session" 2>/dev/null; then
    printf 'skipped: %s (session not alive: %s)\n' "$short" "$expected_session"
    skipped=$((skipped + 1))
    continue
  fi

  # Resolve the EXACT session's active pane id (`%N`) immediately before delivery — the targeting
  # PRIMITIVE is a pane-id handle, NOT a session name, so there is no prefix-match fallback into a
  # sibling. We list panes in target-SESSION context with the exact-match `=` prefix (HONORED on
  # 3.0a for `list-panes -s`), one row per pane:
  #
  #   list-panes -s -t "=$expected_session" -F '#{session_name}\t#{window_active}#{pane_active}\t#{pane_id}'
  #
  # FIELD ORDER (tab-separated, for the test to mirror): 1=session_name  2=window_active+pane_active
  # (concatenated two-digit flag field, `11` == active window AND active pane)  3=pane_id (`%N`).
  #
  # EXACTLY-ONE-CARDINALITY CONTRACT (ADR-0021: ground-truth ambiguous → fail closed, never silently
  # resolved): CONSUME EVERY row — do NOT enumerate-and-select-first (a break-on-first, even a
  # counter-with-early-break, is select-first in disguise and is REJECTED). Count the rows whose
  # active-flags field == `11` into `active_count`, capturing each one's session_name and pane_id.
  # tmux GUARANTEES exactly ONE active pane per session, so the count is asserted on the ACTIVE(`11`)
  # rows — NOT on total row count (a legit multi-window session has many panes but exactly one
  # active). After the loop, require `active_count == 1`: anything else fails CLOSED (this single
  # check covers BOTH zero `11` rows AND >1 `11` rows uniformly). A count != 1 means tmux's exact
  # invariant was violated for the `=`-scoped session — the `=`-exact scoping was defeated, an
  # anomaly — so we record `failed:` and do NOT send. If the `list-panes` itself errors (raced
  # session death between the liveness gate and here) that is the separate rc!=0 fail-closed branch.
  pane_rows="$(tmux list-panes -s -t "=$expected_session" -F '#{session_name}'"$TAB"'#{window_active}#{pane_active}'"$TAB"'#{pane_id}' 2>&1)" || {
    printf 'failed: %s (could not resolve pane id for session %s: %s)\n' "$short" "$expected_session" "$pane_rows"
    failed=$((failed + 1))
    continue
  }
  resolved_session_name=""
  target_pane=""
  active_count=0
  while IFS="$TAB" read -r r_session r_flags r_pane; do
    if [ "$r_flags" = "11" ]; then
      active_count=$((active_count + 1))
      resolved_session_name="$r_session"
      target_pane="$r_pane"
    fi
  done <<< "$pane_rows"
  if [ "$active_count" -ne 1 ]; then
    printf 'failed: %s (expected exactly one active pane for session %s, found %d: %s)\n' "$short" "$expected_session" "$active_count" "$pane_rows"
    failed=$((failed + 1))
    continue
  fi

  # Ownership assert (explicit belt; impossible-by-construction given the `=`-scoped list-panes): the
  # resolved pane's session name MUST be byte-equal to the ground-truth identity. A mismatch means
  # the `=` scoping was somehow defeated — record `failed:`, do NOT send.
  if [ "$resolved_session_name" != "$expected_session" ]; then
    printf 'failed: %s (resolved session %s does not match derived identity %s)\n' "$short" "$resolved_session_name" "$expected_session"
    failed=$((failed + 1))
    continue
  fi

  # Deliver the FIXED form to the resolved pane id (`%N`). Two separate send-keys events:
  #   1. `-l --` types the literal text `/rc <short>` verbatim (no key-name interpretation; the
  #      leading `/` and the short are sent as characters). For a SHORT fixed one-line command,
  #      literal send-keys is sufficient — no bracketed-paste needed (per the delivery decision).
  #   2. a SEPARATE Enter key event submits the slash command.
  # `short` is a [a-z0-9-] token (the canonical de-duped strain identity), so the literal payload
  # cannot carry framing or control bytes. BOTH sends address `$target_pane` (a `%N` pane-id handle):
  # a pane id has NO prefix-match fallback, so it cannot mis-deliver into a sibling, and it ERRORS
  # (`can't find pane: %N`, rc=1) if the pane disappeared between resolve and send — failing CLOSED.
  # Capture each send-keys' stderr and surface it on the `failed:` disposition line. On SUCCESS
  # send-keys emits nothing, so the captured value is empty and is never printed. Any tmux failure
  # for THIS strain is recorded `failed` and the loop continues — a per-strain error never aborts the
  # fan-out. The `applied:` line keeps printing the user-facing `$expected_session` identity (the
  # pane id is an internal handle and is NOT leaked into output).
  if ! err="$(tmux send-keys -t "$target_pane" -l -- "/rc $short" 2>&1)"; then
    printf 'failed: %s (send-keys literal failed for session %s: %s)\n' "$short" "$expected_session" "$err"
    failed=$((failed + 1))
    continue
  fi
  if ! err="$(tmux send-keys -t "$target_pane" Enter 2>&1)"; then
    printf 'failed: %s (send-keys Enter failed for session %s: %s)\n' "$short" "$expected_session" "$err"
    failed=$((failed + 1))
    continue
  fi
  printf 'applied: %s (/rc %s -> %s)\n' "$short" "$short" "$expected_session"
  applied=$((applied + 1))
done

# ── Summary ────────────────────────────────────────────────────────────────────────
# Exit 0 once the fan-out completed, regardless of per-strain skipped/failed counts. The only
# exit-1 paths are the pre-flight blockers above.
printf 'summary: brood %s — %d applied, %d skipped, %d failed (of %d strains)\n' \
  "$brood_id" "$applied" "$skipped" "$failed" "$strain_count"
exit 0
