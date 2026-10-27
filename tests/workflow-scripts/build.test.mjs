import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { loadWorkflow, loadWorkflowSource } from './harness.mjs';
import {
  LIB_FILES,
  MAX_BUILT_LINE_LENGTH,
  MAX_BUILT_LINE_SQUARES,
  MAX_BUILT_SCRIPT_LENGTH,
  PROSE_BUDGETS,
  WORKFLOW_APPROVAL_LIMIT,
  WORKFLOW_PREVIEW_COMBINING_RUN_LIMIT,
  WORKFLOW_PREVIEW_LINE_LIMIT,
  WORKFLOW_PREVIEW_SQUARES_LIMIT,
  assertCompactionPreserves,
  buildWorkflow,
  builtPathFor,
  compactCode,
  compactSource,
  countProseCharacters,
  discoverWorkflowIds,
  findCopiedSentences,
  findNonRegularOutputs,
  findOrphanWorkflowIds,
  findTopLevelStatement,
  isDraftWorkflow,
  listDraftWorkflowIds,
  listLiveWorkflowIds,
  listModulePaths,
  listNamedPromptFiles,
  listSourcePaths,
  REPOSITORY_PATH_MARK,
  projectAutonomyTable,
  projectSchema,
  readDataConstant,
  runCli,
  splitProseSentences,
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
const MAX_SOURCE_LINES = 600;
const DELIVERY_MODULES = ['gates.js', 'plan.js', 'pr.js', 'record.js', 'relay.js', 'review.js', 'waves.js'];
const PROSE_BUDGETS_PATTERN = /export const PROSE_BUDGETS = Object\.freeze\(\{[^}]*\}\);/;
const MAX_PROSE_MARGIN = 1000;
const CEREBRATE_SENTENCE = 'You do not write or edit code.';
const PLAN_PROMPT_OPENING = '\'Plan the delivery of the user request below in this repository, as one plan on one working branch.';
const scratchRoots = [];
let scratchBuilderCount = 0;

function readBuilt(id) {
  return readFileSync(join(repoRoot, builtPathFor(id)), 'utf8').replace(/\r/g, '');
}

function makeScratchCopy() {
  const scratchRoot = mkdtempSync(join(tmpdir(), 'build-workflows-'));
  scratchRoots.push(scratchRoot);
  for (const dir of ['plugin/workflow-src', 'plugin/references', 'plugin/workflows', 'plugin/agents']) {
    cpSync(join(repoRoot, dir), join(scratchRoot, dir), { recursive: true });
  }
  copySkillFiles(scratchRoot);
  return scratchRoot;
}

/**
 * Copies plugin/skills/<name>/SKILL.md of every skill into a scratch copy,
 * the files the duplication check reads.
 */
function copySkillFiles(scratchRoot) {
  const skillNames = readdirSync(join(repoRoot, 'plugin/skills')).filter((name) => existsSync(join(repoRoot, 'plugin/skills', name, 'SKILL.md')));
  for (const name of skillNames) {
    mkdirSync(join(scratchRoot, 'plugin/skills', name), { recursive: true });
    cpSync(join(repoRoot, 'plugin/skills', name, 'SKILL.md'), join(scratchRoot, 'plugin/skills', name, 'SKILL.md'));
  }
}

/**
 * Writes a copy of tools/build_workflows.mjs under a new name into
 * scratchRoot whose PROSE_BUDGETS is budgets, and returns the imported copy.
 */
async function loadScratchBuilder(scratchRoot, budgets) {
  const builderSource = readFileSync(builderPath, 'utf8');
  assert.ok(PROSE_BUDGETS_PATTERN.test(builderSource), 'PROSE_BUDGETS is not one frozen object literal');
  scratchBuilderCount += 1;
  const scratchBuilderPath = join(scratchRoot, 'tools/build_workflows.' + scratchBuilderCount + '.mjs');
  mkdirSync(join(scratchRoot, 'tools'), { recursive: true });
  writeFileSync(scratchBuilderPath, builderSource.replace(PROSE_BUDGETS_PATTERN, 'export const PROSE_BUDGETS = Object.freeze(' + JSON.stringify(budgets) + ');'));
  return import(pathToFileURL(scratchBuilderPath).href);
}

function loadDraftBuilder(scratchRoot) {
  return loadScratchBuilder(scratchRoot, { ...PROSE_BUDGETS, [DRAFT_ID]: PROSE_BUDGETS['analysis-only'] });
}

/**
 * Seeds sentence into the opening line of the standard-delivery plan
 * prompt of a scratch copy.
 */
function seedPlanPromptSentence(scratchRoot, sentence) {
  const planPath = join(scratchRoot, 'plugin/workflow-src/standard-delivery/plan.js');
  const planSource = readFileSync(planPath, 'utf8');
  assert.ok(planSource.includes(PLAN_PROMPT_OPENING), 'the plan prompt opening moved');
  writeFileSync(planPath, planSource.replace(PLAN_PROMPT_OPENING, PLAN_PROMPT_OPENING + ' ' + sentence));
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

function sumLineSquares(source) {
  return source.split('\n').reduce((sum, line) => sum + line.length * line.length, 0);
}

function findLongestLineLength(source) {
  return source.split('\n').reduce((longest, line) => Math.max(longest, line.length), 0);
}

/**
 * Returns [location, node] for schema and every node under its properties
 * and items, in walk order.
 */
function collectSchemaNodes(schema, location, nodes) {
  nodes.push([location, schema]);
  Object.entries(schema.properties === undefined ? {} : schema.properties).forEach(([name, field]) => collectSchemaNodes(field, location + '.' + name, nodes));
  if (schema.items !== undefined) {
    collectSchemaNodes(schema.items, location + '[]', nodes);
  }
  return nodes;
}

function listMarkedLocations(schema) {
  return collectSchemaNodes(schema, '$', [])
    .filter(([, node]) => typeof node.description === 'string' && node.description.startsWith(REPOSITORY_PATH_MARK))
    .map(([location]) => location);
}

function findLongestCombiningRun(source) {
  return [...source.matchAll(/[\p{M}\p{Cf}]+/gu)].reduce((longest, match) => Math.max(longest, [...match[0]].length), 0);
}

/**
 * Returns a log statement line of exactly length characters.
 */
function makeLogLine(length) {
  return 'log(\'' + 'x'.repeat(length - 'log(\'\');'.length) + '\');';
}

function appendAnalysisMainLines(scratchRoot, lines) {
  appendFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js'), '\n' + lines.join('\n') + '\n');
}

function assertBuildAndCheckThrow(scratchRoot, pattern) {
  assert.throws(() => buildWorkflow(scratchRoot, 'analysis-only'), pattern);
  assert.throws(() => runCliIn(scratchRoot, ['--check']), pattern);
}

/**
 * Returns every workflow source path the build reads from
 * plugin/workflow-src/, relative to it, once each.
 */
function listWorkflowSourcePaths() {
  const paths = workflowIds.flatMap((id) => listSourcePaths(repoRoot, id)).filter((path) => path.startsWith('plugin/workflow-src/'));
  return [...new Set(paths)].map((path) => path.slice('plugin/workflow-src/'.length));
}

function countLines(source) {
  return source.split('\n').length - (source.endsWith('\n') ? 1 : 0);
}

function createStream() {
  const chunks = [];
  return { write: (chunk) => chunks.push(chunk), text: () => chunks.join('') };
}

function runCliIn(root, argv, run = runCli) {
  const stdout = createStream();
  const stderr = createStream();
  const code = run(argv, { root, stdout, stderr });
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
  test('stripCommentsAndStrings reads a / after ++ or -- as division, never a regex', () => {
    assert.equal(stripCommentsAndStrings('x = a++ / 2 / 3; y = b-- / c / d;'), 'x = a++ / 2 / 3; y = b-- / c / d;');
    assert.equal(stripCommentsAndStrings('x = a+++/import/.source;'), 'x = a+++"".source;');
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
    ['division after a postfix ++', 'x = a++ / 2 / 3;'],
    ['a regex after + following ++', 'x = a+++/b/.source.length;'],
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
    ['a comment after a regex', 'x = /a/g; // c\ny();', 'x = /a/g;\ny();'],
    ['a line comment after division after a postfix ++', 'x = a++ / 2 // c', 'x = a++ / 2'],
    ['a line comment after division after a postfix --', 'x = b-- / c // d', 'x = b-- / c'],
    ['a line comment after division after a prefix ++ operand', 'x = ++a / 2 // c', 'x = ++a / 2'],
    ['a comment after a regex following ++ and +', 'x = a+++/b/g.source; // c', 'x = a+++/b/g.source;']
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
    const sourcePaths = listWorkflowSourcePaths();
    assert.ok(DELIVERY_MODULES.every((name) => sourcePaths.includes('standard-delivery/' + name)), JSON.stringify(sourcePaths));
    const listLiterals = (source) => tokenizeSource(source).filter((token) => token.kind !== 'code' && token.kind !== 'comment').map((token) => token.text);
    for (const sourcePath of sourcePaths) {
      const source = readFileSync(join(repoRoot, 'plugin/workflow-src', sourcePath), 'utf8').replace(/\r/g, '');
      const output = stripComments(source);
      assert.deepEqual(listLiterals(output), listLiterals(source), sourcePath);
      assert.ok(tokenizeSource(output).every((token) => token.kind !== 'comment'), sourcePath);
    }
  });
});

describe('build_workflows compactCode', () => {
  const compacted = [
    ['two plus signs apart', 'x = a + +b;', 'x=a+ +b;'],
    ['two minus signs apart', 'x = a - -b;', 'x=a- -b;'],
    ['a plus before a prefix ++', 'x = a + ++b;', 'x=a+ ++b;'],
    ['a postfix ++ before a plus', 'x = a++ + b;', 'x=a++ +b;'],
    ['a division before a regex', 'x = a / /b/.source;', 'x=a/ /b/.source;'],
    ['a regex before a star', 'x = /a/ * 2;', 'x=/a/ *2;'],
    ['a < before !--', 'x = a < !--b;', 'x=a< !--b;'],
    ['a postfix -- before >', 'x = a-- > b;', 'x=a-- >b;'],
    ['two words', 'const value = typeof item;', 'const value=typeof item;'],
    ['a regex before a word', 'x = /a/ in y;', 'x=/a/ in y;'],
    ['a regex with flags before a word', 'x = /a/g in y;', 'x=/a/g in y;'],
    ['a digit before a dot', 'x = 1 .toString();', 'x=1 .toString();'],
    ['indentation, trailing blanks and blank lines, keeping every newline', 'function a() {  \n  if (x) {\n\n    return 1;\n  }\n}\n', 'function a(){\nif(x){\nreturn 1;\n}\n}'],
    ['a line break automatic semicolon insertion reads', 'a = b\n  (c)\nreturn\n  x', 'a=b\n(c)\nreturn\nx'],
    ['code inside a substitution, keeping the literal bytes', 'x = \'a  b\' + `c  ${ d  +  e }  f` + /g  h/;', 'x=\'a  b\'+`c  ${d+e}  f`+/g  h/;'],
    ['the last line the harness reads', '  return await runDelivery(args);\n', 'return await runDelivery(args);']
  ];
  for (const [name, source, expected] of compacted) {
    test('compacts ' + name, () => {
      const output = compactCode(source);
      assert.equal(output, expected);
      assert.doesNotThrow(() => assertCompactionPreserves('case.js', source, output));
    });
  }
  test('keeps every literal of every compacted source byte for byte, every newline, and changes only whitespace', () => {
    const listLiterals = (source) => tokenizeSource(source).filter((token) => token.kind !== 'code').map((token) => token.text);
    const countCodeNewlines = (source) => tokenizeSource(source).filter((token) => token.kind === 'code').map((token) => token.text.replace(/\s*\n\s*/g, '\n')).join('').split('\n').length;
    for (const sourcePath of listWorkflowSourcePaths()) {
      const stripped = stripComments(readFileSync(join(repoRoot, 'plugin/workflow-src', sourcePath), 'utf8').replace(/\r/g, '')).trim();
      const output = compactSource(sourcePath, stripped);
      assert.deepEqual(listLiterals(output), listLiterals(stripped), sourcePath);
      assert.equal(countCodeNewlines(output), countCodeNewlines(stripped), sourcePath);
      assert.ok(output.length < stripped.length, sourcePath);
    }
  });
  const broken = [
    ['a changed literal', 'x = "a";', 'x="b";', /^Error: lib\/seeded\.js: compaction changed literal 1 from "string \\"a\\"" to "string \\"b\\""/],
    ['a dropped literal', 'x = "a" + "b";', 'x="a"+b;', /^Error: lib\/seeded\.js: compaction changed literal 2 from "string \\"b\\"" to undefined/],
    ['an added literal', 'x = a;', 'x="a";', /^Error: lib\/seeded\.js: compaction changed literal 1 from undefined to "string \\"a\\""/],
    ['two literals in a new order', 'x = "a" + "b";', 'x="b"+"a";', /^Error: lib\/seeded\.js: compaction changed literal 1/],
    ['a division joined with a regex into a comment', 'x = a / /b/.source;', 'x=a//b/.source;', /^Error: lib\/seeded\.js: compaction changed literal 1 from "regex \/b\/" to "comment \/\/b\/.source;"/],
    ['changed code', 'x = a;', 'x=b;', /^Error: lib\/seeded\.js: compaction changed the code once all whitespace is removed$/],
    ['a literal moved across code', 'x = a + "b";', 'x="b"+a;', /^Error: lib\/seeded\.js: compaction changed the code once all whitespace is removed$/]
  ];
  for (const [name, original, output, pattern] of broken) {
    test('the equivalence check fails on ' + name + ', naming the file', () => {
      assert.throws(() => assertCompactionPreserves('lib/seeded.js', original, output), (error) => pattern.test(String(error)));
    });
  }
  for (const id of liveIds) {
    test(builtPathFor(id) + ' keeps the layout of meta.js and the data constants and compacts the libraries, modules and main.js', () => {
      const source = readBuilt(id);
      const meta = stripComments(readFileSync(join(repoRoot, 'plugin/workflow-src', id, 'meta.js'), 'utf8').replace(/\r/g, '')).trim();
      assert.ok(source.startsWith(meta + '\n\n/*\n * GENERATED'), id);
      assert.ok(meta.includes('\n  '), id);
      for (const name of ['AUTONOMY_TABLE', 'BRIEF_SCHEMA', 'PLAN_SCHEMA']) {
        assert.ok(source.includes('\n\nconst ' + name + ' = ' + JSON.stringify(readDataConstant(repoRoot, name), null, 1).replace(/^ +/gm, '') + ';\n\n'), name);
      }
      const codePaths = listSourcePaths(repoRoot, id).filter((path) => path.startsWith('plugin/workflow-src/') && !path.endsWith('/meta.js'));
      for (const path of codePaths) {
        const stripped = stripComments(readFileSync(join(repoRoot, path), 'utf8').replace(/\r/g, '')).trim();
        assert.ok(source.includes('\n\n' + compactCode(stripped) + '\n'), path);
      }
    });
  }
  test('the built standard-delivery.js keeps its last line return await runDelivery(args);', () => {
    assert.ok(readBuilt('standard-delivery').endsWith('\nreturn await runDelivery(args);\n'));
  });
});

describe('build_workflows modules', () => {
  test('the source list is meta.js, the data, the libraries, the modules in name order, then main.js', () => {
    const expected = [
      'plugin/workflow-src/standard-delivery/meta.js',
      'plugin/references/decision-autonomy-table.json',
      'plugin/references/decision-brief-schema.json',
      'plugin/references/plan-schema.json',
      ...LIB_FILES.map((file) => 'plugin/workflow-src/lib/' + file),
      ...DELIVERY_MODULES.map((name) => 'plugin/workflow-src/standard-delivery/' + name),
      'plugin/workflow-src/standard-delivery/main.js'
    ];
    assert.deepEqual(listSourcePaths(repoRoot, 'standard-delivery'), expected);
    assert.deepEqual(listModulePaths(repoRoot, 'standard-delivery'), DELIVERY_MODULES.map((name) => 'plugin/workflow-src/standard-delivery/' + name));
    assert.deepEqual(listModulePaths(repoRoot, 'analysis-only'), []);
  });
  test('contract.js is test data and is never bundled', () => {
    assert.ok(existsSync(join(repoRoot, 'plugin/workflow-src/standard-delivery/contract.js')));
    assert.ok(!listSourcePaths(repoRoot, 'standard-delivery').some((path) => path.endsWith('/contract.js')));
    assert.ok(!buildWorkflow(repoRoot, 'standard-delivery').includes('function contractRows('));
  });
  test('the modules come after the libraries and before main.js, in name order', () => {
    const source = buildWorkflow(repoRoot, 'standard-delivery');
    const firstFunctions = DELIVERY_MODULES.map((name) => {
      const moduleSource = readFileSync(join(repoRoot, 'plugin/workflow-src/standard-delivery', name), 'utf8');
      return /^(?:async )?function \w+\(/m.exec(moduleSource)[0];
    });
    const markers = ['function gatherFactsRoutingSpec(', ...firstFunctions, 'const RUN_NOUN='];
    const positions = markers.map((marker) => source.indexOf(marker));
    assert.ok(positions.every((position) => position !== -1), JSON.stringify(positions));
    assert.deepEqual([...positions].sort((left, right) => left - right), positions);
  });
  test('a module of function declarations builds, and the banner names it before main.js', () => {
    const scratchRoot = makeScratchCopy();
    writeFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/extra.js'), '/*\n * extra.js: a seeded module.\n */\n\nasync function seededHelper(value = { key: [1] }) {\n  return { value: value, text: \'const X = 1;\' };\n}\n\nfunction seededOther() {\n  return /[{(]/.test(\'}\');\n}\n');
    writeFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/notes.txt'), 'const NOT_A_MODULE = 1;\n');
    assert.deepEqual(listModulePaths(scratchRoot, 'analysis-only'), ['plugin/workflow-src/analysis-only/extra.js']);
    const source = buildWorkflow(scratchRoot, 'analysis-only');
    const banner = source.slice(source.indexOf('/*\n * GENERATED'), source.indexOf('*/'));
    assert.ok(banner.includes(' *   plugin/workflow-src/analysis-only/extra.js\n *   plugin/workflow-src/analysis-only/main.js\n'), banner);
    assert.ok(source.indexOf('async function seededHelper(') > source.indexOf('function gatherFactsRoutingSpec('));
    assert.ok(!source.includes('extra.js: a seeded module'));
    assert.ok(!source.includes('NOT_A_MODULE'));
  });
  test('a top-level const in a module fails the build and --check, naming the file', () => {
    const scratchRoot = makeScratchCopy();
    writeFileSync(join(scratchRoot, 'plugin/workflow-src/analysis-only/seeded.js'), 'function seededHelper() {\n  return SEEDED_LIMIT;\n}\n\nconst SEEDED_LIMIT = 3;\n');
    assertBuildAndCheckThrow(scratchRoot, /plugin\/workflow-src\/analysis-only\/seeded\.js: a module holds only function declarations at top level, but it holds "const SEEDED_LIMIT = 3;"/);
  });
  test('a top-level const seeded into a standard-delivery module fails both modes, naming the file', () => {
    const scratchRoot = makeScratchCopy();
    appendFileSync(join(scratchRoot, 'plugin/workflow-src/standard-delivery/relay.js'), '\nconst SEEDED_NAME = \'relay\';\n');
    const pattern = /plugin\/workflow-src\/standard-delivery\/relay\.js: a module holds only function declarations at top level, but it holds "const SEEDED_NAME = \\"\\";"/;
    assert.throws(() => buildWorkflow(scratchRoot, 'standard-delivery'), pattern);
    assert.throws(() => runCliIn(scratchRoot, ['--check']), pattern);
    assert.throws(() => runCliIn(scratchRoot, []), pattern);
  });
  const topLevelCases = [
    ['function declarations only', 'function a() {}\nasync function b(c = { d: [1] }) {\n  return { e: (c) };\n}\n', undefined],
    ['a const after a function', 'function a() {}\nconst b = 1;\n', 'const b = 1;'],
    ['a call statement', 'f();\nfunction a() {}\n', 'f();'],
    ['a stray semicolon', 'function a() {};\n', ';'],
    ['an exported function', 'export function a() {}\n', 'export function a() {}'],
    ['a function expression call', '(function a() {})();\n', '(function a() {})();'],
    ['an unclosed function body', 'function a() {\n', 'function a() {']
  ];
  for (const [name, code, expected] of topLevelCases) {
    test('findTopLevelStatement finds ' + name, () => {
      assert.equal(findTopLevelStatement(code), expected);
    });
  }
  test('every workflow source file is at most ' + MAX_SOURCE_LINES + ' lines', () => {
    const sourceFiles = readdirSync(join(repoRoot, 'plugin/workflow-src')).flatMap((dir) => readdirSync(join(repoRoot, 'plugin/workflow-src', dir)).filter((name) => name.endsWith('.js')).map((name) => dir + '/' + name));
    assert.ok(sourceFiles.length > DELIVERY_MODULES.length);
    for (const sourceFile of sourceFiles) {
      const lineCount = countLines(readFileSync(join(repoRoot, 'plugin/workflow-src', sourceFile), 'utf8'));
      assert.ok(lineCount <= MAX_SOURCE_LINES, sourceFile + ' has ' + lineCount + ' lines');
    }
  });
});

describe('build_workflows length budget', () => {
  test('the limits are pinned', () => {
    assert.equal(WORKFLOW_APPROVAL_LIMIT, 200000);
    assert.equal(MAX_BUILT_SCRIPT_LENGTH, 190000);
    assert.equal(WORKFLOW_PREVIEW_LINE_LIMIT, 4096);
    assert.equal(WORKFLOW_PREVIEW_SQUARES_LIMIT, 67108864);
    assert.equal(WORKFLOW_PREVIEW_COMBINING_RUN_LIMIT, 8);
    assert.equal(MAX_BUILT_LINE_LENGTH, 2048);
    assert.equal(MAX_BUILT_LINE_SQUARES, 50000000);
  });
  test('a script over the budget fails the build and --check, naming the id and the length', () => {
    const scratchRoot = makeScratchCopy();
    const mainPath = join(scratchRoot, 'plugin/workflow-src/analysis-only/main.js');
    const mainBefore = readFileSync(mainPath, 'utf8').replace(/\r/g, '');
    const mainAfter = mainBefore + '\nlog(\'' + 'x'.repeat(MAX_BUILT_SCRIPT_LENGTH) + '\');\n';
    writeFileSync(mainPath, mainAfter);
    const length = readBuilt('analysis-only').length + compactCode(stripComments(mainAfter).trim()).length - compactCode(stripComments(mainBefore).trim()).length;
    const pattern = new RegExp('analysis-only: the built script is ' + length + ' characters, over the budget of 190000');
    assert.throws(() => buildWorkflow(scratchRoot, 'analysis-only'), pattern);
    assert.throws(() => runCliIn(scratchRoot, ['--check']), pattern);
  });
  test('a line over the line budget fails the build and --check, naming the id, the line and the length', () => {
    const scratchRoot = makeScratchCopy();
    appendAnalysisMainLines(scratchRoot, [makeLogLine(MAX_BUILT_LINE_LENGTH + 1)]);
    assertBuildAndCheckThrow(scratchRoot, /analysis-only: line \d+ of the built script is 2049 characters, over the line budget of 2048 \(the Workflow approval preview cuts a line over 4096\)/);
  });
  test('squared line lengths over the budget fail the build and --check, naming the id and the sum', () => {
    const scratchRoot = makeScratchCopy();
    const lines = Array.from({ length: 13 }, () => makeLogLine(2000));
    appendAnalysisMainLines(scratchRoot, lines);
    const squares = sumLineSquares(readBuilt('analysis-only')) + 13 * 2000 * 2000;
    assert.ok(squares > MAX_BUILT_LINE_SQUARES);
    assert.ok(readBuilt('analysis-only').length + 13 * 2001 < MAX_BUILT_SCRIPT_LENGTH);
    assertBuildAndCheckThrow(scratchRoot, new RegExp('analysis-only: the sum of the squared line lengths of the built script is ' + squares + ', over the budget of 50000000 \\(the Workflow approval preview limit is 67108864\\)'));
  });
  test('the preview truncation marker text fails the build and --check, naming the id and the line', () => {
    const scratchRoot = makeScratchCopy();
    appendAnalysisMainLines(scratchRoot, ['log(\'… [+3 graphemes]\');']);
    assertBuildAndCheckThrow(scratchRoot, /analysis-only: line \d+ of the built script holds the text "… \[\+", which the budget allows 0 times/);
  });
  test('a run of 9 combining characters fails the build and --check, naming the id, the line and the run', () => {
    const scratchRoot = makeScratchCopy();
    appendAnalysisMainLines(scratchRoot, ['log(\'a' + '́'.repeat(9) + '\');']);
    assertBuildAndCheckThrow(scratchRoot, /analysis-only: line \d+ of the built script has a run of 9 combining or zero-width characters, over the budget of 8 \(the Workflow approval limit is a run of 8\)/);
  });
  test('a run of exactly 8 combining characters and a line of exactly 2048 characters build', async () => {
    const scratchRoot = makeScratchCopy();
    const builder = await loadScratchBuilder(scratchRoot, { ...PROSE_BUDGETS, 'analysis-only': PROSE_BUDGETS['analysis-only'] + MAX_BUILT_LINE_LENGTH + MAX_PROSE_MARGIN });
    appendAnalysisMainLines(scratchRoot, ['log(\'a' + '́'.repeat(8) + '\');', makeLogLine(MAX_BUILT_LINE_LENGTH)]);
    const source = builder.buildWorkflow(scratchRoot, 'analysis-only');
    assert.equal(findLongestLineLength(source), MAX_BUILT_LINE_LENGTH);
    assert.equal(findLongestCombiningRun(source), 8);
    const check = runCliIn(scratchRoot, ['--check'], builder.runCli);
    assert.equal(check.code, 1);
    assert.equal(check.stderr, 'plugin/workflows/analysis-only.js is stale. Rebuild with: ' + REBUILD_COMMAND + '\n');
  });
  for (const id of liveIds) {
    test(builtPathFor(id) + ' is within every budget', () => {
      const source = readBuilt(id);
      assert.ok(source.length <= MAX_BUILT_SCRIPT_LENGTH, String(source.length));
      assert.ok(findLongestLineLength(source) <= MAX_BUILT_LINE_LENGTH, String(findLongestLineLength(source)));
      assert.ok(sumLineSquares(source) <= MAX_BUILT_LINE_SQUARES, String(sumLineSquares(source)));
      assert.ok(!source.includes('… [+'));
      assert.ok(findLongestCombiningRun(source) <= WORKFLOW_PREVIEW_COMBINING_RUN_LIMIT, String(findLongestCombiningRun(source)));
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
  test('--check passes on a draft with no built file', async () => {
    const scratchRoot = makeScratchDraftCopy();
    const run = runCliIn(scratchRoot, ['--check'], (await loadDraftBuilder(scratchRoot)).runCli);
    assert.equal(run.code, 0, run.stderr);
    assert.equal(run.stderr, '');
  });
  test('--check fails when a draft has a built file, naming the file and the marker', async () => {
    const scratchRoot = makeScratchDraftCopy();
    const builder = await loadDraftBuilder(scratchRoot);
    writeFileSync(join(scratchRoot, builtPathFor(DRAFT_ID)), builder.buildWorkflow(scratchRoot, DRAFT_ID));
    const run = runCliIn(scratchRoot, ['--check'], builder.runCli);
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
  test('removing the marker reports the script missing, and a stale one stale', async () => {
    const scratchRoot = makeScratchDraftCopy();
    const builder = await loadDraftBuilder(scratchRoot);
    rmSync(join(scratchRoot, 'plugin/workflow-src', DRAFT_ID, 'DRAFT'));
    const missing = runCliIn(scratchRoot, ['--check'], builder.runCli);
    assert.equal(missing.code, 1);
    assert.ok(missing.stderr.includes('plugin/workflows/' + DRAFT_ID + '.js is stale'), missing.stderr);
    writeFileSync(join(scratchRoot, builtPathFor(DRAFT_ID)), readBuilt('analysis-only'));
    const stale = runCliIn(scratchRoot, ['--check'], builder.runCli);
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
    const source = (await loadDraftBuilder(scratchRoot)).buildWorkflow(scratchRoot, DRAFT_ID);
    const run = await loadWorkflowSource(source, DRAFT_ID + ' (in memory)').run({ args: undefined, results: {} });
    assert.equal(run.meta.name, DRAFT_ID);
  });
});

describe('build_workflows schema projection', () => {
  const schemaFiles = [['BRIEF_SCHEMA', 'decision-brief-schema.json'], ['PLAN_SCHEMA', 'plan-schema.json']];
  test('the repository path mark is the one the plan schema description quotes', () => {
    const planSchema = JSON.parse(readFileSync(join(repoRoot, 'plugin/references/plan-schema.json'), 'utf8'));
    assert.equal(REPOSITORY_PATH_MARK, 'Can carry external content. Repository path.');
    assert.ok(planSchema.description.includes('"' + REPOSITORY_PATH_MARK + '"'));
  });
  for (const [name, file] of schemaFiles) {
    test(name + ' drops only title and description, keeps the mark, and keeps $schema and every validation keyword', () => {
      const fileData = JSON.parse(readFileSync(join(repoRoot, 'plugin/references', file), 'utf8'));
      const projected = readDataConstant(repoRoot, name);
      const fileNodes = collectSchemaNodes(fileData, '$', []);
      const projectedNodes = collectSchemaNodes(projected, '$', []);
      assert.deepEqual(projectedNodes.map(([location]) => location), fileNodes.map(([location]) => location));
      assert.equal(projected.$schema, fileData.$schema);
      fileNodes.forEach(([location, fileNode], index) => {
        const projectedNode = projectedNodes[index][1];
        const isMarked = typeof fileNode.description === 'string' && fileNode.description.startsWith(REPOSITORY_PATH_MARK);
        const keptKeys = Object.keys(fileNode).filter((key) => key !== 'title' && (key !== 'description' || isMarked));
        assert.deepEqual(Object.keys(projectedNode), keptKeys, location);
        for (const key of keptKeys.filter((kept) => !['description', 'properties', 'items'].includes(kept))) {
          assert.deepEqual(projectedNode[key], fileNode[key], location + '.' + key);
        }
        assert.equal(projectedNode.description, isMarked ? REPOSITORY_PATH_MARK : undefined, location);
      });
    });
    test(name + ' keeps the mark on every repository path field', () => {
      const fileData = JSON.parse(readFileSync(join(repoRoot, 'plugin/references', file), 'utf8'));
      const projected = readDataConstant(repoRoot, name);
      assert.deepEqual(listMarkedLocations(projected), listMarkedLocations(fileData));
    });
  }
  test('the plan schema has repository path fields to keep', () => {
    assert.deepEqual(listMarkedLocations(readDataConstant(repoRoot, 'PLAN_SCHEMA')), ['$.versioning.artifact_files[]', '$.steps[].files[]']);
  });
  test('a field named title or description is a field, not an annotation', () => {
    const schema = { title: 'T', type: 'object', properties: { title: { type: 'string', description: 'D' }, description: { type: 'string' } }, items: { description: REPOSITORY_PATH_MARK + ' More.', enum: [{ description: 'kept' }] } };
    assert.deepEqual(projectSchema(schema), { type: 'object', properties: { title: { type: 'string' }, description: { type: 'string' } }, items: { description: REPOSITORY_PATH_MARK, enum: [{ description: 'kept' }] } });
  });
});

describe('build_workflows prose guards', () => {
  test('the prose budgets are pinned, one per workflow id', () => {
    assert.deepEqual(PROSE_BUDGETS, { 'analysis-only': 19000, 'standard-delivery': 42000 });
    assert.ok(Object.isFrozen(PROSE_BUDGETS));
    assert.deepEqual(Object.keys(PROSE_BUDGETS).sort(), workflowIds);
  });
  test('splitProseSentences joins wrapped lines, splits at markers and keeps sentences of five words or more', () => {
    const text = '# A heading of five words\nOne two three four five\n  six. Too short here.\n- a list item of words.\n| a table row of words |\nAfter the table, five words.';
    assert.deepEqual(splitProseSentences(text), ['A heading of five words', 'One two three four five six.', 'a list item of words.', '| a table row of words |', 'After the table, five words.']);
  });
  for (const id of liveIds) {
    test(builtPathFor(id) + ' is within its prose budget by a margin of at most ' + MAX_PROSE_MARGIN, () => {
      const count = countProseCharacters(readBuilt(id));
      assert.ok(count <= PROSE_BUDGETS[id], id + ' holds ' + count);
      assert.ok(PROSE_BUDGETS[id] - count <= MAX_PROSE_MARGIN, id + ' holds ' + count + '; lower its budget');
    });
    test(builtPathFor(id) + ' names cerebrate.md and copies no sentence of a file it names', () => {
      const source = readBuilt(id);
      assert.ok(listNamedPromptFiles(repoRoot, [source]).includes('plugin/agents/cerebrate.md'));
      assert.deepEqual(findCopiedSentences(repoRoot, source), []);
    });
    test('a prose budget one under the count of ' + id + ' fails the build and --check, naming the id, the count and the budget', async () => {
      const scratchRoot = makeScratchCopy();
      const count = countProseCharacters(readBuilt(id));
      const under = await loadScratchBuilder(scratchRoot, { ...PROSE_BUDGETS, [id]: count - 1 });
      const pattern = new RegExp('^Error: ' + id + ': the built script holds ' + count + ' characters of string and template literals, over its prose budget of ' + (count - 1) + '\\.');
      assert.throws(() => under.buildWorkflow(scratchRoot, id), (error) => pattern.test(String(error)));
      assert.throws(() => runCliIn(scratchRoot, ['--check'], under.runCli), (error) => pattern.test(String(error)));
      const exact = await loadScratchBuilder(scratchRoot, { ...PROSE_BUDGETS, [id]: count });
      assert.equal(exact.buildWorkflow(scratchRoot, id), readBuilt(id));
    });
  }
  test('a workflow id with no prose budget fails the build and --check, naming it, live or draft', async () => {
    const scratchRoot = makeScratchCopy();
    const { 'analysis-only': analysisBudget, ...otherBudgets } = PROSE_BUDGETS;
    assert.ok(analysisBudget > 0);
    const unbudgeted = await loadScratchBuilder(scratchRoot, otherBudgets);
    const pattern = new RegExp('^Error: analysis-only: the workflow has no prose budget\\. Add one to PROSE_BUDGETS in tools/build_workflows\\.mjs: its measured count of ' + countProseCharacters(readBuilt('analysis-only')) + ' ');
    for (const argv of [[], ['--check']]) {
      assert.throws(() => runCliIn(scratchRoot, argv, unbudgeted.runCli), (error) => pattern.test(String(error)));
    }
    assert.throws(() => runCliIn(makeScratchDraftCopy(), ['--check']), /^Error: draft-check: the workflow has no prose budget\./);
  });
  test('a cerebrate.md sentence seeded into the plan prompt fails the build and --check, naming the script, the file and the sentence', () => {
    assert.ok(splitProseSentences(readFileSync(join(repoRoot, 'plugin/agents/cerebrate.md'), 'utf8')).includes(CEREBRATE_SENTENCE));
    const pattern = /^Error: standard-delivery: a literal of plugin\/workflows\/standard-delivery\.js repeats a sentence of plugin\/agents\/cerebrate\.md: "You do not write or edit code\."/;
    for (const seeded of [CEREBRATE_SENTENCE, 'You do not  write or\\n  edit code.']) {
      const scratchRoot = makeScratchCopy();
      seedPlanPromptSentence(scratchRoot, seeded);
      assert.throws(() => buildWorkflow(scratchRoot, 'standard-delivery'), (error) => pattern.test(String(error)), seeded);
      for (const argv of [[], ['--check']]) {
        assert.throws(() => runCliIn(scratchRoot, argv), (error) => pattern.test(String(error)), seeded);
      }
    }
  });
  test('a sentence under five words and a sentence of a file no literal names do not fail the build', () => {
    const source = readBuilt('standard-delivery');
    const namedFiles = listNamedPromptFiles(repoRoot, [source]);
    assert.ok(!namedFiles.includes('plugin/agents/overlord.md'));
    const overlordSentence = splitProseSentences(readFileSync(join(repoRoot, 'plugin/agents/overlord.md'), 'utf8')).find((sentence) => /^[A-Za-z ,.]+$/.test(sentence) && sentence.length < 120);
    assert.ok(overlordSentence !== undefined);
    const scratchRoot = makeScratchCopy();
    seedPlanPromptSentence(scratchRoot, 'You create plans only. ' + overlordSentence);
    const seededSource = buildWorkflow(scratchRoot, 'standard-delivery');
    assert.ok(seededSource.includes('You create plans only. ' + overlordSentence));
    assert.deepEqual(findCopiedSentences(scratchRoot, seededSource), []);
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
      const sourceLines = banner.split('\n').filter((line) => line.startsWith(' *   ')).map((line) => line.slice(' *   '.length));
      assert.deepEqual(sourceLines, listSourcePaths(repoRoot, id));
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
    test('each data constant is unindented JSON, one key or element per line, over more than one line, equal to the projection of its file', () => {
      const constants = [['AUTONOMY_TABLE', 'decision-autonomy-table.json', projectAutonomyTable], ['BRIEF_SCHEMA', 'decision-brief-schema.json', projectSchema], ['PLAN_SCHEMA', 'plan-schema.json', projectSchema]];
      for (const [name, file, project] of constants) {
        const fileData = project(JSON.parse(readFileSync(join(repoRoot, 'plugin/references', file), 'utf8')));
        assert.deepEqual(readDataConstant(repoRoot, name), fileData, name);
        const prefix = 'const ' + name + ' = ';
        assert.ok(source.includes(prefix + JSON.stringify(fileData, null, 1).replace(/^ +/gm, '') + ';'), name);
        const start = source.indexOf(prefix) + prefix.length;
        const jsonText = source.slice(start, source.indexOf('\n};', start) + 2);
        assert.ok(!jsonText.split('\n').some((line) => line.startsWith(' ')), name);
        assert.ok(jsonText.includes('\n'), name);
        assert.deepEqual(JSON.parse(jsonText), fileData, name);
      }
    });
    test('AUTONOMY_TABLE holds only the fields a script reads', () => {
      const start = source.indexOf('const AUTONOMY_TABLE = ') + 'const AUTONOMY_TABLE = '.length;
      const table = JSON.parse(source.slice(start, source.indexOf('\n};', start) + 2));
      assert.deepEqual(Object.keys(table), ['levels', 'default_level', 'hard_stops', 'rows']);
      assert.ok(table.hard_stops.length > 0 && table.hard_stops.every((stop) => JSON.stringify(Object.keys(stop)) === '["hard_stop"]'));
      assert.ok(table.rows.length > 0 && table.rows.every((row) => JSON.stringify(Object.keys(row)) === '["kind","high","balanced","low"]'));
      for (const dropped of ['"$comment"', '"version"', '"when"', '"resolved_at"']) {
        assert.ok(!source.slice(start, source.indexOf('\n};', start)).includes(dropped), dropped);
      }
      assert.throws(() => readDataConstant(repoRoot, 'NO_SUCH_CONSTANT'), /no data constant named "NO_SUCH_CONSTANT"/);
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
