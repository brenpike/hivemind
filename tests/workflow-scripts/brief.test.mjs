import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const libDir = repoRoot + 'plugin/workflow-src/lib/';
const lib = loadLibs(['decide.js', 'brief.js', 'result.js'].map((name) => libDir + name));
const EM_DASH = '\u2014';
const REPLY_LINE = 'Reply in your own words. You can point at a question by its label, like Q1.';

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

describe('renderQuestions field order', () => {
  const text = lib.renderQuestions([{ brief: makeBrief(), reason: 'gate_irreversible' }], []);
  test('shows every field in the contract order', () => {
    assertInOrder(text, [
      'Q1. PROBLEM_TEXT',
      'How serious: high criticality, likelihood edge case.',
      'If it goes wrong: BLAST_TEXT',
      'If ignored: IGNORED_TEXT',
      'Option A: SUMMARY_A', 'Case for: FOR_A', 'Case against: AGAINST_A', 'Effort small, value high, reversible: yes.',
      'Option B: SUMMARY_B', 'Case for: FOR_B', 'Case against: AGAINST_B', 'Effort large, value low, reversible: no.',
      'Recommendation: option A (weak). Why: WHY_TEXT',
      'Why I am asking: ',
      'USER_STATEMENT', 'REPO_STATEMENT', 'ASSUMED_STATEMENT',
      'Exact text:', 'VERBATIM_TEXT'
    ]);
  });
  test('never shows brief.id or brief.kind', () => {
    assert.doesNotMatch(text, /Q9|planner_question/);
  });
  test('ends with one line telling the user to reply in their own words', () => {
    const lines = text.split('\n');
    assert.equal(lines[lines.length - 1], REPLY_LINE);
    assert.equal(lines.filter((line) => line === REPLY_LINE).length, 1);
  });
  test('omits the verbatim block when verbatim is absent', () => {
    const brief = makeBrief();
    delete brief.verbatim;
    assert.doesNotMatch(lib.renderQuestions([{ brief, reason: 'hard_stop' }], []), /Exact text:/);
  });
  test('shows verbatim exactly as given', () => {
    const verbatim = `keep ${EM_DASH} this | as is`;
    const rendered = lib.renderQuestions([{ brief: makeBrief({ verbatim }), reason: 'hard_stop' }], []);
    assert.ok(rendered.split('\n').includes(verbatim));
  });
  test('shows a recommendation of none', () => {
    const recommendation = { option_id: '', strength: 'none', why: 'NONE_WHY' };
    const rendered = lib.renderQuestions([{ brief: makeBrief({ recommendation }), reason: 'no_recommendation' }], []);
    assert.equal(lineContaining(rendered, 'Recommendation:'), 'Recommendation: none. Why: NONE_WHY');
  });
});

describe('labels', () => {
  test('questions are labelled Q1..Qn by position, not by brief.id', () => {
    const asks = ['FIRST', 'SECOND', 'THIRD'].map((problem, index) => ({
      brief: makeBrief({ id: 'Q' + (7 - index), problem }),
      reason: 'table_surface'
    }));
    const text = lib.renderQuestions(asks, []);
    assertInOrder(text, ['Q1. FIRST', 'Q2. SECOND', 'Q3. THIRD']);
    assert.doesNotMatch(text, /Q[4-7]/);
    assert.match(text, /^I need your answers on 3 questions before I go on\./);
  });
  test('one question uses the singular intro', () => {
    const text = lib.renderQuestions([{ brief: makeBrief(), reason: 'hard_stop' }], []);
    assert.match(text, /^I need your answer on 1 question before I go on\./);
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

describe('assumptions', () => {
  const text = lib.renderQuestions([{ brief: makeBrief(), reason: 'hard_stop' }], []);
  test('assumed origin is marked as something the user can overrule', () => {
    assert.equal(lineContaining(text, 'ASSUMED_STATEMENT'), '  - ASSUMED_STATEMENT (my assumption, you can overrule it: ASSUMED_EVIDENCE)');
  });
  test('user and repo origins are not marked as overrulable', () => {
    assert.equal(lineContaining(text, 'USER_STATEMENT'), '  - USER_STATEMENT (you said so: USER_EVIDENCE)');
    assert.equal(lineContaining(text, 'REPO_STATEMENT'), '  - REPO_STATEMENT (from the repo: REPO_EVIDENCE)');
    assert.equal(text.split('overrule').length - 1, 1);
  });
  test('no assumptions renders a none line', () => {
    const rendered = lib.renderQuestions([{ brief: makeBrief({ assumptions: [] }), reason: 'hard_stop' }], []);
    assert.ok(rendered.split('\n').includes('Assumptions: none.'));
  });
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
      '  D2. TAKEN_TWO',
      '    Chose option A: SUMMARY_A',
      '    Why: WHY_TEXT'
    ].join('\n'));
  });
  test('renderDecisions of nothing is empty', () => {
    assert.equal(lib.renderDecisions([]), '');
  });
  test('renderQuestions lists them after the questions and says they can be changed in the same reply', () => {
    const text = lib.renderQuestions([{ brief: makeBrief(), reason: 'hard_stop' }], taken);
    assertInOrder(text, ['Q1. PROBLEM_TEXT', 'Decided for you:', 'D1. TAKEN_ONE', 'D2. TAKEN_TWO',
      'You can change any of these in the same reply.', REPLY_LINE]);
    assert.ok(text.endsWith(REPLY_LINE));
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
      assert.ok(text.includes('Q1. not given'));
      assert.ok(text.includes('Options: not given.'));
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
      '  Q2. SECOND_OPEN There is no recommendation.'
    ].join('\n'));
  });
  test('strength none has no recommendation even with an option id', () => {
    const brief = makeBrief({ recommendation: { option_id: 'B', strength: 'none', why: 'W' } });
    assert.ok(lib.renderOpenQuestions([{ brief }]).endsWith('Q1. PROBLEM_TEXT There is no recommendation.'));
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
      assert.ok(lib.renderOpenQuestions([{ brief }]).endsWith('Q1. not given There is no recommendation.'));
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
    .map((line) => line.match(/^\s*([QD]\d+)\./))
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
  test('keeps the intro line and the reply line of the full form', () => {
    assert.equal(compact.split('\n')[0], full.split('\n')[0]);
    assert.ok(compact.endsWith(REPLY_LINE));
    assert.equal(compact.split('\n').filter((line) => line === REPLY_LINE).length, 1);
  });
  test('shows only the problem and the recommendation with its why', () => {
    const text = lib.renderQuestionsCompact([{ brief: makeBrief(), reason: 'hard_stop' }], []);
    assert.equal(text, [
      'I need your answer on 1 question before I go on.',
      '',
      'Q1. PROBLEM_TEXT',
      'Recommendation: option A (weak). Why: WHY_TEXT',
      '',
      REPLY_LINE
    ].join('\n'));
  });
  test('omits the detail the full form carries', () => {
    for (const needle of ['Case for:', 'How serious:', 'Assumptions', 'Exact text:']) {
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
      assert.ok(text.includes('Q1. not given'));
      assert.ok(text.includes('  D1. not given Chose option not given. Why: not given'));
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
  test('before_pr says the run stopped before the pull request and asks to run the request again with the answer', () => {
    assert.equal(lib.renderOpenQuestions(open, 'before_pr'), [
      'I stopped before the pull request because these questions need your answer. Run the request again with your answer. These are still open:',
      '  Q1. FIRST_OPEN The report assumes option A.'
    ].join('\n'));
  });
  test('every stop reason has its own intro', () => {
    const intros = ['pause_limit', 'reply_size', 'exact_text_size', 'before_pr'].map((stopReason) => lib.renderOpenQuestions(open, stopReason).split('\n')[0]);
    assert.equal(new Set(intros).size, intros.length);
  });
  for (const stopReason of ['nonsense', null, '']) {
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
  test('the compact form keeps the Exact text lines of an exact entry', () => {
    assert.equal(lib.renderQuestionsCompact([exact], []), [
      'I need your answer on 1 question before I go on.',
      '',
      'Q1. EXACT_PROBLEM',
      'Recommendation: option A (weak). Why: WHY_TEXT',
      'Exact text:',
      'EXACT_VERBATIM',
      '',
      REPLY_LINE
    ].join('\n'));
  });
  test('only exact entries keep their Exact text lines', () => {
    const text = lib.renderQuestionsCompact([plain, exact, plain], []);
    assert.equal(text.split('\n').filter((line) => line === 'Exact text:').length, 1);
    assert.ok(!text.includes('PLAIN_VERBATIM'));
    assertInOrder(text, ['Q1. PLAIN_PROBLEM', 'Q2. EXACT_PROBLEM', 'Exact text:', 'EXACT_VERBATIM', 'Q3. PLAIN_PROBLEM']);
  });
  test('an exact verbatim is shown exactly as given, em dash included', () => {
    const verbatim = `drop the table ${EM_DASH} for good | now`;
    const text = lib.renderQuestionsCompact([{ ...exact, brief: makeBrief({ verbatim }) }], []);
    assert.ok(text.split('\n').includes(verbatim));
  });
  test('an exact entry without verbatim has no Exact text line', () => {
    const brief = makeBrief();
    delete brief.verbatim;
    assert.doesNotMatch(lib.renderQuestionsCompact([{ ...exact, brief }], []), /Exact text:/);
  });
  for (const flag of [false, 'true', 1, null]) {
    test(`exact ${JSON.stringify(flag)} renders as a plain entry`, () => {
      const entry = { ...exact, exact: flag };
      assert.equal(lib.renderQuestionsCompact([entry], []), lib.renderQuestionsCompact([{ brief: entry.brief, reason: entry.reason }], []));
    });
  }
  test('the full form is the same with or without exact', () => {
    assert.equal(lib.renderQuestions([plain, exact], []), lib.renderQuestions([plain, { brief: exact.brief, reason: exact.reason }], []));
  });
});
