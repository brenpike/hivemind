import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFile, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import vm from 'node:vm';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const libDir = repoRoot + 'plugin/workflow-src/lib/';
const wavesPath = libDir + 'waves.js';
const enginePath = repoRoot + 'plugin/skills/next-wave/scripts/next-wave.sh';
const fixturesDir = repoRoot + 'tests/next-wave/';
const lib = loadLibs([wavesPath]);

const ORACLE_CONCURRENCY = 8;
const DEFAULT_SEED = 20261021;
const seedText = process.env.WAVES_PARITY_SEED;
const SEED = seedText === undefined || seedText === '' ? DEFAULT_SEED : Number(seedText);

const STEP_ID_PROBLEM = 'not a step id (1 to 64 of A-Z a-z 0-9 . _ -)';

const workRoot = realpathSync(mkdtempSync(join(tmpdir(), 'hivemind-waves-parity-')));
const gitRoot = join(workRoot, 'checkout');
mkdirSync(gitRoot);
const gitInit = spawnSync('git', ['init', '-q', gitRoot], { encoding: 'utf8' });
let oracleRunCount = 0;

after(() => {
  rmSync(workRoot, { recursive: true, force: true });
  assert.equal(existsSync(workRoot), false, `temp folder ${workRoot} was not removed`);
});

function runOracleRaw(ledger) {
  oracleRunCount += 1;
  const runId = 'parity-' + oracleRunCount;
  const runDir = join(gitRoot, '.hivemind', 'runs', runId);
  mkdirSync(runDir, { recursive: true });
  writeFileSync(join(runDir, 'state.json'), JSON.stringify({ ...ledger, run: { id: runId } }));
  return new Promise((resolve) => {
    execFile('bash', [enginePath, runId], { cwd: gitRoot, encoding: 'utf8' }, (error, stdout, stderr) => {
      resolve({ status: error === null ? 0 : error.code, stdout: stdout, stderr: stderr });
    });
  });
}

async function runOracle(ledger) {
  const result = await runOracleRaw(ledger);
  if (result.status === 0) {
    const match = /^all_done: (true|false)\nwave: \[(.*)\]\nremaining: (\d+)\n$/.exec(result.stdout);
    if (match === null) {
      return { ok: 'unparsed', stdout: result.stdout };
    }
    const wave = match[2] === '' ? [] : match[2].split(', ');
    return { ok: true, all_done: match[1] === 'true', wave: wave, remaining: Number(match[3]) };
  }
  const blocker = /^blocker: (.*)\n$/.exec(result.stderr);
  if (result.status === 1 && result.stdout === '' && blocker !== null) {
    return { ok: false, problem: blocker[1] };
  }
  return { ok: 'crash', status: result.status, stdout: result.stdout, stderr: result.stderr };
}

function readJqDefault(value) {
  return value === undefined || value === null || value === false ? 0 : value;
}

function listJqValues(value) {
  if (Array.isArray(value)) {
    return value;
  }
  if (value !== null && typeof value === 'object') {
    return Object.values(value);
  }
  return [];
}

function isJqObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function deriveDoneIds(ledger) {
  const currentEpoch = readJqDefault(isJqObject(ledger.plan) ? ledger.plan.epoch : undefined);
  const credits = [];
  for (const event of listJqValues(ledger.events)) {
    if (!isJqObject(event) || !isDeepStrictEqual(readJqDefault(event.plan_epoch), currentEpoch)) {
      continue;
    }
    if (!isJqObject(event.outputs)) {
      continue;
    }
    for (const credit of listJqValues(event.outputs.completed_steps)) {
      if (typeof credit === 'string' && !credits.includes(credit)) {
        credits.push(credit);
      }
    }
  }
  return credits;
}

function runSubject(ledger) {
  const steps = isJqObject(ledger.plan) ? ledger.plan.steps : undefined;
  return structuredClone(lib.computeWave(steps, deriveDoneIds(ledger)));
}

function stageLedger(ledger) {
  return JSON.parse(JSON.stringify(ledger));
}

async function assertParity(label, ledger, context = '') {
  const staged = stageLedger(ledger);
  const oracle = await runOracle(staged);
  const subject = runSubject(staged);
  assert.deepEqual(subject, oracle, `${label}${context}\nledger: ${JSON.stringify(staged)}\nnext-wave.sh: ${JSON.stringify(oracle)}\nwaves.js: ${JSON.stringify(subject)}`);
  return oracle;
}

function readFixture(name) {
  return JSON.parse(readFileSync(fixturesDir + name, 'utf8'));
}

function completedEvent(stepIds, extra = {}) {
  return { state: 'implement_step', ...extra, outputs: { completed_steps: stepIds } };
}

function ledgerWithDone(steps, doneIds) {
  return { plan: { steps: steps }, events: [completedEvent(doneIds)] };
}

function withEvents(fixture, events) {
  return { ...fixture, events: events };
}

function mutateFixture(fixture, applyMutation) {
  const copy = structuredClone(fixture);
  applyMutation(copy);
  return copy;
}

function createRandom(seed) {
  let state = seed >>> 0;
  return function nextRandom() {
    state = (state + 0x6D2B79F5) >>> 0;
    let mixed = state;
    mixed = Math.imul(mixed ^ (mixed >>> 15), mixed | 1);
    mixed ^= mixed + Math.imul(mixed ^ (mixed >>> 7), mixed | 61);
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 4294967296;
  };
}

function pickOne(random, list) {
  return list[Math.floor(random() * list.length)];
}

function stepIdAt(index) {
  return 'STEP-' + String(index + 1).padStart(3, '0');
}

function pickOtherStep(steps, target, random) {
  return pickOne(random, steps.filter((step) => step !== target));
}

const CLEAN_PATHS = ['src/a.ts', 'src/b.ts', 'src/c.ts', 'docs/readme.md', 'lib/x.js', 'lib/y.js'];

const SCOPE_FEATURES = [
  ['dot component', (steps, target) => { target.files = ['src/./a.ts']; }],
  ['dot-dot component', (steps, target) => { target.files = ['src/../a.ts']; }],
  ['double slash', (steps, target) => { target.files = ['src//a.ts']; }],
  ['leading slash', (steps, target) => { target.files = ['/src/a.ts']; }],
  ['trailing slash', (steps, target) => { target.files = ['src/']; }],
  ['star glob', (steps, target) => { target.files = ['src/*.ts']; }],
  ['question glob', (steps, target) => { target.files = ['src/?.ts']; }],
  ['bracket glob', (steps, target) => { target.files = ['src/[ab].ts']; }],
  ['directory prefix', (steps, target, random) => {
    target.files = ['pkg'];
    pickOtherStep(steps, target, random).files.push('pkg/deep/x.ts');
  }],
  ['empty files', (steps, target) => { target.files = []; }],
  ['missing files', (steps, target) => { delete target.files; }],
  ['null files', (steps, target) => { target.files = null; }],
  ['string files', (steps, target) => { target.files = 'src/a.ts'; }],
  ['non-string file', (steps, target) => { target.files = [7]; }],
  ['empty string file', (steps, target) => { target.files = ['']; }],
  ['same file twice', (steps, target) => { target.files = ['src/twice.ts', 'src/twice.ts']; }],
  ['shared file', (steps, target, random) => {
    target.files.push('src/shared.ts');
    pickOtherStep(steps, target, random).files.push('src/shared.ts');
  }],
  ['clean scopes', () => {}]
];

function wireChain(steps) {
  steps.forEach((step, index) => {
    step.depends_on = index === 0 ? [] : [steps[index - 1].id];
  });
}

function wireRandomDag(steps, random) {
  steps.forEach((step, index) => {
    step.depends_on = steps.slice(0, index).filter(() => random() < 0.4).map((earlier) => earlier.id);
  });
}

const GRAPH_SHAPES = {
  'chain': wireChain,
  'diamond': (steps) => {
    const last = steps.length - 1;
    steps.forEach((step, index) => {
      step.depends_on = index === 0 ? [] : index === last ? steps.slice(1, last).map((middle) => middle.id) : [steps[0].id];
    });
  },
  'random dag': wireRandomDag,
  'wide': (steps) => {
    steps.forEach((step) => { step.depends_on = []; });
  },
  'two chains': (steps) => {
    steps.forEach((step, index) => {
      step.depends_on = index < 2 ? [] : [steps[index - 2].id];
    });
  },
  'cycle': (steps) => {
    wireChain(steps);
    steps[0].depends_on = [steps[steps.length - 1].id];
  },
  'self dependency': (steps, random) => {
    wireRandomDag(steps, random);
    const target = pickOne(random, steps);
    target.depends_on.push(target.id);
  },
  'unknown dependency': (steps, random) => {
    wireRandomDag(steps, random);
    pickOne(random, steps).depends_on.push('STEP-099');
  },
  'duplicate id': (steps, random) => {
    wireRandomDag(steps, random);
    steps[steps.length - 1].id = pickOne(random, steps.slice(0, -1)).id;
  },
  'unsafe id': (steps, random) => {
    wireRandomDag(steps, random);
    steps[steps.length - 1].id = pickOne(random, ['STEP 1', 'bad]', 'a/b', 'STEP-1,2']);
  }
};

const OK_SHAPES = ['chain', 'diamond', 'random dag', 'wide', 'two chains'];
const BLOCKING_SHAPES = ['cycle', 'self dependency', 'unknown dependency', 'duplicate id', 'unsafe id'];

function relaxEmptyDependencies(steps, random) {
  for (const step of steps) {
    if (step.depends_on.length !== 0) {
      continue;
    }
    const roll = random();
    if (roll < 0.3) {
      step.depends_on = null;
    } else if (roll < 0.5) {
      delete step.depends_on;
    }
  }
}

function buildCorpusEvents(steps, epoch, random) {
  const stepIds = steps.map((step) => step.id);
  const events = [];
  const eventCount = Math.floor(random() * 4);
  for (let index = 0; index < eventCount; index += 1) {
    const credits = stepIds.filter(() => random() < 0.35);
    if (random() < 0.2) {
      credits.push('STEP-777');
    }
    if (random() < 0.1) {
      credits.push(5);
    }
    const roll = random();
    const extra = {};
    if (roll < 0.25) {
      extra.plan_epoch = (epoch === undefined ? 0 : epoch) + 1;
    } else if (roll < 0.6 && epoch !== undefined) {
      extra.plan_epoch = epoch;
    }
    events.push(completedEvent(credits, extra));
  }
  if (random() < 0.15) {
    events.push('junk');
  }
  if (random() < 0.1) {
    events.push({ state: 'implement_step', outputs: 'not-an-object' });
  }
  return events;
}

function buildCorpusCase(shape, feature, random) {
  const count = 3 + Math.floor(random() * 4);
  const steps = [];
  for (let index = 0; index < count; index += 1) {
    const files = CLEAN_PATHS.filter(() => random() < 0.25);
    steps.push({ id: stepIdAt(index), owner: 'drone', files: files.length === 0 ? [pickOne(random, CLEAN_PATHS)] : files, status: 'pending' });
  }
  GRAPH_SHAPES[shape](steps, random);
  feature[1](steps, pickOne(random, steps), random);
  relaxEmptyDependencies(steps, random);
  const epoch = pickOne(random, [undefined, 0, 2]);
  const plan = epoch === undefined ? { steps: steps } : { epoch: epoch, steps: steps };
  return { name: `${feature[0]} on ${shape}`, shape: shape, ledger: { plan: plan, events: buildCorpusEvents(steps, epoch, random) } };
}

function buildCorpus(seed) {
  const random = createRandom(seed);
  const cases = [];
  SCOPE_FEATURES.forEach((feature, index) => {
    cases.push(buildCorpusCase(OK_SHAPES[index % OK_SHAPES.length], feature, random));
  });
  for (const shape of BLOCKING_SHAPES) {
    cases.push(buildCorpusCase(shape, pickOne(random, SCOPE_FEATURES), random));
    cases.push(buildCorpusCase(shape, pickOne(random, SCOPE_FEATURES), random));
  }
  const allShapes = OK_SHAPES.concat(BLOCKING_SHAPES);
  for (let index = 0; index < 12; index += 1) {
    cases.push(buildCorpusCase(pickOne(random, allShapes), pickOne(random, SCOPE_FEATURES), random));
  }
  return cases;
}

test('the oracle checkout was created', () => {
  assert.equal(gitInit.status, 0, gitInit.stderr);
});

describe('computeWave rules', () => {
  const chain = [
    { id: 'STEP-001', files: ['src/a.ts'], depends_on: [] },
    { id: 'STEP-002', files: ['src/b.ts'], depends_on: ['STEP-001'] }
  ];
  test('depends_on null or absent means no dependencies', async () => {
    const steps = [{ id: 'A', files: ['a'], depends_on: null }, { id: 'B', files: ['b'] }];
    assert.deepEqual(structuredClone(lib.computeWave(steps, [])), { ok: true, all_done: false, wave: ['A', 'B'], remaining: 2 });
    await assertParity('depends_on null', ledgerWithDone(steps, []));
  });
  test('done ids that are not step ids, or not strings, are ignored', async () => {
    assert.deepEqual(structuredClone(lib.computeWave(chain, ['STEP-001', 'STEP-777', 5, null])), { ok: true, all_done: false, wave: ['STEP-002'], remaining: 1 });
    await assertParity('foreign done ids', ledgerWithDone(chain, ['STEP-001', 'STEP-777', 5]));
  });
  test('every step done is all_done with an empty wave', () => {
    assert.deepEqual(structuredClone(lib.computeWave(chain, ['STEP-002', 'STEP-001'])), { ok: true, all_done: true, wave: [], remaining: 0 });
  });
  test('a step may list the same file twice and still share a wave', async () => {
    const steps = [{ id: 'A', files: ['a', 'a'] }, { id: 'B', files: ['b'] }];
    assert.deepEqual(structuredClone(lib.computeWave(steps, [])).wave, ['A', 'B']);
    await assertParity('same file twice', ledgerWithDone(steps, []));
  });
  test('the directory prefix check counts done steps', async () => {
    const steps = [{ id: 'A', files: ['lib/x.js'] }, { id: 'B', files: ['lib'] }, { id: 'C', files: ['docs/c.md'] }];
    assert.deepEqual(structuredClone(lib.computeWave(steps, ['A'])), { ok: true, all_done: false, wave: ['B'], remaining: 2 });
    await assertParity('prefix over done step', ledgerWithDone(steps, ['A']));
  });
  test('a conflicts-with-all step later in plan order waits', async () => {
    const steps = [{ id: 'A', files: ['a'] }, { id: 'B', files: ['src/*.ts'] }, { id: 'C', files: ['c'] }];
    assert.deepEqual(structuredClone(lib.computeWave(steps, [])).wave, ['A', 'C']);
    await assertParity('late conflicts-with-all', ledgerWithDone(steps, []));
  });
  test('done ids that are not an array is a problem', () => {
    const outcome = structuredClone(lib.computeWave(chain, null));
    assert.equal(outcome.ok, false);
    assert.match(outcome.problem, /done ids is not an array/);
  });
  test('validation runs in next-wave order, with the same text in both', async () => {
    const cases = [
      ['missing', undefined, 'plan.steps: missing'],
      ['null', null, 'plan.steps: missing'],
      ['not an array', 'BAD', 'plan.steps: not an array'],
      ['shape before empty check', [7], 'plan.steps[0]: not an object'],
      ['null step', [null], 'plan.steps[0]: not an object'],
      ['every step an object before any id', [{ id: 'A]' }, 7], 'plan.steps[1]: not an object'],
      ['empty', [], 'plan.steps: empty, nothing to schedule'],
      ['empty id', [{ id: '', files: ['a'] }], 'plan.steps[0].id: ' + STEP_ID_PROBLEM],
      ['missing id', [{ id: 'A' }, { files: ['a'] }], 'plan.steps[1].id: missing'],
      ['null id', [{ id: null }], 'plan.steps[0].id: missing'],
      ['non-string id', [{ id: 123 }], 'plan.steps[0].id: ' + STEP_ID_PROBLEM],
      ['ids in ascending index', [{ id: 'A]' }, { id: '' }], 'plan.steps[0].id: ' + STEP_ID_PROBLEM],
      ['every id before any depends_on', [{ id: 'A', depends_on: 'x' }, { id: 'B]' }], 'plan.steps[1].id: ' + STEP_ID_PROBLEM],
      ['every depends_on an array before any entry', [{ id: 'A', depends_on: ['B]'] }, { id: 'B', depends_on: 'x' }], 'plan.steps[1].depends_on: not an array'],
      ['depends_on false is present', [{ id: 'A', depends_on: false }], 'plan.steps[0].depends_on: not an array'],
      ['null depends_on entry', [{ id: 'A', depends_on: [null] }], 'plan.steps[0].depends_on[0]: ' + STEP_ID_PROBLEM],
      ['entries in row-major order', [{ id: 'A', depends_on: ['B', 'C]'] }, { id: 'B', depends_on: ['D]'] }], 'plan.steps[0].depends_on[1]: ' + STEP_ID_PROBLEM],
      ['step id before duplicate', [{ id: 'A' }, { id: 'A' }, { id: 'B]' }], 'plan.steps[2].id: ' + STEP_ID_PROBLEM],
      ['step id before unknown', [{ id: 'A', depends_on: ['Z'] }, { id: 'B', depends_on: ['Y]'] }], 'plan.steps[1].depends_on[0]: ' + STEP_ID_PROBLEM],
      ['step id before cycle', [{ id: 'A]', depends_on: ['A]'] }], 'plan.steps[0].id: ' + STEP_ID_PROBLEM],
      ['first repeat of an earlier id', [{ id: 'A' }, { id: 'B' }, { id: 'B' }, { id: 'A' }], 'plan.steps[2].id: duplicate step id'],
      ['duplicate before unknown', [{ id: 'A', depends_on: ['Z'] }, { id: 'A' }], 'plan.steps[1].id: duplicate step id'],
      ['first unknown in plan order', [{ id: 'A', depends_on: ['A', 'Z'] }, { id: 'B', depends_on: ['Y'] }], 'plan.steps[0].depends_on[1]: unknown step id'],
      ['cycle', [{ id: 'A', depends_on: ['B'] }, { id: 'B', depends_on: ['A'] }], 'dependency cycle detected among plan steps']
    ];
    for (const [label, steps, expectedProblem] of cases) {
      assert.deepEqual(structuredClone(lib.computeWave(steps, [])), { ok: false, problem: expectedProblem }, label);
      const plan = steps === undefined ? {} : { steps: steps };
      await assertParity(label, { plan: plan, events: [] });
    }
  });
  test('a problem names positions only, never a model-written value', () => {
    const hostile = 'A\nforged: x\r\u001b[2J';
    const cases = [
      ['not an object', [[hostile]], 'plan.steps[0]: not an object'],
      ['id not a string', [{ id: { text: hostile } }], 'plan.steps[0].id: ' + STEP_ID_PROBLEM],
      ['depends_on not an array', [{ id: 'A', depends_on: { text: hostile } }], 'plan.steps[0].depends_on: not an array'],
      ['depends_on entry not a string', [{ id: 'A', depends_on: [[hostile]] }], 'plan.steps[0].depends_on[0]: ' + STEP_ID_PROBLEM],
      ['duplicate', [{ id: 'A' }, { id: 'A' }], 'plan.steps[1].id: duplicate step id'],
      ['unknown dependency', [{ id: 'A', depends_on: ['Z'] }], 'plan.steps[0].depends_on[0]: unknown step id'],
      ['unsafe duplicate', [{ id: hostile }, { id: hostile }], 'plan.steps[0].id: ' + STEP_ID_PROBLEM],
      ['unsafe unknown dependency', [{ id: 'A', depends_on: [hostile] }], 'plan.steps[0].depends_on[0]: ' + STEP_ID_PROBLEM]
    ];
    for (const [label, steps, expectedProblem] of cases) {
      const outcome = structuredClone(lib.computeWave(steps, []));
      assert.deepEqual(outcome, { ok: false, problem: expectedProblem }, label);
      assert.doesNotMatch(outcome.problem, /[\u0000-\u001f]/, label);
      assert.ok(!outcome.problem.includes('forged'), label);
    }
  });
  test('inputs are not changed', () => {
    const steps = structuredClone(chain);
    const doneIds = ['STEP-001'];
    lib.computeWave(steps, doneIds);
    assert.deepEqual(steps, chain);
    assert.deepEqual(doneIds, ['STEP-001']);
  });
});

describe('parity with next-wave.sh on its fixtures', { concurrency: ORACLE_CONCURRENCY }, () => {
  const fixtureNames = readdirSync(fixturesDir).filter((name) => name.endsWith('.json')).sort();
  test('the fixture folder is not empty', () => {
    assert.ok(fixtureNames.length > 0);
  });
  for (const name of fixtureNames) {
    test(`${name} with its own events`, async () => {
      await assertParity(name, readFixture(name));
    });
  }
});

describe('parity with next-wave.sh on the tools/test_next_wave.sh overrides and mutations', { concurrency: ORACLE_CONCURRENCY }, () => {
  const linear = readFixture('ledger-linear.json');
  const diamond = readFixture('ledger-diamond.json');
  const replan = readFixture('ledger-replan-epoch.json');
  const cases = [
    ['linear wave2 advance', withEvents(linear, [completedEvent(['STEP-001'])])],
    ['diamond wave2 fan-out', withEvents(diamond, [completedEvent(['STEP-001'])])],
    ['diamond wave3 join union', withEvents(diamond, [completedEvent(['STEP-001']), completedEvent(['STEP-002', 'STEP-003'])])],
    ['diamond all done', withEvents(diamond, [completedEvent(['STEP-001']), completedEvent(['STEP-002', 'STEP-003']), completedEvent(['STEP-004'])])],
    ['replan same-epoch credit', withEvents(replan, [completedEvent(['STEP-001'], { plan_epoch: 2 })])],
    ['bad step id', mutateFixture(linear, (ledger) => { ledger.plan.steps[0].id = 'STEP-001]'; })],
    ['non-object step', mutateFixture(linear, (ledger) => { ledger.plan.steps[0] = ['x']; })],
    ['non-array depends_on', mutateFixture(linear, (ledger) => { ledger.plan.steps[1].depends_on = 'BAD]'; })],
    ['non-array plan.steps', mutateFixture(linear, (ledger) => { ledger.plan.steps = 'BAD'; })],
    ['non-string id', mutateFixture(linear, (ledger) => { ledger.plan.steps[0].id = 123; })],
    ['malformed event skipped', withEvents(linear, ['junk', completedEvent(['STEP-001'])])]
  ];
  for (const [label, ledger] of cases) {
    test(label, async () => {
      await assertParity(label, ledger);
    });
  }
});

describe(`parity with next-wave.sh on a seeded corpus (seed ${SEED})`, { concurrency: ORACLE_CONCURRENCY }, () => {
  test('the seed is a number', () => {
    assert.ok(Number.isInteger(SEED), `WAVES_PARITY_SEED must be an integer, got ${seedText}`);
  });
  const corpus = Number.isInteger(SEED) ? buildCorpus(SEED) : [];
  corpus.forEach((corpusCase, index) => {
    test(`case ${index + 1}: ${corpusCase.name}`, async () => {
      const oracle = await assertParity(`case ${index + 1}: ${corpusCase.name}`, corpusCase.ledger, `\nseed: ${SEED}`);
      const expectOk = OK_SHAPES.includes(corpusCase.shape);
      assert.equal(oracle.ok, expectOk, `seed ${SEED}: ${corpusCase.shape} should ${expectOk ? 'not ' : ''}block`);
    });
  });
});

describe('parity with next-wave.sh on ids that carry a line feed, are unsafe or are oversized', () => {
  test('an id ending in a line feed is not a step id in both', async () => {
    const cases = [
      ['trailing line feed id', [{ id: 'STEP-001\n', files: ['src/a.ts'] }], 'plan.steps[0].id: ' + STEP_ID_PROBLEM],
      ['trailing line feed dependency', [{ id: 'STEP-001', files: ['src/a.ts'] }, { id: 'STEP-002', files: ['src/b.ts'], depends_on: ['STEP-001\n'] }], 'plan.steps[1].depends_on[0]: ' + STEP_ID_PROBLEM]
    ];
    for (const [label, steps, expectedProblem] of cases) {
      const oracle = await assertParity(label, { plan: { steps: steps }, events: [] });
      assert.deepEqual(oracle, { ok: false, problem: expectedProblem }, label);
    }
  });
  test('an unsafe duplicate or unknown id is not a step id in both, on one line', async () => {
    const hostile = 'A\nforged: x\r\u001b[2J';
    const cases = [
      ['unsafe duplicate', [{ id: hostile }, { id: hostile }], 'plan.steps[0].id: ' + STEP_ID_PROBLEM],
      ['unsafe unknown dependency', [{ id: 'A', depends_on: [hostile] }], 'plan.steps[0].depends_on[0]: ' + STEP_ID_PROBLEM]
    ];
    for (const [label, steps, expectedProblem] of cases) {
      const oracle = await assertParity(label, { plan: { steps: steps }, events: [] });
      assert.deepEqual(oracle, { ok: false, problem: expectedProblem }, label);
    }
  });
  test('a 65-char and a 5000-char id give the same bounded problem in both', async () => {
    for (const [where, buildSteps, expectedProblem] of [
      ['id', (longId) => [{ id: longId }, { id: longId }], 'plan.steps[0].id: ' + STEP_ID_PROBLEM],
      ['dependency', (longId) => [{ id: 'A', depends_on: [longId] }], 'plan.steps[0].depends_on[0]: ' + STEP_ID_PROBLEM]
    ]) {
      for (const longId of ['Z'.repeat(65), 'S'.repeat(5000)]) {
        const label = `${longId.length}-char ${where}`;
        const ledger = { plan: { steps: buildSteps(longId) }, events: [] };
        const oracle = await assertParity(label, ledger);
        assert.deepEqual(oracle, { ok: false, problem: expectedProblem }, label);
        const raw = await runOracleRaw(ledger);
        assert.equal(raw.stderr, 'blocker: ' + expectedProblem + '\n', label);
        assert.ok(Buffer.byteLength(raw.stderr) <= 200, `${label}: ${Buffer.byteLength(raw.stderr)} bytes`);
      }
    }
  });
  test('a 64-char id is a step id in both', async () => {
    const steps = [{ id: 'Z'.repeat(64), files: ['src/a.ts'] }];
    const oracle = await assertParity('64-char id', { plan: { steps: steps }, events: [] });
    assert.deepEqual(oracle, { ok: true, all_done: false, wave: ['Z'.repeat(64)], remaining: 1 });
  });
});

describe('waves.js is a plain workflow lib', () => {
  const source = readFileSync(wavesPath, 'utf8').replace(/\r/g, '');
  test('no module syntax, clock, randomness, em dash or hash-digit', () => {
    assert.doesNotMatch(source, /\bimport\b|\bexport\b|\brequire\b/);
    assert.doesNotMatch(source, /\bDate\b/);
    assert.doesNotMatch(source, /Math\.random/);
    assert.doesNotMatch(source, /\u2014/);
    assert.doesNotMatch(source, /#\d/);
  });
  test('opens with a contract header that names its parity oracle', () => {
    assert.match(source, /^\/\*\n \* [a-z]+\.js: [\s\S]*?\n \* Inputs\n[\s\S]*?\n \* Outputs\n[\s\S]*?\n \* Invariants\n[\s\S]*?\n \* Why\n[\s\S]*?\*\//);
    assert.match(source, /plugin\/skills\/next-wave\/scripts\/next-wave\.sh/);
  });
  test('declares only top-level functions', () => {
    assert.doesNotMatch(source, /^(const|let|var|class)\s/m);
    const context = vm.createContext({});
    const before = new Set(Object.keys(context));
    vm.runInContext(source, context);
    const added = Object.keys(context).filter((key) => !before.has(key));
    assert.ok(added.includes('computeWave'));
    for (const key of added) {
      assert.equal(typeof context[key], 'function', `${key} is not a function`);
    }
  });
  test('no function name is also declared in another lib or in analysis-only', () => {
    const otherPaths = readdirSync(libDir)
      .filter((name) => name.endsWith('.js') && name !== 'waves.js')
      .map((name) => libDir + name)
      .concat([repoRoot + 'plugin/workflow-src/analysis-only/main.js']);
    const taken = new Map();
    for (const path of otherPaths) {
      for (const match of readFileSync(path, 'utf8').matchAll(/^function\s+([A-Za-z0-9_]+)/gm)) {
        taken.set(match[1], path);
      }
    }
    for (const match of source.matchAll(/^function\s+([A-Za-z0-9_]+)/gm)) {
      assert.equal(taken.has(match[1]), false, `${match[1]} is also declared in ${taken.get(match[1])}`);
    }
  });
});
