# tests/design-review

Fixture home for `tools/test_design_review.sh`, the offline behavioral runner for
the record verify library `plugin/skills/_shared/record-verify.sh` and the
design review engine `plugin/skills/design-review/scripts/design-review.sh`
(issue #619, ADR-0046). Each file's header holds its full contract; this file
describes how the suite tests them.

The suite needs only bash, git and jq. It builds every commit in a scratch
repository with plumbing (`hash-object`, `update-index --index-info`,
`write-tree`, `mktree`, `commit-tree`), so every tree entry mode is exact. A
recording `git` wrapper first on `PATH` logs each git argv. A recording `gh`
stub beside it logs each call and exits 1, and the suite fails when any case
called it. `HOME` points into the scratch space and `GIT_CONFIG_NOSYSTEM` is
set, so no user or system git config reaches a case.

Each library case sources the readiness check library, then the record verify
library, in a fresh `bash -c` twice, once under `set -euo pipefail` and once
under `set -u` alone, and both runs must give the same stdout, stderr and exit
status. In every verify case, each git argv the library runs must start with
`--no-replace-objects --literal-pathspecs`.

## cases.json

One object with five keys.

- `docs`: the shared documents, a map from repository path to content. Every
  commit starts from them: the demo and other PRDs and solution designs, the
  demo initiative's `notes.md` and both UI prototype files,
  `docs/references/recorded.md`, `docs/adr/0001-existing.md` and `README.md`.
- `verify`: record verify cases.
- `stamps`: `design-review.sh stamps` cases.
- `round`: `design-review.sh round` cases, each run with `--slug demo`.
- `diff`: `design-review.sh diff` cases.

### Specs

A commit is given as a spec, `{docs, records, objects}`, each key optional:

- `docs` overrides the shared documents; `null` deletes a path.
- `records` is a list of review records, each written at its `path`, by default
  `docs/initiatives/demo/review-record.md`. A record is `raw` text, or it is
  built from `stamps`, `verdict` (default `pass`), `open` (default all 0),
  `rounds` (default 2), `clean_round` (default true), `findings` (rows of six
  cells) or `findings_raw` (the Findings section's text), `extra` (text appended
  after the last section) and `crlf` (every line ending CRLF). A stamp is a path,
  stamped with its blob in the same commit; `{path, base: true}`, stamped with
  its blob in the shared documents; or `{path, blob}`. The default stamps are the
  PRD and the solution design of the record's slug.
- `objects` turns a path into a `symlink` (to `target`), a `gitlink`, a `tree`
  (the file moves to `<path>/child.md`) or a `symlinked-dir` (the folder moves
  to `target` and a symlink takes its place), or a `graft` writes `text` at a
  path the index refuses, such as one with a `.git` part.

In a document, `{{blob:<path>}}` renders as the blob id of `<path>` in the same
spec before any object change, and `{{base:<path>}}` as its blob id in the
shared documents.

### verify

Each case has a `name`, a `head` spec and an `expect` object, plus an optional
`base` spec (default `{}`, the shared documents alone), an optional `tip` spec
(default the base spec) and an optional `exists` list. `expect.pr` and
`expect.merge` list the record paths that must fail, sorted; an empty list
means exit 0 with no output. `pr` runs `hivemind_record_verify <head> <base>`,
and then `design-review.sh verify`, which must relay the same result. `merge`
runs `hivemind_record_verify_merge <head> <base> <tip>`. Each `exists` path must
pass the Document existence test at the head, so a case that fails on it fails
for its rule, not for a missing file.

### stamps, round, diff

- A `stamps` case runs `stamps --commit <head> <paths>...` and gives either
  `expect`, the output lines with placeholders rendered against the head, or
  `error`, the usage token printed with no git call.
- A `round` case gives `expect`, the exact output lines.
- A `diff` case gives `from` and `to` specs and an optional `cwd` under the
  scratch work tree. With `names` true, `expect` is the exact `--names` output.
  Otherwise `holds` lists exact lines the unified diff must hold, `lacks` text
  it must not hold, and `empty` true means no output at all.

## Cases in the script

Cases that need no documents run from the script itself:

- verify errors: `usage`, `commit-malformed` (with no git call),
  `commit-unresolvable`, `missing-readiness-lib` and `git-failed` (a deleted
  tree object), each with stdout empty, and the relay of each through the
  script, and the script's own `usage` cases;
- the `stamps`, `round` and `diff` argument errors, and `jq-missing`;
- `head`: `ok`, `dirty` (untracked or modified, checked before `moved`) and
  `moved`, in a scratch repository with a work tree;
- `model`: unset, empty, valid values and malformed ones, which print
  `model=default` and `setting=invalid` and never the value;
- `plugin/skills/design-review/SKILL.md` and
  `plugin/skills/design-review/references/record-format.md` hold no
  `engineering-principles` reference and no principle id;
- no case called `gh`.
