import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const workflowsDir = repoRoot + 'plugin/workflows/';
const QUESTION_GATE = 'question';
const QUESTION_OUTCOMES = ['open_questions', 'user-input-required', 'high-severity-rejection'];
const REMOVED_TERMINALS = ['user_input_required', 'review_rejected'];
const EXPECTED_ASKING_STATES = {
  'pr-feedback-remediation': ['github_review_loop', 'github_reviewer_fix', 'review_remediation_plan'],
  'standard-delivery': ['plan', 'local_review', 'review_remediation_plan', 'github_review_loop', 'review_remediation_plan_postpr'],
  'analysis-only': ['analyze'],
  'hatchery-dispatch': ['brood_plan']
};

function readDefinitions() {
  const definitions = [];
  for (const fileName of readdirSync(workflowsDir).sort()) {
    if (fileName.endsWith('.json')) {
      definitions.push({ fileName, definition: JSON.parse(readFileSync(workflowsDir + fileName, 'utf8')) });
    }
  }
  return definitions;
}

function listQuestionEdges(definition) {
  const questionEdges = [];
  for (const [stateName, state] of Object.entries(definition.states)) {
    for (const [outcome, target] of Object.entries(state.transitions ?? {})) {
      if (QUESTION_OUTCOMES.includes(outcome)) {
        questionEdges.push({ stateName, outcome, target });
      }
    }
  }
  return questionEdges;
}

function listAskingStates(definition) {
  return [...new Set(listQuestionEdges(definition).map((edge) => edge.stateName))];
}

const definitions = readDefinitions();

describe('state-machine question gate', () => {
  test('the workflows directory holds state-machine definitions', () => {
    assert.notEqual(definitions.length, 0, 'no plugin/workflows/*.json found');
  });
  test('every definition that the question gate covers declares it', () => {
    for (const workflowId of Object.keys(EXPECTED_ASKING_STATES)) {
      const entry = definitions.find((candidate) => candidate.definition.id === workflowId);
      assert.ok(entry, `no definition with id ${workflowId}`);
      assert.equal(entry.definition.states[QUESTION_GATE]?.type, 'user_gate', `${workflowId} has no ${QUESTION_GATE} user_gate`);
      assert.deepEqual(listAskingStates(entry.definition).sort(), [...EXPECTED_ASKING_STATES[workflowId]].sort(), workflowId);
    }
  });
  for (const { fileName, definition } of definitions) {
    describe(fileName, () => {
      test('every open_questions, user-input-required or high-severity-rejection transition targets the question user_gate', () => {
        for (const edge of listQuestionEdges(definition)) {
          const label = `${edge.stateName}.${edge.outcome}->${edge.target}`;
          assert.equal(edge.target, QUESTION_GATE, label);
          assert.equal(definition.states[edge.target]?.type, 'user_gate', label);
        }
      });
      test('each question gate outcome other than cancelled names the state it targets, and that state routes a question outcome to the gate', () => {
        const gate = definition.states[QUESTION_GATE];
        if (gate === undefined) {
          assert.deepEqual(listQuestionEdges(definition), [], `${fileName} routes question outcomes but has no ${QUESTION_GATE} gate`);
          return;
        }
        const askingStates = listAskingStates(definition);
        const answerOutcomes = Object.keys(gate.transitions).filter((outcome) => outcome !== 'cancelled');
        assert.deepEqual([...answerOutcomes].sort(), [...askingStates].sort(), 'gate outcomes equal the states that ask');
        for (const outcome of answerOutcomes) {
          assert.equal(gate.transitions[outcome], outcome, `${QUESTION_GATE}.${outcome}`);
          const askingEdges = Object.entries(definition.states[outcome]?.transitions ?? {}).filter(([edgeOutcome, target]) => QUESTION_OUTCOMES.includes(edgeOutcome) && target === QUESTION_GATE);
          assert.notEqual(askingEdges.length, 0, `${outcome} routes no question outcome to ${QUESTION_GATE}`);
        }
      });
      test('question.cancelled targets the cancelled terminal', () => {
        const gate = definition.states[QUESTION_GATE];
        if (gate === undefined) {
          return;
        }
        assert.equal(gate.transitions.cancelled, 'cancelled');
        assert.equal(definition.states.cancelled?.type, 'terminal');
        assert.ok(definition.terminal.includes('cancelled'), 'cancelled is in the terminal array');
      });
      test('declares no user_input_required or review_rejected state', () => {
        for (const stateName of REMOVED_TERMINALS) {
          assert.equal(Object.hasOwn(definition.states, stateName), false, `${fileName} declares ${stateName}`);
          assert.equal((definition.terminal ?? []).includes(stateName), false, `${fileName} lists ${stateName} as terminal`);
        }
      });
    });
  }
});
