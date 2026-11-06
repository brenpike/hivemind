/*
 * brief.js: turns decision briefs into the plain text the user reads.
 *
 * Inputs
 *   renderQuestions(asks)
 *     asks   non-empty array of {brief, reason, exact}. brief is a decision
 *            brief; reason is the ask reason decide() returned for it, and
 *            is not shown. exact is optional and set by workflow code only:
 *            true when the user must see the verbatim text of the brief to
 *            answer.
 *   renderDecisions(taken)
 *     taken  array of {brief} for decisions decide() took. May be empty.
 *   renderDecisionsCompact(taken)
 *     taken  as above.
 *   questionLabel(index)
 *     index  non-negative integer, the position of a question in asks or
 *            open.
 *   decisionLabel(index)
 *     index  non-negative integer, the position of a decision in taken.
 *   optionLabel(index)
 *     index  non-negative integer, the position of an option in a brief's
 *            options.
 *   listShownLabels(asks)
 *     asks   as for renderQuestions.
 *   renderText(value)
 *     value  any value, usually a string an agent wrote.
 *   renderOpenQuestions(open, stopReason)
 *     open        non-empty array of {brief} for questions still unanswered
 *                 when the run stops asking. Entries of asks fit.
 *     stopReason  why the run stopped asking: 'pause_limit' (the default),
 *                 'reply_size' or 'exact_text_size'. Only analysis-only
 *                 stops at 'pause_limit': standard-delivery pauses for
 *                 every open question while its replies fit.
 *   readReplyChoices(reply, asks)
 *     reply  the user's reply to a pause, any value.
 *     asks   as for renderQuestions: the asks that pause showed.
 *   buildAnswerEntry(round, revise)
 *     round   {question, labels, reply, chosen} for one answer round:
 *             question is the questions text the pause showed, labels the
 *             labels it showed, the settled enum of the revise that reads
 *             the round, and reply the user's reply. chosen is optional:
 *             the readReplyChoices result for that reply.
 *     revise  the revise result of that round once it passed its check, or
 *             undefined when no such result exists. Its settled array names
 *             the shown labels the reply settled.
 *
 * Outputs
 *   renderQuestions  the questions and a reply line, apart by blank lines.
 *     Each ask becomes a question labelled Q1..Qn by its position in asks:
 *     a bold "Qn. problem" line; one "- L: summary" line per option, L
 *     being optionLabel of the option's position and the reply token, with
 *     " (recommended)" on the first option whose id equals the
 *     recommendation option_id, then " This goes beyond what you asked
 *     for." on any option whose beyond_request is true, then, when its
 *     destructive list is a non-empty array, on the same line " Choosing it
 *     approves these destructive changes: " and each entry as "item
 *     (category n)", item through renderText and whole, n the category
 *     when it is an integer and renderText of it otherwise, joined by "; ";
 *     then
 *     "Recommendation: L (strength). why",
 *     L being the letter of that option or 'not given' when no option id
 *     matches, or "Recommendation: none. why" when strength is none.
 *     Only for an exact entry whose brief carries verbatim, a "Word for
 *     word:" section follows with the verbatim encoded by
 *     encodeUntrustedText (result.js): one line, whole, nothing lost, so a
 *     plan summary is not pasted into every question. The last line is the
 *     reply line: for one question "Reply with an option, like A, or in
 *     your own words.", for more "Reply with a label and an option for
 *     each, like Q1 A, or in your own words." There is no heading, no
 *     criticality or ask reason line and no taken decision. Cases for and
 *     against, effort, value, reversible and assumptions are not shown.
 *   renderDecisions  the "Decided for you" block, labelled D1..Dn by
 *     position, or the empty string when taken is empty. Each decision
 *     shows its problem, "Chose option L" with the summary of the chosen
 *     option, L as in renderQuestions, and the why, then, when verbatim is
 *     a non-empty string, a line "    Word for word:" and the verbatim
 *     exactly as given, unindented. This full form is the record the pull
 *     request body carries, inside a fence.
 *   renderDecisionsCompact  "Decided for you:" then one line per decision,
 *     labelled D1..Dn by position: "- Dn. problem Chose L: summary.", L as
 *     in renderQuestions and the summary being that of the chosen option,
 *     with no why and no verbatim. The full stop after the summary is left
 *     out when the summary ends in '.', '!' or '?', alone or before a
 *     closing quote mark. The empty string when taken is empty.
 *   questionLabel    the label renderQuestions and renderOpenQuestions show
 *     by position: 'Q' + (index + 1).
 *   decisionLabel    the label renderDecisions and renderDecisionsCompact
 *     show for a taken decision by position: 'D' + (index + 1).
 *   optionLabel      the letter every renderer shows for an option by
 *     position: A for 0 up to Z for 25, then AA, AB and so on.
 *   listShownLabels  the labels a question message shows, in order: Q1..Qn
 *     from questionLabel, one per ask. A pause shows no taken decision, so
 *     no D label is ever shown or settled.
 *   renderText       the one-line display form of agent prose: 'not given'
 *     for a non-string or a string with nothing left to show; otherwise
 *     the text with every C0 and C1 control, DEL, U+2028, U+2029 and bidi
 *     control made a space, each whitespace run made one space, the ends
 *     trimmed, and each em dash with the spaces around it made a comma and
 *     a space.
 *   renderOpenQuestions  one block: a line saying why the run stopped
 *     asking: after pauseLimit() rounds ('pause_limit'), because the
 *     replies so far are too long to carry into another round
 *     ('reply_size'), or because the exact text of a question is too long
 *     to show in full ('exact_text_size'). The line names no next action:
 *     the workflow adds its own next-step line. Then one line per
 *     question labelled Q1..Qn by position, with its problem and the
 *     letter of the option the report assumes, L as in renderQuestions, or
 *     the line 'I have no recommendation of my own.'
 *   readReplyChoices  [{label, optionIndex}], one per answered question
 *     in reply order, when the whole reply, trimmed, fits the strict reply
 *     grammar; [] for any other reply, a non-string included. For one ask
 *     the reply, less one trailing full stop, is an option letter in either
 *     case or one pair. For more asks it is pairs separated by a comma, a
 *     semicolon or whitespace. A pair is a shown label, an optional colon,
 *     and an option letter in either case. Each label appears once and its
 *     letter is optionLabel of one of its brief's options; optionIndex is
 *     that option's position.
 *   buildAnswerEntry  one answer log entry {question, settled, reply}, in
 *     that key order. question and reply are copied from round unchanged.
 *     settled holds the labels of round.labels that revise.settled names or
 *     a round.chosen entry labels, in shown order, once each; [] when both
 *     name none, and [] when round.labels is empty.
 *
 * Invariants
 *   Bounded fields: the brief text fields shown are written for the user
 *   and bounded by maxLength in decision-brief-schema.json, problem 300,
 *   an option summary 160, the recommendation why 200 (issue 445), so a
 *   question stays short whatever its producer writes. A brief over a
 *   bound fails the schema: decide() asks it as malformed_brief, and it
 *   still renders here as given.
 *   Text comes from brief fields and fixed wording only. brief.id,
 *   brief.kind and option ids are never shown: labels and option letters
 *   are assigned here, and kind names are internal. A missing or mistyped
 *   field renders as 'not given', so a malformed brief still renders.
 *   Agent text never starts a line: every brief string a code-owned line
 *   shows passes through renderText, and an exact verbatim through
 *   encodeUntrustedText, so no brief text can add a line or forge a
 *   question, option, recommendation or reply line. The one multi-line
 *   agent text is the verbatim renderDecisions shows raw for the fenced
 *   pull request body.
 *   No em dash and no markdown tables: options are a list. An em dash
 *   inside a brief field is replaced by a comma. verbatim is shown whole,
 *   encoded in a question and exactly as given by renderDecisions, and
 *   only renderDecisions shows the verbatim of a taken decision.
 *   One question with two options and no verbatim renders in 6 lines.
 *   Invalid arguments and unknown stop reasons throw, except that
 *   readReplyChoices returns [] for any reply. So do questionLabel,
 *   decisionLabel and optionLabel for anything but a non-negative integer.
 *   renderOpenQuestions with 'pause_limit' calls pauseLimit() from
 *   result.js, and renderQuestions with an exact entry calls
 *   encodeUntrustedText from it, so they run only where result.js is
 *   loaded too, as in every built script.
 *   No size budget lives here.
 *   Settled labels have one writer, buildAnswerEntry, and it is fed only a
 *   revise result that passed its check and choices code read from the
 *   reply. A label the revise or a choice names that the round did not show
 *   is dropped, so an entry never calls settled a question the user was not
 *   shown.
 *   readReplyChoices reads a choice only from a reply that is nothing but
 *   choices, so a reply that adds any words, such as "A, and keep test X",
 *   is never read as a bare choice.
 *
 * Why
 *   The user answers from this text alone, so each question carries only
 *   what the user needs to decide it (issue 431). A question shows
 *   verbatim text only when the user must read it word for word, so a
 *   question message does not paste the plan again (issue 445).
 *   A pause message is one what-happened line plus these questions, and
 *   the reply line is its last line, so a heading, the why-it-matters and
 *   why-I-am-asking lines and the taken decisions only stood between the
 *   user and the choice. They are gone, and a taken decision gets one line
 *   at the run end (issue 460).
 *   Labels, option letters and reply tokens come from code so the reply
 *   can point at a question or an option without trusting a model-written
 *   id. Question labels have one home, questionLabel, decision labels one
 *   home, decisionLabel, and option letters one home, optionLabel, so the
 *   renderers and listShownLabels cannot drift apart.
 *   Agent text is shown inside a structure code owns, so the renderer, not
 *   a check on the input, keeps that text on its own line: a bound on the
 *   input limits its size, never its shape (findings 2c8e2101, 75535594).
 *   Each workflow logs every reply as an answer entry, and later prompts
 *   treat only the labels in its settled array as the user's settled
 *   decisions (issue 472). Settled labels have one writer, buildAnswerEntry,
 *   so the workflows cannot drift on which labels a reply settled.
 *   A summary already ends its own sentence, so a second full stop would
 *   only read as a typo (issue 498).
 *   Only the user's own reply choosing an option that names a destructive
 *   change approves it (security-policy.md, Destructive Fix Confirmation
 *   Gate), so the option line names every such change whole, and the reply
 *   choices are read by code, not by a model (issue 499).
 *   An option that goes beyond the request says so on its own line, so the
 *   user sees the extra scope before choosing it (issue 497).
 */

function renderQuestions(asks) {
  assertArray(asks, 'renderQuestions: asks', true);
  const blocks = asks.map((entry, index) => renderQuestion(entry, index));
  blocks.push(renderReplyLine(asks.length));
  return blocks.join('\n\n');
}

function renderDecisions(taken) {
  assertArray(taken, 'renderDecisions: taken', false);
  return renderDecisionBlock(taken, renderTakenDecision);
}

function renderDecisionsCompact(taken) {
  assertArray(taken, 'renderDecisionsCompact: taken', false);
  return renderDecisionBlock(taken, renderCompactDecision);
}

function renderDecisionBlock(taken, renderEntry) {
  if (taken.length === 0) {
    return '';
  }
  return ['Decided for you:', ...taken.map((entry, index) => renderEntry(entry, index))].join('\n');
}

function renderOpenQuestions(open, stopReason = 'pause_limit') {
  assertArray(open, 'renderOpenQuestions: open', true);
  const lines = [renderStopIntro(stopReason)];
  open.forEach((entry, index) => lines.push(renderOpenQuestion(entry, index)));
  return lines.join('\n');
}

function renderStopIntro(stopReason) {
  return 'I stopped asking ' + renderStopCause(stopReason) + '. These are still open:';
}

function renderStopCause(stopReason) {
  switch (stopReason) {
    case 'pause_limit':
      return 'after ' + pauseLimit() + ' rounds of questions';
    case 'reply_size':
      return 'because your replies so far are too long to carry into another round of questions';
    case 'exact_text_size':
      return 'because the exact text of a question is too long to show you in full';
    default:
      throw new Error('renderOpenQuestions: no intro for stop reason ' + JSON.stringify(stopReason));
  }
}

function assertArray(value, name, isNonEmptyRequired) {
  if (!Array.isArray(value) || (isNonEmptyRequired && value.length === 0)) {
    throw new Error(name + (isNonEmptyRequired ? ' must be a non-empty array' : ' must be an array'));
  }
}

function assertIndex(index, caller) {
  if (!Number.isInteger(index) || index < 0) {
    throw new Error(caller + ': index must be a non-negative integer');
  }
}

function questionLabel(index) {
  assertIndex(index, 'questionLabel');
  return 'Q' + (index + 1);
}

function decisionLabel(index) {
  assertIndex(index, 'decisionLabel');
  return 'D' + (index + 1);
}

function optionLabel(index) {
  assertIndex(index, 'optionLabel');
  let label = '';
  let rest = index;
  do {
    label = String.fromCharCode(65 + (rest % 26)) + label;
    rest = Math.floor(rest / 26) - 1;
  } while (rest >= 0);
  return label;
}

function listShownLabels(asks) {
  assertArray(asks, 'listShownLabels: asks', true);
  return asks.map((entry, index) => questionLabel(index));
}

function readReplyChoices(reply, asks) {
  const shownLabels = listShownLabels(asks);
  if (typeof reply !== 'string') {
    return [];
  }
  const replyText = asks.length === 1 ? reply.trim().replace(/\.$/, '') : reply.trim();
  const pairs = asks.length === 1 && /^[A-Za-z]+$/.test(replyText) ? [[shownLabels[0], replyText]] : readReplyPairs(replyText);
  const choices = pairs.map(([label, letter]) => ({ label: label, optionIndex: findLetterIndex(asks[shownLabels.indexOf(label)], letter) }));
  const isEachValid = choices.every((choice, index) => choice.optionIndex !== -1 && choices.findIndex((other) => other.label === choice.label) === index);
  return isEachValid ? choices : [];
}

function readReplyPairs(replyText) {
  if (!/^Q\d+(?::\s*|\s+)[A-Za-z]+(?:(?:\s*[,;]\s*|\s+)Q\d+(?::\s*|\s+)[A-Za-z]+)*$/.test(replyText)) {
    return [];
  }
  return [...replyText.matchAll(/(Q\d+)(?::\s*|\s+)([A-Za-z]+)/g)].map((match) => [match[1], match[2]]);
}

function findLetterIndex(entry, letter) {
  const options = readField(readField(entry, 'brief'), 'options');
  if (!Array.isArray(options)) {
    return -1;
  }
  return [...options.keys()].map((index) => optionLabel(index)).indexOf(letter.toUpperCase());
}

function buildAnswerEntry(round, revise) {
  const callerPrefix = 'buildAnswerEntry: ';
  const shownLabels = readField(round, 'labels');
  assertArray(shownLabels, callerPrefix + 'round.labels', false);
  const reviseLabels = revise === undefined ? [] : readField(revise, 'settled');
  assertArray(reviseLabels, callerPrefix + 'revise.settled', false);
  const choices = readField(round, 'chosen') ?? [];
  assertArray(choices, callerPrefix + 'round.chosen', false);
  const choiceLabels = choices.map((choice) => readField(choice, 'label'));
  const settled = shownLabels.filter((label, index) => (reviseLabels.includes(label) || choiceLabels.includes(label)) && shownLabels.indexOf(label) === index);
  return { question: round.question, settled: settled, reply: round.reply };
}

function renderReplyLine(count) {
  if (count === 1) {
    return 'Reply with an option, like A, or in your own words.';
  }
  return 'Reply with a label and an option for each, like Q1 A, or in your own words.';
}

function renderQuestion(entry, index) {
  const brief = readField(entry, 'brief');
  const sections = [renderAsk(brief, index).join('\n')];
  if (readField(entry, 'exact') === true) {
    sections.push(...renderVerbatimSection(readField(brief, 'verbatim')));
  }
  return sections.join('\n\n');
}

function renderAsk(brief, index) {
  const options = readField(brief, 'options');
  const recommendation = readField(brief, 'recommendation');
  return [
    '**' + questionLabel(index) + '. ' + renderText(readField(brief, 'problem')) + '**',
    ...renderOptions(options, findRecommendedIndex(options, recommendation)),
    renderRecommendation(recommendation, options)
  ];
}

function renderOptions(options, recommendedIndex) {
  if (!Array.isArray(options) || options.length === 0) {
    return ['Options: not given.'];
  }
  return options.map((option, index) => renderOption(option, index, recommendedIndex));
}

function renderOption(option, index, recommendedIndex) {
  const mark = index === recommendedIndex ? ' (recommended)' : '';
  const beyond = readField(option, 'beyond_request') === true ? ' This goes beyond what you asked for.' : '';
  return '- ' + optionLabel(index) + ': ' + renderText(readField(option, 'summary')) + mark + beyond + renderDestructive(readField(option, 'destructive'));
}

function renderDestructive(changes) {
  if (!Array.isArray(changes) || changes.length === 0) {
    return '';
  }
  return ' Choosing it approves these destructive changes: ' + changes.map((change) => renderDestructiveChange(change)).join('; ');
}

function renderDestructiveChange(change) {
  const category = readField(change, 'category');
  return renderText(readField(change, 'item')) + ' (category ' + (Number.isInteger(category) ? category : renderText(category)) + ')';
}

function renderRecommendation(recommendation, options) {
  const why = renderText(readField(recommendation, 'why'));
  const strength = readField(recommendation, 'strength');
  if (strength === 'none') {
    return 'Recommendation: none. ' + why;
  }
  return 'Recommendation: ' + renderOptionLetter(options, readField(recommendation, 'option_id')) + ' ('
    + renderToken(strength) + '). ' + why;
}

function renderVerbatimSection(verbatim) {
  if (!hasVerbatim(verbatim)) {
    return [];
  }
  return ['Word for word:\n' + encodeUntrustedText(verbatim)];
}

function renderVerbatim(verbatim, labelIndent) {
  if (!hasVerbatim(verbatim)) {
    return [];
  }
  return [labelIndent + 'Word for word:', verbatim];
}

function hasVerbatim(verbatim) {
  return typeof verbatim === 'string' && verbatim !== '';
}

function renderOpenQuestion(entry, index) {
  const brief = readField(entry, 'brief');
  const recommendation = readField(brief, 'recommendation');
  const optionId = readField(recommendation, 'option_id');
  const hasChoice = !isStrengthNone(recommendation) && typeof optionId === 'string' && optionId.trim() !== '';
  const choice = hasChoice
    ? 'The report assumes option ' + renderOptionLetter(readField(brief, 'options'), optionId) + '.'
    : 'I have no recommendation of my own.';
  return '  ' + questionLabel(index) + '. ' + renderText(readField(brief, 'problem')) + ' ' + choice;
}

function renderTakenDecision(entry, index) {
  const brief = readField(entry, 'brief');
  const lines = [
    '  ' + decisionLabel(index) + '. ' + renderText(readField(brief, 'problem')),
    '    Chose option ' + renderChoice(brief),
    '    Why: ' + renderText(readField(readField(brief, 'recommendation'), 'why'))
  ];
  lines.push(...renderVerbatim(readField(brief, 'verbatim'), '    '));
  return lines.join('\n');
}

function renderCompactDecision(entry, index) {
  const brief = readField(entry, 'brief');
  const choice = renderChoice(brief);
  return '- ' + decisionLabel(index) + '. ' + renderText(readField(brief, 'problem')) + ' Chose '
    + choice + (/[.!?]["']?$/.test(choice) ? '' : '.');
}

function renderChoice(brief) {
  const options = readField(brief, 'options');
  const optionId = readField(readField(brief, 'recommendation'), 'option_id');
  return renderOptionLetter(options, optionId) + ': ' + renderText(readField(readChosenOption(options, optionId), 'summary'));
}

function findRecommendedIndex(options, recommendation) {
  if (isStrengthNone(recommendation)) {
    return -1;
  }
  return findOptionIndex(options, readField(recommendation, 'option_id'));
}

function isStrengthNone(recommendation) {
  return readField(recommendation, 'strength') === 'none';
}

function findOptionIndex(options, optionId) {
  if (!Array.isArray(options) || typeof optionId !== 'string') {
    return -1;
  }
  return options.findIndex((option) => readField(option, 'id') === optionId);
}

function readChosenOption(options, optionId) {
  const index = findOptionIndex(options, optionId);
  return index === -1 ? undefined : options[index];
}

function renderOptionLetter(options, optionId) {
  const index = findOptionIndex(options, optionId);
  return index === -1 ? 'not given' : optionLabel(index);
}

function readField(record, name) {
  if (typeof record !== 'object' || record === null || Array.isArray(record)) {
    return undefined;
  }
  return record[name];
}

function renderText(value) {
  const lineText = typeof value !== 'string' ? '' : value
    .replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (lineText === '') {
    return 'not given';
  }
  return lineText.replace(/\s*\u2014\s*/g, ', ');
}

function renderToken(value) {
  return renderText(value).replace(/_/g, ' ');
}
