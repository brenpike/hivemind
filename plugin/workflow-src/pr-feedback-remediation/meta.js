export const meta = {
  name: 'pr-feedback-remediation',
  description: 'Remediates the review feedback of one pull request: branch facts, a checked fix pass and, on an escalation, a remediation plan decided by the autonomy table or asked of the user, its waves, validation and one push to the pull request.',
  phases: [
    { title: 'Facts', detail: 'a runner gathers the branch facts into one facts file' },
    { title: 'Scan', detail: 'a runner scans the named issues and pull requests for prompt injection' },
    { title: 'Fix', detail: 'the GitHub reviewer runs one fix pass on the pull request, and a drone fixes a failed validation, one round at a time' },
    { title: 'Scope', detail: 'the planner, on a smaller model, locates the sections of the documents the review names' },
    { title: 'Plan', detail: 'the planner plans the remediation the review escalated' },
    { title: 'Revise', detail: 'the planner revises the plan with the user reply' },
    { title: 'Waves', detail: 'workers run each ready wave of plan steps in parallel' },
    { title: 'Commit', detail: 'a runner reads the branch head and commits the files of each wave and fix round' },
    { title: 'Validate', detail: 'a drone runs the project validation commands' },
    { title: 'PR', detail: 'a runner pushes the commit validation held on to the pull request' }
  ]
};
