#!/bin/bash

set -euo pipefail

## List of folders to create separate firmware images for
## Generate this list by pulling the linux-firmware building the modules into a temp destdir and running:
## ls -d */ | tr -d '/' | xargs
## for example some folders are in the repo but not build like
# carl9170fw is skipped as it requires to build it by itself?
# Important to check out the proper tag as things go away and are added over time
folders="3com acenic adaptec advansys aeonsemi airoha amd amdgpu amdnpu amdtee amd-ucode
amlogic amphion ar3k arm ath10k ath11k ath12k ath6k ath9k_htc atmel atusb av7110 bnx2
bnx2x brcm cadence cavium cirrus cis cnm cpia2 cxgb3 cxgb4 cypress dabusb dell dpaa2
dsp56k e100 edgeport emi26 emi62 ene-ub6250 ess go7007 HP i915 imx inside-secure
isci ixp4xx kaweth keyspan keyspan_pda korg LENOVO libertas liquidio matrox mediatek
mellanox meson microchip moxa mrvl mwl8k mwlwifi myricom netronome nvidia nxp ositech
powervr qca qed qlogic r128 radeon realtek rockchip rsi rtl_bt rtl_nic rtlwifi
rtw88 rtw89 sb16 slicoss sun sxg tehuti ti ti-connectivity tigon ti-keystone
ttusb-budget ueagle-atm vicam vxge wfx xe yam yamaha"

qcom_folders="aic100 apq8016 apq8096 kaanapali
qcm2290 qcm6490 qcs615 qcs6490 qcs8300 qdu100 qrb4210 sa8775p sc8280xp sdm845
sdx61 sm8250 sm8550 sm8650
venus-1.8 venus-4.2 venus-5.2 venus-5.4 venus-6.0 vpu x1e80100 x1p42100"

intel_folders="avs catpt ice ipu ish iwlwifi qat vpu vsc"


FIRMWARE_VERSION="20251111"

SINGLE_TARGET=""
DOCKERFILE_ONLY=0
BUILD=0
SYSEXT=0
PUSH=0
REPOSITORY="ttl.sh"
CERTIFICATE=""
PRIVATE_KEY=""


while [[ $# -gt 0 ]]; do
  case "$1" in
    --dockerfile-only)
      DOCKERFILE_ONLY=1
      shift
      ;;
    --target)
      SINGLE_TARGET="$2"
      shift 2
      ;;
    --firmware-version)
      FIRMWARE_VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD=1
      shift
      ;;
    --sysext)
      SYSEXT=1
      shift
      ;;
    --push)
      PUSH=1
      shift
      ;;
    --repository)
      REPOSITORY="$2"
      shift 2
      ;;
    --private-key)
      PRIVATE_KEY="$2"
      shift 2
      ;;
    --certificate)
      CERTIFICATE="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --dockerfile-only           Generate only the Dockerfile.firmware"
      echo "  --target <target_name>      Build only the specified target"
      echo "  --firmware-version <ver>    Specify the linux-firmware version (default: $FIRMWARE_VERSION)"
      echo "  --build                     Build the firmware images"
      echo "  --sysext                    Create sysext images for the built firmware images"
      echo "  --push                      Push the built images to the repository (requires --build)"
      echo "  --repository <repo>         Specify the Docker repository (default: $REPOSITORY)"
      echo "  --help, -h                  Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      shift
      ;;
  esac
done

if [[ $PUSH -eq 1 && $BUILD -eq 0 ]]; then
  echo "--push requires --build to be specified."
  exit 1
fi

if [[ $DOCKERFILE_ONLY -eq 0 && $BUILD -eq 0 && $SYSEXT -eq 0 ]]; then
  echo "No action specified. Use --dockerfile-only, --build, or --sysext."
  exit 1
fi

echo "Generating Dockerfile.firmware for linux-firmware version: $FIRMWARE_VERSION"
cat <<EOF > Dockerfile.firmware
ARG FIRMWARE_VERSION=$FIRMWARE_VERSION
ARG ALPINE_VERSION=3.22.2

FROM alpine:\$ALPINE_VERSION AS base
ENV ZSTD_NBTHREADS=4
ENV ZSTD_CLEVEL=19
# rdfind is used to deduplicate files
# parallel is used to speed up compression
# coreutils is used for ln in dedup which uses force option
# findutils is needed for dedup to use xtype option
RUN apk add --no-cache git zstd rdfind parallel coreutils findutils
WORKDIR /src
RUN git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
WORKDIR /src/linux-firmware
RUN git fetch --tags
RUN git checkout $FIRMWARE_VERSION
## This avoids a WHENCE check which we should nto care about and avoids installing python3
RUN rm .git/config
RUN mkdir /out
RUN ./copy-firmware.sh -j\$(nproc) -v --zstd /out/lib/firmware
RUN ./dedup-firmware.sh /out/lib/firmware
EOF

for folder in $folders; do
  # check if name starts with a number, if so, reverse the name
  if [[ $folder =~ ^[0-9] ]]; then
    target=$(echo "$folder" | rev | tr '.' '-')
  else
    target=${folder//./-}
  fi
  # check if folder is uppercase, if so, change target to lowercase
  if [[ $folder =~ ^[A-Z0-9_-]+$ ]]; then
    target=${target,,}
  fi
  cat <<EOF >> Dockerfile.firmware

FROM scratch AS ${target}
COPY --from=base /out/lib/firmware/$folder /lib/firmware/
EOF
done

## Intel section
## Intel firmware requires special handling due to its nested structure.
## we have a couple of HUGE folder and we want to ship those in a separate target BUT the files inside the intel folder
## are a different thing, we have to ship those as well so we manage this specifically
cat <<EOF >> Dockerfile.firmware

FROM base AS intel
RUN mkdir /output
RUN find /out/lib/firmware/intel -maxdepth 1 -type f -exec cp {} /output/ \;

FROM scratch AS intel-generic
COPY --from=intel /output/. /lib/firmware/intel/
EOF

for folder in $intel_folders; do
  # Some names have dots which are not valid for docker target names, replace dots with dashes
  target=${folder//./-}
cat <<EOF >> Dockerfile.firmware

FROM scratch AS intel-${target}
COPY --from=base /out/lib/firmware/intel/$folder/. /lib/firmware/intel/$folder/
EOF
done

## qcom section
## Same as inter, they got several subfolders that are huge and we want to ship them separately
cat <<EOF >> Dockerfile.firmware

FROM base AS qcom
RUN mkdir /output
RUN find /out/lib/firmware/qcom -maxdepth 1 -type f -exec cp {} /output/ \;

FROM scratch AS qcom-generic
COPY --from=qcom /output/. /lib/firmware/qcom/
EOF

for folder in $qcom_folders; do
  # Some names have dots which are not valid for docker target names, replace dots with dashes
  target=${folder//./-}
  cat <<EOF >> Dockerfile.firmware

FROM scratch AS qcom-${target}
COPY --from=base /out/lib/firmware/qcom/$folder/. /lib/firmware/qcom/$folder/
EOF
done

## Now finally lets do the files in the root of /out/lib/firmware
cat <<EOF >> Dockerfile.firmware

FROM base AS uncategorized-firmware
RUN mkdir /output
RUN find /out/lib/firmware -maxdepth 1 -type f -exec cp {} /output/ \;

FROM scratch AS uncategorized
COPY --from=uncategorized-firmware /output/. /lib/firmware/
EOF


echo "Generated Dockerfile.firmware"
# If only generating Dockerfile, exit here so we dont remove the dockerfile
if [[ $DOCKERFILE_ONLY -eq 1 ]]; then
  exit 0
fi


if [[ $BUILD -eq 1 ]]; then
# Build single target if specified
  if [[ -n "$SINGLE_TARGET" ]]; then
    echo "Building only target: $SINGLE_TARGET"
    set +e
    output=$(docker build -f Dockerfile.firmware -t ${REPOSITORY}/linux-firmware-"${SINGLE_TARGET}":"${FIRMWARE_VERSION}" --target "${SINGLE_TARGET}" . 2>&1)
    status=$?
    set -e
    if [ $status -ne 0 ]; then
      echo "Docker build failed:"
      echo "$output"
      exit 1
    fi
    echo "Build for $SINGLE_TARGET completed successfully."
    if [[ $PUSH -eq 1 ]]; then
      echo "Pushing image ${REPOSITORY}/linux-firmware-${SINGLE_TARGET}:${FIRMWARE_VERSION} to repository..."
      docker push ${REPOSITORY}/linux-firmware-"${SINGLE_TARGET}":"${FIRMWARE_VERSION}"
      echo "Push completed successfully."
    fi
    rm Dockerfile.firmware
    exit 0
  fi

  echo "Building all firmware targets..."

  ## Build all targets
  for folder in $folders; do
    if [[ $folder =~ ^[0-9] ]]; then
      target=$(echo "$folder" | rev | tr '.' '-')
    else
      target=${folder//./-}
    fi
    # check if folder is uppercase, if so, change target to lowercase
    if [[ $folder =~ ^[A-Z0-9_-]+$ ]]; then
      target=${target,,}
    fi
    echo "Building: $folder"
    set +e
    output=$(docker build -f Dockerfile.firmware -t ${REPOSITORY}/linux-firmware-"${target}":"${FIRMWARE_VERSION}" --target "${target}" . 2>&1)
    status=$?
    set -e
    # shellcheck disable=SC2181
    if [ $status -ne 0 ]; then
      echo "Docker build failed:"
      echo "$output"
      exit 1
    fi
    if [[ $PUSH -eq 1 ]]; then
      echo "Pushing image ${REPOSITORY}/linux-firmware-${target}:${FIRMWARE_VERSION} to repository..."
      docker push ${REPOSITORY}/linux-firmware-"${target}":"${FIRMWARE_VERSION}"
      echo "Push completed successfully."
    fi
  done

  for folder in $intel_folders; do
    target=${folder//./-}
    echo "Building: intel-$folder"
    set +e
    output=$(docker build -f Dockerfile.firmware -t ${REPOSITORY}/linux-firmware-intel-"${target}":"${FIRMWARE_VERSION}" --target "intel-${target}" . 2>&1)
    status=$?
    set -e
    # shellcheck disable=SC2181
    if [ $status -ne 0 ]; then
      echo "Docker build failed:"
      echo "$output"
      exit 1
    fi
    if [[ $PUSH -eq 1 ]]; then
      echo "Pushing image ${REPOSITORY}/linux-firmware-${target}:${FIRMWARE_VERSION} to repository..."
      docker push ${REPOSITORY}/linux-firmware-"${target}":"${FIRMWARE_VERSION}"
      echo "Push completed successfully."
    fi
  done

  for folder in $qcom_folders; do
    target=${folder//./-}
    echo "Building: qcom-$folder"
    set +e
    output=$(docker build -f Dockerfile.firmware -t ${REPOSITORY}/linux-firmware-qcom-"${target}":"${FIRMWARE_VERSION}" --target "qcom-${target}" . 2>&1)
    status=$?
    set -e
    # shellcheck disable=SC2181
    if [ $status -ne 0 ]; then
      echo "Docker build failed:"
      echo "$output"
      exit 1
    fi
    if [[ $PUSH -eq 1 ]]; then
      echo "Pushing image ${REPOSITORY}/linux-firmware-${target}:${FIRMWARE_VERSION} to repository..."
      docker push ${REPOSITORY}/linux-firmware-"${target}":"${FIRMWARE_VERSION}"
      echo "Push completed successfully."
    fi
  done

  echo "Building: intel"
  set +e
  output=$(docker build -f Dockerfile.firmware -t ${REPOSITORY}/linux-firmware-intel-generic:"${FIRMWARE_VERSION}" --target "intel-generic" . 2>&1)
  status=$?
  set -e
  # shellcheck disable=SC2181
  if [ $status -ne 0 ]; then
    echo "Docker build failed:"
    echo "$output"
    exit 1
  fi
  if [[ $PUSH -eq 1 ]]; then
    echo "Pushing image ${REPOSITORY}/linux-firmware-${target}:${FIRMWARE_VERSION} to repository..."
    docker push ${REPOSITORY}/linux-firmware-"${target}":"${FIRMWARE_VERSION}"
    echo "Push completed successfully."
  fi
  echo "Building: qcom"
  set +e
  output=$(docker build -f Dockerfile.firmware -t ${REPOSITORY}/linux-firmware-qcom-generic:"${FIRMWARE_VERSION}" --target "qcom-generic" .  2>&1)
  set -e
  # shellcheck disable=SC2181
  if [ $status -ne 0 ]; then
    echo "Docker build failed:"
    echo "$output"
    exit 1
  fi
  if [[ $PUSH -eq 1 ]]; then
    echo "Pushing image ${REPOSITORY}/linux-firmware-${target}:${FIRMWARE_VERSION} to repository..."
    docker push ${REPOSITORY}/linux-firmware-"${target}":"${FIRMWARE_VERSION}"
    echo "Push completed successfully."
  fi
  echo "Building: uncategorized"
  set +e
  output=$(docker build -f Dockerfile.firmware -t ${REPOSITORY}/linux-firmware-uncategorized:"${FIRMWARE_VERSION}" --target "uncategorized" . 2>&1)
  status=$?
  set -e
  # shellcheck disable=SC2181
  if [ $status -ne 0 ]; then
    echo "Docker build failed:"
    echo "$output"
    exit 1
  fi
  if [[ $PUSH -eq 1 ]]; then
    echo "Pushing image ${REPOSITORY}/linux-firmware-${target}:${FIRMWARE_VERSION} to repository..."
    docker push ${REPOSITORY}/linux-firmware-"${target}":"${FIRMWARE_VERSION}"
    echo "Push completed successfully."
  fi
  echo "All builds completed successfully."
fi


## Allow passing --private-key and --certificate to sysext in order to sign the sysext images
if [[ $SYSEXT -eq 1 ]]; then
  echo "Building sysext firmware images..."
  images=$(docker images --filter=reference="${REPOSITORY}/linux-firmware-*" --format '{{.Repository}}:{{.Tag}}')
  for image in $images; do
    # target name is the image name without the repository part. Lets keep the linux-firmware on it
    target_name=$(echo "$image" | sed -e "s|${REPOSITORY}/||" -e 's|:|_|g')
    echo "Building sysext for $target_name"
    mounts="-v /var/run/docker.sock:/var/run/docker.sock"
    args="--output /build"
    if [[ -n "$PRIVATE_KEY" && -n "$CERTIFICATE" ]]; then
      # get the base path of the private key and certificate to mount into the docker container
      # For example if the private key is /path/to/key.pem we need to mount /path/to
      key_dir=$(dirname "$PRIVATE_KEY")
      cert_dir=$(dirname "$CERTIFICATE")
      ## If they are relative paths make them absolute
      if [[ "$key_dir" != /* ]]; then
        key_dir="${PWD}/$key_dir"
      fi
      if [[ "$cert_dir" != /* ]]; then
        cert_dir="${PWD}/$cert_dir"
      fi
      ## Now add the mounts for the key and cert
      mounts="$mounts -v $key_dir:/key -v $cert_dir:/cert"
      ## Now set the full destination args to the proper paths inside the container
      args="$args --private-key /key/$(basename "$PRIVATE_KEY") --certificate /cert/$(basename "$CERTIFICATE")"
    fi
    docker run -i --rm ${mounts} \
      -v "${PWD}"/build:/build \
      auroraboot \
      sysext ${args} "$target_name" "$image"
    echo "Sysext for $target_name built successfully."
  done
  echo "All sysext firmware images built"
fi


# Cleanup
echo "Removing temporary Dockerfile.firmware"
rm Dockerfile.firmware
