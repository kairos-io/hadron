#!/bin/sh
#
# Every local source a Dockerfile COPY or ADD names must survive .dockerignore,
# otherwise the stage that copies it cannot build (kairos-io/kairos#5743: the
# test1 stage copied tests/gcc/test.c while .dockerignore excluded tests/).
#
# This builds a FROM scratch image that copies each of those sources from the
# real build context, with the repository's .dockerignore applied. It needs a
# docker daemon but no network and no base image.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Local sources: COPY/ADD lines without --from, not heredocs, not URLs.
# Every argument but the last is a source.
grep -E '^[[:space:]]*(COPY|ADD)[[:space:]]' Dockerfile \
	| grep -v -- '--from' \
	| grep -v '<<' \
	| while read -r _ args; do
		# Keep globs such as files/pam/* for docker to expand.
		set -f
		set -- $args
		while [ $# -gt 1 ]; do
			case "$1" in
				--*|http://*|https://*) ;;
				*) echo "$1" ;;
			esac
			shift
		done
	done | sort -u > "$tmp/sources"

if [ ! -s "$tmp/sources" ]; then
	echo "FAIL: found no local COPY or ADD sources in Dockerfile" >&2
	exit 1
fi

{
	echo "FROM scratch"
	n=0
	while read -r src; do
		n=$((n + 1))
		echo "COPY $src /c/$n/"
	done < "$tmp/sources"
} > "$tmp/Dockerfile"

if ! out=$(docker build -q -f "$tmp/Dockerfile" . 2>&1); then
	echo "$out" >&2
	echo "FAIL: a Dockerfile COPY source is missing or excluded by .dockerignore" >&2
	exit 1
fi
docker rmi -f "$(echo "$out" | tail -n 1)" >/dev/null 2>&1 || true

echo "ok: $(wc -l < "$tmp/sources") Dockerfile COPY sources are in the build context"
