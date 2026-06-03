# Sway desktop on Hadron

A full [Sway](https://swaywm.org/) Wayland desktop built on top of the minimal
Hadron base image, with NetworkManager, PipeWire audio, wifi and bluetooth.
Everything is compiled from source against the Hadron musl toolchain, in the
same multi-stage style as [`../add-packages/Dockerfile.doom`](../add-packages/Dockerfile.doom).

This example is intentionally self-contained (single `Dockerfile`, a `rootfs/`
overlay, a `test/` harness) so it can later be split into its own repository.

> Status: built incrementally. See the milestone table below and the design doc
> at `docs/superpowers/specs/2026-06-03-sway-desktop-example-design.md`.

## What's inside

- **Compositor:** Sway (wlroots), running under **systemd-logind** seat
  management — an autologin user on `tty1` launches Sway, and `pam_systemd`
  registers a logind session that grants DRM/input device access.
- **Terminal:** `foot`.
- **Display stack:** wayland, wlroots, Mesa, libinput, libxkbcommon, pixman,
  pango/cairo, freetype/fontconfig (+ DejaVu fonts).
- *(later milestones)* NetworkManager + wpa_supplicant, PipeWire + WirePlumber,
  BlueZ, plus desktop polish (waybar, mako, fuzzel, …) and real-hardware firmware.

## Build

```sh
# Build the desktop image (extends ghcr.io/kairos-io/hadron:main)
docker build -t sway-desktop:dev examples/sway-desktop
```

To produce a bootable artifact, wrap it with the Kairos init layer and run it
through AuroraBoot — the test harness below does exactly this.

## Run on real hardware

The image is a Kairos/Hadron OS image. Wrap it with the Kairos init layer, build
an ISO/disk with AuroraBoot, and install it to a machine. On boot it autologins
the `sway` user on `tty1` and starts Sway. (Real wifi/bluetooth/audio require the
`linux-firmware` blobs — see milestone M6.)

## Test (headless, autonomous)

The `test/` harness builds the image, wraps it with Kairos, builds a bootable ISO
with AuroraBoot, boots it headless in QEMU, and asserts that the desktop and each
subsystem come up — entirely without a display. It exercises even wifi and
bluetooth using virtual kernel devices (`mac80211_hwsim`, `hci_vhci`).

```sh
# Run all assertions up to a given milestone (default M0)
MILESTONE=M1 examples/sway-desktop/test/run.sh

# Faster iteration
SKIP_BUILD=1 examples/sway-desktop/test/run.sh   # reuse built images
SKIP_ISO=1   examples/sway-desktop/test/run.sh   # reuse existing ISO
```

The guest emits `SWAYTEST: PASS/FAIL <name>` markers on the serial console; the
harness parses them and exits non-zero on any failure. Screenshots captured with
`grim` are written to a scratch disk and extracted to `test/artifacts/`.

### Users and login

The image bakes in **no user**. The desktop user is defined at install time via
a Kairos **cloud-config** (`users:` block — see `cloud-config.yaml`) and lives
on the persistent `/home`. On boot the **`ly`** display manager (TUI, on tty1)
authenticates that user and launches the Sway session
(`/usr/share/wayland-sessions/sway.desktop` → `start-sway`), giving Sway a
proper logind seat session and the DRM/KMS backend.

### Production vs test launch

`ly`'s interactive TUI login can't be driven over a headless VT, and headless
QEMU has no active VT / `virtio-gpu` gets zero scanouts (`-display none`). So the
**test image** (via `test/Dockerfile.test`) creates a throwaway user, **masks
`ly`**, and launches Sway from a dedicated `sway-headless.service` using the
wlroots **headless backend + pixman** renderer — the canonical way Sway is
exercised in CI. The harness still asserts `ly` is installed and wired up. The
real `ly` → DRM login path is validated on physical hardware.

## Milestones

All green and verified by the headless harness (M6's firmware blobs excepted —
those are hardware-validated):

| # | Scope | Autonomous test |
|---|-------|-----------------|
| M0 | e2e QEMU harness | boot, serial markers, scratch-disk round-trip |
| M1 | Sway + logind seat + foot | logind session, `swaymsg`, active output, grim screenshot |
| M2 | NetworkManager + wifi | DHCP on virtio-net + `mac80211_hwsim`/hostapd association |
| M3 | PipeWire + WirePlumber | user services up, `wpctl` sink from emulated HDA |
| M4 | BlueZ bluetooth | virtual adapter via `hci_vhci`+`btvirt`, `bluetoothctl`, bluez5 plugin |
| M5 | Desktop polish | swaybar, mako, fuzzel, wl-clipboard, slurp, swayidle |
| M6 | Real-hardware firmware | `regulatory.db` present; vendor blobs via `--build-arg FIRMWARE=true` (manual HW validation) |

### Real hardware

The default image is VM-slim. For real laptops, build with the firmware subset:

```sh
docker build --build-arg FIRMWARE=true -t sway-desktop:hw examples/sway-desktop
```

This bundles a curated `linux-firmware` subset (iwlwifi, ath, rtw, brcm, intel
bluetooth, i915, amdgpu, …) into `/lib/firmware`. Wifi/BT/audio on real hardware
is validated by booting on a physical machine.

### Hardware GPU (accelerated GL)

The default Mesa build (`GPU=vm`) ships only software/virtual drivers
(virgl/softpipe/svga) — correct for QEMU and needs nothing from LLVM. For
accelerated GL on real Intel/AMD laptops, build with `GPU=full`:

```sh
docker build --build-arg GPU=full --build-arg FIRMWARE=true \
  -t sway-desktop:hw examples/sway-desktop
```

`GPU=full` builds Mesa `iris` (Intel) + `radeonsi` (AMD), which require LLVM.
That LLVM/clang/libclc + SPIRV stack now ships in `hadron-toolchain` itself
(built against the same musl ABI — no Alpine cross-mix), so the example flips
`-Dllvm=true`, sets `-Dcpp_rtti=false` (the toolchain's libLLVM is built without
RTTI), and bundles `libLLVM.so` + `libelf.so` into the image (the megadriver
links them at runtime, ~125 MB).

**This requires a `hadron-toolchain` image that includes the LLVM stack** (see
`docs/superpowers/specs/2026-06-03-toolchain-llvm-for-mesa.md`). Once the main
toolchain Dockerfile is rebuilt/published, plain `docker build --build-arg
GPU=full …` works. To build/test *before* that publish, assemble a derived
toolchain locally (published toolchain + the LLVM/SPIRV stack) and point the
example at it:

```sh
# build hadron-toolchain:llvm = published toolchain + LLVM/clang/libclc + SPIRV
docker build -t hadron-toolchain:llvm /tmp/toolchain-llvm   # recipe in the spec

docker build \
  --build-context ghcr.io/kairos-io/hadron-toolchain:main=docker-image://hadron-toolchain:llvm \
  --build-arg GPU=full --build-arg FIRMWARE=true \
  -t sway-desktop:hw examples/sway-desktop
```

Validated this way: Mesa 25.3 builds `iris`/`radeonsi`/`virgl`/`softpipe` into
`libgallium-25.3.0.so` against the Hadron-built libLLVM, and the megadriver
resolves all runtime symbols in the image. Actual GPU *rendering* is validated
on physical hardware — QEMU has no real GPU, so a VM boot falls back to
softpipe/virgl (software) while the hardware drivers ride along for real metal.

## Layout

```
examples/sway-desktop/
  Dockerfile          # multi-stage build of the whole desktop stack
  cloud-config.yaml   # example Kairos install config (creates the desktop user)
  rootfs/             # overlay: sway config, ly session entry, launcher, env
  test/
    run.sh            # build -> kairos -> ISO -> QEMU -> assert
    Dockerfile.test   # injects in-guest test instrumentation
    guest/check.sh    # in-guest assertions (emit SWAYTEST: markers)
    artifacts/        # console logs + screenshots (gitignored)
```
