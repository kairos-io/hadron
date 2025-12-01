---
title: "Boot Architecture"
linkTitle: "Boot Architecture"
weight: 3
description: |
    Boot modes and boot process in Hadron
---

Hadron supports two boot modes, each optimized for different use cases. The choice of boot mode affects hardware compatibility, security capabilities, and system requirements.

## Standard Boot (BIOS)

Standard Boot provides compatibility with legacy BIOS systems. This boot mode works on older hardware that uses traditional BIOS firmware rather than modern UEFI.

### BIOS Compatibility

Standard Boot supports legacy BIOS firmware:

- Works on systems with BIOS firmware (UEFI systems not supported)
- Compatible with a wide range of legacy systems
- Supports traditional boot configurations
- Reliable boot on BIOS-based hardware

**Hardware Compatibility**

Standard Boot ensures:

- Broad hardware support on BIOS systems
- Compatibility with various storage controllers
- Support for different filesystem types
- Reliable boot on legacy hardware platforms

### Boot Configuration

Standard Boot provides:

- Flexible boot menu configuration
- Kernel parameter customization
- Rescue mode capabilities
- Boot from network or local storage

### Initramfs with dracut

Standard Boot includes [dracut](https://github.com/dracut-ng/dracut-ng) for initramfs generation. dracut creates a minimal initial ramdisk that:

**Early Boot Tasks**

- Discovers hardware devices
- Loads necessary kernel modules
- Mounts the root filesystem
- Handles encrypted partitions
- Sets up network for network boot scenarios

**Minimal Footprint**

dracut is configured to create a minimal initramfs:

- Includes only essential modules
- Uses compression to reduce size
- Optimized for fast boot times
- Supports various root filesystem types

**Integration with systemd**

dracut integrates with systemd in the initramfs:

- Uses systemd as the init process
- Leverages systemd's service management
- Provides systemd units for early boot
- Enables systemd features in initramfs

### Implementation Details

Standard Boot uses GRUB as the bootloader. The build system produces BIOS images for legacy hardware platforms.

## Trusted Boot (UEFI Secure Boot)

Trusted Boot enables secure boot capabilities on UEFI systems with Secure Boot enabled. This boot mode provides a chain of trust from firmware to kernel, protecting against boot-time attacks and enabling advanced security features.

### UEFI Secure Boot Support

Trusted Boot requires UEFI firmware with Secure Boot enabled:

- Requires UEFI firmware (BIOS systems not supported)
- EFI executable signing and verification
- Chain of trust from firmware to kernel
- Protection against boot-time attacks

### Unified Kernel Images (UKI)

Trusted Boot uses Unified Kernel Images that combine kernel, initramfs, and boot configuration into a single EFI executable:

- Single file contains all boot components
- Easier to sign and verify
- Simpler boot process
- Better integration with Secure Boot

### Trusted Boot Capabilities

With Trusted Boot, Hadron supports:

**Secure Boot**

- EFI executable signing
- Verification of boot components
- Chain of trust from firmware to kernel
- Protection against boot-time attacks

**TPM-Based Measurements**

- PCR (Platform Configuration Register) measurements
- Boot integrity verification
- Attestation of boot state
- Integration with encrypted storage

**PCR Policies**

- Encrypted partition unlocking based on PCR values
- Secure storage key management
- Protection against boot-time tampering
- Integration with systemd-cryptsetup

**Boot Assessment**

- Automatic boot success/failure detection
- Integration with A/B upgrade systems
- Automatic rollback on boot failure
- Boot state tracking

### Implementation Details

Trusted Boot uses systemd-boot as the bootloader with Unified Kernel Images. The build process compiles systemd-boot EFI binaries, generates UKI stub files, includes SBAT (Secure Boot Advanced Targeting) information, and produces EFI executables for boot. The EFI binaries are merged into the final image at `/usr/lib/systemd/boot/efi/`.

### UKI Generation

When using Trusted Boot, the build system generates UKI images that combine:

- Linux kernel (vmlinuz)
- Initramfs (if needed)
- systemd stub
- Boot configuration
- Certificates and signatures

This single EFI executable simplifies the boot process and enables trusted boot scenarios.

## Choosing a Boot Mode

**Use Standard Boot (BIOS) when:**

- You need BIOS support for legacy hardware
- You're using systems with traditional BIOS firmware
- You need flexible boot configuration
- You need rescue mode capabilities
- You're deploying on older hardware platforms

**Use Trusted Boot (UEFI Secure Boot) when:**

- You require Secure Boot support
- You need trusted boot capabilities
- You want TPM integration
- You're building secure, immutable systems
- You're using modern UEFI hardware with Secure Boot enabled

## Boot Configuration

Both boot modes support configuration customization:

**Standard Boot Configuration**

- Modify `/etc/default/grub` for boot parameters
- Customize `/boot/grub/grub.cfg` for menu entries
- Add kernel parameters for specific use cases

**Trusted Boot Configuration**

- Configure via systemd-boot loader entries
- Set kernel parameters in loader entries
- Customize UKI generation parameters

## Integration with Kairos

When used with [Kairos](https://kairos.io), both boot modes gain additional capabilities:

- **A/B partition management**: Automatic partition switching for upgrades
- **Boot assessment**: Automatic rollback on boot failure
- **Image-based updates**: Seamless integration with container image updates
- **Trusted boot workflows**: Full trusted boot chain with Kairos

See the [Kairos documentation](https://kairos.io) for details on using Hadron boot modes with Kairos lifecycle management.

## See Also

- [Core Components](/docs/architecture/core-components/) - Kernel and systemd details
- [Build System](/docs/architecture/build-system/) - How boot modes are built
- [Kairos](https://kairos.io) - Lifecycle management with Hadron boot modes
