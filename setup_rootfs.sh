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
ln -sfv run/lock var/lock # var/lock -> run/lock

ln -svf proc/mounts etc/mtab
cat > etc/passwd << "EOF"
root::0:0:root:/root:/bin/ash
EOF

cat > etc/group << "EOF"
root:x:0:
bin:x:1:
sys:x:2:
kmem:x:3:
tty:x:4:
tape:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
EOF

touch var/log/lastlog
chmod -v 664 var/log/lastlog

cat > etc/fstab << "EOF"
# Begin /etc/fstab

# file system  mount-point  type     options                     dump  fsck
proc           /proc        proc     nosuid,noexec,nodev         0     0
sysfs          /sys         sysfs    nosuid,noexec,nodev         0     0
devpts         /dev/pts     devpts   gid=5,mode=620              0     0
tmpfs          /run         tmpfs    defaults                    0     0
devtmpfs       /dev         devtmpfs mode=0755,nosuid            0     0
tmpfs          /dev/shm     tmpfs    nosuid,nodev                0     0

# End /etc/fstab
EOF

cat > etc/profile << "EOF"
export PATH=/bin:/usr/bin

if [ `id -u` -eq 0 ] ; then
        PATH=/bin:/sbin:/usr/bin:/usr/sbin
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
EOF

cat > etc/issue << "EOF"
UKairos Linux (\d)
Kernel \r on an \m

EOF

cat > etc/inittab << "EOF"
::sysinit:/etc/rc.d/startup

tty1::respawn:/sbin/getty 38400 tty1
tty2::respawn:/sbin/getty 38400 tty2
tty3::respawn:/sbin/getty 38400 tty3
tty4::respawn:/sbin/getty 38400 tty4
tty5::respawn:/sbin/getty 38400 tty5
tty6::respawn:/sbin/getty 38400 tty6

::shutdown:/etc/rc.d/shutdown
::ctrlaltdel:/sbin/reboot
EOF

cat > etc/mdev.conf << "EOF"
# Devices:
# Syntax: %s %d:%d %s
# devices user:group mode

# null does already exist; therefore ownership has to
# be changed with command
null    root:root 0666  @chmod 666 $MDEV
zero    root:root 0666
grsec   root:root 0660
full    root:root 0666

random  root:root 0666
urandom root:root 0444
hwrandom root:root 0660

# console does already exist; therefore ownership has to
# be changed with command
console root:tty 0600 @mkdir -pm 755 fd && cd fd && for x in 0 1 2 3 ; do ln -sf /proc/self/fd/$x $x; done

kmem    root:root 0640
mem     root:root 0640
port    root:root 0640
ptmx    root:tty 0666

# ram.*
ram([0-9]*)     root:disk 0660 >rd/%1
loop([0-9]+)    root:disk 0660 >loop/%1
sd[a-z].*       root:disk 0660 */lib/mdev/usbdisk_link
hd[a-z][0-9]*   root:disk 0660 */lib/mdev/ide_links

tty             root:tty 0666
tty[0-9]        root:root 0600
tty[0-9][0-9]   root:tty 0660
ttyO[0-9]*      root:tty 0660
pty.*           root:tty 0660
vcs[0-9]*       root:tty 0660
vcsa[0-9]*      root:tty 0660

ttyLTM[0-9]     root:dialout 0660 @ln -sf $MDEV modem
ttySHSF[0-9]    root:dialout 0660 @ln -sf $MDEV modem
slamr           root:dialout 0660 @ln -sf $MDEV slamr0
slusb           root:dialout 0660 @ln -sf $MDEV slusb0
fuse            root:root  0666

# misc stuff
agpgart         root:root 0660  >misc/
psaux           root:root 0660  >misc/
rtc             root:root 0664  >misc/

# input stuff
event[0-9]+     root:root 0640 =input/
ts[0-9]         root:root 0600 =input/

# v4l stuff
vbi[0-9]        root:video 0660 >v4l/
video[0-9]      root:video 0660 >v4l/

# load drivers for usb devices
usbdev[0-9].[0-9]       root:root 0660 */lib/mdev/usbdev
usbdev[0-9].[0-9]_.*    root:root 0660
EOF

ARCH=$(uname -m)

cat > etc/os-release << EOF
NAME="UKairos Linux"
PRETTY_NAME="UKairos Linux"
ID=ukairos
BUILD_ID=rolling
KAIROS_FLAVOR="ukairos"
KAIROS_ARCH="${ARCH}"
EOF