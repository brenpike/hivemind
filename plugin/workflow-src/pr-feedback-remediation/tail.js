/*
 * pr-feedback-remediation tail.js: the tail of the pr-feedback-remediation
 * workflow, run once a planning pass returns a settled or taken plan: the
 * base check, the head check, then the shared waves, gates and pull
 * request step, with this workflow's gate and pull request hooks.
 *
 * Inputs
 *   run    the run state of main.js. The tail reads trunk, pass, taken and
 *          head, and updates headMoves; the shared steps read and update
 *          every field lib/workers.js, lib/gates.js, lib/pr.js and
 *          lib/record.js name.
 *   plan   the plan runPlanningPass (lib/plan.js) returns once every
 *          question of its pass is settled or taken.
 *   facts  the checked facts of the pass, from runFactsStep
 *          (lib/runner.js).
 *   gates, entry  as lib/gates.js and lib/pr.js pass them to the hooks.
 *   The constants of main.js this file reads: RUN_NAME.
 *
 * Outputs
 *   runRemediationTail(run, plan, facts)  {result}, the run end, or
 *          {replan}, the data the next pass plans from.
 *   describeBaseStop(plan, run)  a terminal report cause when plan.base is
 *          not run.trunk, else undefined.
 *   readPassHead(run, plan, facts)  {} when the head the commit runner
 *          reads is facts.head, else a run end.
 *   The gate hooks lib/gates.js reads: gateIds() and
 *          configuredGateIds(), validation alone; gateNames();
 *          runGateStep(stepId, run, plan, facts, gates), the pull request
 *          step (lib/pr.js) for 'pr', else validation (lib/gates.js); and
 *          listNotConfiguredGateLines(), none.
 *   The pull request hooks lib/pr.js reads:
 *   buildPullRequestComment(run, gates)  a fixed lead naming commit
 *          run.head, then the run record of renderPullRequestRecord
 *          (lib/pr.js), only when run.taken holds an entry isShownDecision
 *          (lib/record.js) shows, else undefined, so no comment is sent.
 *   toPullRequestDecision(entry)  entry as it is: the routing decision of
 *          the review fix pass keeps its own problem text.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   The base check runs before any runner call of the tail. The head
 *   check is runCommitStep (lib/commit.js) with an empty file list, label
 *   head-P, before any wave, and its commit goes to observeHead. A head
 *   other than the facts head plans again once per run (run.headMoves);
 *   a second move is a terminal stop. Its stop has no step cause, so it
 *   never asks and runCommitStep returns {result}.
 *   Every agent prompt of the shared steps takes run.relaySentence as its
 *   second line through addResumeNote or addRelaySentence (lib/runner.js).
 *
 * Why
 *   The waves, gates and pull request step are shared with
 *   standard-delivery; only the checks before the first wave and the
 *   hooks are this workflow's own.
 */

function gateIds() {
  return ['validate'];
}

function configuredGateIds() {
  return gateIds();
}

function gateNames() {
  return { validate: 'validation' };
}

function runGateStep(stepId, run, plan, facts, gates) {
  return stepId === 'pr' ? runPullRequestStep(run, plan, gates) : runValidateGate(run, plan, facts, gates);
}

function listNotConfiguredGateLines() {
  return [];
}

function toPullRequestDecision(entry) {
  return entry;
}

function buildPullRequestComment(run, gates) {
  if (!run.taken.some(isShownDecision)) {
    return undefined;
  }
  const parts = ['The remediation pushed commit ' + run.head + ' to this pull request.', ...renderPullRequestRecord(run, gates)];
  return cleanPullRequestText(parts.join('\n\n'), true);
}

function describeBaseStop(plan, run) {
  if (plan.base === run.trunk) {
    return undefined;
  }
  return { problem: 'The plan base is not the trunk ' + encodeUntrustedText(run.trunk) + ', so ' + RUN_NAME + ' stopped before any wave.', terminal: true, nextAction: 'report' };
}

function requestHeadReplan(run) {
  if (run.headMoves > 0) {
    return stopDelivery([{ problem: 'The pull request branch moved again after a replan, so ' + RUN_NAME + ' stopped before any wave.', terminal: true }], run, [], true);
  }
  run.headMoves += 1;
  return { replan: { reason: 'The pull request branch moved after the facts were read, so plan again from the new facts.' } };
}

async function readPassHead(run, plan, facts) {
  const read = await runCommitStep(run, plan, { files: [], label: 'head-' + run.pass, stepName: 'head' }, []);
  if (read.values === undefined) {
    return read;
  }
  return read.values.commit === facts.head ? {} : requestHeadReplan(run);
}

async function runRemediationTail(run, plan, facts) {
  const baseStop = describeBaseStop(plan, run);
  if (baseStop !== undefined) {
    return { result: finishDeliveryBlocked([baseStop], run) };
  }
  const headEnd = await readPassHead(run, plan, facts);
  if (isRunEnd(headEnd)) {
    return headEnd;
  }
  return runPlanWaves(run, plan, facts);
}
