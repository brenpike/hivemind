/*
 * standard-delivery tails.js: the tail asks of the standard-delivery
 * workflow, the questions a run asks after the last wave. Their briefs
 * live in briefs.js.
 *
 * Inputs
 *   run    the run state of main.js createRunState. The tail asks read
 *          branch and head, and update answerLog; resolveDecision (plan.js)
 *          reads level, and a take updates taken through acceptResolution.
 *   ask    one ask, as resolveDecision (plan.js) builds it.
 *   kind, brief  a decide() kind and its code-built brief.
 *   lead   the lead string of the pause, or undefined.
 *
 * Outputs
 *   askTail(ask, run, lead)  {result}, the pause, or {answer: {question,
 *          reply}} once the user replied.
 *   replanFromTailAsk(ask, run)  the pause, or {replan} once the user
 *          replied.
 *   buildUndecidedAsk  the ask, for kind, brief and run, of a question
 *          decide() must never take.
 *   resolveTailDecision(kind, brief, run)  {} when decide() takes it, else
 *          what replanFromTailAsk returns.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Tail asks: a question after the last wave pauses through pauseDelivery
 *   with a lead and its question: askTail(ask, run, lead) leads with the
 *   given lead string, as a local review question passes, else with
 *   describeTailLead(run), every plan step committed on the encoded branch
 *   at the head. Tail rounds share run.answerLog and the answers round
 *   numbering with planning rounds, so a resume replays every earlier agent
 *   from cache and takes the reply at the ask. At reply time askTail adds
 *   the {question, settled, reply} entry buildAnswerEntry (lib/brief.js)
 *   builds to run.answerLog, the question being that lead and the question,
 *   so every later plan prompt shows it in the answers block; it returns
 *   {question, reply} as the answer. No revise reads a tail reply, so its
 *   settled is always [] and it stays the user's own words in every later
 *   answers block, review questions included: a review decision lives in the
 *   reviewer's record. A reply to a local review question reruns the review
 *   gate on the current head, after any stale gate, with the next gateLabel
 *   count and user_answer {question, reply}. Any other tail reply starts a
 *   new pass from the facts step with the answers block, outside
 *   maxReplans().
 *
 * Why
 *   Every question after the last wave pauses and logs its reply the same
 *   way, whichever gate or stop asks it, so the tail asks live in one place.
 */

function describeTailLead(run) {
  return 'Every plan step is committed on branch ' + encodeUntrustedText(run.branch) + ', with head ' + run.head + '.';
}

function askTail(ask, run, lead) {
  const leadText = lead === undefined ? describeTailLead(run) : lead;
  const reply = takeNextReply(run, run.answerLog.length + 1);
  if (reply === undefined) {
    return { result: pauseDelivery({ asks: [ask], taken: [] }, run, leadText) };
  }
  const question = leadText + '\n\n' + renderQuestions([ask]);
  run.answerLog.push(buildAnswerEntry({ question: question, labels: [], reply: reply }, undefined));
  return { answer: { question: question, reply: reply } };
}

function replanFromTailAsk(ask, run) {
  const asked = askTail(ask, run, undefined);
  if (asked.answer === undefined) {
    return asked;
  }
  return { replan: { reason: 'The user replied to a question the run asked after the last wave, so plan again from the fresh facts with the answers block.' } };
}

/**
 * Returns the ask resolveDecision (plan.js) builds for a question decide()
 * must never take: its brief, kind and the reason decide() gives at
 * run.level. Throws when decide() takes it, so no undecided question is
 * ever auto-taken.
 */
function buildUndecidedAsk(kind, brief, run) {
  const resolution = { asks: [], taken: [] };
  if (resolveDecision(kind, brief, undefined, run, resolution) === 'take') {
    throw new Error('buildUndecidedAsk: decide() took ' + kind);
  }
  return resolution.asks[0];
}

function resolveTailDecision(kind, brief, run) {
  const resolution = { asks: [], taken: [], reversibleEffects: [] };
  if (resolveDecision(kind, brief, undefined, run, resolution) === 'take') {
    acceptResolution(resolution, run);
    return {};
  }
  return replanFromTailAsk(resolution.asks[0], run);
}
