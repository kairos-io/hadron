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

# Same repository layout the cache FROM lines in Dockerfile.tmpl use.
registry=${HADRON_SOURCES_REGISTRY:-ghcr.io/kairos-io/hadron-sources}
registry_host=${registry%%/*}
registry_path=${registry#*/}

if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl not found" >&2
    exit 1
fi

accept='application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'

pinned=$(mktemp)
trap 'rm -f "$pinned"' EXIT

python3 - <<'PY' > "$pinned"
import sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required to probe the source cache (pip install pyyaml)")
data = yaml.safe_load(open('sources.yaml')) or {}
for name, spec in sorted((data.get('packages') or {}).items()):
    version = spec.get('version')
    if version is None:
        sys.exit(f"sources.yaml entry {name!r} missing version")
    print(f'{name} {version}')
PY

# One anonymous pull token covering every package, rather than a token
# round-trip per package. Registry tokens are scoped, so every package the
# loop below reads has to be named here.
request_token() {
    query="service=${registry_host}"
    while read -r package _; do
        query="${query}&scope=repository:${registry_path}/${package}:pull"
    done < "$pinned"

    curl -fsS --max-time 60 "https://${registry_host}/token?${query}" |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])'
}

manifest_status() {
    curl -sS --max-time 60 --head -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: ${accept}" \
        "https://${registry_host}/v2/${registry_path}/$1/manifests/$2"
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
