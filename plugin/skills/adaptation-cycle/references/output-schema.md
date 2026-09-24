Read this file when parsing Codex CLI stdout output in Procedure step 7.

## Output Schema (from codex-plugin-cc)

The `adversarial-review` command returns rendered text to stdout — not JSON. Parse this text to extract structured data. The literal header is `# Codex Adversarial Review` (NOT `# Codex Review`).

**Rendered text format:**

```
# Codex Adversarial Review

Target: <ref>
Verdict: approve | needs-attention

<summary text>

Findings:
- [<severity>] <title> (<file>:<line_start>-<line_end>)
  body text
  Recommendation: <text>
- [<severity>] <title> (<file>:<line_start>)
  body text
```

When there are no findings, the render emits the literal line `No material findings.` in place of the `Findings:` section. An optional `Next steps:` section and/or `Reasoning:` section may be appended after the findings; both use plain `- <text>` bullets (no `[<severity>]` prefix) and are non-finding text.

`<severity>` ∈ {`critical`, `high`, `medium`, `low`} — severity WORDS, not `P0..P4`. The location group inside the parentheses may omit the line suffix entirely (rendered as `(<file>)`) when the finding has no line number.

**Parsing rules:**

- **verdict:** read the explicit `Verdict:` line directly — it is `approve` or `needs-attention`. Do NOT infer the verdict from the presence or absence of findings.
- **summary:** the non-finding text between the `Verdict:` line and the `Findings:` / `No material findings.` line. Lines belonging to a trailing `Next steps:` or `Reasoning:` section, and the `Target:` / `Verdict:` lines themselves, are not part of the summary.
- **findings:** each line matching the prefix `^- \[(critical|high|medium|low)\] ` is a finding entry. (The `- ` bullets under `Next steps:` and `Reasoning:`, and the `- Parse error:` / `- Validation error:` bullets, do NOT match this severity-anchored prefix and are never findings.) Each `- [<severity>] <title> (<location>)` entry is parsed as:
  - `severity`: identity mapping — `critical` → `critical`, `high` → `high`, `medium` → `medium`, `low` → `low` (the rendered severity is already the normalized word).
  - `title`: the text between `] ` and the final ` (` on the entry line. Match the LAST ` (` so titles containing parentheses are preserved.
  - location: the parenthesized group at the end of the entry line (text inside the final `(...)`).
  - `file` / `line_start` / `line_end`: from the location group. Split on the LAST `:` inside the parens so Windows-drive paths such as `C:\x\f.md:10-12` parse correctly: text before the last `:` is the `file`, text after is the line spec. If the line spec matches `^(\d+)(?:-(\d+))?$`, set `line_start` to the first number and `line_end` to the second when present, else equal to `line_start`. If the location has no line suffix (no `:<digits>` at the end), set `file` to the whole location group and `line_start` / `line_end` to `null`.
  - `body`: indented continuation lines following the entry header, up to (but not including) the next `- [<severity>]` finding line, the `Recommendation:` line, or a `Next steps:` / `Reasoning:` section header.
  - `recommendation`: the text of the `  Recommendation: <text>` indented line when present, otherwise empty string. This line terminates the body; it must not be swallowed into body, and it must not consume a following `- [<severity>]` finding line.
  - `confidence`: not present in rendered stdout; set to `null` in normalized output.
- **next_steps:** empty array (the `Next steps:` section, if present, is treated as non-finding trailing text and not extracted into structured findings).

**Empty review (clean path):** `Verdict: approve` followed by `No material findings.` is a clean result — `findings_count` is `0` and verdict is `approve`. It is NOT a block.

**Unexpected output shapes (handled in SKILL step 6, not here):** the JSON-parse-failure render (`Codex did not return valid structured JSON.` with a `- Parse error:` bullet) and the validation-error render (`Codex returned JSON with an unexpected review shape.` with a `- Validation error:` bullet) are blocked as `unexpected output shape` before parsing. Their `- Parse error:` / `- Validation error:` bullets are never parsed as findings.

## Internal Findings Schema (normalized output)

Normalize each finding by adding a stable `id` field (deterministic SHA-256 hash of `file + line_start + line_end + title`) and preserving all Codex fields. The `confidence` field is included but stays `null` (rendered stdout does not carry confidence).

```json
{
  "verdict": "approve | needs-attention",
  "summary": "string",
  "findings": [
    {
      "id": "string (sha256 of file+line_start+line_end+title)",
      "severity": "critical | high | medium | low",
      "title": "string",
      "body": "string",
      "file": "string",
      "line_start": "number | null",
      "line_end": "number | null",
      "confidence": null,
      "recommendation": "string"
    }
  ],
  "next_steps": ["string"],
  "iteration": "number",
  "base": "string"
}
```
