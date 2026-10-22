export const meta = {
  name: 'standard-delivery',
  description: 'Delivers a request on one working branch: branch facts, a checked plan, questions decided by the autonomy table or asked of the user, the working branch, and each wave of plan steps with its commit.',
  phases: [
    { title: 'Facts', detail: 'a runner gathers the branch facts into one facts file' },
    { title: 'Scan', detail: 'a runner scans the named issues and pull requests for prompt injection' },
    { title: 'Plan', detail: 'the planner plans what is left of the request on this branch' },
    { title: 'Revise', detail: 'the planner revises the plan with the user reply' },
    { title: 'Branch', detail: 'a runner creates or confirms the working branch' },
    { title: 'Waves', detail: 'workers run each ready wave of plan steps in parallel' },
    { title: 'Commit', detail: 'a runner commits the files of each wave' }
  ]
};
