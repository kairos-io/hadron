#!/bin/sh
# Guard the toolchain `make update-kernel-configs` resolves each kernel config
# with (kairos-io/kairos#6092). Kconfig probes the compiler and assembler, so a
# config resolved with another toolchain than the image build's loses options
# the build brings back with its own olddefconfig, and a pinned option does not
# stay pinned. Every olddefconfig run for arm64 and riscv64 has to name a cross
# compiler, and the toolchain in the container has to be at least as new as the
# Dockerfile's: the GCC_VERSION major and BINUTILS_VERSION or newer.
#
# The toolchain checks install it in the recipe's image, so they need docker.
# SKIP_TOOLCHAIN=1 runs only the recipe checks.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

recipe=$(make -n update-kernel-configs KERNEL_VERSION=0.0.0 DWARVES_VERSION=0 2>/dev/null) || {
    echo "FAIL: make -n update-kernel-configs did not run" >&2
    exit 1
}

makevar() {
    make -s --no-print-directory --eval "print-var: ; @echo \$($1)" print-var
}

gcc_major=$(makevar KERNEL_CONFIG_GCC)
image=$(makevar KERNEL_CONFIG_IMAGE)
packages=$(makevar KERNEL_CONFIG_PACKAGES)
want_gcc=$(awk -F= '/^ARG GCC_VERSION=/{split($2, v, "."); print v[1]; exit}' Dockerfile)
want_binutils=$(awk -F= '/^ARG BINUTILS_VERSION=/{print $2; exit}' Dockerfile)

fail=0
check() {
    pattern=$1
    what=$2
    if ! printf '%s\n' "$recipe" | grep -q -- "$pattern"; then
        echo "FAIL: $what" >&2
        fail=1
    fi
}

if [ -z "$gcc_major" ] || [ "$gcc_major" != "$want_gcc" ]; then
    echo "FAIL: KERNEL_CONFIG_GCC is '$gcc_major', GCC_VERSION in the Dockerfile has major '$want_gcc'" >&2
    fail=1
fi

check "make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- .*CC=aarch64-linux-gnu-gcc-$gcc_major olddefconfig" \
    "arm64 olddefconfig does not use aarch64-linux-gnu-gcc-$gcc_major"
check "make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- .*CC=riscv64-linux-gnu-gcc-$gcc_major olddefconfig" \
    "riscv64 olddefconfig does not use riscv64-linux-gnu-gcc-$gcc_major"
check "make ARCH=x86_64 .*CC=gcc-$gcc_major olddefconfig" \
    "x86_64 olddefconfig does not use gcc-$gcc_major"
check "gcc-$gcc_major-aarch64-linux-gnu" "the container does not install gcc-$gcc_major-aarch64-linux-gnu"
check "gcc-$gcc_major-riscv64-linux-gnu" "the container does not install gcc-$gcc_major-riscv64-linux-gnu"

# No arm64 or riscv olddefconfig without a CROSS_COMPILE.
if printf '%s\n' "$recipe" | grep -E 'make ARCH=(arm64|riscv) olddefconfig' >/dev/null; then
    echo "FAIL: an arm64 or riscv olddefconfig runs without CROSS_COMPILE" >&2
    fail=1
fi

if [ "${SKIP_TOOLCHAIN:-0}" != 1 ]; then
    # Install the recipe's packages in its image and check what Kconfig will
    # probe: the gcc major, the binutils version, an assembler instruction that
    # only binutils 2.45+ knows (ARM64_LSUI), and that the cross gcc can link.
    docker run --rm -e GCC="$gcc_major" -e WANT_BINUTILS="$want_binutils" \
        "$image" sh -c '
        set -e
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends '"$packages"' >/dev/null
        rc=0
        for p in "" aarch64-linux-gnu- riscv64-linux-gnu-; do
            got=$(${p}gcc-$GCC -dumpversion)
            case "$got" in
                "$GCC"|"$GCC".*) ;;
                *) echo "FAIL: ${p}gcc-$GCC is $got" >&2; rc=1 ;;
            esac
            as_ver=$(${p}as --version | head -n1 | awk "{print \$NF}")
            oldest=$(printf "%s\n%s\n" "$WANT_BINUTILS" "$as_ver" | sort -V | head -n1)
            if [ "$oldest" != "$WANT_BINUTILS" ]; then
                echo "FAIL: ${p}as is binutils $as_ver, older than BINUTILS_VERSION $WANT_BINUTILS" >&2
                rc=1
            fi
        done
        if ! echo ".arch_extension lsui" | aarch64-linux-gnu-as -o /dev/null -; then
            echo "FAIL: aarch64-linux-gnu-as does not know .arch_extension lsui (ARM64_LSUI)" >&2
            rc=1
        fi
        for p in aarch64-linux-gnu- riscv64-linux-gnu-; do
            if ! echo "int main(void) { return 0; }" | ${p}gcc-$GCC -x c - -o /dev/null; then
                echo "FAIL: ${p}gcc-$GCC cannot link (CC_CAN_LINK)" >&2
                rc=1
            fi
        done
        exit $rc
    ' || fail=1
fi

[ "$fail" -eq 0 ] && echo "OK: kernel configs are resolved with gcc $gcc_major and binutils $want_binutils or newer, cross for arm64 and riscv64"
exit "$fail"
