/*
 * commit.js: the commit runner step a workflow shares, its subject and
 * blocker texts and the inputs file paths of every runner step.
 *
 * Inputs
 *   run    the run state of the workflow's main.js. The step reads trunk,
 *          answerLog, head, factsStem and pluginRoot, and runCommitStep
 *          passes its checked commit to observeHead (lib/record.js), which
 *          writes head.
 *   plan   the accepted plan, from runPlanningPass (lib/plan.js).
 *   relay  each runner result: {outcome, stdout, stderr} under
 *          RELAY_SCHEMA, its stdout read with lib/routing.js.
 *   The constants of the workflow's main.js this file reads: RUN_NAME and
 *   RELAY_SCHEMA. Every workflow whose code calls a function of this file
 *   declares them. It reads no workflow function: the relay helpers are
 *   lib/runner.js, the routing spec lib/specs.js, the stop and head
 *   functions lib/record.js and the prompt blocks lib/facts.js.
 *
 * Outputs
 *   runCommitStep(run, plan, commit, stepCauses)  commit is {files,
 *           label, stepName, subject?}, subject commitStepTexts(stepName)
 *           .subject when not given; stepCauses is the array of the step's
 *           own causes, or it throws. {values} when the commit held and
 *           stepCauses is empty, else what stopDelivery (lib/record.js)
 *           returns over stepCauses, then the commit cause when the commit
 *           failed, or else the describeCommitEnd end line when it
 *           committed: {result}, {replan} for a wave, or {rerun: true} for
 *           a gate step or the head check.
 *   buildInputsPath(run, kind, label)  .hivemind/<kind>-inputs-<stem>-<label>
 *           .json, stem run.factsStem, unique per run given a faithful facts
 *           relay (ADR-0037), else undefined: a --inputs command stop. The PR
 *           step also builds its --body-file path with it (standard-delivery
 *           pr.js).
 *   describeCommitEnd(commitValues, stepName)  one sentence: the commit
 *           the step's files went into.
 *   toCommitSubject(text, fallbackSubject)  text made one line and cut by
 *           cutAtBoundary (lib/result.js) to maxSubjectLength() code points,
 *           or fallbackSubject when that line is blank, holds a breaking
 *           change marker or an attribution string molt SKILL.md forbids.
 *   quoteOrEmpty(text, limit)  quoteDiagnostic (lib/result.js) of text, or
 *           the encoded empty string when that is empty.
 *   The step: a runner runs the molt command after every wave and every
 *   gate step that can change files, and with an empty file list as the
 *   head check after a reply. Its checked commit goes to observeHead
 *   (lib/record.js), as the branch commit does at each pass start. Its
 *   inputs_file block carries a code-built subject: a wave's from its plan
 *   steps, and fixed ones for the fix and review commits.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this library into it, so a row can name a
 *   function of this library.
 *   Every step that can change files ends with the commit runner, whatever
 *   the workers returned (ADR-0037 invariant 1, decision 12). Workers never
 *   commit.
 *   A file-changing step reads its own result before its commit and passes
 *   its causes to runCommitStep, which stops through stopDelivery, isReplan
 *   true for a wave: a failed commit adds its cause after them, so a commit
 *   stop never hides the step's cause. A commit script refusal, a branch
 *   other than the plan branch and a runner command value outside its class
 *   (describeCommandStop) are terminal.
 *   The commit runner calls agent() through runRunnerRelay (lib/runner.js),
 *   and its prompt follows its runner prompt and relayed reply rules, with
 *   an inputs_file block.
 *   The commit runner writes its own inputs file and passes its path to
 *   molt.sh (review finding fb4c129c), the path buildInputsPath builds
 *   (issue 487), unique per call and run given a faithful facts relay. What
 *   reaches git rests on the runner copying its inputs_file block (ADR-0037
 *   Risks). molt.sh refuses an inputs file outside the checkout, one that
 *   breaks a field rule and any dirty path outside its list, and the
 *   workflow checks every routing line.
 *
 * Why
 *   Every workflow that changes files ends each file-changing step with the
 *   same commit, so the commit step lives in one place.
 */

function buildInputsPath(run, kind, label) {
  return typeof run.factsStem === 'string' ? '.hivemind/' + kind + '-inputs-' + run.factsStem + '-' + label + '.json' : undefined;
}

function commitStepTexts(stepName) {
  switch (stepName) {
    case 'wave':
      return { purpose: 'the wave of plan steps that just ran', noun: 'the wave' };
    case 'fix':
      return { purpose: 'the validation fix round that just ran', noun: 'the fix round', subject: 'fix the failed validation' };
    case 'review':
      return { purpose: 'the local review that just ran, with an empty file list', noun: 'the local review', subject: 'apply the local review fixes' };
    case 'head':
      return { purpose: 'nothing: the empty file list makes it report the head of the working branch after the user replied to a stop', noun: 'the head check', subject: 'read the branch head' };
    default:
      throw new Error('commitStepTexts: no texts for step ' + JSON.stringify(stepName));
  }
}

function maxSubjectLength() {
  return 72;
}

function forbiddenSubjectTexts() {
  return ['co-authored-by:', 'authored-by:', 'generated with', 'created with claude', '\u{1f916} generated'];
}

function isUsableSubject(subject) {
  const lowered = subject.toLowerCase();
  return subject !== ''
    && !subject.includes('!:')
    && !/breaking[ -]change/i.test(subject)
    && !forbiddenSubjectTexts().some((forbidden) => lowered.includes(forbidden));
}

function toCommitSubject(text, fallbackSubject) {
  const oneLine = text.replace(/[\s\x00-\x1f\x7f-\x9f]+/g, ' ').trim();
  const subject = cutAtBoundary(oneLine, maxSubjectLength());
  return isUsableSubject(subject) ? subject : fallbackSubject;
}

function listCommitWords(trunk, inputsPath) {
  return ['--trunk', trunk, '--inputs', inputsPath];
}

function buildCommitPrompt(files, plan, trunk, inputsPath, stepName, subject, pluginRoot) {
  const content = { type: commitTypeMap()[plan.classification], breaking: plan.breaking, subject: subject, files: files };
  return ['Run the command below to commit ' + commitStepTexts(stepName).purpose + '.', dataBlocksSentence(), '', formatCommandBlock(buildRunnerCommand('molt', listCommitWords(trunk, inputsPath), pluginRoot)), formatInputsFileBlock(inputsPath, content)].join('\n');
}

function readOutsidePath(payload) {
  try {
    const parsed = JSON.parse(payload);
    return typeof parsed === 'string' ? parsed : payload;
  } catch (parseError) {
    return payload;
  }
}

function quoteOrEmpty(text, limit) {
  return quoteDiagnostic(text, limit) || encodeUntrustedText('');
}

function describeCommitBlocker(stderr, stepNoun) {
  const lead = 'The commit step was blocked, so ' + RUN_NAME + ' stopped: ' + describeRelayBlocker(stderr, false);
  const outsideLines = splitStderrLines(stderr).filter((line) => line.startsWith('outside: '));
  if (outsideLines.length === 0) {
    return lead;
  }
  const pathLines = outsideLines.map((line) => '- ' + quoteOrEmpty(readOutsidePath(line.slice('outside: '.length))));
  return [lead + ' Dirty paths outside the files of ' + stepNoun + ':', ...capItemLines(pathLines)].join('\n');
}

function checkCommitRelay(relay, plan, stepName) {
  const stepNoun = commitStepTexts(stepName).noun;
  const stopped = 'so ' + RUN_NAME + ' stopped. Check the branch for a commit of ' + stepNoun + '.';
  if (!validateSchema(RELAY_SCHEMA, relay).ok) {
    return describeUnusableRelay(relay, 'commit', stopped);
  }
  if (relay.outcome === 'blocked') {
    return { problem: describeCommitBlocker(relay.stderr, stepNoun), terminal: true, nextAction: readRelayAction(relay.stderr) };
  }
  const values = readRelayedLines(relay, moltRoutingSpec());
  if (values === undefined) {
    return describeUnusableRelay(relay, 'commit', stopped, true);
  }
  if (values.branch !== plan.branch) {
    return { problem: 'The commit step reported a branch other than the plan branch, ' + stopped, terminal: true };
  }
  return { values: values };
}

function describeCommitEnd(commitValues, stepName) {
  const noun = commitStepTexts(stepName).noun;
  return noun.charAt(0).toUpperCase() + noun.slice(1) + ' was committed as ' + commitValues.commit + ', so that commit can hold partial edits.';
}

async function runCommitStep(run, plan, commit, stepCauses) {
  if (!Array.isArray(stepCauses)) {
    throw new Error('runCommitStep: stepCauses must be an array');
  }
  const subject = commit.subject ?? commitStepTexts(commit.stepName).subject;
  const isReplan = commit.stepName === 'wave';
  phase('Commit');
  const listWords = (label) => listCommitWords(run.trunk, buildInputsPath(run, 'molt', label));
  const commandStop = describeCommandStop('commit', listWords(commit.label), listWords(commit.label + '-retry'));
  if (commandStop !== undefined) {
    return stopDelivery(stepCauses.concat([commandStop]), run, [], isReplan);
  }
  const relay = await runRunnerRelay((label) => addResumeNote(buildCommitPrompt(commit.files, plan, run.trunk, listWords(label)[3], commit.stepName, subject, run.pluginRoot), run), commit.label, 'Commit');
  const checked = checkCommitRelay(relay, plan, commit.stepName);
  if (checked.problem !== undefined) {
    return stopDelivery(stepCauses.concat([checked]), run, [], isReplan);
  }
  observeHead(run, checked.values.commit, plan.branch);
  if (stepCauses.length === 0) {
    return { values: checked.values };
  }
  const endLines = checked.values.committed === 'true' ? [describeCommitEnd(checked.values, commit.stepName)] : [];
  return stopDelivery(stepCauses, run, endLines, isReplan);
}
