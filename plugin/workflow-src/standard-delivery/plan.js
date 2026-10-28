/*
 * standard-delivery plan.js: the planning pass of the standard-delivery
 * workflow. It holds the plan result and revise schemas, the path checks
 * of plan values, the plan and revise prompts, the plan check, the plan
 * briefs and the resolution of every decision of a planning pass.
 *
 * Inputs
 *   run     the run state of main.js createRunState. The pass reads
 *           request, trunk, level, pass, storedAnswers and pendingReply,
 *           and updates answerLog, answeredKeys, taken, reversibleEffects
 *           and acceptedPaths.
 *   facts   the checked facts of the pass, from runFactsStep (relay.js).
 *   scope   the checked scope of the pass, from runScopeStep (scope.js).
 *           After a reply round whose revise result passes the plan check,
 *           unless the reply settled the shown plan acceptance and the shown
 *           result was restored, the pass scopes again with
 *           runScopeStep(run, facts, round), label scope-P-R. That scope
 *           replaces the pass scope for the acceptance check and every later
 *           revise prompt of the pass, and its problem stops the run blocked
 *           as a pass-start scope problem does.
 *   replan  undefined at launch, else the replan data of the step that
 *           sent the run back to planning: its reason, and the review when
 *           it carries one.
 *   PLAN_SCHEMA, BRIEF_SCHEMA, AUTONOMY_TABLE and the kind constants of
 *   main.js.
 *
 * Outputs
 *   runPlanningPass(run, facts, scope, replan)  {plan, freshness} once every
 *           question of the pass is settled or taken, else {result}: the
 *           pause of an open question or a blocked finish.
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
 *   remediation_plan_acceptance. Its brief gate is
 *   plan.remediation_gate.promotion_gate copied whole, with architectural
 *   also true when grows_surface or repeats_surface is, and its problem
 *   names each flag that holds, so it asks then and is taken otherwise at
 *   the default level (decision-autonomy.md, Promotion Gate).
 *   Every decision resolves through decide() with its kind fixed here,
 *   never from brief.kind. Every question of a plan pass is keyed through
 *   questionKey by its kind, a scope its call site passes and the question
 *   rendered alone by renderQuestions, so the key holds every value the user
 *   saw and no hand-picked subset of brief or plan fields (issue 433,
 *   review findings 7578f16f and 0c804e49). The scope is the pass for a
 *   planner question, the pass and the whole plan for both plan
 *   acceptances, and 'run' for trunk_stale and an irreversible effect,
 *   whose rendered text holds the trunk facts, or the step id and exact
 *   summary, so a changed irreversible text is a new question the user must
 *   approve word for word. A tail decision has no scope and no key. A plan
 *   acceptance ask waits while any other ask of its round is open, so the
 *   user accepts the plan that holds no open question. When a reply settles
 *   the shown acceptance, the plan result that was shown is the one that
 *   runs, and a revise that only rewrites the summary to record the answer
 *   does not ask again (issue 433). The residual: a planner question raised
 *   again with other rendered text, a changed recommendation too, is a new
 *   question, asked again in the next pause. The planner's revise pass
 *   reads the reply. The
 *   revise result names in settled, by label like Q1, the shown questions the
 *   reply settled: only the keys of those count as answered and are not
 *   asked again, and every other question resolves again and goes in the
 *   next pause. Which shown questions a reply settles is the planner's
 *   judgment, as its gate flags are (ADR-0037 decision 3). The impact is
 *   bounded: a question the planner does not name is asked again, the
 *   settled enum allows only the labels shown, and nothing runs while a
 *   question is open. Rejected: a free-text reply has no code parse, and a
 *   pause per effect adds stops (review finding d5619285, option C).
 *   Every plan value at a field whose PLAN_SCHEMA description starts with
 *   repositoryPathMark() must pass isRepositoryPath (review finding
 *   461fe942). findRepositoryPathProblem walks the schema for the mark, so
 *   a new path field is checked once it carries the mark, and
 *   describePlanProblem runs it after the schema check and before
 *   computeWave, so a bad path stops the run before the branch step and
 *   any later agent call. The rule is the files rule of molt.sh, its home,
 *   and a parity test runs one corpus through both and requires the same
 *   verdicts, so a change lands in both. The check is lexical, so a
 *   symlinked path or one that names a directory is left to molt.sh. Fix
 *   round files are not plan fields: they reach only molt.sh, which
 *   applies the same rule before any change. The user rejected local
 *   review finding c2e0ada3, which asked for a check of fix round files
 *   members in the workflow, on this basis (ADR-0037, Amendment
 *   2026-10-25). isGitIdentifier stays on
 *   artifact_files for the git show splice in the bump prompt, since the
 *   path rule allows spaces, shell characters and a leading '-'.
 *   Each validation_commands entry is one command line: describePlanProblem
 *   refuses a blank entry, or one that holds a line break or another
 *   control character, naming the reason, before the branch step.
 *   Settled question guard: within one pass, a trunk_stale question a
 *   reply settled renders the same text for the whole run, and a settled
 *   plan_acceptance or remediation_plan_acceptance restores the plan result
 *   that was shown, so its key holds and it is never asked again. When a
 *   pause round would still show one, that is a workflow defect: the run
 *   does not pause, and finishes blocked naming the question kind. An
 *   irreversible effect whose text changed, and a planner question that
 *   renders other text, are new questions and pause again.
 *   An irreversible effect is asked as an exact entry, so the pause keeps
 *   its exact text whole in every fit tier (lib/result.js whole blocks): the
 *   user never answers an effect question without its verbatim text.
 *   The plan and revise prompts carry the scope in a scope data block right
 *   after the request block, and no other planning text holds it.
 *   Each reply a plan pause consumes goes once into run.answerLog as
 *   {question, reply}, the question being the text the pause showed. Every
 *   plan prompt once the log is not empty carries the whole log in an
 *   answers data block, and a revise prompt carries the entries before its
 *   own round, so a replan never asks or reverses a settled answer (issue
 *   472). With an empty log, the plan and first revise prompts are the
 *   prompts of a run with no answers, so a resume replays them from cache.
 *   Outside-limit ask: when scope.limits is not empty, a plan step file
 *   that neither equals a limit nor sits under limit + '/', and is not in
 *   run.acceptedPaths, makes the plan or remediation plan acceptance brief
 *   recommendation strength none, so decide() asks it no_recommendation at
 *   every level. Its problem names their count when it fits, and the detail
 *   block lists up to 5 of them, then the count of the rest. Empty limits
 *   leave the brief as it was. The outside paths of an acceptance that
 *   resolves answered join run.acceptedPaths in acceptResolution, after
 *   resolution, so a restored settled acceptance renders as shown and its
 *   key holds.
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
    items: { type: 'string', enum: shownAsks.map((ask, index) => questionLabel(index)) }
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

function findRepositoryPathProblem(schema, value, location) {
  const isMarked = typeof schema.description === 'string' && schema.description.startsWith(repositoryPathMark());
  if (isMarked && !isRepositoryPath(value)) {
    return location;
  }
  if (schema.properties !== undefined && isPlainObject(value)) {
    const presentNames = Object.keys(schema.properties).filter((name) => Object.prototype.hasOwnProperty.call(value, name));
    for (const name of presentNames) {
      const childProblem = findRepositoryPathProblem(schema.properties[name], value[name], location === '' ? name : location + '.' + name);
      if (childProblem !== '') {
        return childProblem;
      }
    }
  }
  if (schema.items !== undefined && Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      const itemProblem = findRepositoryPathProblem(schema.items, value[index], location + '[' + index + ']');
      if (itemProblem !== '') {
        return itemProblem;
      }
    }
  }
  return '';
}

function settledAnswersSentence(home) {
  return dataBlocksSentence(undefined) + ' ' + home + ' hold the user\'s settled decisions: never ask them again, never reverse them.';
}

function buildPlanPrompt(request, facts, scope, replan, answerLog) {
  const hasAnswers = answerLog.length > 0;
  const lines = [
    'Plan the delivery of the user request below in this repository, as one plan on one working branch.',
    boundarySentence(),
    hasAnswers ? settledAnswersSentence('The entries of the answers block') : dataBlocksSentence(undefined)
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
    hasAnswers ? settledAnswersSentence('The answers and reply blocks') : dataBlocksSentence('The reply block'),
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
  return undefined;
}

/**
 * Returns the key a question counts as answered under: its kind and its
 * content, which resolveDecision builds from the call site scope and the
 * question as renderQuestions shows it alone. A question the user saw
 * settled is not asked again after a revise that shows it the same way
 * (issue 433).
 */
function questionKey(kind, content) {
  return JSON.stringify([kind, content]);
}

function describeCount(count, noun) {
  return count + ' ' + noun + (count === 1 ? '' : 's');
}

function toOneLine(text) {
  return text.trim().split(/\s*[\r\n]+\s*/).join(' ');
}

function listShownPaths(files) {
  const shownPaths = files.slice(0, 5).map((file) => encodeUntrustedText(cutExcerpt(file)));
  const restCount = files.length - shownPaths.length;
  return joinNames(restCount > 0 ? [...shownPaths, restCount + ' more'] : shownPaths, 'and');
}

function buildPlanDetailBlock(plan, outsidePaths) {
  const files = listStepFiles(plan.steps);
  const lines = [
    'What the plan addresses: ' + toOneLine(plan.digest.problem),
    'What it changes: ' + toOneLine(plan.digest.change),
    'It has ' + describeCount(plan.steps.length, 'step') + ' and touches ' + describeCount(files.length, 'file') + ' on branch ' + encodeUntrustedText(cutExcerpt(plan.branch)) + ': ' + listShownPaths(files) + '.'
  ];
  if (outsidePaths.length > 0) {
    lines.push('Outside the limits you set: ' + listShownPaths(outsidePaths) + '.');
  }
  return { text: lines.join('\n') };
}

/**
 * Returns the plan step files outside every limit of the scope that no
 * accepted plan acceptance of the run already covers, or [] when the scope
 * sets no limit. A file is inside a limit when it equals the limit or sits
 * under limit + '/'. A limit that fails isRepositoryPath matches no file.
 */
function listOutsidePaths(plan, scope, run) {
  if (scope.limits.length === 0) {
    return [];
  }
  const limits = scope.limits.filter((limit) => isRepositoryPath(limit));
  const isInsideLimits = (file) => limits.some((limit) => file === limit || file.startsWith(limit + '/'));
  return listStepFiles(plan.steps).filter((file) => !isInsideLimits(file) && !run.acceptedPaths.includes(file));
}

function markOutsideLimits(brief, outsidePaths) {
  if (outsidePaths.length === 0) {
    return brief;
  }
  const problem = brief.problem + ' It changes ' + describeCount(outsidePaths.length, 'file') + ' outside the limits you set.';
  /*
   * INVARIANT: the problem names the count only when it fits the brief
   * problem maxLength, so the brief stays valid with every remediation flag
   * set. The detail block of the pause names the outside paths and their
   * count in every case.
   */
  return Object.assign(brief, {
    problem: problem.length <= BRIEF_SCHEMA.properties.problem.maxLength ? problem : brief.problem,
    recommendation: { ...brief.recommendation, strength: 'none', why: 'Only you can say if the plan may change files outside the limits.' }
  });
}

function remediationGateTexts() {
  return {
    irreversible: 'cannot be undone',
    architectural: 'changes how the system is built',
    safety: 'touches a safety check',
    grows_surface: 'adds more surface than it removes',
    repeats_surface: 'repeats a fix that did not close its class'
  };
}

/**
 * Returns the one text every code-built brief puts in the fields no
 * message shows (lib/brief.js): steel_man, straw_man,
 * criticality.if_ignored and each assumption's statement and evidence.
 */
function unshownBriefText() {
  return 'Not shown.';
}

function buildPlanAcceptanceBrief(plan) {
  return {
    id: 'plan',
    kind: PLAN_ACCEPTANCE_KIND,
    problem: 'Start delivering the plan: create or confirm its working branch and run its steps.',
    criticality: { level: 'medium', likelihood: 'certain', blast_radius: 'The working branch and the files the plan steps list.', if_ignored: unshownBriefText() },
    options: [
      { id: 'A', summary: 'Accept the plan and run its steps.', steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: 'medium', value: 'high', reversible: true },
      { id: 'B', summary: 'Stop before any step runs.', steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: 'trivial', value: 'low', reversible: true }
    ],
    recommendation: { option_id: 'A', strength: 'strong', why: 'Every change stays on the working branch, and every decision taken is listed for you before the merge.' },
    assumptions: [{ statement: unshownBriefText(), origin: 'assumed', evidence: unshownBriefText() }],
    gate: { irreversible: false, architectural: false, safety: false },
    verbatim: plan.summary
  };
}

function buildRemediationPlanBrief(plan) {
  const remediationGate = plan.remediation_gate;
  const flags = { ...remediationGate.promotion_gate, grows_surface: remediationGate.grows_surface, repeats_surface: remediationGate.repeats_surface };
  const texts = remediationGateTexts();
  const flagTexts = Object.keys(texts).filter((flag) => flags[flag]).map((flag) => texts[flag]);
  const lead = 'Run the remediation plan for the local review findings on the working branch, then every gate again.';
  const brief = buildPlanAcceptanceBrief(plan);
  return Object.assign(brief, {
    kind: REMEDIATION_PLAN_ACCEPTANCE_KIND,
    problem: flagTexts.length === 0 ? lead : lead + ' I am asking because the plan ' + joinNames(flagTexts, 'and') + '.',
    recommendation: { ...brief.recommendation, why: 'The plan answers the local review findings, and every gate runs again on its commit before the pull request.' },
    gate: { ...remediationGate.promotion_gate, architectural: flags.architectural || flags.grows_surface || flags.repeats_surface }
  });
}

function buildTrunkStaleBrief(facts) {
  return {
    id: 'trunk',
    kind: TRUNK_STALE_KIND,
    problem: 'The trunk may not be up to date: its freshness is ' + facts.trunk_freshness + ', ' + Number(facts.trunk_ahead) + ' commits ahead of its remote and ' + Number(facts.trunk_behind) + ' behind. Create or confirm the working branch from it anyway?',
    criticality: { level: 'low', likelihood: 'occasional', blast_radius: 'The base of the working branch.', if_ignored: unshownBriefText() },
    options: [
      { id: 'A', summary: 'Go on from the trunk as it is.', steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: 'trivial', value: 'medium', reversible: true },
      { id: 'B', summary: 'Stop so you can bring the trunk up to date first.', steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: 'small', value: 'medium', reversible: true }
    ],
    recommendation: { option_id: 'A', strength: 'strong', why: 'A stale base costs at most a rebase, and the run goes on.' },
    assumptions: [{ statement: unshownBriefText(), origin: 'repo', evidence: unshownBriefText() }],
    gate: { irreversible: false, architectural: false, safety: false }
  };
}

function buildExternalEffectBrief(stepId, summary) {
  return {
    id: 'effect',
    kind: EXTERNAL_EFFECT_KIND,
    problem: 'Plan step ' + encodeUntrustedText(Array.from(stepId).slice(0, 16).join('')) + ' has an effect outside the repo that cannot be undone. May the run go on to it?',
    criticality: { level: 'high', likelihood: 'certain', blast_radius: 'Something outside the repo, which no branch change can undo.', if_ignored: unshownBriefText() },
    options: [
      { id: 'A', summary: 'Go on and let the step make this effect.', steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: 'small', value: 'high', reversible: false },
      { id: 'B', summary: 'Change or drop the step first.', steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: 'small', value: 'medium', reversible: true }
    ],
    recommendation: { option_id: 'A', strength: 'none', why: 'Only you can decide whether this effect outside the repo may happen.' },
    assumptions: [{ statement: unshownBriefText(), origin: 'assumed', evidence: unshownBriefText() }],
    gate: { irreversible: true, architectural: false, safety: false },
    verbatim: summary
  };
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
    ask.key = questionKey(kind, [scope, renderQuestions([ask], [])]);
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
       * word for word, and two steps whose ids share the shown prefix are
       * two questions. The shown step id is cut for the message only, never
       * for the key.
       */
      resolveDecision(EXTERNAL_EFFECT_KIND, buildExternalEffectBrief(step.id, effect.summary), ['run', step.id], run, resolution);
    }
  }
}

function resolvePlanAcceptance(plan, run, resolution, scope) {
  const isRemediation = run.taken.some((entry) => entry.kind === PLANNER_ESCALATION_ROUTING_KIND || entry.kind === ROOT_CLUSTER_ROUTING_KIND);
  resolution.outsidePaths = listOutsidePaths(plan, scope, run);
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
  if (resolution.outsidePaths !== undefined) {
    run.acceptedPaths.push(...resolution.outsidePaths);
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
  const settledKinds = new Set();
  const planPrompt = buildPlanPrompt(run.request, facts, scope, replan, run.answerLog);
  let planResult = await agent(planPrompt, plannerCallOptions('plan-' + run.pass, 'Plan', resultSchema));
  for (;;) {
    const problem = describePlanProblem(planResult, resultSchema, facts, run.trunk);
    if (problem !== undefined) {
      return { result: finishDeliveryBlocked(problem, run) };
    }
    if (shownAsks.length > 0) {
      markSettledAsks(planResult.settled, shownAsks, run, settledKinds);
      if (shownAsks.some((ask) => [PLAN_ACCEPTANCE_KIND, REMEDIATION_PLAN_ACCEPTANCE_KIND].includes(ask.kind) && run.answeredKeys.has(ask.key))) {
        planResult = shownResult;
      } else {
        const rescoped = await runScopeStep(run, facts, run.answerLog.length);
        if (rescoped.problem !== undefined) {
          return { result: finishDeliveryBlocked(rescoped.problem, run) };
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
     * reply settled coming back in its pass is a workflow defect, so the
     * run ends blocked with no pause (issue 434).
     */
    const resettled = resolution.asks.find((ask) => settledKinds.has(ask.kind) && [PLAN_ACCEPTANCE_KIND, REMEDIATION_PLAN_ACCEPTANCE_KIND, TRUNK_STALE_KIND].includes(ask.kind));
    if (resettled !== undefined) {
      return { result: finishDeliveryBlocked('Workflow defect: the ' + resettled.kind + ' question came back after a reply settled it, so ' + RUN_NAME + ' stopped.', run) };
    }
    const questions = renderQuestions(resolution.asks, resolution.taken);
    const isAcceptance = resolution.asks.some((ask) => [PLAN_ACCEPTANCE_KIND, REMEDIATION_PLAN_ACCEPTANCE_KIND].includes(ask.kind));
    const detail = isAcceptance ? buildPlanDetailBlock(planResult.plan, resolution.outsidePaths) : undefined;
    const round = run.answerLog.length + 1;
    const reply = takeNextReply(run, round);
    if (reply === undefined) {
      return { result: pauseDelivery(resolution, questions, run, detail) };
    }
    run.answerLog.push({ question: detail === undefined ? questions : questions + '\n\n' + detail.text, reply: reply });
    phase('Revise');
    shownAsks = resolution.asks;
    shownResult = planResult;
    resultSchema = buildReviseResultSchema(shownAsks);
    const revisePrompt = buildPlanRevisePrompt({ request: run.request, facts: facts, scope: scope, answers: run.answerLog.slice(0, round - 1), plan: planResult.plan, questions: questions, reply: reply });
    planResult = await agent(revisePrompt, plannerCallOptions('revise-' + round, 'Revise', resultSchema));
  }
}
