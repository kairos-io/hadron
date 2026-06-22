# Updatecli Configuration

This directory contains Updatecli configuration files that replace the legacy Bumpfile for automated dependency updates.

## Structure

The configuration is organized into logical groups:

- **compression-tools.yaml** - Compression utilities and libraries
  - curl, rsync, xxhash, zstd, lz4, zlib, xzutils, gzip

- **system-libraries.yaml** - System-level libraries
  - acl, attr, libcap, libmnl, libnftnl, seccomp, libffi, libaio, dbus, expat, popt, libxml2, jsonc, fts, libelf, libiconv, pcre2, libkcapi

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
  - python, sqlite3, tpm2-tss, pax-utils, ca-certificates, aports, gdb, bc, patch

- **vm-tools.yaml** - Virtualization / guest agent tools
  - qemu, glib, open-vm-tools, mspack

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

### Bash Patch Level
Bash uses two Updatecli values in `/home/runner/work/hadron/hadron/Dockerfile`: `BASH_VERSION` and `PATCH_LEVEL`.
`BASH_VERSION` comes from upstream tags, while `PATCH_LEVEL` is derived by parsing the upstream Bash patch directory for the selected minor version and taking the highest available patch number.

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

The autobumper workflow enriches dependency bump PRs with changelog context. The
logic lives in [`.github/scripts/autobumper-changelog.rb`](../.github/scripts/autobumper-changelog.rb),
which reads the staged Dockerfile diff together with the manifest referenced by
`UPDATECLI_MANIFEST` and writes the PR title, commit message and body.

For every bumped dependency the PR body shows the version change plus, depending
on where the source is hosted:

- **GitHub** (`githubrelease`, or any `gittag` whose `spec.url` points at
  `github.com`): the matching GitHub release link and a truncated excerpt of its
  release notes (folded in a `<details>` block), **plus** a
  `…/compare/<old_tag>...<new_tag>` link. The compare link is always included so
  major-version diffs are one click away even when a repository only tags and
  does not publish releases.
- **GitLab** (any `gittag`/`gitlab` source whose URL points at a `gitlab*` host):
  a best-effort release-notes excerpt from the GitLab API (public projects need
  no token) and a `…/-/compare/<old_tag>...<new_tag>` link.
- **Everything else** (cgit hosts, other forges, `shell` and `http` sources):
  the links taken from the optional `changelog` hint on the source (see below).
- When none of the above apply, the body falls back to the upstream source URL
  and notes that release notes are unavailable for that source type.

Because GitHub and GitLab coordinates are derived directly from `spec.url`, any
new `gittag` source added on those forges gets changelog links for free with no
extra configuration.

### Changelog hints

Sources that cannot be auto-derived (Savannah/GNU cgit, kernel.org, netfilter,
sourceware, pagure, and `shell`/`http` sources) can attach an optional
source-level `changelog` block. Updatecli ignores the extra key; only the
enrichment script reads it:

```yaml
sources:
  grep:
    kind: gittag
    spec:
      url: git://git.git.savannah.gnu.org/grep.git
    transformers:
      - trimprefix: v
    changelog:
      url: https://git.savannah.gnu.org/cgit/grep.git/tree/NEWS
      compare: "https://git.savannah.gnu.org/cgit/grep.git/diff/?id={new_tag}&id2={old_tag}"
```

Supported fields:

- `url` — link to the upstream changelog / NEWS / release page.
- `compare` — link to a tag-to-tag diff. Omit it for `shell`/`http` sources whose
  upstream tags cannot be reconstructed reliably.
- `forge`, `owner`, `repository`, `host`, `path` — force GitHub/GitLab handling
  (release-notes lookup + compare links) for a source whose `spec.url` does not
  expose those coordinates.

The `url` and `compare` templates support the placeholders `{old}` / `{new}`
(the Dockerfile versions) and `{old_tag}` / `{new_tag}` (the upstream git tags,
reconstructed by reversing the source `transformers`).

This keeps PRs compact while still surfacing a changelog link — or a real
release-notes excerpt — for essentially every source.
