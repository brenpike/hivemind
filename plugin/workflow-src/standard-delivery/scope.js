/*
 * standard-delivery scope.js: the scope step of the standard-delivery
 * workflow. It holds the scope schema, the scope prompt and options, the
 * scope check and the scope step.
 *
 * Inputs
 *   run    the run state of main.js createRunState: request, pass and
 *          replies.
 *   facts  the checked facts of the pass, from runFactsStep (relay.js).
 *   scope  the planner result in Scope Mode, under SCOPE_SCHEMA.
 *   PLANNER_AGENT, SCOPE_MODEL and SCOPE_SCHEMA from main.js.
 *
 * Outputs
 *   runScopeStep(run, facts)  {scope} or {problem}.
 *   The step, as meta.js names it:
 *   Scope   hivemind:cerebrate in Scope Mode, on SCOPE_MODEL at effort
 *           high, returns the path and start line of each section of the
 *           documents the request names and the drift of each path a
 *           section names, under SCOPE_SCHEMA. It returns start lines, not
 *           line ranges: the planner reads each whole section from the
 *           file. It runs in every pass, after the facts step and the scan
 *           and before planning, with label scope-P.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   The scope result is checked before any field is read: a result that
 *   fails SCOPE_SCHEMA, or whose value at a field marked with
 *   repositoryPathMark() fails isRepositoryPath (findRepositoryPathProblem,
 *   plan.js), stops the run before planning.
 *   ADR-0037 invariant 4 holds by construction: the scope copies no
 *   document text and states no section's extent, because the planner
 *   takes each section's start and end from the file, so no copy or range
 *   can be cut; every string field starts with externalLabel(); and both
 *   lists are partial by definition and bounded by maxItems, so an entry
 *   left out is read or checked by the planner itself and no step depends
 *   on a list being complete.
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
  const pathField = { type: 'string', maxLength: 400, description: repositoryPathMark() };
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
      paths: { type: 'array', maxItems: 30, description: 'The paths a section or the request names for the work, empty when none. A path may be left out, and the planner then checks it itself.', items: pathItem }
    },
    required: ['documents', 'paths'],
    additionalProperties: false
  };
}

function buildScopePrompt(request, facts) {
  return [
    'Scope the user request below for its planner, in Scope Mode.',
    boundarySentence(),
    dataBlocksSentence(),
    '',
    buildFactsBlock(facts),
    formatDataBlock('request', request)
  ].join('\n');
}

function scopeOptions(pass) {
  return { agentType: PLANNER_AGENT, model: SCOPE_MODEL, effort: 'high', schema: toAgentSchema(SCOPE_SCHEMA), label: 'scope-' + pass, phase: 'Scope' };
}

function describeScopeProblem(scope) {
  const isUsable = validateSchema(SCOPE_SCHEMA, scope).ok && findRepositoryPathProblem(SCOPE_SCHEMA, scope, '') === '';
  return isUsable ? undefined : 'The scope step returned a result it could not use, so ' + RUN_NAME + ' stopped before planning.';
}

async function runScopeStep(run, facts) {
  phase('Scope');
  const scope = await agent(addResumeNote(buildScopePrompt(run.request, facts), run), scopeOptions(run.pass));
  const problem = describeScopeProblem(scope);
  return problem === undefined ? { scope: scope } : { problem: problem };
}
