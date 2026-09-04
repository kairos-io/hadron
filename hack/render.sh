#!/bin/sh
# Fork-PR helper: rewrite `FROM ghcr.io/kairos-io/hadron-sources/...`
# lines in the Dockerfile in place, replacing them with checksum-verifying
# upstream download stages. Only fork pull requests need this because they
# cannot publish to the source cache, so any version they bump has no
# published tag to pull. Trusted builds skip this script entirely and
# `docker build .` off the committed Dockerfile.
#
# HADRON_UPSTREAM_PACKAGES restricts which packages are rewritten:
#
#   unset            every package is fetched from upstream. This is the
#                    offline / forked-distro rebuild path documented in
#                    sources.yaml: the Dockerfile ARG defaults plus
#                    sources.yaml alone are enough to rebuild.
#   set to a list    only the named packages are fetched from upstream and
#                    every other package keeps its cache image. Set to the
#                    empty string to keep all of them cached.
#
# Fork PR workflows call this with the list form. The source cache is
# public, so a fork can pull every already-published tag and only has to
# reach upstream for the versions the PR itself bumps. Fetching all of
# them instead makes the build depend on ~100 upstream hosts staying
# reachable, and any single one of them refusing a runner fails the whole
# build.
#
# Reads the pinned version for each package from the matching
# `ARG <version_arg>=<version>` default in the committed Dockerfile
# (single source of truth); sources.yaml supplies the urls / sha256 /
# filename keyed by version_arg.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

if [ ! -f Dockerfile ] || [ ! -f sources.yaml ]; then
    echo "error: Dockerfile or sources.yaml not found in $repo_root" >&2
    exit 1
fi

# Distinguish "unset" (rewrite every FROM) from "set but empty" (rewrite
# nothing); both are meaningful and only the shell can tell them apart.
if [ "${HADRON_UPSTREAM_PACKAGES+set}" = set ]; then
    HADRON_UPSTREAM_FILTER=1
else
    HADRON_UPSTREAM_FILTER=0
fi
export HADRON_UPSTREAM_FILTER

python3 - <<'PY'
from pathlib import Path
import os
import re
import yaml

path = Path('Dockerfile')
dockerfile = path.read_text()
packages = (yaml.safe_load(open('sources.yaml')) or {}).get('packages') or {}

# Parse the ARG defaults in the committed Dockerfile so we can resolve
# the pinned version of each package by its version_arg. Same rule the
# populate-sources workflow uses.
arg_re = re.compile(r'^ARG ([A-Z0-9_]+)=(.*)$', re.MULTILINE)
arg_defaults = {}
for name, value in arg_re.findall(dockerfile):
    value = value.strip()
    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
    value = value.split()[0] if value else ''
    arg_defaults[name] = value

pattern = re.compile(
    r'^FROM ghcr\.io/kairos-io/hadron-sources/'
    # The libnetfilter_* packages carry underscores, in the package name
    # and in the stage name both.
    r'(?P<pkg>[a-z0-9_-]+):[^ ]+ AS (?P<stage>[a-z0-9_-]+)$',
    re.MULTILINE,
)

# See the HADRON_UPSTREAM_PACKAGES contract above.
restricted = os.environ.get('HADRON_UPSTREAM_FILTER') == '1'
selected = set(os.environ.get('HADRON_UPSTREAM_PACKAGES', '').split())
if restricted:
    unknown = sorted(selected - set(packages))
    if unknown:
        raise SystemExit(
            'HADRON_UPSTREAM_PACKAGES names packages missing from '
            f'sources.yaml: {" ".join(unknown)}'
        )
replaced_packages = set()

def downloader(match):
    pkg = match.group('pkg')
    stage = match.group('stage')
    if restricted and pkg not in selected:
        # Already published, and the cache is public: keep pulling it.
        return match.group(0)
    replaced_packages.add(pkg)
    spec = packages.get(pkg)
    if spec is None:
        raise SystemExit(f'package {pkg!r} missing from sources.yaml')
    for field in ('version_arg', 'sha256', 'filename', 'urls'):
        if not spec.get(field):
            raise SystemExit(f'package {pkg!r} missing field {field!r}')
    if not isinstance(spec['urls'], list) or not spec['urls']:
        raise SystemExit(f'package {pkg!r}: urls must be a non-empty list')

    version_arg = spec['version_arg']
    version = arg_defaults.get(version_arg, '')
    if not version:
        raise SystemExit(
            f'package {pkg!r}: no ARG {version_arg}= default in Dockerfile'
        )
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

dockerfile, matched = pattern.subn(downloader, dockerfile)
if matched == 0:
    raise SystemExit('upstream mode found no source-cache stages at all')
if restricted:
    # A selected package that never matched means sources.yaml and the
    # Dockerfile disagree, so the build would silently keep the stale
    # cache tag it cannot pull.
    unmatched = sorted(selected - replaced_packages)
    if unmatched:
        raise SystemExit(
            'no source-cache stage in Dockerfile for selected '
            f'packages: {" ".join(unmatched)}'
        )
path.write_text(dockerfile)
print(
    f'rewrote {len(replaced_packages)} verified upstream source stages, '
    f'{matched - len(replaced_packages)} kept on the source cache'
)
PY
