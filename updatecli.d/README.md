# Updatecli Configuration

This directory contains Updatecli configuration files that replace the legacy Bumpfile for automated dependency updates.

## Structure

The configuration is organized into logical groups:

- **compression-tools.yaml** - Compression utilities and libraries
  - curl, rsync, xxhash, zstd, lz4, zlib, xzutils, gzip

- **system-libraries.yaml** - System-level libraries
  - acl, attr, libcap, libmnl, libnftnl, seccomp, libffi, libaio, dbus, expat, popt, libxml2, jsonc, fts

- **build-tools.yaml** - Build and development tools
  - flex, bison, autoconf, automake, libtool, cmake, make, m4, gawk, pkgconfig, binutils

- **core-system.yaml** - Core system components
  - musl, busybox, systemd, util-linux, coreutils, findutils, grep, gperf, diffutils, readline, bash

- **compiler-tools.yaml** - Compiler and language tools
  - gcc, gmp, mpc, mpfr, perl

- **security-tools.yaml** - Security-related packages
  - openssl, openssh, sudo, pam, shadow, cryptsetup

- **storage-tools.yaml** - Storage and filesystem tools
  - lvm2, multipath-tools, e2fsprogs, dosfstools, parted, urcu

- **kernel-and-boot.yaml** - Kernel and boot-related packages
  - kernel, kmod, dracut, grub, kbd

- **network-tools.yaml** - Network utilities
  - iptables, open-iscsi, strace

- **misc-tools.yaml** - Miscellaneous tools
  - python, sqlite3, tpm2-tss, pax-utils, ca-certificates, aports, gdb

## Usage

### Running Updatecli

To check for available updates:

```bash
updatecli diff
```

To apply updates:

```bash
updatecli apply
```

To run a specific configuration:

```bash
updatecli diff --config updatecli.d/compression-tools.yaml
```

### Environment Variables

Some configurations require environment variables:

- **GITHUB_TOKEN** - Better for for GitHub release sources (security-tools.yaml, system-libraries.yaml) to avoidhitting rate limits
  - Set this when running updatecli: `GITHUB_TOKEN=<your-token> updatecli diff`

### Source Types

The configurations use different source types based on the upstream:

1. **gittag** - For Git repositories with version tags
   - Example: `zstd`, `systemd`, `python`

2. **http** - For HTML pages with version links
   - Example: `curl`, `musl`, `gcc`

3. **githubrelease** - For GitHub releases API
   - Example: `expat`, `sudo`


For ease of use, github releases should be preferred as it usually provides changelogs and release notes, but it may require a `GITHUB_TOKEN` to avoid rate limits.
http sources are faster to query but can change their html structure without notice, so they should be used as a last resort.

Alos github releases will fgallback into the tags if there are no releases. For big repositories, this avoids the need to clone the repo locally as it uses
the github api. While this consumes api quota, its much more faster than using the gittag source which requires cloning the repo locally to get the tags.


### Targets

All targets update `ARG` instructions in the Dockerfile:

```yaml
targets:
  curl:
    name: CURL_VERSION in Dockerfile
    kind: dockerfile
    spec:
      file: Dockerfile
      instruction:
        keyword: ARG
        matcher: CURL_VERSION
    sourceid: curl
```

## Special Cases

### Kernel Version
The kernel version is extracted from the kernel.org finger banner:
```yaml
transformers:
  - findsubmatch:
      pattern: 'latest stable version of the Linux kernel.*?([0-9]+\.[0-9]+\.[0-9]+)'
      captureindex: 1
```


### GCC Version
Constrained to version 14:
```yaml
versionfilter:
  kind: semver
  constraint: '^14'
```

## Testing

Validate all configurations:

```bash
for file in updatecli.d/*.yaml; do
    echo "Validating $file"
    GITHUB_TOKEN=dummy updatecli manifest show --config "$file" > /dev/null
done
```

## CI/CD Integration

In CI/CD pipelines, ensure the `GITHUB_TOKEN` environment variable is set:

```yaml
- name: Check for updates
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: updatecli diff --config updatecli.d/
```
