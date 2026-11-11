/*
 * briefs.js: the code-built decision briefs a workflow shares. It holds the
 * plan acceptance, remediation plan acceptance, trunk and effect briefs of
 * a planning pass, the outside-limit check of a plan acceptance, and the
 * tail briefs of the gates. It builds briefs; lib/brief.js renders them
 * as the text the user reads and reads the replies.
 *
 * Inputs
 *   plan     the plan of the plan result the pass checked, from
 *            runPlanningPass (lib/plan.js).
 *   facts    the checked facts of the pass, from runFactsStep
 *            (lib/runner.js).
 *   scope    the checked scope of the pass, from runScopeStep (lib/scope.js).
 *   head, round and staleIds  the commit, fix round and stale gate ids
 *            of a gate decision (standard-delivery gates.js).
 *   values   the routing values of a version check whose version_check is
 *            undetermined or unreadable (standard-delivery gates.js).
 *   unshownBriefText and describeCount (lib/plan.js), isRepositoryPath and
 *   listPlanPaths (lib/paths.js), and the workflow functions gateNames and
 *   joinNames (standard-delivery gates.js), maxFixRounds (standard-delivery
 *   main.js) and buildUndecidedAsk (standard-delivery tails.js).
 *   The constants of the workflow's main.js this file reads:
 *   PLAN_ACCEPTANCE_KIND, REMEDIATION_PLAN_ACCEPTANCE_KIND, TRUNK_STALE_KIND,
 *   EXTERNAL_EFFECT_KIND, STEP_STOP_KIND, VERSION_BUMP_INDETERMINABLE_KIND,
 *   VALIDATION_REMEDIATION_KIND and GATE_RERUN_KIND, and the data constant
 *   BRIEF_SCHEMA. Every workflow whose code calls a function of this file
 *   declares those it reads.
 *
 * Outputs
 *   buildPlanAcceptanceBrief(plan), buildRemediationPlanBrief(plan),
 *   buildTrunkStaleBrief(facts) and buildExternalEffectBrief(summary)
 *            the briefs lib/plan.js resolves through decide(). The effect brief
 *            names no step: the step id lives only in the question key.
 *   listOutsidePaths(plan, scope)  the plan paths outside every limit of
 *            the scope, [] when it sets none. A version or changelog file
 *            the plan declares is never outside.
 *   markOutsideLimits(brief, outsidePaths)  the acceptance brief with the
 *            outside count added to its problem when a plan path is outside
 *            the limits and the problem still fits. It never changes the
 *            recommendation: its strength and why stay as built, and
 *            lib/plan.js passes listed outside_limits to decide().
 *   buildTailBrief({kind, problem, goOn, other, strength, why})  the
 *            shared shape of a tail brief, also used by standard-delivery
 *            review.js.
 *   buildBriefOption(id, summary, effort, value, reversible),
 *   buildUnshownCriticality(level, likelihood) and
 *   buildUnshownAssumptions(origin)  the option, criticality and
 *            assumptions of a code-built brief, also used by
 *            standard-delivery review.js.
 *   buildBriefGate(irreversible)  the gate of a code-built brief, never
 *            architectural or safety.
 *   buildValidationRemediationBrief, buildFixLimitBrief and
 *   buildGateRerunBrief  the tail briefs standard-delivery gates.js
 *            resolves.
 *   buildStepStopBrief(isReplan)  the fix_cause step_stop brief
 *            stopDelivery (standard-delivery record.js) asks. It has one option, strength
 *            strong, and its problem says to clear the cause named above
 *            and commit any change, then reply, and whether the reply takes
 *            the stopped step again or plans again from fresh facts. It is
 *            built through buildTailBrief with its option B left out.
 *   buildApprovalAsks(holds, isReplan, run)  the asks of an approve stop,
 *            one step_stop ask per held item {stepId, category, item}, in
 *            hold order. Its shown brief names the encoded step in its
 *            problem; option A, Approve this change, lists the encoded item
 *            with its category; option B keeps it as it is, and the reply
 *            plans again or takes the stopped step again without it;
 *            strength none. decide() reads a code-built copy with no step
 *            id and an unshown item, which fits BRIEF_SCHEMA whatever the
 *            hold holds. ask.items is [[{category, item}], []], so only
 *            the user's own reply choosing A approves the item as given.
 *   buildVersionQuestionBrief(values)  the version_bump_indeterminable
 *            brief the validate gate asks through buildUndecidedAsk
 *            (standard-delivery tails.js), strength none. For undetermined its options are a major, minor and
 *            patch bump and no bump, each naming the version it gives
 *            (raiseVersion) when trunk_version is known; for unreadable its
 *            problem names the formats the check reads, and its options
 *            keep the branch version or set the version the reply names.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this library into it, so a row can name a
 *   function of this library.
 *   The brief gate of a remediation plan acceptance is
 *   plan.remediation_gate.promotion_gate copied whole, with architectural
 *   also true when grows_surface is, and its problem names each flag that
 *   holds, so it asks then and is taken otherwise at the default level
 *   (decision-autonomy.md, Promotion Gate). repeats_surface only lists a
 *   taken acceptance: lib/plan.js passes it to decide() in listed.
 *   Every brief here puts unshownBriefText() in each field no message
 *   shows and fits BRIEF_SCHEMA with worst-case inputs (the workflow's
 *   main.js, bounded fields).
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
    criticality: buildUnshownCriticality(),
    options: [
      buildBriefOption('A', 'Accept the plan and run its steps.', 'medium'),
      buildBriefOption('B', 'Stop before any step runs.', 'trivial', 'low')
    ],
    recommendation: { option_id: 'A', strength: 'strong', why: 'Every change stays on the working branch, and every decision taken is listed for you before the merge.' },
    assumptions: buildUnshownAssumptions('assumed'),
    gate: buildBriefGate(),
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
    problem: flagTexts.length === 0 ? lead : lead + ' The plan ' + joinNames(flagTexts, 'and') + '.',
    recommendation: { ...brief.recommendation, why: 'The plan answers the local review findings, and every gate runs again on its commit before the pull request.' },
    gate: { ...remediationGate.promotion_gate, architectural: flags.architectural || flags.grows_surface }
  });
}

function buildTrunkStaleBrief(facts) {
  return {
    id: 'trunk',
    kind: TRUNK_STALE_KIND,
    problem: 'The trunk may not be up to date: its freshness is ' + facts.trunk_freshness + ', ' + Number(facts.trunk_ahead) + ' commits ahead of its remote and ' + Number(facts.trunk_behind) + ' behind. Create or confirm the working branch from it anyway?',
    criticality: buildUnshownCriticality('low', 'occasional'),
    options: [
      buildBriefOption('A', 'Go on from the trunk as it is.', 'trivial', 'medium'),
      buildBriefOption('B', 'Stop so you can bring the trunk up to date first.', 'small', 'medium')
    ],
    recommendation: { option_id: 'A', strength: 'strong', why: 'A stale base costs at most a rebase, and the run goes on.' },
    assumptions: buildUnshownAssumptions(),
    gate: buildBriefGate()
  };
}

function buildExternalEffectBrief(summary) {
  return {
    id: 'effect',
    kind: EXTERNAL_EFFECT_KIND,
    problem: 'A plan step has an effect outside the repo that cannot be undone. May the run go on to it?',
    criticality: buildUnshownCriticality('high'),
    options: [
      buildBriefOption('A', 'Go on and let the step make this effect.', 'small', 'high', false),
      buildBriefOption('B', 'Change or drop the step first.', 'small', 'medium')
    ],
    recommendation: { option_id: 'A', strength: 'none', why: 'Only you can decide whether this effect outside the repo may happen.' },
    assumptions: buildUnshownAssumptions('assumed'),
    gate: buildBriefGate(true),
    verbatim: summary
  };
}

/**
 * Returns the plan paths (listPlanPaths) outside every limit of the scope,
 * or [] when the scope sets no limit. A path is inside a limit when it
 * equals the limit path or sits under it plus '/'. A path in
 * versioning.artifact_files or versioning.changelog_files is never outside.
 * A limit that fails isRepositoryPath matches no path.
 */
function listOutsidePaths(plan, scope) {
  if (scope.limits.length === 0) {
    return [];
  }
  const limits = scope.limits.map((limit) => limit.path).filter((limit) => isRepositoryPath(limit));
  const versionFiles = [...plan.versioning.artifact_files, ...plan.versioning.changelog_files];
  const isInsideLimits = (file) => versionFiles.includes(file) || limits.some((limit) => file === limit || file.startsWith(limit + '/'));
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
   * set.
   */
  return Object.assign(brief, { problem: problem.length <= BRIEF_SCHEMA.properties.problem.maxLength ? problem : brief.problem });
}

function buildTailBrief({ kind, problem, goOn, other = 'Plan again: this run gives your reply to the planner before anything goes further.', strength, why }) {
  return {
    id: 'tail',
    kind: kind,
    problem: problem,
    criticality: buildUnshownCriticality(),
    options: [
      buildBriefOption('A', goOn),
      buildBriefOption('B', other, 'trivial', 'low')
    ],
    recommendation: { option_id: strength === 'none' ? 'B' : 'A', strength: strength, why: why },
    assumptions: buildUnshownAssumptions(),
    gate: buildBriefGate()
  };
}

function describeStopThen(isReplan) {
  return isReplan ? 'the run plans again from fresh facts' : 'the run takes the stopped step again';
}

function buildStepStopBrief(isReplan) {
  const action = describeStopAction('fix_cause', 'commit any change and reply');
  const brief = buildTailBrief({
    kind: STEP_STOP_KIND,
    problem: action.charAt(0).toUpperCase() + action.slice(1) + ', and ' + describeStopThen(isReplan) + '.',
    goOn: isReplan ? 'Go on: plan again from fresh facts.' : 'Go on: take the stopped step again.',
    strength: 'strong',
    why: 'Clearing it lets the step go on.'
  });
  return Object.assign(brief, { options: brief.options.slice(0, 1) });
}

function buildApprovalBrief(stepText, change, isReplan) {
  const brief = buildTailBrief({
    kind: STEP_STOP_KIND,
    problem: stepText + describeGateWait() + '.',
    goOn: 'Approve this change.',
    other: 'Keep it as it is, and ' + describeStopThen(isReplan) + ' without it.',
    strength: 'none',
    why: 'Only you can approve a change the destructive-fix gate holds back.'
  });
  brief.options[0].destructive = [change];
  return brief;
}

function buildApprovalAsk(hold, isReplan, run) {
  const ask = buildUndecidedAsk(STEP_STOP_KIND, buildApprovalBrief('A step', { category: hold.category, item: unshownBriefText() }, isReplan), run);
  const shown = buildApprovalBrief('Step ' + encodeUntrustedText(hold.stepId), { category: hold.category, item: encodeUntrustedText(hold.item) }, isReplan);
  return { ...ask, brief: shown, items: [[{ category: hold.category, item: hold.item }], []] };
}

function buildApprovalAsks(holds, isReplan, run) {
  return holds.map((hold) => buildApprovalAsk(hold, isReplan, run));
}

function raiseVersion(version, bumpType) {
  const parts = version.split('.').map(Number);
  const raised = { major: [parts[0] + 1, 0, 0], minor: [parts[0], parts[1] + 1, 0], patch: [parts[0], parts[1], parts[2] + 1] };
  return raised[bumpType].join('.');
}

/**
 * Returns the criticality of a code-built brief, of level and likelihood,
 * with unshownBriefText() in its blast_radius and if_ignored.
 */
function buildUnshownCriticality(level = 'medium', likelihood = 'certain') {
  return { level: level, likelihood: likelihood, blast_radius: unshownBriefText(), if_ignored: unshownBriefText() };
}

/**
 * Returns the gate of a code-built brief: irreversible as given, never
 * architectural or safety.
 */
function buildBriefGate(irreversible = false) {
  return { irreversible: irreversible, architectural: false, safety: false };
}

/**
 * Returns the one assumption of a code-built brief, of origin, with
 * unshownBriefText() in its statement and evidence.
 */
function buildUnshownAssumptions(origin = 'repo') {
  return [{ statement: unshownBriefText(), origin: origin, evidence: unshownBriefText() }];
}

/**
 * Returns a brief option of id and summary with unshownBriefText() in its
 * unshown fields and beyond_request false.
 */
function buildBriefOption(id, summary, effort = 'small', value = 'high', reversible = true) {
  return { id: id, summary: summary, steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: effort, value: value, reversible: reversible, beyond_request: false };
}

function listVersionOptions(values) {
  if (values.version_check === 'unreadable') {
    return [buildBriefOption('A', 'Keep the version each file holds on the branch.'), buildBriefOption('B', 'Set the version your reply names in each file.')];
  }
  const trunk = values.trunk_version;
  const bumpOptions = [['A', 'major'], ['B', 'minor'], ['C', 'patch']].map(([id, bumpType]) => buildBriefOption(id, 'Make a ' + bumpType + ' version bump' + (trunk === undefined ? '.' : ', to version ' + raiseVersion(trunk, bumpType) + '.')));
  return bumpOptions.concat(buildBriefOption('D', 'Make no version bump' + (trunk === undefined ? '.' : ', keeping version ' + trunk + '.')));
}

function buildVersionQuestionBrief(values) {
  const isUnreadable = values.version_check === 'unreadable';
  return {
    id: 'version',
    kind: VERSION_BUMP_INDETERMINABLE_KIND,
    problem: isUnreadable
      ? 'The version check cannot read one version from the version files. It reads the top-level version string of a .json file, the one version = "X.Y.Z" line of a .toml file and any other file whole, each a plain X.Y.Z version, the same at the trunk. Which version should they hold?'
      : 'The version bump cannot be told from the commits on the branch and the plan answers on versioning. Which version bump does the delivery need?',
    criticality: buildUnshownCriticality(),
    options: listVersionOptions(values),
    recommendation: { option_id: 'A', strength: 'none', why: 'Only you can decide the version of this delivery.' },
    assumptions: buildUnshownAssumptions(),
    gate: buildBriefGate()
  };
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

function buildGateRerunBrief(staleIds, head) {
  const names = joinNames(staleIds.map((gateId) => gateNames()[gateId]), 'and');
  return buildTailBrief({
    kind: GATE_RERUN_KIND,
    problem: 'Commit ' + head + ' landed after ' + names + ' held on an earlier commit. Run ' + names + ' again on the new commit?',
    goOn: 'Run the checks again on the new commit.',
    strength: 'strong',
    why: 'A check holds only for the commit it ran on, and the pull request needs every check to hold on the commit it pushes.'
  });
}
