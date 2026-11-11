/*
 * title.js: the title and closes helpers of the plan check a workflow
 * shares: the pull request title text and its cut, the commit type title
 * prefix and its normalization, and the check of plan.closes against the
 * launch references.
 *
 * Inputs
 *   plan        a plan of the workflow's PLAN_SCHEMA: classification,
 *               breaking, title and the optional closes.
 *   result      a planner result, and schema its result schema.
 *   references  the launch references, digit strings, of run.references.
 *   commitTypeMap() of lib/runner.js and validateSchema of lib/schema.js.
 *   The constant of the workflow's main.js this file reads: RUN_NAME, read
 *   by describeClosesProblem. Every workflow whose code calls it declares
 *   it.
 *
 * Outputs
 *   maxTitleLength()  the most code points a pull request title holds,
 *           its prefix included.
 *   cleanPullRequestText(text, keepsLines)  text with each control
 *           character a space; tab and line feed kept when keepsLines.
 *   cleanTitleText(text)  text cleaned as one line of pull request text,
 *           its blanks collapsed and trimmed.
 *   buildTitlePrefix(plan)  the commit type of plan.classification, '!'
 *           when plan.breaking, and ':'.
 *   buildTitleText(plan)  the title text after its prefix: plan.title
 *           cleaned and cut at a word to the room maxTitleLength() leaves
 *           after the prefix and one space, never inside a bracket the cut
 *           text opened (issue 469).
 *   typedTitlePattern()  the commit type title prefix, read by the plan
 *           check (standard-delivery plan.js).
 *   normalizePlanTitle(result, schema)  result, or a copy with its own
 *           commit type cut from plan.title.
 *   listCloses(plan)  plan.closes, or [] when absent.
 *   describeClosesProblem(plan, references)  the last check of the plan
 *           check: the problem of a plan.closes number that is not the
 *           number of one of references, naming its index, else undefined.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this library into it, so a row can name a
 *   function of this library.
 *   Title type: normalizePlanTitle returns a copy of a complete result
 *   that fits its schema whose cleaned plan.title starts with the plan's
 *   own commitTypeMap() value in any letter case, an optional
 *   parenthesized scope, '!' only when plan.breaking, and ':', with
 *   plan.title the trimmed rest when it is not blank; it never changes the
 *   agent result. Every other result is returned as is, so the plan check
 *   still refuses any other typed title.
 *   The plan check refuses a plan whose buildTitleText is empty, so the
 *   pull request title is never only its type (issue 469).
 *   The closes check is membership only: which reference the run fixes is
 *   the planner's judgment, and code does not check that a number names an
 *   issue rather than a pull request.
 *
 * Why
 *   The plan check and the pull request title read the same title text, so
 *   one set of helpers builds it for every workflow that checks a plan.
 */

function maxTitleLength() {
  return 256;
}

function isPullRequestCharacter(codePoint, keepsLines) {
  if (keepsLines && (codePoint === 9 || codePoint === 10)) {
    return true;
  }
  return codePoint >= 32 && (codePoint < 127 || codePoint > 159);
}

function cleanPullRequestText(text, keepsLines) {
  return Array.from(text).map((character) => (isPullRequestCharacter(character.codePointAt(0), keepsLines) ? character : ' ')).join('');
}

function cleanTitleText(text) {
  return cleanPullRequestText(text, false).replace(/\s+/gu, ' ').trim();
}

function trimTitleEnd(text) {
  return text.replace(/[\s,;:-]+$/u, '');
}

/**
 * Returns the indexes, in order, of each (, [ or { in characters that no
 * matching closer after it closes. A closer pops only the opener on top of
 * the stack it matches, so every opener before the first returned index
 * is closed before that index.
 */
function findUnclosedOpeners(characters) {
  const closers = { '(': ')', '[': ']', '{': '}' };
  const openIndexes = [];
  characters.forEach((character, index) => {
    if (closers[character] !== undefined) {
      openIndexes.push(index);
    } else if (openIndexes.length > 0 && closers[characters[openIndexes[openIndexes.length - 1]]] === character) {
      openIndexes.pop();
    }
  });
  return openIndexes;
}

function closeTitleBrackets(text) {
  const characters = Array.from(text);
  const openIndexes = findUnclosedOpeners(characters);
  if (openIndexes.length === 0) {
    return text;
  }
  const beforeOpener = trimTitleEnd(characters.slice(0, openIndexes[0]).join(''));
  if (beforeOpener !== '') {
    return beforeOpener;
  }
  return trimTitleEnd(characters.filter((character, index) => !openIndexes.includes(index)).join('').trim());
}

function cutTitleText(text, room) {
  const characters = Array.from(text);
  if (characters.length <= room) {
    return text;
  }
  const lastSpace = characters.slice(0, room + 1).lastIndexOf(' ');
  const kept = characters.slice(0, lastSpace > 0 ? lastSpace : room).join('');
  return closeTitleBrackets(trimTitleEnd(kept));
}

function buildTitlePrefix(plan) {
  return commitTypeMap()[plan.classification] + (plan.breaking ? '!' : '') + ':';
}

/**
 * Returns the pull request title text after its prefix: plan.title cleaned
 * as pull request text and cut to the room maxTitleLength() leaves after
 * the prefix and one space. describePlanProblem (plan.js) refuses a plan
 * whose text is empty, so a checked plan never gets a type-only title.
 */
function buildTitleText(plan) {
  return cutTitleText(cleanTitleText(plan.title), maxTitleLength() - buildTitlePrefix(plan).length - 1);
}

function typedTitlePattern() {
  return new RegExp('^(' + Object.values(commitTypeMap()).join('|') + ')(\\([^()]*\\))?(!?):', 'i');
}

/**
 * Returns result, or, for a complete result that fits schema, a copy whose
 * plan.title drops a leading commit type that equals the plan's own type,
 * with '!' only when the plan is breaking, when text is left after it. A
 * result that fits schema holds plan only when its outcome is complete.
 */
function normalizePlanTitle(result, schema) {
  const plan = validateSchema(schema, result).ok ? result.plan : undefined;
  const match = plan === undefined ? null : typedTitlePattern().exec(cleanTitleText(plan.title));
  const rest = match === null ? '' : match.input.slice(match[0].length).trim();
  if (rest === '' || match[1].toLowerCase() !== commitTypeMap()[plan.classification] || (match[3] && !plan.breaking)) {
    return result;
  }
  return { ...result, plan: { ...plan, title: rest } };
}

function listCloses(plan) {
  return plan.closes ?? [];
}

/**
 * Returns the plan problem of the first plan.closes number that is not the
 * number of one of references, the launch digit strings, naming its index,
 * or undefined when every number is one of them. describePlanProblem
 * (plan.js) returns it as its last check. It compares decimal text, never
 * a Number of a reference: the number's String against each reference with
 * its leading zeros cut, so a reference past the safe integer range matches
 * only its own digits, and a reference of zeros alone matches no number.
 */
function describeClosesProblem(plan, references) {
  const index = listCloses(plan).findIndex((number) => !references.some((reference) => reference.replace(/^0+/, '') === String(number)));
  return index === -1 ? undefined : 'The plan names an issue at closes[' + index + '] that is not one of the references the run started with, so ' + RUN_NAME + ' stopped.';
}
