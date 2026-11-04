---
name: refactor-to-depth
description: Deepens a module via a behavior-preserving structural refactor. Use when deepening a module or extracting behind a port.
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - LSP
  - Bash(dotnet *)
  - Bash(pytest *)
  - Bash(npm *)
  - Bash(npx *)
  - Bash(npx vitest *)
  - Bash(go test *)
  - Bash(cargo test *)
  - Bash(mix test *)
  - Bash(bundle exec rspec *)
shell: bash
disable-model-invocation: true
---

# Refactor to Depth (Refactor-Under-Green)

Requires Write and Edit access — invoke only in a context that can modify source and test files.

Execute a behavior-preserving "deepening" refactor: take a cluster of **shallow** modules — small behaviour behind a large, leaky interface — and reshape it into one **deep** module: a large amount of behaviour behind a small interface. This is the execution counterpart to architectural analysis: it consumes a chosen deepening candidate and applies it.

The discipline is **refactor-under-green**: behavior is pinned by tests before any structural change, and the tests stay GREEN throughout. You never reshape code while RED. If you cannot establish a green baseline, you cannot safely deepen — stop and report rather than refactor blind.

This skill uses the architecture vocabulary (**module**, **interface**, **implementation**, **depth/deep/shallow**, **seam**, **adapter**, **leverage**, **locality**) and the **deletion test** from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/LANGUAGE.md`. Use those terms exactly — do not drift into "component," "service," "API," or "boundary." The deepening mechanics and dependency categories come from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/DEEPENING.md`.

---

## Step 0: Resolve the candidate and the green-gate

Do these in parallel before touching any code.

### Resolve the deepening candidate

This skill consumes **one chosen deepening candidate**. Accept it path-agnostically:

- **From live context (default).** A candidate described in the conversation or plan — the shallow modules involved, the proposed deeper interface, the dependency category. This is the normal case: the upstream analysis emits its blueprint inline and never auto-writes a file.
- **From a file path (optional).** If the operator saved a blueprint to a file, read it from that path. Do not require a file to exist — absence of a file is not an error.

If no candidate is identifiable from either source, stop and ask which module to deepen. Do not guess.

### Resolve the green-gate (the test command)

Read the test command from the project's documented convention — the **same source the framework uses for validation**:

1. **Read `CLAUDE.md`** at the repo root — find the project's test command and validation convention. This is the authoritative source.
2. If `CLAUDE.md` does not specify one, detect from project structure (see [Test runner detection](#test-runner-detection)).

Record `TEST_CMD` — the command that establishes GREEN.

**Never install or bootstrap a test harness.** This skill runs an existing green-gate; it does not create one. If no test mechanism is documented or present:

- If the project documents a **Validation Procedure** (e.g. a Markdown plugin, a docs repo, a linter-gated project with no unit tests), DEGRADE to running that documented validation as the green-gate. The validation run is your GREEN.
- If there is no executable test mechanism and no documented validation, **flag that behavior cannot be pinned and stop.** Report blocked. Do not install anything to manufacture a gate.

Record:
- `CANDIDATE` — the shallow-module cluster to deepen and its proposed deep interface
- `TEST_CMD` — the green-gate command (or documented validation command)
- `SRC_FILES` — files where the deepened module will live
- `TEST_FILES` — files where tests live now and will live after relocation

---

## The refactor-under-green loop

Five steps. Run them in order. The invariant across all of them: **tests are GREEN before and after every structural change. Never deepen while RED.**

### Step 1: Pin behavior

Before changing anything, pin the module's **current observable behavior** with **characterization tests**, then confirm GREEN.

> **Characterization test** — a test that pins what the code *currently does*, not what it *should* do. It captures observed behavior (including quirks) through the module's existing interface, so a behavior-preserving refactor has a safety net: if a characterization test breaks during the refactor, behavior changed, and the refactor is no longer behavior-preserving.

Rules for this step:

- Write characterization tests against the **existing interface** of the shallow modules — the interface as it is *today*, not the deep interface you intend to build.
- Capture observable behavior: return values, raised errors, side effects visible through the interface. Do not assert on internal state.
- Cover the behaviors the deepening must preserve: the happy path, the key failure modes, and any genuinely risky edge cases the cluster handles today.
- **Pin behavior with tests before changing anything.** (Where the host framework offers a test-authoring capability, behavior pinning may be satisfied by it; this skill's concern is only that a green baseline exists before Step 2.)

Run `TEST_CMD`. Confirm **GREEN**. This green baseline is the contract the rest of the loop must not break.

```
$ <TEST_CMD>
PASS  characterization: order intake rejects empty cart
PASS  characterization: order intake totals line items
```

If you cannot reach GREEN here, **stop and report.** You cannot deepen safely without a baseline.

### Step 2: Deepen under green

Reshape the cluster into one deep module while the tests stay GREEN. Apply the mechanics in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/DEEPENING.md`:

- **Merge the shallow modules** so the behaviour concentrates behind one small interface.
- **Place the seam** deliberately — where the interface lives is its own decision, distinct from what goes behind it.
- **Classify the cluster's dependencies** (`DEEPENING.md` → Dependency categories) and let the category drive the seam treatment:
  - *In-process* (pure computation, in-memory state) — merge and test through the new interface directly; no adapter.
  - *Local-substitutable* (a local stand-in exists, e.g. PGLite, in-memory filesystem) — internal seam, test with the stand-in in the suite.
  - *Remote but owned* (your own services across a network) — define a **port** at the seam; production gets an HTTP/gRPC/queue adapter, tests get an in-memory adapter.
  - *True external* (third-party you do not control) — take the dependency as an injected port; tests provide a mock adapter.
- **Honor seam discipline** (`DEEPENING.md` → Seam discipline): one adapter means a hypothetical seam, two means a real one. Do not introduce a port unless at least two adapters are justified (typically production + test). A single-adapter seam is just indirection.

Work in small moves. **Run `TEST_CMD` after every move.** The characterization tests must stay GREEN the entire time — they are pinning the behavior you are preserving.

**If a move turns the suite RED:** stop. Either the move changed behavior (revert it — a behavior-preserving refactor must not change behavior) or the characterization test was testing past the interface (fix the test only if it was genuinely coupled to internals, never to paper over a real behavior change). **Never deepen while RED.** Get back to GREEN before the next move.

### Step 3: Relocate tests to the deep interface

The deepened module's **interface is the new test surface** (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/DEEPENING.md` → Testing: replace, do not layer).

- Write tests at the **deepened module's interface** — assert on observable outcomes through that interface, not on internal state.
- **Relocate** the behavior coverage to the new interface, then **DELETE the redundant shallow-module tests.** Replace, do not layer — old unit tests on the now-internal shallow modules are waste once tests at the deep interface exist. Keeping both is duplication, not safety.
- The characterization tests from Step 1 either become the new interface tests (if they already crossed the right seam) or are superseded by them and deleted alongside the shallow-module tests.

Run `TEST_CMD`. Confirm GREEN at the new interface.

### Step 4: Deletion test

Confirm the deepened module **earns its keep** by applying the deletion test (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/LANGUAGE.md` → The deletion test):

- Imagine deleting the deepened module and inlining its body at every call site.
- If complexity would **reappear across N callers**, the module concentrated something — it is genuinely deep and earns its keep. PASS.
- If complexity would simply **vanish**, the module is still a pass-through — you moved code without adding depth. The deepening did not land: reconsider the interface (it is probably still nearly as complex as the implementation) or whether this cluster was worth deepening at all.

A failed deletion test means the refactor is not done — return to Step 2 with a smaller, deeper interface.

### Step 5: Done

The refactor is complete when **all** hold:

- Behavior is preserved — the characterization tests (or their relocated successors) pass against the new interface.
- Tests pass at the **deepened interface**; redundant shallow-module tests are deleted, not layered.
- The **deletion test passes** — the module concentrates complexity that would otherwise reappear across callers.
- `TEST_CMD` is GREEN.

Report: the candidate deepened, the before/after interface, the dependency category and seam treatment, which tests were relocated and which were deleted, and the deletion-test result.

---

## Test runner detection

If `CLAUDE.md` does not specify a test command, detect from project structure:

| Indicator | Command |
|---|---|
| `*.csproj` with `Microsoft.NET.Test.Sdk` | `dotnet test` |
| `pyproject.toml` / `setup.py` / `*.py` tests | `pytest` |
| `package.json` with `jest` | `npm test` or `npx jest` |
| `package.json` with `vitest` | `npx vitest run` |
| `go.mod` | `go test ./...` |
| `Cargo.toml` | `cargo test` |
| `mix.exs` | `mix test` |
| `rspec` / `spec/` dir | `bundle exec rspec` |

If multiple indicators match or the command cannot be determined, ask before running anything. If **no** indicator matches and no validation is documented, DEGRADE to the project's Validation Procedure or report that behavior cannot be pinned — never install a harness to create one.

---

## Anti-patterns to avoid

**Deepening while RED** — reshaping code without a green baseline. You have no way to know whether the refactor preserved behavior. Pin behavior first (Step 1), keep it green through every move.

**Layering tests instead of replacing** — keeping the old shallow-module tests alongside new interface tests. The old tests now exercise internals of the deep module; they are duplication that will break on the next internal refactor. Delete them (Step 3).

**Testing past the interface** — asserting on the deep module's internal state instead of its observable outcomes. Such tests break on internal refactors and signal a misplaced seam.

**Building a single-adapter seam** — introducing a port when only one adapter exists. One adapter is a hypothetical seam, not a real one — it is indirection, not depth. Two adapters (production + test) justify a port.

**Moving code without adding depth** — merging modules but leaving an interface as complex as the implementation. The deletion test (Step 4) catches this: if inlining the module makes complexity vanish, you relocated code rather than deepening.

**Installing a test harness** — this skill never installs or bootstraps a harness. If no green-gate exists, degrade to documented validation or stop. Manufacturing a gate is out of scope.

**Changing behavior under cover of refactor** — a behavior-preserving refactor must preserve behavior. If a characterization test goes RED because behavior changed, revert the move; do not edit the test to make the new behavior pass.
