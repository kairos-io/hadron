#!/usr/bin/env bash
#
# Runs next-release.sh against throwaway git repos and checks the tag it
# prints for each mix of commits.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/next-release.sh"

failed=0
passed=0

# check <want> <commit message>...: a repo tagged v0.6.4, then one empty
# commit per message; next-release.sh must print <want> (empty for none).
check() {
  local want="$1" dir got
  shift
  dir="$(mktemp -d)"
  (
    cd "$dir"
    git init -q
    git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: base"
    git tag v0.6.4
    for msg in "$@"; do
      git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$msg"
    done
  )
  got="$(cd "$dir" && "$SCRIPT" v0.6.4 HEAD 2>/dev/null)" || got="<error>"
  rm -rf "$dir"
  if [ "$got" = "$want" ]; then
    passed=$((passed + 1))
  else
    echo "FAIL: want '$want', got '$got' for: $*" >&2
    failed=$((failed + 1))
  fi
}

check ''
check v0.6.5 'fix(grub): define BUFSIZ'
check v0.6.5 'chore(deps): bump bash' 'ci: something' 'docs: words'
check v0.7.0 'chore(deps): bump bash' 'feat: ship less'
check v0.7.0 'feat: one' 'feat: two' 'fix: three'
check v1.0.0 'fix(kernel)!: drop the arm64 legacy config'
check v1.0.0 'feat: a' $'fix: rename a key\n\nBREAKING CHANGE: foo is now bar'
check v1.0.0 'chore: x' $'refactor: y\n\nBREAKING-CHANGE: z'
# Old and bot commits that are not Conventional Commits count as patch.
check v0.6.5 'Automatic bumps for kernel (#829)'
check v0.7.0 'Automatic bumps for kernel (#829)' 'feat: a'
check v0.6.5 'Revert "feat: a"'

echo "next-release: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
