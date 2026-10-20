import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/schema.js']);
const factsSchema = JSON.parse(readFileSync(repoRoot + 'plugin/references/facts-schema.json', 'utf8'));

const GITHUB_ROOTS = ['$.pull_requests.items[]', '$.references.items[].item'];
const ENUM_LISTS = ['$.summary.cut', '$.summary.delivery_stops'];

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

function localText(text) {
  return { length: text.length, chunks: text === '' ? [] : [text] };
}

function externalText(text) {
  return { origin: 'external', ...localText(text) };
}

function makeFacts() {
  return {
    schema_version: 1,
    content_rule: factsSchema.properties.content_rule.enum[0],
    summary: { cut: [], delivery: 'stop', delivery_stops: ['dirty_paths', 'closed_pr_on_branch'] },
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
            title: externalText('A title'),
            author: 'someone',
            body: externalText(''),
            comments: { complete: true, total: 1, items: [{ origin: 'external', author: 'someone', url: 'https://github.com/o/r/issues/7#c', body: externalText('a comment') }] }
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

  test('content_rule and schema_version are single-value enums', () => {
    assert.equal(factsSchema.properties.content_rule.enum.length, 1);
    assert.match(factsSchema.properties.content_rule.enum[0], /external/);
    assert.deepEqual(factsSchema.properties.schema_version.enum, [1]);
  });

  test('a full sample document is valid', () => {
    assert.deepEqual(validate(makeFacts()), { ok: true, errors: [] });
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
    ['an unknown property', (facts) => { facts.repository.extra = 'x'; }, '$.repository: additionalProperties: unexpected extra'],
    ['a list without complete', (facts) => delete facts.history.commits.complete, '$.history.commits: required: missing complete'],
    ['a list without total', (facts) => delete facts.dirty.paths.total, '$.dirty.paths: required: missing total'],
    ['a blank chunk', (facts) => { facts.history.commits.items[0].subject.chunks = ['   ']; }, '$.history.commits.items[0].subject.chunks[0]: type string: blank'],
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
});
