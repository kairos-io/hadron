## This is Dockerfile, that at the end of the process it builds a 
## small LFS system, starting from Alpine Linux.
## It uses mussel to build the system.
ARG BOOTLOADER=grub
ARG KERNEL_TYPE=default
ARG VERSION=0.0.1
## SBAT distro-version string baked into the systemd-boot/stub EFI .sbat metadata.
## Intentionally STABLE and decoupled from the per-commit build VERSION so the
## (expensive) systemd compile stage stays cache-valid across commits. The SBAT
## *generation* (the revocation counter that actually gates boot) is a separate
## field that defaults to 1; bump SBAT_DISTRO_VERSION manually only on a
## security-relevant SBAT revocation.
ARG SBAT_DISTRO_VERSION=1
ARG JOBS=16
## Maximum load for make -l
ARG MAX_LOAD=32
ARG FIPS="no-fips"
ARG TARGETARCH
ARG CFLAGS
ARG ARCH
## GNU mirror fallback list - tried in order for all GNU FTP package downloads.
## Override any of these if a mirror is consistently unavailable in your region.
ARG GNU_MIRROR_1=https://ftpmirror.gnu.org
ARG GNU_MIRROR_2=https://ftp.gnu.org/gnu
ARG GNU_MIRROR_3=https://mirror.netcologne.de/gnu

# Base image with build tools
# Use sha. Otherwise the tag can get updated and break reproducibility and force rebuilds for apparent no reason
FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS alpine-base
RUN apk update && \
    apk add --no-cache git bash wget bash perl build-base make patch busybox-static \
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
ARG MUSSEL_VERSION="687d2f5e4d679487209cd9b4bd75091a20cae357"
ENV MUSSEL_VERSION=${MUSSEL_VERSION}

# Validate that the arches are correct
RUN if [ "${ARCH}" = "x86-64" ] && [ "${BUILD_ARCH}" != "x86_64" ]; then echo "For ARCH x86-64, BUILD_ARCH must be x86_64"; exit 1; fi
RUN if [ "${ARCH}" = "aarch64" ] && [ "${BUILD_ARCH}" != "aarch64" ]; then echo "For ARCH aarch64, BUILD_ARCH must be aarch64"; exit 1; fi
RUN if [ "${ARCH}" = "riscv64" ] && [ "${BUILD_ARCH}" != "riscv64" ]; then echo "For ARCH riscv64, BUILD_ARCH must be riscv64"; exit 1; fi

RUN git clone https://github.com/firasuke/mussel.git && cd mussel && git checkout ${MUSSEL_VERSION} -b build
RUN cd mussel && ./mussel ${ARCH} -k -l -o -p -s -T ${VENDOR}

ENV PATH=/mussel/toolchain/bin/:$PATH
ENV LC_ALL=POSIX
ENV TARGET=${BUILD_ARCH}-${VENDOR}-linux-musl
ENV BUILD=${BUILD_ARCH}-pc-linux-musl


# Base dowload target with some preparation common to all downloads.
FROM alpine-base AS sources-downloader-base
## Re-declare global GNU mirror ARGs and export as ENV so all child download
## stages inherit them without needing to redeclare ARG in each stage.
ARG GNU_MIRROR_1
ARG GNU_MIRROR_2
ARG GNU_MIRROR_3
ENV GNU_MIRROR_1=${GNU_MIRROR_1} \
    GNU_MIRROR_2=${GNU_MIRROR_2} \
    GNU_MIRROR_3=${GNU_MIRROR_3}
RUN mkdir -p /sources/downloads
WORKDIR /sources/downloads

### This stages below are used to download the sources for the packages
FROM sources-downloader-base AS curl-download
ARG CURL_VERSION=8.21.0
RUN wget -q https://curl.se/download/curl-${CURL_VERSION}.tar.gz -O curl.tar.gz

FROM sources-downloader-base AS rsync-download
ARG RSYNC_VERSION=3.4.4
RUN wget -q https://github.com/RsyncProject/rsync/releases/download/v${RSYNC_VERSION}/rsync-${RSYNC_VERSION}.tar.gz -O rsync.tar.gz

FROM sources-downloader-base AS xxhash-download
ARG XXHASH_VERSION=0.8.3
RUN wget -q https://github.com/Cyan4973/xxHash/archive/refs/tags/v${XXHASH_VERSION}.tar.gz -O xxhash.tar.gz

FROM sources-downloader-base AS zstd-download
ARG ZSTD_VERSION=1.5.7
RUN wget -q https://github.com/facebook/zstd/archive/v${ZSTD_VERSION}.tar.gz -O zstd.tar.gz

FROM sources-downloader-base AS lz4-download
ARG LZ4_VERSION=1.10.0
RUN wget -q https://github.com/lz4/lz4/archive/v${LZ4_VERSION}.tar.gz -O lz4.tar.gz

FROM sources-downloader-base AS zlib-download
ARG ZLIB_VERSION=1.3.2
RUN wget -q https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz -O zlib.tar.gz

FROM sources-downloader-base AS acl-download
ARG ACL_VERSION=2.4.0
RUN wget -q https://download.savannah.gnu.org/releases/acl/acl-${ACL_VERSION}.tar.gz -O acl.tar.gz

FROM sources-downloader-base AS attr-download
ARG ATTR_VERSION=2.6.0
RUN wget -q https://download.savannah.nongnu.org/releases/attr/attr-${ATTR_VERSION}.tar.gz -O attr.tar.gz

FROM sources-downloader-base AS gawk-download
ARG GAWK_VERSION=5.4.1
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/gawk/gawk-${GAWK_VERSION}.tar.xz" -O gawk.tar.xz && break; \
        rm -f gawk.tar.xz; \
    done; \
    test -s gawk.tar.xz

FROM sources-downloader-base AS ca-certificates-download
ARG CA_CERTIFICATES_VERSION=20260611
RUN wget -q https://gitlab.alpinelinux.org/alpine/ca-certificates/-/archive/${CA_CERTIFICATES_VERSION}/ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2 -O ca-certificates.tar.bz2

FROM sources-downloader-base AS systemd-download
ARG SYSTEMD_VERSION=261.1
RUN wget -q https://github.com/systemd/systemd/archive/refs/tags/v${SYSTEMD_VERSION}.tar.gz -O systemd.tar.gz

FROM sources-downloader-base AS libcap-download
ARG LIBCAP_VERSION=2.78
RUN wget -q https://kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-${LIBCAP_VERSION}.tar.xz -O libcap.tar.xz

FROM sources-downloader-base AS util-linux-download
ARG UTIL_LINUX_VERSION=2.42.2
RUN UTIL_LINUX_VERSION_MAJOR="${UTIL_LINUX_VERSION%%.*}" \
    && UTIL_LINUX_VERSION_MINOR="${UTIL_LINUX_VERSION#*.}"; UTIL_LINUX_VERSION_MINOR="${UTIL_LINUX_VERSION_MINOR%.*}" \
    && wget -q https://www.kernel.org/pub/linux/utils/util-linux/v${UTIL_LINUX_VERSION_MAJOR}.${UTIL_LINUX_VERSION_MINOR}/util-linux-${UTIL_LINUX_VERSION}.tar.xz -O util-linux.tar.xz

FROM sources-downloader-base AS python-download
ARG PYTHON_VERSION=3.14.6
RUN wget -q https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz -O Python.tar.xz

FROM sources-downloader-base AS sqlite3-download
ARG SQLITE3_VERSION=3.53.3
RUN wget -q https://github.com/sqlite/sqlite/archive/refs/tags/version-${SQLITE3_VERSION}.tar.gz -O sqlite3.tar.gz

FROM sources-downloader-base AS openssl-download
ARG OPENSSL_VERSION=3.6.3
RUN wget -q https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -O openssl.tar.gz

FROM sources-downloader-base AS openssl-fips-download
ARG OPENSSL_FIPS_VERSION=3.1.2
RUN wget -q https://www.openssl.org/source/openssl-${OPENSSL_FIPS_VERSION}.tar.gz -O openssl-fips.tar.gz

FROM sources-downloader-base AS openssh-download
ARG OPENSSH_VERSION=10.3p1
RUN wget -q https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz -O openssh.tar.gz

FROM sources-downloader-base AS pkgconf-download
ARG PKGCONFIG_VERSION=3.0.0
RUN wget -q https://distfiles.dereferenced.org/pkgconf/pkgconf-${PKGCONFIG_VERSION}.tar.xz -O pkgconf.tar.xz

FROM sources-downloader-base AS dbus-download
ARG DBUS_VERSION=1.16.2
RUN wget -q https://dbus.freedesktop.org/releases/dbus/dbus-${DBUS_VERSION}.tar.xz && mv dbus-${DBUS_VERSION}.tar.xz dbus.tar.xz

FROM sources-downloader-base AS expat-download
# libexpat
ARG EXPAT_VERSION=2.8.2
# Use a single var and extract major/minor/patch to build the URL
RUN EXPAT_VERSION_MAJOR="${EXPAT_VERSION%%.*}" \
 && EXPAT_VERSION_MINOR="${EXPAT_VERSION#*.}"; EXPAT_VERSION_MINOR="${EXPAT_VERSION_MINOR%.*}" \
 && EXPAT_VERSION_PATCH="${EXPAT_VERSION##*.}" \
 && wget -q \
 "https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION_MAJOR}_${EXPAT_VERSION_MINOR}_${EXPAT_VERSION_PATCH}/expat-${EXPAT_VERSION}.tar.gz" \
 -O expat.tar.gz

FROM sources-downloader-base AS libseccomp-download
ARG SECCOMP_VERSION=2.6.1
RUN wget -q https://github.com/seccomp/libseccomp/releases/download/v${SECCOMP_VERSION}/libseccomp-${SECCOMP_VERSION}.tar.gz -O libseccomp.tar.gz

FROM sources-downloader-base AS strace-download
ARG STRACE_VERSION=7.1
RUN wget -q https://strace.io/files/${STRACE_VERSION}/strace-${STRACE_VERSION}.tar.xz -O strace.tar.xz

FROM sources-downloader-base AS kbd-download
ARG KBD_VERSION=2.10.0
RUN wget -q https://www.kernel.org/pub/linux/utils/kbd/kbd-${KBD_VERSION}.tar.gz -O kbd.tar.gz

FROM sources-downloader-base AS iptables-download
ARG IPTABLES_VERSION=1.8.13
RUN wget -q https://www.netfilter.org/projects/iptables/files/iptables-${IPTABLES_VERSION}.tar.xz -O iptables.tar.xz

FROM sources-downloader-base AS libmnl-download
ARG LIBMNL_VERSION=1.0.5
RUN wget -q https://www.netfilter.org/projects/libmnl/files/libmnl-${LIBMNL_VERSION}.tar.bz2 -O libmnl.tar.bz2

FROM sources-downloader-base AS libnftnl-download
ARG LIBNFTNL_VERSION=1.3.1
RUN wget -q https://www.netfilter.org/projects/libnftnl/files/libnftnl-${LIBNFTNL_VERSION}.tar.xz -O libnftnl.tar.xz

FROM sources-downloader-base AS libnfnetlink-download
ARG LIBNFNETLINK_VERSION=1.0.2
RUN wget -q https://www.netfilter.org/projects/libnfnetlink/files/libnfnetlink-${LIBNFNETLINK_VERSION}.tar.bz2 -O libnfnetlink.tar.bz2

FROM sources-downloader-base AS libnetfilter_conntrack-download
ARG LIBNETFILTER_CONNTRACK_VERSION=1.1.1
RUN wget -q https://www.netfilter.org/projects/libnetfilter_conntrack/files/libnetfilter_conntrack-${LIBNETFILTER_CONNTRACK_VERSION}.tar.xz -O libnetfilter_conntrack.tar.xz

FROM sources-downloader-base AS libnetfilter_cttimeout-download
ARG LIBNETFILTER_CTTIMEOUT_VERSION=1.0.1
RUN wget -q https://www.netfilter.org/projects/libnetfilter_cttimeout/files/libnetfilter_cttimeout-${LIBNETFILTER_CTTIMEOUT_VERSION}.tar.bz2 -O libnetfilter_cttimeout.tar.bz2

FROM sources-downloader-base AS libnetfilter_cthelper-download
ARG LIBNETFILTER_CTHELPER_VERSION=1.0.1
RUN wget -q https://www.netfilter.org/projects/libnetfilter_cthelper/files/libnetfilter_cthelper-${LIBNETFILTER_CTHELPER_VERSION}.tar.bz2 -O libnetfilter_cthelper.tar.bz2

FROM sources-downloader-base AS libnetfilter_queue-download
ARG LIBNETFILTER_QUEUE_VERSION=1.0.5
RUN wget -q https://www.netfilter.org/projects/libnetfilter_queue/files/libnetfilter_queue-${LIBNETFILTER_QUEUE_VERSION}.tar.bz2 -O libnetfilter_queue.tar.bz2

FROM sources-downloader-base AS conntrack-tools-download
ARG CONNTRACK_TOOLS_VERSION=1.4.9
RUN wget -q https://www.netfilter.org/projects/conntrack-tools/files/conntrack-tools-${CONNTRACK_TOOLS_VERSION}.tar.xz -O conntrack-tools.tar.xz

FROM sources-downloader-base AS procps-ng-download
ARG PROCPS_NG_VERSION=4.0.6
RUN wget -q https://downloads.sourceforge.net/project/procps-ng/Production/procps-ng-${PROCPS_NG_VERSION}.tar.xz -O procps-ng.tar.xz

FROM sources-downloader-base AS linux-download
ARG KERNEL_VERSION=7.1.3
RUN wget -q https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/snapshot/linux-${KERNEL_VERSION}.tar.gz -O linux.tar.gz

FROM sources-downloader-base AS flex-download
ARG FLEX_VERSION=2.6.4
RUN wget -q https://github.com/westes/flex/releases/download/v${FLEX_VERSION}/flex-${FLEX_VERSION}.tar.gz -O flex.tar.gz

FROM sources-downloader-base AS bison-download
ARG BISON_VERSION=3.8.2
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/bison/bison-${BISON_VERSION}.tar.xz" -O bison.tar.xz && break; \
        rm -f bison.tar.xz; \
    done; \
    test -s bison.tar.xz

FROM sources-downloader-base AS autoconf-download
ARG AUTOCONF_VERSION=2.73
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/autoconf/autoconf-${AUTOCONF_VERSION}.tar.xz" -O autoconf.tar.xz && break; \
        rm -f autoconf.tar.xz; \
    done; \
    test -s autoconf.tar.xz

FROM sources-downloader-base AS automake-download
ARG AUTOMAKE_VERSION=1.18.1
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/automake/automake-${AUTOMAKE_VERSION}.tar.xz" -O automake.tar.xz && break; \
        rm -f automake.tar.xz; \
    done; \
    test -s automake.tar.xz

FROM sources-downloader-base AS musl-fts-download
ARG FTS_VERSION=1.2.7
RUN wget -q https://github.com/pullmoll/musl-fts/archive/v${FTS_VERSION}.tar.gz -O musl-fts.tar.gz

FROM sources-downloader-base AS libtool-download
ARG LIBTOOL_VERSION=2.5.4
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/libtool/libtool-${LIBTOOL_VERSION}.tar.xz" -O libtool.tar.xz && break; \
        rm -f libtool.tar.xz; \
    done; \
    test -s libtool.tar.xz

FROM sources-downloader-base AS libelf-download
ARG LIBELF_VERSION=0.195
RUN wget -q https://github.com/arachsys/libelf/archive/refs/tags/v${LIBELF_VERSION}.tar.gz -O libelf.tar.gz

FROM sources-downloader-base AS xz-download
ARG XZUTILS_VERSION=5.8.3
RUN wget -q https://tukaani.org/xz/xz-${XZUTILS_VERSION}.tar.gz -O xz.tar.gz

FROM sources-downloader-base AS kmod-download
ARG KMOD_VERSION=34.2
RUN wget -q https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-${KMOD_VERSION}.tar.gz -O kmod.tar.gz

FROM sources-downloader-base AS dracut-download
ARG DRACUT_VERSION=111
RUN wget -q https://github.com/dracut-ng/dracut-ng/archive/refs/tags/${DRACUT_VERSION}.tar.gz -O dracut.tar.gz

FROM sources-downloader-base AS libaio-download
ARG LIBAIO_VERSION=0.3.113
RUN wget -q https://releases.pagure.org/libaio/libaio-${LIBAIO_VERSION}.tar.gz -O libaio.tar.gz

FROM sources-downloader-base AS lvm2-download
ARG LVM2_VERSION=2.03.41
RUN wget -q http://ftp-stud.fht-esslingen.de/pub/Mirrors/sourceware.org/lvm2/releases/LVM2.${LVM2_VERSION}.tgz -O lvm2.tgz

FROM sources-downloader-base AS multipath-tools-download
ARG MULTIPATH_TOOLS_VERSION=0.14.3
RUN wget -q https://github.com/opensvc/multipath-tools/archive/refs/tags/${MULTIPATH_TOOLS_VERSION}.tar.gz -O multipath-tools.tar.gz

FROM sources-downloader-base AS json-c-download
ARG JSONC_VERSION=0.19
RUN wget -q https://s3.amazonaws.com/json-c_releases/releases/json-c-${JSONC_VERSION}.tar.gz -O json-c.tar.gz

FROM sources-downloader-base AS cmake-download
ARG CMAKE_VERSION=4.4.0
RUN wget -q https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}.tar.gz -O cmake.tar.gz

FROM sources-downloader-base AS dwarves-download
ARG DWARVES_VERSION=1.28
RUN wget -q https://github.com/acmel/dwarves/archive/refs/tags/v${DWARVES_VERSION}.tar.gz -O dwarves.tar.xz

FROM sources-downloader-base AS argp-standalone-download
ARG ARGP_STANDALONE_VERSION=1.4.1
RUN wget -q https://github.com/argp-standalone/argp-standalone/archive/refs/tags/${ARGP_STANDALONE_VERSION}.tar.gz -O argp-standalone.tar.gz

FROM sources-downloader-base AS musl-obstack-download
ARG MUSL_OBSTACK_VERSION=1.2.3
RUN wget -q https://github.com/void-linux/musl-obstack/archive/refs/tags/v${MUSL_OBSTACK_VERSION}.tar.gz -O musl-obstack.tar.gz

FROM sources-downloader-base AS elfutils-download
ARG ELFUTILS_VERSION=0.192
RUN wget -q https://sourceware.org/elfutils/ftp/${ELFUTILS_VERSION}/elfutils-${ELFUTILS_VERSION}.tar.bz2 -O elfutils.tar.bz2

FROM sources-downloader-base AS urcu-download
ARG URCU_VERSION=0.15.6
RUN wget -q https://lttng.org/files/urcu/userspace-rcu-${URCU_VERSION}.tar.bz2 -O urcu.tar.bz2

FROM sources-downloader-base AS parted-download
ARG PARTED_VERSION=3.7
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/parted/parted-${PARTED_VERSION}.tar.xz" -O parted.tar.xz && break; \
        rm -f parted.tar.xz; \
    done; \
    test -s parted.tar.xz

FROM sources-downloader-base AS e2fsprogs-download
ARG E2FSPROGS_VERSION=1.47.4
RUN wget -q https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v${E2FSPROGS_VERSION}/e2fsprogs-${E2FSPROGS_VERSION}.tar.xz -O e2fsprogs.tar.xz

FROM sources-downloader-base AS dosfstools-download
ARG DOSFSTOOLS_VERSION=4.2
RUN wget -q https://github.com/dosfstools/dosfstools/releases/download/v${DOSFSTOOLS_VERSION}/dosfstools-${DOSFSTOOLS_VERSION}.tar.gz -O dosfstools.tar.gz

FROM sources-downloader-base AS libtirpc-download
ARG LIBTIRPC_VERSION=1.3.7
RUN wget -q https://downloads.sourceforge.net/project/libtirpc/libtirpc/${LIBTIRPC_VERSION}/libtirpc-${LIBTIRPC_VERSION}.tar.bz2 -O libtirpc.tar.bz2

FROM sources-downloader-base AS libnl-download
ARG LIBNL_VERSION=3.12.0
# Upstream release-tag convention is libnl3_X_Y_Z (dots → underscores).
RUN LIBNL_TAG="libnl${LIBNL_VERSION//./_}" \
 && wget -q https://github.com/thom311/libnl/releases/download/${LIBNL_TAG}/libnl-${LIBNL_VERSION}.tar.gz -O libnl.tar.gz

FROM sources-downloader-base AS libevent-download
ARG LIBEVENT_VERSION=2.1.13
# Upstream release-tag convention is release-X.Y.Z-stable, and the tarball
# is named libevent-X.Y.Z-stable.tar.gz.
RUN wget -q https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}-stable/libevent-${LIBEVENT_VERSION}-stable.tar.gz -O libevent.tar.gz

FROM sources-downloader-base AS keyutils-download
ARG KEYUTILS_VERSION=1.6.3
RUN wget -q https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-${KEYUTILS_VERSION}.tar.gz -O keyutils.tar.gz

FROM sources-downloader-base AS nfs-utils-download
ARG NFS_UTILS_VERSION=2.9.1
RUN wget -q https://www.kernel.org/pub/linux/utils/nfs-utils/${NFS_UTILS_VERSION}/nfs-utils-${NFS_UTILS_VERSION}.tar.xz -O nfs-utils.tar.xz

FROM sources-downloader-base AS cryptsetup-download
ARG CRYPTSETUP_VERSION=2.8.6
RUN wget -q https://cdn.kernel.org/pub/linux/utils/cryptsetup/v${CRYPTSETUP_VERSION%.*}/cryptsetup-${CRYPTSETUP_VERSION}.tar.xz -O cryptsetup.tar.xz

FROM sources-downloader-base AS grub-download
ARG GRUB_VERSION=2.14
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/grub/grub-${GRUB_VERSION}.tar.xz" -O grub.tar.xz && break; \
        rm -f grub.tar.xz; \
    done; \
    test -s grub.tar.xz

FROM sources-downloader-base AS pam-download
ARG PAM_VERSION=1.7.2
RUN wget -q https://github.com/linux-pam/linux-pam/releases/download/v${PAM_VERSION}/Linux-PAM-${PAM_VERSION}.tar.xz -O pam.tar.xz

FROM sources-downloader-base AS shadow-download
ARG SHADOW_VERSION=4.19.4
RUN wget -q https://github.com/shadow-maint/shadow/releases/download/${SHADOW_VERSION}/shadow-${SHADOW_VERSION}.tar.xz -O shadow.tar.xz

FROM sources-downloader-base AS aports-download
ARG APORTS_VERSION=3.24.1
RUN wget -q https://gitlab.alpinelinux.org/alpine/aports/-/archive/v${APORTS_VERSION}/aports-v${APORTS_VERSION}.tar.gz -O aports.tar.gz

FROM sources-downloader-base AS busybox-download
ARG BUSYBOX_VERSION=1.37.0
# XXX: Temporary workaround as busybox currently have expired certificates
RUN wget -q --no-check-certificate https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 -O busybox.tar.bz2

FROM sources-downloader-base AS musl-download
ARG MUSL_VERSION=1.2.6
RUN wget -q http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz -O musl.tar.gz

FROM sources-downloader-base AS gcc-download
ARG GCC_VERSION=15.3.0
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz" -O gcc.tar.xz && break; \
        rm -f gcc.tar.xz; \
    done; \
    test -s gcc.tar.xz

FROM sources-downloader-base AS gmp-download
ARG GMP_VERSION=6.3.0
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/gmp/gmp-${GMP_VERSION}.tar.bz2" -O gmp.tar.bz2 && break; \
        rm -f gmp.tar.bz2; \
    done; \
    test -s gmp.tar.bz2

FROM sources-downloader-base AS mpc-download
ARG MPC_VERSION=1.4.1
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/mpc/mpc-${MPC_VERSION}.tar.xz" -O mpc.tar.xz && break; \
        rm -f mpc.tar.xz; \
    done; \
    test -s mpc.tar.xz

FROM sources-downloader-base AS mpfr-download
ARG MPFR_VERSION=4.2.2
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/mpfr/mpfr-${MPFR_VERSION}.tar.bz2" -O mpfr.tar.bz2 && break; \
        rm -f mpfr.tar.bz2; \
    done; \
    test -s mpfr.tar.bz2

FROM sources-downloader-base AS make-download
ARG MAKE_VERSION=4.4.1
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/make/make-${MAKE_VERSION}.tar.gz" -O make.tar.gz && break; \
        rm -f make.tar.gz; \
    done; \
    test -s make.tar.gz

FROM sources-downloader-base AS binutils-download
ARG BINUTILS_VERSION=2.46.1
RUN wget -q https://sourceware.org/pub/binutils/releases/binutils-${BINUTILS_VERSION}.tar.xz -O binutils.tar.xz

FROM sources-downloader-base AS popt-download
ARG POPT_VERSION=1.19
RUN wget -q http://ftp.rpm.org/popt/releases/popt-1.x/popt-${POPT_VERSION}.tar.gz -O popt.tar.gz

FROM sources-downloader-base AS m4-download
ARG M4_VERSION=1.4.21
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/m4/m4-${M4_VERSION}.tar.xz" -O m4.tar.xz && break; \
        rm -f m4.tar.xz; \
    done; \
    test -s m4.tar.xz

FROM sources-downloader-base AS readline-download
ARG READLINE_VERSION=8.3
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/readline/readline-${READLINE_VERSION}.tar.gz" -O readline.tar.gz && break; \
        rm -f readline.tar.gz; \
    done; \
    test -s readline.tar.gz

FROM sources-downloader-base AS perl-download
ARG PERL_VERSION=5.42.2
RUN wget -q https://github.com/Perl/perl5/archive/refs/tags/v${PERL_VERSION}.tar.gz -O perl.tar.gz

FROM sources-downloader-base AS coreutils-download
ARG COREUTILS_VERSION=9.11
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/coreutils/coreutils-${COREUTILS_VERSION}.tar.xz" -O coreutils.tar.xz && break; \
        rm -f coreutils.tar.xz; \
    done; \
    test -s coreutils.tar.xz

FROM sources-downloader-base AS findutils-download
ARG FINDUTILS_VERSION=4.10.0
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/findutils/findutils-${FINDUTILS_VERSION}.tar.xz" -O findutils.tar.xz && break; \
        rm -f findutils.tar.xz; \
    done; \
    test -s findutils.tar.xz

FROM sources-downloader-base AS grep-download
ARG GREP_VERSION=3.12
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/grep/grep-${GREP_VERSION}.tar.xz" -O grep.tar.xz && break; \
        rm -f grep.tar.xz; \
    done; \
    test -s grep.tar.xz

FROM sources-downloader-base AS gperf-download
ARG GPERF_VERSION=3.3
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/gperf/gperf-${GPERF_VERSION}.tar.gz" -O gperf.tar.gz && break; \
        rm -f gperf.tar.gz; \
    done; \
    test -s gperf.tar.gz

FROM sources-downloader-base AS diffutils-download
ARG DIFFUTILS_VERSION=3.12
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/diffutils/diffutils-${DIFFUTILS_VERSION}.tar.xz" -O diffutils.tar.xz && break; \
        rm -f diffutils.tar.xz; \
    done; \
    test -s diffutils.tar.xz

FROM sources-downloader-base AS sudo-download
ARG SUDO_VERSION=1.9.17p2
RUN wget -q https://www.sudo.ws/dist/sudo-${SUDO_VERSION}.tar.gz -O sudo.tar.gz

FROM sources-downloader-base AS pax-utils-download
ARG PAX_UTILS_VERSION=1.3.10
RUN wget -q https://github.com/gentoo/pax-utils/archive/refs/tags/v${PAX_UTILS_VERSION}.tar.gz -O pax-utils.tar.gz

FROM sources-downloader-base AS openscsi-download
ARG OPEN_SCSI_VERSION=2.1.11
RUN wget -q https://github.com/open-iscsi/open-iscsi/archive/refs/tags/${OPEN_SCSI_VERSION}.tar.gz -O openscsi.tar.gz

FROM sources-downloader-base AS gdb-download
ARG GDB_VERSION=17.2
RUN wget -q https://sourceware.org/pub/gdb/releases/gdb-${GDB_VERSION}.tar.gz -O gdb.tar.gz

FROM sources-downloader-base AS libffi-download
ARG LIBFFI_VERSION=3.7.1
RUN wget -q https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz -O libffi.tar.gz

FROM sources-downloader-base AS tpm2-tss-download
ARG TPM2_TSS_VERSION=4.1.3
RUN wget -q https://github.com/tpm2-software/tpm2-tss/releases/download/${TPM2_TSS_VERSION}/tpm2-tss-${TPM2_TSS_VERSION}.tar.gz -O tpm2-tss.tar.gz

FROM sources-downloader-base AS libucontext-download
ARG LIBUCONTEXT_VERSION=1.5.1
RUN wget -q https://github.com/kaniini/libucontext/archive/refs/tags/libucontext-${LIBUCONTEXT_VERSION}.tar.gz -O libucontext.tar.gz

FROM sources-downloader-base AS libxml2-download
ARG LIBXML2_VERSION=2.15.3
RUN major="${LIBXML2_VERSION%%.*}" \
 && minor="${LIBXML2_VERSION#*.}"; minor="${minor%%.*}" \
 && LIBXML2_VERSION_MAJOR_AND_MINOR="${major}.${minor}" \
 && wget -q https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION_MAJOR_AND_MINOR}/libxml2-${LIBXML2_VERSION}.tar.xz -O libxml2.tar.xz

FROM sources-downloader-base AS gzip-download
ARG GZIP_VERSION=1.14
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/gzip/gzip-${GZIP_VERSION}.tar.xz" -O gzip.tar.xz && break; \
        rm -f gzip.tar.xz; \
    done; \
    test -s gzip.tar.xz

FROM sources-downloader-base AS bash-download
ARG BASH_VERSION=5.3
# Patch level is the number of patches upstream bash has released for this version https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}-patches/
# It is bumped separately from BASH_VERSION by updatecli.d/core-system.yaml
ARG PATCH_LEVEL=15
# Get the patches from https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}-patches/
# They are in the format bash$BASH_VERSION_NO_DOT-NNN where NNN is a 3-digit zero-padded index
# starting at 001.
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q -T 30 -t 1 "${mirror}/bash/bash-${BASH_VERSION}.tar.gz" -O bash-${BASH_VERSION}.tar.gz && break; \
        rm -f bash-${BASH_VERSION}.tar.gz; \
    done; \
    test -s bash-${BASH_VERSION}.tar.gz; \
    tar -xf bash-${BASH_VERSION}.tar.gz && mv bash-${BASH_VERSION} bash
WORKDIR /sources/downloads/bash
RUN for i in $(seq 1 ${PATCH_LEVEL}); do \
        patch_num=$(printf '%03d' ${i}); \
        echo "Applying bash patch bash${BASH_VERSION//./}-${patch_num}"; \
        for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
            wget -q -T 30 -t 1 "${mirror}/bash/bash-${BASH_VERSION}-patches/bash${BASH_VERSION//./}-${patch_num}" -O bash-patch-${patch_num}.patch && break; \
            rm -f bash-patch-${patch_num}.patch; \
        done; \
        test -s bash-patch-${patch_num}.patch || { echo "Failed to download bash patch ${patch_num} from all mirrors"; exit 1; }; \
        patch -p0 < bash-patch-${patch_num}.patch; \
    done
WORKDIR /sources/downloads

FROM sources-downloader-base AS libkcapi-download
ARG LIBKCAPI_VERSION=1.5.0
RUN wget -q https://github.com/smuellerDD/libkcapi/archive/refs/tags/v${LIBKCAPI_VERSION}.tar.gz -O libkcapi.tar.gz

FROM sources-downloader-base AS shim-download
ARG SHIM_VERSION=16.1
RUN wget -q https://github.com/rhboot/shim/releases/download/${SHIM_VERSION}/shim-${SHIM_VERSION}.tar.bz2 -O shim.tar.bz2

FROM sources-downloader-base AS libiconv-download
ARG ICONV_VERSION=1.19
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/libiconv/libiconv-${ICONV_VERSION}.tar.gz" -O libiconv.tar.gz && break; \
        rm -f libiconv.tar.gz; \
    done; \
    test -s libiconv.tar.gz

FROM sources-downloader-base AS bc-download
ARG BC_VERSION=7.1.0
RUN wget -q https://github.com/gavinhoward/bc/releases/download/${BC_VERSION}/bc-${BC_VERSION}.tar.xz -O bc.tar.xz

FROM sources-downloader-base AS patch-download
ARG PATCH_VERSION=2.8
RUN for mirror in ${GNU_MIRROR_1} ${GNU_MIRROR_2} ${GNU_MIRROR_3}; do \
        wget -q "${mirror}/patch/patch-${PATCH_VERSION}.tar.gz" -O patch.tar.gz && break; \
        rm -f patch.tar.gz; \
    done; \
    test -s patch.tar.gz


FROM sources-downloader-base AS pcre2-download
ARG PCRE2_VERSION=10.47
RUN wget -q https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz -O pcre2.tar.gz

FROM sources-downloader-base AS glib-download
ARG GLIB_VERSION=2.86.2
RUN GLIB_MAJOR="${GLIB_VERSION%.*}" && wget -q https://download.gnome.org/sources/glib/${GLIB_MAJOR}/glib-${GLIB_VERSION}.tar.xz -O glib.tar.xz

FROM sources-downloader-base AS qemu-download
ARG QEMU_AGENT_VERSION="10.1.5"
RUN wget https://download.qemu.org/qemu-${QEMU_AGENT_VERSION}.tar.xz -O qemu.tar.xz


FROM sources-downloader-base AS mspack-download
ARG MSPACK_VERSION=1.11
RUN wget -q https://github.com/kyz/libmspack/archive/refs/tags/v${MSPACK_VERSION}.tar.gz -O mspack.tar.gz

FROM sources-downloader-base AS open-vm-tools-download
ARG OPENVM_TOOLS_VERSION=13.1.0
RUN wget -q https://github.com/vmware/open-vm-tools/archive/stable-${OPENVM_TOOLS_VERSION}.tar.gz -O open-vm-tools.tar.gz

# Merge all the downloads into a single target
# This avoids a single change in version invalidating the full download cache,
# while still allowing the downloads to run in parallel and be cached separately
FROM scratch AS sources-downloader
COPY --from=curl-download /sources/downloads/curl.tar.gz /sources/downloads/
COPY --from=rsync-download /sources/downloads/rsync.tar.gz /sources/downloads/
COPY --from=xxhash-download /sources/downloads/xxhash.tar.gz /sources/downloads/
COPY --from=zstd-download /sources/downloads/zstd.tar.gz /sources/downloads/
COPY --from=lz4-download /sources/downloads/lz4.tar.gz /sources/downloads/
COPY --from=zlib-download /sources/downloads/zlib.tar.gz /sources/downloads/
COPY --from=acl-download /sources/downloads/acl.tar.gz /sources/downloads/
COPY --from=attr-download /sources/downloads/attr.tar.gz /sources/downloads/
COPY --from=gawk-download /sources/downloads/gawk.tar.xz /sources/downloads/
COPY --from=ca-certificates-download /sources/downloads/ca-certificates.tar.bz2 /sources/downloads/
COPY --from=systemd-download /sources/downloads/systemd.tar.gz /sources/downloads/
COPY --from=libcap-download /sources/downloads/libcap.tar.xz /sources/downloads/
COPY --from=util-linux-download /sources/downloads/util-linux.tar.xz /sources/downloads/
COPY --from=python-download /sources/downloads/Python.tar.xz /sources/downloads/
COPY --from=sqlite3-download /sources/downloads/sqlite3.tar.gz /sources/downloads/
COPY --from=openssl-download /sources/downloads/openssl.tar.gz /sources/downloads/
COPY --from=openssl-fips-download /sources/downloads/openssl-fips.tar.gz /sources/downloads/
COPY --from=openssh-download /sources/downloads/openssh.tar.gz /sources/downloads/
COPY --from=pkgconf-download /sources/downloads/pkgconf.tar.xz /sources/downloads/
COPY --from=dbus-download /sources/downloads/dbus.tar.xz /sources/downloads/
COPY --from=expat-download /sources/downloads/expat.tar.gz /sources/downloads/
COPY --from=libseccomp-download /sources/downloads/libseccomp.tar.gz /sources/downloads/
COPY --from=strace-download /sources/downloads/strace.tar.xz /sources/downloads/
COPY --from=kbd-download /sources/downloads/kbd.tar.gz /sources/downloads/
COPY --from=iptables-download /sources/downloads/iptables.tar.xz /sources/downloads/
COPY --from=libmnl-download /sources/downloads/libmnl.tar.bz2 /sources/downloads/
COPY --from=libnftnl-download /sources/downloads/libnftnl.tar.xz /sources/downloads/
COPY --from=linux-download /sources/downloads/linux.tar.gz /sources/downloads/
COPY --from=flex-download /sources/downloads/flex.tar.gz /sources/downloads/
COPY --from=bison-download /sources/downloads/bison.tar.xz /sources/downloads/
COPY --from=autoconf-download /sources/downloads/autoconf.tar.xz /sources/downloads/
COPY --from=automake-download /sources/downloads/automake.tar.xz /sources/downloads/
COPY --from=musl-fts-download /sources/downloads/musl-fts.tar.gz /sources/downloads/
COPY --from=libtool-download /sources/downloads/libtool.tar.xz /sources/downloads/
COPY --from=libelf-download /sources/downloads/libelf.tar.gz /sources/downloads/
COPY --from=xz-download /sources/downloads/xz.tar.gz /sources/downloads/
COPY --from=kmod-download /sources/downloads/kmod.tar.gz /sources/downloads/
COPY --from=dracut-download /sources/downloads/dracut.tar.gz /sources/downloads/
COPY --from=libaio-download /sources/downloads/libaio.tar.gz /sources/downloads/
COPY --from=lvm2-download /sources/downloads/lvm2.tgz /sources/downloads/
COPY --from=multipath-tools-download /sources/downloads/multipath-tools.tar.gz /sources/downloads/
COPY --from=json-c-download /sources/downloads/json-c.tar.gz /sources/downloads/
COPY --from=cmake-download /sources/downloads/cmake.tar.gz /sources/downloads/
COPY --from=urcu-download /sources/downloads/urcu.tar.bz2 /sources/downloads/
COPY --from=parted-download /sources/downloads/parted.tar.xz /sources/downloads/
COPY --from=e2fsprogs-download /sources/downloads/e2fsprogs.tar.xz /sources/downloads/
COPY --from=dosfstools-download /sources/downloads/dosfstools.tar.gz /sources/downloads/
COPY --from=libtirpc-download /sources/downloads/libtirpc.tar.bz2 /sources/downloads/
COPY --from=libnl-download /sources/downloads/libnl.tar.gz /sources/downloads/
COPY --from=libevent-download /sources/downloads/libevent.tar.gz /sources/downloads/
COPY --from=keyutils-download /sources/downloads/keyutils.tar.gz /sources/downloads/
COPY --from=nfs-utils-download /sources/downloads/nfs-utils.tar.xz /sources/downloads/
COPY --from=cryptsetup-download /sources/downloads/cryptsetup.tar.xz /sources/downloads/
COPY --from=grub-download /sources/downloads/grub.tar.xz /sources/downloads/
COPY --from=pam-download /sources/downloads/pam.tar.xz /sources/downloads/
COPY --from=shadow-download /sources/downloads/shadow.tar.xz /sources/downloads/
COPY --from=aports-download /sources/downloads/aports.tar.gz /sources/downloads/
COPY --from=busybox-download /sources/downloads/busybox.tar.bz2 /sources/downloads/
COPY --from=musl-download /sources/downloads/musl.tar.gz /sources/downloads/
COPY --from=gcc-download /sources/downloads/gcc.tar.xz /sources/downloads/
COPY --from=gmp-download /sources/downloads/gmp.tar.bz2 /sources/downloads/
COPY --from=mpc-download /sources/downloads/mpc.tar.xz /sources/downloads/
COPY --from=mpfr-download /sources/downloads/mpfr.tar.bz2 /sources/downloads/
COPY --from=make-download /sources/downloads/make.tar.gz /sources/downloads/
COPY --from=binutils-download /sources/downloads/binutils.tar.xz /sources/downloads/
COPY --from=popt-download /sources/downloads/popt.tar.gz /sources/downloads/
COPY --from=m4-download /sources/downloads/m4.tar.xz /sources/downloads/
COPY --from=readline-download /sources/downloads/readline.tar.gz /sources/downloads/
COPY --from=perl-download /sources/downloads/perl.tar.gz /sources/downloads/
COPY --from=coreutils-download /sources/downloads/coreutils.tar.xz /sources/downloads/
COPY --from=findutils-download /sources/downloads/findutils.tar.xz /sources/downloads/
COPY --from=grep-download /sources/downloads/grep.tar.xz /sources/downloads/
COPY --from=gperf-download /sources/downloads/gperf.tar.gz /sources/downloads/
COPY --from=diffutils-download /sources/downloads/diffutils.tar.xz /sources/downloads/
COPY --from=sudo-download /sources/downloads/sudo.tar.gz /sources/downloads/
COPY --from=pax-utils-download /sources/downloads/pax-utils.tar.gz /sources/downloads/
COPY --from=openscsi-download /sources/downloads/openscsi.tar.gz /sources/downloads/
COPY --from=gdb-download /sources/downloads/gdb.tar.gz /sources/downloads/
COPY --from=libffi-download /sources/downloads/libffi.tar.gz /sources/downloads/
COPY --from=tpm2-tss-download /sources/downloads/tpm2-tss.tar.gz /sources/downloads/
COPY --from=libucontext-download /sources/downloads/libucontext.tar.gz /sources/downloads/
COPY --from=libxml2-download /sources/downloads/libxml2.tar.xz /sources/downloads/
COPY --from=gzip-download /sources/downloads/gzip.tar.xz /sources/downloads/
COPY --from=bash-download /sources/downloads/bash /sources/downloads/bash
COPY --from=libkcapi-download /sources/downloads/libkcapi.tar.gz /sources/downloads/
COPY --from=shim-download /sources/downloads/shim.tar.bz2 /sources/downloads/
COPY --from=libiconv-download /sources/downloads/libiconv.tar.gz /sources/downloads/
COPY --from=bc-download /sources/downloads/bc.tar.xz /sources/downloads/
COPY --from=patch-download /sources/downloads/patch.tar.gz /sources/downloads/
COPY --from=pcre2-download /sources/downloads/pcre2.tar.gz /sources/downloads/
COPY --from=glib-download /sources/downloads/glib.tar.xz /sources/downloads/
COPY --from=qemu-download /sources/downloads/qemu.tar.xz /sources/downloads/
COPY --from=mspack-download /sources/downloads/mspack.tar.gz /sources/downloads/
COPY --from=open-vm-tools-download /sources/downloads/open-vm-tools.tar.gz /sources/downloads
COPY --from=libnfnetlink-download /sources/downloads/libnfnetlink.tar.bz2 /sources/downloads/
COPY --from=libnetfilter_conntrack-download /sources/downloads/libnetfilter_conntrack.tar.xz /sources/downloads/
COPY --from=libnetfilter_cttimeout-download /sources/downloads/libnetfilter_cttimeout.tar.bz2 /sources/downloads/
COPY --from=libnetfilter_cthelper-download /sources/downloads/libnetfilter_cthelper.tar.bz2 /sources/downloads/
COPY --from=libnetfilter_queue-download /sources/downloads/libnetfilter_queue.tar.bz2 /sources/downloads/
COPY --from=conntrack-tools-download /sources/downloads/conntrack-tools.tar.xz /sources/downloads/
COPY --from=procps-ng-download /sources/downloads/procps-ng.tar.xz /sources/downloads/
COPY --from=dwarves-download /sources/downloads/dwarves.tar.xz /sources/downloads/
COPY --from=argp-standalone-download /sources/downloads/argp-standalone.tar.gz /sources/downloads/
COPY --from=musl-obstack-download /sources/downloads/musl-obstack.tar.gz /sources/downloads/
COPY --from=elfutils-download /sources/downloads/elfutils.tar.bz2 /sources/downloads/

########################################################
#
# Stage 0 - building the packages using the cross-compiler
#
########################################################

# Creates the system skeleton
# dirs, minimum files, symlinks, etc.
FROM stage0 AS skeleton
ARG VERSION
SHELL ["/bin/bash", "-c"]
RUN mkdir -p /sysroot
WORKDIR /sysroot
RUN mkdir -pv {boot,home,mnt,opt,srv,tmp} \
        {etc,var} \
        etc/{opt,sysconfig} \
        usr/{bin,sbin,lib} \
        usr/lib/firmware \
        usr/{,local/}{include,src} \
        usr/local/{bin,lib} \
        usr/{,local/}share/{color,dict,doc,info,locale,man} \
        usr/{,local/}share/{misc,terminfo,zoneinfo} \
        usr/{,local/}share/man/man{1..8} \
        var/{cache,local,log,mail,opt,spool} \
        var/lib/{color,misc,locate} \
        {dev,proc,sys,run}

RUN install -dv -m 0750 root
RUN install -dv -m 1777 var/tmp
RUN touch etc/hostname

RUN ln -sfv usr/sbin sbin # sbin -> usr/sbin
RUN ln -sfv usr/bin bin   # bin -> usr/bin
RUN ln -sfv usr/lib lib   # lib -> usr/lib
RUN ln -sfv usr/lib lib64 # lib64 -> usr/lib
RUN ln -sfv ../run var/run # var/run -> ../run important to be relative
RUN ln -sfv ../run/lock var/lock # var/lock -> run/lock
RUN ln -svf proc/mounts etc/mtab

RUN touch etc/shadow
RUN touch var/log/{btmp,lastlog,faillog,wtmp}
RUN chgrp -v utmp var/log/lastlog
RUN chmod -v 664 var/log/lastlog
RUN chmod -v 600 var/log/btmp

# TODO: Drop systemd users? not needed in container/toolchain images and final images already run sysusers to create basic users
COPY <<'EOF' etc/passwd
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
dbus:x:81:81:System Message Bus:/:/usr/sbin/nologin
systemd-coredump:x:980:980:systemd Core Dumper:/:/usr/sbin/nologin
systemd-network:x:979:979:systemd Network Management:/:/usr/sbin/nologin
systemd-oom:x:978:978:systemd Userspace OOM Killer:/:/usr/sbin/nologin
systemd-journal-remote:x:977:977:systemd Journal Remote:/:/usr/sbin/nologin
systemd-resolve:x:976:976:systemd Resolver:/:/usr/sbin/nologin
systemd-timesync:x:975:975:systemd Time Synchronization:/:/usr/sbin/nologin
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

COPY <<'EOF' etc/group
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF


COPY <<'EOF' etc/profile
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin/:/usr/local/sbin/

if [ `id -u` -eq 0 ] ; then
        unset HISTFILE
fi

# Set up some environment variables.
export USER=`id -un`
export LOGNAME=$USER
export HOSTNAME=`/bin/hostname`
export HISTSIZE=1000
export HISTFILESIZE=1000
export PAGER='/bin/more '
export EDITOR='/bin/vi'
# load other profiles under /etc/profile.d
if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh; do
    if [ -r $i ]; then
      . $i
    fi
  done
  unset i
fi
EOF

COPY <<'EOF' etc/issue
Hadron Linux (\d)
Kernel \r on an \m
EOF

COPY <<'EOF' etc/os-release
NAME="Hadron Linux"
PRETTY_NAME="Hadron Linux"
ID=hadron
BUILD_ID=rolling
EOF

COPY <<'EOF' etc/hosts
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
EOF

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
    if [ "${ARCH}" != "x86-64" ]; then sed -i 's/\(CONFIG_SHA1_HWACCEL\)=y/# \1 is not set/' .config; fi && \
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
COPY --from=sources-downloader /sources/downloads/mpc.tar.xz .
COPY --from=sources-downloader /sources/downloads/mpfr.tar.bz2 .
RUN tar -xf gcc.tar.xz && mv gcc-* gcc
RUN tar -xf gmp.tar.bz2 && mv -v gmp-* gcc/gmp
RUN tar -xf mpc.tar.xz && mv -v mpc-* gcc/mpc
RUN tar -xf mpfr.tar.bz2 && mv -v mpfr-* gcc/mpfr
COPY patches/0001-gcc-atomic-template-body-gcc15.patch /gcc/
RUN cd /gcc && patch -p1 < 0001-gcc-atomic-template-body-gcc15.patch
RUN mkdir -p /sysroot/usr/include
WORKDIR /gcc/build
RUN ../configure --quiet \
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
        --disable-libsanitizer
RUN make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS} -l${MAX_LOAD}
RUN make -s ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS} -l${MAX_LOAD} DESTDIR=/sysroot install

###
### Make
###
FROM stage0 AS make-stage0
ARG JOBS
COPY --from=sources-downloader /sources/downloads/make.tar.gz /sources/

RUN cd /sources && tar -xf make.tar.gz && mv make-* make
WORKDIR /sources/make
COPY patches/0001-make-getopt-gcc15.patch .
RUN patch -p1 < 0001-make-getopt-gcc15.patch
RUN ./configure --quiet --prefix=/usr --build=${BUILD} --host=${TARGET} --disable-nls
RUN make -s -j${JOBS} -l${MAX_LOAD}
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/sysroot install

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

COPY --from=sources-downloader /sources/downloads/linux.tar.gz /sources/

WORKDIR /sources
RUN tar -xf linux.tar.gz && mv linux-* kernel
WORKDIR /sources/kernel
# This installs the headers
RUN if [ ${ARCH} = "aarch64" ]; then \
    export ARCH=arm64; \
    elif [ ${ARCH} = "riscv64" ]; then \
    export ARCH=riscv; \
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
RUN cp aports/main/musl/ldconfig /skeleton/usr/bin/ldconfig && chmod +x /skeleton/usr/bin/ldconfig
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
ENV COMMON_CONFIGURE_ARGS="--quiet --prefix=/usr --host=${TARGET} --build=${TARGET} --enable-lto --enable-shared --disable-static"
ENV COMMON_MESON_FLAGS="--prefix=/usr --libdir=lib --buildtype=minsize -Dstrip=true"
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

RUN mkdir -p /attr

WORKDIR /sources
RUN tar -xf attr.tar.gz && mv attr-* attr
WORKDIR /sources/attr
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
# TARGET-prefixed symlinks so CROSS_COMPILE=${TARGET}- works out of the box on
# native arm64/x86_64 builds (kbuild probes ${CROSS_COMPILE}ld etc.; without
# these, cross-compile workflows fail even though the native tools can handle
# the same arch).
RUN for d in /binutils/usr/bin /usr/bin; do \
      cd "$d" && for t in addr2line ar as c++filt elfedit gprof ld ld.bfd nm \
                          objcopy objdump ranlib readelf size strings strip; do \
        [ -e "$t" ] && [ ! -e "${TARGET}-$t" ] && ln -sf "$t" "${TARGET}-$t"; \
      done; \
    done

## m4 (from stage1, ready to be used in the final image)
FROM stage1 AS m4
ARG JOBS
COPY --from=sources-downloader /sources/downloads/m4.tar.xz /sources/
RUN cd /sources && \
    tar -xf m4.tar.xz && mv m4-* m4 && \
    cd m4 && mkdir -p /m4 && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/m4 && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/m4 install && make -s -j${JOBS} -l${MAX_LOAD} install

## readline
FROM stage1 AS readline
ARG JOBS
COPY --from=sources-downloader /sources/downloads/readline.tar.gz /sources/
RUN cd /sources && \
    tar -xf readline.tar.gz && mv readline-* readline && \
    cd readline && mkdir -p /readline && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking && make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/readline && \
    make -s -j${JOBS} DESTDIR=/readline install && make -s -j${JOBS} install
## flex
FROM stage1 AS flex
ARG JOBS
COPY --from=sources-downloader /sources/downloads/flex.tar.gz /sources/
COPY --from=m4 /m4 /
RUN mkdir -p /flex
RUN mkdir -p /sources && cd /sources && tar -xf flex.tar.gz && mv flex-* flex
WORKDIR /sources/flex
RUN ./configure --quiet --prefix=/usr --build=${BUILD} --enable-shared --disable-static --infodir=/usr/share/info --mandir=/usr/share/man
RUN make -j${JOBS} -l${MAX_LOAD}
RUN make -j${JOBS} -l${MAX_LOAD} DESTDIR=/flex install

## perl
FROM m4 AS perl
ARG JOBS
ENV CFLAGS="${CFLAGS} -static -ffunction-sections -fdata-sections -Bsymbolic-functions"
ENV LDFLAGS="-Wl,--gc-sections"
ENV PERL_CROSS=1.6.2
COPY --from=sources-downloader /sources/downloads/perl.tar.gz /sources/
RUN cd /sources && \
    tar -xf perl.tar.gz && mv perl5-* perl && \
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
COPY --from=flex /flex/ /

COPY --from=m4 /m4/ /

COPY --from=perl /perl/ /

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
COPY --from=perl /perl/ /

COPY --from=zlib /zlib/ /

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
COPY --from=perl /perl/ /

COPY --from=zlib /zlib/ /

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
COPY --from=openssl /openssl/ /

COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=perl /perl/ /

COPY --from=sources-downloader /sources/downloads/coreutils.tar.xz /sources/
RUN cd /sources && \
    tar -xf coreutils.tar.xz && mv coreutils-* coreutils && \
    cd coreutils && mkdir -p /coreutils && FORCE_UNSAFE_CONFIGURE=1 ./configure ${COMMON_CONFIGURE_ARGS} \
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
COPY --from=openssl /openssl/ /

COPY --from=perl /perl/ /

COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /

## readline
COPY --from=readline /readline/ /

## acl
COPY --from=acl /acl/ /

## attr
COPY --from=attr /attr/ /

## findutils
COPY --from=findutils /findutils/ /

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
COPY --from=ca-certificates /ca-certificates/ /

COPY --from=openssl /openssl/ /

COPY --from=zstd /zstd/ /

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
COPY --from=openssl /openssl/ /

COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /

COPY --from=zlib /zlib/ /

COPY --from=readline /readline/ /

COPY --from=pkgconfig /pkgconfig/ /

COPY --from=libffi /libffi/ /

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
WORKDIR /sources
COPY --from=sources-downloader /sources/downloads/util-linux.tar.xz /sources/
RUN tar -xf util-linux.tar.xz && mv util-linux-* util-linux
WORKDIR /sources/util-linux
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking  --prefix=/usr \
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
    --with-sysusersdir=/usr/lib/sysusers.d/
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/util-linux
RUN make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/util-linux install


## gperf
FROM stage1 AS gperf
ARG JOBS
COPY --from=sources-downloader /sources/downloads/gperf.tar.gz /sources/
RUN cd /sources && \
    tar -xf gperf.tar.gz && mv gperf-* gperf && \
    cd gperf && mkdir -p /gperf && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr && \
    make -s -j${JOBS} -l${MAX_LOAD} BUILD_CC=gcc CC="${CC:-gcc}" lib=lib prefix=/usr GOLANG=no DESTDIR=/gperf && \
    make -s -j${JOBS} -l${MAX_LOAD} DESTDIR=/gperf install && make -s -j${JOBS} -l${MAX_LOAD} install

FROM stage1 AS hadron-splash
WORKDIR /sources/hadron
COPY files/hadron-splash/main.c .
COPY files/hadron-splash/Makefile .
RUN make hadron-splash
RUN mkdir -p /hadron-splash && mv hadron-splash /hadron-splash

## libseccomp for k8s stuff mainly
FROM rsync AS libseccomp
ARG JOBS
COPY --from=gperf /gperf/ /
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
COPY --from=sources-downloader /sources/downloads/mpc.tar.xz .
COPY --from=expat /expat /
COPY --from=python-build /python /

RUN tar -xf gmp.tar.bz2
RUN tar -xf mpfr.tar.bz2
RUN tar -xf gdb.tar.gz && mv gdb-* gdb
RUN tar -xf mpc.tar.xz
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
COPY --from=expat /expat/ /
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=sources-downloader /sources/downloads/dbus.tar.xz /sources/
# install target
RUN mkdir -p /dbus
WORKDIR /sources
RUN pip3 install meson ninja
RUN tar -xf dbus.tar.xz && mv dbus-* dbus
WORKDIR /sources/dbus
RUN meson setup buildDir ${COMMON_MESON_FLAGS}
RUN DESTDIR=/dbus ninja -j${JOBS} -C buildDir install


# first pam build so we can build systemd against it
FROM python-build AS pam
ARG JOBS
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=openssl /openssl/ /
COPY --from=readline /readline/ /
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
RUN meson setup buildDir ${COMMON_MESON_FLAGS}
RUN DESTDIR=/pam ninja -j${JOBS} -C buildDir install
COPY files/pam/* /pam/etc/pam.d/


# shadow-base only deps
FROM rsync AS shadow-base
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=readline /readline/ /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /


# Shadow with PAM support, no systemd
FROM shadow-base AS shadow
ARG JOBS
COPY --from=pam /pam/ /
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
COPY --from=openssl /openssl/ /

COPY --from=zlib /zlib/ /

COPY --from=pam /pam/ /

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
# We already have a motd from bash, disable the sshd one
RUN echo "PrintMotd no" >> /openssh/etc/ssh/sshd_config.d/99-hadron.conf


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
COPY --from=xz /xz/ /

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
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dmanpages=false
RUN DESTDIR=/kmod ninja -j${JOBS} -C buildDir install && ninja -j${JOBS} -C buildDir install


## autoconf
FROM rsync AS autoconf
ARG JOBS
COPY --from=m4 /m4/ /


COPY --from=perl /perl/ /

COPY --from=sources-downloader /sources/downloads/autoconf.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf autoconf.tar.xz && mv autoconf-* autoconf && \
    cd autoconf && mkdir -p /autoconf && ./configure ${COMMON_CONFIGURE_ARGS} --prefix=/usr && make DESTDIR=/autoconf && \
    make -j${JOBS} -l${MAX_LOAD} DESTDIR=/autoconf install && make -j${JOBS} -l${MAX_LOAD} install


## automake
FROM rsync AS automake
ARG JOBS
COPY --from=perl /perl/ /

COPY --from=autoconf /autoconf/ /

COPY --from=m4 /m4/ /

COPY --from=sources-downloader /sources/downloads/automake.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf automake.tar.xz && mv automake-* automake && \
    cd automake && mkdir -p /automake && ./configure ${COMMON_CONFIGURE_ARGS} --prefix=/usr && make DESTDIR=/automake && \
    make -j${JOBS} -l${MAX_LOAD} DESTDIR=/automake install && make -j${JOBS} -l${MAX_LOAD} install


## libtool
FROM rsync AS libtool
ARG JOBS
COPY --from=m4 /m4/ /

COPY --from=sources-downloader /sources/downloads/libtool.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf libtool.tar.xz && mv libtool-* libtool && cd libtool && mkdir -p /libtool && sed -i \
-e "s|test-funclib-quote.sh||" \
-e "s|test-option-parser.sh||" \
gnulib-tests/Makefile.in && ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --disable-static --enable-shared && \
    make -j${JOBS} -l${MAX_LOAD} DESTDIR=/libtool install && make -j${JOBS} -l${MAX_LOAD} install


FROM rsync AS patch
ARG JOBS
COPY --from=autoconf /autoconf/ /
COPY --from=automake /automake/ /
COPY --from=m4 /m4/ /
COPY --from=perl /perl/ /
COPY --from=sources-downloader /sources/downloads/patch.tar.gz /sources/
WORKDIR /sources
RUN tar -xvf patch.tar.gz && mv patch-* patch
WORKDIR /sources/patch
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr
RUN make -j${JOBS} -l${MAX_LOAD}
RUN make -j${JOBS} -l${MAX_LOAD} DESTDIR=/patch install

## fts
## fts is only needed to build dracut as it needs libfts.so
## This is only needed during build time so we can drop it later
FROM rsync AS fts
ARG JOBS
ENV CFLAGS="$CFLAGS -fPIC"

COPY --from=autoconf /autoconf/ /

COPY --from=automake /automake/ /

COPY --from=m4 /m4/ /

COPY --from=perl /perl/ /

COPY --from=libtool /libtool/ /

COPY --from=pkgconfig /pkgconfig/ /

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


## argp-standalone — provides argp_parse for musl (required by elfutils configure)
FROM rsync AS argp
ARG JOBS
COPY --from=sources-downloader /sources/downloads/argp-standalone.tar.gz /sources/
WORKDIR /sources
RUN tar -xf argp-standalone.tar.gz && mv argp-standalone-* argp
WORKDIR /sources/argp
RUN gcc ${CFLAGS} -fPIC -I. \
      -c argp-ba.c argp-eexst.c argp-fmtstream.c argp-help.c argp-parse.c argp-pv.c argp-pvh.c && \
    gcc-ar rcs libargp.a argp-ba.o argp-eexst.o argp-fmtstream.o argp-help.o argp-parse.o argp-pv.o argp-pvh.o && \
    mkdir -p /argp/usr/lib /argp/usr/include && \
    cp libargp.a /argp/usr/lib/libargp.a && \
    cp libargp.a /usr/lib/libargp.a && \
    cp argp.h /argp/usr/include/argp.h && \
    cp argp.h /usr/include/argp.h

## musl-obstack — provides obstack functions for musl (required by elfutils configure)
FROM rsync AS obstack
ARG JOBS
ENV CFLAGS="$CFLAGS -fPIC"
COPY --from=autoconf /autoconf/ /
COPY --from=automake /automake/ /
COPY --from=m4 /m4/ /
COPY --from=perl /perl/ /
COPY --from=libtool /libtool/ /
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=sources-downloader /sources/downloads/musl-obstack.tar.gz /sources/
RUN mkdir -p /sources && cd /sources && tar -xf musl-obstack.tar.gz && mv musl-obstack-* obstack && \
    cd obstack && ./bootstrap.sh && \
    ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --prefix=/usr --localstatedir=/var --sysconfdir=/etc && \
    make -j${JOBS} DESTDIR=/obstack install && make -j${JOBS} install

## elfutils — provides libdw (DWARF library) and libelf needed by pahole/dwarves for BTF generation
FROM fts AS elfutils
ARG JOBS
# elfutils must NOT use LTO: lto-wrapper re-invokes make with elfutils' own -Werror=stack-usage=
# which causes argp-help.c to fail with "stack usage might be unbounded".
# Docker ENV does not support bash ${VAR//pat/sub} substitution, so set flags directly.
ENV CFLAGS="-Os -pipe -fomit-frame-pointer -fno-unroll-loops -fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections"
ENV LDFLAGS="-Wl,--gc-sections -Wl,--as-needed"
COPY --from=argp /argp/ /
COPY --from=obstack /obstack/ /
COPY --from=zlib /zlib/ /
COPY --from=sources-downloader /sources/downloads/elfutils.tar.bz2 /sources/
RUN mkdir -p /elfutils
WORKDIR /sources
RUN tar -xf elfutils.tar.bz2 && mv elfutils-* elfutils
WORKDIR /sources/elfutils
RUN ./configure ${COMMON_CONFIGURE_ARGS} \
    --disable-lto \
    --without-bzlib \
    --without-lzma \
    --disable-debuginfod \
    --disable-libdebuginfod \
    --disable-nls
RUN make -j${JOBS} -C lib && \
    make -j${JOBS} -C libelf && \
    make -j${JOBS} -C libcpu && \
    make -j${JOBS} -C libebl && \
    make -j${JOBS} -C backends && \
    make -j${JOBS} -C libdwelf && \
    make -j${JOBS} -C libdwfl && \
    make -j${JOBS} -C libdw && \
    make -C libelf install DESTDIR=/elfutils && \
    make -C backends install DESTDIR=/elfutils && \
    make -C libdw install DESTDIR=/elfutils
RUN rm -rf /elfutils/usr/share


FROM rsync AS diffutils
ARG JOBS
RUN mkdir -p /diffutils
COPY --from=sources-downloader /sources/downloads/diffutils.tar.xz /sources/
COPY --from=perl /perl/ /
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
COPY --from=autoconf /autoconf/ /
COPY --from=automake /automake/ /
COPY --from=libtool /libtool/ /
COPY --from=m4 /m4/ /
COPY --from=perl /perl/ /
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=openssl /openssl/ /
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

# TODO: Once a new jsonc version is released (0.19) they will have meson support
# which means we can drop cmake buiilding which is very slow and heavy
FROM rsync AS cmake
ARG JOBS
# Disable lto for cmake as it gives us nothing but issues
ENV CFLAGS="${CFLAGS//-flto=auto/}"
ENV LDFLAGS="${LDFLAGS//-flto=auto/}"
COPY --from=curl /curl/ /
COPY --from=openssl /openssl/ /
COPY --from=sources-downloader /sources/downloads/cmake.tar.gz /sources/

RUN mkdir -p /cmake
WORKDIR /sources
RUN tar -xf cmake.tar.gz && mv cmake-* cmake
WORKDIR /sources/cmake

RUN ./bootstrap --prefix=/usr --no-debugger  --parallel=${JOBS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/cmake

## pahole (dwarves) — required by the kernel to generate BTF from DWARF debug info
FROM rsync AS pahole
ARG JOBS
COPY --from=cmake /cmake/ /
COPY --from=openssl /openssl/ /
COPY --from=elfutils /elfutils/ /
COPY --from=zlib /zlib/ /
COPY --from=sources-downloader /sources/downloads/dwarves.tar.xz /sources/
WORKDIR /sources
RUN tar -xf dwarves.tar.xz && mv dwarves-* dwarves
RUN mkdir -p /pahole /sources/dwarves-build
WORKDIR /sources/dwarves-build
RUN cmake ../dwarves \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_BUILD_TYPE=MinSizeRel \
      -D__LIB=lib \
      && \
    make -j${JOBS} && \
    make install DESTDIR=/pahole
# Only pahole binary and its shared-library dependencies are needed at kernel build time.
# Remove headers and static libs to keep the layer small.
RUN rm -rf /pahole/usr/include

## kernel
FROM rsync AS kernel-base
ARG JOBS
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /

COPY --from=readline /readline/ /

COPY --from=flex /flex/ /

COPY --from=m4 /m4/ /

COPY --from=bison /bison/ /

COPY --from=libelf /libelf/ /

COPY --from=elfutils /elfutils/ /

COPY --from=openssl /openssl/ /

COPY --from=perl /perl/ /

COPY --from=gawk /gawk/ /

COPY --from=findutils /findutils/ /

COPY --from=diffutils /diffutils/ /

COPY --from=kmod /kmod/ /

COPY --from=xz /xz/ /

COPY --from=grep /grep/ /

COPY --from=pahole /pahole/ /

COPY --from=sources-downloader /sources/downloads/linux.tar.gz /sources/

RUN mkdir -p /sources/kernel-configs
COPY ./files/kernel/* /sources/kernel-configs/

RUN mkdir -p /kernel && mkdir -p /modules

WORKDIR /sources
RUN tar -xf linux.tar.gz && mv linux-* kernel

# Apply kernel patches (sorted; ignore if none).
# LP: #2137714 — virt: vmgenid: remap memory as decrypted (fixes SEV-SNP boot on AWS).
COPY ./files/kernel-patches /sources/kernel-patches
RUN cd /sources/kernel && \
    for p in $(ls /sources/kernel-patches/*.patch 2>/dev/null | sort); do \
        echo "Applying kernel patch: $p"; \
        patch -p1 < "$p"; \
    done


FROM kernel-base AS kernel-cloud
WORKDIR /sources/kernel
RUN if [ ${ARCH} = "aarch64" ] ; then \
    cp -rfv /sources/kernel-configs/cloud-arm64.config .config ; \
    elif [ ${ARCH} = "riscv64" ] ; then \
    cp -rfv /sources/kernel-configs/cloud-riscv64.config .config ; \
    else \
    cp -rfv /sources/kernel-configs/cloud.config .config ; \
    fi

FROM kernel-base AS kernel-default
WORKDIR /sources/kernel
RUN if [ ${ARCH} = "aarch64" ] ; then \
    cp -rfv /sources/kernel-configs/default-arm64.config .config ; \
    elif [ ${ARCH} = "riscv64" ] ; then \
    cp -rfv /sources/kernel-configs/default-riscv64.config .config ; \
    else \
    cp -rfv /sources/kernel-configs/default.config .config ; \
    fi

FROM kernel-${KERNEL_TYPE} AS kernel-build
ARG JOBS
WORKDIR /sources/kernel
# This only builds the kernel
# Linux 7.0 added __attribute_const__ to include/uapi/linux/swab.h. That macro is defined in
# include/linux/compiler_types.h (kernel-internal), which host tools never include. Defining it
# empty silences the undefined-macro errors; it is only an optimization hint and has no effect
# on correctness for build-time host tools such as objtool and insn_sanity.
RUN hcflags='-D__attribute_const__=' && \
    if [ ${ARCH} = "aarch64" ]; then \
    ARCH=arm64 make olddefconfig; \
    ARCH=arm64 make -s -j${JOBS} -l${MAX_LOAD} HOSTCFLAGS="$hcflags" Image; \
    elif [ ${ARCH} = "riscv64" ]; then \
    ARCH=riscv make olddefconfig; \
    ARCH=riscv make -s -j${JOBS} -l${MAX_LOAD} HOSTCFLAGS="$hcflags" Image; \
    else \
    ARCH=x86_64 make olddefconfig; \
    ARCH=x86_64 make -s -j${JOBS} -l${MAX_LOAD} HOSTCFLAGS="$hcflags" bzImage; \
    fi
RUN if [ ${ARCH} = "aarch64" ]; then \
    export ARCH=arm64; \
    elif [ ${ARCH} = "riscv64" ]; then \
    export ARCH=riscv; \
    else \
    export ARCH=x86_64;\
    fi;  make -s -j${JOBS} kernelrelease > /kernel/kernel-release ; make -s -j${JOBS} kernelversion > /kernel/kernel-version
RUN if [ ${ARCH} = "aarch64" ]; then \
    ARCH=arm64 kver=$(cat /kernel/kernel-release) && cp arch/$ARCH/boot/Image /kernel/vmlinuz-${kver}; \
    elif [ ${ARCH} = "riscv64" ]; then \
    ARCH=riscv kver=$(cat /kernel/kernel-release) && cp arch/$ARCH/boot/Image /kernel/vmlinuz-${kver}; \
    else \
    ARCH=x86_64 kver=$(cat /kernel/kernel-release) && cp arch/$ARCH/boot/bzImage /kernel/vmlinuz-${kver};\
    fi
# link vmlinuz to our kernel
RUN ln -sfv /kernel/vmlinuz-$(cat /kernel/kernel-release) /kernel/vmlinuz

FROM kernel-build AS kernel-no-fips
# Nothing to do here, just a placeholder


# This will generate the needed FIPS HMAC for the kernel so dracut can verify it
FROM kernel-build AS kernel-fips
WORKDIR /sources/
# Generate the FIPS integrity HMAC for the kernel. libkcapi/sha512hmac can only reach the
# kernel crypto API through AF_ALG, which Docker's default seccomp profile blocks at build
# time (socket(AF_ALG) -> EPERM). Instead compute the HMAC with the FIPS OpenSSL (the
# openssl-${FIPS} alias selects the FIPS build): HMAC-SHA512 with the well-known sha512hmac
# key produces a byte-identical digest that `kcapi-hasher -c` accepts at runtime, and it
# needs no kernel crypto API so it works under qemu emulation for every architecture.
COPY --from=openssl /openssl/ /
# Make sure the kernel image we are about to hash actually exists and is not empty.
RUN kver=$(cat /kernel/kernel-release) && \
    [ -s "/kernel/vmlinuz-${kver}" ] || { echo "ERROR: kernel image /kernel/vmlinuz-${kver} is missing or empty" >&2; exit 1; }
# Compute the HMAC and write the checkfile with the runtime /boot path so dracut can verify it at boot.
RUN kver=$(cat /kernel/kernel-release) && \
    hmac=$(openssl dgst -sha512 -hmac "FIPS-FTW-RHT2009" "/kernel/vmlinuz-${kver}" | awk '{print $NF}') && \
    [ -n "${hmac}" ] || { echo "ERROR: computed kernel HMAC is empty" >&2; exit 1; } && \
    printf '%s  /boot/vmlinuz-%s\n' "${hmac}" "${kver}" > "/kernel/.vmlinuz-${kver}.hmac"
# Make sure the checkfile was actually written, then set the permissions dracut expects.
RUN kver=$(cat /kernel/kernel-release) && \
    [ -s "/kernel/.vmlinuz-${kver}.hmac" ] || { echo "ERROR: generated /kernel/.vmlinuz-${kver}.hmac is empty" >&2; exit 1; } && \
    chmod 0644 "/kernel/.vmlinuz-${kver}.hmac"

FROM kernel-${FIPS} AS kernel

FROM kernel-build AS kernel-modules
# This builds the modules
RUN hcflags='-D__attribute_const__=' && \
    if [ ${ARCH} = "aarch64" ]; then \
    export ARCH=arm64; \
    elif [ ${ARCH} = "riscv64" ]; then \
    export ARCH=riscv; \
    else \
    export ARCH=x86_64;\
    fi;  make -s -j${JOBS} -l${MAX_LOAD} HOSTCFLAGS="$hcflags" modules
RUN if [ ${ARCH} = "aarch64" ]; then \
    export ARCH=arm64; \
    elif [ ${ARCH} = "riscv64" ]; then \
    export ARCH=riscv; \
    else \
    export ARCH=x86_64;\
    fi;  ZSTD_CLEVEL=19 INSTALL_MOD_PATH="/modules" INSTALL_MOD_STRIP=1 make -s -j${JOBS} -l${MAX_LOAD} modules_install

FROM kernel-base AS kernel-headers
ARG JOBS
WORKDIR /sources/kernel
# This installs the headers
RUN if [ ${ARCH} = "aarch64" ]; then \
    export ARCH=arm64; \
    elif [ ${ARCH} = "riscv64" ]; then \
    export ARCH=riscv; \
    else \
    export ARCH=x86_64;\
    fi; make -s -j${JOBS} -l${MAX_LOAD} headers_install INSTALL_HDR_PATH=/linux-headers

FROM kernel-modules AS kernel-misc
WORKDIR /output/
# This copies some extra stuff from the kernel, like the kernel version and config, that we can use in the toolchain if needed
RUN cp /kernel/kernel-version /output/kernel-version
RUN cp /kernel/kernel-release /output/kernel-release
RUN cp /sources/kernel/.config /output/kernel-config
# This is useful to build out-of-tree modules against our kernel, it contains the exported symbols from the kernel that modules can use
# This way we dont have to rebuild the kernel or the modules
RUN cp /sources/kernel/Module.symvers /output/Module.symvers

## kbd for setting the console keymap and font
FROM rsync AS kbd
ARG JOBS
COPY --from=pkgconfig /pkgconfig/ /

# Use coreutils for install as it needs ln to support relative symlinks
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /
# Use openssl for libssl and libcrypto
COPY --from=openssl /openssl/ /
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
COPY --from=gawk /gawk/ /
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
COPY --from=libmnl /libmnl/ /
COPY --from=pkgconfig /pkgconfig/ /
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
COPY --from=libmnl /libmnl/ /
COPY --from=libnftnl /libnftnl/ /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=pkgconfig /pkgconfig/ /
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

## libnfnetlink (low-level netlink helper used by the libnetfilter_* libs)
FROM rsync AS libnfnetlink
ARG JOBS
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=sources-downloader /sources/downloads/libnfnetlink.tar.bz2 /sources/
RUN mkdir -p /libnfnetlink
WORKDIR /sources
RUN tar -xf libnfnetlink.tar.bz2 && mv libnfnetlink-* libnfnetlink
WORKDIR /sources/libnfnetlink
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libnfnetlink

## libnetfilter_conntrack (conntrack object/netlink library used by conntrack-tools)
FROM rsync AS libnetfilter_conntrack
ARG JOBS
COPY --from=libmnl /libmnl/ /
COPY --from=libnfnetlink /libnfnetlink/ /
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=sources-downloader /sources/downloads/libnetfilter_conntrack.tar.xz /sources/
RUN mkdir -p /libnetfilter_conntrack
WORKDIR /sources
RUN tar -xf libnetfilter_conntrack.tar.xz && mv libnetfilter_conntrack-* libnetfilter_conntrack
WORKDIR /sources/libnetfilter_conntrack
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libnetfilter_conntrack

## libnetfilter_cttimeout (connection-tracking timeout policy library used by conntrackd)
FROM rsync AS libnetfilter_cttimeout
ARG JOBS
COPY --from=libmnl /libmnl/ /
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=sources-downloader /sources/downloads/libnetfilter_cttimeout.tar.bz2 /sources/
RUN mkdir -p /libnetfilter_cttimeout
WORKDIR /sources
RUN tar -xf libnetfilter_cttimeout.tar.bz2 && mv libnetfilter_cttimeout-* libnetfilter_cttimeout
WORKDIR /sources/libnetfilter_cttimeout
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libnetfilter_cttimeout

## libnetfilter_cthelper (user-space conntrack helper library used by conntrackd)
FROM rsync AS libnetfilter_cthelper
ARG JOBS
COPY --from=libmnl /libmnl/ /
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=sources-downloader /sources/downloads/libnetfilter_cthelper.tar.bz2 /sources/
RUN mkdir -p /libnetfilter_cthelper
WORKDIR /sources
RUN tar -xf libnetfilter_cthelper.tar.bz2 && mv libnetfilter_cthelper-* libnetfilter_cthelper
WORKDIR /sources/libnetfilter_cthelper
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libnetfilter_cthelper

## libnetfilter_queue (packet-queueing library used by conntrack-tools)
FROM rsync AS libnetfilter_queue
ARG JOBS
COPY --from=libmnl /libmnl/ /
COPY --from=libnfnetlink /libnfnetlink/ /
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=sources-downloader /sources/downloads/libnetfilter_queue.tar.bz2 /sources/
RUN mkdir -p /libnetfilter_queue
WORKDIR /sources
RUN tar -xf libnetfilter_queue.tar.bz2 && mv libnetfilter_queue-* libnetfilter_queue
WORKDIR /sources/libnetfilter_queue
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libnetfilter_queue

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
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=libaio /libaio/ /
COPY --from=readline /readline/ /
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

FROM rsync AS jsonc
ARG JOBS
COPY --from=cmake /cmake/ /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=readline /readline/ /
COPY --from=openssl /openssl/ /
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
COPY --from=sources-downloader /sources/downloads/pax-utils.tar.gz /sources/
RUN mkdir -p /pax-utils
WORKDIR /sources
RUN tar -xf pax-utils.tar.gz && mv pax-utils-* pax-utils
WORKDIR /sources/pax-utils
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtests=false -Duse_fuzzing=false
RUN DESTDIR=/pax-utils ninja -j${JOBS} -C buildDir install
RUN ninja -j${JOBS} -C buildDir install

# Build URCU static as its only used by multipathd and never reused again, we can save space this way
FROM rsync AS urcu
ARG JOBS
ENV CFLAGS="${CFLAGS} -fPIC"
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=pax-utils /pax-utils/ /

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
COPY --from=pkgconfig /pkgconfig/ /
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

FROM rsync AS libxml
ARG JOBS
RUN mkdir -p /libxml
COPY --from=pkgconfig /pkgconfig/ /

COPY --from=sources-downloader /sources/downloads/libxml2.tar.xz /sources/
WORKDIR /sources
RUN tar -xf libxml2.tar.xz && mv libxml2-* libxml2
WORKDIR /sources/libxml2
RUN ./configure ${COMMON_CONFIGURE_ARGS} --without-python
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libxml

## bsd-compat-headers - <sys/queue.h>, <sys/cdefs.h>, <sys/tree.h>. musl does
## not ship these BSD compatibility headers; Alpine packages them as the
## `bsd-compat-headers` aport. Several packages we build (libtirpc, nfs-utils)
## need them at compile time, so we factor the extraction into a single small
## stage and COPY --from in each consumer.
FROM alpine-base AS bsd-compat-headers
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /sources/
WORKDIR /sources
RUN tar -xf aports.tar.gz && mv aports-* aport
RUN install -Dm644 -t /bsd-compat-headers/usr/include/sys \
      aport/main/bsd-compat-headers/cdefs.h \
      aport/main/bsd-compat-headers/queue.h \
      aport/main/bsd-compat-headers/tree.h

## libtirpc - userspace SunRPC library. Required by nfs-utils since glibc/musl
## do not ship sunrpc. --disable-gssapi avoids the krb5 dependency.
##
## libtirpc uses <sys/queue.h> and <sys/cdefs.h>; see the bsd-compat-headers
## stage above for the source of those.
FROM rsync AS libtirpc
ARG JOBS
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=bsd-compat-headers /bsd-compat-headers/ /

COPY --from=sources-downloader /sources/downloads/libtirpc.tar.bz2 /sources/
RUN mkdir -p /libtirpc
WORKDIR /sources
RUN tar -xf libtirpc.tar.bz2 && mv libtirpc-* libtirpc
WORKDIR /sources/libtirpc
## --enable-rpcdb forces libtirpc to ship the BSD RPC database functions
## (getrpcent/getrpcbyname/getrpcbynumber/setrpcent/endrpcent). They are
## OFF by default because glibc ships them in libc, but musl does not and
## nfs-utils' configure requires them. Without this flag, nfs-utils fails:
##   configure: error: Neither getrpcbynumber_r nor getrpcbynumber are available
RUN ./configure ${COMMON_CONFIGURE_ARGS} \
      --sysconfdir=/etc \
      --disable-gssapi \
      --disable-authdes \
      --enable-rpcdb
RUN make -s -j${JOBS} -l${MAX_LOAD}
RUN make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libtirpc

## conntrack-tools (conntrack + conntrackd binaries). Defined after libtirpc
## because conntrackd's RPC sync support requires it at configure time.
FROM rsync AS conntrack-tools
ARG JOBS
COPY --from=libmnl /libmnl/ /
COPY --from=libnfnetlink /libnfnetlink/ /
COPY --from=libnetfilter_conntrack /libnetfilter_conntrack/ /
COPY --from=libnetfilter_cttimeout /libnetfilter_cttimeout/ /
COPY --from=libnetfilter_cthelper /libnetfilter_cthelper/ /
COPY --from=libnetfilter_queue /libnetfilter_queue/ /
COPY --from=flex /flex/ /
COPY --from=bison /bison/ /
COPY --from=libtirpc /libtirpc/ /
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=sources-downloader /sources/downloads/conntrack-tools.tar.xz /sources/
RUN mkdir -p /conntrack-tools
WORKDIR /sources
RUN tar -xf conntrack-tools.tar.xz && mv conntrack-tools-* conntrack-tools
WORKDIR /sources/conntrack-tools
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/conntrack-tools

## procps-ng — provides the sysctl(8) CLI. systemd-sysctl only applies
## drop-in config files (it cannot read/list/set keys at runtime) and is
## explicitly not a sysctl replacement upstream. Consumers like Stylus run
## `sysctl --system` in preflight, so we ship the real binary. Final image
## only (baremetal), not the container base. Built with a static libproc2
## (--disable-shared --enable-static) so the result is a single
## self-contained binary; ncurses/nls/kill/pidof are dropped since we only
## keep sysctl.
FROM rsync AS procps-ng
ARG JOBS
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=sources-downloader /sources/downloads/procps-ng.tar.xz /sources/
WORKDIR /sources
RUN tar -xf procps-ng.tar.xz && mv procps-ng-* procps-ng
WORKDIR /sources/procps-ng
RUN ./configure ${COMMON_CONFIGURE_ARGS} \
      --disable-shared --enable-static \
      --disable-nls \
      --without-ncurses \
      --without-systemd \
      --disable-kill \
      --disable-pidof
RUN make -s -j${JOBS} -l${MAX_LOAD}
RUN make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/procps-ng-full
## Keep only the sysctl binary (location varies by usrmerge layout)
RUN mkdir -p /procps-ng/usr/sbin && \
    cp "$(find /procps-ng-full -type f -name sysctl | head -n1)" /procps-ng/usr/sbin/sysctl


## libnl - netlink library. Hard build-time dep of nfs-utils >= 2.7 (used
## for the in-kernel notification netlink interface). Standard autotools
## build; --disable-cli drops the libnl CLI utilities we don't ship.
FROM rsync AS libnl
ARG JOBS
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=flex /flex/ /
COPY --from=m4 /m4/ /
COPY --from=bison /bison/ /

COPY --from=sources-downloader /sources/downloads/libnl.tar.gz /sources/
RUN mkdir -p /libnl
WORKDIR /sources
RUN tar -xf libnl.tar.gz && mv libnl-* libnl
WORKDIR /sources/libnl
RUN ./configure ${COMMON_CONFIGURE_ARGS} \
      --sysconfdir=/etc \
      --disable-cli
RUN make -s -j${JOBS} -l${MAX_LOAD} \
 && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libnl

## libevent - async event notification library. Hard build-time dep of
## nfs-utils (used by sm-notify and by the new netlink-based daemons).
FROM rsync AS libevent
ARG JOBS
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=openssl /openssl/ /

COPY --from=sources-downloader /sources/downloads/libevent.tar.gz /sources/
RUN mkdir -p /libevent
WORKDIR /sources
RUN tar -xf libevent.tar.gz && mv libevent-* libevent
WORKDIR /sources/libevent
RUN ./configure ${COMMON_CONFIGURE_ARGS} \
      --sysconfdir=/etc \
      --disable-samples \
      --disable-libevent-regress
RUN make -s -j${JOBS} -l${MAX_LOAD} \
 && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/libevent

## keyutils - kernel keyring API + libkeyutils.so. Required by nfs-utils'
## nfsidmap binary, which the kernel calls via request-key for NFSv4 ID
## mapping. Plain Makefile build, not autotools — the cross-compile vars
## (CC, AR, LD) are picked up from ENV automatically; only LIBDIR is set
## here so the later nfs-utils build finds libkeyutils via pkg-config.
FROM rsync AS keyutils
ARG JOBS
COPY --from=sources-downloader /sources/downloads/keyutils.tar.gz /sources/
RUN mkdir -p /keyutils
WORKDIR /sources
RUN tar -xf keyutils.tar.gz && mv keyutils-* keyutils
WORKDIR /sources/keyutils
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/keyutils LIBDIR=/usr/lib

## nfs-utils - provides mount.nfs / mount.nfs4 host helpers required by
## `mount -t nfs`. Without them, Longhorn RWX (and any other in-cluster NFS
## storage) fails even though kernel NFS client modules are present.
## See https://github.com/kairos-io/kairos/issues/4086.
##
## Minimal client build:
##   --disable-gss          : no Kerberos / RPCSEC_GSS support (drops the krb5
##                            link dep; libevent is still pulled in by other
##                            code paths like rpc.idmapd)
##   --disable-nfsv4server  : kernel server is not in scope here
##   --disable-nfsdcld /
##   --disable-nfsdcltrack  : server-side state DB, not needed for client
##   --disable-nfsdctl      : kernel-server admin tool; pulls in readline
##                            which on this image links to libtermcap symbols
##                            that aren't shipped (no ncurses).
##   --disable-junction     : drops nfsref (NFS junction admin tool, server-side)
##   --without-tcp-wrappers : tcp_wrappers is dead, not shipped
##   --enable-tirpc         : use libtirpc (built above) instead of glibc sunrpc
##   --with-rpcgen=internal : build nfs-utils' bundled rpcgen instead of
##                            requiring a host one (Alpine builder has none).
FROM rsync AS nfs-utils
ARG JOBS
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=libtirpc /libtirpc/ /
COPY --from=libnl /libnl/ /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks /libcap/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks /util-linux/. /
COPY --from=sqlite3 /sqlite3/ /
COPY --from=libxml /libxml/ /
COPY --from=libevent /libevent/ /
COPY --from=keyutils /keyutils /keyutils
RUN rsync -aHAX --keep-dirlinks  /keyutils/. /

## BSD compat headers (queue.h, cdefs.h, tree.h) - musl does not ship these
## and nfs-utils uses them in several places.
COPY --from=bsd-compat-headers /bsd-compat-headers/ /

COPY --from=sources-downloader /sources/downloads/nfs-utils.tar.xz /sources/
RUN mkdir -p /nfs-utils
WORKDIR /sources
RUN tar -xf nfs-utils.tar.xz && mv nfs-utils-* nfs-utils
WORKDIR /sources/nfs-utils
# LIBS="-ltirpc": musl does not ship the BSD RPC database functions
# (getrpcbynumber*, getrpcbyname*); libtirpc provides them. nfs-utils' own
# AC_CHECK_FUNCS doesn't add libtirpc to the link line for the check, so
# we add it here. Without this configure fails with
# "Neither getrpcbynumber_r nor getrpcbynumber are available".
RUN LIBS="-ltirpc" \
    ./configure ${COMMON_CONFIGURE_ARGS} \
      --sysconfdir=/etc \
      --sbindir=/sbin \
      --enable-tirpc \
      --disable-gss \
      --disable-nfsv4server \
      --disable-nfsdcld \
      --disable-nfsdcltrack \
      --disable-nfsdctl \
      --disable-junction \
      --without-tcp-wrappers \
      --with-statedir=/var/lib/nfs \
      --with-rpcgen=internal

# musl >= 1.2 dropped stat64 / struct stat64 — `stat` is already 64-bit on
# all musl platforms. nfs-utils' bundled rpcgen still references the old
# names. Substitute them in-place; the fields are identical so this is a
# pure rename, no semantic change.
RUN sed -i 's/\bstruct stat64\b/struct stat/g; s/\bstat64 (/stat (/g; s/\bstat64(/stat(/g' \
      tools/rpcgen/rpc_main.c

# nfs-utils 2.9.1 bug: support/nfs/fh_key_file.c calls strerror() but is
# missing <string.h>. GCC infers `int` return type and the format check
# (-Werror=format) rejects it. Upstream issue, not musl-specific; the
# file was added in 2025 and the omission slipped through.
# Fixed upstream in commit 0097ceb (post-2.9.1, not yet in a tagged release):
# https://git.linux-nfs.org/?p=steved/nfs-utils.git;a=commit;h=0097ceb136a7db15c535a78fca01e2814e82d2a7
# Drop this whole block once we bump to a release that contains the fix.
# The grep guard makes it a no-op if the file already has the include
# (e.g. after a version bump that pulls in the upstream patch); the sed
# anchors on <errno.h> rather than a line number so it survives reorders.
RUN if ! grep -q '^#include <string\.h>' support/nfs/fh_key_file.c; then \
        sed -i '/^#include <errno\.h>/a #include <string.h>' support/nfs/fh_key_file.c; \
    fi

RUN make -s -j${JOBS} -l${MAX_LOAD} \
 && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/nfs-utils

# Trim to client-only. nfs-utils ships several server-side and NFSv3-only
# binaries that aren't useful on a Hadron node and only drag libnl,
# libxml2, and libevent into the final image. We already disable
# everything we can at configure-time (see flags above); the binaries
# listed here are built unconditionally — utils/Makefile.am hardcodes
# them as SUBDIRS with no AM_CONDITIONAL, so `rm -f` after install is
# the cleanest way to drop them.
#
# Kept:  mount.nfs[4], umount.nfs[4]  (the actual bug fix)
#        nfsidmap + libnfsidmap       (NFSv4 ID mapping via kernel keyring)
#        showmount, nfsstat, nfsiostat, mountstats, nfsconf  (client diag)
#        rpcdebug                                            (kernel debug toggle)
# Dropped: rpc.mountd, rpc.nfsd, exportfs, fsidd, nfsdclnts  (server)
#          rpc.statd, sm-notify, start-statd                 (NFSv3 NSM)
#          rpc.idmapd                                        (superseded by nfsidmap)
#          rpcctl, rpcgen                                    (server/build-only)
RUN rm -f \
      /nfs-utils/sbin/rpc.mountd \
      /nfs-utils/sbin/rpc.nfsd \
      /nfs-utils/sbin/exportfs \
      /nfs-utils/sbin/fsidd \
      /nfs-utils/sbin/nfsdclnts \
      /nfs-utils/sbin/rpc.statd \
      /nfs-utils/sbin/sm-notify \
      /nfs-utils/sbin/start-statd \
      /nfs-utils/sbin/rpc.idmapd \
      /nfs-utils/sbin/rpcctl

## No need to have systemd support, systemd-cryptsetup picks cryptsetup directly
FROM rsync AS cryptsetup
ARG JOBS
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=lvm2 /lvm2/ /
COPY --from=openssl /openssl/ /
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
COPY --from=jsonc /jsonc/ /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=readline /readline/ /
COPY --from=pax-utils /pax-utils/ /
COPY --from=popt /popt/ /

COPY --from=sources-downloader /sources/downloads/cryptsetup.tar.xz /sources/
RUN mkdir -p /cryptsetup
WORKDIR /sources
RUN tar -xf cryptsetup.tar.xz && mv cryptsetup-* cryptsetup
WORKDIR /sources/cryptsetup
# You can build cryptsetup with fips extensions if you pass the --use-fips flag
# but that will only work when using gcrypt as the crypto backend
# Still, its not certified and building with the flag AND openssl will still give you a cryptsetupt hat reports as FIPS capable
# while its not, so we avoid confusion and just build without fips support at all here.
RUN ./configure ${COMMON_CONFIGURE_ARGS} --with-crypto-backend=openssl --disable-asciidoc  --disable-nls --disable-ssh-token
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/cryptsetup

FROM rsync AS parted
ARG JOBS
## device-mapper from lvm2
COPY --from=lvm2 /lvm2/ /

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
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=openssl /openssl/ /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=readline /readline/ /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
COPY --from=bison /bison/ /
COPY --from=flex /flex/ /
COPY --from=xz /xz/ /
COPY --from=m4 /m4/ /
COPY --from=lvm2 /lvm2/ /
COPY --from=gawk /gawk/ /

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
	elif [ "${ARCH}" = "riscv64" ]; then \
		grub_format="riscv64-efi"; \
		grub_efi_name="grubriscv64.efi"; \
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
        search_fs_file chain loadenv gfxterm all_video iso9660 help test smbios

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
# GRUB BIOS (i386-pc) is only supported on x86-64
RUN if [ "${ARCH}" = "x86-64" ]; then ./configure ${COMMON_CONFIGURE_ARGS} --with-platform=pc --disable-werror;fi
# Reconfigure gnulib shipped with grub to avoid build issues
# This comes because on grub 2.14 these files are shipped pre-generated and they were built on a glibc system
# which causes issues when building on musl systems as it expects the bsd-compat-headers to be available
# which is not the case here. So we force regenerating these files with our musl toolchain so it can find there is no cdefs
RUN if [ "${ARCH}" = "x86-64" ]; then make -s -j${JOBS} -l${MAX_LOAD} -C grub-core/lib/gnulib;fi
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

RUN if [ "${ARCH}" = "x86-64" ]; then \
    make -s -j${JOBS} -l${MAX_LOAD} TARGET_IMG_BASE_LDOPT='-Wl,-Ttext' && \
    make -s -j${JOBS} -l${MAX_LOAD} TARGET_IMG_BASE_LDOPT='-Wl,-Ttext' install-strip DESTDIR=/grub-bios ; \
    fi
# Test the mkimage generation in case we have a misalignment on the kernel.img start entry point
RUN if [ "${ARCH}" = "x86-64" ]; then \
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
COPY --from=libelf /libelf/ /
COPY --from=iconv /iconv/ /
COPY --from=sources-downloader /sources/downloads/shim.tar.bz2 /sources/
WORKDIR /sources
RUN tar -xf shim.tar.bz2 && mv shim-* shim
WORKDIR /sources/shim
RUN mkdir -p /shim/usr/share/efi/
# Fix the make.defaults to update the objcopy command to use the proper --output-target instead of --target as the flag has changed on binutils 2.46
# When a new shim version is released, this will be fixed (current shim version is 16.1)
# https://github.com/rhboot/shim/commit/c4665d282072df2ed8ab6ae1d5fa0de41e5db02f
RUN sed -i 's/--target efi-app-$(ARCH)/--output-target efi-app-$(ARCH)/' Make.defaults
# Install it to a temp folder as the dir struct is terrible
# and we want it to be available at /usr/share/efi/shimXX.efi
# TEMP workaround, we should add our paths into the sdk so agent and aurora both search for the proper shim path
# Skip shim build for RISC-V as it doesn't have Secure Boot support yet
RUN if [ "${ARCH}" != "riscv64" ]; then \
    make -s -j${JOBS} -l${MAX_LOAD} EFIDIR=hadron ARCH=${BUILD_ARCH} DESTDIR=/tmp/shim install; \
    fi
RUN if [ ${ARCH} = "aarch64" ] ; then \
    mkdir -p /shim/usr/share/efi/aarch64 && cp /tmp/shim/boot/efi/EFI/BOOT/BOOTAA64.EFI /shim/usr/share/efi/aarch64/shim.efi ; \
    elif [ ${ARCH} = "riscv64" ] ; then \
    mkdir -p /shim/usr/share/efi/riscv64 ; \
    else \
    mkdir -p /shim/usr/share/efi/x86_64 && cp /tmp/shim/boot/efi/EFI/BOOT/BOOTX64.EFI /shim/usr/share/efi/x86_64/shim.efi ; \
    fi

FROM rsync AS tpm2-tss
ARG JOBS
RUN mkdir -p /tpm2-tss

COPY --from=pkgconfig /pkgconfig/ /
COPY --from=openssl /openssl/ /
COPY --from=jsonc /jsonc/ /
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=curl /curl/ /
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

FROM rsync AS libucontext
ARG JOBS
COPY --from=sources-downloader /sources/downloads/libucontext.tar.gz /sources/
RUN mkdir -p /libucontext
WORKDIR /sources
RUN tar -xf libucontext.tar.gz && mv libucontext-* libucontext
WORKDIR /sources/libucontext
RUN make -s -j${JOBS} ARCH=${BUILD_ARCH}
RUN make -s ARCH=${BUILD_ARCH} install DESTDIR=/libucontext

## systemd
## Try to build it at the end so we have most libraries already built
## Anything that depends on systemd should be built after this stage
FROM rsync AS systemd
ARG SBAT_DISTRO_VERSION

COPY --from=gperf /gperf/ /

COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /

COPY --from=python-build /python/ /

COPY --from=openssl /openssl/ /

COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /

COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /

COPY --from=readline /readline/ /

COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=pkgconfig /pkgconfig/ /

COPY --from=libseccomp /libseccomp/ /

COPY --from=dbus /dbus/ /

COPY --from=pam /pam/ /

COPY --from=kmod /kmod/ /

COPY --from=xz /xz/ /

COPY --from=libffi /libffi/ /

# Cryptsetup for systemd-cryptsetup
COPY --from=cryptsetup /cryptsetup/ /

# jsonc for cryptsetup
COPY --from=jsonc /jsonc/ /

# mapper for cryptsetup
COPY --from=lvm2 /lvm2/ /

COPY --from=tpm2-tss /tpm2-tss/ /

COPY --from=libucontext /libucontext/ /

COPY --from=sources-downloader /sources/downloads/systemd.tar.gz /sources/
WORKDIR /sources
RUN tar -xf systemd.tar.gz && mv systemd-* systemd
RUN mkdir -p /systemd
RUN python3 -m pip install meson ninja jinja2 pyelftools

WORKDIR /sources/systemd

RUN /usr/bin/meson setup buildDir \
      ${COMMON_MESON_FLAGS} \
      -D dbus=enabled  \
      -D tpm2=enabled          \
      -D pam=enabled \
      -D libcryptsetup=enabled  \
      -D kmod=enabled \
      -D seccomp=enabled         \
      -D default-dnssec=no    \
      -D firstboot=false      \
      -D sysusers=true -D install-tests=false  -D tests=false -D fuzz-tests=false \
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
      -Dsbat-distro-version="${SBAT_DISTRO_VERSION}"
RUN ninja -C buildDir
RUN DESTDIR=/systemd ninja -C buildDir install

FROM rsync AS dracut
ARG JOBS

COPY --from=pkgconfig /pkgconfig/ /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /

COPY --from=zstd /zstd/ /
COPY --from=zlib /zlib/ /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=openssl /openssl/ /
COPY --from=readline /readline/ /
COPY --from=kmod /kmod/ /
COPY --from=systemd /systemd/ /
COPY --from=fts /fts/ /
COPY --from=xz /xz/ /
COPY --from=libucontext /libucontext/ /

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
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=libaio /libaio/ /
COPY --from=readline /readline/ /
COPY --from=systemd /systemd/ /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=python-build  /python /python
RUN rsync -aHAX --keep-dirlinks  /python/. /
COPY --from=ca-certificates /ca-certificates/ /
COPY --from=openssl /openssl/ /
COPY --from=libucontext /libucontext/ /


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
COPY --from=pkgconfig /pkgconfig/ /
# devmapper
COPY --from=lvm2-systemd /lvm2/ /

COPY --from=libucontext /libucontext/ /

## get libudev from systemd
COPY --from=systemd /systemd/ /

## libaio for multipathd
COPY --from=libaio /libaio/ /

## json-c for multipathd
COPY --from=jsonc /jsonc/ /

## urcu for multipathd
COPY --from=urcu /urcu/ /

## util-linux for libmount.so
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /

## libcap
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=pax-utils /pax-utils/ /

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
COPY --from=expat /expat/ /
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=systemd /systemd/ /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=libucontext /libucontext/ /
COPY --from=sources-downloader /sources/downloads/dbus.tar.xz /sources/
# install target
RUN mkdir -p /dbus
WORKDIR /sources
RUN pip3 install meson ninja
RUN tar -xf dbus.tar.xz && mv dbus-* dbus
WORKDIR /sources/dbus
RUN meson setup buildDir ${COMMON_MESON_FLAGS}
RUN DESTDIR=/dbus ninja -j${JOBS} -C buildDir install

## final build of pam with systemd support
FROM python-build AS pam-systemd
ARG JOBS
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=openssl /openssl/ /
COPY --from=readline /readline/ /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=systemd /systemd/ /
COPY --from=libucontext /libucontext/ /
COPY --from=sources-downloader /sources/downloads/pam.tar.xz /sources/
RUN mkdir -p /pam
WORKDIR /sources
RUN tar -xf pam.tar.xz && mv Linux-PAM-* linux-pam
WORKDIR /sources/linux-pam
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS}
RUN DESTDIR=/pam ninja -j${JOBS} -C buildDir install
COPY files/pam/* /pam/etc/pam.d/
## We are using the pam_shells.so module in a few places, so we need a proper /etc/shells file
COPY files/shells /pam/etc/shells
RUN chmod 644 /pam/etc/shells

# Shadow with systemd support via PAM
FROM shadow-base AS shadow-systemd
ARG JOBS
COPY --from=pam-systemd /pam/ /
COPY --from=libucontext /libucontext/ /
COPY --from=systemd /systemd/ /
COPY --from=sources-downloader /sources/downloads/shadow.tar.xz /sources/
RUN mkdir -p /shadow
WORKDIR /sources
RUN tar -xf shadow.tar.xz && mv shadow-* shadow
WORKDIR /sources/shadow
RUN ./configure ${COMMON_CONFIGURE_ARGS} --sysconfdir=/etc --without-libbsd --disable-nls
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} exec_prefix=/usr pamddir= install DESTDIR=/shadow && make exec_prefix=/usr pamddir= -s -j${JOBS} -l${MAX_LOAD} install

FROM rsync AS sudo-base

COPY --from=pkgconfig /pkgconfig/ /
COPY --from=readline /readline/ /
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /
COPY --from=pax-utils /pax-utils/ /

FROM sudo-base AS sudo-systemd
ARG JOBS
COPY --from=pam-systemd /pam/ /
COPY --from=libucontext /libucontext/ /
COPY --from=sources-downloader /sources/downloads/sudo.tar.gz /sources/
RUN mkdir -p /sudo
WORKDIR /sources
RUN tar -xf sudo.tar.gz && mv sudo-* sudo
WORKDIR /sources/sudo
RUN ./configure ${COMMON_CONFIGURE_ARGS} --libexecdir=/usr/lib --with-pam --disable-nls --with-secure-path --with-env-editor --with-passprompt="[sudo] password for %p: "
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/sudo && make -s -j${JOBS} -l${MAX_LOAD} install

FROM sudo-base AS sudo
ARG JOBS
COPY --from=pam /pam/ /
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
COPY --from=cmake /cmake/ /
COPY --from=kmod /kmod/ /
COPY --from=xz /xz/ /
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /
COPY --from=systemd /systemd/ /
COPY --from=perl /perl/ /
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /
COPY --from=libucontext /libucontext/ /

COPY --from=sources-downloader /sources/downloads/openscsi.tar.gz /sources/
RUN pip3 install meson ninja
RUN mkdir -p /openscsi
WORKDIR /sources
RUN tar -xf openscsi.tar.gz && mv open-iscsi-* openscsi
WORKDIR /sources/openscsi
RUN meson setup buildDir ${COMMON_MESON_FLAGS} --optimization 3 -D isns=disabled
RUN DESTDIR=/openscsi ninja -j${JOBS} -C buildDir install && ninja -j${JOBS} -C buildDir install

FROM rsync AS bc
ARG JOBS
COPY --from=readline /readline/ /
COPY --from=sources-downloader /sources/downloads/bc.tar.xz /sources/
WORKDIR /sources
RUN tar -xf bc.tar.xz && mv bc-* bc
WORKDIR /sources/bc
RUN ./configure --prefix=/usr -G -Os -N
RUN make -s -j${JOBS} -l${MAX_LOAD} && make -s -j${JOBS} -l${MAX_LOAD} install DESTDIR=/bc

FROM rsync AS pcre2
ARG JOBS
WORKDIR /sources
COPY --from=sources-downloader /sources/downloads/pcre2.tar.gz /sources/
RUN tar -xf pcre2.tar.gz && mv pcre2-* pcre2
WORKDIR /sources/pcre2
RUN ./configure ${COMMON_CONFIGURE_ARGS} --enable-utf --enable-unicode-properties --disable-dependency-tracking
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} install DESTDIR=/pcre2

FROM python-build AS glib2
ARG JOBS
COPY --from=pcre2 /pcre2/ /
COPY --from=libffi /libffi/ /
WORKDIR /sources
COPY --from=sources-downloader /sources/downloads/glib.tar.xz /sources/
RUN tar -xf glib.tar.xz && mv glib-* glib
WORKDIR /sources/glib
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dselinux=disabled -Dxattr=false \
    -Dlibmount=disabled -Dman-pages=disabled -Ddtrace=disabled -Dsystemtap=disabled -Dsysprof=disabled \
    -Ddocumentation=false -Dtests=false -Dinstalled_tests=false -Dnls=disabled \
    -Dglib_debug=disabled -Dglib_assert=false -Dglib_checks=false -Dlibelf=disabled \
    -Dintrospection=disabled
RUN DESTDIR=/glib2 ninja -C buildDir install

FROM automake AS libmspack
ARG JOBS
COPY --from=libtool /libtool/ /
WORKDIR /sources
COPY --from=sources-downloader /sources/downloads/mspack.tar.gz /sources/
RUN tar -xf mspack.tar.gz && mv libmspack-* mspack
WORKDIR /sources/mspack/libmspack
RUN autoreconf -i -W all -v
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} install DESTDIR=/libmspack


# On cloud images, build and ship open-vm-tools and qemu-guest-agent
# qemu-ga — only the guest agent target
FROM python-build AS qemu-guest-agent
ARG JOBS
COPY --from=pcre2 /pcre2/ /
COPY --from=libffi /libffi/ /
COPY --from=glib2 /glib2/ /
COPY --from=flex /flex/ /
COPY --from=bison /bison/ /
WORKDIR /sources
RUN pip3 install meson ninja
COPY --from=sources-downloader /sources/downloads/qemu.tar.xz /sources/
RUN tar -xf qemu.tar.xz && mv qemu-* qemu
WORKDIR /sources/qemu
# --without-default-features flips every --enable-FEATURE off; we then only
# turn the guest agent back on. Net effect: no qemu-system-*, qemu-img,
# qemu-user, TCG, KVM, slirp, vnc, pixman, gnutls, etc. Anything pulled in
# transitively by qemu-ga (glib2, qemuutil, qapi-gen) is still built.
#
# No --cross-prefix / --host: each hadron-toolchain image is single-arch
# (one tag per arch — `hadron-toolchain:main-{amd64,arm64,riscv64}`), so
# qemu's configure sees a native build and uses plain `cc` / `strip` /
# `pkg-config`. (QEMU's configure ignores autotools-style --host anyway,
# and --cross-prefix would demand a full set of prefixed binutils that the
# toolchain image doesn't ship — the autotools stages above only get away
# with --host=${TARGET} because autotools uses the prefix as a *hint*.)
#
# --disable-install-blobs is NOT a feature flag (it lives in "Advanced
# options"), so --without-default-features doesn't kill it; left enabled
# qemu's meson probes for `bzip2` which the toolchain doesn't have.
#
# --enable-fdt=disabled prevents meson from git-cloning the dtc subproject
# when libfdt isn't on the system (it would always be missing here).
RUN ./configure \
      --prefix=/usr \
      --without-default-features --without-default-devices --disable-coroutine-pool \
      --disable-install-blobs \
      --enable-fdt=disabled \
      --enable-guest-agent --disable-tcg
RUN make -s -j${JOBS} qemu-ga
# Stage the binary + the upstream systemd unit into /output with the standard layout.
RUN install -Dm755 build/qga/qemu-ga /output/usr/bin/qemu-ga
RUN install -Dm644 contrib/systemd/qemu-guest-agent.service /output/usr/lib/systemd/system/qemu-guest-agent.service

# open-vm-tools
# requires python3 for some after-install scripts
FROM python-build AS open-vm-tools-build
ARG JOBS
COPY --from=pcre2 /pcre2/ /
COPY --from=libffi /libffi/ /
COPY --from=glib2 /glib2/ /
COPY --from=libmspack /libmspack/ /libmspack
RUN rsync -aHAX --keep-dirlinks  /libmspack/. /
COPY --from=libtool /libtool/ /
COPY --from=autoconf /autoconf/ /
COPY --from=automake /automake/ /
COPY --from=m4 /m4/ /
COPY --from=perl /perl/ /
COPY --from=pkgconfig /pkgconfig/ /
COPY --from=libtirpc /libtirpc/ /
# We need rpcgen from nfs-utils
COPY --from=nfs-utils /nfs-utils /nfs-utils
RUN rsync -aHAX --keep-dirlinks  /nfs-utils/. /
# Use proper patch as busybox one does not do proper fuzzing
COPY --from=patch /patch/ /
COPY --from=sources-downloader /sources/downloads/aports.tar.gz /sources/patches/
COPY --from=sources-downloader /sources/downloads/open-vm-tools.tar.gz /sources/
# extract the aport patch to apply to lvm2
WORKDIR /sources/patches
RUN tar -xf aports.tar.gz && mv aports-* aport
WORKDIR /sources/
RUN tar -xf open-vm-tools.tar.gz && mv open-vm-tools-* open-vm-tools
WORKDIR /sources/open-vm-tools
# Its patching time!
# we should really get with alpine and postmarketOS and try to push some of this patches upstream because this is a shame
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/0002-open-vm-tools-Add-disable-werror-configure-option.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/0003-Do-not-assume-that-linux-and-gnu-libc-are-the-same-t.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/0004-Use-configure-test-for-struct-timespec.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/0005-Fix-definition-of-ALLPERMS-and-ACCESSPERMS.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/0006-Use-configure-to-test-for-feature-instead-of-platfor.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/0007-Use-configure-test-for-sys-stat.h-include.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/0008-Rename-poll.h-to-vm_poll.h.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/0010-use-posix-strerror_r-unless-gnu.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/0011-use-off64_t-instead-of-loff_t.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/snprintf.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/strerror_r.patch
RUN patch -p1 < /sources/patches/aport/community/open-vm-tools/mock-res_ninit-and-res_nclose.patch

WORKDIR /sources/open-vm-tools/open-vm-tools
RUN autoreconf -if
# Patch vm tools to recognize Hadron
RUN sed -i '/#define STR_OS_ARCH/a\#define STR_OS_HADRON              "Hadron"' lib/include/guest_os.h
RUN sed -i '/{ "gentoo", *STR_OS_GENTOO, *HostinfoGenericSetShortName },/a\{ "hadron",              STR_OS_HADRON,             HostinfoGenericSetShortName },' lib/misc/hostinfoPosix.c
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-glibc-check --disable-multimon --without-gtk4 --without-gtk3 --without-fuse --without-dnet \
    --without-xerces --without-icu --without-kernel-modules --without-pam --disable-werror --disable-containerinfo --without-x
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} install DESTDIR=/output


# riscv64 currently skips open-vm-tools; keep /output so downstream COPY works
FROM scratch AS open-vm-tools-riscv64
WORKDIR /output

# Map build arches to the stage consumed by cloud-tools
FROM open-vm-tools-build AS open-vm-tools-amd64
FROM open-vm-tools-build AS open-vm-tools-arm64
FROM open-vm-tools-${TARGETARCH} AS open-vm-tools


FROM rsync AS cloud-tools
WORKDIR /tools
COPY --from=open-vm-tools /output /tools
COPY --from=qemu-guest-agent /output /tools
# Runtime deps
COPY --from=glib2 /glib2 /glib2
# Do some cleanup under glib2 before copying, we just need the runtime stuff, not binaries and headers and whatnot
# /usr/local/include provides headers
# /usr/local/bin provides several glib binaries that we dont need for now
RUN rm -Rf /glib2/usr/local/include /glib2/usr/local/bin /glib2/usr/local/libexec
RUN rsync -aHAX --keep-dirlinks  /glib2/. /tools
COPY --from=libffi /libffi /libffi
RUN rsync -aHAX --keep-dirlinks  /libffi/. /tools
COPY --from=pcre2 /pcre2 /pcre2
RUN rsync -aHAX --keep-dirlinks  /pcre2/. /tools

# In default images (no cloud) we dont add any extra tools for now)
FROM scratch AS default-tools
# create the dir at least so the copy doesnt fail
WORKDIR /tools
# no-op

# Target to copy from
FROM ${KERNEL_TYPE}-tools AS extra-tools
# no-op

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

# Base skeleton
COPY --from=skeleton /sysroot /merge

# Now prepare a merged directory with all the built tools
COPY --from=busybox /sysroot /busybox
RUN rsync -aHAX --keep-dirlinks  /busybox/. /merge
COPY --from=cmake /cmake/ /merge/
COPY --from=kmod /kmod/ /merge/
COPY --from=xz /xz/ /merge/
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /merge
COPY --from=systemd /systemd/ /merge/
COPY --from=perl /perl/ /merge/
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /merge
COPY --from=pam-systemd /pam/ /merge/
COPY --from=pkgconfig /pkgconfig/ /merge/
COPY --from=readline /readline/ /merge/
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /merge
COPY --from=pax-utils /pax-utils/ /merge/
COPY --from=readline /readline/ /merge/
COPY --from=openssl /openssl/ /merge/
COPY --from=bison /bison/ /merge/
COPY --from=flex /flex/ /merge/
COPY --from=m4 /m4/ /merge/
COPY --from=lvm2-systemd /lvm2/ /merge/
COPY --from=gawk /gawk/ /merge/
COPY --from=jsonc /jsonc/ /merge/
COPY --from=libaio /libaio/ /merge/
COPY --from=coreutils /coreutils /coreutils
RUN rsync -aHAX --keep-dirlinks  /coreutils/. /merge
COPY --from=expat /expat/ /merge/
COPY --from=zlib /zlib/ /merge/
COPY --from=zstd /zstd/ /merge/
COPY --from=fts /fts/ /merge/
COPY --from=autoconf /autoconf/ /merge/
COPY --from=automake /automake/ /merge/
COPY --from=pkgconfig /pkgconfig/ /merge/
COPY --from=libseccomp /libseccomp/ /merge/
COPY --from=dbus /dbus/ /merge/
COPY --from=python-build /python/ /merge/
COPY --from=acl /acl/ /merge/
COPY --from=ca-certificates /ca-certificates/ /merge/
COPY --from=curl /curl/ /merge/
COPY --from=rsync /rsync/ /merge/
COPY --from=gcc-stage0 /sysroot /gcc
RUN rsync -aHAX --keep-dirlinks /gcc/. /merge
COPY --from=musl-stage0 /sysroot /musl
RUN rsync -aHAX --keep-dirlinks /musl/. /merge
COPY --from=make-stage0 /sysroot /make
RUN rsync -aHAX --keep-dirlinks /make/. /merge
COPY --from=binutils-stage0 /sysroot /binutils
RUN rsync -aHAX --keep-dirlinks /binutils/. /merge
COPY --from=attr /attr/ /merge/
COPY --from=busybox /sysroot /busybox
RUN rsync -aHAX --keep-dirlinks  /busybox/. /merge
COPY --from=libffi /libffi/ /merge/
COPY --from=lz4 /lz4/ /merge/
COPY --from=xxhash /xxhash/ /merge/
COPY --from=libxml /libxml/ /merge/
COPY --from=grep /grep/ /merge/
COPY --from=diffutils /diffutils/ /merge/
## Kernel but only the headers
COPY --from=kernel-headers /linux-headers/ /linux-headers
RUN rsync -aHAX --keep-dirlinks  /linux-headers/. /merge/usr/
COPY --from=findutils /findutils/ /merge/
COPY --from=gzip /gzip/ /merge/
COPY --from=shadow-systemd /shadow/ /merge/
COPY --from=libtool /libtool/ /merge/
COPY --from=patch /patch/ /merge/

COPY --from=kernel-misc /output /merge/usr/share/kernel-misc
COPY --from=bc /bc /merge
COPY --from=libelf /libelf /merge
COPY --from=tpm2-tss /tpm2-tss /merge
COPY --from=hadron-splash /hadron-splash/hadron-splash /merge/bin/hadron-splash

FROM scratch AS toolchain
ARG VERSION
# These are the default values for the toolchain
# Set them so anything using the toolchain will use the default values
ARG VENDOR="hadron"
ENV VENDOR=${VENDOR}
ARG ARCH="x86-64"
ENV ARCH=${ARCH}
ARG BUILD_ARCH="x86_64"
ENV BUILD_ARCH=${BUILD_ARCH}
ENV TARGET=${BUILD_ARCH}-${VENDOR}-linux-musl
ENV BUILD=${BUILD_ARCH}-pc-linux-musl
ENV COMMON_CONFIGURE_ARGS="--quiet --prefix=/usr --host=${TARGET} --build=${TARGET} --enable-lto --enable-shared --disable-static"
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
RUN ln -s /usr/bin/gcc /usr/bin/cc
## Symlink ld-musl-$ARCH.so to /bin/ldd to provide ldd functionality
RUN if [ "${BUILD_ARCH}" == "aarch64" ]; then \
    ln -s /lib/ld-musl-aarch64.so.1 /bin/ldd; \
    elif [ "${BUILD_ARCH}" == "riscv64" ]; then \
    ln -s /lib/ld-musl-riscv64.so.1 /bin/ldd; \
    else \
    ln -s /lib/ld-musl-x86_64.so.1 /bin/ldd; \
    fi
RUN echo "VERSION_ID=\"${VERSION}\"" >> /etc/os-release
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
COPY --from=curl /curl/ /skeleton/

## ca-certificates
COPY --from=ca-certificates /ca-certificates/ /skeleton/

## bash
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /skeleton/

## readline
COPY --from=readline /readline/ /skeleton/

## acl
COPY --from=acl /acl/ /skeleton/

## attr
COPY --from=attr /attr/ /skeleton/

## findutils
COPY --from=findutils /findutils/ /skeleton/

## grep
COPY --from=grep /grep/ /skeleton/

## zstd
COPY --from=zstd /zstd/ /skeleton/

## libz
COPY --from=zlib /zlib/ /skeleton/

## libcap
COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /skeleton/

## util-linux
COPY --from=util-linux /util-linux /util-linux
RUN rsync -aHAX --keep-dirlinks  /util-linux/. /skeleton/

## libexpat
COPY --from=expat /expat/ /skeleton/

## libaio for io asynchronous operations
COPY --from=libaio /libaio/ /skeleton/

## rsync
COPY --from=rsync /rsync/ /skeleton/

COPY --from=lz4 /lz4/ /skeleton/

## xxhash needed by rsync
COPY --from=xxhash /xxhash/ /skeleton/

## kbd for loadkeys support
COPY --from=kbd /kbd/ /skeleton/

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
COPY --from=openssl /openssl/ /skeleton/

COPY --from=hadron-splash /hadron-splash/hadron-splash /skeleton/bin/hadron-splash

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
# ------------------------------------------------------------------------------
# Component version manifest
# Parses the `ARG *_VERSION=` defaults from this very Dockerfile and emits a flat
# `{ "name": "version" }` JSON per shipped image. The version map is intersected
# with the packages each image's merge stages actually `COPY --from`, so each
# image gets an accurate, per-image component list. Self-contained: generated at
# build time from the Dockerfile itself (single source of truth, no host step).
#
# The full-image stage list is variant-aware: `full-image-merge-${FIPS}` selects
# the fips/no-fips merge (fips adds libkcapi) and `full-image-pre-${BOOTLOADER}`
# selects the grub/systemd path (grub adds dracut). This keeps the manifest in
# step with what each FIPS/BOOTLOADER build actually ships.
# Output is consumed by `container` and `full-image-final` below.
# ------------------------------------------------------------------------------
FROM alpine-base AS components
ARG FIPS
ARG BOOTLOADER
COPY Dockerfile /src/Dockerfile
COPY hack/gen-components.sh /src/hack/gen-components.sh
# In fips builds the shipped `openssl` is the `FROM openssl-${FIPS} AS openssl`
# alias built from the FIPS sources (OPENSSL_FIPS_VERSION), not OPENSSL_VERSION —
# same component name, different version. --override reflects that.
RUN cd /src && \
    OVERRIDE=""; [ "${FIPS}" = "fips" ] && OVERRIDE="--override openssl=OPENSSL_FIPS_VERSION"; \
    sh hack/gen-components.sh --shipped "stage2-merge" \
       --format flat --name container --out-dir /out && \
    sh hack/gen-components.sh \
       --shipped "stage2-merge full-image-merge-base full-image-merge-${FIPS} full-image-pre-${BOOTLOADER} full-image-pre-preset full-image-final" \
       ${OVERRIDE} --format flat --name full-image --out-dir /out

FROM scratch AS container
ARG VERSION
COPY --from=stage2-merge /skeleton /
SHELL ["/bin/bash", "-c"]
## Link sh to bash
RUN ln -s /bin/bash /bin/sh
## Symlink ld-musl-$ARCH.so to /bin/ldd to provide ldd functionality
RUN if [ "${ARCH}" == "aarch64" ]; then \
    ln -s /lib/ld-musl-aarch64.so.1 /bin/ldd; \
    elif [ "${ARCH}" == "riscv64" ]; then \
    ln -s /lib/ld-musl-riscv64.so.1 /bin/ldd; \
    else \
    ln -s /lib/ld-musl-x86_64.so.1 /bin/ldd; \
    fi
# Set the version here as otherwise its easy to invalidate the cache with a version change
RUN echo "VERSION_ID=\"${VERSION}\"" >> etc/os-release
# Per-image component manifest (late layer: only busts when a shipped version changes)
COPY --from=components /out/container.json /usr/lib/hadron/components.json
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

# full-image-merge-base is where we prepare stuff for the final image
# more complete, this has systemd, sudo, openssh, iptables, kernel, etc..
FROM alpine-base AS full-image-merge-base

COPY --from=openssl /openssl/ /skeleton/

## openssh
COPY --from=openssh /openssh/ /skeleton/

# kernel and modules
COPY --from=kernel /kernel/ /skeleton/boot/
COPY --from=kernel-modules /modules/lib/modules/ /skeleton/lib/modules

COPY --from=sudo-systemd /sudo/ /skeleton/

# Iptables is needed to support k8s
COPY --from=iptables /iptables/ /skeleton/

# For iptables-nft backend
COPY --from=libmnl /libmnl/ /skeleton/
COPY --from=libnftnl /libnftnl/ /skeleton/

## conntrack-tools (conntrack + conntrackd) for k8s/kube-proxy; baremetal-only, not in container base
COPY --from=libnfnetlink /libnfnetlink/ /skeleton/
COPY --from=libnetfilter_conntrack /libnetfilter_conntrack/ /skeleton/
COPY --from=libnetfilter_cttimeout /libnetfilter_cttimeout/ /skeleton/
COPY --from=libnetfilter_cthelper /libnetfilter_cthelper/ /skeleton/
COPY --from=libnetfilter_queue /libnetfilter_queue/ /skeleton/
COPY --from=conntrack-tools /conntrack-tools/ /skeleton/

## sysctl(8) CLI from procps-ng (final image only, not container base)
COPY --from=procps-ng /procps-ng/ /skeleton/

## cryptsetup for encrypted partitions
COPY --from=cryptsetup /cryptsetup/ /skeleton/

## jsonc needed by libcryptsetup
COPY --from=jsonc /jsonc/ /skeleton/

# device-mapper from lvm2
COPY --from=lvm2-systemd /lvm2/ /skeleton/

COPY --from=multipath-tools /multipath-tools/ /skeleton/
## Use mount and cp to preserv symlinks, otherwise if we copy directly
## we will resolve the symlinks and copy the real files multiple times
## Copy libgcc_s.so.1 for multipathd deps
RUN --mount=from=gcc-stage0,src=/sysroot/usr/lib,dst=/mnt,ro mkdir -p /skeleton/usr/lib && cp -a /mnt/libgcc_s.so* /skeleton/usr/lib/

COPY --from=e2fsprogs /e2fsprogs/ /skeleton/

## NFS client userspace. Required by Longhorn RWX and any other in-cluster
## NFS storage. The nfs-utils build stage trims its install to the
## client-only binaries we actually use, so the runtime deps reduce to
## libtirpc (mount.nfs) and libkeyutils (nfsidmap).
COPY --from=libtirpc /libtirpc/ /skeleton/

COPY --from=keyutils /keyutils/ /skeleton/

COPY --from=nfs-utils /nfs-utils/ /skeleton/

COPY --from=libucontext /libucontext/ /skeleton/

## systemd
COPY --from=systemd /systemd/ /skeleton/

## dbus
COPY --from=dbus-systemd /dbus/ /skeleton/

## seccomp
COPY --from=libseccomp /libseccomp/ /skeleton/

# copy pam but with systemd support
COPY --from=pam-systemd /pam/ /skeleton/

# copy shadow but with systemd support
COPY --from=shadow-systemd /shadow/ /skeleton/

# copy iscsi
COPY --from=openscsi /openscsi/ /skeleton/

# kmod needed by openscsi
COPY --from=kmod /kmod/ /skeleton/

# lzma needed by openscsi
COPY --from=xz /xz/ /skeleton/

COPY --from=tpm2-tss /tpm2-tss/ /skeleton/

COPY --from=libcap /libcap/ /skeleton/

COPY --from=extra-tools /tools/ /skeleton/

# Clean m4 leftover files if any, they are not used in runtime
RUN find /skeleton -type f -name '*.m4' -delete

# Strip binaries
RUN find /skeleton -type f ! -name 'fips.so' -print0 | xargs -0 scanelf --nobanner --osabi --etype "ET_DYN,ET_EXEC" --format "%F" | xargs -r strip --strip-unneeded


# Remove python artifacts
RUN find /skeleton -name "*.pyc" -delete
RUN find /skeleton -name "__pycache__" -type d -exec rm -rf {} +


FROM full-image-merge-base AS full-image-merge-no-fips
# Non-FIPS crypto hardening for sshd. The FIPS variant ships 100-hadron-fips.conf
# instead; exactly one 100-* crypto drop-in is present per image so neither can
# override the other (sshd is first-value-wins for Ciphers/MACs/KexAlgorithms).
COPY files/ssh/sshd_config.d/100-hadron-crypto.conf /skeleton/etc/ssh/sshd_config.d/100-hadron-crypto.conf

FROM full-image-merge-base AS full-image-merge-fips
COPY --from=libkcapi /libkcapi/ /skeleton/
COPY files/ssh/sshd_config.d/100-hadron-fips.conf /skeleton/etc/ssh/sshd_config.d/100-hadron-fips.conf


FROM full-image-merge-${FIPS} AS full-image-merge

## This target will assemble dracut and all its dependencies into the skeleton
FROM stage0 AS dracut-final
RUN apk add rsync pax-utils

## kmod for modprobe, insmod, lsmod, modinfo, rmmod. Draut depends on this
COPY --from=kmod /kmod/ /skeleton/

## fts library, dracut depends on this
COPY --from=fts /fts/ /skeleton/

## xz and liblzma, dracut depends on this
COPY --from=xz /xz/ /skeleton/

## lz4, dracut depends on this if mixed with systemd
COPY --from=lz4 /lz4/ /skeleton/

## gawk for dracut
COPY --from=gawk /gawk/ /skeleton/

## grub
COPY --from=grub-efi /grub-efi/ /skeleton/

COPY --from=grub-bios /grub-bios/ /skeleton/

COPY --from=shim /shim/ /skeleton/

## Dracut
COPY --from=dracut /dracut/ /skeleton/

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
# Split before systemctl preset-all: QEMU cannot run that step reliably (SIGSEGV).
# CI builds full-image-pre-preset on x86, pushes OCI, then native riscv64 imports it
# via buildx --build-context full-image-pre-preset=docker-image://… for full-image-final.
FROM full-image-${BOOTLOADER} AS full-image-pre-preset
SHELL ["/bin/bash", "-c"]
ARG VERSION
ARG BUILD_ARCH
## Cleanup first
# We don't need headers
RUN rm -rf /RUN tree /skeleton usr/include
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
RUN rm -rf /usr/local/share/bash-completion
# Remove gdb debug files
RUN rm -rf /usr/share/gdb/
RUN rm -rf /usr/local/share/gdb/
# Remove glib2 extra leftovers
RUN rm -rf /usr/local/share/glib-2.0
RUN rm -rf /usr/local/lib/glib-2.0/include/
RUN rm -rf /usr/local/share/gettext/its
# remove vmware translations
RUN rm -rf /usr/share/open-vm-tools/messages
# Remove cmake leftovers
RUN rm -rf /usr/lib/cmake/
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
RUN busybox --install
# mkfs.fat is a script that calls mkfs.vfat busybox applet with the proper name and pass all args for compatibility
RUN echo -e '#!/bin/sh\nexec /bin/mkfs.vfat "$@"\n' > /bin/mkfs.fat && chmod +x /bin/mkfs.fat

FROM full-image-pre-preset AS full-image-final
SHELL ["/bin/bash", "-c"]
ARG VERSION
ARG BUILD_ARCH
# preset all systemd services (native riscv64 in CI; crashes under QEMU)
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
# Add modprobe configs (currently only the dirtyfrag mitigation, see the file
# for details). Remove the dirtyfrag.conf once the upstream kernel is patched.
COPY files/modprobe.d/* /etc/modprobe.d/
# copy a new login.defs to have better defaults as some stuff is already done by shadow and pam
COPY files/login.defs /etc/login.defs
# STIG-hardening sshd drop-in (all images; carries NO crypto keywords so it never
# pre-empts the 100-* crypto drop-in in FIPS builds — see the file header).
COPY files/ssh/sshd_config.d/99-hadron-stig.conf /etc/ssh/sshd_config.d/99-hadron-stig.conf
## Remove users stuff
RUN rm -f /etc/passwd /etc/shadow /etc/group /etc/gshadow
## Override root shell to /bin/bash (systemd basic.conf default is /bin/sh); /etc/sysusers.d/ wins over /usr/lib/sysusers.d/
COPY files/systemd/00-root.conf /etc/sysusers.d/00-root.conf
## Create any missing users from scratch
RUN systemd-sysusers
## Firmware lives at /usr/local/lib/firmware so it is sysext-compatible and can
## be overridden by a persistent-partition mount; /lib/firmware is a symlink
## into it so the kernel's default fw search path still resolves. Additive
## composers (COPY --from=<fw> / /) can drop files at /usr/local/lib/firmware/*
## without hitting the "cannot copy to non-directory" buildkit error you get
## when the real directory sits under /lib/firmware and /usr/local is the link.
RUN rm -rf /lib/firmware && \
    mkdir -p /usr/local/lib/firmware && \
    ln -s /usr/local/lib/firmware /lib/firmware
## Symlink ld-musl-$ARCH.so to /bin/ldd to provide ldd functionality
RUN rm /bin/ldd
RUN if [ "${BUILD_ARCH}" == "aarch64" ]; then \
    ln -s /lib/ld-musl-aarch64.so.1 /bin/ldd; \
    elif [ "$BUILD_ARCH" == "riscv64" ]; then \
    ln -s /lib/ld-musl-riscv64.so.1 /bin/ldd; \
    else \
    ln -s /lib/ld-musl-x86_64.so.1 /bin/ldd; \
    fi
# Per-image component manifest (late layer: only busts when a shipped version changes)
COPY --from=components /out/full-image.json /usr/lib/hadron/components.json

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
