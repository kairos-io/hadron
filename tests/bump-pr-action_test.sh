#!/bin/sh
#
# Exercises .github/scripts/bump-pr-action.sh, the autobumper's decision about
# the pull request of a bump branch (kairos-io/kairos#5491).
#
# The script reads real `gh pr list --json number,state` output on standard
# input, so this needs no fake `gh` and no network: every case below is a
# response that endpoint actually returns. The MERGED case is the one that
# matters. The branch name is now stable per bump group, so a group's branch
# keeps the pull request of its previous bump, and reading MERGED as "a pull
# request already exists, edit it" would mean the next bump never opened one.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/.github/scripts/bump-pr-action.sh"

failures=0

check() {
	name=$1
	input=$2
	want=$3

	got=$(printf '%s' "$input" | sh "$script")
	if [ "$got" = "$want" ]; then
		echo "ok: $name"
	else
		echo "FAIL: $name: want '$want', got '$got'" >&2
		failures=$((failures + 1))
	fi
}

# Taken from `gh pr list --head bumps-vm-tools-3abfe5c6... --state all` while
# kairos-io/hadron#715 was open.
check "an open pull request is updated in place" \
	'[{"number":715,"state":"OPEN"}]' \
	"open 715"

# kairos-io/hadron#674, closed without merging when its duplicate #679 merged.
check "a pull request closed without merging is reopened" \
	'[{"number":674,"state":"CLOSED"}]' \
	"closed 674"

# kairos-io/hadron#689. gh reports a merged pull request as MERGED, not as
# CLOSED, which is what lets the next bump of the group open its own.
check "a merged pull request does not block the next bump" \
	'[{"number":689,"state":"MERGED"}]' \
	"merged 689"

check "a branch with no pull request gets one" \
	'[]' \
	"none"

# gh returns the newest first, and only the newest says what to do now: the
# branch of a bump group accumulates one pull request per bump.
check "the newest pull request on the branch decides" \
	'[{"number":720,"state":"OPEN"},{"number":715,"state":"MERGED"}]' \
	"open 720"

check "a reopened branch whose older pull request merged" \
	'[{"number":720,"state":"CLOSED"},{"number":715,"state":"MERGED"}]' \
	"closed 720"

# A listing call that failed leaves nothing on the pipe. Reading that as "no
# pull request" would open a second one, so it has to be an error.
if printf '' | sh "$script" 2>/dev/null; then
	echo "FAIL: an empty listing is accepted as 'no pull request'" >&2
	failures=$((failures + 1))
else
	echo "ok: an empty listing is an error, not 'no pull request'"
fi

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi

echo "all bump-pr-action checks passed"
