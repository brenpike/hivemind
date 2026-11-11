/*
 * standard-delivery plan.js: the planning pass of the standard-delivery
 * workflow. It holds the plan result and revise schemas, the plan and
 * revise prompts, the plan check, the planning pause lead and the
 * resolution of every decision of a planning pass. Its code-built briefs
 * and the outside-limit check live in briefs.js, and the path checks of
 * plan values in paths.js.
 *
 * Inputs
 *   run     the run state of main.js createRunState. The pass reads
 *           request, trunk, references, level, pass, decisions,
 *           storedAnswers and pendingReply, and updates answerLog, answeredKeys, taken,
 *           approvals and reversibleEffects. references reach
 *           describeClosesProblem (pr.js).
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
 *           tail asks of tails.js.
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
 *   repositoryPathMark() must pass isRepositoryPath (paths.js holds the
 *   rule). describePlanProblem runs findRepositoryPathProblem after the
 *   schema check and before computeWave, so a bad path stops the run
 *   before the branch step and any later agent call.
 *   Stops (issue 457): a plan, revise or rescope problem goes through
 *   stopDelivery (record.js) with isReplan true, so the reply starts a new
 *   pass outside maxReplans(). Each plan and revise call goes through
 *   callCheckedPlanner (checks.js), which asks a result that fails the
 *   plan check again, a planner question decide() refuses as a defect
 *   among them, and one still failing ends the run, terminal with next
 *   action report. A null result, an agent failure, adds the
 *   agent-failure sentence through describeUnusableResult (lib/stop.js)
 *   and ends the run with next action run_again. A planner's blocked
 *   outcome that fits its schema and gives a reason pauses with the fix
 *   line, and the reply reaches the next plan prompt's answers block.
 *   The settled question guard below is report too: a workflow defect. A
 *   revise that ends the run on the plan check logs its reply first,
 *   settled []; one a retry fixed logs the settled labels of the fixed
 *   result. Before the plan call, a run that started on a branch other
 *   than the trunk whose name is outside the Branch Taxonomy pauses with
 *   the fix line.
 *   Each validation_commands entry is one command line: describePlanProblem
 *   refuses a blank entry, or one that holds a line break or another
 *   control character, naming the reason, before the branch step.
 *   Branch names: by the plan schema branch pattern, which the schema check
 *   tests first, describePlanProblem refuses a plan.branch outside the
 *   Branch Taxonomy and Branch Naming of ${CLAUDE_PLUGIN_ROOT}/governance/workflow.md,
 *   so a runner with no skill body never creates one (issue 467).
 *   Title type: normalizePlanTitle (checks.js) first cuts the plan's own
 *   commit type from plan.title. Then describePlanProblem refuses a plan whose cleaned
 *   plan.title starts with a commitTypeMap() value in any letter case, an optional
 *   parenthesized scope, an optional '!' and ':', with a fixed message that
 *   names no title text, since the pull request step writes the type
 *   before the title (issue 469). It refuses an empty buildTitleText(plan)
 *   (pr.js) the same way, so the pull request title is never only its type.
 *   Settled question guard: within one pass, a trunk_stale question a
 *   reply settled renders the same text for the whole run, and a settled
 *   plan_acceptance or remediation_plan_acceptance restores the plan result
 *   that was shown, so its key holds and it is never asked again. When a
 *   pause round would still show one, that is a workflow defect: the run
 *   does not pause, and a terminal stop ends it naming the question kind. An
 *   irreversible effect whose text changed, and a planner question that
 *   renders other text, are new questions and pause again.
 *   A planning pause leads with describePlanLine(plan): one line of the
 *   encoded branch, the step count, the distinct file count and
 *   digest.change through renderText. It names no outside path; the
 *   acceptance problem gives their count when it fits.
 *   The answer log question and the revise prompt's questions block hold
 *   that lead and the questions, the text the user saw.
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
 *   On both paths that log a planning reply, logPlanningReply also applies
 *   readReplyChoices (lib/brief.js) of the reply to run.approvals through
 *   applyApprovalChoices (approvals.js); settled still comes only from the
 *   revise.
 *   Every plan prompt once the log is not empty carries the whole log in
 *   an answers data block, and a revise prompt the entries of earlier
 *   rounds. Its data line calls settled only
 *   what the settled labels of an entry name, never the reply of the round
 *   being revised, so a replan never asks or reverses a settled answer and
 *   never takes an open question as settled (issue 472). Each prompt
 *   takes the log through listAnswerEntries (main.js), which puts one
 *   settled entry per launch decision ahead of it (issue 500). With no
 *   decision and an empty log, the plan and first revise prompts are the
 *   prompts of a run with no answers, so a resume replays them from cache.
 *   Outside-limit list: the limit check and the pause lead read every plan
 *   path through the mark walk (listPlanPaths): the version files and the
 *   step files the wave commits take. When scope.limits is not empty, a
 *   plan path in neither versioning.artifact_files nor
 *   versioning.changelog_files that neither equals a limit path nor sits
 *   under it plus '/' makes resolvePlanAcceptance pass outside_limits in
 *   listed to decide(), as plan.remediation_gate.repeats_surface passes
 *   repeats_surface, so an acceptance decide() takes is taken and listed
 *   for veto before merge: markOutsideLimits never changes the strength or
 *   why. A surface cell or a gate flag still asks, with its own reason.
 *   The acceptance problem names their count when it fits. Empty limits
 *   leave the brief as it was. The limits come only
 *   from the scope step, so a later pass lists a file outside them again.
 *   Validation fix round and local review edits are not plan paths and are
 *   outside the limits (ADR-0037, finding 2ecc5af1).
 *   A taken decision goes in taken as {brief, kind, listed}, listed the
 *   listReasons() names decide() returns with it.
 *   The plan and revise prompts restate no rule of
 *   ${CLAUDE_PLUGIN_ROOT}/agents/cerebrate.md (docs/engineering-principles.md
 *   P24): how to read the facts, what is left to plan, the review block and
 *   the revise rules live there, and each field rule in its schema.
 *
 * Why
 *   Every plan a wave runs is checked and accepted in this one place, so
 *   no later step reads a plan field the plan check did not pass.
 */

function buildPlanResultSpec(planSchema, briefSchema) {
  return {
    tag: 'outcome',
    properties: {
      outcome: {
        type: 'string',
        enum: ['complete', 'blocked'],
        description: 'complete when the plan is done. blocked only when no plan is possible.'
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
    lines.push('A replan of a started run: the replan block says why.');
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

function describePlanProblem(planResult, resultSchema, facts, trunk, references) {
  const stopped = ', so ' + RUN_NAME + ' stopped.';
  if (!isPlainObject(planResult)) {
    return 'The planner returned no result' + stopped;
  }
  if (!validateSchema(resultSchema, planResult).ok) {
    return 'The planner returned a plan that does not fit the plan schema' + stopped;
  }
  if (planResult.outcome === 'blocked') {
    return 'The planner could not plan the delivery: ' + describeReason(planResult.blocker);
  }
  const plan = planResult.plan;
  const pathLocation = findRepositoryPathProblem(PLAN_SCHEMA, plan, '');
  if (pathLocation !== '') {
    return 'The plan names a path at ' + pathLocation + ' that is not a plain path inside the repository' + stopped;
  }
  const wave = computeWave(plan.steps, []);
  if (!wave.ok) {
    return 'The plan steps cannot be scheduled, so ' + RUN_NAME + ' stopped: ' + toPrintableAscii(wave.problem);
  }
  if (plan.trunk_freshness !== facts.trunk_freshness) {
    return 'The plan copies a trunk freshness other than the facts' + stopped;
  }
  if (!isGitIdentifier(plan.branch) || !isGitIdentifier(plan.base)) {
    return 'The plan names a branch or base that is not a safe git name' + stopped;
  }
  if (!plan.versioning.artifact_files.every((artifactPath) => isGitIdentifier(artifactPath))) {
    return 'The plan names a version file path that is not a safe git path' + stopped;
  }
  for (let index = 0; index < plan.validation_commands.length; index += 1) {
    const commandProblem = describeValidationCommandProblem(plan.validation_commands[index]);
    if (commandProblem !== '') {
      return 'The plan names a validation command at validation_commands[' + index + '] that ' + commandProblem + stopped;
    }
  }
  if (typedTitlePattern().test(cleanTitleText(plan.title))) {
    return 'The plan title starts with a commit type, which the workflow writes before it' + stopped;
  }
  if (buildTitleText(plan) === '') {
    return 'The plan title leaves no text once it is cleaned and cut to fit the pull request title' + stopped;
  }
  const isOnOtherBranch = facts.head_state === 'branch' && facts.branch !== trunk;
  if (isOnOtherBranch && plan.branch !== facts.branch) {
    return describeStartBranch(facts) + ' and delivers on it, but the plan names branch ' + encodeUntrustedText(plan.branch) + stopped;
  }
  if (!new RegExp(PLAN_SCHEMA.properties.branch.pattern, 'u').test(plan.branch)) {
    return 'The plan names branch ' + encodeUntrustedText(plan.branch) + describeTaxonomyMiss() + stopped;
  }
  return describeClosesProblem(plan, references);
}

function describeStartBranch(facts) {
  return 'The run started on branch ' + encodeUntrustedText(facts.branch);
}

/**
 * Returns the clause that says a branch named before it is outside the
 * Branch Taxonomy.
 */
function describeTaxonomyMiss() {
  return ', which is not a prefix of feature, bugfix, hotfix, refactor, chore, docs, test or ci, a slash and lowercase words joined by hyphens';
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
 * Returns the lead of a planning pause: one line of the encoded branch, the
 * step count, the distinct plan path count and digest.change through
 * renderText.
 */
function describePlanLine(plan) {
  return 'The plan for branch ' + encodeUntrustedText(plan.branch) + ' has ' + describeCount(plan.steps.length, 'step') + ' over ' + describeCount(listPlanPaths(plan).length, 'file') + ': ' + renderText(plan.digest.change);
}

/**
 * Returns the one text every code-built brief puts in the fields no
 * message shows (lib/brief.js): steel_man, straw_man,
 * criticality.if_ignored and each assumption's statement and evidence.
 */
function unshownBriefText() {
  return 'Not shown.';
}

function resolveDecision(kind, brief, scope, run, resolution, listed) {
  const decision = decide({ kind: kind, level: run.level, brief: brief, listed: listed }, AUTONOMY_TABLE, BRIEF_SCHEMA);
  if (decision.action === 'take') {
    resolution.taken.push({ brief: brief, kind: kind, listed: decision.listed });
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
  const outsidePaths = listOutsidePaths(plan, scope);
  const holds = { outside_limits: outsidePaths.length > 0, repeats_surface: plan.remediation_gate.repeats_surface };
  const listed = Object.keys(holds).filter((name) => holds[name]);
  const brief = isRemediation ? buildRemediationPlanBrief(plan) : buildPlanAcceptanceBrief(plan);
  return resolveDecision(isRemediation ? REMEDIATION_PLAN_ACCEPTANCE_KIND : PLAN_ACCEPTANCE_KIND, markOutsideLimits(brief, outsidePaths), [run.pass, plan], run, resolution, listed);
}

function resolvePlanAsks(planResult, facts, run, scope) {
  const resolution = { asks: [], taken: [], freshness: undefined, reversibleEffects: [] };
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

function logPlanningReply(run, shownEntry, shownAsks, revise) {
  run.answerLog.push(buildAnswerEntry(shownEntry, revise));
  run.approvals = applyApprovalChoices(run.approvals, shownAsks, readReplyChoices(shownEntry.reply, shownAsks));
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
  if (facts.head_state === 'branch' && facts.branch !== run.trunk && !new RegExp(PLAN_SCHEMA.properties.branch.pattern, 'u').test(facts.branch)) {
    return stopDelivery([{ problem: describeStartBranch(facts) + describeTaxonomyMiss() + '.' }], run, [], true);
  }
  let checked = await callCheckedPlanner(run, facts, { prompt: buildPlanPrompt(run.request, facts, scope, replan, listAnswerEntries(run)), label: 'plan-' + run.pass, phaseTitle: 'Plan', schema: resultSchema });
  for (;;) {
    let { planResult, problem } = checked;
    if (problem !== undefined) {
      if (shownAsks.length > 0) {
        logPlanningReply(run, shownEntry, shownAsks);
      }
      const unusable = planResult === null ? describeUnusableResult(problem, null) : { problem: problem };
      return stopDelivery([checked.isExhausted ? describeCheckLimit(problem) : unusable], run, [], true);
    }
    if (shownAsks.length > 0) {
      logPlanningReply(run, shownEntry, shownAsks, planResult);
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
      return stopDelivery([{ problem: 'Workflow defect: the ' + resettled.kind + ' question came back after a reply settled it, so ' + RUN_NAME + ' stopped.', terminal: true, nextAction: 'report' }], run, [], true);
    }
    const lead = describePlanLine(planResult.plan);
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
    const revisePrompt = buildPlanRevisePrompt({ request: run.request, facts: facts, scope: scope, answers: listAnswerEntries(run), plan: planResult.plan, questions: questions, reply: reply });
    checked = await callCheckedPlanner(run, facts, { prompt: revisePrompt, label: 'revise-' + round, phaseTitle: 'Revise', schema: resultSchema });
  }
}
