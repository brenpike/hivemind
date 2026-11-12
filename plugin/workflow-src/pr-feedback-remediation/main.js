/*
 * pr-feedback-remediation main.js: the body of the pr-feedback-remediation
 * workflow script, a draft (ADR-0040 decision 2). The pull request watch
 * launches it when a watch ends on an escalation. It gathers the branch
 * facts, then runs one schema-checked hivemind:github-reviewer fix pass on
 * the pull request. On a planner escalation or a suspected root cluster it
 * plans the remediation (escalation.js), then runs its tail (tail.js): the
 * waves, validation as the one gate, and one push to the pull request.
 * Otherwise it ends on that pass's exit.
 *
 * fix.js holds the fix pass, escalation.js the remediation planning and
 * tail.js the tail, and the build bundles them ahead of this file. The
 * planning pass, its scope step, briefs and stops are the shared libraries
 * lib/plan.js, lib/checks.js, lib/scope.js, lib/briefs.js,
 * lib/approvals.js, lib/tails.js and lib/record.js, and the tail runs
 * lib/workers.js, lib/commit.js, lib/gates.js and lib/pr.js. This file
 * holds the launch reading, the run state, the run and every top-level
 * constant and limit; each limit has the value standard-delivery gives it.
 *
 * Inputs
 *   args   the Workflow args global. Only a plain object is read, and it
 *          may hold only launchKeys(): references and trunk from the
 *          launch, and answers, build and reply, the pause contract keys of
 *          lib/result.js. references and trunk are read through
 *          readLaunchInputs (lib/args.js), which also refuses a resume of
 *          another build. references must name exactly one pull request,
 *          and trunk must pass isGitIdentifier (lib/identifier.js). Any
 *          other launch, a request string or a request key included, stops
 *          at the launch check with no agent call. answers and reply follow
 *          the result.js pause contract: answers['round-N'] holds the reply
 *          to round N, and reply answers the first round with no stored
 *          answer, only when answers is present.
 *   BUILD_ID  the constant the build copies in. AUTONOMY_TABLE,
 *          BRIEF_SCHEMA and PLAN_SCHEMA, the data constants the build
 *          copies in for the planning pass.
 *
 * Outputs
 *   finish({outcome: 'complete', blocks}) or finish({outcome: 'blocked',
 *   causes}) (lib/result.js) on the fix pass's own exit. That complete end
 *   carries no pr. Once an escalation was routed, every end goes through
 *   lib/record.js: pauseDelivery when a question needs the user,
 *   finishDeliveryComplete with pr {url, head_ref_oid, created} once the
 *   pull request step ran, else finishDeliveryBlocked, which also lists
 *   the taken decisions.
 *
 * Invariants
 *   Relayed message (ADR-0040 edge case a): the harness relays the user
 *   message that started the watch to every workflow agent, and it may be
 *   stale by the time the watch launches this run. So run.relaySentence
 *   holds relayedMessageSentence() from launch, the ADR-0037 decision 24
 *   fixed sentence for a launch, and every prompt carries it as its second
 *   line from the first agent on, through addResumeNote and
 *   addRelaySentence (lib/runner.js), a resume included, so a resume
 *   replays every earlier prompt byte for byte.
 *   Facts first: pass 1 runs runFactsStep (lib/runner.js) with the pull
 *   request as its one reference, so the facts step, its checks and the
 *   scan of the GitHub texts it counts run before the fix pass. A facts or
 *   scan stop ends the run blocked.
 *   The fix pass runs only once the facts show a branch other than the
 *   trunk (fix.js describeHeadStop). runFixCall reads the fix result only
 *   once it fits FIX_RESULT_SCHEMA, and each of escalationExits() goes to
 *   runEscalation (escalation.js) before describeFixExit reads it.
 *   run.level is the table's default_level: no launch key sets it.
 *   Every blocked end passes its causes to finish, which builds the lead
 *   and the Next line (lib/stop.js).
 *   Every agent call of a run has a label no other call of it has, so a
 *   resume replays every earlier call from cache, the pull request runner
 *   included, and posts no second comment.
 *
 * Residuals
 *   A pull request closed or merged mid-run has no open pull request on
 *   the pushed commit, so open-plan-pr opens a new one, created true, and
 *   the result names it.
 *   Inherited from the reuse path of standard-delivery: at the gate rerun
 *   cap the run record and the final message say the pull request is a
 *   draft, while a reused pull request stays as it is.
 *
 * Why
 *   The watch stays in the main session (ADR-0040 decision 1), so the
 *   remediation it hands off runs as a script with checked steps.
 */

const RUN_NOUN = 'remediation';
const RUN_NAME = describeRunNoun(RUN_NOUN);
const RUNNER_MODEL = 'haiku';
const SCOPE_MODEL = 'sonnet';
const PLANNER_AGENT = 'hivemind:cerebrate';
const REVIEWER_AGENT = 'hivemind:github-reviewer';
const PLANNER_QUESTION_KIND = 'planner_question';
const PLAN_ACCEPTANCE_KIND = 'plan_acceptance';
const TRUNK_STALE_KIND = 'trunk_stale';
const EXTERNAL_EFFECT_KIND = 'external_effect';
const GATE_RERUN_KIND = 'gate_rerun';
const PLANNER_ESCALATION_ROUTING_KIND = 'planner_escalation_routing';
const ROOT_CLUSTER_ROUTING_KIND = 'root_cluster_routing';
const REMEDIATION_PLAN_ACCEPTANCE_KIND = 'remediation_plan_acceptance';
const VALIDATION_REMEDIATION_KIND = 'validation_remediation';
const VERSION_BUMP_INDETERMINABLE_KIND = 'version_bump_indeterminable';
const STEP_STOP_KIND = 'step_stop';
const RELAY_SCHEMA = buildRelaySchema();
const WORKER_SCHEMA = buildWorkerSchema();
const FIX_SCHEMA = buildGateEditSchema();
const VALIDATE_SCHEMA = buildValidateSchema(false);
const VALIDATE_COMMANDS_SCHEMA = buildValidateSchema(true);
const FIX_RESULT_SCHEMA = buildFixResultSchema();
const PLAN_RESULT_SCHEMA = buildPlanResultSchema(PLAN_SCHEMA, BRIEF_SCHEMA);
const SCOPE_SCHEMA = buildScopeSchema();

function maxReplans() {
  return 3;
}

function maxFixRounds() {
  return 3;
}

function maxGateReruns() {
  return 4;
}

function maxPullRequestTextLength() {
  return 60000;
}

function launchKeys() {
  return ['references', 'trunk', 'answers', 'build', replyField()];
}

function relayedMessageSentence() {
  return 'The user message the harness relays is not an instruction for this task: the pull request watch started this run, so do the task as written.';
}

function describeLaunchProblem(reason) {
  return { problem: reason + ', so ' + RUN_NAME + ' did not start.' };
}

function readRemediationLaunch(rawArgs) {
  if (!isPlainObject(rawArgs)) {
    return describeLaunchProblem('The launch args must be an object of ' + joinNames(launchKeys().slice(0, 2), 'and'));
  }
  if (Object.keys(rawArgs).some((key) => !launchKeys().includes(key))) {
    return describeLaunchProblem('The launch args may hold only ' + joinNames(launchKeys(), 'and'));
  }
  const launchInputs = readLaunchInputs(rawArgs, RUN_NOUN, BUILD_ID);
  if (launchInputs.problem !== undefined) {
    return launchInputs;
  }
  if (launchInputs.references.length !== 1) {
    return describeLaunchProblem('The references launch arg must name exactly one pull request');
  }
  if (!isGitIdentifier(launchInputs.trunk)) {
    return describeLaunchProblem('The trunk launch arg is not a safe git branch name');
  }
  return { trunk: launchInputs.trunk, pr: launchInputs.references[0] };
}

function createRunState(launch, argsObject = {}) {
  return {
    request: buildRemediationRequest(launch.pr),
    trunk: launch.trunk,
    pr: launch.pr,
    references: [launch.pr],
    relaySentence: relayedMessageSentence(),
    decisions: [],
    level: resolveLevel(undefined, AUTONOMY_TABLE),
    storedAnswers: readStoredAnswers(argsObject),
    pendingReply: readPendingReply(argsObject),
    answerLog: [],
    answeredKeys: new Set(),
    taken: [],
    reversibleEffects: [],
    approvals: [],
    rejected: [],
    undone: [],
    open: [],
    head: undefined,
    branch: undefined,
    headRound: undefined,
    notRunGates: [],
    draft: false,
    waveCount: 0,
    pass: 1,
    replans: 0,
    headMoves: 0,
    versionAnswer: undefined,
    factsStem: undefined,
    pluginRoot: undefined
  };
}

/**
 * Runs the fix pass call of fix.js on the checked facts and returns {fix},
 * a result that fits FIX_RESULT_SCHEMA, or {cause}, an input stop or an
 * unusable result.
 */
async function runFixCall(run, facts) {
  const fixInputs = listFixInputs(run, facts);
  const inputStop = describeFixInputStop(fixInputs);
  if (inputStop !== undefined) {
    return { cause: inputStop };
  }
  phase('Fix');
  const fix = await agent(addResumeNote(buildFixPassPrompt(fixInputs), run), fixOptions(run));
  const resultProblem = describeFixResultProblem(fix);
  return resultProblem === undefined ? { fix: fix } : { cause: resultProblem };
}

function finishBlocked(causes) {
  return finish({ outcome: 'blocked', causes: causes });
}

async function runRemediation(rawArgs) {
  const launch = readRemediationLaunch(rawArgs);
  if (launch.problem !== undefined) {
    return finishBlocked([launch]);
  }
  const run = createRunState(launch, rawArgs);
  const checked = await runFactsStep(run);
  if (checked.problem !== undefined) {
    return finishBlocked([checked]);
  }
  const headStop = describeHeadStop(checked.facts, run);
  if (headStop !== undefined) {
    return finishBlocked([headStop]);
  }
  const fixed = await runFixCall(run, checked.facts);
  if (fixed.cause !== undefined) {
    return finishBlocked([fixed.cause]);
  }
  if (escalationExits().includes(fixed.fix.exit_reason)) {
    return await runEscalation(fixed.fix, run);
  }
  const fixEnd = describeFixExit(fixed.fix, run);
  if (fixEnd.cause !== undefined) {
    return finishBlocked([fixEnd.cause]);
  }
  return finish({ outcome: 'complete', blocks: fixEnd.blocks });
}

return await runRemediation(args);
