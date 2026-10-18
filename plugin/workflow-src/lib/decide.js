/*
 * decide.js: the only place an autonomy decision is resolved.
 *
 * Inputs
 *   resolveLevel(value, table)
 *     value  the autonomy level asked for. May be absent.
 *     table  the parsed decision autonomy table (AUTONOMY_TABLE once built).
 *   decide({kind, level, brief}, table)
 *     kind   the decision kind. Fixed by the call site in code.
 *     level  the autonomy level. Resolved through resolveLevel.
 *     brief  a decision brief shaped by the decision brief schema.
 *     table  as above.
 *
 * Outputs
 *   resolveLevel  table.default_level when value is undefined, null or the
 *                 empty string; value when it is in table.levels; otherwise 'low'.
 *   decide        {action: 'take' | 'ask', reason}. reason is one of
 *                 decisionReasons(). Only reason 'auto' comes with 'take'.
 *   decisionReasons  every reason code decide can return, in check order.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O. The table is a parameter.
 *   Fails closed: each check runs in decisionReasons() order and the first
 *   one that fires makes it ask. It takes only when every check passes.
 *   brief.kind and brief.id are never read. The kind comes from the call site.
 *   Criticality never makes it ask. A weak recommendation is taken.
 *   An unknown level resolves to 'low', the most cautious level.
 *   A brief is malformed when a field decide or the renderer reads is missing
 *   or has the wrong type, when options is empty, or when
 *   recommendation.strength or an assumption origin is outside its enum.
 *
 * Why
 *   The model that writes a brief must not pick the rule that lets it act.
 *   The rule is picked by the caller in code and resolved in one tested
 *   function, so every decision site behaves the same way.
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

function decide({ kind, level, brief }, table) {
  const resolvedLevel = resolveLevel(level, table);
  if (table.hard_stops.some((stop) => stop.hard_stop === kind)) {
    return askFor('hard_stop');
  }
  if (!isWellFormedBrief(brief)) {
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
  if (brief.gate.irreversible) {
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

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasFieldsOfType(record, names, typeName) {
  return isRecord(record) && names.every((name) => typeof record[name] === typeName);
}

function isWellFormedOption(option) {
  return hasFieldsOfType(option, ['id', 'summary', 'steel_man', 'straw_man', 'effort', 'value'], 'string')
    && typeof option.reversible === 'boolean';
}

function isWellFormedAssumption(assumption) {
  return hasFieldsOfType(assumption, ['statement', 'origin', 'evidence'], 'string')
    && ['user', 'repo', 'assumed'].indexOf(assumption.origin) !== -1;
}

function isWellFormedBrief(brief) {
  if (!isRecord(brief) || typeof brief.problem !== 'string') {
    return false;
  }
  if (brief.verbatim !== undefined && typeof brief.verbatim !== 'string') {
    return false;
  }
  if (!hasFieldsOfType(brief.criticality, ['level', 'likelihood', 'blast_radius', 'if_ignored'], 'string')) {
    return false;
  }
  if (!Array.isArray(brief.options) || brief.options.length === 0 || !brief.options.every(isWellFormedOption)) {
    return false;
  }
  if (!hasFieldsOfType(brief.recommendation, ['option_id', 'strength', 'why'], 'string')) {
    return false;
  }
  if (['strong', 'weak', 'none'].indexOf(brief.recommendation.strength) === -1) {
    return false;
  }
  if (!Array.isArray(brief.assumptions) || !brief.assumptions.every(isWellFormedAssumption)) {
    return false;
  }
  return hasFieldsOfType(brief.gate, ['irreversible', 'architectural', 'safety'], 'boolean');
}

function isRecommendationAnOption(brief) {
  const optionIds = brief.options.map((option) => option.id);
  const idsAreUnique = optionIds.every((optionId, index) => optionIds.indexOf(optionId) === index);
  return idsAreUnique && optionIds.indexOf(brief.recommendation.option_id) !== -1;
}
