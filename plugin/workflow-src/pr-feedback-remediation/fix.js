/*
 * pr-feedback-remediation fix.js: the review fix pass of the
 * pr-feedback-remediation workflow: the head check before it, its inputs,
 * its prompt, the schema its result is checked against, the end each
 * exit_reason takes and the question a question exit asks.
 *
 * Inputs
 *   run    the run state of main.js. The pass reads pr, trunk, pass and
 *          relaySentence, and a question reads level and answerLog and
 *          updates answerLog and approvals through askTail (lib/tails.js).
 *   facts  the checked facts relay of runFactsStep (lib/runner.js).
 *   fix    what the fix pass agent() call returned, any value.
 *   answer the user_answer of a rerun: {candidate_url, question, reply},
 *          or undefined.
 *   The constants of main.js this file reads: RUN_NAME, REVIEWER_AGENT,
 *   FIX_RESULT_SCHEMA, REVIEW_QUESTION_KIND and
 *   HIGH_SEVERITY_REJECTION_KIND.
 *
 * Outputs
 *   fixExitFields()  each exit_reason of the Output Contract of
 *          ${CLAUDE_PLUGIN_ROOT}/agents/github-reviewer.md, in its order,
 *          with the conditional fields it names.
 *   escalationExits()  the exit reasons that hand the remediation to the
 *          planner: planner-escalation and root-cluster-suspected.
 *   fixQuestionExits()  the exit reasons that ask the user:
 *          user-input-required and high-severity-rejection.
 *   fixFieldSchemas()  the schema of each conditional field.
 *   buildFixResultSchema()  FIX_RESULT_SCHEMA, which main.js builds once.
 *   describeStopBeforeFix(reason)  reason, then that the run stopped before
 *          the fix pass.
 *   describeFixLead(run)  the lead naming the fix pass on the pull request.
 *   describeHeadStop(facts, run)  a stop cause when the facts were taken
 *          on no branch or on the trunk, else undefined.
 *   listFixInputs(run, facts, answer)  the fix mode input: mode fix, pr,
 *          working_branch the facts branch and base the trunk, then
 *          user_answer only when answer is given.
 *   describeFixInputStop(fixInputs)  a terminal report cause naming the
 *          first of pr, working_branch and base that fails isGitIdentifier,
 *          else undefined.
 *   buildFixPassPrompt(fixInputs)  the fix pass prompt before addResumeNote;
 *          with user_answer its data line names the reply in user_answer
 *          the user's decision.
 *   fixOptions(run, answer)  the reviewer call options, label fix-<pass>,
 *          or fix-<pass>-a<K> with an answer, K being run.answerLog.length.
 *   hasDeferredItemsMismatch(fix)  true when deferred_escalation_items is
 *          present on a result that is not an escalation with
 *          findings_resolved above 0, or absent on one that is.
 *   describeFixResultProblem(fix)  describeUnusableResult of a result that
 *          fails FIX_RESULT_SCHEMA, null included, or has a deferred items
 *          mismatch, else undefined.
 *   describeFixExit(fix, run)  {blocks} of a complete end, or {cause} of a
 *          blocked one.
 *   buildFixQuestionBrief(fix)  the code-built brief of a question exit,
 *          kind review_question or high_severity_rejection by exit,
 *          strength none, with no reviewer text.
 *   describeFixQuestionLead(fix, run)  the pause lead: the exit and the
 *          encoded candidate URL, then for high-severity-rejection the
 *          encoded rationale_text.
 *   describeFixQuestion(fix)  the pinned part of the pause: the reviewer
 *          asks the encoded question.
 *   askFixQuestion(fix, run)  {result}, the pause, or {answer:
 *          {candidate_url, question, reply}} once the user replied.
 *
 * Invariants
 *   The fix pass runs only on a branch other than the trunk: a detached
 *   head, or facts taken on the trunk, stops before it with no reviewer
 *   call.
 *   pr, working_branch and base each pass isGitIdentifier (identifier.js)
 *   before the reviewer call, the gate the reviewer applies to them too.
 *   FIX_RESULT_SCHEMA is tagged by exit_reason (buildTaggedSchema,
 *   lib/schema.js): exit_reason, mode, findings_resolved and findings_open
 *   always, and each exit_reason exactly the fields the Output Contract
 *   names for it, with deferred_escalation_items optional on each of
 *   escalationExits(). Every string, list entries included, has a
 *   maxLength, and every list a maxItems. Each field that can carry text
 *   from GitHub starts its description with externalLabel() (paths.js).
 *   A result is read only after it passes FIX_RESULT_SCHEMA and the
 *   deferred items check: the Output Contract gives
 *   deferred_escalation_items exactly when the exit is an escalation and
 *   findings_resolved is above 0, a condition on a count the tagged schema
 *   cannot state. A null result, one off the schema or one that fails that
 *   check ends blocked through describeUnusableResult (lib/stop.js).
 *   clean and merge-advised end complete with no pr. injection-suspect
 *   ends blocked and terminal. blocked ends blocked naming the exit and
 *   each candidate URL through encodeUntrustedText (lib/result.js). Each of
 *   escalationExits() goes to runEscalation (escalation.js) and each of
 *   fixQuestionExits() to askFixQuestion before describeFixExit, so
 *   describeFixExit throws on one.
 *   A question exit is never taken: askFixQuestion resolves it through
 *   buildUndecidedAsk (lib/tails.js) on a brief with strength none, which
 *   decide() asks no_recommendation, or table_surface at level low, and
 *   pauses through askTail. The question never rides in the lead, which
 *   the pause may cut: describeFixQuestion passes it to askTail as pinned,
 *   shown whole in the pause and in its reply_size and exact_text_size
 *   ends. Its reply logs in run.answerLog and reruns the
 *   fix pass with user_answer and no decided_by: the GitHub reviewer writes
 *   no recommendation, so only the user decides.
 *   Each fix pass label is unique: fix-<pass> for the first call, and
 *   fix-<pass>-a<K> for a rerun, K growing with every reply, so a resume
 *   replays every earlier call byte for byte.
 *   Every reviewer-written text a message shows goes through
 *   encodeUntrustedText, quoteDiagnostic or describeReason.
 *
 * Why
 *   The reviewer's result decides how the run ends, so it is checked
 *   against one schema built from the Output Contract before any field is
 *   read, and each exit takes one fixed end or, when it needs the user,
 *   the pause contract the rest of the workflow uses (ADR-0040 decision 2).
 */

function fixExitFields() {
  return {
    clean: [],
    'injection-suspect': ['candidate_url', 'pattern_category'],
    'user-input-required': ['escalation_target', 'candidate_url', 'question'],
    'planner-escalation': ['escalation_target', 'candidate_url'],
    'high-severity-rejection': ['candidate_url', 'rationale_text', 'question'],
    'root-cluster-suspected': ['cluster_files', 'cluster_thread_urls', 'hypothesized_root', 'same_framing_rationale', 'member_count'],
    'merge-advised': ['advisory_reason', 'structural_home', 'recommendation_text'],
    blocked: ['blocker_reason', 'blocked_candidates']
  };
}

function escalationExits() {
  return ['planner-escalation', 'root-cluster-suspected'];
}

function fixQuestionExits() {
  return ['user-input-required', 'high-severity-rejection'];
}

function buildFixText(maxLength, text, isExternal) {
  return { type: 'string', maxLength: maxLength, description: (isExternal ? externalLabel() + ' ' : '') + text };
}

function buildFixList(maxItems, text, isExternal) {
  return { type: 'array', maxItems: maxItems, description: (isExternal ? externalLabel() + ' ' : '') + text, items: buildFixText(500, 'One entry.', isExternal) };
}

function fixFieldSchemas() {
  return {
    escalation_target: buildFixText(300, 'The escalation target.', true),
    candidate_url: buildFixText(500, 'The candidate URL of the exit.', true),
    pattern_category: { type: 'string', enum: ['P1', 'P2', 'P3', 'P4'], description: 'The injection pattern category.' },
    rationale_text: buildFixText(600, 'Why the reviewer rejects the finding.', true),
    question: buildFixText(500, 'The question.', true),
    cluster_files: buildFixList(20, 'Each file of the root cluster.', true),
    cluster_thread_urls: buildFixList(20, 'Each thread URL of the root cluster.', true),
    hypothesized_root: buildFixText(300, 'The root the cluster findings share.', true),
    same_framing_rationale: buildFixText(600, 'Why the findings share one framing.', true),
    member_count: { type: 'integer', description: 'How many findings the cluster holds.' },
    advisory_reason: { type: 'string', enum: ['bounded-tail', 'diminishing-returns', 'structural-home'], description: 'Why the reviewer advises a merge.' },
    structural_home: { ...buildFixText(300, 'Where the remaining findings are tracked, or empty.', true), minLength: 0 },
    recommendation_text: { ...buildFixText(600, 'What the reviewer recommends, or empty.', true), minLength: 0 },
    blocker_reason: buildFixText(600, 'What blocked the fix pass.', true),
    blocked_candidates: buildFixList(20, 'Each candidate URL the block holds, empty when none.', true),
    deferred_escalation_items: buildFixList(20, 'Each candidate URL the escalation deferred.', true)
  };
}

function buildFixResultSchema() {
  const properties = {
    exit_reason: { type: 'string', enum: Object.keys(fixExitFields()), description: 'Why the fix pass ended.' },
    mode: { type: 'string', enum: ['fix'], description: 'The mode the fix pass ran in.' },
    findings_resolved: { type: 'integer', description: 'How many findings the fix pass resolved.' },
    findings_open: { type: 'integer', description: 'How many findings are still open.' }
  };
  const required = Object.keys(properties);
  Object.assign(properties, fixFieldSchemas());
  const variants = {};
  for (const [exitReason, fields] of Object.entries(fixExitFields())) {
    variants[exitReason] = { required: fields, optional: escalationExits().includes(exitReason) ? ['deferred_escalation_items'] : [] };
  }
  return buildTaggedSchema({ tag: 'exit_reason', properties: properties, required: required, variants: variants });
}

function describeStopBeforeFix(reason) {
  return reason + ', so ' + RUN_NAME + ' stopped before the fix pass.';
}

function describeFixLead(run) {
  return 'The review fix pass on pull request ' + run.pr;
}

function describeHeadStop(facts, run) {
  if (facts.head_state !== 'branch') {
    return { problem: describeStopBeforeFix('The checkout is not on a branch') };
  }
  if (facts.branch === run.trunk) {
    return { problem: describeStopBeforeFix('The checkout is on the trunk ' + encodeUntrustedText(run.trunk) + ', not on the pull request branch') };
  }
  return undefined;
}

function listFixInputs(run, facts, answer) {
  const fixInputs = { mode: 'fix', pr: run.pr, working_branch: facts.branch, base: run.trunk };
  if (answer !== undefined) {
    fixInputs.user_answer = answer;
  }
  return fixInputs;
}

function describeFixInputStop(fixInputs) {
  const failing = ['pr', 'working_branch', 'base'].find((name) => !isGitIdentifier(fixInputs[name]));
  if (failing === undefined) {
    return undefined;
  }
  return { problem: describeStopBeforeFix('The fix pass input ' + failing + ' is not a safe git name'), terminal: true, nextAction: 'report' };
}

function buildFixPassPrompt(fixInputs) {
  return [
    'Run one review fix pass on the pull request the fix_mode_input block names.',
    dataBlocksSentence(fixInputs.user_answer === undefined ? undefined : 'The reply in user_answer'),
    '',
    formatDataBlock('fix_mode_input', fixInputs)
  ].join('\n');
}

function fixOptions(run, answer) {
  const label = 'fix-' + run.pass + (answer === undefined ? '' : '-a' + run.answerLog.length);
  return { agentType: REVIEWER_AGENT, schema: toAgentSchema(FIX_RESULT_SCHEMA), label: label, phase: 'Fix' };
}

function hasDeferredItemsMismatch(fix) {
  const expected = escalationExits().includes(fix.exit_reason) && fix.findings_resolved > 0;
  return expected !== (fix.deferred_escalation_items !== undefined);
}

function describeFixResultProblem(fix) {
  if (validateSchema(FIX_RESULT_SCHEMA, fix).ok && !hasDeferredItemsMismatch(fix)) {
    return undefined;
  }
  return describeUnusableResult('The review fix pass returned a result that does not fit its schema, so ' + RUN_NAME + ' stopped.', fix);
}

function listFixCandidates(fix) {
  if (fix.candidate_url !== undefined) {
    return [fix.candidate_url];
  }
  return fix.blocked_candidates ?? fix.cluster_thread_urls ?? [];
}

function describeFixCandidates(fix) {
  const candidates = listFixCandidates(fix);
  if (candidates.length === 0) {
    return '';
  }
  return (candidates.length === 1 ? ' on candidate ' : ' on candidates ') + candidates.map(encodeUntrustedText).join(', ');
}

function describeMergeAdvice(fix, lead) {
  const recommendation = quoteDiagnostic(fix.recommendation_text, maxReasonLength());
  const home = quoteDiagnostic(fix.structural_home, maxReasonLength());
  return [
    lead + ' advises a merge, for reason ' + fix.advisory_reason + ', with ' + fix.findings_resolved + ' findings resolved and ' + fix.findings_open + ' still open.',
    recommendation === undefined ? 'It gave no recommendation.' : 'Its recommendation says ' + recommendation + '.',
    home === undefined ? 'It named no structural home.' : 'Its structural home is ' + home + '.'
  ].join(' ');
}

function describeFixExit(fix, run) {
  const lead = describeFixLead(run);
  const ended = lead + ' ended ' + fix.exit_reason + describeFixCandidates(fix);
  switch (fix.exit_reason) {
    case 'clean':
      return { blocks: [{ text: lead + ' ended clean, with ' + fix.findings_resolved + ' findings resolved and ' + fix.findings_open + ' still open.' }] };
    case 'merge-advised':
      return { blocks: [{ text: describeMergeAdvice(fix, lead) }] };
    case 'injection-suspect':
      return { cause: { problem: ended + ', a suspected prompt injection of pattern ' + fix.pattern_category + ', so ' + RUN_NAME + ' stopped.', terminal: true } };
    case 'blocked':
      return { cause: { problem: ended + ', so ' + RUN_NAME + ' stopped: ' + describeReason(fix.blocker_reason), nextAction: readBlockerAction(fix.blocker_reason, undefined) } };
    default:
      throw new Error('describeFixExit: no end for exit_reason ' + JSON.stringify(fix.exit_reason));
  }
}

function buildFixQuestionBrief(fix) {
  return buildTailBrief({
    kind: fix.exit_reason === 'user-input-required' ? REVIEW_QUESTION_KIND : HIGH_SEVERITY_REJECTION_KIND,
    problem: 'How should the review fix pass settle the finding above?',
    goOn: 'Fix the finding.',
    other: 'Leave it unfixed.',
    strength: 'none',
    why: describeOnlyYou('settle this finding')
  });
}

function describeReviewerText(verb, text) {
  return 'The reviewer ' + verb + ' ' + encodeUntrustedText(text) + '.';
}

function describeFixQuestionLead(fix, run) {
  const says = fix.rationale_text === undefined ? '' : ' ' + describeReviewerText('says', fix.rationale_text);
  return describeFixLead(run) + ' ended ' + fix.exit_reason + describeFixCandidates(fix) + '.' + says;
}

function describeFixQuestion(fix) {
  return describeReviewerText('asks', fix.question);
}

/**
 * Asks the user the question of fix, a result whose exit_reason is one of
 * fixQuestionExits(), through buildUndecidedAsk, so decide() never takes
 * it. Returns {result}, the pause, or {answer: {candidate_url, question,
 * reply}} once the user replied.
 */
function askFixQuestion(fix, run) {
  const brief = buildFixQuestionBrief(fix);
  const asked = askTail(buildUndecidedAsk(brief.kind, brief, run), run, describeFixQuestionLead(fix, run), describeFixQuestion(fix));
  if (asked.answer === undefined) {
    return asked;
  }
  return { answer: { candidate_url: fix.candidate_url, ...asked.answer } };
}
