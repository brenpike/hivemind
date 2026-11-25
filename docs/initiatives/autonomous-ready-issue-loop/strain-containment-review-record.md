---
stamps: []
verdict: fail
open:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 5
clean_round: false
---

# Design review record: Lair strain containment

This record covers the design review of the [strain containment design](strain-containment-design.md) for issue #646, epic #603. Issue #646 was split from #633 by the user's answer of 2026-11-22. The review follows ADR-0046 and the record shape in `plugin/skills/design-review/references/record-format.md`.

## Reviewed documents

- The [strain containment design](strain-containment-design.md) is the reviewed and stamped document.
- Read as context, not stamped: the [PRD](../../prds/autonomous-ready-issue-loop.md), the [solution design](solution-design.md), [ADR-0045](../../adr/0045-lair-software-factory.md), the three part designs and the epic record's [integration findings](review-record.md).

How this record is kept:

- The `hivemind:design-review` engine has no part-design mode. Its `round` and `stamps` read only the slug's `review-record.md`, and record verify reads only files named `review-record.md`.
- So this record follows record-format's front matter and body rules by hand.
- The round number, the pass rule and the 3-round cap come from this front matter.
- The maintainer raised the cap to 4 for this review after round 3 (2026-11-24), for one confirming pass over the round-3 fixes. A pass at round 4 or later falls outside record-format's pass rule (rounds 2 to 3); this record is outside record verify (D1), and the exception is the maintainer's decision recorded here. Round 4 was not clean.
- The maintainer then ran a fifth, confirming round (answer C to the local-review join question, 2026-11-24). Round 5 was not clean. Per the maintainer's answer B, the review closed after round 5 with verdict `fail` and no stamp. Its findings were fixed in the part design in one last wave that no review round checked, and the maintainer joined the design to `solution-design.md` anyway (Decisions asked). The Lair review record's re-review is the next look at the join.
- The pass stamp is `git rev-parse <reviewed>:<path>`. It stays unused: no round passed.
- The epic record is not edited.
- Inherited findings join the Findings table at round 1 with IDs such as `integration R1-1`.
- New IDs are `S<round>-<n>` for the cerebrate pass and `S<round>-T<n>` for the local review tool pass. `L-<n>` is a finding of the pull request's pre-PR local review that bears on this review.
- Each round runs one fresh read-only `hivemind:cerebrate` pass with "Memory context: none".
- The design touches a trust boundary and credentials, so each round also runs one local review tool pass, or records its skip.

## Rounds

### Round 1

Reviewed commit `5448a99df44c127e1389f09ea9ea6b5ec6ec1aa5`; merge-base `eb40ed9804b7ad92498ed42a8478b8edd3311e82`.

- Pass 1: reviewer cerebrate, on cerebrate's own model (`HIVEMIND_DESIGN_REVIEW_MODEL` unset, `model=default`), a fresh read-only pass with "Memory context: none". It covered the whole part design, with the PRD, the solution design, ADR-0045, the three part designs, the epic record and the CLAUDE.md principles as context: code truth, principles, governance and ADR conflicts, existing-path coverage, failure modes, trust and injection, and testability. It raised 10 findings and found integration R3-6 unfixed.
- Pass 2: reviewer the local review tool, preset `codex-plugin` (`HIVEMIND_LOCAL_REVIEWER` unset, Codex plugin installed), on the tool's own default model, base the merge-base, iteration 1, with the skill's fixed design-review focus. It raised 2 findings.
- All findings were fixed in the part design before round 2.

### Round 2

Confirming round. Reviewed commit `d1a0ec7ca49b890f42a4d0fd79cd02cd12c05b3a`; previous `5448a99df44c127e1389f09ea9ea6b5ec6ec1aa5`.

- Pass 1: reviewer cerebrate, on cerebrate's own model (`model=default`), a fresh read-only pass with "Memory context: none". It covered only the diff from the previous commit and the fixes to round 1's findings, and checked decisions D1-D7 and the design's Decisions changes for strength and irreversibility. It found every round-1 row closed (`unfixed: none`). It raised 5 findings.
- Pass 2: reviewer the local review tool, preset `codex-plugin`, on the tool's own default model, base the previous round's commit, iteration 2, with the skill's fixed design-review focus. It raised 2 findings.
- All seven findings were fixed in the part design in the same wave.
- Diminishing-returns advisory: the signals are recurrence and trend. Recurrence: both high findings came from residuals that the S1-4 and S1-9 fixes created, and the medium came from the S1-T2 mach allowlist. Trend: cerebrate's severity fell from high to medium and low while the design grew from 74.5 KB to 100 KB. Options given: narrow the design and hand the lows to #604 and #608 as a tracked follow-up; accept the lows as recorded residuals; keep going. The maintainer's answer (2026-11-24): keep going (option 3), fixing all seven in one wave, the two high ones by a deny-by-default view of named binds.

### Round 3

Confirming round. Reviewed commit `7e36583da92f4a1eeb3949da5164767d7110488b`; previous `d1a0ec7ca49b890f42a4d0fd79cd02cd12c05b3a`.

- Pass 1: reviewer cerebrate, on cerebrate's own model (`model=default`), a fresh read-only pass with "Memory context: none". It covered the diff from the previous commit and the round-2 fixes, and checked decisions D1-D9. It found every round-2 row closed (`unfixed: none`). It raised 4 findings.
- Pass 2: reviewer the local review tool, preset `codex-plugin`, on the tool's own default model, base the previous round's commit, iteration 3, with the skill's fixed design-review focus. It raised 1 finding.
- Diminishing-returns advisory: all three signals. Recurrence: S3-1 to S3-4 come from the round-2 file-view fix. Trend: high findings 5, 2, 0 while the design grew 74.5 KB, 100 KB, 102.9 KB. Bounded edge cases: S3-2 to S3-4 are bounded by existing safeguards; S3-1 is bounded at start by the probe's `control` case. Options given: narrow and hand off; accept residuals; keep going. The maintainer's answer (2026-11-24): fix all four design findings now (each has a strong, contained fix, so none is deferred), reject S3-T1, and raise the cap to 4 for one confirming pass.

### Round 4

Confirming round. Reviewed commit `0105014fd000bc808451431e8d0bf0478c0b769b`; previous `7e36583da92f4a1eeb3949da5164767d7110488b`.

- Pass 1: reviewer cerebrate, on cerebrate's own model (`model=default`), a fresh read-only pass with "Memory context: none". It covered the diff from the previous commit and the round-3 fixes. It judged the S3-T1 rejection reason sound and the `/init` carve-out sound, and found every round-3 row closed (`unfixed: none`). It raised 5 findings, all low.
- Pass 2: reviewer the local review tool, preset `codex-plugin`, on the tool's own default model, base the previous round's commit, iteration 4, with the skill's fixed design-review focus. It raised 2 findings.
- Every round-4 finding was fixed in the part design after the round, or rejected. Round 5 checked those fixes.

### Round 5

Confirming round. Reviewed commit `7f9a49b5346dafcb0ea56e3707c22bb5a5eed9c7`; previous `0105014fd000bc808451431e8d0bf0478c0b769b`.

- Pass 1: reviewer cerebrate, on cerebrate's own model (`model=default`), a fresh read-only pass with "Memory context: none". It covered the diff from the previous commit, which holds the round-4 fixes and the joining Amendments entry, checked the round-4 fixes, and checked decisions D1-D14. It found every round-4 row closed (`unfixed: none`). It raised 5 findings: 1 medium and 4 low.
- Pass 2: reviewer the local review tool, preset `codex-plugin`, on the tool's own default model, base the previous round's commit, with the skill's fixed design-review focus. It raised 1 finding, high.
- Not clean. The review closed after this round with verdict `fail` and no stamp. The five cerebrate findings were fixed in the part design and in the joining Amendments entry after the round, without a further review round; S5-T1 was rejected.
- Diminishing-returns advisory: all three signals. Recurrence: the round-3 and round-4 fix surfaces drew new findings (S5-1 from the S4-T1 clause, S5-2 and S5-3 from the S4-2 timeout, S5-4 from the S4-1 case). Trend: severity fell to one medium and four lows, while each fix added surface. Bounded edge cases: S5-2 to S5-4 each turn on one narrow condition, a strain-made FIFO, an untested wrap or a WSL2 binfmt flag. The maintainer's answer (2026-11-24): B. Fix all five, keep the join, close with verdict `fail` and no stamp, and run no sixth round.

## Findings

| ID | Round | Angle | Severity | Disposition | Note |
| --- | --- | --- | --- | --- | --- |
| integration R1-1 | 1 | A | high | fixed | Tmux reach closed by the deny-by-default view, network namespace and socket-family allowlist on Linux, and the macOS profile with channel probe cases; probe cases `list-sessions`/`new-window` on scratch servers. Design: Requirement I2, Components. |
| integration R1-2 | 1 | A | high | fixed | `control/` hidden on Linux (tmpfs over the state root) and denied on macOS; probe read, append and delete cases on `control/` scratch targets. |
| integration R1-5 | 1 | B | medium | fixed | Probe `sandbox` and its stop cause `strain_env_preflight`. |
| integration R1-12 | 1 | B | medium | fixed | Merge lane cache under `control/` covered by I1; result file per strain by I3 on Linux, macOS one strain at a time. |
| integration R2-1 | 1 | B | high | fixed | Deny by default plus network namespace; probe `tmux run-shell` and `systemd-run --user` cases. |
| integration C2-1 | 1 | B | high | fixed | I3 and I5; sibling probe cases with a late target and two sessions at once; #612 gate. |
| integration R3-1 | 1 | B | high | fixed | I4 makes shared run-or-load config read-only; strain-writable worktree admin files are never loaded by the Lair (S1-3). |
| integration R3-2 | 1 | B | medium | fixed | Allowlist view, network namespace, socket-family allowlist; abstract, group-socket, loopback, unix-dgram and WSL interop/vsock probe cases. |
| integration R3-3 | 1 | B | medium | fixed | Keyring and session bus section with its fallback order. |
| integration R3-4 | 1 | B | medium | fixed | Probe targets are scratch under fresh nonces; launch order creates sibling and late targets after sessions start. |
| integration R3-6 | 1 | A | low | fixed | Round 1 pass found it unfixed; every macOS statement now cites both ADR-0045 amendments (2026-11-21, 2026-11-22) and the probe's channel cases. |
| S1-1 | 1 | B | high | fixed | Seccomp argument rules compare only the low 32 bits; high-bit negative test cases and probe case. |
| S1-2 | 1 | B | high | fixed | `env -i` before bwrap so credentials travel in the environment, never a long-lived argv; third-source token not passed as an argument; `tmux new-session -e` dropped; argv pin. |
| S1-3 | 1 | B | high | fixed | No Lair process runs git, gh or a config-loading tool in a strain's worktree or admin folder; head check reads `<admin>/HEAD` as checked data and tests ancestry in the Lair's bare repository; pin. |
| S1-4 | 1 | B | medium | fixed | Socket families allowlisted (AF_INET, AF_INET6, AF_NETLINK); socketpair only stream or seqpacket; FIFOs named; `unix-dgram` and `vsock` probe cases. |
| S1-5 | 1 | A | medium | fixed | Builder bind rule stated over named leaf paths with explicit exceptions; passing real-layout cases beside refusal cases. |
| S1-6 | 1 | B | medium | fixed | Lair-mode tmux calls name the default server or unset `TMUX`; pin. |
| S1-7 | 1 | A | medium | fixed | Local review row: live-probe row for the `codex-plugin` preset in the sandbox and a stated fallback. |
| S1-8 | 1 | B | medium | fixed | Forwarder attach owner, FIFO mechanism, State row and Failure modes row with pins. |
| S1-9 | 1 | B | low | fixed | Mount propagation into the sandbox stopped or probed, with a residual if needed. |
| S1-10 | 1 | A | low | fixed | Citation corrected to `create-working-branch.sh` line 478. |
| S1-T1 | 1 | review | high | fixed | The builder binds every visible submount read-only and each start probe tries a write on each; no claim rests only on the manual live probe. |
| S1-T2 | 1 | review | high | fixed | macOS profile denies mach-lookup by default and denies launchd submission, LaunchServices and Apple Events; adversarial probe cases for each channel; any success or unrunnable case fails the probe and the Lair claims nothing on macOS. |
| S2-1 | 2 | confirm | medium | fixed | macOS profile denies `user-preference-write`; probe case `preferences`; every allowlisted mach service is checked for writes on the caller's behalf, with a live-probe row. |
| S2-2 | 2 | confirm | low | fixed | Code truth: the git-dir read is restated as #604's change; `delete-buffer` added to the tmux call list. |
| S2-3 | 2 | confirm | low | fixed | I4 covers any git or gh call naming a strain or probe layout path, and the pin extends to arguments; the probe clean start removes as clean-up does; a kept worktree is never opened in place, rescue is only by push from the main checkout. |
| S2-4 | 2 | confirm | low | fixed | Consumer degradation rows for `perl` (or #608's raw-syscall tool) and a macOS loopback proxy. |
| S2-5 | 2 | confirm | low | fixed | D3 names its departure from ADR-0046 decisions 6 and 7 and its ground. |
| S2-T1 | 2 | review | high | fixed | Deny-by-default view of named read-only binds on a fresh root: host FIFOs outside the binds are never visible; the probe case walks the view and fails closed on any FIFO, socket or device node outside the allowlist. |
| S2-T2 | 2 | review | high | fixed | Same view: host mounts made after launch outside the named binds are never visible. What remains is a special file or mount made after launch under a bound path by root or by the user's own processes outside the Lair, a named residual with ground and bound. |
| S3-1 | 3 | confirm | medium | fixed | The builder refuses a read-only bind whose resolved source is or contains `/`, `$HOME`, the state root or the Claude Code folder; WSL2 Windows `PATH` entries are dropped; refusal and passing test cases; degradation row. |
| S3-2 | 3 | confirm | low | fixed | The residual for a special file or mount made after launch is bounded as a kernel or sandbox bug: the 2026-11-21 amendment's forged marker and ADR-0045's prompt-injected strain residual. |
| S3-3 | 3 | confirm | low | fixed | The head check lstats the loose ref as it does `HEAD`, a failed check keeps the worktree; the shared-store residual names the stall as a denial of service. |
| S3-4 | 3 | confirm | low | fixed | Probe case `special-files` fails on FIFOs only and reports sockets and device nodes. |
| S3-T1 | 3 | review | medium | rejected | Reason: ADR-0046's head binding exists so the merged design is the reviewed design. Here the pass stamp is the design's blob, checked against the final pull request head before merge, so the merged bytes are the reviewed bytes; every reviewed commit is in the pull request's history (D3). The later `solution-design.md` amendment (D4) is outside this part review and is flagged for the epic re-review. The review closed after round 5 with verdict `fail` and no stamp, so no pass relies on this reason; the docs pull request's head is reviewed by the pull request's own review. |
| S4-1 | 4 | confirm | low | fixed | Probe case `wsl-interop` runs a Windows program copied into the session's scratch folder by path, and passes only on a failure after exec. |
| S4-2 | 4 | confirm | low | fixed | Every Lair git call in its checkout, Lair-mode `spawn-brood.sh` worktree calls included, runs under the child timeout; admin-folder `HEAD` and `gitdir` FIFOs named in the shared-store residual; Failure modes row. |
| S4-3 | 4 | confirm | low | fixed | The wide-bind rule compares against the resolved forms of `$HOME`, the state root and the Claude Code folder; symlinked-home fixture; the probe's `control` case targets the resolved state root. |
| S4-4 | 4 | confirm | low | fixed | The record names no stamp check because the review closed with no stamp; the S3-T1 note now says so. |
| S4-5 | 4 | confirm | low | fixed | The round-3 trust choices are listed for veto as D11 to D13. |
| S4-T1 | 4 | review | high | fixed | The head check runs no git against the shared ref store: it reads `HEAD`, the loose ref and `packed-refs` each by one no-follow, non-blocking open, fstat and bounded read of that descriptor, gates the commit id, and tests ancestry only in the Lair's own bare repository; Lair mode refuses a non-`files` ref backend; race and packed-refs pins. |
| S4-T2 | 4 | review | medium | rejected | Reason: the review closed after round 5 with verdict `fail` and no stamp, so no pass outside record-format's pass rule exists. The cap raises are the maintainer's decisions, recorded here, with precedent in [claim-integrity-review-record.md](claim-integrity-review-record.md), whose cap the user raised to 6. |
| S5-1 | 5 | confirm | medium | fixed | The merge lane clause is narrowed to the clean-up head check, which resolves no strain branch against the shared ref store, so strain launch's moved-head check and clean-up keep their local ref calls; the Amendments entry, Changes to shared documents and "Seam with the merge lane" carry the same text (D15). |
| S5-2 | 5 | confirm | low | fixed | At clean-up of a kept worktree the Lair `lstat`s its admin folder's `HEAD`, `gitdir` and `commondir`, opening none, unlinks each that is not a regular file and names the path in the queue report; the shared-store residual says a FIFO at a loose ref stays until the user removes it; Failure modes row; `tools/test_lair_tick.sh` pins (D16). |
| S5-3 | 5 | confirm | low | fixed | #604's Seam order row owns the timeout wrap of Lair-mode `spawn-brood.sh`'s git calls, 300 seconds with a 10-second kill grace, by the timeout tool of claim integrity's Start step 1, with a `tools/test_lair_strain.sh` case; #608's row and "Seam with #608" own the Start refusal `ref-backend-unsupported` and the timeout on `git worktree prune`, with `tools/test_lair_tick.sh` cases for reftable, unset and `files`. |
| S5-4 | 5 | confirm | low | fixed | Case `wsl-interop` takes `cmd.exe` from the path `wslpath -u` prints, checks the copy is present and executable, then passes on any non-zero result, `ENOENT` included, and passes with no copy when the `WSLInterop` entry is absent or disabled; Consumer degradation row; Live-probe assumptions row on the binfmt flags. |
| S5-5 | 5 | confirm | low | fixed | The Amendments entry and Changes to shared documents name the two Seam order ADRs cell edits: ADR-0045 decision 9 for #604, the 2026-11-22 amendment on process reach for #612. |
| S5-T1 | 5 | review | high | rejected | Reason: the maintainer joined the design knowing its review closed `fail` (answer B, 2026-11-24), with precedent in [claim-integrity-review-record.md](claim-integrity-review-record.md). The finding raises no defect in the design's content. The Lair re-review of `solution-design.md`, flagged in the pull request, checks the join. |
| L-1 | 5 | review | high | rejected | Local review finding `0f9741891d0808b1f7a717f0430698aa6842226ee748f0eedb7dac6e1de1feae`, "Failed, unstamped part design is joined despite the pass prerequisite". Reason: as S5-T1. |
| L-2 | 5 | review | high | fixed | Local review finding `13dfa9dee65dbb57efaa236c924d14a0a6cd02d756f233e63bcbcf8e3dfc8d91`, "WSL interop probe treats successful out-of-sandbox execution with a nonzero exit as containment". S5-4's pass rule accepted any non-zero result, which a Windows program that ran outside the sandbox can also give. Case `wsl-interop` now runs the copy with `/c type nul > W`, a witness under `control/`, and passes only on a non-zero result with no witness; the Lair first runs the copy outside the sandbox and the case cannot run unless that run creates its witness. The Live-probe assumptions row on the binfmt flags states the same rule. L-4 replaces this witness and control: the witness is a registry key named for `N`, and the Lair runs only layout `a`'s copy, before session `a` starts. |
| L-3 | 5 | review | high | fixed | Local review finding `50c4e6ea20d3e1648bc28ad4b034b916a575fb6bb7abd2fed40de1b33fd4fd91`, "External-service probes can pass after successfully crossing the sandbox boundary": the analogous sites of L-2. Case `tmux-default` now has a positive control: the Lair's own `tmux -L default list-sessions` must list the probe session, so the sandboxed call's failure cannot be an empty server, and a failed control is a case that cannot run. Case `service-user` runs `systemd-run --user --wait --collect` of a command that creates a witness under `control/`, and passes only with no witness. The Cases preamble now states the class rule: no pass rests on the exit status alone of an attempt against a real service; a command attempt has a Lair-checked witness and a query attempt a positive control. |
| L-4 | 5 | review | high | fixed | Local review finding `c022cc22392dd829cb104aaf82b5c740d74b7331328f421ffd4faae791251c77`, "WSL witness path is put into cmd.exe /c syntax with no quoting rule". With L-2 and L-3 it forms one root cluster: the probe's witness commands and controls took values each command grammar had to quote, and the `wsl-interop` control ran a file in a probe layout outside the sandbox. Fixed by construction in the Cases preamble: each varying word of a command handed to a service, or of a control's arguments, holds only `[A-Za-z0-9._/-]`, since every such path lies under the state root and its pattern; a Windows-side command takes no path argument; outside the sandbox the Lair runs only host programs, and a probe layout's file only before session `a` starts. Case `wsl-interop` now uses the registry key `HKCU\Software\hivemind-probe-<N>\<x>` as its witness, which the host `cmd.exe` queries in step 8, and no `wslpath -w` path. The `service-user` row and inherited finding R2-1's row name its witness command (D17). The maintainer approved this plan (2026-11-24). L-5 and L-6 replace this rule (D18): the byte rule and the grammar claims are removed, and each attempt through a service has a control the Lair runs outside the sandbox. |
| L-5 | 5 | review | high | fixed | Local review finding `77456829fcf7d8ebbf1dd916ea72306add2291308e3c58fca8c436c2e5503438`: L-4's rule covered only commands handed to a service and controls' arguments, so the agent plist of case `launchd` and the app bundle of case `launchservices` had path arguments with no fixed place and no byte limit. With L-6 it shows L-4's class fix left its class open: each rule argued that the commands it named were well formed, so a command, argument or template it did not name fell outside it. Fixed by a change of approach (D18): no case passes on an attempt that would also fail outside the sandbox. Each attempt that hands a command to a service or a tmux server, or asks a service the Lair did not make, has a control, the probe script's own step run by the Lair outside the sandbox with `check` as its session letter, which must show its witness or answer, or the case cannot run; each file such an attempt hands a service is one the Lair made in the layout's scratch folder, and the session checks it is present. The byte rule and the grammar claims are removed. `tmux-default` makes the same call as its control; `launchd`, `launchservices` and `preferences` name their files, labels and domains per session letter; `service-user` passes with no attempt on a host with no user service manager; Consumer degradation gains the macOS row for the controls' Automation permission and GUI session; `tools/test_lair_tick.sh` gains the control pins. |
| L-6 | 5 | review | high | fixed | Local review finding `d7a7331ed92ff7172a915c3446f7c9dfcb4b9ac42dd0a21c5138dc76fd49d7da`: the registry witness `HKCU\Software\hivemind-probe-<N>\...` holds backslashes, outside L-4's own byte set. Closed by D18, which removes the byte rule: the key is fixed text that the control proves, and step 8's query must list the control's key `check`. |
| L-7 | 5 | review | medium | fixed | Local review finding `5b11377277761113d142a6040ebde728ddb87e0407e528ecbc112ca85054cd57`: the `solution-design.md` Amendments entry of 2026-11-24 ends with a paragraph, on the failed review and the maintainer's override, that the proposed text under the design's Changes to shared documents lacked, though the two must match. That paragraph is added to the proposed text; `solution-design.md` is unchanged. |
| L-8 | 5 | review | high | rejected | Reason: local review finding `def0bef476b07fe5aeeacf3db987c070d29e86c28548b013b69ef50ceb1736c9`, "Controls that run outside the sandbox have no rule against command injection", assumes the controls' paths may hold spaces or parentheses. Every path a control or a witness command carries lies under the state root, which claim integrity's Start limits to `^/[A-Za-z0-9._/-]+$`, refusing start otherwise; the Cases preamble now states this bound. The checkout path, whose launcher gate allows a space, appears in no control. The maintainer chose this disposition (answer 1, 2026-11-24). |

## Decisions taken, listed for veto

- **D1.** Keep a separate part record in record-format shape, outside the engine and verify. The epic record stays untouched. Strength: strong. Touches: none.
- **D2.** Skip the engine's `round`, because it reads the epic record and the PRD lacks a `**UI:**` line, so `round` prints ui=invalid. Stamp through `git rev-parse`. Strength: strong. Touches: none.
- **D3.** Reviewed commits are commits on the working branch, which the docs pull request carries; the pull request opens after the review closes and validation and local review hold, because this run's Instinct path opens a pull request only on a commit both gates passed. This departs from ADR-0046 decision 6 (the guide records the docs pull request's head before each pass) and decision 7 (the reviewed commit is the pull request head). Ground: this part record is kept outside the engine (D1), and every reviewed commit is in the pull request's history. Strength: strong. Touches: scope (ADR-0046 process).
- **D4.** The joining Amendments entry in `solution-design.md` lands in this PR although this review closed with verdict `fail`. That is the maintainer's decision (Decisions asked, Round 5 outcome), not a recommendation. The PR body flags that the Lair review record needs a re-review. Strength: none — asked. Touches: scope.
- **D5.** No PRD, ADR-0045 or epic-record edit is expected. The design stays inside ADR-0045 decision 9 and the 2026-11-21 and 2026-11-22 amendments. Strength: strong. Touches: none.
- **D6.** S1-T2 fix: on macOS, deny the out-of-profile execution channels (launchd, LaunchServices, Apple Events) and probe each; fail closed when any is open, instead of running macOS strains with a known escape as a residual. Strength: strong. Touches: trust.
- **D7.** All round-1 medium and low findings are fixed now rather than deferred or recorded: each had a contained fix in the part design. Strength: strong. Touches: trust.
- **D8.** S2-T1 and S2-T2 fix: the Linux view is a fresh root with named read-only binds, replacing the read-only bind of the whole host root and its per-submount binds. Strength: strong. Touches: trust.
- **D9.** S2-1 fix: the macOS profile denies preference writes and the probe checks it. Strength: strong. Touches: trust.
- **D10.** S3-T1 rejected on the blob-stamp ground. Strength: strong. Touches: scope (ADR-0046 process).
- **D11.** S3-1 fix: a `PATH` link to WSL's `/init` (`/usr/bin/wslpath`, `/sbin/mount.drvfs`) is not followed, so `/` is never bound. Strength: strong. Touches: trust.
- **D12.** S3-1 fix: WSL2 Windows drive-mount `PATH` entries are dropped from the view, not refused. Strength: strong. Touches: trust.
- **D13.** S3-4 fix: probe case `special-files` fails on FIFOs only and reports sockets and device nodes. Strength: strong. Touches: trust.
- **D14.** Round-4 findings fixed in the part design after round 4, and S4-T2 rejected; round 5 checked those fixes. Round-5 findings fixed after the last round, without a further review round. Strength: strong. Touches: scope (ADR-0046 process).
- **D15.** S5-1 fix: the clause is narrowed to the clean-up head check, rather than extending its no-git rule to strain launch's moved-head check and clean-up. Strength: strong. Touches: merge path.
- **D16.** S5-2 fix: at clean-up of a kept worktree the Lair unlinks each admin-folder `HEAD`, `gitdir` and `commondir` that is not a regular file. Strength: strong. Touches: trust.
- **D17.** L-4 fix: one rule for every probe command, under which each varying word holds only `[A-Za-z0-9._/-]`, a Windows-side command takes no path argument, and the Lair runs a probe layout's file only before session `a` starts; case `wsl-interop` witnesses with a registry key named for `N`. The other option, a pattern gate on the Windows path `wslpath -w` prints, keeps a translated path inside a `cmd.exe` redirect. Strength: strong. Touches: trust. D18 replaces its byte rule and grammar claims.
- **D18.** L-5 and L-6 fix, a change of approach after L-4's class fix left its class open: each attempt that hands a command to a service or a tmux server, or asks a service the Lair did not make, has a control, the probe script's own step run by the Lair outside the sandbox with `check` as its session letter, which must show its witness or answer, or the case cannot run; D17's byte rule and grammar claims are removed; each file such an attempt hands a service is made by the Lair in the layout's scratch folder. The other options: a rule on every value put into a command, which still needs a claim per command grammar, such as `cmd.exe` reading `/` as a switch, a scope that leaves out checkout paths, and passes an attempt that fails for another reason; dropping the real-service cases, which leaves the macOS channel cases, the only check of the profile; stopping, which hands #608 a rule its own registry witness breaks. The cost: on macOS the controls need the Automation permission for System Events and the user's GUI session, `service-user` needs its no-manager exception, and #608's probe runs each such step once more. Strength: strong. Touches: trust.

## Decisions asked

The first two are inputs, answered before this review.

- The user's answer 1A of 2026-11-22 at #633's design review round 1, recorded in the epic's [review record](review-record.md). #604 builds per-platform containment of `control/` and the Lair's tmux servers. #608's probe `sandbox` stops the Lair when containment cannot be confirmed. The merge lane's cache sits under `control/`.
- The user's choice of 2026-11-22 to split containment into its own part design with its own review, recorded in the epic's [review record](review-record.md).
- Round 2 diminishing-returns advisory (2026-11-24): options narrow / accept residuals / keep going. Answer: keep going (3).
- Round 3 cap and advisory (2026-11-24): fix all round-3 design findings, reject S3-T1, raise the cap to 4 for one confirming pass. Answer: A.
- Round 4 outcome (2026-11-24): per answer A, the review closes with verdict `fail` and no stamp; no fifth round. Superseded by the answer C below.
- Local-review join question (2026-11-24): answer C — run a fifth round to get a pass, then keep the join.
- Round 5 outcome (2026-11-24): answer B — fix all five round-5 findings, keep the join of an unpassed design citing the claim-integrity precedent, with the Lair re-review as the check; reject S5-T1; no sixth round.
- Local-review root cluster L-2, L-3, L-4 (2026-11-24): the structural fix repeats a surface an earlier class fix did not close; the maintainer accepted it ("Yes").
- Local-review root cluster L-5, L-6 (2026-11-24): L-4's class fix did not close its class, so the run forced an approach-level zoom-out. Options: a rule on the values put into commands; dropping cases or argv-only commands; stopping and shipping with the rest recorded for #608; a control for each attempt through a service. The maintainer chose the controls (D18).
- Local-review break-fix on the probe controls (2026-11-24): finding `def0bef4` said the controls, which run outside the sandbox, carry paths a command grammar could misread. Options: state the state-root bound and reject; rewrite every control so no path enters command text; stop and record it for #608. The maintainer chose to state the bound and reject (answer 1; row L-8).

## Residuals

None yet.
