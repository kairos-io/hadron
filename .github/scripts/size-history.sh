#!/usr/bin/env bash
# Track shipped image sizes over time, one data point per merge to main.
#
# Unlike the per-PR report (image-size-report.sh), which compares a PR against
# the rolling :main baseline and writes an ephemeral step summary / PR comment,
# this script maintains a *durable* time series: a CSV with one row per merge
# (sha, date, and the uncompressed size of each shipped variant) plus a
# regenerated Markdown table and a self-contained SVG line chart. The CSV is the
# source of truth and is meant to be committed to a long-lived branch so the
# history survives log and step-summary purging.
#
# Sizes are uncompressed image sizes (docker image inspect .Size) of the :main
# multi-arch manifest, measured on the host platform of the runner (amd64),
# matching image-size-report.sh.
#
# Usage:
#   size-history.sh record <csv> <sha> <repo-slug>
#       Pull each variant's :main image, read its size, append a row to <csv>
#       (creating it with a header if needed) and print a one-merge summary
#       (with deltas vs the previous row) to stdout.
#
#   size-history.sh render <csv> <out-dir>
#       (Re)generate <out-dir>/SIZE_HISTORY.md and <out-dir>/size-history.svg
#       from <csv>. Pure function of the CSV; needs no network.
#
#   size-history.sh all <csv> <sha> <repo-slug> <out-dir>
#       record then render; prints the per-merge summary to stdout.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/size-history-lib.sh"

# How many of the most recent merges to show in the rendered Markdown table.
HISTORY_TABLE_ROWS="${HISTORY_TABLE_ROWS:-20}"

# csv_header: the canonical CSV header line for the tracked variants.
csv_header() {
  printf 'sha,date'
  local n
  while IFS= read -r n; do printf ',%s' "$n"; done < <(size_variant_names)
  printf '\n'
}

# image_size_bytes <image-ref>: pull the image and print its uncompressed size
# in bytes, or nothing (empty) if the image cannot be pulled (e.g. a brand new
# variant not yet published to :main).
image_size_bytes() {
  local img="$1"
  if docker pull -q "$img" >/dev/null 2>&1; then
    docker image inspect "$img" --format '{{.Size}}' 2>/dev/null || true
  fi
}

# record <csv> <sha> <repo>: append one row for the current merge.
record() {
  local csv="$1" sha="$2" repo="$3"
  local date name img sz row prev
  date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Create the file with a header on first use.
  if [ ! -s "$csv" ]; then
    csv_header >"$csv"
  fi

  # Remember the previous row (for the delta summary) before we append.
  prev="$(tail -n +2 "$csv" | tail -n 1 || true)"

  row="${sha},${date}"
  while IFS= read -r name; do
    img="$(size_variant_ghcr "$repo" "$name")"
    sz="$(image_size_bytes "$img")"
    row+=",${sz}"
  done < <(size_variant_names)
  printf '%s\n' "$row" >>"$csv"

  # Per-merge summary with deltas vs the previous recorded merge.
  printf '## 📈 Image size history — merge `%s`\n\n' "${sha:0:12}"
  printf '| Image | size | Δ vs previous merge |\n|---|--:|--:|\n'
  local i=3 cur base delta sgn pct
  while IFS= read -r name; do
    cur="$(printf '%s\n' "$row" | cut -d, -f"$i")"
    base=""
    [ -n "$prev" ] && base="$(printf '%s\n' "$prev" | cut -d, -f"$i")"
    if [ -z "$cur" ]; then
      printf '| `%s` | _not on main yet_ | — |\n' "$name"
    elif [ -z "$base" ]; then
      printf '| `%s` | %s | _no baseline_ |\n' "$name" "$(human "$cur")"
    else
      delta=$((cur - base))
      sgn='+'; [ "$delta" -lt 0 ] && sgn='-'
      pct=$(awk -v d="$delta" -v m="$base" 'BEGIN{printf "%+.2f", (m>0)?(d/m*100):0}')
      printf '| `%s` | %s | %s%s (%s%%) |\n' \
        "$name" "$(human "$cur")" "$sgn" "$(human "$delta")" "$pct"
    fi
    i=$((i + 1))
  done < <(size_variant_names)
  printf '\n'
}

# svg <csv> <out>: render a self-contained multi-line SVG chart of every
# variant's size over the recorded merges. No external dependencies/services.
svg() {
  local csv="$1" out="$2"
  awk -F',' '
    NR==1 { for (c=3;c<=NF;c++) names[c]=$c; ncol=NF; next }
    {
      n++
      for (c=3;c<=ncol;c++) {
        v[n,c]=$c
        if ($c!="") {
          if (!seen[c] || $c<min[c]) min[c]=$c
          if (!seen[c] || $c>max[c]) max[c]=$c
          seen[c]=1
        }
      }
    }
    END {
      W=760; H=300; L=70; R=160; T=20; B=40
      pw=W-L-R; ph=H-T-B
      # Global y-range across all variants so lines share one scale.
      gmin=""; gmax=""
      for (c=3;c<=ncol;c++) if (seen[c]) {
        if (gmin==""||min[c]<gmin) gmin=min[c]
        if (gmax==""||max[c]>gmax) gmax=max[c]
      }
      if (gmin=="") { gmin=0; gmax=1 }
      if (gmax==gmin) gmax=gmin+1
      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" font-family=\"sans-serif\" font-size=\"11\">\n", W, H, W, H
      printf "<rect width=\"%d\" height=\"%d\" fill=\"#ffffff\"/>\n", W, H
      # Axes.
      printf "<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"#888\"/>\n", L, T, L, T+ph
      printf "<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"#888\"/>\n", L, T+ph, L+pw, T+ph
      # Y gridlines / labels (GiB).
      for (g=0;g<=4;g++) {
        yy=T+ph-(g/4)*ph
        val=gmin+(g/4)*(gmax-gmin)
        printf "<line x1=\"%d\" y1=\"%.1f\" x2=\"%d\" y2=\"%.1f\" stroke=\"#eee\"/>\n", L, yy, L+pw, yy
        printf "<text x=\"%d\" y=\"%.1f\" text-anchor=\"end\" fill=\"#555\">%.2f GiB</text>\n", L-6, yy+3, val/1073741824
      }
      colors[3]="#1f77b4"; colors[4]="#ff7f0e"; colors[5]="#2ca02c"; colors[6]="#d62728"
      colors[7]="#9467bd"; colors[8]="#8c564b"
      xstep=(n>1)?pw/(n-1):0
      ly=T
      for (c=3;c<=ncol;c++) {
        if (!seen[c]) continue
        col=(c in colors)?colors[c]:"#333"
        pts=""; first=1
        for (i=1;i<=n;i++) {
          if (v[i,c]=="") continue
          x=L+(i-1)*xstep
          y=T+ph-((v[i,c]-gmin)/(gmax-gmin))*ph
          pts=pts sprintf("%.1f,%.1f ", x, y)
        }
        if (pts!="") printf "<polyline fill=\"none\" stroke=\"%s\" stroke-width=\"2\" points=\"%s\"/>\n", col, pts
        # Legend.
        printf "<rect x=\"%d\" y=\"%d\" width=\"10\" height=\"10\" fill=\"%s\"/>\n", L+pw+14, ly, col
        printf "<text x=\"%d\" y=\"%d\" fill=\"#333\">%s</text>\n", L+pw+28, ly+9, names[c]
        ly+=18
      }
      printf "<text x=\"%d\" y=\"%d\" text-anchor=\"middle\" fill=\"#555\">merges over time (oldest → newest)</text>\n", L+pw/2, H-10
      print "</svg>"
    }
  ' "$csv" >"$out"
}

# render <csv> <out-dir>: regenerate SIZE_HISTORY.md and size-history.svg.
render() {
  local csv="$1" out="$2"
  mkdir -p "$out"
  svg "$csv" "$out/size-history.svg"

  local md="$out/SIZE_HISTORY.md"
  {
    printf '# 📦 Image size history\n\n'
    printf 'Uncompressed size (`docker image inspect .Size`, amd64) of each shipped\n'
    printf '`:main` image, recorded once per merge. The CSV (`size-history.csv`) is the\n'
    printf 'source of truth; this page and the chart are regenerated from it by\n'
    printf '`.github/scripts/size-history.sh`.\n\n'
    printf '![image size history](./size-history.svg)\n\n'

    # Header row: date, sha, then each variant.
    printf '## Most recent %s merges\n\n' "$HISTORY_TABLE_ROWS"
    printf '| date | sha |'
    local name
    while IFS= read -r name; do printf ' %s |' "$name"; done < <(size_variant_names)
    printf '\n|---|---|'
    while IFS= read -r name; do printf -- '--:|'; done < <(size_variant_names)
    printf '\n'

    # Last N rows, newest first, with per-cell delta vs the previous merge.
    local ncols nvars
    nvars="$(size_variant_names | wc -l)"
    ncols=$((2 + nvars))
    tail -n +2 "$csv" | tail -n "$HISTORY_TABLE_ROWS" | tac | while IFS=',' read -r -a cur; do
      local sha="${cur[0]}" date="${cur[1]}"
      # Find this row's predecessor for deltas.
      local prevline
      prevline="$(grep -n -F "${sha}," "$csv" | head -n1 | cut -d: -f1)"
      local base_row=""
      if [ -n "$prevline" ] && [ "$prevline" -gt 2 ]; then
        base_row="$(sed -n "$((prevline - 1))p" "$csv")"
      fi
      printf '| %s | `%s` |' "${date%T*}" "${sha:0:12}"
      local i=2 c base delta sgn
      while [ "$i" -lt "$ncols" ]; do
        c="${cur[$i]:-}"
        base=""
        [ -n "$base_row" ] && base="$(printf '%s\n' "$base_row" | cut -d, -f"$((i + 1))")"
        if [ -z "$c" ]; then
          printf ' n/a |'
        elif [ -z "$base" ]; then
          printf ' %s |' "$(human "$c")"
        else
          delta=$((c - base))
          sgn='+'; [ "$delta" -lt 0 ] && sgn='-'
          printf ' %s (%s%s) |' "$(human "$c")" "$sgn" "$(human "$delta")"
        fi
        i=$((i + 1))
      done
      printf '\n'
    done
    printf '\n'
  } >"$md"
}

main() {
  local cmd="${1:?usage: size-history.sh <record|render|all> ...}"
  shift
  case "$cmd" in
    record) record "$@" ;;
    render) render "$@" ;;
    all)
      local csv="$1" sha="$2" repo="$3" out="$4"
      record "$csv" "$sha" "$repo"
      render "$csv" "$out"
      ;;
    *) echo "unknown command: $cmd" >&2; exit 2 ;;
  esac
}

main "$@"
