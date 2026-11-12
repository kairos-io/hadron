#!/usr/bin/env bash
#
# Runs .github/scripts/delete-cache-tags.sh against a stub skopeo that acts
# like Quay: deleting a manifest by digest drops every tag pointing at it.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/delete-cache-tags.sh"
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

# The registry: one file per tag holding its manifest.
mkdir -p "${work}/tags"
put() { printf '%s' "$2" > "${work}/tags/$1"; }

cat > "${work}/skopeo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dir=${STUB_TAGS}
ref=${!#}
tag=${ref##*:}
case $1 in
    list-tags)
        python3 -c 'import json, os, sys; print(json.dumps({"Tags": sorted(os.listdir(sys.argv[1]))}))' "${dir}" ;;
    inspect)
        [ -f "${dir}/${tag}" ] || { echo "manifest unknown" >&2; exit 1; }
        cat "${dir}/${tag}" ;;
    delete)
        [ -f "${dir}/${tag}" ] || { echo "manifest unknown" >&2; exit 1; }
        manifest=$(cat "${dir}/${tag}")
        for f in "${dir}"/*; do
            [ "$(cat "${f}")" = "${manifest}" ] && rm -f "${f}"
        done ;;
esac
EOF
chmod +x "${work}/skopeo"

put stage0-amd64 'manifest-main-stage0'
put rsync-amd64 'manifest-main-rsync'
put pr-837-stage0-amd64 'manifest-main-stage0'
put pr-837-kernel-misc-default-amd64 'manifest-pr-kernel'
put pr-829-stage0-amd64 'manifest-main-stage0'
put pr-840-rsync-amd64 'manifest-pr-rsync'
put pr-840-rsync-arm64 'manifest-pr-rsync'

printf '%s\n' pr-837-stage0-amd64 pr-837-kernel-misc-default-amd64 pr-829-stage0-amd64 \
    pr-840-rsync-amd64 pr-840-rsync-arm64 pr-999-gone-amd64 \
    | STUB_TAGS="${work}/tags" SKOPEO="${work}/skopeo" "${SCRIPT}" quay.io/kairos/hadron-build-cache > "${work}/out"

failed=0
expect_present() { [ -f "${work}/tags/$1" ] || { echo "FAIL: $1 was deleted" >&2; failed=1; }; }
expect_absent() { [ ! -f "${work}/tags/$1" ] || { echo "FAIL: $1 was kept" >&2; failed=1; }; }

# main tags survive even though PR tags share their manifest
expect_present stage0-amd64
expect_present rsync-amd64
# PR tags that share main's manifest are kept for a later sweep
expect_present pr-837-stage0-amd64
expect_present pr-829-stage0-amd64
# PR-only manifests go, including two PR tags sharing one manifest
expect_absent pr-837-kernel-misc-default-amd64
expect_absent pr-840-rsync-amd64
expect_absent pr-840-rsync-arm64

if [ "${failed}" -ne 0 ]; then
    cat "${work}/out" >&2
    exit 1
fi
echo "delete-cache-tags: ok"
