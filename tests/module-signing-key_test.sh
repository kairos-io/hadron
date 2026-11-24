#!/bin/sh
# ok/not_ok never fail, so A && ok || not_ok is safe here; the printf builds
# octal escapes for the binary signature length on purpose.
# shellcheck disable=SC2015,SC2059
# Tests for files/kernel/module-signing/module-signing-key.sh and
# .github/scripts/check-module-signer.sh, and for how the Dockerfile, the
# kernel configs and the workflows use them.
#
# Needs openssl, modinfo (kmod with zstd support), zstd, cc and python3 with
# PyYAML. `make test-module-signing` runs it.

set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
script="$repo/files/kernel/module-signing/module-signing-key.sh"
checker="$repo/.github/scripts/check-module-signer.sh"
ci_key="$repo/files/kernel/module-signing/ci-signing-key.pem"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "ok - $1"; }
not_ok() { fail=$((fail + 1)); echo "not ok - $1"; }

# expect_ok NAME CMD...: CMD must succeed.
expect_ok() {
	name=$1; shift
	if "$@" > "$work/out" 2> "$work/err"; then ok "$name"; else not_ok "$name"; cat "$work/err"; fi
}
# expect_fail NAME PATTERN CMD...: CMD must fail and say PATTERN on stderr.
expect_fail() {
	name=$1; pattern=$2; shift 2
	if "$@" > "$work/out" 2> "$work/err"; then
		not_ok "$name (it succeeded)"
	elif grep -q -- "$pattern" "$work/err"; then
		ok "$name"
	else
		not_ok "$name (no \"$pattern\" in the error)"; cat "$work/err"
	fi
}

newkey() { # newkey OUT CN
	cat > "$work/genkey" <<EOF
[ req ]
default_bits = 2048
distinguished_name = dn
prompt = no
x509_extensions = ext
[ dn ]
CN = $2
[ ext ]
basicConstraints=critical,CA:FALSE
keyUsage=digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF
	openssl req -new -nodes -utf8 -sha512 -days 3650 -batch -x509 -config "$work/genkey" \
		-outform PEM -out "$1" -keyout "$1" 2>/dev/null
}

ci_fpr=$(sh "$script" fingerprint "$ci_key")
newkey "$work/release.pem" "test release key"
release_fpr=$(sh "$script" fingerprint "$work/release.pem")
newkey "$work/other.pem" "test other key"

# ---- The CI key, the Dockerfile default and the kernel configs.

dockerfile_fpr=$(sed -n 's/^ARG MODULE_SIGNING_CERT_FPR=//p' "$repo/Dockerfile")
if [ "$dockerfile_fpr" = "$ci_fpr" ]; then
	ok "the Dockerfile's default MODULE_SIGNING_CERT_FPR is the CI key's fingerprint"
else
	not_ok "the Dockerfile's default MODULE_SIGNING_CERT_FPR ($dockerfile_fpr) is not the CI key's ($ci_fpr)"
fi
expect_ok "the CI key is a key and its certificate" sh "$script" check "$ci_key"
ext=$(openssl x509 -in "$ci_key" -noout -ext basicConstraints,keyUsage,subjectKeyIdentifier 2>/dev/null)
case "$ext" in
*CA:FALSE*"Digital Signature"*"Subject Key Identifier"*) ok "the CI certificate has the extensions kbuild's x509.genkey gives" ;;
*) not_ok "the CI certificate extensions: $ext" ;;
esac
openssl x509 -in "$ci_key" -noout -text | grep -q 'Public-Key: (4096 bit)' &&
	ok "the CI key is RSA 4096" || not_ok "the CI key is not RSA 4096"

for cfg in "$repo"/files/kernel/*.config; do
	grep -q '^CONFIG_MODULE_SIG=y' "$cfg" || continue
	if grep -qx 'CONFIG_MODULE_SIG_KEY="certs/hadron_signing_key.pem"' "$cfg"; then
		ok "$(basename "$cfg") signs with certs/hadron_signing_key.pem"
	else
		not_ok "$(basename "$cfg") does not point CONFIG_MODULE_SIG_KEY at certs/hadron_signing_key.pem"
	fi
done

# Each kernel step that runs make on the tree gets the secret and removes the key.
for word in 'install' 'remove'; do
	n=$(grep -c "sh /sources/module-signing/module-signing-key.sh ${word}" "$repo/Dockerfile")
	[ "$n" -eq 3 ] && ok "the Dockerfile runs '${word}' in the three kernel make steps" ||
		not_ok "the Dockerfile runs '${word}' $n times, not 3"
done
n=$(grep -c 'RUN --mount=type=secret,id=module-signing-key' "$repo/Dockerfile")
[ "$n" -eq 3 ] && ok "three kernel steps mount the module-signing-key secret" ||
	not_ok "$n steps mount the module-signing-key secret, not 3"

# ---- select, as the workflows run it.

expect_ok "select without a key uses the CI key" sh "$script" select "$work/sel"
grep -qx "fingerprint=$ci_fpr" "$work/out" && grep -qx "source=ci" "$work/out" && cmp -s "$work/sel" "$ci_key" &&
	ok "select without a key prints the CI fingerprint and copies the CI key" ||
	not_ok "select without a key: $(cat "$work/out")"

expect_fail "select fails without a key when one is required" "MODULE_SIGNING_KEY is not set" \
	env MODULE_SIGNING_KEY_REQUIRED=true sh "$script" select "$work/sel"
expect_fail "select fails when the required key is the CI key" "holds the public CI key" \
	env MODULE_SIGNING_KEY_REQUIRED=true MODULE_SIGNING_KEY="$(cat "$ci_key")" sh "$script" select "$work/sel"

expect_ok "select takes the release key" \
	env MODULE_SIGNING_KEY_REQUIRED=true MODULE_SIGNING_KEY="$(cat "$work/release.pem")" sh "$script" select "$work/sel"
grep -qx "fingerprint=$release_fpr" "$work/out" && grep -qx "source=release" "$work/out" &&
	ok "select prints the release fingerprint" || not_ok "select with the release key: $(cat "$work/out")"
perm=$(stat -c %a "$work/sel" 2>/dev/null || stat -f %Lp "$work/sel")
[ "$perm" = 600 ] && ok "select writes the key readable by the owner only" || not_ok "select wrote the key with mode $perm"

openssl x509 -in "$work/release.pem" > "$work/cert-only.pem"
expect_fail "select rejects a certificate without its key" "no private key" \
	env MODULE_SIGNING_KEY="$(cat "$work/cert-only.pem")" sh "$script" select "$work/sel"
openssl pkey -in "$work/release.pem" > "$work/key-only.pem"
expect_fail "select rejects a key without its certificate" "no certificate" \
	env MODULE_SIGNING_KEY="$(cat "$work/key-only.pem")" sh "$script" select "$work/sel"
{ openssl pkey -in "$work/other.pem"; openssl x509 -in "$work/release.pem"; } > "$work/mixed.pem"
expect_fail "select rejects a key that does not belong to the certificate" "does not belong" \
	env MODULE_SIGNING_KEY="$(cat "$work/mixed.pem")" sh "$script" select "$work/sel"
{ openssl pkey -in "$work/release.pem" -aes256 -passout pass:x; openssl x509 -in "$work/release.pem"; } > "$work/enc.pem"
expect_fail "select rejects an encrypted key" "encrypted" \
	env MODULE_SIGNING_KEY="$(cat "$work/enc.pem")" sh "$script" select "$work/sel"

# ---- install and remove, as the kernel build stage runs them.

stage=$work/stage
mkdir -p "$stage/module-signing" "$stage/kernel/certs"
cp "$script" "$ci_key" "$stage/module-signing/"
: > "$stage/kernel/Makefile"
printf 'CONFIG_MODULE_SIG=y\nCONFIG_MODULE_SIG_KEY="certs/hadron_signing_key.pem"\n' > "$stage/kernel/.config"
inst() { (cd "$stage/kernel" && MODULE_SIGNING_SECRET="$stage/secret" sh "$stage/module-signing/module-signing-key.sh" "$@"); }

echo "$ci_fpr" > "$stage/module-signing/fingerprint"
rm -f "$stage/secret"
expect_ok "install without a secret installs the CI key" inst install
cmp -s "$stage/kernel/certs/hadron_signing_key.pem" "$ci_key" && ok "install wrote the CI key where the config points" ||
	not_ok "install did not write the CI key"
expect_ok "remove deletes the key" inst remove
[ ! -e "$stage/kernel/certs/hadron_signing_key.pem" ] && ok "the key is gone after remove" || not_ok "remove left the key"

: > "$stage/secret"
expect_ok "install treats an empty secret as no secret" inst install
inst remove

cp "$work/release.pem" "$stage/secret"
expect_fail "install refuses a secret that does not match the fingerprint" "MODULE_SIGNING_CERT_FPR is $ci_fpr" inst install
[ ! -e "$stage/kernel/certs/hadron_signing_key.pem" ] && ok "a refused key is not installed" || not_ok "a refused key was installed"

echo "$release_fpr" > "$stage/module-signing/fingerprint"
expect_ok "install takes a secret that matches the fingerprint" inst install
cmp -s "$stage/kernel/certs/hadron_signing_key.pem" "$work/release.pem" && ok "install wrote the secret" ||
	not_ok "install did not write the secret"
inst remove

rm -f "$stage/secret"
expect_fail "install refuses the CI key for a release fingerprint" "the ci key has certificate sha256 $ci_fpr" inst install

echo unsigned > "$stage/module-signing/fingerprint"
expect_ok "install does nothing for a config that does not sign" inst install
[ ! -e "$stage/kernel/certs/hadron_signing_key.pem" ] && ok "nothing installed for an unsigned config" ||
	not_ok "a key was installed for an unsigned config"
expect_ok "remove does nothing for a config that does not sign" inst remove

echo "$ci_fpr" > "$stage/module-signing/fingerprint"
printf 'CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"\n' > "$stage/kernel/.config"
expect_fail "install refuses the path kbuild overwrites" "throwaway key" inst install

# ---- check-module-signer.sh on a made-up image root.

# A module: an ELF object with a .modinfo section, signed the way scripts/sign-file
# signs it (detached PKCS#7, no certificates, issuer and serial), with the
# module_signature trailer kmod reads.
cat > "$work/mod.c" <<'EOF'
__attribute__((section(".modinfo"), used)) static const char license[] = "license=GPL";
EOF
cc -c -o "$work/mod.o" "$work/mod.c"
sign_module() { # sign_module KEY OUT
	openssl cms -sign -binary -nocerts -noattr -nosmimecap -md sha512 -outform DER \
		-signer "$1" -inkey "$1" -in "$work/mod.o" -out "$work/sig.der"
	len=$(wc -c < "$work/sig.der")
	{
		cat "$work/mod.o" "$work/sig.der"
		# algo, hash, id_type=2 (PKCS#7), signer_len, key_id_len, pad[3], then sig_len big endian.
		printf '\000\000\002\000\000\000\000\000'
		printf "$(printf '\\%03o\\%03o\\%03o\\%03o' $((len >> 24 & 255)) $((len >> 16 & 255)) $((len >> 8 & 255)) $((len & 255)))"
		printf '~Module signature appended~\n'
	} > "$2"
}
# A vmlinuz: some setup bytes, then a zstd payload that holds the certificate,
# then trailing bytes, like an x86 bzImage.
make_kernel() { # make_kernel CERT_KEY OUT
	{ head -c 4096 /dev/urandom; openssl x509 -in "$1" -outform DER; head -c 4096 /dev/urandom; } > "$work/vmlinux"
	{ printf 'MZ-setup-'; head -c 1000 /dev/zero; zstd -q -c "$work/vmlinux"; printf 'trailer'; } > "$2"
}
make_root() { # make_root DIR KERNEL_KEY MODULE_KEY [SECOND_MODULE_KEY]
	mkdir -p "$1/boot" "$1/lib/modules/1.0/kernel"
	make_kernel "$2" "$1/boot/vmlinuz-1.0"
	sign_module "$3" "$1/lib/modules/1.0/kernel/a.ko"
	sign_module "${4:-$3}" "$work/b.ko"
	zstd -q -c "$work/b.ko" > "$1/lib/modules/1.0/kernel/b.ko.zst"
}

if [ "$(modinfo -F sig_key "$(sign_module "$work/release.pem" "$work/probe.ko"; echo "$work/probe.ko")" 2>/dev/null)" = "" ]; then
	not_ok "modinfo reads the signature of a test module"
else
	ok "modinfo reads the signature of a test module"
fi

make_root "$work/good" "$work/release.pem" "$work/release.pem"
expect_ok "check passes a kernel and modules of one key" sh "$checker" "$work/good" "$work/release.pem" "$ci_key"
grep -q "2 of 2" "$work/out" && ok "check counted both modules, the compressed one too" || not_ok "check counts: $(cat "$work/out")"

make_root "$work/mixed" "$work/release.pem" "$work/release.pem" "$work/other.pem"
expect_fail "check fails a module signed with another key" "signed with another certificate" \
	sh "$checker" "$work/mixed" "$work/release.pem"

make_root "$work/wrongkernel" "$work/other.pem" "$work/release.pem"
expect_fail "check fails a kernel that does not trust the key" "does not carry the certificate" \
	sh "$checker" "$work/wrongkernel" "$work/release.pem"

make_root "$work/ci" "$ci_key" "$ci_key"
expect_fail "check fails a release build signed with the CI key" "forbidden certificate" \
	sh "$checker" "$work/ci" "$work/release.pem" "$ci_key"
expect_ok "check passes a pull request build signed with the CI key" sh "$checker" "$work/ci" "$ci_key"

make_root "$work/unsigned" "$work/release.pem" "$work/release.pem"
cp "$work/mod.o" "$work/unsigned/lib/modules/1.0/kernel/a.ko"
expect_fail "check fails an unsigned module" "not signed" sh "$checker" "$work/unsigned" "$work/release.pem"

# ---- The workflows: every main and release build that reaches the kernel gets
# the key, and the jobs that need the release key run in its environment.

python3 - "$repo" <<'EOF' > "$work/wf" 2>&1 && ok "workflows pass the key to every kernel build" || { not_ok "workflows pass the key to every kernel build"; cat "$work/wf"; }
import sys, yaml
repo = sys.argv[1]
kernel_targets = {"kernel", "kernel-artifacts", "toolchain", "default", "image-test", "debug"}
errors = []
wf = yaml.safe_load(open(f"{repo}/.github/workflows/build-multiarch-images.yml"))
for name, job in wf["jobs"].items():
    steps = job.get("steps") or []
    builds = [s for s in steps if str(s.get("uses", "")).startswith("docker/build-push-action")
              and s.get("with", {}).get("target") in kernel_targets]
    if not builds:
        continue
    if job.get("environment") != "module-signing":
        errors.append(f"{name}: no environment: module-signing")
    sel = [s for s in steps if s.get("uses") == "./.github/actions/module-signing-key"]
    if len(sel) != 1 or sel[0].get("id") != "modsign":
        errors.append(f"{name}: no module-signing-key step with id modsign")
    elif "secrets.MODULE_SIGNING_KEY" not in str(sel[0].get("with", {}).get("key")):
        errors.append(f"{name}: the key does not come from secrets.MODULE_SIGNING_KEY")
    for s in builds:
        w = s["with"]
        if "module-signing-key=${{ steps.modsign.outputs.file }}" not in str(w.get("secret-files")):
            errors.append(f"{name}/{s.get('name')}: no module-signing-key secret")
        if "MODULE_SIGNING_CERT_FPR=${{ steps.modsign.outputs.fingerprint }}" not in str(w.get("build-args")):
            errors.append(f"{name}/{s.get('name')}: no MODULE_SIGNING_CERT_FPR build arg")
    if any(s["with"].get("target") == "default" for s in builds) and "riscv64" not in name:
        if not any(s.get("uses") == "./.github/actions/check-module-signer" for s in steps):
            errors.append(f"{name}: no check-module-signer step")
for wfname in ("PR_multiarch.yml", "PR_riscv64.yml"):
    wf = yaml.safe_load(open(f"{repo}/.github/workflows/{wfname}"))
    for name, job in wf["jobs"].items():
        if "module-signing" in str(job.get("environment", "")) or "MODULE_SIGNING_KEY" in str(job):
            errors.append(f"{wfname}/{name}: a pull request must not read the release key")
print("\n".join(errors))
sys.exit(1 if errors else 0)
EOF

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
