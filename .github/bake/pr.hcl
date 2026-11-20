# Bake definition for the pull request image build (proposed: .github/bake/pr.hcl).
#
# One `docker buildx bake pr` runs every target below in ONE BuildKit session.
# BuildKit gives a vertex that appears in more than one target a single
# execution, so the kernel, systemd, python and the rest of the common graph
# are built once instead of once per job. The graph is the same one the staged
# jobs build today:
#
#   container       Dockerfile target `container`      (hadron-container-amd64)
#   container-test  Dockerfile target `container-test` (RUN smoke checks)
#   bios            Dockerfile target `default`, BOOTLOADER=grub
#   trusted         Dockerfile target `default`, BOOTLOADER=systemd
#   toolchain       Dockerfile target `toolchain`      (built, never exported)
#
# bios, trusted and toolchain differ from container only in their last few
# stages, so adding them costs the stages that are not shared, not a second
# copy of the build.
#
# Reads from the shared cache that build-multiarch-images.yml writes on main.
# Nothing is written by default: a fork pull request has no registry secrets.
# Set CACHE_TO_PREFIX (an in-repo pull request opting in) to also export the
# result of container, bios and trusted under <prefix><name> and to read those
# tags back on the next push.
#
# Build args are the ones the staged jobs pass today (KERNEL_TYPE=default and
# FIPS=no-fips are the Dockerfile defaults, spelled out so a change of default
# cannot silently change what a pull request builds). SOURCE_DATE_EPOCH comes
# from the environment, as it does in every staged job.

variable "SHA" {
  # github.sha: the tags below are what build-kairos-*, structure-tests,
  # image-size-report-amd64 and component-versions-report-amd64 look up.
  default = "local"
}

variable "CACHE_REPO" {
  default = "quay.io/kairos/hadron-build-cache"
}

variable "CACHE_TO_PREFIX" {
  # "" (default): read main's cache only, export nothing.
  # "pr-123-":   also export pr-123-container-amd64 and friends, and import them.
  default = ""
}

# Main cache tags a pull request may use. Importing a tag costs its manifest and
# config (each capped at 1 MiB by BuildKit, cache/remotecache/import.go) and
# about a second; layers are only pulled for the steps that need them.
# Listed from the coarse stage tags to the per-image tags so that one stale or
# oversize tag (on 2026-11-19 the config of trusted-default-no-fips-amd64 was
# within 1% of the 1 MiB cap) leaves the others to serve the same steps.
# The fips, cloud, arm64 and riscv64 tags never match this build and are left
# out.
variable "MAIN_CACHE_TAGS" {
  default = [
    "stage0-amd64",
    "stage1-merge-amd64",
    "rsync-amd64",
    "cmake-amd64",
    "python-build-amd64",
    "systemd-amd64",
    "kernel-misc-default-amd64",
    "toolchain-amd64",
    "container-amd64",
    "bios-default-no-fips-amd64",
    "trusted-default-no-fips-amd64",
  ]
}

variable "PR_CACHE_NAMES" {
  default = [
    "container-amd64",
    "bios-default-no-fips-amd64",
    "trusted-default-no-fips-amd64",
  ]
}

function "cache_to" {
  params = [name]
  result = CACHE_TO_PREFIX == "" ? [] : [
    "type=registry,ref=${CACHE_REPO}:${CACHE_TO_PREFIX}${name},mode=max,ignore-error=true,compression=zstd,compression-level=3,oci-mediatypes=true,image-manifest=true"
  ]
}

target "_base" {
  context    = "."
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64"]
  cache-from = concat(
    CACHE_TO_PREFIX == "" ? [] : [for n in PR_CACHE_NAMES : "type=registry,ref=${CACHE_REPO}:${CACHE_TO_PREFIX}${n}"],
    [for t in MAIN_CACHE_TAGS : "type=registry,ref=${CACHE_REPO}:${t}"],
  )
}

target "container" {
  inherits = ["_base"]
  target   = "container"
  # Loaded into the runner's docker so the structure tests can `docker run` it.
  tags     = ["hadron-container-amd64:${SHA}"]
  output   = ["type=docker"]
  cache-to = cache_to("container-amd64")
}

target "container-test" {
  inherits = ["_base"]
  target   = "container-test"
  output   = ["type=cacheonly"]
}

target "bios" {
  inherits = ["_base"]
  target   = "default"
  args = {
    BOOTLOADER  = "grub"
    KERNEL_TYPE = "default"
    FIPS        = "no-fips"
  }
  tags     = ["hadron-amd64:${SHA}"]
  output   = ["type=docker"]
  cache-to = cache_to("bios-default-no-fips-amd64")
}

target "trusted" {
  inherits = ["_base"]
  target   = "default"
  args = {
    BOOTLOADER  = "systemd"
    KERNEL_TYPE = "default"
    FIPS        = "no-fips"
  }
  tags     = ["hadron-trusted-${SHA}:24h"]
  output   = ["type=docker"]
  cache-to = cache_to("trusted-default-no-fips-amd64")
}

# The toolchain image is not an output of a pull request: the staged job builds
# it only to prove that it still assembles. Nothing in the Dockerfile reads it.
# Against bios, trusted and container it adds six stages (bc, gzip,
# kernel-headers, kernel-misc, full-toolchain-merge, toolchain).
target "toolchain" {
  inherits = ["_base"]
  target   = "toolchain"
  output   = ["type=cacheonly"]
}

group "pr" {
  targets = ["container", "container-test", "bios", "trusted", "toolchain"]
}

group "default" {
  targets = ["pr"]
}
