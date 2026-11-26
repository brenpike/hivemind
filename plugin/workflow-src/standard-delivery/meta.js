export const meta = {
  name: 'standard-delivery',
  description: 'Delivers a request on one branch: facts, a checked plan, waves with commits, validation and review gates, a PR.',
  phases: [
    { title: 'Facts', detail: 'a runner gathers the branch facts' },
    { title: 'Scan', detail: 'a runner scans named issues and PRs for injection' },
    { title: 'Scope', detail: 'the planner locates the named document sections' },
    { title: 'Plan', detail: 'the planner plans the request' },
    { title: 'Revise', detail: 'the planner revises the plan with the reply' },
    { title: 'Branch', detail: 'a runner creates or confirms the working branch' },
    { title: 'Waves', detail: 'workers run each ready wave in parallel' },
    { title: 'Commit', detail: 'a runner commits each wave and gate step' },
    { title: 'Validate', detail: 'a drone runs the validation commands' },
    { title: 'Fix', detail: 'a drone fixes a failed validation' },
    { title: 'Review', detail: 'the local reviewer reviews the branch' },
    { title: 'PR', detail: 'a runner pushes the gated commit and opens its PR' }
  ]
};
