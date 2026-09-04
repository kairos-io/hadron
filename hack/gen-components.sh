#!/bin/sh
# Generate a grouped component/version manifest from the Hadron Dockerfile.
set -eu

REF="worktree"
NAME="components"
OUT_DIR="."
FORMAT="both"
DATE="${SOURCE_DATE_EPOCH:-}"
SHIPPED=""
OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)     REF="$2";     shift 2 ;;
    --name)    NAME="$2";    shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --format)  FORMAT="$2";  shift 2 ;;
    --date)    DATE="$2";    shift 2 ;;
    --shipped)  SHIPPED="$2";  shift 2 ;;
    --override) OVERRIDE="$2"; shift 2 ;;
    -h|--help) echo "usage: gen-components.sh [--ref REF] [--name BASENAME] [--out-dir DIR] [--format json|md|flat|both] [--date STR] [--shipped \"STAGE...\"] [--override \"NAME=ARG...\"]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT="${HADRON_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"

# --- Resolve Dockerfile content + commit + display ref ---
# The committed Dockerfile carries every pinned version as an
# `ARG <VERSION_ARG>=<version>` default. Historical tags (before this
# repo committed the Dockerfile) only shipped Dockerfile.tmpl and used
# hack/render.sh to render it against sources.yaml; extract those from
# the ref and render into a tmpdir so per-tag snapshots keep working.
if [ "$REF" = "worktree" ] || [ -z "$REF" ]; then
  DOCKERFILE_CONTENT="$(cat "$ROOT/Dockerfile")"
  COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  REF_NAME="worktree"
else
  if git -C "$ROOT" show "${REF}:Dockerfile" >/dev/null 2>&1; then
    DOCKERFILE_CONTENT="$(git -C "$ROOT" show "${REF}:Dockerfile")"
  else
    REF_TMPDIR="$(mktemp -d)"
    git -C "$ROOT" archive "${REF}" Dockerfile.tmpl sources.yaml hack \
      | tar -x -C "$REF_TMPDIR"
    sh "$REF_TMPDIR/hack/render.sh" >/dev/null
    DOCKERFILE_CONTENT="$(cat "$REF_TMPDIR/Dockerfile")"
    rm -rf "$REF_TMPDIR"
  fi
  COMMIT="$(git -C "$ROOT" rev-parse --short "$REF" 2>/dev/null || echo unknown)"
  REF_NAME="$REF"
fi

GROUPS_TMP="$(mktemp)"
ROWS_TMP="$(mktemp)"
ARG2NAME_TMP="$(mktemp)"
trap 'rm -f "$GROUPS_TMP" "$ROWS_TMP" "$ARG2NAME_TMP"' EXIT

# --- ARG -> group map from updatecli.d ---
for f in "$ROOT"/updatecli.d/*.yaml; do
  [ -e "$f" ] || continue
  group="$(basename "$f" .yaml | tr '-' ' ' \
    | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1)) substr($i,2); print}')"
  grep -oE 'matcher: [A-Z0-9_]+_VERSION' "$f" 2>/dev/null \
    | sed -E 's/matcher: //' \
    | while IFS= read -r arg; do
        printf '%s\t%s\n' "$arg" "$group" >> "$GROUPS_TMP"
      done
done

# --- version_arg -> component name map from sources.yaml ---
# The component name in the emitted manifest is the package name
# (e.g. libiconv), which can diverge from the naïve
# lowercase(ARG_NAME[:-len("_VERSION")]) mapping (ICONV_VERSION -> iconv
# vs libiconv, KERNEL_VERSION -> kernel vs linux, JSONC_VERSION ->
# jsonc vs json-c). sources.yaml carries the pkg -> version_arg mapping
# for the 106 cached packages; build the reverse index for use below.
# Packages not in sources.yaml (bash, mussel, sbat) fall through to the
# naïve mapping.
if [ -f "$ROOT/sources.yaml" ]; then
  awk '
    /^  [a-z0-9._-]+:$/ { pkg = $1; sub(/:$/, "", pkg); next }
    /^    version_arg: [A-Z0-9_]+$/ { print $2 "\t" pkg }
  ' "$ROOT/sources.yaml" > "$ARG2NAME_TMP"
fi

# --- Emit rows from every ARG *_VERSION= in the Dockerfile ---
printf '%s\n' "$DOCKERFILE_CONTENT" \
  | grep -E '^ARG [A-Z0-9_]+_VERSION=' \
  | while IFS= read -r line; do
      arg="$(printf '%s' "$line" | sed -E 's/^ARG ([A-Z0-9_]+_VERSION)=.*/\1/')"
      val="$(printf '%s' "$line" | sed -E 's/^ARG [A-Z0-9_]+_VERSION=//; s/^"//; s/"$//; s/[[:space:]].*$//')"
      group="$(awk -F'\t' -v a="$arg" '$1==a{print $2; exit}' "$GROUPS_TMP")"
      [ -n "$group" ] || group="Other"
      name="$(awk -F'\t' -v a="$arg" '$1==a{print $2; exit}' "$ARG2NAME_TMP")"
      if [ -z "$name" ]; then
        name="$(printf '%s' "$arg" | sed -E 's/_VERSION$//' | tr 'A-Z_' 'a-z-')"
      fi
      printf '%s\t%s\t%s\n' "$group" "$name" "$val" >> "$ROWS_TMP"
    done

# Stable ordering: group, then component
TAB="$(printf '\t')"
sort -t"$TAB" -k1,1 -k2,2 "$ROWS_TMP" -o "$ROWS_TMP"

# --- Optional: restrict to components actually shipped in given merge stage(s) ---
# A component "ships" in a stage if that stage has a `COPY --from=<build-stage>`
# whose name maps to it. Build-stage names are normalized the same way as ARG
# names (lowercase, `_`->`-`), with a few suffix rules for two-pass / variant
# stages (`pam-systemd`->`pam`, `grub-efi`->`grub`, `kernel-modules`->`kernel`).
if [ -n "$SHIPPED" ]; then
  ALLOWED_TMP="$(mktemp)"
  trap 'rm -f "$GROUPS_TMP" "$ROWS_TMP" "$ARG2NAME_TMP" "$ALLOWED_TMP"' EXIT
  for st in $SHIPPED; do
    printf '%s\n' "$DOCKERFILE_CONTENT" | awk -v st="$st" '
      $0 ~ "^FROM .* AS "st"$" { inb=1; next }
      inb && /^FROM / { inb=0 }
      inb && /^[ \t]*COPY --from=/ {
        line=$0; sub(/.*--from=/, "", line); sub(/[ \t].*/, "", line); print line
      }'
  done \
    | tr 'A-Z_' 'a-z-' \
    | sed -E 's/-systemd$//; s/-final$//; s/-build$//; s/-efi$//; s/-bios$//; s/-stage0$//; s/^kernel-modules$/kernel/' \
    | sed -E 's/^libseccomp$/seccomp/; s/^xz$/xzutils/; s/^openscsi$/open-scsi/' \
    | sort -u > "$ALLOWED_TMP"

  # Keep only rows whose component name is in the allowed (shipped) set.
  FILTERED_TMP="$(mktemp)"
  awk -F'\t' 'NR==FNR { a[$1]=1; next } ($2 in a)' "$ALLOWED_TMP" "$ROWS_TMP" > "$FILTERED_TMP"
  mv "$FILTERED_TMP" "$ROWS_TMP"

  # Log shipped names that had no matching *_VERSION ARG (mapping gaps / inter-stage refs).
  awk -F'\t' 'NR==FNR { have[$2]=1; next } !($1 in have) { print $1 }' "$ROWS_TMP" "$ALLOWED_TMP" \
    | while IFS= read -r miss; do
        echo "note: shipped stage ref '$miss' has no *_VERSION ARG (skipped)" >&2
      done
fi

# --- Version overrides: "component=ARG_NAME" pairs ---
# Sets a shipped component's version from a different ARG while keeping its
# on-disk name. Models `FROM <name>-${VAR} AS <name>` alias stages that swap the
# built version per build arg — e.g. `openssl=OPENSSL_FIPS_VERSION` in fips
# builds, where the shipped `openssl` is built from the FIPS sources (3.1.2).
if [ -n "$OVERRIDE" ]; then
  for ov in $OVERRIDE; do
    cname="${ov%%=*}"
    argn="${ov#*=}"
    val="$(printf '%s\n' "$DOCKERFILE_CONTENT" | grep -E "^ARG ${argn}=" | head -1 \
      | sed -E "s/^ARG ${argn}=//; s/^\"//; s/\"\$//; s/[[:space:]].*\$//")"
    if [ -z "$val" ]; then
      echo "note: --override '$ov': ARG $argn not found, skipping" >&2
      continue
    fi
    awk -F'\t' -v c="$cname" -v v="$val" 'BEGIN { OFS="\t" } $2==c { $3=v } { print }' \
      "$ROWS_TMP" > "$ROWS_TMP.ov" && mv "$ROWS_TMP.ov" "$ROWS_TMP"
  done
fi

gen_json() {
  awk -F'\t' -v ref="$REF_NAME" -v commit="$COMMIT" -v date="$DATE" '
    BEGIN { printf "{\n  \"ref\": \"%s\",\n  \"commit\": \"%s\",\n  \"generated\": \"%s\",\n  \"groups\": {\n", ref, commit, date }
    {
      if ($1 != curgroup) {
        if (curgroup != "") printf "\n    },\n"
        printf "    \"%s\": {\n", $1
        curgroup=$1; first=1
      }
      if (!first) printf ",\n"
      printf "      \"%s\": \"%s\"", $2, $3
      first=0
    }
    END { if (curgroup != "") printf "\n    }\n"; printf "  }\n}\n" }
  ' "$ROWS_TMP"
}

gen_md() {
  printf '# Hadron components — %s\n\n' "$REF_NAME"
  printf 'Commit: `%s`\n\n' "$COMMIT"
  awk -F'\t' '
    {
      if ($1 != curgroup) {
        if (curgroup != "") printf "\n"
        printf "### %s\n\n| Component | Version |\n|-----------|---------|\n", $1
        curgroup=$1
      }
      printf "| %s | %s |\n", $2, $3
    }
  ' "$ROWS_TMP"
}

# Flat `{ "name": "version", ... }` map, sorted by component name. Intended for
# machine consumption (the in-image manifest) — no groups, no metadata.
gen_flat() {
  sort -t"$TAB" -k2,2 "$ROWS_TMP" | awk -F'\t' '
    BEGIN { print "{"; first=1 }
    {
      if (!first) printf ",\n"
      printf "  \"%s\": \"%s\"", $2, $3
      first=0
    }
    END { if (first) print "}"; else printf "\n}\n" }
  '
}

mkdir -p "$OUT_DIR"
case "$FORMAT" in
  json) gen_json > "$OUT_DIR/$NAME.json" ;;
  md)   gen_md   > "$OUT_DIR/$NAME.md" ;;
  flat) gen_flat > "$OUT_DIR/$NAME.json" ;;
  both) gen_json > "$OUT_DIR/$NAME.json"; gen_md > "$OUT_DIR/$NAME.md" ;;
  *) echo "unknown format: $FORMAT" >&2; exit 2 ;;
esac
