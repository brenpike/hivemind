/*
 * standard-delivery relay.js: the branch runner step of the
 * standard-delivery workflow. The runner options, relay helpers and the
 * facts step live in lib/runner.js, the commit step and the inputs file
 * paths in lib/commit.js, the routing specs in lib/specs.js, and the
 * validation prompt sentences in lib/gates.js.
 *
 * Inputs
 *   run    the run state of main.js createRunState. The branch step reads
 *          trunk, answerLog, head and pluginRoot, and requestBranchReplan
 *          updates branchSwitches.
 *   plan   the accepted plan, from runPlanningPass (lib/plan.js).
 *   relay  each runner result: {outcome, stdout, stderr} under
 *          RELAY_SCHEMA, its stdout read with lib/routing.js.
 *   RUN_NAME and RELAY_SCHEMA from main.js.
 *
 * Outputs
 *   runBranchStep(run, plan, freshness)  {values}, else a cause, terminal
 *           for a command stop, a blocked relay and another branch.
 *   needsBranchReplan(branchValues, facts, plan)  true when the branch step
 *           switched onto a branch or commit other than the facts' one.
 *   requestBranchReplan(run)  {replan} the first time, else the stop of a
 *           second branch switch.
 *   The step, as meta.js names it:
 *   Branch  a runner runs the create-working-branch command. Its checked
 *           commit goes to observeHead (lib/record.js) at each pass start
 *           (main.js).
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Validation edits nothing (lib/gates.js).
 *   Only a branch script refusal, a branch other than the plan branch, a
 *   runner command value outside its class (describeCommandStop) and a
 *   second branch switch (requestBranchReplan) are terminal. stopDelivery
 *   (lib/record.js) ends the run blocked for a terminal cause, an agent
 *   failure and a report or run_again lead; only an approve or fix_cause
 *   lead asks (issue 457).
 *   The branch runner calls agent() through runRunnerRelay (lib/runner.js),
 *   and its prompt follows its runner prompt and relayed reply rules.
 *
 * Why
 *   The branch step is standard-delivery's alone; the relay helpers it
 *   shares with every runner step live in lib/runner.js.
 */

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
