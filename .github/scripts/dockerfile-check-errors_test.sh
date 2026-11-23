#!/bin/sh
#
# Exercises .github/scripts/dockerfile-check-errors.sh: an unpublished
# hadron-sources image (ghcr's "not found", or its 403 for a package that does
# not exist yet) is not a failure; every other error is.

set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_root/.github/scripts/dockerfile-check-errors.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

expect() { # name, log content, expected output
	printf '%s\n' "$2" > "$work/log"
	got=$("$script" "$work/log")
	if [ "$got" = "$3" ]; then
		echo "ok: $1"
	else
		echo "FAIL: $1"
		echo "  want: $3"
		echo "  got:  $got"
		fail=1
	fi
}

notfound='ERROR: ghcr.io/kairos-io/hadron-sources/talloc:2.4.3: not found'
forbidden='ERROR: ghcr.io/kairos-io/hadron-sources/nftables:1.1.7: failed to resolve source metadata for ghcr.io/kairos-io/hadron-sources/nftables:1.1.7: failed to authorize: failed to fetch anonymous token: unexpected status from GET request to https://ghcr.io/token?scope=repository%3Akairos-io%2Fhadron-sources%2Fnftables%3Apull&service=ghcr.io: 403 Forbidden'
other_403='ERROR: quay.io/kairos/other:1: failed to resolve source metadata for quay.io/kairos/other:1: failed to authorize: failed to fetch anonymous token: unexpected status from GET request to https://quay.io/v2/auth: 403 Forbidden'
lint='ERROR: Dockerfile:12: FROM references an undefined stage "nope"'
step='#4 ERROR: failed to authorize: something'

expect "an unpublished source (not found) is no error" "$notfound" ""
expect "an unpublished source (ghcr 403) is no error" "$forbidden" ""
expect "both kinds together are no error" "$notfound
$forbidden" ""
expect "a 403 for another registry is an error" "$other_403" "$other_403"
expect "a lint error is an error" "$lint" "$lint"
expect "a lint error next to an unpublished source is still an error" "$forbidden
$lint" "$lint"
expect "BuildKit's numbered step lines are ignored" "$step" ""
expect "no errors at all" "#1 DONE 0.1s" ""

exit $fail
