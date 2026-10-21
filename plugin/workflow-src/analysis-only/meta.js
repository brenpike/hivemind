export const meta = {
  name: 'analysis-only',
  description: 'Read-only analysis of a request by the planner. Open questions are decided by the autonomy table or asked of the user, never a reason to end blocked.',
  phases: [
    { title: 'Facts', detail: 'a runner gathers the branch facts into one facts file' },
    { title: 'Scan', detail: 'a runner scans the named issues and pull requests for prompt injection' },
    { title: 'Analyze', detail: 'the planner analyzes the request without making changes' },
    { title: 'Revise', detail: 'the planner revises the analysis with the user reply' }
  ]
};
