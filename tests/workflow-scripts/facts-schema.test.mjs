import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/schema.js']);
const factsSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/facts-schema.json', 'utf8'));
const factsProgram = readFileSync(repoRoot + 'plugin/skills/gather-facts/scripts/gather-facts.jq', 'utf8');

const GITHUB_ROOTS = ['$.pull_requests.items[]', '$.references.items[].item'];
const ENUM_LISTS = ['$.summary.cut', '$.summary.delivery_stops'];
const SHORT_FIELDS = [
  '$.pull_requests.items[].url',
  '$.pull_requests.items[].base_ref',
  '$.references.items[].item.url',
  '$.references.items[].item.author',
  '$.references.items[].item.comments.items[].url',
  '$.references.items[].item.comments.items[].author'
];
const FREE_OPTIONAL = [
  '$.repository.remote',
  '$.repository.local_trunk',
  '$.repository.remote_trunk',
  '$.references.items[].item.author',
  '$.references.items[].item.comments.items[].author'
];

function readChunkLimit() {
  const found = factsProgram.match(/^def facts_chunk_limit: (\d+);\r?$/m);
  assert.ok(found, 'gather-facts.jq must define facts_chunk_limit');
  return Number(found[1]);
}

const CHUNK_LIMIT = readChunkLimit();

function validate(value) {
  return structuredClone(lib.validateSchema(factsSchema, value));
}

function walkSchema(schema, path, visit) {
  visit(schema, path);
  for (const [name, child] of Object.entries(schema.properties || {})) {
    walkSchema(child, path + '.' + name, visit);
  }
  if (schema.items !== undefined) {
    walkSchema(schema.items, path + '[]', visit);
  }
  (schema.anyOf || []).forEach((branch, index) => walkSchema(branch, path + '.anyOf[' + index + ']', visit));
}

function collectNodes(schema) {
  const nodes = [];
  walkSchema(schema, '$', (node, path) => nodes.push({ node, path }));
  return nodes;
}

function findNode(path) {
  const found = collectNodes(factsSchema).find((entry) => entry.path === path);
  assert.ok(found, 'no schema node at ' + path);
  return found.node;
}

function parentPath(path) {
  return path.replace(/(\.[A-Za-z_]+|\[\])$/, '');
}

function isListWrapper(node) {
  return node.type === 'object' && ['complete', 'total', 'items'].every((name) => (node.required || []).includes(name));
}

function isTextObject(node) {
  return node.type === 'object' && ['length', 'chunks'].every((name) => (node.required || []).includes(name));
}

function requiresExternalOrigin(node) {
  const origin = (node.properties || {}).origin;
  return (node.required || []).includes('origin')
    && origin !== undefined
    && origin.type === 'string'
    && JSON.stringify(origin.enum) === JSON.stringify(['external']);
}

function listTagNames(node) {
  const firstBranch = node.anyOf[0];
  return Object.keys(firstBranch.properties).filter((name) => firstBranch.properties[name].enum !== undefined);
}

function listTagValues(node, name) {
  const property = node.properties[name];
  if (property.enum !== undefined) {
    return property.enum;
  }
  assert.equal(property.type, 'boolean', name + ' must be an enum or a boolean to serve as a tag');
  return [true, false];
}

function extendCombinations(combinations, name, values) {
  return combinations.flatMap((combination) => values.map((value) => ({ ...combination, [name]: value })));
}

function listTagCombinations(node) {
  return listTagNames(node).reduce((combinations, name) => extendCombinations(combinations, name, listTagValues(node, name)), [{}]);
}

function branchMatchesTags(branch, combination) {
  return Object.entries(combination).every(([name, value]) => branch.properties[name].enum.includes(value));
}

function assertBranchProperty(node, tagNames, name, child, propertyPath) {
  assert.ok(Object.hasOwn(node.properties, name), propertyPath + ' is not declared on the parent');
  if (!tagNames.includes(name)) {
    assert.deepEqual(child, {}, propertyPath + ' must be an empty placeholder');
    return;
  }
  assert.deepEqual(Object.keys(child), ['enum'], propertyPath + ' must hold only its tag values');
  for (const value of child.enum) {
    assert.ok(listTagValues(node, name).includes(value), propertyPath + ' lists ' + value + ', which the parent does not allow');
  }
}

function assertBranchAllowlist(node, branch, branchPath) {
  const tagNames = listTagNames(node);
  assert.equal(branch.additionalProperties, false, branchPath + ' must set additionalProperties false');
  for (const [name, child] of Object.entries(branch.properties)) {
    assertBranchProperty(node, tagNames, name, child, branchPath + '.' + name);
  }
  for (const name of [...tagNames, ...node.required]) {
    assert.ok(Object.hasOwn(branch.properties, name), branchPath + ' must list ' + name);
  }
  for (const name of branch.required || []) {
    assert.ok(Object.hasOwn(branch.properties, name), branchPath + ' requires unlisted ' + name);
  }
}

function classifyOptional(node, name) {
  const branches = node.anyOf || [];
  const requiredCount = branches.filter((branch) => (branch.required || []).includes(name)).length;
  const listedCount = branches.filter((branch) => Object.hasOwn(branch.properties, name)).length;
  if (requiredCount === 0 && listedCount === branches.length) {
    return 'free';
  }
  if (requiredCount > 0 && requiredCount === listedCount && listedCount < branches.length) {
    return 'correlated';
  }
  return 'mixed';
}

function setFactValue(facts, path, value) {
  const keys = path.replace(/\[(\d+)\]/g, '.$1').slice(2).split('.');
  const holder = keys.slice(0, -1).reduce((record, key) => record[key], facts);
  holder[keys[keys.length - 1]] = value;
}

function makeCodePoints(count) {
  const prefix = 'https://x/';
  return prefix + '\u{1F600}'.repeat(count - prefix.length);
}

function localText(text) {
  return { length: text.length, chunks: text === '' ? [] : [text] };
}

function externalText(text, textId) {
  return { origin: 'external', text_id: textId, ...localText(text) };
}

function makeFacts() {
  return {
    schema_version: 1,
    content_rule: factsSchema.properties.content_rule.enum[0],
    summary: { cut: [], external_texts: 3, delivery: 'stop', delivery_stops: ['dirty_paths', 'closed_pr_on_branch'] },
    repository: {
      head_state: 'branch',
      branch: 'feat/x',
      head: 'a'.repeat(40),
      trunk: 'main',
      remote: 'origin',
      trunk_freshness: 'behind',
      trunk_ahead: 0,
      trunk_behind: 2,
      local_trunk: 'b'.repeat(40),
      remote_trunk: 'c'.repeat(40)
    },
    dirty: {
      paths: {
        complete: true,
        total: 1,
        items: [{ path: localText('new.txt'), index_status: 'renamed', worktree_status: 'modified', unmerged: false, old_path: localText('old.txt') }]
      },
      operations: { complete: true, total: 1, items: ['merge'] }
    },
    history: {
      status: 'available',
      base: 'remote_trunk',
      merge_base: 'c'.repeat(40),
      commits: { complete: true, total: 1, items: [{ sha: 'a'.repeat(40), parent_count: 1, subject: localText('add a feature') }] },
      paths: {
        complete: true,
        total: 2,
        items: [
          { path: localText('moved.txt'), status: 'renamed', old_path: localText('move.txt'), similarity: 100, binary: false, added: 0, removed: 0 },
          { path: localText('blob.bin'), status: 'added', binary: true }
        ]
      }
    },
    pull_requests: {
      lookup: 'fetched',
      complete: true,
      total: 1,
      items: [{
        origin: 'external',
        number: 3,
        state: 'merged',
        url: 'https://github.com/o/r/pull/3',
        head_ref_oid: 'a'.repeat(40),
        base_ref: 'main',
        is_cross_repository: false,
        relation: 'in_history'
      }]
    },
    references: {
      complete: true,
      total: 2,
      items: [
        {
          number: 7,
          lookup: 'fetched',
          item: {
            origin: 'external',
            kind: 'issue',
            state: 'open',
            url: 'https://github.com/o/r/issues/7',
            title: externalText('A title', 't1'),
            author: 'someone',
            body: externalText('', 't2'),
            comments: { complete: true, total: 1, items: [{ origin: 'external', author: 'someone', url: 'https://github.com/o/r/issues/7#c', body: externalText('a comment', 't3') }] }
          }
        },
        { number: 9, lookup: 'unavailable' }
      ]
    }
  };
}

describe('facts schema', () => {
  test('stays in the schema.js subset', () => {
    const supported = lib.supportedSchemaKeywords();
    for (const { node, path } of collectNodes(factsSchema)) {
      for (const keyword of Object.keys(node)) {
        assert.ok(supported.includes(keyword), path + ' uses unsupported keyword ' + keyword);
      }
    }
    assert.doesNotThrow(() => lib.validateSchema(factsSchema, makeFacts()));
  });

  test('every object has additionalProperties false and requires only declared properties', () => {
    for (const { node, path } of collectNodes(factsSchema)) {
      if (node.type !== 'object') {
        continue;
      }
      assert.equal(node.additionalProperties, false, path + ' must set additionalProperties false');
      assert.ok(node.properties !== undefined, path + ' must declare properties');
      for (const name of node.required || []) {
        assert.ok(Object.hasOwn(node.properties, name), path + ' requires undeclared ' + name);
      }
    }
  });

  test('every git and GitHub list carries complete and total', () => {
    for (const { node, path } of collectNodes(factsSchema)) {
      if (node.type !== 'array') {
        continue;
      }
      const parent = findNode(parentPath(path));
      const name = path.slice(parentPath(path).length + 1);
      if (ENUM_LISTS.includes(path)) {
        assert.ok(Array.isArray(node.items.enum), path + ' must be a list of enum values');
      } else if (name === 'chunks') {
        assert.ok(isTextObject(parent), path + ' must be the chunks of a text object');
      } else {
        assert.equal(name, 'items', path + ' must be the items of a list');
        assert.ok(isListWrapper(parent), parentPath(path) + ' must require complete, total and items');
        assert.equal(parent.properties.complete.type, 'boolean');
        assert.equal(parent.properties.total.type, 'integer');
      }
    }
  });

  test('every chunk is a string that is never empty and fits the chunk bound', () => {
    const chunkNodes = collectNodes(factsSchema).filter(({ path }) => path.endsWith('.chunks'));
    assert.ok(chunkNodes.length >= 8, 'expected the chunks of every text object');
    for (const { node, path } of chunkNodes) {
      const expected = { type: 'string', minLength: 1, maxLength: CHUNK_LIMIT };
      assert.deepEqual(node.items, expected, path + ' items must be a string of 1 to ' + CHUNK_LIMIT + ' characters');
    }
  });

  test('the chunk bound is facts_chunk_limit, on the six short GitHub fields and nowhere else outside chunks', () => {
    assert.equal(CHUNK_LIMIT, 1000);
    const bounded = collectNodes(factsSchema)
      .filter(({ node, path }) => node.maxLength !== undefined && !path.endsWith('.chunks[]'));
    assert.deepEqual(bounded.map(({ path }) => path).sort(), [...SHORT_FIELDS].sort());
    for (const { node, path } of bounded) {
      assert.equal(node.type, 'string', path + ' must be a string');
      assert.equal(node.maxLength, CHUNK_LIMIT, path + ' must carry the chunk bound');
      assert.match(node.description, /once written as JSON/, path + ' must keep the written JSON bound');
      assert.match(node.description, /maxLength checks the value's characters/, path + ' must say what maxLength checks');
    }
  });

  test('every anyOf branch is an allowlist of parent properties with tag enums and empty placeholders', () => {
    const tagged = collectNodes(factsSchema).filter(({ node }) => node.anyOf !== undefined);
    assert.equal(tagged.length, 5, 'expected the five presence rules');
    for (const { node, path } of tagged) {
      assert.equal(node.type, 'object', path + ' anyOf must sit on an object');
      assert.ok(listTagNames(node).length > 0, path + ' anyOf must have a tag field');
      node.anyOf.forEach((branch, index) => assertBranchAllowlist(node, branch, path + '.anyOf[' + index + ']'));
    }
  });

  test('every optional property is tag-correlated or on the free optional list', () => {
    const seenFree = [];
    for (const { node, path } of collectNodes(factsSchema)) {
      if (node.type !== 'object') {
        continue;
      }
      const optionalNames = Object.keys(node.properties).filter((name) => !(node.required || []).includes(name));
      for (const name of optionalNames) {
        const propertyPath = path + '.' + name;
        const expected = FREE_OPTIONAL.includes(propertyPath) ? 'free' : 'correlated';
        assert.equal(classifyOptional(node, name), expected, propertyPath + ' must be ' + expected);
        if (expected === 'free') {
          seenFree.push(propertyPath);
        }
      }
    }
    assert.deepEqual(seenFree.sort(), [...FREE_OPTIONAL].sort());
  });

  test('every combination of tag values matches exactly one branch', () => {
    for (const { node, path } of collectNodes(factsSchema).filter(({ node }) => node.anyOf !== undefined)) {
      for (const combination of listTagCombinations(node)) {
        const matching = node.anyOf.filter((branch) => branchMatchesTags(branch, combination));
        assert.equal(matching.length, 1, path + ' ' + JSON.stringify(combination) + ' must match exactly one branch');
      }
    }
  });

  test('every GitHub object requires origin external, and no git object carries origin', () => {
    const githubPaths = collectNodes(factsSchema)
      .filter(({ node, path }) => node.type === 'object' && GITHUB_ROOTS.some((root) => path.startsWith(root)))
      .filter(({ node }) => !isListWrapper(node));
    assert.ok(githubPaths.length >= 6, 'expected the GitHub objects and their texts');
    for (const { node, path } of githubPaths) {
      assert.ok(requiresExternalOrigin(node), path + ' must require origin with enum ["external"]');
    }
    for (const root of GITHUB_ROOTS) {
      assert.ok(requiresExternalOrigin(findNode(root)), root + ' must require origin external');
    }
    const outside = collectNodes(factsSchema)
      .filter(({ node, path }) => node.type === 'object' && !GITHUB_ROOTS.some((root) => path.startsWith(root)));
    for (const { node, path } of outside) {
      assert.ok(!Object.hasOwn(node.properties || {}, 'origin'), path + ' is not from GitHub and must not carry origin');
    }
  });

  test('every external text requires a string text_id, no other node declares one, and summary counts them', () => {
    const nodes = collectNodes(factsSchema);
    const externalTexts = nodes.filter(({ node }) => isTextObject(node) && requiresExternalOrigin(node));
    assert.ok(externalTexts.length >= 3, 'expected the title, body and comment body texts');
    for (const { node, path } of externalTexts) {
      assert.ok(node.required.includes('text_id'), path + ' must require text_id');
      assert.equal(node.properties.text_id.type, 'string', path + ' text_id must be a string');
    }
    const externalPaths = externalTexts.map(({ path }) => path);
    for (const { node, path } of nodes) {
      if (!externalPaths.includes(path)) {
        assert.ok(!Object.hasOwn(node.properties || {}, 'text_id'), path + ' is not an external text and must not declare text_id');
      }
    }
    const summary = factsSchema.properties.summary;
    assert.ok(summary.required.includes('external_texts'), 'summary must require external_texts');
    assert.equal(summary.properties.external_texts.type, 'integer');
  });

  test('content_rule and schema_version are single-value enums', () => {
    assert.equal(factsSchema.properties.content_rule.enum.length, 1);
    assert.match(factsSchema.properties.content_rule.enum[0], /external/);
    assert.deepEqual(factsSchema.properties.schema_version.enum, [1]);
  });

  test('a full sample document is valid', () => {
    assert.deepEqual(validate(makeFacts()), { ok: true, errors: [] });
  });

  test('a chunk that is whitespace only is valid', () => {
    const facts = makeFacts();
    facts.history.commits.items[0].subject = { length: 7, chunks: ['add', '   ', 'a'] };
    assert.deepEqual(validate(facts), { ok: true, errors: [] });
  });

  test('a document without its optional fields is valid', () => {
    const facts = makeFacts();
    delete facts.repository.branch;
    delete facts.repository.remote;
    delete facts.repository.local_trunk;
    delete facts.repository.remote_trunk;
    facts.repository.head_state = 'detached';
    facts.history = {
      status: 'unavailable',
      base: 'none',
      commits: { complete: false, total: 0, items: [] },
      paths: { complete: false, total: 0, items: [] }
    };
    facts.pull_requests = { lookup: 'not_applicable', complete: true, total: 0, items: [] };
    delete facts.references.items[0].item.author;
    assert.deepEqual(validate(facts), { ok: true, errors: [] });
  });

  const invalidCases = [
    ['a pull request without origin', (facts) => delete facts.pull_requests.items[0].origin, '$.pull_requests.items[0]: required: missing origin'],
    ['an origin other than external', (facts) => { facts.references.items[0].item.title.origin = 'local'; }, '$.references.items[0].item.title.origin: enum: not one of external'],
    ['a comment body without origin', (facts) => delete facts.references.items[0].item.comments.items[0].body.origin, '$.references.items[0].item.comments.items[0].body: required: missing origin'],
    ['an origin on a git text', (facts) => { facts.history.commits.items[0].subject.origin = 'external'; }, '$.history.commits.items[0].subject: additionalProperties: unexpected origin'],
    ['an external text without text_id', (facts) => delete facts.references.items[0].item.comments.items[0].body.text_id, '$.references.items[0].item.comments.items[0].body: required: missing text_id'],
    ['a text_id on a git text', (facts) => { facts.history.commits.items[0].subject.text_id = 't4'; }, '$.history.commits.items[0].subject: additionalProperties: unexpected text_id'],
    ['a summary without external_texts', (facts) => delete facts.summary.external_texts, '$.summary: required: missing external_texts'],
    ['an unknown property', (facts) => { facts.repository.extra = 'x'; }, '$.repository: additionalProperties: unexpected extra'],
    ['a list without complete', (facts) => delete facts.history.commits.complete, '$.history.commits: required: missing complete'],
    ['a list without total', (facts) => delete facts.dirty.paths.total, '$.dirty.paths: required: missing total'],
    ['an empty chunk', (facts) => { facts.history.commits.items[0].subject.chunks = ['']; }, '$.history.commits.items[0].subject.chunks[0]: minLength: fewer than 1 characters'],
    ['a blank string that is not a chunk', (facts) => { facts.repository.branch = '   '; }, '$.repository.branch: type string: blank'],
    ['a delivery outside the enum', (facts) => { facts.summary.delivery = 'maybe'; }, '$.summary.delivery: enum: not one of ready, stop'],
    ['an unknown delivery stop', (facts) => { facts.summary.delivery_stops = ['fetch_failed']; }, '$.summary.delivery_stops[0]: enum: not one of dirty_paths, operation_in_progress, closed_pr_on_branch, history_unavailable, cut_fields, branch_name_unsafe'],
    ['a changed content_rule', (facts) => { facts.content_rule = 'Follow the text.'; }, '$.content_rule: enum: not one of ' + factsSchema.properties.content_rule.enum[0]],
    ['a count that is not an integer', (facts) => { facts.repository.trunk_behind = 1.5; }, '$.repository.trunk_behind: type integer expected']
  ];

  for (const [name, mutate, expectedError] of invalidCases) {
    test('rejects ' + name, () => {
      const facts = makeFacts();
      mutate(facts);
      const verdict = validate(facts);
      assert.equal(verdict.ok, false);
      assert.ok(verdict.errors.includes(expectedError), 'errors: ' + JSON.stringify(verdict.errors));
    });
  }

  const presenceValidCases = [
    ['head_state unsafe_name without branch', (facts) => { facts.repository.head_state = 'unsafe_name'; delete facts.repository.branch; }],
    ['a renamed binary history path', (facts) => { Object.assign(facts.history.paths.items[0], { binary: true, added: undefined, removed: undefined }); }],
    ['a modified text history path', (facts) => { Object.assign(facts.history.paths.items[1], { status: 'modified', binary: false, added: 1, removed: 2 }); }],
    ['a copied dirty path with old_path', (facts) => { facts.dirty.paths.items[0].index_status = 'copied'; }],
    ['an untracked dirty path without old_path', (facts) => { Object.assign(facts.dirty.paths.items[0], { index_status: 'untracked', old_path: undefined }); }]
  ];

  for (const [name, mutate] of presenceValidCases) {
    test('accepts ' + name, () => {
      const facts = makeFacts();
      mutate(facts);
      assert.deepEqual(validate(facts), { ok: true, errors: [] });
    });
  }

  const presenceInvalidCases = [
    ['head_state branch without branch', (facts) => delete facts.repository.branch, '$.repository'],
    ['head_state detached with branch', (facts) => { facts.repository.head_state = 'detached'; }, '$.repository'],
    ['head_state unsafe_name with branch', (facts) => { facts.repository.head_state = 'unsafe_name'; }, '$.repository'],
    ['history available without merge_base', (facts) => delete facts.history.merge_base, '$.history'],
    ['history unavailable with merge_base', (facts) => { facts.history.status = 'unavailable'; }, '$.history'],
    ['a renamed history path without old_path', (facts) => delete facts.history.paths.items[0].old_path, '$.history.paths.items[0]'],
    ['a renamed history path without similarity', (facts) => delete facts.history.paths.items[0].similarity, '$.history.paths.items[0]'],
    ['a text history path without added', (facts) => delete facts.history.paths.items[0].added, '$.history.paths.items[0]'],
    ['a text history path without removed', (facts) => delete facts.history.paths.items[0].removed, '$.history.paths.items[0]'],
    ['a binary history path with added', (facts) => { facts.history.paths.items[1].added = 1; }, '$.history.paths.items[1]'],
    ['a binary history path with removed', (facts) => { facts.history.paths.items[1].removed = 1; }, '$.history.paths.items[1]'],
    ['a history path that is not renamed with old_path', (facts) => { facts.history.paths.items[1].old_path = localText('was.bin'); }, '$.history.paths.items[1]'],
    ['a history path that is not renamed with similarity', (facts) => { facts.history.paths.items[1].similarity = 90; }, '$.history.paths.items[1]'],
    ['a renamed dirty path without old_path', (facts) => delete facts.dirty.paths.items[0].old_path, '$.dirty.paths.items[0]'],
    ['a copied dirty path without old_path', (facts) => { Object.assign(facts.dirty.paths.items[0], { index_status: 'copied', old_path: undefined }); }, '$.dirty.paths.items[0]'],
    ['a modified dirty path with old_path', (facts) => { facts.dirty.paths.items[0].index_status = 'modified'; }, '$.dirty.paths.items[0]'],
    ['a fetched reference without item', (facts) => delete facts.references.items[0].item, '$.references.items[0]'],
    ['an unavailable reference with item', (facts) => { facts.references.items[0].lookup = 'unavailable'; }, '$.references.items[0]']
  ];

  for (const [name, mutate, path] of presenceInvalidCases) {
    test('rejects ' + name + ' with one anyOf error', () => {
      const facts = makeFacts();
      mutate(facts);
      assert.deepEqual(validate(facts), { ok: false, errors: [path + ': anyOf: matches no branch'] });
    });
  }

  for (const field of SHORT_FIELDS) {
    const valuePath = field.replace(/\[\]/g, '[0]');
    test(valuePath + ' of ' + CHUNK_LIMIT + ' code points passes and one more fails', () => {
      const facts = makeFacts();
      setFactValue(facts, valuePath, makeCodePoints(CHUNK_LIMIT));
      assert.deepEqual(validate(facts), { ok: true, errors: [] });
      setFactValue(facts, valuePath, makeCodePoints(CHUNK_LIMIT + 1));
      assert.deepEqual(validate(facts), { ok: false, errors: [valuePath + ': maxLength: more than ' + CHUNK_LIMIT + ' characters'] });
    });
  }

  test('a chunk of ' + CHUNK_LIMIT + ' code points passes and one more fails', () => {
    const facts = makeFacts();
    const chunksPath = '$.history.commits.items[0].subject.chunks';
    setFactValue(facts, chunksPath, [makeCodePoints(CHUNK_LIMIT)]);
    assert.deepEqual(validate(facts), { ok: true, errors: [] });
    setFactValue(facts, chunksPath, [makeCodePoints(CHUNK_LIMIT + 1)]);
    assert.deepEqual(validate(facts), { ok: false, errors: [chunksPath + '[0]: maxLength: more than ' + CHUNK_LIMIT + ' characters'] });
  });
});
