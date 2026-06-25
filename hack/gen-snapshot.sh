#!/bin/sh
# Generate per-ref component manifests + an index into docs/static/components/.
set -eu

ROOT="${HADRON_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
OUT="$ROOT/docs/static/components"
GEN="$ROOT/hack/gen-components.sh"
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
  "$GEN" --ref "$tag" --name "$tag" --out-dir "$OUT" --format both --date "$DATE"
  REFS="$REFS $tag"
done

# index.json
{
  printf '['
  sep=''
  for r in $REFS; do printf '%s"%s"' "$sep" "$r"; sep=', '; done
  printf ']\n'
} > "$OUT/index.json"

# index.html (lightweight, no framework)
{
  echo '<!doctype html><html><head><meta charset="utf-8">'
  echo '<title>Hadron component manifests</title>'
  echo '<style>body{font-family:system-ui,sans-serif;max-width:48rem;margin:2rem auto;padding:0 1rem}li{margin:.3rem 0}</style>'
  echo '</head><body><h1>Hadron component manifests</h1>'
  echo '<p>Component/version snapshot for each Hadron build.</p><ul>'
  for r in $REFS; do
    printf '<li><strong>%s</strong> — <a href="./%s.md">markdown</a> · <a href="./%s.json">json</a></li>\n' "$r" "$r" "$r"
  done
  echo '</ul></body></html>'
} > "$OUT/index.html"
