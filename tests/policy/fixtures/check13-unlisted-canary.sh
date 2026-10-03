#!/usr/bin/env bash
#
# check13-unlisted-canary.sh -- scanner-canary fixture for tools/policy_check.sh CHECK 13.
# Never executed, outside plugin/, and carries no allowlist entry. Every exception
# phrase below sits outside the leading comment header -- inline on the first statement,
# after a standalone set, in a string literal, and after a non-set statement -- so the
# scanner must not recognize any of them.
set -u # P18 FLOOR EXCEPTION: inline on the first statement, so it is not recognized.
# P18 FLOOR EXCEPTION: after a standalone set, which closed the header, so it is not recognized.
printf '%s\n' 'P18 FLOOR EXCEPTION: in a string literal, so it is not recognized.'
# P18 FLOOR EXCEPTION: after a non-set statement, so it is not recognized.
