/**
 * build_workflows.mjs: builds each plugin/workflows/<id>.js from its sources.
 *
 * Usage
 *   node tools/build_workflows.mjs           write every live built script
 *                                            and print a skipped line for
 *                                            each draft
 *   node tools/build_workflows.mjs --check   rebuild in memory and exit 1
 *                                            when a committed script is stale
 *                                            or has no source directory,
 *                                            when a draft has a committed
 *                                            script, or when an entry under
 *                                            plugin/workflows/ is not a
 *                                            regular file
 *
 * Sources
 *   Workflow ids are the directories of plugin/workflow-src/ other than lib.
 *   A workflow is a draft when its directory holds a regular file named
 *   DRAFT. Its contents are not read. A draft is never written to
 *   plugin/workflows/, so it lands in pieces without going live (ADR-0037).
 *   Every other workflow is live.
 *   Each built script is, in order: <id>/meta.js, a GENERATED banner, the
 *   data constants from plugin/references/, the shared libraries from
 *   plugin/workflow-src/lib/ in LIB_FILES order, and <id>/main.js.
 *
 * Invariants
 *   CR is stripped from every input and the output is written with LF only.
 *   The built script starts with `export const meta`, has no import or
 *   require( outside comments and strings, and declares each top-level
 *   function once, or the build throws.
 *   An entry named DRAFT that is not a regular file (a directory, a
 *   symlink, anything else) fails the build in both modes.
 *   --check compares each live workflow with its committed file after
 *   stripping CR, so a lost DRAFT marker shows as a stale or missing script.
 *   --check builds each draft in memory, so a draft that fails to build
 *   fails --check, and fails when plugin/workflows/<id>.js exists for a
 *   draft, so a stray DRAFT marker on a live workflow fails too.
 *   --check lists plugin/workflows/*.js, never the .json engine files, and
 *   names each one with no plugin/workflow-src/<id>/ directory as an orphan.
 *   Every entry under plugin/workflows/ must be a regular file. --check
 *   names each one that is not (a symlink, a directory or anything else),
 *   whatever its name, .js, .json or other, and exits 1. It never reads
 *   through such an entry, so it is not also reported stale. Write mode
 *   checks every target before it writes any, and throws when a target
 *   exists and is not a regular file, so it never writes through a symlink.
 *
 * Why
 *   A running workflow script cannot import or read files, so the build
 *   copies data and libraries in, and --check keeps the copies in step.
 *   The overlord launches the committed scripts by path, so a symlink there
 *   could run content that --check never compared, and a write through one
 *   would change a file outside plugin/workflows/. Only regular files are
 *   allowed, and nothing else is followed.
 */
import { lstatSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = fileURLToPath(new URL('../', import.meta.url));
const REBUILD_COMMAND = 'node tools/build_workflows.mjs';
const SOURCE_DIR = 'plugin/workflow-src';
const OUTPUT_DIR = 'plugin/workflows';
const DRAFT_MARKER = 'DRAFT';
export const LIB_FILES = Object.freeze(['schema.js', 'decide.js', 'brief.js', 'result.js', 'waves.js', 'routing.js', 'args.js', 'identifier.js', 'facts.js']);
const DATA_CONSTANTS = [
  { name: 'AUTONOMY_TABLE', path: 'plugin/references/decision-autonomy-table.json' },
  { name: 'BRIEF_SCHEMA', path: 'plugin/references/decision-brief-schema.json' },
  { name: 'PLAN_SCHEMA', path: 'plugin/references/plan-schema.json' }
];

function readSource(root, relativePath) {
  return readFileSync(join(root, relativePath), 'utf8').replace(/\r/g, '');
}

export function discoverWorkflowIds(root) {
  return readdirSync(join(root, SOURCE_DIR), { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name !== 'lib')
    .map((entry) => entry.name)
    .sort();
}

export function builtPathFor(id) {
  return OUTPUT_DIR + '/' + id + '.js';
}

export function draftMarkerPathFor(id) {
  return SOURCE_DIR + '/' + id + '/' + DRAFT_MARKER;
}

/**
 * Returns true when plugin/workflow-src/<id>/DRAFT is a regular file, false
 * when there is no entry by that name. Throws when the entry is anything
 * else, a symlink included.
 */
export function isDraftWorkflow(root, id) {
  const markerPath = draftMarkerPathFor(id);
  const stats = lstatSync(join(root, markerPath), { throwIfNoEntry: false });
  if (stats === undefined) {
    return false;
  }
  if (!stats.isFile()) {
    throw new Error(markerPath + ' must be a regular file; remove it or replace it with an empty file');
  }
  return true;
}

export function listLiveWorkflowIds(root) {
  return discoverWorkflowIds(root).filter((id) => !isDraftWorkflow(root, id));
}

export function listDraftWorkflowIds(root) {
  return discoverWorkflowIds(root).filter((id) => isDraftWorkflow(root, id));
}

function listSourcePaths(id) {
  return [
    SOURCE_DIR + '/' + id + '/meta.js',
    ...DATA_CONSTANTS.map((constant) => constant.path),
    ...LIB_FILES.map((file) => SOURCE_DIR + '/lib/' + file),
    SOURCE_DIR + '/' + id + '/main.js'
  ];
}

function renderBanner(id) {
  const sourceLines = listSourcePaths(id).map((path) => ' *   ' + path);
  return [
    '/*',
    ' * GENERATED by tools/build_workflows.mjs from:',
    ...sourceLines,
    ' * Do not edit by hand. Rebuild with `' + REBUILD_COMMAND + '`.',
    ' */'
  ].join('\n');
}

function renderDataConstant(root, constant) {
  const data = JSON.parse(readSource(root, constant.path));
  return 'const ' + constant.name + ' = ' + JSON.stringify(data, null, 2) + ';';
}

function skipQuoted(source, start) {
  const quote = source[start];
  let index = start + 1;
  while (index < source.length && source[index] !== quote) {
    index += source[index] === '\\' ? 2 : 1;
  }
  return index + 1;
}

function skipComment(source, start) {
  if (source[start + 1] === '/') {
    const end = source.indexOf('\n', start);
    return end === -1 ? source.length : end;
  }
  const end = source.indexOf('*/', start + 2);
  return end === -1 ? source.length : end + 2;
}

/**
 * Returns source with comments and string or template literals removed.
 * Regex literals are kept, so a regex literal holding a quote or a comment
 * marker is not supported in workflow sources.
 */
export function stripCommentsAndStrings(source) {
  let code = '';
  let index = 0;
  while (index < source.length) {
    const character = source[index];
    const isComment = character === '/' && (source[index + 1] === '/' || source[index + 1] === '*');
    if (isComment) {
      index = skipComment(source, index);
    } else if (character === '\'' || character === '"' || character === '`') {
      index = skipQuoted(source, index);
      code += '""';
    } else {
      code += character;
      index += 1;
    }
  }
  return code;
}

function findDuplicateFunctions(source) {
  const names = [...source.matchAll(/^(?:async\s+)?function\s+([A-Za-z_$][\w$]*)/gm)].map((match) => match[1]);
  return names.filter((name, index) => names.indexOf(name) !== index);
}

function assertBuiltScript(id, output) {
  if (!output.startsWith('export const meta = {')) {
    throw new Error(id + ': meta.js must start with `export const meta = {`');
  }
  const code = stripCommentsAndStrings(output);
  if (/\bimport\b/.test(code) || /\brequire\s*\(/.test(code)) {
    throw new Error(id + ': the built script uses import or require( as code; workflow scripts cannot load modules');
  }
  const duplicates = findDuplicateFunctions(output);
  if (duplicates.length > 0) {
    throw new Error(id + ': top-level functions declared more than once: ' + duplicates.join(', '));
  }
}

export function buildWorkflow(root, id) {
  const parts = [
    readSource(root, SOURCE_DIR + '/' + id + '/meta.js').trim(),
    renderBanner(id),
    ...DATA_CONSTANTS.map((constant) => renderDataConstant(root, constant)),
    ...LIB_FILES.map((file) => readSource(root, SOURCE_DIR + '/lib/' + file).trim()),
    readSource(root, SOURCE_DIR + '/' + id + '/main.js').trim()
  ];
  const output = parts.join('\n\n') + '\n';
  assertBuiltScript(id, output);
  return output;
}

/**
 * Returns the kind of the entry at relativePath without following a
 * symlink: missing, file, symlink, directory or other.
 */
export function readEntryKind(root, relativePath) {
  const stats = lstatSync(join(root, relativePath), { throwIfNoEntry: false });
  if (stats === undefined) {
    return 'missing';
  }
  if (stats.isFile()) {
    return 'file';
  }
  if (stats.isSymbolicLink()) {
    return 'symlink';
  }
  return stats.isDirectory() ? 'directory' : 'other';
}

/**
 * Returns {path, kind} for each entry under plugin/workflows/ that is not a
 * regular file, by name.
 */
export function findNonRegularOutputs(root) {
  return readdirSync(join(root, OUTPUT_DIR))
    .sort()
    .map((name) => ({ path: OUTPUT_DIR + '/' + name, kind: readEntryKind(root, OUTPUT_DIR + '/' + name) }))
    .filter((entry) => entry.kind !== 'file');
}

function describeNonRegularOutput(entry) {
  const kindText = entry.kind === 'other' ? 'not a file, a directory or a symlink' : 'a ' + entry.kind;
  return entry.path + ' is ' + kindText + '. Every entry under ' + OUTPUT_DIR + '/ must be a regular file. Remove it, then rebuild with: ' + REBUILD_COMMAND;
}

function isStale(root, id) {
  const builtPath = builtPathFor(id);
  const kind = readEntryKind(root, builtPath);
  if (kind === 'missing') {
    return true;
  }
  return kind === 'file' && readSource(root, builtPath) !== buildWorkflow(root, id);
}

export function findOrphanWorkflowIds(root) {
  const workflowIds = discoverWorkflowIds(root);
  return readdirSync(join(root, OUTPUT_DIR), { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.js'))
    .map((entry) => entry.name.slice(0, -'.js'.length))
    .filter((id) => !workflowIds.includes(id))
    .sort();
}

function describeOrphan(id) {
  return builtPathFor(id) + ' is an orphan: there is no ' + SOURCE_DIR + '/' + id + '/ source directory. Add the source or remove the script.';
}

export function findStaleWorkflows(root) {
  return listLiveWorkflowIds(root).filter((id) => isStale(root, id)).map(builtPathFor);
}

/**
 * Builds each draft in memory, so a draft that fails to build throws, and
 * returns the ids of the drafts that have a committed built script.
 */
export function findBuiltDraftIds(root) {
  const draftIds = listDraftWorkflowIds(root);
  draftIds.forEach((id) => buildWorkflow(root, id));
  return draftIds.filter((id) => readEntryKind(root, builtPathFor(id)) !== 'missing');
}

function describeBuiltDraft(id) {
  return builtPathFor(id) + ' exists but ' + draftMarkerPathFor(id) + ' marks the workflow as a draft. Remove the script, or remove the marker to make the workflow live.';
}

/**
 * Writes every live built script. Throws before any write when a target
 * exists and is not a regular file.
 */
export function writeWorkflows(root) {
  const liveIds = listLiveWorkflowIds(root);
  liveIds.forEach((id) => assertWritableTarget(root, builtPathFor(id)));
  return liveIds.map((id) => {
    const builtPath = builtPathFor(id);
    writeFileSync(join(root, builtPath), buildWorkflow(root, id));
    return builtPath;
  });
}

function assertWritableTarget(root, builtPath) {
  const kind = readEntryKind(root, builtPath);
  if (kind !== 'missing' && kind !== 'file') {
    throw new Error(describeNonRegularOutput({ path: builtPath, kind: kind }));
  }
}

/**
 * Runs the command line. Returns the exit code: 0 on success, 1 when --check
 * finds a stale or orphan script, a draft with a built script or an entry
 * under plugin/workflows/ that is not a regular file, 2 on an unknown
 * argument. A build error throws, as does a write through a target that is
 * not a regular file.
 */
export function runCli(argv, { root, stdout, stderr }) {
  const unknown = argv.filter((arg) => arg !== '--check');
  if (unknown.length > 0) {
    stderr.write('build_workflows: unknown argument ' + unknown[0] + '. Usage: ' + REBUILD_COMMAND + ' [--check]\n');
    return 2;
  }
  if (argv.includes('--check')) {
    const stale = findStaleWorkflows(root);
    const orphanIds = findOrphanWorkflowIds(root);
    const builtDraftIds = findBuiltDraftIds(root);
    const nonRegular = findNonRegularOutputs(root);
    stale.forEach((builtPath) => stderr.write(builtPath + ' is stale. Rebuild with: ' + REBUILD_COMMAND + '\n'));
    orphanIds.forEach((id) => stderr.write(describeOrphan(id) + '\n'));
    builtDraftIds.forEach((id) => stderr.write(describeBuiltDraft(id) + '\n'));
    nonRegular.forEach((entry) => stderr.write(describeNonRegularOutput(entry) + '\n'));
    const failures = stale.length + orphanIds.length + builtDraftIds.length + nonRegular.length;
    return failures > 0 ? 1 : 0;
  }
  writeWorkflows(root).forEach((builtPath) => stdout.write('wrote ' + builtPath + '\n'));
  listDraftWorkflowIds(root).forEach((id) => stdout.write('skipped ' + builtPathFor(id) + ': ' + draftMarkerPathFor(id) + ' marks it as a draft\n'));
  return 0;
}

const invokedPath = process.argv[1] === undefined ? '' : resolve(process.argv[1]);
if (invokedPath === fileURLToPath(import.meta.url)) {
  process.exitCode = runCli(process.argv.slice(2), { root: REPO_ROOT, stdout: process.stdout, stderr: process.stderr });
}
