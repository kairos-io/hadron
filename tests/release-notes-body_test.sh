#!/bin/sh
#
# Exercises .github/scripts/release-notes-body.sh, which builds the release
# body the release-notes job writes back for a tag (kairos-io/kairos#5644).
#
# Re-running the job for a tag used to append a second "Shipped components"
# section to the body. Each case below feeds the script its own output again,
# the way a re-run sees the body the previous run wrote, and checks the body
# still has one section, the newest manifest, and the notes above it.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/.github/scripts/release-notes-body.sh"
heading='## 📦 Shipped components'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0

fail() {
	echo "FAIL: $1" >&2
	failures=$((failures + 1))
}

sections() {
	grep -c "^$heading" "$1" || true
}

printf '%s\n' '| component | version |' '|---|---|' '| linux | 6.12.1 |' >"$tmp/components-v1.md"
printf '%s\n' '| component | version |' '|---|---|' '| linux | 6.12.2 |' >"$tmp/components-v2.md"

# A body as `gh release create --generate-notes` leaves it.
printf '%s\n' \
	"## What's Changed" \
	'* fix(build): something by @someone in #1' \
	'' \
	'**Full Changelog**: https://github.com/kairos-io/hadron/compare/v0.0.1...v0.0.2' \
	>"$tmp/generated.md"

sh "$script" "$tmp/generated.md" "$tmp/components-v1.md" >"$tmp/run1.md"
sh "$script" "$tmp/run1.md" "$tmp/components-v1.md" >"$tmp/run2.md"
sh "$script" "$tmp/run2.md" "$tmp/components-v2.md" >"$tmp/run3.md"

n=$(sections "$tmp/run1.md")
[ "$n" = 1 ] || fail "first run: want 1 section, got $n"

n=$(sections "$tmp/run3.md")
[ "$n" = 1 ] && echo "ok: re-runs keep a single components section" \
	|| fail "after three runs: want 1 section, got $n"

cmp -s "$tmp/run1.md" "$tmp/run2.md" && echo "ok: a re-run with the same manifest changes nothing" \
	|| fail "a re-run with the same manifest changed the body: $(diff "$tmp/run1.md" "$tmp/run2.md")"

if grep -q '6.12.2' "$tmp/run3.md" && ! grep -q '6.12.1' "$tmp/run3.md"; then
	echo "ok: a re-run replaces the manifest with the new one"
else
	fail "after a re-run with a new manifest, the body does not carry only the new one"
fi

head -n 4 "$tmp/run3.md" | cmp -s - "$tmp/generated.md" && echo "ok: notes above the section are kept" \
	|| fail "notes above the section were not kept: $(head -n 4 "$tmp/run3.md")"

# A body edited in the web UI comes back from the API with CRLF line endings.
sed 's/$/\r/' "$tmp/run1.md" >"$tmp/crlf.md"
sh "$script" "$tmp/crlf.md" "$tmp/components-v1.md" >"$tmp/crlf-run.md"
n=$(sections "$tmp/crlf-run.md")
[ "$n" = 1 ] && echo "ok: a CRLF body keeps a single components section" \
	|| fail "CRLF body: want 1 section, got $n"

# An empty body, for when `gh release view` fails and the job falls back to ''.
: >"$tmp/empty.md"
sh "$script" "$tmp/empty.md" "$tmp/components-v1.md" >"$tmp/empty-run.md"
n=$(sections "$tmp/empty-run.md")
[ "$n" = 1 ] && echo "ok: an empty body gets the section" \
	|| fail "empty body: want 1 section, got $n"

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi
