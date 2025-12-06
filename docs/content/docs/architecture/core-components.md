---
title: "Core Components"
linkTitle: "Core Components"
weight: 2
description: |
    The fundamental components that make up Hadron: musl libc, systemd, and the Linux kernel
---

Hadron is built from three fundamental components: musl libc, systemd, and the Linux kernel. Each is compiled from upstream sources, ensuring compatibility and reducing maintenance burden.

## musl libc

Hadron uses [musl libc](https://musl.libc.org/) as its C standard library. This choice delivers several advantages over traditional glibc-based distributions.

### Why musl over glibc?

C standard libraries are wrappers around the system calls of the Linux kernel, providing the interface between applications and the operating system. Hadron chose musl over glibc for several critical reasons:

**Small Footprint**

musl is significantly smaller than glibc, resulting in:

- Smaller binary sizes
- Reduced memory usage
- Faster startup times
- Smaller container images

This minimal footprint aligns with Hadron's philosophy of "bare essentials only" and makes it ideal for cloud and edge deployments where resource efficiency matters.

**Security**

musl's simpler codebase provides:

- Fewer lines of code to audit
- Reduced attack surface
- Clearer security boundaries
- Less complexity in critical paths

The reduced complexity means fewer potential vulnerabilities and easier security auditing, critical for a foundational distribution.

**Reproducibility**

musl offers:

- Deterministic builds
- Predictable behavior across environments
- Consistent linking behavior
- Better static linking support

This reproducibility is essential for immutable infrastructure where every node must be identical and predictable.

**Upstream Alignment**

Hadron uses musl from upstream, ensuring:

- Minimal downstream maintenance burden
- Direct access to upstream fixes
- Compatibility with upstream development
- Minimal vendor-specific modifications

This upstream-first approach reduces maintenance overhead and ensures Hadron stays current with upstream improvements.

**Why Not glibc?**

While glibc is the most common C library in Linux distributions, it comes with trade-offs that don't align with Hadron's goals:

- **Larger footprint**: glibc is significantly larger, increasing image size and memory usage
- **More complexity**: The larger codebase increases maintenance burden and security surface
- **Less predictable**: glibc's behavior can vary more across environments
- **Vendor patches**: Most distributions carry extensive glibc patches, increasing maintenance

For a minimal, cloud-native distribution focused on security and reproducibility, musl is the clear choice.

### Compatibility

musl provides a POSIX-compliant interface and maintains compatibility with most Linux software. While some applications may require glibc-specific features, the majority of software works correctly with musl.

The build system compiles musl from source.

## systemd

Hadron includes [systemd](https://systemd.io/) as its init system and service manager. The combination of musl + systemd is uncommon but intentional.

### Why systemd with musl?

The combination of musl + systemd is uncommon but intentional. While most musl-based distributions (like Alpine) use simpler init systems, Hadron chose systemd for its modern capabilities and ecosystem alignment.

**Modern APIs**

systemd provides standardized interfaces for:

- Service management
- Logging and journaling
- Network configuration
- Resource management
- Security policies

These standardized APIs reduce the need for custom tooling and ensure compatibility with modern Linux applications and cloud-native workloads.

**Observability**

Built-in capabilities include:

- Structured logging via journald
- System and service metrics
- Service introspection via D-Bus
- Boot performance analysis

This built-in observability is essential for cloud-native deployments where monitoring and debugging are critical.

**Boot Performance**

systemd's parallel service startup and dependency management result in:

- Faster boot times
- Efficient resource utilization
- Better dependency resolution
- Predictable boot sequences

For edge and cloud deployments, fast and reliable boot times are essential.

**Ecosystem Support**

systemd is widely supported by:

- Cloud-native tools (Kubernetes, container runtimes)
- Monitoring and observability platforms
- Service mesh implementations
- Modern Linux applications

This ecosystem support ensures Hadron works seamlessly with the modern cloud-native stack.

**Why Not Simpler Init Systems?**

Alternatives like OpenRC (used by Alpine) or sysvinit are simpler and smaller, but they lack:

- **Modern service management**: Limited service lifecycle management capabilities
- **Built-in observability**: Requires additional tooling for logging and monitoring
- **Ecosystem integration**: Less support from cloud-native tools and platforms
- **Security features**: Fewer built-in security and resource management features

For a distribution targeting cloud-native and edge workloads, systemd's modern capabilities outweigh the additional complexity, especially when combined with musl's minimal footprint.

### systemd Features in Hadron

The build process compiles systemd with musl support, enabling systemd features without requiring glibc, delivering modern system management capabilities with a minimal footprint.

### Build Considerations

systemd is built with musl support, which requires careful configuration. The build system:

- Applies necessary compatibility patches from upstream
- Configures build options for musl compatibility
- Ensures all systemd features work correctly with musl
- Tests systemd functionality in the final image

## Linux Kernel

Hadron builds vanilla Linux kernels from upstream sources with a minimal configuration. This upstream-first approach ensures maximum compatibility and modern standards.

### Why Vanilla Upstream Kernels?

Hadron uses vanilla upstream kernels rather than distribution-specific kernels for several reasons:

**Upstream Alignment**

- **Maximum compatibility**: Vanilla kernels ensure compatibility with upstream development and standards
- **Modern features**: Direct access to latest kernel features and improvements
- **Reduced maintenance**: No need to maintain distribution-specific kernel patches
- **Better security**: Security fixes come directly from upstream without delay

**Minimal Configuration**

- **Small footprint**: Only essential features are compiled, reducing kernel size
- **Faster boot**: Minimal kernel reduces boot time and memory usage
- **Reduced attack surface**: Fewer compiled features mean fewer potential vulnerabilities
- **Customizable**: Configuration can be tailored per architecture and use case

**Why Not Distribution Kernels?**

Many distributions (like Ubuntu, Debian, RHEL) maintain heavily patched kernels with:

- **Vendor patches**: Extensive downstream patches that increase maintenance burden
- **Backported features**: Features backported from newer kernels, increasing complexity
- **Larger size**: More features compiled in by default
- **Slower updates**: Kernel updates tied to distribution release cycles

For Hadron's minimal, upstream-first philosophy, vanilla kernels provide the best balance of features, security, and maintainability.

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

All components are built from upstream sources:

- **Direct updates**: New upstream releases can be integrated directly
- **Reduced maintenance**: Minimal patch management or backporting
- **Better compatibility**: Aligns with upstream development

This approach ensures Hadron stays current with upstream development while maintaining a minimal maintenance burden.

## See Also

- [Build System](/docs/architecture/build-system/) - How components are built
- [Boot Architecture](/docs/architecture/boot/) - How components work together at boot
- [Kairos Integration](https://kairos.io) - Using Hadron components with Kairos

