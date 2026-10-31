import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const libDir = repoRoot + 'plugin/workflow-src/lib/';
const routingPath = libDir + 'routing.js';
const lib = loadLibs([routingPath]);

const HEAD_SHA = '0123456789abcdef0123456789abcdef01234567';
const NEXT_SHA = 'fedcba9876543210fedcba9876543210fedcba98';
const COUNT = /0|[1-9][0-9]*/;
const SHA = /[0-9a-f]{40}/;
const BRANCH = /[A-Za-z0-9._\/-]+/;
const BOOLEAN = /true|false/;

function parse(text, spec) {
  return structuredClone(lib.parseRoutingLines(text, spec));
}

function joinLines(lines) {
  return lines.join('\n') + '\n';
}

function gatherFactsSpec() {
  return {
    facts_file: { pattern: /\.hivemind\/facts\/facts-[A-Za-z0-9-]+\.json/, required: true },
    facts_lines: { pattern: COUNT, required: true },
    head_state: { pattern: /branch|detached|unsafe_name/, required: true },
    branch: { pattern: BRANCH, required: false },
    head: { pattern: SHA, required: true },
    trunk: { pattern: BRANCH, required: true },
    trunk_freshness: { pattern: /fresh|behind|ahead|diverged|no_remote|no_trunk|fetch_failed|no_local_trunk/, required: true },
    trunk_ahead: { pattern: COUNT, required: true },
    trunk_behind: { pattern: COUNT, required: true },
    cut: { pattern: /none|(pull_requests|references)(,(pull_requests|references))*/, required: true },
    external_texts: { pattern: COUNT, required: true },
    delivery: { pattern: /ready|stop/, required: true },
    delivery_stops: { pattern: /none|[a-z_]+(,[a-z_]+)*/, required: true }
  };
}

function gatherFactsLines() {
  return [
    'facts_file: .hivemind/facts/facts-20261021T101500Z-a1b2c3.json',
    'facts_lines: 42',
    'head_state: branch',
    'branch: feature/409-slice2-pr4-engine-libraries',
    'head: ' + HEAD_SHA,
    'trunk: main',
    'trunk_freshness: fresh',
    'trunk_ahead: 0',
    'trunk_behind: 0',
    'cut: none',
    'external_texts: 2',
    'delivery: ready',
    'delivery_stops: none'
  ];
}

function createWorkingBranchSpec() {
  return {
    branch: { pattern: BRANCH, required: true },
    commit: { pattern: SHA, required: true },
    created: { pattern: BOOLEAN, required: true },
    warning: { pattern: /trunk is stale or diverged from origin; proceeding as acknowledged at preflight|trunk freshness check was skipped/, required: false }
  };
}

function moltSpec() {
  return {
    branch: { pattern: BRANCH, required: true },
    commit: { pattern: SHA, required: true },
    committed: { pattern: BOOLEAN, required: true }
  };
}

function pushBranchSpec() {
  return {
    branch: { pattern: BRANCH, required: true },
    commit: { pattern: SHA, required: true },
    remote: { pattern: /[A-Za-z0-9._-]+/, required: false },
    warning: { pattern: /push was rejected; the branch is not on its remote|no upstream and no origin remote; push deferred/, required: false }
  };
}

function openPlanPrSpec() {
  return {
    url: { pattern: /https:\/\/github\.com\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/pull\/[1-9][0-9]*/, required: true },
    head_ref_oid: { pattern: SHA, required: true },
    created: { pattern: BOOLEAN, required: true },
    warning: { pattern: /.+/, required: false }
  };
}

function bumpTypeSpec() {
  return {
    dominant_row: { pattern: /MAJOR|MINOR|PATCH|NO_BUMP|NONE|MULTI/, required: true },
    verdict: { pattern: /bump_required|no_bump|ask_user/, required: true },
    bump_type: { pattern: /major|minor|patch|none/, required: true },
    rule_applied: { pattern: /[1-6]/, required: true },
    counts: {
      block: {
        major: { pattern: COUNT, required: true },
        minor: { pattern: COUNT, required: true },
        patch: { pattern: COUNT, required: true },
        no_bump: { pattern: COUNT, required: true }
      },
      required: true
    },
    mapped_commits: { pattern: COUNT, required: true },
    dropped_reverts: { pattern: COUNT, required: true }
  };
}

function bumpTypeLines() {
  return [
    'dominant_row: MINOR',
    'verdict: bump_required',
    'bump_type: minor',
    'rule_applied: 3',
    'counts:',
    '  major: 0',
    '  minor: 2',
    '  patch: 1',
    '  no_bump: 4',
    'mapped_commits: 7',
    'dropped_reverts: 2'
  ];
}

function nextWaveSpec() {
  return {
    all_done: { pattern: BOOLEAN, required: true },
    wave: { pattern: /\[\]|\[[A-Za-z0-9._-]+(, [A-Za-z0-9._-]+)*\]/, required: true },
    remaining: { pattern: COUNT, required: true }
  };
}

function assertLineProblem(result, problem, line) {
  assert.deepEqual(result, { ok: false, problem: problem, line: line });
}

function replaceLine(lines, index, replacement) {
  return lines.slice(0, index).concat([replacement], lines.slice(index + 1));
}

describe('header-derived samples parse', () => {
  test('gather-facts on a branch', () => {
    const result = parse(joinLines(gatherFactsLines()), gatherFactsSpec());
    assert.equal(result.ok, true);
    assert.equal(result.values.head_state, 'branch');
    assert.equal(result.values.branch, 'feature/409-slice2-pr4-engine-libraries');
    assert.equal(result.values.delivery_stops, 'none');
    assert.equal(Object.keys(result.values).length, 13);
  });
  test('gather-facts detached with cut lists and stops, optional branch absent', () => {
    const replacements = {
      'head_state: branch': 'head_state: detached',
      'cut: none': 'cut: pull_requests,references',
      'delivery: ready': 'delivery: stop',
      'delivery_stops: none': 'delivery_stops: dirty_paths,history_unavailable'
    };
    const lines = gatherFactsLines()
      .filter((line) => !line.startsWith('branch: '))
      .map((line) => replacements[line] || line);
    const text = joinLines(lines);
    const result = parse(text, gatherFactsSpec());
    assert.equal(result.ok, true);
    assert.equal(Object.prototype.hasOwnProperty.call(result.values, 'branch'), false);
    assert.equal(result.values.cut, 'pull_requests,references');
    assert.equal(result.values.delivery_stops, 'dirty_paths,history_unavailable');
  });
  test('create-working-branch without warning', () => {
    const text = joinLines(['branch: feature/1-x', 'commit: ' + HEAD_SHA, 'created: true']);
    assert.deepEqual(parse(text, createWorkingBranchSpec()), {
      ok: true,
      values: { branch: 'feature/1-x', commit: HEAD_SHA, created: 'true' }
    });
  });
  for (const warning of ['trunk is stale or diverged from origin; proceeding as acknowledged at preflight', 'trunk freshness check was skipped']) {
    test(`create-working-branch with warning "${warning}"`, () => {
      const text = joinLines(['branch: feature/1-x', 'commit: ' + HEAD_SHA, 'created: false', 'warning: ' + warning]);
      const result = parse(text, createWorkingBranchSpec());
      assert.equal(result.ok, true);
      assert.equal(result.values.warning, warning);
      assert.equal(result.values.created, 'false');
    });
  }
  for (const committed of ['true', 'false']) {
    test(`molt committed ${committed}`, () => {
      const text = joinLines(['branch: feature/1-x', 'commit: ' + NEXT_SHA, 'committed: ' + committed]);
      assert.deepEqual(parse(text, moltSpec()), {
        ok: true,
        values: { branch: 'feature/1-x', commit: NEXT_SHA, committed: committed }
      });
    });
  }
  test('push-branch plain', () => {
    const text = joinLines(['branch: feature/1-x', 'commit: ' + HEAD_SHA]);
    assert.deepEqual(parse(text, pushBranchSpec()), { ok: true, values: { branch: 'feature/1-x', commit: HEAD_SHA } });
  });
  test('push-branch with remote and a reject warning', () => {
    const text = joinLines(['branch: feature/1-x', 'commit: ' + HEAD_SHA, 'remote: origin', 'warning: push was rejected; the branch is not on its remote']);
    const result = parse(text, pushBranchSpec());
    assert.equal(result.ok, true);
    assert.equal(result.values.remote, 'origin');
    assert.equal(result.values.warning, 'push was rejected; the branch is not on its remote');
  });
  test('push-branch deferred: warning without remote', () => {
    const text = joinLines(['branch: feature/1-x', 'commit: ' + HEAD_SHA, 'warning: no upstream and no origin remote; push deferred']);
    assert.equal(parse(text, pushBranchSpec()).ok, true);
  });
  test('open-plan-pr without and with warning', () => {
    const base = ['url: https://github.com/brenpike/hivemind/pull/423', 'head_ref_oid: ' + HEAD_SHA, 'created: true'];
    assert.deepEqual(parse(joinLines(base), openPlanPrSpec()), {
      ok: true,
      values: { url: 'https://github.com/brenpike/hivemind/pull/423', head_ref_oid: HEAD_SHA, created: 'true' }
    });
    const warning = 'gh cannot read the push remote as a GitHub repository; the PR head repository was not checked';
    const result = parse(joinLines(base.concat(['warning: ' + warning])), openPlanPrSpec());
    assert.equal(result.values.warning, warning);
  });
  test('bump-type with its counts block', () => {
    assert.deepEqual(parse(joinLines(bumpTypeLines()), bumpTypeSpec()), {
      ok: true,
      values: {
        dominant_row: 'MINOR',
        verdict: 'bump_required',
        bump_type: 'minor',
        rule_applied: '3',
        counts: { major: '0', minor: '2', patch: '1', no_bump: '4' },
        mapped_commits: '7',
        dropped_reverts: '2'
      }
    });
  });
  test('next-wave with a wave list', () => {
    const text = joinLines(['all_done: false', 'wave: [STEP-001, STEP-003]', 'remaining: 4']);
    assert.deepEqual(parse(text, nextWaveSpec()), {
      ok: true,
      values: { all_done: 'false', wave: '[STEP-001, STEP-003]', remaining: '4' }
    });
  });
  test('next-wave all done with an empty wave', () => {
    const text = joinLines(['all_done: true', 'wave: []', 'remaining: 0']);
    assert.equal(parse(text, nextWaveSpec()).values.wave, '[]');
  });
});

describe('line endings', () => {
  const lines = ['branch: feature/1-x', 'commit: ' + HEAD_SHA, 'committed: true'];
  const values = { branch: 'feature/1-x', commit: HEAD_SHA, committed: 'true' };
  test('no trailing LF is accepted', () => {
    assert.equal(parse(lines.join('\n'), moltSpec()).ok, true);
  });
  test('a second trailing LF is a blank line, which is not read', () => {
    assert.deepEqual(parse(lines.join('\n') + '\n\n', moltSpec()), { ok: true, values: values });
  });
  test('a lone LF is a blank line, which is not read', () => {
    assert.deepEqual(parse('\n', moltSpec()), { ok: false, problem: 'missing', key: 'branch' });
    assert.deepEqual(parse('\n', { note: { pattern: /.*/, required: false } }), { ok: true, values: {} });
  });
  test('a blank line in the middle is not read', () => {
    assert.deepEqual(parse('branch: feature/1-x\n\ncommit: ' + HEAD_SHA + '\ncommitted: true\n', moltSpec()), { ok: true, values: values });
  });
  test('CRLF line endings are malformed', () => {
    assertLineProblem(parse(lines.join('\r\n') + '\r\n', moltSpec()), 'malformed', 1);
  });
  test('a CR inside a value is malformed even when the pattern allows it', () => {
    const spec = { note: { pattern: /[\s\S]+/, required: true } };
    assertLineProblem(parse('note: a\rb\n', spec), 'malformed', 1);
  });
  test('a CR on the last line with no trailing LF is malformed', () => {
    assertLineProblem(parse(lines.join('\n') + '\r', moltSpec()), 'malformed', 3);
  });
  test('the empty text has no lines', () => {
    assert.deepEqual(parse('', { note: { pattern: /.*/, required: false } }), { ok: true, values: {} });
    assert.deepEqual(parse('', moltSpec()), { ok: false, problem: 'missing', key: 'branch' });
  });
});

describe('leading whitespace and blocks', () => {
  const bumpLines = bumpTypeLines();
  const bumpValues = parse(joinLines(bumpLines), bumpTypeSpec()).values;
  for (const [label, line] of [['one space', ' dominant_row: MINOR'], ['two spaces', '  dominant_row: MINOR'], ['a tab', '\tdominant_row: MINOR']]) {
    test(`a top-level line led by ${label} is not read`, () => {
      assert.deepEqual(parse(joinLines(replaceLine(bumpLines, 0, line)), bumpTypeSpec()), { ok: false, problem: 'missing', key: 'dominant_row' });
    });
  }
  for (const [label, line] of [['one space', ' major: 0'], ['three spaces', '   major: 0'], ['a tab', '\tmajor: 0'], ['two spaces then a tab', '  \tmajor: 0'], ['only spaces', '    ']]) {
    test(`a block line led by ${label} is not read and closes the block`, () => {
      assert.deepEqual(parse(joinLines(replaceLine(bumpLines, 5, line)), bumpTypeSpec()), { ok: false, problem: 'missing', key: 'counts.major' });
    });
  }
  test('a line that is not a block routing line closes the block, so later block lines are not read', () => {
    for (const line of ['', 'The counts follow.', '  revert: 1', '  Major: 1']) {
      const text = joinLines(bumpLines.slice(0, 6).concat([line], bumpLines.slice(6)));
      assert.deepEqual(parse(text, bumpTypeSpec()), { ok: false, problem: 'missing', key: 'counts.minor' }, JSON.stringify(line));
    }
  });
  test('an indented line after a value line is not read', () => {
    const text = joinLines(bumpLines.slice(0, 4).concat(['  major: 9'], bumpLines.slice(4)));
    assert.deepEqual(parse(text, bumpTypeSpec()), { ok: true, values: bumpValues });
  });
  test('an indented line after the block is closed is not read', () => {
    const text = joinLines(bumpLines.slice(0, 10).concat(['  major: 9', '  extra: 1'], bumpLines.slice(10)));
    assert.deepEqual(parse(text, bumpTypeSpec()), { ok: true, values: bumpValues });
  });
  test('an indented first line is not read', () => {
    assert.deepEqual(parse('  major: 0\n', bumpTypeSpec()), { ok: false, problem: 'missing', key: 'dominant_row' });
  });
  test('a block key with an inline value is malformed', () => {
    assertLineProblem(parse(joinLines(replaceLine(bumpLines, 4, 'counts: 7')), bumpTypeSpec()), 'malformed', 5);
    assertLineProblem(parse(joinLines(replaceLine(bumpLines, 4, 'counts: ')), bumpTypeSpec()), 'malformed', 5);
  });
  test('a value key with no inline value is malformed', () => {
    assertLineProblem(parse(joinLines(replaceLine(bumpLines, 0, 'dominant_row:')), bumpTypeSpec()), 'malformed', 1);
  });
  test('a block key in a block is malformed when the block has no such block entry', () => {
    assertLineProblem(parse(joinLines(replaceLine(bumpLines, 5, '  major:')), bumpTypeSpec()), 'malformed', 6);
  });
  test('a block with no lines is an empty object when its keys are optional', () => {
    const spec = { counts: { block: { major: { pattern: COUNT, required: false } }, required: true }, total: { pattern: COUNT, required: true } };
    assert.deepEqual(parse('counts:\ntotal: 0\n', spec), { ok: true, values: { counts: {}, total: '0' } });
  });
  test('the same key may appear in two different blocks', () => {
    const inner = { major: { pattern: COUNT, required: true } };
    const spec = { before: { block: inner, required: true }, after: { block: inner, required: true } };
    const result = parse('before:\n  major: 1\nafter:\n  major: 2\n', spec);
    assert.deepEqual(result, { ok: true, values: { before: { major: '1' }, after: { major: '2' } } });
  });
  test('a block line does not satisfy a top-level key of the same name', () => {
    const spec = { counts: { block: { major: { pattern: COUNT, required: true } }, required: true }, major: { pattern: COUNT, required: true } };
    assert.deepEqual(parse('counts:\n  major: 1\n', spec), { ok: false, problem: 'missing', key: 'major' });
  });
});

describe('keys and the value split', () => {
  const spec = moltSpec();
  const lines = ['branch: feature/1-x', 'commit: ' + HEAD_SHA, 'committed: true'];
  for (const [label, line] of [
    ['an uppercase key', 'Branch: feature/1-x'],
    ['a key led by a digit', '1branch: feature/1-x'],
    ['a key led by an underscore', '_branch: feature/1-x'],
    ['a key with a dash', 'head-ref: feature/1-x'],
    ['a key with a space', 'my branch: feature/1-x'],
    ['an empty key', ': feature/1-x'],
    ['no separator', 'branch feature/1-x'],
    ['a colon with no space', 'branch:feature/1-x'],
    ['a key with a colon', 'bra:nch: feature/1-x'],
    ['a key named __proto__', '__proto__: x']
  ]) {
    test(`${label} is not a routing line, so it is not read`, () => {
      assert.deepEqual(parse(joinLines(replaceLine(lines, 0, line)), spec), { ok: false, problem: 'missing', key: 'branch' });
      assert.deepEqual(parse(joinLines([line].concat(lines)), spec), { ok: true, values: { branch: 'feature/1-x', commit: HEAD_SHA, committed: 'true' } });
    });
  }
  test('the value is split at the first colon space', () => {
    const noteSpec = { note: { pattern: /.+/, required: true } };
    assert.deepEqual(parse('note: a: b: c\n', noteSpec), { ok: true, values: { note: 'a: b: c' } });
  });
  test('an empty value is checked by the pattern', () => {
    assert.deepEqual(parse('note: \n', { note: { pattern: /.*/, required: true } }), { ok: true, values: { note: '' } });
    assertLineProblem(parse('note: \n', { note: { pattern: /.+/, required: true } }), 'malformed', 1);
  });
  test('trailing whitespace is part of the value', () => {
    assertLineProblem(parse('created: true \n', { created: { pattern: BOOLEAN, required: true } }), 'malformed', 1);
  });
});

describe('patterns are full matches', () => {
  const freshness = { trunk_freshness: { pattern: /fresh|behind/, required: true } };
  for (const value of ['freshly', 'xbehind', 'fresh behind', 'fresh|behind']) {
    test(`an unanchored alternation rejects "${value}"`, () => {
      assertLineProblem(parse('trunk_freshness: ' + value + '\n', freshness), 'malformed', 1);
    });
  }
  for (const value of ['fresh', 'behind']) {
    test(`an unanchored alternation accepts "${value}"`, () => {
      assert.equal(parse('trunk_freshness: ' + value + '\n', freshness).ok, true);
    });
  }
  test('a partial digit match fails', () => {
    assertLineProblem(parse('remaining: 4a\n', { remaining: { pattern: COUNT, required: true } }), 'malformed', 1);
  });
  test('a pattern with its own anchors still works', () => {
    assert.equal(parse('remaining: 4\n', { remaining: { pattern: /^[0-9]+$/, required: true } }).ok, true);
  });
  test('g and y flags do not carry state across lines or calls', () => {
    const sticky = /[0-9]+/gy;
    const spec = { first: { pattern: sticky, required: true }, second: { pattern: sticky, required: true } };
    for (let attempt = 0; attempt < 3; attempt++) {
      assert.equal(parse('first: 12\nsecond: 34\n', spec).ok, true);
    }
  });
  test('the i flag is kept', () => {
    assert.equal(parse('verdict: NO_BUMP\n', { verdict: { pattern: /no_bump/i, required: true } }).ok, true);
  });
  test('a failing value in a block is malformed at its line', () => {
    assertLineProblem(parse(joinLines(replaceLine(bumpTypeLines(), 7, '  patch: some')), bumpTypeSpec()), 'malformed', 8);
  });
});

describe('lines outside the spec, repeats and missing', () => {
  const moltLines = ['branch: feature/1-x', 'commit: ' + HEAD_SHA, 'committed: true'];
  const moltValues = { branch: 'feature/1-x', commit: HEAD_SHA, committed: 'true' };
  const bumpValues = parse(joinLines(bumpTypeLines()), bumpTypeSpec()).values;
  test('a line whose key is not in the spec is not read', () => {
    assert.deepEqual(parse(joinLines(moltLines.concat(['remote: origin'])), moltSpec()), { ok: true, values: moltValues });
  });
  test('a line whose key is not in the block spec is not read', () => {
    const text = joinLines(bumpTypeLines().slice(0, 9).concat(['  revert: 1'], bumpTypeLines().slice(9)));
    assert.deepEqual(parse(text, bumpTypeSpec()), { ok: true, values: bumpValues });
  });
  test('the problem codes are missing and malformed only', () => {
    assert.deepEqual([...lib.routingProblems()].sort(), ['malformed', 'missing']);
  });
  test('a key of the block spec only is not read at top level', () => {
    assert.deepEqual(parse('major: 1\n', bumpTypeSpec()), { ok: false, problem: 'missing', key: 'dominant_row' });
  });
  test('an Object.prototype name is not read unless the spec names it', () => {
    assert.deepEqual(parse('constructor: x\n', moltSpec()), { ok: false, problem: 'missing', key: 'branch' });
    assert.deepEqual(parse('tostring: x\nhasownproperty: y\n', {}), { ok: true, values: {} });
    assert.deepEqual(parse('constructor: x\n', { constructor: { pattern: /x/, required: true } }), { ok: true, values: { constructor: 'x' } });
  });
  test('a later conflicting line of a top-level key is not read, so the first line wins', () => {
    const text = joinLines(['branch: feature/1-x', 'commit: ' + HEAD_SHA, 'branch: feature/2-y', 'committed: true', 'committed: false']);
    assert.deepEqual(parse(text, moltSpec()), { ok: true, values: moltValues });
  });
  test('a later line of a key already read is not read even when off its pattern', () => {
    const text = joinLines(moltLines.concat(['committed: maybe', 'commit: not-a-sha', 'branch:']));
    assert.deepEqual(parse(text, moltSpec()), { ok: true, values: moltValues });
  });
  test('a repeated block key opens no block', () => {
    assert.deepEqual(parse(joinLines(bumpTypeLines().concat(['counts:'])), bumpTypeSpec()), { ok: true, values: bumpValues });
    assert.deepEqual(parse(joinLines(bumpTypeLines().concat(['counts: 7', '  major: x'])), bumpTypeSpec()), { ok: true, values: bumpValues });
  });
  test('a repeated block cannot give a key its first block lacks', () => {
    const lines = bumpTypeLines().filter((line) => line !== '  patch: 1').concat(['counts:', '  patch: 1']);
    assert.deepEqual(parse(joinLines(lines), bumpTypeSpec()), { ok: false, problem: 'missing', key: 'counts.patch' });
  });
  test('a later line of a key inside a block is not read and keeps the block open', () => {
    const text = joinLines(bumpTypeLines().slice(0, 6).concat(['  major: 9'], bumpTypeLines().slice(6)));
    assert.deepEqual(parse(text, bumpTypeSpec()), { ok: true, values: bumpValues });
  });
  test('a required top-level key that is absent is missing by name', () => {
    const text = joinLines(['branch: feature/1-x', 'committed: true']);
    assert.deepEqual(parse(text, moltSpec()), { ok: false, problem: 'missing', key: 'commit' });
  });
  test('missing keys are reported in spec order', () => {
    assert.deepEqual(parse('commit: ' + HEAD_SHA + '\n', moltSpec()), { ok: false, problem: 'missing', key: 'branch' });
  });
  test('a required block that is absent is missing by name', () => {
    const text = joinLines(bumpTypeLines().filter((line) => !line.startsWith(' ') && line !== 'counts:'));
    assert.deepEqual(parse(text, bumpTypeSpec()), { ok: false, problem: 'missing', key: 'counts' });
  });
  test('a required key absent from its block is missing as block.key', () => {
    const text = joinLines(bumpTypeLines().filter((line) => line !== '  patch: 1'));
    assert.deepEqual(parse(text, bumpTypeSpec()), { ok: false, problem: 'missing', key: 'counts.patch' });
  });
  test('top-level missing keys come before block missing keys', () => {
    const text = joinLines(bumpTypeLines().filter((line) => line !== '  patch: 1' && !line.startsWith('dropped_reverts')));
    assert.deepEqual(parse(text, bumpTypeSpec()), { ok: false, problem: 'missing', key: 'dropped_reverts' });
  });
  test('the required keys of an optional block that is absent are not missing', () => {
    const spec = bumpTypeSpec();
    spec.counts.required = false;
    const text = joinLines(bumpTypeLines().filter((line) => !line.startsWith(' ') && line !== 'counts:'));
    assert.equal(parse(text, spec).ok, true);
  });
  test('a line problem wins over a missing key', () => {
    assertLineProblem(parse('branch: feature/1-x\ncommitted: yes\n', moltSpec()), 'malformed', 2);
  });
  test('the first line problem wins', () => {
    assertLineProblem(parse('bogus: 1\ncommitted: yes\nbranch: \n', moltSpec()), 'malformed', 2);
  });
});

describe('lines a relay may add are not read', () => {
  const moltLines = ['branch: feature/1-x', 'commit: ' + HEAD_SHA, 'committed: true'];
  const moltValues = { branch: 'feature/1-x', commit: HEAD_SHA, committed: 'true' };
  test('open-plan-pr with git push remote hint lines before its routing lines, the issue 445 shape', () => {
    const lines = [
      'remote: ',
      'remote: Create a pull request for \'bugfix/1-x\' on GitHub by visiting:',
      'remote:      https://github.com/brenpike/hivemind/pull/new/bugfix/1-x',
      'remote:',
      'To github.com:brenpike/hivemind.git',
      ' * [new branch]      bugfix/1-x -> bugfix/1-x',
      'url: https://github.com/brenpike/hivemind/pull/423',
      'head_ref_oid: ' + HEAD_SHA,
      'created: true'
    ];
    assert.deepEqual(parse(joinLines(lines), openPlanPrSpec()), {
      ok: true,
      values: { url: 'https://github.com/brenpike/hivemind/pull/423', head_ref_oid: HEAD_SHA, created: 'true' }
    });
  });
  test('an added line that is the first line of a spec key is read, and pauses when off its pattern', () => {
    const lines = ['remote: Create a pull request for \'bugfix/1-x\' on GitHub by visiting:', 'branch: feature/1-x', 'commit: ' + HEAD_SHA, 'remote: origin'];
    assertLineProblem(parse(joinLines(lines), pushBranchSpec()), 'malformed', 1);
  });
  test('bump-type with a prose line after its routing lines, the issue 464 shape', () => {
    const lines = bumpTypeLines().concat(['', 'Verdict: bump_required, so the version moves to 7.5.4.']);
    assert.deepEqual(parse(joinLines(lines), bumpTypeSpec()), parse(joinLines(bumpTypeLines()), bumpTypeSpec()));
    assert.equal(parse(joinLines(lines), bumpTypeSpec()).ok, true);
  });
  test('code fences around the routing lines', () => {
    for (const fence of ['```', '```text']) {
      assert.deepEqual(parse(joinLines([fence].concat(moltLines, ['```'])), moltSpec()), { ok: true, values: moltValues });
    }
    const fenced = ['```yaml'].concat(bumpTypeLines(), ['```']);
    assert.deepEqual(parse(joinLines(fenced), bumpTypeSpec()), parse(joinLines(bumpTypeLines()), bumpTypeSpec()));
  });
  test('a whole repeated routing block', () => {
    assert.deepEqual(parse(joinLines(moltLines.concat(moltLines)), moltSpec()), { ok: true, values: moltValues });
    const factsResult = parse(joinLines(gatherFactsLines().concat(gatherFactsLines())), gatherFactsSpec());
    assert.deepEqual(factsResult, parse(joinLines(gatherFactsLines()), gatherFactsSpec()));
    const bumpResult = parse(joinLines(bumpTypeLines().concat(replaceLine(bumpTypeLines(), 5, '  major: 9'))), bumpTypeSpec());
    assert.deepEqual(bumpResult, parse(joinLines(bumpTypeLines()), bumpTypeSpec()));
  });
  test('prose between top-level lines', () => {
    const lines = ['The script printed:', 'branch: feature/1-x', 'Then the commit:', 'commit: ' + HEAD_SHA, 'And it committed.', 'committed: true', 'Done.'];
    assert.deepEqual(parse(joinLines(lines), moltSpec()), { ok: true, values: moltValues });
  });
});

describe('a problem never echoes a value', () => {
  const secret = 'leak_marker_value';
  const cases = [
    ['a key not in the spec', 'leak_marker_value: x\n', moltSpec()],
    ['a value on a line not in the spec', 'remote: ' + secret + '\n', moltSpec()],
    ['malformed value', 'committed: ' + secret + '\n', moltSpec()],
    ['malformed key', 'Leak_marker_value: 1\n', moltSpec()],
    ['a later line of a key', 'branch: a\nbranch: ' + secret + '\n', moltSpec()],
    ['blank line', 'branch: ' + secret + '\n\n', moltSpec()],
    ['missing', 'branch: ' + secret + '\n', moltSpec()],
    ['missing in block', 'counts:\n  major: ' + secret + '\n', { counts: { block: { major: { pattern: /.+/, required: true }, minor: { pattern: /.+/, required: true } }, required: true } }]
  ];
  for (const [label, text, spec] of cases) {
    test(label, () => {
      const result = parse(text, spec);
      assert.equal(result.ok, false);
      assert.ok(lib.routingProblems().includes(result.problem));
      const fieldNames = Object.keys(result).sort();
      assert.ok(
        JSON.stringify(fieldNames) === JSON.stringify(['key', 'ok', 'problem']) || JSON.stringify(fieldNames) === JSON.stringify(['line', 'ok', 'problem']),
        JSON.stringify(fieldNames)
      );
      assert.equal(JSON.stringify(result).toLowerCase().includes(secret), false);
      if (Object.prototype.hasOwnProperty.call(result, 'line')) {
        assert.ok(Number.isInteger(result.line) && result.line >= 1);
      }
    });
  }
});

describe('invalid input throws', () => {
  for (const text of [null, undefined, 3, ['a: b'], { a: 'b' }]) {
    test(`text ${JSON.stringify(text)} throws`, () => {
      assert.throws(() => lib.parseRoutingLines(text, moltSpec()), /text must be a string/);
    });
  }
  const badSpecs = [
    ['null spec', null, /spec must be a plain object/],
    ['array spec', [], /spec must be a plain object/],
    ['a spec key that is not a routing key', { 'Bad-Key': { pattern: /x/, required: true } }, /not a routing key/],
    ['an entry that is not an object', { note: /x/ }, /must be a plain object/],
    ['an entry with no required', { note: { pattern: /x/ } }, /required must be a boolean/],
    ['an entry with a string required', { note: { pattern: /x/, required: 'yes' } }, /required must be a boolean/],
    ['an entry with neither pattern nor block', { note: { required: true } }, /exactly one of pattern and block/],
    ['an entry with both pattern and block', { note: { pattern: /x/, block: {}, required: true } }, /exactly one of pattern and block/],
    ['an entry with an unknown field', { note: { pattern: /x/, required: true, optional: false } }, /unknown field/],
    ['a string pattern', { note: { pattern: 'x', required: true } }, /pattern must be a RegExp/],
    ['a block inside a block', { outer: { block: { inner: { block: {}, required: true } }, required: true } }, /block inside a block/],
    ['a block spec that is not an object', { outer: { block: null, required: true } }, /must be a plain object/]
  ];
  for (const [label, spec, message] of badSpecs) {
    test(`${label} throws`, () => {
      assert.throws(() => lib.parseRoutingLines('', spec), message);
    });
  }
  test('an invalid spec throws even when the text is clean', () => {
    assert.throws(() => lib.parseRoutingLines('note: x\n', { note: { pattern: 'x', required: true } }), /pattern must be a RegExp/);
  });
});

describe('routing.js lib rules', () => {
  const source = readFileSync(routingPath, 'utf8').replace(/\r/g, '');
  test('no module syntax, clock, randomness, em dash or hash-digit', () => {
    assert.doesNotMatch(source, /\bimport\b|\bexport\b|\brequire\b/);
    assert.doesNotMatch(source, /\bDate\b/);
    assert.doesNotMatch(source, /Math\.random/);
    assert.doesNotMatch(source, /\u2014/);
    assert.doesNotMatch(source, /#\d/);
  });
  test('opens with a contract header', () => {
    assert.match(source, /^\/\*\n \* [a-z]+\.js: [\s\S]*?\n \* Inputs\n[\s\S]*?\n \* Outputs\n[\s\S]*?\n \* Invariants\n[\s\S]*?\n \* Why\n[\s\S]*?\*\//);
  });
  test('declares only top-level functions', () => {
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
  test('no function name is shared with another lib or the analysis-only main', () => {
    const otherPaths = readdirSync(libDir)
      .filter((name) => name.endsWith('.js') && name !== 'routing.js')
      .map((name) => libDir + name)
      .concat([repoRoot + 'plugin/workflow-src/analysis-only/main.js']);
    const otherNames = new Set();
    for (const path of otherPaths) {
      for (const match of readFileSync(path, 'utf8').matchAll(/^(?:async\s+)?function\s+([A-Za-z0-9_]+)/gm)) {
        otherNames.add(match[1]);
      }
    }
    for (const match of source.matchAll(/^function\s+([A-Za-z0-9_]+)/gm)) {
      assert.equal(otherNames.has(match[1]), false, `${match[1]} is also declared outside routing.js`);
    }
  });
});
