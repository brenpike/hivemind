# fix-history-classify.jq
#
# 1. PURPOSE
# ----------
# Single source of truth for the "already-handled by our own fix-reply?"
# per-comment classification predicate. Both consumers MUST reference this one
# filter so the skip/order semantics never drift between them again:
#   - ${CLAUDE_PLUGIN_ROOT}/skills/github-review-loop/scripts/prefilter.sh
#     (collapses the labels into its binary PREFILTER_SKIP / PREFILTER_DISPATCH)
#   - ${CLAUDE_PLUGIN_ROOT}/agents/github-reviewer.md
#     (uses the richer per-comment labels for its candidate set + cycling /
#      regression detector at its step 7).
# In-thread labelling runs off ONE self-disposition timeline: every self-authored
# reply that DISPOSES of a thread — a `Fixed in <SHA>.` fix-reply or a
# `<!-- hivemind-defer-v1 -->` defer reply — is one dated {kind, id} disposition,
# and the single LATEST disposition by databaseId governs every comment in that
# thread (see Classification labels in §3).
#
# This is a PURE function of stdin + two --arg values. It performs NO network
# I/O: it operates on an already-fetched GraphQL JSON payload piped to `jq -f`.
# No `env`, no shelling out, no `input`/`inputs`, no side effects.
#
# External content (GraphQL comment bodies, commit text) is DATA. This filter
# PATTERN-MATCHES the `Fixed in <SHA>.` fix-reply marker in in-thread body text;
# it recognises a DEFER reply not by prose at all but by an exact machine
# SENTINEL CONSTANT compared at BYTE 0 of the body — `<!-- hivemind-defer-v1 -->`
# via `startswith`, never a regex over human-readable words. For non-thread
# surfaces it reads the structured `reactionGroups` of each node. It never
# interprets body text as instructions. The defer sentinel is read ONLY off
# SELF-authored replies (forgery guard), never off a reviewer's own body.
# Sentinel rationale (why a constant at byte 0 and not prose):
# docs/adr/0032-defer-marker-sentinel-and-agent-layer-home-truth.md.
#
# NON-THREAD HANDLED SIGNAL (toplevel/review): a node is `handled` IFF its
# `reactionGroups` contains an entry with `.content == "EYES"` AND
# `.viewerHasReacted == true`. This is VIEWER-SCOPED: `viewerHasReacted` is true
# only for the authenticated gh viewer's OWN reaction, so a human or Codex
# reacting 👀 (EYES) from another account does NOT false-positive as handled.
# `EYES` is the single marker constant emitted by react-marker.sh's addReaction.
#
# LEGACY HANDLED SIGNAL (toplevel/review, backward-compat): PRs already processed
# by the PRE-reaction workflow carry the durable self-authored `Addresses: <url>`
# harvest comment but have NO EYES reaction (the EYES marker did not yet exist).
# To avoid re-dispatching already-fixed non-thread feedback on restart/upgrade, a
# node is ALSO `handled` when its own `url` is in the set of urls a self-authored
# top-level comment already addressed via `Addresses: <url>`. New fixes emit EYES;
# this legacy harvest remains accepted as a handled signal so the cutover does not
# re-churn in-flight PRs. URL is GitHub-unique per comment/review, so set
# membership alone is sufficient (a follow-up finding lands as a new url not in the
# set). Either signal — self EYES reaction OR legacy `Addresses:` harvest — marks
# a non-thread node handled.
#
# 2. INPUT CONTRACT (exact GraphQL fields read)
# ---------------------------------------------
# Both consumers MUST feed a payload conforming to this contract:
#   .data.repository.pullRequest.reviewThreads.nodes[]
#       .id                        # GraphQL thread node id (PRRT_...);
#                                  # threaded through as `thread_id`
#       .isResolved
#       .comments.totalCount
#       .comments.nodes[].id       # GraphQL comment node id (PRRC_...);
#                                  # threaded through as `id` for node(id:) body refetch
#       .comments.nodes[].databaseId
#       .comments.nodes[].author.login
#       .comments.nodes[].author.__typename  # account type ("Bot" | "User" |
#                                  # ...); identity key with the login
#       .comments.nodes[].body
#   .data.repository.pullRequest.comments.nodes[]
#       .id                        # GraphQL comment node id (IC_...);
#                                  # threaded through as `id` for node(id:) body refetch
#       .author.login
#       .author.__typename         # account type; identity key with the login
#       .body
#       .url
#       .reactionGroups[]          # [{content, viewerHasReacted}]; EYES +
#                                  # viewerHasReacted==true => handled (self marker)
#   .data.repository.pullRequest.reviews.nodes[]
#       .id                        # GraphQL review node id (PRR_...);
#                                  # threaded through as `id` for node(id:) body refetch
#       .author.login
#       .author.__typename         # account type; identity key with the login
#       .body
#       .state
#       .url
#       .reactionGroups[]          # [{content, viewerHasReacted}]; EYES +
#                                  # viewerHasReacted==true => handled (self marker)
#
# `author.__typename` is a CONTRACT field on every surface: the registry filter
# modes (`automated`, `codex-only`) match only a Bot-typed author, so a payload
# omitting it never matches those modes (fail closed toward "not automated").
# It is ALSO the self identity key: an author is self only when its
# `__typename` is "User" AND its raw login equals --arg login (module
# `is_self`), so a payload omitting `__typename` never reads as self — its
# comment stays a candidate and its fix/defer/`Addresses:` markers are never
# honored as a self disposition (fail toward "actionable"). A Bot sharing the
# viewer's bare login is likewise never self.
# Identity semantics (registry, type gate, self key, filter modes) are owned by
# the reviewer-identity.jq module this filter includes; see its header.
#
# Connection-level tripwires (reviewThreads/comments/reviews `.totalCount`) are
# NOT this filter's concern. They are top-level scalar fields trivially read off
# the raw payload, so each consumer reads them DIRECTLY (prefilter keeps its own
# THREADS_TOTAL / COMMENTS_TOTAL / REVIEWS_TOTAL parse). This filter does PURE
# per-comment classification plus a PER-THREAD overflow flag only.
#
# 3. OUTPUT SCHEMA
# ----------------
# One JSON object per CLASSIFIED non-self matching comment, PLUS one thread-level
# overflow sentinel per unresolved overflowed thread (see THREAD-OVERFLOW
# SENTINEL below), emitted as a stream (one object per line under `jq` default
# output). The sentinel carries databaseId:null and url:null and is emitted ONCE
# PER unresolved overflowed thread EVEN when no matching comment is visible on
# the fetched page; its classification is always "actionable":
#   {
#     "surface":        "thread" | "toplevel" | "review",
#     "thread_resolved": bool,        # false for toplevel/review (no thread)
#     "thread_overflow": bool,        # true => this thread had >page comments;
#                                     #         classification is forced
#                                     #         "actionable" filter-blind
#     "thread_id":      <string>|null,# thread surface (per-comment + sentinel):
#                                     #   the GraphQL thread node id (PRRT_...),
#                                     #   so a consumer can paginate the thread.
#                                     #   null for toplevel/review surfaces, and
#                                     #   null when a thread node lacks `.id`.
#     "id":             <string>|null,# the GraphQL node id for node(id:) body
#                                     #   refetch in step 4:
#                                     #   - thread per-comment: PRRC_... comment id
#                                     #   - toplevel: IC_... issue comment id
#                                     #   - review: PRR_... review id
#                                     #   null ONLY for the thread-level overflow
#                                     #   sentinel (databaseId:null records), which
#                                     #   have no single comment node to fetch.
#     "databaseId":     <int> | null, # null for toplevel/review surfaces
#     "url":            <string>|null,# null for thread surface
#     "classification": "handled" | "actionable" | "followup-after-fix"
#   }
#
# Classification labels. In-thread labels are decided by the SELF-DISPOSITION
# TIMELINE: every self-authored fix-reply (`Fixed in <SHA>.`) or defer reply (body
# STARTING with the sentinel constant `<!-- hivemind-defer-v1 -->`) contributes one
# {kind, id} disposition, and the single LATEST disposition by databaseId governs
# the whole thread — both WHICH comments are already covered and WHAT an
# uncovered comment means:
#   handled            in-thread: body carries `Fixed in <SHA>.` marker, OR a
#                      disposition exists in the thread AND databaseId <= that
#                      latest disposition's id — i.e. the comment PRE-DATES our
#                      most recent disposition of the thread, whatever its kind.
#                      A defer disposition is as DURABLE a handled record as a
#                      fix: a deferred finding stays handled even when the
#                      thread's resolve mutation failed (resolve is non-blocking),
#                      so the loop cannot re-raise it and post duplicate defer
#                      replies. Unlike the fix marker, the defer sentinel is NEVER
#                      read off a non-self body (forgery guard) — only a
#                      self-authored reply can become a defer disposition.
#                      toplevel/review: the node's own `reactionGroups` carries an
#                      EYES group with viewerHasReacted == true (our self-authored
#                      reaction marker), OR (legacy backward-compat) the node's own
#                      `url` is in the `Addresses: <url>` harvest set of a self-
#                      authored top-level comment. A missing/empty reactionGroups,
#                      an EYES group with viewerHasReacted == false, or no EYES group
#                      at all AND no legacy `Addresses:` harvest match => not handled
#                      (actionable).
#   followup-after-fix in-thread ONLY, and ONLY when the thread's LATEST
#                      disposition is a FIX: databaseId > that disposition's id
#                      AND own body has no marker. A non-self comment that
#                      post-dates our most recent fix-reply in the same thread =
#                      a re-raise AFTER our fix (cycling / regression evidence).
#                      A thread with NO disposition at all, or whose latest
#                      disposition is a DEFER, can NEVER yield this label.
#   actionable         a genuinely unaddressed non-self matching comment that is
#                      neither handled nor a post-fix followup: NO disposition
#                      exists on the thread (a FIRST-TIME finding — such a thread
#                      yields actionable, never followup-after-fix), OR the latest
#                      disposition is a DEFER the comment post-dates (a deferral
#                      is not a fix, so a later comment is not cycling evidence),
#                      OR the latest disposition's kind is unrecognised (the
#                      kind->label map's total default). For toplevel/review
#                      surfaces (no databaseId ordering), unaddressed ==
#                      actionable — there is no followup-after-fix distinction
#                      off-thread.
#
# Thread-overflow signal: when a thread's `comments.totalCount` exceeds the
# fetched `comments.nodes` length, EVERY non-self matching comment in that
# thread is emitted with classification="actionable" and thread_overflow=true.
# Matches prefilter's unconditional ACTIONABLE fail-open for oversized threads.
#
# THREAD-OVERFLOW SENTINEL: per-matching-comment records only fire for comments
# VISIBLE on the fetched page. An unresolved overflowed thread whose visible page
# contains ONLY self / non-matching replies would therefore emit ZERO records and
# silently lose the overflow actionable signal — the older unaddressed finding
# sits OUTSIDE the fetched page. To preserve main's unconditional-ACTIONABLE
# fail-open, every UNRESOLVED overflowed thread ALSO emits exactly ONE thread-
# level sentinel record, ONCE PER THREAD, INDEPENDENT of whether any matching
# comment is visible:
#   {"surface":"thread","thread_resolved":false,"thread_overflow":true,
#    "thread_id":"PRRT_...","databaseId":null,"url":null,
#    "classification":"actionable"}
# The sentinel's thread_id is the overflowed thread's node id (or null if the
# thread node lacks `.id`), so a consumer can paginate that exact thread.
# The sentinel's databaseId is null (it is NOT a single comment — it stands for
# the whole overflowed thread). Resolved threads NEVER emit a sentinel. A non-
# overflowed thread NEVER emits a sentinel. An overflowed thread WITH a visible
# matching comment emits BOTH the per-comment actionable record(s) AND the
# sentinel; both project to DISPATCH / candidate, so the duplication is benign.
# Consumers MUST treat a databaseId:null thread-surface record as a THREAD-level
# signal (inspect the full thread), not a single-comment record.
#
# Consumer projection (documented here; NOT implemented by this filter):
#   - prefilter.sh: {actionable, followup-after-fix} -> DISPATCH;
#                   a comment set that is {handled}-only -> SKIP.
#   - github-reviewer agent: {actionable, followup-after-fix} -> candidates,
#                   with followup-after-fix tagged as cycling/regression
#                   evidence for its step-7 detector; {handled} -> skip.
#
# 4. ARGS
# -------
#   --arg login   SELF_LOGIN      viewer login (a User account, from REST
#                                 GET /user); with author.__typename it keys
#                                 self identity (module `is_self`): self-
#                                 authored comments are excluded from every
#                                 filter mode and are the only source of fix /
#                                 defer / `Addresses:` dispositions.
#   --arg filter  REVIEWER_FILTER "automated" | "codex-only" | "all" |
#                                 "<login>"; mode semantics are owned by
#                                 reviewer-identity.jq (its §5).
#
# CALLER OBLIGATION: this filter does `include "reviewer-identity";`, so every
# caller MUST pass the module search path, i.e. the directory holding this file:
#   jq -L <scripts dir> -f fix-history-classify.jq --arg login ... --arg filter ...
# Without `-L` the include fails to resolve and jq exits non-zero.
#
# 5. PLACEMENT
# ------------
# Placement provisional: this filter lives with its primary consumer (the
# github-review-loop), and the github-reviewer agent cross-references it. It may
# relocate to a neutral home if the agent<->skill coupling proves awkward. No
# ADR governs this; revisit in practice.

include "reviewer-identity";

# Identity-match predicate for the active REVIEWER_FILTER, binding this filter's
# --arg globals ($login = self, $filter = mode) onto the module predicate. The
# caller passes the RAW author login and its account type; the module strips the
# bot suffix itself.
def matches_filter($a; $t): reviewer_matches_filter($a; $t; $login; $filter);

# Non-thread handled predicate. A toplevel/review node is handled IFF its own
# `reactionGroups` carries an EYES group whose viewerHasReacted is true — i.e. a
# self-authored EYES reaction by the authenticated gh viewer (react-marker.sh's
# marker). VIEWER-SCOPED: viewerHasReacted is true only for our viewer's own
# reaction, so an EYES from a human / Codex on another account does not register.
# Null-safe: a node lacking `reactionGroups` is treated as not handled.
def has_self_eyes_reaction:
  ((.reactionGroups // [])
   | any(.content == "EYES" and (.viewerHasReacted == true)));

.data.repository.pullRequest as $pr |
$pr.reviewThreads as $rt |

# LEGACY backward-compat harvest: the set of candidate URLs that self-authored
# top-level comments have already addressed via `Addresses: <url>`. PRs processed
# by the PRE-reaction workflow carry this durable marker but NO EYES reaction, so
# this set is OR'd into the non-thread handled test to avoid re-dispatching
# already-fixed feedback on restart/upgrade. URL is GitHub-unique per comment /
# review, so set-membership alone is sufficient — a follow-up finding lands as a
# new item with a new URL and is NOT in the set. New fixes emit EYES; this harvest
# is the legacy fallback only.
([ $pr.comments.nodes[]?
   | . as $c
   | select(is_self($c.author.login; $c.author.__typename; $login))
   | ($c.body // "")
   | scan("Addresses:[[:space:]]*([^[:space:]]+)")
   | .[0]
 ]) as $addressed_urls |

# --- Per-thread classification (surface=thread) -----------------------------
(
  $rt.nodes[]?
  | select(.isResolved == false)
  | . as $thread
  | (($thread.comments.totalCount // 0) > ($thread.comments.nodes | length)) as $thread_overflow
  # SELF-DISPOSITION TIMELINE. Every self-authored reply that DISPOSES of this
  # thread contributes one {kind, id} element: a `Fixed in <SHA>.` fix-reply
  # (kind "fix") or a defer reply carrying the machine sentinel (kind "defer").
  # The FIRST arm below extracts the fix dispositions, the second the defer ones.
  | ([
      $thread.comments.nodes[]
      | . as $c
      | select(is_self($c.author.login; $c.author.__typename; $login))
      | select((($c.body // "") | test("Fixed in [0-9a-f]{7,40}\\.")))
      | {kind: "fix", id: (.databaseId // 0)}
    ] + [
      # The defer arm mirrors the fix arm, but reads the MACHINE SENTINEL that
      # reply-resolve.sh --defer puts at byte 0 of the reply body, NOT the
      # human-readable prose that follows it:
      # `<!-- hivemind-defer-v1 --> Deferred to <home>. <summary>.`. Pinned sentinel
      # constant, byte-exact and position-exact: <!-- hivemind-defer-v1 --> compared
      # with `startswith`, so only a body whose FIRST bytes are the constant counts. A
      # prose-only body can no longer read as a marker: an HTML-comment constant does
      # not occur in human text, and a Markdown quote of a real defer reply gets "> "
      # prepended, which moves the constant off byte 0.
      # SENTINEL-ONLY read (no prose fallback) is intentional: the --defer reply mode
      # ships unreleased alongside this sentinel, so no in-flight PR carries a
      # pre-sentinel defer reply that would need recognising. Rationale:
      # docs/adr/0032-defer-marker-sentinel-and-agent-layer-home-truth.md.
      # A defer reply is a DURABLE handled record, so a thread whose resolve mutation
      # failed (non-blocking by design) is not re-raised into a duplicate defer reply.
      # FORGERY GUARD: this sentinel is read ONLY off the self-authored arm
      # (module `is_self`: User-typed author whose raw login is the viewer's);
      # it is deliberately absent from the non-self $has_marker body test below,
      # so a reviewer cannot forge handled status by quoting the sentinel in its
      # own comment, and a Bot sharing the viewer's bare login cannot mint a
      # self disposition.
      $thread.comments.nodes[]
      | . as $c
      | select(is_self($c.author.login; $c.author.__typename; $login))
      | select((($c.body // "") | startswith("<!-- hivemind-defer-v1 -->")))
      | {kind: "defer", id: (.databaseId // 0)}
    ]) as $self_dispositions
  # The single LATEST disposition by databaseId governs the whole thread. ONE
  # governing element removes the arm-order hazard of two independently-maxed
  # ids, where an earlier fix could outrank a later deferral.
  # `select(.id > 0)` preserves the old sentinel-0 guard: a reply with no
  # databaseId never becomes a disposition. `last` on an empty timeline yields
  # null, which the classification treats as "no disposition".
  # TIE (a single self body carrying BOTH markers, so the same id twice):
  # sort_by is stable and the fix arm is concatenated BEFORE the defer arm, so
  # `last` picks the DEFER element — the conservative outcome, since a later
  # re-raise then stays `actionable` instead of being labelled cycling evidence.
  | ($self_dispositions | map(select(.id > 0)) | sort_by(.id) | last) as $latest_disposition
  # Per-matching-comment records (visible page only) ...
  | (
      $thread.comments.nodes[]
      | . as $c
      | select(matches_filter($c.author.login; $c.author.__typename))
      | (.databaseId // 0) as $dbid
      | (($c.body // "") | test("Fixed in [0-9a-f]{7,40}\\.")) as $has_marker
      | {
          surface: "thread",
          thread_resolved: false,
          thread_overflow: $thread_overflow,
          thread_id: ($thread.id // null),
          id: ($c.id // null),
          databaseId: $dbid,
          url: null,
          # CLOSED BY CONSTRUCTION: the LATEST self disposition governs, so no
          # arm-order invariant is load-bearing. Coverage is decided once
          # ($dbid <= $latest_disposition.id), and only the uncovered case
          # consults the kind, through a total kind->label map. Adding a new
          # marker kind is one extraction arm plus one row in that map; no
          # existing arm has to move, and no ordering between kinds can go stale.
          # "latest disposition on the thread" and "latest disposition preceding
          # this comment, if any later disposition covers it" COINCIDE: a comment
          # is handled IFF its id <= the maximum disposition id, so a per-comment
          # lookback would select the same governing element.
          # FORGERY GUARD (unchanged): the defer sentinel is read ONLY under the
          # `is_self` arm of the timeline above (User type + viewer login); it
          # is deliberately absent from the non-self $has_marker body test, so a
          # reviewer cannot forge handled status by quoting the sentinel.
          classification: (
            if $thread_overflow then "actionable"
            elif $has_marker then "handled"
            elif $latest_disposition == null then "actionable"
            elif $dbid <= $latest_disposition.id then "handled"
            else ({"fix": "followup-after-fix", "defer": "actionable"}[$latest_disposition.kind] // "actionable")
            end
          )
        }
    ),
  # ... PLUS a single thread-level overflow sentinel, emitted ONCE PER unresolved
  # overflowed thread INDEPENDENT of any visible matching comment, so an
  # overflowed thread always yields >=1 actionable record (see THREAD-OVERFLOW
  # SENTINEL in the header). databaseId:null marks it as a thread-level signal.
  (
    if $thread_overflow then
      {
        surface: "thread",
        thread_resolved: false,
        thread_overflow: true,
        thread_id: ($thread.id // null),
        id: null,
        databaseId: null,
        url: null,
        classification: "actionable"
      }
    else empty end
  )
),

# --- Top-level PR comments (surface=toplevel) -------------------------------
(
  $pr.comments.nodes[]?
  | . as $c
  | select(matches_filter($c.author.login; $c.author.__typename))
  | select((($c.body // "") | gsub("[[:space:]]+"; "")) != "")
  | ($c.url // "") as $u
  | {
      surface: "toplevel",
      thread_resolved: false,
      thread_overflow: false,
      thread_id: null,
      id: ($c.id // null),
      databaseId: null,
      url: $u,
      classification: (
        if ($c | has_self_eyes_reaction) then "handled"
        elif ($addressed_urls | index($u)) != null then "handled"
        else "actionable"
        end
      )
    }
),

# --- Review summaries (surface=review) --------------------------------------
(
  $pr.reviews.nodes[]?
  | . as $r
  | select(matches_filter($r.author.login; $r.author.__typename))
  | select(.state == "CHANGES_REQUESTED" or .state == "COMMENTED")
  | select((($r.body // "") | gsub("[[:space:]]+"; "")) != "")
  | ($r.url // "") as $u
  | {
      surface: "review",
      thread_resolved: false,
      thread_overflow: false,
      thread_id: null,
      id: ($r.id // null),
      databaseId: null,
      url: $u,
      classification: (
        if ($r | has_self_eyes_reaction) then "handled"
        elif ($addressed_urls | index($u)) != null then "handled"
        else "actionable"
        end
      )
    }
)
