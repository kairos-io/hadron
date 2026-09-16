#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
# Keep the snapshot outside $tmp so the EXIT trap can restore Dockerfile
# even after $tmp is gone.
snapshot=$(mktemp)
cp "$repo_root/Dockerfile" "$snapshot"
# Restore the committed Dockerfile on any exit, including Ctrl-C, a dropped
# terminal and a cancelled CI job. This is `#!/bin/sh` (dash on the runners),
# and dash leaves an untrapped signal at SIG_DFL: the process is killed and the
# EXIT trap never runs. Without INT/TERM/HUP the working tree keeps the rendered
# downloader stages, and Dockerfile is tracked now, so a following `git commit
# -a` would land them.
cleanup() { cp "$snapshot" "$repo_root/Dockerfile"; rm -rf "$tmp" "$snapshot"; }
trap cleanup EXIT
trap 'cleanup; trap - INT; kill -INT $$' INT
trap 'cleanup; trap - TERM; kill -TERM $$' TERM
trap 'cleanup; trap - HUP; kill -HUP $$' HUP

mkdir -p "$tmp/bin"
# hack/render.sh needs a `yaml` module. On a runner without PyYAML installed,
# fall back to a minimal loader that understands just the shape of sources.yaml.
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

cd "$repo_root"

# render [package-list]
# Restores the committed Dockerfile first so the test is idempotent across
# invocations. Omitting the list leaves HADRON_UPSTREAM_PACKAGES unset,
# which is a different instruction to render.sh than passing an empty list.
render() {
    cp "$snapshot" Dockerfile
    if [ "$#" -ge 1 ]; then
        PYTHONPATH="$tmp" HADRON_UPSTREAM_PACKAGES="$1" \
            ./hack/render.sh >/dev/null
    else
        PYTHONPATH="$tmp" ./hack/render.sh >/dev/null
    fi
}

# --- Whole-file upstream mode -------------------------------------------------
# The offline/forked-distro rebuild path: sources.yaml + the Dockerfile ARG
# defaults alone are enough, so nothing may be left pointing at the cache.
render

PYTHONPATH="$tmp" python3 - <<'PY'
from pathlib import Path
import re, yaml

dockerfile = Path('Dockerfile').read_text()
libkcapi = yaml.safe_load(open('sources.yaml'))['packages']['libkcapi']
arg_re = re.compile(r'^ARG LIBKCAPI_VERSION=(.*)$', re.MULTILINE)
match = arg_re.search(dockerfile)
if not match:
    raise SystemExit('LIBKCAPI_VERSION ARG default missing from Dockerfile')
version = match.group(1).strip().strip('"').split()[0]
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
    if line.startswith('FROM ${SOURCES_REPO}/')
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
unreliable = ('busybox.net', 'musl.libc.org', 'zlib.net')
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

# less-704's configure exits 1 with "Cannot find terminal libraries" if no
# terminal library is visible to it (kairos-io/hadron#587). Two anchors have
# to hold at once: the `less` build stage has to see ncurses' libtinfo so it
# configures at all, and the assembled full image has to ship that same
# libtinfo next to the `less` binary or the binary links fine but refuses to
# start at runtime -- a failure mode CI's image-structure tests cannot catch
# today, since those only run against the `container` target, which never
# ships `less` in the first place.
def stage_body(marker):
    if marker not in dockerfile:
        raise SystemExit(f'stage {marker!r} not found in rendered Dockerfile')
    return dockerfile.split(marker, 1)[1].split('\nFROM ', 1)[0]

less_stage = stage_body('FROM rsync AS less\n')
if 'COPY --from=ncurses /ncurses/ /\n' not in less_stage:
    raise SystemExit(
        "the 'less' stage no longer copies ncurses -- its configure will "
        'fail with "Cannot find terminal libraries" (kairos-io/hadron#587)'
    )

merge_base = stage_body('FROM alpine-base AS full-image-merge-base\n')
if 'COPY --from=ncurses-runtime / /skeleton/' not in merge_base:
    raise SystemExit(
        "full-image-merge-base no longer ships ncurses' libtinfo -- less "
        'would still build but fail to start at runtime (kairos-io/hadron#587)'
    )
if 'COPY --from=less /less/ /skeleton/' not in merge_base:
    raise SystemExit('full-image-merge-base no longer ships the less stage')
PY

# --- Restricted upstream mode -------------------------------------------------
# What a fork pull request actually renders. Only the packages whose cache tag
# does not exist yet come from upstream; the cache is public, so every other
# package is pulled from it and the build does not depend on that upstream
# host answering at all.
render libkcapi

PYTHONPATH="$tmp" python3 - <<'PY'
from pathlib import Path

dockerfile = Path('Dockerfile').read_text()

if 'FROM sources-downloader-base AS libkcapi-download\n' not in dockerfile:
    raise SystemExit('restricted render did not fetch the selected package from upstream')
if 'FROM ${SOURCES_REPO}/libkcapi:' in dockerfile:
    raise SystemExit('restricted render still requires the libkcapi cache image')

# Everything not selected keeps its cache image (the FROM line still uses
# the ${ZLIB_VERSION} placeholder; Docker resolves it from the ARG default
# at build time).
if 'FROM ${SOURCES_REPO}/zlib:${ZLIB_VERSION} AS zlib-download' not in dockerfile:
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
# version at all. The committed Dockerfile is left untouched, so its
# ${LIBKCAPI_VERSION} placeholder must still be there.
render ''
if grep -q '^FROM sources-downloader-base AS libkcapi-download$' Dockerfile; then
    echo 'empty package list still fetched a package from upstream' >&2
    exit 1
fi
grep -q '^FROM \${SOURCES_REPO}/libkcapi:\${LIBKCAPI_VERSION} AS libkcapi-download$' Dockerfile

# A name that is not in sources.yaml is a typo, not a package to skip.
if render 'libkcapi no-such-package' 2>/dev/null; then
    echo 'restricted render accepted a package missing from sources.yaml' >&2
    exit 1
fi

# --- Trusted-build no-op ------------------------------------------------------
# Trusted builds skip hack/render.sh entirely and `docker build .` off the
# committed Dockerfile. Verify the file we ship still has the cache FROM
# line intact.
cp "$snapshot" Dockerfile
grep -q '^FROM \${SOURCES_REPO}/libkcapi:\${LIBKCAPI_VERSION} AS libkcapi-download$' Dockerfile

# --- Global-ARG invariant -----------------------------------------------------
# Every ${X_VERSION} that shows up in a `FROM ${SOURCES_REPO}/pkg:${X_VERSION}` tag
# has to be declared as a global ARG (before the first FROM). Docker only
# interpolates globally-scoped ARGs into FROM lines; a stage-local ARG would
# expand to the empty string and the trusted build would pull an unpinned
# floating tag. hack/render.sh scans the whole file with re.MULTILINE and would
# not catch that regression, so guard it here on the committed Dockerfile.
PYTHONPATH="$tmp" python3 - <<'PY'
import re, sys
from pathlib import Path

src = Path('Dockerfile').read_text()
first_from = re.search(r'(?m)^FROM ', src)
if first_from is None:
    raise SystemExit('Dockerfile has no FROM line')
header = src[:first_from.start()]
globals_ = {m.group(1) for m in re.finditer(r'(?m)^ARG ([A-Z0-9_]+)(?:=|$)', header)}

missing = []
for line in src.splitlines():
    if not line.startswith('FROM ${SOURCES_REPO}/'):
        continue
    for name in re.findall(r'\$\{([A-Z0-9_]+)\}', line):
        if name not in globals_:
            missing.append((name, line))

if missing:
    for name, line in missing:
        print(f'ARG {name} used in a FROM tag but not declared before the first FROM:\n  {line}', file=sys.stderr)
    raise SystemExit(1)
PY
