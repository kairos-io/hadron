---
title: "Common building examples"
weight: 3
---



# Common Build Examples

#### Build Everything (Default - Trusted Boot)

```bash
# Build OCI images and ISO in one command
make build
```

This builds the Hadron OCI image, Kairos OCI image, and creates a Trusted Boot ISO.

#### Build GRUB-based Image (Non-Trusted Boot)

```bash
# Build everything with GRUB bootloader
make build BOOTLOADER=grub
```

This builds the OCI images with GRUB configuration and creates a GRUB ISO.

#### Build Step by Step

If you want to build in separate steps:

```bash
# Step 1: Build Hadron OCI image
make build-hadron

# Step 2: Build Kairos OCI image (requires Hadron)
make build-kairos

# Step 3: Build ISO (requires both OCI images)
make build-iso
```

#### Build ISO Only (After OCI Images Exist)

If you've already built the OCI images and just want to rebuild the ISO:

```bash
# Build ISO based on BOOTLOADER variable (default: systemd/Trusted Boot)
make build-iso

# Or explicitly build Trusted Boot ISO
make trusted-iso

# Or explicitly build GRUB ISO
make grub-iso
```

#### Build with Custom Version

```bash
make build VERSION=v2.0.0
```

#### Build with Production Keys

```bash
# Build everything with production keys
make build KEYS_DIR=/secure/path/to/production/keys VERSION=v1.0.0

# Or rebuild just the ISO with production keys (after OCI images are built)
make trusted-iso KEYS_DIR=/secure/path/to/production/keys VERSION=v1.0.0
```

#### Build Only Hadron OCI Image

```bash
make build-hadron
```

#### Build with Verbose Output

```bash
make build PROGRESS=plain
```