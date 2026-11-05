/*
 * standard-delivery review-schema.js: the result schema of the local
 * review gate of the standard-delivery workflow. It holds REVIEW_SCHEMA's
 * builder, the field texts it is built from and the finding id shape.
 *
 * Inputs
 *   localReviewRoutes() and reviewExitFields() (review.js), the exit
 *   reasons and the fields each one names; externalLabel() (paths.js);
 *   scanExcerptLimit() (lib/facts.js); buildTaggedSchema (lib/schema.js);
 *   buildDestructiveListSchema (approvals.js), the optional destructive
 *   list of each user_question option.
 *
 * Outputs
 *   buildReviewSchema()  REVIEW_SCHEMA, which main.js builds once: the
 *          always-present fields, rejected_findings, and each field of
 *          reviewFieldTexts() under the exit_reason that names it.
 *   reviewFieldTexts()  the type, text, external mark and bounds of each
 *          conditional review field.
 *   findingIdField()  the finding id shape.
 *   reviewOptionIds()  the user_question option ids, A, B, C and D, in
 *          that order.
 *   buildReviewFieldSchema(name, entry)  the schema of one field entry.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   REVIEW_SCHEMA bounds each field that reaches a message or the
 *   planner. findingIdField() is the one home of the finding id shape,
 *   maxLength 64 and pattern ^[0-9a-f]{8,64}$, for finding_id and each
 *   rejected finding_id, so the short id, its first 8 characters, is
 *   always whole hex. Every list has maxItems, and buildReviewFieldSchema
 *   throws on a list entry with none. The review strings that reach no
 *   message and not the planner keep no maxLength: ledger_path, stage,
 *   prior_fix_commit, latest_severity_max, the entries of signals_fired,
 *   signals_observed and conflicting_findings, and the title and record
 *   of each rejected finding. Each field that can carry Codex-derived
 *   text starts its description with externalLabel().
 *   iterations_completed, findings_resolved and findings_open are display
 *   only. The user rejected local review finding de83f9cf, which asked
 *   for bounds and consistency checks on them (ADR-0037, Amendment
 *   2026-10-25: local review counts are display only).
 *
 * Why
 *   The review result is the one step result that carries Codex-derived
 *   text, so the bound of every field it holds sits in one place.
 */

function findingIdField() {
  return {
    type: 'string',
    text: 'The id of the finding, taken from the fix ledger: 8 to 64 lowercase hex characters.',
    isExternal: true,
    bounds: { maxLength: 64, pattern: '^[0-9a-f]{8,64}$' }
  };
}

function reviewFieldTexts() {
  return {
    signals_fired: { type: 'list', text: 'Each break-fix signal that fired.', isExternal: false, maxItems: 10 },
    conflicting_findings: { type: 'list', text: 'Each finding the fix conflicts with.', isExternal: true, maxItems: 20 },
    prior_fix_commit: { type: 'string', text: 'The commit of the earlier fix.', isExternal: false },
    cluster_files: { type: 'list', text: 'Each file of the root cluster.', isExternal: true, maxItems: 20, itemBounds: { maxLength: 400 } },
    cluster_ids: { type: 'list', text: 'Each finding id of the root cluster.', isExternal: true, maxItems: 20, itemBounds: { maxLength: 64 } },
    hypothesized_root: { type: 'string', text: 'The root the cluster findings share.', isExternal: true, bounds: { maxLength: 300 } },
    root_class: { type: 'string', text: 'The class of that root.', isExternal: true, bounds: { maxLength: 100 } },
    same_framing_rationale: { type: 'string', text: 'Why the findings share one framing.', isExternal: true, bounds: { maxLength: 600 } },
    signals_observed: { type: 'list', text: 'Each diminishing returns signal observed.', isExternal: false, maxItems: 10 },
    latest_severity_max: { type: 'string', text: 'The highest severity of the latest findings.', isExternal: true },
    recommendation_text: { type: 'string', text: 'What the reviewer recommends, or empty.', isExternal: true, bounds: { maxLength: 200, minLength: 0 } },
    finding_id: findingIdField(),
    pattern_category: { type: 'string', text: 'The injection pattern category.', isExternal: false, bounds: { enum: ['P1', 'P2', 'P3', 'P4'] } },
    field_excerpt: { type: 'string', text: 'The excerpt of the flagged field.', isExternal: true, bounds: { maxLength: scanExcerptLimit() } },
    classification: { type: 'string', text: 'The classification of the finding.', isExternal: true, bounds: { maxLength: 100 } },
    file: { type: 'string', text: 'The file of the finding.', isExternal: true, bounds: { maxLength: 400 } },
    title: { type: 'string', text: 'The title of the finding.', isExternal: true, bounds: { maxLength: 300 } },
    user_question: { type: 'question', text: 'The question the user answers about the finding.', isExternal: true },
    blocker: { type: 'string', text: 'What blocked the review.', isExternal: true, bounds: { maxLength: 300 } },
    stage: { type: 'string', text: 'The loop stage that was blocked.', isExternal: false }
  };
}

function describeReviewField(entry) {
  return (entry.isExternal ? externalLabel() + ' ' : '') + entry.text;
}

function rejectedFindingTexts() {
  return {
    finding_id: findingIdField(),
    title: { type: 'string', text: reviewFieldTexts().title.text, isExternal: true },
    record: { type: 'string', text: 'The path and section of the recorded decision the reviewer cites.', isExternal: true }
  };
}

function buildFindingItemSchema(texts) {
  const properties = {};
  for (const [name, entry] of Object.entries(texts)) {
    properties[name] = buildReviewFieldSchema(name, entry);
  }
  return { type: 'object', additionalProperties: false, required: Object.keys(texts), properties: properties };
}

function reviewOptionIds() {
  return ['A', 'B', 'C', 'D'];
}

function buildLabelledText(maxLength, text) {
  return { type: 'string', maxLength: maxLength, description: externalLabel() + ' ' + text };
}

function buildUserQuestionSchema(description) {
  const option = {
    type: 'object',
    additionalProperties: false,
    required: ['id', 'summary'],
    properties: {
      id: { type: 'string', enum: reviewOptionIds(), description: 'The option id, by position: A first.' },
      summary: buildLabelledText(160, 'What picking this option does.'),
      destructive: buildDestructiveListSchema(externalLabel() + ' Each change it makes in a gate category.')
    }
  };
  const recommendation = {
    type: 'object',
    additionalProperties: false,
    required: ['option_id', 'strength', 'why'],
    description: 'The option the reviewer recommends.',
    properties: {
      option_id: { type: 'string', enum: reviewOptionIds(), description: 'The id of that option.' },
      strength: { type: 'string', enum: ['strong', 'weak', 'none'], description: 'How sure the reviewer is.' },
      why: buildLabelledText(200, 'Why that option.')
    }
  };
  const gate = {
    type: 'object',
    additionalProperties: false,
    required: ['irreversible', 'architectural'],
    description: 'The reviewer\'s read of the recommended option.',
    properties: {
      irreversible: { type: 'boolean', description: 'true when the recommended option cannot be undone.' },
      architectural: { type: 'boolean', description: 'true when the recommended option changes how the system is built.' }
    }
  };
  return {
    type: 'object',
    description: description,
    additionalProperties: false,
    required: ['found', 'ask', 'options', 'recommendation', 'gate'],
    properties: {
      found: buildLabelledText(200, 'The claim of the finding and its impact.'),
      ask: buildLabelledText(200, 'The question, on one line.'),
      options: { type: 'array', minItems: 2, maxItems: 4, description: 'The choices, 2 to 4.', items: option },
      recommendation: recommendation,
      gate: gate
    }
  };
}

function buildReviewFieldSchema(name, entry) {
  const description = describeReviewField(entry);
  if (entry.type === 'question') {
    return buildUserQuestionSchema(description);
  }
  if (entry.type === 'list') {
    if (entry.maxItems === undefined) {
      throw new Error('buildReviewFieldSchema: field ' + name + ' is a list with no maxItems');
    }
    const itemDescription = (entry.isExternal ? externalLabel() + ' ' : '') + 'One entry.';
    const items = Object.assign({ type: 'string', description: itemDescription }, entry.itemBounds);
    return { type: 'array', description: description, minItems: 1, maxItems: entry.maxItems, items: items };
  }
  if (entry.type === 'string') {
    return Object.assign({ type: 'string', description: description }, entry.bounds);
  }
  throw new Error('buildReviewFieldSchema: field ' + name + ' has type ' + JSON.stringify(entry.type) + ', which states no domain');
}

function buildReviewSchema() {
  const properties = {
    exit_reason: { type: 'string', enum: Object.keys(localReviewRoutes()), description: 'Why the review loop ended.' },
    iterations_completed: { type: 'integer', description: 'How many review iterations ran.' },
    findings_resolved: { type: 'integer', description: 'How many findings the loop fixed.' },
    findings_open: { type: 'integer', description: 'How many findings are still open.' },
    fix_commits_exist: { type: 'boolean', description: 'true when the loop committed at least one fix.' },
    ledger_path: { type: 'string', description: 'The path of the fix ledger.' },
    rejected_findings: { type: 'array', description: externalLabel() + ' Every finding the loop rejected under a recorded decision, empty when none.', maxItems: 50, items: buildFindingItemSchema(rejectedFindingTexts()) }
  };
  for (const [name, entry] of Object.entries(reviewFieldTexts())) {
    properties[name] = buildReviewFieldSchema(name, entry);
  }
  const variants = {};
  for (const [exitReason, fields] of Object.entries(reviewExitFields())) {
    variants[exitReason] = { required: fields, optional: [] };
  }
  return buildTaggedSchema({
    tag: 'exit_reason',
    properties: properties,
    required: ['exit_reason', 'iterations_completed', 'findings_resolved', 'findings_open', 'fix_commits_exist', 'ledger_path', 'rejected_findings'],
    variants: variants
  });
}
