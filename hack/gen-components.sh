#!/bin/sh
# Generate a grouped component/version manifest from the Hadron Dockerfile.
set -eu

REF="worktree"
NAME="components"
OUT_DIR="."
FORMAT="both"
DATE="${SOURCE_DATE_EPOCH:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)     REF="$2";     shift 2 ;;
    --name)    NAME="$2";    shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --format)  FORMAT="$2";  shift 2 ;;
    --date)    DATE="$2";    shift 2 ;;
    -h|--help) echo "usage: gen-components.sh [--ref REF] [--name BASENAME] [--out-dir DIR] [--format json|md|both] [--date STR]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT="${HADRON_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"

# --- Resolve Dockerfile content + commit + display ref ---
if [ "$REF" = "worktree" ] || [ -z "$REF" ]; then
  DOCKERFILE_CONTENT="$(cat "$ROOT/Dockerfile")"
  COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  REF_NAME="worktree"
else
  DOCKERFILE_CONTENT="$(git -C "$ROOT" show "${REF}:Dockerfile")"
  COMMIT="$(git -C "$ROOT" rev-parse --short "$REF" 2>/dev/null || echo unknown)"
  REF_NAME="$REF"
fi

GROUPS_TMP="$(mktemp)"
ROWS_TMP="$(mktemp)"
trap 'rm -f "$GROUPS_TMP" "$ROWS_TMP"' EXIT

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

# --- Parse ARG *_VERSION= lines into GROUP<TAB>NAME<TAB>VERSION rows ---
printf '%s\n' "$DOCKERFILE_CONTENT" \
  | grep -E '^ARG [A-Z0-9_]+_VERSION=' \
  | while IFS= read -r line; do
      arg="$(printf '%s' "$line" | sed -E 's/^ARG ([A-Z0-9_]+_VERSION)=.*/\1/')"
      val="$(printf '%s' "$line" | sed -E 's/^ARG [A-Z0-9_]+_VERSION=//; s/^"//; s/"$//; s/[[:space:]].*$//')"
      group="$(awk -F'\t' -v a="$arg" '$1==a{print $2; exit}' "$GROUPS_TMP")"
      [ -n "$group" ] || group="Other"
      name="$(printf '%s' "$arg" | sed -E 's/_VERSION$//' | tr 'A-Z_' 'a-z-')"
      printf '%s\t%s\t%s\n' "$group" "$name" "$val" >> "$ROWS_TMP"
    done

# Stable ordering: group, then component
TAB="$(printf '\t')"
sort -t"$TAB" -k1,1 -k2,2 "$ROWS_TMP" -o "$ROWS_TMP"

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

mkdir -p "$OUT_DIR"
case "$FORMAT" in
  json) gen_json > "$OUT_DIR/$NAME.json" ;;
  md)   gen_md   > "$OUT_DIR/$NAME.md" ;;
  both) gen_json > "$OUT_DIR/$NAME.json"; gen_md > "$OUT_DIR/$NAME.md" ;;
  *) echo "unknown format: $FORMAT" >&2; exit 2 ;;
esac
