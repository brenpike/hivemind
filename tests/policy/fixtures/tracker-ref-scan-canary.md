---
name: tracker-ref-scan-canary
description: frontmatter cites #11 here
---

<!-- Line numbers in this file are pinned by the CHECK 15 SCANNER CANARY in
     tools/policy_check.sh -- edit both together, or the canary asserts against
     lines that no longer hold what it names. This file is a test fixture, not
     documentation. -->

# tracker-ref scan canary

Body prose cites #21 as a tracker id.

```text
Fenced text cites #31 and must still be scanned.
```

- A list item whose continuation line is indented four spaces.
    Indented continuation cites #41 and must still be scanned.

Adjacent refs #12 #34 and later #56.

## Heading 2

```bash
#!/usr/bin/env bash
```

Letter-bearing colour #1a2b3c stays legal.

See [the section](#section-2) for details.

Inline placeholder `#123` stays legal.

Upstream cli/cli#12258 citation stays legal.
