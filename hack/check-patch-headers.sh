#!/bin/sh
#
# Fails when a patch this repository carries against third-party source has no
# header.
#
# AGENTS.md asks every patch under patches/ for four things: what breaks, why
# it breaks on this target and not on the others, where the fix went upstream,
# and the condition for dropping the patch. Three of those are prose only a
# reviewer can grade. The fourth state, "there is nothing to read at all", is
# the one a script can decide, and it is the worst one: a headerless patch
# leaves the next person with the diff and nothing else, so they cannot tell
# which compiler or libc made it necessary and they cannot tell when it is
# safe to delete.
#
# So this checks one thing only. Every patch must carry at least one line of
# prose before its first diff line. `patch` ignores leading text, which is why
# the four patches that do have a header apply exactly the same way.
#
# Reads files, runs nothing, needs no runner. See tests/workflow-secret-gates.sh
# and tests/make-image-tags.sh for the other no-runner style checks, and
# hack/check-patch-headers_test.sh for the fixtures that exercise this script.
#
# Usage: check-patch-headers.sh [patch-dir]

set -eu

patch_dir=${1:-}
if [ -z "$patch_dir" ]; then
	repo_root=$(cd "$(dirname "$0")/.." && pwd)
	patch_dir="$repo_root/patches"
fi

if [ ! -d "$patch_dir" ]; then
	echo "FAIL: $patch_dir is not a directory" >&2
	exit 1
fi

# The first line of the diff itself. A unified diff opens with `--- `, a
# git-formatted one with `diff --git`, a context diff with `*** `, and some
# generators lead with `Index: `. A bare `@@ ` is here so that a fragment with
# no file markers is still recognised as the start of the diff rather than
# read as prose.
diff_start='^(--- |[+][+][+] |[*][*][*] |diff |Index: |@@ )'

# A line that carries metadata rather than an explanation: the `From:` and
# `Subject:` fields a mail-formatted patch starts with. A patch whose whole
# header is those fields has a title and no reason, which is not a header.
meta_line='^[A-Za-z][A-Za-z-]*: '

failures=0
checked=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

pass() {
	echo "ok: $*"
}

# Sorted so the output is stable between runs and between filesystems.
patches=$(find "$patch_dir" -type f -name '*.patch' | sort)

if [ -z "$patches" ]; then
	# A guard that inspects nothing is not a guard that said no. If the
	# patches move somewhere else, this has to go red rather than pass.
	echo "FAIL: no *.patch files found under $patch_dir" >&2
	exit 1
fi

for patch in $patches; do
	checked=$((checked + 1))
	name=${patch#"$patch_dir"/}

	# Everything above the first diff line.
	header=$(awk -v start="$diff_start" '$0 ~ start { exit } { print }' "$patch")

	# At least one line that is neither blank nor a mail header field.
	prose=$(printf '%s\n' "$header" |
		awk -v meta="$meta_line" 'NF && $0 !~ meta { print; exit }')

	if [ -z "$prose" ]; then
		fail "$name has no header. Say what breaks without this patch, why it breaks on this target and not on the others, where the fix went upstream, and when this file can be deleted. patches/0001-audit-syslog-plugin-include-unistd.patch is the model."
	else
		pass "$name"
	fi
done

echo "checked $checked patch file(s) under $patch_dir"

if [ "$failures" -ne 0 ]; then
	echo "$failures patch(es) have no header" >&2
	exit 1
fi

echo "All patch header checks passed"
