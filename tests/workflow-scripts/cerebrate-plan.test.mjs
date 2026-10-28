import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { splitProseSentences } from '../../tools/build_workflows.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const cerebrateText = readFileSync(repoRoot + 'plugin/agents/cerebrate.md', 'utf8').replace(/\r/g, '');
const planSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/plan-schema.json', 'utf8'));
const briefSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-brief-schema.json', 'utf8'));

const PLAN_SCHEMA_PATH = '${CLAUDE_PLUGIN_ROOT}/references/plan-schema.json';
const BRIEF_SCHEMA_PATH = '${CLAUDE_PLUGIN_ROOT}/references/decision-brief-schema.json';
const SCHEMA_READ_SENTENCE = 'Before you return a plan or a question, read `' + PLAN_SCHEMA_PATH + '` and `' + BRIEF_SCHEMA_PATH + '` with Read for what each field means.';
const DOCTRINE_PATH = '${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md';
const GOVERNANCE_PATH_PREFIX = '${CLAUDE_PLUGIN_ROOT}/governance/';
const SECTION_READ_PATTERN = /read the `## /i;
const LOAD_AND_FOLLOW_PATTERN = /load and follow/i;
const READ_DISCIPLINE_RULES = [
  'Put every independent Read, Grep and Glob of a research step in one turn, as parallel calls.',
  'Grep to locate, then Read only the needed line range with `offset` and `limit`.',
  'Never read a file or range that is already in context again.',
  'Grep long append-only documents (a changelog, an ADR, a plan, a handoff); never read them whole.',
  'When the request names a document, read only the section the request is about.'
];
const SCOPE_BLOCK_RULE = 'Plan from that block. Each document entry locates a section and does not bound it. Read the whole section that holds the entry\'s line, and take where the section starts and ends from the file, not from the entry. Do not check again the paths the block lists, and research only what the block does not cover.';
const SCOPE_BLOCK_COVERAGE_RULE = 'A document entry covers nothing when the file has no such line, or when the section that holds the line is not one the request or the facts texts name.';
const SCOPE_MODE_LOCATOR_RULE ='For each section of a repository document that the request or the facts texts name, the document\'s path and the line the section starts on. Find the line with Grep, and copy no text. Leave a section you cannot find for the planner.';
const SCOPE_MODE_LIMITS_RULE = 'The paths or directories that the request confines the work to, along with the user\'s answers when the delegation carries an answers block. Where they disagree, a later answer beats both the request and any earlier answer. Return none when nothing confines the work.';
const ANSWERS_SETTLE_RULE = 'an answers block in it holds the user\'s earlier answers. Each entry holds the questions of one round, the user\'s reply, and settled, the Q labels the reply settled. Only the questions and decisions an entry\'s settled labels name are settled for good: never raise them again and never reverse them. Every other question in that entry was still open after the reply. Labels belong to their own round, so Q1 in one entry is not Q1 in another.';
const STEP_SIZE_RULE = 'Size each step as one concern that one drone can carry. A step that mixes concerns, or that edits more than about four files beyond its own tests and generated output, is split along its file or concern seams. The split steps get `depends_on` only where the order is real.';
const RESEARCH_NOT_A_STEP_RULE = 'Every plan step changes files, so never make research, a probe or a measurement a plan step. Research, probes and measurements are your own work, and what your tools cannot answer goes to `Open questions:`.';

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
  test('every sentence that names a governance doc reads a named section of it or loads and follows it', () => {
    const citing = splitProseSentences(cerebrateText).filter((sentence) => sentence.includes(GOVERNANCE_PATH_PREFIX));
    assert.ok(citing.length > 0);
    assert.deepEqual(citing.filter((sentence) => !SECTION_READ_PATTERN.test(sentence) && !LOAD_AND_FOLLOW_PATTERN.test(sentence)), []);
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
  test('Scope Mode returns a locator for each section, not copied text', () => {
    assert.ok(readSection(cerebrateText, '### Scope Mode').includes(SCOPE_MODE_LOCATOR_RULE), SCOPE_MODE_LOCATOR_RULE);
  });
  test('Scope Mode returns three things, the third the paths the request and the answers limit the work to', () => {
    const scopeModeSection = readSection(cerebrateText, '### Scope Mode');
    assert.ok(scopeModeSection.includes('return three things:'), 'Scope Mode does not return three things');
    assert.ok(scopeModeSection.includes(SCOPE_MODE_LIMITS_RULE), SCOPE_MODE_LIMITS_RULE);
  });
  test('earlier answers settle for good only the questions their settled labels name', () => {
    const section = readSection(cerebrateText, '### Questions and Replies');
    const reviseStart = section.indexOf('asks you to revise:');
    const ruleStart = section.indexOf(ANSWERS_SETTLE_RULE);
    assert.notEqual(reviseStart, -1, 'the revise list is present');
    assert.notEqual(ruleStart, -1, ANSWERS_SETTLE_RULE);
    assert.ok(ruleStart < reviseStart, 'the answers rule sits before the revise list, so it applies to every delegation');
  });
  test('a plan or revise delegation with a scope block plans from it and reads the whole section at each locator', () => {
    assert.ok(readSection(cerebrateText, '## Scope Block').includes(SCOPE_BLOCK_RULE), SCOPE_BLOCK_RULE);
  });
  test('a document entry whose line is missing or lands outside a named section covers nothing, so the planner researches that section', () => {
    assert.ok(readSection(cerebrateText, '## Scope Block').includes(SCOPE_BLOCK_COVERAGE_RULE), SCOPE_BLOCK_COVERAGE_RULE);
  });
  test('the Scope Block no longer bounds reads by the line ranges of a locator', () => {
    assert.ok(!readSection(cerebrateText, '## Scope Block').includes('read only the line ranges'));
  });
});

describe('cerebrate sizes steps and keeps research out of them', () => {
  test('the Accuracy Note splits a step that mixes concerns or edits more than about four files', () => {
    assert.ok(readSection(cerebrateText, '### Accuracy Note: `depends_on` and `files` Are Concurrency-Load-Bearing').includes(STEP_SIZE_RULE), STEP_SIZE_RULE);
  });
  test('Branch Facts sends research, probes and measurements to the planner or to Open questions, never to a plan step', () => {
    assert.ok(readSection(cerebrateText, '## Branch Facts').includes(RESEARCH_NOT_A_STEP_RULE), RESEARCH_NOT_A_STEP_RULE);
  });
  test('Branch Facts no longer makes git research a plan step', () => {
    assert.ok(!readSection(cerebrateText, '## Branch Facts').includes('make it a plan step'));
  });
});
