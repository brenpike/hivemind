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

describe('argument checks', () => {
  test('renderQuestions needs at least one ask', () => {
    assert.throws(() => lib.renderQuestions([], []), /asks must be a non-empty array/);
    assert.throws(() => lib.renderQuestions(undefined, []), /asks must be a non-empty array/);
  });
  test('taken must be an array', () => {
    assert.throws(() => lib.renderQuestions([{ brief: makeBrief(), reason: 'hard_stop' }], null), /taken must be an array/);
    assert.throws(() => lib.renderDecisions(undefined), /taken must be an array/);
  });
});

describe('result contract', () => {
  const decisions = [{ kind: 'plan_acceptance', option_id: 'A' }];
  test('pauseForUser returns the pause shape', () => {
    const paused = structuredClone(lib.pauseForUser({ answerKey: 'answer_1', message: 'Q?', resumeArgs: { pauses: 1 }, decisions }));
    assert.deepEqual(paused, { needs_user: true, answer_key: 'answer_1', message: 'Q?', resume_args: { pauses: 1 }, decisions });
  });
  test('finish returns the finish shape for both outcomes', () => {
    for (const outcome of ['complete', 'blocked']) {
      const finished = structuredClone(lib.finish({ outcome, message: 'Done.', decisions }));
      assert.deepEqual(finished, { needs_user: false, outcome, message: 'Done.', decisions });
    }
  });
  test('resultFields covers exactly the fields both shapes use', () => {
    const paused = lib.pauseForUser({ answerKey: 'a', message: 'm', resumeArgs: {}, decisions: [] });
    const finished = lib.finish({ outcome: 'complete', message: 'm', decisions: [] });
    const used = new Set([...Object.keys(paused), ...Object.keys(finished)]);
    assert.deepEqual([...lib.resultFields()].sort(), [...used].sort());
  });
  test('a run pauses at most three times', () => {
    assert.equal(lib.pauseLimit(), 3);
    assert.deepEqual([0, 1, 2, 3, 4].map((count) => lib.canPause(count)), [true, true, true, false, false]);
    assert.throws(() => lib.canPause(-1), /non-negative integer/);
    assert.throws(() => lib.canPause('1'), /non-negative integer/);
  });
  test('invalid pause input throws', () => {
    const valid = { answerKey: 'answer_1', message: 'Q?', resumeArgs: {}, decisions: [] };
    assert.throws(() => lib.pauseForUser({ ...valid, answerKey: '' }), /answerKey/);
    assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs: [] }), /resumeArgs must be a plain object/);
    assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs: { answer_1: 'old' } }), /already has answerKey/);
    assert.throws(() => lib.pauseForUser({ ...valid, message: ' ' }), /message/);
    assert.throws(() => lib.pauseForUser({ ...valid, decisions: null }), /decisions/);
  });
  test('invalid finish input throws', () => {
    assert.throws(() => lib.finish({ outcome: 'paused', message: 'm', decisions: [] }), /outcome must be complete or blocked/);
    assert.throws(() => lib.finish({ outcome: 'complete', message: '', decisions: [] }), /message/);
  });
});
