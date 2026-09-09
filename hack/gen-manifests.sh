#!/bin/sh
# Generate every component manifest the build and the PR report need, from one
# definition of which Dockerfile stages ship into which artifact.
#
# The stage lists used to be copied into the Makefile, into
# .github/actions/render-dockerfile/action.yml and into
# .github/workflows/PR_multiarch.yml, and the three copies had already diverged:
# the report one omitted full-image-pre-preset. That name is not a Dockerfile
# stage -- the pre-preset split was retired when preset-all moved into
# full-image-final -- so gen-components.sh matched nothing for it and the
# divergence happened to change no output. It is dropped here rather than
# copied a fourth time. The point of keeping one list is that the next
# divergence will not be harmless.
#
# Output names are what the consumers read:
#   container.<ext>
#   full-image-<fips>-<bootloader>.<ext>   (no-fips|fips x grub|systemd)
#
# The Dockerfile COPYs gen/components/container.json and
# gen/components/full-image-${FIPS}-${BOOTLOADER}.json, so --format flat
# --out-dir gen/components has to run before `docker build .`.
set -eu

FORMAT="flat"
OUT_DIR="gen/components"
QUIET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --format)  FORMAT="$2";  shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --quiet)   QUIET="1";    shift ;;
    -h|--help)
      echo "usage: gen-manifests.sh [--format json|md|flat|both] [--out-dir DIR] [--quiet]"
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT="${HADRON_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
GEN="$ROOT/hack/gen-components.sh"

mkdir -p "$OUT_DIR"

# The container image is stage2-merge and nothing else.
sh "$GEN" --shipped "stage2-merge" \
    --format "$FORMAT" --name container --out-dir "$OUT_DIR" >/dev/null

for fips in no-fips fips; do
    # The FIPS build ships the FIPS openssl, whose version is pinned under a
    # different ARG than the regular one.
    override=""
    [ "$fips" = "fips" ] && override="--override openssl=OPENSSL_FIPS_VERSION"
    for bootloader in grub systemd; do
        # shellcheck disable=SC2086 # $override is either empty or two words
        sh "$GEN" \
            --shipped "stage2-merge full-image-merge-base full-image-merge-${fips} full-image-pre-${bootloader} full-image-final" \
            $override \
            --format "$FORMAT" \
            --name "full-image-${fips}-${bootloader}" \
            --out-dir "$OUT_DIR" >/dev/null
    done
done

[ -n "$QUIET" ] || echo "generated component manifests: $(ls "$OUT_DIR" | wc -l) files in $OUT_DIR/"
