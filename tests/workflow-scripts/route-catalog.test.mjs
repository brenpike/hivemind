import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const skillText = readFileSync(repoRoot + 'plugin/skills/route-workflow/SKILL.md', 'utf8').replace(/\r/g, '');
const workflowsDir = repoRoot + 'plugin/workflows/';
const routerSkill = 'hivemind:route-workflow';

function readSection(text, heading) {
  const lines = text.split('\n');
  const start = lines.indexOf(heading);
  assert.notEqual(start, -1, `skill has the heading ${heading}`);
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => line.startsWith('## '));
  return (end === -1 ? rest : rest.slice(0, end)).join('\n');
}

function parseCatalogEntries(section) {
  const entries = [];
  for (const line of section.split('\n')) {
    const entry = line.match(/^- `([^`]+)`:(.*)$/);
    if (entry) {
      entries.push({ id: entry[1], purpose: entry[2].trim() });
    }
  }
  return entries;
}

function isRouterDefinition(definition) {
  const startState = definition.states?.[definition.start];
  return startState?.skill === routerSkill;
}

function listRoutableWorkflowIds() {
  const routableIds = [];
  for (const fileName of readdirSync(workflowsDir)) {
    if (!fileName.endsWith('.json')) {
      continue;
    }
    const definition = JSON.parse(readFileSync(workflowsDir + fileName, 'utf8'));
    if (!isRouterDefinition(definition)) {
      routableIds.push(fileName.slice(0, -'.json'.length));
    }
  }
  return routableIds.sort();
}

const catalogEntries = parseCatalogEntries(readSection(skillText, '## Workflow Catalog'));

describe('route-workflow catalog', () => {
  test('catalog ids equal the packaged workflow definitions minus the router', () => {
    const catalogIds = catalogEntries.map((entry) => entry.id).sort();
    assert.deepEqual(catalogIds, listRoutableWorkflowIds());
  });
  test('catalog lists each id once', () => {
    const catalogIds = catalogEntries.map((entry) => entry.id);
    assert.equal(new Set(catalogIds).size, catalogIds.length, `catalog ids are ${JSON.stringify(catalogIds)}`);
  });
  test('every catalog purpose is non-empty', () => {
    for (const entry of catalogEntries) {
      assert.notEqual(entry.purpose, '', `catalog entry ${entry.id} has a purpose`);
    }
  });
});

describe('route-workflow reads no workflow file', () => {
  test('skill has no pointer to the plugin workflows directory', () => {
    assert.equal(skillText.includes('${CLAUDE_PLUGIN_ROOT}/workflows/'), false);
  });
  test('skill does not ask the caller for available_workflows', () => {
    assert.equal(skillText.includes('available_workflows'), false);
  });
});
