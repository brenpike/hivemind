import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { loadLibs } from './harness.mjs';
import { buildWorkflow } from '../../tools/build_workflows.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const overlordText = readFileSync(repoRoot + 'plugin/agents/overlord.md', 'utf8').replace(/\r/g, '');
const autonomyText = readFileSync(repoRoot + 'plugin/governance/decision-autonomy.md', 'utf8').replace(/\r/g, '');
const doctrineText = readFileSync(repoRoot + 'plugin/governance/remediation-doctrine.md', 'utf8').replace(/\r/g, '');
const resultLib = loadLibs([repoRoot + 'plugin/workflow-src/lib/result.js']);
const DELIVERY_ID = 'standard-delivery';
const REMEDIATION_ID = 'pr-feedback-remediation';
const DELIVERY_ARGS_LEAD = 'When `<id>` is `standard-delivery`, the launch args also hold ';
const DELIVERY_ARGS_SENTENCE = DELIVERY_ARGS_LEAD + '`local_review`, `draft` and `attribution`, and `decisions` only if the user settled a decision for this request before launch.';
const DECISIONS_ENTRY_SENTENCE = 'Each `decisions` entry is one reply of the user\'s that settled one, word for word, after the question it answers, word for word, when it answers one; never your summary.';
const VALID_ATTRIBUTION = { commit: 'Co-Authored-By: Example Model <noreply@example.com>\nExample-Session: https://example.com/session', pr: 'Generated with Example\n\thttps://example.com/session' };
const VALID_LAUNCH_VALUES = { request: 'Add a cache to the facts step', trunk: 'main', references: [12], local_review: false, draft: true, decisions: ['Keep the cache in memory only.'], attribution: VALID_ATTRIBUTION };
const INVALID_LAUNCH_VALUES = { request: '   ', trunk: '-main', references: ['twelve'], local_review: 'yes', draft: 'no', decisions: ['   '], attribution: 'Co-Authored-By: Example Model' };
const VALID_ATTRIBUTION_VALUES = [['commit and pr text', VALID_ATTRIBUTION], ['an empty object', {}], ['an absent arg', undefined]];
const INVALID_ATTRIBUTION_VALUES = [['null', null], ['a string', 'Co-Authored-By: Example Model'], ['an array', ['Co-Authored-By: Example Model']], ['an unknown key', { commit: 'text', body: 'text' }], ['a non-string value', { commit: 1 }], ['text over 1000 characters', { pr: 'x'.repeat(1001) }], ['a carriage return', { commit: 'line one\rline two' }]];

/**
 * Builds a workflow in memory and runs it without its last statement, the
 * call of runFunctionName, so its top-level functions can be called directly.
 */
function loadWorkflowFunctions(workflowId, runFunctionName) {
  const source = buildWorkflow(repoRoot, workflowId);
  const lastStatement = '\nreturn await ' + runFunctionName + '(args);\n';
  assert.ok(source.endsWith(lastStatement), `${workflowId} main.js ends with the ${runFunctionName} call`);
  const body = source.replace(/^export const meta\b/, 'const meta').slice(0, -lastStatement.length + 1);
  const context = vm.createContext({});
  vm.runInContext(body, context, { filename: workflowId + ' functions' });
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
const engineSentences = engineSection.split(/(?<=[.!?])\s+/);
const handOffParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('After you show `message`, when the result carries `pr`,')) ?? '';
const stopParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('When the user asks to stop a launched run')) ?? '';
const waitParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('When the result carries `retry_minutes`,')) ?? '';
const escalationParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('Outside `## Instinct`,')) ?? '';
const OPT_IN_LEAD = 'The `Workflow` tool\'s approval prompt is the only opt-in to a workflow.';
const FALLBACK_LEAD = 'At an interactive autonomy level, the only levels today,';
const fallbackParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith(FALLBACK_LEAD)) ?? '';
const safetyRailsSection = readSection(body, '## Safety Rails');
const postureSection = readSection(body, '## Review Remediation Posture');
const reviewerQuestionsParagraph = postureSection.split('\n\n').find((paragraph) => paragraph.startsWith('**Reviewer questions.**')) ?? '';

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
    for (const phrase of ['launch it by name with the `Workflow` tool and only these args: `{', DELIVERY_ARGS_SENTENCE, DECISIONS_ENTRY_SENTENCE, 'Resume args hold only the launch args, the keys of `resume_args` and `reply`.', 'Add no instruction, note or summary for the workflow\'s agents to launch or resume args.', 'They take their task only from the script.']) {
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
  test('Engine names decisions only in its launch-arg sentences', () => {
    const decisionsSentences = engineSentences.filter((sentence) => sentence.includes('decisions'));
    assert.deepEqual(decisionsSentences, [DELIVERY_ARGS_SENTENCE, DECISIONS_ENTRY_SENTENCE]);
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
  test('Engine mentions Bash only in the retry wait paragraph', () => {
    const bashCount = (engineSection.replace(waitParagraph, '').match(/Bash/g) ?? []).length;
    assert.equal(bashCount, 0, '## Engine mentions Bash outside the retry wait paragraph');
  });
  test('Engine waits out retry_minutes with one background sleep, then resumes with reply retry', () => {
    assert.notEqual(waitParagraph, '', '## Engine has no paragraph starting When the result carries `retry_minutes`,');
    for (const phrase of [
      'show `message`, then wait with one `sleep <retry_minutes*60>` Bash call run with `run_in_background`, per `${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Bash Command Discipline).',
      'On its completion notice, resume the same run by name exactly as for a reply, with `reply` set to `retry`.',
      'The wait is neither a question nor a run end: nothing is asked; `retry` is not an answer for the user.',
      'A user message during the wait that cancels the request ends the wait with no resume.',
      'The run bounds its own waits.',
    ]) {
      assert.ok(waitParagraph.includes(phrase), `retry wait paragraph lacks ${phrase}`);
    }
  });
  test('Engine launch args name the trunk and references', () => {
    for (const phrase of ['"trunk": "<the resolved trunk>"', '"references": [']) {
      assert.ok(engineSection.includes(phrase), `## Engine launch args lack ${phrase}`);
    }
  });
  test('Engine states the fallback clause', () => {
    const paragraphs = engineSection.split('\n\n');
    const optInIndex = paragraphs.findIndex((paragraph) => paragraph.startsWith(OPT_IN_LEAD));
    assert.notEqual(optInIndex, -1, `## Engine has no paragraph starting ${OPT_IN_LEAD}`);
    assert.notEqual(fallbackParagraph, '', `## Engine has no paragraph starting ${FALLBACK_LEAD}`);
    assert.equal(paragraphs.indexOf(fallbackParagraph), optInIndex + 1, 'the fallback paragraph does not sit right after the opt-in paragraph');
    for (const phrase of [
      '`standard-delivery`',
      '`analysis-only`',
      '`pr-feedback-remediation`',
      'without asking, said in one line',
      'continues from the branch\'s last commit',
      'A started `standard-delivery` run, except a guide run, that fails or ends blocked',
      'reported as it ended',
      'says it switched and where the run stopped',
      '`${CLAUDE_PLUGIN_ROOT}/governance/definitions.md` (Unsafe Git State)',
      'Instinct never relaunches a workflow.',
      'A run the user stopped does not fall back.',
    ]) {
      assert.ok(normalizeWhitespace(fallbackParagraph).includes(normalizeWhitespace(phrase)), `## Engine fallback paragraph lacks ${phrase}`);
    }
  });
  test('no other Engine paragraph names on Instinct', () => {
    const otherParagraphs = engineSection.split('\n\n').filter((paragraph) => paragraph !== fallbackParagraph);
    for (const paragraph of otherParagraphs) {
      assert.ok(!paragraph.includes('on Instinct'), `an Engine paragraph other than the fallback names on Instinct: ${paragraph}`);
    }
  });
});

describe('overlord standard-delivery launch args', () => {
  const deliveryFunctions = loadWorkflowFunctions(DELIVERY_ID, 'runDelivery');
  const launchArgNames = readDeliveryLaunchArgNames();
  test('Engine names local_review and draft for standard-delivery', () => {
    assert.ok(launchArgNames.includes('local_review'), `launch args are ${JSON.stringify(launchArgNames)}`);
    assert.ok(launchArgNames.includes('draft'), `launch args are ${JSON.stringify(launchArgNames)}`);
    for (const phrase of ['`local_review` is `false` only when the request skips local review, else `true`.', '`draft` is `true` only when the request asks for a draft pull request, else `false`.']) {
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
    assert.equal(JSON.stringify(launch.decisions), JSON.stringify(VALID_LAUNCH_VALUES.decisions));
    assert.deepEqual(structuredClone(launch.attribution), VALID_LAUNCH_VALUES.attribution);
  });
  for (const [label, attribution] of VALID_ATTRIBUTION_VALUES) {
    test(`readDeliveryLaunch takes ${label} as the attribution launch arg`, () => {
      const launchArgs = { ...VALID_LAUNCH_VALUES, attribution: attribution };
      const launch = deliveryFunctions.readDeliveryLaunch(launchArgs);
      assert.equal(launch.problem, undefined, `readDeliveryLaunch refused the attribution ${JSON.stringify(attribution)}: ${launch.problem}`);
      assert.deepEqual(structuredClone(launch.attribution), attribution ?? {});
    });
  }
  for (const [label, attribution] of INVALID_ATTRIBUTION_VALUES) {
    test(`readDeliveryLaunch refuses ${label} as the attribution launch arg`, () => {
      const launch = deliveryFunctions.readDeliveryLaunch({ ...VALID_LAUNCH_VALUES, attribution: attribution });
      assert.equal(typeof launch.problem, 'string', `readDeliveryLaunch accepted the attribution ${JSON.stringify(attribution)}`);
    });
  }
  for (const argName of launchArgNames) {
    test(`a bad ${argName} launch arg makes readDeliveryLaunch return a problem`, () => {
      assert.ok(Object.hasOwn(INVALID_LAUNCH_VALUES, argName), `no invalid test value for the launch arg ${argName}`);
      const launchArgs = { ...VALID_LAUNCH_VALUES, [argName]: INVALID_LAUNCH_VALUES[argName] };
      const launch = deliveryFunctions.readDeliveryLaunch(launchArgs);
      assert.equal(typeof launch.problem, 'string', `readDeliveryLaunch accepted ${argName} ${JSON.stringify(INVALID_LAUNCH_VALUES[argName])}`);
    });
  }
});

describe('overlord guide run', () => {
  const guideMarker = '`hivemind-guide-run: <slug>`';
  const guideRunLead = 'A guide run is a request whose line 1 is exactly ' + guideMarker + '.';
  const guideRunArgNames = ['request', 'references', 'draft'];
  const engineParagraphs = engineSection.split('\n\n').filter((paragraph) => paragraph.trim() !== '');
  const guideRunParagraph = engineParagraphs.find((paragraph) => paragraph.startsWith(guideRunLead)) ?? '';
  const guideSkillText = readFileSync(repoRoot + 'plugin/skills/idea-to-ready/SKILL.md', 'utf8').replace(/\r/g, '');
  const launchArgNames = readDeliveryLaunchArgNames();

  /** Returns each backticked launch arg name in text, in order. */
  function readBacktickedLaunchArgNames(text) {
    return [...text.matchAll(/`([a-z_]+)`/g)].map((match) => match[1]).filter((name) => launchArgNames.includes(name));
  }

  test('Engine has the guide-run paragraph right after its opening paragraph', () => {
    assert.notEqual(guideRunParagraph, '', `## Engine has no paragraph starting ${guideRunLead}`);
    assert.equal(engineParagraphs.indexOf(guideRunParagraph), 1, 'the guide-run paragraph does not sit right after the Engine opening paragraph');
  });
  test('the guide-run paragraph sets request, references from line 2 only, and draft, and returns a failed or blocked run to the guide', () => {
    for (const phrase of [
      guideRunLead,
      '`request` is that whole request',
      '`references` holds only the number in line 2 when line 2 is exactly `Docs pull request: #<n>`, else nothing',
      '`draft` is `true`',
      'A started guide run that fails or ends blocked returns to the guide, which re-derives its stage.',
    ]) {
      assert.ok(guideRunParagraph.includes(phrase), `guide-run paragraph lacks ${phrase}`);
    }
  });
  test('the guide-run paragraph overrides only request, references and draft and restates no launch-arg template', () => {
    const overriddenNames = readBacktickedLaunchArgNames(guideRunParagraph);
    assert.deepEqual([...new Set(overriddenNames)].sort(), [...guideRunArgNames].sort());
    assert.ok(!guideRunParagraph.includes('only these args'), 'guide-run paragraph restates the launch-arg template');
  });
  test('the guide skill names the same marker line and no launch arg', () => {
    assert.ok(guideSkillText.includes(guideMarker), `the guide SKILL.md lacks ${guideMarker}`);
    assert.deepEqual(readBacktickedLaunchArgNames(guideSkillText), [], 'the guide SKILL.md names a launch arg');
  });
});

describe('overlord pull request hand-off and opt-in', () => {
  test('the pr hand-off names the watch pointer and runs hivemind:github-review-loop for the watch', () => {
    assert.notEqual(handOffParagraph, '', '## Engine has a paragraph starting After you show `message`, when the result carries `pr`,');
    for (const phrase of ['`## Review Remediation Posture` (Default post-PR watch)', '`HIVEMIND_SKIP_PR_WATCH`', 'When the rule calls for a watch, run `hivemind:github-review-loop` for that pull request.', 'as the Reflex tail does', 'With no `pr`, there is no watch.']) {
      assert.ok(handOffParagraph.includes(phrase), `pr hand-off paragraph lacks ${phrase}`);
    }
  });
  test('the pr hand-off no longer hands the watch to the state machine', () => {
    for (const phrase of ['state machine', 'run ledger', 'intake outcome `watch`']) {
      assert.ok(!handOffParagraph.includes(phrase), `pr hand-off paragraph still names ${phrase}`);
    }
  });
  test('Engine defines pr for any launched run', () => {
    assert.ok(relayParagraph.includes('`pr`, when present, is the run\'s pull request.'), 'relay paragraph lacks the pr definition');
    assert.ok(!relayParagraph.includes('a delivery run opened or reused'), 'relay paragraph still limits pr to a delivery run');
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
  test('Engine names no state machine and no run ledger', () => {
    assert.doesNotMatch(engineSection, /state.machine/i, '## Engine still names a state machine');
    assert.ok(!engineSection.includes('run ledger'), '## Engine still names a run ledger');
  });
  test('Engine states the approval prompt opt-in, that a No interrupts the turn, and the permissions.deny opt-out', () => {
    for (const phrase of ['The `Workflow` tool\'s approval prompt is the only opt-in to a workflow.', 'A No there interrupts the turn: nothing runs and nothing falls back.', 'A `Workflow(hivemind:<id>)` entry in `permissions.deny` is the opt-out: it denies the launch, which falls back as stated next']) {
      assert.ok(engineSection.includes(phrase), `## Engine lacks ${phrase}`);
    }
  });
});

describe('overlord watch escalation to pr-feedback-remediation', () => {
  const remediationFunctions = loadWorkflowFunctions(REMEDIATION_ID, 'runRemediation');
  test('Engine has the escalation paragraph', () => {
    assert.notEqual(escalationParagraph, '', '## Engine has no paragraph starting Outside `## Instinct`,');
  });
  test('the escalation paragraph launches pr-feedback-remediation by name on both watch exits', () => {
    for (const phrase of ['a watch ending `planner-escalation` or `root-cluster-suspected` launches `pr-feedback-remediation` by name', 'and no other key.']) {
      assert.ok(escalationParagraph.includes(phrase), `escalation paragraph lacks ${phrase}`);
    }
  });
  test('the escalation paragraph excludes Instinct, and Instinct does not name the workflow', () => {
    assert.ok(escalationParagraph.startsWith('Outside `## Instinct`,'), 'escalation paragraph lacks the Instinct exclusion');
    assert.ok(!readSection(body, '## Instinct').includes('pr-feedback-remediation'), '## Instinct names pr-feedback-remediation');
  });
  test('the escalation paragraph runs the watch for a routed request, or launches a one-shot fix', () => {
    for (const phrase of ['A request routed to `pr-feedback-remediation` runs the watch', 'or for a one-shot fix launches as above.']) {
      assert.ok(escalationParagraph.includes(phrase), `escalation paragraph lacks ${phrase}`);
    }
    assert.ok(!escalationParagraph.includes('checks out'), 'escalation paragraph still checks out the PR head itself');
  });
  test('Engine keeps pr-feedback-remediation off the generic routed launch', () => {
    for (const phrase of ['for `pr-feedback-remediation`, only as stated below.', 'Launch no workflow this section does not name, and write no workflow script.']) {
      assert.ok(engineSection.includes(phrase), `## Engine lacks ${phrase}`);
    }
    assert.ok(!engineSection.includes('Launch no other workflow'), '## Engine still forbids every other launch');
  });
  test('the escalation args template, filled, passes readRemediationLaunch', () => {
    const template = escalationParagraph.match(/with args `(\{[^`]*\})` and no other key/);
    assert.ok(template, 'escalation paragraph has an args template');
    const filled = template[1].replace('<PR number>', '42').replace('<the resolved trunk>', 'main').replace('<as above>', JSON.stringify(VALID_ATTRIBUTION));
    const launch = remediationFunctions.readRemediationLaunch(JSON.parse(filled));
    assert.equal(launch.problem, undefined, `readRemediationLaunch refused ${filled}: ${launch.problem}`);
    assert.deepEqual(structuredClone(launch), { trunk: 'main', pr: '42', attribution: VALID_ATTRIBUTION });
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
});

// These check each Safety Rails phrase is present, never its meaning, per tests/policy/README.md (1. Honest capability statement); issue 656.
describe('overlord Safety Rails facts and PR-head rules', () => {
  test('Safety Rails holds on every path', () => {
    assertSectionHasPhrases('## Safety Rails', ['Hard stops on every path you drive: the Reflex tail, a launched workflow and Instinct, its fallback included.']);
  });
  test('Safety Rails gathers facts before cerebrate and stops on a cut', () => {
    for (const phrase of ['`hivemind:gather-facts`', '`facts_file`', '`facts_lines`', '`cut`']) {
      assert.ok(safetyRailsSection.includes(phrase), `## Safety Rails lacks ${phrase}`);
    }
  });
  test('Safety Rails sends the scan rule to the gather-facts consumer rules, and delivery stops nothing', () => {
    assert.ok(safetyRailsSection.includes('the scan its consumer rules require does not pass'), '## Safety Rails does not defer the scan rule to the skill consumer rules');
    assert.ok(safetyRailsSection.includes('the texts the scan did not account for'), '## Safety Rails does not surface the texts the scan did not account for');
    assert.ok(safetyRailsSection.includes('`delivery` and `delivery_stops` stop nothing'), '## Safety Rails lets delivery or delivery_stops stop the run');
  });
  test('Safety Rails checks out the PR head before any reviewer and stops blocked when it cannot', () => {
    assertSectionHasPhrases('## Safety Rails', [
      'Before delegating to any reviewer for an existing pull request, resolve its head branch (e.g. via `gh pr view`) and check it out, so remediation commits land on it.',
      'When the branch cannot be resolved or checked out, stop blocked.',
    ]);
  });
});

// These check the reviewer question rerun rule's phrases in its own paragraph, never its meaning, per tests/policy/README.md (1. Honest capability statement); issue 656.
describe('overlord Reviewer questions', () => {
  test('Review Remediation Posture has a Reviewer questions paragraph', () => {
    assert.notEqual(reviewerQuestionsParagraph, '', '## Review Remediation Posture has no paragraph starting **Reviewer questions.**');
  });
  test('Reviewer questions reruns the run that asked with user_answer', () => {
    for (const phrase of ['then run it again and pass `user_answer`', 'the user\'s reply verbatim', '`candidate_url`', '`hivemind:cerebrate` gets it in the delegation as the decision on that question: the run\'s when marked `decided_by: run`, otherwise the user\'s.']) {
      assert.ok(reviewerQuestionsParagraph.includes(phrase), `Reviewer questions paragraph lacks ${phrase}`);
    }
  });
  test('Reviewer questions carries user_answer into planning', () => {
    assert.ok(reviewerQuestionsParagraph.includes('the planning delegation carries the same `user_answer`'), 'Reviewer questions paragraph lacks the carry into planning');
  });
  test('Reviewer questions keeps GitHub text as external content', () => {
    assert.ok(reviewerQuestionsParagraph.includes('external content'), 'Reviewer questions paragraph lacks external content');
    assert.ok(reviewerQuestionsParagraph.includes('data-boundary sentence'), 'Reviewer questions paragraph lacks the data-boundary sentence');
  });
  test('each pausing exit token has its single home in Reviewer questions', () => {
    for (const token of ['`user-input-required`', '`high-severity-rejection`']) {
      assert.equal(body.split(token).length - 1, 1, `overlord body names ${token} other than exactly once`);
      assert.ok(reviewerQuestionsParagraph.includes(token), `Reviewer questions paragraph lacks ${token}`);
    }
  });
});

// These check each removed section and item stays absent and each kept citation agrees with its heading, never their meaning, per tests/policy/README.md (1. Honest capability statement); issue 656.
describe('overlord one-engine removals and kept pins', () => {
  test('the four deleted sections are absent', () => {
    for (const heading of ['## Workflow State Execution', '## Implement Loop (Wave Execution)', '## Resume On Start', '## Intent-Driven Fallback (Universal)']) {
      assert.ok(!body.split('\n').includes(heading), `overlord body still has ${heading}`);
    }
  });
  test('the overlord body names no removed item', () => {
    assert.doesNotMatch(body, /state.machine/i, 'overlord body still names a state machine');
    assert.doesNotMatch(body, /workflow state/i, 'overlord body still names a workflow state');
    for (const phrase of [
      'run ledger',
      'event.outputs',
      'request.raw',
      'watch_optout_citation',
      'pr_branch_preflight',
      'github_review_decision',
      'user_gate',
      'Question gate',
      'HIVEMIND_ENABLE_DECISION_REPORT',
      '.decision-report-done',
      'Post-Merge Decision Report Trigger',
      'Proactive Zoom-Out Ledger Marker',
      'hivemind:init-run-ledger',
      'hivemind:record-state-result',
      'hivemind:next-wave',
      'hivemind:mark-intent-fallback',
      'hivemind:decision-report',
      'exploratory',
    ]) {
      assert.ok(!body.includes(phrase), `overlord body still names ${phrase}`);
    }
  });
  test('the Final Report block holds the Decisions line right after its Review line', () => {
    const reportBlock = readSection(body, '## Final Report').match(/```text\n([\s\S]*?)\n```/);
    assert.ok(reportBlock, '## Final Report has no text block');
    const reportLines = reportBlock[1].split('\n');
    const reviewIndex = reportLines.findIndex((line) => line.startsWith('Review:'));
    assert.notEqual(reviewIndex, -1, '## Final Report block has no Review line');
    assert.equal(reportLines[reviewIndex + 1], 'Decisions: [one line per taken decision | None]');
  });
  test('Stop Conditions cites the Decision Journal and names no ledger mechanism', () => {
    const stopConditions = readSection(body, '### Stop Conditions');
    assert.ok(stopConditions.includes('`${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md` (Decision Journal)'), '### Stop Conditions lacks the (Decision Journal) citation');
    for (const phrase of ['event.outputs', 'run ledger', 'final report', 'record-state-result', 'user_gate']) {
      assert.ok(!stopConditions.includes(phrase), `### Stop Conditions still names ${phrase}`);
    }
  });
  test('the Reflex heading is kept and its body names no run ledger', () => {
    assert.ok(body.split('\n').includes('## Reflex (Ledger-Skip)'), 'overlord body lacks ## Reflex (Ledger-Skip)');
    assert.ok(!readSection(body, '## Reflex (Ledger-Skip)').includes('run ledger'), '## Reflex (Ledger-Skip) still names a run ledger');
  });
  test('the post-PR watch reads only the in-session request text', () => {
    assert.ok(postureSection.includes('The only signal is the in-session request text'), '## Review Remediation Posture lacks the in-session request text signal');
    assert.ok(!postureSection.includes('request.raw'), '## Review Remediation Posture still reads request.raw');
  });
  test('decision-autonomy Decision Journal lists decisions in the final message and keeps no journal without a pull request', () => {
    assert.ok(readSection(autonomyText, '## Decision Journal').includes('lists its decisions in its final message or final report and keeps no decision journal'), 'decision-autonomy ## Decision Journal lacks the no-pull-request rule');
  });
  test('decision-autonomy drops the resume doors and the post-merge decision report', () => {
    const tierA = readSection(autonomyText, '## Decision Tiers').split('### Tier B')[0];
    for (const phrase of ['Resume On Start', 'version-skew']) {
      assert.ok(!tierA.includes(phrase), `decision-autonomy Tier A still names ${phrase}`);
    }
    for (const phrase of ['## Post-Merge Decision Report Trigger', 'HIVEMIND_ENABLE_DECISION_REPORT']) {
      assert.ok(!autonomyText.includes(phrase), `decision-autonomy still names ${phrase}`);
    }
  });
  test('the Proactive Zoom-Out Marker heading agrees with every citer', () => {
    assert.ok(doctrineText.split('\n').includes('### Proactive Zoom-Out Marker'), 'remediation-doctrine lacks ### Proactive Zoom-Out Marker');
    assert.ok(!doctrineText.includes('Ledger Marker'), 'remediation-doctrine still names Ledger Marker');
    assert.ok(body.includes('(Proactive Zoom-Out Marker)'), 'overlord body does not cite (Proactive Zoom-Out Marker)');
    assert.ok(autonomyText.includes('Proactive Zoom-Out Marker)'), 'decision-autonomy does not cite Proactive Zoom-Out Marker');
  });
});

// These check each phrase is present inside its own `## ` section, never its meaning, per tests/policy/README.md (1. Honest capability statement); issue 656.
describe('overlord section-scoped Instinct pins', () => {
  test('readSection stops at the next H2 and keeps an H3 inside its parent', () => {
    const syntheticBody = ['## First', 'first text', '### Child', 'child text', '## Second', 'second text'].join('\n');
    const firstSection = readSection(syntheticBody, '## First');
    assert.ok(!firstSection.includes('second text'), 'a phrase in the next ## section was found in the section before it');
    assert.ok(firstSection.includes('child text'), 'a ### subsection left its parent section');
  });
  test('Instinct states the permanent path, its three paths, the plan and the one-commit PR gate', () => {
    assertSectionHasPhrases('## Instinct', [
      'Instinct is a permanent path beside the workflow scripts',
      'the fallback for every workflow per `## Engine`',
      'asks only what `### Stop Conditions` surfaces',
      'A `standard-delivery` request that names neither path takes the engine when it carries a `working_branch.base` ref',
      'otherwise ask the user which, with your recommendation',
      'Every run needs a plan before any edit',
      'the PR by `hivemind:open-plan-pr` only on a commit that validation and local review (unless it did not run, per `${CLAUDE_PLUGIN_ROOT}/governance/workflow.md` (PR Requirements)) both passed on',
      'a later commit rerunning both',
      '**Read-only analysis.**',
      'Open no branch, commit or pull request',
      '**Post-PR remediation.**',
      'Check out the PR head per `## Safety Rails` first',
      '`hivemind:open-plan-pr` opens a new one',
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

// These check the Reflex check comes before routing and the Reflex conditions sit only in their own section, never their meaning, per tests/policy/README.md (1. Honest capability statement); ADR-0018 amendment 2026-11-06 (issue 451).
describe('overlord Reflex check before routing', () => {
  const reflexSection = readSection(body, '## Reflex (Ledger-Skip)');
  const engineOpening = engineSection.trim().split('\n\n')[0];
  test('Engine checks the Reflex before hivemind:route-workflow selects a workflow', () => {
    const reflexCheck = engineOpening.indexOf('Check `## Reflex (Ledger-Skip)` first; a Reflex launches no workflow.');
    const routing = engineOpening.indexOf('`hivemind:route-workflow` selects the workflow before any launch.');
    assert.notEqual(reflexCheck, -1, 'the opening ## Engine paragraph lacks the Reflex check');
    assert.notEqual(routing, -1, 'the opening ## Engine paragraph lacks the routing sentence');
    assert.ok(reflexCheck < routing, 'the opening ## Engine paragraph routes before it checks the Reflex');
  });
  test('the Reflex conditions admit a version-only edit only as the whole bump', () => {
    assertSectionHasPhrases('## Reflex (Ledger-Skip)', [
      "a version-only edit (the project's whole version bump, no other file)",
      'no version impact beyond that edit',
    ]);
  });
  test('the Reflex conditions are stated only in ## Reflex (Ledger-Skip)', () => {
    for (const phrase of ['one known file', 'version-only edit', 'no version impact']) {
      const inSection = reflexSection.split(phrase).length - 1;
      assert.ok(inSection > 0, `## Reflex (Ledger-Skip) lacks ${phrase}`);
      assert.equal(body.split(phrase).length - 1, inSection, `${phrase} is stated outside ## Reflex (Ledger-Skip)`);
    }
  });
});

// These check brood dispatch runs on Instinct in the main session and RUN-OWNERSHIP-01 is gone, never their meaning, per tests/policy/README.md (1. Honest capability statement); issue 654.
describe('overlord brood dispatch on Instinct', () => {
  const broodSection = readSection(body, '## Brood Execution');
  const hatcheryParagraph = engineSection.split('\n\n').find((paragraph) => paragraph.startsWith('When `hivemind:route-workflow` selects `hatchery-dispatch`,')) ?? '';
  test('Engine routes a selected hatchery-dispatch to ## Brood Execution and launches no workflow', () => {
    assert.notEqual(hatcheryParagraph, '', '## Engine has no paragraph starting When `hivemind:route-workflow` selects `hatchery-dispatch`,');
    for (const phrase of ['launch no workflow', 'run `## Brood Execution` in this session']) {
      assert.ok(hatcheryParagraph.includes(phrase), `hatchery-dispatch paragraph lacks ${phrase}`);
    }
    assert.ok(!hatcheryParagraph.includes('never enter the workflow state machine'), 'hatchery-dispatch paragraph still names the workflow state machine');
  });
  test('Brood Execution states both entry conditions, facts and plan, the Tier A approval before spawn, relay and monitoring', () => {
    assertSectionHasPhrases('## Brood Execution', [
      'Brood dispatch runs on Instinct in the main session',
      'entered when `hivemind:route-workflow` selects `hatchery-dispatch` or an Instinct plan returns delivery `brood`',
      'Get facts from `hivemind:gather-facts` and a brood plan from `hivemind:cerebrate`',
      'That approval is a Tier A item per `${CLAUDE_PLUGIN_ROOT}/governance/decision-autonomy.md` (Decision Tiers), never taken by recommendation',
      '`${CLAUDE_PLUGIN_ROOT}/governance/security-policy.md` (Brood Spawn Bypass-Mode Mitigation)',
      'Invoke `hivemind:spawn-brood` only after that approval',
      'a declined approval spawns nothing, and the final report carries the brood plan',
      'relay the script\'s `remote:` lines together with its `attach:` lines',
      'monitor read-only via `hivemind:brood-status`',
    ]);
  });
  test('Brood Execution seeks the strain approval before it invokes hivemind:spawn-brood', () => {
    const sectionText = normalizeWhitespace(broodSection);
    const approval = sectionText.indexOf('for the user\'s explicit approval');
    const spawn = sectionText.indexOf('Invoke `hivemind:spawn-brood` only after that approval');
    assert.notEqual(approval, -1, '## Brood Execution lacks the explicit approval');
    assert.notEqual(spawn, -1, '## Brood Execution lacks the spawn after approval');
    assert.ok(approval < spawn, '## Brood Execution spawns before it seeks the approval');
  });
  test('Brood Execution drops the state-machine dispatch and the child ledger rule', () => {
    for (const phrase of ['`user_gate`', '`spawn_brood`', 'run ledger', 'RUN-OWNERSHIP-01']) {
      assert.ok(!broodSection.includes(phrase), `## Brood Execution still contains ${phrase}`);
    }
  });
  test('the overlord body no longer names RUN-OWNERSHIP-01', () => {
    assert.ok(!body.includes('RUN-OWNERSHIP-01'), 'the overlord body still names RUN-OWNERSHIP-01');
  });
  test('decision-autonomy Tier A still lists brood strain approval', () => {
    const tierA = readSection(autonomyText, '## Decision Tiers').split('### Tier B')[0];
    assert.ok(tierA.includes('brood strain approval'), 'decision-autonomy Tier A no longer lists brood strain approval');
  });
});
