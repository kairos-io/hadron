#!/bin/sh
#
# Locks in the tag invariant the Makefile depends on:
#
#   1. build-hadron writes the tag build-kairos reads as BASE_IMAGE;
#   2. that tag is local-only, never a published ghcr.io reference;
#   3. pull-image is the single place a published reference is fetched, and it
#      retags it onto the same local tag;
#   4. all of the above hold for both BOOTLOADER values, against their own
#      image pair.
#
# Everything is read from `make -n`, so this needs no docker daemon and builds
# nothing. See tests/render-fork-sources.sh for the other dry-run style test.

set -eu

# A tag set in the caller's environment would win over the Makefile's `?=` and
# make every assertion below test the caller instead of the tree.
unset IMAGE_NAME PULL_IMAGE_NAME BOOTLOADER ARCH || true

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

pass() {
	echo "ok: $*"
}

# make -n prints @-prefixed recipe lines without running them, and prints a
# backslash-continued recipe with its newlines and inner tabs intact. Fold each
# target's output into one space separated line so a single glob can match
# across a continuation.
recipe() {
	make -n "$1" BOOTLOADER="$2" ARCH=amd64 2>/dev/null | tr '\n\t' '  ' | tr -s ' '
}

# check <description> <haystack> <needle>
contains() {
	case "$2" in
	*"$3"*) pass "$1" ;;
	*) fail "$1: expected to find '$3' in: $2" ;;
	esac
}

lacks() {
	case "$2" in
	*"$3"*) fail "$1: did not expect to find '$3' in: $2" ;;
	*) pass "$1" ;;
	esac
}

# check_bootloader <BOOTLOADER> <expected local tag> <expected published ref>
check_bootloader() {
	bootloader=$1
	local_tag=$2
	published_ref=$3

	hadron=$(recipe build-hadron "$bootloader")
	kairos=$(recipe build-kairos "$bootloader")
	pull=$(recipe pull-image "$bootloader")

	contains "BOOTLOADER=$bootloader: build-hadron tags $local_tag" \
		"$hadron" " -t $local_tag "
	contains "BOOTLOADER=$bootloader: build-kairos bases on $local_tag" \
		"$kairos" " --build-arg BASE_IMAGE=$local_tag "

	# The whole point of the split: neither build target may name a published
	# reference, or a stray docker pull can substitute the base under them.
	lacks "BOOTLOADER=$bootloader: build-hadron pulls in no published ref" \
		"$hadron" "ghcr.io/"
	lacks "BOOTLOADER=$bootloader: build-kairos pulls in no published ref" \
		"$kairos" "ghcr.io/"

	contains "BOOTLOADER=$bootloader: pull-image fetches $published_ref" \
		"$pull" "docker pull --platform=amd64 $published_ref"
	contains "BOOTLOADER=$bootloader: pull-image retags onto $local_tag" \
		"$pull" "docker tag $published_ref $local_tag"
}

check_bootloader grub hadron:local ghcr.io/kairos-io/hadron:main
check_bootloader systemd hadron-trusted:local ghcr.io/kairos-io/hadron-trusted:main

# An explicit IMAGE_NAME must still reach both targets, and must not be
# rewritten by the BOOTLOADER=systemd branch.
custom=$(make -n build-kairos BOOTLOADER=systemd IMAGE_NAME=hadron:mine ARCH=amd64 2>/dev/null | tr '\n\t' '  ' | tr -s ' ')
contains "an explicit IMAGE_NAME survives the systemd branch" \
	"$custom" " --build-arg BASE_IMAGE=hadron:mine "

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi

echo "All image tag checks passed"
