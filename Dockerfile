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
ARG ARCH="x86-64"
ARG BUILD_ARCH="x86_64"
ARG JOBS=16
ARG MUSSEL_VERSION="95dec40aee2077aa703b7abc7372ba4d34abb889"

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

RUN cd /sources/downloads && wget https://ftp.gnu.org/gnu/gawk/gawk-${GAWK_VERSION}.tar.xz -O gawk-${GAWK_VERSION}.tar.xz

ARG CA_CERTIFICATES_VERSION=20250619
ENV CA_CERTIFICATES_VERSION=${CA_CERTIFICATES_VERSION}

RUN cd /sources/downloads && wget https://gitlab.alpinelinux.org/alpine/ca-certificates/-/archive/${CA_CERTIFICATES_VERSION}/ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2 -O ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2

ARG SYSTEMD_VERSION=257.8
ENV SYSTEMD_VERSION=${SYSTEMD_VERSION}

RUN cd /sources/downloads && wget https://github.com/systemd/systemd/archive/refs/tags/v${SYSTEMD_VERSION}.tar.gz -O systemd-${SYSTEMD_VERSION}.tar.gz

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

RUN cd /sources && tar -xvf busybox-${BUSYBOX_VERSION}.tar.bz2 && \
    cd busybox-${BUSYBOX_VERSION} && \
    make distclean && \
    make ARCH="${ARCH}" defconfig && \
    sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config && \
    sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_TC\)=y/# \1 is not set/' .config && \
    make ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" && \
    make ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" CONFIG_PREFIX="/sysroot" install

###
### MUSL
###
FROM stage0 AS musl-stage0

ARG MUSL_VERSION=1.2.5
ENV MUSL_VERSION=${MUSL_VERSION}

RUN wget http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz && \
    tar -xvf musl-${MUSL_VERSION}.tar.gz && \
    cd musl-${MUSL_VERSION} && \
    ./configure \
      CROSS_COMPILE=${TARGET}- \
      --prefix=/usr \
      --disable-static \
      --target=${TARGET} && \
      make -j${JOBS} && \
      DESTDIR=/sysroot make -j${JOBS} install

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
RUN tar -xvf gcc-${GCC_VERSION}.tar.xz
RUN tar -xvf gmp-${GMP_VERSION}.tar.bz2
RUN tar -xvf mpc-${MPC_VERSION}.tar.gz
RUN tar -xvf mpfr-${MPFR_VERSION}.tar.bz2

RUN <<EOT bash
    mv -v mpfr-${MPFR_VERSION} gcc-${GCC_VERSION}/mpfr
    mv -v mpc-${MPC_VERSION} gcc-${GCC_VERSION}/mpc
    mv -v gmp-${GMP_VERSION} gcc-${GCC_VERSION}/gmp
    mkdir -p /sysroot/usr/include
    cd gcc-${GCC_VERSION} && mkdir -v build && cd build && ls -liah /gcc-${GCC_VERSION}/mpfr/src/ && \
    ../configure \
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
        make ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" -j${JOBS} && \
        make ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" DESTDIR=/sysroot install ;
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

RUN cd /sources && tar -xvf make-${MAKE_VERSION}.tar.gz && \
    cd make-${MAKE_VERSION} && \
    ./configure --prefix=/usr \
    --build=${BUILD_ARCH} --host=${TARGET} && \
    make -j${JOBS} && \
    make -j${JOBS} DESTDIR=/sysroot install


###
### Binutils
###
FROM stage0 AS binutils-stage0

ENV BINUTILS_VERSION=2.44
ENV BINUTILS_VERSION=${BINUTILS_VERSION}

RUN <<EOT bash
    wget http://mirror.netcologne.de/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz
    tar -xvf binutils-${BINUTILS_VERSION}.tar.xz
EOT

RUN <<EOT bash
    cd binutils-${BINUTILS_VERSION} && 
    ./configure \
       --prefix=/usr \
       --build=${BUILD_ARCH} \
       --host=${TARGET} \
       --target=${TARGET} \
       --with-sysroot=/ \
       --disable-nls \
       --disable-multilib \
       --enable-shared && \
       make -j${JOBS} && \
       make DESTDIR=/sysroot install ;
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
RUN rsync -aHAX --keep-dirlinks  /gcc/. /skeleton

## MUSL
COPY --from=musl-stage0 /sysroot /musl
RUN rsync -aHAX --keep-dirlinks  /musl/. /skeleton/

## BUSYBOX
COPY --from=busybox-stage0 /sysroot /busybox
RUN rsync -aHAX --keep-dirlinks  /busybox/. /skeleton/

## Make
COPY --from=make-stage0 /sysroot /make
RUN rsync -aHAX --keep-dirlinks  /make/. /skeleton/

## Binutils
COPY --from=binutils-stage0 /sysroot /binutils
RUN rsync -aHAX --keep-dirlinks  /binutils/. /skeleton/

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
RUN make --version

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
    tar -xvf musl-${MUSL_VERSION}.tar.gz && \
    cd musl-${MUSL_VERSION} && \
    ./configure \
      --prefix=/usr \
      --disable-static && \
      make -j${JOBS} && \
      DESTDIR=/sysroot make -j${JOBS} install

## pkgconfig
FROM stage1 AS pkgconfig

ARG PKGCONFIG_VERSION=1.8.1
ENV PKGCONFIG_VERSION=${PKGCONFIG_VERSION}

COPY --from=sources-downloader /sources/downloads/pkgconf-${PKGCONFIG_VERSION}.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf pkgconf-${PKGCONFIG_VERSION}.tar.xz && mv pkgconf-${PKGCONFIG_VERSION} pkgconfig && \
    cd pkgconfig && mkdir -p /pkgconfig && ./configure ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --localstatedir=/var \
    --with-pkg-config-dir=/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig && \
    make && \
    make DESTDIR=/pkgconfig install && make install && ln -s pkgconf /pkgconfig/usr/bin/pkg-config

## autoconf
FROM stage1 AS autoconf

ARG AUTOCONF_VERSION=2.71
ENV AUTOCONF_VERSION=${AUTOCONF_VERSION}

RUN mkdir /sources && cd /sources && wget http://mirror.netcologne.de/gnu/autoconf/autoconf-${AUTOCONF_VERSION}.tar.xz && \
    tar -xvf autoconf-${AUTOCONF_VERSION}.tar.xz && mv autoconf-${AUTOCONF_VERSION} autoconf && \
    cd autoconf && mkdir -p /autoconf && ./configure ${COMMON_ARGS} && make DESTDIR=/autoconf && \
    make DESTDIR=/autoconf install && make install

## automake
FROM stage1 AS automake

ARG AUTOMAKE_VERSION=1.16.5
ENV AUTOMAKE_VERSION=${AUTOMAKE_VERSION}

RUN mkdir /sources && cd /sources && wget http://mirror.netcologne.de/gnu/automake/automake-${AUTOMAKE_VERSION}.tar.xz && \
    tar -xvf automake-${AUTOMAKE_VERSION}.tar.xz && mv automake-${AUTOMAKE_VERSION} automake && \
    cd automake && mkdir -p /automake && ./configure ${COMMON_ARGS} && make DESTDIR=/automake && \
    make DESTDIR=/automake install && make install

## xxhash
FROM stage1 AS xxhash

ARG XXHASH_VERSION=0.8.3
ENV XXHASH_VERSION=${XXHASH_VERSION}

COPY --from=sources-downloader /sources/downloads/xxHash-${XXHASH_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf xxHash-${XXHASH_VERSION}.tar.gz && mv xxHash-${XXHASH_VERSION} xxhash && \
    tar -xvf xxHash-${XXHASH_VERSION}.tar.gz && mv xxHash-${XXHASH_VERSION} xxhash && \
    cd xxhash && mkdir -p /xxhash && CC=gcc make DESTDIR=/xxhash && \
    make DESTDIR=/xxhash install && make install

## zstd
FROM xxhash AS zstd

ARG ZSTD_VERSION=1.5.7
ENV ZSTD_VERSION=${ZSTD_VERSION}

COPY --from=sources-downloader /sources/downloads/zstd-${ZSTD_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf zstd-${ZSTD_VERSION}.tar.gz && mv zstd-${ZSTD_VERSION} zstd && \
    cd zstd && mkdir -p /zstd && CC=gcc make DESTDIR=/zstd && \
    make DESTDIR=/zstd install && make install

## lz4
FROM zstd AS lz4

ARG LZ4_VERSION=1.10.0
ENV LZ4_VERSION=${LZ4_VERSION}

COPY --from=sources-downloader /sources/downloads/lz4-${LZ4_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf lz4-${LZ4_VERSION}.tar.gz && mv lz4-${LZ4_VERSION} lz4 && \
    cd lz4 && mkdir -p /lz4 && CC=gcc make PREFIX="/usr" DESTDIR=/lz4 && \
    make DESTDIR=/lz4 install && make install

## attr
FROM lz4 AS attr

ARG ATTR_VERSION=2.5.2
ENV ATTR_VERSION=${ATTR_VERSION}

COPY --from=sources-downloader /sources/downloads/attr-${ATTR_VERSION}.tar.gz /sources/
COPY ./patches/attr/basename.patch /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf attr-${ATTR_VERSION}.tar.gz && mv attr-${ATTR_VERSION} attr && \
    cd attr && mkdir -p /attr && \
    patch -p1 < /sources/basename.patch && \
    ./configure ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --localstatedir=/var \
    --disable-nls && make DESTDIR=/attr && \
    make DESTDIR=/attr install && make install

## acl
FROM attr AS acl

ARG ACL_VERSION=2.3.2
ENV ACL_VERSION=${ACL_VERSION}

COPY --from=sources-downloader /sources/downloads/acl-${ACL_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf acl-${ACL_VERSION}.tar.gz && mv acl-${ACL_VERSION} acl && \
    tar -xvf acl-${ACL_VERSION}.tar.gz && mv acl-${ACL_VERSION} acl && \
    cd acl && mkdir -p /acl && ./configure ${COMMON_ARGS} --prefix=/usr --disable-dependency-tracking --libexecdir=/usr/libexec && make DESTDIR=/acl && \
    make DESTDIR=/acl install && make install

## popt
FROM acl AS popt

ARG POPT_VERSION=1.19
ENV POPT_VERSION=${POPT_VERSION}

RUN mkdir -p /sources && cd /sources && wget http://ftp.rpm.org/popt/releases/popt-1.x/popt-${POPT_VERSION}.tar.gz && \
    tar -xvf popt-${POPT_VERSION}.tar.gz && mv popt-${POPT_VERSION} popt && \
    cd popt && mkdir -p /popt && ./configure ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr && make DESTDIR=/popt && \
    make DESTDIR=/popt install && make install

## zlib
FROM popt AS zlib

ARG ZLIB_VERSION=1.3.1
ENV ZLIB_VERSION=${ZLIB_VERSION}

COPY --from=sources-downloader /sources/downloads/zlib-${ZLIB_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf zlib-${ZLIB_VERSION}.tar.gz && mv zlib-${ZLIB_VERSION} zlib && \
    cd zlib && mkdir -p /zlib && ./configure --prefix=/usr --shared && make DESTDIR=/zlib && \
    make DESTDIR=/zlib install && make install

## gawk

FROM zlib AS gawk

ARG GAWK_VERSION=5.3.2
ENV GAWK_VERSION=${GAWK_VERSION}

COPY --from=sources-downloader /sources/downloads/gawk-${GAWK_VERSION}.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf gawk-${GAWK_VERSION}.tar.xz && mv gawk-${GAWK_VERSION} gawk && \
    cd gawk && mkdir -p /gawk && ./configure ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr -sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --disable-nls \
    --disable-pma&& make DESTDIR=/gawk && \
    make DESTDIR=/gawk install && make install

## rsync
FROM gawk AS rsync

ARG RSYNC_VERSION=3.4.1
ENV RSYNC_VERSION=${RSYNC_VERSION}

COPY --from=sources-downloader /sources/downloads/rsync-${RSYNC_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf rsync-${RSYNC_VERSION}.tar.gz && mv rsync-${RSYNC_VERSION} rsync && \
    cd rsync && mkdir -p /rsync && \
    ./configure ${COMMON_ARGS} --prefix=/usr \
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
    --disable-openssl && make DESTDIR=/rsync && \
    make DESTDIR=/rsync install && make install

## binutils
FROM stage1 AS binutils

ARG BINUTILS_VERSION=2.44
ENV BINUTILS_VERSION=${BINUTILS_VERSION}

RUN mkdir /sources && cd /sources && wget https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz && \
    tar -xvf binutils-${BINUTILS_VERSION}.tar.xz && mv binutils-${BINUTILS_VERSION} binutils && \
    cd binutils && mkdir -p /binutils && ./configure ${COMMON_ARGS} && make DESTDIR=/binutils && \
    make DESTDIR=/binutils install && make install

## ncurses
FROM stage1 AS ncurses

ARG NCURSES_VERSION=6.5
ENV NCURSES_VERSION=${NCURSES_VERSION}

RUN mkdir /sources && cd /sources && wget http://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz && \
    tar -xvf ncurses-${NCURSES_VERSION}.tar.gz && mv ncurses-${NCURSES_VERSION} ncurses && \
    cd ncurses && mkdir -p /ncurses && sed -i s/mawk// configure && mkdir build && \
    cd build && ../configure ${COMMON_ARGS} && make -C include &&  make -C progs tic && cd .. && \
    ./configure ${COMMON_ARGS} \
    --mandir=/usr/share/man \
    --with-manpage-format=normal \
    --with-shared \
    --without-debug \
    --without-ada \
    --without-normal \
    --disable-stripping \
    --enable-widec && \
    make -j${JOBS} && \
    make DESTDIR=/ncurses TIC_PATH=/sources/ncurses/build/progs/tic install && make install && echo "INPUT(-lncursesw)" > /ncurses/usr/lib/libncurses.so && \
    cp /ncurses/usr/lib/libncurses.so /usr/lib/libncurses.so

## m4 (from stage1, ready to be used in the final image)
FROM stage1 AS m4

ARG M4_VERSION=1.4.20
ENV M4_VERSION=${M4_VERSION}

RUN mkdir /sources && cd /sources && wget http://ftp.gnu.org/gnu/m4/m4-${M4_VERSION}.tar.xz && \
    tar -xvf m4-${M4_VERSION}.tar.xz && mv m4-${M4_VERSION} m4 && \
    cd m4 && mkdir -p /m4 && ./configure ${COMMON_ARGS} --disable-dependency-tracking && make DESTDIR=/m4 && \
    make DESTDIR=/m4 install && make install

## readline
FROM stage1 AS readline

ARG READLINE_VERSION=8.3
ENV READLINE_VERSION=${READLINE_VERSION}

RUN mkdir -p /sources && cd /sources && wget http://ftp.gnu.org/gnu/readline/readline-${READLINE_VERSION}.tar.gz && \
    tar -xvf readline-${READLINE_VERSION}.tar.gz && mv readline-${READLINE_VERSION} readline && \
    cd readline && mkdir -p /readline && ./configure ${COMMON_ARGS} --disable-dependency-tracking && make DESTDIR=/readline && \
    make DESTDIR=/readline install && make install

## bash
FROM readline AS bash

ARG BASH_VERSION=5.3
ENV BASH_VERSION=${BASH_VERSION}

COPY ./files/bash/bashrc /sources/bashrc
COPY ./files/bash/profile-bashrc.sh /sources/profile-bashrc.sh

RUN mkdir -p /sources && cd /sources && wget http://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz && \
    tar -xvf bash-${BASH_VERSION}.tar.gz && mv bash-${BASH_VERSION} bash && \
    cd bash && mkdir -p /bash && ./configure ${COMMON_ARGS} \
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
    --with-installed-readline && make y.tab.c && make builtins/libbuiltins.a && make && \
    mkdir -p /bash/etc/bash && \
    install -Dm644  /sources/bashrc /bash/etc/bash/bashrc && \
    install -Dm644  /sources/profile-bashrc.sh /bash/etc/profile.d/00-bashrc.sh && \
    make DESTDIR=/bash install && make install # && rm -rf /bash/usr/share/locale

## perl
FROM m4 AS perl

ARG PERL_VERSION=5.42.0
ENV PERL_VERSION=${PERL_VERSION}

ENV CFLAGS="-static -Os -ffunction-sections -fdata-sections -Bsymbolic-functions"
ENV LDFLAGS="-Wl,--gc-sections"
ENV PERL_CROSS=1.6.2

RUN cd /sources && \
    wget http://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.xz && \
    tar -xvf perl-${PERL_VERSION}.tar.xz && mv perl-${PERL_VERSION} perl && \
    cd perl && \
       ln -s /usr/bin/gcc /usr/bin/cc && ./Configure -des -Dprefix=/usr 	-Dcccdlflags='-fPIC' \
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
       -Duse64bitint && make libperl.so && \
        make DESTDIR=/perl -j 8 && make DESTDIR=/perl install && make install

## openssl
FROM rsync AS openssl

ARG OPENSSL_VERSION=3.5.2
ENV OPENSSL_VERSION=${OPENSSL_VERSION}

COPY --from=perl /perl /perl
RUN rsync -aHAX --keep-dirlinks  /perl/. /

COPY --from=zlib /zlib /zlib
RUN rsync -aHAX --keep-dirlinks  /zlib/. /

COPY --from=sources-downloader /sources/downloads/openssl-${OPENSSL_VERSION}.tar.gz /sources/

RUN cd /sources && tar -xvf openssl-${OPENSSL_VERSION}.tar.gz && mv openssl-${OPENSSL_VERSION} openssl && \
    cd openssl && mkdir -p /openssl && ./config --prefix=/usr         \
    --openssldir=/etc/ssl \
    --libdir=lib          \
    shared                \
    zlib-dynamic 2>&1 && \
    make DESTDIR=/openssl 2>&1  && \
    make DESTDIR=/openssl install && make install

## Busybox (from stage1, ready to be used in the final image)
FROM openssl AS busybox

COPY --from=busybox-stage0 /sources /sources

ARG BUSYBOX_VERSION=1.37.0
ENV BUSYBOX_VERSION=${BUSYBOX_VERSION}

RUN cd /sources && rm -rfv busybox-${BUSYBOX_VERSION} && tar -xvf busybox-${BUSYBOX_VERSION}.tar.bz2 && \
    cd busybox-${BUSYBOX_VERSION} && \
    make -j1 distclean && \
    make defconfig && \
    sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config && \
    sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config && \
    sed -i 's/\(CONFIG_TC\)=y/# \1 is not set/' .config
RUN cd /sources/busybox-${BUSYBOX_VERSION} && \
    make -j1 && \
    make CONFIG_PREFIX="/sysroot" install && make install

## coreutils
FROM rsync AS coreutils

ARG COREUTILS_VERSION=9.4
ENV COREUTILS_VERSION=${COREUTILS_VERSION}

COPY --from=openssl /openssl /openssl
RUN rsync -aHAX --keep-dirlinks  /openssl/. /

RUN mkdir -p /sources && cd /sources && wget http://ftp.gnu.org/gnu/coreutils/coreutils-${COREUTILS_VERSION}.tar.xz && \
    tar -xvf coreutils-${COREUTILS_VERSION}.tar.xz && mv coreutils-${COREUTILS_VERSION} coreutils && \
    cd coreutils && mkdir -p /coreutils && ./configure ${COMMON_ARGS} \
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
    --disable-dependency-tracking && make DESTDIR=/coreutils && \
    make DESTDIR=/coreutils install

## findutils
FROM stage1 AS findutils

ARG FINDUTILS_VERSION=4.10.0
ENV FINDUTILS_VERSION=${FINDUTILS_VERSION}

RUN mkdir -p /sources && cd /sources && wget http://ftp.gnu.org/gnu/findutils/findutils-${FINDUTILS_VERSION}.tar.xz && \
    tar -xvf findutils-${FINDUTILS_VERSION}.tar.xz && mv findutils-${FINDUTILS_VERSION} findutils && \
    cd findutils && mkdir -p /findutils && ./configure ${COMMON_ARGS} --disable-dependency-tracking && make DESTDIR=/findutils && \
    make DESTDIR=/findutils install && make install

## grep
FROM stage1 AS grep

ARG GREP_VERSION=3.12
ENV GREP_VERSION=${GREP_VERSION}

RUN mkdir -p /sources && cd /sources && wget http://ftp.gnu.org/gnu/grep/grep-${GREP_VERSION}.tar.xz && \
    tar -xvf grep-${GREP_VERSION}.tar.xz && mv grep-${GREP_VERSION} grep && \
    cd grep && mkdir -p /grep && ./configure ${COMMON_ARGS} --disable-dependency-tracking && make DESTDIR=/grep && \
    make DESTDIR=/grep install && make install

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

RUN mkdir -p /sources && cd /sources && tar -xvf ca-certificates-${CA_CERTIFICATES_VERSION}.tar.bz2 && mv ca-certificates-${CA_CERTIFICATES_VERSION} ca-certificates && \
    cd ca-certificates && mkdir -p /ca-certificates && CC=gcc make && \
    make DESTDIR=/ca-certificates install

COPY ./files/ca-certificates/post_install.sh /sources/post_install.sh
RUN bash /sources/post_install.sh

## sqlite3 
FROM rsync AS sqlite3

ARG SQLITE3_VERSION=3500400
ENV SQLITE3_VERSION=${SQLITE3_VERSION}

ENV CFLAGS="${CFLAGS//-Os/-O2} -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_UNLOCK_NOTIFY 	-DSQLITE_ENABLE_RTREE 	-DSQLITE_ENABLE_GEOPOLY 	-DSQLITE_USE_URI 	-DSQLITE_ENABLE_DBSTAT_VTAB 	-DSQLITE_SOUNDEX 	-DSQLITE_MAX_VARIABLE_NUMBER=250000"

COPY --from=sources-downloader /sources/downloads/sqlite-autoconf-${SQLITE3_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf sqlite-autoconf-${SQLITE3_VERSION}.tar.gz && \
    mv sqlite-autoconf-${SQLITE3_VERSION} sqlite3 && \
    cd sqlite3 && mkdir -p /sqlite3 && ./configure \
		--prefix=/usr \
		--enable-threadsafe \
		--enable-session \
		--enable-static \
		--enable-fts3 \
		--enable-fts4 \
		--enable-fts5 \
		--soname=legacy && \
    make && \
    make DESTDIR=/sqlite3 install && make install

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

RUN mkdir -p /sources && cd /sources && tar -xvf curl-${CURL_VERSION}.tar.gz && mv curl-${CURL_VERSION} curl && \
    cd curl && mkdir -p /curl && ./configure  ${COMMON_ARGS} --disable-dependency-tracking --enable-ipv6 \
    --enable-unix-sockets \
    --enable-static \
    --without-libidn \
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
    --without-libssh2 && make DESTDIR=/curl && \
    make DESTDIR=/curl install && make install

## python
FROM rsync AS python-build

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

COPY --from=sources-downloader /sources/downloads/Python-${PYTHON_VERSION}.tar.xz /sources/

RUN rm /bin/sh && ln -s /bin/bash /bin/sh && mkdir -p /sources && cd /sources && tar -xvf Python-${PYTHON_VERSION}.tar.xz && mv Python-${PYTHON_VERSION} python && \
    cd python && mkdir -p /python && ./configure --disable-dependency-tracking --prefix=/usr \
    --enable-ipv6 \
    --enable-loadable-sqlite-extensions \
    --enable-optimizations \
    --enable-shared \
    --with-ensurepip=install \
    --with-lto \
    --with-computed-gotos \
    --with-dbmliborder=gdbm:ndbm  2>&1 && make DESTDIR=/python  2>&1 && \
    make DESTDIR=/python install  2>&1 && make install 2>&1
    #--with-system-libmpdec \
    #--with-system-expat \

## util-linux
FROM bash AS util-linux

ARG UTIL_LINUX_VERSION=2.41.1
ENV UTIL_LINUX_VERSION=${UTIL_LINUX_VERSION}

COPY --from=sources-downloader /sources/downloads/util-linux-${UTIL_LINUX_VERSION}.tar.xz /sources/

RUN rm /bin/sh && ln -s /bin/bash /bin/sh && mkdir -p /sources && cd /sources && tar -xf util-linux-${UTIL_LINUX_VERSION}.tar.xz && \
    mv util-linux-${UTIL_LINUX_VERSION} util-linux && \
    cd util-linux && mkdir -p /util-linux && ./configure ${COMMON_ARGS} --disable-dependency-tracking  --prefix=/usr \
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
    && make DESTDIR=/util-linux && \
    make DESTDIR=/util-linux install && make install

## libcap
FROM bash AS libcap

ARG LIBCAP_VERSION=2.76
ENV LIBCAP_VERSION=${LIBCAP_VERSION}

COPY --from=sources-downloader /sources/downloads/libcap-${LIBCAP_VERSION}.tar.xz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf libcap-${LIBCAP_VERSION}.tar.xz && mv libcap-${LIBCAP_VERSION} libcap && \
    cd libcap && mkdir -p /libcap && make BUILD_CC=gcc CC="${CC:-gcc}" && \
    make DESTDIR=/libcap PAM_LIBDIR=/lib prefix=/usr SBINDIR=/sbin lib=lib RAISE_SETFCAP=no GOLANG=no install && make GOLANG=no PAM_LIBDIR=/lib lib=lib prefix=/usr SBINDIR=/sbin RAISE_SETFCAP=no install

## gperf
FROM stage1 AS gperf

ARG GPERF_VERSION=3.3
ENV GPERF_VERSION=${GPERF_VERSION}

RUN mkdir -p /sources && cd /sources && wget http://ftp.gnu.org/gnu/gperf/gperf-${GPERF_VERSION}.tar.gz && \
    tar -xvf gperf-${GPERF_VERSION}.tar.gz && mv gperf-${GPERF_VERSION} gperf && \
    cd gperf && mkdir -p /gperf && ./configure ${COMMON_ARGS} --disable-dependency-tracking --prefix=/usr && \
    make BUILD_CC=gcc CC="${CC:-gcc}" lib=lib prefix=/usr GOLANG=no DESTDIR=/gperf && \
    make DESTDIR=/gperf install && make install

## systemd
FROM rsync as systemd

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

COPY --from=sources-downloader /sources/downloads/systemd /sources/downloads/systemd
ENV CFLAGS="-D __UAPI_DEF_ETHHDR=0 -D _LARGEFILE64_SOURCE"
RUN rm -fv /bin/sh && ln -s /bin/bash /bin/sh && mkdir -p /sources && cd /sources/downloads/systemd && mkdir -p /systemd && python3 -m pip install meson ninja jinja2 && mkdir -p build && cd       build && /usr/bin/meson setup .. \
      --prefix=/usr           \
      --buildtype=release     \
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
      -D docdir=/usr/share/doc/systemd-${SYSTEMD_VERSION} 2>&1 && ninja 2>&1 && \
     DESTDIR=/systemd ninja install && ninja install

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

## Cleanup

# We don't need headers
RUN rm -rf /skeleton/usr/include

FROM quay.io/luet/base:0.36.2 AS luet-base

## Install kernel
FROM alpine AS luet-kernel
COPY --from=luet-base /usr/bin/luet /usr/bin/luet
RUN mkdir -p /etc/luet/repos.conf.d/
RUN luet repo add -y kairos --url quay.io/kairos/packages --type docker
RUN luet repo update
RUN luet install -y kernels/linux --system-target /kernel

## Immucore for initramfs
FROM alpine AS immucore
RUN wget https://github.com/kairos-io/immucore/releases/download/v0.11.3/immucore-v0.11.3-linux-amd64.tar.gz
RUN tar xvf immucore-v0.11.3-linux-amd64.tar.gz
RUN mv immucore /immucore
RUN chmod +x /immucore

# Agent
FROM alpine AS kairos-agent
RUN wget https://github.com/kairos-io/kairos-agent/releases/download/v2.25.0/kairos-agent-v2.25.0-linux-amd64.tar.gz
RUN tar xvf kairos-agent-v2.25.0-linux-amd64.tar.gz
RUN mv kairos-agent /kairos-agent
RUN chmod +x /kairos-agent

# Build thje initramfs
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
COPY --from=immucore /immucore /initramfs/bin/immucore
WORKDIR /initramfs
COPY files/init .
RUN find . | cpio -o -H newc > ../init.cpio

### Assemble the final image
FROM scratch AS stage2

COPY --from=stage2-merge /skeleton /
# This probably needs moving into a different place rather than here it shouldbe done under the skeleton? After building and installing it?
RUN busybox --install
COPY --from=luet-kernel /kernel/boot/vmlinuz /boot/vmlinuz
# Copy modules
COPY --from=luet-kernel /kernel/lib/modules/ /lib/modules/
COPY --from=initramfs-builder /init.cpio /boot/initramfs
COPY --from=kairos-agent /kairos-agent /usr/bin/kairos-agent
# workaround as we dont have the /system/oem files
RUN mkdir -p /system/oem/

### Run the final image for tests
FROM stage2 AS test2

SHELL ["/bin/bash", "-c"]

RUN ls -liah /
RUN curl --version
