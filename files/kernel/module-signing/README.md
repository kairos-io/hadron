# Kernel module signing key

The amd64 and arm64 kernel configs set `CONFIG_MODULE_SIG=y` and
`CONFIG_MODULE_SIG_ALL=y`. The kernel build puts the certificate of the module
signing key into the kernel's builtin keyring, and `make modules_install` signs
every module with the private key. A kernel only loads a module signed by a key
it trusts. Under Secure Boot (lockdown) or with `fips=1` a module it does not
trust is not loaded at all:

```
Loading of module with unavailable key is rejected
```

The kernel used to sign with a throwaway key that kbuild made fresh on every
kernel build (`CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"`). Any image whose
vmlinuz and modules came from two different kernel builds, which the BuildKit
cache can produce, could not load a single module. Pull requests 896 and 899
failed the trusted boot tests this way. Now every build signs with a fixed key,
and `CONFIG_MODULE_SIG_KEY` points at `certs/hadron_signing_key.pem`, a path
kbuild does not overwrite.

## Which key

There are two keys.

| Key | Where | Used by |
|---|---|---|
| CI key | `ci-signing-key.pem` in this directory | pull requests, forks, local `make` builds |
| Release key | the `MODULE_SIGNING_KEY` secret of the `module-signing` environment | builds of `main` and of release tags |

**The CI key is public.** Its private key is committed here on purpose, so a
build without access to any secret still produces a kernel that loads its own
modules. Anyone can sign a module with it. Never trust it on a real system, and
never ship an image signed with it.

`build-multiarch-images.yml` fails when the release key is missing, and when
the secret holds the CI key. It never falls back to the CI key. After each image
is pushed, `.github/scripts/check-module-signer.sh` checks that its vmlinuz
trusts the release certificate and not the CI one, and that every module is
signed with the release key. `PR_multiarch.yml` runs the same check against the
CI key.

The riscv64 kernel configs do not set `CONFIG_MODULE_SIG`, so riscv64 needs no
key. Its jobs in `build-multiarch-images.yml` run outside the `module-signing`
environment and pass neither the secret nor `MODULE_SIGNING_CERT_FPR`; the
Dockerfile records the riscv64 kernel as unsigned and installs no key.
`make test-module-signing` fails if a riscv64 config starts signing modules
before those jobs get the key.

## How the key gets into the build

The Dockerfile reads the key from the BuildKit secret `module-signing-key`. It
is copied into the kernel tree at the start of each kernel build step that needs
it and deleted at the end of that step, so it is in no image layer and in no
build cache. Without the secret the build uses the CI key.

A secret is not part of the BuildKit cache key. The build arg
`MODULE_SIGNING_CERT_FPR`, the sha256 of the key's certificate, is: a kernel
signed with one key is never taken from the cache for a build that asks for
another. Its default is the fingerprint of the CI key. The kernel build checks
that the key it got matches the fingerprint and fails if it does not.

```
sh files/kernel/module-signing/module-signing-key.sh fingerprint KEY.pem
```

Locally:

```
make build-hadron                                  # CI key
make build-hadron MODULE_SIGNING_KEY=/path/key.pem # your own key
```

## Making the release key

The key and its certificate go into one PEM file, the layout kbuild expects.
`x509.genkey` here is the kernel's own `certs/default_x509.genkey`, with another
name. Use it with a name of your own:

```
sed 's/^CN = .*/CN = Hadron kernel module signing key/' \
  files/kernel/module-signing/x509.genkey > release.genkey
openssl req -new -nodes -utf8 -sha512 -days 36500 -batch -x509 \
  -config release.genkey -outform PEM \
  -out module-signing-key.pem -keyout module-signing-key.pem
sh files/kernel/module-signing/module-signing-key.sh check module-signing-key.pem
```

The key is RSA 4096, as `CONFIG_MODULE_SIG_KEY_TYPE_RSA` in the configs says,
and must not be encrypted. Keep a copy somewhere safe: modules built outside
this repository against a released kernel, for example in a system extension,
need a key the kernel trusts, and this is the one its builtin keyring holds.

Then create the environment, allow only `main` and release tags to use it, and
store the key in it:

```
gh api -X PUT repos/kairos-io/hadron/environments/module-signing \
  -F 'deployment_branch_policy[protected_branches]=false' \
  -F 'deployment_branch_policy[custom_branch_policies]=true'
gh api -X POST repos/kairos-io/hadron/environments/module-signing/deployment-branch-policies \
  -f name=main -f type=branch
gh api -X POST repos/kairos-io/hadron/environments/module-signing/deployment-branch-policies \
  -f name='v*' -f type=tag
gh secret set MODULE_SIGNING_KEY --env module-signing --repo kairos-io/hadron \
  < module-signing-key.pem
```

## Changing a key

A new release key changes the fingerprint, so the next `main` build compiles the
kernels again. That is the intent. A new CI key needs the new fingerprint as the
default of `MODULE_SIGNING_CERT_FPR` in the Dockerfile; `make test-module-signing`
fails until the two agree.
