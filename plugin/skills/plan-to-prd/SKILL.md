---
name: plan-to-prd
description: Turns an interrogated plan into a committed WHAT-only PRD at `docs/prds/<slug>.md`. Use when writing a PRD from a plan.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash(find *)
  - Bash(grep *)
  - Bash(ls *)
  - Bash(cat *)
  - Bash(mkdir -p *)
shell: bash
---

# Plan to PRD

Synthesize an already-interrogated plan into a **PRD** — the committed, durable specification of WHAT an Initiative delivers, written to `docs/prds/<slug>.md`. This is a near-zero-interrogation transform: the heavy interrogation already happened upstream. Do not re-run forensic questioning here. Read the plan, draft the PRD, run the two confirm gates, write the file.

A PRD describes **WHAT** the Initiative delivers — never **HOW**. File scope, step sequencing, and the implementation path are the Directive's job, not the PRD's. The PRD is path-agnostic: producing it does not decide single-branch vs brood and does not force any execution path. That routing is decided downstream at implementation time, independent of this artifact.

---

## Inputs

Two inputs, resolved in this order:

1. **The plan (required).** Source it from EITHER:
   - the **live conversation context** (an interrogated plan already present in this session), OR
   - a persisted plan file at `.hivemind/plans/<slug>.md`.

   If neither is present, stop and ask the user for the plan or its slug. Do not synthesize a PRD from an un-interrogated idea.

2. **A handoff (optional).** If a handoff file exists at `.hivemind/handoffs/<slug>.md`, read it for volatile session state (locked decisions, open questions, pointers). Treat it as supplementary context that points at the plan — it does not replace the plan.

### Deriving the slug

Derive `<slug>` from the input; never hardcode it.

- If sourcing from `.hivemind/plans/<slug>.md`, the slug is the plan filename stem.
- If sourcing from live context, derive a short, kebab-case slug from the Initiative's name and confirm it with the user before writing.

One slug names the whole Initiative — its plan, optional handoff, and this PRD at `docs/prds/<slug>.md`. Reuse the existing slug; do not invent a second one.

---

## Context discovery

Before drafting, ground the PRD in the project's documented domain — same grounding the interrogation used. Discover context in this priority order:

1. **Read `CLAUDE.md`, `AGENTS.md`, and `AGENT.md`** at the repo root if they exist — find pointers to other docs.
2. **Read `CONTEXT.md` or `CONTEXT-MAP.md`** at the repo root if they exist.
3. **If `CONTEXT-MAP.md` exists** — multi-context repo; read the map to find the relevant context for this Initiative.
4. **Read existing ADRs** from `docs/adr/` if the directory exists.
5. **Any paths explicitly referenced** in CLAUDE.md/AGENTS.md/AGENT.md.

Respect the glossary and ADRs when writing: use the project's canonical terms (not synonyms the glossary lists under `_Avoid_`), and do not contradict an accepted ADR. If the plan conflicts with a documented decision, surface it as an open question in `## Further Notes` rather than silently overriding it.

---

## Near-zero interrogation

The plan arrived interrogated. Do NOT re-open the design tree, re-eliminate options, or re-run forensic questioning — that work lives upstream and rerunning it is wasted effort and a worse experience for the user. Synthesize the PRD directly from the plan.

Run exactly TWO light confirm gates, each as a single question with your own recommended answer drawn from the plan:

1. **Story completeness gate.** Present the user-story set you derived and ask: "Is this the complete set of user stories, or is one missing?" Adjust only if the user names a gap.
2. **Scope boundary gate.** Present the `## Out of Scope` list you derived and ask: "Are these the right scope boundaries — anything to add or pull back in?" Adjust only if the user corrects a boundary.

If the plan does not contain enough to populate a required PRD section, ask one targeted question to fill that specific gap — but do not turn the gap into a full re-interrogation. Anything genuinely unresolved goes into `## Further Notes` as an open question.

---

## PRD template

Write the PRD with these nine sections, in this EXACT order. Every PRD uses this skeleton.

```markdown
# PRD: <Initiative name>

## Problem Statement
The problem the Initiative solves and who has it. Why it matters now.

## Solution
The high-level approach in WHAT terms. What the delivered thing does, not how it is built.

## User Stories
One per line, each in the form: As an <X>, I want <Y>, so that <Z>.

## Acceptance Criteria
Observable, verifiable conditions that say the Initiative is done. Phrase so each is testable.

## Implementation Decisions
Architectural and contract-level decisions ONLY — e.g. which boundary owns a responsibility,
what an interface/contract guarantees, which data shape crosses a seam. NO file paths, NO code
snippets, NO step-by-step sequence. Those belong to the Directive (HOW), not the PRD (WHAT).

## Testing Decisions
What kinds of tests prove the acceptance criteria and at what level (e.g. contract vs end-to-end),
stated as intent — not test file paths or test code.

## Success Metrics
How success is measured after delivery — observable signals or numbers, not implementation tasks.

## Out of Scope
What this Initiative explicitly does NOT cover. The scope boundary confirmed in the second gate.

## Further Notes
Open questions, deferred decisions, and any plan/ADR conflicts surfaced but not resolved here.
```

### WHAT-only discipline

The PRD specifies WHAT, never HOW. These MUST NOT appear anywhere in the PRD — including in `## Implementation Decisions`:

- **File paths** — no `src/...`, no module/directory names as the unit of work.
- **Code snippets** — no function bodies, signatures-as-spec, or pseudocode.
- **Step sequence** — no ordered "first do X, then Y" implementation plan; sequencing is the Directive's job.

`## Implementation Decisions` is for architectural and contract-level decisions only (a boundary, a guarantee, a data shape that crosses a seam) — the kind of decision that is hard to reverse and shapes the solution, stated without prescribing the code that realizes it.

**Prototype exception:** if the Initiative is an explicit throwaway prototype or spike, a small illustrative code sketch is permitted in `## Solution` or `## Further Notes` — clearly labelled as a prototype sketch, not a spec. This is the only exception; the default is no code.

---

## Writing the file

1. Ensure the target directory exists — `docs/prds/` may not exist yet:

   ```bash
   mkdir -p docs/prds
   ```

2. Write the PRD to `docs/prds/<slug>.md` using the resolved slug. This file is committed and durable — do not write it to `.hivemind/`.
3. If `docs/prds/<slug>.md` already exists, read it first and update in place rather than blindly overwriting; preserve any sections the current plan does not touch.

---

## Handback

Writing or updating `docs/prds/<slug>.md` completes this skill's procedure. This skill
returns control to whatever invoked it; the caller then continues from the point at which it invoked this skill.
