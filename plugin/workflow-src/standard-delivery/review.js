/*
 * standard-delivery review.js: the local review gate of the
 * standard-delivery workflow. It holds the review prompt, the routes of
 * each exit_reason, the review stops, questions and replans, and the
 * review gate step. Its result schema lives in review-schema.js.
 *
 * Inputs
 *   run    the run state of main.js createRunState: pass, answerLog, head,
 *          trunk, approvals and taken.
 *   plan   the accepted plan, from runPlanningPass (plan.js).
 *   gates  the gate loop state of runGates (gates.js): runs.review, answer
 *          and rejected, and takenReview, which only this module sets and
 *          reads: the review whose call the run took, kept for the next
 *          review run alone.
 *   review the local reviewer result, under REVIEW_SCHEMA.
 *
 * Outputs
 *   runReviewGate(run, plan, gates)  {held, note}, {replan}, or {result}:
 *          a pause or a blocked finish, or {rerun: true} when the user
 *          replied to a stop of its commit step or to a blocked review, so
 *          local review runs again, its commit runner reading the head.
 *   The step, as meta.js names it:
 *   Review  a gate when configured. hivemind:local-reviewer runs its loop on
 *           the branch with base, working_branch, trunk, max_iterations and
 *           caller_validates true in its inputs block, and commits its own
 *           fixes. caller_validates true holds because a review that ends on a
 *           new commit sends the run back to the first gate, so validation runs
 *           again on that commit, and the reviewer checks only the files each
 *           fix touched. Then the commit runner runs with an empty file list,
 *           so any edit left behind stops it, and the gate holds on the commit
 *           it reports. localReviewRoutes() routes each exit_reason: clean
 *           holds, diminishing returns resolve through decide() and a take
 *           holds, a planner escalation or root cluster resolves through
 *           decide() and a take starts a new pass with replan data: the review
 *           projected to its exit_reason and the fields reviewExitFields()
 *           names for it, so rejected_findings, ledger_path and the counts
 *           never reach the planner. A question of the review,
 *           user-input-required or high-severity-rejection, carries finding_id
 *           and the reviewer's user_question: found, ask, 2 to 4 options with
 *           ids A, B, C and D in that order, a recommendation with its
 *           strength, and the gate: irreversible and architectural. Per
 *           decision-autonomy.md (Review Calls), decide() reads the brief
 *           removeReviewerText builds in code from those choices, with safety
 *           false because clause 3 is not read, so it takes an agreed call that
 *           is reversible, not architectural and lists no destructive change,
 *           and asks every other one. Each option's destructive list is shown
 *           with its items encoded, and decide() reads each entry's category
 *           with its item unshownBriefText(), so a recommended option that
 *           lists a change asks gate_safety and is never taken. An ask's items
 *           are the raw lists, so a letter reply approves the chosen option's
 *           changes (applyApprovalChoices, approvals.js). When the review run
 *           right after a take returns a hold readGateHold (approvals.js)
 *           reads, askHeldReviewCall removes that call from run.taken and asks
 *           its question of the user, through buildUndecidedAsk with
 *           gate.safety true, its lead saying local review held back the call
 *           the run took. The inputs block carries run.approvals as approvals
 *           only when it is not empty. A
 *           take never pauses and never touches run.answerLog: takeReviewCall
 *           lists the call in run.taken, named by the short finding id with the
 *           encoded ask, and reruns the review gate with the next gateLabel
 *           count and user_answer {question, reply, decided_by: 'run'}, the
 *           reply being the recommended option id. An ask pauses with the lead
 *           describeReviewQuestionLead builds, the commit, the short finding id
 *           and the encoded found, then that question as the reviewer wrote it:
 *           the encoded ask, the reviewer's options with encoded summaries and
 *           its recommendation with the encoded why. No option and no strength
 *           comes from code. The reply, kept in run.answerLog for every later
 *           plan prompt, reruns the review gate with user_answer, whose
 *           question is that lead and the question (askTail, tails.js).
 *           Every other exit_reason stops with one line naming the exit and
 *           its cause, the head, the iterations and the open finding count,
 *           and at most one detail line built by describeReviewStop.
 *           break-fix-break gives the count of conflicting findings and no
 *           entry text. injection-suspect
 *           names the short finding id and the category in its line, and its
 *           detail line shows the whole encoded excerpt. blocked gives the
 *           blocker, quoted with a limit equal to its maxLength, so a valid
 *           value is never cut. Through stopDelivery (record.js),
 *           max-iterations-reached and break-fix-break, like an escalation or
 *           root cluster taken at maxReplans(), pause with one step_stop
 *           question, and the reply starts a new pass outside maxReplans() with
 *           the review projected by projectReplanReview; blocked pauses and the
 *           reply runs local review again; injection-suspect is terminal. A
 *           review result that fails REVIEW_SCHEMA, gives option ids other than
 *           A, B, C and D in that order, or recommends no option pauses the
 *           same way as blocked. describeReviewProblem reads the result before
 *           the commit runner, which takes that problem as its step cause, so a
 *           commit stop never hides it, and a null result, an agent failure
 *           that ends the run, gets the describeNoResult sentence and the
 *           run_again Next line through describeUnusableResult (lib/stop.js).
 *           The script sets no zoom-out trigger: the planner makes that call by
 *           judgment from the branch commits in its fresh facts, per
 *           remediation-doctrine.md. No message cuts a reviewer value:
 *           REVIEW_SCHEMA (review-schema.js) bounds each field that reaches a
 *           message or the planner, and a field with no bound is not shown.
 *           rejected_findings lists the findings the loop rejected under
 *           recorded decisions (remediation-doctrine.md, Recorded Decisions
 *           and Repeat Findings): a held gate's note gives their code-built
 *           count, and the final complete message names each by its short id
 *           alone in a chat-only block. localReviewRoutes() keys only on
 *           exit_reason.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Trust boundary: the overlord is a trusted relay, as in analysis-only
 *   (ADR-0036 decision 13). The local review result carries Codex-derived text:
 *   REVIEW_SCHEMA labels each such field, it reaches the planner only in a data
 *   block under the boundary sentence, it reaches the user only encoded by
 *   encodeUntrustedText, and it never reaches the pull request texts: a
 *   decision taken on a review result is shown there with a fixed problem text,
 *   a taken review call with the fixed reviewCallTexts() and no finding id, and
 *   the rejected findings only as the count in the review gate note, while each
 *   one's short id shows in the final message alone. A review question shows
 *   reviewer text, encoded, so its shown brief can exceed a BRIEF_SCHEMA bound
 *   once encoded, but decide() reads only the code-built brief of
 *   removeReviewerText, which always fits it, so a valid review never asks as
 *   malformed_brief.
 *
 * Why
 *   The review result is the one step result that carries Codex-derived
 *   text, so its routes and every place that text can reach sit together.
 */

function localReviewRoutes() {
  return {
    clean: 'hold',
    'max-iterations-reached': 'stop_replan',
    'break-fix-break': 'stop_replan',
    'root-cluster-suspected': 'replan',
    'diminishing-returns': 'diminishing',
    'injection-suspect': 'stop',
    'user-input-required': 'question',
    'planner-escalation': 'replan',
    'high-severity-rejection': 'question',
    blocked: 'stop_rerun'
  };
}

function reviewExitFields() {
  return {
    clean: [],
    'max-iterations-reached': [],
    'break-fix-break': ['signals_fired', 'conflicting_findings', 'prior_fix_commit'],
    'root-cluster-suspected': ['cluster_files', 'cluster_ids', 'hypothesized_root', 'root_class', 'same_framing_rationale'],
    'diminishing-returns': ['signals_observed', 'latest_severity_max', 'findings_open', 'recommendation_text'],
    'injection-suspect': ['finding_id', 'pattern_category', 'field_excerpt'],
    'user-input-required': ['finding_id', 'user_question'],
    'planner-escalation': ['finding_id', 'classification', 'file', 'title'],
    'high-severity-rejection': ['finding_id', 'user_question'],
    blocked: ['blocker', 'stage']
  };
}

function reviewQuestionKinds() {
  return { 'user-input-required': REVIEW_QUESTION_KIND, 'high-severity-rejection': HIGH_SEVERITY_REJECTION_KIND };
}

function reviewerOptions(label) {
  return { agentType: REVIEWER_AGENT, schema: toAgentSchema(REVIEW_SCHEMA), label: label, phase: 'Review' };
}

function describeReviewAnswerData(answer) {
  if (answer === undefined) {
    return dataBlocksSentence();
  }
  if (answer.decided_by === 'run') {
    return dataBlocksSentence() + ' The reply in user_answer is the run\'s decision, not the user\'s.';
  }
  return dataBlocksSentence('The reply in user_answer');
}

function buildReviewPrompt(plan, run, answer) {
  const inputs = { base: plan.base, working_branch: plan.branch, trunk: run.trunk, max_iterations: maxReviewIterations(), caller_validates: true };
  if (run.approvals.length > 0) {
    inputs.approvals = run.approvals;
  }
  if (answer !== undefined) {
    inputs.user_answer = answer;
  }
  return [
    'Run your pre-PR local review loop once on the working branch as it is checked out, with the inputs in the inputs block below.',
    boundarySentence(),
    describeReviewAnswerData(answer),
    '',
    formatDataBlock('inputs', inputs)
  ].join('\n');
}

/**
 * Returns undefined for a usable review, else {problem, nextAction}: a
 * review that fails REVIEW_SCHEMA, gives user_question option ids other
 * than A, B, C and D in that order, or recommends no option of it is
 * unusable. describeUnusableResult (lib/stop.js) gives a null review, an
 * agent failure, the describeNoResult sentence and next action run_again.
 */
function describeReviewProblem(review) {
  if (!validateSchema(REVIEW_SCHEMA, review).ok || hasUnusableQuestion(review.user_question)) {
    return describeUnusableResult('The local review step returned no usable result' + describeReviewEnd(), review);
  }
  return undefined;
}

/**
 * Returns true when the option ids of question are not A, B, C and D in
 * that order, from the first, which refuses a repeated id too, or when its
 * recommendation names no option id it has. An undefined question is
 * usable.
 */
function hasUnusableQuestion(question) {
  if (question === undefined) {
    return false;
  }
  const optionIds = question.options.map((option) => option.id);
  const isInOrder = optionIds.every((optionId, index) => optionId === reviewOptionIds()[index]);
  return !isInOrder || !optionIds.includes(question.recommendation.option_id);
}

/**
 * Returns the lead and the detail line of a review stop, each built in
 * code. The detail line shows no value REVIEW_SCHEMA does not bound, and it
 * cuts none: the blocker is quoted with a limit equal to its maxLength.
 */
function reviewStopTexts(review) {
  switch (review.exit_reason) {
    case 'max-iterations-reached':
      return { lead: 'Local review reached its iteration limit' };
    case 'break-fix-break':
      return { lead: 'Local review found that a fix broke an earlier fix', detail: 'The fix conflicts with ' + describeCount(review.conflicting_findings.length, 'earlier finding') + '.' };
    case 'injection-suspect':
      return {
        lead: 'Local review flagged the text of finding ' + quoteShortFindingId(review.finding_id) + ' as a possible prompt injection of category ' + review.pattern_category,
        detail: 'Flagged text: ' + encodeUntrustedText(review.field_excerpt)
      };
    case 'blocked':
      return { lead: 'Local review was blocked', detail: 'Blocker: ' + quoteOrEmpty(review.blocker, reviewFieldTexts().blocker.bounds.maxLength) };
    default:
      throw new Error('reviewStopTexts: no texts for exit reason ' + JSON.stringify(review.exit_reason));
  }
}

function quoteOrEmpty(text, limit) {
  return quoteDiagnostic(text, limit) || encodeUntrustedText('');
}

function describeReviewStop(review, head) {
  const texts = reviewStopTexts(review);
  const lines = [texts.lead + ' on commit ' + head + ' after ' + describeCount(review.iterations_completed, 'iteration') + ', with ' + describeCount(review.findings_open, 'finding') + ' still open' + describeReviewEnd()];
  if (texts.detail !== undefined) {
    lines.push(texts.detail);
  }
  return lines.join('\n');
}

function describeReviewEnd() {
  return ', so ' + RUN_NAME + ' stopped before the pull request.';
}

function quoteShortFindingId(findingId) {
  return encodeUntrustedText(Array.from(findingId).slice(0, 8).join(''));
}

function buildRejectedFindingsBlock(note, rejectedFindings) {
  const lines = ['Local review: ' + note + '. The findings it rejected:'];
  rejectedFindings.forEach((finding) => lines.push('- ' + quoteShortFindingId(finding.finding_id)));
  return { text: lines.join('\n') };
}

function buildReviewOption(option, question) {
  const isRecommended = option.id === question.recommendation.option_id;
  const changes = readOptionChanges(option).map((entry) => ({ category: entry.category, item: encodeUntrustedText(entry.item) }));
  return { id: option.id, summary: encodeUntrustedText(option.summary), steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: 'small', value: 'medium', reversible: !isRecommended || !question.gate.irreversible, beyond_request: false, destructive: changes };
}

function readOptionChanges(option) {
  return option.destructive ?? [];
}

/**
 * Returns the brief of a local review question, built from the reviewer's
 * user_question: the encoded ask as the problem, the reviewer's options
 * with encoded summaries, the reviewer's option_id and strength with the
 * encoded why, and the reviewer's gate with safety false, since clause 3
 * is not read for a review call. The recommended option is reversible
 * unless the gate says irreversible.
 */
function buildReviewQuestionBrief(review) {
  const question = review.user_question;
  return {
    id: 'tail',
    kind: reviewQuestionKinds()[review.exit_reason],
    problem: encodeUntrustedText(question.ask),
    criticality: { level: 'medium', likelihood: 'certain', blast_radius: unshownBriefText(), if_ignored: unshownBriefText() },
    options: question.options.map((option) => buildReviewOption(option, question)),
    recommendation: { option_id: question.recommendation.option_id, strength: question.recommendation.strength, why: encodeUntrustedText(question.recommendation.why) },
    assumptions: [{ statement: unshownBriefText(), origin: 'repo', evidence: unshownBriefText() }],
    gate: { irreversible: question.gate.irreversible, architectural: question.gate.architectural, safety: false }
  };
}

function reviewCallTexts() {
  return {
    problem: 'Local review asked about a finding, and the run took the option the reviewer recommended.',
    summary: 'The option the reviewer recommended.',
    why: 'The run took it because the call is reversible and not architectural. The reviewer recorded the decision on the branch, so you can veto it before you merge.'
  };
}

/**
 * Returns a copy of a review question brief whose problem, option
 * summaries and why are the fixed reviewCallTexts(), so it holds no
 * reviewer text and every text field is code-built.
 */
function removeReviewerText(brief) {
  const texts = reviewCallTexts();
  return Object.assign({}, brief, {
    problem: texts.problem,
    options: brief.options.map((option) => Object.assign({}, option, { summary: texts.summary, destructive: readOptionChanges(option).map((entry) => ({ category: entry.category, item: unshownBriefText() })) })),
    recommendation: Object.assign({}, brief.recommendation, { why: texts.why })
  });
}

function describeReviewQuestionLead(review, head) {
  return 'Local review on commit ' + head + ', finding ' + quoteShortFindingId(review.finding_id) + ': ' + encodeUntrustedText(review.user_question.found);
}

/**
 * Lists a taken review call in run.taken, its problem the short finding id
 * and the encoded ask, and returns the answer that reruns the review gate:
 * the lead and the rendered question, the recommended option id as the
 * reply, and decided_by run. run.answerLog is not touched.
 */
function takeReviewCall(review, run, shown, lead) {
  acceptResolution({ taken: [{ brief: listReviewCall(review, shown), kind: shown.kind }], reversibleEffects: [] }, run);
  return { answer: { question: lead + '\n\n' + renderQuestions([{ brief: shown }]), reply: shown.recommendation.option_id, decided_by: 'run' } };
}

function listReviewCall(review, shown) {
  return Object.assign({}, shown, { problem: 'Local review finding ' + quoteShortFindingId(review.finding_id) + ': ' + shown.problem });
}

function askReviewQuestion(review, run) {
  const shown = buildReviewQuestionBrief(review);
  const lead = describeReviewQuestionLead(review, run.head);
  const resolution = { asks: [], taken: [] };
  if (resolveDecision(shown.kind, removeReviewerText(shown), undefined, run, resolution) === 'take') {
    return takeReviewCall(review, run, shown, lead);
  }
  return askShownReviewQuestion(resolution.asks[0], review, run, lead);
}

/**
 * Pauses on ask with the shown brief of review, its items the reviewer's
 * raw destructive list of each option, so a letter reply approves the
 * chosen option's changes (applyApprovalChoices, approvals.js).
 */
function askShownReviewQuestion(ask, review, run, lead) {
  return askTail(Object.assign({}, ask, { brief: buildReviewQuestionBrief(review), items: review.user_question.options.map(readOptionChanges) }), run, lead);
}

/**
 * Asks the user the question of review, a call the run took that local
 * review then held back at the destructive-fix gate: the call leaves
 * run.taken, and the question resolves through buildUndecidedAsk on the
 * code-built brief with gate.safety true, so it is asked, never taken.
 */
function askHeldReviewCall(review, run) {
  const shown = buildReviewQuestionBrief(review);
  const listed = listReviewCall(review, shown);
  run.taken = run.taken.filter((entry) => entry.brief.problem !== listed.problem);
  const decided = removeReviewerText(shown);
  const ask = buildUndecidedAsk(shown.kind, Object.assign({}, decided, { gate: Object.assign({}, decided.gate, { safety: true }) }), run);
  return askShownReviewQuestion(ask, review, run, 'Local review held back the call the run took. ' + describeReviewQuestionLead(review, run.head));
}

function buildDiminishingReturnsBrief(review, head) {
  return buildTailBrief({
    kind: DIMINISHING_RETURNS_EXIT_KIND,
    problem: 'Local review on commit ' + head + ' sees diminishing returns, with ' + describeCount(review.findings_open, 'finding') + ' still open. Stop fixing and hold the local review gate on this commit with those findings open?',
    goOn: 'Stop fixing and go on with the open findings.',
    strength: 'strong',
    why: 'More review rounds fix little now, and the open findings stay on the record for you before the merge.'
  });
}

function describeRejectedCount(rejectedFindings) {
  const count = rejectedFindings.length;
  if (count === 0) {
    return '';
  }
  return ', ' + count + (count === 1 ? ' finding' : ' findings') + ' rejected under recorded decisions';
}

function resolveDiminishingReturns(review, run) {
  const decided = resolveTailDecision(DIMINISHING_RETURNS_EXIT_KIND, buildDiminishingReturnsBrief(review, run.head), run);
  return isRunEnd(decided) ? decided : { held: true, note: 'diminishing returns, ' + review.findings_open + ' findings still open' + describeRejectedCount(review.rejected_findings) };
}

function buildReviewEscalationBrief(review) {
  const isCluster = review.exit_reason === 'root-cluster-suspected';
  return buildTailBrief({
    kind: isCluster ? ROOT_CLUSTER_ROUTING_KIND : PLANNER_ESCALATION_ROUTING_KIND,
    problem: (isCluster
      ? 'Local review found ' + describeCount(review.cluster_ids.length, 'finding') + ' in ' + describeCount(review.cluster_files.length, 'file') + ' that share one suspected root.'
      : 'Local review escalated finding ' + quoteShortFindingId(review.finding_id) + ' to the planner.') + ' Go back to planning, from fresh facts, for ' + (isCluster ? 'a remediation that closes the class?' : 'its remediation?'),
    goOn: 'Plan the remediation from fresh facts.',
    strength: 'strong',
    why: 'The finding needs more than a simple fix, and a remediation plan that cannot be undone, changes how the system is built or touches safety comes to you before it runs.'
  });
}

/**
 * Returns a new object holding the review's exit_reason, then each field
 * reviewExitFields() names for it that the review has, in that order.
 */
function projectReplanReview(review) {
  const projected = { exit_reason: review.exit_reason };
  for (const field of reviewExitFields()[review.exit_reason]) {
    if (Object.prototype.hasOwnProperty.call(review, field)) {
      projected[field] = review[field];
    }
  }
  return projected;
}

function requestReviewReplan(review, run) {
  const brief = buildReviewEscalationBrief(review);
  const decided = review.exit_reason === 'root-cluster-suspected'
    ? resolveTailDecision(ROOT_CLUSTER_ROUTING_KIND, brief, run)
    : resolveTailDecision(PLANNER_ESCALATION_ROUTING_KIND, brief, run);
  if (isRunEnd(decided)) {
    return decided;
  }
  const returned = 'Local review returned ' + review.exit_reason;
  if (run.replans >= maxReplans()) {
    return stopForReviewReplan({ problem: returned + ' after ' + maxReplans() + ' replans, so ' + RUN_NAME + ' stopped.' }, review, run);
  }
  run.replans += 1;
  const reason = returned + ', so plan the remediation of what the review block reports, from the fresh facts.';
  return { replan: { reason: reason, review: projectReplanReview(review) } };
}

function stopForReviewReplan(cause, review, run) {
  const stopped = stopDelivery([cause], run, [], true);
  return stopped.replan === undefined ? stopped : { replan: { reason: stopped.replan.reason, review: projectReplanReview(review) } };
}

function routeLocalReview(review, run) {
  switch (localReviewRoutes()[review.exit_reason]) {
    case 'hold':
      return { held: true, note: 'clean' + describeRejectedCount(review.rejected_findings) };
    case 'diminishing':
      return resolveDiminishingReturns(review, run);
    case 'replan':
      return requestReviewReplan(review, run);
    case 'question':
      return askReviewQuestion(review, run);
    case 'stop_replan':
      return stopForReviewReplan({ problem: describeReviewStop(review, run.head) }, review, run);
    case 'stop_rerun':
      return stopDelivery([{ problem: describeReviewStop(review, run.head) }], run, [], false);
    case 'stop':
      return stopDelivery([{ problem: describeReviewStop(review, run.head), terminal: true }], run, [], false);
    default:
      throw new Error('routeLocalReview: no route for exit reason ' + JSON.stringify(review.exit_reason));
  }
}

async function runReviewGate(run, plan, gates) {
  const count = gates.runs.review;
  const answer = gates.answer;
  const takenReview = gates.takenReview;
  gates.answer = undefined;
  gates.takenReview = undefined;
  phase('Review');
  const prompt = answer === undefined ? addResumeNote(buildReviewPrompt(plan, run), run) : buildReviewPrompt(plan, run, answer);
  const review = await agent(prompt, reviewerOptions(gateLabel('review', run, count)));
  const unusable = describeReviewProblem(review);
  const committed = await runCommitStep(run, plan, { files: [], label: gateLabel('review-commit', run, count), stepName: 'review' }, unusable === undefined ? [] : [unusable]);
  if (committed.values === undefined) {
    return committed;
  }
  const isHeldCall = takenReview !== undefined && readGateHold(review, run.approvals).holds !== undefined;
  const routed = isHeldCall ? askHeldReviewCall(takenReview, run) : routeLocalReview(review, run);
  if (routed.held) {
    gates.rejected = review.rejected_findings;
  }
  if (routed.answer !== undefined && routed.answer.decided_by === 'run') {
    gates.takenReview = review;
  }
  return routed;
}

function notConfiguredReviewLine() {
  return 'local review: the run was launched with local_review false, so the gate is not configured and does not count as held.';
}
