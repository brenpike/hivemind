#!/usr/bin/env bash
#
# push-branch: THIN executable entrypoint (ADR-0020) that places the current working branch on its
# remote in ONE process. It reads the branch, the commit, the upstream config, and the push remote
# exactly once, gates every value, then pushes and (when allowed) retries with force-with-lease
# using those same in-process values. Nothing is re-read between the check and the push.
#
# WHY (P16, check-then-act across calls): the prior skill procedure checked the upstream in one
# Bash call and re-read remote/upstream in a fresh Bash call for the force-with-lease retry. Each
# Bash call is a fresh shell, so the retry ran on values that were never re-checked: a config
# change between the calls (or any divergence in the re-read) could aim a forced push at trunk.
# The fix is structural, not another guard: one process reads once, checks once, and acts on the
# values it checked.
#
# INPUT (`--flag value` form only; each flag at most once; unknown, duplicate, or missing flags
# and invalid enum values all give the fixed usage blocker):
#   --head <branch>              REQUIRED. Expected current branch.
#   --base <branch>              REQUIRED. Trunk; the current branch must not equal it.
#   --remote <name>              OPTIONAL. Explicit push remote (explicit mode).
#   --on-reject block|warn       OPTIONAL, default block. Upstream and origin modes only: a
#                                rejected push blocks, or with `warn` exits 0 with a warning.
#   --no-upstream block|origin   OPTIONAL, default block. With no upstream and no --remote: block,
#                                or push to `origin` when `remote.origin.url` is set (origin mode),
#                                or defer with a warning when it is not.
# head, base, and remote pass hivemind_assert_identifier (_shared/allowlist.sh: non-empty, no
# leading `-`, no `..`, charset ^[A-Za-z0-9._/-]+$) before any git command runs.
#
# READ ONCE:
#   b    `git symbolic-ref --quiet --short HEAD`, gated; must equal head and differ from base.
#   sha  `git rev-parse --verify --quiet 'HEAD^{commit}'`, must be a full hex object id.
#   MODE explicit: --remote given; push -u to it.
#        upstream: branch.<b>.remote or branch.<b>.merge non-empty. Both must then be non-empty,
#                  merge must equal refs/heads/<b>, remote is gated. Push remote is
#                  branch.<b>.pushRemote, else remote.pushDefault, else branch.<b>.remote; the
#                  chosen value is gated. No -u (the upstream is already the branch's own name).
#        origin:   no upstream, --no-upstream origin, remote.origin.url set; push -u origin.
#   The resolved push remote must not be `.` (the local repository is not a remote).
#
# PUSH: always `git push --porcelain [-u] <remote> refs/heads/<b>:refs/heads/<b>` with LC_ALL=C and
# GIT_TERMINAL_PROMPT=0. The explicit refspec means the written ref is the branch's own name in
# every mode, so neither the push nor the retry can target trunk. git stderr is relayed to stderr;
# porcelain stdout is captured and classified, never relayed.
#
# CLASSIFY (from the porcelain ref line for refs/heads/<b>:refs/heads/<b>):
#   success       git exit 0 AND exactly one ref line whose flag is ` `, `+`, `*`, or `=`.
#   non-ff        git exit non-zero AND exactly one ref line with flag `!` and summary
#                 `[rejected] (non-fast-forward)` or `[rejected] (fetch first)`.
#   rejected      everything else, including `[remote rejected]`, `[rejected] (stale info)`, auth
#                 and transport failures, and a missing or duplicated ref line.
#   upstream mode non-ff: retry once with `--force-with-lease` (no expected value: the
#   remote-tracking ref is the lease) against the SAME remote and refspec. Any retry outcome other
#   than success blocks, regardless of --on-reject.
#   explicit/origin non-ff: treated as rejected; no retry.
#   rejected: explicit mode always blocks; upstream and origin modes block, or warn with
#   --on-reject warn.
#
# OUTPUT on success (exit 0), on stdout in ONE write:
#   branch: <b>
#   commit: <sha>
#   warning: <fixed text>        only when a rejection was warned or the push was deferred
# EXIT CONTRACT:
#   0  routing lines on stdout
#   1  `blocker: <fixed reason>` on stderr (after any relayed git stderr), NOTHING on stdout.
#      Blocker text never echoes a caller- or config-supplied value.
#
# NOT CHECKED (caller preconditions): the definitions.md Unsafe Git State members (in-progress
# merge/rebase/cherry-pick, conflicts, unexpected dirty paths). None of them can redirect the ref
# this script writes, which is fixed by the explicit refspec above. Remote URL trust, hooks, and
# credentials are git's and the operator's concern.
#
# RECORDED RESIDUAL (head of the later PR creation): open-plan-pr step 7 `gh pr create` takes its
# head from the current branch, which this script verified in an earlier Bash call, so that
# step acts on a branch check made in a different call.
#   Root cause:  the PR head is implicit (current branch) and the branch check happened earlier.
#   Inherited:   on main, step 7 already relied on an earlier step's branch check. This is not a
#                new exposure introduced by routing pushes through this script.
#   Bounded impact: PR creation writes no git ref (gh's own fallback push applies only to an
#                unpushed branch and is gh-owned, not done by this script). The worst result is a
#                visible, closable PR. Drift needs HEAD to change in the run owner's checkout
#                between two consecutive calls, which single-owner run isolation rules out.
#   Rejected remediations:
#                - passing `--head`: defeats gh's push/fork fallback.
#                - folding PR creation into this script: couples the push kernel to PR authoring
#                  and moves the free-text title and body into script arguments.
#   Linkage:     review findings a3c042d0 and bd3204af, with b0f99069 as lineage.
#
# Conventions (ADR-0020 thin entrypoint): `set -euo pipefail`, an EXIT trap ending in a
# guaranteed-zero `:`, self-location via `cd && pwd -P`, NO `realpath`/`readlink`; bash 3.2
# compatible (no mapfile / associative arrays / ${var,,}).

set -euo pipefail
trap ':' EXIT

blocker() { printf 'blocker: %s\n' "$1" >&2; exit 1; }

# layout plugin/skills/push-branch/scripts/ => ../../_shared is the shared-library dir. cd && pwd -P
# is portable (no realpath/readlink). NO ${CLAUDE_PLUGIN_ROOT} inside an engine script.
# SOURCE-OR-DIE: a missing/unparseable library fails closed before any git command.
script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory; refusing to proceed"
shared_dir="$(CDPATH= cd -- "$script_dir/../../_shared" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot resolve skills/_shared from the script directory; refusing to proceed"
[ -f "$shared_dir/allowlist.sh" ] || blocker "required shared library missing: skills/_shared/allowlist.sh; refusing to proceed"
. "$shared_dir/allowlist.sh" || blocker "failed to source skills/_shared/allowlist.sh (unparseable); refusing to proceed"

export LC_ALL=C
export GIT_TERMINAL_PROMPT=0

usage_reason='invalid arguments; usage: push-branch.sh --head <branch> --base <branch> [--remote <name>] [--on-reject block|warn] [--no-upstream block|origin]'

head_name=''
head_seen=false
base_name=''
base_seen=false
remote_name=''
remote_seen=false
on_reject='block'
on_reject_seen=false
no_upstream='block'
no_upstream_seen=false
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || blocker "$usage_reason"
  case "$1" in
    --head)
      [ "$head_seen" = false ] || blocker "$usage_reason"
      head_name="$2"
      head_seen=true
      ;;
    --base)
      [ "$base_seen" = false ] || blocker "$usage_reason"
      base_name="$2"
      base_seen=true
      ;;
    --remote)
      [ "$remote_seen" = false ] || blocker "$usage_reason"
      remote_name="$2"
      remote_seen=true
      ;;
    --on-reject)
      [ "$on_reject_seen" = false ] || blocker "$usage_reason"
      on_reject="$2"
      on_reject_seen=true
      ;;
    --no-upstream)
      [ "$no_upstream_seen" = false ] || blocker "$usage_reason"
      no_upstream="$2"
      no_upstream_seen=true
      ;;
    *)
      blocker "$usage_reason"
      ;;
  esac
  shift 2
done

[ "$head_seen" = true ] && [ "$base_seen" = true ] || blocker "$usage_reason"
case "$on_reject" in
  block|warn) ;;
  *) blocker "$usage_reason" ;;
esac
case "$no_upstream" in
  block|origin) ;;
  *) blocker "$usage_reason" ;;
esac

identifier_reason='head, base, or remote contains characters outside the safe allowlist'
hivemind_assert_identifier "$head_name" || blocker "$identifier_reason"
hivemind_assert_identifier "$base_name" || blocker "$identifier_reason"
if [ "$remote_seen" = true ]; then
  hivemind_assert_identifier "$remote_name" || blocker "$identifier_reason"
fi

# read_config_value <key>
#   Sets config_value to the value of <key> (empty when the key is unset). Any git config failure
#   other than "key not found" (exit 1) is a blocker. Runs in the main shell so blocker exits it.
config_value=''
read_config_value() {
  local config_key="$1"
  local config_rc=0
  config_value="$(git config --get "$config_key" 2>/dev/null)" || config_rc=$?
  case "$config_rc" in
    0) ;;
    1) config_value='' ;;
    *) blocker "cannot read git config" ;;
  esac
}

# run_git_push <git push args...>
#   Runs `git push --porcelain <args>` with stdout captured into push_output and the exit status in
#   push_rc. git stderr passes through to this script's stderr.
push_output=''
push_rc=0
run_git_push() {
  push_rc=0
  push_output="$(git push --porcelain "$@")" || push_rc=$?
}

# classify_push_result
#   Sets push_class to success, non_ff, or rejected from push_rc and the porcelain ref line for
#   refs/heads/<b>:refs/heads/<b>. A missing or duplicated ref line is rejected.
push_class=''
classify_push_result() {
  local tab=$'\t'
  local expected_ref="refs/heads/$current_branch:refs/heads/$current_branch"
  local ref_line_count=0
  local ref_flag='' ref_summary='' porcelain_line line_flag line_rest line_ref
  while IFS= read -r porcelain_line; do
    case "$porcelain_line" in
      ?"$tab"*"$tab"*) ;;
      *) continue ;;
    esac
    line_flag="${porcelain_line%%"$tab"*}"
    line_rest="${porcelain_line#*"$tab"}"
    line_ref="${line_rest%%"$tab"*}"
    [ "$line_ref" = "$expected_ref" ] || continue
    ref_line_count=$((ref_line_count + 1))
    ref_flag="$line_flag"
    ref_summary="${line_rest#*"$tab"}"
  done <<EOF
$push_output
EOF
  push_class='rejected'
  [ "$ref_line_count" -eq 1 ] || return 0
  if [ "$push_rc" -eq 0 ]; then
    case "$ref_flag" in
      ' '|'+'|'*'|'=') push_class='success' ;;
    esac
    return 0
  fi
  if [ "$ref_flag" = '!' ]; then
    case "$ref_summary" in
      '[rejected] (non-fast-forward)'|'[rejected] (fetch first)') push_class='non_ff' ;;
    esac
  fi
  return 0
}

command -v git >/dev/null 2>&1 || blocker "git not found on PATH"
git rev-parse --git-dir >/dev/null 2>&1 || blocker "not inside a git checkout"

branch_rc=0
current_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" || branch_rc=$?
case "$branch_rc" in
  0) ;;
  1) blocker "HEAD is detached" ;;
  *) blocker "cannot read the current branch" ;;
esac
hivemind_assert_identifier "$current_branch" || blocker "current branch contains characters outside the safe allowlist"

head_sha="$(git rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null)" || blocker "HEAD does not resolve to a commit"
case "$head_sha" in
  ''|*[!0-9a-f]*) blocker "HEAD does not resolve to a commit" ;;
esac
[ "${#head_sha}" -eq 40 ] || [ "${#head_sha}" -eq 64 ] || blocker "HEAD does not resolve to a commit"

if [ "$current_branch" != "$head_name" ] || [ "$current_branch" = "$base_name" ]; then
  blocker "current branch does not match head or equals base"
fi

push_mode=''
push_remote=''
if [ "$remote_seen" = true ]; then
  push_mode='explicit'
  push_remote="$remote_name"
else
  read_config_value "branch.$current_branch.remote"
  upstream_remote="$config_value"
  read_config_value "branch.$current_branch.merge"
  upstream_merge="$config_value"
  if [ -n "$upstream_remote" ] || [ -n "$upstream_merge" ]; then
    [ -n "$upstream_remote" ] && [ -n "$upstream_merge" ] || blocker "upstream does not match the working branch"
    [ "$upstream_merge" = "refs/heads/$current_branch" ] || blocker "upstream does not match the working branch"
    hivemind_assert_identifier "$upstream_remote" || blocker "upstream does not match the working branch"
    push_mode='upstream'
    read_config_value "branch.$current_branch.pushRemote"
    push_remote="$config_value"
    if [ -z "$push_remote" ]; then
      read_config_value "remote.pushDefault"
      push_remote="$config_value"
    fi
    if [ -z "$push_remote" ]; then
      push_remote="$upstream_remote"
    fi
    hivemind_assert_identifier "$push_remote" || blocker "configured push remote contains characters outside the safe allowlist"
  elif [ "$no_upstream" = 'origin' ]; then
    read_config_value "remote.origin.url"
    if [ -z "$config_value" ]; then
      printf 'branch: %s\ncommit: %s\nwarning: %s\n' "$current_branch" "$head_sha" \
        "no upstream and no origin remote; push deferred"
      exit 0
    fi
    push_mode='origin'
    push_remote='origin'
  else
    blocker "no upstream and no remote supplied"
  fi
fi
[ "$push_remote" != '.' ] || blocker "push remote is the local repository, not a remote"

push_refspec="refs/heads/$current_branch:refs/heads/$current_branch"
if [ "$push_mode" = 'upstream' ]; then
  run_git_push "$push_remote" "$push_refspec"
else
  run_git_push -u "$push_remote" "$push_refspec"
fi
classify_push_result

warning_text=''
case "$push_class" in
  success) ;;
  non_ff)
    if [ "$push_mode" = 'upstream' ]; then
      run_git_push --force-with-lease "$push_remote" "$push_refspec"
      classify_push_result
      [ "$push_class" = 'success' ] || blocker "force-with-lease retry was rejected; the remote has commits this clone has not seen"
    else
      push_class='rejected'
    fi
    ;;
esac
if [ "$push_class" = 'rejected' ]; then
  if [ "$push_mode" = 'explicit' ] || [ "$on_reject" = 'block' ]; then
    blocker "push was rejected"
  fi
  warning_text='push was rejected; the branch is not on its remote'
fi

if [ -n "$warning_text" ]; then
  printf 'branch: %s\ncommit: %s\nwarning: %s\n' "$current_branch" "$head_sha" "$warning_text"
else
  printf 'branch: %s\ncommit: %s\n' "$current_branch" "$head_sha"
fi
