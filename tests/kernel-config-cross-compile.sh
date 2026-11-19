#!/bin/sh
# Guard the toolchain `make update-kernel-configs` resolves each kernel config
# with (kairos-io/kairos#6092). Kconfig probes the compiler and assembler, so an
# arm64 or riscv64 config resolved with the x86 host gcc loses options the image
# build brings back with its own olddefconfig, and a pinned option does not stay
# pinned. Every olddefconfig run for those two architectures has to name a cross
# compiler, and the container has to install it.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

recipe=$(make -n update-kernel-configs KERNEL_VERSION=0.0.0 DWARVES_VERSION=0 2>/dev/null) || {
    echo "FAIL: make -n update-kernel-configs did not run" >&2
    exit 1
}

fail=0
check() {
    pattern=$1
    what=$2
    if ! printf '%s\n' "$recipe" | grep -q -- "$pattern"; then
        echo "FAIL: $what" >&2
        fail=1
    fi
}

check 'make ARCH=arm64 CROSS_COMPILE=aarch64-none-elf- olddefconfig' \
    "arm64 olddefconfig does not set CROSS_COMPILE=aarch64-none-elf-"
check 'make ARCH=riscv CROSS_COMPILE=riscv-none-elf- olddefconfig' \
    "riscv64 olddefconfig does not set CROSS_COMPILE=riscv-none-elf-"
check 'gcc-aarch64-none-elf' "the container does not install gcc-aarch64-none-elf"
check 'gcc-riscv-none-elf' "the container does not install gcc-riscv-none-elf"

# No arm64 or riscv olddefconfig without a CROSS_COMPILE.
if printf '%s\n' "$recipe" | grep -E 'make ARCH=(arm64|riscv) olddefconfig' >/dev/null; then
    echo "FAIL: an arm64 or riscv olddefconfig runs without CROSS_COMPILE" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK: arm64 and riscv64 kernel configs are resolved with a cross gcc"
exit "$fail"
