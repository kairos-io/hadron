#!/bin/sh
# The source-cache probe has to survive a stalled connection.
#
# hack/list-missing-sources.sh asks the registry whether each pinned version
# already has a published source-cache image. It runs with `set -eu` and it
# wraps both of its requests in a three-attempt retry, because a rate limit or
# a transient registry error must not be read as "missing" and send the build
# back to an upstream host for a tarball that is in fact cached.
#
# curl reports a timeout or a refused connection as a non-zero exit status,
# not as an HTTP status. Under `set -eu` that exit status propagates out of the
# command substitution the probe assigns from and kills the whole script on the
# first stalled connection, so neither retry ever reaches a second attempt.
# That is what turned kairos-io/hadron#655 red: one `curl: (28) Connection
# timed out` line and an immediate exit 28, with no retry and none of the
# probe's own error text.
#
# This drives the real script with a curl that stalls the way the runner's did.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"

# Counts live in files, not variables: curl runs in a child shell.
mkdir -p "$tmp/calls"

# A curl that fails the way a stalled connection does. STALL_TOKEN and
# STALL_MANIFEST say how many of the first calls of each kind exit 28 after
# writing the `000` that curl writes on a failed transfer.
cat > "$tmp/bin/curl" <<'STUB'
#!/bin/sh
# A curl stand-in. Honours -o (body goes to the file, the -w status stays on
# stdout) because the probe reads the token from a file and the status from
# stdout.
kind=manifest
out=""
next_is_out=0
for arg in "$@"; do
    if [ "$next_is_out" = 1 ]; then out=$arg; next_is_out=0; continue; fi
    case "$arg" in
        -o) next_is_out=1 ;;
        */token\?*) kind=token ;;
    esac
done

count_file="${STALL_DIR}/${kind}"
n=$(cat "$count_file" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$count_file"

case "$kind" in
    token)  stall=${STALL_TOKEN:-0} ;;
    *)      stall=${STALL_MANIFEST:-0} ;;
esac

emit_body() {
    if [ -n "$out" ]; then printf '%s' "$1" > "$out"; else printf '%s' "$1"; fi
}

if [ "$n" -le "$stall" ]; then
    # curl writes the -w output even when the transfer fails, then exits 28.
    emit_body ""
    [ "$kind" = manifest ] && printf '000'
    echo "curl: (28) Connection timed out after 60001 milliseconds" >&2
    exit 28
fi

case "$kind" in
    token)    emit_body '{"token":"stub-token"}' ;;
    manifest) emit_body ""; printf '200' ;;
esac
exit 0
STUB
chmod +x "$tmp/bin/curl"

# The probe reads the token out of the JSON with python3. Runners have it;
# this box may not, and the subject of this test is curl, not the parser.
if ! command -v python3 >/dev/null 2>&1; then
    cat > "$tmp/bin/python3" <<'STUB'
#!/bin/sh
# Stand-in for `python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])'`.
# Fails on an empty body exactly like json.load does, which is the behaviour
# the probe relies on when every token attempt has stalled.
body=$(cat)
[ -n "$body" ] || { echo "stub python3: empty body" >&2; exit 1; }
printf '%s\n' "$body" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | grep . || exit 1
STUB
    chmod +x "$tmp/bin/python3"
fi

run_probe() {
    rm -rf "$tmp/calls"
    mkdir -p "$tmp/calls"
    (
        cd "$repo_root"
        PATH="$tmp/bin:$PATH" \
        STALL_DIR="$tmp/calls" \
        STALL_TOKEN="$1" \
        STALL_MANIFEST="$2" \
            ./hack/list-missing-sources.sh
    )
}

calls() { cat "$tmp/calls/$1" 2>/dev/null || echo 0; }

fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. No stall at all: every package is published, so nothing is reported
#    missing. Establishes that the harness drives the real script correctly.
out=$(run_probe 0 0) || fail "the probe failed with a healthy registry"
[ -z "$out" ] || fail "expected no missing packages with a healthy registry, got: $out"
packages=$(calls manifest)
[ "$packages" -gt 0 ] || fail "the probe made no manifest requests"
echo "ok: healthy registry, $packages manifest probes, nothing reported missing"

# 2. The first manifest request stalls. The retry has to carry the probe
#    through it and still reach every package. Before the fix this exited 28
#    on the very first package.
out=$(run_probe 0 1) || fail "one stalled manifest request killed the probe; the retry never ran"
[ -z "$out" ] || fail "a retried manifest request was reported missing: $out"
retried=$(calls manifest)
[ "$retried" -eq $((packages + 1)) ] ||
    fail "expected $((packages + 1)) manifest requests after one stall, got $retried"
echo "ok: a stalled manifest request is retried, all $packages packages still probed"

# 3. The token request stalls. Same requirement: the probe retries rather
#    than dying on the first stall.
out=$(run_probe 1 0) || fail "one stalled token request killed the probe; the retry never ran"
[ -z "$out" ] || fail "expected no missing packages after a retried token request, got: $out"
[ "$(calls token)" -eq 2 ] || fail "expected 2 token requests after one stall, got $(calls token)"
echo "ok: a stalled token request is retried"

# 4. A registry that never answers must fail loudly, not report every package
#    as missing. Reporting missing would send the build to upstream hosts for
#    tarballs that are in fact cached.
if out=$(run_probe 0 99 2>"$tmp/err"); then
    fail "a registry that never answers was treated as success: $out"
fi
grep -q 'could not determine whether' "$tmp/err" ||
    fail "expected the probe's own error text, got: $(cat "$tmp/err")"
echo "ok: a registry that never answers fails loudly"

echo "PASS: hack/list-missing-sources.sh retries stalled connections"
