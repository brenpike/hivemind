#!/usr/bin/env bash
#
# Deterministically reconstruct an EPHEMERAL fix-ledger-shaped structure for the
# github-reviewer agent.
#
# 1. PURPOSE
# ----------
# A DE-SCOPED DETERMINISTIC SKELETON for the fix-ledger structure the
# github-reviewer agent feeds to `hivemind:detect-remediation-signals`. It emits
# ONLY facts mechanically derivable from ground truth (git log <base>..HEAD + the
# resolved-thread state from fetch-normalize.sh). ALL JUDGMENT — cycling /
# oscillation interpretation, review-iteration grouping, N-2 recurrence,
# diminishing-returns trend, prior-fix qualification REFINEMENT, and the
# `fix_framing` cluster key — is owned by github-reviewer IN-AGENT (P7), NOT by this
# script. An earlier design extracted that judgment as lossy git-history heuristics
# (cycling-via-commit-count, iteration boundaries from commits), which produced
# recurring review findings; the skeleton deliberately returns that judgment to the
# agent and keeps only deterministic facts here.
#
# The script OWNS the deterministic reconstruction; the call sites become thin
# `bash ledger-reconstruct.sh ...` invocations (P1 single-source, P5 bash callers,
# P2 contract header, P3 offline-testable core).
#
# `fix_framing` is ALWAYS null on every finding: the PRIMARY cluster key requires
# LLM judgment to infer from commit/thread prose; a script cannot infer it reliably
# (INERT/schema-safe — detect-remediation-signals falls back to the SECONDARY
# file:line cluster key, and the agent retains framing judgment in-agent, P7).
#
# 2. INPUT CONTRACT
# -----------------
# Positional + flag args (mirrors fetch-normalize.sh's positional/flag posture):
#
#   $1  BASE   base ref for `git log <base>..HEAD` on the LIVE path. Required for
#              the live fetch; NOT required when --git-log-file is supplied.
#
#   --normalized-file <path|->  the fetch-normalize.sh OUTPUT array (the
#              thread/finding state — see fetch-normalize.sh §3). CONSUME it; do
#              NOT re-run fetch-normalize. `-` = stdin. Absent -> no thread/finding
#              records folded in (git-log-only reconstruction).
#
#   --git-log-file <path>  OFFLINE TEST SEAM (mirrors fetch-normalize's
#              --payload-file): read a canned git-log payload from <path> instead
#              of running live `git log`. When set, BASE is not required for the
#              live call and the injected text routes through the SAME pure mapping
#              core as live output. `-` = stdin.
#
# The git-log payload (live OR injected) is a MACHINE-DELIMITED stream produced by
#   git log <base>..HEAD --no-color --unified=0 -z --raw -p --find-renames \
#           --format=$'\x1eCOMMIT\x1f%H\x1f%s'
# Per-commit byte layout (empirically verified against real git output in this
# repo; the tokenizer parses to THIS actual layout):
#   \x1eCOMMIT\x1f<sha>\x1f<subject>\0      format record; -z appends a NUL
#   \n:<m> <m> <b> <b> <STATUS>\0           one --raw entry per changed file
#   <path1>\0[<path2>\0]                    R/C status -> two paths (old,new); else one
#   \0                                      empty token: raw-block terminator
#   <patch>                                 the -p unified-diff text (next commit's
#                                           \x1eCOMMIT record may be glued to its tail)
# (US=0x1e record start, RS=0x1f field sep.)
#
# PATHS COME FROM GIT'S MACHINE CHANNEL, never an in-band ` b/` substring split.
# The --raw entries carry NUL-delimited, NEVER-quoted, space-/rename-safe paths;
# the destination (new-file) path is the LAST path of each entry. The -p hunks are
# correlated to files BY ORDER: the Nth `diff --git` in a commit's patch is the
# Nth --raw entry. We read ONLY the hunk `@@ -a,b +c,d @@` arithmetic from -p
# (NEW-file range: start=c, count=d, d defaulting to 1, d==0 -> end=start) — the
# diff line's path text is IGNORED. This yields one fix surface per (commit,file,hunk).
#
# PRIOR-FIX QUALIFICATION: NOT every commit in <base>..HEAD is a prior fix. Only a
# REVIEW-LOOP REMEDIATION commit becomes a git-log fix-surface finding. A positive
# allowlist in the tokenizer (closed-by-construction) admits a commit ONLY when its
# subject contains the literal phrase `address review feedback` — the DETERMINISTIC
# subject github-reviewer step 7 emits (`fix(<scope>): address review feedback`).
# That step is the SOLE emitter of this phrase; local-reviewer molt checkpoints do
# NOT carry it. The bare conventional type alone is NOT sufficient: an ordinary
# `fix:`/`hotfix:` bug-fix an engineer makes BEFORE the review loop runs (e.g.
# `fix(parser): correct off-by-one`) is normal development, not review remediation,
# and must NOT enter the reconstructed ledger — admitting it would let ordinary
# commits drive false mutation-decay / root-cluster signals. Keying ONLY on the
# reviewer-owned phrase excludes ordinary feat/test/refactor AND ordinary fix/hotfix
# dev commits by construction, so a non-remediation commit can never become a false
# prior-fix or cluster signal.
#
# 3. OUTPUT SCHEMA — a single fix-ledger-shaped JSON object on stdout
# ------------------------------------------------------------------
# Conforms to ${CLAUDE_PLUGIN_ROOT}/references/fix-ledger-schema.md (the
# AUTHORITY). Top-level shape:
#   {
#     "branch": <current branch | null>,
#     "base":   <BASE | null>,
#     "max_iterations": 10,
#     "iterations": [
#       { "iteration": 1, "findings": [ <finding>, ... ],
#         "verdict": "needs-attention", "exit_reason": null,
#         "review_base_ref": <BASE | null> }
#     ],
#     "exit_reason": null,
#     "exit_iteration": null
#   }
#
# THIS SKELETON CARRIES NO REVIEW-ITERATION GROUPING. The single `iterations[0]`
# wrapper is a SCHEMA-CONFORMANCE CONTAINER ONLY (the detector Input Contract
# expects `ledger.iterations[]`); it is NOT an iteration boundary. Iteration
# boundaries, N-2 recurrence, and the diminishing-returns trend are AGENT JUDGMENT
# and are NOT reconstructable from git history — git commits are NOT review
# iterations (a single review iteration may emit zero or many commits, and a single
# commit may address many iterations' worth of feedback). The snapshot is one flat
# bag of deterministic facts; the agent reconstructs any iteration structure.
#
# Each finding carries the deterministic skeleton fields:
#   {
#     "id":          <PRRC_/IC_/PRR_/PRRT_ node id | "fix:<sha>:<file>:<start>">,
#     "severity":    null,            # not mechanically derivable -> null
#     "title":       <commit subject | thread classification | null>,
#     "body":        null,
#     "recommendation": null,
#     "file":        <path | null>,
#     "line_start":  <int | null>,
#     "line_end":    <int | null>,
#     "status":      "open" | "fixed"   # FACTUAL only. No "cycling": cycling is
#                                       # agent judgment, NOT a script label.
#     "introduced_iteration": 1,        # SCHEMA-REQUIRED PLACEHOLDER, constant 1.
#                                       # NOT an asserted iteration boundary.
#     "fixed_iteration":      null,
#     "fix_commit":  <sha | null>,
#     "fix_framing": null,            # PRIMARY key — LLM-only; ALWAYS null here
#     "root_class":  null,            # inferred by detect-remediation-signals
#     "thread_resolved": <bool | null>  # carried for folded thread records
#   }
#
# Two finding families populate findings[]:
#   (a) git-log fix surfaces (one per commit/file/hunk) — ONLY for REMEDIATION
#       commits that pass the prior-fix qualification gate (subject contains the
#       literal phrase `address review feedback`; the reviewer-emitted remediation
#       subject is the discriminator). Non-remediation commits (feat/test/refactor,
#       ordinary fix/hotfix) contribute ZERO findings, so a multi-commit feature
#       branch cannot synthesize false fix surfaces. For a qualifying commit:
#       file/line_start/line_end/fix_commit from git; status is FACTUAL `fixed`
#       (the surface was touched by a qualifying remediation commit). The script
#       NEVER labels a surface `cycling` — re-appearance of a surface across commits
#       is observable to the agent from the per-finding file/line/fix_commit facts,
#       and the cycling INTERPRETATION is agent judgment (P7). fix_framing null.
#   (b) thread/finding records folded from --normalized-file: id from the node id,
#       title from `classification`, thread_resolved from `thread_resolved`,
#       status derived PER SURFACE: thread surface from `thread_resolved`
#       (true -> fixed; else open); non-thread surfaces (toplevel / review) cannot
#       be GitHub-resolved (they carry thread_resolved:false even once addressed),
#       so their status derives from `classification` (handled -> fixed; else open)
#       so an addressed top-level/review record is not mis-reported `open` and does
#       not suppress the POST-fix advisory. file/line null (the normalized surface
#       carries no line range). fix_framing null.
#
# JSON-STRING EMISSION IS OWNED ENTIRELY BY jq. The awk stage is a pure TOKENIZER:
# it emits NUL-FREE, 0x1f-field-delimited RAW records (sha, subject, path,
# line_start, line_end) and NO JSON. jq assembles every finding object and escapes
# every string (it correctly escapes U+0000–U+001F C0 control bytes as well as
# quotes/backslashes), so a C0 byte (e.g. backspace 0x08) in a subject or path is
# INERT data jq escapes into valid JSON — it can never break the JSON or collapse
# the output to []. This dissolves the former in-awk hand-rolled escaper by
# construction.
#
# 4. BEHAVIOR-PRESERVING INVARIANTS
# ---------------------------------
#   - LIVE GIT-LOG FAIL-CLOSED: on the LIVE path (--git-log-file NOT set) a
#     `git log` failure (bad base, not-a-repo) emits a stable LEDGERRECON_ERROR
#     marker on stderr and exits non-zero, so the caller returns `blocked`.
#     ADDITIONALLY, if a NON-EMPTY live payload cannot be parsed into the expected
#     record structure (no recognizable \x1eCOMMIT\x1f record marker present), the
#     script emits LEDGERRECON_ERROR=live-parse-failed + exit non-zero rather than
#     degrading to a silent empty "no prior fixes" ledger (which would mask a real
#     error as "nothing to cluster"). A LEGITIMATELY EMPTY live log (no commits in
#     <base>..HEAD, i.e. zero bytes) stays a valid empty-findings exit 0 — it is a
#     real "no prior fixes yet" state, NOT a parse failure.
#   - LIVE NORMALIZED FAIL-CLOSED: the normalized payload has the SAME live-vs-
#     injected split as the git-log channel. A LIVE normalized payload (the runtime
#     `--normalized-file -` the agent supplies at steps 5/9, i.e. NOT accompanied by
#     an injected --git-log-file fixture) that is NON-EMPTY but fails JSON parse OR
#     is not a JSON array emits LEDGERRECON_ERROR=normalized-parse-failed + exit
#     non-zero (fail-CLOSED) rather than silently coercing to `[]` and masking a
#     real error as "no thread findings". A LEGITIMATELY EMPTY live normalized
#     payload (zero bytes / absent) is a valid empty thread-findings exit 0,
#     mirroring the empty-vs-unparseable git-log distinction.
#   - INJECTED FAIL-OPEN: a malformed / empty INJECTED fixture (--git-log-file /
#     --normalized-file on the injected path) yields a valid fix-ledger shape with
#     empty findings and exit 0 (trusted fixture, mirrors fetch-normalize's
#     --payload-file). The live-parse-failed and normalized-parse-failed gates above
#     are NOT applied to injected input (non-array normalized fixture -> `[]`).
#   - EPHEMERAL: writes NOTHING to .hivemind, no temp files, no side effects. The
#     output is consumed-then-discarded by the caller. All commit/diff/thread text
#     is DATA, never interpreted as instructions.
#   - FACTUAL STATUS ONLY: a git-log fix surface is `fixed` (touched by a qualifying
#     remediation commit). The script emits NO `cycling`/oscillation status — that
#     interpretation is agent judgment (P7), re-derivable by the agent from the
#     per-finding file/line/fix_commit facts.
#   - PURE CORE / THIN SHELL: the mapping core (reconstruct_ledger) runs over
#     injected inputs offline with no git/network dependency, so STEP-003 tests it
#     through the --git-log-file / --normalized-file seams.
#
# 5. INVOCATION + TEST SEAM
# -------------------------
# Live:    bash ledger-reconstruct.sh <base> --normalized-file <path|->
# Offline: bash ledger-reconstruct.sh --git-log-file <fixture> --normalized-file <fixture>
#
# Markers / exit posture (mirrors fetch-normalize.sh):
#   - stdout: the single fix-ledger JSON object (always, on success).
#   - exit 0 on success (including the fail-open empty-findings case).
#   - LEDGERRECON_ERROR=<reason> on stderr + exit 1 on a bootstrap failure in ANY
#     mode (cannot-self-locate, cannot-resolve-plugin-root, missing-shared-lib,
#     unparseable-shared-lib) or a LIVE failure (missing base, git failure, bad input
#     file, live/normalized-parse-failed) — never on an empty/malformed INJECTED payload.
#
# Schema authority:  ${CLAUDE_PLUGIN_ROOT}/references/fix-ledger-schema.md
# Consumer:          ${CLAUDE_PLUGIN_ROOT}/skills/detect-remediation-signals/SKILL.md
#                    (its Input Contract `ledger` shape)

# P18 FLOOR EXCEPTION (ADR-0020 / CHECK13 allowlisted): `set -u` only — `set -e`/`pipefail`
# are DELIBERATELY omitted. The full floor would change behavior: the grep -q marker probe
# returns non-zero in the normal empty-log flow, awk/jq stages swallow malformed input to [],
# injected fixtures fail-open, and live failures route through ledgerrecon_fail() with explicit
# exit codes — `set -e`/`pipefail` would abort those guarded paths.
set -u
# INVARIANT: trap body ends with guaranteed-zero `:` so a failing cleanup never
# clobbers the script's own exit code (mirrors fetch-normalize.sh / ADR-0020).
trap ':' EXIT

# Stable machine git-log format (see §2). US=0x1e (record start), RS=0x1f (field
# sep). The pure core matches the literal "COMMIT" prefix after stripping US.
US=$'\x1e'
RS=$'\x1f'
GIT_LOG_FORMAT="${US}COMMIT${RS}%H${RS}%s"
# The \x1eCOMMIT\x1f record marker (used by both the tokenizer and the live
# parse-failed gate). A live payload with commits ALWAYS contains it.
RECORD_MARKER="${US}COMMIT${RS}"

# ── Self-location + shared PURE-CORE libs (STEP-002 thin entrypoint) ──────────
# The reconstruction functions (git_log_to_findings; normalized_to_findings,
# normalized_live_parse_gate, reconstruct_ledger) live in _shared so STEP-003 can
# test the pure core offline. They reference caller-shell globals US/RS/BASE at
# CALL time — defined above, BEFORE the control flow that calls them. Self-locate
# in a SUBSHELL so cwd is NOT mutated (BASE/`git log` must keep running against the
# process cwd). layout plugin/skills/github-review-loop/scripts/ => 3 dirs up is
# the plugin root. cd && pwd -P is portable (no realpath/readlink). NO
# ${CLAUDE_PLUGIN_ROOT} inside an engine script.
ledgerrecon_fail() {
  echo "LEDGERRECON_ERROR=$1" >&2
  exit 1
}

script_dir="$(__d="$(dirname -- "${BASH_SOURCE[0]}" 2>/dev/null)" && [ -n "$__d" ] && CDPATH= cd -- "$__d" 2>/dev/null && pwd -P 2>/dev/null)" || ledgerrecon_fail "cannot-self-locate"
plugin_root="$(CDPATH= cd -- "$script_dir/../../.." 2>/dev/null && pwd -P 2>/dev/null)" || ledgerrecon_fail "cannot-resolve-plugin-root"
[ -f "$plugin_root/skills/_shared/ledger-reconstruct-parse.sh" ] || ledgerrecon_fail "missing-shared-lib"
. "$plugin_root/skills/_shared/ledger-reconstruct-parse.sh" || ledgerrecon_fail "unparseable-shared-lib"
[ -f "$plugin_root/skills/_shared/ledger-reconstruct-fold.sh" ] || ledgerrecon_fail "missing-shared-lib"
. "$plugin_root/skills/_shared/ledger-reconstruct-fold.sh" || ledgerrecon_fail "unparseable-shared-lib"

BASE=""
NORMALIZED_FILE=""
GIT_LOG_FILE=""

# Parse flags; collect positionals (BASE binds first). Mirrors fetch-normalize.sh.
positionals=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --normalized-file)
      [ "$#" -ge 2 ] || ledgerrecon_fail "missing-value-for-normalized-file"
      NORMALIZED_FILE="$2"; shift 2 ;;
    --normalized-file=*)
      NORMALIZED_FILE="${1#--normalized-file=}"
      [ -n "$NORMALIZED_FILE" ] || ledgerrecon_fail "missing-value-for-normalized-file"
      shift ;;
    --git-log-file)
      [ "$#" -ge 2 ] || ledgerrecon_fail "missing-value-for-git-log-file"
      GIT_LOG_FILE="$2"; shift 2 ;;
    --git-log-file=*)
      GIT_LOG_FILE="${1#--git-log-file=}"
      [ -n "$GIT_LOG_FILE" ] || ledgerrecon_fail "missing-value-for-git-log-file"
      shift ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do positionals+=("$1"); shift; done ;;
    *)
      positionals+=("$1"); shift ;;
  esac
done

BASE="${positionals[0]:-}"

# read_source <path>: read a payload from a file or stdin (`-`). RETURNS non-zero
# (emitting the LEDGERRECON_ERROR marker on stderr) when an explicitly-supplied
# file is unreadable — an input error, distinct from the fail-open empty path.
# INVARIANT: runs inside command substitution, so failure crosses the boundary via
# return code, never `exit`. Mirrors fetch-normalize.sh's read_payload_source. (F1)
read_source() {
  local src="$1"
  if [ "$src" = "-" ]; then
    cat
  else
    if [ ! -f "$src" ]; then
      echo "LEDGERRECON_ERROR=input-file-not-found" >&2
      return 1
    fi
    cat "$src"
  fi
}

# live_git_log_preflight: validate the LIVE path BEFORE streaming (BASE present,
# inside a work tree). RETURNS non-zero with a stable LEDGERRECON_ERROR marker so
# a real failure never degrades to an empty ledger (LIVE FAIL-CLOSED). Separated
# from the byte stream because the git-log payload carries NUL delimiters and so
# MUST NOT round-trip through a `$(...)` capture (bash strips NUL from variables) —
# it streams straight into awk instead.
live_git_log_preflight() {
  [ -n "$BASE" ] || { echo "LEDGERRECON_ERROR=missing-base" >&2; return 1; }
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "LEDGERRECON_ERROR=not-a-repo" >&2
    return 1
  fi
  return 0
}

# stream_git_log: write the raw git-log bytes to stdout (NUL-delimited), streamed
# directly so NULs survive (no variable round-trip). -z --raw gives rename-safe,
# quote-safe, space-safe PATHS on git's machine channel; -p --unified=0 gives hunk
# headers with exact NEW-file line ranges; --find-renames classifies renames
# (R-status emits old+new paths); --no-color keeps the payload machine-parseable.
# RETURNS git's own exit status. All diff/path text is DATA.
#
# LIVE TEST SEAM: if LEDGERRECON_TEST_LIVE_PAYLOAD_FILE is set to a readable file,
# stream its contents instead of running git (mirrors FETCHNORM_LIVE_* pattern).
# Seam is LIVE-branch only: --git-log-file (INJECTED=1) bypasses this function
# entirely, so the seam cannot interfere with the injected fail-open path.
stream_git_log() {
  if [ -n "${LEDGERRECON_TEST_LIVE_PAYLOAD_FILE:-}" ]; then
    cat "$LEDGERRECON_TEST_LIVE_PAYLOAD_FILE"
    return 0
  fi
  git log --no-color --unified=0 -z --raw -p --find-renames \
    --format="$GIT_LOG_FORMAT" "${BASE}..HEAD" 2>/dev/null
}

# --- Resolve the git-log findings (live fetch OR injected fixture) -----------
# The git-log payload carries NUL delimiters, so it is STREAMED straight into the
# tokenizer — never captured into a shell variable (bash strips NUL). Only the
# resulting JSON (NUL-free) is captured. INJECTED FAIL-OPEN: a malformed/empty
# payload degrades to `[]`.
INJECTED=0
if [ -n "$GIT_LOG_FILE" ]; then
  INJECTED=1
  if [ "$GIT_LOG_FILE" = "-" ]; then
    git_findings="$(git_log_to_findings)"          # stdin streams into the tokenizer
  else
    if [ ! -f "$GIT_LOG_FILE" ]; then
      ledgerrecon_fail "input-file-not-found"
    fi
    git_findings="$(git_log_to_findings < "$GIT_LOG_FILE")"
  fi
else
  # LIVE FAIL-CLOSED preflight: bad base / not-a-repo fails closed BEFORE the walk.
  if ! live_git_log_preflight; then
    exit 1
  fi
  # LIVE FAIL-CLOSED parse gate (§4): a NON-EMPTY git output that carries no
  # \x1eCOMMIT\x1f record marker is structurally-broken git output, NOT a real
  # empty log — fail closed rather than mask it as "no prior fixes". An EMPTY
  # output (no commits in <base>..HEAD) is a legitimate "no prior fixes yet" state
  # and stays exit 0. The marker probe streams git once (NUL-safe, no capture);
  # the findings stream git a second time. The injected path is exempt (trusted
  # fixture, fail-open). git's own failure on either stream fails closed.
  # grep -a: the -z stream carries NUL, so force text matching; -F: the marker's
  # \x1e/\x1f bytes are a literal fixed string, never a regex.
  if ! stream_git_log | grep -aqF "$RECORD_MARKER" 2>/dev/null; then
    probe_status="${PIPESTATUS[0]}"
    # grep exit 1 = marker absent. Distinguish empty-log (exit 0, no bytes) from a
    # non-empty unparseable payload: re-probe for ANY byte.
    if [ "$probe_status" -ne 0 ]; then
      ledgerrecon_fail "git-log-failed"
    fi
    if stream_git_log | read -r -n 1 _ 2>/dev/null; then
      ledgerrecon_fail "live-parse-failed"
    fi
  fi
  git_findings="$(stream_git_log | git_log_to_findings)"
fi
case "$git_findings" in '') git_findings='[]' ;; esac

# --- Resolve the normalized payload (live `-` OR injected fixture; optional) --
# The normalized payload is JSON (NUL-free), so a variable capture is safe here.
# LIVE-vs-INJECTED split mirrors the git-log channel: the run-level INJECTED flag
# (set above iff --git-log-file is present) classifies the whole invocation. On a
# LIVE run (INJECTED != 1) the normalized payload is the runtime `--normalized-file -`
# the agent supplies and is fenced by normalized_live_parse_gate (FAIL-CLOSED on a
# non-empty/non-array payload). On an INJECTED run the payload is a trusted fixture
# and skips the gate (FAIL-OPEN: non-array -> [] in the pure core).
normalized_payload=""
if [ -n "$NORMALIZED_FILE" ]; then
  if ! normalized_payload="$(read_source "$NORMALIZED_FILE")"; then
    exit 1
  fi
  if [ "$INJECTED" -ne 1 ]; then
    if ! normalized_live_parse_gate "$normalized_payload"; then
      exit 1
    fi
  fi
fi

thread_findings="$(normalized_to_findings "$normalized_payload")"
case "$thread_findings" in '') thread_findings='[]' ;; esac

reconstruct_ledger "$git_findings" "$thread_findings"

exit 0
