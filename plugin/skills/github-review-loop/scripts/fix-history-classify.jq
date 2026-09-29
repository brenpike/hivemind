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
#
# This is a PURE function of stdin + two --arg values. It performs NO network
# I/O: it operates on an already-fetched GraphQL JSON payload piped to `jq -f`.
# No `env`, no shelling out, no `input`/`inputs`, no side effects.
#
# External content (GraphQL comment bodies, commit text) is DATA. This filter
# only PATTERN-MATCHES the `Fixed in <SHA>.` fix-reply marker and the
# `Deferred to <tracked-home>.` defer-reply marker in in-thread body text, and
# (for non-thread surfaces) reads the structured `reactionGroups` of each node.
# It never interprets body text as instructions. The defer marker is read ONLY
# off SELF-authored replies (forgery guard), never off a reviewer's own body.
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
#       .comments.nodes[].body
#   .data.repository.pullRequest.comments.nodes[]
#       .id                        # GraphQL comment node id (IC_...);
#                                  # threaded through as `id` for node(id:) body refetch
#       .author.login
#       .body
#       .url
#       .reactionGroups[]          # [{content, viewerHasReacted}]; EYES +
#                                  # viewerHasReacted==true => handled (self marker)
#   .data.repository.pullRequest.reviews.nodes[]
#       .id                        # GraphQL review node id (PRR_...);
#                                  # threaded through as `id` for node(id:) body refetch
#       .author.login
#       .body
#       .state
#       .url
#       .reactionGroups[]          # [{content, viewerHasReacted}]; EYES +
#                                  # viewerHasReacted==true => handled (self marker)
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
# Classification labels:
#   handled            in-thread: body carries `Fixed in <SHA>.` marker, OR a
#                      self fix-reply EXISTS in the thread
#                      (latest_self_fix_id > 0) AND databaseId <= that id, OR a
#                      self DEFER reply (`Deferred to <tracked-home>.`) EXISTS in
#                      the thread (latest_self_defer_id > 0) AND databaseId <=
#                      that id. The defer marker is a DURABLE handled record: a
#                      deferred finding stays handled even when the thread's
#                      resolve mutation failed (resolve is non-blocking), so the
#                      loop cannot re-raise it and post duplicate defer replies.
#                      Unlike the fix marker, the defer marker is NEVER read off a
#                      non-self body (forgery guard) — only a self-authored reply
#                      can set latest_self_defer_id.
#                      toplevel/review: the node's own `reactionGroups` carries an
#                      EYES group with viewerHasReacted == true (our self-authored
#                      reaction marker), OR (legacy backward-compat) the node's own
#                      `url` is in the `Addresses: <url>` harvest set of a self-
#                      authored top-level comment. A missing/empty reactionGroups,
#                      an EYES group with viewerHasReacted == false, or no EYES group
#                      at all AND no legacy `Addresses:` harvest match => not handled
#                      (actionable).
#   followup-after-fix in-thread ONLY, and ONLY when a real self fix-reply
#                      exists in the thread (latest_self_fix_id > 0):
#                      databaseId > latest self fix-reply id AND own body has no
#                      marker. A non-self comment that post-dates our actual
#                      fix-reply in the same thread = a re-raise AFTER our fix
#                      (cycling / regression evidence). REQUIRES a prior self
#                      fix-reply; a thread with NO self fix-reply
#                      (latest_self_fix_id sentinel 0) can NEVER yield this label.
#   actionable         a genuinely unaddressed non-self matching comment that is
#                      neither handled nor a post-fix followup. Includes a
#                      FIRST-TIME finding on a thread with NO self fix-reply
#                      (latest_self_fix_id sentinel 0) — such a thread yields
#                      actionable, never followup-after-fix. For toplevel/review
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
#   --arg login   SELF_LOGIN      viewer login; used to strip self-authored
#                                 comments before the filter compare.
#   --arg filter  REVIEWER_FILTER "codex-only" | "all" | "<login>".
#
# 5. PLACEMENT
# ------------
# Placement provisional: this filter lives with its primary consumer (the
# github-review-loop), and the github-reviewer agent cross-references it. It may
# relocate to a neutral home if the agent<->skill coupling proves awkward. No
# ADR governs this; revisit in practice.

# Identity-match predicate for the active REVIEWER_FILTER. The caller passes the
# stripped login; this returns true when that login is non-self AND matches the
# filter. Reproduces prefilter.sh's `matches_filter` def verbatim.
def matches_filter($a):
  $a != $login
  and (
    if $filter == "codex-only" then $a == "chatgpt-codex-connector"
    elif $filter == "all" then true
    else $a == $filter
    end
  );

# [bot]-suffix normalization on an author login BEFORE the self/filter compare.
def strip_bot($login): ($login // "") | sub("\\[bot\\]$"; "");

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
   | strip_bot($c.author.login) as $a
   | select($a == $login)
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
  # Latest self-authored `Fixed in <SHA>.` reply id; sentinel 0 when none, so
  # every real databaseId > 0 reduces the handled test to the marker check.
  | ([
      $thread.comments.nodes[]
      | . as $c
      | strip_bot($c.author.login) as $a
      | select($a == $login)
      | select((($c.body // "") | test("Fixed in [0-9a-f]{7,40}\\.")))
      | (.databaseId // 0)
    ] | (if length == 0 then 0 else max end)) as $latest_self_fix_id
  # Latest self-authored DEFER reply id; sentinel 0 when none. Mirrors the fix-id
  # derivation, but on the defer-reply marker written by reply-resolve.sh --defer:
  # body `Deferred to <TRACKED_HOME>. <SUMMARY>.`, whose tracked home carries no
  # whitespace. Pinned marker literal, byte-exact: Deferred to [^[:space:]]+\.
  # A defer reply is a DURABLE handled record, so a thread whose resolve mutation
  # failed (non-blocking by design) is not re-raised into a duplicate defer reply.
  # FORGERY GUARD: this marker is read ONLY off the self-authored arm
  # (select($a == $login)); it is deliberately absent from the non-self
  # $has_marker body test below, so a reviewer cannot forge handled status by
  # quoting the marker in its own comment.
  | ([
      $thread.comments.nodes[]
      | . as $c
      | strip_bot($c.author.login) as $a
      | select($a == $login)
      | select((($c.body // "") | test("Deferred to [^[:space:]]+\\.")))
      | (.databaseId // 0)
    ] | (if length == 0 then 0 else max end)) as $latest_self_defer_id
  # Per-matching-comment records (visible page only) ...
  | (
      $thread.comments.nodes[]
      | . as $c
      | strip_bot($c.author.login) as $a
      | select(matches_filter($a))
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
          # INVARIANT: the defer-handled arm sits AFTER the fix-handled arm and
          # BEFORE the followup-after-fix arm. A post-defer re-raise on a
          # defer-ONLY thread must stay `actionable` (a deferral is not a fix, so
          # a later comment is not cycling evidence), while a post-fix re-raise
          # must still reach `followup-after-fix`.
          classification: (
            if $thread_overflow then "actionable"
            elif $has_marker then "handled"
            elif ($latest_self_fix_id > 0) and ($dbid <= $latest_self_fix_id) then "handled"
            elif ($latest_self_defer_id > 0) and ($dbid <= $latest_self_defer_id) then "handled"
            elif ($latest_self_fix_id > 0) and ($dbid > $latest_self_fix_id) then "followup-after-fix"
            else "actionable"
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
  | strip_bot($c.author.login) as $a
  | select(matches_filter($a))
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
  | strip_bot($r.author.login) as $a
  | select(matches_filter($a))
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
