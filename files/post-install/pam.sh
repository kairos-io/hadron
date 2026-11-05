#!/bin/bash
# Post-install steps for linux-pam.

# pam_unix runs unix_chkpwd to check a password when the caller cannot read
# /etc/shadow. A screen locker runs as the user, so without the setuid bit
# every unlock fails with "Authentication service cannot retrieve
# authentication info". The meson install does not set it.
#
# Fedora ships the helper as 4755 root:root, the same as here, and Arch as
# 6755 root:root. Debian uses 2755 root:shadow instead, which needs
# /etc/shadow to be group readable by a shadow group. Hadron has no shadow
# group, so it follows Fedora.
chown root:root /usr/sbin/unix_chkpwd
chmod 4755 /usr/sbin/unix_chkpwd
