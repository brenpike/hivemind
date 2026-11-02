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
 *                steps remain but none can run. problem is one fixed line
 *                that names positions only (e.g. plan.steps[2].id), never
 *                a plan value, so a model-written id cannot add a line, a
 *                control character or bulk to it.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O. Inputs are never changed.
 *   The rule's home and parity oracle is
 *   plugin/skills/next-wave/scripts/next-wave.sh: COMPUTATION items 3 to 5,
 *   its VALIDATION in the same order with the same texts, and its defensive
 *   stall check. The first check mirrors the step rows of the wave-ledger
 *   contract of hivemind_check_json: plan.steps a required array, each step
 *   an object, each id a required step id, each depends_on an optional
 *   array of step ids. Absent means undefined or null; an array element is
 *   never absent. Rows run in table order and positions in ascending index
 *   (row-major); the first failure is the problem. A step id is 1 to 64 of
 *   A-Z a-z 0-9 . _ -, all ASCII, so JS and jq count its length alike. Then
 *   come the empty, duplicate id, unknown dependency and cycle checks.
 *   tests/workflow-scripts/waves.test.mjs runs both on the same plans and
 *   requires the same outcome: the same wave, or the same problem text. A
 *   change to the rule lands in next-wave.sh and here together.
 *   Only one thing differs from next-wave.sh:
 *     The input is a list of done ids, not a run ledger. Deriving that list
 *     (epoch scope, event projection) is the caller's job.
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
  const contractProblem = findStepContractProblem(steps);
  if (contractProblem !== '') {
    return contractProblem;
  }
  if (steps.length === 0) {
    return 'plan.steps: empty, nothing to schedule';
  }
  const duplicateIndex = findDuplicateStepIndex(steps);
  if (duplicateIndex !== -1) {
    return 'plan.steps[' + duplicateIndex + '].id: duplicate step id';
  }
  const unknownPosition = findUnknownDependencyPosition(steps);
  if (unknownPosition !== '') {
    return unknownPosition + ': unknown step id';
  }
  if (hasDependencyCycle(steps)) {
    return 'dependency cycle detected among plan steps';
  }
  return '';
}

function findStepContractProblem(steps) {
  if (steps === undefined || steps === null) {
    return 'plan.steps: missing';
  }
  if (!Array.isArray(steps)) {
    return 'plan.steps: not an array';
  }
  const objectIndex = steps.findIndex((step) => !isWaveStepRecord(step));
  if (objectIndex !== -1) {
    return 'plan.steps[' + objectIndex + ']: not an object';
  }
  const idProblem = findStepIdProblem(steps);
  if (idProblem !== '') {
    return idProblem;
  }
  const arrayIndex = steps.findIndex((step) => !isAbsentValue(step.depends_on) && !Array.isArray(step.depends_on));
  if (arrayIndex !== -1) {
    return 'plan.steps[' + arrayIndex + '].depends_on: not an array';
  }
  return findDependencyEntryProblem(steps);
}

function findStepIdProblem(steps) {
  for (let index = 0; index < steps.length; index += 1) {
    if (isAbsentValue(steps[index].id)) {
      return 'plan.steps[' + index + '].id: missing';
    }
    if (!isStepId(steps[index].id)) {
      return 'plan.steps[' + index + '].id: ' + describeStepIdProblem();
    }
  }
  return '';
}

function findDependencyEntryProblem(steps) {
  for (let index = 0; index < steps.length; index += 1) {
    const badEntry = readStepDependencies(steps[index]).findIndex((dependency) => !isStepId(dependency));
    if (badEntry !== -1) {
      return 'plan.steps[' + index + '].depends_on[' + badEntry + ']: ' + describeStepIdProblem();
    }
  }
  return '';
}

function describeStepIdProblem() {
  return 'not a step id (1 to 64 of A-Z a-z 0-9 . _ -)';
}

function isStepId(value) {
  return typeof value === 'string' && /^[A-Za-z0-9._-]{1,64}$/.test(value);
}

function isAbsentValue(value) {
  return value === undefined || value === null;
}

function isWaveStepRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function readStepDependencies(step) {
  return Array.isArray(step.depends_on) ? step.depends_on : [];
}

function findDuplicateStepIndex(steps) {
  const seenIds = new Set();
  for (let index = 0; index < steps.length; index += 1) {
    if (seenIds.has(steps[index].id)) {
      return index;
    }
    seenIds.add(steps[index].id);
  }
  return -1;
}

function findUnknownDependencyPosition(steps) {
  const stepIds = new Set(steps.map((step) => step.id));
  for (let index = 0; index < steps.length; index += 1) {
    const unknownEntry = readStepDependencies(steps[index]).findIndex((dependency) => !stepIds.has(dependency));
    if (unknownEntry !== -1) {
      return 'plan.steps[' + index + '].depends_on[' + unknownEntry + ']';
    }
  }
  return '';
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
