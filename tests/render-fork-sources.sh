#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; rm -f "$repo_root/Dockerfile"' EXIT

mkdir -p "$tmp/bin"
cat > "$tmp/yaml.py" <<'PY'
def safe_load(stream):
    packages = {}
    current = None
    list_key = None
    for raw in stream:
        line = raw.rstrip()
        if not line or line.lstrip().startswith('#') or line == 'packages:':
            continue
        indent = len(line) - len(line.lstrip())
        text = line.strip()
        if indent == 2 and text.endswith(':'):
            current = text[:-1]
            packages[current] = {}
            list_key = None
        elif indent == 4 and text.endswith(':'):
            list_key = text[:-1]
            packages[current][list_key] = []
        elif indent == 4:
            key, value = text.split(':', 1)
            packages[current][key] = value.strip().strip('"')
            list_key = None
        elif indent == 6 and text.startswith('- '):
            packages[current][list_key].append(text[2:])
    return {'packages': packages}
PY
cat > "$tmp/bin/envsubst" <<'PY'
#!/usr/bin/env python3
import os
import re
import sys

variables = set(re.findall(r'\$([A-Za-z_][A-Za-z0-9_]*)', sys.argv[1]))
source = sys.stdin.read()
for variable in variables:
    source = source.replace('${' + variable + '}', os.environ.get(variable, ''))
sys.stdout.write(source)
PY
chmod +x "$tmp/bin/envsubst"

cd "$repo_root"
libkcapi_version=$(PYTHONPATH="$tmp" python3 -c "import yaml; print(yaml.safe_load(open('sources.yaml'))['packages']['libkcapi']['version'])")

# render <mode> [package-list]
# Omitting the list leaves HADRON_UPSTREAM_PACKAGES unset, which is a
# different instruction to render.sh than passing an empty list.
render() {
    if [ "$#" -ge 2 ]; then
        PATH="$tmp/bin:$PATH" PYTHONPATH="$tmp" \
            HADRON_SOURCE_MODE="$1" HADRON_UPSTREAM_PACKAGES="$2" \
            ./hack/render.sh >/dev/null
    else
        PATH="$tmp/bin:$PATH" PYTHONPATH="$tmp" \
            HADRON_SOURCE_MODE="$1" ./hack/render.sh >/dev/null
    fi
}

# --- Whole-file upstream mode -------------------------------------------------
# The offline/forked-distro rebuild path: sources.yaml alone is enough, so
# nothing may be left pointing at the cache.
render upstream

PYTHONPATH="$tmp" python3 - <<'PY'
from pathlib import Path
import yaml

dockerfile = Path('Dockerfile').read_text()
libkcapi = yaml.safe_load(open('sources.yaml'))['packages']['libkcapi']
version = str(libkcapi['version'])
url = libkcapi['urls'][0].replace('${version}', version)
declared = set()
for line in dockerfile.splitlines():
    if not line.startswith('FROM '):
        continue
    parts = line.split()
    source = parts[1]
    if source.endswith('-base') and source not in declared:
        raise SystemExit(f'fork render references stage {source!r} before it is declared')
    if len(parts) >= 4 and parts[-2] == 'AS':
        declared.add(parts[-1])

expected = f'''FROM sources-downloader-base AS libkcapi-download
ARG LIBKCAPI_SOURCE_URLS="{url}"
ARG LIBKCAPI_SOURCE_SHA256="{libkcapi['sha256']}"
RUN set -eu; \\
    out=/sources/downloads/libkcapi.tar.gz; \\
    matched=0; \\
    for attempt in 1 2 3; do \\
        for url in $LIBKCAPI_SOURCE_URLS; do \\
'''
if expected not in dockerfile:
    raise SystemExit('fork render did not generate the verified libkcapi download stage')

# Every cache stage has to be gone, not merely most of them. Package and
# stage names are not all plain lowercase-and-dashes (libnetfilter_conntrack
# and friends carry underscores), and a name the rewrite does not recognise
# leaves behind a cache tag an offline rebuild cannot pull.
leftover = sorted(
    line for line in dockerfile.splitlines()
    if line.startswith('FROM ghcr.io/kairos-io/hadron-sources/')
)
if leftover:
    raise SystemExit(
        'upstream mode left %d source-cache stage(s) in place:\n  %s'
        % (len(leftover), '\n  '.join(leftover))
    )

# A single unreachable host must not fail the build on the first miss.
if 'test "$matched" -eq 0 || break' not in dockerfile:
    raise SystemExit('fork render download stages do not retry a failed round')
if 'sleep $((attempt * 5))' not in dockerfile:
    raise SystemExit('fork render download stages retry without backoff')

# Some upstreams time out or refuse CI runners outright. A package served
# only from one of those hosts fails the whole fork build, so require a
# second URL for every one of them. The checksum test still gates the bytes.
unreliable = ('musl.libc.org', 'zlib.net')
for line in dockerfile.splitlines():
    if not line.startswith('ARG ') or '_SOURCE_URLS=' not in line:
        continue
    name, _, value = line[len('ARG '):].partition('=')
    urls = value.strip().strip('"').split()
    if len(urls) > 1:
        continue
    for host in unreliable:
        if host in urls[0]:
            raise SystemExit(
                f'{name} lists {host} only; add a fallback mirror in sources.yaml'
            )
PY

# --- Restricted upstream mode -------------------------------------------------
# What a fork pull request actually renders. Only the packages whose cache tag
# does not exist yet come from upstream; the cache is public, so every other
# package is pulled from it and the build does not depend on that upstream
# host answering at all.
render upstream libkcapi

python3 - <<'PY'
from pathlib import Path

dockerfile = Path('Dockerfile').read_text()

if 'FROM sources-downloader-base AS libkcapi-download\n' not in dockerfile:
    raise SystemExit('restricted render did not fetch the selected package from upstream')
if 'FROM ghcr.io/kairos-io/hadron-sources/libkcapi:' in dockerfile:
    raise SystemExit('restricted render still requires the libkcapi cache image')

# Everything not selected keeps its cache image.
if 'FROM ghcr.io/kairos-io/hadron-sources/zlib:1.3.2 AS zlib-download' not in dockerfile:
    raise SystemExit('restricted render dropped the cache image of an unselected package')

upstream = [
    line for line in dockerfile.splitlines()
    if line.startswith('ARG ') and '_SOURCE_URLS=' in line
]
if len(upstream) != 1:
    raise SystemExit(
        'restricted render produced %d upstream download stages, expected 1: %s'
        % (len(upstream), upstream)
    )
PY

# An empty list is a valid instruction and means every source is cached
# already, which is the common case for a fork pull request that bumps no
# version at all.
render upstream ''
if grep -q '^FROM sources-downloader-base AS libkcapi-download$' Dockerfile; then
    echo 'empty package list still fetched a package from upstream' >&2
    exit 1
fi
grep -q "^FROM ghcr.io/kairos-io/hadron-sources/libkcapi:$libkcapi_version AS libkcapi-download$" Dockerfile

# A name that is not in sources.yaml is a typo, not a package to skip.
if render upstream 'libkcapi no-such-package' 2>/dev/null; then
    echo 'restricted render accepted a package missing from sources.yaml' >&2
    exit 1
fi

# --- Cache mode ---------------------------------------------------------------
render cache
grep -q "^FROM ghcr.io/kairos-io/hadron-sources/libkcapi:$libkcapi_version AS libkcapi-download$" Dockerfile
