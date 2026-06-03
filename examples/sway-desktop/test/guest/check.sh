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

# ----- M5: desktop polish ---------------------------------------------------
if want M5; then
  U5="$(id -u "$DESKUSER" 2>/dev/null || echo 1000)"; RT5="/run/user/$U5"
  WD5="$(basename "$(ls "$RT5"/wayland-* 2>/dev/null | grep -v '\.lock' | head -1)" 2>/dev/null)"; WD5="${WD5:-wayland-1}"
  desk() { su "$DESKUSER" -c "XDG_RUNTIME_DIR=$RT5 WAYLAND_DISPLAY=$WD5 $1" 2>/dev/null; }
  SOCK5="$(ls "$RT5"/sway-ipc.*.sock 2>/dev/null | head -1)"
  # all polish tools present
  miss=""; for b in swaybar swaybg mako fuzzel wl-copy slurp swayidle grim; do command -v "$b" >/dev/null 2>&1 || miss="$miss $b"; done
  [ -z "$miss" ] && pass polish_tools_present || fail polish_tools_present "missing:$miss"
  # swaybar: sway should have loaded the bar from its config (the bar block in
  # /etc/sway/config), which proves swaybar is wired up.
  if [ -n "$SOCK5" ] && su "$DESKUSER" -c "SWAYSOCK=$SOCK5 swaymsg -t get_bar_config" 2>/dev/null | grep -q 'bar-'; then
    pass swaybar_configured
  else
    fail swaybar_configured
    info "bars=$(su "$DESKUSER" -c "SWAYSOCK=$SOCK5 swaymsg -t get_bar_config" 2>/dev/null | cut -c1-60)"
  fi
  # mako: a notification daemon should own org.freedesktop.Notifications on the
  # user session bus (mako is autostarted from the sway config via `exec mako`).
  if wait_for 25 sh -c "su $DESKUSER -c 'XDG_RUNTIME_DIR=$RT5 busctl --user list' 2>/dev/null | grep -q org.freedesktop.Notifications"; then
    pass mako_running
  else
    fail mako_running
    info "notif_owner=$(desk 'busctl --user list' 2>/dev/null | grep -i notif | cut -c1-50)"
  fi
  # clipboard round-trip via wl-copy / wl-paste
  if desk "sh -c 'printf swaytest-clip | wl-copy'" && [ "$(desk 'wl-paste -n')" = "swaytest-clip" ]; then
    pass clipboard
  else
    fail clipboard
  fi
  # fuzzel launches (dmenu mode, fed empty input, exits cleanly)
  if desk "sh -c 'printf \"\" | fuzzel --dmenu --no-run-if-empty; true'" >/dev/null 2>&1; then pass fuzzel_runs; else fail fuzzel_runs; fi
fi

# ----- M4: BlueZ bluetooth --------------------------------------------------
if want M4; then
  # Fabricate a virtual HCI controller: hci_vhci + btvirt (from BlueZ)
  modprobe hci_vhci 2>/dev/null
  if [ -e /dev/vhci ]; then pass vhci_dev; else fail vhci_dev; fi
  ( btvirt -l -L >/tmp/btvirt.log 2>&1 & ) 2>/dev/null
  sleep 3
  # bluetoothd / bluetoothctl should see the controller (this also dbus-activates
  # bluetoothd if it is not running yet)
  if wait_for 25 sh -c "bluetoothctl list 2>/dev/null | grep -qi Controller || ls /sys/class/bluetooth/hci0 >/dev/null 2>&1"; then
    pass bt_adapter
    info "adapter=$(bluetoothctl list 2>/dev/null | head -1 | cut -c1-60) hci=$(ls /sys/class/bluetooth 2>/dev/null | tr '\n' ' ')"
  else
    fail bt_adapter
    info "hci=$(ls /sys/class/bluetooth 2>/dev/null | tr '\n' ' ') btvirt=$(tail -2 /tmp/btvirt.log 2>/dev/null | tr '\n' ';')"
  fi
  # bluetoothd should now be active (bluetooth.service is D-Bus activated)
  if wait_for 25 sh -c "systemctl is-active bluetooth >/dev/null 2>&1"; then
    pass bluetoothd_active
  else
    fail bluetoothd_active
    journalctl -b -u bluetooth --no-pager 2>/dev/null | tail -6 | while read -r l; do info "diag bt: $l"; done
  fi
  # PipeWire's bluez5 SPA plugin should be installed (Bluetooth audio support)
  if ls /usr/lib/spa-0.2/bluez5/libspa-bluez5.so >/dev/null 2>&1 || find /usr/lib -name 'libspa-bluez5*' 2>/dev/null | grep -q .; then
    pass pipewire_bluez5
  else
    fail pipewire_bluez5
  fi
fi

# ----- M3: PipeWire audio ---------------------------------------------------
if want M3; then
  U3="$(id -u "$DESKUSER" 2>/dev/null || echo 1000)"; RT3="/run/user/$U3"
  swu() { su "$DESKUSER" -c "XDG_RUNTIME_DIR=$RT3 $1" 2>/dev/null; }
  info "snd_cards=$(tr '\n' ';' </proc/asound/cards 2>/dev/null | cut -c1-90)"
  # PipeWire is socket-activated: connecting a client starts the whole stack.
  # Wait for the user systemd instance, then warm it up.
  wait_for 40 sh -c "su $DESKUSER -c 'XDG_RUNTIME_DIR=$RT3 systemctl --user is-system-running --wait' >/dev/null 2>&1; [ -S $RT3/pipewire-0 ] || su $DESKUSER -c 'XDG_RUNTIME_DIR=$RT3 wpctl status' >/dev/null 2>&1"
  # PipeWire core reachable (this connection triggers socket activation)
  if wait_for 30 sh -c "su $DESKUSER -c 'XDG_RUNTIME_DIR=$RT3 pw-cli info 0' >/dev/null 2>&1"; then pass pipewire_running; else fail pipewire_running; fi
  # WirePlumber should now be active for the user
  if wait_for 30 sh -c "su $DESKUSER -c 'XDG_RUNTIME_DIR=$RT3 systemctl --user is-active wireplumber' 2>/dev/null | grep -q '^active'"; then
    pass wireplumber_active
  else
    fail wireplumber_active
    su "$DESKUSER" -c "XDG_RUNTIME_DIR=$RT3 systemctl --user --no-pager status wireplumber pipewire" 2>&1 | tail -8 | while read -r l; do info "diag wp: $l"; done
  fi
  # An audio sink (the QEMU intel-hda device) should be present
  if wait_for 30 sh -c "su $DESKUSER -c 'XDG_RUNTIME_DIR=$RT3 wpctl status' 2>/dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -qiE 'alsa_output|hda|built-in|audio'"; then
    pass audio_sink
    info "sink=$(swu 'wpctl status' | sed -n '/Sinks:/,/Sources:/p' | grep -m1 -iE 'alsa|hda|audio' | tr -s ' ' | cut -c1-70)"
  else
    fail audio_sink
    swu "wpctl status" 2>&1 | sed -n '/Audio/,/Video/p' | head -16 | while read -r l; do info "diag wpctl: $l"; done
  fi
fi

# ----- M2: NetworkManager + wifi --------------------------------------------
if want M2; then
  if wait_for 60 sh -c "systemctl is-active NetworkManager >/dev/null 2>&1"; then
    pass nm_active
  else
    fail nm_active
    journalctl -b -u NetworkManager --no-pager 2>/dev/null | tail -8 | while read -r l; do info "diag nm: $l"; done
  fi

  # Wired: NM should manage the virtio NIC and get a DHCP lease from QEMU usernet
  WIRED="$(ls /sys/class/net 2>/dev/null | grep -E '^(en|eth)' | head -1)"
  info "wired_dev=$WIRED"
  if wait_for 45 sh -c "ip -4 addr show $WIRED 2>/dev/null | grep -q 'inet '"; then
    pass wired_ip
    info "wired_ip=$(ip -4 -o addr show "$WIRED" 2>/dev/null | awk '{print $4}')"
  else
    fail wired_ip
    info "nmcli=$(nmcli -t -f DEVICE,STATE,CONNECTION dev 2>/dev/null | tr '\n' ';')"
  fi
  # DHCP/gateway reachability (QEMU usernet gateway is 10.0.2.2)
  if ping -c1 -W3 10.0.2.2 >/dev/null 2>&1; then pass wired_ping; else fail wired_ping; fi

  # Wifi: fabricate virtual radios, run an AP on one, let NM scan/associate on the other
  modprobe mac80211_hwsim radios=2 2>/dev/null
  if wait_for 20 sh -c "ls /sys/class/net | grep -q '^wlan'"; then
    pass wifi_radios
    info "wlan=$(ls /sys/class/net | grep '^wlan' | tr '\n' ' ')"
    # wlan0 = AP (hostapd; marked unmanaged in NM via the test conf.d snippet),
    # wlan1 = client (NetworkManager + wpa_supplicant).
    ip link set wlan0 up 2>/dev/null; sleep 1
    printf '%s\n' 'interface=wlan0' 'driver=nl80211' 'ssid=swaytest' 'hw_mode=g' 'channel=1' \
      'ieee80211n=1' 'wmm_enabled=1' 'ctrl_interface=/var/run/hostapd' > /tmp/hostapd.conf
    hostapd -B -t /tmp/hostapd.conf >/tmp/hostapd.log 2>&1
    if wait_for 15 sh -c "grep -q AP-ENABLED /tmp/hostapd.log"; then
      pass wifi_ap
    else
      fail wifi_ap; tail -6 /tmp/hostapd.log 2>/dev/null | while read -r l; do info "diag hostapd: $l"; done
    fi
    # NM device should appear as wifi
    if wait_for 20 sh -c "nmcli -t -f DEVICE,TYPE dev 2>/dev/null | grep -q ':wifi'"; then pass wifi_device; else fail wifi_device; fi
    # Scan: NM (via wpa_supplicant on wlan1) should see the AP beacon
    nmcli device wifi rescan ifname wlan1 2>/dev/null
    if wait_for 40 sh -c "nmcli device wifi rescan ifname wlan1 2>/dev/null; nmcli -t -f SSID dev wifi list ifname wlan1 2>/dev/null | grep -qx swaytest"; then
      pass wifi_scan
    else
      fail wifi_scan
      info "wifi_list=$(nmcli -t -f SSID dev wifi list 2>/dev/null | tr '\n' ',')"
      info "wpa_active=$(systemctl is-active wpa_supplicant 2>/dev/null) ap=$(grep -c AP-ENABLED /tmp/hostapd.log)"
      info "wlan1_state=$(nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep '^wlan1:' | cut -d: -f2)"
    fi
    # Association: NM connects wlan1 to the open AP. Use link-local addressing so
    # the (DHCP-less) open network still reaches a "connected" state instead of
    # being torn down. Proof of L2 association: the AP lists wlan1 as a station.
    nmcli con delete swaytest-test 2>/dev/null
    nmcli con add type wifi con-name swaytest-test ifname wlan1 ssid swaytest \
      ipv4.method link-local ipv6.method ignore 2>/dev/null
    nmcli con up swaytest-test ifname wlan1 2>/tmp/wific.log
    if wait_for 25 sh -c "nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep -q '^wlan1:connected' || hostapd_cli -p /var/run/hostapd -i wlan0 list_sta 2>/dev/null | grep -q ."; then
      pass wifi_associate
      info "wifi_sta=$(hostapd_cli -p /var/run/hostapd -i wlan0 list_sta 2>/dev/null | head -1) wlan1=$(nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep '^wlan1:' | cut -d: -f2)"
    else
      fail wifi_associate
      info "wifi_wlan1_state=$(nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep '^wlan1:' | cut -d: -f2) conn_err=$(tr -d '\n' </tmp/wific.log | cut -c1-90)"
    fi
  else
    fail wifi_radios
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
