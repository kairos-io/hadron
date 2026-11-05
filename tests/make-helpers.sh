#!/bin/sh
#
# Locks in the Makefile helpers a fresh clone reaches for first:
#
#   1. `make` (the help target) prints every line and exits 0, and states the
#      real BOOTLOADER default;
#   2. run-qemu boots the newest build/kairos-hadron-*.iso, and fails with a
#      clear message, before creating disk.img, when there is none;
#   3. bump-deps, which ran the removed Bumpfile, is gone.
#
# make runs from a scratch directory with -f pointing at the tree, so build/
# and disk.img resolve there and no qemu is ever started.

set -eu

unset BOOTLOADER ARCH ISO_FILE || true

repo_root=$(cd "$(dirname "$0")/.." && pwd)
makefile="$repo_root/Makefile"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

pass() {
	echo "ok: $*"
}

contains() {
	case "$2" in
	*"$3"*) pass "$1" ;;
	*) fail "$1: expected to find '$3' in: $2" ;;
	esac
}

lacks() {
	case "$2" in
	*"$3"*) fail "$1: did not expect to find '$3' in: $2" ;;
	*) pass "$1" ;;
	esac
}

# 1. help
if help=$(make --no-print-directory -f "$makefile" 2>&1); then
	pass "make help exits 0"
else
	fail "make help exited non-zero: $help"
fi
contains "help prints the ARCH line" "$help" "The ARCH variable can be set to"
contains "help prints the lines after ARCH" "$help" "The expected keys in the KEYS_DIR are:"
contains "help states the grub default" "$help" "The default is 'grub'."
lacks "help does not claim a systemd default" "$help" "The default is 'systemd'"

# 2. run-qemu with no ISO
if out=$(make --no-print-directory -f "$makefile" run-qemu 2>&1); then
	fail "run-qemu with no ISO exited 0: $out"
else
	pass "run-qemu with no ISO exits non-zero"
fi
contains "run-qemu says there is no ISO" "$out" "no build/kairos-hadron-*.iso found"
if [ -e disk.img ]; then
	fail "run-qemu created disk.img with no ISO to boot"
else
	pass "run-qemu does not create disk.img with no ISO"
fi

if out=$(make --no-print-directory -f "$makefile" run-qemu ISO_FILE=build/missing.iso 2>&1); then
	fail "run-qemu with a missing ISO_FILE exited 0: $out"
else
	contains "run-qemu names the missing ISO_FILE" "$out" "build/missing.iso"
fi

# 2. run-qemu picks the newest ISO
mkdir build
touch -t 202601010000 build/kairos-hadron-old.iso
touch -t 202602010000 build/kairos-hadron-new.iso
for arch in amd64 riscv64; do
	dry=$(make --no-print-directory -n -f "$makefile" run-qemu ARCH=$arch 2>&1)
	contains "run-qemu ($arch) boots the newest ISO" "$dry" "build/kairos-hadron-new.iso"
	lacks "run-qemu ($arch) does not boot an older ISO" "$dry" "build/kairos-hadron-old.iso"
done
dry=$(make --no-print-directory -n -f "$makefile" run-qemu ISO_FILE=build/kairos-hadron-old.iso 2>&1)
contains "run-qemu honours ISO_FILE" "$dry" "file=build/kairos-hadron-old.iso"

# 3. bump-deps
if out=$(make --no-print-directory -n -f "$makefile" bump-deps 2>&1); then
	fail "bump-deps still exists: $out"
else
	pass "bump-deps is gone"
fi

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi
echo "all make helper checks passed"
