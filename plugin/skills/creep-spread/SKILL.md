---
name: creep-spread
description: Generates or enriches CONTEXT.md (or CONTEXT-MAP.md) with domain terms from project artifacts. Use to build a glossary.
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

# Creep Spread

Analyze a project's existing artifacts and generate or enrich a populated domain glossary in the canonical format of `${CLAUDE_PLUGIN_ROOT}/skills/plan-interrogation/references/CONTEXT-FORMAT.md`: for a new project adopting the hivemind plugin (seed-hive calls this skill), a project without a CONTEXT.md, or one whose CONTEXT.md needs newly discovered terms, such as after new modules or renamed concepts.

## Required Inputs

None. Operates on the project root from `git rev-parse --show-toplevel`, and needs at least one readable project artifact (README.md, CLAUDE.md, a package manifest, or source files).

## Procedure

1. Resolve the project root via `git rev-parse --show-toplevel`. Stop blocked if not a git repository.

2. **Mode detection** at the project root. Each update mode reads the existing files and puts their term names (lines matching the `**Term**:` pattern) into a known-terms set.
   - `<project root>/CONTEXT-MAP.md` exists: `mode: update-multi`. Read it and every per-context CONTEXT.md it references.
   - Else `<project root>/CONTEXT.md` exists: `mode: update`. Read it.
   - Neither exists: `mode: create`. The known-terms set is empty.

3. **Resolve project name:** try in order:
   a. `jq -r '.name // empty' package.json 2>/dev/null`
   b. First `# ` heading in `README.md`
   c. `basename` of project root directory, with hyphens/underscores replaced by spaces, title-cased

4. **Multi-context detection.** The directory heuristic scans `src/`, `services/`, `packages/`, `apps/`, `modules/`, `libs/`, `crates/`, `workspaces/` for directories containing 2+ subdirectories with source files; detecting 2+ bounded context directories is a hit.
   - `mode: create`: `multi_context: true` on a hit, else `false`.
   - `mode: update`: the root CONTEXT.md is authoritative for the single-context case per CONTEXT-FORMAT.md ("If only a root CONTEXT.md exists, single context"), so `multi_context` starts `false`. Still run the heuristic; a hit overrides it to `true`, so step 5 blocks for manual conversion.
   - `mode: update-multi`: `multi_context: true` unconditionally. CONTEXT-MAP.md is authoritative for its existing entries: do not overwrite or re-detect them. Run the heuristic and flag each found directory not already listed in CONTEXT-MAP.md as a newly detected bounded context to add.

5. **Root CONTEXT.md conflict check:** if `multi_context: true` and `mode: update`, stop blocked with reason: "Root CONTEXT.md exists but project layout requires multi-context (CONTEXT-MAP.md + per-context CONTEXT.md files). Delete the root CONTEXT.md and re-run creep-spread, or proceed manually." Never auto-delete or auto-convert.

6. **Artifact discovery:** read each of these that exists, first 200 lines each:
   a. `CLAUDE.md` — project rules, architecture, conventions
   b. `AGENT.md` or `AGENTS.md` — agent instructions
   c. `README.md` — project description, key concepts
   d. `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod` — project name, deps
   e. Top-level directory listing (`ls -1`)
   f. Source file names in key directories (use `find . -maxdepth 3 -name '*.ts' -o -name '*.tsx' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.cs' -o -name '*.rb' | head -100`)
   g. Grep for domain type declarations: `grep -rn 'class \|interface \|type \|enum \|struct \|trait \|model \|schema ' --include='*.ts' --include='*.py' --include='*.go' --include='*.rs' --include='*.java' --include='*.cs' --include='*.rb' -l | head -50` — capture filenames only, then read first 5 lines of each match for the declaration name

7. **Term extraction** from the step 6 artifacts, applying the Rules of `${CLAUDE_PLUGIN_ROOT}/skills/plan-interrogation/references/CONTEXT-FORMAT.md` (Rules):
   - **Include:** Terms that represent concepts unique to this project's domain — entities, aggregates, value objects, domain events, bounded context names, business rules, workflows
   - **Exclude:** General programming terms — controller, service, repository, handler, middleware, util, helper, config, error, response, request, manager, factory, provider, adapter, wrapper, base, abstract, interface (the keyword), type (the keyword), enum (the keyword), model (the keyword when used generically)
   - **Group:** organize natural clusters (3+ related terms) under subheadings
   - Give each term a one-sentence definition based on its use in the artifacts, and `_Avoid_:` aliases when synonyms are evident.
   - **Deduplicate:** skip any term already in the known-terms set (case-insensitive), so re-running the skill never adds duplicates.

8. **Relationship extraction:** identify relationships between extracted terms, with cardinality where obvious (one-to-many, belongs-to, produces, consumes, etc.).

9. **Generate output file(s):**

   **If `multi_context: false` and `mode: create`:**
   Create `<project root>/CONTEXT.md` in the CONTEXT-FORMAT.md format:
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
   Append new terms (not in the known-terms set) to the `## Language` section and new relationships to the `## Relationships` section of `<project root>/CONTEXT.md`. If no new terms were found, report `status: complete, terms_added: 0`.

   **If `multi_context: true` and `mode: create`:**
   Create `<project root>/CONTEXT-MAP.md` listing each bounded context with a relative path to its CONTEXT.md, and a `CONTEXT.md` inside each bounded context directory with that context's terms. Cap at 20 contexts.

   **If `multi_context: true` and `mode: update-multi`:**
   Add newly detected bounded contexts to CONTEXT-MAP.md. Append to each per-context CONTEXT.md the new terms not in that file's known-terms set.

10. Report output.

## Do Not

- Modify or remove any existing content in CONTEXT.md / CONTEXT-MAP.md; only append
- Remove terms
- Invent domain terms not evidenced in project artifacts
- Include general programming concepts as terms
- Read full source file contents; use structural signals (filenames, declarations, grep) only
- Commit, push, or touch git state
- Exceed 20 bounded contexts in multi-context mode
- Auto-convert a root CONTEXT.md to multi-context layout; stop blocked and inform the user

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

Use the schema from `${CLAUDE_PLUGIN_ROOT}/governance/report-format.md` (Worker Report — Blocked) for blocked states.
