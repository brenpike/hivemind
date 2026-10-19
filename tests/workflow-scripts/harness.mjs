/**
 * Test harness for workflow script libraries and built workflow scripts.
 *
 * loadLibs(paths)
 *   Reads each file, strips CR, and runs them in order in one node:vm
 *   context. Returns the context: each top-level function declaration of the
 *   libs is a property of it.
 *
 * loadWorkflow(builtPath)
 *   Reads a built workflow script and strips CR. Asserts the file has exactly
 *   one `export const meta` and that it is the first statement, then rewrites
 *   it to `const meta`. Returns {run}.
 *   run({args, results}) runs the body as an async function in a fresh
 *   context and resolves to {result, meta, calls, phases, logs, failures}.
 *     args     the `args` global.
 *     results  map from agent label to the value agent() resolves to, or to
 *              a function (prompt, opts, callIndex) returning that value.
 *              Values are cloned before the script sees them. A label with
 *              no entry makes that agent() call reject.
 *     calls    every agent() call as {prompt, opts}, in call order.
 *     failures errors that parallel() or pipeline() turned into null.
 *
 * Every context mirrors the Workflow runtime: Date.now(), Math.random(),
 * Date() and a no-argument new Date() throw. Stubbed globals: args, agent,
 * parallel, pipeline, phase, log, budget, workflow. parallel() and
 * pipeline() resolve a failed task to null, as the runtime does.
 */
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const GUARD_SOURCE = `
(function guardNondeterminism(realDate, realMath) {
  function refuse(name) {
    return function refused() {
      throw new Error(name + ' throws inside a workflow script');
    };
  }
  function GuardedDate(...parts) {
    if (new.target === undefined) {
      throw new Error('Date() throws inside a workflow script');
    }
    if (parts.length === 0) {
      throw new Error('new Date() with no argument throws inside a workflow script');
    }
    return Reflect.construct(realDate, parts, new.target);
  }
  Object.setPrototypeOf(GuardedDate, realDate);
  GuardedDate.prototype = realDate.prototype;
  Object.defineProperty(GuardedDate, 'now', { value: refuse('Date.now()'), writable: true, configurable: true });
  realMath.random = refuse('Math.random()');
  globalThis.Date = GuardedDate;
})(Date, Math);
`;

const MAX_FAN_OUT = 4096;

function readScript(path) {
  return readFileSync(path, 'utf8').replace(/\r/g, '');
}

function createGuardedContext(globals) {
  const context = vm.createContext({ ...globals });
  vm.runInContext(GUARD_SOURCE, context, { filename: 'harness-guard.js' });
  return context;
}

export function loadLibs(paths) {
  const context = createGuardedContext({});
  for (const path of paths) {
    vm.runInContext(readScript(path), context, { filename: path });
  }
  return context;
}

function stripLeadingComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '').trim();
}

export function loadWorkflow(builtPath) {
  const source = readScript(builtPath);
  const metaCount = (source.match(/export\s+const\s+meta\b/g) || []).length;
  if (metaCount !== 1) {
    throw new Error(`${builtPath}: expected exactly one "export const meta", found ${metaCount}`);
  }
  const metaIndex = source.search(/^export const meta\b/m);
  if (metaIndex === -1 || stripLeadingComments(source.slice(0, metaIndex)) !== '') {
    throw new Error(`${builtPath}: "export const meta" must be the first statement`);
  }
  const body = source.slice(0, metaIndex) + source.slice(metaIndex).replace(/^export const meta\b/, 'const meta');
  return { run: (options) => runWorkflowBody(builtPath, body, options || {}) };
}

function resolveScriptedResult(results, prompt, opts, callIndex) {
  const label = opts ? opts.label : undefined;
  if (!Object.prototype.hasOwnProperty.call(results, label)) {
    return Promise.reject(new Error(`no scripted result for agent label ${JSON.stringify(label)}`));
  }
  const scripted = results[label];
  const value = typeof scripted === 'function' ? scripted(prompt, opts, callIndex) : scripted;
  return Promise.resolve(value).then((resolved) => structuredClone(resolved));
}

function assertFanOutList(name, list) {
  if (!Array.isArray(list)) {
    throw new TypeError(`${name}() takes an array`);
  }
  if (list.length > MAX_FAN_OUT) {
    throw new RangeError(`${name}() accepts at most ${MAX_FAN_OUT} items, got ${list.length}`);
  }
}

async function runPipelineItem(item, index, stages, failures) {
  let value = item;
  try {
    for (const stage of stages) {
      value = await stage(value, item, index);
    }
    return value;
  } catch (error) {
    failures.push(error);
    return null;
  }
}

function createWorkflowGlobals(args, results) {
  const record = { calls: [], phases: [], logs: [], failures: [] };
  const settleTask = (task) => Promise.resolve().then(() => task()).catch((error) => {
    record.failures.push(error);
    return null;
  });
  const globals = {
    args,
    agent: (prompt, opts) => {
      record.calls.push({ prompt, opts });
      return resolveScriptedResult(results, prompt, opts, record.calls.length - 1);
    },
    parallel: async (tasks) => {
      assertFanOutList('parallel', tasks);
      return Promise.all(tasks.map(settleTask));
    },
    pipeline: async (items, ...stages) => {
      assertFanOutList('pipeline', items);
      return Promise.all(items.map((item, index) => runPipelineItem(item, index, stages, record.failures)));
    },
    phase: (title) => {
      record.phases.push(title);
    },
    log: (message) => {
      record.logs.push(message);
    },
    budget: { total: null, spent: () => 0, remaining: () => Infinity },
    workflow: async () => {
      throw new Error('workflow() is not supported by the harness');
    }
  };
  return { globals, record };
}

async function runWorkflowBody(builtPath, body, { args, results = {} }) {
  const { globals, record } = createWorkflowGlobals(args, results);
  const context = createGuardedContext(globals);
  const wrapped = '(async function (exposeMetaReader) { function readHarnessMeta() { return meta; } '
    + 'exposeMetaReader(readHarnessMeta); ' + body + '\n})';
  const runBody = vm.runInContext(wrapped, context, { filename: builtPath });
  let metaReader;
  const result = await runBody((reader) => {
    metaReader = reader;
  });
  return { result, meta: metaReader(), ...record };
}
