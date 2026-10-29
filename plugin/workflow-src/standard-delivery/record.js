/*
 * standard-delivery record.js: the run record and the run ends of the
 * standard-delivery workflow. It holds the run record parts and the
 * finish and pause functions.
 *
 * Inputs
 *   run     the run state of main.js createRunState, or undefined when the
 *           launch check failed: reversibleEffects, notRunGates, taken,
 *           branch, head, headRound, waveCount and answerLog.
 *   gates   the gate loop state of runGates (gates.js), once the gates ran.
 *   lead    the what-happened line of a pause, built by its call site.
 *   causes  the causes of a stop, {problem, nextAction?, terminal?,
 *           agentFailure?} each: terminal true marks a cause no reply can
 *           clear, and agentFailure comes only from describeUnusableResult.
 *   endLines  lines a stop shows after its causes, such as a commit end.
 *   commit, branch  a head read from a checked relay: the commit line of
 *           a molt relay or of a branch relay, and the plan branch.
 *   isReplan  true when a reply to a stop plans again from fresh facts.
 *   result.js finish, which builds a blocked message from the causes,
 *   pauseForUser and the fit helpers, and brief.js renderQuestions,
 *   renderOpenQuestions and renderDecisionsCompact.
 *
 * Outputs
 *   finishDeliveryBlocked, finishDeliveryComplete, finishOpenQuestions and
 *   pauseDelivery  the only run results; see the Outputs of main.js.
 *   stopDelivery(causes, run, endLines, isReplan)  {result}, the blocked end
 *           or the pause, or on a reply {replan: {reason}} when isReplan,
 *           a new pass outside maxReplans(), else {rerun: true}: the gate
 *           loop takes the stopped step again, reading the head first when
 *           that step does not read it itself (gates.js).
 *   observeHead(run, commit, branch)  sets run.head to commit, run.branch
 *           to branch and run.headRound to the run.answerLog length.
 *   buildRunRecordParts(run, taken, gates)  the one run record the pull
 *           request body and its comment carry, with no commit list.
 *
 * Message shape (issue 460)
 *   Every chat message has one shape, built here:
 *   pauseDelivery(resolution, run, lead)  the lead, then
 *           renderQuestions(resolution.asks), a whole block when an ask is
 *           exact. The reply line is the last line. No commit, gate line,
 *           taken decision or detail block. A lead longer than
 *           maxBlockedLeadLength() code points has the cutAtBoundary prefix
 *           of at most those code points as its compact form.
 *   stopDelivery  ends through finishDeliveryBlocked when any cause is
 *           terminal or an agent failure. Otherwise it asks one undecided
 *           step_stop question (buildStepStopBrief, briefs.js) through
 *           askTail (gates.js), whose lead is the cause problems in
 *           buildStopBlocks order, then the end lines, one per line.
 *   finishOpenQuestions  finishDeliveryBlocked over one cause, the fixed
 *           lead with next action answer, with the open questions as its
 *           end line and the round's taken decisions added to the run's.
 *   finishDeliveryBlocked(causes, run, endLines)  finish({outcome:
 *           'blocked', causes, blocks}) (lib/result.js), which leads with
 *           buildStopBlocks(causes): the lead, the Next line as a whole
 *           block and one block per later cause. The blocks are one per end
 *           line (the open questions, or the commit end runCommitStep
 *           passes), one line naming the encoded branch and its head
 *           only once a wave ran, then the
 *           reversible effects and the taken decisions, one line each
 *           (renderDecisionsCompact), as every final message lists them
 *           (ADR-0037 decision 3).
 *   finishDeliveryComplete  one line naming the pull request opened or
 *           pushed to and its commit, one line naming the gates that held
 *           and any gate not configured, the warning line when there is
 *           one, the rejected findings block, then the reversible effects
 *           and the taken decisions, one line each.
 *   Every Next line starts with 'Next:' and points at no cause the lead
 *   does not name. No message and no pull request text lists the
 *   commits: the branch and the pull request on GitHub hold them
 *   (ADR-0037 decision 2).
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   One head writer (issue 457): observeHead is the only code that writes
 *   run.head, run.branch or run.headRound, and its callers feed it only a
 *   commit read from a checked relay: runCommitStep (relay.js) the molt
 *   commit, the head check of the gate loop (gates.js) included, and
 *   runDeliveryPass (main.js) the branch commit of each new pass before
 *   any wave. One head read per reply: every reply adds one entry to
 *   run.answerLog, its round, so the head is unread exactly when
 *   run.headRound is behind run.answerLog.length, whatever route the reply
 *   took. The run keeps no commit list, so no record of the run can drop
 *   a commit made during a pause.
 *   One stop path (issue 457): a stop ends the run only on a terminal
 *   cause, an agent failure, a size limit (finishOpenQuestions) or the
 *   launch check. Every other stop pauses through stopDelivery, and a reply
 *   when the cause is still not fixed pauses again, with no cap. So
 *   finishDeliveryBlocked has no caller but stopDelivery,
 *   finishOpenQuestions and the launch end of runDelivery (main.js).
 *   Whether the run pauses or ends depends only on whether a question is
 *   open, never on where it came up or how many rounds ran (issue 453):
 *   every open question pauses through pauseDelivery while a pause can be
 *   built, and the run has no pause limit (lib/result.js pauseLimit()
 *   applies to analysis-only). Open questions end the run blocked, never
 *   complete (issue 434), only when the replies are too long to carry
 *   (reply_size) or an exact question cannot be shown whole
 *   (exact_text_size): it finishes blocked through finishOpenQuestions,
 *   whose Next line is nextStepLine('answer'), lists the questions still
 *   open and runs nothing further. Once a wave ran, the branch line
 *   names the branch.
 *
 * Why
 *   Every message of the run is built here, so each one has the same short
 *   shape: what happened, then what the user decides or does next. Gate
 *   lines and detail blocks stood between the user and that choice
 *   (issue 460), so they stay in the pull request texts. A commit list
 *   would be a second record of the branch (ADR-0037 decision 2), so
 *   none exists.
 */

function renderReversibleEffects(effects) {
  const lines = ['Effects outside the repo that the plan declares as reversible:'];
  effects.forEach((effect) => lines.push('- step ' + encodeUntrustedText(effect.stepId) + ': ' + encodeUntrustedText(effect.summary)));
  return lines.join('\n');
}

function renderNotRunGates(lines) {
  return ['Gates that did not run:', ...lines.map((line) => '- ' + line)].join('\n');
}

function observeHead(run, commit, branch) {
  run.head = commit;
  run.branch = branch;
  run.headRound = run.answerLog.length;
}

function buildRunRecordParts(run, taken, gates) {
  const parts = [];
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

function describeBranchLine(run) {
  return 'Branch ' + encodeUntrustedText(run.branch) + ' is at commit ' + run.head + '.';
}

function buildRecordTailBlocks(run, taken) {
  const blocks = [];
  if (run.reversibleEffects.length > 0) {
    blocks.push({ text: renderReversibleEffects(run.reversibleEffects) });
  }
  if (taken.length > 0) {
    blocks.push({ text: renderDecisionsCompact(taken) });
  }
  return blocks;
}

function finishDeliveryBlocked(causes, run, endLines = []) {
  const blocks = endLines.map((line) => ({ text: line }));
  if (run !== undefined && run.waveCount > 0) {
    blocks.push({ text: describeBranchLine(run) });
  }
  if (run !== undefined) {
    blocks.push(...buildRecordTailBlocks(run, run.taken));
  }
  return finish({ outcome: 'blocked', causes: causes, blocks: blocks });
}

function describePullRequest(values) {
  return values.created === 'true'
    ? 'Opened pull request ' + values.url + ' on commit ' + values.head_ref_oid + '.'
    : 'Pushed commit ' + values.head_ref_oid + ' to the open pull request ' + values.url + ' and commented on it.';
}

function describeHeldGates(run) {
  const held = configuredGateIds(run).map((gateId) => gateNames()[gateId]);
  const notConfigured = gateIds().filter((gateId) => !configuredGateIds(run).includes(gateId)).map((gateId) => gateNames()[gateId]);
  const heldLine = joinNames(held, 'and') + ' held on commit ' + run.head + '.';
  const line = heldLine.charAt(0).toUpperCase() + heldLine.slice(1);
  return notConfigured.length === 0 ? line : line + ' Not configured for this run: ' + joinNames(notConfigured, 'and') + '.';
}

function finishDeliveryComplete(run, plan, prValues, gates) {
  const pr = { url: prValues.url, head_ref_oid: prValues.head_ref_oid, created: prValues.created === 'true' };
  const blocks = [{ text: describePullRequest(prValues) }, { text: describeHeldGates(run) }];
  if (prValues.warning !== undefined) {
    blocks.push({ text: 'The pull request step warned: ' + prValues.warning + '.' });
  }
  if (gates.rejected.length > 0) {
    blocks.push(buildRejectedFindingsBlock(gates.notes.review, gates.rejected));
  }
  blocks.push(...buildRecordTailBlocks(run, run.taken));
  return finish({ outcome: 'complete', blocks: blocks, pr: pr });
}

function finishOpenQuestions(resolution, stopReason, run) {
  const cause = { problem: 'The delivery ran no further step, because questions are still open.', nextAction: 'answer' };
  return finishDeliveryBlocked([cause], { ...run, taken: run.taken.concat(resolution.taken) }, [renderOpenQuestions(resolution.asks, stopReason)]);
}

function pauseDelivery(resolution, run, lead) {
  const resumeArgs = buildResumeArgs(run.answerLog.map((entry) => entry.reply), BUILD_ID);
  if (!canCarry(resumeArgs)) {
    return finishOpenQuestions(resolution, 'reply_size', run);
  }
  const questionsBlock = { text: renderQuestions(resolution.asks) };
  if (resolution.asks.some((ask) => ask.exact === true)) {
    questionsBlock.whole = true;
  }
  const compactLead = cutAtBoundary(lead, maxBlockedLeadLength());
  const blocks = [compactLead === lead ? { text: lead } : { text: lead, compact: compactLead }, questionsBlock];
  if (!canShowWhole({ resumeArgs: resumeArgs, blocks: blocks })) {
    return finishOpenQuestions(resolution, 'exact_text_size', run);
  }
  return pauseForUser({ resumeArgs: resumeArgs, blocks: blocks });
}

function describeStopLead(causes, endLines) {
  const causeTexts = buildStopBlocks(causes).filter((block) => block.whole !== true).map((block) => block.text);
  return causeTexts.concat(endLines).join('\n');
}

function stopDelivery(causes, run, endLines, isReplan) {
  if (causes.some((cause) => cause.terminal === true || cause.agentFailure === true)) {
    return { result: finishDeliveryBlocked(causes, run, endLines) };
  }
  const asked = askTail(buildUndecidedAsk(buildStepStopBrief(causes, isReplan)), run, describeStopLead(causes, endLines));
  if (asked.answer === undefined) {
    return asked;
  }
  if (isReplan) {
    return { replan: { reason: 'The user replied to a stop the run paused at, so plan again from the fresh facts with the answers block.' } };
  }
  return { rerun: true };
}
