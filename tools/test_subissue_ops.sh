#!/usr/bin/env bash
#
# Behavioral unit runner for the prd-to-issues MECHANISM substrate (native sub-issues, STEP-002).
#
# OFFLINE jq/bash TEST — CI-runnable with ONLY jq + bash present (NO gh / network / auth). It
# drives the pure transform core of:
#   plugin/skills/prd-to-issues/scripts/subissue-ops.sh
# via its documented offline seam (SUBISSUE_OPS_OFFLINE=1 + the --response-file injection flag),
# feeds canned fixtures from tests/prd-to-issues/, and asserts the emitted JSON equals a golden
# fixture under tests/prd-to-issues/expected/. Each transform (build_attach_payload,
# surface_attach_response, normalize_parent_resolve, normalize_children) is a PURE function of its
# injected input, so every case is deterministic and offline.
#
# Comparison is canonicalized (object keys sorted via -S, arrays deep-sorted) so jq key/element
# ordering can never flake the match.
#
# Mirrors tools/test_triage_ops.sh's pass/fail counter + per-case assertion + helper-fn +
# exit-nonzero-on-any-fail + scratch-tmpdir-on-trap conventions. Read-only: the only writes are
# scratch files in a disposable tmpdir removed on EXIT.
#
# Usage:
#   ./tools/test_subissue_ops.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
OPS="$REPO_ROOT/plugin/skills/prd-to-issues/scripts/subissue-ops.sh"
PI_DIR="$REPO_ROOT/tests/prd-to-issues"
EXPECTED_DIR="$PI_DIR/expected"

[ -f "$OPS" ] || { echo "FAIL: script under test missing: $OPS" >&2; exit 2; }
[ -d "$PI_DIR" ] || { echo "FAIL: prd-to-issues fixture dir missing: $PI_DIR" >&2; exit 2; }
[ -d "$EXPECTED_DIR" ] || { echo "FAIL: expected-output dir missing: $EXPECTED_DIR" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this suite" >&2; exit 2; }

make_scratch_dir TMPDIR_TEST
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# canon: deep-canonicalize one JSON value into a single deterministic line. Sort object keys (-S)
# and recursively sort every array, so neither key order nor array element order can flake an
# exact-match comparison.
canon() {
  jq -S -c '
    def deepsort:
      if type == "array" then map(deepsort) | sort
      elif type == "object" then map_values(deepsort)
      else . end;
    deepsort'
}

# run_case <case> <expected-fixture-abspath> -- <ops-arg...>
# Invoke subissue-ops.sh under the OFFLINE seam with the given args, canonicalize stdout, and
# exact-match against the canonicalized expected fixture. A nonzero exit, empty, or mismatched
# output fails the case loudly.
run_case() {
  local case_name="$1" expected_fix="$2"; shift 2
  [ "$1" = "--" ] && shift
  if [ ! -f "$expected_fix" ]; then failed "$case_name" "expected fixture missing: $expected_fix"; return; fi

  local expected actual
  if ! expected="$(canon < "$expected_fix")"; then
    failed "$case_name" "could not canonicalize expected fixture $expected_fix"
    return
  fi
  if ! actual="$(SUBISSUE_OPS_OFFLINE=1 bash "$OPS" "$@" 2>/dev/null | canon)"; then
    failed "$case_name" "subissue-ops failed (args: $*)"
    return
  fi
  if [ "$actual" = "$expected" ]; then
    pass "$case_name" "($(basename "$expected_fix"))"
  else
    failed "$case_name" "(args: $*)
    expected: $expected
    actual:   $actual"
  fi
}

# run_exit0_case <case> -- <ops-arg...>
# Like run_case but ONLY asserts the script exited 0 (no pipe masking status). Used to lock the
# recoverable-warning-must-not-crash invariant: an already-parented / cycle response surfaces a
# warning record AND exits 0 so a batch attach keeps going. Captures status WITHOUT a pipe.
run_exit0_case() {
  local case_name="$1"; shift
  [ "$1" = "--" ] && shift
  local out status
  out="$(SUBISSUE_OPS_OFFLINE=1 bash "$OPS" "$@" 2>/dev/null)"
  status=$?
  if [ "$status" -eq 0 ]; then
    pass "$case_name" "exit=0 (args: $*)"
  else
    failed "$case_name" "expected exit 0, got $status (args: $*; stdout: $out)"
  fi
}

# run_exit1_case <case> -- <ops-arg...>
# Asserts the script exited NONZERO (fail-closed). Used to lock the shared-kernel fail-closed
# invariant: a transport error, GraphQL error, malformed/null response, or a mixed recoverable+
# fatal errors array MUST surface as nonzero so the caller never proceeds as if a sub-issue were
# attached/resolved/listed when it was not. Captures status WITHOUT a pipe so the exit code is
# the script's own, not jq's.
run_exit1_case() {
  local case_name="$1"; shift
  [ "$1" = "--" ] && shift
  local out status
  out="$(SUBISSUE_OPS_OFFLINE=1 bash "$OPS" "$@" 2>/dev/null)"
  status=$?
  if [ "$status" -ne 0 ]; then
    pass "$case_name" "exit=$status (args: $*)"
  else
    failed "$case_name" "expected nonzero exit, got 0 (args: $*; stdout: $out)"
  fi
}

# ── attach-subissue: GraphQL variables payload shape ───────────────────────────────
# Offline attach-subissue with the EXPLICIT --emit-payload opt-in builds the addSubIssue
# variables payload. CRITICAL FIELD MAPPING: issueId = the PARENT, subIssueId = the CHILD
# (NOT blockingIssueId). The opt-in flag is REQUIRED — payload build is no longer a silent
# fall-through when --response-file is absent (see attach:offline-no-flag-exit2 below).
run_case "attach:payload-shape" "$EXPECTED_DIR/attach-payload.json" -- \
  attach-subissue --emit-payload --parent-id I_parent --child-id I_child

# Direct key/value assertion: the payload is EXACTLY {issueId:PARENT, subIssueId:CHILD}. Locks the
# load-bearing parent/child mapping independently of the golden file — a swap would be caught here.
PAYLOAD="$(SUBISSUE_OPS_OFFLINE=1 bash "$OPS" attach-subissue --emit-payload --parent-id I_parent --child-id I_child 2>/dev/null)"
if printf '%s' "$PAYLOAD" | jq -e '
    (keys | sort) == ["issueId","subIssueId"]
    and .issueId == "I_parent"
    and .subIssueId == "I_child"' >/dev/null 2>&1; then
  pass "attach:payload-mapping" "issueId=parent, subIssueId=child"
else
  failed "attach:payload-mapping" "unexpected payload mapping (payload: $PAYLOAD)"
fi

# ── attach-subissue: offline fail-closed symmetry (F2) ─────────────────────────────
# Offline attach-subissue with NEITHER --response-file NOR --emit-payload MUST fail closed
# (exit 2). Previously the absent-flag path fell through to build_attach_payload and exited
# 0, so an ambient SUBISSUE_OPS_OFFLINE leak turned a REAL attach into a silent success
# no-op. Even with live-shaped --parent-id/--child-id present, neither opt-in flag means
# no offline action is authorized — fail closed.
run_exit1_case "attach:offline-no-flag-exit2" -- \
  attach-subissue --parent-id I_parent --child-id I_child

# ── attach-subissue: node-id allowlist (F4, defense-in-depth) ──────────────────────
# An out-of-charset node id (the allowed charset is ^[A-Za-z0-9_=-]+$) fails closed BEFORE
# any payload build. A realistic legacy base64 `==`-padded id (which the charset ALLOWS via
# `=`) passes — proving the validator does not false-reject legacy ids.
run_exit1_case "attach:bad-node-id-exit2" -- \
  attach-subissue --emit-payload --parent-id "I_parent;rm -rf" --child-id I_child
run_exit0_case "attach:legacy-base64-id-ok" -- \
  attach-subissue --emit-payload --parent-id "MDU6SXNzdWUx==" --child-id "MDU6SXNzdWUy=="

# ── attach-subissue: success surfacing ─────────────────────────────────────────────
# A canned success addSubIssue response surfaces {status:attached, parent, child} and exits 0.
run_case "attach:success-surface" "$EXPECTED_DIR/attach-success.json" -- \
  attach-subissue --response-file "$PI_DIR/attach-success-response.json"
run_exit0_case "attach:success-exit0" -- \
  attach-subissue --response-file "$PI_DIR/attach-success-response.json"

# ── attach-subissue: recoverable warnings (exit 0) ─────────────────────────────────
# already-parented and cycle-rejected are EXPECTED non-fatal rejections: surface a structured
# warning record AND exit 0 so the batch keeps going.
run_case "attach:already-parented-surface" "$EXPECTED_DIR/attach-already-parented.json" -- \
  attach-subissue --response-file "$PI_DIR/attach-already-parented-response.json"
run_exit0_case "attach:already-parented-exit0" -- \
  attach-subissue --response-file "$PI_DIR/attach-already-parented-response.json"

run_case "attach:cycle-surface" "$EXPECTED_DIR/attach-cycle.json" -- \
  attach-subissue --response-file "$PI_DIR/attach-cycle-response.json"
run_exit0_case "attach:cycle-exit0" -- \
  attach-subissue --response-file "$PI_DIR/attach-cycle-response.json"

# ── attach-subissue: FAIL-CLOSED variants (exit 1) ─────────────────────────────────
# A non-recoverable error (auth/permission), an EMPTY/non-JSON transport body, and a MIXED errors
# array (a cycle alongside a fatal sibling) each MUST surface as nonzero so the caller never treats
# a failed attach as handled. Recoverability is decided over the WHOLE array — a first-error-only
# check would mask the failed write behind a benign cycle.
run_exit1_case "attach:auth-error-exit1" -- \
  attach-subissue --response-file "$PI_DIR/attach-auth-error-response.json"
run_exit1_case "attach:transport-error-exit1" -- \
  attach-subissue --response-file "$PI_DIR/attach-empty-response.json"
run_exit1_case "attach:mixed-errors-exit1" -- \
  attach-subissue --response-file "$PI_DIR/attach-mixed-error-response.json"

# ── list-children: complete single page + multi-field child mapping ────────────────
# A clean single-page subIssues response (pageInfo.hasNextPage=false) normalizes into the stable
# {parent_id, children:[{number,id,title}]} schema. The multifield case exercises a single child
# with a punctuated title to lock the per-field projection.
run_case "list-children:complete-single-page" "$EXPECTED_DIR/list-children-complete.json" -- \
  list-children --response-file "$PI_DIR/list-children-complete-response.json"
run_case "list-children:multifield-mapping" "$EXPECTED_DIR/list-children-multifield.json" -- \
  list-children --response-file "$PI_DIR/list-children-multifield-response.json"

# ── list-children: FAIL-CLOSED variants (exit 1) ───────────────────────────────────
# null .data.node, a non-array subIssues.nodes, a child with a null title, and — the #228 single-
# page lesson — an injected page asserting pageInfo.hasNextPage=true each MUST fail closed so the
# caller never makes attach decisions from a corrupted-into-"no children" or partial set.
run_exit1_case "list-children:null-node-exit1" -- \
  list-children --response-file "$PI_DIR/list-children-null-node-response.json"
run_exit1_case "list-children:non-array-children-exit1" -- \
  list-children --response-file "$PI_DIR/list-children-non-array-response.json"
run_exit1_case "list-children:missing-title-exit1" -- \
  list-children --response-file "$PI_DIR/list-children-missing-title-response.json"
run_exit1_case "list-children:has-next-page-exit1" -- \
  list-children --response-file "$PI_DIR/list-children-paginated-response.json"

# ── list-children: pagination completeness fail-closed (F3) ────────────────────────
# A response with `nodes` but a MISSING pageInfo (so hasNextPage is absent/null) MUST fail
# closed — previously `hasNextPage // false` treated absent pageInfo as a COMPLETE terminal
# page, silently dropping any unfetched children. The offline normalizer now requires
# `hasNextPage | type == "boolean"` AND `== false`, so an absent/null/non-boolean value
# fails closed.
run_exit1_case "list-children:missing-pageinfo-exit1" -- \
  list-children --response-file "$PI_DIR/list-children-missing-pageinfo-response.json"

# ── list-children: node-id allowlist (F4) ──────────────────────────────────────────
# An out-of-charset --parent-id fails closed BEFORE any gh/normalize. (No --response-file:
# the arg-level node-id guard fires first, regardless of seam.)
run_exit1_case "list-children:bad-node-id-exit2" -- \
  list-children --parent-id "I_parent\$(touch x)" \
  --response-file "$PI_DIR/list-children-complete-response.json"

# ── ensure-parent: resolved / created normalization ────────────────────────────────
# With --existing-number the injected repository.issue response normalizes to status:resolved;
# without it (the create path's post-create node-id read) it tags status:created. Both project
# {number, id, status}.
run_case "ensure-parent:resolved" "$EXPECTED_DIR/ensure-parent-resolved.json" -- \
  ensure-parent --title epic --body anchor --existing-number 7 \
  --response-file "$PI_DIR/ensure-parent-resolve-response.json"
run_case "ensure-parent:created" "$EXPECTED_DIR/ensure-parent-created.json" -- \
  ensure-parent --title epic --body anchor \
  --response-file "$PI_DIR/ensure-parent-resolve-response.json"

# ── ensure-parent: FAIL-CLOSED variants (exit 1) ───────────────────────────────────
# A null repository.issue (issue not found) and a GraphQL `.errors` envelope each MUST fail closed
# via the shared kernel so a parent record is never built from an unverifiable read.
run_exit1_case "ensure-parent:null-issue-exit1" -- \
  ensure-parent --existing-number 7 \
  --response-file "$PI_DIR/ensure-parent-null-issue-response.json"
run_exit1_case "ensure-parent:graphql-error-exit1" -- \
  ensure-parent --existing-number 7 \
  --response-file "$PI_DIR/ensure-parent-graphql-error-response.json"

# ── ensure-parent: ORPHAN-SAFE discover-then-create (Q2 DECISION) ───────────────────
# Discovery runs ONLY on the create path (no --existing-number), injected via the dedicated
# --discovery-response-file seam (a repository.issues ENUMERATION response). Resolution rules:
#   (c) exactly ONE OPEN exact-title match -> status resolved-by-title (skip create).
#   (d) ZERO matches -> create unchanged (falls through to the --response-file `created` sim).
#   (e) MULTIPLE exact / a CLOSED exact / divergent -> FAIL CLOSED (never duplicate or reuse
#       a closed epic).
# The shared enumeration machinery (run_title_search/filter_exact_title) is reused — the offline
# discovery transform exercises normalize_find_by_title + resolve_discovery over the fixture.
run_case "ensure-parent:discover-one-open-resolved" "$EXPECTED_DIR/ensure-parent-resolved-by-title.json" -- \
  ensure-parent --title "tracer epic" --body anchor \
  --discovery-response-file "$PI_DIR/ensure-parent-discovery-one-open-response.json"

# ZERO discovery matches -> fall through to the create simulation (status created). Both the
# discovery (empty) and the post-create node-id read (--response-file) fixtures are supplied.
run_case "ensure-parent:discover-zero-create" "$EXPECTED_DIR/ensure-parent-created.json" -- \
  ensure-parent --title "tracer epic" --body anchor \
  --discovery-response-file "$PI_DIR/ensure-parent-discovery-empty-response.json" \
  --response-file "$PI_DIR/ensure-parent-resolve-response.json"

# A single CLOSED exact match MUST fail closed — never silently reuse a closed epic.
run_exit1_case "ensure-parent:discover-closed-exit1" -- \
  ensure-parent --title "tracer epic" --body anchor \
  --discovery-response-file "$PI_DIR/ensure-parent-discovery-closed-response.json"

# COMPLETE candidate-state tuple (closes #273): the lone match is OPEN but PARENTED
# (parent != null) — it is a CHILD sub-issue of another epic, NOT the epic itself. resolve_discovery
# validates {count==1, OPEN, parent==null} as one tuple, so this open-but-parented candidate FAILS
# CLOSED (never reused as the parent epic) rather than being wrongly resolved-by-title.
run_exit1_case "ensure-parent:discover-open-parented-exit1" -- \
  ensure-parent --title "tracer epic" --body anchor \
  --discovery-response-file "$PI_DIR/ensure-parent-discovery-one-open-parented-response.json"

# MULTIPLE exact matches MUST fail closed — never blind-pick among duplicate epics.
run_exit1_case "ensure-parent:discover-multiple-exit1" -- \
  ensure-parent --title "tracer epic" --body anchor \
  --discovery-response-file "$PI_DIR/ensure-parent-discovery-multiple-response.json"

# --discovery-response-file is invalid WITH --existing-number (discovery runs only on the
# create path) — fail closed (exit 2).
run_exit1_case "ensure-parent:discovery-with-existing-number-exit2" -- \
  ensure-parent --existing-number 7 \
  --discovery-response-file "$PI_DIR/ensure-parent-discovery-one-open-response.json"

# ── find-by-title: exact-title candidate discovery (F1) ────────────────────────────
# A repository.issues enumeration with an UNPARENTED candidate (#21, parent:null), an
# ALREADY-ATTACHED candidate (#22, parent:{7}), and a NON-EXACT title (#23 "...extra")
# normalizes to the {title, matches:[{number,id,title,parent}]} schema with ONLY the
# byte-exact-title matches (#21, #22) — the non-exact #23 is dropped by the LOCAL exact-title
# post-filter. parent is null for the orphan and {number,id} for the attached child, so the
# skill can decide attach-vs-reuse per slice.
run_case "find-by-title:exact-matches" "$EXPECTED_DIR/find-by-title-matches.json" -- \
  find-by-title --title "tracer slice A" \
  --response-file "$PI_DIR/find-by-title-response.json"

# An empty enumeration result set normalizes to an empty matches array (a clean no-candidate
# result, NOT a failure) so the skill knows the slice must be created.
run_case "find-by-title:empty" "$EXPECTED_DIR/find-by-title-empty.json" -- \
  find-by-title --title "no such slice" \
  --response-file "$PI_DIR/find-by-title-empty-response.json"

# ── find-by-title: FAIL-CLOSED variants (exit 1) ───────────────────────────────────
# A null repository.issues root, a GraphQL `.errors` envelope, and a node missing a required
# identity field (id) each MUST fail closed via the shared kernel so a candidate set is never
# built from an unverifiable read.
run_exit1_case "find-by-title:null-repo-issues-exit1" -- \
  find-by-title --title "tracer slice A" \
  --response-file "$PI_DIR/find-by-title-null-search-response.json"
run_exit1_case "find-by-title:graphql-error-exit1" -- \
  find-by-title --title "tracer slice A" \
  --response-file "$PI_DIR/find-by-title-graphql-error-response.json"
run_exit1_case "find-by-title:missing-id-exit1" -- \
  find-by-title --title "tracer slice A" \
  --response-file "$PI_DIR/find-by-title-missing-id-response.json"

# A node MISSING `state` MUST fail closed via the shared kernel — state is now a REQUIRED
# identity field (same fail-closed posture as a missing id/number/title). Mirrors missing-id.
run_exit1_case "find-by-title:missing-state-exit1" -- \
  find-by-title --title "tracer slice A" \
  --response-file "$PI_DIR/find-by-title-missing-state-response.json"

# ── find-by-title: CLOSED exact match — state surfaced truthfully ──────────────────
# An enumeration containing a CLOSED exact-title match emits the record with state:"CLOSED". The
# SCRIPT only SURFACES state; classifying a closed match as a CONFLICT is the SKILL's job
# (PRSTEP-003), never baked into the script — so the match is emitted, not dropped.
run_case "find-by-title:closed-match" "$EXPECTED_DIR/find-by-title-closed-match.json" -- \
  find-by-title --title "tracer slice A" \
  --response-file "$PI_DIR/find-by-title-closed-match-response.json"

# ── find-by-title: TERMINAL-PAGE gate — non-terminal offline pages fail closed ────────
# An injected page with pageInfo.hasNextPage=true MUST fail closed (offline seam treats
# the injected page as the COMPLETE result set; a continued page would silently drop
# unfetched candidates). Parallel to list-children:has-next-page-exit1.
run_exit1_case "find-by-title:multipage-exit1" -- \
  find-by-title --title "tracer slice A" \
  --response-file "$PI_DIR/find-by-title-multipage-response.json"

# A response with `nodes` but a MISSING pageInfo (hasNextPage absent/null) MUST fail
# closed — no `// false` default, so absent pageInfo is not silently treated as terminal.
# Parallel to list-children:missing-pageinfo-exit1.
run_exit1_case "find-by-title:missing-pageinfo-exit1" -- \
  find-by-title --title "tracer slice A" \
  --response-file "$PI_DIR/find-by-title-missing-pageinfo-response.json"

# ── find-by-title: bad --repo charset guard fires before gh (exit 2, live path) ──────
# An invalid --repo (contains a third `/` segment or a space/bang) MUST fail closed with
# exit 2 BEFORE any gh call — the owner/repo charset guard fires at the arg-validation
# stage (mirrors attach:bad-node-id / live-reject cases: no SUBISSUE_OPS_OFFLINE, no gh
# needed). Tests two malformed forms: extra slash (a/b/c) and non-charset char (bad!).
BAD_REPO_STATUS=0
bash "$OPS" find-by-title --title "slice" --repo "a/b/c" >/dev/null 2>&1 || BAD_REPO_STATUS=$?
if [ "$BAD_REPO_STATUS" -eq 2 ]; then
  pass "find-by-title:bad-repo-exit2" "exit=2 (a/b/c rejected by charset guard)"
else
  failed "find-by-title:bad-repo-exit2" "expected exit 2 for repo=a/b/c, got $BAD_REPO_STATUS"
fi

BAD_REPO2_STATUS=0
bash "$OPS" find-by-title --title "slice" --repo "bad repo!" >/dev/null 2>&1 || BAD_REPO2_STATUS=$?
if [ "$BAD_REPO2_STATUS" -eq 2 ]; then
  pass "find-by-title:bad-repo-noslash-exit2" "exit=2 (bad repo! rejected by charset guard)"
else
  failed "find-by-title:bad-repo-noslash-exit2" "expected exit 2 for repo='bad repo!', got $BAD_REPO2_STATUS"
fi

# ── Live-mode fixture rejection: --response-file is a TEST SEAM only (exit 2) ───────
# Each subcommand, when invoked LIVE (no SUBISSUE_OPS_OFFLINE) WITH --response-file, MUST be
# rejected fail-closed (exit 2) BEFORE any gh call — the flag could spoof a created/attached/child
# state for a mutation that never ran. The shared guard fires before require_gh, so no gh on PATH
# is needed and the result is deterministic.
for live_case in \
  "attach-subissue:attach-subissue --response-file $PI_DIR/attach-success-response.json" \
  "list-children:list-children --response-file $PI_DIR/list-children-complete-response.json" \
  "ensure-parent:ensure-parent --existing-number 7 --response-file $PI_DIR/ensure-parent-resolve-response.json" \
  "ensure-parent-discovery:ensure-parent --title slice --body anchor --discovery-response-file $PI_DIR/ensure-parent-discovery-one-open-response.json" \
  "find-by-title:find-by-title --title slice --response-file $PI_DIR/find-by-title-response.json" ; do
  cname="${live_case%%:*}"
  cargs="${live_case#*:}"
  LIVE_STATUS=0
  # shellcheck disable=SC2086 # intentional word-split of the fixed, author-static arg string
  bash "$OPS" $cargs >/dev/null 2>&1 || LIVE_STATUS=$?
  if [ "$LIVE_STATUS" -eq 2 ]; then
    pass "$cname:live-response-file-rejected" "exit=2 (live seam rejected)"
  else
    failed "$cname:live-response-file-rejected" "expected exit 2, got $LIVE_STATUS (live path must reject --response-file)"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────────
echo
echo "subissue-ops: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
