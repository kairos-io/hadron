#!/usr/bin/env bash
# Compare the full Hadron images built for this PR against the published
# ":main" baseline and emit a Markdown size report to stdout.
#
# Used by the "image-size-report" job in PR_amd64.yml so reviewers can see how
# much a change (e.g. adding a new dependency) grows the shipped images.
#
# Usage: image-size-report.sh <pr-sha> <repo-slug>
#   <pr-sha>    git SHA the PR images were tagged with (github.sha)
#   <repo-slug> owner/name used for the ghcr baseline (github.repository)
#
# Sizes are uncompressed image sizes (docker image inspect .Size). The
# per-directory and per-file breakdowns come from `find`/`du` inside each
# rootfs, so reviewers can attribute the delta to concrete paths. amd64 only.
#
# Note on interpretation: the baseline is the rolling `:main` image, which is
# rebuilt from scratch, while the PR image is built largely from cache. A small
# nonzero delta on a logically no-op PR therefore usually reflects baseline
# drift or build non-reproducibility (e.g. regenerated caches/indexes), not the
# PR's own change. The per-file breakdown below makes that visible: if the delta
# is concentrated in generated files (ld.so.cache, *.dep, __pycache__, ...) it
# is almost certainly noise rather than a real size impact.
set -euo pipefail
# Stable, locale-independent byte sorting so the path merges below are correct
# regardless of the runner locale. (LC_ALL and human() come from the lib.)

# Shared variant list + human() helper, kept in sync with size-history.sh.
source "$(dirname "${BASH_SOURCE[0]}")/size-history-lib.sh"

SHA="${1:?usage: image-size-report.sh <pr-sha> <repo-slug>}"
REPO="${2:?usage: image-size-report.sh <pr-sha> <repo-slug>}"

# How many individual files to show in the per-image "top file changes" table.
TOP_FILES="${TOP_FILES:-15}"

# Build the per-variant comparison table from the shared SIZE_VARIANTS list:
#   name | PR image (this build, pushed to ttl.sh) | main baseline (ghcr.io)
# PR bios tags carry a -amd64 suffix; trusted tags do not (see PR_amd64.yml).
VARIANTS=()
for _v in "${SIZE_VARIANTS[@]}"; do
  _name="${_v%%|*}"
  case "$_name" in
  *-trusted) _pr="ttl.sh/${_name}-${SHA}:24h" ;;    # trusted tags: SHA in name, TTL as tag
    *)         _pr="ttl.sh/${_name}-amd64:${SHA}" ;;  # bios tags: -amd64 suffix
  esac
  _main="$(size_variant_ghcr "$REPO" "$_name")"
  VARIANTS+=("${_name}|${_pr}|${_main}")
done
unset _v _name _pr _main

# Emit "<bytes>\t<path>" for every regular file in the image rootfs, staying on
# the rootfs device so /proc, /sys and /dev are skipped. Sorted by path so the
# awk merge below can pair two images deterministically. Returns nothing if the
# image has no usable shell (the size table still works without this).
rootfs_files() {
  docker run --rm --entrypoint sh "$1" -c \
    'find / -xdev -type f -printf "%s\t%p\n" 2>/dev/null' 2>/dev/null \
    | sort -t"$(printf '\t')" -k2 || true
}

# Given two "<bytes>\t<path>" listings (main, then PR), print the per-file delta
# as "<path>\t<main_bytes>\t<pr_bytes>\t<delta>" for every path whose size
# changed (including added/removed files). Robust against files present in only
# one image.
file_diff() {
  awk -F'\t' '
    FNR==NR { m[$2]=$1; next }
    {
      p[$2]=$1
      base=($2 in m)?m[$2]:0
      if ($1!=base)
        print $2 "\t" base "\t" $1 "\t" ($1-base)
    }
    END {
      # Files that existed in main but are gone from the PR image.
      for (f in m) if (!(f in p)) print f "\t" m[f] "\t0\t" (-m[f])
    }
  ' "$1" "$2"
}

# Sort "<...>\t<...>\t<...>\t<delta>" rows by absolute value of the trailing
# delta field, descending.
sort_by_abs_delta() {
  awk -F'\t' '{v=$NF; if(v<0)v=-v; printf "%d\t%s\n", v, $0}' \
    | sort -t"$(printf '\t')" -k1 -nr | cut -f2-
}

summary_rows=""
details=""

for v in "${VARIANTS[@]}"; do
  IFS='|' read -r name pr_img main_img <<<"$v"

  # Baseline may legitimately not exist yet (brand new image variant).
  if ! docker pull -q "$main_img" >/dev/null 2>&1; then
    summary_rows+="| \`${name}\` | _not on main yet_ | — | — |"$'\n'
    continue
  fi
  docker pull -q "$pr_img" >/dev/null

  main_sz=$(docker image inspect "$main_img" --format '{{.Size}}')
  pr_sz=$(docker image inspect "$pr_img" --format '{{.Size}}')
  delta=$((pr_sz - main_sz))
  pct=$(awk -v d="$delta" -v m="$main_sz" 'BEGIN{printf "%+.2f", (m>0)?(d/m*100):0}')
  sgn='+'; [ "$delta" -lt 0 ] && sgn='-'
  summary_rows+="| \`${name}\` | $(human "$main_sz") | $(human "$pr_sz") | ${sgn}$(human "$delta") (${pct}%) |"$'\n'

  # Per-file delta, computed from a deterministic merge of both rootfs listings.
  fdiff=$(file_diff <(rootfs_files "$main_img") <(rootfs_files "$pr_img") || true)
  [ -z "$fdiff" ] && continue

  block="<details><summary><code>${name}</code>: where the bytes changed</summary>"$'\n\n'

  # Per top-level directory: aggregate the file deltas by their first path
  # component, then sort by absolute delta so the dominant contributor leads.
  dir_rows=$(awk -F'\t' '
      { d=$1; sub(/^\//,"",d); sub(/\/.*/,"",d); if (d=="") d="(root files)";
        m[d]+=$2; p[d]+=$3 }
      END { for (k in m) printf "%s\t%d\t%d\t%d\n", k, m[k], p[k], p[k]-m[k] }
    ' <<<"$fdiff" | sort_by_abs_delta)
  if [ -n "$dir_rows" ]; then
    block+="**By top-level directory**"$'\n\n'
    block+="| dir | \`main\` | PR | Δ |"$'\n'"|---|--:|--:|--:|"$'\n'
    while IFS=$'\t' read -r dir m p d; do
      [ -z "$dir" ] && continue
      s='+'; [ "$d" -lt 0 ] && s='-'
      block+="| \`${dir}\` | $(human "$m") | $(human "$p") | ${s}$(human "$d") |"$'\n'
    done <<<"$dir_rows"
    block+=$'\n'
  fi

  # Top individual files by absolute delta: this is what pinpoints whether the
  # change is a real new/grown binary or just a regenerated cache/index.
  file_rows=$(printf '%s\n' "$fdiff" | sort_by_abs_delta | head -n "$TOP_FILES")
  if [ -n "$file_rows" ]; then
    block+="**Top ${TOP_FILES} files by |Δ|**"$'\n\n'
    block+="| file | \`main\` | PR | Δ |"$'\n'"|---|--:|--:|--:|"$'\n'
    while IFS=$'\t' read -r path m p d; do
      [ -z "$path" ] && continue
      s='+'; [ "$d" -lt 0 ] && s='-'
      block+="| \`${path}\` | $(human "$m") | $(human "$p") | ${s}$(human "$d") |"$'\n'
    done <<<"$file_rows"
    block+=$'\n'
  fi

  block+="</details>"$'\n\n'
  details+="$block"
done

printf '## 📦 Image size report — PR vs `main` (amd64)\n\n'
printf '| Image | `main` | PR | Δ |\n|---|--:|--:|--:|\n'
printf '%s\n' "$summary_rows"
printf '%b' "$details"
printf '> ℹ️ Baseline is the rolling `:main` image (rebuilt from scratch); the PR\n'
printf '> image is built mostly from cache. A small nonzero Δ on a logically no-op\n'
printf '> change usually reflects baseline drift or build non-reproducibility\n'
printf '> (regenerated caches/indexes), not the PR itself. Check the per-file\n'
printf '> breakdown: a Δ concentrated in generated files (e.g. `ld.so.cache`,\n'
printf '> `*.dep`, `__pycache__`) is noise rather than a real size impact.\n\n'
printf '<sub>Uncompressed image sizes (`docker image inspect .Size`). Baseline = current `:main`. Generated by `.github/scripts/image-size-report.sh`.</sub>\n'
