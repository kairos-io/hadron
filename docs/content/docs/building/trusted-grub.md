---
title: "Trusted Boot or Grub?"
weight: 4
---

Hadron's default build configuration produces a **Trusted Boot** image with Secure Boot support. This is the recommended configuration for production deployments.

### What is Trusted Boot?

Trusted Boot provides:
- **Secure Boot**: EFI files are cryptographically signed
- **Measured Boot**: TPM2 measurements of the boot process, kernel, initrd
- **USI (Unified System Image)**: Single signed EFI file containing kernel, initrd, cmdline and rootfs
- **User data partitions encrypted by default**: Partitions are encrypted based of the measurements of all system components

### Building Trusted Boot Images

The default build already uses Trusted Boot:

```bash
# These are equivalent (systemd is the default)
make build
make build BOOTLOADER=systemd
```

Both commands build the OCI images and create a Trusted Boot ISO.

To create just the Trusted Boot ISO (after OCI images are built):

```bash
make trusted-iso
# or
make build-iso BOOTLOADER=systemd
```

### Trusted Boot Requirements

1. **Keys**: You need the following Secure Boot and TPM sign keys in the `KEYS_DIR` directory:
   - `tpm2-pcr-private.pem`: Used to sign the measurements of the components that make up the EFI file.
   - `db.key` and `db.pem`: Used to sign the EFI file itself.
   - `db.auth`, `KEK.auth`, `PK.auth`: Public keys that have to be added to the EFI firmware for the secure chain to work

2. **Hardware**: The target system must support:
   - UEFI firmware in Setup mode
   - Secure Boot capability
   - TPM2 (for measured boot)


You can read more about what the Secure Boot keys mean and what `Setup Mode` mens in the [UEFI Spec version 2.11 section 32.3](https://uefi.org/sites/default/files/resources/UEFI_Spec_Final_2.11.pdf#section.32.3)

### Trusted Boot Key Management

**⚠️ Security Warning**: The default keys in `tests/assets/keys/` are **INSECURE** and for testing only.

For production, generate your own keys:

```bash
# Generate your own Secure Boot keys
# (Use your preferred method for key generation)

# Then build with your keys
make trusted-iso KEYS_DIR=/path/to/your/secure/keys
```

# Non-Trusted Boot (GRUB)

For systems that don't support Secure Boot or when you need traditional GRUB-based booting, Hadron can be built with GRUB and dracut.

### Building GRUB Images

```bash
# Build everything with GRUB bootloader
make build BOOTLOADER=grub
```

This builds the OCI images with GRUB configuration and creates a GRUB ISO.

To build just the GRUB ISO (after OCI images are built):

```bash
make grub-iso
# or
make build-iso BOOTLOADER=grub
```

### GRUB vs Trusted Boot

| Feature | Trusted Boot (systemd) | GRUB Boot |
|---------|------------------------|-----------|
| Secure Boot | ✅ Yes | ⚠️ Not in Hadron |
| Measured Boot | ✅ Yes | ❌ No |
| Bootloader | [systemd-boot](https://www.freedesktop.org/software/systemd/man/latest/systemd-boot.html) | [GRUB](https://www.gnu.org/software/grub/manual/grub/grub.html) |
| Initrd | [Immucore](https://github.com/kairos-io/immucore) | [Dracut](https://dracut-ng.github.io/dracut-ng/) |
| UEFI Required | ✅ Yes | ⚠️ Recommended |
| Legacy BIOS | ❌ No | ✅ Yes |

### When to Use GRUB

Use GRUB boot when:
- Target hardware doesn't support Secure Boot
- You need legacy BIOS compatibility
- You prefer traditional boot methods
- You're testing or developing

## GRUB and Secure Boot in Hadron

While GRUB can technically be signed to work under Secure Boot, Hadron does not currently provide automated tooling to sign GRUB, the kernel, and kernel modules for Secure Boot compatibility.

### Current State

The default GRUB build in Hadron produces **unsigned** binaries that will not work with Secure Boot enabled.

### Signing GRUB for Secure Boot

If you need GRUB to work with Secure Boot enabled, you would need to:

1. **Sign GRUB itself**: Sign the GRUB EFI binary with your Secure Boot keys
2. **Sign the kernel**: Sign the Linux kernel with your Secure Boot keys
3. **Sign kernel modules**: Sign all kernel modules that are loaded during boot

This signing process is **not automated** in Hadron's build system. If you require GRUB with Secure Boot support, you would need to:

- Implement your own signing workflow
- Use external tooling to sign the binaries after the build
- Manually sign the required files before deployment

### Recommendation

For Secure Boot requirements, we recommend using the **Trusted Boot** configuration (default), which uses systemd-boot and provides automated signing of all boot components through the `trusted-iso` target. This is the supported and tested path for Secure Boot in Hadron.

If you specifically need GRUB with Secure Boot, you'll need to handle the signing process yourself, as this functionality is not currently provided by Hadron's tooling.
