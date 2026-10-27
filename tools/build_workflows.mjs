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
 *   plugin/workflow-src/lib/ in LIB_FILES order, the modules of <id>/, and
 *   <id>/main.js last. The modules are the .js entries of <id>/ other
 *   than meta.js, main.js and contract.js, in name order. contract.js is
 *   test data and is never bundled. listSourcePaths returns this order, and
 *   the banner names each source in it.
 *   The build reads every source only through acorn.parse of the vendored
 *   acorn (tools/vendor/acorn/), with ecmaVersion latest: its syntax tree,
 *   and the tokens and comments of its onToken and onComment callbacks,
 *   never a standalone tokenizer. Each library, each module and main.js
 *   parses as a script with top-level return and await allowed. meta.js
 *   parses as a module, since it holds export const meta. A source acorn
 *   cannot parse fails the build, naming the file, in both modes.
 *   Comments are stripped from meta.js, each library, each module and
 *   main.js by stripComments, and each data constant is
 *   JSON.stringify(data, null, 1) with the leading spaces removed from every
 *   line: one key or element per line, no indent. data is the parsed file
 *   cut to the fields a script reads (readDataConstant): AUTONOMY_TABLE
 *   keeps only what projectAutonomyTable returns, and BRIEF_SCHEMA and
 *   PLAN_SCHEMA keep only what projectSchema returns: $schema and every
 *   validation keyword, since validateSchema reads them, and no title and
 *   no description, except that a description starting with
 *   REPOSITORY_PATH_MARK becomes exactly that mark, since
 *   findRepositoryPathProblem walks the schema for it. JSON.stringify
 *   escapes newlines inside strings, so every leading space it writes is
 *   indentation.
 *   After stripComments, the code of each library, each module and main.js
 *   is compacted by compactCode, which writes acorn's tokens of the stripped
 *   source: a newline wherever the stripped source has one between two
 *   tokens, so automatic semicolon insertion sees the same line breaks, one
 *   space only where the two tokens written together would read as other
 *   tokens (see joinsIntoOtherTokens), and nothing elsewhere. meta.js, the
 *   banner, the data constants and the bytes of every string, template and
 *   regex literal are never compacted.
 *
 * Invariants
 *   CR is stripped from every input and the output is written with LF only.
 *   The built script starts with `export const meta`, parses with acorn as
 *   a script in which import and export may appear, holds no
 *   ImportDeclaration, no ImportExpression and no call of require, declares
 *   each top-level function once, compiles as the body of an async
 *   function, and is at most MAX_BUILT_SCRIPT_LENGTH characters long, or the
 *   build throws, in both modes.
 *   The built script also keeps every line at most MAX_BUILT_LINE_LENGTH
 *   characters, keeps the sum of its squared line lengths at most
 *   MAX_BUILT_LINE_SQUARES, never contains the preview truncation marker
 *   text, and has no run of more than WORKFLOW_PREVIEW_COMBINING_RUN_LIMIT
 *   combining or zero-width characters, or the build throws, in both modes.
 *   Lengths are JavaScript string lengths of the lines split on LF, and an
 *   empty line counts 0.
 *   Two equivalence checks run on each library, module and main.js, and
 *   each fails the build, naming the file, in both modes. The original
 *   source and the stripped source parse to equal syntax trees
 *   (assertStrippingPreserves), and the stripped source and the compacted
 *   code parse to equal syntax trees (assertCompactionPreserves). Trees are
 *   equal when every field other than the position fields start, end, loc
 *   and range is equal, literal raw text included. Neither check uses a rule
 *   of the stripper or the compactor, so any change either makes to the
 *   code, a rewritten regex or two tokens merged into one, fails the build.
 *   Every top-level node of a module's syntax tree is a FunctionDeclaration,
 *   or the build throws naming the file, in both modes. So every top-level
 *   const stays in main.js, which runs after every module, and the module
 *   order cannot change what runs.
 *   Two prose guards run on every built script, live or draft, in both
 *   modes (docs/engineering-principles.md P24). The prose budget: the
 *   characters of the built script's string and template literals, read
 *   from acorn's tokens (countProseCharacters), are at most that workflow's
 *   entry in
 *   PROSE_BUDGETS, and a workflow id with no entry fails the build, naming
 *   it. Each budget is the measured count plus a margin of at most 1,000,
 *   and raising a budget is a visible, reviewed change to this file. The
 *   duplication check compares each sentence of at least five words of a
 *   string literal or a template piece, read as acorn decodes it, with
 *   every plugin/agents/*.md and plugin/skills/<name>/SKILL.md,
 *   found by listing those two directories, never from names in the
 *   literals (listPromptFiles). A literal sentence that equals a sentence of
 *   one of them, once whitespace is normalized, fails the build, naming the
 *   script, the file and the sentence (findCopiedSentences). It is a
 *   verbatim-copy tripwire. It reads each literal and each template piece on
 *   its own, so a sentence split across literals joined by +, across a
 *   template substitution or across a join, or reworded, passes it and
 *   rests on review (ADR-0037, local review finding c5199443).
 *   Every file the build reads, a source, a data file, an agent or skill
 *   file or a committed script, goes through readSource, its only file
 *   read, and every input directory it lists goes through readDirectory.
 *   readSource fails the build, naming the path, in both modes, unless the
 *   entry is a regular file that resolves to its own path under the real
 *   path of the root, so a symlink at the leaf or at any parent directory
 *   fails it (assertRepositoryPath). readDirectory fails the same way when
 *   the directory does not resolve to its own path or an entry is a symlink
 *   or neither a file nor a directory. A listing never drops an entry for
 *   its kind: a .js entry of a workflow directory, an .md entry of
 *   plugin/agents/ and a SKILL.md that are not regular files fail the
 *   build. Both modes also fail before they list, read or write anything
 *   under plugin/workflows/ unless it resolves to its own path.
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
 *   A data field no script reads only adds length toward the approval
 *   limit, so the copy leaves it out (issue 459). Indentation and blanks
 *   inside lines do the same, so the build compacts code, and the
 *   equivalence checks prove that stripping and compaction left the code
 *   the same. A hand-written lexer cannot tell a regex from a division after
 *   every token, so the build reads code only through a parser that follows
 *   the spec.
 *   The title and description of each schema field are prose for the
 *   planner, and their home is plugin/references, which the planner reads
 *   (docs/engineering-principles.md P24), so the copy carries only the
 *   repository path mark the plan check reads.
 *   A running script cannot read an agent's or a skill's file, so a rule
 *   copied into a prompt is a second copy that drifts from its home and
 *   grows the script toward the approval limit. The prose budget bounds all
 *   prompt text, and the duplication check fails the build on a rule pasted
 *   whole into one literal, instead of relying on review (P24, P3). A split
 *   or reworded copy still rests on review.
 *   The overlord launches the committed scripts by path, so a symlink there
 *   could run content that --check never compared, and a write through one
 *   would change a file outside plugin/workflows/. Only regular files are
 *   allowed, and nothing else is followed.
 *   The inputs follow the same rule. A committed symlink among them could
 *   copy a file from outside the repository into a built script, where
 *   review or a commit would expose it, and a listing that drops a
 *   symlinked module builds the script without it and says nothing
 *   (ADR-0037, local review finding 0de223ac).
 */
import { lstatSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { parse, tokTypes } from './vendor/acorn/acorn.mjs';

const REPO_ROOT = fileURLToPath(new URL('../', import.meta.url));
const REBUILD_COMMAND = 'node tools/build_workflows.mjs';
const SOURCE_DIR = 'plugin/workflow-src';
const OUTPUT_DIR = 'plugin/workflows';
const DRAFT_MARKER = 'DRAFT';
const NON_MODULE_FILES = Object.freeze(['meta.js', 'main.js', 'contract.js']);
export const LIB_FILES = Object.freeze(['schema.js', 'decide.js', 'brief.js', 'result.js', 'waves.js', 'routing.js', 'args.js', 'identifier.js', 'facts.js']);
const DATA_CONSTANTS = [
  { name: 'AUTONOMY_TABLE', path: 'plugin/references/decision-autonomy-table.json', project: projectAutonomyTable },
  { name: 'BRIEF_SCHEMA', path: 'plugin/references/decision-brief-schema.json', project: projectSchema },
  { name: 'PLAN_SCHEMA', path: 'plugin/references/plan-schema.json', project: projectSchema }
];
export const REPOSITORY_PATH_MARK = 'Can carry external content. Repository path.';
const SCHEMA_ANNOTATION_KEYS = Object.freeze(['title', 'description']);

/**
 * Returns the fields of the decision autonomy table that a script reads:
 * levels, default_level, each hard stop's hard_stop, and each row's kind
 * and its high, balanced and low cells, in that order. Every other field,
 * such as $comment, version, when and resolved_at, is left out.
 */
export function projectAutonomyTable(table) {
  return {
    levels: table.levels,
    default_level: table.default_level,
    hard_stops: table.hard_stops.map((stop) => ({ hard_stop: stop.hard_stop })),
    rows: table.rows.map((row) => ({ kind: row.kind, high: row.high, balanced: row.balanced, low: row.low }))
  };
}

/**
 * Returns a copy of the JSON schema node schema with no title and no
 * description, walking properties and items as findRepositoryPathProblem
 * does. A description starting with REPOSITORY_PATH_MARK is kept as exactly
 * that mark. Every other key, $schema and each validation keyword, is kept
 * unchanged, and the keys of properties are field names, never annotations.
 */
export function projectSchema(schema) {
  const projected = {};
  for (const [key, value] of Object.entries(schema)) {
    if (key === 'description' && typeof value === 'string' && value.startsWith(REPOSITORY_PATH_MARK)) {
      projected.description = REPOSITORY_PATH_MARK;
    } else if (key === 'properties') {
      projected.properties = Object.fromEntries(Object.entries(value).map(([name, field]) => [name, projectSchema(field)]));
    } else if (key === 'items') {
      projected.items = projectSchema(value);
    } else if (!SCHEMA_ANNOTATION_KEYS.includes(key)) {
      projected[key] = value;
    }
  }
  return projected;
}

/**
 * Returns the data that the built script holds for the data constant named
 * name: the parsed file, cut by that constant's projection.
 */
export function readDataConstant(root, name) {
  const constant = DATA_CONSTANTS.find((candidate) => candidate.name === name);
  if (constant === undefined) {
    throw new Error('readDataConstant: no data constant named ' + JSON.stringify(name));
  }
  return constant.project(JSON.parse(readSource(root, constant.path)));
}

/**
 * WORKFLOW_APPROVAL_LIMIT is the script length, in UTF-16 code units, above
 * which Claude Code 2.1.308 offers only "No" in the Workflow approval dialog.
 * It is an undocumented constant of that release, and an update may lower
 * it. The build fails above MAX_BUILT_SCRIPT_LENGTH, so the 10,000 margin
 * lets the pull request that crosses the budget fail while its script is
 * still approvable. No CR allowance is needed: .gitattributes pins
 * plugin/workflows/*.js to eol=lf.
 */
export const WORKFLOW_APPROVAL_LIMIT = 200000;
export const MAX_BUILT_SCRIPT_LENGTH = 190000;

/**
 * Claude Code 2.1.308 offers only "No" in the Workflow approval dialog when:
 *   (1) the script is longer than WORKFLOW_APPROVAL_LIMIT;
 *   (2) the script is flagged as forged, which the build cannot control;
 *   (3) the sanitized preview holds the marker `… [+N graphemes]`. The
 *       preview cuts any line longer than WORKFLOW_PREVIEW_LINE_LIMIT. It
 *       spends a budget of WORKFLOW_PREVIEW_SQUARES_LIMIT on the squared
 *       length of each line, and once that is spent it cuts any line longer
 *       than 1024 and later replaces whole lines. The marker text written
 *       into the script trips the same check;
 *   (4) the script holds a run of more than
 *       WORKFLOW_PREVIEW_COMBINING_RUN_LIMIT combining or zero-width
 *       characters.
 * These are undocumented constants of that release, and an update may lower
 * them. The build fails above MAX_BUILT_LINE_LENGTH and MAX_BUILT_LINE_SQUARES,
 * so the margins let the pull request that crosses a budget fail while its
 * script is still approvable.
 */
export const WORKFLOW_PREVIEW_LINE_LIMIT = 4096;
export const WORKFLOW_PREVIEW_SQUARES_LIMIT = 67108864;
export const WORKFLOW_PREVIEW_COMBINING_RUN_LIMIT = 8;
export const MAX_BUILT_LINE_LENGTH = 2048;
export const MAX_BUILT_LINE_SQUARES = 50000000;
const PREVIEW_MARKER_TEXT = '… [+';
const COMBINING_RUN_PATTERN = /[\p{M}\p{Cf}]+/gu;

const BUILD_INPUT_RULE = 'The build reads only regular files and directories at their own path inside the repository, and follows no symlink';
const ENTRY_KIND_TEXT = Object.freeze({ missing: 'missing', symlink: 'a symlink', directory: 'a directory', other: 'not a file, a directory or a symlink' });

/**
 * Throws, naming relativePath, unless the entry at relativePath resolves to
 * that same path under the real path of root, so that no component of it,
 * the leaf or a parent directory, is a symlink.
 */
function assertRepositoryPath(root, relativePath) {
  if (realpathSync(join(root, relativePath)) !== join(realpathSync(root), relativePath)) {
    throw new Error(relativePath + ' resolves to another path through a symlink. ' + BUILD_INPUT_RULE);
  }
}

/**
 * Returns the text of the file at relativePath with CR stripped. It is the
 * build's only file read. Throws, naming relativePath, unless the entry is a
 * regular file that resolves to its own path (assertRepositoryPath).
 */
function readSource(root, relativePath) {
  const kind = readEntryKind(root, relativePath);
  if (kind !== 'file') {
    throw new Error(relativePath + ' is ' + ENTRY_KIND_TEXT[kind] + ', not a regular file. ' + BUILD_INPUT_RULE);
  }
  assertRepositoryPath(root, relativePath);
  return readFileSync(join(root, relativePath), 'utf8').replace(/\r/g, '');
}

/**
 * Returns the entries of the directory at relativePath. It is the build's
 * only listing of an input directory. Throws, naming the path, when the
 * directory does not resolve to its own path, or when an entry is a symlink
 * or neither a file nor a directory, so a listing never drops such an entry.
 */
function readDirectory(root, relativePath) {
  assertRepositoryPath(root, relativePath);
  const entries = readdirSync(join(root, relativePath), { withFileTypes: true });
  const odd = entries.find((entry) => !entry.isFile() && !entry.isDirectory());
  if (odd !== undefined) {
    const oddPath = relativePath + '/' + odd.name;
    throw new Error(oddPath + ' is ' + ENTRY_KIND_TEXT[readEntryKind(root, oddPath)] + '. ' + BUILD_INPUT_RULE);
  }
  return entries;
}

export function discoverWorkflowIds(root) {
  return readDirectory(root, SOURCE_DIR)
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

/**
 * Returns the paths of the modules of plugin/workflow-src/<id>/: its .js
 * entries other than NON_MODULE_FILES, in name order. readSource fails the
 * build on one that is not a regular file, so none drops out.
 */
export function listModulePaths(root, id) {
  return readDirectory(root, SOURCE_DIR + '/' + id)
    .filter((entry) => entry.name.endsWith('.js') && !NON_MODULE_FILES.includes(entry.name))
    .map((entry) => entry.name)
    .sort()
    .map((name) => SOURCE_DIR + '/' + id + '/' + name);
}

/**
 * Returns the source paths of the built script of id, in build order:
 * meta.js, the data files, the libraries, the modules and main.js.
 */
export function listSourcePaths(root, id) {
  return [
    SOURCE_DIR + '/' + id + '/meta.js',
    ...DATA_CONSTANTS.map((constant) => constant.path),
    ...LIB_FILES.map((file) => SOURCE_DIR + '/lib/' + file),
    ...listModulePaths(root, id),
    SOURCE_DIR + '/' + id + '/main.js'
  ];
}

function renderBanner(root, id) {
  const sourceLines = listSourcePaths(root, id).map((path) => ' *   ' + path);
  return [
    '/*',
    ' * GENERATED by tools/build_workflows.mjs from:',
    ...sourceLines,
    ' * Do not edit by hand. Rebuild with `' + REBUILD_COMMAND + '`.',
    ' */'
  ].join('\n');
}

function renderDataConstant(root, constant) {
  const data = readDataConstant(root, constant.name);
  return 'const ' + constant.name + ' = ' + JSON.stringify(data, null, 1).replace(/^ +/gm, '') + ';';
}

const SCRIPT_PARSE_OPTIONS = Object.freeze({ ecmaVersion: 'latest', sourceType: 'script', allowReturnOutsideFunction: true, allowAwaitOutsideFunction: true });
const SOURCE_PARSE_OPTIONS = Object.freeze({
  script: SCRIPT_PARSE_OPTIONS,
  module: Object.freeze({ ecmaVersion: 'latest', sourceType: 'module' })
});
const BUILT_SCRIPT_PARSE_OPTIONS = Object.freeze({ ...SCRIPT_PARSE_OPTIONS, allowImportExportEverywhere: true });
const TEMPLATE_TOKEN_TYPES = Object.freeze([tokTypes.template, tokTypes.invalidTemplate]);
const POSITION_FIELDS = Object.freeze(['start', 'end', 'loc', 'range']);
const LINE_TERMINATOR = /[\n\u2028\u2029]/;
const WORD_CHARACTER = /[\w$\\\u0080-\uffff]/;
const MERGING_BOUNDARIES = Object.freeze(['++', '--', '//', '/*', '<!', '->']);
const STRIPPING_STEP = Object.freeze({ name: 'comment stripping', input: 'the original source', output: 'the stripped source' });
const COMPACTION_STEP = Object.freeze({ name: 'compaction', input: 'the stripped source', output: 'the compacted code' });

/**
 * Returns {source, ast, tokens, comments} for source parsed by acorn with
 * options: the syntax tree, every token but the end of input, and every
 * comment. Throws acorn's error when source does not parse.
 */
function parseJavaScript(source, options) {
  const tokens = [];
  const comments = [];
  const ast = parse(source, { ...options, onToken: tokens, onComment: comments });
  return { source: source, ast: ast, tokens: tokens.filter((token) => token.type !== tokTypes.eof), comments: comments };
}

/**
 * Returns parseJavaScript(source, options). Throws, naming relativePath,
 * when acorn cannot parse source.
 */
function parseNamedSource(relativePath, source, options) {
  try {
    return parseJavaScript(source, options);
  } catch (error) {
    throw new Error(relativePath + ': acorn cannot parse it: ' + error.message, { cause: error });
  }
}

function readSourceParseOptions(sourceType) {
  if (!Object.hasOwn(SOURCE_PARSE_OPTIONS, sourceType)) {
    throw new Error('unknown source type ' + JSON.stringify(sourceType) + '; expected script or module');
  }
  return SOURCE_PARSE_OPTIONS[sourceType];
}

/**
 * Returns the literal piece of the token at index of tokens, as an array of
 * none or one {kind, start, end}: a string, a regex, or one piece of a
 * template literal, from the backtick or the } that opens it to the
 * backtick or the ${ that closes it. acorn writes a template token for each
 * piece, between those two delimiter tokens, even when the piece is empty.
 */
function readLiteralPiece(tokens, index) {
  const token = tokens[index];
  if (token.type === tokTypes.string) {
    return [{ kind: 'string', start: token.start, end: token.end }];
  }
  if (token.type === tokTypes.regexp) {
    return [{ kind: 'regex', start: token.start, end: token.end }];
  }
  if (TEMPLATE_TOKEN_TYPES.includes(token.type)) {
    return [{ kind: 'template', start: tokens[index - 1].start, end: tokens[index + 1].end }];
  }
  return [];
}

/**
 * Returns {kind, start, end, text} for each string, regex and template
 * piece of parsed, in source order.
 */
function listLiteralPieces(parsed) {
  return parsed.tokens
    .flatMap((token, index) => readLiteralPiece(parsed.tokens, index))
    .map((piece) => ({ ...piece, text: parsed.source.slice(piece.start, piece.end) }));
}

/**
 * Returns segments of kind code, comment, string, template or regex whose
 * texts join back to the source of parsed. A comment segment carries
 * lineComment, true for a line comment.
 */
function listSourceSegments(parsed) {
  const comments = parsed.comments.map((comment) => ({ kind: 'comment', start: comment.start, end: comment.end, text: parsed.source.slice(comment.start, comment.end), lineComment: comment.type === 'Line' }));
  const marked = [...comments, ...listLiteralPieces(parsed)].sort((left, right) => left.start - right.start);
  const segments = [];
  let codeStart = 0;
  for (const piece of marked) {
    if (codeStart < piece.start) {
      segments.push({ kind: 'code', text: parsed.source.slice(codeStart, piece.start) });
    }
    segments.push(piece);
    codeStart = piece.end;
  }
  if (codeStart < parsed.source.length) {
    segments.push({ kind: 'code', text: parsed.source.slice(codeStart) });
  }
  return segments;
}

/**
 * Returns source with comments removed and string, template and regex
 * literals each replaced by "". source parses as a script.
 */
export function stripCommentsAndStrings(source) {
  return listSourceSegments(parseJavaScript(source, SCRIPT_PARSE_OPTIONS))
    .map((segment) => segment.kind === 'code' ? segment.text : segment.kind === 'comment' ? '' : '""')
    .join('');
}

function trimTrailingBlanks(writer) {
  let end = writer.text.length;
  while (end > writer.lineStart && (writer.text[end - 1] === ' ' || writer.text[end - 1] === '\t')) {
    end -= 1;
  }
  writer.text = writer.text.slice(0, end);
}

function isBlankCodeLine(writer) {
  return writer.lineInCode && /^[ \t]*$/.test(writer.text.slice(writer.lineStart));
}

function writeCodeNewline(writer) {
  if (writer.lineDirty && isBlankCodeLine(writer)) {
    writer.text = writer.text.slice(0, writer.lineStart);
    return;
  }
  writer.text += '\n';
  writer.lineStart = writer.text.length;
  writer.lineInCode = true;
  writer.lineDirty = false;
}

function writeCode(writer, text) {
  const lines = (writer.skipLeadingBlanks ? text.replace(/^[ \t]+/, '') : text).split('\n');
  writer.skipLeadingBlanks = false;
  lines.forEach((line, position) => {
    if (position > 0) {
      writeCodeNewline(writer);
    }
    writer.text += line;
  });
}

function writeLiteral(writer, text) {
  writer.skipLeadingBlanks = false;
  writer.text += text;
  const lastNewline = text.lastIndexOf('\n');
  if (lastNewline !== -1) {
    writer.lineStart = writer.text.length - text.length + lastNewline + 1;
    writer.lineInCode = false;
  }
}

function writeInlineCommentGap(writer, nextCharacter) {
  if (isBlankCodeLine(writer)) {
    writer.skipLeadingBlanks = true;
  } else if (nextCharacter === undefined || /\s/.test(nextCharacter)) {
    trimTrailingBlanks(writer);
  } else if (!/\s/.test(writer.text[writer.text.length - 1])) {
    writer.text += ' ';
  }
}

function writeRemovedComment(writer, comment, nextCharacter) {
  writer.lineDirty = true;
  if (comment.lineComment) {
    trimTrailingBlanks(writer);
  } else if (comment.text.includes('\n')) {
    trimTrailingBlanks(writer);
    writeCodeNewline(writer);
  } else {
    writeInlineCommentGap(writer, nextCharacter);
  }
}

function writeSegment(writer, segment, nextSegment) {
  if (segment.kind === 'code') {
    writeCode(writer, segment.text);
  } else if (segment.kind === 'comment') {
    writeRemovedComment(writer, segment, nextSegment === undefined ? undefined : nextSegment.text[0]);
  } else {
    writeLiteral(writer, segment.text);
  }
}

function writeStrippedSource(parsed) {
  const segments = listSourceSegments(parsed);
  const writer = { text: '', lineStart: 0, lineInCode: true, lineDirty: false, skipLeadingBlanks: false };
  segments.forEach((segment, position) => writeSegment(writer, segment, segments[position + 1]));
  return writer.text;
}

/**
 * Returns source with every comment removed and the bytes of every string,
 * template and regex literal unchanged. source parses as sourceType, script
 * or module, and acorn finds its comments and literals. A block comment
 * holding a newline becomes one newline, so automatic semicolon insertion
 * sees the same line breaks. Blanks before a removed comment that ends its
 * line are dropped, a line left blank by a removed comment is dropped, and
 * a line that starts with code keeps its start.
 */
export function stripComments(source, sourceType = 'script') {
  return writeStrippedSource(parseJavaScript(source, readSourceParseOptions(sourceType)));
}

/**
 * Returns true when left and right, two tokens of source, written with no
 * blank between them would read as other tokens: two word characters that
 * would read as one word, a regex whose flags would take a word, a number
 * that would take a dot, or a boundary of MERGING_BOUNDARIES, which would
 * read as ++, --, a comment, or the start of an HTML-like comment.
 */
function joinsIntoOtherTokens(source, left, right) {
  const lastCharacter = source[left.end - 1];
  const nextCharacter = source[right.start];
  if (WORD_CHARACTER.test(nextCharacter) && (WORD_CHARACTER.test(lastCharacter) || left.type === tokTypes.regexp)) {
    return true;
  }
  if (nextCharacter === '.' && left.type === tokTypes.num) {
    return true;
  }
  return MERGING_BOUNDARIES.includes(lastCharacter + nextCharacter);
}

function writeCompactionGap(parsed, index) {
  if (index === 0) {
    return '';
  }
  const left = parsed.tokens[index - 1];
  const right = parsed.tokens[index];
  const gap = parsed.source.slice(left.end, right.start);
  if (LINE_TERMINATOR.test(gap)) {
    return '\n';
  }
  return gap !== '' && joinsIntoOtherTokens(parsed.source, left, right) ? ' ' : '';
}

function writeCompactedTokens(parsed) {
  return parsed.tokens.map((token, index) => writeCompactionGap(parsed, index) + parsed.source.slice(token.start, token.end)).join('');
}

/**
 * Returns the tokens of source, which parses as a script, written with one
 * newline wherever source has one between two tokens, one space where two
 * tokens written together would read as other tokens (joinsIntoOtherTokens),
 * and nothing elsewhere. The bytes of every token, so of every string,
 * template and regex literal, are unchanged, and anything before the first
 * token or after the last is dropped.
 */
export function compactCode(source) {
  return writeCompactedTokens(parseJavaScript(source, SCRIPT_PARSE_OPTIONS));
}

/**
 * Returns the path of the first field where the syntax trees left and right
 * differ, or undefined when they are equal. Position fields are ignored, a
 * regex value is compared by its text, and every other field, raw text
 * included, must be equal.
 */
function findTreeDifference(left, right, path) {
  if (left instanceof RegExp || right instanceof RegExp) {
    return String(left) === String(right) ? undefined : path;
  }
  if (left === null || right === null || typeof left !== 'object' || typeof right !== 'object') {
    return Object.is(left, right) ? undefined : path;
  }
  if (Array.isArray(left) !== Array.isArray(right)) {
    return path;
  }
  const leftKeys = Object.keys(left).filter((key) => !POSITION_FIELDS.includes(key));
  const rightKeys = Object.keys(right).filter((key) => !POSITION_FIELDS.includes(key));
  if (leftKeys.join() !== rightKeys.join()) {
    return path;
  }
  for (const key of leftKeys) {
    const difference = findTreeDifference(left[key], right[key], path + (Array.isArray(left) ? '[' + key + ']' : '.' + key));
    if (difference !== undefined) {
      return difference;
    }
  }
  return undefined;
}

/**
 * Returns output parsed as a script. Throws, naming relativePath and step,
 * when output does not parse or parses to a syntax tree other than
 * expectedTree, the tree of the step's input.
 */
function parseEquivalentSource(relativePath, step, expectedTree, output) {
  let parsed;
  try {
    parsed = parseJavaScript(output, SCRIPT_PARSE_OPTIONS);
  } catch (error) {
    throw new Error(relativePath + ': ' + step.name + ' changed the code: ' + step.output + ' does not parse: ' + error.message, { cause: error });
  }
  const difference = findTreeDifference(expectedTree, parsed.ast, 'Program');
  if (difference !== undefined) {
    throw new Error(relativePath + ': ' + step.name + ' changed the code: ' + step.output + ' parses to a different syntax tree than ' + step.input + ', at ' + difference);
  }
  return parsed;
}

/**
 * Throws, naming relativePath, unless original and stripped, both scripts,
 * parse to equal syntax trees (findTreeDifference).
 */
export function assertStrippingPreserves(relativePath, original, stripped) {
  parseEquivalentSource(relativePath, STRIPPING_STEP, parseNamedSource(relativePath, original, SCRIPT_PARSE_OPTIONS).ast, stripped);
}

/**
 * Throws, naming relativePath, unless stripped and compacted, both scripts,
 * parse to equal syntax trees (findTreeDifference).
 */
export function assertCompactionPreserves(relativePath, stripped, compacted) {
  parseEquivalentSource(relativePath, COMPACTION_STEP, parseNamedSource(relativePath, stripped, SCRIPT_PARSE_OPTIONS).ast, compacted);
}

/**
 * Returns every node of the syntax tree under value, value included, in
 * walk order.
 */
function collectSyntaxNodes(value, nodes) {
  if (Array.isArray(value)) {
    value.forEach((item) => collectSyntaxNodes(item, nodes));
  } else if (value !== null && typeof value === 'object' && typeof value.type === 'string') {
    nodes.push(value);
    Object.values(value).forEach((child) => collectSyntaxNodes(child, nodes));
  }
  return nodes;
}

function isModuleLoad(node) {
  if (node.type === 'ImportDeclaration' || node.type === 'ImportExpression') {
    return true;
  }
  return node.type === 'CallExpression' && node.callee.type === 'Identifier' && node.callee.name === 'require';
}

function findDuplicateFunctions(ast) {
  const names = ast.body.filter((node) => node.type === 'FunctionDeclaration').map((node) => node.id.name);
  return names.filter((name, index) => names.indexOf(name) !== index);
}

function assertParses(id, output) {
  const body = output.replace(/^export const meta\b/, 'const meta');
  try {
    new vm.Script('(async function () {' + body + '\n})', { filename: builtPathFor(id) });
  } catch (error) {
    throw new Error(id + ': the built script does not parse: ' + error.message);
  }
}

function findLongestCombiningRun(line) {
  return [...line.matchAll(COMBINING_RUN_PATTERN)].reduce((longest, match) => Math.max(longest, [...match[0]].length), 0);
}

function assertPreviewLine(id, line, lineNumber) {
  if (line.length > MAX_BUILT_LINE_LENGTH) {
    throw new Error(id + ': line ' + lineNumber + ' of the built script is ' + line.length + ' characters, over the line budget of ' + MAX_BUILT_LINE_LENGTH + ' (the Workflow approval preview cuts a line over ' + WORKFLOW_PREVIEW_LINE_LIMIT + ')');
  }
  if (line.includes(PREVIEW_MARKER_TEXT)) {
    throw new Error(id + ': line ' + lineNumber + ' of the built script holds the text "' + PREVIEW_MARKER_TEXT + '", which the budget allows 0 times (the Workflow approval preview offers only "No" when its preview holds the truncation marker)');
  }
  const longestRun = findLongestCombiningRun(line);
  if (longestRun > WORKFLOW_PREVIEW_COMBINING_RUN_LIMIT) {
    throw new Error(id + ': line ' + lineNumber + ' of the built script has a run of ' + longestRun + ' combining or zero-width characters, over the budget of ' + WORKFLOW_PREVIEW_COMBINING_RUN_LIMIT + ' (the Workflow approval limit is a run of ' + WORKFLOW_PREVIEW_COMBINING_RUN_LIMIT + ')');
  }
}

/**
 * Throws when the lines of a built script would make the Claude Code
 * Workflow approval dialog offer only "No": see WORKFLOW_PREVIEW_LINE_LIMIT.
 */
function assertPreviewLines(id, lines) {
  lines.forEach((line, position) => assertPreviewLine(id, line, position + 1));
  const squares = lines.reduce((sum, line) => sum + line.length * line.length, 0);
  if (squares > MAX_BUILT_LINE_SQUARES) {
    throw new Error(id + ': the sum of the squared line lengths of the built script is ' + squares + ', over the budget of ' + MAX_BUILT_LINE_SQUARES + ' (the Workflow approval preview limit is ' + WORKFLOW_PREVIEW_SQUARES_LIMIT + ')');
  }
}

/**
 * Returns the built script output parsed by acorn as a script in which
 * import and export may appear, so meta's export parses and an import
 * shows as a node the import check finds. Throws, naming id, when it does
 * not parse.
 */
function parseBuiltScript(id, output) {
  try {
    return parseJavaScript(output, BUILT_SCRIPT_PARSE_OPTIONS);
  } catch (error) {
    throw new Error(id + ': the built script does not parse: ' + error.message, { cause: error });
  }
}

function assertBuiltScript(id, output, parsed) {
  if (!output.startsWith('export const meta = {')) {
    throw new Error(id + ': meta.js must start with `export const meta = {`');
  }
  if (output.length > MAX_BUILT_SCRIPT_LENGTH) {
    throw new Error(id + ': the built script is ' + output.length + ' characters, over the budget of ' + MAX_BUILT_SCRIPT_LENGTH + ' (the Workflow approval limit is ' + WORKFLOW_APPROVAL_LIMIT + ')');
  }
  assertPreviewLines(id, output.split('\n'));
  if (collectSyntaxNodes(parsed.ast, []).some(isModuleLoad)) {
    throw new Error(id + ': the built script uses import or require( as code; workflow scripts cannot load modules');
  }
  const duplicates = findDuplicateFunctions(parsed.ast);
  if (duplicates.length > 0) {
    throw new Error(id + ': top-level functions declared more than once: ' + duplicates.join(', '));
  }
  assertParses(id, output);
}

/**
 * PROSE_BUDGETS pins, for each workflow id, the most characters of string
 * and template literal tokens its built script may hold (P24). Each budget
 * is the script's measured count plus a margin of at most 1,000. Raising a
 * budget is a visible, reviewed change to this file, never a quiet edit to
 * make the build pass.
 */
export const PROSE_BUDGETS = Object.freeze({
  'analysis-only': 19000,
  'standard-delivery': 43000
});
const PROSE_PIECE_KINDS = Object.freeze(['string', 'template']);
const MIN_COPIED_SENTENCE_WORDS = 5;
const AGENT_DIR = 'plugin/agents';
const SKILL_DIR = 'plugin/skills';
const SKILL_FILE = 'SKILL.md';
const PROSE_LINE_MARKER = /^\s*(?:#+|[-*+>]|\d+\.)\s+/;
const PROSE_BLOCK_START = /^\s*(?:[-*+>]|\d+\.)\s/;
const PROSE_SINGLE_LINE = /^\s*(?:#+\s|\||```)/;

function listProsePieces(parsed) {
  return listLiteralPieces(parsed).filter((piece) => PROSE_PIECE_KINDS.includes(piece.kind));
}

/**
 * Returns the number of characters of the string and template literals of
 * source, a built script: the source text of each string literal and of
 * each template literal outside its substitutions, quotes, backticks, ${, }
 * and escapes included. parsed is source parsed as a built script.
 */
export function countProseCharacters(source, parsed = parseJavaScript(source, BUILT_SCRIPT_PARSE_OPTIONS)) {
  return listProsePieces(parsed).reduce((sum, piece) => sum + piece.text.length, 0);
}

const PROSE_TOKEN_TYPES = Object.freeze([tokTypes.string, ...TEMPLATE_TOKEN_TYPES]);

/**
 * Returns the text of each string literal and each template piece of
 * parsed, in source order, as acorn decodes it: every escape form read as
 * the character it stands for and a line continuation removed, with \r\n
 * and \r read as line breaks. A template piece with an invalid escape,
 * legal only in a tagged template, has no decoded text, so acorn gives its
 * source text.
 */
function readProseValues(parsed) {
  return parsed.tokens
    .filter((token) => PROSE_TOKEN_TYPES.includes(token.type))
    .map((token) => token.value.replace(/\r\n?/g, '\n'));
}

function appendProseLine(blocks, line) {
  if (line.trim() === '') {
    blocks.push('');
  } else if (PROSE_SINGLE_LINE.test(line)) {
    blocks.push(line.replace(PROSE_LINE_MARKER, ''), '');
  } else if (blocks.length === 0 || blocks[blocks.length - 1] === '' || PROSE_BLOCK_START.test(line)) {
    blocks.push(line.replace(PROSE_LINE_MARKER, ''));
  } else {
    blocks[blocks.length - 1] += ' ' + line;
  }
}

/**
 * Returns the sentences of text of at least MIN_COPIED_SENTENCE_WORDS words,
 * whitespace normalized to one space. A line joins the line before it unless
 * either is blank, it starts a list item or a quote, or either is a heading,
 * a table row or a fence. A heading, list or quote marker is dropped. Each
 * joined block is split after ., ! or ? followed by a blank.
 */
export function splitProseSentences(text) {
  const blocks = [];
  text.split('\n').forEach((line) => appendProseLine(blocks, line));
  return blocks
    .flatMap((block) => block.split(/(?<=[.!?])\s+/))
    .map((sentence) => sentence.replace(/\s+/g, ' ').trim())
    .filter((sentence) => sentence !== '' && sentence.split(' ').length >= MIN_COPIED_SENTENCE_WORDS);
}

/**
 * Returns the entries of the directory at relativePath, or none when there
 * is no entry by that name. Throws when the entry is not a directory, a
 * symlink included.
 */
function listDirectoryEntries(root, relativePath) {
  const kind = readEntryKind(root, relativePath);
  if (kind === 'missing') {
    return [];
  }
  if (kind !== 'directory') {
    throw new Error(relativePath + ' must be a directory, found kind ' + kind + '. The duplication check lists it to find every agent and skill file');
  }
  return readDirectory(root, relativePath);
}

/**
 * Returns, sorted, the path of every plugin/agents/*.md and
 * plugin/skills/<name>/SKILL.md, found by listing those two directories.
 * readSource fails the build on one that is not a regular file, so none
 * drops out of the comparison set.
 */
export function listPromptFiles(root) {
  const agentPaths = listDirectoryEntries(root, AGENT_DIR)
    .filter((entry) => entry.name.endsWith('.md'))
    .map((entry) => AGENT_DIR + '/' + entry.name);
  const skillPaths = listDirectoryEntries(root, SKILL_DIR)
    .filter((entry) => entry.isDirectory())
    .map((entry) => SKILL_DIR + '/' + entry.name + '/' + SKILL_FILE)
    .filter((path) => readEntryKind(root, path) !== 'missing');
  return [...agentPaths, ...skillPaths].sort();
}

/**
 * Returns {path, sentence} for each sentence of a string literal or a
 * template piece of source, a built script, read as acorn decodes it, that
 * equals a sentence of an agent or skill file (see listPromptFiles), in
 * literal order. parsed is source parsed as a built script. It is a
 * verbatim-copy tripwire: it reads each literal and each template piece on
 * its own, so a sentence split across literals or template pieces, or
 * reworded, passes it (ADR-0037, local review finding c5199443).
 */
export function findCopiedSentences(root, source, parsed = parseJavaScript(source, BUILT_SCRIPT_PARSE_OPTIONS)) {
  const contents = readProseValues(parsed);
  const promptFiles = listPromptFiles(root).map((path) => ({ path: path, sentences: new Set(splitProseSentences(readSource(root, path))) }));
  return contents.flatMap(splitProseSentences).flatMap((sentence) => promptFiles
    .filter((promptFile) => promptFile.sentences.has(sentence))
    .map((promptFile) => ({ path: promptFile.path, sentence: sentence })));
}

function assertProseBudget(id, output, parsed) {
  const count = countProseCharacters(output, parsed);
  if (!Object.hasOwn(PROSE_BUDGETS, id)) {
    throw new Error(id + ': the workflow has no prose budget. Add one to PROSE_BUDGETS in tools/build_workflows.mjs: its measured count of ' + count + ' plus a margin of at most 1000');
  }
  if (count > PROSE_BUDGETS[id]) {
    throw new Error(id + ': the built script holds ' + count + ' characters of string and template literals, over its prose budget of ' + PROSE_BUDGETS[id] + '. Move agent and skill rules into their own files (docs/engineering-principles.md P24); raising a budget is a reviewed change to PROSE_BUDGETS in tools/build_workflows.mjs');
  }
}

function assertNoCopiedSentences(root, id, output, parsed) {
  const copies = findCopiedSentences(root, output, parsed);
  if (copies.length > 0) {
    throw new Error(id + ': a literal of ' + builtPathFor(id) + ' repeats a sentence of ' + copies[0].path + ': ' + JSON.stringify(copies[0].sentence) + '. The build compares each literal sentence of at least ' + MIN_COPIED_SENTENCE_WORDS + ' words with every ' + AGENT_DIR + '/*.md and ' + SKILL_DIR + '/<name>/' + SKILL_FILE + '. Keep the rule in ' + copies[0].path + ' and pass only the task and the data (docs/engineering-principles.md P24)');
  }
}

/**
 * Returns meta.js, parsed as a module, with its comments stripped.
 */
function readStrippedMeta(root, relativePath) {
  return writeStrippedSource(parseNamedSource(relativePath, readSource(root, relativePath), SOURCE_PARSE_OPTIONS.module)).trim();
}

/**
 * Returns a library, a module or main.js, parsed as a script, with its
 * comments stripped, parsed. Throws, naming the file, unless the original
 * and the stripped source parse to equal syntax trees.
 */
function readStrippedCode(root, relativePath) {
  const original = parseNamedSource(relativePath, readSource(root, relativePath), SCRIPT_PARSE_OPTIONS);
  return parseEquivalentSource(relativePath, STRIPPING_STEP, original.ast, writeStrippedSource(original).trim());
}

/**
 * Returns the compacted code of stripped, a parsed stripped source. Throws,
 * naming the file, unless it parses to the syntax tree of stripped.
 */
function compactStrippedCode(relativePath, stripped) {
  const compacted = writeCompactedTokens(stripped);
  parseEquivalentSource(relativePath, COMPACTION_STEP, stripped.ast, compacted);
  return compacted;
}

/**
 * Returns a module, stripped and compacted. Throws, naming the file, when
 * a top-level node of its syntax tree is not a FunctionDeclaration.
 */
function readModuleSource(root, relativePath) {
  const stripped = readStrippedCode(root, relativePath);
  const statement = stripped.ast.body.find((node) => node.type !== 'FunctionDeclaration');
  if (statement !== undefined) {
    const statementLine = stripped.source.slice(statement.start, statement.end).split('\n')[0];
    throw new Error(relativePath + ': a module holds only function declarations at top level, but it holds ' + JSON.stringify(statementLine.slice(0, 80)) + '. Put every top-level const in main.js.');
  }
  return compactStrippedCode(relativePath, stripped);
}

function readCompactedSource(root, relativePath) {
  return compactStrippedCode(relativePath, readStrippedCode(root, relativePath));
}

export function buildWorkflow(root, id) {
  const parts = [
    readStrippedMeta(root, SOURCE_DIR + '/' + id + '/meta.js'),
    renderBanner(root, id),
    ...DATA_CONSTANTS.map((constant) => renderDataConstant(root, constant)),
    ...LIB_FILES.map((file) => readCompactedSource(root, SOURCE_DIR + '/lib/' + file)),
    ...listModulePaths(root, id).map((path) => readModuleSource(root, path)),
    readCompactedSource(root, SOURCE_DIR + '/' + id + '/main.js')
  ];
  const output = parts.join('\n\n') + '\n';
  const parsed = parseBuiltScript(id, output);
  assertBuiltScript(id, output, parsed);
  assertProseBudget(id, output, parsed);
  assertNoCopiedSentences(root, id, output, parsed);
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
  return entry.path + ' is ' + ENTRY_KIND_TEXT[entry.kind] + '. Every entry under ' + OUTPUT_DIR + '/ must be a regular file. Remove it, then rebuild with: ' + REBUILD_COMMAND;
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
  assertRepositoryPath(root, OUTPUT_DIR);
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
