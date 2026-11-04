---
name: create-handoff
description: Writes a session-resumption handoff for an interrogated plan to `.hivemind/handoffs/<slug>.md`. Use to create a handoff.
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

# Create Handoff

Transform an interrogated plan and any additional context which is relevant into a fresh-session kickoff handoff. This is **pure synthesis**: read the source, write the handoff, stop. Ask the user nothing — they review the written output.

The handoff document should contain enough detail to bootstrap a new session with confidence, but it should point to the plan for the full rationale and details — do not duplicate them. The handoff is a **pointer document** that distills the most important context but directs the reader to the plan for the full story. Together with the plan, there must be a high-fidelity record of the interrogation and decision-making that led to the Initiative's current state.

---

## When this runs

The handoff offer is **caller/human-driven**, never a prompt baked into this or any other skill. It runs when:

- the user explicitly asks for a handoff, OR
- the caller suggests one at a context-rich stage boundary and the user accepts.

This skill never decides on its own to produce a handoff and never solicits one from inside another skill's flow.

---

## Inputs

Session-agnostic and resumable at any boundary. Resolve inputs in this order:

1. **Plan (required)** — the interrogated plan. Source it from either:
   - the live conversation context (a plan already on screen / just produced), OR
   - a file at `.hivemind/plans/<slug>.md`.
   If both are present, prefer the live context and treat the file as a cross-check.
   When the plan is sourced from live context, `.hivemind/plans/<slug>.md` is the durable backing for the handoff's plan pointer and MUST exist by the time the handoff is written. Live-context input stays valid — the skill itself is responsible for materializing that backing file when only live context was supplied; do not treat a pre-persisted plan as a precondition.
2. **Handoff-context (optional, never required)** — extra session state the caller passes (recent decisions, in-flight questions, pointers). When absent, synthesize entirely from the plan. Do not ask for it, do not block on it.

Derive `<slug>` from the input — the plan file's basename, or the slug already in use for the initiative. **Never hardcode a slug.** One slug per initiative: the same slug names `.hivemind/plans/<slug>.md`, `.hivemind/handoffs/<slug>.md`, and `docs/prds/<slug>.md`.

---

## Procedure

1. Acquire the plan from context or `.hivemind/plans/<slug>.md`. If neither is available, stop and tell the user which is missing — do not invent a plan.
2. Determine `<slug>` from the input (file basename or the initiative's existing slug).
3. Ensure the output directory exists: `mkdir -p .hivemind/handoffs`.
4. Guarantee the plan's backing file exists (reuse the `<slug>` already determined in step 2 — do not derive a second slug; in the live-context-only case that slug came from the initiative name per the rule above):
   - Check whether `.hivemind/plans/<slug>.md` exists (`ls`/`find`).
   - If it does NOT exist AND the plan came from live context: `mkdir -p .hivemind/plans`, then Write the live plan verbatim to `.hivemind/plans/<slug>.md`.
   - If it ALREADY exists: do NOT overwrite — the existing file is the source of truth.
5. Synthesize the handoff body from the plan plus any optional handoff-context. **Point to the plan; do not duplicate it.** Each section is a pointer or a distilled list, never a copy of the plan's prose.
6. Write `.hivemind/handoffs/<slug>.md` using the exact section set below.
7. Verify `.hivemind/plans/<slug>.md` exists before reporting success. If it is still missing, surface the failure — do not report a handoff that points at a nonexistent plan.
8. Report the written path to the user. This completes this skill's own procedure — do not ask follow-up questions. The skill then returns control to whatever invoked it; the caller then continues from the point at which it invoked this skill.

---

## Output file format

Write `.hivemind/handoffs/<slug>.md` with **exactly** these sections, in this order (D8):

```markdown
# HANDOFF — <Initiative> (fresh-session kickoff)

> One-line pointer to the plan: `.hivemind/plans/<slug>.md` (read it first). This handoff points to the plan — it does not duplicate it.

## What this delivers
<One short paragraph: the outcome the new session is meant to reach. Distilled, not copied.>

## FIRST ACTION
1. Read `.hivemind/plans/<slug>.md` fully.
2. <Next concrete numbered step from the plan.>
3. <…>

## Locked decisions (DO NOT RELITIGATE)
- **<D#/label>** — <settled decision, one line each.>

## Open questions
- <Genuinely unresolved item. If the plan resolved everything, state "NONE (all resolved)".>

## Pointers
- Plan: `.hivemind/plans/<slug>.md`
- <PRD / ADRs / glossary / reference skills / related artifacts as they exist.>
```

Section rules:

- **Title** — `# HANDOFF — <Initiative> (fresh-session kickoff)`. `<Initiative>` is the human-readable initiative name, not the slug.
- **Plan pointer** — the single blockquote line directly under the title. Always present; always tells the reader to read the plan first.
- **What this delivers** — the target outcome in the new session, distilled to a few lines.
- **FIRST ACTION** — a numbered list; step 1 is always "Read the plan fully."
- **Locked decisions (DO NOT RELITIGATE)** — settled decisions, one line each, lifted as references (not re-argued).
- **Open questions** — only genuinely open items. If none, write `NONE (all resolved)`.
- **Pointers** — a bullet list of paths to durable artifacts (plan, PRD, ADRs, glossary, reference material). Pointers, not contents.

Do not add, remove, rename, or reorder sections. The handoff is a pointer document — if a reader needs full rationale, they follow a pointer to the plan or PRD.

---

## Output is ephemeral

`.hivemind/` is already gitignored, so the handoff is disposable session state, not a committed artifact.

- Do **not** `git add`, `git commit`, or otherwise stage the handoff. (This skill has no git tools and must not acquire them.)
- The handoff is consumed by a fresh session and discarded; it is not a durable, committed artifact like a PRD or ADR.
- A `.hivemind/plans/<slug>.md` file this skill materializes from live context has the same disposition: it is gitignored, ephemeral session scaffolding (D11), never `git add`ed or committed by this skill.

---

## Do Not

- ask the user any questions — this skill is zero-interrogation synthesis.
- require handoff-context — the optional input is never mandatory.
- hardcode a slug — always derive it from the input.
- duplicate the plan or PRD — the handoff points to them. (Not in tension with persisting the plan file: the handoff body still only POINTS to the plan, copying no plan prose; materializing the plan FILE when absent is a separate permitted action.)
- overwrite an existing `.hivemind/plans/<slug>.md` — the persisted plan is authoritative; only create it when absent in the live-context path.
- add, drop, rename, or reorder the output sections.
- `git add`, commit, push, or open a PR — the caller handles the commit/push/PR lifecycle; the handoff is gitignored.
