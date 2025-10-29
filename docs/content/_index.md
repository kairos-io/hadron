---
title: "Hadron Linux"
description: "The foundational Linux distribution for the cloud and the edge"
---

<img width="250" alt="logo" src="https://github.com/user-attachments/assets/d9c8b765-191b-401e-a360-1164faa9ba2c" />

**The foundational Linux distribution for the cloud and the edge.**

Hadron delivers a minimal, trustworthy operating system built from the ground up with vanilla upstream components. Engineered for security, flexibility, and reliability.

Hadron is Engineered by [Spectro Cloud](https://www.spectrocloud.com) from the [Kairos](https://kairos.io) team.

## Why Hadron?

- **Minimal & Lean**: Bare essentials only—no bloat, just what you need
- **Trusted Boot**: Secure boot environments with modern security standards
- **Upstream First**: Built with vanilla components, staying close to upstream
- **Edge & Cloud Ready**: Optimized for both cloud workloads and edge deployments
- **Seamless Updates**: A/B upgrade capabilities for zero-downtime operations

## Architecture

Hadron is built from scratch with a focus on minimalism and staying close to upstream sources:

- **Core Components**: Built on `musl` libc, `systemd` init system, and vanilla Linux kernels
- **Boot Methods**: Supports both Trusted Boot (via USI/UKI) and standard boot (via Dracut/GRUB)
- **Upgrade System**: Managed via Kairos agent for A/B style atomic upgrades
- **Upstream Alignment**: Minimal patches, maximum compatibility with upstream projects

## Development

To build locally the image, you just need to have Docker installed, clone the repository and run:

```bash
make build
```

To create an ISO, you can:

```bash
make iso
```

And you can run it in a VM with:

```bash
make run-qemu
```

## License

Apache 2.0

