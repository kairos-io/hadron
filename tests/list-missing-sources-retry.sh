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

# A curl that fails the way a stalled connection does, and that can answer a
# manifest request with a status other than 200:
#
#   STALL_TOKEN=N       the first N token calls exit 28
#   STALL_TOKEN_FROM=K  token calls from the Kth on exit 28
#   STALL_MANIFEST=N    the first N manifest calls exit 28
#   MANIFEST_401=N      the first N manifest calls answer 401
#   MISSING_NTH=N       the Nth manifest call answers 404, and the package it
#                       asked about is recorded in $STALL_DIR/missing
cat > "$tmp/bin/curl" <<'STUB'
#!/bin/sh
# A curl stand-in. Honours -o (body goes to the file, the -w status stays on
# stdout) because the probe reads the token from a file and the status from
# stdout.
kind=manifest
out=""
url=""
next_is_out=0
for arg in "$@"; do
    if [ "$next_is_out" = 1 ]; then out=$arg; next_is_out=0; continue; fi
    case "$arg" in
        -o) next_is_out=1 ;;
        */token\?*) kind=token; url=$arg ;;
        https://*/manifests/*) url=$arg ;;
    esac
done

count_file="${STALL_DIR}/${kind}"
n=$(cat "$count_file" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$count_file"

emit_body() {
    if [ -n "$out" ]; then printf '%s' "$1" > "$out"; else printf '%s' "$1"; fi
}

stalled() {
    [ "$n" -le "${1:-0}" ] && return 0
    [ -n "${2:-}" ] && [ "$n" -ge "$2" ] && return 0
    return 1
}

case "$kind" in
    token) stall_now=$(stalled "${STALL_TOKEN:-0}" "${STALL_TOKEN_FROM:-}" && echo yes) ;;
    *)     stall_now=$(stalled "${STALL_MANIFEST:-0}" "" && echo yes) ;;
esac

if [ "${stall_now:-}" = yes ]; then
    # curl writes the -w output even when the transfer fails, then exits 28.
    # It does not touch the -o file at all when the connection never opens,
    # which is why the probe must not read success out of that file's size.
    [ "$kind" = manifest ] && printf '000'
    echo "curl: (28) Connection timed out after 60001 milliseconds" >&2
    exit 28
fi

if [ "$kind" = token ]; then
    emit_body '{"token":"stub-token"}'
    exit 0
fi

# The package this manifest request is about: .../v2/<path>/<package>/manifests/<version>
package=${url%/manifests/*}
package=${package##*/}

if [ "$n" -le "${MANIFEST_401:-0}" ]; then
    emit_body ""; printf '401'; exit 0
fi

if [ "$n" = "${MISSING_NTH:-0}" ]; then
    printf '%s' "$package" > "${STALL_DIR}/missing"
    emit_body ""; printf '404'; exit 0
fi

emit_body ""; printf '200'
exit 0
STUB
chmod +x "$tmp/bin/curl"

# The retry sleeps between attempts. The subject here is which attempts happen,
# not how long the probe waits, and the real sleeps add ~40s to the run.
cat > "$tmp/bin/sleep" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$tmp/bin/sleep"

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

# run_probe <stall_token> <stall_manifest> [extra VAR=VALUE ...]
run_probe() {
    stall_token=$1
    stall_manifest=$2
    shift 2
    rm -rf "$tmp/calls"
    mkdir -p "$tmp/calls"
    (
        cd "$repo_root"
        env \
            PATH="$tmp/bin:$PATH" \
            STALL_DIR="$tmp/calls" \
            STALL_TOKEN="$stall_token" \
            STALL_MANIFEST="$stall_manifest" \
            "$@" \
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

# 5. A 404 is the one status that means "not published", and it is the whole
#    point of the script. Retrying it would be wrong too: 404 is an answer,
#    not a transport failure. The stub records which package it answered 404
#    for, so this asserts on the registry's answer rather than on a package
#    name copied out of the Dockerfile.
out=$(run_probe 0 0 MISSING_NTH=1) || fail "the probe failed when one package was unpublished"
missing=$(cat "$tmp/calls/missing" 2>/dev/null || echo "")
[ -n "$missing" ] || fail "the stub never answered 404; MISSING_NTH did not take effect"
[ "$out" = "$missing" ] ||
    fail "expected exactly '$missing' reported missing, got: ${out:-<nothing>}"
[ "$(calls manifest)" -eq "$packages" ] ||
    fail "a 404 was retried: expected $packages manifest requests, got $(calls manifest)"
echo "ok: a 404 is reported missing exactly once and is not retried"

# 6. A 401 mid-run asks for a fresh token. If that refresh fails, the probe
#    has to say so. $body is shared by every request_token call, and curl -o
#    leaves the file untouched when the connection never opens, so deciding
#    success from the file's size read the first call's still-present token as
#    a fresh one and carried on with an expired token, silently.
out=$(run_probe 0 0 STALL_TOKEN_FROM=2 MANIFEST_401=1 2>"$tmp/err") ||
    fail "a failed token refresh killed the probe: $(cat "$tmp/err")"
[ "$(calls token)" -eq 4 ] ||
    fail "expected 1 token request plus 3 refresh attempts, got $(calls token)"
grep -q 'could not get a pull token' "$tmp/err" ||
    fail "a token refresh whose every attempt stalled was not reported: $(cat "$tmp/err")"
echo "ok: a token refresh that stalls on every attempt is reported, not passed off as fresh"

echo "PASS: hack/list-missing-sources.sh retries stalled connections"
