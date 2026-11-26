/*
 * standard-delivery review.js: the local review gate of the standard-delivery
 * workflow. It holds the review prompt, the routes of each exit_reason, the
 * review stops, questions and replans, and the review gate step. Its result
 * schema lives in review-schema.js.
 *
 * Inputs
 *   run    the run state of main.js createRunState: pass, decisions,
 *          answerLog, head, trunk, approvals, taken, rejected, undone, open,
 *          waits, replans, reviewReplans, repeatClusterAsked, and, set only
 *          here, resumeLedger, true from a review replan or a rerun of a
 *          blocked review until the next review run, and reviewSkip
 *          (gates.js): a skip's skip_reason, or user-reply on a reply of B.
 *   plan   the accepted plan, from runPlanningPass (plan.js).
 *   gates  the gate loop state of runGates (lib/gates.js): runs.review, answer
 *          and takenReview, which only this module sets and reads: the review
 *          whose call the run took, kept for the next review run alone.
 *   review the local reviewer result, under REVIEW_SCHEMA.
 *
 * Outputs
 *   runReviewGate(run, plan, gates)  {held, note}, {held: false} on a skip,
 *          {replan}, {draft: reason} at a loop cap, so the pull request opens
 *          as a draft, {result}: a pause, a wait or a blocked finish, or
 *          {rerun: true} after a wait or a reply to a stop of its commit step
 *          or a blocked review: local review runs again, its commit runner
 *          reading the head.
 *   The step, as meta.js names it:
 *   Review  a gate when configured. hivemind:local-reviewer runs its loop on
 *           the branch with base, working_branch, trunk, max_iterations and
 *           caller_validates true in its inputs block, and commits its own
 *           fixes, checking only the files each fix touched: a review that
 *           ends on a new commit sends the run back to the first gate, so
 *           validation runs again on it. Then the commit runner runs with an
 *           empty file list and reviewCommitTexts(), so any edit left behind
 *           stops it, and the gate holds on the commit it reports.
 *           localReviewRoutes() routes each exit_reason, and only it: clean
 *           holds; skipped, a review that could not run, sets run.reviewSkip
 *           and returns {held: false}, so configuredGateIds (gates.js) drops
 *           local review for the rest of the run and the pull request opens,
 *           its gates part and the complete message naming the skip
 *           (describeGateSkip, gates.js), never held or not configured;
 *           diminishing returns resolve through decide() and a take holds; a
 *           planner escalation or root cluster resolves through decide(), and
 *           a take or a reply, counted in run.replans and run.reviewReplans,
 *           starts a new pass with replan data: the review projected to its
 *           exit_reason and the fields reviewExitFields() names for it, so no
 *           other field reaches the planner.
 *           A question of the review, user-input-required or
 *           high-severity-rejection, carries finding_id and user_question:
 *           found, ask, 2 to 4 options with ids A, B, C and D in that order,
 *           a recommendation with its strength, and the gate: irreversible
 *           and architectural. Per decision-autonomy.md (Review Calls),
 *           decide() reads the code-built brief of removeReviewerText, safety
 *           false because clause 3 is not read, so it takes an agreed call
 *           that is reversible, not architectural and lists no destructive
 *           change, and asks every other one: it reads each destructive entry
 *           by its category, its item unshownBriefText(), so a recommended
 *           option that lists a change asks gate_safety. An ask's items are
 *           the raw lists, so a letter reply approves the chosen option's
 *           changes (applyApprovalChoices, approvals.js). When the review run
 *           right after a take returns a hold readGateHold (approvals.js)
 *           reads, askHeldReviewCall removes that call from run.taken and asks
 *           it of the user through buildUndecidedAsk with gate.safety true.
 *           The inputs block carries run.approvals as approvals and
 *           listAnswerEntries(run) (main.js) as answers, each only when not
 *           empty. A take never pauses or touches run.answerLog: takeReviewCall
 *           lists it in run.taken and reruns the gate with user_answer
 *           decided_by run, replying the recommended option id. An ask pauses
 *           with the lead describeReviewQuestionLead builds and the reviewer's
 *           question, each reviewer text encoded, no option or strength from
 *           code; the reply, kept in run.answerLog, reruns the review gate with
 *           user_answer (askTail, tails.js).
 *           Every other exit_reason stops with one line naming the exit and
 *           its cause, the head, the iterations and the open finding count,
 *           and at most one detail line (describeReviewStop): break-fix-break
 *           gives the count of conflicting findings, injection-suspect the
 *           short finding id and category in its line and the whole encoded
 *           excerpt, blocked the blocker quoted with a limit equal to its
 *           maxLength. max-iterations-reached and break-fix-break return
 *           {draft} with the lead, the head and the open finding count (issue
 *           549); an escalation or root cluster at maxReplans(), or at
 *           maxReviewReplans() unless the zoom-out trigger holds, returns
 *           {draft} naming that limit before decide() reads it. blocked with
 *           retry_minutes 1 or more waits (waitForService) while the wait fits
 *           the waits left, maxServiceWaits() of at most maxWaitMinutes()
 *           each, and the resume args fit: with no reply it pauses through
 *           pauseForRetry (lib/result.js), and the reply, logged with settled
 *           [] and decided_by run, runs local review again; past the waits it
 *           returns {draft}. blocked with no retry_minutes asks one fix_cause
 *           step_stop question (askBlockedReview): A, take the stopped step
 *           again, or a reply in the user's own words runs local review again,
 *           and B, read by letter, sets run.reviewSkip to user-reply, so local
 *           review is skipped as above. injection-suspect is terminal. Either
 *           rerun of a blocked review, and the next review run after a review
 *           replan, gets fixLedgerPath(plan.branch) as resume_from_ledger,
 *           once, keeping its break-fix and root-cluster history; local review
 *           counts only the iterations after the ledger's last replan exit, so
 *           a rerun of a blocked review keeps its iteration count and the run
 *           after a review replan does not. A result that fails REVIEW_SCHEMA
 *           or has an unusable question (describeReviewProblem) ends the run
 *           blocked with a report lead, read before the commit runner, which
 *           takes it as its step cause, so a commit stop never hides it; a null
 *           result, an agent failure, gets describeUnusableResult (lib/stop.js).
 *           The zoom-out trigger of requestReviewReplan asks the approach
 *           question, gate architectural, once a run: the next returns {draft}
 *           (SD-87). Its ask pins the encoded root and open titles
 *           (buildFindingsData) only when its pause shows them whole
 *           (fitPinned), and a reply of B adds that choice
 *           (describeApproachChange) to the replan reason. No message cuts a
 *           reviewer value: REVIEW_SCHEMA bounds each field that reaches a
 *           message or the planner, and an unbounded field is not shown.
 *           keepReviewLists keeps each new finding_id of a usable review's
 *           rejected_findings, rejected under recorded decisions, and
 *           undone_fixes, whose failed fix the loop undid, in run.rejected and
 *           run.undone, and sets run.open, before its route: a held gate's
 *           note counts each list, and the complete message and the pull
 *           request record name each finding by its short id alone.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of main.js:
 *   the build bundles this module into it, so a row can name a function of
 *   this module.
 *   Trust boundary: the overlord is a trusted relay, as in analysis-only
 *   (ADR-0036 decision 13). Review-tool text, each field REVIEW_SCHEMA
 *   labels, reaches the planner only in a data block under the boundary
 *   sentence, local review only inside the inputs data block as answers, the
 *   user only encoded by encodeUntrustedText, and the pull request texts only
 *   through neutralizePullRequestText (lib/pr.js): a routing decision shows a
 *   fixed problem text, a taken call its compact line with no why, and the
 *   rejected and undone findings their short ids (buildRejectedFindingsBlock,
 *   lib/record.js). decide() reads only the code-built brief of
 *   removeReviewerText, which always fits BRIEF_SCHEMA, so a valid review
 *   never asks as malformed_brief. A review run resumes the fix ledger path
 *   fixLedgerPath(plan.branch), built in code, never the reviewer's one.
 *
 * Why
 *   The review result is the one step result that carries review-tool
 *   text, so its routes and every place that text can reach sit together.
 */

function localReviewRoutes() {
  return {
    clean: 'hold',
    'max-iterations-reached': 'draft',
    'break-fix-break': 'draft',
    'root-cluster-suspected': 'replan',
    'diminishing-returns': 'diminishing',
    'injection-suspect': 'stop',
    'user-input-required': 'question',
    'planner-escalation': 'replan',
    'high-severity-rejection': 'question',
    blocked: 'stop_rerun',
    skipped: 'skip'
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
    blocked: ['blocker', 'stage'],
    skipped: ['skip_reason']
  };
}

/**
 * Returns the per-branch fix ledger path of plugin/agents/local-reviewer.md
 * (Fix Ledger & Safety): one flat file per branch, each / written ~.
 */
function fixLedgerPath(branch) {
  return '.hivemind/review-loop/' + branch.replace(/\//g, '~') + '.yaml';
}

function reviewQuestionKinds() {
  return { 'user-input-required': REVIEW_QUESTION_KIND, 'high-severity-rejection': HIGH_SEVERITY_REJECTION_KIND };
}

function describeReviewAnswerData(answer) {
  if (answer?.decided_by === 'run') {
    return dataBlocksSentence() + ' The reply in user_answer is the run\'s decision, not the user\'s.';
  }
  return dataBlocksSentence(answer === undefined ? undefined : 'The reply in user_answer');
}

function buildReviewPrompt(plan, run, answer) {
  const inputs = { base: plan.base, working_branch: plan.branch, trunk: run.trunk, max_iterations: maxReviewIterations(), caller_validates: true };
  if (run.approvals.length > 0) {
    inputs.approvals = run.approvals;
  }
  const answers = listAnswerEntries(run);
  if (answers.length > 0) {
    inputs.answers = answers;
  }
  if (answer !== undefined) {
    inputs.user_answer = answer;
  }
  /*
   * A rerun after a blocked review, or the review after a review replan,
   * resumes its fix ledger, so its break-fix and root-cluster history
   * carry over. The path is fixLedgerPath(plan.branch), built in code from
   * the checked plan branch, never the reviewer's ledger_path.
   */
  if (run.resumeLedger) {
    inputs.resume_from_ledger = fixLedgerPath(plan.branch);
    run.resumeLedger = false;
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
    return describeUnusableResult('The local review step returned no usable result' + describePullRequestStop(), review);
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
  return !optionIds.every((optionId, index) => optionId === reviewOptionIds()[index]) || !optionIds.includes(question.recommendation.option_id);
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

function describeReviewStop(review, head) {
  const detail = reviewStopTexts(review).detail;
  const line = describeReviewOpen(review, head, ' after ' + describeCount(review.iterations_completed, 'iteration')) + describePullRequestStop();
  return detail === undefined ? line : line + '\n' + detail;
}

/**
 * Returns the lead of review on commit head, then after, then the count of
 * findings still open.
 */
function describeReviewOpen(review, head, after) {
  return reviewStopTexts(review).lead + ' on commit ' + head + after + ', with ' + describeCount(review.findings_open, 'finding') + ' still open';
}

function buildReviewOption(option, question) {
  const isRecommended = option.id === question.recommendation.option_id;
  const changes = readOptionChanges(option).map((entry) => ({ category: entry.category, item: encodeUntrustedText(entry.item) }));
  return { ...buildBriefOption(option.id, encodeUntrustedText(option.summary), 'small', 'medium', !isRecommended || !question.gate.irreversible), destructive: changes };
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
    criticality: buildUnshownCriticality(),
    options: question.options.map((option) => buildReviewOption(option, question)),
    recommendation: { option_id: question.recommendation.option_id, strength: question.recommendation.strength, why: encodeUntrustedText(question.recommendation.why) },
    assumptions: buildUnshownAssumptions(),
    gate: { irreversible: question.gate.irreversible, architectural: question.gate.architectural, safety: false }
  };
}

/**
 * Returns a copy of a review question brief whose problem, option
 * summaries, destructive items and why are unshownBriefText() (plan.js),
 * so it holds no reviewer text and every text field is code-built. Only
 * decide() reads it, and no message shows it.
 */
function removeReviewerText(brief) {
  return {
    ...brief,
    problem: unshownBriefText(),
    options: brief.options.map((option) => ({ ...option, summary: unshownBriefText(), destructive: readOptionChanges(option).map((entry) => ({ category: entry.category, item: unshownBriefText() })) })),
    recommendation: { ...brief.recommendation, why: unshownBriefText() }
  };
}

function describeReviewCommit(head) {
  return 'Local review on commit ' + head;
}

function describeReviewQuestionLead(review, head) {
  return describeReviewCommit(head) + ', finding ' + quoteShortFindingId(review.finding_id) + ': ' + encodeUntrustedText(review.user_question.found);
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
  return { ...shown, problem: 'Local review finding ' + quoteShortFindingId(review.finding_id) + ': ' + shown.problem };
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
  return askTail({ ...ask, brief: buildReviewQuestionBrief(review), items: review.user_question.options.map(readOptionChanges) }, run, lead);
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
  const ask = buildUndecidedAsk(shown.kind, { ...decided, gate: { ...decided.gate, safety: true } }, run);
  return askShownReviewQuestion(ask, review, run, 'Local review held back the call the run took. ' + describeReviewQuestionLead(review, run.head));
}

function buildDiminishingReturnsBrief(review, head) {
  return buildTailBrief({
    kind: DIMINISHING_RETURNS_EXIT_KIND,
    problem: describeReviewCommit(head) + ' sees diminishing returns, with ' + describeCount(review.findings_open, 'finding') + ' still open. Stop fixing and hold the local review gate on this commit with those findings open?',
    goOn: 'Stop fixing and go on with the open findings.',
    strength: 'strong',
    why: 'More review rounds fix little now, and the open findings stay on the record for you before the merge.'
  });
}

function describeFindingCount(findings, tail) {
  return findings.length === 0 ? '' : ', ' + describeCount(findings.length, 'finding') + tail;
}

/**
 * Returns the code-built counts a held gate's note ends with: the findings
 * of run.rejected, then of run.undone, each left out when empty.
 */
function describeHeldCounts(run) {
  return describeFindingCount(run.rejected, ' rejected under recorded decisions') + describeFindingCount(run.undone, ' whose failed fix was undone');
}

function keepNewFindings(kept, findings) {
  for (const finding of findings) {
    if (!kept.some((entry) => entry.finding_id === finding.finding_id)) {
      kept.push(finding);
    }
  }
}

function keepReviewLists(run, review) {
  keepNewFindings(run.rejected, review.rejected_findings);
  keepNewFindings(run.undone, review.undone_fixes);
  run.open = review.open_findings;
}

function resolveDiminishingReturns(review, run) {
  const decided = resolveTailDecision(DIMINISHING_RETURNS_EXIT_KIND, buildDiminishingReturnsBrief(review, run.head), run);
  return isRunEnd(decided) ? decided : { held: true, note: 'diminishing returns, ' + review.findings_open + ' findings still open' + describeHeldCounts(run) };
}

function buildReviewEscalationBrief(review, isRepeat) {
  const isCluster = review.exit_reason === 'root-cluster-suspected';
  const found = isCluster ? 'Local review found ' + describeCount(review.cluster_ids.length, 'finding') + ' in ' + describeCount(review.cluster_files.length, 'file') + ' that share one suspected root.' : 'Local review escalated finding ' + quoteShortFindingId(review.finding_id) + ' to the planner.';
  const brief = buildTailBrief({
    kind: isCluster ? ROOT_CLUSTER_ROUTING_KIND : PLANNER_ESCALATION_ROUTING_KIND,
    problem: found + ' Go back to planning, from fresh facts, for ' + (isCluster ? 'a remediation that closes the class?' : 'its remediation?'),
    goOn: 'Plan the remediation from fresh facts.',
    strength: 'strong',
    why: 'The finding needs more than a simple fix, and a remediation plan that cannot be undone, changes how the system is built or touches safety comes to you before it runs.'
  });
  return isRepeat ? { ...brief, problem: found + ' The last remediation changed those files.', ...buildApproachChoice(), gate: { ...brief.gate, architectural: true } } : brief;
}

/**
 * Returns a new object holding the review's exit_reason, then each field
 * reviewExitFields() names for it that the review has, in that order.
 */
function projectReplanReview(review) {
  const projected = { exit_reason: review.exit_reason };
  for (const field of reviewExitFields()[review.exit_reason]) {
    if (Object.hasOwn(review, field)) {
      projected[field] = review[field];
    }
  }
  return projected;
}

/**
 * Returns {replan}, {draft} or a pause. The zoom-out trigger is a root
 * cluster, the one review with cluster_files, after a review replan, whose
 * cluster_files names a step file of plan, the plan the run just ran. The
 * run asks it once: a later trigger returns {draft}.
 */
function requestReviewReplan(review, run, plan) {
  const returned = 'Local review returned ' + review.exit_reason;
  if (run.replans >= maxReplans()) {
    return { draft: returned + ' after ' + maxReplans() + ' replans.' };
  }
  const isRepeat = run.reviewReplans >= 1 && review.cluster_files?.some((file) => plan.steps.some((step) => step.files.includes(file)));
  if (isRepeat ? run.repeatClusterAsked : run.reviewReplans >= maxReviewReplans()) {
    return { draft: returned + (isRepeat ? ' on the same class after a change of approach.' : ' after ' + describeCount(maxReviewReplans(), 'review replan') + '.') };
  }
  const brief = buildReviewEscalationBrief(review, isRepeat);
  run.repeatClusterAsked = run.repeatClusterAsked || isRepeat === true;
  const decided = resolveTailDecision(brief.kind, brief, run, isRepeat ? buildFindingsData(review.hypothesized_root, run.open) : undefined);
  if (decided.result !== undefined) {
    return decided;
  }
  run.replans += 1;
  run.reviewReplans += 1;
  return { replan: { reason: returned + ', so plan the remediation of what the review block reports, from the fresh facts.' + (isRepeat ? describeApproachChange(run.answerLog[run.answerLog.length - 1].reply, brief) : ''), review: projectReplanReview(review) } };
}

/**
 * Waits out the outside service a blocked review names, when its
 * retry_minutes fits the waits the run has left and the resume args fit:
 * with no reply for the next round, pauses through pauseForRetry for at
 * most maxWaitMinutes(); with one, logs it as the run's own wait, settled
 * [] and decided_by run, and returns {rerun: true}. Else returns {draft}.
 */
function waitForService(review, run) {
  const resumeArgs = buildResumeArgs(run.answerLog.map((entry) => entry.reply), BUILD_ID);
  /*
   * INVARIANT: retry_minutes is 1 or more (routeLocalReview), so the waits
   * left bound it to 0 once run.waits reaches maxServiceWaits().
   */
  if (review.retry_minutes > (maxServiceWaits() - run.waits) * maxWaitMinutes() || !canCarry(resumeArgs)) {
    return { draft: 'Local review was blocked by an outside service, past the waits the run makes.' };
  }
  const minutes = Math.min(review.retry_minutes, maxWaitMinutes());
  const texts = reviewStopTexts(review);
  const lead = texts.lead + ' on commit ' + run.head + ', so ' + RUN_NAME + ' waits ' + describeCount(minutes, 'minute') + '.';
  const reply = takeNextReply(run, run.answerLog.length + 1);
  if (reply === undefined) {
    return { result: pauseForRetry({ resumeArgs: resumeArgs, retryMinutes: minutes, blocks: [{ text: lead }, { text: texts.detail }] }) };
  }
  run.answerLog.push(buildAnswerEntry({ question: lead, labels: [], reply: reply, decided_by: 'run' }));
  run.waits += 1;
  return { rerun: true };
}

/**
 * Asks the fix_cause step_stop question of a blocked review with no retry
 * time, led by describeReviewStop, on buildStepStopBrief(false) with the
 * skip as its option B. A reply of B, read by readReplyChoices, sets
 * run.reviewSkip to user-reply and returns {held: false}; any other reply
 * returns {rerun: true}.
 */
function askBlockedReview(review, run) {
  const ask = { ...buildUndecidedAsk(STEP_STOP_KIND, buildStepStopBrief(false, 'Skip local review for this run.'), run), stop: 'fix_cause' };
  const asked = askTail(ask, run, describeStopLead([{ problem: describeReviewStop(review, run.head) }], []));
  if (asked.answer === undefined) {
    return asked;
  }
  if (!readReplyChoices(asked.answer.reply, [ask]).some((choice) => choice.optionIndex === 1)) {
    return { rerun: true };
  }
  run.reviewSkip = 'user-reply';
  run.resumeLedger = false;
  return { held: false };
}

function routeLocalReview(review, run, plan) {
  switch (localReviewRoutes()[review.exit_reason]) {
    case 'hold':
      return { held: true, note: 'clean' + describeHeldCounts(run) };
    case 'diminishing':
      return resolveDiminishingReturns(review, run);
    case 'replan':
      run.resumeLedger = true;
      return requestReviewReplan(review, run, plan);
    case 'question':
      return askReviewQuestion(review, run);
    case 'draft':
      return { draft: describeReviewOpen(review, run.head, '') + '.' };
    case 'stop_rerun':
      run.resumeLedger = true;
      return review.retry_minutes >= 1 ? waitForService(review, run) : askBlockedReview(review, run);
    case 'stop':
      return stopDelivery([{ problem: describeReviewStop(review, run.head), terminal: true }], run);
    case 'skip':
      run.reviewSkip = review.skip_reason;
      return { held: false };
    default:
      throw new Error('routeLocalReview: no route for exit reason ' + JSON.stringify(review.exit_reason));
  }
}

/**
 * Returns the commit texts of the local review commit, in the shape
 * commitStepTexts (lib/commit.js) gives: purpose, noun and subject.
 */
function reviewCommitTexts() {
  return { purpose: 'the local review that just ran, with an empty file list', noun: 'the local review', subject: 'apply the local review fixes' };
}

async function runReviewGate(run, plan, gates) {
  const count = gates.runs.review;
  const { answer, takenReview } = gates;
  gates.answer = undefined;
  gates.takenReview = undefined;
  phase('Review');
  const built = buildReviewPrompt(plan, run, answer);
  const prompt = answer === undefined ? addResumeNote(built, run) : built;
  const review = await agent(prompt, { agentType: REVIEWER_AGENT, schema: toAgentSchema(REVIEW_SCHEMA), label: gateLabel('review', run, count), phase: 'Review' });
  const unusable = describeReviewProblem(review);
  if (unusable === undefined) {
    keepReviewLists(run, review);
  }
  const committed = await runCommitStep(run, plan, { files: [], label: gateLabel('review-commit', run, count), texts: reviewCommitTexts() }, unusable === undefined ? [] : [unusable]);
  if (committed.values === undefined) {
    return committed;
  }
  const isHeldCall = takenReview !== undefined && readGateHold(review, run.approvals).holds !== undefined;
  const routed = isHeldCall ? askHeldReviewCall(takenReview, run) : routeLocalReview(review, run, plan);
  if (routed.answer?.decided_by === 'run') {
    gates.takenReview = review;
  }
  return routed;
}

function notConfiguredReviewLine() {
  return 'local review: launched with local_review false, so the gate is not configured and does not count as held.';
}
