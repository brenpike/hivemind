import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
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
