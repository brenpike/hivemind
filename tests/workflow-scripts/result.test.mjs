import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/result.js']);

const HARNESS_CUT = 8000;
const LONE_SURROGATE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;
const ALPHABETS = {
  plain: 'abcdefghijklmnopqrstuvwxyz ABCDEFG 0123456789.,;:-',
  heavyEscape: '<>&"\\\n\t\r\u0001\u001f<<>>&&',
  astral: 'ab \u{1F600}\u{1F4A9}\u{10348}<&',
  mixed: 'abc def <tag> & "q" \\ \n\u00e9\u{1F600}\u0007'
};

function oracleNoticeLength(value) {
  return JSON.stringify(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').length;
}

function createRandom(seed) {
  let state = seed >>> 0;
  return function nextRandom() {
    state = (state + 0x6D2B79F5) >>> 0;
    let mixed = Math.imul(state ^ (state >>> 15), 1 | state);
    mixed = (mixed + Math.imul(mixed ^ (mixed >>> 7), 61 | mixed)) ^ mixed;
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 4294967296;
  };
}

function pickInteger(nextRandom, maxValue) {
  return Math.floor(nextRandom() * (maxValue + 1));
}

function buildText(nextRandom, alphabetName, codePointCount) {
  const codePoints = Array.from(ALPHABETS[alphabetName]);
  const parts = ['R'];
  for (let index = 0; index < codePointCount; index++) {
    parts.push(codePoints[pickInteger(nextRandom, codePoints.length - 1)]);
  }
  return parts.join('');
}

function pickAlphabet(nextRandom) {
  const names = Object.keys(ALPHABETS);
  return names[pickInteger(nextRandom, names.length - 1)];
}

function buildReportLength(nextRandom) {
  return Math.floor(Math.pow(nextRandom(), 3) * 100000);
}

function buildBlocks(nextRandom) {
  const blockCount = 1 + pickInteger(nextRandom, 2);
  const blocks = [];
  for (let blockIndex = 0; blockIndex < blockCount; blockIndex++) {
    const isLast = blockIndex === blockCount - 1;
    const textLength = isLast ? buildReportLength(nextRandom) : pickInteger(nextRandom, 2500);
    const block = { text: buildText(nextRandom, pickAlphabet(nextRandom), textLength) };
    if (nextRandom() < 0.5) {
      block.compact = buildText(nextRandom, pickAlphabet(nextRandom), pickInteger(nextRandom, 3000));
    }
    if (isLast && nextRandom() < 0.6) {
      block.shorten = true;
    }
    blocks.push(block);
  }
  return blocks;
}

function buildCarriedResumeArgs(nextRandom) {
  const codePoints = Array.from(buildText(nextRandom, pickAlphabet(nextRandom), pickInteger(nextRandom, 5000)));
  let keptCount = codePoints.length;
  while (!lib.canCarry({ request: codePoints.slice(0, keptCount).join(''), answers: { 'round-1': 'yes' } })) {
    keptCount = Math.floor(keptCount * 0.95);
  }
  return { request: codePoints.slice(0, keptCount).join(''), answers: { 'round-1': 'yes' } };
}

function emptyFinishLength() {
  return lib.noticeLength({ needs_user: false, outcome: 'complete', message: '' });
}

function messageRoom() {
  return lib.noticeBudget() - emptyFinishLength();
}

function costOf(text) {
  return lib.noticeLength(text) - 2;
}

function finishMessage(blocks) {
  return lib.finish({ outcome: 'complete', blocks }).message;
}

function assertFitted(result) {
  const plain = structuredClone(result);
  const oracleLength = oracleNoticeLength(plain);
  assert.ok(oracleLength <= lib.noticeBudget(), `notice length ${oracleLength} is over the budget`);
  assert.ok(oracleLength <= HARNESS_CUT, `notice length ${oracleLength} is over the harness cut`);
  assert.deepEqual(JSON.parse(JSON.stringify(plain)), plain);
  assert.equal(typeof plain.message, 'string');
  assert.notEqual(plain.message.trim(), '');
  assert.ok(!LONE_SURROGATE.test(plain.message), 'message has a lone surrogate');
}

describe('result contract', () => {
  test('pauseForUser returns the pause shape', () => {
    const resumeArgs = { request: 'R', answers: { 'round-1': 'earlier' } };
    const paused = structuredClone(lib.pauseForUser({ resumeArgs, blocks: [{ text: 'Q?' }] }));
    assert.deepEqual(paused, { needs_user: true, resume_args: resumeArgs, message: 'Q?' });
    assert.deepEqual(Object.keys(paused), ['needs_user', 'resume_args', 'message']);
  });
  test('finish returns the finish shape for both outcomes', () => {
    for (const outcome of ['complete', 'blocked']) {
      const finished = structuredClone(lib.finish({ outcome, blocks: [{ text: 'Done.' }] }));
      assert.deepEqual(finished, { needs_user: false, outcome, message: 'Done.' });
      assert.deepEqual(Object.keys(finished), ['needs_user', 'outcome', 'message']);
    }
  });
  test('resultFields covers exactly the fields both shapes use', () => {
    const paused = lib.pauseForUser({ resumeArgs: {}, blocks: [{ text: 'm' }] });
    const finished = lib.finish({ outcome: 'complete', blocks: [{ text: 'm' }] });
    const used = new Set([...Object.keys(paused), ...Object.keys(finished)]);
    assert.deepEqual([...lib.resultFields()].sort(), [...used].sort());
    assert.deepEqual([...lib.resultFields()], ['needs_user', 'outcome', 'resume_args', 'message']);
  });
  test('the reply goes under the args key reply, which is not a result field', () => {
    assert.equal(lib.replyField(), 'reply');
    assert.equal([...lib.resultFields()].includes(lib.replyField()), false);
  });
  test('a run pauses at most three times', () => {
    assert.equal(lib.pauseLimit(), 3);
    assert.deepEqual([0, 1, 2, 3, 4].map((count) => lib.canPause(count)), [true, true, true, false, false]);
    assert.throws(() => lib.canPause(-1), /non-negative integer/);
    assert.throws(() => lib.canPause('1'), /non-negative integer/);
  });
  test('invalid pause input throws', () => {
    const valid = { resumeArgs: { answers: {} }, blocks: [{ text: 'Q?' }] };
    assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs: [] }), /resumeArgs must be a plain object/);
    assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs: null }), /resumeArgs must be a plain object/);
    assert.throws(() => lib.pauseForUser({ ...valid, blocks: [{ text: ' ' }] }), /block text must be a non-empty string/);
  });
  test('resumeArgs with a reply key throws, so a stale reply can never be replayed', () => {
    const valid = { blocks: [{ text: 'Q?' }] };
    for (const reply of ['old reply', '', undefined, null]) {
      assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs: { answers: {}, reply } }), /must not have a reply key/);
    }
  });
  test('reply nested below the top level of resumeArgs is not the guarded key', () => {
    const resumeArgs = { answers: { reply: 'stored' } };
    const paused = lib.pauseForUser({ resumeArgs, blocks: [{ text: 'Q?' }] });
    assert.deepEqual(structuredClone(paused.resume_args), resumeArgs);
  });
  test('invalid finish input throws', () => {
    assert.throws(() => lib.finish({ outcome: 'paused', blocks: [{ text: 'm' }] }), /outcome must be complete or blocked/);
    assert.throws(() => lib.finish({ outcome: 'complete', blocks: [] }), /blocks must be a non-empty array/);
  });
  test('invalid blocks throw', () => {
    const invalidCases = [
      [undefined, /blocks must be a non-empty array/],
      ['text', /blocks must be a non-empty array/],
      [[null], /each block must be a plain object/],
      [[['text']], /each block must be a plain object/],
      [[{ text: 'a', extra: 1 }], /unknown key "extra"/],
      [[{ text: '' }], /block text must be a non-empty string/],
      [[{ text: 7 }], /block text must be a non-empty string/],
      [[{ text: 'a', compact: '' }], /block compact must be a non-empty string/],
      [[{ text: 'a', compact: undefined }], /block compact must be a non-empty string/],
      [[{ text: 'a', shorten: false }], /block shorten must be true when present/],
      [[{ text: 'a', shorten: true }, { text: 'b' }], /only the last block may have shorten/]
    ];
    for (const [blocks, expected] of invalidCases) {
      assert.throws(() => lib.finish({ outcome: 'complete', blocks }), expected);
      assert.throws(() => lib.pauseForUser({ resumeArgs: {}, blocks }), expected);
    }
  });
});

describe('notice size', () => {
  test('noticeBudget leaves a 256 char margin under the 8000 char harness cut', () => {
    assert.equal(lib.noticeBudget(), HARNESS_CUT - 256);
  });
  test('noticeLength equals an escape oracle', () => {
    const fixtures = [
      '', 'plain', 'a<b>c&d', '<<<>>>&&&', '"quoted"', 'back\\slash', 'line\nbreak\r\n', '\t\u0001\u001f\u007f',
      '\u{1F600}\u{1F4A9}', '\uD800 lone', 'caf\u00e9', 0, 12.5, true, null, [],
      { message: '<b> & "x"\n', nested: { list: ['\\', '\u{1F600}', '>'] } },
      { needs_user: true, resume_args: { request: 'a & b < c' }, message: '&amp;' }
    ];
    for (const fixture of fixtures) {
      assert.equal(lib.noticeLength(fixture), oracleNoticeLength(fixture), JSON.stringify(fixture));
    }
    assert.throws(() => lib.noticeLength(undefined), /JSON serializable/);
  });
  test('every seeded result fits the notice, round-trips and keeps surrogate pairs', () => {
    const nextRandom = createRandom(414);
    const tierCounts = { plain: 0, fitted: 0 };
    for (let caseIndex = 0; caseIndex < 240; caseIndex++) {
      const blocks = buildBlocks(nextRandom);
      const result = caseIndex % 2 === 0
        ? lib.pauseForUser({ resumeArgs: buildCarriedResumeArgs(nextRandom), blocks })
        : lib.finish({ outcome: nextRandom() < 0.5 ? 'complete' : 'blocked', blocks });
      assertFitted(result);
      const plainJoin = blocks.map((block) => block.text).join('\n\n');
      const plainResult = { ...structuredClone(result), message: plainJoin };
      if (oracleNoticeLength(plainResult) <= lib.noticeBudget()) {
        assert.equal(result.message, plainJoin);
        tierCounts.plain++;
      } else {
        assert.notEqual(result.message, plainJoin);
        tierCounts.fitted++;
      }
    }
    assert.ok(tierCounts.plain > 20 && tierCounts.fitted > 20, JSON.stringify(tierCounts));
  });
});

describe('fit tiers', () => {
  test('T0 joins block texts with blank lines and adds no marker', () => {
    const blocks = [{ text: 'Q1 <a> & b', compact: 'Q1' }, { text: 'Report.', shorten: true }];
    assert.equal(finishMessage(blocks), 'Q1 <a> & b\n\nReport.');
    assert.equal(finishMessage([{ text: 'Only.' }]), 'Only.');
  });
  test('T1 keeps earlier blocks verbatim and tail-cuts the shorten block to the room', () => {
    const blocks = [{ text: 'Questions <&>', compact: 'Q' }, { text: 'x&'.repeat(20000), shorten: true }];
    const message = finishMessage(blocks);
    const marker = lib.noticeMarker('shortened');
    assert.ok(message.startsWith('Questions <&>\n\nx&x&'));
    assert.ok(message.endsWith('\n\n' + marker));
    assert.ok(!message.includes(lib.noticeMarker('compact')));
    const cutReport = message.slice('Questions <&>\n\n'.length, -('\n\n' + marker).length);
    assert.ok(blocks[1].text.startsWith(cutReport));
    assert.ok(costOf(message) <= messageRoom());
    const longerMessage = 'Questions <&>\n\n' + blocks[1].text.slice(0, cutReport.length + 1) + '\n\n' + marker;
    assert.ok(costOf(longerMessage) > messageRoom(), 'the cut is not the longest that fits');
  });
  test('T1 is chosen even when no char of the shorten block fits', () => {
    const marker = lib.noticeMarker('shortened');
    const lead = 'L'.repeat(messageRoom() - 4 - costOf(marker));
    const message = finishMessage([{ text: lead, compact: 'short lead' }, { text: 'r'.repeat(5000), shorten: true }]);
    assert.equal(message, lead + '\n\n' + marker);
  });
  test('T2 is used only when T1 cannot fit, with the compact marker first', () => {
    const shortenedMarker = lib.noticeMarker('shortened');
    const compactMarker = lib.noticeMarker('compact');
    const lead = 'L'.repeat(messageRoom() - 4 - costOf(shortenedMarker) + 1);
    const report = 'r'.repeat(20000);
    const message = finishMessage([{ text: lead, compact: 'short lead' }, { text: report, shorten: true }]);
    assert.ok(message.startsWith(compactMarker + '\n\nshort lead\n\nrrr'));
    assert.ok(!message.includes(shortenedMarker));
    assert.equal(costOf(message), messageRoom());
  });
  test('T2 without a shorten block shows the compact forms, keeping text where there is none', () => {
    const message = finishMessage([{ text: 'Q'.repeat(9000), compact: 'Q short' }, { text: 'Tail.' }]);
    assert.equal(message, lib.noticeMarker('compact') + '\n\nQ short\n\nTail.');
  });
  test('T2 may leave the shorten block out when the compact forms fill the room', () => {
    const compactMarker = lib.noticeMarker('compact');
    const compact = 'c'.repeat(messageRoom() - 4 - costOf(compactMarker));
    const lead = 'L'.repeat(messageRoom());
    const message = finishMessage([{ text: lead, compact }, { text: 'report', shorten: true }]);
    assert.equal(message, compactMarker + '\n\n' + compact);
  });
  test('T3 cuts hard and puts the cut marker last', () => {
    const cutMarker = lib.noticeMarker('cut');
    const big = '<'.repeat(30000);
    const message = finishMessage([{ text: big }]);
    assert.ok(message.endsWith('\n\n' + cutMarker));
    assert.ok(message.startsWith('<<<'));
    assert.ok(costOf(message) <= messageRoom());
    const compactBig = 'k'.repeat(30000);
    const withShorten = finishMessage([{ text: big, compact: compactBig }, { text: 'report', shorten: true }]);
    assert.ok(withShorten.startsWith('kkk'));
    assert.ok(withShorten.endsWith('\n\n' + cutMarker));
    assert.ok(!withShorten.includes(lib.noticeMarker('compact')));
  });
  test('a cut never splits a surrogate pair', () => {
    for (let padding = 0; padding < 4; padding++) {
      const astral = 'p'.repeat(padding) + '\u{1F600}'.repeat(10000);
      for (const blocks of [[{ text: astral, shorten: true }], [{ text: astral }]]) {
        assertFitted(lib.finish({ outcome: 'complete', blocks }));
      }
    }
  });
  test('every marker names the completion notice and the per-agent results, never the output file', () => {
    for (const kind of ['shortened', 'compact', 'cut']) {
      const marker = lib.noticeMarker(kind);
      assert.match(marker, /shortened .*to fit the completion notice/);
      assert.match(marker, /The full text is in this run's per-agent results\./);
      assert.ok(!/output file/i.test(marker), marker);
      assert.match(marker, /^[\x20-\x7e]+$/);
    }
    assert.throws(() => lib.noticeMarker('other'), /unknown kind/);
  });
});

describe('canCarry', () => {
  test('is true at half the budget and false one char over', () => {
    const half = Math.floor(lib.noticeBudget() / 2);
    const baseLength = lib.noticeLength({ needs_user: true, resume_args: { request: '' }, message: '' });
    const atBoundary = { request: 'a'.repeat(half - baseLength) };
    const overBoundary = { request: 'a'.repeat(half - baseLength + 1) };
    assert.equal(lib.canCarry(atBoundary), true);
    assert.equal(lib.canCarry(overBoundary), false);
    assert.equal(lib.canCarry({ request: '<'.repeat(Math.floor((half - baseLength) / 4) + 1) }), false);
    assertFitted(lib.pauseForUser({ resumeArgs: atBoundary, blocks: [{ text: 'z'.repeat(9000), shorten: true }] }));
    assert.throws(() => lib.pauseForUser({ resumeArgs: overBoundary, blocks: [{ text: 'Q?' }] }), /too long to carry/);
  });
});
