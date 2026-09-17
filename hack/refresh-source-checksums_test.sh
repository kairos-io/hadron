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

echo "PASS: hack/refresh-source-checksums.sh"
