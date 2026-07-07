#!/bin/sh
# Fetch firmware + layers component data from sibling repos' published static
# sites into docs/static/components/. Must run AFTER gen-snapshot.sh (which
# wipes that directory) so the fetched files survive.
#
# Sources:
#   firmware.json <- https://kairos-io.github.io/hadron-firmware/data.json
#   layers.json   <- https://kairos-io.github.io/hadron-layers/releases.json
set -eu

ROOT="${HADRON_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
OUT="$ROOT/docs/static/components"

FIRMWARE_URL="${HADRON_FIRMWARE_URL:-https://kairos-io.github.io/hadron-firmware/data.json}"
LAYERS_URL="${HADRON_LAYERS_URL:-https://kairos-io.github.io/hadron-layers/releases.json}"

mkdir -p "$OUT"

fetch() {
  url="$1"; dest="$2"
  echo "Fetching $url -> $dest" >&2
  curl -fsSL --retry 3 --retry-delay 2 --max-time 60 "$url" -o "$dest.tmp"
  # Validate JSON before swapping in.
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$dest.tmp"
  elif command -v jq >/dev/null 2>&1; then
    jq empty <"$dest.tmp" >/dev/null
  fi
  mv "$dest.tmp" "$dest"
}

fetch "$FIRMWARE_URL" "$OUT/firmware.json"
fetch "$LAYERS_URL"   "$OUT/layers.json"

echo "OK: firmware + layers snapshots written to $OUT" >&2
