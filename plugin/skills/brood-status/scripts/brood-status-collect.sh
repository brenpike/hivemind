#!/usr/bin/env bash
#
# brood-status-collect — THIN executable entrypoint for the brood-status collection loop
# (ADR-0020). The read-side analog completion of the brood-status engine: discovery
# (brood-discover.sh) + single-manifest projection (brood-status-project.sh) were
# already committed; THIS script owns the LOOP, the IMPURE per-strain observable probing, the
# pure status-derivation (via _shared/brood-status-derive.sh), and aggregation, emitting ONE JSON
# document the navigator renders. It replaces the prose loop/derivation that previously lived in
# brood-status's SKILL.md steps 2..5 — exactly the "inline navigator-body logic" ADR-0020 rejects.
#
# STRUCTURAL SPLICE CLOSURE (the security point): the navigator previously spliced each
# discovered manifest path AND the operator-controlled checkout root into an LLM-authored Bash
# command (`bash brood-status-project.sh "<manifest_path>" "<checkout_root>"`). Per
# security-policy.md / ADR-0019, double-quoting does NOT neutralize `$(...)`, backticks, or `${}`
# in command SOURCE. This entrypoint runs the loop and invokes the projector with INERT shell
# variables (`"$manifest"`, `"$root"`), so untrusted paths NEVER cross into LLM-authored command
# source. Both residuals close BY CONSTRUCTION: the brood-id segment (already gated) AND
# the operator-controlled checkout-root (deferred).
#
# RUNTIME DEPS: jq is a hard dep (the projector output is consumed + a JSON document is built with
# jq so all escaping is automatic). Unlike the PURE projector, tmux/gh/git ARE required here —
# this is the IMPURE observable-probing layer. A missing observable tool degrades gracefully
# per-probe (a dead/none/unknown observable), it does not abort the run.
#
# OUTPUT (CONTRACT — the navigator depends on this schema):
#   ONE JSON document on stdout, schema "brood-status-collect/1":
#     { "schema": "brood-status-collect/1",
#       "broods": [ { "brood_id", "status":"ok|empty|unreadable|blocker", "detail":string|null,
#         "strains":[ {"name","branch","session":"alive|dead","tmux_session",
#           "pr":{"number":int|null,"state":"open|merged|none|unknown"},
#           "workflow_state","run_status","derived_status"} ],
#           workflow_state is a real workflow-state token or one of the fixed tokens MISSING /
#           MALFORMED / NO_LEDGER_POINTER (legacy manifest with no ledger pointer); run_status is a
#           real run.status token or MISSING / MALFORMED.
#         "summary":{"complete","running","blocked_failed","total"} } ],
#       "global":{"total_broods","unreadable","complete","total_strains"} }
#   Broods in sorted discovery order; strains in projector/manifest order. PER-BROOD FAILURE
#   ISOLATION is MANDATORY: one bad manifest never aborts the run — it becomes an unreadable/blocker
#   brood entry and the loop continues.
#
# Conventions (ADR-0020 thin entrypoint): `set -euo pipefail`, an EXIT trap ending in a
# guaranteed-zero `:`, self-location via `cd && pwd -P`, NO `realpath`/`readlink`.

set -euo pipefail
trap ':' EXIT
blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# ── Self-location + shared libs ───────────────────────────────────────────────────
# layout plugin/skills/brood-status/scripts/ => 3 dirs up is the plugin root. cd && pwd -P is
# portable (no realpath/readlink). NO ${CLAUDE_PLUGIN_ROOT} inside an engine script.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve the plugin root from the script directory; refusing to proceed"
DISCOVER_SCRIPT="$script_dir/brood-discover.sh"
PROJECT_SCRIPT="$script_dir/brood-status-project.sh"
[ -f "$plugin_root/skills/_shared/brood-status-derive.sh" ] || blocker "required shared library missing: skills/_shared/brood-status-derive.sh; refusing to proceed"
. "$plugin_root/skills/_shared/brood-status-derive.sh" || blocker "failed to source skills/_shared/brood-status-derive.sh (unparseable); refusing to proceed"

# ── Dependency check ──────────────────────────────────────────────────────────────
# jq is the hard floor (consume projector TAB output + build the JSON document). git resolves the
# checkout root + the per-strain branch existence probe. tmux/gh probes degrade per-probe when
# absent (see probe sites), so they are NOT hard deps — a host without them still produces a
# well-formed document (sessions dead, PRs none/unknown).
command -v jq >/dev/null 2>&1 \
  || { printf 'blocker: jq is required to build the brood-status JSON document but is not installed\n' >&2; exit 1; }

# ── Checkout root (INERT $var — never emitted into LLM-facing command source) ─────
# The SAME anchor spawn-brood.sh writes against, so read side and write side agree by construction.
# Held in a shell var; used ONLY as an internal projector arg, never echoed into agent context.
root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$root" ] || [ ! -d "$root" ]; then
  printf 'blocker: not inside a git checkout (git rev-parse --show-toplevel failed)\n' >&2
  exit 1
fi

# ── Discover manifests (validated brood-id segments; treat as DATA) ────────────────
# brood-discover.sh emits sorted absolute manifest paths, one per line. Capture into an array
# with a Bash-3.2-portable read loop (mapfile/readarray are Bash-4-only and absent on macOS system
# bash 3.2) so a path is never re-parsed as shell. Zero lines -> empty broods array.
manifests=()
if discover_out="$(bash "$DISCOVER_SCRIPT" "$root" 2>/dev/null)"; then
  if [ -n "$discover_out" ]; then
    while IFS= read -r manifest_line || [ -n "$manifest_line" ]; do
      manifests+=("$manifest_line")
    done <<< "$discover_out"
  fi
fi

# ── Per-strain observable probes (IMPURE) ─────────────────────────────────────────
# Each probe consumes a projector-VALIDATED token. Skip a probe when its required token is EITHER
# of the projector's two fixed sentinels — `MISSING` (absent field) or `MALFORMED` (rejected
# field): tmux_session gates the tmux probe; the git LIVE branch (live_branch, field 10) gates the
# PR probe. Both sentinels are FIXED tokens the projector emits in lieu of a real identifier (see
# brood-status-project.sh field emission), NOT probeable observables — probing
# `tmux has-session -t MISSING` or `gh pr list --head MISSING` would let an unrelated real
# session/branch/PR literally named `MISSING`/`MALFORMED` masquerade as this strain's observable,
# fabricating alive/open/merged/running status and hiding the very manifest corruption the sentinel
# signals. A MALFORMED/MISSING *ledger* scalar still NEVER suppresses an observable probe
# (informational-only); only the probe's OWN gating token (tmux_session / live_branch) is checked
# here. These tokens are inert "$var" args, never command source.
SENTINEL_RE='^(MISSING|MALFORMED)$'

# probe_session_alive <tmux_session> -> echoes 1 (alive) or 0 (dead/skip).
probe_session_alive() {
  local sess="$1"
  [[ "$sess" =~ $SENTINEL_RE ]] && { printf '0'; return 0; }
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$sess" 2>/dev/null; then
    printf '1'
  else
    printf '0'
  fi
  return 0
}

# probe_pr <live_branch> -> echoes "<state>\t<number>" where state is open|merged|none|unknown and
# number is the PR number or empty. The argument is the selected worktree's git GROUND-TRUTH LIVE
# branch (projector field 10), NOT the manifest `branch` column: a brood child opens its PR from
# the DERIVED branch it switched its worktree HEAD onto, so keying on the stale manifest scratch ref
# would find no PR and falsely derive `failed (session ended, no PR)` (#270). A MISSING/MALFORMED
# live branch skips the probe — both are fixed projector sentinels (a detached-HEAD worktree or an
# identifier-rejected branch), not real branch names (state=unknown is reserved for a real gh
# failure; a sentinel yields none with no number, never a probe against a branch literally named
# `MISSING`/`MALFORMED`). gh failure -> unknown.
probe_pr() {
  local branch="$1"
  if [[ "$branch" =~ $SENTINEL_RE ]]; then
    printf 'none\t'
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    # gh absent => the PR probe was never performed: report the state as UNOBSERVABLE
    # (unknown), NOT a confirmed absence (none). Matches the gh-failure path below, so a real
    # open/merged PR is never masked as `PR: —` on a host without the GitHub CLI.
    printf 'unknown\t'
    return 0
  fi
  local pr_json
  if ! pr_json="$(gh pr list --head "$branch" --state all --json number,state --jq '.[0] // empty' 2>/dev/null)"; then
    printf 'unknown\t'
    return 0
  fi
  if [ -z "$pr_json" ]; then
    printf 'none\t'
    return 0
  fi
  # gh PR state is OPEN|CLOSED|MERGED; map to the dashboard's open|merged|none vocabulary.
  local state number
  state="$(printf '%s' "$pr_json" | jq -r '.state // empty')"
  number="$(printf '%s' "$pr_json" | jq -r '.number // empty')"
  case "$state" in
    OPEN)   printf 'open\t%s' "$number" ;;
    MERGED) printf 'merged\t%s' "$number" ;;
    *)      printf 'none\t%s' "$number" ;;
  esac
  return 0
}

# ── Collect loop ──────────────────────────────────────────────────────────────────
# Build the broods JSON array element-by-element with jq (NO hand-concatenation — jq owns all
# string escaping), then fold into the final document. Per-brood global records feed the global
# aggregate. A tab character literal for splitting projector/probe output.
TAB="$(printf '\t')"

brood_objects=()       # one jq-built JSON object per brood, in discovery order
global_records=()      # "<is_unreadable>:<complete>:<total>" per brood for the global aggregate

for manifest in "${manifests[@]}"; do
  # Brood-id segment = basename of the manifest's parent dir (the discover-validated brood-* dir).
  brood_id="$(basename "$(dirname "$manifest")")"

  # Invoke the PURE projector with INERT "$var" args — the structural splice closure.
  proj_rc=0
  proj_out="$(bash "$PROJECT_SCRIPT" "$manifest" "$root" 2>/dev/null)" || proj_rc=$?

  if [ "$proj_rc" -eq 2 ]; then
    # MANIFEST_UNREADABLE: detail is the manifest path from the sentinel line.
    detail="$(printf '%s\n' "$proj_out" | awk -F'\t' '/^MANIFEST_UNREADABLE\t/ { print $2; exit }')"
    brood_objects+=( "$(jq -n --arg id "$brood_id" --arg detail "$detail" \
      '{brood_id:$id, status:"unreadable", detail:$detail, strains:[],
        summary:{complete:0, running:0, blocked_failed:0, total:0}}')" )
    global_records+=( "1:0:0" )
    continue
  fi

  if [ "$proj_rc" -ne 0 ]; then
    # Other nonzero: pre-flight blocker. The projector wrote the blocker to stderr (discarded by
    # the run above); capture a generic blocker detail rather than re-running the projector.
    blocker_err=0
    detail="$(bash "$PROJECT_SCRIPT" "$manifest" "$root" 2>&1 >/dev/null)" || blocker_err=$?
    brood_objects+=( "$(jq -n --arg id "$brood_id" --arg detail "$detail" \
      '{brood_id:$id, status:"blocker", detail:$detail, strains:[],
        summary:{complete:0, running:0, blocked_failed:0, total:0}}')" )
    global_records+=( "1:0:0" )
    continue
  fi

  # Exit 0: the projection succeeded (including the VALID-empty `{"strains":[]}` -> zero STRAIN
  # lines case). Before any per-strain work, assert BROOD-ID INTEGRITY independently of the strain
  # rows.
  #
  # BROOD-ID INTEGRITY (manifest-level, strain-count-independent): the discovered directory name
  # (brood_id, a discover-validated brood-* segment) and the manifest's TOP-LEVEL brood_id are two
  # ground-truth identities that MUST agree. If they disagree — a manifest copied into the wrong
  # brood dir, or a tampered/absent/malformed top-level brood_id — the brood is unattributable and
  # must NOT be rendered as a normal brood under the directory id (which would mask the corruption).
  # We read the top-level brood_id DIRECTLY here (inert jq DATA read, never command source) rather
  # than inferring it from STRAIN rows, because the projector emits ZERO STRAIN lines for a valid
  # empty manifest — a strain-row-only check would let an empty manifest copied into the wrong dir,
  # or carrying a missing/malformed top-level brood_id, slip through as a normal `empty` brood. The
  # read mirrors the projector's own validation: a control-bearing value is rejected (-> empty ->
  # mismatch), and the value must match the directory id exactly (which is already ^brood-[0-9a-f-]+$
  # shaped by discovery), so absent/tampered/malformed all resolve to "!= brood_id" -> mismatch.
  manifest_brood_id="$(jq -r '(.brood_id // "") | select((tostring | test("[[:cntrl:]]")) | not) // ""' "$manifest" 2>/dev/null || true)"
  if [ "$manifest_brood_id" != "$brood_id" ]; then
    brood_objects+=( "$(jq -n --arg id "$brood_id" --arg got "$manifest_brood_id" \
      '{brood_id:$id, status:"blocker",
        detail:("manifest brood_id mismatch: directory \($id) but manifest top-level brood_id is \(if $got=="" then "absent/malformed" else $got end)"),
        strains:[], summary:{complete:0, running:0, blocked_failed:0, total:0}}')" )
    global_records+=( "1:0:0" )
    continue
  fi

  # Brood-id integrity holds. Parse STRAIN lines. Zero strains -> empty brood.
  strain_objects=()
  buckets=()
  while IFS="$TAB" read -r sentinel f_brood f_name f_wt f_branch f_tmux f_status f_state f_run f_live_branch; do
    [ "$sentinel" = "STRAIN" ] || continue
    # Probe observables using the projector-validated tokens (inert "$var").
    session_alive="$(probe_session_alive "$f_tmux")"
    # PR probe keys on the git GROUND-TRUTH live branch of the selected worktree (f_live_branch,
    # field 10), NOT the display-only manifest `branch` (f_branch). A brood child opens its PR from
    # the DERIVED branch it switched onto, so the stale manifest scratch ref would find no PR (#270).
    pr_pair="$(probe_pr "$f_live_branch")"
    pr_state="${pr_pair%%$TAB*}"
    pr_number="${pr_pair#*$TAB}"

    # f_state (state.current) and f_run (run.status) are the child-ledger started-evidence tokens
    # already projected at the loop head. Threaded inert ("$var") into derivation: an
    # alive session with no started-evidence (MISSING/MALFORMED state.current) demotes to `starting`
    # rather than masking as `running`. A legacy manifest with no ledger pointer projects
    # NO_LEDGER_POINTER, for which the started-evidence gate does not apply (observable status is
    # kept). No new probe, no new I/O.
    derived="$(hivemind_derive_strain_status "$f_status" "$session_alive" "$pr_state" "$pr_number" "$f_state" "$f_run")"
    buckets+=( "$(hivemind_classify_status_bucket "$derived")" )

    session_word="dead"; [ "$session_alive" -eq 1 ] && session_word="alive"
    # pr.number is a JSON integer (or null); build via --argjson with a numeric-or-null guard.
    if printf '%s' "$pr_number" | grep -qE '^[0-9]+$'; then
      pr_num_json="$pr_number"
    else
      pr_num_json="null"
    fi

    # The display object's `branch` shows the manifest branch (f_branch — the spawn-time context
    # ref), while the PR probe above keys on the git-ground-truth live branch (f_live_branch). This
    # divergence is INTENTIONAL: the dashboard surfaces the manifest's recorded branch for context,
    # but the probe must follow the worktree's actual HEAD to find the child's derived-branch PR.
    strain_objects+=( "$(jq -n \
      --arg name "$f_name" \
      --arg branch "$f_branch" \
      --arg session "$session_word" \
      --arg tmux_session "$f_tmux" \
      --argjson number "$pr_num_json" \
      --arg state "$pr_state" \
      --arg wstate "$f_state" \
      --arg run "$f_run" \
      --arg derived "$derived" \
      '{name:$name, branch:$branch, session:$session, tmux_session:$tmux_session,
        pr:{number:$number, state:$state},
        workflow_state:$wstate, run_status:$run, derived_status:$derived}')" )
  done <<< "$proj_out"

  # Per-brood summary via the pure aggregator.
  read -r b_complete b_running b_blocked b_total \
    <<< "$(hivemind_aggregate_brood_summary "${buckets[@]+"${buckets[@]}"}")"

  if [ "$b_total" -eq 0 ]; then
    brood_status="empty"
  else
    brood_status="ok"
  fi

  # Assemble the brood object. The strain array is folded with jq -s over the per-strain objects.
  if [ "${#strain_objects[@]}" -eq 0 ]; then
    strains_json="[]"
  else
    strains_json="$(printf '%s\n' "${strain_objects[@]}" | jq -s '.')"
  fi
  brood_objects+=( "$(jq -n \
    --arg id "$brood_id" \
    --arg status "$brood_status" \
    --argjson strains "$strains_json" \
    --argjson complete "$b_complete" \
    --argjson running "$b_running" \
    --argjson blocked "$b_blocked" \
    --argjson total "$b_total" \
    '{brood_id:$id, status:$status, detail:null, strains:$strains,
      summary:{complete:$complete, running:$running, blocked_failed:$blocked, total:$total}}')" )
  global_records+=( "0:$b_complete:$b_total" )
done

# ── Global aggregate (pure) ───────────────────────────────────────────────────────
read -r g_broods g_unreadable g_complete g_strains \
  <<< "$(hivemind_aggregate_global "${global_records[@]+"${global_records[@]}"}")"

# ── Emit the single JSON document (built entirely with jq) ────────────────────────
if [ "${#brood_objects[@]}" -eq 0 ]; then
  broods_json="[]"
else
  broods_json="$(printf '%s\n' "${brood_objects[@]}" | jq -s '.')"
fi

jq -n \
  --argjson broods "$broods_json" \
  --argjson total_broods "$g_broods" \
  --argjson unreadable "$g_unreadable" \
  --argjson complete "$g_complete" \
  --argjson total_strains "$g_strains" \
  '{schema:"brood-status-collect/1",
    broods:$broods,
    global:{total_broods:$total_broods, unreadable:$unreadable,
            complete:$complete, total_strains:$total_strains}}'
