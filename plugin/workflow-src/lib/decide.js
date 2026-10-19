/*
 * decide.js: the only place an autonomy decision is resolved.
 *
 * Inputs
 *   resolveLevel(value, table)
 *     value  the autonomy level asked for. May be absent.
 *     table  the parsed decision autonomy table (AUTONOMY_TABLE once built).
 *   decide({kind, level, brief}, table, schema)
 *     kind   the decision kind. Fixed by the call site in code.
 *     level  the autonomy level. Resolved through resolveLevel.
 *     brief  a decision brief, checked against schema.
 *     table  as above.
 *     schema the parsed decision brief schema (BRIEF_SCHEMA once built).
 *
 * Outputs
 *   resolveLevel  table.default_level when value is undefined, null or the
 *                 empty string; value when it is in table.levels; otherwise 'low'.
 *   decide        {action: 'take' | 'ask', reason}. reason is one of
 *                 decisionReasons(). Only reason 'auto' comes with 'take'.
 *   decisionReasons  every reason code decide can return, in check order.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O. The table and the schema are
 *   parameters, never globals.
 *   Fails closed: each check runs in decisionReasons() order and the first
 *   one that fires makes it ask. It takes only when every check passes.
 *   A missing schema, or one with a keyword validateSchema does not
 *   support, throws on every call, so decide never takes on a partial check.
 *   brief.kind and brief.id are checked by the schema but never pick the
 *   rule. The kind comes from the call site.
 *   Criticality never makes it ask. A weak recommendation is taken.
 *   A recommended option with reversible false asks gate_irreversible, even
 *   when gate.irreversible is false: the option field is checked, not only
 *   the gate flag.
 *   An unknown level resolves to 'low', the most cautious level.
 *   A brief is malformed when validateSchema(schema, brief) reports any
 *   error. Only the checks the schema cannot express are written here:
 *   option ids are unique, recommendation.option_id names one of them,
 *   strength none, and reversible false on the recommended option.
 *
 * Why
 *   The model that writes a brief must not pick the rule that lets it act.
 *   The rule is picked by the caller in code and resolved in one tested
 *   function, so every decision site behaves the same way. The brief check
 *   comes from the schema the model writes to, so the two cannot drift.
 */

function decisionReasons() {
  return [
    'hard_stop',
    'malformed_brief',
    'unknown_kind',
    'table_surface',
    'bad_cell',
    'gate_irreversible',
    'gate_architectural',
    'gate_safety',
    'no_recommendation',
    'recommendation_not_an_option',
    'auto'
  ];
}

function resolveLevel(value, table) {
  if (value === undefined || value === null || value === '') {
    return table.default_level;
  }
  if (table.levels.indexOf(value) !== -1) {
    return value;
  }
  return 'low';
}

function decide({ kind, level, brief }, table, schema) {
  const briefCheck = validateSchema(schema, brief);
  const resolvedLevel = resolveLevel(level, table);
  if (table.hard_stops.some((stop) => stop.hard_stop === kind)) {
    return askFor('hard_stop');
  }
  if (!briefCheck.ok) {
    return askFor('malformed_brief');
  }
  const row = table.rows.find((candidate) => candidate.kind === kind);
  if (row === undefined) {
    return askFor('unknown_kind');
  }
  const cell = row[resolvedLevel];
  if (cell === 'surface') {
    return askFor('table_surface');
  }
  if (cell !== 'auto') {
    return askFor('bad_cell');
  }
  if (brief.gate.irreversible || isRecommendedOptionIrreversible(brief)) {
    return askFor('gate_irreversible');
  }
  if (brief.gate.architectural) {
    return askFor('gate_architectural');
  }
  if (brief.gate.safety) {
    return askFor('gate_safety');
  }
  if (brief.recommendation.strength === 'none') {
    return askFor('no_recommendation');
  }
  if (!isRecommendationAnOption(brief)) {
    return askFor('recommendation_not_an_option');
  }
  return { action: 'take', reason: 'auto' };
}

function askFor(reason) {
  return { action: 'ask', reason: reason };
}

function isRecommendedOptionIrreversible(brief) {
  return brief.options.some((option) => option.id === brief.recommendation.option_id && option.reversible === false);
}

function isRecommendationAnOption(brief) {
  const optionIds = brief.options.map((option) => option.id);
  const idsAreUnique = optionIds.every((optionId, index) => optionIds.indexOf(optionId) === index);
  return idsAreUnique && optionIds.indexOf(brief.recommendation.option_id) !== -1;
}
