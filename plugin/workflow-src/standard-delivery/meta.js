export const meta = {
  name: 'standard-delivery',
  description: 'Delivers a request on one working branch: branch facts, a checked plan, questions decided by the autonomy table or asked of the user, the working branch, each wave of plan steps with its commit, validation and local review as gates on one commit, and the pull request for that commit.',
  phases: [
    { title: 'Facts', detail: 'a runner gathers the branch facts into one facts file' },
    { title: 'Scan', detail: 'a runner scans the named issues and pull requests for prompt injection' },
    { title: 'Scope', detail: 'the planner, on a smaller model, locates the sections of the documents the request names' },
    { title: 'Plan', detail: 'the planner plans what is left of the request on this branch' },
    { title: 'Revise', detail: 'the planner revises the plan with the user reply' },
    { title: 'Branch', detail: 'a runner creates or confirms the working branch' },
    { title: 'Waves', detail: 'workers run each ready wave of plan steps in parallel' },
    { title: 'Commit', detail: 'a runner commits the files of each wave and of each gate step' },
    { title: 'Validate', detail: 'a drone runs the project validation commands' },
    { title: 'Fix', detail: 'a drone fixes a failed validation, one round at a time' },
    { title: 'Review', detail: 'the local reviewer reviews the branch and commits its simple fixes' },
    { title: 'PR', detail: 'a runner pushes the commit every gate held on and opens or reuses its pull request' }
  ]
};
