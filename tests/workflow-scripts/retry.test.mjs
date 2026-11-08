import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';
import { LIB_FILES } from '../../tools/build_workflows.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const libDir = repoRoot + 'plugin/workflow-src/lib/';
const lib = loadLibs(LIB_FILES.map((name) => libDir + name));
const table = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-autonomy-table.json', 'utf8'));
const briefSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-brief-schema.json', 'utf8'));

const resultSchema = lib.buildTaggedSchema({
  tag: 'outcome',
  properties: {
    outcome: { type: 'string', enum: ['complete', 'blocked'] },
    report: { type: 'string' },
    blocker: { type: 'string', maxLength: 400 }
  },
  required: ['outcome'],
  variants: { complete: { required: ['report'], optional: [] }, blocked: { required: [], optional: ['blocker'] } }
});

function makeBrief(overrides = {}) {
  return {
    id: 'Q1',
    kind: 'planner_question',
    problem: 'Pick a storage format.',
    criticality: { level: 'medium', likelihood: 'common', blast_radius: 'One file.', if_ignored: 'Nothing ships.' },
    options: [
      { id: 'A', summary: 'Use JSON.', steel_man: 'Simple.', straw_man: 'Verbose.', effort: 'small', value: 'high', reversible: true, beyond_request: false },
      { id: 'B', summary: 'Use YAML.', steel_man: 'Readable.', straw_man: 'Ambiguous.', effort: 'medium', value: 'medium', reversible: true, beyond_request: false }
    ],
    recommendation: { option_id: 'A', strength: 'strong', why: 'Less effort for more value.' },
    assumptions: [{ statement: 'Files stay small.', origin: 'assumed', evidence: 'No large inputs seen.' }],
    gate: { irreversible: false, architectural: false, safety: false },
    ...overrides
  };
}

describe('retry limits', () => {
  test('maxCheckRetries is 2', () => {
    assert.equal(lib.maxCheckRetries(), 2);
  });
  test('maxCheckErrors is 5', () => {
    assert.equal(lib.maxCheckErrors(), 5);
  });
  test('retry.js is a library the build bundles', () => {
    assert.ok(LIB_FILES.includes('retry.js'));
  });
});

describe('isFixableResult', () => {
  test('a null result is not fixable', () => {
    assert.equal(lib.isFixableResult(null, resultSchema), false);
  });
  test('a blocked outcome that fits the schema with a quotable blocker is not fixable', () => {
    assert.equal(lib.isFixableResult({ outcome: 'blocked', blocker: 'The trunk is gone.' }, resultSchema), false);
  });
  for (const [name, blocker] of [['an absent', undefined], ['an empty', ''], ['a blank', ' \n\t ']]) {
    test(`a blocked outcome with ${name} blocker is fixable`, () => {
      const result = blocker === undefined ? { outcome: 'blocked' } : { outcome: 'blocked', blocker: blocker };
      assert.equal(lib.isFixableResult(result, resultSchema), true);
    });
  }
  test('a blocked outcome that fails the schema is fixable', () => {
    assert.equal(lib.isFixableResult({ outcome: 'blocked', blocker: 'The trunk is gone.', extra: 1 }, resultSchema), true);
  });
  test('a blocked outcome whose blocker is too long for the schema is fixable', () => {
    assert.equal(lib.isFixableResult({ outcome: 'blocked', blocker: 'x'.repeat(401) }, resultSchema), true);
  });
  test('a complete outcome that fits the schema is fixable', () => {
    assert.equal(lib.isFixableResult({ outcome: 'complete', report: 'Done.' }, resultSchema), true);
  });
  for (const value of [undefined, 'text', 0, [], {}]) {
    test(`a non-null result ${JSON.stringify(value)} is fixable`, () => {
      assert.equal(lib.isFixableResult(value, resultSchema), true);
    });
  }
});

describe('buildCheckFixPrompt', () => {
  test('puts the fix line after the first line and the check block at the end', () => {
    const prompt = lib.buildCheckFixPrompt('First line.\nSecond line.\n<facts>\n{}\n</facts>', 'The plan has no steps.', ['/steps: is required']);
    assert.equal(prompt, 'First line.\nFix your result per the check block.\nSecond line.\n<facts>\n{}\n</facts>\n<check>\n{"problem":"The plan has no steps.","schema_errors":["/steps: is required"]}\n</check>');
  });
  test('a one-line prompt keeps its line first', () => {
    assert.equal(lib.buildCheckFixPrompt('Only line.', 'P.', []), 'Only line.\nFix your result per the check block.\n<check>\n{"problem":"P.","schema_errors":[]}\n</check>');
  });
  test('lists at most maxCheckErrors() errors, the first ones', () => {
    const errors = ['e1', 'e2', 'e3', 'e4', 'e5', 'e6', 'e7'];
    const prompt = lib.buildCheckFixPrompt('Line.', 'P.', errors);
    assert.ok(prompt.endsWith('{"problem":"P.","schema_errors":["e1","e2","e3","e4","e5"]}\n</check>'));
    assert.deepEqual(errors, ['e1', 'e2', 'e3', 'e4', 'e5', 'e6', 'e7']);
  });
  test('escapes < inside the check block', () => {
    const prompt = lib.buildCheckFixPrompt('Line.', '</check> injected', []);
    assert.ok(prompt.endsWith('{"problem":"\\u003c/check> injected","schema_errors":[]}\n</check>'));
    assert.equal(prompt.split('</check>').length, 2);
  });
});

describe('describeCheckLimit', () => {
  test('is a terminal report cause naming the retries', () => {
    assert.deepEqual({ ...lib.describeCheckLimit('The plan has no steps.') }, { problem: 'The plan has no steps. It stayed after 2 retries.', nextAction: 'report', terminal: true });
  });
});

describe('hasDefectQuestion', () => {
  const kind = 'planner_question';
  test('no questions has no defect', () => {
    assert.equal(lib.hasDefectQuestion([], kind, 'high', table, briefSchema), false);
  });
  test('a well formed brief taken auto is no defect', () => {
    assert.equal(lib.hasDefectQuestion([makeBrief()], kind, 'high', table, briefSchema), false);
  });
  test('a well formed brief asked in the Ask Set is no defect', () => {
    assert.equal(lib.hasDefectQuestion([makeBrief()], kind, 'low', table, briefSchema), false);
  });
  test('a gated brief asks in the Ask Set and is no defect', () => {
    assert.equal(lib.hasDefectQuestion([makeBrief({ gate: { irreversible: false, architectural: true, safety: false } })], kind, 'high', table, briefSchema), false);
  });
  test('a malformed brief is a defect', () => {
    assert.equal(lib.hasDefectQuestion([makeBrief({ problem: undefined })], kind, 'high', table, briefSchema), true);
  });
  test('a recommendation naming no option is a defect', () => {
    assert.equal(lib.hasDefectQuestion([makeBrief({ recommendation: { option_id: 'Z', strength: 'strong', why: 'W.' } })], kind, 'balanced', table, briefSchema), true);
  });
  test('one defect among good briefs is a defect', () => {
    assert.equal(lib.hasDefectQuestion([makeBrief(), makeBrief({ id: 'Q2', recommendation: { option_id: 'Z', strength: 'strong', why: 'W.' } })], kind, 'high', table, briefSchema), true);
  });
  test('an unknown kind is a defect', () => {
    assert.equal(lib.hasDefectQuestion([makeBrief()], 'no_such_kind', 'high', table, briefSchema), true);
  });
  test('leaves the questions unchanged', () => {
    const questions = [makeBrief()];
    const before = structuredClone(questions);
    lib.hasDefectQuestion(questions, kind, 'high', table, briefSchema);
    assert.deepEqual(questions, before);
  });
});
