#!/bin/sh
#
# Reads the output of `docker buildx build --check` (file $1) and prints the
# ERROR lines that are real failures, one per line. An error about a
# hadron-sources image that is not published yet is not a failure on a pull
# request: populate-sources publishes a new source on a pull request from
# this repository and on main, never on a fork. ghcr reports such an image
# two ways: "not found", or, for a package that does not exist at all, a 403
# from its anonymous token endpoint. Both are left out here; the caller turns
# them into warnings. Exit 0 always; an empty output means no real error.

set -eu

log=$1
grep '^ERROR:' "$log" |
	grep -v -E 'hadron-sources/[^ ]*: (not found|failed to resolve source metadata for [^ ]*: failed to authorize: failed to fetch anonymous token: unexpected status from GET request to https://ghcr\.io/token\?scope=repository%3Akairos-io%2Fhadron-sources%2F[^ ]*: 403 Forbidden)$' ||
	true
