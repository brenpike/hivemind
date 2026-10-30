/*
 * standard-delivery plan.js: the planning pass of the standard-delivery
 * workflow. It holds the plan result and revise schemas, the path checks
 * of plan values, the plan and revise prompts, the plan check, the
 * planning pause lead and the resolution of every decision of a planning
 * pass. Its code-built briefs and the outside-limit check live in
 * briefs.js.
 *
 * Inputs
 *   run     the run state of main.js createRunState. The pass reads
 *           request, trunk, level, pass, storedAnswers and pendingReply,
 *           and updates answerLog, answeredKeys, taken and
 *           reversibleEffects.
 *   facts   the checked facts of the pass, from runFactsStep (relay.js).
 *   scope   the checked scope of the pass, from runScopeStep (scope.js).
 *           Once the revise result of a reply round passes the plan check,
 *           the pass logs the reply, then, unless the reply settled the shown
 *           plan acceptance and the shown result was restored, scopes again
 *           with runScopeStep(run, facts, round), label scope-P-R. That scope
 *           replaces the pass scope for the acceptance check and every later
 *           revise prompt of the pass, and its problem stops through
 *           stopDelivery (record.js) as a pass-start scope problem does.
 *   replan  undefined at launch, else the replan data of the step that
 *           sent the run back to planning: its reason, and the review when
 *           it carries one.
 *   PLAN_SCHEMA, BRIEF_SCHEMA, AUTONOMY_TABLE and the kind constants of
 *   main.js.
 *
 * Outputs
 *   runPlanningPass(run, facts, scope, replan)  {plan, freshness} once every
 *           question of the pass is settled or taken, else what stopDelivery
 *           returns or {result}, the pause of an open question.
 *   takeNextReply(run, round)  the reply to a round, also read by the
 *           tail asks of gates.js.
 *   The steps it runs, as meta.js names them:
 *   Plan    hivemind:cerebrate returns a plan result: PLAN_SCHEMA under
 *           plan, with outcome, questions and blocker.
 *   Revise  the planner revises the plan with the user reply and names, in
 *           settled, the label of each shown question the reply settles.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Once local review sent the run back to planning, every later plan
 *   acceptance resolves through decide() kind
 *   remediation_plan_acceptance, with the brief of
 *   buildRemediationPlanBrief (briefs.js).
 *   Every decision resolves through decide() with its kind fixed here,
 *   never from brief.kind. Every question of a plan pass is keyed through
 *   questionKey by its kind, a scope its call site passes and the question
 *   rendered alone by renderQuestions, so the key holds every value the user
 *   saw and no hand-picked subset of brief or plan fields (issue 433,
 *   review findings 7578f16f and 0c804e49). The scope is the pass for a
 *   planner question, the pass and the whole plan for both plan
 *   acceptances, 'run' for trunk_stale, whose rendered text holds the trunk
 *   facts, and 'run' with the step id for an irreversible effect, whose
 *   rendered text holds the exact summary, so a changed irreversible text
 *   is a new question the user must approve word for word. A tail decision
 *   has no scope and no key. A plan
 *   acceptance ask waits while any other ask of its round is open, so the
 *   user accepts the plan that holds no open question. When a reply settles
 *   the shown acceptance, the plan result that was shown is the one that
 *   runs, and a revise that only rewrites the summary to record the answer
 *   does not ask again (issue 433). The residual: a planner question raised
 *   again with other rendered text, a changed recommendation too, is a new
 *   question, asked again in the next pause. The planner's revise pass
 *   reads the reply. The revise result names in settled, by label like Q1,
 *   the shown questions the reply settled: only the keys of those questions
 *   count as answered and are not asked again, and every other question
 *   resolves again and goes in the next pause. A pause shows no decision
 *   made for you, so settled holds Q labels only. Which shown questions a
 *   reply settles is the planner's judgment, as its gate flags are
 *   (ADR-0037 decision 3). The impact is
 *   bounded: a question the planner does not name is asked again, the
 *   settled enum allows only the labels shown, and nothing runs while a
 *   question is open. Rejected: a free-text reply has no code parse, and a
 *   pause per effect adds stops (review finding d5619285, option C).
 *   Every plan value at a field whose PLAN_SCHEMA description starts with
 *   repositoryPathMark() must pass isRepositoryPath (review finding
 *   461fe942). collectRepositoryPaths walks the schema for the mark, so a
 *   new path field is read once it carries the mark, by
 *   findRepositoryPathProblem and by listPlanPaths. describePlanProblem
 *   runs the path check after the schema check and before computeWave, so
 *   a bad path stops the run before the branch step and any later agent
 *   call. The rule is the files rule of molt.sh, its home, and a parity test
 *   runs one corpus through both and requires the same verdicts, so a change
 *   lands in both. The check is lexical, so a symlinked path or one that
 *   names a directory is left to molt.sh. Fix round files are not plan
 *   fields: they reach only molt.sh, which applies the same rule before any
 *   change. The user rejected local review finding c2e0ada3, which asked for
 *   a check of fix round files members in the workflow, on this basis
 *   (ADR-0037, Amendment 2026-10-25). isGitIdentifier stays on
 *   artifact_files for the bump-type --version-file argument of the
 *   validate step (gates.js), since the path rule allows spaces, shell
 *   characters and a leading '-'.
 *   Stops (issue 457): a plan, revise or rescope problem goes through
 *   stopDelivery (record.js) with isReplan true, so the reply starts a new
 *   pass outside maxReplans(). A null result, an agent failure, adds the
 *   agent-failure sentence through describeUnusableResult (lib/result.js)
 *   and ends the run with next action run_again; any other problem, a
 *   planner's blocked outcome among them, pauses with the fix line, and
 *   the reply reaches the next plan prompt's answers block. A revise that
 *   fails the plan check logs its reply first, settled [], so the stop
 *   asks the next round.
 *   Each validation_commands entry is one command line: describePlanProblem
 *   refuses a blank entry, or one that holds a line break or another
 *   control character, naming the reason, before the branch step.
 *   Branch names: describePlanProblem refuses a plan.branch outside the
 *   Branch Taxonomy and Branch Naming of
 *   ${CLAUDE_PLUGIN_ROOT}/governance/workflow.md, so a runner with no
 *   skill body never creates one (issue 467).
 *   Settled question guard: within one pass, a trunk_stale question a
 *   reply settled renders the same text for the whole run, and a settled
 *   plan_acceptance or remediation_plan_acceptance restores the plan result
 *   that was shown, so its key holds and it is never asked again. When a
 *   pause round would still show one, that is a workflow defect: the run
 *   does not pause, and a terminal stop ends it naming the question kind. An
 *   irreversible effect whose text changed, and a planner question that
 *   renders other text, are new questions and pause again.
 *   A planning pause leads with describePlanLine(plan, outsidePaths), one
 *   line: the encoded branch, the step count, the distinct file count and
 *   digest.change through renderText. The answer log question and the
 *   revise prompt's questions block hold that lead and the questions, the
 *   text the user saw.
 *   An irreversible effect is asked as an exact entry, so the pause keeps
 *   its exact text whole in every fit tier (lib/result.js whole blocks): the
 *   user never answers an effect question without its verbatim text.
 *   The plan and revise prompts carry the scope in a scope data block right
 *   after the request block, and no other planning text holds it.
 *   Each reply a plan pause consumes goes once into run.answerLog as the
 *   {question, settled, reply} entry buildAnswerEntry (lib/brief.js) builds
 *   from the round and its revise, pushed once the revise of its round
 *   passes the plan check and before any rescope: the question is the text
 *   the pause showed, settled the shown labels the revise names, in shown
 *   order, [] when it names none. The answered keys of the round come from
 *   that logged settled, so the keys and the log share one derivation.
 *   Every plan prompt once the log is not empty carries the whole log in
 *   an answers data block, and a revise prompt the entries of earlier
 *   rounds. Its data line calls settled only
 *   what the settled labels of an entry name, never the reply of the round
 *   being revised, so a replan never asks or reverses a settled answer and
 *   never takes an open question as settled (issue 472). With an empty log,
 *   the plan and first revise prompts are the prompts of a run with no
 *   answers, so a resume replays them from cache.
 *   Outside-limit ask: the limit check and the pause lead read every plan
 *   path through the mark walk (listPlanPaths): the version files and the
 *   step files the wave commits take. When scope.limits is not empty, a
 *   plan path that neither equals a limit nor sits under limit + '/' makes
 *   the plan or remediation plan acceptance brief recommendation strength
 *   none, so decide() asks it no_recommendation at every level. Its problem
 *   names their count when it fits, and the pause lead of a round that shows
 *   the acceptance names up to maxListedItems() of them, each encoded whole,
 *   then the count of the rest. Empty limits leave the brief as it
 *   was. The limits come only from the scope step, so a later pass asks a
 *   file outside them again. Validation fix round and local review edits are
 *   not plan paths and are outside the limits (ADR-0037, finding 2ecc5af1).
 *   The plan and revise prompts restate no rule of
 *   ${CLAUDE_PLUGIN_ROOT}/agents/cerebrate.md (docs/engineering-principles.md
 *   P24): how to read the facts, what is left to plan, the review block and
 *   the revise rules live there, and each field rule in its schema.
 *
 * Why
 *   Every plan a wave runs is checked and accepted in this one place, so
 *   no later step reads a plan field the plan check did not pass.
 */

function omitSchemaDialect(schema) {
  return Object.fromEntries(Object.entries(schema).filter(([key]) => key !== '$schema'));
}

function buildPlanResultSpec(planSchema, briefSchema) {
  return {
    tag: 'outcome',
    properties: {
      outcome: {
        type: 'string',
        enum: ['complete', 'blocked'],
        description: 'complete when the plan is done. blocked only when the delivery cannot be planned at all.'
      },
      plan: omitSchemaDialect(planSchema),
      questions: {
        type: 'array',
        description: 'One decision brief for each decision the repository and the request do not settle.',
        items: omitSchemaDialect(briefSchema)
      },
      blocker: { type: 'string', maxLength: 400, description: 'Why the delivery cannot be planned, in one or two short sentences written for the user.' }
    },
    required: ['outcome', 'questions'],
    variants: { complete: { required: ['plan'], optional: [] }, blocked: { required: [], optional: ['blocker'] } }
  };
}

function buildPlanResultSchema(planSchema, briefSchema) {
  return buildTaggedSchema(buildPlanResultSpec(planSchema, briefSchema));
}

function buildReviseResultSchema(shownAsks) {
  const spec = buildPlanResultSpec(PLAN_SCHEMA, BRIEF_SCHEMA);
  spec.properties.settled = {
    type: 'array',
    description: 'The label, like Q1, of each shown question the reply settles. List a question of the workflow itself (plan acceptance, trunk, effect outside the repo) only when the reply clearly lets the run go on with it as shown. A question left out is asked again.',
    items: { type: 'string', enum: listShownLabels(shownAsks) }
  };
  spec.required.push('settled');
  return buildTaggedSchema(spec);
}

function externalLabel() {
  return 'Can carry external content.';
}

function repositoryPathMark() {
  return externalLabel() + ' Repository path.';
}

function toAsciiLowerCase(text) {
  return text.replace(/[A-Z]/g, (letter) => String.fromCharCode(letter.charCodeAt(0) + 32));
}

function isRepositoryPath(value) {
  if (typeof value !== 'string' || value.length === 0 || value.startsWith('/')) {
    return false;
  }
  const isOneLine = Array.from(value).every((character) => character.codePointAt(0) >= 32 && character.codePointAt(0) !== 127);
  return isOneLine && value.split('/').every((part) => !['', '.', '..', '.git'].includes(toAsciiLowerCase(part)));
}

/**
 * Pushes {location, value} to found for each value at a node the mark names,
 * in pre-order over the present properties and items. Returns found.
 */
function collectRepositoryPaths(schema, value, location, found) {
  if (typeof schema.description === 'string' && schema.description.startsWith(repositoryPathMark())) {
    found.push({ location: location, value: value });
  }
  if (schema.properties !== undefined && isPlainObject(value)) {
    const presentNames = Object.keys(schema.properties).filter((name) => Object.prototype.hasOwnProperty.call(value, name));
    presentNames.forEach((name) => collectRepositoryPaths(schema.properties[name], value[name], location === '' ? name : location + '.' + name, found));
  }
  if (schema.items !== undefined && Array.isArray(value)) {
    value.forEach((item, index) => collectRepositoryPaths(schema.items, item, location + '[' + index + ']', found));
  }
  return found;
}

function findRepositoryPathProblem(schema, value, location) {
  const problem = collectRepositoryPaths(schema, value, location, []).find((entry) => !isRepositoryPath(entry.value));
  return problem === undefined ? '' : problem.location;
}

/**
 * Returns the distinct plan paths in walk order: the values at PLAN_SCHEMA
 * fields the mark names, version files then step files.
 */
function listPlanPaths(plan) {
  return [...new Set(collectRepositoryPaths(PLAN_SCHEMA, plan, '', []).map((entry) => entry.value))];
}

function settledAnswersSentence(replyHome) {
  return dataBlocksSentence(replyHome) + ' In each answers entry, only the questions its settled labels name are the user\'s settled decisions: never ask them again, never reverse them.';
}

function buildPlanPrompt(request, facts, scope, replan, answerLog) {
  const hasAnswers = answerLog.length > 0;
  const lines = [
    'Plan the delivery of the user request below in this repository, as one plan on one working branch.',
    boundarySentence(),
    hasAnswers ? settledAnswersSentence(undefined) : dataBlocksSentence(undefined)
  ];
  if (replan !== undefined) {
    lines.push('This is a new plan in a run that already started: the replan block says why.');
  }
  lines.push('', buildFactsBlock(facts), formatDataBlock('request', request), formatDataBlock('scope', scope));
  if (replan !== undefined) {
    lines.push(formatDataBlock('replan', replan.reason));
  }
  if (replan !== undefined && replan.review !== undefined) {
    lines.push(formatDataBlock('review', replan.review));
  }
  if (hasAnswers) {
    lines.push(formatDataBlock('answers', answerLog));
  }
  return lines.join('\n');
}

function buildPlanRevisePrompt({ request, facts, scope, answers, plan, questions, reply }) {
  const hasAnswers = answers.length > 0;
  const lines = [
    'Revise your plan for the delivery of the user request below with the user reply below.',
    boundarySentence(),
    hasAnswers ? settledAnswersSentence('The reply block') : dataBlocksSentence('The reply block'),
    '',
    buildFactsBlock(facts),
    formatDataBlock('request', request),
    formatDataBlock('scope', scope)
  ];
  if (hasAnswers) {
    lines.push(formatDataBlock('answers', answers));
  }
  lines.push(formatDataBlock('earlier_plan', plan), formatDataBlock('questions', questions), formatDataBlock('reply', reply));
  return lines.join('\n');
}

/**
 * Returns why one validation command of the plan cannot run as one command
 * line: it is blank, holds a line break, or holds another control
 * character. Returns '' for a command the plan check accepts.
 */
function describeValidationCommandProblem(command) {
  if (command.trim() === '') {
    return 'is blank';
  }
  const codePoints = Array.from(command).map((character) => character.codePointAt(0));
  if (codePoints.some((codePoint) => [10, 13, 0x85, 0x2028, 0x2029].includes(codePoint))) {
    return 'holds a line break';
  }
  if (codePoints.some((codePoint) => codePoint < 32 || (codePoint >= 127 && codePoint <= 0x9f))) {
    return 'holds a control character';
  }
  return '';
}

function describePlanProblem(planResult, resultSchema, facts, trunk) {
  if (!isPlainObject(planResult)) {
    return 'The planner returned no result, so ' + RUN_NAME + ' stopped.';
  }
  if (!validateSchema(resultSchema, planResult).ok) {
    return 'The planner returned a plan that does not fit the plan schema, so ' + RUN_NAME + ' stopped.';
  }
  if (planResult.outcome === 'blocked') {
    return 'The planner could not plan the delivery: ' + describeReason(planResult.blocker);
  }
  const plan = planResult.plan;
  const pathLocation = findRepositoryPathProblem(PLAN_SCHEMA, plan, '');
  if (pathLocation !== '') {
    return 'The plan names a path at ' + pathLocation + ' that is not a plain path inside the repository, so ' + RUN_NAME + ' stopped.';
  }
  const wave = computeWave(plan.steps, []);
  if (!wave.ok) {
    return 'The plan steps cannot be scheduled, so ' + RUN_NAME + ' stopped: ' + toPrintableAscii(wave.problem);
  }
  if (plan.trunk_freshness !== facts.trunk_freshness) {
    return 'The plan copies a trunk freshness other than the facts, so ' + RUN_NAME + ' stopped.';
  }
  if (!isGitIdentifier(plan.branch) || !isGitIdentifier(plan.base)) {
    return 'The plan names a branch or base that is not a safe git name, so ' + RUN_NAME + ' stopped.';
  }
  if (!plan.versioning.artifact_files.every((artifactPath) => isGitIdentifier(artifactPath))) {
    return 'The plan names a version file path that is not a safe git path, so ' + RUN_NAME + ' stopped.';
  }
  for (let index = 0; index < plan.validation_commands.length; index += 1) {
    const commandProblem = describeValidationCommandProblem(plan.validation_commands[index]);
    if (commandProblem !== '') {
      return 'The plan names a validation command at validation_commands[' + index + '] that ' + commandProblem + ', so ' + RUN_NAME + ' stopped.';
    }
  }
  const isOnOtherBranch = facts.head_state === 'branch' && facts.branch !== trunk;
  if (isOnOtherBranch && plan.branch !== facts.branch) {
    return 'The run started on branch ' + encodeUntrustedText(facts.branch) + ' and delivers on it, but the plan names branch ' + encodeUntrustedText(plan.branch) + ', so ' + RUN_NAME + ' stopped.';
  }
  if (!/^(feature|bugfix|hotfix|refactor|chore|docs|test|ci)\/[a-z0-9]+(-[a-z0-9]+)*$/.test(plan.branch)) {
    return 'The plan names branch ' + encodeUntrustedText(plan.branch) + ', which is not a prefix of feature, bugfix, hotfix, refactor, chore, docs, test or ci, a slash and lowercase words joined by hyphens, so ' + RUN_NAME + ' stopped.';
  }
  return undefined;
}

/**
 * Returns the key a question counts as answered under: its kind, the call
 * site scope and the ask as renderQuestions shows it alone. A question the
 * user saw settled is not asked again after a revise that shows it the
 * same way (issue 433).
 */
function questionKey(kind, scope, ask) {
  return JSON.stringify([kind, scope, renderQuestions([ask])]);
}

function describeCount(count, noun) {
  return count + ' ' + noun + (count === 1 ? '' : 's');
}

/**
 * Returns the one-line lead of a planning pause: the encoded branch, the
 * step count, the distinct plan path count and digest.change through
 * renderText. When outsidePaths is not empty, one sentence after it names
 * up to maxListedItems() of them, each encoded whole, then the count of
 * the rest.
 */
function describePlanLine(plan, outsidePaths) {
  const fileCount = listPlanPaths(plan).length;
  const lead = 'The plan for branch ' + encodeUntrustedText(plan.branch) + ' has ' + describeCount(plan.steps.length, 'step') + ' over ' + describeCount(fileCount, 'file') + ': ' + renderText(plan.digest.change);
  if (outsidePaths.length === 0) {
    return lead;
  }
  const shownPaths = outsidePaths.slice(0, maxListedItems()).map((file) => encodeUntrustedText(file));
  const restCount = outsidePaths.length - shownPaths.length;
  return lead + ' Outside the limits you set: ' + joinNames(restCount > 0 ? [...shownPaths, restCount + ' more'] : shownPaths, 'and') + '.';
}

/**
 * Returns the one text every code-built brief puts in the fields no
 * message shows (lib/brief.js): steel_man, straw_man,
 * criticality.if_ignored and each assumption's statement and evidence.
 */
function unshownBriefText() {
  return 'Not shown.';
}

function resolveDecision(kind, brief, scope, run, resolution) {
  const decision = decide({ kind: kind, level: run.level, brief: brief }, AUTONOMY_TABLE, BRIEF_SCHEMA);
  if (decision.action === 'take') {
    resolution.taken.push({ brief: brief, kind: kind });
    return 'take';
  }
  const ask = { brief: brief, reason: decision.reason, kind: kind };
  if (kind === EXTERNAL_EFFECT_KIND) {
    ask.exact = true;
  }
  if (scope !== undefined) {
    ask.key = questionKey(kind, scope, ask);
    if (run.answeredKeys.has(ask.key)) {
      return 'answered';
    }
  }
  resolution.asks.push(ask);
  return 'ask';
}

function resolveTrunkFreshness(facts, run, resolution) {
  const mapped = trunkFreshnessMap()[facts.trunk_freshness];
  if (mapped !== 'decide') {
    return mapped;
  }
  const status = resolveDecision(TRUNK_STALE_KIND, buildTrunkStaleBrief(facts), 'run', run, resolution);
  return status === 'ask' ? undefined : 'stale';
}

function resolveExternalEffects(plan, run, resolution) {
  for (const step of plan.steps) {
    for (const effect of step.external_effects) {
      if (effect.reversible) {
        resolution.reversibleEffects.push({ stepId: step.id, summary: effect.summary });
        continue;
      }
      /*
       * INVARIANT: the key holds the full step id in its scope and the
       * rendered question, which shows the exact effect summary, so a
       * changed irreversible text is a new question the user must approve
       * word for word, and two steps with the same summary are two
       * questions. The message does not name the step, so no step id is
       * cut; the step id lives only in the key.
       */
      resolveDecision(EXTERNAL_EFFECT_KIND, buildExternalEffectBrief(effect.summary), ['run', step.id], run, resolution);
    }
  }
}

function resolvePlanAcceptance(plan, run, resolution, scope) {
  const isRemediation = run.taken.some((entry) => entry.kind === PLANNER_ESCALATION_ROUTING_KIND || entry.kind === ROOT_CLUSTER_ROUTING_KIND);
  resolution.outsidePaths = listOutsidePaths(plan, scope);
  if (isRemediation) {
    return resolveDecision(REMEDIATION_PLAN_ACCEPTANCE_KIND, markOutsideLimits(buildRemediationPlanBrief(plan), resolution.outsidePaths), [run.pass, plan], run, resolution);
  }
  return resolveDecision(PLAN_ACCEPTANCE_KIND, markOutsideLimits(buildPlanAcceptanceBrief(plan), resolution.outsidePaths), [run.pass, plan], run, resolution);
}

function resolvePlanAsks(planResult, facts, run, scope) {
  const resolution = { asks: [], taken: [], freshness: undefined, reversibleEffects: [], outsidePaths: [] };
  const plan = planResult.plan;
  /*
   * INVARIANT: a planner question key holds the pass and the question as
   * the user sees it, never the unrendered brief id, assumptions or option
   * steel_man. A settled question raised again with the same rendered text
   * is answered; one that renders other text is a new question, which
   * pauses again. The plan acceptance key holds the pass and
   * the whole plan, so the acceptance waits until no other ask of the
   * round is open: the plan the user accepts is the plan that runs.
   */
  planResult.questions.forEach((brief) => resolveDecision(PLANNER_QUESTION_KIND, brief, run.pass, run, resolution));
  const acceptance = resolvePlanAcceptance(plan, run, resolution, scope);
  const acceptanceAsk = resolution.asks[resolution.asks.length - 1];
  resolution.freshness = resolveTrunkFreshness(facts, run, resolution);
  resolveExternalEffects(plan, run, resolution);
  if (acceptance === 'ask' && resolution.asks.length > 1) {
    resolution.asks = resolution.asks.filter((ask) => ask !== acceptanceAsk);
  }
  return resolution;
}

function acceptResolution(resolution, run) {
  for (const entry of resolution.taken) {
    const isListed = run.taken.some((listed) => JSON.stringify(listed.brief) === JSON.stringify(entry.brief));
    if (!isListed) {
      run.taken.push(entry);
    }
  }
  for (const effect of resolution.reversibleEffects) {
    const isListed = run.reversibleEffects.some((listed) => listed.stepId === effect.stepId && listed.summary === effect.summary);
    if (!isListed) {
      run.reversibleEffects.push(effect);
    }
  }
}

function markSettledAsks(settledLabels, shownAsks, run, settledKinds) {
  shownAsks.forEach((ask, index) => {
    if (ask.key !== undefined && settledLabels.includes(questionLabel(index))) {
      run.answeredKeys.add(ask.key);
      settledKinds.add(ask.kind);
    }
  });
}

function takeNextReply(run, round) {
  const storedReply = readStoredReply(run.storedAnswers, round);
  if (storedReply !== undefined) {
    return storedReply;
  }
  const pendingReply = run.pendingReply;
  run.pendingReply = undefined;
  return pendingReply;
}

async function runPlanningPass(run, facts, passScope, replan) {
  phase('Plan');
  let scope = passScope;
  let resultSchema = PLAN_RESULT_SCHEMA;
  let shownAsks = [];
  let shownResult;
  let shownEntry;
  const settledKinds = new Set();
  const planPrompt = buildPlanPrompt(run.request, facts, scope, replan, run.answerLog);
  let planResult = await agent(planPrompt, plannerCallOptions('plan-' + run.pass, 'Plan', resultSchema));
  for (;;) {
    const problem = describePlanProblem(planResult, resultSchema, facts, run.trunk);
    if (problem !== undefined) {
      if (shownAsks.length > 0) {
        run.answerLog.push(buildAnswerEntry(shownEntry, undefined));
      }
      return stopDelivery([describeUnusableResult(problem, planResult)], run, [], true);
    }
    if (shownAsks.length > 0) {
      run.answerLog.push(buildAnswerEntry(shownEntry, planResult));
      markSettledAsks(run.answerLog[run.answerLog.length - 1].settled, shownAsks, run, settledKinds);
      if (shownAsks.some((ask) => [PLAN_ACCEPTANCE_KIND, REMEDIATION_PLAN_ACCEPTANCE_KIND].includes(ask.kind) && run.answeredKeys.has(ask.key))) {
        planResult = shownResult;
      } else {
        const rescoped = await runScopeStep(run, facts, run.answerLog.length);
        if (rescoped.problem !== undefined) {
          return stopDelivery([rescoped], run, [], true);
        }
        scope = rescoped.scope;
      }
    }
    const resolution = resolvePlanAsks(planResult, facts, run, scope);
    if (resolution.asks.length === 0) {
      acceptResolution(resolution, run);
      return { plan: planResult.plan, freshness: resolution.freshness };
    }
    /*
     * INVARIANT: a settled trunk question keeps its rendered text for the
     * whole run, and a settled plan acceptance restores the shown plan
     * result above, so its key holds again. One of these three kinds a
     * reply settled coming back in its pass is a workflow defect, so a
     * terminal stop ends the run with no pause (issue 434).
     */
    const resettled = resolution.asks.find((ask) => settledKinds.has(ask.kind) && [PLAN_ACCEPTANCE_KIND, REMEDIATION_PLAN_ACCEPTANCE_KIND, TRUNK_STALE_KIND].includes(ask.kind));
    if (resettled !== undefined) {
      return stopDelivery([{ problem: 'Workflow defect: the ' + resettled.kind + ' question came back after a reply settled it, so ' + RUN_NAME + ' stopped.', terminal: true }], run, [], true);
    }
    const isAcceptance = resolution.asks.some((ask) => [PLAN_ACCEPTANCE_KIND, REMEDIATION_PLAN_ACCEPTANCE_KIND].includes(ask.kind));
    const lead = describePlanLine(planResult.plan, isAcceptance ? resolution.outsidePaths : []);
    const round = run.answerLog.length + 1;
    const reply = takeNextReply(run, round);
    if (reply === undefined) {
      return { result: pauseDelivery(resolution, run, lead) };
    }
    phase('Revise');
    const questions = lead + '\n\n' + renderQuestions(resolution.asks);
    shownAsks = resolution.asks;
    shownResult = planResult;
    shownEntry = { question: questions, labels: listShownLabels(shownAsks), reply: reply };
    resultSchema = buildReviseResultSchema(shownAsks);
    const revisePrompt = buildPlanRevisePrompt({ request: run.request, facts: facts, scope: scope, answers: run.answerLog, plan: planResult.plan, questions: questions, reply: reply });
    planResult = await agent(revisePrompt, plannerCallOptions('revise-' + round, 'Revise', resultSchema));
  }
}
