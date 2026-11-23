import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const skillText = readFileSync(repoRoot + 'plugin/skills/route-workflow/SKILL.md', 'utf8').replace(/\r/g, '');
const overlordText = readFileSync(repoRoot + 'plugin/agents/overlord.md', 'utf8').replace(/\r/g, '');
const catalogIdsExpected = ['analysis-only', 'hatchery-dispatch', 'pr-feedback-remediation', 'standard-delivery'];
const outcomeStatuses = ['selected', 'ambiguous', 'blocked'];
const noFitSentence = 'A request that fits no catalog entry routes to `analysis-only` when it asks for no change to the repository, to `standard-delivery` when it asks for a change, and to `ambiguous` with those two candidates otherwise.';
const anyOtherStatusPhrase = '`blocked` or any other status, surface it as `blocked` and stop';

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

function listSubheadings(section) {
  const subheadings = [];
  for (const line of section.split('\n')) {
    const subheading = line.match(/^### `([^`]+)`$/);
    if (subheading) {
      subheadings.push(subheading[1]);
    }
  }
  return subheadings;
}

function listStatusValues(section) {
  return [...section.matchAll(/^status: (\S+)$/gm)].map((match) => match[1]);
}

function normalizeWhitespace(text) {
  return text.replace(/\s+/g, ' ');
}

const catalogEntries = parseCatalogEntries(readSection(skillText, '## Workflow Catalog'));

describe('route-workflow catalog', () => {
  test('catalog holds exactly the four routable workflows', () => {
    const catalogIds = catalogEntries.map((entry) => entry.id).sort();
    assert.deepEqual(catalogIds, catalogIdsExpected);
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

describe('route-workflow outcomes', () => {
  const outputsSection = readSection(skillText, '## Outputs');
  test('outputs are exactly selected, ambiguous and blocked', () => {
    assert.deepEqual(listSubheadings(outputsSection), outcomeStatuses);
  });
  test('every status value is a known outcome', () => {
    const statusValues = listStatusValues(outputsSection);
    assert.notEqual(statusValues.length, 0, 'outputs carry status values');
    for (const statusValue of statusValues) {
      assert.ok(outcomeStatuses.includes(statusValue), `status ${statusValue} is a known outcome`);
    }
  });
  test('skill holds the no-fit rule', () => {
    assert.ok(normalizeWhitespace(skillText).includes(noFitSentence));
  });
  test('skill names no exploratory path', () => {
    assert.doesNotMatch(skillText, /exploratory/i);
    assert.doesNotMatch(skillText, /§G/);
    assert.doesNotMatch(skillText, /escape-hatch/);
  });
});

describe('overlord routing outcome handling', () => {
  test('overlord names no exploratory path', () => {
    assert.doesNotMatch(overlordText, /exploratory/i);
  });
  test('overlord surfaces any other status as blocked', () => {
    assert.ok(overlordText.includes(anyOtherStatusPhrase));
  });
});
