# Report Format

YAML report schemas for worker agents.

## Worker Report — Complete

```yaml
status: complete
step: STEP-001
outcome: [what was accomplished]
changed: [file1, file2]
validated:
  check_name: pass|fail
version: required|none|unknown
scope_out: ["*"]
decisions:
  DEC-001: [decision and rationale]
risks:
  RISK-001: "[description] (low|medium|high)"
assumptions:
  ASM-001: [assumption]
evidence:
  EVD-001: [one-line synopsis]
next: [what next phase must do]
risk_level: low|medium|high
```

## Worker Report — Blocked

```yaml
status: blocked
stage: [planning|implementation|validation|git|versioning|review|review remediation|monitoring|fetch|skill selection|post-fix|route|destructive-fix-gate]
blocker: [one-line reason]
retry: [not attempted|retried once|exhausted]
impact: [what cannot proceed]
next: [specific next step]
```

## Worker Report — Trivial

```yaml
status: complete
changed: [file]
validated:
  check: pass
evidence:
  EVD-001: [synopsis]
```
