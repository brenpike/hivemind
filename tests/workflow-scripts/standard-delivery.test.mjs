import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { loadLibs, loadWorkflowSource } from './harness.mjs';
import { LIB_FILES, buildWorkflow, builtPathFor, isDraftWorkflow } from '../../tools/build_workflows.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const WORKFLOW_ID = 'standard-delivery';
const sourceDir = join(repoRoot, 'plugin/workflow-src', WORKFLOW_ID);
const mainSource = readText(join(sourceDir, 'main.js'));
const metaSource = readText(join(sourceDir, 'meta.js'));
const builtSource = buildWorkflow(repoRoot, WORKFLOW_ID);
const workflow = loadWorkflowSource(builtSource, WORKFLOW_ID + ' (in memory)');
const lib = loadLibs(LIB_FILES.map((file) => join(repoRoot, 'plugin/workflow-src/lib', file)));
const main = loadMainFunctions(builtSource);
const factsSchema = readJson('plugin/references/facts-schema.json');
const planSchema = readJson('plugin/references/plan-schema.json');
const briefSchema = readJson('plugin/references/decision-brief-schema.json');
const droneText = readText(join(repoRoot, 'plugin/agents/drone.md'));
const gatherFactsPath = join(repoRoot, 'plugin/skills/gather-facts/scripts/gather-facts.sh');
const createBranchPath = join(repoRoot, 'plugin/skills/create-working-branch/scripts/create-working-branch.sh');
const moltPath = join(repoRoot, 'plugin/skills/molt/scripts/molt.sh');

const REQUEST = 'Add the cache layer. REQUEST_MARKER_ZQ';
const LAUNCH = { request: REQUEST };
const HEAD = '1'.repeat(40);
const OTHER = '2'.repeat(40);
const THIRD = '3'.repeat(40);
const TRUNK_COMMIT = '4'.repeat(40);
const FACTS_FILE = '.hivemind/facts/facts-20261021T120000Z-0123456789ab.json';
const FACTS_KEYS = ['facts_file', 'facts_lines', 'head_state', 'branch', 'head', 'trunk', 'trunk_freshness', 'trunk_ahead', 'trunk_behind', 'trunk_commit', 'cut', 'external_texts', 'delivery', 'delivery_stops'];
const WORKER_DONE = { outcome: 'complete', summary: 'Done.' };
const MALFORMED_FACTS = 'The facts step returned malformed facts, so the delivery stopped before planning.';
const NOT_READY = 'The branch is not ready for delivery, so the delivery stopped before planning:';
const scratchRoots = [];

after(() => {
  scratchRoots.forEach((root) => rmSync(root, { recursive: true, force: true }));
});

function readText(path) {
  return readFileSync(path, 'utf8').replace(/\r/g, '');
}

function readJson(relativePath) {
  return JSON.parse(readText(join(repoRoot, relativePath)));
}

/**
 * Runs the built script without its last statement in a plain context, so
 * every top-level function of main.js and the libs can be called directly.
 */
function loadMainFunctions(source) {
  const lastStatement = '\nreturn await runDelivery(args);\n';
  assert.ok(source.endsWith(lastStatement), 'main.js ends with the runDelivery call');
  const body = source.replace(/^export const meta\b/, 'const meta').slice(0, -lastStatement.length + 1);
  const context = vm.createContext({});
  vm.runInContext(body, context, { filename: WORKFLOW_ID + ' functions' });
  return context;
}

function factsStdout(changes = {}) {
  const values = {
    facts_file: FACTS_FILE,
    facts_lines: '40',
    head_state: 'branch',
    branch: 'main',
    head: HEAD,
    trunk: 'main',
    trunk_freshness: 'fresh',
    trunk_ahead: '0',
    trunk_behind: '0',
    trunk_commit: TRUNK_COMMIT,
    cut: 'none',
    external_texts: '0',
    delivery: 'ready',
    delivery_stops: 'none',
    ...changes
  };
  return FACTS_KEYS.filter((key) => values[key] !== undefined).map((key) => key + ': ' + values[key]).join('\n') + '\n';
}

function factsRelay(changes) {
  return { outcome: 'ran', stdout: factsStdout(changes) };
}

function onPlanBranchFacts(head, changes = {}) {
  return factsRelay({ branch: 'feature/cache', head: head, ...changes });
}

function parsedFacts(changes) {
  return lib.parseRoutingLines(factsStdout(changes), lib.gatherFactsRoutingSpec()).values;
}

function makeStep(id, files, changes = {}) {
  return { id: id, owner: 'hivemind:drone', files: files, outcome: 'Step ' + id + ' is done.', depends_on: [], external_effects: [], ...changes };
}

function makePlan(changes = {}) {
  return {
    summary: 'Add the cache layer.',
    branch: 'feature/cache',
    base: 'main',
    trunk_freshness: 'fresh',
    classification: 'feature',
    breaking: false,
    versioning: { bump_trigger: 'no', no_bump_match: 'no', artifact_files: [] },
    delivery: 'single',
    steps: [makeStep('STEP-001', ['src/cache.js'])],
    ...changes
  };
}

function planResult(plan = makePlan(), questions = []) {
  return { outcome: 'complete', plan: plan, questions: questions };
}

function reviseResult(result, settled) {
  return { ...result, settled: settled };
}

function effectPlan(summary, reversible) {
  return makePlan({ steps: [makeStep('STEP-001', ['src/cache.js'], { external_effects: [{ summary: summary, reversible: reversible }] })] });
}

function routingStdout(values) {
  return Object.entries(values).filter(([, value]) => value !== undefined).map(([key, value]) => key + ': ' + value).join('\n') + '\n';
}

function branchRelay(changes = {}) {
  return { outcome: 'ran', stdout: routingStdout({ branch: 'feature/cache', commit: HEAD, created: 'true', ...changes }) };
}

function commitRelay(changes = {}) {
  return { outcome: 'ran', stdout: routingStdout({ branch: 'feature/cache', commit: OTHER, committed: 'true', ...changes }) };
}

function happyResults(changes = {}) {
  return {
    'facts-1': factsRelay(),
    'plan-1': planResult(),
    'branch-1': branchRelay(),
    'work-1-STEP-001': WORKER_DONE,
    'commit-1-1': commitRelay(),
    ...changes
  };
}

function makeBrief(changes = {}) {
  return {
    id: 'Q1',
    kind: 'planner_question',
    problem: 'Pick a cache key format.',
    criticality: { level: 'medium', likelihood: 'common', blast_radius: 'One module.', if_ignored: 'Keys collide.' },
    options: [
      { id: 'A', summary: 'Hash the path.', steel_man: 'Short.', straw_man: 'Opaque.', effort: 'small', value: 'high', reversible: true },
      { id: 'B', summary: 'Use the raw path.', steel_man: 'Readable.', straw_man: 'Long.', effort: 'trivial', value: 'medium', reversible: true }
    ],
    recommendation: { option_id: 'A', strength: 'strong', why: 'Less effort for more value.' },
    assumptions: [{ statement: 'Paths are unique.', origin: 'repo', evidence: 'src/cache.js' }],
    gate: { irreversible: false, architectural: false, safety: false },
    ...changes
  };
}

function makeGatedBrief(problem) {
  return makeBrief({ problem: problem, gate: { irreversible: false, architectural: true, safety: false } });
}

async function runWorkflow(args, results, target = workflow) {
  const run = await target.run({ args: args, results: results });
  return structuredClone({ result: run.result, calls: run.calls, phases: run.phases, failures: run.failures.length });
}

function labelsOf(run) {
  return run.calls.map((call) => call.opts.label);
}

function callOf(run, label) {
  const call = run.calls.find((candidate) => candidate.opts.label === label);
  assert.ok(call !== undefined, 'a call with label ' + label);
  return call;
}

function readDataBlock(prompt, name) {
  const lines = prompt.split('\n');
  const start = lines.indexOf('<' + name + '>');
  assert.notEqual(start, -1, 'the prompt has a ' + name + ' block');
  assert.equal(lines[start + 2], '</' + name + '>');
  return JSON.parse(lines[start + 1]);
}

function withoutDataBlock(prompt, name) {
  const lines = prompt.split('\n');
  const start = lines.indexOf('<' + name + '>');
  assert.notEqual(start, -1, 'the prompt has a ' + name + ' block');
  return lines.slice(0, start).concat(lines.slice(start + 3)).join('\n');
}

function resumeWith(launchArgs, pausedResult, reply) {
  return { ...launchArgs, ...pausedResult.resume_args, reply: reply };
}

function assertBlockedBeforeWaves(run, message) {
  assert.equal(run.result.needs_user, false);
  assert.equal(run.result.outcome, 'blocked');
  if (message !== undefined) {
    const actual = run.result.message;
    assert.ok(actual === message || actual.startsWith(message + '\n\n'), actual);
  }
  assert.ok(labelsOf(run).every((label) => !label.startsWith('work-') && !label.startsWith('commit-')), JSON.stringify(labelsOf(run)));
}

/**
 * Builds the workflow from a scratch copy whose autonomy table rows for
 * the given kinds are surface at every level.
 */
function buildWithSurfaceKinds(kinds) {
  const scratchRoot = realpathSync(mkdtempSync(join(tmpdir(), 'hivemind-delivery-table-')));
  scratchRoots.push(scratchRoot);
  for (const dir of ['plugin/workflow-src', 'plugin/references']) {
    cpSync(join(repoRoot, dir), join(scratchRoot, dir), { recursive: true });
  }
  const tablePath = join(scratchRoot, 'plugin/references/decision-autonomy-table.json');
  const table = JSON.parse(readFileSync(tablePath, 'utf8'));
  table.rows.filter((row) => kinds.includes(row.kind)).forEach((row) => Object.assign(row, { high: 'surface', balanced: 'surface', low: 'surface' }));
  writeFileSync(tablePath, JSON.stringify(table));
  return loadWorkflowSource(buildWorkflow(scratchRoot, WORKFLOW_ID), WORKFLOW_ID + ' (surface table)');
}

function makeScratchRepo() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'hivemind-delivery-')));
  scratchRoots.push(root);
  const home = join(root, 'home');
  const stubDir = join(root, 'stub-bin');
  const repo = join(root, 'repo');
  [home, stubDir, repo].forEach((dir) => mkdirSync(dir, { recursive: true }));
  writeFileSync(join(home, '.gitconfig'), '[user]\n\tname = Delivery Test\n\temail = delivery@example.invalid\n[commit]\n\tgpgsign = false\n');
  writeFileSync(join(stubDir, 'gh'), '#!/bin/sh\nexit 1\n');
  chmodSync(join(stubDir, 'gh'), 0o755);
  const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: join(home, '.config'), GIT_CONFIG_NOSYSTEM: '1', GIT_CEILING_DIRECTORIES: root, GIT_TERMINAL_PROMPT: '0', PATH: stubDir + ':' + process.env.PATH };
  ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_COMMON_DIR', 'GIT_LITERAL_PATHSPECS'].forEach((name) => delete env[name]);
  const scratch = { repo: repo, env: env };
  runGitIn(scratch, ['init', '-q']);
  runGitIn(scratch, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
  writeFileSync(join(repo, 'README.md'), 'scratch\n');
  runGitIn(scratch, ['add', 'README.md']);
  runGitIn(scratch, ['commit', '-q', '-m', 'initial']);
  writeFileSync(join(repo, '.git/info/exclude'), '.hivemind/\n');
  return scratch;
}

function runGitIn(scratch, gitArgs) {
  const run = spawnSync('git', gitArgs, { cwd: scratch.repo, env: scratch.env, encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  return run.stdout.trim();
}

function runScriptIn(scratch, scriptPath, scriptArgs) {
  const run = spawnSync('bash', [scriptPath, ...scriptArgs], { cwd: scratch.repo, env: scratch.env, encoding: 'utf8' });
  return run.status === 0 ? { outcome: 'ran', stdout: run.stdout } : { outcome: 'blocked', stderr: run.stderr };
}

function realFactsRunner(scratch) {
  return (prompt) => {
    const inputs = readDataBlock(prompt, 'inputs');
    const refArgs = inputs.references.flatMap((reference) => ['--ref', reference]);
    return runScriptIn(scratch, gatherFactsPath, ['--trunk', inputs.trunk, ...refArgs]);
  };
}

function realBranchRunner(scratch) {
  return (prompt) => {
    const inputs = readDataBlock(prompt, 'inputs');
    const flags = ['--base', inputs.base, '--branch', inputs.working_branch, '--classification', inputs.classification];
    return runScriptIn(scratch, createBranchPath, [...flags, '--trunk-freshness', inputs['trunk-freshness'], '--trunk', inputs.trunk]);
  };
}

function realCommitRunner(scratch) {
  let inputsCount = 0;
  return (prompt) => {
    const inputs = readDataBlock(prompt, 'inputs');
    inputsCount += 1;
    const inputsPath = '.hivemind/molt-inputs-test-' + inputsCount + '.json';
    mkdirSync(join(scratch.repo, '.hivemind'), { recursive: true });
    writeFileSync(join(scratch.repo, inputsPath), JSON.stringify({ type: inputs.commit_type, breaking: inputs.breaking, subject: 'deliver the wave', files: inputs.files }));
    return runScriptIn(scratch, moltPath, ['--trunk', inputs.trunk, '--inputs', inputsPath]);
  };
}

function writeRepoFile(scratch, relativePath, content) {
  mkdirSync(dirname(join(scratch.repo, relativePath)), { recursive: true });
  writeFileSync(join(scratch.repo, relativePath), content);
}

function realWorker(scratch, extraFile) {
  return (prompt) => {
    const step = readDataBlock(prompt, 'step');
    step.files.forEach((file) => writeRepoFile(scratch, file, 'edited by ' + step.id + '\n'));
    if (extraFile !== undefined) {
      writeRepoFile(scratch, extraFile, 'outside the step\n');
    }
    return WORKER_DONE;
  };
}

function realResults(scratch, changes = {}) {
  return {
    'facts-1': realFactsRunner(scratch),
    'plan-1': planResult(makePlan({ trunk_freshness: 'no_remote' })),
    'branch-1': realBranchRunner(scratch),
    'work-1-STEP-001': realWorker(scratch),
    'commit-1-1': realCommitRunner(scratch),
    ...changes
  };
}

function readContractIds(source) {
  return [...source.matchAll(/\{ id: '(SD-[0-9]+)'/g)].map((match) => match[1]);
}

function readDroneClause(startText, endText) {
  const start = droneText.indexOf(startText);
  assert.notEqual(start, -1, 'drone.md has the clause starting ' + JSON.stringify(startText));
  const end = droneText.indexOf(endText, start);
  assert.notEqual(end, -1, 'drone.md has the clause ending ' + JSON.stringify(endText));
  return droneText.slice(start, end + endText.length);
}

const ROW_TESTS = {
  'SD-01': () => {
    test('args undefined finishes blocked with no agent call', async () => {
      const run = await runWorkflow(undefined, {});
      assert.deepEqual(run.result, { needs_user: false, outcome: 'blocked', message: 'No request was given, so there is nothing to deliver.' });
      assert.deepEqual(run.calls, []);
    });
    test('a blank request blocks with no agent call', async () => {
      const run = await runWorkflow({ request: '  ' }, {});
      assert.equal(run.result.message, 'No request was given, so there is nothing to deliver.');
      assert.deepEqual(run.calls, []);
    });
    for (const trunk of ['-main', 'ma..in', 'main branch', 'ma$in', 'main\n']) {
      test(`trunk ${JSON.stringify(trunk)} fails isGitIdentifier and blocks with no agent call`, async () => {
        const run = await runWorkflow({ request: REQUEST, trunk: trunk }, {});
        assert.deepEqual(run.result, { needs_user: false, outcome: 'blocked', message: 'The trunk launch arg is not a safe git branch name, so the delivery did not start.' });
        assert.deepEqual(run.calls, []);
      });
    }
    test('a blank trunk and bad references block through args.js', async () => {
      const blankTrunk = await runWorkflow({ request: REQUEST, trunk: ' ' }, {});
      assert.equal(blankTrunk.result.message, 'The trunk launch arg must be a non-blank string, so the delivery did not start.');
      const badReferences = await runWorkflow({ request: REQUEST, references: ['x'] }, {});
      assert.equal(badReferences.result.message, 'The references launch arg must be a list of issue or pull request numbers, so the delivery did not start.');
      assert.deepEqual(blankTrunk.calls.concat(badReferences.calls), []);
    });
    test('a string launch takes the default trunk and no references', async () => {
      const run = await runWorkflow(REQUEST, happyResults());
      assert.deepEqual(readDataBlock(callOf(run, 'facts-1').prompt, 'inputs'), { trunk: 'main', references: [] });
      assert.equal(run.result.outcome, 'complete');
    });
    test('trunk and references reach the facts inputs normalized', async () => {
      const run = await runWorkflow({ request: REQUEST, trunk: 'develop', references: [12, '7', 12] }, { 'facts-1': factsRelay() });
      assert.deepEqual(readDataBlock(callOf(run, 'facts-1').prompt, 'inputs'), { trunk: 'develop', references: ['12', '7'] });
      assertBlockedBeforeWaves(run, MALFORMED_FACTS);
    });
  },
  'SD-02': () => {
    test('real gather-facts.sh, create-working-branch.sh and molt.sh stdout deliver a plan end to end', async () => {
      const scratch = makeScratchRepo();
      const run = await runWorkflow(LAUNCH, realResults(scratch));
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'branch-1', 'work-1-STEP-001', 'commit-1-1']);
      const head = runGitIn(scratch, ['rev-parse', 'HEAD']);
      assert.equal(runGitIn(scratch, ['symbolic-ref', '--short', 'HEAD']), 'feature/cache');
      assert.equal(runGitIn(scratch, ['log', '-1', '--format=%s']), 'feat: deliver the wave');
      assert.ok(run.result.message.includes('Commits this run made:\n- ' + head), run.result.message);
      assert.equal(readDataBlock(callOf(run, 'branch-1').prompt, 'inputs')['trunk-freshness'], 'skipped');
    });
    test('the facts runner invokes gather-facts with a JSON inputs block under the runner read-only sentence', async () => {
      const run = await runWorkflow({ request: REQUEST, references: [5] }, happyResults());
      const call = callOf(run, 'facts-1');
      assert.ok(call.prompt.startsWith('Invoke the hivemind:gather-facts skill once, with the trunk and references in the inputs block below and no remote.\n'));
      assert.ok(call.prompt.includes(lib.runnerReadOnlySentence()));
      assert.ok(call.prompt.includes('set stdout to its stdout, word for word, every line.'));
      assert.deepEqual(readDataBlock(call.prompt, 'inputs'), { trunk: 'main', references: ['5'] });
      assert.equal(call.opts.agentType, 'hivemind:drone');
      assert.equal(call.opts.model, 'haiku');
      assert.equal(call.opts.phase, 'Facts');
      assert.deepEqual(Object.keys(call.opts.schema.properties), ['outcome', 'stdout', 'stderr']);
      assert.equal(run.phases[0], 'Facts');
    });
    const goodStdout = factsStdout();
    for (const [label, relay] of [
      ['no result', null],
      ['an empty object', {}],
      ['an unknown outcome', { outcome: 'done', stdout: goodStdout }],
      ['ran with no stdout', { outcome: 'ran' }],
      ['a missing line', { outcome: 'ran', stdout: goodStdout.replace('cut: none\n', '') }],
      ['an unknown line', { outcome: 'ran', stdout: goodStdout + 'remote: origin\n' }],
      ['a duplicate line', { outcome: 'ran', stdout: goodStdout + 'cut: none\n' }],
      ['a value off its pattern', { outcome: 'ran', stdout: goodStdout.replace('delivery: ready', 'delivery: maybe') }],
      ['CR line ends', { outcome: 'ran', stdout: goodStdout.replace(/\n/g, '\r\n') }],
      ['an extra field', { outcome: 'ran', stdout: goodStdout, note: 'x' }]
    ]) {
      test(`a relay with ${label} blocks as malformed facts before planning`, async () => {
        const run = await runWorkflow(LAUNCH, { 'facts-1': relay });
        assertBlockedBeforeWaves(run, MALFORMED_FACTS);
        assert.deepEqual(labelsOf(run), ['facts-1']);
      });
    }
    test('a blocked relay names its blocker line', async () => {
      const run = await runWorkflow(LAUNCH, { 'facts-1': { outcome: 'blocked', stderr: 'blocker: not a work tree\n' } });
      assertBlockedBeforeWaves(run, 'The facts step was blocked, so the delivery stopped before planning: blocker: not a work tree');
    });
  },
  'SD-03': () => {
    for (const [label, changes, launch] of [
      ['a trunk line other than the launch trunk', { trunk: 'master', branch: 'master' }, LAUNCH],
      ['no branch line with head_state branch', { branch: undefined }, LAUNCH],
      ['a branch line with head_state detached', { head_state: 'detached' }, LAUNCH],
      ['delivery ready with a stop', { delivery_stops: 'dirty_paths' }, LAUNCH],
      ['a cut with no cut_fields stop', { cut: 'references' }, LAUNCH],
      ['unsafe_name with no stop', { head_state: 'unsafe_name', branch: undefined }, LAUNCH],
      ['counts that do not fit fresh', { trunk_behind: '2' }, LAUNCH],
      ['a repeated stop', { delivery: 'stop', delivery_stops: 'dirty_paths,dirty_paths' }, LAUNCH],
      ['an unsafe external_texts count', { external_texts: '9007199254740993' }, LAUNCH],
      ['a trunk line for another launch trunk', {}, { request: REQUEST, trunk: 'develop' }]
    ]) {
      test(`${label} blocks as malformed facts`, async () => {
        const run = await runWorkflow(launch, { 'facts-1': factsRelay(changes) });
        assertBlockedBeforeWaves(run, MALFORMED_FACTS);
        assert.deepEqual(labelsOf(run), ['facts-1']);
      });
    }
    test('the check is lib/facts.js isConsistentFactsRelay against the launch trunk', async () => {
      assert.ok(/isConsistentFactsRelay\(facts, trunk\)/.test(mainSource));
      const results = happyResults({ 'facts-1': factsRelay({ trunk: 'develop', branch: 'develop' }), 'plan-1': planResult(makePlan({ base: 'develop' })) });
      const run = await runWorkflow({ request: REQUEST, trunk: 'develop' }, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
    });
  },
  'SD-04': () => {
    test('a cut stops before the scan and planning, naming the fields', async () => {
      const relay = factsRelay({ cut: 'references,pull_requests', delivery: 'stop', delivery_stops: 'cut_fields', external_texts: '3' });
      const run = await runWorkflow(LAUNCH, { 'facts-1': relay });
      assertBlockedBeforeWaves(run, 'The facts are incomplete: GitHub could not be read in full for references, pull_requests. Planning needs complete facts, so the delivery stopped before planning.');
      assert.deepEqual(labelsOf(run), ['facts-1']);
      assert.deepEqual(run.phases, ['Facts']);
    });
  },
  'SD-05': () => {
    for (const [stop, changes] of [
      ['dirty_paths', {}],
      ['operation_in_progress', {}],
      ['closed_pr_on_branch', {}],
      ['history_unavailable', {}],
      ['branch_name_unsafe', { head_state: 'unsafe_name', branch: undefined }]
    ]) {
      test(`delivery stop ${stop} stops before the scan and planning with its fixed line`, async () => {
        const relay = factsRelay({ delivery: 'stop', delivery_stops: stop, external_texts: '2', ...changes });
        const run = await runWorkflow(LAUNCH, { 'facts-1': relay });
        assertBlockedBeforeWaves(run, NOT_READY + '\n- ' + main.deliveryStopLine(stop));
        assert.deepEqual(labelsOf(run), ['facts-1']);
      });
    }
    test('each stop of a list gets its own line, in order', async () => {
      const run = await runWorkflow(LAUNCH, { 'facts-1': factsRelay({ delivery: 'stop', delivery_stops: 'operation_in_progress,dirty_paths' }) });
      assert.equal(run.result.message, [NOT_READY, '- ' + main.deliveryStopLine('operation_in_progress'), '- ' + main.deliveryStopLine('dirty_paths')].join('\n'));
    });
    test('the dirty paths line says the run never commits, stashes or discards an edit it did not make', () => {
      assert.ok(main.deliveryStopLine('dirty_paths').includes('The run never commits, stashes or discards an edit it did not make'));
    });
    test('every facts delivery stop has a fixed line, and an unknown stop throws', () => {
      for (const stop of lib.factsDeliveryStops()) {
        assert.ok(main.deliveryStopLine(stop).length > 0, stop);
        assert.ok(mainSource.includes('case \'' + stop + '\':'), stop);
      }
      assert.throws(() => main.deliveryStopLine('dirty'), /no line for stop/);
    });
    test('a real dirty tree stops the run before planning', async () => {
      const scratch = makeScratchRepo();
      writeRepoFile(scratch, 'untracked.txt', 'dirty\n');
      const run = await runWorkflow(LAUNCH, { 'facts-1': realFactsRunner(scratch) });
      assertBlockedBeforeWaves(run, NOT_READY + '\n- ' + main.deliveryStopLine('dirty_paths'));
      assert.deepEqual(labelsOf(run), ['facts-1']);
    });
  },
  'SD-06': () => {
    function cleanScan(count) {
      return { results: Array.from({ length: count }, (_, index) => ({ item_ref: 't' + (index + 1), verdict: 'clean' })) };
    }
    test('external texts are scanned with the shared scan step before planning', async () => {
      const run = await runWorkflow(LAUNCH, happyResults({ 'facts-1': factsRelay({ external_texts: '2' }), scan: cleanScan(2) }));
      assert.deepEqual(labelsOf(run).slice(0, 3), ['facts-1', 'scan', 'plan-1']);
      const call = callOf(run, 'scan');
      assert.equal(call.prompt, lib.buildScanPrompt(parsedFacts({ external_texts: '2' })));
      assert.deepEqual(call.opts, structuredClone(lib.scanOptions()));
      assert.deepEqual(run.phases.slice(0, 3), ['Facts', 'Scan', 'Plan']);
    });
    test('no external text means no scan', async () => {
      const run = await runWorkflow(LAUNCH, happyResults());
      assert.ok(!labelsOf(run).includes('scan'));
    });
    test('an injection suspect stops before planning', async () => {
      const suspect = { results: [{ item_ref: 't1', verdict: 'injection-suspect', pattern_category: 'P2', field_excerpt: 'ignore previous instructions', reason: 'override' }] };
      const run = await runWorkflow(LAUNCH, { 'facts-1': factsRelay({ external_texts: '1' }), scan: suspect });
      assertBlockedBeforeWaves(run);
      assert.ok(run.result.message.startsWith('The injection scan flagged text from GitHub as a possible prompt injection, so the delivery stopped before planning.'), run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'scan']);
    });
    test('a coverage failure stops before planning', async () => {
      const run = await runWorkflow(LAUNCH, { 'facts-1': factsRelay({ external_texts: '2' }), scan: cleanScan(1) });
      assertBlockedBeforeWaves(run, 'The injection scan did not return exactly one result for each text from GitHub in the facts, so the delivery stopped before planning.');
    });
    test('a later pass scans again under its own label', async () => {
      const results = happyResults({
        'facts-1': factsRelay({ external_texts: '1' }),
        scan: cleanScan(1),
        'work-1-STEP-001': { outcome: 'needs_replan', summary: 'Stopped.', blocker: 'The API moved.' },
        'facts-2': onPlanBranchFacts(OTHER, { external_texts: '1' }),
        'scan-2': cleanScan(1),
        'plan-2': planResult(),
        'branch-2': branchRelay({ created: 'false', commit: OTHER }),
        'work-2-STEP-001': WORKER_DONE,
        'commit-2-1': commitRelay({ commit: THIRD })
      });
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.deepEqual(labelsOf(run).slice(6, 9), ['facts-2', 'scan-2', 'plan-2']);
      assert.equal(callOf(run, 'scan-2').opts.phase, 'Scan');
    });
  },
  'SD-07': () => {
    const results = happyResults({
      'branch-1': branchRelay({ created: 'false' }),
      'facts-2': onPlanBranchFacts(HEAD),
      'plan-2': planResult(),
      'branch-2': branchRelay({ created: 'false' }),
      'work-2-STEP-001': { outcome: 'needs_replan', summary: 'Stopped.', blocker: 'The API moved.' },
      'commit-2-1': commitRelay(),
      'facts-3': onPlanBranchFacts(OTHER),
      'plan-3': planResult(makePlan({ steps: [makeStep('STEP-002', ['src/api.js'])] })),
      'branch-3': branchRelay({ created: 'false', commit: OTHER }),
      'work-3-STEP-002': WORKER_DONE,
      'commit-3-1': commitRelay({ commit: THIRD })
    });
    test('passes start at launch, after a branch switch and after needs_replan only', async () => {
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'branch-1', 'facts-2', 'plan-2', 'branch-2', 'work-2-STEP-001', 'commit-2-1', 'facts-3', 'plan-3', 'branch-3', 'work-3-STEP-002', 'commit-3-1']);
    });
    test('every planner call follows the facts step of its own pass', async () => {
      const run = await runWorkflow(LAUNCH, results);
      const labels = labelsOf(run);
      labels.forEach((label, index) => {
        if (!/^(plan|revise)-/.test(label)) {
          return;
        }
        const factsIndex = labels.slice(0, index).map((candidate) => candidate.startsWith('facts-')).lastIndexOf(true);
        const between = labels.slice(factsIndex + 1, index);
        assert.ok(between.every((candidate) => /^(scan|plan-|revise-)/.test(candidate)), label + ' after ' + JSON.stringify(between));
        if (label.startsWith('plan-')) {
          assert.equal(label.slice('plan-'.length), labels[factsIndex].slice('facts-'.length));
        }
        assert.equal(run.calls[index].opts.agentType, 'hivemind:cerebrate');
      });
    });
    test('a replan prompt says why, and the first plan prompt has no replan block', async () => {
      const run = await runWorkflow(LAUNCH, results);
      assert.ok(!callOf(run, 'plan-1').prompt.includes('<replan>'));
      assert.ok(readDataBlock(callOf(run, 'plan-2').prompt, 'replan').startsWith('The branch step switched'));
      assert.equal(readDataBlock(callOf(run, 'plan-3').prompt, 'replan'), 'Step "STEP-001" needs a new plan: The API moved.');
    });
  },
  'SD-08': () => {
    const schemaProblem = 'The planner returned a plan that does not fit the plan schema, so the delivery stopped.';
    for (const [label, result, message] of [
      ['a blocked planner', { outcome: 'blocked', blocker: 'No such module.', questions: [] }, 'The planner could not plan the delivery: No such module.'],
      ['a blocked planner with no reason', { outcome: 'blocked', questions: [] }, 'The planner could not plan the delivery: it gave no reason.'],
      ['a blocked result that fails the schema', { outcome: 'blocked', blocker: 'No such module.' }, schemaProblem],
      ['no result', null, 'The planner returned no result, so the delivery stopped.'],
      ['a complete result with no plan', { outcome: 'complete', questions: [] }, schemaProblem],
      ['a plan with no steps', planResult(makePlan({ steps: [] })), schemaProblem],
      ['a plan with an unknown field', planResult({ ...makePlan(), extra: 1 }), schemaProblem],
      ['a plan with a bad classification', planResult(makePlan({ classification: 'feat' })), schemaProblem],
      ['questions that are not briefs', planResult(makePlan(), [{ id: 'Q1' }]), schemaProblem],
      ['an unknown dependency', planResult(makePlan({ steps: [makeStep('STEP-001', ['a.js'], { depends_on: ['STEP-009'] })] })), 'The plan steps cannot be scheduled, so the delivery stopped: depends_on references unknown step id: "STEP-009"'],
      ['a dependency cycle', planResult(makePlan({ steps: [makeStep('A', ['a.js'], { depends_on: ['B'] }), makeStep('B', ['b.js'], { depends_on: ['A'] })] })), 'The plan steps cannot be scheduled, so the delivery stopped: dependency cycle detected among plan steps'],
      ['a trunk freshness other than the facts', planResult(makePlan({ trunk_freshness: 'behind' })), 'The plan copies a trunk freshness other than the facts, so the delivery stopped.'],
      ['an unsafe branch', planResult(makePlan({ branch: 'feature/..x' })), 'The plan names a branch or base that is not a safe git name, so the delivery stopped.'],
      ['an unsafe base', planResult(makePlan({ base: '-main' })), 'The plan names a branch or base that is not a safe git name, so the delivery stopped.']
    ]) {
      test(`${label} blocks before the branch step`, async () => {
        const run = await runWorkflow(LAUNCH, { 'facts-1': factsRelay(), 'plan-1': result });
        assertBlockedBeforeWaves(run, message);
        assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1']);
      });
    }
    test('a run started on another branch delivers on it: another plan branch blocks', async () => {
      const run = await runWorkflow(LAUNCH, { 'facts-1': factsRelay({ branch: 'feature/old' }), 'plan-1': planResult() });
      assertBlockedBeforeWaves(run, 'The run started on branch "feature/old" and delivers on it, but the plan names branch "feature/cache", so the delivery stopped.');
    });
    test('a run started on another branch with a plan naming it goes on', async () => {
      const results = happyResults({ 'facts-1': factsRelay({ branch: 'feature/cache' }), 'branch-1': branchRelay({ created: 'false' }) });
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
    });
    test('a run started on trunk or a detached HEAD takes the plan branch', async () => {
      const detached = happyResults({ 'facts-1': factsRelay({ head_state: 'detached', branch: undefined }) });
      assert.equal((await runWorkflow(LAUNCH, detached)).result.outcome, 'complete');
      assert.equal((await runWorkflow(LAUNCH, happyResults())).result.outcome, 'complete');
    });
    test('the planner result schema is PLAN_SCHEMA under plan with outcome, questions and blocker', async () => {
      const run = await runWorkflow(LAUNCH, happyResults());
      const options = callOf(run, 'plan-1').opts;
      assert.equal(options.agentType, 'hivemind:cerebrate');
      assert.equal(options.phase, 'Plan');
      const schema = options.schema;
      assert.deepEqual(Object.keys(schema.properties), ['outcome', 'plan', 'questions', 'blocker']);
      assert.deepEqual(schema.required, ['outcome', 'questions']);
      const { $schema: planDialect, ...planWithoutDialect } = planSchema;
      assert.ok(planDialect !== undefined);
      assert.deepEqual(schema.properties.plan, { ...planWithoutDialect, description: planSchema.description + ' Only with outcome complete.' });
      const { $schema: briefDialect, ...briefWithoutDialect } = briefSchema;
      assert.ok(briefDialect !== undefined);
      assert.deepEqual(schema.properties.questions.items, briefWithoutDialect);
    });
    for (const [label, settled] of [['no settled', undefined], ['a label past the shown count', ['Q2']]]) {
      test(`a revise result with ${label} blocks before the branch step with the schema message`, async () => {
        const gated = planResult(makePlan(), [makeGatedBrief('GATED_PROBLEM')]);
        const revised = settled === undefined ? planResult() : reviseResult(planResult(), settled);
        const args = { ...LAUNCH, answers: { 'round-1': 'Take option A.' } };
        const run = await runWorkflow(args, happyResults({ 'plan-1': gated, 'revise-1': revised }));
        assertBlockedBeforeWaves(run, schemaProblem);
        assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'revise-1']);
      });
    }
  },
  'SD-09': () => {
    test('taken planner questions and the plan acceptance are listed in the final message', async () => {
      const strong = makeBrief({ problem: 'STRONG_PROBLEM' });
      const run = await runWorkflow(LAUNCH, happyResults({ 'plan-1': planResult(makePlan(), [strong]) }));
      assert.equal(run.result.outcome, 'complete');
      const taken = [{ brief: strong }, { brief: main.buildPlanAcceptanceBrief(makePlan()) }];
      assert.ok(run.result.message.endsWith(lib.renderDecisions(taken)), run.result.message);
    });
    test('a brief kind never picks the rule: the call site kind does', async () => {
      const hardStopKind = makeBrief({ problem: 'KIND_PROBLEM', kind: 'external_effect' });
      const run = await runWorkflow(LAUNCH, happyResults({ 'plan-1': planResult(makePlan(), [hardStopKind]) }));
      assert.equal(run.result.outcome, 'complete');
      assert.ok(run.result.message.includes('KIND_PROBLEM'));
    });
    test('a gated planner question pauses with resume_args {answers} and no branch step', async () => {
      const run = await runWorkflow(LAUNCH, { 'facts-1': factsRelay(), 'plan-1': planResult(makePlan(), [makeGatedBrief('GATED_PROBLEM')]) });
      assert.equal(run.result.needs_user, true);
      assert.deepEqual(run.result.resume_args, { answers: {} });
      assert.ok(run.result.message.includes('Q1. GATED_PROBLEM'));
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1']);
    });
    test('every ask of a pass goes in one pause', async () => {
      const plan = effectPlan('Publish to the registry.', false);
      const run = await runWorkflow(LAUNCH, { 'facts-1': factsRelay(), 'plan-1': planResult(plan, [makeGatedBrief('GATED_PROBLEM')]) });
      assert.equal(run.result.needs_user, true);
      assert.ok(run.result.message.startsWith('I need your answers on 2 questions before I go on.'), run.result.message);
      assert.ok(run.result.message.includes('Q1. GATED_PROBLEM'));
      assert.ok(run.result.message.includes('Q2. Plan step "STEP-001" has an effect outside the repo'));
    });
    test('a reply goes to a revise pass and the run goes on', async () => {
      const paused = await runWorkflow(LAUNCH, { 'facts-1': factsRelay(), 'plan-1': planResult(makePlan(), [makeGatedBrief('GATED_PROBLEM')]) });
      const results = happyResults({ 'plan-1': planResult(makePlan(), [makeGatedBrief('GATED_PROBLEM')]), 'revise-1': reviseResult(planResult(), ['Q1']) });
      const run = await runWorkflow(resumeWith(LAUNCH, paused.result, 'Take option B.'), results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      const revise = callOf(run, 'revise-1');
      assert.equal(revise.opts.phase, 'Revise');
      assert.equal(readDataBlock(revise.prompt, 'reply'), 'Take option B.');
      assert.equal(readDataBlock(revise.prompt, 'request'), REQUEST);
      assert.deepEqual(readDataBlock(revise.prompt, 'earlier_plan'), makePlan());
      assert.ok(readDataBlock(revise.prompt, 'questions').includes('Q1. GATED_PROBLEM'));
    });
    test('at the pause limit the run finishes complete, lists the open questions and runs nothing further', async () => {
      const gated = planResult(makePlan(), [makeGatedBrief('GATED_PROBLEM')]);
      const args = { ...LAUNCH, answers: { 'round-1': 'one', 'round-2': 'two', 'round-3': 'three' } };
      const revised = reviseResult(gated, []);
      const run = await runWorkflow(args, { 'facts-1': factsRelay(), 'plan-1': gated, 'revise-1': revised, 'revise-2': revised, 'revise-3': revised });
      assert.equal(run.result.needs_user, false);
      assert.equal(run.result.outcome, 'complete');
      assert.ok(run.result.message.startsWith('The delivery ran no further step, because questions are still open.\n\nI stopped asking after 3 rounds of questions.'), run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'revise-1', 'revise-2', 'revise-3']);
    });
    test('replies too long to carry finish complete with the open questions', async () => {
      const gated = planResult(makePlan(), [makeGatedBrief('GATED_PROBLEM')]);
      const args = { ...LAUNCH, answers: { 'round-1': 'x'.repeat(5000) } };
      const run = await runWorkflow(args, { 'facts-1': factsRelay(), 'plan-1': gated, 'revise-1': reviseResult(gated, []) });
      assert.equal(run.result.outcome, 'complete');
      assert.ok(run.result.message.includes('I stopped asking because your replies so far are too long to carry'), run.result.message);
    });
    test('an autonomy arg is ignored: the table default level takes the plan', async () => {
      const run = await runWorkflow({ ...LAUNCH, autonomy: 'low' }, happyResults());
      assert.equal(run.result.outcome, 'complete');
      assert.ok(!mainSource.includes('.autonomy'));
    });
    test('a plan acceptance ask pauses and is not asked again once replied to', async () => {
      const surfaced = buildWithSurfaceKinds(['plan_acceptance']);
      const paused = await runWorkflow(LAUNCH, happyResults(), surfaced);
      assert.equal(paused.result.needs_user, true);
      assert.ok(paused.result.message.includes('Q1. Start delivering the plan'));
      const run = await runWorkflow(resumeWith(LAUNCH, paused.result, 'Yes, go.'), happyResults({ 'revise-1': reviseResult(planResult(), ['Q1']) }), surfaced);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.ok(!run.result.message.includes('Decided for you'), run.result.message);
    });
    test('a reply that settles only the plan acceptance asks the trunk question again', async () => {
      const surfaced = buildWithSurfaceKinds(['plan_acceptance', 'trunk_stale']);
      const behindPlan = planResult(makePlan({ trunk_freshness: 'behind' }));
      const results = happyResults({
        'facts-1': factsRelay({ trunk_freshness: 'behind', trunk_behind: '4' }),
        'plan-1': behindPlan,
        'revise-1': reviseResult(behindPlan, ['Q1']),
        'revise-2': reviseResult(behindPlan, ['Q1']),
        'branch-1': branchRelay({ warning: main.branchWarningTexts().stale })
      });
      const paused = await runWorkflow(LAUNCH, results, surfaced);
      assert.ok(paused.result.message.startsWith('I need your answers on 2 questions before I go on.'), paused.result.message);
      assert.ok(paused.result.message.includes('Q1. Start delivering the plan'), paused.result.message);
      assert.ok(paused.result.message.includes('Q2. The trunk may not be up to date'), paused.result.message);
      const second = await runWorkflow(resumeWith(LAUNCH, paused.result, 'Accept the plan.'), results, surfaced);
      assert.equal(second.result.needs_user, true);
      assert.deepEqual(labelsOf(second), ['facts-1', 'plan-1', 'revise-1']);
      assert.deepEqual(second.result.resume_args, { answers: { 'round-1': 'Accept the plan.' } });
      assert.ok(second.result.message.startsWith('I need your answer on 1 question before I go on.'), second.result.message);
      assert.ok(second.result.message.includes('Q1. The trunk may not be up to date'), second.result.message);
      assert.ok(!second.result.message.includes('Start delivering the plan'), second.result.message);
      const run = await runWorkflow(resumeWith(LAUNCH, second.result, 'Go on from the trunk.'), results, surfaced);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'revise-1', 'revise-2', 'branch-1', 'work-1-STEP-001', 'commit-1-1']);
      assert.equal(readDataBlock(callOf(run, 'branch-1').prompt, 'inputs')['trunk-freshness'], 'stale');
    });
    test('the revise call schema is the plan result schema with a required settled enum of the shown labels', async () => {
      const plan = effectPlan('Publish to the registry.', false);
      const results = happyResults({ 'plan-1': planResult(plan, [makeGatedBrief('GATED_PROBLEM')]), 'revise-1': reviseResult(planResult(plan), ['Q1', 'Q2']) });
      const run = await runWorkflow({ ...LAUNCH, answers: { 'round-1': 'Yes to both.' } }, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      const planCallSchema = callOf(run, 'plan-1').opts.schema;
      const reviseCall = callOf(run, 'revise-1');
      const reviseSchema = reviseCall.opts.schema;
      assert.ok(!Object.keys(planCallSchema.properties).includes('settled'));
      assert.deepEqual(planCallSchema.required, ['outcome', 'questions']);
      assert.deepEqual(reviseSchema.required, ['outcome', 'questions', 'settled']);
      assert.equal(reviseSchema.additionalProperties, false);
      const { settled: settledProperty, ...planProperties } = reviseSchema.properties;
      assert.deepEqual(planProperties, planCallSchema.properties);
      assert.equal(settledProperty.type, 'array');
      assert.ok(settledProperty.description.startsWith('The label, like Q1, of each shown question the reply settles.'), settledProperty.description);
      assert.deepEqual(settledProperty.items, { type: 'string', enum: ['Q1', 'Q2'] });
      assert.ok(reviseCall.prompt.includes('Set settled to the label, like Q1, of each shown question the reply settles.'), reviseCall.prompt);
    });
    test('an effect never settled stays open at the pause limit and nothing runs', async () => {
      const summary = 'Publish to the registry.';
      const revised = reviseResult(planResult(effectPlan(summary, false)), []);
      const args = { ...LAUNCH, answers: { 'round-1': 'one', 'round-2': 'two', 'round-3': 'three' } };
      const run = await runWorkflow(args, happyResults({ 'plan-1': planResult(effectPlan(summary, false)), 'revise-1': revised, 'revise-2': revised, 'revise-3': revised }));
      assert.equal(run.result.needs_user, false);
      assert.equal(run.result.outcome, 'complete');
      assert.ok(run.result.message.startsWith('The delivery ran no further step, because questions are still open.\n\nI stopped asking after 3 rounds of questions.'), run.result.message);
      assert.ok(run.result.message.includes('\n  Q1. Plan step "STEP-001" has an effect outside the repo that cannot be undone'), run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'revise-1', 'revise-2', 'revise-3']);
    });
  },
  'SD-10': () => {
    test('the trunk freshness map keys equal the facts-schema enum', () => {
      const keys = Object.keys(main.trunkFreshnessMap()).sort();
      assert.deepEqual(keys, [...factsSchema.properties.repository.properties.trunk_freshness.enum].sort());
      assert.deepEqual(keys, [...planSchema.properties.trunk_freshness.enum].sort());
      for (const [freshness, mapped] of Object.entries(main.trunkFreshnessMap())) {
        const expected = { fresh: 'fresh', no_remote: 'skipped' }[freshness] || 'decide';
        assert.equal(mapped, expected, freshness);
      }
    });
    test('fresh gives fresh and no_remote gives skipped', async () => {
      const fresh = await runWorkflow(LAUNCH, happyResults());
      assert.equal(readDataBlock(callOf(fresh, 'branch-1').prompt, 'inputs')['trunk-freshness'], 'fresh');
      const results = happyResults({
        'facts-1': factsRelay({ trunk_freshness: 'no_remote' }),
        'plan-1': planResult(makePlan({ trunk_freshness: 'no_remote' })),
        'branch-1': branchRelay({ warning: main.branchWarningTexts().skipped })
      });
      const skipped = await runWorkflow(LAUNCH, results);
      assert.equal(skipped.result.outcome, 'complete', skipped.result.message);
      assert.equal(readDataBlock(callOf(skipped, 'branch-1').prompt, 'inputs')['trunk-freshness'], 'skipped');
    });
    for (const [freshness, ahead, behind] of [['behind', '0', '2'], ['ahead', '1', '0'], ['diverged', '1', '3'], ['fetch_failed', '0', '0'], ['no_local_trunk', '0', '0']]) {
      test(`${freshness} goes through trunk_stale: a take gives stale and is listed`, async () => {
        const results = happyResults({
          'facts-1': factsRelay({ trunk_freshness: freshness, trunk_ahead: ahead, trunk_behind: behind }),
          'plan-1': planResult(makePlan({ trunk_freshness: freshness })),
          'branch-1': branchRelay({ warning: main.branchWarningTexts().stale })
        });
        const run = await runWorkflow(LAUNCH, results);
        assert.equal(run.result.outcome, 'complete', run.result.message);
        assert.equal(readDataBlock(callOf(run, 'branch-1').prompt, 'inputs')['trunk-freshness'], 'stale');
        assert.ok(run.result.message.includes('The trunk may not be up to date: its freshness is ' + freshness), run.result.message);
      });
    }
    test('no_trunk never reaches the branch step: history_unavailable stops first', async () => {
      const relay = factsRelay({ trunk_freshness: 'no_trunk', delivery: 'stop', delivery_stops: 'history_unavailable' });
      const run = await runWorkflow(LAUNCH, { 'facts-1': relay });
      assertBlockedBeforeWaves(run, NOT_READY + '\n- ' + main.deliveryStopLine('history_unavailable'));
    });
    test('a trunk_stale ask pauses, and once replied to gives stale without asking again', async () => {
      const surfaced = buildWithSurfaceKinds(['trunk_stale']);
      const results = happyResults({
        'facts-1': factsRelay({ trunk_freshness: 'behind', trunk_behind: '4' }),
        'plan-1': planResult(makePlan({ trunk_freshness: 'behind' })),
        'revise-1': reviseResult(planResult(makePlan({ trunk_freshness: 'behind' })), ['Q1']),
        'branch-1': branchRelay({ warning: main.branchWarningTexts().stale })
      });
      const paused = await runWorkflow(LAUNCH, results, surfaced);
      assert.equal(paused.result.needs_user, true);
      assert.ok(paused.result.message.includes('Q1. The trunk may not be up to date'), paused.result.message);
      assert.deepEqual(labelsOf(paused), ['facts-1', 'plan-1']);
      const run = await runWorkflow(resumeWith(LAUNCH, paused.result, 'Go on.'), results, surfaced);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.equal(readDataBlock(callOf(run, 'branch-1').prompt, 'inputs')['trunk-freshness'], 'stale');
    });
    test('a real stale trunk passes stale to create-working-branch.sh and its warning parses', async () => {
      const scratch = makeScratchRepo();
      const head = runGitIn(scratch, ['rev-parse', 'HEAD']);
      const results = realResults(scratch, {
        'facts-1': factsRelay({ head: head, trunk_freshness: 'behind', trunk_behind: '1' }),
        'plan-1': planResult(makePlan({ trunk_freshness: 'behind' }))
      });
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.equal(readDataBlock(callOf(run, 'branch-1').prompt, 'inputs')['trunk-freshness'], 'stale');
    });
  },
  'SD-11': () => {
    const summary = 'Publish version 2 to the package registry.';
    test('an irreversible effect asks before the branch step and any wave, with its summary as verbatim data', async () => {
      const run = await runWorkflow(LAUNCH, { 'facts-1': factsRelay(), 'plan-1': planResult(effectPlan(summary, false)) });
      assert.equal(run.result.needs_user, true);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1']);
      assert.ok(run.result.message.includes('Exact text:\n' + summary), run.result.message);
      assert.ok(run.result.message.includes('Why I am asking: ' + lib.askReasonLine('hard_stop')), run.result.message);
    });
    test('a replied effect is not asked again when the revised plan keeps it', async () => {
      const results = happyResults({ 'plan-1': planResult(effectPlan(summary, false)), 'revise-1': reviseResult(planResult(effectPlan(summary, false)), ['Q1']) });
      const paused = await runWorkflow(LAUNCH, results);
      const run = await runWorkflow(resumeWith(LAUNCH, paused.result, 'Yes, publish it.'), results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'revise-1', 'branch-1', 'work-1-STEP-001', 'commit-1-1']);
    });
    test('a changed effect is asked again', async () => {
      const results = happyResults({ 'plan-1': planResult(effectPlan(summary, false)), 'revise-1': reviseResult(planResult(effectPlan('Publish to a staging registry.', false)), ['Q1']) });
      const paused = await runWorkflow(LAUNCH, results);
      const run = await runWorkflow(resumeWith(LAUNCH, paused.result, 'Only staging.'), results);
      assert.equal(run.result.needs_user, true);
      assert.deepEqual(run.result.resume_args, { answers: { 'round-1': 'Only staging.' } });
      assert.ok(run.result.message.includes('Exact text:\nPublish to a staging registry.'));
    });
    test('a revised plan that drops the effect goes on', async () => {
      const results = happyResults({ 'plan-1': planResult(effectPlan(summary, false)), 'revise-1': reviseResult(planResult(), []) });
      const paused = await runWorkflow(LAUNCH, results);
      const run = await runWorkflow(resumeWith(LAUNCH, paused.result, 'Do not publish.'), results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
    });
    function partlySettledResults(settled) {
      const plan = effectPlan(summary, false);
      return happyResults({ 'plan-1': planResult(plan, [makeGatedBrief('GATED_PROBLEM')]), 'revise-1': reviseResult(planResult(plan), settled) });
    }
    test('an effect the reply did not settle is asked again before any wave', async () => {
      const results = partlySettledResults(['Q1']);
      const paused = await runWorkflow(LAUNCH, results);
      assert.ok(paused.result.message.includes('Q1. GATED_PROBLEM'), paused.result.message);
      assert.ok(paused.result.message.includes('Q2. Plan step "STEP-001" has an effect outside the repo'), paused.result.message);
      const reply = 'Take option B on the key format.';
      const run = await runWorkflow(resumeWith(LAUNCH, paused.result, reply), results);
      assert.equal(run.result.needs_user, true);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'revise-1']);
      assert.deepEqual(run.result.resume_args, { answers: { 'round-1': reply } });
      assert.ok(run.result.message.includes('Exact text:\n' + summary), run.result.message);
      assert.ok(labelsOf(run).every((label) => !/^(branch|work|commit)-/.test(label)), JSON.stringify(labelsOf(run)));
    });
    test('an effect the reply settled with the other question goes on to the branch step and the waves', async () => {
      const results = partlySettledResults(['Q1', 'Q2']);
      const paused = await runWorkflow(LAUNCH, results);
      const run = await runWorkflow(resumeWith(LAUNCH, paused.result, 'Option B, and yes, publish it.'), results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'revise-1', 'branch-1', 'work-1-STEP-001', 'commit-1-1']);
    });
    test('a reversible effect is not asked and is listed in the final message', async () => {
      const run = await runWorkflow(LAUNCH, happyResults({ 'plan-1': planResult(effectPlan('Post a preview link.', true)) }));
      assert.equal(run.result.outcome, 'complete');
      assert.ok(run.result.message.includes('Effects outside the repo that the plan declares as reversible:\n- step "STEP-001": "Post a preview link."'), run.result.message);
    });
    test('the external_effect kind is a hard stop of the autonomy table', () => {
      assert.deepEqual({ ...lib.decide({ kind: 'external_effect', level: 'high', brief: main.buildExternalEffectBrief('S1', summary) }, readJson('plugin/references/decision-autonomy-table.json'), briefSchema) }, { action: 'ask', reason: 'hard_stop' });
      assert.ok(lib.validateSchema(briefSchema, main.buildExternalEffectBrief('S1', summary)).ok);
      assert.ok(lib.validateSchema(briefSchema, main.buildTrunkStaleBrief(parsedFacts({ trunk_freshness: 'behind', trunk_behind: '1' }))).ok);
      assert.ok(lib.validateSchema(briefSchema, main.buildPlanAcceptanceBrief(makePlan())).ok);
    });
  },
  'SD-12': () => {
    test('branch, base and trunk appear only in the JSON inputs block, under the git-script sentence', async () => {
      const results = happyResults({
        'facts-1': factsRelay({ trunk: 'trunk-zq', branch: 'trunk-zq' }),
        'plan-1': planResult(makePlan({ branch: 'feature/branch-zq', base: 'base-zq', classification: 'bugfix' })),
        'branch-1': branchRelay({ branch: 'feature/branch-zq' }),
        'commit-1-1': commitRelay({ branch: 'feature/branch-zq' })
      });
      const run = await runWorkflow({ request: REQUEST, trunk: 'trunk-zq' }, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      const call = callOf(run, 'branch-1');
      assert.deepEqual(readDataBlock(call.prompt, 'inputs'), { base: 'base-zq', working_branch: 'feature/branch-zq', classification: 'bugfix', 'trunk-freshness': 'fresh', trunk: 'trunk-zq' });
      const outsideInputs = withoutDataBlock(call.prompt, 'inputs');
      for (const name of ['trunk-zq', 'branch-zq', 'base-zq', 'bugfix']) {
        assert.ok(!outsideInputs.includes(name), name);
      }
      assert.ok(call.prompt.startsWith('Invoke the hivemind:create-working-branch skill once'));
      assert.ok(call.prompt.includes(main.gitScriptSentence('hivemind:create-working-branch')));
      assert.equal(call.opts.agentType, 'hivemind:drone');
      assert.equal(call.opts.model, 'haiku');
      assert.equal(call.opts.phase, 'Branch');
    });
    for (const [label, relay, freshness] of [
      ['a branch other than the plan branch', branchRelay({ branch: 'feature/other' }), 'fresh'],
      ['no commit line', branchRelay({ commit: undefined }), 'fresh'],
      ['a short commit', branchRelay({ commit: '1234567' }), 'fresh'],
      ['created not a boolean', branchRelay({ created: 'yes' }), 'fresh'],
      ['a warning on a fresh trunk', branchRelay({ warning: 'trunk freshness check was skipped' }), 'fresh'],
      ['no warning on a skipped check', branchRelay(), 'no_remote'],
      ['the stale warning on a skipped check', branchRelay({ warning: 'trunk is stale or diverged from origin; proceeding as acknowledged at preflight' }), 'no_remote'],
      ['an unknown warning', branchRelay({ warning: 'trunk is fine' }), 'no_remote'],
      ['a blocked script', { outcome: 'blocked', stderr: 'blocker: working_branch equals trunk\n' }, 'fresh'],
      ['no result', null, 'fresh']
    ]) {
      test(`${label} blocks before any wave`, async () => {
        const results = {
          'facts-1': factsRelay({ trunk_freshness: freshness }),
          'plan-1': planResult(makePlan({ trunk_freshness: freshness })),
          'branch-1': relay
        };
        const run = await runWorkflow(LAUNCH, results);
        assertBlockedBeforeWaves(run);
        assert.ok(/^The branch step (was blocked|returned|reported)/.test(run.result.message), run.result.message);
        assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'branch-1']);
      });
    }
    test('a blocked branch step names its blocker line', async () => {
      const results = { 'facts-1': factsRelay(), 'plan-1': planResult(), 'branch-1': { outcome: 'blocked', stderr: 'blocker: the working tree is dirty\n' } };
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.message.split('\n\n')[0], 'The branch step was blocked, so the delivery stopped before any wave. blocker: the working tree is dirty');
    });
    test('the warning texts are the fixed texts of create-working-branch.sh', () => {
      const scriptText = readText(createBranchPath);
      for (const text of Object.values(main.branchWarningTexts())) {
        assert.ok(scriptText.includes('warning_text=\'' + text + '\''), text);
        assert.ok(/^[a-z ;]+$/.test(text), 'no regex metacharacter in ' + text);
      }
    });
    test('the routing spec keys are the OUTPUT keys of create-working-branch.sh', () => {
      const scriptText = readText(createBranchPath);
      const output = scriptText.slice(scriptText.indexOf('# OUTPUT on success'), scriptText.indexOf('# EXIT CONTRACT'));
      const keys = [...output.matchAll(/^# {3}([a-z_]+): /gm)].map((match) => match[1]);
      assert.deepEqual(Object.keys(main.createWorkingBranchRoutingSpec()), keys);
    });
    test('a trunk spelled refs/heads/main fails safe at the identity-keyed trunk refusal', async () => {
      const scratch = makeScratchRepo();
      runGitIn(scratch, ['branch', 'develop']);
      const head = runGitIn(scratch, ['rev-parse', 'HEAD']);
      const results = realResults(scratch, {
        'facts-1': factsRelay({ trunk: 'refs/heads/main', head: head }),
        'plan-1': planResult(makePlan({ branch: 'main', base: 'develop' }))
      });
      const run = await runWorkflow({ request: REQUEST, trunk: 'refs/heads/main' }, results);
      assertBlockedBeforeWaves(run);
      assert.ok(run.result.message.startsWith('The branch step was blocked, so the delivery stopped before any wave. blocker: working_branch equals trunk'), run.result.message);
    });
  },
  'SD-13': () => {
    test('trunk to a new branch at the same commit: no replan', async () => {
      const run = await runWorkflow(LAUNCH, happyResults());
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'branch-1', 'work-1-STEP-001', 'commit-1-1']);
    });
    test('confirming the branch the facts were taken on: no replan', async () => {
      const results = happyResults({ 'facts-1': onPlanBranchFacts(HEAD), 'branch-1': branchRelay({ created: 'false' }) });
      const run = await runWorkflow(LAUNCH, results);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'branch-1', 'work-1-STEP-001', 'commit-1-1']);
    });
    for (const [label, facts, branch] of [
      ['switching onto an existing branch', factsRelay(), branchRelay({ created: 'false' })],
      ['a new branch at another commit', factsRelay(), branchRelay({ commit: OTHER })],
      ['a detached start where the base commit differs', factsRelay({ head_state: 'detached', branch: undefined }), branchRelay({ commit: OTHER })]
    ]) {
      test(`${label}: facts and planning again before any wave`, async () => {
        const results = happyResults({
          'facts-1': facts,
          'branch-1': branch,
          'facts-2': onPlanBranchFacts(OTHER),
          'plan-2': planResult(),
          'branch-2': branchRelay({ created: 'false', commit: OTHER }),
          'work-2-STEP-001': WORKER_DONE,
          'commit-2-1': commitRelay({ commit: THIRD })
        });
        const run = await runWorkflow(LAUNCH, results);
        assert.equal(run.result.outcome, 'complete', run.result.message);
        assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'branch-1', 'facts-2', 'plan-2', 'branch-2', 'work-2-STEP-001', 'commit-2-1']);
      });
    }
    test('a second switch blocks before any wave', async () => {
      const results = happyResults({
        'branch-1': branchRelay({ created: 'false' }),
        'facts-2': onPlanBranchFacts(HEAD),
        'plan-2': planResult(),
        'branch-2': branchRelay({ created: 'false', commit: OTHER })
      });
      const run = await runWorkflow(LAUNCH, results);
      assertBlockedBeforeWaves(run, 'The branch step switched branch or commit again after a replan, so the delivery stopped before any wave.');
    });
    test('a second plan naming a branch other than the facts branch blocks', async () => {
      const results = happyResults({
        'branch-1': branchRelay({ created: 'false' }),
        'facts-2': onPlanBranchFacts(HEAD),
        'plan-2': planResult(makePlan({ branch: 'feature/other' }))
      });
      const run = await runWorkflow(LAUNCH, results);
      assertBlockedBeforeWaves(run, 'The run started on branch "feature/cache" and delivers on it, but the plan names branch "feature/other", so the delivery stopped.');
    });
    test('real scripts: switching onto an existing branch replans once', async () => {
      const scratch = makeScratchRepo();
      runGitIn(scratch, ['branch', 'feature/cache']);
      const results = realResults(scratch, {
        'facts-2': realFactsRunner(scratch),
        'plan-2': planResult(makePlan({ trunk_freshness: 'no_remote' })),
        'branch-2': realBranchRunner(scratch),
        'work-2-STEP-001': realWorker(scratch),
        'commit-2-1': realCommitRunner(scratch)
      });
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'branch-1', 'facts-2', 'plan-2', 'branch-2', 'work-2-STEP-001', 'commit-2-1']);
    });
    test('real scripts: a detached start at an older commit replans once', async () => {
      const scratch = makeScratchRepo();
      writeRepoFile(scratch, 'second.txt', 'second\n');
      runGitIn(scratch, ['add', 'second.txt']);
      runGitIn(scratch, ['commit', '-q', '-m', 'second']);
      runGitIn(scratch, ['checkout', '-q', '--detach', 'HEAD~1']);
      const results = realResults(scratch, {
        'facts-2': realFactsRunner(scratch),
        'plan-2': planResult(makePlan({ trunk_freshness: 'no_remote' })),
        'branch-2': realBranchRunner(scratch),
        'work-2-STEP-001': realWorker(scratch),
        'commit-2-1': realCommitRunner(scratch)
      });
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'branch-1', 'facts-2', 'plan-2', 'branch-2', 'work-2-STEP-001', 'commit-2-1']);
    });
  },
  'SD-14': () => {
    const plan = makePlan({
      steps: [
        makeStep('S1', ['src/a.js']),
        makeStep('S2', ['src/b.js'], { owner: 'hivemind:changeling' }),
        makeStep('S3', ['src/c.js', 'src/a.js'], { depends_on: ['S1'] })
      ]
    });
    const waveResults = happyResults({ 'plan-1': planResult(plan), 'work-1-S1': WORKER_DONE, 'work-1-S2': WORKER_DONE, 'work-1-S3': WORKER_DONE, 'commit-1-2': commitRelay({ commit: THIRD }) });
    test('each wave comes from computeWave and its workers run in parallel', async () => {
      const run = await runWorkflow(LAUNCH, waveResults);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'branch-1', 'work-1-S1', 'work-1-S2', 'commit-1-1', 'work-1-S3', 'commit-1-2']);
      assert.deepEqual(run.phases.slice(-4), ['Waves', 'Commit', 'Waves', 'Commit']);
    });
    test('each worker gets its step, wave_scopes, branch, base and trunk as data under the boundary sentence', async () => {
      const run = await runWorkflow(LAUNCH, waveResults);
      const first = callOf(run, 'work-1-S1');
      assert.deepEqual(readDataBlock(first.prompt, 'step'), plan.steps[0]);
      assert.deepEqual(readDataBlock(first.prompt, 'wave_scopes'), ['src/b.js']);
      assert.deepEqual(readDataBlock(first.prompt, 'git'), { branch: 'feature/cache', base: 'main', trunk: 'main' });
      assert.equal(readDataBlock(first.prompt, 'plan_summary'), plan.summary);
      assert.deepEqual(readDataBlock(callOf(run, 'work-1-S3').prompt, 'wave_scopes'), []);
      assert.ok(first.prompt.includes(lib.boundarySentence()));
      assert.ok(first.prompt.includes('Never commit, push, create or switch branches'));
      assert.equal(first.opts.agentType, 'hivemind:drone');
      assert.equal(callOf(run, 'work-1-S2').opts.agentType, 'hivemind:changeling');
      assert.equal(first.opts.phase, 'Waves');
      assert.deepEqual(Object.keys(first.opts.schema.properties), ['outcome', 'summary', 'blocker']);
    });
    test('steps sharing a file run in separate waves', async () => {
      const shared = makePlan({ steps: [makeStep('S1', ['src/a.js']), makeStep('S2', ['src/a.js'])] });
      const results = happyResults({ 'plan-1': planResult(shared), 'work-1-S1': WORKER_DONE, 'work-1-S2': WORKER_DONE, 'commit-1-2': commitRelay({ commit: THIRD }) });
      const run = await runWorkflow(LAUNCH, results);
      assert.deepEqual(labelsOf(run).slice(3), ['work-1-S1', 'commit-1-1', 'work-1-S2', 'commit-1-2']);
    });
    test('a null worker result counts as blocked', async () => {
      const results = { ...waveResults };
      delete results['work-1-S2'];
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.failures, 1);
      assert.equal(run.result.outcome, 'blocked');
      assert.ok(run.result.message.includes('Step "S2" was blocked: it returned no usable result.'), run.result.message);
      assert.deepEqual(labelsOf(run).slice(3), ['work-1-S1', 'work-1-S2', 'commit-1-1']);
    });
  },
  'SD-15': () => {
    test('the commit runner commits the wave files with the mapped type under a commit grant and the git-script sentence', async () => {
      const plan = makePlan({ classification: 'bugfix', breaking: true, steps: [makeStep('S1', ['src/a.js', 'src/b.js']), makeStep('S2', ['src/c.js', 'src/b.js'])] });
      const results = happyResults({ 'plan-1': planResult(plan), 'work-1-S1': WORKER_DONE, 'work-1-S2': WORKER_DONE, 'commit-1-2': commitRelay({ commit: THIRD }) });
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      const call = callOf(run, 'commit-1-1');
      assert.deepEqual(readDataBlock(call.prompt, 'inputs'), { files: ['src/a.js', 'src/b.js'], commit_type: 'fix', breaking: true, trunk: 'main' });
      assert.ok(call.prompt.startsWith('Invoke the hivemind:molt skill once'));
      assert.ok(call.prompt.includes(main.commitGrantSentence()));
      assert.ok(call.prompt.includes(main.gitScriptSentence('hivemind:molt')));
      assert.equal(call.opts.agentType, 'hivemind:drone');
      assert.equal(call.opts.model, 'haiku');
      assert.equal(call.opts.phase, 'Commit');
      assert.deepEqual(readDataBlock(callOf(run, 'commit-1-2').prompt, 'inputs').files, ['src/c.js', 'src/b.js']);
    });
    test('the commit type map covers the plan classifications and names only molt types', () => {
      const moltText = readText(moltPath);
      const typeLine = moltText.match(/^# {3}type {6}REQUIRED\. ([a-z|]+)\.$/m);
      assert.ok(typeLine, 'molt.sh lists its commit types');
      const moltTypes = typeLine[1].split('|');
      const map = main.commitTypeMap();
      assert.deepEqual(Object.keys(map).sort(), [...planSchema.properties.classification.enum].sort());
      Object.values(map).forEach((type) => assert.ok(moltTypes.includes(type), type));
      assert.equal(map.feature, 'feat');
      assert.equal(map.bugfix, 'fix');
    });
    test('the routing spec keys are the OUTPUT keys of molt.sh', () => {
      const moltText = readText(moltPath);
      const output = moltText.slice(moltText.indexOf('# OUTPUT on success'), moltText.indexOf('# EXIT CONTRACT'));
      const keys = [...output.matchAll(/^# {3}([a-z_]+): /gm)].map((match) => match[1]);
      assert.deepEqual(Object.keys(main.moltRoutingSpec()), keys);
    });
    for (const [label, relay] of [
      ['a branch other than the plan branch', commitRelay({ branch: 'main' })],
      ['committed not a boolean', commitRelay({ committed: 'yes' })],
      ['no commit line', commitRelay({ commit: undefined })],
      ['no result', null]
    ]) {
      test(`${label} stops the run after the wave`, async () => {
        const run = await runWorkflow(LAUNCH, happyResults({ 'commit-1-1': relay }));
        assert.equal(run.result.outcome, 'blocked');
        assert.ok(/^The commit step (returned|reported)/.test(run.result.message), run.result.message);
        assert.ok(run.result.message.includes('Check the branch for a commit of the wave.'));
      });
    }
    test('a blocked commit names its blocker and outside lines', async () => {
      const stderr = 'outside: "notes.txt"\noutside: "tmp/x"\nblocker: the working tree has dirty paths outside files\n';
      const run = await runWorkflow(LAUNCH, happyResults({ 'commit-1-1': { outcome: 'blocked', stderr: stderr } }));
      assert.equal(run.result.outcome, 'blocked');
      assert.ok(run.result.message.startsWith([
        'The commit step was blocked, so the delivery stopped: blocker: the working tree has dirty paths outside files',
        'Dirty paths outside the files of the wave:',
        '- "notes.txt"',
        '- "tmp/x"'
      ].join('\n')), run.result.message);
    });
    test('real molt.sh: a worker edit outside its files blocks the commit with an outside line', async () => {
      const scratch = makeScratchRepo();
      const run = await runWorkflow(LAUNCH, realResults(scratch, { 'work-1-STEP-001': realWorker(scratch, 'stray.txt') }));
      assert.equal(run.result.outcome, 'blocked');
      assert.ok(run.result.message.startsWith('The commit step was blocked, so the delivery stopped: blocker: the working tree has dirty paths outside files\nDirty paths outside the files of the wave:\n- "stray.txt"'), run.result.message);
    });
    test('real molt.sh: a wave with nothing to commit reports committed false', async () => {
      const scratch = makeScratchRepo();
      const run = await runWorkflow(LAUNCH, realResults(scratch, { 'work-1-STEP-001': WORKER_DONE }));
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.ok(run.result.message.includes('This run made no commit.'), run.result.message);
    });
  },
  'SD-16': () => {
    test('a blocked worker stops the run after the wave commit, naming the commit', async () => {
      const results = happyResults({ 'work-1-STEP-001': { outcome: 'blocked', summary: 'Stopped.', blocker: 'Tests fail.' } });
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.outcome, 'blocked');
      assert.deepEqual(labelsOf(run).slice(-2), ['work-1-STEP-001', 'commit-1-1']);
      assert.ok(run.result.message.startsWith([
        'A worker did not finish its step, so the delivery stopped after the commit of its wave.',
        'Step "STEP-001" was blocked: Tests fail.',
        'The wave was committed as ' + OTHER + ', so that commit can hold partial edits of the steps above.'
      ].join('\n')), run.result.message);
    });
    test('a blocked wave with nothing to commit names the branch head', async () => {
      const results = happyResults({ 'work-1-STEP-001': { outcome: 'blocked', summary: 'Stopped.', blocker: 'Tests fail.' }, 'commit-1-1': commitRelay({ committed: 'false', commit: HEAD }) });
      const run = await runWorkflow(LAUNCH, results);
      assert.ok(run.result.message.includes('The wave left nothing to commit, so the branch head stays ' + HEAD + '.'), run.result.message);
    });
    test('a blocked wave stops later waves', async () => {
      const plan = makePlan({ steps: [makeStep('S1', ['a.js']), makeStep('S2', ['b.js'], { depends_on: ['S1'] })] });
      const results = happyResults({ 'plan-1': planResult(plan), 'work-1-S1': { outcome: 'blocked', summary: 'Stopped.' }, 'work-1-S2': WORKER_DONE });
      const run = await runWorkflow(LAUNCH, results);
      assert.ok(!labelsOf(run).includes('work-1-S2'));
      assert.ok(run.result.message.includes('Step "S1" was blocked: it gave no reason.'));
    });
  },
  'SD-17': () => {
    function replanResults(passes) {
      const results = happyResults({ 'work-1-STEP-001': { outcome: 'needs_replan', summary: 'Stopped.', blocker: 'The API moved.' } });
      for (let pass = 2; pass <= passes; pass += 1) {
        Object.assign(results, {
          ['facts-' + pass]: onPlanBranchFacts(OTHER),
          ['plan-' + pass]: planResult(makePlan({ steps: [makeStep('STEP-001', ['src/cache.js']), makeStep('STEP-002', ['src/api.js'])] })),
          ['branch-' + pass]: branchRelay({ created: 'false', commit: OTHER }),
          ['work-' + pass + '-STEP-001']: { outcome: 'needs_replan', summary: 'Stopped.', blocker: 'The API moved again.' },
          ['work-' + pass + '-STEP-002']: WORKER_DONE,
          ['commit-' + pass + '-1']: commitRelay({ commit: OTHER, committed: 'false' })
        });
      }
      return results;
    }
    test('a needs_replan wave is committed, then facts and a new plan of what is left with done ids reset', async () => {
      const results = replanResults(2);
      results['work-2-STEP-001'] = WORKER_DONE;
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.outcome, 'complete', run.result.message);
      assert.deepEqual(labelsOf(run), ['facts-1', 'plan-1', 'branch-1', 'work-1-STEP-001', 'commit-1-1', 'facts-2', 'plan-2', 'branch-2', 'work-2-STEP-001', 'work-2-STEP-002', 'commit-2-1']);
      assert.ok(run.result.message.includes('Commits this run made:\n- ' + OTHER));
    });
    test('after maxReplans() replans the run stops naming the reason', async () => {
      assert.equal(main.maxReplans(), 3);
      const run = await runWorkflow(LAUNCH, replanResults(4));
      assert.equal(run.result.outcome, 'blocked');
      assert.ok(run.result.message.startsWith('A worker asked for a new plan after 3 replans, so the delivery stopped.\nStep "STEP-001" needs a new plan: The API moved again.'), run.result.message);
      assert.deepEqual(labelsOf(run).slice(-3), ['work-4-STEP-001', 'work-4-STEP-002', 'commit-4-1']);
    });
    test('a blocked worker wins over needs_replan in the same wave', async () => {
      const plan = makePlan({ steps: [makeStep('S1', ['a.js']), makeStep('S2', ['b.js'])] });
      const results = happyResults({ 'plan-1': planResult(plan), 'work-1-S1': { outcome: 'needs_replan', summary: 'x', blocker: 'y' }, 'work-1-S2': { outcome: 'blocked', summary: 'x', blocker: 'z' } });
      const run = await runWorkflow(LAUNCH, results);
      assert.equal(run.result.outcome, 'blocked');
      assert.ok(!labelsOf(run).includes('facts-2'));
    });
  },
  'SD-18': () => {
    const results = happyResults({ 'facts-1': factsRelay({ external_texts: '1' }), scan: { results: [{ item_ref: 't1', verdict: 'clean' }] } });
    test('runner prompts carry no request text', async () => {
      const run = await runWorkflow(LAUNCH, results);
      for (const label of ['facts-1', 'scan', 'branch-1', 'commit-1-1']) {
        assert.ok(!callOf(run, label).prompt.includes('REQUEST_MARKER_ZQ'), label);
      }
      assert.ok(callOf(run, 'plan-1').prompt.includes('REQUEST_MARKER_ZQ'));
    });
    test('read-only runners carry the runner read-only sentence and git-script runners the git-script sentence', async () => {
      const run = await runWorkflow(LAUNCH, results);
      assert.ok(callOf(run, 'facts-1').prompt.includes(lib.runnerReadOnlySentence()));
      assert.ok(callOf(run, 'scan').prompt.includes(lib.runnerReadOnlySentence()));
      for (const [label, skill] of [['branch-1', 'hivemind:create-working-branch'], ['commit-1-1', 'hivemind:molt']]) {
        const prompt = callOf(run, label).prompt;
        assert.ok(prompt.includes(main.gitScriptSentence(skill)), label);
        assert.ok(!prompt.includes(lib.runnerReadOnlySentence()), label);
      }
      assert.ok(!callOf(run, 'branch-1').prompt.includes('commit authority'));
    });
    test('the git-script sentence matches the git-script task clause of drone.md', () => {
      const clause = readDroneClause('A git-script task is also exempt: when the delegation says ', 'take the place of this check.');
      const condition = clause.match(/when the delegation says (.+?), the task runs on (.+?), and that script's refusals take the place of this check\.$/);
      assert.ok(condition, clause);
      for (const skill of ['hivemind:create-working-branch', 'hivemind:molt']) {
        const sentence = main.gitScriptSentence(skill);
        assert.ok(sentence.includes(condition[1].replace('a named hivemind git skill whose script', skill + ', a hivemind git skill whose script')), sentence);
        assert.ok(sentence.includes('the task runs on ' + condition[2]), sentence);
        assert.ok(sentence.includes('that script\'s refusals take the place of'), sentence);
      }
      assert.ok(droneText.includes('Commit authority is unchanged: a commit still needs the delegation\'s explicit grant.'));
      assert.ok(main.commitGrantSentence().startsWith('This delegation explicitly grants commit authority'));
    });
    test('the runner read-only sentence matches the read-only task clause of drone.md', () => {
      const clause = readDroneClause('except for a read-only task: when the delegation says ', 'needs no branch or base.');
      const sentence = lib.runnerReadOnlySentence();
      for (const phrase of ['edits no tracked files and makes no git writes', 'trunk included', 'no branch or base']) {
        assert.ok(clause.includes(phrase), phrase);
        assert.ok(sentence.includes(phrase), phrase);
      }
    });
    test('no prompt and no source line uses git with -C', async () => {
      const run = await runWorkflow(LAUNCH, results);
      assert.ok(run.calls.every((call) => !call.prompt.includes('git -C')));
      assert.ok(!mainSource.includes('git -C'));
    });
  },
  'SD-19': () => {
    test('the final message lists the commits, the reversible effects and every taken decision', async () => {
      const plan = effectPlan('Post a preview link.', true);
      const strong = makeBrief({ problem: 'STRONG_PROBLEM' });
      const run = await runWorkflow(LAUNCH, happyResults({ 'plan-1': planResult(plan, [strong]) }));
      const taken = [{ brief: strong }, { brief: main.buildPlanAcceptanceBrief(plan) }];
      assert.deepEqual(run.result, {
        needs_user: false,
        outcome: 'complete',
        message: [
          'Every plan step is done on branch "feature/cache", and each wave is committed.',
          'Commits this run made:\n- ' + OTHER,
          'Effects outside the repo that the plan declares as reversible:\n- step "STEP-001": "Post a preview link."',
          lib.renderDecisions(taken)
        ].join('\n\n')
      });
    });
    test('a pause after waves lists the commits so far, and a resume replays every earlier prompt byte for byte', async () => {
      const results = happyResults({
        'work-1-STEP-001': { outcome: 'needs_replan', summary: 'Stopped.', blocker: 'The API moved.' },
        'facts-2': onPlanBranchFacts(OTHER),
        'plan-2': planResult(effectPlan('Run the data migration.', false)),
        'revise-1': reviseResult(planResult(effectPlan('Run the data migration.', false)), ['Q1']),
        'branch-2': branchRelay({ created: 'false', commit: OTHER }),
        'work-2-STEP-001': WORKER_DONE,
        'commit-2-1': commitRelay({ commit: THIRD })
      });
      const paused = await runWorkflow(LAUNCH, results);
      assert.equal(paused.result.needs_user, true);
      assert.deepEqual(paused.result.resume_args, { answers: {} });
      assert.ok(paused.result.message.endsWith('Commits this run made:\n- ' + OTHER), paused.result.message);
      const resumed = await runWorkflow(resumeWith(LAUNCH, paused.result, 'Yes, run it.'), results);
      assert.equal(resumed.result.outcome, 'complete', resumed.result.message);
      paused.calls.forEach((call, index) => {
        assert.equal(resumed.calls[index].opts.label, call.opts.label);
        assert.equal(resumed.calls[index].prompt, call.prompt, call.opts.label);
      });
      assert.ok(resumed.result.message.includes('Commits this run made:\n- ' + OTHER + '\n- ' + THIRD), resumed.result.message);
    });
    test('every agent label of a run is unique', async () => {
      const run = await runWorkflow(LAUNCH, happyResults({ 'branch-1': branchRelay({ created: 'false' }), 'facts-2': onPlanBranchFacts(HEAD), 'plan-2': planResult(), 'branch-2': branchRelay({ created: 'false' }), 'work-2-STEP-001': WORKER_DONE, 'commit-2-1': commitRelay() }));
      const labels = labelsOf(run);
      assert.equal(new Set(labels).size, labels.length, JSON.stringify(labels));
    });
  }
};

describe('standard-delivery contract table', () => {
  test('the row ids in main.js equal the tested row ids', () => {
    assert.deepEqual(readContractIds(mainSource), Object.keys(ROW_TESTS));
  });
  test('each row has a step, a rule sentence and a check that is a function of the built script', () => {
    const rows = structuredClone(main.contractRows());
    assert.deepEqual(rows.map((row) => row.id), Object.keys(ROW_TESTS));
    for (const row of rows) {
      assert.deepEqual(Object.keys(row).sort(), ['check', 'id', 'rule', 'step'], row.id);
      assert.ok(row.step.trim() !== '' && row.rule.endsWith('.'), row.id);
      assert.ok(new RegExp('^(?:async )?function ' + row.check + '\\(', 'm').test(builtSource), row.id + ' ' + row.check);
    }
  });
});

for (const [rowId, defineTests] of Object.entries(ROW_TESTS)) {
  describe(rowId, defineTests);
}

describe('standard-delivery draft', () => {
  test('DRAFT is a regular file, so no built script is written', () => {
    assert.ok(lstatSync(join(sourceDir, 'DRAFT')).isFile());
    assert.equal(isDraftWorkflow(repoRoot, WORKFLOW_ID), true);
    assert.equal(existsSync(join(repoRoot, builtPathFor(WORKFLOW_ID))), false);
  });
  test('meta names the workflow and its phases', async () => {
    const run = await workflow.run({ args: undefined, results: {} });
    assert.equal(run.meta.name, WORKFLOW_ID);
    assert.deepEqual(structuredClone(run.meta.phases).map((phase) => phase.title), ['Facts', 'Scan', 'Plan', 'Revise', 'Branch', 'Waves', 'Commit']);
  });
  test('main.js and meta.js are ASCII with no em dash, no hash before a digit and no clock or randomness', () => {
    for (const source of [mainSource, metaSource]) {
      assert.ok(/^[\x09\x0a\x20-\x7e]*$/.test(source));
      assert.ok(!/#[0-9]/.test(source));
      assert.ok(!/\bDate\s*\(|\bDate\.now|Math\.random/.test(source));
    }
  });
  test('every phase the script enters is a meta phase', async () => {
    const run = await runWorkflow(LAUNCH, happyResults({ 'facts-1': factsRelay({ external_texts: '1' }), scan: { results: [{ item_ref: 't1', verdict: 'clean' }] } }));
    const titles = ['Facts', 'Scan', 'Plan', 'Revise', 'Branch', 'Waves', 'Commit'];
    assert.ok(run.phases.every((title) => titles.includes(title)), JSON.stringify(run.phases));
  });
});
