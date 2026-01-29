## This is Dockerfile, that at the end of the process it builds a 
## small LFS system, starting from Alpine Linux.
## It uses mussel to build the system.
ARG BOOTLOADER=grub
ARG KERNEL_TYPE=default
ARG VERSION=0.0.1
ARG JOBS=16
## Maximum load for make -l
ARG MAX_LOAD=32
ARG FIPS="no-fips"
ARG TARGETARCH
ARG CFLAGS

# Base image with build tools
# Use sha. Otherwise the tag can get updated and break reproducibility and force rebuilds for apparent no reason
FROM alpine:3.23.3@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659 AS alpine-base
RUN apk update && \
    apk add git bash wget bash perl build-base make patch busybox-static \
    curl m4 xz texinfo bison gawk gzip zstd-dev coreutils bzip2 tar rsync \
    git coreutils findutils pax-utils binutils

FROM alpine-base AS stage0

########################################################
#
# Stage 0 - building the cross-compiler
#
########################################################

ARG VENDOR="hadron"
ENV VENDOR=${VENDOR}
ARG ARCH="x86-64"
ENV ARCH=${ARCH}
ARG BUILD_ARCH="x86_64"
ENV BUILD_ARCH=${BUILD_ARCH}
ARG JOBS
ENV JOBS=${JOBS}
ARG MUSSEL_VERSION="95dec40aee2077aa703b7abc7372ba4d34abb889"
ENV MUSSEL_VERSION=${MUSSEL_VERSION}

# Validate that the arches are correct
RUN if [ "${ARCH}" = "x86-64" ] && [ "${BUILD_ARCH}" != "x86_64" ]; then echo "For ARCH x86-64, BUILD_ARCH must be x86_64"; exit 1; fi
RUN if [ "${ARCH}" = "aarch64" ] && [ "${BUILD_ARCH}" != "aarch64" ]; then echo "For ARCH aarch64, BUILD_ARCH must be aarch64"; exit 1; fi

RUN git clone https://github.com/firasuke/mussel.git && cd mussel && git checkout ${MUSSEL_VERSION} -b build
RUN cd mussel && ./mussel ${ARCH} -k -l -o -p -s -T ${VENDOR}

ENV PATH=/mussel/toolchain/bin/:$PATH
ENV LC_ALL=POSIX
ENV TARGET=${BUILD_ARCH}-${VENDOR}-linux-musl
ENV BUILD=${BUILD_ARCH}-pc-linux-musl

### This stage is used to download the sources for the packages
### This runs in parallel with stage0 to improve build time since it's network-bound while stage0 is CPU-bound
FROM alpine-base AS sources-downloader

RUN mkdir -p /sources/downloads

WORKDIR /sources/downloads

ARG CURL_VERSION=8.18.0
RUN wget -q https://curl.se/download/curl-${CURL_VERSION}.tar.gz -O curl.tar.gz

ARG RSYNC_VERSION=3.4.1
RUN wget -q https://download.samba.org/pub/rsync/rsync-${RSYNC_VERSION}.tar.gz -O rsync.tar.gz

ARG XXHASH_VERSION=0.8.3
RUN wget -q https://github.com/Cyan4973/xxHash/archive/refs/tags/v${XXHASH_VERSION}.tar.gz -O xxhash.tar.gz

ARG ZSTD_VERSION=1.5.7
RUN wget -q https://github.com/facebook/zstd/archive/v${ZSTD_VERSION}.tar.gz -O zstd.tar.gz

ARG LZ4_VERSION=1.10.0
RUN wget -q https://github.com/lz4/lz4/archive/v${LZ4_VERSION}.tar.gz -O lz4.tar.gz

ARG ZLIB_VERSION=1.3.1
RUN wget -q https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz -O zlib.tar.gz

ARG ACL_VERSION=2.3.2
RUN wget -q https://download.savannah.gnu.org/releases/acl/acl-${ACL_VERSION}.tar.gz -O acl.tar.gz

ARG ATTR_VERSION=2.5.2
RUN wget -q https://download.savannah.nongnu.org/releases/attr/attr-${ATTR_VERSION}.tar.gz -O attr.tar.gz

ARG GAWK_VERSION=5.3.2
RUN wget -q https://ftpmirror.gnu.org/gawk/gawk-${GAWK_VERSION}.tar.xz -O gawk.tar.xz

ARG CA_CERTIFICATES_VERSION=20251003
RUN wget -q https://gitlab.alpinelinux.org/alpine/ca-certificates/-/archive/${CA_CERTIFICATES_VERSION}/ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2 -O ca-certificates.tar.bz2

ARG SYSTEMD_VERSION=259
RUN cd /sources/downloads && wget -q https://github.com/systemd/systemd/archive/refs/tags/v${SYSTEMD_VERSION}.tar.gz -O systemd.tar.gz

ARG LIBCAP_VERSION=2.77
RUN wget -q https://kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-${LIBCAP_VERSION}.tar.xz -O libcap.tar.xz

ARG UTIL_LINUX_VERSION=2.41.3
RUN UTIL_LINUX_VERSION_MAJOR="${UTIL_LINUX_VERSION%%.*}" \
    && UTIL_LINUX_VERSION_MINOR="${UTIL_LINUX_VERSION#*.}"; UTIL_LINUX_VERSION_MINOR="${UTIL_LINUX_VERSION_MINOR%.*}" \
    && wget -q https://www.kernel.org/pub/linux/utils/util-linux/v${UTIL_LINUX_VERSION_MAJOR}.${UTIL_LINUX_VERSION_MINOR}/util-linux-${UTIL_LINUX_VERSION}.tar.xz -O util-linux.tar.xz

ARG PYTHON_VERSION=3.14.2
RUN wget -q https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz -O Python.tar.xz

ARG SQLITE3_VERSION=3.51.2
RUN wget -q https://github.com/sqlite/sqlite/archive/refs/tags/version-${SQLITE3_VERSION}.tar.gz -O sqlite3.tar.gz

ARG OPENSSL_VERSION=3.6.1
ARG OPENSSL_FIPS_VERSION=3.1.2
RUN wget -q https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz  -O openssl.tar.gz
RUN wget -q https://www.openssl.org/source/openssl-${OPENSSL_FIPS_VERSION}.tar.gz  -O openssl-fips.tar.gz

ARG OPENSSH_VERSION=10.0p1
RUN wget -q https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz -O openssh.tar.gz

ARG PKGCONFIG_VERSION=2.5.1
RUN wget -q https://distfiles.dereferenced.org/pkgconf/pkgconf-${PKGCONFIG_VERSION}.tar.xz -O pkgconf.tar.xz

ARG DBUS_VERSION=1.16.2
RUN wget -q https://dbus.freedesktop.org/releases/dbus/dbus-${DBUS_VERSION}.tar.xz && mv dbus-${DBUS_VERSION}.tar.xz dbus.tar.xz

# libexpat
ARG EXPAT_VERSION=2.7.3
# Use a single var and extract major/minor/patch to build the URL
RUN EXPAT_VERSION_MAJOR="${EXPAT_VERSION%%.*}" \
 && EXPAT_VERSION_MINOR="${EXPAT_VERSION#*.}"; EXPAT_VERSION_MINOR="${EXPAT_VERSION_MINOR%.*}" \
 && EXPAT_VERSION_PATCH="${EXPAT_VERSION##*.}" \
 && wget -q \
 "https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION_MAJOR}_${EXPAT_VERSION_MINOR}_${EXPAT_VERSION_PATCH}/expat-${EXPAT_VERSION}.tar.gz" \
 -O expat.tar.gz

ARG SECCOMP_VERSION=2.6.0
# seccomp
RUN wget -q https://github.com/seccomp/libseccomp/releases/download/v${SECCOMP_VERSION}/libseccomp-${SECCOMP_VERSION}.tar.gz -O libseccomp.tar.gz

ARG STRACE_VERSION=6.18
RUN wget -q https://strace.io/files/${STRACE_VERSION}/strace-${STRACE_VERSION}.tar.xz -O strace.tar.xz

ARG KBD_VERSION=2.9.0
RUN wget -q https://www.kernel.org/pub/linux/utils/kbd/kbd-${KBD_VERSION}.tar.gz -O kbd.tar.gz

ARG IPTABLES_VERSION=1.8.11
RUN wget -q https://www.netfilter.org/projects/iptables/files/iptables-${IPTABLES_VERSION}.tar.xz -O iptables.tar.xz

ARG LIBMNL_VERSION=1.0.5
RUN wget -q https://www.netfilter.org/projects/libmnl/files/libmnl-${LIBMNL_VERSION}.tar.bz2 -O libmnl.tar.bz2

ARG LIBNFTNL_VERSION=1.3.1
RUN wget -q https://www.netfilter.org/projects/libnftnl/files/libnftnl-${LIBNFTNL_VERSION}.tar.xz -O libnftnl.tar.xz

## kernel
ARG KERNEL_VERSION=6.18.7
RUN wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz -O linux.tar.xz

## flex
ARG FLEX_VERSION=2.6.4
RUN wget -q https://github.com/westes/flex/releases/download/v${FLEX_VERSION}/flex-${FLEX_VERSION}.tar.gz -O flex.tar.gz

## bison
ARG BISON_VERSION=3.8.2
RUN wget -q https://ftpmirror.gnu.org/bison/bison-${BISON_VERSION}.tar.xz -O bison.tar.xz

## autoconf
ARG AUTOCONF_VERSION=2.72
RUN wget -q https://ftpmirror.gnu.org/autoconf/autoconf-${AUTOCONF_VERSION}.tar.xz -O autoconf.tar.xz

## automake
ARG AUTOMAKE_VERSION=1.18.1
RUN wget -q https://ftpmirror.gnu.org/automake/automake-${AUTOMAKE_VERSION}.tar.xz -O automake.tar.xz

## fts
ARG FTS_VERSION=1.2.7
RUN wget -q https://github.com/pullmoll/musl-fts/archive/v${FTS_VERSION}.tar.gz -O musl-fts.tar.gz

## libtool
ARG LIBTOOL_VERSION=2.5.4
RUN wget -q https://ftpmirror.gnu.org/libtool/libtool-${LIBTOOL_VERSION}.tar.xz -O libtool.tar.xz

ARG LIBELF_VERSION=0.193
RUN wget -q https://github.com/arachsys/libelf/archive/refs/tags/v0.193.tar.gz -O libelf.tar.gz

## xzutils
ARG XZUTILS_VERSION=5.8.2
RUN wget -q https://tukaani.org/xz/xz-${XZUTILS_VERSION}.tar.gz -O xz.tar.gz

## kmod
ARG KMOD_VERSION=34.2
RUN wget -q https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-${KMOD_VERSION}.tar.gz -O kmod.tar.gz

## dracut
ARG DRACUT_VERSION=109
RUN wget -q https://github.com/dracut-ng/dracut-ng/archive/refs/tags/${DRACUT_VERSION}.tar.gz -O dracut.tar.gz

## libaio
ARG LIBAIO_VERSION=0.3.113
RUN wget -q https://releases.pagure.org/libaio/libaio-${LIBAIO_VERSION}.tar.gz -O libaio.tar.gz

## lvm2
ARG LVM2_VERSION=2.03.38
RUN wget -q http://ftp-stud.fht-esslingen.de/pub/Mirrors/sourceware.org/lvm2/releases/LVM2.${LVM2_VERSION}.tgz -O lvm2.tgz

## multipath-tools
ARG MULTIPATH_TOOLS_VERSION=0.14.1
RUN wget -q https://github.com/opensvc/multipath-tools/archive/refs/tags/${MULTIPATH_TOOLS_VERSION}.tar.gz -O multipath-tools.tar.gz

## jsonc
ARG JSONC_VERSION=0.18
RUN wget -q https://s3.amazonaws.com/json-c_releases/releases/json-c-${JSONC_VERSION}.tar.gz -O json-c.tar.gz

## cmake
ARG CMAKE_VERSION=4.2.3
RUN wget -q https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}.tar.gz -O cmake.tar.gz

## urcu
ARG URCU_VERSION=0.15.6
RUN wget -q https://lttng.org/files/urcu/userspace-rcu-${URCU_VERSION}.tar.bz2 -O urcu.tar.bz2

## parted
ARG PARTED_VERSION=3.6
RUN wget -q https://ftpmirror.gnu.org/gnu/parted/parted-${PARTED_VERSION}.tar.xz -O parted.tar.xz

## e2fsprogs
ARG E2FSPROGS_VERSION=1.47.3
RUN wget -q https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v${E2FSPROGS_VERSION}/e2fsprogs-${E2FSPROGS_VERSION}.tar.xz -O e2fsprogs.tar.xz

## dosfstools
ARG DOSFSTOOLS_VERSION=4.2
RUN wget -q https://github.com/dosfstools/dosfstools/releases/download/v${DOSFSTOOLS_VERSION}/dosfstools-${DOSFSTOOLS_VERSION}.tar.gz -O dosfstools.tar.gz

## cryptsetup
ARG CRYPTSETUP_VERSION=2.8.4
RUN wget -q https://cdn.kernel.org/pub/linux/utils/cryptsetup/v${CRYPTSETUP_VERSION%.*}/cryptsetup-${CRYPTSETUP_VERSION}.tar.xz -O cryptsetup.tar.xz

## grub
ARG GRUB_VERSION=2.14
RUN wget -q https://mirrors.edge.kernel.org/gnu/grub/grub-${GRUB_VERSION}.tar.xz -O grub.tar.xz

## PAM
ARG PAM_VERSION=1.7.2
RUN wget -q https://github.com/linux-pam/linux-pam/releases/download/v${PAM_VERSION}/Linux-PAM-${PAM_VERSION}.tar.xz -O pam.tar.xz

# shadow
ARG SHADOW_VERSION=4.19.2
RUN wget -q https://github.com/shadow-maint/shadow/releases/download/${SHADOW_VERSION}/shadow-${SHADOW_VERSION}.tar.xz -O shadow.tar.xz

# alpine aports repo for patches to build under musl
ARG APORTS_VERSION=3.23.3
RUN wget -q https://gitlab.alpinelinux.org/alpine/aports/-/archive/v${APORTS_VERSION}/aports-v${APORTS_VERSION}.tar.gz -O aports.tar.gz

## busybox
ARG BUSYBOX_VERSION=1.37.0
# XXX: Temporary workaround as busybox currently have expired certificates
RUN wget -q --no-check-certificate https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 -O busybox.tar.bz2

## musl
ARG MUSL_VERSION=1.2.5
RUN wget -q http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz -O musl.tar.gz

## gcc and dependencies
ARG GCC_VERSION=14.3.0
RUN wget -q http://mirror.netcologne.de/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz -O gcc.tar.xz

ARG GMP_VERSION=6.3.0
RUN wget -q http://mirror.netcologne.de/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2 -O gmp.tar.bz2

ARG MPC_VERSION=1.3.1
RUN wget -q http://mirror.netcologne.de/gnu/mpc/mpc-${MPC_VERSION}.tar.gz -O mpc.tar.gz

ARG MPFR_VERSION=4.2.2
RUN wget -q http://mirror.netcologne.de/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2 -O mpfr.tar.bz2

## make
ARG MAKE_VERSION=4.4.1
RUN wget -q https://mirror.netcologne.de/gnu/make/make-${MAKE_VERSION}.tar.gz -O make.tar.gz

## binutils (for stage0)
ARG BINUTILS_VERSION=2.45.1
RUN wget -q http://mirror.easyname.at/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz -O binutils.tar.xz

## popt
ARG POPT_VERSION=1.19
RUN wget -q http://ftp.rpm.org/popt/releases/popt-1.x/popt-${POPT_VERSION}.tar.gz -O popt.tar.gz

## m4
ARG M4_VERSION=1.4.20
RUN wget -q http://mirror.easyname.at/gnu/m4/m4-${M4_VERSION}.tar.xz -O m4.tar.xz

## readline
ARG READLINE_VERSION=8.3
RUN wget -q http://mirror.easyname.at/gnu/readline/readline-${READLINE_VERSION}.tar.gz -O readline.tar.gz

## perl
ARG PERL_VERSION=5.42.0
RUN wget -q http://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.xz -O perl.tar.xz

## coreutils
ARG COREUTILS_VERSION=9.9
RUN wget -q http://mirror.easyname.at/gnu/coreutils/coreutils-${COREUTILS_VERSION}.tar.xz -O coreutils.tar.xz

## findutils
ARG FINDUTILS_VERSION=4.10.0
RUN wget -q http://mirror.easyname.at/gnu/findutils/findutils-${FINDUTILS_VERSION}.tar.xz -O findutils.tar.xz

## grep
ARG GREP_VERSION=3.12
RUN wget -q http://mirror.easyname.at/gnu/grep/grep-${GREP_VERSION}.tar.xz -O grep.tar.xz

## gperf
ARG GPERF_VERSION=3.3
RUN wget -q http://mirror.easyname.at/gnu/gperf/gperf-${GPERF_VERSION}.tar.gz -O gperf.tar.gz

## diffutils
ARG DIFFUTILS_VERSION=3.12
RUN wget -q http://ftpmirror.gnu.org/diffutils/diffutils-${DIFFUTILS_VERSION}.tar.xz -O diffutils.tar.xz

## sudo
ARG SUDO_VERSION=1.9.17p2
RUN wget -q https://www.sudo.ws/dist/sudo-${SUDO_VERSION}.tar.gz -O sudo.tar.gz

## pax-utils
ARG PAX_UTILS_VERSION=1.3.9
RUN wget -q https://dev.gentoo.org/~sam/distfiles/app-misc/pax-utils/pax-utils-${PAX_UTILS_VERSION}.tar.xz -O pax-utils.tar.xz

## openscsi
ARG OPEN_SCSI_VERSION=2.1.11
RUN wget -q https://github.com/open-iscsi/open-iscsi/archive/refs/tags/${OPEN_SCSI_VERSION}.tar.gz -O openscsi.tar.gz

# GDB
ARG GDB_VERSION=17.1
RUN wget -q https://sourceware.org/pub/gdb/releases/gdb-${GDB_VERSION}.tar.gz -O gdb.tar.gz

ARG LIBFFI_VERSION=3.5.2
RUN wget -q https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz -O libffi.tar.gz

ARG TPM2_TSS_VERSION=4.1.3
RUN wget -q https://github.com/tpm2-software/tpm2-tss/releases/download/${TPM2_TSS_VERSION}/tpm2-tss-${TPM2_TSS_VERSION}.tar.gz -O tpm2-tss.tar.gz

# libxml
ARG LIBXML2_VERSION=2.15.1
RUN major="${LIBXML2_VERSION%%.*}" \
 && minor="${LIBXML2_VERSION#*.}"; minor="${minor%%.*}" \
 && LIBXML2_VERSION_MAJOR_AND_MINOR="${major}.${minor}" \
 && wget -q https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION_MAJOR_AND_MINOR}/libxml2-${LIBXML2_VERSION}.tar.xz -O libxml2.tar.xz
# gzip
ARG GZIP_VERSION=1.14
RUN wget -q https://ftp.gnu.org/gnu/gzip/gzip-${GZIP_VERSION}.tar.xz -O gzip.tar.xz

ARG BASH_VERSION=5.3
# Patch level is the number of patches upstream bash has released for this version https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}-patches/
# TODO: Maybe we should try like 15 patches and stop once 2 have gone without finding a patch? So we cover more ground without hardcoding a number?
ARG PATCH_LEVEL=9
# Get the patches from https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}-patches/
# They are in the format bash$BASH_VERSION_NO_DOT-00$PATCH_LEVEL
# But the index starts at 1
RUN wget -q http://mirror.easyname.at/gnu/bash/bash-${BASH_VERSION}.tar.gz && tar -xf bash-${BASH_VERSION}.tar.gz && mv bash-${BASH_VERSION} bash
WORKDIR /sources/downloads/bash
RUN for i in $(seq -w 1 ${PATCH_LEVEL}); do \
        echo "Applying bash patch bash${BASH_VERSION//./}-00${i}"; \
        wget -q https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}-patches/bash${BASH_VERSION//./}-00${i} -O bash-patch-${i}.patch; \
        patch -p0 < bash-patch-${i}.patch; \
    done
WORKDIR /sources/downloads

ARG LIBKKCAPI_VERSION=1.5.0
RUN wget -q https://github.com/smuellerDD/libkcapi/archive/refs/tags/v${LIBKKCAPI_VERSION}.tar.gz -O libkcapi.tar.gz

ARG SHIM_VERSION=16.1
RUN wget -q https://github.com/rhboot/shim/releases/download/${SHIM_VERSION}/shim-${SHIM_VERSION}.tar.bz2 -O shim.tar.bz2

ARG ICONV_VERSION=1.18
RUN wget -q https://ftpmirror.gnu.org/libiconv/libiconv-${ICONV_VERSION}.tar.gz -O libiconv.tar.gz

FROM stage0 AS skeleton

COPY ./setup_rootfs.sh ./setup_rootfs.sh
RUN chmod +x ./setup_rootfs.sh && SYSROOT=/sysroot ./setup_rootfs.sh

########################################################
#
# Stage 0 - building the packages using the cross-compiler
#
########################################################

###
### Busybox
###
FROM stage0 AS busybox-stage0
ARG JOBS
COPY --from=sources-downloader /sources/downloads/busybox.tar.bz2 /sources/

RUN cd /sources && tar -xf busybox.tar.bz2 && \
    mv busybox-* busybox && cd busybox && \
    make -s distclean && \
    make -s ARCH="${ARCH}" defconfig && \
    sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config && \
    sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_TC\)=y/# \1 is not set/' .config && \
    if [ "${ARCH}" == "aarch64" ]; then sed -i 's/\(CONFIG_SHA1_HWACCEL\)=y/# \1 is not set/' .config; fi && \
    make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS} -l${MAX_LOAD} && \
    make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS} -l${MAX_LOAD} CONFIG_PREFIX="/sysroot" install

###
### MUSL
###
FROM stage0 AS musl-stage0
ARG JOBS
COPY --from=sources-downloader /sources/downloads/musl.tar.gz /sources/
RUN cd /sources && tar -xf musl.tar.gz && mv musl-* musl &&\
    cd musl && \
    ./configure --disable-warnings \
      CROSS_COMPILE=${TARGET}- \
      --prefix=/usr \
      --disable-static \
      --target=${TARGET} && \
      make -s -j${JOBS} && \
      DESTDIR=/sysroot make -s -j${JOBS} -l${MAX_LOAD} install

###
### GCC
###
FROM stage0 AS gcc-stage0
ARG JOBS
COPY --from=sources-downloader /sources/downloads/gcc.tar.xz .
COPY --from=sources-downloader /sources/downloads/gmp.tar.bz2 .
COPY --from=sources-downloader /sources/downloads/mpc.tar.gz .
COPY --from=sources-downloader /sources/downloads/mpfr.tar.bz2 .
RUN tar -xf gcc.tar.xz && mv gcc-* gcc
RUN tar -xf gmp.tar.bz2 && mv -v gmp-* gcc/gmp
RUN tar -xf mpc.tar.gz && mv -v mpc-* gcc/mpc
RUN tar -xf mpfr.tar.bz2 && mv -v mpfr-* gcc/mpfr

RUN <<EOT bash
    mkdir -p /sysroot/usr/include
    cd gcc && mkdir -v build && cd build && ../configure --quiet \
        --prefix=/usr \
        --build=${BUILD_ARCH} \
        --host=${TARGET} \
        --target=${TARGET} \
        --with-sysroot=/ \
        --disable-nls \
        --enable-languages=c,c++ \
        --enable-c99 \
        --enable-long-long \
        --disable-libmudflap \
        --disable-multilib \
        --disable-libsanitizer && \
        make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS} -l${MAX_LOAD} && \
        make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS} -l${MAX_LOAD} DESTDIR=/sysroot install ;
EOT

###
### Make
###
FROM stage0 AS make-stage0
ARG JOBS
COPY --from=sources-downloader /sources/downloads/make.tar.gz /sources/

RUN cd /sources && tar -xf make.tar.gz && mv make-* make && \
    cd make && \
    ./configure --quiet --prefix=/usr \
    --build=${BUILD_ARCH} --host=${TARGET} && \
    make -s -j${JOBS} -l${MAX_LOAD} && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/sysroot install


###
### Binutils
###
FROM stage0 AS binutils-stage0
ARG JOBS
COPY --from=sources-downloader /sources/downloads/binutils.tar.xz .
RUN tar -xf binutils.tar.xz && mv binutils-* binutils

RUN <<EOT bash
    cd binutils &&
    ./configure --quiet \
       --prefix=/usr \
       --build=${BUILD_ARCH} \
       --host=${TARGET} \
       --target=${TARGET} \
       --with-sysroot=/ \
       --disable-nls \
       --disable-multilib \
       --enable-shared && \
       make -s -j${JOBS} -l${MAX_LOAD} && \
       make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/sysroot install ;
EOT

FROM make-stage0 AS kernel-headers-stage0
ARG JOBS

COPY --from=sources-downloader /sources/downloads/linux.tar.xz /sources/

WORKDIR /sources
RUN tar -xf linux.tar.xz && mv linux-* kernel
WORKDIR /sources/kernel
# This installs the headers
RUN if [ ${ARCH} = "aarch64" ]; then \
    export ARCH=arm64; \
    else \
    export ARCH=x86_64;\
    fi; make -s -j${JOBS} headers_install INSTALL_HDR_PATH=/linux-headers

########################################################
#
# Stage 1 - Assembling image from stage0 with build tools
#
########################################################

# Here we assemble our building image that we will use to build all the other packages, and assemble again from scratch+skeleton
FROM stage0 AS stage1-merge

COPY --from=skeleton /sysroot /skeleton

## GCC
COPY --from=gcc-stage0 /sysroot /gcc
RUN rsync -aHAX --keep-dirlinks /gcc/. /skeleton

## MUSL
COPY --from=musl-stage0 /sysroot /musl
RUN rsync -aHAX --keep-dirlinks /musl/. /skeleton/

## BUSYBOX
COPY --from=busybox-stage0 /sysroot /busybox
RUN rsync -aHAX --keep-dirlinks /busybox/. /skeleton/

## Make
COPY --from=make-stage0 /sysroot /make
RUN rsync -aHAX --keep-dirlinks /make/. /skeleton/

## Binutils
COPY --from=binutils-stage0 /sysroot /binutils
RUN rsync -aHAX --keep-dirlinks /binutils/. /skeleton/

COPY --from=kernel-headers-stage0 /linux-headers /linux-headers
RUN rsync -aHAX --keep-dirlinks  /linux-headers/. /skeleton/usr/

# Provide ldconfig in the image
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /aports/aports.tar.gz
WORKDIR /aports
RUN tar xf aports.tar.gz && mv aports-* aports
RUN cp aports/main/musl/ldconfig /skeleton/usr/bin/ldconfig && chmod +x /skeleton//usr/bin/ldconfig
## END of HACK

FROM scratch AS stage1

ARG VENDOR="hadron"
ENV VENDOR=${VENDOR}
ARG ARCH="x86-64"
ENV ARCH=${ARCH}
ARG BUILD_ARCH="x86_64"
ARG BUILD_ARCH
ENV BUILD_ARCH=${BUILD_ARCH}
ARG TARGET
ENV TARGET=${BUILD_ARCH}-${VENDOR}-linux-musl
ARG BUILD
ENV BUILD=${BUILD_ARCH}-pc-linux-musl
# Point to GCC wrappers so it understand the lto=auto flags
ENV AR="gcc-ar"
ENV NM="gcc-nm"
ENV RANLIB="gcc-ranlib"
ENV COMMON_CONFIGURE_ARGS="--quiet --prefix=/usr --host=${TARGET} --build=${BUILD} --enable-lto --enable-shared --disable-static"
# Standard aggressive size optimization flags
ENV CFLAGS="-Os -pipe -fomit-frame-pointer -fno-unroll-loops -fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections -flto=auto"
ENV LDFLAGS="-Wl,--gc-sections -Wl,--as-needed -flto=auto"
# TODO: we should set -march=x86-64-v2 to avoid compiling for old CPUs. Save space and its faster.

COPY --from=stage1-merge /skeleton /


# This environment now should be vanilla, ready to build the rest of the system
FROM stage1 AS test1

RUN ls -liah /
RUN gcc --version
RUN make -s --version

# This is a test to check if gcc is working
COPY ./tests/gcc/test.c test.c
RUN gcc -Wall test.c -o test
RUN ./test

########################################################
#
# Stage 1.5 - Building the packages for the final image
#
########################################################

## musl
FROM stage1 AS musl
ARG JOBS

WORKDIR /sources
COPY --from=sources-downloader /sources/downloads/musl.tar.gz /sources
RUN tar -xf musl.tar.gz && mv musl-* musl
WORKDIR /sources/musl
COPY patches/0001-musl-stdio-skipempty-iovec-when-buffering-is-disabled.patch .
RUN patch -p1 < 0001-musl-stdio-skipempty-iovec-when-buffering-is-disabled.patch
# Special flags for musl as its a libc and behaves differently
# drop lto and some optimizations that seems to break stuff
# drop -ffunction-sections/-fdata-sections: limited benefit for libc, risky with linker GC
# drop -march=native: preserves sysroot portability
# drop -fno-plt / -fno-semantic-interposition: avoids subtle ELF interposition issues
ENV CFLAGS="-Os -pipe -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-stack-protector -fno-strict-aliasing"
ENV LDFLAGS="-Wl,--hash-style=both"
RUN ./configure --disable-warnings \
      --prefix=/usr \
      --disable-static && \
      make -s -j${JOBS} && \
      DESTDIR=/sysroot make -s -j${JOBS} -l${MAX_LOAD} install

## pkgconfig
FROM stage1 AS pkgconfig
ARG JOBS
COPY --from=sources-downloader /sources/downloads/pkgconf.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf pkgconf.tar.xz && mv pkgconf-* pkgconfig && \
    cd pkgconfig && mkdir -p /pkgconfig && ./configure --quiet ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --localstatedir=/var \
    --with-pkg-config-dir=/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig && \
    make -s -j${JOBS} -l${MAX_LOAD} && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/pkgconfig install && make -s -j${JOBS} -l${MAX_LOAD} install && ln -s pkgconf /pkgconfig/usr/bin/pkg-config

## xxhash
FROM stage1 AS xxhash
ARG JOBS
COPY --from=sources-downloader /sources/downloads/xxhash.tar.gz /sources/
ENV CC="gcc"
RUN mkdir -p /sources && cd /sources && tar -xf xxhash.tar.gz && mv xxHash-* xxhash && \
    cd xxhash && mkdir -p /xxhash && CC=gcc make -s -j${JOBS} -l${MAX_LOAD} prefix=/usr DESTDIR=/xxhash && \
    make -s -j${JOBS} prefix=/usr -l${MAX_LOAD} DESTDIR=/xxhash install && make -s -j${JOBS} -l${MAX_LOAD} prefix=/usr install

## zstd
FROM xxhash AS zstd
ARG JOBS
COPY --from=sources-downloader /sources/downloads/zstd.tar.gz /sources/
RUN mkdir -p /zstd
WORKDIR /sources
RUN tar -xf zstd.tar.gz && mv zstd-* zstd
WORKDIR /sources/zstd
ENV CC=gcc
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/zstd prefix=/usr
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/zstd prefix=/usr install
RUN make -s -j${JOBS} -l${MAX_LOAD} prefix=/usr install

## lz4
FROM zstd AS lz4
ARG JOBS
COPY --from=sources-downloader /sources/downloads/lz4.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf lz4.tar.gz && mv lz4-* lz4 && \
    cd lz4 && mkdir -p /lz4 && CC=gcc make -s -j${JOBS} -l${MAX_LOAD} prefix=/usr DESTDIR=/lz4 && \
    make -s -j${JOBS} -l${MAX_LOAD} prefix=/usr DESTDIR=/lz4 install && make -s -j${JOBS} -l${MAX_LOAD} prefix=/usr install

## attr
FROM lz4 AS attr
ARG JOBS
COPY --from=sources-downloader /sources/downloads/attr.tar.gz /sources/
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /sources/patches/

RUN mkdir -p /attr

# extract the aport patch to apply to attr
WORKDIR /sources/patches
RUN tar -xf aports.tar.gz && mv aports-* aport
WORKDIR /sources
RUN tar -xf attr.tar.gz && mv attr-* attr
WORKDIR /sources/attr
# TODO: Its fixed on attr master so we can drop this patch when they do a new release
RUN patch -p1 < /sources/patches/aport/main/attr/attr-basename.patch
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --localstatedir=/var \
    --disable-nls
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/attr
RUN make -s -j${JOBS} -l${MAX_LOAD}  DESTDIR=/attr install
RUN make -s -j${JOBS} -l${MAX_LOAD} install

## acl
FROM attr AS acl
ARG JOBS
COPY --from=sources-downloader /sources/downloads/acl.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf acl.tar.gz && mv acl-* acl && \
    cd acl && mkdir -p /acl && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --disable-nls --libexecdir=/usr/libexec && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/acl && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/acl install && make -s -j${JOBS} -l${MAX_LOAD} install

## popt as static as only cryptsetup needs it
FROM acl AS popt
ARG JOBS
COPY --from=sources-downloader /sources/downloads/popt.tar.gz /sources/
RUN cd /sources && \
    tar -xf popt.tar.gz && mv popt-* popt && \
    cd popt && mkdir -p /popt && ./configure  --quiet --prefix=/usr --host=${TARGET} --build=${BUILD} --enable-lto --disable-dependency-tracking --disable-shared --enable-static && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/popt && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/popt install

## zlib
FROM acl AS zlib
ARG JOBS
COPY --from=sources-downloader /sources/downloads/zlib.tar.gz /sources/
RUN mkdir -p /zlib
WORKDIR /sources
RUN tar -xf zlib.tar.gz && mv zlib-* zlib
WORKDIR /sources/zlib
RUN ./configure --shared --prefix=/usr
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/zlib
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/zlib install
RUN make -s -j${JOBS} -l${MAX_LOAD} install

## gawk
FROM zlib AS gawk
ARG JOBS
COPY --from=sources-downloader /sources/downloads/gawk.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf gawk.tar.xz && mv gawk-* gawk && \
    cd gawk && mkdir -p /gawk && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr -sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --disable-nls \
    --disable-pma && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/gawk && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/gawk install && make -s -j${JOBS} -l${MAX_LOAD} install

## rsync
FROM gawk AS rsync
ARG JOBS
COPY --from=sources-downloader /sources/downloads/rsync.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf rsync.tar.gz && mv rsync-* rsync && \
    cd rsync && mkdir -p /rsync && \
    ./configure ${COMMON_CONFIGURE_ARGS} \
    --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --localstatedir=/var \
    --enable-acl-support \
    --enable-xattr-support \
    --disable-roll-simd \
    --enable-xxhash \
    --with-rrsync \
    --without-included-popt \
    --without-included-zlib \
    --disable-md2man \
    --disable-nls \
    --disable-openssl && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/rsync && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/rsync install && make -s -j${JOBS} -l${MAX_LOAD} install

## binutils
FROM stage1 AS binutils
ARG JOBS
COPY --from=sources-downloader /sources/downloads/binutils.tar.xz /sources/
RUN cd /sources && \
    tar -xf binutils.tar.xz && mv binutils-* binutils && \
    cd binutils && mkdir -p /binutils
WORKDIR /sources/binutils
ENV AR=ar
ENV GCC=gcc
ENV AS=as
ENV STRIP=strip
ENV NM=nm
ENV RANLIB=ranlib
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/binutils
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/binutils install
RUN make -s -j${JOBS} -l${MAX_LOAD} install

## m4 (from stage1, ready to be used in the final image)
FROM stage1 AS m4
ARG JOBS
COPY --from=sources-downloader /sources/downloads/m4.tar.xz /sources/
RUN cd /sources && \
    tar -xf m4.tar.xz && mv m4-* m4 && \
    cd m4 && mkdir -p /m4 && ./configure --quiet ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/m4 && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/m4 install && make -s -j${JOBS} -l${MAX_LOAD} install

## readline
FROM stage1 AS readline
ARG JOBS
COPY --from=sources-downloader /sources/downloads/readline.tar.gz /sources/
RUN cd /sources && \
    tar -xf readline.tar.gz && mv readline-* readline && \
    cd readline && mkdir -p /readline && ./configure --quiet ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/readline && \
    make -s -j${JOBS} DESTDIR=/readline install && make -s -j${JOBS} install
## flex
FROM m4 AS flex
ARG JOBS
COPY --from=sources-downloader /sources/downloads/flex.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf flex.tar.gz && mv flex-* flex && cd flex && mkdir -p /flex && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --infodir=/usr/share/info --mandir=/usr/share/man --prefix=/usr --disable-static --enable-shared ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes && \
    make -j${JOBS} -l${MAX_LOAD} DESTDIR=/flex install && make -j${JOBS} -l${MAX_LOAD} install && ln -s flex /flex/usr/bin/lex

## perl
FROM m4 AS perl
ARG JOBS
ENV CFLAGS="${CFLAGS} -static -ffunction-sections -fdata-sections -Bsymbolic-functions"
ENV LDFLAGS="-Wl,--gc-sections"
ENV PERL_CROSS=1.6.2
COPY --from=sources-downloader /sources/downloads/perl.tar.xz /sources/
RUN cd /sources && \
    tar -xf perl.tar.xz && mv perl-* perl && \
    cd perl && \
       ln -s /usr/bin/gcc /usr/bin/cc && ./Configure -s -des -Dprefix=/usr -Dcccdlflags='-fPIC' \
       -Dccdlflags='-rdynamic' \
       -Dprivlib=/usr/share/perl5/core_perl \
       -Darchlib=/usr/lib/perl5/core_perl \
       -Dvendorprefix=/usr \
       -Dvendorlib=/usr/share/perl5/vendor_perl \
       -Dvendorarch=/usr/lib/perl5/vendor_perl \
       -Dsiteprefix=/usr/local \
       -Dsitelib=/usr/local/share/perl5/site_perl \
       -Dsitearch=/usr/local/lib/perl5/site_perl \
       -Dlocincpth=' ' \
       -Doptimize="-flto=auto -O2" \
       -Duselargefiles \
       -Dusethreads \
       -Duseshrplib \
       -Dd_semctl_semun \
       -Dman1dir=/usr/share/man/man1 \
       -Dman3dir=/usr/share/man/man3 \
       -Dinstallman1dir=/usr/share/man/man1 \
       -Dinstallman3dir=/usr/share/man/man3 \
       -Dman1ext='1' \
       -Dman3ext='3pm' \
       -Dcf_by='hadron' \
       -Dcf_email='mudler@kairos.io' \
       -Ud_csh \
       -Ud_fpos64_t \
       -Ud_off64_t \
       -Dusenm \
       -Duse64bitint && make -s -j${JOBS} libperl.so && \
        make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/perl && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/perl install && make -s -j${JOBS} -l${MAX_LOAD} install

## bison
FROM rsync AS bison
ARG JOBS
COPY --from=flex /flex /flex
RUN rsync -aHAX --keep-dirlinks  /flex/. /

COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=sources-downloader /sources/downloads/bison.tar.xz /sources/
RUN mkdir -p /sources && cd /sources && tar -xvf bison.tar.xz && mv bison-* bison && cd bison && mkdir -p /bison && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --infodir=/usr/share/info --mandir=/usr/share/man --prefix=/usr --disable-static --enable-shared && \
    make -j${JOBS} -l${MAX_LOAD} DESTDIR=/bison install && make -j${JOBS} -l${MAX_LOAD} install

## bash
FROM readline AS bash
ARG JOBS
COPY --from=bison /bison /
COPY --from=flex /flex /

COPY ./files/bash/bashrc /sources/bashrc
COPY ./files/bash/profile-bashrc.sh /sources/profile-bashrc.sh
COPY --from=sources-downloader /sources/downloads/bash /sources/bash
# If NON_INTERACTIVE_LOGIN_SHELLS is defined, all login shells read the
# startup files, even if they are not interactive.
# This makes something like ssh user@host 'command' work as expected, otherwise you would get
# an error saying that its not a tty
# bash_cv_getcwd_malloc=yes avoids bash using its own getcwd which is broken under overlays
# bash_cv_job_control_missing=no avoids bash thinking that job control is missing in some environments
# bash_cv_sys_named_pipes=no avoids bash thinking that named pipes are broken in some environments
# bash_cv_printf_a_format=yes avoids issues with bash printf implementation
# This settings are enabled by a test which doesnt run when cross compiling so we have to enable them manually
ENV CFLAGS="${CFLAGS} -DNON_INTERACTIVE_LOGIN_SHELLS -DSSH_SOURCE_BASHRC"
RUN mkdir -p /bash
WORKDIR /sources/bash
RUN CFLAGS="${CFLAGS}" ./configure --quiet ${COMMON_CONFIGURE_ARGS} \
    --build=${BUILD} \
    --host=${TARGET} \
    --prefix=/usr \
    --bindir=/bin \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --disable-nls \
    --enable-readline \
    --without-bash-malloc \
    --with-installed-readline \
    bash_cv_getcwd_malloc=yes \
    bash_cv_job_control_missing=nomissing \
    bash_cv_sys_named_pipes=nomissing \
    bash_cv_printf_a_format=yes
RUN make -s -j${JOBS} y.tab.c && make -s -j${JOBS} -l${MAX_LOAD} builtins/libbuiltins.a && make -s -j${JOBS} -l${MAX_LOAD}
RUN mkdir -p /bash/etc/bash
RUN install -Dm644  /sources/bashrc /bash/etc/bash.bashrc
RUN install -Dm644  /sources/profile-bashrc.sh /bash/etc/profile.d/00-bashrc.sh
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/bash install && make -s -j${JOBS} -l${MAX_LOAD} install

## libcap
FROM bash AS libcap
ARG JOBS
COPY --from=sources-downloader /sources/downloads/libcap.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf libcap.tar.xz && mv libcap-* libcap && \
    cd libcap && mkdir -p /libcap && make -s -j${JOBS} -l${MAX_LOAD} BUILD_CC=gcc CC="${CC:-gcc}" && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/libcap PAM_LIBDIR=/lib prefix=/usr SBINDIR=/sbin lib=lib RAISE_SETFCAP=no GOLANG=no install && make -s -j${JOBS} -l${MAX_LOAD} GOLANG=no PAM_LIBDIR=/lib lib=lib prefix=/usr SBINDIR=/sbin RAISE_SETFCAP=no install

## openssl
FROM rsync AS openssl-no-fips
ARG JOBS
COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /

COPY --from=sources-downloader /sources/downloads/openssl.tar.gz /sources/
WORKDIR /sources
RUN tar -xf openssl.tar.gz && mv openssl-* openssl
WORKDIR /sources/openssl
RUN ./Configure --prefix=/usr         \
    --openssldir=/etc/ssl \
    --libdir=lib          \
    shared zlib-dynamic \
    no-ssl3 no-weak-ssl-ciphers no-comp \
    no-md2 no-md4 no-mdc2 no-whirlpool \
    no-rc2 no-rc4 no-idea no-seed no-cast no-bf \
    no-tests no-unit-test no-external-tests no-docs \
    no-ui-console no-afalgeng no-capieng
RUN make -s -j${JOBS} DESTDIR=/openssl 2>&1
RUN make -s -j${JOBS} DESTDIR=/openssl install_sw install_ssldirs && make -s -j${JOBS} -l${MAX_LOAD} install_sw install_ssldirs

FROM rsync AS openssl-fips

ARG JOBS
COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /

COPY --from=sources-downloader /sources/downloads/openssl-fips.tar.gz /sources/
WORKDIR /sources
RUN tar -xf openssl-fips.tar.gz && rm openssl-fips.tar.gz && mv openssl-* openssl-fips
WORKDIR /sources/openssl-fips
RUN ./Configure --prefix=/usr         \
    --openssldir=/etc/ssl \
    --libdir=lib          \
    enable-fips \
    enable-ktls \
    shared \
    no-async \
    no-comp \
    no-idea \
    no-mdc2 \
    no-rc5 \
    no-ec2m \
    no-ssl3 \
    no-seed \
    no-weak-ssl-ciphers \
    zlib-dynamic \
     2>&1
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/openssl 2>&1
RUN ./util/wrap.pl -fips apps/openssl list -provider-path providers -provider fips -providers | grep -A3 FIPS| grep -q active
RUN make -j${JOBS} -l${MAX_LOAD} DESTDIR=/openssl install_sw install_ssldirs
RUN make -j${JOBS} -l${MAX_LOAD} DESTDIR=/openssl install_fips
COPY ./files/openssl/openssl.cnf.fips /openssl/etc/ssl/openssl.cnf

FROM openssl-${FIPS} AS openssl

## Busybox from scratch, minimalist build for final image
## with a tiny config as we have other tools
FROM stage1 AS busybox
ARG JOBS
# Drop lto from busybox build as its causing issues in some environments
ENV CFLAGS="${CFLAGS//-flto=auto/}"

COPY --from=sources-downloader /sources/downloads/busybox.tar.bz2 /sources/
WORKDIR /sources
RUN rm -rfv busybox && tar -xf busybox.tar.bz2 && mv busybox-* busybox
WORKDIR /sources/busybox
RUN make -s distclean
COPY ./files/busybox/minimal.config .config
RUN make -j${JOBS} -l${MAX_LOAD} silentoldconfig
RUN make -s -j${JOBS} -l${MAX_LOAD} CONFIG_PREFIX="/sysroot" install
RUN make -s -j${JOBS} -l${MAX_LOAD} install

## coreutils
FROM rsync AS coreutils
ARG JOBS
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=sources-downloader /sources/downloads/coreutils.tar.xz /sources/
RUN cd /sources && \
    tar -xf coreutils.tar.xz && mv coreutils-* coreutils && \
    cd coreutils && mkdir -p /coreutils && ./configure ${COMMON_CONFIGURE_ARGS} \
    --prefix=/usr \
    --bindir=/bin \
    --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --disable-nls \
    --enable-install-program=hostname,su,env \
    --enable-single-binary=symlinks \
    --enable-single-binary-exceptions=env,fmt,sha512sum \
    --with-openssl \
    --disable-dependency-tracking && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/coreutils && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/coreutils install

## findutils
FROM stage1 AS findutils
ARG JOBS
COPY --from=sources-downloader /sources/downloads/findutils.tar.xz /sources/
RUN cd /sources && \
    tar -xf findutils.tar.xz && mv findutils-* findutils && \
    cd findutils && mkdir -p /findutils && ./configure ${COMMON_CONFIGURE_ARGS} --disable-nls --disable-dependency-tracking && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/findutils && \
    make -s -j${JOBS} DESTDIR=/findutils install && make -s -j${JOBS} install

## grep
FROM stage1 AS grep
ARG JOBS
COPY --from=sources-downloader /sources/downloads/grep.tar.xz /sources/
RUN cd /sources && \
    tar -xf grep.tar.xz && mv grep-* grep && \
    cd grep && mkdir -p /grep && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/grep && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/grep install && make -s -j${JOBS} -l${MAX_LOAD} install

## ca-certificates
FROM rsync AS ca-certificates
ARG JOBS
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /

## readline
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /

## acl
COPY --from=acl /acl /acl
RUN rsync -aHAX --keep-dirlinks  /acl/. /

## attr
COPY --from=attr /attr /attr
RUN rsync -aHAX --keep-dirlinks  /attr/. /

## findutils
COPY --from=findutils /findutils /findutils
RUN rsync -aHAX --keep-dirlinks  /findutils/. /

COPY --from=sources-downloader /sources/downloads/ca-certificates.tar.bz2 /sources/

RUN mkdir -p /sources && cd /sources && tar -xf ca-certificates.tar.bz2 && mv ca-certificates-* ca-certificates && \
    cd ca-certificates && mkdir -p /ca-certificates && CC=gcc make -s -j${JOBS} -l${MAX_LOAD} && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/ca-certificates install

COPY ./files/ca-certificates/post_install.sh /sources/post_install.sh
RUN bash /sources/post_install.sh

## sqlite3 
FROM rsync AS sqlite3
ARG JOBS
ENV CFLAGS="${CFLAGS//-Os/-O2} -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_UNLOCK_NOTIFY 	-DSQLITE_ENABLE_RTREE 	-DSQLITE_ENABLE_GEOPOLY 	-DSQLITE_USE_URI 	-DSQLITE_ENABLE_DBSTAT_VTAB 	-DSQLITE_SOUNDEX 	-DSQLITE_MAX_VARIABLE_NUMBER=250000"

COPY --from=sources-downloader /sources/downloads/sqlite3.tar.gz /sources/
# remove lto flag from sqlite as it causes issues with linking later
ENV COMMON_CONFIGURE_ARGS="${COMMON_CONFIGURE_ARGS//--enable-lto/}"
RUN mkdir -p /sources && cd /sources && tar -xf sqlite3.tar.gz && \
    mv sqlite-* sqlite3 && \
    cd sqlite3 && mkdir -p /sqlite3 && ./configure ${COMMON_CONFIGURE_ARGS} \
		--enable-threadsafe \
		--enable-session \
		--enable-static \
		--enable-fts3 \
		--enable-fts4 \
		--enable-fts5 \
		--soname=legacy && \
    make -s -j${JOBS} -l${MAX_LOAD} && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/sqlite3 install && make -s -j${JOBS} -l${MAX_LOAD} install

## curl
FROM rsync AS curl
ARG JOBS
COPY --from=ca-certificates /ca-certificates /ca-certificates
RUN rsync -aHAX --keep-dirlinks  /ca-certificates/. /

COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=zstd /zstd /zstd
RUN rsync -aHAX --keep-dirlinks  /zstd/. /

COPY --from=sources-downloader /sources/downloads/curl.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf curl.tar.gz && mv curl-* curl && \
    cd curl && mkdir -p /curl && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --enable-ipv6 \
    --enable-unix-sockets \
    --enable-static \
    --without-libidn2 \
    --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
    --with-ca-path=/etc/ssl/certs \
    --with-zsh-functions-dir \
    --with-fish-functions-dir \
    --disable-ldap \
    --with-pic \
    --enable-websockets \
    --without-libssh2 \
    --with-ssl \
    --with-nghttp2 \
    --disable-ldap \
    --with-pic \
    --without-libpsl \
    --without-libssh2 && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/curl && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/curl install && make -s -j${JOBS} -l${MAX_LOAD} install

FROM rsync AS libffi
ARG JOBS
COPY --from=sources-downloader /sources/downloads/libffi.tar.gz /sources/
RUN mkdir -p /libffi
WORKDIR /sources
RUN tar -xf libffi.tar.gz && mv libffi-* libffi
WORKDIR /sources/libffi
# --disable-multi-os-directory makes sure we dont install the libs under /usr/lib64
# https://github.com/libffi/libffi/issues/127
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-docs --libdir=/usr/lib --disable-multi-os-directory
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libffi

## python
FROM rsync AS python-build
ARG JOBS
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /

COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /

COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /

COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /

COPY --from=libffi /libffi /libffi
RUN rsync -aHAX --keep-dirlinks  /libffi/. /

COPY --from=sources-downloader /sources/downloads/Python.tar.xz /sources/

RUN rm /bin/sh && ln -s /bin/bash /bin/sh && mkdir -p /sources && cd /sources && tar -xf Python.tar.xz && mv Python-* python && \
    cd python && mkdir -p /python
WORKDIR /sources/python
RUN ./configure --quiet --prefix=/usr \
    --enable-ipv6 \
    --enable-loadable-sqlite-extensions \
    --enable-shared \
    --with-ensurepip=install \
    --with-computed-gotos \
    --disable-test-modules \
    --with-dbmliborder=gdbm:ndbm
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/python
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/python install
RUN make -s -j${JOBS} -l${MAX_LOAD} install 2>&1


## util-linux
FROM bash AS util-linux

COPY --from=sources-downloader /sources/downloads/util-linux.tar.xz /sources/

RUN rm /bin/sh && ln -s /bin/bash /bin/sh && mkdir -p /sources && cd /sources && tar -xf util-linux.tar.xz && \
    mv util-linux-* util-linux && \
    cd util-linux && mkdir -p /util-linux && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking  --prefix=/usr \
    --libdir=/usr/lib \
    --disable-silent-rules \
    --enable-newgrp \
    --disable-uuidd \
    --disable-liblastlog2 \
    --disable-nls \
    --disable-kill \
    --disable-chfn-chsh \
    --with-vendordir=/usr/lib \
    --enable-fs-paths-extra=/usr/sbin \
    --disable-pam-lastlog2 \
    --disable-asciidoc \
    --disable-poman \
    --disable-minix \
    --disable-cramfs \
    --disable-bfs \
    --without-python \
    --with-sysusersdir=/usr/lib/sysusers.d/ \
    && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/util-linux && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/util-linux install && make -s -j${JOBS} -l${MAX_LOAD} install

## gperf
FROM stage1 AS gperf
ARG JOBS
COPY --from=sources-downloader /sources/downloads/gperf.tar.gz /sources/
RUN cd /sources && \
    tar -xf gperf.tar.gz && mv gperf-* gperf && \
    cd gperf && mkdir -p /gperf && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr && \
    make -s -j${JOBS} -l${MAX_LOAD} BUILD_CC=gcc CC="${CC:-gcc}" lib=lib prefix=/usr GOLANG=no DESTDIR=/gperf && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/gperf install && make -s -j${JOBS} -l${MAX_LOAD} install

## libseccomp for k8s stuff mainly
FROM rsync AS libseccomp
ARG JOBS
COPY --from=gperf /gperf /gperf
RUN rsync -aHAX --keep-dirlinks  /gperf/. /
COPY --from=sources-downloader /sources/downloads/libseccomp.tar.gz /sources/
RUN mkdir -p /libseccomp
WORKDIR /sources
RUN tar -xf libseccomp.tar.gz && mv libseccomp-* libseccomp
WORKDIR /sources/libseccomp
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libseccomp


## expat
FROM bash AS expat
ARG JOBS
## Force bash as shell otherwise it defaults to /bin/sh and fails
RUN rm /bin/sh && ln -s /bin/bash /bin/sh
COPY --from=sources-downloader /sources/downloads/expat.tar.gz /sources/
RUN mkdir -p /expat
WORKDIR /sources
RUN tar -xf expat.tar.gz && mv expat-* expat
WORKDIR /sources/expat
RUN bash ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/expat

FROM stage0 AS gdb-stage0
ARG JOBS
RUN mkdir -p /gdb
WORKDIR /sources
COPY --from=sources-downloader /sources/downloads/gdb.tar.gz .
COPY --from=sources-downloader /sources/downloads/gmp.tar.bz2 .
COPY --from=sources-downloader /sources/downloads/mpfr.tar.bz2 .
COPY --from=sources-downloader /sources/downloads/mpc.tar.gz .
COPY --from=expat /expat /
COPY --from=python-build /python /

RUN tar -xf gmp.tar.bz2
RUN tar -xf mpfr.tar.bz2
RUN tar -xf gdb.tar.gz && mv gdb-* gdb
RUN tar -xf mpc.tar.gz
RUN mv -v mpfr-* gdb/mpfr
RUN mv -v gmp-* gdb/gmp
RUN mv -v mpc-* gdb/mpc
WORKDIR /sources/gdb
RUN ./configure --quiet ${COMMON_CONFIGURE_ARGS} \
    --host=${TARGET}  AR=${TARGET}-ar RANLIB=${TARGET}-ranlib NM=${TARGET}-nm CC=${TARGET}-gcc LD=${TARGET}-ld STRIP=${TARGET}-strip \
    --with-sysroot=/ \
    --disable-nls \
    --with-libexpat-prefix=/usr \
    --disable-multilib
RUN make -j${JOBS} -l${MAX_LOAD}
RUN make -j${JOBS} -l${MAX_LOAD} DESTDIR=/gdb install install-gdbserver


## dbus first pass without systemd support so we can build systemd afterwards
FROM python-build AS dbus
ARG JOBS
COPY --from=expat /expat /expat
RUN rsync -aHAX --keep-dirlinks  /expat/. /
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=sources-downloader /sources/downloads/dbus.tar.xz /sources/
# install target
RUN mkdir -p /dbus
WORKDIR /sources
RUN pip3 install meson ninja
RUN tar -xf dbus.tar.xz && mv dbus-* dbus
WORKDIR /sources/dbus
RUN meson setup buildDir --prefix=/usr --buildtype=minsize -Dstrip=true
RUN DESTDIR=/dbus ninja -j${JOBS} -C buildDir install


# first pam build so we can build systemd against it
FROM python-build AS pam
ARG JOBS
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=sources-downloader /sources/downloads/pam.tar.xz /sources/
RUN mkdir -p /pam
WORKDIR /sources
RUN tar -xf pam.tar.xz && mv Linux-PAM-* linux-pam
WORKDIR /sources/linux-pam
RUN pip3 install meson ninja
RUN meson setup buildDir --prefix=/usr --buildtype=minsize -Dstrip=true
RUN DESTDIR=/pam ninja -j${JOBS} -C buildDir install
COPY files/pam/* /pam/etc/pam.d/


# shadow-base only deps
FROM rsync AS shadow-base
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /


# Shadow with PAM support, no systemd
FROM shadow-base AS shadow
ARG JOBS
COPY --from=pam /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /
COPY --from=sources-downloader /sources/downloads/shadow.tar.xz /sources/
RUN mkdir -p /shadow
WORKDIR /sources
RUN tar -xf shadow.tar.xz && mv shadow-* shadow
WORKDIR /sources/shadow
# --disable-logind disables building with systemd logind support. This is for the base shadow build without systemd
RUN ./configure ${COMMON_CONFIGURE_ARGS} --sysconfdir=/etc --without-libbsd --disable-nls --disable-logind
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} exec_prefix=/usr pamddir= install DESTDIR=/shadow && make exec_prefix=/usr pamddir= -s -j${JOBS} -l${MAX_LOAD} install


## openssh
## TODO: if we want a separate user for sshd we can drop a file onto /usr/lib/sysusers.d/sshd.conf
## with:
# u sshd - "sshd priv user"
## And enable --with-privsep-user=sshd during configure
FROM rsync AS openssh
ARG JOBS
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /

COPY --from=pam /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /

COPY --from=shadow /shadow /shadow

COPY --from=sources-downloader /sources/downloads/openssh.tar.gz /sources/

RUN mkdir -p /openssh
WORKDIR /sources
RUN tar -xf openssh.tar.gz && mv openssh-* openssh

WORKDIR /sources/openssh
RUN ./configure ${COMMON_CONFIGURE_ARGS} \
    --prefix=/usr \
    --sysconfdir=/etc/ssh \
    --libexecdir=/usr/lib/ssh \
    --datadir=/usr/share/openssh \
    --with-privsep-path=/var/empty \
    --with-privsep-user=nobody \
    --with-md5-passwords \
    --with-ssl-engine \
    --with-pam --disable-lastlog --disable-utmp --disable-wtmp --disable-utmpx --disable-wtmpx

RUN make -s -j${JOBS} -l${MAX_LOAD}
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/openssh install
RUN make -s -j${JOBS} -l${MAX_LOAD} install
## Provide the proper files and dirs for sshd to run properly with systemd
COPY files/systemd/sshd.service /openssh/usr/lib/systemd/system/sshd.service
COPY files/systemd/sshkeygen.service /openssh/usr/lib/systemd/system/sshkeygen.service
# Add sshd_config.d dir for droping extra configs
RUN mkdir -p /openssh/etc/ssh/sshd_config.d
RUN echo "# Include drop-in configs from sshd_config.d directory" >> /openssh/etc/ssh/sshd_config
RUN echo "Include sshd_config.d/*.conf" >> /openssh/etc/ssh/sshd_config
# Add Hadron config with enabled pam
RUN echo "# Hadron specific sshd config" >> /openssh/etc/ssh/sshd_config.d/99-hadron.conf
RUN echo "UsePAM yes" >> /openssh/etc/ssh/sshd_config.d/99-hadron.conf


## xz and liblzma
FROM rsync AS xz
ARG JOBS
COPY --from=sources-downloader /sources/downloads/xz.tar.gz /sources/
RUN mkdir -p /xz
WORKDIR /sources
RUN tar -xf xz.tar.gz && mv xz-* xz
WORKDIR /sources/xz
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-nls --disable-doc --enable-small --disable-scripts
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/xz && make -s -j${JOBS} -l${MAX_LOAD} install

# gzip at least for the toolchain
FROM rsync AS gzip
ARG JOBS
COPY --from=sources-downloader /sources/downloads/gzip.tar.xz /sources/
RUN mkdir -p /gzip
WORKDIR /sources
RUN tar -xf gzip.tar.xz && mv gzip-* gzip
WORKDIR /sources/gzip
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking
RUN make -j${JOBS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make install DESTDIR=/gzip


## kmod so modprobe, insmod, lsmod, modinfo, rmmod are available
FROM python-build AS kmod
ARG JOBS
## we need liblzma from xz to build
COPY --from=xz /xz /xz
RUN rsync -aHAX --keep-dirlinks  /xz/. /

## Override ln so the install works
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /

COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /


COPY --from=sources-downloader /sources/downloads/kmod.tar.gz /sources/
RUN mkdir -p /kmod
WORKDIR /sources
RUN tar -xf kmod.tar.gz && mv kmod-* kmod
WORKDIR /sources/kmod
RUN pip3 install meson ninja
RUN meson setup buildDir --prefix=/usr --buildtype=minsize -Dmanpages=false
RUN DESTDIR=/kmod ninja -j${JOBS} -C buildDir install && ninja -j${JOBS} -C buildDir install


## autoconf
FROM rsync AS autoconf
ARG JOBS
COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /


COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=sources-downloader /sources/downloads/autoconf.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf autoconf.tar.xz && mv autoconf-* autoconf && \
    cd autoconf && mkdir -p /autoconf && ./configure ${COMMON_CONFIGURE_ARGS} --prefix=/usr && make DESTDIR=/autoconf && \
    make -j${JOBS} -l${MAX_LOAD} DESTDIR=/autoconf install && make -j${JOBS} -l${MAX_LOAD} install


## automake
FROM rsync AS automake
ARG JOBS
COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=autoconf /autoconf /autoconf
RUN rsync -aHAX --keep-dirlinks  /autoconf/. /

COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=sources-downloader /sources/downloads/automake.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf automake.tar.xz && mv automake-* automake && \
    cd automake && mkdir -p /automake && ./configure ${COMMON_CONFIGURE_ARGS} --prefix=/usr && make DESTDIR=/automake && \
    make -j${JOBS} -l${MAX_LOAD} DESTDIR=/automake install && make -j${JOBS} -l${MAX_LOAD} install


## libtool
FROM rsync AS libtool
ARG JOBS
COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=sources-downloader /sources/downloads/libtool.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf libtool.tar.xz && mv libtool-* libtool && cd libtool && mkdir -p /libtool && sed -i \
-e "s|test-funclib-quote.sh||" \
-e "s|test-option-parser.sh||" \
gnulib-tests/Makefile.in && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --disable-static --enable-shared && \
    make -j${JOBS} -l${MAX_LOAD} DESTDIR=/libtool install && make -j${JOBS} -l${MAX_LOAD} install

## fts
## fts is only needed to build dracut as it needs libfts.so
## This is only needed during build time so we can drop it later
FROM rsync AS fts
ARG JOBS
ENV CFLAGS="$CFLAGS -fPIC"

COPY --from=autoconf /autoconf /autoconf
RUN rsync -aHAX --keep-dirlinks  /autoconf/. /

COPY --from=automake /automake /automake
RUN rsync -aHAX --keep-dirlinks  /automake/. /

COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=libtool /libtool /libtool
RUN rsync -aHAX --keep-dirlinks  /libtool/. /

COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /

COPY --from=sources-downloader /sources/downloads/musl-fts.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf musl-fts.tar.gz && mv musl-fts-* fts && cd fts && mkdir -p /fts && ./bootstrap.sh && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --disable-static --enable-shared --localstatedir=/var --mandir=/usr/share/man  --sysconfdir=/etc  && \
    make -j${JOBS} -l${MAX_LOAD} DESTDIR=/fts install && make -j${JOBS} -l${MAX_LOAD} install &&  cp musl-fts.pc /fts/usr/lib/pkgconfig/libfts.pc

## libelf is the only part from elfutils that we need to build the kernel
# basically gelf.h and elf.h
FROM rsync AS libelf
ARG JOBS

COPY --from=sources-downloader /sources/downloads/libelf.tar.gz /sources/

WORKDIR /sources
RUN tar -xf libelf.tar.gz && mv libelf-* libelf
WORKDIR /sources/libelf
RUN make -j${JOBS} PREFIX=/usr DESTDIR=/libelf
RUN make -j${JOBS} PREFIX=/usr DESTDIR=/libelf install-headers install-shared


FROM rsync AS diffutils
ARG JOBS
RUN mkdir -p /diffutils
COPY --from=sources-downloader /sources/downloads/diffutils.tar.xz /sources/
COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /
WORKDIR /sources
RUN tar xf diffutils.tar.xz && mv diffutils-* diffutils
WORKDIR /sources/diffutils
# define nullptr for older gcc versions
ENV CFLAGS="${CFLAGS:-} -Dnullptr=NULL"
# Set HOST to TARGET for cross compiling to avoid it trying to run tests
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --libdir=/usr/lib --host=${HOST}
RUN make -s -j${JOBS} -l${MAX_LOAD} BUILD_CC=gcc CC="${CC:-gcc}" lib=lib prefix=/usr GOLANG=no DESTDIR=/diffutils
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/diffutils install
RUN make -s -j${JOBS} -l${MAX_LOAD} install

FROM rsync AS libkcapi
ARG JOBS
COPY --from=autoconf /autoconf /autoconf
RUN rsync -aHAX --keep-dirlinks  /autoconf/. /
COPY --from=automake /automake /automake
RUN rsync -aHAX --keep-dirlinks  /automake/. /
COPY --from=libtool /libtool /libtool
RUN rsync -aHAX --keep-dirlinks  /libtool/. /
COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /
COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=sources-downloader /sources/downloads/libkcapi.tar.gz /sources/
RUN mkdir -p /libkcapi
WORKDIR /sources
RUN tar -xf libkcapi.tar.gz && mv libkcapi-* libkcapi
WORKDIR /sources/libkcapi
RUN autoreconf -i
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --disable-static --enable-shared --disable-werror --enable-kcapi-hasher --disable-lib-kdf --disable-lib-sym --disable-lib-aead --disable-lib-rng
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install LIBDIR=lib BINDIR=/bin DESTDIR=/libkcapi
RUN ln -s kcapi-hasher /libkcapi/usr/bin/sha512hmac
RUN rm -Rf /libkcapi/usr/share /libkcapi/usr/lib/pkgconfig /libkcapi/usr/include /libkcapi/usr/libexec /libkcapi/usr/lib/*.la
## kernel
FROM rsync AS kernel-base
ARG JOBS
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /

COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /

COPY --from=flex /flex /flex
RUN rsync -aHAX --keep-dirlinks  /flex/. /

COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=bison /bison /bison
RUN rsync -aHAX --keep-dirlinks  /bison/. /

COPY --from=libelf /libelf /libelf
RUN rsync -aHAX --keep-dirlinks  /libelf/. /

COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=gawk /gawk /gawk
RUN rsync -aHAX --keep-dirlinks  /gawk/. /

COPY --from=findutils /findutils /findutils
RUN rsync -aHAX --keep-dirlinks  /findutils/. /

COPY --from=diffutils /diffutils /diffutils
RUN rsync -aHAX --keep-dirlinks  /diffutils/. /

COPY --from=sources-downloader /sources/downloads/linux.tar.xz /sources/

RUN mkdir -p /sources/kernel-configs
COPY ./files/kernel/* /sources/kernel-configs/

RUN mkdir -p /kernel && mkdir -p /modules

WORKDIR /sources
RUN tar -xf linux.tar.xz && mv linux-* kernel


FROM kernel-base AS kernel-cloud
WORKDIR /sources/kernel
RUN if [ ${ARCH} = "aarch64" ] ; then \
    cp -rfv /sources/kernel-configs/cloud-arm64.config .config ; \
    else \
    cp -rfv /sources/kernel-configs/cloud.config .config ; \
    fi

FROM kernel-base AS kernel-default
WORKDIR /sources/kernel
RUN if [ ${ARCH} = "aarch64" ] ; then \
    cp -rfv /sources/kernel-configs/default-arm64.config .config ; \
    else \
    cp -rfv /sources/kernel-configs/default.config .config ; \
    fi

FROM kernel-${KERNEL_TYPE} AS kernel-build
ARG JOBS
WORKDIR /sources/kernel
# This only builds the kernel
RUN if [ ${ARCH} = "aarch64" ]; then \
    ARCH=arm64 make -s -j${JOBS} -l${MAX_LOAD} Image; \
    else \
    ARCH=x86_64 make -s -j${JOBS} -l${MAX_LOAD} bzImage; \
    fi
RUN if [ ${ARCH} = "aarch64" ]; then \
    export ARCH=arm64; \
    else \
    export ARCH=x86_64;\
    fi;  make -s -j${JOBS} kernelrelease > /kernel/kernel-version
RUN if [ ${ARCH} = "aarch64" ]; then \
    ARCH=arm64 kver=$(cat /kernel/kernel-version) && cp arch/$ARCH/boot/Image /kernel/vmlinuz-${kver}; \
    else \
    ARCH=x86_64 kver=$(cat /kernel/kernel-version) && cp arch/$ARCH/boot/bzImage /kernel/vmlinuz-${kver};\
    fi
# link vmlinuz to our kernel
RUN ln -sfv /kernel/vmlinuz-$(cat /kernel/kernel-version) /kernel/vmlinuz

FROM kernel-build AS kernel-no-fips
# Nothing to do here, just a placeholder


# This will generate the needed FIPS HMAC for the kernel so dracut can verify it
FROM kernel-build AS kernel-fips
WORKDIR /sources/
COPY --from=libkcapi /libkcapi /libkcapi
RUN rsync -aHAX --keep-dirlinks  /libkcapi/. /
# Use generate the HMAC for the kernel, make sure to set the path to the runtime path
RUN kver=$(cat /kernel/kernel-version) && sha512hmac /kernel/vmlinuz-${kver} | sed 's|  /kernel/|  /boot/|' > /kernel/.vmlinuz-${kver}.hmac
RUN kver=$(cat /kernel/kernel-version) && chmod 0644 /kernel/.vmlinuz-${kver}.hmac

FROM kernel-${FIPS} AS kernel

FROM kernel-build AS kernel-modules
# This builds the modules
RUN if [ ${ARCH} = "aarch64" ]; then \
    export ARCH=arm64; \
    else \
    export ARCH=x86_64;\
    fi;  make -s -j${JOBS} -l${MAX_LOAD} modules
RUN if [ ${ARCH} = "aarch64" ]; then \
    export ARCH=arm64; \
    else \
    export ARCH=x86_64;\
    fi;  ZSTD_CLEVEL=19 INSTALL_MOD_PATH="/modules" INSTALL_MOD_STRIP=1 DEPMOD=true make -s -j${JOBS} -l${MAX_LOAD} modules_install

FROM kernel-base AS kernel-headers
ARG JOBS
WORKDIR /sources/kernel
# This installs the headers
RUN if [ ${ARCH} = "aarch64" ]; then \
    export ARCH=arm64; \
    else \
    export ARCH=x86_64;\
    fi; make -s -j${JOBS} -l${MAX_LOAD} headers_install INSTALL_HDR_PATH=/linux-headers

## kbd for setting the console keymap and font
FROM rsync AS kbd
ARG JOBS
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /

# Use coreutils for install as it needs ln to support relative symlinks
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /
# Use openssl for libssl and libcrypto
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=sources-downloader /sources/downloads/kbd.tar.gz /sources/
RUN mkdir -p /kbd
WORKDIR /sources
RUN tar -xf kbd.tar.gz && mv kbd-* kbd
WORKDIR /sources/kbd
RUN ./configure --quiet --prefix=/usr --disable-tests --disable-vlock -enable-libkeymap --enable-libkfont --disable-nls
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/kbd

## strace
FROM rsync AS strace
ARG JOBS
COPY --from=gawk /gawk /gawk
RUN rsync -aHAX --keep-dirlinks  /gawk/. /
COPY --from=sources-downloader /sources/downloads/strace.tar.xz /sources/
RUN mkdir -p /strace
WORKDIR /sources
RUN tar -xf strace.tar.xz && mv strace-* strace
WORKDIR /sources/strace
RUN ./configure ${COMMON_CONFIGURE_ARGS} --enable-mpers=check
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/strace

## libmnl
FROM rsync AS libmnl
ARG JOBS
COPY --from=sources-downloader /sources/downloads/libmnl.tar.bz2 /sources/
RUN mkdir -p /libmnl
WORKDIR /sources
RUN tar -xf libmnl.tar.bz2 && mv libmnl-* libmnl
WORKDIR /sources/libmnl
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libmnl

## libnftnl
FROM rsync AS libnftnl
ARG JOBS
COPY --from=libmnl /libmnl /libmnl
RUN rsync -aHAX --keep-dirlinks  /libmnl/. /
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=sources-downloader /sources/downloads/libnftnl.tar.xz /sources/
RUN mkdir -p /libnftnl
WORKDIR /sources
RUN tar -xf libnftnl.tar.xz && mv libnftnl-* libnftnl
WORKDIR /sources/libnftnl
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libnftnl

## iptables
FROM rsync AS iptables
ARG JOBS
COPY --from=libmnl /libmnl /libmnl
RUN rsync -aHAX --keep-dirlinks  /libmnl/. /
COPY --from=libnftnl /libnftnl /libnftnl
RUN rsync -aHAX --keep-dirlinks  /libnftnl/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=sources-downloader /sources/downloads/iptables.tar.xz /sources/
RUN mkdir -p /iptables
WORKDIR /sources
RUN tar -xf iptables.tar.xz && mv iptables-* iptables
WORKDIR /sources/iptables
# Remove the include of if_ether.h that is not available in our musl toolchain
# otherwise its redeclared in other headers and fails the build
RUN sed -i '/^[[:space:]]*#include[[:space:]]*<linux\/if_ether\.h>/d' extensions/*.c

RUN ./configure ${COMMON_CONFIGURE_ARGS} --with-xtlibdir=/usr/lib/xtables --enable-nftables  --disable-legacy-utils --disable-bpf-compiler --disable-nfs --disable-libipq
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/iptables

## libaio for lvm2
FROM rsync AS libaio
# remove -lto from CFLAGS as it causes issues building libaio
ENV CFLAGS="${CFLAGS//-flto=auto/}"
ARG JOBS
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=sources-downloader /sources/downloads/libaio.tar.gz /sources/
RUN mkdir -p /libaio
WORKDIR /sources
RUN tar -xf libaio.tar.gz && mv libaio-* libaio
WORKDIR /sources/libaio
# Avoid building the static libaio.a as we only need the shared one
RUN sed -i '/install.*libaio.a/s/^/#/' src/Makefile
RUN make -j${JOBS} -l${MAX_LOAD}
RUN DESTDIR=/libaio make -j${JOBS} -l${MAX_LOAD} install

## lvm2 for dmsetup, devmapper and so on
## TODO: build it with systemd support
FROM rsync AS lvm2
ARG JOBS
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=libaio /libaio /libaio
RUN rsync -aHAX --keep-dirlinks  /libaio/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=sources-downloader /sources/downloads/lvm2.tgz /sources/
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /sources/patches/

RUN mkdir -p /lvm2

# extract the aport patch to apply to lvm2
WORKDIR /sources/patches
RUN tar -xf aports.tar.gz && mv aports-* aport
WORKDIR /sources
RUN tar -xf lvm2.tgz && mv LVM2* lvm2
WORKDIR /sources/lvm2
# patch it
RUN patch -p1 < /sources/patches/aport/main/lvm2/fix-stdio-usage.patch
# Note: lvm2 ignores opt flags like -Os so we have to set it directly during configure
# This is the diff between a 4Mb lvm2 vs a 600Kb!!
RUN ./configure --prefix=/usr --libdir=/usr/lib --enable-pkgconfig --with-optimisation=-Os
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install_device-mapper DESTDIR=/lvm2

FROM rsync AS cmake
ARG JOBS
# Disable lto for cmake as it gives us nothing but issues
ENV CFLAGS="${CFLAGS//-flto=auto/}"
ENV LDFLAGS="${LDFLAGS//-flto=auto/}"
COPY --from=curl /curl /curl
RUN rsync -aHAX --keep-dirlinks  /curl/. /
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
COPY --from=sources-downloader /sources/downloads/cmake.tar.gz /sources/

RUN mkdir -p /cmake
WORKDIR /sources
RUN tar -xf cmake.tar.gz && mv cmake-* cmake
WORKDIR /sources/cmake

RUN ./bootstrap --prefix=/usr --no-debugger  --parallel=${JOBS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/cmake


# TODO: Once a new jsonc version is released (0.19) they will have meson support
# which means we can drop cmake buiilding which is very slow and heavy
FROM rsync AS jsonc
ARG JOBS
COPY --from=cmake /cmake /cmake
RUN rsync -aHAX --keep-dirlinks  /cmake/. /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
COPY --from=sources-downloader /sources/downloads/json-c.tar.gz /sources/

RUN mkdir -p /jsonc
WORKDIR /sources
RUN tar -xf json-c.tar.gz && mv json-c-* jsonc
WORKDIR /sources/jsonc-build/
RUN cmake ../jsonc -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_BUILD_TYPE=release -DBUILD_STATIC_LIBS=OFF -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_INSTALL_LIBDIR=lib
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/jsonc && make -s -j${JOBS} -l${MAX_LOAD} install

# pax-utils provives scanelf which lddconfig needs
FROM python-build AS pax-utils
ARG JOBS
COPY --from=sources-downloader /sources/downloads/pax-utils.tar.xz /sources/
RUN mkdir -p /pax-utils
WORKDIR /sources
RUN tar -xf pax-utils.tar.xz && mv pax-utils-* pax-utils
WORKDIR /sources/pax-utils
RUN pip3 install meson ninja
RUN meson setup buildDir --prefix=/usr --buildtype=minsize -Dstrip=true -Dtests=false -Duse_fuzzing=false
RUN DESTDIR=/pax-utils ninja -j${JOBS} -C buildDir install
RUN ninja -j${JOBS} -C buildDir install

# Build URCU static as its only used by multipathd and never reused again, we can save space this way
FROM rsync AS urcu
ARG JOBS
ENV CFLAGS="${CFLAGS} -fPIC"
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=pax-utils /pax-utils /pax-utils
RUN rsync -aHAX --keep-dirlinks  /pax-utils/. /

COPY --from=sources-downloader /sources/downloads/urcu.tar.bz2 /sources/
WORKDIR /sources
RUN mkdir -p /urcu
RUN tar -xf urcu.tar.bz2 && mv userspace-rcu-* urcu
WORKDIR /sources/urcu
RUN ./configure --quiet --prefix=/usr --host=${TARGET} --build=${BUILD} --enable-lto --disable-shared --enable-static --sysconfdir=/etc --mandir=/usr/share/man --infodir=/usr/share/info --localstatedir=/var
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/urcu && make -s -j${JOBS} -l${MAX_LOAD} install

## e2fsprogs for mkfs.ext4, e2fsck, tune2fs, etc
FROM rsync AS e2fsprogs
ARG JOBS
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /

COPY --from=sources-downloader /sources/downloads/e2fsprogs.tar.xz /sources/
RUN mkdir -p /e2fsprogs
WORKDIR /sources
RUN tar -xf e2fsprogs.tar.xz && mv e2fsprogs-* e2fsprogs
WORKDIR /sources/e2fsprogs
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-uuidd --disable-libuuid --disable-libblkid --disable-nls --enable-elf-shlibs  --disable-fsck --enable-symlink-install --disable-more
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/e2fsprogs && make -s -j${JOBS} -l${MAX_LOAD} install


## Provides mkfs.fat and fsck.fat
FROM rsync AS dosfstools
ARG JOBS
COPY --from=sources-downloader /sources/downloads/dosfstools.tar.gz /sources/
RUN mkdir -p /dosfstools
WORKDIR /sources
RUN tar -xf dosfstools.tar.gz && mv dosfstools-* dosfstools
WORKDIR /sources/dosfstools
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/dosfstools


## No need to have systemd support, systemd-cryptsetup picks cryptsetup directly
FROM rsync AS cryptsetup
ARG JOBS
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=lvm2 /lvm2 /lvm2
RUN rsync -aHAX --keep-dirlinks  /lvm2/. /
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
COPY --from=jsonc /jsonc /jsonc
RUN rsync -aHAX --keep-dirlinks  /jsonc/. /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=pax-utils /pax-utils /pax-utils
RUN rsync -aHAX --keep-dirlinks  /pax-utils/. /
COPY --from=popt /popt /popt
RUN rsync -aHAX --keep-dirlinks  /popt/. /

COPY --from=sources-downloader /sources/downloads/cryptsetup.tar.xz /sources/
RUN mkdir -p /cryptsetup
WORKDIR /sources
RUN tar -xf cryptsetup.tar.xz && mv cryptsetup-* cryptsetup
WORKDIR /sources/cryptsetup
# TODO: --enable-fips           enable FIPS mode restrictions
RUN ./configure ${COMMON_CONFIGURE_ARGS} --with-crypto-backend=openssl --disable-asciidoc  --disable-nls --disable-ssh-token
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/cryptsetup


FROM rsync AS parted
ARG JOBS
## device-mapper from lvm2
COPY --from=lvm2 /lvm2 /lvm2
RUN rsync -aHAX --keep-dirlinks  /lvm2/. /

## util-linux for libuuid
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /


COPY --from=sources-downloader /sources/downloads/parted.tar.xz /sources/
RUN mkdir -p /parted
WORKDIR /sources
RUN tar -xf parted.tar.xz && mv parted-* parted
WORKDIR /sources/parted
RUN ./configure ${COMMON_CONFIGURE_ARGS} --without-readline
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/parted && make -s -j${JOBS} -l${MAX_LOAD} install


## grub for bootloader installation
FROM python-build AS grub-base
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
COPY --from=bison /bison /bison
RUN rsync -aHAX --keep-dirlinks  /bison/. /
COPY --from=flex /flex /flex
RUN rsync -aHAX --keep-dirlinks  /flex/. /
COPY --from=xz /xz /xz
RUN rsync -aHAX --keep-dirlinks  /xz/. /
COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /
COPY --from=lvm2 /lvm2 /lvm2
RUN rsync -aHAX --keep-dirlinks  /lvm2/. /
COPY --from=gawk /gawk /gawk
RUN rsync -aHAX --keep-dirlinks  /gawk/. /

COPY --from=sources-downloader /sources/downloads/grub.tar.xz /sources/
WORKDIR /sources
RUN tar -xf grub.tar.xz && mv grub-* grub
WORKDIR /sources/grub
#RUN echo depends bli part_gpt > grub-core/extra_deps.lst


FROM grub-base AS grub-efi
ARG JOBS
# Remove --gc-sections from CFLAGS
ARG CFLAGS="${CFLAGS//-Wl,--gc-sections/}"
ARG LDFLAGS="${LDFLAGS//-Wl,--gc-sections/}"
# Also remove flto
ARG CFLAGS="${CFLAGS//-flto=auto/}"
ARG LDFLAGS="${LDFLAGS//-flto=auto/}"
WORKDIR /sources/grub
RUN mkdir -p /grub-efi
RUN ./configure ${COMMON_CONFIGURE_ARGS} --with-platform=efi --disable-efiemu --disable-werror
# Reconfigure gnulib shipped with grub to avoid build issues
# This comes because on grub 2.14 these files are shipped pre-generated and they were built on a glibc system
# which causes issues when building on musl systems as it expects the bsd-compat-headers to be available
# which is not the case here. So we force regenerating these files with our musl toolchain so it can find there is no cdefs
RUN make -s -j${JOBS} -l${MAX_LOAD} -C grub-core/lib/gnulib
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install-strip DESTDIR=/grub-efi
# The prefix should be empty so grub can find its config next to the efi file
RUN if [ "${ARCH}" = "aarch64" ]; then \
		grub_format="arm64-efi"; \
		grub_efi_name="grubaa64.efi"; \
	else \
		grub_format="x86_64-efi"; \
		grub_efi_name="grubx64.efi"; \
	fi && \
	/grub-efi/usr/bin/grub-mkimage -O ${grub_format} \
		-d /grub-efi/usr/lib/grub/${grub_format} \
		--prefix= \
		-o /grub-efi/usr/lib/grub/${grub_format}/${grub_efi_name} \
		loopback cat squash4 xzio gzio serial regexp part_gpt ext2 fat normal \
        boot configfile part_msdos linux echo search search_label search_fs_uuid \
        search_fs_file chain loadenv gfxterm all_video iso9660 help test


FROM grub-base AS grub-bios
ARG JOBS
# Remove --gc-sections from CFLAGS
ARG CFLAGS="${CFLAGS//-Wl,--gc-sections/}"
ARG LDFLAGS="${LDFLAGS//-Wl,--gc-sections/}"
# Also remove flto
ARG CFLAGS="${CFLAGS//-flto=auto/}"
ARG LDFLAGS="${LDFLAGS//-flto=auto/}"
WORKDIR /sources/grub
RUN mkdir -p /grub-bios
# Protect against building grub-bios on aarch64 host which is not supported
RUN if [ "${ARCH}" != "aarch64" ]; then ./configure ${COMMON_CONFIGURE_ARGS} --with-platform=pc --disable-werror;fi
# Reconfigure gnulib shipped with grub to avoid build issues
# This comes because on grub 2.14 these files are shipped pre-generated and they were built on a glibc system
# which causes issues when building on musl systems as it expects the bsd-compat-headers to be available
# which is not the case here. So we force regenerating these files with our musl toolchain so it can find there is no cdefs
RUN if [ "${ARCH}" != "aarch64" ]; then make -s -j${JOBS} -l${MAX_LOAD} -C grub-core/lib/gnulib;fi
# GRUB 2.14 + binutils >= 2.4x regression (musl toolchain): force -Ttext instead of --image-base
#
# Symptom:
#   grub-install fails with:
#     ".../i386-pc/kernel.img is miscompiled: its start address is 0x9074 instead of 0x9000: ld.gold bug?."
#
# Root cause:
#   For the i386-pc target, GRUB requires kernel.img to have its entry point (and .text start) at 0x9000.
#   With newer binutils, GRUB's configure detects support for ld's --image-base and sets:
#       TARGET_IMG_BASE_LDOPT = -Wl,--image-base
#   Using --image-base sets the base address of the LOAD segment, but ld then places .text *after* ELF+PHDR
#   headers (SIZEOF_HEADERS). On our builds SIZEOF_HEADERS is 0x74 bytes, so:
#       0x9000 + 0x74 = 0x9074
#   This shifts the entry point to 0x9074, and grub-install correctly rejects the image.
#
# Fix:
#   Override GRUB to link with -Ttext instead, which pins the .text VMA/entry exactly at 0x9000
#   (independent of header size), restoring the layout GRUB expects.
#
# Note:
#   The error message mentions "ld.gold", but this occurs with ld.bfd as well; it is a generic GRUB
#   mislink diagnostic for i386-pc images.
#
# Implementation:
#   Pass TARGET_IMG_BASE_LDOPT='-Wl,-Ttext' on the make/make install invocations that produce/install i386-pc images.

RUN if [ "${ARCH}" != "aarch64" ]; then \
    make -s -j${JOBS} -l${MAX_LOAD} TARGET_IMG_BASE_LDOPT='-Wl,-Ttext' && \
    make -s -j${JOBS} -l${MAX_LOAD} TARGET_IMG_BASE_LDOPT='-Wl,-Ttext' install-strip DESTDIR=/grub-bios ; \
    fi
# Test the mkimage generation in case we have a misalignment on the kernel.img start entry point
RUN if [ "${ARCH}" != "aarch64" ]; then \
    /grub-bios/usr/bin/grub-mkimage \
      --directory '/grub-bios/usr/lib/grub/i386-pc' \
      --prefix= \
      --output '/core.img' \
      --format 'i386-pc' \
      ext2 part_gpt biosdisk ; \
    fi
# libiconv for shim build only, NOT NEEDED IN THE FINAL BUILD
FROM rsync AS iconv
ARG JOBS
COPY --from=sources-downloader /sources/downloads/libiconv.tar.gz /sources/
RUN mkdir -p /iconv
WORKDIR /sources
RUN tar -xf libiconv.tar.gz && mv libiconv-* iconv
WORKDIR /sources/iconv
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-static --enable-shared
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/iconv

FROM rsync AS shim
ARG JOBS
COPY --from=libelf /libelf /libelf
RUN rsync -aHAX --keep-dirlinks  /libelf/. /
COPY --from=iconv /iconv /iconv
RUN rsync -aHAX --keep-dirlinks  /iconv/. /
COPY --from=sources-downloader /sources/downloads/shim.tar.bz2 /sources/
WORKDIR /sources
RUN tar -xf shim.tar.bz2 && mv shim-* shim
WORKDIR /sources/shim
RUN mkdir -p /shim/usr/share/efi/
# Install it to a temp folder as the dir struct is terrible
# and we want it to be available at /usr/share/efi/shimXX.efi
# TEMP workaround, we should add our paths into the sdk so agent and aurora both search for the proper shim path
RUN make -s -j${JOBS} -l${MAX_LOAD} EFIDIR=hadron ARCH=${BUILD_ARCH} DESTDIR=/tmp/shim install
RUN if [ ${ARCH} = "aarch64" ] ; then \
    mkdir -p /shim/usr/share/efi/aarch64 && cp /tmp/shim/boot/efi/EFI/BOOT/BOOTAA64.EFI /shim/usr/share/efi/aarch64/shim.efi ; \
    else \
    mkdir -p /shim/usr/share/efi/x86_64 && cp /tmp/shim/boot/efi/EFI/BOOT/BOOTX64.EFI /shim/usr/share/efi/x86_64/shim.efi ; \
    fi

FROM rsync AS tpm2-tss
ARG JOBS
RUN mkdir -p /tpm2-tss

COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
COPY --from=jsonc /jsonc /jsonc
RUN rsync -aHAX --keep-dirlinks  /jsonc/. /
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=curl /curl /curl
RUN rsync -aHAX --keep-dirlinks  /curl/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
COPY --from=sources-downloader /sources/downloads/tpm2-tss.tar.gz /sources/

WORKDIR /sources
RUN tar -xf tpm2-tss.tar.gz && mv tpm2-tss-* tpm2-tss
WORKDIR /sources/tpm2-tss
RUN ./configure ${COMMON_CONFIGURE_ARGS}     --disable-fapi \
                                             --disable-policy \
                                             --disable-tcti-mssim \
                                             --disable-tcti-swtpm \
                                             --disable-tcti-libusb \
                                             --disable-tcti-pcap
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/tpm2-tss


## systemd
## Try to build it at the end so we have most libraries already built
## Anything that depends on systemd should be built after this stage
FROM rsync AS systemd
ARG VERSION

COPY --from=gperf /gperf /gperf
RUN rsync -aHAX --keep-dirlinks  /gperf/. /

COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /

COPY --from=python-build /python /python
RUN rsync -aHAX --keep-dirlinks  /python/. /

COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /

COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /

COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /

COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /

COPY --from=libseccomp /libseccomp /libseccomp
RUN rsync -aHAX --keep-dirlinks  /libseccomp/. /

COPY --from=dbus /dbus /dbus
RUN rsync -aHAX --keep-dirlinks  /dbus/. /

COPY --from=pam /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /

COPY --from=kmod /kmod /kmod
RUN rsync -aHAX --keep-dirlinks  /kmod/. /

COPY --from=xz /xz /xz
RUN rsync -aHAX --keep-dirlinks  /xz/. /

COPY --from=libffi /libffi /libffi
RUN rsync -aHAX --keep-dirlinks  /libffi/. /

# Cryptsetup for systemd-cryptsetup
COPY --from=cryptsetup /cryptsetup /cryptsetup
RUN rsync -aHAX --keep-dirlinks  /cryptsetup/. /

# jsonc for cryptsetup
COPY --from=jsonc /jsonc /jsonc
RUN rsync -aHAX --keep-dirlinks  /jsonc/. /

# mapper for cryptsetup
COPY --from=lvm2 /lvm2 /lvm2
RUN rsync -aHAX --keep-dirlinks  /lvm2/. /

COPY --from=tpm2-tss /tpm2-tss /tpm2-tss
RUN rsync -aHAX --keep-dirlinks  /tpm2-tss/. /

COPY --from=sources-downloader /sources/downloads/systemd.tar.gz /sources/
WORKDIR /sources
RUN tar -xf systemd.tar.gz && mv systemd-* systemd
RUN mkdir -p /systemd
RUN python3 -m pip install meson ninja jinja2 pyelftools

WORKDIR /sources/systemd

RUN /usr/bin/meson setup buildDir \
      --prefix=/usr           \
      --buildtype=minsize -Dstrip=true     \
      -D dbus=enabled  \
      -D tpm2=enabled          \
      -D pam=enabled \
      -D libcryptsetup=enabled  \
      -D kmod=enabled \
      -D seccomp=enabled         \
      -D default-dnssec=no    \
      -D firstboot=false      \
      -D sysusers=true -D install-tests=false  -D tests=false -D fuzz-tests=false \
      -D integration-tests=false \
      -D kernel-install=false \
      -D ukify=false \
      -D ldconfig=false       \
      -D rpmmacrosdir=no      \
      -D gshadow=false        \
      -D idn=false            \
      -D localed=false        \
      -D nss-myhostname=false  \
      -D nss-systemd=false     \
      -D userdb=false         \
      -D nss-mymachines=disabled \
      -D nss-resolve=disabled   \
      -D utmp=false           \
      -D homed=disabled       \
      -D man=disabled         \
      -D mode=release         \
      -D pamconfdir=no        \
      -D dev-kvm-mode=0660    \
      -D nobody-group=nogroup \
      -D sysupdate=disabled   \
      -D repart=disabled \
      -D coredump=false \
      -D analyze=false \
      -D link-udev-shared=true \
      -D link-systemctl-shared=true \
      -D link-journalctl-shared=true \
      -D link-networkd-shared=true \
      -D link-timesyncd-shared=true \
      -D link-boot-shared=true \
      -D link-executor-shared=true \
      -D nspawn=disabled \
      -D portabled=false \
      -D storagetm=false \
      -D nsresourced=false \
      -D localed=false \
      -D pstore=false \
      -D sysupdated=disabled \
      -D importd=false \
      -D libc=musl \
      -D urlify=false \
      -D ukify=disabled \
      -D bootloader=true -Defi=true \
      -D sbat-distro="Hadron" \
      -D sbat-distro-url="hadron-linux.io" \
      -Dsbat-distro-summary="Hadron Linux" \
      -Dsbat-distro-version="${VERSION}"
RUN ninja -C buildDir
RUN DESTDIR=/systemd ninja -C buildDir install


FROM rsync AS dracut
ARG JOBS

COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /

COPY --from=zstd /zstd /zstd
RUN rsync -aHAX --keep-dirlinks  /zstd/. /
COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=kmod /kmod /kmod
RUN rsync -aHAX --keep-dirlinks  /kmod/. /
COPY --from=systemd /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /
COPY --from=fts /fts /fts
RUN rsync -aHAX --keep-dirlinks  /fts/. /
COPY --from=xz /xz /xz
RUN rsync -aHAX --keep-dirlinks  /xz/. /

COPY --from=sources-downloader /sources/downloads/dracut.tar.gz /sources/
RUN mkdir -p /dracut
WORKDIR /sources
RUN tar -xf dracut.tar.gz && mv dracut-* dracut
WORKDIR /sources/dracut
## TODO: Fix this, it should be set everywhere already?
ENV CC=gcc
RUN ./configure --disable-asciidoctor --disable-documentation --prefix=/usr
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/dracut


## lvm2 for dmsetup, devmapper and so on
## We need to build it with systemd support so we can use it later with systemd rules and so on
## This helps when a device is unlocked to makle the mapper show the device right away
FROM rsync AS lvm2-systemd
ARG JOBS
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=libaio /libaio /libaio
RUN rsync -aHAX --keep-dirlinks  /libaio/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=systemd /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=python-build  /python /python
RUN rsync -aHAX --keep-dirlinks  /python/. /
COPY --from=ca-certificates /ca-certificates /ca-certificates
RUN rsync -aHAX --keep-dirlinks  /ca-certificates/. /
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /


COPY --from=sources-downloader /sources/downloads/lvm2.tgz /sources/
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /sources/patches/

RUN mkdir -p /lvm2

# extract the aport patch to apply to lvm2
WORKDIR /sources/patches
RUN tar -xf aports.tar.gz && mv aports-* aport
WORKDIR /sources
RUN tar -xf lvm2.tgz && mv LVM2* lvm2
WORKDIR /sources/lvm2
# patch it
RUN patch -p1 < /sources/patches/aport/main/lvm2/fix-stdio-usage.patch
RUN ./configure --prefix=/usr --libdir=/usr/lib --enable-pkgconfig --enable-udev_sync --enable-udev_rules --with-udevdir=/usr/lib/udev/rules.d --enable-dmeventd
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/lvm2 && make -s -j${JOBS} -l${MAX_LOAD} install

## needed for dracut and other tools
FROM rsync AS multipath-tools
ARG JOBS
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
# devmapper
COPY --from=lvm2-systemd /lvm2 /lvm2
RUN rsync -aHAX --keep-dirlinks  /lvm2/. /

## get libudev from systemd
COPY --from=systemd /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /

## libaio for multipathd
COPY --from=libaio /libaio /libaio
RUN rsync -aHAX --keep-dirlinks  /libaio/. /

## json-c for multipathd
COPY --from=jsonc /jsonc /jsonc
RUN rsync -aHAX --keep-dirlinks  /jsonc/. /

## urcu for multipathd
COPY --from=urcu /urcu /urcu
RUN rsync -aHAX --keep-dirlinks  /urcu/. /

## util-linux for libmount.so
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /

## libcap
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=pax-utils /pax-utils /pax-utils
RUN rsync -aHAX --keep-dirlinks  /pax-utils/. /

COPY --from=sources-downloader /sources/downloads/multipath-tools.tar.gz /sources/
RUN mkdir -p /multipath-tools
WORKDIR /sources
RUN tar -xf multipath-tools.tar.gz && mv multipath-tools-* multipath-tools
WORKDIR /sources/multipath-tools
ENV CC="gcc"
# Set lib to /lib so it works in initramfs as well
RUN make -s -j${JOBS} -l${MAX_LOAD} sysconfdir="/etc" configdir="/etc/multipath/conf.d" LIB=/lib
RUN make -s -j${JOBS} -l${MAX_LOAD} SYSTEMDPATH=/lib LIB=/lib install DESTDIR=/multipath-tools
RUN make -s -j${JOBS} -l${MAX_LOAD} LIB=/lib install
RUN rm -Rf /multipath/usr/share/man

## dbus second pass pass with systemd support, so we can have a working systemd and dbus
FROM python-build AS dbus-systemd
ARG JOBS
COPY --from=expat /expat /expat
RUN rsync -aHAX --keep-dirlinks  /expat/. /
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=systemd /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=sources-downloader /sources/downloads/dbus.tar.xz /sources/
# install target
RUN mkdir -p /dbus
WORKDIR /sources
RUN pip3 install meson ninja
RUN tar -xf dbus.tar.xz && mv dbus-* dbus
WORKDIR /sources/dbus
RUN meson setup buildDir --prefix=/usr --buildtype=minsize -Dstrip=true
RUN DESTDIR=/dbus ninja -j${JOBS} -C buildDir install

## final build of pam with systemd support
FROM python-build AS pam-systemd
ARG JOBS
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=systemd /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /
COPY --from=sources-downloader /sources/downloads/pam.tar.xz /sources/
RUN mkdir -p /pam
WORKDIR /sources
RUN tar -xf pam.tar.xz && mv Linux-PAM-* linux-pam
WORKDIR /sources/linux-pam
RUN pip3 install meson ninja
RUN meson setup buildDir --prefix=/usr --buildtype=minsize -Dstrip=true
RUN DESTDIR=/pam ninja -j${JOBS} -C buildDir install
COPY files/pam/* /pam/etc/pam.d/
## We are using the pam_shells.so module in a few places, so we need a proper /etc/shells file
COPY files/shells /pam/etc/shells
RUN chmod 644 /pam/etc/shells

# Shadow with systemd support via PAM
FROM shadow-base AS shadow-systemd
ARG JOBS
COPY --from=pam-systemd /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /
COPY --from=systemd /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /
COPY --from=sources-downloader /sources/downloads/shadow.tar.xz /sources/
RUN mkdir -p /shadow
WORKDIR /sources
RUN tar -xf shadow.tar.xz && mv shadow-* shadow
WORKDIR /sources/shadow
RUN ./configure ${COMMON_CONFIGURE_ARGS} --sysconfdir=/etc --without-libbsd --disable-nls
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} exec_prefix=/usr pamddir= install DESTDIR=/shadow && make exec_prefix=/usr pamddir= -s -j${JOBS} -l${MAX_LOAD} install


FROM rsync AS sudo-base

COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=pax-utils /pax-utils /pax-utils
RUN rsync -aHAX --keep-dirlinks  /pax-utils/. /

FROM sudo-base AS sudo-systemd
ARG JOBS
COPY --from=pam-systemd /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /
COPY --from=sources-downloader /sources/downloads/sudo.tar.gz /sources/
RUN mkdir -p /sudo
WORKDIR /sources
RUN tar -xf sudo.tar.gz && mv sudo-* sudo
WORKDIR /sources/sudo
RUN ./configure ${COMMON_CONFIGURE_ARGS} --libexecdir=/usr/lib --with-pam --disable-nls --with-secure-path --with-env-editor --with-passprompt="[sudo] password for %p: "
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/sudo && make -s -j${JOBS} -l${MAX_LOAD} install

FROM sudo-base AS sudo
ARG JOBS
COPY --from=pam /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /
COPY --from=sources-downloader /sources/downloads/sudo.tar.gz /sources/
RUN mkdir -p /sudo
WORKDIR /sources
RUN tar -xf sudo.tar.gz && mv sudo-* sudo
WORKDIR /sources/sudo
RUN ./configure ${COMMON_CONFIGURE_ARGS} --libexecdir=/usr/lib --with-pam --disable-nls --with-secure-path --with-env-editor --with-passprompt="[sudo] password for %p: "
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/sudo && make -s -j${JOBS} -l${MAX_LOAD} install

FROM python-build AS openscsi
ARG JOBS
# Wee need cmake, libkmod, liblzma, mount, systemd, perl
COPY --from=cmake /cmake /cmake
RUN rsync -aHAX --keep-dirlinks  /cmake/. /
COPY --from=kmod /kmod /kmod
RUN rsync -aHAX --keep-dirlinks  /kmod/. /
COPY --from=xz /xz /xz
RUN rsync -aHAX --keep-dirlinks  /xz/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
COPY --from=systemd /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /
COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=sources-downloader /sources/downloads/openscsi.tar.gz /sources/
RUN pip3 install meson ninja
RUN mkdir -p /openscsi
WORKDIR /sources
RUN tar -xf openscsi.tar.gz && mv open-iscsi-* openscsi
WORKDIR /sources/openscsi
RUN meson setup buildDir --prefix=/usr --buildtype=minsize --optimization 3 -D isns=disabled
RUN DESTDIR=/openscsi ninja -j${JOBS} -C buildDir install && ninja -j${JOBS} -C buildDir install


FROM rsync AS libxml
ARG JOBS
RUN mkdir -p /libxml
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /

COPY --from=sources-downloader /sources/downloads/libxml2.tar.xz /sources/
WORKDIR /sources
RUN tar -xf libxml2.tar.xz && mv libxml2-* libxml2
WORKDIR /sources/libxml2
RUN ./configure ${COMMON_CONFIGURE_ARGS} --without-python
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libxml && make -s -j${JOBS} -l${MAX_LOAD} install


## Build image with all the deps on it
## Busybox provides the following tools for the final images:
# Needed to build initramfs under grub variants
# awk
# cpio
# gzip # this is not strictly needed
# pkill
# sed
# cool utils to have for easy management and utility:
# free
# clear
# less
# lsof
# more
# ps
# watch
# which
# ip
# tree
# really needed in the system and the actual ones are too big:
# tar
# vi
# mkfs.vfat
FROM stage1 AS full-toolchain-merge
## Prepare rsync to work
COPY --link --from=rsync /rsync /
COPY --link --from=attr /attr /
COPY --link --from=acl /acl /
COPY --link --from=zstd /zstd /
COPY --link --from=zlib /zlib /
COPY --link --from=lz4 /lz4 /
COPY --link --from=xxhash /xxhash /

# Now prepare a merged directory with all the built tools
COPY --from=busybox /sysroot /busybox
RUN rsync -aHAX --keep-dirlinks  /busybox/. /merge
COPY --from=cmake /cmake /cmake
RUN rsync -aHAX --keep-dirlinks  /cmake/. /merge
COPY --from=kmod /kmod /kmod
RUN rsync -aHAX --keep-dirlinks  /kmod/. /merge
COPY --from=xz /xz /xz
RUN rsync -aHAX --keep-dirlinks  /xz/. /merge
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /merge
COPY --from=systemd /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /merge
COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /merge
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /merge
COPY --from=pam-systemd /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /merge
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /merge
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /merge
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /merge
COPY --from=pax-utils /pax-utils /pax-utils
RUN rsync -aHAX --keep-dirlinks  /pax-utils/. /merge
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /merge
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /merge
COPY --from=bison /bison /bison
RUN rsync -aHAX --keep-dirlinks  /bison/. /merge
COPY --from=flex /flex /flex
RUN rsync -aHAX --keep-dirlinks  /flex/. /merge
COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /merge
COPY --from=lvm2-systemd /lvm2 /lvm2
RUN rsync -aHAX --keep-dirlinks  /lvm2/. /merge
COPY --from=gawk /gawk /gawk
RUN rsync -aHAX --keep-dirlinks  /gawk/. /merge
COPY --from=jsonc /jsonc /jsonc
RUN rsync -aHAX --keep-dirlinks  /jsonc/. /merge
COPY --from=libaio /libaio /libaio
RUN rsync -aHAX --keep-dirlinks  /libaio/. /merge
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /merge
COPY --from=expat /expat /expat
RUN rsync -aHAX --keep-dirlinks  /expat/. /merge
COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /merge
COPY --from=zstd /zstd /zstd
RUN rsync -aHAX --keep-dirlinks  /zstd/. /merge
COPY --from=fts /fts /fts
RUN rsync -aHAX --keep-dirlinks  /fts/. /merge
COPY --from=autoconf /autoconf /autoconf
RUN rsync -aHAX --keep-dirlinks  /autoconf/. /merge
COPY --from=automake /automake /automake
RUN rsync -aHAX --keep-dirlinks  /automake/. /merge
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /merge
COPY --from=libseccomp /libseccomp /libseccomp
RUN rsync -aHAX --keep-dirlinks  /libseccomp/. /merge
COPY --from=dbus /dbus /dbus
RUN rsync -aHAX --keep-dirlinks  /dbus/. /merge
COPY --from=python-build /python /python
RUN rsync -aHAX --keep-dirlinks  /python/. /merge
COPY --from=acl /acl /acl
RUN rsync -aHAX --keep-dirlinks  /acl/. /merge
COPY --from=ca-certificates /ca-certificates /ca-certificates
RUN rsync -aHAX --keep-dirlinks  /ca-certificates/. /merge
COPY --from=curl /curl /curl
RUN rsync -aHAX --keep-dirlinks  /curl/. /merge
COPY --from=rsync /rsync /rsync
RUN rsync -aHAX --keep-dirlinks  /rsync/. /merge
COPY --from=gcc-stage0 /sysroot /gcc
RUN rsync -aHAX --keep-dirlinks /gcc/. /merge
COPY --from=musl-stage0 /sysroot /musl
RUN rsync -aHAX --keep-dirlinks /musl/. /merge
COPY --from=make-stage0 /sysroot /make
RUN rsync -aHAX --keep-dirlinks /make/. /merge
COPY --from=binutils-stage0 /sysroot /binutils
RUN rsync -aHAX --keep-dirlinks /binutils/. /merge
COPY --from=attr /attr /attr
RUN rsync -aHAX --keep-dirlinks  /attr/. /merge
COPY --from=busybox /sysroot /busybox
RUN rsync -aHAX --keep-dirlinks  /busybox/. /merge
COPY --from=libffi /libffi /libffi
RUN rsync -aHAX --keep-dirlinks  /libffi/. /merge
COPY --from=lz4 /lz4 /lz4
RUN rsync -aHAX --keep-dirlinks  /lz4/. /merge
COPY --from=xxhash /xxhash /xxhash
RUN rsync -aHAX --keep-dirlinks  /xxhash/. /merge
COPY --from=libxml /libxml /libxml
RUN rsync -aHAX --keep-dirlinks  /libxml/. /merge
COPY --from=grep /grep /grep
RUN rsync -aHAX --keep-dirlinks  /grep/. /merge
COPY --from=diffutils /diffutils /diffutils
RUN rsync -aHAX --keep-dirlinks  /diffutils/. /merge
## Kernel but only the headers
COPY --from=kernel-headers /linux-headers/ /linux-headers
RUN rsync -aHAX --keep-dirlinks  /linux-headers/. /merge/usr/
COPY --from=findutils /findutils /findutils
RUN rsync -aHAX --keep-dirlinks  /findutils/. /merge
COPY --from=gzip /gzip /gzip
RUN rsync -aHAX --keep-dirlinks  /gzip/. /merge

FROM scratch AS toolchain
# These are the default values for the toolchain
# Set them so anything using the toolchain will use the default values
ENV VENDOR="hadron"
ENV ARCH="x86-64"
ENV BUILD_ARCH="x86_64"
ENV VENDOR=${VENDOR}
ENV BUILD_ARCH=${BUILD_ARCH}
ENV TARGET=${BUILD_ARCH}-${VENDOR}-linux-musl
ENV BUILD=${BUILD_ARCH}-pc-linux-musl
ENV COMMON_CONFIGURE_ARGS="--quiet --prefix=/usr --host=${TARGET} --build=${BUILD} --enable-lto --enable-shared --disable-static"
# Standard aggressive size optimization flags
ENV CFLAGS="-Os -pipe -fomit-frame-pointer -fno-unroll-loops -fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections -flto=auto"
ENV LDFLAGS="-Wl,--gc-sections -Wl,--as-needed -flto=auto"
# Point to GCC wrappers so it understand the lto=auto flags
ENV AR="gcc-ar"
ENV NM="gcc-nm"
ENV RANLIB="gcc-ranlib"
ENV M4="/usr/bin/m4"
ENV COMMON_MESON_FLAGS="--prefix=/usr --libdir=lib --buildtype=minsize -Dstrip=true"
SHELL ["/bin/bash", "-c"]
COPY --from=full-toolchain-merge /merge /.
RUN ln -s /bin/bash /bin/sh
CMD ["/bin/bash", "-l"]

########################################################
#
# Stage 2 - Building the final image
#
########################################################
# stage-merge will merge all the built packages into a single directory
FROM stage0 AS stage2-merge

RUN apk add rsync pax-utils


COPY --from=skeleton /sysroot /skeleton

## Musl
COPY --from=musl /sysroot /musl
RUN rsync -aHAX --keep-dirlinks  /musl/. /skeleton/

## BUSYBOX
COPY --from=busybox /sysroot /busybox
RUN rsync -avHAX --keep-dirlinks  /busybox/. /skeleton/

## coreutils
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /skeleton/

## CURL
COPY --from=curl /curl /curl
RUN rsync -aHAX --keep-dirlinks  /curl/. /skeleton/

## ca-certificates
COPY --from=ca-certificates /ca-certificates /ca-certificates
RUN rsync -aHAX --keep-dirlinks  /ca-certificates/. /skeleton/

## bash
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /skeleton/

## readline
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /skeleton/

## acl
COPY --from=acl /acl /acl
RUN rsync -aHAX --keep-dirlinks  /acl/. /skeleton/

## attr
COPY --from=attr /attr /attr
RUN rsync -aHAX --keep-dirlinks  /attr/. /skeleton/

## findutils
COPY --from=findutils /findutils /findutils
RUN rsync -aHAX --keep-dirlinks  /findutils/. /skeleton/

## grep
COPY --from=grep /grep /grep
RUN rsync -aHAX --keep-dirlinks  /grep/. /skeleton/

## zstd
COPY --from=zstd /zstd /zstd
RUN rsync -aHAX --keep-dirlinks  /zstd/. /skeleton/

## libz
COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /skeleton/

## libcap
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /skeleton/

## util-linux
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /skeleton/

## libexpat
COPY --from=expat /expat /expat
RUN rsync -aHAX --keep-dirlinks  /expat/. /skeleton/

## libaio for io asynchronous operations
COPY --from=libaio /libaio /libaio
RUN rsync -aHAX --keep-dirlinks  /libaio/. /skeleton/

## rsync
COPY --from=rsync /rsync /rsync
RUN rsync -aHAX --keep-dirlinks  /rsync/. /skeleton/

COPY --from=lz4 /lz4 /lz4
RUN rsync -aHAX --keep-dirlinks  /lz4/. /skeleton

## xxhash needed by rsync
COPY --from=xxhash /xxhash /xxhash
RUN rsync -aHAX --keep-dirlinks  /xxhash/. /skeleton

## kbd for loadkeys support
COPY --from=kbd /kbd /kbd
RUN rsync -aHAX --keep-dirlinks  /kbd/. /skeleton

# This is mostly for debugging purposes, not needed for final image
# This provides scanelf needed by ldconfig
#COPY --from=pax-utils /pax-utils /pax-utils
#RUN rsync -aHAX --keep-dirlinks  /pax-utils/. /skeleton

## Copy ldconfig from alpine musl
#COPY --from=sources-downloader /sources/downloads/aports.tar.gz /
#RUN tar xf /aports.tar.gz && mv aports-* aports
#RUN cp /aports/main/musl/ldconfig /skeleton/usr/bin/ldconfig
# make sure they are both executable
#RUN chmod 755 /skeleton/sbin/ldconfig

## OpenSSL
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /skeleton/

# TODO: Do we need sudo in the container image?
## Cleanup

# We don't need headers
RUN rm -rf /skeleton/usr/include
# Remove man files
RUN rm -rf /skeleton/usr/share/man
RUN rm -rf /skeleton/usr/local/share/man
# Remove docs
RUN rm -rf /skeleton/usr/share/doc
RUN rm -rf /skeleton/usr/share/info
RUN rm -rf /skeleton/usr/share/local/info
# Remove static libs
RUN find /skeleton -name '*.a' -delete

# Strip binaries
RUN find /skeleton -type f ! -name 'fips.so' -print0 | xargs -0 scanelf --nobanner --osabi --etype "ET_DYN,ET_EXEC" --format "%F" | xargs -r strip --strip-unneeded


# Remove python artifacts
RUN find /skeleton -name "*.pyc" -delete
RUN find /skeleton -name "__pycache__" -type d -exec rm -rf {} +


# Container base image, it has the minimal required to run as a container
FROM scratch AS container
COPY --from=stage2-merge /skeleton /
SHELL ["/bin/bash", "-c"]
## Link sh to bash
RUN ln -s /bin/bash /bin/sh
## Symlink ld-musl-$ARCH.so to /bin/ldd to provide ldd functionality
RUN if [ "${ARCH}" == "aarch64" ]; then \
    ln -s /lib/ld-musl-aarch64.so.1 /bin/ldd; \
    else \
    ln -s /lib/ld-musl-x86_64.so.1 /bin/ldd; \
    fi
CMD ["/bin/bash", "-l"]

# Target that tests to see if the binaries work or we are missing some libs
FROM container AS container-test
RUN bash --version
RUN curl --version
RUN rsync --version
RUN grep --version
RUN find --version
RUN zstd --version
RUN xxhsum --version
RUN lz4 --version
RUN ls --version
RUN attr -l /bin/bash
RUN getfacl --version
RUN setfacl --version
RUN busybox --list
RUN openssl version

# stage2-merge is where we prepare stuff for the final image
# more complete, this has systemd, sudo, openssh, iptables, kernel, etc..
FROM alpine-base AS full-image-merge-base

COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /skeleton/

## openssh
COPY --from=openssh /openssh /openssh
RUN rsync -aHAX --keep-dirlinks  /openssh/. /skeleton/

# kernel and modules
COPY --from=kernel /kernel/ /skeleton/boot/
COPY --from=kernel-modules /modules/lib/modules/ /skeleton/lib/modules

COPY --from=sudo-systemd /sudo /sudo
RUN rsync -aHAX --keep-dirlinks  /sudo/. /skeleton

# Iptables is needed to support k8s
COPY --from=iptables /iptables /iptables
RUN rsync -aHAX --keep-dirlinks  /iptables/. /skeleton

# For iptables-nft backend
COPY --from=libmnl /libmnl /libmnl
RUN rsync -aHAX --keep-dirlinks  /libmnl/. /skeleton
COPY --from=libnftnl /libnftnl /libnftnl
RUN rsync -aHAX --keep-dirlinks  /libnftnl/. /skeleton

## cryptsetup for encrypted partitions
COPY --from=cryptsetup /cryptsetup /cryptsetup
RUN rsync -aHAX --keep-dirlinks  /cryptsetup/. /skeleton

## jsonc needed by libcryptsetup
COPY --from=jsonc /jsonc /jsonc
RUN rsync -aHAX --keep-dirlinks  /jsonc/. /skeleton

# device-mapper from lvm2
COPY --from=lvm2-systemd /lvm2 /lvm2
RUN rsync -aHAX --keep-dirlinks  /lvm2/. /skeleton/

COPY --from=multipath-tools /multipath-tools /multipath-tools
RUN rsync -aHAX --keep-dirlinks  /multipath-tools/. /skeleton/
## Use mount and cp to preserv symlinks, otherwise if we copy directly
## we will resolve the symlinks and copy the real files multiple times
## Copy libgcc_s.so.1 for multipathd deps
RUN --mount=from=gcc-stage0,src=/sysroot/usr/lib,dst=/mnt,ro mkdir -p /skeleton/usr/lib && cp -a /mnt/libgcc_s.so* /skeleton/usr/lib/

COPY --from=e2fsprogs /e2fsprogs /e2fsprogs
RUN rsync -aHAX --keep-dirlinks  /e2fsprogs/. /skeleton/

## systemd
COPY --from=systemd /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /skeleton/

## dbus
COPY --from=dbus-systemd /dbus /dbus
RUN rsync -aHAX --keep-dirlinks  /dbus/. /skeleton/

## seccomp
COPY --from=libseccomp /libseccomp /libseccomp
RUN rsync -aHAX --keep-dirlinks  /libseccomp/. /skeleton/

# copy pam but with systemd support
COPY --from=pam-systemd /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /skeleton

# copy shadow but with systemd support
COPY --from=shadow-systemd /shadow /shadow
RUN rsync -aHAX --keep-dirlinks  /shadow/. /skeleton

# copy iscsi
COPY --from=openscsi /openscsi /openscsi
RUN rsync -aHAX --keep-dirlinks  /openscsi/. /skeleton

# kmod needed by openscsi
COPY --from=kmod /kmod /kmod
RUN rsync -aHAX --keep-dirlinks  /kmod/. /skeleton

# lzma needed by openscsi
COPY --from=xz /xz /xz
RUN rsync -aHAX --keep-dirlinks  /xz/. /skeleton

COPY --from=tpm2-tss /tpm2-tss /tpm2-tss
RUN rsync -aHAX --keep-dirlinks  /tpm2-tss/. /skeleton

# Strip binaries
RUN find /skeleton -type f ! -name 'fips.so' -print0 | xargs -0 scanelf --nobanner --osabi --etype "ET_DYN,ET_EXEC" --format "%F" | xargs -r strip --strip-unneeded


# Remove python artifacts
RUN find /skeleton -name "*.pyc" -delete
RUN find /skeleton -name "__pycache__" -type d -exec rm -rf {} +


FROM full-image-merge-base AS full-image-merge-no-fips
# no-op

FROM full-image-merge-base AS full-image-merge-fips
COPY --from=libkcapi /libkcapi /libkcapi
RUN rsync -aHAX --keep-dirlinks  /libkcapi/. /skeleton


FROM full-image-merge-${FIPS} AS full-image-merge

## This target will assemble dracut and all its dependencies into the skeleton
FROM stage0 AS dracut-final
RUN apk add rsync pax-utils

## kmod for modprobe, insmod, lsmod, modinfo, rmmod. Draut depends on this
COPY --from=kmod /kmod /kmod
RUN rsync -aHAX --keep-dirlinks  /kmod/. /skeleton

## fts library, dracut depends on this
COPY --from=fts /fts /fts
RUN rsync -aHAX --keep-dirlinks  /fts/. /skeleton

## xz and liblzma, dracut depends on this
COPY --from=xz /xz /xz
RUN rsync -aHAX --keep-dirlinks  /xz/. /skeleton

## lz4, dracut depends on this if mixed with systemd
COPY --from=lz4 /lz4 /lz4
RUN rsync -aHAX --keep-dirlinks  /lz4/. /skeleton

## gawk for dracut
COPY --from=gawk /gawk /gawk
RUN rsync -aHAX --keep-dirlinks  /gawk/. /skeleton

## grub
COPY --from=grub-efi /grub-efi /grub-efi
RUN rsync -aHAX --keep-dirlinks  /grub-efi/. /skeleton

COPY --from=grub-bios /grub-bios /grub-bios
RUN rsync -aHAX --keep-dirlinks  /grub-bios/. /skeleton

COPY --from=shim /shim /shim
RUN rsync -aHAX --keep-dirlinks  /shim/. /skeleton

## Dracut
COPY --from=dracut /dracut /dracut
RUN rsync -aHAX --keep-dirlinks  /dracut/. /skeleton

# Strip binaries
# As this is added to the full-image-merge we still have to strip binaries here
RUN find /skeleton -type f ! -name 'fips.so' -print0 | xargs -0 scanelf --nobanner --osabi --etype "ET_DYN,ET_EXEC" --format "%F" | xargs -r strip --strip-unneeded


### Assemble the image depending on our bootloader
## either grub or systemd-boot for trusted boot
## To not merge things and have extra software where we dont want it we prepare a base image with all the
## needed software and then we merge it with the bootloader specific stuff

## This workarounds over the COPY not being able to run over the same dir
## We merge the base container + stage2-merge (kernel, sudo, systemd, etc) + dracut into a single dir
FROM alpine-base AS full-image-pre-grub
COPY --from=container / /skeleton
COPY --from=full-image-merge /skeleton /stage2-merge
RUN rsync -aHAX --keep-dirlinks  /stage2-merge/. /skeleton/
COPY --from=dracut-final /skeleton /dracut-final
RUN rsync -aHAX --keep-dirlinks  /dracut-final/. /skeleton/
# TODO: Remove the sd-boot efi files to save space

## We merge the base container + stage2-merge (kernel, sudo, systemd, etc) into a single dir
FROM alpine-base AS full-image-pre-systemd
COPY --from=container / /skeleton
COPY --from=full-image-merge /skeleton /stage2-merge
RUN rsync -aHAX --keep-dirlinks  /stage2-merge/. /skeleton/
# No dracut for systemd-boot

## Final image for grub
FROM scratch AS full-image-grub
COPY --from=full-image-pre-grub /skeleton /

## Final image for systemd-boot
FROM scratch AS full-image-systemd
COPY --from=full-image-pre-systemd /skeleton /

## Final image depending on the bootloader
# We run some final tasks like creating /etc/shadow, /etc/passwd, etc
# We also add some default configs for sysctl, login.defs, etc
# We also run systemctl preset-all to have default presets for systemd services
FROM full-image-${BOOTLOADER} AS full-image-final
SHELL ["/bin/bash", "-c"]
ARG VERSION
## Cleanup first
# We don't need headers
RUN rm -rf /usr/include
# Remove man files, 4,9Mb
RUN rm -rf /usr/share/man
RUN rm -rf /usr/local/share/man
# Remove docs 4,9Mb
RUN rm -rf /usr/share/doc
# remove info 3,8Mb
RUN rm -rf /usr/share/info
RUN rm -rf /usr/share/local/info
# remove locales to save space
RUN rm -rf /usr/share/locale
# Remove bash completions
RUN rm -rf /usr/share/bash-completion
# Remove zsh/fish completions
RUN rm -rf /usr/share/zsh
RUN rm -rf /usr/share/fish
# Remove useless keymaps
RUN rm -rf /usr/share/keymaps/amiga
RUN rm -rf /usr/share/keymaps/atari
RUN rm -rf /usr/share/keymaps/sun
# Remove static libs
RUN find / -name '*.a' -delete
RUN find / -name "*.la" -delete
RUN find / -name "*.pc" -delete
# Remove packageconfig files
RUN rm -Rf /usr/share/pkgconfig
## Small configs
# set a default locale
RUN echo "export LANG=en_US.UTF-8" >> /etc/profile.d/locale.sh
RUN echo "en_US.UTF-8" > /etc/locale.conf
# Export no colors for systemd
# Make it a check so if we move to the proper less it will not hit this
RUN echo "if ! less -V > /dev/null 2>&1 ; then export SYSTEMD_COLORS=0; fi" >> /etc/profile.d/systemd-no-colors.sh
RUN chmod 644 /etc/profile.d/locale.sh
RUN chmod 644 /etc/bash.bashrc
RUN echo "VERSION_ID=\"${VERSION}\"" >> /etc/os-release
RUN busybox --install
# mkfs.fat is a script that calls mkfs.vfat busybox applet with the proper name and pass all args for compatibility
RUN echo -e '#!/bin/sh\nexec /bin/mkfs.vfat "$@"\n' > /bin/mkfs.fat && chmod +x /bin/mkfs.fat
# preset all systemd services
RUN systemctl preset-all
# Disable systemd-make-policy as we don't use it and it conflicts with
# measurements with PCR policies
# This is automatically brough in and creates a /var/lib/systemnd/pcrlock.json with measurements
# This conflicts with PCR policies that we want to enforce, as it tries to mix them
# This is new under 259 it seems, as before it would ignore the file and use the PCR policies instead
RUN systemctl disable systemd-pcrlock-make-policy && systemctl mask systemd-pcrlock-make-policy
# Add sysctl configs
# TODO: kernel tuning based on the environment? Hardening? better defaults?
COPY files/sysctl/* /etc/sysctl.d/
# copy a new login.defs to have better defaults as some stuff is already done by shadow and pam
COPY files/login.defs /etc/login.defs
## Remove users stuff
RUN rm -f /etc/passwd /etc/shadow /etc/group /etc/gshadow
## Create any missing users from scratch
RUN systemd-sysusers
## Link /lib/firmware into /usr/local/lib/firmware for firmware loading
RUN mkdir -p /usr/local/lib && ln -s /lib/firmware /usr/local/lib/firmware

## final image with debug
FROM full-image-final AS debug

COPY --from=strace /strace /
COPY --from=gdb-stage0 /gdb /
COPY --from=python-build /python /
RUN --mount=from=gcc-stage0,src=/sysroot/usr/lib,dst=/mnt,ro cp -a /mnt/libstdc++.so* /usr/lib/
CMD ["/bin/bash", "-l"]

## Final verification stage
FROM full-image-final AS image-test
COPY files/verify_binaries.sh /verify_binaries.sh
RUN chmod +x /verify_binaries.sh
RUN /verify_binaries.sh

### final image, last in case we call it without a target, it will build this one
FROM scratch AS default
COPY --from=full-image-final / /
CMD ["/bin/bash", "-l"]
