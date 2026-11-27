#!/usr/bin/env bash
#
# subissue-ops.sh — deterministic MECHANISM substrate for the hivemind
# `prd-to-issues` skill (judgment/mechanism split; engineering-principles P5 +
# P11). Path: ${CLAUDE_PLUGIN_ROOT}/skills/prd-to-issues/scripts/subissue-ops.sh
#
# 1. PURPOSE
# ----------
# This script owns ONLY the lossless, deterministic mechanism of wiring GitHub
# NATIVE sub-issue relationships (the GA 2025 issue hierarchy), so the
# prd-to-issues skill can model a PRD as a PARENT (epic) issue with its sliced
# issues attached as NATIVE SUB-ISSUES — replacing the old `initiative:<slug>`
# label-grouping convention with a first-class GitHub parent/child link.
# NO slicing / judgment logic lives here — deciding WHAT the epic is, how the PRD
# decomposes into slices, or which slice blocks which is holistic LLM work (P11)
# and stays in the SKILL prose. The script is the reproducible hands:
#   - idempotently ensure (create-or-find) the PRD-level epic PARENT issue,
#     returning its issue number + GraphQL NODE ID, and add the `type:epic` label to the
#     returned epic (live only) so the readiness check reads every slice's parent as an epic,
#   - attach a sliced (child) issue to the parent as a NATIVE sub-issue via the
#     GraphQL `addSubIssue` mutation,
#   - read the parent's `subIssues` connection (paginated to completeness),
#   - discover candidate child issues by EXACT title (attached AND unparented) so a
#     create-before-attach partial failure is recoverable, not re-created,
#   - surface a GitHub rejection of an attach (child already parented, cycle) as a
#     STRUCTURED recoverable warning record instead of crashing,
#   - report whether a resolved epic is the SEED issue of an initiative (ensure-parent --slug:
#     its body's first line is the seed issue marker naming that slug),
#   - gate slicing on the initiative's design at the trunk commit (design-gate): the PRD's UI
#     line, the UI prototype files and the review record, read ONLY through the shared readiness
#     check library ${CLAUDE_PLUGIN_ROOT}/skills/_shared/readiness-check.sh.
# The split mirrors triage-ops.sh: a thin live `gh`/network shell wrapping a pure,
# offline-exercisable transform core.
#
# 2. INPUT CONTRACT — per subcommand
# ----------------------------------
#   ensure-parent --title <str> --body <str>|--body-file <path|-> [--repo <owner/repo>]
#                 [--existing-number <int> [--slug <slug>]] [--response-file <path|->]
#                 [--discovery-response-file <path|->]
#     Idempotently CREATE-OR-FIND the PRD-level epic (parent) issue — ORPHAN-SAFE
#     (closed-by-construction): when no --existing-number is supplied, ensure-parent first
#     DISCOVERS-BY-TITLE before creating, so a rerun after a create-before-record partial
#     failure never spawns a SECOND duplicate epic. Concurrent runs: see the THREAT MODEL
#     under PARENT ORPHAN-SAFETY in §4.
#     Idempotency key: if --existing-number is supplied the parent is RESOLVED (its
#     node id read by number) instead of created — the skill anchors the epic to a
#     known issue across re-runs. Otherwise: discover the EXACT epic title via the SHARED
#     ENUMERATION machinery (repository.issues enumeration + paginate_to_completeness +
#     filter_exact_title — the SAME path find-by-title uses, never a divergent copy), then
#     apply the resolution rules below; only on ZERO matches is a NEW issue created.
#     Discovery resolution rules (Q2 DECISION):
#       - exactly ONE OPEN exact-title match  -> RESOLVE it (skip create), status
#         `resolved-by-title`, emit its number+id.
#       - ZERO matches                        -> CREATE as today, status `created`.
#       - MULTIPLE exact matches, OR any CLOSED exact match, OR divergent -> FAIL CLOSED
#         (structured, nonzero) — never blind-create a second parent, never silently reuse a
#         closed epic. The ambiguity is surfaced, not papered over.
#     online (create path): `gh issue create --title --body[-file]` (untrusted title
#              /body flow ONLY through gh flags, never into shell/GraphQL source),
#              then resolve its node id by number via GraphQL. --repo, when given,
#              is passed to gh as `-R`. The PRE-CREATE discovery enumeration applies the SAME
#              owner/repo charset guard find-by-title has (not the weak `*/*` glob).
#     online (resolve path, --existing-number): GraphQL repository.issue(number) read
#              of { number id }, routed through the SHARED kernel (see §4).
#     --slug <slug> (seed check): valid ONLY with --existing-number (else exit 2); the slug must
#              match ^[a-z0-9]+(-[a-z0-9]+)*$ (else exit 2). Both checks run BEFORE any gh call.
#              The resolve read then also asks for the issue `body`; the shared kernel requires
#              it to be a string, else FAILS CLOSED. The body reaches the library's
#              hivemind_seed_marker_slug ONLY on stdin; `seed` is true only when that function
#              prints exactly <slug> (a CRLF marker line counts; another slug or no marker gives
#              false). The resolve path creates no issue and only adds the epic label (below),
#              never touching the body, so the seed's marker line stays. Without --slug every
#              output is byte-identical to the contract before it.
#     online (epic label, every live path): after the record is read and before it is printed,
#              ensure_epic_label adds `type:epic` to the returned epic: the resolved path (number
#              from the record), the --slug path ONLY when `seed` is true, resolved-by-title
#              (number from the discovery decision) and the created path (after the node-id read).
#              It reads the repository's label by name (GraphQL repository.label, owner/name/label
#              via -f, through the SHARED kernel); a missing label is created with
#              `gh label create type:epic --color 3e4b9e --description "triage type rating" -R
#              <owner/repo>` (the triage palette's values, never --force); when that create
#              fails, the label is read again the same way and the run goes on only if it now
#              reads exactly `type:epic` (another run created it); a label found whose name
#              is not exactly `type:epic` (e.g. `Type:Epic`) FAILS CLOSED; then `gh issue edit
#              <number> -R <owner/repo> --add-label type:epic`. It never edits an existing label,
#              never removes a label and never touches an issue's title or body. Any read, create
#              or edit failure exits nonzero with nothing on stdout. Offline paths never label.
#     offline: with --response-file -> normalizes the injected raw GraphQL
#              repository.issue response (number+id) through the shared kernel and
#              emits the parent record (status resolved when --existing-number was given,
#              else created — the create path's post-create node-id read). With --slug the
#              injected response carries the issue body and the seed record is emitted. Title/body/create
#              are NOT exercised offline (no deterministic transform — creation is pure live
#              side effect). With --discovery-response-file (no --existing-number) -> runs the
#              discovery transform (shared kernel + exact-title filter + resolution rules) over
#              the injected repository.issues ENUMERATION response: one OPEN match emits status
#              resolved-by-title; a multiple/CLOSED/divergent set FAILS CLOSED; ZERO matches
#              falls through to the --response-file `created` simulation.
#     --response-file / --discovery-response-file are TEST SEAMS honored ONLY when
#     SUBISSUE_OPS_OFFLINE is set; a live invocation supplying either is REJECTED fail-closed
#     via the shared guard (see §5) BEFORE any gh call.
#
#   attach-subissue --parent-id <NODE_ID> --child-id <NODE_ID> [--response-file <path|->]
#     Run the GraphQL `addSubIssue` mutation. CRITICAL FIELD MAPPING: the input
#     fields are `issueId` (the PARENT) and `subIssueId` (the CHILD). This is
#     DELIBERATELY DIFFERENT from the dependency API's `blockingIssueId` — do NOT
#     conflate the two. Operates on GraphQL NODE IDs (ensure-parent's id + the
#     child issue's id), so no number->id round-trip is needed.
#     online:  addSubIssue mutation, raw response routed through surface_attach_response.
#     offline: with --response-file -> surfaces that injected response (exercises the
#              attached / already-parented / cycle / error / transport records); with
#              --emit-payload (the EXPLICIT opt-in) -> emits the constructed GraphQL
#              variables payload (exercises payload build). Offline with NEITHER flag
#              FAILS CLOSED (exit 2) — symmetric with ensure-parent/list-children, so an
#              ambient SUBISSUE_OPS_OFFLINE leak can never turn a REAL attach into a silent
#              success no-op via a fall-through payload build.
#     --response-file is a TEST SEAM honored ONLY when SUBISSUE_OPS_OFFLINE is set;
#     a live invocation supplying it is REJECTED fail-closed via the shared guard
#     (see §5) BEFORE any gh call.
#     --parent-id / --child-id are validated against the node-id charset (defense-in-depth,
#     ADR-0020) BEFORE any gh/GraphQL use.
#
#   find-by-title --title <str> [--repo <owner/repo>] [--response-file <path|->]
#     DETERMINISTIC orphan/candidate discovery: ENUMERATE the repository's issues and match
#     the EXACT title LOCALLY to find candidate child issues — both ALREADY-ATTACHED (carrying
#     a parent) AND recently-created-but-UNPARENTED issues — so a create-before-attach PARTIAL
#     FAILURE is RECOVERABLE (attach-or-reuse) instead of re-creating a duplicate slice. The
#     skill (RSTEP-002) consumes the output to decide attach-vs-reuse per slice.
#     EXACT-title semantics: the lookup enumerates `repository.issues` (a DETERMINISTIC,
#     terminally-paginated connection — NOT GitHub's fuzzy/ranked full-text search API) and
#     this subcommand POST-FILTERS to issues whose `.title` EQUALS the queried title
#     byte-for-byte (the untrusted title is compared as DATA via jq --arg). The untrusted
#     title NEVER enters a query STRING at all — it flows ONLY through the jq --arg exact-match
#     filter; owner/name flow via gh -f as DATA. There is no search DSL, so no quote-breakout,
#     qualifier-injection, is:issue/PR-leak, or 1000-result truncation class to neutralize.
#     online:  `gh api graphql` enumerates `repository(owner,name).issues(states:[OPEN,CLOSED])`
#              page-by-page to completeness; each raw page is routed through the SHARED kernel
#              (see §4) then the full accumulated set is exact-title post-filtered. Each emitted
#              match carries the issue's `state` (OPEN/CLOSED) — the script SURFACES state
#              truthfully; the closed-child CONFLICT judgment lives in the SKILL, never here.
#     offline: with --response-file -> normalizes the injected raw repository.issues page
#              through the shared kernel + exact-title filter (the injected fixture is the
#              enumeration result set). REQUIRES --response-file offline (fail-closed otherwise).
#     --response-file is a TEST SEAM honored ONLY when SUBISSUE_OPS_OFFLINE is set; a live
#     invocation supplying it is REJECTED fail-closed via the shared guard (see §5) BEFORE
#     any gh call.
#
#   list-children --parent-id <NODE_ID> [--response-file <path|->]
#     Read the parent's `subIssues` connection. PAGINATES TO COMPLETENESS in the
#     live path (first:100 per page, following endCursor while hasNextPage) so the
#     full child set is always returned — this script LEARNS the triage-ops single-
#     page lesson (issue #228): a partial read that drops children past page 1 would
#     let the skill re-attach an already-attached slice or miss a child entirely.
#     online:  one node(id:) subIssues page per cursor; each page's raw response is
#              routed through the SHARED kernel (see §4) BEFORE accumulation — a
#              malformed/error page FAILS CLOSED mid-pagination, never emitting a
#              partial set as if complete.
#     offline: with --response-file -> normalizes the injected raw single-page
#              GraphQL response through the shared kernel. The injected fixture is
#              treated as the COMPLETE connection (its pageInfo.hasNextPage MUST be
#              false; a true value FAILS CLOSED — the offline seam exercises the
#              same completeness gate the live loop enforces).
#     --response-file is a TEST SEAM honored ONLY when SUBISSUE_OPS_OFFLINE is set;
#     a live invocation supplying it is REJECTED fail-closed via the shared guard
#     (see §5) BEFORE any gh call.
#
#   design-gate --slug <slug> [--repo <owner/repo>] [--remote <name>] [--trunk-response-file <path|->]
#     Design gate for slicing under a seed epic. Argument order: the slug is checked FIRST
#     (required, ^[a-z0-9]+(-[a-z0-9]+)*$, else exit 2); --trunk-response-file on a live
#     invocation is REJECTED (exit 2) via the shared guard (see §5); the remote (default `origin`)
#     passes the identifier gate (^[A-Za-z0-9._/-]+$, no leading `-`, no `..`; else exit 2);
#     owner/repo (explicit --repo, else the current checkout) is checked with assert_owner_repo.
#     online (trunk read): ONE GraphQL read of repository.defaultBranchRef { name target { oid } },
#              routed through the SHARED kernel (see §4). The trunk name passes the identifier
#              gate and `git check-ref-format --branch`; the commit id must pass the library's
#              hivemind_readiness_commit_ok (40 or 64 lowercase hex).
#     link prefix: after those checks, `link_prefix` is hivemind_readiness_link_prefix of
#              owner/repo and the trunk NAME (never the commit id): the one Design blob link prefix
#              the readiness check reads back. A failure there FAILS CLOSED.
#     online (fetch): `GIT_TERMINAL_PROMPT=0 git --no-replace-objects fetch --quiet --no-tags
#              --no-recurse-submodules --no-prune --refmap= -- <remote> refs/heads/<trunk>`, which
#              writes FETCH_HEAD only. The commit id must then name a local commit object that
#              is FETCH_HEAD or its ancestor, else FAILS CLOSED (a force-pushed trunk, even when
#              the old commit is still in the object store, or a --repo that is not the local
#              clone). The gate then reads, and reports as `commit`, the fetched tip's commit id,
#              so a trunk that moved forward between the read and the fetch is read as it now
#              stands. No branch name or local ref ever reaches the library: every document
#              is read at the commit id, so files only in the working tree never count.
#     documents (read at the commit ONLY through the shared library):
#       - ui: docs/prds/<slug>.md via hivemind_doc_read under hivemind_readiness_jq_defs with
#         rc_doc_eval(rc_prd_ui): yes, no or invalid, or missing when the PRD fails the Document
#         existence test.
#       - ONLY when ui is yes:
#         * docs/initiatives/<slug>/prototype/index.html and notes.md are each tested with
#           hivemind_doc_entry (the Document existence test: a symlink, submodule or tree is
#           missing); either one missing gives `prototype_missing`, once.
#         * docs/initiatives/<slug>/review-record.md is read with hivemind_doc_read and piped to
#           hivemind_record_front_matter: missing gives record_missing, unparseable gives
#           record_malformed.
#         * the pass rule (restating the readiness check's, clause for clause): record_not_passed
#           (verdict not pass, clean_round not true, or rounds below 2), record_rounds_exceeded
#           (rounds above 3), record_open (any open count above 0).
#         * each stamped path failing the Document existence test, or whose blob at the commit
#           differs from its stamp, gives record_stale:<path> (the staleness rule).
#         * each prototype path missing from the record's stamps gives record_unstamped:<path>.
#       ui missing or invalid gives no reason and no refusal: the readiness check fails such a
#       slice at triage.
#     offline: --trunk-response-file replaces the GraphQL read (same kernel) and the fetch is
#              skipped, so the commit must already be in the local object store. REQUIRES
#              --trunk-response-file and --repo offline (exit 2 with no stdout otherwise); --repo
#              is checked with assert_owner_repo and is the owner/repo of `link_prefix`.
#     failure: a gh, git or fetch failure, a malformed read, or an unresolvable commit leaves
#              stdout empty, prints ONE `subissue-ops:` stderr line and exits nonzero.
#
# 3. OUTPUT SCHEMA — JSON on stdout (compact)
# -------------------------------------------
#   ensure-parent:
#     { "number": <int>, "id": <node-id>,
#       "status": "created"|"resolved"|"resolved-by-title" }
#     `resolved-by-title` is emitted when the pre-create discovery found exactly ONE OPEN
#     exact-title epic and resolved it instead of creating a duplicate (orphan-safety).
#   ensure-parent --existing-number <int> --slug <slug>:
#     { "number": <int>, "id": <node-id>, "status": "resolved", "seed": true|false }
#   Live, every ensure-parent record above is printed only after its epic is labeled `type:epic`
#   (with --slug, only a seed epic is labeled); the record itself is unchanged by the label step.
#
#   attach-subissue payload (offline, --emit-payload):
#     { "issueId": <parent-node-id>, "subIssueId": <child-node-id> }
#   attach-subissue surfaced response (online, or offline with --response-file):
#     attached: { "status": "attached", "parent": <int>, "child": <int> }
#     warning:  { "status": "warning",
#                 "kind": "already-parented"|"cycle-rejected"|"error"|"transport-error",
#                 "message": <str> }
#
#   list-children normalized:
#     { "parent_id": <node-id|null>,
#       "children": [ { "number": <int>, "id": <node-id>, "title": <str> }, ... ] }
#
#   find-by-title normalized:
#     { "title": <str>,
#       "matches": [ { "number": <int>, "id": <node-id>, "title": <str>,
#                      "state": "OPEN"|"CLOSED",
#                      "parent": { "number": <int>, "id": <node-id> } | null }, ... ] }
#     `matches` holds ONLY issues whose title EQUALS the queried title byte-for-byte
#     (exact-title post-filter). `state` is the issue's GitHub state (OPEN/CLOSED), surfaced
#     truthfully so the skill (PRSTEP-003) can treat a CLOSED exact match as a CONFLICT — the
#     classification JUDGMENT is the SKILL's, never baked into this script. `parent` is null
#     for an UNPARENTED (orphan) candidate and the {number,id} of the parent for an already-
#     attached child — the skill reads it to decide attach (parent null) vs reuse/skip
#     (already attached to the intended epic).
#
#   design-gate (one compact line, exit 0):
#     { "commit": <object-id>, "trunk": <str>,
#       "link_prefix": "https://github.com/<owner/repo>/blob/<trunk>/", "slug": <str>,
#       "ui": "yes"|"no"|"invalid"|"missing",
#       "result": "pass"|"refuse",
#       "reasons": [ <readiness reason code>, ... ] }
#     `reasons` is sorted and unique, and empty unless ui is yes. `result` is refuse ONLY when
#     ui is yes and reasons is non-empty; otherwise pass. Each Design link the skill writes is
#     `link_prefix` plus the path.
#
# 4. INVARIANTS
# -------------
#   - SINGLE SHARED RESPONSE-SHAPE KERNEL: EVERY live gh/GraphQL read that informs a
#     decision or that is emitted as a result routes through validate_response_shape
#     before any processing. No per-site hand-parsing of response shape is permitted.
#     A non-clean response — transport error (empty/non-JSON), a non-empty `.errors`
#     envelope, null/missing entity at the expected root path, non-array collection,
#     or a null/wrong-typed field on any element — FAILS CLOSED (nonzero, structured
#     kind record to stderr) before any decision or emission. Covered reads:
#     ensure-parent's repository.issue resolve/normalize (with --slug, its body too),
#     ensure-parent's repository.label read of the epic label, list-children's per-page subIssues response (before accumulation), design-gate's
#     defaultBranchRef trunk read. No subcommand bypasses this kernel.
#   - SHARED READINESS CHECK LIBRARY. The script sources
#     ${CLAUDE_PLUGIN_ROOT}/skills/_shared/readiness-check.sh with the canonical ADR-0020
#     prologue (C1 self-location, C2 shared dir, C4 source-or-die; emitter subissue_ops_fail,
#     exit 2), so EVERY subcommand needs the library present and parseable. The seed marker parse,
#     the Document existence test, document reads and the review record front matter parse are
#     the library's; this script never re-implements them and never reads a document by branch
#     name, local ref or working-tree path.
#   - NATIVE SUB-ISSUES, NOT LABELS. This script wires the first-class GitHub
#     parent/child hierarchy; it NEVER reads, writes, or grooms any `initiative:*` label.
#     Grouping is the native relationship, full stop. The ONLY label it touches is
#     `type:epic` on the epic ensure-parent returns, and only by adding it: it may create the
#     missing repository label, but never edits an existing label and never removes one.
#   - addSubIssue FIELD MAPPING IS LOAD-BEARING: input `issueId` = the PARENT node,
#     `subIssueId` = the CHILD node. This is NOT the dependency API's
#     `blockingIssueId`. build_attach_payload and the mutation source are the SINGLE
#     SOURCE of this mapping so the two can never diverge.
#   - GraphQL-Features HEADER ON EVERY SUB-ISSUE CALL. Sub-issues are GA (2025) but
#     the GraphQL surface is gated behind `-H "GraphQL-Features: sub_issues"`. EVERY
#     live `gh api graphql` call in this script sends it via the single $GQL_HEADER
#     constant (one source, no per-site divergence). Absent it the API may 404/reject;
#     the script ALWAYS sends it and, if the API STILL rejects, FAILS CLOSED with a
#     clear error — it NEVER silently succeeds or no-ops.
#   - ADD-ONLY. attach-subissue never detaches an existing sub-issue; reparenting /
#     removal is a human decision outside this script.
#   - A GitHub rejection of an attach that is EXPECTED and non-fatal — the child
#     already has a parent, or the link would form a cycle — is surfaced as a warning
#     record (kind already-parented / cycle-rejected) with exit 0, so a batch attach
#     keeps going (slices are independent). EVERY other failure FAILS CLOSED.
#   - PAGINATE TO COMPLETENESS (issue #228 lesson). list-children follows the
#     subIssues connection across ALL pages; a partial read is never emitted as if
#     complete (live: loop on hasNextPage; offline: an injected page asserting
#     hasNextPage==true FAILS CLOSED).
#   - Untrusted issue body/title is DATA: it flows ONLY through `gh issue create`
#     flags (--title / --body / --body-file) and `gh api graphql -f/-F` / jq
#     --arg/--argjson; it is NEVER interpolated into shell source or into GraphQL
#     query source. Node IDs are validated non-empty before use. GraphQL variables
#     are passed via -f/-F, never string-concatenated.
#   - FAIL-CLOSED on malformed injected input to a pure transform (bad --response-file,
#     unreadable injection file, a continued offline page) — a malformed fixture is a
#     usage bug, not noise.
#   - PARENT ORPHAN-SAFETY IS CLOSED-BY-CONSTRUCTION. Across sequential runs and reruns,
#     ensure-parent never blind-creates a second epic: with no --existing-number it
#     DISCOVERS-BY-TITLE first (reusing the SINGLE
#     SHARED ENUMERATION machinery find-by-title uses — repository.issues enumeration +
#     paginate_to_completeness + filter_exact_title, never a divergent second lookup), resolves
#     a lone OPEN exact match (status resolved-by-title), creates ONLY on zero matches, and
#     FAILS CLOSED on a multiple/CLOSED/divergent set rather than duplicating or reusing a
#     closed epic. The same owner/repo charset guard find-by-title enforces is applied to the
#     discovery enumeration path.
#     THREAT MODEL: discovery and `gh issue create` are two GitHub calls, and GitHub issues
#     have no create-if-absent. Two runs publishing the same initiative at once that both
#     find zero exact-title matches each create an epic and return different epics, in all
#     three create branches (--body-file -, --body-file <path>, --body). The skill's
#     per-slice find-by-title-then-create has the same window. That race is outside the
#     threat model: one run publishes an initiative at a time, and concurrent publishes of
#     the same initiative are unsupported. Recorded per
#     ${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md (Recorded Residual), on the
#     user's decision of 2026-11-27, local review finding 5f28677a. The impact is bounded:
#     duplicate open issues, visible and reversible by closing them; no data loss, no body
#     or title edit, no trust boundary crossed. A later run fails closed on the duplicates
#     (resolve_discovery, kind ambiguous-epic), and the seed and --existing-number paths
#     create no epic. Still in scope: concurrent runs for different initiatives, and the
#     `type:epic` label create race, which ensure_epic_label closes by rereading the label
#     after a failed create, because label names are unique per repository. A need to
#     support concurrent publishes of one initiative reopens this as a filed issue.
#   - TITLE-EXISTENCE IS A DETERMINISTIC ENUMERATION, NOT A FUZZY SEARCH. The title-lookup
#     enumerates `repository.issues` (a terminally-paginated connection) and matches the title
#     LOCALLY as jq --arg DATA. It NEVER feeds the untrusted title into GitHub's ranked
#     full-text `search` API as a query string. This dissolves by construction the whole class
#     of search-as-existence-oracle defects (DSL quote-breakout, qualifier injection,
#     is:issue/PR leak, 1000-result truncation) — there is no query string for the title to
#     break, and the connection has a real terminal page (no relevance cap to guard).
#
# 5. OFFLINE TEST SEAM (STEP-002 depends on this)
# -----------------------------------------------
# Set env SUBISSUE_OPS_OFFLINE to any non-empty value to make EVERY subcommand skip
# ALL gh/network calls and instead drive its pure transform over INJECTED input,
# emitting the deterministic artifact (parent record / attach payload / surfaced
# record / normalized children / title-match candidates) to stdout. Input that would
# normally come from gh is injected via --response-file (ensure-parent, attach-subissue,
# list-children, find-by-title); ensure-parent's PRE-CREATE discovery enumeration is injected via
# the dedicated --discovery-response-file seam (a repository.issues ENUMERATION response, distinct
# from the --response-file repository.issue response); design-gate's trunk read is injected via
# --trunk-response-file (a repository.defaultBranchRef response; the fetch is skipped and the
# documents are still read at that commit from the local object store); attach-subissue's
# payload-build artifact instead needs the explicit --emit-payload opt-in (offline attach with NEITHER flag FAILS CLOSED). The
# fixture flags are honored ONLY when SUBISSUE_OPS_OFFLINE is set; a live invocation
# supplying any is REJECTED fail-closed (exit 2) BEFORE any gh call via the single
# shared guard reject_fixture_flags_in_live_mode (one mechanism, no per-subcommand
# divergence) — they are test seams, not live caller payloads, and would otherwise let
# a fixture spoof a created/attached/child/resolved-by-title state for a mutation that never
# ran. Use `-` for stdin on any *-file flag. The pure transforms are factored as functions
# reading from injected input (build_attach_payload, surface_attach_response,
# normalize_parent_resolve, normalize_parent_seed, normalize_trunk_ref, normalize_children,
# normalize_find_by_title, resolve_discovery) so the test can drive each directly via the
# offline CLI with only jq + bash, no `gh`. Mirrors
# triage-ops.sh's --response-file injection.

set -euo pipefail

subissue_ops_fail() { printf 'subissue-ops: %s\n' "$1" >&2; exit 2; }

script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || subissue_ops_fail "cannot self-locate the script directory; refusing to proceed"
shared_dir="$(CDPATH= cd -- "$script_dir/../../_shared" 2>/dev/null && pwd -P 2>/dev/null)" || subissue_ops_fail "cannot resolve skills/_shared from the script directory; refusing to proceed"
[ -f "$shared_dir/readiness-check.sh" ] || subissue_ops_fail "required shared library missing: skills/_shared/readiness-check.sh; refusing to proceed"
# shellcheck source=../../_shared/readiness-check.sh
. "$shared_dir/readiness-check.sh" || subissue_ops_fail "failed to source skills/_shared/readiness-check.sh (unparseable); refusing to proceed"

PROG="subissue-ops"

# SINGLE SOURCE of the sub-issues GraphQL feature header. EVERY live `gh api graphql`
# call in this script passes `-H "$GQL_HEADER"`; the GA sub-issue surface is gated
# behind it (see INVARIANT §4). Splice via the array idiom `"${GQL_HEADER_ARGS[@]}"`.
GQL_HEADER="GraphQL-Features: sub_issues"
GQL_HEADER_ARGS=(-H "$GQL_HEADER")

die() {
  # Structured, nonzero failure to stderr — propagate, never swallow. A message may quote a
  # rejected untrusted value, so every control byte is dropped before it reaches a terminal or log.
  printf '%s' "$PROG: $1" | LC_ALL=C tr -d '\000-\037\177' >&2
  printf '\n' >&2
  exit "${2:-1}"
}

require_gh() {
  command -v gh >/dev/null 2>&1 \
    || die "the '$1' subcommand requires the 'gh' CLI on PATH (offline mode: set SUBISSUE_OPS_OFFLINE)" 1
}

is_offline() {
  [ -n "${SUBISSUE_OPS_OFFLINE:-}" ]
}

# reject_fixture_flags_in_live_mode <subcommand> <flag-name>=<value> [<flag-name>=<value> ...]
# UNIFIED offline-test-seam gate (mirrors triage-ops). Fixture/injection flags
# (--response-file) are honored ONLY when SUBISSUE_OPS_OFFLINE is set; supplying one
# on a LIVE invocation could spoof a created/attached/child state for a mutation that
# never ran. So: when NOT offline, any passed flag whose value is non-empty fails
# CLOSED with exit 2 BEFORE any require_gh/gh/graphql call (so STEP-002's live-reject
# tests run with no gh on PATH). Receives the ALREADY-PARSED flag value(s) as
# arguments — it does NOT re-parse argv (P9). Each arg is "<flag-name>=<value>"; only
# the value is tested, the name is used solely for the diagnostic message.
reject_fixture_flags_in_live_mode() {
  local subcmd="$1"; shift
  is_offline && return 0
  local pair flag value
  for pair in "$@"; do
    flag="${pair%%=*}"
    value="${pair#*=}"
    [ -z "$value" ] \
      || die "$subcmd: $flag is valid only with SUBISSUE_OPS_OFFLINE set" 2
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

# assert_owner_repo <subcmd> <owner/repo>: the SINGLE SOURCE owner/repo charset guard,
# shared by find-by-title AND ensure-parent's pre-create discovery search so the two cannot
# diverge (ensure-parent's create path previously did only the weak `*/*` glob; the discovery
# path now applies this stronger guard). Split on the single `/`, gate each half against the
# GitHub name charset BEFORE any gh/GraphQL call. owner_repo flows into the search DSL via -f
# as DATA, but a malformed value is a usage bug, not a broadened query — fail CLOSED (exit 2).
# Replaces the weak `*/*` glob, which admitted e.g. `a/b/c` or shell metacharacters.
assert_owner_repo() {
  local subcmd="$1" owner_repo="$2" owner_part repo_part
  case "$owner_repo" in */*) ;; *) die "$subcmd: --repo must be owner/repo (got '$owner_repo')" 2 ;; esac
  owner_part="${owner_repo%%/*}"; repo_part="${owner_repo#*/}"
  case "$owner_part" in ''|*[!A-Za-z0-9._-]*) die "$subcmd: invalid repo owner (got '$owner_part')" 2 ;; esac
  case "$repo_part" in ''|*/*|*[!A-Za-z0-9._-]*) die "$subcmd: invalid repo name (got '$repo_part')" 2 ;; esac
}

# assert_node_id <flag-name> <value>: DEFENSE-IN-DEPTH node-id allowlist (ADR-0020 trust
# boundary). Applied at every node-id-bearing subcommand entry (attach-subissue
# --parent-id/--child-id, list-children --parent-id, find-by-title's resolved parent id)
# BEFORE any gh/GraphQL use. Node ids already flow ONLY through gh `-f/-F` as DATA (never
# interpolated into shell or GraphQL source), so this is a belt-and-suspenders floor, not
# the primary boundary. Charset: ^[A-Za-z0-9_=-]+$ — admits modern `I_kw...` ids AND
# legacy base64 `==`-padded ids (`=` IS allowed); charset-only, no length/prefix bound.
# Deliberately NOT _shared/allowlist.sh's identifier class, whose ^[A-Za-z0-9._/-]+$ omits
# `=` and would false-reject legacy ids. Fails CLOSED (exit 2) on any out-of-charset byte.
assert_node_id() {
  local flag="$1" value="$2"
  case "$value" in
    '') die "$flag must be a non-empty node id" 2 ;;
    *[!A-Za-z0-9_=-]*) die "$flag contains an invalid node id (allowed charset: A-Za-z0-9_=-)" 2 ;;
  esac
}

# assert_slug <subcmd> <slug>: the initiative slug gate shared by ensure-parent --slug and
# design-gate --slug. The slug must match ^[a-z0-9]+(-[a-z0-9]+)*$; it is checked BEFORE any
# gh/git call and fails CLOSED (exit 2) otherwise.
assert_slug() {
  local subcmd="$1" slug="$2"
  case "$slug" in
    ''|-*|*-|*--*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
      die "$subcmd: --slug must match ^[a-z0-9]+(-[a-z0-9]+)*\$ (got '$slug')" 2 ;;
  esac
}

# assert_git_identifier <subcmd> <label> <value>: the identifier gate design-gate applies to the
# trunk name and the remote name before either reaches git. Charset ^[A-Za-z0-9._/-]+$, with no
# leading `-` and no `..`; fails CLOSED (exit 2) otherwise. The rejected value is never echoed:
# the trunk name is GitHub-supplied text.
assert_git_identifier() {
  local subcmd="$1" label="$2" value="$3"
  case "$value" in
    ''|-*|*..*|*[!A-Za-z0-9._/-]*) die "$subcmd: invalid $label (allowed charset: A-Za-z0-9._/-, no leading '-', no '..')" 2 ;;
  esac
}

# --- Pure transform core (offline-exercisable; no gh) ------------------------

# validate_response_shape <resp> <root_path> <root_pred> <coll_path> <elem_pred> <projection>:
# the SINGLE SOURCE fail-closed GraphQL/response-shape validator+normalizer (P1).
# Byte-for-byte the same contract as triage-ops.sh's kernel (one shape mechanism
# across the plugin's GraphQL scripts). Pure jq+bash, no gh — offline-exercisable.
# Given a RAW response string and a PROJECTION SPEC (author-static jq fragments
# passed as the 2nd..6th args), it REJECTS fail-closed (nonzero, structured kind
# record to stderr) any of:
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
#                 `.data.node`); fail-closed when it is null/missing.
#   <root_pred>   jq boolean over that entity bound as `.` (field-completeness on
#                 the root).
#   <coll_path>   jq path FROM the root entity to the node collection (e.g.
#                 `.subIssues.nodes`); fail-closed when not an array.
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
  # Shape + field-completeness gate (root non-null, collection is an array, the root
  # and EVERY element satisfy their completeness predicate). The fragments are
  # spliced into the jq PROGRAM (author-static), never into the DATA.
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

# normalize_parent_resolve <response-json>: project a raw repository.issue GraphQL
# response (used by ensure-parent's resolve path and its post-create node-id read)
# into the parent identity { number, id }. FAIL-CLOSED via the shared kernel: a
# transport error, `.errors` envelope, null/missing issue node, or a null/wrong-typed
# number/id field, or a number that is not a positive integer, exits nonzero — never emit a parent record built from an
# unverifiable read. The issue node carries no collection of interest, so the kernel's
# collection slot is `[]` (a trivially-valid empty array) and there is no element
# predicate. <status> is spliced as DATA via --arg to tag the record created/resolved.
# Exit codes: 0 = normalized; 1 = fail-closed.
normalize_parent_resolve() {
  local resp="$1" status="$2"
  validate_response_shape "$resp" \
    '.data.repository.issue' \
    '(.number | type == "number" and . >= 1 and . == floor)
     and (.id | type == "string" and length > 0)' \
    '[]' \
    'true' \
    "{ number: .data.repository.issue.number,
       id: .data.repository.issue.id,
       status: \"$status\" }"
}

# normalize_parent_seed <response-json> <slug>: project a raw repository.issue GraphQL response
# that also carries the issue `body` (ensure-parent --slug) into { number, id, status:"resolved",
# seed }. FAIL-CLOSED via the shared kernel: on top of normalize_parent_resolve's checks, the
# body must be a string. The body reaches the shared library's hivemind_seed_marker_slug ONLY on
# stdin (never argv, never program text); `seed` is true only when that function prints exactly
# <slug>. A marker naming another slug, or no marker, gives seed false. A library failure other
# than "no marker" (exit 1) fails closed. Exit codes: 0 = normalized; 1 = fail-closed.
normalize_parent_seed() {
  local resp="$1" slug="$2" validated marker="" marker_rc=0 seed=false
  validated="$(validate_response_shape "$resp" \
    '.data.repository.issue' \
    '(.number | type == "number" and . >= 1 and . == floor)
     and (.id | type == "string" and length > 0)
     and (.body | type == "string")' \
    '[]' \
    'true' \
    '.data.repository.issue | { number, id, body }')" || return 1
  marker="$(printf '%s' "$validated" | jq -j '.body' | hivemind_seed_marker_slug)" || marker_rc=$?
  case "$marker_rc" in
    0) if [ "$marker" = "$slug" ]; then seed=true; fi ;;
    1) ;;
    *) die "ensure-parent: seed marker parse failed" 1 ;;
  esac
  printf '%s' "$validated" | jq -c --argjson seed "$seed" \
    '{ number, id, status: "resolved", seed: $seed }'
}

# normalize_trunk_ref <response-json>: project a raw repository.defaultBranchRef GraphQL response
# (design-gate's trunk read) into { name, oid }. FAIL-CLOSED via the shared kernel: a transport
# error, `.errors` envelope, null/missing defaultBranchRef, or a non-string/empty name or
# target.oid exits nonzero. The trunk ref carries no collection, so the collection slot is `[]`.
# Exit codes: 0 = normalized; 1 = fail-closed.
normalize_trunk_ref() {
  local resp="$1"
  validate_response_shape "$resp" \
    '.data.repository.defaultBranchRef' \
    '(.name | type == "string" and length > 0)
     and (.target | type == "object")
     and (.target.oid | type == "string" and length > 0)' \
    '[]' \
    'true' \
    '.data.repository.defaultBranchRef | { name, oid: .target.oid }'
}

# normalize_children <response-json>: project a raw node(id:) subIssues GraphQL page
# into the stable list-children schema (§3) — FAIL-CLOSED via the shared kernel. A
# subIssues read carries NO recoverable failure: EVERY failure exits nonzero so the
# caller never makes attach decisions from a corrupted-into-"no children" state.
# Fail-closed on: empty/non-JSON transport, any `.errors`, missing/null `.data.node`,
# missing/non-array `subIssues.nodes`, any null/wrong-typed child identifier
# (number/id/title), AND — mirroring deps-read's #228 lesson — a NON-TERMINAL page:
# `subIssues.pageInfo.hasNextPage` MUST be a genuine boolean `false`. A missing/null/
# non-boolean `hasNextPage` FAILS CLOSED (no `// false` default — a response whose
# pageInfo is absent/null is NOT silently treated as complete), and a `true` value also
# fails closed: the offline seam injects a SINGLE page and treats it as COMPLETE, so a
# continued or unverifiable-terminal page would normalize as if the unfetched children
# do not exist; that partial read is failed closed rather than emitted. (The
# LIVE path follows endCursor across all pages, so live completeness is enforced by
# the loop, not this normalizer — see cmd_list_children.) The parent_id is captured
# from .data.node.id. Exit codes: 0 = normalized; 1 = fail-closed.
normalize_children() {
  local resp="$1"
  validate_response_shape "$resp" \
    '.data.node' \
    '(.id | type == "string" and length > 0)
     and (.subIssues.pageInfo.hasNextPage | type == "boolean")
     and (.subIssues.pageInfo.hasNextPage == false)' \
    '.subIssues.nodes' \
    '(.number | type == "number" and . >= 1 and . == floor)
     and (.id | type == "string" and length > 0)
     and (.title | type == "string" and length > 0)' \
    '.data.node as $n
     | { parent_id: ($n.id // null),
         children: [ ($n.subIssues.nodes)[] | { number, id, title } ] }'
}

# normalize_find_by_title <response-json> <title>: project a raw repository.issues
# enumeration GraphQL response into the find-by-title schema (§3) — FAIL-CLOSED via the shared
# kernel, then EXACT-title post-filtered. Two passes:
#   1. validate_response_shape gates the SHAPE: root `.data.repository.issues` non-null, `.nodes`
#      an array, and EVERY node carries a string id (len>0), a number, a string title (len>0),
#      AND a string state (len>0) — a state-less node FAILS CLOSED, same posture as the other
#      identity fields. The `parent` field is OPTIONAL per node (null when unparented), so it
#      is NOT in the element predicate; it is normalized to {number,id}|null in pass 2.
#   2. a jq pass binds the UNTRUSTED title as DATA via --arg and keeps ONLY nodes whose
#      `.title == $title` byte-for-byte (the enumeration is unfiltered; this selects exact-title),
#      emitting each match's `state` (OPEN/CLOSED) truthfully (closed-child CONFLICT judgment is
#      the SKILL's job). The title is NEVER interpolated into the jq program — it flows via --arg.
# A transport error, `.errors` envelope, null repository.issues root, non-array nodes, or any node
# missing a required identity field FAILS CLOSED (nonzero) — a candidate set built from an
# unverifiable read is never emitted. Exit codes: 0 = normalized; 1 = fail-closed.
normalize_find_by_title() {
  local resp="$1" title="$2" validated
  # OFFLINE shape gate: root `.data.repository.issues` non-null, `.nodes` an array, EVERY node
  # carries a string id/number/title/state — AND a TERMINAL-PAGE gate mirroring normalize_children:
  # the injected offline page is treated as the COMPLETE result set, so its
  # `repository.issues.pageInfo.hasNextPage` MUST be a genuine boolean `false` (no `// false`
  # default — a missing/null/non-boolean OR a `true` hasNextPage FAILS CLOSED, so an injected page
  # that is not a genuine terminal page cannot normalize as if the unfetched candidates do not
  # exist). The LIVE path enforces completeness via the pagination loop, not this gate.
  validated="$(validate_response_shape "$resp" \
    '.data.repository.issues' \
    '(.pageInfo.hasNextPage | type == "boolean")
     and (.pageInfo.hasNextPage == false)' \
    '.nodes' \
    '(.number | type == "number" and . >= 1 and . == floor)
     and (.id | type == "string" and length > 0)
     and (.title | type == "string" and length > 0)
     and (.state | type == "string" and length > 0)' \
    '.data.repository.issues.nodes')" || return 1
  filter_exact_title "$validated" "$title"
}

# filter_exact_title <nodes-json-array> <title>: the SINGLE SOURCE exact-title post-filter
# (shared by the offline normalize_find_by_title path AND the live paginate-to-completeness
# path, so the exactness contract can never diverge). The enumeration is unfiltered; this keeps
# ONLY nodes whose `.title` EQUALS the queried title byte-for-byte and wraps them in the §3
# {title, matches:[{number,id,title,state,parent}]} schema. Each match carries the issue's
# `state` (OPEN/CLOSED) truthfully — the SCRIPT only SURFACES it; the closed-child CONFLICT
# JUDGMENT is the SKILL's job, never baked in here. The UNTRUSTED title enters ONLY as --arg
# DATA — it is NEVER interpolated into the jq program.
filter_exact_title() {
  local nodes="$1" title="$2"
  printf '%s' "$nodes" | jq -c --arg title "$title" \
    '{ title: $title,
       matches: [ .[]
                  | select(.title == $title)
                  | { number, id, title, state,
                      parent: ( if (.parent != null) then { number: .parent.number, id: .parent.id } else null end ) } ] }'
}

# resolve_discovery <find-by-title-json>: the PURE discovery resolution transform for
# ensure-parent's orphan-safety (Q2 DECISION). Input is the filter_exact_title output
# ({title, matches:[{number,id,title,state,parent}]}) over the EXACT epic title. It applies
# the resolution rules and emits a DECISION on stdout (exit 0) or FAILS CLOSED (exit 1).
#
# COMPLETE CANDIDATE-STATE VALIDATION (closes the candidate-validation-completeness class per
# issue #273 — closed-by-construction). A lone-epic resolution is SAFE only when the COMPLETE
# attribute tuple of the candidate holds, validated EXPLICITLY and EXHAUSTIVELY in ONE place so a
# reviewer can see by inspection that NO attribute is left unchecked. The three required
# attributes are:
#       count  == 1        (exactly one exact-title match)
#   AND state  == "OPEN"   (that match is open)
#   AND parent == null     (that match is UNPARENTED — an epic, not a CHILD sub-issue of some
#                           other epic; the `parent` field is already projected by
#                           filter_exact_title, so the predicate consults it directly)
# Resolution outcomes:
#   - the COMPLETE tuple {count==1, OPEN, parent==null} holds -> emit the parent record
#     { number, id, status: "resolved-by-title" } (the caller emits it verbatim). This is the
#     ONLY shape that resolves; it is gated on ALL THREE attributes, never a subset.
#   - ZERO matches -> emit { action: "create" } (the caller proceeds to create).
#   - ANY other non-empty shape -> FAIL CLOSED (structured record to stderr, exit 1). This single
#     branch subsumes EVERY unsafe candidate state by construction:
#       * MULTIPLE exact matches (count>1)                  -> ambiguous, never blind-pick.
#       * the lone match is CLOSED (state!="OPEN")          -> never reuse a closed epic.
#       * the lone match is OPEN but PARENTED (parent!=null)-> it is a CHILD sub-issue, not an
#                                                              epic; surface, never reuse.
# Because the resolve branch validates the WHOLE tuple, no future single-missing-conjunct finding
# of this shape can recur: a candidate not matching ALL THREE required attributes fails closed.
# Pure jq — offline-exercisable.
resolve_discovery() {
  local matches_json="$1" decision
  decision="$(printf '%s' "$matches_json" | jq -c '
        .matches as $m
        | if   ($m | length) == 0
          then { action: "create" }
          # COMPLETE candidate-state tuple: ALL THREE attributes must hold to resolve.
          # {count==1, state=="OPEN", parent==null} — see header (closes #273 class).
          elif ($m | length) == 1
               and ($m[0].state  == "OPEN")
               and ($m[0].parent == null)
          then { number: $m[0].number, id: $m[0].id, status: "resolved-by-title" }
          else { action: "fail" } end')" || {
    jq -c -n '{ status:"error", kind:"discovery-malformed",
                message:"could not evaluate discovery matches" }' >&2
    return 1
  }
  case "$(printf '%s' "$decision" | jq -r '.action // "ok"')" in
    fail)
      printf '%s' "$matches_json" | jq -c \
        '{ status:"error", kind:"ambiguous-epic",
           message:"discovery found multiple exact-title matches, a closed match, or a lone OPEN match that is itself a parented child — refusing to create or reuse",
           matches: .matches }' >&2
      return 1 ;;
    *)
      printf '%s\n' "$decision"
      return 0 ;;
  esac
}

# build_attach_payload <parent-id> <child-id>: the GraphQL variables for the
# addSubIssue mutation. Pure jq construction — node ids pass through as DATA.
# CRITICAL: issueId = the PARENT, subIssueId = the CHILD (NOT blockingIssueId — see
# INVARIANT §4). This function and DEPS-style mutation source are the single source
# of the field mapping.
build_attach_payload() {
  jq -c -n --arg issueId "$1" --arg subIssueId "$2" \
    '{ issueId: $issueId, subIssueId: $subIssueId }'
}

# surface_attach_response <response-json>: classify a raw addSubIssue GraphQL response
# into a structured record AND signal recoverability via exit code (mirrors triage-ops'
# surface_dep_response). A GraphQL `.errors` array becomes an exit-0 warning ONLY when
# EVERY error names an EXPECTED, non-fatal sub-issue rejection — the child already has
# a parent (already-parented) or the link would form a cycle (cycle-rejected). A MIXED
# array (an expected rejection alongside ANY other error — auth, rate-limit, schema, a
# missing sub_issues feature header) is FAIL-CLOSED: the non-recoverable sibling marks
# a genuine write failure that a first-error-only check would mask. EVERY other failure
# is FAIL-CLOSED and exits nonzero so the caller never proceeds as if a sub-issue were
# attached when none was: empty/non-JSON transport errors, a success body missing the
# expected addSubIssue issue numbers, and any array containing a non-recoverable error.
# The record is still emitted on stdout (recoverable) or stderr (fail-closed) for
# diagnostics; the EXIT CODE is the gate. See INVARIANT §4.
# Exit codes: 0 = attached | already-parented | cycle-rejected; 1 = fail-closed.
surface_attach_response() {
  local resp="$1"
  # Empty / non-JSON => transport error. Fail closed: record to stderr, exit 1.
  if ! printf '%s' "$resp" | jq -e . >/dev/null 2>&1; then
    jq -c -n '{ status:"warning", kind:"transport-error",
                message:"empty or non-JSON response from addSubIssue" }' >&2
    return 1
  fi
  # Single classification pass (always exits 0): emit the structured record. The
  # record's `kind` is the gate the caller honors — `attached`, `already-parented`,
  # and `cycle-rejected` are recoverable (exit 0); every other kind is fail-closed
  # (exit 1). Recoverable ONLY when EVERY error matches a known non-fatal pattern; a
  # single other sibling fails the whole array closed (a first-error-only check would
  # mask a real write failure, e.g. a missing sub_issues feature-header rejection).
  local record kind
  record="$(printf '%s' "$resp" | jq -c '
        if ((.errors // []) | length) > 0
        then
          (.errors | map(.message // "")) as $msgs
          | if   ($msgs | all(test("already (has|been added).*parent|already a sub-?issue|already parented"; "i")))
            then { status: "warning", kind: "already-parented",
                   message: ($msgs[0] // "child already has a parent") }
            elif ($msgs | all(test("cycl|circular"; "i")))
            then { status: "warning", kind: "cycle-rejected",
                   message: ($msgs[0] // "addSubIssue rejected: cycle") }
            else { status: "warning", kind: "error",
                   message: ($msgs | map(select(test("already (has|been added).*parent|already a sub-?issue|already parented|cycl|circular"; "i") | not)))[0] } end
        elif (.data.addSubIssue.issue.number != null
              and .data.addSubIssue.subIssue.number != null)
        then { status: "attached",
               parent: (.data.addSubIssue.issue.number),
               child:  (.data.addSubIssue.subIssue.number) }
        else { status: "warning", kind: "error",
               message: "addSubIssue response missing expected issue numbers" }
        end')"
  kind="$(printf '%s' "$record" | jq -r '.kind // "attached"')"
  case "$kind" in
    attached|already-parented|cycle-rejected)  # recoverable: stdout, caller continues.
      printf '%s\n' "$record"; return 0 ;;
    *)  # error (and any unknown): fail closed.
      printf '%s\n' "$record" >&2; return 1 ;;
  esac
}

# --- Baked GraphQL operations (live path only) -------------------------------
# Native GitHub sub-issues (issue hierarchy), GA 2025. Spec citation:
# https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues
# and the GraphQL mutation `addSubIssue(input: AddSubIssueInput!)` — input fields
# `issueId` (the PARENT) + `subIssueId` (the CHILD); the Issue.subIssues connection
# reads the child set. The GraphQL surface is feature-gated: every call sends
# `-H "$GQL_HEADER"` (GraphQL-Features: sub_issues). Variables are passed via -f/-F
# (never interpolated); external issue text is never read into source.
PARENT_RESOLVE_QUERY='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      number
      id
    }
  }
}'

PARENT_SEED_QUERY='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      number
      id
      body
    }
  }
}'

# INVARIANT: the epic label's name, color and description equal the `type:epic` entry of
# triage_palette and the description cmd_ensure_labels gives a `type` family label, both in
# ${CLAUDE_PLUGIN_ROOT}/skills/triage-backlog/scripts/triage-ops.sh. tools/test_subissue_ops.sh
# (case ensure-parent:label-matches-triage-palette) runs both scripts and pins the agreement.
EPIC_LABEL="type:epic"
EPIC_LABEL_COLOR="3e4b9e"
EPIC_LABEL_DESCRIPTION="triage type rating"

# ensure_epic_label's label read: the repository's label named $label, or null when it has none
# (owner/name/label via gh -f as DATA).
EPIC_LABEL_QUERY='
query($owner: String!, $name: String!, $label: String!) {
  repository(owner: $owner, name: $name) {
    label(name: $label) {
      name
    }
  }
}'

# design-gate's trunk read: the default branch name and its commit id (owner/name via gh -f as DATA).
TRUNK_REF_QUERY='
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    defaultBranchRef {
      name
      target { oid }
    }
  }
}'

SUBISSUES_QUERY='
query($id: ID!, $after: String) {
  node(id: $id) {
    ... on Issue {
      id
      subIssues(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes { id number title }
      }
    }
  }
}'

ADD_SUBISSUE_MUTATION='
mutation($issueId: ID!, $subIssueId: ID!) {
  addSubIssue(input: { issueId: $issueId, subIssueId: $subIssueId }) {
    issue { id number }
    subIssue { id number }
  }
}'

# find-by-title / discovery: ENUMERATE the repository's issues deterministically (owner/name
# bound as DATA via gh -f, the GitHub-issued cursor via -F — NEITHER ever interpolated into this
# source, and the untrusted title NEVER enters this query at all). states:[OPEN,CLOSED] so a
# closed exact match is surfaced (the SKILL classifies CONFLICT). Returns each issue's identity +
# its sub-issue `parent` (null when unparented; `parent` is a sub-issue field, so the
# GraphQL-Features: sub_issues header is required on every call). The exact-title match is a
# LOCAL jq --arg post-filter (filter_exact_title) over the fully-paginated set — there is no
# query-string search, hence no DSL/quote/qualifier/PR-leak/truncation class to neutralize.
ISSUES_BY_REPO_QUERY='
query($owner: String!, $name: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, after: $after, states: [OPEN, CLOSED]) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        id
        title
        state
        parent { number id }
      }
    }
  }
}'

# paginate_to_completeness: the SINGLE SHARED paginate-to-completeness mechanism (P1)
# driving BOTH cmd_list_children (node.subIssues) and the title-lookup (repository.issues). It
# follows endCursor while hasNextPage, routes EVERY raw page through the shared kernel
# BEFORE accumulation (a malformed/error page FAILS CLOSED mid-loop, never emitting a
# partial set as complete), accumulates the cleaned node objects across pages, and
# emits the FULLY-ACCUMULATED node array (compact JSON) on stdout. The per-page root
# predicate is VALUE-AGNOSTIC on hasNextPage (must be a boolean — present/null/non-bool
# fails closed — but true is still accepted so the loop keeps paging); the loop, not the
# kernel, drives completeness. Fails closed when hasNextPage is true but endCursor is
# empty (GitHub-issued cursor missing). The cursor `$after` is GitHub-issued DATA passed
# via -F, never interpolated into source. Both driven connections (subIssues, repository.issues)
# are DETERMINISTIC and terminally paginated — there is no ranked-search relevance cap, so the
# loop trusts hasNextPage==false as genuinely complete (no truncation guard is needed).
#
# Args:
#   $1 label        — diagnostic prefix for die() messages (the subcommand name)
#   $2 query        — the GraphQL query const
#   $3 root_path    — jq path to the entity holding the collection (e.g. .data.node)
#   $4 root_pred    — jq boolean over that entity; MUST gate hasNextPage|type=="boolean"
#   $5 coll_path    — jq path FROM root to the node array (e.g. .subIssues.nodes)
#   $6 elem_pred    — jq boolean per element (field completeness)
#   $7 pageinfo     — jq path FROM root to the pageInfo object (e.g. .subIssues.pageInfo)
#   $8.. base_args  — the FIXED gh query-arg pair(s) identifying the connection
#                     (e.g. -f id=<NODE_ID> or -f owner=<OWNER> -f name=<REPO>); $after is
#                     appended by this loop, never by the caller.
paginate_to_completeness() {
  local label="$1" query="$2" root_path="$3" root_pred="$4" coll_path="$5" elem_pred="$6" pageinfo="$7"
  shift 7
  local -a base_args=("$@")
  local after="" page projected accumulated="[]" has_next end_cursor
  while :; do
    if [ -z "$after" ]; then
      page="$(gh api graphql "${GQL_HEADER_ARGS[@]}" -f query="$query" \
                "${base_args[@]}" 2>/dev/null)" \
        || die "$label: GraphQL query failed" 1
    else
      page="$(gh api graphql "${GQL_HEADER_ARGS[@]}" -f query="$query" \
                "${base_args[@]}" -F after="$after" 2>/dev/null)" \
        || die "$label: GraphQL query failed" 1
    fi
    # Validate the raw page shape WITHOUT a hasNextPage==false gate (mid-pagination a
    # continued page is legitimate); the loop drives completeness. Project to this page's
    # clean nodes + its pageInfo for cursor advance. The root predicate (caller-supplied)
    # gates hasNextPage PRESENCE/TYPE (boolean) but is VALUE-AGNOSTIC on its value.
    projected="$(validate_response_shape "$page" \
      "$root_path" \
      "$root_pred" \
      "$coll_path" \
      "$elem_pred" \
      "{ nodes: (($root_path) | $coll_path),
         hasNextPage: (($root_path) | $pageinfo.hasNextPage),
         endCursor: (($root_path) | $pageinfo.endCursor // null) }")" \
      || die "$label: malformed page" 1
    accumulated="$(jq -c -n --argjson acc "$accumulated" --argjson page "$projected" \
      '$acc + $page.nodes')"
    has_next="$(printf '%s' "$projected" | jq -r '.hasNextPage')"
    end_cursor="$(printf '%s' "$projected" | jq -r '.endCursor // ""')"
    [ "$has_next" = "true" ] || break
    [ -n "$end_cursor" ] \
      || die "$label: connection reports hasNextPage but no endCursor" 1
    after="$end_cursor"
  done
  printf '%s' "$accumulated"
}

# read_epic_label_name <owner_repo>: prints the name of the repository's label named `type:epic`
# as GitHub returns it, or nothing when the repository has none. Reads it through the shared
# kernel (root `.data.repository`; label null, or an object with a non-empty string name). A read
# failure or a malformed read exits nonzero with nothing on stdout.
read_epic_label_name() {
  local owner_repo="$1" owner repo_name resp label_read
  owner="${owner_repo%%/*}"; repo_name="${owner_repo#*/}"
  resp="$(gh api graphql "${GQL_HEADER_ARGS[@]}" -f query="$EPIC_LABEL_QUERY" \
            -f owner="$owner" -f name="$repo_name" -f label="$EPIC_LABEL" 2>/dev/null)" \
    || die "ensure-parent: GraphQL read of label '$EPIC_LABEL' failed" 1
  label_read="$(validate_response_shape "$resp" \
    '.data.repository' \
    '(.label == null)
     or ((.label | type) == "object" and (.label.name | type == "string" and length > 0))' \
    '[]' \
    'true' \
    '.data.repository.label')" \
    || die "ensure-parent: malformed read of label '$EPIC_LABEL'" 1
  printf '%s' "$label_read" | jq -r 'if . == null then "" else .name end' \
    || die "ensure-parent: could not read the name of label '$EPIC_LABEL'" 1
}

# ensure_epic_label <owner_repo> <number>: give the epic issue <number> the `type:epic` label
# (live path only; the caller has validated owner_repo and ensured `gh` is on PATH). Reads the
# repository's label (read_epic_label_name). A missing label is created with the triage palette's
# color and description, never with --force; when that create fails, the label is read again and
# the run goes on only if it now reads exactly `type:epic` (a concurrent run created it). A label
# found under a name that is not exactly `type:epic` (e.g. `Type:Epic`) fails closed. Then adds
# the label to the issue. It never edits an existing label, never removes a label and never
# touches an issue's title or body. Any read, create or edit failure exits nonzero with nothing
# on stdout.
ensure_epic_label() {
  local owner_repo="$1" number="$2" label_name
  label_name="$(read_epic_label_name "$owner_repo")" || exit "$?"
  if [ -z "$label_name" ]; then
    if ! gh label create "$EPIC_LABEL" --color "$EPIC_LABEL_COLOR" \
        --description "$EPIC_LABEL_DESCRIPTION" -R "$owner_repo" >/dev/null; then
      label_name="$(read_epic_label_name "$owner_repo")" || exit "$?"
      [ "$label_name" = "$EPIC_LABEL" ] \
        || die "ensure-parent: gh label create '$EPIC_LABEL' failed" 1
    fi
  elif [ "$label_name" != "$EPIC_LABEL" ]; then
    die "ensure-parent: the repository's label '$label_name' is not exactly '$EPIC_LABEL'; refusing to label the epic" 1
  fi
  gh issue edit "$number" -R "$owner_repo" --add-label "$EPIC_LABEL" >/dev/null \
    || die "ensure-parent: gh issue edit failed to add label '$EPIC_LABEL' to issue #$number" 1
}

# record_issue_number <record> [<expected-number>]: prints the ensure-parent <record>'s number.
# It must be a positive integer and, when <expected-number> is given (a read addressed by
# number), equal to it; else it fails closed with nothing on stdout.
record_issue_number() {
  local record="$1" expected="${2-}" record_number
  record_number="$(printf '%s' "$record" | jq -r '.number')" \
    || die "ensure-parent: could not read the epic number from its record" 1
  case "$record_number" in
    '' | 0* | *[!0-9]*) die "ensure-parent: the epic record's number is not a positive integer" 1 ;;
  esac
  if [ -n "$expected" ]; then
    expected="${expected#"${expected%%[!0]*}"}"
    [ "$record_number" = "$expected" ] \
      || die "ensure-parent: the read of issue #$expected returned issue #$record_number" 1
  fi
  printf '%s' "$record_number"
}

# emit_labeled_record <owner_repo> <record> [<expected-number>]: label the epic the ensure-parent
# <record> names `type:epic` (ensure_epic_label), then print the record unchanged. The number is
# checked first (record_issue_number), so a wrong issue is never labeled. A labeling failure
# exits nonzero before anything reaches stdout.
emit_labeled_record() {
  local owner_repo="$1" record="$2" record_number
  record_number="$(record_issue_number "$record" "${3-}")" || exit "$?"
  ensure_epic_label "$owner_repo" "$record_number"
  printf '%s\n' "$record"
}

# --- Subcommand implementations ----------------------------------------------

cmd_ensure_parent() {
  local title="" body="" body_file="" repo="" existing_number="" response_file="" discovery_response_file=""
  local slug="" slug_given=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --title) [ "$#" -ge 2 ] || die "missing value for --title" 2
               title="$2"; shift 2 ;;
      --body) [ "$#" -ge 2 ] || die "missing value for --body" 2
               body="$2"; shift 2 ;;
      --body-file) [ "$#" -ge 2 ] || die "missing value for --body-file" 2
               body_file="$2"; shift 2 ;;
      --repo) [ "$#" -ge 2 ] || die "missing value for --repo" 2
               repo="$2"; shift 2 ;;
      --existing-number) [ "$#" -ge 2 ] || die "missing value for --existing-number" 2
               existing_number="$2"; shift 2 ;;
      --response-file) [ "$#" -ge 2 ] || die "missing value for --response-file" 2
               response_file="$2"; shift 2 ;;
      --discovery-response-file) [ "$#" -ge 2 ] || die "missing value for --discovery-response-file" 2
               discovery_response_file="$2"; shift 2 ;;
      --slug) [ "$#" -ge 2 ] || die "missing value for --slug" 2
               slug="$2"; slug_given="1"; shift 2 ;;
      *) die "ensure-parent: unexpected argument '$1'" 2 ;;
    esac
  done
  if [ -n "$existing_number" ]; then
    case "$existing_number" in ''|*[!0-9]*) die "ensure-parent: --existing-number must be an integer (got '$existing_number')" 2 ;; esac
  fi

  # --discovery-response-file is meaningful ONLY on the create path (no --existing-number) —
  # with an idempotency key supplied there is nothing to discover. Reject the combination as a
  # usage bug rather than silently ignoring the injected discovery fixture.
  if [ -n "$discovery_response_file" ] && [ -n "$existing_number" ]; then
    die "ensure-parent: --discovery-response-file is invalid with --existing-number (discovery runs only on the create path)" 2
  fi

  # --slug asks whether the resolved epic is the seed issue of that initiative; it is meaningful
  # ONLY on the resolve path. Both checks run BEFORE any gh call.
  if [ -n "$slug_given" ]; then
    [ -n "$existing_number" ] || die "ensure-parent: --slug is valid only with --existing-number" 2
    assert_slug "ensure-parent" "$slug"
  fi

  if is_offline; then
    # Offline DISCOVERY seam (create path): with --discovery-response-file the injected SEARCH
    # response is run through the shared kernel + exact-title filter + resolve_discovery. A lone
    # OPEN exact match emits { number, id, status:"resolved-by-title" }; a multiple/CLOSED/
    # divergent set FAILS CLOSED (exit 1); ZERO matches falls through to the --response-file
    # `created` simulation below (mirroring the live discover-then-create flow).
    if [ -n "$discovery_response_file" ]; then
      local matches decision
      matches="$(normalize_find_by_title "$(read_injected "$discovery_response_file")" "$title")" \
        || die "ensure-parent: malformed discovery search response" 1
      decision="$(resolve_discovery "$matches")" || return 1
      if [ "$(printf '%s' "$decision" | jq -r '.action // "resolved"')" != "create" ]; then
        printf '%s\n' "$decision"
        return 0
      fi
      # ZERO matches: fall through to the create simulation (requires --response-file).
    fi
    # Offline exercises ONLY the resolve/normalize transform (creation is a pure live
    # side effect with no deterministic transform). The injected response is treated
    # as a repository.issue read; status tag is resolved when --existing-number was
    # given, else created (the create path's post-create node-id read).
    [ -n "$response_file" ] || die "offline ensure-parent requires --response-file" 2
    if [ -n "$slug_given" ]; then
      normalize_parent_seed "$(read_injected "$response_file")" "$slug"
      return
    fi
    local status="created"
    [ -n "$existing_number" ] && status="resolved"
    normalize_parent_resolve "$(read_injected "$response_file")" "$status"
    return
  fi

  reject_fixture_flags_in_live_mode "ensure-parent" \
    "--response-file=$response_file" "--discovery-response-file=$discovery_response_file"
  require_gh "ensure-parent"

  # Resolve owner/repo: explicit --repo wins, else the current checkout.
  local owner_repo owner repo_name
  if [ -n "$repo" ]; then
    owner_repo="$repo"
  else
    owner_repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" \
      || die "ensure-parent: failed to resolve owner/repo (pass --repo)" 1
  fi
  # Apply the SAME owner/repo charset guard find-by-title uses (the SHARED guard) — tightening
  # the former weak `*/*` glob now that the discovery search flows owner_repo into the search DSL.
  assert_owner_repo "ensure-parent" "$owner_repo"
  owner="${owner_repo%%/*}"; repo_name="${owner_repo#*/}"

  # Every live path captures its record, labels the returned epic `type:epic` (ensure_epic_label),
  # then prints the record unchanged: a labeling failure leaves stdout empty.
  local number resp record
  if [ -n "$existing_number" ]; then
    # RESOLVE path (idempotency key supplied): read the known epic's node id. Routed
    # through the shared kernel — a missing/malformed read FAILS CLOSED.
    number="$existing_number"
    if [ -n "$slug_given" ]; then
      resp="$(gh api graphql "${GQL_HEADER_ARGS[@]}" -f query="$PARENT_SEED_QUERY" \
                -f owner="$owner" -f repo="$repo_name" -F number="$number" 2>/dev/null)" \
        || die "ensure-parent: GraphQL resolve failed for issue #$number" 1
      record="$(normalize_parent_seed "$resp" "$slug")" || exit "$?"
      # Only a seed epic is labeled: an issue that is not the initiative's seed is left as it is.
      if [ "$(printf '%s' "$record" | jq -r '.seed')" = "true" ]; then
        emit_labeled_record "$owner_repo" "$record" "$number"
      else
        record_issue_number "$record" "$number" >/dev/null || exit "$?"
        printf '%s\n' "$record"
      fi
      return
    fi
    resp="$(gh api graphql "${GQL_HEADER_ARGS[@]}" -f query="$PARENT_RESOLVE_QUERY" \
              -f owner="$owner" -f repo="$repo_name" -F number="$number" 2>/dev/null)" \
      || die "ensure-parent: GraphQL resolve failed for issue #$number" 1
    record="$(normalize_parent_resolve "$resp" "resolved")" || exit "$?"
    emit_labeled_record "$owner_repo" "$record" "$number"
    return
  fi

  # ORPHAN-SAFE DISCOVER-THEN-CREATE (no idempotency key): before creating, DISCOVER the epic
  # by EXACT title via the SHARED enumeration machinery (run_title_search → repository.issues
  # enumeration + paginate_to_completeness + filter_exact_title — the SAME path find-by-title
  # uses, never a divergent second lookup) and apply the resolution rules (resolve_discovery): a
  # lone OPEN exact match RESOLVES (status resolved-by-title, skip create); a multiple/CLOSED/
  # divergent set FAILS CLOSED; ZERO matches falls through to create. A title is REQUIRED to discover.
  # Concurrent runs for one initiative: see the THREAT MODEL under PARENT ORPHAN-SAFETY in §4.
  [ -n "$title" ] || die "ensure-parent: --title is required to create a parent (or pass --existing-number)" 2
  local discovery decision
  discovery="$(run_title_search "ensure-parent" "$owner_repo" "$title")" \
    || die "ensure-parent: discovery search failed" 1
  decision="$(resolve_discovery "$discovery")" || exit 1
  if [ "$(printf '%s' "$decision" | jq -r '.action // "resolved"')" != "create" ]; then
    emit_labeled_record "$owner_repo" "$decision"
    return 0
  fi

  # CREATE path (discovery found ZERO existing epics): untrusted title/body flow ONLY through
  # gh flags (never shell/GraphQL source). Prefer --body-file when given (large/multiline
  # PRD epic bodies).
  local -a create_args=(issue create --title "$title")
  [ -n "$repo" ] && create_args=(issue create -R "$owner_repo" --title "$title")
  if [ -n "$body_file" ]; then
    [ -z "$body" ] || die "ensure-parent: pass --body OR --body-file, not both" 2
    if [ "$body_file" = "-" ]; then
      # Materialize stdin to a temp file so gh reads the untrusted body as DATA.
      local tmp_body; tmp_body="$(mktemp)"
      cat > "$tmp_body"
      create_args+=(--body-file "$tmp_body")
      local created_url
      created_url="$(gh "${create_args[@]}")" || { rm -f "$tmp_body"; die "ensure-parent: gh issue create failed" 1; }
      rm -f "$tmp_body"
      number="${created_url##*/}"
    else
      create_args+=(--body-file "$body_file")
      local created_url
      created_url="$(gh "${create_args[@]}")" || die "ensure-parent: gh issue create failed" 1
      number="${created_url##*/}"
    fi
  else
    [ -n "$body" ] || die "ensure-parent: --body or --body-file is required to create a parent" 2
    create_args+=(--body "$body")
    local created_url
    created_url="$(gh "${create_args[@]}")" || die "ensure-parent: gh issue create failed" 1
    # `gh issue create` prints the new issue URL; the trailing path segment is the number.
    number="${created_url##*/}"
  fi
  case "$number" in ''|*[!0-9]*) die "ensure-parent: could not parse new issue number from gh output" 1 ;; esac

  # Resolve the just-created issue's node id (the skill needs the id to attach
  # children). Routed through the shared kernel — a malformed read FAILS CLOSED.
  resp="$(gh api graphql "${GQL_HEADER_ARGS[@]}" -f query="$PARENT_RESOLVE_QUERY" \
            -f owner="$owner" -f repo="$repo_name" -F number="$number" 2>/dev/null)" \
    || die "ensure-parent: GraphQL node-id resolve failed for created issue #$number" 1
  record="$(normalize_parent_resolve "$resp" "created")" || exit "$?"
  emit_labeled_record "$owner_repo" "$record" "$number"
}

cmd_attach_subissue() {
  local parent_id="" child_id="" response_file="" emit_payload=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --parent-id) [ "$#" -ge 2 ] || die "missing value for --parent-id" 2
               parent_id="$2"; shift 2 ;;
      --child-id) [ "$#" -ge 2 ] || die "missing value for --child-id" 2
               child_id="$2"; shift 2 ;;
      --response-file) [ "$#" -ge 2 ] || die "missing value for --response-file" 2
               response_file="$2"; shift 2 ;;
      --emit-payload) emit_payload="1"; shift ;;
      *) die "attach-subissue: unexpected argument '$1'" 2 ;;
    esac
  done

  # Node ids (when supplied) are validated BEFORE any gh/GraphQL use — defense-in-depth.
  [ -n "$parent_id" ] && assert_node_id "--parent-id" "$parent_id"
  [ -n "$child_id" ] && assert_node_id "--child-id" "$child_id"

  if is_offline; then
    if [ -n "$response_file" ]; then
      # Propagate surface_attach_response's exit code — a fail-closed (non-recoverable)
      # error must surface as nonzero on the offline seam too, not be masked.
      surface_attach_response "$(read_injected "$response_file")"
      return "$?"
    fi
    # Offline attach-subissue is SYMMETRIC with ensure-parent/list-children: the response-
    # surfacing path REQUIRES --response-file. Payload CONSTRUCTION (the only other offline
    # action) requires the EXPLICIT --emit-payload opt-in — it is an intentional offline
    # build, never a silent fall-through. Without EITHER flag we FAIL CLOSED: an ambient
    # SUBISSUE_OPS_OFFLINE leak must never turn a REAL attach into a silent success no-op.
    [ -n "$emit_payload" ] \
      || die "offline attach-subissue requires --response-file (surface a response) or --emit-payload (build the variables payload)" 2
    [ -n "$parent_id" ] && [ -n "$child_id" ] \
      || die "offline attach-subissue --emit-payload requires --parent-id and --child-id" 2
    build_attach_payload "$parent_id" "$child_id"
    return 0
  fi

  reject_fixture_flags_in_live_mode "attach-subissue" "--response-file=$response_file"
  [ -n "$parent_id" ] && [ -n "$child_id" ] \
    || die "attach-subissue requires --parent-id and --child-id" 2
  require_gh "attach-subissue"
  # Capture stdout regardless of gh's exit status: a GraphQL rejection (already-
  # parented / cycle) returns the error BODY (which surface_attach_response classifies)
  # yet gh exits nonzero. The surfacing function is the single decision point — never
  # crash. issueId = PARENT, subIssueId = CHILD (NOT blockingIssueId — INVARIANT §4).
  local resp
  resp="$(gh api graphql "${GQL_HEADER_ARGS[@]}" -f query="$ADD_SUBISSUE_MUTATION" \
            -f issueId="$parent_id" -f subIssueId="$child_id" 2>/dev/null)" || true
  surface_attach_response "$resp"
}

cmd_list_children() {
  local parent_id="" response_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --parent-id) [ "$#" -ge 2 ] || die "missing value for --parent-id" 2
               parent_id="$2"; shift 2 ;;
      --response-file) [ "$#" -ge 2 ] || die "missing value for --response-file" 2
               response_file="$2"; shift 2 ;;
      *) die "list-children: unexpected argument '$1'" 2 ;;
    esac
  done

  # Node id (when supplied) is validated BEFORE any gh/GraphQL use — defense-in-depth.
  [ -n "$parent_id" ] && assert_node_id "--parent-id" "$parent_id"

  if is_offline; then
    # Offline injects a SINGLE page treated as the COMPLETE connection — its
    # pageInfo.hasNextPage MUST be false (normalize_children FAILS CLOSED otherwise),
    # exercising the same completeness gate the live loop enforces.
    [ -n "$response_file" ] || die "offline list-children requires --response-file" 2
    normalize_children "$(read_injected "$response_file")"
    return
  fi

  reject_fixture_flags_in_live_mode "list-children" "--response-file=$response_file"
  [ -n "$parent_id" ] || die "list-children requires --parent-id" 2
  require_gh "list-children"

  # PAGINATE TO COMPLETENESS (issue #228 lesson) via the SHARED mechanism: each raw page
  # is routed through the kernel BEFORE accumulation (a malformed/error page FAILS CLOSED
  # mid-loop, never a partial set), nodes accumulate across pages, completeness is driven
  # by the loop on hasNextPage/endCursor. The root predicate gates `.id` (string,len>0) AND
  # `subIssues.pageInfo.hasNextPage` as a boolean (VALUE-AGNOSTIC — true is still accepted).
  local accumulated
  accumulated="$(paginate_to_completeness \
    "list-children" "$SUBISSUES_QUERY" \
    '.data.node' \
    '(.id | type == "string" and length > 0)
     and (.subIssues.pageInfo.hasNextPage | type == "boolean")' \
    '.subIssues.nodes' \
    '(.number | type == "number" and . >= 1 and . == floor)
     and (.id | type == "string" and length > 0)
     and (.title | type == "string" and length > 0)' \
    '.subIssues.pageInfo' \
    -f id="$parent_id")" || exit "$?"
  jq -c -n --arg pid "$parent_id" --argjson children "$accumulated" \
    '{ parent_id: $pid, children: [ $children[] | { number, id, title } ] }'
}

# run_title_search <subcmd> <owner_repo> <title>: the SINGLE SHARED live exact-title lookup,
# driving BOTH cmd_find_by_title AND ensure-parent's pre-create discovery so there is exactly
# ONE enumeration + pagination + exact-filter path (no divergent second lookup). It ENUMERATES
# `repository.issues` (owner/name split from the already-validated owner_repo and passed to gh
# via -f as DATA — the untrusted TITLE is NEVER passed to gh and never enters any query string),
# paginates ISSUES_BY_REPO_QUERY to completeness via the shared mechanism (state-aware element
# predicate), and runs filter_exact_title ONCE over the full accumulated set (the LOCAL byte-for-
# byte title match). Emits the {title, matches:[{number,id,title,state,parent}]} schema on stdout
# (exit 0) or FAILS CLOSED via the kernel (propagated exit). The caller MUST have already
# validated owner_repo via assert_owner_repo and ensured `gh` is on PATH.
run_title_search() {
  local subcmd="$1" owner_repo="$2" title="$3"
  local owner repo_name accumulated
  owner="${owner_repo%%/*}"; repo_name="${owner_repo#*/}"
  accumulated="$(paginate_to_completeness \
    "$subcmd" "$ISSUES_BY_REPO_QUERY" \
    '.data.repository.issues' \
    '(.pageInfo.hasNextPage | type == "boolean")' \
    '.nodes' \
    '(.number | type == "number" and . >= 1 and . == floor)
     and (.id | type == "string" and length > 0)
     and (.title | type == "string" and length > 0)
     and (.state | type == "string" and length > 0)' \
    '.pageInfo' \
    -f owner="$owner" -f name="$repo_name")" || return "$?"
  filter_exact_title "$accumulated" "$title"
}

cmd_find_by_title() {
  local title="" repo="" response_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --title) [ "$#" -ge 2 ] || die "missing value for --title" 2
               title="$2"; shift 2 ;;
      --repo) [ "$#" -ge 2 ] || die "missing value for --repo" 2
               repo="$2"; shift 2 ;;
      --response-file) [ "$#" -ge 2 ] || die "missing value for --response-file" 2
               response_file="$2"; shift 2 ;;
      *) die "find-by-title: unexpected argument '$1'" 2 ;;
    esac
  done
  [ -n "$title" ] || die "find-by-title: --title is required" 2

  if is_offline; then
    # Offline normalizes the injected search response (treated as the search result set)
    # through the shared kernel + exact-title filter. REQUIRES --response-file (symmetric
    # with the other discovery subcommands).
    [ -n "$response_file" ] || die "offline find-by-title requires --response-file" 2
    normalize_find_by_title "$(read_injected "$response_file")" "$title"
    return
  fi

  reject_fixture_flags_in_live_mode "find-by-title" "--response-file=$response_file"

  # Resolve owner/repo: explicit --repo wins, else the current checkout (mirrors
  # ensure-parent). The search is scoped to that repo so candidates do not leak across
  # repos. An EXPLICITLY supplied --repo is a pure-usage value validated BEFORE require_gh
  # so a malformed --repo fails closed (exit 2) even on a machine without `gh` — the
  # owner/repo charset guard is the usage gate, not a network precondition. `gh` is only
  # required when --repo was OMITTED (to resolve owner/repo from the checkout) or for the
  # subsequent GraphQL search.
  local owner_repo
  if [ -n "$repo" ]; then
    owner_repo="$repo"
  else
    require_gh "find-by-title"
    owner_repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" \
      || die "find-by-title: failed to resolve owner/repo (pass --repo)" 1
  fi
  # Charset-validate owner AND repo via the SHARED guard BEFORE any gh/GraphQL call
  # (defense-in-depth — owner_repo flows into the search DSL via -f as DATA, but a malformed
  # `--repo` is a usage bug, not a broadened query). Replaces the weak `*/*` glob, which
  # admitted e.g. `a/b/c` or shell metacharacters. Same guard ensure-parent's discovery uses.
  assert_owner_repo "find-by-title" "$owner_repo"

  # With an EXPLICIT --repo the charset guard above has now passed; require `gh` before the
  # live GraphQL search (the --repo-omitted branch already required it above).
  [ -n "$repo" ] && require_gh "find-by-title"

  # Run the SHARED live exact-title lookup (repository.issues enumeration + paginate-to-
  # completeness + LOCAL exact-title post-filter). The untrusted title is NEVER passed to gh and
  # NEVER enters a query string — it flows ONLY into the jq --arg filter as DATA; owner/name flow
  # via gh -f as DATA. The SAME path ensure-parent's discovery uses, so the enumeration/pagination/
  # exactness contract cannot diverge. A malformed/error page FAILS CLOSED via the kernel inside
  # run_title_search.
  run_title_search "find-by-title" "$owner_repo" "$title" || exit "$?"
}

# read_prd_ui <commit> <slug>: prints the PRD's UI value at <commit> — yes, no or invalid, or
# missing when docs/prds/<slug>.md fails the Document existence test. The PRD is read ONLY through
# the shared library: hivemind_doc_read frames the bytes (an empty prefix line, the document, then
# its read status) into jq under hivemind_readiness_jq_defs with rc_doc_eval(rc_prd_ui), so the
# UI line is parsed by the readiness check's own rules. A read or jq failure fails closed.
read_prd_ui() {
  local commit="$1" slug="$2" program ui="" read_rc=0
  program="$(hivemind_readiness_jq_defs)"'
rc_doc_eval(rc_prd_ui)'
  ui="$(
    {
      printf '\n'
      hivemind_doc_read "$commit" "docs/prds/$slug.md" 2>/dev/null || read_rc=$?
      printf '\n%s' "$read_rc"
    } | jq -Rsr "$program" 2>/dev/null
  )" || die "design-gate: PRD read failed at the trunk commit" 1
  case "$ui" in
    yes|no|invalid|missing) printf '%s\n' "$ui" ;;
    *) die "design-gate: PRD read failed at the trunk commit" 1 ;;
  esac
}

# read_record_front_matter <commit> <path>: pipes the review record at <commit>, read with
# hivemind_doc_read, into hivemind_record_front_matter. Prints the parsed front matter line (only
# when both succeed), then one last line `<read-status> <parse-status>` so the caller can tell a
# missing record (read 1), a failed read (read 2) and an unparseable record (read 0, parse 1) apart.
read_record_front_matter() {
  local -a statuses=()
  if hivemind_doc_read "$1" "$2" 2>/dev/null | hivemind_record_front_matter; then
    statuses=(0 0)
  else
    statuses=("${PIPESTATUS[@]}")
  fi
  printf '%s %s\n' "${statuses[0]}" "${statuses[1]}"
}

# design_reasons <commit> <slug>: prints the design gate's reasons for a UI slice as one compact
# JSON array, sorted and unique, using the readiness check's own codes:
#   prototype_missing          either prototype file fails the Document existence test (once)
#   record_missing             the review record fails the Document existence test
#   record_malformed           the review record's front matter does not parse
#   record_not_passed          verdict not pass, clean_round not true, or rounds below 2
#   record_rounds_exceeded     rounds above 3
#   record_open                any open count above 0
#   record_stale:<path>        a stamped path failing the Document existence test or holding
#                              another blob than its stamp
#   record_unstamped:<path>    a prototype path missing from the record's stamps
# The pass rule restates the readiness check's rc_record_codes clause for clause, and the stale
# rule its staleness rule. Every read is at <commit> through the shared library; a git failure
# fails closed (nonzero, stdout empty).
design_reasons() {
  local commit="$1" slug="$2" path="" entry_rc=0 codes="" output="" record_status="" record_codes=""
  local stamps="" stamp="" blob="" oid=""
  local prototype_dir="docs/initiatives/$slug/prototype"
  local -a prototypes=("$prototype_dir/index.html" "$prototype_dir/notes.md")
  for path in "${prototypes[@]}"; do
    entry_rc=0
    hivemind_doc_entry "$commit" "$path" >/dev/null 2>&1 || entry_rc=$?
    case "$entry_rc" in
      0) ;;
      1) codes="prototype_missing"$'\n' ;;
      *) die "design-gate: prototype read failed at the trunk commit" 1 ;;
    esac
  done
  output="$(read_record_front_matter "$commit" "docs/initiatives/$slug/review-record.md")"
  record_status="${output##*$'\n'}"
  case "$record_status" in
    '0 0')
      record_codes="$(printf '%s' "${output%$'\n'*}" \
        | jq -r --arg index "${prototypes[0]}" --arg notes "${prototypes[1]}" '
            [.stamps[].path] as $stamped
            | (if .verdict != "pass" or .clean_round != true or .rounds < 2
               then "record_not_passed" else empty end),
              (if .rounds > 3 then "record_rounds_exceeded" else empty end),
              (if any(.open[]; . > 0) then "record_open" else empty end),
              ($index, $notes | select(. as $path | any($stamped[]; . == $path) | not)
               | "record_unstamped:" + .)')" \
        || die "design-gate: review record evaluation failed" 1
      codes+="$record_codes"$'\n'
      stamps="$(printf '%s' "${output%$'\n'*}" | jq -r '.stamps[] | .path + "\t" + .blob')" \
        || die "design-gate: review record evaluation failed" 1
      while IFS= read -r stamp; do
        [ -n "$stamp" ] || continue
        path="${stamp%%$'\t'*}"
        blob="${stamp#*$'\t'}"
        entry_rc=0
        oid="$(hivemind_doc_entry "$commit" "$path" 2>/dev/null)" || entry_rc=$?
        case "$entry_rc" in
          0|1) ;;
          *) die "design-gate: stamped document read failed at the trunk commit" 1 ;;
        esac
        if [ "$entry_rc" -ne 0 ] || [ "$oid" != "$blob" ]; then
          codes+="record_stale:$path"$'\n'
        fi
      done <<<"$stamps" ;;
    '1 '*) codes+="record_missing"$'\n' ;;
    '0 1') codes+="record_malformed"$'\n' ;;
    *) die "design-gate: review record read failed at the trunk commit" 1 ;;
  esac
  printf '%s' "$codes" | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique' \
    || die "design-gate: reason assembly failed" 1
}

cmd_design_gate() {
  local slug="" slug_given="" repo="" remote="origin" trunk_response_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --slug) [ "$#" -ge 2 ] || die "missing value for --slug" 2
               slug="$2"; slug_given="1"; shift 2 ;;
      --repo) [ "$#" -ge 2 ] || die "missing value for --repo" 2
               repo="$2"; shift 2 ;;
      --remote) [ "$#" -ge 2 ] || die "missing value for --remote" 2
               remote="$2"; shift 2 ;;
      --trunk-response-file) [ "$#" -ge 2 ] || die "missing value for --trunk-response-file" 2
               trunk_response_file="$2"; shift 2 ;;
      *) die "design-gate: unexpected argument '$1'" 2 ;;
    esac
  done
  [ -n "$slug_given" ] || die "design-gate: --slug is required" 2
  assert_slug "design-gate" "$slug"
  reject_fixture_flags_in_live_mode "design-gate" "--trunk-response-file=$trunk_response_file"
  assert_git_identifier "design-gate" "remote name" "$remote"

  local resp="" owner_repo="" trunk_ref="" trunk="" commit="" object_type="" ui="" reasons="[]"
  local link_prefix=""
  if is_offline; then
    [ -n "$trunk_response_file" ] || die "offline design-gate requires --trunk-response-file" 2
    [ -n "$repo" ] || die "offline design-gate requires --repo" 2
    assert_owner_repo "design-gate" "$repo"
    owner_repo="$repo"
    resp="$(read_injected "$trunk_response_file")"
  else
    if [ -n "$repo" ]; then
      owner_repo="$repo"
    else
      require_gh "design-gate"
      owner_repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" \
        || die "design-gate: failed to resolve owner/repo (pass --repo)" 1
    fi
    assert_owner_repo "design-gate" "$owner_repo"
    [ -n "$repo" ] && require_gh "design-gate"
    resp="$(gh api graphql "${GQL_HEADER_ARGS[@]}" -f query="$TRUNK_REF_QUERY" \
              -f owner="${owner_repo%%/*}" -f name="${owner_repo#*/}" 2>/dev/null)" \
      || die "design-gate: GraphQL trunk read failed" 1
  fi

  # INVARIANT: the extracted trunk name and commit id must equal the read byte for byte; command
  # substitution strips trailing newlines, and the jq equality check rejects any value it altered.
  trunk_ref="$(normalize_trunk_ref "$resp" 2>/dev/null)" \
    || die "design-gate: malformed trunk read (defaultBranchRef name and target.oid required)" 1
  trunk="$(printf '%s' "$trunk_ref" | jq -r '.name')"
  commit="$(printf '%s' "$trunk_ref" | jq -r '.oid')"
  printf '%s' "$trunk_ref" | jq -e --arg name "$trunk" --arg oid "$commit" \
      '.name == $name and .oid == $oid' >/dev/null 2>&1 \
    || die "design-gate: malformed trunk read (name or commit id not plain text)" 1
  assert_git_identifier "design-gate" "trunk name" "$trunk"
  git check-ref-format --branch "$trunk" >/dev/null 2>&1 \
    || die "design-gate: trunk name fails git check-ref-format --branch" 1
  hivemind_readiness_commit_ok "$commit" \
    || die "design-gate: trunk commit id is not a full lowercase object id" 1
  link_prefix="$(hivemind_readiness_link_prefix "$owner_repo" "$trunk" 2>/dev/null)" \
    || die "design-gate: Design link prefix build failed for '$owner_repo' at trunk '$trunk'" 1

  # INVARIANT: the fetch writes FETCH_HEAD only (empty refmap: no remote-tracking ref moves), and
  # only the checked commit id, never a branch name or local ref, reaches the shared library.
  if ! is_offline; then
    GIT_TERMINAL_PROMPT=0 git --no-replace-objects fetch --quiet --no-tags --no-recurse-submodules \
        --no-prune --refmap= -- "$remote" "refs/heads/$trunk" </dev/null >/dev/null 2>&1 \
      || die "design-gate: fetch of the trunk from remote '$remote' failed" 1
  fi
  object_type="$(git --no-replace-objects cat-file -t "$commit" </dev/null 2>/dev/null)" \
    || die "design-gate: trunk commit $commit is not in the local object store" 1
  [ "$object_type" = commit ] \
    || die "design-gate: trunk commit $commit is not in the local object store" 1
  # The trunk read and the fetch are two reads: a commit id already in the object store passes
  # the check above even when the remote branch was force-pushed away from it in between, so the
  # fetched tip must equal it or descend from it. The gate then reads the fetched tip, the newest
  # trunk it holds, so a trunk that moved forward in between is read as it now stands.
  if ! is_offline; then
    local fetched=""
    fetched="$(git --no-replace-objects rev-parse --verify -q 'FETCH_HEAD^{commit}' </dev/null 2>/dev/null)" \
      && hivemind_readiness_commit_ok "$fetched" \
      || die "design-gate: fetched trunk tip of remote '$remote' is unreadable" 1
    git --no-replace-objects merge-base --is-ancestor "$commit" "$fetched" </dev/null >/dev/null 2>&1 \
      || die "design-gate: trunk commit $commit is not on the fetched trunk of remote '$remote'" 1
    commit="$fetched"
  fi

  ui="$(read_prd_ui "$commit" "$slug")" || exit "$?"
  if [ "$ui" = yes ]; then
    reasons="$(design_reasons "$commit" "$slug")" || exit "$?"
  fi
  jq -c -n --arg commit "$commit" --arg trunk "$trunk" --arg link_prefix "$link_prefix" \
    --arg slug "$slug" --arg ui "$ui" --argjson reasons "$reasons" \
    '{ commit: $commit, trunk: $trunk, link_prefix: $link_prefix, slug: $slug, ui: $ui,
       result: (if $ui == "yes" and ($reasons | length) > 0 then "refuse" else "pass" end),
       reasons: $reasons }'
}

# --- Dispatch ----------------------------------------------------------------

usage() {
  cat >&2 <<EOF
$PROG — deterministic mechanism for the hivemind prd-to-issues skill (native sub-issues).
usage: $PROG <subcommand> [args]
subcommands:
  ensure-parent   --title <str> --body <str>|--body-file <path|-> [--repo <owner/repo>] [--existing-number <int> [--slug <slug>]] [--response-file <path|->] [--discovery-response-file <path|->]
  attach-subissue --parent-id <ID> --child-id <ID> [--response-file <path|->] | --emit-payload --parent-id <ID> --child-id <ID> (offline payload build)
  list-children   --parent-id <ID> [--response-file <path|->]
  find-by-title   --title <str> [--repo <owner/repo>] [--response-file <path|->]
  design-gate     --slug <slug> [--repo <owner/repo>] [--remote <name>] [--trunk-response-file <path|->]
--slug (ensure-parent, valid only with --existing-number) adds "seed": true only when the epic body's
first line is the seed issue marker naming <slug>. Live, ensure-parent adds the type:epic label to the
epic it returns (with --slug, only a seed epic), creating the repository label when missing. design-gate reads the trunk commit (fetched into
FETCH_HEAD only) and, when docs/prds/<slug>.md says UI yes, refuses on a prototype file failing the
Document existence test or a review record that is missing, malformed, not passed, stale or unstamped.
Its output's link_prefix (https://github.com/<owner/repo>/blob/<trunk>/) starts every Design link;
offline design-gate requires --repo.
Set SUBISSUE_OPS_OFFLINE to drive the pure transforms over injected input (no gh).
EOF
}

[ "$#" -ge 1 ] || { usage; exit 2; }
subcmd="$1"; shift
case "$subcmd" in
  ensure-parent)   cmd_ensure_parent "$@" ;;
  attach-subissue) cmd_attach_subissue "$@" ;;
  list-children)   cmd_list_children "$@" ;;
  find-by-title)   cmd_find_by_title "$@" ;;
  design-gate)     cmd_design_gate "$@" ;;
  -h|--help)       usage; exit 0 ;;
  *)               die "unknown subcommand '$subcmd' (try --help)" 2 ;;
esac
