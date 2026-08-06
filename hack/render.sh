#!/bin/sh
# Render Dockerfile from Dockerfile.tmpl by substituting every
# ${<version_arg>} placeholder with the corresponding package version
# from sources.yaml.
#
# Uses envsubst (from gettext) so only variables in the format string
# are substituted; unrelated ${...} shell parameter expansions and
# Docker ARGs inside RUN commands are left untouched.
#
# Exits non-zero if any expected version placeholder remains
# unresolved in the output (safety net against a missing version_arg
# in sources.yaml).

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

if [ ! -f sources.yaml ] || [ ! -f Dockerfile.tmpl ]; then
    echo "error: sources.yaml or Dockerfile.tmpl not found in $repo_root" >&2
    exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
    echo "error: envsubst not found (install the 'gettext' package)" >&2
    exit 1
fi

envfile=$(mktemp)
trap 'rm -f "$envfile"' EXIT

python3 - <<'PY' > "$envfile"
import sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required to render Dockerfile (pip install pyyaml)")
data = yaml.safe_load(open('sources.yaml')) or {}
for name, spec in (data.get('packages') or {}).items():
    var = spec.get('version_arg')
    version = spec.get('version')
    if not var or version is None:
        sys.exit(f"sources.yaml entry {name!r} missing version_arg or version")
    print(f'{var}={version}')
PY

# Load the env vars, build the shell-format list for envsubst
set -a
# shellcheck disable=SC1090
. "$envfile"
set +a

format=$(cut -d= -f1 <"$envfile" | sed 's/^/$/' | tr '\n' ' ')

envsubst "$format" <Dockerfile.tmpl >Dockerfile

# Safety: any unresolved ${..._VERSION} placeholder means a missing
# version_arg in sources.yaml (or a typo in Dockerfile.tmpl).
if remaining=$(grep -oE '\$\{[A-Z0-9_]+_VERSION\}' Dockerfile | sort -u); then
    if [ -n "$remaining" ]; then
        # Filter out placeholders whose ARG name is NOT declared in sources.yaml.
        # Those are legitimately not templated (e.g., GNU-mirror packages we
        # have not onboarded yet). Only alert if we see a placeholder that
        # SHOULD have been substituted but was not.
        declared=$(cut -d= -f1 <"$envfile" | tr '\n' '|' | sed 's/|$//')
        stragglers=$(echo "$remaining" | grep -E "\$\{($declared)\}" || true)
        if [ -n "$stragglers" ]; then
            echo "error: expected placeholders were not substituted:" >&2
            echo "$stragglers" >&2
            exit 1
        fi
    fi
fi

echo "rendered Dockerfile ($(wc -l <Dockerfile) lines) from Dockerfile.tmpl"

# --- Component manifests (per-variant) ----------------------------------------
# The final container / full-image stages COPY one of these into
# /usr/lib/hadron/components.json. Generating them here (on the host, once
# per render) avoids adding a container stage with its own toolchain just to
# produce a JSON file.
#
# Variants:
#   container.json                         no variants (always the same)
#   full-image-<FIPS>-<BOOTLOADER>.json    2 x 2 = 4 files
mkdir -p gen/components
sh hack/gen-components.sh --shipped "stage2-merge" \
    --format flat --name container --out-dir gen/components >/dev/null

for fips in no-fips fips; do
    override=""
    [ "$fips" = "fips" ] && override="--override openssl=OPENSSL_FIPS_VERSION"
    for bootloader in grub systemd; do
        sh hack/gen-components.sh \
            --shipped "stage2-merge full-image-merge-base full-image-merge-${fips} full-image-pre-${bootloader} full-image-pre-preset full-image-final" \
            ${override} \
            --format flat \
            --name "full-image-${fips}-${bootloader}" \
            --out-dir gen/components >/dev/null
    done
done

echo "generated component manifests: $(ls gen/components | wc -l) files in gen/components/"
