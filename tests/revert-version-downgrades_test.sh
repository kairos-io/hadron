#!/bin/sh
#
# Exercises .github/scripts/revert-version-downgrades.sh, which keeps the
# autobumper from opening a pull request that moves a version backwards
# (#814: openssh 10.6p2 to 10.6p1).
#
# Builds a throwaway git repository with a committed Dockerfile, rewrites it
# the way `updatecli apply` would, and checks which ARGs the script puts back.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/.github/scripts/revert-version-downgrades.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

git init -q .
cat > Dockerfile <<'EOF'
ARG OPENSSH_VERSION=10.6p2
ARG SHADOW_VERSION=4.18.0
ARG ZLIB_VERSION=1.3.1
ARG KERNEL_VERSION=6.12.9
ARG TZDATA_VERSION=2025b
ARG UNTOUCHED_VERSION=2.0
ARG OPENSSH_VERSION_NOTE=keep
FROM scratch
EOF
git add Dockerfile
git -c user.name=t -c user.email=t@t commit -q -m base

# What a bad updatecli run leaves behind: two downgrades and three real bumps.
cat > Dockerfile <<'EOF'
ARG OPENSSH_VERSION=10.6p1
ARG SHADOW_VERSION=3.3.1
ARG ZLIB_VERSION=1.3.2
ARG KERNEL_VERSION=6.12.10
ARG TZDATA_VERSION=2025c
ARG UNTOUCHED_VERSION=2.0
ARG OPENSSH_VERSION_NOTE=keep
FROM scratch
EOF

out=$(sh "$script")
echo "$out"

failures=0
want() {
	if grep -qxF "$1" Dockerfile; then
		echo "ok: $1"
	else
		echo "FAIL: want line '$1'" >&2
		failures=$((failures + 1))
	fi
}

want 'ARG OPENSSH_VERSION=10.6p2'
want 'ARG SHADOW_VERSION=4.18.0'
want 'ARG ZLIB_VERSION=1.3.2'
want 'ARG KERNEL_VERSION=6.12.10'
want 'ARG TZDATA_VERSION=2025c'
want 'ARG UNTOUCHED_VERSION=2.0'
want 'ARG OPENSSH_VERSION_NOTE=keep'
want 'FROM scratch'

case "$out" in
*"2 downgrade(s) reverted"*) echo "ok: reports 2 reverts" ;;
*) echo "FAIL: expected 2 reverts in output" >&2; failures=$((failures + 1)) ;;
esac

# Nothing changed: the script is a no-op and leaves the file as committed.
git checkout -q Dockerfile
sh "$script" > /dev/null
if git diff --quiet; then
	echo "ok: clean tree stays clean"
else
	echo "FAIL: clean tree was modified" >&2
	failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] || exit 1
echo "all revert-version-downgrades checks passed"
