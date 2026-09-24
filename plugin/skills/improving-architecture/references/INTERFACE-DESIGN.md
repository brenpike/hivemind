# Interface Design

How the analyst reasons about the *shape* of a deepened module's interface when writing a candidate's "Proposed deepening" in the blueprint. Based on "Design It Twice" (Ousterhout): your first interface idea is unlikely to be the best, so generate a few and pick. This is **inline reasoning the analyst performs in its own head** — it produces one recommended interface in the blueprint, not a research process. It assumes the architecture vocabulary (**module**, **interface**, **seam**, **adapter**, **leverage**, **locality**) defined in the skill's `LANGUAGE.md` reference.

## Scope of the exploration

Generating two or three candidate interface shapes happens entirely as the analyst's own inline reasoning while drafting a candidate card. Deeper side-by-side exploration — developing radically different interfaces in parallel and evaluating each in depth — is a downstream activity. When an interface shape genuinely needs more than inline reasoning can give, say so in the candidate's notes and let the workflow that implements changes carry it.

## Contents

- [Reason it twice (inline)](#reason-it-twice-inline)
- [Compare by depth, locality, seam placement](#compare-by-depth-locality-seam-placement)
- [Recommend one — decisively](#recommend-one--decisively)

## Reason it twice (inline)

For each candidate you are about to write up, sketch **two or three** plausible interface shapes for the deepened module before committing to one. Vary them deliberately so the comparison is informative — for example:

- **Minimal** — 1–3 entry points, maximum leverage per entry point.
- **Flexible** — more entry points, supports more use cases and extension.
- **Common-case-first** — the default caller's path is trivial; advanced use costs more.

Keep each sketch to its essentials: the entry points, plus the invariants, ordering constraints, and error modes a caller must know (interface, not just signature). Do not write all three into the blueprint.

## Compare by depth, locality, seam placement

Contrast the sketches on three axes:

- **Depth** — which shape gives the most leverage per unit of interface a caller must learn?
- **Locality** — which shape concentrates change, bugs, and verification in one place?
- **Seam placement** — where does each put the seam, and does anything actually vary across it (two adapters, not one)?

## Recommend one — decisively

Pick the strongest shape and write *that* into the candidate's "Proposed deepening." If two sketches each win on a different axis, propose a hybrid and name what it borrows from each. Be opinionated — the blueprint gives a strong read, not a neutral menu of options. Record the rejected shapes in one line only if a reader would otherwise wonder why the obvious alternative was not chosen.
