import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const cerebrateText = readFileSync(repoRoot + 'plugin/agents/cerebrate.md', 'utf8').replace(/\r/g, '');
const planSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/plan-schema.json', 'utf8'));
const briefSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-brief-schema.json', 'utf8'));

const PLAN_SCHEMA_PATH = '${CLAUDE_PLUGIN_ROOT}/references/plan-schema.json';
const BRIEF_SCHEMA_PATH = '${CLAUDE_PLUGIN_ROOT}/references/decision-brief-schema.json';
const SCHEMA_READ_SENTENCE = 'Before you return a plan or a question, read `' + PLAN_SCHEMA_PATH + '` and `' + BRIEF_SCHEMA_PATH + '` with Read for what each field means.';
const DOCTRINE_PATH = '${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md';
const READ_DISCIPLINE_RULES = [
  'Put every independent Read, Grep and Glob of a research step in one turn, as parallel calls.',
  'Grep to locate, then Read only the needed line range with `offset` and `limit`.',
  'Never read a file or range that is already in context again.',
  'Grep long append-only documents (a changelog, an ADR, a plan, a handoff); never read them whole.',
  'When the request names a document, read only the section the request is about.'
];
const SCOPE_BLOCK_RULE = 'Plan from that block. For each document it lists, read only the line ranges it names, and do not check again the paths it lists. Research only what the block does not cover.';
const SCOPE_MODE_RANGE_RULE = 'its path and the line ranges of the whole section the request is about. Find them with Grep, and copy no text. Leave out a document whose section you cannot bound, for the planner.';

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

function collectAnnotations(schema, texts) {
  for (const key of ['title', 'description']) {
    if (typeof schema[key] === 'string') {
      texts.push(schema[key]);
    }
  }
  Object.values(schema.properties === undefined ? {} : schema.properties).forEach((field) => collectAnnotations(field, texts));
  if (schema.items !== undefined) {
    collectAnnotations(schema.items, texts);
  }
  return texts;
}

function splitSentences(text) {
  return text.split(/(?<=\.)\s+/).map((sentence) => sentence.trim()).filter((sentence) => sentence.split(' ').length >= 6);
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

describe('cerebrate reads the plan and brief schemas for field meanings', () => {
  test('the Output section tells the planner to read both schema files before it returns a plan or a question', () => {
    assert.ok(readSection(cerebrateText, '## Output').includes(SCHEMA_READ_SENTENCE), SCHEMA_READ_SENTENCE);
  });
  test('cerebrate.md restates no title or description sentence of either schema', () => {
    const sentences = [...collectAnnotations(planSchema, []), ...collectAnnotations(briefSchema, [])].flatMap(splitSentences);
    assert.ok(sentences.length > 0);
    const copied = sentences.filter((sentence) => cerebrateText.includes(sentence));
    assert.deepEqual(copied, []);
  });
});

describe('cerebrate loads each governance doc only where a rule uses it', () => {
  test('no Load and follow line names remediation-doctrine.md', () => {
    const loadLines = cerebrateText.split('\n').filter((line) => /^load and follow/i.test(line.trim()));
    assert.deepEqual(loadLines.filter((line) => line.includes('remediation-doctrine.md')), []);
  });
  test('Remediation Zoom-Out Mode names remediation-doctrine.md', () => {
    assert.ok(readSection(cerebrateText, '### Remediation Zoom-Out Mode').includes(DOCTRINE_PATH), DOCTRINE_PATH);
  });
});

describe('cerebrate research reads only what the plan needs', () => {
  for (const rule of READ_DISCIPLINE_RULES) {
    test(`Research Rules carry: ${rule}`, () => {
      assert.ok(readSection(cerebrateText, '## Research Rules').includes(rule), rule);
    });
  }
  test('Research Rules drop the framing that over-reading is the cheap failure', () => {
    assert.ok(!readSection(cerebrateText, '## Research Rules').includes('under-reading is the expensive failure'));
  });
  test('the Scope Mode section exists and plans nothing', () => {
    assert.ok(readSection(cerebrateText, '### Scope Mode').includes('In this mode you plan nothing, raise no question, read neither schema file, load no governance doc and search no memory.'));
  });
  test('Scope Mode returns line ranges, not copied text', () => {
    assert.ok(readSection(cerebrateText, '### Scope Mode').includes(SCOPE_MODE_RANGE_RULE), SCOPE_MODE_RANGE_RULE);
  });
  test('a plan or revise delegation with a scope block plans from it', () => {
    assert.ok(readSection(cerebrateText, '## Scope Block').includes(SCOPE_BLOCK_RULE), SCOPE_BLOCK_RULE);
  });
});
