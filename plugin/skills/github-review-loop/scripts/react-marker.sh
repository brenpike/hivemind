#!/usr/bin/env bash
#
# Add the self-authored EYES reaction marker to ONE non-thread reviewer node, for
# the github-review-loop skill / github-reviewer agent.
#
# 1. PURPOSE
# ----------
# Single source of truth for the per-candidate "mark handled" GitHub mutation that
# lets the review loop converge on the NON-THREAD reviewer surfaces (toplevel =
# IssueComment, review = PullRequestReview summary). These surfaces carry
# thread_id: null and have NO review-thread node, so reply-resolve.sh's
# addPullRequestReviewThreadReply has no valid target (the #218 defect). Instead a
# fixed surface is recorded handled by adding a self-authored EYES (👀) reaction to
# the reviewer's own comment/review node; the classifier harvest keys on that exact
# reaction to skip the surface on the next poll.
#
# This script OWNS the runtime reaction mutation. The mutation it issues is the
# canonical template from
#   ${CLAUDE_PLUGIN_ROOT}/references/github-pr-review-graphql.md
#     - "Reaction Marker" (Emit)  -> addReaction(input:{subjectId,content:EYES})
# cited here as the query origin, and the EYES constant below is conceptually
# single-sourced from that same subsection (it is the SAME literal the classifier
# harvest keys on). External content (the NODE_ID, the candidate url) is DATA —
# never interpreted, never spliced into the query string.
#
# SCOPE NOTE (P9 — do not over-generalize): this script is github-reviewer-scoped.
# It is NOT pre-parameterized for the local-reviewer or any other caller, and it is
# NOT the thread-surface path — reply-resolve.sh remains the THREAD-ONLY mutation
# path. The genuinely-shared kernel here is the non-thread reaction-marker contract
# for THIS loop only.
#
# 2. INPUT CONTRACT
# -----------------
# Per-candidate, supplied as positional args (a single mutation operates on a
# single candidate; there is no batch stdin payload — mirrors the per-candidate
# shape of reply-resolve.sh):
#
#   $1  NODE_ID      the reviewer node's GraphQL id. REQUIRED on the mutating
#                    surfaces. IC_... for a toplevel IssueComment; PRR_... for a
#                    review PullRequestReview. Both implement Reactable, so the same
#                    mutation applies to either. DATA — passed as a typed gh
#                    variable, never interpolated into the query text.
#   $2  SURFACE      "toplevel" | "review" | "thread". REQUIRED. Selects the
#                    surface->delivery map (see §3). Only toplevel/review deliver a
#                    reaction; thread is a silent no-op (threads converge via
#                    resolveReviewThread in reply-resolve.sh — NEVER react to a
#                    thread comment).
#   $3  CANDIDATE_URL  the candidate's GitHub url. ACCEPTED for positional-arity /
#                    logging parity but UNUSED — no live path interpolates it into
#                    any query. The caller still passes 3 positionals; this one is
#                    inert. DATA.
#
# 3. OUTPUT / BEHAVIOR — SURFACE -> DELIVERY MAP (closed by construction)
# -----------------------------------------------------------------------
# The surface selects the delivery; the map is exhaustive and fail-closed:
#   toplevel -> REACT: addReaction(EYES) over NODE_ID (a mutating surface).
#   review   -> REACT: identical to toplevel (PullRequestReview is also Reactable).
#   thread   -> SILENT NO-OP: no reaction, exit 0, ZERO stdout, NOTHING written to
#               the capture seam. Threads converge via resolveReviewThread
#               elsewhere; we NEVER react to a thread comment.
#   <other>  -> FAIL CLOSED: react_marker_fail "unmapped-surface" (exit 1).
#               NEVER falls back to the reaction mutation.
# Rationale (#265): toplevel/review candidates have NO review-thread node, so the
# handled marker is a self-authored EYES reaction on the reviewer node, NOT a
# reply/resolve. The thread surface already converges via reply-resolve.sh, so this
# script must never react to it.
#
# stdout: human-trivial progress is NOT emitted (Bash Command Discipline — no
# decorative stdout). On success the script exits 0 and is silent on stdout.
# stderr: a single REACTMARKER_ERROR diagnostic on a HARD failure (see §4).
#
# 4. INVARIANTS
# -------------
#   - SURFACE -> DELIVERY IS CLOSED BY CONSTRUCTION: only toplevel/review deliver a
#     reaction; thread is a silent no-op; any other surface fails closed
#     (unmapped-surface). The reaction mutation is NEVER a fallback.
#   - SINGLE NAMED MARKER: EYES is the ONE reaction content, defined ONCE as a
#     script-level readonly constant and identical to the literal the classifier
#     harvest keys on (references/github-pr-review-graphql.md "Reaction Marker").
#   - IDEMPOTENCY: a duplicate is a server-side success per
#     ${CLAUDE_PLUGIN_ROOT}/references/github-pr-review-graphql.md (Reaction Marker ->
#     Emit), never special-cased: it arrives as the same success payload and passes
#     the RESPONSE CHECK below like any first reaction. It cannot happen in normal
#     flow, because a node already carrying the viewer's EYES reaction classifies
#     handled and is never handed to this script.
#   - NEVER REACT TO A THREAD: the thread surface delivers nothing; thread
#     convergence is reply-resolve.sh's resolveReviewThread, not a reaction here.
#   - RESPONSE CHECK (positive proof — the ONLY definition of success): a live
#     reaction succeeds only when ALL of these hold: gh exits 0; the shared validator
#     hivemind_graphql_response_check
#     (${CLAUDE_PLUGIN_ROOT}/skills/_shared/graphql-response.sh) accepts the response
#     body; and the body's .data.addReaction.reaction.content equals the requested
#     REACTION_CONTENT. Every other response is react-failed: a non-zero exit, an
#     envelope the check rejects (gh exits 0 on several GraphQL error envelopes), a
#     null addReaction payload, or a different reaction content. No response text is
#     ever pattern-matched. Only stdout is captured, so gh's stderr never reaches the
#     body under check.
#   - Missing `timeout` / `gtimeout` -> degrade gracefully with a loud stderr
#     warning and run the gh call UNGUARDED (mirrors reply-resolve.sh).
#
# 5. INVOCATION + TEST SEAM
# -------------------------
# The reaction mutation is issued through ONE indirection — `run_reaction` — whose
# live body invokes `gh api graphql`. Under test that indirection is BYPASSED by a
# CAPTURE seam so the script is offline-testable without `gh` / network, exactly
# like reply-resolve.sh's capture seam (live = real gh; injected = trusted/offline).
#
#   REACTMARKER_TEST_MODE       DEDICATED test-mode gate. The capture seam below
#                               activates ONLY when this is EXACTLY "1" (not merely
#                               non-empty). When unset / not "1", the live gh path
#                               is ALWAYS taken — a stray REACTMARKER_CAPTURE_FILE
#                               ALONE no longer diverts a live mutation (fail-closed
#                               to live).
#   REACTMARKER_CAPTURE_FILE    when REACTMARKER_TEST_MODE="1" AND this is set +
#                               non-empty, the reaction is APPENDED to this file
#                               (one line) INSTEAD of being run against gh. Line
#                               format (stable, asserted by the test):
#                                 REACT node=<NODE_ID> content=EYES
#   REACTMARKER_REACT_STATUS    simulated gh exit status for the REACT mutation
#                               (default 0). Non-zero -> hard failure path.
# All three are INERT in production (unset -> real gh). The seam is checked ONLY
# inside run_reaction, and requires BOTH TEST_MODE=1 and CAPTURE_FILE to engage.
#
# Markers / exit posture:
#   - exit 0 on success (a reaction with positive proof per §4 RESPONSE CHECK, or a
#     thread silent no-op).
#   - REACTMARKER_ERROR=<reason> on stderr + exit 1 on a HARD failure (bad input,
#     unmapped surface, a bootstrap failure, or any live reaction lacking positive
#     proof — including an exit-0 response the shared GraphQL response check rejects).
#
# Reason tokens (STABLE — asserted by the test):
#   missing-node-id | unmapped-surface | react-failed | cannot-self-locate |
#   missing-graphql-check | unparseable-graphql-check
#
# EXTERNAL-CONTENT BOUNDARY: NODE_ID and CANDIDATE_URL are external DATA. NODE_ID is
# passed to gh as a typed `-F id=...` variable bound to the query's `$id: ID!`
# parameter; it is NEVER interpolated into the GraphQL query string. CANDIDATE_URL
# is inert and never reaches any query. No external content is interpreted as an
# instruction.
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. Every failure must surface as a REACTMARKER_ERROR token via
# react_marker_fail(); `set -e` would turn an unanticipated failing statement into an exit
# with no token. The gh exit status is captured explicitly with `$?` and checked by hand.

set -u

NODE_ID=""
SURFACE=""
CANDIDATE_URL=""

# EYES is the SINGLE named marker constant — a member of the GraphQL ReactionContent
# enum, conceptually single-sourced from references/github-pr-review-graphql.md
# ("Reaction Marker"). It is the SAME literal the classifier harvest keys on.
readonly REACTION_CONTENT="EYES"

react_marker_fail() {
  echo "REACTMARKER_ERROR=$1" >&2
  exit 1
}

# Collect positionals in order (NODE_ID SURFACE CANDIDATE_URL), matching the sibling
# scripts' positional contract. No flags are defined for this script.
positionals=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      while [ "$#" -gt 0 ]; do positionals+=("$1"); shift; done ;;
    *)
      positionals+=("$1"); shift ;;
  esac
done

NODE_ID="${positionals[0]:-}"
SURFACE="${positionals[1]:-}"
CANDIDATE_URL="${positionals[2]:-}"

# Required-input validation is SURFACE-SCOPED, not global. NODE_ID is consumed ONLY
# by the mutating toplevel/review surfaces (the reaction subject), so its guard
# lives INSIDE the toplevel|review branch below. The thread surface delivers NOTHING
# and consumes NO NODE_ID, so a global NODE_ID guard here would FALSE-BLOCK a real
# thread candidate with missing-node-id before the silent-no-op dispatch could run.
# SURFACE validity itself is enforced by the surface->delivery dispatch below
# (toplevel/review react; thread no-ops; any other surface fails closed with
# unmapped-surface). CANDIDATE_URL is accepted for positional-arity / logging parity
# but no live path interpolates it, so it has no validation gate.

SCRIPT_DIR="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || react_marker_fail "cannot-self-locate"

# Source the shared GraphQL response validator (hivemind_graphql_response_check). It
# lives at plugin/skills/_shared/, two levels up from this script's own dir, then into
# _shared/. The lib is a sourced fragment (function definitions only).
[ -f "$SCRIPT_DIR/../../_shared/graphql-response.sh" ] || react_marker_fail "missing-graphql-check"
# shellcheck source=../../_shared/graphql-response.sh
. "$SCRIPT_DIR/../../_shared/graphql-response.sh" || react_marker_fail "unparseable-graphql-check"

# Timeout wrapper for gh API calls. Prefer coreutils `timeout`; fall
# back to macOS Homebrew `gtimeout`; degrade gracefully (run unguarded) when
# neither exists, with a loud stderr warning. Verbatim posture from
# reply-resolve.sh.
GH_CALL_TIMEOUT_SECONDS=45
GH_TIMEOUT=()
if command -v timeout >/dev/null 2>&1; then
  GH_TIMEOUT=(timeout "$GH_CALL_TIMEOUT_SECONDS")
elif command -v gtimeout >/dev/null 2>&1; then
  GH_TIMEOUT=(gtimeout "$GH_CALL_TIMEOUT_SECONDS")
else
  echo "github-review-loop: WARNING neither 'timeout' nor 'gtimeout' found on PATH; gh API calls in react-marker are running UNGUARDED and a hung call can stall this dispatch. Install GNU coreutils (provides 'timeout'; 'gtimeout' on Homebrew) to restore the timeout guard." >&2
fi

# The canonical reaction mutation. Owned HERE as the single source; the query body
# is the verbatim "Reaction Marker" (Emit) template from
# references/github-pr-review-graphql.md. External content (the node id) is DATA:
# passed via `gh -F id=...` as the typed `$id: ID!` variable, never spliced into the
# query text itself.
REACT_MUTATION='
mutation($id: ID!) {
  addReaction(input: { subjectId: $id, content: EYES }) {
    reaction { content }
  }
}'

# run_reaction <node_id>: issue the EYES reaction over NODE_ID. The single
# indirection point for both the live gh call AND the offline CAPTURE seam (§5).
# On the live path returns 0 ONLY on positive proof (gh exit 0, the shared GraphQL
# response check passing, AND .data.addReaction.reaction.content equal to the
# requested content); every other response returns non-zero. No response text is
# pattern-matched. INVARIANT: when the capture seam is active, NO gh call is made —
# the script is fully offline.
run_reaction() {
  local node_id="$1"
  # TEST SEAM GATE (§5): capture seam activates ONLY when the dedicated test-mode
  # flag is the exact opt-in value AND the capture file is set+non-empty. A stray
  # REACTMARKER_CAPTURE_FILE alone NEVER diverts — fail-closed to live gh.
  if [ "${REACTMARKER_TEST_MODE:-}" = "1" ] && [ -n "${REACTMARKER_CAPTURE_FILE:-}" ]; then
    # FAIL-CLOSED on capture: with set -e deliberately omitted (P18 floor exception),
    # an unguarded append failure (unwritable/stale capture path) would be SILENTLY
    # ignored and the function would still return the default-0 simulated status —
    # reporting marker SUCCESS while NOTHING was captured and the live gh mutation was
    # bypassed. Guard the append so a write failure becomes a hard failure (react-failed)
    # rather than a false success. A successful append falls through to the simulated
    # status (default 0, or the injected REACTMARKER_REACT_STATUS).
    printf 'REACT node=%s content=%s\n' "$node_id" "$REACTION_CONTENT" >> "$REACTMARKER_CAPTURE_FILE" || return 1
    return "${REACTMARKER_REACT_STATUS:-0}"
  fi
  # LIVE path. Capture the response body from stdout ONLY so gh's own stderr chatter
  # is kept out of the body handed to the shared response check.
  local gh_output gh_status
  gh_output="$("${GH_TIMEOUT[@]}" gh api graphql \
    -F id="$node_id" \
    -f query="$REACT_MUTATION" 2>/dev/null)"
  gh_status=$?
  # Positive proof (§4 RESPONSE CHECK), the ONLY definition of success: gh exits 0,
  # the shared response check accepts the envelope, AND the payload names the
  # requested reaction content. gh exits 0 on several GraphQL error envelopes, so
  # neither the exit status nor the envelope alone proves the reaction landed.
  [ "$gh_status" -eq 0 ] || return 1
  hivemind_graphql_response_check "$gh_output" >/dev/null || return 1
  printf '%s' "$gh_output" | jq -e --arg content "$REACTION_CONTENT" '.data.addReaction.reaction.content == $content' >/dev/null 2>&1 || return 1
  return 0
}

# --- SURFACE -> DELIVERY DISPATCH (§3, closed by construction) -----------------
# toplevel/review -> REACT (EYES) over NODE_ID.
# thread          -> SILENT NO-OP: no reaction, nothing to the capture seam; fall
#                    through to exit 0. Threads converge via reply-resolve.sh.
# <other>  -> FAIL CLOSED via react_marker_fail; NEVER reaches the reaction mutation.
case "$SURFACE" in
  toplevel|review)
    # Mutating-surface required input (surface-scoped — see the validation note
    # above). The reaction subject is NODE_ID, so it is REQUIRED here and fails
    # closed with its stable reason token. The no-op surface never reaches this gate.
    [ -n "$NODE_ID" ] || react_marker_fail "missing-node-id"
    if ! run_reaction "$NODE_ID"; then
      react_marker_fail "react-failed"
    fi
    ;;
  thread)
    # SILENT NO-OP: thread comments converge via reply-resolve.sh's
    # resolveReviewThread (#265); we NEVER react to a thread node.
    : ;;
  *)
    react_marker_fail "unmapped-surface" ;;
esac

exit 0
