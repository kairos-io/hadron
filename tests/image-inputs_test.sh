#!/bin/sh
#
# Keeps .github/scripts/image-inputs.sh honest. That script decides which pull
# requests skip the image build, so a path it wrongly skips is an image change
# nobody builds. This test checks it against what the build really reads:
#
#   1. a table of paths with the answer each must get,
#   2. every local source the Dockerfile COPYs, ADDs or bind mounts,
#   3. every repository path PR_multiarch.yml refers to,
#   4. that the variants the skip list assumes a pull request never builds
#      (arm64, riscv64, the cloud kernel, FIPS) are still not built by it.
#
# It needs no docker daemon and no network.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

filter=.github/scripts/image-inputs.sh
workflow=.github/workflows/PR_multiarch.yml
fail=0

verdict() {
	printf '%s\n' "$1" | sh "$filter"
}

expect() { # expect <true|false> <path>
	got=$(verdict "$2")
	if [ "$got" != "$1" ]; then
		echo "FAIL: $2 gives $got, want $1" >&2
		fail=1
	fi
}

# ---- 1. The table.
for p in Dockerfile sources.yaml .dockerignore files/pam/sshd files/post-install/pam.sh \
	files/kernel/default.config patches/0001-make-getopt-gcc15.patch \
	hack/gen-manifests.sh hack/gen-components.sh hack/render.sh hack/list-missing-sources.sh \
	.github/workflows/PR_multiarch.yml .github/workflows/populate-sources.yml \
	.github/actions/render-dockerfile/action.yml .github/scripts/image-size-report.sh \
	.github/scripts/image-inputs.sh \
	tests/acceptance_test.go tests/go.mod tests/assets/keys/db.pem tests/gcc/test.c \
	a-new-top-level-dir/file; do
	expect true "$p"
done
for p in README.md DEV.md docs/src/index.md examples/hetzner-cloud/Dockerfile updatecli.d/core-system.yaml \
	.github/workflows/quick-checks.yml .github/workflows/autobumper.yml .github/scripts/bump-pr-action.sh \
	.github/CODEOWNERS hack/check-patch-headers.sh hack/gen-manifests_shipped_test.sh \
	tests/make-helpers.sh tests/autobumper-changelog_test.rb Makefile renovate.json \
	files/kernel/cloud.config files/kernel/default-arm64.config files/kernel/cloud-riscv64.config \
	files/openssl/openssl.cnf.fips; do
	expect false "$p"
done
# One file that needs the image outweighs any number that do not.
if [ "$(printf 'docs/a.md\nMakefile\nfiles/login.defs\n' | sh "$filter")" != true ]; then
	echo "FAIL: a mixed list must build" >&2
	fail=1
fi
if [ "$(printf '' | sh "$filter")" != false ]; then
	echo "FAIL: an empty list must not build" >&2
	fail=1
fi

# Files the Dockerfile reads only in variants a pull request does not build.
variant_only="files/kernel/cloud.config files/kernel/cloud-arm64.config
files/kernel/default-arm64.config files/kernel/cloud-riscv64.config
files/kernel/default-riscv64.config files/openssl/openssl.cnf.fips
files/ssh/sshd_config.d/02-hadron-fips.conf"

# Print every file below a path or glob, one per line.
files_of() {
	set -f
	for entry in $1; do
		set +f
		# shellcheck disable=SC2086 # the glob is meant to expand
		for m in $entry; do
			if [ -d "$m" ]; then
				find "$m" -type f
			elif [ -e "$m" ]; then
				echo "$m"
			fi
		done
		set -f
	done
	set +f
}

# ---- 2. What the Dockerfile reads from the build context.
sources=$(
	{
		grep -E '^[[:space:]]*(COPY|ADD)[[:space:]]' Dockerfile |
			grep -v -- '--from' | grep -v '<<' |
			while read -r _ args; do
				set -f
				# shellcheck disable=SC2086
				set -- $args
				while [ $# -gt 1 ]; do
					case "$1" in
					--* | http://* | https://*) ;;
					*) echo "${1#./}" ;;
					esac
					shift
				done
			done
		grep -oE 'type=bind,source=[^, ]+' Dockerfile | sed 's/^type=bind,source=//'
	} | sort -u
)
[ -n "$sources" ] || {
	echo "FAIL: found no local sources in Dockerfile" >&2
	fail=1
}
for src in $sources; do
	found=0
	for f in $(files_of "$src"); do
		found=1
		case " $(echo $variant_only) " in
		*" $f "*) expect false "$f" ;;
		*) expect true "$f" ;;
		esac
	done
	if [ "$found" = 0 ]; then
		echo "FAIL: Dockerfile reads $src and nothing matches it" >&2
		fail=1
	fi
done

# ---- 3. What PR_multiarch.yml refers to.
refs=$(
	grep -oE '(hack|\.github/scripts|\.github/actions|tests)/[A-Za-z0-9_./*-]+' "$workflow" |
		sed 's/[.:,]*$//' | sort -u
)
for ref in $refs; do
	case "$ref" in
	tests/\*\*/logs/\*) continue ;; # the failure artifact path, not an input
	esac
	for f in $(files_of "$ref"); do
		# check-kernel-configs calls quick-checks.yml, which always runs.
		expect true "$f"
	done
done

# ---- 4. The pull request pipeline still builds only what the skip list assumes.
# Comments are dropped first: they may mention the variants main builds.
if sed 's/#.*$//' "$workflow" |
	grep -nE 'linux/arm64|riscv64|KERNEL_TYPE=cloud|FIPS=fips|"(fips|cloud)"|[^o]-fips-|-cloud[-"]' >&2; then
	echo "FAIL: $workflow now builds a variant that $filter assumes it does not." >&2
	echo "      Remove the 'variants main builds' arm from $filter." >&2
	fail=1
fi

if [ "$fail" = 0 ]; then
	echo "ok: $filter agrees with the Dockerfile and $workflow"
fi
exit "$fail"
