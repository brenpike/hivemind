import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const DOCTRINE_PATH = '${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md';
const LOAD_LINE_PREFIX = 'Load and follow: ';
const GOVERNANCE_PATH_PREFIX = '${CLAUDE_PLUGIN_ROOT}/governance/';
const WORKER_AGENT_PATHS = ['plugin/agents/drone.md', 'plugin/agents/changeling.md'];
const AGENT_SECTIONS = [
  { agentPath: 'plugin/agents/drone.md', remediationHeading: '## Review Remediation' },
  { agentPath: 'plugin/agents/overlord.md', remediationHeading: '## Review Remediation Posture' },
];

function readAgentText(agentPath) {
  return readFileSync(repoRoot + agentPath, 'utf8').replace(/\r/g, '');
}

function readLoadLine(text, agentPath) {
  const loadLines = text.split('\n').filter((line) => line.startsWith(LOAD_LINE_PREFIX));
  assert.equal(loadLines.length, 1, `${agentPath} has exactly one Load and follow line`);
  return loadLines[0];
}

function readSection(text, heading, agentPath) {
  const lines = text.split('\n');
  const start = lines.indexOf(heading);
  assert.notEqual(start, -1, `${agentPath} has the heading ${heading}`);
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => line.startsWith('## '));
  return (end === -1 ? rest : rest.slice(0, end)).join('\n');
}

describe('agents load the remediation doctrine only in their review-remediation section', () => {
  for (const { agentPath, remediationHeading } of AGENT_SECTIONS) {
    test(`${agentPath}: the Load and follow line does not name the doctrine`, () => {
      const loadLine = readLoadLine(readAgentText(agentPath), agentPath);
      assert.ok(!loadLine.includes('remediation-doctrine.md'), `${agentPath} loads the doctrine on every dispatch`);
    });
    test(`${agentPath}: ${remediationHeading} says to load and follow the doctrine`, () => {
      const section = readSection(readAgentText(agentPath), remediationHeading, agentPath);
      assert.ok(section.includes('load and follow `' + DOCTRINE_PATH + '`'), `${remediationHeading} does not load the doctrine`);
    });
  }
});

describe('worker agents load no governance doc whole on dispatch', () => {
  for (const agentPath of WORKER_AGENT_PATHS) {
    test(`${agentPath}: the Load and follow line names no governance path`, () => {
      const loadLine = readLoadLine(readAgentText(agentPath), agentPath);
      assert.ok(!loadLine.includes(GOVERNANCE_PATH_PREFIX), `${agentPath} loads a governance doc whole on every dispatch`);
    });
  }
});

const PLUGIN_ROOT_TOKEN = '${CLAUDE_PLUGIN_ROOT}/';
const GOVERNANCE_REF = /`\$\{CLAUDE_PLUGIN_ROOT\}\/(governance\/[^`]+)`( \(([^)]*)\)| whole)?/g;

/**
 * Lists each governance doc a Load and follow line names, with the
 * sections named in parentheses after it, or null when it loads the doc
 * whole. A doc named with neither form gets an empty section list, so the
 * caller reports it.
 */
function loadLineRefs(loadLine) {
  const refs = [];
  for (const match of loadLine.matchAll(GOVERNANCE_REF)) {
    const [, docPath, tail, list] = match;
    if (tail === ' whole') {
      refs.push({ docPath, sections: null });
    } else {
      refs.push({ docPath, sections: list === undefined ? [] : list.split(',').map((name) => name.trim()).filter(Boolean) });
    }
  }
  return refs;
}

/**
 * Returns one problem string for each ref whose doc is missing, that
 * names no section and is not loaded whole, or that names a section with
 * no heading of that exact text in the doc.
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
      problems.push(`${docPath} is named with no section list and is not loaded whole`);
      continue;
    }
    const headings = new Set(text.replace(/\r/g, '').split('\n')
      .map((line) => line.match(/^#{1,6} (.+?)\s*$/))
      .filter(Boolean)
      .map((m) => m[1]));
    for (const name of sections) {
      if (!headings.has(name)) problems.push(`${docPath} has no heading "${name}"`);
    }
  }
  return problems;
}

function readPluginDoc(docPath) {
  const full = repoRoot + 'plugin/' + docPath;
  return existsSync(full) ? readFileSync(full, 'utf8') : null;
}

describe('every governance section an agent Load and follow line names exists', () => {
  const agentPaths = readdirSync(repoRoot + 'plugin/agents')
    .filter((name) => name.endsWith('.md'))
    .map((name) => 'plugin/agents/' + name);
  for (const agentPath of agentPaths) {
    const text = readAgentText(agentPath);
    if (!text.split('\n').some((line) => line.startsWith(LOAD_LINE_PREFIX))) continue;
    test(`${agentPath}: each named governance doc exists and each named section is a heading in it`, () => {
      const loadLine = readLoadLine(text, agentPath);
      const refs = loadLineRefs(loadLine);
      const governanceMentions = loadLine.split(PLUGIN_ROOT_TOKEN + 'governance/').length - 1;
      assert.equal(refs.length, governanceMentions, `${agentPath} names a governance path the Load line parser does not read`);
      assert.deepEqual(loadRefProblems(refs, readPluginDoc), [], `${agentPath} Load line names a missing doc or section`);
    });
  }
});

describe('the Load line section check reports missing docs and headings', () => {
  const docs = {
    'governance/a.md': '# A\n\n## First Rule\n\ntext\n\n### Nested Rule\n',
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
  test('a doc named with no section list and not whole is reported', () => {
    const refs = loadLineRefs('Load and follow: `${CLAUDE_PLUGIN_ROOT}/governance/a.md`.');
    assert.deepEqual(loadRefProblems(refs, readDoc), ['governance/a.md is named with no section list and is not loaded whole']);
  });
});
