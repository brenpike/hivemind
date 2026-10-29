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
 *   buildAnswerEntry(round, revise)
 *     round   {question, labels, reply} for one answer round: question is
 *             the questions text the pause showed, labels the labels it
 *             showed, the settled enum of the revise that reads the round,
 *             and reply the user's reply.
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
 *     recommendation option_id; then "Recommendation: L (strength). why",
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
 *     with no why and no verbatim. The empty string when taken is empty.
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
 *   buildAnswerEntry  one answer log entry {question, settled, reply}, in
 *     that key order. question and reply are copied from round unchanged.
 *     settled holds the labels of round.labels that revise.settled names,
 *     in shown order, once each; [] when revise is undefined, and [] when
 *     round.labels is empty.
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
 *   Invalid arguments and unknown stop reasons throw. So do questionLabel,
 *   decisionLabel and optionLabel for anything but a non-negative integer.
 *   renderOpenQuestions with 'pause_limit' calls pauseLimit() from
 *   result.js, and renderQuestions with an exact entry calls
 *   encodeUntrustedText from it, so they run only where result.js is
 *   loaded too, as in every built script.
 *   No size budget lives here.
 *   Settled labels have one writer, buildAnswerEntry, and it is fed only a
 *   revise result that passed its check. A label the revise names that the
 *   round did not show is dropped, so an entry never calls settled a
 *   question the user was not shown.
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
 */

function renderQuestions(asks) {
  if (!Array.isArray(asks) || asks.length === 0) {
    throw new Error('renderQuestions: asks must be a non-empty array');
  }
  const blocks = asks.map((entry, index) => renderQuestion(entry, index));
  blocks.push(renderReplyLine(asks.length));
  return blocks.join('\n\n');
}

function renderDecisions(taken) {
  if (!Array.isArray(taken)) {
    throw new Error('renderDecisions: taken must be an array');
  }
  if (taken.length === 0) {
    return '';
  }
  const lines = ['Decided for you:'];
  taken.forEach((entry, index) => lines.push(renderTakenDecision(entry, index)));
  return lines.join('\n');
}

function renderDecisionsCompact(taken) {
  if (!Array.isArray(taken)) {
    throw new Error('renderDecisionsCompact: taken must be an array');
  }
  if (taken.length === 0) {
    return '';
  }
  const lines = ['Decided for you:'];
  taken.forEach((entry, index) => lines.push(renderCompactDecision(entry, index)));
  return lines.join('\n');
}

function renderOpenQuestions(open, stopReason = 'pause_limit') {
  if (!Array.isArray(open) || open.length === 0) {
    throw new Error('renderOpenQuestions: open must be a non-empty array');
  }
  const lines = [renderStopIntro(stopReason)];
  open.forEach((entry, index) => lines.push(renderOpenQuestion(entry, index)));
  return lines.join('\n');
}

function renderStopIntro(stopReason) {
  switch (stopReason) {
    case 'pause_limit':
      return 'I stopped asking after ' + pauseLimit() + ' rounds of questions. These are still open:';
    case 'reply_size':
      return 'I stopped asking because your replies so far are too long to carry into another round of questions. These are still open:';
    case 'exact_text_size':
      return 'I stopped asking because the exact text of a question is too long to show you in full. These are still open:';
    default:
      throw new Error('renderOpenQuestions: no intro for stop reason ' + JSON.stringify(stopReason));
  }
}

function questionLabel(index) {
  if (!Number.isInteger(index) || index < 0) {
    throw new Error('questionLabel: index must be a non-negative integer');
  }
  return 'Q' + (index + 1);
}

function decisionLabel(index) {
  if (!Number.isInteger(index) || index < 0) {
    throw new Error('decisionLabel: index must be a non-negative integer');
  }
  return 'D' + (index + 1);
}

function optionLabel(index) {
  if (!Number.isInteger(index) || index < 0) {
    throw new Error('optionLabel: index must be a non-negative integer');
  }
  let label = '';
  let rest = index;
  do {
    label = String.fromCharCode(65 + (rest % 26)) + label;
    rest = Math.floor(rest / 26) - 1;
  } while (rest >= 0);
  return label;
}

function listShownLabels(asks) {
  if (!Array.isArray(asks) || asks.length === 0) {
    throw new Error('listShownLabels: asks must be a non-empty array');
  }
  return asks.map((entry, index) => questionLabel(index));
}

function buildAnswerEntry(round, revise) {
  const shownLabels = readField(round, 'labels');
  if (!Array.isArray(shownLabels)) {
    throw new Error('buildAnswerEntry: round.labels must be an array');
  }
  const reviseLabels = revise === undefined ? [] : readField(revise, 'settled');
  if (!Array.isArray(reviseLabels)) {
    throw new Error('buildAnswerEntry: revise.settled must be an array');
  }
  const settled = shownLabels.filter((label, index) => reviseLabels.includes(label) && shownLabels.indexOf(label) === index);
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
  return '- ' + optionLabel(index) + ': ' + renderText(readField(option, 'summary')) + mark;
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
  const hasChoice = readField(recommendation, 'strength') !== 'none' && typeof optionId === 'string' && optionId.trim() !== '';
  const choice = hasChoice
    ? 'The report assumes option ' + renderOptionLetter(readField(brief, 'options'), optionId) + '.'
    : 'I have no recommendation of my own.';
  return '  ' + questionLabel(index) + '. ' + renderText(readField(brief, 'problem')) + ' ' + choice;
}

function renderTakenDecision(entry, index) {
  const brief = readField(entry, 'brief');
  const options = readField(brief, 'options');
  const recommendation = readField(brief, 'recommendation');
  const optionId = readField(recommendation, 'option_id');
  const lines = [
    '  ' + decisionLabel(index) + '. ' + renderText(readField(brief, 'problem')),
    '    Chose option ' + renderOptionLetter(options, optionId) + ': ' + renderText(readField(readChosenOption(options, optionId), 'summary')),
    '    Why: ' + renderText(readField(recommendation, 'why'))
  ];
  lines.push(...renderVerbatim(readField(brief, 'verbatim'), '    '));
  return lines.join('\n');
}

function renderCompactDecision(entry, index) {
  const brief = readField(entry, 'brief');
  const options = readField(brief, 'options');
  const optionId = readField(readField(brief, 'recommendation'), 'option_id');
  return '- ' + decisionLabel(index) + '. ' + renderText(readField(brief, 'problem')) + ' Chose '
    + renderOptionLetter(options, optionId) + ': ' + renderText(readField(readChosenOption(options, optionId), 'summary')) + '.';
}

function findRecommendedIndex(options, recommendation) {
  if (readField(recommendation, 'strength') === 'none') {
    return -1;
  }
  return findOptionIndex(options, readField(recommendation, 'option_id'));
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
  if (typeof value !== 'string') {
    return 'not given';
  }
  const lineText = value
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
