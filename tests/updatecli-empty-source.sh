#!/bin/sh
# Every updatecli `kind: shell` source must fail when it finds no version.
#
# updatecli takes a shell source's stdout as the new version. A source that
# prints nothing and exits 0 rewrites `ARG MPC_VERSION=1.4.1` to a bare
# `ARG MPC_VERSION`, and the autobumper commits an image that cannot build.
# A pipeline ending in `| tail -n 1` exits 0 whatever its input, so a failed
# `git ls-remote` or `curl` upstream of it goes unnoticed.
#
# This runs each source command with git, curl and wget replaced by stubs that
# print nothing and fail, the way an unreachable mirror looks, and expects a
# non-zero exit and empty stdout from every one.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/cmds"
for tool in git curl wget; do
    printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/$tool"
    chmod +x "$WORK/bin/$tool"
done

# One file per shell source, named <manifest>.<source>. A command block is
# every line indented deeper than its `command: |` key.
for manifest in "$ROOT"/updatecli.d/*.yaml; do
    awk -v out="$WORK/cmds/$(basename "$manifest" .yaml)" '
        function indent(s) { match(s, /^ */); return RLENGTH }
        incmd {
            if ($0 ~ /^[ \t]*$/ || indent($0) > cmdindent) {
                print substr($0, cmdindent + 3) > file
                next
            }
            close(file); incmd = 0
        }
        /^  [A-Za-z0-9_-]+:[ \t]*$/ { name = $1; sub(/:$/, "", name); shell = 0 }
        /^    kind:[ \t]*shell[ \t]*$/ { shell = 1 }
        shell && /^      command:[ \t]*\|[ \t]*$/ {
            cmdindent = indent($0); file = out "." name; incmd = 1
        }
    ' "$manifest"
done

count=$(find "$WORK/cmds" -type f | wc -l)
[ "$count" -ge 20 ] || { echo "FAIL: only $count shell sources found under updatecli.d" >&2; exit 1; }

failed=0
for cmd in "$WORK"/cmds/*; do
    src=$(basename "$cmd")
    # bash_patch_level reads another source's value through a template.
    sed -i 's/{{ *source "[a-z_]*" *}}/5.3/g' "$cmd"
    if PATH="$WORK/bin:$PATH" timeout 60 sh "$cmd" > "$WORK/stdout" 2>/dev/null; then
        echo "FAIL: $src exits 0 when it finds no version" >&2
        failed=1
    elif [ -s "$WORK/stdout" ]; then
        echo "FAIL: $src prints '$(cat "$WORK/stdout")' when it finds no version" >&2
        failed=1
    fi
done
[ "$failed" -eq 0 ] || exit 1

echo "PASS: all $count updatecli shell sources fail on empty output"
