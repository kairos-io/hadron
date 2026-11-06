#!/bin/sh
#
# Puts back every `ARG <NAME>_VERSION=` in the Dockerfile that `updatecli
# apply` moved to an older version than the one committed at HEAD.
#
# An updatecli dockerfile target writes whatever its source returns. It never
# checks that the new value is newer. So when a source reads a place that lags
# behind the release, or that carries an odd historic tag, the autobumper opens
# a pull request that downgrades the package:
#
#   - #814 took openssh from 10.6p2 back to 10.6p1. 10.6p2 was out on
#     cdn.openbsd.org, but openssh-portable had not tagged V_10_6_P2 yet.
#   - shadow keeps being offered 3.3.1, an old tag that sorts as its newest
#     release, against a 4.x pin.
#
# A deliberate downgrade is a human change, made by hand in its own pull
# request. The autobumper only ever moves a version forward.
#
# Run from the repository root, straight after `updatecli apply` and before
# hack/refresh-source-checksums.sh --changed, so the checksum refresher never
# sees the reverted ARG as changed. Versions are compared with `sort -V`.

set -eu

dockerfile=${1:-Dockerfile}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# NAME<tab>VALUE for every `ARG *_VERSION=value` line.
parse_args() {
	sed -n 's/^ARG \([A-Za-z0-9_]*_VERSION\)=\([^[:space:]]*\)[[:space:]]*$/\1	\2/p'
}

git show "HEAD:$dockerfile" | parse_args > "$work/old"
parse_args < "$dockerfile" > "$work/new"

reverted=0
while IFS='	' read -r name new; do
	old=$(awk -F'	' -v n="$name" '$1 == n { print $2; exit }' "$work/old")
	[ -n "$old" ] && [ -n "$new" ] && [ "$old" != "$new" ] || continue
	lowest=$(printf '%s\n%s\n' "$old" "$new" | sort -V | head -n 1)
	[ "$lowest" = "$new" ] || continue
	echo "::warning::$name: updatecli offered $new, older than $old at HEAD; keeping $old"
	# Versions carry dots, so match the line literally rather than as a regex.
	awk -v line="ARG $name=$new" -v keep="ARG $name=$old" \
		'$0 == line { print keep; next } { print }' "$dockerfile" > "$work/Dockerfile"
	cat "$work/Dockerfile" > "$dockerfile"
	reverted=$((reverted + 1))
done < "$work/new"

echo "revert-version-downgrades: $reverted downgrade(s) reverted"
