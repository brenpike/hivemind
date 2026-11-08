/*
 * standard-delivery specs.js: the routing specs of the runner scripts of
 * the standard-delivery workflow, their fixed warning texts and the
 * consistency checks of the bump-type relay.
 *
 * Inputs
 *   values  the routing lines of one relay, as readRelayedLines (relay.js)
 *           parses them with one of these specs.
 *
 * Outputs
 *   createWorkingBranchRoutingSpec(), moltRoutingSpec(),
 *   bumpTypeRoutingSpec() and openPlanPrRoutingSpec()  the routing spec of
 *           create-working-branch.sh, molt.sh, bump-type.sh and
 *           open-plan-pr.sh, for parseRoutingLines (lib/routing.js).
 *   branchWarningTexts() and pullRequestWarningTexts()  the fixed warning
 *           texts of create-working-branch.sh and open-plan-pr.sh.
 *   versionCheckRoutingSpec()  bumpTypeRoutingSpec() plus the bump-type.sh
 *           --version-file keys in its OUTPUT order: version_check, then
 *           optional trunk_version and expected_version, each a SemVer core
 *           of at most 15 digits a part, so briefs.js raises it exactly.
 *   isConsistentVersionRelay(values)  the bump checks; match and mismatch
 *           carry both versions and a verdict other than ask_user,
 *           undetermined has verdict ask_user and no expected_version, and
 *           expected_version comes only with trunk_version.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   The keys of each spec are the OUTPUT keys of its script, and each
 *   warning pattern holds only the fixed texts of its script.
 *
 * Why
 *   A relay is read only through the spec of the script that wrote it, so
 *   the specs of every runner step live in one place.
 */

function commitShaPattern() {
  return /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
}

function branchWarningTexts() {
  return {
    stale: 'trunk is stale or diverged from origin; proceeding as acknowledged at preflight',
    skipped: 'trunk freshness check was skipped'
  };
}

function createWorkingBranchRoutingSpec() {
  const warnings = branchWarningTexts();
  return {
    branch: { pattern: gitIdentifierPattern(), required: true },
    commit: { pattern: commitShaPattern(), required: true },
    created: { pattern: /^(?:true|false)$/, required: true },
    warning: { pattern: new RegExp('^(?:' + warnings.stale + '|' + warnings.skipped + ')$'), required: false }
  };
}

function moltRoutingSpec() {
  return {
    branch: { pattern: gitIdentifierPattern(), required: true },
    commit: { pattern: commitShaPattern(), required: true },
    committed: { pattern: /^(?:true|false)$/, required: true }
  };
}

function bumpTypeRoutingSpec() {
  const count = { pattern: /^(?:0|[1-9][0-9]*)$/, required: true };
  return {
    dominant_row: { pattern: /^(?:MAJOR|MINOR|PATCH|NO_BUMP|NONE|MULTI)$/, required: true },
    verdict: { pattern: /^(?:bump_required|no_bump|ask_user)$/, required: true },
    bump_type: { pattern: /^(?:major|minor|patch|none)$/, required: true },
    rule_applied: { pattern: /^[1-6]$/, required: true },
    counts: { block: { major: count, minor: count, patch: count, no_bump: count }, required: true },
    mapped_commits: count,
    dropped_reverts: count
  };
}

function pullRequestWarningTexts() {
  return [
    'push was rejected; the branch is not on its remote',
    'no upstream and no origin remote; push deferred',
    'gh cannot read the push remote as a GitHub repository; the PR head repository was not checked'
  ];
}

function openPlanPrRoutingSpec() {
  return {
    url: { pattern: /^https:\/\/[A-Za-z0-9._/-]+\/pull\/[0-9]+$/, required: true },
    head_ref_oid: { pattern: commitShaPattern(), required: true },
    created: { pattern: /^(?:true|false)$/, required: true },
    commented: { pattern: /^(?:true|false)$/, required: true },
    warning: { pattern: new RegExp('^(?:' + pullRequestWarningTexts().join('|') + ')$'), required: false }
  };
}

function semverCorePattern() {
  return /^(?:0|[1-9][0-9]{0,14})\.(?:0|[1-9][0-9]{0,14})\.(?:0|[1-9][0-9]{0,14})$/;
}

function versionCheckRoutingSpec() {
  return {
    ...bumpTypeRoutingSpec(),
    version_check: { pattern: /^(?:match|mismatch|unreadable|undetermined)$/, required: true },
    trunk_version: { pattern: semverCorePattern(), required: false },
    expected_version: { pattern: semverCorePattern(), required: false }
  };
}

function isConsistentBumpRelay(values) {
  const counts = values.counts;
  const countSum = Number(counts.major) + Number(counts.minor) + Number(counts.patch) + Number(counts.no_bump);
  return (values.verdict === 'bump_required') === (values.bump_type !== 'none')
    && countSum === Number(values.mapped_commits);
}

function isConsistentVersionRelay(values) {
  const hasExpected = values.expected_version !== undefined;
  const hasTrunk = values.trunk_version !== undefined;
  if (!isConsistentBumpRelay(values) || (hasExpected && !hasTrunk)) {
    return false;
  }
  if (values.version_check === 'match' || values.version_check === 'mismatch') {
    return hasExpected && values.verdict !== 'ask_user';
  }
  return values.version_check === 'unreadable' || (values.verdict === 'ask_user' && !hasExpected);
}
