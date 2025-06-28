MUSL_CROSS_MAKE_VERSION=6f3701d08137496d5aac479e3a3977b5ae993c1f
IMAGE_NAME=ukairos

.PHONY: build
build:
	docker build --progress=plain --build-arg MUSL_CROSS_MAKE_VERSION=${MUSL_CROSS_MAKE_VERSION} -t ${IMAGE_NAME} .

run:
	docker run -it ${IMAGE_NAME}

clean:
	docker rmi ${IMAGE_NAME}