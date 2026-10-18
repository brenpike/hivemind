import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, cpSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadWorkflow } from './harness.mjs';
import { buildWorkflow, builtPathFor, discoverWorkflowIds, runCli, stripCommentsAndStrings } from '../../tools/build_workflows.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const builderPath = join(repoRoot, 'tools/build_workflows.mjs');
const REBUILD_COMMAND = 'node tools/build_workflows.mjs';
const workflowIds = discoverWorkflowIds(repoRoot);
const scratchRoots = [];

function readBuilt(id) {
  return readFileSync(join(repoRoot, builtPathFor(id)), 'utf8').replace(/\r/g, '');
}

function makeScratchCopy() {
  const scratchRoot = mkdtempSync(join(tmpdir(), 'build-workflows-'));
  scratchRoots.push(scratchRoot);
  for (const dir of ['plugin/workflow-src', 'plugin/references', 'plugin/workflows']) {
    cpSync(join(repoRoot, dir), join(scratchRoot, dir), { recursive: true });
  }
  return scratchRoot;
}

function createStream() {
  const chunks = [];
  return { write: (chunk) => chunks.push(chunk), text: () => chunks.join('') };
}

function runCliIn(root, argv) {
  const stdout = createStream();
  const stderr = createStream();
  const code = runCli(argv, { root, stdout, stderr });
  return { code, stdout: stdout.text(), stderr: stderr.text() };
}

after(() => {
  scratchRoots.forEach((scratchRoot) => rmSync(scratchRoot, { recursive: true, force: true }));
});

describe('build_workflows --check', () => {
  test('passes on the repository', () => {
    const run = spawnSync(process.execPath, [builderPath, '--check'], { cwd: repoRoot, encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stderr, '');
  });
  test('reports a mutated source as stale, naming the file and the rebuild command', () => {
    const scratchRoot = makeScratchCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js'), '\nlog(\'changed\');\n');
    const run = runCliIn(scratchRoot, ['--check']);
    assert.equal(run.code, 1);
    assert.ok(run.stderr.includes('plugin/workflows/analysis-only.js is stale'), run.stderr);
    assert.ok(run.stderr.includes(REBUILD_COMMAND), run.stderr);
  });
  test('reports mutated data as stale', () => {
    const scratchRoot = makeScratchCopy();
    const tablePath = join(scratchRoot, 'plugin/references/decision-autonomy-table.json');
    const table = JSON.parse(readFileSync(tablePath, 'utf8'));
    table.default_level = 'low';
    writeFileSync(tablePath, JSON.stringify(table));
    assert.equal(runCliIn(scratchRoot, ['--check']).code, 1);
  });
  test('reports a missing built file as stale', () => {
    const scratchRoot = makeScratchCopy();
    rmSync(join(scratchRoot, 'plugin/workflows/analysis-only.js'));
    assert.equal(runCliIn(scratchRoot, ['--check']).code, 1);
  });
  test('ignores CR in sources and in the committed file', () => {
    const scratchRoot = makeScratchCopy();
    for (const relativePath of ['plugin/workflow-src/analysis-only/main.js', 'plugin/workflows/analysis-only.js']) {
      const fullPath = join(scratchRoot, relativePath);
      writeFileSync(fullPath, readFileSync(fullPath, 'utf8').replace(/\r/g, '').replace(/\n/g, '\r\n'));
    }
    assert.equal(runCliIn(scratchRoot, ['--check']).code, 0);
  });
  test('a rebuild clears a stale report and writes LF only', () => {
    const scratchRoot = makeScratchCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js'), '\r\nlog(\'changed\');\r\n');
    const build = runCliIn(scratchRoot, []);
    assert.equal(build.code, 0);
    assert.ok(build.stdout.includes('plugin/workflows/analysis-only.js'));
    assert.ok(!readFileSync(join(scratchRoot, 'plugin/workflows/analysis-only.js'), 'utf8').includes('\r'));
    assert.equal(runCliIn(scratchRoot, ['--check']).code, 0);
  });
  test('rejects an unknown argument', () => {
    assert.equal(runCliIn(repoRoot, ['--chek']).code, 2);
  });
});

describe('build_workflows guards', () => {
  test('workflow ids are the source directories other than lib', () => {
    const dirs = readdirSync(join(repoRoot, 'plugin/workflow-src'), { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && entry.name !== 'lib')
      .map((entry) => entry.name)
      .sort();
    assert.deepEqual(workflowIds, dirs);
    assert.ok(workflowIds.includes('analysis-only'));
  });
  test('a new source directory is built without a hand list', () => {
    const scratchRoot = makeScratchCopy();
    cpSync(join(scratchRoot, 'plugin/workflow-src/analysis-only'), join(scratchRoot, 'plugin/workflow-src/copy-check'), { recursive: true });
    assert.deepEqual(discoverWorkflowIds(scratchRoot), [...workflowIds, 'copy-check'].sort());
    const run = runCliIn(scratchRoot, ['--check']);
    assert.equal(run.code, 1);
    assert.ok(run.stderr.includes('plugin/workflows/copy-check.js is stale'));
  });
  test('an import in code fails the build', () => {
    const scratchRoot = makeScratchCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js'), '\nimport x from \'y\';\n');
    assert.throws(() => buildWorkflow(scratchRoot, 'analysis-only'), /import or require/);
  });
  test('a require( call in code fails the build', () => {
    const scratchRoot = makeScratchCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js'), '\nconst fs = require(\'fs\');\n');
    assert.throws(() => buildWorkflow(scratchRoot, 'analysis-only'), /import or require/);
  });
  test('import and require( inside strings or comments do not fail the build', () => {
    const scratchRoot = makeScratchCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js'), '\n// import x\nlog(\'import y require(z)\');\n');
    assert.doesNotThrow(() => buildWorkflow(scratchRoot, 'analysis-only'));
  });
  test('a top-level function declared twice fails the build', () => {
    const scratchRoot = makeScratchCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js'), '\nfunction decide() {\n  return null;\n}\n');
    assert.throws(() => buildWorkflow(scratchRoot, 'analysis-only'), /declared more than once: decide/);
  });
  test('stripCommentsAndStrings keeps code and drops comments and literals', () => {
    assert.equal(stripCommentsAndStrings('a /* x */ b // y\nc \'d\' "e" `f`'), 'a  b \nc "" "" ""');
  });
});

for (const id of workflowIds) {
  describe('built ' + builtPathFor(id), () => {
    const source = readBuilt(id);
    test('matches a fresh build', () => {
      assert.equal(source, buildWorkflow(repoRoot, id));
    });
    test('meta is the first statement', () => {
      assert.ok(source.startsWith('export const meta = {'));
      assert.doesNotThrow(() => loadWorkflow(join(repoRoot, builtPathFor(id))));
    });
    test('the GENERATED banner follows meta and names its sources', () => {
      const metaEnd = source.indexOf('\n};\n\n');
      const bannerStart = source.indexOf('/*\n * GENERATED by tools/build_workflows.mjs');
      assert.ok(metaEnd !== -1 && bannerStart === metaEnd + 5, 'banner must follow meta');
      const banner = source.slice(bannerStart, source.indexOf('*/', bannerStart));
      for (const name of ['workflow-src/' + id + '/meta.js', 'workflow-src/' + id + '/main.js', 'workflow-src/lib/decide.js', 'decision-autonomy-table.json']) {
        assert.ok(banner.includes(name), name);
      }
      assert.ok(banner.includes('Do not edit by hand'));
      assert.ok(banner.includes(REBUILD_COMMAND));
    });
    test('data constants and libraries come in build order', () => {
      const markers = ['const AUTONOMY_TABLE = ', 'const BRIEF_SCHEMA = ', 'function decisionReasons(', 'function renderQuestions(', 'function resultFields('];
      const positions = markers.map((marker) => source.indexOf(marker));
      assert.ok(positions.every((position) => position !== -1), JSON.stringify(positions));
      assert.deepEqual([...positions].sort((left, right) => left - right), positions);
    });
    test('has no import or require', () => {
      assert.ok(!/\bimport\b/.test(source));
      assert.ok(!/\brequire\s*\(/.test(source));
    });
    test('has no em dash', () => {
      assert.ok(!source.includes('\u2014'));
    });
    test('has no # followed by a digit', () => {
      assert.ok(!/#\d/.test(source));
    });
    test('has no CR', () => {
      assert.ok(!readFileSync(join(repoRoot, builtPathFor(id)), 'utf8').replace(/\r\n/g, '\n').includes('\r'));
    });
    test('meta.name equals the file stem and the JSON workflow id', async () => {
      const run = await loadWorkflow(join(repoRoot, builtPathFor(id))).run({ args: undefined, results: {} });
      const definition = JSON.parse(readFileSync(join(repoRoot, 'plugin/workflows/' + id + '.json'), 'utf8'));
      assert.equal(run.meta.name, id);
      assert.equal(definition.id, id);
    });
  });
}
