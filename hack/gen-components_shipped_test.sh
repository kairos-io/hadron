#!/bin/sh
# Self-contained, no-network test for the --shipped / --format flat
# per-image filtering in hack/gen-components.sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GEN="$SCRIPT_DIR/gen-components.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/updatecli.d"
# Fixture: 4 versioned components, two merge stages.
# - stage2-merge ships curl + openssl (the minimal container set)
# - full-image-merge-base inherits stage2-merge, adds kernel + pam (via the
#   two-pass `pam-systemd` build stage, whose name must strip to `pam`)
cat > "$WORK/Dockerfile" <<'EOF'
ARG CURL_VERSION=8.20.0
ARG OPENSSL_VERSION=3.6.3
ARG KERNEL_VERSION=7.1.1
ARG PAM_VERSION=1.7.0
ARG SECCOMP_VERSION=2.6.0
ARG XZUTILS_VERSION=5.8.3
ARG OPEN_SCSI_VERSION=2.1.11
ARG OPENSSL_FIPS_VERSION=3.1.2

ARG PAXUTILS_VERSION=1.3.10

FROM scratch AS stage2-merge
COPY --from=curl /curl /curl
RUN rsync /curl/. /skeleton/
COPY --from=openssl /openssl /openssl
# commented-out COPY must NOT count as shipped
#COPY --from=paxutils /paxutils /paxutils

FROM scratch AS full-image-merge-base
COPY --from=stage2-merge /skeleton /
COPY --from=kernel /kernel/ /skeleton/boot/
COPY --from=pam-systemd /pam /pam
COPY --from=libseccomp /libseccomp /libseccomp
COPY --from=xz /xz /xz
COPY --from=openscsi /openscsi /openscsi
EOF

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- container manifest: only stage2-merge's shipped packages ---
HADRON_ROOT="$WORK" "$GEN" --shipped "stage2-merge" --format flat \
  --name container --out-dir "$WORK"

CJSON="$WORK/container.json"
[ -f "$CJSON" ] || fail "container.json not created"
grep -q '"curl": "8.20.0"'    "$CJSON" || fail "container missing curl"
grep -q '"openssl": "3.6.3"'  "$CJSON" || fail "container missing openssl"
grep -q 'kernel'   "$CJSON" && fail "container must NOT list kernel (not shipped there)"
grep -q 'pam'      "$CJSON" && fail "container must NOT list pam (not shipped there)"
grep -q 'paxutils' "$CJSON" && fail "container must NOT list paxutils (its COPY is commented out)"

# --- full-image manifest: union of both merge stages, -systemd suffix stripped ---
HADRON_ROOT="$WORK" "$GEN" --shipped "stage2-merge full-image-merge-base" --format flat \
  --name full-image --out-dir "$WORK"

FJSON="$WORK/full-image.json"
[ -f "$FJSON" ] || fail "full-image.json not created"
grep -q '"curl": "8.20.0"'   "$FJSON" || fail "full-image missing curl"
grep -q '"openssl": "3.6.3"' "$FJSON" || fail "full-image missing openssl"
grep -q '"kernel": "7.1.1"'  "$FJSON" || fail "full-image missing kernel"
grep -q '"pam": "1.7.0"'     "$FJSON" || fail "full-image missing pam (pam-systemd should map to pam)"
# build-stage name != ARG name: aliases must bridge them
grep -q '"seccomp": "2.6.0"'    "$FJSON" || fail "libseccomp should map to seccomp"
grep -q '"xzutils": "5.8.3"'    "$FJSON" || fail "xz should map to xzutils"
grep -q '"open-scsi": "2.1.11"' "$FJSON" || fail "openscsi should map to open-scsi"

# --- --override sets a shipped component's version from a different ARG, keeping
#     its on-disk name. Models the `FROM openssl-${FIPS} AS openssl` alias: in
#     fips builds the `openssl` that ships is built from OPENSSL_FIPS_VERSION
#     (3.1.2), not OPENSSL_VERSION (3.6.3) — one entry, named openssl. ---
HADRON_ROOT="$WORK" "$GEN" --shipped "stage2-merge" --override "openssl=OPENSSL_FIPS_VERSION" \
  --format flat --name ovr --out-dir "$WORK"

OJSON="$WORK/ovr.json"
[ -f "$OJSON" ] || fail "ovr.json not created"
grep -q '"openssl": "3.1.2"' "$OJSON" || fail "--override did not set openssl to the FIPS version"
grep -q '"openssl": "3.6.3"' "$OJSON" && fail "--override left the stale non-FIPS openssl version"
grep -q 'openssl-fips'       "$OJSON" && fail "--override must not emit a separate openssl-fips entry"
grep -q '"curl": "8.20.0"'   "$OJSON" || fail "--override disturbed unrelated components"

# without --override, openssl keeps its default (non-fips) version
HADRON_ROOT="$WORK" "$GEN" --shipped "stage2-merge" --format flat --name noovr --out-dir "$WORK"
grep -q '"openssl": "3.6.3"' "$WORK/noovr.json" || fail "default openssl version should be 3.6.3"

# --- flat JSON is a valid, flat object if python3 is available ---
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert all(isinstance(v,str) for v in d.values())' "$FJSON" \
    || fail "full-image.json is not a valid flat string map"
fi

echo "PASS: gen-components shipped/flat tests"
