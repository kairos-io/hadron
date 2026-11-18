#!/usr/bin/env bash
#
# Runs .github/scripts/pr-commit-check.sh against pull request titles and
# commit messages, and checks the bump it prints and its exit status.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-commit-check.sh"

failed=0
passed=0

# expect <bump> <title> <message>: the script prints <bump> and exits 0.
expect() {
  local want="$1" title="$2" msg="$3" got
  if got="$("$SCRIPT" "$title" "$msg" 2>/dev/null)" && [ "$got" = "$want" ]; then
    passed=$((passed + 1))
  else
    echo "FAIL: want '$want', got '${got:-<error>}' for title '$title', commit: $msg" >&2
    failed=$((failed + 1))
  fi
}

# reject <title> <message>: the script exits non-zero, prints nothing on
# stdout and one line on stderr.
reject() {
  local title="$1" msg="$2" got err
  if got="$("$SCRIPT" "$title" "$msg" 2>/dev/null)"; then
    echo "FAIL: accepted as '$got' for title '$title', commit: $msg" >&2
    failed=$((failed + 1))
    return
  fi
  err="$("$SCRIPT" "$title" "$msg" 2>&1 >/dev/null || true)"
  if [ -n "$got" ]; then
    echo "FAIL: rejected but printed '$got' for title '$title', commit: $msg" >&2
    failed=$((failed + 1))
  elif [ -z "$err" ] || [[ "$err" == *$'\n'* ]]; then
    echo "FAIL: want one line on stderr, got: '$err'" >&2
    failed=$((failed + 1))
  else
    passed=$((passed + 1))
  fi
}

expect patch 'fix(grub): define BUFSIZ' 'fix(grub): define BUFSIZ'
expect patch 'fix(grub): define BUFSIZ' $'fix: define it\n\nSome body text.'
expect patch 'fix(grub): define BUFSIZ' 'chore: different wording, same bump'
expect minor 'feat: ship less' 'feat(init): ship less'
expect major 'feat!: drop the legacy flag' 'fix(agent)!: drop the legacy flag'
expect major 'fix!: rename a key' $'fix: rename a key\n\nBREAKING CHANGE: foo is now bar'
expect patch 'Revert "feat: a"' 'Revert "feat: a"'

# The commit message lands on main, so its bump must match the title's.
reject 'fix: rename a key' 'feat!: rename a key'
reject 'fix: rename a key' $'fix: rename a key\n\nBREAKING CHANGE: foo is now bar'
reject 'fix: small thing' 'feat: small thing'
reject 'feat: ship less' 'fix: ship less'
reject 'feat!: drop it' 'feat: drop it'

# Not Conventional Commits.
reject 'fix: define BUFSIZ' 'Update grub.cfg'
reject 'fix: define BUFSIZ' ''
reject 'Update grub.cfg' 'fix: define BUFSIZ'

echo "pr-commit-check: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
