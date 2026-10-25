/*
 * brief.js: turns decision briefs into the plain text the user reads.
 *
 * Inputs
 *   renderQuestions(asks, taken)
 *     asks   non-empty array of {brief, reason, exact}. brief is a decision
 *            brief; reason is the ask reason decide() returned for it.
 *            exact is optional and set by workflow code only: true when the
 *            user must see the verbatim text of the brief to answer.
 *     taken  array of {brief} for decisions decide() took. May be empty.
 *   renderDecisions(taken)
 *     taken  as above.
 *   renderQuestionsCompact(asks, taken)
 *     asks, taken  as for renderQuestions.
 *   renderDecisionsCompact(taken)
 *     taken  as above.
 *   askReasonLine(reason)
 *     reason an ask reason from decisionReasons(), other than 'auto'.
 *   questionLabel(index)
 *     index  non-negative integer, the position of a question in asks or
 *            open.
 *   renderOpenQuestions(open, stopReason)
 *     open        non-empty array of {brief} for questions still unanswered
 *                 when the run stops asking. Entries of asks fit.
 *     stopReason  why the run stopped asking: 'pause_limit' (the default),
 *                 'reply_size' or 'exact_text_size'. Only analysis-only
 *                 stops at 'pause_limit': standard-delivery pauses for
 *                 every open question while its replies fit.
 *
 * Outputs
 *   renderQuestions  one message, the ask first, its sections apart by
 *     blank lines. The first line is a bold heading naming the labels the
 *     user must answer. Each ask then becomes a question labelled Q1..Qn by
 *     its position in asks: a bold "Qn. problem" line; one list line per
 *     option with its id, which is the reply token, and its summary, the
 *     recommended option marked; the recommendation with its why on one
 *     line; then the "Why it matters" part, two lines: the criticality
 *     level, likelihood and blast_radius, and the "Why I am asking" line
 *     from askReasonLine.
 *     Only for an exact entry whose brief carries verbatim, a "Word for
 *     word:" section follows with the verbatim whole, so a plan summary is
 *     not pasted into every question. Then one line per taken decision, its
 *     D label, problem and chosen option id, with a line saying the user can
 *     change them in the same reply. The last line shows how to reply, like
 *     Q1 A, or in their own words. Cases for and against, effort, value,
 *     reversible and assumptions are not shown.
 *   renderDecisions  the "Decided for you" block, labelled D1..Dn by
 *     position, or the empty string when taken is empty. Each decision
 *     shows its problem, the chosen option with its summary and the why,
 *     then, when verbatim is a non-empty string, a line "    Word for
 *     word:" and the verbatim exactly as given, unindented. This full form
 *     is the record the pull request body carries.
 *   renderQuestionsCompact  the shorter form of renderQuestions, with the
 *     same layout, heading, Q1..Qn labels, taken decision lines and last
 *     line. Each question shows its problem line, option lines and
 *     recommendation line, without the "Why it matters" part, and, as in
 *     the full form, only an exact entry has its "Word for word:" section.
 *   renderDecisionsCompact  the "Decided for you" block with one line per
 *     decision, labelled D1..Dn by position: problem, chosen option id and
 *     why, without the option summary or verbatim. The why is made one line
 *     and cut by cutAtBoundary (result.js) to maxExcerptLength(). The empty
 *     string when taken is empty.
 *   askReasonLine    one plain sentence for the reason.
 *   questionLabel    the label renderQuestions, renderQuestionsCompact and
 *     renderOpenQuestions show by position: 'Q' + (index + 1).
 *   renderOpenQuestions  one block: a line saying why the run stopped
 *     asking: after pauseLimit() rounds ('pause_limit'), because the
 *     replies so far are too long to carry into another round
 *     ('reply_size'), or because the exact text of a question is too long
 *     to show in full ('exact_text_size'). The line names no next action:
 *     the workflow adds its own next-step line. Then one line per
 *     question labelled Q1..Qn by position, with its problem and the option
 *     the report assumes, or the line 'I have no recommendation of my own.'
 *
 * Invariants
 *   Bounded fields: the brief text fields shown are written for the user
 *   and bounded by maxLength in decision-brief-schema.json, problem 300,
 *   an option summary 160, the recommendation why 200, blast_radius 160
 *   (issue 445), so a question stays short whatever its producer writes.
 *   A brief over a bound fails the schema: decide() asks it as
 *   malformed_brief, and it still renders here as given.
 *   Text comes from brief fields and fixed wording only. brief.id and
 *   brief.kind are never shown: labels are assigned here, and kind names
 *   are internal. A missing or mistyped field renders as 'not given', so a
 *   malformed brief still renders.
 *   No em dash and no markdown tables: options are a list. An em dash
 *   inside a brief field is replaced by a comma. verbatim is shown exactly
 *   as given and whole, and only renderDecisions shows the verbatim of a
 *   taken decision. The question messages give a taken decision one line,
 *   so its full text lives in the final message and the pull request body.
 *   One question with two options and no verbatim renders in about 10
 *   lines.
 *   Invalid arguments, unknown reasons and unknown stop reasons throw. So
 *   does questionLabel for anything but a non-negative integer.
 *   renderOpenQuestions with 'pause_limit' calls pauseLimit() from
 *   result.js, and renderDecisionsCompact calls cutAtBoundary and
 *   maxExcerptLength() from it, so they run only where result.js is loaded
 *   too, as in every built script.
 *   No size budget lives here: the caller picks the full or compact form.
 *
 * Why
 *   The user answers from this text alone, so the ask comes first and each
 *   question carries only what the user needs to decide it (issue 431).
 *   A question shows verbatim text only when the user must read it word
 *   for word, and a taken decision gets one short line, so a question
 *   message does not paste the plan again (issue 445).
 *   Labels and reply tokens come from code so the reply can point at a
 *   question without trusting a model-written id. Question labels have one
 *   home, questionLabel, so the three renderers cannot drift apart.
 */

function renderQuestions(asks, taken) {
  if (!Array.isArray(asks) || asks.length === 0) {
    throw new Error('renderQuestions: asks must be a non-empty array');
  }
  if (!Array.isArray(taken)) {
    throw new Error('renderQuestions: taken must be an array');
  }
  const blocks = [renderHeading(asks.length)];
  asks.forEach((entry, index) => blocks.push(renderQuestion(entry, index)));
  if (taken.length > 0) {
    blocks.push(renderTakenLines(taken));
  }
  blocks.push(renderReplyLine());
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

function renderQuestionsCompact(asks, taken) {
  if (!Array.isArray(asks) || asks.length === 0) {
    throw new Error('renderQuestionsCompact: asks must be a non-empty array');
  }
  if (!Array.isArray(taken)) {
    throw new Error('renderQuestionsCompact: taken must be an array');
  }
  const blocks = [renderHeading(asks.length)];
  asks.forEach((entry, index) => blocks.push(renderCompactQuestion(entry, index)));
  if (taken.length > 0) {
    blocks.push(renderTakenLines(taken));
  }
  blocks.push(renderReplyLine());
  return blocks.join('\n\n');
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

function askReasonLine(reason) {
  switch (reason) {
    case 'hard_stop':
      return 'This is a step I always check with you before taking.';
    case 'malformed_brief':
      return 'The details I have for this decision are incomplete, so I will not decide it alone.';
    case 'unknown_kind':
      return 'I have no rule that lets me decide this kind of question on my own.';
    case 'table_surface':
      return 'Your autonomy setting has me check with you on this kind of decision.';
    case 'bad_cell':
      return 'My rule for this kind of decision is unclear, so I am checking with you.';
    case 'gate_irreversible':
      return 'The recommended option cannot be undone cheaply.';
    case 'gate_architectural':
      return 'The recommended option changes how the system is built.';
    case 'gate_safety':
      return 'The recommended option touches safety.';
    case 'no_recommendation':
      return 'I do not have a recommendation I am confident enough to act on.';
    case 'recommendation_not_an_option':
      return 'My recommendation does not match one of the options, so I need you to pick.';
    default:
      throw new Error('askReasonLine: no line for reason ' + JSON.stringify(reason));
  }
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

function renderHeading(count) {
  if (count === 1) {
    return '**Answer ' + questionLabel(0) + ' so I can go on: pick one of its options.**';
  }
  const joiner = count === 2 ? ' and ' : ' to ';
  return '**Answer ' + questionLabel(0) + joiner + questionLabel(count - 1) + ' so I can go on: pick one option for each.**';
}

function renderReplyLine() {
  return 'Reply with a label and an option, like Q1 A, or in your own words.';
}

function renderTakenLines(taken) {
  const lines = ['Decided for you:'];
  taken.forEach((entry, index) => lines.push(renderTakenLine(entry, index)));
  lines.push('You can change any of these in the same reply.');
  return lines.join('\n');
}

function renderTakenLine(entry, index) {
  const brief = readField(entry, 'brief');
  return '- D' + (index + 1) + '. ' + renderText(readField(brief, 'problem')) + ' Chose option '
    + renderText(readField(readField(brief, 'recommendation'), 'option_id')) + '.';
}

function renderQuestion(entry, index) {
  const brief = readField(entry, 'brief');
  const lines = renderAsk(brief, index);
  lines.push(renderWhyItMatters(readField(brief, 'criticality')));
  lines.push('Why I am asking: ' + askReasonLine(readField(entry, 'reason')));
  const sections = [lines.join('\n')];
  if (readField(entry, 'exact') === true) {
    sections.push(...renderVerbatimSection(readField(brief, 'verbatim')));
  }
  return sections.join('\n\n');
}

function renderCompactQuestion(entry, index) {
  const brief = readField(entry, 'brief');
  const sections = [renderAsk(brief, index).join('\n')];
  if (readField(entry, 'exact') === true) {
    sections.push(...renderVerbatimSection(readField(brief, 'verbatim')));
  }
  return sections.join('\n\n');
}

function renderAsk(brief, index) {
  const recommendation = readField(brief, 'recommendation');
  return [
    '**' + questionLabel(index) + '. ' + renderText(readField(brief, 'problem')) + '**',
    ...renderOptions(readField(brief, 'options'), recommendation),
    renderRecommendation(recommendation)
  ];
}

function renderWhyItMatters(criticality) {
  return 'Why it matters: ' + renderToken(readField(criticality, 'level')) + ' criticality, likelihood '
    + renderToken(readField(criticality, 'likelihood')) + '. If it goes wrong: '
    + renderText(readField(criticality, 'blast_radius'));
}

function renderOptions(options, recommendation) {
  if (!Array.isArray(options) || options.length === 0) {
    return ['Options: not given.'];
  }
  const recommendedId = readField(recommendation, 'strength') === 'none' ? undefined : readField(recommendation, 'option_id');
  return options.map((option) => renderOption(option, recommendedId));
}

function renderOption(option, recommendedId) {
  const optionId = readField(option, 'id');
  const mark = typeof optionId === 'string' && optionId === recommendedId ? ' (recommended)' : '';
  return '- ' + renderText(optionId) + ': ' + renderText(readField(option, 'summary')) + mark;
}

function renderRecommendation(recommendation) {
  const why = 'Why: ' + renderText(readField(recommendation, 'why'));
  const strength = readField(recommendation, 'strength');
  if (strength === 'none') {
    return 'Recommendation: none. ' + why;
  }
  return 'Recommendation: option ' + renderText(readField(recommendation, 'option_id')) + ' ('
    + renderToken(strength) + '). ' + why;
}

function renderVerbatimSection(verbatim) {
  const lines = renderVerbatim(verbatim, '');
  return lines.length === 0 ? [] : [lines.join('\n')];
}

function renderVerbatim(verbatim, labelIndent) {
  if (typeof verbatim !== 'string' || verbatim === '') {
    return [];
  }
  return [labelIndent + 'Word for word:', verbatim];
}

function renderOpenQuestion(entry, index) {
  const brief = readField(entry, 'brief');
  const recommendation = readField(brief, 'recommendation');
  const optionId = readField(recommendation, 'option_id');
  const hasChoice = readField(recommendation, 'strength') !== 'none' && typeof optionId === 'string' && optionId.trim() !== '';
  const choice = hasChoice ? 'The report assumes option ' + renderText(optionId) + '.' : 'I have no recommendation of my own.';
  return '  ' + questionLabel(index) + '. ' + renderText(readField(brief, 'problem')) + ' ' + choice;
}

function renderTakenDecision(entry, index) {
  const brief = readField(entry, 'brief');
  const recommendation = readField(brief, 'recommendation');
  const optionId = readField(recommendation, 'option_id');
  const chosen = findOptionById(readField(brief, 'options'), optionId);
  const lines = [
    '  D' + (index + 1) + '. ' + renderText(readField(brief, 'problem')),
    '    Chose option ' + renderText(optionId) + ': ' + renderText(readField(chosen, 'summary')),
    '    Why: ' + renderText(readField(recommendation, 'why'))
  ];
  lines.push(...renderVerbatim(readField(brief, 'verbatim'), '    '));
  return lines.join('\n');
}

function renderCompactDecision(entry, index) {
  const brief = readField(entry, 'brief');
  const recommendation = readField(brief, 'recommendation');
  const whyLine = renderText(readField(recommendation, 'why')).split(/\s*[\r\n]+\s*/).join(' ');
  return '  D' + (index + 1) + '. ' + renderText(readField(brief, 'problem')) + ' Chose option '
    + renderText(readField(recommendation, 'option_id')) + '. Why: ' + cutAtBoundary(whyLine, maxExcerptLength());
}

function findOptionById(options, optionId) {
  if (!Array.isArray(options)) {
    return undefined;
  }
  return options.find((option) => readField(option, 'id') === optionId);
}

function readField(record, name) {
  if (typeof record !== 'object' || record === null || Array.isArray(record)) {
    return undefined;
  }
  return record[name];
}

function renderText(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    return 'not given';
  }
  return value.replace(/\s*\u2014\s*/g, ', ');
}

function renderToken(value) {
  return renderText(value).replace(/_/g, ' ');
}
