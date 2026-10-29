import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const table = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-autonomy-table.json', 'utf8'));
const schema = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-brief-schema.json', 'utf8'));
const briefSource = readFileSync(repoRoot + 'plugin/workflow-src/lib/brief.js', 'utf8');
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/schema.js', repoRoot + 'plugin/workflow-src/lib/decide.js']);

const SHOWN_FIELD_PATHS = {
  problem: ['problem'],
  options: ['options'],
  summary: ['options', 'items', 'summary'],
  recommendation: ['recommendation'],
  why: ['recommendation', 'why'],
  strength: ['recommendation', 'strength']
};
const INTERNAL_FIELDS = ['id', 'option_id', 'kind'];
const ASK_OR_ROUND_FIELDS = ['brief', 'exact', 'labels', 'settled'];
const VERBATIM_FIELDS = ['verbatim'];

function readSchemaNode(path) {
  return path.reduce((node, name) => (name === 'items' ? node.items : node.properties[name]), schema);
}

function hasShownBound(node) {
  if (node.type === 'string') {
    return Object.hasOwn(node, 'maxLength') || Array.isArray(node.enum);
  }
  if (node.type === 'array') {
    return Object.hasOwn(node, 'maxItems');
  }
  return node.type === 'object' && node.additionalProperties === false;
}

function listReadFieldCalls(source) {
  const callCount = source.split('readField(').length - 1;
  const definitionCount = source.split('function readField(').length - 1;
  const names = [...source.matchAll(/(?=readField\((?:[^()]|\([^()]*\))*?,\s*'([A-Za-z_]+)'\))/g)].map((match) => match[1]);
  return { names, unnamedCount: callCount - definitionCount - names.length };
}

function collectSchemaNodes(node, path, nodes) {
  nodes.push({ node, path });
  for (const [name, child] of Object.entries(node.properties || {})) {
    collectSchemaNodes(child, `${path}.properties.${name}`, nodes);
  }
  if (node.items) {
    collectSchemaNodes(node.items, `${path}.items`, nodes);
  }
  return nodes;
}

describe('autonomy table', () => {
  test("'low' and default_level are levels", () => {
    assert.ok(table.levels.includes('low'));
    assert.ok(table.levels.includes(table.default_level));
  });
  test('levels are unique', () => {
    assert.equal(new Set(table.levels).size, table.levels.length);
  });
  for (const row of table.rows) {
    test(`row ${row.kind} has an auto or surface cell for every level`, () => {
      for (const level of table.levels) {
        assert.ok(['auto', 'surface'].includes(row[level]), `${row.kind}.${level} is ${JSON.stringify(row[level])}`);
      }
    });
  }
  for (const stop of table.hard_stops) {
    test(`hard stop ${stop.hard_stop} has no level keys`, () => {
      for (const level of table.levels) {
        assert.equal(Object.hasOwn(stop, level), false, `${stop.hard_stop} has key ${level}`);
      }
    });
  }
  test('external_effect is a hard stop, so it asks at every level', () => {
    const stop = table.hard_stops.find((entry) => entry.hard_stop === 'external_effect');
    assert.ok(stop !== undefined, 'external_effect is not a hard stop');
    assert.equal(table.rows.some((row) => row.kind === 'external_effect'), false, 'external_effect must not be a row with level cells');
    for (const level of table.levels) {
      const verdict = structuredClone(lib.decide({ kind: 'external_effect', level, brief: null }, table, schema));
      assert.deepEqual(verdict, { action: 'ask', reason: 'hard_stop' }, 'external_effect at ' + level);
    }
  });
  test('gate_rerun takes at high and balanced, asks at low, and is resolved at the gates step', () => {
    const row = table.rows.find((entry) => entry.kind === 'gate_rerun');
    assert.ok(row !== undefined, 'gate_rerun is not a row');
    assert.deepEqual([row.high, row.balanced, row.low], ['auto', 'auto', 'surface']);
    assert.deepEqual(row.resolved_at, ['standard-delivery.gates']);
  });
  test('remediation_plan_acceptance takes at high and balanced, asks at low, and its rule names plan.remediation_gate', () => {
    const row = table.rows.find((entry) => entry.kind === 'remediation_plan_acceptance');
    assert.ok(row !== undefined, 'remediation_plan_acceptance is not a row');
    assert.deepEqual([row.high, row.balanced, row.low], ['auto', 'auto', 'surface']);
    assert.ok(row.when.includes('plan.remediation_gate'), row.when);
  });
  for (const kind of ['review_question', 'high_severity_rejection']) {
    test(`${kind} takes at high and balanced, asks at low, and is resolved at a standard-delivery site`, () => {
      const row = table.rows.find((entry) => entry.kind === kind);
      assert.ok(row !== undefined, kind + ' is not a row');
      assert.deepEqual([row.high, row.balanced, row.low], ['auto', 'auto', 'surface']);
      assert.ok(row.resolved_at.includes('standard-delivery.local_review'), JSON.stringify(row.resolved_at));
      assert.ok(row.resolved_at.some((site) => !site.startsWith('standard-delivery.')), 'its state-machine sites stay');
    });
  }
  test('row kinds and hard stop names are unique and disjoint', () => {
    const names = [...table.rows.map((row) => row.kind), ...table.hard_stops.map((stop) => stop.hard_stop)];
    assert.ok(names.every((name) => typeof name === 'string' && name !== ''));
    assert.equal(new Set(names).size, names.length);
  });
});

describe('brief schema bounds the fields written for the user', () => {
  const properties = schema.properties;
  for (const [path, node, bound] of [
    ['problem', properties.problem, 300],
    ['options[].summary', properties.options.items.properties.summary, 160],
    ['recommendation.why', properties.recommendation.properties.why, 200],
    ['criticality.blast_radius', properties.criticality.properties.blast_radius, 160],
    ['criticality.if_ignored', properties.criticality.properties.if_ignored, 160]
  ]) {
    test(`${path} has maxLength ${bound} and says it is written for the user`, () => {
      assert.equal(node.maxLength, bound);
      assert.ok(node.description.startsWith('Written for the user'), node.description);
    });
  }
});

describe('brief schema stays inside the structured-output subset', () => {
  const nodes = collectSchemaNodes(schema, '$', []);
  test('the root is an object schema', () => {
    assert.equal(schema.type, 'object');
  });
  test('only options has maxItems, and it is 4', () => {
    const bounded = nodes.filter(({ node }) => Object.hasOwn(node, 'maxItems'));
    assert.deepEqual(bounded.map(({ path }) => path), ['$.properties.options']);
    assert.equal(schema.properties.options.maxItems, 4);
  });
  for (const { node, path } of nodes) {
    test(`${path} has minItems at most 1`, () => {
      if (Object.hasOwn(node, 'minItems')) {
        assert.ok(node.minItems <= 1, `minItems is ${node.minItems}`);
      }
    });
    if (node.type === 'object') {
      test(`${path} sets additionalProperties false`, () => {
        assert.equal(node.additionalProperties, false);
      });
      test(`${path} requires only declared properties`, () => {
        const declared = Object.keys(node.properties || {});
        for (const name of node.required || []) {
          assert.ok(declared.includes(name), `${name} is required but not a property`);
        }
      });
    }
  }
});

describe('every brief field lib/brief.js reads is classified', () => {
  const { names, unnamedCount } = listReadFieldCalls(briefSource);
  test('every readField call names its field as a string literal', () => {
    assert.ok(names.length > 0, 'no readField call found');
    assert.equal(unnamedCount, 0, 'a readField call names its field some other way');
  });
  for (const name of [...new Set(names)].sort()) {
    test(`readField name ${name} is shown with a bound, internal, an ask or round field, or verbatim`, () => {
      if (Object.hasOwn(SHOWN_FIELD_PATHS, name)) {
        const node = readSchemaNode(SHOWN_FIELD_PATHS[name]);
        assert.ok(node !== undefined, `${name} has no node in the brief schema`);
        assert.ok(hasShownBound(node), `${name} is shown but has no bound in the brief schema`);
        return;
      }
      const otherClasses = [...INTERNAL_FIELDS, ...ASK_OR_ROUND_FIELDS, ...VERBATIM_FIELDS];
      assert.ok(otherClasses.includes(name), `${name} is not classified`);
    });
  }
  test('verbatim is shown encoded in exact asks and whole in the PR body', () => {
    assert.ok(briefSource.includes("encodeUntrustedText(verbatim)"), 'an exact ask does not encode verbatim');
    assert.ok(briefSource.includes("return [labelIndent + 'Word for word:', verbatim];"), 'the PR body does not show verbatim whole');
  });
});
