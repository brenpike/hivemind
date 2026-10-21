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

describe('validateSchema minLength', () => {
  test('accepts a string at the boundary and rejects one below it', () => {
    assert.deepEqual(validate({ type: 'string', minLength: 2 }, 'ab'), { ok: true, errors: [] });
    assert.deepEqual(validate({ type: 'string', minLength: 2 }, 'a'), { ok: false, errors: ['$: minLength: fewer than 2 characters'] });
  });
  test('counts Unicode code points, not UTF-16 units', () => {
    assert.deepEqual(validate({ type: 'string', minLength: 1 }, '\u{1F600}'), { ok: true, errors: [] });
    assert.deepEqual(validate({ type: 'string', minLength: 2 }, '\u{1F600}').errors, ['$: minLength: fewer than 2 characters']);
  });
  for (const whitespace of [' ', '\t\n', '\u00a0']) {
    test(`type string with minLength 1 accepts whitespace-only ${JSON.stringify(whitespace)}`, () => {
      assert.deepEqual(validate({ type: 'string', minLength: 1 }, whitespace), { ok: true, errors: [] });
    });
  }
  test('an empty string gives only the minLength error', () => {
    assert.deepEqual(validate({ type: 'string', minLength: 1 }, '').errors, ['$: minLength: fewer than 1 characters']);
  });
  test('minLength 0 accepts the empty string', () => {
    assert.deepEqual(validate({ type: 'string', minLength: 0 }, ''), { ok: true, errors: [] });
  });
  test('minLength with no type applies to a string and ignores a number', () => {
    assert.deepEqual(validate({ minLength: 2 }, 5), { ok: true, errors: [] });
    assert.deepEqual(validate({ minLength: 2 }, 'a').errors, ['$: minLength: fewer than 2 characters']);
  });
  test('a short nested array item is reported at its index', () => {
    const schema = { type: 'array', items: { type: 'string', minLength: 1 } };
    assert.deepEqual(validate(schema, ['a', '', ' ']).errors, ['$[1]: minLength: fewer than 1 characters']);
  });
  test('a type failure skips minLength', () => {
    assert.deepEqual(validate({ type: 'string', minLength: 3 }, 1).errors, ['$: type string expected']);
  });
});

describe('validateSchema maxLength', () => {
  test('accepts a string at the boundary and rejects one above it', () => {
    assert.deepEqual(validate({ type: 'string', maxLength: 2 }, 'ab'), { ok: true, errors: [] });
    assert.deepEqual(validate({ type: 'string', maxLength: 2 }, 'abc'), { ok: false, errors: ['$: maxLength: more than 2 characters'] });
  });
  test('counts Unicode code points, not UTF-16 units', () => {
    assert.deepEqual(validate({ type: 'string', maxLength: 1 }, '\u{1F600}'), { ok: true, errors: [] });
    assert.deepEqual(validate({ type: 'string', maxLength: 1 }, '\u{1F600}\u{1F600}').errors, ['$: maxLength: more than 1 characters']);
  });
  test('maxLength 0 accepts only the empty string when no type is given', () => {
    assert.deepEqual(validate({ maxLength: 0 }, ''), { ok: true, errors: [] });
    assert.deepEqual(validate({ maxLength: 0 }, 'a').errors, ['$: maxLength: more than 0 characters']);
  });
  test('maxLength with no type applies to a string and ignores other values', () => {
    for (const other of [12345, null, true, ['a', 'b', 'c'], { a: 'abc' }]) {
      assert.deepEqual(validate({ maxLength: 2 }, other), { ok: true, errors: [] }, JSON.stringify(other));
    }
    assert.deepEqual(validate({ maxLength: 2 }, 'abc').errors, ['$: maxLength: more than 2 characters']);
  });
  test('maxLength does not govern the blank-string rule', () => {
    assert.deepEqual(validate({ type: 'string', maxLength: 5 }, ' ').errors, ['$: type string: blank']);
  });
  test('minLength and maxLength together bound a string', () => {
    const schema = { type: 'string', minLength: 2, maxLength: 3 };
    assert.equal(validate(schema, 'ab').ok, true);
    assert.equal(validate(schema, 'abc').ok, true);
    assert.deepEqual(validate(schema, 'a').errors, ['$: minLength: fewer than 2 characters']);
    assert.deepEqual(validate(schema, 'abcd').errors, ['$: maxLength: more than 3 characters']);
  });
  test('a long nested property is reported at its path', () => {
    const schema = { type: 'object', properties: { a: { type: 'string', maxLength: 1 } } };
    assert.deepEqual(validate(schema, { a: 'xy' }).errors, ['$.a: maxLength: more than 1 characters']);
  });
  test('a type failure skips maxLength', () => {
    assert.deepEqual(validate({ type: 'integer', maxLength: 1 }, 'abc').errors, ['$: type integer expected']);
  });
});

describe('validateSchema anyOf', () => {
  const stringOrNull = { anyOf: [{ type: 'string' }, { type: 'null' }] };
  test('accepts a value that matches any one branch', () => {
    assert.deepEqual(validate(stringOrNull, 'x'), { ok: true, errors: [] });
    assert.deepEqual(validate(stringOrNull, null), { ok: true, errors: [] });
  });
  test('accepts a value that matches more than one branch', () => {
    assert.deepEqual(validate({ anyOf: [{ type: 'number' }, { type: 'integer' }] }, 2), { ok: true, errors: [] });
  });
  test('a value that matches no branch gives exactly one error and no branch errors', () => {
    assert.deepEqual(validate(stringOrNull, 1), { ok: false, errors: ['$: anyOf: matches no branch'] });
  });
  test('a branch fails on any of its keywords, not only type', () => {
    const schema = { anyOf: [{ type: 'string', maxLength: 1 }, { type: 'string', enum: ['long'] }] };
    assert.equal(validate(schema, 'a').ok, true);
    assert.equal(validate(schema, 'long').ok, true);
    assert.deepEqual(validate(schema, 'other').errors, ['$: anyOf: matches no branch']);
  });
  test('the blank-string rule applies inside a branch', () => {
    assert.deepEqual(validate(stringOrNull, ' ').errors, ['$: anyOf: matches no branch']);
  });
  test('object branch errors do not leak', () => {
    const schema = {
      anyOf: [
        { type: 'object', required: ['a'], additionalProperties: false, properties: { a: { type: 'string' } } },
        { type: 'object', required: ['b'], additionalProperties: false, properties: { b: { type: 'integer' } } }
      ]
    };
    assert.equal(validate(schema, { a: 'x' }).ok, true);
    assert.equal(validate(schema, { b: 1 }).ok, true);
    assert.deepEqual(validate(schema, { a: 1, c: 2 }), { ok: false, errors: ['$: anyOf: matches no branch'] });
  });
  test('nested anyOf works', () => {
    const schema = { anyOf: [{ type: 'null' }, { anyOf: [{ type: 'boolean' }, { type: 'integer' }] }] };
    for (const good of [null, true, 3]) {
      assert.deepEqual(validate(schema, good), { ok: true, errors: [] }, JSON.stringify(good));
    }
    assert.deepEqual(validate(schema, 'x').errors, ['$: anyOf: matches no branch']);
  });
  test('anyOf errors are reported at their path alongside sibling errors', () => {
    const schema = { type: 'object', required: ['b'], properties: { a: stringOrNull, b: {} } };
    assert.deepEqual(validate(schema, { a: 1 }).errors, ['$: required: missing b', '$.a: anyOf: matches no branch']);
    const list = { type: 'array', items: stringOrNull };
    assert.deepEqual(validate(list, ['x', 2, null]).errors, ['$[1]: anyOf: matches no branch']);
  });
  test('anyOf combines with other keywords at the same path', () => {
    const schema = { type: 'string', minLength: 2, anyOf: [{ enum: ['ab'] }, { enum: ['cd'] }] };
    assert.equal(validate(schema, 'ab').ok, true);
    assert.deepEqual(validate(schema, 'x').errors, ['$: minLength: fewer than 2 characters', '$: anyOf: matches no branch']);
  });
  test('a type failure skips anyOf', () => {
    assert.deepEqual(validate({ type: 'object', anyOf: [{ type: 'string' }] }, 1).errors, ['$: type object expected']);
  });
  test('an unreachable bad branch still throws', () => {
    const schema = { anyOf: [{ type: 'string' }, { type: 'string', pattern: 'x' }] };
    assert.throws(() => lib.validateSchema(schema, 'x'), (error) => error.message === 'validateSchema: $.anyOf[1]: unsupported keyword pattern');
  });
  test('a bad branch inside an absent property still throws', () => {
    const schema = { type: 'object', properties: { a: { anyOf: [{ type: 'null' }, { anyOf: [{ type: 'text' }] }] } } };
    assert.throws(() => lib.validateSchema(schema, {}), /^Error: validateSchema: \$\.a\.anyOf\[1\]\.anyOf\[0\]: type must be one of/);
  });
});

describe('validateSchema fails closed on the schema', () => {
  for (const keyword of ['oneOf', 'allOf', 'not', 'if', 'then', 'else', 'pattern', 'maxItems', 'const', '$ref', 'multipleOf', 'default']) {
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
    'minLength negative': { minLength: -1 },
    'minLength not an integer': { minLength: 1.5 },
    'maxLength negative': { maxLength: -1 },
    'maxLength not an integer': { maxLength: 1.5 },
    'maxLength a string': { maxLength: '2' },
    'anyOf not an array': { anyOf: { type: 'string' } },
    'anyOf empty': { anyOf: [] },
    'anyOf with a non-object branch': { anyOf: [{ type: 'string' }, true] },
    'anyOf with a null branch': { anyOf: [null] },
    'anyOf with an array branch': { anyOf: [[]] },
    'property schema not an object': { properties: { a: true } }
  };
  for (const [name, schema] of Object.entries(badShapes)) {
    test(`${name} throws`, () => {
      assert.throws(() => lib.validateSchema(schema, {}), /^Error: validateSchema: /);
    });
  }
  test('supportedSchemaKeywords lists exactly the supported keywords', () => {
    assert.deepEqual([...lib.supportedSchemaKeywords()].sort(), [
      '$schema', 'additionalProperties', 'anyOf', 'description', 'enum', 'items', 'maxLength', 'minItems', 'minLength', 'properties',
      'required', 'title', 'type'
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
