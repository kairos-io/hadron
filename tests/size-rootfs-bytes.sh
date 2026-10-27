#!/bin/sh
# The image size tooling must measure the same thing for :main and for a PR.
#
# image-size-report.sh compares a PR image that the workflow `docker load`ed
# from a tarball against the :main image it pulls from ghcr. Both used to be
# read with `docker image inspect .Size`, whose meaning depends on the daemon's
# image store. On the ubuntu-26.04 runners Docker uses the containerd store,
# where a pulled image reports its compressed size and a loaded one reports
# uncompressed. That turned a 120 byte python bump (kairos-io/hadron#770) into
# a reported +77MB, and it would have put a false 70MB drop in size-history.
#
# rootfs_bytes reads the flattened filesystem from `docker export` instead, so
# the store cannot change the answer. This drives it with a docker that
# exports a known rootfs and checks that only regular files are counted, each
# hardlinked file once, and that the container it creates is removed.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A rootfs with 1000 + 234 bytes of regular files, a hardlink to the larger
# one, a symlink and a directory. Only the two regular files count.
mkdir -p "$tmp/rootfs/usr/bin"
head -c 1000 /dev/zero > "$tmp/rootfs/usr/bin/big"
head -c 234 /dev/zero > "$tmp/rootfs/small"
ln "$tmp/rootfs/usr/bin/big" "$tmp/rootfs/usr/bin/big-link"
ln -s usr/bin/big "$tmp/rootfs/link"
tar -C "$tmp/rootfs" -cf "$tmp/export.tar" .

mkdir -p "$tmp/bin"
cat > "$tmp/bin/docker" <<STUB
#!/bin/sh
echo "\$*" >> "$tmp/calls"
case "\$1" in
  create) echo ctr123 ;;
  export) cat "$tmp/export.tar" ;;
  rm) ;;
  *) echo "unexpected docker \$*" >&2; exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/docker"

got=$(PATH="$tmp/bin:$PATH" bash -c '. "$1"; rootfs_bytes some/image:main' _ \
  "$repo_root/.github/scripts/size-history-lib.sh")

fail=0
if [ "$got" != 1234 ]; then
  echo "FAIL: rootfs_bytes printed '$got', want 1234"
  fail=1
fi
if ! grep -q '^create some/image:main ' "$tmp/calls"; then
  echo "FAIL: rootfs_bytes did not create a container from the image"
  fail=1
fi
if ! grep -q '^rm -f ctr123$' "$tmp/calls"; then
  echo "FAIL: rootfs_bytes left its container behind"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "PASS: rootfs_bytes counts regular files once"
exit "$fail"
