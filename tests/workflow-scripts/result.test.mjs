import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/result.js']);

const HARNESS_CUT = 8000;
const FIX_LINE = 'Next: fix what stopped the run, then run the request again.';
const ANSWER_LINE = 'Next: run the request again with the answers in it.';
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
    const finishCases = [
      [{ outcome: 'complete', blocks: [{ text: 'Done.' }] }, 'Done.'],
      [{ outcome: 'blocked', causes: [{ problem: 'Stopped.' }] }, 'Stopped.\n\n' + FIX_LINE]
    ];
    for (const [input, message] of finishCases) {
      const finished = structuredClone(lib.finish(input));
      assert.deepEqual(finished, { needs_user: false, outcome: input.outcome, message });
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
  test('causes must be given exactly when the outcome is blocked', () => {
    const causesError = /^Error: finish: causes must be given exactly when outcome is blocked$/;
    assert.throws(() => lib.finish({ outcome: 'blocked', blocks: [{ text: 'Stopped.' }] }), causesError);
    assert.throws(() => lib.finish({ outcome: 'blocked' }), causesError);
    assert.throws(() => lib.finish({ outcome: 'complete', causes: [{ problem: 'P.' }], blocks: [{ text: 'Done.' }] }), causesError);
    assert.throws(() => lib.finish({ outcome: 'blocked', causes: [] }), /buildStopBlocks: causes must be a non-empty array/);
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
        : lib.finish(nextRandom() < 0.5 ? { outcome: 'complete', blocks } : { outcome: 'blocked', causes: [{ problem: 'Stopped.' }], blocks });
      assertFitted(result);
      const stopTexts = result.outcome === 'blocked' ? ['Stopped.', FIX_LINE] : [];
      const plainJoin = stopTexts.concat(blocks.map((block) => block.text)).join('\n\n');
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
    const finished = lib.finish({ outcome: 'blocked', causes: [{ problem: 'Stopped.' }], pr: undefined });
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
  test('maxExcerptLength is 200', () => {
    assert.equal(lib.maxExcerptLength(), 200);
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
  test('quoteDiagnostic cuts the joined line to 200 code points at a boundary, marks the cut and never splits a pair', () => {
    assert.equal(lib.quoteDiagnostic('a'.repeat(5000)), '"' + 'a'.repeat(200) + '" (cut)');
    assert.equal(lib.quoteDiagnostic('a'.repeat(150) + '\n' + 'b'.repeat(150)), '"' + 'a'.repeat(150) + '" (cut)');
    assert.equal(lib.quoteDiagnostic('One. ' + 'b'.repeat(250)), '"One." (cut)');
    const quoted = lib.quoteDiagnostic('x' + '\u{1F600}'.repeat(300));
    assert.equal(quoted, '"x' + '\\ud83d\\ude00'.repeat(199) + '" (cut)');
    assert.ok(!LONE_SURROGATE.test(JSON.parse(quoted.slice(0, -' (cut)'.length))));
  });
  test('quoteDiagnostic adds no cut mark when nothing was cut', () => {
    assert.equal(lib.quoteDiagnostic('a'.repeat(200)), '"' + 'a'.repeat(200) + '"');
    assert.equal(lib.quoteDiagnostic('a'.repeat(100) + '\n' + 'b'.repeat(99)), '"' + 'a'.repeat(100) + ' ' + 'b'.repeat(99) + '"');
    assert.equal(lib.quoteDiagnostic('\u{1F600}'.repeat(200)), '"' + '\\ud83d\\ude00'.repeat(200) + '"');
  });
  test('quoteDiagnostic takes an optional limit', () => {
    assert.equal(lib.quoteDiagnostic('one two three', 7), '"one two" (cut)');
    assert.equal(lib.quoteDiagnostic('one two three', 13), '"one two three"');
    assert.equal(lib.quoteDiagnostic('a'.repeat(300), 250), '"' + 'a'.repeat(250) + '" (cut)');
    assert.equal(lib.quoteDiagnostic('a'.repeat(300)), lib.quoteDiagnostic('a'.repeat(300), lib.maxExcerptLength()));
    assert.throws(() => lib.quoteDiagnostic('text', 0), /cutAtBoundary: limit must be a positive integer/);
  });
  test('quoteDiagnostic keeps a lone surrogate as its escape', () => {
    assert.equal(lib.quoteDiagnostic('\ud800x\udc00'), '"\\ud800x\\udc00"');
  });
  test('maxReasonLength is 600', () => {
    assert.equal(lib.maxReasonLength(), 600);
  });
  test('describeReason quotes a reason whole up to 600 code points', () => {
    const sentence = 'The step stopped here.';
    const reason = sentence + ' ' + 'x'.repeat(600 - sentence.length - 1);
    assert.equal(Array.from(reason).length, 600);
    assert.equal(lib.describeReason(reason), 'it says "' + reason + '".');
    assert.equal(lib.describeReason(reason + 'y'), 'it says "' + sentence + '" (cut).');
    assert.equal(lib.describeReason('w'.repeat(700)), 'it says "' + 'w'.repeat(600) + '" (cut).');
    assert.equal(lib.describeReason('\u{1F600}'.repeat(600)), 'it says "' + '\\ud83d\\ude00'.repeat(600) + '".');
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

describe('describeNoResult', () => {
  const agentFailed = 'The step\'s agent failed before it returned a result, as an agent API error such as an expired login, a rate limit or a network failure does.';
  test('a null result names the agent failure in one fixed sentence', () => {
    assert.equal(lib.describeNoResult(null), agentFailed);
    assert.match(lib.describeNoResult(null), /^[A-Z][^.]*\.$/);
    assert.match(lib.describeNoResult(null), /^[\x20-\x7e]+$/);
  });
  test('any other result gives the empty string', () => {
    for (const value of [undefined, {}, [], '', 'text', 0, false, { outcome: 'blocked' }]) {
      assert.equal(lib.describeNoResult(value), '', JSON.stringify(value));
    }
  });
});

describe('cutAtBoundary', () => {
  test('returns text unchanged when it has at most limit code points', () => {
    assert.equal(lib.cutAtBoundary('short', 5), 'short');
    assert.equal(lib.cutAtBoundary('', 3), '');
    assert.equal(lib.cutAtBoundary('\u{1F600}'.repeat(4), 4), '\u{1F600}'.repeat(4));
  });
  test('cuts right after the last sentence end within the limit', () => {
    assert.equal(lib.cutAtBoundary('One. Two! Three? Four five six', 20), 'One. Two! Three?');
    assert.equal(lib.cutAtBoundary('First part. Second part goes on', 12), 'First part.');
    assert.equal(lib.cutAtBoundary('Ends here.\nnext line', 11), 'Ends here.');
  });
  test('a sentence mark needs whitespace after it', () => {
    assert.equal(lib.cutAtBoundary('see v1.2 and more words', 12), 'see v1.2 and');
  });
  test('cuts before the last whitespace when there is no sentence end', () => {
    assert.equal(lib.cutAtBoundary('alpha beta gamma delta', 13), 'alpha beta');
    assert.equal(lib.cutAtBoundary('alpha beta gamma', 10), 'alpha beta');
    assert.equal(lib.cutAtBoundary('alpha   beta gamma', 9), 'alpha');
  });
  test('cuts hard at the limit when there is no boundary', () => {
    assert.equal(lib.cutAtBoundary('abcdefghij', 4), 'abcd');
    assert.equal(lib.cutAtBoundary(' abcdefghij', 4), ' abc');
  });
  test('counts code points and never splits a surrogate pair', () => {
    const smile = '\u{1F600}';
    assert.equal(lib.cutAtBoundary(smile.repeat(10), 3), smile.repeat(3));
    assert.equal(lib.cutAtBoundary('x' + smile.repeat(10), 4), 'x' + smile.repeat(3));
    assert.equal(lib.cutAtBoundary(smile + smile + ' ' + smile.repeat(5), 5), smile + smile);
    assert.equal(lib.cutAtBoundary(smile + '. ' + smile.repeat(5), 6), smile + '.');
    for (let limit = 1; limit < 12; limit += 1) {
      const cut = lib.cutAtBoundary('a' + smile + ' b' + smile + '. ' + smile.repeat(6), limit);
      assert.ok(!LONE_SURROGATE.test(cut), String(limit));
      assert.ok(Array.from(cut).length <= limit, String(limit));
    }
  });
  test('throws on a non-string text or a bad limit', () => {
    assert.throws(() => lib.cutAtBoundary(7, 3), /cutAtBoundary: text must be a string/);
    for (const limit of [0, -1, 1.5, '3', undefined]) {
      assert.throws(() => lib.cutAtBoundary('text', limit), /cutAtBoundary: limit must be a positive integer/);
    }
  });
});

describe('describeUnusableResult', () => {
  test('a null result gets the describeNoResult sentence once, run_again and the agentFailure mark', () => {
    const sentence = lib.describeNoResult(null);
    assert.deepEqual(structuredClone(lib.describeUnusableResult('P.', null)), { problem: 'P. ' + sentence, nextAction: 'run_again', agentFailure: true });
    assert.equal(lib.describeUnusableResult('P.', null).problem.split(sentence).length - 1, 1);
  });
  test('any other result gives the problem alone', () => {
    for (const result of [{}, undefined, 'x', 0]) {
      assert.deepEqual(structuredClone(lib.describeUnusableResult('P.', result)), { problem: 'P.' }, JSON.stringify(result));
    }
  });
});

describe('isTransientFailure', () => {
  test('each root cause of the Transient Failure definition is transient, in any case', () => {
    const transientTexts = [
      'remote: HTTP 503 from the server',
      'error: RPC failed; HTTP 500 curl 22 The requested URL returned error: 500',
      'HTTP/1.1 502 Bad Gateway',
      'gh: HTTP 429: rate limited',
      '429 Too Many Requests',
      '504 Gateway Time-out',
      'read tcp: connection reset by peer',
      'connect: Connection refused',
      'Software caused connection abort: connection aborted',
      'Error: ECONNRESET',
      'fatal: unable to access: Could not resolve host: github.com',
      'Temporary failure in name resolution',
      'getaddrinfo ENOTFOUND api.github.com',
      'TLS handshake timeout',
      'SSL handshake failed',
      'the command exited with code 124',
      'exit status 137',
      'connect: Network is unreachable',
      'ssh: connect to host github.com port 22: Connection timed out',
      'fatal: early EOF',
      'fatal: index-pack failed',
      'error: rpc FAILED'
    ];
    for (const text of transientTexts) {
      assert.equal(lib.isTransientFailure(text), true, text);
    }
  });
  test('any other text, a non-string or an empty text is not transient', () => {
    const otherTexts = [
      '',
      'fatal: not a git repository',
      'HTTP 404 Not Found',
      'HTTP 403 Forbidden',
      'error: pathspec did not match any file',
      'exit code 1',
      'exit code 1240',
      'the commit refused a dirty path',
      'malformed routing lines',
      'TLS handshake succeeded',
      'blocker: the branch is not the plan branch'
    ];
    for (const text of otherTexts) {
      assert.equal(lib.isTransientFailure(text), false, text);
    }
    for (const value of [undefined, null, 503, {}, ['HTTP 503']]) {
      assert.equal(lib.isTransientFailure(value), false, JSON.stringify(value));
    }
  });
});

describe('nextStepLine', () => {
  test('run_again says nothing in the repo needs a fix, anything else gives the fix line', () => {
    const runAgainLine = 'Next: nothing in the repo needs a fix, so run the request again later, for example once the machine is idle.';
    const fixLine = 'Next: fix what stopped the run, then run the request again.';
    assert.equal(lib.nextStepLine('run_again'), runAgainLine);
    for (const nextAction of ['fix_cause', undefined]) {
      assert.equal(lib.nextStepLine(nextAction), fixLine, String(nextAction));
    }
  });
  test('answer says to run the request again with the answers in it', () => {
    assert.equal(lib.nextStepLine('answer'), ANSWER_LINE);
  });
});

describe('buildStopBlocks', () => {
  const fixLine = 'Next: fix what stopped the run, then run the request again.';
  const runAgainLine = 'Next: nothing in the repo needs a fix, so run the request again later, for example once the machine is idle.';
  test('causes that need a fix lead with the fix line, then run_again causes, each in step order', () => {
    const causes = [
      { problem: 'A.', nextAction: 'run_again' },
      { problem: 'B.' },
      { problem: 'C.', nextAction: 'fix_cause' },
      { problem: 'D.', nextAction: 'run_again' }
    ];
    assert.deepEqual(structuredClone(lib.buildStopBlocks(causes)), [
      { text: 'B.' }, { text: fixLine, whole: true }, { text: 'C.' }, { text: 'A.' }, { text: 'D.' }
    ]);
  });
  test('the run_again line shows only when every cause is run_again', () => {
    const causes = [{ problem: 'A.', nextAction: 'run_again' }, { problem: 'B.', nextAction: 'run_again' }];
    assert.deepEqual(structuredClone(lib.buildStopBlocks(causes)), [
      { text: 'A.' }, { text: runAgainLine, whole: true }, { text: 'B.' }
    ]);
    assert.deepEqual(structuredClone(lib.buildStopBlocks([{ problem: 'A.', nextAction: 'fix_cause' }])), [
      { text: 'A.' }, { text: fixLine, whole: true }
    ]);
  });
  test('the lead has a compact form only when it is over maxBlockedLeadLength() code points', () => {
    assert.equal(lib.maxBlockedLeadLength(), 1000);
    const atLimit = 'x'.repeat(1000);
    assert.deepEqual(structuredClone(lib.buildStopBlocks([{ problem: atLimit }])[0]), { text: atLimit });
    const overLimit = 'word '.repeat(300).trim();
    assert.deepEqual(structuredClone(lib.buildStopBlocks([{ problem: overLimit }])[0]), { text: overLimit, compact: lib.cutAtBoundary(overLimit, 1000) });
    const laterBlock = lib.buildStopBlocks([{ problem: 'A.' }, { problem: overLimit }])[2];
    assert.deepEqual(structuredClone(laterBlock), { text: overLimit });
  });
  test('throws unless causes is a non-empty array', () => {
    for (const causes of [[], undefined, null, 'x', { problem: 'A.' }]) {
      assert.throws(() => lib.buildStopBlocks(causes), /buildStopBlocks: causes must be a non-empty array/, JSON.stringify(causes));
    }
  });
  test('a blocked finish over a 20,000-character costliest lead and two later causes keeps the Next line whole after the lead', () => {
    const words = 'The planner could not plan the delivery: ' + ('\u0001'.repeat(9) + ' ').repeat(2000);
    const unbroken = 'The planner could not plan the delivery: ' + '\u0001'.repeat(20000);
    const laterCauses = [{ problem: 'Later one: ' + '<&>'.repeat(3000) }, { problem: 'Later two: ' + '\u0001'.repeat(5000), nextAction: 'run_again' }];
    for (const lead of [words, unbroken]) {
      const result = lib.finish({ outcome: 'blocked', causes: [{ problem: lead }].concat(laterCauses) });
      const paragraphs = result.message.split('\n\n');
      const leadIndex = paragraphs.findIndex((paragraph) => paragraph.startsWith('The planner could not plan'));
      assert.equal(paragraphs[leadIndex], lib.cutAtBoundary(lead, lib.maxBlockedLeadLength()));
      assert.equal(paragraphs[leadIndex + 1], fixLine);
      assert.ok(lib.noticeLength(result) <= lib.noticeBudget());
    }
  });
});

describe('blocked finish', () => {
  test('a blocked finish with no blocks shows the stop blocks alone', () => {
    const finished = lib.finish({ outcome: 'blocked', causes: [{ problem: 'A.' }, { problem: 'B.', nextAction: 'run_again' }] });
    assert.equal(finished.message, 'A.\n\n' + FIX_LINE + '\n\nB.');
  });
  test('the stop blocks come before the given blocks', () => {
    const finished = lib.finish({ outcome: 'blocked', causes: [{ problem: 'A.' }], blocks: [{ text: 'Later.' }, { text: 'Tail.' }] });
    assert.equal(finished.message, 'A.\n\n' + FIX_LINE + '\n\nLater.\n\nTail.');
  });
  test('a lone answer cause leads with the answer line', () => {
    const causes = [{ problem: 'Questions are still open.', nextAction: 'answer' }];
    assert.deepEqual(structuredClone(lib.buildStopBlocks(causes)), [
      { text: 'Questions are still open.' }, { text: ANSWER_LINE, whole: true }
    ]);
    const finished = lib.finish({ outcome: 'blocked', causes, blocks: [{ text: 'Open questions.' }] });
    assert.equal(finished.message, 'Questions are still open.\n\n' + ANSWER_LINE + '\n\nOpen questions.');
  });
});
