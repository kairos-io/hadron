---
title: "Quickstart"
weight: 1
---

# Building Hadron

Building Hadron requires only Docker on your build system. We provide a Makefile for ease of use, but you can also build directly with Docker if you prefer.

### Prerequisites

- **Docker**: Required for building Hadron images
- **Make** (optional): For using the provided Makefile

# Quick Start

The simplest way to build Hadron is using the Makefile:

```bash
make build
```

This will build the Hadron OCI image, the Kairos OCI image, and create a bootable ISO image using the default Trusted Boot configuration. Everything is built in one command.

## Building with Makefile

The Makefile provides several targets and configuration options to customize your build.

The build process consists of three main stages:

1. **`build-hadron`**: Builds the Hadron base OCI image
2. **`build-kairos`**: Builds the Kairos OCI image on top of Hadron (requires Hadron image)
3. **`build-iso`**: Creates a bootable ISO from the OCI images (requires Hadron+Kairos OCI image)

The **`build`** target runs all three stages in sequence, which is the recommended way to build everything.

### Available Targets

- **`build`**: Builds the Hadron+Kairos OCI images and the ISO image (complete build workflow)
- **`build-hadron`**: Builds only the Hadron OCI image
- **`build-kairos`**: Builds the Hadron+Kairos OCI images (builds Hadron first, then Kairos on top)
- **`build-iso`**: Builds the GRUB or Trusted Boot ISO image based on the `BOOTLOADER` variable. Expects the Hadron+Kairos OCI images to be built already.
- **`trusted-iso`**: Builds a Trusted Boot ISO image with Secure Boot signing. Expects the Hadron+Kairos OCI images to be built already.
- **`grub-iso`**: Builds a GRUB-based ISO image (non-trusted boot). Expects the Hadron+Kairos OCI images to be built already.
- **`help`**: Shows all available targets and configuration options

### Configuration Variables

The Makefile supports several variables to customize the build process:

| Variable | Default | Possible Values | Description |
|----------|---------|----------------|-------------|
| `BOOTLOADER` | `systemd` | `systemd`, `grub` | Controls which bootloader to use. `systemd` uses systemd-boot for Trusted Boot with Secure Boot support. `grub` uses GRUB with dracut for traditional boot (no Secure Boot). |
| `VERSION` | `v0.0.1` | Semver string | Sets the version of the generated Kairos+Hadron image. Used in the final ISO filename and metadata. Typically semantic versioning like `v1.0.0`. |
| `HADRON_VERSION` | `Git tag + dirty` | Semver string | Automatically set from git tags. Represents the version of the Hadron base image itself. Typically don't need to set manually. |
| `IMAGE_NAME` | `hadron` | Any string | The name of the Docker image for the Hadron base image. |
| `INIT_IMAGE_NAME` | `hadron-init` | Any string | The name of the Docker image for the Kairos image built on top of Hadron. |
| `KEYS_DIR` | `Test keys` | Path to directory | Directory containing the keys for Trusted Boot image signing. **⚠️ Warning**: Default keys are **INSECURE** and should **NOT** be used in production. Required keys: `tpm2-pcr-private.pem`, `db.key`, `db.pem`, `db.auth`, `KEK.auth`, `PK.auth`. |
| `PROGRESS` | `none` | `auto`, `plain`, `tty`, `none` | Docker build progress output style. |

**Examples:**

```bash
# Build with Trusted Boot (default)
make build

# Build with GRUB bootloader
make build BOOTLOADER=grub

# Build with custom version
make build VERSION=v1.2.3

# Build with production keys
make build KEYS_DIR=/path/to/secure/keys VERSION=v1.0.0

# Build with verbose output
make build PROGRESS=plain

```

## Build Output

### Image Names

After building, you'll have Docker images:
- `hadron` (or `IMAGE_NAME`): The Hadron base image
- `hadron-init` (or `INIT_IMAGE_NAME`): The Kairos image with Hadron

### ISO Files

ISO files are created in the `build/` directory with names like:
- Trusted Boot: `kairos-hadron-<HADRON_VERSION>-core-$ARCH-generic-<VERSION>-uki.iso`
- GRUB: `kairos-hadron-<HADRON_VERSION>-core-$ARCH-generic-<VERSION>.iso`

### Finding Your ISO

After building, the Makefile will print the location:

```bash
$ make build
...
Trusted Boot ISO image built successfully at build/kairos-hadron-v0.0.1-core-amd64-generic-v0.0.1-uki.iso
```

Or find it manually:

```bash
find build -name "*.iso"
```


## Next Steps

After building, you may want to:
- [Building Extra Packages from the Toolchain image](./building_extra_packages_from_toolchain): Learn how to build additional packages
- [Learn more about Kairos](https://kairos.io/docs/): Learn about all the functionality that Kairos brings into Hadron
