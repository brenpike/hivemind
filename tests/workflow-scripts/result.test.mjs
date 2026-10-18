import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/result.js']);

describe('result contract', () => {
  const decisions = [{ kind: 'plan_acceptance', option_id: 'A' }];
  test('pauseForUser returns the pause shape', () => {
    const resumeArgs = { request: 'R', answers: { answer_0: 'earlier' } };
    const paused = structuredClone(lib.pauseForUser({ answerKey: 'answer_1', message: 'Q?', resumeArgs, decisions }));
    assert.deepEqual(paused, { needs_user: true, answer_key: 'answer_1', message: 'Q?', resume_args: resumeArgs, decisions });
  });
  test('finish returns the finish shape for both outcomes', () => {
    for (const outcome of ['complete', 'blocked']) {
      const finished = structuredClone(lib.finish({ outcome, message: 'Done.', decisions }));
      assert.deepEqual(finished, { needs_user: false, outcome, message: 'Done.', decisions });
    }
  });
  test('resultFields covers exactly the fields both shapes use', () => {
    const paused = lib.pauseForUser({ answerKey: 'a', message: 'm', resumeArgs: { answers: {} }, decisions: [] });
    const finished = lib.finish({ outcome: 'complete', message: 'm', decisions: [] });
    const used = new Set([...Object.keys(paused), ...Object.keys(finished)]);
    assert.deepEqual([...lib.resultFields()].sort(), [...used].sort());
  });
  test('a run pauses at most three times', () => {
    assert.equal(lib.pauseLimit(), 3);
    assert.deepEqual([0, 1, 2, 3, 4].map((count) => lib.canPause(count)), [true, true, true, false, false]);
    assert.throws(() => lib.canPause(-1), /non-negative integer/);
    assert.throws(() => lib.canPause('1'), /non-negative integer/);
  });
  test('invalid pause input throws', () => {
    const valid = { answerKey: 'answer_1', message: 'Q?', resumeArgs: { answers: {} }, decisions: [] };
    assert.throws(() => lib.pauseForUser({ ...valid, answerKey: '' }), /answerKey/);
    assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs: [] }), /resumeArgs must be a plain object/);
    assert.throws(() => lib.pauseForUser({ ...valid, message: ' ' }), /message/);
    assert.throws(() => lib.pauseForUser({ ...valid, decisions: null }), /decisions/);
  });
  test('resumeArgs.answers must be a plain object', () => {
    const valid = { answerKey: 'answer_1', message: 'Q?', decisions: [] };
    for (const resumeArgs of [{}, { answers: null }, { answers: [] }, { answers: 'answer_1' }]) {
      assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs }), /resumeArgs.answers must be a plain object/);
    }
  });
  test('answerKey already in resumeArgs.answers throws, so a reply cannot overwrite an earlier one', () => {
    const valid = { answerKey: 'answer_1', message: 'Q?', decisions: [] };
    assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs: { answers: { answer_1: 'old' } } }), /answers already has answerKey/);
  });
  test('answerKey at the top level of resumeArgs is not the guarded slot', () => {
    const resumeArgs = { answer_1: 'unrelated', answers: {} };
    const paused = lib.pauseForUser({ answerKey: 'answer_1', message: 'Q?', resumeArgs, decisions: [] });
    assert.equal(paused.answer_key, 'answer_1');
  });
  test('invalid finish input throws', () => {
    assert.throws(() => lib.finish({ outcome: 'paused', message: 'm', decisions: [] }), /outcome must be complete or blocked/);
    assert.throws(() => lib.finish({ outcome: 'complete', message: '', decisions: [] }), /message/);
  });
});
