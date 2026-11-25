#!/usr/bin/env bash
#
# triage-ops.sh — deterministic MECHANISM substrate for the hivemind
# `triage-backlog` skill (judgment/mechanism split; engineering-principles P5 +
# P11). Path: ${CLAUDE_PLUGIN_ROOT}/skills/triage-backlog/scripts/triage-ops.sh
#
# 1. PURPOSE
# ----------
# This script owns ONLY the lossless, deterministic mechanism of issue triage.
# NO rating / judgment logic lives here — choosing a readiness / type / effort /
# moscow / priority / risk / difficulty value for an issue is holistic LLM work
# (P11) and stays in the SKILL prose. The script is the reproducible hands:
#   - bake + idempotently ensure the fixed label palette (name->color->family),
#   - enumerate open issues with their current labels in one call,
#   - apply a rating as labels with PER-FAMILY MUTUAL EXCLUSION (clean reconcile),
#   - read + add NATIVE GitHub issue dependencies (blocked-by) via GraphQL,
#   - surface a GitHub-rejected dependency cycle as a STRUCTURED warning record
#     instead of crashing,
#   - run the shared readiness check (skills/_shared/readiness-check.sh, sourced at
#     startup) over an overlay of the labels and blocked-by edges a pending apply would write.
# The split mirrors fetch-normalize.sh: a thin live `gh`/network shell wrapping a
# pure, offline-exercisable transform core.
#
# 2. INPUT CONTRACT — per subcommand
# ----------------------------------
#   ensure-labels
#     args:    none
#     online:  create-or-update every palette label (gh label create --force;
#              idempotent + self-healing color). NEVER deletes any label
#              (foreign labels and triage:locked content are untouched).
#     offline: emits the baked palette JSON; performs no gh call.
#
#   list-issues [--limit N] [--response-file <path|->]
#     online:  gh issue list --state open --limit N
#                --json number,title,labels,body,id   (id = GraphQL node id)
#     offline: re-emits the injected --response-file verbatim (identity), no gh.
#     N defaults to 500. PRs are excluded by `gh issue list` default.
#     NO SILENT TRUNCATION: the skill advertises the ENTIRE backlog, but `gh issue
#     list --limit N` caps at N with no overflow signal. So when the produced
#     row-count EQUALS the requested --limit (cap possibly hit) the subcommand
#     FAILS CLOSED with a diagnostic to raise --limit and re-run (no pagination).
#     The cap check runs UNIFORMLY over the produced rows in BOTH offline and live
#     paths so it is offline-drivable (STEP-002).
#     --response-file is a TEST SEAM honored ONLY when TRIAGE_OPS_OFFLINE is set;
#     a live invocation supplying it is REJECTED fail-closed via the shared guard
#     (see §5) BEFORE any gh call.
#
#   apply-labels <issue-number> --targets <json> | --targets-file <path>
#                                [--current-labels-file <path|->]
#     <json> is a family->value object, e.g. {"priority":"high","type":"bug"}.
#     Only the families PRESENT in the object are reconciled; absent families are
#     left untouched. Every "<family>:<value>" MUST be a managed palette label
#     (validated against the palette — an unknown family/value fails CLOSED).
#     online:  derives current labels UNCONDITIONALLY from `gh issue view` (ground
#              truth); if triage:locked is present it emits a skipped-locked record
#              and mutates NOTHING; otherwise applies the computed delta via one
#              `gh issue edit`. --current-labels-file is a TEST SEAM and is honored
#              ONLY when TRIAGE_OPS_OFFLINE is set — supplying it in the live path
#              is REJECTED fail-closed via the shared guard (see §5) BEFORE any gh
#              call (it could spoof label state, incl. omitting triage:locked to
#              bypass the human-only lock).
#     offline: reads current labels from --current-labels-file (a JSON array of
#              label-name strings) and emits the computed delta JSON; no gh.
#
#   deps-read <issue-number> [--response-file <path|->]
#     online:  gh api graphql — repository.issue(number).blockedBy.
#     offline: normalizes the injected --response-file (a raw GraphQL response).
#     --response-file is a TEST SEAM honored ONLY when TRIAGE_OPS_OFFLINE is set;
#     a live invocation supplying it is REJECTED fail-closed via the shared guard
#     (see §5) BEFORE any gh call.
#
#   deps-add --issue-id <NODE_ID> --blocked-by-id <NODE_ID> [--response-file <path|->]
#            [--issue-labels-file <path|->] [--issue-labels-response <path|->]
#     Operates on GraphQL NODE IDs (from list-issues' `id` field), not numbers —
#     no number->id resolution round-trip is needed because the skill already has
#     the ids. ADD-ONLY: never removes an existing dependency.
#     online:  resolves the GROUND-TRUTH labels of the issue being MUTATED
#              (--issue-id) via a node(id:) GraphQL query; routes the RAW response
#              through validate_response_shape (the SHARED kernel — see §4) so a
#              transport error, .errors envelope, null node, non-array label list,
#              or null/wrong-typed label name FAILS CLOSED before assert_unlocked_live
#              and BEFORE the addBlockedBy mutation — never mutate on unverifiable
#              lock state. A locked issue emits a skipped-locked record and mutates
#              NOTHING (exit 0 — same gate apply-labels uses). Only --issue-id is
#              gated; a locked BLOCKER does not block the edge.
#     offline: with --response-file -> surfaces that injected response (exercises
#              the cycle/error/success records); else with --issue-labels-response ->
#              injects the RAW node(id:) labels GraphQL response and drives the
#              FULL live lock-read path (shared kernel shape gate + lock gate) offline
#              (skipped-locked when locked, payload when unlocked, fail-closed on
#              malformed/error body — exactly what the live path does); else with
#              --issue-labels-file -> injects a PRE-PROJECTED label-name JSON array
#              and drives the lock gate only (bypasses the raw-response kernel guard
#              — use --issue-labels-response to test the kernel guard offline); else
#              -> emits the constructed GraphQL variables payload (exercises payload
#              build).
#     --response-file, --issue-labels-file, and --issue-labels-response are TEST
#              SEAMS honored ONLY when TRIAGE_OPS_OFFLINE is set; a live invocation
#              supplying ANY of them is REJECTED fail-closed via the shared guard
#              (see §5) BEFORE any gh call.
#
#   deps-add --issue-id <NODE_ID> --blocked-by-number <n> [--blocked-by-number-response <path|->]
#     --blocked-by-number names the blocker by issue number (^[1-9][0-9]*$) in place of
#     --blocked-by-id; passing both fails with exit 2. A closed blocker resolves like an open one.
#     online:  resolves the blocker's node id with one `gh api graphql` issue(number:) read
#              (owner/repo from gh's {owner}/{repo} placeholders), routed through
#              validate_response_shape BEFORE the lock gate and the mutation; a null issue,
#              `.errors` envelope, malformed body or number mismatch FAILS CLOSED (exit 1).
#     offline: --blocked-by-number-response injects that RAW read and drives the same
#              resolution; the resolved id then feeds the offline flow above.
#     --blocked-by-number-response is a TEST SEAM honored ONLY when TRIAGE_OPS_OFFLINE is set;
#              a live invocation supplying it is REJECTED fail-closed (see §5) BEFORE any gh call.
#
#   readiness <commit> --overlay <json> [--snapshot-file <path|->] [--repo-response-file <path|->]
#     Runs the shared readiness check (skills/_shared/readiness-check.sh) on every issue the
#     overlay names, as if the overlay's labels and blocked-by edges were present.
#     <commit> must be a full lowercase hex commit id (40 or 64 characters, the library's
#              hivemind_readiness_commit_ok); anything else (a branch name, HEAD, a local ref,
#              short or uppercase hex) exits 2 with empty stdout BEFORE any gh or git call.
#     <json> is an object keyed by issue number (^[1-9][0-9]*$); each value is
#              {"targets": {family: value}, "blocked_by": [positive integers]}, both keys
#              optional and no other key allowed. Every target is checked against the palette
#              exactly as apply-labels checks --targets: an unknown family or value, or the
#              `triage` family, exits 2 BEFORE any gh call. No inputs file is involved.
#     online:  owner/repo and the default branch name come from one `gh repo view` read
#              routed through validate_response_shape; each issue is fetched with
#              hivemind_readiness_fetch_snapshot; the overlay is applied (label names become
#              current minus compute_mutex_delta's remove set plus its add set; each blocked_by
#              number not already present becomes a blockedBy node); every issue is evaluated in
#              ONE hivemind_readiness_check_snapshot call.
#     offline: --snapshot-file (an object of issue snapshot nodes keyed by issue number) and
#              --repo-response-file (the RAW gh repo view response) replace the two gh reads;
#              an absent node reaches the library as null and fails snapshot-malformed.
#     Any non-zero gh or library return leaves stdout EMPTY and exits 1, keeping the library's
#     `readiness-check-error: <token>` stderr line. A locked issue is checked like any other;
#     this subcommand never mutates.
#     --snapshot-file and --repo-response-file are TEST SEAMS honored ONLY when
#              TRIAGE_OPS_OFFLINE is set; a live invocation supplying either is REJECTED
#              fail-closed (see §5) BEFORE any gh call.
#
# 3. OUTPUT SCHEMA — JSON on stdout (compact)
# -------------------------------------------
#   ensure-labels (offline) / palette:
#     [ { "name": <str>, "color": <hex6-no-#>, "family": <str>, "managed": bool }, ... ]
#
#   apply-labels delta (offline, and the applied set echoed online):
#     { "issue": <int>, "remove": [<label-name>...], "add": [<label-name>...] }
#   apply-labels online, additionally one of:
#     { "issue": <int>, "status": "applied",       "remove": [...], "add": [...] }
#     { "issue": <int>, "status": "skipped-locked" }   # triage:locked present
#
#   deps-read normalized:
#     { "issue": <int|null>, "id": <node-id|null>,
#       "blocked_by": [ { "number": <int>, "id": <node-id>, "title": <str> }, ... ] }
#
#   deps-add payload (offline, no --response-file):
#     { "issueId": <node-id>, "blockingIssueId": <node-id> }
#   deps-add surfaced response (online, or offline with --response-file):
#     added:   { "status": "added",   "issue": <int>, "blocked_by": <int> }
#     warning: { "status": "warning", "kind": "cycle-rejected"|"error"|"transport-error",
#                "message": <str> }
#
#   readiness: the library's output contract lines, printed verbatim, one per overlay issue in
#   ascending issue order (exit 0 only when every issue was evaluated):
#     { "issue": <int>, "commit": <commit>, "track": "standalone"|"slice",
#       "result": "pass"|"fail", "reasons": [<code>, ...] }
#
# 4. INVARIANTS
# -------------
#   - SINGLE SHARED RESPONSE-SHAPE KERNEL: EVERY live gh/GraphQL read that informs
#     a decision or mutation routes through validate_response_shape before any
#     processing. No per-site hand-parsing of response shape is permitted. A
#     non-clean response — transport error (empty/non-JSON), a non-empty `.errors`
#     envelope, null/missing entity at the expected root path, non-array collection,
#     or a null/wrong-typed field on any element — FAILS CLOSED (nonzero, structured
#     kind record to stderr) before any gate, decision, or mutation. Covered reads:
#     deps-read's blockedBy response (via normalize_deps_read), deps-read's
#     repo-name read (gh repo view — routed RAW through the kernel, no pre-`--jq`
#     projection; an object read wrapped in a synthetic 1-element array to satisfy
#     the kernel's array requirement), deps-add's lock-label node(id:) read (before
#     the addBlockedBy mutation — never mutate on unverifiable lock state),
#     list-issues' gh issue list output (before the cap check and before emitting
#     the backlog), apply-labels' label read (before the lock gate and before
#     the delta), deps-add's --blocked-by-number node-id read (before the lock gate
#     and the mutation), and readiness' gh repo view read. readiness' issue reads go
#     through the shared library's hivemind_readiness_fetch_snapshot, which carries
#     its own fail-closed shape gate. No subcommand bypasses this kernel — no live read
#     pre-projects before the kernel.
#   - READINESS COMMIT GATE: readiness refuses any <commit> that is not a full
#     lowercase hex object id before any gh or git call, so no ref is ever resolved.
#     A failed read or library return never prints a partial result: stdout is empty.
#   - DEPS-ADD LOCK-READ IS PAGINATION-COMPLETE (fail-closed). The node(id:) labels
#     read requests labels(first: 100) with pageInfo { hasNextPage }; the shared
#     kernel's root_pred requires (.labels.pageInfo.hasNextPage // false) == false,
#     so a CONTINUED labels page (hasNextPage == true) FAILS CLOSED (nonzero,
#     malformed-read) BEFORE assert_unlocked_live and BEFORE addBlockedBy — never
#     mutate on a possibly-incomplete labels array whose later page could carry
#     triage:locked. The `// false` default treats an ABSENT pageInfo as complete
#     (clean single-page fixtures stay green), mirroring deps-read's blockedBy idiom.
#     Both call sites (the LIVE node(id:) read and the OFFLINE --issue-labels-response
#     seam) drive the identical predicate so live and offline cannot diverge.
#   - PER-FAMILY MUTUAL EXCLUSION (clean reconcile): for each family in --targets,
#     the delta REMOVES every existing "<family>:*" label that is not the chosen
#     value and ADDS the chosen value if absent. End state: exactly the chosen
#     value in that family. This is minimal-churn (an already-correct value is not
#     removed-and-re-added) yet self-correcting for the conflicting-duplicate case
#     (e.g. a stray second priority:* is removed). Families NOT in --targets are
#     never touched.
#   - NEVER touches triage:locked. It is a human-only control label: the script
#     ensures it EXISTS (ensure-labels) but never adds or removes it, and refuses
#     to mutate any issue carrying it (skipped-locked). "triage" is never a target
#     family, so the mutex prefix match can never select triage:locked.
#   - NEVER deletes foreign labels. Reconcile only removes labels whose prefix is a
#     family PRESENT in --targets and whose value differs from the chosen one;
#     anything outside the seven managed families (incl. initiative:*, wontfix, …)
#     is invisible to the delta. ensure-labels uses create/update only — no delete.
#   - NEVER touches initiative:* (a special case of the foreign-label invariant —
#     this skill is grouping-agnostic).
#   - ADD-ONLY dependencies. deps-add never removes an existing dependency; removal
#     is a human decision outside this script.
#   - deps-add HONORS triage:locked. Before the addBlockedBy write it resolves the
#     ground-truth labels of the issue being MUTATED (the --issue-id NODE ID) via a
#     node(id:) query and gates through the SINGLE shared decision point
#     assert_unlocked_live (the same lock test apply-labels uses, so the two live
#     mutation paths can never diverge). A locked issue is reported skipped-locked
#     and mutated NOT at all; an unverifiable lock state (unreadable/malformed label
#     read) FAILS CLOSED — never mutate. Only --issue-id is gated; a locked BLOCKER
#     does not block the edge.
#   - A GitHub-rejected dependency CYCLE is surfaced as a warning record (kind
#     cycle-rejected) with exit 0 — the script never crashes on it, so a batch
#     keeps going (issues are independent).
#   - Untrusted issue body/title is DATA: it flows only through `gh --json` output
#     and is never interpolated into shell or into GraphQL query source. GraphQL
#     variables are passed via `gh api graphql -f/-F`, never string-concatenated.
#   - FAIL-CLOSED on malformed injected input to a pure transform (bad --targets,
#     unknown family/value, unreadable injection file) — distinct from the review
#     loop's fail-open posture; here a malformed rating is a usage bug, not noise.
#
# 5. OFFLINE TEST SEAM (STEP-002 depends on this)
# -----------------------------------------------
# Set env TRIAGE_OPS_OFFLINE to any non-empty value to make EVERY subcommand skip
# ALL gh/network calls and instead drive its pure transform over INJECTED input,
# emitting the deterministic artifact (palette / delta / payload / surfaced
# record / normalized deps) to stdout. Input that would normally come from gh is
# injected via flags: --current-labels-file (apply-labels), --response-file
# (deps-read, deps-add, list-issues), --issue-labels-file (deps-add — injects the
# label set the live path would resolve by node id, so the lock gate is offline-
# drivable), --issue-labels-response (deps-add — the RAW lock-label read),
# --blocked-by-number-response (deps-add — the RAW blocker node-id read), and
# --snapshot-file / --repo-response-file (readiness — the issue snapshot nodes and the
# RAW gh repo view read). EVERY fixture/injection flag is honored ONLY when TRIAGE_OPS_OFFLINE
# is set; a live invocation supplying ANY of them is REJECTED fail-closed (exit 2)
# BEFORE any gh call — they are test seams, not live caller payloads, and would
# otherwise spoof state (e.g. omit triage:locked to bypass the human-only lock on
# the deps-add path) or silently no-op a real mutation. This offline-only invariant
# is enforced UNIFORMLY for every subcommand by the single shared guard
# reject_fixture_flags_in_live_mode (one mechanism, no per-subcommand divergence).
# Use `-` for stdin on any *-file
# flag. The pure transforms are factored as functions reading from injected input
# (compute_mutex_delta, build_deps_add_payload, surface_dep_response,
# normalize_deps_read, triage_palette) so the test can drive each directly via
# the offline CLI with only jq + bash, no `gh`. Mirrors fetch-normalize.sh's
# --payload-file injection.

set -euo pipefail

triage_ops_fail() { printf 'triage-ops: %s\n' "$1" >&2; exit 1; }
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || triage_ops_fail "cannot self-locate the script directory; refusing to proceed"
shared_dir="$(CDPATH= cd -- "$script_dir/../../_shared" 2>/dev/null && pwd -P 2>/dev/null)" || triage_ops_fail "cannot resolve skills/_shared from the script directory; refusing to proceed"
[ -f "$shared_dir/readiness-check.sh" ] || triage_ops_fail "required shared library missing: skills/_shared/readiness-check.sh; refusing to proceed"
. "$shared_dir/readiness-check.sh" || triage_ops_fail "failed to source skills/_shared/readiness-check.sh (unparseable); refusing to proceed"

PROG="triage-ops"

die() {
  # Structured, nonzero failure to stderr — propagate, never swallow.
  echo "$PROG: $1" >&2
  exit "${2:-1}"
}

require_gh() {
  command -v gh >/dev/null 2>&1 \
    || die "the '$1' subcommand requires the 'gh' CLI on PATH (offline mode: set TRIAGE_OPS_OFFLINE)" 1
}

is_offline() {
  [ -n "${TRIAGE_OPS_OFFLINE:-}" ]
}

# reject_fixture_flags_in_live_mode <subcommand> <flag-name>=<value> [<flag-name>=<value> ...]
# UNIFIED offline-test-seam gate. Fixture/injection flags (--current-labels-file,
# --response-file) are honored ONLY when TRIAGE_OPS_OFFLINE is set; supplying one
# on a LIVE invocation could spoof state (e.g. omit triage:locked to bypass the
# human-only lock) or silently no-op a real mutation (the live deps-add path).
# So: when NOT offline, any passed flag whose value is non-empty fails CLOSED with
# exit 2 BEFORE any require_gh/gh/graphql call (so STEP-S002's live-reject tests
# run with no gh on PATH). Receives the ALREADY-PARSED flag value(s) as arguments —
# it does NOT re-parse argv (P9: the shared kernel is the offline-gate check only,
# not arg parsing). Each arg is "<flag-name>=<value>"; only the value is tested,
# the name is used solely for the diagnostic message.
reject_fixture_flags_in_live_mode() {
  local subcmd="$1"; shift
  is_offline && return 0
  local pair flag value
  for pair in "$@"; do
    flag="${pair%%=*}"
    value="${pair#*=}"
    [ -z "$value" ] \
      || die "$subcmd: $flag is valid only with TRIAGE_OPS_OFFLINE set" 2
  done
}

# read_injected <path>: read an injected fixture from a file or stdin (`-`).
# Fails CLOSED (nonzero) when the file is unreadable — an explicitly-supplied
# injection path that cannot be read is a usage error, not empty input.
read_injected() {
  local src="$1"
  if [ "$src" = "-" ]; then
    cat
  elif [ -f "$src" ]; then
    cat "$src"
  else
    die "injection file not found: $src" 1
  fi
}

# is_locked_labels <labels-json-array>: pure predicate — true (exit 0) when the
# array of label-name strings contains the human-only control label
# "triage:locked". SINGLE SOURCE of the lock test: both apply-labels and deps-add
# gate through this, so the two live mutation paths can never diverge on what
# "locked" means. Mirrors the apply-labels jq `index("triage:locked")` check.
is_locked_labels() {
  printf '%s' "$1" | jq -e 'index("triage:locked") != null' >/dev/null 2>&1
}

# assert_unlocked_live <subcmd> <labels-json>: the SINGLE live lock decision point
# every live mutation calls (mirrors the shared reject_fixture_flags_in_live_mode
# pattern — one mechanism, no per-subcommand divergence). If the issue's labels
# carry triage:locked, emit the byte-identical skipped-locked record to stdout and
# return 10 to signal the caller to SKIP the mutation and exit 0 (do NOT mutate).
# Otherwise return 0 (caller proceeds to mutate). The skipped-locked record shape
# is per-subcommand: apply-labels emits {issue,status} (existing tests depend on
# the exact bytes); deps-add emits {id,status} keyed on the node id of the issue
# being mutated (--issue-id). The CALLER selects the record via <subcmd>; the lock
# TEST is shared.
# Exit codes: 0 = unlocked (proceed) | 10 = locked (record emitted, skip mutation).
assert_unlocked_live() {
  local subcmd="$1" labels_json="$2"
  is_locked_labels "$labels_json" || return 0
  case "$subcmd" in
    apply-labels)
      jq -c -n --argjson issue "$3" '{ issue: $issue, status: "skipped-locked" }' ;;
    deps-add)
      jq -c -n --arg id "$3" '{ id: $id, status: "skipped-locked" }' ;;
    *)
      die "assert_unlocked_live: unknown subcmd '$subcmd'" 1 ;;
  esac
  return 10
}

# --- Pure transform core (offline-exercisable; no gh) ------------------------

# triage_palette: the SINGLE SOURCE of the fixed label palette. Emits a compact
# JSON array of { name, color, family, managed }. Color constraints (plan
# "Label creation + color palette"): ordinal families are one hue shaded by
# ordinal; `type` values get distinct hues; triage:locked gets a distinct control
# color. Exact hexes are this build's concrete choice. `managed: false` marks the
# human-only control label, which mutex reconcile must never select.
triage_palette() {
  jq -c -n '
    [
      # readiness ladder — neutral grey progression (light=early -> dark=done);
      # off-ladder blocked/parked kept muted-neutral.
      {name:"readiness:ideation",       color:"ededed", family:"readiness", managed:true},
      {name:"readiness:needs-decision", color:"d4d4d4", family:"readiness", managed:true},
      {name:"readiness:interrogation",  color:"bdbdbd", family:"readiness", managed:true},
      {name:"readiness:planning",       color:"a3a3a3", family:"readiness", managed:true},
      {name:"readiness:ready",          color:"8a8a8a", family:"readiness", managed:true},
      {name:"readiness:implementation", color:"707070", family:"readiness", managed:true},
      {name:"readiness:done",           color:"565656", family:"readiness", managed:true},
      {name:"readiness:blocked",        color:"7a6a6a", family:"readiness", managed:true},
      {name:"readiness:parked",         color:"6a6a7a", family:"readiness", managed:true},

      # type — DISTINCT hue per value.
      {name:"type:bug",           color:"d73a4a", family:"type", managed:true},
      {name:"type:idea",          color:"fef2c0", family:"type", managed:true},
      {name:"type:feature",       color:"a2eeef", family:"type", managed:true},
      {name:"type:enhancement",   color:"84b6eb", family:"type", managed:true},
      {name:"type:chore",         color:"c2e0c6", family:"type", managed:true},
      {name:"type:refactor",      color:"5319e7", family:"type", managed:true},
      {name:"type:epic",          color:"3e4b9e", family:"type", managed:true},
      {name:"type:documentation", color:"0075ca", family:"type", managed:true},

      # effort — one hue (purple) light->dark by volume xs->xl.
      {name:"effort:xs", color:"f5f0ff", family:"effort", managed:true},
      {name:"effort:s",  color:"d9c7ff", family:"effort", managed:true},
      {name:"effort:m",  color:"b18cff", family:"effort", managed:true},
      {name:"effort:l",  color:"8a4fff", family:"effort", managed:true},
      {name:"effort:xl", color:"5a189a", family:"effort", managed:true},

      # moscow — commitment red(must) -> grey(wont).
      {name:"moscow:must",   color:"b60205", family:"moscow", managed:true},
      {name:"moscow:should", color:"d98880", family:"moscow", managed:true},
      {name:"moscow:could",  color:"bcaaaa", family:"moscow", managed:true},
      {name:"moscow:wont",   color:"cccccc", family:"moscow", managed:true},

      # priority — sequencing urgency red(high) -> amber -> green(low).
      {name:"priority:high",   color:"b60205", family:"priority", managed:true},
      {name:"priority:medium", color:"fbca04", family:"priority", managed:true},
      {name:"priority:low",    color:"0e8a16", family:"priority", managed:true},

      # risk — likelihood x blast radius red(high) -> amber -> green(low).
      {name:"risk:high",   color:"e11d21", family:"risk", managed:true},
      {name:"risk:medium", color:"fbca04", family:"risk", managed:true},
      {name:"risk:low",    color:"0e8a16", family:"risk", managed:true},

      # difficulty — intellectual hardness, one hue (brown/amber) shaded by ordinal.
      {name:"difficulty:high",   color:"8a3b00", family:"difficulty", managed:true},
      {name:"difficulty:medium", color:"c46210", family:"difficulty", managed:true},
      {name:"difficulty:low",    color:"f4c79e", family:"difficulty", managed:true},

      # control — human-only lock, DISTINCT control color, NOT a managed family.
      {name:"triage:locked", color:"0e1116", family:"control", managed:false}
    ]'
}

# compute_mutex_delta <issue-number> <targets-json> <current-labels-json>:
# pure per-family reconcile. Reads injected input directly (no gh) so the test
# drives it. Validates every target against the palette (single source); an
# unknown family/value fails CLOSED via jq error. See INVARIANTS §4.
compute_mutex_delta() {
  local issue="$1" targets_json="$2" current_json="$3"
  triage_palette | jq -c \
    --argjson issue "$issue" \
    --argjson targets "$targets_json" \
    --argjson current "$current_json" '
    . as $palette
    | ( [ $palette[] | select(.managed) | .name ] ) as $valid
    | ( [ $targets | to_entries[] ] ) as $fams
    | ( [ $fams[] | (.key + ":" + .value) ] ) as $wants
    | ( [ $wants[] as $w | select( ($valid | index($w)) | not ) | $w ] ) as $bad
    | if ($bad | length) > 0
      then error("unknown target label(s): " + ($bad | join(", ")))
      else
        {
          issue: $issue,
          remove: ( [ $fams[] as $f
                      | $current[] as $lbl
                      | $lbl
                      | select(startswith($f.key + ":"))
                      | select(. != ($f.key + ":" + $f.value))
                      # Bound the remove set to the FIXED managed palette: a
                      # foreign/human label sharing a family prefix (e.g.
                      # priority:customer) is invisible and MUST NOT be removed.
                      # NOTE: capture $lbl first — inside `$valid | index(.)` the
                      # `.` rebinds to $valid (the pipe input), so index(.) would
                      # search for the whole array and always match; test the
                      # captured element with `index($lbl)` instead.
                      | select( $valid | index($lbl) ) ] | unique ),
          add:    ( [ $fams[]
                      | (.key + ":" + .value) as $want
                      | select( ($current | index($want)) | not )
                      | $want ] | unique )
        }
      end'
}

# build_deps_add_payload <issue-id> <blocked-by-id>: the GraphQL variables for
# the addBlockedBy mutation. Pure jq construction — node ids pass through as DATA.
build_deps_add_payload() {
  jq -c -n --arg issueId "$1" --arg blockingId "$2" \
    '{ issueId: $issueId, blockingIssueId: $blockingId }'
}

# surface_dep_response <response-json>: classify a raw addBlockedBy GraphQL
# response into a structured record AND signal recoverability via exit code.
# A GraphQL `.errors` array becomes an exit-0 `cycle-rejected` warning ONLY when
# EVERY error in the array names a cycle (the one expected, non-fatal GitHub
# rejection — a cycle is a legitimate "can't add this edge" answer, not a failed
# write). A MIXED array (a cycle error alongside ANY non-cycle error — auth,
# rate-limit, schema) is FAIL-CLOSED: the non-cycle sibling marks a genuine write
# failure that a first-error-only check would mask. EVERY other failure is
# FAIL-CLOSED and exits nonzero so the caller never proceeds as if an edge were
# written when none was: empty/non-JSON transport errors, a success body missing
# the expected addBlockedBy issue numbers, and any array containing a non-cycle
# GraphQL error (auth, rate-limit, 4xx, schema, malformed). The record is still
# emitted on stdout for diagnostics; the EXIT CODE is the gate.
# See INVARIANT §4. Exit codes: 0 = added | cycle-rejected; 1 = fail-closed.
surface_dep_response() {
  local resp="$1"
  # Empty / non-JSON => transport error. Fail closed: record to stderr, exit 1.
  if ! printf '%s' "$resp" | jq -e . >/dev/null 2>&1; then
    jq -c -n '{ status:"error", kind:"transport-error",
                message:"empty or non-JSON response from addBlockedBy" }' >&2
    return 1
  fi
  # Single classification pass (always exits 0): emit the structured record. The
  # record's `kind` is the gate the caller honors — `cycle-rejected` and `added`
  # are recoverable (exit 0); every other kind is fail-closed (exit 1). A
  # non-cycle GraphQL error, or a success body missing the expected addBlockedBy
  # issue numbers, is classified `graphql-error` / `malformed-success`.
  local record kind
  record="$(printf '%s' "$resp" | jq -c '
        if ((.errors // []) | length) > 0
        then
          (.errors | map(.message // "")) as $msgs
          # Recoverable ONLY when EVERY error names a cycle. A single non-cycle
          # sibling (auth/rate-limit/schema) fails the whole array closed — a
          # first-error-only check would mask a real write failure.
          | if ($msgs | all(test("cycl|circular"; "i")))
            then { status: "warning", kind: "cycle-rejected",
                   message: ($msgs[0] // "addBlockedBy rejected") }
            else { status: "error", kind: "graphql-error",
                   message: ($msgs | map(select(test("cycl|circular"; "i") | not)))[0] } end
        elif (.data.addBlockedBy.issue.number != null
              and .data.addBlockedBy.blockingIssue.number != null)
        then { status: "added",
               issue: (.data.addBlockedBy.issue.number),
               blocked_by: (.data.addBlockedBy.blockingIssue.number) }
        else { status: "error", kind: "malformed-success",
               message: "addBlockedBy response missing expected issue numbers" }
        end')"
  kind="$(printf '%s' "$record" | jq -r '.kind // "added"')"
  case "$kind" in
    added|cycle-rejected)  # recoverable: emit on stdout, caller continues.
      printf '%s\n' "$record"; return 0 ;;
    *)  # graphql-error, malformed-success (and any unknown): fail closed.
      printf '%s\n' "$record" >&2; return 1 ;;
  esac
}

# validate_response_shape <resp> <root_path> <root_pred> <coll_path> <elem_pred> <projection>:
# the SINGLE SOURCE fail-closed GraphQL/response-shape validator+normalizer (P1).
# Pure jq+bash, no gh — offline-exercisable. Given a RAW response string and a
# PROJECTION SPEC (author-static jq fragments passed as the 2nd..6th args), it
# REJECTS fail-closed (nonzero, structured kind record to stderr) any of:
#   - empty / non-JSON transport body            => kind transport-error
#   - a non-empty `.errors` array                => kind graphql-error
#   - null/missing entity at <root_path>, or a
#     non-array collection at <coll_path>, or the
#     <root_pred>/<elem_pred> field-completeness
#     predicates failing on any element           => kind malformed-read
# On a clean response it runs <projection> and emits the projected value (exit 0).
#
# PROJECTION SPEC (all jq program fragments — AUTHOR-STATIC, never caller/untrusted
# text; the untrusted RESPONSE is the only value flowing through as DATA, piped on
# stdin and never interpolated, satisfying the §4 no-interpolation invariant):
#   <root_path>   jq path to the entity that holds the collection (e.g.
#                 `.data.repository.issue`); fail-closed when it is null/missing.
#   <root_pred>   jq boolean over that entity bound as `.` (field-completeness on
#                 the root, e.g. numeric number + nonempty string id).
#   <coll_path>   jq path FROM the root entity to the node collection (e.g.
#                 `.blockedBy.nodes`); fail-closed when not an array.
#   <elem_pred>   jq boolean over each element bound as `.` (per-element field
#                 completeness); must hold for EVERY element.
#   <projection>  jq program over the FULL response that yields the clean value.
# Exit codes: 0 = projected; 1 = fail-closed.
validate_response_shape() {
  local resp="$1" root_path="$2" root_pred="$3" coll_path="$4" elem_pred="$5" projection="$6"
  # Empty / non-JSON => transport error. Fail closed (cannot be checked in-jq).
  if ! printf '%s' "$resp" | jq -e . >/dev/null 2>&1; then
    jq -c -n '{ status:"error", kind:"transport-error",
                message:"empty or non-JSON response" }' >&2
    return 1
  fi
  # Any GraphQL `.errors` (no recoverable variant for a read) => fail closed.
  if printf '%s' "$resp" | jq -e '((.errors // []) | length) > 0' >/dev/null 2>&1; then
    printf '%s' "$resp" | jq -c \
      '{ status:"error", kind:"graphql-error",
         message: ((.errors[0].message) // "response rejected") }' >&2
    return 1
  fi
  # Shape + field-completeness gate (root non-null, collection is an array, the
  # root and EVERY element satisfy their completeness predicate). The fragments
  # are spliced into the jq PROGRAM (author-static), never into the DATA.
  if ! printf '%s' "$resp" | jq -e "
        ($root_path) as \$root
        | \$root != null
          and (((\$root | $coll_path) | type) == \"array\")
          and (\$root | ($root_pred))
          and ((\$root | $coll_path) | all($elem_pred))" \
        >/dev/null 2>&1; then
    jq -c -n '{ status:"error", kind:"malformed-read",
                message:"response missing root entity, collection array, or required fields" }' >&2
    return 1
  fi
  printf '%s' "$resp" | jq -c "$projection"
}

# normalize_deps_read <response-json>: project a raw blockedBy GraphQL
# response into the stable deps-read schema (§3) — FAIL-CLOSED, mirroring
# surface_dep_response. A blockedBy read carries NO recoverable failure
# (unlike deps-add's cycle rejection): EVERY failure exits nonzero so the caller
# never makes triage/dependency decisions from a corrupted-into-"no blockers"
# state. Fail-closed on: empty/non-JSON transport errors, any non-empty
# `.errors` (auth, rate-limit, 4xx, schema), a missing/null `.data.repository.issue`
# (issue absent or 200-with-error body), a missing/non-array
# `blockedBy.nodes`, any null/wrong-typed identifier FIELD on the issue
# or a blocker node (null issue id/number, or a blocker missing its number/id/title),
# and a CONTINUED blockedBy connection (`pageInfo.hasNextPage == true`): the query
# requests only the first 50 blockers, so an issue with more than one page would
# normalize as if the unfetched blockers do not exist, letting a re-triage table
# propose bogus dependency removals or re-add an already-existing edge outside the
# first page. That partial read is failed closed rather than emitted.
# A 200 body satisfying the outer shape but carrying null identifiers would
# normalize into dependency records that cannot be safely matched for later
# deps-add/removal, so the field-completeness gate fails it closed too. Only a
# fully-formed issue node with fully-formed blocker nodes is normalized and emitted
# on stdout with exit 0. See INVARIANT §3/§4. Exit codes: 0 = normalized; 1 = fail-closed.
normalize_deps_read() {
  local resp="$1"
  # SINGLE MECHANISM: delegate every shape gate to the shared validator (P1). The
  # projection spec encodes the blockedBy-specific contract as author-static
  # jq fragments — root = the issue node, collection = its blockedBy.nodes,
  # field-completeness on the issue (numeric number + nonempty string id) and on
  # every blocker (numeric number + nonempty string id + title). A null identifier
  # would normalize into a record that cannot be matched for later deps-add/removal,
  # so the field gate fails it closed. Behavior is byte-identical to the prior
  # hand-rolled gates: same kinds (transport-error / graphql-error / malformed-read)
  # and the same exit-1-on-failure / exit-0-on-success contract.
  validate_response_shape "$resp" \
    '.data.repository.issue' \
    '(.number | type == "number")
     and (.id | type == "string" and length > 0)
     and ((.blockedBy.pageInfo.hasNextPage // false) == false)' \
    '.blockedBy.nodes' \
    '(.number | type == "number")
     and (.id | type == "string" and length > 0)
     and (.title | type == "string" and length > 0)' \
    '.data.repository.issue as $i
     | { issue: ($i.number // null),
         id: ($i.id // null),
         blocked_by: [ ($i.blockedBy.nodes)[] | { number, id, title } ] }'
}

# resolve_blocker_node_id <response-json> <number>: project a raw issue(number:) GraphQL
# response into the blocker's node id, through the shared kernel. Fails closed (nonzero) on a
# transport error, a `.errors` envelope, a null issue, a missing id or number, or an issue
# whose number is not <number>. Exit codes: 0 = id printed; 1 = fail-closed.
resolve_blocker_node_id() {
  local resp="$1" number="$2" blocker
  blocker="$(validate_response_shape "$resp" \
    '.data.repository.issue' \
    '(.number | type == "number") and (.id | type == "string" and length > 0)' \
    '[.id]' \
    'type == "string" and length > 0' \
    '.data.repository.issue | { number, id }')" || return 1
  printf '%s' "$blocker" | jq -e -r --arg number "$number" \
    'select((.number | tostring) == $number) | .id'
}

# validate_readiness_overlay <overlay-json>: pure shape gate for the readiness --overlay. True
# (exit 0) only for a non-empty object keyed by issue numbers (^[1-9][0-9]*$) whose every value
# is an object holding no key but `targets` (an object) and `blocked_by` (an array of positive
# integers). Both keys are optional. The targets' palette check is compute_mutex_delta's.
validate_readiness_overlay() {
  printf '%s' "$1" | jq -e '
    type == "object" and length > 0
    and all(to_entries[];
      (.key | test("\\A[1-9][0-9]*\\z"))
      and (.value | type == "object")
      and ((.value | keys) - ["targets", "blocked_by"] | length == 0)
      and ((.value | has("targets") | not) or (.value.targets | type == "object"))
      and ((.value | has("blocked_by") | not)
           or (.value.blocked_by | type == "array"
               and all(.[]; type == "number" and . == floor and . > 0))))' >/dev/null 2>&1
}

# apply_readiness_overlay <issue-number> <node-json> <targets-json> <blocked-by-json>: pure
# overlay of one issue snapshot node. The label names become current minus compute_mutex_delta's
# remove set plus its add set, and each blocked-by number not already present becomes a
# blockedBy node {number}. Prints the overlaid node.
# INVARIANT: a node whose labels or blockedBy nodes are not well-formed passes through unchanged,
# so the readiness library's own snapshot validation fails it closed (snapshot-malformed) rather
# than this transform masking the malformed read.
apply_readiness_overlay() {
  local issue="$1" node="$2" targets_json="$3" blocked_json="$4" current_json delta
  current_json="$(printf '%s' "$node" \
    | jq -c 'try [ .labels.nodes[] | .name | strings ] catch []')" || return 1
  delta="$(compute_mutex_delta "$issue" "$targets_json" "$current_json")" || return 1
  printf '%s' "$node" | jq -c --argjson delta "$delta" --argjson blocked "$blocked_json" '
    if type == "object"
       and (.labels | type) == "object" and (.labels.nodes | type) == "array"
       and all(.labels.nodes[]; type == "object" and (.name | type) == "string")
       and (.blockedBy | type) == "object" and (.blockedBy.nodes | type) == "array"
       and all(.blockedBy.nodes[]; type == "object")
    then
      .labels.nodes |= ( [ .[] | select(.name as $name | ($delta.remove | index($name)) | not) ]
                         + [ $delta.add[] | { name: . } ] )
      | [ .blockedBy.nodes[].number ] as $have
      | .blockedBy.nodes += [ $blocked[] | select(. as $n | ($have | index($n)) | not)
                              | { number: . } ]
    else . end'
}

# --- Baked GraphQL operations (live path only) -------------------------------
# Native GitHub issue dependencies (blocked-by), GA 2025-08-21. Spec citation:
# https://github.blog/changelog/2025-08-21-dependencies-on-issues/ — mutation
# `addBlockedBy(input: AddBlockedByInput!)` with issueId + blockingIssueId; the
# Issue.blockedBy connection reads the blocked-by set. Variables are passed
# via -f/-F (never interpolated). External issue text is never read into source.
DEPS_READ_QUERY='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      id
      number
      blockedBy(first: 50) {
        pageInfo { hasNextPage }
        nodes { id number title }
      }
    }
  }
}'

# Resolve ground-truth labels for an issue by its GraphQL NODE ID — used by
# deps-add to honor the human-only triage:locked lock on the issue being mutated
# (--issue-id) before running addBlockedBy. $id is passed via -f (never
# interpolated); the untrusted label NAMEs flow back only through --jq output.
DEPS_ISSUE_LABELS_QUERY='
query($id: ID!) {
  node(id: $id) {
    ... on Issue {
      labels(first: 100) {
        pageInfo { hasNextPage }
        nodes { name }
      }
    }
  }
}'

# Resolve a blocker's GraphQL NODE ID from its issue number, for deps-add --blocked-by-number.
# owner and repo come from gh's {owner} and {repo} placeholders; $number is passed via -F.
DEPS_BLOCKER_ID_QUERY='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      id
      number
    }
  }
}'

DEPS_ADD_MUTATION='
mutation($issueId: ID!, $blockingIssueId: ID!) {
  addBlockedBy(input: { issueId: $issueId, blockingIssueId: $blockingIssueId }) {
    issue { id number }
    blockingIssue { id number }
  }
}'

# --- Subcommand implementations ----------------------------------------------

cmd_ensure_labels() {
  [ "$#" -eq 0 ] || die "ensure-labels takes no arguments" 2
  if is_offline; then
    triage_palette
    return 0
  fi
  require_gh "ensure-labels"
  # Idempotent create-or-update: --force creates if missing and self-heals a
  # drifted color, and NEVER deletes. Each label is independent — a single
  # failure is reported but does not abort the rest (issues/labels independent).
  local failures=0
  while IFS=$'\t' read -r name color family; do
    local desc="triage ${family} rating"
    [ "$family" = "control" ] && desc="human-only triage lock (never set by the skill)"
    if ! gh label create "$name" --color "$color" --description "$desc" --force >/dev/null 2>&1; then
      echo "$PROG: WARNING failed to ensure label '$name'" >&2
      failures=$((failures + 1))
    fi
  done < <(triage_palette | jq -r '.[] | [.name, .color, .family] | @tsv')
  [ "$failures" -eq 0 ] || die "ensure-labels: $failures label(s) failed to apply" 1
}

cmd_list_issues() {
  local limit=500 response_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --limit) [ "$#" -ge 2 ] || die "missing value for --limit" 2
               limit="$2"; shift 2 ;;
      --response-file) [ "$#" -ge 2 ] || die "missing value for --response-file" 2
               response_file="$2"; shift 2 ;;
      *) die "list-issues: unexpected argument '$1'" 2 ;;
    esac
  done
  case "$limit" in ''|*[!0-9]*) die "list-issues: --limit must be an integer" 2 ;; esac

  # No silent truncation. The skill advertises the ENTIRE backlog, but `gh issue
  # list --limit N` caps at N with no signal that more exist. So: whenever the
  # produced row-count EQUALS the requested --limit, the cap may have been hit —
  # FAIL CLOSED with a diagnostic telling the caller to raise --limit and re-run
  # (no pagination). The check is applied UNIFORMLY over the produced rows in BOTH
  # offline (identity over --response-file) and live (gh) paths, so STEP-L002 can
  # drive it offline with an injected fixture of exactly --limit rows.
  local rows row_count
  if is_offline; then
    [ -n "$response_file" ] || die "offline list-issues requires --response-file" 2
    rows="$(read_injected "$response_file" | jq -c .)"
  else
    reject_fixture_flags_in_live_mode "list-issues" "--response-file=$response_file"
    require_gh "list-issues"
    rows="$(gh issue list --state open --limit "$limit" \
              --json number,title,labels,body,id)" \
      || die "list-issues: gh issue list failed" 1
  fi
  # Shape-validate the produced rows through the SHARED kernel IN ADDITION TO the
  # cap check (both run; neither replaces the other), in BOTH offline and live
  # paths, so an error/malformed body is never emitted as the backlog. Root = the
  # whole response, collection = the rows themselves, per-row field-completeness
  # (numeric number + nonempty string id/title). Well-formed rows pass through
  # byte-identically (projection is the identity over the row array).
  rows="$(validate_response_shape "$rows" \
    '.' \
    'true' \
    '.' \
    '(.number | type == "number")
     and (.id | type == "string" and length > 0)
     and (.title | type == "string" and length > 0)' \
    '.')" \
    || die "list-issues: produced rows are not a clean array of well-formed issue rows" 1
  row_count="$(printf '%s' "$rows" | jq 'length')"
  [ "$row_count" -lt "$limit" ] \
    || die "list-issues: returned exactly --limit ($limit) rows — the cap may have truncated the backlog; raise --limit and re-run" 1
  printf '%s\n' "$rows"
}

cmd_apply_labels() {
  local issue="" targets_json="" targets_file="" current_file=""
  [ "$#" -ge 1 ] || die "apply-labels requires an issue number" 2
  issue="$1"; shift
  case "$issue" in ''|*[!0-9]*) die "apply-labels: issue number must be an integer (got '$issue')" 2 ;; esac
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --targets) [ "$#" -ge 2 ] || die "missing value for --targets" 2
                 targets_json="$2"; shift 2 ;;
      --targets-file) [ "$#" -ge 2 ] || die "missing value for --targets-file" 2
                 targets_file="$2"; shift 2 ;;
      --current-labels-file) [ "$#" -ge 2 ] || die "missing value for --current-labels-file" 2
                 current_file="$2"; shift 2 ;;
      *) die "apply-labels: unexpected argument '$1'" 2 ;;
    esac
  done
  if [ -n "$targets_file" ]; then
    [ -z "$targets_json" ] || die "apply-labels: pass --targets OR --targets-file, not both" 2
    targets_json="$(read_injected "$targets_file")"
  fi
  [ -n "$targets_json" ] || die "apply-labels requires --targets or --targets-file" 2
  printf '%s' "$targets_json" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || die "apply-labels: --targets must be a JSON object (family->value)" 2

  local current_json
  if is_offline; then
    [ -n "$current_file" ] || die "offline apply-labels requires --current-labels-file" 2
    current_json="$(read_injected "$current_file")"
    printf '%s' "$current_json" | jq -e 'type == "array"' >/dev/null 2>&1 \
      || die "apply-labels: --current-labels-file must be a JSON array of label names" 2
    compute_mutex_delta "$issue" "$targets_json" "$current_json"
    return 0
  fi

  # --current-labels-file is a TEST SEAM (offline only). In the LIVE path it would
  # let a caller spoof the label set — including omitting triage:locked to bypass
  # the human-only lock. The UNIFIED guard rejects it fail-closed BEFORE any gh
  # call so the live path derives ground truth UNCONDITIONALLY from `gh issue view`.
  reject_fixture_flags_in_live_mode "apply-labels" "--current-labels-file=$current_file"
  require_gh "apply-labels"
  # Route the lock-bearing label read through the SHARED kernel so it is uniformly
  # fail-closed: a `.errors`/null/non-array/null-element body dies BEFORE the lock
  # gate, never spoofing an unlocked set. Read the raw labels object (not pre-
  # projected) so the kernel can validate shape, then project the clean name array.
  local labels_resp
  labels_resp="$(gh issue view "$issue" --json labels)" \
    || die "apply-labels: failed to read current labels for issue #$issue" 1
  current_json="$(validate_response_shape "$labels_resp" \
    '.' \
    'true' \
    '.labels' \
    '(.name | type == "string" and length > 0)' \
    '[ .labels[].name ]')" \
    || die "apply-labels: cannot verify lock state for issue #$issue (unreadable/malformed label response)" 1
  # Honor the human-only lock via the SHARED gate (single decision point; mirrors
  # reject_fixture_flags_in_live_mode). A locked issue emits the byte-identical
  # skipped-locked record (return 10) and mutates NOTHING — caller exits 0.
  assert_unlocked_live "apply-labels" "$current_json" "$issue" || return 0

  local delta
  delta="$(compute_mutex_delta "$issue" "$targets_json" "$current_json")"

  # Build one `gh issue edit` invocation from the delta (atomic per issue).
  local -a edit_args=()
  while IFS= read -r lbl; do
    [ -n "$lbl" ] && edit_args+=(--remove-label "$lbl")
  done < <(printf '%s' "$delta" | jq -r '.remove[]')
  while IFS= read -r lbl; do
    [ -n "$lbl" ] && edit_args+=(--add-label "$lbl")
  done < <(printf '%s' "$delta" | jq -r '.add[]')

  if [ "${#edit_args[@]}" -gt 0 ]; then
    gh issue edit "$issue" "${edit_args[@]}" >/dev/null \
      || die "apply-labels: gh issue edit failed for issue #$issue" 1
  fi
  printf '%s' "$delta" | jq -c '. + { status: "applied" }'
}

cmd_deps_read() {
  local issue="" response_file=""
  [ "$#" -ge 1 ] || die "deps-read requires an issue number" 2
  issue="$1"; shift
  case "$issue" in ''|*[!0-9]*) die "deps-read: issue number must be an integer (got '$issue')" 2 ;; esac
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --response-file) [ "$#" -ge 2 ] || die "missing value for --response-file" 2
               response_file="$2"; shift 2 ;;
      *) die "deps-read: unexpected argument '$1'" 2 ;;
    esac
  done
  if is_offline; then
    [ -n "$response_file" ] || die "offline deps-read requires --response-file" 2
    # Propagate normalize_deps_read's fail-closed exit code — do NOT mask with
    # `return 0` (mirrors the cmd_deps_add fix): a GraphQL error / null-issue /
    # malformed read must surface as nonzero through the offline seam too.
    normalize_deps_read "$(read_injected "$response_file")"
    return
  fi
  reject_fixture_flags_in_live_mode "deps-read" "--response-file=$response_file"
  require_gh "deps-read"
  local repo_resp owner_repo owner_repo_preview owner repo resp
  # Route the repo-name read through the SHARED kernel too (no pre-`--jq`
  # projection): read the RAW object and let validate_response_shape gate its
  # shape, then split owner/repo from the KERNEL-VALIDATED value. `gh repo view`
  # returns an OBJECT, so wrap nameWithOwner in a synthetic 1-element array to
  # satisfy the kernel's array-at-coll_path requirement.
  repo_resp="$(gh repo view --json nameWithOwner)" \
    || die "deps-read: failed to resolve owner/repo" 1
  owner_repo="$(validate_response_shape "$repo_resp" \
    '.' \
    '.nameWithOwner | type == "string" and length > 0' \
    '[.nameWithOwner]' \
    'type == "string" and length > 0' \
    '.nameWithOwner')" \
    || die "deps-read: failed to resolve owner/repo (unreadable/malformed repo response)" 1
  owner_repo="$(printf '%s' "$owner_repo" | jq -r .)"
  # Defense-in-depth: validate the kernel-projected token is exactly one owner/repo
  # shape before splitting (owner/repo still flow only as inert `gh -f` data flags).
  # The rejected value crosses a trust boundary, so the diagnostic emits only a
  # JSON-escaped, length-bounded preview of it (never the raw bytes) per ADR-0019 —
  # control bytes / newlines / terminal escapes cannot reach the log raw.
  if [[ ! "$owner_repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    owner_repo_preview="$(printf '%s' "$owner_repo" \
      | jq -Rs '.[0:80] | tojson' 2>/dev/null)" \
      || owner_repo_preview='"<unprintable>"'
    die "deps-read: resolved owner/repo is not a valid 'owner/repo' token (got ${owner_repo_preview})" 1
  fi
  owner="${owner_repo%%/*}"; repo="${owner_repo#*/}"
  resp="$(gh api graphql -f query="$DEPS_READ_QUERY" \
            -f owner="$owner" -f repo="$repo" -F number="$issue" 2>/dev/null)" \
    || die "deps-read: GraphQL query failed for issue #$issue" 1
  normalize_deps_read "$resp"
}

cmd_deps_add() {
  local issue_id="" blocked_by_id="" response_file="" issue_labels_file="" issue_labels_response=""
  local blocked_by_number="" blocked_by_number_response=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --issue-id) [ "$#" -ge 2 ] || die "missing value for --issue-id" 2
               issue_id="$2"; shift 2 ;;
      --blocked-by-id) [ "$#" -ge 2 ] || die "missing value for --blocked-by-id" 2
               blocked_by_id="$2"; shift 2 ;;
      --blocked-by-number) [ "$#" -ge 2 ] || die "missing value for --blocked-by-number" 2
               blocked_by_number="$2"; shift 2 ;;
      --blocked-by-number-response) [ "$#" -ge 2 ] || die "missing value for --blocked-by-number-response" 2
               blocked_by_number_response="$2"; shift 2 ;;
      --response-file) [ "$#" -ge 2 ] || die "missing value for --response-file" 2
               response_file="$2"; shift 2 ;;
      --issue-labels-file) [ "$#" -ge 2 ] || die "missing value for --issue-labels-file" 2
               issue_labels_file="$2"; shift 2 ;;
      # NEW SEAM (STEP-N004 drives the security-critical lock-read fail-closed path
      # offline): inject the RAW node(id:) labels GraphQL response — exactly what
      # the live path feeds to validate_response_shape — so the kernel guard
      # (.errors/null-node/non-array/null-element => fail closed) is offline-
      # exercisable. Distinct from --issue-labels-file, which injects a PRE-
      # PROJECTED label array and thus bypasses the raw-response kernel guard.
      --issue-labels-response) [ "$#" -ge 2 ] || die "missing value for --issue-labels-response" 2
               issue_labels_response="$2"; shift 2 ;;
      *) die "deps-add: unexpected argument '$1'" 2 ;;
    esac
  done
  if [ -n "$blocked_by_number" ]; then
    [ -z "$blocked_by_id" ] \
      || die "deps-add: pass --blocked-by-id OR --blocked-by-number, not both" 2
    [[ "$blocked_by_number" =~ ^[1-9][0-9]*$ ]] \
      || die "deps-add: --blocked-by-number must be a positive issue number" 2
  fi

  if is_offline; then
    if [ -n "$response_file" ]; then
      # Propagate surface_dep_response's exit code — a fail-closed (non-cycle)
      # error must surface as nonzero on the offline seam too, not be masked.
      surface_dep_response "$(read_injected "$response_file")"
      return "$?"
    fi
    [ -n "$issue_id" ] && { [ -n "$blocked_by_id" ] || [ -n "$blocked_by_number" ]; } \
      || die "offline deps-add requires --issue-id and --blocked-by-id or --blocked-by-number (or --response-file)" 2
    # Offline blocker-number seam: drive the live number->id resolution (shared kernel gate)
    # over an injected RAW issue(number:) response, before any lock gate or payload.
    if [ -n "$blocked_by_number" ]; then
      [ -n "$blocked_by_number_response" ] \
        || die "offline deps-add --blocked-by-number requires --blocked-by-number-response" 2
      local raw_blocker_resp
      raw_blocker_resp="$(read_injected "$blocked_by_number_response")"
      blocked_by_id="$(resolve_blocker_node_id "$raw_blocker_resp" "$blocked_by_number")" \
        || die "deps-add: cannot resolve the node id of blocker issue #$blocked_by_number (unreadable/malformed/null read)" 1
    elif [ -n "$blocked_by_number_response" ]; then
      die "deps-add: --blocked-by-number-response is valid only with --blocked-by-number" 2
    fi
    # Offline RAW-response lock seam: drive the SECURITY-CRITICAL live lock-read
    # path — the SHARED kernel guard + the lock gate — over an injected RAW
    # node(id:) labels response (mirrors the live deps-add lock read exactly). A
    # malformed/error body FAILS CLOSED before any gate; a clean body projects to
    # the label array and feeds assert_unlocked_live (locked => skipped-locked, no
    # payload; unlocked => payload). Distinct from --issue-labels-file below, which
    # injects the already-projected array and bypasses the raw-response guard.
    if [ -n "$issue_labels_response" ]; then
      local raw_labels_resp injected_labels_json
      raw_labels_resp="$(read_injected "$issue_labels_response")"
      injected_labels_json="$(validate_response_shape "$raw_labels_resp" \
        '.data.node' \
        '(.labels.pageInfo.hasNextPage // false) == false' \
        '.labels.nodes' \
        '(.name | type == "string" and length > 0)' \
        '[ .data.node.labels.nodes[].name ]')" \
        || die "deps-add: cannot verify lock state for issue id '$issue_id' (unreadable/malformed label response)" 1
      assert_unlocked_live "deps-add" "$injected_labels_json" "$issue_id" || return 0
      build_deps_add_payload "$issue_id" "$blocked_by_id"
      return 0
    fi
    # Offline lock seam: drive the SHARED gate over injected labels. A locked set
    # emits the byte-identical skipped-locked record and short-circuits with NO
    # payload (mirrors the live skip); an unlocked set proceeds to payload build.
    if [ -n "$issue_labels_file" ]; then
      local injected_labels
      injected_labels="$(read_injected "$issue_labels_file")"
      printf '%s' "$injected_labels" | jq -e 'type == "array"' >/dev/null 2>&1 \
        || die "deps-add: --issue-labels-file must be a JSON array of label names" 2
      assert_unlocked_live "deps-add" "$injected_labels" "$issue_id" || return 0
    fi
    build_deps_add_payload "$issue_id" "$blocked_by_id"
    return 0
  fi

  reject_fixture_flags_in_live_mode "deps-add" \
    "--response-file=$response_file" "--issue-labels-file=$issue_labels_file" \
    "--issue-labels-response=$issue_labels_response" \
    "--blocked-by-number-response=$blocked_by_number_response"
  [ -n "$issue_id" ] && { [ -n "$blocked_by_id" ] || [ -n "$blocked_by_number" ]; } \
    || die "deps-add requires --issue-id and --blocked-by-id or --blocked-by-number" 2
  require_gh "deps-add"
  # Resolve --blocked-by-number to the blocker's node id BEFORE the lock gate and the
  # mutation, through the shared kernel: a null issue, an `.errors` envelope or a malformed
  # body FAILS CLOSED, so addBlockedBy never runs against an unverified blocker.
  if [ -n "$blocked_by_number" ]; then
    local blocker_resp
    blocker_resp="$(gh api graphql -f query="$DEPS_BLOCKER_ID_QUERY" \
                      -F owner='{owner}' -F repo='{repo}' -F number="$blocked_by_number" 2>/dev/null)" || true
    blocked_by_id="$(resolve_blocker_node_id "$blocker_resp" "$blocked_by_number")" \
      || die "deps-add: cannot resolve the node id of blocker issue #$blocked_by_number (unreadable/malformed/null read)" 1
  fi
  # Honor the human-only lock on the issue being MUTATED (--issue-id) BEFORE the
  # addBlockedBy write, via the SAME shared gate apply-labels uses. Resolve
  # ground-truth labels by node id ($id passed via -f, never interpolated). Only
  # the issue GAINING the dependency is gated — a locked BLOCKER does not block the
  # edge. SECURITY-CRITICAL: route the raw label response through the SHARED kernel
  # validate_response_shape so a `.errors`/null-node/non-array/null-element body
  # FAILS CLOSED (nonzero) BEFORE assert_unlocked_live and BEFORE the mutation —
  # NEVER mutate on an unverifiable lock state. The kernel projects the node's
  # labels into a clean string array; that array feeds the lock gate.
  local labels_resp current_json
  labels_resp="$(gh api graphql -f query="$DEPS_ISSUE_LABELS_QUERY" \
                   -f id="$issue_id" 2>/dev/null)" || true
  current_json="$(validate_response_shape "$labels_resp" \
    '.data.node' \
    '(.labels.pageInfo.hasNextPage // false) == false' \
    '.labels.nodes' \
    '(.name | type == "string" and length > 0)' \
    '[ .data.node.labels.nodes[].name ]')" \
    || die "deps-add: cannot verify lock state for issue id '$issue_id' (unreadable/malformed label response)" 1
  assert_unlocked_live "deps-add" "$current_json" "$issue_id" || return 0

  # Capture stdout regardless of gh's exit status: a GraphQL cycle rejection
  # returns the error BODY (which surface_dep_response classifies) yet gh exits
  # nonzero. The surfacing function is the single decision point — never crash.
  local resp
  resp="$(gh api graphql -f query="$DEPS_ADD_MUTATION" \
            -f issueId="$issue_id" -f blockingIssueId="$blocked_by_id" 2>/dev/null)" || true
  surface_dep_response "$resp"
}

cmd_readiness() {
  local commit="" overlay_json="" snapshot_file="" repo_response_file=""
  [ "$#" -ge 1 ] || die "readiness requires a commit id" 2
  commit="$1"; shift
  # The commit gate runs before any gh or git call: a branch name, HEAD, a local ref, short or
  # uppercase hex never reaches the library's git reads.
  hivemind_readiness_commit_ok "$commit" \
    || die "readiness: <commit> must be a full lowercase hex commit id (40 or 64 characters)" 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --overlay) [ "$#" -ge 2 ] || die "missing value for --overlay" 2
                 overlay_json="$2"; shift 2 ;;
      --snapshot-file) [ "$#" -ge 2 ] || die "missing value for --snapshot-file" 2
                 snapshot_file="$2"; shift 2 ;;
      --repo-response-file) [ "$#" -ge 2 ] || die "missing value for --repo-response-file" 2
                 repo_response_file="$2"; shift 2 ;;
      *) die "readiness: unexpected argument '$1'" 2 ;;
    esac
  done
  [ -n "$overlay_json" ] || die "readiness requires --overlay" 2
  validate_readiness_overlay "$overlay_json" \
    || die "readiness: --overlay must be a non-empty object keyed by issue number, each value {\"targets\": {family: value}, \"blocked_by\": [positive integers]} with no other keys" 2

  local key keys_text entry targets_json blocked_json
  local -a issue_keys=()
  keys_text="$(printf '%s' "$overlay_json" | jq -r 'keys_unsorted | sort_by(tonumber) | .[]')" \
    || die "readiness: cannot order the --overlay issue numbers" 1
  mapfile -t issue_keys <<<"$keys_text"
  # Every target is checked against the palette exactly as apply-labels checks --targets, for
  # every issue, before any gh call.
  for key in "${issue_keys[@]}"; do
    targets_json="$(printf '%s' "$overlay_json" | jq -c --arg k "$key" '.[$k].targets // {}')"
    compute_mutex_delta "$key" "$targets_json" '[]' >/dev/null \
      || die "readiness: --overlay targets for issue #$key name a label outside the managed palette" 2
  done

  local repo_resp snapshot_json=""
  if is_offline; then
    [ -n "$snapshot_file" ] && [ -n "$repo_response_file" ] \
      || die "offline readiness requires --snapshot-file and --repo-response-file" 2
    snapshot_json="$(read_injected "$snapshot_file")"
    repo_resp="$(read_injected "$repo_response_file")"
  else
    reject_fixture_flags_in_live_mode "readiness" \
      "--snapshot-file=$snapshot_file" "--repo-response-file=$repo_response_file"
    require_gh "readiness"
    repo_resp="$(gh repo view --json nameWithOwner,defaultBranchRef)" \
      || die "readiness: failed to resolve owner/repo and the default branch" 1
  fi
  # The repo read routes RAW through the shared kernel; the object is wrapped in a synthetic
  # 1-element array to satisfy the kernel's array requirement (as deps-read does).
  local repo_target owner_repo trunk
  repo_target="$(validate_response_shape "$repo_resp" \
    '.' \
    '(.nameWithOwner | type == "string" and length > 0)
     and (.defaultBranchRef.name | type == "string" and length > 0)' \
    '[.nameWithOwner]' \
    'type == "string" and length > 0' \
    '{ owner_repo: .nameWithOwner, trunk: .defaultBranchRef.name }')" \
    || die "readiness: failed to resolve owner/repo and the default branch (unreadable/malformed repo response)" 1
  owner_repo="$(printf '%s' "$repo_target" | jq -r '.owner_repo')"
  trunk="$(printf '%s' "$repo_target" | jq -r '.trunk')"

  local node nodes="" output
  for key in "${issue_keys[@]}"; do
    entry="$(printf '%s' "$overlay_json" | jq -c --arg k "$key" '.[$k]')"
    targets_json="$(printf '%s' "$entry" | jq -c '.targets // {}')"
    blocked_json="$(printf '%s' "$entry" | jq -c '.blocked_by // [] | unique')"
    if is_offline; then
      node="$(printf '%s' "$snapshot_json" \
        | jq -c --arg k "$key" 'if type == "object" then .[$k] else null end')" \
        || die "readiness: --snapshot-file is not JSON" 1
    else
      node="$(hivemind_readiness_fetch_snapshot "$owner_repo" "$key")" \
        || die "readiness: snapshot read failed for issue #$key; no issue was evaluated" 1
    fi
    node="$(apply_readiness_overlay "$key" "$node" "$targets_json" "$blocked_json")" \
      || die "readiness: cannot apply the overlay to issue #$key" 1
    nodes+="${nodes:+,}$node"
  done
  output="$(printf '[%s]\n' "$nodes" \
    | hivemind_readiness_check_snapshot "$commit" "$owner_repo" "$trunk")" \
    || die "readiness: readiness check failed; no issue was evaluated" 1
  [ -z "$output" ] || printf '%s\n' "$output"
}

# --- Dispatch ----------------------------------------------------------------

usage() {
  cat >&2 <<EOF
$PROG — deterministic mechanism for the hivemind triage-backlog skill.
usage: $PROG <subcommand> [args]
subcommands:
  ensure-labels
  list-issues   [--limit N] [--response-file <path|->]
  apply-labels  <issue> --targets <json>|--targets-file <path> [--current-labels-file <path|->]
  deps-read     <issue> [--response-file <path|->]
  deps-add      --issue-id <ID> --blocked-by-id <ID>|--blocked-by-number <n> [--response-file <path|->]
                [--issue-labels-file <path|->] [--issue-labels-response <path|->]
                [--blocked-by-number-response <path|->]
  readiness     <commit> --overlay <json> [--snapshot-file <path|->] [--repo-response-file <path|->]
Set TRIAGE_OPS_OFFLINE to drive the pure transforms over injected input (no gh).
Test flags (offline only; rejected on a live run): --current-labels-file, --response-file,
--issue-labels-file, --issue-labels-response, --blocked-by-number-response, --snapshot-file,
--repo-response-file.
EOF
}

[ "$#" -ge 1 ] || { usage; exit 2; }
subcmd="$1"; shift
case "$subcmd" in
  ensure-labels) cmd_ensure_labels "$@" ;;
  list-issues)   cmd_list_issues "$@" ;;
  apply-labels)  cmd_apply_labels "$@" ;;
  deps-read)     cmd_deps_read "$@" ;;
  deps-add)      cmd_deps_add "$@" ;;
  readiness)     cmd_readiness "$@" ;;
  -h|--help)     usage; exit 0 ;;
  *)             die "unknown subcommand '$subcmd' (try --help)" 2 ;;
esac
