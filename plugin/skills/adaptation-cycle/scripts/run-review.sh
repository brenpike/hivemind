#!/usr/bin/env bash
#
# run-review: THIN executable entrypoint (ADR-0020) for hivemind:adaptation-cycle. It runs ONE
# local pre-PR adversarial review of the current branch with the reviewer that
# HIVEMIND_LOCAL_REVIEWER names, checks that the reviewer left the work tree alone, checks the
# review against the findings schema and prints normalized findings. It fixes nothing and never
# names a model. Design: ADR-0042 (tool-neutral local review).
#
# INPUT:
#   --base <ref>      REQUIRED, exactly once. The ref the branch is reviewed against. It must
#                     match ^[a-zA-Z0-9/_.-]+$ and not start with `-` (`base ref contains
#                     characters unsafe for shell invocation`), and `git rev-parse --verify
#                     --quiet <ref>^{commit}` must name a commit (`base ref cannot be resolved`).
#   -- <focus>        OPTIONAL, after the flags: exactly one argument, inert caller data. Empty
#                     or white-space-only focus is no focus. It is never run, evaluated or put in
#                     a program text.
#   Any other argument shape is the usage blocker.
#
# REVIEWER (env HIVEMIND_LOCAL_REVIEWER, read once; its value never reaches output):
#   unset or empty    the `codex-plugin` preset when a Codex companion script is installed,
#                     else `skipped: no-reviewer`.
#   codex-plugin      the preset; no companion script is `skipped: tool-missing`.
#   JSON array        a generic argv run: one JSON value, an array of at least one non-empty
#                     string, no NUL character, at most one element exactly `{prompt}`, and the
#                     first element not `{prompt}`. Parsed by jq; each element becomes one argv
#                     element read NUL-delimited. No shell and no eval runs it, and argv[0] is
#                     always run as an external program, never a shell builtin or function.
#   anything else     `skipped: bad-setting`.
#   The companion script is the newest (by mtime) match of
#   $HOME/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs.
#
# PRESET RUN: node <companion> adversarial-review --base <base> --scope branch --wait --json
#   [-- <focus>], stdin /dev/null. A focus whose first non-space character is `-` gets the prefix
#   `focus: `. The companion must print one JSON object. Its `.result`, when an object, is the
#   review, even when `.rawOutput` differs. Otherwise its `.rawOutput`, when a string, is read
#   as a generic reply (RESULT CHECKS). Otherwise the result is the output shape blocker.
#
# GENERIC RUN: the prompt is references/adversarial-review.md with its leading HTML comment
#   removed and its placeholders filled in one jq pass (a filled value is never scanned again):
#   {{TARGET_LABEL}} `branch diff against <base>`, {{USER_FOCUS}} the focus or `No extra focus
#   provided.`, {{REVIEW_COLLECTION_GUIDANCE}}, {{REVIEW_INPUT}} and {{OUTPUT_SCHEMA}} (the text
#   of references/review-output.schema.json). A template missing a placeholder is the blocker
#   `cannot build the review prompt`. The review input is the commit log (<base>..HEAD), the
#   diff stat and `git diff --no-color --no-ext-diff <base>...HEAD`. Input of at most 65536 bytes
#   goes inline. Larger input is written to a new file .hivemind/review-loop/review-diff.<random>
#   (made by mktemp, so it never reuses or overwrites an existing file, in a contained folder,
#   see _shared/containment.sh) before the before-snapshot, the prompt points at that file, and
#   only that file is removed after the after-check. A `{prompt}` element is replaced whole by the
#   prompt as one argv element, with stdin /dev/null; otherwise the prompt goes on stdin.
#
# EXECUTION: from the top of the work tree, only under `<timeout> -k 5 <deadline>`, where
#   <timeout> is the executable `timeout` on PATH, else `gtimeout` (resolved by `type -P`, so a
#   shell function or builtin of that name is never used). With neither, the result is
#   `skipped: tool-missing`, decided right after the reviewer setting and before any other work;
#   the reviewer never runs unguarded. The deadline is derived from CALL_BUDGET_SECONDS (570: 30
#   seconds under the 600-second cap that the review call in the adaptation-cycle SKILL.md sets
#   with `timeout: 600000`): the budget less the seconds the script has spent (SECONDS, reset at its start), less
#   twice the before-snapshot time (its whole seconds plus one) as the reserve for the
#   after-check, less the 5-second kill grace. A deadline under MIN_REVIEW_SECONDS (60) is
#   `skipped: timed-out` without running the reviewer. stdout and stderr go to files in a private
#   mktemp folder. The EXIT trap removes only the files the script writes there, each by its name
#   in WORK_FILE_NAMES, then the folder itself only when it is empty, and the large-diff file;
#   it never deletes recursively. It acts only on a path mktemp created (exit 0) and the checks
#   confirmed: the folder a real, empty directory, the diff file an empty regular file, neither
#   a symlink. A path that fails them is the creation blocker and is left in place.
#
# BEFORE/AFTER CHECK: before the run the script records HEAD, `git status --porcelain=v1 -z
#   --untracked-files=all --no-renames`, and for every path of `git ls-files -z --cached --others
#   --exclude-standard` its kind and content (`git hash-object --no-filters` for a regular file,
#   the link text for a symlink). It records them again after the run, timeout and failure
#   included, and checks this BEFORE every other result check. Any difference is the blocker
#   `reviewer modified the working tree`. Nothing is ever reverted.
#
# RESULT CHECKS, in order, after the before/after check:
#   exit 124 or 137   `skipped: timed-out`
#   exit 126 or 127   `skipped: tool-missing`
#   other non-zero    `skipped: tool-failed`, then `stderr_excerpt: <JSON string>`: the trimmed
#                     stderr (stdout when stderr is blank, as the preset reports failures there),
#                     cut to its last 300 code points with `...` in front when cut.
#   exit 0            the review is taken from the trimmed reply (generic: stdout; preset:
#                     PRESET RUN) by the first of these rules that yields exactly one JSON
#                     object (jq -s length 1): (a) the whole reply; (b) the inside of its one
#                     fenced block, when the reply holds exactly two ``` marks and the first is
#                     ```json or ``` followed by a line break (spaces or tabs may come first);
#                     (c) the text from the first `{` to the last `}`, when no `{`, `}`, `[` or
#                     `]` lies outside it. When no rule yields one, or the preset output has
#                     neither an object `.result` nor a string `.rawOutput`, the result is
#                     `unexpected output shape` with `raw_excerpt: <JSON string>` (the first 200
#                     code points of the trimmed stdout). The review must then match review-output.schema.json (verdict, summary, findings,
#                     next_steps, no other key; each finding exactly severity, title, body, file,
#                     line_start, line_end, confidence, recommendation, with integer lines >= 1,
#                     line_end >= line_start and confidence in 0..1); else `output does not
#                     match schema`.
#   A finding is kept only when its `file` is a new-side path of `git diff --name-only -z
#   --no-renames --diff-filter=d <base>...HEAD` (exact string match); the others are dropped and
#   counted. Each kept finding gets `finding_id`: the SHA-256 hex digest (sha256sum, else shasum
#   -a 256) of the compact UTF-8 JSON text of the array [file, line_start, line_end, title], as
#   jq's `[.file, .line_start, .line_end, .title] | tojson` prints it, e.g.
#   `["src/a.txt",9,9,"A title"]`. The JSON framing keeps the fields apart, so (1, 123) and
#   (11, 23) give different ids.
#
# OUTPUT / EXIT CONTRACT:
#   0  success: ONE line on stdout, a JSON object
#        {"base", "verdict", "summary", "findings", "next_steps", "dropped_outside_diff"}
#      each finding being the reviewer's fields with `finding_id` first.
#   0  skip: `skipped: <reason>` on stdout, reason exactly no-reviewer | bad-setting |
#      tool-missing | tool-failed | timed-out; tool-failed adds the stderr_excerpt line.
#      tool-missing also covers no `timeout` or `gtimeout` executable on PATH; timed-out also
#      covers a deadline under the 60-second floor (EXECUTION).
#   1  blocked: NOTHING on stdout. stderr carries `blocker: <fixed reason>` as its FIRST line,
#      then detail lines: `raw_excerpt: <JSON string>` (unexpected output shape), or for the
#      working tree blocker an optional `head_moved: true` line and up to 50
#      `changed_path: <JSON string>` lines, then `changed_path_more: <n>` when there are more.
#      Other fixed reasons: usage, the two base ref reasons, `jq not found`, `git not found`,
#      `not inside a git work tree`, `no sha256 tool found`, `cannot compute the branch diff`,
#      `cannot prepare the review diff file`, `cannot build the review prompt`, `cannot
#      snapshot the working tree`, `cannot remove the review diff file`, `cannot compute a
#      finding id`, `cannot create a private work folder`, `cannot self-locate the script
#      directory`, `review references missing`.
#
# NOT CHECKED: ignored files (outside the snapshot, so a write there is not seen); the content
# of a submodule or nested repository (its folder is recorded as a folder; git status still
# reports its changes); paths that are not UTF-8 are compared after jq's decoding only when
# the changed paths are listed. The reviewer command is operator config and is trusted to be
# what the operator chose; the script only keeps any shell out of the path between the setting
# and the exec. An after-check that outlasts its reserve ends the call at the Bash tool's cap,
# and the skill then blocks with `review timed out`, never passes. A reviewer that leaves its
# process group escapes the timeout's kill (the operator-configured command is trusted). The
# stderr_excerpt and raw_excerpt are not redacted, per ADR-0042 Implementation decisions item 9.
#
# Conventions (ADR-0020 thin entrypoint): `set -euo pipefail`, an EXIT trap ending in a
# guaranteed-zero `:`, self-location via `cd && pwd -P`, bash 3.2 compatible (no mapfile, no
# associative arrays), jq for every JSON read and write.

set -euo pipefail
SECONDS=0

work_dir=''
patch_path=''

# INVARIANT: every file the script writes in $work_dir is named here (snapshot files as
# <prefix>.<suffix>); cleanup removes exactly these names, so a name missing here leaves the
# folder behind instead of being deleted with it.
WORK_FILE_NAMES=(
  argv.nul candidate.json changed-paths.txt changed.nul ids.txt kept.json prompt.txt
  raw-output.txt review-input-pointer.txt review-input.txt review.json stderr stdout
  before.hashes before.head before.kinds before.list before.regular before.snap before.status
  after.hashes after.head after.kinds after.list after.regular after.snap after.status
)
readonly WORK_FILE_NAMES

remove_private_files() {
  local name work_paths=()
  if [ -n "$patch_path" ] && { [ -f "$patch_path" ] || [ -L "$patch_path" ]; }; then
    rm -f -- "$patch_path" 2>/dev/null || :
  fi
  if [ -n "$work_dir" ] && [ -d "$work_dir" ] && [ ! -L "$work_dir" ]; then
    for name in "${WORK_FILE_NAMES[@]}"; do
      work_paths+=("$work_dir/$name")
    done
    rm -f -- "${work_paths[@]}" 2>/dev/null || :
    rmdir -- "$work_dir" 2>/dev/null || :
  fi
  :
}
trap remove_private_files EXIT

blocker() {
  printf 'blocker: %s\n' "$1" >&2
  shift
  [ "$#" -eq 0 ] || printf '%s\n' "$@" >&2
  exit 1
}

skip_review() {
  printf 'skipped: %s\n' "$1"
  shift
  [ "$#" -eq 0 ] || printf '%s\n' "$@"
  exit 0
}

usage_reason='invalid arguments; usage: run-review.sh --base <ref> [-- <focus>]'
readonly INLINE_INPUT_LIMIT=65536
readonly CALL_BUDGET_SECONDS=570
readonly MIN_REVIEW_SECONDS=60
readonly REVIEW_KILL_GRACE_SECONDS=5
readonly PATCH_DIR_REL='.hivemind/review-loop'

base=''
base_seen=false
focus=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      [ "$#" -ge 2 ] && [ "$base_seen" = false ] || blocker "$usage_reason"
      base="$2"
      base_seen=true
      shift 2
      ;;
    --)
      [ "$#" -eq 2 ] || blocker "$usage_reason"
      focus="$2"
      shift 2
      ;;
    *)
      blocker "$usage_reason"
      ;;
  esac
done
[ "$base_seen" = true ] || blocker "$usage_reason"

script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory"
template_path="$script_dir/../references/adversarial-review.md"
schema_path="$script_dir/../references/review-output.schema.json"
[ -f "$template_path" ] && [ -f "$schema_path" ] || blocker 'review references missing'
shared_dir="$(CDPATH= cd -- "$script_dir/../../_shared" 2>/dev/null && pwd -P 2>/dev/null)" || blocker "cannot self-locate the script directory"
[ -f "$shared_dir/containment.sh" ] || blocker "review references missing"
# shellcheck source=../../_shared/containment.sh
. "$shared_dir/containment.sh" || blocker "review references missing"

command -v jq >/dev/null 2>&1 || blocker 'jq not found'
command -v git >/dev/null 2>&1 || blocker 'git not found'

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || blocker 'not inside a git work tree'
[ -n "$repo_root" ] || blocker 'not inside a git work tree'
cd -- "$repo_root" || blocker 'not inside a git work tree'

base_pattern='^[a-zA-Z0-9/_.-]+$'
case "$base" in
  -*) blocker 'base ref contains characters unsafe for shell invocation' ;;
esac
[[ "$base" =~ $base_pattern ]] || blocker 'base ref contains characters unsafe for shell invocation'
git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 || blocker 'base ref cannot be resolved'

# focus_text: the focus with leading and trailing white space removed ('' when none).
focus_text="${focus#"${focus%%[![:space:]]*}"}"
focus_text="${focus_text%"${focus_text##*[![:space:]]}"}"

# find_codex_companion: set companion_path to the newest installed Codex companion script, or
# '' when none is installed.
companion_path=''
find_codex_companion() {
  local candidate
  [ -n "${HOME:-}" ] || return 0
  for candidate in "$HOME"/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs; do
    [ -f "$candidate" ] || continue
    if [ -z "$companion_path" ] || [ "$candidate" -nt "$companion_path" ]; then
      companion_path="$candidate"
    fi
  done
}

# True only for one JSON array of non-empty, NUL-free strings with at most one `{prompt}`
# element, which is not the first.
SETTING_CHECK='
  try (
    length == 1
    and (.[0] | type) == "array"
    and (.[0] | length) >= 1
    and all(.[0][]; type == "string" and length >= 1 and (explode | all(. != 0)))
    and ([.[0][] | select(. == "{prompt}")] | length) <= 1
    and .[0][0] != "{prompt}"
  ) catch false'

setting="${HIVEMIND_LOCAL_REVIEWER:-}"
reviewer_mode=''
if [ -z "$setting" ]; then
  find_codex_companion
  [ -n "$companion_path" ] || skip_review 'no-reviewer'
  reviewer_mode='preset'
elif [ "$setting" = 'codex-plugin' ]; then
  find_codex_companion
  [ -n "$companion_path" ] || skip_review 'tool-missing'
  reviewer_mode='preset'
else
  printf '%s' "$setting" | jq -s -e "$SETTING_CHECK" >/dev/null 2>&1 || skip_review 'bad-setting'
  reviewer_mode='generic'
fi

timeout_path="$(type -P timeout)" || timeout_path="$(type -P gtimeout)" || skip_review 'tool-missing'
[ -n "$timeout_path" ] || skip_review 'tool-missing'

if command -v sha256sum >/dev/null 2>&1; then
  sha_cmd=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  sha_cmd=(shasum -a 256)
else
  blocker 'no sha256 tool found'
fi

# dir_is_empty <dir>: true when <dir> holds no entry, dot files included.
dir_is_empty() {
  local entries=()
  shopt -s nullglob dotglob
  entries=("$1"/*)
  shopt -u nullglob dotglob
  [ "${#entries[@]}" -eq 0 ]
}

new_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/run-review.XXXXXX" 2>/dev/null)" || blocker 'cannot create a private work folder'
[ -n "$new_work_dir" ] && [ -d "$new_work_dir" ] && [ ! -L "$new_work_dir" ] && dir_is_empty "$new_work_dir" \
  || blocker 'cannot create a private work folder'
work_dir="$new_work_dir"

git diff --name-only -z --no-renames --diff-filter=d "$base...HEAD" >"$work_dir/changed.nul" 2>/dev/null || blocker 'cannot compute the branch diff'

# Fills the template in one pass: the leading HTML comment goes, then every {{NAME}} whose NAME
# is a key of $vals is replaced; a filled value is never scanned again. Fails when the template
# lacks any placeholder.
FILL_PROGRAM='
  def strip_leading_comment:
    if startswith("<!--") then (split("-->") | .[1:] | join("-->") | ltrimstr("\n")) else . end;
  def fill($vals):
    split("{{") as $parts
    | $parts[0] + ([$parts[1:][] as $seg
        | ([$vals | keys[] | select(. as $k | $seg | startswith($k + "}}"))] | .[0]) as $key
        | if $key == null then "{{" + $seg else $vals[$key] + $seg[(($key | length) + 2):] end
      ] | join(""));
  {
    TARGET_LABEL: $target,
    USER_FOCUS: $focus,
    REVIEW_COLLECTION_GUIDANCE: $guidance,
    REVIEW_INPUT: $input,
    OUTPUT_SCHEMA: ($schema | rtrimstr("\n"))
  } as $vals
  | ($template | strip_leading_comment) as $body
  | if all($vals | keys[]; . as $k | $body | contains("{{" + $k + "}}"))
    then $body | fill($vals)
    else error("template is missing a placeholder")
    end'

# write_review_input: print the review input (commit log, diff stat, full diff) to stdout.
# Returns non-zero on any failed git read.
write_review_input() {
  local head_sha
  head_sha="$(git rev-parse --verify --quiet HEAD)" || return 1
  printf 'Base: %s\nHead: %s\n\n## Commit log\n\n' "$base" "$head_sha" || return 1
  git log --no-color --no-decorate --format='%h %s' "$base..HEAD" || return 1
  printf '\n## Diff stat\n\n' || return 1
  git diff --no-color --no-ext-diff --stat "$base...HEAD" || return 1
  printf '\n## Diff\n\n' || return 1
  git diff --no-color --no-ext-diff "$base...HEAD" || return 1
}

# build_generic_prompt: write the filled prompt to $work_dir/prompt.txt, and the review diff
# file when the review input is over the inline limit.
build_generic_prompt() {
  local input_path="$work_dir/review-input.txt" input_bytes guidance input_text_path canon_root patch_rel
  local new_patch_path
  write_review_input >"$input_path" 2>/dev/null || blocker 'cannot compute the branch diff'
  input_bytes="$(wc -c <"$input_path")" || blocker 'cannot compute the branch diff'
  input_bytes=$((input_bytes + 0))
  if [ "$input_bytes" -le "$INLINE_INPUT_LIMIT" ]; then
    guidance='The commit log, diff stat and full diff are inlined in the repository context below. Read other repository files as needed for context, without changing anything.'
    input_text_path="$input_path"
  else
    canon_root="$(hivemind_assert_contained "$repo_root" "$PATCH_DIR_REL" 2>/dev/null)" || blocker 'cannot prepare the review diff file'
    [ -n "$canon_root" ] || blocker 'cannot prepare the review diff file'
    mkdir -p -- "$canon_root/$PATCH_DIR_REL" || blocker 'cannot prepare the review diff file'
    new_patch_path="$(mktemp "$canon_root/$PATCH_DIR_REL/review-diff.XXXXXXXXXX")" || blocker 'cannot prepare the review diff file'
    [ -n "$new_patch_path" ] && [ -f "$new_patch_path" ] && [ ! -L "$new_patch_path" ] && [ ! -s "$new_patch_path" ] \
      || blocker 'cannot prepare the review diff file'
    patch_path="$new_patch_path"
    patch_rel="$PATCH_DIR_REL/${patch_path##*/}"
    cat -- "$input_path" >"$patch_path" || blocker 'cannot prepare the review diff file'
    guidance="The change is too large to inline. Before you review, read the file $patch_rel at the repository root with your file-read tool: it holds the commit log, diff stat and full diff. Read other repository files as needed for context, without changing anything."
    input_text_path="$work_dir/review-input-pointer.txt"
    printf 'The commit log, diff stat and full diff against %s are in %s at the repository root (%s bytes).\n' \
      "$base" "$patch_rel" "$input_bytes" >"$input_text_path" || blocker 'cannot prepare the review diff file'
  fi
  jq -n -j \
    --rawfile template "$template_path" \
    --rawfile schema "$schema_path" \
    --rawfile input "$input_text_path" \
    --arg target "branch diff against $base" \
    --arg focus "${focus_text:-No extra focus provided.}" \
    --arg guidance "$guidance" \
    "$FILL_PROGRAM" >"$work_dir/prompt.txt" 2>/dev/null || blocker 'cannot build the review prompt'
}

run_argv=()
stdin_path='/dev/null'
if [ "$reviewer_mode" = 'preset' ]; then
  run_argv=(node "$companion_path" adversarial-review --base "$base" --scope branch --wait --json)
  if [ -n "$focus_text" ]; then
    case "$focus_text" in
      -*) run_argv+=(-- "focus: $focus_text") ;;
      *) run_argv+=(-- "$focus_text") ;;
    esac
  fi
else
  build_generic_prompt
  printf '%s' "$setting" | jq -j '.[] | (., "\u0000")' >"$work_dir/argv.nul" 2>/dev/null || skip_review 'bad-setting'
  prompt_text="$(cat -- "$work_dir/prompt.txt" && printf x)" || blocker 'cannot build the review prompt'
  prompt_text="${prompt_text%x}"
  has_prompt_slot=false
  while IFS= read -r -d '' element; do
    if [ "$element" = '{prompt}' ]; then
      run_argv+=("$prompt_text")
      has_prompt_slot=true
    else
      run_argv+=("$element")
    fi
  done <"$work_dir/argv.nul"
  [ "${#run_argv[@]}" -ge 1 ] || skip_review 'bad-setting'
  [ "$has_prompt_slot" = true ] || stdin_path="$work_dir/prompt.txt"
fi

# take_snapshot <prefix>: record HEAD (<prefix>.head), git status (<prefix>.status) and the kind
# and content of every tracked or untracked non-ignored path (<prefix>.snap, NUL-delimited
# `path` `kind` pairs). Returns non-zero on any failed read.
take_snapshot() {
  local prefix="$1" entry kind hash
  git rev-parse --verify --quiet HEAD >"$prefix.head" 2>/dev/null || return 1
  git --no-optional-locks status --porcelain=v1 -z --untracked-files=all --no-renames >"$prefix.status" 2>/dev/null || return 1
  git ls-files -z --cached --others --exclude-standard >"$prefix.list" 2>/dev/null || return 1
  while IFS= read -r -d '' entry; do
    if [ -L "$entry" ]; then
      kind="l:$(readlink -- "$entry")" || return 1
    elif [ -f "$entry" ]; then
      kind='f'
      printf '%s\0' "$entry" >&3 || return 1
    elif [ -d "$entry" ]; then
      kind='d'
    elif [ -e "$entry" ]; then
      kind='o'
    else
      kind='m'
    fi
    printf '%s\0%s\0' "$entry" "$kind" || return 1
  done <"$prefix.list" >"$prefix.kinds" 3>"$prefix.regular" || return 1
  xargs -0 git hash-object --no-filters -- <"$prefix.regular" >"$prefix.hashes" 2>/dev/null || return 1
  while IFS= read -r -d '' entry && IFS= read -r -d '' kind; do
    if [ "$kind" = 'f' ]; then
      IFS= read -r hash <&3 || return 1
      kind="f:$hash"
    fi
    printf '%s\0%s\0' "$entry" "$kind" || return 1
  done <"$prefix.kinds" >"$prefix.snap" 3<"$prefix.hashes" || return 1
}

# Lists the paths whose snapshot record or status entry differs, each as a JSON string.
CHANGED_PATHS_PROGRAM='
  def pairs: split("\u0000") | . as $p
    | [range(0; (length / 2 | floor)) | {key: $p[2 * .], value: $p[2 * . + 1]}] | from_entries;
  def entries: split("\u0000") | map(select(length > 0));
  ($snap_before | pairs) as $a | ($snap_after | pairs) as $b
  | ($status_before | entries) as $sa | ($status_after | entries) as $sb
  | ([($a + $b) | keys[] | select($a[.] != $b[.])] + [(($sa - $sb) + ($sb - $sa))[] | .[3:]])
  | unique
  | (.[:50][] | "changed_path: " + tojson),
    (if length > 50 then "changed_path_more: \(length - 50)" else empty end)'

before="$work_dir/before"
after="$work_dir/after"
snapshot_started="$SECONDS"
take_snapshot "$before" || blocker 'cannot snapshot the working tree'
snapshot_seconds=$((SECONDS - snapshot_started + 1))

# INVARIANT: review_seconds >= MIN_REVIEW_SECONDS > 0 here, so GNU `timeout 0` (no limit) is
# never reached.
review_seconds=$((CALL_BUDGET_SECONDS - SECONDS - 2 * snapshot_seconds - REVIEW_KILL_GRACE_SECONDS))
[ "$review_seconds" -ge "$MIN_REVIEW_SECONDS" ] || skip_review 'timed-out'

run_status=0
"$timeout_path" -k "$REVIEW_KILL_GRACE_SECONDS" "$review_seconds" "${run_argv[@]}" \
  <"$stdin_path" >"$work_dir/stdout" 2>"$work_dir/stderr" || run_status=$?

take_snapshot "$after" || blocker 'cannot snapshot the working tree'
tree_changed=false
head_moved=false
cmp -s "$before.head" "$after.head" || { tree_changed=true; head_moved=true; }
cmp -s "$before.status" "$after.status" || tree_changed=true
cmp -s "$before.snap" "$after.snap" || tree_changed=true
if [ "$tree_changed" = true ]; then
  change_lines=()
  [ "$head_moved" = false ] || change_lines+=('head_moved: true')
  jq -n -r \
    --rawfile snap_before "$before.snap" --rawfile snap_after "$after.snap" \
    --rawfile status_before "$before.status" --rawfile status_after "$after.status" \
    "$CHANGED_PATHS_PROGRAM" >"$work_dir/changed-paths.txt" 2>/dev/null \
    || blocker 'reviewer modified the working tree' ${change_lines[@]+"${change_lines[@]}"}
  while IFS= read -r line; do
    change_lines+=("$line")
  done <"$work_dir/changed-paths.txt"
  blocker 'reviewer modified the working tree' ${change_lines[@]+"${change_lines[@]}"}
fi

if [ -n "$patch_path" ]; then
  rm -f -- "$patch_path" || blocker 'cannot remove the review diff file'
  patch_path=''
fi

# Trimmed text cut to its first or last $n code points, as a JSON string.
EXCERPT_PROGRAM='
  (sub("\\A\\s+"; "") | sub("\\s+\\z"; "")) as $t
  | if ($t | length) <= $n then $t
    elif $from_end then "..." + $t[-($n - 3):]
    else $t[:$n]
    end
  | tojson'

case "$run_status" in
  0) ;;
  124|137) skip_review 'timed-out' ;;
  126|127) skip_review 'tool-missing' ;;
  *)
    excerpt_source="$work_dir/stderr"
    if ! grep -q '[^[:space:]]' "$work_dir/stderr" 2>/dev/null; then
      excerpt_source="$work_dir/stdout"
    fi
    stderr_excerpt="$(jq -R -s -r --argjson n 300 --argjson from_end true "$EXCERPT_PROGRAM" <"$excerpt_source" 2>/dev/null)" || stderr_excerpt='""'
    skip_review 'tool-failed' "stderr_excerpt: $stderr_excerpt"
    ;;
esac

# shape_blocker: the unexpected output shape blocker with the first 200 code points of stdout.
shape_blocker() {
  local raw_excerpt
  raw_excerpt="$(jq -R -s -r --argjson n 200 --argjson from_end false "$EXCERPT_PROGRAM" <"$work_dir/stdout" 2>/dev/null)" || raw_excerpt='""'
  blocker 'unexpected output shape' "raw_excerpt: $raw_excerpt"
}

# The JSON text that one acceptance rule ($rule: whole, fence or span) takes from a trimmed
# reviewer reply; an error when the reply holds no such text.
# INVARIANT: regex and split only, never a slice at a string index/rindex result (jq 1.6
# returns byte offsets there), so a non-ASCII reply is cut at the right code point.
CANDIDATE_PROGRAM='
  (sub("\\A\\s+"; "") | sub("\\s+\\z"; "")) as $t
  | if $rule == "whole" then $t
    elif $rule == "fence" then
      ($t | split("```")) as $parts
      | if ($parts | length) == 3 and ($parts[1] | test("\\A(json)?[ \\t]*\\n"))
        then $parts[1] | sub("\\A(json)?[ \\t]*\\n"; "")
        else error("not one fenced block")
        end
    else
      ([$t | capture("\\A(?<before>[^{]*)(?<span>\\{[\\s\\S]*\\})(?<after>[^}]*)\\z")] | .[0]) as $match
      | if $match == null or ($match.before + $match.after | test("[\\[\\]{}]"))
        then error("no bracket-free brace span")
        else $match.span
        end
    end'

ONE_OBJECT_CHECK='length == 1 and (.[0] | type) == "object"'

# extract_review <reply file>: write the review object that the first matching acceptance rule
# takes from <reply file> to $work_dir/review.json; returns non-zero when no rule yields exactly
# one JSON object.
extract_review() {
  local reply_path="$1" rule
  for rule in whole fence span; do
    jq -R -s -j --arg rule "$rule" "$CANDIDATE_PROGRAM" <"$reply_path" >"$work_dir/candidate.json" 2>/dev/null || continue
    jq -s -e "$ONE_OBJECT_CHECK" <"$work_dir/candidate.json" >/dev/null 2>&1 || continue
    jq -c '.' <"$work_dir/candidate.json" >"$work_dir/review.json" 2>/dev/null || return 1
    return 0
  done
  return 1
}

if [ "$reviewer_mode" = 'preset' ]; then
  jq -s -e "$ONE_OBJECT_CHECK" <"$work_dir/stdout" >/dev/null 2>&1 || shape_blocker
  if jq -e '.result | type == "object"' <"$work_dir/stdout" >/dev/null 2>&1; then
    jq -c '.result' <"$work_dir/stdout" >"$work_dir/review.json" 2>/dev/null || shape_blocker
  else
    jq -e '.rawOutput | type == "string"' <"$work_dir/stdout" >/dev/null 2>&1 || shape_blocker
    jq -j '.rawOutput' <"$work_dir/stdout" >"$work_dir/raw-output.txt" 2>/dev/null || shape_blocker
    extract_review "$work_dir/raw-output.txt" || shape_blocker
  fi
else
  extract_review "$work_dir/stdout" || shape_blocker
fi

# review-output.schema.json, as one predicate.
SCHEMA_CHECK='
  def nonempty_string: type == "string" and length >= 1;
  def line_number: type == "number" and . == floor and . >= 1;
  def finding_ok:
    type == "object"
    and (keys == ["body", "confidence", "file", "line_end", "line_start", "recommendation", "severity", "title"])
    and (.severity as $s | ["critical", "high", "medium", "low"] | any(. == $s))
    and (.title | nonempty_string)
    and (.body | nonempty_string)
    and (.file | nonempty_string)
    and (.line_start | line_number)
    and (.line_end | line_number)
    and .line_end >= .line_start
    and (.confidence | type == "number" and . >= 0 and . <= 1)
    and (.recommendation | type == "string");
  try (
    type == "object"
    and (keys == ["findings", "next_steps", "summary", "verdict"])
    and (.verdict == "approve" or .verdict == "needs-attention")
    and (.summary | nonempty_string)
    and (.findings | type == "array" and all(.[]; finding_ok))
    and (.next_steps | type == "array" and all(.[]; nonempty_string))
  ) catch false'

jq -e "$SCHEMA_CHECK" <"$work_dir/review.json" >/dev/null 2>&1 || blocker 'output does not match schema'

# Keeps the findings whose file is a changed new-side path; counts the rest.
FILTER_PROGRAM='
  ($changed | split("\u0000") | map(select(length > 0))) as $paths
  | .findings as $all
  | .findings = [$all[] | select(.file as $f | any($paths[]; . == $f))]
  | .dropped_outside_diff = (($all | length) - (.findings | length))'

jq -c --rawfile changed "$work_dir/changed.nul" "$FILTER_PROGRAM" <"$work_dir/review.json" >"$work_dir/kept.json" 2>/dev/null \
  || blocker 'output does not match schema'

finding_count="$(jq -r '.findings | length' <"$work_dir/kept.json" 2>/dev/null)" || blocker 'cannot compute a finding id'
: >"$work_dir/ids.txt"
index=0
while [ "$index" -lt "$finding_count" ]; do
  digest_line="$(jq -j --argjson i "$index" '.findings[$i] | [.file, .line_start, .line_end, .title] | tojson' \
    <"$work_dir/kept.json" | "${sha_cmd[@]}")" || blocker 'cannot compute a finding id'
  digest="${digest_line%% *}"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || blocker 'cannot compute a finding id'
  printf '%s\n' "$digest" >>"$work_dir/ids.txt" || blocker 'cannot compute a finding id'
  index=$((index + 1))
done

RESULT_PROGRAM='
  ($ids | split("\n") | map(select(length > 0))) as $id_list
  | {
      base: $base,
      verdict: .verdict,
      summary: .summary,
      findings: [.findings | to_entries[] | {finding_id: $id_list[.key]} + .value],
      next_steps: .next_steps,
      dropped_outside_diff: .dropped_outside_diff
    }'

result_json="$(jq -c --arg base "$base" --rawfile ids "$work_dir/ids.txt" "$RESULT_PROGRAM" <"$work_dir/kept.json" 2>/dev/null)" \
  || blocker 'cannot compute a finding id'
printf '%s\n' "$result_json"
exit 0
