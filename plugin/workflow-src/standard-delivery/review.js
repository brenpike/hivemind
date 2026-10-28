/*
 * standard-delivery review.js: the local review gate of the
 * standard-delivery workflow. It holds the review schema and prompt, the
 * routes of each exit_reason, the review stops, questions and replans,
 * and the review gate step.
 *
 * Inputs
 *   run    the run state of main.js createRunState: pass, answerLog, head,
 *          trunk and taken.
 *   plan   the accepted plan, from runPlanningPass (plan.js).
 *   gates  the gate loop state of runGates (gates.js): runs.review, answer
 *          and rejected.
 *   review the local reviewer result, under REVIEW_SCHEMA.
 *
 * Outputs
 *   runReviewGate(run, plan, gates)  {held, note}, {replan}, or {result}:
 *          the pause of a review question or a blocked finish.
 *   The step, as meta.js names it:
 *   Review  a gate when configured. hivemind:local-reviewer runs its loop on
 *           the branch with base, working_branch, trunk, max_iterations and
 *           caller_validates true in its inputs block, and commits its own
 *           fixes. caller_validates true holds because a review that ends
 *           on a new commit sends the run back to the first gate, so
 *           validation runs again on that commit, and the reviewer checks
 *           only the files each fix touched. Then the commit
 *           runner runs with an empty file list, so any edit left behind
 *           stops it, and the gate holds on the commit it reports.
 *           localReviewRoutes() routes each exit_reason: clean holds,
 *           diminishing returns resolve through decide() and a take holds,
 *           a planner escalation or root cluster resolves through decide()
 *           and a take starts a new pass with replan data: the review
 *           projected to its exit_reason and the fields reviewExitFields()
 *           names for it, so rejected_findings, ledger_path and the counts
 *           never reach the planner. A question of the review,
 *           user-input-required or high-severity-rejection, carries
 *           finding_id and the reviewer's user_question: found, ask, 2 to 4
 *           options with ids A, B, C and D in that order, and a
 *           recommendation with its strength. The run pauses with the lead
 *           describeReviewQuestionLead builds, the commit, the short finding
 *           id and the encoded found, then that question as the reviewer
 *           wrote it: the encoded ask, the reviewer's options with encoded
 *           summaries and its recommendation with the encoded why. No option
 *           and no strength comes from code. The reply, kept in
 *           run.answerLog for every later plan prompt, reruns the review
 *           gate with user_answer, whose question is that lead and the
 *           question (Tail asks). Every other exit_reason stops the run
 *           blocked with one line naming the exit and its cause, the head,
 *           the iterations and the open finding count, and at most one
 *           detail line, which describeReviewStop builds in code.
 *           break-fix-break gives the count of conflicting findings and no
 *           entry text. injection-suspect names the short finding id and
 *           the category in its line, and its detail line shows the whole
 *           encoded excerpt. blocked gives the blocker, quoted with a limit
 *           equal to its maxLength, so a valid value is never cut. A review
 *           result that fails REVIEW_SCHEMA, gives option ids other than A,
 *           B, C and D in that order, or recommends no option stops the run
 *           blocked, and a null result, an agent failure, adds the
 *           describeNoResult sentence and the run_again Next line. The
 *           script sets no zoom-out trigger: the
 *           planner makes that call by judgment from the branch commits in
 *           its fresh facts, per remediation-doctrine.md.
 *           No message cuts a reviewer value: REVIEW_SCHEMA bounds each
 *           field that reaches a message or the planner, and a field with
 *           no bound is not shown. findingIdField() is the one home of the
 *           finding id shape, maxLength 64 and pattern ^[0-9a-f]{8,64}$,
 *           for finding_id and each rejected finding_id, so the short id,
 *           its first 8 characters, is always whole hex. Every list has
 *           maxItems, and buildReviewFieldSchema throws on a list entry
 *           with none. The review strings that reach no message and not
 *           the planner keep no maxLength: ledger_path, stage,
 *           prior_fix_commit, latest_severity_max, the entries of
 *           signals_fired, signals_observed and conflicting_findings, and
 *           the title and record of each rejected finding.
 *           rejected_findings lists the findings the loop rejected under recorded decisions (remediation-doctrine.md,
 *           Recorded Decisions and Repeat Findings): a held gate's note
 *           gives their code-built count, and the final complete message
 *           names each by its short id alone in a chat-only block.
 *           iterations_completed, findings_resolved and findings_open are
 *           display only: localReviewRoutes() keys only on exit_reason. The
 *           user rejected local review finding de83f9cf, which asked for
 *           bounds and consistency checks on them (ADR-0037, Amendment
 *           2026-10-25: local review counts are display only).
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Trust boundary: the overlord is a trusted relay, as in analysis-only
 *   (ADR-0036 decision 13). The local review result carries Codex-derived
 *   text: REVIEW_SCHEMA labels each such field, it reaches the planner only
 *   in a data block under the boundary sentence, it reaches the user only
 *   encoded by encodeUntrustedText, and it never reaches the pull request texts: a decision
 *   taken on a review result is shown there with a fixed problem text, and
 *   the rejected findings only as the count in the review gate note, while
 *   each one's short id shows in the final message alone. A
 *   review question shows reviewer text, encoded, so its brief can exceed
 *   a BRIEF_SCHEMA bound once encoded: decide() then asks it as
 *   malformed_brief, and its kinds always ask anyway.
 *
 * Why
 *   The review result is the one step result that carries Codex-derived
 *   text, so its routes and every place that text can reach sit together.
 */

function localReviewRoutes() {
  return {
    clean: 'hold',
    'max-iterations-reached': 'stop',
    'break-fix-break': 'stop',
    'root-cluster-suspected': 'replan',
    'diminishing-returns': 'diminishing',
    'injection-suspect': 'stop',
    'user-input-required': 'question',
    'planner-escalation': 'replan',
    'high-severity-rejection': 'question',
    blocked: 'stop'
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
  return { 'user-input-required': 'review_question', 'high-severity-rejection': 'high_severity_rejection' };
}

function findingIdField() {
  return {
    type: 'string',
    text: 'The id of the finding, taken from the fix ledger: 8 to 64 lowercase hex characters.',
    isExternal: true,
    bounds: { maxLength: 64, pattern: '^[0-9a-f]{8,64}$' }
  };
}

function reviewFieldTexts() {
  return {
    signals_fired: { type: 'list', text: 'Each break-fix signal that fired.', isExternal: false, maxItems: 10 },
    conflicting_findings: { type: 'list', text: 'Each finding the fix conflicts with.', isExternal: true, maxItems: 20 },
    prior_fix_commit: { type: 'string', text: 'The commit of the earlier fix.', isExternal: false },
    cluster_files: { type: 'list', text: 'Each file of the root cluster.', isExternal: true, maxItems: 20, itemBounds: { maxLength: 400 } },
    cluster_ids: { type: 'list', text: 'Each finding id of the root cluster.', isExternal: true, maxItems: 20, itemBounds: { maxLength: 64 } },
    hypothesized_root: { type: 'string', text: 'The root the cluster findings share.', isExternal: true, bounds: { maxLength: 300 } },
    root_class: { type: 'string', text: 'The class of that root.', isExternal: true, bounds: { maxLength: 100 } },
    same_framing_rationale: { type: 'string', text: 'Why the findings share one framing.', isExternal: true, bounds: { maxLength: 600 } },
    signals_observed: { type: 'list', text: 'Each diminishing returns signal observed.', isExternal: false, maxItems: 10 },
    latest_severity_max: { type: 'string', text: 'The highest severity of the latest findings.', isExternal: true },
    recommendation_text: { type: 'string', text: 'What the reviewer recommends, or empty.', isExternal: true, bounds: { maxLength: 200, minLength: 0 } },
    finding_id: findingIdField(),
    pattern_category: { type: 'string', text: 'The injection pattern category.', isExternal: false, bounds: { enum: ['P1', 'P2', 'P3', 'P4'] } },
    field_excerpt: { type: 'string', text: 'The excerpt of the flagged field.', isExternal: true, bounds: { maxLength: scanExcerptLimit() } },
    classification: { type: 'string', text: 'The classification of the finding.', isExternal: true, bounds: { maxLength: 100 } },
    file: { type: 'string', text: 'The file of the finding.', isExternal: true, bounds: { maxLength: 400 } },
    title: { type: 'string', text: 'The title of the finding.', isExternal: true, bounds: { maxLength: 300 } },
    user_question: { type: 'question', text: 'The question the user answers about the finding.', isExternal: true },
    blocker: { type: 'string', text: 'What blocked the review.', isExternal: true, bounds: { maxLength: 300 } },
    stage: { type: 'string', text: 'The loop stage that was blocked.', isExternal: false }
  };
}

function describeReviewField(entry) {
  return (entry.isExternal ? externalLabel() + ' ' : '') + entry.text;
}

function rejectedFindingTexts() {
  return {
    finding_id: findingIdField(),
    title: { type: 'string', text: 'The title of the finding.', isExternal: true },
    record: { type: 'string', text: 'The path and section of the recorded decision the reviewer cites.', isExternal: true }
  };
}

function buildFindingItemSchema(texts) {
  const properties = {};
  for (const [name, entry] of Object.entries(texts)) {
    properties[name] = buildReviewFieldSchema(name, entry);
  }
  return { type: 'object', additionalProperties: false, required: Object.keys(texts), properties: properties };
}

function reviewOptionIds() {
  return ['A', 'B', 'C', 'D'];
}

function buildLabelledText(maxLength, text) {
  return { type: 'string', maxLength: maxLength, description: externalLabel() + ' ' + text };
}

function buildUserQuestionSchema(description) {
  const option = {
    type: 'object',
    additionalProperties: false,
    required: ['id', 'summary'],
    properties: { id: { type: 'string', enum: reviewOptionIds(), description: 'The option id, by position: A first.' }, summary: buildLabelledText(160, 'What picking this option does.') }
  };
  const recommendation = {
    type: 'object',
    additionalProperties: false,
    required: ['option_id', 'strength', 'why'],
    description: 'The option the reviewer recommends.',
    properties: {
      option_id: { type: 'string', enum: reviewOptionIds(), description: 'The id of that option.' },
      strength: { type: 'string', enum: ['strong', 'weak', 'none'], description: 'How sure the reviewer is.' },
      why: buildLabelledText(200, 'Why that option.')
    }
  };
  return {
    type: 'object',
    description: description,
    additionalProperties: false,
    required: ['found', 'ask', 'options', 'recommendation'],
    properties: {
      found: buildLabelledText(200, 'The claim of the finding and its impact.'),
      ask: buildLabelledText(200, 'The question, on one line.'),
      options: { type: 'array', minItems: 2, maxItems: 4, description: 'The choices, 2 to 4.', items: option },
      recommendation: recommendation
    }
  };
}

function buildReviewFieldSchema(name, entry) {
  const description = describeReviewField(entry);
  if (entry.type === 'question') {
    return buildUserQuestionSchema(description);
  }
  if (entry.type === 'list') {
    if (entry.maxItems === undefined) {
      throw new Error('buildReviewFieldSchema: field ' + name + ' is a list with no maxItems');
    }
    const itemDescription = (entry.isExternal ? externalLabel() + ' ' : '') + 'One entry.';
    const items = Object.assign({ type: 'string', description: itemDescription }, entry.itemBounds);
    return { type: 'array', description: description, minItems: 1, maxItems: entry.maxItems, items: items };
  }
  if (entry.type === 'string') {
    return Object.assign({ type: 'string', description: description }, entry.bounds);
  }
  throw new Error('buildReviewFieldSchema: field ' + name + ' has type ' + JSON.stringify(entry.type) + ', which states no domain');
}

function buildReviewSchema() {
  const properties = {
    exit_reason: { type: 'string', enum: Object.keys(localReviewRoutes()), description: 'Why the review loop ended.' },
    iterations_completed: { type: 'integer', description: 'How many review iterations ran.' },
    findings_resolved: { type: 'integer', description: 'How many findings the loop fixed.' },
    findings_open: { type: 'integer', description: 'How many findings are still open.' },
    fix_commits_exist: { type: 'boolean', description: 'true when the loop committed at least one fix.' },
    ledger_path: { type: 'string', description: 'The path of the fix ledger.' },
    rejected_findings: { type: 'array', description: externalLabel() + ' Every finding the loop rejected under a recorded decision, empty when none.', maxItems: 50, items: buildFindingItemSchema(rejectedFindingTexts()) }
  };
  for (const [name, entry] of Object.entries(reviewFieldTexts())) {
    properties[name] = buildReviewFieldSchema(name, entry);
  }
  const variants = {};
  for (const [exitReason, fields] of Object.entries(reviewExitFields())) {
    variants[exitReason] = { required: fields, optional: [] };
  }
  return buildTaggedSchema({
    tag: 'exit_reason',
    properties: properties,
    required: ['exit_reason', 'iterations_completed', 'findings_resolved', 'findings_open', 'fix_commits_exist', 'ledger_path', 'rejected_findings'],
    variants: variants
  });
}

function reviewerOptions(label) {
  return { agentType: REVIEWER_AGENT, schema: toAgentSchema(REVIEW_SCHEMA), label: label, phase: 'Review' };
}

function buildReviewPrompt(plan, trunk, answer) {
  const inputs = { base: plan.base, working_branch: plan.branch, trunk: trunk, max_iterations: maxReviewIterations(), caller_validates: true };
  if (answer !== undefined) {
    inputs.user_answer = answer;
  }
  return [
    'Run your pre-PR local review loop once on the working branch as it is checked out, with the inputs in the inputs block below.',
    boundarySentence(),
    dataBlocksSentence(answer === undefined ? undefined : 'The reply in user_answer'),
    '',
    formatDataBlock('inputs', inputs)
  ].join('\n');
}

/**
 * Returns undefined for a usable review, else {problem, nextAction}: a
 * review that fails REVIEW_SCHEMA, gives user_question option ids other
 * than A, B, C and D in that order, or recommends no option of it is
 * unusable, and a null review, an agent failure, adds the describeNoResult
 * sentence with next action run_again.
 */
function describeReviewProblem(review) {
  const problem = 'The local review step returned no usable result, so ' + RUN_NAME + ' stopped before the pull request.';
  if (!validateSchema(REVIEW_SCHEMA, review).ok || hasUnusableQuestion(review.user_question)) {
    return describeUnusableResult(problem, review);
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
  const lines = [texts.lead + ' on commit ' + head + ' after ' + describeCount(review.iterations_completed, 'iteration') + ', with ' + describeCount(review.findings_open, 'finding') + ' still open, so ' + RUN_NAME + ' stopped before the pull request.'];
  if (texts.detail !== undefined) {
    lines.push(texts.detail);
  }
  return lines.join('\n');
}

function quoteShortFindingId(findingId) {
  return encodeUntrustedText(Array.from(findingId).slice(0, 8).join(''));
}

function buildRejectedFindingsBlock(note, rejectedFindings) {
  const lines = ['Local review: ' + note + '. The findings it rejected:'];
  rejectedFindings.forEach((finding) => lines.push('- ' + quoteShortFindingId(finding.finding_id)));
  return { text: lines.join('\n') };
}

function buildReviewOption(option) {
  return { id: option.id, summary: encodeUntrustedText(option.summary), steel_man: unshownBriefText(), straw_man: unshownBriefText(), effort: 'small', value: 'medium', reversible: true };
}

/**
 * Returns the brief of a local review question, built from the reviewer's
 * user_question: the encoded ask as the problem, the reviewer's options
 * with encoded summaries, and the reviewer's option_id and strength with
 * the encoded why.
 */
function buildReviewQuestionBrief(review) {
  const question = review.user_question;
  return {
    id: 'tail',
    kind: reviewQuestionKinds()[review.exit_reason],
    problem: encodeUntrustedText(question.ask),
    criticality: { level: 'medium', likelihood: 'certain', blast_radius: unshownBriefText(), if_ignored: unshownBriefText() },
    options: question.options.map(buildReviewOption),
    recommendation: { option_id: question.recommendation.option_id, strength: question.recommendation.strength, why: encodeUntrustedText(question.recommendation.why) },
    assumptions: [{ statement: unshownBriefText(), origin: 'repo', evidence: unshownBriefText() }],
    gate: { irreversible: false, architectural: false, safety: false }
  };
}

function describeReviewQuestionLead(review, head) {
  return 'Local review on commit ' + head + ', finding ' + quoteShortFindingId(review.finding_id) + ': ' + encodeUntrustedText(review.user_question.found);
}

function askReviewQuestion(review, run) {
  const resolution = { asks: [], taken: [] };
  resolveDecision(reviewQuestionKinds()[review.exit_reason], buildReviewQuestionBrief(review), undefined, run, resolution);
  return askTail(resolution.asks[0], run, describeReviewQuestionLead(review, run.head));
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
    problem: isCluster
      ? 'Local review found ' + describeCount(review.cluster_ids.length, 'finding') + ' in ' + describeCount(review.cluster_files.length, 'file') + ' that share one suspected root. Go back to planning, from fresh facts, for a remediation that closes the class?'
      : 'Local review escalated finding ' + quoteShortFindingId(review.finding_id) + ' to the planner. Go back to planning, from fresh facts, for its remediation?',
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
  if (run.replans >= maxReplans()) {
    return { result: finishDeliveryBlocked('Local review returned ' + review.exit_reason + ' after ' + maxReplans() + ' replans, so ' + RUN_NAME + ' stopped.', run) };
  }
  run.replans += 1;
  const reason = 'Local review returned ' + review.exit_reason + ', so plan the remediation of what the review block reports, from the fresh facts.';
  return { replan: { reason: reason, review: projectReplanReview(review) } };
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
    case 'stop':
      return { result: finishDeliveryBlocked(describeReviewStop(review, run.head), run) };
    default:
      throw new Error('routeLocalReview: no route for exit reason ' + JSON.stringify(review.exit_reason));
  }
}

async function runReviewGate(run, plan, gates) {
  const count = gates.runs.review;
  const answer = gates.answer;
  gates.answer = undefined;
  phase('Review');
  const prompt = answer === undefined ? addResumeNote(buildReviewPrompt(plan, run.trunk), run) : buildReviewPrompt(plan, run.trunk, answer);
  const review = await agent(prompt, reviewerOptions(gateLabel('review', run, count)));
  const committed = await runCommitStep(run, plan, [], gateLabel('review-commit', run, count), 'review');
  if (committed.problem !== undefined) {
    return { result: finishDeliveryBlocked(committed.problem, run, committed.nextAction) };
  }
  const unusable = describeReviewProblem(review);
  if (unusable !== undefined) {
    return { result: finishDeliveryBlocked(unusable.problem, run, unusable.nextAction) };
  }
  const routed = routeLocalReview(review, run);
  if (routed.held) {
    gates.rejected = review.rejected_findings;
  }
  return routed;
}

function notConfiguredReviewLine() {
  return 'local review: the run was launched with local_review false, so the gate is not configured and does not count as held.';
}
