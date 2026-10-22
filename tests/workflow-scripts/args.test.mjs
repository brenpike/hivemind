import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const sourceRoot = repoRoot + 'plugin/workflow-src/';
const libDir = sourceRoot + 'lib/';
const lib = loadLibs([libDir + 'result.js', libDir + 'args.js']);
const NEW_LIBS = ['args.js', 'facts.js', 'identifier.js'];

const RUN_NOUN = 'delivery';
const BAD_TRUNK = 'The trunk launch arg must be a non-blank string, so the delivery did not start.';
const BAD_REFERENCES = 'The references launch arg must be a list of issue or pull request numbers, so the delivery did not start.';

function read(value) {
  return structuredClone(value);
}

function listReferences(count) {
  return Array.from({ length: count }, (_, index) => index + 1);
}

describe('readArgsObject', () => {
  test('a string is the request itself', () => {
    assert.deepEqual(read(lib.readArgsObject('Ship it')), { request: 'Ship it' });
  });
  test('a plain object passes through', () => {
    const args = { request: 'r', trunk: 'develop' };
    assert.equal(lib.readArgsObject(args), args);
  });
  for (const rawArgs of [undefined, null, 5, true, ['r']]) {
    test(`${JSON.stringify(rawArgs)} reads as an empty object`, () => {
      assert.deepEqual(read(lib.readArgsObject(rawArgs)), {});
    });
  }
});

describe('readTrunk', () => {
  test('an absent trunk is main', () => {
    assert.equal(lib.defaultTrunk(), 'main');
    assert.deepEqual(read(lib.readTrunk({}, RUN_NOUN)), { trunk: 'main' });
  });
  test('a non-blank string passes through as it is', () => {
    assert.deepEqual(read(lib.readTrunk({ trunk: 'release/2.x' }, RUN_NOUN)), { trunk: 'release/2.x' });
  });
  for (const trunk of ['', ' ', '\n', null, 5, ['main'], { name: 'main' }]) {
    test(`trunk ${JSON.stringify(trunk)} is a problem naming the delivery`, () => {
      assert.deepEqual(read(lib.readTrunk({ trunk: trunk }, RUN_NOUN)), { problem: BAD_TRUNK });
    });
  }
});

describe('readReferences', () => {
  test('absent references are none', () => {
    assert.deepEqual(read(lib.readReferences({}, RUN_NOUN)), { references: [] });
  });
  test('numbers and digit strings become digit strings, deduplicated in order', () => {
    assert.deepEqual(read(lib.readReferences({ references: [12, '7', '12', 7, '007'] }, RUN_NOUN)), { references: ['12', '7', '007'] });
  });
  for (const references of ['12', 12, null, {}, [0], [-1], [1.5], [Number.MAX_SAFE_INTEGER + 1], ['1a'], [' 1'], ['1\n'], [''], [null], [[1]]]) {
    test(`references ${JSON.stringify(references)} is a problem naming the delivery`, () => {
      assert.deepEqual(read(lib.readReferences({ references: references }, RUN_NOUN)), { problem: BAD_REFERENCES });
    });
  }
  test('20 distinct references pass and 21 are a problem that counts them', () => {
    assert.equal(lib.maxReferences(), 20);
    assert.equal(read(lib.readReferences({ references: listReferences(20) }, RUN_NOUN)).references.length, 20);
    assert.deepEqual(read(lib.readReferences({ references: listReferences(21) }, RUN_NOUN)), {
      problem: 'The references launch arg names 21 issues or pull requests, more than the 20 the facts step takes, so the delivery did not start.'
    });
  });
  test('the limit counts references after deduplication', () => {
    const references = [...listReferences(20), ...listReferences(20).map(String)];
    assert.equal(read(lib.readReferences({ references: references }, RUN_NOUN)).references.length, 20);
  });
});

describe('readLaunchInputs', () => {
  test('returns trunk and references together', () => {
    assert.deepEqual(read(lib.readLaunchInputs({ trunk: 'develop', references: [3] }, RUN_NOUN)), { trunk: 'develop', references: ['3'] });
  });
  test('a bad trunk is reported before bad references', () => {
    assert.deepEqual(read(lib.readLaunchInputs({ trunk: 5, references: 'bad' }, RUN_NOUN)), { problem: BAD_TRUNK });
  });
  test('the analysis noun gives the analysis-only text', () => {
    assert.deepEqual(read(lib.readLaunchInputs({ trunk: ' ' }, 'analysis')), { problem: 'The trunk launch arg must be a non-blank string, so the analysis did not start.' });
  });
  for (const runNoun of [undefined, '', ' ', 5]) {
    test(`run noun ${JSON.stringify(runNoun)} throws`, () => {
      assert.throws(() => lib.readLaunchInputs({}, runNoun), /runNoun must be a non-blank string/);
    });
  }
  test('describeRunNoun names the run after "the"', () => {
    assert.equal(lib.describeRunNoun(RUN_NOUN), 'the delivery');
  });
});

describe('pause rounds', () => {
  test('roundKey names round N', () => {
    assert.equal(lib.roundKey(1), 'round-1');
    assert.equal(lib.roundKey(3), 'round-3');
  });
  test('stored answers are read only from a plain answers object', () => {
    const answers = { 'round-1': 'R1' };
    assert.equal(lib.readStoredAnswers({ answers: answers }), answers);
    for (const notAnswers of [undefined, null, 'R1', ['R1']]) {
      assert.deepEqual(read(lib.readStoredAnswers({ answers: notAnswers })), {}, JSON.stringify(notAnswers));
    }
    assert.deepEqual(read(lib.readStoredAnswers({ 'round-1': 'R1' })), {});
  });
  test('a stored reply is read only when it is a non-blank string', () => {
    const stored = { 'round-1': 'R1', 'round-2': ' ', 'round-3': 7 };
    assert.equal(lib.readStoredReply(stored, 1), 'R1');
    assert.equal(lib.readStoredReply(stored, 2), undefined);
    assert.equal(lib.readStoredReply(stored, 3), undefined);
    assert.equal(lib.readStoredReply(stored, 4), undefined);
  });
  test('a pending reply needs answers present and a non-blank reply', () => {
    assert.equal(lib.replyField(), 'reply');
    assert.equal(lib.readPendingReply({ answers: {}, reply: 'yes' }), 'yes');
    assert.equal(lib.readPendingReply({ reply: 'yes' }), undefined);
    assert.equal(lib.readPendingReply({ answers: ['x'], reply: 'yes' }), undefined);
    assert.equal(lib.readPendingReply({ answers: {}, reply: ' ' }), undefined);
    assert.equal(lib.readPendingReply({ answers: {}, reply: 5 }), undefined);
  });
  test('resume args are {answers} alone, keyed by round', () => {
    assert.deepEqual(read(lib.buildResumeArgs(['A', 'B'])), { answers: { 'round-1': 'A', 'round-2': 'B' } });
    assert.deepEqual(read(lib.buildResumeArgs([])), { answers: {} });
  });
});

function listWorkflowMains() {
  return readdirSync(sourceRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name !== 'lib')
    .map((entry) => sourceRoot + entry.name + '/main.js')
    .filter((path) => existsSync(path));
}

function listFunctionNames(source) {
  return [...source.matchAll(/^(?:async\s+)?function\s+([A-Za-z0-9_$]+)/gm)].map((match) => match[1]);
}

describe('the new libs are plain workflow libs', () => {
  for (const name of NEW_LIBS) {
    const path = libDir + name;
    const source = readFileSync(path, 'utf8').replace(/\r/g, '');
    test(`${name} has no module syntax, clock, randomness, em dash or hash-digit, comments included`, () => {
      assert.doesNotMatch(source, /\bimport\b|\bexport\b|\brequire\b/);
      assert.doesNotMatch(source, /\bDate\b/);
      assert.doesNotMatch(source, /Date\(|new Date\(\)/);
      assert.doesNotMatch(source, /Math\.random/);
      assert.doesNotMatch(source, /\u2014/);
      assert.doesNotMatch(source, /#\d/);
    });
    test(`${name} opens with a contract header`, () => {
      assert.match(source, /^\/\*\n \* [a-z]+\.js: [\s\S]*?\n \* Inputs\n[\s\S]*?\n \* Outputs\n[\s\S]*?\n \* Invariants\n[\s\S]*?\n \* Why\n[\s\S]*?\*\//);
    });
    test(`${name} declares only top-level functions`, () => {
      assert.doesNotMatch(source, /^(const|let|var|class)\s/m);
      const context = vm.createContext({});
      const before = new Set(Object.keys(context));
      vm.runInContext(source, context);
      const added = Object.keys(context).filter((key) => !before.has(key));
      assert.ok(added.length > 0);
      for (const key of added) {
        assert.equal(typeof context[key], 'function', `${key} is not a function`);
      }
    });
    test(`${name} shares no function name with another lib or a workflow main`, () => {
      const otherPaths = readdirSync(libDir)
        .filter((fileName) => fileName.endsWith('.js') && fileName !== name)
        .map((fileName) => libDir + fileName)
        .concat(listWorkflowMains());
      const taken = new Map();
      for (const otherPath of otherPaths) {
        listFunctionNames(readFileSync(otherPath, 'utf8')).forEach((functionName) => taken.set(functionName, otherPath));
      }
      for (const functionName of listFunctionNames(source)) {
        assert.equal(taken.has(functionName), false, `${functionName} is also declared in ${taken.get(functionName)}`);
      }
    });
  }
  test('the workflow mains checked include analysis-only', () => {
    assert.ok(listWorkflowMains().includes(sourceRoot + 'analysis-only/main.js'));
  });
});
