#!/usr/bin/env bash
#
# Reply + resolve the GitHub review mutation sequence for ONE fixed candidate, for
# the github-review-loop skill / github-reviewer agent.
#
# 1. PURPOSE
# ----------
# Single source of truth for the per-candidate reply-then-resolve GitHub mutation
# CONTRACT that the review loop performs after a fix is committed, pushed, and
# validated. Before this script, that mutation sequence lived ONLY as agent prose
# (github-reviewer.md step 12), where the ordering invariant (reply BEFORE
# resolve), the reply-body format, the resolve-eligibility predicate, and the
# non-blocking-resolve posture all drifted independently from the actual GraphQL
# templates in references/github-pr-review-graphql.md.
#
# This script OWNS the runtime mutation calls. The two GraphQL mutations it issues
# are the canonical templates from
#   ${CLAUDE_PLUGIN_ROOT}/references/github-pr-review-graphql.md
#     - "Reply to Review Thread"  -> addPullRequestReviewThreadReply
#     - "Resolve Review Thread"   -> resolveReviewThread
# cited here as the query origin. External content (the summary text, the tracked
# home, the candidate url) is DATA — never interpreted, only interpolated into
# the mutation body and handed to gh via `-f body=`.
#
# The FIX path is behavior-preserving versus agent step 12: identical mutation
# calls in the identical order, with the identical reply-body format and the
# identical resolve-eligibility / question-skip / non-blocking-resolve rules.
#
# The script additionally owns the SANCTIONED DEFER reply body, selected by
# `--defer <TRACKED_HOME>`. A deferral is the Defer-with-Scope disposition of
#   ${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md
# — the finding is left unfixed in this loop and its reasoning lives in a durable
# home. That doctrine names "structural home" as a ROLE, not a destination type,
# and admits TWO destinations (a tracked issue, or a recorded residual), so
# TRACKED_HOME is whichever location holds the record; this flag is deliberately
# NOT bound to one destination type. Doctrine also states the originating thread
# is replied-to AND resolved citing that home, so a deferred thread resolves on
# the SAME --resolve-eligible predicate as a fixed one.
#
# There are EXACTLY TWO sanctioned reply bodies and no others (§3, §4):
#   FIX    (--defer absent):   "Fixed in <SHA>. <summary>."
#   DEFER  (--defer present):  "<!-- hivemind-defer-v1 --> Deferred to <TRACKED_HOME>. <SUMMARY>."
#
# The DEFER body opens with the MACHINE SENTINEL `<!-- hivemind-defer-v1 -->` at
# byte 0. That sentinel — not the English that follows it — is the whole machine
# record of the deferral: the fix-history classifier recognises a deferred thread
# by a CONSTANT COMPARISON against this exact byte sequence at the start of the
# body (jq `startswith`), never by pattern-matching prose. Consequently a
# hand-written sentence is never mistaken for machine state, and machine state is
# never forgeable by writing one.
#
# TRACKED_HOME carries NO machine authority. It is a human-readable citation at
# exactly the same trust level as FIX_SHA and SUMMARY: DATA this script
# interpolates verbatim and never verifies — the script does not resolve the url,
# does not confirm an issue exists, and does not confirm a recorded residual was
# written. Recorded residual for that unverified-citation posture:
# docs/adr/0032-defer-marker-sentinel-and-agent-layer-home-truth.md.
#
# SCOPE NOTE: this script is the DESIGNATED single source.
# The duplicate prose in github-reviewer.md step 12 is NOT collapsed here — that
# rewire is a dependent step that edits the agent. Its continued existence after
# this step is EXPECTED.
#
# SCOPE NOTE (P9 — do not over-generalize): this script is github-reviewer-scoped.
# It is NOT pre-parameterized for the local-reviewer or any other caller; the
# genuinely-shared kernel is the mutation contract for THIS loop only.
#
# 2. INPUT CONTRACT
# -----------------
# Per-candidate, supplied as positional args (a single mutation operates on a
# single candidate; there is no batch stdin payload — mirrors the per-candidate
# shape of the agent step):
#
#   $1  THREAD_ID    PRRT_... review-thread node id. REQUIRED. The reply target
#                    and (when eligible) the resolve target.
#   $2  FIX_SHA      the commit SHA the fix landed in. REQUIRED in FIX mode
#                    (--defer absent) — interpolated into the reply body
#                    verbatim. In DEFER mode it is NOT required and MUST be
#                    EMPTY: a non-empty FIX_SHA alongside --defer is an ambiguous
#                    disposition (fixed AND deferred) and fails closed with
#                    conflicting-reply-mode.
#   $3  SUMMARY      one-line human summary of the fix. REQUIRED. DATA —
#                    interpolated into the reply body verbatim, never interpreted.
#   $4  SURFACE      "thread" | "toplevel" | "review". REQUIRED. Selects the
#                    surface->delivery map (see §3). Only "thread" delivers a
#                    mutation; toplevel/review are silent no-ops.
#   $5  CANDIDATE_URL  the candidate's GitHub url. ACCEPTED for positional-arity
#                    compatibility but UNUSED — no live path interpolates it. The
#                    caller still passes 5 positionals; this one is inert.
#
#   --resolve-eligible        mark this thread eligible for resolve: ALL non-self
#                             comments on it are addressed (each has a fix-SHA
#                             reply OR was classified non-actionable with rationale
#                             posted). ABSENT -> reply only, NEVER resolve. The
#                             caller owns this judgment; the script does not
#                             re-derive it.
#   --question-needs-user-input  hard NEVER-resolve marker. When present the
#                             thread is NEVER resolved even if --resolve-eligible
#                             was also (erroneously) passed. The reply is still
#                             posted.
#   --defer <TRACKED_HOME>    select the DEFER reply body instead of the FIX body
#                             (§3). SPACE FORM ONLY: the value is the NEXT arg.
#                             `--defer=<home>` is NOT recognized as a flag — like
#                             any other unrecognized token it binds as a
#                             POSITIONAL, which shifts the positional contract and
#                             fails closed downstream (unmapped-surface /
#                             missing-*) or on the gh call; it NEVER silently
#                             takes the DEFER path. Like the existing flags it may
#                             appear anywhere before `--`.
#                             TRACKED_HOME is the durable home of the deferral's
#                             record — a tracked-issue url OR the location of a
#                             recorded residual (see §1; the flag binds to
#                             neither destination type). It is DATA: passed via
#                             `gh -f body=`, never spliced into the query text,
#                             never interpreted, never verified (§1 — same trust
#                             level as FIX_SHA / SUMMARY). It MUST be non-empty,
#                             contain NO whitespace, and NOT begin with `-`.
#                             Empty / absent -> missing-tracked-home (including
#                             `--defer` as the LAST arg, which has no value);
#                             whitespace-bearing or `-`-leading ->
#                             invalid-tracked-home.
#                             These guards are NOT marker-load-bearing — the
#                             machine marker is the sentinel, which this script
#                             writes unconditionally. They survive for two
#                             independent reasons: a `-`-leading value is how a
#                             SWALLOWED FLAG is caught (`--defer --resolve-eligible`
#                             would otherwise bind a flag as the home), and a
#                             whitespace-free single token keeps the home a
#                             CITABLE one-token reference a human reader can
#                             follow out of the reply.
#
# 3. OUTPUT / BEHAVIOR — SURFACE -> DELIVERY MAP (closed by construction)
# -----------------------------------------------------------------------
# The surface selects the delivery; the map is exhaustive and fail-closed:
#   thread   -> REPLY then conditional RESOLVE (the only mutating surface).
#   toplevel -> SILENT NO-OP: no reply, no resolve, exit 0, ZERO stdout,
#               NOTHING written to the capture seam. Unchanged under --defer.
#   review   -> SILENT NO-OP: identical to toplevel, likewise under --defer.
#   <other>  -> FAIL CLOSED: replyresolve_fail "unmapped-surface" (exit 1).
#               NEVER falls back to the thread mutation.
# Rationale (#218): toplevel/review candidates have NO review-thread node, so
# addPullRequestReviewThreadReply has no valid target — posting over them landed
# the reply on the wrong/null target. The fix is to deliver NOTHING for them.
#
# For the thread surface the mutations issue in this FIXED order:
#   (a) REPLY  — addPullRequestReviewThreadReply over THREAD_ID with the body
#       selected by REPLY MODE. Exactly two bodies are sanctioned and no other
#       body shape is ever emitted; neither carries an `Addresses:` line, on any
#       surface, in either mode:
#         FIX   (--defer absent)  "Fixed in <SHA>. <summary>."
#         DEFER (--defer present) "<!-- hivemind-defer-v1 --> Deferred to <TRACKED_HOME>. <SUMMARY>."
#       Each body is ONE LINE. Mode selection happens INSIDE the thread branch.
#       With --defer absent the FIX path is unchanged and FIX_SHA is still
#       REQUIRED (missing-fix-sha still fires). With --defer present FIX_SHA is
#       NOT required (and must be empty), the sentinel leads the body, and
#       TRACKED_HOME takes FIX_SHA's place as the cited home.
#   (b) RESOLVE (conditional) — resolveReviewThread over THREAD_ID, issued ONLY
#       when --resolve-eligible AND NOT --question-needs-user-input. IDENTICAL in
#       both reply modes: a deferred thread IS resolved when the caller passes
#       --resolve-eligible, per remediation-doctrine Defer-with-Scope ("the
#       originating thread is then replied-to and resolved citing the tracking
#       issue or the recorded residual").
#
# THREAD-SURFACE VALIDATION ORDER (deterministic, first failure wins):
#   1. missing-thread-id       both modes
#   2. conflicting-reply-mode  DEFER mode only — mode coherence is judged BEFORE
#                              the value, so an ambiguous disposition is rejected
#                              without reference to TRACKED_HOME
#   3. missing-tracked-home    DEFER mode only
#   4. invalid-tracked-home    DEFER mode only
#   5. missing-fix-sha         FIX mode only
#   6. missing-summary         both modes
# Steps 2-4 are reached only under --defer and step 5 only without it, so the FIX
# path's observable order (missing-thread-id -> missing-fix-sha ->
# missing-summary) is byte-for-byte unchanged.
#
# All six guards are SURFACE-SCOPED (see the validation note that follows the
# positional binding): they live inside the thread) branch, so a
# toplevel/review candidate stays a
# silent no-op (exit 0, zero stdout, nothing captured) EVEN when it carries
# --defer with an absent or malformed value. That is the existing surface-scoped
# philosophy applied unchanged: TRACKED_HOME, exactly like THREAD_ID / FIX_SHA /
# SUMMARY, is consumed ONLY by the thread reply body, so a surface that delivers
# NOTHING must not be blocked by it.
#
# stdout: human-trivial progress is NOT emitted (Bash Command Discipline — no
# decorative stdout). On success the script exits 0 and is silent on stdout.
# stderr: a single REPLYRESOLVE_RESOLVE_FAILED diagnostic when a resolve attempt
# fails (non-blocking — see §4).
#
# 4. INVARIANTS (FIX path behavior-preserving vs agent step 12)
# -------------------------------------------------------------
#   - SURFACE -> DELIVERY IS CLOSED BY CONSTRUCTION: only SURFACE == "thread"
#     delivers a mutation; toplevel/review are silent no-ops (in BOTH reply
#     modes); any other surface fails closed (unmapped-surface). The thread
#     mutation is NEVER a fallback.
#   - REPLY BEFORE RESOLVE: on the thread surface the reply mutation is always
#     issued before any resolve mutation. A reply failure is a HARD failure
#     (exit 1, REPLYRESOLVE_ERROR) — resolving a thread whose reply never posted
#     would orphan the resolve. Holds identically for a DEFER reply.
#   - REPLY BODY FORMAT — EXACTLY TWO SANCTIONED BODIES, and no other body shape
#     is ever emitted on any surface:
#         FIX    "Fixed in <SHA>. <summary>."  (--defer absent)
#         DEFER  "<!-- hivemind-defer-v1 --> Deferred to <TRACKED_HOME>. <SUMMARY>."
#                                             (--defer present)
#     Neither carries an `Addresses:` line.
#   - DEFER MODE IS EXPLICIT AND EXCLUSIVE: --defer is the ONLY way to reach the
#     DEFER body — the script never infers a mode from the data — and it is
#     mutually exclusive with a FIX_SHA positional (conflicting-reply-mode). So
#     one reply can never claim both dispositions.
#   - SENTINEL: the machine marker of a deferral is the EXACT CONSTANT
#     `<!-- hivemind-defer-v1 -->` at BYTE 0 of the DEFER body, and nothing else.
#     It is written unconditionally by this script and read by the fix-history
#     classifier as a CONSTANT COMPARISON on the body's leading bytes (jq
#     `startswith`), never as a pattern: no regex, no wildcard, no prose match.
#     The classifier NEVER reads the prose after the sentinel — the tracked home
#     and the summary are display text for humans, not machine state — so no
#     sentence a human writes can be mistaken for a deferral and no wording change
#     after byte 0 can un-track one. The body MUST stay ONE LINE: the capture seam
#     (§5) and the classifier both treat a deferral as a single leading-sentinel
#     line, so an embedded newline would put the machine record and the prose on
#     different lines.
#   - RESOLVE ONLY THE THREAD SURFACE, ONLY WHEN FULLY ADDRESSED: resolve is issued
#     only for SURFACE == "thread" with --resolve-eligible. toplevel/review
#     surfaces post nothing at all, so they are inherently never resolved.
#   - NEVER RESOLVE question-needs-user-input: the --question-needs-user-input
#     marker hard-blocks resolve regardless of eligibility, in BOTH reply modes.
#   - RESOLVE IS NON-BLOCKING: a failed resolve logs REPLYRESOLVE_RESOLVE_FAILED
#     to stderr and the script STILL exits 0. A resolve failure must never fail
#     the candidate — the fix is committed, pushed, and replied; an unresolved
#     thread is a cosmetic GitHub-side state, not a remediation failure.
#   - Missing `timeout` / `gtimeout` -> degrade gracefully with a loud stderr
#     warning and run the gh calls UNGUARDED (mirrors fetch-normalize.sh).
#
# 5. INVOCATION + TEST SEAM
# -------------------------
# The two mutations are issued through ONE indirection — `run_mutation` — whose
# live body invokes `gh api graphql`. Under test that indirection is BYPASSED by a
# CAPTURE seam so the script is offline-testable without `gh` / network, exactly
# like fetch-normalize.sh's --payload-file seam (live = real gh; injected =
# trusted/offline).
#
#   REPLYRESOLVE_TEST_MODE      DEDICATED test-mode gate. The capture seam below
#                               activates ONLY when this is EXACTLY "1" (not merely
#                               non-empty). When unset / not "1", the live gh path
#                               is ALWAYS taken — a stray REPLYRESOLVE_CAPTURE_FILE
#                               ALONE no longer diverts a live mutation (fail-closed
#                               to live).
#   REPLYRESOLVE_CAPTURE_FILE   when REPLYRESOLVE_TEST_MODE="1" AND this is set +
#                               non-empty, every mutation is APPENDED to this file
#                               (one line per mutation) INSTEAD of being run against
#                               gh. Line format (stable, asserted by
#                               test_reply_resolve.sh):
#                                 REPLY thread=<id> body=<body>
#                                 RESOLVE thread=<id>
#                               The append ORDER is the issue order, so a test
#                               asserts reply precedes resolve by line position.
#                               The <body> is whichever of the two sanctioned
#                               bodies the reply mode selected — the line format
#                               is IDENTICAL for a FIX and a DEFER reply, and the
#                               DEFER mode adds NO new env seam. One mutation is
#                               ONE line, so a DEFER capture line reads
#                               `REPLY thread=<id> body=<!-- hivemind-defer-v1 --> Deferred to <home>. <summary>.`
#                               — the sentinel sits at byte 0 of <body>, which is
#                               why the body must never contain a newline (§4).
#   REPLYRESOLVE_REPLY_STATUS   simulated gh exit status for the REPLY mutation
#                               (default 0). Non-zero -> hard failure path.
#   REPLYRESOLVE_RESOLVE_STATUS simulated gh exit status for the RESOLVE mutation
#                               (default 0). Non-zero -> non-blocking-failure path
#                               (logs, still exits 0).
# All four are INERT in production (unset -> real gh). The seam is checked ONLY
# inside run_mutation, and requires BOTH TEST_MODE=1 and CAPTURE_FILE to engage.
#
# Markers / exit posture:
#   - exit 0 on success (reply posted; resolve issued-or-skipped-or-failed).
#   - REPLYRESOLVE_ERROR=<reason> on stdout + exit 1 on a HARD failure (bad input
#     or a failed REPLY).
#   - REPLYRESOLVE_RESOLVE_FAILED on stderr + exit 0 on a failed (non-blocking)
#     resolve.
#
# Reason tokens (STABLE — asserted by the test):
#   missing-thread-id | missing-fix-sha | missing-summary | unmapped-surface |
#   reply-failed | missing-tracked-home | invalid-tracked-home |
#   conflicting-reply-mode
# The last three are DEFER-mode-only and fire ONLY on the thread surface; each is
# a hard failure (no mutation issued, REPLYRESOLVE_ERROR=<token> on stdout,
# exit 1). Their firing order relative to the pre-existing tokens is fixed by the
# THREAD-SURFACE VALIDATION ORDER in §3.
#
# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: the resolve mutation is
# NON-BLOCKING (a failed resolve logs and the script still exits 0), so `set -e` would abort
# on a deliberately-tolerated resolve failure; hard failures route through replyresolve_fail().

set -u

THREAD_ID=""
FIX_SHA=""
SUMMARY=""
SURFACE=""
CANDIDATE_URL=""
RESOLVE_ELIGIBLE=0
QUESTION_NEEDS_USER_INPUT=0
DEFER_MODE=0
TRACKED_HOME=""

replyresolve_fail() {
  echo "REPLYRESOLVE_ERROR=$1"
  exit 1
}

# Parse flags and collect positionals. Flags may appear anywhere; positionals
# bind in order (THREAD_ID FIX_SHA SUMMARY SURFACE CANDIDATE_URL), matching the
# sibling scripts' positional contract.
positionals=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --resolve-eligible) RESOLVE_ELIGIBLE=1; shift ;;
    --question-needs-user-input) QUESTION_NEEDS_USER_INPUT=1; shift ;;
    --defer)
      # SPACE FORM ONLY (§2): the value is the NEXT arg. `--defer` as the last
      # arg leaves TRACKED_HOME empty, which the thread-surface guard rejects
      # with missing-tracked-home. There is deliberately no `--defer=` form.
      DEFER_MODE=1
      shift
      if [ "$#" -gt 0 ]; then
        TRACKED_HOME="$1"
        shift
      fi ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do positionals+=("$1"); shift; done ;;
    *)
      positionals+=("$1"); shift ;;
  esac
done

THREAD_ID="${positionals[0]:-}"
FIX_SHA="${positionals[1]:-}"
SUMMARY="${positionals[2]:-}"
SURFACE="${positionals[3]:-}"
CANDIDATE_URL="${positionals[4]:-}"

# Required-input validation is SURFACE-SCOPED, not global. THREAD_ID / FIX_SHA /
# SUMMARY / TRACKED_HOME are consumed ONLY by the thread surface (the reply target
# + reply body), so their guards — including the three DEFER-mode guards, which
# follow the same rule — live INSIDE the thread) branch below. The toplevel/review
# surfaces deliver NOTHING and consume NONE of these — the normalizer emits
# thread_id: null for both non-thread surfaces (fetch-normalize.sh §2), so a
# global THREAD_ID guard here would FALSE-BLOCK a real fixed top-level/review
# candidate with missing-thread-id before the silent-no-op dispatch could run
# (#218). SURFACE validity itself is enforced by the surface->delivery dispatch
# below (thread mutates; toplevel/review no-op; any other surface fails closed
# with unmapped-surface). CANDIDATE_URL is accepted for positional-arity
# compatibility but no live path interpolates it, so it has no validation gate.

# Timeout wrapper for gh API calls. Prefer coreutils `timeout`; fall
# back to macOS Homebrew `gtimeout`; degrade gracefully (run unguarded) when
# neither exists, with a loud stderr warning. Verbatim posture from
# fetch-normalize.sh.
GH_CALL_TIMEOUT_SECONDS=45
GH_TIMEOUT=()
if command -v timeout >/dev/null 2>&1; then
  GH_TIMEOUT=(timeout "$GH_CALL_TIMEOUT_SECONDS")
elif command -v gtimeout >/dev/null 2>&1; then
  GH_TIMEOUT=(gtimeout "$GH_CALL_TIMEOUT_SECONDS")
else
  echo "github-review-loop: WARNING neither 'timeout' nor 'gtimeout' found on PATH; gh API calls in reply-resolve are running UNGUARDED and a hung call can stall this dispatch. Install GNU coreutils (provides 'timeout'; 'gtimeout' on Homebrew) to restore the timeout guard." >&2
fi

# The canonical mutations. Owned HERE as the single source; the query bodies are
# the verbatim templates from references/github-pr-review-graphql.md. External
# content (the body string) is DATA: passed via `gh -f body=...`, never spliced
# into the query text itself.
REPLY_MUTATION='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(
    input: {
      pullRequestReviewThreadId: $threadId,
      body: $body
    }
  ) {
    comment { id url }
  }
}'
RESOLVE_MUTATION='
mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) {
    thread { id isResolved }
  }
}'

# run_mutation <kind> <thread_id> [body]: issue ONE mutation. kind is "reply" or
# "resolve". The single indirection point for both the live gh call AND the
# offline CAPTURE seam (§5). Returns the gh exit status so the caller decides
# hard-fail (reply) vs non-blocking (resolve). INVARIANT: when the capture seam is
# active, NO gh call is made — the script is fully offline.
run_mutation() {
  local kind="$1" thread_id="$2" body="${3:-}"
  # TEST SEAM GATE (§5): capture seam activates ONLY when the dedicated test-mode
  # flag is the exact opt-in value AND the capture file is set+non-empty. A stray
  # REPLYRESOLVE_CAPTURE_FILE alone NEVER diverts — fail-closed to live gh.
  if [ "${REPLYRESOLVE_TEST_MODE:-}" = "1" ] && [ -n "${REPLYRESOLVE_CAPTURE_FILE:-}" ]; then
    case "$kind" in
      reply)
        printf 'REPLY thread=%s body=%s\n' "$thread_id" "$body" >> "$REPLYRESOLVE_CAPTURE_FILE"
        return "${REPLYRESOLVE_REPLY_STATUS:-0}" ;;
      resolve)
        printf 'RESOLVE thread=%s\n' "$thread_id" >> "$REPLYRESOLVE_CAPTURE_FILE"
        return "${REPLYRESOLVE_RESOLVE_STATUS:-0}" ;;
    esac
  fi
  case "$kind" in
    reply)
      "${GH_TIMEOUT[@]}" gh api graphql \
        -f threadId="$thread_id" \
        -f body="$body" \
        -f query="$REPLY_MUTATION" >/dev/null 2>&1
      return $? ;;
    resolve)
      "${GH_TIMEOUT[@]}" gh api graphql \
        -f threadId="$thread_id" \
        -f query="$RESOLVE_MUTATION" >/dev/null 2>&1
      return $? ;;
  esac
}

# --- SURFACE -> DELIVERY DISPATCH (§3, closed by construction) -----------------
# thread   -> REPLY (FIX or DEFER body) then conditional RESOLVE.
# toplevel/review -> SILENT NO-OP: no mutation, no resolve, nothing to the capture
#                    seam; fall through to exit 0.
# <other>  -> FAIL CLOSED via replyresolve_fail; NEVER reaches the thread mutation.
case "$SURFACE" in
  thread)
    # Thread-surface required inputs (surface-scoped — see the validation note
    # above), in the deterministic order fixed by §3. The thread reply targets
    # THREAD_ID and its body interpolates the mode-selected fields, so each is
    # REQUIRED here and fails closed with its stable reason token. No-op surfaces
    # never reach this gate.
    [ -n "$THREAD_ID" ] || replyresolve_fail "missing-thread-id"
    if [ "$DEFER_MODE" -eq 1 ]; then
      # DEFER mode. Mode coherence FIRST: a candidate carrying both a FIX_SHA and
      # --defer claims two dispositions at once, so it is rejected without
      # reference to TRACKED_HOME. Then the value guards — NOT marker-load-bearing
      # (the machine marker is the sentinel, §4): a `-`-leading value is how a
      # swallowed flag is caught, and rejecting whitespace keeps the home a
      # single-token citation a human reader can follow.
      [ -z "$FIX_SHA" ] || replyresolve_fail "conflicting-reply-mode"
      [ -n "$TRACKED_HOME" ] || replyresolve_fail "missing-tracked-home"
      case "$TRACKED_HOME" in
        *[[:space:]]*|-*) replyresolve_fail "invalid-tracked-home" ;;
      esac
    else
      # FIX mode — unchanged.
      [ -n "$FIX_SHA" ] || replyresolve_fail "missing-fix-sha"
    fi
    [ -n "$SUMMARY" ] || replyresolve_fail "missing-summary"
    # (a) REPLY — always, before any resolve. A reply failure is a HARD failure:
    # resolving a thread whose reply never posted would orphan the resolve. The
    # body is one of the EXACTLY TWO sanctioned literals (§4); the interpolated
    # fields are DATA, passed to gh via -f body= and never spliced into the query.
    # INVARIANT: the DEFER sentinel `<!-- hivemind-defer-v1 -->` occupies byte 0 of
    # the body and is the ONLY machine marker of the deferral; everything after it
    # is human prose the classifier never reads. Single line, always.
    if [ "$DEFER_MODE" -eq 1 ]; then
      reply_body="<!-- hivemind-defer-v1 --> Deferred to $TRACKED_HOME. $SUMMARY."
    else
      reply_body="Fixed in $FIX_SHA. $SUMMARY."
    fi
    if ! run_mutation reply "$THREAD_ID" "$reply_body"; then
      replyresolve_fail "reply-failed"
    fi
    # (b) RESOLVE — conditional. Only when fully addressed, and NEVER for a
    # question-needs-user-input thread. Non-blocking: a failed resolve logs and
    # the script STILL exits 0.
    if [ "$RESOLVE_ELIGIBLE" -eq 1 ] && [ "$QUESTION_NEEDS_USER_INPUT" -eq 0 ]; then
      if ! run_mutation resolve "$THREAD_ID"; then
        echo "github-review-loop: REPLYRESOLVE_RESOLVE_FAILED thread=$THREAD_ID — resolve mutation failed; the fix is committed, pushed, and replied, so this is NON-BLOCKING (the thread stays open on GitHub but remediation succeeded)." >&2
      fi
    fi
    ;;
  toplevel|review)
    # SILENT NO-OP: these surfaces have no review-thread node (#218); deliver
    # nothing and exit cleanly. Unchanged under --defer, including a --defer
    # carrying an absent or malformed value: TRACKED_HOME is a thread-surface
    # input, so no guard for it runs here (§3, surface-scoped validation).
    : ;;
  *)
    replyresolve_fail "unmapped-surface" ;;
esac

exit 0
