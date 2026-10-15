#!/bin/sh
#
# Decides what the autobumper should do with the pull request of a bump
# branch. Reads the output of
#
#   gh pr list --head <branch> --base main --state all --json number,state
#
# on standard input and prints one of:
#
#   open <number>     a pull request for this branch is open, update it
#   closed <number>   a pull request was closed without merging, reopen it
#   merged <number>   the newest pull request was merged, open a new one
#   none              this branch has never had a pull request
#
# The branch name is stable per bump group (`bumps-<group>`), so one branch
# collects one pull request per bump over the life of the group and only the
# newest matters. `gh pr list` returns them newest first.
#
# Merged has to be told apart from closed, otherwise the group's next bump
# would edit the pull request that carried the previous one and never open its
# own. `gh pr list --json state` reports a merged pull request as MERGED, so
# the distinction costs no extra call.

set -eu

decision=$(jq -r '
  (.[0] // {}) as $pr
  | if   $pr.state == "OPEN"   then "open \($pr.number)"
    elif $pr.state == "CLOSED" then "closed \($pr.number)"
    elif $pr.state == "MERGED" then "merged \($pr.number)"
    else "none"
    end
')

# Empty input is not "no pull request". jq reads it as nothing at all and says
# so by printing nothing, and a caller that read that as "none" would open a
# second pull request every time the listing call failed, which is the bug this
# script exists to end.
if [ -z "$decision" ]; then
	echo "bump-pr-action.sh: no pull request listing on standard input" >&2
	exit 1
fi

echo "$decision"
