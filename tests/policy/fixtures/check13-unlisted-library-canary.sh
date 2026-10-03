# shellcheck shell=bash
#
# check13-unlisted-library-canary.sh -- scanner-canary fixture for tools/policy_check.sh CHECK 13.
# A sourced-library shape: no shebang, no set, never executed, outside plugin/, and no
# allowlist entry. Every exception phrase below sits after the first statement, inside a
# function body and after it, so the scanner must not recognize any of them.
canary_helper() {
    # P18 FLOOR EXCEPTION: inside a function body, so it is not recognized.
    :
}
# P18 FLOOR EXCEPTION: after the first statement, so it is not recognized.
