/*
 * paths.js: the path checks of plan and scope values a workflow shares:
 * the external content label, the repository path mark, the path rule and
 * the walk of a schema for the mark.
 *
 * Inputs
 *   schema  a step schema whose path fields carry repositoryPathMark() in
 *           their description: the workflow's PLAN_SCHEMA. The
 *           standard-delivery scope schema (scope.js) marks its path fields
 *           the same way.
 *   value   the step value checked against it, such as a plan.
 *   The constant of the workflow's main.js this file reads: PLAN_SCHEMA,
 *   read by listPlanPaths. Every workflow whose code calls listPlanPaths
 *   declares it. isPlainObject is lib/result.js.
 *
 * Outputs
 *   externalLabel()  the label that starts every description of a field
 *           that can carry external content.
 *   repositoryPathMark()  externalLabel() plus the repository path mark.
 *   isRepositoryPath(value)  true when value is a plain path inside the
 *           repository, by the files rule of molt.sh.
 *   collectRepositoryPaths(schema, value, location, found)  found, with
 *           {location, value} pushed for each marked value.
 *   findRepositoryPathProblem(schema, value, location)  the location of the
 *           first marked value that fails isRepositoryPath, else ''.
 *   listPlanPaths(plan)  the distinct plan paths in walk order.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this library into it, so a row can name a
 *   function of this library.
 *   Every plan value at a field whose PLAN_SCHEMA description starts with
 *   repositoryPathMark() must pass isRepositoryPath (review finding
 *   461fe942). collectRepositoryPaths walks the schema for the mark, so a
 *   new path field is read once it carries the mark, by
 *   findRepositoryPathProblem and by listPlanPaths. The rule is the files
 *   rule of molt.sh, its home, and a parity test runs one corpus through
 *   both and requires the same verdicts, so a change lands in both. The
 *   check is lexical, so a symlinked path or one that names a directory is
 *   left to molt.sh. Fix round files are not plan fields: they reach only
 *   molt.sh, which applies the same rule before any change. The user
 *   rejected local review finding c2e0ada3, which asked for a check of fix
 *   round files members in the workflow, on this basis (ADR-0037,
 *   Amendment 2026-10-25). isGitIdentifier stays on artifact_files for the
 *   bump-type --version-file argument of the standard-delivery validate
 *   step (gates.js), since the path rule allows spaces, shell characters
 *   and a leading '-'.
 *
 * Why
 *   A path a step writes reaches the commit script, so one rule, read from
 *   the schema mark, checks every such path before any later step.
 */

function externalLabel() {
  return 'Can carry external content.';
}

function repositoryPathMark() {
  return externalLabel() + ' Repository path.';
}

function toAsciiLowerCase(text) {
  return text.replace(/[A-Z]/g, (letter) => String.fromCharCode(letter.charCodeAt(0) + 32));
}

function isRepositoryPath(value) {
  if (typeof value !== 'string' || value.length === 0 || value.startsWith('/')) {
    return false;
  }
  const isOneLine = Array.from(value).every((character) => character.codePointAt(0) >= 32 && character.codePointAt(0) !== 127);
  return isOneLine && value.split('/').every((part) => !['', '.', '..', '.git'].includes(toAsciiLowerCase(part)));
}

/**
 * Pushes {location, value} to found for each value at a node the mark names,
 * in pre-order over the present properties and items. Returns found.
 */
function collectRepositoryPaths(schema, value, location, found) {
  if (typeof schema.description === 'string' && schema.description.startsWith(repositoryPathMark())) {
    found.push({ location: location, value: value });
  }
  if (schema.properties !== undefined && isPlainObject(value)) {
    const presentNames = Object.keys(schema.properties).filter((name) => Object.hasOwn(value, name));
    presentNames.forEach((name) => collectRepositoryPaths(schema.properties[name], value[name], location === '' ? name : location + '.' + name, found));
  }
  if (schema.items !== undefined && Array.isArray(value)) {
    value.forEach((item, index) => collectRepositoryPaths(schema.items, item, location + '[' + index + ']', found));
  }
  return found;
}

function findRepositoryPathProblem(schema, value, location) {
  const problem = collectRepositoryPaths(schema, value, location, []).find((entry) => !isRepositoryPath(entry.value));
  return problem === undefined ? '' : problem.location;
}

/**
 * Returns the distinct plan paths in walk order: the values at PLAN_SCHEMA
 * fields the mark names, version files then step files.
 */
function listPlanPaths(plan) {
  return [...new Set(collectRepositoryPaths(PLAN_SCHEMA, plan, '', []).map((entry) => entry.value))];
}
