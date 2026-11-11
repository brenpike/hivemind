/*
 * checks.js: the check retries of the planning pass a workflow shares. A
 * plan or revise result that fails its check goes back to its agent with
 * the check, and one still failing ends the run.
 *
 * Inputs
 *   run     the run state of the workflow's main.js. callCheckedPlanner
 *           reads trunk, references, level and relaySentence.
 *   facts   the checked facts of the pass, from runFactsStep (lib/runner.js).
 *   call    {prompt, label, phaseTitle, schema} of one plan or revise call.
 *           call.prompt is the prompt before run.relaySentence is added.
 *   maxCheckRetries(), isFixableResult, buildCheckFixPrompt and
 *   hasDefectQuestion of lib/retry.js, plannerCallOptions and
 *   addRelaySentence of lib/runner.js and describePlanProblem of
 *   lib/plan.js.
 *   The constants of the workflow's main.js this file reads: RUN_NAME and
 *   PLANNER_QUESTION_KIND, and the data constants AUTONOMY_TABLE and
 *   BRIEF_SCHEMA. It reads no workflow function. Every workflow whose code
 *   calls callCheckedPlanner declares them.
 *
 * Outputs
 *   callCheckedPlanner(run, facts, call)  {planResult, problem,
 *           isExhausted} of the last planner call.
 *   The retry prompt (buildCheckFixPrompt) and the terminal report cause of
 *   a result still failing its check (describeCheckLimit) are in
 *   lib/retry.js, which runScopeStep (standard-delivery scope.js) also
 *   reads.
 *   callCheckedPlanner normalizes each result with normalizePlanTitle
 *   (lib/title.js) before the plan check.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this library into it, so a row can name a
 *   function of this library.
 *   Each plan and revise call goes through callCheckedPlanner: a result
 *   isFixableResult (lib/retry.js) accepts that fails the plan check is
 *   asked again with buildCheckFixPrompt, label plan-P-fix-N or revise-R-fix-N, up to
 *   maxCheckRetries() times, and one still failing ends the run, terminal
 *   with next action report, through describeCheckLimit. A null result, an
 *   agent failure, and a planner blocked outcome that fits its schema and
 *   gives a reason are never asked again.
 *   A plan result that passes the plan check still fails it when decide()
 *   (kind planner_question, the run level) gives one of its questions a
 *   reason in neither askReasons() nor auto: a defect in the brief, which
 *   the planner fixes, so the user is never asked a defect.
 *   Title type: normalizePlanTitle (lib/title.js) never changes the agent
 *   result, so describePlanProblem (lib/plan.js) still refuses any typed title
 *   it returns as is.
 *   The retry prompt is the first prompt with one fix line after its first
 *   line and a check data block at its end, so it holds every block the
 *   first prompt holds. run.relaySentence is added last, with
 *   addRelaySentence (lib/runner.js) at each send, to the first prompt and
 *   to each retry prompt, so it stays on line two and the fix line of a
 *   retry is line three.
 *
 * Why
 *   A check slip is fixed by the agent that made it, never asked of the
 *   user, and a bounded retry count keeps a result that never fits from
 *   looping.
 */

/**
 * Calls the planner with call.prompt plus run.relaySentence
 * (addRelaySentence), normalizes its title and checks it.
 * A fixable problem calls it again with buildCheckFixPrompt plus
 * run.relaySentence, label
 * call.label plus '-fix-N', up to maxCheckRetries() times. Returns
 * {planResult, problem, isExhausted}: isExhausted when the last result
 * still has a fixable problem.
 */
/**
 * Returns a fixed problem when hasDefectQuestion (lib/retry.js) finds a
 * question of the complete planResult with a reason in neither askReasons()
 * nor auto, else undefined.
 */
function describeQuestionProblem(planResult, run) {
  return hasDefectQuestion(planResult.questions, PLANNER_QUESTION_KIND, run.level, AUTONOMY_TABLE, BRIEF_SCHEMA) ? 'A planner question fails the decision check, so ' + RUN_NAME + ' stopped.' : undefined;
}

async function callCheckedPlanner(run, facts, call) {
  let attempt = call.prompt;
  for (let retry = 0; ; retry += 1) {
    const label = retry === 0 ? call.label : call.label + '-fix-' + retry;
    const result = normalizePlanTitle(await agent(addRelaySentence(attempt, run), plannerCallOptions(label, call.phaseTitle, call.schema)), call.schema);
    const planProblem = describePlanProblem(result, call.schema, facts, run.trunk, run.references);
    const problem = planProblem === undefined ? describeQuestionProblem(result, run) : planProblem;
    const isFixable = problem !== undefined && isFixableResult(result, call.schema);
    if (!isFixable || retry === maxCheckRetries()) {
      return { planResult: result, problem: problem, isExhausted: isFixable };
    }
    attempt = buildCheckFixPrompt(call.prompt, problem, validateSchema(call.schema, result).errors);
  }
}
