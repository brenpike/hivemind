/*
 * standard-delivery waves.js: the wave loop of the standard-delivery
 * workflow. It holds the worker schema and prompt, the worker outcomes
 * and the loop that runs each wave and its commit.
 *
 * Inputs
 *   run    the run state of main.js createRunState. The loop reads pass,
 *          replies, trunk and approvals, and updates waveCount and replans.
 *   plan   the accepted plan, from runPlanningPass (plan.js).
 *   facts  the checked facts of the pass, passed on to runGates.
 *   Each worker result: an object under WORKER_SCHEMA, or null.
 *
 * Outputs
 *   runPlanWaves(run, plan, facts)  what runGates (gates.js) returns once
 *          every step is done, else a run end as is: {result}, a blocked
 *          finish or a pause, or {replan}, the reasons of a needs_replan
 *          wave or the reply to a stop.
 *   buildNextActionProperty()  the next_action property the worker, gate
 *          edit and validate schemas share.
 *   buildStageProperty() and describeHeldChanges()  the stage property
 *          and the destructive list description the worker and gate edit
 *          schemas share.
 *   describeUnusableEdit(result)  the cause of an unusable worker or gate
 *          edit result, through describeUnusableResult (lib/stop.js).
 *   buildWaveSubject(waveSteps, waveNumber)  the commit subject of a wave:
 *          the outcome of its one step, or the ids of its steps then the
 *          first outcome, through toCommitSubject (relay.js), whose
 *          fallback names the wave.
 *   The step, as meta.js names it:
 *   Waves   workers run each computeWave() wave in parallel().
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Every wave ends with the commit runner, whatever its workers returned.
 *   The loop reads every worker outcome before the commit, and a null
 *   worker result counts as blocked: its reason names the agent failure
 *   through describeUnusableResult (lib/stop.js), with next action
 *   run_again, and readWorkerOutcome passes its agentFailure mark on.
 *   readWorkerOutcome types a blocked worker through readGateHold
 *   (approvals.js) with run.approvals. describeBlockedWave makes the one
 *   cause of a blocked wave: a lead line naming the stop, then one line per
 *   blocked step in orderStopCauses order (lib/stop.js) through
 *   capItemLines, an approve step waiting for approval and a report hold
 *   stopped at the gate without a change the run can approve, the first
 *   giving the next action, so run_again only when every blocked worker
 *   says so, holds the {stepId, category, item} of each approve step's
 *   holds, and agentFailure when any blocked worker had a null result.
 *   The worker prompt carries the approvals block only when run.approvals
 *   is not empty. A plan that cannot be
 *   scheduled mid-run is a report stop. runCommitStep
 *   (relay.js) takes that cause as its step cause and stops with it through
 *   stopDelivery (record.js) as a replan, so a commit stop never hides it,
 *   and the loop returns that run end as is. Stops (issue 457): a wave with
 *   an agent failure ends the run; any other blocked wave, a plan that
 *   cannot be scheduled mid-run and a needs_replan at maxReplans() pause
 *   with one step_stop question, and the reply starts a new pass that does
 *   not count against maxReplans(), the needs_replan one with the worker
 *   reasons. needs_replan is handled only after a successful commit.
 *
 * Why
 *   A worker edits files and never commits, so the loop owns the commit
 *   of each wave. It reads the outcomes first so the commit runner gets the
 *   wave's cause, and it still commits whatever the workers left.
 */

function buildNextActionProperty() {
  return {
    type: 'string',
    enum: ['fix_cause', 'run_again'],
    description: 'run_again when the cause is outside the repo and passes with no change, such as machine load, a timeout or a network failure. fix_cause otherwise.'
  };
}

function buildStageProperty() {
  return { type: 'string', maxLength: 40, description: 'Worker Report stage.' };
}

function describeHeldChanges() {
  return 'With stage destructive-fix-gate: each change held back for approval, by gate category number and the one item it changes, named exactly.';
}

function describeUnusableEdit(result) {
  return describeUnusableResult('it returned no usable result.', result);
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
      next_action: buildNextActionProperty(),
      stage: buildStageProperty(),
      destructive: buildDestructiveListSchema(describeHeldChanges())
    },
    required: ['outcome', 'summary'],
    variants: {
      complete: { required: [], optional: [] },
      blocked: { required: [], optional: ['blocker', 'next_action', 'stage', 'destructive'] },
      needs_replan: { required: [], optional: ['blocker'] }
    }
  });
}

function buildWorkerPrompt(step, waveScopes, plan, run) {
  return [
    'Do one step of the approved delivery plan: the step in the step block below.',
    boundarySentence(),
    dataBlocksSentence(describeApprovalsHome(run.approvals, undefined)),
    '',
    formatDataBlock('step', step),
    formatDataBlock('wave_scopes', waveScopes),
    formatDataBlock('plan_summary', plan.summary),
    formatDataBlock('git', { branch: plan.branch, base: plan.base, trunk: run.trunk }),
    ...listApprovalsBlock(run.approvals)
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

function buildWaveSubject(waveSteps, waveNumber) {
  const firstOutcome = waveSteps[0].outcome;
  const text = waveSteps.length === 1 ? firstOutcome : waveSteps.map((step) => step.id).join(', ') + ': ' + firstOutcome;
  return toCommitSubject(text, 'complete wave ' + waveNumber + ' of the delivery plan');
}

function findPlanStep(plan, stepId) {
  return plan.steps.find((step) => step.id === stepId);
}

function createWorkerTask(step, waveSteps, plan, run) {
  const waveScopes = listStepFiles(waveSteps.filter((other) => other.id !== step.id));
  const prompt = addResumeNote(buildWorkerPrompt(step, waveScopes, plan, run), run);
  const options = { agentType: step.owner, schema: toAgentSchema(WORKER_SCHEMA), label: 'work-' + run.pass + '-' + step.id, phase: 'Waves' };
  return () => agent(prompt, options);
}

function readWorkerOutcome(step, result, approvals) {
  if (!validateSchema(WORKER_SCHEMA, result).ok) {
    const unusable = describeUnusableEdit(result);
    return { stepId: step.id, status: 'blocked', reason: unusable.problem, nextAction: unusable.nextAction, agentFailure: unusable.agentFailure };
  }
  if (result.outcome === 'complete') {
    return { stepId: step.id, status: 'complete' };
  }
  return Object.assign({ stepId: step.id, status: result.outcome, reason: describeReason(result.blocker) }, readGateHold(result, approvals));
}

function describeBlockedVerb(outcome) {
  if (outcome.holds === undefined) {
    return ' was blocked: ';
  }
  return outcome.nextAction === 'approve' ? describeGateWait() + ': ' : ' stopped at the destructive-fix gate without a change the run can approve: ';
}

function describeBlockedStep(outcome) {
  return '- Step ' + encodeUntrustedText(outcome.stepId) + describeBlockedVerb(outcome) + outcome.reason;
}

function listStepHolds(outcomes) {
  return outcomes.flatMap((outcome) => (outcome.nextAction === 'approve' ? outcome.holds.map((hold) => ({ stepId: outcome.stepId, ...hold })) : []));
}

function describeBlockedWave(blockedOutcomes) {
  const lead = 'A worker did not finish its step, so ' + RUN_NAME + ' stopped after its wave:';
  const orderedOutcomes = orderStopCauses(blockedOutcomes);
  const stepLines = orderedOutcomes.map(describeBlockedStep);
  const cause = { problem: [lead, ...capItemLines(stepLines)].join('\n'), nextAction: orderedOutcomes[0].nextAction };
  if (blockedOutcomes.some((outcome) => outcome.agentFailure === true)) {
    cause.agentFailure = true;
  }
  if (cause.nextAction === 'approve') {
    cause.holds = listStepHolds(orderedOutcomes);
  }
  return cause;
}

function describeReplanReasons(replanOutcomes) {
  return replanOutcomes.map((outcome) => 'Step ' + encodeUntrustedText(outcome.stepId) + ' needs a new plan: ' + outcome.reason).join('\n');
}

function requestStepReplan(run, replanOutcomes) {
  const reasons = describeReplanReasons(replanOutcomes);
  if (run.replans >= maxReplans()) {
    const cause = { problem: 'A worker asked for a new plan after ' + maxReplans() + ' replans, so ' + RUN_NAME + ' stopped.\n' + reasons };
    const stopped = stopDelivery([cause], run, [], true);
    return stopped.replan === undefined ? stopped : { replan: { reason: reasons } };
  }
  run.replans += 1;
  return { replan: { reason: reasons } };
}

async function runPlanWaves(run, plan, facts) {
  const doneIds = [];
  for (let waveNumber = 1; ; waveNumber += 1) {
    const wave = computeWave(plan.steps, doneIds);
    if (!wave.ok) {
      return stopDelivery([{ problem: 'The plan steps cannot be scheduled, so ' + RUN_NAME + ' stopped: ' + toPrintableAscii(wave.problem), nextAction: 'report' }], run, [], true);
    }
    if (wave.all_done) {
      return runGates(run, plan, facts);
    }
    const waveSteps = wave.wave.map((stepId) => findPlanStep(plan, stepId));
    phase('Waves');
    const workerResults = await parallel(waveSteps.map((step) => createWorkerTask(step, waveSteps, plan, run)));
    run.waveCount += 1;
    const outcomes = waveSteps.map((step, index) => readWorkerOutcome(step, workerResults[index], run.approvals));
    const blockedOutcomes = outcomes.filter((outcome) => outcome.status === 'blocked');
    const stepCauses = blockedOutcomes.length > 0 ? [describeBlockedWave(blockedOutcomes)] : [];
    const commit = { files: listStepFiles(waveSteps), label: 'commit-' + run.pass + '-' + waveNumber, stepName: 'wave', subject: buildWaveSubject(waveSteps, waveNumber) };
    const committed = await runCommitStep(run, plan, commit, stepCauses);
    if (committed.values === undefined) {
      return committed;
    }
    const replanOutcomes = outcomes.filter((outcome) => outcome.status === 'needs_replan');
    if (replanOutcomes.length > 0) {
      return requestStepReplan(run, replanOutcomes);
    }
    wave.wave.forEach((stepId) => doneIds.push(stepId));
  }
}
