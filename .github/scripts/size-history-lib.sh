#!/usr/bin/env bash
# Shared helpers for the image size tooling.
#
# Sourced by:
#   - image-size-report.sh : per-PR size report (PR vs :main baseline)
#   - size-history.sh       : per-merge size history (running time series)
#
# Keeping the canonical variant list and a couple of formatting helpers here
# avoids duplicating the list of shipped images in two places that must stay in
# sync. This file is meant to be sourced, not executed.

# Stable, locale-independent byte sorting/formatting regardless of runner locale.
export LC_ALL=C

# Canonical list of shipped image variants we track, in stable column order.
# Each entry is "<display-name>|<ghcr-repo-suffix>" where <ghcr-repo-suffix> is
# appended to "ghcr.io/<owner>/<repo>" to form the published image repository
# (the plain `hadron` image has an empty suffix). The :main multi-arch manifest
# of each of these is what the history job measures.
SIZE_VARIANTS=(
  "hadron|"
  "hadron-cloud|-cloud"
  "hadron-trusted|-trusted"
  "hadron-cloud-trusted|-cloud-trusted"
)

# size_variant_names: print the display names, one per line, in column order.
size_variant_names() {
  local v name
  for v in "${SIZE_VARIANTS[@]}"; do
    name="${v%%|*}"
    printf '%s\n' "$name"
  done
}

# size_variant_ghcr <owner/repo> <display-name>: print the :main ghcr image ref
# for the given variant, or nothing if the name is unknown.
size_variant_ghcr() {
  local repo="$1" want="$2" v name suffix
  for v in "${SIZE_VARIANTS[@]}"; do
    name="${v%%|*}"
    suffix="${v#*|}"
    if [ "$name" = "$want" ]; then
      printf 'ghcr.io/%s%s:main\n' "$repo" "$suffix"
      return 0
    fi
  done
  return 1
}

# human <bytes>: human-readable IEC size. A leading "-" is stripped so callers
# control the sign themselves (matches the existing report formatting).
human() {
  numfmt --to=iec --suffix=B "${1#-}"
}
