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
HADRON_ROOT="$WORK" "$GEN" --ref worktree --name components --out-dir "$WORK" --format both --date "2026-06-25"

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

echo "PASS: gen-components tests"
