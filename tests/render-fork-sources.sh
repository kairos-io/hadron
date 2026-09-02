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
PATH="$tmp/bin:$PATH" PYTHONPATH="$tmp" HADRON_SOURCE_MODE=upstream ./hack/render.sh >/dev/null

python3 - <<'PY'
from pathlib import Path

dockerfile = Path('Dockerfile').read_text()
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

expected = '''FROM sources-downloader-base AS libkcapi-download
ARG LIBKCAPI_SOURCE_URLS="https://github.com/smuellerDD/libkcapi/archive/refs/tags/v1.5.0.tar.gz"
ARG LIBKCAPI_SOURCE_SHA256="f1d827738bda03065afd03315479b058f43493ab6e896821b947f391aa566ba0"
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

PATH="$tmp/bin:$PATH" PYTHONPATH="$tmp" HADRON_SOURCE_MODE=cache ./hack/render.sh >/dev/null
grep -q '^FROM ghcr.io/kairos-io/hadron-sources/libkcapi:1.5.0 AS libkcapi-download$' Dockerfile
