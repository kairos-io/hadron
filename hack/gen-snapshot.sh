#!/bin/sh
# Generate per-ref component manifests + an index into docs/static/components/.
set -eu

ROOT="${HADRON_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
OUT="$ROOT/docs/static/components"
GEN="$ROOT/hack/gen-components.sh"
TEMPLATE="$ROOT/hack/components-template.html"
DATE="${SOURCE_DATE_EPOCH:-}"

rm -rf "$OUT"
mkdir -p "$OUT"

# Refs: main first, then every v* tag (version-sorted, newest first)
REFS="main"
TAGS="$(git -C "$ROOT" tag -l 'v*' --sort=-version:refname || true)"

# main snapshot (use current checkout's Dockerfile if HEAD is main)
"$GEN" --ref main --name main --out-dir "$OUT" --format both --date "$DATE" \
  || "$GEN" --ref worktree --name main --out-dir "$OUT" --format both --date "$DATE"

for tag in $TAGS; do
  # Skip (don't abort under set -e) any tag whose manifest can't be generated.
  if "$GEN" --ref "$tag" --name "$tag" --out-dir "$OUT" --format both --date "$DATE"; then
    REFS="$REFS $tag"
  else
    echo "warning: skipping tag $tag (could not generate manifest)" >&2
  fi
done

# index.json
{
  printf '['
  sep=''
  for r in $REFS; do printf '%s"%s"' "$sep" "$r"; sep=', '; done
  printf ']\n'
} > "$OUT/index.json"


# index.html — self-contained page with tabs (Components / Firmware / Layers).
# Template lives at hack/components-template.html so it can be iterated on
# independently of this generator. Firmware + layers JSON is fetched by the
# sibling script hack/gen-external.sh (run after this one).
cp "$TEMPLATE" "$OUT/index.html"
