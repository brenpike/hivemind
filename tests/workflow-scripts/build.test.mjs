import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadWorkflow, loadWorkflowSource } from './harness.mjs';
import {
  LIB_FILES,
  MAX_BUILT_SCRIPT_LENGTH,
  WORKFLOW_APPROVAL_LIMIT,
  buildWorkflow,
  builtPathFor,
  discoverWorkflowIds,
  findNonRegularOutputs,
  findOrphanWorkflowIds,
  isDraftWorkflow,
  listDraftWorkflowIds,
  listLiveWorkflowIds,
  runCli,
  stripComments,
  stripCommentsAndStrings,
  tokenizeSource
} from '../../tools/build_workflows.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const builderPath = join(repoRoot, 'tools/build_workflows.mjs');
const REBUILD_COMMAND = 'node tools/build_workflows.mjs';
const workflowIds = discoverWorkflowIds(repoRoot);
const liveIds = listLiveWorkflowIds(repoRoot);
const draftIds = listDraftWorkflowIds(repoRoot);
const DRAFT_ID = 'draft-check';
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

/**
 * Adds plugin/workflow-src/draft-check/ to a scratch copy: a copy of
 * analysis-only renamed to draft-check, with a DRAFT marker.
 */
function addScratchDraft(scratchRoot) {
  const draftDir = join(scratchRoot, 'plugin/workflow-src', DRAFT_ID);
  cpSync(join(scratchRoot, 'plugin/workflow-src/analysis-only'), draftDir, { recursive: true });
  const metaPath = join(draftDir, 'meta.js');
  writeFileSync(metaPath, readFileSync(metaPath, 'utf8').replace('name: \'analysis-only\'', 'name: \'' + DRAFT_ID + '\''));
  writeFileSync(join(draftDir, 'DRAFT'), 'contents are not read\n');
  return draftDir;
}

function makeScratchDraftCopy() {
  const scratchRoot = makeScratchCopy();
  addScratchDraft(scratchRoot);
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
  test('reports a .js with no source directory as an orphan, naming it', () => {
    const scratchRoot = makeScratchCopy();
    writeFileSync(join(scratchRoot, 'plugin/workflows/orphan-check.js'), readBuilt('analysis-only'));
    writeFileSync(join(scratchRoot, 'plugin/workflows/lib.js'), readBuilt('analysis-only'));
    const run = runCliIn(scratchRoot, ['--check']);
    assert.equal(run.code, 1);
    assert.ok(run.stderr.includes('plugin/workflows/orphan-check.js is an orphan'), run.stderr);
    assert.ok(run.stderr.includes('plugin/workflow-src/orphan-check/'), run.stderr);
    assert.ok(run.stderr.includes('plugin/workflows/lib.js is an orphan'), run.stderr);
    assert.ok(!run.stderr.includes('stale'), run.stderr);
    assert.ok(!run.stderr.includes('.json'), run.stderr);
  });
  test('a .json engine file with no source directory is not an orphan', () => {
    const scratchRoot = makeScratchCopy();
    writeFileSync(join(scratchRoot, 'plugin/workflows/orphan-check.json'), '{}');
    assert.deepEqual(findOrphanWorkflowIds(scratchRoot), []);
    assert.equal(runCliIn(scratchRoot, ['--check']).code, 0);
  });
  test('rejects an unknown argument', () => {
    assert.equal(runCliIn(repoRoot, ['--chek']).code, 2);
  });
});

describe('build_workflows regular files only', () => {
  test('--check names a symlinked .js and does not read through it', () => {
    const scratchRoot = makeScratchCopy();
    const builtPath = join(scratchRoot, 'plugin/workflows/analysis-only.js');
    const outsidePath = join(scratchRoot, 'outside-analysis-only.js');
    writeFileSync(outsidePath, readFileSync(builtPath, 'utf8'));
    rmSync(builtPath);
    symlinkSync(outsidePath, builtPath);
    symlinkSync(outsidePath, join(scratchRoot, 'plugin/workflows/link-check.js'));
    const run = runCliIn(scratchRoot, ['--check']);
    assert.equal(run.code, 1);
    assert.ok(run.stderr.includes('plugin/workflows/analysis-only.js is a symlink'), run.stderr);
    assert.ok(run.stderr.includes('plugin/workflows/link-check.js is a symlink'), run.stderr);
    assert.ok(!run.stderr.includes('stale'), run.stderr);
    assert.deepEqual(findNonRegularOutputs(scratchRoot), [
      { path: 'plugin/workflows/analysis-only.js', kind: 'symlink' },
      { path: 'plugin/workflows/link-check.js', kind: 'symlink' }
    ]);
  });
  test('--check names a directory named x.js', () => {
    const scratchRoot = makeScratchCopy();
    mkdirSync(join(scratchRoot, 'plugin/workflows/x.js'));
    const run = runCliIn(scratchRoot, ['--check']);
    assert.equal(run.code, 1);
    assert.ok(run.stderr.includes('plugin/workflows/x.js is a directory'), run.stderr);
    assert.ok(run.stderr.includes('must be a regular file'), run.stderr);
  });
  test('--check names a symlinked .json, whatever its name', () => {
    const scratchRoot = makeScratchCopy();
    symlinkSync(join(scratchRoot, 'plugin/workflows/analysis-only.json'), join(scratchRoot, 'plugin/workflows/link-check.json'));
    symlinkSync(join(scratchRoot, 'plugin/workflows/analysis-only.json'), join(scratchRoot, 'plugin/workflows/no-extension'));
    const run = runCliIn(scratchRoot, ['--check']);
    assert.equal(run.code, 1);
    assert.ok(run.stderr.includes('plugin/workflows/link-check.json is a symlink'), run.stderr);
    assert.ok(run.stderr.includes('plugin/workflows/no-extension is a symlink'), run.stderr);
  });
  test('--check names an entry that is neither a file, a directory nor a symlink', (t) => {
    const scratchRoot = makeScratchCopy();
    const fifo = spawnSync('mkfifo', [join(scratchRoot, 'plugin/workflows/pipe-check.js')], { encoding: 'utf8' });
    if (fifo.status !== 0) {
      t.skip('mkfifo is not available');
      return;
    }
    const run = runCliIn(scratchRoot, ['--check']);
    assert.equal(run.code, 1);
    assert.ok(run.stderr.includes('plugin/workflows/pipe-check.js is not a file, a directory or a symlink'), run.stderr);
  });
  test('write mode refuses a symlinked target before writing anything', () => {
    const scratchRoot = makeScratchCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js'), '\nlog(\'changed\');\n');
    const builtPath = join(scratchRoot, 'plugin/workflows/analysis-only.js');
    const outsidePath = join(scratchRoot, 'outside-target.js');
    writeFileSync(outsidePath, 'outside\n');
    rmSync(builtPath);
    symlinkSync(outsidePath, builtPath);
    assert.throws(() => runCliIn(scratchRoot, []), /plugin\/workflows\/analysis-only\.js is a symlink/);
    assert.equal(readFileSync(outsidePath, 'utf8'), 'outside\n');
  });
  test('write mode refuses a directory target', () => {
    const scratchRoot = makeScratchCopy();
    const builtPath = join(scratchRoot, 'plugin/workflows/analysis-only.js');
    rmSync(builtPath);
    mkdirSync(builtPath);
    assert.throws(() => runCliIn(scratchRoot, []), /plugin\/workflows\/analysis-only\.js is a directory/);
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
  test('stripCommentsAndStrings hides a regex literal and keeps template substitution code', () => {
    assert.equal(stripCommentsAndStrings('x = /import/; y = `a${require(z)}b`'), 'x = ""; y = ""require(z)""');
  });
  test('a syntax error in the built script fails the build', () => {
    const scratchRoot = makeScratchCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js'), '\nconst = 1;\n');
    assert.throws(() => buildWorkflow(scratchRoot, 'analysis-only'), /analysis-only: the built script does not parse/);
  });
  test('an unterminated literal in a source fails the build, naming the file', () => {
    const scratchRoot = makeScratchCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js'), '\nlog(`open);\n');
    assert.throws(() => buildWorkflow(scratchRoot, 'analysis-only'), /plugin\/workflow-src\/analysis-only\/main\.js: unterminated template literal/);
  });
  test('LIB_FILES is every .js in plugin/workflow-src/lib/', () => {
    const libFiles = readdirSync(join(repoRoot, 'plugin/workflow-src/lib'), { withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith('.js'))
      .map((entry) => entry.name)
      .sort();
    assert.deepEqual([...LIB_FILES].sort(), libFiles);
  });
  test('live ids and draft ids split the workflow ids', () => {
    assert.deepEqual([...liveIds, ...draftIds].sort(), workflowIds);
    assert.ok(liveIds.every((id) => !draftIds.includes(id)));
    assert.ok(liveIds.includes('analysis-only'));
  });
});

describe('build_workflows stripComments', () => {
  const unchanged = [
    ['line and block markers inside single quotes', 'x = \'a // b /* c */\';'],
    ['line and block markers inside double quotes', 'x = "a // b /* c */";'],
    ['line and block markers inside a template', 'x = `a // b /* c */`;'],
    ['a block marker string inside a substitution', 'x = `${ \'/*\' }`;'],
    ['a template nested in a substitution', 'x = `a${ `b${ c }/*` }// d`;'],
    ['a regex of escaped slashes', 'x = /\\/\\//;'],
    ['a slash and a star inside a regex class', 'x = /[/*]/g;'],
    ['a quote inside a regex', 'x = /\'/;'],
    ['a regex after return', 'function f() {\n  return /a\\/b/.test(s);\n}'],
    ['chained division', 'x = a / b / c;'],
    ['division after ) and ]', 'x = (a) / b[0] / 2;'],
    ['line starts and blank lines in code', 'function a() {\n  return 1;\n}\n\nasync function b() {}\n']
  ];
  for (const [name, source] of unchanged) {
    test('keeps ' + name + ' unchanged', () => {
      assert.equal(stripComments(source), source);
    });
  }
  const stripped = [
    ['a line comment after division', 'x = a / b // c', 'x = a / b'],
    ['a block comment inside a substitution', 'x = `${ /* c */ 1 }`;', 'x = `${ 1 }`;'],
    ['a block comment holding a newline, keeping one newline', 'return /*\n*/ x', 'return\n x'],
    ['a block comment between tokens, keeping them apart', 'a/* c */b', 'a b'],
    ['a block comment before code, keeping its indent', '  /* c */ x();', '  x();'],
    ['a comment-only line', 'function a() {\n  // c\n  return 1;\n}', 'function a() {\n  return 1;\n}'],
    ['a doc comment above a function', 'x();\n\n/**\n * d\n */\nfunction a() {}\n', 'x();\n\nfunction a() {}\n'],
    ['a comment after a regex', 'x = /a/g; // c\ny();', 'x = /a/g;\ny();']
  ];
  for (const [name, source, expected] of stripped) {
    test('strips ' + name, () => {
      assert.equal(stripComments(source), expected);
    });
  }
  const unterminated = [
    ['template', 'x = `abc', /unterminated template literal at line 1/],
    ['template substitution', 'x = `${ a', /unterminated template literal substitution/],
    ['string', 'x = \'abc\ny = 1;', /unterminated string literal at line 1/],
    ['block comment', 'x = 1;\n/* c', /unterminated block comment at line 2/],
    ['regex', 'x = /abc\n', /unterminated regex literal at line 1/]
  ];
  for (const [name, source, pattern] of unterminated) {
    test('throws on an unterminated ' + name, () => {
      assert.throws(() => stripComments(source), pattern);
    });
  }
  test('keeps every literal of every source byte for byte', () => {
    const sourcePaths = [...workflowIds.flatMap((id) => [id + '/meta.js', id + '/main.js']), ...LIB_FILES.map((file) => 'lib/' + file)];
    const listLiterals = (source) => tokenizeSource(source).filter((token) => token.kind !== 'code' && token.kind !== 'comment').map((token) => token.text);
    for (const sourcePath of sourcePaths) {
      const source = readFileSync(join(repoRoot, 'plugin/workflow-src', sourcePath), 'utf8').replace(/\r/g, '');
      const output = stripComments(source);
      assert.deepEqual(listLiterals(output), listLiterals(source), sourcePath);
      assert.ok(tokenizeSource(output).every((token) => token.kind !== 'comment'), sourcePath);
    }
  });
});

describe('build_workflows length budget', () => {
  test('the limits are pinned', () => {
    assert.equal(WORKFLOW_APPROVAL_LIMIT, 200000);
    assert.equal(MAX_BUILT_SCRIPT_LENGTH, 190000);
  });
  test('a script over the budget fails the build and --check, naming the id and the length', () => {
    const scratchRoot = makeScratchCopy();
    const mainPath = join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js');
    const mainBefore = readFileSync(mainPath, 'utf8').replace(/\r/g, '');
    const mainAfter = mainBefore + '\nlog(\'' + 'x'.repeat(MAX_BUILT_SCRIPT_LENGTH) + '\');\n';
    writeFileSync(mainPath, mainAfter);
    const length = readBuilt('analysis-only').length + stripComments(mainAfter).trim().length - stripComments(mainBefore).trim().length;
    const pattern = new RegExp('analysis-only: the built script is ' + length + ' characters, over the budget of 190000');
    assert.throws(() => buildWorkflow(scratchRoot, 'analysis-only'), pattern);
    assert.throws(() => runCliIn(scratchRoot, ['--check']), pattern);
  });
  for (const id of liveIds) {
    test(builtPathFor(id) + ' is within the budget', () => {
      assert.ok(readFileSync(join(repoRoot, builtPathFor(id)), 'utf8').length <= MAX_BUILT_SCRIPT_LENGTH);
    });
  }
});

describe('build_workflows drafts', () => {
  test('a DRAFT regular file marks a draft and its contents are not read', () => {
    const scratchRoot = makeScratchDraftCopy();
    writeFileSync(join(scratchRoot, 'plugin/workflow-src', DRAFT_ID, 'DRAFT'), '');
    assert.equal(isDraftWorkflow(scratchRoot, DRAFT_ID), true);
    assert.equal(isDraftWorkflow(scratchRoot, 'analysis-only'), false);
    assert.deepEqual(listDraftWorkflowIds(scratchRoot), [...draftIds, DRAFT_ID].sort());
    assert.deepEqual(listLiveWorkflowIds(scratchRoot), liveIds);
  });
  test('write skips the draft and prints a skipped line', () => {
    const scratchRoot = makeScratchDraftCopy();
    const build = runCliIn(scratchRoot, []);
    assert.equal(build.code, 0);
    assert.ok(build.stdout.includes('wrote plugin/workflows/analysis-only.js'), build.stdout);
    assert.ok(build.stdout.includes('skipped plugin/workflows/' + DRAFT_ID + '.js'), build.stdout);
    assert.ok(build.stdout.includes('plugin/workflow-src/' + DRAFT_ID + '/DRAFT'), build.stdout);
    assert.ok(!build.stdout.includes('wrote plugin/workflows/' + DRAFT_ID + '.js'), build.stdout);
    assert.equal(existsSync(join(scratchRoot, builtPathFor(DRAFT_ID))), false);
  });
  test('--check passes on a draft with no built file', () => {
    const run = runCliIn(makeScratchDraftCopy(), ['--check']);
    assert.equal(run.code, 0, run.stderr);
    assert.equal(run.stderr, '');
  });
  test('--check fails when a draft has a built file, naming the file and the marker', () => {
    const scratchRoot = makeScratchDraftCopy();
    writeFileSync(join(scratchRoot, builtPathFor(DRAFT_ID)), buildWorkflow(scratchRoot, DRAFT_ID));
    const run = runCliIn(scratchRoot, ['--check']);
    assert.equal(run.code, 1);
    assert.ok(run.stderr.includes('plugin/workflows/' + DRAFT_ID + '.js exists but plugin/workflow-src/' + DRAFT_ID + '/DRAFT'), run.stderr);
    assert.ok(!run.stderr.includes('orphan'), run.stderr);
  });
  test('--check fails on a stray DRAFT marker on a live workflow', () => {
    const scratchRoot = makeScratchCopy();
    writeFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/DRAFT'), '');
    const run = runCliIn(scratchRoot, ['--check']);
    assert.equal(run.code, 1);
    assert.ok(run.stderr.includes('plugin/workflows/analysis-only.js exists but plugin/workflow-src/analysis-only/DRAFT'), run.stderr);
  });
  test('--check fails on a draft that does not build', () => {
    const scratchRoot = makeScratchDraftCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src', DRAFT_ID, 'main.js'), '\nimport x from \'y\';\n');
    assert.throws(() => runCliIn(scratchRoot, ['--check']), new RegExp(DRAFT_ID + ': the built script uses import or require'));
  });
  test('removing the marker reports the script missing, and a stale one stale', () => {
    const scratchRoot = makeScratchDraftCopy();
    rmSync(join(scratchRoot, 'plugin/workflow-src', DRAFT_ID, 'DRAFT'));
    const missing = runCliIn(scratchRoot, ['--check']);
    assert.equal(missing.code, 1);
    assert.ok(missing.stderr.includes('plugin/workflows/' + DRAFT_ID + '.js is stale'), missing.stderr);
    writeFileSync(join(scratchRoot, builtPathFor(DRAFT_ID)), readBuilt('analysis-only'));
    const stale = runCliIn(scratchRoot, ['--check']);
    assert.equal(stale.code, 1);
    assert.ok(stale.stderr.includes('plugin/workflows/' + DRAFT_ID + '.js is stale'), stale.stderr);
  });
  test('a DRAFT entry that is not a regular file fails both modes', () => {
    const directoryRoot = makeScratchDraftCopy();
    const directoryMarker = join(directoryRoot, 'plugin/workflow-src', DRAFT_ID, 'DRAFT');
    rmSync(directoryMarker);
    mkdirSync(directoryMarker);
    const symlinkRoot = makeScratchDraftCopy();
    const symlinkMarker = join(symlinkRoot, 'plugin/workflow-src', DRAFT_ID, 'DRAFT');
    rmSync(symlinkMarker);
    symlinkSync(join(symlinkRoot, 'plugin/workflow-src', DRAFT_ID, 'meta.js'), symlinkMarker);
    for (const scratchRoot of [directoryRoot, symlinkRoot]) {
      for (const argv of [[], ['--check']]) {
        assert.throws(() => runCliIn(scratchRoot, argv), /plugin\/workflow-src\/draft-check\/DRAFT must be a regular file/);
      }
    }
  });
  test('the in-memory draft loads and its meta.name equals its id', async () => {
    const scratchRoot = makeScratchDraftCopy();
    const source = buildWorkflow(scratchRoot, DRAFT_ID);
    const run = await loadWorkflowSource(source, DRAFT_ID + ' (in memory)').run({ args: undefined, results: {} });
    assert.equal(run.meta.name, DRAFT_ID);
  });
});

for (const id of draftIds) {
  describe('draft plugin/workflow-src/' + id + '/', () => {
    test('builds in memory and has no built file', () => {
      assert.doesNotThrow(() => buildWorkflow(repoRoot, id));
      assert.equal(existsSync(join(repoRoot, builtPathFor(id))), false);
    });
    test('meta.name equals the directory name', async () => {
      const run = await loadWorkflowSource(buildWorkflow(repoRoot, id), id + ' (in memory)').run({ args: undefined, results: {} });
      assert.equal(run.meta.name, id);
    });
  });
}

for (const id of liveIds) {
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
      for (const name of ['workflow-src/' + id + '/meta.js', 'workflow-src/' + id + '/main.js', ...LIB_FILES.map((file) => 'workflow-src/lib/' + file), 'decision-autonomy-table.json', 'plan-schema.json']) {
        assert.ok(banner.includes(name), name);
      }
      assert.ok(banner.includes('Do not edit by hand'));
      assert.ok(banner.includes(REBUILD_COMMAND));
    });
    test('data constants and libraries come in build order', () => {
      const markers = ['const AUTONOMY_TABLE = ', 'const BRIEF_SCHEMA = ', 'const PLAN_SCHEMA = ', 'function validateSchema(', 'function decisionReasons(', 'function renderQuestions(', 'function resultFields(', 'function computeWave(', 'function parseRoutingLines(', 'function readArgsObject(', 'function isGitIdentifier(', 'function gatherFactsRoutingSpec('];
      const positions = markers.map((marker) => source.indexOf(marker));
      assert.ok(positions.every((position) => position !== -1), JSON.stringify(positions));
      assert.deepEqual([...positions].sort((left, right) => left - right), positions);
    });
    test('each data constant is one line of JSON equal to its file', () => {
      const constants = [['AUTONOMY_TABLE', 'decision-autonomy-table.json'], ['BRIEF_SCHEMA', 'decision-brief-schema.json'], ['PLAN_SCHEMA', 'plan-schema.json']];
      for (const [name, file] of constants) {
        const line = source.split('\n').find((candidate) => candidate.startsWith('const ' + name + ' = '));
        assert.ok(line !== undefined && line.endsWith(';'), name);
        const data = JSON.parse(line.slice(('const ' + name + ' = ').length, -1));
        assert.deepEqual(data, JSON.parse(readFileSync(join(repoRoot, 'plugin/references', file), 'utf8')), name);
      }
    });
    test('has no comment other than the GENERATED banner', () => {
      const comments = tokenizeSource(source).filter((token) => token.kind === 'comment');
      assert.equal(comments.length, 1);
      assert.ok(comments[0].text.startsWith('/*\n * GENERATED by tools/build_workflows.mjs'));
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
