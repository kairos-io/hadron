IMAGE_NAME=hadron
AURORA_IMAGE ?= quay.io/kairos/auroraboot:v0.9.0
TARGET ?= default
JOBS ?= 24

.PHONY: build
build:
	docker build --progress=plain \
	--build-arg JOBS=${JOBS} \
	--build-arg VERSION=$$(git describe --tags --always --dirty) \
	-t ${IMAGE_NAME} \
	--target ${TARGET} .

run:
	docker run -it ${IMAGE_NAME}

clean:
	docker rmi ${IMAGE_NAME}

# Build a development ISO image
# This make a base artifact and some workarounds to be able to generate a working iso
# It bundles a custom init (very basic) to be able to mount the iso and run immucore and such, should support cdrom/netboot/installed boot
# It bundles a hardcoded immucore and agent versions in there
# manually builds a initramfs with the needed tools and deps
# creates /system/oem so immucore boots
# hardcodedes the systemd-networkd config so enp is up with dhcp always
# So this is all done to be able to boot from an iso and test it, things will change in the future and init will be called instead
devel-iso:
	make build TARGET=devel
	docker run -v /var/run/docker.sock:/var/run/docker.sock -v ${PWD}/build/:/output ${AURORA_IMAGE} build-iso --output /output/ docker:${IMAGE_NAME}

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
