/*
 * standard-delivery main.js: the body of the standard-delivery
 * workflow script. It delivers a request on one working branch: branch
 * facts, a checked plan, questions decided or asked, the working branch,
 * each wave of plan steps with its commit, then the version bump,
 * validation and local review as gates (ADR-0037 invariant 2), then the
 * pull request. The run ends at the pull request: once every configured
 * gate held on one commit, it pushes that commit and opens or reuses the
 * pull request, and ends complete naming it. Watching the pull request is
 * the overlord's, not this script's (ADR-0037 decision 4).
 *
 * The phase modules of this directory hold every other function, and the
 * build bundles them, in name order, ahead of this file: gates.js, plan.js,
 * pr.js, record.js, relay.js, review.js, scope.js and waves.js. Each opens
 * with the contract of its steps. This file holds the launch reading, the
 * run state, the pass loop and every top-level constant and limit.
 *
 * Inputs
 *   args   the Workflow args global, read with lib/args.js as analysis-only
 *          reads it: a string (the request), an object {request, trunk?,
 *          references?, local_review?, draft?, answers?, build?, reply?},
 *          or undefined. request, trunk, references, local_review and draft
 *          come from the launch args only. local_review is true or false:
 *          absent means true, so the local review gate is configured unless
 *          the launch turns it off, and any other value stops the run. draft
 *          is true or false: absent means false, so the pull request opens
 *          ready for review unless the launch asks for a draft, and any
 *          other value stops the run. answers and reply
 *          follow the result.js pause contract: answers['round-N'] holds the
 *          reply to round N, and reply answers the first round with no
 *          stored answer, only when answers is present. Round N is the
 *          answerLog length plus 1, so a resume of the same build replays
 *          every earlier round byte for byte. When answers is present, build
 *          must equal BUILD_ID or the run stops at the launch check
 *          (lib/args.js readLaunchInputs). An autonomy key is
 *          never read: the level is the table's default_level until slice 3
 *          (ADR-0037 decision 23).
 *   AUTONOMY_TABLE, BRIEF_SCHEMA, PLAN_SCHEMA  data constants copied in by
 *          the build. SCOPE_SCHEMA, built here by buildScopeSchema
 *          (scope.js), is the scope step result schema.
 *
 * Outputs
 *   pauseForUser({resumeArgs, blocks}) when a question needs the user,
 *   otherwise finish({outcome: 'blocked', causes, blocks}), or
 *   finish({outcome: 'complete', blocks, pr}) once the pull request step
 *   ran; see result.js for these shapes.
 *   resume_args is {answers, build} alone: no run record (ADR-0037
 *   decision 2). build is BUILD_ID, the build id the build injects, and a
 *   resume whose build differs stops at the launch check (issue 472).
 *   Every chat message has one shape (issue 460), built in record.js. A
 *   pause is a one-line lead of what happened, then the questions
 *   renderQuestions shows, with the reply line last: a planning pause leads
 *   with describePlanLine(plan, outsidePaths) (plan.js), a tail ask with its
 *   own lead (askTail, gates.js). A run end is its lead, then, when blocked,
 *   the Next line, any later causes and the commit end line, then only the
 *   records ADR-0037 decision 3 needs in chat:
 *   the branch, commit count and head when the run made commits, the
 *   reversible effects and the taken decisions, one line each. A complete
 *   run names the pull request and its commit, the gates that held and any
 *   gate not configured, the warning when there is one and the rejected
 *   findings. No chat message shows a commit list, a criticality or ask
 *   reason line, and no pause shows a taken decision.
 *   The pull request body and comment each carry the one run record
 *   buildRunRecordParts() returns: the commits, the reversible effects, the
 *   gates and the taken decisions, in that order (ADR-0037 decision 3;
 *   review findings 1a75f008 and 6f87ce62), the decisions in full with
 *   their compact fallback (issue 445). Each decision is the same brief
 *   once however many passes took it.
 *   No question shows the plan summary or names this run's per-agent
 *   results. When the scope sets limits and a plan path lies outside them,
 *   the acceptance has no recommendation, so it is asked at every level,
 *   and the planning pause lead names up to maxListedItems() of those
 *   paths, each encoded whole, then the count of the rest (plan.js
 *   listPlanPaths). Only an irreversible effect, an exact ask, shows its
 *   text word for word.
 *   Bounded fields (issue 445): every planner, worker and validation
 *   string a message shows comes from a step-schema field with maxLength,
 *   the brief fields of decision-brief-schema.json, the digest, step id
 *   and effect summary of plan-schema.json, and the blocker of the plan
 *   result, worker, gate edit and validate schemas, 400 code points. The
 *   unbounded agent fields never reach a message: plan.summary reaches
 *   only the pull request title and body, a worker summary nothing, and
 *   validate failures only the fix prompt. The code-built brief of every
 *   plan, trunk, effect, bump, validation, gate rerun and review routing
 *   decision fits BRIEF_SCHEMA with worst-case inputs, holds
 *   unshownBriefText() (plan.js) in each field no message shows, so the
 *   bundle carries no text the user never reads, and the diminishing
 *   returns, escalation and root cluster problems embed no reviewer free
 *   text, only a short finding id and counts.
 *   No message cuts an agent value: a value is bounded at its source schema
 *   and shown whole, or it is not shown. Every local review string a
 *   message shows has a bound in REVIEW_SCHEMA, written by the reviewer for
 *   the user: the user_question found, ask and recommendation why 200 and
 *   each option summary 160, blocker 300, field_excerpt 200 and
 *   pattern_category one of P1 to P4. A finding id is 8 to 64 lowercase hex
 *   characters by its schema pattern, so its short id, the first 8, is
 *   whole hex. A break-fix-break stop shows the count of conflicting
 *   findings and no entry, and a rejected finding shows its short id alone.
 *   Every blocked result carries one Next line as a whole block right
 *   after its first block, and no block carries shorten. A blocked run end
 *   takes a list of causes, {problem, nextAction?} each, never a message:
 *   finishDeliveryBlocked passes them to finish (lib/result.js), which
 *   builds the lead, the Next line nextStepLine(nextAction) and one block
 *   per later cause through buildStopBlocks. Each Next line starts with
 *   'Next:' and points at no cause its lead does not name. A worker, gate
 *   edit or validation result may carry
 *   next_action with outcome blocked: run_again when the cause is outside
 *   the repo and passes with no change, fix_cause otherwise.
 *   One rule covers every step: a null result from any agent() call, an
 *   agent failure, is a cause through describeUnusableResult
 *   (lib/result.js), with the describeNoResult sentence once and next
 *   action run_again, and a non-null unusable result keeps the fix line.
 *   run_again gives a line saying nothing in the repo needs a fix and to
 *   run the request again later; fix_cause or no value gives the fix line.
 *   A blocked wave says run_again only when every blocked worker does.
 *   Compound rule: a file-changing step passes its own causes to
 *   runCommitStep (relay.js), which ends the run with them and a failed
 *   commit's cause after them, so no stop hides another. Causes that need
 *   a fix lead, with the fix line, then agent failures, each group in step
 *   order, so the Next line is run_again only when every cause is. A lead
 *   longer than maxBlockedLeadLength() code points has as its compact form
 *   the cutAtBoundary prefix of at most those code points, so it never
 *   cuts mid-word, and the lead of an open question stop is fixed and
 *   short, so the fit keeps the lead and the Next line in every tier and
 *   finish never throws.
 *   An open question stop and a resume across builds are each one cause
 *   with next action answer, so their Next line is nextStepLine('answer'):
 *   run the request again with the answers in it. When the run made
 *   commits, the branch line names the encoded branch, which
 *   plan-schema.json bounds by maxLength 200 (issue 434). No Next line
 *   offers a pull request from commits a gate did not hold on (issue 444).
 *   Only finishDeliveryComplete, with pr, ends complete, so complete
 *   always means a pull request exists.
 *   Every step- or script-written diagnostic or name a message shows goes
 *   through encodeUntrustedText (lib/result.js), so it shows as quoted JSON
 *   of printable ASCII. A blocked relay of the facts, branch, commit,
 *   bump-type or pull request step quotes the payload of its last
 *   'blocker: ' line that has one; with none it quotes the first two
 *   non-blank stderr lines, and only a blank or missing stderr says it
 *   gave no reason (describeRelayBlocker). A planner, worker, gate edit or
 *   validation blocker goes through describeReason, and each dirty path a
 *   commit relay names goes through quoteDiagnostic: each made one line and
 *   cut at a sentence or word boundary to maxExcerptLength() code points
 *   first, or to maxReasonLength() through describeReason, with the cut
 *   mark after a cut quote. The blocker of a review stop goes through
 *   quoteDiagnostic with a limit equal to its maxLength 300, so it is made
 *   one line and never cut. Branch names, step ids, reversible effect
 *   summaries and the other review values, the excerpt of a review stop
 *   among them, go through encodeUntrustedText whole, and a scheduling
 *   problem through
 *   toPrintableAscii. JSON.stringify is left only in throw messages, in
 *   questionKey and in the acceptResolution comparison. Planner prose
 *   written for the user is not encoded: the brief fields and verbatim
 *   text lib/brief.js renders, which include an irreversible effect's
 *   text, and digest.change in the planning pause lead, show as
 *   written. That
 *   is the residual ADR-0037 records (Risks, step text in a blocked
 *   message, (b)).
 *   A local review question is the reviewer's own: the review returns
 *   finding_id and user_question, and the pause leads with one line, 'Local
 *   review on commit', the head, the finding's first 8 code points and the
 *   encoded found, then shows that question, the encoded ask, the
 *   reviewer's 2 to 4 options with encoded summaries and its recommendation
 *   and strength with the encoded why. No option and no strength comes from
 *   code (issue 460), and its ask reason comes from decide(). The rerun
 *   review's user_answer.question is that lead and the question, the text
 *   the user saw. A review stop is one line naming the exit and its cause,
 *   the head, the iterations and the open finding count, and at most one
 *   detail line built in code: the count of conflicting findings, the whole
 *   encoded excerpt under a line naming the short finding id and the
 *   category, or the blocker.
 *
 * Invariants
 *   contractRows() in contract.js is the executable home of the step
 *   rules: one row per rule, each naming the check that enforces it, and
 *   one test per row in tests/workflow-scripts/standard-delivery.test.mjs.
 *   A check is a function of the built script, not of this file: it can
 *   live in any module. The build never bundles contract.js, so the rows
 *   never reach the built script.
 *   Every top-level const of the workflow is in this file. A module holds
 *   only function declarations, or the build fails naming it, so the
 *   module order cannot change what runs.
 *   A pass is one runDeliveryPass call. It ends with {result}, the run
 *   result, or {replan}, the data the next pass plans from.
 *   A pass starts at launch, after a needs_replan wave, after a branch
 *   step that switched branch or commit, after a taken local review
 *   escalation or root cluster, or after a reply to a tail ask other than
 *   a local review question, and every pass starts with the facts step,
 *   so every planner call follows the facts of its own pass (ADR-0037
 *   invariant 3). Then the scope step (scope.js) runs once, after the facts
 *   step and the scan and before planning, and again after each reply round
 *   of the pass unless the reply settled the shown plan acceptance
 *   (plan.js). Its checked scope reaches only the plan and revise prompts
 *   and the plan acceptance check of its pass.
 *   Every step result schema whose fields depend on its outcome, or on
 *   exit_reason for the review, is built by buildTaggedSchema (lib/schema.js)
 *   from one table, which gives both its anyOf branches and its 'Only with'
 *   descriptions: the plan result and revise schemas, the relay, worker,
 *   bump, fix, both validate and review schemas. validateSchema checks the
 *   full schema, so a result that carries a field of another outcome, or
 *   lacks a field its outcome requires, blocks the step that reads it with
 *   that step's malformed or schema message, and no consumer checks the tie
 *   again by hand. A field is required under its outcome only where a
 *   consumer rejected its absence before. The revise schema goes through
 *   the same builder with settled as a shared field, never Object.assign
 *   over a built schema: settled would then be missing from every branch,
 *   so every value would fail. Each agent gets toAgentSchema of the full
 *   schema, the same schema with every anyOf removed, because the Messages
 *   API rejects a tool input schema that has anyOf at its top level.
 *   Labels come only from the pass, the round, the step id, the wave
 *   number, and the gate step with its run count (gateLabel), so each is
 *   unique and a resume replays every earlier prompt byte for byte and gets
 *   every earlier result, side effects included, from cache.
 *
 * Why
 *   Delivery transitions cost no model turn when they are code. The git
 *   hard stops live in the committed scripts, so the workflow hands each
 *   script checked inputs and blocks when a relay is missing, malformed or
 *   inconsistent.
 */

const RUN_NOUN = 'delivery';
const RUN_NAME = describeRunNoun(RUN_NOUN);
const PLANNER_AGENT = 'hivemind:cerebrate';
const RUNNER_MODEL = 'haiku';
const SCOPE_MODEL = 'sonnet';
const BUMP_MODEL = 'sonnet';
const PLANNER_QUESTION_KIND = 'planner_question';
const PLAN_ACCEPTANCE_KIND = 'plan_acceptance';
const TRUNK_STALE_KIND = 'trunk_stale';
const EXTERNAL_EFFECT_KIND = 'external_effect';
const VERSION_BUMP_TYPE_KIND = 'version_bump_type';
const VERSION_BUMP_INDETERMINABLE_KIND = 'version_bump_indeterminable';
const VALIDATION_REMEDIATION_KIND = 'validation_remediation';
const GATE_RERUN_KIND = 'gate_rerun';
const DIMINISHING_RETURNS_EXIT_KIND = 'diminishing_returns_exit';
const PLANNER_ESCALATION_ROUTING_KIND = 'planner_escalation_routing';
const ROOT_CLUSTER_ROUTING_KIND = 'root_cluster_routing';
const REMEDIATION_PLAN_ACCEPTANCE_KIND = 'remediation_plan_acceptance';
const REVIEWER_AGENT = 'hivemind:local-reviewer';
const PLAN_RESULT_SCHEMA = buildPlanResultSchema(PLAN_SCHEMA, BRIEF_SCHEMA);
const RELAY_SCHEMA = buildRelaySchema();
const WORKER_SCHEMA = buildWorkerSchema();
const BUMP_SCHEMA = buildBumpSchema();
const FIX_SCHEMA = buildGateEditSchema();
const VALIDATE_SCHEMA = buildValidateSchema(false);
const VALIDATE_COMMANDS_SCHEMA = buildValidateSchema(true);
const REVIEW_SCHEMA = buildReviewSchema();
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

function maxReviewIterations() {
  return 10;
}

function maxTitleLength() {
  return 72;
}

function maxPullRequestTextLength() {
  return 60000;
}

function readDeliveryLaunch(rawArgs) {
  const argsObject = readArgsObject(rawArgs);
  if (!isNonEmptyString(argsObject.request)) {
    return { problem: 'No request was given, so there is nothing to deliver.' };
  }
  const launchInputs = readLaunchInputs(argsObject, RUN_NOUN, BUILD_ID);
  if (launchInputs.problem !== undefined) {
    return launchInputs;
  }
  if (!isGitIdentifier(launchInputs.trunk)) {
    return { problem: 'The trunk launch arg is not a safe git branch name, so ' + RUN_NAME + ' did not start.' };
  }
  const reviewInput = readLocalReview(argsObject);
  if (reviewInput.problem !== undefined) {
    return reviewInput;
  }
  const draftInput = readDraft(argsObject);
  if (draftInput.problem !== undefined) {
    return draftInput;
  }
  return { argsObject: argsObject, request: argsObject.request, trunk: launchInputs.trunk, references: launchInputs.references, localReview: reviewInput.localReview, draft: draftInput.draft };
}

function readLocalReview(argsObject) {
  if (argsObject.local_review === undefined) {
    return { localReview: true };
  }
  if (argsObject.local_review === true || argsObject.local_review === false) {
    return { localReview: argsObject.local_review };
  }
  return { problem: 'The local_review launch arg must be true or false, so ' + RUN_NAME + ' did not start.' };
}

function readDraft(argsObject) {
  if (argsObject.draft === undefined) {
    return { draft: false };
  }
  if (argsObject.draft === true || argsObject.draft === false) {
    return { draft: argsObject.draft };
  }
  return { problem: 'The draft launch arg must be true or false, so ' + RUN_NAME + ' did not start.' };
}

function createRunState(launch) {
  return {
    request: launch.request,
    trunk: launch.trunk,
    references: launch.references,
    localReview: launch.localReview,
    draft: launch.draft,
    level: resolveLevel(undefined, AUTONOMY_TABLE),
    storedAnswers: readStoredAnswers(launch.argsObject),
    pendingReply: readPendingReply(launch.argsObject),
    answerLog: [],
    answeredKeys: new Set(),
    taken: [],
    reversibleEffects: [],
    commits: [],
    runnerCommits: {},
    head: undefined,
    branch: undefined,
    notRunGates: [],
    waveCount: 0,
    pass: 0,
    replans: 0,
    branchSwitches: 0
  };
}

async function runDeliveryPass(run, replan) {
  const checked = await runFactsStep(run);
  if (checked.problem !== undefined) {
    return { result: finishDeliveryBlocked([checked], run) };
  }
  const scoped = await runScopeStep(run, checked.facts);
  if (scoped.problem !== undefined) {
    return { result: finishDeliveryBlocked([scoped], run) };
  }
  const planned = await runPlanningPass(run, checked.facts, scoped.scope, replan);
  if (planned.result !== undefined) {
    return planned;
  }
  const branched = await runBranchStep(run, planned.plan, planned.freshness);
  if (branched.problem !== undefined) {
    return { result: finishDeliveryBlocked([branched], run) };
  }
  if (needsBranchReplan(branched.values, checked.facts, planned.plan)) {
    return requestBranchReplan(run);
  }
  return runPlanWaves(run, planned.plan, checked.facts);
}

async function runDelivery(rawArgs) {
  const launch = readDeliveryLaunch(rawArgs);
  if (launch.problem !== undefined) {
    return finishDeliveryBlocked([launch], undefined);
  }
  const run = createRunState(launch);
  let replan;
  for (;;) {
    run.pass += 1;
    const passEnd = await runDeliveryPass(run, replan);
    if (passEnd.result !== undefined) {
      return passEnd.result;
    }
    replan = passEnd.replan;
  }
}

return await runDelivery(args);
