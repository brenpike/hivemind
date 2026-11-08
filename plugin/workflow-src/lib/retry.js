/*
 * retry.js: the check retries both engines share. A result that fails its
 * check goes back to its agent with the check, up to a bounded count, and
 * one still failing ends the run.
 *
 * Inputs
 *   isFixableResult(result, schema)  result any value, what one agent()
 *                 returned; schema the result's tagged schema, whose tag
 *                 is outcome.
 *   buildCheckFixPrompt(prompt, problem, errors)  prompt the first prompt
 *                 of the call; problem a string; errors the
 *                 validateSchema (schema.js) errors of the result.
 *   describeCheckLimit(problem)  problem a string.
 *   hasDefectQuestion(questions, kind, level, table, schema)  questions an
 *                 array of decision briefs; kind the decision kind, fixed
 *                 by the call site; level the run's autonomy level; table
 *                 and schema as decide (decide.js) takes them.
 *
 * Outputs
 *   maxCheckRetries  2, the retries of one call whose result fails its
 *                 check.
 *   maxCheckErrors  5, the schema errors a retry prompt lists.
 *   isFixableResult  false for a null result, an agent failure, and for a
 *                 blocked outcome that fits schema and whose blocker
 *                 quoteDiagnostic (result.js) can quote; true for every
 *                 other result, which a check retry may fix.
 *   buildCheckFixPrompt  prompt with a line asking for the result fixed
 *                 after its first line, and a check data block of problem
 *                 and up to maxCheckErrors() errors at its end.
 *   describeCheckLimit  the terminal stop cause, next action report, of a
 *                 result whose problem stayed after maxCheckRetries()
 *                 retries.
 *   hasDefectQuestion  true when decide({kind, level, brief}, table,
 *                 schema) gives some brief a reason in neither askReasons()
 *                 nor auto, else false.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O. Inputs are never changed.
 *   The retry prompt is the first prompt with one fix line after its first
 *   line and a check data block at its end, so it holds every block the
 *   first prompt holds.
 *   A question decide() gives a reason outside the Ask Set is a defect in
 *   the brief, which the agent fixes, so the user is never asked a defect.
 *
 * Why
 *   A check slip is fixed by the agent that made it, never asked of the
 *   user, and a bounded retry count keeps a result that never fits from
 *   looping (issue 549).
 */

function maxCheckRetries() {
  return 2;
}

function maxCheckErrors() {
  return 5;
}

function isFixableResult(result, schema) {
  return result !== null && !(validateSchema(schema, result).ok && result.outcome === 'blocked' && quoteDiagnostic(result.blocker) !== undefined);
}

function buildCheckFixPrompt(prompt, problem, errors) {
  const lines = prompt.split('\n');
  return [lines[0], 'Fix your result per the check block.', ...lines.slice(1), formatDataBlock('check', { problem: problem, schema_errors: errors.slice(0, maxCheckErrors()) })].join('\n');
}

function describeCheckLimit(problem) {
  return { problem: problem + ' It stayed after ' + maxCheckRetries() + ' retries.', nextAction: 'report', terminal: true };
}

function hasDefectQuestion(questions, kind, level, table, schema) {
  return questions.some((brief) => !['auto', ...askReasons()].includes(decide({ kind: kind, level: level, brief: brief }, table, schema).reason));
}
