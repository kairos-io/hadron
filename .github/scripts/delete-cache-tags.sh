#!/usr/bin/env bash
#
# delete-cache-tags.sh <repository>
#
# Deletes the cache tags read from stdin (one per line) from <repository>,
# for example quay.io/kairos/hadron-build-cache, but never a tag whose
# manifest another tag still uses.
#
# `skopeo delete` resolves the tag to its manifest digest and deletes the
# manifest. Quay then drops every tag that points at that manifest. A PR
# build that hits the cache all the way through exports a manifest that is
# byte for byte the one main exported, so deleting pr-837-stage0-amd64 also
# deleted stage0-amd64, and the next main run rebuilt the toolchain and
# re-ran `apk update` in alpine-base with whatever Alpine served that day.
# A tag that shares its manifest with a tag we keep is left alone; the
# weekly sweep tries again once main has moved on.
#
# SKOPEO overrides the skopeo binary (the test uses a stub).

set -euo pipefail

repo=$1
skopeo=${SKOPEO:-skopeo}

doomed=()
while IFS= read -r tag; do
    [ -n "${tag}" ] && doomed+=("${tag}")
done
if [ "${#doomed[@]}" -eq 0 ]; then
    echo "No cache tags to delete."
    exit 0
fi

digest() {
    "${skopeo}" inspect --raw "docker://${repo}:$1" | sha256sum | cut -d' ' -f1
}

declare -A deleting=()
for tag in "${doomed[@]}"; do
    deleting[${tag}]=1
done

# Digest of every tag that stays, so a shared manifest is never deleted.
declare -A kept=()
unreadable=0
while IFS= read -r tag; do
    [ -n "${tag}" ] || continue
    [ -z "${deleting[${tag}]:-}" ] || continue
    if d=$(digest "${tag}"); then
        kept[${d}]=${tag}
    else
        echo "WARN: could not read ${tag}; its manifest may be shared with a tag to delete"
        unreadable=1
    fi
done < <("${skopeo}" list-tags "docker://${repo}" \
    | python3 -c "import sys, json; print('\n'.join(json.load(sys.stdin).get('Tags', [])))")

# A tag we could not read might share a manifest with a tag to delete, so
# delete nothing; the next run tries again.
if [ "${unreadable}" -ne 0 ]; then
    echo "Refusing to delete anything: a kept tag could not be read." >&2
    exit 1
fi

for tag in "${doomed[@]}"; do
    if ! d=$(digest "${tag}"); then
        echo "skip ${tag}: already gone"
        continue
    fi
    if [ -n "${kept[${d}]:-}" ]; then
        echo "keep ${tag}: same manifest as ${kept[${d}]}, deleting it would delete that tag too"
        continue
    fi
    echo "==> deleting ${repo}:${tag}"
    "${skopeo}" delete "docker://${repo}:${tag}" || echo "WARN: could not delete ${tag} (continuing)"
done
