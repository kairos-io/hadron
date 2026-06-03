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
  UID_SWAY="$(id -u "$DESKUSER" 2>/dev/null || echo 1000)"
  RT="/run/user/$UID_SWAY"

  # logind should have created a graphical session on seat0 for the autologin user
  if wait_for 60 sh -c "loginctl list-sessions 2>/dev/null | grep -q $DESKUSER"; then
    pass logind_session
    info "session=$(loginctl list-sessions --no-legend 2>/dev/null | tr -s ' ' | head -1)"
  else
    fail logind_session
  fi

  # sway IPC socket appears once the compositor is up
  find_sock() { ls "$RT"/sway-ipc.*.sock 2>/dev/null | head -1; }
  if ! wait_for 30 sh -c "ls $RT/sway-ipc.*.sock >/dev/null 2>&1"; then
    # diagnostics: why didn't sway come up?
    info "diag getty@tty1=$(systemctl is-active getty@tty1.service 2>/dev/null)"
    info "diag sessions=[$(loginctl list-sessions --no-legend 2>/dev/null | tr '\n' ';')]"
    info "diag run_user=[$(ls /run/user 2>/dev/null | tr '\n' ' ')]"
    info "diag sway_proc=[$(pgrep -a sway 2>/dev/null | head -1)]"
    info "diag tty1_exec=$(systemctl show -p ExecStart getty@tty1.service 2>/dev/null | grep -o 'autologin [a-z]*' | head -1)"
    journalctl -b -u getty@tty1.service --no-pager 2>/dev/null | tail -6 | while read -r l; do info "diag j: $l"; done
    [ -f /tmp/sway.log ] && tail -12 /tmp/sway.log | while read -r l; do info "diag sway: $l"; done || info "diag sway: no /tmp/sway.log"
  fi
  if wait_for 90 sh -c "ls $RT/sway-ipc.*.sock >/dev/null 2>&1"; then
    SOCK="$(find_sock)"
    pass sway_ipc_socket
    info "swaysock=$SOCK"
    # query sway over IPC (as the desktop user)
    if su "$DESKUSER" -c "SWAYSOCK=$SOCK swaymsg -t get_version" >/tmp/swayver 2>/dev/null; then
      pass sway_running
      info "sway=$(tr -d '\n' </tmp/swayver | cut -c1-80)"
    else
      fail sway_running
    fi
    # at least one active output
    if su "$DESKUSER" -c "SWAYSOCK=$SOCK swaymsg -t get_outputs" 2>/dev/null | grep -q '"active": true'; then
      pass sway_output
    else
      fail sway_output
    fi
    # foot terminal: verify it launches under sway, connects to the compositor,
    # and runs a command. (A persistent autostarted foot exits on stdin EOF in a
    # headless/no-input VM, so we drive it explicitly instead of pgrep.)
    WD="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | grep -v '\.lock' | head -1)" 2>/dev/null)"
    WD="${WD:-wayland-1}"
    if timeout 15 su "$DESKUSER" -c "XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=$WD foot -e /bin/true" >/tmp/footerr 2>&1; then
      pass foot_launch
    else
      fail foot_launch
      tail -5 /tmp/footerr 2>/dev/null | while read -r l; do info "diag foot: $l"; done
    fi
  else
    fail sway_ipc_socket
  fi

  # screenshot proof: grim must succeed and produce a real PNG; ship it to host
  WD="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | grep -v '\.lock' | head -1)" 2>/dev/null)"
  WD="${WD:-wayland-1}"
  mkdir -p "$SHOT_DIR" && chmod 0777 "$SHOT_DIR"
  if su "$DESKUSER" -c "XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=$WD grim $SHOT_DIR/m1-sway.png" 2>/tmp/grimerr; then
    sz=$(stat -c%s "$SHOT_DIR/m1-sway.png" 2>/dev/null || echo 0)
    info "screenshot_bytes=$sz"
    if [ "$sz" -gt 500 ] && head -c8 "$SHOT_DIR/m1-sway.png" | grep -q PNG; then pass screenshot; else fail screenshot "small_or_not_png:$sz"; fi
    dev="$(scratch_dev)" && ( cd "$SHOT_DIR" && tar -cf - m1-sway.png ) | dd of="$dev" bs=1M conv=notrunc 2>/dev/null
  else
    fail screenshot "grim:$(tr -d '\n' </tmp/grimerr | cut -c1-80)"
  fi
fi

say "DONE"
sync
sleep 1
systemctl poweroff --no-block 2>/dev/null || poweroff -f 2>/dev/null || reboot -f
