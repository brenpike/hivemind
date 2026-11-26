#!/usr/bin/env bash
#
# Behavioral runner for the guide skill's engine script:
#   plugin/skills/idea-to-ready/scripts/idea-to-ready.sh
#
# OFFLINE git/jq/bash TEST — needs only bash, git and jq (NO network / auth / real gh). Each case
# runs the real script in a scratch clone of a scratch bare remote. Every remote is built from
# commits made with plumbing only (hash-object, update-index --index-info, write-tree,
# commit-tree), so each tree entry mode is exact (100644, 120000 symlink, 160000 gitlink), then
# pushed to a bare repository the clone names as `origin`; the script's own fetches read from it.
# A recording `gh` stub first on PATH logs each gh argv, copies each --body-file it is given, and
# serves the case's routes from tests/idea-to-ready/gh-routes.json; an unrouted call exits 1. A
# recording `git` wrapper beside it logs each git argv. The suite fails when any gh argv of any
# case holds `readiness:ready`, so the script never writes that label.
#
# Fixture data lives in tests/idea-to-ready/cases.json and gh-routes.json;
# tests/idea-to-ready/README.md describes their layout. Mirrors tools/test_stage_derivation.sh's
# pass/fail counter: exit 1 on any failure, exit 2 on set-up failure, scratch dir removed on EXIT.
# Read-only: the only writes are in the scratch dir.
#
# Usage:
#   ./tools/test_idea_to_ready.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/scratch.sh
. "$SCRIPT_DIR/lib/scratch.sh" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ENGINE="$REPO_ROOT/plugin/skills/idea-to-ready/scripts/idea-to-ready.sh"
RC_LIB="$REPO_ROOT/plugin/skills/_shared/readiness-check.sh"
RV_LIB="$REPO_ROOT/plugin/skills/_shared/record-verify.sh"
SD_LIB="$REPO_ROOT/plugin/skills/_shared/stage-derivation.sh"
CASES="$REPO_ROOT/tests/idea-to-ready/cases.json"
ROUTES="$REPO_ROOT/tests/idea-to-ready/gh-routes.json"

for required_file in "$ENGINE" "$RC_LIB" "$RV_LIB" "$SD_LIB" "$CASES" "$ROUTES"; do
  [ -f "$required_file" ] || { echo "FAIL: file under test missing: $required_file" >&2; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required to run this suite" >&2; exit 2; }
REAL_GIT="$(command -v git)" || { echo "FAIL: git is required to run this suite" >&2; exit 2; }

make_scratch_dir TMPDIR_TEST
trap 'rm -rf "$TMPDIR_TEST"' EXIT

export HOME="$TMPDIR_TEST/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=guide-test GIT_AUTHOR_EMAIL=guide-test@example.invalid
export GIT_COMMITTER_NAME=guide-test GIT_COMMITTER_EMAIL=guide-test@example.invalid
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
export TMPDIR="$TMPDIR_TEST/tmp"
mkdir -p "$HOME" "$TMPDIR" || { echo "FAIL: cannot create scratch HOME" >&2; exit 2; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
setup_fail() { echo "FAIL: set-up: $1" >&2; exit 2; }

jq -e 'type == "object" and (keys == ["cases", "docs", "scenarios"])
  and all(.cases[]; (.name | type) == "string" and (.scenario | type) == "string"
    and (.args | type) == "array" and (.routes | type) == "array" and (.expect | type) == "object"
    and (keys - ["args", "bodies", "clone", "compare", "compare_tail", "cwd", "detach", "dirty", "expect",
                 "gh_has", "gh_lacks", "inputs", "name", "no_gh", "no_git", "request", "routes", "scenario",
                 "stdout_lacks", "symlinks"] == []))' "$CASES" >/dev/null 2>&1 \
  || setup_fail "cases file missing or off its shape: $CASES"
jq -e '.routes | type == "object" and all(.[]; (.args | type) == "array" and (has("json") or has("raw")))' \
  "$ROUTES" >/dev/null 2>&1 || setup_fail "routes file missing or off its shape: $ROUTES"

# ── Recording wrappers ───────────────────────────────────────────────────────────────

WRAP_DIR="$TMPDIR_TEST/wrap-bin"
ALL_GH_LOG="$TMPDIR_TEST/all-gh.log"
mkdir -p "$WRAP_DIR" || setup_fail "cannot create the wrapper dir"
: >"$ALL_GH_LOG" || setup_fail "cannot create the gh log"
printf '%s\n' '#!/bin/sh' \
  'printf "%s\n" "$*" >>"$IR_TEST_GIT_LOG"' \
  'exec "$IR_TEST_REAL_GIT" "$@"' >"$WRAP_DIR/git" \
  && chmod +x "$WRAP_DIR/git" || setup_fail "cannot write the recording git wrapper"
# The gh stub logs its argv as one line of <arg> fields, copies the file after each --body-file to
# $IR_TEST_BODY_DIR/<n>, then serves the first route of $IR_TEST_GH_ROUTES whose args all match:
# an arg pattern starting `^` matches by prefix, `*` by substring, any other exactly.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'key="$(printf "<%s>" "$@")"' \
  'printf "%s\n" "$key" >>"$IR_TEST_GH_LOG"' \
  'printf "%s\n" "$key" >>"$IR_TEST_ALL_GH_LOG"' \
  'previous=""' \
  'for arg in "$@"; do' \
  '  if [ "$previous" = --body-file ]; then' \
  '    count="$(ls "$IR_TEST_BODY_DIR" | wc -l)"' \
  '    cp -- "$arg" "$IR_TEST_BODY_DIR/$((count + 1))" || exit 3' \
  '  fi' \
  '  previous="$arg"' \
  'done' \
  'argv="$(printf "%s\n" "$@" | jq -R . | jq -sc .)" || exit 4' \
  'route="$(jq -c --argjson argv "$argv" '"'"'first(.[] | select((.args | length) == ($argv | length)
    and ([range(0; $argv | length) as $i | .args[$i] as $p | $argv[$i] as $a
          | if ($p | startswith("^")) then ($a | startswith($p[1:]))
            elif ($p | startswith("*")) then ($a | contains($p[1:]))
            else $a == $p end] | all))) // empty'"'"' "$IR_TEST_GH_ROUTES")" || exit 5' \
  '[ -n "$route" ] || exit 1' \
  'printf "%s" "$route" | jq -j '"'"'if has("raw") then .raw else (.json | tojson) + "\n" end'"'"'' \
  'exit "$(printf "%s" "$route" | jq -r '"'"'.rc // 0'"'"')"' >"$WRAP_DIR/gh" \
  && chmod +x "$WRAP_DIR/gh" || setup_fail "cannot write the recording gh stub"

# ── Documents and scenario remotes ───────────────────────────────────────────────────

BUILD="$TMPDIR_TEST/build"
"$REAL_GIT" init -q "$BUILD" || setup_fail "git init build"
bgit() { "$REAL_GIT" -C "$BUILD" "$@"; }

declare -A DOC_TEXT=()
while IFS=$'\t' read -r doc_name encoded; do
  decoded="$(printf '%s' "$encoded" | base64 -d && printf x)" || setup_fail "base64 decode"
  DOC_TEXT[$doc_name]="${decoded%x}"
done < <(jq -r '.docs | to_entries[] | "\(.key)\t\(.value | @base64)"' "$CASES")

GITLINK_BLOB="$(printf 'gitlink target\n' | bgit hash-object -w --stdin)" || setup_fail "gitlink blob"
GITLINK_TREE="$(printf '100644 blob %s\tREADME.md\n' "$GITLINK_BLOB" | bgit mktree)" || setup_fail "gitlink tree"
GITLINK_COMMIT="$(bgit commit-tree "$GITLINK_TREE" -m gitlink </dev/null)" || setup_fail "gitlink commit"
UNFETCHED='0123456789abcdef0123456789abcdef01234567'

declare -A BLOBS=()
declare -A IDS=()

# store_text <var> <bytes>: writes a blob and assigns its id to <var>.
store_text() {
  local blob_id
  blob_id="$(printf '%s' "$2" | bgit hash-object -w --stdin)" || setup_fail "hash-object"
  printf -v "$1" '%s' "$blob_id"
}

# doc_blob <slug> <doc-name>: assigns BLOB the blob id of the named document rendered for <slug>.
doc_blob() {
  local key="$1:$2" text
  if [ -z "${BLOBS[$key]-}" ]; then
    [ -n "${DOC_TEXT[$2]+set}" ] || setup_fail "unknown document $2"
    render_doc text "${DOC_TEXT[$2]}" "$1"
    store_text BLOBS[$key] "$text"
  fi
  BLOB="${BLOBS[$key]}"
}

# render_doc <var> <bytes> <slug>: assigns <bytes> with {{slug}} and {{blob:<doc>}} rendered.
render_doc() {
  local rendered="${2//\{\{slug\}\}/$3}" name
  while [[ "$rendered" =~ \{\{blob:([a-z0-9-]+)\}\} ]]; do
    name="${BASH_REMATCH[1]}"
    doc_blob "$3" "$name"
    rendered="${rendered//"{{blob:$name}}"/$BLOB}"
  done
  printf -v "$1" '%s' "$rendered"
}

# tree_lines <slug> <set-json> <base-lines>: prints the index lines `<mode> <oid>\t<path>` of
# <base-lines> with the set applied, one per path.
tree_lines() {
  local slug="$1" path kind value oid line
  declare -A entries=()
  while IFS= read -r line; do
    [ -n "$line" ] && entries[${line#*$'\t'}]="${line%%$'\t'*}"
  done <<<"$3"
  while IFS=$'\t' read -r path kind value; do
    path="${path//\{\{slug\}\}/$slug}"
    case "$kind" in
      doc) doc_blob "$slug" "$value"; entries[$path]="100644 $BLOB" ;;
      symlink) store_text oid "$value"; entries[$path]="120000 $oid" ;;
      gitlink) entries[$path]="160000 $GITLINK_COMMIT" ;;
      delete) unset "entries[$path]" ;;
      *) setup_fail "unknown entry kind $kind" ;;
    esac
  done < <(printf '%s\n' "$2" | jq -r 'to_entries[] | .key + "\t" + (
      if .value == null then "delete\t-" elif (.value | type) == "string" then "doc\t" + .value
      elif .value.symlink then "symlink\t" + .value.symlink else "gitlink\t-" end)')
  for path in "${!entries[@]}"; do
    printf '%s\t%s\n' "${entries[$path]}" "$path"
  done
}

# commit_lines <var> <lines> [<parent>]: commits the index lines and assigns the commit id.
commit_lines() {
  local index_file="$TMPDIR_TEST/index.build" tree_id commit_id
  local -a parent_args=()
  [ -n "${3-}" ] && parent_args=(-p "$3")
  rm -f "$index_file"
  printf '%s\n' "$2" | GIT_INDEX_FILE="$index_file" bgit update-index --index-info || setup_fail "update-index"
  tree_id="$(GIT_INDEX_FILE="$index_file" bgit write-tree)" || setup_fail "write-tree"
  commit_id="$(bgit commit-tree "$tree_id" "${parent_args[@]}" -m "$1" </dev/null)" || setup_fail "commit-tree"
  printf -v "$1" '%s' "$commit_id"
}

# build_scenario <name>: builds the scenario's commits, pushes them to its bare remote and records
# IDS[<name>:trunk] and IDS[<name>:docs<i>].
build_scenario() {
  local name="$1" slug count index parent set lines bare branch target refspecs=()
  local -a docs_lines=()
  slug="$(jq -r --arg n "$name" '.scenarios[$n].slug' "$CASES")" || setup_fail "scenario $name"
  lines="$(tree_lines "$slug" "$(jq -c --arg n "$name" '.scenarios[$n].trunk' "$CASES")" "")"
  commit_lines trunk_commit "$lines"
  IDS[$name:trunk]="$trunk_commit"
  docs_lines[0]="$lines"
  count="$(jq --arg n "$name" '.scenarios[$n].docs | length' "$CASES")"
  for ((index = 1; index <= count; index++)); do
    parent="$(jq --arg n "$name" --argjson i "$index" '.scenarios[$n].docs[$i - 1].parent' "$CASES")"
    set="$(jq -c --arg n "$name" --argjson i "$index" '.scenarios[$n].docs[$i - 1].set' "$CASES")"
    lines="$(tree_lines "$slug" "$set" "${docs_lines[parent]}")"
    docs_lines[index]="$lines"
    if [ "$parent" -eq 0 ]; then
      commit_lines docs_commit "$lines" "${IDS[$name:trunk]}"
    else
      commit_lines docs_commit "$lines" "${IDS[$name:docs$parent]}"
    fi
    IDS[$name:docs$index]="$docs_commit"
  done
  bare="$TMPDIR_TEST/remotes/$name.git"
  "$REAL_GIT" init -q --bare "$bare" || setup_fail "init bare $name"
  refspecs=("${IDS[$name:trunk]}:refs/heads/main")
  while IFS=$'\t' read -r branch target; do
    refspecs+=("${IDS[$name:docs$target]}:refs/heads/$branch")
  done < <(jq -r --arg n "$name" '.scenarios[$n].branches | to_entries[] | "\(.key)\t\(.value)"' "$CASES")
  bgit push -q "$bare" "${refspecs[@]}" || setup_fail "push $name"
  "$REAL_GIT" -C "$bare" symbolic-ref HEAD refs/heads/main || setup_fail "bare HEAD $name"
}

while IFS= read -r scenario_name; do
  build_scenario "$scenario_name"
done < <(jq -r '.scenarios | keys[]' "$CASES")

# render_ids <var> <bytes> <scenario> <abs>: assigns <bytes> with the placeholders rendered:
# {{trunk}}, {{docs<i>}}, {{upper2}} (docs2 in capitals), {{unfetched}}, {{abs}} (the clone
# path) and {{blob:<doc>}} for the scenario's slug.
render_ids() {
  local __ri_text="$2" __ri_scenario="$3" __ri_key __ri_slug __ri_name
  __ri_slug="$(jq -r --arg n "$__ri_scenario" '.scenarios[$n].slug' "$CASES")"
  for __ri_key in "${!IDS[@]}"; do
    case "$__ri_key" in
      "$__ri_scenario":*) __ri_text="${__ri_text//"{{${__ri_key#*:}}}"/${IDS[$__ri_key]}}" ;;
    esac
  done
  if [ -n "${IDS[$__ri_scenario:docs2]-}" ]; then
    __ri_text="${__ri_text//"{{upper2}}"/$(printf '%s' "${IDS[$__ri_scenario:docs2]}" | tr 'abcdef' 'ABCDEF')}"
  fi
  __ri_text="${__ri_text//"{{unfetched}}"/$UNFETCHED}"
  __ri_text="${__ri_text//"{{abs}}"/$4}"
  while [[ "$__ri_text" =~ \{\{blob:([a-z0-9-]+)\}\} ]]; do
    __ri_name="${BASH_REMATCH[1]}"
    doc_blob "$__ri_slug" "$__ri_name"
    __ri_text="${__ri_text//"{{blob:$__ri_name}}"/$BLOB}"
  done
  printf -v "$1" '%s' "$__ri_text"
}

# ── Case runner ──────────────────────────────────────────────────────────────────────

# case_field <index> <jq-filter>: prints the filter's raw output over case <index>.
case_field() {
  jq -r "$2" "$TMPDIR_TEST/cases/$1/case.json"
}

# case_text <var> <index> <jq-filter>: assigns the filter's raw text over case <index>, ending
# newlines kept, to <var>.
case_text() {
  local __ct_text
  __ct_text="$(jq -j "$3" "$TMPDIR_TEST/cases/$2/case.json" && printf x)" || setup_fail "case text $3"
  printf -v "$1" '%s' "${__ct_text%x}"
}

# library_line <case-dir> <scenario> <mode> <slug>: runs the libraries' evidence read and derive or
# handoff directly, in a clone holding every branch, with the case's routes; prints its output.
library_line() {
  local dir="$1/full"
  "$REAL_GIT" clone -q --no-local "$TMPDIR_TEST/remotes/$2.git" "$dir" || setup_fail "full clone"
  (
    cd "$dir" || exit 97
    PATH="$WRAP_DIR:$PATH" IR_TEST_GIT_LOG="$1/lib-git.log" IR_TEST_REAL_GIT="$REAL_GIT" \
      IR_TEST_GH_LOG="$1/lib-gh.log" IR_TEST_ALL_GH_LOG="$ALL_GH_LOG" IR_TEST_BODY_DIR="$1/lib-bodies" \
      IR_TEST_GH_ROUTES="$1/routes.json" bash -c '
        set -euo pipefail
        . "$1"; . "$2"; . "$3"
        evidence="$(hivemind_stage_evidence_gh acme/widgets "$6")"
        if [ "$5" = derive ]; then
          printf "%s\n" "$evidence" | hivemind_stage_derive "$4" acme/widgets main "$6"
        else
          printf "%s\n" "$evidence" | hivemind_stage_handoff "$4" acme/widgets main "$6"
        fi' library "$RC_LIB" "$RV_LIB" "$SD_LIB" "${IDS[$2:trunk]}" "$3" "$4"
  )
}

# run_case <index>: sets up case <index>'s clone, routes and inputs, runs the engine and asserts.
run_case() {
  local index="$1" name scenario dir clone detach cwd routes_text rendered want got line slug
  local rc=0 compare tail expected count body_index body_count want_body arg library_want="" text
  local -a args=() raw_args=()
  mkdir -p "$TMPDIR_TEST/cases/$index" || setup_fail "case dir $index"
  jq -c --argjson i "$index" '.cases[$i]' "$CASES" >"$TMPDIR_TEST/cases/$index/case.json" \
    || setup_fail "case $index"
  name="$(case_field "$index" .name)"
  scenario="$(case_field "$index" .scenario)"
  slug="$(jq -r --arg n "$scenario" '.scenarios[$n].slug' "$CASES")"
  dir="$TMPDIR_TEST/cases/$index"
  mkdir -p "$dir/bodies" "$dir/lib-bodies" || setup_fail "case dir $name"
  : >"$dir/gh.log"
  : >"$dir/git.log"
  clone="$(case_field "$index" '.clone // ""')"
  if [ -z "$clone" ]; then
    "$REAL_GIT" clone -q --no-local --single-branch --branch main "$TMPDIR_TEST/remotes/$scenario.git" "$dir/clone" \
      || setup_fail "clone $name"
  else
    "$REAL_GIT" clone -q --no-local --branch "$clone" "$TMPDIR_TEST/remotes/$scenario.git" "$dir/clone" \
      || setup_fail "clone $name"
  fi
  detach="$(case_field "$index" '.detach // ""')"
  if [ -n "$detach" ]; then
    render_ids detach "$detach" "$scenario" "$dir/clone"
    "$REAL_GIT" -C "$dir/clone" checkout -q --detach "$detach" || setup_fail "detach $name"
  fi
  if [ "$(case_field "$index" '.dirty // false')" = true ]; then
    printf 'scratch\n' >"$dir/clone/untracked.txt" || setup_fail "dirty $name"
  fi
  while IFS=$'\t' read -r line encoded; do
    [ -n "$line" ] || continue
    mkdir -p "$(dirname "$dir/clone/$line")" || setup_fail "inputs dir $name"
    printf '%s' "$encoded" | base64 -d >"$dir/clone/$line" || setup_fail "inputs $name"
  done < <(case_field "$index" '(.inputs // {}) | to_entries[]
    | "\(.key)\t\(if (.value | type) == "string" then (.value | @base64) else .value.base64 end)"')
  while IFS=$'\t' read -r line encoded; do
    [ -n "$line" ] || continue
    mkdir -p "$(dirname "$dir/clone/$line")" || setup_fail "symlink dir $name"
    ln -s "$encoded" "$dir/clone/$line" || setup_fail "symlink $name"
  done < <(case_field "$index" '(.symlinks // {}) | to_entries[] | "\(.key)\t\(.value)"')
  cwd="$(case_field "$index" '.cwd // ""')"
  if [ -n "$cwd" ]; then
    mkdir -p "$dir/clone/$cwd" || setup_fail "cwd $name"
  fi
  routes_text="$(jq -c --argjson i "$index" --slurpfile r "$ROUTES" \
    '[.cases[$i].routes[] as $n | $r[0].routes[$n] // error("unknown route \($n)")]' "$CASES")" \
    || setup_fail "routes of $name"
  render_ids rendered "$routes_text" "$scenario" "$dir/clone"
  printf '%s\n' "$rendered" >"$dir/routes.json" || setup_fail "routes file $name"
  mapfile -t raw_args < <(case_field "$index" '.args[]')
  for arg in "${raw_args[@]}"; do
    render_ids rendered "$arg" "$scenario" "$dir/clone"
    args+=("$rendered")
  done

  compare="$(case_field "$index" '.compare // ""')"
  if [ -n "$compare" ]; then
    library_want="$(library_line "$dir" "$scenario" "$compare" "$slug")" || setup_fail "library call of $name"
  fi

  (
    cd "$dir/clone/$cwd" || exit 97
    PATH="$WRAP_DIR:$PATH" IR_TEST_GIT_LOG="$dir/git.log" IR_TEST_REAL_GIT="$REAL_GIT" \
      IR_TEST_GH_LOG="$dir/gh.log" IR_TEST_ALL_GH_LOG="$ALL_GH_LOG" IR_TEST_BODY_DIR="$dir/bodies" \
      IR_TEST_GH_ROUTES="$dir/routes.json" bash "$ENGINE" "${args[@]}"
  ) >"$dir/out" 2>"$dir/err" || rc=$?

  want="$(case_field "$index" '.expect.rc')"
  if [ "$rc" != "$want" ]; then
    failed "$name" "rc $rc, want $want (stdout: $(head -c 400 "$dir/out"); stderr: $(head -c 400 "$dir/err"))"
    return 0
  fi
  if [ -n "$compare" ]; then
    case_text tail "$index" '.compare_tail // ""'
    expected="$library_want"$'\n'"$tail"
    if [ "$(cat "$dir/out"; printf x)" = "${expected}x" ]; then
      pass "$name:library" "stdout equals the libraries' own line"
    else
      failed "$name:library" "stdout: $(cat "$dir/out") want: $expected"
    fi
  fi
  for line in stdout stderr; do
    if [ "$(case_field "$index" ".expect | has(\"$line\")")" = true ]; then
      case_text text "$index" ".expect.$line"
      render_ids want "$text" "$scenario" "$dir/clone"
      if [ "$line" = stdout ]; then got="$dir/out"; else got="$dir/err"; fi
      if [ "$(cat "$got"; printf x)" = "${want}x" ]; then
        pass "$name:$line" "exact"
      else
        failed "$name:$line" "got: $(cat "$got") want: $want"
      fi
    fi
  done
  while IFS= read -r want; do
    [ -n "$want" ] || continue
    if grep -qF -- "$want" "$dir/out"; then pass "$name:has" "$want"; else failed "$name:has" "stdout lacks $want"; fi
  done < <(case_field "$index" '(.expect.stdout_has // [])[]')
  while IFS= read -r want; do
    [ -n "$want" ] || continue
    if grep -qF -- "$want" "$dir/out"; then failed "$name:lacks" "stdout holds $want"; else pass "$name:lacks" "$want"; fi
  done < <(case_field "$index" '(.stdout_lacks // [])[]')
  while IFS= read -r want; do
    [ -n "$want" ] || continue
    render_ids want "$want" "$scenario" "$dir/clone"
    if grep -qF -- "$want" "$dir/gh.log"; then pass "$name:gh-has" "$want"; else failed "$name:gh-has" "no gh call holds $want"; fi
  done < <(case_field "$index" '(.gh_has // [])[]')
  while IFS= read -r want; do
    [ -n "$want" ] || continue
    if grep -qF -- "$want" "$dir/gh.log"; then failed "$name:gh-lacks" "a gh call holds $want"; else pass "$name:gh-lacks" "$want"; fi
  done < <(case_field "$index" '(.gh_lacks // [])[]')
  if [ "$(case_field "$index" '.no_gh // false')" = true ]; then
    if [ -s "$dir/gh.log" ]; then failed "$name:no-gh" "gh ran: $(head -n 1 "$dir/gh.log")"; else pass "$name:no-gh" "no gh call"; fi
  fi
  if [ "$(case_field "$index" '.no_git // false')" = true ]; then
    if [ -s "$dir/git.log" ]; then failed "$name:no-git" "git ran: $(head -n 1 "$dir/git.log")"; else pass "$name:no-git" "no git call"; fi
  elif [ -s "$dir/git.log" ]; then
    if grep -qv -e '^--no-replace-objects ' -e '^--no-optional-locks --no-replace-objects ' \
      -e '^-C [^ ]* --no-replace-objects ' "$dir/git.log"; then
      failed "$name:git-flags" "a git call lacks --no-replace-objects: $(grep -v -e '--no-replace-objects' "$dir/git.log" | head -n 1)"
    else
      pass "$name:git-flags" "every git call carries --no-replace-objects"
    fi
  fi
  body_count="$(case_field "$index" '(.bodies // []) | length')"
  if [ "$body_count" -gt 0 ]; then
    count="$(find "$dir/bodies" -type f | wc -l)"
    if [ "$count" -ne "$body_count" ]; then
      failed "$name:bodies" "$count body files posted, want $body_count"
    fi
    for ((body_index = 0; body_index < body_count; body_index++)); do
      case_text text "$index" ".bodies[$body_index]"
      render_ids want_body "$text" "$scenario" "$dir/clone"
      if [ -f "$dir/bodies/$((body_index + 1))" ] \
        && [ "$(cat "$dir/bodies/$((body_index + 1))"; printf x)" = "${want_body}x" ]; then
        pass "$name:body" "posted body $((body_index + 1)) exact"
      else
        failed "$name:body" "posted body $((body_index + 1)): $(cat "$dir/bodies/$((body_index + 1))" 2>/dev/null)"
      fi
    done
  fi
  if [ "$(case_field "$index" '.request // false')" = true ]; then
    check_request "$name" "$slug" "$dir/out"
  fi
}

# check_request <case> <slug> <file>: asserts the guide request layout: line 1 is the marker line,
# line 2 the one `Docs pull request:` line, and no other line holds that text or comment prose.
check_request() {
  local first second count
  first="$(sed -n 1p "$3")"
  second="$(sed -n 2p "$3")"
  count="$(grep -c 'Docs pull request:' "$3")"
  if [ "$first" = "hivemind-guide-run: $2" ] && [[ "$second" =~ ^Docs\ pull\ request:\ (none|#[1-9][0-9]*)$ ]] \
    && [ "$count" -eq 1 ] && ! grep -q -e 'findings\.$' -e 'Ignore' "$3"; then
    pass "$1:request" "marker line, one Docs pull request line, no comment text"
  else
    failed "$1:request" "layout: $(head -n 3 "$3")"
  fi
}

# test_cases: runs every case of cases.json.
test_cases() {
  local count index
  count="$(jq '.cases | length' "$CASES")" || setup_fail "cannot count cases"
  for ((index = 0; index < count; index++)); do
    run_case "$index"
  done
}

# test_no_ready_label: asserts no gh argv of any case or library call holds readiness:ready.
test_no_ready_label() {
  if grep -q 'readiness:ready' "$ALL_GH_LOG"; then
    failed "no-ready-label" "a gh call holds readiness:ready: $(grep 'readiness:ready' "$ALL_GH_LOG" | head -n 1)"
  elif [ ! -s "$ALL_GH_LOG" ]; then
    failed "no-ready-label" "no gh call was logged"
  else
    pass "no-ready-label" "$(wc -l <"$ALL_GH_LOG") gh calls, none holds readiness:ready"
  fi
  if grep -q -e '<label>' -e '--add-label' -e '/labels' "$ALL_GH_LOG"; then
    failed "no-label-write" "a gh call writes a label"
  else
    pass "no-label-write" "no gh call writes a label"
  fi
}

test_cases
test_no_ready_label

echo ""
echo "test_idea_to_ready: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
exit 0
