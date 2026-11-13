/*
 * stop.js: the typing of a stopped run: the next action of each cause, the
 * stop order, the Next line and the blocks finish (lib/result.js) leads a
 * blocked message with.
 *
 * Inputs
 *   describeNoResult(result)  result any value, what one agent() returned.
 *   describeUnusableResult(problem, result)  problem a string.
 *   readBlockerAction(blocker, nextAction)  blocker any value, a step's
 *                 blocker; nextAction the step's own next_action.
 *   isTransientFailure(text)  text any value, a runner's stderr or blocker.
 *   nextStepLine(nextAction)  a next action: 'fix_cause', 'run_again',
 *                 'answer', 'approve', 'report' or absent. An agent sets
 *                 only fix_cause or run_again; code alone sets the rest.
 *   describeStopAction(nextAction, then)  nextAction as above, then the
 *                 words of the user's next move, such as 'reply'.
 *   orderStopCauses(causes), buildStopBlocks(causes)  causes non-empty
 *                 array of {problem, nextAction?}.
 *
 * Outputs
 *   describeNoResult  for a null result, one fixed sentence: the step's
 *                 agent failed before it returned a result, as an agent API
 *                 error such as an expired login, a rate limit or a network
 *                 failure does. Otherwise the empty string.
 *   describeUnusableResult  {problem: problem + ' ' + describeNoResult(null),
 *                 nextAction: 'run_again', agentFailure: true} for a null
 *                 result, else {problem, nextAction: 'report'}: a result
 *                 the run cannot use is its own step's failure, so nothing
 *                 in the repo needs a fix. agentFailure is set only here.
 *   readBlockerAction  'report' when quoteDiagnostic(blocker) is undefined,
 *                 since a lead that names no reason has no cause to clear,
 *                 else nextAction.
 *   isTransientFailure  true only when text is a string that names, by one
 *                 fixed case-insensitive pattern, a root cause the Transient
 *                 Failure definition of definitions.md lists, else false.
 *   describeStopAction  the one action phrase of nextAction, then joined
 *                 in: approve or refuse the change named above, clear the
 *                 cause named above, rerun with the answers, report the stop
 *                 as a workflow defect since nothing in your repo needs a
 *                 fix, or rerun later since nothing in the repo does. An
 *                 absent or unknown value is fix_cause.
 *   nextStepLine  'Next: ' + describeStopAction(nextAction, 'run the request
 *                 again') + '.', one action per line.
 *   orderStopCauses  causes stably ordered by next action: approve,
 *                 fix_cause or absent, answer, report, run_again.
 *   maxBlockedLeadLength  1000, the code points of a compact lead.
 *   maxPinnedLeadLength  100, the code points of the compact lead of a
 *                 pause with a pinned part (pauseDelivery, lib/record.js),
 *                 which shows that part whole.
 *   buildLeadBlock(text, bound)  {text}, plus compact
 *                 cutAtBoundary(text, bound) when that is shorter.
 *   buildStopBlocks  the lead, then its Next line as a whole block, then a
 *                 block per later cause, in orderStopCauses order; the
 *                 first cause leads. The lead is
 *                 buildLeadBlock(problem, maxBlockedLeadLength()).
 *
 * Invariants
 *   A null result is an agent failure: agent() returns null on an agent API
 *   error, so describeNoResult names that failure and never the step's
 *   output, which does not exist (issue 460). describeUnusableResult alone
 *   gives it that sentence, run_again and the agentFailure mark, so a caller
 *   can end the run on it (issue 457), and gives any other unusable result
 *   report (issues 481, 498).
 *
 * Why
 *   A stop names one action the user can take, and the most pressing
 *   leads, so the stop order and the action phrases share one table
 *   (issues 481, 498).
 */

function describeNoResult(result) {
  if (result !== null) {
    return '';
  }
  return 'The step\'s agent failed before it returned a result, as an agent API error such as an expired login, a rate limit or a network failure does.';
}

function describeUnusableResult(problem, result) {
  if (result !== null) {
    return { problem: problem, nextAction: 'report' };
  }
  return { problem: problem + ' ' + describeNoResult(result), nextAction: 'run_again', agentFailure: true };
}

function readBlockerAction(blocker, nextAction) {
  return quoteDiagnostic(blocker) === undefined ? 'report' : nextAction;
}

function isTransientFailure(text) {
  const patterns = [
    /\bHTTP(?:\/[0-9.]+)?:? (?:error |status )?(?:5[0-9]{2}|429)\b/i,
    /\b(?:5[0-9]{2} (?:Internal Server Error|Bad Gateway|Service Unavailable|Gateway Time-?out)|429 Too Many Requests)\b/i,
    /\b(?:connection (?:reset|refused|aborted)|ECONN(?:RESET|REFUSED|ABORTED))\b/i,
    /\b(?:could not resolve host|temporary failure in name resolution|name or service not known|DNS (?:resolution|lookup) failed|ENOTFOUND|EAI_AGAIN)\b/i,
    /\b(?:TLS|SSL) handshake (?:failed|failure|error|timeout)\b/i,
    /\bexit(?:ed)?(?: with)?(?: code| status)?:? (?:124|137)\b/i,
    /\b(?:network (?:is )?unreachable|ENETUNREACH)\b/i,
    /\b(?:connection timed out|RPC failed|early EOF|index-pack failed)\b/i
  ];
  return typeof text === 'string' && patterns.some((pattern) => pattern.test(text));
}

function stopActions(then) {
  /* INVARIANT: the key order is the stop order orderStopCauses ranks by. */
  return {
    approve: 'approve or refuse the change named above, then ' + then + ' with that answer',
    fix_cause: 'clear the cause named above, then ' + then,
    answer: then + ' with the answers in it',
    report: 'nothing in your repo needs a fix, so report this stop as a workflow defect, then ' + then,
    run_again: 'nothing in the repo needs a fix, so ' + then + ' later, for example once the machine is idle'
  };
}

function readStopAction(nextAction) {
  return Object.hasOwn(stopActions(''), nextAction) ? nextAction : 'fix_cause';
}

function describeStopAction(nextAction, then) {
  return stopActions(then)[readStopAction(nextAction)];
}

function nextStepLine(nextAction) {
  return 'Next: ' + describeStopAction(nextAction, 'run the request again') + '.';
}

function orderStopCauses(causes) {
  const actionOrder = Object.keys(stopActions(''));
  const rankCause = (cause) => actionOrder.indexOf(readStopAction(cause.nextAction));
  return causes.slice().sort((first, second) => rankCause(first) - rankCause(second));
}

function maxBlockedLeadLength() {
  /* 1000: a code point costs at most 6 notice chars (\u00XX), so the compact lead, Next line and cut marker fit noticeBudget(). */
  return 1000;
}

function maxPinnedLeadLength() {
  return 100;
}

function buildLeadBlock(text, bound) {
  const compact = cutAtBoundary(text, bound);
  return compact === text ? { text: text } : { text: text, compact: compact };
}

function buildStopBlocks(causes) {
  if (!Array.isArray(causes) || causes.length === 0) {
    throw new Error('buildStopBlocks: causes must be a non-empty array');
  }
  const [leadCause, ...laterCauses] = orderStopCauses(causes);
  const leadBlock = buildLeadBlock(leadCause.problem, maxBlockedLeadLength());
  return [leadBlock, { text: nextStepLine(leadCause.nextAction), whole: true }, ...laterCauses.map((cause) => ({ text: cause.problem }))];
}
