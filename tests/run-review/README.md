# tests/run-review

Fixture home for `tools/test_run_review.sh`, the offline behavioral runner for
`plugin/skills/adaptation-cycle/scripts/run-review.sh` (issue #581, ADR-0042).
The suite needs only bash, git, jq and a sha256 tool. It builds every input it
uses inside a mktemp dir, so this directory holds no fixture files. It exists so
`tools/validate.sh --changed` can route `tests/run-review/**` to the suite.

Each case runs the real, unmodified script from a scratch git repository. The
repository's `feature` branch changes one file, adds one and deletes one against
`main`, and every case passes `--base main`. Two more repositories add one file
on top: MID, a review input of about 100 KiB (over 65536 and under 262144
bytes), and HUGE, about 300 KiB (over 262144 bytes). Each file opens and closes
with its own marker line, and the suite checks each diff size before any case
runs. The suite controls only four settings:

- `PATH`: a fake-tool directory comes first. It holds a pass-through `timeout`,
  or one that exits 124 or 137, and a fake `node` that runs the companion with
  bash and logs its argv. The pass-through `timeout` (and `gtimeout`) requires `-k`, `5` and an
  all-digit deadline, logs its argv and the epoch second of its call, then runs
  the rest. The host `PATH` follows for git and jq. The curated cases replace
  the host `PATH` with symlinks to the host tools the script and the fakes call,
  without `timeout` or `gtimeout`. A slow fake `git` sleeps 3 seconds on the
  snapshot's `ls-files --others`, then runs the real git. In the cleanup
  cases a fake `mktemp` answers the work-folder call with an existing decoy
  path, either exiting 1 or exiting 0 with a non-empty decoy, and passes every
  other call to the real `mktemp`.
- `TMPDIR`: a scratch folder under the suite's mktemp dir, where the script
  makes its work folder.
- `HOME`: a scratch home. Only the preset cases put a fake Codex companion under
  `.claude/plugins/cache/openai-codex/codex/<version>/scripts/`. It records its
  argv and stdin and prints a reply in the `task --json` shape.
- `HIVEMIND_LOCAL_REVIEWER`: unset, empty, `codex-plugin`, a malformed value, or
  a JSON argv that names a fake reviewer script. The fake reviewer reads its
  action, capture directory and reply file from its own argv.

No real reviewer runs: no codex, no copilot and no real node.

Covered behavior:

- Prompt delivery: one `{prompt}` argv element with empty stdin, or the prompt on
  stdin. Both modes get the same prompt, and the focus text is trimmed and never
  run.
- Skip reasons: `no-reviewer`, `bad-setting`, `tool-missing` (exit 127, exit 126,
  a missing preset companion, and no `timeout` or `gtimeout` on `PATH`, where the
  reviewer never runs, `no-reviewer` still comes first and `tool-missing` comes
  before `too-large`), `tool-failed` with its `stderr_excerpt` line, `timed-out`
  (exit 124 and 137) and `too-large`.
- Input limits, each on both sides: MID is skipped as `too-large` for a
  `{prompt}` argv (65536 bytes) and is inlined whole on stdin and for the preset
  (262144 bytes), both marker lines in the prompt and no too-large-to-inline
  text. HUGE is skipped on stdin and for the preset. A skipped run prints
  exactly `skipped: too-large`, runs no reviewer, no `node` and no `timeout`,
  leaves its `TMPDIR` empty, writes no `.hivemind` folder and leaves
  `git status --porcelain` empty. No exact-boundary case: it would need a copy
  of the script's input builder.
- Deadline: the reviewer runs only under `-k 5 <deadline>`, with `gtimeout` when
  `timeout` is missing. A fast run's deadline is an integer from 500 to 563. The
  call second, the deadline and the 5-second grace stay within the 570-second
  budget plus one second. A before-snapshot slowed by 3 seconds lowers the
  deadline to 554 or less.
- Output shape: the review is taken by the first rule that yields one JSON
  object: the whole reply, the inside of its one ```` ```json ```` or plain
  fence, or the span from the first `{` to the last `}` with no bracket or brace
  outside it. Bare JSON, one fence, prose before or after an object or a fence,
  non-ASCII prose and a fence with no line break are accepted. Two fences, two
  objects, a fenced array, prose holding a bracket or a brace, empty output, an
  array and schema violations are blocked; `raw_excerpt` is checked on a blocked
  reply.
- Findings: a finding on a file the diff does not change is dropped and counted.
  A finding on any line of a changed or added file is kept. Each `finding_id` is
  checked against a precomputed SHA-256 digest of the JSON array text
  `[file, line_start, line_end, title]`. Four findings whose old run-together
  texts collide in pairs, such as lines 1-123 and 11-23, get four distinct ids.
- Work tree: a tracked edit, a new untracked file and a HEAD move are each
  blocked, and the change stays in place.
- HEAD anchor: a commit made after the script reads HEAD and before its
  before-snapshot is blocked as `cannot compute the branch diff`, and the
  reviewer never runs.
- No repository write: normal, preset and too-large runs leave no `.hivemind`
  folder. An old `.hivemind/review-loop/review-diff.patch` is left unchanged
  and alone.
- Preset: `node` gets exactly `<companion> task --json` and the companion
  exactly `task --json`. Its stdin carries the prompt, equal to the generic
  prompt. A focus, even one starting with `-`, lands in the prompt and never in
  argv. The newest companion by mtime runs. A string `.rawOutput` is read by the
  same output shape rules: bare JSON, prose or a fence is accepted, two objects,
  a non-string `.rawOutput`, no `.rawOutput` or a `.result` object with no
  `.rawOutput` give the shape blocker, and a review breaking the schema gives
  the schema blocker.
- Cleanup: when the work-folder `mktemp` fails but prints an existing path, or
  exits 0 with a non-empty folder, the run is blocked and the decoy and its
  sentinel file survive. A normal run and a too-large run leave their `TMPDIR`
  empty. After every case, the shared `TMPDIR` holds no `run-review.*` folder.
- Static checks: `run-review.sh` holds no recursive `rm` (`-r`, `-R`, `-rf`,
  `-fr` or `--recursive`), every `$work_dir/<name>` it writes is in its
  `WORK_FILE_NAMES` list (snapshot prefixes by each `<prefix>.<suffix>`), and
  it names no `.hivemind/` path and no `containment.sh`. Each check is also run
  on a copy with an appended violation, which it must flag.
