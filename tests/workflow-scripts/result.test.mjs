import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { loadLibs } from './harness.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const lib = loadLibs([repoRoot + 'plugin/workflow-src/lib/result.js']);

describe('result contract', () => {
  const decisions = [{ kind: 'plan_acceptance', option_id: 'A' }];
  test('pauseForUser returns the pause shape', () => {
    const resumeArgs = { request: 'R', answers: { 'round-1': 'earlier' } };
    const paused = structuredClone(lib.pauseForUser({ message: 'Q?', resumeArgs, decisions }));
    assert.deepEqual(paused, { needs_user: true, message: 'Q?', resume_args: resumeArgs, decisions });
  });
  test('finish returns the finish shape for both outcomes', () => {
    for (const outcome of ['complete', 'blocked']) {
      const finished = structuredClone(lib.finish({ outcome, message: 'Done.', decisions }));
      assert.deepEqual(finished, { needs_user: false, outcome, message: 'Done.', decisions });
    }
  });
  test('message is the last key and resume_args precedes it, so a cut notice loses only message', () => {
    const paused = lib.pauseForUser({ message: 'Q?', resumeArgs: { request: 'R' }, decisions });
    assert.deepEqual([...Object.keys(paused)], ['needs_user', 'resume_args', 'decisions', 'message']);
    for (const outcome of ['complete', 'blocked']) {
      const finished = lib.finish({ outcome, message: 'Done.', decisions });
      assert.deepEqual([...Object.keys(finished)], ['needs_user', 'outcome', 'decisions', 'message']);
    }
  });
  test('resultFields covers exactly the fields both shapes use', () => {
    const paused = lib.pauseForUser({ message: 'm', resumeArgs: {}, decisions: [] });
    const finished = lib.finish({ outcome: 'complete', message: 'm', decisions: [] });
    const used = new Set([...Object.keys(paused), ...Object.keys(finished)]);
    assert.deepEqual([...lib.resultFields()].sort(), [...used].sort());
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
    const valid = { message: 'Q?', resumeArgs: { answers: {} }, decisions: [] };
    assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs: [] }), /resumeArgs must be a plain object/);
    assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs: null }), /resumeArgs must be a plain object/);
    assert.throws(() => lib.pauseForUser({ ...valid, message: ' ' }), /message/);
    assert.throws(() => lib.pauseForUser({ ...valid, decisions: null }), /decisions/);
  });
  test('resumeArgs with a reply key throws, so a stale reply can never be replayed', () => {
    const valid = { message: 'Q?', decisions: [] };
    for (const reply of ['old reply', '', undefined, null]) {
      assert.throws(() => lib.pauseForUser({ ...valid, resumeArgs: { answers: {}, reply } }), /must not have a reply key/);
    }
  });
  test('reply nested below the top level of resumeArgs is not the guarded key', () => {
    const resumeArgs = { answers: { reply: 'stored' } };
    const paused = lib.pauseForUser({ message: 'Q?', resumeArgs, decisions: [] });
    assert.deepEqual(structuredClone(paused.resume_args), resumeArgs);
  });
  test('invalid finish input throws', () => {
    assert.throws(() => lib.finish({ outcome: 'paused', message: 'm', decisions: [] }), /outcome must be complete or blocked/);
    assert.throws(() => lib.finish({ outcome: 'complete', message: '', decisions: [] }), /message/);
  });
});
