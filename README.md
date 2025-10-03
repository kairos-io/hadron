## Hadron Linux

Hadron is a a lightweight Cloud-Native Linux Distribution built from scratch.

What it makes Hadron so special? Hadron is built entirely from the ground-up in containers to run with Kairos and be as much close at upstream projects as possible: it uses musl, systemd and vanilla Linux Kernels. 

It is ready for modern workloads: supports Trusted Boot (via USI/UKI) and standard boot (via Dracut/GRUB).

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
