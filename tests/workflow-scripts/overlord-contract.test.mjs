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
const cutNoticeParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('The harness may cut')) ?? '';

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
  test('Engine names the reply arg the resume adds to resume_args', () => {
    const replyName = resultLib.replyField();
    assert.ok(engineSection.includes('`resume_args` plus `' + replyName + '` set to the user\'s reply verbatim'), `${replyName} resume clause is missing from ## Engine`);
  });
  test('Engine no longer names the dropped answer_key field', () => {
    assert.ok(!engineSection.includes('answer_key'));
  });
  test('Engine ties the cut-notice trigger, the act-on-notice rule, the message-first rule, the show-as-held rule and never reading the file in one paragraph, in order', () => {
    const ruleSentences = [
      'The harness may cut the end of the result in the completion notice.',
      '`needs_user` and `resume_args` come before `message`, so act on them from the notice.',
      '`message` puts the questions and the decisions first, so a cut loses only the end of the report.',
      'When `message` is cut, show it as the notice holds it and say in one line that the full output is in the file the notice names.',
      'Never read that file.',
    ];
    let previousIndex = -1;
    for (const ruleSentence of ruleSentences) {
      const sentenceIndex = cutNoticeParagraph.indexOf(ruleSentence);
      assert.ok(sentenceIndex > previousIndex, `cut-notice paragraph lacks, or misorders, ${ruleSentence}`);
      previousIndex = sentenceIndex;
    }
  });
  test('Engine cut-notice rule does not stop the resume or fall back', () => {
    assert.notEqual(cutNoticeParagraph, '', '## Engine has a paragraph starting The harness may cut');
    for (const phrase of ['do not resume', 'fall back', 'state machine', 'with the Read tool', 'read the output file']) {
      assert.ok(!cutNoticeParagraph.includes(phrase), `cut-notice paragraph contains ${phrase}`);
    }
  });
  test('result puts needs_user and resume_args before message, and message last', () => {
    const pausedKeys = [...Object.keys(resultLib.pauseForUser({ message: 'Q?', resumeArgs: { request: 'R' }, decisions: [] }))];
    const finishedKeys = [...Object.keys(resultLib.finish({ outcome: 'complete', message: 'done', decisions: [] }))];
    for (const resultKeys of [pausedKeys, finishedKeys]) {
      assert.ok(resultKeys.indexOf('needs_user') < resultKeys.indexOf('message'), `keys are ${JSON.stringify(resultKeys)}`);
      assert.equal(resultKeys.at(-1), 'message', `keys are ${JSON.stringify(resultKeys)}`);
    }
    assert.ok(pausedKeys.indexOf('resume_args') < pausedKeys.indexOf('message'), `keys are ${JSON.stringify(pausedKeys)}`);
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
