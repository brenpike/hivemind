/*
 * standard-delivery pr.js: the pull request step of the standard-delivery
 * workflow. It holds the pull request title, body and comment, the PR
 * runner prompt, the check of its relay and the step.
 *
 * Inputs
 *   run    the run state of main.js createRunState: head, commits, taken,
 *          reversibleEffects, notRunGates and draft.
 *   plan   the accepted plan, from runPlanningPass (plan.js).
 *   gates  the gate loop state of runGates (gates.js): notes, rejected and
 *          runs.pr, the count of this step's runs in the pass.
 *   maxTitleLength() and maxPullRequestTextLength() from main.js.
 *
 * Outputs
 *   runPullRequestStep(run, plan, gates)  {result}: finishDeliveryComplete
 *          naming the pull request, a pause, or a blocked finish, or
 *          {rerun: true} when the user replied to its stop.
 *   renderLiteralBlock(text)  the literal fenced block the pull request
 *          texts put external text in.
 *   The step, as meta.js names it:
 *   PR      once every configured gate held on one commit H, a haiku
 *           runner invokes hivemind:open-plan-pr once under the push grant
 *           and the git-script sentence. Its inputs block holds only head,
 *           base, expect_commit H, the title, body and comment the code
 *           builds, and draft from the launch. This runner is the only push the workflow makes, so
 *           every push carries expect_commit. Its stdout parses with
 *           openPlanPrRoutingSpec(), head_ref_oid must equal H, and the run
 *           finishes complete with pr. The runner call goes through
 *           runRunnerRelay (relay.js), so a transient block runs once more
 *           under pr-P-retry. A pull request text over its size limit and a
 *           head_ref_oid other than H are terminal stops. A blocked,
 *           malformed or other unusable relay pauses through stopDelivery
 *           (record.js). The step makes one runner call: the gate loop
 *           runs the head check after a reply, then this step again under
 *           pr-P-N, N from 2, or the gates first when the head moved, so
 *           expect_commit is always a head the run read. The body is the
 *           plan summary and the
 *           comment a fixed lead, each followed by the one run record
 *           buildRunRecordParts() returns, the same record the final
 *           message carries, with every taken decision and no reviewer
 *           text. The plan text that can carry external content sits in
 *           literal fenced blocks.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   The pull request body and comment carry the one run record
 *   buildRunRecordParts() returns, as the final message does. The summary
 *   and the external parts of that record, the reversible effects and the
 *   decisions, reach the pull request body and comment only through
 *   renderLiteralBlock(), so GitHub shows them as literal text and an
 *   at-mention, issue reference or HTML in them does nothing. The gates,
 *   the commits and the comment lead are code-built and stay plain. The
 *   title stays plain text: GitHub renders titles with code spans only and
 *   takes no mentions from them, and a wrapper would reach the squash
 *   commit subject.
 *   The relay is read through describeUnusableResult (lib/result.js): a
 *   null result, an agent failure, adds the agent-failure sentence and
 *   next action run_again, and stopDelivery ends the run on it; any other
 *   unusable result keeps the fix line and pauses.
 *
 * Why
 *   The pull request is the one push of the run, so its texts and the
 *   check of its head sit in one place.
 */

function reviewDecisionProblems() {
  return {
    [DIMINISHING_RETURNS_EXIT_KIND]: 'Local review saw diminishing returns with findings still open. Stop fixing and hold the local review gate on that commit?',
    [PLANNER_ESCALATION_ROUTING_KIND]: 'Local review escalated a finding to the planner. Go back to planning, from fresh facts, for its remediation?',
    [ROOT_CLUSTER_ROUTING_KIND]: 'Local review found findings with one suspected root. Go back to planning, from fresh facts, for a remediation that closes the class?'
  };
}

function toPullRequestDecision(entry) {
  if (Object.values(reviewQuestionKinds()).includes(entry.kind)) {
    return { brief: removeReviewerText(entry.brief) };
  }
  const problem = reviewDecisionProblems()[entry.kind];
  return problem === undefined ? { brief: entry.brief } : { brief: Object.assign({}, entry.brief, { problem: problem }) };
}

function isPullRequestCharacter(codePoint, keepsLines) {
  if (keepsLines && (codePoint === 9 || codePoint === 10)) {
    return true;
  }
  return codePoint >= 32 && (codePoint < 127 || codePoint > 159);
}

function cleanPullRequestText(text, keepsLines) {
  return Array.from(text).map((character) => (isPullRequestCharacter(character.codePointAt(0), keepsLines) ? character : ' ')).join('');
}

function renderLiteralBlock(text) {
  const longestRun = Array.from(text.matchAll(/`+/g)).reduce((longest, match) => Math.max(longest, match[0].length), 0);
  const fence = '`'.repeat(Math.max(3, longestRun + 1));
  return fence + '\n' + text + '\n' + fence;
}

function readFirstSentence(text) {
  const end = /[.!?](?= |$)/.exec(text);
  const sentence = end === null ? text : text.slice(0, end.index + 1);
  return (sentence.endsWith('.') ? sentence.slice(0, -1) : sentence).trimEnd();
}

function cutTitleText(text, room) {
  const characters = Array.from(text);
  if (characters.length <= room) {
    return text;
  }
  const lastSpace = characters.slice(0, room + 1).lastIndexOf(' ');
  const kept = characters.slice(0, lastSpace > 0 ? lastSpace : room).join('');
  return kept.replace(/[\s,;:-]+$/u, '');
}

function buildPullRequestTitle(plan) {
  const prefix = commitTypeMap()[plan.classification] + (plan.breaking ? '!' : '') + ':';
  const text = cleanPullRequestText(plan.summary, false).replace(/\s+/gu, ' ').trim();
  const sentence = cutTitleText(readFirstSentence(text), maxTitleLength() - prefix.length - 1);
  return sentence === '' ? prefix : prefix + ' ' + sentence;
}

function renderPullRequestGates(run, gates) {
  const lines = ['Gates:'];
  for (const gateId of gateIds()) {
    const name = gateNames()[gateId];
    if (!configuredGateIds(run).includes(gateId)) {
      lines.push('- ' + name + ': not configured for this run');
      continue;
    }
    lines.push('- ' + name + ': ' + gates.notes[gateId] + ', held on commit ' + gates.held[gateId]);
  }
  return lines.join('\n');
}

function renderPullRequestPart(part, isCompact) {
  const text = isCompact && part.compact !== undefined ? part.compact : part.text;
  return part.external ? renderLiteralBlock(text) : text;
}

function renderPullRequestRecord(run, gates, isCompact) {
  return buildRunRecordParts(run, run.taken.map(toPullRequestDecision), gates).map((part) => renderPullRequestPart(part, isCompact));
}

function buildPullRequestBody(run, plan, gates, isCompact) {
  const parts = plan.summary.trim() === '' ? [] : [renderLiteralBlock(plan.summary)];
  parts.push(...renderPullRequestRecord(run, gates, isCompact));
  return cleanPullRequestText(parts.join('\n\n'), true);
}

function buildPullRequestComment(run, gates, isCompact) {
  const parts = ['The delivery pushed commit ' + run.head + ' to this pull request.', ...renderPullRequestRecord(run, gates, isCompact)];
  return cleanPullRequestText(parts.join('\n\n'), true);
}

function fitPullRequestText(buildText) {
  const full = buildText(false);
  if (full.length <= maxPullRequestTextLength()) {
    return { text: full };
  }
  const compact = buildText(true);
  return compact.length <= maxPullRequestTextLength() ? { text: compact } : { size: compact.length };
}

function describePullRequestTextSize(noun, size) {
  return 'The pull request ' + noun + ' would be ' + size + ' characters even with the decisions in short form, more than the limit of ' + maxPullRequestTextLength() + ', so ' + RUN_NAME + ' stopped before the pull request and pushed nothing.';
}

function buildPullRequestTexts(run, plan, gates) {
  const body = fitPullRequestText((isCompact) => buildPullRequestBody(run, plan, gates, isCompact));
  if (body.text === undefined) {
    return { problem: describePullRequestTextSize('body', body.size) };
  }
  const comment = fitPullRequestText((isCompact) => buildPullRequestComment(run, gates, isCompact));
  if (comment.text === undefined) {
    return { problem: describePullRequestTextSize('comment', comment.size) };
  }
  return { title: buildPullRequestTitle(plan), body: body.text, comment: comment.text };
}

function buildPullRequestPrompt(plan, head, texts, draft) {
  return [
    'Invoke the hivemind:open-plan-pr skill once, with each value of the inputs block below, word for word, as the input of the same name, to push the working branch and open its pull request or reuse the open one.',
    pushGrantSentence(),
    gitScriptSentence('hivemind:open-plan-pr'),
    dataBlocksSentence(),
    skillRunOnlySentence(),
    '',
    formatDataBlock('inputs', { head: plan.branch, base: plan.base, expect_commit: head, title: texts.title, body: texts.body, comment: texts.comment, draft: draft })
  ].join('\n');
}

function checkPullRequestRelay(relay, head) {
  const stopped = 'so ' + RUN_NAME + ' stopped. The branch may be on its remote, and a pull request may be open for it.';
  if (!validateSchema(RELAY_SCHEMA, relay).ok) {
    return describeUnusableResult('The pull request step returned a result it could not use, ' + stopped, relay);
  }
  if (relay.outcome === 'blocked') {
    return { problem: 'The pull request step was blocked, ' + stopped + ' ' + describeRelayBlocker(relay.stderr, true) };
  }
  const values = readRelayedLines(relay, openPlanPrRoutingSpec());
  if (values === undefined || values.commented === values.created) {
    return { problem: 'The pull request step returned malformed routing lines, ' + stopped };
  }
  if (values.head_ref_oid !== head) {
    return { problem: 'The pull request step reported a head commit other than the commit every gate held on, ' + stopped, terminal: true };
  }
  return { values: values };
}

function describePullRequestLabel(run, count) {
  return 'pr-' + run.pass + (count === 1 ? '' : '-' + count);
}

async function runPullRequestStep(run, plan, gates) {
  const texts = buildPullRequestTexts(run, plan, gates);
  if (texts.problem !== undefined) {
    return stopDelivery([{ problem: texts.problem, terminal: true }], run, [], false);
  }
  phase('PR');
  const relay = await runRunnerRelay(addResumeNote(buildPullRequestPrompt(plan, run.head, texts, run.draft), run), describePullRequestLabel(run, gates.runs.pr), 'PR');
  const checked = checkPullRequestRelay(relay, run.head);
  if (checked.problem === undefined) {
    return { result: finishDeliveryComplete(run, plan, checked.values, gates) };
  }
  return stopDelivery([checked], run, [], false);
}
