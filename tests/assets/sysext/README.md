This folder contains 2 sysextensions. The whole folder is handed to
auroraboot as `--overlay-iso` by `.github/workflows/PR_multiarch.yml`, so it
ends up on the Trusted Boot test ISO.

`work.sysext.raw` contains a script called `hello.sh` that prints
`Hello world`. It is verity + signed with the `db.key` and `db.pem` test keys
under `tests/assets/keys`, which are the same keys the UKI ISO enrols into the
Secure Boot db, so the kernel trusts the signature and systemd-sysext merges
the extension.

`hello-broke.sysext.raw` contains the same script but is NOT signed and has no
verity. The image policy the kairos drop-in installs rejects it. It is there to
assert that a broken extension does not take the valid one down with it.

Both extensions carry a `usr/lib/extension-release.d/extension-release.NAME`
with `ID=_any`, so systemd-sysext identifies them regardless of the host
os-release.

## Where the payload sits

`work.sysext.raw` ships `hello.sh` at `usr/bin/`. It used to ship it at
`usr/local/bin/`, which stopped working when kairos-io/kairos#5115 removed
every `/usr/local` path from `SYSTEMD_SYSEXT_HIERARCHIES` in
`kairos-init/pkg/bundled/cloudconfigs/99_sysext.yaml`: `/usr/local` is where
`COS_PERSISTENT` is mounted, and a successful merge makes every hierarchy it
covers read-only, which cost the persistent partition its writable half.
`/usr/bin` is where a sysext-delivered binary belongs anyway.

`hello-broke.sysext.raw` is never merged, so where its payload sits does not
matter and it is left untouched.

## The test

1. Copy the sysextensions to the overlay folder on test preparation
2. Build the uki iso with the overlay files on it and sign it with the same
   test keys
3. Boot the uki iso and check if the sysextensions are loaded correctly
4. Check that `hello-broke.sysext.raw` never reaches `/run/extensions`
5. Check that `work.sysext.raw` was moved onto `/run/extensions` and merged at
   `/usr/bin`
6. Check that `hello.sh` runs, which it only can if the merge went up
7. Check if the sysext service is running with the override from kairos with
   the policy

## Rebuilding

`work.sysext.raw` is a systemd-repart DDI (erofs data + verity hash + verity
signature partition). `systemd-repart -S` needs systemd's stock
`sysext.repart.d` installed on the build host and fails with
`DDI type 'sysext' is not defined` without it, so pass an explicit definitions
directory instead.

Prepare a `SOURCE_DIR` with `usr/bin/hello.sh` (mode 0755) and
`usr/lib/extension-release.d/extension-release.work` (carrying `ID=_any`), then
write `defs.d`:

```bash
mkdir -p defs.d
cat > defs.d/10-root.conf <<'EOF'
[Partition]
Type=root
Format=erofs
CopyFiles=/usr/
CopyFiles=/opt/
Verity=data
VerityMatchKey=root
Minimize=best
EOF
cat > defs.d/20-root-verity.conf <<'EOF'
[Partition]
Type=root-verity
Verity=hash
VerityMatchKey=root
Minimize=best
EOF
cat > defs.d/30-root-verity-sig.conf <<'EOF'
[Partition]
Type=root-verity-sig
Verity=signature
VerityMatchKey=root
EOF
```

`mkfs.erofs` (package `erofs-utils`) has to be on PATH. The seed only fixes
what repart derives from it: `mkfs.erofs` stamps a random filesystem UUID into
the data partition, so the verity root hash and the partition UUIDs repart
derives from it change on every rebuild. Expect different bytes each time.

Then, with a 0600 copy of the key (repart refuses a more permissive one):

```bash
systemd-repart --seed=00000000-0000-0000-0000-000000000000 \
    --empty=create --size=auto --offline=yes \
    --definitions=defs.d --root=SOURCE_DIR OUTPUT_FILE \
    --private-key=db.key --certificate=tests/assets/keys/db.pem
```

`hello-broke.sysext.raw` was built with
[sysext-bakery](https://github.com/flatcar/sysext-bakery), which has no support
for signing or verity, which is the point:

```bash
bake.sh SOURCE_DIR
```

The same pair of extensions lives upstream in
`kairos-io/kairos` under `tests/assets/sysext-uki/` and `tests/assets/sysext-grub/`.
Keep this one in step with the UKI half.
