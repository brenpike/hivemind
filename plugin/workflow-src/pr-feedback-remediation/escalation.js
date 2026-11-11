/*
 * pr-feedback-remediation escalation.js: the remediation planning of the
 * pr-feedback-remediation workflow, run when the fix pass ends
 * planner-escalation or root-cluster-suspected: the routing decision, the
 * review block, the planning passes and the draft end.
 *
 * Inputs
 *   fix    a fix pass result that fits FIX_RESULT_SCHEMA, whose exit_reason
 *          is one of escalationExits() (fix.js).
 *   run    the run state of main.js. The passes read and update every field
 *          lib/plan.js, lib/scope.js, lib/tails.js and lib/record.js name.
 *   replan the replan data the next pass plans from: {reason, review?}.
 *   plan   the plan runPlanningPass (lib/plan.js) returns once every
 *          question of its pass is settled or taken.
 *   describeFixLead(run) (fix.js) leads the routing brief and the replan
 *   reason.
 *   The constants of main.js this file reads: RUN_NAME,
 *   PLANNER_ESCALATION_ROUTING_KIND and ROOT_CLUSTER_ROUTING_KIND.
 *
 * Outputs
 *   buildRemediationRequest(pr)  run.request: the code-built request the
 *          scope, plan and revise prompts carry, naming the pull request.
 *   buildEscalationBrief(fix, run)  the routing brief, kind
 *          planner_escalation_routing or root_cluster_routing, built in
 *          code from counts and the pull request, with no reviewer text.
 *   projectEscalationReview(fix)  the review block of the replan: the
 *          exit_reason, then each field fixExitFields() names for it and
 *          deferred_escalation_items, each only when the result has it.
 *   routeEscalation(fix, run)  the routing pause {result}, else {replan}
 *          with the review block, once decide() took the routing or the
 *          user replied to it.
 *   describeUnbuiltWaves(plan)  the terminal cause the draft ends on once
 *          the plan is settled or taken, naming describePlanLine(plan).
 *   runRemediationPass(run, replan)  one planning pass: {result} or
 *          {replan}.
 *   runEscalation(fix, run)  the run result after the escalation.
 *
 * Invariants
 *   The routing decision resolves through resolveTailDecision
 *   (lib/tails.js) with its kind fixed here. At the table's default level
 *   decide() takes it, so it is listed in the run's taken decisions; an
 *   ask pauses, and the reply plans again with the same review block.
 *   Each planning pass starts with runFactsStep (lib/runner.js), labels
 *   facts-P and scan-P, then runScopeStep (lib/scope.js), label scope-P,
 *   then runPlanningPass (lib/plan.js), label plan-P, with P the pass
 *   number from 2, so every planner call follows the facts of its own pass
 *   and every label is unique. Once the routing kind is in run.taken, the
 *   plan acceptance resolves as remediation_plan_acceptance, the Promotion
 *   Gate (buildRemediationPlanBrief, lib/briefs.js).
 *   A facts, scan or scope stop goes through stopDelivery (lib/record.js)
 *   with isReplan true, and the reply to it plans again with the review
 *   block kept (keepReplanReview, lib/plan.js). A planning stop or pause
 *   comes back from runPlanningPass the same way.
 *   This draft builds no wave, so a settled or taken plan ends the run
 *   blocked with one terminal cause through finishDeliveryBlocked.
 *
 * Why
 *   The fix pass stops at a finding a review fix cannot close, so the
 *   remediation goes to the planner from fresh facts, with the review's
 *   own exit fields as the data it plans from.
 */

function buildRemediationRequest(pr) {
  return 'Remediate the review feedback of pull request ' + pr + ' that its review fix pass escalated, on the pull request branch.';
}

function buildEscalationBrief(fix, run) {
  const isCluster = fix.exit_reason === 'root-cluster-suspected';
  const lead = describeFixLead(run);
  return buildTailBrief({
    kind: isCluster ? ROOT_CLUSTER_ROUTING_KIND : PLANNER_ESCALATION_ROUTING_KIND,
    problem: (isCluster
      ? lead + ' found ' + describeCount(fix.member_count, 'finding') + ' in ' + describeCount(fix.cluster_files.length, 'file') + ' that share one suspected root.'
      : lead + ' escalated a finding to the planner.') + ' Go back to planning, from fresh facts, for ' + (isCluster ? 'a remediation that closes the class?' : 'its remediation?'),
    goOn: 'Plan the remediation from fresh facts.',
    strength: 'strong',
    why: 'A review fix cannot close it, and a plan that cannot be undone, changes how the system is built or touches safety comes to you before it runs.'
  });
}

function projectEscalationReview(fix) {
  const review = { exit_reason: fix.exit_reason };
  for (const field of [...fixExitFields()[fix.exit_reason], 'deferred_escalation_items']) {
    if (Object.hasOwn(fix, field)) {
      review[field] = fix[field];
    }
  }
  return review;
}

function routeEscalation(fix, run) {
  const brief = buildEscalationBrief(fix, run);
  const decided = resolveTailDecision(brief.kind, brief, run);
  if (decided.result !== undefined) {
    return decided;
  }
  const reason = describeFixLead(run) + ' returned ' + fix.exit_reason + ', so plan a remediation of the review block from the fresh facts.';
  return { replan: { reason: reason, review: projectEscalationReview(fix) } };
}

function describeUnbuiltWaves(plan) {
  return { problem: 'The remediation is planned, but this draft builds no waves yet, so ' + RUN_NAME + ' stopped. ' + describePlanLine(plan), terminal: true };
}

async function runRemediationPass(run, replan) {
  const stopPass = (cause) => keepReplanReview(stopDelivery([cause], run, [], true), replan);
  const checked = await runFactsStep(run);
  if (checked.problem !== undefined) {
    return stopPass(checked);
  }
  const scoped = await runScopeStep(run, checked.facts);
  if (scoped.problem !== undefined) {
    return stopPass(scoped);
  }
  const planned = await runPlanningPass(run, checked.facts, scoped.scope, replan);
  if (planned.plan === undefined) {
    return keepReplanReview(planned, replan);
  }
  return { result: finishDeliveryBlocked([describeUnbuiltWaves(planned.plan)], run) };
}

async function runEscalation(fix, run) {
  const routed = routeEscalation(fix, run);
  if (routed.result !== undefined) {
    return routed.result;
  }
  let replan = routed.replan;
  for (;;) {
    run.pass += 1;
    const passEnd = await runRemediationPass(run, replan);
    if (passEnd.result !== undefined) {
      return passEnd.result;
    }
    replan = passEnd.replan;
  }
}
