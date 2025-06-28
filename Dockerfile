## This is Dockerfile, that at the end of the process it builds a 
## small LFS system, starting from Alpine Linux.
## It uses musl-cross-make to build the system.

FROM alpine

ARG TARGET="x86_64-ukairos-linux-musl"
ARG ARCH="x86"
ARG CPU="x86-64"
ARG JOBS="20"
ARG MUSL_CROSS_MAKE_VERSION="6f3701d08137496d5aac479e3a3977b5ae993c1f"
ENV TARGET=${TARGET}
ENV ARCH=${ARCH}
ENV CPU=${CPU}
ENV MUSL_CROSS_MAKE_VERSION=${MUSL_CROSS_MAKE_VERSION}
ENV JOBS=${JOBS}

COPY ./config.mak ./config.mak
RUN apk update && \
  apk add git build-base make patch busybox-static curl && git clone https://github.com/richfelker/musl-cross-make &&  \
  cd musl-cross-make && \
  git checkout ${PACKAGE_VERSION} -b build && \
  cp -rf /config.mak ./config.mak && \
  mkdir -p /build && \
  mkdir -p output/bin && \
  make -j ${JOBS} && \
  make install && \
  ls -liah output && \
  PATH=$PATH:$PWD/output/bin:$PWD/output/$TARGET/bin make NATIVE=1 -j${JOBS} && \
  PATH=$PATH:$PWD/output/bin:$PWD/output/$TARGET/bin make NATIVE=1 install