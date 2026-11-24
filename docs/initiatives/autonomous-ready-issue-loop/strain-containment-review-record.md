---
stamps: []
verdict: fail
open:
  critical: 0
  high: 0
  medium: 0
  low: 0
rounds: 1
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
- The pass stamp is `git rev-parse <reviewed>:<path>`.
- The epic record is not edited.
- Inherited findings join the Findings table at round 1 with IDs such as `integration R1-1`.
- New IDs are `S<round>-<n>` for the cerebrate pass and `S<round>-T<n>` for the local review tool pass.
- Each round runs one fresh read-only `hivemind:cerebrate` pass with "Memory context: none".
- The design touches a trust boundary and credentials, so each round also runs one local review tool pass, or records its skip.

## Rounds

### Round 1

Reviewed commit `5448a99df44c127e1389f09ea9ea6b5ec6ec1aa5`; merge-base `eb40ed9804b7ad92498ed42a8478b8edd3311e82`.

- Pass 1: reviewer cerebrate, on cerebrate's own model (`HIVEMIND_DESIGN_REVIEW_MODEL` unset, `model=default`), a fresh read-only pass with "Memory context: none". It covered the whole part design, with the PRD, the solution design, ADR-0045, the three part designs, the epic record and the CLAUDE.md principles as context: code truth, principles, governance and ADR conflicts, existing-path coverage, failure modes, trust and injection, and testability. It raised 10 findings and found integration R3-6 unfixed.
- Pass 2: reviewer the local review tool, preset `codex-plugin` (`HIVEMIND_LOCAL_REVIEWER` unset, Codex plugin installed), on the tool's own default model, base the merge-base, iteration 1, with the skill's fixed design-review focus. It raised 2 findings.
- All findings were fixed in the part design before round 2.

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

## Decisions taken, listed for veto

- **D1.** Keep a separate part record in record-format shape, outside the engine and verify. The epic record stays untouched. Strength: strong. Touches: none.
- **D2.** Skip the engine's `round`, because it reads the epic record and the PRD lacks a `**UI:**` line, so `round` prints ui=invalid. Stamp through `git rev-parse`. Strength: strong. Touches: none.
- **D3.** Reviewed commits are commits on the working branch, which the docs pull request carries. The pull request opens after the review passes, validation and local review hold, because the run's Instinct path opens a pull request only on a commit that both gates passed. Strength: strong. Touches: none.
- **D4.** The joining Amendments entry in `solution-design.md` lands in this PR after the pass record. The PR body flags that the Lair review record needs a re-review. Strength: strong. Touches: scope.
- **D5.** No PRD, ADR-0045 or epic-record edit is expected. The design stays inside ADR-0045 decision 9 and the 2026-11-21 and 2026-11-22 amendments. Strength: strong. Touches: none.
- **D6.** S1-T2 fix: on macOS, deny the out-of-profile execution channels (launchd, LaunchServices, Apple Events) and probe each; fail closed when any is open, instead of running macOS strains with a known escape as a residual. Strength: strong. Touches: trust.
- **D7.** All round-1 medium and low findings are fixed now rather than deferred or recorded: each had a contained fix in the part design. Strength: strong. Touches: trust.

## Decisions asked

Both are inputs, answered before this review.

- The user's answer 1A of 2026-11-22 at #633's design review round 1, recorded in the epic's [review record](review-record.md). #604 builds per-platform containment of `control/` and the Lair's tmux servers. #608's probe `sandbox` stops the Lair when containment cannot be confirmed. The merge lane's cache sits under `control/`.
- The user's choice of 2026-11-22 to split containment into its own part design with its own review, recorded in the epic's [review record](review-record.md).

## Residuals

None yet.
