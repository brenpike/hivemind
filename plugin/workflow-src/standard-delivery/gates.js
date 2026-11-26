/*
 * standard-delivery gates.js: the gate hooks of the standard-delivery
 * workflow. The gate loop they serve, with the validate and fix steps,
 * the version check, the gate rerun and the head check, lives in
 * lib/gates.js; its tail briefs live in lib/briefs.js and its tail asks
 * in lib/tails.js.
 *
 * Inputs
 *   run    the run state of main.js createRunState: localReview and
 *          reviewSkip, which runReviewGate (review.js) sets on a skip.
 *   plan, facts, gates  as lib/gates.js runGates passes them.
 *
 * Outputs
 *   gateIds()  every gate of the workflow, in run order: validation, then
 *          local review.
 *   configuredGateIds(run)  the gates the run requires, local review only
 *          when run.localReview is true and no review was skipped, so a
 *          skip holds for the rest of the run.
 *   gateNames()  the name of each gate, as the gate notes and briefs show
 *          it.
 *   runGateStep(stepId, run, plan, facts, gates)  the gate step of stepId:
 *          the pull request step (pr.js) for 'pr', local review
 *          (runReviewGate, review.js) for 'review', else validation
 *          (lib/gates.js).
 *   describeGateSkip(run, gateId)  skipped and run.reviewSkip in
 *          parentheses, a skip_reason enum code REVIEW_SCHEMA checks, or the
 *          code-built user-reply, never reviewer text, for a skipped local
 *          review, else undefined: lib/pr.js and lib/record.js show it in
 *          place of not configured.
 *   listGateSkipWarnings(run)  one warning line per gate describeGateSkip
 *          names: Warning:, the gate name, was and that text, which
 *          lib/record.js adds to the complete message.
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
  return run.localReview && !run.reviewSkip ? gateIds() : gateIds().filter((gateId) => gateId !== 'review');
}

function describeGateSkip(run, gateId) {
  return gateId === 'review' && run.reviewSkip ? 'skipped (' + run.reviewSkip + ')' : undefined;
}

function listGateSkipWarnings(run) {
  return gateIds().filter((gateId) => describeGateSkip(run, gateId) !== undefined).map((gateId) => 'Warning: ' + gateNames()[gateId] + ' was ' + describeGateSkip(run, gateId) + '.');
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
