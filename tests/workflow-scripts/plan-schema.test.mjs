import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/schema.js']);
const planCheck = loadLibs([repoRoot + 'plugin/workflow-src/standard-delivery/plan.js']);
const planSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/plan-schema.json', 'utf8'));
const factsSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/facts-schema.json', 'utf8'));
const briefSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-brief-schema.json', 'utf8'));

const EXTERNAL_LABEL = 'Can carry external content.';
const PATH_MARK = EXTERNAL_LABEL + ' Repository path.';
const SUBSET_KEYWORDS = [
  '$schema',
  'title',
  'description',
  'type',
  'enum',
  'required',
  'properties',
  'additionalProperties',
  'items',
  'minItems',
  'maxLength'
];
const OPTIONAL_PROPERTIES = { $: ['closes'] };

function validate(value) {
  return structuredClone(lib.validateSchema(planSchema, value));
}

function walkSchema(schema, path, visit) {
  visit(schema, path);
  for (const [name, child] of Object.entries(schema.properties || {})) {
    walkSchema(child, path + '.' + name, visit);
  }
  if (schema.items !== undefined) {
    walkSchema(schema.items, path + '[]', visit);
  }
}

function collectNodes(schema) {
  const nodes = [];
  walkSchema(schema, '$', (node, path) => nodes.push({ node, path }));
  return nodes;
}

function readScript(relativePath) {
  return readFileSync(repoRoot + relativePath, 'utf8').replace(/\r/g, '');
}

function parseCaseValues(scriptText, variableName) {
  const lines = scriptText.split('\n');
  const header = 'case "$' + variableName + '" in';
  const start = lines.findIndex((line) => line.trim() === header);
  assert.ok(start !== -1, 'no line ' + header);
  const firstArm = lines[start + 1].trim();
  const pattern = firstArm.slice(0, firstArm.indexOf(')'));
  assert.ok(pattern.length > 0, 'no pattern after ' + header);
  return pattern.split('|');
}

function makePlan() {
  return {
    summary: 'Add the plan schema.',
    title: 'Add the plan schema',
    digest: { problem: 'Plans have no schema the workflow can check.', change: 'Add the plan schema.' },
    remediation_gate: { promotion_gate: { irreversible: false, architectural: false, safety: false }, grows_surface: false, repeats_surface: false },
    branch: 'feature/409-plan-schema',
    base: 'main',
    trunk_freshness: 'fresh',
    classification: 'feature',
    breaking: false,
    versioning: { bump_trigger: 'yes', no_bump_match: 'no', artifact_files: ['plugin/.claude-plugin/plugin.json'] },
    validation_commands: ['bash tools/validate.sh --changed'],
    delivery: 'multi',
    steps: [
      {
        id: 'STEP-001',
        owner: 'hivemind:drone',
        files: ['plugin/references/plan-schema.json'],
        outcome: 'The schema exists.',
        depends_on: [],
        external_effects: []
      },
      {
        id: 'STEP-002',
        owner: 'hivemind:changeling',
        files: ['README.md', 'docs/notes.md'],
        outcome: 'The docs name the schema.',
        depends_on: ['STEP-001'],
        external_effects: [{ summary: 'Publish the package to the registry.', reversible: false }]
      }
    ]
  };
}

describe('plan schema', () => {
  test('stays in the structured-output subset of schema.js', () => {
    const supported = lib.supportedSchemaKeywords();
    for (const { node, path } of collectNodes(planSchema)) {
      for (const keyword of Object.keys(node)) {
        assert.ok(SUBSET_KEYWORDS.includes(keyword), path + ' uses keyword ' + keyword + ' outside the subset');
        assert.ok(supported.includes(keyword), path + ' uses keyword ' + keyword + ' that schema.js does not support');
      }
      if (node.minItems !== undefined) {
        assert.ok(node.minItems <= 1, path + ' minItems must be at most 1');
      }
    }
    assert.doesNotThrow(() => lib.validateSchema(planSchema, makePlan()));
  });

  test('every object has additionalProperties false and requires every declared property but the optional ones', () => {
    for (const { node, path } of collectNodes(planSchema)) {
      if (node.type !== 'object') {
        continue;
      }
      assert.equal(node.additionalProperties, false, path + ' must set additionalProperties false');
      assert.ok(node.properties !== undefined, path + ' must declare properties');
      const optional = OPTIONAL_PROPERTIES[path] ?? [];
      const expected = Object.keys(node.properties).filter((name) => !optional.includes(name));
      assert.deepEqual([...node.required].sort(), expected.sort(), path + ' must require exactly its properties but ' + JSON.stringify(optional));
    }
  });

  test('each optional property says so first in its description', () => {
    for (const [path, names] of Object.entries(OPTIONAL_PROPERTIES)) {
      const node = collectNodes(planSchema).find((entry) => entry.path === path).node;
      for (const name of names) {
        assert.ok(node.properties[name].description.startsWith('Optional.'), path + '.' + name);
      }
    }
  });

  test('closes is an optional list of issue numbers, and a plan with it is valid', () => {
    const closes = planSchema.properties.closes;
    assert.equal(closes.type, 'array');
    assert.equal(closes.items.type, 'integer');
    const plan = makePlan();
    plan.closes = [491, 488];
    assert.deepEqual(validate(plan), { ok: true, errors: [] });
    plan.closes = [];
    assert.deepEqual(validate(plan), { ok: true, errors: [] });
  });

  test('the external content label is on every string without an enum and on no other node', () => {
    const labelled = [];
    for (const { node, path } of collectNodes(planSchema)) {
      assert.equal(typeof node.description, 'string', path + ' must have a description');
      const isOpenString = node.type === 'string' && node.enum === undefined;
      const hasLabel = node.description.startsWith(EXTERNAL_LABEL);
      assert.equal(hasLabel, isOpenString, path + (isOpenString ? ' must start with the label' : ' must not carry the label'));
      if (hasLabel) {
        labelled.push(path);
      }
    }
    assert.deepEqual(labelled, [
      '$.summary',
      '$.title',
      '$.digest.problem',
      '$.digest.change',
      '$.branch',
      '$.base',
      '$.versioning.artifact_files[]',
      '$.validation_commands[]',
      '$.steps[].id',
      '$.steps[].files[]',
      '$.steps[].outcome',
      '$.steps[].depends_on[]',
      '$.steps[].external_effects[].summary'
    ]);
  });

  test('the repository path mark is on exactly the path fields', () => {
    const marked = collectNodes(planSchema).filter(({ node }) => node.description.startsWith(PATH_MARK));
    assert.deepEqual(marked.map(({ path }) => path), ['$.versioning.artifact_files[]', '$.steps[].files[]']);
    for (const { node, path } of marked) {
      assert.equal(node.type, 'string', path + ' must be a string');
      assert.equal(node.enum, undefined, path + ' must have no enum');
    }
  });

  test('every string node that names a path carries the repository path mark', () => {
    for (const { node, path } of collectNodes(planSchema)) {
      if (node.type === 'string' && /\bpath\b/i.test(node.description)) {
        assert.ok(node.description.startsWith(PATH_MARK), path + ' names a path but does not carry the mark');
      }
    }
  });

  test('the title description forbids naming a brood id, strain id or strain name unless the request asks', () => {
    const description = planSchema.properties.title.description;
    assert.ok(description.includes('It names no brood id, strain id or strain name unless the request asks for it.'), 'description: ' + description);
  });

  test('the top-level description defines the repository path mark and names molt.sh', () => {
    const description = planSchema.description;
    assert.ok(description.includes('"' + PATH_MARK + '"'), 'must quote the mark');
    assert.ok(description.includes('${CLAUDE_PLUGIN_ROOT}/skills/molt/scripts/molt.sh'), 'must name molt.sh');
  });

  test('the top-level description defines the label and says the plan is whole', () => {
    const description = planSchema.description;
    assert.ok(description.includes('"' + EXTERNAL_LABEL + '"'), 'must quote the label');
    assert.ok(description.includes('External Content Boundary'), 'must name the External Content Boundary');
    assert.ok(description.includes('${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md'), 'must name security-policy.md');
    assert.ok(description.includes('(Shell Identifier Discipline)'), 'must name Shell Identifier Discipline');
    assert.ok(description.includes('(Inert Inputs-File Navigator Pattern)'), 'must name the Inert Inputs-File Navigator Pattern');
    assert.ok(description.includes('never spliced into command text'), 'must keep labelled fields out of command text');
    assert.ok(description.includes('returns the plan whole'), 'must say the plan is returned whole');
  });

  test('no node declares complete or total', () => {
    for (const { node, path } of collectNodes(planSchema)) {
      for (const name of ['complete', 'total']) {
        assert.ok(!Object.hasOwn(node.properties || {}, name), path + ' must not declare ' + name);
        assert.ok(!(node.required || []).includes(name), path + ' must not require ' + name);
      }
    }
  });

  test('classification matches the enum in create-working-branch.sh', () => {
    const script = readScript('plugin/skills/create-working-branch/scripts/create-working-branch.sh');
    assert.deepEqual(planSchema.properties.classification.enum, parseCaseValues(script, 'classification'));
  });

  test('the versioning flags match the enums in bump-type.sh', () => {
    const script = readScript('plugin/skills/bump-type/scripts/bump-type.sh');
    const versioning = planSchema.properties.versioning.properties;
    assert.deepEqual(versioning.bump_trigger.enum, parseCaseValues(script, 'bump_trigger'));
    assert.deepEqual(versioning.no_bump_match.enum, parseCaseValues(script, 'no_bump_match'));
  });

  test('trunk_freshness matches the enum in facts-schema.json', () => {
    const factsFreshness = factsSchema.properties.repository.properties.trunk_freshness;
    assert.deepEqual(planSchema.properties.trunk_freshness.enum, factsFreshness.enum);
  });

  test('remediation_gate.promotion_gate has the property names, required list and types of the decision brief gate', () => {
    const promotionGate = planSchema.properties.remediation_gate.properties.promotion_gate;
    const briefGate = briefSchema.properties.gate;
    assert.equal(promotionGate.type, briefGate.type);
    assert.equal(promotionGate.additionalProperties, briefGate.additionalProperties);
    assert.deepEqual(Object.keys(promotionGate.properties), Object.keys(briefGate.properties));
    assert.deepEqual(promotionGate.required, briefGate.required);
    for (const [name, flag] of Object.entries(briefGate.properties)) {
      assert.equal(promotionGate.properties[name].type, flag.type, name + ' type');
    }
  });

  test('a full sample plan is valid', () => {
    assert.deepEqual(validate(makePlan()), { ok: true, errors: [] });
  });

  const invalidCases = [
    ['a plan without branch', (plan) => delete plan.branch, '$: required: missing branch'],
    ['a plan without base', (plan) => delete plan.base, '$: required: missing base'],
    ['a plan without title', (plan) => delete plan.title, '$: required: missing title'],
    ['a blank title', (plan) => { plan.title = ' \t '; }, '$.title: type string: blank'],
    ['a plan without versioning.artifact_files', (plan) => delete plan.versioning.artifact_files, '$.versioning: required: missing artifact_files'],
    ['a plan without validation_commands', (plan) => delete plan.validation_commands, '$: required: missing validation_commands'],
    ['a validation command that is not a string', (plan) => { plan.validation_commands = [5]; }, '$.validation_commands[0]: type string expected'],
    ['a blank validation command', (plan) => { plan.validation_commands = [' \t ']; }, '$.validation_commands[0]: type string: blank'],
    ['a trunk_freshness outside the enum', (plan) => { plan.trunk_freshness = 'stale'; }, '$.trunk_freshness: enum: not one of fresh, behind, ahead, diverged, no_remote, fetch_failed, no_local_trunk, no_trunk'],
    ['a classification outside the enum', (plan) => { plan.classification = 'feat'; }, '$.classification: enum: not one of feature, bugfix, hotfix, refactor, chore, docs, test, ci'],
    ['a brood delivery', (plan) => { plan.delivery = 'brood'; }, '$.delivery: enum: not one of single, multi'],
    ['a step without external_effects', (plan) => delete plan.steps[0].external_effects, '$.steps[0]: required: missing external_effects'],
    ['an effect without reversible', (plan) => delete plan.steps[1].external_effects[0].reversible, '$.steps[1].external_effects[0]: required: missing reversible'],
    ['an empty step list', (plan) => { plan.steps = []; }, '$.steps: minItems: fewer than 1 items'],
    ['a step with no files', (plan) => { plan.steps[0].files = []; }, '$.steps[0].files: minItems: fewer than 1 items'],
    ['an unknown key', (plan) => { plan.target = 'main'; }, '$: additionalProperties: unexpected target'],
    ['a plan without digest', (plan) => delete plan.digest, '$: required: missing digest'],
    ['a plan without remediation_gate', (plan) => delete plan.remediation_gate, '$: required: missing remediation_gate'],
    ['a digest problem over 200 code points', (plan) => { plan.digest.problem = 'p'.repeat(201); }, '$.digest.problem: maxLength: more than 200 characters'],
    ['a digest change over 200 code points', (plan) => { plan.digest.change = '\u{1F600}'.repeat(201); }, '$.digest.change: maxLength: more than 200 characters'],
    ['a promotion_gate that is missing a clause', (plan) => delete plan.remediation_gate.promotion_gate.safety, '$.remediation_gate.promotion_gate: required: missing safety'],
    ['a promotion_gate flag that is not a boolean', (plan) => { plan.remediation_gate.promotion_gate.irreversible = 'yes'; }, '$.remediation_gate.promotion_gate.irreversible: type boolean expected'],
    ['a remediation_gate flag that is not a boolean', (plan) => { plan.remediation_gate.grows_surface = 'yes'; }, '$.remediation_gate.grows_surface: type boolean expected'],
    ['a branch over 200 code points', (plan) => { plan.branch = 'b'.repeat(201); }, '$.branch: maxLength: more than 200 characters'],
    ['a step file path over 400 code points', (plan) => { plan.steps[0].files[0] = 'f'.repeat(401); }, '$.steps[0].files[0]: maxLength: more than 400 characters'],
    ['an artifact file path over 400 code points', (plan) => { plan.versioning.artifact_files[0] = '\u{1F600}'.repeat(401); }, '$.versioning.artifact_files[0]: maxLength: more than 400 characters'],
    ['a step id over 64 code points', (plan) => { plan.steps[0].id = 'S'.repeat(65); }, '$.steps[0].id: maxLength: more than 64 characters'],
    ['an effect summary over 300 code points', (plan) => { plan.steps[1].external_effects[0].summary = 'e'.repeat(301); }, '$.steps[1].external_effects[0].summary: maxLength: more than 300 characters'],
    ['a closes that is not a list', (plan) => { plan.closes = 491; }, '$.closes: type array expected'],
    ['a closes number written as a string', (plan) => { plan.closes = ['491']; }, '$.closes[0]: type integer expected'],
    ['a negative closes number', (plan) => { plan.closes = [-1]; }, '$.closes[0]: type integer: negative']
  ];

  for (const [name, mutate, expectedError] of invalidCases) {
    test('rejects ' + name, () => {
      const plan = makePlan();
      mutate(plan);
      const verdict = validate(plan);
      assert.equal(verdict.ok, false);
      assert.ok(verdict.errors.includes(expectedError), 'errors: ' + JSON.stringify(verdict.errors));
    });
  }

  const commandCases = [
    ['a validation command with a line break', 'bash tools/validate.sh --changed\nrm -rf x', 'holds a line break'],
    ['a validation command with a carriage return', 'bash tools/validate.sh\r', 'holds a line break'],
    ['a validation command with a line separator', 'bash tools/validate.sh\u2028x', 'holds a line break'],
    ['a validation command with a control character', 'bash tools/validate.sh\u001b[0m', 'holds a control character'],
    ['a validation command with a C1 control character', 'bash tools/validate.sh\u009b', 'holds a control character']
  ];

  for (const [name, command, expectedReason] of commandCases) {
    test('the plan check rejects ' + name, () => {
      const plan = makePlan();
      plan.validation_commands = ['bash tools/validate.sh --changed', command];
      assert.deepEqual(validate(plan), { ok: true, errors: [] });
      const reasons = plan.validation_commands.map((entry) => planCheck.describeValidationCommandProblem(entry));
      assert.deepEqual(reasons, ['', expectedReason]);
    });
  }

  test('the plan check also refuses a blank or empty validation command', () => {
    assert.deepEqual([' \t ', ''].map((entry) => planCheck.describeValidationCommandProblem(entry)), ['is blank', 'is blank']);
  });

  test('the plan check accepts the sample commands and an empty command list', () => {
    const plan = makePlan();
    assert.deepEqual(plan.validation_commands.map((entry) => planCheck.describeValidationCommandProblem(entry)), ['']);
    plan.validation_commands = [];
    assert.deepEqual(validate(plan), { ok: true, errors: [] });
  });
});
