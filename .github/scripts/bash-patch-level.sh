#!/bin/sh
#
# Prints the number of official patches GNU has published for a bash release,
# the PATCH_LEVEL the Dockerfile applies. Used by the bash_patch_level source in
# updatecli.d/core-system.yaml.
#
#   bash-patch-level.sh <version>      e.g. bash-patch-level.sh 5.3
#
# A release with no patches yet prints 0: GNU answers 404 for the patches
# directory until the first patch ships, or lists it empty. 0 is a valid
# PATCH_LEVEL everywhere it is read, so the bump goes ahead
# (kairos-io/kairos#5841). Any other failure (no connection, a 5xx, an
# unexpected status) exits 1, so an outage never drops the patches of a
# release that has them.

set -u

version=$1
version_nodot=$(printf '%s' "$version" | tr -d '.')
url="${BASH_PATCHES_BASE_URL:-https://ftp.gnu.org/gnu/bash}/bash-${version}-patches/"

listing=$(mktemp)
trap 'rm -f "$listing"' EXIT

fail() {
	echo "unable to determine bash patch level for ${version}: $1" >&2
	exit 1
}

# Prints the HTTP status of a request, 000 when there was no answer at all.
status() {
	curl -sSL --retry 3 -w '%{http_code}' "$@"
}

code=$(status -o "$listing" "$url")
case $code in
	200) ;;
	404)
		printf '0'
		exit 0
		;;
	*) fail "$url answered HTTP $code" ;;
esac

patch_level=$(
	grep -oE "bash${version_nodot}-[0-9]{3}" "$listing" \
		| sed -E "s/^bash${version_nodot}-0*//" \
		| sort -n \
		| tail -n 1
)

# The listing did not name any patch, so probe the files one by one. Three
# misses in a row end the search.
if [ -z "$patch_level" ]; then
	patch_level=0
	misses=0
	i=1

	while [ "$misses" -lt 3 ]; do
		candidate=$(printf '%03d' "$i")
		code=$(status -I -o /dev/null "${url}bash${version_nodot}-${candidate}")
		case $code in
			200)
				patch_level=$i
				misses=0
				;;
			404) misses=$((misses + 1)) ;;
			*) fail "${url}bash${version_nodot}-${candidate} answered HTTP $code" ;;
		esac
		i=$((i + 1))
	done
fi

printf '%s' "$patch_level"
