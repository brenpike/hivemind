/*
 * standard-delivery scope.js: the scope step of the standard-delivery
 * workflow. It holds the scope schema, the scope prompt and options, the
 * scope check and the scope step.
 *
 * Inputs
 *   run    the run state of main.js createRunState: request, pass and
 *          answerLog.
 *   facts  the checked facts of the pass, from runFactsStep (relay.js).
 *          Its root line, the checkout root, converts scope paths.
 *   scope  the planner result in Scope Mode, under SCOPE_SCHEMA.
 *   round  undefined for the scope of a pass, else the answer round after
 *          whose reply the same pass scopes again.
 *   PLANNER_AGENT, SCOPE_MODEL and SCOPE_SCHEMA from main.js.
 *
 * Outputs
 *   runScopeStep(run, facts, round)  {scope} or {problem, nextAction}.
 *                             The scope holds only the documents and paths
 *                             entries whose path passes isRepositoryPath,
 *                             after a path under the checkout root is made
 *                             relative to it (toRepositoryRelativePath),
 *                             and every limit.
 *   The step, as meta.js names it:
 *   Scope   hivemind:cerebrate in Scope Mode, on SCOPE_MODEL at effort
 *           high, returns the path and start line of each section of the
 *           documents the request names and the drift of each path a
 *           section names, under SCOPE_SCHEMA. It returns start lines, not
 *           line ranges: the planner reads each whole section from the
 *           file. It also returns the limits the request and the user's
 *           answers set on the work. It runs once in every pass, after the
 *           facts step and the scan and before planning, with label
 *           scope-P. A re-scope runs it again in the same pass after the
 *           reply of answer round R, with label scope-P-R.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   The scope result is checked before any field is read: a result that
 *   fails SCOPE_SCHEMA stops the run before planning, through
 *   describeUnusableResult (lib/result.js): a null result, an agent
 *   failure, adds the agent-failure sentence and next action run_again,
 *   and any other unusable result keeps the fix line. A path, the field
 *   marked with repositoryPathMark(), that starts with the facts root line
 *   and a slash is first cut to the rest after that slash; a root line of
 *   none, or no root line, converts nothing. An entry whose path then fails
 *   isRepositoryPath (plan.js) is dropped from the scope
 *   (keepRepositoryPathEntries), as an entry left out: the planner then
 *   reads or checks it itself.
 *   A limit is made relative to the facts root the same way and loses a
 *   trailing '/', but is never dropped: a dropped limit would widen the
 *   work. A limit that fails isRepositoryPath matches no plan file, so the
 *   check of edits outside the limits asks: it fails closed by
 *   construction.
 *   With an empty answerLog the scope prompt is the prompt of a run with
 *   no answers, and it carries no resume note, so a resume replays it from
 *   cache. Otherwise it carries the whole log in an answers data block
 *   right after the request block, and its data line calls settled only
 *   what the settled labels of each entry name, so an open question shown
 *   in the same round is never taken as settled.
 *   ADR-0037 invariant 4 holds by construction: the scope copies no
 *   document text and states no section's extent, because the planner
 *   takes each section's start and end from the file, so no copy or range
 *   can be cut; every string field starts with externalLabel(); and the
 *   documents and paths lists are partial by definition and bounded by
 *   maxItems, so an entry left out is read or checked by the planner itself
 *   and no step depends on a list being complete. The limits list is
 *   bounded by maxItems too.
 *   The scope reaches only the plan and revise prompts, in a scope data
 *   block after the request block. It never reaches a message, the pull
 *   request texts or a worker prompt.
 *   The prompt restates no rule of ${CLAUDE_PLUGIN_ROOT}/agents/cerebrate.md
 *   (docs/engineering-principles.md P24): what a scope holds and how it is
 *   found live in its Scope Mode section, and each field rule in the
 *   schema. The effort is set here because the planner frontmatter sets a
 *   higher one.
 *
 * Why
 *   A cheaper model finds where the sections of the documents the request
 *   names start, once, so the planner reads those whole sections, not each
 *   whole document, and checks no named path again. A Workflow script
 *   cannot read files, so it could never check a copied slice or a stated
 *   range against its file. A start line bounds nothing, so a wrong one
 *   cannot cut what the planner reads; the file the planner reads is
 *   ground truth. The maxItems bounds keep the size of the scope block,
 *   which every plan and revise prompt carries, bounded. They do not bound
 *   what the planner reads: each read is a whole section, never more than
 *   the whole document the planner read before the scope step.
 */

function buildScopeSchema() {
  const pathField = { type: 'string', maxLength: 400, description: repositoryPathMark() + ' It is relative to the repository root, like tools/validate.sh, never absolute.' };
  const documentItem = {
    type: 'object',
    properties: {
      path: pathField,
      line: { type: 'integer', description: 'The 1-based line where the section starts. It locates the section and does not bound it.' }
    },
    required: ['path', 'line'],
    additionalProperties: false
  };
  const pathItem = {
    type: 'object',
    properties: {
      path: pathField,
      exists: { type: 'boolean', description: 'true when the path exists now.' },
      drift: { type: 'string', minLength: 0, maxLength: 400, description: externalLabel() + ' How the path differs from what the section says, empty when it does not.' }
    },
    required: ['path', 'exists', 'drift'],
    additionalProperties: false
  };
  return {
    type: 'object',
    properties: {
      documents: { type: 'array', maxItems: 10, description: 'The sections of the named documents, empty when none. A section may be left out, and the planner then reads it itself.', items: documentItem },
      paths: { type: 'array', maxItems: 30, description: 'The paths a section or the request names for the work, empty when none. A path may be left out, and the planner then checks it itself.', items: pathItem },
      limits: { type: 'array', maxItems: 30, description: 'The paths or directories the request and the user\'s answers limit the work to, empty when none.', items: pathField }
    },
    required: ['documents', 'paths', 'limits'],
    additionalProperties: false
  };
}

function buildScopePrompt(request, facts, answerLog) {
  const hasAnswers = answerLog.length > 0;
  const lines = [
    'Scope the user request below for its planner, in Scope Mode.',
    boundarySentence(),
    hasAnswers ? settledAnswersSentence(undefined) : dataBlocksSentence(),
    '',
    buildFactsBlock(facts),
    formatDataBlock('request', request)
  ];
  if (hasAnswers) {
    lines.push(formatDataBlock('answers', answerLog));
  }
  return lines.join('\n');
}

function scopeOptions(pass, round) {
  const label = round === undefined ? 'scope-' + pass : 'scope-' + pass + '-' + round;
  return { agentType: PLANNER_AGENT, model: SCOPE_MODEL, effort: 'high', schema: toAgentSchema(SCOPE_SCHEMA), label: label, phase: 'Scope' };
}

function describeScopeProblem(scope) {
  const isUsable = validateSchema(SCOPE_SCHEMA, scope).ok;
  return isUsable ? undefined : describeUnusableResult('The scope step returned a result it could not use, so ' + RUN_NAME + ' stopped before planning.', scope);
}

function toRepositoryRelativePath(path, root) {
  if (typeof root !== 'string' || root === 'none') {
    return path;
  }
  const prefix = root.endsWith('/') ? root : root + '/';
  return path.startsWith(prefix) ? path.slice(prefix.length) : path;
}

function relativizeScopeEntry(entry, root) {
  return Object.assign({}, entry, { path: toRepositoryRelativePath(entry.path, root) });
}

function toLimitPath(limit, root) {
  const relativeLimit = toRepositoryRelativePath(limit, root);
  return relativeLimit.endsWith('/') ? relativeLimit.slice(0, -1) : relativeLimit;
}

function keepRepositoryPathEntries(scope, root) {
  const keepEntries = (entries) => entries.map((entry) => relativizeScopeEntry(entry, root)).filter((entry) => isRepositoryPath(entry.path));
  return {
    documents: keepEntries(scope.documents),
    paths: keepEntries(scope.paths),
    limits: scope.limits.map((limit) => toLimitPath(limit, root))
  };
}

async function runScopeStep(run, facts, round) {
  phase('Scope');
  const scope = await agent(buildScopePrompt(run.request, facts, run.answerLog), scopeOptions(run.pass, round));
  const unusable = describeScopeProblem(scope);
  return unusable === undefined ? { scope: keepRepositoryPathEntries(scope, facts.root) } : unusable;
}
