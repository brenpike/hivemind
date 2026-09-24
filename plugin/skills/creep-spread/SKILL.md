---
name: creep-spread
description: >-
  Generates or enriches CONTEXT.md (or CONTEXT-MAP.md and per-context files for multi-context repos)
  with domain terms extracted from project artifacts. Use when seeding a new hive, building a
  domain glossary, or updating CONTEXT.md.
allowed-tools:
  - Read
  - Write
  - Bash(git rev-parse *)
  - Bash(find *)
  - Bash(ls *)
  - Bash(wc *)
  - Bash(jq *)
  - Bash(test *)
  - Bash(basename *)
  - Bash(grep *)
shell: bash
---

## Quick Reference

Before:
- [ ] Project root resolved via `git rev-parse --show-toplevel`
- [ ] Project root resolved and artifact files accessible
- [ ] At least one project artifact readable (README.md, CLAUDE.md, package manifest, or source files)

After:
- [ ] CONTEXT.md or CONTEXT-MAP.md created following canonical format
- [ ] Terms extracted from actual project artifacts, not invented
- [ ] General programming terms excluded per CONTEXT-FORMAT.md Rules

# Creep Spread

Analyze a project's existing artifacts and generate a populated domain glossary following the canonical format defined in `${CLAUDE_PLUGIN_ROOT}/skills/plan-interrogation/references/CONTEXT-FORMAT.md`.

## When to Use

- New project adopting the hivemind plugin (called by seed-hive)
- Existing project that lacks a CONTEXT.md
- Existing project where CONTEXT.md needs enrichment with newly discovered terms
- After significant project changes (new modules, renamed concepts)

## Required Inputs

None. Operates on the current project root resolved via `git rev-parse --show-toplevel`.

## Procedure

1. Resolve project root via `git rev-parse --show-toplevel`. Stop blocked if not a git repository.

2. **Mode detection:** Check for existing context files at the project root.
   - If `<project root>/CONTEXT-MAP.md` exists: set `mode: update-multi`. Read existing CONTEXT-MAP.md and all referenced per-context CONTEXT.md files. Extract existing term names (lines matching `**Term**:` pattern) into a known-terms set.
   - If `<project root>/CONTEXT.md` exists: set `mode: update`. Read existing CONTEXT.md. Extract existing term names (lines matching `**Term**:` pattern) into a known-terms set.
   - If neither exists: set `mode: create`. Known-terms set is empty.

3. **Resolve project name:** Try in order:
   a. `jq -r '.name // empty' package.json 2>/dev/null`
   b. First `# ` heading in `README.md`
   c. `basename` of project root directory, with hyphens/underscores replaced by spaces, title-cased

4. **Multi-context detection:** Determine `multi_context` based on mode:
   - If `mode: update` (a root CONTEXT.md exists without CONTEXT-MAP.md): an existing root CONTEXT.md is authoritative for the single-context case per CONTEXT-FORMAT.md ("If only a root CONTEXT.md exists, single context"). Set `multi_context: false` initially. Still run the directory heuristic (same as `mode: create`: scan `src/`, `services/`, `packages/`, `apps/`, `modules/`, `libs/`, `crates/`, `workspaces/` for directories containing 2+ subdirectories with source files). If 2+ bounded context directories are detected, override to `multi_context: true` — this allows Step 5 (Root CONTEXT.md conflict check) to fire and block for manual conversion.
   - If `mode: update-multi` (CONTEXT-MAP.md exists): CONTEXT-MAP.md is authoritative for existing entries — do not overwrite or re-detect them. Set `multi_context: true` unconditionally. Also run the directory heuristic (same as `mode: create`: scan `src/`, `services/`, `packages/`, `apps/`, `modules/`, `libs/`, `crates/`, `workspaces/` for directories containing 2+ subdirectories with source files). Compare found directories against contexts already listed in CONTEXT-MAP.md; any found directory not already mapped is flagged as a newly detected bounded context for addition.
   - If `mode: create`: scan for top-level directories that indicate bounded contexts, such as: `src/`, `services/`, `packages/`, `apps/`, `modules/`, `libs/`, `crates/`, `workspaces/`. For each found, check if it contains 2+ subdirectories with source files. If 2+ bounded context directories are detected, set `multi_context: true`. Otherwise `multi_context: false`.

5. **Root CONTEXT.md conflict check:** If `multi_context: true` AND `mode: update` (root CONTEXT.md exists but no CONTEXT-MAP.md):
   Stop blocked with reason: "Root CONTEXT.md exists but project layout requires multi-context (CONTEXT-MAP.md + per-context CONTEXT.md files). Delete the root CONTEXT.md and re-run creep-spread, or proceed manually." Do NOT auto-delete or auto-convert.

6. **Artifact discovery:** Read the following files if they exist (first 200 lines each to stay within budget):
   a. `CLAUDE.md` — project rules, architecture, conventions
   b. `AGENT.md` or `AGENTS.md` — agent instructions
   c. `README.md` — project description, key concepts
   d. `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod` — project name, deps
   e. Top-level directory listing (`ls -1`)
   f. Source file names in key directories (use `find . -maxdepth 3 -name '*.ts' -o -name '*.tsx' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.cs' -o -name '*.rb' | head -100`)
   g. Grep for domain type declarations: `grep -rn 'class \|interface \|type \|enum \|struct \|trait \|model \|schema ' --include='*.ts' --include='*.py' --include='*.go' --include='*.rs' --include='*.java' --include='*.cs' --include='*.rb' -l | head -50` — capture filenames only, then read first 5 lines of each match for the declaration name

7. **Term extraction:** From the artifacts gathered in step 6, identify domain-specific terms. Apply these filters:
   - **Include:** Terms that represent concepts unique to this project's domain — entities, aggregates, value objects, domain events, bounded context names, business rules, workflows
   - **Exclude:** General programming terms — controller, service, repository, handler, middleware, util, helper, config, error, response, request, manager, factory, provider, adapter, wrapper, base, abstract, interface (the keyword), type (the keyword), enum (the keyword), model (the keyword when used generically)
   - **Group:** When natural clusters emerge (3+ related terms), organize under subheadings
   - For each term: write a one-sentence definition based on how it's used in the project artifacts. Add `_Avoid_:` aliases if synonyms are evident.
   - **Deduplicate:** Compare each extracted term against the known-terms set (case-insensitive). Skip any term already present in the existing CONTEXT.md. This ensures re-running the skill never adds duplicates.

8. **Relationship extraction:** From the artifacts, identify relationships between extracted terms. Express cardinality where obvious (one-to-many, belongs-to, produces, consumes, etc.).

9. **Generate output file(s):**

   **If `multi_context: false` and `mode: create`:**
   Create `<project root>/CONTEXT.md` following the format in `${CLAUDE_PLUGIN_ROOT}/skills/plan-interrogation/references/CONTEXT-FORMAT.md`:
   ```
   # {Project Name}

   {One sentence description derived from README or CLAUDE.md}

   ## Language

   {Extracted terms with definitions and Avoid lists}

   ## Relationships

   {Extracted relationships between terms}

   ## Example dialogue

   > **Dev:** "{A realistic question using 2-3 of the extracted terms}"
   > **Domain expert:** "{A clarifying answer that demonstrates term boundaries}"

   ## Flagged ambiguities

   {Any terms that appeared with multiple meanings in the artifacts, or "None detected during bootstrap"}
   ```

   **If `multi_context: false` and `mode: update`:**
   Read existing `<project root>/CONTEXT.md`. Append new terms (not in known-terms set) to the `## Language` section. Append new relationships to the `## Relationships` section. Do NOT modify or remove any existing content. If no new terms were found, report `status: complete, terms_added: 0`.

   **If `multi_context: true` and `mode: create`:**
   Create `<project root>/CONTEXT-MAP.md` listing each bounded context with a relative path to its CONTEXT.md. Create a `CONTEXT.md` inside each bounded context directory with terms relevant to that context. Cap at 20 contexts.

   **If `multi_context: true` and `mode: update-multi`:**
   Read existing CONTEXT-MAP.md. Add any newly detected bounded contexts. For each per-context CONTEXT.md, append new terms not in that file's known-terms set. Do NOT modify or remove existing content.

10. Report output.

## Term Quality Rules

Apply the Rules defined in `${CLAUDE_PLUGIN_ROOT}/skills/plan-interrogation/references/CONTEXT-FORMAT.md` (Rules) — that file is the single source and they are not restated here.

## Do Not

- Modify or remove any existing content in CONTEXT.md / CONTEXT-MAP.md — only append
- Remove terms
- Invent domain terms not evidenced in project artifacts
- Include general programming concepts as terms
- Read full source file contents — use structural signals (filenames, declarations, grep) only
- Commit, push, or touch git state
- Exceed 20 bounded contexts in multi-context mode
- Auto-convert a root CONTEXT.md to multi-context layout — stop blocked and inform the user

## Output

```text
status: complete | blocked
reason: <text>  # when blocked

project_root:
- [absolute path]

project_name:
- [resolved name]

mode:
- [create | update | update-multi]

multi_context:
- [true | false]

files_created:
- [list of created files, empty when mode is update or update-multi]

terms_extracted:
- [count]

terms_added:
- [count of new terms added (0 when all discovered terms already exist)]

term_sources:
- [list of artifact files that contributed terms]

```

Use the Worker Report — Blocked schema from `${CLAUDE_PLUGIN_ROOT}/governance/report-format.md` for blocked states.
