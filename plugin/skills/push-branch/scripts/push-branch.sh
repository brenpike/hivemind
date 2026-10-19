#!/usr/bin/env bash
#
# push-branch: THIN executable entrypoint (ADR-0020) that places the current working branch on its
# remote in ONE process. It reads the branch, the commit, the upstream config, and the push remote
# exactly once, gates every value, then pushes and (when allowed) retries with force-with-lease
# using those same in-process values. The push writes the captured commit by object id, in peel
# form `<sha>^{commit}` (no refname can contain `^`), to the branch's own name, so the commit and
# the ref written are the values checked, and `commit:` is the object written (or, on the warning
# paths, the object that would have been written).
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
#   MODE explicit: --remote given; push to it, then record the upstream.
#        upstream: branch.<b>.remote or branch.<b>.merge non-empty. Both must then be non-empty,
#                  merge must equal refs/heads/<b>, remote is gated. Push remote is
#                  branch.<b>.pushRemote, else remote.pushDefault, else branch.<b>.remote; the
#                  chosen value is gated. No upstream is recorded (it is already the branch's own
#                  name).
#        origin:   no upstream, --no-upstream origin, remote.origin.url set; push to origin, then
#                  record the upstream.
#   The resolved push remote must not be `.` (the local repository is not a remote).
#
# PUSH: always `git push --porcelain <remote> <sha>^{commit}:refs/heads/<b>` with LC_ALL=C and
# GIT_TERMINAL_PROMPT=0, never `-u`. The source is the captured object id, so moving a ref after
# the read (the branch ref, HEAD, or a ref named after the sha) cannot change the commit written.
# The destination is the branch's own name in every mode, so neither the push nor the retry can
# target trunk. git stderr is relayed to stderr; porcelain stdout is captured and classified, never
# relayed.
# UPSTREAM RECORD: `-u` records nothing for an object-id source, so after a successful push in
# explicit or origin mode the script itself sets branch.<b>.remote to the push remote and
# branch.<b>.merge to refs/heads/<b>. A failed write blocks with `pushed, but the upstream could not
# be recorded`. Upstream mode records nothing.
#
# CLASSIFY (from the porcelain ref line whose destination is refs/heads/<b>; git prints the source
# as given, so only the part after the last `:` is compared):
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
# OUTPUT on success (exit 0), on stdout in ONE write, after any upstream record:
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
# this script writes, which is fixed by the explicit refspec above. Credentials are git's and the
# operator's concern. git still resolves these at push time, after the checks:
#   (a) the remote URL, from the remote name;
#   (b) the force-with-lease expected value, from the remote-tracking ref. Inherited, and limited
#       to refs/heads/<b>. Capturing the expected object id early was rejected: it narrows a window
#       without changing what the lease means, and `--force-if-includes` needs git 2.30 or later;
#   (c) client hooks, which are repo-owned and could push anything themselves;
#   (d) branch.autoSetupRebase, which the upstream record above does not apply.
# These decide where and whether the write lands, never which commit or which ref is written. They
# are recorded rather than defended because of the trust boundary in
# ${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md (Shell Identifier Discipline): the identifier
# rule defends against untrusted identifier text only; repo hooks, local refs, git config, and the
# operator are trusted, and their changes between a check and a write are recorded residuals.
#
# RECORDED RESIDUAL R1 (implicit head of the later PR creation): open-plan-pr step 7 runs
# `gh pr create` without `--head`, so gh resolves the PR head from the current branch in its own
# process, after this script has exited. No check made here binds that resolution.
#   Root cause:  the PR head is implicit, and gh resolves it in a different process.
#   Inherited:   on main, step 7 already relied on an earlier step's branch check. This is not a
#                new exposure introduced by routing pushes through this script.
#   Bounded impact: non-interactive gh never pushes, prompts, or forks; it aborts when the branch
#                is not on a remote at the local commit. open-plan-pr step 8 compares GitHub's
#                headRefName and headRefOid against the gated head input and this script's
#                `commit:` line, never against a re-read of local state, so a drifted head is
#                blocked, not accepted. Drift needs HEAD to change in the run owner's worktree
#                between two consecutive calls, and only repo-owned hooks or the operator act in
#                the run owner's worktree. The worst result is a visible, closable PR.
#   Rejected remediations:
#                - passing `--head <branch>`: gh then uses the base repository unless given
#                  `<owner>:<branch>`, and deriving the owner means hand-parsing a remote URL,
#                  which breaks fork and triangular remotes.
#                - folding PR creation into this script: gh still resolves its own head unless
#                  `--head` is passed, so one process binds nothing. It also couples the push
#                  kernel to PR authoring and moves the free-text title and body into script
#                  arguments.
#   Linkage:     review findings f781f8c8, 87f850de, a3c042d0, and bd3204af, with b0f99069 as
#                lineage.
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

# write_config_value <key> <value>
#   Sets <key> to <value> in the repository git config. Runs only after a successful push, so any
#   failure is the blocker `pushed, but the upstream could not be recorded`. Runs in the main shell
#   so blocker exits it.
write_config_value() {
  local config_key="$1"
  local config_new_value="$2"
  git config "$config_key" "$config_new_value" 2>/dev/null || blocker "pushed, but the upstream could not be recorded"
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
#   Sets push_class to success, non_ff, or rejected from push_rc and the porcelain ref line whose
#   destination (the part after the last `:`) is refs/heads/<b>. git prints the source as given,
#   so it is not compared. A missing or duplicated ref line is rejected.
push_class=''
classify_push_result() {
  local tab=$'\t'
  local expected_ref="refs/heads/$current_branch"
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
    [ "${line_ref##*:}" = "$expected_ref" ] || continue
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

push_refspec="${head_sha}^{commit}:refs/heads/$current_branch"
run_git_push "$push_remote" "$push_refspec"
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
if [ "$push_class" = 'success' ] && [ "$push_mode" != 'upstream' ]; then
  write_config_value "branch.$current_branch.remote" "$push_remote"
  write_config_value "branch.$current_branch.merge" "refs/heads/$current_branch"
fi

if [ -n "$warning_text" ]; then
  printf 'branch: %s\ncommit: %s\nwarning: %s\n' "$current_branch" "$head_sha" "$warning_text"
else
  printf 'branch: %s\ncommit: %s\n' "$current_branch" "$head_sha"
fi
