/*
 * analysis-only main.js: the body of the analysis-only workflow script.
 *
 * Inputs
 *   args   the Workflow args global. One of:
 *            a string: the request itself (slash-command form);
 *            an object {request, trunk?, references?, answers?, build?,
 *            reply?};
 *            undefined.
 *          request comes from the launch args only. A resumed run still
 *          has it because the overlord relaunches with the launch args, then
 *          the keys of resume_args over them, then reply (result.js
 *          contract). Without the launch args there is no request.
 *          answers is this script's own field: it comes only from the
 *          resume_args of an earlier pause, holds the reply to round N as
 *          answers['round-N'], and is read only when it is a plain object.
 *          build is the BUILD_ID the pause wrote with answers. A resume
 *          whose build is absent or not this script's BUILD_ID stops before
 *          any agent call (lib/args.js): the plugin changed while it was
 *          paused. A fresh launch ignores build.
 *          reply is the user's reply to that pause, per the result.js
 *          contract. It answers the first round with no stored answer, and
 *          only when answers is present, since that marks a pending pause.
 *          A top-level 'round-N' key is not read. An autonomy key is not
 *          read: the level is always the table's default_level until the
 *          user-set level comes in slice 3 (ADR-0036 decision 8).
 *          trunk and references come from the launch args only, so a
 *          string launch takes their defaults. trunk is the resolved trunk
 *          branch: absent means 'main', a non-blank string passes through,
 *          and anything else blocks. references are the issue and pull
 *          request numbers the request names: absent means none; each is a
 *          positive integer or a digit string, normalized to a digit string
 *          and deduplicated in order; more than 20, or any other shape,
 *          blocks. The facts skill's input gate is the charset check on
 *          both, so no second allowlist is kept here.
 *   AUTONOMY_TABLE, BRIEF_SCHEMA, BUILD_ID  constants copied in by the
 *   build.
 *   The launch args and pause rounds are read with lib/args.js. The facts
 *   patterns and messages, the prompt sentences and the scan step come from
 *   lib/facts.js. Both take the run noun 'analysis', so every message keeps
 *   its analysis-only words.
 *
 * Outputs
 *   pauseForUser({resumeArgs, blocks}) when a question needs the user's
 *   answer, otherwise finish({outcome, blocks}). See result.js for both
 *   shapes and for how blocks are fitted to the completion notice.
 *
 * Invariants
 *   Facts first: the first agent call is the facts step, a haiku drone that
 *   invokes hivemind:gather-facts once. Its result is checked against its
 *   schema, the facts file path, the line count and external_texts against
 *   their patterns, and cut against the known cut fields, before anything
 *   reads it. external_texts must also be a safe integer. A failed check
 *   blocks as malformed facts, and no planner starts.
 *   The facts schema is built by buildTaggedSchema (lib/schema.js) from one
 *   table, which gives both its anyOf branches and its 'Only with'
 *   descriptions: ran requires facts_file, facts_lines, cut and
 *   external_texts, blocked may carry blocker, and no other field passes.
 *   So a ran result with a blocker, or a blocked result with a facts field,
 *   blocks as malformed facts.
 *   Only cut stops: a cut other than none blocks before the scan and the
 *   planner, naming the fields cut (ADR-0037 invariant 4). delivery and
 *   delivery_stops are never asked for or read: their checks belong to
 *   delivery, not to analysis. A facts result that carries either blocks as
 *   malformed facts, as any field outside the facts schema does.
 *   Scan before planning: when external_texts, the count N of texts from
 *   GitHub in the facts file, is above 0, a drone scans each of those texts,
 *   named by its text_id t1 to tN, with hivemind:injection-scan before any
 *   planner call. references is not looked at for this. Any
 *   injection-suspect result, or a result it cannot use, blocks before
 *   planning, naming each flagged item_ref, its pattern category and the
 *   first 200 characters of its excerpt (security-policy.md, When Classified
 *   as injection-suspect), then the facts file that holds each text_id. A
 *   suspect is reported before any coverage failure.
 *   The script cannot read the facts file, so it checks coverage 1:1
 *   instead: exactly N results, each item_ref a text_id from t1 to tN, none
 *   twice, in any order. Anything else blocks before planning. How a reader
 *   finds each text_id is in the consumer rules of
 *   ${CLAUDE_PLUGIN_ROOT}/skills/gather-facts/SKILL.md. The verdict on each
 *   text stays the judgment of the scan (ADR-0037 Risks, 'External text the
 *   scan does not catch').
 *   Read-only scope: no agent edits a tracked file, creates a branch,
 *   commits, pushes or opens a pull request. The facts script writes only
 *   its ignored facts file under .hivemind/facts and the remote-tracking
 *   trunk ref, with the fetched objects and FETCH_HEAD.
 *   Read-only: the planner, hivemind:cerebrate, has no write tool, and
 *   the facts and scan prompts carry the read-only trigger of drone.md.
 *   No prompt restates a rule its agent or skill owns
 *   (docs/engineering-principles.md P24): each is a task line, the
 *   triggers and the boundary it needs, one data line and its data.
 *   Every question resolves through decide() with kind 'planner_question',
 *   fixed here. The brief's own kind is never used.
 *   The facts and scan prompts depend only on the launch args and the facts
 *   step result, and the analyze prompt never carries answers or the reply,
 *   so a resumed run gets all three results from cache. The revise-N prompt
 *   depends only on earlier results and on the replies to rounds 1 to N.
 *   Each revise-N call gets its own revise schema: the analysis spec plus a
 *   shared required settled array whose items enum is
 *   listShownLabels(asks), the labels Q1 to Qn round N showed. Its agent
 *   schema and its check schema are both built from that spec each round,
 *   the check one with the questions items check left out, as for analyze.
 *   Each reply a pause consumes goes once into the answer log as {question,
 *   settled, reply}, and only after its revise result passes its check. The
 *   shared lib buildAnswerEntry is the one writer of settled: the question is
 *   the questions text of its round, renderQuestions of its asks, settled
 *   the labels of result.settled in shown order, and a reply that settles
 *   nothing logs settled []. Only the questions settled names count as
 *   settled, never the whole round, so a question the reply left open is
 *   never called settled (issue 472). The revise-N prompt carries the whole
 *   log, the entries of rounds 1 to N-1, in an answers data block, with a
 *   data line saying only the questions those labels in each entry name are
 *   settled decisions,
 *   never asked again or reversed. The revise-1 prompt has no answers block,
 *   so it is the prompt of a run with no answers. resume_args still takes
 *   its replies from the log.
 *   The revise-N prompt shows the planner the same questions text the
 *   pause message showed the user, renderQuestions of the asks.
 *   A run pauses at most pauseLimit() times. After that it completes and
 *   lists the questions still open, with stop reason 'pause_limit'.
 *   A run also stops asking when the replies so far are too long to carry:
 *   when canCarry fails for the resume_args a pause would return, it
 *   completes instead and lists the questions still open, with stop reason
 *   'reply_size'.
 *   The analysis schema is built by buildTaggedSchema from one table too:
 *   outcome and questions are shared, complete requires report, and blocked
 *   may carry blocker. A planner result is checked against the full
 *   analysis schema, or on a revise its revise schema, with the questions
 *   items check left out, so decide()
 *   still checks each brief and a malformed brief is asked, never a reason
 *   to stop. A result that fails the check, a field of the other outcome
 *   included, finishes blocked with one plain malformed-result message.
 *   Each agent gets toAgentSchema of its full schema, the same schema with
 *   every anyOf removed, because the Messages API rejects a tool input
 *   schema that has anyOf at its top level.
 *   The planner blocker has maxLength 400 in the analysis schema, so a
 *   result with a longer one fails the check and finishes blocked as
 *   malformed.
 *   agent() returns null on an agent API error, such as an expired login.
 *   A null facts result blocks as malformed facts and a null analyze or
 *   revise result as no result, and each message then ends with the
 *   describeNoResult (result.js) sentence that names the agent failure,
 *   so the user does not look for a cause in the repo (issue 460).
 *   A blocked facts or planner result shows its blocker only through
 *   describeReason (result.js): its non-blank lines joined into one line,
 *   quoted whole up to maxReasonLength() code points, 600, else cut by
 *   cutAtBoundary at a sentence or word boundary with the mark ' (cut)'
 *   after the quote, and encoded by encodeUntrustedText, or 'it gave no
 *   reason.' when it has none. So a control character, an escape sequence,
 *   a bidi mark or a line feed in it never reaches the user raw.
 *   Open questions never end it blocked: only a missing request, a bad
 *   trunk or references arg, a build skew on resume, a facts or scan stop,
 *   or a planner result it cannot use does.
 *   No run record: resume_args is {answers, build} alone, every reply so
 *   far and BUILD_ID. The request is never in it, because the launch args
 *   already hold it. It always has answers, so a relaunch with it is a
 *   resume, and never has request, reply or an autonomy key.
 *   A reply is ignored when no pause is pending: when the run was not
 *   launched with answers, or when it finishes before it reaches a round
 *   with no stored answer.
 *   Trust boundary: the overlord is a trusted relay. It already chooses the
 *   request it launches with, so args, including resume_args and its stored
 *   answers, are trusted as this script's own echo. A script has no secret
 *   or I/O to authenticate that state, and a forged answer gains nothing the
 *   overlord could not get by misquoting the reply. Resume-state tampering
 *   is by design, not a defect (ADR-0036 decision 13).
 *   Every message is a list of blocks, highest priority first, which
 *   result.js fits to the completion notice (ADR-0036 decision 15). A pause
 *   message is two blocks: a one-line lead built here, saying the analysis
 *   is drafted and how many questions need the user's answer before the
 *   report is final, then renderQuestions of the asks. It has no compact
 *   form and no taken-decision line: a taken decision shows only in the
 *   complete message. No ask is marked exact, so a question never shows
 *   the verbatim of its brief. A complete message is the decided-for-you
 *   block as renderDecisionsCompact alone, one line per decision with no
 *   verbatim, then any open-questions block, then the report last, the only
 *   block that may be shortened. A blocked message is one block that may be
 *   shortened.
 *
 * Why
 *   analysis-only used to end blocked whenever the planner had open
 *   questions. Here the planner states its recommendation for each one, code
 *   decides which recommendations to take, and only the rest reach the user.
 */

const RUN_NOUN = 'analysis';
const QUESTION_KIND = 'planner_question';
const PLANNER_AGENT_TYPE = 'hivemind:cerebrate';
const ANALYSIS_SCHEMA = buildTaggedSchema(buildAnalysisSpec(omitSchemaDialect(BRIEF_SCHEMA)));
const ANALYSIS_CHECK_SCHEMA = buildTaggedSchema(buildAnalysisSpec({}));
const FACTS_STEP_SCHEMA = buildTaggedSchema({
  tag: 'outcome',
  properties: {
    outcome: { type: 'string', enum: ['ran', 'blocked'], description: 'ran when the facts script exited 0. blocked when it exited 1.' },
    facts_file: { type: 'string', description: 'The facts_file routing line value, copied exactly.' },
    facts_lines: { type: 'string', description: 'The facts_lines routing line value, copied exactly.' },
    cut: { type: 'string', description: 'The cut routing line value, copied exactly.' },
    external_texts: { type: 'string', description: 'The external_texts routing line value, copied exactly.' },
    blocker: { type: 'string', description: 'The blocker line the skill relayed.' }
  },
  required: ['outcome'],
  variants: {
    ran: { required: ['facts_file', 'facts_lines', 'cut', 'external_texts'], optional: [] },
    blocked: { required: [], optional: ['blocker'] }
  }
});

function omitSchemaDialect(schema) {
  return Object.fromEntries(Object.entries(schema).filter(([key]) => key !== '$schema'));
}

function buildAnalysisSpec(questionSchema) {
  return {
    tag: 'outcome',
    properties: {
      outcome: {
        type: 'string',
        enum: ['complete', 'blocked'],
        description: 'complete when the analysis is done. blocked only when it cannot be done at all.'
      },
      report: {
        type: 'string',
        description: 'The analysis for the user. It assumes the recommendation of every question raised.'
      },
      blocker: {
        type: 'string',
        maxLength: 400,
        description: 'Why the analysis cannot be done, in one or two short sentences written for the user.'
      },
      questions: {
        type: 'array',
        description: 'One decision brief for each decision the repository and the request do not settle.',
        items: questionSchema
      }
    },
    required: ['outcome', 'questions'],
    variants: { complete: { required: ['report'], optional: [] }, blocked: { required: [], optional: ['blocker'] } }
  };
}

function buildReviseSpec(questionSchema, shownLabels) {
  const spec = buildAnalysisSpec(questionSchema);
  spec.properties.settled = {
    type: 'array',
    description: 'The label, like Q1, of each shown question the reply settles.',
    items: { type: 'string', enum: shownLabels.slice() }
  };
  spec.required.push('settled');
  return spec;
}

function buildReviseSchemas(shownLabels) {
  return {
    agent: buildTaggedSchema(buildReviseSpec(omitSchemaDialect(BRIEF_SCHEMA), shownLabels)),
    check: buildTaggedSchema(buildReviseSpec({}, shownLabels))
  };
}

function buildFactsPrompt(trunk, references) {
  return [
    'Invoke the hivemind:gather-facts skill once, with the trunk and references in the inputs block below and no remote.',
    runnerReadOnlySentence(),
    dataBlocksSentence(),
    runnerToolSentence(),
    '',
    formatDataBlock('inputs', { trunk: trunk, references: references })
  ].join('\n');
}

function buildAnalyzePrompt(request, facts) {
  return [
    'Analyze the user request below and answer it from this repository.',
    boundarySentence(),
    dataBlocksSentence(),
    '',
    buildFactsBlock(facts),
    formatDataBlock('request', request)
  ].join('\n');
}

function buildRevisePrompt({ request, facts, answers, report, questions, reply }) {
  const hasAnswers = answers.length > 0;
  const lines = [
    'Revise your analysis of the user request below with the user reply below.',
    boundarySentence(),
    hasAnswers ? dataBlocksSentence('The reply block') + ' In each answers entry, only the questions its settled labels name are the user\'s settled decisions: never ask them again, never reverse them.' : dataBlocksSentence('The reply block'),
    '',
    buildFactsBlock(facts),
    formatDataBlock('request', request)
  ];
  if (hasAnswers) {
    lines.push(formatDataBlock('answers', answers));
  }
  lines.push(formatDataBlock('earlier_report', report), formatDataBlock('questions', questions), formatDataBlock('reply', reply));
  return lines.join('\n');
}

function plannerOptions(label, phaseTitle, schema) {
  return { agentType: PLANNER_AGENT_TYPE, schema: toAgentSchema(schema), label: label, phase: phaseTitle };
}

function factsOptions() {
  return { agentType: runnerAgentType(), model: 'haiku', schema: toAgentSchema(FACTS_STEP_SCHEMA), label: 'facts', phase: 'Facts' };
}

function describeFactsProblem(facts) {
  if (!validateSchema(FACTS_STEP_SCHEMA, facts).ok) {
    return malformedFactsMessage(RUN_NOUN, facts);
  }
  if (facts.outcome === 'blocked') {
    return blockedFactsMessage(RUN_NOUN, describeReason(facts.blocker));
  }
  const isWellFormed = matchesFactsLine('facts_file', facts.facts_file)
    && matchesFactsLine('facts_lines', facts.facts_lines)
    && isCutList(facts.cut)
    && isTextCount(facts.external_texts);
  if (!isWellFormed) {
    return malformedFactsMessage(RUN_NOUN, facts);
  }
  if (facts.cut !== 'none') {
    return cutFactsMessage(RUN_NOUN, facts.cut);
  }
  return undefined;
}

async function gatherCheckedFacts(launchInputs) {
  phase('Facts');
  const facts = await agent(buildFactsPrompt(launchInputs.trunk, launchInputs.references), factsOptions());
  const factsProblem = describeFactsProblem(facts);
  if (factsProblem !== undefined) {
    return { problem: factsProblem };
  }
  const scanProblem = await runScanStep(facts, RUN_NOUN);
  if (scanProblem !== undefined) {
    return { problem: scanProblem };
  }
  return { facts: facts };
}

function describeReplyProblem(analysis, checkSchema) {
  if (!isPlainObject(analysis)) {
    return appendSentence('The planner returned no result, so the analysis stopped.', describeNoResult(analysis));
  }
  if (!validateSchema(checkSchema, analysis).ok) {
    return 'The planner returned a result that does not fit the analysis schema, so the analysis stopped.';
  }
  if (analysis.outcome === 'blocked') {
    return 'The planner could not do the analysis: ' + describeReason(analysis.blocker);
  }
  return undefined;
}

function resolveQuestions(questions, level) {
  const asks = [];
  const taken = [];
  for (const brief of questions) {
    const decision = decide({ kind: QUESTION_KIND, level: level, brief: brief }, AUTONOMY_TABLE, BRIEF_SCHEMA);
    if (decision.action === 'take') {
      taken.push({ brief: brief });
    } else {
      asks.push({ brief: brief, reason: decision.reason });
    }
  }
  return { asks: asks, taken: taken };
}

function finishBlocked(message) {
  return finish({ outcome: 'blocked', blocks: [{ text: message, shorten: true }] });
}

function finishComplete(report, openQuestions, taken) {
  const blocks = [];
  if (taken.length > 0) {
    blocks.push({ text: renderDecisionsCompact(taken) });
  }
  if (openQuestions !== '') {
    blocks.push({ text: openQuestions });
  }
  blocks.push({ text: report, shorten: true });
  return finish({ outcome: 'complete', blocks: blocks });
}

function renderPauseLead(questionCount) {
  if (questionCount === 1) {
    return 'The analysis is drafted. 1 question needs your answer before the report is final.';
  }
  return 'The analysis is drafted. ' + questionCount + ' questions need your answer before the report is final.';
}

function pauseOrStopAsking(report, resolution, questions, answerLog) {
  const resumeArgs = buildResumeArgs(answerLog.map((entry) => entry.reply), BUILD_ID);
  if (!canCarry(resumeArgs)) {
    return finishComplete(report, renderOpenQuestions(resolution.asks, 'reply_size'), resolution.taken);
  }
  const blocks = [{ text: renderPauseLead(resolution.asks.length) }, { text: questions }];
  return pauseForUser({ resumeArgs: resumeArgs, blocks: blocks });
}

async function runAnalysis(rawArgs) {
  const argsObject = readArgsObject(rawArgs);
  if (!isNonEmptyString(argsObject.request)) {
    return finishBlocked('No request was given, so there is nothing to analyze.');
  }
  const launchInputs = readLaunchInputs(argsObject, RUN_NOUN, BUILD_ID);
  if (launchInputs.problem !== undefined) {
    return finishBlocked(launchInputs.problem);
  }
  const checked = await gatherCheckedFacts(launchInputs);
  if (checked.problem !== undefined) {
    return finishBlocked(checked.problem);
  }
  const facts = checked.facts;
  const level = resolveLevel(undefined, AUTONOMY_TABLE);
  const storedAnswers = readStoredAnswers(argsObject);
  let pendingReply = readPendingReply(argsObject);
  const answerLog = [];
  let checkSchema = ANALYSIS_CHECK_SCHEMA;
  let shownRound;
  phase('Analyze');
  let analysis = await agent(buildAnalyzePrompt(argsObject.request, facts), plannerOptions('analyze', 'Analyze', ANALYSIS_SCHEMA));
  for (let round = 1; ; round += 1) {
    const problem = describeReplyProblem(analysis, checkSchema);
    if (problem !== undefined) {
      return finishBlocked(problem);
    }
    if (shownRound !== undefined) {
      answerLog.push(buildAnswerEntry(shownRound, analysis));
    }
    const resolution = resolveQuestions(analysis.questions, level);
    if (resolution.asks.length === 0) {
      return finishComplete(analysis.report, '', resolution.taken);
    }
    if (!canPause(round - 1)) {
      return finishComplete(analysis.report, renderOpenQuestions(resolution.asks, 'pause_limit'), resolution.taken);
    }
    const questions = renderQuestions(resolution.asks);
    let reply = readStoredReply(storedAnswers, round);
    if (reply === undefined) {
      reply = pendingReply;
      pendingReply = undefined;
    }
    if (reply === undefined) {
      return pauseOrStopAsking(analysis.report, resolution, questions, answerLog);
    }
    const shownLabels = listShownLabels(resolution.asks);
    const reviseSchemas = buildReviseSchemas(shownLabels);
    phase('Revise');
    const revisePrompt = buildRevisePrompt({ request: argsObject.request, facts: facts, answers: answerLog, report: analysis.report, questions: questions, reply: reply });
    analysis = await agent(revisePrompt, plannerOptions('revise-' + round, 'Revise', reviseSchemas.agent));
    checkSchema = reviseSchemas.check;
    shownRound = { question: questions, labels: shownLabels, reply: reply };
  }
}

return await runAnalysis(args);
