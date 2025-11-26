---
title: "Boot Architecture"
linkTitle: "Boot Architecture"
weight: 3
description: |
    Bootloader configurations and boot process in Hadron
---

Hadron supports two bootloader configurations, each optimized for different use cases. The choice of bootloader affects the boot process, security capabilities, and system requirements.

## GRUB Bootloader

GRUB is the default bootloader for Hadron, providing traditional boot capabilities with broad hardware compatibility.

### GRUB Features

**BIOS and UEFI Support**

GRUB supports both legacy BIOS and modern UEFI firmware:

- Works on older hardware without UEFI
- Supports UEFI Secure Boot (with appropriate keys)
- Compatible with a wide range of systems
- Flexible boot configuration

**Boot Configuration**

GRUB provides:

- Flexible boot menu configuration
- Kernel parameter customization
- Rescue mode capabilities
- Boot from network or local storage

**Hardware Compatibility**

GRUB's mature codebase ensures:

- Broad hardware support
- Compatibility with various storage controllers
- Support for different filesystem types
- Reliable boot on diverse hardware

### Initramfs with dracut

When using GRUB, Hadron includes [dracut](https://github.com/dracut-ng/dracut-ng) for initramfs generation. dracut creates a minimal initial ramdisk that:

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

### GRUB Build Process

GRUB is built with:

- Support for both BIOS and UEFI platforms
- Minimal module set (only essential modules)
- Optimized binary size
- Compatibility with musl-based systems

The build system produces separate GRUB images for BIOS and UEFI, allowing Hadron to boot on either platform.

## systemd-boot (Trusted Boot)

For systems requiring trusted boot capabilities, Hadron supports systemd-boot with Unified Kernel Images (UKI).

### systemd-boot Features

**Modern UEFI Bootloader**

systemd-boot is a lightweight UEFI bootloader that:

- Integrates with systemd ecosystem
- Supports Unified Kernel Images
- Provides simple, predictable boot process
- Eliminates need for separate initramfs

**Unified Kernel Images (UKI)**

UKI combines kernel, initramfs, and boot configuration into a single EFI executable:

- Single file contains all boot components
- Easier to sign and verify
- Simpler boot process
- Better integration with Secure Boot

### Trusted Boot Capabilities

With systemd-boot, Hadron supports:

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

### systemd-boot Build Process

systemd-boot is built separately from the main systemd build due to musl's limitations with wchar_t definitions. The build process:

- Compiles systemd-boot EFI binaries
- Generates UKI stub files
- Includes SBAT (Secure Boot Advanced Targeting) information
- Produces EFI executables for boot

The EFI binaries are then merged into the final image at `/usr/lib/systemd/boot/efi/`.

### UKI Generation

When using systemd-boot, the build system can generate UKI images that combine:

- Linux kernel (vmlinuz)
- Initramfs (if needed)
- systemd stub
- Boot configuration
- Certificates and signatures

This single EFI executable simplifies the boot process and enables trusted boot scenarios.

## Boot Process Comparison

### GRUB Boot Process

1. Firmware loads GRUB from EFI system partition or MBR
2. GRUB reads configuration and displays boot menu
3. GRUB loads kernel and initramfs
4. Kernel starts, initramfs is mounted
5. dracut in initramfs discovers hardware and mounts root
6. System switches to root filesystem
7. systemd takes over as PID 1

### systemd-boot Boot Process

1. Firmware loads systemd-boot from EFI system partition
2. systemd-boot loads Unified Kernel Image
3. UKI contains kernel and (optional) initramfs
4. Kernel starts directly, or with embedded initramfs
5. systemd takes over as PID 1
6. Simpler, more direct boot path

## Choosing a Bootloader

**Use GRUB when:**

- You need BIOS support
- You want flexible boot configuration
- You need rescue mode capabilities
- You're using traditional hardware

**Use systemd-boot when:**

- You require trusted boot capabilities
- You want Secure Boot support
- You need TPM integration
- You're building secure, immutable systems
- You're using modern UEFI-only hardware

## Boot Configuration

Both bootloaders support configuration customization:

**GRUB Configuration**

- Modify `/etc/default/grub` for boot parameters
- Customize `/boot/grub/grub.cfg` for menu entries
- Add kernel parameters for specific use cases

**systemd-boot Configuration**

- Configure via systemd-boot loader entries
- Set kernel parameters in loader entries
- Customize UKI generation parameters

## Integration with Kairos

When used with [Kairos](https://kairos.io), both bootloaders gain additional capabilities:

- **A/B partition management**: Automatic partition switching for upgrades
- **Boot assessment**: Automatic rollback on boot failure
- **Image-based updates**: Seamless integration with container image updates
- **Trusted boot workflows**: Full trusted boot chain with Kairos

See the [Kairos documentation](https://kairos.io) for details on using Hadron bootloaders with Kairos lifecycle management.

## See Also

- [Core Components](/docs/architecture/core-components/) - Kernel and systemd details
- [Build System](/docs/architecture/build-system/) - How bootloaders are built
- [Kairos](https://kairos.io) - Lifecycle management with Hadron bootloaders

