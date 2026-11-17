# tests/run-review

Fixture home for `tools/test_run_review.sh`, the offline behavioral runner for
`plugin/skills/adaptation-cycle/scripts/run-review.sh` (issue #581, ADR-0042).
The suite needs only bash, git, jq and a sha256 tool. It builds every input it
uses inside a mktemp dir, so this directory holds no fixture files. It exists so
`tools/validate.sh --changed` can route `tests/run-review/**` to the suite.

Each case runs the real, unmodified script from a scratch git repository. The
repository's `feature` branch changes one file, adds one and deletes one against
`main`, and every case passes `--base main`. The suite controls only four
settings:

- `PATH`: a fake-tool directory comes first. It holds a pass-through `timeout`,
  or one that exits 124 or 137, and a fake `node` that runs the companion with
  bash. The pass-through `timeout` (and `gtimeout`) requires `-k`, `5` and an
  all-digit deadline, logs its argv and the epoch second of its call, then runs
  the rest. The host `PATH` follows for git and jq. The curated cases replace
  the host `PATH` with symlinks to the host tools the script and the fakes call,
  without `timeout` or `gtimeout`. A slow fake `git` sleeps 3 seconds on the
  snapshot's `ls-files --others`, then runs the real git. In the cleanup
  cases a fake `mktemp` answers the work-folder call or the large-diff call
  with an existing decoy path, either exiting 1 or exiting 0 with a non-empty
  decoy, and passes every other call to the real `mktemp`.
- `TMPDIR`: a scratch folder under the suite's mktemp dir, where the script
  makes its work folder.
- `HOME`: a scratch home. Only the preset cases put a fake Codex companion under
  `.claude/plugins/cache/openai-codex/codex/<version>/scripts/`.
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
  reviewer never runs and `no-reviewer` still comes first), `tool-failed` with
  its `stderr_excerpt` line, and `timed-out` (exit 124 and 137).
- Deadline: the reviewer runs only under `-k 5 <deadline>`, with `gtimeout` when
  `timeout` is missing. A fast run's deadline is an integer from 500 to 563. The
  call second, the deadline and the 5-second grace stay within the 570-second
  budget plus one second. A before-snapshot slowed by 3 seconds lowers the
  deadline to 554 or less.
- Output shape: bare JSON and one `json` fence are accepted. Prose, two fences,
  two objects, empty output and schema violations are blocked.
- Findings: a finding on a file the diff does not change is dropped and counted.
  A finding on any line of a changed or added file is kept. Each `finding_id` is
  checked against a precomputed SHA-256 digest of the JSON array text
  `[file, line_start, line_end, title]`. Four findings whose old run-together
  texts collide in pairs, such as lines 1-123 and 11-23, get four distinct ids.
- Work tree: a tracked edit, a new untracked file and a HEAD move are each
  blocked, and the change stays in place.
- Large diff: the patch file exists while the reviewer runs, the prompt points at
  it, and it is gone after the run.
- Preset: the companion's argv, focus handling, the newest companion by mtime,
  and the `.result` object.
- Cleanup: when the work-folder or the large-diff `mktemp` fails but prints an
  existing path, or exits 0 with a non-empty folder or file, the run is blocked
  and the decoy and its sentinel file survive. A normal run and a large-diff run
  leave their `TMPDIR` empty and no large-diff file. After every case, the
  shared `TMPDIR` holds no `run-review.*` folder.
- Static checks: `run-review.sh` holds no recursive `rm` (`-r`, `-R`, `-rf`,
  `-fr` or `--recursive`), and every `$work_dir/<name>` it writes is in its
  `WORK_FILE_NAMES` list (snapshot prefixes by each `<prefix>.<suffix>`). Each
  check is also run on a copy with an appended violation, which it must flag.
