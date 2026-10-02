# reviewer-identity.jq
#
# 1. PURPOSE
# ----------
# Single source of truth for GitHub review IDENTITY predicates: which PR-review
# author is the authenticated viewer (`is_self`), which authors count as an
# automated reviewer, which one a REVIEWER_FILTER value selects, and which
# automated reviewer's signal counts as an approval. Every
# github-review-loop script that filters review authors or detects an automated
# approval MUST call these defs instead of inlining its own login compare, so the
# identity semantics never drift between consumers.
#
# This is a DEFINITIONS-ONLY jq module: it has NO main expression and is never
# run with `jq -f`. Every def takes its inputs as explicit parameters; none reads
# a `$login` / `$filter` --arg global, so the module binds nothing from its
# caller's argument namespace. Pure: no `env`, no `input`/`inputs`, no I/O.
#
# Decision record: docs/adr/0033-automated-reviewer-identity-registry.md.
#
# 2. REGISTRY SCHEMA (`automated_reviewers`)
# ------------------------------------------
# An array of entries, one per automated reviewer product:
#   .id        stable machine key ("codex" | "copilot" | "claude"); filter
#              modes address entries by id, never by display name.
#   .name      human display name; not used for matching.
#   .logins    every login spelling the product's bot account appears under,
#              compared AFTER `[bot]`-suffix stripping. Copilot is listed under
#              BOTH its GraphQL spelling (`copilot-pull-request-reviewer`) and
#              its REST spelling (`Copilot`) because the two APIs disagree.
#   .approval  the approval-kind this reviewer's approval signal arrives as
#              (one of `approval_kinds`), or null when the reviewer has no
#              recognised approval signal.
#
# The registry is a `def` returning an array literal, NOT a JSON data import:
# jq 1.6 binds an `import "x" as $x;` data file as an ARRAY wrapping the
# document, while jq 1.7 binds the bare document, so a data import would parse
# differently across the local (1.6) and CI (1.7.x) toolchains.
#
# 3. IDENTITY KEY: account type + login
# -------------------------------------
# A registry match requires BOTH `$type == "Bot"` AND a stripped-login hit.
# `$type` is the author's account type: GraphQL `author.__typename` or REST
# `user.type`. A login alone is NOT an identity: a human GitHub User account
# named `claude` (created 2009) exists, and its bare login collides with the
# Claude app bot's login once `[bot]` is stripped. Gating on the Bot type keeps
# that human out of every registry mode. A missing or null `$type` never matches
# a registry mode (fail closed toward "not automated").
#
# SELF identity (`is_self`) is keyed the same way, on the opposite type: the
# author is self ONLY when `$type == "User"` AND the RAW login equals `$self`
# (no `[bot]` strip). `$self` is SELF_LOGIN, read from REST `GET /user`, which
# answers only for a user credential, so the viewer is always a User account. A
# Bot whose bare login equals the operator's login (operator = the human User
# `claude`, the Claude app Bot also `claude`) is therefore NOT self: its findings
# stay visible and its fix/defer/`Addresses:` markers are never honored as the
# operator's. A missing or null `$type`, or an empty `$self`, is never self (fail
# toward "actionable": an unrecognised author is surfaced, never silenced).
#
# `github-actions[bot]` is DELIBERATELY EXCLUDED from the registry. It is the
# generic CI identity that any workflow step posts as, so admitting it would
# admit arbitrary CI noise and widen the prompt-injection surface to anything a
# workflow can write. Claude Code's GitHub Action run with the default
# `github_token` also posts as `github-actions[bot]`; operators who want those
# reviews select them with `all` or an explicit `<login>` filter.
#
# 4. APPROVAL KINDS (`approval_kinds`, closed enum)
# -------------------------------------------------
#   "pr-reaction-thumbs-up"  a +1 reaction on the PR object itself (Codex).
#   "review-approved"        an approver's latest submitted review (GitHub
#                            `latestReviews`) has state APPROVED (Copilot).
# A kind outside this enum (including null) never identifies an approver.
#
# 5. FILTER MODES (`reviewer_matches_filter` $filter values)
# ----------------------------------------------------------
#   "automated"   any registry entry (Bot type required).
#   "codex-only"  the `codex` registry entry only (Bot type required).
#   "all"         every author.
#   "<login>"     legacy: stripped login == $filter, type-agnostic (unchanged
#                 from the pre-registry behavior).
# The keywords SHADOW same-named logins: an account literally named `automated`,
# `codex-only`, or `all` cannot be selected via the `<login>` mode.
# Every mode first requires the author not be self per `is_self` (§3), so
# self-authored content never matches a filter.
#
# 6. CALLER OBLIGATION
# --------------------
# Load the module by search path and include it before use:
#   jq -L <dir containing this file> '... include "reviewer-identity"; ...'
# (`include` must precede the program's main expression.) Do not copy these defs
# inline; a copy is a second source of truth.

# Registry of automated reviewer products (schema: §2).
def automated_reviewers:
  [
    {id: "codex", name: "Codex",
     logins: ["chatgpt-codex-connector"],
     approval: "pr-reaction-thumbs-up"},
    {id: "copilot", name: "Copilot",
     logins: ["copilot-pull-request-reviewer", "Copilot"],
     approval: "review-approved"},
    {id: "claude", name: "Claude",
     logins: ["claude"],
     approval: null}
  ];

# Closed enum of approval-signal kinds (§4).
def approval_kinds: ["pr-reaction-thumbs-up", "review-approved"];

# [bot]-suffix normalization on an author login BEFORE any identity compare.
def strip_bot($login): ($login // "") | sub("\\[bot\\]$"; "");

# True when the author is the authenticated viewer: a User-typed account whose
# raw login equals the non-empty $self (§3). Positive allowlist on the type, so
# a null/missing $type is never self.
def is_self($login; $type; $self):
  $type == "User" and $self != "" and $login == $self;

# True when the author is non-self (is_self, §3) AND matches the filter mode (§5).
def reviewer_matches_filter($login; $type; $self; $filter):
  strip_bot($login) as $stripped
  | (is_self($login; $type; $self) | not)
    and (
      if $filter == "automated" then
        $type == "Bot"
        and any(automated_reviewers[]; any(.logins[]; . == $stripped))
      elif $filter == "codex-only" then
        $type == "Bot"
        and any(automated_reviewers[] | select(.id == "codex");
                any(.logins[]; . == $stripped))
      elif $filter == "all" then true
      else $stripped == $filter
      end
    );

# True when a Bot-typed author belongs to a registry entry whose approval kind
# is $kind and $kind is a member of approval_kinds (§4).
def reviewer_is_approver($login; $type; $kind):
  strip_bot($login) as $stripped
  | $type == "Bot"
    and any(approval_kinds[]; . == $kind)
    and any(automated_reviewers[] | select(.approval == $kind);
            any(.logins[]; . == $stripped));
