import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const enginePath = join(repoRoot, 'plugin/skills/gate-check/scripts/gate-check.sh');
const contractPath = join(repoRoot, 'plugin/skills/gate-check/scripts/gate-contract.json');
const mainSource = readFileSync(join(repoRoot, 'plugin/workflow-src/standard-delivery/main.js'), 'utf8');
const contract = JSON.parse(readFileSync(contractPath, 'utf8'));

const RUN_ID = 'run-1';
const OLD_A = 'a'.repeat(40);
const OLD_B = 'b'.repeat(40);
const OLD_C = 'c'.repeat(40);
const OLD_D = 'd'.repeat(40);
const OLD_E = 'e'.repeat(40);
const ROUTING_RE = /^outcome: ([A-Za-z0-9._-]+)\nhead: ([0-9a-f]{40})\nreruns: (\d+)\nmax_reruns: (\d+)\n$/;

const workRoot = realpathSync(mkdtempSync(join(tmpdir(), 'hivemind-gate-check-')));
const homeDir = join(workRoot, 'home');
mkdirSync(homeDir);
const scriptEnv = { ...process.env, HOME: homeDir, XDG_CONFIG_HOME: join(homeDir, '.config'), GIT_CONFIG_NOSYSTEM: '1' };
for (const name of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_COMMON_DIR']) {
  delete scriptEnv[name];
}
let repoCount = 0;

after(() => {
  rmSync(workRoot, { recursive: true, force: true });
  assert.equal(existsSync(workRoot), false, `temp folder ${workRoot} was not removed`);
});

function runGit(cwd, args) {
  const run = spawnSync('git', ['-c', 'user.name=Gate Test', '-c', 'user.email=gate@example.invalid', '-c', 'commit.gpgsign=false', ...args], { cwd: cwd, env: scriptEnv, encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  return run.stdout.trim();
}

function makeRepo(withCommit = true) {
  repoCount += 1;
  const root = join(workRoot, 'repo-' + repoCount);
  mkdirSync(root);
  runGit(root, ['init', '-q']);
  writeFileSync(join(root, '.gitignore'), '.hivemind/\n');
  if (withCommit) {
    runGit(root, ['add', '.gitignore']);
    runGit(root, ['commit', '-q', '-m', 'initial']);
  }
  return root;
}

function headOf(root) {
  return runGit(root, ['rev-parse', 'HEAD']);
}

function event(state, result, head, extra = {}) {
  return { at: '2026-10-24T00:00:00Z', state: state, result: result, plan_epoch: 0, head: head, outputs: {}, ...extra };
}

function writeLedger(root, events, overrides = {}) {
  const runDir = join(root, '.hivemind', 'runs', RUN_ID);
  mkdirSync(runDir, { recursive: true });
  const ledger = { run: { id: RUN_ID, workflow: 'standard-delivery' }, plan: { epoch: 0, steps: [] }, events: events, ...overrides };
  writeFileSync(join(runDir, 'state.json'), JSON.stringify(ledger));
  return join(runDir, 'state.json');
}

function runEngine(root, runId = RUN_ID, engine = enginePath) {
  return spawnSync('bash', [engine, runId], { cwd: root, env: scriptEnv, encoding: 'utf8' });
}

function readRouting(root) {
  const run = runEngine(root);
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stderr, '');
  const match = ROUTING_RE.exec(run.stdout);
  assert.notEqual(match, null, 'unparsed routing: ' + JSON.stringify(run.stdout));
  return { outcome: match[1], head: match[2], reruns: Number(match[3]), max_reruns: Number(match[4]) };
}

function assertBlocked(run, reasonPattern) {
  assert.equal(run.status, 1, run.stdout + run.stderr);
  assert.equal(run.stdout, '');
  const lastLine = run.stderr.replace(/\n$/, '').split('\n').pop();
  assert.match(lastLine, /^blocker: /);
  assert.match(lastLine, reasonPattern);
}

function heldOn(head) {
  return [
    event('version_bump_decision', 'not_required', head),
    event('validate', 'passed', head),
    event('local_review', 'clean', head)
  ];
}

describe('gate contract', () => {
  test('names the state-machine gates, their holding transitions and the rerun bound', () => {
    assert.deepEqual(contract, {
      workflow: 'standard-delivery',
      gates: [
        { id: 'bump', due: 'version_due', holds: ['version_bump_decision.not_required', 'version_checkpoint.complete'] },
        { id: 'validate', due: 'validation_due', holds: ['validate.passed'] },
        { id: 'review', due: 'review_due', holds: ['local_review.clean', 'diminishing_returns_decision.taken'], skip: ['local_review_decision.skipped'] }
      ],
      max_reruns: 4,
      outcomes: { all_held: 'all_held', rerun_limit: 'rerun_limit' }
    });
  });

  test('max_reruns agrees with the workflow script bound', () => {
    const match = /function maxGateReruns\(\) \{\s*return (\d+);\s*\}/.exec(mainSource);
    assert.notEqual(match, null, 'maxGateReruns() not found in main.js');
    assert.equal(contract.max_reruns, Number(match[1]));
    assert.match(mainSource, /if \(gates\.reruns >= maxGateReruns\(\)\)/);
  });
});

describe('outcomes', () => {
  test('routing format is exactly four lines and head is HEAD', () => {
    const root = makeRepo();
    writeLedger(root, []);
    const run = runEngine(root);
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stdout, 'outcome: version_due\nhead: ' + headOf(root) + '\nreruns: 0\nmax_reruns: 4\n');
  });

  test('no holding event: version_due', () => {
    const root = makeRepo();
    writeLedger(root, [event('plan', 'single', headOf(root))]);
    assert.equal(readRouting(root).outcome, 'version_due');
  });

  test('every gate held on HEAD: all_held', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, heldOn(head));
    assert.deepEqual(readRouting(root), { outcome: 'all_held', head: head, reruns: 0, max_reruns: 4 });
  });

  test('bump held: validation_due; bump and validate held: review_due', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_checkpoint', 'complete', head)]);
    assert.equal(readRouting(root).outcome, 'validation_due');
    writeLedger(root, [event('version_checkpoint', 'complete', head), event('validate', 'passed', head)]);
    assert.equal(readRouting(root).outcome, 'review_due');
  });

  test('diminishing_returns_decision.taken holds review', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', head), event('validate', 'passed', head), event('diminishing_returns_decision', 'taken', head)]);
    assert.equal(readRouting(root).outcome, 'all_held');
  });

  test('a review exit that is not a holding transition holds nothing', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', head), event('validate', 'passed', head), event('local_review', 'max-iterations-reached', head)]);
    assert.equal(readRouting(root).outcome, 'review_due');
  });
});

describe('gate order and reruns of held gates', () => {
  test('the first gate in order that is not held on HEAD is due', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('validate', 'passed', head), event('local_review', 'clean', head)]);
    assert.equal(readRouting(root).outcome, 'version_due');
  });

  test('a gate held on HEAD is not run again', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', OLD_A), event('validate', 'passed', head), event('version_bump_decision', 'not_required', head)]);
    const routing = readRouting(root);
    assert.equal(routing.outcome, 'review_due');
    assert.equal(routing.reruns, 1);
  });

  test('a later commit sends the run back to the first stale gate', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [...heldOn(OLD_A), event('local_review', 'clean', head)]);
    const routing = readRouting(root);
    assert.equal(routing.outcome, 'version_due');
    assert.equal(routing.reruns, 1);
  });
});

describe('local review skip', () => {
  test('a skipped review is not configured', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', head), event('validate', 'passed', head), event('local_review_decision', 'skipped', head)]);
    assert.equal(readRouting(root).outcome, 'all_held');
  });

  test('a skip does not hold the earlier gates', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', head), event('local_review_decision', 'skipped', head)]);
    assert.equal(readRouting(root).outcome, 'validation_due');
  });

  test('a later required decision configures review again', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', head), event('validate', 'passed', head), event('local_review_decision', 'skipped', head), event('local_review_decision', 'required', head)]);
    assert.equal(readRouting(root).outcome, 'review_due');
  });
});

describe('plan epoch scoping', () => {
  test('events from an earlier plan epoch hold nothing after a replan', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, heldOn(head), { plan: { epoch: 1, steps: [] } });
    assert.deepEqual(readRouting(root), { outcome: 'version_due', head: head, reruns: 0, max_reruns: 4 });
  });

  test('events of the current epoch count', () => {
    const root = makeRepo();
    const head = headOf(root);
    const current = heldOn(head).map((entry) => ({ ...entry, plan_epoch: 1 }));
    writeLedger(root, [...heldOn(OLD_A), ...current], { plan: { epoch: 1, steps: [] } });
    assert.deepEqual(readRouting(root), { outcome: 'all_held', head: head, reruns: 0, max_reruns: 4 });
  });

  test('a ledger with no epoch fields reads as epoch 0', () => {
    const root = makeRepo();
    const head = headOf(root);
    const events = heldOn(head).map(({ plan_epoch, ...rest }) => rest);
    writeLedger(root, events, { plan: { steps: [] } });
    assert.equal(readRouting(root).outcome, 'all_held');
  });
});

describe('events with no head', () => {
  test('a holding event with no head holds nothing', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', head), event('validate', 'passed', null)]);
    assert.equal(readRouting(root).outcome, 'validation_due');
  });

  test('the latest holding event decides, even when it has no head', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', head), event('validate', 'passed', head), event('validate', 'passed', null)]);
    assert.equal(readRouting(root).outcome, 'validation_due');
  });

  test('an event without a head field holds nothing and is dropped from the rerun count', () => {
    const root = makeRepo();
    const head = headOf(root);
    const headless = event('validate', 'passed', null);
    delete headless.head;
    writeLedger(root, [event('version_bump_decision', 'not_required', head), headless]);
    assert.deepEqual(readRouting(root), { outcome: 'validation_due', head: head, reruns: 0, max_reruns: 4 });
  });
});

describe('rerun counting', () => {
  test('equal adjacent heads are one commit', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', OLD_A), event('validate', 'passed', OLD_A), event('local_review', 'clean', head)]);
    assert.equal(readRouting(root).reruns, 1);
  });

  test('A-B-A counts two reruns', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', head), event('validate', 'passed', OLD_B)]);
    const routing = readRouting(root);
    assert.equal(routing.reruns, 2);
    assert.equal(routing.outcome, 'validation_due');
  });

  test('a non-holding event head is not in the sequence', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('implement_next_step', 'complete', OLD_A), event('version_bump_decision', 'not_required', head)]);
    assert.equal(readRouting(root).reruns, 0);
  });

  test('exactly max_reruns reruns still routes to the due gate', () => {
    const root = makeRepo();
    writeLedger(root, [event('version_bump_decision', 'not_required', OLD_A), event('validate', 'passed', OLD_B), event('local_review', 'clean', OLD_C), event('version_bump_decision', 'not_required', OLD_D)]);
    const routing = readRouting(root);
    assert.equal(routing.reruns, 4);
    assert.equal(routing.outcome, 'version_due');
  });

  test('max_reruns plus one reruns: rerun_limit', () => {
    const root = makeRepo();
    const head = headOf(root);
    writeLedger(root, [event('version_bump_decision', 'not_required', OLD_A), event('validate', 'passed', OLD_B), event('local_review', 'clean', OLD_C), event('version_bump_decision', 'not_required', OLD_D), event('validate', 'passed', OLD_E)]);
    assert.deepEqual(readRouting(root), { outcome: 'rerun_limit', head: head, reruns: 5, max_reruns: 4 });
  });
});

describe('blockers', () => {
  test('a modified tracked file blocks', () => {
    const root = makeRepo();
    writeLedger(root, heldOn(headOf(root)));
    writeFileSync(join(root, '.gitignore'), '.hivemind/\nchanged\n');
    assertBlocked(runEngine(root), /uncommitted or untracked changes/);
  });

  test('a staged file blocks', () => {
    const root = makeRepo();
    writeLedger(root, heldOn(headOf(root)));
    writeFileSync(join(root, 'staged.txt'), 'x\n');
    runGit(root, ['add', 'staged.txt']);
    assertBlocked(runEngine(root), /uncommitted or untracked changes/);
  });

  test('an untracked file blocks', () => {
    const root = makeRepo();
    writeLedger(root, heldOn(headOf(root)));
    writeFileSync(join(root, 'untracked.txt'), 'x\n');
    assertBlocked(runEngine(root), /uncommitted or untracked changes/);
  });

  test('a run of another workflow blocks', () => {
    const root = makeRepo();
    writeLedger(root, heldOn(headOf(root)), { run: { id: RUN_ID, workflow: 'analysis-only' } });
    assertBlocked(runEngine(root), /workflow is not standard-delivery/);
  });

  test('a run with no workflow blocks', () => {
    const root = makeRepo();
    writeLedger(root, [], { run: { id: RUN_ID } });
    assertBlocked(runEngine(root), /workflow is not standard-delivery/);
  });

  test('HEAD with no commit blocks', () => {
    const root = makeRepo(false);
    writeLedger(root, []);
    assertBlocked(runEngine(root), /HEAD has no commit/);
  });

  test('a missing ledger blocks', () => {
    const root = makeRepo();
    assertBlocked(runEngine(root), /blocker: /);
    mkdirSync(join(root, '.hivemind', 'runs', RUN_ID), { recursive: true });
    assertBlocked(runEngine(root), /blocker: /);
  });

  test('a ledger that is not JSON blocks', () => {
    const root = makeRepo();
    const ledgerPath = writeLedger(root, []);
    writeFileSync(ledgerPath, '{ not json');
    assertBlocked(runEngine(root), /blocker: /);
  });

  test('events that are not an array block', () => {
    const root = makeRepo();
    writeLedger(root, 'BAD');
    assertBlocked(runEngine(root), /events is not an array/);
  });

  test('a symlinked state.json leaf blocks', () => {
    const root = makeRepo();
    const outside = join(workRoot, 'outside-' + repoCount + '.json');
    writeFileSync(outside, JSON.stringify({ run: { id: RUN_ID, workflow: 'standard-delivery' }, events: [] }));
    const runDir = join(root, '.hivemind', 'runs', RUN_ID);
    mkdirSync(runDir, { recursive: true });
    symlinkSync(outside, join(runDir, 'state.json'));
    assertBlocked(runEngine(root), /outside the checkout/);
  });

  test('an unsafe run_id blocks', () => {
    const root = makeRepo();
    assertBlocked(runEngine(root, '../x'), /run_id is not a safe path component/);
    assertBlocked(runEngine(root, '..'), /reserved path component/);
    assertBlocked(runEngine(root, ''), /missing required argument/);
  });
});

describe('gate contract blockers', () => {
  function copyPlugin(label) {
    const pluginCopy = join(workRoot, 'plugin-' + label);
    mkdirSync(join(pluginCopy, 'skills'), { recursive: true });
    cpSync(join(repoRoot, 'plugin/skills/gate-check'), join(pluginCopy, 'skills/gate-check'), { recursive: true });
    cpSync(join(repoRoot, 'plugin/skills/_shared'), join(pluginCopy, 'skills/_shared'), { recursive: true });
    return pluginCopy;
  }

  test('a missing contract blocks', () => {
    const pluginCopy = copyPlugin('missing');
    rmSync(join(pluginCopy, 'skills/gate-check/scripts/gate-contract.json'));
    const root = makeRepo();
    writeLedger(root, []);
    assertBlocked(runEngine(root, RUN_ID, join(pluginCopy, 'skills/gate-check/scripts/gate-check.sh')), /gate contract missing/);
  });

  test('a contract that is not JSON blocks', () => {
    const pluginCopy = copyPlugin('not-json');
    writeFileSync(join(pluginCopy, 'skills/gate-check/scripts/gate-contract.json'), '{');
    const root = makeRepo();
    writeLedger(root, []);
    assertBlocked(runEngine(root, RUN_ID, join(pluginCopy, 'skills/gate-check/scripts/gate-check.sh')), /gate contract is malformed/);
  });

  test('a contract of the wrong shape blocks', () => {
    const shapes = [
      { ...contract, max_reruns: '4' },
      { ...contract, gates: [] },
      { ...contract, gates: [{ ...contract.gates[0], holds: [] }] },
      { ...contract, outcomes: { all_held: 'all held', rerun_limit: 'rerun_limit' } }
    ];
    shapes.forEach((shape, index) => {
      const pluginCopy = copyPlugin('shape-' + index);
      writeFileSync(join(pluginCopy, 'skills/gate-check/scripts/gate-contract.json'), JSON.stringify(shape));
      const root = makeRepo();
      writeLedger(root, []);
      assertBlocked(runEngine(root, RUN_ID, join(pluginCopy, 'skills/gate-check/scripts/gate-check.sh')), /gate contract is malformed/);
    });
  });
});

describe('read-only', () => {
  test('the engine changes neither the ledger nor the run folder', () => {
    const root = makeRepo();
    const ledgerPath = writeLedger(root, heldOn(headOf(root)));
    const before = readFileSync(ledgerPath, 'utf8');
    const runDir = join(root, '.hivemind', 'runs', RUN_ID);
    assert.equal(readRouting(root).outcome, 'all_held');
    assert.equal(readFileSync(ledgerPath, 'utf8'), before);
    assert.deepEqual(readdirSync(runDir), ['state.json']);
    assert.equal(runGit(root, ['status', '--porcelain']), '');
  });
});
