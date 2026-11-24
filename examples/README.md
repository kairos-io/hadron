# Examples

- [hetzner-cloud](hetzner-cloud/): run Hadron-based Kairos nodes on Hetzner Cloud.
- [add-packages](add-packages/): Dockerfiles that build extra software on top of
  Hadron:
  - [Dockerfile.nvidia](add-packages/Dockerfile.nvidia): NVIDIA out-of-tree
    kernel modules plus the userspace driver libraries.
  - [Dockerfile.Thor](add-packages/Dockerfile.Thor): a kernel for the NVIDIA
    Jetson Thor, see [thor-gpu-operator.md](add-packages/thor-gpu-operator.md).

## Adding packages

Packages such as git, gpg, fwupd, qemu-guest-agent, drbd, zfs and
open-vm-tools are published as layers in
[kairos-io/hadron-layers](https://github.com/kairos-io/hadron-layers). Each one
is built from source with the Hadron toolchain and published as a minimal image
under `ghcr.io/kairos-io/hadron-layers/<name>`. The
[index](https://kairos-io.github.io/hadron-layers/) lists every layer with its
tags and pinned digests.

To add one to an image, copy it on top of Hadron:

```dockerfile
FROM ghcr.io/kairos-io/hadron:VERSION
COPY --from=ghcr.io/kairos-io/hadron-layers/git:latest / /
```
