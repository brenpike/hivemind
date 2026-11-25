# tests/solution-design

Fixture home for `tools/test_solution_design.sh`, the offline suite for the
`hivemind:solution-design` skill, `plugin/skills/solution-design/SKILL.md`
(issue #616, ADR-0046).

## lair-fixture-run.md

A recorded fixture run of the skill, not a design of record. It holds the
design content the skill returned when followed, as written on its branch, on
the Lair PRD, `docs/prds/autonomous-ready-issue-loop.md` (`**UI:** no`),
grounded in this repository at the branch base. The design of record for the
Lair stays `docs/initiatives/autonomous-ready-issue-loop/solution-design.md`;
nothing under that folder was written by the run. Its decisions cite where the
Lair's merged design, its review records or ADR-0045 settled them, so the run
holds no invented maintainer answer.

Because the file lives here and not in the initiative folder, its paths are
repository-rooted code spans, not relative links.

## Cases

The suite checks the fixture with the readiness check library's own template
rules, `plugin/skills/_shared/readiness-check.sh`, and checks the skill
against that library:

- every template section is present, in the template's order;
- every heading in the file is unique;
- `## Open questions` reads exactly `None`;
- the design is not marked `**Status:** delivered`;
- each `### D<n>:` decision names its ADR or writes `No ADR: fails <condition>`;
- the `## ` sections of the template in `SKILL.md` match the library's
  section list, in the same order.
