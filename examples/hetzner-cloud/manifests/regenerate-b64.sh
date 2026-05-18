#!/usr/bin/env bash
# Encode each cleartext manifest to single-line base64 and print it.
# Paste the output into the matching `content:` field in the cloud-config(s)
# listed in the header above each block.
#
# Leading file-explanation comments (the block of `#` lines at the top of
# each manifest, before the first YAML node) are STRIPPED before encoding.
# They exist to help humans browsing manifests/ — they don't need to be
# embedded in the cloud-config's encoded `content:` field, which only
# Kubernetes ever sees. Inline comments inside `valuesContent:` blocks are
# preserved (they're part of the chart values payload).
#
# Usage (from anywhere): bash examples/hetzner-cloud/manifests/regenerate-b64.sh
#
# Dependencies: bash, awk, base64 (all in POSIX coreutils on Linux/macOS).

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

emit() {
  local file="$1"; shift
  echo
  echo "=== ${file} ==="
  echo "# consumed by: $*"
  awk '!started && (/^#/ || /^[[:space:]]*$/) {next} {started=1; print}' "${DIR}/${file}" \
    | base64 | tr -d '\n'
  echo
}

emit hcloud-secret.yaml       hcm-only.yaml  hcm-traefik.yaml  hcm-cilium.yaml
emit hcloud-ccm-only.yaml     hcm-only.yaml
emit hcloud-ccm-traefik.yaml  hcm-traefik.yaml
emit hcloud-ccm-cilium.yaml   hcm-cilium.yaml
emit traefik-config.yaml      hcm-traefik.yaml
emit cilium.yaml              hcm-cilium.yaml
emit hcloud-csi.yaml          hcm-only.yaml  hcm-traefik.yaml  hcm-cilium.yaml
