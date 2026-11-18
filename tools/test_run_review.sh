#!/usr/bin/env bash
#
# Behavioral runner for the adaptation-cycle local review entrypoint (issue #581, ADR-0042):
#   plugin/skills/adaptation-cycle/scripts/run-review.sh
#
# OFFLINE bash TEST: needs only bash, git, jq and a sha256 tool. It never runs a real reviewer:
# no codex, no copilot, no real node. Each case runs the REAL script, unmodified, from a scratch
# git repository under a mktemp dir, with exactly four settings under test control:
#   - PATH: one fake-tool dir first (a fake `timeout`, and a fake `node` in the pass-through dir),
#     then the host PATH for git and jq. The pass-through `timeout` checks its `-k 5 <deadline>`
#     prefix (all-digit deadline), logs its argv and the epoch second of its call, and execs the
#     rest; the expiring ones exit 124 or 137 without running anything. The curated-PATH cases
#     replace the host PATH with a dir of symlinks to the host tools the script, containment.sh
#     and the fakes call, with no `timeout` or `gtimeout` among them. A slow fake `git` sleeps 3
#     seconds on the snapshot's `ls-files --others`, then runs the real git. A fake `mktemp`
#     answers the work-folder or the large-diff call with an existing decoy path (exit 1, or exit
#     0 with a non-empty decoy) and passes every other call to the real mktemp.
#   - TMPDIR: a scratch folder under the test tmpdir, where the script makes its work folder.
#   - HOME: a scratch home. Only the preset cases install a fake Codex companion under it; the
#     fake `node` runs that companion with bash.
#   - HIVEMIND_LOCAL_REVIEWER: unset, empty, `codex-plugin`, a malformed value, or a JSON argv
#     that names the fake reviewer script. The fake reviewer reads its behavior from its OWN argv
#     (capture dir, action, reply file), so no other environment setting reaches the script.
#
# Scratch repo: `main` holds README.md, src/a.txt, src/unchanged.txt and src/doomed.txt; branch
# `feature` changes line 3 of src/a.txt, adds src/new.txt and deletes src/doomed.txt. Every case
# reviews `feature` against `--base main` in its own `cp -a` copy of that repo.
#
# Covered: argv `{prompt}` and stdin prompt delivery; every skip reason, including no timeout
# tool; the `gtimeout` fallback; the deadline derived from the call budget and the
# before-snapshot reserve; bare and fenced JSON, prose, two fences and schema violations;
# out-of-diff filtering and its count; the finding_id formula against precomputed digests and
# its field framing; tracked edit, untracked file and HEAD move each blocked with the change left
# in place; the large-diff patch file; the preset argv and its `.result`; cleanup removes only
# what the run created (decoy paths from a fake mktemp survive, no work folder or patch file is
# left) and the script holds no recursive delete and names every work file it writes.
#
# Mirrors tools/test_prefilter.sh's pass/fail counter, per-case assertion and
# exit-nonzero-on-any-fail convention. The only writes are under a tmpdir removed on EXIT.
#
# Usage:
#   ./tools/test_run_review.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
RUN_REVIEW="$REPO_ROOT/plugin/skills/adaptation-cycle/scripts/run-review.sh"

[ -f "$RUN_REVIEW" ] || { echo "FAIL: script under test missing: $RUN_REVIEW" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required by the script under test" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required by the script under test" >&2; exit 2; }
if command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  SHA_CMD=(shasum -a 256)
else
  echo "FAIL: sha256sum or shasum is required" >&2
  exit 2
fi

# INVARIANT: the cleanup trap's target is set once, before the trap, and only by make_scratch_dir
# from a fresh, empty directory this run's mktemp created and resolved; a failed call exits 2
# first, so cleanup never removes an empty, fallback or working-directory path.
make_scratch_dir TMPDIR_TEST
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

unset HIVEMIND_LOCAL_REVIEWER GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
HOST_PATH="$PATH"
EMPTY_HOME="$TMPDIR_TEST/home-empty"
FAKES="$TMPDIR_TEST/fakes"
mkdir -p "$EMPTY_HOME" "$FAKES" "$TMPDIR_TEST/repos" "$TMPDIR_TEST/captures" "$TMPDIR_TEST/runs" \
  "$TMPDIR_TEST/replies" "$TMPDIR_TEST/homes"
# INVARIANT: harness git runs with the scratch HOME, so no host config (autocrlf, hooks, signing)
# shapes the scratch repositories.
export HOME="$EMPTY_HOME"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

USAGE_REASON='invalid arguments; usage: run-review.sh --base <ref> [-- <focus>]'
# The large-diff file is a fresh mktemp file: review-diff. plus a 10-character random suffix.
PATCH_DIR_REL='.hivemind/review-loop'
PATCH_GLOB='review-diff.??????????'
TIMEOUT_ARGS_LOG="$TMPDIR_TEST/timeout-args.log"
TIMEOUT_EPOCH_LOG="$TMPDIR_TEST/timeout-epoch.log"
NODE_LOG="$TMPDIR_TEST/node-companion-path.log"
REAL_GIT="$(type -P git)" || { echo "FAIL: git is not an executable on PATH" >&2; exit 2; }

# The run-review.sh deadline bounds: the 570-second call budget, the 5-second kill grace, the
# highest deadline (570 - 0 spent - 2 * 1 snapshot reserve - 5 grace) and the lowest this suite
# accepts for a fast run.
CALL_BUDGET_SECONDS=570
KILL_GRACE_SECONDS=5
DEADLINE_MAX=563
DEADLINE_FAST_MIN=500

# Precomputed SHA-256 digests of the JSON array text [file, line_start, line_end, title]
# (UTF-8), the finding_id formula of run-review.sh's header, for the two findings the base
# review keeps.
ID_A_JSON_TEXT='["src/a.txt",9,9,"Kept on an unchanged line of a changed file"]'
ID_NEW_JSON_TEXT='["src/new.txt",1,2,"Ünïcödé title on a new file"]'
ID_A_TXT='d991ff84f411d707f05711423f885fc34ce96dd3e8884fc1867f6bae66e571f5'
ID_NEW_TXT='1c5a33d8b6fd02e3358b60f53176f8387c10032705e46efcb9e171ef2772fd5e'
TITLE_A_TXT='Kept on an unchanged line of a changed file'
TITLE_NEW_TXT='Ünïcödé title on a new file'

# ── Fake tools ─────────────────────────────────────────────────────────────────

BIN_PASS="$FAKES/bin-pass"
BIN_EXPIRE_124="$FAKES/bin-expire-124"
BIN_EXPIRE_137="$FAKES/bin-expire-137"
BIN_NONE="$FAKES/bin-none"
BIN_GTIMEOUT="$FAKES/bin-gtimeout"
BIN_SLOW_GIT="$FAKES/bin-slow-git"
CURATED_BIN="$FAKES/curated-bin"
mkdir -p "$BIN_PASS" "$BIN_EXPIRE_124" "$BIN_EXPIRE_137" "$BIN_NONE" "$BIN_GTIMEOUT" "$BIN_SLOW_GIT" \
  "$CURATED_BIN"

# write_pass_timeout <path>: a pass-through timeout that logs the epoch second of its call and
# its argv, requires `-k 5 <all-digit deadline>`, then execs the rest.
write_pass_timeout() {
  cat >"$1" <<STUB || return 1
#!/usr/bin/env bash
date +%s >$(printf '%q' "$TIMEOUT_EPOCH_LOG")
printf '%s\n' "\$*" >$(printf '%q' "$TIMEOUT_ARGS_LOG")
[ "\$1" = -k ] && [ "\$2" = 5 ] || { echo "fake timeout: unexpected prefix \$*" >&2; exit 92; }
case "\$3" in
  ''|*[!0-9]*) echo "fake timeout: deadline is not all digits: \$*" >&2; exit 92 ;;
esac
shift 3
exec "\$@"
STUB
  chmod +x "$1"
}
write_pass_timeout "$BIN_PASS/timeout" || exit 2
write_pass_timeout "$BIN_GTIMEOUT/gtimeout" || exit 2
write_pass_timeout "$BIN_SLOW_GIT/timeout" || exit 2

cat >"$BIN_SLOW_GIT/git" <<STUB
#!/usr/bin/env bash
lists_files=false
lists_others=false
for arg in "\$@"; do
  case "\$arg" in
    ls-files) lists_files=true ;;
    --others) lists_others=true ;;
  esac
done
if [ "\$lists_files" = true ] && [ "\$lists_others" = true ]; then
  sleep 3
fi
exec $(printf '%q' "$REAL_GIT") "\$@"
STUB
chmod +x "$BIN_SLOW_GIT/git"

# INVARIANT: the curated bin holds every host tool the script, containment.sh and the fakes call,
# and never `timeout` or `gtimeout`, so a curated-PATH run sees no timeout tool at all.
CURATED_REQUIRED_TOOLS=(bash env date dirname basename jq git mktemp wc cat rm rmdir mkdir readlink xargs cmp grep cp)
CURATED_OPTIONAL_TOOLS=(sha256sum shasum)
for tool_name in "${CURATED_REQUIRED_TOOLS[@]}"; do
  tool_path="$(type -P "$tool_name")" || { echo "FAIL: host tool missing: $tool_name" >&2; exit 2; }
  ln -s "$tool_path" "$CURATED_BIN/$tool_name" || exit 2
done
for tool_name in "${CURATED_OPTIONAL_TOOLS[@]}"; do
  tool_path="$(type -P "$tool_name")" || continue
  ln -s "$tool_path" "$CURATED_BIN/$tool_name" || exit 2
done
[ ! -e "$CURATED_BIN/timeout" ] && [ ! -e "$CURATED_BIN/gtimeout" ] \
  || { echo "FAIL: the curated bin holds a timeout tool" >&2; exit 2; }

cat >"$BIN_PASS/node" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$1" >$(printf '%q' "$NODE_LOG")
exec bash "\$@"
STUB
printf '#!/usr/bin/env bash\nexit 124\n' >"$BIN_EXPIRE_124/timeout"
printf '#!/usr/bin/env bash\nexit 137\n' >"$BIN_EXPIRE_137/timeout"
chmod +x "$BIN_PASS/timeout" "$BIN_PASS/node" "$BIN_EXPIRE_124/timeout" "$BIN_EXPIRE_137/timeout"

# fake-reviewer.sh <capture dir> <action> <reply file> [rest...]: records the rest of its argv
# (NUL-delimited), its argc, its stdin and its cwd, acts, then prints the reply file.
FAKE_REVIEWER="$FAKES/fake-reviewer.sh"
cat >"$FAKE_REVIEWER" <<'STUB'
#!/usr/bin/env bash
set -u
capture_dir="$1"
action="$2"
reply_file="$3"
shift 3
: >"$capture_dir/argv.nul"
for arg in "$@"; do
  printf '%s\0' "$arg" >>"$capture_dir/argv.nul"
done
printf '%s\n' "$#" >"$capture_dir/argc"
cat >"$capture_dir/stdin.txt"
pwd -P >"$capture_dir/cwd"
case "$action" in
  reply) ;;
  fail) printf 'boom: reviewer crashed\n' >&2; exit 3 ;;
  fail-stdout-only) cat "$reply_file"; exit 2 ;;
  fail-long-stderr) cat "$reply_file" >&2; exit 1 ;;
  edit-tracked) printf 'reviewer edit\n' >>src/a.txt ;;
  edit-and-fail) printf 'reviewer edit\n' >>src/a.txt; exit 3 ;;
  add-untracked) printf 'reviewer note\n' >reviewer-note.txt ;;
  move-head) git commit -q --allow-empty -m 'reviewer commit' || exit 90 ;;
  read-patch)
    for patch_file in .hivemind/review-loop/review-diff.??????????; do
      [ -f "$patch_file" ] || continue
      printf '%s\n' "$patch_file" >>"$capture_dir/patch-names"
      cp "$patch_file" "$capture_dir/patch-seen" 2>/dev/null || :
    done
    ;;
  *) printf 'fake-reviewer: unknown action %s\n' "$action" >&2; exit 91 ;;
esac
cat "$reply_file"
STUB
chmod +x "$FAKE_REVIEWER"

NOT_EXECUTABLE="$FAKES/not-executable.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$NOT_EXECUTABLE"
chmod -x "$NOT_EXECUTABLE"

# ── Scratch repositories ───────────────────────────────────────────────────────

# init_scratch_repo <dir>: a git repo on `main` with local identity and no line-ending filters.
init_scratch_repo() {
  git init -q "$1" || return 1
  git -C "$1" symbolic-ref HEAD refs/heads/main || return 1
  git -C "$1" config core.autocrlf false || return 1
  git -C "$1" config user.name 'Run Review Test' || return 1
  git -C "$1" config user.email 'run-review-test@example.invalid' || return 1
  git -C "$1" config commit.gpgsign false || return 1
}

TEMPLATE_REPO="$TMPDIR_TEST/template"
LARGE_TEMPLATE_REPO="$TMPDIR_TEST/template-large"
LARGE_MARKER='LARGE_DIFF_MARKER_LINE'

# build_template_repo: main with four files, then `feature` with one changed, one added and one
# deleted file.
build_template_repo() {
  local repo="$TEMPLATE_REPO" line_number
  init_scratch_repo "$repo" || return 1
  mkdir -p "$repo/src"
  printf '# scratch\n' >"$repo/README.md"
  for line_number in 1 2 3 4 5 6 7 8 9 10; do
    printf 'line %s\n' "$line_number"
  done >"$repo/src/a.txt"
  printf 'stays the same\nacross the branch\n' >"$repo/src/unchanged.txt"
  printf 'deleted on the branch\n' >"$repo/src/doomed.txt"
  git -C "$repo" add -A && git -C "$repo" commit -q -m 'base' || return 1
  git -C "$repo" checkout -q -b feature || return 1
  sed 's/^line 3$/line 3 MARKER_CHANGED_LINE/' "$repo/src/a.txt" >"$repo/src/a.txt.next" \
    && mv "$repo/src/a.txt.next" "$repo/src/a.txt" || return 1
  printf 'brand new file\nsecond line\n' >"$repo/src/new.txt"
  git -C "$repo" rm -q src/doomed.txt || return 1
  git -C "$repo" add -A && git -C "$repo" commit -q -m 'feature change' || return 1
}

# build_large_template_repo: the template plus one commit adding a file over the 65536-byte
# inline limit.
build_large_template_repo() {
  local repo="$LARGE_TEMPLATE_REPO" line_number
  cp -a "$TEMPLATE_REPO" "$repo" || return 1
  {
    printf '%s\n' "$LARGE_MARKER"
    for line_number in $(seq 1 2000); do
      printf 'filler line %05d of the large review input file\n' "$line_number"
    done
  } >"$repo/src/big.txt"
  git -C "$repo" add -A && git -C "$repo" commit -q -m 'large change' || return 1
}

build_template_repo || { echo "FAIL: cannot build the scratch template repo" >&2; exit 2; }
build_large_template_repo || { echo "FAIL: cannot build the large scratch template repo" >&2; exit 2; }

# new_repo <name> [template]: a fresh copy of the template; prints its path.
new_repo() {
  local repo="$TMPDIR_TEST/repos/$1"
  cp -a "${2:-$TEMPLATE_REPO}" "$repo" || return 1
  printf '%s\n' "$repo"
}

# new_capture <name>: an empty capture dir for one fake reviewer run; prints its path.
new_capture() {
  local capture="$TMPDIR_TEST/captures/$1"
  mkdir -p "$capture" || return 1
  printf '%s\n' "$capture"
}

# ── Reviews and replies ────────────────────────────────────────────────────────

# BASE_REVIEW keeps two findings (an unchanged line of a changed file, a new file) and drops
# three (an unchanged file, README.md, the deleted file).
BASE_REVIEW="$(jq -nc --arg title_a "$TITLE_A_TXT" --arg title_new "$TITLE_NEW_TXT" '
  def finding($path; $first; $last; $heading):
    {severity: "high", title: $heading, body: "Body text.", file: $path, line_start: $first,
     line_end: $last, confidence: 0.8, recommendation: "Fix it."};
  {
    verdict: "needs-attention",
    summary: "Two findings in the diff.",
    findings: [
      finding("src/a.txt"; 9; 9; $title_a),
      finding("src/new.txt"; 1; 2; $title_new),
      finding("src/unchanged.txt"; 1; 2; "Dropped: unchanged file"),
      finding("README.md"; 1; 1; "Dropped: README is not in the diff"),
      finding("src/doomed.txt"; 1; 1; "Dropped: deleted file")
    ],
    next_steps: ["Address the findings."]
  }')" || { echo "FAIL: cannot build the base review" >&2; exit 2; }

# write_reply <name> <bytes>: write <bytes> verbatim to a reply file; prints its path.
write_reply() {
  local reply="$TMPDIR_TEST/replies/$1"
  printf '%s' "$2" >"$reply" || return 1
  printf '%s\n' "$reply"
}

# derive_review <jq program>: BASE_REVIEW transformed by <program>, compact.
derive_review() {
  printf '%s' "$BASE_REVIEW" | jq -c "$1"
}

BARE_REPLY="$(write_reply bare "$BASE_REVIEW")" || exit 2

# reviewer_setting <capture> <action> <reply> <prompt-slot yes|no>: the JSON argv setting for the
# fake reviewer.
reviewer_setting() {
  if [ "$4" = yes ]; then
    jq -nc '$ARGS.positional' --args "$FAKE_REVIEWER" "$1" "$2" "$3" '{prompt}'
  else
    jq -nc '$ARGS.positional' --args "$FAKE_REVIEWER" "$1" "$2" "$3"
  fi
}

# ── Runner and assertions ──────────────────────────────────────────────────────

RUN_SEQ=0
# RR_PATH_TAIL: the PATH after the fake-tool dir; the host PATH except in run_review_curated.
RR_PATH_TAIL="$HOST_PATH"
# RR_TMPDIR: the TMPDIR every run gets; the shared run folder except in the cleanup cases.
RUN_TMPDIR="$TMPDIR_TEST/run-tmp"
mkdir -p "$RUN_TMPDIR" || exit 2
RR_TMPDIR="$RUN_TMPDIR"

# run_review <cwd> <home> <bin dir> <unset|set> <setting> [script args...]: run the real script
# from <cwd> with PATH <bin dir>:RR_PATH_TAIL and TMPDIR RR_TMPDIR; sets RR_OUT, RR_ERR (file
# paths) and RR_RC.
run_review() {
  local run_cwd="$1" run_home="$2" bin_dir="$3" setting_mode="$4" setting="$5"
  shift 5
  RUN_SEQ=$((RUN_SEQ + 1))
  RR_OUT="$TMPDIR_TEST/runs/$RUN_SEQ.out"
  RR_ERR="$TMPDIR_TEST/runs/$RUN_SEQ.err"
  RR_RC=0
  if [ "$setting_mode" = unset ]; then
    (cd "$run_cwd" && HOME="$run_home" PATH="$bin_dir:$RR_PATH_TAIL" TMPDIR="$RR_TMPDIR" bash "$RUN_REVIEW" "$@") \
      >"$RR_OUT" 2>"$RR_ERR" || RR_RC=$?
  else
    (cd "$run_cwd" && HIVEMIND_LOCAL_REVIEWER="$setting" HOME="$run_home" PATH="$bin_dir:$RR_PATH_TAIL" \
      TMPDIR="$RR_TMPDIR" bash "$RUN_REVIEW" "$@") >"$RR_OUT" 2>"$RR_ERR" || RR_RC=$?
  fi
}

# run_review_curated <run_review args...>: run_review with the curated bin in place of the host
# PATH, so no timeout tool is reachable except one in <bin dir>.
run_review_curated() {
  RR_PATH_TAIL="$CURATED_BIN"
  run_review "$@"
  RR_PATH_TAIL="$HOST_PATH"
}

# describe_run: one-line summary of the last run.
describe_run() {
  printf 'rc=%s stdout=%q stderr=%q' "$RR_RC" "$(head -c 400 "$RR_OUT")" "$(head -c 400 "$RR_ERR")"
}

# assert_skip <name> <expected stdout>: exit 0 and stdout exactly <expected stdout> plus newline.
assert_skip() {
  if [ "$RR_RC" -eq 0 ] && printf '%s\n' "$2" | cmp -s - "$RR_OUT"; then
    pass "$1" "$(head -n 1 "$RR_OUT")"
  else
    failed "$1" "want rc=0 stdout=$(printf '%q' "$2"); got $(describe_run)"
  fi
}

# assert_blocked <name> <reason>: exit 1, empty stdout, first stderr line `blocker: <reason>`.
assert_blocked() {
  if [ "$RR_RC" -eq 1 ] && [ ! -s "$RR_OUT" ] && [ "$(head -n 1 "$RR_ERR")" = "blocker: $2" ]; then
    pass "$1" "blocker: $2"
  else
    failed "$1" "want rc=1, empty stdout, blocker: $2; got $(describe_run)"
  fi
}

# assert_success <name> <jq predicate>: exit 0, one stdout line, the predicate true on it.
assert_success() {
  local line_count
  line_count="$(wc -l <"$RR_OUT" | tr -d ' ')"
  if [ "$RR_RC" -eq 0 ] && [ "$line_count" = 1 ] && jq -e "$2" <"$RR_OUT" >/dev/null 2>&1; then
    pass "$1" "success object matches"
  else
    failed "$1" "want rc=0 and one line matching $2; got $(describe_run)"
  fi
}

# assert_stderr_line <name> <exact line>: the last run's stderr holds <exact line>.
assert_stderr_line() {
  if grep -Fxq -- "$2" "$RR_ERR"; then
    pass "$1" "stderr has $2"
  else
    failed "$1" "stderr lacks $(printf '%q' "$2"); got $(describe_run)"
  fi
}

# assert_check <name> <description> <command...>: pass when <command> succeeds.
assert_check() {
  local check_name="$1" description="$2"
  shift 2
  if "$@"; then
    pass "$check_name" "$description"
  else
    failed "$check_name" "$description"
  fi
}

# file_has_text <file> <fixed text>
file_has_text() { [ -f "$1" ] && grep -Fq -- "$2" "$1"; }

# file_lacks_text <file> <fixed text>
file_lacks_text() { [ -f "$1" ] && ! grep -Fq -- "$2" "$1"; }

# no_run_patch_files <repo>: no large-diff file made by a run is left in the review-loop folder.
no_run_patch_files() { ! compgen -G "$1/$PATCH_DIR_REL/$PATCH_GLOB" >/dev/null; }

# one_patch_named_in <capture> <prompt file>: the reviewer saw exactly one large-diff file, and
# the prompt names it.
one_patch_named_in() {
  [ -f "$1/patch-names" ] && [ "$(wc -l <"$1/patch-names")" -eq 1 ] \
    && grep -Fq -- "$(cat "$1/patch-names")" "$2"
}

# argv_equals <capture> <expected elements...>: the recorded argv is exactly the elements.
argv_equals() {
  local capture="$1"
  shift
  printf '%s\0' "$@" | cmp -s - "$capture"
}

# prompt_from_argv <capture>: print the single recorded argv element (the prompt) verbatim.
prompt_from_argv() {
  tr -d '\0' <"$1/argv.nul"
}

# placeholders_filled <file>: no {{NAME}} placeholder of the template survives.
placeholders_filled() {
  ! grep -Eq '\{\{(TARGET_LABEL|USER_FOCUS|REVIEW_COLLECTION_GUIDANCE|REVIEW_INPUT|OUTPUT_SCHEMA)\}\}' "$1"
}

# not_html_comment_start <file>: the prompt does not begin with the template's leading comment.
not_html_comment_start() {
  [ "$(head -c 4 "$1")" != '<!--' ]
}

# sha256_hex <text>: the SHA-256 hex digest of <text>.
sha256_hex() {
  local digest_line
  digest_line="$(printf '%s' "$1" | "${SHA_CMD[@]}")" || return 1
  printf '%s\n' "${digest_line%% *}"
}

# all_digits <text>: <text> is one or more ASCII digits.
all_digits() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# deadline_within <low> <high> <command prefix>: the last pass-through timeout call was
# `-k 5 <deadline> <command prefix>...` with an all-digit deadline in [<low>, <high>].
deadline_within() {
  local call_line deadline
  call_line="$(head -n 1 "$TIMEOUT_ARGS_LOG")" || return 1
  deadline="$(printf '%s\n' "$call_line" | awk '{ print $3 }')" || return 1
  all_digits "$deadline" || return 1
  [ "$deadline" -ge "$1" ] && [ "$deadline" -le "$2" ] || return 1
  case "$call_line" in
    "-k 5 $deadline $3"*) return 0 ;;
    *) return 1 ;;
  esac
}

# kill_within_call_budget <start epoch>: the seconds from <start epoch> to the timeout call, plus
# the deadline and the kill grace, are at most the call budget plus one second of rounding.
kill_within_call_budget() {
  local call_epoch deadline
  call_epoch="$(cat "$TIMEOUT_EPOCH_LOG")" || return 1
  deadline="$(awk 'NR == 1 { print $3 }' "$TIMEOUT_ARGS_LOG")" || return 1
  all_digits "$call_epoch" && all_digits "$deadline" || return 1
  [ $((call_epoch - $1 + deadline + KILL_GRACE_SECONDS)) -le $((CALL_BUDGET_SECONDS + 1)) ]
}

# ── Usage and base ref blockers ────────────────────────────────────────────────

REPO="$(new_repo usage)" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" unset ''
assert_blocked "usage:no-args" "$USAGE_REASON"
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" unset '' --base main --base main
assert_blocked "usage:base-twice" "$USAGE_REASON"
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" unset '' --base main -- one two
assert_blocked "usage:two-focus-args" "$USAGE_REASON"
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" unset '' --base '-x'
assert_blocked "base:leading-dash" 'base ref contains characters unsafe for shell invocation'
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" unset '' --base 'main;true'
assert_blocked "base:shell-metachar" 'base ref contains characters unsafe for shell invocation'
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" unset '' --base no-such-ref
assert_blocked "base:unresolvable" 'base ref cannot be resolved'
mkdir -p "$TMPDIR_TEST/not-a-repo"
run_review "$TMPDIR_TEST/not-a-repo" "$EMPTY_HOME" "$BIN_PASS" unset '' --base main
assert_blocked "repo:not-a-work-tree" 'not inside a git work tree'

# ── Skip: no-reviewer and bad-setting ──────────────────────────────────────────

run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" unset '' --base main
assert_skip "skip:no-reviewer-unset" 'skipped: no-reviewer'
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set '' --base main
assert_skip "skip:no-reviewer-empty" 'skipped: no-reviewer'

BAD_SETTINGS=(
  'not json'
  '[]'
  '{"argv":["x"]}'
  '"/bin/echo"'
  '[1]'
  '["x",""]'
  '["{prompt}","x"]'
  '["x","{prompt}","{prompt}"]'
  '["x\u0000y"]'
  '["x"] ["y"]'
  'codex'
)
bad_index=0
for bad_setting in "${BAD_SETTINGS[@]}"; do
  bad_index=$((bad_index + 1))
  run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$bad_setting" --base main
  assert_skip "skip:bad-setting-$bad_index $(printf '%q' "$bad_setting")" 'skipped: bad-setting'
done

# ── Skip: tool-missing, tool-failed, timed-out ─────────────────────────────────

run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(jq -nc --arg p "$FAKES/no-such-reviewer" '[$p]')" --base main
assert_skip "skip:tool-missing-127" 'skipped: tool-missing'
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(jq -nc --arg p "$NOT_EXECUTABLE" '[$p]')" --base main
assert_skip "skip:tool-missing-126" 'skipped: tool-missing'
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set 'codex-plugin' --base main
assert_skip "skip:tool-missing-preset-no-companion" 'skipped: tool-missing'

CAPTURE="$(new_capture tool-failed)" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$CAPTURE" fail "$BARE_REPLY" no)" --base main
assert_skip "skip:tool-failed-stderr-excerpt" "$(printf 'skipped: tool-failed\nstderr_excerpt: "boom: reviewer crashed"')"

STDOUT_ONLY_REPLY="$(write_reply stdout-only $'  failure reported on stdout  \n')" || exit 2
CAPTURE="$(new_capture tool-failed-stdout)" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$CAPTURE" fail-stdout-only "$STDOUT_ONLY_REPLY" no)" --base main
assert_skip "skip:tool-failed-blank-stderr-uses-stdout" \
  "$(printf 'skipped: tool-failed\nstderr_excerpt: "failure reported on stdout"')"

LONG_STDERR="$(printf 'a%.0s' $(seq 1 100))$(printf 'b%.0s' $(seq 1 300))"
LONG_REPLY="$(write_reply long-stderr "$LONG_STDERR")" || exit 2
CAPTURE="$(new_capture tool-failed-long)" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$CAPTURE" fail-long-stderr "$LONG_REPLY" no)" --base main
assert_skip "skip:tool-failed-excerpt-last-300" \
  "$(printf 'skipped: tool-failed\nstderr_excerpt: "...%s"' "$(printf 'b%.0s' $(seq 1 297))")"

CAPTURE="$(new_capture timed-out)" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_EXPIRE_124" set "$(reviewer_setting "$CAPTURE" reply "$BARE_REPLY" no)" --base main
assert_skip "skip:timed-out-124" 'skipped: timed-out'
run_review "$REPO" "$EMPTY_HOME" "$BIN_EXPIRE_137" set "$(reviewer_setting "$CAPTURE" reply "$BARE_REPLY" no)" --base main
assert_skip "skip:timed-out-137" 'skipped: timed-out'

# ── Skip: no timeout tool ──────────────────────────────────────────────────────

CAPTURE="$(new_capture no-timeout)" || exit 2
run_review_curated "$REPO" "$EMPTY_HOME" "$BIN_NONE" set "$(reviewer_setting "$CAPTURE" reply "$BARE_REPLY" no)" --base main
assert_skip "skip:no-timeout-tool" 'skipped: tool-missing'
assert_check "no-timeout:reviewer-never-ran" "the reviewer never ran without a timeout tool" \
  test ! -e "$CAPTURE/argv.nul"
run_review_curated "$REPO" "$EMPTY_HOME" "$BIN_NONE" unset '' --base main
assert_skip "skip:no-timeout-no-reviewer-first" 'skipped: no-reviewer'

# ── Generic run: argv {prompt} and stdin delivery ──────────────────────────────

ARGV_CAPTURE="$(new_capture argv-mode)" || exit 2
REPO="$(new_repo argv-mode)" || exit 2
: >"$TIMEOUT_ARGS_LOG"
: >"$TIMEOUT_EPOCH_LOG"
ARGV_START_EPOCH="$(date +%s)"
run_review "$REPO/src" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$ARGV_CAPTURE" reply "$BARE_REPLY" yes)" --base main
assert_success "argv:success" '.base == "main" and .verdict == "needs-attention"'
assert_check "argv:prompt-is-one-element" "argc is 1" grep -qx 1 "$ARGV_CAPTURE/argc"
assert_check "argv:stdin-empty" "stdin was empty" test ! -s "$ARGV_CAPTURE/stdin.txt"
prompt_from_argv "$ARGV_CAPTURE" >"$ARGV_CAPTURE/prompt.txt"
assert_check "argv:prompt-target" "prompt names the target" \
  file_has_text "$ARGV_CAPTURE/prompt.txt" 'Target: branch diff against main'
assert_check "argv:prompt-no-focus" "prompt carries the no-focus text" \
  file_has_text "$ARGV_CAPTURE/prompt.txt" 'User focus: No extra focus provided.'
assert_check "argv:prompt-inline-diff" "prompt inlines the diff" \
  file_has_text "$ARGV_CAPTURE/prompt.txt" '+line 3 MARKER_CHANGED_LINE'
assert_check "argv:prompt-placeholders-filled" "no template placeholder survives" \
  placeholders_filled "$ARGV_CAPTURE/prompt.txt"
assert_check "argv:prompt-comment-stripped" "leading HTML comment removed" \
  not_html_comment_start "$ARGV_CAPTURE/prompt.txt"
assert_check "argv:runs-from-top-level" "reviewer cwd is the work tree top" \
  test "$(cat "$ARGV_CAPTURE/cwd")" = "$REPO"
assert_check "argv:timeout-guard" "timeout got -k 5 <deadline in $DEADLINE_FAST_MIN..$DEADLINE_MAX> then the reviewer" \
  deadline_within "$DEADLINE_FAST_MIN" "$DEADLINE_MAX" "$FAKE_REVIEWER "
assert_check "budget:kill-before-call-budget" "call second + deadline + kill grace <= $((CALL_BUDGET_SECONDS + 1))" \
  kill_within_call_budget "$ARGV_START_EPOCH"
assert_check "argv:no-patch-file-small-diff" "small input writes no patch file" \
  no_run_patch_files "$REPO"

CAPTURE="$(new_capture gtimeout)" || exit 2
REPO="$(new_repo gtimeout)" || exit 2
: >"$TIMEOUT_ARGS_LOG"
run_review_curated "$REPO" "$EMPTY_HOME" "$BIN_GTIMEOUT" set "$(reviewer_setting "$CAPTURE" reply "$BARE_REPLY" no)" --base main
assert_success "argv:gtimeout-fallback" '.base == "main" and (.findings | length) == 2'
assert_check "argv:gtimeout-guard" "gtimeout got -k 5 <deadline> then the reviewer" \
  deadline_within "$DEADLINE_FAST_MIN" "$DEADLINE_MAX" "$FAKE_REVIEWER "

# A before-snapshot of over 3 seconds reserves twice its time for the after-check:
# 570 - 3 spent - 2 * 4 reserve - 5 grace = 554 at most.
CAPTURE="$(new_capture slow-snapshot)" || exit 2
REPO="$(new_repo slow-snapshot)" || exit 2
: >"$TIMEOUT_ARGS_LOG"
run_review "$REPO" "$EMPTY_HOME" "$BIN_SLOW_GIT" set "$(reviewer_setting "$CAPTURE" reply "$BARE_REPLY" no)" --base main
assert_success "slow-snapshot:success" '.base == "main"'
assert_check "budget:slow-snapshot-reserve" "a slow before-snapshot lowers the deadline to 554 or less" \
  deadline_within 60 554 "$FAKE_REVIEWER "

STDIN_CAPTURE="$(new_capture stdin-mode)" || exit 2
REPO="$(new_repo stdin-mode)" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$STDIN_CAPTURE" reply "$BARE_REPLY" no)" --base main
assert_success "stdin:success" '.base == "main"'
assert_check "stdin:no-prompt-arg" "argc is 0" grep -qx 0 "$STDIN_CAPTURE/argc"
assert_check "stdin:prompt-on-stdin" "stdin carries the prompt" \
  file_has_text "$STDIN_CAPTURE/stdin.txt" 'Target: branch diff against main'
assert_check "stdin:same-prompt-as-argv" "stdin prompt equals the argv prompt" \
  cmp -s "$STDIN_CAPTURE/stdin.txt" "$ARGV_CAPTURE/prompt.txt"

CAPTURE="$(new_capture focus)" || exit 2
REPO="$(new_repo focus)" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$CAPTURE" reply "$BARE_REPLY" no)" \
  --base main -- '  check the parser $(touch pwned)  '
assert_success "focus:success" '.base == "main"'
assert_check "focus:trimmed-and-inert" "focus text lands verbatim in the prompt" \
  file_has_text "$CAPTURE/stdin.txt" 'User focus: check the parser $(touch pwned)'
assert_check "focus:never-run" "the focus text was never run" test ! -e "$REPO/pwned"

CAPTURE="$(new_capture blank-focus)" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$CAPTURE" reply "$BARE_REPLY" no)" --base main -- '   '
assert_check "focus:blank-is-none" "white-space focus is no focus" \
  file_has_text "$CAPTURE/stdin.txt" 'User focus: No extra focus provided.'

# ── Output shape ───────────────────────────────────────────────────────────────

# run_reply_case <name> <reply file>: one generic stdin-mode run of the fake reviewer printing
# <reply file>, in a fresh repo copy.
run_reply_case() {
  local capture repo
  capture="$(new_capture "$1")" || return 1
  repo="$(new_repo "$1")" || return 1
  run_review "$repo" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$capture" reply "$2" no)" --base main
}

FENCED_REPLY="$(write_reply fenced "$(printf '\n  ```json\n%s\n```  \n' "$BASE_REVIEW")")" || exit 2
run_reply_case shape-fenced "$FENCED_REPLY"
assert_success "shape:one-json-fence-accepted" '.base == "main" and (.findings | length) == 2'

PADDED_REPLY="$(write_reply padded "$(printf '\n\t %s \n\n' "$BASE_REVIEW")")" || exit 2
run_reply_case shape-padded "$PADDED_REPLY"
assert_success "shape:bare-json-with-white-space-accepted" '.base == "main"'

PROSE_REPLY="$(write_reply prose "$(printf 'Here is my review:\n%s\n' "$BASE_REVIEW")")" || exit 2
run_reply_case shape-prose-before "$PROSE_REPLY"
assert_blocked "shape:prose-before-json-blocked" 'unexpected output shape'
RAW_LINE="$(sed -n '2p' "$RR_ERR")"
assert_check "shape:raw-excerpt-first-200" "raw_excerpt is the JSON string of the first 200 code points" \
  test "$RAW_LINE" = "raw_excerpt: $(printf 'Here is my review:\n%s' "$BASE_REVIEW" | jq -R -s -c '.[:200]')"

PROSE_AFTER_REPLY="$(write_reply prose-after "$(printf '%s\nHope this helps.\n' "$BASE_REVIEW")")" || exit 2
run_reply_case shape-prose-after "$PROSE_AFTER_REPLY"
assert_blocked "shape:prose-after-json-blocked" 'unexpected output shape'

PROSE_AROUND_FENCE_REPLY="$(write_reply prose-fence "$(printf 'Review:\n```json\n%s\n```\n' "$BASE_REVIEW")")" || exit 2
run_reply_case shape-prose-fence "$PROSE_AROUND_FENCE_REPLY"
assert_blocked "shape:prose-around-fence-blocked" 'unexpected output shape'

TWO_FENCES_REPLY="$(write_reply two-fences "$(printf '```json\n%s\n```\n```json\n%s\n```\n' "$BASE_REVIEW" "$BASE_REVIEW")")" || exit 2
run_reply_case shape-two-fences "$TWO_FENCES_REPLY"
assert_blocked "shape:two-fences-blocked" 'unexpected output shape'

PLAIN_FENCE_REPLY="$(write_reply plain-fence "$(printf '```\n%s\n```\n' "$BASE_REVIEW")")" || exit 2
run_reply_case shape-plain-fence "$PLAIN_FENCE_REPLY"
assert_blocked "shape:non-json-fence-blocked" 'unexpected output shape'

ONE_LINE_FENCE_REPLY="$(write_reply one-line-fence "$(printf '```json %s```\n' "$BASE_REVIEW")")" || exit 2
run_reply_case shape-one-line-fence "$ONE_LINE_FENCE_REPLY"
assert_blocked "shape:fence-without-newline-blocked" 'unexpected output shape'

TWO_OBJECTS_REPLY="$(write_reply two-objects "$(printf '%s\n%s\n' "$BASE_REVIEW" "$BASE_REVIEW")")" || exit 2
run_reply_case shape-two-objects "$TWO_OBJECTS_REPLY"
assert_blocked "shape:two-objects-blocked" 'unexpected output shape'

EMPTY_REPLY="$(write_reply empty '')" || exit 2
run_reply_case shape-empty "$EMPTY_REPLY"
assert_blocked "shape:empty-output-blocked" 'unexpected output shape'

ARRAY_REPLY="$(write_reply array "[$BASE_REVIEW]")" || exit 2
run_reply_case shape-array "$ARRAY_REPLY"
assert_blocked "shape:array-blocked" 'unexpected output shape'

# ── Schema violations ──────────────────────────────────────────────────────────

SCHEMA_VIOLATIONS=(
  'del(.next_steps)'
  '. + {extra: true}'
  '.verdict = "maybe"'
  '.summary = ""'
  '.findings = {}'
  '.next_steps = [""]'
  '.findings[0].severity = "blocker"'
  '.findings[0] += {extra: 1}'
  'del(.findings[0].recommendation)'
  '.findings[0].title = ""'
  '.findings[0].line_start = 0'
  '.findings[0].line_start = 1.5'
  '.findings[0].line_start = 10 | .findings[0].line_end = 9'
  '.findings[0].confidence = 1.5'
  '.findings[0].confidence = "high"'
  '.findings[0].recommendation = null'
)
violation_index=0
for violation in "${SCHEMA_VIOLATIONS[@]}"; do
  violation_index=$((violation_index + 1))
  REVIEW_JSON="$(derive_review "$violation")" || { failed "schema:derive-$violation_index" "$violation"; continue; }
  REPLY="$(write_reply "schema-$violation_index" "$REVIEW_JSON")" || exit 2
  run_reply_case "schema-$violation_index" "$REPLY"
  assert_blocked "schema:$violation" 'output does not match schema'
done

APPROVE_REPLY="$(write_reply approve "$(derive_review '.verdict = "approve" | .findings = [] | .next_steps = []')")" || exit 2
run_reply_case schema-approve-empty "$APPROVE_REPLY"
assert_success "schema:approve-with-no-findings" \
  '.verdict == "approve" and .findings == [] and .next_steps == [] and .dropped_outside_diff == 0'

# ── Out-of-diff filtering and finding_id ───────────────────────────────────────

run_reply_case filter "$BARE_REPLY"
assert_success "filter:changed-files-kept" '[.findings[].file] == ["src/a.txt", "src/new.txt"]'
assert_success "filter:dropped-counted" '.dropped_outside_diff == 3'
assert_success "filter:result-keys" \
  'keys_unsorted == ["base", "verdict", "summary", "findings", "next_steps", "dropped_outside_diff"]'
assert_success "filter:finding-id-first" \
  'all(.findings[]; keys_unsorted == ["finding_id", "severity", "title", "body", "file", "line_start", "line_end", "confidence", "recommendation"])'
assert_check "id:formula-matches-precomputed-a" "sha256 of the JSON array text is the precomputed digest" \
  test "$(sha256_hex "$ID_A_JSON_TEXT")" = "$ID_A_TXT"
assert_check "id:formula-matches-precomputed-new" "UTF-8 JSON array text digest is the precomputed digest" \
  test "$(sha256_hex "$ID_NEW_JSON_TEXT")" = "$ID_NEW_TXT"
assert_success "id:finding-a" ".findings[0].finding_id == \"$ID_A_TXT\""
assert_success "id:finding-new-utf8" ".findings[1].finding_id == \"$ID_NEW_TXT\""
assert_check "success:stderr-empty" "a clean run writes nothing to stderr" test ! -s "$RR_ERR"

# Four findings whose old run-together id texts collide in pairs: (1, 123) with (11, 23), and
# (12, "3 title") with (123, " title").
COLLISION_REVIEW="$(derive_review '
  .findings[0] as $base_finding
  | .findings = [
      $base_finding + {line_start: 1, line_end: 123, title: "Same title"},
      $base_finding + {line_start: 11, line_end: 23, title: "Same title"},
      $base_finding + {line_start: 5, line_end: 12, title: "3 title"},
      $base_finding + {line_start: 5, line_end: 123, title: " title"}
    ]')" || exit 2
COLLISION_JSON_TEXTS=(
  '["src/a.txt",1,123,"Same title"]'
  '["src/a.txt",11,23,"Same title"]'
  '["src/a.txt",5,12,"3 title"]'
  '["src/a.txt",5,123," title"]'
)
COLLISION_IDS=()
for collision_text in "${COLLISION_JSON_TEXTS[@]}"; do
  collision_id="$(sha256_hex "$collision_text")" || exit 2
  COLLISION_IDS+=("$collision_id")
done
COLLISION_REPLY="$(write_reply collision "$COLLISION_REVIEW")" || exit 2
assert_check "id:old-concatenation-collides" "each pair's old file+start+end+title bytes are equal" \
  jq -e '[.findings[] | .file + (.line_start | tostring) + (.line_end | tostring) + .title]
    | .[0] == .[1] and .[2] == .[3]' "$COLLISION_REPLY"
run_reply_case id-collision "$COLLISION_REPLY"
assert_success "id:boundary-distinct" '(.findings | length) == 4 and ([.findings[].finding_id] | unique | length) == 4'
assert_success "id:boundary-framed" \
  "[.findings[].finding_id] == $(jq -nc '$ARGS.positional' --args "${COLLISION_IDS[@]}")"

# ── Work tree changes: blocked, change left in place ───────────────────────────

# run_tree_case <name> <action>: one generic run whose fake reviewer performs <action>; sets REPO
# and TREE_HEAD_BEFORE.
run_tree_case() {
  local capture
  capture="$(new_capture "$1")" || return 1
  REPO="$(new_repo "$1")" || return 1
  TREE_HEAD_BEFORE="$(git -C "$REPO" rev-parse HEAD)" || return 1
  run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$capture" "$2" "$BARE_REPLY" no)" --base main
}

# tracked_file_modified <repo> <path>: git sees <path> modified in the work tree.
tracked_file_modified() {
  ! git -C "$1" diff --quiet -- "$2"
}

run_tree_case tree-edit edit-tracked
assert_blocked "tree:tracked-edit-blocked" 'reviewer modified the working tree'
assert_stderr_line "tree:tracked-edit-path" 'changed_path: "src/a.txt"'
assert_check "tree:tracked-edit-left-in-place" "src/a.txt is still modified" tracked_file_modified "$REPO" src/a.txt
assert_check "tree:tracked-edit-content-kept" "the reviewer's line is still there" \
  test "$(tail -n 1 "$REPO/src/a.txt")" = 'reviewer edit'

run_tree_case tree-untracked add-untracked
assert_blocked "tree:untracked-file-blocked" 'reviewer modified the working tree'
assert_stderr_line "tree:untracked-file-path" 'changed_path: "reviewer-note.txt"'
assert_check "tree:untracked-file-left-in-place" "reviewer-note.txt still exists" test -f "$REPO/reviewer-note.txt"

run_tree_case tree-head move-head
assert_blocked "tree:head-move-blocked" 'reviewer modified the working tree'
assert_stderr_line "tree:head-moved-line" 'head_moved: true'
assert_check "tree:head-move-left-in-place" "HEAD still points at the reviewer's commit" \
  test "$(git -C "$REPO" rev-parse HEAD)" != "$TREE_HEAD_BEFORE"
assert_check "tree:head-move-commit-kept" "the reviewer's commit is HEAD" \
  test "$(git -C "$REPO" log -1 --format=%s)" = 'reviewer commit'

run_tree_case tree-edit-fail edit-and-fail
assert_blocked "tree:check-precedes-exit-status" 'reviewer modified the working tree'
assert_check "tree:edit-fail-left-in-place" "src/a.txt is still modified" tracked_file_modified "$REPO" src/a.txt

# ── Large diff: patch file mode ────────────────────────────────────────────────

CAPTURE="$(new_capture large)" || exit 2
REPO="$(new_repo large "$LARGE_TEMPLATE_REPO")" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$CAPTURE" read-patch "$BARE_REPLY" no)" --base main
assert_success "large:success" '.base == "main"'
assert_check "large:patch-written" "the reviewer read the patch file during the run" \
  file_has_text "$CAPTURE/patch-seen" "+$LARGE_MARKER"
assert_check "large:patch-holds-diff" "the patch file holds the full diff" \
  file_has_text "$CAPTURE/patch-seen" '+line 3 MARKER_CHANGED_LINE'
assert_check "large:prompt-points-at-patch" "the prompt names the one patch file the reviewer saw" \
  one_patch_named_in "$CAPTURE" "$CAPTURE/stdin.txt"
assert_check "large:prompt-not-inlined" "the prompt does not inline the diff" \
  file_lacks_text "$CAPTURE/stdin.txt" "$LARGE_MARKER"
assert_check "large:patch-removed" "the patch file is gone after the run" no_run_patch_files "$REPO"

# A file already in the review-loop folder, such as one left by an older run, is never reused,
# overwritten or removed.
CAPTURE="$(new_capture large-stale)" || exit 2
REPO="$(new_repo large-stale "$LARGE_TEMPLATE_REPO")" || exit 2
mkdir -p "$REPO/$PATCH_DIR_REL"
printf 'EXISTING_FILE_CONTENT\n' >"$REPO/$PATCH_DIR_REL/review-diff.patch"
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$CAPTURE" read-patch "$BARE_REPLY" no)" --base main
assert_success "large-stale:success" '.base == "main"'
assert_check "large-stale:existing-file-kept" "the existing file is unchanged" \
  test "$(cat "$REPO/$PATCH_DIR_REL/review-diff.patch")" = 'EXISTING_FILE_CONTENT'
assert_check "large-stale:fresh-file-read" "the reviewer read a fresh file holding the diff" \
  file_has_text "$CAPTURE/patch-seen" "+$LARGE_MARKER"
assert_check "large-stale:prompt-names-fresh-file" "the prompt names the fresh file, not the existing one" \
  one_patch_named_in "$CAPTURE" "$CAPTURE/stdin.txt"
assert_check "large-stale:fresh-file-removed" "only the fresh file is removed" no_run_patch_files "$REPO"

# ── Preset: fake node + fake companion ─────────────────────────────────────────

# make_preset_home <name> <capture> <reply file> [version]: a scratch HOME holding one fake Codex
# companion that records its argv and prints <reply file>; prints the HOME path.
make_preset_home() {
  local preset_home="$TMPDIR_TEST/homes/$1" version="${4:-1.0.6}" companion_dir
  companion_dir="$preset_home/.claude/plugins/cache/openai-codex/codex/$version/scripts"
  mkdir -p "$companion_dir" || return 1
  add_companion "$companion_dir/codex-companion.mjs" "$2" "$3" || return 1
  printf '%s\n' "$preset_home"
}

# add_companion <path> <capture> <reply file>: write one fake companion script.
add_companion() {
  cat >"$1" <<STUB || return 1
#!/usr/bin/env bash
: >$(printf '%q' "$2/argv.nul")
for arg in "\$@"; do printf '%s\0' "\$arg" >>$(printf '%q' "$2/argv.nul"); done
cat >$(printf '%q' "$2/stdin.txt")
cat $(printf '%q' "$3")
STUB
}

PRESET_REPLY="$(write_reply preset "$(jq -nc --argjson review "$BASE_REVIEW" '{status: 0, result: $review}')")" || exit 2
PRESET_ARGV=(adversarial-review --base main --scope branch --wait --json)

CAPTURE="$(new_capture preset)" || exit 2
PRESET_HOME="$(make_preset_home preset "$CAPTURE" "$PRESET_REPLY")" || exit 2
REPO="$(new_repo preset)" || exit 2
: >"$TIMEOUT_ARGS_LOG"
run_review "$REPO" "$PRESET_HOME" "$BIN_PASS" set 'codex-plugin' --base main
assert_success "preset:result-used" \
  "[.findings[].finding_id] == [\"$ID_A_TXT\", \"$ID_NEW_TXT\"] and .dropped_outside_diff == 3"
assert_check "preset:argv" "node got the companion then the preset argv" \
  argv_equals "$CAPTURE/argv.nul" "${PRESET_ARGV[@]}"
assert_check "preset:stdin-empty" "the companion's stdin was empty" test ! -s "$CAPTURE/stdin.txt"
assert_check "preset:timeout-guard" "timeout got -k 5 <deadline in $DEADLINE_FAST_MIN..$DEADLINE_MAX> node <companion>" \
  deadline_within "$DEADLINE_FAST_MIN" "$DEADLINE_MAX" "node $PRESET_HOME/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs "

CAPTURE="$(new_capture preset-unset)" || exit 2
PRESET_HOME="$(make_preset_home preset-unset "$CAPTURE" "$PRESET_REPLY")" || exit 2
run_review "$REPO" "$PRESET_HOME" "$BIN_PASS" unset '' --base main
assert_success "preset:unset-setting-uses-companion" '.base == "main"'
assert_check "preset:unset-setting-argv" "the companion ran with the preset argv" \
  argv_equals "$CAPTURE/argv.nul" "${PRESET_ARGV[@]}"

CAPTURE="$(new_capture preset-empty)" || exit 2
PRESET_HOME="$(make_preset_home preset-empty "$CAPTURE" "$PRESET_REPLY")" || exit 2
run_review "$REPO" "$PRESET_HOME" "$BIN_PASS" set '' --base main
assert_success "preset:empty-setting-uses-companion" '.base == "main"'

CAPTURE="$(new_capture preset-focus)" || exit 2
PRESET_HOME="$(make_preset_home preset-focus "$CAPTURE" "$PRESET_REPLY")" || exit 2
run_review "$REPO" "$PRESET_HOME" "$BIN_PASS" set 'codex-plugin' --base main -- '  look at auth  '
assert_check "preset:focus-argv" "the trimmed focus follows --" \
  argv_equals "$CAPTURE/argv.nul" "${PRESET_ARGV[@]}" -- 'look at auth'
run_review "$REPO" "$PRESET_HOME" "$BIN_PASS" set 'codex-plugin' --base main -- '--dangerous flag'
assert_check "preset:dash-focus-prefixed" "a focus starting with - gets the focus: prefix" \
  argv_equals "$CAPTURE/argv.nul" "${PRESET_ARGV[@]}" -- 'focus: --dangerous flag'

CAPTURE="$(new_capture preset-newest)" || exit 2
OLD_CAPTURE="$(new_capture preset-oldest)" || exit 2
PRESET_HOME="$(make_preset_home preset-newest "$CAPTURE" "$PRESET_REPLY" 2.0.0)" || exit 2
OLD_COMPANION_DIR="$PRESET_HOME/.claude/plugins/cache/openai-codex/codex/9.9.9/scripts"
mkdir -p "$OLD_COMPANION_DIR" && add_companion "$OLD_COMPANION_DIR/codex-companion.mjs" "$OLD_CAPTURE" "$PRESET_REPLY" || exit 2
touch -t 202001010000 "$OLD_COMPANION_DIR/codex-companion.mjs"
run_review "$REPO" "$PRESET_HOME" "$BIN_PASS" set 'codex-plugin' --base main
assert_check "preset:newest-companion" "the newest companion by mtime ran" \
  test "$(cat "$NODE_LOG")" = "$PRESET_HOME/.claude/plugins/cache/openai-codex/codex/2.0.0/scripts/codex-companion.mjs"

# run_preset_reply_case <name> <reply file>: one preset run printing <reply file>.
run_preset_reply_case() {
  local capture preset_home
  capture="$(new_capture "$1")" || return 1
  preset_home="$(make_preset_home "$1" "$capture" "$2")" || return 1
  run_review "$REPO" "$preset_home" "$BIN_PASS" set 'codex-plugin' --base main
}

run_preset_reply_case preset-string-result "$(write_reply preset-string '{"result":"looks fine"}')"
assert_blocked "preset:non-object-result-blocked" 'unexpected output shape'
run_preset_reply_case preset-no-result "$(write_reply preset-no-result '{"status":0}')"
assert_blocked "preset:missing-result-blocked" 'unexpected output shape'
run_preset_reply_case preset-prose "$(write_reply preset-prose "$(printf 'Done.\n%s\n' "$(cat "$PRESET_REPLY")")")"
assert_blocked "preset:prose-blocked" 'unexpected output shape'
run_preset_reply_case preset-schema "$(write_reply preset-schema '{"result":{"verdict":"approve"}}')"
assert_blocked "preset:schema-violation-blocked" 'output does not match schema'

# ── Cleanup: only what the run created ─────────────────────────────────────────

REAL_MKTEMP="$(type -P mktemp)" || { echo "FAIL: mktemp is not an executable on PATH" >&2; exit 2; }
DECOYS="$TMPDIR_TEST/decoys"
SENTINEL_TEXT='DECOY_SENTINEL_CONTENT'
mkdir -p "$DECOYS" || exit 2

# write_fake_mktemp <bin dir> <dir|file> <decoy path> <exit code>: a fake mktemp that answers the
# `mktemp -d` call (dir) or any other call (file) by printing <decoy path> and exiting <exit
# code>, and passes every other call to the real mktemp; plus a pass-through timeout.
write_fake_mktemp() {
  local bin_dir="$1" target_kind="$2" decoy_path="$3" exit_code="$4"
  mkdir -p "$bin_dir" || return 1
  write_pass_timeout "$bin_dir/timeout" || return 1
  cat >"$bin_dir/mktemp" <<STUB || return 1
#!/usr/bin/env bash
call_kind=file
[ "\${1:-}" = -d ] && call_kind=dir
if [ "\$call_kind" = $(printf '%q' "$target_kind") ]; then
  printf '%s\n' $(printf '%q' "$decoy_path")
  exit $exit_code
fi
exec $(printf '%q' "$REAL_MKTEMP") "\$@"
STUB
  chmod +x "$bin_dir/mktemp"
}

# make_decoy_dir <name>: an existing folder holding one sentinel file; prints its path.
make_decoy_dir() {
  local decoy="$DECOYS/$1"
  mkdir -p "$decoy" && printf '%s\n' "$SENTINEL_TEXT" >"$decoy/sentinel" || return 1
  printf '%s\n' "$decoy"
}

# make_decoy_file <name>: an existing file holding the sentinel text; prints its path.
make_decoy_file() {
  local decoy="$DECOYS/$1"
  printf '%s\n' "$SENTINEL_TEXT" >"$decoy" || return 1
  printf '%s\n' "$decoy"
}

# decoy_dir_intact <dir>: the folder and its sentinel file still exist, the sentinel unchanged.
decoy_dir_intact() { [ -d "$1" ] && [ -f "$1/sentinel" ] && [ "$(cat "$1/sentinel")" = "$SENTINEL_TEXT" ]; }

# decoy_file_intact <file>: the file still exists with the sentinel text unchanged.
decoy_file_intact() { [ -f "$1" ] && [ "$(cat "$1")" = "$SENTINEL_TEXT" ]; }

# dir_has_no_entries <dir>: <dir> exists and holds nothing, dot files included.
dir_has_no_entries() { [ -d "$1" ] && [ -z "$(ls -A -- "$1")" ]; }

# no_run_work_dirs <dir>: no run-review.* work folder is left in <dir>.
no_run_work_dirs() { ! compgen -G "$1/run-review.*" >/dev/null; }

# run_decoy_dir_case <name> <exit code>: one run whose work-folder mktemp prints an existing
# decoy folder and exits <exit code>; sets DECOY.
run_decoy_dir_case() {
  local bin_dir="$FAKES/bin-$1" repo
  DECOY="$(make_decoy_dir "$1")" || return 1
  write_fake_mktemp "$bin_dir" dir "$DECOY" "$2" || return 1
  repo="$(new_repo "$1")" || return 1
  run_review "$repo" "$EMPTY_HOME" "$bin_dir" set "$(reviewer_setting "$(new_capture "$1")" reply "$BARE_REPLY" no)" --base main
}

# run_decoy_patch_case <name> <exit code>: one large-diff run whose diff-file mktemp prints an
# existing decoy file and exits <exit code>; sets DECOY and REPO.
run_decoy_patch_case() {
  local bin_dir="$FAKES/bin-$1"
  DECOY="$(make_decoy_file "$1")" || return 1
  write_fake_mktemp "$bin_dir" file "$DECOY" "$2" || return 1
  REPO="$(new_repo "$1" "$LARGE_TEMPLATE_REPO")" || return 1
  run_review "$REPO" "$EMPTY_HOME" "$bin_dir" set "$(reviewer_setting "$(new_capture "$1")" read-patch "$BARE_REPLY" no)" --base main
}

run_decoy_dir_case cleanup-dir-fail 1
assert_blocked "cleanup:dir-mktemp-fail-blocked" 'cannot create a private work folder'
assert_check "cleanup:dir-mktemp-fail-decoy-kept" "a failed mktemp's existing folder and its file survive" \
  decoy_dir_intact "$DECOY"
run_decoy_dir_case cleanup-dir-not-empty 0
assert_blocked "cleanup:dir-not-empty-blocked" 'cannot create a private work folder'
assert_check "cleanup:dir-not-empty-decoy-kept" "a non-empty folder from mktemp and its file survive" \
  decoy_dir_intact "$DECOY"

run_decoy_patch_case cleanup-patch-fail 1
assert_blocked "cleanup:patch-mktemp-fail-blocked" 'cannot prepare the review diff file'
assert_check "cleanup:patch-mktemp-fail-decoy-kept" "a failed mktemp's existing file survives" \
  decoy_file_intact "$DECOY"
run_decoy_patch_case cleanup-patch-not-empty 0
assert_blocked "cleanup:patch-not-empty-blocked" 'cannot prepare the review diff file'
assert_check "cleanup:patch-not-empty-decoy-kept" "a non-empty file from mktemp survives" \
  decoy_file_intact "$DECOY"

RR_TMPDIR="$TMPDIR_TEST/run-tmp-normal"
mkdir -p "$RR_TMPDIR" || exit 2
REPO="$(new_repo cleanup-normal)" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$(new_capture cleanup-normal)" reply "$BARE_REPLY" no)" --base main
assert_success "cleanup:normal-success" '.base == "main"'
assert_check "cleanup:normal-no-work-dir" "a normal run leaves no run-review.* folder" no_run_work_dirs "$RR_TMPDIR"
assert_check "cleanup:normal-tmpdir-empty" "a normal run leaves nothing in TMPDIR" dir_has_no_entries "$RR_TMPDIR"
assert_check "cleanup:normal-no-patch" "a normal run leaves no patch file" no_run_patch_files "$REPO"

RR_TMPDIR="$TMPDIR_TEST/run-tmp-large"
mkdir -p "$RR_TMPDIR" || exit 2
REPO="$(new_repo cleanup-large "$LARGE_TEMPLATE_REPO")" || exit 2
run_review "$REPO" "$EMPTY_HOME" "$BIN_PASS" set "$(reviewer_setting "$(new_capture cleanup-large)" read-patch "$BARE_REPLY" no)" --base main
assert_success "cleanup:large-success" '.base == "main"'
assert_check "cleanup:large-tmpdir-empty" "a large-diff run leaves nothing in TMPDIR" dir_has_no_entries "$RR_TMPDIR"
assert_check "cleanup:large-no-patch" "a large-diff run leaves no patch file" no_run_patch_files "$REPO"
RR_TMPDIR="$RUN_TMPDIR"

# has_recursive_rm <file>: <file> holds an rm call with a recursive flag (-r, -R, -rf, -fr, ...
# or --recursive).
has_recursive_rm() {
  grep -Eq '(^|[^[:alnum:]_.-])rm[[:space:]]+(-[^[:space:]]*[[:space:]]+)*(-[[:alnum:]]*[rR][[:alnum:]]*|--recursive)([[:space:]]|$)' "$1"
}

# work_names_listed <file>: every `$work_dir/<name>` in <file> is in its WORK_FILE_NAMES list,
# or is a snapshot prefix whose `<name>.<suffix>` is listed for every `$prefix.<suffix>` it uses.
work_names_listed() {
  local listed used_names suffixes name suffix
  listed="$(sed -n '/^WORK_FILE_NAMES=($/,/^)$/p' "$1" | sed '1d;$d' | tr -s ' \t' '\n\n' | grep -v '^$')"
  used_names="$(grep -o '\$work_dir/[A-Za-z0-9._-]*' "$1" | sed 's|^\$work_dir/||' | grep -v '^$' | sort -u)"
  suffixes="$(grep -o '\$prefix\.[A-Za-z0-9_-]*' "$1" | sed 's|^\$prefix\.||' | sort -u)"
  [ -n "$listed" ] && [ -n "$used_names" ] && [ -n "$suffixes" ] || return 1
  while IFS= read -r name; do
    printf '%s\n' "$listed" | grep -Fxq -- "$name" && continue
    while IFS= read -r suffix; do
      printf '%s\n' "$listed" | grep -Fxq -- "$name.$suffix" || { echo "unlisted work file: $name" >&2; return 1; }
    done <<<"$suffixes"
  done <<<"$used_names"
}

STATIC_PROBES="$TMPDIR_TEST/static-probes"
mkdir -p "$STATIC_PROBES" || exit 2
cp "$RUN_REVIEW" "$STATIC_PROBES/with-rm-rf.sh" && printf '  rm -fr -- "$work_dir"\n' >>"$STATIC_PROBES/with-rm-rf.sh" || exit 2
cp "$RUN_REVIEW" "$STATIC_PROBES/with-unlisted.sh" && printf ': >"$work_dir/unlisted.txt"\n' >>"$STATIC_PROBES/with-unlisted.sh" || exit 2
assert_check "static:no-recursive-rm" "run-review.sh holds no recursive rm" eval '! has_recursive_rm "$RUN_REVIEW"'
assert_check "static:recursive-rm-probe" "the recursive rm check flags an appended rm -fr" \
  has_recursive_rm "$STATIC_PROBES/with-rm-rf.sh"
assert_check "static:work-files-listed" "every work file the script writes is in WORK_FILE_NAMES" \
  work_names_listed "$RUN_REVIEW"
assert_check "static:unlisted-probe" "the list check flags an appended unlisted work file" \
  eval '! work_names_listed "$STATIC_PROBES/with-unlisted.sh" 2>/dev/null'

# Every run of the suite shared RUN_TMPDIR; none may leave a work folder there.
assert_check "cleanup:suite-no-work-dir" "no run of the suite left a run-review.* folder" \
  dir_has_no_entries "$RUN_TMPDIR"

# ── Summary ────────────────────────────────────────────────────────────────────
echo
echo "run-review: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
