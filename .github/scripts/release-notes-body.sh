#!/bin/sh
#
# Prints the body of a GitHub release with the shipped components section
# appended:
#
#   release-notes-body.sh <existing-body> <components.md>
#
# <existing-body> is the current release body (`gh release view --json body`),
# <components.md> the manifest from `hack/gen-components.sh --format md`.
#
# The release-notes job runs again whenever a tag's workflow is re-run, so an
# existing "Shipped components" section is dropped first, from its heading to
# the end of the body, together with the blank lines in front of it. Running
# this any number of times leaves exactly one section and keeps every note
# above it. Release bodies edited in the web UI come back with CRLF line
# endings, so the heading match ignores a trailing carriage return.

set -eu

existing=$1
components=$2
heading='## 📦 Shipped components'

awk -v heading="$heading" '
  { line = $0; sub(/\r$/, "", line) }
  line == heading { exit }
  {
    if (line == "") { blank++; next }
    for (; blank > 0; blank--) print ""
    print
  }
' "$existing"

echo
echo "$heading"
echo
cat "$components"
