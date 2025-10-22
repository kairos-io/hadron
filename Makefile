IMAGE_NAME ?= hadron
INIT_IMAGE_NAME ?= hadron-init
AURORA_IMAGE ?= quay.io/kairos/auroraboot:v0.9.0
TARGET ?= default
JOBS ?= 24
GIT_VERSION := v0.0.0-$(shell git describe --tags --always --dirty)

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

# Build an ISO image
## This needs a TAG to be set in the git repo otherwise it will fail to parse the version
iso:
	make build
	docker build -t ${INIT_IMAGE_NAME} -f Dockerfile.init --build-arg BASE_IMAGE=${IMAGE_NAME} --build-arg VERSION=${GIT_VERSION} .
	docker run -v /var/run/docker.sock:/var/run/docker.sock -v ${PWD}/build/:/output ${AURORA_IMAGE} build-iso --output /output/ docker:${INIT_IMAGE_NAME}


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
