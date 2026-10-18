/*
 * brief.js: turns decision briefs into the plain text the user reads.
 *
 * Inputs
 *   renderQuestions(asks, taken)
 *     asks   non-empty array of {brief, reason}. brief is a decision brief;
 *            reason is the ask reason decide() returned for it.
 *     taken  array of {brief} for decisions decide() took. May be empty.
 *   renderDecisions(taken)
 *     taken  as above.
 *   askReasonLine(reason)
 *     reason an ask reason from decisionReasons(), other than 'auto'.
 *   renderOpenQuestions(open)
 *     open   non-empty array of {brief} for questions still unanswered when
 *            the run stops asking. Entries of asks fit.
 *
 * Outputs
 *   renderQuestions  one message. Each ask becomes a question labelled Q1..Qn
 *     by its position in asks. Each question shows, in this order: problem;
 *     how serious (criticality level, likelihood, blast_radius, if_ignored);
 *     each option with summary, case for (steel_man), case against
 *     (straw_man), effort, value and reversible; the recommendation with its
 *     why; one "Why I am asking" line from askReasonLine; the assumptions,
 *     where origin 'assumed' is marked as something the user can overrule;
 *     the verbatim text when present. Taken decisions follow, with a line
 *     saying the user can change them in the same reply. The last line tells
 *     the user to reply in their own words.
 *   renderDecisions  the "Decided for you" block, labelled D1..Dn by
 *     position, or the empty string when taken is empty.
 *   askReasonLine    one plain sentence for the reason.
 *   renderOpenQuestions  one block: a line saying the run stopped asking
 *     after pauseLimit() rounds, then one line per question labelled Q1..Qn
 *     by position, with its problem and the option the report assumes, or a
 *     line saying there is no recommendation.
 *
 * Invariants
 *   Text comes from brief fields and fixed wording only. brief.id and
 *   brief.kind are never shown: labels are assigned here, and kind names
 *   are internal. A missing or mistyped field renders as 'not given', so a
 *   malformed brief still renders.
 *   No em dash and no markdown tables. An em dash inside a brief field is
 *   replaced by a comma. verbatim is shown exactly as given.
 *   Invalid arguments and unknown reasons throw.
 *   renderOpenQuestions calls pauseLimit() from result.js, so it runs only
 *   where result.js is loaded too, as in every built script.
 *
 * Why
 *   The user answers from this text alone, so every question carries what
 *   the user needs to decide it, and labels come from code so the reply can
 *   point at a question without trusting a model-written id.
 */

function renderQuestions(asks, taken) {
  if (!Array.isArray(asks) || asks.length === 0) {
    throw new Error('renderQuestions: asks must be a non-empty array');
  }
  if (!Array.isArray(taken)) {
    throw new Error('renderQuestions: taken must be an array');
  }
  const blocks = [renderIntroLine(asks.length)];
  asks.forEach((entry, index) => blocks.push(renderQuestion(entry, index)));
  if (taken.length > 0) {
    blocks.push(renderDecisions(taken) + '\nYou can change any of these in the same reply.');
  }
  blocks.push('Reply in your own words. You can point at a question by its label, like Q1.');
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

function renderOpenQuestions(open) {
  if (!Array.isArray(open) || open.length === 0) {
    throw new Error('renderOpenQuestions: open must be a non-empty array');
  }
  const lines = ['I stopped asking after ' + pauseLimit() + ' rounds of questions. These are still open:'];
  open.forEach((entry, index) => lines.push(renderOpenQuestion(entry, index)));
  return lines.join('\n');
}

function renderIntroLine(count) {
  if (count === 1) {
    return 'I need your answer on 1 question before I go on.';
  }
  return 'I need your answers on ' + count + ' questions before I go on.';
}

function renderQuestion(entry, index) {
  const brief = readField(entry, 'brief');
  const lines = ['Q' + (index + 1) + '. ' + renderText(readField(brief, 'problem'))];
  lines.push(...renderSeriousness(readField(brief, 'criticality')));
  lines.push(...renderOptions(readField(brief, 'options')));
  lines.push(renderRecommendation(readField(brief, 'recommendation')));
  lines.push('Why I am asking: ' + askReasonLine(readField(entry, 'reason')));
  lines.push(...renderAssumptions(readField(brief, 'assumptions')));
  lines.push(...renderVerbatim(readField(brief, 'verbatim')));
  return lines.join('\n');
}

function renderSeriousness(criticality) {
  return [
    'How serious: ' + renderToken(readField(criticality, 'level')) + ' criticality, likelihood '
      + renderToken(readField(criticality, 'likelihood')) + '.',
    '  If it goes wrong: ' + renderText(readField(criticality, 'blast_radius')),
    '  If ignored: ' + renderText(readField(criticality, 'if_ignored'))
  ];
}

function renderOptions(options) {
  if (!Array.isArray(options) || options.length === 0) {
    return ['Options: not given.'];
  }
  const lines = ['Options:'];
  options.forEach((option) => lines.push(...renderOption(option)));
  return lines;
}

function renderOption(option) {
  return [
    '  Option ' + renderText(readField(option, 'id')) + ': ' + renderText(readField(option, 'summary')),
    '    Case for: ' + renderText(readField(option, 'steel_man')),
    '    Case against: ' + renderText(readField(option, 'straw_man')),
    '    Effort ' + renderToken(readField(option, 'effort')) + ', value ' + renderToken(readField(option, 'value'))
      + ', reversible: ' + renderYesNo(readField(option, 'reversible')) + '.'
  ];
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

function renderAssumptions(assumptions) {
  if (!Array.isArray(assumptions) || assumptions.length === 0) {
    return ['Assumptions: none.'];
  }
  const lines = ['Assumptions:'];
  assumptions.forEach((assumption) => lines.push(renderAssumption(assumption)));
  return lines;
}

function renderAssumption(assumption) {
  const statement = '  - ' + renderText(readField(assumption, 'statement'));
  const evidence = renderText(readField(assumption, 'evidence'));
  const origin = readField(assumption, 'origin');
  if (origin === 'user') {
    return statement + ' (you said so: ' + evidence + ')';
  }
  if (origin === 'repo') {
    return statement + ' (from the repo: ' + evidence + ')';
  }
  if (origin === 'assumed') {
    return statement + ' (my assumption, you can overrule it: ' + evidence + ')';
  }
  return statement + ' (source not given: ' + evidence + ')';
}

function renderVerbatim(verbatim) {
  if (typeof verbatim !== 'string' || verbatim === '') {
    return [];
  }
  return ['Exact text:', verbatim];
}

function renderOpenQuestion(entry, index) {
  const brief = readField(entry, 'brief');
  const recommendation = readField(brief, 'recommendation');
  const optionId = readField(recommendation, 'option_id');
  const hasChoice = readField(recommendation, 'strength') !== 'none' && typeof optionId === 'string' && optionId.trim() !== '';
  const choice = hasChoice ? 'The report assumes option ' + renderText(optionId) + '.' : 'There is no recommendation.';
  return '  Q' + (index + 1) + '. ' + renderText(readField(brief, 'problem')) + ' ' + choice;
}

function renderTakenDecision(entry, index) {
  const brief = readField(entry, 'brief');
  const recommendation = readField(brief, 'recommendation');
  const optionId = readField(recommendation, 'option_id');
  const chosen = findOptionById(readField(brief, 'options'), optionId);
  return [
    '  D' + (index + 1) + '. ' + renderText(readField(brief, 'problem')),
    '    Chose option ' + renderText(optionId) + ': ' + renderText(readField(chosen, 'summary')),
    '    Why: ' + renderText(readField(recommendation, 'why'))
  ].join('\n');
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

function renderYesNo(value) {
  if (value === true) {
    return 'yes';
  }
  if (value === false) {
    return 'no';
  }
  return 'not given';
}
