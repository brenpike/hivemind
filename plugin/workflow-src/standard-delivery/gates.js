/*
 * standard-delivery gates.js: the gates of the standard-delivery
 * workflow. It holds the gate ids, names and labels, the tail briefs and
 * asks, the bump, validate and fix steps, the gate rerun and the gate
 * loop.
 *
 * Inputs
 *   run    the run state of main.js createRunState. The gates read pass,
 *          replies, head, trunk and localReview, and update notRunGates.
 *   plan   the accepted plan, from runPlanningPass (plan.js).
 *   facts  the checked facts of the pass: trunk_commit is the bump base.
 *   gates  the gate loop state runGates builds: held, notes, runs,
 *          failures, fixRounds, reruns, rejected, answer and bumpMark.
 *          failures maps a head to the failures validation reported on it,
 *          and bumpMark is the run.commits length when the bump last held.
 *   BUMP_SCHEMA, BUMP_MODEL, FIX_SCHEMA, VALIDATE_SCHEMA,
 *   VALIDATE_COMMANDS_SCHEMA and the limits of main.js.
 *
 * Outputs
 *   runGates(run, plan, facts)  what runPullRequestStep (pr.js) returns
 *          once every configured gate holds on the head, else {result} or
 *          {replan}.
 *   A gate step returns {held} with a note when it held, {answer} when
 *   the user answered a review question, or a run end, {result} or
 *   {replan}, which isRunEnd tells apart.
 *   The steps, as meta.js names them:
 *   Bump    a gate, after the last wave. With no version files a haiku
 *           runner, else one drone on BUMP_MODEL, invokes hivemind:bump-type
 *           with the pass's facts trunk_commit as base and the plan's two
 *           versioning answers, and relays its stdout, which parses with
 *           bumpTypeRoutingSpec(); its verdict resolves through decide().
 *           Only on bump_required or no_bump the drone also sets each version
 *           file to its version at trunk_commit raised by the bump type
 *           (ADR-0037 decision 26), and the commit runner commits exactly
 *           those files, so a bump step run again with trunk unmoved
 *           commits nothing.
 *   Validate a gate. A drone runs validation as its whole task and edits
 *           nothing, and no commit runner follows it: a dirty path it leaves
 *           is refused by the next commit runner or by the dirty check of
 *           hivemind:open-plan-pr. When plan.validation_commands is not
 *           empty, the drone runs each of those commands once, from the
 *           inputs block, and VALIDATE_COMMANDS_SCHEMA offers no not_run.
 *           When it is empty, the drone runs the Validation Procedure of
 *           definitions.md, and VALIDATE_SCHEMA keeps not_run, so an empty
 *           list never skips validation.
 *   Fix     a failed validation resolves through decide(). Each taken
 *           round is a drone that fixes the failures and reports its files,
 *           which the commit runner commits; at maxFixRounds() the run asks.
 *           A failed result is kept for the head it ran on, so when a fix
 *           round commits nothing no validate agent runs again on that
 *           head: the next fix-round decision takes the kept failures.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   A gate holds only for the commit its step ended on, read from the
 *   commit runner's routing line; validation, which has no commit runner,
 *   ends on the head it ran on. The configured gates run in gateIds()
 *   order, local review only when the launch configures it, and a
 *   gate that already holds on the head is not run again. When a step ends
 *   on a commit other than the head the gates last checked, the run goes
 *   back to the first gate: each gate that held on an earlier commit runs
 *   again. Each such going back resolves once through decide() kind
 *   gate_rerun, and after maxGateReruns() of them the run asks. The pull
 *   request step runs only when every configured gate holds on the head.
 *   keepBumpHeld keeps the bump held over a head move, with no agent call,
 *   when every commit since is a runner commit of the pass with the plan
 *   commit type and breaking flag and no version file, which cannot change
 *   the verdict; a recorded range reruns it. The bump drone edits before
 *   decide() reads its verdict: the edit stays local and unpushed, and an
 *   ask leaves it to the dirty check of the next facts step.
 *   Tail asks: a question after the last wave pauses like any other open
 *   question, through pauseDelivery with its question, the commits and
 *   each gate that did not run, and a local review question also with its
 *   detail block. That
 *   covers the asks of resolveTailDecision, the fix round and gate rerun
 *   limits, and the user-input-required and high-severity-rejection
 *   questions; each ask carries a reason renderQuestions shows. Tail rounds
 *   share run.replies and the answers round numbering with planning
 *   rounds, so a resume replays every earlier agent from cache and takes
 *   the reply at the ask (askTail). A reply to a local review question
 *   reruns the review gate on the current head, after any gate the head
 *   move made stale, with the next gateLabel count and user_answer
 *   {question, reply} in its inputs block; the commit runner and
 *   localReviewRoutes() then apply as for any review run. A reply to any
 *   other tail ask starts a new pass through the facts step whose plan
 *   prompt carries the answer block {question, reply}; that replan does not
 *   count against maxReplans(). Nothing is pushed before every configured
 *   gate holds on one commit.
 *   The bump prompt names each versioning.artifact_files path in a git
 *   show command, and that list is planner text that can carry external
 *   content (review finding 143374b9). The impact is bounded:
 *   describePlanProblem refuses each path that fails isGitIdentifier, so a
 *   version file path with a character outside A-Z a-z 0-9 . _ / -, a
 *   leading '-' or '..' stops the run at the plan check, before the branch
 *   step and any later agent call, naming the reason, and the bump is left
 *   to the user. Rejected for now: a committed bump script that reads each
 *   file at trunk_commit from an inputs file costs a script, a skill and
 *   tests for a case no known project has.
 *   A version file path that passes isGitIdentifier can still lead through
 *   a symlink out of the checkout (review finding 8a9a66f3). That is the
 *   filesystem-alias residual ADR-0037 records for plan step files: the
 *   drone holds the whole Bash tool, and this script cannot read the file
 *   system, so no check here can close it. The impact is bounded: the bump
 *   reads each path with git show at trunk_commit, and the git tree holds a
 *   symlink as its link text and no path below one, so a path through a
 *   symlink in trunk yields no version and the drone stops blocked; a
 *   symlink added on the branch is in a branch commit the PR shows; only a
 *   drone that ignores its task writes through a link, and then the commit
 *   runner finds nothing to commit and the PR shows no version change.
 *   Rejected: a containment check in a committed bump script covers the
 *   bump only, while plan step files keep the same exposure.
 *
 * Why
 *   A gate holds only on a commit, so one loop decides which gate runs
 *   next from the head each step ends on.
 */

function gateIds() {
  return ['bump', 'validate', 'review'];
}

function configuredGateIds(run) {
  return run.localReview ? gateIds() : gateIds().filter((gateId) => gateId !== 'review');
}

function gateNames() {
  return { bump: 'the version bump', validate: 'validation', review: 'local review' };
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

function buildBumpSchema() {
  return buildTaggedSchema({
    tag: 'outcome',
    properties: {
      outcome: { type: 'string', enum: ['ran', 'blocked'], description: 'ran when the skill exited 0. blocked when it exited 1 or a version file cannot be set.' },
      stdout: { type: 'string', description: 'The skill stdout, word for word, every line.' },
      stderr: { type: 'string', description: 'The skill stderr, word for word, every line.' },
      blocker: { type: 'string', maxLength: 400, description: 'Why a version file cannot be set, in one or two short sentences written for the user.' },
      next_action: buildNextActionProperty()
    },
    required: ['outcome'],
    variants: { ran: { required: ['stdout'], optional: [] }, blocked: { required: [], optional: ['stderr', 'blocker', 'next_action'] } }
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

function buildTailBrief({ kind, problem, goOn, other, strength, why }) {
  return {
    id: 'tail',
    kind: kind,
    problem: problem,
    criticality: { level: 'medium', likelihood: 'certain', blast_radius: 'The working branch and the pull request it becomes.', if_ignored: unshownBriefText() },
    options: [
      { id: 'A', summary: goOn, steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: 'small', value: 'high', reversible: true },
      { id: 'B', summary: other === undefined ? 'Plan again: this run gives your reply to the planner before anything goes further.' : other, steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: 'trivial', value: 'low', reversible: true }
    ],
    recommendation: { option_id: strength === 'none' ? 'B' : 'A', strength: strength, why: why },
    assumptions: [{ statement: unshownBriefText(), origin: 'repo', evidence: unshownBriefText() }],
    gate: { irreversible: false, architectural: false, safety: false }
  };
}

function buildBumpTypeBrief(values) {
  const isBump = values.verdict === 'bump_required';
  return buildTailBrief({
    kind: VERSION_BUMP_TYPE_KIND,
    problem: isBump
      ? 'The commits on the branch since the trunk call for a ' + values.bump_type + ' version bump: each version file the plan names gets its trunk version raised by that bump.'
      : 'The commits on the branch since the trunk need no version bump: each version file the plan names keeps its trunk version.',
    goOn: isBump ? 'Make the ' + values.bump_type + ' version bump.' : 'Go on with no version bump.',
    strength: 'strong',
    why: 'The verdict comes by fixed rules from the commit types and the plan answers on versioning, and the version files stay on the branch until you merge.'
  });
}

function buildBumpIndeterminableBrief(values) {
  const hasVerdict = values.verdict === 'bump_required';
  return buildTailBrief({
    kind: VERSION_BUMP_INDETERMINABLE_KIND,
    problem: hasVerdict
      ? 'The commits on the branch call for a ' + values.bump_type + ' version bump, but the plan names no file that holds the version. Where should the version be set?'
      : 'The version bump cannot be told from the commits on the branch and the plan answers on versioning. Which version bump does the delivery need?',
    goOn: hasVerdict ? 'Name the version files: this run plans again with your reply.' : 'Name the version bump: this run plans again with your reply.',
    strength: 'none',
    why: 'Only you can decide the version of this delivery.'
  });
}

function buildValidationRemediationBrief(head, round) {
  return buildTailBrief({
    kind: VALIDATION_REMEDIATION_KIND,
    problem: 'Validation failed on commit ' + head + '. Run fix round ' + round + ' of at most ' + maxFixRounds() + ', where a worker fixes the failures and the run commits the fix and checks again?',
    goOn: 'Run a fix round.',
    strength: 'strong',
    why: 'A fix round stays on the branch and is listed for you, and every check runs again on its commit.'
  });
}

function buildFixLimitBrief(head) {
  return buildTailBrief({
    kind: VALIDATION_REMEDIATION_KIND,
    problem: 'Validation still fails on commit ' + head + ' after ' + maxFixRounds() + ' fix rounds. How should the failures be fixed?',
    goOn: 'Say how to fix the failures: this run plans the fix from your reply.',
    strength: 'none',
    why: 'The fix rounds did not make validation pass, so only you can decide what comes next.'
  });
}

function buildGateRerunBrief(staleIds, head, isLimit) {
  const names = joinNames(staleIds.map((gateId) => gateNames()[gateId]), 'and');
  const landed = 'Commit ' + head + ' landed after ' + names + ' held on an earlier commit.';
  return buildTailBrief({
    kind: GATE_RERUN_KIND,
    problem: isLimit
      ? landed + ' The checks already ran again ' + maxGateReruns() + ' times after later commits. How should the delivery go on?'
      : landed + ' Run ' + names + ' again on the new commit?',
    goOn: isLimit ? 'Say how to go on: this run plans again from your reply.' : 'Run the checks again on the new commit.',
    strength: isLimit ? 'none' : 'strong',
    why: isLimit
      ? 'Commits kept landing after the checks, so only you can decide what comes next.'
      : 'A check holds only for the commit it ran on, and the pull request needs every check to hold on the commit it pushes.'
  });
}

function isRunEnd(outcome) {
  return outcome.result !== undefined || outcome.replan !== undefined;
}

function askTail(asks, run, detail) {
  const questions = renderQuestions(asks, []);
  const reply = takeNextReply(run, run.replies.length + 1);
  if (reply === undefined) {
    return { result: pauseDelivery({ asks: asks, taken: [] }, questions, run, detail) };
  }
  run.replies.push(reply);
  return { answer: { question: detail === undefined ? questions : questions + '\n\n' + detail.text, reply: reply } };
}

function replanFromTailAsk(asks, run) {
  const asked = askTail(asks, run, undefined);
  if (asked.answer === undefined) {
    return asked;
  }
  return { replan: { reason: 'The user answered a question the run asked after the last wave, so plan again from the fresh facts with the answer block.', answer: asked.answer } };
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
  return replanFromTailAsk(resolution.asks, run);
}

function bumpTypeTaskLine() {
  return 'Invoke the hivemind:bump-type skill once, with each value of the inputs block below as the input of the same name.';
}

function buildBumpTypeInputs(trunkCommit, versioning) {
  return { base: trunkCommit, bump_trigger: versioning.bump_trigger, no_bump_match: versioning.no_bump_match };
}

function buildBumpTypePrompt(trunkCommit, versioning) {
  return [
    bumpTypeTaskLine(),
    runnerReadOnlySentence(),
    dataBlocksSentence(),
    runnerToolSentence(),
    '',
    formatDataBlock('inputs', buildBumpTypeInputs(trunkCommit, versioning))
  ].join('\n');
}

function checkBumpTypeRelay(relay, schema) {
  const stopped = 'so ' + RUN_NAME + ' stopped before validation.';
  if (!validateSchema(schema, relay).ok) {
    return { problem: 'The bump step returned a result it could not use, ' + stopped };
  }
  if (relay.outcome === 'blocked') {
    const said = Object.hasOwn(relay, 'blocker') ? describeReason(relay.blocker) : describeRelayBlocker(relay.stderr, true);
    return { problem: 'The bump step was blocked, ' + stopped + ' ' + said.charAt(0).toUpperCase() + said.slice(1), nextAction: relay.next_action };
  }
  const values = readRelayedLines(relay, bumpTypeRoutingSpec());
  if (values === undefined || !isConsistentBumpRelay(values)) {
    return { problem: 'The bump step returned malformed routing lines, ' + stopped };
  }
  return { values: values };
}

function resolveBumpVerdict(values, plan, run) {
  const hasFiles = plan.versioning.artifact_files.length > 0;
  if (values.verdict === 'ask_user' || (values.verdict === 'bump_required' && !hasFiles)) {
    return resolveTailDecision(VERSION_BUMP_INDETERMINABLE_KIND, buildBumpIndeterminableBrief(values), run);
  }
  return resolveTailDecision(VERSION_BUMP_TYPE_KIND, buildBumpTypeBrief(values), run);
}

function buildBumpPrompt(trunkCommit, plan, trunk) {
  return [
    bumpTypeTaskLine(),
    'Only on a bump_required or no_bump verdict, set each file of artifact_files below, as one step of the approved delivery plan: read it at trunk_commit with plain git show <trunk_commit>:<path> run from the repo folder, raise the version it holds by the bump_type line (none keeps it), and write that version in the file, never raising the version the file holds now. On any other verdict, edit nothing.',
    boundarySentence(),
    dataBlocksSentence(),
    'Each path in artifact_files passed the plan check as a safe git path, so it goes into that git show command as it is.',
    '',
    formatDataBlock('inputs', buildBumpTypeInputs(trunkCommit, plan.versioning)),
    formatDataBlock('version_files', { trunk_commit: trunkCommit, artifact_files: plan.versioning.artifact_files }),
    formatDataBlock('git', { branch: plan.branch, base: plan.base, trunk: trunk })
  ].join('\n');
}

function readGateEditOutcome(result, schema) {
  if (!validateSchema(schema, result).ok) {
    return { status: 'blocked', reason: 'it returned no usable result.', files: [] };
  }
  if (result.outcome === 'blocked') {
    return { status: 'blocked', reason: describeReason(result.blocker), files: result.files, nextAction: result.next_action };
  }
  return { status: 'complete', files: result.files };
}

function describeCommitEnd(commitValues) {
  const isCommitted = commitValues.committed === 'true';
  return isCommitted ? 'Its files were committed as ' + commitValues.commit + ', so that commit can hold partial edits.' : 'It left nothing to commit, so the branch head stays ' + commitValues.commit + '.';
}

function describeBlockedGateStep(stepTitle, reason, commitValues) {
  return stepTitle + ' was blocked, so ' + RUN_NAME + ' stopped after its commit: ' + reason + '\n' + describeCommitEnd(commitValues);
}

function runBumpStep(run, plan, facts, count) {
  if (plan.versioning.artifact_files.length === 0) {
    return agent(addResumeNote(buildBumpTypePrompt(facts.trunk_commit, plan.versioning), run), runnerOptions(gateLabel('bump-type', run, count), 'Bump'));
  }
  return agent(addResumeNote(buildBumpPrompt(facts.trunk_commit, plan, run.trunk), run), Object.assign(droneOptions(gateLabel('bump', run, count), 'Bump', BUMP_SCHEMA), { model: BUMP_MODEL }));
}

function describeBumpNote(values) {
  return values.verdict === 'bump_required' ? values.bump_type + ' bump' : 'no bump';
}

async function commitBumpEdit(run, plan, count, checked) {
  const committed = await runCommitStep(run, plan, plan.versioning.artifact_files, gateLabel('bump-commit', run, count), 'bump');
  if (committed.problem !== undefined) {
    return { result: finishDeliveryBlocked(committed.problem, run) };
  }
  if (checked.problem !== undefined) {
    return { result: finishDeliveryBlocked(checked.problem + '\n' + describeCommitEnd(committed.values), run, checked.nextAction) };
  }
  return { held: true, note: describeBumpNote(checked.values) };
}

async function runBumpGate(run, plan, facts, gates) {
  const count = gates.runs.bump;
  const hasFiles = plan.versioning.artifact_files.length > 0;
  phase('Bump');
  const result = await runBumpStep(run, plan, facts, count);
  const checked = checkBumpTypeRelay(result, hasFiles ? BUMP_SCHEMA : RELAY_SCHEMA);
  if (checked.problem !== undefined) {
    return hasFiles ? commitBumpEdit(run, plan, count, checked) : { result: finishDeliveryBlocked(checked.problem, run) };
  }
  const verdict = resolveBumpVerdict(checked.values, plan, run);
  if (isRunEnd(verdict)) {
    return verdict;
  }
  return hasFiles ? commitBumpEdit(run, plan, count, checked) : { held: true, note: describeBumpNote(checked.values) };
}

function isKeptRunnerCommit(entry, run, plan) {
  const record = Object.hasOwn(run.runnerCommits, entry) ? run.runnerCommits[entry] : undefined;
  return record !== undefined && record.commitType === commitTypeMap()[plan.classification] && record.breaking === plan.breaking
    && !record.files.some((file) => plan.versioning.artifact_files.includes(file));
}

function keepBumpHeld(run, plan, gates) {
  const since = run.commits.slice(gates.bumpMark);
  if (gates.held.bump !== undefined && since.length > 0 && since.every((entry) => isKeptRunnerCommit(entry, run, plan))) {
    gates.held.bump = run.head;
    gates.bumpMark = run.commits.length;
  }
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
    return { problem: 'The validation step returned no usable result, so ' + RUN_NAME + ' stopped before the pull request.' };
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
  const committed = await runCommitStep(run, plan, fix.files, gateLabel('fix-commit', run, round), 'fix');
  if (committed.problem !== undefined) {
    return { result: finishDeliveryBlocked(committed.problem, run) };
  }
  if (fix.status === 'blocked') {
    return { result: finishDeliveryBlocked(describeBlockedGateStep('The validation fix round', fix.reason, committed.values), run, fix.nextAction) };
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
    return { result: finishDeliveryBlocked(validation.problem, run, validation.nextAction) };
  }
  if (validation.status === 'not_run') {
    listNotRunGate(run, 'validation: the project documents no validation commands.');
  }
  if (validation.status !== 'failed') {
    return { held: true, note: validation.status === 'passed' ? 'passed' : 'not run, the project documents no validation commands' };
  }
  gates.failures[run.head] = validation.failures;
  if (gates.fixRounds >= maxFixRounds()) {
    return replanFromTailAsk([buildUndecidedAsk(buildFixLimitBrief(run.head))], run);
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
    return replanFromTailAsk([buildUndecidedAsk(buildGateRerunBrief(staleIds, run.head, true))], run);
  }
  gates.reruns += 1;
  return resolveTailDecision(GATE_RERUN_KIND, buildGateRerunBrief(staleIds, run.head, false), run);
}

function runGateStep(gateId, run, plan, facts, gates) {
  if (gateId === 'bump') {
    return runBumpGate(run, plan, facts, gates);
  }
  if (gateId === 'review') {
    return runReviewGate(run, plan, gates);
  }
  return runValidateGate(run, plan, gates);
}

async function runGates(run, plan, facts) {
  const gateList = configuredGateIds(run);
  const gates = { held: {}, notes: {}, runs: { bump: 0, validate: 0, review: 0 }, failures: {}, fixRounds: 0, reruns: 0, rejected: [], answer: undefined, bumpMark: 0 };
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
    const ended = await runGateStep(gateId, run, plan, facts, gates);
    if (isRunEnd(ended)) {
      return ended;
    }
    if (ended.held) {
      gates.held[gateId] = run.head;
      gates.notes[gateId] = ended.note;
      gates.bumpMark = gateId === 'bump' ? run.commits.length : gates.bumpMark;
    }
    if (ended.answer !== undefined) {
      gates.answer = ended.answer;
    }
    if (run.head === checkedHead) {
      continue;
    }
    checkedHead = run.head;
    keepBumpHeld(run, plan, gates);
    const rerun = resolveGateRerun(run, gates);
    if (isRunEnd(rerun)) {
      return rerun;
    }
    index = 0;
  }
  return runPullRequestStep(run, plan, gates);
}
