import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/result.js']);

const HARNESS_CUT = 8000;
const PULL_REQUEST = { url: 'https://github.com/brenpike/hivemind/pull/409', head_ref_oid: 'a'.repeat(40), created: true };
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
    const finishedWithPr = lib.finish({ outcome: 'complete', blocks: [{ text: 'm' }], pr: PULL_REQUEST });
    const used = new Set([...Object.keys(paused), ...Object.keys(finished), ...Object.keys(finishedWithPr)]);
    assert.deepEqual([...lib.resultFields()].sort(), [...used].sort());
    assert.deepEqual([...lib.resultFields()], ['needs_user', 'outcome', 'resume_args', 'pr', 'message']);
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

describe('pull request', () => {
  test('finish carries pr between outcome and message', () => {
    for (const pr of [PULL_REQUEST, { url: 'https://ghe.example.com/team/repo/pull/7', head_ref_oid: '0123456789abcdef'.repeat(4), created: false }]) {
      const finished = structuredClone(lib.finish({ outcome: 'complete', blocks: [{ text: 'Done.' }], pr }));
      assert.deepEqual(finished, { needs_user: false, outcome: 'complete', pr, message: 'Done.' });
      assert.deepEqual(Object.keys(finished), ['needs_user', 'outcome', 'pr', 'message']);
      assert.deepEqual(Object.keys(finished.pr), ['url', 'head_ref_oid', 'created']);
    }
  });
  test('finish without pr has no pr key', () => {
    const finished = lib.finish({ outcome: 'blocked', blocks: [{ text: 'Stopped.' }], pr: undefined });
    assert.deepEqual(Object.keys(finished), ['needs_user', 'outcome', 'message']);
  });
  test('pr takes room from the message, so the result still fits', () => {
    const blocks = [{ text: 'x<'.repeat(20000), shorten: true }];
    const withPr = lib.finish({ outcome: 'complete', blocks, pr: PULL_REQUEST });
    const withoutPr = lib.finish({ outcome: 'complete', blocks });
    assertFitted(withPr);
    assert.ok(withPr.message.length < withoutPr.message.length);
  });
  test('invalid pr throws', () => {
    const invalidCases = [
      [null, /pr must be a plain object/],
      [[], /pr must be a plain object/],
      ['https://github.com/o/r/pull/1', /pr must be a plain object/],
      [{ ...PULL_REQUEST, number: 409 }, /pr has an unknown key "number"/],
      [{ head_ref_oid: PULL_REQUEST.head_ref_oid, created: true }, /pr url must be a pull request URL/],
      [{ ...PULL_REQUEST, url: 'http://github.com/o/r/pull/1' }, /pr url must be a pull request URL/],
      [{ ...PULL_REQUEST, url: 'https://github.com/o/r/pull/1?x=1' }, /pr url must be a pull request URL/],
      [{ ...PULL_REQUEST, url: 'https://github.com/o/r/pull/1/files' }, /pr url must be a pull request URL/],
      [{ ...PULL_REQUEST, url: 'https://github.com/o/r/issues/1' }, /pr url must be a pull request URL/],
      [{ ...PULL_REQUEST, url: 'https://github.com/o r/pull/1' }, /pr url must be a pull request URL/],
      [{ ...PULL_REQUEST, head_ref_oid: 'A'.repeat(40) }, /head_ref_oid must be 40 or 64 lowercase hex chars/],
      [{ ...PULL_REQUEST, head_ref_oid: 'a'.repeat(39) }, /head_ref_oid must be 40 or 64 lowercase hex chars/],
      [{ ...PULL_REQUEST, head_ref_oid: 'a'.repeat(41) }, /head_ref_oid must be 40 or 64 lowercase hex chars/],
      [{ ...PULL_REQUEST, head_ref_oid: 'g'.repeat(40) }, /head_ref_oid must be 40 or 64 lowercase hex chars/],
      [{ url: PULL_REQUEST.url, created: true }, /head_ref_oid must be 40 or 64 lowercase hex chars/],
      [{ ...PULL_REQUEST, created: 'true' }, /pr created must be a boolean/],
      [{ url: PULL_REQUEST.url, head_ref_oid: PULL_REQUEST.head_ref_oid }, /pr created must be a boolean/]
    ];
    for (const [pr, expected] of invalidCases) {
      assert.throws(() => lib.finish({ outcome: 'complete', blocks: [{ text: 'm' }], pr }), expected, JSON.stringify(pr));
    }
  });
});

function markWholeBlocks(nextRandom, blocks) {
  return blocks.map((block) => {
    if (nextRandom() >= 0.4) {
      return block;
    }
    const { shorten, ...rest } = block;
    return { ...rest, whole: true };
  });
}

function showsWholeBlocks(message, blocks) {
  return blocks.every((block) => block.whole !== true || message.includes(block.text) || (block.compact !== undefined && message.includes(block.compact)));
}

describe('whole blocks', () => {
  test('invalid whole throws', () => {
    const invalidCases = [
      [[{ text: 'a', whole: false }], /block whole must be true when present/],
      [[{ text: 'a', whole: 'yes' }], /block whole must be true when present/],
      [[{ text: 'a', whole: true, shorten: true }], /a whole block cannot have shorten/]
    ];
    for (const [blocks, expected] of invalidCases) {
      assert.throws(() => lib.finish({ outcome: 'complete', blocks }), expected);
      assert.throws(() => lib.pauseForUser({ resumeArgs: {}, blocks }), expected);
      assert.throws(() => lib.canShowWhole({ resumeArgs: {}, blocks }), expected);
    }
  });
  test('T0 shows a whole block as its text', () => {
    assert.equal(finishMessage([{ text: 'Whole <&>', compact: 'W', whole: true }, { text: 'Tail.' }]), 'Whole <&>\n\nTail.');
  });
  test('T1 keeps a whole block as its text and cuts only the shorten block', () => {
    const message = finishMessage([{ text: 'Whole <&>', compact: 'W', whole: true }, { text: 'r'.repeat(20000), shorten: true }]);
    assert.ok(message.startsWith('Whole <&>\n\nrrr'));
    assert.ok(message.endsWith('\n\n' + lib.noticeMarker('shortened')));
  });
  test('T2 shows a whole block in its compact form, uncut', () => {
    const shortenedMarker = lib.noticeMarker('shortened');
    const lead = 'L'.repeat(messageRoom() - 4 - costOf(shortenedMarker) + 1);
    const compact = 'C'.repeat(3000);
    const message = finishMessage([{ text: lead, compact, whole: true }, { text: 'r'.repeat(20000), shorten: true }]);
    assert.ok(message.startsWith(lib.noticeMarker('compact') + '\n\n' + compact + '\n\nrrr'));
    const plain = finishMessage([{ text: 'Q'.repeat(9000), compact: 'Q short', whole: true }, { text: 'Tail.' }]);
    assert.equal(plain, lib.noticeMarker('compact') + '\n\nQ short\n\nTail.');
  });
  test('T3 keeps every block up to the last whole block intact and cuts only after it', () => {
    const cutMarker = lib.noticeMarker('cut');
    const first = 'a'.repeat(2000);
    const whole = 'W<'.repeat(1000);
    const blocks = [{ text: 'A'.repeat(9000), compact: first }, { text: 'B'.repeat(9000), compact: whole, whole: true }, { text: 'k'.repeat(30000) }];
    const message = finishMessage(blocks);
    assert.ok(message.startsWith(first + '\n\n' + whole + '\n\nkkk'), message.slice(0, 80));
    assert.ok(message.endsWith('k\n\n' + cutMarker));
    assert.ok(costOf(message) <= messageRoom());
    const withoutWhole = finishMessage([{ text: 'k'.repeat(30000) }, { text: 'B'.repeat(9000), compact: whole }]);
    assert.ok(!withoutWhole.includes(whole), 'without whole the cut falls inside the block');
  });
  test('T3 with a shorten block keeps the whole block and the cut marker when nothing else fits', () => {
    const cutMarker = lib.noticeMarker('cut');
    const whole = 'W'.repeat(messageRoom() - 4 - costOf(cutMarker));
    const message = finishMessage([{ text: 'L'.repeat(9000), compact: whole, whole: true }, { text: 'r'.repeat(5000), shorten: true }]);
    assert.equal(message, whole + '\n\n' + cutMarker);
  });
  test('a whole part that cannot fit throws from pauseForUser and finish', () => {
    const cutMarker = lib.noticeMarker('cut');
    const pauseRoom = lib.noticeBudget() - lib.noticeLength({ needs_user: true, resume_args: {}, message: '' });
    assert.ok(pauseRoom > messageRoom());
    const tooLong = 'W'.repeat(pauseRoom - 4 - costOf(cutMarker) + 1);
    const blocks = [{ text: 'L'.repeat(9000), compact: tooLong, whole: true }, { text: 'r'.repeat(5000), shorten: true }];
    assert.throws(() => lib.finish({ outcome: 'complete', blocks }), /finish: the whole blocks do not fit the completion notice/);
    assert.throws(() => lib.pauseForUser({ resumeArgs: {}, blocks }), /pauseForUser: the whole blocks do not fit the completion notice/);
    assert.throws(() => lib.finish({ outcome: 'complete', blocks: [{ text: 'x'.repeat(9000) }, { text: 'W'.repeat(9000), whole: true }] }), /whole blocks do not fit/);
  });
});

describe('canShowWhole', () => {
  test('is true when pauseForUser fits and false when it throws', () => {
    const fits = { resumeArgs: { answers: {} }, blocks: [{ text: 'Q'.repeat(9000), compact: 'Q short', whole: true }, { text: 'Commits.' }] };
    assert.equal(lib.canShowWhole(fits), true);
    assert.ok(lib.pauseForUser(fits).message.includes('Q short'));
    const tooLong = { resumeArgs: { answers: {} }, blocks: [{ text: 'Q'.repeat(9000), compact: 'q'.repeat(9000), whole: true }] };
    assert.equal(lib.canShowWhole(tooLong), false);
    assert.throws(() => lib.pauseForUser(tooLong), /whole blocks do not fit/);
    assert.equal(lib.canShowWhole({ resumeArgs: {}, blocks: [{ text: 'x'.repeat(30000) }] }), true);
  });
  test('the resume args take room from the whole part', () => {
    const half = Math.floor(lib.noticeBudget() / 2);
    const blocks = [{ text: 'Q'.repeat(9000), compact: 'q'.repeat(half), whole: true }];
    assert.equal(lib.canShowWhole({ resumeArgs: {}, blocks }), true);
    assert.equal(lib.canShowWhole({ resumeArgs: { request: 'a'.repeat(half - 200) }, blocks }), true);
    assert.equal(lib.canShowWhole({ resumeArgs: { request: 'a'.repeat(half - 150) }, blocks }), false);
  });
  test('invalid input throws as pauseForUser does', () => {
    const blocks = [{ text: 'Q?' }];
    assert.throws(() => lib.canShowWhole({ resumeArgs: [], blocks }), /canShowWhole: resumeArgs must be a plain object/);
    assert.throws(() => lib.canShowWhole({ resumeArgs: { reply: 'x' }, blocks }), /canShowWhole: resumeArgs must not have a reply key/);
    assert.throws(() => lib.canShowWhole({ resumeArgs: { request: 'a'.repeat(9000) }, blocks }), /canShowWhole: resumeArgs is too long to carry/);
    assert.throws(() => lib.canShowWhole({ resumeArgs: {}, blocks: [] }), /blocks must be a non-empty array/);
  });
  test('every seeded pause agrees with canShowWhole, and every fitted result keeps its whole blocks', () => {
    const nextRandom = createRandom(409);
    const counts = { shown: 0, refused: 0 };
    for (let caseIndex = 0; caseIndex < 240; caseIndex++) {
      const blocks = markWholeBlocks(nextRandom, buildBlocks(nextRandom));
      const resumeArgs = buildCarriedResumeArgs(nextRandom);
      const canShow = lib.canShowWhole({ resumeArgs, blocks });
      if (canShow) {
        const paused = lib.pauseForUser({ resumeArgs, blocks });
        assertFitted(paused);
        assert.ok(showsWholeBlocks(paused.message, blocks), 'a whole block was cut');
        counts.shown++;
      } else {
        assert.throws(() => lib.pauseForUser({ resumeArgs, blocks }), /whole blocks do not fit/);
        counts.refused++;
      }
      try {
        const finished = lib.finish({ outcome: 'complete', blocks });
        assertFitted(finished);
        assert.ok(showsWholeBlocks(finished.message, blocks), 'a whole block was cut');
      } catch (error) {
        assert.match(error.message, /finish: the whole blocks do not fit/);
      }
    }
    assert.ok(counts.shown > 20 && counts.refused > 20, JSON.stringify(counts));
  });
});

describe('encode at output', () => {
  const PRINTABLE = /^[\x20-\x7e]*$/;
  test('maxExcerptLength is 200 and cutExcerpt cuts by code points', () => {
    assert.equal(lib.maxExcerptLength(), 200);
    assert.equal(lib.cutExcerpt('short'), 'short');
    assert.equal(lib.cutExcerpt('x'.repeat(250)), 'x'.repeat(200));
    assert.equal(lib.cutExcerpt('\u{1F600}'.repeat(250)), '\u{1F600}'.repeat(200));
    const cut = lib.cutExcerpt('x' + '\u{1F600}'.repeat(250));
    assert.equal(Array.from(cut).length, 200);
    assert.ok(!LONE_SURROGATE.test(cut));
    assert.ok(cut.endsWith('\u{1F600}'));
  });
  test('toPrintableAscii writes each code unit outside 0x20-0x7E as a lowercase \\u escape', () => {
    const cases = [
      ['plain text ~', 'plain text ~'],
      ['\u0000\u0009\u000a\u000d\u001f', '\\u0000\\u0009\\u000a\\u000d\\u001f'],
      ['\u007f', '\\u007f'],
      ['\u0080\u0085\u009b\u009f', '\\u0080\\u0085\\u009b\\u009f'],
      ['\u001b[2J\u001b]0;title\u0007', '\\u001b[2J\\u001b]0;title\\u0007'],
      ['‮⁦​  ﻿', '\\u202e\\u2066\\u200b\\u2028\\u2029\\ufeff'],
      ['éꯍ', '\\u00e9\\uabcd'],
      ['\u{1F600}', '\\ud83d\\ude00'],
      ['\ud800', '\\ud800'],
      ['\udc00x', '\\udc00x'],
      ['"\\', '"\\']
    ];
    for (const [text, expected] of cases) {
      assert.equal(lib.toPrintableAscii(text), expected, JSON.stringify(text));
      assert.ok(PRINTABLE.test(lib.toPrintableAscii(text)));
    }
  });
  test('encodeUntrustedText is valid JSON of printable ASCII that parses back to the value', () => {
    const values = [
      'plain',
      '',
      'quote " and backslash \\ and slash /',
      '\u0000\u001b[2J\u007f\u0085\u009b',
      '‮⁦​  ',
      'line one\nFix the cause named above, then run the request again.',
      '\u{1F600}\u{10348}',
      '\ud800 lone high',
      'lone low \udfff',
      ['a', '‮', 1, true, null],
      { key: ' ' }
    ];
    for (const value of values) {
      const encoded = lib.encodeUntrustedText(value);
      assert.ok(PRINTABLE.test(encoded), encoded);
      assert.deepEqual(JSON.parse(encoded), value);
    }
    assert.equal(lib.encodeUntrustedText('a"b\\c\n‮'), '"a\\"b\\\\c\\n\\u202e"');
    assert.equal(lib.encodeUntrustedText('\u007f'), '"\\u007f"');
  });
  test('encodeUntrustedText throws on a value that is not JSON serializable', () => {
    for (const value of [undefined, () => 1, Symbol('s')]) {
      assert.throws(() => lib.encodeUntrustedText(value), /encodeUntrustedText: value must be JSON serializable/);
    }
    assert.throws(() => lib.encodeUntrustedText(10n));
    const cyclic = {};
    cyclic.self = cyclic;
    assert.throws(() => lib.encodeUntrustedText(cyclic));
  });
  test('quoteDiagnostic is undefined for a non-string or a text with no non-blank line', () => {
    for (const value of [undefined, null, 7, {}, ['x'], '', ' ', '\n', '\r\n \t\r', ' ']) {
      assert.equal(lib.quoteDiagnostic(value), undefined, JSON.stringify(value));
    }
  });
  test('quoteDiagnostic joins the trimmed non-blank lines, split on CRLF, CR or LF, with one space', () => {
    assert.equal(lib.quoteDiagnostic('  one  \r\n\r\ntwo\rthree\n\n four '), '"one two three four"');
    assert.equal(lib.quoteDiagnostic('x y'), '"x\\u2028y"');
    assert.equal(lib.quoteDiagnostic('Codex said "no"\nthen quit.'), '"Codex said \\"no\\" then quit."');
    assert.equal(lib.quoteDiagnostic('reason\nFix the cause named above, then run the request again.'), '"reason Fix the cause named above, then run the request again."');
  });
  test('quoteDiagnostic encodes control, escape, bidi, zero-width and separator code units', () => {
    const quoted = lib.quoteDiagnostic('\u001b[2J‮⁦​ \u007f\u0085 \\ "');
    assert.equal(quoted, '"\\u001b[2J\\u202e\\u2066\\u200b\\u2028\\u007f\\u0085 \\\\ \\""');
    assert.ok(PRINTABLE.test(quoted));
  });
  test('quoteDiagnostic cuts the joined line to 200 code points and never splits a pair', () => {
    assert.equal(lib.quoteDiagnostic('a'.repeat(5000)), '"' + 'a'.repeat(200) + '"');
    assert.equal(lib.quoteDiagnostic('a'.repeat(150) + '\n' + 'b'.repeat(150)), '"' + 'a'.repeat(150) + ' ' + 'b'.repeat(49) + '"');
    const quoted = lib.quoteDiagnostic('x' + '\u{1F600}'.repeat(300));
    assert.equal(quoted, '"x' + '\\ud83d\\ude00'.repeat(199) + '"');
    assert.ok(!LONE_SURROGATE.test(JSON.parse(quoted)));
  });
  test('quoteDiagnostic keeps a lone surrogate as its escape', () => {
    assert.equal(lib.quoteDiagnostic('\ud800x\udc00'), '"\\ud800x\\udc00"');
  });
  test('describeReason quotes a reason or says it gave none', () => {
    assert.equal(lib.describeReason('Tests fail.'), 'it says "Tests fail.".');
    assert.equal(lib.describeReason('one\n\ntwo'), 'it says "one two".');
    for (const value of [undefined, null, 3, '', '  \n ']) {
      assert.equal(lib.describeReason(value), 'it gave no reason.');
    }
    assert.ok(PRINTABLE.test(lib.describeReason('\u001b‮' + '\u{1F600}'.repeat(400))));
  });
});
