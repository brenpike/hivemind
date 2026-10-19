/*
 * schema.js: checks a value against the JSON Schema subset the decision
 * brief schema uses.
 *
 * Inputs
 *   validateSchema(schema, value)
 *     schema  a JSON Schema object (BRIEF_SCHEMA once built).
 *     value   any value, such as a decision brief from the model.
 *   supportedSchemaKeywords()
 *     no input.
 *
 * Outputs
 *   validateSchema  {ok, errors}. errors lists one string per violation,
 *                   each naming the path from '$' and the failed keyword.
 *                   ok is true only when errors is empty.
 *   supportedSchemaKeywords  every keyword validateSchema accepts.
 *
 * Invariants
 *   Pure: no clock, no randomness, no I/O. The schema is a parameter.
 *   Validation keywords: type (one string), enum, required, properties,
 *   additionalProperties (false only), items, minItems. Annotation keywords
 *   $schema, title and description are accepted and change nothing.
 *   Fails closed: the whole schema is walked before the value is read, and
 *   any other keyword, a non-object schema, or a keyword value of the wrong
 *   shape throws. A schema edit that adds a keyword cannot pass unchecked.
 *   A property whose value is undefined counts as absent, as it does in JSON.
 *   type object means a plain object: not null and not an array.
 *   When type fails, the other keywords at that path are not checked.
 *   Every string value whose schema has type string and no enum must hold a
 *   non-whitespace character. An enum governs when present, so an enum may
 *   list the empty string.
 *
 * Why
 *   A brief is written by a model and read by decide(). A hand-kept check
 *   drifts from the schema one field at a time. Checking against the schema
 *   itself keeps the two the same by construction.
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
    'minItems'
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
  return schema.type === 'string' && schema.enum === undefined && value.trim() === '';
}

function collectSchemaErrors(schema, value, path, errors) {
  if (schema.type !== undefined && !matchesSchemaType(schema.type, value)) {
    errors.push(path + ': type ' + schema.type + ' expected');
    return;
  }
  if (isBlankSchemaString(schema, value)) {
    errors.push(path + ': type string: blank');
  }
  if (schema.enum !== undefined && schema.enum.indexOf(value) === -1) {
    errors.push(path + ': enum: not one of ' + schema.enum.join(', '));
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
      errors.push(path + ': additionalProperties: unexpected ' + name);
    }
  }
}

function collectArrayErrors(schema, list, path, errors) {
  if (schema.minItems !== undefined && list.length < schema.minItems) {
    errors.push(path + ': minItems: fewer than ' + schema.minItems + ' items');
  }
  if (schema.items !== undefined) {
    list.forEach((item, index) => collectSchemaErrors(schema.items, item, path + '[' + index + ']', errors));
  }
}
