## Hadron Linux

<img width="250" align="left" alt="logo" src="https://github.com/user-attachments/assets/d9c8b765-191b-401e-a360-1164faa9ba2c" />

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

Hadron is built from scratch with a focus on minimalism and staying close to upstream sources:

- **Core Components**: Built on `musl` libc, `systemd` init system, and vanilla Linux kernels
- **Boot Methods**: Supports both Trusted Boot (via USI/UKI) and standard boot (via Dracut/GRUB)
- **Upgrade System**: Managed via Kairos agent for A/B style atomic upgrades
- **Upstream Alignment**: Minimal patches, maximum compatibility with upstream projects

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

## License

Apache 2.0

## Acknowledgements

- https://github.com/firasuke/mussel For making things even easier than musl-cross-make with mussel. It was so plug-n-play that felt like a really nice experience right from the start.
- https://github.com/openembedded/openembedded-core/tree/master/meta/recipes-core/systemd which makes possible to build systemd on top of musl
- https://github.com/mocaccinoOS/mocaccino-micro For inspiration on how to build a musl system from scratch
