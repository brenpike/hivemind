# set_check zero-match canary target

This file is the target consumed by the `SAFETY-CANARY` set_check zero-match
self-test in `tools/policy_check.sh`. It is NOT a policy fixture (fixture
discovery is `safety-*.json` at the `tests/policy/` top level) and nothing else
in the repo reads it.

It exists to exercise five branches of `test_set_check`:

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

3. NON-COMPILING REGEX branch. The self-test also extracts with a regex that
   does not compile under perl. A regex that fails to compile must FAIL the
   check rather than being silently treated as a zero-match pass.

4. BROKEN-EXTRACTION branch. The self-test also extracts with a regex that
   compiles but has no capture group, so the extraction produces no captures
   at run time. That must FAIL the check: a broken extraction is never the
   same thing as a real zero-match result, and the two must not be conflated.

5. UNESCAPED-SLASH branch. The self-test also extracts with a regex containing
   an unescaped `/` delimiter character, matched against the slash-canary
   marker line below whose value is `a/b`. The regex reaches perl as data, not
   as program source, so the unescaped `/` must not break the match: the check
   must PASS and capture `a/b`.

Present-canary lines (one occurrence each, do not duplicate or remove):

- SETCHECK-PRESENT-CANARY 1: first present marker
- SETCHECK-PRESENT-CANARY 2: second present marker
- SETCHECK-SLASH-CANARY a/b: unescaped-slash delimiter marker
