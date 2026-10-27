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
 *   <id>/main.js last. The modules are the regular .js files of <id>/ other
 *   than meta.js, main.js and contract.js, in name order. contract.js is
 *   test data and is never bundled. listSourcePaths returns this order, and
 *   the banner names each source in it.
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
 *   is compacted by compactCode: leading indentation, trailing blanks, blank
 *   lines and every space or tab go, except one space between two word
 *   characters, between a regex literal and a word character, between a
 *   digit and a dot, and where the join would form another token (+ +, - -,
 *   a / before / or *, < before !--, -- before >). Every newline between
 *   code stays, so automatic semicolon insertion sees the same line breaks.
 *   meta.js, the banner, the data constants and the bytes of every string,
 *   template and regex literal are never compacted.
 *
 * Invariants
 *   CR is stripped from every input and the output is written with LF only.
 *   The built script starts with `export const meta`, has no import or
 *   require( outside comments and strings, declares each top-level function
 *   once, compiles as the body of an async function, and is at most
 *   MAX_BUILT_SCRIPT_LENGTH characters long, or the build throws, in both
 *   modes.
 *   The built script also keeps every line at most MAX_BUILT_LINE_LENGTH
 *   characters, keeps the sum of its squared line lengths at most
 *   MAX_BUILT_LINE_SQUARES, never contains the preview truncation marker
 *   text, and has no run of more than WORKFLOW_PREVIEW_COMBINING_RUN_LIMIT
 *   combining or zero-width characters, or the build throws, in both modes.
 *   Lengths are JavaScript string lengths of the lines split on LF, and an
 *   empty line counts 0.
 *   The compacted code of each library, module and main.js has the same
 *   literal tokens in the same order as its stripped source and the same
 *   code once all whitespace is removed, or the build throws naming the
 *   file, in both modes (assertCompactionPreserves).
 *   A module holds only function declarations at top level, or the build
 *   throws naming the file, in both modes. So every top-level const stays
 *   in main.js, which runs after every module, and the module order cannot
 *   change what runs.
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
 *   equivalence check proves it changed only whitespace.
 *   The title and description of each schema field are prose for the
 *   planner, and their home is plugin/references, which the planner reads
 *   (docs/engineering-principles.md P24), so the copy carries only the
 *   repository path mark the plan check reads.
 *   The overlord launches the committed scripts by path, so a symlink there
 *   could run content that --check never compared, and a write through one
 *   would change a file outside plugin/workflows/. Only regular files are
 *   allowed, and nothing else is followed.
 */
import { lstatSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

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

/**
 * Returns the paths of the modules of plugin/workflow-src/<id>/: its
 * regular .js files other than NON_MODULE_FILES, in name order.
 */
export function listModulePaths(root, id) {
  return readdirSync(join(root, SOURCE_DIR, id), { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.js') && !NON_MODULE_FILES.includes(entry.name))
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

const REGEX_AFTER_KEYWORDS = new Set(['return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void', 'throw', 'case', 'do', 'else', 'yield', 'await']);
const WORD_CHARACTER = /[\w$\u0080-￿]/;

function describeOffset(source, offset) {
  return 'line ' + (source.slice(0, offset).split('\n').length);
}

function findBlockCommentEnd(source, start) {
  const end = source.indexOf('*/', start + 2);
  if (end === -1) {
    throw new Error('unterminated block comment at ' + describeOffset(source, start));
  }
  return end + 2;
}

function findLineCommentEnd(source, start) {
  const end = source.indexOf('\n', start);
  return end === -1 ? source.length : end;
}

function findQuotedEnd(source, start) {
  const quote = source[start];
  let index = start + 1;
  while (index < source.length && source[index] !== '\n') {
    if (source[index] === quote) {
      return index + 1;
    }
    index += source[index] === '\\' ? 2 : 1;
  }
  throw new Error('unterminated string literal at ' + describeOffset(source, start));
}

/**
 * Scans one piece of a template literal that starts at start, on the opening
 * backtick or on the } that closes a substitution. Returns {end, opensSubstitution}:
 * the piece ends after the closing backtick or after the next ${.
 */
function findTemplatePieceEnd(source, start) {
  let index = start + 1;
  while (index < source.length) {
    if (source[index] === '\\') {
      index += 2;
    } else if (source[index] === '`') {
      return { end: index + 1, opensSubstitution: false };
    } else if (source[index] === '$' && source[index + 1] === '{') {
      return { end: index + 2, opensSubstitution: true };
    } else {
      index += 1;
    }
  }
  throw new Error('unterminated template literal at ' + describeOffset(source, start));
}

function findRegexEnd(source, start) {
  let index = start + 1;
  let inClass = false;
  while (index < source.length && source[index] !== '\n') {
    const character = source[index];
    if (character === '\\') {
      index += 2;
    } else if (character === '/' && !inClass) {
      index += 1;
      while (index < source.length && /[A-Za-z]/.test(source[index])) {
        index += 1;
      }
      return index;
    } else {
      if (character === '[' || character === ']') {
        inClass = character === '[';
      }
      index += 1;
    }
  }
  throw new Error('unterminated regex literal at ' + describeOffset(source, start));
}

function flushCode(lexer) {
  if (lexer.codeStart < lexer.index) {
    lexer.tokens.push({ kind: 'code', text: lexer.source.slice(lexer.codeStart, lexer.index) });
  }
}

function pushToken(lexer, kind, end) {
  flushCode(lexer);
  lexer.tokens.push({ kind: kind, text: lexer.source.slice(lexer.index, end) });
  lexer.index = end;
  lexer.codeStart = end;
}

function lexTemplatePiece(lexer) {
  const piece = findTemplatePieceEnd(lexer.source, lexer.index);
  pushToken(lexer, 'template', piece.end);
  if (piece.opensSubstitution) {
    lexer.braceStack.push('template');
  }
  lexer.regexAllowed = piece.opensSubstitution;
}

function lexSlash(lexer) {
  const next = lexer.source[lexer.index + 1];
  if (next === '/') {
    pushToken(lexer, 'comment', findLineCommentEnd(lexer.source, lexer.index));
  } else if (next === '*') {
    pushToken(lexer, 'comment', findBlockCommentEnd(lexer.source, lexer.index));
  } else if (lexer.regexAllowed) {
    pushToken(lexer, 'regex', findRegexEnd(lexer.source, lexer.index));
    lexer.regexAllowed = false;
  } else {
    lexer.index += 1;
    lexer.regexAllowed = true;
  }
}

function lexWord(lexer) {
  const start = lexer.index;
  while (lexer.index < lexer.source.length && WORD_CHARACTER.test(lexer.source[lexer.index])) {
    lexer.index += 1;
  }
  lexer.regexAllowed = REGEX_AFTER_KEYWORDS.has(lexer.source.slice(start, lexer.index));
}

function lexClosingBrace(lexer) {
  if (lexer.braceStack.pop() === 'template') {
    lexTemplatePiece(lexer);
    return;
  }
  lexer.index += 1;
  lexer.regexAllowed = true;
}

/**
 * INVARIANT: a regex literal never directly follows ++ or --. After the
 * postfix form a / is division, and after the prefix form the next token is
 * an operand, so ++ and -- are each read as one token that leaves
 * regexAllowed false. A third + or - after them is its own punctuator.
 */
function lexPunctuator(lexer, character) {
  if (character === '{') {
    lexer.braceStack.push('brace');
  }
  if ((character === '+' || character === '-') && lexer.source[lexer.index + 1] === character) {
    lexer.index += 2;
    lexer.regexAllowed = false;
    return;
  }
  lexer.index += 1;
  if (!/\s/.test(character)) {
    lexer.regexAllowed = character !== ')' && character !== ']';
  }
}

function lexNext(lexer) {
  const character = lexer.source[lexer.index];
  if (character === '/') {
    lexSlash(lexer);
  } else if (character === '\'' || character === '"') {
    pushToken(lexer, 'string', findQuotedEnd(lexer.source, lexer.index));
    lexer.regexAllowed = false;
  } else if (character === '`') {
    lexTemplatePiece(lexer);
  } else if (character === '}') {
    lexClosingBrace(lexer);
  } else if (WORD_CHARACTER.test(character)) {
    lexWord(lexer);
  } else {
    lexPunctuator(lexer, character);
  }
}

/**
 * Splits JavaScript source into tokens of kind code, comment, string,
 * template or regex, whose texts join back to source. A template literal
 * with substitutions is one template token per piece, with the code of each
 * substitution between them as code and comment tokens. A / starts a regex
 * literal at the start of source, after a punctuator other than ), ], ++
 * and --, and after the keywords in REGEX_AFTER_KEYWORDS; after any other
 * word, a literal, ++ or -- it is division. Throws on an unterminated
 * comment, string, template or regex literal.
 */
export function tokenizeSource(source) {
  const lexer = { source: source, index: 0, codeStart: 0, tokens: [], braceStack: [], regexAllowed: true };
  while (lexer.index < source.length) {
    lexNext(lexer);
  }
  if (lexer.braceStack.includes('template')) {
    throw new Error('unterminated template literal substitution at end of source');
  }
  flushCode(lexer);
  return lexer.tokens;
}

/**
 * Returns source with comments removed and string, template and regex
 * literals each replaced by "".
 */
export function stripCommentsAndStrings(source) {
  return tokenizeSource(source)
    .map((token) => token.kind === 'code' ? token.text : token.kind === 'comment' ? '' : '""')
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

function writeRemovedComment(writer, text, nextCharacter) {
  writer.lineDirty = true;
  if (text.startsWith('//')) {
    trimTrailingBlanks(writer);
  } else if (text.includes('\n')) {
    trimTrailingBlanks(writer);
    writeCodeNewline(writer);
  } else {
    writeInlineCommentGap(writer, nextCharacter);
  }
}

/**
 * Returns source with every comment removed and the bytes of every string,
 * template and regex literal unchanged. A block comment holding a newline
 * becomes one newline, so automatic semicolon insertion sees the same line
 * breaks. Blanks before a removed comment that ends its line are dropped, a
 * line left blank by a removed comment is dropped, and a line that starts
 * with code keeps its start.
 */
export function stripComments(source) {
  const tokens = tokenizeSource(source);
  const writer = { text: '', lineStart: 0, lineInCode: true, lineDirty: false, skipLeadingBlanks: false };
  tokens.forEach((token, position) => writeToken(writer, token, tokens[position + 1]));
  return writer.text;
}

function writeToken(writer, token, nextToken) {
  if (token.kind === 'code') {
    writeCode(writer, token.text);
  } else if (token.kind === 'comment') {
    writeRemovedComment(writer, token.text, nextToken === undefined ? undefined : nextToken.text[0]);
  } else {
    writeLiteral(writer, token.text);
  }
}

const COMPACTION_HAZARDS = Object.freeze(['++', '--', '//', '/*', '<!--', '-->']);

/**
 * Returns true when left and right, written with no blank between them,
 * would form a hazard of COMPACTION_HAZARDS that spans the join.
 */
function formsHazardAcrossJoin(left, right) {
  return COMPACTION_HAZARDS.some((hazard) => hazardSpansJoin(left, right, hazard));
}

function hazardSpansJoin(left, right, hazard) {
  const joined = left + right;
  for (let start = Math.max(0, left.length - hazard.length + 1); start < left.length; start += 1) {
    if (joined.startsWith(hazard, start)) {
      return true;
    }
  }
  return false;
}

function needsSeparator(compactor, nextText) {
  const lastCharacter = compactor.text[compactor.text.length - 1];
  const nextCharacter = nextText[0];
  if (lastCharacter === undefined || nextCharacter === undefined || lastCharacter === '\n') {
    return false;
  }
  if (WORD_CHARACTER.test(nextCharacter) && (WORD_CHARACTER.test(lastCharacter) || compactor.lastKind === 'regex')) {
    return true;
  }
  if (nextCharacter === '.' && /[0-9]/.test(lastCharacter)) {
    return true;
  }
  return formsHazardAcrossJoin(compactor.text.slice(-3), nextText.slice(0, 3));
}

function splitCompactionPieces(tokens) {
  return tokens.flatMap((token) => {
    if (token.kind !== 'code') {
      return [token];
    }
    return token.text.split(/(\s+)/).filter((text) => text !== '').map((text) => ({ kind: /^\s/.test(text) ? 'blank' : 'code', text: text }));
  });
}

function writeCompactedBlank(compactor, blank, nextPiece) {
  if (nextPiece === undefined || compactor.text === '') {
    return;
  }
  if (blank.includes('\n')) {
    if (!compactor.text.endsWith('\n')) {
      compactor.text += '\n';
    }
  } else if (needsSeparator(compactor, nextPiece.text)) {
    compactor.text += ' ';
  }
}

/**
 * Returns source with its code compacted and the bytes of every string,
 * template and regex literal unchanged. A run of blanks holding a newline
 * becomes one newline, so leading indentation, trailing blanks and blank
 * lines go, and automatic semicolon insertion sees the same line breaks. A
 * run of spaces or tabs is dropped, except that one space stays between two
 * word characters, between a regex literal and a word character, between a
 * digit and a dot, and where the join would form a hazard of
 * COMPACTION_HAZARDS, such as + +, - -, a / before / or *, or < before !--.
 */
export function compactCode(source) {
  const pieces = splitCompactionPieces(tokenizeSource(source));
  const compactor = { text: '', lastKind: undefined };
  pieces.forEach((piece, position) => writeCompactionPiece(compactor, piece, pieces[position + 1]));
  return compactor.text;
}

function writeCompactionPiece(compactor, piece, nextPiece) {
  if (piece.kind === 'blank') {
    writeCompactedBlank(compactor, piece.text, nextPiece);
    return;
  }
  compactor.text += piece.text;
  compactor.lastKind = piece.kind;
}

function listLiteralTexts(tokens) {
  return tokens.filter((token) => token.kind !== 'code').map((token) => token.kind + ' ' + token.text);
}

function joinCodeWithoutBlanks(tokens) {
  return tokens.map((token) => token.kind === 'code' ? token.text.replace(/\s+/g, '') : '\u0000').join('');
}

/**
 * Throws, naming relativePath, unless compacted has the same literal tokens
 * as original in the same order and the same code once all whitespace is
 * removed.
 */
export function assertCompactionPreserves(relativePath, original, compacted) {
  const originalTokens = tokenizeSource(original);
  const compactedTokens = tokenizeSource(compacted);
  const originalLiterals = listLiteralTexts(originalTokens);
  const compactedLiterals = listLiteralTexts(compactedTokens);
  const changedIndex = originalLiterals.findIndex((literal, index) => literal !== compactedLiterals[index]);
  if (changedIndex !== -1 || compactedLiterals.length !== originalLiterals.length) {
    const index = changedIndex === -1 ? originalLiterals.length : changedIndex;
    throw new Error(relativePath + ': compaction changed literal ' + (index + 1) + ' from ' + JSON.stringify(originalLiterals[index]) + ' to ' + JSON.stringify(compactedLiterals[index]));
  }
  if (joinCodeWithoutBlanks(originalTokens) !== joinCodeWithoutBlanks(compactedTokens)) {
    throw new Error(relativePath + ': compaction changed the code once all whitespace is removed');
  }
}

/**
 * Returns compactCode(source), after assertCompactionPreserves checks it.
 */
export function compactSource(relativePath, source) {
  const compacted = compactCode(source);
  assertCompactionPreserves(relativePath, source, compacted);
  return compacted;
}

const LEADING_BLANKS = /\s*/y;
const FUNCTION_DECLARATION_START = /(?:async\s+)?function\s*\*?\s*[A-Za-z_$][\w$]*\s*\(/y;

function skipBlanks(code, start) {
  LEADING_BLANKS.lastIndex = start;
  LEADING_BLANKS.test(code);
  return LEADING_BLANKS.lastIndex;
}

/**
 * Returns the index after the bracket that closes the one at start, or -1
 * when it never closes. code holds no comment or literal, so every bracket
 * in it is code.
 */
function skipBracketed(code, start) {
  let depth = 0;
  for (let index = start; index < code.length; index += 1) {
    if ('([{'.includes(code[index])) {
      depth += 1;
    } else if (')]}'.includes(code[index])) {
      depth -= 1;
      if (depth === 0) {
        return index + 1;
      }
    }
  }
  return -1;
}

/**
 * Returns the index after the function declaration that starts at start,
 * or -1 when no function declaration starts there.
 */
function findFunctionDeclarationEnd(code, start) {
  FUNCTION_DECLARATION_START.lastIndex = start;
  if (!FUNCTION_DECLARATION_START.test(code)) {
    return -1;
  }
  const paramsEnd = skipBracketed(code, FUNCTION_DECLARATION_START.lastIndex - 1);
  if (paramsEnd === -1) {
    return -1;
  }
  const bodyStart = skipBlanks(code, paramsEnd);
  return code[bodyStart] === '{' ? skipBracketed(code, bodyStart) : -1;
}

/**
 * Returns the first line of the first top-level statement of code that is
 * not a function declaration, or undefined when there is none. code holds
 * no comment or literal: see stripCommentsAndStrings.
 */
export function findTopLevelStatement(code) {
  let index = skipBlanks(code, 0);
  while (index < code.length) {
    const end = findFunctionDeclarationEnd(code, index);
    if (end === -1) {
      return code.slice(index).split('\n')[0];
    }
    index = skipBlanks(code, end);
  }
  return undefined;
}

function findDuplicateFunctions(source) {
  const names = [...source.matchAll(/^(?:async\s+)?function\s+([A-Za-z_$][\w$]*)/gm)].map((match) => match[1]);
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

function assertBuiltScript(id, output) {
  if (!output.startsWith('export const meta = {')) {
    throw new Error(id + ': meta.js must start with `export const meta = {`');
  }
  if (output.length > MAX_BUILT_SCRIPT_LENGTH) {
    throw new Error(id + ': the built script is ' + output.length + ' characters, over the budget of ' + MAX_BUILT_SCRIPT_LENGTH + ' (the Workflow approval limit is ' + WORKFLOW_APPROVAL_LIMIT + ')');
  }
  assertPreviewLines(id, output.split('\n'));
  const code = stripCommentsAndStrings(output);
  if (/\bimport\b/.test(code) || /\brequire\s*\(/.test(code)) {
    throw new Error(id + ': the built script uses import or require( as code; workflow scripts cannot load modules');
  }
  const duplicates = findDuplicateFunctions(output);
  if (duplicates.length > 0) {
    throw new Error(id + ': top-level functions declared more than once: ' + duplicates.join(', '));
  }
  assertParses(id, output);
}

function readStrippedSource(root, relativePath) {
  try {
    return stripComments(readSource(root, relativePath)).trim();
  } catch (error) {
    throw new Error(relativePath + ': ' + error.message);
  }
}

/**
 * Returns a module with its comments stripped. Throws, naming the file,
 * when it holds anything at top level other than function declarations.
 */
function readModuleSource(root, relativePath) {
  const stripped = readStrippedSource(root, relativePath);
  const statement = findTopLevelStatement(stripCommentsAndStrings(stripped));
  if (statement !== undefined) {
    throw new Error(relativePath + ': a module holds only function declarations at top level, but it holds ' + JSON.stringify(statement.slice(0, 80)) + '. Put every top-level const in main.js.');
  }
  return compactSource(relativePath, stripped);
}

function readCompactedSource(root, relativePath) {
  return compactSource(relativePath, readStrippedSource(root, relativePath));
}

export function buildWorkflow(root, id) {
  const parts = [
    readStrippedSource(root, SOURCE_DIR + '/' + id + '/meta.js'),
    renderBanner(root, id),
    ...DATA_CONSTANTS.map((constant) => renderDataConstant(root, constant)),
    ...LIB_FILES.map((file) => readCompactedSource(root, SOURCE_DIR + '/lib/' + file)),
    ...listModulePaths(root, id).map((path) => readModuleSource(root, path)),
    readCompactedSource(root, SOURCE_DIR + '/' + id + '/main.js')
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
