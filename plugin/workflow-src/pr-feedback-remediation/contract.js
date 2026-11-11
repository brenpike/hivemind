/*
 * pr-feedback-remediation contract.js: the contract table of the
 * pr-feedback-remediation workflow, one row per step rule.
 *
 * Outputs
 *   contractRows()  an array of {id, step, check, rule}: id is PFR-NN, step
 *                   the step the rule governs, check the function of the
 *                   built script that enforces it, and rule one sentence.
 *
 * Invariants
 *   Each row has one test in
 *   tests/workflow-scripts/pr-feedback-remediation.test.mjs, which loads
 *   this file with loadLibs and requires each check to be a function of the
 *   script the build makes in memory: a check can live in main.js, in
 *   fix.js, in escalation.js or in a shared library the build carries.
 *   The build bundles every .js file of this directory but this one, so this
 *   file never reaches the built script.
 *
 * Why
 *   The rows are test data, so keeping them out of the built script leaves
 *   its character budget to the code that runs.
 */

function contractRows() {
  return [
    { id: 'PFR-01', step: 'Launch', check: 'readRemediationLaunch', rule: 'The launch is a plain object holding only references, trunk, answers, build and reply, its references and trunk are read through readLaunchInputs of args.js, whose build check refuses a resume of another build, references names exactly one pull request and trunk passes isGitIdentifier, or the run ends blocked with no agent call; a request, as a string or as a key, is refused the same way.' },
    { id: 'PFR-02', step: 'Relay', check: 'createRunState', rule: 'run.relaySentence holds relayedMessageSentence() from launch, so every agent prompt, the facts, scan and fix pass prompts and a facts retry included, carries it as its second line from the first agent on (ADR-0040 edge case a).' },
    { id: 'PFR-03', step: 'Facts', check: 'runFactsStep', rule: 'Pass 1 runs runFactsStep of runner.js with the pull request as its one reference, label facts-1, so the facts checks and the scan of the texts it counts run before the fix pass, and a facts or scan stop ends the run blocked with no fix pass.' },
    { id: 'PFR-04', step: 'Head', check: 'describeHeadStop', rule: 'When the facts show no branch, or a branch equal to the trunk, the run ends blocked before the fix pass, naming the trunk through encodeUntrustedText.' },
    { id: 'PFR-05', step: 'Fix', check: 'describeFixInputStop', rule: 'The fix pass is one hivemind:github-reviewer call, label fix-1, phase Fix, whose fix_mode_input data block holds mode fix, pr the launch reference, working_branch the facts branch and base the trunk, each of pr, working_branch and base passing isGitIdentifier first, or the run ends blocked, terminal with next action report, naming the input and never its value, with no reviewer call.' },
    { id: 'PFR-06', step: 'Fix', check: 'buildFixResultSchema', rule: 'FIX_RESULT_SCHEMA is tagged by exit_reason, holds exactly the Output Contract fields of github-reviewer.md, requires exit_reason, mode, findings_resolved and findings_open and per exit_reason exactly the fields the contract names, allows deferred_escalation_items only on an escalation, and bounds every string with maxLength or an enum and every list with maxItems.' },
    { id: 'PFR-07', step: 'Fix', check: 'describeFixResultProblem', rule: 'A null fix pass result, or one that fails FIX_RESULT_SCHEMA, ends the run blocked through describeUnusableResult: run_again with the agent failure sentence for null, report otherwise.' },
    { id: 'PFR-08', step: 'Fix', check: 'describeFixExit', rule: 'clean and merge-advised end complete with no pr, and merge-advised shows its advisory reason and its recommendation and structural home through quoteDiagnostic.' },
    { id: 'PFR-09', step: 'Fix', check: 'describeFixExit', rule: 'injection-suspect ends the run blocked with a terminal cause naming the encoded candidate URL and the pattern category.' },
    { id: 'PFR-10', step: 'Fix', check: 'describeFixExit', rule: 'blocked, user-input-required and high-severity-rejection end the run blocked naming the exit and each candidate URL through encodeUntrustedText, and blocked also quotes its blocker_reason through describeReason.' },
    { id: 'PFR-11', step: 'Route', check: 'routeEscalation', rule: 'planner-escalation and root-cluster-suspected never end at describeFixExit: the routing decision resolves through resolveTailDecision of tails.js with kind planner_escalation_routing or root_cluster_routing fixed by the exit, and at the table default level decide() takes it, so the final message lists it as a decision taken.' },
    { id: 'PFR-12', step: 'Route', check: 'buildEscalationBrief', rule: 'The routing brief is built in code through buildTailBrief, names the pull request and, for a root cluster, only the member and file counts, carries no reviewer text, and fits BRIEF_SCHEMA with option A going back to planning from fresh facts at strength strong.' },
    { id: 'PFR-13', step: 'Plan', check: 'buildRemediationRequest', rule: 'run.request is the code-built request naming the pull request, and the scope, plan and revise prompts carry it in their request block, with run.relaySentence as their second line.' },
    { id: 'PFR-14', step: 'Plan', check: 'runRemediationPass', rule: 'After the routing, each planning pass runs runFactsStep from fresh facts, label facts-P with its scan scan-P, then runScopeStep, label scope-P, then runPlanningPass, label plan-P, P counting from 2, so every planner call follows the facts of its own pass.' },
    { id: 'PFR-15', step: 'Plan', check: 'projectEscalationReview', rule: 'The plan prompt of the first planning pass carries a replan block naming the pull request and the exit, and a review block holding only the exit_reason and the fields fixExitFields() names for it, with deferred_escalation_items when the result has it.' },
    { id: 'PFR-16', step: 'Plan', check: 'describeUnbuiltWaves', rule: 'The plan acceptance resolves through decide() as remediation_plan_acceptance, the Promotion Gate; once every question is settled or taken the run ends blocked with one terminal cause saying this draft builds no waves yet and naming describePlanLine(plan), followed by the decisions taken.' },
    { id: 'PFR-17', step: 'Revise', check: 'pauseDelivery', rule: 'A plan acceptance decide() asks pauses through pauseDelivery with resume_args {answers, build}, and a resume with answers, build and reply replays every earlier agent prompt byte for byte from cache, then revises, label revise-R, and a reply that settles the acceptance ends at the draft end with no second pause.' },
    { id: 'PFR-18', step: 'Plan', check: 'keepReplanReview', rule: 'A facts, scan or scope stop of a planning pass goes through stopDelivery with isReplan true, so a fix_cause stop pauses with a step_stop question, and its reply starts a new pass whose plan prompt keeps the review block.' },
    { id: 'PFR-19', step: 'Labels', check: 'runEscalation', rule: 'Every agent call of a run has a label no other call of that run has, across the fix pass, every planning pass, every revise round and every check retry, so a resume gets every earlier result from cache.' }
  ];
}
