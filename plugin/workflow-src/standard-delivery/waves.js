/*
 * standard-delivery waves.js: the wave loop of the standard-delivery
 * workflow. It holds the worker schema and prompt, the worker outcomes
 * and the loop that runs each wave and its commit.
 *
 * Inputs
 *   run    the run state of main.js createRunState. The loop reads pass,
 *          replies and trunk, and updates waveCount and replans.
 *   plan   the accepted plan, from runPlanningPass (plan.js).
 *   facts  the checked facts of the pass, passed on to runGates.
 *   Each worker result: an object under WORKER_SCHEMA, or null.
 *
 * Outputs
 *   runPlanWaves(run, plan, facts)  what runGates (gates.js) returns once
 *          every step is done, else {result}, a blocked finish, or
 *          {replan}, the reasons of a needs_replan wave.
 *   buildNextActionProperty()  the next_action property the worker, gate
 *          edit and validate schemas share.
 *   The step, as meta.js names it:
 *   Waves   workers run each computeWave() wave in parallel().
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Every wave ends with the commit runner, whatever its workers returned,
 *   and a null worker result counts as blocked.
 *
 * Why
 *   A worker edits files and never commits, so the loop owns the commit
 *   of each wave and reads every worker outcome only after it.
 */

function buildNextActionProperty() {
  return {
    type: 'string',
    enum: ['fix_cause', 'run_again'],
    description: 'run_again when the cause is outside the repo and passes with no change, such as machine load, a timeout or a network failure. fix_cause otherwise.'
  };
}

function buildWorkerSchema() {
  return buildTaggedSchema({
    tag: 'outcome',
    properties: {
      outcome: {
        type: 'string',
        enum: ['complete', 'blocked', 'needs_replan'],
        description: 'complete when the step outcome holds. blocked when the step cannot be done. needs_replan when the plan must change before the step can be done.'
      },
      summary: { type: 'string', description: 'What you changed, in one or two sentences.' },
      blocker: { type: 'string', maxLength: 400, description: 'Why the step is blocked or needs a new plan, in one or two short sentences written for the user.' },
      next_action: buildNextActionProperty()
    },
    required: ['outcome', 'summary'],
    variants: {
      complete: { required: [], optional: [] },
      blocked: { required: [], optional: ['blocker', 'next_action'] },
      needs_replan: { required: [], optional: ['blocker'] }
    }
  });
}

function buildWorkerPrompt(step, waveScopes, plan, trunk) {
  return [
    'Do one step of the approved delivery plan: the step in the step block below.',
    boundarySentence(),
    dataBlocksSentence(),
    '',
    formatDataBlock('step', step),
    formatDataBlock('wave_scopes', waveScopes),
    formatDataBlock('plan_summary', plan.summary),
    formatDataBlock('git', { branch: plan.branch, base: plan.base, trunk: trunk })
  ].join('\n');
}

function listStepFiles(steps) {
  const files = [];
  for (const step of steps) {
    for (const file of step.files) {
      if (!files.includes(file)) {
        files.push(file);
      }
    }
  }
  return files;
}

function findPlanStep(plan, stepId) {
  return plan.steps.find((step) => step.id === stepId);
}

function createWorkerTask(step, waveSteps, plan, run) {
  const waveScopes = listStepFiles(waveSteps.filter((other) => other.id !== step.id));
  const prompt = addResumeNote(buildWorkerPrompt(step, waveScopes, plan, run.trunk), run);
  const options = { agentType: step.owner, schema: toAgentSchema(WORKER_SCHEMA), label: 'work-' + run.pass + '-' + step.id, phase: 'Waves' };
  return () => agent(prompt, options);
}

function readWorkerOutcome(step, result) {
  if (!validateSchema(WORKER_SCHEMA, result).ok) {
    return { stepId: step.id, status: 'blocked', reason: 'it returned no usable result.' };
  }
  if (result.outcome === 'complete') {
    return { stepId: step.id, status: 'complete' };
  }
  return { stepId: step.id, status: result.outcome, reason: describeReason(result.blocker), nextAction: result.next_action };
}

function describeBlockedWave(blockedOutcomes, commitValues) {
  const lines = ['A worker did not finish its step, so ' + RUN_NAME + ' stopped after the commit of its wave.'];
  blockedOutcomes.forEach((outcome) => lines.push('Step ' + encodeUntrustedText(outcome.stepId) + ' was blocked: ' + outcome.reason));
  if (commitValues.committed === 'true') {
    lines.push('The wave was committed as ' + commitValues.commit + ', so that commit can hold partial edits of the steps above.');
  } else {
    lines.push('The wave left nothing to commit, so the branch head stays ' + commitValues.commit + '.');
  }
  return lines.join('\n');
}

function describeReplanReasons(replanOutcomes) {
  return replanOutcomes.map((outcome) => 'Step ' + encodeUntrustedText(outcome.stepId) + ' needs a new plan: ' + outcome.reason).join('\n');
}

function requestStepReplan(run, replanOutcomes) {
  const reasons = describeReplanReasons(replanOutcomes);
  if (run.replans >= maxReplans()) {
    return { result: finishDeliveryBlocked('A worker asked for a new plan after ' + maxReplans() + ' replans, so ' + RUN_NAME + ' stopped.\n' + reasons, run) };
  }
  run.replans += 1;
  return { replan: { reason: reasons } };
}

async function runPlanWaves(run, plan, facts) {
  const doneIds = [];
  for (let waveNumber = 1; ; waveNumber += 1) {
    const wave = computeWave(plan.steps, doneIds);
    if (!wave.ok) {
      return { result: finishDeliveryBlocked('The plan steps cannot be scheduled, so ' + RUN_NAME + ' stopped: ' + toPrintableAscii(wave.problem), run) };
    }
    if (wave.all_done) {
      return runGates(run, plan, facts);
    }
    const waveSteps = wave.wave.map((stepId) => findPlanStep(plan, stepId));
    phase('Waves');
    const workerResults = await parallel(waveSteps.map((step) => createWorkerTask(step, waveSteps, plan, run)));
    run.waveCount += 1;
    const committed = await runCommitStep(run, plan, listStepFiles(waveSteps), 'commit-' + run.pass + '-' + waveNumber, 'wave');
    if (committed.problem !== undefined) {
      return { result: finishDeliveryBlocked(committed.problem, run) };
    }
    const outcomes = waveSteps.map((step, index) => readWorkerOutcome(step, workerResults[index]));
    const blockedOutcomes = outcomes.filter((outcome) => outcome.status === 'blocked');
    if (blockedOutcomes.length > 0) {
      const nextAction = blockedOutcomes.every((outcome) => outcome.nextAction === 'run_again') ? 'run_again' : 'fix_cause';
      return { result: finishDeliveryBlocked(describeBlockedWave(blockedOutcomes, committed.values), run, nextAction) };
    }
    const replanOutcomes = outcomes.filter((outcome) => outcome.status === 'needs_replan');
    if (replanOutcomes.length > 0) {
      return requestStepReplan(run, replanOutcomes);
    }
    wave.wave.forEach((stepId) => doneIds.push(stepId));
  }
}
