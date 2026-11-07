import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { loadLibs } from './harness.mjs';
import { LIB_FILES } from '../../tools/build_workflows.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const libDir = repoRoot + 'plugin/workflow-src/lib/';
const libPaths = LIB_FILES.map((name) => libDir + name);
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
      { id: 'A', summary: 'Use JSON.', steel_man: 'Simple.', straw_man: 'Verbose.', effort: 'small', value: 'high', reversible: true, beyond_request: false },
      { id: 'B', summary: 'Use YAML.', steel_man: 'Readable.', straw_man: 'Ambiguous.', effort: 'medium', value: 'medium', reversible: true, beyond_request: false }
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

function decideListing(kind, level, brief, listed, decisionTable = table) {
  return structuredClone(lib.decide({ kind, level, brief, listed }, decisionTable, briefSchema));
}

const takeAuto = { action: 'take', reason: 'auto', listed: [] };
const askSet = ['hard_stop', 'table_surface', 'gate_irreversible', 'gate_architectural', 'gate_safety', 'no_recommendation'];
const listSet = ['beyond_request', 'outside_limits', 'repeats_surface'];
const callerListSet = ['outside_limits', 'repeats_surface'];

function resolvedLevelOf(level) {
  return level === undefined ? table.default_level : level;
}
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
  test('a recommended option with a destructive change asks gate_safety at every level and kind, even when gate.safety is false', () => {
    const base = makeBrief();
    const options = [{ ...base.options[0], destructive: [{ category: 3, item: 'Skip test X.' }] }, base.options[1]];
    const brief = makeBrief({ options });
    for (const kind of [...table.rows.map((row) => row.kind), ...hardStopKinds]) {
      for (const level of [...table.levels, undefined]) {
        const verdict = decideWith(kind, level, brief);
        const row = table.rows.find((entry) => entry.kind === kind);
        const expected = row !== undefined && row[resolvedLevelOf(level)] === 'auto' ? 'gate_safety' : verdict.reason;
        assert.deepEqual(verdict, { action: 'ask', reason: expected }, `${kind} at ${level}`);
      }
    }
  });
  for (const kind of ['review_question', 'high_severity_rejection']) {
    test(`review kind ${kind} asks gate_safety for a recommended destructive option where it would take`, () => {
      const base = makeBrief();
      const options = [{ ...base.options[0], destructive: [{ category: 8, item: 'Edit .github/workflows/ci.yml.' }] }, base.options[1]];
      assert.deepEqual(decideWith(kind, 'high', makeBrief()), takeAuto);
      assert.deepEqual(decideWith(kind, 'high', makeBrief({ options })), { action: 'ask', reason: 'gate_safety' });
    });
  }
  test('a destructive option that is not recommended does not block a take', () => {
    const base = makeBrief();
    const options = [base.options[0], { ...base.options[1], destructive: [{ category: 3, item: 'Skip test X.' }] }];
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ options })), takeAuto);
  });
  test('an empty destructive list on the recommended option does not make it ask', () => {
    const base = makeBrief();
    const options = [{ ...base.options[0], destructive: [] }, base.options[1]];
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ options })), takeAuto);
  });
  test('table_surface wins over a gate flag', () => {
    const gate = { irreversible: true, architectural: false, safety: false };
    assert.equal(decideWith('plan_acceptance', 'low', makeBrief({ gate })).reason, 'table_surface');
  });
});

function makeBeyondBrief(beyondIndex, overrides = {}) {
  const base = makeBrief();
  const options = base.options.map((option, index) => ({ ...option, beyond_request: index === beyondIndex }));
  return makeBrief({ options, ...overrides });
}

describe('beyond request', () => {
  const allKinds = [...table.rows.map((row) => row.kind), ...hardStopKinds];
  const beyondTake = { action: 'take', reason: 'auto', listed: ['beyond_request'] };
  for (const effort of ['trivial', 'small']) {
    test(`a strong recommendation of ${effort} effort beyond the request is taken and listed at every auto cell`, () => {
      const brief = makeBeyondBrief(0);
      brief.options[0].effort = effort;
      for (const kind of allKinds) {
        for (const level of [...table.levels, undefined]) {
          const row = table.rows.find((entry) => entry.kind === kind);
          const verdict = decideWith(kind, level, brief);
          if (row !== undefined && row[resolvedLevelOf(level)] === 'auto') {
            assert.deepEqual(verdict, beyondTake, `${kind} at ${level}`);
          } else {
            assert.deepEqual(verdict, decideWith(kind, level, makeBrief()), `${kind} at ${level}`);
          }
        }
      }
    });
  }
  for (const [strength, effort] of [['strong', 'medium'], ['strong', 'large'], ['weak', 'trivial'], ['weak', 'small'], ['weak', 'large'], ['none', 'small']]) {
    test(`a ${strength} recommendation of ${effort} effort beyond the request asks malformed_brief at every level and kind but a hard stop`, () => {
      const brief = makeBeyondBrief(0, { recommendation: { option_id: 'A', strength, why: 'Bigger change.' } });
      brief.options[0].effort = effort;
      for (const kind of allKinds) {
        for (const level of [...table.levels, undefined, 'bogus']) {
          const expected = hardStopKinds.includes(kind) ? 'hard_stop' : 'malformed_brief';
          assert.deepEqual(decideWith(kind, level, brief), { action: 'ask', reason: expected }, `${kind} at ${level}`);
        }
      }
    });
  }
  test('an option with beyond_request true that is not recommended does not make it ask and is not listed', () => {
    const brief = makeBeyondBrief(1);
    brief.options[1].effort = 'large';
    assert.deepEqual(decideWith('plan_acceptance', 'high', brief), takeAuto);
  });
  test('malformed_brief for an unearned expansion wins over every later check', () => {
    const gate = { irreversible: true, architectural: true, safety: true };
    const brief = makeBeyondBrief(0, { gate, recommendation: { option_id: 'A', strength: 'weak', why: 'Bigger.' } });
    assert.equal(decideWith('not_a_kind', 'low', brief).reason, 'malformed_brief');
    assert.equal(decideWith('plan_acceptance', 'high', brief).reason, 'malformed_brief');
  });
  test('every later ask wins over listing an earned expansion', () => {
    const gateWith = (flag) => ({ irreversible: false, architectural: false, safety: false, [flag]: true });
    for (const flag of ['irreversible', 'architectural', 'safety']) {
      assert.deepEqual(decideWith('plan_acceptance', 'high', makeBeyondBrief(0, { gate: gateWith(flag) })), { action: 'ask', reason: `gate_${flag}` });
    }
    assert.deepEqual(decideWith('plan_acceptance', 'low', makeBeyondBrief(0)), { action: 'ask', reason: 'table_surface' });
  });
  test('a brief whose every option goes beyond the request is malformed even for an auto cell', () => {
    const brief = makeBrief({ options: makeBrief().options.map((option) => ({ ...option, beyond_request: true })) });
    for (const level of table.levels) {
      assert.deepEqual(decideWith('plan_acceptance', level, brief), { action: 'ask', reason: 'malformed_brief' }, level);
    }
  });
});

describe('recommendation', () => {
  test('strength none asks no_recommendation', () => {
    const recommendation = { option_id: 'A', strength: 'none', why: 'Both are fine.' };
    assert.deepEqual(decideWith('plan_acceptance', 'high', makeBrief({ recommendation })), { action: 'ask', reason: 'no_recommendation' });
  });
  test('a gate flag wins over strength none', () => {
    const recommendation = { option_id: 'A', strength: 'none', why: 'Both are fine.' };
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
  test('an option mismatch wins over strength none', () => {
    const recommendation = { option_id: 'Z', strength: 'none', why: 'Unsure.' };
    assert.equal(decideWith('plan_acceptance', 'high', makeBrief({ recommendation })).reason, 'recommendation_not_an_option');
  });
  test('recommendation_not_an_option wins over unknown_kind, table_surface, bad_cell and the gates', () => {
    const recommendation = { option_id: 'C', strength: 'strong', why: 'Best.' };
    const gate = { irreversible: true, architectural: true, safety: true };
    const syntheticTable = { ...table, rows: [{ kind: 'synthetic', high: 'maybe', balanced: 'auto', low: 'surface' }] };
    assert.equal(decideWith('not_a_kind', 'high', makeBrief({ recommendation })).reason, 'recommendation_not_an_option');
    assert.equal(decideWith('plan_acceptance', 'low', makeBrief({ recommendation })).reason, 'recommendation_not_an_option');
    assert.equal(decideWith('synthetic', 'high', makeBrief({ recommendation }), syntheticTable).reason, 'recommendation_not_an_option');
    assert.equal(decideWith('plan_acceptance', 'high', makeBrief({ recommendation, gate })).reason, 'recommendation_not_an_option');
  });
  test('hard_stop and malformed_brief win over recommendation_not_an_option', () => {
    const recommendation = { option_id: 'C', strength: 'strong', why: 'Best.' };
    assert.equal(decideWith(hardStopKinds[0], 'high', makeBrief({ recommendation })).reason, 'hard_stop');
    assert.equal(decideWith('plan_acceptance', 'high', makeBrief({ recommendation, problem: '' })).reason, 'malformed_brief');
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
    'ruled_out entry missing why': makeBrief({ ruled_out: [{ summary: 'Use XML.' }] }),
    'blank option id recommended by blank option_id': makeBrief({
      options: [{ ...base.options[0], id: '' }],
      recommendation: { ...base.recommendation, option_id: '' }
    }),
    'whitespace-only problem': makeBrief({ problem: ' \t ' }),
    'whitespace-only option id': makeBrief({ options: [{ ...base.options[0], id: ' ' }, base.options[1]] }),
    'blank option summary': makeBrief({ options: [{ ...base.options[0], summary: '' }, base.options[1]] }),
    'blank recommendation why': makeBrief({ recommendation: { ...base.recommendation, why: '' } }),
    'strength none with blank option_id': makeBrief({ recommendation: { option_id: '', strength: 'none', why: 'Both are fine.' } }),
    'empty verbatim': makeBrief({ verbatim: '' }),
    'destructive category outside 1 to 10': makeBrief({ options: [{ ...base.options[0], destructive: [{ category: 11, item: 'X' }] }] }),
    'destructive entry missing item': makeBrief({ options: [{ ...base.options[0], destructive: [{ category: 3 }] }] }),
    'option missing beyond_request': makeBrief({ options: [{ ...base.options[0], beyond_request: undefined }, base.options[1]] }),
    'option beyond_request not boolean': makeBrief({ options: [{ ...base.options[0], beyond_request: 'false' }, base.options[1]] }),
    'every option beyond_request true': makeBrief({ options: base.options.map((option) => ({ ...option, beyond_request: true })) })
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
    const decision = decideWith('version_bump_indeterminable', 'high', makeBrief({ kind: 'plan_acceptance' }));
    assert.deepEqual(decision, { action: 'ask', reason: 'table_surface' });
  });
});

describe('the schema is a parameter', () => {
  test('decide without a schema throws, even for a hard stop', () => {
    assert.throws(() => lib.decide({ kind: 'plan_acceptance', level: 'high', brief: makeBrief() }, table), /validateSchema: \$: schema must be an object/);
    assert.throws(() => lib.decide({ kind: hardStopKinds[0], level: 'high', brief: makeBrief() }, table), /schema must be an object/);
  });
  test('decide with a schema keyword validateSchema does not support throws', () => {
    const schema = { ...briefSchema, properties: { ...briefSchema.properties, problem: { type: 'string', format: 'email' } } };
    assert.throws(() => lib.decide({ kind: 'plan_acceptance', level: 'high', brief: makeBrief() }, table, schema), /unsupported keyword format/);
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

describe('askReasons and listReasons', () => {
  test('askReasons is the closed Ask Set in check order', () => {
    assert.deepEqual(structuredClone(lib.askReasons()), askSet);
  });
  test('listReasons names every list reason in listing order', () => {
    assert.deepEqual(structuredClone(lib.listReasons()), listSet);
  });
  test('the two sets share no name and neither holds auto', () => {
    for (const name of lib.listReasons()) {
      assert.equal(lib.askReasons().includes(name), false, name);
    }
    assert.equal([...lib.askReasons(), ...lib.listReasons()].includes('auto'), false);
  });
  test('each call returns a new array', () => {
    const asks = lib.askReasons();
    asks.push('beyond_request');
    const lists = lib.listReasons();
    lists.length = 0;
    assert.deepEqual(structuredClone(lib.askReasons()), askSet);
    assert.deepEqual(structuredClone(lib.listReasons()), listSet);
  });
  test('the removed reasons and caller ask input are gone', () => {
    assert.equal(typeof lib.decisionReasons, 'undefined');
    assert.equal(typeof lib.callerAskReasons, 'undefined');
    for (const reason of ['beyond_request', 'outside_limits', 'repeats_surface']) {
      assert.equal(lib.askReasons().includes(reason), false, reason);
    }
  });
});

const recommendedVariants = (() => {
  const variants = [];
  for (const strength of ['strong', 'weak', 'none']) {
    for (const reversible of [true, false]) {
      for (const destructive of [undefined, [], [{ category: 3, item: 'Skip test X.' }]]) {
        for (const beyondRequest of [false, true]) {
          for (const effort of ['trivial', 'small', 'medium', 'large']) {
            variants.push({ strength, reversible, destructive, beyondRequest, effort });
          }
        }
      }
    }
  }
  return variants;
})();

const gateVariants = [false, true].flatMap((irreversible) => [false, true].flatMap((architectural) => [false, true].map((safety) => ({ irreversible, architectural, safety }))));

const callerListVariants = [undefined, [], ['outside_limits'], ['repeats_surface'], ['outside_limits', 'repeats_surface'], ['repeats_surface', 'outside_limits']];

function makeVariantBrief(variant, gate) {
  const base = makeBrief();
  const recommended = { ...base.options[0], reversible: variant.reversible, beyond_request: variant.beyondRequest, effort: variant.effort };
  if (variant.destructive !== undefined) {
    recommended.destructive = variant.destructive;
  }
  return makeBrief({ options: [recommended, base.options[1]], recommendation: { option_id: 'A', strength: variant.strength, why: 'Reason.' }, gate });
}

function expectDecision(kind, level, variant, gate, callerListed) {
  if (hardStopKinds.includes(kind)) {
    return { action: 'ask', reason: 'hard_stop' };
  }
  const isEarned = variant.strength === 'strong' && (variant.effort === 'trivial' || variant.effort === 'small');
  if (variant.beyondRequest && !isEarned) {
    return { action: 'ask', reason: 'malformed_brief' };
  }
  const row = table.rows.find((entry) => entry.kind === kind);
  if (row[lib.resolveLevel(level, table)] === 'surface') {
    return { action: 'ask', reason: 'table_surface' };
  }
  if (gate.irreversible || !variant.reversible) {
    return { action: 'ask', reason: 'gate_irreversible' };
  }
  if (gate.architectural) {
    return { action: 'ask', reason: 'gate_architectural' };
  }
  if (gate.safety || (variant.destructive !== undefined && variant.destructive.length > 0)) {
    return { action: 'ask', reason: 'gate_safety' };
  }
  if (variant.strength === 'none') {
    return { action: 'ask', reason: 'no_recommendation' };
  }
  const named = callerListed === undefined ? [] : callerListed;
  const listed = listSet.filter((name) => (name === 'beyond_request' ? variant.beyondRequest : named.includes(name)));
  return { action: 'take', reason: 'auto', listed };
}

function isSameDecision(verdict, expected) {
  if (verdict.action !== expected.action || verdict.reason !== expected.reason) {
    return false;
  }
  if (expected.action === 'ask') {
    return Object.keys(verdict).length === 2;
  }
  return Array.isArray(verdict.listed) && verdict.listed.join(',') === expected.listed.join(',');
}

describe('every kind, level, gate, recommended option and caller list', () => {
  const kinds = [...table.rows.map((row) => row.kind), ...hardStopKinds];
  const levels = [...table.levels, undefined, 'bogus'];
  const defectReasons = ['malformed_brief', 'recommendation_not_an_option'];
  const emptySchema = {};
  const cases = gateVariants.flatMap((gate) => recommendedVariants.map((variant) => ({ gate, variant, brief: makeVariantBrief(variant, gate) })));
  test('every product brief is well formed against the real schema, so an empty schema checks the rest the same way', () => {
    for (const { brief } of cases) {
      assert.deepEqual(structuredClone(lib.validateSchema(briefSchema, brief)), { ok: true, errors: [] });
    }
  });
  for (const testCase of cases) {
    const plannerVerdict = lib.decide({ kind: 'planner_question', level: 'high', brief: testCase.brief }, table, briefSchema);
    testCase.isRefused = defectReasons.includes(plannerVerdict.reason);
  }
  for (const kind of kinds) {
    test(`${kind}: an ask is in askReasons() unless the planner check refuses its brief, and a take is auto with listed in order`, () => {
      for (const { gate, variant, brief, isRefused } of cases) {
        for (const level of levels) {
          for (const callerListed of callerListVariants) {
            const verdict = lib.decide({ kind, level, brief, listed: callerListed }, table, emptySchema);
            const expected = expectDecision(kind, level, variant, gate, callerListed);
            const isAllowedAsk = verdict.action === 'ask' && (askSet.includes(verdict.reason) || (defectReasons.includes(verdict.reason) && isRefused));
            const isOrderedTake = verdict.action === 'take' && verdict.reason === 'auto' && verdict.listed.join(',') === listSet.filter((name) => verdict.listed.includes(name)).join(',');
            if (!isSameDecision(verdict, expected) || !(isAllowedAsk || isOrderedTake)) {
              assert.fail(JSON.stringify({ kind, level, gate, variant, callerListed, verdict, expected, isRefused }));
            }
          }
        }
      }
    });
  }
});

describe('caller listed names', () => {
  test('a caller name rides on a take at every auto cell of the real table, in listReasons() order', () => {
    const autoCells = table.rows.flatMap((row) => table.levels.filter((level) => row[level] === 'auto').map((level) => [row.kind, level]));
    assert.ok(autoCells.length > 0);
    for (const [kind, level] of autoCells) {
      assert.deepEqual(decideListing(kind, level, makeBrief(), ['outside_limits']), { ...takeAuto, listed: ['outside_limits'] });
      assert.deepEqual(decideListing(kind, level, makeBrief(), ['repeats_surface']), { ...takeAuto, listed: ['repeats_surface'] });
      const both = { ...takeAuto, listed: ['beyond_request', 'outside_limits', 'repeats_surface'] };
      assert.deepEqual(decideListing(kind, level, makeBeyondBrief(0), ['repeats_surface', 'outside_limits']), both);
    }
  });
  test('a caller name never makes it ask and never changes an ask', () => {
    const none = { option_id: 'A', strength: 'none', why: 'Both are fine.' };
    const briefs = [makeBrief(), makeBrief({ recommendation: none }), makeBrief({ gate: { irreversible: false, architectural: true, safety: false } }), null];
    for (const row of table.rows) {
      for (const level of [...table.levels, undefined, 'bogus']) {
        for (const brief of briefs) {
          const unlisted = decideWith(row.kind, level, brief);
          const withNames = decideListing(row.kind, level, brief, callerListSet);
          assert.equal(withNames.action, unlisted.action);
          assert.equal(withNames.reason, unlisted.reason);
          assert.deepEqual(decideListing(row.kind, level, brief, undefined), unlisted);
        }
      }
    }
  });
  test('an ask carries no listed field', () => {
    assert.deepEqual(Object.keys(decideListing('plan_acceptance', 'low', makeBrief(), callerListSet)).sort(), ['action', 'reason']);
  });
  test('a repeated caller name is listed once', () => {
    assert.deepEqual(decideListing('plan_acceptance', 'high', makeBrief(), ['outside_limits', 'outside_limits']).listed, ['outside_limits']);
  });
  for (const invalid of ['outside_limits', null, 0, false, {}, ['beyond_request'], ['auto'], ['hard_stop'], ['OUTSIDE_LIMITS'], [''], [undefined], ['outside_limits', 'gate_safety']]) {
    test(`listed ${JSON.stringify(invalid)} throws, even for a hard stop`, () => {
      for (const kind of ['plan_acceptance', hardStopKinds[0]]) {
        const call = () => lib.decide({ kind, level: 'high', brief: makeBrief(), listed: invalid }, table, briefSchema);
        assert.throws(call, /decide: (listed must be an array|unknown listed name)/);
      }
    });
  }
  test('neither the brief nor the caller list is mutated, and each take returns a new list', () => {
    const brief = makeBeyondBrief(0);
    const before = structuredClone(brief);
    const callerListed = ['repeats_surface'];
    const first = lib.decide({ kind: 'plan_acceptance', level: 'high', brief, listed: callerListed }, table, briefSchema);
    const second = lib.decide({ kind: 'plan_acceptance', level: 'high', brief, listed: callerListed }, table, briefSchema);
    decideListing('plan_acceptance', 'low', brief, callerListed);
    assert.deepEqual(brief, before);
    assert.deepEqual(callerListed, ['repeats_surface']);
    assert.notEqual(first.listed, second.listed);
    assert.notEqual(first.listed, callerListed);
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
