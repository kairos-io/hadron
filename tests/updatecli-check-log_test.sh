#!/bin/sh
#
# Exercises .github/scripts/updatecli-check-log.sh, which turns an updatecli
# run with a failing source red (kairos-io/kairos#6138).
#
# The failing log below is trimmed from what `updatecli apply` 0.123.0 prints
# for a shell source that exits 1. updatecli itself exits 0 on that run and
# reports "Succeeded: 1", which is why the log is all there is to go on.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/.github/scripts/updatecli-check-log.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
esc=$(printf '\033')

pass() {
	echo "ok: $1"
}

fail() {
	echo "FAIL: $1" >&2
	failures=$((failures + 1))
}

# check <name> <logfile> <want exit code> [<line the output must contain>...]
check() {
	name=$1
	log=$2
	want=$3
	shift 3

	rc=0
	out=$(sh "$script" "$log") || rc=$?
	if [ "$rc" -ne "$want" ]; then
		fail "$name: want exit $want, got $rc (output: $out)"
		return
	fi
	for line in "$@"; do
		if ! printf '%s\n' "$out" | grep -qxF "$line"; then
			fail "$name: output lacks '$line' (output: $out)"
			return
		fi
	done
	pass "$name"
}

cat > "$work/clean.log" <<'EOF'
source: ok
----------

✔ shell command executed successfully

target: fine
------------

✔ - all contents from 'file' and 'files' combined already up to date

== SUMMARY ==

✔ probe:
	Source:
		✔ [ok] ok version
	Target:
		✔ [fine] bump fine
EOF
check "a run with no failure passes" "$work/clean.log" 0

cat > "$work/failed.log" <<'EOF'
source: attr
------------

ERROR: failed cloning git repository "https://git.savannah.nongnu.org/git/attr.git"
✗ Something went wrong:
	failed cloning git repository: unexpected EOF

source: ok
----------

✔ shell command executed successfully

target: unifont
---------------

✗ Something went wrong:
	file "Dockerfile" does not exist

== SUMMARY ==

✔ probe:
	Source:
		✗ [attr] attr version
		✔ [ok] ok version
	Target:
		✗ [unifont] bump unifont
EOF
check "a failing source and target fail the run and are named" \
	"$work/failed.log" 1 \
	"::error::source attr went wrong: failed cloning git repository: unexpected EOF" \
	'::error::target unifont went wrong: file "Dockerfile" does not exist'

if sh "$script" "$work/failed.log" | grep -q "source ok"; then
	fail "a source that succeeded is reported"
else
	pass "a source that succeeded is not reported"
fi

printf '%s\n' \
	"${esc}[1msource: attr${esc}[0m" \
	"------------" \
	"${esc}[31m✗ Something went wrong:${esc}[0m" \
	"	shell command failed. Expected exit code 0 but got 1" \
	> "$work/colour.log"
check "a coloured log fails the same way" \
	"$work/colour.log" 1 \
	"::error::source attr went wrong: shell command failed. Expected exit code 0 but got 1"

# updatecli prints the marker for a pipeline that failed before any source
# ran, with no header above it. That still has to fail.
printf '✗ Something went wrong:\n' > "$work/headless.log"
check "a failure outside any source still fails" \
	"$work/headless.log" 1 \
	"::error::updatecli went wrong"

check "a missing log fails" "$work/does-not-exist.log" 1

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi

echo "all updatecli-check-log checks passed"
