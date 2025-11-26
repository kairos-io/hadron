---
title: "Architecture Overview"
linkTitle: "Architecture"
icon: fa-regular fa-diagram-project
weight: 4
description: |
    Understanding Hadron's design and implementation
---

Hadron is a minimal Linux distribution built completely from scratch using a container-based build system. Unlike distributions derived from Ubuntu, Debian, or Alpine, Hadron is constructed from upstream sources with no downstream patches or modifications.

## Design Philosophy

Hadron is designed specifically for **immutable, image-based systems**. While Hadron itself is a standard Linux distribution, its minimal design and container-based distribution model make it an ideal foundation for immutable operating system workflows.

### Key Design Principles

**Minimal and Upstream-First**

Hadron includes only essential components needed to boot securely and run workloads. Every package is compiled from upstream sources without modifications, ensuring compatibility and reducing maintenance burden.

**Container-Based Distribution**

Hadron images are distributed as standard OCI container images. This allows you to:

- Store images in any container registry
- Version and tag images like application containers
- Inspect images with familiar container tools
- Integrate with existing container workflows

**musl + systemd Combination**

Hadron combines musl libc with systemd, an uncommon but intentional pairing:

- **musl**: Small, secure, reproducible C library ideal for cloud-native workloads
- **systemd**: Modern service management, observability, and ecosystem compatibility

This combination delivers a small footprint with modern system management capabilities.

## Architecture Components

### Build System

Hadron uses a multi-stage Docker build process that constructs the entire operating system from source. The build follows a Linux From Scratch (LFS) approach with modern containerization.

See the [Build System](/docs/architecture/build-system/) documentation for detailed information.

### Core Components

**musl libc**

Hadron uses musl as its C standard library, providing a small footprint, security benefits, and reproducible builds.

**systemd**

systemd serves as the init system and service manager, providing modern APIs, observability, and wide ecosystem support.

**Linux Kernel**

The kernel is built from upstream sources with minimal configuration, allowing customization per architecture while maintaining a small footprint.

See the [Core Components](/docs/architecture/core-components/) documentation for detailed information.

### Boot Architecture

Hadron supports two bootloader configurations:

- **GRUB**: Traditional bootloader with BIOS and UEFI support, used with dracut for initramfs generation
- **systemd-boot**: Modern bootloader for trusted boot scenarios, supporting Secure Boot and TPM-based measurements

See the [Boot Architecture](/docs/architecture/boot/) documentation for detailed information.

## Immutable System Design

Hadron is designed to be used in immutable, image-based systems. While Hadron itself is a standard Linux distribution, its architecture supports immutable workflows:

### Image-Based Distribution

All system components are packaged into container images. Updates are delivered as complete images rather than incremental package changes.

### Minimal Runtime Modifications

The base system is designed to minimize runtime changes, making it suitable for read-only root filesystems when used with appropriate tooling.

### System Extensions

Hadron supports systemd system extensions for runtime customization without modifying the base image.

## Lifecycle Management with Kairos

When paired with [Kairos](https://kairos.io), Hadron gains full immutable OS capabilities including:

- **Atomic A/B upgrades**: Zero-downtime system updates with automatic rollback
- **Image-based lifecycle**: Complete system state managed as container images
- **Trusted boot**: Secure Boot and TPM-based boot assessment
- **Automated recovery**: Automatic rollback on boot failures

Kairos provides the lifecycle management layer that transforms Hadron into a fully immutable operating system. See the [Kairos documentation](https://kairos.io) for details on using Hadron with Kairos.

## Container-Based Distribution

Hadron images are standard OCI container images, providing:

- **Standard format**: Compatible with any OCI registry
- **Build reproducibility**: Containerized builds ensure consistent results
- **Easy inspection**: Use familiar container tools to examine images

```bash
docker pull ghcr.io/kairos-io/hadron:main 
docker run -it --rm ghcr.io/kairos-io/hadron:main /bin/sh
```

## Security Features

### Minimal Attack Surface

By including only essential components, Hadron reduces the attack surface:

- Fewer packages mean fewer potential vulnerabilities
- No package manager reduces attack vectors
- Upstream sources minimize supply chain risks

### Trusted Boot Support

With systemd-boot, Hadron supports Secure Boot and TPM-based measurements for trusted boot scenarios.

### Default Hardening

The build system applies security hardening by default, including stripped binaries and minimal setuid binaries.

## See Also

- [Build System](/docs/architecture/build-system/) - Detailed build process documentation
- [Core Components](/docs/architecture/core-components/) - musl, systemd, and kernel details
- [Boot Architecture](/docs/architecture/boot/) - Bootloader configurations and trusted boot
- [Kairos](https://kairos.io) - Immutable OS lifecycle management with Hadron
