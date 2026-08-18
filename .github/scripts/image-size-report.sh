#!/usr/bin/env bash
# Compare the full Hadron images built for this PR against the published
# ":main" baseline and emit a Markdown size report to stdout.
#
# Used by the "image-size-report" job in PR_multiarch.yml so reviewers can see how
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

# Reporting baseline: deltas smaller than this are noise, not signal. A variant
# whose |Δ| is below NEGLIGIBLE_BYTES *and* below NEGLIGIBLE_PCT of the baseline
# is reported as "≈ no change" with no per-file breakdown, so a ~1 KiB drift on a
# 200 MiB image (≈0.0005%) doesn't clutter the PR. Per-file rows below
# FILE_MIN_DELTA are dropped from the breakdown for the same reason.
NEGLIGIBLE_BYTES="${NEGLIGIBLE_BYTES:-262144}"  # 256 KiB
NEGLIGIBLE_PCT="${NEGLIGIBLE_PCT:-0.1}"         # 0.10%
FILE_MIN_DELTA="${FILE_MIN_DELTA:-4096}"        # 4 KiB

# Build the per-variant comparison table from the shared SIZE_VARIANTS list:
#   name | PR image (this build, already docker-loaded locally by the workflow
#         from a tarball artifact — see the image-size-report-amd64 job) |
#         main baseline (ghcr.io)
# PR bios tags carry a -amd64 suffix; trusted tags do not (see PR_multiarch.yml).
VARIANTS=()
for _v in "${SIZE_VARIANTS[@]}"; do
  _name="${_v%%|*}"
  case "$_name" in
  *-trusted) _pr="${_name}-${SHA}:24h" ;;    # trusted tags: SHA in name, TTL as tag
    *)         _pr="${_name}-amd64:${SHA}" ;;  # bios tags: -amd64 suffix
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
# Note: stderr from sort/cut is suppressed because callers may pipe this into
# "head -n N", which closes the pipe early and causes harmless SIGPIPE errors.
sort_by_abs_delta() {
  awk -F'\t' '{v=$NF; if(v<0)v=-v; printf "%d\t%s\n", v, $0}' \
    | sort -t"$(printf '\t')" -k1 -nr 2>/dev/null | cut -f2- 2>/dev/null
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
  main_sz=$(docker image inspect "$main_img" --format '{{.Size}}')

  # PR image was docker-loaded locally by the workflow before this script
  # runs (see image-size-report-amd64 in PR_multiarch.yml), so this checks
  # local presence rather than pulling. Skip rather than aborting the whole
  # report with no output if it is somehow missing (e.g. a build job failed).
  if ! docker image inspect "$pr_img" >/dev/null 2>&1; then
    summary_rows+="| \`${name}\` | $(human "$main_sz") | _PR image not found_ | — |"$'\n'
    continue
  fi

  pr_sz=$(docker image inspect "$pr_img" --format '{{.Size}}')
  delta=$((pr_sz - main_sz))
  pct=$(awk -v d="$delta" -v m="$main_sz" 'BEGIN{printf "%+.2f", (m>0)?(d/m*100):0}')
  sgn='+'; [ "$delta" -lt 0 ] && sgn='-'

  # Negligible delta: too small in both absolute and relative terms to matter,
  # so report "≈ no change" and skip the noisy per-file breakdown entirely.
  if awk -v d="$delta" -v m="$main_sz" -v nb="$NEGLIGIBLE_BYTES" -v np="$NEGLIGIBLE_PCT" \
       'BEGIN{ad=(d<0)?-d:d; p=(m>0)?(ad/m*100):0; exit !(ad<nb && p<np)}'; then
    summary_rows+="| \`${name}\` | $(human "$main_sz") | $(human "$pr_sz") | ≈ no change |"$'\n'
    continue
  fi
  summary_rows+="| \`${name}\` | $(human "$main_sz") | $(human "$pr_sz") | ${sgn}$(human "$delta") (${pct}%) |"$'\n'

  # Per-file delta, computed from a deterministic merge of both rootfs listings.
  # Files whose |Δ| is below FILE_MIN_DELTA are dropped: they only add noise to
  # the table (regenerated caches, timestamps, etc.) without changing the story.
  fdiff=$(file_diff <(rootfs_files "$main_img") <(rootfs_files "$pr_img") \
    | awk -F'\t' -v t="$FILE_MIN_DELTA" '{d=$NF; if(d<0)d=-d; if(d>=t)print}' || true)
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
  # "|| true" is required: head -n N closes the pipe early which causes sort
  # inside sort_by_abs_delta to exit with SIGPIPE; pipefail would otherwise
  # abort the script before the printf statements below ever run.
  file_rows=$(printf '%s\n' "$fdiff" | sort_by_abs_delta | head -n "$TOP_FILES" || true)
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
printf '> (regenerated caches/indexes), not the PR itself. Variants whose Δ is below\n'
printf '> ~256 KiB *and* 0.1%% of the baseline are shown as “≈ no change”, and files\n'
printf '> changing by <4 KiB are omitted from the breakdown, so negligible drift on\n'
printf '> large images stays out of the way. Check the per-file breakdown: a Δ\n'
printf '> concentrated in generated files (e.g. `ld.so.cache`, `*.dep`,\n'
printf '> `__pycache__`) is noise rather than a real size impact.\n\n'
printf '<sub>Uncompressed image sizes (`docker image inspect .Size`). Baseline = current `:main`. Generated by `.github/scripts/image-size-report.sh`.</sub>\n'
