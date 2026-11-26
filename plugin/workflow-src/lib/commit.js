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
 *   The constants of the workflow's main.js this file reads: RUN_NAME,
 *   RELAY_SCHEMA and RECORD_WRITES. Every workflow whose code calls a
 *   function of this file declares them. It reads no workflow function:
 *   the relay helpers are lib/runner.js, the routing spec lib/specs.js,
 *   the stop and head functions lib/record.js and the prompt blocks
 *   lib/facts.js.
 *
 * Outputs
 *   runCommitStep(run, plan, commit, stepCauses)  commit is {files,
 *           label, stepName?, subject?, texts?}, texts {purpose, noun,
 *           subject} the caller's own step texts, commitStepTexts(stepName)
 *           of wave, fix or head when not given, and subject texts.subject
 *           when not given; stepCauses is the array of the step's
 *           own causes, or it throws. {values} when the commit held and
 *           stepCauses is empty, else what stopDelivery (lib/record.js)
 *           returns over stepCauses, then the commit cause when the commit
 *           failed, or else the describeCommitEnd end line when it
 *           committed: {result}, {replan} for a wave, or {rerun: true} for
 *           a gate step or the head check.
 *   buildInputsPath(run, kind, label)  .hivemind/<kind>-inputs-<stem>-<label>
 *           .json, stem run.factsStem, unique per run given a faithful facts
 *           relay (ADR-0037), else undefined: a --inputs command stop. The
 *           commit step builds its --subject-file and --files-file paths with
 *           it from the label and -subj or -files, and the PR step its
 *           --body-file and --comment-file paths (lib/pr.js).
 *   describeCommitEnd(commitValues, noun)  one sentence: the commit the
 *           files of the step noun names went into.
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
 *   command carries --trunk, --inputs, --subject-file and, only when the
 *   file list is not empty, --files-file, and --body-file with
 *   run.attribution.commit. The inputs_file content is the
 *   JSON text of only type and breaking, the subject_file content the raw
 *   code-built subject: a wave's from its plan steps, and fixed ones for
 *   the fix commit and the head check, and for the local review commit
 *   those standard-delivery review.js passes. The files_file content is
 *   the files joined by line feeds, so no free text sits in the JSON a
 *   runner copies (issue 595). A file that is empty or holds a line feed
 *   gets no --files-file value, a command stop before any runner call, so
 *   the join stays lossless and molt.sh reads back the same list.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this library into it, so a row can name a
 *   function of this library.
 *   Every step that can change files ends with the commit runner, whatever
 *   the workers returned (ADR-0037 invariant 1, decision 12). Workers never
 *   commit.
 *   Before any runner call, runCommitStep refuses a file list holding a
 *   review record path, docs/initiatives/<slug>/review-record.md compared
 *   case-insensitively, unless stepName is wave and RECORD_WRITES is true:
 *   one terminal cause naming the path, after the step causes (issue 619).
 *   A file-changing step reads its own result before its commit and passes
 *   its causes to runCommitStep, which stops through stopDelivery, isReplan
 *   true for a wave: a failed commit adds its cause after them, so a commit
 *   stop never hides the step's cause. A commit script refusal, a branch
 *   other than the plan branch and a runner command value outside its class
 *   (describeCommandStop), among them the --files-file value of a file list
 *   its line feed join cannot carry, are terminal.
 *   The commit runner calls agent() through runRunnerRelay (lib/runner.js),
 *   and its prompt follows its runner prompt and relayed reply rules, with
 *   a block per file word.
 *   The commit runner writes its own files and passes their paths to
 *   molt.sh (review finding fb4c129c), the paths buildInputsPath builds
 *   (issue 487), unique per call and run given a faithful facts relay; a
 *   retry label gets its own. What reaches git rests on the runner copying
 *   its file blocks (ADR-0037 Risks). molt.sh refuses a file outside the
 *   checkout, one that breaks a field rule and any dirty path outside its
 *   list, and the workflow checks every routing line.
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
      return { purpose: 'the fix round', noun: 'the fix round', subject: 'fix the failed validation' };
    case 'head':
      return { purpose: 'nothing: with no files it reports the working branch head after a reply to a stop', noun: 'the head check', subject: 'read the branch head' };
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

function toCommitSubject(text, fallbackSubject) {
  const subject = cutAtBoundary(text.replace(/[\s\x00-\x1f\x7f-\x9f]+/g, ' ').trim(), maxSubjectLength());
  return subject !== '' && !subject.includes('!:') && !/breaking[ -]change/i.test(subject) && !forbiddenSubjectTexts().some((forbidden) => subject.toLowerCase().includes(forbidden)) ? subject : fallbackSubject;
}

/**
 * Returns the words of the molt command for label, with --files-file only
 * when files is not empty, its value undefined when a file is empty or
 * holds a line feed, which the line feed join would lose.
 */
function listCommitWords(run, label, files) {
  const buildPath = (suffix) => buildInputsPath(run, 'molt', label + suffix);
  return ['--trunk', run.trunk, '--inputs', buildPath(''), '--subject-file', buildPath('-subj'), ...(files.length === 0 ? [] : ['--files-file', files.some((file) => /^$|\n/.test(file)) ? undefined : buildPath('-files')]), ...(run.attribution?.commit ? ['--body-file', buildPath('-body')] : [])];
}

function buildCommitPrompt(words, files, plan, purpose, subject, pluginRoot, body) {
  const inputs = JSON.stringify({ type: commitTypeMap()[plan.classification], breaking: plan.breaking });
  return ['Run the command below to commit ' + purpose + '.', dataBlocksSentence(), '', formatCommandBlock(buildRunnerCommand('molt', words, pluginRoot)), formatFileBlock(words, 2, inputs), formatFileBlock(words, 4, subject), ...(files.length === 0 ? [] : [formatFileBlock(words, 6, files.join('\n'))]), ...(body ? [formatFileBlock(words, words.length - 2, body)] : [])].join('\n');
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
  const outsideLines = splitStderrLines(stderr).filter((line) => /^outside: /.test(line));
  if (outsideLines.length === 0) {
    return lead;
  }
  const pathLines = outsideLines.map((line) => '- ' + quoteOrEmpty(readOutsidePath(line.replace(/^outside: /, ''))));
  return [lead + ' Dirty paths outside the files of ' + stepNoun + ':', ...capItemLines(pathLines)].join('\n');
}

function checkCommitRelay(relay, plan, stepNoun) {
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

function describeCommitEnd(commitValues, noun) {
  return noun.charAt(0).toUpperCase() + noun.slice(1) + ' was committed as ' + commitValues.commit + ', so that commit can hold partial edits.';
}

async function runCommitStep(run, plan, commit, stepCauses) {
  if (!Array.isArray(stepCauses)) {
    throw new Error('runCommitStep: stepCauses must be an array');
  }
  const texts = commit.texts ?? commitStepTexts(commit.stepName);
  const subject = commit.subject ?? texts.subject;
  const isReplan = commit.stepName === 'wave';
  phase('Commit');
  const listWords = (label) => listCommitWords(run, label, commit.files);
  /*
   * INVARIANT: the record match reads only the exact path form. molt.sh
   * refuses a listed path with a leading slash or an empty, . or ..
   * component, so a record path spelled with ./, //, /./ or a leading slash
   * never commits a record: the run stops on that commit script refusal.
   */
  const record =commit.stepName === 'wave' && RECORD_WRITES ? undefined : commit.files.find((file) => /^docs\/initiatives\/[^/]+\/review-record\.md$/i.test(file));
  const recordStop = record === undefined ? undefined : { problem: 'The commit step refused review record ' + encodeUntrustedText(record) + ', so ' + RUN_NAME + ' stopped.', terminal: true };
  const commandStop = describeCommandStop('commit', listWords(commit.label), listWords(commit.label + '-retry'));
  const buildPrompt = (label) => addResumeNote(buildCommitPrompt(listWords(label), commit.files, plan, texts.purpose, subject, run.pluginRoot, run.attribution?.commit), run);
  const checked = recordStop ?? commandStop ?? checkCommitRelay(await runRunnerRelay(buildPrompt, commit.label, 'Commit'), plan, texts.noun);
  if (checked.problem !== undefined) {
    return stopDelivery(stepCauses.concat([checked]), run, [], isReplan);
  }
  observeHead(run, checked.values.commit, plan.branch);
  if (stepCauses.length === 0) {
    return { values: checked.values };
  }
  const endLines = checked.values.committed === 'true' ? [describeCommitEnd(checked.values, texts.noun)] : [];
  return stopDelivery(stepCauses, run, endLines, isReplan);
}
