/*
 * tails.js: the tail asks a workflow shares, the questions a run asks
 * after the last wave. Their briefs live in lib/briefs.js.
 *
 * Inputs
 *   run    the run state of the workflow's main.js. The tail asks read
 *          branch and head, and update answerLog and approvals;
 *          resolveDecision (lib/plan.js)
 *          reads level, and a take updates taken through acceptResolution.
 *   ask    one ask, as resolveDecision (lib/plan.js) builds it.
 *   asks   the asks one pause shows, in shown order.
 *   kind, brief  a decide() kind and its code-built brief.
 *   lead   the lead string of the pause, or undefined.
 *   pinned  must-read text the pause shows whole after the lead, never
 *          cut (pauseDelivery), or undefined.
 *   It reads no constant of the workflow's main.js and no workflow
 *   function: pauseDelivery is lib/record.js, takeNextReply,
 *   resolveDecision and acceptResolution lib/plan.js.
 *
 * Outputs
 *   askTails(asks, run, lead, pinned)  {result}, the pause, or {answer:
 *          {question, reply}} once the user replied.
 *   askTail(ask, run, lead, pinned)  askTails([ask], run, lead, pinned).
 *   replanFromTailAsk(ask, run)  the pause, or {replan} once the user
 *          replied.
 *   buildReplyReplan(asked)  the {replan} of a reply to what asked names,
 *          also returned by stopDelivery (lib/record.js).
 *   buildUndecidedAsk  the ask, for kind, brief and run, of a question
 *          decide() must never take.
 *   resolveTailDecision(kind, brief, run)  {} when decide() takes it, else
 *          what replanFromTailAsk returns.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this library into it, so a row can name a
 *   function of this library.
 *   Tail asks: a question after the last wave pauses through pauseDelivery
 *   with a lead and its questions: askTails(asks, run, lead) leads with the
 *   given lead string, as a local review question passes, else with
 *   describeTailLead(run), every plan step committed on the encoded branch
 *   at the head. Tail rounds share run.answerLog and the answers round
 *   numbering with planning rounds, so a resume replays every earlier agent
 *   from cache and takes the reply at the ask. At reply time askTails adds
 *   the {question, settled, reply} entry buildAnswerEntry (lib/brief.js)
 *   builds to run.answerLog, the question being that lead, pinned when
 *   given and the questions, joined by blank lines in shown order, so
 *   every later plan prompt shows it in the answers block; it returns
 *   {question, reply} as the answer. No revise reads a tail reply, so its
 *   settled holds only the shown labels readReplyChoices (lib/brief.js)
 *   reads from it: a letter reply settles its label, and a reply in the
 *   user's own words settles none and stays the user's own words in every
 *   later answers block, review questions included: a review decision lives
 *   in the reviewer's record. The same choices update run.approvals through
 *   applyApprovalChoices (lib/approvals.js). A tail question has no question
 *   key, so a settled label never keys it: a step_stop asked again is asked,
 *   never skipped. A reply to a local review question reruns the review
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

function askTails(asks, run, lead, pinned) {
  const leadText = lead === undefined ? describeTailLead(run) : lead;
  const reply = takeNextReply(run, run.answerLog.length + 1);
  if (reply === undefined) {
    return { result: pauseDelivery({ asks: asks, taken: [] }, run, leadText, pinned) };
  }
  const question = [leadText].concat(pinned ?? [], renderQuestions(asks)).join('\n\n');
  const choices = readReplyChoices(reply, asks);
  run.answerLog.push(buildAnswerEntry({ question: question, labels: listShownLabels(asks), reply: reply, chosen: choices }));
  run.approvals = applyApprovalChoices(run.approvals, asks, choices);
  return { answer: { question: question, reply: reply } };
}

function askTail(ask, run, lead, pinned) {
  return askTails([ask], run, lead, pinned);
}

function replanFromTailAsk(ask, run) {
  const asked = askTail(ask, run);
  if (asked.answer === undefined) {
    return asked;
  }
  return buildReplyReplan('a question the run asked after the last wave');
}

function buildReplyReplan(asked) {
  return { replan: { reason: 'The user replied to ' + asked + ', so plan again from the fresh facts with the answers block.' } };
}

/**
 * Returns the ask resolveDecision (lib/plan.js) builds for a question decide()
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
