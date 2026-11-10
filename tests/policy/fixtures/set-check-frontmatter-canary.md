---
name: set-check-frontmatter-canary
tools:
  - Read
  - Bash(git status *)
---

# set_check frontmatter-key canary target

This file is the target of the `SAFETY-CANARY` set_check frontmatter-key
self-test in `tools/policy_check.sh`. It is NOT a policy fixture (fixture
discovery is `safety-*.json` at the `tests/policy/` top level) and nothing else
in the repo reads it.

The self-test reads the `tools` key above through `extract_frontmatter_key`,
which uses the CHECK 16 frontmatter reader, `check16_collect_entries`. A spec
that expects exactly `Read` and `Bash(git status *)` must PASS. A control spec
one member short must FAIL, and so must specs that name both extractors or
neither. Keep the frontmatter on line 1 and keep its `tools` list exactly as
written: the canary specs depend on it.
