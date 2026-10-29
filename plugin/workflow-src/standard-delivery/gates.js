/*
 * standard-delivery gates.js: the gates of the standard-delivery workflow. It
 * holds the gate ids, names and labels, the tail asks, the validate and
 * fix steps, the gate rerun and the gate loop. Its tail briefs live in
 * briefs.js.
 *
 * Inputs
 *   run    the run state of main.js createRunState. The gates read pass,
 *          head, headRound, trunk and localReview, and update answerLog,
 *          notRunGates and versionAnswer. headRound is the answerLog length
 *          at the last head read (observeHead, record.js).
 *   plan   the accepted plan, from runPlanningPass (plan.js).
 *   facts  the checked facts of the pass, from runPlanWaves (waves.js):
 *          trunk_commit is the base of the version check.
 *   gates  the gate loop state runGates builds: held, notes, runs
 *          (validate, review, fix, headCheck and pr), failures, fixRounds,
 *          reruns, rejected and answer.
 *          failures maps a head to the kept failed validation on it:
 *          {status, failures, versionOnly, versionLine}.
 *   FIX_SCHEMA, VALIDATE_SCHEMA, VALIDATE_COMMANDS_SCHEMA and the limits of
 *   main.js.
 *
 * Outputs
 *   runGates(run, plan, facts)  {result} or {replan}: the pull request step
 *          (pr.js) runs inside the gate loop once every configured gate holds
 *          on the head.
 *   A gate step returns {held} with a note when it held, {answer} when the user
 *   answered a review question, {rerun: true} when the user replied to its
 *   stop, or a run end, {result} or {replan} (isRunEnd).
 *   The steps, as meta.js names them:
 *   Validate a gate, after the last wave. A drone runs validation as its
 *           whole task and edits nothing, and no commit runner follows it: a
 *           dirty path it leaves is refused by the next commit runner or by
 *           the dirty check of hivemind:open-plan-pr. When plan.validation_commands is not empty,
 *           the drone runs each of those commands once, from the inputs block,
 *           and VALIDATE_COMMANDS_SCHEMA offers no not_run. When it is empty,
 *           the drone runs the Validation Procedure of definitions.md, and
 *           VALIDATE_SCHEMA keeps not_run, so an empty list never skips
 *           validation. When plan.versioning.artifact_files is not empty,
 *           the same drone also invokes hivemind:bump-type once with the
 *           version block, the pass's facts trunk_commit as base, the plan's
 *           two versioning answers and the version files, and relays it in
 *           the version field the schema then requires under passed, failed
 *           and not_run. Its stdout parses with versionCheckRoutingSpec()
 *           and passes isConsistentVersionRelay (relay.js). With no version
 *           file the prompt and schema are as before, and no bump-type run
 *           happens.
 *   Fix     a failed validation resolves through decide(). Each taken round is
 *           a drone that fixes the failures and reports its files, which the
 *           commit runner commits; at maxFixRounds() the run asks. A failed
 *           result is kept for the head it ran on, so when a fix round commits
 *           nothing no validate agent runs again on that head: the next
 *           fix-round decision takes the kept failures. Fix labels count
 *           gates.runs.fix, every fix round of the pass.
 *
 * Version check (issue 457), while run.versionAnswer is unset:
 *   match         the gate holds, its note naming the version.
 *   mismatch      a code-built line naming expected_version and the bump
 *                 joins the command failures, and the fix prompt gets the
 *                 version_files block. A version-only failure runs its fix
 *                 round with no decide() call, counted toward
 *                 maxFixRounds(); at the limit it stops through
 *                 stopDelivery, and the reply resets the round count and
 *                 runs the head check, then validation again. Any other
 *                 failure keeps the fix limit ask.
 *   undetermined, unreadable  the run asks version_bump_indeterminable with
 *                 no decide() call (buildVersionQuestionBrief, briefs.js).
 *                 The reply becomes run.versionAnswer and runs one fix round
 *                 with the version_files and user_answer blocks, outside
 *                 decide() and the round limit, and never starts a new pass.
 *   Once run.versionAnswer is set, no later version check of the run fails
 *   or asks, and the gate note says the version is as the user replied. No
 *   version path plans again.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of main.js:
 *   the build bundles this module into it, so a row can name a function of this
 *   module.
 *   A null gate result reads through describeUnusableResult (lib/result.js),
 *   next action run_again, and readGateEditOutcome passes its agentFailure
 *   mark on. The fix step reads its result before the commit and passes its
 *   cause, if any, to runCommitStep (relay.js), which stops with every
 *   cause through stopDelivery with isReplan false, so a commit stop never
 *   hides a step cause; a stop it returns is returned as is. A null fix
 *   result ends the run, and any other fix round stop pauses. A blocked,
 *   malformed or unusable validation or version relay goes through
 *   stopDelivery (record.js) with isReplan false: an agent failure ends the
 *   run, and any other cause pauses. A user_answer fix prompt carries the
 *   reply in a data block and not the resume note.
 *   The head read keys on the reply round (issue 457): the head is unread
 *   exactly when run.headRound is behind run.answerLog.length, whatever
 *   route the reply took. Before validation or the pull request step, an
 *   unread head runs one head check: runCommitStep (relay.js) with an
 *   empty file list and label head-P-N, N counting gates.runs.headCheck,
 *   which clears the kept failures, so validation runs again with the next
 *   count. A run end it returns is returned as is, a refusal of it is a
 *   commit-script refusal and ends the run, and a reply to its own stop
 *   leaves the head unread, so the loop reads again. Local review ends
 *   with its own head read, its commit runner the same empty-list molt
 *   run, so no head check precedes it. A gate holds only on a read head.
 *   A head the check saw move goes through the gate rerun below; else the
 *   same step runs again.
 *   A gate holds only for the commit its step ended on, read from the commit
 *   runner's routing line; validation, which has no commit runner, ends on the
 *   head it ran on. The configured gates run in gateIds() order, local review
 *   only when the launch configures it, and a gate that already holds on the
 *   head is not run again. When a step ends on a commit other than the head the
 *   gates last checked, the run goes back to the first gate: each gate that
 *   held on an earlier commit runs again. Each such going back resolves once
 *   through decide() kind gate_rerun, and after maxGateReruns() of them the run
 *   asks. The pull request step runs only when every configured gate holds on
 *   the head, as the last step of the gate loop, under label pr-P, then
 *   pr-P-N with N counting gates.runs.pr.
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

function buildValidateSchema(hasCommands, hasVersion) {
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
  if (hasVersion) {
    spec.properties.version = Object.assign(buildRelaySchema(), { description: 'The relay of the one hivemind:bump-type run.' });
    Object.keys(spec.variants).forEach((value) => spec.variants[value][value === 'blocked' ? 'optional' : 'required'].push('version'));
  }
  return buildTaggedSchema(spec);
}

function hasVersionFiles(plan) {
  return plan.versioning.artifact_files.length > 0;
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
    return { status: 'blocked', reason: unusable.problem, files: [], nextAction: unusable.nextAction, agentFailure: unusable.agentFailure };
  }
  if (result.outcome === 'blocked') {
    return { status: 'blocked', reason: describeReason(result.blocker), files: result.files, nextAction: result.next_action };
  }
  return { status: 'complete', files: result.files };
}

function versionCheckSentence() {
  return 'The hivemind:bump-type run is part of this validation task: invoke the hivemind:bump-type skill once, with each value of the version block below as the input of the same name, and relay that run in the version field.';
}

function buildValidatePrompt(plan, trunkCommit) {
  const commands = plan.validation_commands;
  const lines = ['Run the project\'s validation on the working branch as it is checked out.', commands.length === 0 ? validationTaskSentence() : validationCommandsSentence(), runnerReadOnlySentence()];
  const blocks = commands.length === 0 ? [] : [formatDataBlock('inputs', { commands: commands })];
  if (hasVersionFiles(plan)) {
    lines.push(versionCheckSentence());
    blocks.push(formatDataBlock('version', Object.assign(buildBumpTypeInputs(trunkCommit, plan.versioning), { version_files: plan.versioning.artifact_files })));
  }
  return (blocks.length === 0 ? lines : lines.concat('', blocks)).join('\n');
}

function selectValidateSchema(plan) {
  const hasCommands = plan.validation_commands.length > 0;
  if (hasVersionFiles(plan)) {
    return buildValidateSchema(hasCommands, true);
  }
  return hasCommands ? VALIDATE_COMMANDS_SCHEMA : VALIDATE_SCHEMA;
}

function readValidateOutcome(result, schema) {
  if (!validateSchema(schema, result).ok) {
    return describeUnusableResult('The validation step returned no usable result, so ' + RUN_NAME + ' stopped before the pull request.', result);
  }
  if (result.outcome === 'blocked') {
    return { problem: 'The validation step was blocked, so ' + RUN_NAME + ' stopped before the pull request: ' + describeReason(result.blocker), nextAction: result.next_action };
  }
  const validation = { status: result.outcome, failures: result.failures };
  if (Object.hasOwn(result, 'version')) {
    validation.versionRelay = result.version;
  }
  return validation;
}

function checkVersionRelay(relay) {
  const stopped = 'so ' + RUN_NAME + ' stopped before the pull request.';
  if (relay.outcome === 'blocked') {
    return { problem: 'The version check of the validation step was blocked, ' + stopped + ' ' + describeRelayBlocker(relay.stderr, true) };
  }
  const values = readRelayedLines(relay, versionCheckRoutingSpec());
  if (values === undefined || !isConsistentVersionRelay(values)) {
    return { problem: 'The version check of the validation step returned malformed routing lines, ' + stopped };
  }
  return { values: values };
}

function describeVersionMismatch(values) {
  const source = values.verdict === 'bump_required' ? 'the trunk version ' + values.trunk_version + ' raised by a ' + values.bump_type + ' bump' : 'the trunk version, since the commits call for no version bump';
  return 'Version check: each file of the version_files block must hold version ' + values.expected_version + ', ' + source + '.';
}

function describeVersionQuestionLine(values) {
  const cause = values.version_check === 'unreadable' ? 'The check cannot read one version from the files of the version_files block.' : 'The commits since the trunk do not settle the version bump.';
  return 'Version check: ' + cause + ' Set each file of the version_files block as the reply in the user_answer block says.';
}

function describeValidateNote(validation, plan, run) {
  const note = validation.status === 'passed' ? 'passed' : 'not run, the project documents no validation commands';
  if (!hasVersionFiles(plan)) {
    return note;
  }
  return run.versionAnswer === undefined ? note + ', version ' + validation.version.expected_version : note + ', version as the user replied';
}

/**
 * Returns the validation with the version check applied: {problem} for an
 * unusable version relay, {question} with the routing values for
 * undetermined or unreadable, else the validation with version set to the
 * values, and on a mismatch status failed, the version line joined to the
 * failures and versionOnly. A kept failure or a set run.versionAnswer skips
 * the check.
 */
function applyVersionCheck(validation, run) {
  if (validation.versionRelay === undefined || run.versionAnswer !== undefined) {
    return validation;
  }
  const checked = checkVersionRelay(validation.versionRelay);
  if (checked.problem !== undefined) {
    return checked;
  }
  const values = checked.values;
  if (values.version_check === 'undetermined' || values.version_check === 'unreadable') {
    return { question: values, status: validation.status, failures: validation.failures };
  }
  if (values.version_check === 'match') {
    return Object.assign(validation, { version: values });
  }
  const versionLine = describeVersionMismatch(values);
  const isFailed = validation.status === 'failed';
  return { status: 'failed', failures: isFailed ? validation.failures + '\n\n' + versionLine : versionLine, versionOnly: !isFailed, versionLine: versionLine };
}

function buildFixPrompt(fix, plan, trunk) {
  const lines = [
    'Fix the failed validation of the delivery: the failures block below holds what the validation reported.',
    validationFixSentence(),
    boundarySentence(),
    fix.userAnswer === undefined ? dataBlocksSentence() : dataBlocksSentence('The reply in user_answer'),
    '',
    formatDataBlock('failures', fix.failures)
  ];
  if (fix.versionLine !== undefined) {
    lines.push(formatDataBlock('version_files', plan.versioning.artifact_files));
  }
  if (fix.userAnswer !== undefined) {
    lines.push(formatDataBlock('user_answer', fix.userAnswer));
  }
  lines.push(formatDataBlock('plan_summary', plan.summary), formatDataBlock('git', { branch: plan.branch, base: plan.base, trunk: trunk }));
  return lines.join('\n');
}

async function runFixRound(run, plan, fix, gates) {
  phase('Fix');
  gates.runs.fix += 1;
  const count = gates.runs.fix;
  const prompt = fix.userAnswer === undefined ? addResumeNote(buildFixPrompt(fix, plan, run.trunk), run) : buildFixPrompt(fix, plan, run.trunk);
  const result = await agent(prompt, droneOptions(gateLabel('fix', run, count), 'Fix', FIX_SCHEMA));
  const edit = readGateEditOutcome(result, FIX_SCHEMA);
  const stepCauses = edit.status === 'blocked' ? [{ problem: 'The validation fix round was blocked, so ' + RUN_NAME + ' stopped: ' + edit.reason, nextAction: edit.nextAction, agentFailure: edit.agentFailure }] : [];
  const committed = await runCommitStep(run, plan, { files: edit.files, label: gateLabel('fix-commit', run, count), stepName: 'fix' }, stepCauses);
  if (committed.values === undefined) {
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

async function runValidateStep(run, plan, facts, gates) {
  phase('Validate');
  const schema = selectValidateSchema(plan);
  const prompt = addResumeNote(buildValidatePrompt(plan, facts.trunk_commit), run);
  const result = await agent(prompt, droneOptions(gateLabel('validate', run, gates.runs.validate), 'Validate', schema));
  const validation = readValidateOutcome(result, schema);
  return validation.problem === undefined ? applyVersionCheck(validation, run) : validation;
}

async function askVersionQuestion(run, plan, gates, validation) {
  const asked = askTail(buildUndecidedAsk(buildVersionQuestionBrief(validation.question)), run, undefined);
  if (asked.answer === undefined) {
    return asked;
  }
  run.versionAnswer = asked.answer;
  const versionLine = describeVersionQuestionLine(validation.question);
  const failures = validation.status === 'failed' ? validation.failures + '\n\n' + versionLine : versionLine;
  return runFixRound(run, plan, { failures: failures, versionLine: versionLine, userAnswer: asked.answer }, gates);
}

function stopVersionFixLimit(run, gates, kept) {
  const cause = { problem: 'Validation still fails its version check on commit ' + run.head + ' after ' + maxFixRounds() + ' fix rounds, so ' + RUN_NAME + ' stopped before the pull request. ' + kept.versionLine };
  const stopped = stopDelivery([cause], run, [], false);
  if (stopped.rerun === true) {
    gates.fixRounds = 0;
  }
  return stopped;
}

async function runValidateGate(run, plan, facts, gates) {
  const validation = hasKeptFailure(run, gates) ? gates.failures[run.head] : await runValidateStep(run, plan, facts, gates);
  if (validation.problem !== undefined) {
    return stopDelivery([validation], run, [], false);
  }
  if (validation.question !== undefined) {
    return askVersionQuestion(run, plan, gates, validation);
  }
  if (validation.status === 'not_run') {
    listNotRunGate(run, 'validation: the project documents no validation commands.');
  }
  if (validation.status !== 'failed') {
    return { held: true, note: describeValidateNote(validation, plan, run) };
  }
  gates.failures[run.head] = validation;
  if (gates.fixRounds >= maxFixRounds()) {
    return validation.versionOnly === true ? stopVersionFixLimit(run, gates, validation) : replanFromTailAsk(buildUndecidedAsk(buildFixLimitBrief(run.head)), run);
  }
  if (validation.versionOnly !== true) {
    const decided = resolveTailDecision(VALIDATION_REMEDIATION_KIND, buildValidationRemediationBrief(run.head, gates.fixRounds + 1), run);
    if (isRunEnd(decided)) {
      return decided;
    }
  }
  gates.fixRounds += 1;
  return runFixRound(run, plan, validation, gates);
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

function runGateStep(stepId, run, plan, facts, gates) {
  if (stepId === 'pr') {
    return runPullRequestStep(run, plan, gates);
  }
  if (stepId === 'review') {
    return runReviewGate(run, plan, gates);
  }
  return runValidateGate(run, plan, facts, gates);
}

async function runHeadCheck(run, plan, gates) {
  gates.runs.headCheck += 1;
  gates.failures = {};
  return runCommitStep(run, plan, { files: [], label: gateLabel('head', run, gates.runs.headCheck), stepName: 'head' }, []);
}

async function runGates(run, plan, facts) {
  const gateList = configuredGateIds(run);
  const gates = { held: {}, notes: {}, runs: { validate: 0, review: 0, fix: 0, headCheck: 0, pr: 0 }, failures: {}, fixRounds: 0, reruns: 0, rejected: [], answer: undefined };
  if (!run.localReview) {
    listNotRunGate(run, notConfiguredReviewLine());
  }
  let checkedHead = run.head;
  let index = 0;
  for (;;) {
    if (run.head !== checkedHead) {
      checkedHead = run.head;
      const rerun = resolveGateRerun(run, gates);
      if (isRunEnd(rerun)) {
        return rerun;
      }
      index = 0;
    }
    const stepId = index < gateList.length ? gateList[index] : 'pr';
    if (stepId !== 'pr' && gates.held[stepId] === run.head) {
      index += 1;
      continue;
    }
    if (stepId !== 'review' && run.headRound !== run.answerLog.length) {
      const checked = await runHeadCheck(run, plan, gates);
      if (isRunEnd(checked)) {
        return checked;
      }
      continue;
    }
    if (stepId !== 'validate' || !hasKeptFailure(run, gates)) {
      gates.runs[stepId] += 1;
    }
    const ended = await runGateStep(stepId, run, plan, facts, gates);
    if (isRunEnd(ended)) {
      return ended;
    }
    if (ended.held && run.headRound === run.answerLog.length) {
      gates.held[stepId] = run.head;
      gates.notes[stepId] = ended.note;
    }
    if (ended.answer !== undefined) {
      gates.answer = ended.answer;
    }
  }
}
