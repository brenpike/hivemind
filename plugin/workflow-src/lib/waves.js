/*
 * waves.js: computes the next ready wave of plan steps.
 *
 * Inputs
 *   computeWave(steps, doneIds)
 *     steps    the plan steps, in plan order. Each step is an object with
 *              id (string), files (array of path strings) and depends_on
 *              (array of step ids, or null, or absent).
 *     doneIds  the ids of the steps already done. Entries that are not
 *              strings, or that name no step, are ignored.
 *
 * Outputs
 *   computeWave  {ok: true, all_done, wave, remaining} when the plan is valid:
 *                  remaining  the count of steps not done.
 *                  wave       the step ids to run now, in plan order. Empty
 *                             only when all_done is true.
 *                  all_done   true when remaining is 0.
 *                {ok: false, problem} when the plan is not valid, or when
 *                steps remain but none can run. problem is one plain line.
 *                Every plan value it names is JSON-encoded, so a line feed
 *                or control character in a model-written id cannot break
 *                the line.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O. Inputs are never changed.
 *   The rule's home and parity oracle is
 *   plugin/skills/next-wave/scripts/next-wave.sh: COMPUTATION items 3 to 5,
 *   its VALIDATION in the same order (shape gate, empty, missing id,
 *   duplicate id, unknown dependency, cycle, safe-id charset) and its
 *   defensive stall check. tests/workflow-scripts/waves.test.mjs runs both on
 *   the same plans and requires the same outcome: the same wave, or a problem
 *   of the same class, which is its text before any value it names. A
 *   change to the rule lands
 *   in next-wave.sh and here together.
 *   Only two things differ from next-wave.sh:
 *     The input is a list of done ids, not a run ledger. Deriving that list
 *     (epoch scope, event projection) is the caller's job.
 *     The safe-id check is strict at the end of the string. jq's `$` also
 *     matches before a final line feed, so next-wave.sh accepts an id such as
 *     "STEP-001" followed by a line feed. computeWave rejects it.
 *
 * Why
 *   Both engines must dispatch the same waves from the same plan. The rule
 *   lives in one place, next-wave.sh, and this mirror is held to it by the
 *   parity test rather than by review.
 */

function computeWave(steps, doneIds) {
  const problem = findWavePlanProblem(steps);
  if (problem !== '') {
    return { ok: false, problem: problem };
  }
  if (!Array.isArray(doneIds)) {
    return { ok: false, problem: 'done ids is not an array' };
  }
  const doneSet = new Set(doneIds.filter((doneId) => typeof doneId === 'string'));
  const notDone = steps.filter((step) => !doneSet.has(step.id));
  const ready = notDone.filter((step) => readStepDependencies(step).every((dependency) => doneSet.has(dependency)));
  const wave = pickGreedyWave(ready, steps);
  if (notDone.length > 0 && wave.length === 0) {
    return { ok: false, problem: 'remaining steps exist but no step is ready (unsatisfiable dependencies)' };
  }
  return { ok: true, all_done: notDone.length === 0, wave: wave, remaining: notDone.length };
}

function findWavePlanProblem(steps) {
  if (!Array.isArray(steps)) {
    return 'plan.steps is not an array';
  }
  const shapeProblem = findStepShapeProblem(steps);
  if (shapeProblem !== '') {
    return shapeProblem;
  }
  if (steps.length === 0) {
    return 'plan.steps is empty or absent; nothing to schedule';
  }
  if (steps.some((step) => step.id === '')) {
    return 'a plan step is missing an id';
  }
  const duplicateId = findDuplicateStepId(steps);
  if (duplicateId !== null) {
    return 'duplicate plan step id: ' + JSON.stringify(duplicateId);
  }
  const unknownDependency = findUnknownDependency(steps);
  if (unknownDependency !== null) {
    return 'depends_on references unknown step id: ' + JSON.stringify(unknownDependency);
  }
  if (hasDependencyCycle(steps)) {
    return 'dependency cycle detected among plan steps';
  }
  const unsafeId = findUnsafeStepId(steps);
  if (unsafeId !== null) {
    return 'plan step id or depends_on entry fails the safe-id charset: ' + JSON.stringify(unsafeId);
  }
  return '';
}

function findStepShapeProblem(steps) {
  for (const step of steps) {
    const stepProblem = describeStepShapeProblem(step);
    if (stepProblem !== '') {
      return stepProblem;
    }
  }
  return '';
}

function describeStepShapeProblem(step) {
  if (!isWaveStepRecord(step)) {
    return 'a plan step is not an object: ' + JSON.stringify(step);
  }
  if (!Object.prototype.hasOwnProperty.call(step, 'id')) {
    return 'a plan step is missing an id';
  }
  if (typeof step.id !== 'string') {
    return 'a plan step id is not a string: ' + JSON.stringify(step.id);
  }
  if (step.depends_on === undefined || step.depends_on === null) {
    return '';
  }
  if (!Array.isArray(step.depends_on)) {
    return 'a plan step depends_on is not an array: ' + JSON.stringify(step.depends_on);
  }
  const badIndex = step.depends_on.findIndex((dependency) => typeof dependency !== 'string');
  if (badIndex !== -1) {
    return 'a plan step depends_on entry is not a string: ' + JSON.stringify(step.depends_on[badIndex]);
  }
  return '';
}

function isWaveStepRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function readStepDependencies(step) {
  return Array.isArray(step.depends_on) ? step.depends_on : [];
}

function findDuplicateStepId(steps) {
  const seenIds = new Set();
  for (const step of steps) {
    if (seenIds.has(step.id)) {
      return step.id;
    }
    seenIds.add(step.id);
  }
  return null;
}

function findUnknownDependency(steps) {
  const stepIds = new Set(steps.map((step) => step.id));
  for (const step of steps) {
    const unknown = readStepDependencies(step).find((dependency) => !stepIds.has(dependency));
    if (unknown !== undefined) {
      return unknown;
    }
  }
  return null;
}

function hasDependencyCycle(steps) {
  const dependenciesById = new Map(steps.map((step) => [step.id, readStepDependencies(step)]));
  let remainingIds = steps.map((step) => step.id);
  for (let pass = 0; pass < steps.length; pass += 1) {
    const remainingSet = new Set(remainingIds);
    remainingIds = remainingIds.filter((stepId) => dependenciesById.get(stepId).some((dependency) => remainingSet.has(dependency)));
  }
  return remainingIds.length > 0;
}

function findUnsafeStepId(steps) {
  for (const step of steps) {
    const candidates = [step.id].concat(readStepDependencies(step));
    const unsafe = candidates.find((candidate) => !isSafeStepId(candidate));
    if (unsafe !== undefined) {
      return unsafe;
    }
  }
  return null;
}

function isSafeStepId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9._-]+$/.test(value);
}

function pickGreedyWave(ready, steps) {
  const wave = [];
  const claimedFiles = new Set();
  for (const step of ready) {
    if (scopeConflictsWithAll(step, steps)) {
      if (wave.length === 0) {
        wave.push(step.id);
        return wave;
      }
      continue;
    }
    if (step.files.some((file) => claimedFiles.has(file))) {
      continue;
    }
    wave.push(step.id);
    step.files.forEach((file) => claimedFiles.add(file));
  }
  return wave;
}

function scopeConflictsWithAll(step, steps) {
  if (!Array.isArray(step.files) || step.files.length === 0) {
    return true;
  }
  if (step.files.some((file) => typeof file !== 'string' || file === '')) {
    return true;
  }
  if (!step.files.every(isCanonicalScopePath)) {
    return true;
  }
  return step.files.some((file) => isDirectoryOfOtherStepFile(file, step.id, steps));
}

function isCanonicalScopePath(file) {
  if (/[*?[]/.test(file)) {
    return false;
  }
  return file.split('/').every((component) => component !== '' && component !== '.' && component !== '..');
}

function isDirectoryOfOtherStepFile(file, stepId, steps) {
  const prefix = file + '/';
  return steps.some((other) => other.id !== stepId
    && Array.isArray(other.files)
    && other.files.some((otherFile) => typeof otherFile === 'string' && otherFile.startsWith(prefix)));
}
