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

Requires Write and Edit access: invoke only in a context that can modify source and test files.

Execute a behavior-preserving "deepening" refactor of one chosen deepening candidate: reshape a cluster of **shallow** modules (small behaviour behind a large, leaky interface) into one **deep** module (a large amount of behaviour behind a small interface).

The discipline is **refactor-under-green**: pin behavior with tests before any structural change, and keep the tests GREEN throughout. Never reshape code while RED. If you cannot establish a green baseline, stop and report rather than refactor blind.

Use the architecture vocabulary (**module**, **interface**, **implementation**, **depth/deep/shallow**, **seam**, **adapter**, **leverage**, **locality**) and the **deletion test** of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/LANGUAGE.md` exactly; never drift into "component," "service," "API," or "boundary." The deepening mechanics and dependency categories come from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/DEEPENING.md`.

## Step 0: Resolve the candidate and the green-gate

Do both in parallel before touching any code.

### Resolve the deepening candidate

Accept **one chosen deepening candidate** from either source:

- **Live context (default):** a candidate in the conversation or plan: the shallow modules, the proposed deeper interface, the dependency category.
- **A file path (optional):** a blueprint the operator saved. Never require a file; its absence is no error.

If neither yields a candidate, stop and ask which module to deepen; never guess.

### Resolve the green-gate (the test command)

Take the test command from the project's documented convention, the **same source the framework uses for validation**: the repo-root `CLAUDE.md`, which is authoritative, or, when it specifies none, detection from project structure ([Test runner detection](#test-runner-detection)). Record it as `TEST_CMD`.

**Never install or bootstrap a test harness.** If no test mechanism is documented or present:

- If the project documents a **Validation Procedure** (e.g. a Markdown plugin, a docs repo, a linter-gated project with no unit tests), degrade to running that validation as the green-gate; its run is your GREEN.
- With no executable test mechanism and no documented validation, **flag that behavior cannot be pinned and stop**, reporting blocked.

Record:
- `CANDIDATE`: the shallow-module cluster to deepen and its proposed deep interface
- `TEST_CMD`: the green-gate command (or documented validation command)
- `SRC_FILES`: files where the deepened module will live
- `TEST_FILES`: files where tests live now and will live after relocation

## The refactor-under-green loop

Run the five steps in order. Invariant: **tests are GREEN before and after every structural change. Never deepen while RED.**

### Step 1: Pin behavior

Before changing anything, pin the module's **current observable behavior** with **characterization tests**: tests of what the code *currently does*, quirks included, not what it *should* do. If one breaks during the refactor, behavior changed.

- Test the shallow modules' **existing interface** as it is *today*, not the deep interface you intend to build.
- Assert on observable behavior (return values, raised errors, side effects visible through the interface), never on internal state.
- Cover the behaviors the deepening must preserve: the happy path, the key failure modes, and any genuinely risky edge cases the cluster handles today.
- A host test-authoring capability may do the pinning; this skill needs only a green baseline before Step 2.

Run `TEST_CMD` and confirm **GREEN**. This baseline is the contract the rest of the loop must not break.

```
$ <TEST_CMD>
PASS  characterization: order intake rejects empty cart
PASS  characterization: order intake totals line items
```

If you cannot reach GREEN here, **stop and report.**

### Step 2: Deepen under green

Reshape the cluster into one deep module, applying `${CLAUDE_PLUGIN_ROOT}/skills/_shared/DEEPENING.md`:

- **Merge the shallow modules** so the behaviour concentrates behind one small interface.
- **Place the seam** deliberately: where the interface lives is its own decision.
- **Classify the cluster's dependencies** (`DEEPENING.md` → Dependency categories) and let the category drive the seam treatment: *in-process* merges with no adapter; *local-substitutable* gets an internal seam tested with the stand-in; *remote but owned* gets a **port** with a production adapter and an in-memory test adapter; *true external* is an injected port with a mock adapter in tests.
- **Honor seam discipline** (`DEEPENING.md` → Seam discipline): introduce a port only when at least two adapters are justified (typically production + test).

Work in small moves and **run `TEST_CMD` after every move**; the characterization tests must stay GREEN the entire time.

**If a move turns the suite RED:** stop. Either the move changed behavior (revert it) or the characterization test was testing past the interface (fix the test only if it was genuinely coupled to internals, never to paper over a real behavior change or to make new behavior pass). Get back to GREEN before the next move.

### Step 3: Relocate tests to the deep interface

The deepened module's **interface is the new test surface** (`DEEPENING.md` → Testing: replace, do not layer).

- Write tests at the **deepened module's interface**, asserting on observable outcomes, not internal state.
- **Relocate** the behavior coverage to the new interface, then **delete the redundant shallow-module tests**: replace, do not layer.
- The Step 1 characterization tests either become the new interface tests (if they already crossed the right seam) or are superseded by them and deleted alongside the shallow-module tests.

Run `TEST_CMD`. Confirm GREEN at the new interface.

### Step 4: Deletion test

Apply the deletion test (`LANGUAGE.md` → The deletion test): imagine deleting the deepened module and inlining its body at every call site.

- Complexity would **reappear across N callers**: the module is genuinely deep and earns its keep. PASS.
- Complexity would **vanish**: the module is still a pass-through, and the deepening did not land. Reconsider the interface (it is probably still nearly as complex as the implementation) or whether this cluster was worth deepening at all.

A failed deletion test means the refactor is not done: return to Step 2 with a smaller, deeper interface.

### Step 5: Done

The refactor is complete when **all** hold:

- Behavior is preserved: the characterization tests (or their relocated successors) pass against the new interface.
- Tests pass at the **deepened interface**; redundant shallow-module tests are deleted, not layered.
- The **deletion test passes**.
- `TEST_CMD` is GREEN.

Report: the candidate deepened, the before/after interface, the dependency category and seam treatment, which tests were relocated and which were deleted, and the deletion-test result.

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

If multiple indicators match or the command cannot be determined, ask before running anything. If **no** indicator matches and no validation is documented, degrade to the project's Validation Procedure or report that behavior cannot be pinned; never install a harness to create one.
