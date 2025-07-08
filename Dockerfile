## This is Dockerfile, that at the end of the process it builds a 
## small LFS system, starting from Alpine Linux.
## It uses mussel to build the system.

FROM alpine

ARG VENDOR="ukairos"
ARG ARCH="x86-64"
ARG BUILD_ARCH="x86_64"
ARG PACKAGE_VERSION="95dec40aee2077aa703b7abc7372ba4d34abb889"
ENV VENDOR=${VENDOR}
ENV BUILD_ARCH=${BUILD_ARCH}
ENV ARCH=${ARCH}
ENV PACKAGE_VERSION=${PACKAGE_VERSION}
ENV JOBS=${JOBS}

COPY ./config.mak ./config.mak
RUN apk update && \
  apk add git build-base make patch busybox-static curl && git clone https://github.com/firasuke/mussel.git &&  \
  cd mussel && \
  git checkout ${PACKAGE_VERSION} -b build && \
  ./mussel ${ARCH} -k -l -o -p -s -T ${VENDOR}

ENV PATH=/mussel/toolchain/bin/:$PATH
ENV LC_ALL=POSIX
#ENV SHELL=bash
ENV BUSYBOX_VERSION=1.37.0
ENV MAKE_VERSION=4.4

RUN mkdir /sources && \
   cd /sources && \
   wget https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 
   # && \
#   wget https://ftp.gnu.org/gnu/make/make-${MAKE_VERSION}.tar.gz

ENV TARGET=${BUILD_ARCH}-${VENDOR}-linux-musl

# Busybox
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
    make ARCH="${ARCH}" CROSS_COMPILE="${TARGET}-" CONFIG_PREFIX="/" install
    #cp -v examples/depmod.pl /mussel/toolchain/bin && \
    #chmod -v 755 /mussel/toolchain/bin/depmod.pl
