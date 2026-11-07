import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const libDir = repoRoot + 'plugin/workflow-src/lib/';
const lib = loadLibs([libDir + 'schema.js', libDir + 'decide.js']);
const doc = readFileSync(repoRoot + 'plugin/governance/decision-autonomy.md', 'utf8').replace(/\r/g, '');
const askPhrase = '`decide()` asks only for';

function isolateTierA(text) {
  const lines = text.split('\n');
  const start = lines.findIndex((line) => /^#{1,6}\s+Tier A\b/.test(line));
  assert.notEqual(start, -1, 'Tier A heading not found');
  const level = lines[start].match(/^#+/)[0].length;
  const tail = lines.slice(start + 1);
  const end = tail.findIndex((line) => {
    const heading = line.match(/^(#+)\s/);
    return heading !== null && heading[1].length <= level;
  });
  return end === -1 ? tail : tail.slice(0, end);
}

function extractAskLine(tierA) {
  const matches = tierA.filter((line) => line.includes(askPhrase));
  assert.equal(matches.length, 1, `expected exactly one line containing ${askPhrase}, found ${matches.length}`);
  return matches[0];
}

function extractCodes(line) {
  const tail = line.slice(line.indexOf(askPhrase) + askPhrase.length);
  return [...tail.matchAll(/`([^`]+)`/g)].map((match) => match[1]);
}

describe('Tier A Ask Set parity', () => {
  const line = extractAskLine(isolateTierA(doc));

  test('Tier A line lists the askReasons codes in order', () => {
    assert.deepEqual(extractCodes(line), structuredClone(lib.askReasons()));
  });

  test('Tier A line lists no listReasons code', () => {
    const codes = extractCodes(line);
    for (const name of lib.listReasons()) {
      assert.equal(codes.includes(name), false, name);
      assert.equal(line.includes(name), false, name);
    }
  });
});
