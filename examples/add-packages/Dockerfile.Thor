# syntax=docker/dockerfile:1
# Builds NVIDIA Tegra kernel + OOT modules using NVIDIA's official source bundle
# (Linux_for_Tegra public_sources) per Jetson Linux Developer Guide.
ARG JOBS=10

# ── 1. Download L4T public_sources, extract 4 inner tarballs into one tree ───
FROM alpine AS nvidia-sources
RUN apk add --no-cache curl tar bzip2 patch
WORKDIR /src
RUN curl -fL \
    https://developer.download.nvidia.com/embedded/L4T/r38_Release_v4.0/source/public_sources.tbz2 \
    -o /tmp/public_sources.tbz2
RUN tar -xjf /tmp/public_sources.tbz2 --strip-components=2 \
      Linux_for_Tegra/source/kernel_src.tbz2 \
      Linux_for_Tegra/source/kernel_oot_modules_src.tbz2 \
      Linux_for_Tegra/source/nvidia_kernel_display_driver_source.tbz2 \
      Linux_for_Tegra/source/nvidia_unified_gpu_display_driver_source.tbz2 \
    && rm /tmp/public_sources.tbz2
# Each inner tarball unpacks into /src: kernel_src → kernel/, OOT modules →
# Makefile + nvidia-oot/ hwpm/ nvgpu/ hardware/ kernel-devicetree/,
# display drivers → nvdisplay/ + unifiedgpudisp/.
RUN for t in *.tbz2; do echo "extracting $t"; tar -xjf "$t"; done && rm *.tbz2

# Patch time!
# out of the box sources do not compile LMAO. So good luck. Thanks to the OE4T team for their work, becuase otherwise wow.
# patch makefile
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0001-Makefile-update-for-OE-builds.patch .
RUN for p in *.patch; do echo "applying $p"; patch -p1 < "$p"; done && rm *.patch
# Now patch nvidia-oot
WORKDIR /src/nvidia-oot
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0002-Fix-build-warning-on-rtl8852ce-driver.patch .
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0003-conftest-work-around-stringify-issue-with-__assign_s.patch .
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0004-tegra_virt_storage-fix-build-error-for-Linux-v6.18.patch .
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0005-ASoC-tegra-virt-alt-fix-build-error-with-Linux-v6.18.patch .
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0006-ASoC-Fix-compression-build-failures-with-Linux-v6.18.patch .
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0007-bluetooth-fix-build-issues-with-Linux-v6.18.patch .
RUN for p in *.patch; do echo "applying $p"; patch -p1 < "$p"; done && rm *.patch
# Then patch unifiedgpudisp
WORKDIR /src/unifiedgpudisp
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0008-Fix-unifiedgpudisp-modules-builds.patch .
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0009-Fix-unifiedgpudisp-conftest-gcc-14-compatibility-iss.patch .
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0010-Fix-pfn_t-references-for-Linux-6.17-compatibility.patch .
ADD https://raw.githubusercontent.com/OE4T/meta-tegra/refs/heads/master-l4t-r38.4.x/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot/0011-Fix-drm-fb-builds-for-Linux-6.17.patch .
RUN for p in *.patch; do echo "applying $p"; patch -p1 < "$p"; done && rm *.patch
WORKDIR /src

# ── 2. Build kernel + OOT modules ────────────────────────────────────────────
FROM ghcr.io/kairos-io/hadron-toolchain:main AS kernel-build
ARG JOBS
# CROSS_COMPILE-prefixed binutils symlinks (until Hadron toolchain ships them)
RUN for t in ld as ar nm objcopy objdump ranlib readelf strip; do \
      [ -e /usr/bin/$t ] && ln -sf $t /usr/bin/aarch64-hadron-linux-musl-$t; \
    done

COPY --from=nvidia-sources /src /src
WORKDIR /src

# Step 1 — kernel
RUN NPROC=${JOBS} make -C kernel

RUN mkdir -p /output

ENV KERNEL_HEADERS=/src/kernel/kernel-noble
ENV KERNEL_PATH=/src/kernel/kernel-noble
ENV KERNEL_SRC=/src/kernel/kernel-noble
ENV KBUILD_OUTPUT=/src/kernel/kernel-noble
ENV kernel_name=noble
# Toolchain image sets ARCH=x86-64. Override: we're cross-compiling to arm64.
# nvidia-display-install sub-make doesn't pass ARCH explicitly, relies on env.
ENV ARCH=arm64
ENV CC="aarch64-hadron-linux-musl-gcc -std=gnu17 -Wno-error=header-guard"
ENV CXX="aarch64-hadron-linux-musl-gcc -x c++"
# Toolchain image ENV carries LDFLAGS="-Wl,--gc-sections -Wl,--as-needed -flto=auto"
# and CFLAGS with LTO. unifiedgpudisp's Makefile invokes `ld` directly (not through
# gcc driver), so the `-Wl,` prefix trips "ld: unrecognized option '-Wl,--gc-sections'".
# Also clear AR/NM/RANLIB (gcc-ar wrappers mess with kbuild tool detection).
ENV CFLAGS=""
ENV LDFLAGS=""
ENV AR=""
ENV NM=""
ENV RANLIB=""
RUN NPROC=${JOBS} make modules
# Install kernel (Image → /output/boot/Image) + in-tree modules via NVIDIA Makefile
RUN mkdir -p /output/boot
RUN INSTALL_MOD_PATH=/output make -C kernel install
# Capture release string up front so we can pass MODLIB correctly to OOT install.
# OE4T patch 0001 passes MODLIB=$(MODLIB) (default /lib/modules) to the OOT
# modules_install sub-makes, which OVERRIDES INSTALL_MOD_PATH. Without setting
# MODLIB to the right per-kver path, OOT modules land in /lib/modules/updates/
# inside the image instead of /output/lib/modules/<kver>/updates/.
# `-s` silences make's "Entering directory" noise.
# NVIDIA's kernel/Makefile hardcodes LOCALVERSION=-tegra → kernel release is
# 6.8.12-tegra. Query must match that or OOT install lands in a different dir
# than kernel-tree install.
RUN make -s -C kernel/kernel-noble LOCALVERSION=-tegra kernelrelease > /output/kernel-release
RUN make -s -C kernel/kernel-noble LOCALVERSION=-tegra kernelversion > /output/kernel-version
# Install OOT modules (hwpm + nvidia-oot + unifiedgpudisp) to /output/lib/modules/<kver>/
RUN kver=$(cat /output/kernel-release) && MODLIB=/output/lib/modules/${kver} INSTALL_MOD_PATH=/output make modules_install
# Rename Image → vmlinuz-${kver} and create /output/boot/vmlinuz symlink
RUN kver=$(cat /output/kernel-release) && mv /output/boot/Image /output/boot/vmlinuz-${kver}
# DEBUG: ship kernel .config for inspection
RUN cp /src/kernel/kernel-noble/.config /output/kernel-config

# ── 3. Extract NVIDIA userspace libs + firmware from L4T apt repo ────────────
FROM ubuntu:24.04 AS extract
ARG L4T_RELEASE=r38.4
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends gnupg ca-certificates curl && \
    curl -fsSL https://repo.download.nvidia.com/jetson/jetson-ota-public.asc \
      | gpg --dearmor -o /usr/share/keyrings/nvidia-jetson.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nvidia-jetson.gpg] https://repo.download.nvidia.com/jetson/common ${L4T_RELEASE} main" \
      > /etc/apt/sources.list.d/nvidia-l4t.list && \
    echo "deb [signed-by=/usr/share/keyrings/nvidia-jetson.gpg] https://repo.download.nvidia.com/jetson/som ${L4T_RELEASE} main" \
      >> /etc/apt/sources.list.d/nvidia-l4t.list && \
    apt-get update

WORKDIR /tmp/debs
# nvidia-l4t-init ships: CSVs for nvidia-container-runtime (drivers.csv + devices.csv),
# /etc/udev/rules.d/99-tegra-devices.rules (mknod + GROUP=video on nvmap/nvhost — fixes
# non-root /dev/nvmap access), systemd jetson.preset (disables services Jetson doesn't need),
# sysctl tegra-settings, power fix scripts, hugetlbfs init, memory warning service.
#
# Container runtime stack from upstream Jetson Linux instead of building from source:
# - nvidia-container-toolkit-base: nvidia-ctk + nvidia-container-runtime + nvidia-cdi-hook
#   + /etc/systemd/system/nvidia-cdi-refresh.{service,path} (auto-generates
#   /var/run/cdi/nvidia.yaml when nvidia.ko + nvidia-smi appear, refreshes on driver
#   upgrade — this is the supported Jetson Linux mechanism for boot-time CDI registration)
# - nvidia-container-toolkit: nvidia-container-runtime-hook (legacy OCI hook)
# - libnvidia-container-tools: nvidia-container-cli
# - libnvidia-container1: libnvidia-container.so + libnvidia-container-go.so
RUN apt-get download \
      nvidia-l4t-nvml nvidia-l4t-core nvidia-l4t-cuda nvidia-l4t-firmware-openrm nvidia-l4t-init \
      nvidia-container-toolkit-base nvidia-container-toolkit \
      libnvidia-container-tools libnvidia-container1
RUN mkdir -p /output && for deb in *.deb; do dpkg-deb -x "$deb" /output; done
RUN rm -rf /output/usr/share

RUN cd /output/usr/lib/aarch64-linux-gnu/nvidia && \
    for real in lib*.so.*.*; do \
      base=$(echo "$real" | sed -E 's/\.so\..*/.so.1/'); \
      ln -sf "$real" "$base"; \
    done

RUN GLIBC=/lib/aarch64-linux-gnu && \
    cp -L $GLIBC/ld-linux-aarch64.so* /output/usr/lib/ && \
    cp -L $GLIBC/libc.so.6 /output/usr/lib/aarch64-linux-gnu && \
    cp -L $GLIBC/libpthread.so.0 /output/usr/lib/aarch64-linux-gnu && \
    cp -L $GLIBC/libm.so.6 /output/usr/lib/aarch64-linux-gnu && \
    cp -L $GLIBC/libdl.so.2 /output/usr/lib/aarch64-linux-gnu && \
    cp -L $GLIBC/librt.so.1 /output/usr/lib/aarch64-linux-gnu && \
    cp -L $GLIBC/libresolv.so.2 /output/usr/lib/aarch64-linux-gnu && \
    cp -L $GLIBC/libstdc++.so.6 /output/usr/lib/aarch64-linux-gnu && \
    cp -L $GLIBC/libgcc_s.so.1 /output/usr/lib/aarch64-linux-gnu && \
    cp -L $GLIBC/libnsl.so.1 /output/usr/lib/aarch64-linux-gnu && \
    cp -L $GLIBC/libcrypt.so.1 /output/usr/lib/aarch64-linux-gnu
RUN echo "/usr/lib/aarch64-linux-gnu" > /output/etc/ld.so.conf
RUN echo "/usr/lib/aarch64-linux-gnu/nvidia" >> /output/etc/ld.so.conf
RUN ldconfig -r /output -f /etc/ld.so.conf
# Ship real glibc ldconfig so nvidia-container-toolkit hook can run it to rebuild
# /etc/ld.so.cache in CUDA containers. Hadron's /bin/ldconfig is a coreutils
# multicall that errors ("unknown program 'ldconfig'"). Ubuntu's /usr/sbin/ldconfig
# is a shell WRAPPER that execs /sbin/ldconfig.real (dpkg-divert pattern). Ship
# the real ELF binary, not the wrapper.
RUN cp /usr/sbin/ldconfig.real /output/usr/sbin/ldconfig

# ── 6. Final Hadron extension image ──────────────────────────────────────────
FROM quay.io/itxaka/nvidia:main AS hadron-extension
# NVIDIA Tegra kernel (replaces vanilla Hadron kernel)
RUN rm -Rf /boot/* && rm -rf /lib/modules/* && rm -rf /usr/share/kernel-misc/*
# kernel image + modules (both kernel-tree and OOT) + dtbs from kernel-build stage
COPY --from=kernel-build /output/boot/ /boot/
COPY --from=kernel-build /output/lib/modules /lib/modules/
COPY --from=kernel-build /output/kernel-release /usr/share/kernel-misc/kernel-release
COPY --from=kernel-build /output/kernel-version /usr/share/kernel-misc/kernel-version
# NVIDIA userspace libs, firmware, glibc runtime, container toolkit
COPY --from=extract /output/usr/lib /usr/lib
COPY --from=extract /output/usr/bin /usr/bin
COPY --from=extract /output/usr/sbin /usr/sbin
COPY --from=extract /output/etc/ /etc/
COPY --from=extract /output/lib /lib

# Enable nvidia-cdi-refresh.{service,path} so /var/run/cdi/nvidia.yaml is generated
# at boot when nvidia.ko + nvidia-smi are present, and refreshed on driver upgrade.
RUN mkdir -p /etc/systemd/system/multi-user.target.wants && \
    ln -sf /etc/systemd/system/nvidia-cdi-refresh.service \
      /etc/systemd/system/multi-user.target.wants/nvidia-cdi-refresh.service && \
    ln -sf /etc/systemd/system/nvidia-cdi-refresh.path \
      /etc/systemd/system/multi-user.target.wants/nvidia-cdi-refresh.path

RUN printf 'options nvidia NVreg_TegraGpuPgMask=-1\noptions nvidia-drm modeset=1\nsoftdep nvidia pre: governor_pod_scaling tegra-bpmp-thermal\nsoftdep nvidia post: nvidia-uvm\n' \
    > /etc/modprobe.d/nvidia-unifiedgpudisp.conf
RUN echo "options nv-gpu-static-pg gpu_pg_mask_param=4294967295" > /etc/modprobe.d/nv-gpu-static-pg.conf
RUN echo "blacklist nouveau" > /etc/modprobe.d/blacklist-nouveau.conf
RUN printf 'blacklist tegradisp_nvkms\nblacklist tegradisp_rm\nblacklist nvmap\n' > /etc/modprobe.d/denylist-oot-modules.conf
CMD ["/bin/bash", "-l"]
