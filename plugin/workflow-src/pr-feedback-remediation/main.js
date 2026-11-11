/*
 * pr-feedback-remediation main.js: the body of the pr-feedback-remediation
 * workflow script, a draft (ADR-0040 decision 2). The pull request watch
 * launches it when a watch ends on an escalation. It gathers the branch
 * facts, then runs one schema-checked hivemind:github-reviewer fix pass on
 * the pull request, and ends on that pass's exit.
 *
 * fix.js holds the fix pass, and the build bundles it ahead of this file.
 * This file holds the launch reading, the run state, the run and every
 * top-level constant.
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
 *          at the launch check with no agent call.
 *   BUILD_ID  the constant the build copies in.
 *
 * Outputs
 *   finish({outcome: 'complete', blocks}) or finish({outcome: 'blocked',
 *   causes}) (lib/result.js). A complete end carries no pr.
 *
 * Invariants
 *   Relayed message (ADR-0040 edge case a): the harness relays the user
 *   message that started the watch to every workflow agent, and it may be
 *   stale by the time the watch launches this run. So run.relaySentence
 *   holds relayedMessageSentence() from launch, the ADR-0037 decision 24
 *   fixed sentence for a launch, and every prompt carries it as its second
 *   line from the first agent on, through addResumeNote (lib/runner.js).
 *   Facts first: pass 1 runs runFactsStep (lib/runner.js) with the pull
 *   request as its one reference, so the facts step, its checks and the
 *   scan of the GitHub texts it counts run before the fix pass. A facts or
 *   scan stop ends the run blocked.
 *   The fix pass runs only once the facts show a branch other than the
 *   trunk (fix.js describeHeadStop).
 *   Every blocked end passes its causes to finish, which builds the lead
 *   and the Next line (lib/stop.js).
 *
 * Why
 *   The watch stays in the main session (ADR-0040 decision 1), so the
 *   remediation it hands off runs as a script with checked steps.
 */

const RUN_NOUN = 'remediation';
const RUN_NAME = describeRunNoun(RUN_NOUN);
const RUNNER_MODEL = 'haiku';
const REVIEWER_AGENT = 'hivemind:github-reviewer';
const RELAY_SCHEMA = buildRelaySchema();
const FIX_RESULT_SCHEMA = buildFixResultSchema();

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
    return describeLaunchProblem('The launch args must be an object of references and trunk');
  }
  if (Object.keys(rawArgs).some((key) => !launchKeys().includes(key))) {
    return describeLaunchProblem('The launch args may hold only references, trunk, answers, build and reply');
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

function createRunState(launch) {
  return {
    trunk: launch.trunk,
    pr: launch.pr,
    references: [launch.pr],
    relaySentence: relayedMessageSentence(),
    answerLog: [],
    pass: 1,
    factsStem: undefined,
    pluginRoot: undefined
  };
}

function finishBlocked(causes) {
  return finish({ outcome: 'blocked', causes: causes });
}

async function runRemediation(rawArgs) {
  const launch = readRemediationLaunch(rawArgs);
  if (launch.problem !== undefined) {
    return finishBlocked([launch]);
  }
  const run = createRunState(launch);
  const checked = await runFactsStep(run);
  if (checked.problem !== undefined) {
    return finishBlocked([checked]);
  }
  const headStop = describeHeadStop(checked.facts, run);
  if (headStop !== undefined) {
    return finishBlocked([headStop]);
  }
  const fixEnd = await runFixPass(run, checked.facts);
  if (fixEnd.cause !== undefined) {
    return finishBlocked([fixEnd.cause]);
  }
  return finish({ outcome: 'complete', blocks: fixEnd.blocks });
}

return await runRemediation(args);
