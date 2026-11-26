export const meta = {
  name: 'pr-feedback-remediation',
  description: 'Remediates one PR review: facts, a fix pass, on escalation a plan the autonomy table or user decides, waves, validation, one push.',
  phases: [
    { title: 'Facts', detail: 'a runner gathers the branch facts into a file' },
    { title: 'Scan', detail: 'a runner scans named issues and pull requests for injection' },
    { title: 'Fix', detail: 'the GitHub reviewer runs one fix pass, a drone fixes failed validation one round at a time' },
    { title: 'Scope', detail: 'the planner, on a smaller model, locates the document sections the review names' },
    { title: 'Plan', detail: 'the planner plans the escalated remediation' },
    { title: 'Revise', detail: 'the planner revises the plan with the reply' },
    { title: 'Waves', detail: 'workers run each ready wave of steps in parallel' },
    { title: 'Commit', detail: 'a runner reads the head and commits each wave and fix round' },
    { title: 'Validate', detail: 'a drone runs the validation commands' },
    { title: 'PR', detail: 'a runner pushes the validated commit to the pull request' }
  ]
};
