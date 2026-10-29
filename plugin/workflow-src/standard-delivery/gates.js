/*
 * standard-delivery gates.js: the gates of the standard-delivery workflow. It
 * holds the gate ids, names and labels, the tail asks, the validate and
 * fix steps, the gate rerun and the gate loop. Its tail briefs live in
 * briefs.js.
 *
 * Inputs
 *   run    the run state of main.js createRunState. The gates read pass,
 *          head, trunk and localReview, and update answerLog and notRunGates.
 *   plan   the accepted plan, from runPlanningPass (plan.js).
 *   facts  the checked facts of the pass, from runPlanWaves (waves.js).
 *   gates  the gate loop state runGates builds: held, notes, runs, failures,
 *          fixRounds, reruns, rejected and answer. failures maps a head to
 *          the failures validation reported on it.
 *   FIX_SCHEMA, VALIDATE_SCHEMA, VALIDATE_COMMANDS_SCHEMA and the limits of
 *   main.js.
 *
 * Outputs
 *   runGates(run, plan, facts)  what runPullRequestStep (pr.js) returns once
 *          every configured gate holds on the head, else {result} or {replan}.
 *   A gate step returns {held} with a note when it held, {answer} when the user
 *   answered a review question, or a run end, {result} or {replan} (isRunEnd).
 *   The steps, as meta.js names them:
 *   Validate a gate, after the last wave. A drone runs validation as its
 *           whole task and edits nothing, and no commit runner follows it: a
 *           dirty path it leaves is refused by the next commit runner or by
 *           the dirty check of hivemind:open-plan-pr. When plan.validation_commands is not empty,
 *           the drone runs each of those commands once, from the inputs block,
 *           and VALIDATE_COMMANDS_SCHEMA offers no not_run. When it is empty,
 *           the drone runs the Validation Procedure of definitions.md, and
 *           VALIDATE_SCHEMA keeps not_run, so an empty list never skips
 *           validation.
 *   Fix     a failed validation resolves through decide(). Each taken round is
 *           a drone that fixes the failures and reports its files, which the
 *           commit runner commits; at maxFixRounds() the run asks. A failed
 *           result is kept for the head it ran on, so when a fix round commits
 *           nothing no validate agent runs again on that head: the next
 *           fix-round decision takes the kept failures.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of main.js:
 *   the build bundles this module into it, so a row can name a function of this
 *   module.
 *   A null gate result reads through describeUnusableResult (lib/result.js),
 *   next action run_again. The fix step reads its result before the commit
 *   and passes its cause, if any, to runCommitStep (relay.js), which ends
 *   the run with every cause, so a commit stop never hides a step cause;
 *   a run end it returns is returned as is. Every other blocked end passes
 *   its causes to finishDeliveryBlocked (record.js).
 *   A gate holds only for the commit its step ended on, read from the commit
 *   runner's routing line; validation, which has no commit runner, ends on the
 *   head it ran on. The configured gates run in gateIds() order, local review
 *   only when the launch configures it, and a gate that already holds on the
 *   head is not run again. When a step ends on a commit other than the head the
 *   gates last checked, the run goes back to the first gate: each gate that
 *   held on an earlier commit runs again. Each such going back resolves once
 *   through decide() kind gate_rerun, and after maxGateReruns() of them the run
 *   asks. The pull request step runs only when every configured gate holds on
 *   the head.
 *   Tail asks: a question after the last wave pauses through pauseDelivery
 *   with a lead and its question: askTail(ask, run, lead) leads with the
 *   given lead string, as a local review question passes, else with
 *   describeTailLead(run), every plan step committed on the encoded branch
 *   at the head. Tail rounds share run.answerLog and the answers round
 *   numbering with planning rounds, so a resume replays every earlier agent
 *   from cache and takes the reply at the ask. At reply time askTail adds
 *   the {question, settled, reply} entry buildAnswerEntry (lib/brief.js)
 *   builds to run.answerLog, the question being that lead and the question,
 *   so every later plan prompt shows it in the answers block; it returns
 *   {question, reply} as the answer. No revise reads a tail reply, so its
 *   settled is always [] and it stays the user's own words in every later
 *   answers block, review questions included: a review decision lives in the
 *   reviewer's record. A reply to a local review question reruns the review
 *   gate on the current head, after any stale gate, with the next gateLabel
 *   count and user_answer {question, reply}. Any other tail reply starts a
 *   new pass from the facts step with the answers block, outside
 *   maxReplans(). Nothing is pushed before every configured gate holds on
 *   one commit.
 *
 * Why
 *   A gate holds only on a commit, so one loop decides which gate runs next
 *   from the head each step ends on.
 */

function gateIds() {
  return ['validate', 'review'];
}

function configuredGateIds(run) {
  return run.localReview ? gateIds() : gateIds().filter((gateId) => gateId !== 'review');
}

function gateNames() {
  return { validate: 'validation', review: 'local review' };
}

function joinNames(names, conjunction) {
  if (names.length < 3) {
    return names.join(' ' + conjunction + ' ');
  }
  return names.slice(0, -1).join(', ') + ' ' + conjunction + ' ' + names[names.length - 1];
}

function gateLabel(stepName, run, count) {
  return stepName + '-' + run.pass + '-' + count;
}

function buildGateEditSchema() {
  return buildTaggedSchema({
    tag: 'outcome',
    properties: {
      outcome: { type: 'string', enum: ['complete', 'blocked'], description: 'complete when the task is done. blocked when it cannot be done.' },
      blocker: { type: 'string', maxLength: 400, description: 'Why the task cannot be done, in one or two short sentences written for the user.' },
      next_action: buildNextActionProperty(),
      files: { type: 'array', description: 'Every path you created, edited or deleted, relative to the top of the repository.', items: { type: 'string' } }
    },
    required: ['outcome', 'files'],
    variants: { complete: { required: [], optional: [] }, blocked: { required: [], optional: ['blocker', 'next_action'] } }
  });
}

function buildValidateSchema(hasCommands) {
  const spec = {
    tag: 'outcome',
    properties: {
      outcome: {
        type: 'string',
        enum: ['passed', 'failed', 'blocked'],
        description: 'passed when every command passes. failed when any fails. blocked when a command cannot run.'
      },
      failures: { type: 'string', description: 'What failed: each failing command with its failure output.' },
      blocker: { type: 'string', maxLength: 400, description: 'The command that cannot run and why, in one or two short sentences written for the user.' },
      next_action: buildNextActionProperty()
    },
    required: ['outcome'],
    variants: {
      passed: { required: [], optional: [] },
      failed: { required: ['failures'], optional: [] },
      blocked: { required: [], optional: ['blocker', 'next_action'] }
    }
  };
  if (!hasCommands) {
    spec.properties.outcome.enum = ['passed', 'failed', 'not_run', 'blocked'];
    spec.properties.outcome.description = 'passed when every validation command passes. failed when any fails. not_run when the project documents no validation commands. blocked when a command cannot run.';
    spec.variants.not_run = { required: [], optional: [] };
  }
  return buildTaggedSchema(spec);
}

function isRunEnd(outcome) {
  return outcome.result !== undefined || outcome.replan !== undefined;
}

function describeTailLead(run) {
  return 'Every plan step is committed on branch ' + encodeUntrustedText(run.branch) + ', with head ' + run.head + '.';
}

function askTail(ask, run, lead) {
  const leadText = lead === undefined ? describeTailLead(run) : lead;
  const reply = takeNextReply(run, run.answerLog.length + 1);
  if (reply === undefined) {
    return { result: pauseDelivery({ asks: [ask], taken: [] }, run, leadText) };
  }
  const question = leadText + '\n\n' + renderQuestions([ask]);
  run.answerLog.push(buildAnswerEntry({ question: question, labels: [], reply: reply }, undefined));
  return { answer: { question: question, reply: reply } };
}

function replanFromTailAsk(ask, run) {
  const asked = askTail(ask, run, undefined);
  if (asked.answer === undefined) {
    return asked;
  }
  return { replan: { reason: 'The user replied to a question the run asked after the last wave, so plan again from the fresh facts with the answers block.' } };
}

function buildUndecidedAsk(brief) {
  return { brief: brief, reason: 'no_recommendation' };
}

function resolveTailDecision(kind, brief, run) {
  const resolution = { asks: [], taken: [], reversibleEffects: [] };
  if (resolveDecision(kind, brief, undefined, run, resolution) === 'take') {
    acceptResolution(resolution, run);
    return {};
  }
  return replanFromTailAsk(resolution.asks[0], run);
}

function buildBumpTypeInputs(trunkCommit, versioning) {
  return { base: trunkCommit, bump_trigger: versioning.bump_trigger, no_bump_match: versioning.no_bump_match };
}

function readGateEditOutcome(result, schema) {
  if (!validateSchema(schema, result).ok) {
    const unusable = describeUnusableResult('it returned no usable result.', result);
    return { status: 'blocked', reason: unusable.problem, files: [], nextAction: unusable.nextAction };
  }
  if (result.outcome === 'blocked') {
    return { status: 'blocked', reason: describeReason(result.blocker), files: result.files, nextAction: result.next_action };
  }
  return { status: 'complete', files: result.files };
}

function buildValidatePrompt(commands) {
  const taskLine = 'Run the project\'s validation on the working branch as it is checked out.';
  if (commands.length === 0) {
    return [taskLine, validationTaskSentence(), runnerReadOnlySentence()].join('\n');
  }
  return [
    taskLine,
    validationCommandsSentence(),
    runnerReadOnlySentence(),
    '',
    formatDataBlock('inputs', { commands: commands })
  ].join('\n');
}

function selectValidateSchema(plan) {
  return plan.validation_commands.length > 0 ? VALIDATE_COMMANDS_SCHEMA : VALIDATE_SCHEMA;
}

function readValidateOutcome(result, schema) {
  if (!validateSchema(schema, result).ok) {
    return describeUnusableResult('The validation step returned no usable result, so ' + RUN_NAME + ' stopped before the pull request.', result);
  }
  if (result.outcome === 'blocked') {
    return { problem: 'The validation step was blocked, so ' + RUN_NAME + ' stopped before the pull request: ' + describeReason(result.blocker), nextAction: result.next_action };
  }
  return { status: result.outcome, failures: result.failures };
}

function buildFixPrompt(failures, plan, trunk) {
  return [
    'Fix the failed validation of the delivery: the failures block below holds what the validation reported.',
    validationFixSentence(),
    boundarySentence(),
    dataBlocksSentence(),
    '',
    formatDataBlock('failures', failures),
    formatDataBlock('plan_summary', plan.summary),
    formatDataBlock('git', { branch: plan.branch, base: plan.base, trunk: trunk })
  ].join('\n');
}

async function runFixRound(run, plan, failures, round) {
  phase('Fix');
  const result = await agent(addResumeNote(buildFixPrompt(failures, plan, run.trunk), run), droneOptions(gateLabel('fix', run, round), 'Fix', FIX_SCHEMA));
  const fix = readGateEditOutcome(result, FIX_SCHEMA);
  const stepCauses = fix.status === 'blocked' ? [{ problem: 'The validation fix round was blocked, so ' + RUN_NAME + ' stopped: ' + fix.reason, nextAction: fix.nextAction }] : [];
  const committed = await runCommitStep(run, plan, { files: fix.files, label: gateLabel('fix-commit', run, round), stepName: 'fix' }, stepCauses);
  if (committed.result !== undefined) {
    return committed;
  }
  return { held: false };
}

function listNotRunGate(run, line) {
  if (!run.notRunGates.includes(line)) {
    run.notRunGates.push(line);
  }
}

function hasKeptFailure(run, gates) {
  return Object.hasOwn(gates.failures, run.head);
}

async function runValidateStep(run, plan, gates) {
  phase('Validate');
  const schema = selectValidateSchema(plan);
  const prompt = addResumeNote(buildValidatePrompt(plan.validation_commands), run);
  const result = await agent(prompt, droneOptions(gateLabel('validate', run, gates.runs.validate), 'Validate', schema));
  return readValidateOutcome(result, schema);
}

async function runValidateGate(run, plan, gates) {
  const validation = hasKeptFailure(run, gates) ? { status: 'failed', failures: gates.failures[run.head] } : await runValidateStep(run, plan, gates);
  if (validation.problem !== undefined) {
    return { result: finishDeliveryBlocked([validation], run) };
  }
  if (validation.status === 'not_run') {
    listNotRunGate(run, 'validation: the project documents no validation commands.');
  }
  if (validation.status !== 'failed') {
    return { held: true, note: validation.status === 'passed' ? 'passed' : 'not run, the project documents no validation commands' };
  }
  gates.failures[run.head] = validation.failures;
  if (gates.fixRounds >= maxFixRounds()) {
    return replanFromTailAsk(buildUndecidedAsk(buildFixLimitBrief(run.head)), run);
  }
  const decided = resolveTailDecision(VALIDATION_REMEDIATION_KIND, buildValidationRemediationBrief(run.head, gates.fixRounds + 1), run);
  if (isRunEnd(decided)) {
    return decided;
  }
  gates.fixRounds += 1;
  return runFixRound(run, plan, validation.failures, gates.fixRounds);
}

function resolveGateRerun(run, gates) {
  const staleIds = configuredGateIds(run).filter((gateId) => gates.held[gateId] !== undefined && gates.held[gateId] !== run.head);
  if (staleIds.length === 0) {
    return {};
  }
  if (gates.reruns >= maxGateReruns()) {
    return replanFromTailAsk(buildUndecidedAsk(buildGateRerunBrief(staleIds, run.head, true)), run);
  }
  gates.reruns += 1;
  return resolveTailDecision(GATE_RERUN_KIND, buildGateRerunBrief(staleIds, run.head, false), run);
}

function runGateStep(gateId, run, plan, gates) {
  if (gateId === 'review') {
    return runReviewGate(run, plan, gates);
  }
  return runValidateGate(run, plan, gates);
}

async function runGates(run, plan, facts) {
  const gateList = configuredGateIds(run);
  const gates = { held: {}, notes: {}, runs: { validate: 0, review: 0 }, failures: {}, fixRounds: 0, reruns: 0, rejected: [], answer: undefined };
  if (!run.localReview) {
    listNotRunGate(run, notConfiguredReviewLine());
  }
  let checkedHead = run.head;
  let index = 0;
  while (index < gateList.length) {
    const gateId = gateList[index];
    if (gates.held[gateId] === run.head) {
      index += 1;
      continue;
    }
    if (gateId !== 'validate' || !hasKeptFailure(run, gates)) {
      gates.runs[gateId] += 1;
    }
    const ended = await runGateStep(gateId, run, plan, gates);
    if (isRunEnd(ended)) {
      return ended;
    }
    if (ended.held) {
      gates.held[gateId] = run.head;
      gates.notes[gateId] = ended.note;
    }
    if (ended.answer !== undefined) {
      gates.answer = ended.answer;
    }
    if (run.head === checkedHead) {
      continue;
    }
    checkedHead = run.head;
    const rerun = resolveGateRerun(run, gates);
    if (isRunEnd(rerun)) {
      return rerun;
    }
    index = 0;
  }
  return runPullRequestStep(run, plan, gates);
}
