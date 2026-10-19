import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const table = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-autonomy-table.json', 'utf8'));
const schema = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-brief-schema.json', 'utf8'));

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
  test('row kinds and hard stop names are unique and disjoint', () => {
    const names = [...table.rows.map((row) => row.kind), ...table.hard_stops.map((stop) => stop.hard_stop)];
    assert.ok(names.every((name) => typeof name === 'string' && name !== ''));
    assert.equal(new Set(names).size, names.length);
  });
});

describe('brief schema stays inside the structured-output subset', () => {
  const nodes = collectSchemaNodes(schema, '$', []);
  test('the root is an object schema', () => {
    assert.equal(schema.type, 'object');
  });
  for (const { node, path } of nodes) {
    test(`${path} has no maxItems and minItems at most 1`, () => {
      assert.equal(Object.hasOwn(node, 'maxItems'), false);
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
