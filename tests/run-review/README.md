# tests/run-review

Fixture home for `tools/test_run_review.sh`, the offline behavioral runner for
`plugin/skills/adaptation-cycle/scripts/run-review.sh` (issue #581, ADR-0042).
The suite needs only bash, git, jq and a sha256 tool. It builds every input it
uses inside a mktemp dir, so this directory holds no fixture files. It exists so
`tools/validate.sh --changed` can route `tests/run-review/**` to the suite.

Each case runs the real, unmodified script from a scratch git repository. The
repository's `feature` branch changes one file, adds one and deletes one against
`main`, and every case passes `--base main`. The suite controls only three
settings:

- `PATH`: a fake-tool directory comes first. It holds a pass-through `timeout`
  that checks its `-k 5 590` prefix, or one that exits 124 or 137, and a fake
  `node` that runs the companion with bash. The host `PATH` follows for git and
  jq.
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
- Skip reasons: `no-reviewer`, `bad-setting`, `tool-missing` (exit 127, exit 126
  and a missing preset companion), `tool-failed` with its `stderr_excerpt` line,
  and `timed-out` (exit 124 and 137).
- Output shape: bare JSON and one `json` fence are accepted. Prose, two fences,
  two objects, empty output and schema violations are blocked.
- Findings: a finding on a file the diff does not change is dropped and counted.
  A finding on any line of a changed or added file is kept. Each `finding_id` is
  checked against a precomputed SHA-256 digest.
- Work tree: a tracked edit, a new untracked file and a HEAD move are each
  blocked, and the change stays in place.
- Large diff: the patch file exists while the reviewer runs, the prompt points at
  it, and it is gone after the run.
- Preset: the companion's argv, focus handling, the newest companion by mtime,
  and the `.result` object.
