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

# Fork pull requests cannot publish missing source-cache images. In upstream
# mode, replace each cache image with a downloader stage that uses the same
# pinned URL and checksum from sources.yaml. Regular builds keep using cache
# images and do not contact upstream mirrors.
case "${HADRON_SOURCE_MODE:-cache}" in
    cache)
        ;;
    upstream)
        python3 - <<'PY'
from pathlib import Path
import re
import yaml

path = Path('Dockerfile')
dockerfile = path.read_text()
packages = (yaml.safe_load(open('sources.yaml')) or {}).get('packages') or {}
pattern = re.compile(
    r'^FROM ghcr\.io/kairos-io/hadron-sources/'
    # The libnetfilter_* packages carry underscores, in the package name
    # and in the stage name both.
    r'(?P<pkg>[a-z0-9_-]+):[^ ]+ AS (?P<stage>[a-z0-9_-]+)$',
    re.MULTILINE,
)

def downloader(match):
    pkg = match.group('pkg')
    stage = match.group('stage')
    spec = packages.get(pkg)
    if spec is None:
        raise SystemExit(f'package {pkg!r} missing from sources.yaml')
    for field in ('version', 'sha256', 'filename', 'urls'):
        if not spec.get(field):
            raise SystemExit(f'package {pkg!r} missing field {field!r}')
    if not isinstance(spec['urls'], list) or not spec['urls']:
        raise SystemExit(f'package {pkg!r}: urls must be a non-empty list')

    version = str(spec['version'])
    urls = [url.replace('${version}', version) for url in spec['urls']]
    if any(any(char.isspace() for char in url) for url in urls):
        raise SystemExit(f'package {pkg!r} URL contains whitespace')
    variable = pkg.upper().replace('-', '_')
    url_list = ' '.join(urls)
    filename = spec['filename']
    sha256 = spec['sha256']
    return f'''FROM sources-downloader-base AS {stage}
ARG {variable}_SOURCE_URLS="{url_list}"
ARG {variable}_SOURCE_SHA256="{sha256}"
RUN set -eu; \\
    out=/sources/downloads/{filename}; \\
    matched=0; \\
    for attempt in 1 2 3; do \\
        for url in ${variable}_SOURCE_URLS; do \\
            rm -f "$out"; \\
            if wget -q --timeout=30 --tries=1 "$url" -O "$out"; then \\
                actual=$(sha256sum "$out" | awk '{{print $1}}'); \\
                if [ "$actual" = "${variable}_SOURCE_SHA256" ]; then matched=1; break; fi; \\
            fi; \\
        done; \\
        test "$matched" -eq 0 || break; \\
        sleep $((attempt * 5)); \\
    done; \\
    test "$matched" -eq 1 || {{ echo "No URL served the expected bytes for {pkg}-{version}"; exit 1; }}
'''

dockerfile, replaced = pattern.subn(downloader, dockerfile)
if replaced == 0:
    raise SystemExit('upstream mode found no source-cache stages to replace')
path.write_text(dockerfile)
print(f'rendered {replaced} verified upstream source stages')
PY
        ;;
    *)
        echo "error: HADRON_SOURCE_MODE must be 'cache' or 'upstream'" >&2
        exit 1
        ;;
esac

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
