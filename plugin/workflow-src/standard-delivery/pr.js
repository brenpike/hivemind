/*
 * standard-delivery pr.js: the pull request step of the standard-delivery
 * workflow. It holds the pull request title, body and comment, the PR
 * runner prompt, the check of its relay and the step.
 *
 * Inputs
 *   run    the run state of main.js createRunState: head, taken,
 *          approvals, reversibleEffects, notRunGates and draft.
 *   plan   the accepted plan, from runPlanningPass (plan.js). plan.title
 *          reaches only the pull request title, and plan.digest, the
 *          step ids, outcomes and files and the optional plan.closes only
 *          the body. plan.summary reaches no pull request text.
 *   gates  the gate loop state of runGates (gates.js): notes, rejected and
 *          runs.pr, the count of this step's runs in the pass.
 *   maxTitleLength() and maxPullRequestTextLength() from main.js.
 *
 * Outputs
 *   runPullRequestStep(run, plan, gates)  {result}: finishDeliveryComplete
 *          naming the pull request, a pause, or a blocked finish, or
 *          {rerun: true} when the user replied to its stop.
 *   neutralizePullRequestText(text)  text in which nothing mentions, closes
 *          or links an issue; other Markdown still renders: the one renderer
 *          of every external part of the pull request texts.
 *   describeClosesProblem(plan, references)  the last check of
 *          describePlanProblem (plan.js): the problem of a plan.closes
 *          number that is not the number of one of references, the launch
 *          references of run.references, naming its index, else undefined.
 *   The step, as meta.js names it:
 *   PR      once every configured gate held on one commit H, a haiku
 *           synapse runner runs the open-plan-pr command once. The
 *           command carries only --head, --base, --expect-commit H,
 *           --inputs, the path buildInputsPath (relay.js) builds for the
 *           call label, and --body-file, the one it builds for that label
 *           and -body. The inputs_file content is a JSON string of only the
 *           title and comment the code builds and draft from the launch,
 *           and the body_file content the body the code builds, the raw
 *           text the script reads whole. This runner is the only push the
 *           workflow makes, so every push carries --expect-commit. A
 *           command value outside its class (describeCommandStop,
 *           relay.js), a body path whose token passes 64 characters
 *           among them, is a terminal stop before the call. Its stdout parses with
 *           openPlanPrRoutingSpec(), head_ref_oid must equal H, and the run
 *           finishes complete with pr. The runner call goes through
 *           runRunnerRelay (relay.js), so a transient block runs once more
 *           under pr-P-retry with the inputs and body paths of that label, and the
 *           step checks the words of both labels before the call. A pull
 *           request text over its size limit and a
 *           head_ref_oid other than H are terminal stops. A blocked,
 *           malformed or other unusable relay pauses through stopDelivery
 *           (record.js). The step makes one runner call: the gate loop
 *           runs the head check after a reply, then this step again under
 *           pr-P-N, N from 2, or the gates first when the head moved, so
 *           expect_commit is always a head the run read. The title is the
 *           commit type of the plan classification, the breaking marker, a
 *           colon and plan.title, never the summary, cut at a word only when
 *           longer than maxTitleLength() code points, never inside a
 *           bracket the cut text opened (issue 469). buildTitleText(plan)
 *           gives the text after the prefix; the plan check refuses a plan
 *           whose text is empty, so the title is never only its type
 *           (issue 469). The body is the closing lines of
 *           renderClosingLines(plan), one Closes line per plan.closes
 *           number, then the digest paragraph, digest.problem then
 *           digest.change through renderText with a blank one left out,
 *           then a Steps: line and one line per step, its id, files and
 *           outcome through renderText (issue 506). The comment is a fixed
 *           lead with no closing line. Each is followed by the one run
 *           record buildRunRecordParts() returns, every decision in it one
 *           compact line, the question and the chosen option with no why.
 *           No pull request text holds a code fence.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   The pull request body and comment carry the one run record
 *   buildRunRecordParts() returns. The digest, the step lines and the
 *   external parts of that record reach the pull request body and comment
 *   only through neutralizePullRequestText(), so an at-mention, issue
 *   reference, URL or HTML in them links, closes or notifies nothing. The
 *   gates, the labels and the comment lead are code-built and stay plain.
 *   So are the closing lines, which open the body, so GitHub links each
 *   issue they name as closed by the pull request (issue 491): each is the
 *   fixed text and an integer the plan check found among the launch
 *   references, never planner text.
 *   The closes check is membership only: which reference the run fixes is
 *   the planner's judgment, and the engine never reads the facts file, so
 *   code does not check that a number names an issue rather than a pull
 *   request; a Closes line naming a pull request closes nothing. The
 *   title stays plain text: GitHub renders titles with code spans only and
 *   takes no mentions from them, and a wrapper would reach the squash
 *   commit subject.
 *   No title, body or comment holds a forbiddenSubjectTexts() string
 *   (relay.js), in any case: code holds this check, not a skill body the
 *   runner may never read, so buildPullRequestTexts makes one a terminal
 *   stop before any push (issue 467). The check reads the neutralized
 *   texts: neutralizing wraps or escapes no character of those strings, so
 *   each stays detectable. A text over maxPullRequestTextLength() is a
 *   terminal stop naming its size; no shorter form is tried.
 *   The relay is read through describeUnusableResult (lib/stop.js): a
 *   null result, an agent failure, adds the agent-failure sentence and
 *   next action run_again, and stopDelivery ends the run on it; any other
 *   unusable result, malformed routing lines among them, gets report and
 *   pauses. The text size and attribution stops are report too.
 *   A stop names what the run saw of the push: a blocked relay whose
 *   stderr holds a synapse-gate denial (isGateDenial, relay.js) or an
 *   inputs refusal of the open-plan-pr script (isInputsRefusal), each made
 *   before any push, says this step pushed nothing and is report. A
 *   blocked relay whose stderr holds the line pushed: no says the same and
 *   keeps the action readRelayAction gives its blocker, and one holding
 *   pushed: yes says the step pushed commit H. Any
 *   other stop says the run did not see whether it pushed, and that taking
 *   the step again pushes the same commit and reuses a pull request open
 *   on it, since the script pushes --expect-commit and reuses the open
 *   pull request on the pushed commit. Any other blocked relay takes
 *   readRelayAction. isInputsRefusal matches a blocker line of each inputs
 *   file refusal and each validate_program reason of the script, none of
 *   which comes after the push, and a parity test pins it to the script.
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
  const problem = reviewDecisionProblems()[entry.kind];
  return problem === undefined ? entry : { brief: Object.assign({}, entry.brief, { problem: problem }), kind: entry.kind };
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

/**
 * Returns text with each URL, owner/repo reference, issue reference, GH-N
 * reference and at-mention in a single-backtick code span, and every
 * backslash, backtick, <, > and & outside them backslash-escaped, so nothing
 * in the text mentions, closes or links an issue. Other Markdown (headings,
 * emphasis, links, images) still renders.
 * No span holds a backtick or a blank, so each one is literal whole.
 */
function neutralizePullRequestText(text) {
  return text.split(/((?:https?:\/\/|www\.)[^\s`]+|(?<![\w.-])[\w.-]+\/[\w.-]+#\d+|#\d+|GH-\d+|@[\w-]+(?:\/[\w-]+)?)/i)
    .map((piece, index) => (index % 2 === 1 ? '`' + piece + '`' : piece.replace(/[\\`<>&]/g, '\\$&')))
    .join('');
}

function cleanTitleText(text) {
  return cleanPullRequestText(text, false).replace(/\s+/gu, ' ').trim();
}

function trimTitleEnd(text) {
  return text.replace(/[\s,;:-]+$/u, '');
}

/**
 * Returns the indexes, in order, of each (, [ or { in characters that no
 * matching closer after it closes. A closer pops only the opener on top of
 * the stack it matches, so every opener before the first returned index
 * is closed before that index.
 */
function findUnclosedOpeners(characters) {
  const closers = { '(': ')', '[': ']', '{': '}' };
  const openIndexes = [];
  characters.forEach((character, index) => {
    if (closers[character] !== undefined) {
      openIndexes.push(index);
    } else if (openIndexes.length > 0 && closers[characters[openIndexes[openIndexes.length - 1]]] === character) {
      openIndexes.pop();
    }
  });
  return openIndexes;
}

function closeTitleBrackets(text) {
  const characters = Array.from(text);
  const openIndexes = findUnclosedOpeners(characters);
  if (openIndexes.length === 0) {
    return text;
  }
  const beforeOpener = trimTitleEnd(characters.slice(0, openIndexes[0]).join(''));
  if (beforeOpener !== '') {
    return beforeOpener;
  }
  return trimTitleEnd(characters.filter((character, index) => !openIndexes.includes(index)).join('').trim());
}

function cutTitleText(text, room) {
  const characters = Array.from(text);
  if (characters.length <= room) {
    return text;
  }
  const lastSpace = characters.slice(0, room + 1).lastIndexOf(' ');
  const kept = characters.slice(0, lastSpace > 0 ? lastSpace : room).join('');
  return closeTitleBrackets(trimTitleEnd(kept));
}

function buildTitlePrefix(plan) {
  return commitTypeMap()[plan.classification] + (plan.breaking ? '!' : '') + ':';
}

/**
 * Returns the pull request title text after its prefix: plan.title cleaned
 * as pull request text and cut to the room maxTitleLength() leaves after
 * the prefix and one space. describePlanProblem (plan.js) refuses a plan
 * whose text is empty, so a checked plan never gets a type-only title.
 */
function buildTitleText(plan) {
  return cutTitleText(cleanTitleText(plan.title), maxTitleLength() - buildTitlePrefix(plan).length - 1);
}

function buildPullRequestTitle(plan) {
  const prefix = buildTitlePrefix(plan);
  const text = buildTitleText(plan);
  return text === '' ? prefix : prefix + ' ' + text;
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

function renderPullRequestPart(part) {
  return part.external ? neutralizePullRequestText(part.text) : part.text;
}

function renderPullRequestRecord(run, gates) {
  return buildRunRecordParts(run, run.taken.map(toPullRequestDecision), gates).map(renderPullRequestPart);
}

function listCloses(plan) {
  return plan.closes === undefined ? [] : plan.closes;
}

/**
 * Returns the plan problem of the first plan.closes number that is not the
 * number of one of references, the launch digit strings, naming its index,
 * or undefined when every number is one of them. describePlanProblem
 * (plan.js) returns it as its last check. It compares decimal text, never
 * a Number of a reference: the number's String against each reference with
 * its leading zeros cut, so a reference past the safe integer range matches
 * only its own digits, and a reference of zeros alone matches no number.
 */
function describeClosesProblem(plan, references) {
  const index = listCloses(plan).findIndex((number) => !references.some((reference) => reference.replace(/^0+/, '') === String(number)));
  return index === -1 ? undefined : 'The plan names an issue at closes[' + index + '] that is not one of the references the run started with, so ' + RUN_NAME + ' stopped.';
}

/**
 * Returns one plain line Closes #N for each distinct plan.closes number, in
 * plan order. describeClosesProblem refuses a number that is not a launch
 * reference, so each line names a number the launch gave.
 */
function renderClosingLines(plan) {
  return [...new Set(listCloses(plan))].map((number) => 'Closes #' + number);
}

/**
 * Returns the digest paragraph of the body: digest.problem, then
 * digest.change, each through renderText, a blank one left out, or '' when
 * both are blank.
 */
function renderDigestParagraph(plan) {
  return [plan.digest.problem, plan.digest.change].filter((text) => text.trim() !== '').map(renderText).join(' ');
}

function renderStepLines(plan) {
  return ['Steps:', ...plan.steps.map((step) => '- ' + renderText(step.id) + ' (' + step.files.map(renderText).join(', ') + '): ' + renderText(step.outcome))].join('\n');
}

function buildPullRequestBody(run, plan, gates) {
  const closingLines = renderClosingLines(plan);
  const parts = closingLines.length === 0 ? [] : [closingLines.join('\n')];
  const digest = renderDigestParagraph(plan);
  if (digest !== '') {
    parts.push(neutralizePullRequestText(digest));
  }
  parts.push(neutralizePullRequestText(renderStepLines(plan)), ...renderPullRequestRecord(run, gates));
  return cleanPullRequestText(parts.join('\n\n'), true);
}

function buildPullRequestComment(run, gates) {
  const parts = ['The delivery pushed commit ' + run.head + ' to this pull request.', ...renderPullRequestRecord(run, gates)];
  return cleanPullRequestText(parts.join('\n\n'), true);
}

function describePullRequestTextSize(noun, size) {
  return 'The pull request ' + noun + ' would be ' + size + ' characters, more than the limit of ' + maxPullRequestTextLength() + ', so ' + RUN_NAME + ' stopped before the pull request and pushed nothing.';
}

function buildPullRequestTexts(run, plan, gates) {
  const texts = { title: buildPullRequestTitle(plan), body: buildPullRequestBody(run, plan, gates), comment: buildPullRequestComment(run, gates) };
  const longNoun = ['body', 'comment'].find((noun) => texts[noun].length > maxPullRequestTextLength());
  if (longNoun !== undefined) {
    return { problem: describePullRequestTextSize(longNoun, texts[longNoun].length) };
  }
  const attributedNoun = Object.keys(texts).find((noun) => forbiddenSubjectTexts().some((forbidden) => texts[noun].toLowerCase().includes(forbidden)));
  if (attributedNoun !== undefined) {
    return { problem: 'The pull request ' + attributedNoun + ' would hold an attribution string, so ' + RUN_NAME + ' stopped before the pull request and pushed nothing.' };
  }
  return texts;
}

function listPullRequestWords(plan, run, label) {
  const [inputsPath, bodyPath] = [label, label + '-body'].map((name) => buildInputsPath(run, 'pr', name));
  return ['--head', plan.branch, '--base', plan.base, '--expect-commit', run.head, '--inputs', inputsPath, '--body-file', bodyPath];
}

function buildPullRequestPrompt(words, texts, draft, pluginRoot) {
  return [
    'Open or reuse the PR with the command below.',
    dataBlocksSentence(),
    '',
    formatCommandBlock(buildRunnerCommand('open-plan-pr', words, pluginRoot)),
    formatInputsFileBlock(words[7], JSON.stringify({ title: texts.title, comment: texts.comment, draft: draft })),
    formatBodyFileBlock(words[9], texts.body)
  ].join('\n');
}

function isInputsRefusal(stderr) {
  return /^blocker: (?:(?:inputs?|title|body|draft|comment) |cannot read the inputs file$)/m.test(stderr);
}

/**
 * Returns the words after the run name of a blocked pull request step: it
 * pushed nothing when refused before the push or when stderr holds the
 * line pushed: no, it pushed head when stderr holds pushed: yes, else
 * unseenPush.
 */
function describeBlockedPush(stderr, head, isUnpushed, unseenPush) {
  if (isUnpushed || /^pushed: no$/m.test(stderr)) {
    return ' stopped. This step pushed nothing.';
  }
  return /^pushed: yes$/m.test(stderr) ? ' stopped after this step pushed commit ' + head + '.' : unseenPush;
}

function describePullRequestBlocker(stderr, head, unseenPush) {
  const isUnpushed = isGateDenial(stderr) || isInputsRefusal(stderr);
  const lead = 'The pull request step was blocked, so ' + RUN_NAME + describeBlockedPush(stderr, head, isUnpushed, unseenPush);
  return { problem: lead + ' ' + describeRelayBlocker(stderr, true), nextAction: readRelayAction(stderr, isUnpushed) };
}

function checkPullRequestRelay(relay, head) {
  const unseenPush = ' stopped and did not see whether this step pushed. Taking it again pushes the same commit and reuses a pull request open on it.';
  const stopped = 'so ' + RUN_NAME + unseenPush;
  if (!validateSchema(RELAY_SCHEMA, relay).ok) {
    return describeUnusableResult('The pull request step returned a result it could not use, ' + stopped, relay);
  }
  if (relay.outcome === 'blocked') {
    return describePullRequestBlocker(relay.stderr, head, unseenPush);
  }
  const values = readRelayedLines(relay, openPlanPrRoutingSpec());
  if (values === undefined || values.commented === values.created) {
    return describeUnusableResult('The pull request step returned malformed routing lines, ' + stopped, relay);
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
    return stopDelivery([{ problem: texts.problem, terminal: true, nextAction: 'report' }], run, [], false);
  }
  phase('PR');
  const label = describePullRequestLabel(run, gates.runs.pr);
  const commandStop = describeCommandStop('pull request', listPullRequestWords(plan, run, label), listPullRequestWords(plan, run, label + '-retry'));
  if (commandStop !== undefined) {
    return stopDelivery([commandStop], run, [], false);
  }
  const buildPrompt = (callLabel) => addResumeNote(buildPullRequestPrompt(listPullRequestWords(plan, run, callLabel), texts, run.draft, run.pluginRoot), run);
  const relay = await runRunnerRelay(buildPrompt, label, 'PR');
  const checked = checkPullRequestRelay(relay, run.head);
  if (checked.problem === undefined) {
    return { result: finishDeliveryComplete(run, plan, checked.values, gates) };
  }
  return stopDelivery([checked], run, [], false);
}
