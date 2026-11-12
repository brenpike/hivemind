/*
 * standard-delivery gates.js: the gate hooks of the standard-delivery
 * workflow. The gate loop they serve, with the validate and fix steps,
 * the version check, the gate rerun and the head check, lives in
 * lib/gates.js; its tail briefs live in lib/briefs.js and its tail asks
 * in lib/tails.js.
 *
 * Inputs
 *   run    the run state of main.js createRunState: localReview.
 *   plan, facts, gates  as lib/gates.js runGates passes them.
 *
 * Outputs
 *   gateIds()  every gate of the workflow, in run order: validation, then
 *          local review.
 *   configuredGateIds(run)  the gates the launch configures, local review
 *          only when run.localReview is true.
 *   gateNames()  the name of each gate, as the gate notes and briefs show
 *          it.
 *   runGateStep(stepId, run, plan, facts, gates)  the gate step of stepId:
 *          the pull request step (pr.js) for 'pr', local review
 *          (runReviewGate, review.js) for 'review', else validation
 *          (lib/gates.js).
 *   listNotConfiguredGateLines(run)  the notRunGates line of each gate the
 *          launch leaves out: notConfiguredReviewLine() (review.js) when
 *          run.localReview is false, else none.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   runGateStep is the only place the gate loop reaches runReviewGate and
 *   runPullRequestStep.
 *
 * Why
 *   The gate loop is shared (lib/gates.js), and the gates are not: each
 *   workflow that runs it names its own gates and steps here.
 */

function gateIds() {
  return ['validate', 'review'];
}

function configuredGateIds(run) {
  return run.localReview ? gateIds() : gateIds().filter((gateId) => gateId !== 'review');
}

function gateNames() {
  return { validate: 'validation', review: 'local review' };
}

function runGateStep(stepId, run, plan, facts, gates) {
  if (stepId === 'pr') {
    return runPullRequestStep(run, plan, gates);
  }
  if (stepId === 'review') {
    return runReviewGate(run, plan, gates);
  }
  return runValidateGate(run, plan, facts, gates);
}

function listNotConfiguredGateLines(run) {
  return run.localReview ? [] : [notConfiguredReviewLine()];
}
