/*
 * standard-delivery relay.js: the branch and commit runner steps of the
 * standard-delivery workflow, the validation prompt sentences and the
 * inputs file paths. The runner options, relay helpers and the facts step
 * live in lib/runner.js; the routing specs live in specs.js.
 *
 * Inputs
 *   run    the run state of main.js createRunState. The steps read trunk,
 *          answerLog, head, factsStem and pluginRoot, and runCommitStep
 *          passes its checked commit to observeHead (record.js), which
 *          writes head.
 *   plan   the accepted plan, from runPlanningPass (plan.js).
 *   relay  each runner result: {outcome, stdout, stderr} under
 *          RELAY_SCHEMA, its stdout read with lib/routing.js.
 *   RUN_NAME and RELAY_SCHEMA from main.js.
 *
 * Outputs
 *   runBranchStep(run, plan, freshness)  {values}, else a cause, terminal
 *           for a command stop, a blocked relay and another branch.
 *   runCommitStep(run, plan, commit, stepCauses)  commit is {files,
 *           label, stepName, subject?}, subject commitStepTexts(stepName)
 *           .subject when not given; stepCauses is the array of the step's
 *           own causes, or it throws. {values} when the commit held and
 *           stepCauses is empty, else what stopDelivery (record.js) returns
 *           over stepCauses, then the commit cause when the commit failed,
 *           or else the describeCommitEnd end line when it committed:
 *           {result}, {replan} for a wave, or {rerun: true} for a gate step
 *           or the head check.
 *   buildInputsPath(run, kind, label)  .hivemind/<kind>-inputs-<stem>-<label>
 *           .json, stem run.factsStem, unique per run given a faithful facts
 *           relay (ADR-0037), else undefined: a --inputs command stop. The PR
 *           step also builds its --body-file path with it (pr.js).
 *   describeCommitEnd(commitValues, stepName)  one sentence: the commit
 *           the step's files went into.
 *   toCommitSubject(text, fallbackSubject)  text made one line and cut by
 *           cutAtBoundary (lib/result.js) to maxSubjectLength() code points,
 *           or fallbackSubject when that line is blank, holds a breaking
 *           change marker or an attribution string molt SKILL.md forbids.
 *   slowCaseSentence()  the validate prompt's line for the slow case rule
 *           of the Validation Procedure (gates.js), with the other
 *           validation sentences. The steps, as meta.js names them:
 *   Branch  a runner runs the create-working-branch command.
 *   Commit  a runner runs the molt command after every wave and every gate
 *           step that can change files, and with an empty file list as the
 *           head check of gates.js after a reply. Its checked commit goes to
 *           observeHead (record.js), as the branch commit does at each pass
 *           start (main.js). Its inputs_file block carries a code-built
 *           subject: a wave's from its plan steps (waves.js buildWaveSubject),
 *           and fixed ones for the fix and review commits.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Every step that can change files ends with the commit runner, whatever
 *   the workers returned (ADR-0037 invariant 1, decision 12). Workers never
 *   commit, and validation edits nothing (gates.js).
 *   A file-changing step reads its own result before its commit and passes
 *   its causes to runCommitStep, which stops through stopDelivery, isReplan
 *   true for a wave: a failed commit adds its cause after them, so a commit
 *   stop never hides the step's cause. Only a commit or branch script
 *   refusal, a branch other than the plan branch, a scan injection suspect,
 *   a runner command value outside its class (describeCommandStop) and a
 *   second branch switch (requestBranchReplan) are terminal. stopDelivery
 *   (record.js) ends the run blocked for a terminal cause, an agent failure
 *   and a report or run_again lead; only an approve or fix_cause lead asks
 *   (issue 457).
 *   The branch and commit runners call agent() through runRunnerRelay
 *   (lib/runner.js), and their prompts follow its runner prompt and
 *   relayed reply rules; the commit and PR prompts add an inputs_file
 *   block and the PR prompt a body_file block.
 *   The commit and PR runners write their own inputs file and pass its path to
 *   molt.sh or open-plan-pr.sh (review finding fb4c129c), the path
 *   buildInputsPath builds (issue 487), unique per call and run given a faithful
 *   facts relay. The PR runner also writes its body file, at the path
 *   buildInputsPath builds for its label and -body, and passes it as
 *   --body-file. What reaches git and GitHub rests on the runner copying its
 *   inputs_file and body_file blocks (ADR-0037 Risks). Each script refuses an
 *   inputs or body file outside the checkout or one that breaks a field rule,
 *   molt.sh refuses any dirty path outside its list, and the workflow checks
 *   every routing line.
 *
 * Why
 *   The branch and commit steps are standard-delivery's alone; the relay
 *   helpers they share with every runner step live in lib/runner.js.
 */

function validationTaskSentence() {
  return 'This is a validation task: the Validation Procedure of ${CLAUDE_PLUGIN_ROOT}/governance/definitions.md is its whole task, not a Worker Self-Check.';
}

function validationCommandsSentence() {
  return 'This is a validation task: running each command of the inputs block once, in order and in the foreground, is its whole task, not a Worker Self-Check.';
}

function slowCaseSentence() {
  return 'A test case that hits its own time limit, in a file the branch does not change from the base in the git block, runs once more alone: if it passes, it counts as passed and goes in slow.';
}

function validationFixSentence() {
  return 'This is a validation fix task: the task is one fix round for the run\'s failed validation.';
}

function buildInputsPath(run, kind, label) {
  return typeof run.factsStem === 'string' ? '.hivemind/' + kind + '-inputs-' + run.factsStem + '-' + label + '.json' : undefined;
}

function listBranchWords(plan, freshness, trunk) {
  return ['--base', plan.base, '--branch', plan.branch, '--classification', plan.classification, '--trunk-freshness', freshness, '--trunk', trunk];
}

function buildBranchPrompt(words, pluginRoot) {
  return ['Create or confirm the working branch with the command below.', dataBlocksSentence(), '', formatCommandBlock(buildRunnerCommand('create-working-branch', words, pluginRoot))].join('\n');
}

function checkBranchRelay(relay, plan, freshness) {
  const stopped = 'so ' + RUN_NAME + ' stopped before any wave.';
  if (!validateSchema(RELAY_SCHEMA, relay).ok) {
    return describeUnusableRelay(relay, 'branch', stopped);
  }
  if (relay.outcome === 'blocked') {
    return { problem: 'The branch step was blocked, ' + stopped + ' ' + describeRelayBlocker(relay.stderr, true), terminal: true, nextAction: readRelayAction(relay.stderr) };
  }
  const values = readRelayedLines(relay, createWorkingBranchRoutingSpec());
  if (values === undefined || values.warning !== branchWarningTexts()[freshness]) {
    return describeUnusableRelay(relay, 'branch', stopped, true);
  }
  if (values.branch !== plan.branch) {
    return { problem: 'The branch step reported a branch other than the plan branch, ' + stopped, terminal: true };
  }
  return { values: values };
}

async function runBranchStep(run, plan, freshness) {
  phase('Branch');
  const words = listBranchWords(plan, freshness, run.trunk);
  const commandStop = describeCommandStop('branch', words);
  if (commandStop !== undefined) {
    return commandStop;
  }
  const relay = await runRunnerRelay(() => addResumeNote(buildBranchPrompt(words, run.pluginRoot), run), 'branch-' + run.pass, 'Branch');
  return checkBranchRelay(relay, plan, freshness);
}

function needsBranchReplan(branchValues, facts, plan) {
  const isOnPlanBranch = facts.head_state === 'branch' && facts.branch === plan.branch;
  return (branchValues.created === 'false' && !isOnPlanBranch) || branchValues.commit !== facts.head;
}

function requestBranchReplan(run) {
  if (run.branchSwitches > 0) {
    return stopDelivery([{ problem: 'The branch step switched branch or commit again after a replan, so ' + RUN_NAME + ' stopped before any wave.', terminal: true }], run, [], true);
  }
  run.branchSwitches += 1;
  return { replan: { reason: 'The branch step switched onto a branch or commit other than the one the facts were taken on, so plan again from the new facts.' } };
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
