# reviewer-identity.jq
#
# 1. PURPOSE
# ----------
# Single source of truth for GitHub review IDENTITY predicates: which PR-review
# author is the authenticated viewer (`is_self`), which authors count as an
# Automated Reviewer, which one a REVIEWER_FILTER value selects, which review
# state counts as a Reviewer Approval, and which filter value is retired. Every
# github-review-loop script that filters review authors or detects an approval
# MUST call these defs instead of inlining its own login compare, so the
# identity semantics never drift between consumers.
#
# This is a DEFINITIONS-ONLY jq module: it has NO main expression and is never
# run with `jq -f`. Every def takes its inputs as explicit parameters; none reads
# a `$login` / `$filter` / `$reviewers` --arg global, so the module binds nothing
# from its caller's argument namespace. Pure: no `env`, no `input`/`inputs`, no
# I/O.
#
# Decision record: docs/adr/0043-tool-neutral-github-review.md (supersedes the
# reviewer registry, the retired filter value and the per-reviewer approval
# kinds of docs/adr/0033-automated-reviewer-identity-registry.md, whose account
# type rules below still stand). No reviewer product and no product login is
# named in this module: an Automated Reviewer is derived from what the PR shows.
#
# 2. IDENTITY KEY: account type + login
# -------------------------------------
# An author is a Bot account (`is_bot`) when `$type == "Bot"` OR its RAW login
# ends in the `[bot]` suffix. `$type` alone is not a reliable source: GraphQL
# `author.__typename` reports a bot as `Bot`, but the REST reactions endpoint
# reports a bot reactor's `user.type` as `User` while its login still carries
# `[bot]`. The suffix is unforgeable by a human: a GitHub login is alphanumerics
# and hyphens only, so `[bot]` is reserved for app bot accounts. A login alone
# (without the suffix) is NOT an identity: a human User account can hold the
# same bare login as an app bot once `[bot]` is stripped. Requiring a Bot
# account keeps that human out of the `automated` mode. A non-suffixed login
# with a missing or null `$type` is never a Bot (fail closed toward "not
# automated").
#
# SELF identity (`is_self`) is keyed the same way, on the opposite type: the
# author is self ONLY when `$type == "User"` AND the RAW login equals `$self`
# (no `[bot]` strip). `$self` is SELF_LOGIN, read from REST `GET /user`, which
# answers only for a user credential, so the viewer is always a User account. A
# Bot whose bare login equals the operator's login is therefore NOT self: its
# findings stay visible and its fix/defer/`Addresses:` markers are never honored
# as the operator's. A missing or null `$type`, or an empty `$self`, is never
# self (fail toward "actionable": an unrecognised author is surfaced, never
# silenced).
#
# 3. AUTOMATED REVIEWER SET (`automated_reviewer_set`)
# ----------------------------------------------------
# The set is a deduplicated array of LOWERCASED, `[bot]`-stripped logins (GitHub
# logins are case-insensitive), built from two sources:
#   - EVIDENCE: an array of `{login, type}` rows the caller reads off the PR:
#     every review author (per-author latest reviews, the reviews history,
#     review-thread comment authors) and every reactor of the THUMBS_UP group on
#     the pull request object. Only rows that pass `is_bot` and carry a string
#     login are kept. A Bot that only posts plain comments (coverage, deploy
#     previews, dependency bots) never submits a review or a THUMBS_UP, so it
#     stays out with no list to maintain.
#   - CONFIGURED: `configured_reviewers($raw)` over the raw
#     HIVEMIND_PR_REVIEWERS value (comma- or whitespace-separated, `[bot]`
#     optional). It only ADDS to the evidence set, never narrows it.
# `github-actions` (the generic CI identity any workflow step posts as) is
# dropped from the evidence and counts only when configured: admitting it by
# default would admit arbitrary CI noise and widen the prompt-injection surface
# to anything a workflow can write.
# Membership alone never makes an author a reviewer: `is_automated_reviewer`
# still requires a Bot account, so a configured login held by a human User
# never matches.
#
# EVIDENCE CONTRACT RESIDUALS:
#   - The evidence pages are bounded: at most 100 reviewing authors per review
#     connection and 100 reactors per reaction group are read. A Bot whose only
#     evidence lies past those pages is out of the set (fail toward "not
#     automated").
#   - The payload shape check does not cover the evidence fields; an absent or
#     null evidence field reads as no evidence, never as an error.
#   - Inherited from ADR-0033: an unsuffixed bot reactor that a REST read types
#     `User` fails `is_bot` and is rejected.
#
# 4. REVIEWER APPROVAL (`is_review_approval`, `is_settled_thread`)
# ----------------------------------------------------------------
# A review state is an approval when it is `APPROVED`, or `COMMENTED` with zero
# inline review comments. A THUMBS_UP reaction on the PR object is the third
# approval form; the caller reads it off the reaction rows. Review text is never
# read. Approval is counted only from an in-scope Automated Reviewer, and only
# the caller decides whether it is terminal.
#
# SETTLED APPROVAL: after the watch's quiet period, an in-scope Automated
# Reviewer has reviewed or left a THUMBS_UP, and every review thread is settled.
# A thread is settled (`is_settled_thread`) when its `isResolved` is exactly
# true, or when its last comment's author is self per `is_self` (§2). A null or
# missing `isResolved` is never resolved, and a null or missing last author is
# never self, so an unreadable thread is never settled. The settled approval
# reads no review text either; the quiet period is the caller's clock.
#
# 5. FILTER MODES (`reviewer_matches_filter` $filter values)
# ----------------------------------------------------------
#   "automated"   an Automated Reviewer per `is_automated_reviewer` over $set.
#   "all"         every author.
#   "<login>"     stripped login == $filter exactly (case-sensitive),
#                 type-agnostic.
# The keywords SHADOW same-named logins: an account literally named `automated`
# or `all` cannot be selected via the `<login>` mode. Every mode first requires
# the author not be self per `is_self` (§2), so self-authored content never
# matches a filter. One former filter value is retired (`is_retired_filter`):
# input gates reject it and point to `<login>` mode; this module holds its only
# literal in code.
#
# 6. CALLER OBLIGATION
# --------------------
# Load the module by search path and include it before use:
#   jq -L <dir containing this file> '... include "reviewer-identity"; ...'
# (`include` must precede the program's main expression.) Do not copy these defs
# inline; a copy is a second source of truth.

# [bot]-suffix normalization on an author login BEFORE any identity compare.
def strip_bot($login): ($login // "") | sub("\\[bot\\]$"; "");

# True when the author is a Bot account (§2): typed Bot, OR its raw login ends in
# the reserved `[bot]` suffix, because REST mis-types a bot reactor as User and a
# GitHub login (alphanumerics + hyphens) can never carry the suffix itself.
def is_bot($login; $type): $type == "Bot" or (($login // "") | endswith("[bot]"));

# True when the author is the authenticated viewer: a User-typed account whose
# raw login equals the non-empty $self (§2). Positive allowlist on the type, so
# a null/missing $type is never self.
def is_self($login; $type; $self):
  $type == "User" and $self != "" and $login == $self;

# Logins named in the raw HIVEMIND_PR_REVIEWERS value (§3): split on commas and
# whitespace, `[bot]` stripped once, lowercased, empties dropped.
def configured_reviewers($raw):
  [ ($raw // "") | splits("[,\\s]+")
    | select(. != "")
    | strip_bot(.)
    | ascii_downcase
    | select(. != "") ];

# The Automated Reviewer set (§3): Bot evidence rows plus the configured logins,
# `github-actions` kept only when configured.
def automated_reviewer_set($evidence; $raw):
  configured_reviewers($raw) as $configured
  | [ ($evidence // [])[]?
      | objects
      | select((.login | type) == "string")
      | select(is_bot(.login; .type))
      | strip_bot(.login)
      | ascii_downcase
      | select(. != "" and . != "github-actions") ]
    + $configured
  | unique;

# True when a Bot account (§2) holds a login in the Automated Reviewer $set (§3).
def is_automated_reviewer($login; $type; $set):
  is_bot($login; $type)
  and ((strip_bot($login) | ascii_downcase) as $key
       | any(($set // [])[]; . == $key));

# True when the author is non-self (is_self, §2) AND matches the filter mode (§5).
def reviewer_matches_filter($login; $type; $self; $filter; $set):
  (is_self($login; $type; $self) | not)
  and (
    if $filter == "automated" then is_automated_reviewer($login; $type; $set)
    elif $filter == "all" then true
    else strip_bot($login) == $filter
    end
  );

# True when a review state is a Reviewer Approval (§4); null or missing is not.
def is_review_approval($state; $inline):
  $state == "APPROVED" or ($state == "COMMENTED" and $inline == 0);

# True when a review thread is settled (§4): $resolved is exactly true, or the
# thread's last comment author ($login, $type) is self per is_self (§2).
def is_settled_thread($resolved; $login; $type; $self):
  $resolved == true or is_self($login; $type; $self);

# True for the retired filter value (§5); its only literal in code.
def is_retired_filter($filter): $filter == "codex-only";
