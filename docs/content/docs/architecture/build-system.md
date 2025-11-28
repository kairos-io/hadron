---
title: "Build System"
linkTitle: "Build System"
weight: 1
description: |
    How Hadron is built from source using a container-based multi-stage build process
---

Hadron uses a multi-stage Docker build process that constructs the entire operating system from source. The build system follows a Linux From Scratch (LFS) approach, but with modern tooling and containerization.

## Multi-Stage Build Process

The build process is organized into distinct stages, each with a specific purpose:

### Stage 0: Cross-Compiler Toolchain

The foundation begins with building a cross-compiler toolchain using [mussel](https://github.com/firasuke/mussel), a tool designed for building minimal Linux systems. This stage:

- Creates a complete build environment targeting `x86_64-hadron-linux-musl`
- Builds GCC, binutils, and supporting libraries
- Establishes the base toolchain for all subsequent compilation

The toolchain is built in isolation, ensuring no contamination from the host system.

### Stage 1: Build Environment Assembly

Once the toolchain is ready, Stage 1 assembles a complete build environment by merging:

- GCC compiler and runtime libraries
- musl libc
- binutils (assembler, linker, etc.)
- make and other build utilities
- BusyBox for basic utilities during build

This environment is used to compile all subsequent packages in a consistent, reproducible manner.

### Stage 1.5: Package Compilation

Individual packages are built in parallel stages, each producing a self-contained installation directory. Packages are organized by dependencies:

**Core Libraries**
- musl libc
- zlib, zstd, lz4 (compression libraries)
- openssl (cryptography)
- libcap (capabilities)

**System Utilities**
- coreutils (ls, cp, mv, etc.)
- util-linux (mount, fdisk, etc.)
- bash and readline
- findutils, grep, diffutils

**Development Tools**
- gcc, binutils, make
- pkg-config
- autotools (autoconf, automake, libtool)

**System Services**
- systemd (init system)
- dbus (inter-process communication)
- pam (Pluggable Authentication Modules)
- shadow (user management)

Each package stage can run independently, allowing for parallel builds and better cache utilization.

### Stage 2: Final Image Assembly

The final stage merges all compiled packages into a single root filesystem. The build system:

- Strips binaries to reduce size
- Removes development headers and documentation
- Removes static libraries (only shared libraries are kept)
- Creates essential system directories
- Configures systemd presets
- Generates user accounts via systemd-sysusers

The result is a minimal, production-ready root filesystem.

## Parallel Source Downloads

To optimize build times, source code downloads happen in parallel with toolchain compilation. A dedicated `sources-downloader` stage:

- Fetches all required source tarballs
- Applies necessary patches
- Prepares sources for compilation

This runs simultaneously with the CPU-intensive toolchain build, reducing overall build time.

## Build Targets

The build system produces several targets:

**container**

Minimal base image with essential tools (bash, curl, coreutils, etc.). Suitable for container workloads or as a base for custom images.

**full-image-grub**

Complete bootable image with Standard Boot (BIOS) support. Works on legacy BIOS systems. Uses GRUB as the bootloader with dracut for initramfs generation.

**full-image-systemd**

Complete bootable image with Trusted Boot (UEFI Secure Boot) support. Requires UEFI firmware with Secure Boot enabled. Supports Secure Boot and TPM-based measurements. Uses systemd-boot as the bootloader.

**toolchain**

Reusable build environment for compiling custom packages. Includes all build tools and can be used as a base for extending Hadron.

## Build Customization

The build system is designed for customization. You can:

**Modify Package Versions**

Use build arguments to specify package versions:

```dockerfile
ARG KERNEL_VERSION=6.16.7
ARG SYSTEMD_VERSION=257.8
```

**Add Custom Packages**

Create additional build stages to include custom software:

```dockerfile
FROM stage1 AS custom-package
COPY --from=sources-downloader /sources/custom-package.tar.gz /sources/
# ... build and install custom package
```

**Adjust Kernel Configuration**

Modify kernel configuration files per architecture to enable or disable features.

**Extend Base Image**

Use the base container image as a starting point for your own Dockerfile, adding packages and configurations as needed.

## Build Reproducibility

The entire build process is containerized, ensuring:

- **Consistent builds**: Same inputs produce identical outputs
- **Environment isolation**: No dependency on host system configuration
- **Version control**: Build configuration is versioned and tracked
- **CI/CD integration**: Easy integration with automated build pipelines

## Build Optimization

Several optimizations reduce build time and image size:

**Parallel Compilation**

Packages are built in parallel where possible, utilizing multiple CPU cores.

**Layer Caching**

Docker layer caching ensures unchanged stages don't rebuild, significantly speeding up iterative development.

**Binary Stripping**

All binaries are stripped of debug symbols and unnecessary sections, reducing image size.

**Selective Inclusion**

Only runtime-necessary files are included in final images. Development headers, documentation, and static libraries are excluded.

## See Also

- [Core Components](/docs/architecture/core-components/) - What gets built
- [Boot Architecture](/docs/architecture/boot/) - Boot modes and trusted boot
- [Customization Guide](/docs/customization/) - Extending Hadron with custom packages

