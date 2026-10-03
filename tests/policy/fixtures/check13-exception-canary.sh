#!/usr/bin/env bash
#
# check13-exception-canary.sh -- decision-canary fixture for tools/policy_check.sh CHECK 13.
# Never executed. It lives outside plugin/, so the production scan never reaches it;
# the marker-key canary scans it, pins its record, and resolves its allowlist decision.
#
# P18 FLOOR EXCEPTION: fixture-only marker; this file carries set -u alone by design.
set -u
printf '%s\n' 'never executed'
