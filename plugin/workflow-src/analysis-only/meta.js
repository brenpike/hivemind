export const meta = {
  name: 'analysis-only',
  description: 'Read-only analysis of a request by the planner. Open questions are decided by the autonomy table or asked of the user, never a reason to end blocked.',
  phases: [
    { title: 'Analyze', detail: 'the planner analyzes the request without making changes' },
    { title: 'Revise', detail: 'the planner revises the analysis with the user reply' }
  ]
};
