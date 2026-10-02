# shellcheck shell=bash
#
# fetch-normalize-core.sh — shared PURE normalize core for the fetch-normalize
# entrypoint (github-review-loop). Defines emit_overflow_tripwire (the three
# connection-totalCount >50 OVERFLOW stderr diagnostic) and
# build_normalized_candidate_set (the review_records + ci_records + `jq -s` union
# into ONE compact normalized candidate array). This is the offline core; the live
# `gh` fetch + the LIVE-RESPONSE gate stay in the thin outer entrypoint shell that
# is BYPASSED under test.
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: the fetch-normalize entrypoint
# sources it by absolute path derived from its OWN script_dir
# (`. "$SCRIPT_DIR/../../_shared/fetch-normalize-core.sh"`). It defines functions only;
# it runs no top-level statements and changes no caller state beyond defining the
# functions below. `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately
# OMITS the P18 shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced
# file mutates the SOURCING shell's option state, so installing those here would corrupt
# the entrypoint's shell; the floor is therefore the documented exception, not the full
# `set -euo pipefail`. This file carries no top-level `set` at all (pure function
# definitions); the ENTRYPOINT owns its own `set -u`, EXIT trap, and error routing.
# Installing `set -e`/`pipefail` here would ALSO break the fail-OPEN-on-CONTENT posture
# (§4 of the entrypoint): the jq pipelines below intentionally swallow malformed payloads
# to empty, and `set -e`/`pipefail` would abort those guarded paths.
# Allowlisted under CHECK13 as a P18 documented exception.
#
# VARIABLE CONTRACT: unlike the ledger-reconstruct shared libraries (which read
# caller-shell globals), these functions take EXPLICIT parameters and read NO caller
# globals. The ONLY I/O is reading the passed-in classify-filter path. Per function:
#   emit_overflow_tripwire <graphql_payload>
#     $1 graphql_payload  — raw GraphQL JSON (live-validated or trusted injected).
#     Reads the three connection totalCounts (reviewThreads/comments/reviews) off the
#     payload, each defaulting to 0 when absent, and emits the >50 OVERFLOW diagnostic
#     on stderr. No stdout. The per-counter command-substitution read (NO here-doc / NO
#     temp file) is preserved so the read-only-FS invariant holds.
#   build_normalized_candidate_set <graphql_payload> <ci_payload> <self_login> <reviewer_filter> <classify_filter_path>
#     $1 graphql_payload      — raw GraphQL JSON (live-validated or trusted injected).
#     $2 ci_payload           — raw `gh pr checks --json ...` JSON (may be empty).
#     $3 self_login           — viewer login (passed to the classifier as --arg login).
#     $4 reviewer_filter      — automated | codex-only | all | <login> (--arg filter;
#                               mode semantics owned by reviewer-identity.jq §5).
#     $5 classify_filter_path — absolute path to fix-history-classify.jq. The classifier
#                               `include`s reviewer-identity.jq, resolved via
#                               `-L <dir of $5>`, so the module MUST be co-located with
#                               the classify filter (same directory).
#     Emits the SINGLE compact normalized candidate array on stdout; `[]` when both
#     record families are empty (the fail-open shape). Malformed/empty injected payload
#     fails OPEN to `[]`, never an error.

# emit_overflow_tripwire <graphql_payload>: read the three connection totalCounts
# DIRECTLY off the raw payload (the classifier filter does not emit them), each
# defaulting to 0 when absent so a malformed/empty payload behaves like a 0-node page.
# Mirrors prefilter.sh. Emit an OVERFLOW diagnostic on stderr (never silently drop)
# when any exceeds 50; the consumer's existing >50 fail-open stays the authority.
# Each count is read via its OWN command substitution — NO here-doc / here-string and
# NO temp file. A here-doc-fed `while read` loop requires a writable TMPDIR; on a
# read-only filesystem bash cannot create the here-doc temp file, the loop body never
# runs, the counters stay 0, and a real >50 overflow is silently lost (exit 0) — the
# overflow signal must NEVER fail open on an unwritable FS. Reading each scalar by
# command substitution removes that filesystem dependency entirely.
# INTENTIONAL fail-open-on-CONTENT: a jq failure here (malformed payload) yields an
# empty substitution, which the integer guard below resolves to 0 per counter. This
# swallow is deliberate — graphql_payload is already cleared by validate_live_response
# (live) or is trusted injected content (--payload-file). This is NOT an unguarded live
# boundary; the live gate ran before this point.
emit_overflow_tripwire() {
  local graphql_payload="$1"
  local threads_total comments_total reviews_total
  threads_total="$(printf '%s' "$graphql_payload" | jq -r '
    (.data.repository.pullRequest.reviewThreads.totalCount // 0) | tostring' 2>/dev/null)"
  comments_total="$(printf '%s' "$graphql_payload" | jq -r '
    (.data.repository.pullRequest.comments.totalCount // 0) | tostring' 2>/dev/null)"
  reviews_total="$(printf '%s' "$graphql_payload" | jq -r '
    (.data.repository.pullRequest.reviews.totalCount // 0) | tostring' 2>/dev/null)"
  case "$threads_total" in ''|*[!0-9]*) threads_total=0 ;; esac
  case "$comments_total" in ''|*[!0-9]*) comments_total=0 ;; esac
  case "$reviews_total" in ''|*[!0-9]*) reviews_total=0 ;; esac

  if [ "$threads_total" -gt 50 ] || [ "$comments_total" -gt 50 ] || [ "$reviews_total" -gt 50 ]; then
    echo "github-review-loop: OVERFLOW one or more connection totalCounts exceed 50 (reviewThreads=$threads_total comments=$comments_total reviews=$reviews_total); in-page classification is untrustworthy on the overflowed axis — the consumer must fail open (DISPATCH) per its >50 tripwire." >&2
  fi
}

# build_normalized_candidate_set <graphql_payload> <ci_payload> <self_login> <reviewer_filter> <classify_filter_path>:
# build the SINGLE normalized candidate array (the union of review-surface records and
# CI-check-failure records) and emit it compact on stdout. FAIL-OPEN: a malformed /
# empty / unparseable injected payload yields `[]` (NOT an error) — the normalize core
# never errors on a bad injected payload.
build_normalized_candidate_set() {
  local graphql_payload="$1" ci_payload="$2" self_login="$3" reviewer_filter="$4" classify_filter_path="$5"
  local review_records ci_records classify_module_dir
  classify_module_dir="$(dirname -- "$classify_filter_path")"

  # --- Review-surface records: pipe the raw GraphQL payload through the shared
  # classifier filter (the single source of skip/order/overflow semantics), then
  # tag each emitted record with item_source: "review". FAIL-OPEN: a malformed /
  # empty / unparseable payload yields an empty review-record set (NOT an error) —
  # the normalize core never errors on a bad injected payload. -------------------
  # INTENTIONAL fail-open-on-CONTENT: the 2>/dev/null swallow here is deliberate.
  # graphql_payload is already cleared by validate_live_response (live) or is
  # trusted injected content (--payload-file). A jq content-level parse failure
  # (e.g. structurally valid JSON but unexpected shape) degrades to an empty record
  # set — the slurp below canonicalizes to []. This is NOT an unguarded live
  # boundary; the live gate ran before this point. A classifier COMPILE failure (syntax
  # error, missing/broken reviewer-identity include) is NOT content: the entrypoint
  # compile-probes the classifier before calling this function and fails closed
  # (FETCHNORM_ERROR=unparseable-filter).
  review_records="$(printf '%s' "$graphql_payload" \
    | jq -c -L "$classify_module_dir" -f "$classify_filter_path" --arg login "$self_login" --arg filter "$reviewer_filter" 2>/dev/null \
    | jq -c '. + {item_source: "review"}' 2>/dev/null)"
  # A jq failure (e.g. malformed payload) leaves review_records empty -> the slurp
  # below canonicalizes to an empty array. This is the fail-open empty-set path.

  # --- CI-check-failure records: project the raw `gh pr checks --json` array down
  # to failed checks only (bucket == "fail"), normalizing each into a CI candidate
  # carrying NO node id (id: null). A malformed / empty CI payload yields zero CI
  # candidates (fail-open). The raw gh output is a JSON array of check objects. ----
  # INTENTIONAL fail-open-on-CONTENT: the `if type == "array" then .[] else empty
  # end` guard and 2>/dev/null swallow are deliberate. ci_payload is already
  # cleared by validate_live_response (live) or is trusted injected content
  # (--ci-payload-file). A non-array body here means validate_live_response already
  # rejected it (live) or it is a trusted injected fixture whose shape mismatch
  # degrades to zero CI candidates. This is NOT an unguarded live boundary; the
  # live gate ran before this point.
  ci_records="$(printf '%s' "$ci_payload" | jq -c '
    if type == "array" then .[] else empty end
    | select(.bucket == "fail")
    | {
        item_source: "ci-check-failure",
        id: null,
        name: (.name // ""),
        description: (.description // ""),
        link: (.link // null),
        state: (.state // ""),
        workflow: (.workflow // null)
      }
  ' 2>/dev/null)"

  # --- Union the two record families into ONE normalized JSON array on stdout.
  # `jq -s` slurps the (possibly empty) newline-delimited record streams; an empty
  # stream slurps to []. The two slurps are concatenated. Always emits exactly one
  # compact array, `[]` when both families are empty (the fail-open shape). -------
  printf '%s\n%s\n' "$review_records" "$ci_records" \
    | jq -s -c '[ .[] ]'
}
