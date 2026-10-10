#!/bin/sh
# Self-contained, no-network test for hack/gen-components.sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GEN="$SCRIPT_DIR/gen-components.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Fixture repo root ---
mkdir -p "$WORK/updatecli.d"
cat > "$WORK/Dockerfile" <<'EOF'
ARG KERNEL_VERSION=9.9.9
ARG SYSTEMD_VERSION=260.2
ARG MUSSEL_VERSION="abc123"
ARG SOMETHING_ELSE=notaversion
EOF
cat > "$WORK/updatecli.d/kernel-and-boot.yaml" <<'EOF'
targets:
  kernel:
    spec:
      instruction:
        matcher: KERNEL_VERSION
EOF
cat > "$WORK/updatecli.d/core-system.yaml" <<'EOF'
targets:
  systemd:
    spec:
      instruction:
        matcher: SYSTEMD_VERSION
EOF

# --- Run generator against the fixture ---
HADRON_MIN_VERSION_ARGS=1 HADRON_ROOT="$WORK" "$GEN" --ref worktree --name components --out-dir "$WORK" --format both --date "2026-06-25"

fail() { echo "FAIL: $1" >&2; exit 1; }

JSON="$WORK/components.json"
MD="$WORK/components.md"

[ -f "$JSON" ] || fail "components.json not created"
[ -f "$MD" ]   || fail "components.md not created"

# kernel parsed and grouped
grep -q '"kernel": "9.9.9"' "$JSON" || fail "kernel version/name wrong in JSON"
grep -q '"Kernel And Boot"' "$JSON" || fail "Kernel And Boot group missing in JSON"

# quoted value stripped + uncovered ARG -> Other
grep -q '"mussel": "abc123"' "$JSON" || fail "mussel quote-strip/name wrong in JSON"
grep -q '"Other"' "$JSON"            || fail "Other group missing in JSON"

# non *_VERSION ARG excluded
grep -q 'something' "$JSON" && fail "SOMETHING_ELSE should be excluded"

# markdown headings
grep -q '### Kernel And Boot' "$MD" || fail "MD missing Kernel And Boot heading"
grep -q '### Other' "$MD"           || fail "MD missing Other heading"
grep -q '| kernel | 9.9.9 |' "$MD"  || fail "MD missing kernel row"

# JSON is valid if python3 is available
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$JSON" || fail "components.json is not valid JSON"
fi

# --- version_arg -> package name index, from sources.yaml ---
# The fixture above has no sources.yaml, so it only exercises the naive
# lowercase(ARG minus _VERSION) fallback: KERNEL_VERSION -> "kernel". The real
# sources.yaml maps KERNEL_VERSION to package "linux", and 105 other packages
# the same way. Without a fixture that has the file, the awk that parses
# `version_arg:` could stop matching and every cached package would silently
# revert to its fallback name in the shipped components.json with the suite
# still green.
WORK2="$(mktemp -d)"
trap 'rm -rf "$WORK" "$WORK2"' EXIT
mkdir -p "$WORK2/updatecli.d"
cp "$WORK/Dockerfile" "$WORK2/Dockerfile"
cp "$WORK/updatecli.d/kernel-and-boot.yaml" "$WORK2/updatecli.d/"
cat > "$WORK2/sources.yaml" <<'EOF'
packages:
  linux:
    version_arg: KERNEL_VERSION
    url: https://example.invalid/linux
  libiconv:
    version_arg: ICONV_VERSION
EOF

HADRON_MIN_VERSION_ARGS=1 HADRON_ROOT="$WORK2" "$GEN" --ref worktree --name components --out-dir "$WORK2" --format both --date "2026-06-25"

JSON2="$WORK2/components.json"
MD2="$WORK2/components.md"

# KERNEL_VERSION must resolve through sources.yaml to "linux", not to "kernel"
grep -q '"linux": "9.9.9"' "$JSON2"  || fail "KERNEL_VERSION did not map to sources.yaml name 'linux'"
grep -q '"kernel"' "$JSON2"          && fail "naive fallback name 'kernel' used despite sources.yaml mapping"
grep -q '| linux | 9.9.9 |' "$MD2"   || fail "MD missing linux row"

# The group still comes from updatecli.d, keyed on the ARG not the package name
grep -q '"Kernel And Boot"' "$JSON2"  || fail "group lost when name comes from sources.yaml"

# A package in sources.yaml with no matching ARG contributes no row: versions
# live only in the Dockerfile ARG defaults now.
grep -q 'libiconv' "$JSON2" && fail "libiconv has no ARG in the fixture and must not appear"

# An ARG with no sources.yaml entry still falls back to the naive name
grep -q '"mussel": "abc123"' "$JSON2" || fail "fallback name lost when sources.yaml is present"

# --- Guard: a ref whose versions never reached the ARG defaults ---
# Models the pre-committed-Dockerfile shape, where render.sh substituted
# versions straight into the FROM lines and left only a few ARG defaults. The
# generator must fail instead of writing a near-empty manifest, so that
# hack/gen-snapshot.sh skips the ref visibly rather than publishing it.
WORK3="$(mktemp -d)"
trap 'rm -rf "$WORK" "$WORK2" "$WORK3"' EXIT
mkdir -p "$WORK3/updatecli.d"
cat > "$WORK3/Dockerfile" <<'EOF'
ARG SBAT_DISTRO_VERSION=1
ARG MUSSEL_VERSION="abc123"
ARG BASH_VERSION=5.3
FROM ${SOURCES_REPO}/linux:7.1.7 AS linux
EOF

if HADRON_ROOT="$WORK3" "$GEN" --ref worktree --name thin --out-dir "$WORK3" \
     --format both --date "2026-06-25" >/dev/null 2>"$WORK3/err"; then
  fail "generator accepted a Dockerfile with 3 version ARGs"
fi
grep -q 'ARG \*_VERSION defaults' "$WORK3/err" || fail "guard did not explain why it refused"
grep -q 'worktree' "$WORK3/err"                || fail "guard did not name the ref"
[ -f "$WORK3/thin.json" ] && fail "guard wrote a manifest anyway"

echo "PASS: gen-components tests"
