/*
 * args.js: reads a workflow's launch args and the state its pauses carry.
 *
 * Inputs
 *   rawArgs     the Workflow args global. A string is the request itself
 *               (slash-command form). A plain object is read as
 *               {request, trunk?, references?, answers?, reply?, build?}. Anything
 *               else reads as an empty object.
 *   argsObject  the object readArgsObject returns.
 *   runNoun     the word for the run in a user-facing message, read after
 *               "the": 'analysis' gives "so the analysis did not start". A
 *               non-blank string, or the message function throws.
 *   buildId     the build id of the running script, a non-blank string,
 *               or readLaunchInputs and buildResumeArgs throw.
 *   round       a positive integer, the pause round.
 *   replies     the replies so far, round 1 first.
 *
 * Outputs
 *   isPlainObject(value)       true for an object that is not null and not
 *                              an array.
 *   isNonEmptyString(value)    true for a string that is not blank.
 *   readArgsObject(rawArgs)    the args as an object, as above.
 *   defaultTrunk()             'main', the trunk when the trunk arg is
 *                              absent.
 *   maxReferences()            20, the most references a launch may name.
 *   describeRunNoun(runNoun)   'the ' + runNoun, the run as a message names
 *                              it. Throws when runNoun is not a non-blank
 *                              string.
 *   requireBuildId(buildId)    buildId. Throws when it is not a non-blank
 *                              string.
 *   readTrunk(argsObject, runNoun)
 *     {trunk} when trunk is absent ('main') or a non-blank string, which
 *     passes through. Otherwise {problem}.
 *   normalizeReference(value)  a positive safe integer or a digit string as
 *                              a digit string, else undefined.
 *   readReferences(argsObject, runNoun)
 *     {references} when references is absent (none) or a list whose every
 *     entry normalizes, deduplicated in order, at most maxReferences().
 *     Otherwise {problem}.
 *   readLaunchInputs(argsObject, runNoun, buildId)
 *     {trunk, references}, or the {problem} of the first bad arg: a
 *     resume_args key first, then the build, then trunk, then references.
 *     The build is checked only on a resume, when answers is a plain
 *     object: a build absent or not equal to buildId is a problem.
 *   roundKey(round)            'round-N', the answers key of round N.
 *   readStoredAnswers(argsObject)
 *     argsObject.answers when it is a plain object, else {}.
 *   readStoredReply(storedAnswers, round)
 *     the stored reply to round N when it is a non-blank string, else
 *     undefined.
 *   readPendingReply(argsObject)
 *     the replyField() value when it is a non-blank string and answers is a
 *     plain object, since answers marks a pending pause. Else undefined.
 *   buildResumeArgs(replies, buildId)
 *     {answers, build}: each reply under its roundKey, and buildId.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O. Inputs are never changed.
 *   request, trunk and references come from the launch args only, so a
 *   string launch takes the defaults. A top-level 'round-N' key is never
 *   read. resume_args is {answers, build} alone: never the request, which
 *   the launch args already hold, and never a reply or an autonomy key.
 *   A resume whose build is not the running build stops before any agent
 *   call: the plugin changed while the run was paused, so the stored
 *   answers may not fit the new script. A fresh launch ignores a build.
 *   Args that hold a resume_args key are a problem before any other check:
 *   the resume rule puts the keys of resume_args at the top level of args,
 *   so a nested resume_args would drop the stored answers and ask the same
 *   question again.
 *   A digit string reference passes as it is, leading zeros included. The
 *   facts skill's input gate is the charset check on trunk and references,
 *   so no second allowlist is kept here.
 *   Every problem but the build problem is one sentence ending "so the
 *   <runNoun> did not start.". No problem echoes an arg value. With runNoun 'analysis' the text is the
 *   analysis-only text, byte for byte.
 *   Uses replyField() from result.js.
 *
 * Why
 *   analysis-only and standard-delivery take the same launch args and pause
 *   the same way. One home keeps their checks and resume rule in step, and
 *   the run noun keeps each workflow's messages in its own words.
 */

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim() !== '';
}

function readArgsObject(rawArgs) {
  if (typeof rawArgs === 'string') {
    return { request: rawArgs };
  }
  if (isPlainObject(rawArgs)) {
    return rawArgs;
  }
  return {};
}

function defaultTrunk() {
  return 'main';
}

function maxReferences() {
  return 20;
}

function describeRunNoun(runNoun) {
  if (!isNonEmptyString(runNoun)) {
    throw new Error('args.js: runNoun must be a non-blank string');
  }
  return 'the ' + runNoun;
}

function readTrunk(argsObject, runNoun) {
  const notStarted = 'so ' + describeRunNoun(runNoun) + ' did not start.';
  if (argsObject.trunk === undefined) {
    return { trunk: defaultTrunk() };
  }
  if (isNonEmptyString(argsObject.trunk)) {
    return { trunk: argsObject.trunk };
  }
  return { problem: 'The trunk launch arg must be a non-blank string, ' + notStarted };
}

function normalizeReference(value) {
  if (Number.isSafeInteger(value) && value > 0) {
    return String(value);
  }
  return typeof value === 'string' && /^[0-9]+$/.test(value) ? value : undefined;
}

function readReferences(argsObject, runNoun) {
  const notStarted = 'so ' + describeRunNoun(runNoun) + ' did not start.';
  const badShape = { problem: 'The references launch arg must be a list of issue or pull request numbers, ' + notStarted };
  if (argsObject.references === undefined) {
    return { references: [] };
  }
  if (!Array.isArray(argsObject.references)) {
    return badShape;
  }
  const normalized = argsObject.references.map(normalizeReference);
  if (normalized.includes(undefined)) {
    return badShape;
  }
  const references = normalized.filter((reference, index) => normalized.indexOf(reference) === index);
  if (references.length > maxReferences()) {
    return { problem: 'The references launch arg names ' + references.length + ' issues or pull requests, more than the ' + maxReferences() + ' the facts step takes, ' + notStarted };
  }
  return { references: references };
}

function requireBuildId(buildId) {
  if (!isNonEmptyString(buildId)) {
    throw new Error('args.js: buildId must be a non-blank string');
  }
  return buildId;
}

function readLaunchInputs(argsObject, runNoun, buildId) {
  requireBuildId(buildId);
  if (Object.prototype.hasOwnProperty.call(argsObject, 'resume_args')) {
    return { problem: 'The args hold a resume_args key, but the keys of resume_args belong at the top level of args, so ' + describeRunNoun(runNoun) + ' did not start.' };
  }
  if (isPlainObject(argsObject.answers) && argsObject.build !== buildId) {
    return { problem: 'The plugin changed while ' + describeRunNoun(runNoun) + ' was paused, so nothing ran. Run the request again with your answers in it.' };
  }
  const trunkInput = readTrunk(argsObject, runNoun);
  if (trunkInput.problem !== undefined) {
    return trunkInput;
  }
  const referencesInput = readReferences(argsObject, runNoun);
  if (referencesInput.problem !== undefined) {
    return referencesInput;
  }
  return { trunk: trunkInput.trunk, references: referencesInput.references };
}

function roundKey(round) {
  return 'round-' + round;
}

function readStoredAnswers(argsObject) {
  return isPlainObject(argsObject.answers) ? argsObject.answers : {};
}

function readStoredReply(storedAnswers, round) {
  const key = roundKey(round);
  return isNonEmptyString(storedAnswers[key]) ? storedAnswers[key] : undefined;
}

function readPendingReply(argsObject) {
  const reply = argsObject[replyField()];
  return isPlainObject(argsObject.answers) && isNonEmptyString(reply) ? reply : undefined;
}

function buildResumeArgs(replies, buildId) {
  const answers = Object.fromEntries(replies.map((reply, index) => [roundKey(index + 1), reply]));
  return { answers: answers, build: requireBuildId(buildId) };
}
