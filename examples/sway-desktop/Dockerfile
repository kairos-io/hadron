# Sway desktop environment for Hadron.
#
# This builds a full Wayland desktop (Sway) on top of the Hadron base image,
# with NetworkManager, PipeWire audio, wifi and bluetooth. Everything is built
# from source against the Hadron musl toolchain, following the same multi-stage
# pattern as examples/add-packages/Dockerfile.doom.
#
# Build:
#   docker build -t sway-desktop:dev examples/sway-desktop
#
# The image is meant to be wrapped with the Kairos init layer and turned into a
# bootable artifact (see test/run.sh for the full build -> boot -> test loop).
#
# Milestones are built incrementally; see
# docs/superpowers/specs/2026-06-03-sway-desktop-example-design.md
#
# ---------------------------------------------------------------------------
# M0: skeleton. The desktop stack is added in later milestones. For now this is
# just the base image plus the rootfs overlay, so the end-to-end test harness
# (build -> kairos layer -> AuroraBoot ISO -> QEMU) can be brought up first.
# ---------------------------------------------------------------------------

ARG BASE_IMAGE=ghcr.io/kairos-io/hadron:main

FROM ${BASE_IMAGE} AS default
COPY rootfs/ /
