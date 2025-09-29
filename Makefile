MUSL_CROSS_MAKE_VERSION=6f3701d08137496d5aac479e3a3977b5ae993c1f
IMAGE_NAME=ukairos
AURORA_IMAGE=quay.io/kairos/auroraboot:v0.9.0
TARGET=default

.PHONY: build
build:
	docker build --progress=plain --build-arg MUSL_CROSS_MAKE_VERSION=${MUSL_CROSS_MAKE_VERSION} -t ${IMAGE_NAME} --target ${TARGET} .

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