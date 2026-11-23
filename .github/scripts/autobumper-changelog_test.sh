#!/usr/bin/env bash
#
# Checks which dependency bumps autobumper-changelog.rb counts as a release
# (critical_release_bump?), and so which Conventional Commit type the bump PR
# gets: feat for a release of the kernel, systemd, musl, bash or openssh,
# chore for everything else.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/autobumper-changelog.rb"

failed=0
passed=0

# check <true|false> <ARG> <old> <new>
check() {
  local want="$1" arg="$2" old="$3" new="$4" got
  got="$(ruby -e '
    require ARGV[0]
    puts critical_release_bump?("matcher" => ARGV[1], "old_version" => ARGV[2], "new_version" => ARGV[3])
  ' "$SCRIPT" "$arg" "$old" "$new")"
  if [ "$got" = "$want" ]; then
    passed=$((passed + 1))
  else
    echo "FAIL: want $want, got $got for $arg $old -> $new" >&2
    failed=$((failed + 1))
  fi
}

# kernel and systemd: the first component
check true  KERNEL_VERSION  6.18.2 7.0
check true  KERNEL_VERSION  6.18.2 7.0.1
check false KERNEL_VERSION  7.3.5  7.4.1
check false KERNEL_VERSION  7.3.4  7.3.5
check true  SYSTEMD_VERSION 262.2  263
check false SYSTEMD_VERSION 262.2  262.3

# musl, bash, openssh: the first two components
check true  MUSL_VERSION    1.2.6  1.3.0
check false MUSL_VERSION    1.2.5  1.2.6
check true  BASH_VERSION    5.3    5.4
check true  BASH_VERSION    5.3    6.0
check false BASH_VERSION    5.3    5.3.1
check true  OPENSSH_VERSION 10.6p2 10.7p1
check true  OPENSSH_VERSION 10.6p2 11.0p1
check false OPENSSH_VERSION 10.6p1 10.6p2

# downgrades, unreadable versions and packages off the list are not releases
check false KERNEL_VERSION  7.0    6.18.2
check false SYSTEMD_VERSION abc    263
check false FLEX_VERSION    2.6.4  3.0.0
check false BUSYBOX_VERSION 1.38.0 2.0.0

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
