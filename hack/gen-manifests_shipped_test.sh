#!/bin/sh
# Runs hack/gen-manifests.sh over the real Dockerfile and checks that each
# bootloader manifest lists what its image ships. full-image-pre-grub takes
# grub, shim, gawk and fts (musl-fts) in one `COPY --from=dracut-final`, and
# the filter in gen-components.sh only reads the direct COPY lines of the
# stages it is given, so the grub manifests only see them when dracut-final is
# in their list.
#
# No network, no docker.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

sh "$ROOT/hack/gen-manifests.sh" --format flat --out-dir "$OUT" --quiet 2>/dev/null

for fips in no-fips fips; do
  grub="$OUT/full-image-${fips}-grub.json"
  systemd="$OUT/full-image-${fips}-systemd.json"
  [ -f "$grub" ]    || fail "$(basename "$grub") not generated"
  [ -f "$systemd" ] || fail "$(basename "$systemd") not generated"

  for c in grub shim gawk musl-fts dracut; do
    grep -q "\"$c\":" "$grub" || fail "$(basename "$grub") does not list $c"
  done
  for c in grub shim dracut; do
    grep -q "\"$c\":" "$systemd" && fail "$(basename "$systemd") lists $c, which only the grub image ships"
  done
done

for c in grub shim dracut; do
  grep -q "\"$c\":" "$OUT/container.json" && fail "container.json lists $c, which only the grub image ships"
done

echo "PASS: gen-manifests shipped tests"
