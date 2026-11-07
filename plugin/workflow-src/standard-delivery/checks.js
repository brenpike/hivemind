/*
 * standard-delivery checks.js: the check retries of the standard-delivery
 * workflow. A scope, plan or revise result that fails its check goes back
 * to its agent with the check, and one still failing ends the run.
 *
 * Inputs
 *   run     the run state of main.js createRunState. callCheckedPlanner
 *           reads trunk and references.
 *   facts   the checked facts of the pass, from runFactsStep (relay.js).
 *   call    {prompt, label, phaseTitle, schema} of one plan or revise call.
 *   maxCheckRetries() of main.js.
 *
 * Outputs
 *   callCheckedPlanner(run, facts, call)  {planResult, problem,
 *           isExhausted} of the last planner call.
 *   buildCheckFixPrompt(prompt, problem, errors)  the retry prompt, also
 *           built by runScopeStep (scope.js).
 *   describeCheckLimit(problem)  the terminal report cause of a result
 *           still failing its check after maxCheckRetries() retries.
 *   normalizePlanTitle(result, schema)  result, or a copy with its own
 *           commit type cut from plan.title.
 *   typedTitlePattern()  the commit type title prefix, also read by
 *           describePlanProblem (plan.js).
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Each plan and revise call goes through callCheckedPlanner: a result
 *   isFixablePlanResult accepts that fails the plan check is asked again
 *   with buildCheckFixPrompt, label plan-P-fix-N or revise-R-fix-N, up to
 *   maxCheckRetries() times, and one still failing ends the run, terminal
 *   with next action report, through describeCheckLimit. A null result, an
 *   agent failure, and a planner blocked outcome that fits its schema and
 *   gives a reason are never asked again.
 *   Title type: normalizePlanTitle returns a copy of a complete result
 *   that fits its schema whose cleaned plan.title starts with the plan's
 *   own commitTypeMap() value in any letter case, an optional
 *   parenthesized scope, '!' only when plan.breaking, and ':', with
 *   plan.title the trimmed rest when it is not blank; it never changes the
 *   agent result. Every other result is returned as is, so
 *   describePlanProblem (plan.js) still refuses any other typed title.
 *   The retry prompt is the first prompt with one fix line after its first
 *   line and a check data block at its end, so it holds every block the
 *   first prompt holds.
 *
 * Why
 *   A check slip is fixed by the agent that made it, never asked of the
 *   user, and a bounded retry count keeps a result that never fits from
 *   looping.
 */

function typedTitlePattern() {
  return new RegExp('^(' + Object.values(commitTypeMap()).join('|') + ')(\\([^()]*\\))?(!?):', 'i');
}

/**
 * Returns result, or, for a complete result that fits schema, a copy whose
 * plan.title drops a leading commit type that equals the plan's own type,
 * with '!' only when the plan is breaking, when text is left after it. A
 * result that fits schema holds plan only when its outcome is complete.
 */
function normalizePlanTitle(result, schema) {
  const plan = validateSchema(schema, result).ok ? result.plan : undefined;
  const match = plan === undefined ? null : typedTitlePattern().exec(cleanTitleText(plan.title));
  const rest = match === null ? '' : match.input.slice(match[0].length).trim();
  if (rest === '' || match[1].toLowerCase() !== commitTypeMap()[plan.classification] || (match[3] && !plan.breaking)) {
    return result;
  }
  return { ...result, plan: { ...plan, title: rest } };
}

/**
 * Returns false for a null result, an agent failure, and for a planner
 * blocked outcome that fits its schema and gives a reason; true for every
 * other result, which a check retry may fix. A result that fits schema
 * lacks plan only when its outcome is blocked.
 */
function isFixablePlanResult(result, schema) {
  return result !== null && !(validateSchema(schema, result).ok && result.plan === undefined && quoteDiagnostic(result.blocker) !== undefined);
}

/**
 * Returns prompt with a line asking for the result fixed after its first
 * line, and a check data block of problem and up to maxListedItems()
 * schema errors at its end.
 */
function buildCheckFixPrompt(prompt, problem, errors) {
  const lines = prompt.split('\n');
  return [lines[0], 'Fix your result per the check block.', ...lines.slice(1), formatDataBlock('check', { problem: problem, schema_errors: errors.slice(0, maxListedItems()) })].join('\n');
}

/**
 * Returns the terminal stop cause, next action report, of a result whose
 * problem stayed after maxCheckRetries() retries.
 */
function describeCheckLimit(problem) {
  return { problem: problem + ' It stayed after ' + maxCheckRetries() + ' retries.', nextAction: 'report', terminal: true };
}

/**
 * Calls the planner with call.prompt, normalizes its title and checks it.
 * A fixable problem calls it again with buildCheckFixPrompt, label
 * call.label plus '-fix-N', up to maxCheckRetries() times. Returns
 * {planResult, problem, isExhausted}: isExhausted when the last result
 * still has a fixable problem.
 */
async function callCheckedPlanner(run, facts, call) {
  let prompt = call.prompt;
  for (let retry = 0; ; retry += 1) {
    const label = retry === 0 ? call.label : call.label + '-fix-' + retry;
    const result = normalizePlanTitle(await agent(prompt, plannerCallOptions(label, call.phaseTitle, call.schema)), call.schema);
    const problem = describePlanProblem(result, call.schema, facts, run.trunk, run.references);
    const isFixable = problem !== undefined && isFixablePlanResult(result, call.schema);
    if (!isFixable || retry === maxCheckRetries()) {
      return { planResult: result, problem: problem, isExhausted: isFixable };
    }
    prompt = buildCheckFixPrompt(call.prompt, problem, validateSchema(call.schema, result).errors);
  }
}
