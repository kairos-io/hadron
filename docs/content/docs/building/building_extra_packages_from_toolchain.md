---
title: "Building Extra Packages from Toolchain"
weight: 8
---

# Building Extra Packages from Toolchain

Hadron's Dockerfile builds many packages that are available in the toolchain but not included in the final production images. This guide explains how to build additional packages using the Hadron toolchain environment.

## Understanding the Toolchain

The Hadron build system provides a `toolchain` Docker target that contains a complete build environment with:

- Cross-compilation toolchain (mussel-based)
- All build dependencies and libraries
- Development tools (make, autoconf, automake, etc.)
- Pre-built packages and their headers
- Pre-defined ENV vars that setup CFLAGS,COMMON_CONFIGURE_ARGS,BUILD,HOST,TARGET, etc... for easy build

This toolchain environment allows you to build additional packages that match Hadron's build configuration and architecture.


## Building Packages Using the Toolchain

The recommended approach is to create a multi-stage Dockerfile that:
1. Uses the `toolchain` target as a build environment
2. Builds your package in that environment
3. Copies the built package into a new base Hadron image

### Basic Pattern

Here's the general pattern for building a new package:

```dockerfile
# Stage 1: Build the package using the toolchain
FROM toolchain AS build-env

# Download and extract the package source
RUN wget https://example.com/package-1.0.0.tar.xz
RUN tar xvf package-1.0.0.tar.xz
WORKDIR /package-1.0.0

# Configure and build
RUN ./configure ${COMMON_CONFIGURE_ARGS}$
RUN make -j$(nproc)
RUN make install DESTDIR=/NewPackage

# Stage 2: Create Hadron image with the new package
FROM hadron AS default

# Copy the built package into the Hadron image
COPY --from=build-env /NewPackage /
```


### Building Your Custom Image

Save this to a file (e.g., `Dockerfile.custom`) and build:

```bash
# Build your custom Hadron image with the new package
docker build -f Dockerfile.custom -t hadron-with-package .
```

This creates a new Hadron image that includes your built package.

## Real example: Building strace

`strace` is a useful debugging tool. Here's how to build it and add it to a Hadron image:

```dockerfile
# Stage 1: Build strace using the toolchain
FROM hadron-toolchain AS build-env

ARG STRACE_VERSION=6.16

# Download and extract strace
RUN curl https://strace.io/files/${STRACE_VERSION}/strace-${STRACE_VERSION}.tar.xz -o strace.tar.xz
RUN tar xf strace.tar.xz
WORKDIR /strace-${STRACE_VERSION}
# Configure and build
RUN ./configure ${COMMON_CONFIGURE_ARGS} --enable-mpers=check --disable-dependency-tracking


RUN make -j$(nproc)
RUN make install DESTDIR=/strace

# Stage 2: Create Hadron image with strace
FROM hadron AS default

# Copy strace into the Hadron image
COPY --from=build-env /strace /
RUN strace --version
```

Build the image:

```bash
$ docker build -f Dockerfile.strace -t hadron-strace . 
[+] Building 0.1s (15/15) FINISHED                                                                     docker:default
 => [internal] load build definition from Dockerfile.strace                                                      0.0s
 => => transferring dockerfile: 621B                                                                             0.0s
 => [internal] load metadata for docker.io/library/hadron:latest                                                 0.0s
 => [internal] load metadata for docker.io/library/hadron-toolchain:latest                                       0.0s
 => [internal] load .dockerignore                                                                                0.0s
 => => transferring context: 2B                                                                                  0.0s
 => [build-env 1/7] FROM docker.io/library/hadron-toolchain:latest                                               0.0s
 => [default 1/3] FROM docker.io/library/hadron:latest                                                           0.0s
 => CACHED [build-env 2/7] RUN curl https://strace.io/files/6.16/strace-6.16.tar.xz -o strace.tar.xz             0.0s
 => CACHED [build-env 3/7] RUN tar xf strace.tar.xz                                                              0.0s
 => CACHED [build-env 4/7] WORKDIR /strace-6.16                                                                  0.0s
 => CACHED [build-env 5/7] RUN ./configure --quiet --prefix=/usr --host=x86_64-hadron-linux-musl --build=x86_64  0.0s
 => CACHED [build-env 6/7] RUN make -j$(nproc)                                                                   0.0s
 => CACHED [build-env 7/7] RUN make install DESTDIR=/strace                                                      0.0s
 => CACHED [default 2/3] COPY --from=build-env /strace /                                                         0.0s
 => CACHED [default 3/3] RUN strace --version                                                                    0.0s
 => exporting to image                                                                                           0.0s
 => => exporting layers                                                                                          0.0s
 => => writing image sha256:8f1057a2b18f2185c7fc3ebd95cc69537d670fa83c448d82c625bb562146bb56                     0.0s
 => => naming to docker.io/library/hadron-strace    
```

Now you have a Hadron image with `strace` included!

```
$ docker run -it --rm --entrypoint strace hadron-strace --version
strace -- version 6.16
Copyright (c) 1991-2025 The strace developers <https://strace.io>.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

Optional features enabled: no-m32-mpers no-mx32-mpers
```


*Note* Some packages may need patches for musl compatibility


## Using Your Custom Image

After building with the multi-stage Dockerfile approach, you'll have a complete Hadron image with your package included. You can use it just like the standard Hadron image to build an image with Kairos by setting the `IMAGE_NAME` to point to our custom Hadron image:

```bash
$ make build-kairos IMAGE_NAME=hadron-strace
Building Kairos image...
Kairos image built successfully

$ docker run -it --rm --entrypoint strace hadron-init --version
strace -- version 6.16
Copyright (c) 1991-2025 The strace developers <https://strace.io>.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

Optional features enabled: no-m32-mpers no-mx32-mpers

```

The package is fully integrated into the image, so all binaries, libraries, and man pages are in their standard locations.


### Build Environment Variables

The toolchain provides these important environment variables:
- `VENDOR`: `hadron`
- `ARCH`: `x86-64`
- `BUILD_ARCH`: `x86_64`
- `TARGET`: `x86_64-hadron-linux-musl`
- `BUILD`: `x86_64-pc-linux-musl`
- `COMMON_CONFIGURE_ARGS`: `--quiet --prefix=/usr --host=x86_64-hadron-linux-musl --build=x86_64-pc-linux-musl --enable-lto --enable-shared --disable-static`
- `CFLAGS`: `-Os -pipe -fomit-frame-pointer -fno-unroll-loops -fno-asynchronous-unwind-tables`


It also provides a host of standard build tools: `make`, `gcc`, `g++`, `autoconf`, `automake`, etc.

You can check available tools in the toolchain:

```bash
$ docker run --rm hadron-toolchain which gcc
/usr/bin/gcc

$ docker run --rm hadron-toolchain gcc --version
gcc (GCC) 14.3.0
Copyright (C) 2024 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

```