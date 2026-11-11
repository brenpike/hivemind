/*
 * pr.js: the pull request step a workflow shares. It holds the pull
 * request title and body, the PR runner prompt, the check of its relay,
 * the blocked-push descriptions and the step. A workflow's own comment and
 * its pull request line for a taken decision are its hook functions.
 *
 * Inputs
 *   run    the run state of the workflow's main.js: head, branch, pass,
 *          taken, approvals, reversibleEffects, notRunGates, draft,
 *          pluginRoot, rejected and undone.
 *   plan   the accepted plan, from runPlanningPass (lib/plan.js).
 *          plan.title reaches only the pull request title, and plan.digest,
 *          the step ids, outcomes and files and the optional plan.closes
 *          only the body. plan.summary reaches no pull request text.
 *   gates  the gate loop state of runGates (lib/gates.js): held, notes,
 *          draft and runs.pr, the count of this step's runs in the pass.
 *   The constants of the workflow's main.js this file reads: RUN_NAME and
 *   RELAY_SCHEMA. The workflow functions it reads: maxPullRequestTextLength(),
 *   the limit, and the hooks buildPullRequestComment(run, gates), the
 *   comment text, or undefined when the workflow sends none, and
 *   toPullRequestDecision(entry), the taken decision entry the run record of
 *   the pull request texts shows. Every workflow whose code calls
 *   runPullRequestStep declares them all. Every other function it reads is
 *   a library's, among them the title helpers and listCloses of
 *   lib/title.js, buildRunRecordParts and stopDelivery (lib/record.js) and
 *   runRunnerRelay (lib/runner.js).
 *
 * Outputs
 *   runPullRequestStep(run, plan, gates)  {result}: finishDeliveryComplete
 *          naming the pull request, a pause, or a blocked finish, or
 *          {rerun: true} when the user replied to its stop.
 *   neutralizePullRequestText(text)  text in which nothing mentions, closes
 *          or links an issue; other Markdown still renders: the one renderer
 *          of every external part of the pull request texts.
 *   renderPullRequestGates(run, gates)  the Gates: part of the run record
 *          (buildRunRecordParts, lib/record.js).
 *   renderPullRequestRecord(run, gates)  the run record parts, each
 *          external one through neutralizePullRequestText, for the body
 *          and a workflow's comment hook.
 *   The step, as the workflow's meta.js names it:
 *   PR      once every required gate held on one commit H, a haiku
 *           synapse runner runs the open-plan-pr command once. The
 *           command carries only --head, --base, --expect-commit H,
 *           --inputs, the path buildInputsPath (lib/commit.js) builds for
 *           the call label, and --body-file, the one it builds for that
 *           label and -body. The inputs_file content is a JSON string of
 *           only the title the code builds, the comment of the comment
 *           hook, left out when the hook returns undefined, and draft, true
 *           when the launch asks for a draft or gates.draft is set, and the
 *           body_file content the body the code builds, the raw text the
 *           script reads whole. This runner is the only push the workflow
 *           makes, so every push carries --expect-commit. A command value
 *           outside its class (describeCommandStop, lib/runner.js), a body
 *           path whose token passes 64 characters among them, is a terminal
 *           stop before the call. Its stdout parses with
 *           openPlanPrRoutingSpec() (lib/specs.js), head_ref_oid must equal
 *           H, commented must be present exactly when a comment was sent,
 *           and then unequal to created, and the run finishes complete with
 *           pr. The runner call goes through runRunnerRelay, so a transient
 *           block runs once more under pr-P-retry with the inputs and body
 *           paths of that label, and the step checks the words of both
 *           labels before the call. A pull request text over its size limit
 *           and a head_ref_oid other than H are terminal stops. A blocked,
 *           malformed or other unusable relay stops through stopDelivery.
 *           The step makes one runner call: the gate loop runs the head
 *           check after a reply, then this step again under pr-P-N, N from
 *           2, or the gates first when the head moved, so expect_commit is
 *           always a head the run read. The title is the commit type of the
 *           plan classification, the breaking marker, a colon and
 *           plan.title, never the summary, cut at a word only when longer
 *           than maxTitleLength() code points, never inside a bracket the
 *           cut text opened (issue 469). buildTitleText(plan) gives the
 *           text after the prefix; the plan check refuses a plan whose text
 *           is empty, so the title is never only its type (issue 469). The
 *           body is the closing lines of renderClosingLines(plan), one
 *           Closes line per plan.closes number, then the digest paragraph,
 *           digest.problem then digest.change through renderText with a
 *           blank one left out, then a Steps: line and one line per step,
 *           its id, files and outcome through renderText (issue 506), then
 *           the one run record buildRunRecordParts() returns, every
 *           decision in it one compact line, the question and the chosen
 *           option with no why. No pull request text holds a code fence.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this library into it, so a row can name a
 *   function of this library.
 *   The pull request body and any comment carry the one run record
 *   buildRunRecordParts() returns. The digest, the step lines and the
 *   external parts of that record reach the pull request texts only
 *   through neutralizePullRequestText(), so an at-mention, issue
 *   reference, URL or HTML in them links, closes or notifies nothing. The
 *   gates and the labels are code-built and stay plain. So are the closing
 *   lines, which open the body, so GitHub links each issue they name as
 *   closed by the pull request (issue 491): each is the fixed text and an
 *   integer the plan check found among the launch references, never
 *   planner text.
 *   The closes check is membership only: which reference the run fixes is
 *   the planner's judgment, and the engine never reads the facts file, so
 *   code does not check that a number names an issue rather than a pull
 *   request; a Closes line naming a pull request closes nothing. The
 *   title stays plain text: GitHub renders titles with code spans only and
 *   takes no mentions from them, and a wrapper would reach the squash
 *   commit subject.
 *   No title, body or comment holds a forbiddenSubjectTexts() string
 *   (lib/commit.js), in any case: code holds this check, not a skill body
 *   the runner may never read, so buildPullRequestTexts makes one a
 *   terminal stop before any push (issue 467). The check reads the
 *   neutralized texts: neutralizing wraps or escapes no character of those
 *   strings, so each stays detectable. A text over
 *   maxPullRequestTextLength() is a terminal stop naming its size; no
 *   shorter form is tried.
 *   The relay is read through describeUnusableResult (lib/stop.js): a
 *   null result, an agent failure, adds the agent-failure sentence and
 *   next action run_again, and stopDelivery ends the run on it; any other
 *   unusable result, malformed routing lines among them, gets report and
 *   ends the run blocked. The text size and attribution stops are report
 *   too.
 *   A stop names what the run saw of the push: a blocked relay whose
 *   stderr holds a synapse-gate denial (isGateDenial, lib/runner.js) or an
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
 *   The pull request is the one push of a run, so its texts and the check
 *   of its head sit in one place, and every workflow that pushes through
 *   open-plan-pr shares them; only its comment and its decision lines are
 *   its own.
 */

/**
 * Returns text with each URL, owner/repo reference, issue reference, GH-N
 * reference and at-mention in a single-backtick code span, and every
 * backslash, backtick, [, ], <, > and & outside them backslash-escaped, so
 * nothing in it mentions, closes or links an issue, or forms a link or
 * image. Headings and emphasis still render.
 * No span holds a backtick or a blank, so each is literal whole.
 */
function neutralizePullRequestText(text) {
  return text.split(/((?:https?:\/\/|www\.)[^\s`]+|(?<![\w.-])[\w.-]+\/[\w.-]+#\d+|#\d+|GH-\d+|@[\w-]+(?:\/[\w-]+)?)/i)
    .map((piece, index) => (index % 2 === 1 ? '`' + piece + '`' : piece.replace(/[\\`[\]<>&]/g, '\\$&')))
    .join('');
}

function buildPullRequestTitle(plan) {
  const prefix = buildTitlePrefix(plan);
  const text = buildTitleText(plan);
  return text === '' ? prefix : prefix + ' ' + text;
}

/**
 * Returns the Gates: part: one line per gate, its note and held commit, did
 * not hold for a configured gate with no hold (draft mode, gates.js), or
 * not configured for this run.
 */
function renderPullRequestGates(run, gates) {
  const lines = ['Gates:'];
  for (const gateId of gateIds()) {
    const name = gateNames()[gateId];
    if (!configuredGateIds(run).includes(gateId)) {
      lines.push('- ' + name + ': not configured for this run');
      continue;
    }
    lines.push('- ' + name + ': ' + (gates.held[gateId] === undefined ? 'did not hold' : gates.notes[gateId] + ', held on commit ' + gates.held[gateId]));
  }
  return lines.join('\n');
}

function renderPullRequestPart(part) {
  return part.external ? neutralizePullRequestText(part.text) : part.text;
}

function renderPullRequestRecord(run, gates) {
  return buildRunRecordParts(run, run.taken.map(toPullRequestDecision), gates).map(renderPullRequestPart);
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

function describePullRequestTextSize(noun, size) {
  return 'The pull request ' + noun + ' would be ' + size + ' characters, more than the limit of ' + maxPullRequestTextLength() + ', so ' + RUN_NAME + ' stopped before the pull request and pushed nothing.';
}

/**
 * Returns {title, body, comment} of the pull request, comment left out when
 * the comment hook returns undefined, or {problem} for a terminal stop.
 */
function buildPullRequestTexts(run, plan, gates) {
  const comment = buildPullRequestComment(run, gates);
  const texts = { title: buildPullRequestTitle(plan), body: buildPullRequestBody(run, plan, gates), ...(comment === undefined ? {} : { comment: comment }) };
  const longNoun = ['body', 'comment'].find((noun) => texts[noun]?.length > maxPullRequestTextLength());
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

/**
 * Returns the PR runner prompt. JSON.stringify leaves out a comment that is
 * undefined, so the inputs file then carries no comment field.
 */
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

/**
 * Returns {values} of a usable relay, else a stop cause. commented must be
 * present exactly when hasComment, and then unequal to created.
 */
function checkPullRequestRelay(relay, head, hasComment) {
  const unseenPush = ' stopped and did not see whether this step pushed. Taking it again pushes the same commit and reuses a pull request open on it.';
  const stopped = 'so ' + RUN_NAME + unseenPush;
  if (!validateSchema(RELAY_SCHEMA, relay).ok) {
    return describeUnusableRelay(relay, 'pull request', stopped);
  }
  if (relay.outcome === 'blocked') {
    return describePullRequestBlocker(relay.stderr, head, unseenPush);
  }
  const values = readRelayedLines(relay, openPlanPrRoutingSpec());
  if (values === undefined || (values.commented !== undefined) !== hasComment || values.commented === values.created) {
    return describeUnusableRelay(relay, 'pull request', stopped, true);
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
    return stopDelivery([{ problem: texts.problem, terminal: true, nextAction: 'report' }], run);
  }
  phase('PR');
  const label = describePullRequestLabel(run, gates.runs.pr);
  const commandStop = describeCommandStop('pull request', listPullRequestWords(plan, run, label), listPullRequestWords(plan, run, label + '-retry'));
  if (commandStop !== undefined) {
    return stopDelivery([commandStop], run);
  }
  const buildPrompt = (callLabel) => addResumeNote(buildPullRequestPrompt(listPullRequestWords(plan, run, callLabel), texts, run.draft || gates.draft !== undefined, run.pluginRoot), run);
  const relay = await runRunnerRelay(buildPrompt, label, 'PR');
  const checked = checkPullRequestRelay(relay, run.head, texts.comment !== undefined);
  if (checked.problem === undefined) {
    return { result: finishDeliveryComplete(run, plan, checked.values, gates) };
  }
  return stopDelivery([checked], run);
}
