#!/bin/sh
# module-signing-key.sh: pick, check and install the kernel module signing key.
#
# The kernel embeds the certificate of this key in vmlinuz and signs every
# module with the private half at modules_install. Both have to come from the
# same key, see README.md in this directory.
#
#   fingerprint FILE  Print the sha256 of the certificate in FILE (DER form),
#                     lower case hex, no colons. This is what the build arg
#                     MODULE_SIGNING_CERT_FPR carries.
#   check FILE        Fail unless FILE holds an unencrypted private key and the
#                     certificate for it. Print the fingerprint.
#   select OUT        For CI. Write the key to sign with to OUT and print
#                     "fingerprint=..." and "source=ci|release", ready for
#                     $GITHUB_OUTPUT. The key is the MODULE_SIGNING_KEY
#                     environment variable when it is set, else the public CI
#                     key next to this script. With
#                     MODULE_SIGNING_KEY_REQUIRED=true a missing key, or the
#                     CI key passed as MODULE_SIGNING_KEY, is an error.
#   install           For the kernel build stage, run in the kernel tree. Copy
#                     the key to the path CONFIG_MODULE_SIG_KEY names in
#                     .config. The key is the BuildKit secret when it was
#                     passed, else the CI key, and its fingerprint has to match
#                     the "fingerprint" file next to this script. That file
#                     says "unsigned" when the config does not sign modules,
#                     and then nothing is installed.
#   remove            For the kernel build stage. Delete what install wrote,
#                     so the private key never ends up in an image layer.
#
# Environment for install and remove, to make them testable:
#   MODULE_SIGNING_SECRET  the secret file (/run/secrets/module-signing-key)
#   KCONFIG                the kernel config (.config)

set -eu

here=$(cd "$(dirname "$0")" && pwd)
ci_key="${here}/ci-signing-key.pem"

die() {
	echo "module-signing-key: $*" >&2
	exit 1
}

fingerprint() {
	[ -s "$1" ] || die "$1: no such file or empty"
	fpr=$(openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null) ||
		die "$1: no X.509 certificate in it"
	printf '%s\n' "${fpr#*=}" | tr -d ':' | tr 'A-F' 'a-f'
}

check() {
	[ -s "$1" ] || die "$1: no such file or empty"
	grep -q -- '-----BEGIN CERTIFICATE-----' "$1" ||
		die "$1: no certificate in it, kbuild needs the key and the certificate in one PEM file"
	grep -q -- '-----BEGIN ENCRYPTED PRIVATE KEY-----' "$1" &&
		die "$1: the private key is encrypted, the kernel build cannot read it"
	grep -Eq -- '-----BEGIN (RSA |EC )?PRIVATE KEY-----' "$1" ||
		die "$1: no private key in it, kbuild needs the key and the certificate in one PEM file"
	cert_pub=$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null) ||
		die "$1: cannot read the certificate"
	key_pub=$(openssl pkey -in "$1" -pubout 2>/dev/null) ||
		die "$1: cannot read the private key"
	[ "$cert_pub" = "$key_pub" ] ||
		die "$1: the private key does not belong to the certificate"
	fingerprint "$1"
}

select_key() {
	out=$1
	required=${MODULE_SIGNING_KEY_REQUIRED:-false}
	ci_fpr=$(fingerprint "$ci_key")
	umask 077
	if [ -n "${MODULE_SIGNING_KEY:-}" ]; then
		printf '%s\n' "$MODULE_SIGNING_KEY" > "$out"
		source=release
	elif [ "$required" = true ]; then
		die "MODULE_SIGNING_KEY is not set. This build has to sign the kernel modules with the release key, not the public CI key. Set the MODULE_SIGNING_KEY secret, see files/kernel/module-signing/README.md."
	else
		cp "$ci_key" "$out"
		source=ci
	fi
	fpr=$(check "$out")
	if [ "$source" = release ] && [ "$fpr" = "$ci_fpr" ]; then
		if [ "$required" = true ]; then
			die "MODULE_SIGNING_KEY holds the public CI key. Release builds need their own key."
		fi
		source=ci
	fi
	echo "Module signing key: ${source}, certificate sha256 ${fpr}" >&2
	echo "fingerprint=${fpr}"
	echo "source=${source}"
}

# The file CONFIG_MODULE_SIG_KEY names in the kernel config.
key_path() {
	kconfig=${KCONFIG:-.config}
	[ -f "$kconfig" ] || die "${kconfig}: no kernel config"
	path=$(sed -n 's/^CONFIG_MODULE_SIG_KEY="\(.*\)"$/\1/p' "$kconfig")
	[ -n "$path" ] || die "${kconfig}: CONFIG_MODULE_SIG_KEY is not set"
	case "$path" in
	certs/signing_key.pem)
		# kbuild regenerates this one on every build, whatever is in it.
		die "${kconfig}: CONFIG_MODULE_SIG_KEY is certs/signing_key.pem, the path kbuild fills with a throwaway key. Point it at certs/hadron_signing_key.pem." ;;
	pkcs11:*)
		die "${kconfig}: a PKCS#11 CONFIG_MODULE_SIG_KEY is not supported here" ;;
	esac
	printf '%s\n' "$path"
}

install_key() {
	want=$(cat "${here}/fingerprint")
	if [ "$want" = unsigned ]; then
		echo "Module signing key: not needed, this kernel config does not sign modules" >&2
		return 0
	fi
	secret=${MODULE_SIGNING_SECRET:-/run/secrets/module-signing-key}
	if [ -s "$secret" ]; then
		src=$secret
		source=secret
	else
		src=$ci_key
		source=ci
	fi
	fpr=$(check "$src")
	if [ "$fpr" != "$want" ]; then
		die "the ${source} key has certificate sha256 ${fpr}, but MODULE_SIGNING_CERT_FPR is ${want}. Pass the fingerprint of the key you sign with, or the key that goes with the fingerprint."
	fi
	dest=$(key_path)
	mkdir -p "$(dirname "$dest")"
	(umask 077 && cp "$src" "$dest")
	# An old mtime, so make never takes the key for newer than the
	# certificate it already extracted from it and rebuilds vmlinux objects
	# in a later step.
	touch -r Makefile "$dest" 2>/dev/null || true
	echo "Module signing key: ${source}, certificate sha256 ${fpr}" >&2
}

remove_key() {
	want=$(cat "${here}/fingerprint")
	[ "$want" = unsigned ] && return 0
	rm -f "$(key_path)"
}

[ $# -ge 1 ] || die "usage: $0 fingerprint FILE | check FILE | select OUT | install | remove"
cmd=$1
shift
case "$cmd" in
fingerprint) [ $# -eq 1 ] || die "usage: $0 fingerprint FILE"; fingerprint "$1" ;;
check) [ $# -eq 1 ] || die "usage: $0 check FILE"; check "$1" ;;
select) [ $# -eq 1 ] || die "usage: $0 select OUT"; select_key "$1" ;;
install) install_key ;;
remove) remove_key ;;
*) die "unknown command: $cmd" ;;
esac
