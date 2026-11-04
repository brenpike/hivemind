---
name: tdd
description: Implements features test-first via red-green-refactor TDD. Use when the user asks to TDD a feature or write tests first.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash(dotnet *)
  - Bash(pytest *)
  - Bash(npm *)
  - Bash(npx *)
  - Bash(go test *)
  - Bash(cargo test *)
  - Bash(mix test *)
  - Bash(bundle exec rspec *)
shell: bash
---

# Test-Driven Development (Red-Green-Refactor)

Requires Write and Edit access — invoke only in a context that can modify source and test files.

TDD produces better designs because writing the test first forces you to think about the interface before the implementation. The test is the first caller — if it's awkward to test, the interface is awkward to use.

See `${CLAUDE_PLUGIN_ROOT}/skills/tdd/references/tests.md` for good/bad test examples.
See `${CLAUDE_PLUGIN_ROOT}/skills/tdd/references/mocking.md` for when (and when not) to mock.

---

## Step 0: Read the project context

Before writing any code, do these in parallel:

1. **Read `CLAUDE.md`** — find the project's test command and any testing conventions. If none found, detect from project structure (see [Test runner detection](#test-runner-detection)).
2. **Read existing code** in the affected area — understand the domain language, existing interfaces, and conventions.

Record:
- `TEST_CMD` — the command to run tests (e.g., `dotnet test`, `npm test`, `go test ./...`)
- `SRC_FILE` — file where implementation will live
- `TEST_FILE` — file where tests will live

---

## Step 1: Plan before touching any code

Planning prevents the biggest TDD trap: writing tests for imagined interfaces.

Ask the user (or infer from the task if obvious):

1. **What is the public interface?** — the function/method/class signature the tests will call. Shape it for testability as you design it: see `${CLAUDE_PLUGIN_ROOT}/skills/tdd/references/interface-design.md`.
2. **Which behaviors matter most?** — list them in priority order

Align test names and interface vocabulary with the project's domain glossary (e.g. `CONTEXT.md`, if present) and honor any architectural decisions the project records (e.g. ADRs, if it keeps them).

You cannot test everything. Focus on:
- Happy path (primary use case)
- Key failure modes (invalid input, missing dependencies, error states)
- Edge cases that are genuinely risky (not every edge case)

Write the behavior list in plain language:
```
Behaviors to test:
1. addItem adds a product to an empty cart
2. addItem increases quantity if same product added twice
3. checkout fails when cart is empty
4. checkout returns order total
```

**Get user confirmation on the interface and behavior list before writing any code.**

---

## Step 2: RED → GREEN loop

Run one full cycle per behavior. Do not move to the next behavior until the current one is green.

### RED: Write one failing test

Write a test for exactly one behavior. Rules:

- Test through the **public interface only** — no internal methods, no database queries, no peeking inside the module
- The test name should read like a spec: `"checkout fails when cart is empty"` not `"test_checkout_error"`
- One logical assertion per test
- Use real dependencies where possible; mock only at system boundaries (external APIs, databases you don't control)

Then **run the tests** using `TEST_CMD`. The test must fail. If it passes, the test is wrong — it's testing nothing.

```
$ <TEST_CMD>
Failed  CartTests.CheckoutFailsWhenCartIsEmpty [< 1 ms]
```

If the test passes when it should fail: stop, diagnose why, rewrite the test.

### GREEN: Write minimal code

Write the **minimum code** to make this one test pass. Not the correct code. Not the complete code. The minimum.

Resist the urge to:
- Handle cases the current test doesn't cover
- Write helper functions the current test doesn't need
- Anticipate the next test

Run the tests again. All previously passing tests must still pass.

```
$ <TEST_CMD>
Passed  CartTests.CheckoutFailsWhenCartIsEmpty [< 1 ms]
```

If any previously-passing test now fails: fix it before moving on. Never proceed with a broken test suite.

**Repeat from RED for the next behavior.**

---

## Step 3: REFACTOR

After all behaviors are green, look for improvement opportunities:

- [ ] Extract duplicated setup into fixtures/helpers
- [ ] Simplify complex conditionals
- [ ] Move logic closer to the data it operates on
- [ ] Deepen shallow modules: prefer a small interface over a large one hiding a deep implementation. Fold trivial pass-through helpers into the abstraction that owns the logic.
- [ ] Long method → extract a helper, but keep the tests on the public interface — don't test the extracted private helper directly.
- [ ] New code reveals existing smells — what you just wrote may expose problems in adjacent existing code. Note or address them when they're covered by tests.
- [ ] Remove speculative code added "just in case"

**Rules:**
- Never refactor while RED. Get green first.
- Run the full test suite after every refactor step — not just at the end.
- Only refactor code covered by tests. Don't touch untested code.

After refactoring, run the full suite one final time to confirm everything is green.

---

## Step 4: Done

The feature is done when:
- All behaviors from the plan have at least one passing test
- All tests pass
- No test is coupled to implementation details (would break on a pure refactor)
- Code reads clearly against the domain language from CLAUDE.md

Report: list each behavior, its test, and `PASS`.

---

## Test runner detection

If CLAUDE.md doesn't specify a test command, detect from project structure:

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

If multiple indicators match or the test command cannot be determined, ask the user before running anything.

---

## Anti-patterns to avoid

**Horizontal slicing** — writing all tests first, then all code. This is not TDD. Each test should respond to what you learned writing the previous implementation.

**Testing implementation details** — if your test would break when you rename an internal function (without changing behavior), the test is wrong.

**Over-mocking** — mocking your own classes creates tests that verify mocks, not code. See `${CLAUDE_PLUGIN_ROOT}/skills/tdd/references/mocking.md`.

**Speculative implementation** — writing code for the next test while the current one is red. Stay in the current cycle.

**Skipping refactor** — green tests with messy code is not the goal. The refactor phase is required.

**Too-minimal-to-fail trap** — if your cycle 1 GREEN passes cycle 2's test without new code, your first implementation was too complete. The point of minimal code is to force the next test to fail. When in doubt, write something deliberately wrong: return a hardcoded value, ignore parameters, throw new NotImplementedException() for branches not yet tested. The next test will expose the gap and you'll add exactly what's needed. Example: `public decimal GetTotal() => 1.50m;` for a single-item test — obviously wrong, but it makes the next test genuinely RED.
