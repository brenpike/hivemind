import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/schema.js']);
const briefSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/decision-brief-schema.json', 'utf8'));

function validate(schema, value) {
  return structuredClone(lib.validateSchema(schema, value));
}

function collectKeywords(schema, keywords) {
  for (const keyword of Object.keys(schema)) {
    keywords.add(keyword);
  }
  Object.values(schema.properties || {}).forEach((child) => collectKeywords(child, keywords));
  if (schema.items !== undefined) {
    collectKeywords(schema.items, keywords);
  }
  return keywords;
}

function collectBlankableStringPaths(schema, path, paths) {
  if (schema.type === 'string' && schema.enum === undefined) {
    paths.push(path);
  }
  for (const [name, child] of Object.entries(schema.properties || {})) {
    collectBlankableStringPaths(child, path + '.' + name, paths);
  }
  if (schema.items !== undefined) {
    collectBlankableStringPaths(schema.items, path + '[0]', paths);
  }
  return paths;
}

function collectEnums(schema, enums) {
  if (schema.enum !== undefined) {
    enums.push(schema.enum);
  }
  Object.values(schema.properties || {}).forEach((child) => collectEnums(child, enums));
  if (schema.items !== undefined) {
    collectEnums(schema.items, enums);
  }
  return enums;
}

function setBriefPath(brief, path, value) {
  const steps = [...path.slice(1).matchAll(/\.([A-Za-z_]+)|\[(\d+)\]/g)].map((match) => match[1] ?? Number(match[2]));
  let node = brief;
  for (const step of steps.slice(0, -1)) {
    node = node[step];
  }
  node[steps[steps.length - 1]] = value;
  return brief;
}

function makeBrief(overrides = {}) {
  return {
    id: 'Q1',
    kind: 'planner_question',
    problem: 'Pick a format.',
    criticality: { level: 'low', likelihood: 'occasional', blast_radius: 'One file.', if_ignored: 'Nothing.' },
    options: [{ id: 'A', summary: 'S', steel_man: 'F', straw_man: 'G', effort: 'small', value: 'high', reversible: true }],
    ruled_out: [{ summary: 'R', why: 'W' }],
    recommendation: { option_id: 'A', strength: 'strong', why: 'Y' },
    assumptions: [{ statement: 'S', origin: 'user', evidence: 'E' }],
    gate: { irreversible: false, architectural: false, safety: false },
    verbatim: 'V',
    ...overrides
  };
}

describe('validateSchema keywords', () => {
  const typeCases = [
    ['object', { a: 1 }, [[], null, 'x']],
    ['array', [1], [{}, 'x', null]],
    ['string', 'x', [1, null, ['x'], undefined]],
    ['boolean', false, ['false', 0, null]],
    ['number', 1.5, ['1', NaN, Infinity, null]],
    ['integer', 2, [2.5, '2', null]],
    ['null', null, [undefined, 0, '']]
  ];
  for (const [typeName, good, bads] of typeCases) {
    test(`type ${typeName} accepts a match and rejects others`, () => {
      assert.deepEqual(validate({ type: typeName }, good), { ok: true, errors: [] });
      for (const bad of bads) {
        const result = validate({ type: typeName }, bad);
        assert.equal(result.ok, false, JSON.stringify(bad));
        assert.deepEqual(result.errors, ['$: type ' + typeName + ' expected']);
      }
    });
  }
  test('enum accepts a listed value and rejects others', () => {
    const schema = { type: 'string', enum: ['low', 'high'] };
    assert.equal(validate(schema, 'low').ok, true);
    assert.deepEqual(validate(schema, 'Low').errors, ['$: enum: not one of low, high']);
  });
  test('required reports each missing name and treats undefined as missing', () => {
    const schema = { type: 'object', required: ['a', 'b', 'c'], properties: { a: {}, b: {}, c: {} } };
    assert.equal(validate(schema, { a: 1, b: 2, c: 3 }).ok, true);
    assert.deepEqual(validate(schema, { a: 1, b: undefined }).errors, ['$: required: missing b', '$: required: missing c']);
  });
  test('properties checks each present property at its path', () => {
    const schema = { type: 'object', properties: { a: { type: 'string' }, b: { type: 'object', properties: { c: { type: 'boolean' } } } } };
    assert.equal(validate(schema, {}).ok, true);
    assert.deepEqual(validate(schema, { a: 1, b: { c: 'no' } }).errors, ['$.a: type string expected', '$.b.c: type boolean expected']);
  });
  test('additionalProperties false rejects unlisted keys but not undefined ones', () => {
    const schema = { type: 'object', additionalProperties: false, properties: { a: {} } };
    assert.equal(validate(schema, { a: 1, b: undefined }).ok, true);
    assert.deepEqual(validate(schema, { a: 1, b: 2 }).errors, ['$: additionalProperties: unexpected b']);
  });
  test('without additionalProperties unlisted keys are allowed', () => {
    assert.equal(validate({ type: 'object', properties: { a: {} } }, { b: 2 }).ok, true);
  });
  test('items checks every element at its index', () => {
    const schema = { type: 'array', items: { type: 'string' } };
    assert.equal(validate(schema, ['a', 'b']).ok, true);
    assert.deepEqual(validate(schema, ['a', 2, null]).errors, ['$[1]: type string expected', '$[2]: type string expected']);
  });
  test('minItems rejects a shorter array', () => {
    const schema = { type: 'array', minItems: 1 };
    assert.equal(validate(schema, [0]).ok, true);
    assert.deepEqual(validate(schema, []).errors, ['$: minItems: fewer than 1 items']);
  });
  test('$schema, title and description change nothing', () => {
    const schema = { $schema: 'https://json-schema.org/draft/2020-12/schema', title: 'T', description: 'D', type: 'string' };
    assert.equal(validate(schema, 'x').ok, true);
    assert.equal(validate(schema, 1).ok, false);
  });
  test('a failed type skips the other keywords at that path', () => {
    const schema = { type: 'object', required: ['a'], additionalProperties: false };
    assert.deepEqual(validate(schema, []).errors, ['$: type object expected']);
  });
});

describe('validateSchema blank strings', () => {
  for (const blank of ['', ' ', '\t\n', '\u00a0']) {
    test(`type string rejects blank ${JSON.stringify(blank)}`, () => {
      assert.deepEqual(validate({ type: 'string' }, blank), { ok: false, errors: ['$: type string: blank'] });
    });
  }
  for (const filled of [' x ', 'x']) {
    test(`type string accepts ${JSON.stringify(filled)}`, () => {
      assert.deepEqual(validate({ type: 'string' }, filled), { ok: true, errors: [] });
    });
  }
  test('a blank nested property is reported at its path', () => {
    const schema = { type: 'object', properties: { a: { type: 'string' } } };
    assert.deepEqual(validate(schema, { a: ' ' }).errors, ['$.a: type string: blank']);
  });
  test('a blank array item is reported at its index', () => {
    const schema = { type: 'array', items: { type: 'string' } };
    assert.deepEqual(validate(schema, ['a', '', 'b']).errors, ['$[1]: type string: blank']);
  });
  test('non-string types are unaffected', () => {
    assert.equal(validate({ type: 'boolean' }, false).ok, true);
    assert.equal(validate({ type: 'integer' }, 0).ok, true);
    assert.equal(validate({ type: 'null' }, null).ok, true);
    assert.equal(validate({ type: 'array' }, []).ok, true);
    assert.equal(validate({ type: 'object' }, {}).ok, true);
    assert.deepEqual(validate({ type: 'number' }, '').errors, ['$: type number expected']);
  });
  test('a schema with no type accepts a blank string', () => {
    assert.deepEqual(validate({}, ''), { ok: true, errors: [] });
  });
  test('an enum that lists the empty string accepts it', () => {
    assert.deepEqual(validate({ type: 'string', enum: ['', 'a'] }, ''), { ok: true, errors: [] });
  });
  test('an enum governs a blank not listed, with only the enum error', () => {
    assert.deepEqual(validate({ type: 'string', enum: ['a'] }, '').errors, ['$: enum: not one of a']);
  });
});

describe('validateSchema fails closed on the schema', () => {
  for (const keyword of ['oneOf', 'pattern', 'maxItems', 'const', '$ref', 'minLength', 'default']) {
    test(`unsupported keyword ${keyword} throws`, () => {
      const isUnsupported = (error) => error.message === 'validateSchema: $: unsupported keyword ' + keyword;
      assert.throws(() => lib.validateSchema({ type: 'string', [keyword]: 1 }, 'x'), isUnsupported);
    });
  }
  test('an unsupported keyword deep in an absent property still throws', () => {
    const schema = { type: 'object', properties: { a: { type: 'array', items: { type: 'string', format: 'email' } } } };
    assert.throws(() => lib.validateSchema(schema, {}), /\$\.a\[\]: unsupported keyword format/);
  });
  const badShapes = {
    'no schema': undefined,
    'null schema': null,
    'array schema': [],
    'type as an array': { type: ['string', 'null'] },
    'unknown type name': { type: 'text' },
    'enum not an array': { enum: 'a' },
    'enum with an object': { enum: [{}] },
    'required not an array': { required: 'a' },
    'required with a number': { required: [1] },
    'properties not an object': { properties: [] },
    'additionalProperties true': { additionalProperties: true },
    'additionalProperties a schema': { additionalProperties: { type: 'string' } },
    'items an array': { items: [] },
    'minItems negative': { minItems: -1 },
    'minItems not an integer': { minItems: 1.5 },
    'property schema not an object': { properties: { a: true } }
  };
  for (const [name, schema] of Object.entries(badShapes)) {
    test(`${name} throws`, () => {
      assert.throws(() => lib.validateSchema(schema, {}), /^Error: validateSchema: /);
    });
  }
  test('supportedSchemaKeywords lists exactly the supported keywords', () => {
    assert.deepEqual([...lib.supportedSchemaKeywords()].sort(), [
      '$schema', 'additionalProperties', 'description', 'enum', 'items', 'minItems', 'properties', 'required', 'title', 'type'
    ]);
  });
});

describe('the decision brief schema', () => {
  test('uses only supported keywords', () => {
    const used = [...collectKeywords(briefSchema, new Set())].sort();
    const supported = [...lib.supportedSchemaKeywords()];
    assert.deepEqual(used.filter((keyword) => !supported.includes(keyword)), []);
    assert.doesNotThrow(() => lib.validateSchema(briefSchema, {}));
  });
  test('accepts a full brief and one without optional fields', () => {
    assert.deepEqual(validate(briefSchema, makeBrief()), { ok: true, errors: [] });
    const brief = makeBrief();
    delete brief.ruled_out;
    delete brief.verbatim;
    assert.equal(validate(briefSchema, brief).ok, true);
  });
  for (const name of briefSchema.required) {
    test(`missing ${name} is rejected`, () => {
      assert.deepEqual(validate(briefSchema, makeBrief({ [name]: undefined })).errors, ['$: required: missing ' + name]);
    });
  }
  test('an unlisted top-level key is rejected', () => {
    assert.deepEqual(validate(briefSchema, makeBrief({ extra: 1 })).errors, ['$: additionalProperties: unexpected extra']);
  });
  const blankablePaths = collectBlankableStringPaths(briefSchema, '$', []);
  test('has string fields that must not be blank', () => {
    assert.ok(blankablePaths.includes('$.problem'));
    assert.ok(blankablePaths.includes('$.recommendation.option_id'));
    assert.ok(blankablePaths.includes('$.options[0].id'));
    assert.ok(blankablePaths.includes('$.verbatim'));
  });
  for (const path of blankablePaths) {
    test(`a blank ${path} is rejected`, () => {
      const brief = setBriefPath(makeBrief(), path, ' ');
      assert.deepEqual(validate(briefSchema, brief).errors, [path + ': type string: blank']);
    });
  }
  test('no enum lists a blank string', () => {
    const blanks = collectEnums(briefSchema, []).flat().filter((entry) => typeof entry === 'string' && entry.trim() === '');
    assert.deepEqual(blanks, []);
  });
  test('nested violations are reported with their paths', () => {
    const brief = makeBrief({
      criticality: { level: 'severe', likelihood: 'common', blast_radius: 'B', if_ignored: 'I' },
      ruled_out: [{ summary: 'R' }],
      assumptions: [{ statement: 'S', origin: 'user', evidence: 'E', note: 'N' }]
    });
    assert.deepEqual(validate(briefSchema, brief).errors, [
      '$.criticality.level: enum: not one of low, medium, high, critical',
      '$.ruled_out[0]: required: missing why',
      '$.assumptions[0]: additionalProperties: unexpected note'
    ]);
  });
});
