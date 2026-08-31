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
expected = '''FROM sources-downloader-base AS libkcapi-download
ARG LIBKCAPI_SOURCE_URLS="https://github.com/smuellerDD/libkcapi/archive/refs/tags/v1.5.0.tar.gz"
ARG LIBKCAPI_SOURCE_SHA256="f1d827738bda03065afd03315479b058f43493ab6e896821b947f391aa566ba0"
RUN set -eu; \\
    out=/sources/downloads/libkcapi.tar.gz; \\
    matched=0; \\
    for url in $LIBKCAPI_SOURCE_URLS; do \\
'''
if expected not in dockerfile:
    raise SystemExit('fork render did not generate the verified libkcapi download stage')
if 'FROM ghcr.io/kairos-io/hadron-sources/libkcapi:' in dockerfile:
    raise SystemExit('fork render still requires the libkcapi cache image')
PY

PATH="$tmp/bin:$PATH" PYTHONPATH="$tmp" HADRON_SOURCE_MODE=cache ./hack/render.sh >/dev/null
grep -q '^FROM ghcr.io/kairos-io/hadron-sources/libkcapi:1.5.0 AS libkcapi-download$' Dockerfile
