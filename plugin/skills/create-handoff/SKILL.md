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

Turn an interrogated plan, plus any relevant additional context, into a fresh-session kickoff handoff. This is **pure synthesis**: read the source, write the handoff, stop. Ask the user nothing; they review the written output.

The handoff is a **pointer document**: it distills enough context to bootstrap a new session with confidence and points to the plan for the full rationale and details, never duplicating them. Together with the plan, it must give a high-fidelity record of the interrogation and decision-making that led to the Initiative's current state.

## When this runs

The handoff offer is **caller/human-driven**, never a prompt baked into this or any other skill. It runs when the user explicitly asks for a handoff, or when the caller suggests one at a context-rich stage boundary and the user accepts. This skill never decides on its own to produce a handoff and never solicits one from inside another skill's flow.

## Inputs

Session-agnostic and resumable at any boundary. Resolve inputs in this order:

1. **Plan (required)**: the interrogated plan, from the live conversation context (a plan already on screen or just produced) or from a file at `.hivemind/plans/<slug>.md`. If both are present, prefer the live context and treat the file as a cross-check. A plan from live context needs `.hivemind/plans/<slug>.md` as the durable backing for the handoff's plan pointer, and that file must exist by the time the handoff is written. This skill materializes it when only live context was supplied, so a pre-persisted plan is no precondition.
2. **Handoff-context (optional, never required)**: extra session state the caller passes (recent decisions, in-flight questions, pointers). When absent, synthesize entirely from the plan; never ask for it or block on it.

Derive `<slug>` from the input: the plan file's basename, or the slug already in use for the initiative. **Never hardcode a slug.** One slug per initiative names `.hivemind/plans/<slug>.md`, `.hivemind/handoffs/<slug>.md`, and `docs/prds/<slug>.md`.

## Procedure

1. Acquire the plan from context or `.hivemind/plans/<slug>.md`. If neither is available, stop and tell the user which is missing; never invent a plan.
2. Determine `<slug>` from the input.
3. Ensure the output directory exists: `mkdir -p .hivemind/handoffs`.
4. Guarantee the plan's backing file exists, reusing the step 2 `<slug>` (never derive a second slug). Check whether `.hivemind/plans/<slug>.md` exists (`ls`/`find`). If it does not and the plan came from live context, `mkdir -p .hivemind/plans`, then Write the live plan verbatim to `.hivemind/plans/<slug>.md`. If it already exists, never overwrite it: the existing file is the source of truth.
5. Synthesize the handoff body from the plan plus any handoff-context. **Point to the plan; never duplicate it**: each section is a pointer or a distilled list, never a copy of the plan's prose. Materializing an absent plan file (step 4) is a separate permitted action.
6. Write `.hivemind/handoffs/<slug>.md` using the exact section set below.
7. Verify `.hivemind/plans/<slug>.md` exists before reporting success. If it is still missing, surface the failure; never report a handoff that points at a nonexistent plan.
8. Report the written path to the user, with no follow-up questions. This completes this skill's own procedure. The skill then returns control to whatever invoked it; the caller then continues from the point at which it invoked this skill.

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

Section rules: `<Initiative>` is the human-readable initiative name, not the slug. The plan pointer, the single blockquote line directly under the title, is always present and always tells the reader to read the plan first. **What this delivers** distills the target outcome to a few lines. **FIRST ACTION** step 1 is always "Read the plan fully." **Locked decisions (DO NOT RELITIGATE)** lists settled decisions one line each, lifted as references, not re-argued. **Open questions** holds only genuinely open items, else `NONE (all resolved)`. **Pointers** lists paths to durable artifacts (plan, PRD, ADRs, glossary, reference material), not their contents.

Never add, remove, rename, or reorder sections. A reader who needs the full rationale follows a pointer to the plan or PRD.

## Output is ephemeral

`.hivemind/` is gitignored, so the handoff is disposable session state, consumed by a fresh session and discarded, not a durable committed artifact like a PRD or ADR. A `.hivemind/plans/<slug>.md` this skill materializes from live context is the same ephemeral session scaffolding (D11). Never `git add`, stage, commit, push, or open a PR; the caller handles the commit/push/PR lifecycle. This skill has no git tools and must not acquire them.
