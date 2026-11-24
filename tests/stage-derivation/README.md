# tests/stage-derivation

Fixture home for `tools/test_stage_derivation.sh`, the offline behavioral runner
for the stage derivation library `plugin/skills/_shared/stage-derivation.sh`
(issue #621, ADR-0046). The library's header holds its full contract, the
evidence JSON v1 and the precedence; this file describes how the suite tests it.

The suite needs only bash, git and jq. It builds every commit in a scratch
repository with plumbing (`hash-object`, `update-index --index-info`,
`write-tree`, `mktree`, `commit-tree`), so every tree entry mode is exact. A
case's docs head commit has its trunk commit as parent, so the merge-base that
verify reads is real. A recording `git` wrapper first on `PATH` logs each git
argv. A recording `gh` stub beside it logs each call and exits 1, and the suite
fails when any case called it. `HOME` points into the scratch space and
`GIT_CONFIG_NOSYSTEM` is set, so no user or system git config reaches a case.

Each call sources the readiness check library, the record verify library and the
stage derivation library, in that order, in a fresh `bash -c` twice, once under
`set -euo pipefail` and once under `set -u` alone, and both runs must give the
same stdout, stderr and exit status. Every git argv a case runs must start with
`--no-replace-objects --literal-pathspecs`.

## docs.json

A map from a document name to its content: PRDs whose `**UI:**` line is `yes`,
`no`, `maybe` or missing, another initiative's PRD, a solution design and a
delivered one, the UI prototype's `index.html`, `notes.md` with no `## Verdict`
section, with an empty one and with a filled one (CRLF), and a malformed review
record.

## cases.json

A list of cases. Each has a `name`, a `trunk` spec and either `expect` or
`error`.

### Specs

`trunk` builds the trunk commit. `docs`, when present, builds the docs head
commit, with the trunk commit as parent. A spec is `{docs, records, objects}`,
each key optional:

- `docs` maps a repository path to a `docs.json` name. A docs spec starts from
  the trunk spec's documents; `null` deletes a path.
- `records` is a list of review records, each written at its `path`, by default
  `docs/initiatives/demo/review-record.md`. A docs spec without `records` keeps
  the trunk spec's. A record is `{raw: <docs.json name>}`, or it is built from
  `stamps`, `verdict` (default `pass`), `open` (default all 0), `rounds` (default
  2) and `clean_round` (default true), with a Findings table of one fixed low
  row. A stamp is a path, stamped with the blob of its document in the same
  spec, or `{path, doc}`, stamped with the blob of the `docs.json` document
  `doc`, so a stale stamp names other content. The default stamps are the PRD
  and the solution design of the record's slug.
- `objects` turns a path into a `symlink` (to `target`), a `gitlink`, a `tree`
  (the file moves to `<path>/child.md`) or a `symlinked-dir` (the folder moves
  to `target` and a symlink takes its place). A docs spec carries only its own
  objects.

### Evidence

`evidence` is shorthand for evidence JSON v1, expanded by the suite:

- `seeds` defaults to one open seed, issue 1, by a writer, whose body opens
  with the demo marker and a CRLF line ending; a seed entry defaults `state`,
  `author_can_write` and `body` the same way.
- A `pull_requests` entry defaults to an open `docs/demo` pull request from
  `acme/widgets` by a writer, not a draft, whose head is the docs head commit.
- A `branches` entry defaults to the docs head commit, used by no pull request.
- A `slices` entry is an open slice under issue 1 whose labels hold every rating
  family; `rated` false keeps only the type label, and `labels_truncated` true
  sets `hasNextPage`. The epic defaults to issue 1 with one sub-issue per slice.
- `version` and `epic` may be given to break the evidence.

`evidence_raw` instead gives the stdin bytes verbatim.

Placeholders in evidence, arguments and `expect`: `{{trunk}}` and `{{docs}}`
are the case's commits, `{{short}}` the trunk's 7-hex prefix, `{{upper}}` the
trunk in capitals and `{{unfetched}}` a well-formed id of no object.

### Arguments and expectations

Derive runs with the trunk commit, `acme/widgets`, `main` and `demo`, unless
`trunk_arg`, `repo_arg`, `trunk_name_arg` or `slug_arg` overrides one.

- `expect` gives `stage`, `status`, `next` and `reasons`, compared exactly, and
  `ignored`, compared exactly and empty by default. `seed`, `docs` and `slices`
  are compared when given. The output must be one compact object with the
  contract's keys in order, naming the slug and the trunk commit.
- `error` gives the failure token: exit 2, stdout empty and exactly one stderr
  line. `no_git` true also asserts no git call.
- `lacks` lists text stdout must not hold, and `no_git_text` text no git argv
  may hold.

## Cases in the script

Cases that need no fixture run from the script itself: the library's form (no
shebang, no `BASH_SOURCE`, no sourced file, the `P18 FLOOR EXCEPTION` marker,
no `gh` command, `bash -n`, and sourcing twice changes no option or variable),
argument-count `usage` with no git call, `missing-library` with no git call,
`git-failed` for a deleted tree object, the same result from a subdirectory
working directory, and that no case called `gh`.
