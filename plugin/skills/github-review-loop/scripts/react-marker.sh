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
#   - IDEMPOTENCY: addReaction against a node the authenticated viewer has ALREADY
#     reacted to with EYES is a server-side no-op / success. The live path treats an
#     "already reacted" response as SUCCESS without erroring — duplicate re-marking
#     never fails the candidate. A clean success passes through unchanged.
#   - NEVER REACT TO A THREAD: the thread surface delivers nothing; thread
#     convergence is reply-resolve.sh's resolveReviewThread, not a reaction here.
#   - RESPONSE CHECK: a live reaction succeeds only when gh exits 0 AND the shared
#     validator hivemind_graphql_response_check
#     (${CLAUDE_PLUGIN_ROOT}/skills/_shared/graphql-response.sh) accepts the response
#     body. gh exits 0 on several GraphQL error envelopes (a top-level `errors`
#     value), so an exit-0 response the check rejects is NOT success: it falls to the
#     idempotency test over stdout and otherwise fails react-failed. Only stdout is
#     captured — gh copies the response body there even on a non-zero exit.
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
#   - exit 0 on success (reaction added, or already-present duplicate tolerated, or
#     a thread silent no-op).
#   - REACTMARKER_ERROR=<reason> on stderr + exit 1 on a HARD failure (bad input,
#     unmapped surface, a bootstrap failure, or a non-idempotent failed reaction —
#     including an exit-0 response the shared GraphQL response check rejects).
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
# are DELIBERATELY omitted. The full floor would change behavior: the reaction mutation is
# IDEMPOTENCY-TOLERANT (an "already reacted" gh response is treated as success), so `set -e`
# would abort on a deliberately-tolerated duplicate-reaction status; hard failures route
# through react_marker_fail().

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
# Returns 0 on success (gh exit 0 AND the shared GraphQL response check passing),
# including the idempotent "already reacted" case; returns non-zero only on a
# genuine non-idempotent failure. INVARIANT: when the capture
# seam is active, NO gh call is made — the script is fully offline.
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
  # LIVE path. Capture the response body from stdout ONLY: gh copies the GraphQL
  # response body to stdout even when it exits non-zero, so an "already reacted"
  # error stays detectable there (idempotency invariant, §4) while gh's own stderr
  # chatter is kept out of the body handed to the shared response check.
  local gh_output gh_status
  gh_output="$("${GH_TIMEOUT[@]}" gh api graphql \
    -F id="$node_id" \
    -f query="$REACT_MUTATION" 2>/dev/null)"
  gh_status=$?
  # Success requires BOTH a zero gh exit AND a passing shared response check: gh
  # exits 0 on several GraphQL error envelopes, so the exit status alone is not
  # proof the reaction landed.
  if [ "$gh_status" -eq 0 ] && hivemind_graphql_response_check "$gh_output" >/dev/null; then
    return 0
  fi
  # Idempotency tolerance: a response whose body names an already-existing
  # reaction is a server-side no-op for our purposes — treat it as success. Any
  # other failure (non-zero exit, or exit 0 with a rejected response) is a genuine
  # react-failed.
  if printf '%s' "$gh_output" | grep -qi 'already.*reacted\|reaction.*already\|already exists'; then
    return 0
  fi
  return 1
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
