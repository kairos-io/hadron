## Hadron Linux

<img width="200" align="left" alt="logo" src="./docs/static/images/hadron-logo-with-text.jpg" />

**The foundational Linux distribution for the cloud and the edge.**

Hadron delivers a minimal, trustworthy operating system built from the ground up with vanilla upstream components. Engineered for security, flexibility, and reliability.

Hadron is Engineered by [Spectro Cloud](https://www.spectrocloud.com) from the [Kairos](https://kairos.io) team.

### Why Hadron?

- **Minimal & Lean**: Bare essentials only—no bloat, just what you need
- **Trusted Boot**: Secure boot environments with modern security standards
- **Upstream First**: Built with vanilla components, staying close to upstream
- **Edge & Cloud Ready**: Optimized for both cloud workloads and edge deployments
- **Seamless Updates**: A/B upgrade capabilities for zero-downtime operations

## Architecture

Hadron is a Linux Distribution built from scratch with a focus on minimalism and staying close to upstream sources:

- **Core Components**: Built on `musl` libc, `systemd` init system, and vanilla Linux kernels
- **Boot Methods**: Supports both Trusted Boot (via USI/UKI) and standard boot (via Dracut/GRUB)
- **Upgrade System**: Managed via Kairos agent for A/B style atomic upgrades
- **Upstream Alignment**: Minimal patches, maximum compatibility with upstream projects
- **Simple and no vendor-lock-in**: Hadron doesn't ship a package manager by default, and it's not based on any other Linux distribution. You can build packages on top of Hadron, or use the package manager you like.

## Development

To build locally the image, you just need to have Docker installed, clone the repository and run:

```
make build
```

To create an ISO, you can:

```
make devel-iso
```

And you can run it in a VM with:

```
make run-qemu
```

### Building Kairos Images

**Note**: The following examples are for testing purposes only. The Dockerfile used for building Kairos images is automatically fetched from the [kairos repository](https://github.com/kairos-io/kairos) and should not be modified locally.

#### Building a Core Kairos Image

To build a core Kairos image (without Kubernetes distribution) based on Hadron:

```bash
# Pull the base Hadron image and build the Kairos image
make pull-image build-kairos BOOTLOADER=grub VERSION=v0.0.1

# Or for Trusted Boot:
make pull-image build-kairos BOOTLOADER=systemd VERSION=v0.0.1
```

This will:
- Fetch the latest Dockerfile from the kairos repository
- Build a core Kairos image named `hadron-init` based on the Hadron base image
- Use the specified bootloader (grub or systemd) and version

#### Building a Standard Image with Kubernetes

To build a standard image with a Kubernetes distribution (e.g., k3s or k0s):

```bash
# Build with k3s
make pull-image build-kairos BOOTLOADER=grub VERSION=v0.0.1 KUBERNETES_DISTRO=k3s

# Build with k0s
make pull-image build-kairos BOOTLOADER=grub VERSION=v0.0.1 KUBERNETES_DISTRO=k0s

# Optionally specify Kubernetes version
make pull-image build-kairos BOOTLOADER=grub VERSION=v0.0.1 KUBERNETES_DISTRO=k3s KUBERNETES_VERSION=v1.28.0
```

After building the Kairos image, you can create an ISO:

```bash
# For GRUB bootloader
make grub-iso

# For Trusted Boot
make trusted-iso
```

## License

Apache 2.0

## Acknowledgements

- https://github.com/firasuke/mussel For making things even easier than musl-cross-make with mussel. It was so plug-n-play that felt like a really nice experience right from the start.
- https://github.com/openembedded/openembedded-core/tree/master/meta/recipes-core/systemd which makes possible to build systemd on top of musl
- https://github.com/mocaccinoOS/mocaccino-micro For inspiration on how to build a musl system from scratch
