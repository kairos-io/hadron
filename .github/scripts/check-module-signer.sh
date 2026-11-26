#!/bin/sh
# check-module-signer.sh ROOTFS EXPECT [FORBID]
#
# Check that the kernel and the modules in an image root were signed with one
# key, the one in EXPECT. ROOTFS needs boot/vmlinuz-<release> and
# lib/modules/<release>. EXPECT and FORBID are PEM files with the certificate
# of a module signing key, with or without its private key.
#
#   - vmlinuz has to carry the EXPECT certificate, byte for byte, in its builtin
#     keyring. The sha256 of those bytes is the key's fingerprint. It must not
#     carry the FORBID certificate.
#   - Every module has to be signed, and signed by the EXPECT certificate:
#     `modinfo -F sig_key` is the serial number of the signing certificate
#     for the PKCS#7 signatures kbuild writes.
#
# A kernel and modules from two kernel builds that each made a throwaway key
# fail this with "Loading of module with unavailable key is rejected" at boot
# (kairos-io/hadron, pull requests 896 and 899). This finds it before the boot.
#
# Needs openssl, modinfo (kmod, with zstd and xz support for compressed
# modules), od, GNU grep (-P) and zstd, xz and gzip to unpack a compressed
# vmlinuz.

set -eu

die() {
	echo "check-module-signer: $*" >&2
	exit 1
}

[ $# -ge 2 ] && [ $# -le 3 ] || die "usage: $0 ROOTFS EXPECT [FORBID]"
rootfs=$1
expect=$2
forbid=${3:-}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

der_hex() {
	openssl x509 -in "$1" -outform DER 2>/dev/null | od -An -v -tx1 | tr -d ' \n' ||
		die "$1: no X.509 certificate in it"
}

serial() {
	s=$(openssl x509 -in "$1" -noout -serial 2>/dev/null) || die "$1: no X.509 certificate in it"
	printf '%s\n' "${s#serial=}" | tr -d ':' | tr 'a-f' 'A-F'
}

fpr() {
	f=$(openssl x509 -in "$1" -noout -fingerprint -sha256)
	printf '%s\n' "${f#*=}" | tr -d ':' | tr 'A-F' 'a-f'
}

expect_hex=$(der_hex "$expect")
expect_serial=$(serial "$expect")
expect_fpr=$(fpr "$expect")
[ -n "$expect_hex" ] || die "$expect: empty certificate"
forbid_hex=
forbid_serial=
if [ -n "$forbid" ]; then
	forbid_hex=$(der_hex "$forbid")
	forbid_serial=$(serial "$forbid")
	[ "$forbid_hex" != "$expect_hex" ] || die "the expected and the forbidden certificate are the same"
fi

# Hex dumps of the kernel image as it is (arm64 and riscv64 ship the raw
# Image) and of every compressed payload in it (an x86 bzImage carries
# vmlinux compressed). Written to $work/kernel.*.hex.
kernel_dumps() {
	img=$1
	od -An -v -tx1 "$img" | tr -d ' \n' > "$work/kernel.raw.hex"
	n=0
	for magic in '\x28\xb5\x2f\xfd:zstd' '\xfd\x37\x7a\x58\x5a\x00:xz' '\x1f\x8b\x08:gzip'; do
		pattern=${magic%%:*}
		tool=${magic#*:}
		# The offset in bytes of the first match.
		off=$(LC_ALL=C grep -obUaP "$pattern" "$img" | head -n 1 | cut -d: -f1)
		[ -n "$off" ] || continue
		n=$((n + 1))
		# The payload is followed by the rest of the bzImage, which the
		# decompressor reports as trailing garbage. What it wrote before
		# that is the whole vmlinux.
		tail -c +$((off + 1)) "$img" | "$tool" -dc 2>/dev/null > "$work/kernel.$n" || true
		od -An -v -tx1 "$work/kernel.$n" | tr -d ' \n' > "$work/kernel.$n.hex"
		rm -f "$work/kernel.$n"
	done
}

contains() {
	grep -qF -- "$2" "$1"
}

failed=0
fail() {
	echo "FAIL: $*" >&2
	failed=1
}

kernels=$(find "$rootfs/boot/" -maxdepth 1 -type f -name 'vmlinuz-*' ! -name '*.hmac' 2>/dev/null | sort)
[ -n "$kernels" ] || die "$rootfs/boot: no vmlinuz-* in it"
for k in $kernels; do
	kernel_dumps "$k"
	found=false
	for d in "$work"/kernel.*.hex; do
		if contains "$d" "$expect_hex"; then
			found=true
		fi
		if [ -n "$forbid_hex" ] && contains "$d" "$forbid_hex"; then
			fail "$(basename "$k") trusts the forbidden certificate (serial ${forbid_serial})"
		fi
	done
	if [ "$found" = true ]; then
		echo "OK: $(basename "$k") trusts the certificate with sha256 ${expect_fpr}"
	else
		fail "$(basename "$k") does not carry the certificate with sha256 ${expect_fpr} (serial ${expect_serial})"
	fi
	rm -f "$work"/kernel.*.hex
done

mods=$(find "$rootfs/lib/modules/" -type f \( -name '*.ko' -o -name '*.ko.*' \) 2>/dev/null | sort)
[ -n "$mods" ] || die "$rootfs/lib/modules: no modules in it"
total=0
good=0
for m in $mods; do
	total=$((total + 1))
	key=$(modinfo -F sig_key "$m" 2>/dev/null | tr -d ':' | tr 'a-f' 'A-F')
	if [ "$key" = "$expect_serial" ]; then
		good=$((good + 1))
		continue
	fi
	case "$key" in
	"") fail "${m#"$rootfs"/}: not signed" ;;
	"$forbid_serial") fail "${m#"$rootfs"/}: signed with the forbidden certificate (serial ${key})" ;;
	*) fail "${m#"$rootfs"/}: signed with another certificate (serial ${key})" ;;
	esac
done
echo "Modules signed with the certificate with serial ${expect_serial}: ${good} of ${total}"

if [ "$failed" -ne 0 ]; then
	die "the kernel and the modules were not signed with the expected key"
fi
