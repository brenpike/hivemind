# Solution design: Lair claim integrity

This is the claim-integrity design for the Lair, issue #632, split from the [solution design](solution-design.md) of epic #603 after its round-3 review. It links the [PRD](../../prds/autonomous-ready-issue-loop.md), [ADR-0045](../../adr/0045-lair-software-factory.md) and the [solution design](solution-design.md) rather than restating them, and cites ADR-0045 as "ADR-0045 decision N". It follows the user's answers of 2026-11-21.

For its scope, this design supersedes these parts of the solution design:

- in the component Controller tick and admission: the claim, the readiness-check call, the injection scan, labels and marker comments, the halt switch, the start-up sweep, the lock and the queue report;
- the marker side of Park answer round trip, and the marker side of Decision digest and circuit breaker;
- the Contracts Claim marker comment, Park marker comment, Readiness-check call at claim and Queue report;
- the claim-marker, park-marker, halt-file, single-instance-lock and local-cache rows of State and ownership;
- the GitHub API failure, Lock already held, Orphaned claim and Stale design rows of Failure modes;
- the Decisions on the queue report contents, the outcome in the claim marker and the circuit-breaker scope.

Every other part of the solution design stands. Strain launch and containment belong to #630, the merge lane to #631, and the readiness check to #615; this design states each assumption it makes about them under Contracts and seams.

## Context and code truth

This design builds on the following code, as it stands on trunk:

- `plugin/skills/spawn-brood/scripts/spawn-brood.sh` starts each strain as a detached tmux session running `claude --permission-mode auto` in a worktree at `.claude/worktrees/<brood-id>/<slug>`, detached at the base commit. It keeps brood state in `.hivemind/broods/<brood-id>/` of the coordinator checkout and launches with `--settings ../../../../.hivemind/broods/<brood-id>/strain-settings.json`, a file holding only plugin-folder `Read` rules. A strain's working folder therefore sits inside the coordinator checkout, four levels below its root. The script also copies the coordinator's `.claude/settings.local.json` into each worktree, and [ADR-0010](../../adr/0010-permission-allowlist-posture.md) records that since Claude Code 2.1.211 a worktree session reads the main checkout's local settings file anyway. Nothing the Lair must keep from a session can live in the checkout.
- `plugin/skills/triage-backlog/scripts/triage-ops.sh` holds the label palette: the `readiness:*` ladder (`needs-decision`, `ready`, `implementation` and `done` among them), `type:epic`, and the human-only `triage:locked`. It defines no `lair:*` label. Its `deps-read` reads native `blockedBy` links and fails closed on a continued page (`pageInfo.hasNextPage`); its other GraphQL reads fail closed the same way.
- `plugin/skills/github-review-loop/scripts/react-marker.sh` is the only GitHub marker HIVEMIND writes today: a self-authored EYES reaction. It marks only the version of a node it read, comparing `lastEditedAt` (null read as never edited), and accepts a GraphQL response only when `hivemind_graphql_response_check` passes it. It records the residual that `lastEditedAt` has one-second granularity.
- [ADR-0032](../../adr/0032-defer-marker-sentinel-and-agent-layer-home-truth.md) recognizes the defer marker only when a self-authored body starts with an exact HTML-comment sentinel, compared at byte 0, never by a pattern. `plugin/skills/github-review-loop/scripts/fix-history-classify.jq` reads `lastEditedAt` the same way.
- `plugin/skills/injection-scan/SKILL.md` is judgment-driven and has no script, so it needs a model. It takes `items` (`item_ref`, `body`), treats each body as data, and returns one `results` entry per item with `verdict: clean | injection-suspect` and, for a suspect item, `pattern_category` (`P1` to `P4`). It is stateless, and its only tool grant is a plugin-folder `Read`.
- `plugin/governance/security-policy.md` lists GitHub issue bodies under External Content Boundary. Its Brood Spawn Bypass-Mode Mitigation makes human approval of the task text the injection gate for brood strains; for Lair strains ADR-0045 decision 10 replaces that approval with admission and the scan. Its Injection-Suspect Classification defines P1 to P4, and When Classified as injection-suspect escalates to the user.
- `tools/validate.sh` registers each suite five ways: a `SUITE_*` constant, an `ALL_SUITES` entry, a `KNOWN_SUITES` entry, a path rule in its change mapping, and a `--self-test` probe path. A `tools/*.sh` suite missing from `KNOWN_SUITES` and `NON_SUITE_TOOLS` fails `--self-test`.
- `plugin/skills/adaptation-cycle/scripts/run-review.sh` hashes with `sha256sum`, else `shasum -a 256`, else blocks.
- No plugin script takes a lock with `flock`, signs anything, or keeps state outside the checkout. No Lair state exists.
- [P16](../../engineering-principles.md) requires writes to a shared artifact to be serialized by a lock, never by a prior read.

## Components

### Design invariants

Each invariant below is stated once, here. Every later section cites it by name, as "invariant Claim state", and never restates it.

- **Claim state.**
  - A Lair issue is an issue that carries a `lair:*` label or a counting claim marker (the user's 2026-11-21 sweep answer). A markerless Lair issue is one with no counting claim marker.
  - An open claim is a counting claim marker with no counting outcome marker of its nonce.
  - A live strain is a strain session for the nonce, or, for a markerless Lair issue, any strain session for the issue; or an unconsumed result file for the nonce.
  - A Lair pull request is a pull request as #631 defines it, bound to the nonce.
  - An orphan is a Lair issue with no live strain and no Lair pull request that is in `readiness:implementation` or holds an open claim.
  - An orphan is marked failed and never returned to ready. An orphan holding an open claim gets an outcome marker `crashed`, then the `crashed` labels. A markerless orphan gets labels only: `lair:failed` added, `readiness:implementation` and `readiness:ready` removed.
  - A non-Lair issue is never touched.
  - This rule runs at start and on each tick. Halt tripwires stop new claims and never suppress this action.
- **Markers and labels.**
  - Counting markers decide which claim and which outcome exist; labels follow them.
  - Each label pairs with a marker: `lair:claimed` with a counting claim marker; `lair:handoff` with a counting handoff marker, or with the counting park marker of an `approval` park or a third park; `lair:failed` and `lair:review` with a counting outcome marker under #631's mapping.
  - The reconciler moves labels forward only. It skips repair when a `readiness:ready` labeled event is newer than the latest counting outcome marker: the Lair never applies `readiness:ready` (ADR-0045 decision 10), so that event is the user's re-admission (ADR-0045 decision 11), and admission decides what happens next.
  - Only `lair:claimed` without a counting claim marker trips the halt `marker-missing`. Any other `lair:*` label without its marker is left alone and never claimed.
- **Lock scope.**
  - One controller runs per lock scope. A lock scope is one repository (the state root, keyed by the repository's GraphQL node id), one user account and one machine.
  - Creating the state root and creating the lock file are the only writes before the lock is held, and both are idempotent.
  - The Lair takes a non-blocking `flock` on `lock` before any other write and holds it for its whole life.
  - The lock descriptor is never inherited. Every child the controller launches (tmux, strains, scanner sessions, helper scripts) starts with it closed, so a strain that outlives a crashed controller never holds the lock, and the kernel frees the lock when the controller exits.
  - The lock covers the Lair's own GitHub writes, launches, key creation and halt-file writes. It does not cover the user's edits, triage, interactive sessions, the user's halt-file writes or deletion, or any other lock scope.
  - Outside one lock scope, exclusivity is detect-and-halt by markers, never prevention. Two Lairs on one repository may both claim an issue and may fail each other's claims as orphans; that setup is unsupported.
  - The re-read before the claim marker narrows an edit race. It is not mutual exclusion.
- **Lair-written text.**
  - Every string the Lair writes to GitHub, a terminal, a tmux pane or a scanner prompt is a fixed template, a token matching a validated pattern, or the one bounded slot.
  - The slot is the park marker's question block: strain-authored data (question, options, recommendation), printable text only (no control, escape or bidi-override characters), at most 2000 bytes, inside a fenced block.
  - No reader ever reads the slot's bytes. The Lair never prints them, and never puts them in a scanner prompt or a signed payload.
  - Beyond the fields every marker carries, the signed park payload carries only `key` (pattern `^[a-z0-9][a-z0-9-]{0,63}$`) and `type`.
  - A park record that breaks this rule is never posted; its handling is #631's result check.
  - Claim, outcome and handoff marker text and the queue report have no slot.

### Lair state root

One directory per repository, outside every checkout and worktree: `${XDG_STATE_HOME:-$HOME/.local/state}/hivemind/lair/<repo-key>/`, where `<repo-key>` is the first 32 hex digits of the SHA-256 of the repository's GraphQL node id. The Lair creates it with mode 0700 and prints its path on start. It holds:

- `lock`, the single-instance lock file;
- `control/`, mode 0700, holding `marker.key` (mode 0600) and the halt file `halt`;
- `scan/<scan-id>/`, one directory per scan;
- `cache/`, the local cache and the last queue report.

### Single-instance lock

The controller takes an exclusive, non-blocking `flock` on `lock` at start and holds it for its whole life. The kernel releases it when the process exits, so no stale lock survives a crash. The lock's scope is one repository for one user account on one machine, whatever the checkout. It serializes every write the controller makes: GitHub writes, scanner and strain launches, key creation and halt-file writes. It does not serialize the user's own edits, triage, interactive sessions, or a Lair on another machine or account; one Lair per repository is the supported setup, and a second Lair elsewhere is caught only through its markers (see Failure modes).

### Marker signer and verifier

The Lair writes four marker kinds as issue comments: claim, outcome, park and handoff. Each carries a claim nonce and a signature made with `marker.key`, a 32-byte random key the Lair creates on first start. The signing helper reads the key from its file and never passes it on a command line, in an environment variable, or through any file inside a session's reach. Every Lair reader of a marker goes through one verifier, which applies the counting rule under Contracts and seams. This answers B3-3.

### Readiness snapshot

For each candidate the Lair takes one snapshot: one GraphQL read of the issue node and one trunk commit fetched once per tick. Admission, the readiness check and the captured text all come from the same snapshot. This answers B3-16.

### Scanner session

The pre-spawn injection scan of ADR-0045 decision 10 runs in a locked-down scanner session. The Lair starts it as it starts a strain: an interactive `claude` session in a detached tmux session, with a per-session settings file. The session reads only the captured text and writes only one verdict file. The Lair accepts only the exact clean token. ADR-0045 decision 10 keeps its text. This answers B3-1.

### Claim sequence

The ordered reads and writes that take a candidate from snapshot to spawned strain, given under Lifecycle. Every write follows the one before it only on positive proof of success. This answers B3-10.

### Reconciler and start-up sweep

At start and at the start of every tick, the reconciler ends every orphan under invariant Claim state and repairs labels under invariant Markers and labels. Its order within a tick and its other rules are under Lifecycle.

### Halt file and circuit breaker

The halt file stops new claims (ADR-0045 decision 17). The circuit breaker counts the runs that ended in the current Lair session, read from signed outcome markers. A trip writes the halt file with its cause, so only the user deleting that file re-arms the Lair. ADR-0045 decision 17 keeps its text.

### Queue report

A report of the Ready Issue queue that prints no text taken from an issue and gives the cause of each failure. This answers B3-19.

## State and ownership

GitHub alone is authoritative (ADR-0045 decision 2). These rows replace the solution design's claim-marker, park-marker, halt-file, single-instance-lock and local-cache rows. Every other row stands.

| State | Writer | Readers | Authoritative |
| --- | --- | --- | --- |
| Claim marker comment | Lair, at claim; never edited | Lair verifier (admission, reconciler, budget, merge lane under #631), user | yes, when it counts |
| Outcome marker comment | Lair, at run end or when the reconciler ends a claim; never edited | Lair verifier (reconciler, circuit breaker, digest), user | yes, when it counts |
| Park marker comment | Lair, from the strain's park record; never edited | Lair verifier (answer admission, park count), user | yes, when it counts |
| Handoff marker comment | Lair, on a scan handoff; never edited | Lair verifier, user | yes, when it counts |
| `lair:claimed` label | Lair | Lair, triage, user | no; it pairs with a counting claim marker under invariant Markers and labels |
| Marker key `control/marker.key` | Lair, once, on first start | Lair signer and verifier only | no; a secret |
| Halt file `control/halt` | User, or the Lair's breaker and tripwires; removed only by the user | Lair, each tick | no; a control input |
| Lock `lock` | Lair | Lair | no; process exclusion only |
| Scan input and verdict `scan/<scan-id>/` | Lair writes the input; the scanner session writes the verdict | Scanner session reads the input; Lair reads the verdict | no; removed after each scan |
| Local cache `cache/` | Lair | Lair | no; rebuildable from GitHub |
| Lair session id | Lair, at start | Lair; written into every marker | no |

The local cache holds the session id, the comment ids of markers written this session, the nonces spawned and ended this session in order, and the fingerprint of each failed readiness check. Losing it loses only the tripwires that compare it with GitHub.

## Contracts and seams

Fields and seams only. Each slice builds the code.

- **Marker comment.** The body's first line is exactly `<!-- lair-marker-v1 <payload> <sig> -->`, then LF, then readable text. `<payload>` is unpadded base64url (`[A-Za-z0-9_-]`, at most 4096 bytes) of a compact JSON object. `<sig>` is the lowercase hex HMAC-SHA256, under `marker.key`, of the payload's bytes as written. The readable text comes from fixed templates and validated tokens, and no reader reads it.
- **Marker payload, every kind.** `v` (1), `kind` (`claim`, `outcome`, `park` or `handoff`), `repo` (the repository's GraphQL node id), `issue` (number), `nonce` (32 hex digits, one per claim attempt), `session` (the Lair session id, 32 hex digits), `kid` (the first 16 hex digits of the SHA-256 of the key) and `at` (UTC time).
  - `claim` adds `admit_event` (the node id of the admitting labeled event), `body_sha256`, `trunk` (the snapshot commit) and `scan` (the scan id).
  - `outcome` adds `outcome` (`complete`, `parked`, `blocked`, `failed`, `stalled`, `timed-out` or `crashed`), `ended_at`, `pr` (number or null) and, for `crashed`, `stage` (`claim-labels`, `spawn` or `run`).
  - `park` adds `key` and `type` from the park record. The question and options go in the readable text.
  - `handoff` adds `reason` (`scan-suspect` or `scan-malformed`) and `category` (`P1` to `P4`, or null).
- **Counting rule.** A comment is a marker candidate when the Lair's login wrote it and its body starts, at byte 0, with `<!-- lair-marker-`. The Lair's login is `viewer { login }`, read once at start. A candidate counts only when all hold:
  - its author is the Lair's login and `viewerDidAuthor` is true;
  - it is unedited: its `lastEditedAt` key is present and null;
  - its first line matches the form above exactly, CR bytes included;
  - its signature verifies under the current key;
  - its payload decodes, with `v` 1, `kid` equal to the current key's id, and `repo` and `issue` equal to the issue being read;
  - it carries the claim nonce: a `claim` marker carries its own; an `outcome` or `park` marker carries the nonce of a counting `claim` marker on the same issue; a `handoff` marker carries the nonce generated for the claim attempt its scan stopped.

  A candidate that fails any check is invalid. A comment by any other login is never a candidate, whatever it holds. Identical counting markers count once.
- **Reader failure direction.** Every marker reader fails toward stopping:
  - any invalid candidate, on any issue the Lair reads, writes the halt file with cause `marker-invalid`, and the issue is not claimed;
  - a marker id the cache recorded this session that GitHub no longer returns writes the halt file with cause `marker-missing`;
  - the `lair:claimed` case of invariant Markers and labels writes the halt file with cause `marker-missing`;
  - the budget check ends as `timed-out` a live strain whose claim marker does not count;
  - the breaker counts as a failure a run the Lair ended this session whose outcome marker does not count;
  - an answer to a park whose marker does not count is never admitted (#609);
  - the digest lists as `unverified` a run whose outcome marker does not count (#611).
- **`body_sha256`.** Lowercase hex SHA-256 of the ASCII string `v1:<T>:<B>`, where `<T>` is the hex SHA-256 of the title's bytes and `<B>` the hex SHA-256 of the body's bytes, both exactly as the GraphQL read returns them. A null body (REST) and an empty body both hash as zero bytes. CR bytes, CRLF line endings, trailing newlines and Unicode forms are kept as read, with no normalization. Each hash is computed from a pipe, never through command substitution, which drops trailing newlines. The field keeps its name although it covers the title too. This answers B3-18.
- **Snapshot.** One GraphQL read of the issue: `number`, `state`, `title`, `body`, `lastEditedAt`, `updatedAt`, labels, the `LABELED_EVENT`, `UNLABELED_EVENT` and `RENAMED_TITLE_EVENT` timeline items with actors, `blockedBy` states, the parent's state, the sub-issue count and the comments with the fields the counting rule needs. Any connection with `hasNextPage` true, or a response `hivemind_graphql_response_check` rejects, is a snapshot error. The write permission of the admitting label's actor is one REST read in the same evaluation. The trunk commit is fetched once per tick.
- **Readiness-check call at claim.** The Lair calls the check with the snapshot and the trunk commit, never letting it read GitHub itself. The result is the one the [idea-to-ready PRD](../../prds/idea-to-ready.md) names under "Readiness check output": track, pass or fail, and reason codes. Only a pass is claimed. A non-zero exit, a malformed result, or no result within 60 seconds is the Lair-side state `check-error`, never a pass. Per tick the Lair checks at most 5 candidates, in ascending issue number. A candidate whose `updatedAt` and trunk commit equal those of its last failed check this session is not checked again; its cached reasons are reported.
- **Scanner session settings.** Written by the Lair per scan through #630's per-session settings mechanism. They allow `Read` of `scan/<scan-id>/input.txt`, `Write` of `scan/<scan-id>/verdict`, the `hivemind:injection-scan` skill and plugin-folder reads. They allow nothing else: no Bash, no Edit, no web tools, no MCP servers, no agents. The pasted prompt is fixed text holding only the scan id and paths derived from identifiers; issue text never enters the pane.
- **Scan input.** `input.txt` holds the captured title, LF, then the body: the exact bytes whose hash is the claim's `body_sha256`.
- **Verdict file.** Exactly one line ending in LF, read bounded to 129 bytes:
  - `lair-scan-v1 <scan-id> clean` is the clean token, and the only verdict the Lair accepts;
  - `lair-scan-v1 <scan-id> injection-suspect <P1|P2|P3|P4>` is suspect;
  - any other content, a stale scan id included, is malformed and handled as suspect;
  - no file within 300 seconds is a scan error.

  The Lair then ends the scanner session and removes the scan directory, whatever the verdict.
- **Halt file.** Its path is `control/halt` under the state root. Any directory entry at that path, of any content, halts; so does a state root the Lair cannot read. The Lair writes it as `halt` LF, `cause: <code>` LF, `at: <UTC time>` LF, and for the breaker one `run: <issue> <outcome>` line per counted run. Cause codes: `breaker`, `marker-invalid`, `marker-missing`, `scanner-error`. A file of any other form reads as cause `user`. The Lair never deletes it.
- **Queue report.** Lines of fixed keys and validated tokens only: `lair-queue v1 session=<hex> at=<UTC time>`; `halted: <cause code>` or `halted: no`; `ready: <count>`; one `issue <number>: <stage> <code>[,<code>...]` line per ready-labeled issue that failed; and, when `ready` is 0, `hint: run hivemind:triage-backlog`. `<stage>` is `admission`, `snapshot-error`, `readiness`, `check-error`, `scan` or `marker`. A reason code that does not match `^[a-z0-9][a-z0-9-]{0,63}$` prints as `unknown-reason`. No title, body, label text from outside the palette, login or comment text is printed. The Lair prints it to its tmux window and writes it to `cache/queue-report.txt` on start, on each tick that finds nothing to claim, and on each tick where a ready-labeled issue fails.

### Assumptions about #630

- **Strain settings and environment.** The Lair-written settings carry `HIVEMIND_LAIR_STRAIN` and no merge keys (ADR-0045 decision 4), and no session's environment holds the state root's path, the key or its id.
- **Where the claim nonce lives.** In `HIVEMIND_LAIR_STRAIN`, per ADR-0045 decision 4. The nonce is not a secret: a session that knows it still cannot make a marker count without the key.
- **Start on a re-claim.** Each claim, a re-claim included, gets a new nonce and its own claim marker. Where the strain starts, on the pushed branch per ADR-0045 decision 11, is #630's.
- **Governance edits for unattended runs.** #630's governance edits also cover the scanner session as a caller of `hivemind:injection-scan` whose suspect handling is the verdict token, not the escalation in When Classified as injection-suspect.
- **Scanner session on #630's mechanism.** The scanner session uses #630's per-session settings-file mechanism, and that mechanism makes the Lair's file the session's complete permission set, with no committed or local allow rule added to it. Its start directory is whatever #630 gives a strain, so it starts without any prompt that waits for a human.
- **Containment of the key and the halt file.** No session the Lair starts, strains, remediation strains and scanner sessions included, can read, write or delete anything under the state root's `control/` directory, by any tool, Bash included. Only the scanner session reaches `scan/`, and only its own two files.

### Assumptions about #631

- **Merge lane.** The lane reads a claim's `body_sha256` and nonce only from a counting claim marker, through this design's verifier, and merges nothing for an issue without one.
- **What counts as a Lair pull request.** Defined by #631, bound to a claim nonce. It is an input to the orphan rule of invariant Claim state.
- **Result file at run end.** Run end reads the strain's result file, whose form and location are #631's. A result file run end has not yet read is unconsumed, an input to invariant Claim state.
- **Result field checks.** #631 checks the strain result's fields; an outcome marker records the outcome the Lair accepted after those checks.
- **Run-outcome to label mapping.** Defined by #631, over the outcome values above. The reconciler re-applies it under invariant Markers and labels, and only `failed`, `crashed` and `timed-out` count toward the breaker.
- **Issue edited after claim.** The merge-side action is #631's; this design supplies the `body_sha256` form.
- **Halt.** The halt's effect on merges and remediation strains is #631's. A remediation run counts toward the breaker only if #631 gives it an outcome marker.

### Assumptions about #615

- **The check itself.** The readiness check is the one the Acceptance Criteria bullets of the [idea-to-ready PRD](../../prds/idea-to-ready.md) specify: every-issue, standalone and initiative-slice bullets, and "Readiness check output".
- **Recorded input.** It accepts a recorded issue state and a commit, as its Testing Decisions' recorded fixtures already require, and makes no GitHub read of its own when given them.
- **Document paths in the issue body (B3-22).** It reads a document path named in the issue body only as a git object at the given commit, never from a working tree. A path that is absolute, holds `..`, lies outside `docs/`, is absent, or names a symlink blob is a fail with a reason code, never a read elsewhere.
- **Reason codes.** Each matches `^[a-z0-9][a-z0-9-]{0,63}$`.

## Trust boundaries

- **Markers.** A marker counts only when the Lair's login wrote it, it is unedited, it carries the claim nonce and its signature verifies with a key no Lair-started session can read. The login check alone cannot tell the Lair from a strain, since both act as the user ([ADR-0045 residuals](../../adr/0045-lair-software-factory.md#residuals)); the signature can. An outsider's comment is never a candidate, so outsiders cannot forge a marker or trip the halt.
- **The key.** It lives under `control/`, out of every session's reach by #630's containment. A session that escapes that containment can read the key and sign markers that count. This is proposed as an ADR-0045 residual under Changes to shared documents, as the user chose.
- **The scanner session.** It receives the captured text as data, through a file, with no tool that can act outside its two files. The verdict is a filter, not a boundary: an injected scanner can write the clean token, and the strain that then runs stays inside #630's containment. A scanner can never write a clean token for another scan, because the token names its scan id.
- **The halt file.** Only the user removes it. Sessions cannot reach it (#630), so a strain cannot re-arm the Lair.
- **The queue report and marker text.** Neither carries issue-derived text, so neither is an injection path into the user's terminal or a later reader.
- **Admission.** ADR-0045 decision 10 and its amendment stand. A ready label applied by hand on a parked issue is the user's re-admission (ADR-0045 decision 11).

## Lifecycle

Each tick runs in this order:

1. Read the halt file.
2. Reconcile every Lair issue under invariants Claim state and Markers and labels.
3. The stages other slices own: run end, the merge lane, park answers.
4. Unless halted, evaluate candidates and claim at most one.

The claim sequence, for one candidate:

1. Take the snapshot. Check admission (ADR-0045 decision 10 and its amendment; the PRD Admission criterion), including that every counting claim marker on the issue has a counting outcome marker.
2. Run the readiness check on the snapshot. Only a pass goes on.
3. Generate the claim nonce and scan id, capture the text, and compute `body_sha256`.
4. Run the scanner session. A clean token goes on. A suspect or malformed verdict hands the issue off: a handoff marker, then the `lair:handoff` label, with no other label changed. A scan error leaves the issue unclaimed, with no new label and stage `scan` in the queue report.
5. Re-read the issue's labels, `lastEditedAt`, title and latest labeled and renamed events. Any difference from the snapshot ends the attempt with no write; the next tick evaluates the issue again.
6. Read the halt file again. A halt ends the attempt with no write.
7. Write the claim marker.
8. Add `lair:claimed`, then add `readiness:implementation`, then remove `readiness:ready`.
9. Spawn the strain.

At run end the Lair writes the outcome marker first, then the labels of #631's mapping. On a park the issue moves to `readiness:needs-decision` and keeps `lair:claimed`, so triage still skips it (ADR-0045 decision 16). This answers A3-17. The user re-admits it by applying `readiness:ready` by hand.

The reconciler applies invariants Claim state and Markers and labels, with these rules of its own:

- The `crashed` outcome marker of an orphan holding an open claim carries `stage` `claim-labels` when the claim's label writes were incomplete, `spawn` when the cache shows no spawn, and `run` otherwise. This covers a write that failed, a write whose response was lost, and an orphan left by an earlier Lair session alike.
- An unconsumed result file is a live strain, so the reconciler in step 2 never ends a finished run `crashed`; run end reads its result in step 3 of the same tick.
- A counting outcome marker whose labels do not match #631's mapping gets the mapping's labels again, except on an issue the user re-admitted, which invariant Markers and labels skips.
- A counting handoff marker without `lair:handoff` gets the label again.
- Every label write is idempotent.

The halt and the breaker:

- With the halt file present, the tick reconciles and reports, and makes no snapshot, scan or claim. A halt that appears after the claim marker is written takes effect from the next tick, and that claim completes.
- After each outcome marker, the breaker reads the counting outcome markers of this session's ended runs, ordered by `ended_at`, from the latest re-arm on. Three consecutive `failed`, `crashed` or `timed-out` outcomes write the halt file with cause `breaker` and the three runs. A `parked` outcome is skipped and does not end a streak; any other outcome, `complete`, `blocked` or `stalled`, ends it. The Lair's first tick and every tick that finds a halt file gone after it was present start a new window.

## Existing-path coverage

- Non-Lair brood strains keep today's launch, settings copy and approval gate. Nothing in `spawn-brood.sh` changes for them.
- `hivemind:injection-scan` keeps its contract, and its review-loop callers are unchanged. The scanner session is a new caller.
- `react-marker.sh` and the review-loop markers are unchanged. The Lair's marker sentinel shares no prefix with them.
- Triage is unchanged beyond ADR-0045 decision 16's skip, and the skip still holds for a parked issue because it keeps `lair:claimed`.
- An issue a human labels `readiness:implementation` without the Lair is not a Lair issue, so the reconciler never touches it (invariant Claim state).
- Interactive sessions never read the state root, the key or the halt file.
- `tools/validate.sh` is not changed by this design; the registrations under Verification strategy land with the slices.

## Failure modes

| Failure | Detection | Resulting state |
| --- | --- | --- |
| GitHub read failure or rate limit | A failed or rate-limited read, or a response `hivemind_graphql_response_check` rejects. | No write for the issue concerned this tick. A candidate's snapshot error is reported with stage `snapshot-error`. The next tick retries. |
| Incomplete page | A connection in the snapshot has `hasNextPage` true. | Snapshot error; the issue is not claimed. |
| GitHub write failure mid-sequence | A claim, run-end or handoff write without positive proof of success. | The sequence stops at that write and spawns nothing. The next tick's reconciler moves the partial state forward. |
| Claim stopped partway, or orphaned claim | An orphan under invariant Claim state. | Ended under invariant Claim state, with the `crashed` stage under Lifecycle. A `crashed` outcome marker counts toward the breaker. |
| Lock already held | `flock` cannot take `lock`. | The second Lair prints `lock held`, exits non-zero and changes nothing. |
| `flock` missing | The tool is not on `PATH`. | The Lair refuses to start and changes nothing. |
| Issue changed during evaluation | The re-read before the claim marker differs from the snapshot. | No write; the issue is evaluated again next tick. |
| Stale design, or an epic | The readiness check fails, or the issue carries `type:epic`. | Not claimed and given no new label. Reported with its stage and reason codes. |
| Readiness check error | A non-zero exit, a malformed result, or no result within 60 seconds. | Not claimed, no new label, reported with stage `check-error`. |
| Scan suspect or malformed | The verdict file holds the suspect form or any non-clean content. | Handoff marker, then `lair:handoff`. No strain starts. |
| Scan error | No verdict file within 300 seconds, or the session failed to start. | Not claimed, no new label, reported with stage `scan`. Three consecutive scan errors in a session write the halt file with cause `scanner-error`. |
| Invalid marker | A candidate fails the counting rule. | Halt file with cause `marker-invalid`; the issue is not claimed. |
| Missing marker | A marker the cache recorded this session is gone, or the `lair:claimed` case of invariant Markers and labels. | Halt file with cause `marker-missing`. An orphan among these issues is still ended under invariant Claim state. |
| Key missing or replaced | A new key was created, so earlier markers carry another `kid`. | Each earlier marker the Lair reads is invalid, so the Lair halts with `marker-invalid`. The user restores the key or clears the issues by hand. |
| Second Lair on another machine or account | Its markers carry another `kid`, or another login. | Another `kid` halts this Lair with `marker-invalid`. Another login's comments are not candidates, and its `lair:claimed` without a counting claim marker halts this Lair with `marker-missing`. |
| Halt file present or state root unreadable | Read at the start of the tick and before the claim marker. | No snapshot, scan or claim. Reconciling and reporting continue. |
| Circuit breaker trip | Three consecutive counted outcomes in the current window. | Halt file with cause `breaker` and the runs; only the user deleting it re-arms the Lair. |

## Decisions

A decision that is not ADR-worthy names the [P20](../../engineering-principles.md) condition it fails. The three Tier A answers the user gave on 2026-11-21 come first.

- **The injection scan runs in a locked-down scanner session, and ADR-0045 decision 10 keeps its text.** Tier A, answered by the user on 2026-11-21 (B3-1). Implements ADR-0045 decision 10.
- **Markers count only when signed, unedited, carrying the claim nonce and written by the Lair's login, and forgery after a containment escape becomes an ADR-0045 residual.** Tier A, answered by the user on 2026-11-21 (B3-3). Implements ADR-0045 decisions 2 and 17; the residual is proposed under Changes to shared documents.
- **The circuit breaker counts the runs that ended in the current Lair session, and a trip writes the halt file with its cause; ADR-0045 decision 17 keeps its text.** Tier A, answered by the user on 2026-11-21 (the breaker part of A3-12). Implements ADR-0045 decision 17.
- **HMAC-SHA256 with one local key per repository, and a `kid` in every marker.** Implements the signed-marker answer. Not ADR-worthy: fails P20's hard-to-reverse condition, since the `v` field allows a second scheme.
- **The state root lives outside every checkout and worktree.** Implements ADR-0045 decision 17's halt file and the signed-marker answer. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Every marker reader fails toward stopping, and an invalid or missing marker halts the Lair.** Implements ADR-0045 decision 17. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Markers are append-only; the outcome is a separate outcome marker, not an edit of the claim marker.** Replaces the solution design's outcome in the claim marker, since an edited marker never counts. Implements ADR-0045 decision 2. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Claim write order: claim marker, then labels, then spawn; run end: outcome marker, then labels.** Implements ADR-0045 decisions 2 and 16 (B3-10). Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Orphans, a claim that stopped partway included, are ended under invariant Claim state, which covers only Lair issues.** The scope is the user's 2026-11-21 answer (A), through a proposed ADR-0045 amendment to decision 17 under Changes to shared documents. The amendment's wording is derived from the invariant, decided for the user and listed for veto.
- **The lock covers one repository for one account on one machine, through `flock`.** Implements ADR-0045 decision 2 (B3-11). Not ADR-worthy: fails P20's hard-to-reverse condition.
- **One snapshot per candidate, a Lair-side `check-error` state, and at most 5 checks of 60 seconds each per tick.** Implements the ADR-0045 2026-11-21 amendment (B3-16). The limits are tuning values. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The scan verdict is a token file; only the exact clean token passes, malformed is suspect, and missing is an error.** Implements ADR-0045 decision 10. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Three consecutive scan errors halt the Lair.** Extends ADR-0045 decision 17. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The `body_sha256` form: a hash of the title and body hashes, with no normalization.** Implements ADR-0045 decision 10 (B3-18). Not ADR-worthy: fails P20's hard-to-reverse condition, since the `v1:` prefix allows another form.
- **The queue report prints only fixed keys and validated tokens, with a stage and reason codes per failure.** Replaces the solution design's queue report contents (B3-19). Not ADR-worthy: fails P20's hard-to-reverse condition.
- **A parked issue keeps `lair:claimed`.** Implements ADR-0045 decision 16 with its label list unchanged (A3-17). Not ADR-worthy: fails P20's hard-to-reverse condition.
- **Only `failed`, `crashed` and `timed-out` outcomes count toward the breaker; a park is skipped, and any other outcome ends a streak.** Implements ADR-0045 decision 17, which names failed, crashed and timed-out outcomes and excludes parks and review waits. Not ADR-worthy: fails P20's hard-to-reverse condition.
- **The halt file's path and cause codes.** Implements ADR-0045 decision 17 (the owned part of B3-20). Not ADR-worthy: fails P20's hard-to-reverse condition.

### Changes to shared documents

None of these changes is applied in this pull request.

- **Target:** `docs/adr/0045-lair-software-factory.md`, section Residuals, as a new last bullet. **Answer:** signed markers plus this residual, chosen by the user on 2026-11-21. **Exact proposed text:**

  ```markdown
  - **A session that escapes its containment can forge markers.** Marker comments count only when signed with a key no Lair-started session can read. A session that escapes the containment of the Lair-written settings can read that key and sign claim, outcome, park and handoff markers that count. The user chose signed markers with this residual on 2026-11-21.
  ```

- **Target:** `docs/adr/0045-lair-software-factory.md`, as a new last section after the 2026-11-21 admission amendment. **Answer:** the sweep covers only Lair issues, through an ADR-0045 amendment, chosen by the user on 2026-11-21 (A). The wording follows invariant Claim state; it was decided for the user and is listed for veto. **Exact proposed text:**

  ```markdown
  ## Amendment 2026-11-21: the orphan rule covers only Lair issues

  This amends decision 17 (Stop controls). An issue is a Lair issue when it carries a `lair:*` label or a counting claim marker. A Lair issue is an orphaned claim when it is in `implementation` or holds a counting claim marker with no counting outcome marker of the same claim, and it has no live strain and no Lair pull request. A live strain is a running strain session for the claim, or for the issue when it has no counting claim marker, or a strain result the Lair has not yet read at run end. An orphaned claim is marked failed, never returned to ready, and this includes a claim that stopped before its label writes. The Lair applies this rule at start and on each tick. Any other issue is left alone, so an issue a person moved to `implementation` by hand is never failed. Decision 17's other stop controls stand unchanged. Status remains accepted.
  ```

- **Target:** `docs/initiatives/autonomous-ready-issue-loop/solution-design.md`, section Amendments, as a new paragraph after the existing one. Decided for the user and listed for veto. **Exact proposed text:**

  ```markdown
  **2026-11-21, claim integrity.** The claim-integrity design, `claim-integrity-design.md` in this folder, supersedes, for its scope, these parts of this design: in Controller tick and admission, the claim, the readiness-check call, the injection scan, labels and marker comments, the halt switch, the start-up sweep, the lock and the queue report; the marker side of Park answer round trip and of Decision digest and circuit breaker; the Contracts Claim marker comment, Park marker comment, Readiness-check call at claim and Queue report; the claim-marker, park-marker, halt-file, single-instance-lock and local-cache rows of State and ownership; the GitHub API failure, Lock already held, Orphaned claim and Stale design rows of Failure modes; and the Decisions on the queue report contents, the outcome in the claim marker and the circuit-breaker scope.
  ```

## Verification strategy

The tests are the PRD's [Testing Decisions](../../prds/autonomous-ready-issue-loop.md#testing-decisions); this section adds the claim-integrity cases and where they live. All run on recorded GitHub states, with no live GitHub, and fixtures live under `tests/lair/`.

- **`tools/test_lair_markers.sh`.** Sign then verify; and one failing case per counting check: another login, `viewerDidAuthor` false, a non-null `lastEditedAt`, a missing `lastEditedAt` key, a CRLF first line, a bad signature, another `kid`, a marker copied to another issue or repository, an outcome marker whose nonce has no counting claim marker. An outsider's sentinel comment is ignored and halts nothing. Identical markers count once.
- **`tools/test_lair_claim.sh`.**
  - Write order, and the reconciler's result for a stop after each write, including a lost response.
  - The lock held twice, and `flock` missing.
  - A change between snapshot and re-read.
  - The halt file present at tick start, appearing before the claim marker, and appearing after it.
  - The breaker: three counted outcomes trip it and write the halt file with its cause; parks are skipped; a `complete`, `blocked` or `stalled` outcome ends a streak; another session's outcomes are ignored; a run ended with no counting outcome marker counts; a removed halt file starts a new window.
  - `body_sha256` vectors: CRLF, null body, empty body, trailing newline, a title edit only.
  - Check error, check timeout, the per-tick cap, and the cached failed fingerprint.
  - A parked issue keeps `lair:claimed`. A parked issue the user re-admits by hand keeps `readiness:ready` through the next reconcile.
  - The orphan matrix, each case checked against invariant Claim state: a partial claim still in `readiness:ready` is ended `crashed` with stage `claim-labels`; an issue in `readiness:implementation` with a Lair pull request is left alone; a finished run with an unconsumed result file is not ended `crashed`, and run end reads its result; a markerless `lair:claimed` issue in `readiness:implementation` gets the markerless orphan labels and halts the Lair with `marker-missing`; a human's `readiness:implementation` issue is never touched.
- **Queue-report and injection tests.** Fixture titles and bodies hold P1 to P4 text, terminal escape sequences and a fake `lair-queue` line. The test asserts no fixture byte from a title or body appears in the queue report, the marker readable text, the tmux paste, or the scanner prompt.
- **`tools/test_lair_scan.sh`.** The exact clean token passes; a trailing space, a stale scan id, a CR and an extra line are malformed and hand off; the suspect form hands off with its category; no verdict file is an error with no label; three errors halt. The scanner settings allow exactly the two scan files, the skill and plugin reads.
- **Registration in `tools/validate.sh`.** Each new suite gets a `SUITE_*` constant, an `ALL_SUITES` entry, a `KNOWN_SUITES` entry, a change-mapping rule that routes the controller scripts #608 adds and `tests/lair/*` to it, and a `--self-test` probe path. This is the design only: `tools/validate.sh` is not edited here.
- **Live smoke.** The by-hand smoke run adds a halt-file stop and an outsider's sentinel comment on the throwaway issue.

## Seam order

The build order of the solution design stands. This design adds two seams: #630's containment and per-session settings, and #631's merge-lane reading of markers, both land before #608 is ready.

| Slice | What this design changes | ADRs |
| --- | --- | --- |
| #604 | The scanner session reuses the strain launch and per-session settings; strain settings keep the state root out of reach. | ADR-0045 decisions 3, 4, 5 and 10; ADR-0007; ADR-0010; ADR-0017 |
| #605 | The merge lane reads `body_sha256` and the nonce only from a counting claim marker. | ADR-0045 decisions 10 and 12; ADR-0044 |
| #608 | The claim sequence, snapshot, scanner session, signed markers, reconciler and sweep, lock, halt file, queue report and state root. | ADR-0045 decisions 2, 10, 16 and 17 and the 2026-11-21 amendment; ADR-0007; ADR-0019; ADR-0026; ADR-0032 |
| #609 | Park markers are signed, answers count only against a counting park marker, and a parked issue keeps `lair:claimed`. | ADR-0045 decisions 7, 11 and 16 |
| #611 | The breaker's session window and halt-file write; the digest reads counting outcome markers. | ADR-0045 decisions 14 and 17 |
| #612 | Parallel strains keep one lock and at most one claim per tick. | ADR-0045 decisions 12 and 15; ADR-0007 |

Slices #606, #607 and #610 are unchanged by this design.

## Open questions

None

## Amendments

None yet. Later changes to this design are appended here as dated entries.
