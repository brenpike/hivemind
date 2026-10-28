/*
 * standard-delivery record.js: the run record and the run ends of the
 * standard-delivery workflow. It holds the run record parts, the finish
 * and pause functions and the next-step lines.
 *
 * Inputs
 *   run     the run state of main.js createRunState, or undefined when the
 *           launch check failed: commits, reversibleEffects, notRunGates,
 *           taken, branch, head, waveCount and answerLog.
 *   gates   the gate loop state of runGates (gates.js), once the gates ran.
 *   result.js finish, pauseForUser, renderQuestions and the fit helpers.
 *
 * Outputs
 *   finishDeliveryBlocked, finishDeliveryComplete, finishOpenQuestions and
 *   pauseDelivery  the only run results; see the Outputs of main.js.
 *   buildRunRecordParts(run, taken, gates)  the one run record the final
 *           message, the pull request body and its comment carry.
 *   nextStepLine(nextAction) and nextActionLine(run)  the next-step lines.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Whether the run pauses or ends depends only on whether a question is
 *   open, never on where it came up or how many rounds ran (issue 453):
 *   every open question pauses through pauseDelivery while a pause can be
 *   built, and the run has no pause limit (lib/result.js pauseLimit()
 *   applies to analysis-only). Open questions end the run blocked, never
 *   complete (issue 434), only when the replies are too long to carry
 *   (reply_size) or an exact question cannot be shown whole
 *   (exact_text_size): it finishes blocked through finishOpenQuestions,
 *   lists the questions still open, names the next action with
 *   nextActionLine() and runs nothing further.
 *
 * Why
 *   Every message of the run is built here from one record, so the chat
 *   message, the pull request texts and every pause list the same facts.
 */

function renderCommits(commits) {
  if (commits.length === 0) {
    return 'This run made no commit.';
  }
  return ['Commits this run made:', ...commits.map((commit) => '- ' + commit)].join('\n');
}

function renderReversibleEffects(effects) {
  const lines = ['Effects outside the repo that the plan declares as reversible:'];
  effects.forEach((effect) => lines.push('- step ' + encodeUntrustedText(effect.stepId) + ': ' + encodeUntrustedText(effect.summary)));
  return lines.join('\n');
}

function renderNotRunGates(lines) {
  return ['Gates that did not run:', ...lines.map((line) => '- ' + line)].join('\n');
}

function buildRunRecordParts(run, taken, gates) {
  const parts = [];
  if (run.waveCount > 0) {
    parts.push({ id: 'commits', text: renderCommits(run.commits), external: false });
  }
  if (run.reversibleEffects.length > 0) {
    parts.push({ id: 'reversible_effects', text: renderReversibleEffects(run.reversibleEffects), external: true });
  }
  if (gates !== undefined) {
    parts.push({ id: 'gates', text: renderPullRequestGates(run, gates), external: false });
  } else if (run.notRunGates.length > 0) {
    parts.push({ id: 'gates', text: renderNotRunGates(run.notRunGates), external: false });
  }
  if (taken.length > 0) {
    parts.push({ id: 'decisions', text: renderDecisions(taken), compact: renderDecisionsCompact(taken), external: true });
  }
  return parts;
}

function toMessageBlock(part) {
  return { text: part.compact === undefined ? part.text : part.compact };
}

function buildRunBlocks(lead, run, taken, secondText) {
  const blocks = [{ text: lead }];
  if (secondText !== '') {
    blocks.push({ text: secondText });
  }
  blocks.push(...buildRunRecordParts(run, taken, undefined).map(toMessageBlock));
  if (blocks.length === 1) {
    blocks[0].shorten = true;
  }
  return blocks;
}

function nextStepLine(nextAction) {
  if (nextAction === 'run_again') {
    return 'Nothing in the repo needs a fix: run the request again once the cause named above has passed, for example when the machine is idle.';
  }
  return 'Fix the cause named above, then run the request again.';
}

function nextActionLine(run) {
  const again = 'Run the request again with the answers in it.';
  if (run.commits.length === 0) {
    return again;
  }
  return again + ' The new run plans what is left from the commits already on branch ' + encodeUntrustedText(cutExcerpt(run.branch)) + '.';
}

function buildBlockedLead(message) {
  const compact = cutAtBoundary(message, maxBlockedLeadLength());
  return compact === message ? { text: message } : { text: message, compact: compact };
}

function finishDeliveryBlocked(message, run, nextAction) {
  const recordBlocks = run === undefined ? [] : buildRunRecordParts(run, run.taken, undefined).map(toMessageBlock);
  return finish({ outcome: 'blocked', blocks: [buildBlockedLead(message), { text: nextStepLine(nextAction), whole: true }, ...recordBlocks] });
}

function describePullRequest(values) {
  const lines = [values.created === 'true'
    ? 'Opened pull request ' + values.url + ' on commit ' + values.head_ref_oid + '.'
    : 'Pushed commit ' + values.head_ref_oid + ' to the open pull request ' + values.url + ', and commented on it with the gates and the decisions taken.'];
  if (values.warning !== undefined) {
    lines.push('The pull request step warned: ' + values.warning + '.');
  }
  return lines.join('\n');
}

function finishDeliveryComplete(run, plan, prValues, gates) {
  const held = joinNames(configuredGateIds(run).map((gateId) => gateNames()[gateId]), 'and');
  const heldLine = 'Every plan step is done on branch ' + encodeUntrustedText(plan.branch) + ', each wave is committed, and ' + held + ' held on commit ' + run.head + '.';
  const lead = heldLine + '\n\n' + describePullRequest(prValues);
  const pr = { url: prValues.url, head_ref_oid: prValues.head_ref_oid, created: prValues.created === 'true' };
  const blocks = buildRunBlocks(lead, run, run.taken, '');
  if (gates.rejected.length > 0) {
    blocks.splice(1, 0, buildRejectedFindingsBlock(gates.notes.review, gates.rejected));
  }
  return finish({ outcome: 'complete', blocks: blocks, pr: pr });
}

function finishOpenQuestions(resolution, stopReason, run, detail) {
  const lead = 'The delivery ran no further step, because questions are still open.';
  const blocks = buildRunBlocks(lead, run, run.taken.concat(resolution.taken), renderOpenQuestions(resolution.asks, stopReason));
  blocks.splice(1, 0, { text: nextActionLine(run), whole: true });
  if (detail !== undefined) {
    blocks.splice(3, 0, detail);
  }
  return finish({ outcome: 'blocked', blocks: blocks });
}

function pauseDelivery(resolution, questions, run, detail) {
  const resumeArgs = buildResumeArgs(run.answerLog.map((entry) => entry.reply), BUILD_ID);
  if (!canCarry(resumeArgs)) {
    return finishOpenQuestions(resolution, 'reply_size', run, detail);
  }
  const questionsBlock = { text: questions, compact: renderQuestionsCompact(resolution.asks, resolution.taken) };
  if (resolution.asks.some((ask) => ask.exact === true)) {
    questionsBlock.whole = true;
  }
  const blocks = [questionsBlock];
  if (detail !== undefined) {
    blocks.push(detail);
  }
  if (run.waveCount > 0) {
    blocks.push({ text: renderCommits(run.commits) });
  }
  if (run.notRunGates.length > 0) {
    blocks.push({ text: renderNotRunGates(run.notRunGates) });
  }
  if (!canShowWhole({ resumeArgs: resumeArgs, blocks: blocks })) {
    return finishOpenQuestions(resolution, 'exact_text_size', run, detail);
  }
  return pauseForUser({ resumeArgs: resumeArgs, blocks: blocks });
}
