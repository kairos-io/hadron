## This is Dockerfile, that at the end of the process it builds a 
## small LFS system, starting from Alpine Linux.
## It uses mussel to build the system.

FROM alpine AS stage0

########################################################
#
# Stage 0 - building the cross-compiler
#
########################################################

ARG VENDOR="ukairos"
ENV VENDOR=${VENDOR}
ARG ARCH="x86-64"
ENV ARCH=${ARCH}
ARG BUILD_ARCH="x86_64"
ENV BUILD_ARCH=${BUILD_ARCH}
ARG JOBS=8
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
### This is needed to download packages via https when we don't still have wget/curl with ssl support
FROM stage0 AS sources-downloader

ARG CURL_VERSION=8.5.0
ENV CURL_VERSION=${CURL_VERSION}

RUN mkdir -p /sources/downloads && cd /sources/downloads && wget https://curl.se/download/curl-${CURL_VERSION}.tar.gz 

ARG RSYNC_VERSION=3.4.1
ENV RSYNC_VERSION=${RSYNC_VERSION}

RUN cd /sources/downloads && wget https://download.samba.org/pub/rsync/rsync-${RSYNC_VERSION}.tar.gz

ARG XXHASH_VERSION=0.8.3
ENV XXHASH_VERSION=${XXHASH_VERSION}

RUN cd /sources/downloads && wget https://github.com/Cyan4973/xxHash/archive/refs/tags/v${XXHASH_VERSION}.tar.gz -O xxHash-${XXHASH_VERSION}.tar.gz

ARG ZSTD_VERSION=1.5.7
ENV ZSTD_VERSION=${ZSTD_VERSION}

RUN cd /sources/downloads && wget https://github.com/facebook/zstd/archive/v${ZSTD_VERSION}.tar.gz -O zstd-${ZSTD_VERSION}.tar.gz

ARG LZ4_VERSION=1.10.0
ENV LZ4_VERSION=${LZ4_VERSION}

RUN cd /sources/downloads && wget https://github.com/lz4/lz4/archive/v${LZ4_VERSION}.tar.gz -O lz4-${LZ4_VERSION}.tar.gz

ARG ZLIB_VERSION=1.3.1
ENV ZLIB_VERSION=${ZLIB_VERSION}

RUN cd /sources/downloads && wget https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz -O zlib-${ZLIB_VERSION}.tar.gz

ARG ACL_VERSION=2.3.2
ENV ACL_VERSION=${ACL_VERSION}

RUN cd /sources/downloads && wget https://download.savannah.gnu.org/releases/acl/acl-${ACL_VERSION}.tar.gz -O acl-${ACL_VERSION}.tar.gz

ARG ATTR_VERSION=2.5.2
ENV ATTR_VERSION=${ATTR_VERSION}

RUN cd /sources/downloads && wget https://download.savannah.nongnu.org/releases/attr/attr-${ATTR_VERSION}.tar.gz -O attr-${ATTR_VERSION}.tar.gz

ARG GAWK_VERSION=5.3.2
ENV GAWK_VERSION=${GAWK_VERSION}

RUN cd /sources/downloads && wget https://ftpmirror.gnu.org/gawk/gawk-${GAWK_VERSION}.tar.xz -O gawk-${GAWK_VERSION}.tar.xz

ARG CA_CERTIFICATES_VERSION=20250619
ENV CA_CERTIFICATES_VERSION=${CA_CERTIFICATES_VERSION}

RUN cd /sources/downloads && wget https://gitlab.alpinelinux.org/alpine/ca-certificates/-/archive/${CA_CERTIFICATES_VERSION}/ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2 -O ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2

ARG SYSTEMD_VERSION=257.8
ENV SYSTEMD_VERSION=${SYSTEMD_VERSION}

RUN cd /sources/downloads && wget https://github.com/systemd/systemd/archive/refs/tags/v${SYSTEMD_VERSION}.tar.gz -O systemd-${SYSTEMD_VERSION}.tar.gz

## systemd patches
RUN apk add git patch

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

RUN cd /sources/downloads && wget https://kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-${LIBCAP_VERSION}.tar.xz -O libcap-${LIBCAP_VERSION}.tar.xz

ARG UTIL_LINUX_VERSION=2.41.1
ARG UTIL_LINUX_VERSION_MAJOR=2.41
ENV UTIL_LINUX_VERSION=${UTIL_LINUX_VERSION}

RUN cd /sources/downloads && wget https://www.kernel.org/pub/linux/utils/util-linux/v${UTIL_LINUX_VERSION_MAJOR}/util-linux-${UTIL_LINUX_VERSION}.tar.xz -O util-linux-${UTIL_LINUX_VERSION}.tar.xz

ARG PYTHON_VERSION=3.12.11
ENV PYTHON_VERSION=${PYTHON_VERSION}
RUN cd /sources/downloads && wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz -O Python-${PYTHON_VERSION}.tar.xz

ARG SQLITE3_VERSION=3500400
ENV SQLITE3_VERSION=${SQLITE3_VERSION}

RUN cd /sources/downloads && wget https://www.sqlite.org/2025/sqlite-autoconf-${SQLITE3_VERSION}.tar.gz -O sqlite-autoconf-${SQLITE3_VERSION}.tar.gz

ARG OPENSSL_VERSION=3.5.2
ENV OPENSSL_VERSION=${OPENSSL_VERSION}
RUN cd /sources/downloads && wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz 

ARG PKGCONFIG_VERSION=1.8.1
ENV PKGCONFIG_VERSION=${PKGCONFIG_VERSION}
RUN cd /sources/downloads && wget https://distfiles.dereferenced.org/pkgconf/pkgconf-${PKGCONFIG_VERSION}.tar.xz

ARG DBUS_VERSION=1.16.2
RUN cd /sources/downloads && wget https://dbus.freedesktop.org/releases/dbus/dbus-${DBUS_VERSION}.tar.xz && mv dbus-${DBUS_VERSION}.tar.xz dbus.tar.xz

ARG EXPAT_VERSION=2.7.3
ARG EXPAT_VERSION_MAJOR=2
ARG EXPAT_VERSION_MINOR=7
ARG EXPAT_VERSION_PATCH=3
# expat
RUN cd /sources/downloads && wget https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION_MAJOR}_${EXPAT_VERSION_MINOR}_${EXPAT_VERSION_PATCH}/expat-${EXPAT_VERSION}.tar.gz && mv expat-2.7.3.tar.gz expat.tar.gz

ARG SECCOMP_VERSION=2.6.0
# seccomp
RUN cd /sources/downloads && wget https://github.com/seccomp/libseccomp/releases/download/v${SECCOMP_VERSION}/libseccomp-${SECCOMP_VERSION}.tar.gz && mv libseccomp-${SECCOMP_VERSION}.tar.gz libseccomp.tar.gz

ARG STRACE_VERSION=6.16
RUN cd /sources/downloads && wget https://strace.io/files/${STRACE_VERSION}/strace-${STRACE_VERSION}.tar.xz && mv strace-${STRACE_VERSION}.tar.xz strace.tar.xz

ARG KBD_VERSION=2.9.0
RUN cd /sources/downloads && wget https://www.kernel.org/pub/linux/utils/kbd/kbd-${KBD_VERSION}.tar.gz && mv kbd-${KBD_VERSION}.tar.gz kbd.tar.gz

ARG IPTABLES_VERSION=1.8.11
RUN cd /sources/downloads && wget https://www.netfilter.org/projects/iptables/files/iptables-${IPTABLES_VERSION}.tar.xz && mv iptables-${IPTABLES_VERSION}.tar.xz iptables.tar.xz

ARG LIBMNL_VERSION=1.0.5
RUN cd /sources/downloads && wget https://www.netfilter.org/projects/libmnl/files/libmnl-${LIBMNL_VERSION}.tar.bz2 && mv libmnl-${LIBMNL_VERSION}.tar.bz2 libmnl.tar.bz2

ARG LIBNFTNL_VERSION=1.3.0
RUN cd /sources/downloads && wget https://www.netfilter.org/projects/libnftnl/files/libnftnl-${LIBNFTNL_VERSION}.tar.xz && mv libnftnl-${LIBNFTNL_VERSION}.tar.xz libnftnl.tar.xz

## kernel
ARG KERNEL_VERSION=6.16.7
ENV KERNEL_VERSION=${KERNEL_VERSION}
RUN cd /sources/downloads && wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz

## flex

ARG FLEX_VERSION=2.6.4
ENV FLEX_VERSION=${FLEX_VERSION}
RUN cd /sources/downloads && wget https://github.com/westes/flex/releases/download/v${FLEX_VERSION}/flex-${FLEX_VERSION}.tar.gz

## bison

ARG BISON_VERSION=3.8.2
ENV BISON_VERSION=${BISON_VERSION}
RUN cd /sources/downloads && wget https://ftpmirror.gnu.org/bison/bison-${BISON_VERSION}.tar.xz


## argp-standalone

ARG ARGP_STANDALONE_VERSION=1.3
ENV ARGP_STANDALONE_VERSION=${ARGP_STANDALONE_VERSION}
RUN cd /sources/downloads && wget http://www.lysator.liu.se/~nisse/misc/argp-standalone-${ARGP_STANDALONE_VERSION}.tar.gz

## autoconf

ARG AUTOCONF_VERSION=2.71
ENV AUTOCONF_VERSION=${AUTOCONF_VERSION}
RUN cd /sources/downloads && wget https://ftpmirror.gnu.org/autoconf/autoconf-${AUTOCONF_VERSION}.tar.xz

## automake

ARG AUTOMAKE_VERSION=1.18.1
ENV AUTOMAKE_VERSION=${AUTOMAKE_VERSION}
RUN cd /sources/downloads && wget https://ftpmirror.gnu.org/automake/automake-${AUTOMAKE_VERSION}.tar.xz

## fts

ARG FTS_VERSION=1.2.7
ENV FTS_VERSION=${FTS_VERSION}
RUN cd /sources/downloads && wget https://github.com/pullmoll/musl-fts/archive/v${FTS_VERSION}.tar.gz -O musl-fts-${FTS_VERSION}.tar.gz

## libtool

ARG LIBTOOL_VERSION=2.5.4
ENV LIBTOOL_VERSION=${LIBTOOL_VERSION}
RUN cd /sources/downloads && wget https://ftpmirror.gnu.org/libtool/libtool-${LIBTOOL_VERSION}.tar.xz

## musl-obstack
ARG MUSL_OBSTACK_VERSION=1.2.3
ENV MUSL_OBSTACK_VERSION=${MUSL_OBSTACK_VERSION}
RUN cd /sources/downloads && wget https://github.com/void-linux/musl-obstack/archive/v${MUSL_OBSTACK_VERSION}.tar.gz -O musl-obstack-${MUSL_OBSTACK_VERSION}.tar.gz

## elfutils

ARG ELFUTILS_VERSION=0.193
ENV ELFUTILS_VERSION=${ELFUTILS_VERSION}
RUN cd /sources/downloads && wget https://sourceware.org/elfutils/ftp/${ELFUTILS_VERSION}/elfutils-${ELFUTILS_VERSION}.tar.bz2

RUN cd /sources/downloads && mkdir -p elfutils-patches && wget https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/main/elfutils/musl-macros.patch -O elfutils-patches/musl-macros.patch

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

RUN mkdir /sources && \
   cd /sources && \
   wget https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 

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

RUN wget http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz && \
    tar -xf musl-${MUSL_VERSION}.tar.gz && \
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
RUN wget http://mirror.netcologne.de/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
RUN wget http://mirror.netcologne.de/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2
RUN wget http://mirror.netcologne.de/gnu/mpc/mpc-${MPC_VERSION}.tar.gz
RUN wget http://mirror.netcologne.de/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2
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

RUN mkdir /sources && \
   cd /sources && \
   wget https://mirror.netcologne.de/gnu/make/make-${MAKE_VERSION}.tar.gz

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

RUN <<EOT bash
    wget http://mirror.easyname.at/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz
    tar -xf binutils-${BINUTILS_VERSION}.tar.xz
EOT

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
FROM alpine AS alpine-hack
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
## END of HACK

FROM scratch AS stage1

ARG VENDOR="ukairos"
ARG ARCH="x86-64"
ARG BUILD_ARCH="x86_64"
ENV VENDOR=${VENDOR}
ENV BUILD_ARCH=${BUILD_ARCH}
ENV TARGET=${BUILD_ARCH}-${VENDOR}-linux-musl
ENV BUILD=${BUILD_ARCH}-pc-linux-musl
ENV COMMON_ARGS="--prefix=/usr --host=${TARGET} --build=${BUILD}"

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

RUN wget http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz && \
    tar -xf musl-${MUSL_VERSION}.tar.gz && \
    cd musl-${MUSL_VERSION} && \
    ./configure \
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
    cd pkgconfig && mkdir -p /pkgconfig && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr --sysconfdir=/etc \
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

RUN mkdir -p /sources && cd /sources && tar -xf xxHash-${XXHASH_VERSION}.tar.gz && mv xxHash-${XXHASH_VERSION} xxhash && \
    tar -xf xxHash-${XXHASH_VERSION}.tar.gz && mv xxHash-${XXHASH_VERSION} xxhash && \
    cd xxhash && mkdir -p /xxhash && CC=gcc make -s -j${JOBS} DESTDIR=/xxhash && \
    make -s -j${JOBS} DESTDIR=/xxhash install && make -s -j${JOBS} install

## zstd
FROM xxhash AS zstd

ARG ZSTD_VERSION=1.5.7
ENV ZSTD_VERSION=${ZSTD_VERSION}

COPY --from=sources-downloader /sources/downloads/zstd-${ZSTD_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf zstd-${ZSTD_VERSION}.tar.gz && mv zstd-${ZSTD_VERSION} zstd && \
    cd zstd && mkdir -p /zstd && CC=gcc make -s -j${JOBS} DESTDIR=/zstd && \
    make -s -j${JOBS} DESTDIR=/zstd install && make -s -j${JOBS} install

## lz4
FROM zstd AS lz4

ARG LZ4_VERSION=1.10.0
ENV LZ4_VERSION=${LZ4_VERSION}

COPY --from=sources-downloader /sources/downloads/lz4-${LZ4_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf lz4-${LZ4_VERSION}.tar.gz && mv lz4-${LZ4_VERSION} lz4 && \
    cd lz4 && mkdir -p /lz4 && CC=gcc make -s -j${JOBS} PREFIX="/usr" DESTDIR=/lz4 && \
    make -s -j${JOBS} DESTDIR=/lz4 install && make -s -j${JOBS} install

## attr
FROM lz4 AS attr

ARG ATTR_VERSION=2.5.2
ENV ATTR_VERSION=${ATTR_VERSION}

COPY --from=sources-downloader /sources/downloads/attr-${ATTR_VERSION}.tar.gz /sources/
COPY ./patches/attr/basename.patch /sources/

RUN mkdir -p /sources && cd /sources && tar -xf attr-${ATTR_VERSION}.tar.gz && mv attr-${ATTR_VERSION} attr && \
    cd attr && mkdir -p /attr && \
    patch -p1 < /sources/basename.patch && \
    ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --localstatedir=/var \
    --disable-nls && make -s -j${JOBS} DESTDIR=/attr && \
    make -s -j${JOBS} DESTDIR=/attr install && make -s -j${JOBS} install

## acl
FROM attr AS acl

ARG ACL_VERSION=2.3.2
ENV ACL_VERSION=${ACL_VERSION}

COPY --from=sources-downloader /sources/downloads/acl-${ACL_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf acl-${ACL_VERSION}.tar.gz && mv acl-${ACL_VERSION} acl && \
    tar -xf acl-${ACL_VERSION}.tar.gz && mv acl-${ACL_VERSION} acl && \
    cd acl && mkdir -p /acl && ./configure --quiet ${COMMON_ARGS} --prefix=/usr --disable-dependency-tracking --libexecdir=/usr/libexec && make -s -j${JOBS} DESTDIR=/acl && \
    make -s -j${JOBS} DESTDIR=/acl install && make -s -j${JOBS} install

## popt
FROM acl AS popt

ARG POPT_VERSION=1.19
ENV POPT_VERSION=${POPT_VERSION}

RUN mkdir -p /sources && cd /sources && wget http://ftp.rpm.org/popt/releases/popt-1.x/popt-${POPT_VERSION}.tar.gz && \
    tar -xf popt-${POPT_VERSION}.tar.gz && mv popt-${POPT_VERSION} popt && \
    cd popt && mkdir -p /popt && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr && make -s -j${JOBS} DESTDIR=/popt && \
    make -s -j${JOBS} DESTDIR=/popt install && make -s -j${JOBS} install

## zlib
FROM popt AS zlib

ARG ZLIB_VERSION=1.3.1
ENV ZLIB_VERSION=${ZLIB_VERSION}

COPY --from=sources-downloader /sources/downloads/zlib-${ZLIB_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf zlib-${ZLIB_VERSION}.tar.gz && mv zlib-${ZLIB_VERSION} zlib && \
    cd zlib && mkdir -p /zlib && ./configure --prefix=/usr --shared && make -s -j${JOBS} DESTDIR=/zlib && \
    make -s -j${JOBS} DESTDIR=/zlib install && make -s -j${JOBS} install

## gawk

FROM zlib AS gawk

ARG GAWK_VERSION=5.3.2
ENV GAWK_VERSION=${GAWK_VERSION}

COPY --from=sources-downloader /sources/downloads/gawk-${GAWK_VERSION}.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf gawk-${GAWK_VERSION}.tar.xz && mv gawk-${GAWK_VERSION} gawk && \
    cd gawk && mkdir -p /gawk && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr -sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --disable-nls \
    --disable-pma&& make -s -j${JOBS} DESTDIR=/gawk && \
    make -s -j${JOBS} DESTDIR=/gawk install && make -s -j${JOBS} install

## rsync
FROM gawk AS rsync

ARG RSYNC_VERSION=3.4.1
ENV RSYNC_VERSION=${RSYNC_VERSION}

COPY --from=sources-downloader /sources/downloads/rsync-${RSYNC_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xf rsync-${RSYNC_VERSION}.tar.gz && mv rsync-${RSYNC_VERSION} rsync && \
    cd rsync && mkdir -p /rsync && \
    ./configure --quiet ${COMMON_ARGS} --prefix=/usr \
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

RUN mkdir /sources && cd /sources && wget https://ftpmirror.gnu.org/binutils/binutils-${BINUTILS_VERSION}.tar.xz && \
    tar -xf binutils-${BINUTILS_VERSION}.tar.xz && mv binutils-${BINUTILS_VERSION} binutils && \
    cd binutils && mkdir -p /binutils && ./configure --quiet ${COMMON_ARGS} && make -s -j${JOBS} DESTDIR=/binutils && \
    make -s -j${JOBS} DESTDIR=/binutils install && make -s -j${JOBS} install

## ncurses
FROM stage1 AS ncurses

ARG NCURSES_VERSION=6.5
ENV NCURSES_VERSION=${NCURSES_VERSION}

RUN mkdir /sources && cd /sources && wget http://ftpmirror.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz && \
    tar -xf ncurses-${NCURSES_VERSION}.tar.gz && mv ncurses-${NCURSES_VERSION} ncurses && \
    cd ncurses && mkdir -p /ncurses && sed -i s/mawk// configure && mkdir build && \
    cd build && ../configure --quiet ${COMMON_ARGS} && make -s -C include &&  make -s -C progs tic && cd .. && \
    ./configure --quiet ${COMMON_ARGS} \
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

RUN mkdir /sources && cd /sources && wget http://mirror.easyname.at/gnu/m4/m4-${M4_VERSION}.tar.xz && \
    tar -xf m4-${M4_VERSION}.tar.xz && mv m4-${M4_VERSION} m4 && \
    cd m4 && mkdir -p /m4 && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking && make -s -j${JOBS} DESTDIR=/m4 && \
    make -s -j${JOBS} DESTDIR=/m4 install && make -s -j${JOBS} install

## readline
FROM stage1 AS readline

ARG READLINE_VERSION=8.3
ENV READLINE_VERSION=${READLINE_VERSION}

RUN mkdir -p /sources && cd /sources && wget http://mirror.easyname.at/gnu/readline/readline-${READLINE_VERSION}.tar.gz && \
    tar -xf readline-${READLINE_VERSION}.tar.gz && mv readline-${READLINE_VERSION} readline && \
    cd readline && mkdir -p /readline && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking && make -s -j${JOBS} DESTDIR=/readline && \
    make -s -j${JOBS} DESTDIR=/readline install && make -s -j${JOBS} install

## bash
FROM readline AS bash

ARG BASH_VERSION=5.3
ENV BASH_VERSION=${BASH_VERSION}

COPY ./files/bash/bashrc /sources/bashrc
COPY ./files/bash/profile-bashrc.sh /sources/profile-bashrc.sh
RUN mkdir -p /sources && cd /sources && wget http://mirror.easyname.at/gnu/bash/bash-${BASH_VERSION}.tar.gz && \
    tar -xf bash-${BASH_VERSION}.tar.gz && mv bash-${BASH_VERSION} bash && \
    cd bash && mkdir -p /bash && ./configure --quiet ${COMMON_ARGS} \
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

ENV CFLAGS="-static -Os -ffunction-sections -fdata-sections -Bsymbolic-functions"
ENV LDFLAGS="-Wl,--gc-sections"
ENV PERL_CROSS=1.6.2

RUN cd /sources && \
    wget http://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.xz && \
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
       -Dcf_by='uKairos' \
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

ARG COREUTILS_VERSION=9.4
ENV COREUTILS_VERSION=${COREUTILS_VERSION}

COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

COPY --from=libcap /libcap /libcap
RUN rsync -aHAX --keep-dirlinks  /libcap/. /

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

RUN mkdir -p /sources && cd /sources && wget http://mirror.easyname.at/gnu/coreutils/coreutils-${COREUTILS_VERSION}.tar.xz && \
    tar -xf coreutils-${COREUTILS_VERSION}.tar.xz && mv coreutils-${COREUTILS_VERSION} coreutils && \
    cd coreutils && mkdir -p /coreutils && ./configure --quiet ${COMMON_ARGS} \
    --prefix=/usr \
    --bindir=/bin \
    --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --disable-nls \
    --enable-no-install-program=hostname,su,kill,uptime \
    --enable-single-binary=symlinks \
    --enable-single-binary-exceptions=env,fmt,sha512sum \
    --with-openssl \
    --disable-dependency-tracking && make -s -j${JOBS} DESTDIR=/coreutils && \
    make -s -j${JOBS} DESTDIR=/coreutils install

## findutils
FROM stage1 AS findutils

ARG FINDUTILS_VERSION=4.10.0
ENV FINDUTILS_VERSION=${FINDUTILS_VERSION}

RUN mkdir -p /sources && cd /sources && wget http://mirror.easyname.at/gnu/findutils/findutils-${FINDUTILS_VERSION}.tar.xz && \
    tar -xf findutils-${FINDUTILS_VERSION}.tar.xz && mv findutils-${FINDUTILS_VERSION} findutils && \
    cd findutils && mkdir -p /findutils && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking && make -s -j${JOBS} DESTDIR=/findutils && \
    make -s -j${JOBS} DESTDIR=/findutils install && make -s -j${JOBS} install

## grep
FROM stage1 AS grep

ARG GREP_VERSION=3.12
ENV GREP_VERSION=${GREP_VERSION}

RUN mkdir -p /sources && cd /sources && wget http://mirror.easyname.at/gnu/grep/grep-${GREP_VERSION}.tar.xz && \
    tar -xf grep-${GREP_VERSION}.tar.xz && mv grep-${GREP_VERSION} grep && \
    cd grep && mkdir -p /grep && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking && make -s -j${JOBS} DESTDIR=/grep && \
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
    cd sqlite3 && mkdir -p /sqlite3 && ./configure --quiet \
		--prefix=/usr \
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
    cd curl && mkdir -p /curl && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking --enable-ipv6 \
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
    cd util-linux && mkdir -p /util-linux && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking  --prefix=/usr \
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
    && make -s -j${JOBS} DESTDIR=/util-linux && \
    make -s -j${JOBS} DESTDIR=/util-linux install && make -s -j${JOBS} install


## gperf
FROM stage1 AS gperf

ARG GPERF_VERSION=3.3
ENV GPERF_VERSION=${GPERF_VERSION}

RUN mkdir -p /sources && cd /sources && wget http://mirror.easyname.at/gnu/gperf/gperf-${GPERF_VERSION}.tar.gz && \
    tar -xf gperf-${GPERF_VERSION}.tar.gz && mv gperf-${GPERF_VERSION} gperf && \
    cd gperf && mkdir -p /gperf && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr && \
    make -s -j${JOBS} BUILD_CC=gcc CC="${CC:-gcc}" lib=lib prefix=/usr GOLANG=no DESTDIR=/gperf && \
    make -s -j${JOBS} DESTDIR=/gperf install && make -s -j${JOBS} install

## libseccomp
FROM rsync AS libseccomp
COPY --from=gperf /gperf /gperf
RUN rsync -aHAX --keep-dirlinks  /gperf/. /
COPY --from=sources-downloader /sources/downloads/libseccomp.tar.gz /sources/
RUN mkdir -p /libseccomp
WORKDIR /sources
RUN tar -xf libseccomp.tar.gz && mv libseccomp-* libseccomp
WORKDIR /sources/libseccomp
RUN ./configure --quiet --prefix=/usr --disable-static
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
RUN bash ./configure --quiet --prefix=/usr --disable-static
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/expat


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
RUN meson setup buildDir --prefix=/usr --buildtype=release
RUN DESTDIR=/dbus ninja -C buildDir install


## systemd
FROM rsync AS systemd

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

COPY --from=sources-downloader /sources/downloads/systemd /sources/systemd
ENV CFLAGS="-D __UAPI_DEF_ETHHDR=0 -D _LARGEFILE64_SOURCE"
RUN mkdir -p /systemd
RUN python3 -m pip install meson ninja jinja2
WORKDIR /sources/systemd
RUN /usr/bin/meson setup buildDir \
      --prefix=/usr           \
      --buildtype=release     \
      -D dbus=true \
      -D seccomp=true         \
      -D default-dnssec=no    \
      -D firstboot=false      \
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
      -D docdir=/usr/share/doc/systemd-${SYSTEMD_VERSION}
RUN ninja -C buildDir
RUN DESTDIR=/systemd ninja -C buildDir install
RUN ninja -C buildDir install

## flex
FROM m4 AS flex
ARG FLEX_VERSION=2.6.4
ENV FLEX_VERSION=${FLEX_VERSION}

COPY --from=sources-downloader /sources/downloads/flex-${FLEX_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf flex-${FLEX_VERSION}.tar.gz && mv flex-${FLEX_VERSION} flex && cd flex && mkdir -p /flex && ./configure ${COMMON_ARGS} --docdir=/usr/share/doc/flex-${FLEX_VERSION} --disable-dependency-tracking --infodir=/usr/share/info --mandir=/usr/share/man --prefix=/usr --disable-static --enable-shared ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes && \
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
RUN mkdir -p /sources && cd /sources && tar -xvf bison-${BISON_VERSION}.tar.xz && mv bison-${BISON_VERSION} bison && cd bison && mkdir -p /bison && ./configure ${COMMON_ARGS} --disable-dependency-tracking --infodir=/usr/share/info --mandir=/usr/share/man --prefix=/usr --disable-static --enable-shared && \
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
    cd autoconf && mkdir -p /autoconf && ./configure ${COMMON_ARGS} --prefix=/usr && make DESTDIR=/autoconf && \
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
    cd automake && mkdir -p /automake && ./configure ${COMMON_ARGS} --prefix=/usr && make DESTDIR=/automake && \
    make DESTDIR=/automake install && make install


## argp-standalone
FROM rsync AS argp-standalone

ARG ARGP_STANDALONE_VERSION=1.3
ENV ARGP_STANDALONE_VERSION=${ARGP_STANDALONE_VERSION}

ENV CFLAGS="$CFLAGS -fPIC"

COPY --from=autoconf /autoconf /autoconf
RUN rsync -aHAX --keep-dirlinks  /autoconf/. /

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=automake /automake /automake
RUN rsync -aHAX --keep-dirlinks  /automake/. /

COPY --from=m4 /m4 /m4
RUN rsync -aHAX --keep-dirlinks  /m4/. /

COPY --from=sources-downloader /sources/downloads/argp-standalone-${ARGP_STANDALONE_VERSION}.tar.gz /sources/
RUN mkdir -p /sources && cd /sources && tar -xvf argp-standalone-${ARGP_STANDALONE_VERSION}.tar.gz && mv argp-standalone-${ARGP_STANDALONE_VERSION} argp-standalone && cd argp-standalone && mkdir -p /argp-standalone && autoreconf -vif && ./configure ${COMMON_ARGS} --disable-dependency-tracking --mandir=/usr/share/man --prefix=/usr --disable-static --enable-shared -sysconfdir=/etc --localstatedir=/var && \
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
gnulib-tests/Makefile.in && ./configure ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr --disable-static --enable-shared && \
    make DESTDIR=/libtool install && make install

## fts

FROM rsync AS fts
ARG FTS_VERSION=1.2.7
ENV FTS_VERSION=${FTS_VERSION}

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

RUN mkdir -p /sources && cd /sources && tar -xvf musl-fts-${FTS_VERSION}.tar.gz && mv musl-fts-${FTS_VERSION} fts && cd fts && mkdir -p /fts && ./bootstrap.sh && ./configure ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr --disable-static --enable-shared --localstatedir=/var --mandir=/usr/share/man  --sysconfdir=/etc  && \
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
RUN mkdir -p /sources && cd /sources && tar -xvf musl-obstack-${MUSL_OBSTACK_VERSION}.tar.gz && mv musl-obstack-${MUSL_OBSTACK_VERSION} musl-obstack && cd musl-obstack && mkdir -p /musl-obstack && ./bootstrap.sh && ./configure ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr --disable-static --enable-shared && \
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

RUN mkdir -p /sources && cd /sources && tar -xvf elfutils-${ELFUTILS_VERSION}.tar.bz2 && mv elfutils-${ELFUTILS_VERSION} elfutils && cd elfutils && mkdir -p /elfutils && patch -p1 -i /sources/downloads/elfutils-patches/musl-macros.patch && ./configure ${COMMON_ARGS} --disable-dependency-tracking --infodir=/usr/share/info --mandir=/usr/share/man --prefix=/usr --disable-static --enable-shared \
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


from rsync AS diffutils
ARG DIFFUTILS_VERSION=3.9


RUN mkdir -p /sources && cd /sources && wget http://ftpmirror.gnu.org/diffutils/diffutils-${DIFFUTILS_VERSION}.tar.xz && \
    tar -xf diffutils-${DIFFUTILS_VERSION}.tar.xz && mv diffutils-${DIFFUTILS_VERSION} diffutils && \
    cd diffutils && mkdir -p /diffutils && ./configure --quiet ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr && \
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
RUN cp -rfv /sources/kernel-configs/ukairos-${TARGETARCH}.config .config
WORKDIR /sources/kernel
RUN make -j${JOBS} olddefconfig
# This only builds the kernel
RUN KBUILD_BUILD_VERSION="$KERNEL_VERSION-${VENDOR}" make -s -j${JOBS} bzImage
RUN cp arch/$ARCH/boot/bzImage /kernel/vmlinuz

# This builds the modules
RUN KBUILD_BUILD_VERSION="$KERNEL_VERSION-${VENDOR}" make -s -j${JOBS} modules
RUN ln -s /modules/lib/modules /lib/modules
RUN ZSTD_CLEVEL=19 INSTALL_MOD_PATH="/modules" INSTALL_MOD_STRIP=1 DEPMOD=true make modules_install

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
RUN meson setup buildDir --prefix=/usr --buildtype=release
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
RUN ./configure --quiet --prefix=/usr --disable-static --enable-mpers=check
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/strace

## libmnl
FROM rsync AS libmnl
COPY --from=sources-downloader /sources/downloads/libmnl.tar.bz2 /sources/
RUN mkdir -p /libmnl
WORKDIR /sources
RUN tar -xf libmnl.tar.bz2 && mv libmnl-* libmnl
WORKDIR /sources/libmnl
RUN ./configure --quiet --prefix=/usr
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
RUN ./configure --quiet --prefix=/usr
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

RUN ./configure --quiet --prefix=/usr --with-xtlibdir=/usr/lib/xtables
RUN make -s -s && make -s -s install DESTDIR=/iptables

########################################################
#
# Stage 2 - Building the final image
#
########################################################

FROM stage0 AS stage2-merge

RUN apk add rsync

COPY --from=skeleton /sysroot /skeleton

## Perl
# COPY --from=perl /perl /perl
# RUN rsync -aHAX --keep-dirlinks  /perl/. /skeleton/

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

## systemd
COPY --from=systemd /systemd /systemd
RUN rsync -aHAX --keep-dirlinks  /systemd/. /skeleton/

## dbus
COPY --from=dbus-systemd /dbus /dbus
RUN rsync -aHAX --keep-dirlinks  /dbus/. /skeleton/

## seccomp
COPY --from=libseccomp /libseccomp /libseccomp
RUN rsync -aHAX --keep-dirlinks  /libseccomp/. /skeleton/

## libexpat
COPY --from=expat /expat /expat
RUN rsync -aHAX --keep-dirlinks  /expat/. /skeleton/

## strace, disabled but if we need to debug this is very useful to add
## Just uncomment this and you will get it in the final image
# COPY --from=strace /strace /strace
# RUN rsync -aHAX --keep-dirlinks  /strace/. /skeleton

## kbd for loadkeys support
COPY --from=kbd /kbd /kbd
RUN rsync -aHAX --keep-dirlinks  /kbd/. /skeleton

COPY --from=iptables /iptables /iptables
RUN rsync -aHAX --keep-dirlinks  /iptables/. /skeleton
## Cleanup

# We don't need headers
RUN rm -rf /skeleton/usr/include

## Immucore for initramfs
FROM alpine AS immucore
RUN wget https://github.com/kairos-io/immucore/releases/download/v0.11.3/immucore-v0.11.3-linux-amd64.tar.gz
RUN tar xf immucore-v0.11.3-linux-amd64.tar.gz
RUN mv immucore /immucore
RUN chmod +x /immucore
RUN apk add --no-cache upx
RUN upx /immucore

# Agent
FROM alpine AS kairos-agent
RUN wget https://github.com/kairos-io/kairos-agent/releases/download/v2.25.0/kairos-agent-v2.25.0-linux-amd64.tar.gz
RUN tar xf kairos-agent-v2.25.0-linux-amd64.tar.gz
RUN mv kairos-agent /kairos-agent
RUN chmod +x /kairos-agent
RUN apk add --no-cache upx
RUN upx /kairos-agent

# Build the initramfs
FROM alpine AS initramfs-builder
RUN apk add --no-cache cpio
COPY --from=busybox /sysroot /initramfs
# Copy groups file
COPY --from=stage2-merge /skeleton/etc/group /initramfs/etc/group
COPY --from=stage2-merge /skeleton/usr/lib/ld-musl-x86_64.so.1 /initramfs/lib/ld-musl-x86_64.so.1
# Udev stuff, consider building eudev?
COPY --from=stage2-merge /skeleton/usr/lib/systemd/systemd-udevd /initramfs/usr/lib/systemd/systemd-udevd
COPY --from=stage2-merge /skeleton/usr/sbin/udevadm /initramfs/usr/sbin/udevadm
COPY --from=stage2-merge /skeleton/etc/udev/ /initramfs/etc/udev/
COPY --from=stage2-merge /skeleton/usr/lib/udev/ /initramfs/usr/lib/udev/
# Policy for network naming
COPY --from=stage2-merge /skeleton/usr/lib/systemd/network/ /initramfs/usr/lib/systemd/network/
# This are all libs needed by systemd-udevd
COPY --from=stage2-merge /skeleton/usr/lib/systemd/libsystemd-shared-257.so /initramfs/usr/lib/systemd/libsystemd-shared-257.so
COPY --from=stage2-merge /skeleton/usr/lib/libblkid.so.1 /initramfs/usr/lib/libblkid.so.1
COPY --from=stage2-merge /skeleton/usr/lib/libcrypto.so.3 /initramfs/usr/lib/libcrypto.so.3
COPY --from=stage2-merge /skeleton/usr/lib/libmount.so.1 /initramfs/usr/lib/libmount.so.1
COPY --from=stage2-merge /skeleton/usr/lib/libcap.so.2 /initramfs/usr/lib/libcap.so.2
COPY --from=stage2-merge /skeleton/usr/lib/libacl.so.1 /initramfs/usr/lib/libacl.so.1
COPY --from=stage2-merge /skeleton/usr/lib/libattr.so.1 /initramfs/usr/lib/libattr.so.1
COPY --from=stage2-merge /skeleton/usr/lib/libseccomp.so.2 /initramfs/usr/lib/libseccomp.so.2
COPY --from=immucore /immucore /initramfs/bin/immucore
WORKDIR /initramfs
COPY files/init .
RUN find . | cpio -o -H newc > ../init.cpio

### Assemble the final image for testing
## You can use this image with aurora and it will generate a bootable image
FROM scratch AS devel
COPY --from=stage2-merge /skeleton /

# This probably needs moving into a different place rather than here it shouldbe done under the skeleton? After building and installing it?
RUN busybox --install
## Workaround to have bash as /bin/sh after busybox overrides it
RUN rm /bin/sh && ln -s /bin/bash /bin/sh
RUN systemctl preset-all
COPY --from=luet-kernel /kernel/boot/vmlinuz /boot/vmlinuz
COPY --from=luet-kernel /kernel/lib/modules/ /lib/modules/
COPY --from=initramfs-builder /init.cpio /boot/initramfs
COPY --from=kairos-agent /kairos-agent /usr/bin/kairos-agent
# workaround as we dont have the /system/oem files
RUN mkdir -p /system/oem/
## Make eth devices managed by systemd-networkd
RUN echo -e "[Match]\nName=en*\n\n[Network]\nDHCP=yes\n" > /etc/systemd/network/20-wired.network

## Assemble the final image
## you can pass this image to init like if it was any other base image and it should generate
## a kairosified image
## Note that in here we serve the minimal systeml, no workarounds, no initrd, just the kernel and system
## Its the kairos-init the one that will take care of the rest
FROM scratch AS stage2
COPY --from=stage2-merge /skeleton /

FROM stage2 AS stage3
RUN busybox --install
## Workaround to have bash as /bin/sh after busybox overrides it
RUN rm /bin/sh && ln -s /bin/bash /bin/sh
RUN systemctl preset-all

## TODO: The images probably are not shipping the files there
COPY --from=kernel /kernel/vmlinuz /boot/vmlinuz
COPY --from=kernel /modules/ /lib/modules/

### final image
FROM stage3 AS default
CMD ["/bin/bash", "-l"]
