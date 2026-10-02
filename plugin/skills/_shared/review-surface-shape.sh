# shellcheck shell=bash
#
# review-surface-shape.sh — shared positive shape predicate for the PR review-activity skeleton
# (github-review-loop). Defines hivemind_review_surface_shape_check (one GraphQL response body).
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute
# path derived from its OWN script_dir (`. "$plugin_root/skills/_shared/review-surface-shape.sh"`).
# It defines functions only; it runs no top-level statements and changes no caller state
# beyond defining the function below. `bash -n` validates it as a sourced fragment.
#
# P18 FLOOR EXCEPTION (ADR-0020): as a SOURCED library this file deliberately
# OMITS the P18 shell-safety floor `set -e` / `set -o pipefail` and any EXIT trap. A sourced
# file mutates the SOURCING shell's option state, so installing those here would corrupt
# every caller's shell; the floor is therefore the documented exception, not the full
# `set -euo pipefail`. This file carries no top-level `set` at all (pure function
# definitions); each caller owns its own `set -u` and error routing. Allowlisted under
# CHECK13 as a P18 documented exception.
#
# SINGLE RESPONSIBILITY: decide whether a GraphQL response body carries the complete PR
# review-activity skeleton the review-loop consumers read, and name the failure class when it
# does not. It performs no fetch, reads no file, and projects no field. A body that has LOST part
# of the skeleton (null repository or pullRequest, an absent or null connection) normalizes to an
# empty candidate set downstream, indistinguishable from a genuinely clean PR; this check is what
# keeps that hollow body from reading as a clean verdict.
#
# PRECONDITION: the body has ALREADY passed hivemind_graphql_response_check
# (${CLAUDE_PLUGIN_ROOT}/skills/_shared/graphql-response.sh). This function does not re-check the
# `errors` / `data` envelope: a body that carries an `errors` entry next to a well-formed skeleton
# passes here, so a caller that skips the envelope check gets no error protection from this file.
#
# SKELETON (every position the predicate checks, and the exact type it requires there):
#   (body)                                            object
#   .data                                             object
#   .data.repository                                  object
#   .data.repository.pullRequest                      object
#     .comments / .reviews / .reviewThreads           object (each connection)
#       .nodes                                        array  (each connection)
#     .reviewThreads.nodes[] (each thread element)    object
#       .comments                                     object
#         .nodes                                      array
#   `nodes: []` passes at every level, so a genuinely clean PR (no comments, no reviews, no
#   threads, or threads with no comments) passes.
#
# CONTRACT:
#   success -> return 0, print NOTHING.
#   failure -> print exactly ONE token on stdout, return 1. Never `exit`.
#
# TOKENS, in precedence order (the first that applies wins):
#   null-pullrequest     the body, `.data`, `.data.repository`, or `.data.repository.pullRequest`
#                        is not an object: absent, null, or of any other type. Also the token for
#                        any body jq cannot evaluate (unparseable) and for any unexpected jq
#                        output, so no failure path can read as success.
#   missing-connection   pullRequest is an object but a SKELETON connection is not an object
#                        (absent, null, scalar, or array), or its `nodes` is not an array, or a
#                        reviewThreads element is not an object, or that thread's `.comments` is
#                        not an object, or its `.comments.nodes` is not an array.
#
#   hivemind_review_surface_shape_check <body>
#     $1 body — the raw stdout of ONE `gh api graphql` call for the review-activity query, after
#               it passed hivemind_graphql_response_check.
#
# COMPLETENESS (envelope + shape cover the skeleton): the predicate checks EVERY skeleton position,
# nullable or not, and it is TYPE-STRICT per position: each position must be the exact type the
# SKELETON table names, tested as a positive `type == "object"` / `type == "array"` allowlist.
# Eliminated class: any non-object or non-array value at a skeleton position (null, absent,
# string, number, boolean, or the wrong container) passing. INVARIANT: every term of the program
# yields exactly ONE boolean for every input, because each `.field` access is reached only after
# a short-circuit `and` has proved its parent an object, and each `[]` iteration only after its
# list was proved an array. So no position can pass by yielding NO output (jq's all/2 treats an
# element whose condition yields nothing as passing), and no access can raise a jq error. At a
# NULLABLE position (repository, pullRequest, reviews, each connection's
# `nodes` list, each reviewThreads element) a null is spec-legal WITHOUT any `errors` entry, which
# is exactly the hollow-body class the envelope check cannot see, so this predicate must reject it.
# At a NON-NULL position, a failed field cannot surface as a silent null: per the GraphQL
# specification (Execution, "Handling Field Errors" / "Errors and Non-Null Fields") the null
# propagates to the nearest nullable parent AND the error is added to the response's `errors`
# list, which hivemind_graphql_response_check rejects. Together the two checks leave no skeleton
# position that can be lost without a failure token. Leaf record elements and their fields
# (individual elements of `.comments.nodes` and `.reviews.nodes`, and each thread comment) are
# content, not skeleton: this predicate does not type-check them, and they stay with the consumers.
#
# CONSUMERS: fetch-normalize.sh, prefilter.sh, and the pr-change-detect-poll.sh snapshot read
# (github-review-loop) each request this skeleton and route the body through this check.
#
# RECORDED RESIDUAL (linked finding 597c0a72): the predicate mirrors the requested skeleton BY
# HAND. A future query that adds a nullable connection a consumer reads must add that connection
# here, or a lost instance of it reads as clean. Inherited: the predicate existed on main inside
# fetch-normalize.sh (validate_live_response); it is lifted here and tightened to the type-strict
# form above. Bounded: the gap opens
# only for a spec-legal null-without-errors response at a position not yet listed, a shape never
# observed from the GitHub API. Obvious remediation considered and rejected on the merits:
# deriving the positions from the query text needs a GraphQL parser plus schema nullability
# data, disproportionate to a hand-listed five-position skeleton. Because every consumer calls
# this one copy, that maintenance happens in one place.
#
# SINGLE SOURCE: this file holds the ONLY copy of the review-activity skeleton predicate
# (shape_program). No consumer re-implements it. Its signature is the jq definition
# `def is_skeleton_connection: (type == "object") and ((.nodes | type) == "array");`, which
# appears nowhere else in the plugin.
#
# DEPENDENCY: jq (1.6 and 1.7: uses only -r, def, if/then/else, short-circuit `and`, and all/2)
# + pure bash.

# hivemind_review_surface_shape_check <body>: check ONE response body for the review-activity
# skeleton. See CONTRACT above. Both predicates live in ONE jq program; a jq failure on any body
# and any output other than a known token resolve to a failure token, never to success.
hivemind_review_surface_shape_check() {
  local surface_body="${1-}"
  local shape_token
  local shape_program='
    def is_skeleton_connection: (type == "object") and ((.nodes | type) == "array");
    if ((type == "object")
        and ((.data | type) == "object")
        and ((.data.repository | type) == "object")
        and ((.data.repository.pullRequest | type) == "object")) | not
      then "null-pullrequest"
    else .data.repository.pullRequest
      | if (.comments | is_skeleton_connection)
          and (.reviews | is_skeleton_connection)
          and (.reviewThreads | is_skeleton_connection)
          and all(.reviewThreads.nodes[]; (type == "object") and (.comments | is_skeleton_connection))
        then "ok"
        else "missing-connection" end
    end'

  shape_token="$(printf '%s' "$surface_body" | jq -r "$shape_program" 2>/dev/null)" \
    || shape_token="null-pullrequest"

  case "$shape_token" in
    ok) return 0 ;;
    null-pullrequest|missing-connection) printf '%s\n' "$shape_token"; return 1 ;;
    *) printf '%s\n' "null-pullrequest"; return 1 ;;
  esac
}
