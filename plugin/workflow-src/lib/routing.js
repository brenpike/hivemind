/*
 * routing.js: reads the routing lines a committed script prints, as a runner
 * relays them in one text field.
 *
 * Inputs
 *   parseRoutingLines(text, spec)
 *     text  string. The relayed stdout of the script, which may hold other
 *           lines too.
 *     spec  plain object, a positive allowlist. Each own key is a routing
 *           key and maps to an entry:
 *             {pattern, required}  a value line. pattern is a RegExp the
 *                                  whole value must match. required is a
 *                                  boolean.
 *             {block, required}    a block line with no inline value,
 *                                  followed by its two-space indented
 *                                  lines. block is a spec of the same shape
 *                                  whose entries are value lines only.
 *           Every key matches routingKeyPattern(). A block spec may be
 *           empty; the top-level spec may be empty.
 *
 * Grammar
 *   Lines end in LF. The text may end in one LF, or in none. The empty text
 *   has no lines.
 *   A top-level routing line has no leading whitespace and is `key: value`,
 *   split at the first `: `, or `key:`, where key is an own key of the spec.
 *   A block opens at the first routing line of its block key. While it is
 *   open, a line of exactly two spaces then a non-space, in the same form,
 *   whose key is an own key of the block spec, is a routing line of the
 *   block. The block closes at the next top-level routing line that is
 *   read. A line that is not read closes no block.
 *   The first routing line of each key at its level is read. No other line
 *   is read: blank lines, prose, code fences, lines whose key is not in the
 *   spec, lines with the wrong indent, indented lines with no open block,
 *   and every later line of a key already read, top-level or in the block.
 *   A repeated block key opens no block and closes none.
 *
 * Outputs
 *   parseRoutingLines  {ok: true, values} when every line read is well
 *                      formed and every required key was read. values maps
 *                      each key read to its value string, and each block
 *                      key read to an object of its own values.
 *                      Otherwise {ok: false, problem, key} or
 *                      {ok: false, problem, line}:
 *                        missing    key: a required key has no routing
 *                                   line. A required key inside a block is
 *                                   named `block.key`.
 *                        malformed  line: the first routing line of a key
 *                                   holds a CR, or its value fails its
 *                                   pattern, or a block key has an inline
 *                                   value, or a value key has none.
 *                      line is the 1-based line number.
 *   routingProblems    every problem code, in no particular order.
 *   routingKeyPattern  the RegExp every key matches.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O.
 *   A pattern is always checked as a full match of the value, even when the
 *   spec RegExp has no anchors. Its g, y and m flags are dropped.
 *   A problem never echoes a value or a line. It names a spec key or a line
 *   number only.
 *   Only the first routing line of each key is read, and no other line
 *   causes a problem.
 *   A line that is not read changes nothing: the text without it gives the
 *   same result, apart from the line number of a problem.
 *   Lines are read top to bottom and the first line problem is returned.
 *   Missing keys are checked only when every line read is clean, top-level
 *   keys in spec order first, then the required keys of each block read.
 *   A spec key is looked up as an own property, so a line keyed constructor
 *   is not read unless the spec names it.
 *   An invalid spec, or text that is not a string, throws.
 *
 * Why
 *   A workflow cannot run a script itself. A runner runs it and relays its
 *   stdout, and the workflow must block when that relay lost or bent a
 *   routing line. But a runner's relay can hold lines the script never
 *   printed on stdout, such as the stderr of a command the script ran, and
 *   an agent may add its own: notes, code fences, blank lines and repeats.
 *   So only routing lines are read (issue 447). One generic parser checks
 *   every script's lines the same way. Each script's header stays the home
 *   of its own output contract, and the spec for it lands with the step
 *   that reads it.
 */

function routingProblems() {
  return ['missing', 'malformed'];
}

function routingKeyPattern() {
  return /^[a-z][a-z0-9_]*$/;
}

function parseRoutingLines(text, spec) {
  if (typeof text !== 'string') {
    throw new Error('parseRoutingLines: text must be a string');
  }
  const compiledSpec = compileRoutingSpec(spec, 'spec', true);
  const lines = splitRoutingText(text);
  const values = {};
  let openBlock = null;
  for (let index = 0; index < lines.length; index++) {
    const lineNumber = index + 1;
    const line = lines[index];
    const blockMatch = openBlock === null || !/^ {2}\S/.test(line) ? null : matchRoutingLine(line.slice(2), openBlock.entries);
    if (blockMatch !== null) {
      const blockProblem = Object.prototype.hasOwnProperty.call(openBlock.values, blockMatch.key) ? null : readFirstRoutingLine(blockMatch, openBlock.values);
      if (blockProblem !== null) {
        return routingLineProblem(blockProblem, lineNumber);
      }
      continue;
    }
    const topMatch = /^\S/.test(line) ? matchRoutingLine(line, compiledSpec) : null;
    if (topMatch === null || Object.prototype.hasOwnProperty.call(values, topMatch.key)) {
      continue;
    }
    const topProblem = readFirstRoutingLine(topMatch, values);
    if (topProblem !== null) {
      return routingLineProblem(topProblem, lineNumber);
    }
    openBlock = topMatch.entry.block === null ? null : { entries: topMatch.entry.block, values: values[topMatch.key] };
  }
  const missingKey = findMissingRoutingKey(compiledSpec, values);
  if (missingKey !== null) {
    return { ok: false, problem: 'missing', key: missingKey };
  }
  return { ok: true, values: values };
}

function splitRoutingText(text) {
  if (text === '') {
    return [];
  }
  const body = text.endsWith('\n') ? text.slice(0, -1) : text;
  return body.split('\n');
}

function matchRoutingLine(body, entries) {
  const parsed = splitRoutingLine(body);
  if (parsed === null || !entries.has(parsed.key)) {
    return null;
  }
  return { key: parsed.key, value: parsed.value, entry: entries.get(parsed.key) };
}

function splitRoutingLine(line) {
  const separatorIndex = line.indexOf(': ');
  if (separatorIndex >= 0) {
    return { key: line.slice(0, separatorIndex), value: line.slice(separatorIndex + 2) };
  }
  if (line.endsWith(':')) {
    return { key: line.slice(0, -1), value: null };
  }
  return null;
}

function readFirstRoutingLine(match, values) {
  if (match.entry.block !== null) {
    if (match.value !== null) {
      return 'malformed';
    }
    values[match.key] = {};
    return null;
  }
  if (match.value === null || match.value.includes('\r') || !match.entry.pattern.test(match.value)) {
    return 'malformed';
  }
  values[match.key] = match.value;
  return null;
}

function findMissingRoutingKey(compiledSpec, values) {
  for (const [key, entry] of compiledSpec) {
    if (entry.required && !Object.prototype.hasOwnProperty.call(values, key)) {
      return key;
    }
  }
  for (const [key, entry] of compiledSpec) {
    if (entry.block === null || !Object.prototype.hasOwnProperty.call(values, key)) {
      continue;
    }
    const missingInBlock = findMissingRoutingKey(entry.block, values[key]);
    if (missingInBlock !== null) {
      return key + '.' + missingInBlock;
    }
  }
  return null;
}

function routingLineProblem(problem, lineNumber) {
  return { ok: false, problem: problem, line: lineNumber };
}

function isRoutingRecord(value) {
  return Object.prototype.toString.call(value) === '[object Object]';
}

function compileRoutingSpec(spec, where, allowBlocks) {
  if (!isRoutingRecord(spec)) {
    throw new Error('parseRoutingLines: ' + where + ' must be a plain object');
  }
  const entries = new Map();
  for (const key of Object.keys(spec)) {
    if (!routingKeyPattern().test(key)) {
      throw new Error('parseRoutingLines: ' + where + ' has a key that is not a routing key: ' + JSON.stringify(key));
    }
    entries.set(key, compileRoutingEntry(spec[key], where + '.' + key, allowBlocks));
  }
  return entries;
}

function compileRoutingEntry(entry, where, allowBlocks) {
  if (!isRoutingRecord(entry)) {
    throw new Error('parseRoutingLines: ' + where + ' must be a plain object');
  }
  for (const field of Object.keys(entry)) {
    if (field !== 'pattern' && field !== 'block' && field !== 'required') {
      throw new Error('parseRoutingLines: ' + where + ' has an unknown field ' + JSON.stringify(field));
    }
  }
  if (typeof entry.required !== 'boolean') {
    throw new Error('parseRoutingLines: ' + where + '.required must be a boolean');
  }
  const hasPattern = Object.prototype.hasOwnProperty.call(entry, 'pattern');
  const hasBlock = Object.prototype.hasOwnProperty.call(entry, 'block');
  if (hasPattern === hasBlock) {
    throw new Error('parseRoutingLines: ' + where + ' must have exactly one of pattern and block');
  }
  if (hasBlock) {
    if (!allowBlocks) {
      throw new Error('parseRoutingLines: ' + where + ' is a block inside a block');
    }
    return { required: entry.required, pattern: null, block: compileRoutingSpec(entry.block, where + '.block', false) };
  }
  return { required: entry.required, pattern: anchorRoutingPattern(entry.pattern, where), block: null };
}

function anchorRoutingPattern(pattern, where) {
  if (Object.prototype.toString.call(pattern) !== '[object RegExp]') {
    throw new Error('parseRoutingLines: ' + where + '.pattern must be a RegExp');
  }
  const keptFlags = pattern.flags.replace(/[gym]/g, '');
  return new RegExp('^(?:' + pattern.source + ')$', keptFlags);
}
