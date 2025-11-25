---
title: "Quickstart"
menu:
  main:
    weight: 10
weight: 1
---

## Prerequisites

Before building Hadron, ensure you have [Docker Engine](https://docs.docker.com/engine/install/) installed.

## Building Hadron Using Make

### Installing Make

Ensure you have `make` installed.

{{< tabpane >}}
{{< tab header="apt" lang="bash" >}}
# Debian, Ubuntu
sudo apt install make
{{< /tab >}}
{{< tab header="dnf" lang="bash" >}}
# Fedora, RHEL derivatives
sudo dnf install make
{{< /tab >}}
{{< tab header="zypper" lang="bash" >}}
# openSUSE, SUSE
sudo zypper install make
{{< /tab >}}
{{< tab header="apk" lang="bash" >}}
# Alpine
apk add make
{{< /tab >}}
{{< tab header="pacman" lang="bash" >}}
# Arch
sudo pacman -S make
{{< /tab >}}
{{< /tabpane >}}

### Build Command

The simplest way to build Hadron is using the Makefile:

```bash
make build
```

This will pull the Hadron image, build the Kairos+Hadron OCI image, and create a bootable ISO image using the default Trusted Boot configuration. Everything is built in one command.

```bash
$ make build                               
Pulling base Hadron image from ghcr.io/kairos-io/hadron:main...
main: Pulling from kairos-io/hadron
Digest: sha256:a6924c87ceebff059b0ddf48245c50d9ae61ebaca47c46dfe66f908fbc7615be
Status: Image is up to date for ghcr.io/kairos-io/hadron:main
ghcr.io/kairos-io/hadron:main
Building Kairos image...
Kairos image built successfully
Building Trusted Boot ISO image...
2025-11-24T09:53:26Z INF [1] Extracting image to a temporary directory
2025-11-24T09:53:26Z INF [1] Copying hadron-init:latest source to /tmp/auroraboot-build-uki-3859643668
2025-11-24T09:53:27Z INF [1] Finished copying hadron-init:latest into /tmp/auroraboot-build-uki-3859643668
2025-11-24T09:53:27Z INF [1] Creating additional directories in the rootfs
2025-11-24T09:53:27Z INF [1] Copying kernel
2025-11-24T09:53:27Z INF [1] Creating an initramfs file
2025-11-24T09:53:29Z INF [1] Running ukify for cmdline: Kairos: console=ttyS0 console=tty1 net.ifnames=1 rd.immucore.oemlabel=COS_OEM rd.immucore.oemtimeout=2 rd.immucore.uki selinux=0 panic=5 rd.shell=0 systemd.crash_reboot=yes install-mode
2025-11-24T09:53:29Z INF [1] Generating: norole.efi
2025/11/24 09:53:29 INFO Signing systemd-boot path=/tmp/auroraboot-build-uki-3859643668/usr/lib/systemd/boot/efi/systemd-bootx64.efi
2025/11/24 09:53:29 INFO Signed systemd-boot path=BOOTX64.EFI
2025/11/24 09:53:29 INFO Generating UKI sections
2025/11/24 09:53:29 INFO Generating PCR measurements
2025/11/24 09:53:29 INFO Generating signed policy per profile
2025/11/24 09:53:29 INFO Generated UKI sections
2025/11/24 09:53:29 INFO Assembling UKI
2025/11/24 09:53:29 INFO Assembled UKI
2025/11/24 09:53:29 INFO Signing UKI
2025/11/24 09:53:30 INFO Signed UKI at norole.efi
2025-11-24T09:53:30Z INF [1] Creating kairos and loader conf files
2025-11-24T09:53:30Z INF [1] Creating base config file with profile 0
2025-11-24T09:53:30Z INF [1] Calculating the size of the img file
2025-11-24T09:53:30Z INF [1] Creating the img file with size: 95Mb
2025-11-24T09:53:30Z INF [1] Created image: /tmp/auroraboot-iso-dir-3496997432/efiboot.img
2025-11-24T09:53:30Z INF [1] Creating directories in the img file
2025-11-24T09:53:30Z INF [1] Copying files in the img file
2025-11-24T09:53:30Z INF [1] Creating the iso files with xorriso
2025-11-24T09:53:30Z INF [1] Done building iso at: /output/
Trusted Boot ISO image built successfully at build/kairos-hadron-v0.0.1-beta1-8-gbff906b-dirty-core-amd64-generic-v0.0.1.iso build/kairos-hadron-v0.0.1-beta1-8-gbff906b-dirty-core-amd64-generic-v0.0.1-uki.iso

```

If you need to build a grub-based ISO (non-trusted boot), you can run:

```bash
make build BOOTLOADER=grub
```

And that will build the Hadron+Kairos OCI images and create a GRUB-based ISO image instead.

### Using a different Hadron image as base

By default, the Makefile pulls the `main` branch of the Hadron image. You can specify a different image altogether by using the `IMAGE_NAME` variable:

```bash
make build IMAGE_NAME=ghcr.io/kairos-io/hadron:$VERSION
```

or for grub bootloader:

```bash
make build IMAGE_NAME=ghcr.io/kairos-io/hadron-grub:$VERSION
```

## Building Hadron Using Docker

If you prefer not to use the Makefile, you can build directly with Docker commands.

Pull the Hadron base image:

```bash
docker pull ghcr.io/kairos-io/hadron:$VERSION
```

Build the Kairos+Hadron OCI image (we provide a Dockefile.init for this):

```bash
docker build -t $MYTAG -f Dockerfile.init --build-arg BASE_IMAGE=ghcr.io/kairos-io/hadron:$VERSION --build-arg VERSION=$VERSION .
```

**Note**: Replace `$MYTAG` and `$VERSION` with your desired image tag and version.

Then build the ISO image using the `auroraboot` image:

```bash
docker run -v /var/run/docker.sock:/var/run/docker.sock \
	-v ${PWD}/build/:/output \
	-v ${KEYS_DIR}:/keys \
	quay.io/kairos/auroraboot:v0.14.0-beta1 \
	build-uki \
	--output-dir /output/ \
	--public-keys /keys \
	--tpm-pcr-private-key /keys/tpm2-pcr-private.pem \
	--sb-key /keys/db.key \
	--sb-cert /keys/db.pem \
	--output-type iso \
	--sdboot-in-source \
	docker:$MYTAG
```

**Note**: Make sure to replace `${KEYS_DIR}` with the path to your keys directory, and `$MYTAG` with the tag of the Kairos+Hadron OCI image you built earlier.
See the [Trusted Boot documentation](/docs/building/trusted-grub) for more details on the required keys.

This will generate a Trusted Boot ISO image in the `build/` directory.


## Next Steps

After building, you may want to:
- [Building Extra Packages from the Toolchain image](/docs/building/building_extra_packages_from_toolchain): Learn how to build additional packages
- [Learn more about Kairos](https://kairos.io/docs/): Learn about all the functionality that Kairos brings into Hadron
- [Build Hadron from Scratch](/docs/building/building-scratch): Learn how to build Hadron step-by-step from source