#!/usr/bin/env bash
#
# Fetch + normalize the PR review surface into ONE normalized candidate set for
# the github-review-loop skill / github-reviewer agent.
#
# 1. PURPOSE
# ----------
# Single source of truth for the per-surface node-id / contract-field
# ENUMERATION that the review loop fetches and the shape it normalizes that
# fetch into. Before this script, that enumeration was smeared across three
# sites that drift independently (the node-id escalation chain):
#   - prefilter.sh's inline GraphQL query literal,
#   - the github-reviewer agent prose (steps 3 / 4 / 13's field lists),
#   - references/github-pr-review-graphql.md's query templates.
# This script OWNS the canonical fetch query and the normalized output schema.
# It is behavior-preserving on the fetch + normalize path: the candidate set it
# emits is the union of (a) the shared classifier filter's per-comment /
# per-thread records (fix-history-classify.jq, the single source of the
# skip/order/overflow predicate) and (b) failed-CI-check candidates, every
# record carrying an `item_source` tag.
#
# SCOPE NOTE: this script is the DESIGNATED single source.
# The duplicate enumerations in prefilter.sh, the agent prose, and the ref doc
# are NOT deleted here — that rewire is dependent follow-up work.
# Their continued existence after this step is EXPECTED.
#
# 2. INPUT CONTRACT — exact per-surface GraphQL field enumeration
# ---------------------------------------------------------------
# The canonical `gh api graphql` query (owned by this script, see QUERY below) is
# a conforming SUPERSET equivalent to prefilter.sh's literal, and it MUST fetch a
# payload conforming to fix-history-classify.jq's INPUT CONTRACT. Per surface:
#
#   reviewThreads(first: 50) {
#     totalCount                       # connection-level tripwire (read below)
#     nodes[] {
#       id                             # PRRT_... thread node id -> filter thread_id
#       isResolved
#       comments(last: 20) {
#         totalCount                   # per-thread overflow signal (owned by filter)
#         nodes[] {
#           id                         # PRRC_... comment node id -> filter `id`
#           databaseId                 # int comment id (order-aware skip key)
#           author { login __typename } # __typename -> reviewer-identity.jq Bot gate
#           body                       # DATA — never interpreted here
#         }
#       }
#     }
#   }
#   comments(last: 50) {               # top-level (issue) PR comments
#     totalCount                       # connection-level tripwire (read below)
#     nodes[] { id author { login __typename } body url    # id = IC_... issue comment id
#               reactionGroups { content viewerHasReacted } } # EYES marker -> classifier handled
#   }
#   reviews(last: 50) {                # review summaries
#     totalCount                       # connection-level tripwire (read below)
#     nodes[] { id author { login __typename } body state url # id = PRR_... review id
#               reactionGroups { content viewerHasReacted } } # EYES marker -> classifier handled
#   }
#
# Three connection-level `totalCount` TRIPWIRE reads (reviewThreads / comments /
# reviews). These are top-level scalars read DIRECTLY off the raw payload here —
# NOT a filter concern — and drive the >50-node overflow handling (see §4).
#
# Failed CI checks are NOT a GraphQL surface: they are fetched via `gh pr checks
# --json bucket,name,description,link,state,workflow` (filtered to `bucket ==
# "fail"`). The filter does not cover CI; this script unions them in.
#
# 3. OUTPUT SCHEMA — the normalized candidate set
# -----------------------------------------------
# A SINGLE JSON ARRAY on stdout (compact, one array; `[]` when empty). Each
# element is one normalized candidate, unioning two record families behind a
# common `item_source` discriminator:
#
#   Review-surface records (item_source: "review") — the fix-history-classify.jq
#   per-comment / per-thread output object, passed through VERBATIM with
#   `item_source` added. Shape (see fix-history-classify.jq §3 for the authority):
#     {
#       "item_source":     "review",
#       "surface":         "thread" | "toplevel" | "review",
#       "thread_resolved": bool,
#       "thread_overflow": bool,
#       "thread_id":       <string>|null,   # PRRT_... (thread surface) else null
#       "id":              <string>|null,    # PRRC_/IC_/PRR_ node id; null ONLY
#                                            #   for the thread-overflow sentinel
#       "databaseId":      <int>|null,       # null off-thread + for the sentinel
#       "url":             <string>|null,    # null on thread surface
#       "classification":  "handled" | "actionable" | "followup-after-fix"
#     }
#
#   CI-check-failure records (item_source: "ci-check-failure") — one per failed
#   check. NO GraphQL node id (CI checks are not review nodes):
#     {
#       "item_source": "ci-check-failure",
#       "id":          null,                 # CI candidates carry NO node id
#       "name":        <string>,             # check name
#       "description": <string>,             # used as the candidate body
#       "link":        <string>|null,        # check details url
#       "state":       <string>,             # raw gh state (e.g. FAILURE)
#       "workflow":    <string>|null
#     }
#
# Consumers project this set exactly as today: review records by `classification`
# (actionable / followup-after-fix -> candidate; handled -> skip; the
# databaseId-null thread-surface record is the overflow SENTINEL -> thread-level
# inspection); ci-check-failure records -> fix candidates with `description` as
# body. This script does NOT collapse to a SKIP/DISPATCH decision — that
# projection stays with each consumer (prefilter keeps its binary collapse).
#
# 4. BEHAVIOR-PRESERVING INVARIANTS
# ---------------------------------
#   - FAIL-OPEN on a malformed / empty / unparseable INJECTED payload: the
#     normalize core emits an empty candidate set (`[]`) rather than erroring, so
#     a consumer treats a broken INJECTED fixture as "nothing classified" exactly
#     as the filter's empty-stream behavior. Injected payloads (--payload-file /
#     --ci-payload-file / read_payload_source) are TRUSTED content and are NOT
#     routed through the live-response gate (see validate_live_response, §5) — the
#     fail-OPEN-on-CONTENT guarantee for injected fixtures is UNCHANGED. The three
#     downstream jq pipelines (overflow-read, review pipeline, CI pipeline) swallow
#     malformed content to empty — this is the INTENTIONAL fail-open-on-CONTENT
#     behavior for trusted/already-gated payloads, not unguarded live boundaries.
#   - FAIL-CLOSED on a LIVE-response operational failure (§5 validate_live_response):
#     a live `gh` response that returns exit 0 with a non-empty `.errors` array, a
#     null/absent `.data.repository.pullRequest`, an empty body, or a REQUESTED
#     connection that is absent / null / has a null `nodes` (the connection-shape
#     assertion — covering the three top-level connections AND the nested
#     per-thread `reviewThreads.nodes[].comments`, so a parseable response that
#     silently lost its nodes can no longer masquerade as a clean PR) — OR a live
#     `gh pr checks` response at ANY allowlisted status (0, 1, 8) whose stdout is
#     NOT a JSON array, or a non-allowlisted status — fails CLOSED (non-zero + a
#     stable FETCHNORM_ERROR reason). All three allowlisted CI statuses share ONE
#     uniform `type=="array"` parse (iter-3 closure — no per-status carve-out may
#     skip the check). RS-001 closed the EXIT boundary; RS2-001 + iter-3 close the
#     CONTENT boundary: an operational failure must never masquerade as "zero
#     candidates".
#   - >50-node connection overflow is NOT silently dropped. The three
#     connection-level totalCounts are emitted on stderr as a diagnostic
#     OVERFLOW notice AND surfaced to the caller via the trailing exit/marker
#     posture (see §5). This script does NOT itself decide DISPATCH — it
#     preserves the raw signal so the consumer's existing >50 fail-open logic
#     (prefilter's bash tripwire) stays the authority. The overflow read mirrors
#     prefilter.sh: each totalCount defaults to 0 when absent.
#   - Thread-overflow SENTINEL pass-through: the filter's databaseId-null,
#     thread_id-non-null thread-surface record is passed through UNTOUCHED (only
#     `item_source` is added). It is never collapsed, deduped, or reinterpreted.
#   - CI candidates carry NO node id (`id: null`) — they are not review nodes and
#     must never be routed to a `node(id:)` body refetch.
#   - Missing `timeout` / `gtimeout` -> degrade gracefully with a loud stderr
#     warning and run the gh calls UNGUARDED (mirrors prefilter.sh).
#
# 5. INVOCATION + TEST SEAM
# -------------------------
# Pure normalization core over an INJECTED raw payload, with the live fetch as a
# thin outer shell that is BYPASSED under test (designed for offline fixtures
# exactly like test_fix_history_classify.sh). Positional + flag args:
#
#   $1  OWNER             base-repo owner            (required for LIVE fetch)
#   $2  REPO              base-repo name             (required for LIVE fetch)
#   $3  PR_NUMBER         integer PR number          (required for LIVE fetch)
#   $4  REVIEWER_FILTER   "automated" | "codex-only" | "all" | "<login>" (default automated)
#   $5  SELF_LOGIN        viewer login               (required — self strip)
#
#   --payload-file <path>     read the raw GraphQL JSON from <path> instead of
#                             running the live `gh api graphql` fetch. Use `-`
#                             for stdin. BYPASSES the live GraphQL fetch.
#   --ci-payload-file <path>  read the raw `gh pr checks --json ...` JSON from
#                             <path> instead of running the live `gh pr checks`.
#                             Use `-` for stdin. BYPASSES the live CI fetch.
#                             Absent under --payload-file -> NO CI candidates
#                             (offline review-only fixture).
#
#   When --payload-file is supplied the GraphQL fetch is skipped and
#   OWNER/REPO/PR_NUMBER are NOT required (the offline core only needs
#   SELF_LOGIN + REVIEWER_FILTER for the filter args). STEP-002 feeds canned
#   GraphQL fixtures through --payload-file (and optional canned CI JSON through
#   --ci-payload-file) and asserts the emitted normalized array.
#
# Markers / exit posture (mirrors prefilter.sh's fail-open):
#   - stdout: the single normalized JSON array (always, on success).
#   - exit 0 on success (including the fail-open empty-set case).
#   - FETCHNORM_ERROR=<reason> on stdout + exit 1 ONLY on a bootstrap or LIVE-fetch failure
#     (gh error, cannot-self-locate, missing/unparseable core/filter/identity module, bad input,
#     or a LIVE-RESPONSE failure caught by validate_live_response) — never on an empty or
#     malformed INJECTED payload (that is the fail-open empty-set path).
#   - OVERFLOW diagnostic emitted on stderr when any connection totalCount > 50.
#
# 5a. LIVE-RESPONSE GATE — validate_live_response (closed-by-construction)
# ------------------------------------------------------------------------
# ONE shared gate, invoked by BOTH fetch_graphql_payload and fetch_ci_payload
# over the RAW live response BEFORE the value crosses the command-substitution
# return boundary. This is the ONLY place live-response operational-failure
# detection lives — no per-helper duplicate — so a future live surface is
# structurally forced through the same gate. SCOPE: LIVE PATH ONLY. The injected
# --payload-file / --ci-payload-file / read_payload_source path is TRUSTED and is
# NEVER routed through this gate (forcing injected fixtures through it would break
# the fail-OPEN-on-CONTENT guarantee and the offline test suite). This is the
# explicit, deliberate divergence: live response = validated; injected = trusted.
#
# GraphQL mode (validate_live_response graphql <body> <status>):
#   - exit-0 with empty/whitespace body (no JSON)            -> graphql-empty-body
#   - non-empty `.errors` array (EVEN IF a pullRequest is also
#     present — `.errors` is the operational-failure signal)  -> graphql-errors
#   - null/absent `.data.repository.pullRequest` (covers
#     repo-not-found AND PR-not-found AND auth)               -> graphql-null-pullrequest
#   - a REQUESTED connection that is ABSENT, null, or whose `nodes` is null —
#     including the NESTED per-thread `reviewThreads.nodes[].comments` — fails
#     CLOSED                                                   -> graphql-missing-connection
#   - present pullRequest whose connections are all present but EMPTY
#     (`nodes: []`)                                            -> PASSES (valid empty;
#     downstream fail-open -> [] exit 0; do NOT over-reject valid-but-empty). The
#     per-thread clause is vacuously true on `reviewThreads.nodes: []`.
#   ORDER IS LOAD-BEARING: the connection-shape check runs LAST, so a null
#   pullRequest and an `.errors` response keep their own stable reason strings.
#
# CI mode (validate_live_response ci <body> <status>):
#   - status is an ALLOWLIST of the documented check-carrying exit states whose
#     stdout is the expected JSON array: 0 (all pass; [] or absent) and the
#     checks-failing/pending states 1 and 8. Allowlist, NOT a reject-list — an
#     unknown/new exit code fails CLOSED by default (closed-by-construction).
#   - ALL allowlisted statuses (0, 1, 8) share ONE uniform `type=="array"` parse
#     (iter-3 closure). No per-status carve-out may skip the check. A non-array
#     body at ANY allowlisted status (incl. 0) -> ci-not-array.
#   - any NON-allowlisted non-zero status (auth=4, cancelled=2, network, unknown)
#     -> ci-operational-failure (EVEN IF stdout happens to be a valid JSON array;
#     the prior shape-only `type=="array"` trust wrongly accepted auth-4 + []).
#   - status 0 with `[]` or a valid non-empty array               -> PASSES
#     ([] is a valid-but-empty all-pass result; do NOT over-reject it).
#   - The three jq pipelines downstream of this gate (overflow-read, review
#     pipeline, CI pipeline) swallow malformed content to empty — those are
#     INTENTIONAL fail-open-on-CONTENT behaviors, NOT unguarded live boundaries.
#     They operate on payload already cleared here (live) or on trusted injected
#     content (--payload-file/--ci-payload-file). See §4 fail-open invariant.
#
# Reason tokens (STABLE — asserted by RS2-002, documented above):
#   graphql-empty-body | graphql-errors | graphql-null-pullrequest
#   graphql-missing-connection
#   ci-not-array | ci-operational-failure
#
# 5b. LIVE-RESPONSE TEST SEAM (offline drive THROUGH the gate)
# ------------------------------------------------------------
# DISTINCT from --payload-file (which BYPASSES the live path + gate). These env
# seams inject a RAW live response + exit status that the LIVE helpers consume
# exactly as a real `gh` response, so validate_live_response runs over injected
# content identically to a real fetch. INERT in production (unset -> real gh):
#   FETCHNORM_TEST_MODE            DEDICATED test-mode gate. EITHER live seam below
#                                  activates ONLY when this is EXACTLY "1" (not
#                                  merely non-empty). When unset / not "1", the live
#                                  gh path is ALWAYS taken — a stray *_FILE var
#                                  ALONE no longer diverts a live fetch (fail-closed
#                                  to live).
#   FETCHNORM_LIVE_GRAPHQL_FILE    raw graphql response body file (`-` = stdin n/a here)
#   FETCHNORM_LIVE_GRAPHQL_STATUS  simulated gh exit status (default 0)
#   FETCHNORM_LIVE_CI_FILE         raw `gh pr checks` response body file
#   FETCHNORM_LIVE_CI_STATUS       simulated gh exit status (default 0)
# When FETCHNORM_TEST_MODE="1" AND the *_FILE var is set + non-empty, the helper
# reads that file as the live response and uses *_STATUS as the live exit code
# INSTEAD of invoking gh, then routes the result THROUGH validate_live_response. The
# *_STATUS vars are read ONLY inside that already-gated branch (no separate gate).
# An unreadable seam file is an input error (live-seam-file-not-found). The seams
# are checked ONLY inside the live helpers, which the --payload-file path never
# reaches.

# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: the fail-OPEN-on-CONTENT
# posture (§4) relies on jq pipelines swallowing malformed payloads to []; live failures route
# through fetchnorm_fail()/validate_live_response with explicit exit codes, and `$?` is captured
# after gh — `set -e`/`pipefail` would abort those guarded paths.
set -u
# INVARIANT: trap body ends with guaranteed-zero `:` so a failing rm never clobbers the
# script's own exit code under set -e (mirrors ADR-0020 thin-entrypoint convention).
# No temp files are created today; the trap is here for explicit hygiene so future
# additions cannot accidentally leak.
trap ':' EXIT

OWNER=""
REPO=""
PR_NUMBER=""
REVIEWER_FILTER=""
SELF_LOGIN=""
PAYLOAD_FILE=""
CI_PAYLOAD_FILE=""

fetchnorm_fail() {
  echo "FETCHNORM_ERROR=$1"
  exit 1
}

# Parse flags and collect positionals. Flags may appear anywhere; positionals
# bind in order (OWNER REPO PR_NUMBER REVIEWER_FILTER SELF_LOGIN), matching the
# sibling scripts' positional contract.
positionals=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --payload-file)
      [ "$#" -ge 2 ] || fetchnorm_fail "missing-value-for-payload-file"
      PAYLOAD_FILE="$2"; shift 2 ;;
    --payload-file=*)
      PAYLOAD_FILE="${1#--payload-file=}"
      # An empty inline value (`--payload-file=`) is the same input error as the
      # separated form with no value: reject rather than silently re-routing to
      # the live GraphQL path. (F3)
      [ -n "$PAYLOAD_FILE" ] || fetchnorm_fail "missing-value-for-payload-file"
      shift ;;
    --ci-payload-file)
      [ "$#" -ge 2 ] || fetchnorm_fail "missing-value-for-ci-payload-file"
      CI_PAYLOAD_FILE="$2"; shift 2 ;;
    --ci-payload-file=*)
      CI_PAYLOAD_FILE="${1#--ci-payload-file=}"
      [ -n "$CI_PAYLOAD_FILE" ] || fetchnorm_fail "missing-value-for-ci-payload-file"
      shift ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do positionals+=("$1"); shift; done ;;
    *)
      positionals+=("$1"); shift ;;
  esac
done

OWNER="${positionals[0]:-}"
REPO="${positionals[1]:-}"
PR_NUMBER="${positionals[2]:-}"
REVIEWER_FILTER="${positionals[3]:-}"
SELF_LOGIN="${positionals[4]:-}"

# REVIEWER_FILTER defaults to automated when empty; any non-empty string is
# accepted as a filter mode (automated | codex-only | all | <login>; semantics
# owned by reviewer-identity.jq §5). Mirrors prefilter.sh.
[ -n "$REVIEWER_FILTER" ] || REVIEWER_FILTER="automated"
# SELF_LOGIN is required on every path: without it the shared filter cannot strip
# self-authored comments and the self-echo storm re-emerges. Mirrors prefilter.
[ -n "$SELF_LOGIN" ] || fetchnorm_fail "missing-self-login"

# Resolve the shared classifier filter RELATIVE to this script's own location,
# matching prefilter.sh: this script runs as a sibling of fix-history-classify.jq
# so ${BASH_SOURCE[0]}'s dir is the correct resolution, NOT ${CLAUDE_PLUGIN_ROOT}.
SCRIPT_DIR="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || fetchnorm_fail "cannot-self-locate"
CLASSIFY_FILTER="$SCRIPT_DIR/fix-history-classify.jq"
[ -f "$CLASSIFY_FILTER" ] || fetchnorm_fail "missing-filter"
# INVARIANT: the classifier `include`s reviewer-identity.jq, resolved via
# `-L "$SCRIPT_DIR"`, so the module MUST be co-located with fix-history-classify.jq.
IDENTITY_MODULE="$SCRIPT_DIR/reviewer-identity.jq"
[ -f "$IDENTITY_MODULE" ] || fetchnorm_fail "missing-identity-module"
# INVARIANT: compile-probe the classifier BEFORE use. Null input yields no output
# and no runtime error, so a non-zero exit here is a compile failure (syntax error,
# missing or broken include). The normalize core swallows classifier stderr for
# fail-OPEN-on-CONTENT, so without this probe a compile failure would normalize
# silently to `[]` — indistinguishable from a clean PR.
jq -n -L "$SCRIPT_DIR" -f "$CLASSIFY_FILTER" --arg login x --arg filter automated \
  </dev/null >/dev/null 2>&1 || fetchnorm_fail "unparseable-filter"

# Source the shared PURE normalize core (emit_overflow_tripwire +
# build_normalized_candidate_set). It lives at plugin/skills/_shared/, which from
# this script's own dir (plugin/skills/github-review-loop/scripts/) is two levels
# up then into _shared/. VERIFIED path: ../../_shared/ (NOT ../_shared/). The lib
# is a sourced fragment (function definitions only; no top-level statements).
FETCHNORM_CORE="$SCRIPT_DIR/../../_shared/fetch-normalize-core.sh"
[ -f "$FETCHNORM_CORE" ] || fetchnorm_fail "missing-core"
# shellcheck source=../../_shared/fetch-normalize-core.sh
. "$FETCHNORM_CORE" || fetchnorm_fail "unparseable-core"

# Timeout wrapper for gh API calls. Prefer coreutils `timeout`;
# fall back to macOS Homebrew `gtimeout`; degrade gracefully (run unguarded) when
# neither exists, with a loud stderr warning. Verbatim posture from prefilter.sh.
GH_CALL_TIMEOUT_SECONDS=45
GH_TIMEOUT=()
if command -v timeout >/dev/null 2>&1; then
  GH_TIMEOUT=(timeout "$GH_CALL_TIMEOUT_SECONDS")
elif command -v gtimeout >/dev/null 2>&1; then
  GH_TIMEOUT=(gtimeout "$GH_CALL_TIMEOUT_SECONDS")
else
  echo "github-review-loop: WARNING neither 'timeout' nor 'gtimeout' found on PATH; gh API calls in fetch-normalize are running UNGUARDED and a hung call can stall this dispatch. Install GNU coreutils (provides 'timeout'; 'gtimeout' on Homebrew) to restore the timeout guard." >&2
fi

# The canonical fetch query. Owned HERE as the single source. Conforming
# superset equivalent to prefilter.sh's literal, extended with the per-comment
# `id` (PRRC_...) thread-comment node id that fix-history-classify.jq's INPUT
# CONTRACT (§2) documents but prefilter.sh's literal omitted — see DEVIATIONS in
# the return report. External content (bodies) is DATA: never interpreted here.
QUERY='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      comments(last: 50) {
        totalCount
        nodes { id author { login __typename } body url reactionGroups { content viewerHasReacted } }
      }
      reviews(last: 50) {
        totalCount
        nodes { id author { login __typename } body state url reactionGroups { content viewerHasReacted } }
      }
      reviewThreads(first: 50) {
        totalCount
        nodes {
          id
          isResolved
          comments(last: 20) {
            totalCount
            nodes {
              id
              databaseId
              author { login __typename }
              body
            }
          }
        }
      }
    }
  }
}'

# read_payload_source <path>: read the raw payload from a file or stdin (`-`).
# Returns the content on stdout. RETURNS non-zero (emitting the FETCHNORM_ERROR
# marker on stdout) when the file is unreadable — an explicitly-supplied
# --payload-file that cannot be read is an input error, distinct from the
# fail-open empty-payload normalize path. INVARIANT: this helper runs inside
# command substitution, so failure MUST cross the boundary via return code, not
# `exit` (which would only kill the subshell and be discarded by `x="$(...)"`).
# Every capture site checks the substitution status (`if ! x="$(...)"`). (F1)
read_payload_source() {
  local src="$1"
  if [ "$src" = "-" ]; then
    cat
  else
    if [ ! -f "$src" ]; then
      echo "FETCHNORM_ERROR=payload-file-not-found"
      return 1
    fi
    cat "$src"
  fi
}

# validate_live_response <mode> <body> <status>: the SINGLE shared live-response
# operational-failure gate (closed-by-construction). Invoked by BOTH live helpers
# over the RAW live response BEFORE the value crosses the command-substitution
# boundary. LIVE PATH ONLY — injected --payload-file content is TRUSTED and never
# reaches here. On a detected operational failure it emits the stable
# FETCHNORM_ERROR marker on stdout and RETURNS non-zero (the caller propagates via
# the return-code boundary, never `exit`). On success returns 0 and emits nothing
# (the caller is responsible for emitting the validated body). See §5a.
validate_live_response() {
  local mode="$1" body="$2" status="$3"
  case "$mode" in
    graphql)
      # exit-0 with no JSON body is an operational failure, distinct from a valid
      # empty-connections response (which still carries a pullRequest object).
      case "$body" in
        *[![:space:]]*) : ;;
        *) echo "FETCHNORM_ERROR=graphql-empty-body"; return 1 ;;
      esac
      # A non-empty `.errors` array is THE operational-failure signal — fail
      # closed even if a pullRequest is also present.
      if printf '%s' "$body" | jq -e '(.errors // []) | length > 0' >/dev/null 2>&1; then
        echo "FETCHNORM_ERROR=graphql-errors"
        return 1
      fi
      # A concrete pullRequest object MUST be present. null/absent covers
      # repo-not-found, PR-not-found, and auth-stripped data.
      if ! printf '%s' "$body" \
        | jq -e '.data.repository.pullRequest | type == "object"' >/dev/null 2>&1; then
        echo "FETCHNORM_ERROR=graphql-null-pullrequest"
        return 1
      fi
      # Every connection this script's QUERY requests MUST be present AND
      # array-shaped, including the NESTED per-thread comments connection. A
      # response that parses and carries a pullRequest but has LOST a connection
      # normalizes to an empty candidate set — indistinguishable downstream from a
      # genuinely clean PR. `type == "array"` is total and strictly stronger than
      # has(): absent key, null connection, and null `nodes` all yield "null" and
      # fail; `nodes: []` and populated `nodes` yield "array" and pass; a scalar
      # connection fails via the `?`. The all/2 clause is VACUOUSLY TRUE on
      # `reviewThreads.nodes: []`, so a genuinely clean PR still passes.
      # INVARIANT: this check runs LAST — live-graphql-null-pr and
      # live-graphql-errors also fail this predicate, and their stable reason
      # strings are preserved only because the earlier checks catch them first.
      if ! printf '%s' "$body" | jq -e '.data.repository.pullRequest
        | ((.reviewThreads?.nodes? | type) == "array")
          and ((.comments?.nodes?  | type) == "array")
          and ((.reviews?.nodes?   | type) == "array")
          and all(.reviewThreads.nodes[]?; (.comments?.nodes? | type) == "array")' >/dev/null 2>&1; then
        echo "FETCHNORM_ERROR=graphql-missing-connection"
        return 1
      fi
      return 0 ;;
    ci)
      # Status ALLOWLIST: 0 (all pass), 1 (failing), 8 (pending) are the
      # documented check-carrying exit states. ALL three must carry a JSON array
      # (including status 0 — `[]` is valid-but-empty on an all-pass run).
      # Anything else fails closed. Closed-by-construction: ONE array-parse path
      # for every allowlisted status; no per-status branch may skip the check.
      case "$status" in
        0|1|8)
          # INVARIANT: every allowlisted status (incl. 0) must produce a JSON
          # array. Status 0 with `[]` or a non-empty array passes; status 0 with
          # a non-array body (e.g. an error object) is an operational failure.
          if printf '%s' "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
            return 0
          fi
          echo "FETCHNORM_ERROR=ci-not-array"
          return 1 ;;
        *)
          # Non-allowlisted non-zero (auth=4, cancelled=2, network, unknown):
          # fail closed EVEN IF stdout is a valid JSON array (the prior shape-only
          # check wrongly accepted auth-4 + []).
          echo "FETCHNORM_ERROR=ci-operational-failure"
          return 1 ;;
      esac ;;
    *)
      echo "FETCHNORM_ERROR=validate-live-bad-mode"
      return 1 ;;
  esac
}

# fetch_graphql_payload: thin outer shell — the LIVE fetch, BYPASSED under test.
# Requires OWNER/REPO/PR_NUMBER (validated here, not at top, so the offline
# --payload-file path needs none of them). Captures the raw GraphQL JSON
# verbatim. RETURNS non-zero (emitting the FETCHNORM_ERROR marker) on a gh error
# so a real fetch failure is never silently swallowed. INVARIANT: runs inside
# command substitution — failure crosses the boundary via return code, never
# `exit` (which the capture site would discard). Stderr diagnostics -> /dev/null.
# Mirrors prefilter.sh. (F1)
fetch_graphql_payload() {
  local gql_body gql_status
  # LIVE-RESPONSE TEST SEAM (§5b): inject a raw response + status THROUGH the gate
  # instead of invoking gh. Activates ONLY when FETCHNORM_TEST_MODE="1" AND the
  # *_FILE var is set+non-empty — a stray file var ALONE never diverts (fail-closed
  # to live). Inert in production. The seam response is validated exactly as a real
  # one — UNLIKE --payload-file.
  if [ "${FETCHNORM_TEST_MODE:-}" = "1" ] && [ -n "${FETCHNORM_LIVE_GRAPHQL_FILE:-}" ]; then
    if [ ! -f "$FETCHNORM_LIVE_GRAPHQL_FILE" ]; then
      echo "FETCHNORM_ERROR=live-seam-file-not-found"
      return 1
    fi
    gql_body="$(cat "$FETCHNORM_LIVE_GRAPHQL_FILE")"
    gql_status="${FETCHNORM_LIVE_GRAPHQL_STATUS:-0}"
  else
    [ -n "$OWNER" ] || { echo "FETCHNORM_ERROR=missing-owner"; return 1; }
    [ -n "$REPO" ] || { echo "FETCHNORM_ERROR=missing-repo"; return 1; }
    case "$PR_NUMBER" in
      ''|*[!0-9]*) echo "FETCHNORM_ERROR=invalid-pr-number"; return 1 ;;
    esac
    gql_body="$("${GH_TIMEOUT[@]}" gh api graphql \
      -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUMBER" \
      -f query="$QUERY" 2>/dev/null)"
    gql_status=$?
  fi
  # gh transport / non-zero exit is still a hard failure (RS-001 exit boundary).
  if [ "$gql_status" -ne 0 ]; then
    echo "FETCHNORM_ERROR=graphql-failed"
    return 1
  fi
  # RESPONSE-CONTENT gate (RS2-001): reject exit-0 operational failures (errors
  # array / null pullRequest / empty body) BEFORE the body crosses the boundary.
  if ! validate_live_response graphql "$gql_body" "$gql_status"; then
    return 1
  fi
  printf '%s' "$gql_body"
}

# fetch_ci_payload: thin outer shell — the LIVE failed-CI-check fetch, BYPASSED
# under test. `gh pr checks` EXITS NON-ZERO both for the LEGITIMATE
# checks-failing/pending case (exit 8 = pending; exit 1 = failing) AND for real
# fetch errors (auth=4, repo-not-found / unsupported-field=1, cancelled=2). gh's
# exit codes do NOT cleanly separate "checks failing" (where we WANT the JSON and
# let the normalize core filter bucket=="fail") from a live-fetch failure, so the
# discrimination is by PAYLOAD SHAPE: on a non-zero exit, accept the output ONLY
# when stdout parses as the expected JSON array (the documented checks-state
# case); otherwise propagate as a live-fetch failure via the return-code boundary
# (a real error must never fail-OPEN to zero CI candidates). Exit 0 (all checks
# pass; output is `[]` or absent) yields zero CI candidates. INVARIANT: runs
# inside command substitution — failure crosses via return code, never `exit`.
# (F2)
fetch_ci_payload() {
  local ci_out ci_status
  # LIVE-RESPONSE TEST SEAM (§5b): inject a raw response + status THROUGH the gate
  # instead of invoking gh. Activates ONLY when FETCHNORM_TEST_MODE="1" AND the
  # *_FILE var is set+non-empty — a stray file var ALONE never diverts (fail-closed
  # to live). Inert in production.
  if [ "${FETCHNORM_TEST_MODE:-}" = "1" ] && [ -n "${FETCHNORM_LIVE_CI_FILE:-}" ]; then
    if [ ! -f "$FETCHNORM_LIVE_CI_FILE" ]; then
      echo "FETCHNORM_ERROR=live-seam-file-not-found"
      return 1
    fi
    ci_out="$(cat "$FETCHNORM_LIVE_CI_FILE")"
    ci_status="${FETCHNORM_LIVE_CI_STATUS:-0}"
  else
    [ -n "$OWNER" ] || { echo "FETCHNORM_ERROR=missing-owner"; return 1; }
    [ -n "$REPO" ] || { echo "FETCHNORM_ERROR=missing-repo"; return 1; }
    case "$PR_NUMBER" in
      ''|*[!0-9]*) echo "FETCHNORM_ERROR=invalid-pr-number"; return 1 ;;
    esac
    ci_out="$("${GH_TIMEOUT[@]}" gh pr checks "$PR_NUMBER" --repo "$OWNER/$REPO" \
      --json bucket,name,description,link,state,workflow 2>/dev/null)"
    ci_status=$?
  fi
  # RESPONSE-CONTENT gate (RS2-001): status-ALLOWLIST + array-shape over the live
  # response. Replaces the prior shape-only `type=="array"` trust that wrongly
  # accepted auth(4)/cancelled(2) + a valid JSON array. See §5a.
  if ! validate_live_response ci "$ci_out" "$ci_status"; then
    return 1
  fi
  printf '%s' "$ci_out"
}

# --- Resolve the two raw payloads (live fetch OR injected fixture) -----------
# INVARIANT: each helper RETURNS non-zero on a live/input failure (emitting its
# FETCHNORM_ERROR marker on stdout, which is captured into the var). The capture
# site checks the substitution status explicitly so the inner failure can no
# longer be discarded by a bare `x="$(...)"`. On failure the captured marker is
# the FETCHNORM_ERROR line; re-emit it verbatim and exit 1. (F1)
if [ -n "$PAYLOAD_FILE" ]; then
  if ! graphql_payload="$(read_payload_source "$PAYLOAD_FILE")"; then
    printf '%s\n' "$graphql_payload"
    exit 1
  fi
else
  if ! graphql_payload="$(fetch_graphql_payload)"; then
    printf '%s\n' "$graphql_payload"
    exit 1
  fi
fi

if [ -n "$CI_PAYLOAD_FILE" ]; then
  if ! ci_payload="$(read_payload_source "$CI_PAYLOAD_FILE")"; then
    printf '%s\n' "$ci_payload"
    exit 1
  fi
elif [ -z "$PAYLOAD_FILE" ]; then
  # Live path: fetch CI checks too. Offline review-only path (--payload-file with
  # no --ci-payload-file) deliberately yields NO CI candidates.
  if ! ci_payload="$(fetch_ci_payload)"; then
    printf '%s\n' "$ci_payload"
    exit 1
  fi
else
  ci_payload=""
fi

# --- Pure normalize core (sourced from _shared/fetch-normalize-core.sh) --------
# All live I/O (arg parse, read_payload_source, validate_live_response, the two
# fetch helpers, payload resolution, exit posture, FETCHNORM_ERROR markers) stays
# ABOVE this point in the entrypoint. Below is the pure, fixture-driven core over
# the already-resolved (live-validated OR trusted injected) payloads.
#
# Overflow tripwire: read the three connection totalCounts off the raw payload and
# emit the >50 OVERFLOW stderr diagnostic (never silently drop). The consumer's
# existing >50 fail-open stays the authority.
emit_overflow_tripwire "$graphql_payload"

# Build + emit the SINGLE normalized candidate array on stdout (review-surface
# records unioned with CI-check-failure records; `[]` when both empty — the
# fail-open shape).
build_normalized_candidate_set "$graphql_payload" "$ci_payload" "$SELF_LOGIN" "$REVIEWER_FILTER" "$CLASSIFY_FILTER"

exit 0
