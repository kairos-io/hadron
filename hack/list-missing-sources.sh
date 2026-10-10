#!/bin/sh
# Print the name of every package in sources.yaml whose pinned version has
# no published source-cache image, one per line.
#
# The source cache is public, so this probe needs no credentials and works
# the same from a fork pull request as it does from the base repository.
# Fork pull requests use the result to decide the small set of packages they
# have to fetch from upstream (the versions the pull request itself bumps);
# everything else is already published and is pulled from the cache.
#
# Only a 404 counts as missing. A rate limit or a registry error is retried
# and then reported as an error, because treating it as missing would send
# the build back to an upstream host for a tarball that is in fact cached.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

# The cache repository is the `ARG SOURCES_REPO` default in the committed
# Dockerfile, so this probe and the cache FROM lines cannot drift apart.
# HADRON_SOURCES_REGISTRY overrides it to probe a mirror instead.
registry=${HADRON_SOURCES_REGISTRY:-$(awk -F= '/^ARG SOURCES_REPO=/ {print $2; exit}' Dockerfile)}
if [ -z "$registry" ]; then
    echo "error: no ARG SOURCES_REPO= default in Dockerfile" >&2
    exit 1
fi
registry_host=${registry%%/*}
registry_path=${registry#*/}

if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl not found" >&2
    exit 1
fi

accept='application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'

pinned=$(mktemp)
raw=$(mktemp)
body=$(mktemp)
trap 'rm -f "$pinned" "$raw" "$body"' EXIT

# The pinned version for each package is the default of its
# `ARG <version_arg>=<version>` in the committed Dockerfile
# (single source of truth); sources.yaml only names the version_arg.
# awk writes to $raw (not a pipeline) so an `exit 1` on a missing ARG
# actually fails the script under POSIX sh (no pipefail).
awk '
    /^ARG [A-Z0-9_]+=/ {
        line = substr($0, 5)
        eq = index(line, "=")
        name = substr(line, 1, eq - 1)
        val = substr(line, eq + 1)
        gsub(/^"|"$/, "", val)
        sub(/[ \t].*$/, "", val)
        args[name] = val
    }
    END {
        while ((getline yl < "sources.yaml") > 0) {
            if (match(yl, /^  [a-z0-9._-]+:$/)) {
                pkg = substr(yl, 3, RLENGTH - 3)
            } else if (match(yl, /^    version_arg: [A-Z0-9_]+$/)) {
                sub(/^    version_arg: /, "", yl)
                arg = yl
                if (!(arg in args)) {
                    print "error: package " pkg " (version_arg " arg ") has no ARG default in Dockerfile" > "/dev/stderr"
                    exit 1
                }
                print pkg " " args[arg]
            }
        }
    }
' Dockerfile > "$raw"
sort "$raw" > "$pinned"

# One anonymous pull token covering every package, rather than a token
# round-trip per package. Registry tokens are scoped, so every package the
# loop below reads has to be named here.
# This is one URL that names all 109 packages as scopes, so it is the
# largest and slowest request the probe makes, and the one most likely to
# stall. Retry it like the manifest probe below, because a stalled token
# reached python3 as an empty body and failed the script with a traceback
# rather than a second attempt.
request_token() {
    query="service=${registry_host}"
    while read -r scope_package _; do
        query="${query}&scope=repository:${registry_path}/${scope_package}:pull"
    done < "$pinned"

    token_attempt=1
    while [ "$token_attempt" -le 3 ]; do
        # Empty the body first. curl -o leaves the file's prior contents fully
        # intact when the connection never opens, and can leave a partial body
        # when it times out mid-transfer, so a failed attempt must not be able
        # to hand old or truncated bytes to the check below.
        : > "$body"
        if curl -fsS --max-time 60 -o "$body" \
            "https://${registry_host}/token?${query}"; then
            break
        fi
        sleep $((token_attempt * 3))
        token_attempt=$((token_attempt + 1))
    done

    # Decide from the loop counter, not from the file: token_attempt only gets
    # past 3 when no attempt broke out of the loop. $body is shared by every
    # request_token call, so on the 401 refresh path a file-size check reads
    # the first call's still-present token as success and prints an expired
    # token instead of reporting the failure.
    if [ "$token_attempt" -gt 3 ] || [ ! -s "$body" ]; then
        echo "error: could not get a pull token from ${registry_host}" \
            "after 3 attempts" >&2
        return 1
    fi

    python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])' < "$body"
}

# curl writes the -w status even when the transfer itself fails, and then
# exits non-zero: 28 on a timeout, 7 on a refused connection. Under `set -eu`
# that exit status propagates out of the `status=$(manifest_status ...)` the
# loop below assigns from and kills the script on the first stalled
# connection, so the retry never reaches a second attempt and the error text
# further down never prints. Those transport failures are exactly what the
# retry is for, so report the `000` curl already wrote and let the loop decide.
manifest_status() {
    curl -sS --max-time 60 --head -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: ${accept}" \
        "https://${registry_host}/v2/${registry_path}/$1/manifests/$2" || true
}

token=$(request_token)

while read -r package version; do
    status=""
    attempt=1
    while [ "$attempt" -le 3 ]; do
        status=$(manifest_status "$package" "$version")
        case "$status" in
            200 | 404) break ;;
            # The token outlives a short probe but not necessarily a slow
            # one, so take 401 as "expired" and ask for a fresh one.
            401) token=$(request_token) || true ;;
        esac
        sleep $((attempt * 3))
        attempt=$((attempt + 1))
    done

    case "$status" in
        200) ;;
        404) echo "$package" ;;
        *)
            echo "error: could not determine whether ${package}:${version} is" \
                "published (last HTTP status: ${status:-none})" >&2
            exit 1
            ;;
    esac
done < "$pinned"
