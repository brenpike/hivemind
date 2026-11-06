import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const DOCTRINE_PATH = '${CLAUDE_PLUGIN_ROOT}/governance/remediation-doctrine.md';
const LOAD_LINE_PREFIX = 'Load and follow: ';
const GOVERNANCE_PATH_PREFIX = '${CLAUDE_PLUGIN_ROOT}/governance/';
const WORKER_AGENT_PATHS = ['plugin/agents/drone.md', 'plugin/agents/changeling.md'];
const DOCTRINE_WHOLE_MARKER = 'remediation-doctrine.md` whole';
const REVIEWER_AGENT_PATHS = ['plugin/agents/local-reviewer.md', 'plugin/agents/github-reviewer.md'];
const AGENT_SECTIONS = [
  { agentPath: 'plugin/agents/drone.md', remediationHeading: '## Review Remediation', loadsWhole: false },
  { agentPath: 'plugin/agents/overlord.md', remediationHeading: '## Review Remediation Posture', loadsWhole: true },
];
const DEFINITIONS_PATH = 'plugin/governance/definitions.md';
const DEFINITIONS_CITATION = '`' + GOVERNANCE_PATH_PREFIX + 'definitions.md` (';
const BASH_DISCIPLINE_HEADING = 'Bash Command Discipline';
const DELETION_SCOPE_CLAIM = 'A worker deletes only paths in its assigned scope or created by its own task, in or out of the repo';
const DELETION_SCOPE_CONSUMERS = [
  { agentPath: 'plugin/agents/drone.md', heading: '## Coding Principles' },
  { agentPath: 'plugin/agents/changeling.md', heading: '## Design Rules' },
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

function lineCitesDefinitionsHeading(line, heading) {
  const citationStart = line.indexOf(DEFINITIONS_CITATION);
  if (citationStart === -1) return false;
  const listStart = citationStart + DEFINITIONS_CITATION.length;
  const listEnd = line.indexOf(')', listStart);
  if (listEnd === -1) return false;
  return line.slice(listStart, listEnd).split(', ').includes(heading);
}

function sectionCitesDefinitionsHeading(section, heading) {
  return section.split('\n').some((line) => lineCitesDefinitionsHeading(line, heading));
}

describe('agents load the remediation doctrine only in their review-remediation section', () => {
  for (const { agentPath, remediationHeading, loadsWhole } of AGENT_SECTIONS) {
    test(`${agentPath}: the Load and follow line does not name the doctrine`, () => {
      const loadLine = readLoadLine(readAgentText(agentPath), agentPath);
      assert.ok(!loadLine.includes('remediation-doctrine.md'), `${agentPath} loads the doctrine on every dispatch`);
    });
    if (loadsWhole) {
      test(`${agentPath}: ${remediationHeading} says to load and follow the doctrine whole`, () => {
        const section = readSection(readAgentText(agentPath), remediationHeading, agentPath);
        assert.ok(section.includes('load and follow `' + DOCTRINE_PATH + '` whole'), `${remediationHeading} does not load the doctrine whole`);
      });
    } else {
      test(`${agentPath}: ${remediationHeading} loads and follows the doctrine by a section list`, () => {
        const section = readSection(readAgentText(agentPath), remediationHeading, agentPath);
        assert.ok(section.includes('load and follow `' + DOCTRINE_PATH + '` ('), `${remediationHeading} does not load the doctrine by section`);
        assert.ok(!section.includes(DOCTRINE_WHOLE_MARKER), `${remediationHeading} loads the doctrine whole`);
      });
    }
  }
});

describe('reviewer agents load the remediation doctrine by section', () => {
  for (const agentPath of REVIEWER_AGENT_PATHS) {
    test(`${agentPath}: the Load and follow line cites the doctrine with a section list`, () => {
      const loadLine = readLoadLine(readAgentText(agentPath), agentPath);
      assert.ok(loadLine.includes('`' + DOCTRINE_PATH + '` ('), `${agentPath} does not load the doctrine by section`);
      assert.ok(!loadLine.includes(DOCTRINE_WHOLE_MARKER), `${agentPath} loads the doctrine whole`);
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

describe('worker agents follow the deletion-scope rule in Bash Command Discipline', () => {
  test(`${DEFINITIONS_PATH}: ## ${BASH_DISCIPLINE_HEADING} states the deletion-scope rule`, () => {
    const section = readSection(readAgentText(DEFINITIONS_PATH), '## ' + BASH_DISCIPLINE_HEADING, DEFINITIONS_PATH);
    assert.ok(section.includes(DELETION_SCOPE_CLAIM), `## ${BASH_DISCIPLINE_HEADING} does not state the deletion-scope rule`);
  });
  for (const { agentPath, heading } of DELETION_SCOPE_CONSUMERS) {
    test(`${agentPath}: ${heading} cites definitions.md (${BASH_DISCIPLINE_HEADING})`, () => {
      const section = readSection(readAgentText(agentPath), heading, agentPath);
      assert.ok(sectionCitesDefinitionsHeading(section, BASH_DISCIPLINE_HEADING), `${heading} does not cite definitions.md (${BASH_DISCIPLINE_HEADING})`);
    });
  }
});
