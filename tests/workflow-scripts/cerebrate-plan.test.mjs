import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const cerebrateText = readFileSync(repoRoot + 'plugin/agents/cerebrate.md', 'utf8').replace(/\r/g, '');
const planSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/plan-schema.json', 'utf8'));

const PLAN_SCHEMA_PATH = '${CLAUDE_PLUGIN_ROOT}/references/plan-schema.json';

function readSection(text, heading) {
  const lines = text.split('\n');
  const start = lines.indexOf(heading);
  assert.notEqual(start, -1, `cerebrate.md has the heading ${heading}`);
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => /^#{2,3} /.test(line));
  return (end === -1 ? rest : rest.slice(0, end)).join('\n');
}

function readYamlBlock(section) {
  const match = section.match(/```yaml\n([\s\S]*?)\n```/);
  assert.ok(match, 'the plan block section has a yaml code block');
  return match[1];
}

function readKeyPaths(yamlText) {
  const keyPaths = new Set();
  const stack = [];
  for (const line of yamlText.split('\n')) {
    const keyMatch = line.match(/^( *)(- )?([A-Za-z_]+):/);
    if (!keyMatch) {
      continue;
    }
    const indent = keyMatch[1].length + (keyMatch[2] ? keyMatch[2].length : 0);
    while (stack.length > 0 && stack[stack.length - 1].indent >= indent) {
      stack.pop();
    }
    stack.push({ indent, name: keyMatch[3] });
    keyPaths.add(stack.map((entry) => entry.name).join('.'));
  }
  return keyPaths;
}

const planSection = readSection(cerebrateText, '### Machine-Readable Plan Block');
const planYaml = readYamlBlock(planSection);
const planKeyPaths = readKeyPaths(planYaml);
const stepSchema = planSchema.properties.steps.items;
const effectSchema = stepSchema.properties.external_effects.items;

describe('cerebrate plan block against plan-schema.json', () => {
  for (const name of Object.keys(planSchema.properties)) {
    test(`plan block carries top-level ${name}`, () => {
      assert.ok(planKeyPaths.has(`plan.${name}`), `key paths are ${JSON.stringify([...planKeyPaths])}`);
    });
  }
  for (const name of Object.keys(stepSchema.properties)) {
    test(`plan block step carries ${name}`, () => {
      assert.ok(planKeyPaths.has(`plan.steps.${name}`), `key paths are ${JSON.stringify([...planKeyPaths])}`);
    });
  }
  for (const name of Object.keys(planSchema.properties.versioning.properties)) {
    test(`plan block versioning carries ${name}`, () => {
      assert.ok(planKeyPaths.has(`plan.versioning.${name}`), `key paths are ${JSON.stringify([...planKeyPaths])}`);
    });
  }
  for (const name of Object.keys(effectSchema.properties)) {
    test(`plan block names the external effect field ${name}`, () => {
      assert.match(planYaml, new RegExp(`external_effects:.*\\b${name}\\b`));
    });
  }
  test('plan block section names the plan-schema path', () => {
    assert.ok(planSection.includes(PLAN_SCHEMA_PATH), `section does not name ${PLAN_SCHEMA_PATH}`);
  });
});
