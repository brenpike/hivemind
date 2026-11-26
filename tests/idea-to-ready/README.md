# tests/idea-to-ready

Fixture home for `tools/test_idea_to_ready.sh`, the offline behavioral runner
for the guide skill's engine script
`plugin/skills/idea-to-ready/scripts/idea-to-ready.sh` (issue #622, ADR-0046).
The script's header holds its full contract; this file describes how the suite
tests it.

The suite needs only bash, git and jq. It never reaches GitHub or the network.

## How a case runs

1. Each scenario of `cases.json` is built once: its commits are made in a
   scratch build repository with plumbing (`hash-object`,
   `update-index --index-info`, `write-tree`, `commit-tree`), so every tree
   entry mode is exact, then pushed to a scratch bare repository, the
   scenario's remote.
2. Each case clones that remote into its own folder: by default a fresh
   single-branch clone of `main`, with no docs branch, so the script's own
   fetches of the trunk and the docs head are what bring those commits in.
   `clone` checks out a docs branch instead, `detach` then detaches HEAD at a
   commit, and `dirty` adds an untracked file.
3. The case's inputs files and symlinks are written into the clone, its routes
   are rendered into a routes file, and the script runs from the clone (or
   from `cwd` under it) with the recording wrappers first on `PATH`.
4. The suite asserts the exit status, stdout and stderr, the posted bodies, the
   gh calls made or not made, and that every git call carries
   `--no-replace-objects` (or that none ran).

A recording `gh` stub logs each argv as one line of `<arg>` fields, copies the
file after each `--body-file` so the posted body can be compared, and serves
the first route whose args all match; an unrouted call exits 1. A recording
`git` wrapper logs each git argv. After every case the suite asserts that no gh
argv of any case, the libraries' own calls included, holds `readiness:ready`
and that no gh call writes a label.

## cases.json

One object with three keys.

- `docs`: documents by name, each a template. `{{slug}}` renders to the
  scenario's slug and `{{blob:<name>}}` to the blob id of the named document
  rendered for that slug, so a review record's stamps match its documents.
- `scenarios`: remotes by name. Each has a `slug`, a `trunk` tree, a `docs`
  list of commits and the `branches` to push besides `main`. A tree maps a
  path (with `{{slug}}`) to a document name, `{"symlink": "<target>"}` (mode
  120000), `{"gitlink": true}` (a submodule entry, mode 160000) or `null`
  (removed). Each docs commit is `{"parent": <i>, "set": <tree>}`: the tree of
  commit `<i>` (0 is the trunk commit) with `set` applied, committed with that
  parent. `branches` maps a branch name to a docs commit index.
  - `alpha`: an initiative with `**UI:** no`. Docs commit 1 adds the PRD and
    the solution design; 2 adds a passing record and an ADR (branch
    `docs/alpha`); 3 edits the design after the clean pass
    (`docs/alpha-stale`); 4 replaces the record with a failing one whose veto
    section is empty (`docs/alpha-fail`).
  - `beta`: a UI initiative. Commit 1 holds the PRD, the prototype variants
    and notes with no Verdict; 2 folds `index.html`, writes the Verdict and adds
    the design and an ADR (`docs/beta`).
  - `gamma`: a UI initiative whose `notes.md` is a symlink and whose ADR
    `0101` is a submodule entry, beside a regular ADR `0102`.
  - `omega`: a passing initiative on trunk whose docs branch only marks the
    design delivered (a close-out pull request that does not edit the record).
- `cases`: one object per case.
  - `name`, `scenario`, `args` (the script's argv), `routes` (route names from
    `gh-routes.json`).
  - `expect`: `rc`, and optionally exact `stdout` and `stderr` and a
    `stdout_has` list of substrings.
  - Optional: `clone`, `detach`, `dirty`, `cwd`, `inputs` (path to text, or
    `{"base64": ...}` for bytes), `symlinks` (path to target), `bodies` (each
    posted body, in order, exact), `gh_has` and `gh_lacks` (substrings of the gh
    log), `stdout_lacks`, `no_gh`, `no_git`, and `request` (assert the guide
    request layout: line 1 the marker line, line 2 the one `Docs pull request:`
    line, no other line holding it).
  - `compare`: `derive` or `handoff`. The suite also runs the libraries'
    `hivemind_stage_evidence_gh` and `hivemind_stage_derive` or
    `hivemind_stage_handoff` directly, in a clone holding every branch, against
    the same routes, and the script's stdout must equal that line, then
    `compare_tail`. This is the "fresh clone with no local branch derives the
    same stage as the library" check.

Placeholders render in args, expectations, bodies and routes: `{{trunk}}`,
`{{docs<i>}}`, `{{upper2}}` (docs commit 2 in capitals), `{{unfetched}}` (a
well-formed id of no object), `{{abs}}` (the clone's path) and
`{{blob:<name>}}`.

## gh-routes.json

`routes` maps a route name to `{args, json | raw, rc}`. `args` must match the
gh argv element by element: a pattern starting `^` matches by prefix, `*` by
substring, and any other exactly. A reply is `json` (served as one line) or
`raw` text, with gh's exit status `rc`, 0 by default. The script's own GraphQL
reads are named operations (`IdeaToReadyTrunk`, `IdeaToReadyPullRequest`,
`IdeaToReadyDocsPulls`, `IdeaToReadySeeds`, `IdeaToReadyComments`), matched by
prefix; the stage derivation and readiness check libraries' anonymous queries
are matched by their fixed prefix or a distinguishing substring. Comment routes
hold guide marker comments by writers (`alice`, admin), non-writers (`bob`,
read) and a Bot, comments of another slug or another pull request's URL, and a
marker that is not on the first line, so each ignore rule has a case.
