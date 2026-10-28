import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const libDir = repoRoot + 'plugin/workflow-src/lib/';
const lib = loadLibs(['decide.js', 'brief.js', 'result.js'].map((name) => libDir + name));
const EM_DASH = '\u2014';
const REPLY_LINE = 'Reply with a label and an option, like Q1 A, or in your own words.';
const ONE_HEADING = '**Answer Q1 so I can go on: pick one of its options.**';

function makeBrief(overrides = {}) {
  return {
    id: 'Q9',
    kind: 'planner_question',
    problem: 'PROBLEM_TEXT',
    criticality: { level: 'high', likelihood: 'edge_case', blast_radius: 'BLAST_TEXT', if_ignored: 'IGNORED_TEXT' },
    options: [
      { id: 'A', summary: 'SUMMARY_A', steel_man: 'FOR_A', straw_man: 'AGAINST_A', effort: 'small', value: 'high', reversible: true },
      { id: 'B', summary: 'SUMMARY_B', steel_man: 'FOR_B', straw_man: 'AGAINST_B', effort: 'large', value: 'low', reversible: false }
    ],
    recommendation: { option_id: 'A', strength: 'weak', why: 'WHY_TEXT' },
    assumptions: [
      { statement: 'USER_STATEMENT', origin: 'user', evidence: 'USER_EVIDENCE' },
      { statement: 'REPO_STATEMENT', origin: 'repo', evidence: 'REPO_EVIDENCE' },
      { statement: 'ASSUMED_STATEMENT', origin: 'assumed', evidence: 'ASSUMED_EVIDENCE' }
    ],
    gate: { irreversible: true, architectural: false, safety: false },
    verbatim: 'VERBATIM_TEXT',
    ...overrides
  };
}

function lineContaining(text, needle) {
  const line = text.split('\n').find((candidate) => candidate.includes(needle));
  assert.ok(line !== undefined, `no line contains ${needle}`);
  return line;
}

function assertInOrder(text, needles) {
  let previous = -1;
  for (const needle of needles) {
    const position = text.indexOf(needle, previous + 1);
    assert.ok(position > previous, `${needle} is missing or out of order`);
    previous = position;
  }
}

describe('renderQuestions layout', () => {
  const text = lib.renderQuestions([{ brief: makeBrief(), reason: 'gate_irreversible' }], []);
  test('puts the ask first, then options, recommendation and why it matters, with no verbatim for a non-exact ask', () => {
    assert.equal(text, [
      ONE_HEADING,
      '',
      '**Q1. PROBLEM_TEXT**',
      '- A: SUMMARY_A (recommended)',
      '- B: SUMMARY_B',
      'Recommendation: option A (weak). Why: WHY_TEXT',
      'Why it matters: high criticality, likelihood edge case. If it goes wrong: BLAST_TEXT',
      'Why I am asking: ' + lib.askReasonLine('gate_irreversible'),
      '',
      REPLY_LINE
    ].join('\n'));
  });
  test('an exact ask shows its verbatim under Word for word', () => {
    const exactText = lib.renderQuestions([{ brief: makeBrief(), reason: 'gate_irreversible', exact: true }], []);
    assert.equal(exactText, text.replace('\n\n' + REPLY_LINE, '\n\nWord for word:\nVERBATIM_TEXT\n\n' + REPLY_LINE));
  });
  test('one question with two options and no verbatim fits in 12 lines', () => {
    const brief = makeBrief();
    delete brief.verbatim;
    const lines = lib.renderQuestions([{ brief, reason: 'hard_stop' }], []).split('\n');
    assert.ok(lines.length <= 12, `${lines.length} lines`);
  });
  test('leaves out the cases, effort, value, reversible and assumptions', () => {
    for (const needle of ['FOR_A', 'AGAINST_A', 'Case for', 'Effort', 'reversible', 'Assumptions', 'USER_STATEMENT', 'IGNORED_TEXT']) {
      assert.equal(text.includes(needle), false, `shows ${needle}`);
    }
  });
  test('never shows brief.id or brief.kind', () => {
    assert.doesNotMatch(text, /Q9|planner_question/);
  });
  test('ends with one line showing how to reply', () => {
    const lines = text.split('\n');
    assert.equal(lines[lines.length - 1], REPLY_LINE);
    assert.equal(lines.filter((line) => line === REPLY_LINE).length, 1);
  });
  test('omits the verbatim section when verbatim is absent', () => {
    const brief = makeBrief();
    delete brief.verbatim;
    assert.doesNotMatch(lib.renderQuestions([{ brief, reason: 'hard_stop', exact: true }], []), /Word for word:/);
  });
  test('shows the verbatim of an exact ask exactly as given', () => {
    const verbatim = `keep ${EM_DASH} this | as is`;
    const rendered = lib.renderQuestions([{ brief: makeBrief({ verbatim }), reason: 'hard_stop', exact: true }], []);
    assert.ok(rendered.split('\n').includes(verbatim));
  });
  test('shows a multi-line verbatim of an exact ask whole', () => {
    const verbatim = 'line one\n\nline three';
    const rendered = lib.renderQuestions([{ brief: makeBrief({ verbatim }), reason: 'hard_stop', exact: true }], []);
    assert.ok(rendered.includes('Word for word:\n' + verbatim + '\n\n'));
  });
  test('shows a recommendation of none and marks no option', () => {
    const recommendation = { option_id: 'A', strength: 'none', why: 'NONE_WHY' };
    const rendered = lib.renderQuestions([{ brief: makeBrief({ recommendation }), reason: 'no_recommendation' }], []);
    assert.equal(lineContaining(rendered, 'Recommendation:'), 'Recommendation: none. Why: NONE_WHY');
    assert.doesNotMatch(rendered, /recommended\)/);
  });
  test('marks only the recommended option', () => {
    const recommendation = { option_id: 'B', strength: 'strong', why: 'W' };
    const rendered = lib.renderQuestions([{ brief: makeBrief({ recommendation }), reason: 'hard_stop' }], []);
    assert.ok(rendered.includes('- A: SUMMARY_A\n- B: SUMMARY_B (recommended)\n'));
  });
});

describe('labels', () => {
  test('questions are labelled Q1..Qn by position, not by brief.id', () => {
    const asks = ['FIRST', 'SECOND', 'THIRD'].map((problem, index) => ({
      brief: makeBrief({ id: 'Q' + (7 - index), problem }),
      reason: 'table_surface'
    }));
    const text = lib.renderQuestions(asks, []);
    assertInOrder(text, ['**Q1. FIRST**', '**Q2. SECOND**', '**Q3. THIRD**']);
    assert.doesNotMatch(text, /Q[4-7]/);
    assert.equal(text.split('\n')[0], '**Answer Q1 to Q3 so I can go on: pick one option for each.**');
  });
  test('one question uses the singular heading', () => {
    const text = lib.renderQuestions([{ brief: makeBrief(), reason: 'hard_stop' }], []);
    assert.equal(text.split('\n')[0], ONE_HEADING);
  });
  test('two questions name both labels in the heading', () => {
    const entry = { brief: makeBrief(), reason: 'hard_stop' };
    const text = lib.renderQuestions([entry, entry], []);
    assert.equal(text.split('\n')[0], '**Answer Q1 and Q2 so I can go on: pick one option for each.**');
  });
});

describe('reason lines', () => {
  const askReasons = [...lib.decisionReasons()].filter((reason) => reason !== 'auto');
  test('every ask reason has its own line', () => {
    const lines = askReasons.map((reason) => lib.askReasonLine(reason));
    assert.equal(new Set(lines).size, askReasons.length);
    for (const line of lines) {
      assert.match(line, /^[A-Z].*\.$/);
    }
  });
  for (const reason of askReasons) {
    test(`${reason} renders its line under Why I am asking`, () => {
      const text = lib.renderQuestions([{ brief: makeBrief(), reason }], []);
      assert.equal(lineContaining(text, 'Why I am asking:'), 'Why I am asking: ' + lib.askReasonLine(reason));
    });
  }
  for (const reason of ['auto', 'nonsense', undefined]) {
    test(`reason ${JSON.stringify(reason)} throws`, () => {
      assert.throws(() => lib.askReasonLine(reason), /askReasonLine: no line for reason/);
      assert.throws(() => lib.renderQuestions([{ brief: makeBrief(), reason }], []), /askReasonLine/);
    });
  }
});

describe('taken decisions', () => {
  const taken = [
    { brief: makeBrief({ problem: 'TAKEN_ONE', recommendation: { option_id: 'B', strength: 'strong', why: 'TAKEN_WHY' } }) },
    { brief: makeBrief({ problem: 'TAKEN_TWO' }) }
  ];
  test('renderDecisions lists them as decided for you', () => {
    assert.equal(lib.renderDecisions(taken), [
      'Decided for you:',
      '  D1. TAKEN_ONE',
      '    Chose option B: SUMMARY_B',
      '    Why: TAKEN_WHY',
      '    Word for word:',
      'VERBATIM_TEXT',
      '  D2. TAKEN_TWO',
      '    Chose option A: SUMMARY_A',
      '    Why: WHY_TEXT',
      '    Word for word:',
      'VERBATIM_TEXT'
    ].join('\n'));
  });
  test('renderDecisions omits the Word for word lines when verbatim is absent or empty', () => {
    const absent = makeBrief({ problem: 'NO_VERBATIM' });
    delete absent.verbatim;
    const text = lib.renderDecisions([{ brief: absent }, { brief: makeBrief({ problem: 'EMPTY_VERBATIM', verbatim: '' }) }]);
    assert.doesNotMatch(text, /Word for word:/);
  });
  test('renderDecisions shows verbatim exactly as given, unindented', () => {
    const verbatim = `keep ${EM_DASH} this | as is`;
    const lines = lib.renderDecisions([{ brief: makeBrief({ verbatim }) }]).split('\n');
    assert.deepEqual(lines.slice(-2), ['    Word for word:', verbatim]);
  });
  test('renderDecisions of nothing is empty', () => {
    assert.equal(lib.renderDecisions([]), '');
  });
  test('renderQuestions lists them one line each after the questions and says they can be changed in the same reply', () => {
    const text = lib.renderQuestions([{ brief: makeBrief(), reason: 'hard_stop' }], taken);
    assert.ok(text.endsWith([
      '',
      'Decided for you:',
      '- D1. TAKEN_ONE Chose option B.',
      '- D2. TAKEN_TWO Chose option A.',
      'You can change any of these in the same reply.',
      '',
      REPLY_LINE
    ].join('\n')));
  });
  test('renderQuestions leaves out the summary, why and verbatim of a taken decision', () => {
    const decided = [{ brief: makeBrief({ problem: 'TAKEN_ONE', options: [{ id: 'A', summary: 'TAKEN_SUMMARY' }], recommendation: { option_id: 'A', strength: 'strong', why: 'TAKEN_WHY' }, verbatim: 'TAKEN_VERBATIM' }) }];
    const text = lib.renderQuestions([{ brief: makeBrief({ verbatim: '' }), reason: 'hard_stop' }], decided);
    for (const needle of ['TAKEN_SUMMARY', 'TAKEN_WHY', 'TAKEN_VERBATIM', 'Word for word:']) {
      assert.equal(text.includes(needle), false, `shows ${needle}`);
    }
  });
  test('renderQuestions without taken decisions has no decided block', () => {
    assert.doesNotMatch(lib.renderQuestions([{ brief: makeBrief(), reason: 'hard_stop' }], []), /Decided for you|change any of these/);
  });
});

describe('plain text', () => {
  const dashed = makeBrief({ problem: `Pick one ${EM_DASH} or not`, recommendation: { option_id: 'A', strength: 'strong', why: `Because${EM_DASH}cheap` } });
  delete dashed.verbatim;
  const text = lib.renderQuestions([{ brief: dashed, reason: 'gate_safety' }], [{ brief: dashed }]);
  test('has no em dash, even when brief fields have one', () => {
    assert.equal(text.includes(EM_DASH), false);
    assert.ok(text.includes('Pick one, or not'));
  });
  test('has no markdown table rows', () => {
    for (const line of text.split('\n')) {
      assert.doesNotMatch(line, /^\s*\|/);
    }
  });
});

describe('malformed briefs still render', () => {
  for (const brief of [null, undefined, {}, { problem: 7, options: 'x', criticality: [], recommendation: null, assumptions: {} }]) {
    test(`brief ${JSON.stringify(brief)} renders with not given placeholders`, () => {
      const text = lib.renderQuestions([{ brief, reason: 'malformed_brief' }], []);
      assert.ok(text.includes('**Q1. not given**'));
      assert.ok(text.includes('Options: not given.'));
      assert.ok(text.includes('Why it matters: not given criticality, likelihood not given. If it goes wrong: not given'));
      assert.ok(text.endsWith(REPLY_LINE));
    });
  }
});

describe('open questions', () => {
  const open = [
    { brief: makeBrief({ problem: 'FIRST_OPEN' }), reason: 'gate_irreversible' },
    { brief: makeBrief({ problem: 'SECOND_OPEN', recommendation: { option_id: '', strength: 'none', why: 'W' } }), reason: 'no_recommendation' }
  ];
  test('lists each open question by position with the option the report assumes', () => {
    assert.equal(lib.renderOpenQuestions(open), [
      'I stopped asking after ' + lib.pauseLimit() + ' rounds of questions. These are still open:',
      '  Q1. FIRST_OPEN The report assumes option A.',
      '  Q2. SECOND_OPEN I have no recommendation of my own.'
    ].join('\n'));
  });
  test('strength none has no recommendation even with an option id', () => {
    const brief = makeBrief({ recommendation: { option_id: 'B', strength: 'none', why: 'W' } });
    assert.ok(lib.renderOpenQuestions([{ brief }]).endsWith('Q1. PROBLEM_TEXT I have no recommendation of my own.'));
  });
  test('never shows brief.id or brief.kind', () => {
    assert.doesNotMatch(lib.renderOpenQuestions(open), /Q9|planner_question/);
  });
  test('has no em dash, even when brief fields have one', () => {
    const brief = makeBrief({ problem: `Pick one ${EM_DASH} or not`, recommendation: { option_id: `A${EM_DASH}1`, strength: 'weak', why: 'W' } });
    const text = lib.renderOpenQuestions([{ brief }]);
    assert.equal(text.includes(EM_DASH), false);
    assert.ok(text.endsWith('Q1. Pick one, or not The report assumes option A, 1.'));
  });
  for (const brief of [null, undefined, {}, { problem: 7, recommendation: [] }]) {
    test(`malformed brief ${JSON.stringify(brief)} renders with not given placeholders`, () => {
      assert.ok(lib.renderOpenQuestions([{ brief }]).endsWith('Q1. not given I have no recommendation of my own.'));
    });
  }
});

describe('argument checks', () => {
  test('renderQuestions needs at least one ask', () => {
    assert.throws(() => lib.renderQuestions([], []), /asks must be a non-empty array/);
    assert.throws(() => lib.renderQuestions(undefined, []), /asks must be a non-empty array/);
  });
  test('taken must be an array', () => {
    assert.throws(() => lib.renderQuestions([{ brief: makeBrief(), reason: 'hard_stop' }], null), /taken must be an array/);
    assert.throws(() => lib.renderDecisions(undefined), /taken must be an array/);
  });
  test('renderOpenQuestions needs at least one open question', () => {
    assert.throws(() => lib.renderOpenQuestions([]), /open must be a non-empty array/);
    assert.throws(() => lib.renderOpenQuestions(undefined), /open must be a non-empty array/);
  });
});

function labelsOf(text) {
  return text.split('\n')
    .map((line) => line.match(/^\s*(?:- |\*\*)?([QD]\d+)\./))
    .filter((match) => match !== null)
    .map((match) => match[1]);
}

describe('compact questions', () => {
  const asks = ['FIRST', 'SECOND', 'THIRD'].map((problem, index) => ({
    brief: makeBrief({ id: 'Q' + (7 - index), problem }),
    reason: 'gate_irreversible'
  }));
  const taken = [
    { brief: makeBrief({ id: 'D8', problem: 'TAKEN_ONE', recommendation: { option_id: 'B', strength: 'strong', why: 'TAKEN_WHY' } }) },
    { brief: makeBrief({ id: 'D9', problem: 'TAKEN_TWO' }) }
  ];
  const full = lib.renderQuestions(asks, taken);
  const compact = lib.renderQuestionsCompact(asks, taken);
  test('labels equal the full form labels for questions and decisions', () => {
    assert.deepEqual(labelsOf(compact), labelsOf(full));
    assert.deepEqual(labelsOf(compact), ['Q1', 'Q2', 'Q3', 'D1', 'D2']);
  });
  test('keeps the heading and the reply line of the full form', () => {
    assert.equal(compact.split('\n')[0], full.split('\n')[0]);
    assert.ok(compact.endsWith(REPLY_LINE));
    assert.equal(compact.split('\n').filter((line) => line === REPLY_LINE).length, 1);
  });
  test('shows the problem, the options and the recommendation with its why', () => {
    const text = lib.renderQuestionsCompact([{ brief: makeBrief(), reason: 'hard_stop' }], []);
    assert.equal(text, [
      ONE_HEADING,
      '',
      '**Q1. PROBLEM_TEXT**',
      '- A: SUMMARY_A (recommended)',
      '- B: SUMMARY_B',
      'Recommendation: option A (weak). Why: WHY_TEXT',
      '',
      REPLY_LINE
    ].join('\n'));
  });
  test('omits the detail the full form carries', () => {
    for (const needle of ['Why it matters:', 'Why I am asking:']) {
      assert.ok(full.includes(needle), `full form lacks ${needle}`);
      assert.equal(compact.includes(needle), false, `compact form shows ${needle}`);
    }
  });
  test('is no longer than the full form', () => {
    assert.ok(compact.length <= full.length);
  });
  test('lists taken decisions compactly and says they can be changed in the same reply', () => {
    assertInOrder(compact, ['Q3. THIRD', 'Decided for you:', 'D1. TAKEN_ONE', 'D2. TAKEN_TWO',
      'You can change any of these in the same reply.', REPLY_LINE]);
  });
  test('without taken decisions has no decided block', () => {
    assert.doesNotMatch(lib.renderQuestionsCompact(asks, []), /Decided for you|change any of these/);
  });
  test('never shows brief.id or brief.kind', () => {
    assert.doesNotMatch(compact, /Q[4-9]|D[89]|planner_question/);
  });
  test('has no em dash, even when brief fields have one', () => {
    const dashed = makeBrief({ problem: `Pick one ${EM_DASH} or not`, recommendation: { option_id: 'A', strength: 'strong', why: `Because${EM_DASH}cheap` } });
    const text = lib.renderQuestionsCompact([{ brief: dashed, reason: 'gate_safety' }], [{ brief: dashed }]);
    assert.equal(text.includes(EM_DASH), false);
    assert.ok(text.includes('Q1. Pick one, or not'));
    assert.ok(text.includes('Why: Because, cheap'));
  });
  for (const brief of [null, undefined, {}, { problem: 7, options: 'x', criticality: [], recommendation: null, assumptions: {} }]) {
    test(`malformed brief ${JSON.stringify(brief)} renders with not given placeholders`, () => {
      const text = lib.renderQuestionsCompact([{ brief, reason: 'malformed_brief' }], [{ brief }]);
      assert.ok(text.includes('**Q1. not given**'));
      assert.ok(text.includes('- D1. not given Chose option not given.'));
      assert.ok(text.endsWith(REPLY_LINE));
    });
  }
});

describe('compact decisions', () => {
  const taken = [
    { brief: makeBrief({ problem: 'TAKEN_ONE', recommendation: { option_id: 'B', strength: 'strong', why: 'TAKEN_WHY' } }) },
    { brief: makeBrief({ problem: 'TAKEN_TWO' }) }
  ];
  test('renderDecisionsCompact lists one line per decision without the option summary', () => {
    assert.equal(lib.renderDecisionsCompact(taken), [
      'Decided for you:',
      '  D1. TAKEN_ONE Chose option B. Why: TAKEN_WHY',
      '  D2. TAKEN_TWO Chose option A. Why: WHY_TEXT'
    ].join('\n'));
  });
  test('renderDecisionsCompact of nothing is empty', () => {
    assert.equal(lib.renderDecisionsCompact([]), '');
  });
  test('labels equal the full form labels', () => {
    assert.deepEqual(labelsOf(lib.renderDecisionsCompact(taken)), labelsOf(lib.renderDecisions(taken)));
  });
  test('renderDecisionsCompact gives a long multi-sentence why one line, cut at a sentence end', () => {
    const sentence = 'This sentence explains one part of the choice in some detail.';
    const why = Array.from({ length: 8 }, () => sentence).join(' ') + '\nA second line of reasons.';
    const brief = makeBrief({ problem: 'LONG_WHY', recommendation: { option_id: 'B', strength: 'strong', why } });
    const lines = lib.renderDecisionsCompact([{ brief }]).split('\n');
    assert.equal(lines.length, 2);
    const kept = lib.cutAtBoundary(why.replace('\n', ' '), lib.maxExcerptLength());
    assert.equal(lines[1], '  D1. LONG_WHY Chose option B. Why: ' + kept);
    assert.ok(kept.endsWith('detail.'));
    assert.ok(Array.from(kept).length <= lib.maxExcerptLength());
    assert.ok(kept.length < why.length);
    assert.doesNotMatch(lines[1], /SUMMARY_B|VERBATIM_TEXT/);
  });
  test('argument checks', () => {
    assert.throws(() => lib.renderDecisionsCompact(undefined), /renderDecisionsCompact: taken must be an array/);
    assert.throws(() => lib.renderQuestionsCompact([], []), /renderQuestionsCompact: asks must be a non-empty array/);
    assert.throws(() => lib.renderQuestionsCompact([{ brief: makeBrief(), reason: 'hard_stop' }], null), /renderQuestionsCompact: taken must be an array/);
  });
});

describe('open questions stop reasons', () => {
  const open = [{ brief: makeBrief({ problem: 'FIRST_OPEN' }) }];
  const pauseIntro = 'I stopped asking after ' + lib.pauseLimit() + ' rounds of questions. These are still open:';
  const sizeIntro = 'I stopped asking because your replies so far are too long to carry into another round of questions. These are still open:';
  test('pause_limit keeps the default intro', () => {
    assert.equal(lib.renderOpenQuestions(open, 'pause_limit'), lib.renderOpenQuestions(open));
    assert.equal(lib.renderOpenQuestions(open, 'pause_limit').split('\n')[0], pauseIntro);
  });
  test('reply_size says the replies are too long to carry on', () => {
    assert.equal(lib.renderOpenQuestions(open, 'reply_size'), [
      sizeIntro,
      '  Q1. FIRST_OPEN The report assumes option A.'
    ].join('\n'));
  });
  test('exact_text_size says the exact text of a question is too long to show in full', () => {
    assert.equal(lib.renderOpenQuestions(open, 'exact_text_size'), [
      'I stopped asking because the exact text of a question is too long to show you in full. These are still open:',
      '  Q1. FIRST_OPEN The report assumes option A.'
    ].join('\n'));
  });
  test('every stop reason has its own intro', () => {
    const intros = ['pause_limit', 'reply_size', 'exact_text_size'].map((stopReason) => lib.renderOpenQuestions(open, stopReason).split('\n')[0]);
    assert.equal(new Set(intros).size, intros.length);
  });
  for (const stopReason of ['nonsense', null, '', 'before_pr']) {
    test(`stop reason ${JSON.stringify(stopReason)} throws`, () => {
      assert.throws(() => lib.renderOpenQuestions(open, stopReason), /renderOpenQuestions: no intro for stop reason/);
    });
  }
});

describe('questionLabel', () => {
  test('labels a position as Q followed by position plus one', () => {
    assert.equal(lib.questionLabel(0), 'Q1');
    assert.equal(lib.questionLabel(1), 'Q2');
    assert.equal(lib.questionLabel(2), 'Q3');
  });
  for (const index of [-1, 1.5, '0', undefined]) {
    test(`index ${JSON.stringify(index)} throws`, () => {
      assert.throws(() => lib.questionLabel(index), /questionLabel: index must be a non-negative integer/);
    });
  }
  const entries = [0, 1, 2].map((position) => ({ brief: makeBrief({ problem: `PROBLEM_${position}` }), reason: 'gate_irreversible' }));
  test('renderQuestions shows questionLabel by position', () => {
    const text = lib.renderQuestions(entries, []);
    entries.forEach((entry, index) => {
      assert.ok(text.includes(`${lib.questionLabel(index)}. PROBLEM_${index}`), `label ${index}`);
    });
  });
  test('renderQuestionsCompact shows questionLabel by position', () => {
    const text = lib.renderQuestionsCompact(entries, []);
    entries.forEach((entry, index) => {
      assert.ok(text.includes(`${lib.questionLabel(index)}. PROBLEM_${index}`), `label ${index}`);
    });
  });
  test('renderOpenQuestions shows questionLabel by position', () => {
    const text = lib.renderOpenQuestions(entries);
    entries.forEach((entry, index) => {
      assert.ok(text.includes(`  ${lib.questionLabel(index)}. PROBLEM_${index}`), `label ${index}`);
    });
  });
});

describe('exact entries', () => {
  const plain = { brief: makeBrief({ problem: 'PLAIN_PROBLEM', verbatim: 'PLAIN_VERBATIM' }), reason: 'gate_irreversible' };
  const exact = { brief: makeBrief({ problem: 'EXACT_PROBLEM', verbatim: 'EXACT_VERBATIM' }), reason: 'hard_stop', exact: true };
  test('the compact form keeps the Word for word lines of an exact entry', () => {
    assert.equal(lib.renderQuestionsCompact([exact], []), [
      ONE_HEADING,
      '',
      '**Q1. EXACT_PROBLEM**',
      '- A: SUMMARY_A (recommended)',
      '- B: SUMMARY_B',
      'Recommendation: option A (weak). Why: WHY_TEXT',
      '',
      'Word for word:',
      'EXACT_VERBATIM',
      '',
      REPLY_LINE
    ].join('\n'));
  });
  for (const [formName, render] of [['full', lib.renderQuestions], ['compact', lib.renderQuestionsCompact]]) {
    test(`only exact entries keep their Word for word lines in the ${formName} form`, () => {
      const text = render([plain, exact, plain], []);
      assert.equal(text.split('\n').filter((line) => line === 'Word for word:').length, 1);
      assert.ok(!text.includes('PLAIN_VERBATIM'));
      assertInOrder(text, ['Q1. PLAIN_PROBLEM', 'Q2. EXACT_PROBLEM', 'Word for word:', 'EXACT_VERBATIM', 'Q3. PLAIN_PROBLEM']);
    });
  }
  test('an exact verbatim is shown exactly as given, em dash included', () => {
    const verbatim = `drop the table ${EM_DASH} for good | now`;
    const text = lib.renderQuestionsCompact([{ ...exact, brief: makeBrief({ verbatim }) }], []);
    assert.ok(text.split('\n').includes(verbatim));
  });
  test('an exact entry without verbatim has no Exact text line', () => {
    const brief = makeBrief();
    delete brief.verbatim;
    assert.doesNotMatch(lib.renderQuestionsCompact([{ ...exact, brief }], []), /Word for word:/);
  });
  for (const flag of [false, 'true', 1, null]) {
    test(`exact ${JSON.stringify(flag)} renders as a plain entry`, () => {
      const entry = { ...exact, exact: flag };
      const plainEntry = { brief: entry.brief, reason: entry.reason };
      assert.equal(lib.renderQuestionsCompact([entry], []), lib.renderQuestionsCompact([plainEntry], []));
      assert.equal(lib.renderQuestions([entry], []), lib.renderQuestions([plainEntry], []));
      assert.doesNotMatch(lib.renderQuestions([entry], []), /EXACT_VERBATIM/);
    });
  }
  test('no output says Exact text', () => {
    const taken = [{ brief: makeBrief() }];
    const outputs = [
      lib.renderQuestions([plain, exact], taken),
      lib.renderQuestionsCompact([plain, exact], taken),
      lib.renderDecisions(taken),
      lib.renderDecisionsCompact(taken),
      ...['pause_limit', 'reply_size', 'exact_text_size'].map((stopReason) => lib.renderOpenQuestions([exact], stopReason))
    ];
    for (const output of outputs) {
      assert.equal(output.includes('Exact text'), false, output);
    }
  });
});

describe('decisionLabel', () => {
  test('labels a position as D followed by position plus one', () => {
    assert.equal(lib.decisionLabel(0), 'D1');
    assert.equal(lib.decisionLabel(1), 'D2');
    assert.equal(lib.decisionLabel(2), 'D3');
  });
  for (const index of [-1, 1.5, '0', undefined]) {
    test(`index ${JSON.stringify(index)} throws`, () => {
      assert.throws(() => lib.decisionLabel(index), /decisionLabel: index must be a non-negative integer/);
    });
  }
  const taken = [0, 1, 2].map((position) => ({ brief: makeBrief({ problem: `TAKEN_${position}` }) }));
  const ask = [{ brief: makeBrief(), reason: 'hard_stop' }];
  const renderers = [
    ['renderQuestions', () => lib.renderQuestions(ask, taken), '- '],
    ['renderQuestionsCompact', () => lib.renderQuestionsCompact(ask, taken), '- '],
    ['renderDecisions', () => lib.renderDecisions(taken), '  '],
    ['renderDecisionsCompact', () => lib.renderDecisionsCompact(taken), '  ']
  ];
  for (const [name, render, indent] of renderers) {
    test(`${name} shows decisionLabel by position`, () => {
      const text = render();
      taken.forEach((entry, index) => {
        assert.ok(text.includes(`${indent}${lib.decisionLabel(index)}. TAKEN_${index}`), `label ${index}`);
      });
    });
  }
  test('renderers keep their exact decision lines', () => {
    assert.equal(lib.renderDecisions([taken[0]]), [
      'Decided for you:',
      '  D1. TAKEN_0',
      '    Chose option A: SUMMARY_A',
      '    Why: WHY_TEXT',
      '    Word for word:',
      'VERBATIM_TEXT'
    ].join('\n'));
    assert.equal(lib.renderDecisionsCompact(taken.slice(0, 2)), [
      'Decided for you:',
      '  D1. TAKEN_0 Chose option A. Why: WHY_TEXT',
      '  D2. TAKEN_1 Chose option A. Why: WHY_TEXT'
    ].join('\n'));
    for (const text of [lib.renderQuestions(ask, taken.slice(0, 2)), lib.renderQuestionsCompact(ask, taken.slice(0, 2))]) {
      assert.ok(text.endsWith([
        'Decided for you:',
        '- D1. TAKEN_0 Chose option A.',
        '- D2. TAKEN_1 Chose option A.',
        'You can change any of these in the same reply.',
        '',
        REPLY_LINE
      ].join('\n')));
    }
  });
});

describe('listShownLabels', () => {
  const asks = ['FIRST', 'SECOND', 'THIRD'].map((problem, index) => ({
    brief: makeBrief({ id: 'Q' + (7 - index), problem }),
    reason: 'gate_irreversible'
  }));
  const taken = [
    { brief: makeBrief({ id: 'D8', problem: 'TAKEN_ONE' }) },
    { brief: makeBrief({ id: 'D9', problem: 'TAKEN_TWO' }) }
  ];
  test('lists Q1..Qn for asks, then D1..Dm for taken decisions', () => {
    assert.deepEqual([...lib.listShownLabels(asks, taken)], ['Q1', 'Q2', 'Q3', 'D1', 'D2']);
  });
  test('lists only question labels when nothing was taken', () => {
    assert.deepEqual([...lib.listShownLabels(asks.slice(0, 1), [])], ['Q1']);
  });
  test('uses questionLabel and decisionLabel by position', () => {
    assert.deepEqual([...lib.listShownLabels(asks, taken)], [
      ...asks.map((entry, index) => lib.questionLabel(index)),
      ...taken.map((entry, index) => lib.decisionLabel(index))
    ]);
  });
  test('equals the labels the full and compact question messages show', () => {
    const labels = [...lib.listShownLabels(asks, taken)];
    assert.deepEqual(labelsOf(lib.renderQuestions(asks, taken)), labels);
    assert.deepEqual(labelsOf(lib.renderQuestionsCompact(asks, taken)), labels);
  });
  test('argument checks', () => {
    assert.throws(() => lib.listShownLabels([], []), /listShownLabels: asks must be a non-empty array/);
    assert.throws(() => lib.listShownLabels(undefined, []), /listShownLabels: asks must be a non-empty array/);
    assert.throws(() => lib.listShownLabels(asks, null), /listShownLabels: taken must be an array/);
    assert.throws(() => lib.listShownLabels(asks, undefined), /listShownLabels: taken must be an array/);
  });
});
