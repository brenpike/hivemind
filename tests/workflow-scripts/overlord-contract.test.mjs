import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { loadLibs } from './harness.mjs';
import { buildWorkflow } from '../../tools/build_workflows.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const overlordText = readFileSync(repoRoot + 'plugin/agents/overlord.md', 'utf8').replace(/\r/g, '');
const resultLib = loadLibs([repoRoot + 'plugin/workflow-src/lib/result.js']);
const DELIVERY_ID = 'standard-delivery';
const DELIVERY_ARGS_LEAD = 'When `<id>` is `standard-delivery`, the launch args also hold ';
const VALID_LAUNCH_VALUES = { request: 'Add a cache to the facts step', trunk: 'main', references: [12], local_review: false, draft: true };
const INVALID_LAUNCH_VALUES = { request: '   ', trunk: '-main', references: ['twelve'], local_review: 'yes', draft: 'no' };

/**
 * Builds standard-delivery in memory and runs it without its last
 * statement, so its top-level functions can be called directly.
 */
function loadDeliveryFunctions() {
  const source = buildWorkflow(repoRoot, DELIVERY_ID);
  const lastStatement = '\nreturn await runDelivery(args);\n';
  assert.ok(source.endsWith(lastStatement), 'standard-delivery main.js ends with the runDelivery call');
  const body = source.replace(/^export const meta\b/, 'const meta').slice(0, -lastStatement.length + 1);
  const context = vm.createContext({});
  vm.runInContext(body, context, { filename: DELIVERY_ID + ' functions' });
  return context;
}

function splitFrontmatter(text) {
  const match = text.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  assert.ok(match, 'overlord.md has a YAML frontmatter block');
  return { frontmatter: match[1], body: match[2] };
}

function readToolNames(frontmatter) {
  const lines = frontmatter.split('\n');
  const start = lines.indexOf('tools:');
  assert.notEqual(start, -1, 'frontmatter has a tools: key');
  const toolNames = [];
  for (const line of lines.slice(start + 1)) {
    const item = line.match(/^\s+-\s+([A-Za-z]+)/);
    if (!item) {
      break;
    }
    toolNames.push(item[1]);
  }
  return toolNames;
}

function readSection(body, heading) {
  const lines = body.split('\n');
  const start = lines.indexOf(heading);
  assert.notEqual(start, -1, `body has the heading ${heading}`);
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => line.startsWith('## '));
  return (end === -1 ? rest : rest.slice(0, end)).join('\n');
}

function normalizeWhitespace(text) {
  return text.replace(/\s+/g, ' ').trim();
}

function assertSectionHasPhrases(heading, phrases) {
  const sectionText = normalizeWhitespace(readSection(body, heading));
  for (const phrase of phrases) {
    assert.ok(sectionText.includes(normalizeWhitespace(phrase)), `${heading} lacks ${phrase}`);
  }
}

const { frontmatter, body } = splitFrontmatter(overlordText);
const engineSection = readSection(body, '## Engine');
const defectParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('A notice is cut only when its result is not one complete JSON object;')) ?? '';
const relayParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('Only the harness completion notice is the run\'s result, never your own summary.')) ?? '';
const stateExecutionSection = readSection(body, '## Workflow State Execution');
const questionGateParagraph = stateExecutionSection.split('\n\n').find((paragraph) => paragraph.startsWith('**Question gate.**')) ?? '';
const engineSentences = engineSection.split(/(?<=[.!?])\s+/);
const handOffParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('After you show `message`, when the result carries `pr`,')) ?? '';
const stopParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('When the user asks to stop a launched run')) ?? '';

function readDeliveryLaunchArgNames() {
  const template = engineSection.match(/only these args: `(\{[^`]*\})`/);
  assert.ok(template, '## Engine has a launch args template');
  const templateNames = [...template[1].matchAll(/"([a-z_]+)":/g)].map((match) => match[1]);
  const deliverySentence = engineSentences.find((sentence) => sentence.startsWith(DELIVERY_ARGS_LEAD));
  assert.ok(deliverySentence, `## Engine lacks a sentence starting ${DELIVERY_ARGS_LEAD}`);
  const deliveryNames = [...deliverySentence.slice(DELIVERY_ARGS_LEAD.length).matchAll(/`([a-z_]+)`/g)].map((match) => match[1]);
  return [...templateNames, ...deliveryNames];
}

describe('overlord frontmatter tools', () => {
  const toolNames = readToolNames(frontmatter);
  test('tools include Workflow', () => {
    assert.ok(toolNames.includes('Workflow'), `tools are ${JSON.stringify(toolNames)}`);
  });
  test('tools include TaskStop', () => {
    assert.ok(toolNames.includes('TaskStop'), `tools are ${JSON.stringify(toolNames)}`);
  });
  test('tools exclude Edit', () => {
    assert.equal(toolNames.includes('Edit'), false, `tools are ${JSON.stringify(toolNames)}`);
  });
});

describe('overlord Engine section', () => {
  test('the first H2 is Engine', () => {
    const firstHeading = body.split('\n').find((line) => line.startsWith('## '));
    assert.equal(firstHeading, '## Engine');
  });
  test('Engine comes after the opening paragraph and before the Load and follow line', () => {
    const paragraphs = body.trim().split('\n\n');
    assert.match(paragraphs[0], /^You are the control plane/);
    assert.equal(paragraphs[1], '## Engine');
    assert.ok(body.indexOf('## Engine') < body.indexOf('Load and follow: '));
  });
  test('Engine names hivemind:route-workflow', () => {
    assert.ok(engineSection.includes('`hivemind:route-workflow`'));
  });
  for (const fieldName of structuredClone(resultLib.resultFields())) {
    test(`Engine names the result field ${fieldName}`, () => {
      assert.match(engineSection, new RegExp('`[^`\\n]*\\b' + fieldName + '\\b[^`\\n]*`'), `${fieldName} is missing from ## Engine`);
    });
  }
  test('Engine resumes with one flat object: the launch args, the keys of resume_args at the top level, then the reply arg', () => {
    const replyName = resultLib.replyField();
    assert.ok(engineSection.includes('with args set to one flat object: the launch args, then each key of `resume_args` (today `answers` and `build`) at the top level of args, never nested under a `resume_args` key, then `' + replyName + '` set to the user\'s reply verbatim.'), `${replyName} resume clause is missing from ## Engine`);
  });
  test('Engine never nests the resume args under a resume_args key', () => {
    assert.ok(engineSection.includes('never nested under a `resume_args` key'), '## Engine resume clause lacks the never-nested clause');
    assert.ok(!engineSection.includes('the launch args plus `resume_args`'), '## Engine still adds resume_args as one nested key');
  });
  test('Engine resumes the same run by name with resumeFromRunId', () => {
    for (const phrase of ['resume the same run by name', '`name` set to the name you launched (`hivemind:<id>`)', '`resumeFromRunId` from the launch']) {
      assert.ok(engineSection.includes(phrase), `## Engine resume clause lacks ${phrase}`);
    }
  });
  test('Engine names scriptPath only in never-clauses', () => {
    const scriptPathSentences = engineSection.split(/(?<=[.!?])\s+/).filter((sentence) => sentence.includes('scriptPath'));
    assert.notEqual(scriptPathSentences.length, 0, '## Engine has no never-clause for scriptPath');
    for (const sentence of scriptPathSentences) {
      assert.match(sentence, /\b[Nn]ever\b[^.]*`scriptPath`/, `## Engine names scriptPath outside a never-clause: ${sentence}`);
    }
  });
  test('Engine limits launch and resume args and adds no runner instructions', () => {
    for (const phrase of ['launch it by name with the `Workflow` tool and only these args: `{', 'When `<id>` is `standard-delivery`, the launch args also hold `local_review` and `draft`.', 'Resume args hold only the launch args, the keys of `resume_args` and `reply`.', 'Add no instruction, note or summary for the workflow\'s agents to launch or resume args.', 'They take their task only from the script.']) {
      assert.ok(engineSection.includes(phrase), `## Engine args clause lacks ${phrase}`);
    }
  });
  test('Engine keeps the routing outcome out of chat', () => {
    for (const phrase of ['Act on its routing outcome without printing it.']) {
      assert.ok(engineSection.includes(phrase), `## Engine routing clause lacks ${phrase}`);
    }
  });
  test('Engine no longer names the dropped answer_key field', () => {
    assert.ok(!engineSection.includes('answer_key'));
  });
  test('Engine no longer names the dropped decisions field', () => {
    assert.ok(!engineSection.includes('decisions'));
  });
  test('Engine treats a cut notice as a defect that does not resume or read a file, and counts the run as failed', () => {
    assert.notEqual(defectParagraph, '', '## Engine has a paragraph starting A notice is cut only when its result is not one complete JSON object;');
    for (const phrase of ['A cut notice is a defect', 'do not resume', 'read any file', 'The run counts as failed.']) {
      assert.ok(defectParagraph.includes(phrase), `defect paragraph lacks ${phrase}`);
    }
  });
  test('Engine no longer carries the old cut-notice rule', () => {
    for (const phrase of ['come before `message`', 'Never read that file.']) {
      assert.ok(!engineSection.includes(phrase), `## Engine still contains ${phrase}`);
    }
  });
  test('Engine does not mention Bash', () => {
    const bashCount = (engineSection.match(/Bash/g) ?? []).length;
    assert.equal(bashCount, 0, '## Engine mentions Bash');
  });
  test('Engine launch args name the trunk and references', () => {
    for (const phrase of ['"trunk": "<the resolved trunk>"', '"references": [']) {
      assert.ok(engineSection.includes(phrase), `## Engine launch args lack ${phrase}`);
    }
  });
  test('Engine states the fallback clause', () => {
    for (const phrase of [
      'For `standard-delivery`, launch only when `## Instinct` picks the engine',
      'If a `standard-delivery` launch is refused or blocked (denied, not found, or workflows turned off), or the started run fails or ends blocked, say so in one line and continue on Instinct from the branch\'s last commit without asking;',
      'the final report says it switched and where the engine stopped.',
      'Uncommitted edits the failed run left stop the takeover per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State) and are never discarded',
      'Instinct never relaunches the engine.',
      'A run the user stopped does not fall back.',
      'Any other workflow runs a refused or blocked launch on the state machine and reports a started run as it ended.',
    ]) {
      assert.ok(normalizeWhitespace(engineSection).includes(normalizeWhitespace(phrase)), `## Engine fallback clause lacks ${phrase}`);
    }
  });
});

describe('overlord standard-delivery launch args', () => {
  const deliveryFunctions = loadDeliveryFunctions();
  const launchArgNames = readDeliveryLaunchArgNames();
  test('Engine names local_review and draft for standard-delivery', () => {
    assert.ok(launchArgNames.includes('local_review'), `launch args are ${JSON.stringify(launchArgNames)}`);
    assert.ok(launchArgNames.includes('draft'), `launch args are ${JSON.stringify(launchArgNames)}`);
    for (const phrase of ['`local_review` is `false` when the Codex plugin is unavailable in this session or the request skips local review, else `true`.', '`draft` is `true` only when the request asks for a draft pull request, else `false`.']) {
      assert.ok(engineSection.includes(phrase), `## Engine lacks ${phrase}`);
    }
  });
  test('a launch with every Engine launch arg valid passes readDeliveryLaunch', () => {
    const launchArgs = {};
    for (const argName of launchArgNames) {
      assert.ok(Object.hasOwn(VALID_LAUNCH_VALUES, argName), `no valid test value for the launch arg ${argName}`);
      launchArgs[argName] = VALID_LAUNCH_VALUES[argName];
    }
    const launch = deliveryFunctions.readDeliveryLaunch(launchArgs);
    assert.equal(launch.problem, undefined, `readDeliveryLaunch refused ${JSON.stringify(launchArgs)}: ${launch.problem}`);
    assert.equal(launch.localReview, VALID_LAUNCH_VALUES.local_review);
    assert.equal(launch.draft, VALID_LAUNCH_VALUES.draft);
  });
  for (const argName of launchArgNames) {
    test(`a bad ${argName} launch arg makes readDeliveryLaunch return a problem`, () => {
      assert.ok(Object.hasOwn(INVALID_LAUNCH_VALUES, argName), `no invalid test value for the launch arg ${argName}`);
      const launchArgs = { ...VALID_LAUNCH_VALUES, [argName]: INVALID_LAUNCH_VALUES[argName] };
      const launch = deliveryFunctions.readDeliveryLaunch(launchArgs);
      assert.equal(typeof launch.problem, 'string', `readDeliveryLaunch accepted ${argName} ${JSON.stringify(INVALID_LAUNCH_VALUES[argName])}`);
    });
  }
});

describe('overlord pull request hand-off and opt-in', () => {
  test('the pr hand-off names the watch pointer, pr-feedback-remediation and intake watch', () => {
    assert.notEqual(handOffParagraph, '', '## Engine has a paragraph starting After you show `message`, when the result carries `pr`,');
    for (const phrase of ['`## Review Remediation Posture` (Default post-PR watch)', '`HIVEMIND_SKIP_PR_WATCH`', 'run `pr-feedback-remediation` on the workflow state machine', 'with its intake outcome `watch`', 'as the Reflex tail does', 'With no `pr`, there is no watch.']) {
      assert.ok(handOffParagraph.includes(phrase), `pr hand-off paragraph lacks ${phrase}`);
    }
  });
  test('the pr hand-off does not restate the watch predicate', () => {
    for (const phrase of ['if and only if', '`not_requested`', '`watch_requested`']) {
      assert.ok(!handOffParagraph.includes(phrase), `pr hand-off paragraph restates the watch predicate: ${phrase}`);
    }
  });
  test('the Reflex tail points to the watch predicate and does not restate it', () => {
    const reflexSection = readSection(body, '## Reflex (Ledger-Skip)');
    assert.ok(reflexSection.includes('under the canonical predicate stated once under `## Review Remediation Posture` (Default post-PR watch)'), '## Reflex (Ledger-Skip) lacks the watch predicate pointer');
    for (const phrase of ['if and only if', '`not_requested`', '`watch_requested`']) {
      assert.ok(!reflexSection.includes(phrase), `## Reflex (Ledger-Skip) restates the watch predicate: ${phrase}`);
    }
  });
  test('the never-enter rule covers only the launched request', () => {
    assert.ok(engineSection.includes('Do not enter the workflow state machine or create a run ledger for the launched request.'));
    assert.ok(handOffParagraph.includes('covers only the launched request'));
  });
  test('Engine states the approval prompt opt-in, that a No interrupts the turn, and the permissions.deny opt-out', () => {
    for (const phrase of ['The `Workflow` tool\'s approval prompt is the only opt-in to a workflow.', 'A No there interrupts the turn: nothing runs and nothing falls back.', 'A `Workflow(hivemind:<id>)` entry in `permissions.deny` is the opt-out: it denies the launch, which falls back as stated next']) {
      assert.ok(engineSection.includes(phrase), `## Engine lacks ${phrase}`);
    }
  });
});

describe('overlord stop and resume of a stopped run', () => {
  test('Engine has a stop paragraph', () => {
    assert.notEqual(stopParagraph, '', '## Engine has no paragraph starting When the user asks to stop a launched run');
  });
  test('the stop paragraph calls TaskStop with the taskId from any surface', () => {
    for (const phrase of ['from any surface including Remote Control', 'call `TaskStop` with the `taskId` the `Workflow` tool returned for the running invocation', 'say in one line that the run stopped']) {
      assert.ok(stopParagraph.includes(phrase), `stop paragraph lacks ${phrase}`);
    }
  });
  test('the stop paragraph stops a run only when the user asks', () => {
    assert.ok(stopParagraph.includes('Stop a run only when the user asks.'), 'stop paragraph lacks the only-when-the-user-asks clause');
  });
  test('the stop paragraph resumes a stopped run by name from its completed results', () => {
    for (const phrase of ['A stopped run keeps every completed agent result.', 'When the user asks to go on, resume it by name', '`resumeFromRunId`', 'the args of its last launch or resume']) {
      assert.ok(stopParagraph.includes(phrase), `stop paragraph lacks ${phrase}`);
    }
  });
});

describe('overlord relay and cut rules', () => {
  test('the relay paragraph HTML-unescapes message', () => {
    assert.notEqual(relayParagraph, '', '## Engine has a paragraph starting Only the harness completion notice is the run\'s result, never your own summary.');
    for (const phrase of ['HTML-escapes its result', 'JSON string value', '`&lt;`', '`&gt;`', '`&amp;`']) {
      assert.ok(relayParagraph.includes(phrase), `relay paragraph lacks ${phrase}`);
    }
  });
  test('the relay paragraph makes message the whole reply in the user\'s output style', () => {
    for (const phrase of ['for a question and for the final report alike, as your whole reply in the user\'s active output style, such as a terse style.']) {
      assert.ok(relayParagraph.includes(phrase), `relay paragraph lacks ${phrase}`);
    }
  });
  test('the relay paragraph keeps labels, tokens, numbers, paths and identifiers exact', () => {
    const exactKeepClause = 'Keep exactly as written every question label, every option and reply token, the recommendation, and every number, path, URL, commit, branch and identifier.';
    assert.ok(relayParagraph.includes(exactKeepClause), `relay paragraph lacks ${exactKeepClause}`);
  });
  test('the relay paragraph adds nothing and drops nothing the user must answer', () => {
    const noCommentClause = 'Add no line before or after it and no comment on what it says, and drop nothing the user must answer.';
    assert.ok(relayParagraph.includes(noCommentClause), `relay paragraph lacks ${noCommentClause}`);
  });
  test('the relay paragraph no longer forbids restyling message', () => {
    for (const phrase of ['verbatim as your whole reply', 'no character changed']) {
      assert.ok(!relayParagraph.includes(phrase), `relay paragraph still contains ${phrase}`);
    }
  });
  test('the defect paragraph decides cut from the envelope, not from message text', () => {
    assert.ok(defectParagraph.includes('not one complete JSON object'), 'defect paragraph lacks not one complete JSON object');
    assert.ok(defectParagraph.includes('text inside `message`'), 'defect paragraph lacks text inside `message`');
    assert.ok(defectParagraph.includes('never makes a notice cut'), 'defect paragraph lacks never makes a notice cut');
  });
  test('Engine no longer points at result.js', () => {
    assert.ok(!engineSection.includes('result.js'), '## Engine still points at result.js');
  });
});

describe('overlord workflow definition reads', () => {
  test('overlord.md has no pointer into the workflows directory', () => {
    assert.ok(!overlordText.includes('${CLAUDE_PLUGIN_ROOT}/workflows/'), 'overlord.md still points into ${CLAUDE_PLUGIN_ROOT}/workflows/');
  });
  test('Workflow State Execution takes the state from the engine output lines', () => {
    for (const phrase of ['`current_state`', '`state_definition`', '`hivemind:init-run-ledger`', '`hivemind:record-state-result`']) {
      assert.ok(stateExecutionSection.includes(phrase), `## Workflow State Execution lacks ${phrase}`);
    }
  });
  test('Workflow State Execution gathers facts before cerebrate and stops on a cut', () => {
    for (const phrase of ['`hivemind:gather-facts`', '`facts_file`', '`facts_lines`', '`cut`']) {
      assert.ok(stateExecutionSection.includes(phrase), `## Workflow State Execution lacks ${phrase}`);
    }
  });
  test('Workflow State Execution has a Question gate paragraph', () => {
    assert.notEqual(questionGateParagraph, '', '## Workflow State Execution has no paragraph starting **Question gate.**');
  });
  test('the Question gate paragraph routes to the question user gate and asks the user', () => {
    for (const phrase of ['routes to the `question` user gate', 'record that result', 'ask the user the question in plain words, with its options and a recommendation, and wait']) {
      assert.ok(questionGateParagraph.includes(phrase), `Question gate paragraph lacks ${phrase}`);
    }
  });
  test('the Question gate outcome names the state that asked, or cancelled', () => {
    for (const phrase of ['Record the gate outcome as the name of the state that asked (the ledger\'s previous state)', 'or `cancelled` when the reply cancels']) {
      assert.ok(questionGateParagraph.includes(phrase), `Question gate paragraph lacks ${phrase}`);
    }
  });
  test('the Question gate reruns the state that asked with user_answer', () => {
    for (const phrase of ['run the state that asked again and pass `user_answer`', 'the user\'s reply verbatim', '`candidate_url`', 'take it as their `user_answer` input', 'the user\'s decision on that question']) {
      assert.ok(questionGateParagraph.includes(phrase), `Question gate paragraph lacks ${phrase}`);
    }
  });
  test('the Question gate carries user_answer into planning', () => {
    assert.ok(questionGateParagraph.includes('escalates to a planning state, that planning delegation carries the same `user_answer`'), 'Question gate paragraph lacks the carry into planning');
  });
  test('the Question gate keeps GitHub text as external content', () => {
    assert.ok(questionGateParagraph.includes('external content'), 'Question gate paragraph lacks external content');
    assert.ok(questionGateParagraph.includes('data-boundary sentence'), 'Question gate paragraph lacks the data-boundary sentence');
  });
  test('the Question gate states the resume rule', () => {
    for (const phrase of ['On `## Resume On Start` at `question`, the reply is not in the ledger', 'run that state again without an answer, so it asks again']) {
      assert.ok(questionGateParagraph.includes(phrase), `Question gate paragraph lacks ${phrase}`);
    }
  });
  test('Workflow State Execution sends the scan rule to the gather-facts consumer rules', () => {
    assert.ok(stateExecutionSection.includes('the scan its consumer rules require does not pass'), '## Workflow State Execution does not defer the scan rule to the skill consumer rules');
    assert.ok(stateExecutionSection.includes('the texts the scan did not account for'), '## Workflow State Execution does not surface the texts the scan did not account for');
  });
});

// These check each phrase is present inside its own `## ` section, never its meaning, per tests/policy/README.md (1. Honest capability statement); ADR-0039 decisions 2 to 4.
describe('overlord section-scoped Instinct pins', () => {
  test('readSection stops at the next H2 and keeps an H3 inside its parent', () => {
    const syntheticBody = ['## First', 'first text', '### Child', 'child text', '## Second', 'second text'].join('\n');
    const firstSection = readSection(syntheticBody, '## First');
    assert.ok(!firstSection.includes('second text'), 'a phrase in the next ## section was found in the section before it');
    assert.ok(firstSection.includes('child text'), 'a ### subsection left its parent section');
  });
  test('Instinct states the permanent path, the default choice, the plan and the one-commit PR gate', () => {
    assertSectionHasPhrases('## Instinct', [
      'Instinct, a permanent delivery path beside the script engine, is also its `standard-delivery` fallback',
      'A `standard-delivery` request that names neither path takes the engine when it carries a `working_branch.base` ref',
      'otherwise ask the user which, with your recommendation',
      'Every run needs a plan before any edit',
      'the PR by `hivemind:open-plan-pr` only on a commit that validation and local review (unless the Codex plugin is unavailable or the request skips it) both passed on',
      'a later commit rerunning both',
    ]);
  });
  test('Parallel Delegation Safety holds on any path and forbids git writes and repo-global mutations', () => {
    assertSectionHasPhrases('## Parallel Delegation Safety', [
      'These rules hold for every wave, on any path.',
      'Each wave delegation must forbid git writes',
      'Each wave delegation must forbid repo-global mutations',
    ]);
  });
});
