#!/usr/bin/env bash
#
# Behavioral unit runner for the prd-to-issues MECHANISM substrate (native sub-issues, STEP-002).
#
# OFFLINE jq/bash/git TEST — CI-runnable with ONLY jq + bash + git present (NO gh / network /
# auth: the live cases put a recording gh stub first on PATH and use local repositories). It
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
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required to run this suite" >&2; exit 2; }

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

# run_exit2_case <case> -- <ops-arg...>
# Asserts the OFFLINE script exited with EXACTLY 2 (a usage error caught before any read).
run_exit2_case() {
  local case_name="$1"; shift
  [ "$1" = "--" ] && shift
  local out status
  out="$(SUBISSUE_OPS_OFFLINE=1 bash "$OPS" "$@" 2>/dev/null)"
  status=$?
  if [ "$status" -eq 2 ]; then
    pass "$case_name" "exit=2 (args: $*)"
  else
    failed "$case_name" "expected exit 2, got $status (args: $*; stdout: $out)"
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

# ── ensure-parent --slug: seed issue marker (#617) ─────────────────────────────────
# With --existing-number and --slug the resolve read carries the epic body; seed is true only when
# its first line is the seed issue marker naming the slug. A CRLF marker line still counts.
# Another initiative's marker, or no marker, gives seed false. All four fixtures share number 7
# and id I_epic7, so one not-seed golden covers both negative cases.
SEED_SLUG="demo-initiative"
run_case "ensure-parent:seed-marker" "$EXPECTED_DIR/ensure-parent-seed.json" -- \
  ensure-parent --existing-number 7 --slug "$SEED_SLUG" \
  --response-file "$PI_DIR/ensure-parent-seed-response.json"
run_case "ensure-parent:seed-marker-crlf" "$EXPECTED_DIR/ensure-parent-seed.json" -- \
  ensure-parent --existing-number 7 --slug "$SEED_SLUG" \
  --response-file "$PI_DIR/ensure-parent-seed-crlf-response.json"
run_case "ensure-parent:other-seed-marker" "$EXPECTED_DIR/ensure-parent-not-seed.json" -- \
  ensure-parent --existing-number 7 --slug "$SEED_SLUG" \
  --response-file "$PI_DIR/ensure-parent-other-seed-response.json"
run_case "ensure-parent:no-seed-marker" "$EXPECTED_DIR/ensure-parent-not-seed.json" -- \
  ensure-parent --existing-number 7 --slug "$SEED_SLUG" \
  --response-file "$PI_DIR/ensure-parent-no-marker-response.json"

# --slug is valid only with --existing-number, and a malformed slug is a usage error: both exit 2.
# The existing body-less resolve fixture under --slug has no string body, so it fails closed.
run_exit2_case "ensure-parent:slug-without-existing-number-exit2" -- \
  ensure-parent --title epic --body anchor --slug "$SEED_SLUG" \
  --response-file "$PI_DIR/ensure-parent-seed-response.json"
run_exit2_case "ensure-parent:malformed-slug-exit2" -- \
  ensure-parent --existing-number 7 --slug "Demo_Initiative" \
  --response-file "$PI_DIR/ensure-parent-seed-response.json"
run_exit1_case "ensure-parent:slug-body-less-resolve-exit1" -- \
  ensure-parent --existing-number 7 --slug "$SEED_SLUG" \
  --response-file "$PI_DIR/ensure-parent-resolve-response.json"

# ── Scratch git environment and the recording gh stub ──────────────────────────────
# Git runs with a scratch HOME and no system config, so no user hook, template or signing setting
# reaches the scratch repositories. The gh stub records the first two argv words of every call and
# answers `api graphql` with the file named by SUBISSUE_TEST_GH_RESPONSE; any other call exits 1.
export HOME="$TMPDIR_TEST/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=subissue-test GIT_AUTHOR_EMAIL=subissue-test@example.invalid
export GIT_COMMITTER_NAME=subissue-test GIT_COMMITTER_EMAIL=subissue-test@example.invalid
mkdir -p "$HOME" || { echo "FAIL: cannot create scratch HOME" >&2; exit 2; }

GH_STUB_DIR="$TMPDIR_TEST/gh-bin"
GH_LOG="$TMPDIR_TEST/gh-calls.log"
mkdir -p "$GH_STUB_DIR" || { echo "FAIL: cannot create the gh stub dir" >&2; exit 2; }
# shellcheck disable=SC2016 # the stub's own $-expansions are written literally
printf '%s\n' '#!/bin/sh' \
  'printf "%s %s\n" "$1" "$2" >>"$SUBISSUE_TEST_GH_LOG"' \
  'if [ "$1 $2" = "api graphql" ]; then cat "$SUBISSUE_TEST_GH_RESPONSE"; exit 0; fi' \
  'exit 1' >"$GH_STUB_DIR/gh" \
  && chmod +x "$GH_STUB_DIR/gh" \
  || { echo "FAIL: cannot write the recording gh stub" >&2; exit 2; }

# setup_fail <message>: a scratch setup step failed; the suite cannot run.
setup_fail() { echo "FAIL: setup: $1" >&2; exit 2; }

# run_live_ops <dir> <gh-response> -- <ops-arg...>
# Runs subissue-ops.sh LIVE (SUBISSUE_OPS_OFFLINE unset) in <dir> with the recording gh stub first
# on PATH, after emptying the gh call log. Sets LIVE_OUT (stdout) and LIVE_STATUS.
run_live_ops() {
  local dir="$1" gh_response="$2"; shift 2
  [ "$1" = "--" ] && shift
  : >"$GH_LOG" || setup_fail "cannot empty the gh call log"
  LIVE_STATUS=0
  LIVE_OUT="$(cd "$dir" && env -u SUBISSUE_OPS_OFFLINE PATH="$GH_STUB_DIR:$PATH" \
    SUBISSUE_TEST_GH_LOG="$GH_LOG" SUBISSUE_TEST_GH_RESPONSE="$gh_response" \
    bash "$OPS" "$@" 2>/dev/null)" || LIVE_STATUS=$?
}

# count_gh_calls <first-two-words>: prints how many logged gh calls began with those words.
count_gh_calls() { grep -c -x -F -- "$1" "$GH_LOG"; }

# ── ensure-parent --slug: live seed resolve ────────────────────────────────────────
# Live with --repo, the seed resolve makes exactly ONE `api graphql` call and never creates or
# edits an issue, so the seed's marker line stays first. A second run gives the same output: no
# duplicate epic.
SEED_GOLDEN="$(canon <"$EXPECTED_DIR/ensure-parent-seed.json")"
SEED_FIRST_OUT=""
for seed_run in 1 2; do
  run_live_ops "$TMPDIR_TEST" "$PI_DIR/ensure-parent-seed-response.json" -- \
    ensure-parent --existing-number 7 --slug "$SEED_SLUG" --repo demo-owner/demo-repo
  seed_actual="$(printf '%s' "$LIVE_OUT" | canon 2>/dev/null)"
  graphql_calls="$(count_gh_calls "api graphql")"
  total_calls="$(wc -l <"$GH_LOG" | tr -d ' ')"
  if [ "$LIVE_STATUS" -eq 0 ] && [ "$seed_actual" = "$SEED_GOLDEN" ] \
    && [ "$graphql_calls" = 1 ] && [ "$total_calls" = 1 ]; then
    pass "ensure-parent:live-seed-resolve-run$seed_run" "one api graphql call, no issue create or edit"
  else
    failed "ensure-parent:live-seed-resolve-run$seed_run" "status=$LIVE_STATUS graphql=$graphql_calls total=$total_calls
    gh calls: $(tr '\n' ';' <"$GH_LOG")
    expected: $SEED_GOLDEN
    actual:   $seed_actual"
  fi
  [ "$seed_run" = 1 ] && SEED_FIRST_OUT="$LIVE_OUT"
done
if [ -n "$LIVE_OUT" ] && [ "$LIVE_OUT" = "$SEED_FIRST_OUT" ]; then
  pass "ensure-parent:live-seed-rerun-identical" "second run output equals the first"
else
  failed "ensure-parent:live-seed-rerun-identical" "first: $SEED_FIRST_OUT second: $LIVE_OUT"
fi

# A malformed slug, and --slug without --existing-number, exit 2 live BEFORE any gh call.
for slug_case in \
  "malformed-slug:--existing-number 7 --slug demo--initiative --repo demo-owner/demo-repo" \
  "slug-without-existing-number:--title epic --body anchor --slug demo-initiative --repo demo-owner/demo-repo" ; do
  cname="${slug_case%%:*}"
  # shellcheck disable=SC2086 # intentional word-split of the fixed, author-static arg string
  run_live_ops "$TMPDIR_TEST" "$PI_DIR/ensure-parent-seed-response.json" -- \
    ensure-parent ${slug_case#*:}
  if [ "$LIVE_STATUS" -eq 2 ] && [ ! -s "$GH_LOG" ]; then
    pass "ensure-parent:live-$cname-exit2" "exit=2, no gh call"
  else
    failed "ensure-parent:live-$cname-exit2" "status=$LIVE_STATUS gh calls: $(tr '\n' ';' <"$GH_LOG")"
  fi
done

# ── design-gate: offline, one scratch repository per case ──────────────────────────
# Each case builds its own scratch repository, commits a design state on branch main and writes a
# --trunk-response-file holding that commit's id. design-gate reads every document at the commit
# through the shared readiness check library, so work-tree files never count.
DG_SLUG="demo-initiative"
DG_PRD="docs/prds/$DG_SLUG.md"
DG_INDEX="docs/initiatives/$DG_SLUG/prototype/index.html"
DG_NOTES="docs/initiatives/$DG_SLUG/prototype/notes.md"
DG_RECORD="docs/initiatives/$DG_SLUG/review-record.md"
DG_REPO_SEQ=0

# create_repo <var> [<branch>]: assigns <var> a fresh scratch repository under TMPDIR_TEST whose
# HEAD names refs/heads/<branch> (default main).
create_repo() {
  local repo_dir branch="${2:-main}"
  DG_REPO_SEQ=$((DG_REPO_SEQ + 1))
  repo_dir="$TMPDIR_TEST/repo.$DG_REPO_SEQ"
  git init -q "$repo_dir" || setup_fail "git init $repo_dir"
  git -C "$repo_dir" symbolic-ref HEAD "refs/heads/$branch" || setup_fail "symbolic-ref in $repo_dir"
  printf -v "$1" '%s' "$repo_dir"
}

# write_file <repo> <path> <bytes>: writes <bytes> to <path> in the work tree of <repo>.
write_file() {
  mkdir -p "$1/$(dirname "$2")" && printf '%s' "$3" >"$1/$2" || setup_fail "cannot write $1/$2"
}

# copy_prd <repo> <fixture-name>: places a PRD fixture at the demo initiative's PRD path.
copy_prd() {
  mkdir -p "$1/docs/prds" && cp "$PI_DIR/$2" "$1/$DG_PRD" || setup_fail "cannot copy $2"
}

# remove_file <repo> <path>: deletes one work-tree file of <repo>.
remove_file() {
  rm -f -- "${1:?}/${2:?}" || setup_fail "cannot remove $1/$2"
}

# hash_path <repo> <path>: prints the blob id of the work-tree file, or of empty bytes when absent.
hash_path() {
  if [ -e "$1/$2" ]; then
    git -C "$1" hash-object -- "$2"
  else
    printf '' | git -C "$1" hash-object --stdin
  fi
}

# write_record <repo> <verdict> <rounds> <open-medium> <clean-round> <stamp-path>...
# Writes the review record whose front matter stamps each <stamp-path> with its work-tree blob id.
write_record() {
  local repo="$1" verdict="$2" rounds="$3" medium="$4" clean="$5" path blob
  local record=$'---\nstamps:\n'
  shift 5
  for path in "$@"; do
    blob="$(hash_path "$repo" "$path")" || setup_fail "hash-object $path"
    record+="  - path: $path"$'\n'"    blob: $blob"$'\n'
  done
  record+="verdict: $verdict"$'\nopen:\n  critical: 0\n  high: 0\n'
  record+="  medium: $medium"$'\n  low: 0\n'"rounds: $rounds"$'\n'"clean_round: $clean"$'\n---\n\n# Review record\n'
  write_file "$repo" "$DG_RECORD" "$record"
}

# stage_passing_design <repo>: writes a UI yes PRD, both prototype files and a passing record
# stamping both with their blob ids, without committing.
stage_passing_design() {
  copy_prd "$1" design-gate-prd-ui-yes.md
  write_file "$1" "$DG_INDEX" $'<!doctype html>\n<title>Demo</title>\n'
  write_file "$1" "$DG_NOTES" $'# Prototype notes\n\nDemo screen.\n'
  write_record "$1" pass 2 0 true "$DG_INDEX" "$DG_NOTES"
}

# commit_paths <repo> [<path>...]: commits exactly <path>... (default: the whole work tree).
commit_paths() {
  local repo="$1"; shift
  if [ "$#" -eq 0 ]; then
    git -C "$repo" add -A || setup_fail "git add in $repo"
  else
    git -C "$repo" add -- "$@" || setup_fail "git add in $repo"
  fi
  git -C "$repo" -c commit.gpgsign=false commit -q --no-verify -m "design state" \
    || setup_fail "git commit in $repo"
}

# write_trunk_response <file> <name> <oid>: writes a repository.defaultBranchRef response.
write_trunk_response() {
  jq -n -c --arg name "$2" --arg oid "$3" \
    '{data: {repository: {defaultBranchRef: {name: $name, target: {oid: $oid}}}}}' >"$1" \
    || setup_fail "cannot write $1"
}

# run_design_gate <repo> <trunk-file>: runs design-gate OFFLINE in <repo>. Sets DG_OUT, DG_STATUS.
run_design_gate() {
  DG_STATUS=0
  DG_OUT="$(cd "$1" && SUBISSUE_OPS_OFFLINE=1 bash "$OPS" design-gate --slug "$DG_SLUG" \
    --trunk-response-file "$2" 2>/dev/null)" || DG_STATUS=$?
}

# assert_design_case <case> <repo> <ui> <result> <reasons-json>
# Writes a trunk response naming main at the repository's HEAD commit, runs design-gate offline
# and asserts exit 0 and exactly {commit, trunk:"main", slug, ui, result, reasons}.
assert_design_case() {
  local case_name="$1" repo="$2" ui="$3" result="$4" reasons="$5" commit trunk_file
  commit="$(git -C "$repo" rev-parse HEAD)" || setup_fail "rev-parse HEAD in $repo"
  trunk_file="$repo.trunk.json"
  write_trunk_response "$trunk_file" main "$commit"
  run_design_gate "$repo" "$trunk_file"
  if [ "$DG_STATUS" -eq 0 ] && printf '%s' "$DG_OUT" | jq -e --arg commit "$commit" \
      --arg slug "$DG_SLUG" --arg ui "$ui" --arg result "$result" --argjson reasons "$reasons" '
      (keys | sort) == ["commit","reasons","result","slug","trunk","ui"]
      and .commit == $commit and .trunk == "main" and .slug == $slug
      and .ui == $ui and .result == $result and .reasons == $reasons' >/dev/null 2>&1; then
    pass "$case_name" "ui=$ui result=$result reasons=$reasons"
  else
    failed "$case_name" "status=$DG_STATUS expected ui=$ui result=$result reasons=$reasons
    actual: $DG_OUT"
  fi
}

# UI no passes; a PRD with no UI line reads as no and passes.
create_repo DG_REPO; copy_prd "$DG_REPO" design-gate-prd-ui-no.md; commit_paths "$DG_REPO"
assert_design_case "design-gate:ui-no-pass" "$DG_REPO" no pass '[]'
create_repo DG_REPO; copy_prd "$DG_REPO" design-gate-prd-no-ui-line.md; commit_paths "$DG_REPO"
assert_design_case "design-gate:no-ui-line-pass" "$DG_REPO" no pass '[]'

# UI yes with both prototype files and a passing record stamping both passes.
create_repo DG_REPO; stage_passing_design "$DG_REPO"; commit_paths "$DG_REPO"
assert_design_case "design-gate:ui-yes-pass" "$DG_REPO" yes pass '[]'

# A missing index.html, or notes.md committed as a symlink, fails the Document existence test,
# which also stales that file's stamp.
create_repo DG_REPO; stage_passing_design "$DG_REPO"; remove_file "$DG_REPO" "$DG_INDEX"
commit_paths "$DG_REPO"
assert_design_case "design-gate:index-missing-refuse" "$DG_REPO" yes refuse \
  '["prototype_missing","record_stale:docs/initiatives/demo-initiative/prototype/index.html"]'
create_repo DG_REPO; stage_passing_design "$DG_REPO"; remove_file "$DG_REPO" "$DG_NOTES"
ln -s index.html "$DG_REPO/$DG_NOTES" || setup_fail "symlink notes.md"
commit_paths "$DG_REPO"
assert_design_case "design-gate:notes-symlink-refuse" "$DG_REPO" yes refuse \
  '["prototype_missing","record_stale:docs/initiatives/demo-initiative/prototype/notes.md"]'

# No docs/initiatives/<slug>/ at all: both prototype_missing and record_missing.
create_repo DG_REPO; copy_prd "$DG_REPO" design-gate-prd-ui-yes.md; commit_paths "$DG_REPO"
assert_design_case "design-gate:no-initiative-dir-refuse" "$DG_REPO" yes refuse \
  '["prototype_missing","record_missing"]'

# Each pass-rule clause maps to its own code.
create_repo DG_REPO; stage_passing_design "$DG_REPO"
write_record "$DG_REPO" fail 2 0 true "$DG_INDEX" "$DG_NOTES"; commit_paths "$DG_REPO"
assert_design_case "design-gate:verdict-fail-refuse" "$DG_REPO" yes refuse '["record_not_passed"]'
create_repo DG_REPO; stage_passing_design "$DG_REPO"
write_record "$DG_REPO" pass 4 0 true "$DG_INDEX" "$DG_NOTES"; commit_paths "$DG_REPO"
assert_design_case "design-gate:rounds-4-refuse" "$DG_REPO" yes refuse '["record_rounds_exceeded"]'
create_repo DG_REPO; stage_passing_design "$DG_REPO"
write_record "$DG_REPO" pass 2 1 true "$DG_INDEX" "$DG_NOTES"; commit_paths "$DG_REPO"
assert_design_case "design-gate:open-medium-refuse" "$DG_REPO" yes refuse '["record_open"]'

# A record stamping only index.html leaves notes.md unstamped.
create_repo DG_REPO; stage_passing_design "$DG_REPO"
write_record "$DG_REPO" pass 2 0 true "$DG_INDEX"; commit_paths "$DG_REPO"
assert_design_case "design-gate:notes-unstamped-refuse" "$DG_REPO" yes refuse \
  '["record_unstamped:docs/initiatives/demo-initiative/prototype/notes.md"]'

# A prototype file edited after the record stamped it gives record_stale:<path>, for each file.
for dg_stale_path in "$DG_INDEX" "$DG_NOTES"; do
  create_repo DG_REPO; stage_passing_design "$DG_REPO"
  write_file "$DG_REPO" "$dg_stale_path" $'edited after review\n'; commit_paths "$DG_REPO"
  assert_design_case "design-gate:stale-${dg_stale_path##*/}-refuse" "$DG_REPO" yes refuse \
    "[\"record_stale:$dg_stale_path\"]"
done

# Front matter that does not parse gives record_malformed.
create_repo DG_REPO; stage_passing_design "$DG_REPO"
write_file "$DG_REPO" "$DG_RECORD" $'---\nverdict: pass\n---\n\n# Review record\n'
commit_paths "$DG_REPO"
assert_design_case "design-gate:record-malformed-refuse" "$DG_REPO" yes refuse '["record_malformed"]'

# Prototype files present only in the work tree, never committed, still refuse, and stale both stamps.
create_repo DG_REPO; stage_passing_design "$DG_REPO"
commit_paths "$DG_REPO" "$DG_PRD" "$DG_RECORD"
if [ -f "$DG_REPO/$DG_INDEX" ] && [ -f "$DG_REPO/$DG_NOTES" ]; then
  assert_design_case "design-gate:work-tree-only-prototype-refuse" "$DG_REPO" yes refuse \
    '["prototype_missing","record_stale:docs/initiatives/demo-initiative/prototype/index.html","record_stale:docs/initiatives/demo-initiative/prototype/notes.md"]'
else
  failed "design-gate:work-tree-only-prototype-refuse" "setup lost the work-tree prototype files"
fi

# A commit id absent from the repository, or a branch name in its place, exits nonzero with no
# output.
create_repo DG_REPO; copy_prd "$DG_REPO" design-gate-prd-ui-no.md; commit_paths "$DG_REPO"
for dg_oid_case in "absent-commit:0123456789abcdef0123456789abcdef01234567" "branch-name:main"; do
  cname="${dg_oid_case%%:*}"
  write_trunk_response "$DG_REPO.$cname.json" main "${dg_oid_case#*:}"
  run_design_gate "$DG_REPO" "$DG_REPO.$cname.json"
  if [ "$DG_STATUS" -ne 0 ] && [ -z "$DG_OUT" ]; then
    pass "design-gate:$cname-exit-nonzero" "exit=$DG_STATUS, no output"
  else
    failed "design-gate:$cname-exit-nonzero" "status=$DG_STATUS output: $DG_OUT"
  fi
done

# --trunk-response-file without SUBISSUE_OPS_OFFLINE is rejected (exit 2) before any gh call.
DG_HEAD="$(git -C "$DG_REPO" rev-parse HEAD)" || setup_fail "rev-parse HEAD in $DG_REPO"
write_trunk_response "$DG_REPO.live-reject.json" main "$DG_HEAD"
run_live_ops "$DG_REPO" "$DG_REPO.live-reject.json" -- \
  design-gate --slug "$DG_SLUG" --trunk-response-file "$DG_REPO.live-reject.json"
if [ "$LIVE_STATUS" -eq 2 ] && [ ! -s "$GH_LOG" ]; then
  pass "design-gate:live-response-file-rejected" "exit=2, no gh call"
else
  failed "design-gate:live-response-file-rejected" "status=$LIVE_STATUS gh calls: $(tr '\n' ';' <"$GH_LOG")"
fi

# ── design-gate: live, local bare origin ───────────────────────────────────────────
# A source repository pushes a passing UI yes design to a local bare origin. A consumer repository
# that lacks that commit runs design-gate live: the gh stub answers defaultBranchRef with origin's
# main commit id and the fetch brings the commit in. The fetch writes FETCH_HEAD only: the
# consumer's refs, local branches and remote-tracking refs alike, are unchanged, and the result
# equals the offline run's.
create_repo DG_SOURCE; stage_passing_design "$DG_SOURCE"; commit_paths "$DG_SOURCE"
DG_LIVE_COMMIT="$(git -C "$DG_SOURCE" rev-parse HEAD)" || setup_fail "rev-parse source HEAD"
DG_ORIGIN="$TMPDIR_TEST/origin.git"
git init -q --bare "$DG_ORIGIN" || setup_fail "git init --bare"
git -C "$DG_SOURCE" push -q "$DG_ORIGIN" main:refs/heads/main || setup_fail "push to origin"
create_repo DG_CONSUMER work
write_file "$DG_CONSUMER" README.md $'consumer\n'; commit_paths "$DG_CONSUMER"
git -C "$DG_CONSUMER" remote add origin "$DG_ORIGIN" || setup_fail "remote add origin"
DG_LIVE_TRUNK="$TMPDIR_TEST/live-trunk.json"
write_trunk_response "$DG_LIVE_TRUNK" main "$DG_LIVE_COMMIT"

if git -C "$DG_CONSUMER" cat-file -e "$DG_LIVE_COMMIT" 2>/dev/null; then
  setup_fail "consumer already holds the origin commit"
fi
DG_REFS_BEFORE="$(git -C "$DG_CONSUMER" for-each-ref --format='%(refname) %(objectname)')" \
  || setup_fail "for-each-ref before"
run_live_ops "$DG_CONSUMER" "$DG_LIVE_TRUNK" -- \
  design-gate --slug "$DG_SLUG" --repo demo-owner/demo-repo
DG_LIVE_OUT="$LIVE_OUT"
DG_LIVE_STATUS="$LIVE_STATUS"
DG_LIVE_GRAPHQL="$(count_gh_calls "api graphql")"
DG_REFS_AFTER="$(git -C "$DG_CONSUMER" for-each-ref --format='%(refname) %(objectname)')" \
  || setup_fail "for-each-ref after"

if [ "$DG_LIVE_STATUS" -eq 0 ] && [ "$DG_LIVE_GRAPHQL" = 1 ] && printf '%s' "$DG_LIVE_OUT" \
    | jq -e --arg commit "$DG_LIVE_COMMIT" \
      '.commit == $commit and .trunk == "main" and .ui == "yes" and .result == "pass"
       and .reasons == []' >/dev/null 2>&1; then
  pass "design-gate:live-pass" "one api graphql call, commit fetched"
else
  failed "design-gate:live-pass" "status=$DG_LIVE_STATUS graphql=$DG_LIVE_GRAPHQL output: $DG_LIVE_OUT"
fi
if [ "$DG_REFS_AFTER" = "$DG_REFS_BEFORE" ] \
  && ! git -C "$DG_CONSUMER" rev-parse --verify -q refs/remotes/origin/main >/dev/null \
  && ! git -C "$DG_CONSUMER" rev-parse --verify -q refs/heads/main >/dev/null \
  && grep -q -F "$DG_LIVE_COMMIT" "$DG_CONSUMER/.git/FETCH_HEAD" 2>/dev/null; then
  pass "design-gate:live-fetch-head-only" "no local branch, no remote-tracking ref"
else
  failed "design-gate:live-fetch-head-only" "refs before: $DG_REFS_BEFORE
    refs after:  $DG_REFS_AFTER"
fi
run_design_gate "$DG_CONSUMER" "$DG_LIVE_TRUNK"
if [ "$DG_STATUS" -eq 0 ] && [ -n "$DG_OUT" ] && [ "$DG_OUT" = "$DG_LIVE_OUT" ]; then
  pass "design-gate:live-equals-offline" "live and offline output identical"
else
  failed "design-gate:live-equals-offline" "live: $DG_LIVE_OUT offline: $DG_OUT (status $DG_STATUS)"
fi

# A trunk that moved forward after the trunk read: origin's main gains a commit editing index.html.
# The gate reads the fetched tip, not the older commit the read named, so it reports the new tip
# and refuses on the now-stale stamp.
write_file "$DG_SOURCE" "$DG_INDEX" $'edited after review\n'; commit_paths "$DG_SOURCE"
DG_FF_COMMIT="$(git -C "$DG_SOURCE" rev-parse HEAD)" || setup_fail "rev-parse source HEAD"
git -C "$DG_SOURCE" push -q "$DG_ORIGIN" main:refs/heads/main || setup_fail "fast-forward origin"
run_live_ops "$DG_CONSUMER" "$DG_LIVE_TRUNK" -- \
  design-gate --slug "$DG_SLUG" --repo demo-owner/demo-repo
if [ "$LIVE_STATUS" -eq 0 ] && printf '%s' "$LIVE_OUT" | jq -e --arg commit "$DG_FF_COMMIT" \
    --arg stale "record_stale:$DG_INDEX" \
    '.commit == $commit and .result == "refuse" and .reasons == [$stale]' >/dev/null 2>&1; then
  pass "design-gate:live-fast-forward-reads-tip" "fetched tip read, stale stamp refused"
else
  failed "design-gate:live-fast-forward-reads-tip" "status=$LIVE_STATUS output: $LIVE_OUT"
fi

# A trunk force-pushed to unrelated history after the trunk read: the read's commit is still in
# the consumer's object store from the earlier fetch, but is no ancestor of the fetched tip, so
# design-gate fails closed with no output.
create_repo DG_REWRITE; copy_prd "$DG_REWRITE" design-gate-prd-ui-no.md; commit_paths "$DG_REWRITE"
git -C "$DG_REWRITE" push -q -f "$DG_ORIGIN" main:refs/heads/main || setup_fail "force-push to origin"
git -C "$DG_CONSUMER" cat-file -e "$DG_LIVE_COMMIT" 2>/dev/null \
  || setup_fail "consumer lost the earlier origin commit"
run_live_ops "$DG_CONSUMER" "$DG_LIVE_TRUNK" -- \
  design-gate --slug "$DG_SLUG" --repo demo-owner/demo-repo
if [ "$LIVE_STATUS" -ne 0 ] && [ -z "$LIVE_OUT" ]; then
  pass "design-gate:live-force-pushed-refuse" "exit=$LIVE_STATUS, no output"
else
  failed "design-gate:live-force-pushed-refuse" "status=$LIVE_STATUS output: $LIVE_OUT"
fi

# A rejected value quoted in a diagnostic reaches stderr with no control byte.
DIE_ERR="$(SUBISSUE_OPS_OFFLINE=1 bash "$OPS" design-gate --slug $'bad\033[31m\nslug' 2>&1 >/dev/null)"
DIE_STATUS=$?
if [ "$DIE_STATUS" -eq 2 ] && ! printf '%s' "$DIE_ERR" | LC_ALL=C grep -q $'\033' \
    && [ "$(printf '%s\n' "$DIE_ERR" | wc -l | tr -d ' ')" = 1 ]; then
  pass "die:control-bytes-dropped" "exit=2, one stderr line, no escape byte"
else
  failed "die:control-bytes-dropped" "status=$DIE_STATUS stderr: $(printf '%q' "$DIE_ERR")"
fi

# ── Summary ───────────────────────────────────────────────────────────────────────
echo
echo "subissue-ops: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
