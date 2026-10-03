#!/usr/bin/env bash
#
# check13-unlisted-canary.sh -- scanner-canary fixture for tools/policy_check.sh CHECK 13.
# Never executed, outside plugin/, and carries no allowlist entry. Every exception
# phrase below sits outside a full-line prologue comment -- in an inline comment and
# a string literal on the first executable lines, and after the first executable
# line -- so the scanner must not recognize any of them.
set -u # P18 FLOOR EXCEPTION: inline on an executable line, so it is not recognized.
printf '%s\n' 'P18 FLOOR EXCEPTION: in a string literal, so it is not recognized.'
# P18 FLOOR EXCEPTION: placed after the first executable line, so it is not recognized.
