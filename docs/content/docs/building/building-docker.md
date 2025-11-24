---
title: "Building Hadron from Scratch with Docker"
weight: 3
---

If you prefer not to use the Makefile, you can build directly with Docker commands.

### Build Hadron Base Image

```bash
docker build \
  --build-arg VERSION=$(git describe --tags --always --dirty) \
  --build-arg BOOTLOADER=systemd \
  -t hadron \
  --target default .
```

### Build Kairos Image

**Note**: This requires the Hadron image to exist first.

```bash
docker build \
  -t hadron-init \
  -f Dockerfile.init \
  --build-arg BASE_IMAGE=hadron \
  --build-arg VERSION=v0.0.1 .
```

### Build Trusted Boot ISO

```bash

docker run \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ${PWD}/build/:/output \
  -v ${PWD}/tests/assets/keys:/keys \
  quay.io/kairos/auroraboot:v0.14.0-beta1 \
  build-uki \
  --output-dir /output/ \
  --public-keys /keys \
  --tpm-pcr-private-key /keys/tpm2-pcr-private.pem \
  --sb-key /keys/db.key \
  --sb-cert /keys/db.pem \
  --output-type iso \
  --sdboot-in-source \
  docker:hadron-init
```

### Build GRUB ISO

```bash
docker run \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ${PWD}/build/:/output \
  quay.io/kairos/auroraboot:v0.14.0-beta1 \
  build-iso \
  --output /output/ \
  docker:hadron-init
```