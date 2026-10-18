/*
 * result.js: the value a workflow run returns, and the pause contract.
 *
 * Inputs
 *   pauseForUser({message, resumeArgs, decisions})
 *     message     non-empty string. The text the user reads.
 *     resumeArgs  plain JSON object. The args to relaunch with, before the
 *                 reply is added. It has no replyField() key.
 *     decisions   array. The decisions the run took so far, in order.
 *   finish({outcome, message, decisions})
 *     outcome     'complete' or 'blocked'.
 *     message     non-empty string. The run's final text for the user.
 *     decisions   array, as above.
 *   canPause(pausesSoFar)
 *     pausesSoFar non-negative integer. How many times this run has paused.
 *
 * Outputs
 *   pauseForUser  {needs_user: true, message, resume_args, decisions}
 *   finish        {needs_user: false, outcome, message, decisions}
 *   resultFields  every top-level field name a result can carry.
 *   replyField    the args key a resumed run reads the reply from: 'reply'.
 *   pauseLimit    the most times one run may pause: 3.
 *   canPause      true when pausesSoFar is below pauseLimit().
 *
 * Contract the overlord relays
 *   Only the harness completion notice carries the result. A model's own
 *   summary of the run never counts.
 *   needs_user true: show message to the user as is. Then relaunch the same
 *   run with args set to resume_args plus reply set to the user's reply word
 *   for word. That is the only resume rule: nothing else in args is read as
 *   a reply. Never answer for the user.
 *   needs_user false: show message to the user as is. The run is over.
 *   decisions lists what the run decided for the user. message already
 *   states them, so the overlord shows message and does not act on decisions.
 *
 * Invariants
 *   A run pauses at most pauseLimit() times. After that it finishes with
 *   outcome 'complete' and its message lists the questions still open.
 *   Open questions never make a run end as 'blocked'.
 *   resume_args is the only state that crosses a pause, so the workflow keeps
 *   its pause count and earlier answers there, in fields it alone reads.
 *   resume_args never has a reply key, so a stale reply cannot be replayed.
 *   Invalid input throws instead of returning a partial result.
 *
 * Why
 *   A running workflow cannot take input mid-run, so asking the user means
 *   returning. One fixed shape lets the overlord relay and resume any
 *   workflow the same way, and the decisions travel in the final message
 *   instead of a separate journal.
 */

function resultFields() {
  return ['needs_user', 'outcome', 'message', 'resume_args', 'decisions'];
}

function replyField() {
  return 'reply';
}

function pauseLimit() {
  return 3;
}

function canPause(pausesSoFar) {
  if (!Number.isInteger(pausesSoFar) || pausesSoFar < 0) {
    throw new Error('canPause: pausesSoFar must be a non-negative integer');
  }
  return pausesSoFar < pauseLimit();
}

function pauseForUser({ message, resumeArgs, decisions }) {
  if (typeof resumeArgs !== 'object' || resumeArgs === null || Array.isArray(resumeArgs)) {
    throw new Error('pauseForUser: resumeArgs must be a plain object');
  }
  if (Object.prototype.hasOwnProperty.call(resumeArgs, replyField())) {
    throw new Error('pauseForUser: resumeArgs must not have a ' + replyField() + ' key');
  }
  assertMessageAndDecisions('pauseForUser', message, decisions);
  return {
    needs_user: true,
    message: message,
    resume_args: resumeArgs,
    decisions: decisions
  };
}

function finish({ outcome, message, decisions }) {
  if (outcome !== 'complete' && outcome !== 'blocked') {
    throw new Error('finish: outcome must be complete or blocked, got ' + JSON.stringify(outcome));
  }
  assertMessageAndDecisions('finish', message, decisions);
  return {
    needs_user: false,
    outcome: outcome,
    message: message,
    decisions: decisions
  };
}

function assertMessageAndDecisions(caller, message, decisions) {
  if (typeof message !== 'string' || message.trim() === '') {
    throw new Error(caller + ': message must be a non-empty string');
  }
  if (!Array.isArray(decisions)) {
    throw new Error(caller + ': decisions must be an array');
  }
}
