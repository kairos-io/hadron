#!/bin/sh
# Self-contained, no-network test for hack/refresh-source-checksums.sh.
# Every URL in the fixtures is a file:// URL, which curl serves locally, so
# the real fetch-and-hash path runs without reaching any upstream host.
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REFRESH="$SCRIPT_DIR/refresh-source-checksums.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- Tarball fixtures, one per package and version ---
TARS="$WORK/tars"
mkdir -p "$TARS"
printf 'alpha 1.0\n' > "$TARS/alpha-1.0.tar.gz"
printf 'alpha 2.0\n' > "$TARS/alpha-2.0.tar.gz"
printf 'beta 3.1\n'  > "$TARS/beta-3.1.tar.gz"
sha_alpha_1=$(sha256sum "$TARS/alpha-1.0.tar.gz" | awk '{print $1}')
sha_alpha_2=$(sha256sum "$TARS/alpha-2.0.tar.gz" | awk '{print $1}')
sha_beta_3=$(sha256sum "$TARS/beta-3.1.tar.gz" | awk '{print $1}')

# --- Fixture repo root ---
ROOT="$WORK/repo"
mkdir -p "$ROOT"

write_fixture() {
    cat > "$ROOT/Dockerfile" <<EOF
ARG SOURCES_REPO=ghcr.io/kairos-io/hadron-sources
ARG ALPHA_VERSION=$1
ARG BETA_VERSION=$2
ARG GAMMA_VERSION=$3
ARG NOT_A_VERSION=hello
EOF
    cat > "$ROOT/sources.yaml" <<EOF
# A leading comment that must survive every rewrite.
packages:
  alpha:
    version_arg: ALPHA_VERSION
    sha256: $4
    urls:
      - file://$TARS/alpha-\${version}.tar.gz
    filename: alpha.tar.gz

  # An interior comment that must survive too.
  beta:
    version_arg: BETA_VERSION
    sha256: $5
    urls:
      - file://$TARS/beta-missing-\${version}.tar.gz
      - file://$TARS/beta-\${version}.tar.gz
    filename: beta.tar.gz

  gamma:
    version_arg: GAMMA_VERSION
    sha256: 0000000000000000000000000000000000000000000000000000000000000000
    urls:
      - file://$TARS/gamma-\${version}.tar.gz
    filename: gamma.tar.gz
EOF
}

# =====================================================================
# 1. Named packages: a stale checksum is rewritten to the pinned version
# =====================================================================
write_fixture 2.0 3.1 9.9 "$sha_alpha_1" "$sha_beta_3"
HADRON_ROOT="$ROOT" "$REFRESH" alpha > "$WORK/out1" 2>&1 || fail "refresh alpha exited non-zero"

grep -q "$sha_alpha_2" "$ROOT/sources.yaml" || fail "alpha sha256 not updated to the 2.0 tarball"
grep -q "$sha_alpha_1" "$ROOT/sources.yaml" && fail "alpha still carries the 1.0 checksum"
grep -q "$sha_beta_3"  "$ROOT/sources.yaml" || fail "beta checksum touched by an alpha-only run"
grep -q '^# A leading comment' "$ROOT/sources.yaml" || fail "leading comment lost"
grep -q '^  # An interior comment' "$ROOT/sources.yaml" || fail "interior comment lost"
grep -q '^    filename: alpha.tar.gz' "$ROOT/sources.yaml" || fail "alpha filename line lost"
grep -q "refreshed 1 checksum" "$WORK/out1" || fail "summary did not report one refresh: $(cat "$WORK/out1")"

# Idempotent: a second run finds nothing to do.
HADRON_ROOT="$ROOT" "$REFRESH" alpha > "$WORK/out2" 2>&1 || fail "second alpha run exited non-zero"
grep -q "refreshed 0 checksum" "$WORK/out2" || fail "second run was not a no-op: $(cat "$WORK/out2")"

# =====================================================================
# 2. URL fallback: the first URL 404s, the second serves the tarball
# =====================================================================
write_fixture 2.0 3.1 9.9 "$sha_alpha_1" "0000000000000000000000000000000000000000000000000000000000000000"
HADRON_ROOT="$ROOT" "$REFRESH" beta > "$WORK/out3" 2>&1 || fail "refresh beta exited non-zero"
grep -q "$sha_beta_3" "$ROOT/sources.yaml" || fail "beta did not fall through to its second URL"

# =====================================================================
# 3. An unfetchable package leaves its checksum alone and is reported
# =====================================================================
write_fixture 2.0 3.1 9.9 "$sha_alpha_1" "$sha_beta_3"
HADRON_ROOT="$ROOT" "$REFRESH" gamma > "$WORK/out4" 2>&1 || fail "refresh gamma exited non-zero"
grep -q '0000000000000000000000000000000000000000000000000000000000000000' "$ROOT/sources.yaml" \
    || fail "gamma checksum was replaced despite no URL serving it"
grep -q "no URL served gamma-9.9" "$WORK/out4" || fail "gamma skip not reported: $(cat "$WORK/out4")"
grep -q "1 skipped" "$WORK/out4" || fail "summary did not count the skip: $(cat "$WORK/out4")"

# =====================================================================
# 3b. An empty, bare or missing sha256 is refreshed like a stale one, and
#     the fields after it (filename, urls) are still read correctly
# =====================================================================
for shaline in 'sha256: ""' 'sha256:' '' "sha256: $sha_alpha_1"; do
    {
        echo 'packages:'
        echo '  alpha:'
        echo '    version_arg: ALPHA_VERSION'
        [ -n "$shaline" ] && echo "    $shaline"
        echo '    urls:'
        echo "      - file://$TARS/alpha-\${version}.tar.gz"
        echo '    filename: alpha.tar.gz'
        echo ''
        echo '  beta:'
        echo '    version_arg: BETA_VERSION'
        echo "    sha256: $sha_beta_3"
        echo '    urls:'
        echo "      - file://$TARS/beta-\${version}.tar.gz"
        echo '    filename: beta.tar.gz'
    } > "$ROOT/sources.yaml"
    HADRON_ROOT="$ROOT" "$REFRESH" alpha > "$WORK/out-sha" 2>&1 \
        || fail "refresh alpha with '$shaline' exited non-zero: $(cat "$WORK/out-sha")"
    [ "$(grep -c "^    sha256: $sha_alpha_2\$" "$ROOT/sources.yaml")" -eq 1 ] \
        || fail "alpha with '$shaline' did not get exactly one 2.0 sha256 line: $(cat "$ROOT/sources.yaml")"
    [ "$(grep -c '^    sha256:' "$ROOT/sources.yaml")" -eq 2 ] \
        || fail "alpha with '$shaline' left a stray sha256 line: $(cat "$ROOT/sources.yaml")"
    grep -q "^    sha256: $sha_beta_3\$" "$ROOT/sources.yaml" || fail "beta checksum touched with alpha '$shaline'"
    grep -q '^    filename: alpha.tar.gz' "$ROOT/sources.yaml" || fail "alpha filename line lost with '$shaline'"
    grep -q "refreshed 1 checksum" "$WORK/out-sha" || fail "alpha with '$shaline' not reported as refreshed: $(cat "$WORK/out-sha")"
done

# =====================================================================
# 4. --changed picks exactly the packages whose ARG moved, and reverts
#    the ones no URL serves
# =====================================================================
GITROOT="$WORK/git"
mkdir -p "$GITROOT"
ROOT="$GITROOT"
write_fixture 1.0 3.1 9.9 "$sha_alpha_1" "$sha_beta_3"

git -C "$GITROOT" init -q
git -C "$GITROOT" config user.email test@example.invalid
git -C "$GITROOT" config user.name test
git -C "$GITROOT" add -A
git -C "$GITROOT" commit -qm base

# Simulate `updatecli apply`: alpha bumps to a version that exists, gamma to
# one that does not, beta is untouched.
sed -i 's/^ARG ALPHA_VERSION=1.0$/ARG ALPHA_VERSION=2.0/' "$GITROOT/Dockerfile"
sed -i 's/^ARG GAMMA_VERSION=9.9$/ARG GAMMA_VERSION=9.10/' "$GITROOT/Dockerfile"

HADRON_ROOT="$GITROOT" "$REFRESH" --changed > "$WORK/out5" 2>&1 || fail "--changed exited non-zero"

grep -q "$sha_alpha_2" "$GITROOT/sources.yaml" || fail "--changed did not refresh alpha"
grep -q "$sha_beta_3"  "$GITROOT/sources.yaml" || fail "--changed touched the unbumped beta"
grep -qx 'ARG GAMMA_VERSION=9.9' "$GITROOT/Dockerfile" \
    || fail "unfetchable gamma bump was not reverted: $(grep GAMMA "$GITROOT/Dockerfile")"
grep -qx 'ARG ALPHA_VERSION=2.0' "$GITROOT/Dockerfile" \
    || fail "--changed reverted the fetchable alpha bump too"
grep -q "reverted gamma to 9.9" "$WORK/out5" || fail "revert not reported: $(cat "$WORK/out5")"

# The step summary names the dropped bump so the nightly run says why.
rm -f "$WORK/summary"
git -C "$GITROOT" checkout -q -- Dockerfile sources.yaml
sed -i 's/^ARG GAMMA_VERSION=9.9$/ARG GAMMA_VERSION=9.10/' "$GITROOT/Dockerfile"
HADRON_ROOT="$GITROOT" GITHUB_STEP_SUMMARY="$WORK/summary" "$REFRESH" --changed >/dev/null 2>&1 \
    || fail "--changed with a step summary exited non-zero"
grep -q 'gamma` 9.10' "$WORK/summary" || fail "step summary did not name the dropped bump"

# An updatecli shell source that printed nothing leaves a bare `ARG X` (or
# `ARG X=`). That must fail the run, not report "no packages to refresh".
for blank in 'ARG BETA_VERSION' 'ARG BETA_VERSION='; do
    git -C "$GITROOT" checkout -q -- Dockerfile sources.yaml
    sed -i "s/^ARG BETA_VERSION=3.1\$/$blank/" "$GITROOT/Dockerfile"
    grep -qx "$blank" "$GITROOT/Dockerfile" || fail "fixture did not blank BETA_VERSION"
    if HADRON_ROOT="$GITROOT" "$REFRESH" --changed > "$WORK/out6" 2>&1; then
        fail "--changed accepted '$blank': $(cat "$WORK/out6")"
    fi
    grep -q "have none now: BETA_VERSION" "$WORK/out6" || fail "lost default not named for '$blank': $(cat "$WORK/out6")"
done
git -C "$GITROOT" checkout -q -- Dockerfile sources.yaml

# =====================================================================
# 5. A package named on the command line that does not exist is an error
# =====================================================================
if HADRON_ROOT="$GITROOT" "$REFRESH" nosuchpkg >/dev/null 2>&1; then
    fail "an unknown package name should be an error"
fi

# =====================================================================
# 6. The committed sources.yaml parses, and every package resolves to an
#    ARG default in the committed Dockerfile
# =====================================================================
REAL_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
if [ -f "$REAL_ROOT/sources.yaml" ] && [ -f "$REAL_ROOT/Dockerfile" ]; then
    count=$(awk '/^  [a-z0-9._-]+:$/ { n++ } END { print n + 0 }' "$REAL_ROOT/sources.yaml")
    [ "$count" -gt 50 ] || fail "only $count packages parsed out of the real sources.yaml"
    missing=$(awk '
        NR == FNR {
            if (/^ARG [A-Z0-9_]+=/) {
                line = substr($0, 5); eq = index(line, "=")
                args[substr(line, 1, eq - 1)] = 1
            }
            next
        }
        /^  [a-z0-9._-]+:$/ { pkg = substr($0, 3, length($0) - 3) }
        /^    version_arg:[ \t]/ { if (!($2 in args)) print pkg " " $2 }
    ' "$REAL_ROOT/Dockerfile" "$REAL_ROOT/sources.yaml")
    [ -z "$missing" ] || fail "sources.yaml names version_args with no ARG default: $missing"
fi

# =====================================================================
# 7. Bash patches: files/bash/patches.sha256 follows BASH_VERSION and
#    PATCH_LEVEL, and a patch level no mirror serves is reverted
# =====================================================================
GNU="$WORK/gnu"
mkdir -p "$GNU/bash/bash-5.3-patches" "$GNU/bash/bash-5.4-patches" "$WORK/gnu-empty"
printf 'bash 5.3\n' > "$GNU/bash/bash-5.3.tar.gz"
sha_bash_53=$(sha256sum "$GNU/bash/bash-5.3.tar.gz" | awk '{print $1}')
for n in 001 002 003; do
    printf 'bash53 patch %s\n' "$n" > "$GNU/bash/bash-5.3-patches/bash53-$n"
    printf 'bash54 patch %s\n' "$n" > "$GNU/bash/bash-5.4-patches/bash54-$n"
done
patch_sum() { sha256sum "$GNU/bash/bash-$1-patches/$2" | awk '{print $1}'; }

BROOT="$WORK/bashrepo"
mkdir -p "$BROOT/files/bash"
cat > "$BROOT/Dockerfile" <<EOF
ARG GNU_MIRROR_1=file://$WORK/gnu-empty
ARG GNU_MIRROR_2=file://$GNU
ARG BASH_VERSION=5.3
FROM scratch AS bash-download
ARG PATCH_LEVEL=1
EOF
cat > "$BROOT/sources.yaml" <<EOF
packages:
  bash:
    version_arg: BASH_VERSION
    sha256: $sha_bash_53
    urls:
      - file://$GNU/bash/bash-\${version}.tar.gz
    filename: bash.tar.gz
EOF
printf 'stale  bash53-001\n' > "$BROOT/files/bash/patches.sha256"

# Named run: the stale line is replaced, fetched through the second mirror.
HADRON_ROOT="$BROOT" "$REFRESH" bash > "$WORK/out7" 2>&1 || fail "refresh bash exited non-zero: $(cat "$WORK/out7")"
printf '%s  bash53-001\n' "$(patch_sum 5.3 bash53-001)" > "$WORK/want"
cmp -s "$WORK/want" "$BROOT/files/bash/patches.sha256" \
    || fail "named bash run did not rewrite the patch checksums: $(cat "$BROOT/files/bash/patches.sha256")"

git -C "$BROOT" init -q
git -C "$BROOT" config user.email test@example.invalid
git -C "$BROOT" config user.name test
git -C "$BROOT" add -A
git -C "$BROOT" commit -qm base

# --changed after a PATCH_LEVEL bump appends the new patches.
sed -i 's/^ARG PATCH_LEVEL=1$/ARG PATCH_LEVEL=3/' "$BROOT/Dockerfile"
HADRON_ROOT="$BROOT" "$REFRESH" --changed > "$WORK/out8" 2>&1 || fail "--changed PATCH_LEVEL exited non-zero: $(cat "$WORK/out8")"
for n in 001 002 003; do
    printf '%s  bash53-%s\n' "$(patch_sum 5.3 "bash53-$n")" "$n"
done > "$WORK/want"
cmp -s "$WORK/want" "$BROOT/files/bash/patches.sha256" \
    || fail "PATCH_LEVEL bump did not refresh the patch checksums: $(cat "$BROOT/files/bash/patches.sha256")"
grep -qx 'ARG PATCH_LEVEL=3' "$BROOT/Dockerfile" || fail "fetchable PATCH_LEVEL bump was reverted"
git -C "$BROOT" commit -qam level3

# A PATCH_LEVEL with no published patch is reverted and the file is left alone.
sed -i 's/^ARG PATCH_LEVEL=3$/ARG PATCH_LEVEL=4/' "$BROOT/Dockerfile"
HADRON_ROOT="$BROOT" "$REFRESH" --changed > "$WORK/out9" 2>&1 || fail "--changed unfetchable PATCH_LEVEL exited non-zero: $(cat "$WORK/out9")"
grep -qx 'ARG PATCH_LEVEL=3' "$BROOT/Dockerfile" \
    || fail "unfetchable PATCH_LEVEL bump was not reverted: $(grep PATCH_LEVEL "$BROOT/Dockerfile")"
cmp -s "$WORK/want" "$BROOT/files/bash/patches.sha256" || fail "unfetchable PATCH_LEVEL bump touched the patch checksums"
grep -q "no mirror served bash53-004" "$WORK/out9" || fail "missing patch not reported: $(cat "$WORK/out9")"
grep -q "1 skipped" "$WORK/out9" || fail "summary did not count the patch skip: $(cat "$WORK/out9")"

# A BASH_VERSION whose patches exist but whose tarball does not is reverted,
# and the patch checksums go back with it.
git -C "$BROOT" checkout -q -- Dockerfile
sed -i 's/^ARG BASH_VERSION=5.3$/ARG BASH_VERSION=5.4/' "$BROOT/Dockerfile"
HADRON_ROOT="$BROOT" "$REFRESH" --changed > "$WORK/out10" 2>&1 || fail "--changed unfetchable BASH_VERSION exited non-zero: $(cat "$WORK/out10")"
grep -qx 'ARG BASH_VERSION=5.3' "$BROOT/Dockerfile" || fail "unfetchable BASH_VERSION bump was not reverted"
cmp -s "$WORK/want" "$BROOT/files/bash/patches.sha256" \
    || fail "patch checksums not restored with BASH_VERSION: $(cat "$BROOT/files/bash/patches.sha256")"
grep -q "$sha_bash_53" "$BROOT/sources.yaml" || fail "bash tarball checksum moved for a reverted bump"

# The committed patch checksums cover exactly patches 1 to PATCH_LEVEL of
# the committed BASH_VERSION, so the bash-download stage finds every one.
if [ -f "$REAL_ROOT/files/bash/patches.sha256" ]; then
    real_bash=$(awk -F= '/^ARG BASH_VERSION=/ { print $2; exit }' "$REAL_ROOT/Dockerfile")
    real_level=$(awk -F= '/^ARG PATCH_LEVEL=/ { print $2; exit }' "$REAL_ROOT/Dockerfile")
    [ -n "$real_bash" ] && [ -n "$real_level" ] || fail "BASH_VERSION or PATCH_LEVEL default missing from the Dockerfile"
    nodot=$(printf '%s' "$real_bash" | tr -d '.')
    i=1
    : > "$WORK/want-names"
    while [ "$i" -le "$real_level" ]; do
        printf 'bash%s-%03d\n' "$nodot" "$i" >> "$WORK/want-names"
        i=$((i + 1))
    done
    awk '{ print $2 }' "$REAL_ROOT/files/bash/patches.sha256" > "$WORK/have-names"
    cmp -s "$WORK/want-names" "$WORK/have-names" \
        || fail "files/bash/patches.sha256 does not list bash $real_bash patches 1 to $real_level"
    if awk 'length($1) != 64 || $1 ~ /[^0-9a-f]/ { bad = 1 } END { exit !bad }' "$REAL_ROOT/files/bash/patches.sha256"; then
        fail "files/bash/patches.sha256 has a line that is not a sha256"
    fi
fi

echo "PASS: hack/refresh-source-checksums.sh"
