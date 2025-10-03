## Hadron Linux

The foundational Linux for the cloud and the edge. Hadron is a minimal, from-scratch distro using vanilla components, engineered for trusted and flexible boot environments.

Stays close to upstream with `musl`, `systemd`, and `vanilla kernels` for modern, secure workloads.

It is ready for modern workloads: supports Trusted Boot (via USI/UKI) and standard boot (via Dracut/GRUB). Upgrades are managed via Kairos's agent for A/B style upgrades.

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
