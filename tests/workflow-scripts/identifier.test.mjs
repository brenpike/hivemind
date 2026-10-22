import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const allowlistPath = repoRoot + 'plugin/skills/_shared/allowlist.sh';
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/identifier.js']);

const ORACLE_SCRIPT = [
  '. "$1"',
  'shift',
  'for value in "$@"; do',
  '  if hivemind_assert_identifier "$value"; then printf \'1\'; else printf \'0\'; fi',
  'done'
].join('\n');

const CORPUS = [
  'main', 'develop', 'feature/409-slice2-pr6-delivery-core', 'release/1.2.3', 'a', 'A', '0', '_', '.', '/',
  'a.b', 'a_b', 'a-b', 'a/b/c', '.hidden', 'trailing/', '/leading', 'x-', 'a.b.c', 'v1.0',
  '', '-', '-x', '--force', 'a-', '..', 'a..b', '...', 'a/../b', '../x', 'x/..',
  'a b', ' a', 'a ', 'a\tb', 'a\nb', 'a\n', '\na', 'a\rb', 'a\r',
  'a$b', '$HOME', 'a`b`', 'a;b', 'a&b', 'a|b', 'a*b', 'a?b', 'a[b]', 'a{b}', 'a(b)', 'a<b', 'a>b',
  'a\\b', 'a"b', 'a\'b', 'a:b', 'a@b', 'a#b', 'a~b', 'a^b', 'a+b', 'a=b', 'a,b', 'a%b', 'a!b',
  '\u00e9', 'caf\u00e9', 'a\u00a0b', '\u0430', 'a\u202eb', '\u4e2d\u6587', 'x\u0001y', '\u007f'
];

function runOracle(values) {
  const run = spawnSync('bash', ['-c', ORACLE_SCRIPT, 'identifier-oracle', allowlistPath, ...values], { encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stdout.length, values.length, 'one verdict per value');
  return Array.from(run.stdout, (verdict) => verdict === '1');
}

describe('isGitIdentifier parity with hivemind_assert_identifier', () => {
  const verdicts = runOracle(CORPUS);
  CORPUS.forEach((value, index) => {
    test(`${JSON.stringify(value)} gets the shell verdict ${verdicts[index]}`, () => {
      assert.equal(lib.isGitIdentifier(value), verdicts[index]);
    });
  });
  test('the corpus holds both verdicts', () => {
    assert.ok(verdicts.includes(true));
    assert.ok(verdicts.includes(false));
  });
  for (const locale of ['C', 'C.UTF-8']) {
    test(`the shell verdicts do not change under LC_ALL=${locale}`, () => {
      const run = spawnSync('bash', ['-c', ORACLE_SCRIPT, 'identifier-oracle', allowlistPath, ...CORPUS], {
        encoding: 'utf8',
        env: { ...process.env, LC_ALL: locale }
      });
      assert.equal(run.status, 0, run.stderr);
      assert.deepEqual(Array.from(run.stdout, (verdict) => verdict === '1'), verdicts);
    });
  }
});

describe('isGitIdentifier on values the shell cannot be given', () => {
  for (const value of [undefined, null, 5, true, ['main'], { name: 'main' }]) {
    test(`${JSON.stringify(value)} is not an identifier`, () => {
      assert.equal(lib.isGitIdentifier(value), false);
    });
  }
  test('a NUL byte is not an identifier', () => {
    assert.equal(lib.isGitIdentifier('a\u0000b'), false);
  });
});

describe('gitIdentifierPattern', () => {
  test('is anchored, has no flags and is a fresh RegExp each call', () => {
    const pattern = lib.gitIdentifierPattern();
    assert.equal(pattern.flags, '');
    assert.ok(pattern.source.startsWith('^'));
    assert.ok(pattern.source.endsWith('$'));
    assert.notEqual(lib.gitIdentifierPattern(), pattern);
  });
  test('a trailing line feed fails it', () => {
    assert.equal(lib.gitIdentifierPattern().test('main\n'), false);
  });
});
