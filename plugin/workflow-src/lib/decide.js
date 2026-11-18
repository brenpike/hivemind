/*
 * decide.js: the only place an autonomy decision is resolved.
 *
 * Inputs
 *   resolveLevel(value, table)
 *     value  the autonomy level asked for. May be absent.
 *     table  the parsed decision autonomy table (AUTONOMY_TABLE once built).
 *   decide({kind, level, brief, listed}, table, schema)
 *     kind   the decision kind. Fixed by the call site in code.
 *     level  the autonomy level. Resolved through resolveLevel.
 *     brief  a decision brief, checked against schema.
 *     listed optional array of the listReasons() names the caller sees
 *            hold: outside_limits only. Any other value, a non-array,
 *            beyond_request or repeats_surface included, throws.
 *     table  as above.
 *     schema the parsed decision brief schema (BRIEF_SCHEMA once built).
 *
 * Outputs
 *   resolveLevel  table.default_level when value is undefined, null or the
 *                 empty string; value when it is in table.levels; otherwise 'low'.
 *   decide        {action: 'ask', reason} or
 *                 {action: 'take', reason: 'auto', listed}. listed is a new
 *                 array of the listReasons() names that hold, in
 *                 listReasons() order: beyond_request when the recommended
 *                 option has beyond_request true, the others when the caller
 *                 passed them.
 *   askReasons    the closed Ask Set: every reason a well formed brief from
 *                 a known kind can ask, in check order.
 *   listReasons   the names a take may be listed under for veto before merge,
 *                 beyond_request first; a caller may pass every other one.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O. The table and the schema are
 *   parameters, never globals.
 *   Fails closed: the checks run in this order and the first one that fires
 *   makes it ask: hard_stop, malformed_brief, recommendation_not_an_option,
 *   unknown_kind, table_surface, bad_cell, gate_irreversible,
 *   gate_architectural, gate_safety, no_recommendation. It takes only when
 *   every check passes.
 *   Only askReasons() asks for a well formed brief, a table kind and a table
 *   cell of auto or surface. malformed_brief and recommendation_not_an_option
 *   name a defective brief, unknown_kind and bad_cell a defective caller or
 *   table; a caller can tell them from the Ask Set.
 *   A listed name never makes it ask; it only rides on a take.
 *   A missing schema, or one with a keyword validateSchema does not
 *   support, throws on every call, so decide never takes on a partial check.
 *   brief.kind and brief.id are checked by the schema but never pick the
 *   rule. The kind comes from the call site.
 *   Criticality never makes it ask. A weak recommendation is taken.
 *   A recommended option with reversible false asks gate_irreversible, even
 *   when gate.irreversible is false: the option field is checked, not only
 *   the gate flag.
 *   A recommended option with a non-empty destructive list asks gate_safety,
 *   even when gate.safety is false, for every kind, review kinds included:
 *   only the user's own reply approves a destructive change, so a run never
 *   takes one (security-policy.md, Destructive Fix Confirmation Gate).
 *   A recommended option with beyond_request true is well formed only with
 *   strength strong and effort trivial or small; then a take lists it.
 *   An unknown level resolves to 'low', the most cautious level.
 *   A brief is malformed when validateSchema(schema, brief) reports any
 *   error, when no option has beyond_request false, so a brief always
 *   offers the in-request option, or when its recommended option goes
 *   beyond the request without a strong recommendation of trivial or small
 *   effort. recommendation_not_an_option fires when option ids repeat or
 *   recommendation.option_id names none of them.
 *
 * Why
 *   ADR-0037, amendment 2026-11-07 (issue 549): the closed Ask Set.
 *   Issue 587: a remediation plan that repeats a surface is no longer a
 *   list reason; its brief sets gate.architectural, so it asks.
 */

function askReasons() {
  return ['hard_stop', 'table_surface', 'gate_irreversible', 'gate_architectural', 'gate_safety', 'no_recommendation'];
}

function listReasons() {
  return ['beyond_request', 'outside_limits'];
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

function decide({ kind, level, brief, listed }, table, schema) {
  const [hardStop, tableSurface, gateIrreversible, gateArchitectural, gateSafety, noRecommendation] = askReasons();
  const callerListed = checkCallerListed(listed);
  const briefCheck = validateSchema(schema, brief);
  const resolvedLevel = resolveLevel(level, table);
  if (table.hard_stops.some((stop) => stop.hard_stop === kind)) {
    return askFor(hardStop);
  }
  if (!briefCheck.ok || !hasInRequestOption(brief) || isBeyondRequestUnearned(brief)) {
    return askFor('malformed_brief');
  }
  if (!isRecommendationAnOption(brief)) {
    return askFor('recommendation_not_an_option');
  }
  const row = table.rows.find((candidate) => candidate.kind === kind);
  if (row === undefined) {
    return askFor('unknown_kind');
  }
  const cell = row[resolvedLevel];
  if (cell === 'surface') {
    return askFor(tableSurface);
  }
  if (cell !== 'auto') {
    return askFor('bad_cell');
  }
  if (brief.gate.irreversible || hasRecommendedOption(brief, (option) => option.reversible === false)) {
    return askFor(gateIrreversible);
  }
  if (brief.gate.architectural) {
    return askFor(gateArchitectural);
  }
  if (brief.gate.safety || hasRecommendedOption(brief, (option) => Array.isArray(option.destructive) && option.destructive.length > 0)) {
    return askFor(gateSafety);
  }
  if (brief.recommendation.strength === 'none') {
    return askFor(noRecommendation);
  }
  return { action: 'take', reason: 'auto', listed: collectListed(brief, callerListed) };
}

function checkCallerListed(listed) {
  if (listed === undefined) {
    return [];
  }
  if (!Array.isArray(listed)) {
    throw new Error('decide: listed must be an array, got ' + JSON.stringify(listed));
  }
  const callerNames = listReasons().slice(1);
  for (const name of listed) {
    if (callerNames.indexOf(name) === -1) {
      throw new Error('decide: unknown listed name ' + JSON.stringify(name));
    }
  }
  return listed;
}

function collectListed(brief, callerListed) {
  return listReasons().filter((name, index) => (index === 0 ? hasRecommendedOption(brief, (option) => option.beyond_request === true) : callerListed.includes(name)));
}

function askFor(reason) {
  return { action: 'ask', reason: reason };
}

/**
 * Returns whether an option whose id is the recommended option_id
 * satisfies predicate.
 */
function hasRecommendedOption(brief, predicate) {
  return brief.options.some((option) => option.id === brief.recommendation.option_id && predicate(option));
}

function isBeyondRequestUnearned(brief) {
  const isStrong = brief.recommendation.strength === 'strong';
  return hasRecommendedOption(brief, (option) => option.beyond_request === true && !(isStrong && (option.effort === 'trivial' || option.effort === 'small')));
}

function hasInRequestOption(brief) {
  return brief.options.some((option) => option.beyond_request === false);
}

function isRecommendationAnOption(brief) {
  const optionIds = brief.options.map((option) => option.id);
  const idsAreUnique = optionIds.every((optionId, index) => optionIds.indexOf(optionId) === index);
  return idsAreUnique && optionIds.indexOf(brief.recommendation.option_id) !== -1;
}
