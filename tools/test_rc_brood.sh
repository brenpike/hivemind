#!/usr/bin/env bash
#
# Script-triple test for the enable-brood-remote engine
# plugin/skills/enable-brood-remote/scripts/rc-brood.sh.
#
# Drives the engine end-to-end against DISPOSABLE throwaway git checkouts (so its
# `git rev-parse --show-toplevel` resolves a tmp root) with a FAKE `tmux` first on PATH so the
# test controls session liveness and captures every `send-keys` payload WITHOUT delivering a
# keystroke anywhere. Mirrors tools/test_seed_hive.sh conventions: hermetic `mktemp -d` workdir,
# EXIT-trap cleanup, tmp HOME, SKIP-clean when jq/git absent, explicit PASS/FAIL counters,
# non-zero exit on any failed assertion. Writes nothing into this repo's tree.
#
# LOCKED INVARIANTS (each a PASS/FAIL case):
#   1. All-alive fan-out: N strains, all sessions alive → one `/rc <short>` + one Enter per strain,
#      correct canonical `short` per strain, exit 0, summary applied=N. Each send addresses the
#      RESOLVED ACTIVE PANE-ID (`%N`) of the strain's EXACT session — never a bare session name.
#   2. Fail-soft on dead session: one strain's session NOT alive → that strain skipped, the OTHER
#      strains still get their send-keys, exit 0, summary shows the skip.
#   3. Pre-flight blocker → ZERO send-keys: (a) bad/empty/traversal brood-id, (b) missing manifest
#      → `blocker:` on stderr, exit 1, send-keys log EMPTY.
#   4. Injection-safety: a hostile strain name (`;`, `$()`, backticks, spaces, slashes) → the bytes
#      sent are ONLY the `/rc <short>` literal (`short` is [a-z0-9-]-only); no shell metacharacter
#      reaches send-keys and no side-effect file the hostile name tried to create exists.
#   5. Summary correctness: applied/skipped/failed counts match the scenario.
#   6. RC-name collision guard: two strains whose names collide under the OLD delete-slug but are
#      DISTINCT under `short` receive DISTINCT `/rc <short>` names (the de-dup-inheritance fix).
#   7. Manifest-shape preflight (fail-closed): a wrong-shaped/corrupt manifest is a PRE-FLIGHT
#      blocker (exit 1, ZERO send-keys), never a silent no-op and never object-value-iterated —
#      `.strains` MISSING / NULL / OBJECT / non-array → blocker; a non-object strain element →
#      blocker; a non-string name/tmux_session → blocker (caught up front by the shape gate). The
#      valid EMPTY-ARRAY `.strains` boundary is NOT regressed (zero-strain run still exits 0).
#   8. Pane-id targeting (TOCTOU prefix-match closure): delivery is addressed to the active pane-id
#      resolved from the EXACT session (`list-panes -s -t "=<session>"`, the `11` active row), NOT to
#      a bare/`=`-prefixed session name. A same-prefix SIBLING is never a target (neither its bare
#      name nor its pane-id) and never receives `/rc`, even when it is alive alongside the exact
#      session (Case 16).
#   9. Fail-closed on raced pane death: if the resolved pane disappears between resolve and send
#      (pane-id no longer deliverable) the send FAILS CLOSED — `failed:` disposition, strain counted
#      failed, ZERO `/rc` mis-delivered to a same-prefix sibling, no bare-name target ever emitted
#      (Case 16b). The fake models real tmux exact-first-then-PREFIX session-name fallback, so a
#      hypothetical revert to bare-name addressing WOULD mis-deliver to the sibling and trip 16/16b.
#  10. Exactly-one-active-pane resolver (STEP-001 fail-closed): the send-time resolver consumes ALL
#      `list-panes -s -t "=<session>"` rows and counts the ACTIVE (`11`) rows, requiring EXACTLY ONE.
#      A session reporting >1 active pane (or zero) fails CLOSED — `failed:` disposition, strain counted
#      failed, ZERO `/rc` sent (it never selects one of multiple active panes), fan-out still exits 0
#      (Case 17). A revert to break-on-first would silently pick one pane and deliver, tripping Case 17.
#  11. Strain selection (`--only <short>...`, spawn-time remote control): a selected short is delivered;
#      an unselected strain gets one `skipped: <short> (not selected)` line and ZERO send-keys; a bad
#      short (outside ^[a-z0-9-]+$) is a pre-flight blocker with ZERO send-keys; `--only` with no shorts
#      sends nothing, exits 0 and reports 0 applied (Cases 18a-18d).
#
# Usage:
#   ./tools/test_rc_brood.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ENGINE="$REPO_ROOT/plugin/skills/enable-brood-remote/scripts/rc-brood.sh"
FIXTURES="$REPO_ROOT/tests/brood"

[ -f "$ENGINE" ] || { echo "FAIL: engine missing: $ENGINE" >&2; exit 2; }

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq is required to run this suite"  >&2; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git is required to run this suite" >&2; exit 0; }

PASS_COUNT=0
FAIL_COUNT=0
pass()   { echo "PASS [$1] $2"; PASS_COUNT=$((PASS_COUNT + 1)); }
failed() { echo "FAIL [$1] $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# assert_eq <case> <expected> <actual> [msg]
assert_eq() {
  local case_name="$1" expected="$2" actual="$3" msg="${4:-}"
  if [ "$expected" = "$actual" ]; then
    pass "$case_name" "${msg:+$msg }(== '$expected')"
  else
    failed "$case_name" "${msg:+$msg }expected '$expected', got '$actual'"
  fi
}

# assert_contains <case> <needle> <haystack> [msg]
assert_contains() {
  local case_name="$1" needle="$2" haystack="$3" msg="${4:-}"
  if grep -qF -- "$needle" <<<"$haystack"; then
    pass "$case_name" "${msg:+$msg }(contains '$needle')"
  else
    failed "$case_name" "${msg:+$msg }missing '$needle'"
  fi
}

# assert_not_contains <case> <needle> <haystack> [msg]
assert_not_contains() {
  local case_name="$1" needle="$2" haystack="$3" msg="${4:-}"
  if grep -qF -- "$needle" <<<"$haystack"; then
    failed "$case_name" "${msg:+$msg }unexpectedly contains '$needle'"
  else
    pass "$case_name" "${msg:+$msg }(free of '$needle')"
  fi
}

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hivemind-rc-brood.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# ── Fake tmux ───────────────────────────────────────────────────────────────────
# A FAKE `tmux` placed FIRST on PATH so the engine's `tmux has-session` / `tmux list-panes` /
# `tmux send-keys` calls hit the fake instead of a real server. It models the EXACT resolution
# contract the engine relies on (STEP-001 re-key from bare session NAME to pane-id `%N`):
#
#   has-session -t "=<s>" : exit 0 iff <s> (after stripping a single leading `=`) is listed (one per
#                           line) in $TMUX_ALIVE_FILE; else exit 1. Liveness gate.
#   list-panes -s -t "=<s>" -F <fmt>
#                         : if <s> (after `=`-strip) is alive, emit ONE deterministic active-pane row
#                           `<session>\t11\t<pane_id>` (field2 `11` == active win + active pane;
#                           field3 the stable pane-id derived from the session name). Not alive →
#                           empty output, exit 1. The `=` prefix IS honored here (target-SESSION).
#                           If <s> is in the space-separated $TMUX_MULTI_ACTIVE list, a SECOND active
#                           (`11`) row with a DISTINCT pane id is emitted too (models a >1-active-pane
#                           anomaly the STEP-001 resolver must reject; empty default → one row).
#   send-keys -t <target> ...
#                         : models tmux target-PANE resolution. A pane-id target (`%…`) has NO prefix
#                           fallback — it delivers ONLY when its session is alive AND the pane is not
#                           in $TMUX_PANE_GONE_AT_SEND; otherwise `can't find pane: %…`, exit 1. A BARE
#                           session-name target models real tmux exact-FIRST-then-PREFIX fallback:
#                           delivers to the exact session if deliverable, ELSE to a same-prefix
#                           SIBLING (the mis-delivery a revert to bare-name addressing must trigger).
#                           A `=`-prefixed target is invalid as a pane spec on 3.0a → `can't find
#                           pane`, exit 1. On SUCCESS the full argv plus a `DELIVERED-SESSION:`/
#                           `DELIVERED-PANE:` pair (the EFFECTIVE delivery target) is appended to
#                           $TMUX_SENDKEYS_LOG; on FAILURE nothing is logged (a record == a delivered
#                           keystroke). It NEVER actually sends a keystroke — capture only.
#   any other subcmd      : exit 0 (no-op; the engine uses only the three above).
FAKE_BIN="$WORKDIR/fakebin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/tmux" <<'FAKE_TMUX'
#!/usr/bin/env bash
# Hermetic tmux stand-in for test_rc_brood.sh. Liveness + pane-id resolution + send-keys capture.

# pane_id_for <session> — deterministic stable pane-id (`%<n>`) for a session name. cksum gives a
# stable integer hash; the parent test recomputes this IDENTICALLY so assertions know each pane id.
# Zero-padded to a FIXED 10 digits (cksum is a 32-bit value, max 4294967295) so no pane id is ever a
# substring of another — `assert_not_contains` on a pane id must not false-positive on a longer one.
pane_id_for() { printf '%%%010d' "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }

# pane_is_gone <pane_id> — true if the pane-id is in the space-separated $TMUX_PANE_GONE_AT_SEND list
# (a pane that has DIED between resolve and send). Models the raced-death fail-closed boundary.
pane_is_gone() {
  local p="$1" g
  for g in ${TMUX_PANE_GONE_AT_SEND:-}; do
    [ "$g" = "$p" ] && return 0
  done
  return 1
}

# session_alive <session> — true if the session is listed in the alive-set file.
session_alive() {
  [ -n "${TMUX_ALIVE_FILE:-}" ] || return 1
  [ -f "$TMUX_ALIVE_FILE" ]     || return 1
  grep -qxF -- "$1" "$TMUX_ALIVE_FILE"
}

# record_send <eff_session> <eff_pane> <argv…> — append ONE delivery record: the verbatim argv plus
# the EFFECTIVE delivery target (so the test can detect a mis-delivery to a sibling, which the bare
# argv alone would hide). Only ever called on a SUCCESSFUL delivery.
record_send() {
  local eff_session="$1" eff_pane="$2"; shift 2
  {
    printf 'SEND-KEYS-RECORD\n'
    for a in "$@"; do printf 'ARG:%s\n' "$a"; done
    printf 'DELIVERED-SESSION:%s\n' "$eff_session"
    printf 'DELIVERED-PANE:%s\n'    "$eff_pane"
    printf 'END-RECORD\n'
  } >> "${TMUX_SENDKEYS_LOG:?TMUX_SENDKEYS_LOG unset}"
}

sub="${1:-}"
shift || true
case "$sub" in
  has-session)
    # parse `-t <session>`
    target=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t) target="${2:-}"; shift 2 ;;
        *)  shift ;;
      esac
    done
    # The engine probes liveness with tmux's exact-match `=` prefix (`-t "=<session>"`). Strip a
    # single leading `=` before comparing to the plain alive-set lines so fixtures stay plain names.
    target="${target#=}"
    if session_alive "$target"; then exit 0; fi
    exit 1
    ;;
  list-panes)
    # parse `-s -t <target> -F <fmt>`; the engine always passes `-s -t "=<session>"`.
    target=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t) target="${2:-}"; shift 2 ;;
        -F) shift 2 ;;
        *)  shift ;;
      esac
    done
    target="${target#=}"
    # Resolution is liveness-only: a pane that DIES AFTER this gate is modeled at send time via
    # $TMUX_PANE_GONE_AT_SEND, so list-panes here ignores that override (the race the engine closes).
    if session_alive "$target"; then
      printf '%s\t11\t%s\n' "$target" "$(pane_id_for "$target")"
      # $TMUX_MULTI_ACTIVE: a session in this space-separated list gets a SECOND active (`11`) row with
      # a DISTINCT pane id, so list-panes returns 2 active rows — the >1-active-pane anomaly the
      # STEP-001 resolver must fail CLOSED on. Sessions NOT listed keep exactly one active row.
      for m in ${TMUX_MULTI_ACTIVE:-}; do
        if [ "$m" = "$target" ]; then
          printf '%s\t11\t%s\n' "$target" "$(pane_id_for "$target-multi-active-2")"
          break
        fi
      done
      exit 0
    fi
    exit 1
    ;;
  send-keys)
    # Parse `-t <target>` to model tmux's target resolution rules below.
    sk_target=""
    sk_args=("$@")
    i=0
    while [ "$i" -lt "${#sk_args[@]}" ]; do
      case "${sk_args[$i]}" in
        -t) i=$((i + 1)); sk_target="${sk_args[$i]:-}" ;;
      esac
      i=$((i + 1))
    done
    # tmux 3.0a: the exact-match `=` prefix is a target-SESSION-only modifier, NOT honored in
    # target-PANE resolution. A `=`-prefixed target to `send-keys` FAILS (`can't find pane`, rc=1).
    # The engine must therefore NEVER hand a `=`-prefixed target to send-keys.
    case "$sk_target" in
      =*) printf "can't find pane: %s\n" "$sk_target" >&2; exit 1 ;;
    esac
    # Test-controlled forced failure: when the send-keys target equals $TMUX_SENDKEYS_FAIL_TARGET,
    # emit a recognizable line on STDERR and exit non-zero so a case can assert the engine surfaces
    # the tmux stderr text on its `failed:` disposition line.
    if [ -n "${TMUX_SENDKEYS_FAIL_TARGET:-}" ] && [ "$sk_target" = "$TMUX_SENDKEYS_FAIL_TARGET" ]; then
      printf "can't find pane: %s\n" "$sk_target" >&2
      exit 1
    fi
    case "$sk_target" in
      %*)
        # PANE-ID target: NO prefix fallback. Deliver ONLY if the pane has not gone AND its (derived)
        # session is alive. A gone pane (or one whose session died) FAILS CLOSED — never mis-delivers.
        if pane_is_gone "$sk_target"; then
          printf "can't find pane: %s\n" "$sk_target" >&2; exit 1
        fi
        eff_session=""
        while IFS= read -r s; do
          [ -n "$s" ] || continue
          if [ "$(pane_id_for "$s")" = "$sk_target" ]; then eff_session="$s"; break; fi
        done < "${TMUX_ALIVE_FILE:-/dev/null}"
        if [ -z "$eff_session" ]; then
          printf "can't find pane: %s\n" "$sk_target" >&2; exit 1
        fi
        record_send "$eff_session" "$sk_target" "$@"
        exit 0
        ;;
      *)
        # BARE session-name target: model real tmux exact-FIRST-then-PREFIX fallback. This is the
        # vulnerable behavior a revert to bare-name addressing would re-introduce — it MUST be able to
        # mis-deliver to a same-prefix sibling so Cases 16/16b trip on such a revert.
        if session_alive "$sk_target"; then
          exact_pane="$(pane_id_for "$sk_target")"
          if ! pane_is_gone "$exact_pane"; then
            record_send "$sk_target" "$exact_pane" "$@"
            exit 0
          fi
          # Exact session alive but its pane gone → tmux falls back to prefix matching (mis-delivery).
        fi
        # Prefix fallback: deliver to the FIRST alive same-prefix session whose pane is deliverable.
        while IFS= read -r s; do
          [ -n "$s" ] || continue
          case "$s" in
            "$sk_target"*)
              sp="$(pane_id_for "$s")"
              if ! pane_is_gone "$sp"; then
                record_send "$s" "$sp" "$@"
                exit 0
              fi
              ;;
          esac
        done < "${TMUX_ALIVE_FILE:-/dev/null}"
        printf "can't find pane: %s\n" "$sk_target" >&2; exit 1
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
FAKE_TMUX
chmod +x "$FAKE_BIN/tmux"

# pane_id_for <session> — parent-side recompute of the fake tmux pane-id mapping (IDENTICAL formula,
# fixed 10-digit zero-pad), so targeting assertions can name the resolved pane id (`%N`) the engine
# addresses for each exact session.
pane_id_for() { printf '%%%010d' "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }

# new_brood_root <name> <brood_id> <fixture> — materialize a throwaway git checkout under $WORKDIR
# and stage <fixture> at <root>/.hivemind/broods/<brood_id>/manifest.json so the engine's
# `git rev-parse --show-toplevel`-anchored manifest read resolves it there. Prints the root path.
new_brood_root() {
  local name="$1" brood_id="$2" fixture="$3"
  local root="$WORKDIR/$name"
  mkdir -p "$root"
  git -C "$root" init -q
  mkdir -p "$root/.hivemind/broods/$brood_id"
  cp "$fixture" "$root/.hivemind/broods/$brood_id/manifest.json"
  printf '%s' "$root"
}

# run_engine <root> <brood_id> <alive_file> <sendkeys_log> [engine_arg…] — run the engine inside <root>
# with the fake tmux first on PATH, a tmp HOME, the configured alive-set + send-keys log. Any argument
# after <sendkeys_log> is passed to the engine after the brood-id (e.g. `--only api`). Stdout is written to
# <sendkeys_log>.stdout, stderr to <sendkeys_log>.stderr, and the exit code is stored in the global
# RUN_RC. run_engine is NOT invoked through command substitution (a `$()` subshell could not write
# RUN_RC back to the parent shell); callers read RUN_RC and the .stdout file after the call.
RUN_RC=0
run_engine() {
  local root="$1" brood_id="$2" alive_file="$3" sendkeys_log="$4"
  shift 4
  set +e
  (
    cd "$root" \
      && PATH="$FAKE_BIN:$PATH" \
         HOME="$root/fakehome" \
         TMUX_ALIVE_FILE="$alive_file" \
         TMUX_SENDKEYS_LOG="$sendkeys_log" \
         TMUX_SENDKEYS_FAIL_TARGET="${TMUX_SENDKEYS_FAIL_TARGET:-}" \
         TMUX_PANE_GONE_AT_SEND="${TMUX_PANE_GONE_AT_SEND:-}" \
         TMUX_MULTI_ACTIVE="${TMUX_MULTI_ACTIVE:-}" \
         bash "$ENGINE" "$brood_id" "$@"
  ) >"${sendkeys_log}.stdout" 2>"${sendkeys_log}.stderr"
  RUN_RC=$?
  set -e
}

# count_records <log> — number of send-keys invocations captured. `grep -c` prints its count AND
# exits 1 on zero matches, so route through a var to keep a single clean integer on stdout.
count_records() {
  local n
  n="$(grep -c '^SEND-KEYS-RECORD$' "$1" 2>/dev/null)" || true
  printf '%s' "${n:-0}"
}

# literal_payloads <log> — for every send-keys call carrying `-l`, echo the LAST ARG (the literal
# text typed, e.g. `/rc <slug>`), one per line. This is the exact byte payload delivered.
literal_payloads() {
  awk '
    /^SEND-KEYS-RECORD$/ { has_l=0; last=""; next }
    /^ARG:-l$/           { has_l=1; next }
    /^ARG:/              { last=substr($0,5); next }
    /^END-RECORD$/       { if (has_l) print last; next }
  ' "$1"
}

# enter_count <log> — number of send-keys calls whose final ARG is the literal `Enter` key event.
enter_count() {
  awk '
    /^SEND-KEYS-RECORD$/ { last=""; next }
    /^ARG:/              { last=substr($0,5); next }
    /^END-RECORD$/       { if (last=="Enter") c++; next }
    END                  { print c+0 }
  ' "$1"
}

# ── Case 1: all-alive fan-out ─────────────────────────────────────────────────────
# 3 strains, all sessions alive → one `/rc <short>` literal + one Enter per strain, correct `short`
# per strain, exit 0, summary applied=3 skipped=0 failed=0.
echo '=== Case 1: all-alive fan-out — one /rc <short> + Enter per strain, exit 0 ==='
BID1="brood-feedface-0000-4000-8000-000000000001"
ROOT1="$(new_brood_root all-alive "$BID1" "$FIXTURES/rc-manifest-all-alive.json")"
ALIVE1="$WORKDIR/alive1"
LOG1="$WORKDIR/log1"
: > "$LOG1"
printf '%s\n' \
  "$BID1-api" \
  "$BID1-web-ui" \
  "$BID1-db-migrations" > "$ALIVE1"
run_engine "$ROOT1" "$BID1" "$ALIVE1" "$LOG1"
OUT1="$(cat "${LOG1}.stdout")"
assert_eq "all-alive:exit" "0" "$RUN_RC" "fan-out completed"
# 3 literal send-keys (the /rc payloads) + 3 Enter = 6 records.
assert_eq "all-alive:record-count" "6" "$(count_records "$LOG1")" "two send-keys per strain"
assert_eq "all-alive:enter-count" "3" "$(enter_count "$LOG1")" "one Enter per strain"
PAYLOADS1="$(literal_payloads "$LOG1")"
# `/rc` payload is now the canonical `short` (the session-identity token), NOT a separate slug.
# api → api, web-ui → web-ui (already short-equal); db.migrations → db-migrations (`.` REPLACE-mapped
# to `-` by the short derivation, not deleted as the old slug did).
assert_contains "all-alive:short-api"   "/rc api"           "$PAYLOADS1" "api short"
assert_contains "all-alive:short-webui" "/rc web-ui"        "$PAYLOADS1" "web-ui short"
assert_contains "all-alive:short-db"    "/rc db-migrations" "$PAYLOADS1" "db.migrations short"
assert_eq "all-alive:literal-payload-count" "3" "$(printf '%s\n' "$PAYLOADS1" | grep -c '^/rc ')" "exactly 3 /rc literals"
assert_contains "all-alive:summary" "3 applied, 0 skipped, 0 failed (of 3 strains)" "$OUT1" "summary counts"
assert_contains "all-alive:applied-api" "applied: api" "$OUT1"
# Pane-id targeting (STEP-001): every delivered send-keys addresses the RESOLVED ACTIVE PANE-ID (`%N`)
# of the strain's EXACT session — NOT a bare session name and NOT a `=`-prefixed name. The pane id is
# resolved from `list-panes -s -t "=<session>"` (the `11` active row); a pane id has no prefix-match
# fallback. The fake tmux logs full argv, so assert the resolved pane id ARG appears for each delivered
# strain (incl. the derived db-migrations identity — not the manifest's old `-db` value), and that NO
# bare session-name target is ever emitted.
LOGTEXT1="$(cat "$LOG1")"
PANE_API1="$(pane_id_for "$BID1-api")"
PANE_WEBUI1="$(pane_id_for "$BID1-web-ui")"
PANE_DB1="$(pane_id_for "$BID1-db-migrations")"
assert_contains "all-alive:exact-target-api"    "ARG:$PANE_API1"   "$LOGTEXT1" "api addressed at resolved exact pane id"
assert_contains "all-alive:exact-target-webui"  "ARG:$PANE_WEBUI1" "$LOGTEXT1" "web-ui addressed at resolved exact pane id"
assert_contains "all-alive:exact-target-db"     "ARG:$PANE_DB1"    "$LOGTEXT1" "db.migrations addressed at resolved derived pane id"
assert_not_contains "all-alive:no-bare-api"    "ARG:$BID1-api"           "$LOGTEXT1" "no bare session-name target for api"
assert_not_contains "all-alive:no-bare-webui"  "ARG:$BID1-web-ui"        "$LOGTEXT1" "no bare session-name target for web-ui"
assert_not_contains "all-alive:no-bare-db"     "ARG:$BID1-db-migrations" "$LOGTEXT1" "no bare session-name target for db.migrations"

# ── Case 2: fail-soft on dead session ─────────────────────────────────────────────
# Same 3-strain manifest, but the web-ui session is NOT alive → web-ui skipped, api + db.migrations
# still delivered, exit 0, summary applied=2 skipped=1.
echo '=== Case 2: fail-soft — one dead session skipped, others still delivered ==='
ROOT2="$(new_brood_root dead-session "$BID1" "$FIXTURES/rc-manifest-all-alive.json")"
ALIVE2="$WORKDIR/alive2"
LOG2="$WORKDIR/log2"
: > "$LOG2"
# web-ui session intentionally OMITTED → has-session returns failure for it.
printf '%s\n' \
  "$BID1-api" \
  "$BID1-db-migrations" > "$ALIVE2"
run_engine "$ROOT2" "$BID1" "$ALIVE2" "$LOG2"
OUT2="$(cat "${LOG2}.stdout")"
assert_eq "dead:exit" "0" "$RUN_RC" "dead session does not abort fan-out"
PAYLOADS2="$(literal_payloads "$LOG2")"
assert_contains "dead:short-api" "/rc api"           "$PAYLOADS2" "api still delivered"
assert_contains "dead:short-db"  "/rc db-migrations" "$PAYLOADS2" "db still delivered"
assert_not_contains "dead:no-webui" "/rc web-ui" "$PAYLOADS2" "dead web-ui never delivered"
assert_eq "dead:literal-payload-count" "2" "$(printf '%s\n' "$PAYLOADS2" | grep -c '^/rc ')" "exactly 2 /rc literals (1 skipped)"
assert_eq "dead:enter-count" "2" "$(enter_count "$LOG2")" "one Enter per applied strain"
assert_contains "dead:skip-line" "skipped: web-ui (session not alive:" "$OUT2" "skip disposition line"
assert_contains "dead:summary" "2 applied, 1 skipped, 0 failed (of 3 strains)" "$OUT2" "summary counts"

# ── Case 3a: pre-flight blocker — bad brood-id → ZERO send-keys ───────────────────
# A traversal-shaped brood-id is rejected by the FAIL-CLOSED arg gate BEFORE any manifest read or
# keystroke. blocker on stderr, exit 1, send-keys log EMPTY.
echo '=== Case 3a: bad brood-id (traversal) — blocker, exit 1, zero send-keys ==='
ROOT3A="$(new_brood_root badid "$BID1" "$FIXTURES/rc-manifest-all-alive.json")"
ALIVE3A="$WORKDIR/alive3a"; : > "$ALIVE3A"
LOG3A="$WORKDIR/log3a"; : > "$LOG3A"
run_engine "$ROOT3A" "../../etc/passwd" "$ALIVE3A" "$LOG3A"
assert_eq "badid:exit" "1" "$RUN_RC" "bad brood-id is a pre-flight blocker"
assert_contains "badid:blocker" "blocker:" "$(cat "${LOG3A}.stderr")" "blocker line on stderr"
assert_eq "badid:zero-sendkeys" "0" "$(count_records "$LOG3A")" "no keystroke delivered on pre-flight blocker"

# ── Case 3a': empty brood-id → blocker, zero send-keys ────────────────────────────
echo '=== Case 3a-empty: empty brood-id — blocker, exit 1, zero send-keys ==='
ROOT3AE="$(new_brood_root emptyid "$BID1" "$FIXTURES/rc-manifest-all-alive.json")"
ALIVE3AE="$WORKDIR/alive3ae"; : > "$ALIVE3AE"
LOG3AE="$WORKDIR/log3ae"; : > "$LOG3AE"
run_engine "$ROOT3AE" "" "$ALIVE3AE" "$LOG3AE"
assert_eq "emptyid:exit" "1" "$RUN_RC" "empty brood-id is a pre-flight blocker"
assert_contains "emptyid:blocker" "blocker:" "$(cat "${LOG3AE}.stderr")" "blocker line on stderr"
assert_eq "emptyid:zero-sendkeys" "0" "$(count_records "$LOG3AE")" "no keystroke on empty brood-id"

# ── Case 3b: missing manifest → blocker, exit 1, zero send-keys ───────────────────
# Well-formed brood-id, but no manifest staged under that id → blocker, exit 1, send-keys empty.
echo '=== Case 3b: missing manifest — blocker, exit 1, zero send-keys ==='
ROOT3B="$WORKDIR/no-manifest"
mkdir -p "$ROOT3B"
git -C "$ROOT3B" init -q
ALIVE3B="$WORKDIR/alive3b"; : > "$ALIVE3B"
LOG3B="$WORKDIR/log3b"; : > "$LOG3B"
run_engine "$ROOT3B" "brood-deadbeef-0000-4000-8000-000000000099" "$ALIVE3B" "$LOG3B"
assert_eq "nomanifest:exit" "1" "$RUN_RC" "missing manifest is a pre-flight blocker"
assert_contains "nomanifest:blocker" "brood manifest not found" "$(cat "${LOG3B}.stderr")" "manifest-missing blocker"
assert_eq "nomanifest:zero-sendkeys" "0" "$(count_records "$LOG3B")" "no keystroke when manifest missing"

# ── Case 4: injection-safety ──────────────────────────────────────────────────────
# A hostile strain name carrying `;`, `$()`, backticks, spaces and slashes. The ONLY bytes sent are
# the sanitized `/rc <slug>` literal. No shell metacharacter reaches send-keys; no side-effect file
# the hostile name tried to create exists anywhere.
echo '=== Case 4: injection-safety — only the /rc <short> literal is sent ==='
BID4="brood-feedface-0000-4000-8000-000000000002"
ROOT4="$(new_brood_root hostile "$BID4" "$FIXTURES/rc-manifest-hostile-name.json")"
ALIVE4="$WORKDIR/alive4"
LOG4="$WORKDIR/log4"
: > "$LOG4"
# The strain session is addressed at its GROUND-TRUTH-derived identity, not the manifest's old
# `-hostile` value. spawn-brood derives `short = name | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-'`,
# so the hostile name reduces to the long `-` token below; the fixture's tmux_session records exactly
# this so the coherence gate passes and the delivery (sanitization) path actually runs.
HOSTILE_SESSION4="$BID4-abc--touch-pwned---touch-subpwn---touch-btpwn---etc-x"
printf '%s\n' "$HOSTILE_SESSION4" > "$ALIVE4"
# The `/rc` payload is now the canonical `short` (the REPLACE-based session-identity token), the same
# value embedded in HOSTILE_SESSION4 after the brood-id prefix:
#   "abc; touch PWNED $(touch SUBPWN) `touch BTPWN` /etc/x"
#   -> abc--touch-pwned---touch-subpwn---touch-btpwn---etc-x   (lowercase, non-[a-z0-9-] -> '-')
EXPECT_SHORT="abc--touch-pwned---touch-subpwn---touch-btpwn---etc-x"
run_engine "$ROOT4" "$BID4" "$ALIVE4" "$LOG4"
OUT4="$(cat "${LOG4}.stdout")"
assert_eq "hostile:exit" "0" "$RUN_RC" "hostile name still completes fan-out"
PAYLOADS4="$(literal_payloads "$LOG4")"
# Exactly ONE literal payload, and it is the canonical `short` form verbatim.
assert_eq "hostile:literal-count" "1" "$(printf '%s\n' "$PAYLOADS4" | grep -c '^/rc ')" "exactly one /rc literal"
assert_eq "hostile:exact-payload" "/rc $EXPECT_SHORT" "$PAYLOADS4" "sent payload is the canonical short only"
# No shell metacharacter from the hostile name survived into the delivered short. The fixed `/rc `
# command prefix legitimately carries a space and a leading `/`; the SHORT (everything after `/rc `)
# is the only untrusted-derived portion and must be a pure [a-z0-9-] token. Strip the fixed prefix
# and assert the remaining short bytes carry none of the hostile metacharacters.
SHORT4="${PAYLOADS4#/rc }"
for meta in ';' '$(' '`' ' ' '/'; do
  if grep -qF -- "$meta" <<<"$SHORT4"; then
    failed "hostile:no-meta" "metacharacter '$meta' reached the send-keys short"
  else
    pass "hostile:no-meta" "(short free of metacharacter '$meta')"
  fi
done
# No side-effect file the hostile name attempted to create exists — search the whole workdir + cwd.
INJECT_HITS="$(find "$WORKDIR" \( -name 'PWNED' -o -name 'SUBPWN' -o -name 'BTPWN' \) 2>/dev/null | head -n 1)"
assert_eq "hostile:no-side-effect" "" "$INJECT_HITS" "no injected file (PWNED/SUBPWN/BTPWN) created"
# The delivery addresses the RESOLVED PANE-ID of the GROUND-TRUTH-derived identity — proving the
# coherence gate passed and the sanitized payload was actually delivered (not skipped), and that no
# bare session-name target was emitted. The slug (command-arg charset) and the session identity
# (lowercased `-` charset) legitimately differ.
LOGTEXT4="$(cat "$LOG4")"
PANE_HOSTILE4="$(pane_id_for "$HOSTILE_SESSION4")"
assert_contains "hostile:exact-target" "ARG:$PANE_HOSTILE4" "$LOGTEXT4" "hostile strain addressed at resolved derived pane id"
assert_not_contains "hostile:no-bare-target" "ARG:$HOSTILE_SESSION4" "$LOGTEXT4" "no bare session-name target for hostile strain"

# ── Case 6: manifest brood_id mismatch → pre-flight blocker, zero send-keys ───────
# A well-formed REQUESTED brood-id, a manifest staged under that id, but the manifest's OWN top-level
# brood_id disagrees (stale/tampered) → pre-flight blocker, exit 1, send-keys EMPTY. We stage the
# all-alive fixture (whose recorded brood_id is ...0001) under a DIFFERENT requested id.
echo '=== Case 6: manifest brood_id mismatch — blocker, exit 1, zero send-keys ==='
BID6="brood-feedface-0000-4000-8000-000000000006"
ROOT6="$(new_brood_root brood-mismatch "$BID6" "$FIXTURES/rc-manifest-all-alive.json")"
ALIVE6="$WORKDIR/alive6"; : > "$ALIVE6"
LOG6="$WORKDIR/log6"; : > "$LOG6"
run_engine "$ROOT6" "$BID6" "$ALIVE6" "$LOG6"
assert_eq "brood-mismatch:exit" "1" "$RUN_RC" "manifest brood_id mismatch is a pre-flight blocker"
assert_contains "brood-mismatch:blocker" "manifest brood_id does not match" "$(cat "${LOG6}.stderr")" "mismatch blocker line"
assert_eq "brood-mismatch:zero-sendkeys" "0" "$(count_records "$LOG6")" "no keystroke on brood_id mismatch"

# ── Case 7: foreign-session → exact-identity mismatch skip, others delivered ──────
# A coherent manifest (brood_id matches) where the `evil` strain's tmux_session points at an alive
# UNRELATED session (`victim-unrelated-session`) that does NOT equal its ground-truth-derived identity
# `<brood_id>-evil`. With exact-identity targeting the recorded value is only a coherence signal: it
# mismatches the derived identity, so the strain is SKIPPED and the victim session is NEVER addressed
# (the engine targets the derived identity, never the manifest value). The legitimate in-namespace
# strain is still delivered. The victim session is "alive" in the fake tmux, proving the identity gate
# is what blocks it — not liveness.
echo '=== Case 7: foreign session — exact-identity mismatch skip, never addressed ==='
BID7="brood-feedface-0000-4000-8000-000000000004"
ROOT7="$(new_brood_root foreign-session "$BID7" "$FIXTURES/rc-manifest-foreign-session.json")"
ALIVE7="$WORKDIR/alive7"
LOG7="$WORKDIR/log7"
: > "$LOG7"
# Both the legitimate in-namespace session AND the unrelated victim session are alive.
printf '%s\n' \
  "$BID7-api" \
  "victim-unrelated-session" > "$ALIVE7"
run_engine "$ROOT7" "$BID7" "$ALIVE7" "$LOG7"
OUT7="$(cat "${LOG7}.stdout")"
LOGTEXT7="$(cat "$LOG7")"
assert_eq "foreign:exit" "0" "$RUN_RC" "foreign-session skip does not abort fan-out"
PAYLOADS7="$(literal_payloads "$LOG7")"
assert_contains "foreign:slug-api" "/rc api" "$PAYLOADS7" "in-namespace strain delivered"
assert_not_contains "foreign:no-victim" "/rc evil" "$PAYLOADS7" "foreign-session strain never delivered"
assert_eq "foreign:literal-count" "1" "$(printf '%s\n' "$PAYLOADS7" | grep -c '^/rc ')" "exactly 1 /rc literal (foreign skipped)"
assert_contains "foreign:skip-line" "skipped: evil (manifest session victim-unrelated-session does not match derived identity $BID7-evil)" "$OUT7" "exact-identity-mismatch skip disposition"
# The victim session is NEVER addressed: neither has-session nor send-keys ever carries it as a target.
assert_not_contains "foreign:victim-never-addressed" "ARG:=victim-unrelated-session" "$LOGTEXT7" "victim session never targeted"
assert_not_contains "foreign:victim-bare-never-addressed" "ARG:victim-unrelated-session" "$LOGTEXT7" "victim session never targeted (bare)"
assert_contains "foreign:summary" "1 applied, 1 skipped, 0 failed (of 2 strains)" "$OUT7" "summary counts"

# ── Case 7s: sibling/prefix rejection — the iter2 prefix-glob bypass, now closed ──
# REGRESSION GUARD for the old prefix-membership target-trust. A COHERENT manifest (brood_id matches)
# whose single strain `name=api` derives `expected_session=<brood_id>-api`, but whose recorded
# `tmux_session` is a SAME-PREFIX SIBLING `<brood_id>-api-sibling`. Under the old prefix/fnmatch
# membership check this sibling (and a glob-adjacent name) would have passed the namespace gate and
# been addressed. Under exact-identity targeting the recorded value is only a coherence signal: it does
# NOT equal the derived identity, so the strain is SKIPPED, ZERO `/rc` is delivered, and neither the
# sibling nor the fnmatch-adjacent session is ever addressed. The manifest is built inline (no fixture
# file) so the test owns the sibling-bypass shape directly.
echo '=== Case 7s: sibling/prefix rejection — exact-identity mismatch, zero delivery ==='
BID7S="brood-feedface-0000-4000-8000-000000000005"
ROOT7S="$WORKDIR/sibling-bypass"
mkdir -p "$ROOT7S/.hivemind/broods/$BID7S"
git -C "$ROOT7S" init -q
# name=api derives <bid>-api, but tmux_session records the same-prefix sibling <bid>-api-sibling.
jq -n --arg bid "$BID7S" '{
  manifest_version: 4,
  brood_id: $bid,
  created_at: "2026-06-21T00:00:00Z",
  hatchery_session: "",
  base: "main",
  hatchery: { run_id: ($bid + "-hatchery"), ledger: (".hivemind/runs/" + $bid + "-hatchery/state.json"), workflow: "hatchery-dispatch" },
  overlap_risk: "low",
  overlap_details: "No shared file scopes detected.",
  strains: [ {
    name: "api",
    description: "Coherent strain whose recorded tmux_session is a same-prefix sibling of its derived identity.",
    worktree_path: ("/repo/.claude/worktrees/" + $bid + "/api"),
    branch: ("strain/" + $bid + "/api"),
    tmux_session: ($bid + "-api-sibling"),
    status: "running",
    pr: null,
    merged: false,
    rebased_after: [],
    run: { suggested_id: ($bid + "--api"), workflow_hint: "standard-delivery" }
  } ],
  merge_order: []
}' > "$ROOT7S/.hivemind/broods/$BID7S/manifest.json"
ALIVE7S="$WORKDIR/alive7s"
LOG7S="$WORKDIR/log7s"
: > "$LOG7S"
# The sibling session AND an fnmatch-adjacent name are BOTH alive — proving the gate, not liveness,
# is what rejects them. The derived identity <bid>-api is intentionally NOT alive here.
printf '%s\n' \
  "$BID7S-api-sibling" \
  "$BID7S-api-x" > "$ALIVE7S"
run_engine "$ROOT7S" "$BID7S" "$ALIVE7S" "$LOG7S"
OUT7S="$(cat "${LOG7S}.stdout")"
LOGTEXT7S="$(cat "$LOG7S")"
assert_eq "sibling:exit" "0" "$RUN_RC" "sibling mismatch skip does not abort fan-out"
assert_eq "sibling:zero-sendkeys" "0" "$(count_records "$LOG7S")" "ZERO /rc delivered to the sibling (prefix bypass gone)"
assert_contains "sibling:skip-line" "skipped: api (manifest session $BID7S-api-sibling does not match derived identity $BID7S-api)" "$OUT7S" "exact-identity-mismatch skip disposition"
assert_not_contains "sibling:never-addressed" "ARG:=$BID7S-api-sibling" "$LOGTEXT7S" "sibling session never targeted"
assert_not_contains "sibling:bare-never-addressed" "ARG:$BID7S-api-sibling" "$LOGTEXT7S" "sibling session never targeted (bare)"
assert_contains "sibling:summary" "0 applied, 1 skipped, 0 failed (of 1 strains)" "$OUT7S" "summary shows the skip"

# ── Case 8: malformed strain field → pre-flight blocker, zero send-keys ───────────
# A manifest whose strain `name`/`tmux_session` is a non-string (object/array). The type-strict jq
# projection errors; the captured status converts it to a pre-flight blocker rather than a silent
# drop hidden by process substitution. blocker on stderr, exit 1, send-keys EMPTY.
echo '=== Case 8: malformed strain field (non-string) — blocker, exit 1, zero send-keys ==='
BID8="brood-feedface-0000-4000-8000-000000000003"
ROOT8="$(new_brood_root malformed "$BID8" "$FIXTURES/rc-manifest-malformed-name.json")"
ALIVE8="$WORKDIR/alive8"; : > "$ALIVE8"
LOG8="$WORKDIR/log8"; : > "$LOG8"
run_engine "$ROOT8" "$BID8" "$ALIVE8" "$LOG8"
assert_eq "malformed:exit" "1" "$RUN_RC" "non-string strain field is a pre-flight blocker"
assert_contains "malformed:blocker" "shape preflight" "$(cat "${LOG8}.stderr")" "shape-preflight blocker line (caught up front)"
assert_eq "malformed:zero-sendkeys" "0" "$(count_records "$LOG8")" "no keystroke on malformed projection"

# ── Case 10: manifest-shape preflight — `.strains` MISSING → blocker, zero send-keys ─
# THE P1 FIX'S REGRESSION GUARD (container-shape gate). A coherent manifest (brood_id matches) that
# OMITS `.strains` entirely. The OLD `.strains // []` silently turned this into an EMPTY brood and
# reported a "successful" `0 applied` run. The shape preflight now BLOCKS it: blocker on stderr,
# exit 1, ZERO send-keys (no silent no-op). Built inline so the test owns the missing-container shape.
echo '=== Case 10: .strains MISSING — shape-preflight blocker, exit 1, zero send-keys ==='
BID10="brood-feedface-0000-4000-8000-000000000010"
ROOT10="$WORKDIR/strains-missing"
mkdir -p "$ROOT10/.hivemind/broods/$BID10"
git -C "$ROOT10" init -q
jq -n --arg bid "$BID10" '{
  manifest_version: 4, brood_id: $bid, created_at: "2026-06-21T00:00:00Z",
  hatchery_session: "", base: "main",
  hatchery: { run_id: ($bid + "-hatchery"), ledger: (".hivemind/runs/" + $bid + "-hatchery/state.json"), workflow: "hatchery-dispatch" },
  overlap_risk: "low", overlap_details: "No shared file scopes detected.", merge_order: []
}' > "$ROOT10/.hivemind/broods/$BID10/manifest.json"
ALIVE10="$WORKDIR/alive10"; : > "$ALIVE10"
LOG10="$WORKDIR/log10"; : > "$LOG10"
run_engine "$ROOT10" "$BID10" "$ALIVE10" "$LOG10"
assert_eq "strains-missing:exit" "1" "$RUN_RC" "missing .strains is a pre-flight blocker (no silent empty brood)"
assert_contains "strains-missing:blocker" "shape preflight" "$(cat "${LOG10}.stderr")" "shape-preflight blocker line"
assert_eq "strains-missing:zero-sendkeys" "0" "$(count_records "$LOG10")" "no keystroke when .strains missing"

# ── Case 11: manifest-shape preflight — `.strains` NULL → blocker, zero send-keys ───
# Coherent manifest whose `.strains` is explicitly null. The OLD `.strains // []` turned null into an
# EMPTY brood (silent `0 applied`). The shape preflight BLOCKS: blocker, exit 1, zero send-keys.
echo '=== Case 11: .strains NULL — shape-preflight blocker, exit 1, zero send-keys ==='
BID11="brood-feedface-0000-4000-8000-000000000011"
ROOT11="$WORKDIR/strains-null"
mkdir -p "$ROOT11/.hivemind/broods/$BID11"
git -C "$ROOT11" init -q
jq -n --arg bid "$BID11" '{
  manifest_version: 4, brood_id: $bid, created_at: "2026-06-21T00:00:00Z",
  hatchery_session: "", base: "main",
  hatchery: { run_id: ($bid + "-hatchery"), ledger: (".hivemind/runs/" + $bid + "-hatchery/state.json"), workflow: "hatchery-dispatch" },
  overlap_risk: "low", overlap_details: "No shared file scopes detected.",
  strains: null, merge_order: []
}' > "$ROOT11/.hivemind/broods/$BID11/manifest.json"
ALIVE11="$WORKDIR/alive11"; : > "$ALIVE11"
LOG11="$WORKDIR/log11"; : > "$LOG11"
run_engine "$ROOT11" "$BID11" "$ALIVE11" "$LOG11"
assert_eq "strains-null:exit" "1" "$RUN_RC" "null .strains is a pre-flight blocker (no silent empty brood)"
assert_contains "strains-null:blocker" "shape preflight" "$(cat "${LOG11}.stderr")" "shape-preflight blocker line"
assert_eq "strains-null:zero-sendkeys" "0" "$(count_records "$LOG11")" "no keystroke when .strains null"

# ── Case 12: manifest-shape preflight — `.strains` OBJECT → blocker, zero send-keys ─
# Coherent manifest whose `.strains` is an OBJECT, not an array. The OLD `(.strains // [])[]` iterated
# the object's VALUES — processing a wrong-shaped manifest and potentially delivering `/rc` from a
# bogus shape. The shape preflight requires `.strains` to be an ARRAY: blocker, exit 1, zero send-keys.
echo '=== Case 12: .strains OBJECT — shape-preflight blocker, exit 1, zero send-keys ==='
BID12="brood-feedface-0000-4000-8000-000000000012"
ROOT12="$WORKDIR/strains-object"
mkdir -p "$ROOT12/.hivemind/broods/$BID12"
git -C "$ROOT12" init -q
# `.strains` is an OBJECT whose VALUES look like strain entries — exactly the shape the old jq would
# have iterated. The alive-set even contains the derived sessions, so ONLY the shape gate (not
# liveness) can be what blocks delivery.
jq -n --arg bid "$BID12" '{
  manifest_version: 4, brood_id: $bid, created_at: "2026-06-21T00:00:00Z",
  hatchery_session: "", base: "main",
  hatchery: { run_id: ($bid + "-hatchery"), ledger: (".hivemind/runs/" + $bid + "-hatchery/state.json"), workflow: "hatchery-dispatch" },
  overlap_risk: "low", overlap_details: "No shared file scopes detected.",
  strains: {
    api: { name: "api", tmux_session: ($bid + "-api"), status: "running", pr: null, merged: false, rebased_after: [] }
  },
  merge_order: []
}' > "$ROOT12/.hivemind/broods/$BID12/manifest.json"
ALIVE12="$WORKDIR/alive12"; : > "$ALIVE12"
printf '%s\n' "$BID12-api" > "$ALIVE12"
LOG12="$WORKDIR/log12"; : > "$LOG12"
run_engine "$ROOT12" "$BID12" "$ALIVE12" "$LOG12"
assert_eq "strains-object:exit" "1" "$RUN_RC" "object .strains is a pre-flight blocker (no value-iteration)"
assert_contains "strains-object:blocker" "shape preflight" "$(cat "${LOG12}.stderr")" "shape-preflight blocker line"
assert_eq "strains-object:zero-sendkeys" "0" "$(count_records "$LOG12")" "no keystroke when .strains is an object (values never iterated)"

# ── Case 13: manifest-shape preflight — non-object strain element → blocker, zero ──
# Coherent manifest whose `.strains` IS an array, but one element is a STRING (not an object). The
# shape preflight requires EVERY element to be an object: blocker, exit 1, zero send-keys.
echo '=== Case 13: non-object strain element — shape-preflight blocker, exit 1, zero send-keys ==='
BID13="brood-feedface-0000-4000-8000-000000000013"
ROOT13="$WORKDIR/strain-nonobject"
mkdir -p "$ROOT13/.hivemind/broods/$BID13"
git -C "$ROOT13" init -q
jq -n --arg bid "$BID13" '{
  manifest_version: 4, brood_id: $bid, created_at: "2026-06-21T00:00:00Z",
  hatchery_session: "", base: "main",
  hatchery: { run_id: ($bid + "-hatchery"), ledger: (".hivemind/runs/" + $bid + "-hatchery/state.json"), workflow: "hatchery-dispatch" },
  overlap_risk: "low", overlap_details: "No shared file scopes detected.",
  strains: [ "not-an-object" ],
  merge_order: []
}' > "$ROOT13/.hivemind/broods/$BID13/manifest.json"
ALIVE13="$WORKDIR/alive13"; : > "$ALIVE13"
LOG13="$WORKDIR/log13"; : > "$LOG13"
run_engine "$ROOT13" "$BID13" "$ALIVE13" "$LOG13"
assert_eq "strain-nonobject:exit" "1" "$RUN_RC" "non-object strain element is a pre-flight blocker"
assert_contains "strain-nonobject:blocker" "shape preflight" "$(cat "${LOG13}.stderr")" "shape-preflight blocker line"
assert_eq "strain-nonobject:zero-sendkeys" "0" "$(count_records "$LOG13")" "no keystroke on non-object strain element"

# ── Case 14: shape preflight does NOT regress the empty-array case ─────────────────
# `.strains` is an EMPTY ARRAY — a VALID shape (a brood with zero strains). This must NOT blocker:
# it is the legitimate zero-strain run that exits 0 with a `0 strains` summary and zero send-keys.
# Guards against the preflight over-rejecting the valid empty-array boundary.
echo '=== Case 14: .strains EMPTY ARRAY — valid, exit 0, zero send-keys, 0-strain summary ==='
BID14="brood-feedface-0000-4000-8000-000000000014"
ROOT14="$WORKDIR/strains-empty"
mkdir -p "$ROOT14/.hivemind/broods/$BID14"
git -C "$ROOT14" init -q
jq -n --arg bid "$BID14" '{
  manifest_version: 4, brood_id: $bid, created_at: "2026-06-21T00:00:00Z",
  hatchery_session: "", base: "main",
  hatchery: { run_id: ($bid + "-hatchery"), ledger: (".hivemind/runs/" + $bid + "-hatchery/state.json"), workflow: "hatchery-dispatch" },
  overlap_risk: "low", overlap_details: "No shared file scopes detected.",
  strains: [], merge_order: []
}' > "$ROOT14/.hivemind/broods/$BID14/manifest.json"
ALIVE14="$WORKDIR/alive14"; : > "$ALIVE14"
LOG14="$WORKDIR/log14"; : > "$LOG14"
run_engine "$ROOT14" "$BID14" "$ALIVE14" "$LOG14"
OUT14="$(cat "${LOG14}.stdout")"
assert_eq "strains-empty:exit" "0" "$RUN_RC" "empty .strains array is valid (zero-strain run, not a blocker)"
assert_eq "strains-empty:zero-sendkeys" "0" "$(count_records "$LOG14")" "no keystroke on zero-strain run"
assert_contains "strains-empty:summary" "0 applied, 0 skipped, 0 failed (of 0 strains)" "$OUT14" "zero-strain summary preserved"

# ── Case 9: RC-name collision guard — distinct `short`, distinct /rc names ─────────
# THE FIX'S REGRESSION GUARD. Two strains whose names COLLIDE under the OLD delete-based slug
# (`api/v1` and `apiv1` both deleted `/` -> `apiv1`) but are DISTINCT under the REPLACE-based `short`
# spawn-brood de-dupes: `api/v1` -> `api-v1`, `apiv1` -> `apiv1`. Because the `/rc` payload is now the
# `short` (not the slug), the two strains MUST receive DISTINCT `/rc` names, each into its OWN exact
# `=`-session. Built inline via jq -n (no committed fixture). Both derived sessions are alive.
echo '=== Case 9: RC-name collision guard — distinct short -> distinct /rc names ==='
BID9="brood-feedface-0000-4000-8000-000000000009"
ROOT9="$WORKDIR/rc-collision"
mkdir -p "$ROOT9/.hivemind/broods/$BID9"
git -C "$ROOT9" init -q
# name "api/v1" -> short "api-v1" -> session <bid>-api-v1
# name "apiv1"  -> short "apiv1"  -> session <bid>-apiv1
# Under the OLD slug both names collapsed to "apiv1" (ambiguous /rc). Under `short` they diverge.
jq -n --arg bid "$BID9" '{
  manifest_version: 4,
  brood_id: $bid,
  created_at: "2026-06-21T00:00:00Z",
  hatchery_session: "",
  base: "main",
  hatchery: { run_id: ($bid + "-hatchery"), ledger: (".hivemind/runs/" + $bid + "-hatchery/state.json"), workflow: "hatchery-dispatch" },
  overlap_risk: "low",
  overlap_details: "No shared file scopes detected.",
  strains: [
    {
      name: "api/v1",
      description: "Strain whose name collides with apiv1 under the old delete-slug.",
      worktree_path: ("/repo/.claude/worktrees/" + $bid + "/api-v1"),
      branch: ("strain/" + $bid + "/api-v1"),
      tmux_session: ($bid + "-api-v1"),
      status: "running", pr: null, merged: false, rebased_after: [],
      run: { suggested_id: ($bid + "--api-v1"), workflow_hint: "standard-delivery" }
    },
    {
      name: "apiv1",
      description: "Strain whose name collides with api/v1 under the old delete-slug.",
      worktree_path: ("/repo/.claude/worktrees/" + $bid + "/apiv1"),
      branch: ("strain/" + $bid + "/apiv1"),
      tmux_session: ($bid + "-apiv1"),
      status: "running", pr: null, merged: false, rebased_after: [],
      run: { suggested_id: ($bid + "--apiv1"), workflow_hint: "standard-delivery" }
    }
  ],
  merge_order: []
}' > "$ROOT9/.hivemind/broods/$BID9/manifest.json"
ALIVE9="$WORKDIR/alive9"
LOG9="$WORKDIR/log9"
: > "$LOG9"
printf '%s\n' \
  "$BID9-api-v1" \
  "$BID9-apiv1" > "$ALIVE9"
run_engine "$ROOT9" "$BID9" "$ALIVE9" "$LOG9"
OUT9="$(cat "${LOG9}.stdout")"
LOGTEXT9="$(cat "$LOG9")"
assert_eq "collision:exit" "0" "$RUN_RC" "collision fan-out completes"
PAYLOADS9="$(literal_payloads "$LOG9")"
# DISTINCT /rc names — the whole point of the fix.
assert_contains "collision:rc-api-v1" "/rc api-v1" "$PAYLOADS9" "api/v1 -> distinct /rc api-v1"
assert_contains "collision:rc-apiv1"  "/rc apiv1"  "$PAYLOADS9" "apiv1 -> distinct /rc apiv1"
assert_eq "collision:literal-count" "2" "$(printf '%s\n' "$PAYLOADS9" | grep -c '^/rc ')" "two distinct /rc literals"
# Each into the RESOLVED PANE-ID of its OWN exact-identity session (no bare session-name target).
PANE_APIV1_9="$(pane_id_for "$BID9-api-v1")"
PANE_APIV9="$(pane_id_for "$BID9-apiv1")"
assert_contains "collision:target-api-v1" "ARG:$PANE_APIV1_9" "$LOGTEXT9" "api-v1 addressed at own resolved pane id"
assert_contains "collision:target-apiv1"  "ARG:$PANE_APIV9"   "$LOGTEXT9" "apiv1 addressed at own resolved pane id"
assert_not_contains "collision:no-bare-api-v1" "ARG:$BID9-api-v1" "$LOGTEXT9" "no bare session-name target for api-v1"
assert_not_contains "collision:no-bare-apiv1"  "ARG:$BID9-apiv1"  "$LOGTEXT9" "no bare session-name target for apiv1"
assert_contains "collision:summary" "2 applied, 0 skipped, 0 failed (of 2 strains)" "$OUT9" "both applied, no collision"

# ── Case 15: failed-path stderr surfacing — tmux send-keys error reaches the report ─
# A coherent all-alive manifest, but one strain's send-keys is forced to FAIL (fake tmux exits
# non-zero and prints `can't find pane: <target>` on STDERR for the chosen target). The engine must
# capture that stderr (not swallow it with `2>/dev/null`) and surface it on the `failed:` disposition
# line, count the strain as failed, and STILL complete the fan-out (exit 0) delivering the other two.
echo '=== Case 15: failed-path stderr surfacing — tmux error text on the failed: line ==='
ROOT15="$(new_brood_root sendkeys-fail "$BID1" "$FIXTURES/rc-manifest-all-alive.json")"
ALIVE15="$WORKDIR/alive15"
LOG15="$WORKDIR/log15"
: > "$LOG15"
printf '%s\n' \
  "$BID1-api" \
  "$BID1-web-ui" \
  "$BID1-db-migrations" > "$ALIVE15"
# Force the api strain's send-keys to fail; the engine addresses the RESOLVED PANE-ID of the exact
# session, so the forced-failure target is that pane id (not the bare session name).
TMUX_SENDKEYS_FAIL_TARGET="$(pane_id_for "$BID1-api")"
run_engine "$ROOT15" "$BID1" "$ALIVE15" "$LOG15"
TMUX_SENDKEYS_FAIL_TARGET=""
OUT15="$(cat "${LOG15}.stdout")"
assert_eq "sendkeys-fail:exit" "0" "$RUN_RC" "per-strain send-keys failure does not abort fan-out"
# The engine surfaces the captured tmux stderr text on the api strain's `failed:` line. The stderr
# names the RESOLVED PANE-ID (the send target), so assert that pane id is surfaced.
assert_contains "sendkeys-fail:failed-line" "failed: api" "$OUT15" "api strain recorded failed"
assert_contains "sendkeys-fail:stderr-surfaced" "can't find pane: $(pane_id_for "$BID1-api")" "$OUT15" "tmux stderr text surfaced on failed: line"
# The other two strains still deliver; summary counts the single failure.
assert_contains "sendkeys-fail:db-applied" "applied: db-migrations" "$OUT15" "db strain still delivered"
assert_contains "sendkeys-fail:summary" "2 applied, 0 skipped, 1 failed (of 3 strains)" "$OUT15" "summary counts the failure"

# ── Case 5: summary correctness already asserted per case above ───────────────────
# Cases 1, 2 assert the exact applied/skipped/failed triple; Case 4 asserts the hostile slug path
# still summarises applied=1. Re-assert the hostile summary explicitly for the failed=0 dimension.
echo '=== Case 5: summary correctness — hostile path applied=1 skipped=0 failed=0 ==='
assert_contains "summary:hostile" "1 applied, 0 skipped, 0 failed (of 1 strains)" "$OUT4" "hostile summary counts"

# ── Case 16: sibling-coexistence — exact pane targeted, same-prefix sibling never touched ──
# A COHERENT single-strain manifest (name=api, derived identity <bid>-api). The EXACT session AND a
# same-prefix SIBLING (<bid>-api-x) are BOTH alive. Pane-id targeting resolves the EXACT session's
# active pane id and delivers there; the sibling is NEVER a target (neither its bare name nor its
# pane id) and NEVER receives `/rc`. Under a revert to bare-name addressing this case would still
# deliver to the exact session (exact-first wins), but the pane-id-target assertion below would FAIL
# (a bare-name engine emits a bare target, not the resolved pane id) — so a revert still trips here.
echo '=== Case 16: sibling-coexistence — exact pane targeted, sibling never touched ==='
BID16="brood-feedface-0000-4000-8000-000000000016"
ROOT16="$WORKDIR/sibling-coexist"
mkdir -p "$ROOT16/.hivemind/broods/$BID16"
git -C "$ROOT16" init -q
jq -n --arg bid "$BID16" '{
  manifest_version: 4, brood_id: $bid, created_at: "2026-06-21T00:00:00Z",
  hatchery_session: "", base: "main",
  hatchery: { run_id: ($bid + "-hatchery"), ledger: (".hivemind/runs/" + $bid + "-hatchery/state.json"), workflow: "hatchery-dispatch" },
  overlap_risk: "low", overlap_details: "No shared file scopes detected.",
  strains: [ {
    name: "api",
    description: "Exact strain whose derived identity has a same-prefix sibling alive alongside it.",
    worktree_path: ("/repo/.claude/worktrees/" + $bid + "/api"),
    branch: ("strain/" + $bid + "/api"),
    tmux_session: ($bid + "-api"),
    status: "running", pr: null, merged: false, rebased_after: [],
    run: { suggested_id: ($bid + "--api"), workflow_hint: "standard-delivery" }
  } ],
  merge_order: []
}' > "$ROOT16/.hivemind/broods/$BID16/manifest.json"
ALIVE16="$WORKDIR/alive16"
LOG16="$WORKDIR/log16"
: > "$LOG16"
# Exact identity AND a same-prefix sibling are BOTH alive — proving the targeting primitive, not
# liveness, is what keeps the sibling untouched.
printf '%s\n' \
  "$BID16-api" \
  "$BID16-api-x" > "$ALIVE16"
run_engine "$ROOT16" "$BID16" "$ALIVE16" "$LOG16"
OUT16="$(cat "${LOG16}.stdout")"
LOGTEXT16="$(cat "$LOG16")"
PANE_EXACT16="$(pane_id_for "$BID16-api")"
PANE_SIBLING16="$(pane_id_for "$BID16-api-x")"
assert_eq "sibling-coexist:exit" "0" "$RUN_RC" "fan-out completes"
assert_eq "sibling-coexist:applied-count" "2" "$(count_records "$LOG16")" "exactly one /rc + one Enter delivered"
# The exact session's resolved pane id is the target; the strain is delivered to the EXACT session.
assert_contains "sibling-coexist:exact-pane-target" "ARG:$PANE_EXACT16" "$LOGTEXT16" "exact session pane id targeted"
assert_contains "sibling-coexist:delivered-exact" "DELIVERED-SESSION:$BID16-api" "$LOGTEXT16" "delivered to the exact session"
assert_contains "sibling-coexist:summary" "1 applied, 0 skipped, 0 failed (of 1 strains)" "$OUT16" "exact strain applied"
# The sibling is NEVER a target (neither bare name nor its pane id) and NEVER receives a delivery.
assert_not_contains "sibling-coexist:no-bare-sibling" "ARG:$BID16-api-x" "$LOGTEXT16" "sibling bare name never targeted"
assert_not_contains "sibling-coexist:no-pane-sibling" "ARG:$PANE_SIBLING16" "$LOGTEXT16" "sibling pane id never targeted"
assert_not_contains "sibling-coexist:no-delivery-sibling" "DELIVERED-SESSION:$BID16-api-x" "$LOGTEXT16" "sibling never receives /rc"

# ── Case 16b: pane-gone-at-send — fail-closed, no sibling mis-delivery ─────────────
# The raced-death boundary pane-id targeting exists to close. The EXACT session is alive at the
# liveness gate AND at list-panes (so its pane id resolves), but that pane DIES before the send —
# modeled by placing the resolved pane id in TMUX_PANE_GONE_AT_SEND. A same-prefix SIBLING is alive.
# A pane id has NO prefix fallback, so the send FAILS CLOSED (`can't find pane`), the strain is
# counted FAILED, ZERO `/rc` is delivered to the sibling, and NO bare session-name target is ever
# emitted. CRITICAL REGRESSION: a revert to bare-name addressing would, when the exact session's
# pane is gone, prefix-fall-back to the sibling and DELIVER `/rc` there — tripping the sibling-
# delivery assertion below. (The fake models that exact-first-then-prefix fallback faithfully.)
echo '=== Case 16b: pane-gone-at-send — fail-closed, zero sibling mis-delivery ==='
BID16B="brood-feedface-0000-4000-8000-00000000016b"
ROOT16B="$WORKDIR/pane-gone"
mkdir -p "$ROOT16B/.hivemind/broods/$BID16B"
git -C "$ROOT16B" init -q
jq -n --arg bid "$BID16B" '{
  manifest_version: 4, brood_id: $bid, created_at: "2026-06-21T00:00:00Z",
  hatchery_session: "", base: "main",
  hatchery: { run_id: ($bid + "-hatchery"), ledger: (".hivemind/runs/" + $bid + "-hatchery/state.json"), workflow: "hatchery-dispatch" },
  overlap_risk: "low", overlap_details: "No shared file scopes detected.",
  strains: [ {
    name: "api",
    description: "Exact strain whose resolved pane dies between resolve and send; sibling is alive.",
    worktree_path: ("/repo/.claude/worktrees/" + $bid + "/api"),
    branch: ("strain/" + $bid + "/api"),
    tmux_session: ($bid + "-api"),
    status: "running", pr: null, merged: false, rebased_after: [],
    run: { suggested_id: ($bid + "--api"), workflow_hint: "standard-delivery" }
  } ],
  merge_order: []
}' > "$ROOT16B/.hivemind/broods/$BID16B/manifest.json"
ALIVE16B="$WORKDIR/alive16b"
LOG16B="$WORKDIR/log16b"
: > "$LOG16B"
# Exact identity alive (passes has-session + list-panes) AND a same-prefix sibling alive.
printf '%s\n' \
  "$BID16B-api" \
  "$BID16B-api-x" > "$ALIVE16B"
PANE_EXACT16B="$(pane_id_for "$BID16B-api")"
PANE_SIBLING16B="$(pane_id_for "$BID16B-api-x")"
# The exact session's resolved pane DIES before the send — fail-closed boundary.
TMUX_PANE_GONE_AT_SEND="$PANE_EXACT16B"
run_engine "$ROOT16B" "$BID16B" "$ALIVE16B" "$LOG16B"
TMUX_PANE_GONE_AT_SEND=""
OUT16B="$(cat "${LOG16B}.stdout")"
LOGTEXT16B="$(cat "$LOG16B")"
assert_eq "pane-gone:exit" "0" "$RUN_RC" "per-strain fail-closed does not abort fan-out"
# The send fails CLOSED with the tmux can't-find-pane error surfaced on the failed: line.
assert_contains "pane-gone:failed-line" "failed: api" "$OUT16B" "strain recorded failed (fail-closed)"
assert_contains "pane-gone:cant-find-pane" "can't find pane: $PANE_EXACT16B" "$OUT16B" "raced pane-death surfaced on failed: line"
assert_contains "pane-gone:summary" "0 applied, 0 skipped, 1 failed (of 1 strains)" "$OUT16B" "strain counted failed, none applied"
# ZERO /rc delivered anywhere — nothing logged on a fail-closed send.
assert_eq "pane-gone:zero-sendkeys" "0" "$(count_records "$LOG16B")" "no keystroke delivered on raced pane death"
# The sibling is NEVER mis-delivered to (the regression a revert to bare-name addressing would trip).
assert_not_contains "pane-gone:no-delivery-sibling" "DELIVERED-SESSION:$BID16B-api-x" "$LOGTEXT16B" "sibling never receives mis-delivered /rc"
assert_not_contains "pane-gone:no-pane-sibling" "ARG:$PANE_SIBLING16B" "$LOGTEXT16B" "sibling pane id never targeted"
# No bare session-name target is ever emitted (neither exact nor sibling).
assert_not_contains "pane-gone:no-bare-exact" "ARG:$BID16B-api" "$LOGTEXT16B" "exact session bare name never targeted"
assert_not_contains "pane-gone:no-bare-sibling" "ARG:$BID16B-api-x" "$LOGTEXT16B" "sibling bare name never targeted"

# ── Case 17: multi-active-row fail-closed — >1 active pane resolves to NO send ─────
# THE STEP-001 RESOLVER REGRESSION GUARD. The send-time resolver consumes ALL list-panes rows and
# counts the active (`11`) rows, requiring EXACTLY ONE. A coherent single-strain manifest (name=api,
# derived identity <bid>-api) whose EXACT session is placed in TMUX_MULTI_ACTIVE so list-panes returns
# TWO active rows (active_count=2). The resolver fails CLOSED: `failed:` disposition carrying the
# `expected exactly one active pane` substring, ZERO send-keys (it never selects one of the two), the
# strain counted failed, and the fan-out still exits 0 (a per-strain resolution failure is not fatal).
# A revert to break-on-first (select the first `11` row) would silently pick one pane and DELIVER `/rc`
# — tripping the zero-send assertion below.
echo '=== Case 17: multi-active-row fail-closed — >1 active pane, zero send ==='
BID17="brood-feedface-0000-4000-8000-000000000017"
ROOT17="$WORKDIR/multi-active"
mkdir -p "$ROOT17/.hivemind/broods/$BID17"
git -C "$ROOT17" init -q
jq -n --arg bid "$BID17" '{
  manifest_version: 4, brood_id: $bid, created_at: "2026-06-21T00:00:00Z",
  hatchery_session: "", base: "main",
  hatchery: { run_id: ($bid + "-hatchery"), ledger: (".hivemind/runs/" + $bid + "-hatchery/state.json"), workflow: "hatchery-dispatch" },
  overlap_risk: "low", overlap_details: "No shared file scopes detected.",
  strains: [ {
    name: "api",
    description: "Coherent strain whose exact session reports >1 active pane (resolver must fail closed).",
    worktree_path: ("/repo/.claude/worktrees/" + $bid + "/api"),
    branch: ("strain/" + $bid + "/api"),
    tmux_session: ($bid + "-api"),
    status: "running", pr: null, merged: false, rebased_after: [],
    run: { suggested_id: ($bid + "--api"), workflow_hint: "standard-delivery" }
  } ],
  merge_order: []
}' > "$ROOT17/.hivemind/broods/$BID17/manifest.json"
ALIVE17="$WORKDIR/alive17"
LOG17="$WORKDIR/log17"
: > "$LOG17"
printf '%s\n' "$BID17-api" > "$ALIVE17"
# The exact session reports TWO active (`11`) panes — the anomaly the resolver must reject.
TMUX_MULTI_ACTIVE="$BID17-api"
run_engine "$ROOT17" "$BID17" "$ALIVE17" "$LOG17"
TMUX_MULTI_ACTIVE=""
OUT17="$(cat "${LOG17}.stdout")"
assert_eq "multi-active:exit" "0" "$RUN_RC" "per-strain resolution failure does not abort fan-out"
assert_contains "multi-active:failed-line" "failed: api" "$OUT17" "strain recorded failed"
assert_contains "multi-active:expected-one" "expected exactly one active pane" "$OUT17" "multi-active fails closed with the exactly-one-active-pane error"
assert_contains "multi-active:summary" "0 applied, 0 skipped, 1 failed (of 1 strains)" "$OUT17" "strain counted failed, none applied"
assert_eq "multi-active:zero-sendkeys" "0" "$(count_records "$LOG17")" "no keystroke delivered when >1 active pane (never selects one)"

# ── Case 18a: --only selects one strain — the selected short is delivered ─────────
# The 3-strain all-alive manifest with `--only db-migrations`: only that strain gets `/rc`; api and
# web-ui are skipped as not selected with zero send-keys, even though their sessions are alive.
echo '=== Case 18a: --only selected short delivered, unselected strains skipped ==='
ROOT18A="$(new_brood_root only-selected "$BID1" "$FIXTURES/rc-manifest-all-alive.json")"
ALIVE18A="$WORKDIR/alive18a"
LOG18A="$WORKDIR/log18a"
: > "$LOG18A"
printf '%s\n' \
  "$BID1-api" \
  "$BID1-web-ui" \
  "$BID1-db-migrations" > "$ALIVE18A"
run_engine "$ROOT18A" "$BID1" "$ALIVE18A" "$LOG18A" --only db-migrations
OUT18A="$(cat "${LOG18A}.stdout")"
LOGTEXT18A="$(cat "$LOG18A")"
PAYLOADS18A="$(literal_payloads "$LOG18A")"
assert_eq "only-selected:exit" "0" "$RUN_RC" "selected fan-out completed"
assert_eq "only-selected:record-count" "2" "$(count_records "$LOG18A")" "one literal + one Enter for the selected strain"
assert_eq "only-selected:payload" "/rc db-migrations" "$PAYLOADS18A" "only the selected short is delivered"
assert_contains "only-selected:target" "ARG:$(pane_id_for "$BID1-db-migrations")" "$LOGTEXT18A" "selected strain addressed at its resolved pane id"
assert_contains "only-selected:applied" "applied: db-migrations" "$OUT18A"
assert_contains "only-selected:summary" "1 applied, 2 skipped, 0 failed (of 3 strains)" "$OUT18A" "summary counts"

# ── Case 18b: --only — an unselected strain is skipped with zero send-keys ───────
# Same run as 18a, asserted from the unselected side: one `skipped: <short> (not selected)` line per
# unselected strain and no keystroke addressed to either of their panes.
echo '=== Case 18b: --only unselected strain skipped, zero send-keys to it ==='
assert_contains "only-unselected:skip-api"   "skipped: api (not selected)"    "$OUT18A" "api skipped as not selected"
assert_contains "only-unselected:skip-webui" "skipped: web-ui (not selected)" "$OUT18A" "web-ui skipped as not selected"
assert_eq "only-unselected:skip-api-once" "1" "$(grep -c '^skipped: api ' <<<"$OUT18A")" "exactly one skip line for api"
assert_not_contains "only-unselected:no-payload-api"   "/rc api"    "$PAYLOADS18A" "unselected api never receives /rc"
assert_not_contains "only-unselected:no-payload-webui" "/rc web-ui" "$PAYLOADS18A" "unselected web-ui never receives /rc"
assert_not_contains "only-unselected:no-pane-api"   "ARG:$(pane_id_for "$BID1-api")"    "$LOGTEXT18A" "unselected api pane never targeted"
assert_not_contains "only-unselected:no-pane-webui" "ARG:$(pane_id_for "$BID1-web-ui")" "$LOGTEXT18A" "unselected web-ui pane never targeted"

# ── Case 18c: --only with a bad short → pre-flight blocker, zero send-keys ────────
# A short outside ^[a-z0-9-]+$ (uppercase, then a shell metacharacter, then empty) is rejected before
# the manifest is read: blocker on stderr, exit 1, send-keys log EMPTY. The good short listed first
# proves the whole selection is validated before any delivery.
echo '=== Case 18c: --only bad short — blocker, exit 1, zero send-keys ==='
for bad_short in 'API' 'api;touch' ''; do
  ROOT18C="$(new_brood_root "only-bad-$RANDOM" "$BID1" "$FIXTURES/rc-manifest-all-alive.json")"
  ALIVE18C="$WORKDIR/alive18c"
  LOG18C="$WORKDIR/log18c"
  : > "$LOG18C"
  printf '%s\n' "$BID1-api" "$BID1-web-ui" "$BID1-db-migrations" > "$ALIVE18C"
  run_engine "$ROOT18C" "$BID1" "$ALIVE18C" "$LOG18C" --only api "$bad_short"
  assert_eq "only-bad[$bad_short]:exit" "1" "$RUN_RC" "bad short is a pre-flight blocker"
  assert_contains "only-bad[$bad_short]:blocker" "blocker: --only short must match" "$(cat "${LOG18C}.stderr")" "blocker line on stderr"
  assert_eq "only-bad[$bad_short]:zero-sendkeys" "0" "$(count_records "$LOG18C")" "no keystroke delivered on a bad short"
  assert_eq "only-bad[$bad_short]:no-stdout" "" "$(cat "${LOG18C}.stdout")" "no disposition lines before the blocker"
done

# ── Case 18d: --only with no shorts → nothing sent, exit 0, 0 applied ─────────────
echo '=== Case 18d: --only with no shorts — zero send-keys, exit 0, 0 applied ==='
ROOT18D="$(new_brood_root only-empty "$BID1" "$FIXTURES/rc-manifest-all-alive.json")"
ALIVE18D="$WORKDIR/alive18d"
LOG18D="$WORKDIR/log18d"
: > "$LOG18D"
printf '%s\n' "$BID1-api" "$BID1-web-ui" "$BID1-db-migrations" > "$ALIVE18D"
run_engine "$ROOT18D" "$BID1" "$ALIVE18D" "$LOG18D" --only
OUT18D="$(cat "${LOG18D}.stdout")"
assert_eq "only-empty:exit" "0" "$RUN_RC" "empty selection completes"
assert_eq "only-empty:zero-sendkeys" "0" "$(count_records "$LOG18D")" "no keystroke delivered with an empty selection"
assert_contains "only-empty:summary" "0 applied, 3 skipped, 0 failed (of 3 strains)" "$OUT18D" "summary reports 0 applied"
assert_contains "only-empty:skip-db" "skipped: db-migrations (not selected)" "$OUT18D" "every strain skipped as not selected"

# ── Tally ─────────────────────────────────────────────────────────────────────────
echo
echo "test_rc_brood: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
