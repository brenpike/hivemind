/*
 * schema.js: checks a value against the JSON Schema subset the plugin's
 * schemas use, such as the decision brief schema, builds a step result
 * schema whose fields depend on one tag field, and makes the agent copy of
 * a schema.
 *
 * Inputs
 *   validateSchema(schema, value)
 *     schema  a JSON Schema object (BRIEF_SCHEMA once built).
 *     value   any value, such as a decision brief from the model.
 *   supportedSchemaKeywords()
 *     no input.
 *   buildTaggedSchema(spec)
 *     spec  {tag, properties, required, variants}, the one table of a
 *           result whose fields depend on one tag field.
 *       tag         the name of the tag field.
 *       properties  every field with its full schema, the tag included
 *                   with its enum.
 *       required    the fields every outcome carries, the tag included.
 *                   These are the shared fields.
 *       variants    one entry per tag enum value, {required, optional}:
 *                   the fields only that value carries.
 *   toAgentSchema(schema)
 *     schema  a schema, such as one buildTaggedSchema built.
 *
 * Outputs
 *   validateSchema  {ok, errors}. errors lists one string per violation,
 *                   each naming the path from '$' and the failed keyword.
 *                   ok is true only when errors is empty. Each error is one
 *                   line. Every name in it comes from the schema, except an
 *                   unexpected key, which comes from the value: it is named
 *                   as is when it holds only letters, digits, _ and -, and
 *                   JSON-encoded otherwise.
 *   supportedSchemaKeywords  every keyword validateSchema accepts.
 *   buildTaggedSchema  {type: 'object', additionalProperties: false,
 *                   required, properties, anyOf}. anyOf holds one branch
 *                   per tag value, in enum order. Each branch is an
 *                   allowlist in the facts schema form: additionalProperties
 *                   false, the tag as {enum: [value]}, every shared field
 *                   and every field of that value as a {} placeholder, and
 *                   required set to that value's required list. Each field
 *                   that is not shared gets ' Only with <tag> <values>.'
 *                   appended to its description, or that sentence alone
 *                   when it has none. The values are the tag values that
 *                   list the field, in enum order, joined as 'a or b' or
 *                   'a, b or c'. A field that is shared and also named by
 *                   a variant counts as shared and gets no sentence.
 *                   Throws when the tag is not a required property with a
 *                   non-empty enum, a shared field is not in properties, a
 *                   variant is not a tag value, a tag value has no
 *                   variant, a variant names a field not in properties, or
 *                   a field that is not shared is listed by no variant.
 *   toAgentSchema   a deep copy of schema with every anyOf removed, at any
 *                   depth, and nothing else changed. schema is never
 *                   changed.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O. The schema is a parameter.
 *   Validation keywords: type (one string), enum, required, properties,
 *   additionalProperties (false only), items, minItems, maxItems, minLength,
 *   maxLength, pattern, anyOf. Annotation keywords $schema, title and description are accepted
 *   and change nothing.
 *   Fails closed: the whole schema is walked before the value is read, and
 *   any other keyword, a non-object schema, or a keyword value of the wrong
 *   shape throws. A schema edit that adds a keyword cannot pass unchecked.
 *   anyOf must be a non-empty array of schema objects, and every branch is
 *   walked even when no value reaches it, so a bad unreachable branch throws.
 *   A property whose value is undefined counts as absent, as it does in JSON.
 *   type object means a plain object: not null and not an array.
 *   When type fails, the other keywords at that path are not checked,
 *   anyOf included.
 *   minLength and maxLength count Unicode code points, not UTF-16 units, and
 *   apply to any string value, with or without type. They ignore non-string
 *   values.
 *   pattern must be a string that compiles as new RegExp(pattern, 'u'). It
 *   applies to any string value, with or without type, and ignores
 *   non-string values. It is not anchored for the caller: a schema that
 *   needs a whole-string match writes ^ and $ itself.
 *   A value passes anyOf when at least one branch gives no errors. Otherwise
 *   anyOf adds exactly one error at that path, and no branch error is kept.
 *   Every string value whose schema has type string, no enum and no
 *   minLength must hold a non-whitespace character. An enum or a minLength
 *   governs when present, so an enum may list the empty string and a
 *   minLength may accept a whitespace-only string. maxLength does not govern.
 *   Every value whose schema has type integer must be zero or more, inside
 *   anyOf branches too. Every integer the plugin's schemas hold is a count,
 *   a size or an id, so a negative one is never valid.
 *
 * Why
 *   A brief is written by a model and read by decide(). A hand-kept check
 *   drifts from the schema one field at a time. Checking against the schema
 *   itself keeps the two the same by construction.
 *   anyOf is the one combinator here because the structured outputs docs list
 *   anyOf as supported and do not list if, then, else, oneOf or not. A schema
 *   that uses anyOf can still be an agent output schema.
 *   Integers are zero or more by default, with no keyword, because every
 *   integer the plugin's schemas hold is a count, a size or an id, and the
 *   structured outputs docs list no numeric bound keyword such as minimum.
 *   A model-written count can then never be negative, as a model-written
 *   string can never be blank.
 *   buildTaggedSchema puts the tie between an outcome and its fields in the
 *   schema. A flat list of every outcome's fields kept that tie only in
 *   description prose, so no check rejected a field from another outcome.
 *   One table gives both the anyOf branches and the 'Only with' sentences,
 *   so the two cannot drift apart.
 *   toAgentSchema exists because the Messages API rejects a tool
 *   input_schema with anyOf at its top level. So every agent gets the flat
 *   copy and the script checks the full schema with validateSchema.
 *   maxItems, like maxLength, is outside the strict structured-output
 *   subset. It relies on the Workflow agent schema check and on the script
 *   check here. The ADR-0037 harness record never tested it.
 *   pattern is checked here too, though the harness enforces it: the
 *   ADR-0037 harness record (Amendment 2026-10-26, pattern row) shows a
 *   breach rejected. The script check keeps the full schema the one check
 *   of agent() output, as for every other keyword.
 *   The harness record of ADR-0037 (Amendment 2026-10-26) keeps every
 *   check of agent() output: the root anyOf probe failed with that API
 *   error, a failed agent() call returned null to the script, no probe
 *   used an agentType, and no probe showed a type string breach rejected.
 */

function supportedSchemaKeywords() {
  return [
    '$schema',
    'title',
    'description',
    'type',
    'enum',
    'required',
    'properties',
    'additionalProperties',
    'items',
    'minItems',
    'maxItems',
    'minLength',
    'maxLength',
    'pattern',
    'anyOf'
  ];
}

function schemaTypeNames() {
  return ['object', 'array', 'string', 'boolean', 'number', 'integer', 'null'];
}

function validateSchema(schema, value) {
  assertSupportedSchema(schema, '$');
  const errors = [];
  collectSchemaErrors(schema, value, '$', errors);
  return { ok: errors.length === 0, errors: errors };
}

function isSchemaRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function failSchema(path, message) {
  throw new Error('validateSchema: ' + path + ': ' + message);
}

function assertSupportedSchema(schema, path) {
  if (!isSchemaRecord(schema)) {
    failSchema(path, 'schema must be an object');
  }
  for (const keyword of Object.keys(schema)) {
    if (supportedSchemaKeywords().indexOf(keyword) === -1) {
      failSchema(path, 'unsupported keyword ' + keyword);
    }
  }
  assertKeywordShapes(schema, path);
  if (schema.properties !== undefined) {
    for (const name of Object.keys(schema.properties)) {
      assertSupportedSchema(schema.properties[name], path + '.' + name);
    }
  }
  if (schema.items !== undefined) {
    assertSupportedSchema(schema.items, path + '[]');
  }
  if (schema.anyOf !== undefined) {
    schema.anyOf.forEach((branch, index) => assertSupportedSchema(branch, path + '.anyOf[' + index + ']'));
  }
}

function isPrimitiveEnumValue(candidate) {
  return candidate === null || ['string', 'number', 'boolean'].indexOf(typeof candidate) !== -1;
}

function assertKeywordShapes(schema, path) {
  if (schema.type !== undefined && schemaTypeNames().indexOf(schema.type) === -1) {
    failSchema(path, 'type must be one of ' + schemaTypeNames().join(', '));
  }
  if (schema.enum !== undefined && !(Array.isArray(schema.enum) && schema.enum.every(isPrimitiveEnumValue))) {
    failSchema(path, 'enum must be an array of strings, numbers, booleans or null');
  }
  const requiredIsValid = Array.isArray(schema.required) && schema.required.every((name) => typeof name === 'string');
  if (schema.required !== undefined && !requiredIsValid) {
    failSchema(path, 'required must be an array of strings');
  }
  if (schema.properties !== undefined && !isSchemaRecord(schema.properties)) {
    failSchema(path, 'properties must be an object');
  }
  if (schema.additionalProperties !== undefined && schema.additionalProperties !== false) {
    failSchema(path, 'additionalProperties must be false');
  }
  if (schema.minItems !== undefined && !(Number.isInteger(schema.minItems) && schema.minItems >= 0)) {
    failSchema(path, 'minItems must be a non-negative integer');
  }
  if (schema.maxItems !== undefined && !(Number.isInteger(schema.maxItems) && schema.maxItems >= 0)) {
    failSchema(path, 'maxItems must be a non-negative integer');
  }
  if (schema.minLength !== undefined && !(Number.isInteger(schema.minLength) && schema.minLength >= 0)) {
    failSchema(path, 'minLength must be a non-negative integer');
  }
  if (schema.maxLength !== undefined && !(Number.isInteger(schema.maxLength) && schema.maxLength >= 0)) {
    failSchema(path, 'maxLength must be a non-negative integer');
  }
  if (schema.pattern !== undefined) {
    assertSchemaPattern(schema.pattern, path);
  }
  if (schema.anyOf !== undefined && !(Array.isArray(schema.anyOf) && schema.anyOf.length > 0)) {
    failSchema(path, 'anyOf must be a non-empty array of schemas');
  }
}

function assertSchemaPattern(pattern, path) {
  if (typeof pattern !== 'string') {
    failSchema(path, 'pattern must be a string');
  }
  try {
    new RegExp(pattern, 'u');
  } catch (error) {
    failSchema(path, 'pattern does not compile: ' + error.message);
  }
}

function matchesSchemaType(typeName, value) {
  if (typeName === 'object') {
    return isSchemaRecord(value);
  }
  if (typeName === 'array') {
    return Array.isArray(value);
  }
  if (typeName === 'null') {
    return value === null;
  }
  if (typeName === 'integer') {
    return Number.isInteger(value);
  }
  if (typeName === 'number') {
    return typeof value === 'number' && Number.isFinite(value);
  }
  return typeof value === typeName;
}

function listPresentKeys(record) {
  return Object.keys(record).filter((name) => record[name] !== undefined);
}

function isBlankSchemaString(schema, value) {
  const isGoverned = schema.enum !== undefined || schema.minLength !== undefined;
  return schema.type === 'string' && !isGoverned && value.trim() === '';
}

function isNegativeSchemaInteger(schema, value) {
  return schema.type === 'integer' && value < 0;
}

function countSchemaCodePoints(text) {
  return [...text].length;
}

function isShortSchemaString(schema, value) {
  return schema.minLength !== undefined && typeof value === 'string' && countSchemaCodePoints(value) < schema.minLength;
}

function isLongSchemaString(schema, value) {
  return schema.maxLength !== undefined && typeof value === 'string' && countSchemaCodePoints(value) > schema.maxLength;
}

function isUnmatchedSchemaString(schema, value) {
  return schema.pattern !== undefined && typeof value === 'string' && !new RegExp(schema.pattern, 'u').test(value);
}

function matchesSchemaBranch(branch, value, path) {
  const branchErrors = [];
  collectSchemaErrors(branch, value, path, branchErrors);
  return branchErrors.length === 0;
}

function collectSchemaErrors(schema, value, path, errors) {
  if (schema.type !== undefined && !matchesSchemaType(schema.type, value)) {
    errors.push(path + ': type ' + schema.type + ' expected');
    return;
  }
  if (isBlankSchemaString(schema, value)) {
    errors.push(path + ': type string: blank');
  }
  if (isNegativeSchemaInteger(schema, value)) {
    errors.push(path + ': type integer: negative');
  }
  if (isShortSchemaString(schema, value)) {
    errors.push(path + ': minLength: fewer than ' + schema.minLength + ' characters');
  }
  if (isLongSchemaString(schema, value)) {
    errors.push(path + ': maxLength: more than ' + schema.maxLength + ' characters');
  }
  if (isUnmatchedSchemaString(schema, value)) {
    errors.push(path + ': pattern: does not match ' + schema.pattern);
  }
  if (schema.enum !== undefined && schema.enum.indexOf(value) === -1) {
    errors.push(path + ': enum: not one of ' + schema.enum.join(', '));
  }
  if (schema.anyOf !== undefined && !schema.anyOf.some((branch) => matchesSchemaBranch(branch, value, path))) {
    errors.push(path + ': anyOf: matches no branch');
  }
  if (isSchemaRecord(value)) {
    collectObjectErrors(schema, value, path, errors);
  }
  if (Array.isArray(value)) {
    collectArrayErrors(schema, value, path, errors);
  }
}

function collectObjectErrors(schema, record, path, errors) {
  const presentKeys = listPresentKeys(record);
  const properties = schema.properties === undefined ? {} : schema.properties;
  for (const name of schema.required === undefined ? [] : schema.required) {
    if (presentKeys.indexOf(name) === -1) {
      errors.push(path + ': required: missing ' + name);
    }
  }
  for (const name of presentKeys) {
    const isListed = Object.prototype.hasOwnProperty.call(properties, name);
    if (isListed) {
      collectSchemaErrors(properties[name], record[name], path + '.' + name, errors);
    } else if (schema.additionalProperties === false) {
      errors.push(path + ': additionalProperties: unexpected ' + describeUnexpectedSchemaKey(name));
    }
  }
}

function describeUnexpectedSchemaKey(name) {
  return /^[A-Za-z0-9_-]+$/.test(name) ? name : JSON.stringify(name);
}

function collectArrayErrors(schema, list, path, errors) {
  if (schema.minItems !== undefined && list.length < schema.minItems) {
    errors.push(path + ': minItems: fewer than ' + schema.minItems + ' items');
  }
  if (schema.maxItems !== undefined && list.length > schema.maxItems) {
    errors.push(path + ': maxItems: more than ' + schema.maxItems + ' items');
  }
  if (schema.items !== undefined) {
    list.forEach((item, index) => collectSchemaErrors(schema.items, item, path + '[' + index + ']', errors));
  }
}

function buildTaggedSchema(spec) {
  const tagValues = readTagValues(spec);
  assertTaggedSpec(spec, tagValues);
  const properties = copySchemaValue(spec.properties);
  for (const name of Object.keys(properties)) {
    if (spec.required.indexOf(name) === -1) {
      properties[name].description = describeTaggedField(properties[name].description, spec.tag, listTaggedValues(spec, tagValues, name));
    }
  }
  return {
    type: 'object',
    additionalProperties: false,
    required: spec.required.slice(),
    properties: properties,
    anyOf: tagValues.map((value) => buildTaggedBranch(spec, value))
  };
}

function failTaggedSchema(message) {
  throw new Error('buildTaggedSchema: ' + message);
}

function readTagValues(spec) {
  if (!isSchemaRecord(spec) || !isSchemaRecord(spec.properties) || !Array.isArray(spec.required) || !isSchemaRecord(spec.variants)) {
    failTaggedSchema('spec must hold tag, properties, required and variants');
  }
  const tagSchema = spec.properties[spec.tag];
  if (!isSchemaRecord(tagSchema) || !Array.isArray(tagSchema.enum) || tagSchema.enum.length === 0) {
    failTaggedSchema('tag ' + spec.tag + ' must be a property with a non-empty enum');
  }
  if (spec.required.indexOf(spec.tag) === -1) {
    failTaggedSchema('tag ' + spec.tag + ' must be required');
  }
  return tagSchema.enum.slice();
}

function listVariantFields(variant) {
  return variant.required.concat(variant.optional);
}

function assertTaggedSpec(spec, tagValues) {
  const isKnownField = (name) => Object.prototype.hasOwnProperty.call(spec.properties, name);
  for (const name of spec.required) {
    if (!isKnownField(name)) {
      failTaggedSchema('required field ' + name + ' is not in properties');
    }
  }
  for (const value of Object.keys(spec.variants)) {
    if (tagValues.indexOf(value) === -1) {
      failTaggedSchema('variant ' + value + ' is not a value of tag ' + spec.tag);
    }
  }
  for (const value of tagValues) {
    assertTaggedVariant(spec, value, isKnownField);
  }
  for (const name of Object.keys(spec.properties)) {
    if (spec.required.indexOf(name) === -1 && listTaggedValues(spec, tagValues, name).length === 0) {
      failTaggedSchema('field ' + name + ' is not shared and no variant lists it');
    }
  }
}

function assertTaggedVariant(spec, value, isKnownField) {
  const variant = spec.variants[value];
  if (!Object.prototype.hasOwnProperty.call(spec.variants, value) || !isSchemaRecord(variant)) {
    failTaggedSchema('tag value ' + value + ' has no variant');
  }
  if (!Array.isArray(variant.required) || !Array.isArray(variant.optional)) {
    failTaggedSchema('variant ' + value + ' must hold required and optional lists');
  }
  for (const name of listVariantFields(variant)) {
    if (!isKnownField(name)) {
      failTaggedSchema('variant ' + value + ' names field ' + name + ', which is not in properties');
    }
  }
}

function listTaggedValues(spec, tagValues, name) {
  return tagValues.filter((value) => listVariantFields(spec.variants[value]).indexOf(name) !== -1);
}

function joinTagValues(values) {
  if (values.length < 3) {
    return values.join(' or ');
  }
  return values.slice(0, -1).join(', ') + ' or ' + values[values.length - 1];
}

function describeTaggedField(description, tag, values) {
  const sentence = 'Only with ' + tag + ' ' + joinTagValues(values) + '.';
  return description === undefined ? sentence : description + ' ' + sentence;
}

function buildTaggedBranch(spec, value) {
  const variant = spec.variants[value];
  const variantFields = listVariantFields(variant);
  const properties = {};
  for (const name of Object.keys(spec.properties)) {
    if (name === spec.tag) {
      properties[name] = { enum: [value] };
    } else if (spec.required.indexOf(name) !== -1 || variantFields.indexOf(name) !== -1) {
      properties[name] = {};
    }
  }
  return { additionalProperties: false, required: variant.required.slice(), properties: properties };
}

function copySchemaValue(value) {
  return JSON.parse(JSON.stringify(value));
}

function toAgentSchema(schema) {
  return removeSchemaAnyOf(copySchemaValue(schema));
}

function removeSchemaAnyOf(schema) {
  if (!isSchemaRecord(schema)) {
    return schema;
  }
  delete schema.anyOf;
  if (isSchemaRecord(schema.properties)) {
    Object.values(schema.properties).forEach(removeSchemaAnyOf);
  }
  if (schema.items !== undefined) {
    removeSchemaAnyOf(schema.items);
  }
  return schema;
}
