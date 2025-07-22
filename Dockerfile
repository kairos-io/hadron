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
ENV VENDOR=${VENDOR}
ENV BUILD_ARCH=${BUILD_ARCH}
ENV ARCH=${ARCH}
ENV MUSSEL_VERSION=${MUSSEL_VERSION}
ENV JOBS=${JOBS}

RUN apk update && \
  apk add git bash wget bash perl build-base make patch busybox-static curl && git clone https://github.com/firasuke/mussel.git &&  \
  cd mussel && \
  git checkout ${MUSSEL_VERSION} -b build && \
  ./mussel ${ARCH} -k -l -o -p -s -T ${VENDOR}

ENV PATH=/mussel/toolchain/bin/:$PATH
ENV LC_ALL=POSIX
ENV TARGET=${BUILD_ARCH}-${VENDOR}-linux-musl
ENV BUILD=${BUILD_ARCH}-pc-linux-musl

FROM stage0 AS sources-downloader

ARG CURL_VERSION=8.5.0
ENV CURL_VERSION=${CURL_VERSION}

RUN mkdir -p /sources/downloads && cd /sources/downloads && wget http://curl.se/download/curl-${CURL_VERSION}.tar.gz 

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
RUN <<EOT bash
    wget https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz \
    https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2 \
    https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz \
    http://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2
    tar -xvf gcc-${GCC_VERSION}.tar.xz
    tar -xvf gmp-${GMP_VERSION}.tar.bz2
    tar -xvf mpc-${MPC_VERSION}.tar.gz
    tar -xvf mpfr-${MPFR_VERSION}.tar.bz2
EOT
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
   wget https://ftp.gnu.org/gnu/make/make-${MAKE_VERSION}.tar.gz

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
    wget https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz
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

## libressl
FROM stage1 AS libressl

ARG LIBRESSL_VERSION=4.1.0
ENV LIBRESSL_VERSION=${LIBRESSL_VERSION}

RUN mkdir /sources && cd /sources && wget http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${LIBRESSL_VERSION}.tar.gz && \
    tar -xvf libressl-${LIBRESSL_VERSION}.tar.gz && mv libressl-${LIBRESSL_VERSION} libressl && \
    cd libressl && mkdir -p /libressl && ./configure --disable-dependency-tracking ${COMMON_ARGS} && make DESTDIR=/libressl && \
    make DESTDIR=/libressl install && make install

## Busybox (from stage1, ready to be used in the final image)
FROM libressl AS busybox

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

FROM busybox AS curl

ARG CURL_VERSION=8.5.0
ENV CURL_VERSION=${CURL_VERSION}

COPY --from=sources-downloader /sources/downloads/curl-${CURL_VERSION}.tar.gz /sources/

RUN mkdir -p /sources && cd /sources && tar -xvf curl-${CURL_VERSION}.tar.gz && mv curl-${CURL_VERSION} curl && \
    cd curl && mkdir -p /curl && ./configure  ${COMMON_ARGS} --disable-dependency-tracking --enable-ipv6 \
    --enable-unix-sockets \
    --enable-static \
    --without-libidn \
    --without-libidn2 \
    --with-ssl \
    --with-nghttp2 \
    --disable-ldap \
    --with-pic \
    --without-libssh2 && make DESTDIR=/curl && \
    make DESTDIR=/curl install && make install

## autoconf
FROM stage1 AS autoconf

ARG AUTOCONF_VERSION=2.71
ENV AUTOCONF_VERSION=${AUTOCONF_VERSION}

RUN mkdir /sources && cd /sources && wget http://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VERSION}.tar.xz && \
    tar -xvf autoconf-${AUTOCONF_VERSION}.tar.xz && mv autoconf-${AUTOCONF_VERSION} autoconf && \
    cd autoconf && mkdir -p /autoconf && ./configure ${COMMON_ARGS} && make DESTDIR=/autoconf && \
    make DESTDIR=/autoconf install && make install

## automake
FROM stage1 AS automake

ARG AUTOMAKE_VERSION=1.16.5
ENV AUTOMAKE_VERSION=${AUTOMAKE_VERSION}

RUN mkdir /sources && cd /sources && wget http://ftp.gnu.org/gnu/automake/automake-${AUTOMAKE_VERSION}.tar.xz && \
    tar -xvf automake-${AUTOMAKE_VERSION}.tar.xz && mv automake-${AUTOMAKE_VERSION} automake && \
    cd automake && mkdir -p /automake && ./configure ${COMMON_ARGS} && make DESTDIR=/automake && \
    make DESTDIR=/automake install && make install


## m4 (from stage1, ready to be used in the final image)
FROM stage1 AS m4

ARG M4_VERSION=1.4.20
ENV M4_VERSION=${M4_VERSION}

RUN mkdir /sources && cd /sources && wget http://ftp.gnu.org/gnu/m4/m4-${M4_VERSION}.tar.xz && \
    tar -xvf m4-${M4_VERSION}.tar.xz && mv m4-${M4_VERSION} m4 && \
    cd m4 && mkdir -p /m4 && ./configure ${COMMON_ARGS} --disable-dependency-tracking && make DESTDIR=/m4 && \
    make DESTDIR=/m4 install && make install

## bash
FROM stage1 AS bash

ARG BASH_VERSION=5.3
ENV BASH_VERSION=${BASH_VERSION}

RUN mkdir /sources && cd /sources && wget http://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz && \
    tar -xvf bash-${BASH_VERSION}.tar.gz && mv bash-${BASH_VERSION} bash && \
    cd bash && mkdir -p /bash && ./configure ${COMMON_ARGS} \
    --build=${BUILD} \
    --host=${TARGET} \
    --prefix=/usr \
    --bindir=/bin \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --with-curses \
    --disable-nls \
    --enable-readline \
    --without-bash-malloc \
    --with-installed-readline && make y.tab.c && make builtins/libbuiltins.a && make && \
    mkdir -p /bash/etc/bash && \
    install -Dm644  /sources/bash-${BASH_VERSION}/bashrc /bash/etc/bash/bashrc && \
    install -Dm644  /sources/bash-${BASH_VERSION}/profile-bashrc.sh /bash/etc/profile.d/00-bashrc.sh && \
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

## CURL
COPY --from=curl /curl /curl
RUN rsync -aHAX --keep-dirlinks  /curl/. /skeleton/

## LibreSSL
COPY --from=libressl /libressl /libressl
RUN rsync -aHAX --keep-dirlinks  /libressl/. /skeleton/

## bash
COPY --from=bash /bash /bash
RUN rsync -aHAX --keep-dirlinks  /bash/. /skeleton/

### Assemble the final image
FROM scratch AS stage2

COPY --from=stage2-merge /skeleton /

### Run the final image for tests
FROM stage2 AS test2

SHELL ["/bin/sh", "-c"]

RUN ls -liah /
RUN curl --version