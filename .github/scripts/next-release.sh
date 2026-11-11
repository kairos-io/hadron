#!/usr/bin/env bash
#
# Prints the next release tag for the commits between a release tag and a
# commit, following Conventional Commits 1.0.0 and SemVer:
#
#   next-release.sh <last-tag> <commit>
#
# Every commit message in <last-tag>..<commit> goes through semver-bump.sh,
# and the biggest bump wins: a `!` or a `BREAKING CHANGE:` footer is major,
# `feat` is minor, anything else is patch. There is no 0.x exception: the
# spec says to "proceed as if you've already released the product", so a
# breaking change on v0.6.4 gives v1.0.0.
#
# A commit that is not a Conventional Commit counts as patch and is named on
# stderr, so a release is never blocked by an old or bot commit.
#
# Prints nothing and exits 0 when there are no commits in the range.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
last="${1:?usage: next-release.sh <last-tag> <commit>}"
target="${2:?usage: next-release.sh <last-tag> <commit>}"

if ! [[ "$last" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "last tag '$last' is not vMAJOR.MINOR.PATCH" >&2
  exit 1
fi
major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"

rank=0 # 0 none, 1 patch, 2 minor, 3 major
while read -r sha; do
  msg="$(git log -1 --format=%B "$sha")"
  if ! bump="$(bash "$here/semver-bump.sh" "$msg" 2>/dev/null)"; then
    echo "not a Conventional Commit, counted as patch: $(git log -1 --format='%h %s' "$sha")" >&2
    bump=patch
  fi
  case "$bump" in
    major) r=3 ;;
    minor) r=2 ;;
    *) r=1 ;;
  esac
  if [ "$r" -gt "$rank" ]; then
    rank=$r
  fi
done < <(git rev-list "${last}..${target}")

case "$rank" in
  0) exit 0 ;;
  1) echo "v${major}.${minor}.$((patch + 1))" ;;
  2) echo "v${major}.$((minor + 1)).0" ;;
  3) echo "v$((major + 1)).0.0" ;;
esac
