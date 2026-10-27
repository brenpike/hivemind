#!/usr/bin/env bash
#
# gather-facts: THIN executable entrypoint (ADR-0020) that reports the branch as it is, so a
# planner with no shell can plan what is left. It fetches the trunk, reads the branch state, the
# dirty paths, the branch's history against trunk, the branch's pull requests and the text of
# each named issue or pull request, and writes them as ONE complete facts file. Its contract is
# plugin/references/facts-schema.json; gather-facts.jq beside this script holds the pure assembly
# (text chunking and the delivery gate).
#
# WHY ONE COMPLETE FILE (the long-history decision): the planner has no shell and no run record,
# so the facts are all it knows about what the branch already did. A cut list could hide landed
# commits, deletions and renames, and the planner would repeat or miss work. So no list is
# capped, and one facts file per run carries every commit and every changed path. Long free text
# is split into chunks of at most 1000 characters, one chunk per JSON line, so no line is too big
# for one Read page. GitHub values that are not free text (url, base_ref, author) are kept whole,
# and a page whose such value is blank or does not fit one chunk fails its shape check. That is a
# shape check, not the rejected size bound below: GitHub keeps these values far shorter, so real
# data never fails it. A cut arises only from a failed GitHub page (complete false, total from
# totalCount) or from no merge-base (history unavailable), and both stop delivery planning.
# Rejected: a size bound that stops the run when crossed (it adds stops), and pages the planner
# would fetch one by one (the planner has no shell). Stdout carries only bounded routing lines,
# never the facts themselves.
# THE LINE BOUND: before publishing, the written facts file is checked line by line, and a line
# of more than 1100 code points blocks the run. The unit is the code point, as jq length counts
# and as a chunk's cost counts; a byte bound would block real CJK text, whose characters take 3
# bytes each. This is not the rejected size bound: that one could stop a run on real history,
# while no real git or GitHub value reaches this one. Free text is chunked to at most 1000, the
# GitHub values above fit one chunk, and every other value is a hash, a count, an enum, or a
# branch, trunk or remote name, which real repositories keep far shorter. So it fires only on a
# value no real repository holds, such as a branch name of thousands of characters, and the one
# check on the written file holds every line, whichever field the line carries.
#
# INPUT (`--flag value` form only; each flag at most once except --ref; an unknown, duplicate or
# missing flag, a missing value, or a bad --ref gives the fixed usage blocker):
#   --trunk <name>    REQUIRED. The trunk branch.
#   --remote <name>   OPTIONAL. The remote to fetch trunk from. Default: origin when
#                     remote.origin.url is set, else no remote.
#   --ref <number>    OPTIONAL, repeatable, at most 20. An issue or pull request number,
#                     ^[0-9]+$, whose text the facts carry.
# trunk and remote pass hivemind_assert_identifier (_shared/allowlist.sh) before any git command
# runs. No blocker echoes a caller-supplied value.
#
# READS AND WRITES, all with plain `git` run from the top of the work tree. HEAD is read first,
# then the steps below run in this order:
#   (1) the facts folder .hivemind/facts is checked by _shared/containment.sh, created when absent,
#       and given a .gitignore holding `*` when that file is absent. A private work folder inside
#       it holds the raw reads and is removed on exit.
#   (2) with a remote, one fetch: `+refs/heads/<trunk>:refs/remotes/<remote>/<trunk>` with
#       --no-tags --no-recurse-submodules --no-prune --no-auto-gc. It writes only that
#       remote-tracking ref and the fetched objects (and FETCH_HEAD): no branch, HEAD, index or
#       work-tree file changes. A failed fetch is reported, not a blocker.
#   (3) head_state branch|detached|unsafe_name (a branch whose name fails the identifier gate),
#       HEAD, and trunk_freshness of the local trunk against the remote-tracking trunk:
#       fresh|behind|ahead|diverged, with ahead and behind counts; no_remote (no remote, local
#       trunk present); no_trunk (no remote and no local trunk); fetch_failed; no_local_trunk.
#       Counts are 0 unless both refs were compared.
#   (4) dirty paths from `git status --porcelain=v1 -z --untracked-files=all --renames`, each
#       with its index and work-tree status, whether it is unmerged, and the old path of a
#       rename; ignored files are not listed. An in-progress merge, rebase, am, cherry-pick,
#       revert or bisect is detected from the git folder.
#   (5) history against the merge-base of HEAD and the remote-tracking trunk (the local trunk
#       when there is no remote, or when the remote-tracking ref is absent after a failed
#       fetch): every commit in merge_base..HEAD oldest first, topological order, with its sha,
#       parent count and chunked subject; every changed path between the merge-base and HEAD
#       from `git diff-tree -r -z -M --no-ext-diff --no-textconv`, with its status, the old path
#       and similarity of a rename, and its added and removed line counts or binary. No
#       merge-base, or no trunk at all, makes the history unavailable.
#   (6) on a branch other than trunk, the branch's pull requests through
#       `gh api graphql --paginate` with gh's {owner} and {repo} placeholders. Every page is
#       checked with hivemind_graphql_pages_check (_shared/graphql-response.sh), then each page
#       alone with hivemind_graphql_response_check to keep the pages before a bad one. Each pull
#       request gets a relation to the branch: in_history (its head commit is in
#       merge_base..HEAD), ahead_of_head (HEAD is an ancestor of its head commit), unrelated, or
#       unknown (the head commit is not present locally). Lookup is not_applicable on trunk, on
#       a detached HEAD and on an unsafe branch name.
#   (7) for each --ref, `gh api graphql --paginate` over issueOrPullRequest: kind, state, url,
#       title, author, chunked body, and every top-level comment with its chunked body.
#   (8) the facts file, written to a temp file in the facts folder, checked against the line
#       bound (every line at most 1100 code points), and moved to
#       .hivemind/facts/facts-<UTC>-<random>.json after a leaf containment check.
# gh missing or failing, or a first page that fails a check, makes a lookup unavailable: reported,
# never a stop. Every object from GitHub carries origin external; this script does not judge
# injection, its consumer runs the injection scan.
#
# OUTPUT on success (exit 0), on stdout in ONE write, `key: value` lines holding only enum or
# gated values (a gated value is shorter than the facts line holding it, so the line bound bounds
# every routing line but root, which the facts file does not hold), in this order:
#   facts_file       checkout-relative path of the facts file
#   facts_lines      its line count (wc -l)
#   head_state       branch|detached|unsafe_name
#   branch           only when head_state is branch
#   head             the HEAD commit
#   trunk            the trunk name
#   trunk_freshness  as in (3)
#   trunk_ahead      count
#   trunk_behind     count
#   trunk_commit     the trunk commit the history is read against, as in (5): the remote-tracking
#                    trunk (after fetch_failed, its last fetched value), else the local trunk,
#                    else none
#   cut              none, or a comma list of pull_requests,references
#   external_texts   count N of external texts in the facts file; each has a text_id, t1 to tN in
#                    file order (gather-facts.jq, TEXT IDS). 0 means nothing to scan
#   delivery         ready|stop
#   delivery_stops   none, or a comma list from dirty_paths, operation_in_progress,
#                    closed_pr_on_branch, history_unavailable, cut_fields, branch_name_unsafe
#   root             the absolute checkout root from `git rev-parse --show-toplevel`, or none
#                    when it holds a control character (0x00-0x1f, 0x7f)
# A MERGED or CLOSED pull request stops delivery when its relation is in_history or
# ahead_of_head. A detached HEAD and an unavailable lookup are reported, never a stop.
# EXIT CONTRACT:
#   0  routing lines on stdout
#   1  `blocker: <fixed reason>` on stderr, NOTHING on stdout. Blockers: a usage or gate failure,
#      a missing library or tool, not a work tree, a failed git read, facts that cannot be
#      assembled, a facts line longer than the line bound, and a failed or uncontained write.
#
# NOT CHECKED (recorded residuals):
#   (a) repo hooks, git config, local refs and the operator are trusted (security-policy.md,
#       Shell Identifier Discipline). A change they make between a containment check and the
#       write it guards, or between two reads, is not defended against.
#   (b) git and JSON carry text, not bytes: a path or subject that is not valid UTF-8 has each
#       bad byte replaced by U+FFFD in the facts.
#   (c) past git's rename limit, renames show as a delete and an add.
#   (d) in a partial clone, checking a pull request's head commit can make git fetch it.
#   (e) the fetch in (2) rewrites FETCH_HEAD, git's record of the last fetch, as the fetch in
#       ${CLAUDE_PLUGIN_ROOT}/governance/workflow.md (Trunk Freshness) does. No facts consumer
#       reads it, and any later fetch or pull rewrites it again. --no-write-fetch-head was
#       rejected: it needs git 2.29 or later, and on an older git every fetch would fail and
#       report fetch_failed.
#   (f) the work grows linearly with what the repository holds, and nothing bounds it: a commit
#       subject, path or path list of any size is read in full. Measured times from the scale
#       tests in tools/test_gather_facts.sh (jq 1.6, full engine run including git): a
#       1,000,000-character U+0001 subject 4.5 s; 40,000 untracked paths 4.3 s; 20,000 history
#       paths 2.9 s. In each case 4x the input takes well under 10x the time (3.4x, 2.4x,
#       1.6x). Per-character cost: about 1.4 s and 69 MB per 2,000,000 escape-dense characters
#       (U+0001, written as \u0001), and about 0.6 s for ASCII, on jq 1.6. Repository content
#       is trusted as in (a) (${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md), so the cost
#       is slowness only. A run that cannot finish blocks and publishes nothing. A size bound
#       was rejected above because it adds stops.
#
# Conventions (ADR-0020 thin entrypoint): `set -euo pipefail`, an EXIT trap ending in a
# guaranteed-zero `:`, self-location via `cd && pwd -P`, NO `realpath`/`readlink`; bash 3.2
# compatible (no mapfile / associative arrays / ${var,,}).

set -euo pipefail
trap ':' EXIT

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# layout plugin/skills/gather-facts/scripts/ => ../../_shared is the shared-library dir. cd && pwd -P
# is portable (no realpath/readlink). NO ${CLAUDE_PLUGIN_ROOT} inside an engine script.
# SOURCE-OR-DIE: a missing/unparseable library fails closed before any git command.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
shared_dir="$(CDPATH= cd -- "$script_dir/../../_shared" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve skills/_shared from the script directory; refusing to proceed"
[ -f "$shared_dir/allowlist.sh" ] || blocker "required shared library missing: skills/_shared/allowlist.sh; refusing to proceed"
. "$shared_dir/allowlist.sh" || blocker "failed to source skills/_shared/allowlist.sh (unparseable); refusing to proceed"
[ -f "$shared_dir/containment.sh" ] || blocker "required shared library missing: skills/_shared/containment.sh; refusing to proceed"
. "$shared_dir/containment.sh" || blocker "failed to source skills/_shared/containment.sh (unparseable); refusing to proceed"
[ -f "$shared_dir/graphql-response.sh" ] || blocker "required shared library missing: skills/_shared/graphql-response.sh; refusing to proceed"
. "$shared_dir/graphql-response.sh" || blocker "failed to source skills/_shared/graphql-response.sh (unparseable); refusing to proceed"
assembly_program="$script_dir/gather-facts.jq"
[ -f "$assembly_program" ] || blocker "required file missing: gather-facts.jq; refusing to proceed"

export LC_ALL=C
export GIT_TERMINAL_PROMPT=0
export GIT_OPTIONAL_LOCKS=0
export GH_PROMPT_DISABLED=1

usage_reason='invalid arguments; usage: gather-facts.sh --trunk <name> [--remote <name>] [--ref <number>]...'
max_refs=20

trunk_name=''
trunk_seen=false
remote_name=''
remote_seen=false
ref_numbers=''
ref_count=0
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || blocker "$usage_reason"
  case "$1" in
    --trunk)
      [ "$trunk_seen" = false ] || blocker "$usage_reason"
      trunk_name="$2"
      trunk_seen=true
      ;;
    --remote)
      [ "$remote_seen" = false ] || blocker "$usage_reason"
      remote_name="$2"
      remote_seen=true
      ;;
    --ref)
      case "$2" in
        ''|*[!0-9]*) blocker "$usage_reason" ;;
      esac
      ref_count=$((ref_count + 1))
      [ "$ref_count" -le "$max_refs" ] || blocker "$usage_reason"
      ref_numbers="$ref_numbers $2"
      ;;
    *)
      blocker "$usage_reason"
      ;;
  esac
  shift 2
done
[ "$trunk_seen" = true ] || blocker "$usage_reason"

identifier_reason='trunk or remote contains characters outside the safe allowlist'
hivemind_assert_identifier "$trunk_name" || blocker "$identifier_reason"
if [ "$remote_seen" = true ]; then
  hivemind_assert_identifier "$remote_name" || blocker "$identifier_reason"
fi

command -v jq >/dev/null 2>&1 || blocker "jq not found on PATH"
command -v git >/dev/null 2>&1 || blocker "git not found on PATH"

git_read_reason='a git read failed'
write_reason='cannot write the facts file'
contain_reason='the facts folder is not contained in the checkout'
line_bound_reason='a facts line is longer than the line bound'

# ── Helpers ─────────────────────────────────────────────────────────────────

# read_config_value <key>
#   Sets config_value to the value of <key>, empty when unset. Any other git config failure is a
#   blocker. Runs in the main shell so blocker exits it.
config_value=''
read_config_value() {
  local config_key="$1"
  local config_rc=0
  config_value="$(git config --get "$config_key" 2>/dev/null)" || config_rc=$?
  case "$config_rc" in
    0) ;;
    1) config_value='' ;;
    *) blocker "$git_read_reason" ;;
  esac
}

# resolve_commit <ref>
#   Sets resolved_sha to the commit <ref> names, empty when it names none. A value that is not a
#   full hex object id is a blocker.
resolved_sha=''
resolve_commit() {
  resolved_sha="$(git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null)" || resolved_sha=''
  if [ -n "$resolved_sha" ]; then
    assert_object_id "$resolved_sha"
  fi
}

# assert_object_id <value>
#   Blocks unless <value> is a 40 or 64 character lowercase hex object id.
assert_object_id() {
  case "$1" in
    ''|*[!0-9a-f]*) blocker "$git_read_reason" ;;
  esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ] || blocker "$git_read_reason"
}

# is_ancestor <older> <newer>
#   Returns 0 when <older> is an ancestor of <newer> (or the same commit), 1 when it is not. Any
#   other git failure is a blocker.
is_ancestor() {
  local ancestor_rc=0
  git merge-base --is-ancestor "$1" "$2" >/dev/null 2>&1 || ancestor_rc=$?
  case "$ancestor_rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) blocker "$git_read_reason" ;;
  esac
}

# git_path_exists <name>
#   Returns 0 when the git folder entry <name> (resolved for this work tree) exists.
git_path_exists() {
  local entry_path
  entry_path="$(git rev-parse --git-path "$1" 2>/dev/null)" || blocker "$git_read_reason"
  [ -e "$entry_path" ]
}

# collect_valid_pages <raw page stream file> <gh exit code> <out file>
#   Writes to <out file> each page of the stream, compact and one per line, up to the first page
#   that fails hivemind_graphql_response_check. Sets stream_complete to true only when gh exited
#   0 and hivemind_graphql_pages_check passed the whole stream. A stream jq cannot parse to its
#   end keeps the pages before the break; pages_check has then already left stream_complete
#   false, so the pages that follow are reported as a cut, never dropped silently.
stream_complete=false
collect_valid_pages() {
  local raw_file="$1" gh_rc="$2" out_file="$3"
  local lines_file="$out_file.lines" page_stream page_line
  stream_complete=false
  : >"$out_file"
  page_stream="$(cat -- "$raw_file")" || blocker "$write_reason"
  if [ "$gh_rc" -eq 0 ] && hivemind_graphql_pages_check "$page_stream" >/dev/null; then
    stream_complete=true
  fi
  jq -c . "$raw_file" >"$lines_file" 2>/dev/null || true
  while IFS= read -r page_line; do
    hivemind_graphql_response_check "$page_line" >/dev/null || break
    printf '%s\n' "$page_line" >>"$out_file"
  done <"$lines_file"
}

# run_gh_pages <out file> <gh api graphql args...>
#   Runs `gh api graphql --paginate` with stdout captured into <out file>, stdin closed and stderr
#   dropped. Sets gh_rc.
gh_rc=0
run_gh_pages() {
  local out_file="$1"
  shift
  gh_rc=0
  gh api graphql --paginate "$@" >"$out_file" 2>/dev/null </dev/null || gh_rc=$?
}

# ── Work tree ────────────────────────────────────────────────────────────────

inside_work_tree="$(git rev-parse --is-inside-work-tree 2>/dev/null)" || inside_work_tree=''
[ "$inside_work_tree" = true ] || blocker "not inside a git work tree"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || blocker "$git_read_reason"
[ -n "$repo_root" ] || blocker "$git_read_reason"
CDPATH= cd -- "$repo_root" 2>/dev/null || blocker "$git_read_reason"

# ── HEAD ─────────────────────────────────────────────────────────────────────

head_state=''
branch_name=''
symbolic_rc=0
head_ref="$(git symbolic-ref --quiet HEAD 2>/dev/null)" || symbolic_rc=$?
case "$symbolic_rc" in
  0)
    case "$head_ref" in
      refs/heads/*)
        branch_name="${head_ref#refs/heads/}"
        if hivemind_assert_identifier "$branch_name"; then
          head_state='branch'
        else
          head_state='unsafe_name'
          branch_name=''
        fi
        ;;
      *)
        head_state='unsafe_name'
        ;;
    esac
    ;;
  1) head_state='detached' ;;
  *) blocker "$git_read_reason" ;;
esac

head_sha="$(git rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null)" || blocker "HEAD does not resolve to a commit"
assert_object_id "$head_sha"

# ── (1) Facts folder, work folder ───────────────────────────────────────────

canon_root="$(hivemind_assert_contained "$repo_root" ".hivemind/facts" 2>/dev/null)" || blocker "$contain_reason"
[ -n "$canon_root" ] || blocker "$contain_reason"
CDPATH= cd -- "$canon_root" 2>/dev/null || blocker "$git_read_reason"
facts_dir="$canon_root/.hivemind/facts"
mkdir -p -- "$facts_dir" 2>/dev/null || blocker "$write_reason"
hivemind_assert_contained "$canon_root" ".hivemind/facts" >/dev/null 2>&1 || blocker "$contain_reason"

if [ ! -e "$facts_dir/.gitignore" ] && [ ! -L "$facts_dir/.gitignore" ]; then
  ignore_temp="$(mktemp "$facts_dir/.gitignore-XXXXXX" 2>/dev/null)" || blocker "$write_reason"
  printf '*\n' >"$ignore_temp" 2>/dev/null || { rm -f -- "$ignore_temp"; blocker "$write_reason"; }
  hivemind_assert_file_contained "$canon_root" ".hivemind/facts/.gitignore" >/dev/null 2>&1 || { rm -f -- "$ignore_temp"; blocker "$contain_reason"; }
  mv -f -- "$ignore_temp" "$facts_dir/.gitignore" 2>/dev/null || { rm -f -- "$ignore_temp"; blocker "$write_reason"; }
fi

work_dir="$(mktemp -d "$facts_dir/.work-XXXXXX" 2>/dev/null)" || blocker "$write_reason"
facts_temp=''
# remove_work_files
#   Removes the private work folder and an unpublished facts temp file. Runs from the EXIT trap.
remove_work_files() {
  rm -rf -- "$work_dir" 2>/dev/null
  if [ -n "$facts_temp" ]; then
    rm -f -- "$facts_temp" 2>/dev/null
  fi
  return 0
}
trap 'remove_work_files; :' EXIT

# ── (2) Remote and fetch ────────────────────────────────────────────────────

has_remote=false
if [ "$remote_seen" = true ]; then
  has_remote=true
else
  read_config_value "remote.origin.url"
  if [ -n "$config_value" ]; then
    remote_name='origin'
    has_remote=true
  fi
fi

fetch_ok=false
if [ "$has_remote" = true ]; then
  if git fetch --quiet --no-tags --no-recurse-submodules --no-prune --no-auto-gc \
      "$remote_name" "+refs/heads/$trunk_name:refs/remotes/$remote_name/$trunk_name" \
      </dev/null >/dev/null 2>&1; then
    fetch_ok=true
  fi
fi

# ── (3) Trunk freshness ─────────────────────────────────────────────────────

resolve_commit "refs/heads/$trunk_name"
local_trunk_sha="$resolved_sha"
remote_trunk_sha=''
if [ "$has_remote" = true ]; then
  resolve_commit "refs/remotes/$remote_name/$trunk_name"
  remote_trunk_sha="$resolved_sha"
fi

trunk_ahead=0
trunk_behind=0
if [ "$has_remote" = false ]; then
  if [ -n "$local_trunk_sha" ]; then
    trunk_freshness='no_remote'
  else
    trunk_freshness='no_trunk'
  fi
elif [ "$fetch_ok" = false ] || [ -z "$remote_trunk_sha" ]; then
  trunk_freshness='fetch_failed'
elif [ -z "$local_trunk_sha" ]; then
  trunk_freshness='no_local_trunk'
else
  trunk_counts="$(git rev-list --left-right --count "$local_trunk_sha...$remote_trunk_sha" 2>/dev/null)" || blocker "$git_read_reason"
  trunk_ahead="${trunk_counts%%[!0-9]*}"
  trunk_behind="${trunk_counts##*[!0-9]}"
  case "$trunk_ahead$trunk_behind" in
    ''|*[!0-9]*) blocker "$git_read_reason" ;;
  esac
  [ -n "$trunk_ahead" ] && [ -n "$trunk_behind" ] || blocker "$git_read_reason"
  if [ "$trunk_ahead" -eq 0 ] && [ "$trunk_behind" -eq 0 ]; then
    trunk_freshness='fresh'
  elif [ "$trunk_behind" -eq 0 ]; then
    trunk_freshness='ahead'
  elif [ "$trunk_ahead" -eq 0 ]; then
    trunk_freshness='behind'
  else
    trunk_freshness='diverged'
  fi
fi

# ── (4) Dirty paths, operations in progress ────────────────────────────────

status_file="$work_dir/status.z"
git status --porcelain=v1 -z --untracked-files=all --renames >"$status_file" 2>/dev/null || blocker "$git_read_reason"

operations=''
if git_path_exists MERGE_HEAD; then
  operations="$operations merge"
fi
if git_path_exists rebase-merge; then
  operations="$operations rebase"
elif git_path_exists rebase-apply; then
  if git_path_exists rebase-apply/applying; then
    operations="$operations am"
  else
    operations="$operations rebase"
  fi
fi
if git_path_exists CHERRY_PICK_HEAD; then
  operations="$operations cherry_pick"
fi
if git_path_exists REVERT_HEAD; then
  operations="$operations revert"
fi
if git_path_exists BISECT_LOG; then
  operations="$operations bisect"
fi

# ── (5) History against the merge-base ──────────────────────────────────────

commits_file="$work_dir/commits.z"
names_file="$work_dir/names.z"
numstat_file="$work_dir/numstat.z"
: >"$commits_file"
: >"$names_file"
: >"$numstat_file"

history_base='none'
base_sha=''
if [ -n "$remote_trunk_sha" ]; then
  history_base='remote_trunk'
  base_sha="$remote_trunk_sha"
elif [ -n "$local_trunk_sha" ]; then
  history_base='local_trunk'
  base_sha="$local_trunk_sha"
fi

history_status='unavailable'
merge_base_sha=''
if [ -n "$base_sha" ]; then
  merge_base_rc=0
  merge_base_sha="$(git merge-base HEAD "$base_sha" 2>/dev/null)" || merge_base_rc=$?
  case "$merge_base_rc" in
    0)
      assert_object_id "$merge_base_sha"
      history_status='available'
      ;;
    1) merge_base_sha='' ;;
    *) blocker "$git_read_reason" ;;
  esac
fi

if [ "$history_status" = 'available' ]; then
  git log -z --reverse --topo-order --no-show-signature --no-color \
    --format='%H%x00%P%x00%s' "$merge_base_sha..$head_sha" >"$commits_file" 2>/dev/null || blocker "$git_read_reason"
  git diff-tree -r -z -M --no-ext-diff --no-textconv --no-commit-id --name-status \
    "$merge_base_sha" "$head_sha" >"$names_file" 2>/dev/null || blocker "$git_read_reason"
  git diff-tree -r -z -M --no-ext-diff --no-textconv --no-commit-id --numstat \
    "$merge_base_sha" "$head_sha" >"$numstat_file" 2>/dev/null || blocker "$git_read_reason"
fi

# ── (6) Pull requests on the branch ─────────────────────────────────────────

gh_present=false
if command -v gh >/dev/null 2>&1; then
  gh_present=true
fi

pr_query='query($owner: String!, $repo: String!, $branch: String!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequests(headRefName: $branch, first: 100, after: $endCursor) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes { number state url headRefOid baseRefName isCrossRepository }
    }
  }
}'

pr_lookup='not_applicable'
pr_doc_file="$work_dir/pr.json"
relations_file="$work_dir/relations.tsv"
: >"$pr_doc_file"
: >"$relations_file"
if [ "$head_state" = 'branch' ] && [ "$branch_name" != "$trunk_name" ]; then
  pr_lookup='unavailable'
  if [ "$gh_present" = true ]; then
    run_gh_pages "$work_dir/pr.raw" -F owner='{owner}' -F repo='{repo}' -f branch="$branch_name" -f query="$pr_query"
    collect_valid_pages "$work_dir/pr.raw" "$gh_rc" "$work_dir/pr.pages"
    jq -n -f "$assembly_program" --arg entry pr_project --arg stream_complete "$stream_complete" \
      --slurpfile pages "$work_dir/pr.pages" >"$pr_doc_file" 2>/dev/null || blocker "cannot assemble the facts"
    pr_lookup='fetched'
    jq -r '.items[].head_ref_oid' "$pr_doc_file" >"$work_dir/pr.oids" 2>/dev/null || blocker "cannot assemble the facts"
    while IFS= read -r pr_head_oid; do
      assert_object_id "$pr_head_oid"
      pr_relation='unknown'
      if git cat-file -e "$pr_head_oid^{commit}" 2>/dev/null; then
        if is_ancestor "$pr_head_oid" "$head_sha" \
            && { [ -z "$merge_base_sha" ] || ! is_ancestor "$pr_head_oid" "$merge_base_sha"; }; then
          pr_relation='in_history'
        elif is_ancestor "$head_sha" "$pr_head_oid"; then
          pr_relation='ahead_of_head'
        else
          pr_relation='unrelated'
        fi
      fi
      printf '%s\t%s\n' "$pr_head_oid" "$pr_relation" >>"$relations_file"
    done <"$work_dir/pr.oids"
  fi
fi

# ── (7) Named issues and pull requests ──────────────────────────────────────

ref_query='query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    issueOrPullRequest(number: $number) {
      __typename
      ... on Issue {
        number state url title body author { login }
        comments(first: 100, after: $endCursor) {
          totalCount
          pageInfo { hasNextPage endCursor }
          nodes { url body author { login } }
        }
      }
      ... on PullRequest {
        number state url title body author { login }
        comments(first: 100, after: $endCursor) {
          totalCount
          pageInfo { hasNextPage endCursor }
          nodes { url body author { login } }
        }
      }
    }
  }
}'

refs_file="$work_dir/refs.jsonl"
: >"$refs_file"
ref_index=0
for ref_number in $ref_numbers; do
  ref_index=$((ref_index + 1))
  ref_raw="$work_dir/ref-$ref_index.raw"
  ref_pages="$work_dir/ref-$ref_index.pages"
  : >"$ref_raw"
  gh_rc=1
  if [ "$gh_present" = true ]; then
    run_gh_pages "$ref_raw" -F owner='{owner}' -F repo='{repo}' -F number="$ref_number" -f query="$ref_query"
  fi
  collect_valid_pages "$ref_raw" "$gh_rc" "$ref_pages"
  jq -c -n -f "$assembly_program" --arg entry ref_project --arg number "$ref_number" \
    --arg stream_complete "$stream_complete" --slurpfile pages "$ref_pages" >>"$refs_file" 2>/dev/null \
    || blocker "cannot assemble the facts"
done

# ── (8) Assemble, publish, report ───────────────────────────────────────────

remote_value=''
if [ "$has_remote" = true ]; then
  remote_value="$remote_name"
fi
facts_temp="$(mktemp "$facts_dir/.facts-XXXXXX" 2>/dev/null)" || blocker "$write_reason"
jq -n --indent 2 -f "$assembly_program" --arg entry build \
  --arg head_state "$head_state" --arg branch "$branch_name" --arg head "$head_sha" \
  --arg trunk "$trunk_name" --arg remote "$remote_value" \
  --arg trunk_freshness "$trunk_freshness" --arg trunk_ahead "$trunk_ahead" --arg trunk_behind "$trunk_behind" \
  --arg local_trunk "$local_trunk_sha" --arg remote_trunk "$remote_trunk_sha" \
  --arg history_status "$history_status" --arg history_base "$history_base" --arg merge_base "$merge_base_sha" \
  --arg operations "$operations" --arg pr_lookup "$pr_lookup" \
  --rawfile status_z "$status_file" --rawfile commits_z "$commits_file" \
  --rawfile names_z "$names_file" --rawfile numstat_z "$numstat_file" \
  --slurpfile pr_doc "$pr_doc_file" --rawfile relations "$relations_file" \
  --slurpfile references "$refs_file" >"$facts_temp" 2>/dev/null || blocker "cannot assemble the facts"

facts_lines="$(wc -l <"$facts_temp" 2>/dev/null)" || blocker "$write_reason"
facts_lines="${facts_lines//[!0-9]/}"
[ -n "$facts_lines" ] || blocker "$write_reason"
jq -n -f "$assembly_program" --arg entry line_check --rawfile facts_text "$facts_temp" >/dev/null 2>&1 || blocker "$line_bound_reason"
routing_text="$(jq -r -n -f "$assembly_program" --arg entry routing --slurpfile facts "$facts_temp" 2>/dev/null)" || blocker "cannot assemble the facts"

facts_stamp="$(date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null)" || blocker "$write_reason"
facts_random="$(od -An -N6 -tx1 /dev/urandom 2>/dev/null)" || blocker "$write_reason"
facts_random="${facts_random//[!0-9a-f]/}"
[ "${#facts_random}" -eq 12 ] || blocker "$write_reason"
facts_name="facts-$facts_stamp-$facts_random.json"
facts_relative=".hivemind/facts/$facts_name"
hivemind_assert_file_contained "$canon_root" "$facts_relative" >/dev/null 2>&1 || blocker "$contain_reason"
[ ! -e "$canon_root/$facts_relative" ] && [ ! -L "$canon_root/$facts_relative" ] || blocker "$write_reason"
mv -- "$facts_temp" "$canon_root/$facts_relative" 2>/dev/null || blocker "$write_reason"
facts_temp=''

root_value="$repo_root"
case "$root_value" in
  *[[:cntrl:]]*) root_value='none' ;;
esac
printf 'facts_file: %s\nfacts_lines: %s\n%s\nroot: %s\n' "$facts_relative" "$facts_lines" "$routing_text" "$root_value"
