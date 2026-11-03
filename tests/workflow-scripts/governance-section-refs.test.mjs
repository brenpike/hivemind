import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const GOVERNANCE_PATH_PREFIX = '${CLAUDE_PLUGIN_ROOT}/governance/';
const CITED_FILE_SUFFIXES = ['.md', '.json'];
const GOVERNANCE_CITATION = /\$\{CLAUDE_PLUGIN_ROOT\}\/(governance\/[A-Za-z0-9_.-]+\.md)`?\s+(?:\(([^()]*)\)|(whole)\b)/g;
const HEADING_LINE = /^#{1,6} (.+?)\s*$/;

/**
 * Lists each governance citation in the text: the doc path, with the
 * section names given in parentheses after it, or null when the doc is
 * loaded whole. A mention in any other form yields no citation, so the
 * caller compares the citation count with the mention count.
 */
function loadLineRefs(text) {
  const refs = [];
  for (const match of text.replace(/\r/g, '').matchAll(GOVERNANCE_CITATION)) {
    const [, docPath, list, whole] = match;
    if (whole !== undefined) {
      refs.push({ docPath, sections: null });
    } else {
      refs.push({ docPath, sections: list.split(',').map((name) => name.replace(/\s+/g, ' ').trim()).filter(Boolean) });
    }
  }
  return refs;
}

function countGovernanceMentions(text) {
  return text.split(GOVERNANCE_PATH_PREFIX).length - 1;
}

/**
 * Returns one problem string for each ref whose doc is missing, that
 * names an empty section list, or that names a section which is not the
 * exact text of exactly one heading of the doc.
 */
function loadRefProblems(refs, readDoc) {
  const problems = [];
  for (const { docPath, sections } of refs) {
    const text = readDoc(docPath);
    if (text === null) {
      problems.push(`${docPath} does not exist`);
      continue;
    }
    if (sections === null) continue;
    if (sections.length === 0) {
      problems.push(`${docPath} is named with an empty section list`);
      continue;
    }
    const headings = text.replace(/\r/g, '').split('\n')
      .map((line) => line.match(HEADING_LINE))
      .filter(Boolean)
      .map((headingMatch) => headingMatch[1]);
    for (const name of sections) {
      const matchCount = headings.filter((heading) => heading === name).length;
      if (matchCount === 0) problems.push(`${docPath} has no heading "${name}"`);
      if (matchCount > 1) problems.push(`${docPath} has ${matchCount} headings "${name}"`);
    }
  }
  return problems;
}

function readPluginDoc(docPath) {
  const full = repoRoot + 'plugin/' + docPath;
  return existsSync(full) ? readFileSync(full, 'utf8') : null;
}

function listCitingFiles(dirPath = 'plugin') {
  const filePaths = [];
  for (const entry of readdirSync(repoRoot + dirPath, { withFileTypes: true })) {
    const entryPath = dirPath + '/' + entry.name;
    if (entry.isDirectory()) {
      filePaths.push(...listCitingFiles(entryPath));
    } else if (CITED_FILE_SUFFIXES.some((suffix) => entry.name.endsWith(suffix))) {
      filePaths.push(entryPath);
    }
  }
  return filePaths.sort();
}

describe('every governance citation in a plugin Markdown or JSON file names a real doc and heading', () => {
  for (const filePath of listCitingFiles()) {
    const text = readFileSync(repoRoot + filePath, 'utf8').replace(/\r/g, '');
    const mentionCount = countGovernanceMentions(text);
    if (mentionCount === 0) continue;
    test(`${filePath}: each governance mention is a citation of an existing doc and heading`, () => {
      const refs = loadLineRefs(text);
      assert.equal(refs.length, mentionCount, `${filePath} names a governance path in a form the citation parser does not read`);
      assert.deepEqual(loadRefProblems(refs, readPluginDoc), [], `${filePath} cites a missing doc or heading`);
    });
  }
});

describe('the governance citation check reports missing docs and headings', () => {
  const docs = {
    'governance/a.md': '# A\n\n## First Rule\n\ntext\n\n### Nested Rule\n\n## Twice\n\n## Twice\n',
  };
  const readDoc = (docPath) => (docPath in docs ? docs[docPath] : null);
  test('a present doc whose named sections are all headings has no problem', () => {
    const refs = loadLineRefs('Load and follow: `${CLAUDE_PLUGIN_ROOT}/governance/a.md` (First Rule, Nested Rule).');
    assert.deepEqual(loadRefProblems(refs, readDoc), []);
  });
  test('a renamed heading is reported', () => {
    const refs = loadLineRefs('Load and follow: `${CLAUDE_PLUGIN_ROOT}/governance/a.md` (First Rules).');
    assert.deepEqual(loadRefProblems(refs, readDoc), ['governance/a.md has no heading "First Rules"']);
  });
  test('a missing doc is reported, whole or by section', () => {
    const refs = loadLineRefs('Load and follow: `${CLAUDE_PLUGIN_ROOT}/governance/b.md` whole, and `${CLAUDE_PLUGIN_ROOT}/governance/c.md` (Any).');
    assert.deepEqual(loadRefProblems(refs, readDoc), ['governance/b.md does not exist', 'governance/c.md does not exist']);
  });
  test('a doc named with no section list and not whole is not parsed as a citation', () => {
    const text = 'Load and follow: `${CLAUDE_PLUGIN_ROOT}/governance/a.md`.';
    assert.deepEqual(loadLineRefs(text), []);
    assert.equal(countGovernanceMentions(text), 1);
  });
  test('a citation wrapped over a line break is parsed', () => {
    const refs = loadLineRefs('per `${CLAUDE_PLUGIN_ROOT}/governance/a.md`\r\n(First Rule,\n Nested Rule).');
    assert.deepEqual(refs, [{ docPath: 'governance/a.md', sections: ['First Rule', 'Nested Rule'] }]);
    assert.deepEqual(loadRefProblems(refs, readDoc), []);
  });
  test('a JSON citation without backticks is parsed', () => {
    const refs = loadLineRefs('{"note": "see ${CLAUDE_PLUGIN_ROOT}/governance/a.md (First Rule)."}');
    assert.deepEqual(refs, [{ docPath: 'governance/a.md', sections: ['First Rule'] }]);
    assert.deepEqual(loadRefProblems(refs, readDoc), []);
  });
  test('a name matching two headings is reported', () => {
    const refs = loadLineRefs('per `${CLAUDE_PLUGIN_ROOT}/governance/a.md` (Twice).');
    assert.deepEqual(loadRefProblems(refs, readDoc), ['governance/a.md has 2 headings "Twice"']);
  });
  test('a name carrying # marks is reported', () => {
    const refs = loadLineRefs('per `${CLAUDE_PLUGIN_ROOT}/governance/a.md` (## First Rule).');
    assert.deepEqual(loadRefProblems(refs, readDoc), ['governance/a.md has no heading "## First Rule"']);
  });
});
