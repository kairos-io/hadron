IMAGE_NAME ?= hadron
INIT_IMAGE_NAME ?= hadron-init
AURORA_IMAGE ?= quay.io/kairos/auroraboot:v0.14.0-beta1
TARGET ?= default
JOBS ?= $(shell nproc)
HADRON_VERSION ?= $(shell git describe --tags --always --dirty)
VERSION ?= v0.0.1
BOOTLOADER ?= systemd
KEYS_DIR ?= ${PWD}/tests/assets/keys
PROGRESS ?= none
PROGRESS_FLAG = --progress=${PROGRESS}

.DEFAULT_GOAL := help

.PHONY: targets
targets:
	@echo "Usage: make <target> <variable>=<value>"
	@echo "For example: make build BOOTLOADER=grub VERSION=v0.0.1"
	@echo "Available targets:"
	@echo "------------------------------------------------------------------------"
	@echo "build: Build the Hadron+Kairos OCI images and the ISO image"
	@echo "build-hadron: Build the Hadron OCI image"
	@echo "build-kairos: Build the Hadron+Kairos OCI images"
	@echo "build-iso: Build the GRUB or Trusted Boot ISO image based on the BOOTLOADER variable. Expects the Hadron+Kairos OCI images to be built already."
	@echo "grub-iso: Build the GRUB ISO image. Expects the Hadron+Kairos OCI images to be built already."
	@echo "trusted-iso: Build the Trusted Boot ISO image. Expects the Hadron+Kairos OCI images to be built already."

.PHONY: help
help: targets
	@echo "------------------------------------------------------------------------"
	@echo "The BOOTLOADER variable can be set to 'grub' or 'systemd'. The default is 'systemd' to build a Trusted Boot image."
	@echo "The VERSION variable can be set to the version of the generated kairos+hadrond image. The default is v0.0.1."
	@echo "The IMAGE_NAME variable can be set to the name of the Hadron image that its built. The default is 'hadron'."
	@echo "The INIT_IMAGE_NAME variable can be set to the name of the Kairos image builts from Hadron. The default is 'hadron-init'."
	@echo "The KEYS_DIR variable can be set to the directory containing the keys for the Trusted Boot image. The default is to use the keys that we use for testing, which are INSECURE and should not be used in production."
	@echo "------------------------------------------------------------------------"
	@echo "The expected keys in the KEYS_DIR are:"
	@echo " - tpm2-pcr-private.pem: The private key for the TPM2 measurements used for the Trusted Boot image"
	@echo " - db.key: The private key to sign the EFI files"
	@echo " - db.pem: The certificate to sign the EFI files"
	@echo " - db.auth, KEK.auth, PK.auth: The public authentication keys to inject into the EFI firmware"


.PHONY: build
build: build-hadron build-kairos build-iso

## This builds the Hadron image
build-hadron:
	@echo "Building Hadron image..."
	@docker build ${PROGRESS_FLAG} \
	--build-arg JOBS=${JOBS} \
	--build-arg VERSION=${HADRON_VERSION} \
	--build-arg BOOTLOADER=${BOOTLOADER} \
	-t ${IMAGE_NAME} \
	--target ${TARGET} .
	@echo "Hadron image built successfully"

## This builds the Kairos image based off Hadron
build-kairos:
	@echo "Building Kairos image..."
	@docker build ${PROGRESS_FLAG} -t ${INIT_IMAGE_NAME} \
	-f Dockerfile.init \
	--build-arg BASE_IMAGE=${IMAGE_NAME} \
	--build-arg VERSION=${VERSION} .
	@echo "Kairos image built successfully"


run:
	@docker run -it ${IMAGE_NAME}

clean:
	@docker rmi ${IMAGE_NAME}

grub-iso:
	@echo "Building GRUB ISO image..."
	@docker run -v /var/run/docker.sock:/var/run/docker.sock -v ${PWD}/build/:/output ${AURORA_IMAGE} build-iso --output /output/ docker:${INIT_IMAGE_NAME}
	@echo "GRUB ISO image built successfully at $(shell find build -name "kairos-hadron-${HADRON_VERSION}-*-${VERSION}*.iso")"

# Build an ISO image
trusted-iso:
	@echo "Building Trusted Boot ISO image..."
	@docker run -v /var/run/docker.sock:/var/run/docker.sock \
	-v ${PWD}/build/:/output \
	-v ${KEYS_DIR}:/keys \
	${AURORA_IMAGE} \
	build-uki \
	--output-dir /output/ \
	--public-keys /keys \
	--tpm-pcr-private-key /keys/tpm2-pcr-private.pem \
	--sb-key /keys/db.key \
	--sb-cert /keys/db.pem \
	--output-type iso \
	--sdboot-in-source \
	docker:${INIT_IMAGE_NAME}
	@echo "Trusted Boot ISO image built successfully at $(shell find build -name "kairos-hadron-${HADRON_VERSION}-*-${VERSION}*.iso")"

# Default ISO is the Trusted Boot ISO
build-iso:
	@if [ "${BOOTLOADER}" = "systemd" ]; then \
		$(MAKE) --no-print-directory trusted-iso; \
	else \
		$(MAKE) --no-print-directory grub-iso; \
	fi


MEMORY ?= 2096
ISO_FILE ?= build/kairos-hadron-.iso

run-qemu:
	@if [ ! -e disk.img ]; then \
		qemu-img create -f qcow2 disk.img 40g; \
	fi
	qemu-system-x86_64 \
		-m $(MEMORY) \
		-smp cores=2 \
		-nographic \
		-serial mon:stdio \
		-rtc base=utc,clock=rt \
		-chardev socket,path=qga.sock,server,nowait,id=qga0 \
		-device virtio-serial \
		-device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
		-drive if=virtio,media=disk,file=disk.img \
		-drive if=ide,media=cdrom,file=$(ISO_FILE)
