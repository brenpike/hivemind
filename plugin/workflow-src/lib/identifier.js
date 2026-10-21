/*
 * identifier.js: the git identifier gate, the one check a branch or trunk
 * name passes before it reaches a git command.
 *
 * Inputs
 *   isGitIdentifier(value)
 *     value  any value.
 *
 * Outputs
 *   isGitIdentifier       true when value is a string that is not empty,
 *                         uses only the characters A-Z a-z 0-9 . _ / -,
 *                         does not start with '-' and holds no '..'.
 *                         Otherwise false.
 *   gitIdentifierPattern  the RegExp isGitIdentifier tests a string with.
 *                         It is anchored at both ends and has no flags, so
 *                         a trailing line feed fails it.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O.
 *   The rule's home is hivemind_assert_identifier in
 *   plugin/skills/_shared/allowlist.sh, the Shell Identifier Discipline
 *   gate of plugin/governance/security-policy.md: the full floor (not
 *   empty, no leading '-', no '..', no '$' or backtick, no TAB, LF or CR)
 *   plus the charset ^[A-Za-z0-9._/-]+$. The charset already shuts out
 *   every floor byte, so the floor adds only the empty, leading '-' and
 *   '..' rejects here. tests/workflow-scripts/identifier.test.mjs runs
 *   both on one corpus and requires the same verdict. A change to the rule
 *   lands in allowlist.sh and here together.
 *   The characters are ASCII only: no letter outside A-Z and a-z passes.
 *
 * Why
 *   A workflow checks a branch or trunk name it relays to a script before
 *   the script sees it, so a bad name stops the run in code with a clear
 *   message instead of a script blocker. The check must be the shell gate
 *   itself, or the two would let different names through.
 */

function gitIdentifierPattern() {
  return /^(?!-)(?!.*\.\.)[A-Za-z0-9._\/-]+$/;
}

function isGitIdentifier(value) {
  return typeof value === 'string' && gitIdentifierPattern().test(value);
}
