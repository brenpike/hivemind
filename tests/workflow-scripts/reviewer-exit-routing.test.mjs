import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const loopSkillPath = 'plugin/skills/github-review-loop/SKILL.md';
const reviewerAgentPath = 'plugin/agents/github-reviewer.md';
const loopSkillText = readFileSync(repoRoot + loopSkillPath, 'utf8').replace(/\r/g, '');
const reviewerAgentText = readFileSync(repoRoot + reviewerAgentPath, 'utf8').replace(/\r/g, '');
const overlordText = readFileSync(repoRoot + 'plugin/agents/overlord.md', 'utf8').replace(/\r/g, '');
const LOOP_EXIT_SPAN = /`exit_reason` drawn from: `([^`]+)`/;
const REVIEWER_EXIT_LINE = /^exit_reason:\s*(.+)$/m;
const EXIT_TOKEN = /^[a-z]+(-[a-z]+)*$/;
const BACKTICKED_TOKEN = /`([a-z]+(?:-[a-z]+)*)`/g;
const ROUTED_PARAGRAPH_LEADS = [
  'Outside `## Instinct`,',
  '**Post-PR remediation.**',
  '**Reviewer questions.**',
  '**`merge_advised` terminal.**',
];
const ENDS_PARAGRAPH_LEAD = '**Reviewer exits.**';

function readSection(text, heading) {
  const lines = text.split('\n');
  const start = lines.indexOf(heading);
  assert.notEqual(start, -1, `heading ${heading} found`);
  const level = heading.match(/^#+/)[0].length;
  const end = lines.findIndex((line, index) => index > start && /^#+ /.test(line) && line.match(/^#+/)[0].length <= level);
  return lines.slice(start, end === -1 ? lines.length : end).join('\n');
}

/** Splits a pipe-separated exit_reason list into its trimmed tokens. */
function splitExitTokens(list) {
  return list.split('|').map((token) => token.trim()).filter((token) => token.length > 0);
}

/** Reads the github-review-loop exit_reason set from the span after "`exit_reason` drawn from: ". */
function readLoopExitTokens(text) {
  const match = text.match(LOOP_EXIT_SPAN);
  if (!match) throw new Error(`${loopSkillPath}: no "\`exit_reason\` drawn from: " span`);
  return splitExitTokens(match[1]);
}

/** Reads the github-reviewer fix-mode exit_reason set from the exit_reason line of its Output Contract. */
function readReviewerExitTokens(text) {
  const match = readSection(text, '## Output Contract').match(REVIEWER_EXIT_LINE);
  if (!match) throw new Error(`${reviewerAgentPath}: no exit_reason line in ## Output Contract`);
  return splitExitTokens(match[1]);
}

/** Returns the first blank-line-delimited paragraph starting with the lead, or throws naming the lead. */
function findParagraph(body, lead) {
  const paragraph = body.split(/\n[ \t]*\n/).map((block) => block.trim()).find((block) => block.startsWith(lead));
  if (paragraph === undefined) throw new Error(`overlord.md: no paragraph starting ${lead}`);
  return paragraph;
}

/** Lists the distinct backticked kebab-case tokens of the text. */
function extractBacktickedTokens(text) {
  return new Set([...text.matchAll(BACKTICKED_TOKEN)].map((match) => match[1]));
}

/** Maps each exit_reason token to the producers that emit it. */
function buildProducerTokens(producerSets) {
  const producerTokens = new Map();
  for (const [producer, tokens] of Object.entries(producerSets)) {
    for (const token of tokens) {
      producerTokens.set(token, [...(producerTokens.get(token) ?? []), producer]);
    }
  }
  return producerTokens;
}

/**
 * Checks the overlord body against the producer exit_reason tokens, a Map of
 * token to producer names. Returns one finding per problem: a token neither
 * routed nor ended, a token both routed and ended, or an ended token no
 * producer emits. Throws when a routed or ends paragraph is missing.
 */
function findUnhandledExits(body, producerTokens) {
  const routedTokens = new Set(ROUTED_PARAGRAPH_LEADS.flatMap((lead) => [...extractBacktickedTokens(findParagraph(body, lead))]));
  const endedTokens = extractBacktickedTokens(findParagraph(body, ENDS_PARAGRAPH_LEAD));
  const findings = [];
  for (const [token, producers] of producerTokens) {
    const routed = routedTokens.has(token);
    const ended = endedTokens.has(token);
    if (!routed && !ended) findings.push({ kind: 'unhandled', token, producers });
    if (routed && ended) findings.push({ kind: 'routed-and-ended', token, producers });
  }
  for (const token of endedTokens) {
    if (!producerTokens.has(token)) findings.push({ kind: 'ended-not-produced', token, producers: [] });
  }
  return findings;
}

/** Renders a finding as one line naming its token and producers. */
function describeFinding(finding) {
  const producers = finding.producers.length > 0 ? finding.producers.join(', ') : 'no producer';
  return `${finding.kind}: \`${finding.token}\` (${producers})`;
}

const producerSets = {
  [loopSkillPath]: readLoopExitTokens(loopSkillText),
  [reviewerAgentPath]: readReviewerExitTokens(reviewerAgentText),
};
const producerTokens = buildProducerTokens(producerSets);

describe('reviewer exit_reason producer sets', () => {
  for (const [producer, tokens] of Object.entries(producerSets)) {
    test(`${producer} lists two or more well-formed tokens including clean and blocked`, () => {
      assert.ok(tokens.length >= 2, `${producer} lists ${tokens.length} tokens`);
      for (const token of tokens) assert.match(token, EXIT_TOKEN, `${producer} token ${token} is kebab-case`);
      assert.ok(tokens.includes('clean'), `${producer} lists clean`);
      assert.ok(tokens.includes('blocked'), `${producer} lists blocked`);
    });
  }
});

describe('overlord routes or ends every reviewer exit_reason', () => {
  test('each routed paragraph and the ends paragraph is found', () => {
    for (const lead of [...ROUTED_PARAGRAPH_LEADS, ENDS_PARAGRAPH_LEAD]) {
      assert.doesNotThrow(() => findParagraph(overlordText, lead), `paragraph starting ${lead}`);
    }
  });

  test('every producer token is routed or ended, never both, and every ended token is produced', () => {
    const findings = findUnhandledExits(overlordText, producerTokens);
    assert.deepEqual(findings.map(describeFinding), []);
  });

  test('negative self-test: a token dropped from the ends paragraph is reported', () => {
    const endsParagraph = findParagraph(overlordText, ENDS_PARAGRAPH_LEAD);
    const droppedToken = [...extractBacktickedTokens(endsParagraph)].find((token) => producerTokens.has(token));
    assert.ok(droppedToken, 'the ends paragraph holds a producer token');
    const syntheticEnds = endsParagraph.replace('`' + droppedToken + '`', 'the dropped exit');
    const syntheticBody = overlordText.replace(endsParagraph, syntheticEnds);
    assert.notEqual(syntheticBody, overlordText, 'synthetic body differs');
    const findings = findUnhandledExits(syntheticBody, producerTokens);
    assert.deepEqual(findings, [{ kind: 'unhandled', token: droppedToken, producers: producerTokens.get(droppedToken) }]);
  });

  test('negative self-test: a missing ends paragraph throws', () => {
    const syntheticBody = overlordText.replace(ENDS_PARAGRAPH_LEAD, '**Reviewer endings.**');
    assert.throws(() => findUnhandledExits(syntheticBody, producerTokens), /no paragraph starting \*\*Reviewer exits\.\*\*/);
  });
});
