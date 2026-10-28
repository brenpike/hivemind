import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';
import { listSourcePaths, stripCommentsAndStrings } from '../../tools/build_workflows.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const libDir = repoRoot + 'plugin/workflow-src/lib/';
const lib = loadLibs(['decide.js', 'brief.js', 'result.js'].map((name) => libDir + name));
const EM_DASH = '—';
const ONE_REPLY_LINE = 'Reply with an option, like A, or in your own words.';
const MANY_REPLY_LINE = 'Reply with a label and an option for each, like Q1 A, or in your own words.';

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

function labelsOf(text) {
  return text.split('\n')
    .map((line) => line.match(/^\s*(?:- |\*\*)?([QD]\d+)\./))
    .filter((match) => match !== null)
    .map((match) => match[1]);
}

describe('renderQuestions layout', () => {
  const text = lib.renderQuestions([{ brief: makeBrief(), reason: 'gate_irreversible' }]);
  test('shows the question, its options and the recommendation, then the reply line, with no verbatim for a non-exact ask', () => {
    assert.equal(text, [
      '**Q1. PROBLEM_TEXT**',
      '- A: SUMMARY_A (recommended)',
      '- B: SUMMARY_B',
      'Recommendation: A (weak). WHY_TEXT',
      '',
      ONE_REPLY_LINE
    ].join('\n'));
  });
  test('an exact ask shows its verbatim encoded under Word for word', () => {
    const exactText = lib.renderQuestions([{ brief: makeBrief(), reason: 'gate_irreversible', exact: true }]);
    assert.equal(exactText, text.replace('\n\n' + ONE_REPLY_LINE, '\n\nWord for word:\n"VERBATIM_TEXT"\n\n' + ONE_REPLY_LINE));
  });
  test('one question with two options and no verbatim fits in 6 lines', () => {
    const brief = makeBrief();
    delete brief.verbatim;
    const lines = lib.renderQuestions([{ brief, reason: 'hard_stop' }]).split('\n');
    assert.ok(lines.length <= 6, `${lines.length} lines`);
  });
  test('shows no heading, no criticality and no ask reason', () => {
    assert.equal(text.startsWith('**Q1.'), true);
    for (const needle of ['Answer Q1', 'Why it matters', 'Why I am asking', 'BLAST_TEXT', 'criticality', 'likelihood', 'Why:']) {
      assert.equal(text.includes(needle), false, `shows ${needle}`);
    }
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
    assert.equal(lines[lines.length - 1], ONE_REPLY_LINE);
    assert.equal(lines.filter((line) => line === ONE_REPLY_LINE).length, 1);
  });
  test('the reply line asks for an option alone for one question and a label and an option for more', () => {
    const entry = { brief: makeBrief(), reason: 'hard_stop' };
    assert.ok(lib.renderQuestions([entry]).endsWith('\n\n' + ONE_REPLY_LINE));
    for (const count of [2, 3]) {
      const many = lib.renderQuestions(Array.from({ length: count }, () => entry));
      assert.ok(many.endsWith('\n\n' + MANY_REPLY_LINE), many);
      assert.equal(many.includes(ONE_REPLY_LINE), false);
    }
  });
  test('the ask reason does not change the text', () => {
    const reasons = [...lib.decisionReasons(), 'nonsense', undefined];
    for (const reason of reasons) {
      assert.equal(lib.renderQuestions([{ brief: makeBrief(), reason }]), text, String(reason));
    }
  });
  test('omits the verbatim section when verbatim is absent', () => {
    const brief = makeBrief();
    delete brief.verbatim;
    assert.doesNotMatch(lib.renderQuestions([{ brief, reason: 'hard_stop', exact: true }]), /Word for word:/);
  });
  test('shows the verbatim of an exact ask encoded on one line, nothing lost', () => {
    const verbatim = `keep ${EM_DASH} this | as is`;
    const rendered = lib.renderQuestions([{ brief: makeBrief({ verbatim }), reason: 'hard_stop', exact: true }]);
    const shown = lib.encodeUntrustedText(verbatim);
    assert.ok(rendered.split('\n').includes(shown));
    assert.equal(JSON.parse(shown), verbatim);
  });
  test('shows a multi-line verbatim of an exact ask whole, on one line', () => {
    const verbatim = 'line one\n\nline three';
    const rendered = lib.renderQuestions([{ brief: makeBrief({ verbatim }), reason: 'hard_stop', exact: true }]);
    assert.ok(rendered.includes('Word for word:\n"line one\\n\\nline three"\n\n'));
    assert.equal(rendered.includes(verbatim), false);
  });
  test('shows a recommendation of none and marks no option', () => {
    const recommendation = { option_id: 'A', strength: 'none', why: 'NONE_WHY' };
    const rendered = lib.renderQuestions([{ brief: makeBrief({ recommendation }), reason: 'no_recommendation' }]);
    assert.equal(lineContaining(rendered, 'Recommendation:'), 'Recommendation: none. NONE_WHY');
    assert.doesNotMatch(rendered, /recommended\)/);
  });
  test('marks only the recommended option and names its strength', () => {
    const recommendation = { option_id: 'B', strength: 'strong', why: 'W' };
    const rendered = lib.renderQuestions([{ brief: makeBrief({ recommendation }), reason: 'hard_stop' }]);
    assert.ok(rendered.includes('- A: SUMMARY_A\n- B: SUMMARY_B (recommended)\nRecommendation: B (strong). W\n'));
  });
});

describe('option letters', () => {
  test('optionLabel gives the letter for a position', () => {
    assert.deepEqual([0, 1, 2, 3, 25, 26, 27, 51, 52].map((index) => lib.optionLabel(index)),
      ['A', 'B', 'C', 'D', 'Z', 'AA', 'AB', 'AZ', 'BA']);
  });
  for (const index of [-1, 1.5, '0', undefined]) {
    test(`optionLabel index ${JSON.stringify(index)} throws`, () => {
      assert.throws(() => lib.optionLabel(index), /optionLabel: index must be a non-negative integer/);
    });
  }
  const options = [{ id: 'X', summary: 'SUMMARY_X' }, { id: 'Y', summary: 'SUMMARY_Y' }, { id: 'Z', summary: 'SUMMARY_Z' }];
  const recommendation = { option_id: 'Y', strength: 'strong', why: 'W' };
  const brief = makeBrief({ options, recommendation });
  test('renderQuestions shows options by position, not by their ids', () => {
    assert.equal(lib.renderQuestions([{ brief }]), [
      '**Q1. PROBLEM_TEXT**',
      '- A: SUMMARY_X',
      '- B: SUMMARY_Y (recommended)',
      '- C: SUMMARY_Z',
      'Recommendation: B (strong). W',
      '',
      ONE_REPLY_LINE
    ].join('\n'));
  });
  test('the decision and open question renderers show the letter of the matching option', () => {
    assert.ok(lib.renderDecisions([{ brief }]).includes('    Chose option B: SUMMARY_Y\n'));
    assert.ok(lib.renderDecisionsCompact([{ brief }]).endsWith('- D1. PROBLEM_TEXT Chose B: SUMMARY_Y.'));
    assert.ok(lib.renderOpenQuestions([{ brief }]).endsWith('Q1. PROBLEM_TEXT The report assumes option B.'));
  });
  test('duplicate option ids mark only the first match', () => {
    const twins = makeBrief({ options: [{ id: 'A', summary: 'FIRST' }, { id: 'A', summary: 'SECOND' }] });
    const text = lib.renderQuestions([{ brief: twins }]);
    assert.ok(text.includes('- A: FIRST (recommended)\n- B: SECOND\nRecommendation: A (weak).'));
  });
  test('a recommendation id that names no option marks nothing and shows not given', () => {
    const stray = makeBrief({ recommendation: { option_id: 'Q', strength: 'strong', why: 'W' } });
    const text = lib.renderQuestions([{ brief: stray }]);
    assert.doesNotMatch(text, /recommended\)/);
    assert.equal(lineContaining(text, 'Recommendation:'), 'Recommendation: not given (strong). W');
    assert.ok(lib.renderDecisions([{ brief: stray }]).includes('    Chose option not given: not given\n'));
    assert.ok(lib.renderDecisionsCompact([{ brief: stray }]).endsWith('- D1. PROBLEM_TEXT Chose not given: not given.'));
    assert.ok(lib.renderOpenQuestions([{ brief: stray }]).endsWith('Q1. PROBLEM_TEXT The report assumes option not given.'));
  });
  test('option ids are never shown', () => {
    const hidden = makeBrief({ options: [{ id: 'HIDDEN_ONE', summary: 'S1' }, { id: 'HIDDEN_TWO', summary: 'S2' }], recommendation: { option_id: 'HIDDEN_TWO', strength: 'weak', why: 'W' } });
    const outputs = [
      lib.renderQuestions([{ brief: hidden }]),
      lib.renderDecisions([{ brief: hidden }]),
      lib.renderDecisionsCompact([{ brief: hidden }]),
      lib.renderOpenQuestions([{ brief: hidden }])
    ];
    for (const output of outputs) {
      assert.doesNotMatch(output, /HIDDEN_/, output);
    }
  });
});

describe('labels', () => {
  test('questions are labelled Q1..Qn by position, not by brief.id, apart by blank lines', () => {
    const asks = ['FIRST', 'SECOND', 'THIRD'].map((problem, index) => ({
      brief: makeBrief({ id: 'Q' + (7 - index), problem }),
      reason: 'table_surface'
    }));
    const text = lib.renderQuestions(asks);
    assertInOrder(text, ['**Q1. FIRST**', '\n\n**Q2. SECOND**', '\n\n**Q3. THIRD**', '\n\n' + MANY_REPLY_LINE]);
    assert.doesNotMatch(text, /Q[4-7]/);
    assert.equal(text.split('\n')[0], '**Q1. FIRST**');
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
  test('renderDecisions keeps a multi-line verbatim raw for the pull request body', () => {
    const verbatim = 'line one\n\nline three';
    assert.ok(lib.renderDecisions([{ brief: makeBrief({ verbatim }) }]).endsWith('    Word for word:\n' + verbatim));
  });
  test('renderDecisions of nothing is empty', () => {
    assert.equal(lib.renderDecisions([]), '');
  });
});

describe('compact decisions', () => {
  const taken = [
    { brief: makeBrief({ problem: 'TAKEN_ONE', recommendation: { option_id: 'B', strength: 'strong', why: 'TAKEN_WHY' } }) },
    { brief: makeBrief({ problem: 'TAKEN_TWO' }) }
  ];
  test('renderDecisionsCompact lists one line per decision with the chosen option summary', () => {
    assert.equal(lib.renderDecisionsCompact(taken), [
      'Decided for you:',
      '- D1. TAKEN_ONE Chose B: SUMMARY_B.',
      '- D2. TAKEN_TWO Chose A: SUMMARY_A.'
    ].join('\n'));
  });
  test('renderDecisionsCompact shows no why and no verbatim', () => {
    const text = lib.renderDecisionsCompact(taken);
    for (const needle of ['TAKEN_WHY', 'WHY_TEXT', 'Why', 'VERBATIM_TEXT', 'Word for word:']) {
      assert.equal(text.includes(needle), false, `shows ${needle}`);
    }
  });
  test('renderDecisionsCompact of nothing is empty', () => {
    assert.equal(lib.renderDecisionsCompact([]), '');
  });
  test('labels equal the full form labels', () => {
    assert.deepEqual(labelsOf(lib.renderDecisionsCompact(taken)), labelsOf(lib.renderDecisions(taken)));
    assert.deepEqual(labelsOf(lib.renderDecisionsCompact(taken)), ['D1', 'D2']);
  });
  test('never shows brief.id or brief.kind', () => {
    const text = lib.renderDecisionsCompact([{ brief: makeBrief({ id: 'D8' }) }]);
    assert.doesNotMatch(text, /D8|planner_question/);
  });
  test('has no em dash, even when brief fields have one', () => {
    const dashed = makeBrief({ problem: `Pick one ${EM_DASH} or not`, options: [{ id: 'A', summary: `Cheap${EM_DASH}fast` }], recommendation: { option_id: 'A', strength: 'strong', why: 'W' } });
    const text = lib.renderDecisionsCompact([{ brief: dashed }]);
    assert.equal(text.includes(EM_DASH), false);
    assert.ok(text.endsWith('- D1. Pick one, or not Chose A: Cheap, fast.'));
  });
  for (const brief of [null, undefined, {}, { problem: 7, options: 'x', recommendation: null }]) {
    test(`malformed brief ${JSON.stringify(brief)} renders with not given placeholders`, () => {
      assert.equal(lib.renderDecisionsCompact([{ brief }]), 'Decided for you:\n- D1. not given Chose not given: not given.');
    });
  }
  test('argument checks', () => {
    assert.throws(() => lib.renderDecisionsCompact(undefined), /renderDecisionsCompact: taken must be an array/);
  });
});

describe('plain text', () => {
  const dashed = makeBrief({ problem: `Pick one ${EM_DASH} or not`, recommendation: { option_id: 'A', strength: 'strong', why: `Because${EM_DASH}cheap` } });
  delete dashed.verbatim;
  const text = lib.renderQuestions([{ brief: dashed, reason: 'gate_safety' }]);
  test('has no em dash, even when brief fields have one', () => {
    assert.equal(text.includes(EM_DASH), false);
    assert.ok(text.includes('Pick one, or not'));
    assert.ok(text.includes('Recommendation: A (strong). Because, cheap'));
  });
  test('has no markdown table rows', () => {
    for (const line of text.split('\n')) {
      assert.doesNotMatch(line, /^\s*\|/);
    }
  });
});

describe('renderText', () => {
  test('keeps plain text as given', () => {
    assert.equal(lib.renderText('Plain text, kept.'), 'Plain text, kept.');
  });
  for (const value of [undefined, null, 7, {}, [], '', '   ', '\n\t', '\u0000 ‮']) {
    test(`${JSON.stringify(value)} renders as not given`, () => {
      assert.equal(lib.renderText(value), 'not given');
    });
  }
  const breakers = {
    'line feed': '\n', 'carriage return': '\r', 'CRLF': '\r\n', 'tab': '\t', 'vertical tab': '\u000b', 'form feed': '\u000c',
    'NUL': '\u0000', 'escape': '\u001b', 'DEL': '\u007f', 'NEL': '\u0085', 'C1 CSI': '\u009b',
    'line separator': ' ', 'paragraph separator': ' ',
    'ALM': '؜', 'LRM': '‎', 'RLM': '‏', 'LRE': '‪', 'RLO': '‮', 'LRI': '⁦', 'PDI': '⁩'
  };
  for (const [name, breaker] of Object.entries(breakers)) {
    test(`a ${name} becomes one space`, () => {
      assert.equal(lib.renderText('left' + breaker + 'right'), 'left right');
      assert.equal(lib.renderText('left ' + breaker + breaker + ' right'), 'left right');
    });
  }
  test('collapses whitespace runs and trims the ends', () => {
    assert.equal(lib.renderText('  a \n\n  b  c  '), 'a b c');
  });
  test('keeps the em dash rule', () => {
    assert.equal(lib.renderText(`a\n${EM_DASH}\nb`), 'a, b');
    assert.equal(lib.renderText(`a${EM_DASH}b`), 'a, b');
  });
});

describe('malformed briefs still render', () => {
  for (const brief of [null, undefined, {}, { problem: 7, options: 'x', criticality: [], recommendation: null, assumptions: {} }]) {
    test(`brief ${JSON.stringify(brief)} renders with not given placeholders`, () => {
      const text = lib.renderQuestions([{ brief, reason: 'malformed_brief' }]);
      assert.equal(text, [
        '**Q1. not given**',
        'Options: not given.',
        'Recommendation: not given (not given). not given',
        '',
        ONE_REPLY_LINE
      ].join('\n'));
    });
  }
  test('more than 26 options still render, lettered past Z', () => {
    const options = Array.from({ length: 28 }, (unused, index) => ({ id: 'O' + index, summary: 'S' + index }));
    const text = lib.renderQuestions([{ brief: makeBrief({ options, recommendation: { option_id: 'O27', strength: 'weak', why: 'W' } }) }]);
    assert.ok(text.includes('- Z: S25\n- AA: S26\n- AB: S27 (recommended)\nRecommendation: AB (weak). W'));
  });
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
  test('has no em dash, even when brief fields have one, and an id that names no option shows not given', () => {
    const brief = makeBrief({ problem: `Pick one ${EM_DASH} or not`, recommendation: { option_id: `A${EM_DASH}1`, strength: 'weak', why: 'W' } });
    const text = lib.renderOpenQuestions([{ brief }]);
    assert.equal(text.includes(EM_DASH), false);
    assert.ok(text.endsWith('Q1. Pick one, or not The report assumes option not given.'));
  });
  for (const brief of [null, undefined, {}, { problem: 7, recommendation: [] }]) {
    test(`malformed brief ${JSON.stringify(brief)} renders with not given placeholders`, () => {
      assert.ok(lib.renderOpenQuestions([{ brief }]).endsWith('Q1. not given I have no recommendation of my own.'));
    });
  }
});

describe('argument checks', () => {
  test('renderQuestions needs at least one ask', () => {
    assert.throws(() => lib.renderQuestions([]), /asks must be a non-empty array/);
    assert.throws(() => lib.renderQuestions(undefined), /asks must be a non-empty array/);
  });
  test('taken must be an array', () => {
    assert.throws(() => lib.renderDecisions(undefined), /taken must be an array/);
  });
  test('the deleted renderers are gone', () => {
    for (const name of ['renderQuestionsCompact', 'askReasonLine', 'renderHeading', 'renderWhyItMatters', 'renderTakenLines', 'renderTakenLine', 'renderCompactQuestion']) {
      assert.equal(lib[name], undefined, name);
    }
  });
  test('renderOpenQuestions needs at least one open question', () => {
    assert.throws(() => lib.renderOpenQuestions([]), /open must be a non-empty array/);
    assert.throws(() => lib.renderOpenQuestions(undefined), /open must be a non-empty array/);
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
    const text = lib.renderQuestions(entries);
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
  test('an exact entry keeps its Word for word lines after its question', () => {
    assert.equal(lib.renderQuestions([exact]), [
      '**Q1. EXACT_PROBLEM**',
      '- A: SUMMARY_A (recommended)',
      '- B: SUMMARY_B',
      'Recommendation: A (weak). WHY_TEXT',
      '',
      'Word for word:',
      '"EXACT_VERBATIM"',
      '',
      ONE_REPLY_LINE
    ].join('\n'));
  });
  test('only exact entries keep their Word for word lines', () => {
    const text = lib.renderQuestions([plain, exact, plain]);
    assert.equal(text.split('\n').filter((line) => line === 'Word for word:').length, 1);
    assert.ok(!text.includes('PLAIN_VERBATIM'));
    assertInOrder(text, ['Q1. PLAIN_PROBLEM', 'Q2. EXACT_PROBLEM', 'Word for word:', '"EXACT_VERBATIM"', 'Q3. PLAIN_PROBLEM', MANY_REPLY_LINE]);
  });
  test('an exact verbatim is shown whole and encoded, em dash included', () => {
    const verbatim = `drop the table ${EM_DASH} for good | now`;
    const text = lib.renderQuestions([{ ...exact, brief: makeBrief({ verbatim }) }]);
    assert.ok(text.split('\n').includes('"drop the table \\u2014 for good | now"'));
    assert.equal(text.includes(EM_DASH), false);
  });
  for (const flag of [false, 'true', 1, null]) {
    test(`exact ${JSON.stringify(flag)} renders as a plain entry`, () => {
      const entry = { ...exact, exact: flag };
      const plainEntry = { brief: entry.brief, reason: entry.reason };
      assert.equal(lib.renderQuestions([entry]), lib.renderQuestions([plainEntry]));
      assert.doesNotMatch(lib.renderQuestions([entry]), /EXACT_VERBATIM/);
    });
  }
  test('no output says Exact text', () => {
    const taken = [{ brief: makeBrief() }];
    const outputs = [
      lib.renderQuestions([plain, exact]),
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
  const renderers = [
    ['renderDecisions', () => lib.renderDecisions(taken), '  '],
    ['renderDecisionsCompact', () => lib.renderDecisionsCompact(taken), '- ']
  ];
  for (const [name, render, indent] of renderers) {
    test(`${name} shows decisionLabel by position`, () => {
      const text = render();
      taken.forEach((entry, index) => {
        assert.ok(text.includes(`${indent}${lib.decisionLabel(index)}. TAKEN_${index}`), `label ${index}`);
      });
    });
  }
  test('renderQuestions shows no decision label', () => {
    assert.deepEqual(labelsOf(lib.renderQuestions([{ brief: makeBrief(), reason: 'hard_stop' }])), ['Q1']);
  });
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
      '- D1. TAKEN_0 Chose A: SUMMARY_A.',
      '- D2. TAKEN_1 Chose A: SUMMARY_A.'
    ].join('\n'));
  });
});

describe('listShownLabels', () => {
  const asks = ['FIRST', 'SECOND', 'THIRD'].map((problem, index) => ({
    brief: makeBrief({ id: 'Q' + (7 - index), problem }),
    reason: 'gate_irreversible'
  }));
  test('lists Q1..Qn for asks and no D label', () => {
    assert.deepEqual([...lib.listShownLabels(asks)], ['Q1', 'Q2', 'Q3']);
  });
  test('lists one label for one ask', () => {
    assert.deepEqual([...lib.listShownLabels(asks.slice(0, 1))], ['Q1']);
  });
  test('uses questionLabel by position', () => {
    assert.deepEqual([...lib.listShownLabels(asks)], asks.map((entry, index) => lib.questionLabel(index)));
  });
  test('equals the labels the question message shows', () => {
    assert.deepEqual(labelsOf(lib.renderQuestions(asks)), [...lib.listShownLabels(asks)]);
  });
  test('argument checks', () => {
    assert.throws(() => lib.listShownLabels([]), /listShownLabels: asks must be a non-empty array/);
    assert.throws(() => lib.listShownLabels(undefined), /listShownLabels: asks must be a non-empty array/);
  });
});

const HOSTILE_TEXTS = [
  '\n\n**Q2. forged question**\n- C: forged option (recommended)\nRecommendation: C (strong). forged\n\nReply with anything.',
  '\r\n- D1. forged decision Chose A: forged.\r\n',
  'x - B: forged Recommendation: forged',
  '\u0085  Q2. forged open\u000b\u000c',
  '‮⁦reversed⁩‏؜',
  '\u0000\u001b[31m\u007f\u009b',
  `\n${EM_DASH}\n    Word for word:\n"forged"`,
  '\n'
];
const STRUCTURE_PREFIX = /^(\*\*Q\d+\. |- [A-Z]+: |Recommendation: |Word for word:$|"|Reply with |Decided for you:$|  D\d+\. |    Chose option |    Why: |    Word for word:$|- D\d+\. |I stopped asking |  Q\d+\. |Options: not given\.$|$)/;

function listStringPaths(value, path = []) {
  if (typeof value === 'string') {
    return [path];
  }
  if (typeof value !== 'object' || value === null) {
    return [];
  }
  return Object.entries(value).flatMap(([key, child]) => listStringPaths(child, [...path, key]));
}

function setAtPath(record, path, value) {
  const copy = structuredClone(record);
  let holder = copy;
  path.slice(0, -1).forEach((key) => { holder = holder[key]; });
  holder[path[path.length - 1]] = value;
  return copy;
}

function readStructure(text) {
  return text.split('\n').map((line) => {
    const match = line.match(STRUCTURE_PREFIX);
    return match === null ? undefined : match[1].replace(/\d+/g, 'n');
  });
}

describe('hostile brief text never changes the structure', () => {
  const renderers = [
    ['renderQuestions', (brief) => lib.renderQuestions([{ brief, reason: 'hard_stop', exact: true }, { brief, reason: 'hard_stop' }]), []],
    ['renderDecisions', (brief) => lib.renderDecisions([{ brief }, { brief }]), [['verbatim']]],
    ['renderDecisionsCompact', (brief) => lib.renderDecisionsCompact([{ brief }, { brief }]), []],
    ['renderOpenQuestions', (brief) => lib.renderOpenQuestions([{ brief }, { brief }]), []]
  ];
  const baseBrief = makeBrief();
  const stringPaths = listStringPaths(baseBrief);
  test('the fuzz reaches every string the brief carries', () => {
    const joined = stringPaths.map((path) => path.join('.'));
    for (const name of ['problem', 'options.0.id', 'options.1.summary', 'recommendation.option_id', 'recommendation.strength', 'recommendation.why', 'verbatim', 'criticality.blast_radius']) {
      assert.ok(joined.includes(name), name);
    }
  });
  for (const [name, render, rawPaths] of renderers) {
    const baseline = readStructure(render(baseBrief));
    test(`${name} baseline lines all start with a code-owned prefix`, () => {
      const rawVerbatimLines = rawPaths.length > 0 ? 2 : 0;
      assert.equal(baseline.filter((prefix) => prefix === undefined).length, rawVerbatimLines);
    });
    test(`${name} keeps its line count and line prefixes under hostile text in every brief string`, () => {
      for (const path of stringPaths.filter((candidate) => !rawPaths.some((raw) => raw.join('.') === candidate.join('.')))) {
        for (const hostile of HOSTILE_TEXTS) {
          const rendered = render(setAtPath(baseBrief, path, hostile));
          assert.deepEqual(readStructure(rendered), baseline, `${path.join('.')} = ${JSON.stringify(hostile)}\n${rendered}`);
        }
      }
    });
  }
});

describe('buildAnswerEntry', () => {
  const round = { question: 'QUESTION_TEXT', labels: ['Q1', 'Q2', 'D1'], reply: 'REPLY_TEXT' };
  test('keeps shown order once each when the revise repeats or reorders labels', () => {
    const entry = lib.buildAnswerEntry(round, { settled: ['D1', 'Q1', 'D1', 'Q1'] });
    assert.deepEqual([...entry.settled], ['Q1', 'D1']);
  });
  test('drops a label the round did not show', () => {
    const entry = lib.buildAnswerEntry(round, { settled: ['Q2', 'Q7', 'D3'] });
    assert.deepEqual([...entry.settled], ['Q2']);
  });
  test('an undefined revise settles nothing', () => {
    assert.deepEqual([...lib.buildAnswerEntry(round, undefined).settled], []);
  });
  test('a round that showed no labels settles nothing, even with a revise', () => {
    const emptyRound = { question: 'QUESTION_TEXT', labels: [], reply: 'REPLY_TEXT' };
    assert.deepEqual([...lib.buildAnswerEntry(emptyRound, { settled: ['Q1', 'D1'] }).settled], []);
  });
  test('copies question and reply unchanged, keys in order question, settled, reply', () => {
    const entry = lib.buildAnswerEntry(round, { settled: ['Q1'] });
    assert.deepEqual(Object.keys(entry), ['question', 'settled', 'reply']);
    assert.equal(entry.question, 'QUESTION_TEXT');
    assert.equal(entry.reply, 'REPLY_TEXT');
  });
  test('argument checks', () => {
    assert.throws(() => lib.buildAnswerEntry({ question: 'Q', reply: 'R' }, undefined), /buildAnswerEntry: round.labels must be an array/);
    assert.throws(() => lib.buildAnswerEntry(undefined, undefined), /buildAnswerEntry: round.labels must be an array/);
    assert.throws(() => lib.buildAnswerEntry(round, {}), /buildAnswerEntry: revise.settled must be an array/);
    assert.throws(() => lib.buildAnswerEntry(round, null), /buildAnswerEntry: revise.settled must be an array/);
  });
});

const ANSWER_ENTRY_PATH = 'plugin/workflow-src/lib/brief.js';
const ANSWER_ENTRY_FUNCTION = 'function buildAnswerEntry(';

function findFunctionBodyRange(code, opener) {
  const start = code.indexOf(opener);
  if (start === -1) {
    return undefined;
  }
  let depth = 0;
  for (let index = code.indexOf('{', start); index < code.length; index += 1) {
    depth += code[index] === '{' ? 1 : code[index] === '}' ? -1 : 0;
    if (depth === 0) {
      return { start: start, end: index + 1 };
    }
  }
  return undefined;
}

function checkSettledKeys(path, code, violations) {
  const offsets = [...code.matchAll(/\bsettled\s*:/g)].map((match) => match.index);
  if (path !== ANSWER_ENTRY_PATH) {
    offsets.forEach(() => violations.push(`${path}: settled key outside ${ANSWER_ENTRY_PATH}`));
    return;
  }
  if (offsets.length !== 1) {
    violations.push(`${path}: ${offsets.length} settled keys, expected exactly 1`);
  }
  const body = findFunctionBodyRange(code, ANSWER_ENTRY_FUNCTION);
  if (body === undefined) {
    violations.push(`${path}: no ${ANSWER_ENTRY_FUNCTION}`);
    return;
  }
  offsets.filter((offset) => offset < body.start || offset >= body.end)
    .forEach(() => violations.push(`${path}: settled key outside buildAnswerEntry`));
}

function checkAnswerLogPushes(path, code, violations) {
  const offsets = [...code.matchAll(/answerLog\.push\(/g)].map((match) => match.index + match[0].length);
  offsets.filter((offset) => !/^\s*buildAnswerEntry\(/.test(code.slice(offset)))
    .forEach(() => violations.push(`${path}: answerLog.push not directly followed by buildAnswerEntry(`));
  return offsets.length;
}

/**
 * Checks sources, a list of { path, source }, after stripping comments and
 * literals: a settled key appears only once, inside buildAnswerEntry of
 * brief.js, and every answerLog.push( is directly followed by
 * buildAnswerEntry(. Returns { violations, pushSites, settledFileSeen }.
 */
function findAnswerLogViolations(sources) {
  const violations = [];
  let pushSites = 0;
  for (const { path, source } of sources) {
    const code = stripCommentsAndStrings(source);
    checkSettledKeys(path, code, violations);
    pushSites += checkAnswerLogPushes(path, code, violations);
  }
  const settledFileSeen = sources.some((entry) => entry.path === ANSWER_ENTRY_PATH);
  if (!settledFileSeen) {
    violations.push(`${ANSWER_ENTRY_PATH} not among the sources`);
  }
  return { violations: violations, pushSites: pushSites, settledFileSeen: settledFileSeen };
}

const META_PREFIX = 'export const meta = {';

function readScriptSource(path) {
  const source = readFileSync(repoRoot + path, 'utf8').replace(/\r/g, '');
  if (!path.endsWith('/meta.js')) {
    return source;
  }
  assert.ok(source.startsWith(META_PREFIX), `${path} must start with ${META_PREFIX}`);
  return source.slice('export '.length);
}

function readWorkflowSources(id) {
  return listSourcePaths(repoRoot, id)
    .filter((path) => path.startsWith('plugin/workflow-src/'))
    .map((path) => ({ path: path, source: readScriptSource(path) }));
}

describe('buildAnswerEntry is the one writer of settled', () => {
  for (const id of ['analysis-only', 'standard-delivery']) {
    test(`${id} sources write settled only in buildAnswerEntry and push only its entries`, () => {
      const sources = readWorkflowSources(id);
      assert.ok(sources.length > 0, `${id} has no workflow-src paths`);
      const result = findAnswerLogViolations(sources);
      assert.equal(result.settledFileSeen, true);
      assert.ok(result.pushSites >= 1, `${id} has no answerLog.push site`);
      assert.deepEqual(result.violations, []);
    });
  }
  const briefSource = 'function buildAnswerEntry(round, revise) {\n  return { question: round.question, settled: [], reply: round.reply };\n}\n';
  const goodPush = { path: 'plugin/workflow-src/x/main.js', source: 'answerLog.push(buildAnswerEntry(round, undefined));\n' };
  const goodBrief = { path: ANSWER_ENTRY_PATH, source: briefSource };
  test('a clean fixture passes, and settled in a comment or string is ignored', () => {
    const quiet = { path: 'plugin/workflow-src/x/plan.js', source: '// settled: x\nconst text = "settled: y";\n' };
    const result = findAnswerLogViolations([goodBrief, goodPush, quiet]);
    assert.deepEqual(result.violations, []);
    assert.equal(result.pushSites, 1);
  });
  test('a settled key in another file bites', () => {
    const stray = { path: 'plugin/workflow-src/x/gates.js', source: 'const entry = { settled: [] };\n' };
    assert.match(findAnswerLogViolations([goodBrief, goodPush, stray]).violations.join('\n'), /gates\.js: settled key outside/);
  });
  test('a second settled key in brief.js bites', () => {
    const twice = { path: ANSWER_ENTRY_PATH, source: briefSource + 'function other() {\n  return { settled: [] };\n}\n' };
    const violations = findAnswerLogViolations([twice, goodPush]).violations.join('\n');
    assert.match(violations, /2 settled keys, expected exactly 1/);
    assert.match(violations, /settled key outside buildAnswerEntry/);
  });
  test('the one settled key outside buildAnswerEntry bites', () => {
    const moved = { path: ANSWER_ENTRY_PATH, source: 'function buildAnswerEntry(round) {\n  return round;\n}\nfunction other() {\n  return { settled: [] };\n}\n' };
    assert.match(findAnswerLogViolations([moved, goodPush]).violations.join('\n'), /settled key outside buildAnswerEntry/);
  });
  test('an answerLog.push of a bare object bites', () => {
    const bare = { path: 'plugin/workflow-src/x/plan.js', source: 'run.answerLog.push({ question: q, reply: r });\n' };
    const result = findAnswerLogViolations([goodBrief, bare]);
    assert.equal(result.pushSites, 1);
    assert.match(result.violations.join('\n'), /plan\.js: answerLog\.push not directly followed by buildAnswerEntry\(/);
  });
  test('a missing brief.js bites', () => {
    assert.match(findAnswerLogViolations([goodPush]).violations.join('\n'), /lib\/brief\.js not among the sources/);
  });
});
