#!/bin/sh
# Refresh the `sha256` of each sources.yaml package so it matches the
# version currently pinned in the Dockerfile.
#
# sources.yaml carries the fetch metadata (urls, sha256, filename) and the
# Dockerfile carries the pinned version, as `ARG <version_arg>=<version>`.
# Bumping the ARG alone leaves the sha256 describing the previous release,
# and both consumers of that field then reject the new tarball: the
# populate-sources workflow fails the cell on a checksum mismatch, and the
# downloader stages hack/render.sh writes for fork pull requests exhaust
# their URL list without a match. This script closes that half of a bump.
#
#   hack/refresh-source-checksums.sh                 every package
#   hack/refresh-source-checksums.sh expat pcre2     the named packages
#   hack/refresh-source-checksums.sh --changed       packages whose version
#                                                    ARG differs from HEAD
#
# `--changed` is what the autobumper runs, straight after `updatecli apply`
# and before it stages anything. A package there whose new version no URL
# serves has its ARG reverted to the committed value and is reported as
# skipped, so one unfetchable package costs its own bump instead of the
# whole group's.

set -eu

# HADRON_ROOT overrides the repository root, the same way hack/gen-components.sh
# takes it, so the test can run the script against a fixture tree.
repo_root="${HADRON_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
cd "$repo_root"

if [ ! -f Dockerfile ] || [ ! -f sources.yaml ]; then
    echo "error: Dockerfile or sources.yaml not found in $repo_root" >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl not found" >&2
    exit 1
fi

changed_only=0
if [ "${1-}" = "--changed" ]; then
    changed_only=1
    shift
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# One flat record per package: pkg, version_arg, sha256, filename, urls.
# Tab separated because a URL may not contain a tab but the url list is
# space separated.
parse_sources() {
    awk '
        function flush(   ) {
            if (pkg != "")
                printf "%s\t%s\t%s\t%s\t%s\n", pkg, va, sha, fn, urls
        }
        function unquote(s) { gsub(/^"|"$/, "", s); return s }
        /^  [a-z0-9._-]+:$/ {
            flush()
            pkg = substr($0, 3, length($0) - 3)
            va = ""; sha = ""; fn = ""; urls = ""; inurls = 0
            next
        }
        /^    version_arg:[ \t]/ { va = unquote($2); inurls = 0; next }
        /^    sha256:[ \t]/      { sha = unquote($2); inurls = 0; next }
        /^    filename:[ \t]/    { fn = unquote($2); inurls = 0; next }
        /^    urls:[ \t]*$/      { inurls = 1; next }
        /^      - / {
            if (inurls) {
                u = unquote(substr($0, 9))
                urls = (urls == "" ? u : urls " " u)
            }
            next
        }
        /^    [a-z0-9_]+:/ { inurls = 0 }
        END { flush() }
    ' sources.yaml
}

# `ARG <NAME>=<value>` defaults, one `NAME value` pair per line. Same rule
# hack/render.sh, hack/list-missing-sources.sh and populate-sources use:
# the Dockerfile is the single source of truth for pinned versions.
parse_args() {
    awk '
        /^ARG [A-Z0-9_]+=/ {
            line = substr($0, 5)
            eq = index(line, "=")
            name = substr(line, 1, eq - 1)
            val = substr(line, eq + 1)
            gsub(/^"|"$/, "", val)
            sub(/[ \t].*$/, "", val)
            print name, val
        }
    '
}

parse_sources > "$work/packages"
parse_args < Dockerfile > "$work/args"

version_of() {
    awk -v want="$1" '$1 == want { print $2; found = 1; exit } END { if (!found) exit 1 }' "$work/args"
}

# Which packages to touch.
if [ "$changed_only" -eq 1 ]; then
    if [ $# -gt 0 ]; then
        echo "error: --changed takes no package arguments" >&2
        exit 1
    fi
    git show HEAD:Dockerfile | parse_args > "$work/args.head"
    # An ARG whose default moved, or one that did not exist before.
    awk 'NR == FNR { old[$1] = $2; next } !($1 in old) || old[$1] != $2 { print $1 }' \
        "$work/args.head" "$work/args" | sort > "$work/changed-args"
    # -F tab suits both files: changed-args has a single field per line.
    awk -F'	' 'NR == FNR { want[$1] = 1; next } $2 in want { print $1 }' \
        "$work/changed-args" "$work/packages" | sort > "$work/selected"
elif [ $# -gt 0 ]; then
    # Validate before building the list: a `for` loop piped into `sort` runs
    # in a subshell, where `exit 1` would only end the subshell and leave the
    # script reporting "no packages to refresh" for a typo.
    : > "$work/selected.raw"
    for pkg in "$@"; do
        if ! awk -F'	' -v p="$pkg" '$1 == p { found = 1 } END { exit !found }' "$work/packages"; then
            echo "error: package '$pkg' is not in sources.yaml" >&2
            exit 1
        fi
        echo "$pkg" >> "$work/selected.raw"
    done
    sort "$work/selected.raw" > "$work/selected"
else
    cut -f1 "$work/packages" | sort > "$work/selected"
fi

if [ ! -s "$work/selected" ]; then
    echo "no packages to refresh"
    exit 0
fi

: > "$work/skipped"
updated=0
unchanged=0

while IFS='	' read -r pkg va sha fn urls; do
    grep -qx "$pkg" "$work/selected" || continue

    if [ -z "$va" ] || [ -z "$fn" ] || [ -z "$urls" ]; then
        echo "error: package '$pkg' is missing version_arg, filename or urls" >&2
        exit 1
    fi

    if ! version=$(version_of "$va"); then
        echo "error: package '$pkg': no ARG $va= default in Dockerfile" >&2
        exit 1
    fi

    out="$work/$fn"
    actual=''
    for template in $urls; do
        url=$(printf '%s\n' "$template" | sed "s|\${version}|$version|g")
        rm -f "$out"
        if curl -fsSL --retry 2 --max-time 300 "$url" -o "$out"; then
            actual=$(sha256sum "$out" | awk '{print $1}')
            break
        fi
    done
    rm -f "$out"

    if [ -z "$actual" ]; then
        echo "warning: no URL served $pkg-$version, leaving its checksum alone" >&2
        echo "$pkg $va $version" >> "$work/skipped"
        continue
    fi

    if [ "$actual" = "$sha" ]; then
        unchanged=$((unchanged + 1))
        continue
    fi

    # Rewrite the `sha256:` line inside this package's block only. Every
    # other line of the 900-odd line file, comments included, is copied
    # through byte for byte.
    awk -v pkg="  $pkg:" -v new="$actual" '
        $0 == pkg { inpkg = 1; print; next }
        /^  [a-z0-9._-]+:$/ { inpkg = 0 }
        inpkg && /^    sha256:[ \t]/ {
            sub(/^    sha256:[ \t]*[^ \t]*/, "    sha256: " new)
            inpkg = 0
            done = 1
        }
        { print }
        END { if (!done) exit 1 }
    ' sources.yaml > "$work/sources.new" || {
        echo "error: package '$pkg' has no sha256 line to rewrite" >&2
        exit 1
    }
    mv "$work/sources.new" sources.yaml
    echo "$pkg $version: $sha -> $actual"
    updated=$((updated + 1))
done < "$work/packages"

# A bump nobody can fetch is worse than no bump: the pull request it would
# open cannot build, and it hides the other bumps in the same group. Put
# the ARG back so the rest of the group still lands.
if [ "$changed_only" -eq 1 ] && [ -s "$work/skipped" ]; then
    while read -r pkg va version; do
        old=$(git show HEAD:Dockerfile | parse_args | awk -v want="$va" '$1 == want { print $2; exit }')
        if [ -z "$old" ]; then
            echo "error: cannot revert $va, it has no default in HEAD:Dockerfile" >&2
            exit 1
        fi
        awk -v arg="$va" -v val="$old" '
            index($0, "ARG " arg "=") == 1 { print "ARG " arg "=" val; next }
            { print }
        ' Dockerfile > "$work/Dockerfile.new"
        mv "$work/Dockerfile.new" Dockerfile
        echo "reverted $pkg to $old ($version was not fetchable)"
    done < "$work/skipped"
fi

echo "refreshed $updated checksum(s), $unchanged already current, $(wc -l < "$work/skipped" | tr -d ' ') skipped"

if [ -n "${GITHUB_STEP_SUMMARY-}" ] && [ -s "$work/skipped" ]; then
    {
        echo "### Bumps dropped, no URL served the tarball"
        echo
        while read -r pkg _ version; do
            echo "- \`$pkg\` $version"
        done < "$work/skipped"
    } >> "$GITHUB_STEP_SUMMARY"
fi
