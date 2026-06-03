#!/bin/sh
# In-guest assertion script for the sway-desktop e2e harness.
#
# It is run by swaytest.service after boot, emits "SWAYTEST: ..." markers on the
# first serial port (/dev/ttyS0, captured by the host harness), then powers the
# machine off. Checks are milestone-aware: the target milestone is read from
# /etc/swaytest-milestone and all checks up to and including it are run.
#
# Marker protocol (host greps these):
#   SWAYTEST: BEGIN milestone=<M>
#   SWAYTEST: INFO  <text>
#   SWAYTEST: PASS  <name>
#   SWAYTEST: FAIL  <name> [detail]
#   SWAYTEST: DONE
set -u

SERIAL=/dev/ttyS0
MS="$(cat /etc/swaytest-milestone 2>/dev/null || echo M0)"
DESKUSER="${DESKUSER:-sway}"   # desktop user created in M1

# milestone ordinal, for ">= Mx" comparisons
ord() { case "$1" in M0) echo 0;; M1) echo 1;; M2) echo 2;; M3) echo 3;; M4) echo 4;; M5) echo 5;; M6) echo 6;; *) echo 0;; esac; }
TARGET="$(ord "$MS")"
want() { [ "$(ord "$1")" -le "$TARGET" ]; }

say()  { echo "SWAYTEST: $*" > "$SERIAL" 2>/dev/null; echo "SWAYTEST: $*" > /dev/console 2>/dev/null; }
info() { say "INFO  $*"; }
pass() { say "PASS  $1"; }
fail() { say "FAIL  $1${2:+ ($2)}"; }

# assert <name> <cmd...> : run cmd, PASS on exit 0 else FAIL
assert() { name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

# wait_for <secs> <cmd...> : poll until cmd succeeds or timeout
wait_for() { secs="$1"; shift; i=0; while [ "$i" -lt "$secs" ]; do if "$@" >/dev/null 2>&1; then return 0; fi; i=$((i+1)); sleep 1; done; return 1; }

# locate the host-provided scratch disk (attached with serial=swayscratch)
scratch_dev() {
  if [ -b /dev/disk/by-id/virtio-swayscratch ]; then
    readlink -f /dev/disk/by-id/virtio-swayscratch; return 0
  fi
  # fallback: the only ~64M virtio block device
  for d in /sys/block/vd*; do
    [ -e "$d/size" ] || continue
    sz=$(cat "$d/size"); # 512-byte sectors; 64M = 131072
    if [ "$sz" -ge 100000 ] && [ "$sz" -le 200000 ]; then echo "/dev/$(basename "$d")"; return 0; fi
  done
  return 1
}

# screenshot <out.png-on-scratch> : grim into the scratch disk for the host to read.
# Writes a tar (name + data) to the raw scratch device so the host can extract it
# without needing a filesystem driver (9P_FS is absent in the kernel).
SHOT_DIR=/run/swaytest
screenshot() {
  name="$1"; dev="$(scratch_dev)" || return 1
  mkdir -p "$SHOT_DIR"
  if XDG_RUNTIME_DIR=/run/user/$(id -u "$DESKUSER" 2>/dev/null || echo 0) \
     grim "$SHOT_DIR/$name" >/dev/null 2>&1; then
    ( cd "$SHOT_DIR" && tar -cf - "$name" ) | dd of="$dev" bs=1M conv=notrunc 2>/dev/null
    return 0
  fi
  return 1
}

say "BEGIN milestone=$MS"

# ----- M0: boot + harness plumbing ------------------------------------------
if want M0; then
  pass boot
  info "kernel=$(uname -r 2>/dev/null)"
  info "systemd=$(systemctl --version 2>/dev/null | head -1)"
  info "dri=$(ls /dev/dri 2>/dev/null | tr '\n' ' ')"
  # prove the scratch disk round-trip works (used for screenshots in M1+)
  dev="$(scratch_dev)"
  if [ -n "$dev" ] && [ -b "$dev" ]; then
    info "scratch=$dev"
    if echo "swaytest-scratch-ok" | dd of="$dev" bs=512 count=1 conv=notrunc 2>/dev/null && \
       dd if="$dev" bs=512 count=1 2>/dev/null | grep -q swaytest-scratch-ok; then
      pass scratch_disk
    else
      fail scratch_disk write_readback
    fi
  else
    fail scratch_disk no_device
  fi
fi

# ----- M1: sway display + logind seat ---------------------------------------
if want M1; then
  : # implemented in M1
fi

say "DONE"
sync
sleep 1
systemctl poweroff --no-block 2>/dev/null || poweroff -f 2>/dev/null || reboot -f
