#!/usr/bin/env bash
#
# check13-unlisted-canary.sh -- scanner-canary fixture for tools/policy_check.sh CHECK 13.
# Never executed, outside plugin/, and carries no allowlist entry. Its marker sits after
# the first executable line, outside the prologue, so the scanner must not recognize it.
set -u
printf '%s\n' 'never executed'
# P18 FLOOR EXCEPTION: placed after the first executable line, so it is not recognized.
