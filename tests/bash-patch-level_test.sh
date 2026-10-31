#!/bin/sh
#
# Exercises .github/scripts/bash-patch-level.sh, the bash_patch_level source of
# updatecli.d/core-system.yaml (kairos-io/kairos#5841).
#
# A bash release GNU has not patched yet must give 0, not an error: the source
# failing aborts the whole core-system bump group. A network failure must still
# fail, so an outage never resets PATCH_LEVEL to 0. A fake curl on PATH answers
# from a routes file of "<url> <status|down> [body file]" lines; any other URL
# gets 404.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/.github/scripts/bash-patch-level.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/bin"
cat > "$work/bin/curl" <<'FAKE'
#!/bin/sh
out=
url=
while [ $# -gt 0 ]; do
	case $1 in
		-o) out=$2; shift ;;
		-w|--retry) shift ;;
		-*) ;;
		*) url=$1 ;;
	esac
	shift
done
status=404
body=
while read -r route_url route_status route_body; do
	if [ "$route_url" = "$url" ]; then
		status=$route_status
		body=$route_body
	fi
done < "$FAKE_CURL_ROUTES"
if [ "$status" = down ]; then
	echo "curl: (7) Failed to connect" >&2
	exit 7
fi
if [ -n "$out" ] && [ -n "$body" ]; then
	cp "$body" "$out"
elif [ -n "$out" ]; then
	: > "$out"
fi
printf '%s' "$status"
FAKE
chmod +x "$work/bin/curl"

base=https://ftp.gnu.org/gnu/bash
failures=0

# check <name> <version> <want output> <want exit status> <routes...>
check() {
	name=$1
	version=$2
	want=$3
	want_rc=$4
	shift 4
	printf '%s\n' "$@" > "$work/routes"

	rc=0
	got=$(PATH="$work/bin:$PATH" FAKE_CURL_ROUTES="$work/routes" sh "$script" "$version" 2>/dev/null) || rc=$?
	if [ "$got" = "$want" ] && [ "$rc" = "$want_rc" ]; then
		echo "ok: $name"
	else
		echo "FAIL: $name: want '$want' exit $want_rc, got '$got' exit $rc" >&2
		failures=$((failures + 1))
	fi
}

cat > "$work/listing-5.3" <<'HTML'
<a href="bash53-001">bash53-001</a>
<a href="bash53-001.sig">bash53-001.sig</a>
<a href="bash53-002">bash53-002</a>
<a href="bash53-003">bash53-003</a>
HTML
: > "$work/listing-empty"
echo '<html><body>no index here</body></html>' > "$work/listing-unparsed"

check "the listing gives the highest patch" 5.3 3 0 \
	"$base/bash-5.3-patches/ 200 $work/listing-5.3"

check "a release whose patches directory does not exist yet is level 0" 5.4 0 0 \
	"$base/bash-5.4-patches/ 404"

check "an empty patches directory is level 0" 5.4 0 0 \
	"$base/bash-5.4-patches/ 200 $work/listing-empty"

check "an unparsed listing falls back to probing each patch" 5.3 2 0 \
	"$base/bash-5.3-patches/ 200 $work/listing-unparsed" \
	"$base/bash-5.3-patches/bash53-001 200" \
	"$base/bash-5.3-patches/bash53-002 200"

check "a connection failure on the listing fails" 5.3 "" 1 \
	"$base/bash-5.3-patches/ down"

check "a server error on the listing fails" 5.3 "" 1 \
	"$base/bash-5.3-patches/ 503"

check "a connection failure while probing fails" 5.3 "" 1 \
	"$base/bash-5.3-patches/ 200 $work/listing-unparsed" \
	"$base/bash-5.3-patches/bash53-001 200" \
	"$base/bash-5.3-patches/bash53-002 down"

if [ "$failures" -ne 0 ]; then
	echo "$failures case(s) failed" >&2
	exit 1
fi
