import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const libDir = repoRoot + 'plugin/workflow-src/lib/';
const libPaths = ['schema.js', 'decide.js', 'brief.js', 'result.js'].map((name) => libDir + name);
const table = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-autonomy-table.json', 'utf8'));
const briefSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-brief-schema.json', 'utf8'));
const lib = loadLibs([libDir + 'schema.js', libDir + 'decide.js']);

function makeBrief(overrides = {}) {
  return {
    id: 'Q1',
    kind: 'plan_acceptance',
    problem: 'Pick a storage format.',
    criticality: { level: 'medium', likelihood: 'common', blast_radius: 'One file.', if_ignored: 'Nothing ships.' },
    options: [
      { id: 'A', summary: 'Use JSON.', steel_man: 'Simple.', straw_man: 'Verbose.', effort: 'small', value: 'high', reversible: true },
      { id: 'B', summary: 'Use YAML.', steel_man: 'Readable.', straw_man: 'Ambiguous.', effort: 'medium', value: 'medium', reversible: true }
    ],
    recommendation: { option_id: 'A', strength: 'strong', why: 'Less effort for more value.' },
    assumptions: [{ statement: 'Files stay small.', origin: 'assumed', evidence: 'No large inputs seen.' }],
    gate: { irreversible: false, architectural: false, safety: false },
    ...overrides
  };
}

function decideWith(kind, level, brief, decisionTable = table) {
  return structuredClone(lib.decide({ kind, level, brief }, decisionTable, briefSchema));
}

const takeAuto = { action: 'take', reason: 'auto' };
const hardStopKinds = table.hard_stops.map((stop) => stop.hard_stop);
const autoRow = table.rows.find((row) => row.kind === 'plan_acceptance');

describe('resolveLevel', () => {
  for (const absent of [undefined, null, '']) {
    test(`absent level ${JSON.stringify(absent)} resolves to default_level`, () => {
      assert.equal(lib.resolveLevel(absent, table), table.default_level);
    });
  }
  for (const level of table.levels) {
    test(`valid level ${level} resolves to itself`, () => {
      assert.equal(lib.resolveLevel(level, table), level);
    });
  }
  for (const invalid of ['max', 'HIGH', ' high', 0, 3, false, {}, []]) {
    test(`invalid level ${JSON.stringify(invalid)} resolves to low`, () => {
      assert.equal(lib.resolveLevel(invalid, table), 'low');
    });
  }
});

describe('every row at every level of the real table', () => {
  for (const row of table.rows) {
    for (const level of table.levels) {
      test(`${row.kind} at ${level} is ${row[level]}`, () => {
        const expected = row[level] === 'auto' ? takeAuto : { action: 'ask', reason: 'table_surface' };
        assert.deepEqual(decideWith(row.kind, level, makeBrief()), expected);
      });
    }
  }
});

describe('every hard stop at every level', () => {
  for (const kind of hardStopKinds) {
    for (const level of [...table.levels, undefined, 'bogus']) {
      test(`${kind} at ${JSON.stringify(level)} asks hard_stop`, () => {
        assert.deepEqual(decideWith(kind, level, makeBrief()), { action: 'ask', reason: 'hard_stop' });
      });
    }
  }
  test('a hard stop asks hard_stop even with a malformed brief', () => {
    assert.deepEqual(decideWith(hardStopKinds[0], 'high', null), { action: 'ask', reason: 'hard_stop' });
  });
});

describe('levels', () => {
  test('absent level uses default_level', () => {
    const kind = table.rows.find((row) => row[table.default_level] !== row.low).kind;
    const expectedAtDefault = decideWith(kind, table.default_level, makeBrief());
    assert.deepEqual(decideWith(kind, undefined, makeBrief()), expectedAtDefault);
    assert.deepEqual(decideWith(kind, null, makeBrief()), expectedAtDefault);
    assert.deepEqual(decideWith(kind, '', makeBrief()), expectedAtDefault);
  });
  test('invalid level is treated as low and asks', () => {
    assert.equal(autoRow.high, 'auto');
    assert.equal(autoRow.low, 'surface');
    assert.deepEqual(decideWith('plan_acceptance', 'max', makeBrief()), { action: 'ask', reason: 'table_surface' });
  });
  test('valid level is used as given', () => {
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief()), takeAuto);
    assert.deepEqual(decideWith('plan_acceptance', 'low', makeBrief()), { action: 'ask', reason: 'table_surface' });
  });
});

describe('gate flags', () => {
  for (const flag of ['irreversible', 'architectural', 'safety']) {
    test(`gate.${flag} asks gate_${flag}`, () => {
      const gate = { irreversible: false, architectural: false, safety: false, [flag]: true };
      assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ gate })), { action: 'ask', reason: `gate_${flag}` });
    });
  }
  test('gate flags are checked in order irreversible, architectural, safety', () => {
    const all = { irreversible: true, architectural: true, safety: true };
    assert.equal(decideWith('plan_acceptance', 'high', makeBrief({ gate: all })).reason, 'gate_irreversible');
    const lastTwo = { irreversible: false, architectural: true, safety: true };
    assert.equal(decideWith('plan_acceptance', 'high', makeBrief({ gate: lastTwo })).reason, 'gate_architectural');
  });
  test('a recommended option with reversible false asks gate_irreversible even when gate.irreversible is false', () => {
    const base = makeBrief();
    const options = [{ ...base.options[0], reversible: false }, base.options[1]];
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ options })), { action: 'ask', reason: 'gate_irreversible' });
  });
  test('an option with reversible false that is not recommended does not make it ask', () => {
    const base = makeBrief();
    const options = [base.options[0], { ...base.options[1], reversible: false }];
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ options })), takeAuto);
  });
  test('table_surface wins over a gate flag', () => {
    const gate = { irreversible: true, architectural: false, safety: false };
    assert.equal(decideWith('plan_acceptance', 'low', makeBrief({ gate })).reason, 'table_surface');
  });
});

describe('recommendation', () => {
  test('strength none asks no_recommendation', () => {
    const recommendation = { option_id: '', strength: 'none', why: 'Both are fine.' };
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ recommendation })), { action: 'ask', reason: 'no_recommendation' });
  });
  test('a gate flag wins over strength none', () => {
    const recommendation = { option_id: '', strength: 'none', why: 'Both are fine.' };
    const gate = { irreversible: false, architectural: false, safety: true };
    assert.equal(decideWith('plan_acceptance', 'high', makeBrief({ recommendation, gate })).reason, 'gate_safety');
  });
  test('a weak recommendation is taken', () => {
    const recommendation = { option_id: 'B', strength: 'weak', why: 'Slight edge.' };
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ recommendation })), takeAuto);
  });
  test('option_id not among the options asks recommendation_not_an_option', () => {
    const recommendation = { option_id: 'C', strength: 'strong', why: 'Best.' };
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ recommendation })), { action: 'ask', reason: 'recommendation_not_an_option' });
  });
  test('duplicate option ids ask recommendation_not_an_option', () => {
    const base = makeBrief();
    const options = [base.options[0], { ...base.options[1], id: 'A' }];
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ options })), { action: 'ask', reason: 'recommendation_not_an_option' });
  });
  test('strength none wins over an option mismatch', () => {
    const recommendation = { option_id: 'Z', strength: 'none', why: 'Unsure.' };
    assert.equal(decideWith('plan_acceptance', 'high', makeBrief({ recommendation })).reason, 'no_recommendation');
  });
});

describe('criticality never asks', () => {
  for (const level of ['low', 'medium', 'high', 'critical']) {
    for (const likelihood of ['edge_case', 'occasional', 'common', 'certain']) {
      test(`criticality ${level} with likelihood ${likelihood} is taken`, () => {
        const criticality = { level, likelihood, blast_radius: 'Everything.', if_ignored: 'Outage.' };
        assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ criticality })), takeAuto);
      });
    }
  }
});

describe('unknown kind', () => {
  for (const kind of ['not_a_kind', '', undefined, null, 'rows', 'levels']) {
    test(`kind ${JSON.stringify(kind)} asks unknown_kind`, () => {
      assert.deepEqual(decideWith(kind, 'high', makeBrief()), { action: 'ask', reason: 'unknown_kind' });
    });
  }
  test('malformed_brief wins over unknown_kind', () => {
    assert.equal(decideWith('not_a_kind', 'high', {}).reason, 'malformed_brief');
  });
});

describe('bad cell', () => {
  for (const cell of ['maybe', 'AUTO', undefined, true]) {
    test(`cell ${JSON.stringify(cell)} asks bad_cell`, () => {
      const row = { kind: 'synthetic', high: cell, balanced: 'auto', low: 'surface' };
      const syntheticTable = { ...table, rows: [row] };
      assert.deepEqual(decideWith('synthetic', 'high', makeBrief(), syntheticTable), { action: 'ask', reason: 'bad_cell' });
    });
  }
  test('an invalid default_level asks bad_cell for an absent level', () => {
    const syntheticTable = { ...table, default_level: 'nowhere' };
    assert.deepEqual(decideWith('plan_acceptance', undefined, makeBrief(), syntheticTable), { action: 'ask', reason: 'bad_cell' });
  });
});

describe('malformed brief', () => {
  const base = makeBrief();
  const malformed = {
    'null brief': null,
    'undefined brief': undefined,
    'array brief': [],
    'string brief': 'brief',
    'missing problem': makeBrief({ problem: undefined }),
    'non-string problem': makeBrief({ problem: 42 }),
    'missing criticality': makeBrief({ criticality: undefined }),
    'criticality missing if_ignored': makeBrief({ criticality: { ...base.criticality, if_ignored: undefined } }),
    'options not an array': makeBrief({ options: { A: base.options[0] } }),
    'empty options': makeBrief({ options: [] }),
    'option missing steel_man': makeBrief({ options: [{ ...base.options[0], steel_man: undefined }] }),
    'option reversible not boolean': makeBrief({ options: [{ ...base.options[0], reversible: 'yes' }] }),
    'option is null': makeBrief({ options: [null] }),
    'missing recommendation': makeBrief({ recommendation: undefined }),
    'recommendation missing why': makeBrief({ recommendation: { option_id: 'A', strength: 'strong' } }),
    'strength outside enum': makeBrief({ recommendation: { option_id: 'A', strength: 'Strong', why: 'x' } }),
    'assumptions not an array': makeBrief({ assumptions: 'none' }),
    'assumption origin outside enum': makeBrief({ assumptions: [{ statement: 's', origin: 'guess', evidence: 'e' }] }),
    'assumption missing evidence': makeBrief({ assumptions: [{ statement: 's', origin: 'repo' }] }),
    'missing gate': makeBrief({ gate: undefined }),
    'gate flag not boolean': makeBrief({ gate: { irreversible: 'false', architectural: false, safety: false } }),
    'gate missing safety': makeBrief({ gate: { irreversible: false, architectural: false } }),
    'verbatim not a string': makeBrief({ verbatim: 7 }),
    'missing id': makeBrief({ id: undefined }),
    'missing kind': makeBrief({ kind: undefined }),
    'kind not a string': makeBrief({ kind: 3 }),
    'extra top-level key': makeBrief({ score: 9 }),
    'extra option key': makeBrief({ options: [{ ...base.options[0], cost: 'low' }] }),
    'extra gate key': makeBrief({ gate: { ...base.gate, legal: false } }),
    'criticality level outside enum': makeBrief({ criticality: { ...base.criticality, level: 'severe' } }),
    'criticality likelihood outside enum': makeBrief({ criticality: { ...base.criticality, likelihood: 'rare' } }),
    'option effort outside enum': makeBrief({ options: [{ ...base.options[0], effort: 'huge' }] }),
    'option value outside enum': makeBrief({ options: [{ ...base.options[0], value: 'none' }] }),
    'ruled_out not an array': makeBrief({ ruled_out: 'none' }),
    'ruled_out entry missing why': makeBrief({ ruled_out: [{ summary: 'Use XML.' }] })
  };
  for (const [name, brief] of Object.entries(malformed)) {
    test(`${name} asks malformed_brief`, () => {
      assert.deepEqual(decideWith('plan_acceptance', 'high', brief), { action: 'ask', reason: 'malformed_brief' });
    });
  }
  test('optional fields may be present', () => {
    const brief = makeBrief({ verbatim: 'Shown as is.', ruled_out: [{ summary: 'Use XML.', why: 'Too heavy.' }] });
    assert.deepEqual(decideWith('plan_acceptance', 'high', brief), takeAuto);
  });
  test('optional fields may be absent', () => {
    const brief = makeBrief();
    delete brief.verbatim;
    delete brief.ruled_out;
    assert.deepEqual(decideWith('plan_acceptance', 'high', brief), takeAuto);
  });
  test('empty assumptions are well formed', () => {
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ assumptions: [] })), takeAuto);
  });
});

describe('brief.kind never picks the rule', () => {
  test('a kind that names no table kind is taken', () => {
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ kind: 'not_a_kind', id: 'ZZ' })), takeAuto);
  });
  test('a hard stop named in brief.kind does not make it ask', () => {
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ kind: hardStopKinds[0] })), takeAuto);
  });
  test('an auto kind named in brief.kind does not make a surface kind take', () => {
    const decision = decideWith('remediation_plan_acceptance', 'high', makeBrief({ kind: 'plan_acceptance' }));
    assert.deepEqual(decision, { action: 'ask', reason: 'table_surface' });
  });
});

describe('the schema is a parameter', () => {
  test('decide without a schema throws, even for a hard stop', () => {
    assert.throws(() => lib.decide({ kind: 'plan_acceptance', level: 'high', brief: makeBrief() }, table), /validateSchema: \$: schema must be an object/);
    assert.throws(() => lib.decide({ kind: hardStopKinds[0], level: 'high', brief: makeBrief() }, table), /schema must be an object/);
  });
  test('decide with a schema keyword validateSchema does not support throws', () => {
    const schema = { ...briefSchema, properties: { ...briefSchema.properties, problem: { type: 'string', minLength: 1 } } };
    assert.throws(() => lib.decide({ kind: 'plan_acceptance', level: 'high', brief: makeBrief() }, table, schema), /unsupported keyword minLength/);
  });
  test('the brief check follows the schema given, not a copy', () => {
    const required = [...briefSchema.required, 'owner'];
    const properties = { ...briefSchema.properties, owner: { type: 'string' } };
    const schema = { ...briefSchema, required, properties };
    const decision = structuredClone(lib.decide({ kind: 'plan_acceptance', level: 'high', brief: makeBrief() }, table, schema));
    assert.deepEqual(decision, { action: 'ask', reason: 'malformed_brief' });
    const withOwner = structuredClone(lib.decide({ kind: 'plan_acceptance', level: 'high', brief: makeBrief({ owner: 'me' }) }, table, schema));
    assert.deepEqual(withOwner, takeAuto);
  });
});

describe('decisionReasons', () => {
  test('lists every reason in check order, ending with auto', () => {
    assert.deepEqual(structuredClone(lib.decisionReasons()), [
      'hard_stop', 'malformed_brief', 'unknown_kind', 'table_surface', 'bad_cell',
      'gate_irreversible', 'gate_architectural', 'gate_safety',
      'no_recommendation', 'recommendation_not_an_option', 'auto'
    ]);
  });
});

describe('lib sources are plain workflow scripts', () => {
  for (const path of libPaths) {
    const name = path.slice(libDir.length);
    const source = readFileSync(path, 'utf8').replace(/\r/g, '');
    test(`${name} has no module syntax, clock, randomness, em dash or hash-digit`, () => {
      assert.doesNotMatch(source, /\bimport\b|\bexport\b|\brequire\b/);
      assert.doesNotMatch(source, /\bDate\b/);
      assert.doesNotMatch(source, /Math\.random/);
      assert.doesNotMatch(source, /\u2014/);
      assert.doesNotMatch(source, /#\d/);
    });
    test(`${name} opens with a contract header`, () => {
      assert.match(source, /^\/\*\n \* [a-z]+\.js: [\s\S]*?\n \* Inputs\n[\s\S]*?\n \* Outputs\n[\s\S]*?\n \* Invariants\n[\s\S]*?\n \* Why\n[\s\S]*?\*\//);
    });
    test(`${name} declares only top-level functions`, () => {
      assert.doesNotMatch(source, /^(const|let|var|class)\s/m);
      const context = vm.createContext({});
      const before = new Set(Object.keys(context));
      vm.runInContext(source, context);
      const added = Object.keys(context).filter((key) => !before.has(key));
      assert.ok(added.length > 0);
      for (const key of added) {
        assert.equal(typeof context[key], 'function', `${key} is not a function`);
      }
    });
  }
  test('no top-level function name is declared in two libs', () => {
    const seen = new Map();
    for (const path of libPaths) {
      const source = readFileSync(path, 'utf8');
      for (const match of source.matchAll(/^function\s+([A-Za-z0-9_]+)/gm)) {
        assert.equal(seen.has(match[1]), false, `${match[1]} is declared in ${seen.get(match[1])} and ${path}`);
        seen.set(match[1], path);
      }
    }
  });
});

describe('harness context mirrors the Workflow runtime', () => {
  const context = loadLibs(libPaths);
  for (const expression of ['Date.now()', 'Math.random()', 'new Date()', 'Date()']) {
    test(`${expression} throws`, () => {
      assert.throws(() => vm.runInContext(expression, context), /throws inside a workflow script/);
    });
  }
  test('new Date with an argument still works', () => {
    assert.equal(vm.runInContext('new Date(0).toISOString()', context), '1970-01-01T00:00:00.000Z');
    assert.equal(vm.runInContext('new Date(0) instanceof Date', context), true);
  });
  test('module loading is not available', () => {
    assert.equal(vm.runInContext('typeof require', context), 'undefined');
  });
});
