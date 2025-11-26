---
title: "Core Components"
linkTitle: "Core Components"
weight: 2
description: |
    The fundamental components that make up Hadron: musl libc, systemd, and the Linux kernel
---

Hadron is built from three fundamental components: musl libc, systemd, and the Linux kernel. Each is compiled from upstream sources without modifications, ensuring compatibility and reducing maintenance burden.

## musl libc

Hadron uses [musl libc](https://musl.libc.org/) as its C standard library. This choice delivers several advantages over traditional glibc-based distributions.

### Why musl?

**Small Footprint**

musl is significantly smaller than glibc, resulting in:

- Smaller binary sizes
- Reduced memory usage
- Faster startup times
- Smaller container images

**Security**

musl's simpler codebase provides:

- Fewer lines of code to audit
- Reduced attack surface
- Clearer security boundaries
- Less complexity in critical paths

**Reproducibility**

musl offers:

- Deterministic builds
- Predictable behavior across environments
- Consistent linking behavior
- Better static linking support

**Upstream Alignment**

Hadron uses unpatched musl from upstream, ensuring:

- No downstream maintenance burden
- Direct access to upstream fixes
- Compatibility with upstream development
- No vendor-specific modifications

### Compatibility

musl provides a POSIX-compliant interface and maintains compatibility with most Linux software. While some applications may require glibc-specific features, the majority of software works correctly with musl.

The build system compiles musl from source, ensuring no downstream patches or modifications are applied.

## systemd

Hadron includes [systemd](https://systemd.io/) as its init system and service manager. The combination of musl + systemd is uncommon but intentional.

### Why systemd with musl?

**Modern APIs**

systemd provides standardized interfaces for:

- Service management
- Logging and journaling
- Network configuration
- Resource management
- Security policies

**Observability**

Built-in capabilities include:

- Structured logging via journald
- System and service metrics
- Service introspection via D-Bus
- Boot performance analysis

**Boot Performance**

systemd's parallel service startup and dependency management result in:

- Faster boot times
- Efficient resource utilization
- Better dependency resolution
- Predictable boot sequences

**Ecosystem Support**

systemd is widely supported by:

- Cloud-native tools (Kubernetes, container runtimes)
- Monitoring and observability platforms
- Service mesh implementations
- Modern Linux applications

### systemd Features in Hadron

The build process compiles systemd with musl support, enabling features like:

- **systemd-cryptsetup**: Encrypted partition management
- **systemd-networkd**: Network configuration
- **systemd-resolved**: DNS resolution
- **systemd-journald**: Logging
- **systemd-udevd**: Device management

All of these work without requiring glibc, delivering modern system management capabilities with a minimal footprint.

### Build Considerations

systemd is built with musl support, which requires careful configuration. The build system:

- Applies necessary compatibility patches from upstream
- Configures build options for musl compatibility
- Ensures all systemd features work correctly with musl
- Tests systemd functionality in the final image

## Linux Kernel

Hadron builds the Linux kernel from upstream sources with a minimal configuration.

### Kernel Build Process

The kernel build:

- Compiles from upstream kernel sources
- Uses minimal configuration (tinyconfig-based)
- Compiles only essential modules
- Uses zstd compression for modules to reduce size
- Generates kernel headers for compatibility
- Produces a compressed kernel image (bzImage)

### Kernel Customization

The kernel configuration can be customized per architecture:

- Enable or disable specific features
- Add hardware support
- Configure security options
- Optimize for specific use cases

Configuration files are stored in `files/kernel/` and can be modified to suit your needs.

### Module Management

Kernel modules are:

- Compiled with zstd compression
- Stripped of debug symbols
- Installed to `/lib/modules/`
- Managed via kmod (modprobe, insmod, etc.)

Only essential modules are included, keeping the kernel footprint small.

### Kernel Versioning

The kernel version is specified via build arguments:

```dockerfile
ARG KERNEL_VERSION=6.16.7
```

This allows you to:

- Pin specific kernel versions
- Test with different kernel versions
- Track kernel updates
- Maintain compatibility

## Component Integration

These three components work together to provide a complete Linux system:

**musl** provides the system call interface and standard library, enabling applications to interact with the kernel.

**systemd** manages the boot process, services, and system resources, providing a modern foundation for running workloads.

**Linux kernel** provides hardware abstraction, process management, and system services.

Together, they form a minimal but complete operating system suitable for cloud-native and edge deployments.

## Upstream Alignment

All components are built from upstream sources without modifications:

- **No downstream patches**: Hadron uses vanilla upstream code
- **Direct updates**: New upstream releases can be integrated directly
- **Reduced maintenance**: No patch management or backporting
- **Better compatibility**: Aligns with upstream development

This approach ensures Hadron stays current with upstream development while maintaining a minimal maintenance burden.

## See Also

- [Build System](/docs/architecture/build-system/) - How components are built
- [Boot Architecture](/docs/architecture/boot/) - How components work together at boot
- [Kairos Integration](https://kairos.io) - Using Hadron components with Kairos

