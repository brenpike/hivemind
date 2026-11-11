/*
 * standard-delivery pr.js: the pull request hooks of the
 * standard-delivery workflow. The pull request step they serve, with its
 * title and body, the PR runner prompt, the check of its relay and the
 * blocked-push descriptions, lives in lib/pr.js.
 *
 * Inputs
 *   run    the run state of main.js createRunState: head.
 *   gates  the gate loop state of runGates (lib/gates.js).
 *   entry  a taken decision of run.taken: brief, kind and listed.
 *
 * Outputs
 *   buildPullRequestComment(run, gates)  the comment of the pull request:
 *          a fixed lead naming commit run.head with no closing line, then
 *          the run record of renderPullRequestRecord (lib/pr.js). The
 *          workflow always returns it, so its inputs file always carries a
 *          comment and its relay always a commented line.
 *   toPullRequestDecision(entry)  entry as the run record of the pull
 *          request texts shows it: a routing decision taken on a local
 *          review result with its fixed problem text of
 *          reviewDecisionProblems(), every other entry as it is.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   The comment lead is code-built and stays plain; the external parts of
 *   the run record pass through neutralizePullRequestText (lib/pr.js). A
 *   routing decision taken on a review result reaches the pull request
 *   texts with a fixed problem text, never reviewer text.
 *
 * Why
 *   The pull request step is shared (lib/pr.js), and its comment and
 *   decision lines are not: each workflow that runs it names its own here.
 */

function reviewDecisionProblems() {
  return {
    [DIMINISHING_RETURNS_EXIT_KIND]: 'Local review saw diminishing returns with findings still open. Stop fixing and hold the local review gate on that commit?',
    [PLANNER_ESCALATION_ROUTING_KIND]: 'Local review escalated a finding to the planner. Go back to planning, from fresh facts, for its remediation?',
    [ROOT_CLUSTER_ROUTING_KIND]: 'Local review found findings with one suspected root. Go back to planning, from fresh facts, for a remediation that closes the class?'
  };
}

function toPullRequestDecision(entry) {
  const problem = reviewDecisionProblems()[entry.kind];
  return problem === undefined ? entry : { brief: { ...entry.brief, problem: problem }, kind: entry.kind, listed: entry.listed };
}

function buildPullRequestComment(run, gates) {
  const parts = ['The delivery pushed commit ' + run.head + ' to this pull request.', ...renderPullRequestRecord(run, gates)];
  return cleanPullRequestText(parts.join('\n\n'), true);
}
