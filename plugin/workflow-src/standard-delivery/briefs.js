/*
 * standard-delivery briefs.js: the code-built decision briefs of the
 * standard-delivery workflow. It holds the plan acceptance, remediation
 * plan acceptance, trunk and effect briefs of a planning pass, the
 * outside-limit check of a plan acceptance, and the tail briefs of the
 * gates.
 *
 * Inputs
 *   plan     the plan of the plan result the pass checked, from
 *            runPlanningPass (plan.js).
 *   facts    the checked facts of the pass, from runFactsStep (relay.js).
 *   scope    the checked scope of the pass, from runScopeStep (scope.js).
 *   values   the parsed routing values of a bump step (gates.js).
 *   head, round, staleIds and isLimit  the commit, fix round, stale gate
 *            ids and limit flag of a gate decision (gates.js).
 *   The kind constants of main.js, unshownBriefText, isRepositoryPath,
 *   listPlanPaths and describeCount (plan.js), and gateNames, joinNames,
 *   maxFixRounds and maxGateReruns.
 *
 * Outputs
 *   buildPlanAcceptanceBrief(plan), buildRemediationPlanBrief(plan),
 *   buildTrunkStaleBrief(facts) and buildExternalEffectBrief(summary)
 *            the briefs plan.js resolves through decide(). The effect brief
 *            names no step: the step id lives only in the question key.
 *   listOutsidePaths(plan, scope)  the plan paths outside every limit of
 *            the scope, [] when it sets none.
 *   markOutsideLimits(brief, outsidePaths)  the acceptance brief with
 *            recommendation strength none when a plan path is outside the
 *            limits.
 *   buildTailBrief({kind, problem, goOn, other, strength, why})  the
 *            shared shape of a tail brief, also used by review.js.
 *   buildBumpTypeBrief, buildBumpIndeterminableBrief,
 *   buildValidationRemediationBrief, buildFixLimitBrief and
 *   buildGateRerunBrief  the tail briefs gates.js resolves.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   The brief gate of a remediation plan acceptance is
 *   plan.remediation_gate.promotion_gate copied whole, with architectural
 *   also true when grows_surface or repeats_surface is, and its problem
 *   names each flag that holds, so it asks then and is taken otherwise at
 *   the default level (decision-autonomy.md, Promotion Gate).
 *   Every brief here puts unshownBriefText() in each field no message
 *   shows and fits BRIEF_SCHEMA with worst-case inputs (main.js, bounded
 *   fields).
 *
 * Why
 *   Each code-built brief is a fixed shape with a few computed fields, so
 *   keeping them apart from the steps that resolve them keeps those steps
 *   short.
 */

function remediationGateTexts() {
  return {
    irreversible: 'cannot be undone',
    architectural: 'changes how the system is built',
    safety: 'touches a safety check',
    grows_surface: 'adds more surface than it removes',
    repeats_surface: 'repeats a fix that did not close its class'
  };
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

function buildExternalEffectBrief(summary) {
  return {
    id: 'effect',
    kind: EXTERNAL_EFFECT_KIND,
    problem: 'A plan step has an effect outside the repo that cannot be undone. May the run go on to it?',
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

/**
 * Returns the plan paths (listPlanPaths) outside every limit of the scope,
 * or [] when the scope sets no limit. A path is inside a limit when it
 * equals the limit or sits under limit + '/'. A limit that fails
 * isRepositoryPath matches no path.
 */
function listOutsidePaths(plan, scope) {
  if (scope.limits.length === 0) {
    return [];
  }
  const limits = scope.limits.filter((limit) => isRepositoryPath(limit));
  const isInsideLimits = (file) => limits.some((limit) => file === limit || file.startsWith(limit + '/'));
  return listPlanPaths(plan).filter((file) => !isInsideLimits(file));
}

function markOutsideLimits(brief, outsidePaths) {
  if (outsidePaths.length === 0) {
    return brief;
  }
  const problem = brief.problem + ' It changes ' + describeCount(outsidePaths.length, 'file') + ' outside the limits you set.';
  /*
   * INVARIANT: the problem names the count only when it fits the brief
   * problem maxLength, so the brief stays valid with every remediation flag
   * set. The pause lead names the outside paths and their count in every
   * case.
   */
  return Object.assign(brief, {
    problem: problem.length <= BRIEF_SCHEMA.properties.problem.maxLength ? problem : brief.problem,
    recommendation: { ...brief.recommendation, strength: 'none', why: 'Only you can say if the plan may change files outside the limits.' }
  });
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
