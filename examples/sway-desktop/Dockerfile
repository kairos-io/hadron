# Sway desktop environment for Hadron.
#
# Builds a full Wayland desktop (Sway) on top of the Hadron base image, with (in
# later milestones) NetworkManager, PipeWire audio, wifi and bluetooth.
# Everything is built from source against the Hadron musl toolchain, following
# the multi-stage pattern of examples/add-packages/Dockerfile.doom.
#
# Build:    docker build -t sway-desktop:dev examples/sway-desktop
# Test:     examples/sway-desktop/test/run.sh   (full build -> boot -> assert loop)
# Design:   docs/superpowers/specs/2026-06-03-sway-desktop-example-design.md
#
# Milestone M1: Sway compositor under systemd-logind, rendering on tty1 via an
# autologin user, with a terminal (foot).

ARG BASE_IMAGE=ghcr.io/kairos-io/hadron:main

FROM ghcr.io/kairos-io/hadron-toolchain:main AS toolchain

# ===========================================================================
# Wayland display stack (shared with the doom example)
# ===========================================================================

FROM toolchain AS wayland
ARG WAYLAND_VERSION=1.24.0
ARG WAYLAND_PROTOCOLS_VERSION=1.46
RUN mkdir -p /wayland
WORKDIR /build
RUN curl -L https://gitlab.freedesktop.org/wayland/wayland/-/archive/${WAYLAND_VERSION}/wayland-${WAYLAND_VERSION}.tar -o wayland.tar && tar -xf wayland.tar && rm wayland.tar && mv wayland-* wayland-src
RUN curl -L https://gitlab.freedesktop.org/wayland/wayland-protocols/-/archive/${WAYLAND_PROTOCOLS_VERSION}/wayland-protocols-${WAYLAND_PROTOCOLS_VERSION}.tar -o wayland-protocols.tar && tar -xf wayland-protocols.tar && rm wayland-protocols.tar && mv wayland-protocols-* wayland-protocols-src
RUN pip3 install meson ninja
WORKDIR /build/wayland-src
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtests=false -Ddocumentation=false -Dscanner=true -Dlibraries=true
RUN DESTDIR=/wayland ninja -C buildDir install
RUN ninja -C buildDir install
WORKDIR /build/wayland-protocols-src
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtests=false
RUN DESTDIR=/wayland ninja -C buildDir install


FROM toolchain AS libdrm
ARG LIBDRM_VERSION=2.4.129
RUN mkdir -p /libdrm
WORKDIR /build
RUN curl -L https://dri.freedesktop.org/libdrm/libdrm-${LIBDRM_VERSION}.tar.xz -o libdrm.tar.xz && tar -xf libdrm.tar.xz && rm libdrm.tar.xz && mv libdrm-* libdrm-src
WORKDIR /build/libdrm-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtests=false
RUN DESTDIR=/libdrm ninja -C buildDir install


FROM toolchain AS mesa
COPY --from=libdrm /libdrm /
COPY --from=wayland /wayland /
ARG MESA_VERSION=25.3.0
RUN mkdir -p /mesa
WORKDIR /build
RUN curl -L https://archive.mesa3d.org/mesa-${MESA_VERSION}.tar.xz -o mesa.tar.xz && tar -xf mesa.tar.xz && rm mesa.tar.xz && mv mesa-* mesa-src
WORKDIR /build/mesa-src
RUN pip3 install meson ninja setuptools mako pyyaml
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dplatforms=wayland \
    -Dgallium-drivers=virgl,softpipe,svga \
    -Dglx=dri \
    -Dopengl=true \
    -Dgles1=enabled \
    -Dgles2=enabled \
    -Degl=enabled \
    -Dvulkan-drivers= \
    -Dllvm=false \
    -Dglx=disabled \
    -Dbuild-tests=false
RUN DESTDIR=/mesa ninja -C buildDir install


FROM toolchain AS xkeyboard-config
ARG XKEYBOARD_CONFIG_VERSION=2.44
RUN mkdir -p /xkeyboard-config
WORKDIR /build
RUN curl -L http://www.x.org/releases/individual/data/xkeyboard-config/xkeyboard-config-${XKEYBOARD_CONFIG_VERSION}.tar.xz -o xkeyboard-config.tar.xz && tar -xf xkeyboard-config.tar.xz && rm xkeyboard-config.tar.xz && mv xkeyboard-config-* xkeyboard-config-src
WORKDIR /build/xkeyboard-config-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS}
RUN DESTDIR=/xkeyboard-config ninja -C buildDir install


FROM toolchain AS libxkb
COPY --from=wayland /wayland /
COPY --from=xkeyboard-config /xkeyboard-config /
ARG LIBXKBCOMMON_VERSION=1.13.0
RUN mkdir -p /libxkb
WORKDIR /build
RUN curl -L https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-${LIBXKBCOMMON_VERSION}.tar.gz -o libxkbcommon.tar.gz && tar -xzf libxkbcommon.tar.gz && rm libxkbcommon.tar.gz && mv libxkbcommon-* libxkbcommon-src
WORKDIR /build/libxkbcommon-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Denable-x11=false -Denable-xkbregistry=true -Denable-bash-completion=false
RUN DESTDIR=/libxkb ninja -C buildDir install


FROM toolchain AS pixman
ARG PIXMAN_VERSION=0.46.0
RUN mkdir -p /pixman
WORKDIR /build
RUN curl -L https://www.cairographics.org/releases/pixman-${PIXMAN_VERSION}.tar.gz -o pixman.tar.gz && tar -xzf pixman.tar.gz && rm pixman.tar.gz && mv pixman-* pixman-src
WORKDIR /build/pixman-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS}
RUN DESTDIR=/pixman ninja -C buildDir install


FROM toolchain AS libevdev
ARG LIBEVDEV_VERSION=1.13.5
RUN mkdir -p /libevdev
WORKDIR /build
RUN curl -L https://gitlab.freedesktop.org/libevdev/libevdev/-/archive/libevdev-${LIBEVDEV_VERSION}/libevdev-libevdev-${LIBEVDEV_VERSION}.tar.gz -o libevdev.tar.gz && tar -xzf libevdev.tar.gz && rm libevdev.tar.gz && mv libevdev-* libevdev-src
WORKDIR /build/libevdev-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtests=disabled -Ddocumentation=disabled -Dtools=disabled
RUN DESTDIR=/libevdev ninja -C buildDir install


FROM toolchain AS libinput
COPY --from=libevdev /libevdev /
ARG LIBINPUT_VERSION=1.30.0
RUN mkdir -p /libinput
WORKDIR /build
RUN curl -L https://gitlab.freedesktop.org/libinput/libinput/-/archive/${LIBINPUT_VERSION}/libinput-${LIBINPUT_VERSION}.tar.gz -o libinput.tar.gz && tar -xf libinput.tar.gz && rm libinput.tar.gz && mv libinput-* libinput-src
WORKDIR /build/libinput-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dmtdev=false -Dlibwacom=false -Dtests=false -Ddebug-gui=false
RUN DESTDIR=/libinput ninja -C buildDir install


FROM toolchain AS hwdata
ARG HWDATA_VERSION=0.401
RUN mkdir -p /hwdata
WORKDIR /build
RUN curl -L https://github.com/vcrhonek/hwdata/archive/v${HWDATA_VERSION}/hwdata-${HWDATA_VERSION}.tar.gz -o hwdata.tar.xz && tar -xf hwdata.tar.xz && rm hwdata.tar.xz && mv hwdata-* hwdata-src
WORKDIR /build/hwdata-src
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking
RUN make -j$(nproc) && make install DESTDIR=/hwdata


FROM toolchain AS libdisplay-info
COPY --from=hwdata /hwdata /
ARG LIBDISPLAY_INFO_VERSION=0.3.0
RUN mkdir -p /libdisplay-info
WORKDIR /build
RUN curl -L https://gitlab.freedesktop.org/emersion/libdisplay-info/-/releases/${LIBDISPLAY_INFO_VERSION}/downloads/libdisplay-info-${LIBDISPLAY_INFO_VERSION}.tar.xz -o libdisplay-info.tar.xz && tar -xf libdisplay-info.tar.xz && rm libdisplay-info.tar.xz && mv libdisplay-info-* libdisplay-info-src
WORKDIR /build/libdisplay-info-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS}
RUN DESTDIR=/libdisplay-info ninja -C buildDir install


# ===========================================================================
# Desktop libraries (new for the sway desktop)
# ===========================================================================

# PCRE2 — required by glib
FROM toolchain AS pcre2
ARG PCRE2_VERSION=10.44
RUN mkdir -p /pcre2
WORKDIR /build
RUN curl -L https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz -o pcre2.tar.gz && tar -xzf pcre2.tar.gz && rm pcre2.tar.gz && mv pcre2-* pcre2-src
WORKDIR /build/pcre2-src
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --enable-pcre2-16 --enable-pcre2-32
RUN make -j$(nproc) && make install DESTDIR=/pcre2


# libpng — needed by grim (PNG screenshots)
FROM toolchain AS libpng
ARG LIBPNG_VERSION=1.6.44
RUN mkdir -p /libpng
WORKDIR /build
RUN curl -L https://download.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.xz -o libpng.tar.xz && tar -xf libpng.tar.xz && rm libpng.tar.xz && mv libpng-* libpng-src
WORKDIR /build/libpng-src
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking
RUN make -j$(nproc) && make install DESTDIR=/libpng


# GLib — libffi/expat/zlib already provided by the toolchain
FROM toolchain AS glib2
COPY --from=pcre2 /pcre2 /
ARG GLIB_VERSION=2.82.5
RUN mkdir -p /glib2
WORKDIR /build
RUN GLIB_MAJOR="${GLIB_VERSION%.*}" && curl -L https://download.gnome.org/sources/glib/${GLIB_MAJOR}/glib-${GLIB_VERSION}.tar.xz -o glib.tar.xz && tar -xf glib.tar.xz && rm glib.tar.xz && mv glib-* glib-src
WORKDIR /build/glib-src
RUN pip3 install meson ninja packaging
RUN meson setup buildDir ${COMMON_MESON_FLAGS} \
    -Dnls=disabled -Dtests=false -Dlibmount=disabled -Dselinux=disabled \
    -Dman-pages=disabled -Dintrospection=disabled -Dglib_debug=disabled \
    -Ddtrace=disabled -Dsysprof=disabled
RUN DESTDIR=/glib2 ninja -C buildDir install


# FreeType — built without harfbuzz (broken circular dep), png/brotli optional
FROM toolchain AS freetype
RUN mkdir -p /freetype
WORKDIR /build
ARG FREETYPE_VERSION=2.13.3
RUN curl -L https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.xz -o freetype.tar.xz && tar -xf freetype.tar.xz && rm freetype.tar.xz && mv freetype-* freetype-src
WORKDIR /build/freetype-src
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --with-harfbuzz=no --with-png=no --with-brotli=no --with-bzip2=no --with-zlib=yes
RUN make -j$(nproc) && make install DESTDIR=/freetype


# HarfBuzz — needs freetype + glib
FROM toolchain AS harfbuzz
COPY --from=freetype /freetype /
COPY --from=glib2 /glib2 /
COPY --from=pcre2 /pcre2 /
ARG HARFBUZZ_VERSION=10.1.0
RUN mkdir -p /harfbuzz
WORKDIR /build
RUN curl -L https://github.com/harfbuzz/harfbuzz/releases/download/${HARFBUZZ_VERSION}/harfbuzz-${HARFBUZZ_VERSION}.tar.xz -o harfbuzz.tar.xz && tar -xf harfbuzz.tar.xz && rm harfbuzz.tar.xz && mv harfbuzz-* harfbuzz-src
WORKDIR /build/harfbuzz-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtests=disabled -Ddocs=disabled -Dintrospection=disabled -Dglib=enabled -Dfreetype=enabled -Dcairo=disabled -Dchafa=disabled
RUN DESTDIR=/harfbuzz ninja -C buildDir install


# FriBidi — bidirectional text, needed by pango
FROM toolchain AS fribidi
ARG FRIBIDI_VERSION=1.0.16
RUN mkdir -p /fribidi
WORKDIR /build
RUN curl -L https://github.com/fribidi/fribidi/releases/download/v${FRIBIDI_VERSION}/fribidi-${FRIBIDI_VERSION}.tar.xz -o fribidi.tar.xz && tar -xf fribidi.tar.xz && rm fribidi.tar.xz && mv fribidi-* fribidi-src
WORKDIR /build/fribidi-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtests=false -Ddocs=false -Dbin=false
RUN DESTDIR=/fribidi ninja -C buildDir install


# gperf — build-time tool required by fontconfig
FROM toolchain AS gperf
ARG GPERF_VERSION=3.1
RUN mkdir -p /gperf
WORKDIR /build
RUN curl -L https://ftp.gnu.org/pub/gnu/gperf/gperf-${GPERF_VERSION}.tar.gz -o gperf.tar.gz && tar -xzf gperf.tar.gz && rm gperf.tar.gz && mv gperf-* gperf-src
WORKDIR /build/gperf-src
# gperf 3.1 ships an ancient K&R getopt.c; the toolchain GCC defaults to C23
# where `()` means `(void)`, so force the older language semantics.
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking
RUN make -j$(nproc) CFLAGS="-std=gnu17 -O2 -g" && make install DESTDIR=/gperf


# Fontconfig (+ DejaVu fonts) — expat from toolchain, freetype built above
FROM toolchain AS fontconfig
COPY --from=freetype /freetype /
COPY --from=gperf /gperf /
ARG FONTCONFIG_VERSION=2.15.0
RUN mkdir -p /fontconfig
WORKDIR /build
RUN curl -L https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VERSION}.tar.xz -o fontconfig.tar.xz && tar -xf fontconfig.tar.xz && rm fontconfig.tar.xz && mv fontconfig-* fontconfig-src
WORKDIR /build/fontconfig-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtests=disabled -Dtools=disabled -Ddoc=disabled -Dnls=disabled -Dcache-build=disabled
RUN DESTDIR=/fontconfig ninja -C buildDir install
# Bundle DejaVu fonts
ARG DEJAVU_VERSION=2.37
RUN mkdir -p /fontconfig/usr/share/fonts/dejavu
RUN curl -L https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-${DEJAVU_VERSION}.tar.bz2 -o dejavu.tar.bz2 && \
    tar -xjf dejavu.tar.bz2 && \
    cp dejavu-fonts-ttf-*/ttf/*.ttf /fontconfig/usr/share/fonts/dejavu/ && \
    rm -rf dejavu.tar.bz2 dejavu-fonts-ttf-*


# Cairo — built with the FreeType + fontconfig backends (cairo-ft), required by
# pango. Defined here so freetype/fontconfig stages precede it.
FROM toolchain AS cairo
COPY --from=pixman /pixman /
COPY --from=freetype /freetype /
COPY --from=fontconfig /fontconfig /
# 1.18.4 fixes the COLRv1 / FreeType 2.13.x cairo-ft detection bug.
ARG CAIRO_VERSION=1.18.4
RUN mkdir -p /cairo
WORKDIR /build
RUN curl -L https://cairographics.org/releases/cairo-${CAIRO_VERSION}.tar.xz -o cairo.tar.xz && tar -xf cairo.tar.xz && rm cairo.tar.xz && mv cairo-* cairo-src
WORKDIR /build/cairo-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtests=disabled -Dglib=disabled -Dspectre=disabled \
    -Dfreetype=enabled -Dfontconfig=enabled -Dpng=disabled -Dxlib=disabled -Dxcb=disabled
RUN DESTDIR=/cairo ninja -C buildDir install


# Pango
FROM toolchain AS pango
COPY --from=glib2 /glib2 /
COPY --from=pcre2 /pcre2 /
COPY --from=harfbuzz /harfbuzz /
COPY --from=freetype /freetype /
COPY --from=fontconfig /fontconfig /
COPY --from=fribidi /fribidi /
COPY --from=cairo /cairo /
COPY --from=pixman /pixman /
ARG PANGO_VERSION=1.54.0
RUN mkdir -p /pango
WORKDIR /build
RUN PANGO_MAJOR="${PANGO_VERSION%.*}" && curl -L https://download.gnome.org/sources/pango/${PANGO_MAJOR}/pango-${PANGO_VERSION}.tar.xz -o pango.tar.xz && tar -xf pango.tar.xz && rm pango.tar.xz && mv pango-* pango-src
WORKDIR /build/pango-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dintrospection=disabled -Dgtk_doc=false -Dfontconfig=enabled -Dfreetype=enabled -Dcairo=enabled
RUN DESTDIR=/pango ninja -C buildDir install


# wlroots — compositor library (shared with doom)
FROM toolchain AS wlroots
RUN mkdir -p /wlroots
COPY --from=wayland /wayland /
COPY --from=libdrm /libdrm /
COPY --from=libxkb /libxkb /
COPY --from=pixman /pixman /
COPY --from=libinput /libinput /
COPY --from=libevdev /libevdev /
COPY --from=mesa /mesa /
COPY --from=hwdata /hwdata /
COPY --from=libdisplay-info /libdisplay-info /
ARG WLROOTS_VERSION=0.18.2
WORKDIR /build
RUN curl -L https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/${WLROOTS_VERSION}/wlroots-${WLROOTS_VERSION}.tar -o wlroots.tar && tar -xf wlroots.tar && rm wlroots.tar && mv wlroots-* wlroots-src
WORKDIR /build/wlroots-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dexamples=false -Dwerror=false
RUN DESTDIR=/wlroots ninja -C buildDir install


# libseat — built with the systemd-logind backend (libsystemd from toolchain)
FROM toolchain AS libseat
ARG SEATD_VERSION=0.9.1
RUN mkdir -p /libseat
WORKDIR /build
RUN curl -L https://git.sr.ht/~kennylevinsen/seatd/archive/${SEATD_VERSION}.tar.gz -o seatd.tar.gz && tar -xf seatd.tar.gz && rm seatd.tar.gz && mv seatd-* seatd-src
WORKDIR /build/seatd-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} \
    -Dlibseat-logind=systemd -Dlibseat-seatd=enabled -Dlibseat-builtin=enabled -Dserver=enabled -Dexamples=disabled -Dman-pages=disabled
RUN DESTDIR=/libseat ninja -C buildDir install


# Sway
FROM toolchain AS sway
COPY --from=wayland /wayland /
COPY --from=libdrm /libdrm /
COPY --from=libxkb /libxkb /
COPY --from=pixman /pixman /
COPY --from=libinput /libinput /
COPY --from=libevdev /libevdev /
COPY --from=mesa /mesa /
COPY --from=wlroots /wlroots /
COPY --from=libseat /libseat /
COPY --from=cairo /cairo /
COPY --from=pango /pango /
COPY --from=glib2 /glib2 /
COPY --from=pcre2 /pcre2 /
COPY --from=harfbuzz /harfbuzz /
COPY --from=freetype /freetype /
COPY --from=fontconfig /fontconfig /
COPY --from=fribidi /fribidi /
COPY --from=hwdata /hwdata /
COPY --from=libdisplay-info /libdisplay-info /
ARG SWAY_VERSION=1.10.1
RUN mkdir -p /sway
WORKDIR /build
RUN curl -L https://github.com/swaywm/sway/releases/download/${SWAY_VERSION}/sway-${SWAY_VERSION}.tar.gz -o sway.tar.gz && tar -xzf sway.tar.gz && rm sway.tar.gz && mv sway-* sway-src
WORKDIR /build/sway-src
RUN pip3 install meson ninja
# swaybar/swaynag image loading needs cairo PNG; defer the bar to waybar (M5).
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dman-pages=disabled -Dgdk-pixbuf=disabled -Dtray=disabled -Dswaybar=false -Dswaynag=false -Dwerror=false
RUN DESTDIR=/sway ninja -C buildDir install


# tllist — foot dependency (header-only-ish)
FROM toolchain AS tllist
ARG TLLIST_VERSION=1.1.0
RUN mkdir -p /tllist
WORKDIR /build
RUN curl -L https://codeberg.org/dnkl/tllist/archive/${TLLIST_VERSION}.tar.gz -o tllist.tar.gz && tar -xzf tllist.tar.gz && rm tllist.tar.gz && mv tllist* tllist-src
WORKDIR /build/tllist-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS}
RUN DESTDIR=/tllist ninja -C buildDir install


# fcft — font loading/glyph rasterization for foot (shaping disabled)
FROM toolchain AS fcft
COPY --from=freetype /freetype /
COPY --from=fontconfig /fontconfig /
COPY --from=pixman /pixman /
COPY --from=harfbuzz /harfbuzz /
COPY --from=glib2 /glib2 /
COPY --from=pcre2 /pcre2 /
COPY --from=tllist /tllist /
ARG FCFT_VERSION=3.3.1
RUN mkdir -p /fcft
WORKDIR /build
RUN curl -L https://codeberg.org/dnkl/fcft/archive/${FCFT_VERSION}.tar.gz -o fcft.tar.gz && tar -xzf fcft.tar.gz && rm fcft.tar.gz && mv fcft* fcft-src
WORKDIR /build/fcft-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtest-text-shaping=false -Dgrapheme-shaping=disabled -Drun-shaping=disabled -Ddocs=disabled
RUN DESTDIR=/fcft ninja -C buildDir install


# foot — Wayland terminal emulator
FROM toolchain AS foot
COPY --from=wayland /wayland /
COPY --from=libxkb /libxkb /
COPY --from=pixman /pixman /
COPY --from=freetype /freetype /
COPY --from=fontconfig /fontconfig /
COPY --from=fcft /fcft /
COPY --from=tllist /tllist /
COPY --from=harfbuzz /harfbuzz /
COPY --from=glib2 /glib2 /
COPY --from=pcre2 /pcre2 /
ARG FOOT_VERSION=1.20.2
RUN mkdir -p /foot
WORKDIR /build
RUN curl -L https://codeberg.org/dnkl/foot/archive/${FOOT_VERSION}.tar.gz -o foot.tar.gz && tar -xzf foot.tar.gz && rm foot.tar.gz && mv foot* foot-src
WORKDIR /build/foot-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Ddocs=disabled -Dgrapheme-clustering=disabled -Dthemes=false -Dterminfo=disabled -Dwerror=false
RUN DESTDIR=/foot ninja -C buildDir install


# grim — Wayland screenshot tool (used by the test harness and desktop)
FROM toolchain AS grim
COPY --from=wayland /wayland /
COPY --from=pixman /pixman /
COPY --from=libpng /libpng /
ARG GRIM_VERSION=1.4.1
RUN mkdir -p /grim
WORKDIR /build
RUN curl -L https://gitlab.freedesktop.org/emersion/grim/-/archive/v${GRIM_VERSION}/grim-v${GRIM_VERSION}.tar.gz -o grim.tar.gz && tar -xzf grim.tar.gz && rm grim.tar.gz && mv grim-* grim-src
WORKDIR /build/grim-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Djpeg=disabled -Dman-pages=disabled
RUN DESTDIR=/grim ninja -C buildDir install


# ===========================================================================
# M2: networking — NetworkManager + wpa_supplicant + wifi
# ===========================================================================

# libnl — netlink library, needed by wpa_supplicant/hostapd (nl80211)
FROM toolchain AS libnl
ARG LIBNL_VERSION=3.11.0
RUN mkdir -p /libnl
WORKDIR /build
RUN curl -L https://github.com/thom311/libnl/releases/download/libnl3_11_0/libnl-${LIBNL_VERSION}.tar.gz -o libnl.tar.gz && tar -xzf libnl.tar.gz && rm libnl.tar.gz && mv libnl-* libnl-src
WORKDIR /build/libnl-src
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking
RUN make -j$(nproc) && make install DESTDIR=/libnl


# wpa_supplicant — wifi backend for NetworkManager (D-Bus control interface)
FROM toolchain AS wpa-supplicant
COPY --from=libnl /libnl /
ARG WPA_VERSION=2.11
RUN mkdir -p /wpa
WORKDIR /build
RUN curl -L https://w1.fi/releases/wpa_supplicant-${WPA_VERSION}.tar.gz -o wpa.tar.gz && tar -xzf wpa.tar.gz && rm wpa.tar.gz && mv wpa_supplicant-* wpa-src
WORKDIR /build/wpa-src/wpa_supplicant
RUN printf '%s\n' \
    'CONFIG_DRIVER_NL80211=y' \
    'CONFIG_LIBNL32=y' \
    'CONFIG_CTRL_IFACE=y' \
    'CONFIG_CTRL_IFACE_DBUS_NEW=y' \
    'CONFIG_CTRL_IFACE_DBUS_INTRO=y' \
    'CONFIG_BACKEND=file' \
    'CONFIG_TLS=openssl' \
    'CONFIG_IEEE80211W=y' \
    'CONFIG_IEEE80211AC=y' \
    'CONFIG_AP=y' \
    'CONFIG_WPS=y' \
    'CONFIG_EAP=y' \
    'CONFIG_PKCS12=y' \
    'CONFIG_DEBUG_FILE=y' \
    > .config
# Toolchain OpenSSL is built with OPENSSL_NO_MD4; drop the (unused for WPA2-PSK)
# EVP_md4 reference so the crypto backend compiles and links.
RUN sed -i 's/EVP_md4()/NULL/g' ../src/crypto/crypto_openssl.c
# Install to /usr/bin (the base image is usrmerged: /usr/sbin -> /usr/bin).
RUN make -j$(nproc) BINDIR=/usr/bin
RUN make install DESTDIR=/wpa BINDIR=/usr/bin
# D-Bus + systemd service files so NetworkManager can use wpa_supplicant.
# Written explicitly (the upstream .in templates use @BINDIR@ placeholders).
RUN mkdir -p /wpa/usr/share/dbus-1/system-services /wpa/usr/share/dbus-1/system.d /wpa/usr/lib/systemd/system && \
    cp dbus/dbus-wpa_supplicant.conf /wpa/usr/share/dbus-1/system.d/wpa_supplicant.conf && \
    printf '%s\n' \
      '[D-BUS Service]' \
      'Name=fi.w1.wpa_supplicant1' \
      'Exec=/usr/bin/wpa_supplicant -u -O /run/wpa_supplicant' \
      'User=root' \
      'SystemdService=wpa_supplicant.service' \
      > /wpa/usr/share/dbus-1/system-services/fi.w1.wpa_supplicant1.service && \
    printf '%s\n' \
      '[Unit]' \
      'Description=WPA supplicant' \
      'Before=network.target' \
      'After=dbus.service' \
      'Wants=network.target' \
      '[Service]' \
      'Type=dbus' \
      'BusName=fi.w1.wpa_supplicant1' \
      'ExecStart=/usr/bin/wpa_supplicant -u -O /run/wpa_supplicant' \
      'ExecReload=/bin/kill -HUP $MAINPID' \
      '[Install]' \
      'WantedBy=multi-user.target' \
      'Alias=dbus-fi.w1.wpa_supplicant1.service' \
      > /wpa/usr/lib/systemd/system/wpa_supplicant.service


# hostapd — test-only AP for exercising wifi association against mac80211_hwsim
FROM toolchain AS hostapd
COPY --from=libnl /libnl /
ARG HOSTAPD_VERSION=2.11
RUN mkdir -p /hostapd
WORKDIR /build
RUN curl -L https://w1.fi/releases/hostapd-${HOSTAPD_VERSION}.tar.gz -o hostapd.tar.gz && tar -xzf hostapd.tar.gz && rm hostapd.tar.gz && mv hostapd-* hostapd-src
WORKDIR /build/hostapd-src/hostapd
RUN printf '%s\n' \
    'CONFIG_DRIVER_NL80211=y' \
    'CONFIG_LIBNL32=y' \
    'CONFIG_IEEE80211N=y' \
    'CONFIG_IEEE80211AC=y' \
    > .config
RUN sed -i 's/EVP_md4()/NULL/g' ../src/crypto/crypto_openssl.c
RUN make -j$(nproc) BINDIR=/usr/bin
RUN make install DESTDIR=/hostapd BINDIR=/usr/bin


# libndp — IPv6 router/neighbour discovery, required by NetworkManager
FROM toolchain AS libndp
ARG LIBNDP_VERSION=1.9
RUN mkdir -p /libndp
WORKDIR /build
RUN curl -L https://github.com/jpirko/libndp/archive/refs/tags/v${LIBNDP_VERSION}.tar.gz -o libndp.tar.gz && tar -xzf libndp.tar.gz && rm libndp.tar.gz && mv libndp-* libndp-src
WORKDIR /build/libndp-src
RUN ./autogen.sh 2>/dev/null || true
# libndp 1.9 has musl pointer-type mismatches that GCC 14+ treats as errors.
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking \
    CFLAGS="-O2 -g -Wno-error=incompatible-pointer-types -Wno-error=int-conversion"
RUN make -j$(nproc) && make install DESTDIR=/libndp


# wireless-regdb — regulatory database (loaded by cfg80211 from /lib/firmware)
FROM toolchain AS wireless-regdb
ARG WIRELESS_REGDB_VERSION=2024.10.07
# Use /usr/lib (the base image is usrmerged; /lib -> usr/lib). Installing to a
# top-level /lib would create a real dir that conflicts with the /lib symlink.
RUN mkdir -p /wireless-regdb/usr/lib/firmware
WORKDIR /build
RUN curl -L https://www.kernel.org/pub/software/network/wireless-regdb/wireless-regdb-${WIRELESS_REGDB_VERSION}.tar.xz -o regdb.tar.xz && tar -xf regdb.tar.xz && rm regdb.tar.xz && mv wireless-regdb-* regdb-src
RUN cp regdb-src/regulatory.db regdb-src/regulatory.db.p7s /wireless-regdb/usr/lib/firmware/


# ncurses — provides the termcap library (libtinfo) that the toolchain's
# libreadline needs; without it nmcli fails to link (undefined tgetent, tputs…).
FROM toolchain AS ncurses
ARG NCURSES_VERSION=6.5
RUN mkdir -p /ncurses
WORKDIR /build
RUN curl -L https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz -o ncurses.tar.gz && tar -xzf ncurses.tar.gz && rm ncurses.tar.gz && mv ncurses-* ncurses-src
WORKDIR /build/ncurses-src
RUN ./configure ${COMMON_CONFIGURE_ARGS} --with-shared --enable-termcap --disable-widec \
    --without-debug --without-ada --without-cxx --without-cxx-binding \
    --without-tests --disable-stripping --without-manpages
# install.libs installs just the libraries/headers (libncurses); the full
# `install` cross-runs `tic` to build the terminfo DB, which fails here and is
# not needed (we only want the termcap symbols for readline).
RUN make -j$(nproc) libs && make install.libs install.includes DESTDIR=/ncurses


# libxslt — provides xsltproc, a build-time requirement of NetworkManager
FROM toolchain AS libxslt
ARG LIBXSLT_VERSION=1.1.42
RUN mkdir -p /libxslt
WORKDIR /build
RUN curl -L https://download.gnome.org/sources/libxslt/1.1/libxslt-${LIBXSLT_VERSION}.tar.xz -o libxslt.tar.xz && tar -xf libxslt.tar.xz && rm libxslt.tar.xz && mv libxslt-* libxslt-src
WORKDIR /build/libxslt-src
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --without-python
RUN make -j$(nproc) && make install DESTDIR=/libxslt


# NetworkManager
FROM toolchain AS networkmanager
COPY --from=glib2 /glib2 /
COPY --from=pcre2 /pcre2 /
COPY --from=libndp /libndp /
COPY --from=libnl /libnl /
COPY --from=libxslt /libxslt /
COPY --from=ncurses /ncurses /
# The toolchain's libreadline needs termcap symbols from libncurses; make the
# readline pkg-config dependency pull it in so nmcli links cleanly.
RUN sed -i 's/-lreadline/-lreadline -lncurses/' /usr/lib/pkgconfig/readline.pc /usr/lib64/pkgconfig/readline.pc 2>/dev/null || true
ARG NM_VERSION=1.50.0
RUN mkdir -p /networkmanager
WORKDIR /build
RUN curl -L https://download.gnome.org/sources/NetworkManager/1.50/NetworkManager-${NM_VERSION}.tar.xz -o nm.tar.xz && tar -xf nm.tar.xz && rm nm.tar.xz && mv NetworkManager-* nm-src
WORKDIR /build/nm-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} --sbindir=bin \
    -Dpolkit=false -Dwifi=true -Diwd=false -Dwext=false \
    -Dnmcli=true -Dnmtui=false -Dmodem_manager=false -Dppp=false -Dovs=false \
    -Dintrospection=false -Ddocs=false -Dtests=no -Dlibpsl=false -Dqt=false \
    -Dselinux=false -Dvapi=false -Difcfg_rh=false -Dlibaudit=no \
    -Dsession_tracking=systemd -Dsuspend_resume=systemd -Dsystemd_journal=true \
    -Dcrypto=null -Dconfig_dns_rc_manager_default=symlink \
    -Dc_link_args=-lncurses
RUN DESTDIR=/networkmanager ninja -C buildDir install


# ===========================================================================
# M3: audio — PipeWire + WirePlumber
# ===========================================================================

# ALSA library
FROM toolchain AS alsa-lib
ARG ALSA_VERSION=1.2.12
RUN mkdir -p /alsa-lib
WORKDIR /build
RUN curl -L https://www.alsa-project.org/files/pub/lib/alsa-lib-${ALSA_VERSION}.tar.bz2 -o alsa-lib.tar.bz2 && tar -xjf alsa-lib.tar.bz2 && rm alsa-lib.tar.bz2 && mv alsa-lib-* alsa-lib-src
WORKDIR /build/alsa-lib-src
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --disable-python
RUN make -j$(nproc) && make install DESTDIR=/alsa-lib


# ALSA UCM configuration (data files describing sound cards)
FROM toolchain AS alsa-ucm-conf
ARG ALSA_UCM_VERSION=1.2.12
RUN mkdir -p /alsa-ucm-conf
WORKDIR /build
RUN curl -L https://www.alsa-project.org/files/pub/lib/alsa-ucm-conf-${ALSA_UCM_VERSION}.tar.bz2 -o ucm.tar.bz2 && tar -xjf ucm.tar.bz2 && rm ucm.tar.bz2 && mv alsa-ucm-conf-* ucm-src
RUN mkdir -p /alsa-ucm-conf/usr/share/alsa && cp -a ucm-src/ucm2 /alsa-ucm-conf/usr/share/alsa/


# PipeWire
FROM toolchain AS pipewire
COPY --from=alsa-lib /alsa-lib /
COPY --from=glib2 /glib2 /
COPY --from=pcre2 /pcre2 /
ARG PIPEWIRE_VERSION=1.2.7
RUN mkdir -p /pipewire
WORKDIR /build
RUN curl -L https://gitlab.freedesktop.org/pipewire/pipewire/-/archive/${PIPEWIRE_VERSION}/pipewire-${PIPEWIRE_VERSION}.tar.gz -o pipewire.tar.gz && tar -xzf pipewire.tar.gz && rm pipewire.tar.gz && mv pipewire-* pipewire-src
WORKDIR /build/pipewire-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} \
    -Dalsa=enabled -Dpipewire-alsa=enabled \
    -Ddbus=enabled -Dsystemd=enabled -Dsystemd-user-service=enabled \
    -Dbluez5=disabled -Djack=disabled -Dvulkan=disabled -Dv4l2=disabled \
    -Dlibcamera=disabled -Dexamples=disabled -Dtests=disabled -Dman=disabled \
    -Dgstreamer=disabled -Dsndfile=disabled -Dreadline=disabled -Draop=disabled \
    -Dlibpulse=disabled -Davahi=disabled -Dx11=disabled -Dlegacy-rtkit=true \
    -Dudev=enabled -Dsession-managers=[]
RUN DESTDIR=/pipewire ninja -C buildDir install


# WirePlumber (session manager; uses its bundled Lua)
FROM toolchain AS wireplumber
COPY --from=glib2 /glib2 /
COPY --from=pcre2 /pcre2 /
COPY --from=pipewire /pipewire /
COPY --from=alsa-lib /alsa-lib /
ARG WIREPLUMBER_VERSION=0.5.7
RUN mkdir -p /wireplumber
WORKDIR /build
RUN curl -L https://gitlab.freedesktop.org/pipewire/wireplumber/-/archive/${WIREPLUMBER_VERSION}/wireplumber-${WIREPLUMBER_VERSION}.tar.gz -o wireplumber.tar.gz && tar -xzf wireplumber.tar.gz && rm wireplumber.tar.gz && mv wireplumber-* wireplumber-src
WORKDIR /build/wireplumber-src
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} \
    -Dsystem-lua=false -Dintrospection=disabled -Ddoc=disabled -Dtests=false \
    -Delogind=disabled -Dsystemd=enabled -Dsystemd-user-service=true -Dsystemd-system-service=false
RUN DESTDIR=/wireplumber ninja -C buildDir install


# ===========================================================================
# Final assembly
# ===========================================================================

FROM scratch AS sway-rootfs
COPY --from=wayland /wayland /
COPY --from=libdrm /libdrm /
COPY --from=mesa /mesa /
COPY --from=xkeyboard-config /xkeyboard-config /
COPY --from=libxkb /libxkb /
COPY --from=pixman /pixman /
COPY --from=libevdev /libevdev /
COPY --from=libinput /libinput /
COPY --from=hwdata /hwdata /
COPY --from=libdisplay-info /libdisplay-info /
COPY --from=cairo /cairo /
COPY --from=wlroots /wlroots /
COPY --from=pcre2 /pcre2 /
COPY --from=glib2 /glib2 /
COPY --from=freetype /freetype /
COPY --from=harfbuzz /harfbuzz /
COPY --from=fribidi /fribidi /
COPY --from=fontconfig /fontconfig /
COPY --from=pango /pango /
COPY --from=libseat /libseat /
COPY --from=sway /sway /
COPY --from=tllist /tllist /
COPY --from=fcft /fcft /
COPY --from=foot /foot /
COPY --from=libpng /libpng /
COPY --from=grim /grim /
# M2: networking
COPY --from=libnl /libnl /
COPY --from=wpa-supplicant /wpa /
COPY --from=hostapd /hostapd /
COPY --from=libndp /libndp /
COPY --from=networkmanager /networkmanager /
COPY --from=wireless-regdb /wireless-regdb /
COPY --from=ncurses /ncurses /
# M3: audio
COPY --from=alsa-lib /alsa-lib /
COPY --from=alsa-ucm-conf /alsa-ucm-conf /
COPY --from=pipewire /pipewire /
COPY --from=wireplumber /wireplumber /


FROM ${BASE_IMAGE} AS default
# Built desktop stack
COPY --from=sway-rootfs / /
# Runtime libraries provided by the toolchain but not the base image
COPY --from=toolchain /usr/lib/libffi.so* /usr/lib/
COPY --from=toolchain /usr/lib/libexpat.so* /usr/lib/
COPY --from=toolchain /usr/lib/libjson-c.so* /usr/lib/
COPY --from=toolchain /usr/lib/libstdc++.so.6* /usr/lib/
COPY --from=toolchain /usr/lib/libgcc_s.so* /usr/lib/
COPY --from=toolchain /usr/lib/libreadline.so* /usr/lib/
# Static config / launch layer
COPY rootfs/ /
# Desktop user (logind grants device ACLs to the active tty1 session via uaccess)
RUN ldconfig 2>/dev/null || true; \
    groupadd -f audio; groupadd -f video; groupadd -f render; \
    useradd -m -u 1000 -s /bin/bash -G audio,video,render sway && \
    install -d -o sway -g sway /home/sway/.config && \
    printf '%s\n' \
      '# Launch Sway on the first VT after autologin.' \
      'if [ "$(tty)" = "/dev/tty1" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then' \
      '  [ -f /etc/sway-desktop/env ] && . /etc/sway-desktop/env' \
      '  [ -f /etc/sway-desktop/env.local ] && . /etc/sway-desktop/env.local' \
      '  exec sway -d >/tmp/sway.log 2>&1' \
      'fi' > /home/sway/.bash_profile && \
    chown sway:sway /home/sway/.bash_profile && \
    systemctl enable getty@tty1.service 2>/dev/null || true; \
    # M2: NetworkManager is the network manager. (systemd-networkd is left for
    # the Kairos init layer to enable; it is disabled at runtime in favour of NM
    # via the cloud-config drop-in shipped below.)
    systemctl enable NetworkManager.service 2>/dev/null || true; \
    systemctl enable wpa_supplicant.service 2>/dev/null || true; \
    # M3: PipeWire + WirePlumber as per-user services
    systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
