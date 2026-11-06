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
#
# The bash patch checksums in files/bash/patches.sha256 are refreshed along
# with the `bash` package, and under `--changed` whenever BASH_VERSION or
# PATCH_LEVEL moved. A PATCH_LEVEL no mirror serves is reverted the same way.

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
# Separated by the ASCII unit separator, not a tab: the url list is space
# separated, and `read` collapses runs of a whitespace IFS, so an empty
# field such as a blank sha256 would shift every field after it.
us=$(printf '\037')
parse_sources() {
    awk '
        function flush(   ) {
            if (pkg != "")
                printf "%s\037%s\037%s\037%s\037%s\n", pkg, va, sha, fn, urls
        }
        function unquote(s) { gsub(/^"|"$/, "", s); return s }
        /^  [a-z0-9._-]+:$/ {
            flush()
            pkg = substr($0, 3, length($0) - 3)
            va = ""; sha = ""; fn = ""; urls = ""; inurls = 0
            next
        }
        /^    version_arg:[ \t]/ { va = unquote($2); inurls = 0; next }
        /^    sha256:([ \t]|$)/  { sha = unquote($2); inurls = 0; next }
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
    # An updatecli shell source that prints nothing rewrites `ARG X=1.2` to a
    # bare `ARG X` (or `ARG X=`). parse_args then drops X or reads it empty,
    # the comparison below sees no change, and the empty pin gets committed.
    lost=$(awk 'NR == FNR { if ($2 != "") now[$1] = 1; next } $2 != "" && !($1 in now) { print $1 }' \
        "$work/args" "$work/args.head")
    if [ -n "$lost" ]; then
        echo "error: these ARGs had a default at HEAD and have none now:" $lost >&2
        exit 1
    fi
    # An ARG whose default moved, or one that did not exist before.
    awk 'NR == FNR { old[$1] = $2; next } !($1 in old) || old[$1] != $2 { print $1 }' \
        "$work/args.head" "$work/args" | sort > "$work/changed-args"
    # -F "$us" suits both files: changed-args has a single field per line.
    awk -F "$us" 'NR == FNR { want[$1] = 1; next } $2 in want { print $1 }' \
        "$work/changed-args" "$work/packages" | sort > "$work/selected"
elif [ $# -gt 0 ]; then
    # Validate before building the list: a `for` loop piped into `sort` runs
    # in a subshell, where `exit 1` would only end the subshell and leave the
    # script reporting "no packages to refresh" for a typo.
    : > "$work/selected.raw"
    for pkg in "$@"; do
        if ! awk -F "$us" -v p="$pkg" '$1 == p { found = 1 } END { exit !found }' "$work/packages"; then
            echo "error: package '$pkg' is not in sources.yaml" >&2
            exit 1
        fi
        echo "$pkg" >> "$work/selected.raw"
    done
    sort "$work/selected.raw" > "$work/selected"
else
    cut -d "$us" -f1 "$work/packages" | sort > "$work/selected"
fi

: > "$work/skipped"
: > "$work/skipped-patches"
updated=0
unchanged=0

# Put `ARG <name>=` back to its HEAD:Dockerfile default and leave that
# default in $reverted_to.
revert_arg() {
    reverted_to=$(git show HEAD:Dockerfile | parse_args | awk -v want="$1" '$1 == want { print $2; exit }')
    if [ -z "$reverted_to" ]; then
        echo "error: cannot revert $1, it has no default in HEAD:Dockerfile" >&2
        exit 1
    fi
    awk -v arg="$1" -v val="$reverted_to" '
        index($0, "ARG " arg "=") == 1 { print "ARG " arg "=" val; next }
        { print }
    ' Dockerfile > "$work/Dockerfile.new"
    mv "$work/Dockerfile.new" Dockerfile
}

# The upstream bash patches are single files, not a tarball, so they have no
# sources.yaml entry and no cache image. The bash-download stage fetches
# patches 1 to PATCH_LEVEL of BASH_VERSION from the GNU mirrors and checks
# each one against this file, which holds one `sha256  name` line per patch.
bash_patches=files/bash/patches.sha256

refresh_bash_patches() {
    if ! bash_version=$(version_of BASH_VERSION); then
        echo "error: no ARG BASH_VERSION= default in Dockerfile" >&2
        exit 1
    fi
    level=$(version_of PATCH_LEVEL)
    case "$level" in
        ''|*[!0-9]*)
            echo "error: ARG PATCH_LEVEL=$level is not a number" >&2
            exit 1
            ;;
    esac
    mirrors=''
    for name in GNU_MIRROR_1 GNU_MIRROR_2 GNU_MIRROR_3; do
        if mirror=$(version_of "$name"); then
            mirrors="$mirrors $mirror"
        fi
    done
    if [ -z "$mirrors" ]; then
        echo "error: no ARG GNU_MIRROR_1/2/3= default in Dockerfile" >&2
        exit 1
    fi

    nodot=$(printf '%s\n' "$bash_version" | tr -d '.')
    : > "$work/patches.new"
    i=1
    while [ "$i" -le "$level" ]; do
        patch_name=$(printf 'bash%s-%03d' "$nodot" "$i")
        sum=''
        for mirror in $mirrors; do
            rm -f "$work/patch"
            if curl -fsSL --retry 2 --max-time 120 "$mirror/bash/bash-$bash_version-patches/$patch_name" -o "$work/patch"; then
                sum=$(sha256sum "$work/patch" | awk '{print $1}')
                break
            fi
        done
        rm -f "$work/patch"
        if [ -z "$sum" ]; then
            echo "warning: no mirror served $patch_name, leaving $bash_patches alone" >&2
            echo "bash-patches PATCH_LEVEL $bash_version-$level" >> "$work/skipped-patches"
            return 1
        fi
        printf '%s  %s\n' "$sum" "$patch_name" >> "$work/patches.new"
        i=$((i + 1))
    done

    if cmp -s "$work/patches.new" "$bash_patches"; then
        unchanged=$((unchanged + 1))
        return 0
    fi
    mv "$work/patches.new" "$bash_patches"
    echo "bash patches $bash_version up to $level: rewrote $bash_patches"
    updated=$((updated + 1))
}

patches_selected=0
if [ -f "$bash_patches" ] && version_of PATCH_LEVEL >/dev/null; then
    if [ "$changed_only" -eq 1 ]; then
        if grep -qx -e BASH_VERSION -e PATCH_LEVEL "$work/changed-args"; then
            patches_selected=1
        fi
    elif grep -qx bash "$work/selected"; then
        patches_selected=1
    fi
fi

# Runs before the tarballs so that, under --changed, a bash bump whose
# patches no mirror serves is reverted before its tarball checksum moves.
if [ "$patches_selected" -eq 1 ] && ! refresh_bash_patches && [ "$changed_only" -eq 1 ]; then
    for name in BASH_VERSION PATCH_LEVEL; do
        grep -qx "$name" "$work/changed-args" || continue
        revert_arg "$name"
        echo "reverted $name to $reverted_to (bash patches were not fetchable)"
    done
    parse_args < Dockerfile > "$work/args"
    grep -vx bash "$work/selected" > "$work/selected.new" || true
    mv "$work/selected.new" "$work/selected"
fi

if [ ! -s "$work/selected" ] && [ "$patches_selected" -eq 0 ]; then
    echo "no packages to refresh"
    exit 0
fi

while IFS="$us" read -r pkg va sha fn urls; do
    grep -qx "$pkg" "$work/selected" || continue

    if [ -z "$va" ] || [ -z "$fn" ] || [ -z "$urls" ]; then
        echo "error: package '$pkg' is missing version_arg, filename or urls" >&2
        exit 1
    fi

    if ! version=$(version_of "$va"); then
        echo "error: package '$pkg': no ARG $va= default in Dockerfile" >&2
        exit 1
    fi

    # Same placeholders, and the same order, as hack/render.sh and
    # .github/workflows/populate-sources.yml. All three must stay in step.
    version_underscore=$(printf '%s\n' "$version" | tr '.' '_')
    version_major_minor=$(printf '%s\n' "$version" | cut -d. -f1,2)

    out="$work/$fn"
    actual=''
    for template in $urls; do
        url=$(printf '%s\n' "$template" \
            | sed -e "s|\${version_underscore}|$version_underscore|g" \
                  -e "s|\${version_major_minor}|$version_major_minor|g" \
                  -e "s|\${version}|$version|g")
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

    # Rewrite the `sha256:` line inside this package's block only, or add
    # one under the package name when the block has none. Every other line
    # of the 900-odd line file, comments included, is copied through byte
    # for byte.
    awk -v pkg="  $pkg:" -v new="$actual" '
        NR == FNR {
            if ($0 == pkg) { scan = 1; next }
            if (/^  [a-z0-9._-]+:$/) scan = 0
            if (scan && /^    sha256:([ \t]|$)/) has = 1
            next
        }
        $0 == pkg {
            print
            if (has) inpkg = 1
            else { print "    sha256: " new; done = 1 }
            next
        }
        /^  [a-z0-9._-]+:$/ { inpkg = 0 }
        inpkg && /^    sha256:([ \t]|$)/ {
            sub(/^    sha256:[ \t]*[^ \t]*/, "    sha256: " new)
            inpkg = 0
            done = 1
        }
        { print }
        END { if (!done) exit 1 }
    ' sources.yaml sources.yaml > "$work/sources.new" || {
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
        revert_arg "$va"
        echo "reverted $pkg to $reverted_to ($version was not fetchable)"
        # The patch checksums were written for the bash version that is
        # being dropped, so they go back to HEAD along with PATCH_LEVEL.
        if [ "$va" = BASH_VERSION ] && [ "$patches_selected" -eq 1 ]; then
            if grep -qx PATCH_LEVEL "$work/changed-args"; then
                revert_arg PATCH_LEVEL
                echo "reverted PATCH_LEVEL to $reverted_to (bash $version was not fetchable)"
            fi
            if git cat-file -e "HEAD:$bash_patches" 2>/dev/null; then
                git show "HEAD:$bash_patches" > "$bash_patches"
            fi
        fi
    done < "$work/skipped"
fi

cat "$work/skipped" "$work/skipped-patches" > "$work/skipped-all"
echo "refreshed $updated checksum(s), $unchanged already current, $(wc -l < "$work/skipped-all" | tr -d ' ') skipped"

if [ -n "${GITHUB_STEP_SUMMARY-}" ] && [ -s "$work/skipped-all" ]; then
    {
        echo "### Bumps dropped, no URL served the tarball"
        echo
        while read -r pkg _ version; do
            echo "- \`$pkg\` $version"
        done < "$work/skipped-all"
    } >> "$GITHUB_STEP_SUMMARY"
fi
