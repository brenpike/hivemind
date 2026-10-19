import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const overlordText = readFileSync(repoRoot + 'plugin/agents/overlord.md', 'utf8').replace(/\r/g, '');
const resultLib = loadLibs([repoRoot + 'plugin/workflow-src/lib/result.js']);

function splitFrontmatter(text) {
  const match = text.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  assert.ok(match, 'overlord.md has a YAML frontmatter block');
  return { frontmatter: match[1], body: match[2] };
}

function readToolNames(frontmatter) {
  const lines = frontmatter.split('\n');
  const start = lines.indexOf('tools:');
  assert.notEqual(start, -1, 'frontmatter has a tools: key');
  const toolNames = [];
  for (const line of lines.slice(start + 1)) {
    const item = line.match(/^\s+-\s+([A-Za-z]+)/);
    if (!item) {
      break;
    }
    toolNames.push(item[1]);
  }
  return toolNames;
}

function readSection(body, heading) {
  const lines = body.split('\n');
  const start = lines.indexOf(heading);
  assert.notEqual(start, -1, `body has the heading ${heading}`);
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => line.startsWith('## '));
  return (end === -1 ? rest : rest.slice(0, end)).join('\n');
}

const { frontmatter, body } = splitFrontmatter(overlordText);
const engineSection = readSection(body, '## Engine');
const defectParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('The result is built to fit the completion notice.')) ?? '';

describe('overlord frontmatter tools', () => {
  const toolNames = readToolNames(frontmatter);
  test('tools include Workflow', () => {
    assert.ok(toolNames.includes('Workflow'), `tools are ${JSON.stringify(toolNames)}`);
  });
  test('tools exclude Edit', () => {
    assert.equal(toolNames.includes('Edit'), false, `tools are ${JSON.stringify(toolNames)}`);
  });
});

describe('overlord Engine section', () => {
  test('the first H2 is Engine', () => {
    const firstHeading = body.split('\n').find((line) => line.startsWith('## '));
    assert.equal(firstHeading, '## Engine');
  });
  test('Engine comes after the opening paragraph and before the Load and follow line', () => {
    const paragraphs = body.trim().split('\n\n');
    assert.match(paragraphs[0], /^You are the control plane/);
    assert.equal(paragraphs[1], '## Engine');
    assert.ok(body.indexOf('## Engine') < body.indexOf('Load and follow: '));
  });
  test('Engine names hivemind:route-workflow', () => {
    assert.ok(engineSection.includes('`hivemind:route-workflow`'));
  });
  for (const fieldName of structuredClone(resultLib.resultFields())) {
    test(`Engine names the result field ${fieldName}`, () => {
      assert.match(engineSection, new RegExp('`[^`\\n]*\\b' + fieldName + '\\b[^`\\n]*`'), `${fieldName} is missing from ## Engine`);
    });
  }
  test('Engine resumes with the launch args, then resume_args, then the reply arg', () => {
    const replyName = resultLib.replyField();
    assert.ok(engineSection.includes('with args set to the launch args plus `resume_args` plus `' + replyName + '` set to the user\'s reply verbatim'), `${replyName} resume clause is missing from ## Engine`);
  });
  test('Engine no longer names the dropped answer_key field', () => {
    assert.ok(!engineSection.includes('answer_key'));
  });
  test('Engine no longer names the dropped decisions field', () => {
    assert.ok(!engineSection.includes('decisions'));
  });
  test('Engine treats a cut notice as a defect that does not resume, fall back or read a file', () => {
    assert.notEqual(defectParagraph, '', '## Engine has a paragraph starting The result is built to fit the completion notice.');
    for (const phrase of ['that is a defect', 'do not resume', 'fall back', 'read any file']) {
      assert.ok(defectParagraph.includes(phrase), `defect paragraph lacks ${phrase}`);
    }
  });
  test('Engine no longer carries the old cut-notice rule', () => {
    for (const phrase of ['come before `message`', 'Never read that file.']) {
      assert.ok(!engineSection.includes(phrase), `## Engine still contains ${phrase}`);
    }
  });
  test('Engine does not mention Bash', () => {
    const bashCount = (engineSection.match(/Bash/g) ?? []).length;
    assert.equal(bashCount, 0, '## Engine mentions Bash');
  });
  test('Engine states the fallback clause', () => {
    assert.ok(engineSection.includes('If the launch is refused or blocked'));
    assert.ok(engineSection.includes('say so in one line and run the request on the workflow state machine'));
    assert.ok(engineSection.includes('A run that started, then failed or ended blocked, is reported as it ended and does not fall back.'));
  });
});
