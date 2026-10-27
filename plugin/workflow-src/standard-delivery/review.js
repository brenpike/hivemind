/*
 * standard-delivery review.js: the local review gate of the
 * standard-delivery workflow. It holds the review schema and prompt, the
 * routes of each exit_reason, the review stops, questions and replans,
 * and the review gate step.
 *
 * Inputs
 *   run    the run state of main.js createRunState: pass, replies, head,
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
 *           the branch with base, working_branch, trunk and max_iterations
 *           in its inputs block, and commits its own fixes. Then the commit
 *           runner runs with an empty file list, so any edit left behind
 *           stops it, and the gate holds on the commit it reports.
 *           localReviewRoutes() routes each exit_reason: clean holds,
 *           diminishing returns resolve through decide() and a take holds,
 *           a planner escalation or root cluster resolves through decide()
 *           and a take starts a new pass with replan data: the review
 *           projected to its exit_reason and the fields reviewExitFields()
 *           names for it, so rejected_findings, open_findings, ledger_path
 *           and the counts never reach the planner. When the review that
 *           escalated ran with user_answer, the replan carries that answer
 *           too, and the plan prompt shows it in an answer block next to
 *           the review block. A question of the review pauses the run, and
 *           the reply reruns the review gate with user_answer (Tail asks).
 *           Every other exit_reason stops the run blocked. The script sets
 *           no zoom-out trigger: the
 *           planner makes that call by judgment from the branch commits in
 *           its fresh facts, per remediation-doctrine.md.
 *           rejected_findings lists the findings the loop rejected under recorded decisions (remediation-doctrine.md,
 *           Recorded Decisions and Repeat Findings): a held gate's note
 *           gives their code-built count, and the final complete message
 *           names each in a chat-only detail block.
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
 *   each one's short id, title and record shows in the final message alone.
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
    'user-input-required': ['finding_id', 'title', 'question', 'recommendation_text', 'open_findings'],
    'planner-escalation': ['finding_id', 'classification', 'file', 'title'],
    'high-severity-rejection': ['finding_id', 'title', 'rationale_text', 'recommendation_text', 'open_findings'],
    blocked: ['blocker', 'stage']
  };
}

function reviewQuestionKinds() {
  return { 'user-input-required': 'review_question', 'high-severity-rejection': 'high_severity_rejection' };
}

function reviewFieldTexts() {
  return {
    signals_fired: { type: 'list', text: 'Each break-fix signal that fired.', isExternal: false },
    conflicting_findings: { type: 'list', text: 'Each finding the fix conflicts with.', isExternal: true },
    prior_fix_commit: { type: 'string', text: 'The commit of the earlier fix.', isExternal: false },
    cluster_files: { type: 'list', text: 'Each file of the root cluster.', isExternal: true },
    cluster_ids: { type: 'list', text: 'Each finding id of the root cluster.', isExternal: true },
    hypothesized_root: { type: 'string', text: 'The root the cluster findings share.', isExternal: true },
    root_class: { type: 'string', text: 'The class of that root.', isExternal: true },
    same_framing_rationale: { type: 'string', text: 'Why the findings share one framing.', isExternal: true },
    signals_observed: { type: 'list', text: 'Each diminishing returns signal observed.', isExternal: false },
    latest_severity_max: { type: 'string', text: 'The highest severity of the latest findings.', isExternal: true },
    recommendation_text: { type: 'string', text: 'What the reviewer recommends, or empty.', isExternal: true, bounds: { maxLength: 200, minLength: 0 } },
    finding_id: { type: 'string', text: 'The id of the finding.', isExternal: true },
    pattern_category: { type: 'string', text: 'The injection pattern category.', isExternal: false },
    field_excerpt: { type: 'string', text: 'The excerpt of the flagged field.', isExternal: true },
    classification: { type: 'string', text: 'The classification of the finding.', isExternal: true },
    file: { type: 'string', text: 'The file of the finding.', isExternal: true },
    title: { type: 'string', text: 'The title of the finding.', isExternal: true },
    question: { type: 'string', text: 'The ask to the user.', isExternal: true, bounds: { maxLength: 300 } },
    rationale_text: { type: 'string', text: 'Why the reviewer rejects the finding.', isExternal: true, bounds: { maxLength: 300 } },
    open_findings: { type: 'findings', text: 'Every finding still open in the fix ledger.', isExternal: true },
    blocker: { type: 'string', text: 'What blocked the review.', isExternal: true, bounds: { maxLength: 300 } },
    stage: { type: 'string', text: 'The loop stage that was blocked.', isExternal: false }
  };
}

function describeReviewField(entry) {
  return (entry.isExternal ? externalLabel() + ' ' : '') + entry.text;
}

function openFindingTexts() {
  return {
    finding_id: 'The id of the finding.',
    severity: 'The severity of the finding.',
    summary: 'What is wrong, in one plain sentence for the user.',
    recommendation: 'What the reviewer recommends for the finding, in one plain sentence, or empty.'
  };
}

function rejectedFindingTexts() {
  return {
    finding_id: 'The id of the finding.',
    title: 'The title of the finding.',
    record: 'The path and section of the recorded decision the reviewer cites.'
  };
}

function buildFindingItemSchema(texts) {
  const properties = {};
  for (const [name, text] of Object.entries(texts)) {
    properties[name] = { type: 'string', description: externalLabel() + ' ' + text };
  }
  return { type: 'object', additionalProperties: false, required: Object.keys(texts), properties: properties };
}

function buildOpenFindingSchema() {
  const schema = buildFindingItemSchema(openFindingTexts());
  schema.properties.summary.maxLength = 200;
  schema.properties.recommendation.maxLength = 200;
  schema.properties.recommendation.minLength = 0;
  return schema;
}

function buildReviewFieldSchema(name, entry) {
  const description = describeReviewField(entry);
  if (entry.type === 'findings') {
    return { type: 'array', description: description, minItems: 1, items: buildOpenFindingSchema() };
  }
  if (entry.type === 'list') {
    const itemDescription = (entry.isExternal ? externalLabel() + ' ' : '') + 'One entry.';
    return { type: 'array', description: description, minItems: 1, items: { type: 'string', description: itemDescription } };
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
    rejected_findings: { type: 'array', description: externalLabel() + ' Every finding the loop rejected under a recorded decision, empty when none.', items: buildFindingItemSchema(rejectedFindingTexts()) }
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
  const inputs = { base: plan.base, working_branch: plan.branch, trunk: trunk, max_iterations: maxReviewIterations() };
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

function describeReviewProblem(review) {
  if (!validateSchema(REVIEW_SCHEMA, review).ok) {
    return 'The local review step returned no usable result, so ' + RUN_NAME + ' stopped before the pull request.';
  }
  return undefined;
}

function reviewStopTexts(exitReason) {
  switch (exitReason) {
    case 'max-iterations-reached':
      return { lead: 'Local review reached its limit of ' + maxReviewIterations() + ' iterations with findings still open', fields: ['iterations_completed', 'findings_open'] };
    case 'break-fix-break':
      return { lead: 'Local review found that a fix broke an earlier fix', fields: reviewExitFields()[exitReason] };
    case 'injection-suspect':
      return { lead: 'Local review flagged text of a review finding as a possible prompt injection', fields: reviewExitFields()[exitReason] };
    case 'blocked':
      return { lead: 'Local review was blocked', fields: reviewExitFields()[exitReason] };
    default:
      throw new Error('reviewStopTexts: no texts for exit reason ' + JSON.stringify(exitReason));
  }
}

function reviewFieldNames() {
  return {
    iterations_completed: 'Iterations run',
    findings_open: 'Findings still open',
    signals_fired: 'Signals that fired',
    conflicting_findings: 'Conflicting findings',
    prior_fix_commit: 'Earlier fix commit',
    finding_id: 'Finding',
    pattern_category: 'Pattern category',
    field_excerpt: 'Excerpt, cut to ' + maxExcerptLength() + ' characters',
    blocker: 'Blocker',
    stage: 'Stage'
  };
}

function quoteOrEmpty(text) {
  return quoteDiagnostic(text) || encodeUntrustedText('');
}

/**
 * Returns the review value of field as the user sees it: a finding id cut
 * to its short id, the blocker and the excerpt quoted by quoteDiagnostic, a
 * list cut to its first 5 entries, each cut by
 * cutExcerpt, then the count of the rest, a count as it is, and every other
 * string encoded whole when its schema field has bounds, else cut by
 * cutExcerpt first.
 */
function quoteReviewValue(review, field) {
  const value = review[field];
  if (field === 'finding_id') {
    return quoteShortFindingId(value);
  }
  if (field === 'blocker' || field === 'field_excerpt') {
    return quoteOrEmpty(value);
  }
  if (Array.isArray(value)) {
    const restCount = value.length - 5;
    return encodeUntrustedText(value.slice(0, 5).map(cutExcerpt)) + (restCount > 0 ? ' and ' + restCount + ' more' : '');
  }
  return encodeUntrustedText(typeof value === 'number' || reviewFieldTexts()[field].bounds ? value : cutExcerpt(value));
}

function hasReviewText(review, field) {
  return review[field].trim() !== '';
}

function describeReviewStop(review, head) {
  const texts = reviewStopTexts(review.exit_reason);
  const lines = [texts.lead + ', so ' + RUN_NAME + ' stopped before the pull request. Each value below is quoted as the review returned it, encoded as JSON in printable ASCII.'];
  texts.fields.forEach((field) => lines.push('- ' + reviewFieldNames()[field] + ': ' + quoteReviewValue(review, field)));
  if (review.fix_commits_exist) {
    lines.push('Local review committed fixes before it stopped, so the branch head is ' + head + '.');
  }
  return lines.join('\n');
}

function quoteShortFindingId(findingId) {
  return encodeUntrustedText(Array.from(findingId).slice(0, 8).join(''));
}

function renderOpenFindingLine(finding) {
  const recommendation = finding.recommendation.trim() === '' ? 'none' : encodeUntrustedText(finding.recommendation);
  return '- ' + quoteShortFindingId(finding.finding_id) + ', severity ' + encodeUntrustedText(cutExcerpt(finding.severity)) + ': ' + encodeUntrustedText(finding.summary) + ' Recommendation: ' + recommendation;
}

/**
 * Returns the detail block of a local review question: the question or the
 * rejection reason, the reviewer recommendation, then up to
 * 5 open findings and one line counting the rest.
 */
function buildReviewDetailBlock(review, openFindings) {
  const lines = [
    review.exit_reason === 'high-severity-rejection' ? 'Rejected because: ' + quoteReviewValue(review, 'rationale_text') : 'Local review asks: ' + quoteReviewValue(review, 'question'),
    hasReviewText(review, 'recommendation_text') ? 'It recommends: ' + quoteReviewValue(review, 'recommendation_text') : 'It makes no recommendation.',
    'Findings still open, each value quoted as the review returned it:',
    ...openFindings.slice(0, 5).map(renderOpenFindingLine)
  ];
  const restCount = openFindings.length - 5;
  if (restCount > 0) {
    lines.push(describeCount(restCount, 'more open finding') + '.');
  }
  return { text: lines.join('\n') };
}

function renderRejectedFindingLine(finding, isCompact) {
  const head = '- ' + quoteShortFindingId(finding.finding_id) + ', ' + encodeUntrustedText(cutExcerpt(finding.title));
  return isCompact ? head : head + ', record ' + encodeUntrustedText(cutExcerpt(finding.record));
}

function buildRejectedFindingsBlock(note, rejectedFindings) {
  const heading = 'Local review: ' + note + '. Each finding it rejected, each value quoted as the review returned it; the pull request shows only the count:';
  return {
    text: [heading, ...rejectedFindings.map((finding) => renderRejectedFindingLine(finding, false))].join('\n'),
    compact: [heading, ...rejectedFindings.map((finding) => renderRejectedFindingLine(finding, true))].join('\n')
  };
}

/**
 * Returns the code-built brief of a local review question. Its problem
 * names the finding by its short id and the open finding count, and its
 * recommendation is option A, weak, pointing at the reviewer
 * recommendation in the detail block when the review gives one, or none.
 */
function buildReviewQuestionBrief(review, openFindings) {
  const finding = 'finding ' + quoteReviewValue(review, 'finding_id');
  const isRejection = review.exit_reason === 'high-severity-rejection';
  const hasRecommendation = hasReviewText(review, 'recommendation_text');
  return buildTailBrief({
    kind: reviewQuestionKinds()[review.exit_reason],
    problem: (isRejection
      ? 'Local review rejected high severity ' + finding + ' and left it unfixed, for the reason below. Should it be fixed before the pull request?'
      : 'Local review asks you about ' + finding + ' before the pull request, as below.') + ' ' + describeCount(openFindings.length, 'finding') + ' still open.',
    goOn: isRejection ? 'Reject the finding and go on with it unfixed: local review records the decision at its source and goes on.' : 'Answer the finding: this run gives your answer to local review, which goes on with it.',
    other: isRejection ? 'Fix the finding: local review fixes it, or sends it to the planner, and goes on.' : 'Stop: local review ends blocked on this run, before the pull request.',
    strength: hasRecommendation ? 'weak' : 'none',
    why: (hasRecommendation ? 'See its recommendation below. ' : '') + 'Only you can settle a question the review raises.'
  });
}

function askReviewQuestion(review, run) {
  const openFindings = review.open_findings;
  const resolution = { asks: [], taken: [] };
  resolveDecision(reviewQuestionKinds()[review.exit_reason], buildReviewQuestionBrief(review, openFindings), undefined, run, resolution);
  return askTail(resolution.asks, run, buildReviewDetailBlock(review, openFindings));
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
      : 'Local review escalated finding ' + quoteReviewValue(review, 'finding_id') + ' to the planner. Go back to planning, from fresh facts, for its remediation?',
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

function requestReviewReplan(review, run, answer) {
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
  const replan = { reason: reason, review: projectReplanReview(review) };
  if (answer !== undefined) {
    replan.answer = answer;
  }
  return { replan: replan };
}

function routeLocalReview(review, run, answer) {
  switch (localReviewRoutes()[review.exit_reason]) {
    case 'hold':
      return { held: true, note: 'clean' + describeRejectedCount(review.rejected_findings) };
    case 'diminishing':
      return resolveDiminishingReturns(review, run);
    case 'replan':
      return requestReviewReplan(review, run, answer);
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
    return { result: finishDeliveryBlocked(committed.problem, run) };
  }
  const problem = describeReviewProblem(review);
  if (problem !== undefined) {
    return { result: finishDeliveryBlocked(problem, run) };
  }
  const routed = routeLocalReview(review, run, answer);
  if (routed.held) {
    gates.rejected = review.rejected_findings;
  }
  return routed;
}

function notConfiguredReviewLine() {
  return 'local review: the run was launched with local_review false, so the gate is not configured and does not count as held.';
}
