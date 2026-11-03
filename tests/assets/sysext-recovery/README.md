`work.sysext.raw` here is the recovery spec's fixture. It is
`../sysext/work.sysext.raw` with the verity signature partition removed, so it
carries a root partition and its verity hash and nothing else.

The recovery spec boots the BIOS image through GRUB. On a GRUB boot immucore
validates extensions against `root=verity+absent:usr=verity+absent`, and it
also skips any image that carries a verity signature, because GRUB enrols no
certificate to check it with (kairos-io/kairos#5004). The signed image in
`../sysext/` is therefore never linked into `/run/extensions` on that boot.
This one passes the verity policy and has no signature to skip it for.

It is kept out of `../sysext/` because that whole folder is the UKI test ISO's
overlay, and the UKI boot only accepts signed images.

## Rebuild

Copy `../sysext/work.sysext.raw`, drop its third partition
(`root-x86-64-verity-sig`) and zero the sectors it used:

    cp ../sysext/work.sysext.raw .
    sfdisk --delete work.sysext.raw 3
    dd if=/dev/zero of=work.sysext.raw bs=512 seek=2064 count=32 conv=notrunc

Check it with a systemd 254 or newer:

    systemd-dissect --validate --image-policy="root=verity+absent:usr=verity+absent" work.sysext.raw   # OK
    systemd-dissect --validate --image-policy="root=signed+absent:usr=signed+absent" work.sysext.raw   # does not match
