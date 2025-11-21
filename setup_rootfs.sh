#!/bin/bash

if [ ! -e ${SYSROOT} ]; then
    mkdir -pv ${SYSROOT}
fi

cd ${SYSROOT}

mkdir -pv {boot,home,mnt,opt,srv,tmp} \
    {etc,var} \
    etc/{opt,sysconfig} \
    usr/{bin,lib} \
    usr/lib/firmware \
    usr/{,local/}{include,src} \
    usr/local/{bin,lib} \
    usr/{,local/}share/{color,dict,doc,info,locale,man} \
    usr/{,local/}share/{misc,terminfo,zoneinfo} \
    usr/{,local/}share/man/man{1..8} \
    var/{cache,local,log,mail,opt,spool} \
    var/lib/{color,misc,locate} \
    {dev,proc,sys,run}

install -dv -m 0750 root
install -dv -m 1777 var/tmp
touch etc/hostname

ln -sfv usr/bin sbin  # sbin -> usr/bin
ln -sfv usr/bin bin   # bin -> usr/bin
ln -sfv usr/lib lib   # lib -> usr/lib
ln -sfv usr/lib lib64 # lib64 -> usr/lib
ln -sfv bin usr/sbin  # usr/sbin -> usr/bin
ln -sfv lib usr/lib64 # usr/lib64 -> usr/lib
ln -sfv ../run var/run # var/run -> ../run important to be relative
ln -sfv ../run/lock var/lock # var/lock -> run/lock


ln -svf proc/mounts etc/mtab

cat > etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/fa
dbus:x:81:81:System Message Bus:/:/usr/bin/nologin
systemd-coredump:x:980:980:systemd Core Dumper:/:/usr/bin/nologin
systemd-network:x:979:979:systemd Network Management:/:/usr/bin/nologin
systemd-oom:x:978:978:systemd Userspace OOM Killer:/:/usr/bin/nologin
systemd-journal-remote:x:977:977:systemd Journal Remote:/:/usr/bin/nologin
systemd-resolve:x:976:976:systemd Resolver:/:/usr/bin/nologin
systemd-timesync:x:975:975:systemd Time Synchronization:/:/usr/bin/nologin
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

cat > etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

touch etc/shadow

touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664  /var/log/lastlog
chmod -v 600  /var/log/btmp

cat > etc/profile << "EOF"
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin/:/usr/local/sbin/

if [ `id -u` -eq 0 ] ; then
        unset HISTFILE
fi

# Set up some environment variables.
export USER=`id -un`
export LOGNAME=$USER
export HOSTNAME=`/bin/hostname`
export HISTSIZE=1000
export HISTFILESIZE=1000
export PAGER='/bin/more '
export EDITOR='/bin/vi'
# load other profiles under /etc/profile.d
if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh; do
    if [ -r $i ]; then
      . $i
    fi
  done
  unset i
fi
EOF

cat > etc/issue << "EOF"
Hadron Linux (\d)
Kernel \r on an \m

EOF

cat > etc/os-release << EOF
NAME="Hadron Linux"
PRETTY_NAME="Hadron Linux"
ID=hadron
BUILD_ID=rolling
EOF

cat > etc/hosts << "EOF"
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
EOF