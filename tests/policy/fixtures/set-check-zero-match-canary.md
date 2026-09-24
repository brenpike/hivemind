# set_check zero-match canary target

This file is the target consumed by the `SAFETY-CANARY` set_check zero-match
self-test in `tools/policy_check.sh`. It is NOT a policy fixture (fixture
discovery is `safety-*.json` at the `tests/policy/` top level) and nothing else
in the repo reads it.

It exists to exercise two branches of `test_set_check`:

1. ZERO-MATCH branch. The self-test extracts with the regex
   `SETCHECK-ZERO-MATCH-CANARY <n>:` (digit-suffixed form), which matches
   NOTHING in this file. A capture of zero matches must still yield a valid
   empty JSON object and a clean pass. No digit-suffixed form of that token may
   EVER be added to this file: the ABSENCE of any match is the test. Adding one
   makes the self-test vacuous.

2. NON-VACUITY control. The self-test also extracts with the regex
   `SETCHECK-PRESENT-CANARY <n>:`, which matches the two lines below exactly
   once each. The control asserts a deliberately wrong occurrence count and so
   must FAIL — proving the zero-match pass in (1) is a real assertion and not a
   predicate that accepts anything.

Present-canary lines (one occurrence each, do not duplicate or remove):

- SETCHECK-PRESENT-CANARY 1: first present marker
- SETCHECK-PRESENT-CANARY 2: second present marker
