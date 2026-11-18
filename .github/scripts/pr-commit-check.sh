#!/usr/bin/env bash
#
# Checks the only commit of a single-commit pull request against its title.
#
#   pr-commit-check.sh <pull request title> <full commit message>
#
# GitHub squash-merges a pull request with one commit using that commit's
# message, not the title, and next-release.sh reads the whole message of each
# commit on main. So the commit message must be a Conventional Commit, and it
# must ask for the same bump as the title: a `feat!:` commit under a `fix:`
# title would land on main as a major change.
#
# Prints the bump (major, minor or patch) when both agree. Otherwise exits 1
# and prints one line on stderr saying why.

set -euo pipefail

BUMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/semver-bump.sh"

title="${1-}"
msg="${2-}"
subject="${msg%%$'\n'*}"

if ! title_bump="$("$BUMP" "$title" 2>/dev/null)"; then
  echo "the title '$title' is not a Conventional Commit subject" >&2
  exit 1
fi

if ! commit_bump="$("$BUMP" "$msg" 2>/dev/null)"; then
  echo "the only commit, '$subject', is not a Conventional Commit and becomes the message on main: reword it as 'type(scope): description'" >&2
  exit 1
fi

if [ "$commit_bump" != "$title_bump" ]; then
  echo "the only commit, '$subject', asks for a $commit_bump change but the title asks for a $title_bump one; the commit message is what lands on main, so make them agree" >&2
  exit 1
fi

echo "$commit_bump"
