# shellcheck shell=bash
#
# graphql-response.sh — shared fail-closed validator for a live GitHub GraphQL response body
# (github-review-loop). Defines hivemind_graphql_response_check (one response body) and
# hivemind_graphql_pages_check (the raw concatenated page stream of `gh api graphql --paginate`).
#
# THIS FILE IS SOURCED, NOT EXECUTED. No shebang: each caller sources it by absolute
# path derived from its OWN script_dir (`. "$plugin_root/skills/_shared/graphql-response.sh"`).
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
# SINGLE RESPONSIBILITY: decide whether a GraphQL response body that `gh` delivered with exit 0
# is a usable success, and name the failure class when it is not. It performs no fetch, reads no
# file, and projects no field beyond the top-level `errors` / `data` envelope. Consumer-specific
# shape checks (e.g. a required `.data.repository.pullRequest`) stay with the consumer and run
# AFTER this check passes.
#
# CONTRACT (both functions):
#   success -> return 0, print NOTHING.
#   failure -> print exactly ONE token on stdout, return 1. Never `exit`.
#   A body passes iff it is exactly ONE JSON value, that value is an object,
#   (.errors == null or .errors == []) and (.data | type) == "object".
#
# TOKENS, in precedence order (the first that applies wins):
#   empty-body    the body is blank under POSIX [:space:] (so a CR/LF-only body is blank).
#   malformed     unparseable, not exactly one JSON value (single mode), or not an object.
#   errors        any other `.errors` value: a non-empty array (including [{}] and [null]),
#                 an object, a string, a number, or a boolean.
#   missing-data  `.data` is absent, null, or not an object.
#
#   hivemind_graphql_response_check <body>
#     $1 body — the raw stdout of ONE `gh api graphql` call made without --jq / --paginate.
#   hivemind_graphql_pages_check <stream>
#     $1 stream — the raw stdout of `gh api graphql --paginate` made WITHOUT --jq and WITHOUT
#                 --slurp: every page's JSON object concatenated with no separator. It is
#                 parsed with `jq -s`. At least one page is required; every page must pass the
#                 single-body check; one bad page fails the whole stream. When pages fail with
#                 different tokens, the highest-precedence token among them is printed.
#
# WHY A POSITIVE ALLOWLIST (not "fail when .errors is a non-empty array"): gh does not turn every
# GraphQL error envelope into a non-zero exit. Per gh's `parseErrorResponse` (cli/cli
# pkg/cmd/api), gh exits 0 AND still runs --jq over the body for a single error object with no
# `message`, for an `errors` value that is not an array, and for array elements that are neither
# objects nor strings. A reject-list keyed on one shape would pass every other shape as success,
# so this file accepts only the one success envelope and fails every other shape closed.
#
# WHY PAGES MODE EXISTS: under `--paginate`, gh runs --jq once PER PAGE, and gh's embedded jq
# cannot load a module, so a consumer cannot apply a shared envelope check inside its --jq
# program. The consumer instead captures the raw page stream (no --jq, no --slurp), validates
# every page here, and only then projects the pages itself.
#
# REST SCOPE BOUNDARY: gh turns every HTTP status above 299 into a non-zero exit, so a REST call
# has no "200 with an errors body" shape to catch. REST responses are out of scope for this file;
# their consumers keep relying on gh's exit status.
#
# TOKEN-PREFIX CONVENTION FOR CONSUMERS: the token is a bare class name. A consumer emits it as
# `<ERRTOKEN>=graphql-<token>` (e.g. `FETCHNORM_ERROR=graphql-errors`) or maps it onto its own
# existing failure token; it never forwards the response body.
#
# SINGLE SOURCE: both public functions delegate to _hivemind_graphql_check_stream, which holds the
# ONLY copy of the jq envelope predicate (page_token). No caller re-implements the predicate.
#
# DEPENDENCY: jq (1.6 and 1.7: uses only -s, --arg, and if/elif/any/2) + pure bash.

# _hivemind_graphql_check_stream <mode> <body>: shared engine for both public functions.
# <mode> is `single` (exactly one JSON value required) or `pages` (one or more concatenated
# values). Prints nothing and returns 0 on success; prints one token and returns 1 otherwise.
# A jq parse failure (unparseable or truncated input) and any unexpected jq output both resolve
# to `malformed`, so no failure path can read as success.
_hivemind_graphql_check_stream() {
  local check_mode="$1" response_body="$2"
  local check_token
  local envelope_program='
    def page_token:
      if type != "object" then "malformed"
      elif (.errors == null or .errors == []) | not then "errors"
      elif (.data | type) != "object" then "missing-data"
      else "ok" end;
    if length == 0 then "empty-body"
    elif $mode == "single" and length != 1 then "malformed"
    else
      [ .[] | page_token ] as $page_tokens
      | if any($page_tokens[]; . == "malformed") then "malformed"
        elif any($page_tokens[]; . == "errors") then "errors"
        elif any($page_tokens[]; . == "missing-data") then "missing-data"
        else "ok" end
    end'

  case "$response_body" in
    *[![:space:]]*) : ;;
    *) printf '%s\n' "empty-body"; return 1 ;;
  esac

  check_token="$(printf '%s' "$response_body" \
    | jq -r -s --arg mode "$check_mode" "$envelope_program" 2>/dev/null)" || check_token="malformed"

  case "$check_token" in
    ok) return 0 ;;
    empty-body|malformed|errors|missing-data) printf '%s\n' "$check_token"; return 1 ;;
    *) printf '%s\n' "malformed"; return 1 ;;
  esac
}

# hivemind_graphql_response_check <body>: validate ONE GraphQL response body. See CONTRACT above.
hivemind_graphql_response_check() {
  _hivemind_graphql_check_stream single "${1-}"
}

# hivemind_graphql_pages_check <stream>: validate the raw concatenated page stream of
# `gh api graphql --paginate` (no --jq, no --slurp). See CONTRACT above.
hivemind_graphql_pages_check() {
  _hivemind_graphql_check_stream pages "${1-}"
}
