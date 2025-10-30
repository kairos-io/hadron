## This is Dockerfile, that at the end of the process it builds a 
## small LFS system, starting from Alpine Linux.
## It uses mussel to build the system.
ARG BOOTLOADER=grub
ARG VERSION=0.0.1
ARG JOBS=24

ARG ALPINE_VERSION=3.22.2
ARG CFLAGS

FROM alpine:${ALPINE_VERSION} AS stage0

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

RUN apk update && apk add git bash wget bash perl build-base make patch busybox-static curl m4 xz texinfo bison gawk gzip zstd-dev coreutils bzip2 tar
RUN git clone https://github.com/firasuke/mussel.git && cd mussel && git checkout ${MUSSEL_VERSION} -b build
RUN cd mussel && ./mussel ${ARCH} -k -l -o -p -s -T ${VENDOR}

ENV PATH=/mussel/toolchain/bin/:$PATH
ENV LC_ALL=POSIX
ENV TARGET=${BUILD_ARCH}-${VENDOR}-linux-musl
ENV BUILD=${BUILD_ARCH}-pc-linux-musl

### This stage is used to download the sources for the packages
### This runs in parallel with stage0 to improve build time since it's network-bound while stage0 is CPU-bound
FROM alpine:${ALPINE_VERSION} AS sources-downloader

# Install packages needed for downloading and patching sources
RUN apk update && apk add wget git patch tar bash coreutils findutils

ARG CURL_VERSION=8.5.0
ENV CURL_VERSION=${CURL_VERSION}

RUN mkdir -p /sources/downloads && cd /sources/downloads && wget -q https://curl.se/download/curl-${CURL_VERSION}.tar.gz 

ARG RSYNC_VERSION=3.4.1
ENV RSYNC_VERSION=${RSYNC_VERSION}

RUN cd /sources/downloads && wget -q https://download.samba.org/pub/rsync/rsync-${RSYNC_VERSION}.tar.gz

ARG XXHASH_VERSION=0.8.3
ENV XXHASH_VERSION=${XXHASH_VERSION}

RUN cd /sources/downloads && wget -q https://github.com/Cyan4973/xxHash/archive/refs/tags/v${XXHASH_VERSION}.tar.gz -O xxHash-${XXHASH_VERSION}.tar.gz

ARG ZSTD_VERSION=1.5.7
ENV ZSTD_VERSION=${ZSTD_VERSION}

RUN cd /sources/downloads && wget -q https://github.com/facebook/zstd/archive/v${ZSTD_VERSION}.tar.gz -O zstd-${ZSTD_VERSION}.tar.gz

ARG LZ4_VERSION=1.10.0
ENV LZ4_VERSION=${LZ4_VERSION}

RUN cd /sources/downloads && wget -q https://github.com/lz4/lz4/archive/v${LZ4_VERSION}.tar.gz -O lz4-${LZ4_VERSION}.tar.gz

ARG ZLIB_VERSION=1.3.1
ENV ZLIB_VERSION=${ZLIB_VERSION}

RUN cd /sources/downloads && wget -q https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz -O zlib-${ZLIB_VERSION}.tar.gz

ARG ACL_VERSION=2.3.2
ENV ACL_VERSION=${ACL_VERSION}

RUN cd /sources/downloads && wget -q https://download.savannah.gnu.org/releases/acl/acl-${ACL_VERSION}.tar.gz -O acl-${ACL_VERSION}.tar.gz

ARG ATTR_VERSION=2.5.2
ENV ATTR_VERSION=${ATTR_VERSION}

RUN cd /sources/downloads && wget -q https://download.savannah.nongnu.org/releases/attr/attr-${ATTR_VERSION}.tar.gz -O attr-${ATTR_VERSION}.tar.gz

ARG GAWK_VERSION=5.3.2
ENV GAWK_VERSION=${GAWK_VERSION}

RUN cd /sources/downloads && wget -q https://ftpmirror.gnu.org/gawk/gawk-${GAWK_VERSION}.tar.xz -O gawk-${GAWK_VERSION}.tar.xz

ARG CA_CERTIFICATES_VERSION=20250619
ENV CA_CERTIFICATES_VERSION=${CA_CERTIFICATES_VERSION}

RUN cd /sources/downloads && wget -q https://gitlab.alpinelinux.org/alpine/ca-certificates/-/archive/${CA_CERTIFICATES_VERSION}/ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2 -O ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2

ARG SYSTEMD_VERSION=257.8
ENV SYSTEMD_VERSION=${SYSTEMD_VERSION}

RUN cd /sources/downloads && wget -q https://github.com/systemd/systemd/archive/refs/tags/v${SYSTEMD_VERSION}.tar.gz -O systemd-${SYSTEMD_VERSION}.tar.gz

## systemd patches

ARG OE_CORE_VERSION=30140cb9354fa535f68fab58e73b76f0cca342e4
ENV OE_CORE_VERSION=${OE_CORE_VERSION}

# Extract systemd and apply patches
RUN cd /sources/downloads && tar -xvf systemd-${SYSTEMD_VERSION}.tar.gz && \
    mv systemd-${SYSTEMD_VERSION} systemd
RUN cd /sources/downloads && git clone https://github.com/openembedded/openembedded-core && \
    cd openembedded-core && \
    git checkout ${OE_CORE_VERSION}
COPY patches/apply_all.sh /apply_all.sh
#COPY patches/systemd/ /sources/patches/systemd
RUN chmod +x /apply_all.sh
RUN /apply_all.sh /sources/downloads/openembedded-core/meta/recipes-core/systemd/systemd/ /sources/downloads/systemd
#RUN /apply_all.sh /sources/patches/systemd /sources/downloads/systemd

ARG LIBCAP_VERSION=2.76
ENV LIBCAP_VERSION=${LIBCAP_VERSION}

RUN cd /sources/downloads && wget -q https://kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-${LIBCAP_VERSION}.tar.xz -O libcap-${LIBCAP_VERSION}.tar.xz

ARG UTIL_LINUX_VERSION=2.41.1
ARG UTIL_LINUX_VERSION_MAJOR=2.41
ENV UTIL_LINUX_VERSION=${UTIL_LINUX_VERSION}

RUN cd /sources/downloads && wget -q https://www.kernel.org/pub/linux/utils/util-linux/v${UTIL_LINUX_VERSION_MAJOR}/util-linux-${UTIL_LINUX_VERSION}.tar.xz -O util-linux-${UTIL_LINUX_VERSION}.tar.xz

ARG PYTHON_VERSION=3.12.11
ENV PYTHON_VERSION=${PYTHON_VERSION}
RUN cd /sources/downloads && wget -q https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz -O Python-${PYTHON_VERSION}.tar.xz

ARG SQLITE3_VERSION=3500400
ENV SQLITE3_VERSION=${SQLITE3_VERSION}

RUN cd /sources/downloads && wget -q https://www.sqlite.org/2025/sqlite-autoconf-${SQLITE3_VERSION}.tar.gz -O sqlite-autoconf-${SQLITE3_VERSION}.tar.gz

ARG OPENSSL_VERSION=3.5.2
ENV OPENSSL_VERSION=${OPENSSL_VERSION}
RUN cd /sources/downloads && wget -q https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz 

ARG OPENSSH_VERSION=9.9p1
ENV OPENSSH_VERSION=${OPENSSH_VERSION}
RUN cd /sources/downloads && wget -q https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz

ARG PKGCONFIG_VERSION=1.8.1
ENV PKGCONFIG_VERSION=${PKGCONFIG_VERSION}
RUN cd /sources/downloads && wget -q https://distfiles.dereferenced.org/pkgconf/pkgconf-${PKGCONFIG_VERSION}.tar.xz

ARG DBUS_VERSION=1.16.2
RUN cd /sources/downloads && wget -q https://dbus.freedesktop.org/releases/dbus/dbus-${DBUS_VERSION}.tar.xz && mv dbus-${DBUS_VERSION}.tar.xz dbus.tar.xz

ARG EXPAT_VERSION=2.7.3
ARG EXPAT_VERSION_MAJOR=2
ARG EXPAT_VERSION_MINOR=7
ARG EXPAT_VERSION_PATCH=3
# expat
RUN cd /sources/downloads && wget -q https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION_MAJOR}_${EXPAT_VERSION_MINOR}_${EXPAT_VERSION_PATCH}/expat-${EXPAT_VERSION}.tar.gz && mv expat-2.7.3.tar.gz expat.tar.gz

ARG SECCOMP_VERSION=2.6.0
# seccomp
RUN cd /sources/downloads && wget -q https://github.com/seccomp/libseccomp/releases/download/v${SECCOMP_VERSION}/libseccomp-${SECCOMP_VERSION}.tar.gz && mv libseccomp-${SECCOMP_VERSION}.tar.gz libseccomp.tar.gz

ARG STRACE_VERSION=6.16
RUN cd /sources/downloads && wget -q https://strace.io/files/${STRACE_VERSION}/strace-${STRACE_VERSION}.tar.xz && mv strace-${STRACE_VERSION}.tar.xz strace.tar.xz

ARG KBD_VERSION=2.9.0
RUN cd /sources/downloads && wget -q https://www.kernel.org/pub/linux/utils/kbd/kbd-${KBD_VERSION}.tar.gz && mv kbd-${KBD_VERSION}.tar.gz kbd.tar.gz

ARG IPTABLES_VERSION=1.8.11
RUN cd /sources/downloads && wget -q https://www.netfilter.org/projects/iptables/files/iptables-${IPTABLES_VERSION}.tar.xz && mv iptables-${IPTABLES_VERSION}.tar.xz iptables.tar.xz

ARG LIBMNL_VERSION=1.0.5
RUN cd /sources/downloads && wget -q https://www.netfilter.org/projects/libmnl/files/libmnl-${LIBMNL_VERSION}.tar.bz2 && mv libmnl-${LIBMNL_VERSION}.tar.bz2 libmnl.tar.bz2

ARG LIBNFTNL_VERSION=1.3.0
RUN cd /sources/downloads && wget -q https://www.netfilter.org/projects/libnftnl/files/libnftnl-${LIBNFTNL_VERSION}.tar.xz && mv libnftnl-${LIBNFTNL_VERSION}.tar.xz libnftnl.tar.xz

## kernel
ARG KERNEL_VERSION=6.16.7
ENV KERNEL_VERSION=${KERNEL_VERSION}
RUN cd /sources/downloads && wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz

## flex

ARG FLEX_VERSION=2.6.4
ENV FLEX_VERSION=${FLEX_VERSION}
RUN cd /sources/downloads && wget -q https://github.com/westes/flex/releases/download/v${FLEX_VERSION}/flex-${FLEX_VERSION}.tar.gz

## bison

ARG BISON_VERSION=3.8.2
ENV BISON_VERSION=${BISON_VERSION}
RUN cd /sources/downloads && wget -q https://ftpmirror.gnu.org/bison/bison-${BISON_VERSION}.tar.xz


## argp-standalone

ARG ARGP_STANDALONE_VERSION=1.3
ENV ARGP_STANDALONE_VERSION=${ARGP_STANDALONE_VERSION}
RUN cd /sources/downloads && wget -q http://www.lysator.liu.se/~nisse/misc/argp-standalone-${ARGP_STANDALONE_VERSION}.tar.gz

## autoconf

ARG AUTOCONF_VERSION=2.71
ENV AUTOCONF_VERSION=${AUTOCONF_VERSION}
RUN cd /sources/downloads && wget -q https://ftpmirror.gnu.org/autoconf/autoconf-${AUTOCONF_VERSION}.tar.xz

## automake

ARG AUTOMAKE_VERSION=1.18.1
ENV AUTOMAKE_VERSION=${AUTOMAKE_VERSION}
RUN cd /sources/downloads && wget -q https://ftpmirror.gnu.org/automake/automake-${AUTOMAKE_VERSION}.tar.xz

## fts

ARG FTS_VERSION=1.2.7
ENV FTS_VERSION=${FTS_VERSION}
RUN cd /sources/downloads && wget -q https://github.com/pullmoll/musl-fts/archive/v${FTS_VERSION}.tar.gz -O musl-fts-${FTS_VERSION}.tar.gz

## libtool

ARG LIBTOOL_VERSION=2.5.4
ENV LIBTOOL_VERSION=${LIBTOOL_VERSION}
RUN cd /sources/downloads && wget -q https://ftpmirror.gnu.org/libtool/libtool-${LIBTOOL_VERSION}.tar.xz

## musl-obstack
ARG MUSL_OBSTACK_VERSION=1.2.3
ENV MUSL_OBSTACK_VERSION=${MUSL_OBSTACK_VERSION}
RUN cd /sources/downloads && wget -q https://github.com/void-linux/musl-obstack/archive/v${MUSL_OBSTACK_VERSION}.tar.gz -O musl-obstack-${MUSL_OBSTACK_VERSION}.tar.gz

## elfutils

ARG ELFUTILS_VERSION=0.193
ENV ELFUTILS_VERSION=${ELFUTILS_VERSION}
RUN cd /sources/downloads && wget -q https://sourceware.org/elfutils/ftp/${ELFUTILS_VERSION}/elfutils-${ELFUTILS_VERSION}.tar.bz2

RUN cd /sources/downloads && mkdir -p elfutils-patches && wget -q https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/main/elfutils/musl-macros.patch -O elfutils-patches/musl-macros.patch

## xzutils
ARG XZUTILS_VERSION=5.8.1
ENV XZUTILS_VERSION=${XZUTILS_VERSION}

RUN cd /sources/downloads && wget -q https://tukaani.org/xz/xz-${XZUTILS_VERSION}.tar.gz && mv xz-${XZUTILS_VERSION}.tar.gz xz.tar.gz

## kmod
ARG KMOD_VERSION=34
ENV KMOD_VERSION=${KMOD_VERSION}

RUN cd /sources/downloads && wget -q https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-${KMOD_VERSION}.tar.gz && mv kmod-${KMOD_VERSION}.tar.gz kmod.tar.gz

## dracut
ARG DRACUT_VERSION=108
ENV DRACUT_VERSION=${DRACUT_VERSION}

RUN cd /sources/downloads && wget -q https://github.com/dracut-ng/dracut-ng/archive/refs/tags/${DRACUT_VERSION}.tar.gz && mv ${DRACUT_VERSION}.tar.gz dracut.tar.gz

## libaio

ARG LIBAIO_VERSION=0.3.113
ENV LIBAIO_VERSION=${LIBAIO_VERSION}

RUN cd /sources/downloads && wget -q https://pagure.io/libaio/archive/libaio-${LIBAIO_VERSION}/libaio-libaio-${LIBAIO_VERSION}.tar.gz && mv libaio-libaio-${LIBAIO_VERSION}.tar.gz libaio.tar.gz

## lvm2
ARG LVM2_VERSION=2.03.35
ENV LVM2_VERSION=${LVM2_VERSION}

RUN cd /sources/downloads && wget -q http://ftp-stud.fht-esslingen.de/pub/Mirrors/sourceware.org/lvm2/releases/LVM2.${LVM2_VERSION}.tgz && mv LVM2.${LVM2_VERSION}.tgz lvm2.tgz


## multipath-tools
ARG MULTIPATH_TOOLS_VERSION=0.11.1
ENV MULTIPATH_TOOLS_VERSION=${MULTIPATH_TOOLS_VERSION}

RUN cd /sources/downloads && wget -q https://github.com/opensvc/multipath-tools/archive/refs/tags/${MULTIPATH_TOOLS_VERSION}.tar.gz && mv ${MULTIPATH_TOOLS_VERSION}.tar.gz multipath-tools.tar.gz


## jsonc
ARG JSONC_VERSION=0.18
ENV JSONC_VERSION=${JSONC_VERSION}

RUN cd /sources/downloads && wget -q https://s3.amazonaws.com/json-c_releases/releases/json-c-${JSONC_VERSION}.tar.gz && mv json-c-${JSONC_VERSION}.tar.gz json-c.tar.gz

## cmake
ARG CMAKE_VERSION=4.1.1
ENV CMAKE_VERSION=${CMAKE_VERSION}

RUN cd /sources/downloads && wget -q https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}.tar.gz && mv cmake-${CMAKE_VERSION}.tar.gz cmake.tar.gz

## urcu
ARG URCU_VERSION=0.15.2
ENV URCU_VERSION=${URCU_VERSION}
RUN cd /sources/downloads && wget -q https://lttng.org/files/urcu/userspace-rcu-${URCU_VERSION}.tar.bz2 && mv userspace-rcu-${URCU_VERSION}.tar.bz2 urcu.tar.bz2


## parted
ARG PARTED_VERSION=3.6
ENV PARTED_VERSION=${PARTED_VERSION}

RUN cd /sources/downloads && wget -q https://ftpmirror.gnu.org/gnu/parted/parted-${PARTED_VERSION}.tar.xz && mv parted-${PARTED_VERSION}.tar.xz parted.tar.xz

## e2fsprogs
ARG E2FSPROGS_VERSION=1.46.6
ENV E2FSPROGS_VERSION=${E2FSPROGS_VERSION}

RUN cd /sources/downloads && wget -q https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v${E2FSPROGS_VERSION}/e2fsprogs-${E2FSPROGS_VERSION}.tar.xz && mv e2fsprogs-${E2FSPROGS_VERSION}.tar.xz e2fsprogs.tar.xz

## dosfstools
ARG DOSFSTOOLS_VERSION=4.2
ENV DOSFSTOOLS_VERSION=${DOSFSTOOLS_VERSION}
RUN cd /sources/downloads && wget -q https://github.com/dosfstools/dosfstools/releases/download/v${DOSFSTOOLS_VERSION}/dosfstools-${DOSFSTOOLS_VERSION}.tar.gz && mv dosfstools-${DOSFSTOOLS_VERSION}.tar.gz dosfstools.tar.gz

## sgdisk
ARG SGDISK_VERSION=1.0.8
ENV SGDISK_VERSION=${SGDISK_VERSION}
RUN cd /sources/downloads && wget -q https://downloads.sourceforge.net/project/gptfdisk/gptfdisk/${SGDISK_VERSION}/gptfdisk-${SGDISK_VERSION}.tar.gz && mv gptfdisk-${SGDISK_VERSION}.tar.gz gptfdisk.tar.gz


## cryptsetup
ARG CRYPTSETUP_VERSION=2.8.1
ENV CRYPTSETUP_VERSION=${CRYPTSETUP_VERSION}
RUN cd /sources/downloads && wget -q https://cdn.kernel.org/pub/linux/utils/cryptsetup/v${CRYPTSETUP_VERSION%.*}/cryptsetup-${CRYPTSETUP_VERSION}.tar.xz && mv cryptsetup-${CRYPTSETUP_VERSION}.tar.xz cryptsetup.tar.xz


## grub
ARG GRUB_VERSION=2.12
ENV GRUB_VERSION=${GRUB_VERSION}
RUN cd /sources/downloads && wget -q https://mirrors.edge.kernel.org/gnu/grub/grub-${GRUB_VERSION}.tar.xz && mv grub-${GRUB_VERSION}.tar.xz grub.tar.xz


## PAM
ARG PAM_VERSION=1.7.1
ENV PAM_VERSION=${PAM_VERSION}

RUN cd /sources/downloads && wget -q https://github.com/linux-pam/linux-pam/releases/download/v${PAM_VERSION}/Linux-PAM-${PAM_VERSION}.tar.xz && mv Linux-PAM-${PAM_VERSION}.tar.xz pam.tar.xz

# shadow
ARG SHADOW_VERSION=4.18.0
ENV SHADOW_VERSION=${SHADOW_VERSION}
RUN cd /sources/downloads && wget -q https://github.com/shadow-maint/shadow/releases/download/${SHADOW_VERSION}/shadow-${SHADOW_VERSION}.tar.xz && mv shadow-${SHADOW_VERSION}.tar.xz shadow.tar.xz


# cloud-utils for growpart
ARG CLOUD_UTILS_VERSION=0.33
ENV CLOUD_UTILS_VERSION=${CLOUD_UTILS_VERSION}
RUN cd /sources/downloads && wget -q https://github.com/canonical/cloud-utils/archive/refs/tags/${CLOUD_UTILS_VERSION}.tar.gz && mv ${CLOUD_UTILS_VERSION}.tar.gz cloud-utils.tar.gz


# alpine aports repo for patches to build under musl
ARG APORTS_VERSION=3.22.1
ENV APORTS_VERSION=${APORTS_VERSION}

RUN cd /sources/downloads && wget -q https://gitlab.alpinelinux.org/alpine/aports/-/archive/v${APORTS_VERSION}/aports-v${APORTS_VERSION}.tar.gz && mv aports-v${APORTS_VERSION}.tar.gz aports.tar.gz

## busybox
ARG BUSYBOX_VERSION=1.37.0
ENV BUSYBOX_VERSION=${BUSYBOX_VERSION}
# XXX: Temporary workaround as busybox currently have expired certificates
RUN cd /sources/downloads && wget -q --no-check-certificate https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2

## musl
ARG MUSL_VERSION=1.2.5
ENV MUSL_VERSION=${MUSL_VERSION}
RUN cd /sources/downloads && wget -q http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz

## gcc and dependencies
ARG GCC_VERSION=14.3.0
ENV GCC_VERSION=${GCC_VERSION}
ARG GMP_VERSION=6.3.0
ENV GMP_VERSION=${GMP_VERSION}
ARG MPC_VERSION=1.3.1
ENV MPC_VERSION=${MPC_VERSION}
ARG MPFR_VERSION=4.2.2
ENV MPFR_VERSION=${MPFR_VERSION}
RUN cd /sources/downloads && wget -q http://mirror.netcologne.de/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
RUN cd /sources/downloads && wget -q http://mirror.netcologne.de/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2
RUN cd /sources/downloads && wget -q http://mirror.netcologne.de/gnu/mpc/mpc-${MPC_VERSION}.tar.gz
RUN cd /sources/downloads && wget -q http://mirror.netcologne.de/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2

## make
ARG MAKE_VERSION=4.4.1
ENV MAKE_VERSION=${MAKE_VERSION}
RUN cd /sources/downloads && wget -q https://mirror.netcologne.de/gnu/make/make-${MAKE_VERSION}.tar.gz

## binutils (for stage0)
ARG BINUTILS_VERSION=2.44
ENV BINUTILS_VERSION=${BINUTILS_VERSION}
RUN cd /sources/downloads && wget -q http://mirror.easyname.at/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz

## popt
ARG POPT_VERSION=1.19
ENV POPT_VERSION=${POPT_VERSION}
RUN cd /sources/downloads && wget -q http://ftp.rpm.org/popt/releases/popt-1.x/popt-${POPT_VERSION}.tar.gz

## ncurses
ARG NCURSES_VERSION=6.5
ENV NCURSES_VERSION=${NCURSES_VERSION}
RUN cd /sources/downloads && wget -q http://ftpmirror.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz

## m4
ARG M4_VERSION=1.4.20
ENV M4_VERSION=${M4_VERSION}
RUN cd /sources/downloads && wget -q http://mirror.easyname.at/gnu/m4/m4-${M4_VERSION}.tar.xz

## readline
ARG READLINE_VERSION=8.3
ENV READLINE_VERSION=${READLINE_VERSION}
RUN cd /sources/downloads && wget -q http://mirror.easyname.at/gnu/readline/readline-${READLINE_VERSION}.tar.gz

## bash
ARG BASH_VERSION=5.3
ENV BASH_VERSION=${BASH_VERSION}
RUN cd /sources/downloads && wget -q http://mirror.easyname.at/gnu/bash/bash-${BASH_VERSION}.tar.gz

## perl
ARG PERL_VERSION=5.42.0
ENV PERL_VERSION=${PERL_VERSION}
RUN cd /sources/downloads && wget -q http://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.xz

## coreutils
ARG COREUTILS_VERSION=9.6
ENV COREUTILS_VERSION=${COREUTILS_VERSION}
RUN cd /sources/downloads && wget -q http://mirror.easyname.at/gnu/coreutils/coreutils-${COREUTILS_VERSION}.tar.xz

## findutils
ARG FINDUTILS_VERSION=4.10.0
ENV FINDUTILS_VERSION=${FINDUTILS_VERSION}
RUN cd /sources/downloads && wget -q http://mirror.easyname.at/gnu/findutils/findutils-${FINDUTILS_VERSION}.tar.xz

## grep
ARG GREP_VERSION=3.12
ENV GREP_VERSION=${GREP_VERSION}
RUN cd /sources/downloads && wget -q http://mirror.easyname.at/gnu/grep/grep-${GREP_VERSION}.tar.xz

## gperf
ARG GPERF_VERSION=3.3
ENV GPERF_VERSION=${GPERF_VERSION}
RUN cd /sources/downloads && wget -q http://mirror.easyname.at/gnu/gperf/gperf-${GPERF_VERSION}.tar.gz

## diffutils
ARG DIFFUTILS_VERSION=3.9
ENV DIFFUTILS_VERSION=${DIFFUTILS_VERSION}
RUN cd /sources/downloads && wget -q http://ftpmirror.gnu.org/diffutils/diffutils-${DIFFUTILS_VERSION}.tar.xz

## sudo
ARG SUDO_VERSION=1.9.17p2
ENV SUDO_VERSION=${SUDO_VERSION}
RUN cd /sources/downloads && wget -q https://www.sudo.ws/dist/sudo-${SUDO_VERSION}.tar.gz && mv sudo-${SUDO_VERSION}.tar.gz sudo.tar.gz

## pax-utils
ARG PAX_UTILS_VERSION=1.3.8
ENV PAX_UTILS_VERSION=${PAX_UTILS_VERSION}
RUN cd /sources/downloads && wget -q https://dev.gentoo.org/~sam/distfiles/app-misc/pax-utils/pax-utils-${PAX_UTILS_VERSION}.tar.xz && mv pax-utils-${PAX_UTILS_VERSION}.tar.xz pax-utils.tar.xz

## openscsi

ARG OPEN_SCSI_VERSION=2.1.11
ENV OPEN_SCSI_VERSION=${OPEN_SCSI_VERSION}

RUN cd /sources/downloads && wget -q https://github.com/open-iscsi/open-iscsi/archive/refs/tags/${OPEN_SCSI_VERSION}.tar.gz && mv ${OPEN_SCSI_VERSION}.tar.gz openscsi.tar.gz


# GDB
ARG GDB_VERSION=16.3
RUN cd /sources/downloads && wget -q https://sourceware.org/pub/gdb/releases/gdb-${GDB_VERSION}.tar.gz && mv gdb-${GDB_VERSION}.tar.gz gdb.tar.gz


ARG LIBFFI_VERSION=3.5.2
RUN cd /sources/downloads && wget -q https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz && mv libffi-${LIBFFI_VERSION}.tar.gz libffi.tar.gz

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

ARG BUSYBOX_VERSION=1.37.0
ENV BUSYBOX_VERSION=${BUSYBOX_VERSION}

COPY --from=sources-downloader /sources/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 /sources/ 

RUN cd /sources && tar -xf busybox-${BUSYBOX_VERSION}.tar.bz2 && \
    cd busybox-${BUSYBOX_VERSION} && \
    make -s distclean && \
    make -s ARCH="${ARCH}" defconfig && \
    sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config && \
    sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_TC\)=y/# \1 is not set/' .config && \
    make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS} && \
    make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS} CONFIG_PREFIX="/sysroot" install

###
### MUSL
###
FROM stage0 AS musl-stage0
ARG MUSL_VERSION=1.2.5
ENV MUSL_VERSION=${MUSL_VERSION}

COPY --from=sources-downloader /sources/downloads/musl-${MUSL_VERSION}.tar.gz /sources/
RUN cd /sources && tar -xf musl-${MUSL_VERSION}.tar.gz && \
    cd musl-${MUSL_VERSION} && \
    ./configure --disable-warnings \
      CROSS_COMPILE=${TARGET}- \
      --prefix=/usr \
      --disable-static \
      --target=${TARGET} && \
      make -s -j${JOBS} && \
      DESTDIR=/sysroot make -s -j${JOBS} install

###
### GCC
###
FROM stage0 AS gcc-stage0
ARG GCC_VERSION=14.3.0
ENV GCC_VERSION=${GCC_VERSION}
ARG GMP_VERSION=6.3.0
ENV GMP_VERSION=${GMP_VERSION}
ARG MPC_VERSION=1.3.1
ENV MPC_VERSION=${MPC_VERSION}
ARG MPFR_VERSION=4.2.2
ENV MPFR_VERSION=${MPFR_VERSION}
COPY --from=sources-downloader /sources/downloads/gcc-${GCC_VERSION}.tar.xz .
COPY --from=sources-downloader /sources/downloads/gmp-${GMP_VERSION}.tar.bz2 .
COPY --from=sources-downloader /sources/downloads/mpc-${MPC_VERSION}.tar.gz .
COPY --from=sources-downloader /sources/downloads/mpfr-${MPFR_VERSION}.tar.bz2 .
RUN tar -xf gcc-${GCC_VERSION}.tar.xz
RUN tar -xf gmp-${GMP_VERSION}.tar.bz2
RUN tar -xf mpc-${MPC_VERSION}.tar.gz
RUN tar -xf mpfr-${MPFR_VERSION}.tar.bz2

RUN <<EOT bash
    mv -v mpfr-${MPFR_VERSION} gcc-${GCC_VERSION}/mpfr
    mv -v mpc-${MPC_VERSION} gcc-${GCC_VERSION}/mpc
    mv -v gmp-${GMP_VERSION} gcc-${GCC_VERSION}/gmp
    mkdir -p /sysroot/usr/include
    cd gcc-${GCC_VERSION} && mkdir -v build && cd build && ../configure --quiet \
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
        make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS} && \
        make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" DESTDIR=/sysroot install ;
EOT

###
### Make
###
FROM stage0 AS make-stage0

ARG MAKE_VERSION=4.4.1
ENV MAKE_VERSION=${MAKE_VERSION}

COPY --from=sources-downloader /sources/downloads/make-${MAKE_VERSION}.tar.gz /sources/

RUN cd /sources && tar -xf make-${MAKE_VERSION}.tar.gz && \
    cd make-${MAKE_VERSION} && \
    ./configure --quiet --prefix=/usr \
    --build=${BUILD_ARCH} --host=${TARGET} && \
    make -s -j${JOBS} && \
    make -s -j${JOBS} DESTDIR=/sysroot install


###
### Binutils
###
FROM stage0 AS binutils-stage0

ENV BINUTILS_VERSION=2.44
ENV BINUTILS_VERSION=${BINUTILS_VERSION}

COPY --from=sources-downloader /sources/downloads/binutils-${BINUTILS_VERSION}.tar.xz .
RUN tar -xf binutils-${BINUTILS_VERSION}.tar.xz

RUN <<EOT bash
    cd binutils-${BINUTILS_VERSION} && 
    ./configure --quiet \
       --prefix=/usr \
       --build=${BUILD_ARCH} \
       --host=${TARGET} \
       --target=${TARGET} \
       --with-sysroot=/ \
       --disable-nls \
       --disable-multilib \
       --enable-shared && \
       make -s -j${JOBS} && \
       make -s -j${JOBS} DESTDIR=/sysroot install ;
EOT

## This is a hack to avoid to need the kernel headers to compile things like busybox
FROM alpine:${ALPINE_VERSION} AS alpine-hack
RUN apk add linux-headers

########################################################
#
# Stage 1 - Assembling image from stage0 with build tools
#
########################################################

# Here we assemble our building image that we will use to build all the other packages, and assemble again from scratch+skeleton
FROM stage0 AS stage1-merge

RUN apk add rsync

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

## This is a hack to avoid to need the kernel headers to compile things like busybox
COPY --from=alpine-hack /usr/include/linux /linux
RUN mkdir -p /skeleton/usr/include/linux && rsync -aHAX --keep-dirlinks  /linux/. /skeleton/usr/include/linux

COPY --from=alpine-hack /usr/include/asm /asm
RUN mkdir -p /skeleton/usr/include/asm && rsync -aHAX --keep-dirlinks  /asm/. /skeleton/usr/include/asm

COPY --from=alpine-hack /usr/include/asm-generic /asm-generic
RUN mkdir -p /skeleton/usr/include/asm-generic && rsync -aHAX --keep-dirlinks  /asm-generic/. /skeleton/usr/include/asm-generic

COPY --from=alpine-hack /usr/include/mtd /mtd
RUN mkdir -p /skeleton/usr/include/mtd && rsync -aHAX --keep-dirlinks  /mtd/. /skeleton/usr/include/mtd

# Provide ldconfig in the image
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /aports/aports.tar.gz
WORKDIR /aports
RUN tar xf aports.tar.gz && mv aports-* aports
RUN cp aports/main/musl/ldconfig /skeleton/usr/bin/ldconfig && chmod +x /skeleton//usr/bin/ldconfig
## END of HACK

FROM scratch AS stage1

ARG VENDOR="hadron"
ARG ARCH="x86-64"
ARG BUILD_ARCH="x86_64"
ARG CFLAGS
ENV VENDOR=${VENDOR}
ENV BUILD_ARCH=${BUILD_ARCH}
ENV TARGET=${BUILD_ARCH}-${VENDOR}-linux-musl
ENV BUILD=${BUILD_ARCH}-pc-linux-musl
ENV COMMON_CONFIGURE_ARGS="--quiet --prefix=/usr --host=${TARGET} --build=${BUILD} --enable-lto --enable-shared --disable-static"
ENV CFLAGS="${CFLAGS} -Os -pipe -fomit-frame-pointer -fno-unroll-loops -fno-asynchronous-unwind-tables"
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

ARG MUSL_VERSION=1.2.5
ENV MUSL_VERSION=${MUSL_VERSION}

COPY --from=sources-downloader /sources/downloads/musl-${MUSL_VERSION}.tar.gz .
RUN tar -xf musl-${MUSL_VERSION}.tar.gz && \
    cd musl-${MUSL_VERSION} && \
    ./configure --disable-warnings \
      --prefix=/usr \
      --disable-static && \
      make -s -j${JOBS} && \
      DESTDIR=/sysroot make -s -j${JOBS} install

## pkgconfig
FROM stage1 AS pkgconfig

ARG PKGCONFIG_VERSION=1.8.1
ENV PKGCONFIG_VERSION=${PKGCONFIG_VERSION}

COPY --from=sources-downloader /sources/downloads/pkgconf-${PKGCONFIG_VERSION}.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf pkgconf-${PKGCONFIG_VERSION}.tar.xz && mv pkgconf-${PKGCONFIG_VERSION} pkgconfig && \
    cd pkgconfig && mkdir -p /pkgconfig && ./configure --quiet ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --localstatedir=/var \
    --with-pkg-config-dir=/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig && \
    make -s -j${JOBS} && \
    make -s -j${JOBS} DESTDIR=/pkgconfig install && make -s -j${JOBS} install && ln -s pkgconf /pkgconfig/usr/bin/pkg-config

## xxhash
FROM stage1 AS xxhash

ARG XXHASH_VERSION=0.8.3
ENV XXHASH_VERSION=${XXHASH_VERSION}

COPY --from=sources-downloader /sources/downloads/xxHash-${XXHASH_VERSION}.tar.gz /sources/
ENV CC="gcc"
RUN mkdir -p /sources && cd /sources && tar -xf xxHash-${XXHASH_VERSION}.tar.gz && mv xxHash-${XXHASH_VERSION} xxhash && \
    tar -xf xxHash-${XXHASH_VERSION}.tar.gz && mv xxHash-${XXHASH_VERSION} xxhash && \
    cd xxhash && mkdir -p /xxhash && CC=gcc make -s -j${JOBS} prefix=/usr DESTDIR=/xxhash && \
    make -s -j${JOBS} prefix=/usr DESTDIR=/xxhash install && make -s -j${JOBS} prefix=/usr install

## zstd
FROM xxhash AS zstd

ARG ZSTD_VERSION=1.5.7
ENV ZSTD_VERSION=${ZSTD_VERSION}

COPY --from=sources-downloader /sources/downloads/zstd-${ZSTD_VERSION}.tar.gz /sources/
RUN mkdir -p /zstd
WORKDIR /sources
RUN tar -xf zstd-${ZSTD_VERSION}.tar.gz && mv zstd-${ZSTD_VERSION} zstd
WORKDIR /sources/zstd
ENV CC=gcc
RUN make -s -j${JOBS} DESTDIR=/zstd prefix=/usr
RUN make -s -j${JOBS} DESTDIR=/zstd prefix=/usr install
RUN make -s -j${JOBS} prefix=/usr install

## lz4
FROM zstd AS lz4

ARG LZ4_VERSION=1.10.0
ENV LZ4_VERSION=${LZ4_VERSION}

COPY --from=sources-downloader /sources/downloads/lz4-${LZ4_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf lz4-${LZ4_VERSION}.tar.gz && mv lz4-${LZ4_VERSION} lz4 && \
    cd lz4 && mkdir -p /lz4 && CC=gcc make -s -j${JOBS} prefix=/usr DESTDIR=/lz4 && \
    make -s -j${JOBS} prefix=/usr DESTDIR=/lz4 install && make -s -j${JOBS} prefix=/usr install

## attr
FROM lz4 AS attr

ARG ATTR_VERSION=2.5.2
ENV ATTR_VERSION=${ATTR_VERSION}

COPY --from=sources-downloader /sources/downloads/attr-${ATTR_VERSION}.tar.gz /sources/
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /sources/patches/

RUN mkdir -p /attr

# extract the aport patch to apply to attr
WORKDIR /sources/patches
RUN tar -xf aports.tar.gz && mv aports-* aport
WORKDIR /sources
RUN tar -xf attr-${ATTR_VERSION}.tar.gz && mv attr-${ATTR_VERSION} attr
WORKDIR /sources/attr
RUN patch -p1 < /sources/patches/aport/main/attr/attr-basename.patch
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --localstatedir=/var \
    --disable-nls
RUN make -s -j${JOBS} DESTDIR=/attr
RUN make -s -j${JOBS} DESTDIR=/attr install
RUN make -s -j${JOBS} install

## acl
FROM attr AS acl

ARG ACL_VERSION=2.3.2
ENV ACL_VERSION=${ACL_VERSION}

COPY --from=sources-downloader /sources/downloads/acl-${ACL_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf acl-${ACL_VERSION}.tar.gz && mv acl-${ACL_VERSION} acl && \
    tar -xf acl-${ACL_VERSION}.tar.gz && mv acl-${ACL_VERSION} acl && \
    cd acl && mkdir -p /acl && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --libexecdir=/usr/libexec && make -s -j${JOBS} DESTDIR=/acl && \
    make -s -j${JOBS} DESTDIR=/acl install && make -s -j${JOBS} install

## popt
FROM acl AS popt

ARG POPT_VERSION=1.19
ENV POPT_VERSION=${POPT_VERSION}

COPY --from=sources-downloader /sources/downloads/popt-${POPT_VERSION}.tar.gz /sources/
RUN cd /sources && \
    tar -xf popt-${POPT_VERSION}.tar.gz && mv popt-${POPT_VERSION} popt && \
    cd popt && mkdir -p /popt && ./configure  ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking  && make -s -j${JOBS} DESTDIR=/popt && \
    make -s -j${JOBS} DESTDIR=/popt install && make -s -j${JOBS} install

## zlib
FROM popt AS zlib

ARG ZLIB_VERSION=1.3.1
ENV ZLIB_VERSION=${ZLIB_VERSION}

COPY --from=sources-downloader /sources/downloads/zlib-${ZLIB_VERSION}.tar.gz /sources/
RUN mkdir -p /zlib
WORKDIR /sources
RUN tar -xf zlib-${ZLIB_VERSION}.tar.gz && mv zlib-${ZLIB_VERSION} zlib
WORKDIR /sources/zlib
RUN ./configure --shared --prefix=/usr
RUN make -s -j${JOBS} DESTDIR=/zlib
RUN make -s -j${JOBS} DESTDIR=/zlib install
RUN make -s -j${JOBS} install

## gawk

FROM zlib AS gawk

ARG GAWK_VERSION=5.3.2
ENV GAWK_VERSION=${GAWK_VERSION}

COPY --from=sources-downloader /sources/downloads/gawk-${GAWK_VERSION}.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf gawk-${GAWK_VERSION}.tar.xz && mv gawk-${GAWK_VERSION} gawk && \
    cd gawk && mkdir -p /gawk && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr -sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --disable-nls \
    --disable-pma && make -s -j${JOBS} DESTDIR=/gawk && \
    make -s -j${JOBS} DESTDIR=/gawk install && make -s -j${JOBS} install

## rsync
FROM gawk AS rsync

ARG RSYNC_VERSION=3.4.1
ENV RSYNC_VERSION=${RSYNC_VERSION}

COPY --from=sources-downloader /sources/downloads/rsync-${RSYNC_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf rsync-${RSYNC_VERSION}.tar.gz && mv rsync-${RSYNC_VERSION} rsync && \
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
    --disable-openssl && make -s -j${JOBS} DESTDIR=/rsync && \
    make -s -j${JOBS} DESTDIR=/rsync install && make -s -j${JOBS} install

## binutils
FROM stage1 AS binutils

ARG BINUTILS_VERSION=2.44
ENV BINUTILS_VERSION=${BINUTILS_VERSION}
ARG JOBS
COPY --from=sources-downloader /sources/downloads/binutils-${BINUTILS_VERSION}.tar.xz /sources/
RUN cd /sources && \
    tar -xf binutils-${BINUTILS_VERSION}.tar.xz && mv binutils-${BINUTILS_VERSION} binutils && \
    cd binutils && mkdir -p /binutils
WORKDIR /sources/binutils
ENV AR=ar
ENV GCC=gcc
ENV AS=as
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} DESTDIR=/binutils
RUN make -s -j${JOBS} DESTDIR=/binutils install
RUN make -s -j${JOBS} install

## ncurses
FROM stage1 AS ncurses

ARG NCURSES_VERSION=6.5
ENV NCURSES_VERSION=${NCURSES_VERSION}

COPY --from=sources-downloader /sources/downloads/ncurses-${NCURSES_VERSION}.tar.gz /sources/
RUN cd /sources && \
    tar -xf ncurses-${NCURSES_VERSION}.tar.gz && mv ncurses-${NCURSES_VERSION} ncurses && \
    cd ncurses && mkdir -p /ncurses && sed -i s/mawk// configure && mkdir build && \
    cd build && ../configure --quiet ${COMMON_CONFIGURE_ARGS} && make -s -C include &&  make -s -C progs tic && cd .. && \
    ./configure --quiet ${COMMON_CONFIGURE_ARGS} \
    --mandir=/usr/share/man \
    --with-manpage-format=normal \
    --with-shared \
    --without-debug \
    --without-ada \
    --without-normal \
    --disable-stripping \
    --enable-widec && \
    make -s -j${JOBS} && \
    make -s DESTDIR=/ncurses TIC_PATH=/sources/ncurses/build/progs/tic install && make -s -j${JOBS} install && echo "INPUT(-lncursesw)" > /ncurses/usr/lib/libncurses.so && \
    cp /ncurses/usr/lib/libncurses.so /usr/lib/libncurses.so

## m4 (from stage1, ready to be used in the final image)
FROM stage1 AS m4

ARG M4_VERSION=1.4.20
ENV M4_VERSION=${M4_VERSION}

COPY --from=sources-downloader /sources/downloads/m4-${M4_VERSION}.tar.xz /sources/
RUN cd /sources && \
    tar -xf m4-${M4_VERSION}.tar.xz && mv m4-${M4_VERSION} m4 && \
    cd m4 && mkdir -p /m4 && ./configure --quiet ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking && make -s -j${JOBS} DESTDIR=/m4 && \
    make -s -j${JOBS} DESTDIR=/m4 install && make -s -j${JOBS} install

## readline
FROM stage1 AS readline

ARG READLINE_VERSION=8.3
ENV READLINE_VERSION=${READLINE_VERSION}

COPY --from=sources-downloader /sources/downloads/readline-${READLINE_VERSION}.tar.gz /sources/
RUN cd /sources && \
    tar -xf readline-${READLINE_VERSION}.tar.gz && mv readline-${READLINE_VERSION} readline && \
    cd readline && mkdir -p /readline && ./configure --quiet ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking && make -s -j${JOBS} DESTDIR=/readline && \
    make -s -j${JOBS} DESTDIR=/readline install && make -s -j${JOBS} install

## bash
FROM readline AS bash

ARG BASH_VERSION=5.3
ENV BASH_VERSION=${BASH_VERSION}

COPY ./files/bash/bashrc /sources/bashrc
COPY ./files/bash/profile-bashrc.sh /sources/profile-bashrc.sh
COPY --from=sources-downloader /sources/downloads/bash-${BASH_VERSION}.tar.gz /sources/
RUN cd /sources && \
    tar -xf bash-${BASH_VERSION}.tar.gz && mv bash-${BASH_VERSION} bash && \
    cd bash && mkdir -p /bash && ./configure --quiet ${COMMON_CONFIGURE_ARGS} \
    --build=${BUILD} \
    --host=${TARGET} \
    --prefix=/usr \
    --bindir=/bin \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    #--with-curses \
    --disable-nls \
    --enable-readline \
    --without-bash-malloc \
    --with-installed-readline && make -s -j${JOBS} y.tab.c && make -s -j${JOBS} builtins/libbuiltins.a && make -s -j${JOBS} && \
    mkdir -p /bash/etc/bash && \
    install -Dm644  /sources/bashrc /bash/etc/bash/bashrc && \
    install -Dm644  /sources/profile-bashrc.sh /bash/etc/profile.d/00-bashrc.sh && \
    make -s -j${JOBS} DESTDIR=/bash install && make -s -j${JOBS} install # && rm -rf /bash/usr/share/locale

## libcap
FROM bash AS libcap

ARG LIBCAP_VERSION=2.76
ENV LIBCAP_VERSION=${LIBCAP_VERSION}

COPY --from=sources-downloader /sources/downloads/libcap-${LIBCAP_VERSION}.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf libcap-${LIBCAP_VERSION}.tar.xz && mv libcap-${LIBCAP_VERSION} libcap && \
    cd libcap && mkdir -p /libcap && make -s -j${JOBS} BUILD_CC=gcc CC="${CC:-gcc}" && \
    make -s -j${JOBS} DESTDIR=/libcap PAM_LIBDIR=/lib prefix=/usr SBINDIR=/sbin lib=lib RAISE_SETFCAP=no GOLANG=no install && make -s -j${JOBS} GOLANG=no PAM_LIBDIR=/lib lib=lib prefix=/usr SBINDIR=/sbin RAISE_SETFCAP=no install

## perl
FROM m4 AS perl

ARG PERL_VERSION=5.42.0
ENV PERL_VERSION=${PERL_VERSION}

ENV CFLAGS="${CFLAGS} -static -ffunction-sections -fdata-sections -Bsymbolic-functions"
ENV LDFLAGS="-Wl,--gc-sections"
ENV PERL_CROSS=1.6.2

COPY --from=sources-downloader /sources/downloads/perl-${PERL_VERSION}.tar.xz /sources/
RUN cd /sources && \
    tar -xf perl-${PERL_VERSION}.tar.xz && mv perl-${PERL_VERSION} perl && \
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
        make -s -j${JOBS} DESTDIR=/perl && make -s -j${JOBS} DESTDIR=/perl install && make -s -j${JOBS} install

## openssl
FROM rsync AS openssl

ARG OPENSSL_VERSION=3.5.2
ENV OPENSSL_VERSION=${OPENSSL_VERSION}

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /

COPY --from=sources-downloader /sources/downloads/openssl-${OPENSSL_VERSION}.tar.gz /sources/

RUN cd /sources && tar -xf openssl-${OPENSSL_VERSION}.tar.gz && mv openssl-${OPENSSL_VERSION} openssl && \
    cd openssl && mkdir -p /openssl && ./Configure --prefix=/usr         \
    --openssldir=/etc/ssl \
    --libdir=lib          \
    shared zlib-dynamic 2>&1 && \
    make -s -j${JOBS} DESTDIR=/openssl 2>&1  && \
    make -s -j${JOBS} DESTDIR=/openssl install_sw install_ssldirs && make -s -j${JOBS} install_sw install_ssldirs

## Busybox (from stage1, ready to be used in the final image)
FROM openssl AS busybox

COPY --from=busybox-stage0 /sources /sources

ARG BUSYBOX_VERSION=1.37.0
ENV BUSYBOX_VERSION=${BUSYBOX_VERSION}

RUN cd /sources && rm -rfv busybox-${BUSYBOX_VERSION} && tar -xf busybox-${BUSYBOX_VERSION}.tar.bz2 && \
    cd busybox-${BUSYBOX_VERSION} && \
    make -s distclean && \
    make -s defconfig && \
    sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config && \
    sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_TC\)=y/# \1 is not set/' .config
RUN cd /sources/busybox-${BUSYBOX_VERSION} && \
    make -s && \
    make -s CONFIG_PREFIX="/sysroot" install && make -s -j${JOBS} install

## coreutils
FROM rsync AS coreutils

ARG COREUTILS_VERSION=9.6
ENV COREUTILS_VERSION=${COREUTILS_VERSION}

COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=sources-downloader /sources/downloads/coreutils-${COREUTILS_VERSION}.tar.xz /sources/
RUN cd /sources && \
    tar -xf coreutils-${COREUTILS_VERSION}.tar.xz && mv coreutils-${COREUTILS_VERSION} coreutils && \
    cd coreutils && mkdir -p /coreutils && ./configure ${COMMON_CONFIGURE_ARGS} \
    --prefix=/usr \
    --bindir=/bin \
    --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --disable-nls \
    --enable-install-program=hostname,su \
    --enable-single-binary=symlinks \
    --enable-single-binary-exceptions=env,fmt,sha512sum \
    --with-openssl \
    --disable-dependency-tracking && make -s -j${JOBS} DESTDIR=/coreutils && \
    make -s -j${JOBS} DESTDIR=/coreutils install

## findutils
FROM stage1 AS findutils

ARG FINDUTILS_VERSION=4.10.0
ENV FINDUTILS_VERSION=${FINDUTILS_VERSION}

COPY --from=sources-downloader /sources/downloads/findutils-${FINDUTILS_VERSION}.tar.xz /sources/
RUN cd /sources && \
    tar -xf findutils-${FINDUTILS_VERSION}.tar.xz && mv findutils-${FINDUTILS_VERSION} findutils && \
    cd findutils && mkdir -p /findutils && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking && make -s -j${JOBS} DESTDIR=/findutils && \
    make -s -j${JOBS} DESTDIR=/findutils install && make -s -j${JOBS} install

## grep
FROM stage1 AS grep

ARG GREP_VERSION=3.12
ENV GREP_VERSION=${GREP_VERSION}

COPY --from=sources-downloader /sources/downloads/grep-${GREP_VERSION}.tar.xz /sources/
RUN cd /sources && \
    tar -xf grep-${GREP_VERSION}.tar.xz && mv grep-${GREP_VERSION} grep && \
    cd grep && mkdir -p /grep && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking && make -s -j${JOBS} DESTDIR=/grep && \
    make -s -j${JOBS} DESTDIR=/grep install && make -s -j${JOBS} install

## ca-certificates
FROM rsync AS ca-certificates

ARG CA_CERTIFICATES_VERSION=20250619
ENV CA_CERTIFICATES_VERSION=${CA_CERTIFICATES_VERSION}

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

COPY --from=sources-downloader /sources/downloads/ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2 /sources/

RUN mkdir -p /sources && cd /sources && tar -xf ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2 && mv ca-certificates-${CA_CERTIFICATES_VERSION} ca-certificates && \
    cd ca-certificates && mkdir -p /ca-certificates && CC=gcc make -s -j${JOBS} && \
    make -s -j${JOBS} DESTDIR=/ca-certificates install

COPY ./files/ca-certificates/post_install.sh /sources/post_install.sh
RUN bash /sources/post_install.sh

## sqlite3 
FROM rsync AS sqlite3

ARG SQLITE3_VERSION=3500400
ENV SQLITE3_VERSION=${SQLITE3_VERSION}

ENV CFLAGS="${CFLAGS//-Os/-O2} -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_UNLOCK_NOTIFY 	-DSQLITE_ENABLE_RTREE 	-DSQLITE_ENABLE_GEOPOLY 	-DSQLITE_USE_URI 	-DSQLITE_ENABLE_DBSTAT_VTAB 	-DSQLITE_SOUNDEX 	-DSQLITE_MAX_VARIABLE_NUMBER=250000"

COPY --from=sources-downloader /sources/downloads/sqlite-autoconf-${SQLITE3_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf sqlite-autoconf-${SQLITE3_VERSION}.tar.gz && \
    mv sqlite-autoconf-${SQLITE3_VERSION} sqlite3 && \
    cd sqlite3 && mkdir -p /sqlite3 && ./configure ${COMMON_CONFIGURE_ARGS} \
		--enable-threadsafe \
		--enable-session \
		--enable-static \
		--enable-fts3 \
		--enable-fts4 \
		--enable-fts5 \
		--soname=legacy && \
    make -s -j${JOBS} && \
    make -s -j${JOBS} DESTDIR=/sqlite3 install && make -s -j${JOBS} install

## curl
FROM rsync AS curl

COPY --from=ca-certificates /ca-certificates /ca-certificates
RUN rsync -aHAX --keep-dirlinks  /ca-certificates/. /

COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=zstd /zstd /zstd
RUN rsync -aHAX --keep-dirlinks  /zstd/. /

ARG CURL_VERSION=8.5.0
ENV CURL_VERSION=${CURL_VERSION}

COPY --from=sources-downloader /sources/downloads/curl-${CURL_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf curl-${CURL_VERSION}.tar.gz && mv curl-${CURL_VERSION} curl && \
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
    --without-libssh2 && make -s -j${JOBS} DESTDIR=/curl && \
    make -s -j${JOBS} DESTDIR=/curl install && make -s -j${JOBS} install

## openssh
## TODO: if we want a separate user for sshd we can drop a file onto /usr/lib/sysusers.d/sshd.conf
## with:
# u sshd - "sshd priv user"
## And enable --with-privsep-user=sshd during configure
FROM rsync AS openssh

ARG OPENSSH_VERSION=9.9p1
ENV OPENSSH_VERSION=${OPENSSH_VERSION}

COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /

COPY --from=sources-downloader /sources/downloads/openssh-${OPENSSH_VERSION}.tar.gz /sources/

RUN mkdir -p /openssh
WORKDIR /sources
RUN tar -xf openssh-${OPENSSH_VERSION}.tar.gz && mv openssh-${OPENSSH_VERSION} openssh

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
    --disable-strip
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} DESTDIR=/openssh install
RUN make -s -j${JOBS} install
## Provide the proper files and dirs for sshd to run properly with systemd
COPY files/systemd/sshd.service /openssh/usr/lib/systemd/system/sshd.service
COPY files/systemd/sshd.socket /openssh/usr/lib/etc/systemd/system/sshd.socket
COPY files/systemd/sshkeygen.service /openssh/usr/lib/systemd/system/sshkeygen.service
# Add sshd_config.d dir for droping extra configs
RUN mkdir -p /openssh/etc/ssh/sshd_config.d
RUN echo "# Include drop-in configs from sshd_config.d directory" >> /openssh/etc/ssh/sshd_config
RUN echo "Include sshd_config.d/*.conf" >> /openssh/etc/ssh/sshd_config

FROM rsync AS libffi

COPY --from=sources-downloader /sources/downloads/libffi.tar.gz /sources/
RUN mkdir -p /libffi
WORKDIR /sources
RUN tar -xf libffi.tar.gz && mv libffi-* libffi
WORKDIR /sources/libffi
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-docs
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/libffi

## python
FROM rsync AS python-build
ARG JOBS
ARG PYTHON_VERSION=3.12.11
ENV PYTHON_VERSION=${PYTHON_VERSION}

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

COPY --from=sources-downloader /sources/downloads/Python-${PYTHON_VERSION}.tar.xz /sources/

RUN rm /bin/sh && ln -s /bin/bash /bin/sh && mkdir -p /sources && cd /sources && tar -xf Python-${PYTHON_VERSION}.tar.xz && mv Python-${PYTHON_VERSION} python && \
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
RUN make -s -j${JOBS} DESTDIR=/python
RUN make -s -j${JOBS} DESTDIR=/python install
RUN make -s -j${JOBS} install 2>&1
## util-linux
FROM bash AS util-linux

ARG UTIL_LINUX_VERSION=2.41.1
ENV UTIL_LINUX_VERSION=${UTIL_LINUX_VERSION}

COPY --from=sources-downloader /sources/downloads/util-linux-${UTIL_LINUX_VERSION}.tar.xz /sources/

RUN rm /bin/sh && ln -s /bin/bash /bin/sh && mkdir -p /sources && cd /sources && tar -xf util-linux-${UTIL_LINUX_VERSION}.tar.xz && \
    mv util-linux-${UTIL_LINUX_VERSION} util-linux && \
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
    && make -s -j${JOBS} DESTDIR=/util-linux && \
    make -s -j${JOBS} DESTDIR=/util-linux install && make -s -j${JOBS} install


## gperf
FROM stage1 AS gperf

ARG GPERF_VERSION=3.3
ENV GPERF_VERSION=${GPERF_VERSION}

COPY --from=sources-downloader /sources/downloads/gperf-${GPERF_VERSION}.tar.gz /sources/
RUN cd /sources && \
    tar -xf gperf-${GPERF_VERSION}.tar.gz && mv gperf-${GPERF_VERSION} gperf && \
    cd gperf && mkdir -p /gperf && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr && \
    make -s -j${JOBS} BUILD_CC=gcc CC="${CC:-gcc}" lib=lib prefix=/usr GOLANG=no DESTDIR=/gperf && \
    make -s -j${JOBS} DESTDIR=/gperf install && make -s -j${JOBS} install

## libseccomp for k8s stuff mainly
FROM rsync AS libseccomp
COPY --from=gperf /gperf /gperf
RUN rsync -aHAX --keep-dirlinks  /gperf/. /
COPY --from=sources-downloader /sources/downloads/libseccomp.tar.gz /sources/
RUN mkdir -p /libseccomp
WORKDIR /sources
RUN tar -xf libseccomp.tar.gz && mv libseccomp-* libseccomp
WORKDIR /sources/libseccomp
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/libseccomp


## expat
FROM bash AS expat
## Force bash as shell otherwise it defaults to /bin/sh and fails
RUN rm /bin/sh && ln -s /bin/bash /bin/sh
COPY --from=sources-downloader /sources/downloads/expat.tar.gz /sources/
RUN mkdir -p /expat
WORKDIR /sources
RUN tar -xf expat.tar.gz && mv expat-* expat
WORKDIR /sources/expat
RUN bash ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/expat

FROM stage0 as gdb-stage0
ARG GMP_VERSION=6.3.0
ARG MPFR_VERSION=4.2.2
ARG MPC_VERSION=1.3.1

RUN mkdir -p /gdb
WORKDIR /sources
COPY --from=sources-downloader /sources/downloads/gdb.tar.gz .
COPY --from=sources-downloader /sources/downloads/gmp-${GMP_VERSION}.tar.bz2 .
COPY --from=sources-downloader /sources/downloads/mpfr-${MPFR_VERSION}.tar.bz2 .
COPY --from=sources-downloader /sources/downloads/mpc-${MPC_VERSION}.tar.gz .
COPY --from=expat /expat /
COPY --from=python-build /python /

RUN tar -xf gmp-${GMP_VERSION}.tar.bz2
RUN tar -xf mpfr-${MPFR_VERSION}.tar.bz2
RUN tar -xf gdb.tar.gz && mv gdb-* gdb
RUN tar -xf mpc-${MPC_VERSION}.tar.gz
RUN mv -v mpfr-${MPFR_VERSION} gdb/mpfr
RUN mv -v gmp-${GMP_VERSION} gdb/gmp
RUN mv -v mpc-${MPC_VERSION} gdb/mpc
WORKDIR /sources/gdb
RUN ./configure --quiet ${COMMON_CONFIGURE_ARGS} \
    --target=${TARGET} \
    --with-sysroot=/ \
    --disable-nls \
    --with-libexpat-prefix=/usr \
    --disable-multilib
RUN make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS}
RUN make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" DESTDIR=/gdb install


## dbus first pass without systemd support so we can build systemd afterwards
FROM python-build AS dbus

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
RUN DESTDIR=/dbus ninja -C buildDir install


# first pam build so we can build systemd against it
FROM python-build AS pam

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
RUN DESTDIR=/pam ninja -C buildDir install
COPY files/pam/* /pam/etc/pam.d/


## xz and liblzma
FROM rsync AS xz
COPY --from=sources-downloader /sources/downloads/xz.tar.gz /sources/
RUN mkdir -p /xz
WORKDIR /sources
RUN tar -xf xz.tar.gz && mv xz-* xz
WORKDIR /sources/xz
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-doc --enable-small --disable-scripts
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/xz && make -s -j${JOBS} install


## kmod so modprobe, insmod, lsmod, modinfo, rmmod are available
FROM python-build AS kmod
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
RUN meson setup buildDir --prefix=/usr --buildtype=minsize --optimization 3 -Dmanpages=false
RUN DESTDIR=/kmod ninja -C buildDir install && ninja -C buildDir install


## systemd
FROM rsync AS systemd-base

ARG SYSTEMD_VERSION=257.8
ENV SYSTEMD_VERSION=${SYSTEMD_VERSION}

COPY --from=gperf /gperf /gperf
RUN rsync -aHAX --keep-dirlinks  /gperf/. /

COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

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

COPY --from=sources-downloader /sources/downloads/systemd /sources/systemd
RUN mkdir -p /systemd
RUN python3 -m pip install meson ninja jinja2 pyelftools


FROM systemd-base AS systemd
WORKDIR /sources/systemd
ENV CFLAGS="$CFLAGS -D __UAPI_DEF_ETHHDR=0 -D _LARGEFILE64_SOURCE"
RUN /usr/bin/meson setup buildDir \
      --prefix=/usr           \
      --buildtype=minsize -Dstrip=true     \
      -D dbus=true  \
      -D pam=enabled \
      -D kmod=true \
      -D seccomp=true         \
      -D default-dnssec=no    \
      -D firstboot=false      \
      -D sysusers=true \
      -D install-tests=false  \
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
      -D ukify=disabled       \
      -D bootloader=disabled \
      -D docdir=/usr/share/doc/systemd-${SYSTEMD_VERSION}
RUN ninja -C buildDir
RUN DESTDIR=/systemd ninja -C buildDir install
RUN ninja -C buildDir install


FROM systemd-base AS systemd-bootloader
ARG VERSION
WORKDIR /sources/systemd
ENV CFLAGS="$CFLAGS -D __UAPI_DEF_ETHHDR=0 -D _LARGEFILE64_SOURCE -D__DEFINED_wchar_t"
RUN /usr/bin/meson setup buildDir \
    --prefix=/usr \
    --buildtype=minsize \
    -D strip=true -Dman=false \
    -D bootloader=true -Defi=true \
    -D sbat-distro="Hadron" \
    -D sbat-distro-url="hadron.kairos.io" \
    -Dsbat-distro-summary="Hadron Linux" \
    -Dsbat-distro-version="hadron-${VERSION}"
RUN /usr/bin/meson compile systemd-boot -C buildDir
## Mimic the efi install places other distros and the full systemd install does.
RUN mkdir -p /systemd/usr/lib/systemd/boot/efi/
RUN cp buildDir/src/boot/*.efi /systemd/usr/lib/systemd/boot/efi/
RUN cp buildDir/src/boot/*.efi.stub /systemd/usr/lib/systemd/boot/efi/
## flex
FROM m4 AS flex
ARG FLEX_VERSION=2.6.4
ENV FLEX_VERSION=${FLEX_VERSION}

COPY --from=sources-downloader /sources/downloads/flex-${FLEX_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf flex-${FLEX_VERSION}.tar.gz && mv flex-${FLEX_VERSION} flex && cd flex && mkdir -p /flex && ./configure ${COMMON_CONFIGURE_ARGS} --docdir=/usr/share/doc/flex-${FLEX_VERSION} --disable-dependency-tracking --infodir=/usr/share/info --mandir=/usr/share/man --prefix=/usr --disable-static --enable-shared ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes && \
    make DESTDIR=/flex install && make install && ln -s flex /flex/usr/bin/lex

## bison
FROM rsync AS bison

ARG BISON_VERSION=3.8.2
ENV BISON_VERSION=${BISON_VERSION}

COPY --from=flex /flex /flex
RUN rsync -aHAX --keep-dirlinks  /flex/. /

COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=sources-downloader /sources/downloads/bison-${BISON_VERSION}.tar.xz /sources/
RUN mkdir -p /sources && cd /sources && tar -xvf bison-${BISON_VERSION}.tar.xz && mv bison-${BISON_VERSION} bison && cd bison && mkdir -p /bison && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --infodir=/usr/share/info --mandir=/usr/share/man --prefix=/usr --disable-static --enable-shared && \
    make DESTDIR=/bison install && make install


## autoconf
FROM rsync AS autoconf

ARG AUTOCONF_VERSION=2.71
ENV AUTOCONF_VERSION=${AUTOCONF_VERSION}


COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /


COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=sources-downloader /sources/downloads/autoconf-${AUTOCONF_VERSION}.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf autoconf-${AUTOCONF_VERSION}.tar.xz && mv autoconf-${AUTOCONF_VERSION} autoconf && \
    cd autoconf && mkdir -p /autoconf && ./configure ${COMMON_CONFIGURE_ARGS} --prefix=/usr && make DESTDIR=/autoconf && \
    make DESTDIR=/autoconf install && make install


## automake
FROM rsync AS automake

ARG AUTOMAKE_VERSION=1.18.1
ENV AUTOMAKE_VERSION=${AUTOMAKE_VERSION}


COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=autoconf /autoconf /autoconf
RUN rsync -aHAX --keep-dirlinks  /autoconf/. /

COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=sources-downloader /sources/downloads/automake-${AUTOMAKE_VERSION}.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf automake-${AUTOMAKE_VERSION}.tar.xz && mv automake-${AUTOMAKE_VERSION} automake && \
    cd automake && mkdir -p /automake && ./configure ${COMMON_CONFIGURE_ARGS} --prefix=/usr && make DESTDIR=/automake && \
    make DESTDIR=/automake install && make install


## argp-standalone
FROM rsync AS argp-standalone

ARG ARGP_STANDALONE_VERSION=1.3
ENV ARGP_STANDALONE_VERSION=${ARGP_STANDALONE_VERSION}
ENV CFLAGS="-fPIC"

COPY --from=autoconf /autoconf /autoconf
RUN rsync -aHAX --keep-dirlinks  /autoconf/. /

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=automake /automake /automake
RUN rsync -aHAX --keep-dirlinks  /automake/. /

COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=sources-downloader /sources/downloads/argp-standalone-${ARGP_STANDALONE_VERSION}.tar.gz /sources/
RUN mkdir -p /sources && cd /sources && tar -xvf argp-standalone-${ARGP_STANDALONE_VERSION}.tar.gz && mv argp-standalone-${ARGP_STANDALONE_VERSION} argp-standalone && cd argp-standalone && mkdir -p /argp-standalone && autoreconf -vif && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --mandir=/usr/share/man --prefix=/usr --disable-static --enable-shared -sysconfdir=/etc --localstatedir=/var && \
    make DESTDIR=/argp-standalone install && make install && install -D -m644 argp.h /argp-standalone/usr/include/argp.h && install -D -m755 libargp.a /argp-standalone/usr/lib/libargp.a

## libtool
FROM rsync AS libtool

ARG LIBTOOL_VERSION=2.5.4
ENV LIBTOOL_VERSION=${LIBTOOL_VERSION}

COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=sources-downloader /sources/downloads/libtool-${LIBTOOL_VERSION}.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf libtool-${LIBTOOL_VERSION}.tar.xz && mv libtool-${LIBTOOL_VERSION} libtool && cd libtool && mkdir -p /libtool && sed -i \
-e "s|test-funclib-quote.sh||" \
-e "s|test-option-parser.sh||" \
gnulib-tests/Makefile.in && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --disable-static --enable-shared && \
    make DESTDIR=/libtool install && make install

## fts
FROM rsync AS fts
ARG FTS_VERSION=1.2.7
ENV FTS_VERSION=${FTS_VERSION}
ARG CFLAGS
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

COPY --from=sources-downloader /sources/downloads/musl-fts-${FTS_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf musl-fts-${FTS_VERSION}.tar.gz && mv musl-fts-${FTS_VERSION} fts && cd fts && mkdir -p /fts && ./bootstrap.sh && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --disable-static --enable-shared --localstatedir=/var --mandir=/usr/share/man  --sysconfdir=/etc  && \
    make DESTDIR=/fts install && make install &&  cp musl-fts.pc /fts/usr/lib/pkgconfig/libfts.pc

## musl-obstack
FROM rsync AS musl-obstack
ARG MUSL_OBSTACK_VERSION=1.2.3
ENV MUSL_OBSTACK_VERSION=${MUSL_OBSTACK_VERSION}

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


COPY --from=sources-downloader /sources/downloads/musl-obstack-${MUSL_OBSTACK_VERSION}.tar.gz /sources/
RUN mkdir -p /sources && cd /sources && tar -xvf musl-obstack-${MUSL_OBSTACK_VERSION}.tar.gz && mv musl-obstack-${MUSL_OBSTACK_VERSION} musl-obstack && cd musl-obstack && mkdir -p /musl-obstack && ./bootstrap.sh && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --disable-static --enable-shared && \
    make DESTDIR=/musl-obstack install && make install


## elfutils
FROM rsync AS elfutils

ARG ELFUTILS_VERSION=0.193
ENV ELFUTILS_VERSION=${ELFUTILS_VERSION}

COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /

COPY --from=argp-standalone /argp-standalone /argp-standalone
RUN rsync -aHAX --keep-dirlinks  /argp-standalone/. /

COPY --from=fts /fts /fts
RUN rsync -aHAX --keep-dirlinks  /fts/. /

COPY --from=zstd /zstd /zstd
RUN rsync -aHAX --keep-dirlinks  /zstd/. /

COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /

COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=musl-obstack /musl-obstack /musl-obstack
RUN rsync -aHAX --keep-dirlinks  /musl-obstack/. /

COPY --from=sources-downloader /sources/downloads/elfutils-${ELFUTILS_VERSION}.tar.bz2 /sources/
COPY --from=sources-downloader /sources/downloads/elfutils-patches /sources/downloads/elfutils-patches

RUN mkdir -p /sources && cd /sources && tar -xvf elfutils-${ELFUTILS_VERSION}.tar.bz2 && mv elfutils-${ELFUTILS_VERSION} elfutils && cd elfutils && mkdir -p /elfutils && patch -p1 -i /sources/downloads/elfutils-patches/musl-macros.patch && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --infodir=/usr/share/info --mandir=/usr/share/man --prefix=/usr --disable-static --enable-shared \
--sysconfdir=/etc \
--localstatedir=/var \
--disable-werror \
--program-prefix=eu- \
--enable-deterministic-archives \
--disable-nls \
--disable-libdebuginfod \
--disable-debuginfod \
--with-zstd && \
    make DESTDIR=/elfutils install && make install


FROM rsync AS diffutils
ARG DIFFUTILS_VERSION=3.9

COPY --from=sources-downloader /sources/downloads/diffutils-${DIFFUTILS_VERSION}.tar.xz /sources/
RUN cd /sources && \
    tar -xf diffutils-${DIFFUTILS_VERSION}.tar.xz && mv diffutils-${DIFFUTILS_VERSION} diffutils && \
    cd diffutils && mkdir -p /diffutils && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr && \
    make -s -j${JOBS} BUILD_CC=gcc CC="${CC:-gcc}" lib=lib prefix=/usr GOLANG=no DESTDIR=/diffutils && \
    make -s -j${JOBS} DESTDIR=/diffutils install && make -s -j${JOBS} install

## kernel
FROM rsync AS kernel
ARG JOBS
ARG TARGETARCH
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

COPY --from=elfutils /elfutils /elfutils
RUN rsync -aHAX --keep-dirlinks  /elfutils/. /

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

ARG KERNEL_VERSION=6.16.7
ENV ARCH=x86_64

COPY --from=sources-downloader /sources/downloads/linux-${KERNEL_VERSION}.tar.xz /sources/

RUN mkdir -p /sources/kernel-configs
COPY ./files/kernel/* /sources/kernel-configs/

RUN mkdir -p /kernel && mkdir -p /modules

WORKDIR /sources
RUN tar -xf linux-${KERNEL_VERSION}.tar.xz && mv linux-${KERNEL_VERSION} kernel
WORKDIR /sources/kernel
#RUN cp -rfv /sources/kernel-configs/hadron-${TARGETARCH}.config .config
RUN cp -rfv /sources/kernel-configs/tinyconfig.config .config
# This only builds the kernel
RUN KBUILD_BUILD_VERSION="$KERNEL_VERSION-${VENDOR}" make -s -j${JOBS} bzImage
RUN cp arch/$ARCH/boot/bzImage /kernel/vmlinuz

# This builds the modules
RUN KBUILD_BUILD_VERSION="$KERNEL_VERSION-${VENDOR}" make -s -j${JOBS} modules
RUN KBUILD_BUILD_VERSION="$KERNEL_VERSION-${VENDOR}" ZSTD_CLEVEL=19 INSTALL_MOD_PATH="/modules" INSTALL_MOD_STRIP=1 DEPMOD=true make modules_install

## dbus second pass pass with systemd support, so we can have a working systemd and dbus
FROM python-build AS dbus-systemd

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
RUN DESTDIR=/dbus ninja -C buildDir install

## kbd for setting the console keymap and font
FROM rsync AS kbd

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
RUN ./configure --quiet --prefix=/usr --disable-tests --disable-vlock -enable-libkeymap --enable-libkfont
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/kbd

## strace
FROM rsync AS strace

COPY --from=gawk /gawk /gawk
RUN rsync -aHAX --keep-dirlinks  /gawk/. /
COPY --from=sources-downloader /sources/downloads/strace.tar.xz /sources/
RUN mkdir -p /strace
WORKDIR /sources
RUN tar -xf strace.tar.xz && mv strace-* strace
WORKDIR /sources/strace
RUN ./configure ${COMMON_CONFIGURE_ARGS} --enable-mpers=check
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/strace

## libmnl
FROM rsync AS libmnl
COPY --from=sources-downloader /sources/downloads/libmnl.tar.bz2 /sources/
RUN mkdir -p /libmnl
WORKDIR /sources
RUN tar -xf libmnl.tar.bz2 && mv libmnl-* libmnl
WORKDIR /sources/libmnl
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/libmnl

## libnftnl
FROM rsync AS libnftnl

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
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/libnftnl

## iptables
FROM rsync AS iptables

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

RUN ./configure ${COMMON_CONFIGURE_ARGS} --with-xtlibdir=/usr/lib/xtables
RUN make -s -s && make -s -s install DESTDIR=/iptables

FROM rsync AS dracut


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
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/dracut

## libaio for lvm2
FROM rsync AS libaio

COPY --from=sources-downloader /sources/downloads/libaio.tar.gz /sources/
RUN mkdir -p /libaio
WORKDIR /sources
RUN tar -xf libaio.tar.gz && mv libaio-* libaio
WORKDIR /sources/libaio
ENV CC=gcc
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/libaio


FROM rsync AS lvm2

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
RUN ./configure --prefix=/usr
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/lvm2 && make -s -j${JOBS} install


FROM rsync AS cmake
ARG JOBS

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
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/cmake && make -s -j${JOBS} install


FROM rsync AS jsonc

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
RUN cmake ../jsonc -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_POLICY_VERSION_MINIMUM=3.5
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/jsonc && make -s -j${JOBS} install

# pax-utils provives scanelf which lddconfig needs
FROM python-build AS pax-utils

COPY --from=sources-downloader /sources/downloads/pax-utils.tar.xz /sources/
RUN mkdir -p /pax-utils
WORKDIR /sources
RUN tar -xf pax-utils.tar.xz && mv pax-utils-* pax-utils
WORKDIR /sources/pax-utils
RUN pip3 install meson ninja
RUN meson setup buildDir --prefix=/usr --buildtype=minsize -Dstrip=true -Dtests=false
RUN DESTDIR=/pax-utils ninja -C buildDir install
RUN ninja -C buildDir install

FROM rsync AS urcu

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
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-static --enable-shared --sysconfdir=/etc --mandir=/usr/share/man --infodir=/usr/share/info --localstatedir=/var
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/urcu && make -s -j${JOBS} install

## needed for dracut and other tools
FROM rsync AS multipath-tools

COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
# devmapper
COPY --from=lvm2 /lvm2 /lvm2
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
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /sources/patches/
WORKDIR /sources/patches
RUN tar -xf aports.tar.gz && mv aports-* aport
# extract the aport patch to apply to multipath-tools
RUN mkdir -p /multipath-tools
WORKDIR /sources
RUN tar -xf multipath-tools.tar.gz && mv multipath-tools-* multipath-tools
WORKDIR /sources/multipath-tools
# patch it
RUN patch -p1 < /sources/patches/aport/main/multipath-tools/0001-Disable-O2.patch
RUN patch -p1 < /sources/patches/aport/main/multipath-tools/fix-basename.patch
RUN patch -p1 < /sources/patches/aport/main/multipath-tools/fix-implicit-function-declaration-error.patch
ENV CC="gcc"
# Set lib to /lib so it works in initramfs as well
RUN make -s -j${JOBS} WARN_ONLY=1 sysconfdir="/etc" configdir="/etc/multipath/conf.d" LIB=/lib
RUN make -s -j${JOBS} WARN_ONLY=1 SYSTEMDPATH=/lib LIB=/lib install DESTDIR=/multipath-tools
RUN make -s -j${JOBS} WARN_ONLY=1 LIB=/lib install
RUN rm -Rf /multipath/usr/share/man

FROM rsync AS parted

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
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/parted && make -s -j${JOBS} install


## e2fsprogs for mkfs.ext4, e2fsck, tune2fs, etc
FROM rsync AS e2fsprogs

COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /

COPY --from=sources-downloader /sources/downloads/e2fsprogs.tar.xz /sources/
RUN mkdir -p /e2fsprogs
WORKDIR /sources
RUN tar -xf e2fsprogs.tar.xz && mv e2fsprogs-* e2fsprogs
WORKDIR /sources/e2fsprogs
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-uuidd --disable-libuuid --disable-libblkid --disable-nls --enable-elf-shlibs  --disable-fsck --enable-symlink-install
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/e2fsprogs && make -s -j${JOBS} install


## Provides mkfs.fat and fsck.fat
FROM rsync AS dosfstools

COPY --from=sources-downloader /sources/downloads/dosfstools.tar.gz /sources/
RUN mkdir -p /dosfstools
WORKDIR /sources
RUN tar -xf dosfstools.tar.gz && mv dosfstools-* dosfstools
WORKDIR /sources/dosfstools
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/dosfstools && make -s -j${JOBS} install


FROM rsync AS gptfdisk
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
## We need libstdc++ and libgcc to build gptfdisk
COPY --from=gcc-stage0 /sysroot /gcc-stage0
RUN rsync -aHAX --keep-dirlinks  /gcc-stage0/. /

COPY --from=sources-downloader /sources/downloads/gptfdisk.tar.gz /sources/
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /sources/patches/

RUN mkdir -p /gptfdisk

WORKDIR /sources/patches
RUN tar -xf aports.tar.gz && mv aports-* aport
WORKDIR /sources
RUN tar -xf gptfdisk.tar.gz && mv gptfdisk-* gptfdisk
WORKDIR /sources/gptfdisk
RUN patch -p1 < /sources/patches/aport/main/gptfdisk/fix-musl.patch
RUN patch -p1 < /sources/patches/aport/main/gptfdisk/fix-wrong-include.patch
## TODO: we need to get rid of these LDFLAGS, makes the binary around 9MB
RUN make -s -j${JOBS} sgdisk
RUN install -Dm0755 -t /gptfdisk/usr/bin sgdisk
RUN install -Dm0755 -t /usr/bin sgdisk


## TODO: build cryptsetup before systemd so we can enable systemd-cryptsetup
FROM rsync AS cryptsetup
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /
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

COPY --from=sources-downloader /sources/downloads/cryptsetup.tar.xz /sources/
RUN mkdir -p /cryptsetup
WORKDIR /sources
RUN tar -xf cryptsetup.tar.xz && mv cryptsetup-* cryptsetup
WORKDIR /sources/cryptsetup
RUN ./configure ${COMMON_CONFIGURE_ARGS} --with-crypto-backend=openssl --disable-asciidoc  --disable-nls --disable-ssh-token
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/cryptsetup && make -s -j${JOBS} install


## growpart from cloud-utils
# its just a simple pyton script
FROM stage0 AS growpart
RUN mkdir -p /growpart/usr/bin
COPY --from=sources-downloader /sources/downloads/cloud-utils.tar.gz /sources/
WORKDIR /sources
RUN tar -xf cloud-utils.tar.gz && mv cloud-utils-* cloud-utils
RUN stat /sources/cloud-utils/bin
RUN cp /sources/cloud-utils/bin/growpart /growpart/usr/bin/growpart

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
RUN echo depends bli part_gpt > grub-core/extra_deps.lst

FROM grub-base AS grub-efi
WORKDIR /sources/grub
RUN mkdir -p /grub-efi
RUN ./configure ${COMMON_CONFIGURE_ARGS} --with-platform=efi --disable-efiemu --disable-werror
RUN make -s -j${JOBS} && make -s -j${JOBS} install-strip DESTDIR=/grub-efi

FROM grub-base AS grub-bios
WORKDIR /sources/grub
RUN mkdir -p /grub-bios
RUN ./configure ${COMMON_CONFIGURE_ARGS} --with-platform=pc --disable-werror
RUN make -s -j${JOBS} && make -s -j${JOBS} install-strip DESTDIR=/grub-bios


## final build of pam with systemd support
FROM python-build AS pam-systemd

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
RUN DESTDIR=/pam ninja -C buildDir install
COPY files/pam/* /pam/etc/pam.d/
## We are using the pam_shells.so module in a few places, so we need a proper /etc/shells file
COPY files/shells /pam/etc/shells
RUN chmod 644 /pam/etc/shells

# install shadow now that we have pam to get a proper login binary
FROM rsync AS shadow-base
COPY --from=pkgconfig /pkgconfig /pkgconfig
RUN rsync -aHAX --keep-dirlinks  /pkgconfig/. /
COPY --from=readline /readline /readline
RUN rsync -aHAX --keep-dirlinks  /readline/. /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /


# Shadow with systemd support via PAM
FROM shadow-base AS shadow-systemd
COPY --from=pam-systemd /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /
COPY --from=sources-downloader /sources/downloads/shadow.tar.xz /sources/
RUN mkdir -p /shadow
WORKDIR /sources
RUN tar -xf shadow.tar.xz && mv shadow-* shadow
WORKDIR /sources/shadow
RUN ./configure ${COMMON_CONFIGURE_ARGS} --sysconfdir=/etc --without-libbsd
RUN make -s -j${JOBS} && make -s -j${JOBS} exec_prefix=/usr pamddir= install DESTDIR=/shadow && make exec_prefix=/usr pamddir= -s -j${JOBS} install

# Shadow with PAM support, no systemd
FROM shadow-base AS shadow
COPY --from=pam /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /
COPY --from=sources-downloader /sources/downloads/shadow.tar.xz /sources/
RUN mkdir -p /shadow
WORKDIR /sources
RUN tar -xf shadow.tar.xz && mv shadow-* shadow
WORKDIR /sources/shadow
RUN ./configure ${COMMON_CONFIGURE_ARGS} --sysconfdir=/etc --without-libbsd
RUN make -s -j${JOBS} && make -s -j${JOBS} exec_prefix=/usr pamddir= install DESTDIR=/shadow && make exec_prefix=/usr pamddir= -s -j${JOBS} install


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
COPY --from=pam-systemd /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /
COPY --from=sources-downloader /sources/downloads/sudo.tar.gz /sources/
RUN mkdir -p /sudo
WORKDIR /sources
RUN tar -xf sudo.tar.gz && mv sudo-* sudo
WORKDIR /sources/sudo
RUN ./configure ${COMMON_CONFIGURE_ARGS} --libexecdir=/usr/lib --with-pam --with-secure-path --with-env-editor --with-passprompt="[sudo] password for %p: "
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/sudo && make -s -j${JOBS} install

FROM sudo-base AS sudo
COPY --from=pam /pam /pam
RUN rsync -aHAX --keep-dirlinks  /pam/. /
COPY --from=sources-downloader /sources/downloads/sudo.tar.gz /sources/
RUN mkdir -p /sudo
WORKDIR /sources
RUN tar -xf sudo.tar.gz && mv sudo-* sudo
WORKDIR /sources/sudo
RUN ./configure ${COMMON_CONFIGURE_ARGS} --libexecdir=/usr/lib --with-pam --with-secure-path --with-env-editor --with-passprompt="[sudo] password for %p: "
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/sudo && make -s -j${JOBS} install

FROM python-build AS openscsi

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
RUN DESTDIR=/openscsi ninja -C buildDir install && ninja -C buildDir install


########################################################
#
# Stage 2 - Building the final image
#
########################################################
# stage-merge will merge all the built packages into a single directory
FROM stage0 AS stage2-merge

RUN apk add rsync

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

## OpenSSL
COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /skeleton/


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

## popt for rsync
COPY --from=popt /popt /popt
RUN rsync -aHAX --keep-dirlinks  /popt/. /skeleton

COPY --from=lz4 /lz4 /lz4
RUN rsync -aHAX --keep-dirlinks  /lz4/. /skeleton

## xxhash needed by rsync
COPY --from=xxhash /xxhash /xxhash
RUN rsync -aHAX --keep-dirlinks  /xxhash/. /skeleton

## kbd for loadkeys support
COPY --from=kbd /kbd /kbd
RUN rsync -aHAX --keep-dirlinks  /kbd/. /skeleton

# This provides readelf needed by ldconfig
COPY --from=pax-utils /pax-utils /pax-utils
RUN rsync -aHAX --keep-dirlinks  /pax-utils/. /skeleton

## Copy ldconfig from alpine musl
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /
RUN tar xf /aports.tar.gz && mv aports-* aports
RUN cp /aports/main/musl/ldconfig /skeleton/usr/bin/ldconfig

# make sure they are both executable
RUN chmod 755 /skeleton/sbin/ldconfig

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

# Container base image, it has the minimal required to run as a container
FROM scratch AS container
COPY --from=stage2-merge /skeleton /
RUN rm /bin/sh && ln -s /bin/bash /bin/sh
## Symlink ld-musl-$ARCH.so to /bin/ldd to provide ldd functionality
RUN ln -s /lib/ld-musl-x86_64.so.1 /bin/ldd
CMD ["/bin/bash", "-l"]

# Target that tests to see if the binaries work or we are missing some libs
FROM container AS container-test
RUN bash --version
RUN ldconfig bash
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
RUN ldd /bin/bash

# stage2-merge is where we prepare stuff for the final image
# more complete, this has systemd, sudo, openssh, iptables, kernel, etc..
FROM alpine:${ALPINE_VERSION} AS full-image-merge
RUN apk add rsync
## openssh
COPY --from=openssh /openssh /openssh
RUN rsync -aHAX --keep-dirlinks  /openssh/. /skeleton/

# kernel and modules
COPY --from=kernel /kernel/vmlinuz /skeleton/boot/vmlinuz
COPY --from=kernel /modules/lib/modules/ /skeleton/lib/modules

COPY --from=sudo-systemd /sudo /sudo
RUN rsync -aHAX --keep-dirlinks  /sudo/. /skeleton

# Iptables is needed to support k8s
COPY --from=iptables /iptables /iptables
RUN rsync -aHAX --keep-dirlinks  /iptables/. /skeleton

## cryptsetup for encrypted partitions
## TODO: do we need to build systemd after cryptsetup to have the systemd-cryptsetup unit?
COPY --from=cryptsetup /cryptsetup /cryptsetup
RUN rsync -aHAX --keep-dirlinks  /cryptsetup/. /skeleton

## jsonc needed by libcryptsetup
COPY --from=jsonc /jsonc /jsonc
RUN rsync -aHAX --keep-dirlinks  /jsonc/. /skeleton

## growpart
COPY --from=growpart /growpart /growpart
RUN rsync -aHAX --keep-dirlinks  /growpart/. /skeleton

# device-mapper from lvm2
COPY --from=lvm2 /lvm2 /lvm2
RUN rsync -aHAX --keep-dirlinks  /lvm2/. /skeleton/

COPY --from=multipath-tools /multipath-tools /multipath-tools
RUN rsync -aHAX --keep-dirlinks  /multipath-tools/. /skeleton/
## Use mount and cp to preserv symlinks, otherwise if we copy directly
## we will resolve the symlinks and copy the real files multiple times
## Copy libgcc_s.so.1 for multipathd deps and gptfdisk
RUN --mount=from=gcc-stage0,src=/sysroot/usr/lib,dst=/mnt,ro \
    mkdir -p /skeleton/usr/lib && \
    cp -a /mnt/libgcc_s.so* /skeleton/usr/lib/ && \
    cp -a /mnt/libstdc++.so* /skeleton/usr/lib/

## liburcu needed by multipath-tools
COPY --from=urcu /urcu /urcu
RUN rsync -aHAX --keep-dirlinks  /urcu/. /skeleton

COPY --from=parted /parted /parted
RUN rsync -aHAX --keep-dirlinks  /parted/. /skeleton/

COPY --from=e2fsprogs /e2fsprogs /e2fsprogs
RUN rsync -aHAX --keep-dirlinks  /e2fsprogs/. /skeleton/

COPY --from=dosfstools /dosfstools /dosfstools
RUN rsync -aHAX --keep-dirlinks  /dosfstools/. /skeleton/

## popt for gptfdisk and probably parted
COPY --from=popt /popt /popt
RUN rsync -aHAX --keep-dirlinks  /popt/. /skeleton/

COPY --from=gptfdisk /gptfdisk /gptfdisk
RUN rsync -aHAX --keep-dirlinks  /gptfdisk/. /skeleton/

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

## This target will assemble dracut and all its dependencies into the skeleton
FROM stage0 AS dracut-final
RUN apk add rsync
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

## Dracut
COPY --from=dracut /dracut /dracut
RUN rsync -aHAX --keep-dirlinks  /dracut/. /skeleton

### Assemble the image depending on our bootloader
## either grub or systemd-boot for trusted boot
## To not merge things and have extra software where we dont want it we prepare a base image with all the
## needed software and then we merge it with the bootloader specific stuff

## This workarounds over the COPY not being able to run over the same dir
## We merge the base container + stage2-merge (kernel, sudo, systemd, etc) + dracut into a single dir
FROM alpine:${ALPINE_VERSION} AS full-image-pre-grub
RUN apk add rsync
COPY --from=container / /skeleton
COPY --from=full-image-merge /skeleton /stage2-merge
RUN rsync -aHAX --keep-dirlinks  /stage2-merge/. /skeleton/
COPY --from=dracut-final /skeleton /dracut-final
RUN rsync -aHAX --keep-dirlinks  /dracut-final/. /skeleton/

## We merge the base container + stage2-merge (kernel, sudo, systemd, etc) into a single dir
FROM alpine:${ALPINE_VERSION} AS full-image-pre-systemd
RUN apk add rsync
COPY --from=container / /skeleton
COPY --from=full-image-merge /skeleton /stage2-merge
RUN rsync -aHAX --keep-dirlinks  /stage2-merge/. /skeleton/
COPY --from=systemd-bootloader /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /skeleton/
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
# Remove static libs
RUN find / -name '*.a' -delete
# Remove packageconfig files
RUN rm -Rf /usr/share/pkgconfig
## Small configs
# set a default locale
RUN echo "export LANG=C.UTF-8" >> /etc/profile.d/locale.sh
RUN echo "export LANG=C.UTF-8" >> /etc/bash.bashrc
RUN chmod 644 /etc/profile.d/locale.sh
RUN chmod 644 /etc/bash.bashrc
RUN echo "VERSION_ID=\"${VERSION}\"" >> /etc/os-release
RUN busybox --install
RUN systemctl preset-all
# Add sysctl configs
# TODO: kernel tuning based on the environment? Hardening? better defaults?
COPY files/sysctl/* /etc/sysctl.d/
# copy a new login.defs to have better defaults as some stuff is already done by shadow and pam
COPY files/login.defs /etc/login.defs
## Remove users stuff
RUN rm -f /etc/passwd /etc/shadow /etc/group /etc/gshadow
## Create any missing users from scratch
RUN systemd-sysusers

### final image
FROM full-image-final AS default
CMD ["/bin/bash", "-l"]

## final image with debug
FROM full-image-final AS debug

COPY --from=strace /strace /
COPY --from=gdb-stage0 /gdb /
CMD ["/bin/bash", "-l"]
