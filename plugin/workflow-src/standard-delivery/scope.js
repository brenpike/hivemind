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
 *           high, returns the slice of each document the request names and
 *           the drift of each path the slice names, under SCOPE_SCHEMA. It
 *           runs in every pass, after the facts step and the scan and
 *           before planning, with label scope-P.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   The scope result is checked before any field is read: a result that
 *   fails SCOPE_SCHEMA, or whose value at a field marked with
 *   repositoryPathMark() fails isRepositoryPath (findRepositoryPathProblem,
 *   plan.js), stops the run before planning.
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
 *   A cheaper model slices the documents the request names once, so the
 *   planner reads no whole document and checks no named path again.
 */

function buildScopeSchema() {
  const pathField = { type: 'string', maxLength: 400, description: repositoryPathMark() };
  const documentItem = {
    type: 'object',
    properties: {
      path: pathField,
      lines: { type: 'string', maxLength: 100, description: 'The line ranges of the slice, like 12-40.' },
      text: { type: 'string', maxLength: 20000, description: 'The slice, word for word.' }
    },
    required: ['path', 'lines', 'text'],
    additionalProperties: false
  };
  const pathItem = {
    type: 'object',
    properties: {
      path: pathField,
      exists: { type: 'boolean', description: 'true when the path exists now.' },
      drift: { type: 'string', minLength: 0, maxLength: 400, description: 'How the path differs from what the slice says, empty when it does not.' }
    },
    required: ['path', 'exists', 'drift'],
    additionalProperties: false
  };
  return {
    type: 'object',
    properties: {
      documents: { type: 'array', description: 'One slice per named document, empty when none.', items: documentItem },
      paths: { type: 'array', description: 'One entry per path a slice or the request names for the work, empty when none.', items: pathItem }
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
