<!-- Line numbers in this file are pinned by the CHECK 15 SCANNER CANARY in
     tools/policy_check.sh -- edit both together, or the canary asserts against
     lines that no longer hold what it names. Append new cases at the END so the
     pinned lines keep their numbers. This file is a test fixture, not
     documentation. -->

# tracker-ref allowlist canary

Glued issue#123 is flagged.

Glued PR#456 is flagged.

Glued x#9 is flagged.

Double-backtick ``#123`` stays legal.

Triple-backtick ```#123``` stays legal.

Unclosed double ``#123 is flagged.

Unclosed triple ```#123 is flagged.

A ``code`` span then #123 is flagged.

See [the section](#2-section) for details.

Bare anchor text (#2-slug) is flagged.

Mixed cli/cli#1 and issue#2 and `#3` and #4 on one line.

Host path example.com/a/b#12 is flagged.

Linked [cli/cli#12258](https://github.com/cli/cli/pull/12258) stays legal.

Right-bounded candidate #1a2b3c stays legal.

Mismatched ``#123` run is flagged.
